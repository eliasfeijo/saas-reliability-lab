import { describe, expect, it, vi } from 'vitest';

import { sendPushNotifications } from '../src/index';
import {
	buildEnv,
	buildPendingNotification,
	buildPushPayloadStub,
	FakePendingNotificationRepository,
} from './test-support/notify-worker-test-support';

describe('notify worker dispatch', () => {
	it('marks notifications as sent when the push provider accepts the request', async () => {
		const repository = new FakePendingNotificationRepository([
			buildPendingNotification(),
		]);

		const fetchFn = vi.fn(async () => {
			return new Response(null, { status: 201, statusText: 'Created' });
		});

		const response = await sendPushNotifications(buildEnv(), 'test trigger', {
			repository,
			buildPushPayloadFn: buildPushPayloadStub,
			fetchFn: fetchFn as typeof fetch,
		});

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			sent: 1,
			failed: 0,
			staleSubscriptionsDeleted: 0,
		});
		expect(repository.markedTaskIds).toEqual(['task-1']);
		expect(repository.deletedSubscriptions).toEqual([]);
		expect(fetchFn).toHaveBeenCalledTimes(1);
	});

	it('returns a no-op response when there are no pending notifications', async () => {
		const repository = new FakePendingNotificationRepository([]);
		const fetchFn = vi.fn();

		const response = await sendPushNotifications(buildEnv(), 'test trigger', {
			repository,
			buildPushPayloadFn: buildPushPayloadStub,
			fetchFn: fetchFn as typeof fetch,
		});

		expect(response.status).toBe(200);
		expect(await response.text()).toBe('No tasks to notify');
		expect(repository.markedTaskIds).toEqual([]);
		expect(repository.deletedSubscriptions).toEqual([]);
		expect(fetchFn).not.toHaveBeenCalled();
	});
});
