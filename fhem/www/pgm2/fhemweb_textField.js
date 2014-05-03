function
FW_textFieldUpdateLine(d)
{
  var name = "textField."+d[0];
  el = document.getElementById(name);
  if(el)
    el.value = d[1];
}

function
FW_textFieldSelChange(name, devName, vArr)
{
  if(vArr.length != 1 || vArr[0] != "textField")
    return undefined;
  
  var o = new Object();
  o.newEl = document.createElement('input');
  o.newEl.type='text';
  o.newEl.size=30;
  o.qFn = 'FW_textFieldSetSelected(qArg, "%")';
  o.qArg = o.newEl;
  return o;
}

function
FW_textFieldSetSelected(el, val)
{
  if(typeof el == 'string')
    el = document.getElementById(el);
  el.value=val;
}

function
textField_setText(el,cmd)
{
  var v = el.value;
  var req = new XMLHttpRequest();
  req.open("GET", cmd.replace('%',v), true);
  req.send(null);
}

FW_widgets['textField'] = { 
  updateLine:FW_textFieldUpdateLine,
  selChange:FW_textFieldSelChange
};
