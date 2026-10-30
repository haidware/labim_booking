self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch {
    payload = {
      title: "Rooms booking update",
      body: event.data ? event.data.text() : "Your booking status has changed.",
    };
  }

  event.waitUntil(
    self.registration.showNotification(payload.title || "Rooms booking update", {
      body: payload.body || "Your booking status has changed.",
      icon: "/icons/Icon-192.png",
      badge: "/icons/Icon-192.png",
      vibrate: [200, 100, 200],
      requireInteraction: true,
      data: { url: payload.url || "/" },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || "/", self.location.origin);
  if (target.origin !== self.location.origin) return;

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(
      (clients) => {
        const existing = clients.find((client) => client.url === target.href);
        if (existing) return existing.focus();
        return self.clients.openWindow(target.href);
      },
    ),
  );
});
