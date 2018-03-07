"use strict";
FW_version["console.js"] = "$Id$";

var consConn;

var consFilter, oldFilter, consFType="";
var consLastIndex = 0;
var withLog = 0;
var mustScroll = 1;

log("Event monitor is starting");

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
  log("Console Rcvd: "+new_content);
  if(new_content.indexOf('<') != 0)
    new_content = new_content.replace(/ /g, "&nbsp;");
  
  $("#console").append(new_content);
    
  if(mustScroll)
    $("#console").scrollTop($("#console")[0].scrollHeight);
}

function
consFill()
{
  FW_errmsg("");

  if(FW_pollConn)
    FW_closeConn();

  var query = "?XHR=1"+
       "&inform=type=raw;withLog="+withLog+";filter="+
       encodeURIComponent(consFilter)+consFType+
       "&timestamp="+new Date().getTime();
  query = addcsrf(query);

  var loc = (""+location).replace(/\?.*/,"");
  if($("body").attr("longpoll") == "websocket") {
    if(consConn)
      consConn.close();
    consConn = new WebSocket(loc.replace(/[&?].*/,'')
                                .replace(/^http/i, "ws")+query);
    consConn.onclose = 
    consConn.onerror = 
    consConn.onmessage = consUpdate;
    consConn.onopen = function(){FW_wsPing(consConn);};

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
    $("#console").html("");
  
  oldFilter = consFilter;
}

function
consStart()
{
  var el = document.getElementById("console");

  consFilter = $("a#eventFilter").html();
  if(consFilter == undefined)
    consFilter = ".*";
  oldFilter = consFilter;
  withLog = ($("#eventWithLog").is(':checked') ? 1 : 0);
  setTimeout(consFill, 1000);
  
   $("#eventReset").click(function(evt){  // Event Monitor Reset
     log("Console resetted by user");
     $("#console").html("");
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
  
  
  $("#console").scroll(function() { // autoscroll check
    
    if($("#console")[0].scrollHeight - $("#console").scrollTop() <=
       $("#console").outerHeight() + 2) { 
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
    var evt2 = evt1.replace(/\b-?\d*\.?\d+\b/g,'.*').replace(/\.\* \.\*/g,'.*');

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
  
window.onload = consStart;
