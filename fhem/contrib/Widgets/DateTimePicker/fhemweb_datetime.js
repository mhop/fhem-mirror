// Wrapper for the jquery datetimepicker widget.
// http://xdsoft.net/jqplugins/datetimepicker/
FW_widgets['datetime'] = { createFn:FW_datetimeCreate, };

function
FW_datetimeCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if(!vArr.length || vArr[0] != "datetime" || (params && params.length))
    return undefined;
   
  var newEl = $("<div style='display:inline-block'>").get(0);
  $(newEl).append('<input type="text" id="datetimepicker'+devName+'" onfocus="blur();" >');
  var inp = $(newEl).find("input");
  if(elName)
    $(inp).attr("name", elName);
  if(currVal != undefined)
    $(inp).val(currVal);

  function addBlur() { if(cmd) $(inp).blur(function() { cmd($(inp).val()) }); };
  newEl.setValueFn = function(arg){ $(inp).val(arg) };
  addBlur();
 
  var options = {
      lang:'de',
      i18n:{
        de:{
          months:[
          "Januar","Februar","März","April",
          "Mai","Juni","Juli","August",
          "September","Oktober","November","Dezember",
          ],
         dayOfWeek:[
          "So.", "Mo", "Di", "Mi", 
          "Do", "Fr", "Sa.",
         ]
        }
      },
       theme:"dark",
       format:"d.m.Y H:i",
       onClose: function(current_time,$input){
                    console.log("set data");
                    $('#datetimepicker'+devName).blur();
                ;}
      };

  for(var i1=0; i1<vArr.length; i1++) {
    var kv = vArr[i1].split(":");
    var value;
    if(kv[1] == "false")
    {
        value = false;
    }
    else if(kv[1] == "true")
    {
        value = true;
    }
    else
    {
        var number = parseInt(kv[1], 10);
        log(number);
        if(isNaN(number))
        {
            value = kv[1];
            log("other value "+kv[1]);
        }
        else
        {
            value = number;
            log("set number");
        }
    }
    if(kv[1])
    {
        log("set to option: "+value);
        options[kv[0]] = value;
    }
  }

  var useInline = options["inline"] && options["inline"] == true;
  
  loadLink("pgm2/jquery.datetimepicker.css");
    
  if(useInline)
  {
    log("inline");
    
    options["onSelectDate"] = function(current_time,$input){console.log("set data");inp.blur();};
    options["onSelectTime"] = function(current_time,$input){console.log("set time");inp.blur();};
    
    loadScript("pgm2/jquery.datetimepicker.js",
    function() {
        inp.datetimepicker(options);
    });  
  }
  else
  {
    log("not inline");
    loadScript("pgm2/jquery.datetimepicker.js");
    
    $(newEl).click(function(){
      $('#datetimepicker'+devName).datetimepicker(options);   
  });
  }

  return newEl;
}
