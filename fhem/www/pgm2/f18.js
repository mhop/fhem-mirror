"use strict";
FW_version["f18.js"] = "$Id$";

// TODO: rewrite menu, floorplan
var f18_attr, f18_aCol, f18_sd, f18_isMobile, f18_icon={}, f18_hasPos;
var f18_small = (screen.width < 480 || screen.height < 480);

$(window).resize(f18_resize);
$(document).ready(function(){

  f18_sd = $("body").attr("data-styleData");
  if(f18_sd) {
    eval("f18_sd="+f18_sd);
    if(!f18_sd)
      f18_sd = {};
    f18_attr = f18_sd.f18;

  } else {
    f18_sd = {};

  }

  if(!f18_attr) {
    f18_attr = { "Pinned.menu":"true" };
    f18_resetCol();
    f18_sd.f18 = f18_attr;
  }
  if(typeof f18_attr.savePinChanges == "undefined")
    f18_attr.savePinChanges = true;

 f18_setCss('init');

 var icon = FW_root+"/images/default/fhemicon_ios.png";
  $('head').append(
    '<meta name="viewport" content="initial-scale=1.0,user-scalable=1">'+
    '<meta name=      "mobile-web-app-capable" content="yes">'+
    '<meta name="apple-mobile-web-app-capable" content="yes">'+
    '<link rel="apple-touch-icon" href="'+icon+'">');
  if('ontouchstart' in window)                  $("body").addClass('touch');
  if(f18_small) {
    $("body").addClass('small');
    f18_attr["Pinned.menu"] = false;
  }
  if(f18_attr.rightMenu)
    $("body").addClass("rightMenu");

  f18_aCol = getComputedStyle($("a").get(0),null).getPropertyValue('color'); 
  for(var i in f18_icon)
    f18_icon[i] = f18_icon[i].replace('gray', f18_aCol);
  f18_icon.pinOut = f18_icon.pinIn
                        .replace('/>',' transform="rotate(90,896,896)"/>');

  f18_menu();
  f18_tables();
  f18_svgSetCols();
  if(typeof svgCallback != "undefined")
    svgCallback.f18 = f18_svgSetCols;
});

function
f18_menu()
{
  if($("#menuScrollArea #menuBtn").length)
    return fixMenu();

  $("<div id='menuBtn'></div>").prependTo("div#menuScrollArea")
    .css( {"background-image":"url('"+f18_icon.bars+"')", "cursor":"pointer" })
    .click(function(){ $("#menu").toggleClass("visible") });

  $("div#menu").prepend("<div></div>");
  f18_addPin("div#menu > div:first", "menu", true, fixMenu, f18_small);
  setTimeout(function(){ $("#menu,#content,#logo,#hdr").addClass("animated"); },
             10);
  function
  fixMenu()
  {
    $("#menuScrollArea #logo").css("display", f18_attr.hideLogo?"none":"block");
    if(f18_attr["Pinned.menu"]) {
      $("body").addClass("pinnedMenu");
      $("#menu").removeClass("visible");
      $("#content").css("left", (parseInt($("div#menu").width())+20)+"px");

    } else {
      $("body").removeClass("pinnedMenu");
      $("#content").css("left", "");
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
    if(f18_attr.showDragger)
      f18_addDragger(el);
    f18_setPos(el);
  });

  $("div.SVGlabel").each(function(){
    if(f18_attr.showDragger)
      f18_addDragger(this);
    f18_setPos(this);
  });

  if(f18_hasPos || f18_attr.showDragger)
    $("div.pinHeader:not(.menu) div.pin").hide();

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

    var addRow = function(name, desc, val)
    {
      $("table.f18colors")
        .append("<tr class='ar_"+name+" "+(++row%2 ? "even":"odd")+"'>"+
                  "<td "+(val ? "" : "colspan='2'")+">"+
                        "<div class='col1'>"+desc+"</div></td>"+
                  (val ? "<td><div class='col2'>"+val+"</div></div></td>" : '')+
                "</tr>");
    };

    var addHider = function(name, desc, fn)
    {
      addRow(name, desc, "<input type='checkbox'>");
      $("table.f18colors tr.ar_"+name+" input")
        .prop("checked", f18_attr[name])
        .click(function(){
          var c = $(this).is(":checked");
          f18_setAttr(name, c);
          fn(c);
        });
    };

    var addColorChooser = function(name, desc)
    {
      addRow(name, desc, "<div class='cp'></div>");
      FW_replaceWidget("table.f18colors tr.ar_"+name+" div.col2 div.cp", name,
        ["colorpicker","RGB"], f18_attr.cols[name], name, "rgb", undefined,
        function(value) {
          f18_attr.cols[name] = value;
          f18_setAttr();
          f18_setCss(name);
        });
    };


    $("div#content > table").append("<tr class='f18'></tr>");

    $("tr.f18").append("<div class='fileList f18colors'>f18 special</div>");
    $("div.f18colors").css("margin-top", "20px");
    $("tr.f18").append("<table class='block wide f18colors'></table>");

    var addColors = function()
    {
      $("table.f18colors")
        .append("<tr class='reset' "+(++row%2 ? "even":"odd")+"'>"+
                  "<td colspan='2'><div class='col1'>Preset colors: "+
                     "<a href='#'>default</a> "+
                     "<a href='#'>light</a> "+
                     "<a href='#'>dark</a> "+
                  "</div></td>"+
                "</tr>");
      $("table.f18colors tr.reset a").click(function(){
        row = 0;
        $("table.f18colors").html("");
        f18_resetCol($(this).text());
        f18_setCss('preset');
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
      addColorChooser("sel",     "Menu:Selected");
      addColorChooser("inpBack", "Input bg");
      $("table.f18colors input").attr("size", 8);

      addRow("editStyle", "<a href='#'>Additional CSS</a>");
      $("table.f18colors tr.ar_editStyle a").click(function(){
        $('body').append(
          '<div id="editdlg" style="display:none">'+
            '<textarea id="f18_cssEd" rows="25" cols="60" style="width:99%"/>'+
          '</div>');

        $("#f18_cssEd").val($("head #fhemweb_css").html());
        $('#editdlg').dialog(
          { modal:true, closeOnEscape:true, width:$(window).width()*3/4,
            height:$(window).height()*3/4, title:$(this).text(),
            close:function(){ $('#editdlg').remove(); },
            buttons:[
            { text: "Cancel",click:function(){$(this).dialog('close')}},
            { text: "OK", click:function(){

              if(!$("head #fhemweb_css"))
                $("head").append("<style id='fhemweb_css'>\n</style>");
              var txt = $("#f18_cssEd").val();
              $("head #fhemweb_css").html(txt);
              var wn = $("body").attr("data-webName");
              FW_cmd(FW_root+"?cmd=attr "+wn+" Css "+
                     encodeURIComponent(txt.replace(/;/g,";;"))+"&XHR=1");
              $(this).dialog('close');
            }}]
          });
      });

      addRow("empty", "&nbsp;");
      addHider("hidePin", "Hide pin", function(c){
        $("div.pinHeader div.pin").css("display", c ? "none":"block");
      });
      addHider("hideLogo", "Hide logo", f18_menu);
      addHider("rightMenu", "MenuBtn right on SmallScreen", function(c){
        $("body").toggleClass("rightMenu");
      });
      addHider("savePinChanges", "Save pin changes", function(){});
      addHider("showDragger", "Dragging active", function(c){
        if(c) {
          $("div.fileList").each(function(){ f18_addDragger(this) });
          $("div.pinHeader:not(.menu) div.pin").hide();
        } else {
          $("div.pinHeader div.dragger").remove();
        }
      });

    };
    loadScript("pgm2/fhemweb_colorpicker.js", addColors);
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
      if(f18_attr.showDragger)
        f18_addDragger(el);
      f18_setPos(el);
    });
    if(f18_hasPos || f18_attr.showDragger)
      $("div.pinHeader:not(.menu) div.pin").hide();
  }
}

function
f18_resize()
{
  var w=$(window).width();
  log("f18.js W:"+w+" S:"+screen.width);

  var diff = 0;
  diff += f18_attr.hideLogo ? 0 : 40;
  diff += f18_attr["Pinned.menu"] ? 0 : 44;
  $("input.maininput").css("width", (w-(FW_isiOS ? 40 : 30)-diff)+'px');
}

function
f18_addPin(el, name, defVal, fn, hidePin)
{
  var init = f18_attr["Pinned."+name];
  if(init == undefined)
    init = defVal;
  $("<div class='pin'></div>")
    .appendTo(el)
    .css("background-image", "url('"+
                              (init ? f18_icon.pinIn : f18_icon.pinOut)+"')");
  var f18_name = name.replace(/[^A-Z0-9]/ig,'_');
  $(el)
    .addClass("col_header pinHeader "+f18_name)
    .attr("data-name", f18_name);
  el = $(el).find("div.pin");
  $(el)
    .addClass(init ? "pinIn" : "")
    .css("cursor", "pointer")
    .css("display", (f18_attr.hidePin || hidePin) ? "none" : "block")
    .click(function(){
      var nextVal = !$(el).hasClass("pinIn");
      $(el).toggleClass("pinIn");
      $(el).css("background-image","url('"+
                             (nextVal ? f18_icon.pinIn : f18_icon.pinOut)+"')")
      f18_setAttr("Pinned."+name, nextVal);
      fn(nextVal);
    });
  fn(init);
}

function
f18_addDragger(el)
{
  if(f18_small)
    return;
  var comp = $(el).hasClass("fileList") ?  $(el).next("table") : 
             $(el).hasClass("SVGlabel") ?  $(el).prev(".SVGplot") :
             $(el).closest("tr").next().find(">td>table").first();

  $("<div class='dragger dragMove'></div>")
    .appendTo(el)
    .css({"cursor":"pointer",
         "background-image":"url('"+f18_icon.arrows+"')"})
  $(el).draggable({
    drag:function(evt,ui){
      $(comp).css({ left:ui.position.left, top:ui.position.top});
    },
    start:function(evt,ui){
      $(comp).css({ position:"relative",
                    left:0, top:0, right:"auto", bottom:"auto" });
    },
    stop:function(evt,ui){
      f18_setAttr("Pos."+$(el).attr("data-name"), ui.position);
    },
  });

  $("<div class='dragger dragReset'></div>")
    .appendTo(el)
    .css({"cursor":"pointer",
         "background-image":"url('"+f18_icon.ban+"')"})
    .click(function(){
      $(el)  .css({ left:0, top:0 });
      $(comp).css({ left:0, top:0 });
      delete(f18_attr["Pos."+$(el).attr("data-name")]);
      f18_setAttr();
    });
}

function
f18_setPos(el)
{
  if(f18_small)
    return;
  var name = $(el).attr("data-name");
  var pos = f18_attr["Pos."+name];
  if(!pos)
    return;

  f18_hasPos = true;
  var comp = $(el).hasClass("fileList") ?  $(el).next("table") : 
             $(el).hasClass("SVGlabel") ?  $(el).prev(".SVGplot") :
             $(el).closest("tr").next().find(">td>table").first();
  $(el).css({ position:"relative",
              left:pos.left, top:pos.top, right:"auto", bottom:"auto" });
  $(comp).css({ position:"relative",
              left:pos.left, top:pos.top, right:"auto", bottom:"auto" });
}

function
f18_setAttr(name, value)
{
  if(name)
    f18_attr[name]=value;
  if(name && name.indexOf("Pinned.") == 0 && !f18_attr.savePinChanges)
    return;
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

// Put all the colors into a head style tag, send background changes to FHEM
function
f18_setCss(why)
{
  var cols = f18_attr.cols;
  var style = "";
  function bg(c) { return "{ background:#"+c+"; fill:#"+c+"; }\n" }
  function fg(c) { return "{ color:#"+c+"; }\n" }
  style += ".col_fg, body, input, textarea "+fg(cols.fg);
  style += ".col_bg, body, #menu, textarea, input, option "+bg(cols.bg);
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

  if(typeof DashboardDraggable  != "undefined") {
    var db = "#dashboard ";
    style += db+".dashboard_widgetheader "+bg(cols.header);
    style += db+".dashboard_tabnav "+bg(cols.menu+"!important");
    style += db+".ui-widget-header .ui-state-default "+bg(cols.menu);
    style += db+".ui-widget-header .ui-state-active "+bg(cols.sel);
    style += db+".ui-widget-header "+fg(cols.fg+"!important;");
    style += db+".ui-widget-header li { border:none!important; }";
    style += db+".ui-widget-content a "+fg(cols.link+"!important" );
  }

  $("head style#f18_css").remove();
  if(why == 'preset' || why == 'bg') { // Add background to css to avoid flicker
    if(!$("head #fhemweb_css").length)
      $("head").append("<style id='fhemweb_css'>\n</style>");
    var otxt = $("head #fhemweb_css").html(), ntxt = otxt;
    if(!ntxt)
      ntxt = "";
    ntxt = ntxt.replace(/^body,#menu { background:[^;]*; }[\r\n]*/m,'');
    ntxt += "body,#menu { background:#"+cols.bg+"; }\n";
    if(ntxt != otxt) {
      $("head #fhemweb_css").html(ntxt);
      var wn = $("body").attr("data-webName");
      FW_cmd(FW_root+"?cmd=attr "+wn+" Css "+
             encodeURIComponent(ntxt.replace(/;/g,";;"))+"&XHR=1");
    }
  }

  style = "<style id='f18_css'>"+style+"</style>";
  if($("head style#fhemweb_css").length)
    $("head style#fhemweb_css").before(style);
  else
    $("head").append(style);

  $("head meta[name=theme-color]").remove();
  $("head").append('<meta name="theme-color" content="#'+cols.bg+'">');
}

// SVG color tuning
function
f18_svgSetCols(svg)
{
  if(!svg || !svg.getAttribute("data-origin"))
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
        n = "0"+n;
      r += n;
    }
    return r;
  }

  // SVG background gradient: .css does not work in Firefox, has to use .attr
  var stA = $(svg).find("> defs > #gr_bg").children();
  var so = "; stop-opacity:1;";
  $(stA[0]).attr("style", "stop-color:#"+addCol(cols.bg,10)+so);
  $(stA[1]).attr("style", "stop-color:#"+addCol(cols.bg,-10)+so);
}

// font-awesome
var f18_svgPrefix='data:image/svg+xml;utf8,<svg viewBox="0 0 1792 1792" xmlns="http://www.w3.org/2000/svg"><path fill="gray" ';
f18_icon.pinIn=f18_svgPrefix+'d="M896 1088q66 0 128-15v655q0 26-19 45t-45 19h-128q-26 0-45-19t-19-45v-655q62 15 128 15zm0-1088q212 0 362 150t150 362-150 362-362 150-362-150-150-362 150-362 362-150zm0 224q14 0 23-9t9-23-9-23-23-9q-146 0-249 103t-103 249q0 14 9 23t23 9 23-9 9-23q0-119 84.5-203.5t203.5-84.5z"/></svg>';

f18_icon.bars=f18_svgPrefix+'d="M1664 1344v128q0 26-19 45t-45 19h-1408q-26 0-45-19t-19-45v-128q0-26 19-45t45-19h1408q26 0 45 19t19 45zm0-512v128q0 26-19 45t-45 19h-1408q-26 0-45-19t-19-45v-128q0-26 19-45t45-19h1408q26 0 45 19t19 45zm0-512v128q0 26-19 45t-45 19h-1408q-26 0-45-19t-19-45v-128q0-26 19-45t45-19h1408q26 0 45 19t19 45z"/></svg>';

f18_icon.arrows=f18_svgPrefix+'d="M1792 896q0 26-19 45l-256 256q-19 19-45 19t-45-19-19-45v-128h-384v384h128q26 0 45 19t19 45-19 45l-256 256q-19 19-45 19t-45-19l-256-256q-19-19-19-45t19-45 45-19h128v-384h-384v128q0 26-19 45t-45 19-45-19l-256-256q-19-19-19-45t19-45l256-256q19-19 45-19t45 19 19 45v128h384v-384h-128q-26 0-45-19t-19-45 19-45l256-256q19-19 45-19t45 19l256 256q19 19 19 45t-19 45-45 19h-128v384h384v-128q0-26 19-45t45-19 45 19l256 256q19 19 19 45z"/></svg>';

f18_icon.ban=f18_svgPrefix+'d="M1440 893q0-161-87-295l-754 753q137 89 297 89 111 0 211.5-43.5t173.5-116.5 116-174.5 43-212.5zm-999 299l755-754q-135-91-300-91-148 0-273 73t-198 199-73 274q0 162 89 299zm1223-299q0 157-61 300t-163.5 246-245 164-298.5 61-298.5-61-245-164-163.5-246-61-300 61-299.5 163.5-245.5 245-164 298.5-61 298.5 61 245 164 163.5 245.5 61 299.5z"/></svg>';


/*!
 * jQuery UI Touch Punch 0.2.3
 *
 * Copyright 2011-2014, Dave Furfero
 * Dual licensed under the MIT or GPL Version 2 licenses.
 *
 * Depends:
 *  jquery.ui.widget.js
 *  jquery.ui.mouse.js
 */
!function(a){function f(a,b){if(!(a.originalEvent.touches.length>1)){a.preventDefault();var c=a.originalEvent.changedTouches[0],d=document.createEvent("MouseEvents");d.initMouseEvent(b,!0,!0,window,1,c.screenX,c.screenY,c.clientX,c.clientY,!1,!1,!1,!1,0,null),a.target.dispatchEvent(d)}}if(a.support.touch="ontouchend"in document,a.support.touch){var e,b=a.ui.mouse.prototype,c=b._mouseInit,d=b._mouseDestroy;b._touchStart=function(a){var b=this;!e&&b._mouseCapture(a.originalEvent.changedTouches[0])&&(e=!0,b._touchMoved=!1,f(a,"mouseover"),f(a,"mousemove"),f(a,"mousedown"))},b._touchMove=function(a){e&&(this._touchMoved=!0,f(a,"mousemove"))},b._touchEnd=function(a){e&&(f(a,"mouseup"),f(a,"mouseout"),this._touchMoved||f(a,"click"),e=!1)},b._mouseInit=function(){var b=this;b.element.bind({touchstart:a.proxy(b,"_touchStart"),touchmove:a.proxy(b,"_touchMove"),touchend:a.proxy(b,"_touchEnd")}),c.call(b)},b._mouseDestroy=function(){var b=this;b.element.unbind({touchstart:a.proxy(b,"_touchStart"),touchmove:a.proxy(b,"_touchMove"),touchend:a.proxy(b,"_touchEnd")}),d.call(b)}}}(jQuery);
