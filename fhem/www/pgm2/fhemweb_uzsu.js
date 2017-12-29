
FW_version["fhemweb_uzsu.js"] = "$Id$";

FW_widgets['uzsuToggle'] = {
  createFn:FW_uzsuToggleCreate,
};

FW_widgets['uzsuSelect'] = {
  createFn:FW_uzsuSelectCreate,
};

FW_widgets['uzsuSelectRadio'] = {
  createFn:FW_uzsuSelectRadioCreate,
};


FW_widgets['uzsuDropDown'] = {
  createFn:FW_uzsuDropDownCreate,
};

FW_widgets['uzsuTimerEntry'] = {
  createFn:FW_uzsuTimerEntryCreate,
};

FW_widgets['uzsuList'] = {
  createFn:FW_uzsuListCreate,
};

FW_widgets['uzsu'] = {
  createFn:FW_uzsuCreate,
};

function
FW_uzsuDropDownCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "uzsuDropDown")
    return undefined;

  //vArr[0] = 'time';
  //return FW_createTime(elName, devName, vArr, currVal, set, params, cmd);

  var newEl = $("<div style='display:inline-block;margin:2px 4px 2px 0px;'>").get(0);

  if( vArr[1] === undefined )
    vArr = ["select",
            "00:00","01:00","02:00","03:00","04:00","05:00","06:00","07:00","08:00","09:00",
            "10:00","11:00","12:00","13:00","14:00","15:00","16:00","17:00","18:00","19:00",
            "20:00","21:00","22:00","23:00"];
  else
    vArr[0] = 'select';
    
  $(newEl).append( FW_createSelect(elName, devName, vArr, currVal, set, params, cmd) );
  var select = $(newEl).find("select");
  select.selectmenu();
  select.selectmenu( "option", "width", "auto" );
  select.selectmenu( "option", "position", {collision: "flipfit"} );
  select.selectmenu( { change: function( event, data ) {
                       if( cmd )
                         cmd(data.item.value);
      }
    });

  newEl.getValueFn = function(arg){ return select.val(); };

  newEl.setValueFn = function(arg){
                                    select.val(arg);
                                    select.selectmenu("refresh");
                                  }

  //newEl.setValueFn(currVal);

  return newEl;
}

function
FW_uzsuSelectCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "uzsuSelect")
    return undefined;

  var newEl = $("<div style='display:inline-block;'>").get(0);
  $(newEl).addClass(vArr[0]);

  var hidden;
  if(elName)
    hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
  $(newEl).append(hidden);

  var clicked = function(arg) { var new_val=newEl.getValueFn(arg);
                                newEl.setValueFn( new_val );
                                if( cmd )
                                  cmd(new_val);
                              };

  var buttons = [];
  for( var i = 1; i < vArr.length; ++i ) {
    var button = $('<input type="checkbox">').uniqueId();
    var label = $('<label for="'+button.attr("id")+'">'+vArr[i]+'</label>');
    buttons.push(button);

    $(newEl).append(button);
    $(newEl).append(label);

    $(button).change(clicked);
  }

  $(newEl).buttonset();

  if( !currVal )
    currVal = ",";

  newEl.getValueFn = function(arg) { var new_val="";
                                  for( var i = 0; i < buttons.length; ++i ) {
                                    var button = buttons[i];
                                    if( $(button).prop("checked") ) {
                                      if( new_val ) new_val += ',';
                                      new_val += $(button).button( "option", "label")
                                    }
                                  }
                                 if( !new_val )  return ',';
                                 return new_val;
                               };

  newEl.setValueFn = function(arg){ if( !arg )  arg = ',';
                                    if( hidden )
                                      hidden.attr("value", arg);
                                    for( var i = 0; i < buttons.length; ++i ) {
                                      var button = buttons[i];
                                      button.prop("checked", arg.match(new RegExp('(^|,)'+vArr[i+1]+'($|,)') ) );
                                      button.button("refresh");
                                    }
                                  };

  newEl.setValueFn( currVal );

  return newEl;
}

function
FW_uzsuSelectRadioCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "uzsuSelectRadio")
    return undefined;

  var newEl = $("<div style='display:inline-block;'>").get(0);
  $(newEl).addClass(vArr[0]);

  var hidden;
  if(elName)
    hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
  $(newEl).append(hidden);

  var clicked = function(arg) { var new_val=newEl.getValueFn(arg);
                                newEl.setValueFn( new_val );
                                if( cmd )
                                  cmd(new_val);
                              };

  var buttons = [];
  for( var i = 1; i < vArr.length; ++i ) {
    var button = $('<input type="radio" name="radio">').uniqueId();
    var label = $('<label for="'+button.attr("id")+'">'+vArr[i]+'</label>');
    buttons.push(button);

    $(newEl).append(button);
    $(newEl).append(label);

    $(button).change(clicked);

    if( currVal )
      button.prop("checked", currVal == vArr[i] );
  }

  $(newEl).buttonset();

  if( !currVal )
    currVal = ",";

  newEl.getValueFn = function(arg) { var new_val="";
                                  for( var i = 0; i < buttons.length; ++i ) {
                                    var button = buttons[i];
                                    if( $(button).prop("checked") ) {
                                      if( new_val ) new_val += ',';
                                      new_val += $(button).button( "option", "label")
                                    }
                                  }
                                 if( !new_val )  return ',';
                                 return new_val;
                               };

  newEl.setValueFn = function(arg){ if( !arg )  arg = ',';
                                    if( hidden )
                                      hidden.attr("value", arg);
                                    for( var i = 0; i < buttons.length; ++i ) {
                                      var button = buttons[i];
                                      button.prop("checked", (arg == vArr[i+1]) );
                                      button.button("refresh");
                                    }
                                  };

  newEl.setValueFn( currVal );

  return newEl;
}

function
FW_uzsuToggleCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(vArr.length<3 || vArr[0] != "uzsuToggle")
    return undefined;

  var newEl = $("<div style='display:inline-block;'>").get(0);
  $(newEl).addClass(vArr[0]);

  var hidden;
  if(elName)
    hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
  $(newEl).append(hidden);

  var button = $('<input type="checkbox">').uniqueId();
  var label = $('<label for="'+button.attr("id")+'"></label>');

  $(newEl).append(button);
  $(newEl).append(label);

  button.button();

  $(newEl).change(function(arg) { var new_val = newEl.getValueFn();
                                  newEl.setValueFn( new_val );
                                  if( cmd )
                                    cmd(new_val);
                                } );

  newEl.getValueFn = function(arg){ return button.prop("checked")?vArr[2]:vArr[1]; };

  newEl.setValueFn = function(arg){ if( !arg )
                                      arg = vArr[1];
                                    if( hidden )
                                      hidden.attr("value", arg);
                                    button.button( "option", "label", arg);
                                    button.prop("checked", arg.match(new RegExp('(^|,)'+vArr[2]+'($|,)') ) );
                                    button.button("refresh");
                                  };

  newEl.setValueFn( currVal );

  return newEl;
}
function
FW_uzsuTimerEntryCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "uzsuTimerEntry")
    return undefined;

  if( !currVal )
    currVal = '';
  currVals = currVal.split('|');
  if( !currVals[2] );
    currVals[2] = "enabled";

  var newEl = $("<div style='display:inline-block;'>").get(0);
  $(newEl).addClass(vArr[0]);

  var hidden;
  if(elName)
    hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
  $(newEl).append(hidden);

  var changed = function(arg) { $(newEl).change();
                                if(hidden)
                                  hidden.attr("value", newEl.getValueFn());
                                if(cmd && newEl.getValueFn)
                                  cmd(newEl.getValueFn())};
  var wval;
  var wchanged = function(arg) { wval = arg; changed() };

  var days = FW_uzsuSelectCreate(undefined, devName+"Days", ["uzsuSelect","Mo","Di","Mi","Do","Fr","Sa","So"],
                                   currVals[0], undefined, params, changed);
  $(newEl).append(days); //days.activateFn();

  var time = FW_uzsuDropDownCreate(undefined, devName+"Time", ["uzsuDropDown"],
                                 currVals[1], undefined, params, changed);
  $(newEl).append(time); //time.activateFn();

  var widget;
  if( vArr[1] ) {
    var vArr = vArr;
    var params = vArr.slice(1).join(',').split(',');
    var wn = params[0];
    FW_callCreateFn(elName+'-'+wn, devName+'-'+wn, params,
                    currVals[3], undefined, undefined, wchanged,
                    function(wn, ne) {
      widget = ne;

      if( widget ) {
        if( widget.activateFn )
          widget.activateFn();

        wval = currVals[3];
        if( typeof wval == 'undefined' )
          wval = params[1];

        if( widget.setValueFn
            &&( typeof wval !== 'undefined' )  )
          widget.setValueFn(wval);

        $(widget).css('margin','0 8px 0 4px');
        $(newEl).append(widget)
      } else {
        var button = $('<button>aktion</button>');
        button.button();
        button.val(wn);
        button.css('margin','0 8px 0 4px');
        button.css('height','29px');
        button.button("disable");
        $(newEl).append(button);
      }
    });
  }

  var enabled = FW_uzsuToggleCreate(undefined, devName+"Enabled", ["uzsuToggle","disabled","enabled"],
                                    currVals[2], undefined, params, changed);
  $(newEl).append(enabled); //enabled.activateFn();

  newEl.getValueFn = function() { var ret = "";
                                  ret += days.getValueFn();
                                  ret += '|';
                                  ret += time.getValueFn();
                                  ret += '|';
                                  ret += enabled.getValueFn();
                                  if( widget
                                      && ( typeof wval !== 'undefined' ) ) {
                                    ret += '|';
                                    ret += wval;
                                    //ret += $(widget).val();
                                  }
                                  return ret;
                                }

  newEl.setValueFn = function(arg){ if( hidden )
                                      hidden.attr("value", arg);
                                    var args = arg.split('|');
                                    days.setValueFn(args[0]);
                                    time.setValueFn(args[1])
                                    enabled.setValueFn(args[2])
                                    wval = args[3];
                                    if( widget && widget.setValueFn
                                        && ( typeof wval !== 'undefined' )  ) {
                                      widget.setValueFn(wval);
                                    }
                                  };

  if( currVal )
    newEl.setValueFn( currVal );

  return newEl;
}
function
FW_uzsuListCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "uzsuList")
    return undefined;

  var newEl = $("<div style='display:inline-block;'>").get(0);
  $(newEl).addClass(vArr[0]);

  var button = $('<button>');
  button.addClass("back");
  button.button({ icons: { primary: "ui-icon-carat-1-w", }, text: false});
  button.css('margin','3px');
  button.css('height','18px');
  button.hover( function() { $(this).css('background', 'red') }, function() { $(this).css('background', '') });
  button.click(function( event ) { event.preventDefault();
                                  var arg = $(this).attr("parent");
                                  FW_cmd(FW_root+"?cmd=get "+devName+" children "+arg+"&XHR=1",children);
                                 });

  $(newEl).append(button);

  var list = $('<ul>');
  list.css('overflow','auto');
  list.css('height','250px');
  list.css('width','350px');
  list.css('margin','0px');
  list.css('padding','0px');
  list.css('list-style','none');
  $(newEl).append(list);

  var children = function(data) {
    $(list).empty();

    var items = data.split(',');
    button.attr("parent", items[0]);
    for( var i = 1; i < items.length; ++i ) {
      var item = $('<li>'+items[i]+'</li>')
      item.css('border', '1px solid #ccc');
      item.css('background-color', '#222');
      item.css('margin', '0.25em');
      item.css('padding', '0.5em');
      item.hover( function() { $(this).css('background', 'red') }, function() { $(this).css('background', '#222') });
      item.click(function( event ) { event.preventDefault();
                                     var arg = $(this).text();
                                     FW_cmd(FW_root+"?cmd=get "+devName+" children "+arg+"&XHR=1",children);
                                   });
      $(list).append(item);
    }
  };

  children(currVal);

  return newEl;
}
function
FW_uzsuCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "uzsu")
    return undefined;

  if( !currVal )
    currVal = ",";

  var newEl = $("<div style='display:inline-block;'>").get(0);

  var hidden;
  if(elName)
    hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
  $(newEl).append(hidden);

  var toJson = function() { var list = [];
                            var lines = $(newEl).find(".uzsuSelect");
                            for( var line = 0; line < lines.length; ++line ) {
                              var entry = {};
                              entry['value'] = 'on';
                              entry['time'] = '10:00';
                              entry['rrule'] = 'FREQ=WEEKLY;BYDAY='+lines[line].getValueFn();
                              entry['active'] = true;
                              list.push(entry);
                            }

                            var ret = {};
                            ret['list'] = list;
                            ret['active'] = true;

                            return ret;
                          }

  var changed = function(arg) { var new_val = newEl.getValueFn();
                                    //new_val = JSON.stringify(toJson());
                                if( hidden )
                                  hidden.attr("value", new_val);
                                if( cmd )
                                  cmd(new_val);
                              };

  var addLine = function(arg,currVal) {
    vArr[0] = 'uzsuTimerEntry';
    var entry = FW_uzsuTimerEntryCreate(undefined, devName+"UZSU", vArr,
                                        currVal, undefined, params, changed);
    var button = $('<button>');
    button.button({ icons: { primary: "ui-icon-plus", }, text: false});
    button.css('margin','0 0 0 10px');
    button.css('height','29px');
    button.click(function( event ) { event.preventDefault();
                                     addLine($(button).parent().index()-(hidden?1:0));
                                     changed();
                                   });
    $(entry).append(button);

    var button = $('<button>');
    button.addClass("trash");
    button.button({ icons: { primary: "ui-icon-trash", }, text: false});
    button.css('margin','0 0 0 10px');
    button.css('height','18px');
    button.click(function( event ) { event.preventDefault();
                                     $(button).parent().remove();
                                     if( $(newEl).children().length == 1 )
                                       $(newEl).find(".trash").button("disable");
                                     changed();
                                   });

    button.hover( function() { $(this).css('background', 'red') }, function() { $(this).css('background', '') });

    $(entry).append(button);

    var lines = $(newEl).find(".uzsuTimerEntry");
    if( !lines.length )
      $(newEl).append(entry);
    else
      $(entry).insertAfter($(lines[arg]));

    if( lines.length == 0 )
      $(newEl).find(".trash").button("disable");
    else if( lines.length == 1 )
      $(newEl).find(".trash").button("enable");
  }

  addLine(-1);

  newEl.getValueFn = function() { var ret = "";
                                  var lines = $(newEl).find(".uzsuTimerEntry");
                                  for( var line = 0; line < lines.length; ++line ) {
                                    if(ret) ret += ' ';
                                    ret += lines[line].getValueFn();
                                  }
                                  return ret;
                                }

  newEl.setValueFn = function(arg){ if( hidden )
                                      hidden.attr("value", arg);
                                    var old_lines = $(newEl).find(".uzsuTimerEntry");
                                    var new_lines = arg.split(' ');
                                    for( var line = 0; line < new_lines.length; ++line ) {
                                      if( line < old_lines.length ) {
                                        old_lines[line].setValueFn(new_lines[line]);
                                      } else {
                                        addLine(line-1, new_lines[line]);
                                      }
                                    }
                                    for( var line = new_lines.length; line < old_lines.length; ++line ) {
                                      $(old_lines[line]).remove();
                                    }

                                    if( new_lines.length == 1 )
                                      $(newEl).find(".trash").button("disable");
                                  };

  newEl.setValueFn( currVal );

  return newEl;
}

/*
=pod

=begin html

  <li>uzsuToggle,state1,state2 - dispay a toggle button with two possible
      states. the first is the active state.</li>

  <li>uzsuSelect,val1,val2,... - display a button bar with a button per value
      from which multiple values can be selected. the result is comma
      separated.</li>

  <li>uzsuSelectRadio,val1,val2,... - display a button bar with a button per
      value from which only one value can be selected.</li>

  <li>uzsuDropDown,val1,val2,... - display a dropdown with all values.</li>

  <li>uzsuTimerEntry[,modifier2] - combine uzsuSelect, uzsuDropDown and
      uzsuToggle into a single line display to select a timer entry. an
      optional modifier can be given to select the switching value. see
      examples below.  the result is a comma separated list of days followed by
      a time, an enabled indicator and the switching value all separated by a|.
      eg: Mo,Di,Sa,So|00:00|enabled|19.5</li>

  <li>uzsu[,modifier2] - combine multiple uzsuTimerEntry widets to allow the
      setting of multiple switching times an optional modifier can be given to
      select the switching value. see examples below.  the result is a space
      separeted list of uzsuTimerEntry results. Examples:
      <ul>
        attr myToggle widgetOverride state:uzsuToggle,123,xyz<br>
        attr mySelect widgetOverride state:uzsuSelect,abc,123,456,xyz<br>
        attr myTemp widgetOverride state:uzsuDropDown,18,18.5,19,19.5,20,20.5,21,21.5,22,22.5,23<br>
        attr myTimerEntry widgetOverride state:uzsuTimerEntry<br>
        attr myTimer widgetOverride state:uzsu<br>
        <br>
        the following gives some examples of for the modifier2 parameter of uzsuTimerEntry and uzsu to
        combine the setting of a timer with another widget to select the switching value :
        <pre>
... widgetOverride state:uzsu,slider,0,5,100                                         -> a slider
... widgetOverride state:uzsu,uzsuToggle,off,on                                      -> a on/off button
... widgetOverride state:uzsu,uzsuDropDown,18,19,20,21,22,23                         -> a dropDownMenue
... widgetOverride state:uzsu,knob,min:18,max:24,step:0.5,linecap:round,fgColor:red  -> a knob widget
... widgetOverride state:uzsu,colorpicker                                            -> a colorpicker
... widgetOverride state:uzsu,colorpicker,CT,2700,50,5000                            -> a colortemperature selector
        </pre>
      </ul>
      </li>

=end html

=begin html_DE

  <li>uzsuToggle,zust1,zust2 - damit ist es m&ouml;glich mit einem
      Toggle-Button zwischen zwei Zust&auml;nden zu w&auml;hlen. Der Erste ist
      der aktive Zustand.</li>

  <li>uzsuSelect,val1,val2,... - damit ist es m&ouml;gliche in einer
      Buttonleiste meherere Werte auszuw&auml;hlen.  Das Ergebnis ist
      Komma-separiert.</li>

  <li>uzsuSelectRadio,val1,val2,... - damit ist es m&ouml;gliche in einer
      Buttonleiste einen aus meherere Werten auszuw&auml;hlen.</li>

  <li>uzsuDropDown,val1,val2,... - damit ist es m&ouml;gliche mit einem
      DropDown Men&uuml; einen der Werte auszuw&auml;hlen.</li>

  <li>uzsuTimerEntry[,modifier2] - damit werden je ein uzsuSelect,
      uzsuDropDown und uzsuToggle Widget kombiniert um einen Schaltzeitpunkt
      auszuw&auml;hlen. &Uuml;ber den optionalen modifier2 kann ein Widget zur
      Auswahl des Schaltwertes angegeben werden. Siehe Beispiele unten.  Das
      Ergebniss is eine komma-separiert Liste von Wochentagen gefolgt vom
      Zeitpunkt, eine Aktiv-Indikator und dem Schaltwert, jeweils durch |
      abetrennt.  Zum Beispiel: Mo,Di,Sa,So|00:00|enabled|19.5</li>

  <li>uzsu[,modifier2] - damit werden mehrere uzsuTimerEntry Widets kombiniert
      um eine beliebige Anzahl an Schaltzeiten einzugeben. &Uuml;ber den
      optionalen modifier2 kann ein Widget zur Auswahl des Schaltwertes
      angegeben werden. Siehe Beispiele unten.  Das Ergebiss ist eine durch
      leerzeichen getrennte Liste von uzsuTimerEntry Ergebnissen.<br>
      Beispiele:
      <ul>
        attr myToggle widgetOverride state:uzsuToggle,123,xyz<br>
        attr mySelect widgetOverride state:uzsuSelect,abc,123,456,xyz<br>
        attr myTemp widgetOverride
          state:uzsuDropDown,18,18.5,19,19.5,20,20.5,21,21.5,22,22.5,23<br>
        attr myTimerEntry widgetOverride state:uzsuTimerEntry<br>
        attr myTimer widgetOverride state:uzsu<br>
        <br>
        Im Folgenden wird die Verwendung des modifier2 parameters von
        uzsuTimerEntry und uzsu gezeigt um die Auswahl des Schaltzeitpunktes
        mit der Auswahl des Schaltwertes zu kombinieren:
        <pre>
      ... widgetOverride state:uzsu,slider,0,5,100                                         -> ein slider
      ... widgetOverride state:uzsu,uzsuToggle,off,on                                      -> ein on/off button
      ... widgetOverride state:uzsu,uzsuDropDown,18,19,20,21,22,23                         -> ein dropDownMenue
      ... widgetOverride state:uzsu,knob,min:18,max:24,step:0.5,linecap:round,fgColor:red  -> ein knob widget
      ... widgetOverride state:uzsu,colorpicker                                            -> ein colorpicker
      ... widgetOverride state:uzsu,colorpicker,CT,2700,50,5000                            -> ein colortemperature slider
        </pre>
      </ul></li>

=end html_DE

=cut
*/
