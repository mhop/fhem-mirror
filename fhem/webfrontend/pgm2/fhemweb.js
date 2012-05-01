/*************** LONGPOLL START **************/
var FW_pollConn;

function
FW_cmd(arg)     /* see also FW_devState */
{
  var req = new XMLHttpRequest();
  req.open("GET", arg, true);
  req.send(null);
}

function
FW_doUpdate()
{
  if(FW_pollConn.readyState != 4 || FW_pollConn.status != 200)
    return;
  var lines = FW_pollConn.responseText.split("\n");
  for(var i=0; i < lines.length; i++) {
    var d = lines[i].split(";", 3);    // Complete arg
    if(d.length != 3)
      continue;
    var el = document.getElementById(d[0]);
    if(el)
      el.innerHTML=d[2];
  }
  FW_pollConn.abort();
  FW_longpoll();
}

function
FW_longpoll()
{
  FW_pollConn = new XMLHttpRequest();
  var room="room=all";
  var sa = document.location.search.substring(1).split("&");
  for(var i = 0; i < sa.length; i++) {
    if(sa[i].substring(0,5) == "room=")
      room=sa[i];
  }
  var query = document.location.pathname+"?"+room+"&XHR=1&inform=1";
  FW_pollConn.open("GET", query, true);
  FW_pollConn.onreadystatechange = FW_doUpdate;
  FW_pollConn.send(null);
}

function
FW_delayedStart()
{
  setTimeout("FW_longpoll()", 1000);
}
/*************** LONGPOLL END **************/

/*************** SLIDER **************/
function
Slider(slider, min, stp, max, curr, cmd)
{
  var sh = slider.firstChild;
  var lastX=-1, offX=0, maxX=0, val=-1;

  function
  init()
  {
    maxX = slider.offsetWidth-sh.offsetWidth;
    if(curr) {
      offX += curr*maxX/(max-min);
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
    }
    document.onmousemove = mouseMove;
    document.ontouchmove = function(e) { touchFn(e, mouseMove); }

    document.onmouseup = document.ontouchend = function(e)
    {
      document.onmousemove = oldFn1; document.onmouseup  = oldFn2;
      document.ontouchmove = oldFn3; document.ontouchend = oldFn4;
      if(cmd) {
        document.location = cmd.replace('%',val);
      } else {
        slider.nextSibling.setAttribute('value', val);
      }
    };
  };

  sh.onselectstart = function() { return false; }
  sh.onmousedown = mouseDown;
  sh.ontouchstart = function(e) { touchFn(e, mouseDown); }

}


/*************** Select **************/
/** Change attr/set argument type to input:text or select **/
function
FW_selChange(sel, list, elName)
{
  var value;
  var l = list.split(" ");
  for(var i=0; i < l.length; i++) {
    var nv = l[i].split(":",2);
    if(nv[0] == sel) {
      value = nv[1]; break;
    }
  }

  var el = document.getElementsByName(elName)[0];
  var name = el.getAttribute('name');

  if(value==undefined) {
    newEl = document.createElement('input');
    newEl.type='text'; newEl.size=30; 

  } else {
    var vArr = value.split(","); 
    if(vArr.length == 4 && vArr[0] == "slider") {
      var min=parseFloat(vArr[1]),
          stp=parseFloat(vArr[2]),
          max=parseFloat(vArr[3]);
      newEl = document.createElement('div');
      newEl.innerHTML=
        '<div class="slider"><div class="handle">'+min+'</div></div>'+
        '<input type="hidden" name="'+name+'" value="'+min+'">';
      Slider(newEl.firstChild, min, stp, max, undefined, undefined);

    } else {
      newEl = document.createElement('select');
      for(var j=0; j < vArr.length; j++) {
        newEl.options[j] = new Option(vArr[j], vArr[j]);
      }
    }
  }

  newEl.setAttribute('class', el.getAttribute('class')); //changed from el.class
  newEl.setAttribute('name', el.getAttribute('name'));
  el.parentNode.replaceChild(newEl, el);

}
