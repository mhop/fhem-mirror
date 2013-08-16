/*************** SLIDER **************/
function
FW_sliderUpdateLine(d)
{
  for(var k=0; k<2; k++) {
    var name = "slider."+d[0];
    if(k == 1)
      name = name+"-"+d[1].replace(/[ \d].*$/,'');
    el = document.getElementById(name);
    if(el) {
      var doSet = 1;    // Only set the "state" slider in the detail view
      if(el.parentNode.getAttribute("name") == "val.set"+d[0]) {
        var el2 = document.getElementsByName("arg.set"+d[0])[0];
        if(el2.nodeName.toLowerCase() == "select" &&
           el2.options[el2.selectedIndex].value != "state")
          doSet = 0;
      }

      if(doSet) {
        var val = d[1].replace(/^.*?([.\-\d]+).*/g, "$1"); // get first number
        if(!val.match(/[.\-\d]+/))
          val = 0;
        FW_sliderCreate(el, val);
      }

    }
  }
}

function
FW_sliderCreate(slider, curr)
{
  var sh = slider.firstChild;
  var lastX=-1, offX=0, maxX=0, val=-1;
  var min = parseFloat(slider.getAttribute("min"));
  var stp = parseFloat(slider.getAttribute("stp"));
  var max = parseFloat(slider.getAttribute("max"));
  var cmd = slider.getAttribute("cmd");

  function
  init()
  {
    maxX = slider.offsetWidth-sh.offsetWidth;
    if(curr) {
      offX += (curr-min)*maxX/(max-min);
      sh.innerHTML = curr;
      sh.setAttribute('style', 'left:'+offX+'px;');
    }
  }
  init();

  function
  touchFn(e, fn)
  {
    e.preventDefault(); // Prevents Safari from scrolling!
    if(e.touches == null || e.touches.length == 0)
      return;
    e.clientX = e.touches[0].clientX;
    fn(e);
  }

  function
  mouseDown(e)
  {
    var oldFn1 = document.onmousemove, oldFn2 = document.onmouseup,
        oldFn3 = document.ontouchmove, oldFn4 = document.ontouchend;

    if(maxX == 0)
      init();
    lastX = e.clientX;

    function
    mouseMove(e)
    {
      var diff = e.clientX-lastX; lastX = e.clientX;
      offX += diff;
      if(offX < 0) offX = 0;
      if(offX > maxX) offX = maxX;
      val = min+(offX/maxX * (max-min));
      val = Math.floor(Math.floor(val/stp)*stp);
      sh.innerHTML = val;
      sh.setAttribute('style', 'left:'+offX+'px;');
      if(cmd && cmd.substring(0,3) == "js:") {
        eval(cmd.substring(3).replace('%',val));
      }
    }
    document.onmousemove = mouseMove;
    document.ontouchmove = function(e) { touchFn(e, mouseMove); }

    document.onmouseup = document.ontouchend = function(e)
    {
      document.onmousemove = oldFn1; document.onmouseup  = oldFn2;
      document.ontouchmove = oldFn3; document.ontouchend = oldFn4;
      if(cmd) {
        if(cmd.substring(0,3) != "js:") {
          document.location = cmd.replace('%',val);
        }
      } else {
        slider.nextSibling.setAttribute('value', val);
      }
    };
  };

  sh.onselectstart = function() { return false; }
  sh.onmousedown = mouseDown;
  sh.ontouchstart = function(e) { touchFn(e, mouseDown); }
}


function
FW_sliderSelChange(name, devName, vArr)
{
  if(vArr.length != 4 || vArr[0] != "slider")
    return undefined;

  var o = new Object();
  var min=parseFloat(vArr[1]),
      stp=parseFloat(vArr[2]),
      max=parseFloat(vArr[3]);
  o.newEl = document.createElement('div');
  o.newEl.innerHTML =
    '<div class="slider" id="slider.'+devName+'" min="'+min+'" stp="'+stp+
              '" max="'+max+'"><div class="handle">'+min+'</div></div>'+
    '<input type="hidden" name="'+name+'" value="'+min+'">';
  FW_sliderCreate(o.newEl.firstChild, undefined);

  o.qFn = 'FW_querySetSlider(qArg, "%")';
  o.qArg = o.newEl.firstChild;
  return o;
}

function
FW_querySetSlider(el, val)
{
  val = val.replace(/[^\d.\-]/g, ""); // remove non numbers
  FW_sliderCreate(el, val);
}

FW_widgets['slider'] = {
  updateLine:FW_sliderUpdateLine,
  selChange:FW_sliderSelChange
};
