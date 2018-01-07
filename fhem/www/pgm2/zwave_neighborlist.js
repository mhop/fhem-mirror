"use strict";
FW_version["zwave_neighborlist.js"] = "$Id$";

var zw_visible;
var svgns = 'xmlns="http://www.w3.org/2000/svg"';

function
zw_nl(fhemFn)
{
  log("ZWNL called with "+fhemFn);
  zw_visible = !zw_visible;
  var txt = (zw_visible ? 'Hide' : 'Show');

  var width=960,height=480;
  $('#ZWDongleNr a#zw_snm').html(txt+' neighbor map');

  if(!zw_visible) {
    $('#ZWDongleNr span').remove();
    $("#ZWDongleNrSVG")
        .css({width:0, height:0})
        .html('');
    return;
  }

  $('#ZWDongleNr').append('<span>'+
    '&nbsp;&nbsp;<a id="zw_al" href="#">Start auto layout</a>'+
    '&nbsp;&nbsp;<a id="zw_save" href="#">Send layout to FHEM</a></span>');

  FW_cmd(FW_root+"?cmd={"+fhemFn+"}&XHR=1", function(r){
    var xpos=20, ypos=20, fnRet = JSON.parse(r);

    var cnt=0;
    for(var elName in fnRet.el) {
      var el = fnRet.el[elName];
      el.lines = [];
      el.name = elName;
      el.elHash = fnRet.el;
      if(el.img) {
        el.width = 64; el.height = 64+20;
      } else {
        el.width = el.height = 30;
      }

      if(!el.pos.length) {
        el.pos = [xpos, ypos];
        xpos += 150;
        if(xpos+150 >= width)
          xpos = 20, ypos += 50;
      }
      el.x = el.pos[0]; el.y = el.pos[1]; 
      cnt++;
    }
    if(height < cnt*35)
      height = cnt*35;
    zw_draw(fnRet, width, height);
    $('#ZWDongleNr a#zw_al').click(function(){ zw_al(fnRet, width, height); });

    $('#ZWDongleNr a#zw_save').click(function(){
      if(!fnRet.saveFn)
        return;
      for(var eName in fnRet.el) {
        var el = fnRet.el[eName];
        if(el.pos[0] != el.x || el.pos[1] != el.y) {
          log("SavePos:"+eName);
          el.pos[0] = el.x; el.pos[1] = el.y;
          var cmd = sprintf(fnRet.saveFn, eName, el.x+","+el.y);
          FW_cmd(FW_root+"?cmd="+cmd+"&XHR=1");
        }
      }
    });
  });

}

function
zw_draw(fnRet, width, height)
{
  var h = fnRet.el;
  var svg = '<svg '+svgns+' style="width:'+width+';height:'+height+'" '+
                  'class="zw_nr" viewBox="0 0 '+width+' '+height+'">';
  svg += '<defs>'+
            '<marker id="endarrow" markerWidth="20" markerHeight="20" '+
                'refx="50" refy="6" orient="auto" markerUnits="strokeWidth">'+
              '<path d="M0,0 L0,12 L18,6 z" class="zwArrowHead col_link" />'+
             '</marker>'+
            '<marker id="startarrow" markerWidth="20" markerHeight="20" '+
                'refx="-50" refy="6" orient="auto" markerUnits="strokeWidth">'+
              '<path d="M18,0 L18,12 L0,6 z" class="zwArrowHead col_link" />'+
             '</marker>'+
          '</defs>';
  svg += '<rect class="zwMargin col_link" x="1" y="1" width="'+
                (width-1)+'" height="'+(height-1)+'"/>';
  var ld={};

  for(var o in h) {
    if(h[o].txt && h[o].neighbors)
      for(var i1=0; i1<h[o].neighbors.length; i1++)
        svg += zw_drawline(ld, h, o, h[o].neighbors[i1]);
  }
  for(var o in h)
    if(h[o].txt)
      svg += zw_drawbox(h[o]);

  svg += '</svg>';

  var ox, oy, o;
  $("#ZWDongleNrSVG")
    .css({width:width, height:height})
    .html(svg);

  $("svg.zw_nr g").each(function(){
    $(this).css({cursor:"pointer", position:"absolute"}); // firefox is relative
    var name = $(this).attr("data-name");
    var o = h[name];
    o.text = $(this).find("text");
    o.rect = $(this).find("rect");
    if(o.img) {
      o.image = $(this).find("image");
      o.imgOffX = 0;
    }
    o.width = $(o.text)[0].getBBox().width+10;
    if(o.img && o.width < 64)
      o.width = 64;
    if(o.image) {
      o.imgOffX = (o.width-60)/2;
      $(o.image).attr("x", o.x+o.imgOffX);
    }

    $(o.rect).attr("width",o.width);
    zw_adjustLines(h, name);
  })
  .draggable()
  .bind('mousedown', function(e) {
    o = h[$(e.target).parent().attr("data-name")];
    ox = o.x; oy = o.y;
  })
  .bind('drag', function(e, ui) {
    var p = ui.position, op = ui.originalPosition;
    o.x = ox + (p.left-op.left);
    o.y = oy + (p.top -op.top);
    $(o.rect).attr("x", o.x);   $(o.rect).attr("y", o.y);
    $(o.text).attr("x", o.x+5); $(o.text).attr("y", o.y+20);
    if(o.image) {
      $(o.image).attr("x", o.x+o.imgOffX);
      $(o.image).attr("y", o.y+20);
    }
    zw_adjustLines(h, o.name);
  });
}

function
zw_drawbox(o)
{
  var s = '';
  s += '<g data-name="'+o.name+'">';
  if(o.title)
    s += '<title>'+o.title+'</title>';
  s += '<rect x="'+o.x+'" y="'+o.y+'" rx="5" ry="5" '+
              'width="'+o.width+'" height="'+o.height+'" class="'+o.class+'"/>';
  if(o.img)
    s += '<image x="'+(o.x+2)+'" y="'+(o.y+20)+'"/ width="60" height="60" '+
              'xlink:href="'+o.img+'"/>';
  s += '<text x="'+(o.x+5)+'" y="'+(o.y+20)+'">'+o.txt+'</text>'
  s +='</g>';
  return s;
}

function
zw_calcPos(o, n)
{
  return { x: o.x+o.width/2, y: o.y+o.height/2 };
}

function
zw_drawline(ld, h, o, n)
{
  if(!h[o] || !h[n])
    return "";
  var bidi = false;
  for(var i1=0; i1<h[n].neighbors.length; i1++)
    if(h[n].neighbors[i1] == o)
      bidi = true;

  if(n < o) {
    var t = n; n = o; o = t;
  }
  var cl = o+"-"+n;
  if(ld[cl])
    return "";
  ld[cl] = 1;
  h[o].lines.push(cl);
  h[n].lines.push(cl);
  var fr = zw_calcPos(h[o], h[n]);
  var to = zw_calcPos(h[n], h[o]);
  return '<line class="zwLine col_link" data-name="'+cl+
               '" x1="'+fr.x+'" y1="'+fr.y+
               '" x2="'+to.x+'" y2="'+to.y+'"'+
                 ' marker-end="url(#endarrow)"'+
                 (bidi?' marker-start="url(#startarrow)"':'')+
               '/>';
}

function
zw_adjustLines(h, name)
{
  var la = h[name].lines;
  for(var i1=0; i1<la.length; i1++) {
    var se = la[i1].split('-');
    var attName = la[i1].replace(/\./g, "\\.");
    if(la[i1].indexOf(name) == 0) {     // we are the from line
      var p = zw_calcPos(h[se[0]], h[se[1]]);
      $("svg line[data-name="+attName+"]")
        .attr("x1", p.x)
        .attr("y1", p.y);
    } else {
      var p = zw_calcPos(h[se[1]], h[se[0]]);
      $("svg line[data-name="+attName+"]")
        .attr("x2", p.x)
        .attr("y2", p.y);
    }
    if (navigator.appVersion.indexOf("Trident") != -1) {
      var svgNode = $("svg line[data-name="+attName+"]")[0];
      svgNode.parentNode.insertBefore(svgNode, svgNode);
    }
  }
}

/////////////////////////////////////
// fmt contains {1}, {2}, ...
function
sprintf() {
  var formatted = arguments[0];
  for (var i = 1; i < arguments.length; i++) {
    var regexp = new RegExp('\\{'+i+'\\}', 'gi');
    formatted = formatted.replace(regexp, arguments[i]);
  }
  return formatted;
};

var gm;
function
zw_al(fnRet, width, height)
{
  function
  stop()
  {
    $("a#zw_al").html("Start auto layout");
    clearTimeout(gm.gm_timeout);
    gm = undefined;
  }

  if(gm) {
    stop();
    return;
  }

  $("a#zw_al").html("Stop auto layout");

  var lu = [ fnRet.el[fnRet.firstObj] ], idx=0;
  fnRet.el[fnRet.firstObj].idx = idx++;
  for(var el in fnRet.el)
    if(el != fnRet.firstObj) {
      fnRet.el[el].idx = idx++;
      lu.push(fnRet.el[el]);
    }

  var nEl=lu.length, dist=new Array(nEl);
  for(var i1=0; i1<nEl; i1++) {
    dist[i1] = new Array(nEl);
    var dp = dist[i1];
    for(var i2=0; i2<nEl; i2++)
      dp[i2] = 1;
    dp[i1] = -1;
  }

  for(var i1=0; i1<nEl; i1++) {
    var nl = lu[i1].neighbors;
    for(var i2=0; i2<nl.length; i2++) {
      if(!fnRet.el[nl[i2]])
        continue;
      var i3 = fnRet.el[nl[i2]].idx;
      dist[i1][i3] = dist[i3][i1] = 0.1;
    }
  }

  gm = new GM();
  gm.aid = dist;
  gm.lu= lu;
  gm.minX = 0; gm.maxX = width;
  gm.minY = 0; gm.maxY = height;
  gm.init();
  gm.finishFn = stop;
}

/*!
 * jQuery UI Touch Punch 0.2.3
 *
 * Copyright 2011–2014, Dave Furfero
 * Dual licensed under the MIT or GPL Version 2 licenses.
 *
 * Depends:
 *  jquery.ui.widget.js
 *  jquery.ui.mouse.js
 */
(function ($) {

  // Detect touch support
  $.support.touch = 'ontouchend' in document;

  // Ignore browsers without touch support
  if (!$.support.touch) {
    return;
  }

  var mouseProto = $.ui.mouse.prototype,
      _mouseInit = mouseProto._mouseInit,
      _mouseDestroy = mouseProto._mouseDestroy,
      touchHandled;

  /**
   * Simulate a mouse event based on a corresponding touch event
   * @param {Object} event A touch event
   * @param {String} simulatedType The corresponding mouse event
   */
  function simulateMouseEvent (event, simulatedType) {

    // Ignore multi-touch events
    if (event.originalEvent.touches.length > 1) {
      return;
    }

    event.preventDefault();

    var touch = event.originalEvent.changedTouches[0],
        simulatedEvent = document.createEvent('MouseEvents');
    
    // Initialize the simulated mouse event using the touch event's coordinates
    simulatedEvent.initMouseEvent(
      simulatedType,    // type
      true,             // bubbles                    
      true,             // cancelable                 
      window,           // view                       
      1,                // detail                     
      touch.screenX,    // screenX                    
      touch.screenY,    // screenY                    
      touch.clientX,    // clientX                    
      touch.clientY,    // clientY                    
      false,            // ctrlKey                    
      false,            // altKey                     
      false,            // shiftKey                   
      false,            // metaKey                    
      0,                // button                     
      null              // relatedTarget              
    );

    // Dispatch the simulated event to the target element
    event.target.dispatchEvent(simulatedEvent);
  }

  /**
   * Handle the jQuery UI widget's touchstart events
   * @param {Object} event The widget element's touchstart event
   */
  mouseProto._touchStart = function (event) {

    var self = this;

    // Ignore the event if another widget is already being handled
    if (touchHandled || !self._mouseCapture(event.originalEvent.changedTouches[0])) {
      return;
    }

    // Set the flag to prevent other widgets from inheriting the touch event
    touchHandled = true;

    // Track movement to determine if interaction was a click
    self._touchMoved = false;

    // Simulate the mouseover event
    simulateMouseEvent(event, 'mouseover');

    // Simulate the mousemove event
    simulateMouseEvent(event, 'mousemove');

    // Simulate the mousedown event
    simulateMouseEvent(event, 'mousedown');
  };

  /**
   * Handle the jQuery UI widget's touchmove events
   * @param {Object} event The document's touchmove event
   */
  mouseProto._touchMove = function (event) {

    // Ignore event if not handled
    if (!touchHandled) {
      return;
    }

    // Interaction was not a click
    this._touchMoved = true;

    // Simulate the mousemove event
    simulateMouseEvent(event, 'mousemove');
  };

  /**
   * Handle the jQuery UI widget's touchend events
   * @param {Object} event The document's touchend event
   */
  mouseProto._touchEnd = function (event) {

    // Ignore event if not handled
    if (!touchHandled) {
      return;
    }

    // Simulate the mouseup event
    simulateMouseEvent(event, 'mouseup');

    // Simulate the mouseout event
    simulateMouseEvent(event, 'mouseout');

    // If the touch interaction did not move, it should trigger a click
    if (!this._touchMoved) {

      // Simulate the click event
      simulateMouseEvent(event, 'click');
    }

    // Unset the flag to allow other widgets to inherit the touch event
    touchHandled = false;
  };

  /**
   * A duck punch of the $.ui.mouse _mouseInit method to support touch events.
   * This method extends the widget with bound touch event handlers that
   * translate touch events to mouse events and pass them to the widget's
   * original mouse event handling methods.
   */
  mouseProto._mouseInit = function () {
    
    var self = this;

    // Delegate the touch handlers to the widget's element
    self.element.bind({
      touchstart: $.proxy(self, '_touchStart'),
      touchmove: $.proxy(self, '_touchMove'),
      touchend: $.proxy(self, '_touchEnd')
    });

    // Call the original $.ui.mouse init method
    _mouseInit.call(self);
  };

  /**
   * Remove the touch event handlers
   */
  mouseProto._mouseDestroy = function () {
    
    var self = this;

    // Delegate the touch handlers to the widget's element
    self.element.unbind({
      touchstart: $.proxy(self, '_touchStart'),
      touchmove: $.proxy(self, '_touchMove'),
      touchend: $.proxy(self, '_touchEnd')
    });

    // Call the original $.ui.mouse destroy method
    _mouseDestroy.call(self);
  };

})(jQuery);

function
GM()
{
  this.aid=null;

  this.scaleFactor      =1.4;   // scaling in respect to calculated window space
  this.scaleByCenterDist=-1;    // scaling in respect to mean target center distance (mean aid[i][0])

  this.frameDelayInitial=250;   // initial value of increasing delay at each timestep
  this.slowdownCycle    =30;    // number of timesteps after that delay is increased
  this.inertia          =0.7;   // part of velocity kept in one timestep 
  this.damperInitial    =4;     // initial value of increasing damper that cool down motion with time
  this.damperFactor     =1.052; // factor the damper is increased by in one timestep
  this.damperMax        =60;    // max. value of damper
  this.springForce0     =2.500; // force between each item and the central item s0 trying to keep them at aid[][]-distance
  this.springForce      =0.015; // force between each item pair except the central item s0
  this.centeringForce   =0.1;   // force that pulls the center of gravity towards the central item 

  // overlap avoiding
  this.repelInitial     = 0.1
  this.repelDelay       = 0;   // nr. of timesteps without repulsion
  this.repelIncrease    =0.02; // amount the repelling force that keeps items non overlapping increases each timestep
  this.repelMax         =0.9;  // max amount of repelling force. 
  this.paddingFactor    =2.00; // factor by which an item is enlarged while avoiding overlap

  var nrItems, items;
  var maxX, maxY, minX, minY; // bounds of drawing area
  var scaleX,scaleY;
  var cogX, cogY;
  var cycle=0;
  var damper;
  var repel = this.repelInitial;

  this.getMeanItemSize=function()
  {
    var meanW=0, meanH=0;
   
    for(var i=1; i<nrItems; i++) {
      meanW+=items[i].width;
      meanH+=items[i].height;
    } 
    meanW/=nrItems;
    meanH/=nrItems;
    
    return {width: meanW, height: meanH};
  }


  this.updateScale=function()
  {
    var scale = this.scaleFactor*
                  (1+this.scaleByCenterDist*this.meanTargetCenterDistance());
    var meanSize =this.getMeanItemSize();
   
    scaleX=(maxX-minX-meanSize.width )*scale;
    scaleY=(maxY-minY-meanSize.height)*scale;
  }

  this.resetItemPositions=function()
  {
    items=this.lu;
    for(var i1=0; i1<nrItems; i1++) {
      var el = this.lu[i1];
      el.speedX = el.speedY = 0;
      el.width =el.width;
      el.height=el.height;
      el.inertia=0.7;
      var maxDist = Math.sqrt(Math.pow(gm.maxX-gm.maxX/2,2) + 
                              Math.pow(gm.maxY-gm.maxY/2,2));
      el.update=function(damper)
      {
        $(this.rect).attr("x", this.x);   $(this.rect).attr("y", this.y);
        $(this.text).attr("x", this.x+5); $(this.text).attr("y", this.y+20);
        if(this.image) {
          $(this.image).attr("x", this.x+this.imgOffX);
          $(this.image).attr("y", this.y+20);
        }
        zw_adjustLines(this.elHash, this.name, 0);
       
        this.x+=this.speedX/damper;
        this.y+=this.speedY/damper;  
       
        this.speedX*=this.inertia;
        this.speedY*=this.inertia;
      }
    }
   
    this.updateScale();
   
    cogX=items[0].x;
    cogY=items[0].y;
    cycle=0;
    this.gm_frameDelay=this.frameDelayInitial;
    damper=this.damperInitial;
    repel=this.repelInitial;
  }

  this.recenterItems=function()
  {
    var forceX=(items[0].x-cogX)*this.centeringForce;
    var forceY=(items[0].y-cogY)*this.centeringForce;
    for (var i=1; i<nrItems; i++)
    {
     items[i].x+=forceX;
     items[i].y+=forceY;
    }
  }

  this.updateItems=function()
  {
    cogX=0; cogY=0;
    for (var i=0; i<nrItems; i++) {
      var w=items[i].width /2;
      var h=items[i].height/2;
      if (items[i].x+w>maxX) items[i].x=maxX-w;
      if (items[i].x-w<minX) items[i].x=minX+w;
      if (items[i].y+h>maxY) items[i].y=maxY-h;
      if (items[i].y-h<minY) items[i].y=minY+h;
     
      cogX+=items[i].x;
      cogY+=items[i].y;
     
      items[i].update(damper);
    }
    cogX/=nrItems; 
    cogY/=nrItems;
  }

  function
  positiveMin(values)
  {
    var r=Number.MAX_VALUE;
    for (var i=0; i<values.length; i++)
     if (values[i]>=0 && values[i]<r) r=values[i];
   
    return r;
  }

  this.layoutItems=function()
  {
    for(var i1=0; i1<nrItems; i1++) {
      for(var i2=i1+1; i2<nrItems; i2++) {
        this.adjustItemDistance(items[i1], items[i2]);
        this.repelItems        (items[i1], items[i2]);
       }
    }
  }

  this.adjustItemDistance=function(item1, item2)
  {
    var targetDistance=this.aid[item1.idx][item2.idx];
    if(targetDistance<=0) return;
   
    var dx=item1.x-item2.x;
    var dy=item1.y-item2.y;
   
    var forceFactor = (item1.idx==0) ? this.springForce0 : this.springForce;
   
    var wdx=dx/scaleX;
    var wdy=dy/scaleY;
    var distanceInWindowSpace=Math.sqrt(wdx*wdx+wdy*wdy);
    var force=(targetDistance-distanceInWindowSpace)*forceFactor;
   
    if(item1.idx != 0) {
      item1.speedX+=dx/distanceInWindowSpace*force;
      item1.speedY+=dy/distanceInWindowSpace*force;
    }
   
    item2.speedX-=dx/distanceInWindowSpace*force;
    item2.speedY-=dy/distanceInWindowSpace*force;

  }

  this.repelItems=function(item1, item2)
  {
    var dx=item1.x-item2.x;
    var dy=item1.y-item2.y;
   
    var pf = (item1.idx == 0 ? this.paddingFactor : this.paddingFactor/2);
   
    var extentsSumX=(item1.width +item2.width)*pf;
    var extentsSumY=(item1.height+item2.height)*pf;
   
    var oLeft  =-dx+extentsSumX;
    var oRight = dx+extentsSumX;
    var oTop   =-dy+extentsSumY;
    var oBottom= dy+extentsSumY;
   
    var no_overlap = oLeft<0 || oRight<0 || oTop<0 || oBottom<0;
    if (repel>0 && !no_overlap) {
      var oMin=positiveMin(Array(oLeft, oRight, oTop, oBottom));
      var distance=Math.sqrt(dx*dx+dy*dy);
      var repelScaler=repel*oMin/distance;
      if(item1.idx != 0) {
        item1.x+=dx*repelScaler;
        item1.y+=dy*repelScaler;
      }
      item2.x-=dx*repelScaler;
      item2.y-=dy*repelScaler;
    }
  }

  this.layoutStep = function ()
  {
    log("LS:"+cycle);
    var thisMap=this;
    this.layoutItems();
    this.recenterItems();
    this.updateItems();
   
    if (damper<this.damperMax)    damper=damper*this.damperFactor;
    if (cycle>this.repelDelay && repel<this.repelMax) repel+=this.repelIncrease;
    if (cycle>this.slowdownCycle) this.gm_frameDelay++;
    
    if(cycle++ == 100) {
      this.finishFn();
      return;
    }
    
    this.gm_timeout =
            setTimeout(function(){thisMap.layoutStep()}, this.gm_frameDelay); 
  }

  this.meanTargetCenterDistance = function()
  {
    var r=0;
    for(var i1=1; i1<nrItems; i1++)
      r += this.aid[i1][0];
    r /= (nrItems-1);
    return r;
  }

  function
  search(needle, haystack)
  {
    var low=0;
    var high=haystack.length-1;
   
    while (low<=high)
    {
     var mid   = parseInt((low+high)/2);
     var value = haystack[mid];
   
     if      (value>needle) high=mid-1;
     else if (value<needle) low =mid+1;
     else    return mid;
    }
   
    return -1;
  }

  this.equalizeAid=function()
  {
    var values=new Array();
   
    for (var i=0; i<nrItems; i++)
     for (var j=0; j<nrItems; j++)
      if (this.aid[i][j]>0) values.push(this.aid[i][j]);
   
    values.sort();
   
    for (var i=0; i<nrItems; i++)
     for (var j=0; j<nrItems; j++)
      if (this.aid[i][j]>0)
         this.aid[i][j]= 1-(search(this.aid[i][j], values)/values.length);
  }

  this.init=function ()
  {
    nrItems=this.aid[0].length;
    maxX=this.maxX; maxY=this.maxY;
    minX=this.minX; minY=this.minY;
   
    this.equalizeAid();
    this.resetItemPositions();
    this.gm_timeout = setTimeout(function(){gm.layoutStep()},10);
  }
}
