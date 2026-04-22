function getBaseHref() {
  return document.querySelector('base')?.getAttribute('href') ?? '/';
}

function getPushServiceWorkerScope() {
  return `${getBaseHref()}push/`;
}

function getPushServiceWorkerUrl() {
  return `${getBaseHref()}push-sw.js`;
}

const pushServiceWorkerActivationTimeoutMs = 5000;
const pushSubscriptionTimeoutMs = 15000;
const pushPermissionTimeoutMs = 15000;

async function withTimeout(promise, timeoutMs, errorMessage) {
  let timeoutId;

  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => {
          reject(new Error(errorMessage));
        }, timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timeoutId);
  }
}

async function waitForServiceWorkerActivation(registration) {
  if (registration?.active) {
    return registration;
  }

  const worker = registration?.installing || registration?.waiting;
  if (!worker) {
    return null;
  }

  if (worker.state === 'activated') {
    return registration;
  }

  let timeoutId;

  try {
    await Promise.race([
      new Promise((resolve) => {
        worker.addEventListener('statechange', () => {
          if (worker.state === 'activated') {
            resolve();
          }
        });
      }),
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => {
          reject(new Error('Timed out waiting for service worker activation'));
        }, pushServiceWorkerActivationTimeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timeoutId);
  }

  return registration.active ? registration : null;
}

async function waitForActiveServiceWorkerRegistration(scope) {
  let timeoutId;

  try {
    const registration = await Promise.race([
      (async function waitForScopedRegistration() {
        while (true) {
          const scopedRegistration = await navigator.serviceWorker.getRegistration(
            scope,
          );
          if (scopedRegistration?.active) {
            return scopedRegistration;
          }

          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      })(),
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => {
          reject(new Error('Timed out waiting for active push service worker'));
        }, pushServiceWorkerActivationTimeoutMs);
      }),
    ]);

    if (registration?.active) {
      return registration;
    }
  } finally {
    clearTimeout(timeoutId);
  }

  return null;
}

async function getPushServiceWorkerRegistration() {
  const registrationScope = getPushServiceWorkerScope();
  const existingRegistration = await navigator.serviceWorker.getRegistration(
    registrationScope,
  );

  if (existingRegistration?.active) {
    console.log('Using existing active push service worker registration');
    return existingRegistration;
  }

  if (existingRegistration) {
    const activatedRegistration = await waitForServiceWorkerActivation(
      existingRegistration,
    );
    if (activatedRegistration) {
      console.log('Using newly activated push service worker registration');
      return activatedRegistration;
    }
  }

  console.log(
    `Registering dedicated push service worker for scope ${registrationScope}`,
  );

  const registration = await navigator.serviceWorker.register(
    getPushServiceWorkerUrl(),
    {
      scope: registrationScope,
      updateViaCache: 'none',
    },
  );
  const activatedRegistration = await waitForServiceWorkerActivation(
    registration,
  );

  if (activatedRegistration) {
    return activatedRegistration;
  }

  const readyRegistration = await waitForActiveServiceWorkerRegistration(
    registrationScope,
  );
  if (readyRegistration) {
    console.log('Using active push service worker registration from ready');
    return readyRegistration;
  }

  return Promise.reject('No active push service worker registration');
}

async function requestPushPermission() {
  if (!('Notification' in window)) {
    console.error('Notifications are not supported in this browser.');
    return 'unsupported';
  }

  if (Notification.permission !== 'default') {
    return Notification.permission;
  }

  console.log('Requesting notification permission from user gesture');
  return withTimeout(
    Notification.requestPermission(),
    pushPermissionTimeoutMs,
    'Timed out waiting for notification permission',
  );
}

async function registerPush(publicKey) {
  if (!('serviceWorker' in navigator)) {
    console.error('Service workers are not supported in this browser.');
    return null;
  };

  if (!('PushManager' in window)) {
    console.error('Push messaging is not supported in this browser.');
    return Promise.reject('Push manager is not available');
  }

  const permission = Notification.permission;
  console.log(`Current notification permission: ${permission}`);
  if (permission !== 'granted') {
    console.error('Notification permission must be granted before registering push.');
    return Promise.reject(`Notification permission is ${permission}`);
  }

  const activeRegistration = await getPushServiceWorkerRegistration();
  console.log('Using push service worker registration:', activeRegistration);

  if (!activeRegistration.pushManager) {
    console.error('Push manager is not available in this browser.');
    return Promise.reject('Push manager is not available');
  }

  let subscription = await activeRegistration.pushManager.getSubscription();
  if (!subscription) {
    console.log('Creating new push subscription');
    subscription = await withTimeout(
      activeRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(publicKey),
      }),
      pushSubscriptionTimeoutMs,
      'Timed out waiting for push subscription',
    );
  }

  if (!subscription) {
    console.error('Push subscription failed');
    return Promise.reject('Push subscription failed');
  }

  console.log('Push subscription successful:', subscription);

  return {
    endpoint: subscription.endpoint,
    keys: {
      p256dh: arrayBufferToBase64(subscription.getKey('p256dh')),
      auth: arrayBufferToBase64(subscription.getKey('auth')),
    }
  };    
}

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const output = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; ++i) {
    output[i] = raw.charCodeAt(i);
  }
  return output;
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = String.fromCharCode(...bytes);
  const base64 = btoa(binary);
  return base64
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, ''); // remove any padding
}

async function unregisterPush() {
  if (!('serviceWorker' in navigator)) {
    console.error('No service worker available.');
    return null;
  }

  const registration = await navigator.serviceWorker.getRegistration(
    getPushServiceWorkerScope(),
  );
  if (!registration) {
    console.log('No push service worker registration found.');
    return null;
  }

  const subscription = await registration.pushManager.getSubscription();
  if (!subscription) {
    console.log('No subscription to unsubscribe.');
    return null;
  }

  const endpoint = subscription.endpoint;
  const success = await subscription.unsubscribe();
  console.log('Unsubscribed:', success);

  return endpoint;
}
