
function
FW_colorpickerUpdateLine(d)
{
  el = document.getElementById(name);

  if(el) {
    el.setAttribute('value', '#d');
  }
}

function
colorpicker_setColor(el,mode,cmd)
{
  var v = el.color;
  if(mode=="HSV") {
    v = (0x100 | Math.round(42*el.color.hsv[0])).toString(16).substr(1) +
        (0x100 | Math.round(255*el.color.hsv[1])).toString(16).substr(1) +
        (0x100 | Math.round(255*el.color.hsv[2])).toString(16).substr(1);
  }
  if(cmd)
    document.location = cmd.replace('%',v);
}

FW_widgets['colorpicker'] = { 
  updateLine:FW_colorpickerUpdateLine
};

