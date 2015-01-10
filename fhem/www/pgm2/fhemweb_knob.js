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
    inp.knob({ 'release' : function(v){ if(cmd) cmd(v) } });
    newEl.setValueFn = function(arg){ inp.val(arg);
                                      inp.trigger('change'); };
    newEl.setValueFn(currVal);
  });

  return newEl;
}
