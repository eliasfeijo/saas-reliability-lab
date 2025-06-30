self.addEventListener("push", function (event) {
  if (!event.data) {
    console.log("[push-sw] No data in push event");
    return;
  }

  const text = event.data.text();

  console.log(text);

  const title = "Agenda";
  const options = {
    body: text || "Check your task list.",
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});
