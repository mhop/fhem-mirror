// Prerequisites: npm install express webpush bodyparser
// Starting it: node webpush.js > webpush.log

let email = 'mailto:admin@fhem.local';
let subscriptions = []; 

const express = require('express');
const webpush = require('web-push');
const bodyParser = require('body-parser');
const app = express();
app.use(bodyParser.json());

app.post('/vapid-key', (req, res) => {
  let b = req.body;
  console.log("/vapid-key:"+JSON.stringify(b));
  if(!b.privateKey)
    b = webpush.generateVAPIDKeys();
  webpush.setVapidDetails(email, b.publicKey, b.privateKey);
  res.status(200).json(b);
});

app.post('/subscriptions', (req, res) => {
  let b = req.body;
  console.log("/subscriptions:"+JSON.stringify(b));
  subscriptions = b;
  res.status(200).json({});
});

app.post('/notify', (req, res) => {
  let payload = JSON.stringify(req.body);
  console.log("/notify:"+payload);

  Promise.all(subscriptions.map(sub => 
    webpush.sendNotification(sub, payload).catch(err => console.error(err))
  ))
  .then(() => res.status(200).json({ success: true }));
});

app.listen(3000, "localhost", () => console.log('Port 3000 opened'));
