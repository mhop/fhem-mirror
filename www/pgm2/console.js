var consConn;

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
  if(el)
    el.innerHTML="Events:<br>"+consConn.responseText;
}

function
consFill()
{
  var errdiv = document.getElementById("connect_err");
  if(errdiv)
    document.body.removeChild(errdiv);

  consConn = new XMLHttpRequest();
  consConn.open("GET", document.location.pathname+"?XHR=1&inform=console", true);
  consConn.onreadystatechange = consUpdate;
  consConn.send(null);
}

function
consStart()
{
  setTimeout("consFill()", 1000);
}

window.onload = consStart;
