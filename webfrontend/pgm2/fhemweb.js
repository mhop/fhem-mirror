/*************** LONGPOLL START **************/
var FW_pollConn;

function
FW_cmd(arg)     /* see also FW_devState */
{
  var req = new XMLHttpRequest();
  req.open("GET", arg, true);
  req.send(null);
}

function
FW_doUpdate()
{
  if(FW_pollConn.readyState != 4 || FW_pollConn.status != 200)
    return;
  var lines = FW_pollConn.responseText.split("\n");
  for(var i=0; i < lines.length; i++) {
    var d = lines[i].split(";", 3);    // Complete arg
    if(d.length != 3)
      continue;
    var el = document.getElementById(d[0]);
    if(el)
      el.innerHTML=d[2];
  }
  FW_pollConn.abort();
  FW_longpoll();
}

function
FW_longpoll()
{
  FW_pollConn = new XMLHttpRequest();
  var room="room=all";
  var sa = document.location.search.substring(1).split("&");
  for(var i = 0; i < sa.length; i++) {
    if(sa[i].substring(0,5) == "room=")
      room=sa[i];
  }
  var query = document.location.pathname+"?"+room+"&XHR=1&inform=1";
  FW_pollConn.open("GET", query, true);
  FW_pollConn.onreadystatechange = FW_doUpdate;
  FW_pollConn.send(null);
}

function
FW_delayedStart()
{
  setTimeout("FW_longpoll()", 1000);
}

function
FW_selChange(sel, list, elName)
{
  var value;
  var l = list.split(" ");
  for(var i=0; i < l.length; i++) {
    var nv = l[i].split(":",2);
    if(nv[0] == sel) {
      value = nv[1]; break;
    }
  }

  var el = document.getElementsByName(elName)[0];
  if(value==undefined) {
    newEl = document.createElement('input');
    newEl.type='text'; newEl.size=30; 
  } else {
    newEl = document.createElement('select');
    var vArr = value.split(",");
    for(var j=0; j < vArr.length; j++) {
      newEl.options[j] = new Option(vArr[j], vArr[j]);
    }
  }
  newEl.class=el.class; newEl.name=el.name;
  el.parentNode.replaceChild(newEl, el);
}
/*************** LONGPOLL END **************/
