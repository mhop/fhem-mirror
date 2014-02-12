var consConn;

var isFF = (navigator.userAgent.toLowerCase().indexOf('firefox') > -1);

function
consUpdate()
{
  if(consConn.readyState == 4) {
    FW_errmsg("Connection lost, trying a reconnect every 5 seconds.");
    setTimeout(consFill, 5000);
    return; // some problem connecting
  }

  if(consConn.readyState != 3)
    return;

  var el = document.getElementById("console");
  if(el) {
    el.innerHTML="Events:<br>"+consConn.responseText;
    el.scrollTop = el.scrollHeight;    
  }
}

function
consFill()
{
  FW_errmsg("");
  consConn = new XMLHttpRequest();
  var query = document.location.pathname+"?XHR=1"+
       "&inform=type=raw;filter=.*"+
       "&timestamp="+new Date().getTime();
  consConn.open("GET", query, true);
  consConn.onreadystatechange = consUpdate;
  consConn.send(null);
}

function
consStart()
{
  setTimeout("consFill()", 1000);
}

window.onload = consStart;
