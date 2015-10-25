var cm_loaded = 0;

$(document).ready(function(){
  var els = document.getElementsByTagName("textarea");
  if(els.length == 0)
    return;

  if($(els[0]).closest("div#edit").css("display")=="none") { // DEF special
    $("table.internals a").each(function(){
      var oc = $(this).attr("onclick");
      if(oc) {
        $(this).attr("onclick", oc+
        's=document.getElementById("edit").getElementsByTagName("textarea");'+
        'if(!s[0].editor) { s[0].editor=true; AddCodeMirror(s[0]);}');
      }
    });
  } else {
    AddCodeMirror(els[0]);
  }
});

function
AddCodeMirror(e, cb)
{
  if(cm_loaded == 9)
    return cm_wait(e, cb);
  loadLink("codemirror/codemirror.css");
  loadLink("codemirror/show-hint.css");
  loadLink("codemirror/dialog.css");
  loadScript("codemirror/codemirror.js",   function(){ cm_loaded++;} );
  loadScript("codemirror/closebrackets.js",function(){ cm_loaded++;} );
  loadScript("codemirror/matchbrackets.js",function(){ cm_loaded++;} );
  loadScript("codemirror/search.js",       function(){ cm_loaded++;} );
  loadScript("codemirror/searchcursor.js", function(){ cm_loaded++;} );
  loadScript("codemirror/dialog.js",       function(){ cm_loaded++;} );
  loadScript("codemirror/comment.js",      function(){ cm_loaded++;} );
  loadScript("codemirror/autorefresh.js",  function(){ cm_loaded++;} );
  loadScript("codemirror/show-hint.js",    function(){
    cm_loaded++;
    cm_wait(e, cb);
  });
}

function
cm_wait(cm_editor, callback)
{
  if(cm_loaded != 9) {
    setTimeout(cm_wait, 10);
    return;
  }

  var ltype,type="fhem";    // get the type from the hidden filename extension
  $("input[name=save]").each(function(){
    ltype = $(this).attr("value");
    ltype = ltype.substr(ltype.lastIndexOf(".")+1);
    if(ltype=="css") type = "css";
    if(ltype=="svg") type = "xml";
  });
  var attr = {
    indentUnit: 4,
    indentWithTabs: false,
    autoCloseBrackets: false,
    matchBrackets: true,
    autofocus: true,
    theme: "blackboard",
    lineNumbers: true,
    autoRefresh: true,
    extraKeys: {
        'Ctrl-Space': 'autocomplete',
        'Tab': function(cm) {
            if (cm.somethingSelected()) {
                var sel = cm.getSelection("\n");
                // Indent only if there are multiple lines selected, or if the selection spans a full line
                if (sel.length > 0 && (sel.indexOf("\n") > -1 || sel.length === cm.getLine(cm.getCursor().line).length)) {
                    cm.indentSelection("add");
                    return;
                }
            }
            cm.getOption("indentWithTabs") ? cm.execCommand("insertTab") : cm.execCommand("insertSoftTab");
        },
        'Shift-Tab': function(cm) {
            cm.indentSelection("subtract");
        },
        'Ctrl-Q': function(cm) {   // Needs comment.js
            cm.toggleComment({ indent: false, lineComment: "#" });
        },
        'Ctrl-Up': function(cm) {
            var info = cm.getScrollInfo();
            if (!cm.somethingSelected()) {
                var visibleBottomLine = cm.lineAtHeight(info.top + info.clientHeight, "local");
                if (cm.getCursor().line >= visibleBottomLine)
                    cm.execCommand("goLineUp");
            }
            cm.scrollTo(null, info.top - cm.defaultTextHeight());
        },
        'Ctrl-Down': function(cm) {
            var info = cm.getScrollInfo();
            if (!cm.somethingSelected()) {
                var visibleTopLine = cm.lineAtHeight(info.top, "local")+1;
                if (cm.getCursor().line <= visibleTopLine)
                    cm.execCommand("goLineDown");
            }
            cm.scrollTo(null, info.top + cm.defaultTextHeight());
        }
    }
  };
  var userAttr = scriptAttribute("fhem_codemirror.js");
  for(var a in userAttr)
    attr[a] = userAttr[a];

  loadLink("codemirror/"+attr.theme+".css");
  $("head").append(
    '<style type="text/css">'+
      (ltype ? 
      '.CodeMirror {height: ' + (window.innerHeight - 150) + 'px;}':
      '.CodeMirror {width:  ' + (window.innerWidth  - 300) + 'px;}')+
    '</style>');

  loadScript("codemirror/"+type+".js", function(){
    log("Calling CodeMirror");
    var cm = CodeMirror.fromTextArea(cm_editor, attr);
    if(callback)
      callback(cm);
  });
}
