var consConn;

var consFilter, oldFilter;
var consLastIndex = 0;
var withLog = 0;
log("Console is opening");

function
consUpdate()
{
  if(consConn.readyState == 4) {
    FW_errmsg("Connection lost, trying a reconnect every 5 seconds.");
    setTimeout(consFill, 5000);
    return; // some problem connecting
  }

  if(consConn.readyState != 3)
    return;
  var len = consConn.responseText.length;
  
  if (consLastIndex == len) // No new data
    return; 
 
  var new_content = consConn.responseText.substring(consLastIndex, len);
  consLastIndex = len;
  
  log("Console Rcvd: "+new_content);
  if(new_content.indexOf('<') != 0)
    new_content = new_content.replace(/ /g, "&nbsp;");
  $("#console")
    .append(new_content)
    .scrollTop($("#console")[0].scrollHeight);
}

function
consFill()
{
  FW_errmsg("");

  if(consConn) {
    consConn.onreadystatechange = undefined;
    consConn.abort();
  }
  consConn = new XMLHttpRequest();
  var query = document.location.pathname+"?XHR=1"+
       "&inform=type=raw;withLog="+withLog+";filter="+consFilter+
       "&timestamp="+new Date().getTime();
  query = addcsrf(query);
  consConn.open("GET", query, true);
  consConn.onreadystatechange = consUpdate;
  consConn.send(null);
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
}

window.onload = consStart;
