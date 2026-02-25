async function registerPush(publicKey) {
  if (!('serviceWorker' in navigator)) {
    console.error('Service workers are not supported in this browser.');
    return null;
  };

  console.log('Registering push service worker');

  const inRelease = self.isReleaseMode ?? true;

  // console.log('In release mode:', inRelease);

  const swFile = inRelease ? 'flutter_service_worker.js' : 'push-sw.js';

  const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/'
  const swPath = `${baseHref}${swFile}`;
  
  await navigator.serviceWorker.register(swPath);

  const registration = await navigator.serviceWorker.ready;
  if (!registration.pushManager) {
    console.error('Push manager is not available in this browser.');
    return Promise.reject('Push manager is not available');
  }

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(publicKey),
  });
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

  const registration = await navigator.serviceWorker.ready;
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
