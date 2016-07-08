var zw_visible;
var svgns = 'xmlns="http://www.w3.org/2000/svg"';

function
zw_nr(dev, dpos)
{
  log("ZWNR called for "+dev+": "+zw_visible);
  zw_visible = !zw_visible;
  var txt = (zw_visible ? 'Hide' : 'Show');

  var width=720,height=480;
  $('#ZWDongleNr')
        .html('<a href="#">'+txt+' neighbor list</a>');

  if(!zw_visible) {
    $("#ZWDongleNrSVG")
        .css({width:0, height:0})
        .html('');
    return;
  }

  var h={}, ldev, xpos=20, ypos=20; 
  var dp = dpos.split(",");
        
  h[dev] = { txt:dev, pos:[ parseInt(dp[0]), parseInt(dp[1]) ], lines:[], 
             width:40, height:30 };

  var cmd = FW_root+"?cmd=list ZWaveSubDevice=no,FILTER=IODev="+dev+
                            " neighborList timeToAck neighborListPos&XHR=1";
  FW_cmd(cmd, function(r){
    console.log(r);
    var la = r.split("\n");
    for(var i1=0; i1<la.length; i1++) {
      var cols = la[i1].split(/ +/);
      if(cols[0] != '')
        ldev = cols[0];
      if(cols[1] == 'neighborListPos') {
        var p = cols[2].split(",");
        h[ldev].pos = [ parseInt(p[0]), parseInt(p[1]) ];

      } else if(cols[3] == 'timeToAck') {
        // h[ldev].txt += ' ('+cols[4]+')';

      } else if(cols[3] == 'neighborList') {
        cols.splice(0,4);
        h[ldev] = { txt:ldev, neighbors:cols,pos:[xpos,ypos], lines:[],
                    width:40, height:30 };
        xpos += 150;
        if(xpos >= width) {
          xpos = 20; ypos += 50;
        }

      }
    }
    zw_draw(h, width, height);
  });
}

function
zw_draw(h, width, height)
{
  var svg = '<svg '+svgns+' style="width:'+width+';height:'+height+'" '+
                  'class="zw_nr" viewBox="0 0 '+width+' '+height+'">';
  svg += '<rect class="zwMargin" x="1" y="1" width="'+
                (width-1)+'" height="'+(height-1)+'"/>';
  var ld={};

  for(var o in h) {
    if(h[o].txt && h[o].neighbors)
      for(var i1=0; i1<h[o].neighbors.length; i1++)
        svg += zw_drawline(ld, h, o, h[o].neighbors[i1]);
  }
  for(var o in h)
    if(h[o].txt)
      svg += zw_drawbox(h[o]);

  svg += '</svg>';

  var ox, oy, o;
  $("#ZWDongleNrSVG")
    .css({width:width, height:height})
    .html(svg);

  $("svg g").each(function(){
    var w = $(this).find("text").width();
    $(this).find("rect").attr("width",w+10);
    $(this).css("cursor", "pointer");
    var name = $(this).attr("data-name");
    h[name].width = w+10;
    zw_adjustLines(h, name);
  })
  .draggable()
  .bind('mouseup', function(e) {
    var name = $(e.target).parent().attr("data-name");
    FW_cmd(FW_root+"?cmd=attr "+name+" neighborListPos "+
                h[name].pos[0]+","+h[name].pos[1]+"&XHR=1");
  })
  .bind('mousedown', function(e) {
    o = h[$(e.target).parent().attr("data-name")];
    ox = o.pos[0]; oy = o.pos[1];
  })
  .bind('drag', function(e, ui) {
    var rect = $(e.target).find("rect"),
        text = $(e.target).find("text"),
        p = ui.position; op = ui.originalPosition;
    o.pos[0] = ox + (p.left-op.left);
    o.pos[1] = oy + (p.top -op.top);
    $(rect).attr("x", o.pos[0]); $(rect).attr("y", o.pos[1]);
    $(text).attr("x", o.pos[0]+5); $(text).attr("y", o.pos[1]+20);
    zw_adjustLines(h, o.txt);
  });
}

function
zw_drawbox(o)
{
  var s = '<g data-name="'+o.txt+'">'+
            '<rect x="'+o.pos[0]+'" y="'+o.pos[1]+'" rx="5" ry="5" '+
                'width="'+o.width+'" height="'+o.height+'" class="zwBox"/>';
  s += '<text x="'+(o.pos[0]+5)+'" y="'+(o.pos[1]+20)+'">'+o.txt+'</text></g>';
  return s;
}

function
zw_drawline(ld, h, o, n)
{
  if(n < o) {
    var t = n; n = o; o = t;
  }
  var cl = o+"-"+n;
  if(ld[cl] || !h[o] || !h[n])
    return;
  ld[cl] = 1;
  h[o].lines.push(cl);
  h[n].lines.push(cl);
  var fr = zw_calcPos(h[o], h[n]);
  var to = zw_calcPos(h[n], h[o]);
  return '<line class="zwLine" data-name="'+cl+
               '" x1="'+fr.x+'" y1="'+fr.y+
               '" x2="'+to.x+'" y2="'+to.y+'"/>';
}

function
zw_calcPos(o, n)
{
  return { x: o.pos[0]+o.width/2, y: o.pos[1]+o.height/2 };
}

function
zw_adjustLines(h, name)
{
  var la = h[name].lines;
  for(var i1=0; i1< la.length; i1++) {
    var se = la[i1].split('-');
    if(la[i1].indexOf(name) == 0) {     // we are the from line
      var p = zw_calcPos(h[se[0]], h[se[1]]);
      $("svg line[data-name="+la[i1]+"]")
        .attr("x1", p.x)
        .attr("y1", p.y);
    } else {
      var p = zw_calcPos(h[se[1]], h[se[0]]);
      $("svg line[data-name="+la[i1]+"]")
        .attr("x2", p.x)
        .attr("y2", p.y);
    }
  }
}
