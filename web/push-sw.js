self.addEventListener("push", function (event) {
  if (!event.data) {
    console.log("[push-sw] No data in push event");
    return;
  }

  const text = event.data.text();

  console.log(text);

  const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/'
  const iconPath = `${baseHref}icons/Icon-192.png`;

  const title = "Agenda";
  const options = {
    body: text || "Check your task list.",
    icon: iconPath,
    badge: iconPath,
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});
