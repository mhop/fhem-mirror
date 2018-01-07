/*
  - style FW_okDialog
  - SVG width on mobile
  - FLOORPLAN
  - Dashboard
 */

var f18_attr, f18_aCol, f18_pinOut, f18_sd, f18_isMobile;
var f18_small = (screen.width < 480 || screen.height < 480);
// font-awesome: map-pin
var f18_pinIn='data:image/svg+xml;utf8,<svg viewBox="0 0 1792 1792" xmlns="http://www.w3.org/2000/svg"><path fill="gray" d="M896 1088q66 0 128-15v655q0 26-19 45t-45 19h-128q-26 0-45-19t-19-45v-655q62 15 128 15zm0-1088q212 0 362 150t150 362-150 362-362 150-362-150-150-362 150-362 362-150zm0 224q14 0 23-9t9-23-9-23-23-9q-146 0-249 103t-103 249q0 14 9 23t23 9 23-9 9-23q0-119 84.5-203.5t203.5-84.5z"/></svg>';

$(window).resize(f18_resize);
$(document).ready(function(){
  f18_sd = $("body").attr("data-styleData");
  if(f18_sd) {
    eval("f18_sd="+f18_sd);
    if(!f18_sd)
      f18_sd = {};
    f18_attr = f18_sd.f18;
  }
  if(!f18_attr) {
    f18_attr = { "Pinned.menu":"true" };
    f18_resetCol();
    f18_sd.f18 = f18_attr;
  }

 f18_setCss();

 var icon = FW_root+"/images/default/fhemicon_ios.png";
  $('head').append(
    '<meta name="viewport" content="initial-scale=1.0,user-scalable=1">'+
    '<meta name=      "mobile-web-app-capable" content="yes">'+
    '<meta name="apple-mobile-web-app-capable" content="yes">'+
    '<link rel="apple-touch-icon" href="'+icon+'">');
  if('ontouchstart' in window)                  $("body").addClass('touch');
  if(f18_small)
    $("body").addClass('small');


  f18_aCol = getComputedStyle($("a").get(0),null).getPropertyValue('color'); 
  f18_pinIn  = f18_pinIn.replace('gray', f18_aCol);
  f18_pinOut = f18_pinIn.replace('/>',' transform="rotate(90,896,896)"/>');

  if(f18_attr.hideLogo) {
    $("div#menuScrollArea div#logo").css("display", "none");
    $("#hdr").css("left", f18_small ? "10px":"54px");
  }
  f18_menu();
  f18_tables();
  f18_svgSetCols();
});

function
f18_menu()
{
  // font-awesome: bars
  var bars='data:image/svg+xml;utf8,<svg viewBox="0 0 1792 1792" xmlns="http://www.w3.org/2000/svg"><path fill="gray" d="M1664 1344v128q0 26-19 45t-45 19h-1408q-26 0-45-19t-19-45v-128q0-26 19-45t45-19h1408q26 0 45 19t19 45zm0-512v128q0 26-19 45t-45 19h-1408q-26 0-45-19t-19-45v-128q0-26 19-45t45-19h1408q26 0 45 19t19 45zm0-512v128q0 26-19 45t-45 19h-1408q-26 0-45-19t-19-45v-128q0-26 19-45t45-19h1408q26 0 45 19t19 45z"/></svg>'
        .replace('gray', f18_aCol);
  $("<div id='menuBtn'></div>").prependTo("div#menuScrollArea")
    .css( {"background-image":"url('"+bars+"')", "cursor":"pointer" })
    .click(function(){ $("div#menu").toggleClass("visible") });

  $("div#menu").prepend("<div></div>");
  f18_addPin("div#menu > div:first", "menu", true, fixMenu, f18_small);
  setTimeout(function(){ $("div#menu,div#content").addClass("animated"); }, 10);

  function
  fixMenu(isFixed) {
    if(isFixed) {
      $("div#content").css("left", (parseInt($("div#menu").width())+20)+"px");
      $("div#menu").addClass("visible");
      $("div#hdr").css("left", "10px");
      $("div#menuBtn").hide();
      if(!f18_small)
        $("div#logo").css("left", "10px");
    } else {
      $("div#content").css("left", "10px"); 
      $("div#menu").removeClass("visible");
      if(!f18_small)
        $("div#logo").css("left", "52px");
      $("div#menuBtn").show();
    }
    f18_resize();
  }
}

function
f18_tables()
{
  $("table.roomoverview > tbody > tr > td > .devType:not(:first)")
      .css("margin-top", "20px"); 
  $("table.column tbody tr:not(:first-child) .devType")
      .css("margin-top", "20px"); 

  $("#content .devType").each(function(){
    var el = this, grp = $(el).text();
    f18_addPin(el, "room."+FW_urlParams.room+".grp."+grp, true,
    function(isFixed){
      var ntr = $(el).closest("tr").next("tr");
      isFixed ? $(ntr).show() : $(ntr).hide();
    });
  });

  if(FW_urlParams.detail) {
    $("div.makeTable > span").each(function(){
      var el = this, grp = $(el).text();
      var nel = $("<div>"+grp+"</div>");
      $(el).replaceWith(nel);
      f18_addPin(nel, "detail."+grp, true,
      function(isFixed){
        var ntr = $(nel).next("table");
        isFixed ? $(ntr).show() : $(ntr).hide();
      });
    });
  }

  if(FW_urlParams.cmd == "style%20select") {
    var row=0;

    function
    addRow(name, desc, val)
    {
      $("table.colors")
        .append("<tr class='"+name+" "+(++row%2 ? "even":"odd")+"'>"+
                  "<td "+(val ? "" : "colspan='2'")+">"+
                        "<div class='col1'>"+desc+"</div></td>"+
                  (val ? "<td><div class='col2'>"+val+"</div></div></td>" : '')+
                "</tr>");
    }

    function
    addHider(name, desc, fn)
    {
      addRow(name, desc, "<input type='checkbox'>");
      $("table.colors tr."+name+" input")
        .prop("checked", f18_attr[name])
        .click(function(){
          var c = $(this).is(":checked");
          f18_setAttr(name, c);
          fn(c);
        });
    }

    function
    addColorChooser(name, desc)
    {
      addRow(name, desc, "<div class='cp'></div>");
      FW_replaceWidget("table.colors tr."+name+" div.col2 div.cp", name,
        ["colorpicker","RGB"], f18_attr.cols[name], name, "rgb", undefined,
        function(value) {
          f18_attr.cols[name] = value;
          f18_setAttr();
          f18_setCss();
        });
    }


    $("div#content > table").append("<tr class='f18'></tr>");

    $("tr.f18").append("<div class='fileList f18colors'>f18 special</div>");
    $("div.f18colors").css("margin-top", "20px");
    $("tr.f18").append("<table class='block wide colors'></table>");

    loadScript("pgm2/fhemweb_colorpicker.js", addColors);

    function
    addColors()
    {
      $("table.colors")
        .append("<tr class='reset' "+(++row%2 ? "even":"odd")+"'>"+
                  "<td colspan='2'><div class='col1'>Preset colors: "+
                     "<a href='#'>default</a> "+
                     "<a href='#'>light</a> "+
                     "<a href='#'>dark</a> "+
                  "</div></td>"+
                "</tr>");
      $("table.colors tr.reset a").click(function(){
        row = 0;
        $("table.colors").html("");
        f18_resetCol($(this).text());
        f18_setCss();
        f18_setAttr();
        addColors();
      });
      addColorChooser("bg",      "Background");
      addColorChooser("fg",      "Foreground");
      addColorChooser("link",    "Link");
      addColorChooser("evenrow", "Even row");
      addColorChooser("oddrow",  "Odd row");
      addColorChooser("header",  "Header row");
      addColorChooser("menu",    "Menu");
      addColorChooser("sel",     "Menu/Selected");
      addColorChooser("inpBack", "Input bg");
      $("table.colors input").attr("size", 8);
      addRow("empty", "&nbsp;");
      addHider("hidePin", "Hide pin", function(c){
        $("div.pinHeader div.pin").css("display", c ? "none":"block");
      });
      addHider("hideLogo", "Hide logo", function(c){
        $("div#menuScrollArea div#logo").css("display", c ? "none":"block");
        f18_resize();
      });
    }
  }

  if(FW_urlParams.cmd == "style%20list" ||
     FW_urlParams.cmd == "style%20select") {
    $("div.fileList").each(function(){
      var el = this, grp = $(el).text();
      f18_addPin(el, "style.list."+grp, true,
      function(isFixed){
        var ntr = $(el).next("table");
        isFixed ? $(ntr).show() : $(ntr).hide();
      });
    });
  }
}

function
f18_resize()
{
  var w=$(window).width();
  log("W:"+w+" S:"+screen.width);

  var diff = 0
  diff += f18_attr.hideLogo ? 0 : 40;
  diff += f18_attr["Pinned.menu"] ? 0 : 44;
  $("input.maininput").css("width", (w-(FW_isiOS ? 40 : 30)-diff)+'px');
  if(f18_small)
    diff -= 44
  $("#hdr").css("left",(10+diff)+"px");

}

function
f18_addPin(el, name, defVal, fn, hidePin)
{
  var init = f18_attr["Pinned."+name];
  if(init == undefined)
    init = defVal;
  $("<div class='pin'></div>")
    .appendTo(el)
    .css("background-image", "url('"+(init ? f18_pinIn : f18_pinOut)+"')");
  $(el).addClass("col_header pinHeader "+name.replace(/[^A-Z0-9]/ig,'_'));
  el = $(el).find("div.pin");
  $(el)
    .addClass(init ? "pinIn" : "")
    .css("cursor", "pointer")
    .css("display", (f18_attr.hidePin || hidePin) ? "none" : "block")
    .click(function(){
      var nextVal = !$(el).hasClass("pinIn");
      $(el).toggleClass("pinIn");
      $(el).css("background-image","url('"+(nextVal ?f18_pinIn:f18_pinOut)+"')")
      f18_setAttr("Pinned."+name, nextVal);
      fn(nextVal);
    });
  fn(init);
}


function
f18_setAttr(name, value)
{
  if(name)
    f18_attr[name]=value;
  var wn = $("body").attr("data-webName");
  FW_cmd(FW_root+"?cmd=attr "+wn+" styleData "+
        encodeURIComponent(JSON.stringify(f18_sd, null, 2))+"&XHR=1");
}

function
f18_resetCol(name)
{
  var cols = {
    "default":{ bg:     "FFFFE7", fg:    "000000", link:   "278727", 
                evenrow:"F8F8E0", oddrow:"F0F0D8", header: "E0E0C8",
                menu:   "D7FFFF", sel:   "A0FFFF", inpBack:"FFFFFF" },
    light:    { bg:     "F8F8F8", fg:    "465666", link:   "4C9ED9",
                evenrow:"E8E8E8", oddrow:"F0F0F0", header: "DDDDDD",
                menu:   "EEEEEE", sel:   "CAC8CF", inpBack:"FFFFFF" },
    dark:     { bg:     "444444", fg:    "CCCCCC", link:   "FF9900",
                evenrow:"333333", oddrow:"111111", header: "222222",
                menu:   "111111", sel:   "333333", inpBack:"444444" }
  };
  f18_attr.cols = name ? cols[name] : cols["default"];
}

function
f18_setCss()
{
  var cols = f18_attr.cols;
  var style = "";
  function bg(c) { return "{ background:#"+c+"; fill:#"+c+"; }\n" }
  function fg(c) { return "{ color:#"+c+"; }\n" }
  style += ".col_fg, body, input "+fg(cols.fg);
  style += ".col_bg, body, #menu, input, option "+bg(cols.bg);
  style += ".col_fg, body, input { color:#"+cols.fg+"; }\n";
  style += ".col_link, a, .handle, .fhemlog, input[type=submit], select "+
                 "{color:#"+cols.link+"; stroke:#"+cols.link+";}\n";
  style += "svg:not([fill]):not(.jssvg) { fill:#"+cols.link+"; }\n";
  style += ".col_evenrow, table.block,div.block "+bg(cols.evenrow);
  style += ".col_oddrow,table.block tr.odd,table.block tr.sel "+bg(cols.oddrow);
  style += ".col_header "+bg(cols.header);
  style += ".col_menu, table.room "+bg(cols.menu);
  style += ".col_sel, table.room tr.sel "+bg(cols.sel);
  style += ".col_inpBack, input "+bg(cols.inpBack);
  if(cols.bg == "FFFFE7") // default
    style += "div.pinHeader.menu {background:#"+cols.sel+";}\n";

  style += "div.ui-dialog-titlebar "+bg(cols.header);
  style += "div.ui-widget-content "+bg(cols.bg);
  style += "div.ui-widget-content, .ui-button-text "+fg(cols.fg+"!important");
  style += "div.ui-dialog { border:1px solid #"+cols.link+"; }";
  style += "button.ui-button { background:#"+cols.oddrow+"!important; "+
                              "border:1px solid #"+cols.link+"!important; }\n";

  $("head style.f18").remove();
  $("head").append("<style class='f18'>"+style+"</style>");
}

var dbg;
function
f18_svgSetCols()
{
  $("body embed").each(function(){
    this.addEventListener('load', function(){
      var svg = FW_getSVG(this);
      if(svg.contentType != "image/svg+xml")
        return;
      if(!svg || !svg.firstChild || !svg.firstChild.nextSibling)
        return;
      svg = svg.firstChild.nextSibling;
      if(!svg.getAttribute("data-origin"))
        return;


      var style = $(svg).find("> style").first();
      var sTxt = $(style).text();
      var cols = f18_attr.cols;
      sTxt = sTxt.replace(/font-family:Times/, "fill:#"+cols.fg);
      $(style).text(sTxt);

      function
      addCol(c, d)
      {
        var r="";
        for(var i1=0; i1<6; i1+=2) {
          var n = parseInt(c.substr(i1,2), 16);
          n += d;
          if(n>255) n = 255;
          if(n<  0) n = 0;
          n = n.toString(16);
          if(n.length < 2)
            n = "0"+length;
          r += n;
        }
        return r;
      }

      var stA = $(svg).find("> defs > #gr_bg").children();
      $(stA[0]).css("stop-color", addCol(cols.bg, 10));
      $(stA[1]).css("stop-color", addCol(cols.bg, -10));

    }, false);
  });
}
