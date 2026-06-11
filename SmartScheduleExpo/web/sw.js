self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(clients.claim()));

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (url.pathname.endsWith('/ics')) {
    const content = url.searchParams.get('c');
    if (content) {
      event.respondWith(new Response(decodeURIComponent(content), {
        status: 200,
        headers: { 'Content-Type': 'text/calendar;charset=utf-8' }
      }));
    }
  }
});
