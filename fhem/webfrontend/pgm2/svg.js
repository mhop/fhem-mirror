var xmlns="http://www.w3.org/2000/svg";
var old_title;
var old_sel;
var svgdoc;
var b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Base64 encode the xy points (12 bit x, 12 bit y).
function
compressPoints(pointList)
{
  var i, x, y, lx = -1, ly, ret = "";
  var pl_arr = pointList.split(" ");
  for(i = 0; i < pl_arr.length; i++) {
    var xy = pl_arr[i].split(",");
    x = parseInt(xy[0]);
    y = parseInt(xy[1]);
    if(pl_arr.length > 500 && lx != -1 && x-lx < 2)    // Filter the data.
      continue;
    ret = ret+
          b64.charAt((x&0xfc0)>>6)+
          b64.charAt((x&0x3f))+
          b64.charAt((y&0xfc0)>>6)+
          b64.charAt((y&0x3f));
    lx = x; ly = y;
  }
  return ret;
}

function
uncompressPoints(cmpData)
{
  var i = 0, ret = "";
  while(i < cmpData.length) {
    var x = (b64.indexOf(cmpData.charAt(i++))<<6)+
            b64.indexOf(cmpData.charAt(i++));
    var y = (b64.indexOf(cmpData.charAt(i++))<<6)+
            b64.indexOf(cmpData.charAt(i++));
    ret += " "+x+","+y;
  }
  return ret;
}


function
get_cookie(name)
{
  var c = parent.document.cookie;
  if(c == null)
    return "";
  var results = c.match("fw_"+escape(name)+'=(.*?)(;|$)' );
  return (results ? unescape(results[1]) : "");
}

function
set_cookie(name, value)
{
  name = "fw_"+escape(name);
  parent.document.cookie=name+"="+escape(value);
}

 
function
svg_copy(evt)
{
  var d = evt.target.ownerDocument;
  var cp = d.getElementById("svg_copy");
  cp.firstChild.nodeValue = " ";
  set_cookie(old_sel.getAttribute("title"),
             old_sel.getAttribute("y_min")+":"+
             old_sel.getAttribute("y_mul")+":"+
             compressPoints(old_sel.getAttribute("points")));
}

function
svg_paste(evt)
{
  var d = evt.target.ownerDocument;
  var ps = d.getElementById("svg_paste");
  ps.firstChild.nodeValue = " ";

  var o=d.createElementNS(xmlns, "polyline");
  o.setAttribute("class", "pasted");
  var data = get_cookie(old_sel.getAttribute("title")).split(":", 3);
  o.setAttribute("points", uncompressPoints(data[2]));

  var h  = parseFloat(old_sel.getAttribute("y_h"));
  var ny_mul = parseFloat(data[1]);
  var ny_min = parseInt(data[0]);
  var y_mul  = parseFloat(old_sel.getAttribute("y_mul"));
  var y_min  = parseInt(old_sel.getAttribute("y_min"));
  var tr = 
      "translate(0,"+ (h/y_mul+y_min-h/ny_mul-ny_min)*y_mul +") "+
      "scale(1, "+ (y_mul/ny_mul) +") ";
  o.setAttribute("transform", tr);

  d.documentElement.appendChild(o);
}



function
svg_labelselect(evt)
{
  var d = evt.target.ownerDocument;
  var sel = d.getElementById(evt.target.getAttribute("line_id"));
  var tl = d.getElementById("svg_title");
  var cp = d.getElementById("svg_copy");
  var ps = d.getElementById("svg_paste");

  if(old_sel == sel) {
    sel.setAttribute("stroke-width", 1);
    old_sel = null;
    tl.firstChild.nodeValue = old_title;
    cp.firstChild.nodeValue = " ";
    ps.firstChild.nodeValue = " ";

  } else {
    if(old_sel == null)
      old_title = tl.firstChild.nodeValue;
    else
      old_sel.setAttribute("stroke-width", 1);
    sel.setAttribute("stroke-width", 3);
    old_sel = sel;
    if(sel.getAttribute("points") != null) {
      tl.firstChild.nodeValue = evt.target.getAttribute("title");
      cp.firstChild.nodeValue = "Copy";
      ps.firstChild.nodeValue = (
                    get_cookie(sel.getAttribute("title"))==""?" ":"Paste");
    }

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

  
  var tl = evt.target.ownerDocument.getElementById('svg_title');
  tl.firstChild.nodeValue = t.getAttribute("title")+": "+y_org+" ("+ts+")";
}
