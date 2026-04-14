import { describe, expect, it, vi } from 'vitest';

import {
	sendPushNotifications,
	type Env,
	type PendingNotificationRepository,
} from '../src/index';

describe('notify worker', () => {
	it('deletes stale subscriptions when the push provider returns 410', async () => {
		const repository = new FakePendingNotificationRepository([
			{
				id: 'task-1',
				title: 'Renew passport',
				user_id: 'user-1',
				endpoint: 'https://push.example/subscription-1',
				p256dh: 'p256dh-key',
				auth: 'auth-key',
			},
		]);

		const fetchFn = vi.fn(async () => {
			return new Response('gone', { status: 410, statusText: 'Gone' });
		});

		const buildPushPayloadFn = (async () => ({
			method: 'POST',
			headers: {
				'content-encoding': 'aes128gcm',
				'content-length': '0',
				'content-type': 'application/octet-stream',
				'crypto-key': 'test-crypto-key',
				encryption: 'salt=test-salt',
				ttl: '900',
				authorization: 'WebPush test',
			},
			body: new Uint8Array(),
		})) as typeof import('@block65/webcrypto-web-push').buildPushPayload;

		const response = await sendPushNotifications(buildEnv(), 'test trigger', {
			repository,
			buildPushPayloadFn,
			fetchFn: fetchFn as typeof fetch,
		});

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			sent: 0,
			failed: 1,
			staleSubscriptionsDeleted: 1,
		});
		expect(repository.markedTaskIds).toEqual([]);
		expect(repository.deletedSubscriptions).toEqual([
			{
				userId: 'user-1',
				endpoint: 'https://push.example/subscription-1',
			},
		]);
		expect(fetchFn).toHaveBeenCalledTimes(1);
	});
});

class FakePendingNotificationRepository implements PendingNotificationRepository {
	readonly markedTaskIds: string[] = [];
	readonly deletedSubscriptions: Array<{ userId: string; endpoint: string }> = [];

	constructor(private readonly pendingNotifications: Array<{
		id: string;
		title: string;
		user_id: string;
		endpoint: string;
		p256dh: string;
		auth: string;
	}>) {}

	async fetchPendingNotifications(): Promise<Array<{
		id: string;
		title: string;
		user_id: string;
		endpoint: string;
		p256dh: string;
		auth: string;
	}>> {
		return this.pendingNotifications;
	}

	async markNotificationSent(taskId: string): Promise<void> {
		this.markedTaskIds.push(taskId);
	}

	async deleteSubscription(userId: string, endpoint: string): Promise<void> {
		this.deletedSubscriptions.push({ userId, endpoint });
	}
}

function buildEnv(): Env {
	return {
		SUPABASE_URL: 'https://example.supabase.co',
		SUPABASE_SERVICE_ROLE: 'service-role-key',
		VAPID_PUBLIC_KEY: 'public-vapid-key',
		VAPID_PRIVATE_KEY: 'private-vapid-key',
	};
}
