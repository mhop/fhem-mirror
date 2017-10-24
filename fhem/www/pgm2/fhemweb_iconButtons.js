
FW_version["fhemweb_iconButtons.js"] = "$Id$";

FW_widgets['iconButtons'] = {
  createFn:FW_iconButtonsCreate,
};

/********* iconButtons *********/
function
FW_iconButtonsCreate(elName, devName, vArr, currVal, set, params, cmd)
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

  if(!vArr.length || vArr[0] != "iconButtons")
    return undefined;
  var ipar = 2;

  var use4icon = false;
  if(vArr[1].match(/^use4icon@/)) {
    use4icon = true;
    vArr[1] = vArr[1].replace(/^use4icon@/,"");
  }

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
    var button = $('<input type="checkbox">').uniqueId();
    var label = $('<label for="'+button.attr("id")+'" name="'+vArr[i+1]+'" title="'+vArr[i]+'" >'+vArr[i]+'</label>');
    buttons.push(button);

    $(newEl).append(button);
    $(newEl).append(label);

    $(button).change(clicked);

    if( currVal )
      button.prop("checked", currVal.match(new RegExp('(^|,)'+vArr[i]+'($|,)') ) );
  }

  $(newEl).buttonset();
  $(newEl).find("label").css({"margin":"0","border":"0","border-radius":"4px","background":"inherit"});
  $(newEl).find("span").css({"padding":"0.0em 0.3em"})
                       .attr( "selectcolor",use4icon ? vArr[1] : "");
  $(newEl).find("input").each(function(ind,val){
    $(val).next().find("span").attr("ischecked",$(val).prop("checked"));
  });
  $(newEl).find("Label").each(function(ind,val){
    $(val).addClass("iconButtons_widget")

    var ico = vArr[ind*ipar+3];
    var m = ico.match(/.*@(.*)/);
    var uscol = m[1];
    if( uscol.match(/^[A-F0-9]{6}$/))
      uscol = "#"+uscol;
    $(val).find("span").attr( "unselectcolor",uscol);

    FW_cmd(FW_root+"?cmd={FW_makeImage('"+ico+"')}&XHR=1",function(data){
       data = data.replace(/\n$/,'');
      $(newEl).find("label").each(function(ind,val){
        var span = $(val).find("span");
        var sc = $(span).attr("selectcolor");
        var usc = $(span).attr("unselectcolor");
        var isc = $(span).attr("ischecked");
        var re = new RegExp("\"\s?"+$(val).attr("name")+"(\s?|\")","i");
        if (!(data.match(re) === null) && ($(val).find("span").html().match(re) === null)) {
          if(isc == "true") {
            if(sc.length > 0) {
              data = data.replace(/fill=\".*?\"/,'fill="'+sc+'"')
                         .replace(/fill:.*?[;\s]/,'fill:'+sc+';');
            }
          } else {
            if(sc.length > 0) {
              data = data.replace(/fill=\".*?\"/,'fill="'+usc+'"')
                         .replace(/fill:.*?[;\s]/,'fill:'+usc+';');
            }
          }
          $(val).find("span").addClass("iconButtons_widget").html(data);
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
                                    var span = button.next().find("span");
                                    var sc = $(span).attr("selectcolor");
                                    if( $(button).prop("checked") ) {
                                      if(sc.length > 0) {
                                        var html = $(span).html().replace(/fill=\".*?\"/,"fill=\""+sc+"\"")
                                                                 .replace(/fill:.*?[;\s]/,"fill:"+sc+";");
                                        $(span).html(html);
                                      } else {
                                        button.next().css({"background-color":vArr[1]});
                                      }
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
                                      var span = button.next().find("span");
                                      var sc = $(span).attr("selectcolor");
                                      var usc = $(span).attr("unselectcolor");
                                      if( usc.match(/^[A-F0-9]{6}$/))
                                        usc = "#"+usc;
                                      button.prop("checked", arg.match(new RegExp('(^|,)'+vArr[i*ipar+2]+'($|,)') ) );
                                      if (button.prop("checked")==true){
                                        if(sc.length > 0) {
                                          var html = $(span).html().replace(/fill=\".*?\"/,"fill=\""+sc+"\"")
                                                                   .replace(/fill:.*?[;\s]/,"fill:"+sc+";");
                                          $(span).html(html);
                                        } else {
                                          button.next().css({"background-color":vArr[1]});
                                        }
                                      } else {
                                        if(sc.length > 0) {
                                          var html = $(span).html().replace(/fill=\".*?\"/,'fill="'+usc+'"')
                                                                   .replace(/fill:.*?[;\s]/,'fill:'+usc+';');
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

=end html

=begin html_DE

=end html_DE
=cut
*/
