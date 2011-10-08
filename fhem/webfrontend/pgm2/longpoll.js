var pollConn;

function
cmd(arg)
{
  var req = new XMLHttpRequest();
  req.open("GET", arg, true);
  req.send(null);
}

function
doUpdate()
{
  if(pollConn.readyState != 4 || pollConn.status != 200)
    return;
  var lines = pollConn.responseText.split("\n");
  for(var i=0; i < lines.length; i++) {
    var d = lines[i].split(";", 3);    // Complete arg
    if(d.length != 3)
      continue;
    var el = document.getElementById(d[0]);
    if(el)
      el.innerHTML=d[2];
  }
  pollConn.abort();
  longpoll();
}

function
longpoll()
{
  pollConn = new XMLHttpRequest();
  pollConn.open("GET", document.location.pathname+document.location.search+
                "&XHR=1&inform=1", true);
  pollConn.onreadystatechange = doUpdate;
  pollConn.send(null);
}

window.onload = longpoll;
