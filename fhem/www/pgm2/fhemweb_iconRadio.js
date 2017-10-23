
FW_version["fhemweb_iconRadio.js"] = "$Id$";

FW_widgets['iconRadio'] = {
  createFn:FW_iconRadioCreate,
};

/********* iconRadio *********/
function
FW_iconRadioCreate(elName, devName, vArr, currVal, set, params, cmd)
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

  if(!vArr.length || vArr[0] != "iconRadio")
    return undefined;
  var ipar = 2;

  if( vArr[1].match(/^[A-F0-9]{6}$/))
    vArr[1] = "#"+vArr[1];
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
  for( var i = 2; i < (vArr.length); i+=ipar ) {
    vArr[i] = vArr[i].replace(/#/g," ");
    var button = $('<input type="radio" name="radio">').uniqueId();
    var label = $('<label for="'+button.attr("id")+'" name="'+vArr[i+1]+'" title="'+vArr[i]+'" >'+vArr[i]+'</label>');
    buttons.push(button);

    $(newEl).append(button);
    $(newEl).append(label);

    $(button).change(clicked);

    if( currVal )
      button.prop("checked", currVal == vArr[i] );
  }

  $(newEl).buttonset();
  $(newEl).find("label").css({"margin":"0","border":"0","border-radius":"4px","background":"inherit"});
  $(newEl).find("span").css({"padding":"0.0em 0.3em"});

  $(newEl).find("label").each(function(ind,val){
    $(val).addClass("iconRadio_widget");

    var ico = vArr[ind*ipar+3];
    FW_cmd(FW_root+"?cmd={FW_makeImage('"+ico+"')}&XHR=1",function(data){
       data = data.replace(/\n$/,'');
      $(newEl).find("label").each(function(ind,val){
        var re = new RegExp("\"\s?"+$(val).attr("name")+"(\s?|\")","i");
        if (!(data.match(re) === null) && ($(val).find("span").html().match(re) === null)) {
          $(val).find("span").addClass("iconRadio_widget").html(data);
          return false;
        }
      });

    });

  });
  if( !currVal )
    currVal = ",";

  newEl.getValueFn = function(arg) { var new_val="";
                                  for( var i = 0; i < buttons.length; ++i ) {
                                    var button = buttons[i];
                                    if( $(button).prop("checked") ) {
                                        button.next().css({"background-color":vArr[1]});
                                      if( new_val ) new_val += ',';
                                      new_val += $(button).button( "option", "label")
                                    }
                                  }
                                 if( !new_val )  return ',';
                                 return new_val;
                               };

  newEl.setValueFn = function(arg){ if( !arg ) arg = ',';
                                    if( hidden )
                                      hidden.attr("value", arg);
                                    for( var i = 0; i < buttons.length; ++i ) {
                                      var button = buttons[i];
                                      button.prop("checked", (arg == vArr[i*ipar+2]) );
                                      if (button.prop("checked")==true){
                                        button.next().css({"background-color":vArr[1]});
                                      } else {
                                        button.next().css({"background-color":"inherit"});
                                      }
                                      button.button("refresh");
                                    }
                                  };

  newEl.setValueFn( currVal );

  return newEl;
}

/*
=pod
=begin html

<br>
  <u>To the icon.* widgets listed below applies:</u><br>
  &lt;color&gt; is specified by a color name or a color number without leading <b>#</b> e.g. FFA500 or orange. Depending on the context <b>@</b> has to be escaped <b>\@</b>.<br>
  &lt;icon&gt; is the icon name.<br>
  Examples for import with raw definition, will be found in <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets">FHEMWEB-Widgets</a>
  <li>iconRadio,&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - displays Icons as radio button and returns value if pushed.
    &lt;value&gt; return value.<br>
    &lt;select color&gt; the background color of the selected icon.<br>
    The widget contains a CSS-class "iconRadio_widget".<br>
  </li>
  <li>
    iconButtons,&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - displays Icons as button bar and returns comma separated values of pushed buttons.
    &lt;value&gt; return value.<br>
    &lt;select color&gt; the background color of the selected icon.<br>
    The widget contains a CSS-class "iconButtons_widget".<br>
  </li>
  <li>iconLabel[,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
    - displays states by colorized values, labels and icons, if the current
    value fits to the reference value. A state is described by a parameter peer.
    The number of peers is arbitrarily. A peer consists of a &lt;reference
    value&gt; and an optional display value with an optional color value
    &lt;reference value&gt; is a number or a regular expression.<br>
    If &lt;icon&gt; is no icon name, the text will be displayed, otherwise
    the icon. If nothing is specified, the current value will be displayed.<br>
  </li>
  <li>iconSwitch,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
    - switches cyclic after actuation to the diplayed state and the actual
    value is set to the reference Value. A state is described by a 
    parameter peer. The number of peers is arbitrarily. A peer consists
    of a &lt;reference value&gt; and an optional display value with an
    optional color value [&lt;icon&gt;][@&lt;color&gt;].<br>
    &lt;reference value&gt; is a number or a string.<br>
    If &lt;icon&gt; is no icon name, the text will be displayed, otherwise
    the icon. If nothing is specified, the reference value will be displayed.<br>
  </li>
<br>
=end html
=begin html_DE

<br>
  <u>Für die folgenden icon.* Widgets gilt:</u><br>
  &lt;color&gt; kann ein Farbname oder eine Farbnummer ohne führende <b>#</b> sein, z.B. orange oder FFA500. Abhängig vom Kontext ist <b>@</b> zu escapen <b>\@</b>.<br>
  &lt;icon&gt; ist der Iconname.<br>
  Beispiele zum Import über Raw definition findet man im FHEM-Wiki unter <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets">FHEMWEB-Widgets</a>
  <li>iconRadio,&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - zeigt Icons als Radiobutton an und gibt Value bei Betätigung zurück.<br>
    &lt;value&gt; ist der Rückgabewert.<br>
    &lt;select color&gt; die Hintergrundfarbe des gewählten Icons.<br>
    Das Widget enthält eine CSS-Klasse "iconRadio_widget".<br>
  </li>
  <li>iconButtons,&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - zeigt Icons als Tastenleiste an und gibt durch Komma getrennte Werte der betätigten Tasten zurück.<br>
    &lt;value&gt; ist der Rückgabewert.<br>
    &lt;select color&gt; die Hintergrundfarbe des gewählten Icons.<br>
    Das Widget enthält eine CSS-Klasse "iconButton_widget".<br>
  </li>
  <li>iconLabel[,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
    - zeigt Zustände durch colorierte Werte, Beschriftungen und Icons an, wenn 
    der aktuelle Wert zum Vergleichswert passt. Ein Zustand wird durch 
    ein Parameterpaar beschrieben. Es können beliebig viele Paare angegeben
    werden. Ein Paar besteht aus einem Vergleichswert &lt;reference
    value&gt; und einem optionalen Anzeigewert mit optionaler mit
    Farbangabe [,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]].<br>
    &lt;reference value&gt; kann eine Zahl oder ein regulärer Ausdruck sein.<br>
    Wenn &lt;icon&gt; keinem Iconnamen entspricht, wird der Text angezeigt,
    sonst das Icon. Wird &lt;icon&gt; nicht angegeben, wird der aktuelle
    Wert angezeigt.<br>
  </li>
  <li>iconSwitch,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
    - schaltet zyklisch nach jeder Betätigung in den angezeigten
    Zustand, dabei wird der aktuelle Wert auf den Vergleichswert
    gesetzt. Ein Zustand wird durch ein Parameterpaar beschrieben.
    Es können beliebig viele Paare angegeben werden. Ein Paar 
    besteht aus einem Vergleichswert &lt;reference value&gt; und einem
    optionalen Anzeigewert mit optionaler mit Farbangabe [,&lt;reference
    value&gt;,[&lt;icon&gt;][@&lt;color&gt;]].<br>
    &lt;reference value&gt; kann eine Zahl oder eine Zeichenkette sein.<br>
    Wenn &lt;icon&gt; keinem Iconnamen entspricht, wird der Text
    angezeigt, sonst das Icon. Wird &lt;icon&gt; nicht angegeben,
    wird der Vergleichwert angezeigt.<br>
  </li>
<br>
=end html_DE
=cut
*/
