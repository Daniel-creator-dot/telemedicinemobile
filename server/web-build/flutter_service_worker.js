'use strict';

// Cache name changes with each web release. A previous worker kept
// serving main.dart.js that painted the API host on the sign-in layout.
const CACHE_NAME = 'healynks-shell-261005144736';

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(Promise.resolve());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((key) => caches.delete(key)));
      } catch (e) {
        console.warn('Failed to delete old Healynks caches:', e);
      }

      try {
        await self.clients.claim();
      } catch (e) {
        console.warn('Failed to claim clients:', e);
      }

      try {
        await self.registration.unregister();
      } catch (e) {
        console.warn('Failed to unregister the service worker:', e);
      }

      try {
        const clients = await self.clients.matchAll({
          type: 'window',
        });
        clients.forEach((client) => {
          if (client.url && 'navigate' in client) {
            client.navigate(client.url);
          }
        });
      } catch (e) {
        console.warn('Failed to navigate some service worker clients:', e);
      }
    })()
  );
});
