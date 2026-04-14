import type {
	Env,
	PendingNotificationRepository,
} from '../../src/index';

export interface PendingNotificationRecord {
	id: string;
	title: string;
	user_id: string;
	endpoint: string;
	p256dh: string;
	auth: string;
}

export class FakePendingNotificationRepository
	implements PendingNotificationRepository
{
	readonly markedTaskIds: string[] = [];
	readonly deletedSubscriptions: Array<{ userId: string; endpoint: string }> = [];

	constructor(
		private readonly pendingNotifications: PendingNotificationRecord[],
	) {}

	async fetchPendingNotifications(_now: string): Promise<PendingNotificationRecord[]> {
		return this.pendingNotifications;
	}

	async markNotificationSent(taskId: string): Promise<void> {
		this.markedTaskIds.push(taskId);
	}

	async deleteSubscription(userId: string, endpoint: string): Promise<void> {
		this.deletedSubscriptions.push({ userId, endpoint });
	}
}

export function buildEnv(): Env {
	return {
		SUPABASE_URL: 'https://example.supabase.co',
		SUPABASE_SERVICE_ROLE: 'service-role-key',
		VAPID_PUBLIC_KEY: 'public-vapid-key',
		VAPID_PRIVATE_KEY: 'private-vapid-key',
	};
}

export function buildPendingNotification(
	overrides: Partial<PendingNotificationRecord> = {},
): PendingNotificationRecord {
	return {
		id: 'task-1',
		title: 'Renew passport',
		user_id: 'user-1',
		endpoint: 'https://push.example/subscription-1',
		p256dh: 'p256dh-key',
		auth: 'auth-key',
		...overrides,
	};
}

export const buildPushPayloadStub =
	(async () => ({
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
