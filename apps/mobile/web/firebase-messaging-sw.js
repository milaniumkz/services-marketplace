/* Dedicated FCM worker; it does not cache application pages or credentials. */
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
const initialized = fetch('/api/v1/public/push-config', {cache: 'no-store'})
  .then(response => { if (!response.ok) throw Error('Push configuration unavailable'); return response.json(); })
  .then(({data}) => {
    if (!data.enabled || !data.platforms.web) return;
    firebase.initializeApp(data.platforms.web);
    return firebase.messaging(); // FCM displays the notification payload, once.
  });
self.addEventListener('install', event => event.waitUntil(initialized));
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
