
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

  var iconclass = "";
  if(vArr[1].match(/class.*?@/)) {
    var m = vArr[1].match(/class(.*?)@/);
    iconclass = m && m[1] ? m[1] : "";
    vArr[1] = vArr[1].replace(/class.*?@/,"");
  }

  var use4icon = false;
  if(vArr[1].match(/^use4icon@|^@/)) {
    use4icon = true;
    vArr[1] = vArr[1].replace(/^use4icon@|^@/,"");
  }

  if( vArr[1].match(/^[A-F0-9]{6}$/i))
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
  var istart = 2;
  for( var i = 2; i < (vArr.length-1); i+=ipar ) {
    if(!isNaN(parseFloat(vArr[i]))) {
      istart = i;
      break;
    }
  }
  var iend = vArr.length-ipar;
  for( var i = istart+ipar; i < (vArr.length-1); i+=ipar ) {
    if(isNaN(parseFloat(vArr[i]))) {
      iend = i-ipar;
      break;
    }
  }
  var ascd = true;
  if(!isNaN(parseFloat(vArr[istart+ipar])) && parseFloat(vArr[istart]) > parseFloat(vArr[istart+ipar]))
    ascd = false;

  for( var i = 2; i < (vArr.length); i+=ipar ) {

    var button = $('<input type="radio" name="radio">').uniqueId();
    var label = $('<label for="'+button.attr("id")+'" iconr=":'+((i-2)/ipar)+':" name="'+vArr[i+1]+'" title="'+vArr[i]+'" >'+vArr[i]+'</label>');
    buttons.push(button);

    $(newEl).append(button);
    $(newEl).append(label);

    $(button).change(clicked);

    // console.log("currVal: "+currVal+", vArr["+i+"]: "+vArr[i]+", is: "+ (currVal == vArr[i]));
    if( currVal ) {
      // console.log("FW_cmd, i:",i,"ascd:",ascd,"istart:",istart,"iend:",iend);
      // console.log("FW_cmd, parseFloat(currVal):", parseFloat(currVal),"i+ipar:",i+ipar,"parseFloat(vArr[i+ipar]):",parseFloat(vArr[i+ipar]),"i:",i,"parseFloat(vArr[i]):",parseFloat(vArr[i]));
      if(ascd && i>istart && !isNaN(parseFloat(vArr[i-ipar])) && !isNaN(parseFloat(currVal)) && !isNaN(parseFloat(vArr[i]))){
         button.prop("checked", parseFloat(currVal) > parseFloat(vArr[i-ipar]) && parseFloat(currVal) <= parseFloat(vArr[i]));
      } else if(!ascd && i<iend && !isNaN(parseFloat(vArr[i+ipar])) && !isNaN(parseFloat(currVal)) && !isNaN(parseFloat(vArr[i]))) {
         button.prop("checked", parseFloat(currVal) > parseFloat(vArr[i+ipar]) && parseFloat(currVal) <= parseFloat(vArr[i]));
      } else if(ascd && i==istart && !isNaN(parseFloat(currVal)) && !isNaN(parseFloat(vArr[i]))) {
        button.prop("checked", parseFloat(currVal) <= parseFloat(vArr[i]));
      } else if(!ascd && i==iend && !isNaN(parseFloat(currVal)) && !isNaN(parseFloat(vArr[i]))) {
        button.prop("checked", parseFloat(currVal) <= parseFloat(vArr[i]));
      } else {
        button.prop("checked", currVal == vArr[i]);
      }
    }
  }

  $(newEl).buttonset();
  $(newEl).find("label").css({"margin":"0","border":"0","border-radius":"4px","background":"inherit"});
  $(newEl).find("span").css({"padding":"0.0em 0.3em"})
                       .attr( "selectcolor",use4icon ? vArr[1] : "");
  $(newEl).find("input").each(function(ind,val){
    $(val).next().find("span").attr("ischecked",$(val).prop("checked"));
//    console.log("input checked("+ind+"): "+$(val).prop("checked"));
  });
  $(newEl).find("label").each(function(ind,val){
    $(val).addClass("iconRadio_widget")

    var ico = vArr[ind*ipar+3];
    var m = ico.match(/.*@(.*)/);
    var uscol = m && m[1] ? m[1] : "none";
    if( uscol.match(/^[A-F0-9]{6}$/i))
      uscol = "#"+uscol;
    if(uscol == 'none')
      ico += "@none";
    $(val).find("span").attr( "unselectcolor",uscol);

    FW_cmd(FW_root+"?cmd={FW_makeImage('"+ico+"','"+ico+"',':"+ind+": "+(iconclass.length > 0 ? iconclass :'')+"')}&XHR=1",function(data){
      data = data.replace(/\n$/,'');
      // console.log($(data).attr("class"));
      var m = $(data).attr("class").match(/(:\d+?:)/);
      var iconr = m && m[1] ? m[1] : "error";
      $(newEl).find("label[iconr='"+iconr+"']").each(function(ind,val){
        var span = $(val).find("span");
        var sc = $(span).attr("selectcolor");
        var usc = $(span).attr("unselectcolor") == "none" ? "" : $(span).attr("unselectcolor");
        if( usc.match(/^[A-F0-9]{6}$/i))
          usc = "#"+usc;
        var isc = $(span).attr("ischecked");
        // console.log("span usc_"+ind+": "+usc+", sc_"+ind+": "+sc);
        // console.log("Fw_cmd checked: "+ind+": "+isc);
        if(isc == "true") {
          if(sc.length > 0) {
            var re1 = new RegExp('fill="'+usc+'"','gi');
            var re2 = new RegExp('fill:\\s?"'+usc+'[;\\s]','gi');
            // console.log("FW_cmd re1u=",re1,", re2u=",re2);
            data = data.replace(re1,'fill="'+sc+'"')
                       .replace(re2,'fill:'+sc+';');
            // console.log("Fw_cmd sc_ind: "+ind+": "+sc+", isc:"+isc+"\n"+data);
          }
        } else {
          if(sc.length > 0) {
            var re1 = new RegExp('fill="'+sc+'"','gi');
            var re2 = new RegExp('fill:\\s?"'+sc+'[;\\s]','gi');
            // console.log("FW_cmd re1=",re1,", re2=",re2);
            data = data.replace(re1,'fill="'+usc+'"')
                       .replace(re2,'fill:'+usc+';');
            // console.log("Fw_cmd usc_ind: "+ind+": "+usc+", isc:"+isc+"\n"+data);
          }
        }
        $(span).addClass("iconRadio_widget").html(data);
      });

    });

  });
  if( !currVal )
    currVal = ",";

  newEl.getValueFn = function(arg) { var new_val="";
                                  for( var i = 0; i < buttons.length; ++i ) {
                                    var button = buttons[i];
                                    var span = button.next().find("span");
                                    var sc = $(span).attr("selectcolor");
                                    var usc = $(span).attr("unselectcolor");
                                    if( usc.match(/^[A-F0-9]{6}$/i))
                                      usc = "#"+usc;
                                    if( $(button).prop("checked") == true) {
                                      if(sc.length > 0) {
                                        
                                        var re1 = new RegExp('fill="'+usc+'"','gi');
                                        var re2 = new RegExp('fill:\\s?"'+usc+'[;\\s]','gi');
                                        // console.log("getFn re1u=",re1,", re2u=",re2);
                                        var html = $(span).html().replace(re1,'fill="'+sc+'"')
                                                                 .replace(re2,'fill:'+sc+';');
                                        // console.log("getFn sc_i:"+i+": "+sc+"\n"+html);
                                        $(span).html(html);
                                      } else {
                                        button.next().css({"background-color":vArr[1]});
                                      }
                                      // console.log("getFn new_val: ",new_val)
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
                                    var istart = 0;
                                    for( var i = 0; i < buttons.length; i++ ) {
                                      if(!isNaN(parseFloat(vArr[i*ipar+2]))) {
                                        istart = i;
                                        break;
                                      }
                                    }
                                    var iend = buttons.length-1;
                                    for( var i = istart+1; i < buttons.length; i++ ) {
                                      if(isNaN(parseFloat(vArr[i*ipar+2]))) {
                                        iend = i-1;
                                        break;
                                      }
                                    }
                                    var ascd = true;
                                    if(!isNaN(parseFloat(vArr[(istart+1)*ipar+2])) && parseFloat(vArr[istart*ipar+2]) > parseFloat(vArr[(istart+1)*ipar+2]))
                                      ascd = false;
                                    for( var i = 0; i < buttons.length; ++i ) {
                                      var button = buttons[i];
                                      var span = button.next().find("span");
                                      var sc = $(span).attr("selectcolor");
                                      var usc = $(span).attr("unselectcolor") == "none" ? "" : $(span).attr("unselectcolor");
                                      if( usc.match(/^[A-F0-9]{6}$/i))
                                        usc = "#"+usc;
                                      // console.log("setFn usc_"+i+": "+usc+": sc_"+i+": "+sc+", arg: "+arg);
                                      // console.log("setFn, i:",i,"ascd:",ascd,"istart:",istart,"iend:",iend);
                                      // console.log("setFn, parseFloat(arg):", parseFloat(arg),"(i+1)*ipar+2:",(i+1)*ipar+2,"parseFloat(vArr[(i+1)*ipar+2]):",parseFloat(vArr[(i+1)*ipar+2]),"i*ipar+2:",i*ipar+2,"parseFloat(vArr[i*ipar+2]):",parseFloat(vArr[i*ipar+2]));
                                      if(ascd && i>istart && !isNaN(parseFloat(vArr[(i-1)*ipar+2])) && !isNaN(parseFloat(arg)) && !isNaN(parseFloat(vArr[i*ipar+2]))){
                                        button.prop("checked", parseFloat(arg) > parseFloat(vArr[(i-1)*ipar+2]) && parseFloat(arg) <= parseFloat(vArr[i*ipar+2]));
                                      } else if(!ascd && i<iend && !isNaN(parseFloat(vArr[(i+1)*ipar+2])) && !isNaN(parseFloat(arg)) && !isNaN(parseFloat(vArr[i*ipar+2]))) {
                                        button.prop("checked", parseFloat(arg) > parseFloat(vArr[(i+1)*ipar+2]) && parseFloat(arg) <= parseFloat(vArr[i*ipar+2]));
                                      } else if(ascd && i==istart && !isNaN(parseFloat(arg)) && !isNaN(parseFloat(vArr[i*ipar+2]))) {
                                        button.prop("checked", parseFloat(arg) <= parseFloat(vArr[i*ipar+2]));
                                      } else if(!ascd && i==iend && !isNaN(parseFloat(arg)) && !isNaN(parseFloat(vArr[i*ipar+2]))) {
                                        button.prop("checked", parseFloat(arg) <= parseFloat(vArr[i*ipar+2]));
                                      } else {
                                        button.prop("checked", arg == vArr[i*ipar+2]);
                                      }
                                      
                                      if (button.prop("checked") == true){
                                        if(sc.length > 0) {
                                        var re1 = new RegExp('fill="'+usc+'"','gi');
                                        var re2 = new RegExp('fill:\\s?"'+usc+'[;\\s]','gi');
                                        // console.log("setFn re1u=",re1,", re2u=",re2);
                                        var html = $(span).html().replace(re1,'fill="'+sc+'"')
                                                                 .replace(re2,"fill:"+sc+";");
                                          $(span).html(html);
                                        } else {
                                          button.next().css({"background-color":vArr[1]});
                                        }
                                      } else {
                                        if(sc.length > 0) {
                                          var re1 = new RegExp('fill="'+sc+'"','gi');
                                          var re2 = new RegExp('fill:\\s?"'+sc+'[;\\s]','gi');
                                          // console.log("setFn re1=",re1,", re2=",re2);
                                          var html = $(span).html().replace(re1,'fill="'+usc+'"')
                                                                   .replace(re2,'fill:'+usc+';');
                                          $(span).html(html);
                                          
                                        } else {
                                          button.next().css({"background-color":"inherit"});
                                        }
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
  [class&lt;classname&gt;@] as prefix in front of the second parameter, assigns a css-class to the icons.<br>
  Examples for import with raw definition, will be found in <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets">FHEMWEB-Widgets</a>
  <li>iconRadio,[class&lt;classname&gt;@][use4icon@]&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - displays Icons as radio button and returns value if pushed.<br>
    &lt;value&gt; return or compare value. If a numerical sequence of &lt;value&gt; is specified, the current value will match the next higher &lt;value&gt. It is allowed to place non numerical &lt;value&gt in front of or after the sequence but not in between. The numerical sequence has to be ascendind or descending.<br>
    <u>Example:</u> <code>iconRadio,808080,<b>closed</b>,control_arrow_down,<b>10</b>,fts_shutter_10,<b>20</b>,fts_shutter_20,<b>30</b>,fts_shutter_30,<b>open</b>,control_arrow_up</code><br>
    &lt;select color&gt; the background color of the selected icon or the icon color if the prefix <i>use4icon@</i> is used.<br>
    The widget contains a CSS-class "iconRadio_widget".<br>
  </li>
  <li>
    iconButtons,[class&lt;classname&gt;@][use4icon@]&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - displays Icons as button bar and returns comma separated values of pushed buttons.<br>
    &lt;value&gt; return value.<br>
    &lt;select color&gt; the background color of the selected icon or the icon color if the prefix <i>use4icon@</i> is used.<br>
    The widget contains a CSS-class "iconButtons_widget".<br>
  </li>
  <li>iconLabel[,[class&lt;classname&gt;@]&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
    - displays states by colorized values, labels and icons, if the current
    value fits to the reference value. A state is described by a parameter peer.
    The number of peers is arbitrarily. A peer consists of a &lt;reference
    value&gt; and an optional display value with an optional color value
    &lt;reference value&gt; is a number or a regular expression.<br>
    If &lt;icon&gt; is no icon name, the text will be displayed, otherwise
    the icon. If nothing is specified, the current value will be displayed.<br>
  </li>
  <li>iconSwitch,[class&lt;classname&gt;@]&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
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
  [class&lt;classname&gt;@] als Prefix vor dem zweiten Parameter, weist den SVG-Icons eine CSS-Klasse zu.<br>
  Beispiele zum Import über Raw definition findet man im FHEM-Wiki unter <a href="https://wiki.fhem.de/wiki/FHEMWEB/Widgets">FHEMWEB-Widgets</a>
  <li>iconRadio,[class&lt;classname&gt;@][use4icon@]&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - zeigt Icons als Radiobutton an und gibt Value bei Betätigung zurück.<br>
    &lt;value&gt; ist der Rückgabe- u.Vergleichswert. Wenn eine numerische Folge von &lt;value&gt; angegeben wird, dann passt der laufende Wert zum nächsten höheren Vergleichswert. Vor und hinter der numerischen Folge dürfen nicht numerische Werte angegeben werden, dazwischen nicht. Die numerische Folge muss auf- oder absteigend sein.<br>
    <u>Beispiel:</u> <code>iconRadio,808080,<b>zu</b>,control_arrow_down,<b>10</b>,fts_shutter_10,<b>20</b>,fts_shutter_20,<b>30</b>,fts_shutter_30,<b>auf</b>,control_arrow_up</code><br>
    &lt;select color&gt; die Hintergrundfarbe des gewählten Icons oder die Farbe des Icons wenn der Prefix use4icon@ vorangestellt wird.<br>
    Das Widget enthält eine CSS-Klasse "iconRadio_widget".<br>
  </li>
  <li>iconButtons,[class&lt;classname&gt;@][use4icon@]&lt;select color&gt;,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;][,&lt;value&gt;,&lt;icon&gt;[@&lt;color&gt;]]...
    - zeigt Icons als Tastenleiste an und gibt durch Komma getrennte Werte der betätigten Tasten zurück.<br>
    &lt;value&gt; ist der Rückgabewert.<br>
    &lt;select color&gt; die Hintergrundfarbe des gewählten Icons oder die Farbe des Icons wenn der Prefix use4icon@ vorangestellt wird.<br>
    Das Widget enthält eine CSS-Klasse "iconButton_widget".<br>
  </li>
  <li>iconLabel[,[class&lt;classname&gt;@]&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
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
  <li>iconSwitch,[class&lt;classname&gt;@]&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;][,&lt;reference value&gt;,[&lt;icon&gt;][@&lt;color&gt;]]...
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
