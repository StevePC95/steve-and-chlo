// Steve & Chlo service worker: only shows push reminders. It does not cache pages,
// so the app always loads fresh from the site.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: e.data ? e.data.text() : '' }; }
  const title = d.title || 'Steve & Chlo';
  const opts = {
    body: d.body || '',
    icon: 'icons/icon-192.png',
    badge: 'icons/icon-192.png',
    data: { url: d.url || '#today' },
  };
  // Same tag replaces the old one; renotify makes it pop up and buzz again instead of swapping silently.
  if (d.tag) { opts.tag = d.tag; opts.renotify = true; }
  // Tell any open copy of the app that the push arrived (or why it could not be shown).
  const tell = msg => self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(list => list.forEach(c => c.postMessage(msg)));
  e.waitUntil(self.registration.showNotification(title, opts)
    .then(() => tell({ pushed: d.tag || '' }))
    .catch(err => tell({ pushed: d.tag || '', err: String(err) })));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const hash = (e.notification.data && e.notification.data.url) || '#today';
  const url = new URL(hash, self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) {
      if (c.url.startsWith(self.registration.scope) && 'focus' in c) {
        c.postMessage({ go: hash });
        return c.focus();
      }
    }
    return self.clients.openWindow(url);
  }));
});
