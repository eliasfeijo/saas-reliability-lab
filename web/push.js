async function registerPush(publicKey) {
  if (!('serviceWorker' in navigator)) return null;
  
  console.log('Registering push service worker');
  
  navigator.serviceWorker.register('/push-sw.js').then((registration) => {

    console.log('Push service worker registered');

    registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(publicKey),
    }).then((subscription) => {
      console.log('Push subscription successful:', subscription);
      return {
        endpoint: subscription.endpoint,
        keys: {
          p256dh: arrayBufferToBase64(subscription.getKey('p256dh')),
          auth: arrayBufferToBase64(subscription.getKey('auth')),
        }
      };
    }).catch((error) => {
      console.error('Push subscription failed:', error);
    });
  }).catch((error) => {
    console.error('Push service worker registration failed:', error);
    return null;
  });
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
