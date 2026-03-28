// Service worker counterpart to f18.js

self.addEventListener('push', function (e) {
  if(!e.data)
    return;
  var o = e.data.json();
  console.log(o);
  e.waitUntil(Promise.all([
    self.registration.showNotification(o.title, { body: o.body })
  ]));
});


self.addEventListener('install', function(e) {
  console.log("SW: install");
});

self.addEventListener('activate', function(e) {
  console.log("SW: activate");
});

self.addEventListener('pushsubscriptionchange', function(event) {
  log("Subscription changed");
  console.log(event.oldSubscription);
  console.log(event.newSubscription);
});

console.log("f18_sw.js is active");
