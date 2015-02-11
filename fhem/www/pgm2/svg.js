"use strict";
var svgNS = "http://www.w3.org/2000/svg";
var svg_b64 ="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
var svg_initialized={}, lastHidden;



// Base64 encode the xy points (12 bit x, 12 bit y).
function
svg_compressPoints(pointList)
{
  var i, x, y, lx = -1, ly, ret = "";
  var pl_arr = pointList.replace(/^  */,'').split(/[, ]/);
  for(i = 0; i < pl_arr.length; i +=2) {
    x = parseInt(pl_arr[i]);
    y = parseInt(pl_arr[i+1]);
    if(pl_arr.length > 500 && lx != -1 && x-lx < 2)    // Filter the data.
      continue;
    ret = ret+
          svg_b64.charAt((x&0xfc0)>>6)+
          svg_b64.charAt((x&0x3f))+
          svg_b64.charAt((y&0xfc0)>>6)+
          svg_b64.charAt((y&0x3f));
    lx = x; ly = y;
  }
  return ret;
}

function
svg_uncompressPoints(cmpData)
{
  var i = 0, ret = "";
  while(i < cmpData.length) {
    var x = (svg_b64.indexOf(cmpData.charAt(i++))<<6)+
             svg_b64.indexOf(cmpData.charAt(i++));
    var y = (svg_b64.indexOf(cmpData.charAt(i++))<<6)+
             svg_b64.indexOf(cmpData.charAt(i++));
    ret += " "+x+","+y;
  }
  return ret;
}


function
svg_getcookie()
{
  var c = document.cookie;
  if(c == null)
    return [];
  var results = c.match('fhemweb=(.*?)(;|$)' );
  return (results ? unescape(results[1]).split(":") : []);
}

function
svg_prepareHash(el)
{
  var obj = { y_mul:0,y_h:0,y_min:0, decimals:0, x_mul:0,x_off:0,x_min:0 };
  for(var name in obj)
    obj[name] = parseFloat($(el).attr(name));
  return obj;
}

function
svg_click(evt)
{
  var t = evt.target;
  var o = svg_prepareHash(t);

  var y_org = (((o.y_h-evt.clientY)/o.y_mul)+o.y_min).toFixed(o.decimals);
  var d = new Date((((evt.clientX-o.x_min)/o.x_mul)+o.x_off) * 1000);
  var ts = (d.getHours() < 10 ? '0' : '') + d.getHours() + ":"+
           (d.getMinutes() < 10 ? '0' : '') + d.getMinutes();

  
  var tl = t.ownerDocument.getElementById('svg_title');
  tl.firstChild.nodeValue = t.getAttribute("title")+": "+y_org+" ("+ts+")";
}

function
sv_menu(evt, embed)
{
  var label = evt.target;
  var svg = $(label).closest("svg");
  var svgNode = $(svg).get(0);
  var lid = $(label).attr("line_id");
  var data = svg_getcookie();
  var sel = $(svg).find("#"+lid);
  var selNode = $(sel).get(0);
  var tl = $(svg).find("#svg_title");
  var par = svgNode.par;

  var lines = $(svg).find("[line_id]");
  var hidden = $(svg).find(".hidden");

  function
  showValOff() {
    $(svg).find("[id]").each(function(){delete($(this).get(0).showVal)});
    $(svg).off("mousemove");

    if(par && par.circle) {
      $(par.circle).remove();
      $(par.div).remove();
    }
  }

  var sn = selNode.nodeName,
      pn = (sn=="path" ? "d" : "points"),
      arrName = (sn=="path" ? "pathSegList" : "points");
  FW_menu(evt, label,
    ["Copy", "Paste",
      selNode.isHidden ? "Show line" : "Hide line",
      "Hide other lines",
      "Show all lines",
      selNode.showVal ? "Stop displaying values" : "Display plot values" ],
    [undefined, data.length==0,
      !selNode.isHidden && (lines.length - hidden.length) == 1,
      !selNode.isHidden && (lines.length - hidden.length) == 1,
      hidden.length==0,
      selNode.isHidden || (sn!="polyline" && sn!="path") ],
    function(arg) {

      //////////////////////////////////// copy
      if(arg == 0) {
        document.cookie="fhemweb="+
              $(sel).attr("y_min")+":"+$(sel).attr("y_mul")+":"+
              svg_compressPoints($(sel).attr(pn));
      }

      //////////////////////////////////// paste
      if(arg == 1) {
        var doc = $(svg).get(0).ownerDocument;
        var o=doc.createElementNS(svgNS, "polyline");
        o.setAttribute("class", "pasted");
        o.setAttribute(pn, svg_uncompressPoints(data[2]));

        var h  = parseFloat($(sel).attr("y_h"));
        var ny_mul = parseFloat(data[1]);
        var ny_min = parseInt(data[0]);
        var y_mul  = parseFloat($(sel).attr("y_mul"));
        var y_min  = parseInt($(sel).attr("y_min"));
        var tr = 
            "translate(0,"+ (h/y_mul+y_min-h/ny_mul-ny_min)*y_mul +") "+
            "scale(1, "+ (y_mul/ny_mul) +") ";
        o.setAttribute("transform", tr);
        doc.documentElement.appendChild(o);
      }

      //show/hide
      if(arg == 2) {
        setVisibility(lid, selNode.isHidden?1:0);
        $(label).attr("opacity", selNode.isHidden?0.4:1);
      }

      //hide other
      if(arg == 3) {
        $(svg).find("[id]").each(function(){
          var id = $(this).attr("id");
          if(id.indexOf("line_") != 0 )
            return;
          var label = $(svg).find('[line_id="'+id+'"]');
          if( !label.length ) // ignore lines with label none
            return;
          var sel = $(svg).find("#"+id);
          var selNode = $(sel).get(0);
          if( (selNode.isHidden?false:true) != (id == lid) )
            setVisibility(id, id == lid);
          label.attr("opacity", id == lid?1:0.4);
        } );
      }

      //show all
      if(arg == 4) {
        $(svg).find("[line_id]").attr("opacity",1);
        $(svg).find("[id]").each(function(){
          var id = $(this).attr("id");
          if(id.indexOf("line_") != 0 )
            return;
          var sel = $(svg).find("#"+id);
          var selNode = $(sel).get(0);
          if( !selNode.isHidden )
            return;
          setVisibility(id, 1);
          //$(svg).find('[line_id="'+id+'"]').attr("opacity",1);
        } );
      }

      //////////////////////////////////// value display
      if(arg == 5) {

        var hadShowVal = selNode.showVal;
        showValOff();

        if(!hadShowVal) {
          selNode.showVal = true;
          $(svg).mousemove(mousemove);
          svgNode.par = par = svg_prepareHash(selNode);

          par.circle =
                $(svg).get(0).ownerDocument.createElementNS(svgNS, "circle");
          $(par.circle).attr("id", "svgmarker").attr("r", "8");
          $(svg).append(par.circle);

          par.div = $('<div id="svgmarker">');
          par.divoffY = $(embed ? embed : svg).offset().top -
                       $("#content").offset().top-50;
          $("#content").append(par.div);

          var pl = selNode[arrName];
          if(pl.numberOfItems > 2)
            mousemove({pageX:pl.getItem(pl.numberOfItems-2).x});
        }
      }


      if( arg >= 2 && arg <= 4 ) {
        var hidden = $(svg).find(".hidden");
        if( lines.length - hidden.length == 1 ) {
            $(tl).attr("hiddentitle", $(tl).text());
            if($(sel).attr(pn) != null)
              $(tl).text($(label).attr("title"));

        } else if( $(tl).attr("hiddentitle") ) {
            $(tl).text($(tl).attr("hiddentitle"));
            $(tl).removeAttr("hiddentitle")

        }
      }

    }, embed);

  function pad0(v) { return (v < 10 ? '0'+v  :v); }

  function
  mousemove(e)
  {
    var xRaw = e.pageX, pl = selNode[arrName], l = pl.numberOfItems, i1;
    if(!embed)
      xRaw -= $(svg).offset().left;
    for(i1=0; i1<l; i1++)
      if(pl.getItem(i1).x > xRaw)
        break;
    if(i1==l || i1==0)
      return;

    var pp=pl.getItem(i1-1), pn=pl.getItem(i1);
    var xR = (xRaw-pp.x)/(pn.x-pp.x);   // Compute interim values
    var yRaw = pp.y+xR*(pn.y-pp.y); 

    var y = (((par.y_h-yRaw)/par.y_mul)+par.y_min).toFixed(par.decimals);

    var d = new Date((((xRaw-par.x_min)/par.x_mul)+par.x_off) * 1000), ts;
    if(par.x_mul < 0.0001) {           // Year
      ts = (d.getMonth()+1)+"."+pad0(d.getDate());
    } else if(par.x_mul < 0.001) {     // Month
      ts = d.getDate()+". "+pad0(d.getHours())+":"+pad0(d.getMinutes());
    } else {
      ts = pad0(d.getHours())+":"+pad0(d.getMinutes());
    }

    $(par.circle).attr("cx", xRaw).attr("cy", yRaw);
    var yd = Math.floor((yRaw+par.divoffY) / 20)*20;
    $(par.div).html(ts+" "+y)
              .css({ left:xRaw-20, top:yd });
  }

  function
  setVisibility(id,visible)
  {
    var sel = $(svg).find("#"+id);
    var selNode = $(sel).get(0);
    var currval = visible?1:0;
    var h = parseFloat(sel.attr("y_h"));
    //sel.attr("transform", "translate(0,"+h*(1-currval)+") "+ "scale(1,"+currval+")");

    if( !visible
        && selNode.showVal )
      showValOff();

    animateVisibility(sel,visible?0:1, visible?1:0);

    if( visible ) {
      delete(selNode.isHidden);
      sel.attr("class", sel.attr("class").replace(/ hidden/, "" ) );
    } else {
      selNode.isHidden = true;
      sel.attr("class", sel.attr("class") + " hidden" );
    }
  }

  function
  animateVisibility(sel, currval, maxval)
  {
      var h = parseFloat(sel.attr("y_h"));
      sel.attr("transform", "translate(0,"+h*(1-currval)+") "+
                                "scale(1,"+currval+")");

    if(currval != maxval) {
      currval += (currval<maxval ? 0.02 : -0.02);
      currval = Math.round(currval*100)/100;
      setTimeout(function(){ animateVisibility(sel,currval,maxval) }, 10);
    }
  }

}

function
svg_init_one(embed, svg)
{
  var sid = $(svg).attr("id");
  if(svg_initialized[sid])
    return;
  svg_initialized[sid] = true;
  $("text.legend", svg).click(function(e){sv_menu(e, embed)});
}

function
svg_init(par)    // also called directly from perl, in race condition
{
  $("embed").each(function(){
    var e = this;
    var src = $(e).attr("src");
    var ed = e.getSVGDocument();
    if(src.indexOf("SVG_showLog") < 0 || !ed)
      return;
    var sTag = $("svg", ed)[0];
    if((par && $(sTag).attr("id") != par))
      return;
    svg_init_one(e, sTag);
  });
}

$(document).ready(function(){
  svg_init();                          // <embed><svg>
  $("svg[id]").each(function(){        // <svg> (direct)
    if($(this).attr("id").indexOf("SVGPLOT") == 0)
      svg_init_one(undefined, this);
  });
});

// longpollSVG code below
function
FW_svgUpdateDevs(devs)
{
  // if matches, refresh the SVG by removing and readding the embed tag
  var embArr = document.getElementsByTagName("embed");
  for(var i = 0; i < embArr.length; i++) {
    var svg = embArr[i].getSVGDocument();
    if(!svg || !svg.firstChild || !svg.firstChild.nextSibling)
      continue;
    svg = svg.firstChild.nextSibling;
    var flog = svg.getAttribute("flog");
    if(!flog)
      continue;
    flog = flog.replace(/\\x3a/g, ".");
    log("longpollSVG filter:"+flog);
    for(var j=0; j < devs.length; j++) {
      var d = devs[j];
      var ev = d[0]+":"+d[1];
      if(ev.match(flog)) {
        log("longpollSVG: reload SVG");
        delete(svg_initialized[$(svg).attr("id")]);
        var e = embArr[i];
        var newE = document.createElement("embed");
        for(var k=0; k<e.attributes.length; k++)
          newE.setAttribute(e.attributes[k].name, e.attributes[k].value);
        e.parentNode.insertBefore(newE, e);
        e.parentNode.removeChild(e);
        break;
      }
    }
  }
}

FW_widgets.SVG = { updateDevs:FW_svgUpdateDevs };
