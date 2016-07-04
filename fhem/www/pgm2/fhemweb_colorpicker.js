
//TODO: realtime picker
//
FW_widgets['colorpicker'] = {
  createFn:FW_colorpickerCreate,
};

function
FW_colorpickerCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if(!vArr.length || vArr[0] != "colorpicker")
    return undefined;

  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  var mode = "RGB";
  if( vArr.length >= 1 )
    mode = vArr[1]

  if( mode == "HSV" ) {
    for( var i = 2; i <= 4; ++i ) {
      var d = parseInt(vArr[i]);

      if( !isNaN(d) )
        vArr[i] = d;
      else if( !vArr[i] )
        vArr[i] = undefined;
    }

    var hsv = [];
    function change(index, arg) {
      hsv[index] = arg;

      if( typeof vArr[2+index] === 'number' )
        hsv[index] = vArr[2+index]/100;

      var rgb = colorpicker_hsv2rgb(hsv[0],hsv[1],hsv[2]);
      if( hidden )
        hidden.attr("value", rgb);
      cmd( rgb );
    }

    if( currVal )
      hsv = colorpicker_rgb2hsv(currVal);
    else
      hsv = [0,1,1];
    var hue = FW_createSlider(undefined, devName, ["slider",0,1,359],
                              ""+parseInt(hsv[0]*359), undefined, params, function(arg) { change(0, arg/359) });
    $(hue).addClass("colorpicker_hue");

    var sat = FW_createSlider(undefined, devName, ["slider",0,1,100],
                              ""+parseInt(hsv[1]*100), undefined, params, function(arg) { change(1, arg/100) });
    $(sat).addClass("colorpicker_sat");

    var bri = FW_createSlider(undefined, devName, ["slider",0,1,100],
                              ""+parseInt(hsv[2]*100), undefined, params, function(arg) { change(2, arg/100) });
    $(bri).addClass("colorpicker_bri");


    var newEl = $('<div class="colorpicker">').get(0);
    var hidden;
    if(elName)
      hidden = $('<input type="hidden" name="'+elName+'" value="'+currVal+'">');
    $(newEl).append(hidden);

    var first = true;
    if(vArr[2] === undefined) {
      $(newEl).append(hue);
      first = false;
    } else {
      hue.style.display='none';
    }

    if(vArr[3] === undefined) {
      if( !first ) $(newEl).append("<br>");
      $(newEl).append(sat);
      first = false;
    } else {
      sat.style.display='none';
    }

    if(vArr[4] === undefined) {
      if( !first ) $(newEl).append("<br>");
      $(newEl).append(bri);
      first = false;
    } else {
      bri.style.display='none';
    }

    newEl.setValueFn = function(arg){
     if( hidden )
       hidden.attr("value", arg);

      hsv = colorpicker_rgb2hsv(arg);
      for( var i = 0; i < 3; ++i ) {
        if( typeof vArr[2+i] === 'number' )
          hsv[i] = vArr[2+i]/100;
        }
      hue.setValueFn(""+parseInt(hsv[0]*359));
      sat.setValueFn(""+parseInt(hsv[1]*100));
      bri.setValueFn(""+parseInt(hsv[2]*100));

      var grad = 'background-image: -webkit-linear-gradient(left, #c1#, #c2# );'
                 +  'background-image: -moz-linear-gradient(left, #c1#, #c2# );'
                 +   'background-image: -ms-linear-gradient(left, #c1#, #c2# );'
                 +    'background-image: -o-linear-gradient(left, #c1#, #c2# );'
                 +       'background-image: linear-gradient(left, #c1#, #c2# );';
      function hsv2hsl(a,b,c){return[a,b*c/((a=(2-b)*c)<1?a:2-a),a/2]}

      var s = grad.replace(/#c1#/g, 'hsla(' + hsv[0]*359 + ', 100%, 100%, 1)')
                  .replace(/#c2#/g, 'hsla(' + hsv[0]*359 + ', 100%,  50%, 1)')

      var v = grad.replace(/#c1#/g, 'rgb(  0,  0  ,0)')
                  .replace(/#c2#/g, 'rgb(255,255,255)')

      var slider = $(sat).find('.slider').get(0);
      slider.setAttribute('style', s );

      slider = $(bri).find('.slider').get(0);
      slider.setAttribute('style', v );
    }

    if( currVal ) {
      newEl.setValueFn(currVal);
      $(document).ready(function(arg) { newEl.setValueFn(currVal) });
    }

    return newEl;
  }

  //console.log( "mode: "+mode );

  //preset ?
  if( params && params.length ) {
    var color = params[0];
    if( mode == "CT" )
      color = colorpicker_ct2rgb(color);

    var newEl = $('<div informID="###" style="width:32px;height:19px;border:1px solid #fff;border-radius:8px;background-color:#'+color+'" >').get(0);
    $(newEl).click(function(arg) { cmd(params[0]) });
    return newEl;

  }

  if( mode == "CT" ) {
    if( currVal )
      currVal = currVal.match(/[\d.\-]*/)[0];

   if( +currVal < +vArr[2]
       || +currVal > +vArr[4] )
     currVal = Math.round(1000000/currVal).toString();

    var newEl = FW_createSlider(elName, devName, ["slider",vArr[2],vArr[3],vArr[4]], currVal, undefined, params, cmd);

    old_set_fn = newEl.setValueFn;
    newEl.setValueFn = function(arg) {
      arg = arg.match(/[\d.\-]*/)[0];
      if( +arg < +vArr[2]
          || +arg > +vArr[4] )
        arg = Math.round(1000000/arg).toString();
      old_set_fn(arg);
    }

    if( vArr[4] < 1000 )
      $(newEl).addClass("colorpicker_ct_mired");
    else
      $(newEl).addClass("colorpicker_ct");
    return newEl;

  } else if( mode == "HUE" ) {
    var newEl = FW_createSlider(elName, devName, ["slider",vArr[2],vArr[3],vArr[4]], currVal, undefined, params, cmd);
    $(newEl).addClass("colorpicker_hue");
    return newEl;

  }

  if( currVal )
    currVal = currVal.toUpperCase();

  var newEl = $("<div style='display:inline-block'>").get(0);
  $(newEl).append('<input type="text" id="colorpicker.'+ devName +'-'+set +'" maxlength="6" size="6">');

  var inp = $(newEl).find("[type=text]");

  newEl.setValueFn = function(arg){ if( arg.length > 6 ) arg = arg.slice(0,6); $(inp).val(arg); }

  loadScript("jscolor/jscolor.js",
  function() {
    var myPicker = new jscolor.color(inp.get(0),
                                   {pickerMode:'RGB',pickerFaceColor:'transparent',pickerFace:3,pickerBorder:0,pickerInsetColor:'red'});
    inp.get(0).color = myPicker;

    if( elName )
      $(inp).attr("name", elName);

    if( cmd )
      $(newEl).change(function(arg) { cmd( myPicker.toString() ) });
    else
      $(newEl).change(function(arg) { $(inp).attr("value", myPicker.toString() ) });

    newEl.setValueFn = function(arg){ if( arg.length > 6 ) arg = arg.slice(0,6);
                                      myPicker.fromString(arg); };

    if( currVal )
      newEl.setValueFn(currVal);
  });

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

function
colorpicker_rgb2hsv(r,g,b) {
  if( r === undefined )
    return;

  if( g === undefined ) {
    var str = r;
    r = parseInt( str.substr(0,2), 16 );
    g = parseInt( str.substr(2,2), 16 );
    b = parseInt( str.substr(4,2), 16 );

    r /= 255;
    g /= 255;
    b /= 255;
  }

  var M = Math.max( r, g, b );
  var m = Math.min( r, g, b );
  var c = M - m;

  var h, s, v;
  if( c == 0 ) {
    h = 0;
  } else if( M == r ) {
    h = ( ( 360 + 60 * ( ( g - b ) / c ) ) % 360 ) / 360;
  } else if( M == g ) {
    h = ( 60 * ( ( b - r ) / c ) + 120 ) / 360;
  } else if( M == b ) {
    h = ( 60 * ( ( r - g ) / c ) + 240 ) / 360;
  }

  if( M == 0 ) {
    s = 0;
  } else {
    s = c / M;
  }

  v = M;

  return  [h,s,v];
}
function
colorpicker_hsv2rgb(h,s,v) {
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;

  if( s == 0 ) {
    r = v;
    g = v;
    b = v;

  } else {
    var i = Math.floor( h * 6.0 );
    var f = ( h * 6.0 ) - i;
    var p = v * ( 1.0 - s );
    var q = v * ( 1.0 - s * f );
    var t = v * ( 1.0 - s * ( 1.0 - f ) );
    i = i % 6;

    if( i == 0 ) {
      r = v;
      g = t;
      b = p;
    } else if( i == 1 ) {
      r = q;
      g = v;
      b = p;
    } else if( i == 2 ) {
      r = p;
      g = v;
      b = t;
    } else if( i == 3 ) {
      r = p;
      g = q;
      b = v;
    } else if( i == 4 ) {
      r = t;
      g = p;
      b = v;
    } else if( i == 5 ) {
      r = v;
      g = p;
      b = q;
    }
  }

  return colorpicker_rgb2hex( Math.round(r*255),Math.round(g*255),Math.round(b*255) );
}
