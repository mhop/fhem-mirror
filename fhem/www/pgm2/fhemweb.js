/*************** LONGPOLL START **************/
var FW_pollConn;
var FW_curLine; // Number of the next line in FW_pollConn.responseText to parse

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
    var d = lines[i].split("<<", 3);    // Complete arg
    if(d.length != 3)
      continue;
    var el = document.getElementById(d[0]);
    if(el) {
      if(el.nodeName.toLowerCase() == "select") {
        // dropdown: set the selected index to the current value
        for(var j=0;j<el.options.length;j++)
            if(el.options[j].value == d[2]) {
              el.selectedIndex = j;
            }

      } else {
        el.innerHTML=d[2];
        if(d[0].indexOf("-") >= 0)  // readings / timestamps
          el.setAttribute('class', 'changed');

      }
    }

    el = document.getElementById("slider."+d[0]);
    if(el) {
      var doSet = 1;    // Only set the "state" slider in the detail view
      if(el.parentNode.getAttribute("name") == "val.set"+d[0]) {
        var el2 = document.getElementsByName("arg.set"+d[0])[0];
        if(el2.nodeName.toLowerCase() == "select" &&
           el2.options[el2.selectedIndex].value != "state")
          doSet = 0;
      }
      if(doSet) {
        var val = d[1].replace(/^.*?(\d+).*/g, "$1"); // get first number
        if(!val.match(/\d+/))
          val = 0;
        Slider(el, val);
      }
    }
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
  setTimeout("FW_longpoll()", 100);
}
/*************** LONGPOLL END **************/

/*************** SLIDER **************/
function
Slider(slider, curr)
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
setTime(el,name,val)
{
  var el = el.parentNode.parentNode.firstChild;
  var v = el.value.split(":");
  v[name] = ''+val;
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
    sl.innerHTML = '<div class="slider" min="0" stp='+(i==0?1:5)+
                      ' max='+(i==0?23:55)+
                      ' cmd="js:setTime(slider,'+i+',%)"'+
                      '><div class="handle">'+val[i]+
                   '</div></div>';
    par.appendChild(sl);
    sl.setAttribute('class', par.getAttribute('class'));

    Slider(sl.firstChild, val[i]);
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
    cmd = l[i];
    var off = l[i].indexOf(":");
    if(off >= 0)
      cmd = l[i].substring(0, off);
    if(cmd == sel) {
      if(off >= 0)
        value = l[i].substring(off+1);
    }
  }
  var el = document.getElementsByName(elName)[0];
  var name = el.getAttribute('name');

  var qFn, qArg;
  var devName="";
  if(elName.indexOf("val.attr")==0) devName = elName.substring(8);
  if(elName.indexOf("val.set")==0) devName = elName.substring(7);

  if(value==undefined) {
    newEl = document.createElement('input');
    newEl.type='text'; newEl.size=30; 
    qFn = 'qArg.setAttribute("value", "%")';
    qArg = newEl;


  } else {
    var vArr = value.split(","); 
    if(vArr.length == 4 && vArr[0] == "slider") {
      var min=parseFloat(vArr[1]),
          stp=parseFloat(vArr[2]),
          max=parseFloat(vArr[3]);
      newEl = document.createElement('div');
      newEl.innerHTML=
        '<div class="slider" id="slider.'+devName+'" min="'+min+'" stp="'+stp+
                  '" max="'+max+'"><div class="handle">'+min+'</div></div>'+
        '<input type="hidden" name="'+name+'" value="'+min+'">';
      Slider(newEl.firstChild, undefined);
      qFn = 'FW_querySetSlider(qArg, "%")';
      qArg = newEl.firstChild;

    } else if(vArr.length == 1 && vArr[0] == "time") {
      newEl = document.createElement('div');
      newEl.innerHTML='<input name="'+name+'" type="text" size="5">'+
              '<input type="button" value="+" onclick="addTime(this)">';

    } else {
      newEl = document.createElement('select');
      for(var j=0; j < vArr.length; j++) {
        newEl.options[j] = new Option(vArr[j], vArr[j]);
      }
      qFn = 'FW_querySetSelected(qArg, "%")';
      qArg = newEl;
    }


  }

  newEl.setAttribute('class', el.getAttribute('class'));
  newEl.setAttribute('name', name);
  el.parentNode.replaceChild(newEl, el);

  if((typeof qFn == "string")) {
    if(elName.indexOf("val.attr")==0)
      FW_queryValue('{AttrVal("'+devName+'","'+sel+'","")}', qFn, qArg);
    if(elName.indexOf("val.set")==0)
      FW_queryValue('{ReadingsVal("'+devName+'","'+sel+'","")}', qFn, qArg);
  }
}


/*************** Fill attribute **************/
function
FW_queryValue(cmd, qFn, qArg)
{
  var qConn = new XMLHttpRequest();
  qConn.onreadystatechange = function() {
    if(qConn.readyState != 3)
      return;
    var qResp = qConn.responseText.replace(/[\r\n]/g, "")
                                  .replace(/"/g, "\\\"");
    eval(qFn.replace("%", qResp));
    delete qConn;
  }
  qConn.open("GET", document.location.pathname+"?cmd="+cmd+"&XHR=1", true);
  qConn.send(null);
}


function
FW_querySetSelected(el, val)
{
  for(var j=0;j<el.options.length;j++)
    if(el.options[j].value == val)
      el.selectedIndex = j;
}

function
FW_querySetSlider(el, val)
{
  val = val.replace(/[^\d\.]/g, ""); // remove non numbers
  Slider(el, val);
}
