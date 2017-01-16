var consConn;

var consFilter, oldFilter;
var consLastIndex = 0;
var withLog = 0;
var mustScroll = 1;

log("Console is opening");

function
consUpdate(evt)
{
  var errstr = "Connection lost, trying a reconnect every 5 seconds.";
  var new_content = "";

  if(typeof WebSocket == "function" && evt && evt.target instanceof WebSocket) {
    if(evt.type == 'close') {
      FW_errmsg(errstr, 4900);
      consConn.close();
      consConn = undefined;
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

  if(FW_pollConn) {
    if($("body").attr("longpoll") == "websocket") {
      FW_pollConn.onclose = undefined;
      FW_pollConn.close();
    } else {
      FW_pollConn.onreadystatechange = undefined;
      FW_pollConn.abort();
    }
    FW_pollConn = undefined;
  }

  var query = "?XHR=1"+
       "&inform=type=raw;withLog="+withLog+";filter="+consFilter+
       "&timestamp="+new Date().getTime();
  query = addcsrf(query);

  if($("body").attr("longpoll") == "websocket") {
    if(consConn) {
      consConn.close();
    }
    consConn = new WebSocket((location+query).replace(/^http/i, "ws"));
    consConn.onclose = 
    consConn.onerror = 
    consConn.onmessage = consUpdate;

  } else {
    if(consConn) {
      consConn.onreadystatechange = undefined;
      consConn.abort();
    }
    consConn = new XMLHttpRequest();
    consConn.open("GET", location.pathname+query, true);
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
        '<div>Filter:</div><br>'+
        '<div><input id="filtertext" value="'+consFilter+'"></div>'+
      '</div>');

    $('#evtfilterdlg').dialog({ modal:true,
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
}

window.onload = consStart;
