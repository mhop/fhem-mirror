/* $Id$ */

var cm_loaded = 0;
var cm_active = 0;
var cm_attr = {
    matchBrackets:       true,
    autoRefresh:         true,
    search:              true,
    comment:             true,
    autocomplete:        true,
    autocompleteAlways:  false,
    autoCloseBrackets:   true,
    indentUnit:          4,
    type:                "fhem",
    theme:               "blackboard",
    indentWithTabs:      true,
    autofocus:           true,
    lineNumbers:         true,
    jumpToLine:          false,
    jumpToLine_extraKey: false,
    smartIndent:         false,
    height:              false,
    extraKeys: {
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

function AddCodeMirror(e, cb) {
    if(e instanceof jQuery) {
	AddCodeMirror(e.get(0), cb);
	return;
    }

    if(e == undefined || e.editor) {
	return;
    }
    e.editor = true;

    if(cm_active && cm_loaded == cm_active)
        return cm_wait(e, cb);
        
    var userAttr = scriptAttribute("fhem_codemirror.js");
    for(var a in userAttr)
        cm_attr[a] = userAttr[a];

    cm_active++;
      loadLink("codemirror/codemirror.css");
      loadScript("codemirror/codemirror.js", function(){cm_loaded++;} );
        
    // load additional addons
    if (cm_attr.autoCloseBrackets) {
        cm_active++; loadScript("codemirror/closebrackets.js", function(){cm_loaded++;} );
    }
    if (cm_attr.matchBrackets) {
        cm_active++; loadScript("codemirror/matchbrackets.js", function(){cm_loaded++;} );
    }
    if (cm_attr.search) {
        cm_active++; loadScript("codemirror/search.js", function(){cm_loaded++;} );
        cm_active++; loadScript("codemirror/searchcursor.js", function(){cm_loaded++;} );
        cm_active++;
          loadLink("codemirror/dialog.css");
          loadScript("codemirror/dialog.js", function(){cm_loaded++;} );
    }
    if (cm_attr.comment) {
        cm_active++; loadScript("codemirror/comment.js", function(){cm_loaded++;} );
        cm_attr.extraKeys['Ctrl-Q'] = function(cm) {
            cm.toggleComment({ indent: false, lineComment: "#" });
        };
    }
    if (cm_attr.autocomplete) {
        cm_active++;
          loadLink("codemirror/show-hint.css");
          loadScript("codemirror/show-hint.js", function(){cm_loaded++;});
        cm_attr.extraKeys['Ctrl-Space'] = 'autocomplete';
    }
    if (cm_attr.autoRefresh) {
        cm_active++; loadScript("codemirror/autorefresh.js",  function(){cm_loaded++;} );
    }
    if (cm_attr.jumpToLine) {
        cm_active++; loadScript("codemirror/jump-to-line.js", function(){cm_loaded++;} );
        if (cm_attr.jumpToLine_extraKey) {
            cm_attr.extraKeys[cm_attr.jumpToLine_extraKey] = 'jumpToLine';
        }
    }
    if (cm_attr.keyMap) {
        cm_active++; loadScript("codemirror/"+cm_attr.keyMap+".js", function(){cm_loaded++;} );
    }
    
    // editor user preferences
    if (cm_attr.height) {
        if(cm_attr.height == true)
            cm_attr.height = "auto";
        if(isNaN(cm_attr.height)) {
            $("head").append('<style type="text/css">.CodeMirror {height:auto;}');
        } else {
            $("head").append('<style type="text/css">.CodeMirror {height:' + cm_attr.height + 'px;}');
        }
    }
    
    // get the type from hidden filename extension, load the type-file.js, theme.css and call cm_wait
    var ltype;
    $("input[name=save]").each(function() {
        ltype = $(this).attr("value");
        ltype = ltype.substr(ltype.lastIndexOf(".")+1);
        if(ltype=="css") cm_attr.type = "css";
        if(ltype=="svg") cm_attr.type = "xml";
    });
    
    loadLink("codemirror/"+cm_attr.theme+".css");
    $("head").append(
        '<style type="text/css">'+
            (ltype ? 
            '.CodeMirror {height: ' + (window.innerHeight - 150) + 'px;}':
            '.CodeMirror {width:  ' + (window.innerWidth  - 300) + 'px;}')+
        '</style>');
        
    cm_active++;
    loadScript("codemirror/"+cm_attr.type+".js", function(){
        cm_loaded++;
        cm_wait(e, cb);
    });
}

function cm_wait(cm_editor, callback, recursions) {
    if(cm_loaded != cm_active) {
        recursions = typeof recursions !== 'undefined' ? recursions : 0;
        if(recursions < 100) {
            recursions++;
            setTimeout(function(){ cm_wait(cm_editor, callback, recursions) }, 20);
        }
        return;
    }

    var cm = CodeMirror.fromTextArea(cm_editor, cm_attr);

    if (cm_attr.autocomplete && cm_attr.autocompleteAlways) {
        cm.on("keyup", function (cm, event) {
            if ( !cm.state.completionActive && String.fromCharCode(event.keyCode).match(/\w/) ) {
                CodeMirror.commands.autocomplete(cm, null, {completeSingle: false});
            }
        });
    }

    if(callback)
        callback(cm);
}
