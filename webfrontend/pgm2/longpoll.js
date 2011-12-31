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
  var room="room=all";
  var sa = document.location.search.substring(1).split("&");
  for(var i = 0; i < sa.length; i++) {
    if(sa[i].substring(0,5) == "room=")
      room=sa[i];
  }
  var query = document.location.pathname+"?"+room+"&XHR=1&inform=1";
  pollConn.open("GET", query, true);
  pollConn.onreadystatechange = doUpdate;
  pollConn.send(null);
}

window.onload = longpoll;
