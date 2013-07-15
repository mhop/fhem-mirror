function
FW_timeSet(el,name,val)
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
FW_timeCreate(el,cmd)
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
                      ' cmd="js:FW_timeSet(slider,'+i+',%)"'+
                      '><div class="handle">'+val[i]+
                   '</div></div>';
    par.appendChild(sl);
    sl.setAttribute('class', par.getAttribute('class'));

    FW_sliderCreate(sl.firstChild, val[i]);
  }
}

function
FW_timeSelChange(name, devName, vArr)
{
  if(vArr.length != 1 || vArr[0] != "time")
    return undefined;

  var o = new Object();
  o.newEl = document.createElement('div');
  o.newEl.innerHTML='<input name="'+name+'" type="text" size="5">'+
            '<input type="button" value="+" onclick="FW_timeCreate(this)">';
  return o;
}

FW_widgets['time'] = {
  selChange:FW_timeSelChange
};
