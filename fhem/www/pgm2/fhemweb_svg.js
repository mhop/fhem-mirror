function
FW_svgUpdateDevs(devs)
{
  // if matches, refresh the SVG by removing and readding the embed tag
  var embArr = document.getElementsByTagName("embed");
  for(var i = 0; i < embArr.length; i++) {
    var svg = embArr[i].getSVGDocument();
    if(svg == null) // too many events sometimes.
      continue;
    svg = svg.firstChild.nextSibling;
    var flog = svg.getAttribute("flog");
    for(var j=0; j < devs.length; j++) {
      if(flog !== null && flog.match(" "+devs[j]+" ")) {
        var e = embArr[i];
        var newE = document.createElement("embed");
        for(var k=0; k<e.attributes.length; k++)
          newE.setAttribute(e.attributes[k].name, e.attributes[k].value);
        e.parentNode.insertBefore(newE, e);
        e.parentNode.removeChild(e);
        break;
      }
    }
  }
}

FW_widgets['SVG'] = {
  updateDevs:FW_svgUpdateDevs,
};
