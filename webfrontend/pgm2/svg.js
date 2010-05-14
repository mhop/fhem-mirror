var old_title;
var old_sel;

function
svg_labelselect(evt)
{
  var sel = document.getElementById(evt.target.getAttribute("line_id"));
  var tl  = document.getElementById("svg_title");

  if(old_sel == sel) {
    sel.setAttribute("stroke-width", 1);
    old_sel = null;
    tl.firstChild.nodeValue = old_title;

  } else {
    if(old_sel == null)
      old_title = tl.firstChild.nodeValue;
    else
      old_sel.setAttribute("stroke-width", 1);
    sel.setAttribute("stroke-width", 3);
    old_sel = sel;
    tl.firstChild.nodeValue = evt.target.getAttribute("title");

  }
}

function
svg_click(evt)
{
  var t=evt.target;
  var y_mul = parseFloat(t.getAttribute("y_mul"));
  var y_h   = parseFloat(t.getAttribute("y_h"));
  var y_min = parseFloat(t.getAttribute("y_min"));
  var y_fx  = parseFloat(t.getAttribute("decimals"));
  var y_org = (((y_h-evt.clientY)/y_mul)+y_min).toFixed(y_fx);

  var x_mul = parseFloat(t.getAttribute("x_mul"));
  var x_off = parseFloat(t.getAttribute("x_off"));
  var x_min = parseFloat(t.getAttribute("x_min"));
  var d = new Date((((evt.clientX-x_min)/x_mul)+x_off) * 1000);
  var ts = (d.getHours() < 10 ? '0' : '') + d.getHours() + ":"+
           (d.getMinutes() < 10 ? '0' : '') + d.getMinutes();

  var tl = document.getElementById('svg_title');
  tl.firstChild.nodeValue = t.getAttribute("title")+": "+y_org+" ("+ts+")";
}
