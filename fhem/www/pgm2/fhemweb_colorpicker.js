
//TODO: realtime picker
//
FW_widgets['colorpicker'] = {
  createFn:FW_colorpickerCreate,
};

function
FW_colorpickerCreate(elName, devName, vArr, currVal, set, params, cmd)
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

  if(!vArr.length || vArr[0] != "colorpicker")
    return undefined;


  var mode = "RGB";
  if( vArr.length >= 1 )
    mode = vArr[1]

  //console.log( "mode: "+mode );

  if( params && params.length ) {
    var color = params[0];
    if( mode == "CT" )
      color = colorpicker_ct2rgb(color);

    var newEl = $('<div informID="###" style="width:32px;height:19px;border:1px solid #fff;border-radius:8px;background-color:#'+color+'" >').get(0);
    $(newEl).click(function(arg) { cmd(params[0]) });
    return newEl;

  }

  if( mode == "CT" ) {
    var newEl = FW_createSlider(elName, devName, ["slider",vArr[2],vArr[3],vArr[4]], currVal, set, params, cmd);
    $(newEl).addClass("colorpicker_ct");
    return newEl;

  } else if( mode == "HUE" ) {
    var newEl = FW_createSlider(elName, devName, ["slider",vArr[2],vArr[3],vArr[4]], currVal, set, params, cmd);
    $(newEl).addClass("colorpicker_hue");
    return newEl;

  }

  if( currVal )
    currVal = currVal.toUpperCase();

  var newEl = $("<div style='display:inline-block'>").get(0);
  $(newEl).append('<input type="text" id="colorpicker.'+ devName +'-'+set +'" maxlength="6" size="6">');

  var inp = $(newEl).find("[type=text]");

  var myPicker = new jscolor.color(inp.get(0),
                                   {pickerMode:'RGB',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red'});
  inp.get(0).color = myPicker;

  if( currVal ) {
    if( currVal.length > 6 ) currVal = currVal.slice(0,6);
    myPicker.fromString(currVal);
  }

  if( elName )
    $(inp).attr("name", elName);

  if( cmd )
    $(newEl).change(function(arg) { cmd( myPicker.toString() ) });
  else
    $(newEl).change(function(arg) { $(inp).attr("value", myPicker.toString() ) });

  newEl.setValueFn = function(arg){ if( arg.length > 6 ) arg = arg.slice(0,6);
                                    myPicker.fromString(arg); };

  return newEl;
}

function
colorpicker_ct2rgb(ct)
{
  // calculation from http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code

  if( ct > 1000 ) // kelvin -> mired
    ct = 1000000/ct;

  // adjusted by 1000K
  var temp = (1000000/ct)/100 + 10;

  var r = 0;
  var g = 0;
  var b = 0;

  r = 255;
  if( temp > 66 )
    r = 329.698727446 * Math.pow((temp - 60), -0.1332047592);

  if( r < 0 )
    r = 0;
  else if( r > 255 )
    r = 255;

  if( temp <= 66 )
    g = 99.4708025861 * Math.log(temp) - 161.1195681661;
  else
    g = 288.1221695283 * Math.pow((temp - 60), -0.0755148492);

  if( g < 0 )
    g = 0;
  else if( g > 255 )
    g   = 255;

  b = 255;
  if( temp <= 19 )
    b = 0;
  if( temp < 66 )
    b = 138.5177312231 * Math.log(temp-10) - 305.0447927307;

  r = Math.round( r );
  g = Math.round( g );
  b = Math.round( b );

  if( b < 0 )
    b = 0;
  else if( b > 255 )
    b = 255;

  return colorpicker_rgb2hex(r,g,b);
}

function
colorpicker_rgb2hex(r,g,b) {
  if( g !== undefined )
    return Number(0x1000000 + r*0x10000 + g*0x100 + b).toString(16).substring(1);
  else
    return Number(0x1000000 + r[0]*0x10000 + r[1]*0x100 + r[2]).toString(16).substring(1);
}
