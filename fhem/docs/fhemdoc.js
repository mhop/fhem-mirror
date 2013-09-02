function
room_table2select() {
  var ra = document.getElementsByClassName("room");
  if(!ra || !ra.length)
    return;
  ra = ra[0];
  ra.style.visibility='hidden';
  var aarr = ra.getElementsByTagName("a");
  var sel = document.createElement("select");
  sel.setAttribute("onChange",
        "location.href=this.options[this.selectedIndex].value");
  for(var i=0; i<aarr.length; i++) {
   var o = document.createElement("option");
   o.setAttribute("value", aarr[i].getAttribute("href"));
   o.innerHTML = aarr[i].innerHTML;
   sel.appendChild(o);
  }
  ra.parentElement.insertBefore(sel, ra);
}

var link = document.createElement('link');
link.rel = 'stylesheet';
link.type = 'text/css';
var ua = navigator.userAgent;
if(ua.match("Mobile")) {
  window.onload = room_table2select;
  link.href="../www/pgm2/smallscreenstyle.css";
} else {
  link.href="../www/pgm2/style.css";
}
document.getElementsByTagName("head")[0].appendChild(link);
