"use strict";
FW_version["f18.js"] = "$Id$";

// TODO: hierMenu+Pin,SVGcolors,floorplan
// Known bugs: AbsSize is wrong for ColorSlider
var f18_attr={}, f18_sd, f18_icon={}, f18_room, f18_grid=20;
var f18_small = (screen.width < 480 || screen.height < 480);

$(window).resize(f18_resize);
$(document).ready(function(){

  f18_room  = $("div#content").attr("room");
  f18_sd = $("body").attr("data-styleData");
  if(f18_sd) {
    eval("f18_sd="+f18_sd);
    if(!f18_sd)
      f18_sd = {};
    f18_attr = f18_sd.f18;
    if(f18_attr)
      delete(f18_attr.cols); // fix the past

  } else {
    f18_sd = {};

  }

  if(!f18_sd.f18) {
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
  if('ontouchstart' in window)
    $("body").addClass('touch');
  if(f18_small) {
    $("body").addClass('small');
    f18_attr["Pinned.menu"] = false;
  }

  var f18_aCol = getComputedStyle($("a").get(0),null).getPropertyValue('color');
  for(var i in f18_icon)
    f18_icon[i] = f18_icon[i].replace('gray', f18_aCol);
  f18_icon.pinOut = f18_icon.pinIn
                        .replace('/>',' transform="rotate(90,896,896)"/>');

  // Needed for moving this label
  var szc = $("[data-name=svgZoomControl]");
  if($(szc).length)
    $(szc).before("<div class='SVGplot'></div>");

  $(".SVGlabel[data-name]").each(function(){ 
    $(this).attr("data-name", "Room_"+f18_room+"_"+$(this).attr("data-name"));
  });
  f18_menu();
  f18_tables();
  f18_svgSetCols();
  if(typeof svgCallback != "undefined")
    svgCallback.f18 = f18_svgSetCols;
  $("[data-name]").each(function(){ f18_setPos(this) });
  
  f18_setWrapColumns();
  f18_setFixedInput();
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
    $("#menuScrollArea #logo").css("display", 
        f18_getAttr("hideLogo") ? "none" : "block");
    if(f18_getAttr("Pinned.menu")) {
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
    f18_addPin(el, "Room."+FW_urlParams.room+".grp."+grp, true,
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


  if(FW_urlParams.cmd == "style%20list" ||
     FW_urlParams.cmd == "style%20select")
    $("div.fileList").each(function(){ f18_addPinToStyleDiv(this) });

  if(FW_urlParams.cmd == "style%20select") 
    f18_special();
  else if(f18_getAttr("showDragger"))
    $("[data-name]").each(function(){ f18_addDragger(this) });
}

function
f18_special()
{
  var row, room='all', appendTo;

  var attr = function(attrName, inRoom)
  { 
    if(inRoom && room != "all") {
      var val = f18_attr["Room."+room+"."+attrName];
      if(val != undefined)
        return val;
    }
    return f18_attr[attrName];
  };

  var setAttr = function(attrName, attrVal, inRoom)
  { 
    if(inRoom && room != "all")
      attrName = "Room."+room+"."+attrName;
    f18_setAttr(attrName, attrVal);
  };

  var addRow = function(name, desc, val)
  {
    $(appendTo)
      .append("<tr class='ar_"+name+" "+(++row%2 ? "even":"odd")+"'>"+
                "<td "+(val ? "" : "colspan='2'")+">"+
                      "<div class='col1'>"+desc+"</div></td>"+
                (val ? "<td><div class='col2'>"+val+"</div></div></td>" : '')+
              "</tr>");
  };

  var addHider = function(name, inRoom, desc, fn)
  {
    addRow(name, desc, "<input type='checkbox'>");
    $(appendTo+" tr.ar_"+name+" input")
      .prop("checked", attr(name, inRoom))
      .click(function(){
        var c = $(this).is(":checked");
        setAttr(name, c, inRoom);
        if(fn)
          fn(c);
      });
  };

  var addColorChooser = function(name, desc)
  {
    addRow(name, desc, "<div class='cp'></div>");
    FW_replaceWidget(appendTo+" tr.ar_"+name+" div.col2 div.cp", name,
      ["colorpicker","RGB"], attr("cols."+name, true), name, "rgb", undefined,
      function(value) {
        setAttr("cols."+name, value, true);
        f18_setCss(name);
      });
  };

  // call drawspecial after got the roomlist...
  var f18_drawSpecial = function()
  {
    var roomHash={};

    var cleanRoom = function(){
      for(var k in f18_attr) {
        var m = k.match(/^room\.([^.]*)\..*/);
        if(m && !roomHash[m[1]])
          delete f18_attr[k];
      }
    };

    row = 0;
    $("div#content tr.f18").remove();

    $("div#content > table").append("<tr id='f18rs' class='f18'></tr>");
    $("tr#f18rs").append("<div class='fileList f18colors'>f18 special</div>");
    $("tr#f18rs").append("<table id='f18ts' class='block wide'></table>");
    appendTo = "table#f18ts";

    addHider("rightMenu", false, "MenuBtn right<br>on small screen",f18_resize);
    addHider("savePinChanges", false, "Save pin changes");
    addHider("showDragger", false, "Dragging active", function(c){
      if(c) {
        if($(".ui-draggable").length) {
          $(".ui-draggable").draggable("enable");
          $(".dragMove,.dragSize,.dragReset").show();
        } else {
          $("div.fileList").each(function(){ f18_addDragger(this) });
        }
      } else {
        $(".dragMove,.dragSize,.dragReset").hide();
        $(".ui-draggable").draggable("disable");
      }
    });
    addHider("snapToGrid", false, "Snap to grid", function(c){
      $(".ui-draggable").draggable("option", "grid",
        c ? [f18_grid,f18_grid] : [1,1]);
    });

    addRow("editStyle", "<a href='#'>Additional CSS</a>");
    $(appendTo+" tr.ar_editStyle a").click(function(){
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


    $("div#content > table").append("<tr id='f18rr' class='f18'></tr>");
    $("tr#f18rr").append("<div class='fileList f18colors'>"+
                         "f18: Room specific</div>");
    $("tr#f18rr").append("<table id='f18tr' class='block wide'></table>");
    appendTo = "table#f18tr";

    addRow("room", "Target <select><option>all</option></select>");
    FW_cmd(FW_root+"?cmd=jsonlist2 .* room&XHR=1", function(data) {
      var d;
      try { d=JSON.parse(data); } catch(e){ log(data); return FW_okDialog(e); }
      for(var i1=0; i1<d.Results.length; i1++) {
        var rname = d.Results[i1].Attributes.room;
        if(!rname || rname == "hidden")
          continue;
        var rl = rname.split(",")
        for(var i2=0; i2<rl.length; i2++)
          roomHash[rl[i2]] = true;
      }
      cleanRoom();
      var rArr = Object.keys(roomHash); rArr.sort();
      $(appendTo+" tr.ar_room select")
        .html("<option>all</option><option>"+
                rArr.join("</option><option>")+
              "</option>")
        .change(function(e){ 
          room = $(e.target).val(); 
          f18_drawSpecial();
        });
      $("tr.ar_room select").val(room);
    });
    addRow("reset", "Preset colors: "+
                   "<a href='#'>default</a> "+
                   "<a href='#'>light</a> "+
                   "<a href='#'>dark</a> "+
                   (room=='all' ? '': "<a href='#'>like:all</a>"));
    $(appendTo+" tr.ar_reset a").click(function(){
      var txt = $(this).text();
      if(txt == "like:all") {
        delete(roomHash[room]);
        cleanRoom();
      } else {
        f18_resetCol(txt, room);
        if(room == "all")
          f18_setCss('preset');
      }
      f18_setAttr();
      f18_drawSpecial();
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

    var bgImg = attr("bgImg", true);
    addRow("bgImg", "<a href='#'>Background: <span>"+
                    (bgImg ? bgImg : "none")+"</span></a>");
    $(appendTo+" tr.ar_bgImg a").click(function(){
      FW_cmd(FW_root+'?cmd='+
      '{join("\\n",FW_fileList("$FW_icondir/background/.*.(jpg|png)"))}&XHR=1',
      function(data) {
        if(data)
          data += "none";
        var imgList = data.split(/\n/);
        FW_okDialog("List of files in www/images/background:<br><ul>"+
              "<a href='#'>"+imgList.join("</a><br><a href='#'>")+'</a></ul>');
        $("#FW_okDialog a").click(function(){
          var txt = $(this).text();
          setAttr("bgImg", txt == 'none' ? undefined : txt, true);
          $(appendTo+" tr.ar_bgImg span").html(txt);
          f18_setCss("bgImg");
        });
      });
      
    });

    addHider("hideLogo", true, "Hide logo", f18_menu);
    addHider("hideInput", true, "Hide input", f18_menu);
    addHider("hidePin", true, "Hide pin", function(c){
      $("div.pinHeader div.pin").css("display", c ? "none":"block");
    });
    addHider("fixedInput", true, "Fixed input and menu", f18_setFixedInput);
    addHider("wrapcolumns",false,"Wrap columns<br>on small screen",
                        f18_setWrapColumns);

    $("div.f18colors").css("margin-top", "20px");
    $("tr.f18 div.fileList").each(function(e){ f18_addPinToStyleDiv(this) });
    if(f18_getAttr("showDragger"))
      $("div.fileList").each(function(){ f18_addDragger(this) });
    $("[data-name]").each(function(){ f18_setPos(this) });
    f18_setWrapColumns();
  };
  loadScript("pgm2/fhemweb_colorpicker.js", f18_drawSpecial);
}

function
f18_setFixedInput()
{
  $("#menu,#menuBtn,#content,#hdr")
    .css(f18_getAttr("fixedInput") ?
      { position:"fixed", overflow:"auto" } :
      { position:"absolute", overflow:"visible" });
}

function
f18_setFixedInput()
{
  $("body").toggleClass("fixedInput", f18_getAttr("fixedInput"));
  f18_resize();
}

function
f18_setWrapColumns()
{
  $("table.block").toggleClass("wrapcolumns", f18_getAttr("wrapcolumns"));
}

function
f18_addPinToStyleDiv(el)
{
  var grp = $(el).text();
  f18_addPin(el, "style.list."+grp, true,
  function(isFixed){
    var ntr = $(el).next("table");
    isFixed ? $(ntr).show() : $(ntr).hide();
  });
}


function
f18_resize()
{
  var w=$(window).width();
  log("f18.js W:"+w+" S:"+screen.width);
  var hl = f18_getAttr("hideLogo"),
      hi = f18_getAttr("hideInput"),
      pm = f18_getAttr("Pinned.menu"),
      rm = (f18_getAttr("rightMenu") && f18_small);

  var left = 0;
  left += hl ? 0 : 40;
  left += pm ? 0 : 44;
  var lleft = (pm ? 10 : 52);
  $("input.maininput").css({ width:(w-left-(FW_isiOS ? 26 : 24))+'px', 
                             "margin-left":(rm ? "0px" : "10px"),
                             display: hi ? "none":"block"});
  $("#menu,#content").css("top", (hi && pm && hl) ? "10px" : "50px");
  $("#hdr").css({ left:(rm ? 10 : left)+'px' });
  $("#menuBtn").css({ left:(rm ? "auto":"10px"), right:(rm ? "10px":"auto") });
  $("#logo")   .css({ left:(rm ? "auto":lleft ), right:(rm ? "48px":"auto") });
}

function
f18_addPin(el, name, defVal, fn, hidePin)
{
  var init = f18_getAttr("Pinned."+name);
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
    .css("display", (f18_getAttr("hidePin") || hidePin) ? "none" : "block")
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

// el is the drag-handle, return the corresponding SVG/table etc
function
f18_compEl(el)
{
  return $(el).hasClass("fileList") ?  $(el).next("table") : 
         $(el).hasClass("SVGlabel") ?  $(el).prev(".SVGplot") :
         $(el).closest("tr").next().find(">td>table").first();
}

function
f18_addDragger(el)
{
  if(f18_small || FW_urlParams.detail)
    return;
  if($(el).find(".dragger").length)
    return;
    
  var comp = f18_compEl(el);
  if($(comp).length == 0)
    return;

  f18_convertToAbs();
  var ep = $(el).position();
  var cp = $(comp).position();
  var pl = parseInt($(el).css("padding-left").replace("px",""));

  var grid = [1,1];
  if(f18_getAttr("snapToGrid"))
    grid = [f18_grid, f18_grid];

  function
  save()
  {
    var nep = $(el).position();
    f18_setAttr("Pos."+$(el).attr("data-name"), {
      left:nep.left, top:nep.top,
      width:$(comp).width(), height:$(comp).height(), 
      oTop:cp.top-ep.top, oLeft:cp.left-ep.left
    });
  }

  /////////////////////////////////////
  // Position
  $("<div class='dragger dragMove'></div>")
    .appendTo(el)
    .css({"cursor":"pointer",
         "background-image":"url('"+f18_icon.arrows+"')"})
  $(el).draggable({
    drag:function(evt,ui){
      $(comp).css({ left:ui.position.left+cp.left-ep.left,
                    top: ui.position.top +cp.top -ep.top });
    },
    stop:save, grid:grid
  });

  /////////////////////////////////////
  // Size
  var off = 20;
  if(!$(el).hasClass("SVGlabel")) {
    $("<div class='dragSize'></div>")
      .appendTo(el)
      .css({ cursor:"pointer", "background-image":"url('"+f18_icon.arrows+"')",
             position:"absolute", width:"16px", height:"16px",
             top:$(comp).height()+2, left:$(comp).width()-off, "z-index":1 })
      .draggable({
        drag:function(evt,ui){
          $(el).css(  { width:ui.position.left+off });
          $(comp).css({ width:ui.position.left+off,
                        height:ui.position.top });
        },
        stop:save, grid:grid
      });
  }


  /////////////////////////////////////
  // Reset _all_ elements on this page
  $("<div class='dragger dragReset'></div>")
    .appendTo(el)
    .css({"cursor":"pointer",
         "background-image":"url('"+f18_icon.ban+"')"})

    .click(function(){
      function
      delStyle(e)
      {
        var style = $(e).attr("style");
        $(e).attr("style", style.replace(/position:.*;/,"")); // hack
      }

      $("[data-name]").each(function(){
        var el = this;
        var name = $(el).attr("data-name");
        if(!f18_getAttr("Pos."+name))
          return;
        delete(f18_attr["Pos."+$(el).attr("data-name")]);
        delStyle(el);
        delStyle(f18_compEl(el));
        $(el).draggable('disable');
        $(el).find(".dragMove,.dragSize,.dragReset").hide();
      });
      f18_setAttr();
    });
}

function
f18_applyGrid(pos)
{
  if(!f18_getAttr("snapToGrid"))
    return;
  pos.left   = Math.floor((pos.left  + f18_grid-1)/f18_grid)*f18_grid;
  pos.top    = Math.floor((pos.top   + f18_grid-1)/f18_grid)*f18_grid;
  pos.width  = Math.floor((pos.width + f18_grid-1)/f18_grid)*f18_grid;
  pos.height = Math.floor((pos.height+ f18_grid-1)/f18_grid)*f18_grid;
}

//////////////////////////
// We use absolute positioning for all elements, if a user positioned 
// an item, relative (the default one) else.
function
f18_convertToAbs()
{
  // Need two loops, else the sizes/positions are wrong
  var sz = {};
  $("[data-name]").each(function(){
    var el = this;
    var name = $(el).attr("data-name");
    if(f18_getAttr("Pos."+name))
      return;
    var comp = f18_compEl(el);
    if($(comp).length == 0)
      return;
    sz[name] = { ep:$(el).position(), cp:$(comp).position(), 
                 w:$(comp).width(), h:$(comp).height() };
  });

  var needSave=false;
  $("[data-name]").each(function(){
    var el = this;
    var name = $(el).attr("data-name");
    if(!name || !sz[name])
      return;
    needSave = true;

    var comp = f18_compEl(el);
    var ep=sz[name].ep, cp=sz[name].cp, w=sz[name].w, h=sz[name].h;
    var pos = {
      left:ep.left, top:ep.top, width:w, height:h, 
      oTop:cp.top-ep.top, oLeft:cp.left-ep.left
    };
    f18_doSetPos(el, comp, pos);
    f18_setAttr("Pos."+name, pos, true);
  });

  if(needSave)
    f18_setAttr();
}

function
f18_setPos(el)
{
  if(f18_small || FW_urlParams.detail)
    return;
  var comp = f18_compEl(el);
  if($(comp).length == 0)
    return;

  var name = $(el).attr("data-name");
  var pos = f18_getAttr("Pos."+name);
  if(!pos || !pos.width)
    return;

  f18_doSetPos(el, comp, pos);

  // correct position
  var ds = $(el).find(".dragSize");
  if($(ds).length)
    $(ds).css({ top:pos.height+2, left:pos.width-20 });
}

function
f18_doSetPos(el, comp, pos)
{
  f18_applyGrid(pos);
  $(el).css({ position:"absolute", left:pos.left, top:pos.top });
  if(!$(el).hasClass("SVGlabel")) {
    var padding = parseInt($(el).css("padding-left").replace("px",""));
    $(el).css({ width:pos.width-padding });
  }
  $(comp).css({ position:"absolute", 
                left:pos.left+pos.oLeft, top:pos.top+pos.oTop,
                width:pos.width, height:pos.height });

}


function
f18_getAttr(attrName)
{
  if(f18_room != undefined) {
    var val = f18_attr["Room."+f18_room+"."+attrName];
    if(val != undefined)
      return val
  }
  return f18_attr[attrName];
}

function
f18_setAttr(name, value, dontSave)
{
  if(name)
    f18_attr[name]=value;
  if(name && value == undefined)
    delete f18_attr[name];
  if(name && name.indexOf("Pinned.") == 0 && !f18_attr.savePinChanges)
    return;
  if(dontSave)
    return;

  var wn = $("body").attr("data-webName");
  FW_cmd(FW_root+"?cmd=attr "+wn+" styleData "+
         encodeURIComponent(JSON.stringify(f18_sd, undefined, 1))+"&XHR=1");
}

function
f18_resetCol(name, room)
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
  var col = (name ? cols[name] : cols["default"]);
  var prefix = (room && room != 'all' ? "Room."+room+".cols." : "cols.");
  for(var c in col)
    f18_attr[prefix+c] = col[c];
}

// Put all the colors into a head style tag, send background changes to FHEM
function
f18_setCss(why)
{
  var style = "";
  function col(n) { return f18_getAttr("cols."+n, true) };
  function bg(c) { return "{ background:#"+c+"; fill:#"+c+"; }\n" }
  function fg(c) { return "{ color:#"+c+"; }\n" }
  style += ".col_fg, body, input, textarea "+fg(col("fg"));
  style += ".col_bg, textarea, input, option "+bg(col("bg"));
  style += ".col_link,a:not(.changed),.handle,.fhemlog,input[type=submit],"+
           "select,div.ui-widget-content a "+
           "{color:#"+col("link")+"!important; stroke:#"+col("link")+";}\n";
  style += "svg:not([fill]):not(.jssvg) { fill:#"+col("link")+"; }\n";
  style += ".col_evenrow, table.block,div.block "+bg(col("evenrow"));
  style += ".col_oddrow,table.block tr.odd,table.block tr.sel "+
        bg(col("oddrow"));
  style += ".col_header "+bg(col("header"));
  style += ".col_menu, table.room "+bg(col("menu"));
  style += ".col_sel, table.room tr.sel "+bg(col("sel"));
  style += ".col_inpBack, input "+bg(col("inpBack"));
  if(col("bg") == "FFFFE7") // default
    style += "div.pinHeader.menu {background:#"+col("sel")+";}\n";

  style += "div.ui-dialog-titlebar "+bg(col("header"));
  style += "div.ui-widget-content "+bg(col("bg"));
  style += "div.ui-widget-content, .ui-button-text "+fg(col("fg")+"!important");
  style += "div.ui-dialog { border:1px solid #"+col("link")+"; }";
  style += "button.ui-button { background:#"+col("oddrow")+"!important; "+
                            "border:1px solid #"+col("link")+"!important; }\n";

  if(typeof DashboardDraggable  != "undefined") {
    var db = "#dashboard ";
    style += db+".dashboard_widgetheader "+bg(col("header"));
    style += db+".dashboard_tabnav "+bg(col("menu")+"!important");
    style += db+".ui-widget-header .ui-state-default "+bg(col("menu"));
    style += db+".ui-widget-header .ui-state-active "+bg(col("sel"));
    style += db+".ui-widget-header "+fg(col("fg")+"!important;");
    style += db+".ui-widget-header li { border:none!important; }";
    style += db+".ui-widget-content a "+fg(col("link")+"!important" );
  }
  var bgImg = f18_getAttr("bgImg", true);
  if(bgImg) {
    style += 'body { background-image: url('+FW_root+
                     '/images/background/'+bgImg+');}';
  } else {
    style += "body "+bg(col("bg"));
  }

  $("head style#f18_css").remove();
  style = "<style id='f18_css'>"+style+"</style>";
  if($("head style#fhemweb_css").length)
    $("head style#fhemweb_css").before(style);
  else
    $("head").append(style);

  $("head meta[name=theme-color]").remove();
  $("head").append('<meta name="theme-color" content="#'+col("bg")+'">');

  // Recolor the menu arrows. CSS does not apply to such SVGs :(
  if(why=='init' || why=='preset' || why=='link') {
    var a = $("a").get(0);
    if(window.getComputedStyle && a) {
      var col = getComputedStyle(a,null).getPropertyValue('color');
      FW_arrowRight = FW_arrowRight.replace(/rgb[^)]*\)/,col);
      FW_arrowDown  = FW_arrowDown.replace(/rgb[^)]*\)/,col);
      $("div#menu table.room tr.menuTree > td > div > div")
        .css("background-image", "url('"+FW_arrowRight+"')");
      $("div#menu table.room tr.menuTree.open > td > div > div")
        .css("background-image", "url('"+FW_arrowDown+"')");
    }
  }

}

// SVG color tuning
function
f18_svgSetCols(svg)
{
  function col(n) { return f18_getAttr("cols."+n, true) };

  if(!svg || !svg.getAttribute("data-origin"))
    return;

  var style = $(svg).find("> style").first();
  var sTxt = $(style).text();
  sTxt = sTxt.replace(/font-family:Times/, "fill:#"+col("fg"));
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
  $(stA[0]).attr("style", "stop-color:#"+addCol(col("bg"),10)+so);
  $(stA[1]).attr("style", "stop-color:#"+addCol(col("bg"),-10)+so);
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
