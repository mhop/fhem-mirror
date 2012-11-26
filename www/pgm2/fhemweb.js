/*************** LONGPOLL START **************/
var FW_pollConn;
//The number of the next line in FW_pollConn.responseText to parse
var FW_curLine;

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
  if(FW_pollConn.readyState == 4) {
    var errdiv = document.createElement('div');
    errdiv.innerHTML = "Connection lost, reconnecting in 5 seconds...";
    errdiv.setAttribute("id","connect_err");
    document.body.appendChild(errdiv);
    setTimeout("FW_longpoll()", 5000);
    return; // some problem connecting
  }

  if(FW_pollConn.readyState != 3)
    return;
  var lines = FW_pollConn.responseText.split("\n");
  //Pop the last (maybe empty) line after the last "\n"
  //We wait until it is complete, i.e. terminated by "\n"
  lines.pop();
  for(var i=FW_curLine; i < lines.length; i++) {
    var d = lines[i].split(";", 3);    // Complete arg
    if(d.length != 3)
      continue;
    var el = document.getElementById(d[0]);
    if(el)
      el.innerHTML=d[2];
  }
  //Next time, we continue at the next line
  FW_curLine = lines.length;
}

function
FW_longpoll()
{
  var errdiv = document.getElementById("connect_err");
  if(errdiv)
    document.body.removeChild(errdiv);

  FW_curLine = 0;

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
  min = parseFloat(min); max = parseFloat(max); stp = parseFloat(stp);

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
setTime(el,name,val)
{
  var el = el.parentNode.parentNode.firstChild;
  var v = el.value.split(":");
  v[name == "H" ? 0 : 1] = ''+val;
  if(v[0].length < 2) v[0] = '0'+v[0];
  if(v[1].length < 2) v[1] = '0'+v[1];
  el.value = v[0]+":"+v[1];
  el.setAttribute('value', el.value);
}

function
addTime(el,cmd)
{
  var par = el.parentNode;
  var v = par.firstChild.value;
  var brOff = par.innerHTML.indexOf("<br>");

  if(brOff > 0) {
    par.innerHTML = par.innerHTML.substring(0, brOff).replace('"-"','"+"');
    if(cmd)
      document.location = cmd.replace('%',v);
    return;
  }

  el.setAttribute('value', '-');
  if(v.indexOf(":") < 0)
    par.firstChild.value = v = "12:00";
  var val = v.split(":");

  for(var i = 0; i < 2; i++) {
    par.appendChild(document.createElement('br'));

    var sl = document.createElement('div');
    sl.innerHTML = '<div class="slider"><div class="handle">'+val[i]+
                   '</div></div>';
    par.appendChild(sl);
    sl.setAttribute('class', par.getAttribute('class'));

    Slider(sl.firstChild, 0, (i==0 ? 1 : 5), (i==0 ? 23 : 55), val[i],
          'js:setTime(slider,"'+(i==0? "H":"M")+'",%)');
  }
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

    } else if(vArr.length == 1 && vArr[0] == "time") {
      newEl = document.createElement('div');
      newEl.innerHTML='<input name="'+name+'" type="text" size="5">'+
              '<input type="button" value="+" onclick="addTime(this)">';

    } else {
      newEl = document.createElement('select');
      for(var j=0; j < vArr.length; j++) {
        newEl.options[j] = new Option(vArr[j], vArr[j]);
      }
    }
  }

  newEl.setAttribute('class', el.getAttribute('class'));
  newEl.setAttribute('name', el.getAttribute('name'));
  el.parentNode.replaceChild(newEl, el);

}
