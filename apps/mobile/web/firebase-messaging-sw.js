/* Register push handlers synchronously on EVERY worker start, not only installation.
   A push event may be dispatched immediately when a terminated worker restarts. */
self.addEventListener('notificationclick', event => {
  if (!event.notification.data?.joba) return; // Firebase handles its own background payloads.
  event.stopImmediatePropagation();
  event.notification.close();
  event.waitUntil(self.clients.openWindow('/app/?joba_push=notifications'));
});
importScripts('/api/v1/public/push-worker-config.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
if (self.JOBA_FIREBASE_CONFIG) {
  firebase.initializeApp(self.JOBA_FIREBASE_CONFIG);
  firebase.messaging(); // Installs the push listener before the first event is dispatched.
}
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));

self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
