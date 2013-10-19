var consConn;

var isFF = (navigator.userAgent.toLowerCase().indexOf('firefox') > -1);

function
consUpdate()
{
  if(consConn.readyState == 4) {
    var errdiv = document.createElement('div');
    errdiv.innerHTML = "Connection lost, reconnecting in 5 seconds...";
    errdiv.setAttribute("id","connect_err");
    document.body.appendChild(errdiv);
    setTimeout("consFill()", 5000);
    return; // some problem connecting
  }
  if(consConn.readyState != 3)
    return;

  var el = document.getElementById("console");
  if(el) {
    el.innerHTML="Events:<br>"+consConn.responseText;
    // Scroll to bottom. FF is different from Safari/Chrome
    el.scrollTop = el.scrollHeight;    
    //var p = el.parentElement; // content div
    //if(isFF)
    //  p.parentElement.parentElement.scrollTop = p.scrollHeight; // html tag
    //else
    //  p.parentElement.scrollTop = p.scrollHeight; // body tag
  }
}

function
consFill()
{
  var errdiv = document.getElementById("connect_err");
  if(errdiv)
    document.body.removeChild(errdiv);

  consConn = new XMLHttpRequest();
  // Needed when using multiple FF windows
  var timestamp = "&timestamp="+new Date().getTime();
  var query = document.location.pathname+"?XHR=1&inform=console"+timestamp;
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
