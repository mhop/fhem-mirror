
function
FW_colorpickerUpdateLine(d)
{
  var name = "colorpicker."+d[0];

  el = document.getElementById(name);

  if(el) {
    if( d[1].length > 6 ) {
      d[1] = d[1].slice(0,6);
    }
    el.color.fromString(d[1]);
  }
}

function
colorpicker_setColor(el,mode,cmd)
{
  var v = el.color;

  if(mode==undefined) {
    mode=el.pickerMode;
  }
  if(cmd==undefined) {
    cmd=el.command;
  }
  if(v==undefined) {
    v=el.toString();
  }

  if(mode=="HSV") {
    v = (0x100 | Math.round(42*el.color.hsv[0])).toString(16).substr(1) +
        (0x100 | Math.round(255*el.color.hsv[1])).toString(16).substr(1) +
        (0x100 | Math.round(255*el.color.hsv[2])).toString(16).substr(1);
  }

  var req = new XMLHttpRequest();
  req.open("GET", cmd.replace('%',v), true);
  req.send(null);

  if( 0 )
  if(cmd)
    document.location = cmd.replace('%',v);
}

FW_widgets['colorpicker'] = {
  updateLine:FW_colorpickerUpdateLine
};

