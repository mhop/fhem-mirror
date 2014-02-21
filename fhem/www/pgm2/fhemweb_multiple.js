function
FW_multipleSelChange(name, devName, vArr)
{
  if(vArr.length < 2 || vArr[0] != "multiple")
    return undefined;

  var o = new Object();
  o.newEl = document.createElement('select');
  o.newEl.setAttribute('multiple', true);
  for(var j=1; j < vArr.length; j++) {
    o.newEl.options[j-1] = new Option(vArr[j], vArr[j]);
  }
  o.qFn = 'FW_multipleSetSelected(qArg, "%")';
  o.qArg = o.newEl;
  return o;
}

function
FW_multipleSetSelected(el, val)
{
  if(typeof el == 'string')
    el = document.getElementById(el);

    var l = val.split(",");
    for(var j=0;j<el.options.length;j++)
      for(var i=0;i<l.length;i++)
        if(el.options[j].value == l[i])
           el.options[j].selected = true;
         
    if(el.onchange)
      el.onchange();
}

FW_widgets['multiple'] = {
  selChange:FW_multipleSelChange
};
