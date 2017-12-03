
FW_version["doif.js"] = "$Id$";

function doifUpdateCell(doifname,attrname,attrcont,content,style) {
    $("table[uitabid='DOIF-"+doifname+"']").find("div["+attrname+"='"+attrcont+"']").each(function() {
      if(this.setValueFn) {     // change widget value
        this.setValueFn(content.replace(/\n/g, '\u2424'));
      } else {
        $(this).html(content+"");
        if(style)
          $(this).attr("style",style);
      }
    });
}

/*function doifUpdateIconColor(doifname,doifid,fillcolor) {
    $("table[uitabid='DOIF-"+doifname+"']").find("svg."+doifid).each(function() {
        if(fillcolor.length>0) {
          var html = $(this).html().replace(/fill=\".*?\"/gi,'fill="'+fillcolor+'"')
                                   .replace(/fill:.*?[;\s]/gi,'fill:'+fillcolor+';');
          $(this).html(html);
        }
    });
}*/

function doifTablePopUp(hash,name,doif,table) {
  FW_cmd(FW_root+"?cmd={DOIF_RegisterEvalAll(\$defs{"+name+"},\""+name+"\",\""+table+"\")}&XHR=1", function(data){
    var uit = $("[uitabid='DOIF-"+doif+"']");
    if(uit.html() !== undefined){
      FW_okDialog(data,uit);
    } else {
      FW_okDialog(data);
    }
  });
}

$(window).ready(function(){
  var room = $("#content").attr("room");
  $("table[uitabid]").each(function() {
    var uitabid = $(this).attr("uitabid").replace(/DOIF-/, '');
    var nodl = $(this).attr("doifnodevline");
    var atfi = $(this).attr("doifattrfirst");
    var tabl = "uiTable", t = $(this).attr("class").match(/(uiTable|uiState)doif/);
    if (t && t[1])
      tabl = t[1];
      
    // console.log("[readyFn] room",room,"nodl",nodl,"atfi",atfi,"tabl",tabl);
    if(room === undefined && atfi !== undefined && atfi != "" && atfi != "0" ) {
      $('.makeTable.wide.internals').before($('.makeTable.wide.attributes'));
      $('.makeTable.wide.attributes').before($('[cmd="attr"]'));
      $("div>a:contains("+tabl+")").closest('td').attr('valign','top');
    }
    if(room !== undefined && nodl !== undefined && nodl != "") {
      var re1 = new RegExp(nodl);
      if (room !="all" && room.match(re1))
        $('#'+uitabid).closest('tr').css('display','none');
    }
    if($(this).attr("doifnostate") == 1) {
      $('#'+uitabid).remove();
    }
  });
});

