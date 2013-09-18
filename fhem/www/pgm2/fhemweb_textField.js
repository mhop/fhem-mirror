
function
FW_textFieldUpdateLine(d)
{
  var name = "textField."+d[0];
  //console.log("Cmd "+d);

  el = document.getElementById(name);

  if(el) {
    el.value = d[1];
  }
 
}

function
textField_setText(el,cmd)
{
  var v = el.value;
  //console.log("Got "+v);
  //console.log("Cmd "+cmd);

  var req = new XMLHttpRequest();
  req.open("GET", cmd.replace('%',v), true);
  req.send(null);
}

FW_widgets['textField'] = { 
  updateLine:FW_textFieldUpdateLine
};

