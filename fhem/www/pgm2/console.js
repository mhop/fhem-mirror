var consConn;

function
consUpdate()
{
  if(consConn.readyState != 4 || consConn.status != 200)
    return;
  var el = document.getElementById("console");
  if(el)
    el.innerHTML=el.innerHTML+consConn.responseText;
  consConn.abort();
  consFill();
}

function
consFill()
{
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
