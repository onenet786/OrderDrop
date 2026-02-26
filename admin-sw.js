self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const allClients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (allClients && allClients.length) {
      const client = allClients[0];
      try {
        await client.focus();
      } catch (_) {}
      return;
    }
    try {
      await self.clients.openWindow('/');
    } catch (_) {}
  })());
});
