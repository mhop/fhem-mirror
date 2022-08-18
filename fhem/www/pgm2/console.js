"use strict";
FW_version["console.js"] = "$Id$";

var consConn;
var consName="#console";

var consFilter, oldFilter, consFType="";
var consLastIndex = 0;
var withLog = 0;
var mustScroll = 1;

log("Event monitor is starting!");

function
cons_closeConn()
{
  if(!consConn)
    return;
  if(typeof consConn.close ==  "function")
    consConn.close();
  else if(typeof consConn.abort ==  "function")
    consConn.abort();
  consConn = undefined;
}

function
consAppender(new_content)
{
  // Extract the FHEM-Log, to avoid escaping its formatting (Forum #104842)
  var logContent = "";
  var rTab = {'<':'&lt;', '>':'&gt;',' ':'&nbsp;', '\n':'<br>' };
  new_content = new_content.replace(
  /(<div class='fhemlog'>)([\s\S]*?)(<\/div>)/gm,
  function(all, div1, msg, div2) {
    logContent += div1+
                  msg.replace(/[<> \n]/g, function(a){return rTab[a]})+
                  div2;
    return "";
  });

  var isTa = $(consName).is("textarea"); // 102773
  var ncA = new_content.split(/<br>[\r\n]/);
  for(var i1=0; i1<ncA.length; i1++)
    ncA[i1] = ncA[i1].replace(/[<> ]/g, function(a){return rTab[a]});
  $(consName).append(logContent+ncA.join(isTa?"\n":"<br>"));
}

function
consUpdate(evt)
{
  var errstr = "Connection lost, trying a reconnect every 5 seconds.";
  var new_content = "";

  if((typeof WebSocket == "function" || typeof WebSocket == "object") && evt &&
     evt.target instanceof WebSocket) {
    if(evt.type == 'close') {
      FW_errmsg(errstr, 4900);
      cons_closeConn();
      setTimeout(consFill, 5000);
      return;
    }
    new_content = evt.data;
    consLastIndex = 0;

  } else {
    if(consConn.readyState == 4) {
      FW_errmsg(errstr, 4900);
      setTimeout(consFill, 5000);
      return;
    }

    if(consConn.readyState != 3)
      return;

    var len = consConn.responseText.length;
    if (consLastIndex == len) // No new data
      return; 
   
    new_content = consConn.responseText.substring(consLastIndex, len);
    consLastIndex = len;
  }
  if(new_content == undefined || new_content.length == 0)
    return;
  if(new_content.length < 120)
    log("console Rcvd: "+new_content);
  else
    log("console Rcvd: "+new_content.substr(0,120)+
        "..., truncated, original length "+new_content.length);

  consAppender(new_content);
    
  if(mustScroll)
    $(consName).scrollTop($(consName)[0].scrollHeight);
}

function
consFill()
{
  FW_errmsg("");

  if(FW_pollConn)
    FW_closeConn();

  var query = "?XHR=1&inform="+
        encodeURIComponent("type=raw;withLog="+withLog+
                                   ";filter="+consFilter+consFType)+
       "&fw_id="+$("body").attr('fw_id')+
       "&timestamp="+new Date().getTime();
  query = addcsrf(query);

  var loc = (""+location).replace(/\?.*/,"");
  if($("body").attr("longpoll") == "websocket") {
    if(consConn) {
      consConn.onclose = 
      consConn.onerror = 
      consConn.onmessage = undefined;
      consConn.close();
    }
    consConn = new WebSocket(loc.replace(/[&?].*/,'')
                                .replace(/^http/i, "ws")+query);
    consConn.onclose = 
    consConn.onerror = 
    consConn.onmessage = consUpdate;

  } else {
    if(consConn) {
      consConn.onreadystatechange = undefined;
      consConn.abort();
    }
    consConn = new XMLHttpRequest();
    consConn.open("GET", loc+query, true);
    consConn.onreadystatechange = consUpdate;
    consConn.send(null);

  }

  consLastIndex = 0;
  if(oldFilter != consFilter)  // only clear, when filter changes
    $(consName).html("");
  
  oldFilter = consFilter;
}

function
consStart()
{
  if($(consName).length != 1)
    return;

  if($("a#eventFilter").length)
    consFilter = $("a#eventFilter").html();
  if(consFilter == undefined)
    consFilter = ".*";
  oldFilter = consFilter;
  withLog = ($("#eventWithLog").is(':checked') ? 1 : 0);
  setTimeout(consFill, 1000);
  
  $("#eventReset").click(function(evt){  // Event Monitor Reset
    log("Console resetted by user");
    $(consName).html("");
  });
  
  $("#eventFilter").click(function(evt){  // Event-Filter Dialog
    $('body').append(
      '<div id="evtfilterdlg">'+
        '<div>Filter (Regexp):</div><br>'+
        '<div><input id="filtertext" value="'+consFilter+'"></div><br>'+
        '<div>'+
          '<input id="f" type="radio" name="x"> Match the whole line</br>'+
          '<input id="n" type="radio" name="x"> Notify-Type: deviceName:event'+
        '</div>'+
      '</div>');
    $("#evtfilterdlg input#"+(consFType=="" ? "f" : "n")).prop("checked",true);

    $('#evtfilterdlg').dialog({ modal:true, width:'auto',
      position:{ my: "left top", at: "right bottom",
                 of: this, collision: "flipfit" },
      close:function(){$('#evtfilterdlg').remove();},
      buttons:[
        { text:"Cancel", click:function(){ $(this).dialog('close'); }},
        { text:"OK", click:function(){
          var val = $("#filtertext").val().trim();
          try { 
            new RegExp(val ? val : ".*");
          } catch(e) {
            return FW_okDialog(e);
          }
          consFilter = val ? val : ".*";
          consFType= ($("#evtfilterdlg input#n").is(":checked")) ?
                                ";filterType=notify" : "";
          $(this).dialog('close');
          $("a#eventFilter").html(consFilter);
          consFill();
        }}]
    });
  });

  $("#eventWithLog").change(function(evt){  // Event-Filter Dialog
    withLog = ($("#eventWithLog").is(':checked') ? 1 : 0);
    consFill();
  });
  
  
  $(consName).scroll(function() { // autoscroll check
    
    if($(consName)[0].scrollHeight - $(consName).scrollTop() <=
       $(consName).outerHeight() + 2) { 
      if(!mustScroll) {
        mustScroll = 1;
        log("Console autoscroll restarted");
      }
    } else {
      if(mustScroll) {
        mustScroll = 0;  
        log("Console autoscroll stopped");
      }
    }
  });
  consAddRegexpPart();
}

function
consAddRegexpPart()
{
  $("<button style='margin-left:1em' id='addRegexpPart'>"+
    "Create/Modify Device</button>").insertAfter("button#eventReset");

  var knownTypes = {
    "notify": { modify:    "set modDev addRegexpPart evtDev event",
                createArg: "evtDev:event {}" },
    "FileLog":{ modify:    "set modDev addRegexpPart evtDev event",
                createArg: "./log/modDev.log evtDev:event" },
    "watchdog":{createArg: "evtDev:event 00:15 SAME {}" },
    "sequence":{createArg: "evtDev:event 00:15 evtDev:event" },
    "average":{createArg: "evtDev:event" },
    "DOIF":{createArg: "([evtDev:\"^event$\"]) ()" }
  };

  var modDev, devList, devHash = {};
  var creates = [];
  for(var t in knownTypes)
    if(knownTypes[t].createArg)
      creates.push(t);

  $("button#addRegexpPart").click(function(){
    // get selection, build regexp from event
    var txt = window.getSelection().toString();
    var hlp = "Please highlight exactly one complete event line";
    if(!txt)
      return FW_okDialog(hlp);
    var re=/^....-..-..\s..:..:..(\....)?\s([^\s]+)\s([^\s]+)\s(.*)([\r\n]*)?$/;
    var ret = txt.match(re);
    if(!ret)
      return FW_okDialog(hlp);

    var evtDev=ret[3];
    var evt1 = ret[4].replace(/\s/g, ".")
                     .replace(/[\^\$\[\]\(\)\\]/g, function(s){return"\\"+s});
    var evt2 = evt1.replace(/\b-?\d*\.?\d+\b/g,'.*')
                   .replace(/\.+\*(\.+\*)*/g,'.*');

    // build the dialog
    var txt = '<style type="text/css">\n'+
              'div.evt label { display:block; margin-left:2em; }\n'+
              'div.evt input { float:left; }\n'+
              '</style>\n';

    var inputPrf="<input type='radio' name="
    txt += inputPrf+"'defmod' id='def' checked/><label>Create</label>"+
           inputPrf+"'defmod' id='mod'/><label>Modify</label><br><br>"
    txt += "<select id='modDev' style='display:none'></select>";
    txt += "<select id='newType'><option>"+
              creates.sort().join("</option><option>")+
           "</select><br><br>";

    if(evt1 != evt2) {
      txt += "<div class='evt'>"+inputPrf+"'evtType' id='rdEx' checked/>"+
             "<label>with exactly this event</div><br>";
      txt += "<div class='evt'>"+inputPrf+"'evtType' id='rdNum'/>"+
             "<label>with any number matching</label></div><br>";
    }
    txt += "<div class='evt' id='cmd'>&nbsp;</txt>";

    $('body').append('<div id="evtCoM" style="display:none">'+txt+'</div>');
    $('#evtCoM').dialog(
      { modal:true, closeOnEscape:true, width:"auto",
        close:function(){ $('#evtCoM').remove(); },
        buttons:[
        { text:"Cancel", click:function(){ $(this).dialog('close'); }},
        { text:"OK", click:function(){
          FW_cmd(FW_root+"?cmd="+$("#evtCoM #cmd").html()+"&XHR=1");
          $(this).dialog('close');
          location = FW_root+'?detail='+modDev;
        }}],
        open:function(){
          $("#evtCoM #newType").val("notify");
          $("#evtCoM input,#evtCoM select").change(optChanged);
        }
      });

    function
    optChanged()
    {
      var event = evt1;
      if(evt1 != evt2 && $("#evtCoM #rdNum").is(":checked"))
        event = evt2;
      var cmd;

      if($("#evtCoM #def").is(":checked")) {    // define
        $("#evtCoM #newType").show();
        $("#evtCoM #modDev").hide();
        var type = $("#evtCoM #newType").val(), num=1;
        var nRe = new RegExp(evtDev+"_"+type+"_(\\d+)");
        for(var i1=0; i1<devList.length; i1++) {
          var m = nRe.exec(devList[i1].Name);
          if(m && m[1] >= num)
            num = parseInt(m[1])+1;
        }
        modDev = evtDev+"_"+type+"_"+num;
        cmd = "define "+modDev+" "+type+" "+knownTypes[type].createArg;

      } else {
        $("#evtCoM #newType").hide();
        $("#evtCoM #modDev").show();
        modDev = $("#evtCoM #modDev").val();
        cmd = knownTypes[devHash[modDev].Internals.TYPE].modify;

      }

      $("#evtCoM #cmd").text(cmd
                             .replace(/modDev/g,modDev)
                             .replace(/evtDev/g,evtDev)
                             .replace(/event/g,event));
    }

    FW_cmd(FW_root+"?cmd=jsonlist2 .* TYPE&XHR=1", function(data){
      devList = JSON.parse(data).Results;
      for(var i1=0; i1<devList.length; i1++) {
        var dev = devList[i1], type = dev.Internals.TYPE;
        if(knownTypes[type] && knownTypes[type].modify)
          $("select#modDev").append('<option>'+dev.Name+'</option>');
        devHash[dev.Name] = dev;
      }
      optChanged();
    });
  });
}

var c4d_rowNum=0, c4d_filter=".*"
function
cons4devAppender(new_content)
{
  var cArr = new_content.split("\n");
  for(var i1=0; i1<cArr.length; i1++) {
    var cols = [];

    try { cols = JSON.parse(cArr[i1]); } catch(e) { continue; };
    if(c4d_filter != ".*") {
      var content = cols.join(" ");
      if(!content.match(c4d_filter))
        continue;
    }
    var row = $(`<tr class="${c4d_rowNum++%2 ? 'odd':'even'}"><td>
                 <div class="dname">`+
                  cols.join('</div></td><td><div class="dval">')+
                "</div></td></tr>");
    $(consName+" table").append(row);
    $(row).find("div.dval")           // Format JSON
      .css("cursor", "pointer")
      .click(function(){
        var content = $(this).attr("data-content");
        if(!content) {
          content = $(this).html();
          $(this).attr("data-content", content);
        }
        if(content.match(/^{.*}$/)) {
          try{
            var fmt = $(this).attr("data-fmt");
            fmt = (typeof(fmt)=="undefined" || fmt=="no") ? "yes" : "no";
            $(this).attr("data-fmt", fmt);
            if(fmt=="yes") {
              var js = JSON.parse(content);
              content = '<pre>'+JSON.stringify(js, undefined, 2)+'</pre>';
            }
            $(this).html(content);
          } catch(e) { }
        }
      });
  }
}

function
cons4dev(screenId, filter, feedFn, devName)
{
  $(screenId).find("a")
    .blur()     // remove focus, so return wont open/close it
    .unbind("click")
    .click(toggleOpen);

  consName = screenId+">div.console";
  consFilter = filter;
  consAppender = cons4devAppender;
  var opened;

  function
  toggleOpen()
  {
    $(this).blur();
    var cmd = FW_root+"?cmd="+encodeURIComponent("{"+feedFn+"('"+devName+"',"+
                        (opened ? 0 : 1)+")}")+"&XHR=1";
    if(!opened) {
      $(screenId)
        .append(`<span class="buttons">
                  &nbsp;<a href="#" class="reset">Reset</a>
                  &nbsp;<a href="#" class="filter">Filter:</a>
                  &nbsp;<span class="filterContent">${c4d_filter}</span>
                 </span>`);
      $(screenId)
        .append(`<div class="console">
                   <table class="block wide"></table>
                 </div>`);
      $(consName)
        .width( $("#content").width()-40)
        .height($("#content").height()/2-20)
        .css({overflow:"auto"});
      $(screenId+">a").html($(screenId+">a").html().replace("Show", "Hide"));
      FW_closeConn();
      consStart();
      // Leave time for establishing the connection, else the "feeder" may
      // clear the flag
      setTimeout(function(){ FW_cmd(cmd) }, 100);

      $(screenId+" .reset").click(function(){ $(consName+" table").html("") });
      $(screenId+" .filter").click(function(){
        $('body').append(
          '<div id="filterdlg">'+
            '<div>Filter (Regexp, matching the row):</div><br>'+
            '<div><input id="filtertext" value="'+c4d_filter+'"></div><br>'+
          '</div>');
        $('#filterdlg').dialog({ modal:true, width:'auto',
          position:{ my: "left top", at: "right bottom",
                     of: this, collision: "flipfit" },
          close:function(){$('#filterdlg').remove();},
          buttons:[
            { text:"Cancel", click:function(){ $(this).dialog('close'); }},
            { text:"OK", click:function(){
              var val = $("#filtertext").val().trim();
              try {
                new RegExp(val ? val : ".*");
              } catch(e) {
                return FW_okDialog(e);
              }
              c4d_filter = val ? val : ".*";
              $(this).dialog('close');
              $(screenId+" .filterContent").html(c4d_filter);
              $(consName+" table").html("");
            }}]
        });
      });

    } else {
      FW_cmd(cmd);
      $(consName).remove();
      $(screenId+">a").html($(screenId+">a").html().replace("Hide", "Show"));
      $(screenId+" span.buttons").remove();
      if(consConn) {
        consConn.onclose = undefined;
        cons_closeConn();
      }
      FW_longpoll();
    }
    opened = !opened;
  }

  toggleOpen();
}

window.onload = consStart;
