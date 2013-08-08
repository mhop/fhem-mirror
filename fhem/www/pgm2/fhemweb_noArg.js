function
FW_noArgSelChange(name, devName, vArr)
{
  if(vArr.length != 1 || vArr[0] != "noArg")
    return undefined;

  var o = new Object();
  o.newEl = document.createElement('div');
  return o;
}

FW_widgets['noArg'] = {
  selChange:FW_noArgSelChange
};
