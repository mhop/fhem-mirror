
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