import { describe, expect, it, vi } from 'vitest';

import { sendPushNotifications } from '../src/index';
import {
	buildEnv,
	buildPendingNotification,
	buildPushPayloadStub,
	FakePendingNotificationRepository,
} from './test-support/notify-worker-test-support';

describe('notify worker cleanup', () => {
	it('deletes stale subscriptions when the push provider returns 410', async () => {
		const repository = new FakePendingNotificationRepository([
			buildPendingNotification(),
		]);

		const fetchFn = vi.fn(async () => {
			return new Response('gone', { status: 410, statusText: 'Gone' });
		});

		const response = await sendPushNotifications(buildEnv(), 'test trigger', {
			repository,
			buildPushPayloadFn: buildPushPayloadStub,
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
