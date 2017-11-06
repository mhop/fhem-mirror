
FW_version["fhemweb_iconSwitch.js"] = "$Id$";

FW_widgets['iconSwitch'] = {
  createFn:FW_iconSwitchCreate,
};

/********* iconSwitch *********/
function
FW_iconSwitchCreate(elName, devName, vArr, currVal, set, params, cmd)
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

  if(vArr.length<1 || vArr[0] != "iconSwitch")
    return undefined;
  var newEl = $("<div style='display:inline-block;'>").get(0);

  var ipar = 2;

  var iconclass = "";
  if(vArr[1].match(/class.*?@/)) {
    var m = vArr[1].match(/class(.*?)@/);
    iconclass = m && m[1] ? m[1] : "";
    vArr[1] = vArr[1].replace(/class.*?@/,"");
  }

  for( var i = 1; i < (vArr.length); i+=ipar ) {
    vArr[i] = vArr[i].replace(/#/g," ");
  }
  var hidden;
  if(elName)
    hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
  $(newEl).append(hidden);

  var button = $('<input type="checkbox">').uniqueId();

  var label = $('<label for="'+button.attr("id")+'">');

  $(newEl).append(button);
  $(newEl).append(label);

  button.button();
  $(newEl).change(function(arg) { var new_val = newEl.getValueFn();
                                  newEl.setValueFn( new_val );
                                  if( cmd )
                                    cmd(new_val);
                                } );

  newEl.getValueFn = function(arg){ if( !currVal )
                                      currVal = vArr[1] ? vArr[1] : "???";
                                    var imax = vArr.length - 2;
                                    var istart = 1;
                                    var ilast = 0;
                                    for (var i=1;i < vArr.length-1;i+=ipar) {
                                      if (isNaN(parseFloat(vArr[i])) && currVal === vArr[i] || !isNaN(parseFloat(vArr[i])) && parseFloat(currVal) <= parseFloat(vArr[i])) {
                                        ilast = i;
                                        break;
                                      }
                                    }
                                    if(ilast > 0) {
                                      if(ilast + ipar > imax) {
                                        i = istart;
                                      } else {
                                        i+= ipar;
                                      }
                                      currVal = vArr[i];
                                      return vArr[i];
                                    } else {
                                      currVal = ilast > 0 ? vArr[ilast] : vArr[istart];
                                      return ilast > 0 ? vArr[ilast] : vArr[istart];
                                    }
                                  };

  newEl.setValueFn = function(arg){ if( !arg )
                                      arg = vArr[1] ? vArr[1] : "???";
                                    if( hidden )
                                      hidden.attr("value", arg);
                                    $(newEl).find("span").attr("style","padding:0.0em 0.3em;");
                                    $(newEl).find("label").attr("style","background:none; border:none; font-size: inherit;");
                                    var imax = vArr.length - 2, istart = 1, ilast = 0,ico, col;
                                    for (var i=1;i < vArr.length-1;i+=ipar) {
                                      if (isNaN(parseFloat(vArr[i])) && arg === vArr[i] || !isNaN(parseFloat(vArr[i])) && parseFloat(arg) <= parseFloat(vArr[i])) {
                                        ilast = i;
                                        break;
                                      }
                                    }
                                    if(ilast > 0) {
                                      if(ilast + ipar > imax) {
                                        i = istart;
                                      } else {
                                        i += ipar;
                                      }
                                      if (vArr[i+1] && vArr[i+1].indexOf("@") == 0) { //text only with color
                                          col = vArr[i+1].replace(/@/,'');
                                          if( col.match(/^[A-F0-9]{6}$/i))
                                            col = "#"+col;
                                          $(newEl).find("span").html(vArr[i]+"")
                                                               .attr("style","color: "+col+" !important; padding:0.0em 0.3em ")
                                                               .attr("title",arg);
                                          $(newEl).find("label").attr("style","border-style:solid; background-color:#f6f6f6; background-image:none; font-size: inherit;");
                                          } else if( vArr[i+1] && vArr[i+1].indexOf("@") == -1) { //text or image no color
                                          ico = vArr[i+1];
                                          FW_cmd(FW_root+"?cmd={FW_makeImage('"+ico+"','"+arg+"',"+(iconclass.length > 0 ? "'"+iconclass+"'" :'')+")}&XHR=1",function(data){
                                            data = data.replace(/\n$/,'');
                                            $(newEl).find("span").html(data+"")
                                                                 .attr("title",arg);
                                            if (data.indexOf("<svg") == -1 && data.indexOf("<img") == -1)
                                              $(newEl).find("label").attr("style","border-style:solid; background-color:#f6f6f6; background-image:none;font-size: inherit;");
                                          });
                                      } else if (vArr[i+1] && vArr[i+1].indexOf("@") > 0) { //text or image with color
                                          ico = vArr[i+1].split("@");
                                          if( ico[1] && ico[1].match(/^[A-F0-9]{6}$/i))
                                            ico[1] = "#"+ico[1];
                                          FW_cmd(FW_root+"?cmd={FW_makeImage('"+vArr[i+1]+"','"+arg+"',"+(iconclass.length > 0 ? "'"+iconclass+"'" :'')+")}&XHR=1",function(data){
                                            data = data.replace(/\n$/,'');
                                            $(newEl).find("span").html((vArr[i+1] == data ? ico[0] : data )+"")
                                                                 .attr("title",arg)
                                                                 .attr("style","color: "+ico[1]+" !important; padding:0.0em 0.3em");
                                            if (data.indexOf("<svg") == -1 && data.indexOf("<img") == -1)
                                              $(newEl).find("label").attr("style","border-style:solid; background-color:#f6f6f6; background-image:none;font-size: inherit;");
                                          });
                                      } else { // text only
                                            $(newEl).find("span").html(vArr[i])
                                                                 .attr("title", arg);
                                            $(newEl).find("label").attr("style","border-style:solid; background-color:#f6f6f6; background-image:none;font-size: inherit;");
                                      }
                                    }
                                    button.button("refresh");
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
