/**
 * Welcome to Cloudflare Workers! This is your first worker.
 *
 * - Run `npm run dev` in your terminal to start a development server
 * - Open a browser tab at http://localhost:8787/ to see your worker in action
 * - Run `npm run deploy` to publish your worker
 *
 * Bind resources to your worker in `wrangler.jsonc`. After adding bindings, a type definition for the
 * `Env` object can be regenerated with `npm run cf-typegen`.
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */

import {
	buildPushPayload,
	type PushSubscription,
} from "@block65/webcrypto-web-push";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export interface Env {
	SUPABASE_URL: string;
	SUPABASE_SERVICE_ROLE: string;
	VAPID_PUBLIC_KEY: string;
	VAPID_PRIVATE_KEY: string;
}

interface PendingNotification {
	id: string;
	title: string;
	user_id: string;
	endpoint: string;
	p256dh: string;
	auth: string;
}

export interface PendingNotificationRepository {
	fetchPendingNotifications(now: string): Promise<PendingNotification[]>;
	markNotificationSent(taskId: string): Promise<void>;
	deleteSubscription(userId: string, endpoint: string): Promise<void>;
}

class SupabasePendingNotificationRepository
	implements PendingNotificationRepository
{
	constructor(private readonly supabase: SupabaseClient) {}

	async fetchPendingNotifications(now: string): Promise<PendingNotification[]> {
		const { data: tasks, error } = await this.supabase.rpc(
			"get_pending_notifications",
			{ now },
		);

		if (error) {
			throw error;
		}

		return (tasks ?? []) as PendingNotification[];
	}

	async markNotificationSent(taskId: string): Promise<void> {
		const { error } = await this.supabase
			.from("tasks")
			.update({ notification_sent: true })
			.eq("id", taskId);

		if (error) {
			throw error;
		}
	}

	async deleteSubscription(userId: string, endpoint: string): Promise<void> {
		const { error } = await this.supabase
			.from("push_subscriptions")
			.delete()
			.eq("user_id", userId)
			.eq("endpoint", endpoint);

		if (error) {
			throw error;
		}
	}
}

type BuildPushPayloadFn = typeof buildPushPayload;
type FetchFn = typeof fetch;

export interface NotifyWorkerDeps {
	repository?: PendingNotificationRepository;
	buildPushPayloadFn?: BuildPushPayloadFn;
	fetchFn?: FetchFn;
}

export async function sendPushNotifications(
	env: Env,
	trigger: string,
	deps: NotifyWorkerDeps = {},
): Promise<Response> {
	if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE) {
		return new Response("Environment variables not set", { status: 500 });
	}
	if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) {
		return new Response("VAPID keys not set", { status: 500 });
	}

	const repository =
		deps.repository ??
		new SupabasePendingNotificationRepository(
			createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE),
		);
	const buildPushPayloadFn = deps.buildPushPayloadFn ?? buildPushPayload;
	const fetchFn = deps.fetchFn ?? fetch;

	const now = new Date().toISOString();
	console.log(`[notify-worker] Trigger=${trigger} now=${now}`);

	let tasks: PendingNotification[];
	try {
		tasks = await repository.fetchPendingNotifications(now);
	} catch (error) {
		console.error("Failed to fetch tasks:", error);
		return new Response("DB error", { status: 500 });
	}

	if (tasks.length === 0) {
		console.log("No tasks to notify");
		return new Response("No tasks to notify", { status: 200 });
	}

	console.log(`[notify-worker] Found ${tasks.length} pending task(s)`);

	// Log the number of successful notifications
	let count = 0;
	let failed = 0;
	let staleSubscriptionsDeleted = 0;

	for (const task of tasks) {
		try {
			const subscription: PushSubscription = {
				endpoint: task.endpoint,
				keys: {
					auth: task.auth,
					p256dh: task.p256dh,
				},
				expirationTime: null,
			};

			const message = {
				data: `⏰ ${task.title}`,
				options: { topic: "Task Reminder", ttl: 900, urgency: "high" as const },
			};

			const payload = await buildPushPayloadFn(message, subscription, {
				subject: "mailto:you@example.com",
				publicKey: env.VAPID_PUBLIC_KEY,
				privateKey: env.VAPID_PRIVATE_KEY,
			});

			const res = await fetchFn(subscription.endpoint, payload);

			if (!res.ok) {
				failed++;

				if (res.status === 404 || res.status === 410) {
					try {
						await repository.deleteSubscription(task.user_id, task.endpoint);
						staleSubscriptionsDeleted++;
					} catch (deleteError) {
						console.error(
							`Failed to delete stale subscription for ${task.user_id}:`,
							deleteError,
						);
					}
				}

				console.error(
					`Push failed for task ${task.id}: ${res.status} ${res.statusText}`,
				);
				continue;
			}

			await repository.markNotificationSent(task.id);

			console.log(
				`[notify-worker] Sent notification for task ${task.id} (${task.title})`,
			);

			count++;
		} catch (err) {
			failed++;
			console.error(`Push failed for task ${task.id}`, err);
		}
	}

	console.log(
		`[notify-worker] Run complete: sent=${count} failed=${failed} staleSubscriptionsDeleted=${staleSubscriptionsDeleted}`,
	);

	return new Response(
		JSON.stringify({ sent: count, failed, staleSubscriptionsDeleted }),
		{
			status: 200,
			headers: { "Content-Type": "application/json" },
		},
	);
}

export default {
	async fetch(
		request: Request,
		env: Env,
		ctx: ExecutionContext,
	): Promise<Response> {
		return sendPushNotifications(env, `fetch ${request.method}`);
	},

	async scheduled(
		controller: ScheduledController,
		env: Env,
		ctx: ExecutionContext,
	) {
		return sendPushNotifications(env, `cron ${controller.cron}`);
	},
};
