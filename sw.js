// Steve & Chlo service worker: only shows push reminders. It does not cache pages,
// so the app always loads fresh from the site.
importScripts('config.js');
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
  // Also tell the server this phone got it (sc_push_seen), so a missing push can be traced.
  const seen = err => self.registration.pushManager.getSubscription().then(s => {
    const C = self.SC_CONFIG || {};
    if (!s || !C.supabaseUrl) return;
    return fetch(C.supabaseUrl + '/rest/v1/rpc/sc_push_seen', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: C.supabaseKey, Authorization: 'Bearer ' + C.supabaseKey },
      body: JSON.stringify({ p_endpoint: s.endpoint, p_err: err || null }),
    });
  }).catch(() => {});
  e.waitUntil(self.registration.showNotification(title, opts)
    .then(() => Promise.all([tell({ pushed: d.tag || '' }), seen(null)]))
    .catch(err => Promise.all([tell({ pushed: d.tag || '', err: String(err) }), seen(String(err))])));
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
