var zw_visible;
var svgns = 'xmlns="http://www.w3.org/2000/svg"';

function
zw_nl(fhemFn)
{
  log("ZWNL called with "+fhemFn);
  zw_visible = !zw_visible;
  var txt = (zw_visible ? 'Hide' : 'Show');

  var width=960,height=480;
  $('#ZWDongleNr').html('<a href="#">'+txt+' neighbor map</a>');

  if(!zw_visible) {
    $("#ZWDongleNrSVG")
        .css({width:0, height:0})
        .html('');
    return;
  }

  FW_cmd(FW_root+"?cmd={"+fhemFn+"}&XHR=1", function(r){
    var xpos=20, ypos=20, fnRet = JSON.parse(r);

    var cnt=0;
    for(var elName in fnRet.el) {
      var el = fnRet.el[elName];
      el.lines = [];
      el.width = el.height = 30;
      if(!el.pos.length) {
        el.pos = [xpos, ypos];
        xpos += 150;
        if(xpos+150 >= width)
          xpos = 20, ypos += 50;
      }
      cnt++;
    }
    if(height < cnt*35)
      height = cnt*35;
    zw_draw(fnRet, width, height);
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
              '<path d="M0,0 L0,12 L18,6 z" class="zwArrowHead" />'+
             '</marker>'+
            '<marker id="startarrow" markerWidth="20" markerHeight="20" '+
                'refx="-50" refy="6" orient="auto" markerUnits="strokeWidth">'+
              '<path d="M18,0 L18,12 L0,6 z" class="zwArrowHead" />'+
             '</marker>'+
          '</defs>';
  svg += '<rect class="zwMargin" x="1" y="1" width="'+
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

  $("svg g").each(function(){
    var name = $(this).attr("data-name");
    var w = $(this).find("text")[0].getBBox().width;
    $(this).find("rect").attr("width",w+10);
    $(this).css({cursor:"pointer", position:"absolute"}); // firefox is relative
    h[name].width = w+10;
    zw_adjustLines(h, name);
  })
  .draggable()
  .bind('mouseup', function(e) {
    var name = $(e.target).parent().attr("data-name");
    if(fnRet.saveFn)
      FW_cmd(FW_root+"?cmd="+sprintf(fnRet.saveFn, name, 
                                h[name].pos[0]+","+h[name].pos[1])+"&XHR=1");
  })
  .bind('mousedown', function(e) {
    o = h[$(e.target).parent().attr("data-name")];
    ox = o.pos[0]; oy = o.pos[1];
  })
  .bind('drag', function(e, ui) {
    var rect = $(e.target).find("rect"),
        text = $(e.target).find("text"),
        p = ui.position; op = ui.originalPosition;
    o.pos[0] = ox + (p.left-op.left);
    o.pos[1] = oy + (p.top -op.top);
    $(rect).attr("x", o.pos[0]); $(rect).attr("y", o.pos[1]);
    $(text).attr("x", o.pos[0]+5); $(text).attr("y", o.pos[1]+20);
    zw_adjustLines(h, o.txt);
  });
}

function
zw_drawbox(o)
{
  var s = '<g data-name="'+o.txt+'">'+
            '<rect x="'+o.pos[0]+'" y="'+o.pos[1]+'" rx="5" ry="5" '+
              'width="'+o.width+'" height="'+o.height+'" class="'+o.class+'"/>';
  s += '<text x="'+(o.pos[0]+5)+'" y="'+(o.pos[1]+20)+'">'+o.txt+'</text></g>';
  return s;
}

function
zw_calcPos(o, n)
{
  return { x: o.pos[0]+o.width/2, y: o.pos[1]+o.height/2 };
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
  return '<line class="zwLine" data-name="'+cl+
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
  for(var i1=0; i1< la.length; i1++) {
    var se = la[i1].split('-');
    if(la[i1].indexOf(name) == 0) {     // we are the from line
      var p = zw_calcPos(h[se[0]], h[se[1]]);
      $("svg line[data-name="+la[i1]+"]")
        .attr("x1", p.x)
        .attr("y1", p.y);
    } else {
      var p = zw_calcPos(h[se[1]], h[se[0]]);
      $("svg line[data-name="+la[i1]+"]")
        .attr("x2", p.x)
        .attr("y2", p.y);
    }
    if (navigator.appVersion.indexOf("Trident") != -1) {
      var svgNode = $("svg line[data-name="+la[i1]+"]")[0];
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
