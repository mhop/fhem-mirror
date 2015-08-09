"use strict";

var FW_serverGenerated;
var FW_serverFirstMsg = (new Date()).getTime()/1000;
var FW_serverLastMsg = FW_serverFirstMsg;
var FW_isIE = (navigator.appVersion.indexOf("MSIE") > 0);
var FW_isiOS = navigator.userAgent.match(/(iPad|iPhone|iPod)/);
var FW_scripts = {}, FW_links = {};
var FW_docReady = false;
var FW_root = "/fhem";  // root

// createFn returns an HTML Element, which may contain 
// - setValueFn, which is called when data via longpoll arrives
// - activateFn, which is called after the HTML element is part of the DOM.
var FW_widgets = {
  select:            { createFn:FW_createSelect    },
  slider:            { createFn:FW_createSlider    },
  time:              { createFn:FW_createTime      },
  noArg:             { createFn:FW_createNoArg     },
  multiple:          { createFn:FW_createMultiple  },
  "multiple-strict": { createFn:FW_createMultiple  },
  textfield:         { createFn:FW_createTextField },
  "textfield-long":  { createFn:FW_createTextField }
};

window.onbeforeunload = function(e)
{ 
  FW_leaving = 1;
  return undefined;
}

function
FW_replaceWidgets(parent)
{
  parent.find("div.fhemWidget").each(function() {
    var dev=$(this).attr("dev");
    var cmd=$(this).attr("cmd");
    var rd=$(this).attr("reading");
    var params = cmd.split(" ");
    var type=$(this).attr("type");
    if( type == undefined ) type = "set";
    FW_replaceWidget(this, dev, $(this).attr("arg").split(","),
      $(this).attr("current"), rd, params[0], params.slice(1),
      function(arg) {
        FW_cmd(FW_root+"?cmd="+type+" "+dev+
                (params[0]=="state" ? "":" "+params[0])+" "+arg+"&XHR=1");
      });
  });
}

function
FW_jqueryReadyFn()
{
  FW_docReady = true;
  FW_serverGenerated = document.body.getAttribute("generated");
  if(document.body.getAttribute("longpoll"))
    setTimeout("FW_longpoll()", 100);

  $("a").each(function() { FW_replaceLink(this); })
  $("head script").each(function() {
    var sname = $(this).attr("src"),
        p = FW_scripts[sname];
    if(!p) {
      FW_scripts[sname] = { loaded:true };
      return;
    }
    FW_scripts[sname].loaded = true;
    if(p.callbacks && !p.called) {
      p.called = true;  // Avoid endless loop
      for(var i1=0; i1< p.callbacks.length; i1++)
        if(p.callbacks[i1]) // pushing undefined callbacks on the stack is ok
          p.callbacks[i1]();
      delete(p.callbacks);
    }

  });
  $("head link").each(function() { FW_links[$(this).attr("href")] = 1 });

  $("div.makeSelect select").each(function() {
    FW_detailSelect(this);
    $(this).change(FW_detailSelect);
  });


  // Activate the widgets
  var r = $("head").attr("root");
  if(r)
    FW_root = r;

  FW_replaceWidgets($("html"));

  // Fix the td count by setting colspan on the last column
  $("table.block.wide").each(function(){        // table
    var id = $(this).attr("id");
    if(!id || id.indexOf("TYPE") != 0)
      return;
    var maxTd=0, tdCount=[];
    $(this).find("tr").each(function(){         // count the td's
      var cnt=0;
      $(this).find("td").each(function(){ cnt++; });
      if(maxTd < cnt) maxTd = cnt;
      tdCount.push(cnt);
    });
    $(this).find("tr").each(function(){         // set the colspan
      $(this).find("td").last().attr("colspan", maxTd-tdCount.shift()+1);
    });
  });

  // Replace the FORM-POST in detail-view by XHR
  /* Inactive, as Internals and Attributes arent auto updated.
  $("form input[type=submit]").click(function(e) {
    var cmd = "";
    $(this).parent().find("[name]").each(function() {
      cmd += (cmd?"&":"")+$(this).attr("name")+"="+$(this).val();
    });
    if(cmd.indexOf("detail=") < 0)
      return;
    e.preventDefault();
    FW_cmd(FW_root+"?"+cmd+"&XHR=1");
  });
  */

  $("form input.get[type=submit]").click(function(e) { //"get" via XHR to dialog
    e.preventDefault();
    var cmd = "", el=this;
    $(el).parent().find("input,[name]").each(function() {
      cmd += (cmd?"&":"")+$(this).attr("name")+"="+$(this).val();
    });
    FW_cmd(FW_root+"?"+cmd+"&XHR=1&addLinks=1", function(data) {
      if(!data.match(/^[\r\n]*$/)) // ignore empty answers
        FW_okDialog('<pre>'+data+'</pre>', el);
    });
  });
  

  $("#saveCheck")
    .css("cursor", "pointer")
    .click(function(){
      var parent = this;
      FW_cmd(FW_root+"?cmd=save ?&XHR=1", function(data) {
        FW_okDialog('<pre>'+data+'</pre>',parent);
      });
    });

  $("form").each(function(){                             // shutdown handling
    var input = $(this).find("input.maininput");
    if(!input.length)
      return;
    $(this).on("submit", function() {
      if($(input).val().match(/^\s*shutdown/)) {
        FW_cmd(FW_root+"?XHR=1&cmd="+$(input).val());
        $(input).val("");
        return false;
      }
      return true;
    });
  });

  $("div.devSpecHelp a").each(function(){       // Help on detail window
    var dev = FW_getLink(this).split("#").pop();
    $(this).unbind("click");
    $(this).attr("href", "#"); // Desktop: show underlined Text
    $(this).removeAttr("onclick");

    $(this).click(function(evt){
      if($("#devSpecHelp").length) {
        $("#devSpecHelp").remove();
        return;
      }
      $("#content").append('<div id="devSpecHelp"></div>');
      FW_cmd(FW_root+"?cmd=help "+dev+"&XHR=1", function(data) {
        $("#devSpecHelp").html(data);
        var off = $("#devSpecHelp").position().top-20;
        $('body, html').animate({scrollTop:off}, 500);
      });
    });
  });


}


if(window.jQuery) {
  $(document).ready(FW_jqueryReadyFn);

} else {
  // FLOORPLAN compatibility
  loadScript("pgm2/jquery.min.js", function() {
    loadScript("pgm2/jquery-ui.min.js", function() {
      FW_jqueryReadyFn();
    }, true);
  }, true);
}

// FLOORPLAN compatibility
function
FW_delayedStart()
{
  setTimeout("FW_longpoll()", 100);
}
    


function
log(txt)
{
  var d = new Date();
  var ms = ("000"+(d.getMilliseconds()%1000));
  ms = ms.substr(ms.length-3,3);
  txt = d.toTimeString().substring(0,8)+"."+ms+" "+txt;
  if(typeof window.console != "undefined")
    console.log(txt);
}

function
addcsrf(arg)
{
  var csrf = document.body.getAttribute('fwcsrf');
  if(csrf && arg.indexOf('fwcsrf') < 0)
    arg += '&fwcsrf='+csrf;
  return arg;
}

function
FW_cmd(arg, callback)
{
  log("FW_cmd:"+arg);
  arg = addcsrf(arg);
  var req = new XMLHttpRequest();
  req.open("POST", arg, true);
  req.send(null);
  req.onreadystatechange = function(){
    if(req.readyState == 4 && req.responseText) {
      if(callback)
        callback(req.responseText);
      else
        FW_errmsg(req.responseText, 5000);
    }
  }
}

function
FW_errmsg(txt, timeout)
{
  log("ERRMSG:"+txt+"<");
  var errmsg = document.getElementById("errmsg");
  if(!errmsg) {
    if(txt == "")
      return;
    errmsg = document.createElement('div');
    errmsg.setAttribute("id","errmsg");
    document.body.appendChild(errmsg);
  }
  if(txt == "") {
    document.body.removeChild(errmsg);
    return;
  }
  errmsg.innerHTML = txt;
  if(timeout)
    setTimeout("FW_errmsg('')", timeout);
}

function
FW_okDialog(txt, parent)
{
  var div = $("<div id='FW_okDialog'>");
  $(div).html(txt);
  $("body").append(div);
  $(div).dialog({
    dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    buttons: [{text:"OK", click:function(){
      $(this).dialog("close");
      $(div).remove();
    }}]
  });

  FW_replaceWidgets(div);
  $(div).find("a").each(function(){FW_replaceLink(this);}); //Forum #33766

  if(parent)
    $(div).dialog( "option", "position", {
      my: "left top", at: "right bottom",
      of: parent, collision: "flipfit"
    });
}

function
FW_menu(evt, el, arr, dis, fn, embedEl)
{
  if(!embedEl)
    evt.stopPropagation();
  if($("#fwmenu").length) {
    delfwmenu();
    return;
  }

  var html = '<ul id="fwmenu">';
  for(var i=0; i<arr.length; i++) {
    html+='<li class="'+ ((dis && dis[i]) ? 'ui-state-disabled' : '')+'">'+
            '<a row="'+i+'" href="#">'+arr[i]+'</a></li>';
  }
  html += '</ul>';
  $("body").append(html);

  function
  delfwmenu()
  {
    $("ul#fwmenu").remove();
    $('html').unbind('click.fwmenu');
  }

  var wt = $(window).scrollTop();
  $("#fwmenu")
    .menu({
      select: function(e,ui) { // changes the scrollTop();
        e.stopPropagation();
        fn($(e.currentTarget).find("[row]").attr("row"));
        delfwmenu();
        setTimeout(function(){ $(window).scrollTop(wt) }, 1); // Bug in select?
      }
    });

  var off = $(el).offset();
  if(embedEl) {
    var embOff = $(embedEl).offset();
    off.top += embOff.top;
    off.left += embOff.left;
  }
  var dH = $("#fwmenu").height(), dW = $("#fwmenu").width(), 
      wH = $(window).height(), wW = $(window).width();
  var ey = off.top+dH+20, ex = off.left+dW;
  if(ex>wW && ey>wH) { off.top -= dH; off.left -= (dW+16);
  } else if(ey > wH) { off.top -= dH; off.left += 20;
  } else if(ex > wW) {                off.left -= (dW+16);
  } else {             off.top += 20;
  }

  $("#fwmenu").css(off);
  $('html').bind('click.fwmenu', function() { delfwmenu(); });
}

function
FW_getLink(el)
{
  var attr = $(el).attr("href");
  if(!attr) {
    attr = $(el).attr("onclick");   // Tablet/smallScreen version
    if(!attr)
      return "";
    attr = attr.replace(/^location.href='/,'');
    attr = attr.replace(/'$/,'');
  }
  return attr;
}

function
FW_replaceLink(el)
{
  var attr = FW_getLink(el);
  if(!attr)
    return;

  var ma = attr.match(/^(.*\?)(cmd[^=]*=.*)$/);
  if(ma == null || ma.length == 0 || !ma[2].match(/=(save|set)/)) {
    ma = attr.match(new RegExp("^"+FW_root)); // Avoid "Connection lost" @iOS
    if(ma) {
      $(el).click(function(e) {
        if(e.shiftKey || e.ctrlKey || e.metaKey) // Open link in window/tab
          return;
        FW_leaving = 1;
        if($(el).attr("target") == "_blank") {
          window.open(url, '_blank').focus();
        } else {
          location.href = attr;
        }
      });
    }
    return;
  }
  $(el).removeAttr("href");
  $(el).removeAttr("onclick");
  $(el).click(function() { 
    FW_cmd(attr+"&XHR=1", function(txt){
      if(!txt)
        return;
      if(ma[2].match(/=set/)) // Forum #38875
        FW_okDialog(txt, el);
      else
        FW_errmsg(txt, 5000);
    });
  });
  $(el).css("cursor", "pointer");
}


/*************** LONGPOLL START **************/
var FW_pollConn;
var FW_longpollOffset = 0;
var FW_leaving;

function
FW_doUpdate()
{
  if(FW_pollConn.readyState == 4 && !FW_leaving) {
    FW_errmsg("Connection lost, trying a reconnect every 5 seconds.", 4900);
    setTimeout(FW_longpoll, 5000);
    return; // some problem connecting
  }

  if(FW_pollConn.readyState != 3)
    return;

  var input = FW_pollConn.responseText;
  var devs = new Array();
  if(input.length <= FW_longpollOffset)
    return;

  FW_serverLastMsg = (new Date()).getTime()/1000;
  for(;;) {
    var nOff = input.indexOf("\n", FW_longpollOffset);
    if(nOff < 0)
      break;
    var l = input.substr(FW_longpollOffset, nOff-FW_longpollOffset);
    FW_longpollOffset = nOff+1;

    log("Rcvd: "+(l.length>132 ? l.substring(0,132)+"...("+l.length+")":l));
    if(!l.length)
      continue;
    var d = JSON.parse(l);
    if(d.length != 3)
      continue;

    if( d[0].match(/^#FHEMWEB:/) ) {
      eval(d[1]);

    } else {
      $("[informId='"+d[0]+"']").each(function(){
        if(this.setValueFn) {     // change the select/etc value
          this.setValueFn(d[1]);

        } else {
          $(this).html(d[2]);     // Readings-Value
          if(d[0].match(/-ts$/))  // timestamps
            $(this).addClass('changed');
          $(this).find("a").each(function() { FW_replaceLink(this) });
        }
      });
    }

    for(var w in FW_widgets)
      if(FW_widgets[w].updateLine) // updateLine is deprecated, use setValueFn
        FW_widgets[w].updateLine(d);

    devs.push(d);
  }

  for(var w in FW_widgets)
    if(FW_widgets[w].updateDevs) // used for SVG to avoid double-reloads
      FW_widgets[w].updateDevs(devs);

  // reset the connection to avoid memory problems
  if(FW_longpollOffset > 1024*1024 && FW_longpollOffset==input.length)
    FW_longpoll();
}

function
FW_longpoll()
{
  FW_longpollOffset = 0;
  if(FW_pollConn) {
    FW_leaving = 1;
    FW_pollConn.abort();
  }

  FW_pollConn = new XMLHttpRequest();
  FW_leaving = 0;

  // Build the notify filter for the backend
  var filter = $("body").attr("longpollfilter");
  if(filter == null)
    filter = "";
  if(filter == "") {
    $("embed").each(function() {
      if($(this.getSVGDocument()).find("svg[flog]").attr("flog"))
        filter=".*";
    });
  }

  if(filter == "") {
    var sa = location.search.substring(1).split("&");
    for(var i = 0; i < sa.length; i++) {
      if(sa[i].substring(0,5) == "room=")
        filter=sa[i];
      if(sa[i].substring(0,7) == "detail=")
        filter=sa[i].substring(7);
    }
  }

  if($("#floorplan").length>0) //floorplan special
    filter += ";iconPath="+$("body").attr("name");

  if(filter == "") {
    var content = document.getElementById("content");
    if(content) {
      var room = content.getAttribute("room");
      if(room)
        filter="room="+room;
    }
  }
  var iP = document.body.getAttribute("iconPath");
  if(iP != null)
    filter = filter +";iconPath="+iP;

  var since = "null";
  if(FW_serverGenerated)
    since = FW_serverLastMsg + (FW_serverGenerated-FW_serverFirstMsg);

  var query = location.pathname+"?XHR=1"+
              "&inform=type=status;filter="+filter+";since="+since+";fmt=JSON"+
              "&timestamp="+new Date().getTime();
  query = addcsrf(query);
  FW_pollConn.open("GET", query, true);
  FW_pollConn.onreadystatechange = FW_doUpdate;
  FW_pollConn.send(null);

  log("Longpoll with filter "+filter);
}

/*************** LONGPOLL END **************/


/*************** WIDGETS START **************/
/*************** "Double" select in detail window ****/
function
FW_detailSelect(selEl)
{
  if(selEl.target)
    selEl = selEl.target;
  var selVal = $(selEl).val();

  var div = $(selEl).closest("div.makeSelect");
  var arg,
      listArr = $(div).attr("list").split(" "),
      devName = $(div).attr("dev"),
      cmd = $(div).attr("cmd");

  for(var i1=0; i1<listArr.length; i1++) {
    arg = listArr[i1];
    if(arg.indexOf(selVal) == 0 &&
       (arg.length == selVal.length || arg[selVal.length] == ':'))
      break;
  }
  if(!arg)
    return;

  var vArr = [];
  if(arg.length > selVal.length)
    vArr = arg.substr(selVal.length+1).split(","); 

  var newEl = FW_replaceWidget($(selEl).next(), devName, vArr,undefined,selVal);
  if(cmd == "attr")
    FW_queryValue('{AttrVal("'+devName+'","'+selVal+'","")}', newEl);

  if(cmd == "set")
    FW_queryValue('{ReadingsVal("'+devName+'","'+selVal+'","")}', newEl);
}

function
FW_replaceWidget(oldEl, devName, vArr, currVal, reading, set, params, cmd)
{
  var newEl, wn;
  var elName = $(oldEl).attr("name");
  if(!elName)
    elName = $(oldEl).find("[name]").attr("name");

  if(vArr.length == 0) { //  No parameters, input field
    newEl = FW_createTextField(elName, devName, ["textField"], currVal,
                               set, params, cmd);
    wn = "textField";

  } else {
    for(wn in FW_widgets) {
      if(FW_widgets[wn].createFn) {
        newEl = FW_widgets[wn].createFn(elName, devName, vArr, currVal,
                                        set, params, cmd);
        if(newEl)
          break;
      }
    }

    if(!newEl) { // Select as fallback
     vArr.unshift("select");
     newEl = FW_createSelect(elName, devName, vArr, currVal, set, params, cmd);
     wn = "select";
    }
  }

  if(!newEl) { // Simple link
    newEl = $('<div class="col3"><a style="cursor: pointer;">'+
                set+' '+params.join(' ')+ '</a></div>');
    $(newEl).click(function(arg) { cmd(params[0]) });
    $(oldEl).replaceWith(newEl);
    return newEl;
  }

  $(newEl).addClass(wn+"_widget");

  if( $(newEl).find("[informId]").length == 0 && !$(newEl).attr("informId") ) {
    if(reading && reading == "state")
      $(newEl).attr("informId", devName);
    else if(reading)
      $(newEl).attr("informId", devName+"-"+reading);
  }

  $(oldEl).replaceWith(newEl);

  if(newEl.activateFn) // CSS is not applied if newEl is not in the document
    newEl.activateFn();
  return newEl;
}

function
FW_queryValue(cmd, el)
{
  log("FW_queryValue:"+cmd);
  var query = location.pathname+"?cmd="+cmd+"&XHR=1";
  query = addcsrf(query);
  var qConn = new XMLHttpRequest();
  qConn.onreadystatechange = function() {
    if(qConn.readyState != 4)
      return;
    var qResp = qConn.responseText.replace(/[\r\n]/g, "");
    if(el.setValueFn)
      el.setValueFn(qResp);
    qConn.abort();
  }
  qConn.open("GET", query, true);
  qConn.send(null);
}

function
FW_querySetSelected(el, val)    // called by the attribute links
{
  $("#"+el).val(val);
  FW_detailSelect("#"+el);
}

/*************** TEXTFIELD **************/
function
FW_createTextField(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length != 1 ||
     (vArr[0] != "textField" && vArr[0] != "textField-long") ||
     (params && params.length))
    return undefined;
  
  var is_long = (vArr[0] == "textField-long");

  var newEl = $("<div style='display:inline-block'>").get(0);
  if(set && set != "state")
    $(newEl).append(set+":");
  $(newEl).append('<input type="text" size="30">');
  var inp = $(newEl).find("input").get(0);
  if(elName)
    $(inp).attr('name', elName);
  if(currVal != undefined)
    $(inp).val(currVal);

  function addBlur() { if(cmd) $(inp).blur(function() { cmd($(inp).val()) }); };

  newEl.setValueFn = function(arg){ $(inp).val(arg) };
  addBlur();

  var myFunc = function(){
    
    $(inp).unbind("blur");
    $('body').append(
      '<div id="editdlg" style="display:none">'+
        '<textarea id="td_longText" rows="25" cols="60" style="width:99%"/>'+
      '</div>');

    $("#td_longText").val($(inp).val());

    var cm;
    if( typeof AddCodeMirror == 'function' ) 
      AddCodeMirror($("#td_longText").get(0), function(pcm) {cm = pcm;});

    $('#editdlg').dialog(
      { modal:true, closeOnEscape:true, width:$(window).width()*3/4,
        maxHeight:$(window).height()*3/4,
        close:function(){ $('#editdlg').remove(); },
        buttons:[
        { text:"Cancel", click:function(){
          $(this).dialog('close');
          addBlur();
        }},
        { text:"OK", click:function(){
          if(cm)
            $("#td_longText").val(cm.getValue());
          var res=$("#td_longText").val();
          $(this).dialog('close');
          $(inp).val(res);
          addBlur();
        }}]
      });
  };

  if( is_long )
    $(newEl).click(myFunc);

  return newEl;
}

/*************** select **************/
function
FW_createSelect(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length < 2 || vArr[0] != "select" || (params && params.length))
    return undefined;
  var newEl = document.createElement('select');
  var vHash = {};
  for(var j=1; j < vArr.length; j++) {
    var o = document.createElement('option');
    o.text = o.value = vArr[j].replace(/#/g," ");
    vHash[vArr[j]] = 1;
    newEl.options[j-1] = o;
  }
  if(currVal)
    $(newEl).val(currVal);
  if(elName)
    $(newEl).attr('name', elName);
  if(cmd)
    $(newEl).change(function(arg) { cmd($(newEl).val()) });
  newEl.setValueFn = function(arg) { if(vHash[arg]) $(newEl).val(arg); };
  return newEl;
}

/*************** noArg **************/
function
FW_createNoArg(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length != 1 || vArr[0] != "noArg" || (params && params.length))
    return undefined;
  var newEl = $('<div style="display:none">').get(0);
  if(elName) 
    $(newEl).append('<input type="hidden" name="'+elName+ '" value="">');
  return(newEl);
}

/*************** slider **************/
function
FW_createSlider(elName, devName, vArr, currVal, set, params, cmd)
{
  // min, step, max, float
  if(vArr.length < 4 || vArr.length > 5 || vArr[0] != "slider" ||
     (params && params.length))
    return undefined;

  var min = parseFloat(vArr[1]);
  var stp = parseFloat(vArr[2]);
  var max = parseFloat(vArr[3]);
  var flt = vArr[4];
  if(currVal != undefined)
    currVal = currVal.replace(/[^\d.\-]/g, "");
  currVal = (currVal==undefined || currVal=="") ?  min : parseFloat(currVal);
  if(max==min)
    return undefined;
  if(currVal < min || currVal > max)
    currVal = min;

  var newEl = $('<div style="display:inline-block" tabindex="0">').get(0);
  var slider = $('<div class="slider" id="slider.'+devName+'">').get(0);
  $(newEl).append(slider);

  var sh = $('<div class="handle">'+currVal+'</div>').get(0);
  $(slider).append(sh);
  if(elName)
    $(newEl).append('<input type="hidden" name="'+elName+
                        '" value="'+currVal+'">');

  var lastX=-1, offX=0, maxX=0, val;

  newEl.activateFn = function() {
    if(currVal < min || currVal > max)
      return;
    maxX = slider.offsetWidth-sh.offsetWidth;
    offX = (currVal-min)*maxX/(max-min);
    sh.innerHTML = currVal;
    sh.setAttribute('style', 'left:'+offX+'px;');
    if(elName)
      slider.nextSibling.setAttribute('value', currVal);
  }

  $(newEl).keydown(function(e){
    if(e.keyCode == 37) currVal -= stp;
    if(e.keyCode == 39) currVal += stp;
    if(currVal < min) currVal = min;
    if(currVal > max) currVal = max;
    offX = (currVal-min)*maxX/(max-min);
    sh.innerHTML = currVal;
    sh.setAttribute('style', 'left:'+offX+'px;');
    if(cmd)
      cmd(currVal);
    if(elName)
      slider.nextSibling.setAttribute('value', currVal);
  });

  function
  touchFn(e, fn)
  {
    e.preventDefault(); // Prevents Safari from scrolling!
    if(e.touches == null || e.touches.length == 0)
      return;
    e.clientX = e.touches[0].clientX;
    fn(e);
  }

  function
  mouseDown(e)
  {
    var oldFn1 = document.onmousemove, oldFn2 = document.onmouseup,
        oldFn3 = document.ontouchmove, oldFn4 = document.ontouchend;

    lastX = e.clientX;  // Does not work on IE8

    function
    mouseMove(e)
    {
      if(maxX == 0) // Forum #35846
        maxX = slider.offsetWidth-sh.offsetWidth;
      var diff = e.clientX-lastX; lastX = e.clientX;
      offX += diff;
      if(offX < 0) offX = 0;
      if(offX > maxX) offX = maxX;
      val = offX/maxX * (max-min);
      val = (flt ? Math.floor(val/stp)*stp :
                   Math.floor(Math.floor(val/stp)*stp))+min;
      sh.innerHTML = val;
      sh.setAttribute('style', 'left:'+offX+'px;');
    }
    document.onmousemove = mouseMove;
    document.ontouchmove = function(e) { touchFn(e, mouseMove); }

    document.onmouseup = document.ontouchend = function(e)
    {
      document.onmousemove = oldFn1; document.onmouseup  = oldFn2;
      document.ontouchmove = oldFn3; document.ontouchend = oldFn4;
      if(cmd)
        cmd(val);
      if(elName)
        slider.nextSibling.setAttribute('value', val);
    };
  };

  sh.onselectstart = function() { return false; }
  sh.onmousedown = mouseDown;
  sh.ontouchstart = function(e) { touchFn(e, mouseDown); }

  newEl.setValueFn = function(arg) {
    var res = arg.match(/[\d.\-]+/); // extract first number
    currVal = (res ? parseFloat(res[0]) : min);
    if(currVal < min || currVal > max)
      currVal = min;
    newEl.activateFn();
  };
  return newEl;
}


/*************** TIME **************/
function
FW_createTime(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length != 1 || vArr[0] != "time" || (params && params.length))
    return undefined;
  var open="-", closed="+";

  var newEl = document.createElement('div');
  $(newEl).append('<input type="text" size="5">');
  $(newEl).append('<input type="button" value="'+closed+'">');

  var inp = $(newEl).find("[type=text]");
  var btn = $(newEl).find("[type=button]");
  currVal = (currVal ? currVal : "12:00")
            .replace(/[^\d]*(\d\d):(\d\d).*/g,"$1:$2");
  $(inp).val(currVal)
  if(elName)
    $(inp).attr("name", elName);

  var hh, mm;   // the slider elements
  newEl.setValueFn = function(arg) {
    arg = arg.replace(/[^\d]*(\d\d):(\d\d).*/g,"$1:$2");
    $(inp).val(arg);
    var hhmm = arg.split(":");
    if(hhmm.length == 2 && hh && mm) {
      hh.setValueFn(hhmm[0]);
      mm.setValueFn(hhmm[1]);
    }
  };

  $(btn).click(function(){      // Open/Close the slider view
    var v = $(inp).val();

    if($(btn).val() == open) {
      $(btn).val(closed);
      $(newEl).find(".timeSlider").remove();
      hh = mm = undefined;
      if(cmd)
        cmd(v);
      return;
    }

    $(btn).val(open);
    if(v.indexOf(":") < 0) {
      v = "12:00";
      $(inp).val(v);
    }
    var hhmm = v.split(":");

    function
    tSet(idx, arg)
    {
      if((""+arg).length < 2)
        arg = '0'+arg;
      hhmm[idx] = arg;
      $(inp).val(hhmm.join(":"));
    }

    $(newEl).append('<div class="timeSlider">');
    var ts = $(newEl).find(".timeSlider");

    hh = FW_createSlider(undefined, devName+"HH", ["slider", 0, 1, 23],
                hhmm[0], undefined, params, function(arg) { tSet(0, arg) });
    mm = FW_createSlider(undefined, devName+"MM", ["slider", 0, 5, 55],
                hhmm[1], undefined, params, function(arg) { tSet(1, arg) });
    $(ts).append("<br>"); $(ts).append(hh); hh.activateFn();
    $(ts).append("<br>"); $(ts).append(mm); mm.activateFn();
  });

  return newEl;
}

/*************** MULTIPLE **************/
function
FW_createMultiple(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length < 2 || (vArr[0]!="multiple" && vArr[0]!="multiple-strict") ||
     (params && params.length))
    return undefined;
  
  var newEl = $('<input type="text" size="30" readonly>').get(0);
  if(currVal)
    $(newEl).val(currVal);
  if(elName)
    $(newEl).attr("name", elName);
  newEl.setValueFn = function(arg){ $(newEl).val(arg) };

  for(var i1=1; i1<vArr.length; i1++)
    vArr[i1] = vArr[i1].replace(/#/g, " ");

  $(newEl).focus(function(){
    var sel = $(newEl).val().split(","), selObj={};
    for(var i1=0; i1<sel.length; i1++)
      selObj[sel[i1]] = 1;

    var table = "";
    for(var i1=1; i1<vArr.length; i1++) {
      var v = vArr[i1];
      table += '<tr>'+ // funny stuff for ios6 style, forum #23561
        '<td><div class="checkbox"><input name="'+v+'" type="checkbox"'+
              (selObj[v] ? " checked" : "")+'/>'+
                      '<label for="'+v+'"><span></span></label></div></td>'+
        '<td><label for="' +v+'">'+v+'</label></td></tr>';
      delete(selObj[v]);
    }

    var selArr=[];
    for(var i1 in selObj)
      selArr.push(i1);
    
    var strict = (vArr[0] == "multiple-strict");
    $('body').append(
      '<div id="multidlg" style="display:none">'+
        '<table>'+table+'</table>'+(!strict ? '<input id="md_freeText" '+
              'value="'+selArr.join(',')+'"/>' : '')+
      '</div>');

    $('#multidlg').dialog(
      { modal:true, closeOnEscape:false, maxHeight:$(window).height()*3/4,
        buttons:[
        { text:"Cancel", click:function(){ $('#multidlg').remove(); }},
        { text:"OK", click:function(){
          var res=[];
          if($("#md_freeText").val())
            res.push($("#md_freeText").val());
          $("#multidlg table input").each(function(){
            if($(this).prop("checked"))
              res.push($(this).attr("name"));
          });
          $('#multidlg').remove();
          $(newEl).val(res.join(","));
          if(cmd)
            cmd(res.join(","));
        }}]});
  });
  return newEl;
}

/*************** WIDGETS END **************/


/*************** SCRIPT LOAD FUNCTIONS START **************/
function
loadScript(sname, callback, force)
{
  var h = document.head || document.getElementsByTagName('head')[0];
  sname = FW_root+"/"+sname;
  if(FW_scripts[sname]) {
    if(FW_scripts[sname].loaded) {
      if(callback)
        callback();
    } else {
      FW_scripts[sname].callbacks.push(callback);
    }
    return;
  }
  if(!FW_docReady && !force) {
    FW_scripts[sname] = { callbacks:[ callback] };
    return;
  }

  var script = document.createElement("script");
  script.src = sname;
  script.async = script.defer = false;
  script.type = "text/javascript";
  FW_scripts[sname] = { callbacks:[ callback] };

  function
  scriptLoaded()
  {
    var p = FW_scripts[sname];
    p.loaded = true;
    if(!p.called) {
      p.called = true;
      for(var i1=0; i1< p.callbacks.length; i1++)
        if(p.callbacks[i1]) // pushing undefined callbacks on the stack is ok
          p.callbacks[i1]();
    }
    delete(p.callbacks);
  }

  log("Loading script "+sname);
  if(FW_isIE) {
    script.onreadystatechange = function() {
      if(script.readyState == 'loaded' || script.readyState == 'complete') {
        script.onreadystatechange = null;
        scriptLoaded();
      }
    }

  } else {
    if(FW_isiOS) {
      FW_leaving = 1;
      if(FW_pollConn)
        FW_pollConn.abort();
    }
    script.onload = function(){
      scriptLoaded();
      if(FW_isiOS)
        FW_longpoll();
    }
  }
  h.appendChild(script);
}

function
loadLink(lname)
{
  var h = document.head || document.getElementsByTagName('head')[0];
  lname = FW_root+"/"+lname;

  var arr = h.getElementsByTagName("link");
  for(var i1=0; i1<arr.length; i1++)
    if(lname == arr[i1].getAttribute("href"))
      return;
  var link = document.createElement("link");
  link.href = lname;
  link.rel = "stylesheet";
  log("Loading link "+lname);
  h.appendChild(link);
}

function
scriptAttribute(sname)
{
  var attr="";
  $("head script").each(function(){
    var src = $(this).attr("src");
    if(src && src.indexOf(sname) >= 0)
      attr = $(this).attr("attr");
  });

  var ua={};
  if(attr && attr != "") {
    try {
      ua=JSON.parse(attr);
    } catch(e){
      FW_errmsg(sname+" Parameter "+e,5000);
    }
  }
  return ua;
}
/*************** SCRIPT LOAD FUNCTIONS END **************/
