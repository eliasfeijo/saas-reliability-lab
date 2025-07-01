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
import { createClient } from "@supabase/supabase-js";

export interface Env {
	SUPABASE_URL: string;
	SUPABASE_SERVICE_ROLE: string;
	VAPID_PUBLIC_KEY: string;
	VAPID_PRIVATE_KEY: string;
}

async function sendPushNotifications(env: Env): Promise<Response> {
	if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE) {
		return new Response("Environment variables not set", { status: 500 });
	}
	if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY) {
		return new Response("VAPID keys not set", { status: 500 });
	}

	const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE);

	const now = new Date().toISOString();

	const { data: tasks, error } = await supabase.rpc(
		"get_pending_notifications",
		{ now },
	);

	if (error) {
		console.error("Failed to fetch tasks:", error);
		return new Response("DB error", { status: 500 });
	}

	if (!tasks || tasks.length === 0) {
		console.log("No tasks to notify");
		return new Response("No tasks to notify", { status: 200 });
	}

	// Log the number of successful notifications
	let count = 0;

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

			const payload = await buildPushPayload(message, subscription, {
				subject: "mailto:you@example.com",
				publicKey: env.VAPID_PUBLIC_KEY,
				privateKey: env.VAPID_PRIVATE_KEY,
			});

			const res = await fetch(subscription.endpoint, payload);

			if (!res.ok) {
				console.error(
					`Push failed for task ${task.id}: ${res.status} ${res.statusText}`,
				);
				continue;
			}

			await supabase
				.from("tasks")
				.update({ notification_sent: true })
				.eq("id", task.id);

			count++;
		} catch (err) {
			console.error(`Push failed for task ${task.id}`, err);
		}
	}

	return new Response(`${count} notifications sent`, { status: 200 });
}

export default {
	async fetch(
		request: Request,
		env: Env,
		ctx: ExecutionContext,
	): Promise<Response> {
		return sendPushNotifications(env);
	},

	async scheduled(
		controller: ScheduledController,
		env: Env,
		ctx: ExecutionContext,
	) {
		return sendPushNotifications(env);
	},
};
