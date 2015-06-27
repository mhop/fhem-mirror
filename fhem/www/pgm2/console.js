var consConn;

var isFF = (navigator.userAgent.toLowerCase().indexOf('firefox') > -1);
var consFilter, consTxt;

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

  $("#console")
    .html(consTxt+consConn.responseText)
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
       "&inform=type=raw;filter="+consFilter+
       "&timestamp="+new Date().getTime();
  query = addcsrf(query);
  consConn.open("GET", query, true);
  consConn.onreadystatechange = consUpdate;
  consConn.send(null);
}

function
consStart()
{
  var el = document.getElementById("console");

  consFilter = $("a#eventFilter").html();
  if(consFilter == undefined)
    consFilter = ".*";
  consTxt = el.innerHTML;
  setTimeout("consFill()", 1000);
  
  $("a#eventFilter").click(function(evt){  // Event-Filter Dialog
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
          consFilter = val ? val : ".*";
          $(this).dialog('close');
          $("a#eventFilter").html(consFilter);
          $("#console").html(consTxt);
          consFill();
        }}]
    });
  });
}

window.onload = consStart;
