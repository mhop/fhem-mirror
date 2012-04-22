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
Slider(slider, min, stp, max)
{
  var sh = slider.firstChild;
  var lastX=-1, offX=-1, minX, maxX, val=-1;

  sh.onselectstart = function() { return false; }
  sh.onmousedown = function(e) {
    var oldMoveFn = document['onmousemove'];
    var oldUpFn = document['onmouseup'];

    if(offX == -1) {
      minX = offX = slider.offsetLeft;
      maxX = minX+slider.offsetWidth-sh.offsetWidth;
    }
    lastX = e.clientX;

    document['onmousemove'] = function(e) {
      var diff = e.clientX-lastX; lastX = e.clientX;
      offX += diff;
      if(offX < minX) offX = minX;
      if(offX > maxX) offX = maxX;
      val = min+((offX-minX)/(maxX-minX) * (max-min));
      val = Math.floor(Math.floor(val/stp)*stp);
      sh.innerHTML = val;
      sh.setAttribute('style', 'left:'+offX+'px;');
    }

    document.onmouseup = function(e) {
      document['onmousemove'] = oldMoveFn;
      document['onmouseup'] = oldUpFn;
      slider.nextSibling.setAttribute('value', val);
    };
  };

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
      Slider(newEl.firstChild, min, stp, max);

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
