self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const data = event.notification?.data || {};
    const payload = {
      type: 'store-grace-alert-action',
      action: String(event.action || 'open').trim() || 'open',
      store_id: Number.parseInt(String(data.store_id || ''), 10) || 0,
      store_name: String(data.store_name || '').trim(),
      due_date: String(data.due_date || '').trim(),
      pending_amount: data.pending_amount,
      days_left: data.days_left
    };

    const allClients = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    });

    const adminClient = (allClients || []).find((client) => {
      const url = String(client?.url || '');
      return url.includes('/admin');
    }) || (allClients && allClients.length ? allClients[0] : null);

    if (adminClient) {
      try {
        await adminClient.focus();
      } catch (_) {}
      try {
        adminClient.postMessage(payload);
      } catch (_) {}
      return;
    }

    try {
      const query = new URLSearchParams({
        notification_action: String(payload.action || 'open'),
        store_id: String(payload.store_id || ''),
        store_name: String(payload.store_name || ''),
        due_date: String(payload.due_date || ''),
        pending_amount: String(payload.pending_amount || ''),
        days_left: String(payload.days_left || '')
      });
      const target = `/admin.html?${query.toString()}`;
      await self.clients.openWindow(target);
    } catch (_) {
      try {
        await self.clients.openWindow('/');
      } catch (_) {}
    }
  })());
});
