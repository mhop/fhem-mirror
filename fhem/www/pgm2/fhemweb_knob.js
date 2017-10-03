// Wrapper for the jquery knob widget.
FW_widgets['knob'] = { createFn:FW_knobCreate, };

function
FW_knobCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if(!vArr.length || vArr[0] != "knob" || (params && params.length))
    return undefined;

  var conf = {};
  for(var i1=0; i1<vArr.length; i1++) {
    var kv = vArr[i1].split(":");
    conf[kv[0]] = kv[1];
  }

  currVal = (currVal == undefined) ?
             conf.min : parseFloat(currVal.replace(/[^\d.\-]/g, ""));
  if(!conf.width) conf.width=conf.height=100;
  if(!conf.fgColor) conf.fgColor="#278727";

  var newEl = $("<div style='display:inline-block'>").get(0);
  $(newEl).append('<input type="text" id="knob.'+devName+'-'+set +'" >');
  var inp = $(newEl).find("input");
  if(elName)
    $(inp).attr("name", elName);
  for(c in conf)
    $(inp).attr("data-"+c, conf[c]);

  loadScript("pgm2/jquery.knob.min.js",
  function() {
    inp.knob({ 'release' : function(v){ if(cmd && !inp.block) cmd(v) } });
    newEl.setValueFn = function(arg){ inp.val(arg);
                      inp.block=true; inp.trigger('change'); inp.block=false; };
    newEl.setValueFn(currVal);
  });

  return newEl;
}

/*
=pod

=begin html

  <li>:knob,min:1,max:100,... - shows the jQuery knob widget. The parameters
      are a comma separated list of key:value pairs, where key does not have to
      contain the "data-" prefix. For details see the jQuery-knob
      definition.<br> Example:
        attr dimmer widgetOverride dim:knob,min:1,max:100,step:1,linecap:round
      </li>

=end html

=begin html_DE

  <li>:knob,min:1,max:100,... - zeigt das jQuery knob Widget.Die Parameter
      werden als eine Komma separierte Liste von Key:Value Paaren spezifiziert,
      wobei das data- Pr&auml;fix entf&auml;llt.F&uuml;r Details siehe die
      jQuery knob Dokumentation.<br> Beispiel:
        attr dimmer widgetOverride dim:knob,min:1,max:100,step:1,linecap:round
      </li>

=end html_DE

=cut
*/
