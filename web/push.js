function getBaseHref() {
  return document.querySelector('base')?.getAttribute('href') ?? '/';
}

function isReleaseBuild() {
  return globalThis.isReleaseMode !== false;
}

function getPushServiceWorkerUrl() {
  const serviceWorkerFile = isReleaseBuild()
    ? 'flutter_service_worker.js'
    : 'push-sw.js';
  return `${getBaseHref()}${serviceWorkerFile}`;
}

const pushServiceWorkerActivationTimeoutMs = 5000;

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

async function waitForActiveServiceWorkerRegistration() {
  let timeoutId;

  try {
    const registration = await Promise.race([
      navigator.serviceWorker.ready,
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => {
          reject(new Error('Timed out waiting for active service worker'));
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
  if (isReleaseBuild()) {
    const readyRegistration = await waitForActiveServiceWorkerRegistration();
    if (readyRegistration) {
      console.log('Using active push service worker registration');
      return readyRegistration;
    }

    const existingRegistration = await navigator.serviceWorker.getRegistration(
      getBaseHref(),
    );
    if (existingRegistration?.active) {
      console.log('Using existing active push service worker registration');
      return existingRegistration;
    }

    return Promise.reject('No active push service worker registration');
  }

  const existingRegistration = await navigator.serviceWorker.getRegistration();
  if (existingRegistration?.active) {
    console.log('Using existing development push service worker registration');
    return existingRegistration;
  }

  console.log('Registering development push service worker');

  const registration = await navigator.serviceWorker.register(
    getPushServiceWorkerUrl(),
    { scope: getBaseHref() },
  );
  const activatedRegistration = await waitForServiceWorkerActivation(
    registration,
  );

  if (activatedRegistration) {
    return activatedRegistration;
  }

  return Promise.reject('No active push service worker registration');
}

async function requestPushPermission() {
  if (!('Notification' in window)) {
    console.error('Notifications are not supported in this browser.');
    return 'unsupported';
  }

  return Notification.requestPermission();
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

  const permission = await requestPushPermission();
  if (permission !== 'granted') {
    console.error('Notification permission was not granted.');
    return Promise.reject('Notification permission was not granted');
  }

  const activeRegistration = await getPushServiceWorkerRegistration();

  if (!activeRegistration.pushManager) {
    console.error('Push manager is not available in this browser.');
    return Promise.reject('Push manager is not available');
  }

  let subscription = await activeRegistration.pushManager.getSubscription();
  if (!subscription) {
    subscription = await activeRegistration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(publicKey),
    });
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
    getBaseHref(),
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
