function getBaseHref() {
  return document.querySelector('base')?.getAttribute('href') ?? '/';
}

function getPushServiceWorkerUrl() {
  return `${getBaseHref()}flutter_service_worker.js`;
}

async function getPushServiceWorkerRegistration() {
  const existingRegistration = await navigator.serviceWorker.getRegistration();
  if (existingRegistration) {
    console.log('Using existing push service worker registration');
    return existingRegistration;
  }

  console.log('Registering push service worker');

  const baseHref = getBaseHref();
  const registration = await navigator.serviceWorker.register(
    getPushServiceWorkerUrl(),
    { scope: baseHref },
  );

  return registration.active ? registration : await navigator.serviceWorker.ready;
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
