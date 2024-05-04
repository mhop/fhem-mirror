
if ( !(typeof FW_version === 'undefined') )
  FW_version["automowerconnect.js"] = "$Id: automowerconnect.js 28823a 2024-04-26 13:14:53Z Ellert $";
  
{  window.onload = ( ()=>{
    let room = document.querySelector("#content");
    room = room.getAttribute("room");
    if ( room ) {
      let invis = document.querySelectorAll( "div[name='fhem_amc_mower_schedule_buttons'], div.fhem_amc_hull_buttons " ).forEach( (item, index, invis) => { // do not display schedule and hull buttons
        item.style.display = "none";
      });
    }
    let invis = document.querySelectorAll( "div.amc_panel_div" ).forEach( (item, index, invis) => { // do not display panel
      let ivipan = item.getAttribute("data-amc_panel_inroom");
      item.style.display = ( room && !ivipan ? "none" : "" );
    });

  });
}

function AutomowerConnectShowError( ctx, div, dev, picx, picy, errdesc, erray ) {
  // ERROR BANNER
  ctx.beginPath();
  ctx.fillStyle = div.getAttribute( 'data-errorBackgroundColor' );
  ctx.font = div.getAttribute( 'data-errorFont' );
  var m = ctx.measureText( errdesc[ 1 ] + ', ' + dev + ': ' + errdesc[ 2 ] + ' - ' + errdesc[ 0 ] ).width > picx - 6;

  if ( m ) {

    ctx.fillRect( 0, 0, picx, 35);

  } else {

    ctx.fillRect( 0, 0, picx, 20);

  }

  ctx.fillStyle = div.getAttribute( 'data-errorFontColor' );
  ctx.textAlign = "left";

  if ( m ) {

  ctx.fillText( errdesc[ 1 ] + ', ' + dev + ':', 3, 15 );
  ctx.fillText( errdesc[ 2 ] + ' - ' + errdesc[ 0 ], 3, 30 );

  } else {

  ctx.fillText( errdesc[ 1 ] + ', ' + dev + ': ' + errdesc[ 2 ] + ' - ' + errdesc[ 0 ], 3, 15 );

  }

  ctx.stroke();
  //~ log('AutomowerConnectShowError: erray '+ erray[2]+', '+erray[3]+', '+erray[0]+', '+erray[1]  );

  if ( erray[ 0 ] && erray[ 1 ] && erray.length > 3) {

    AutomowerConnectIcon( ctx,  erray[ 0 ], erray[ 1 ], AutomowerConnectTor ( erray[2], erray[3], erray[0], erray[1] ), 'E' );

  }

}

function AutomowerConnectHull( ctx, div, pos, type ) {
//  log("array length: "+pos.length);
  if ( pos.length > 3 ) {
    // draw limits
    ctx.beginPath();

      ctx.lineWidth = div.getAttribute( 'data-'+ type + 'LineWidth' );
      ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'Color' );
      ctx.setLineDash( [] );

    for (var i=0;i < pos.length; i++ ) {
      ctx.lineTo( pos[i][0], pos[i][1]);
    }
    ctx.stroke();

    // hull connector
    if ( div.getAttribute( 'data-'+ type + 'Connector' ) ) {
      for ( var i = 0; i < pos.length; i++ ) {
        ctx.beginPath();
        ctx.setLineDash( [] );
        ctx.lineWidth = 1;
        ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'Color' );
        ctx.fillStyle= 'white';
        ctx.moveTo( pos[i][0], pos[i][1]);
        ctx.arc( pos[i][0], pos[i][1], 2, 0, 2 * Math.PI, false);
        ctx.fill();
        ctx.stroke();
      }
    }
  }
}

function AutomowerConnectLimits( ctx, div, pos, type ) {
//  log("array length: "+pos.length);
  if ( pos.length > 3 ) {
    // draw limits
    ctx.beginPath();

      ctx.lineWidth = div.getAttribute( 'data-'+ type + 'limitsLineWidth' );
      ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'limitsColor' );
      ctx.setLineDash( [] );
    //~ if ( type == 'property' ) {
      //~ ctx.lineWidth=1;
      //~ ctx.strokeStyle = '#33cc33';
      //~ ctx.setLineDash( [] );
    //~ }

    ctx.moveTo(parseInt(pos[0]),parseInt(pos[1]));
    for (var i=2;i < pos.length - 1; i+=2 ) {
      ctx.lineTo(parseInt(pos[i]),parseInt(pos[i+1]));
    }
    ctx.lineTo(parseInt(pos[0]),parseInt(pos[1]));
    ctx.stroke();

    // limits connector
    if ( div.getAttribute( 'data-'+ type + 'limitsConnector' ) ) {
      for ( var i =0 ; i < pos.length - 1; i += 2 ) {
        ctx.beginPath();
        ctx.setLineDash( [] );
        ctx.lineWidth = 1;
        ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'limitsColor' );
        ctx.fillStyle= 'white';
        ctx.moveTo(parseInt(pos[i]),parseInt(pos[i+1]));
        ctx.arc(parseInt(pos[i]), parseInt(pos[i+1]), 2, 0, 2 * Math.PI, false);
        ctx.fill();
        ctx.stroke();
      }
    }
  }
}

function AutomowerConnectScale( ctx, picx, picy, scalx ) {
  // draw scale
  ctx.beginPath();
  ctx.lineWidth=2;
  ctx.setLineDash([]);
  const l = 10;
  const scam = picx / scalx;
  ctx.moveTo(picx-l*scam-30, picy-30);
  ctx.lineTo(picx-l*scam-30,picy-20);
  ctx.lineTo(picx-30,picy-20);
  ctx.moveTo(picx-30, picy-30);
  ctx.lineTo(picx-30,picy-20);
  ctx.moveTo(picx-(l/2)*scam-30, picy-26);
  ctx.lineTo(picx-(l/2)*scam-30, picy-20);
  ctx.strokeStyle = '#ff8000';
  ctx.stroke();
  ctx.beginPath();
  ctx.lineWidth = 1;
  for (var i=1;i<l;i++){
    ctx.moveTo(picx-i*scam-30, picy-24);
    ctx.lineTo(picx-i*scam-30, picy-20);
  }
  ctx.stroke();
  ctx.beginPath();
  ctx.font = "16px Arial";
  ctx.fillStyle = "#ff8000";
  ctx.textAlign = "center";
  ctx.fillText( l+" Meter", picx-(l/2)*scam-30, picy-37 );
  ctx.fill();
  ctx.stroke();
}

function AutomowerConnectTag( ctx, pos, colorat ) {

  for ( i = 0; i < pos.length ; i+=3 ){

    if ( pos[ i + 2 ] == 'K' ){
      ctx.beginPath();
      ctx.setLineDash( [] );
      ctx.lineWidth=1.5;
      ctx.strokeStyle = 'white';
      ctx.fillStyle= 'black';
      ctx.arc( parseInt( pos[ i ] ), parseInt( pos[ i + 1 ] ), 2, 0, 2 * Math.PI, false );
      ctx.fill();
      ctx.stroke();
    }
    if ( pos[ i + 2 ] == 'KE' ){
      ctx.beginPath();
      ctx.setLineDash( [] );
      ctx.lineWidth=3;
      ctx.strokeStyle = 'white';
      ctx.fillStyle= 'black';
      ctx.arc( parseInt( pos[ i ] ), parseInt( pos[ i + 1 ] ), 4, 0, 2 * Math.PI, false );
      ctx.fill();
      ctx.stroke();
    }
    if ( pos[ i + 2 ] == 'KS' ){
      ctx.beginPath();
      ctx.setLineDash( [] );
      ctx.lineWidth=3;
      ctx.strokeStyle = 'red';
      ctx.fillStyle= 'black';
      ctx.arc( parseInt( pos[ i ] ), parseInt( pos[ i + 1 ] ), 4, 0, 2 * Math.PI, false );
      ctx.fill();
      ctx.stroke();
    }

  }

}
function AutomowerConnectIcon( ctx, csx, csy, csrel, type ) {
  if (parseInt(csx) > 0 && parseInt(csy) > 0) {
    // draw icon
    ctx.beginPath();
    ctx.setLineDash([]);
    ctx.lineWidth=3;
    ctx.strokeStyle = '#ffffff';
    ctx.fillStyle= '#3d3d3d';
    if (csrel == 'right') ctx.arc(parseInt(csx)+13, parseInt(csy), 13, 0, 2 * Math.PI, false);
    if (csrel == 'bottom') ctx.arc(parseInt(csx), parseInt(csy)+13, 13, 0, 2 * Math.PI, false);
    if (csrel == 'left') ctx.arc(parseInt(csx)-13, parseInt(csy), 13, 0, 2 * Math.PI, false);
    if (csrel == 'top') ctx.arc(parseInt(csx), parseInt(csy)-13, 13, 0, 2 * Math.PI, false);
    if (csrel == 'center') ctx.arc(parseInt(csx), parseInt(csy), 13, 0, 2 * Math.PI, false);
    ctx.fill();
    ctx.stroke();

    if(type == 'CS') ctx.font = "16px Arial";
    if(type == 'M' ) ctx.font = "20px Arial";
    if(type == 'E' ) ctx.font = "20px Arial";
    ctx.fillStyle = "#f15422";
    ctx.textAlign = "center";
    if (csrel == 'right') ctx.fillText(type, parseInt(csx)+13, parseInt(csy)+6);
    if (csrel == 'bottom') ctx.fillText(type, parseInt(csx), parseInt(csy)+6+13);
    if (csrel == 'left') ctx.fillText(type, parseInt(csx)-13, parseInt(csy)+6);
    if (csrel == 'top') ctx.fillText(type, parseInt(csx), parseInt(csy)+6-13);
    if (csrel == 'center') ctx.fillText(type, parseInt(csx), parseInt(csy)+6);

    // draw mark
    ctx.beginPath();
    ctx.setLineDash([]);
    ctx.lineWidth=1;
    ctx.strokeStyle = '#f15422';
    ctx.fillStyle= '#3d3d3d';
    ctx.arc( parseInt(csx), parseInt(csy), 2, 0, 2 * Math.PI, false);
    ctx.fill();
    ctx.stroke();
  }
}

function AutomowerConnectDrawPathColorRev ( ctx, div, pos, colorat ) {
  // draw path
  var type = colorat[ pos[ 2 ] ];
  ctx.beginPath();
  ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
  ctx.lineWidth=div.getAttribute( 'data-'+ type + 'LineWidth' );
  ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split(",") );
  ctx.moveTo( parseInt( pos[ 0 ] ), parseInt( pos[ 1 ] ) );
  var i = 0;

  for ( i = 3; i<pos.length; i+=3 ){

    ctx.lineTo( parseInt( pos[ i ] ),parseInt( pos[ i + 1 ] ) );

    if ( colorat[ pos[ i + 2 ] ] != type ){

      ctx.stroke();
      type = colorat[ pos[ i + 2 ] ];
      ctx.beginPath();
      ctx.moveTo( parseInt( pos[ i ] ), parseInt( pos[ i + 1 ] ) );
      ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
      ctx.lineWidth=div.getAttribute( 'data-'+ type + 'LineWidth' );
      ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split( "," ) );

    }
  }

  ctx.stroke();

}

function AutomowerConnectDrawPathColor ( ctx, div, pos, colorat ) {
  // draw path
  var type = colorat[ pos[ pos.length-1 ] ];
  ctx.beginPath();
  ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
  ctx.lineWidth=div.getAttribute( 'data-'+ type + 'LineWidth' );
  ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split(",") );
  ctx.moveTo( parseInt( pos[ pos.length-3 ] ), parseInt( pos[ pos.length-2 ] ) );
  var i = 0;

  for ( i = pos.length-3; i>-1; i-=3 ){

    ctx.lineTo( parseInt( pos[ i ] ),parseInt( pos[ i + 1 ] ) );

    if ( colorat[ pos[ i + 2 ] ] != type ){

      ctx.stroke();
      type = colorat[ pos[ i + 2 ] ];
      ctx.beginPath();
      ctx.moveTo( parseInt( pos[ i ] ), parseInt( pos[ i + 1 ] ) );
      ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
      ctx.lineWidth=div.getAttribute( 'data-'+ type + 'LineWidth' );
      ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split( "," ) );

    }
  }

  ctx.stroke();

}

function AutomowerConnectDrawDotColor ( ctx, div, pos, colorat ) {
  // draw dots
  var type = colorat[ pos[ pos.length-1 ] ];
  ctx.beginPath();
  ctx.fillStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
  var fillWidth = 4
  var fillWidth = div.getAttribute( 'data-'+ type + 'DotWidth' )
  //~ ctx.lineWidth=div.getAttribute( 'data-'+ type + 'LineWidth' );
  //~ ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split(",") );
  //~ ctx.moveTo( parseInt( pos[ pos.length-3 ] ), parseInt( pos[ pos.length-2 ] ) );
  var i = 0;

  for ( i = pos.length; i>-1; i-=3 ){

    ctx.fillRect( parseInt( pos[ i ] ),parseInt( pos[ i + 1 ] ), fillWidth, fillWidth );

    if ( colorat[ pos[ i + 2 ] ] != type ){

      ctx.stroke();
      type = colorat[ pos[ i + 2 ] ];
      //~ ctx.beginPath();
      ctx.fillRect( parseInt( pos[ i ] ), parseInt( pos[ i + 1 ] ), fillWidth, fillWidth );
      ctx.fillStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
      fillWidth=div.getAttribute( 'data-'+ type + 'DotWidth' );
      //~ ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split( "," ) );

    }
  }

  ctx.stroke();

}

function AutomowerConnectTor ( x0, y0, x1, y1 ) {
  var dy = y0-y1;
  var dx = x0-x1;
  var dyx = dx ? Math.abs( dy / dx ) : 999;
  var ret = '';
  // position of icon relative to path end point
  if ( dx >= 0 && dy >= 0 && Math.abs( dyx ) >= 1 ) ret = 'top';
  if ( dx >= 0 && dy >= 0 && Math.abs( dyx )  < 1 ) ret = 'left';
  if ( dx < 0  && dy >= 0 && Math.abs( dyx ) >= 1 ) ret = 'top';
  if ( dx < 0  && dy >= 0 && Math.abs( dyx )  < 1 ) ret = 'right';

  if ( dx >= 0 && dy <  0 && Math.abs( dyx ) >= 1 ) ret = 'bottom';
  if ( dx >= 0 && dy <  0 && Math.abs( dyx )  < 1 ) ret = 'left';
  if ( dx < 0  && dy <  0 && Math.abs( dyx ) >= 1 ) ret = 'bottom';
  if ( dx < 0  && dy <  0 && Math.abs( dyx )  < 1 ) ret = 'right';

  //~ log ('AUTOMOWERCONNECTTOR:');
  //~ log ('dx:  ' + dx);
  //~ log ('dy:  ' + dy);
  //~ log ('dyx: ' + dyx);
  //~ log ('ret: ' + ret);
  return ret;
}

function AutomowerConnectUpdateJson ( path ) {
  $.getJSON( path, function( data, textStatus ) {
    console.log( 'AutomowerConnectUpdateJson ( \''+path+'\' ): status '+textStatus );
    if ( textStatus == 'success') 
      AutomowerConnectUpdateDetail ( data.name, data.type, data.detailfnfirst, data.picx, data.picy, data.scalx, data.scaly, data.errdesc, data.posxy, data.poserrxy, data.hullxy );

  });

}

function AutomowerConnectUpdateJsonFtui ( path ) {
  $.getJSON( path, function( data, textStatus ) {
    console.log( 'AutomowerConnectUpdateJsonFtui ( \''+path+'\' ): status '+textStatus );
    if ( textStatus == 'success') {
      AutomowerConnectUpdateDetail ( data.name, data.type, 1, data.picx, data.picy, data.scalx, data.scaly, data.errdesc, data.posxy, data.poserrxy, data.hullxy );
      let invis = document.querySelectorAll( "div[name='fhem_amc_mower_schedule_buttons'], div.amc_panel_div, div.fhem_amc_hull_buttons" ).forEach((item, index, invis) => { // do not display buttons
        item.style.display = "none";
      });
    }
  });

}

function AutomowerConnectGetHull ( path ) {
  $.getJSON( path, function( data, textStatus ) {
    console.log( 'AutomowerConnectGetHull ( \''+path+'\' ): status '+textStatus );

    if ( textStatus == 'success') {
      // data.name, data.type, data.picx, data.picy, data.scalx, data.scaly, data.errdesc, data.posxy, data.poserrxy );
      const div = document.getElementById(data.type+'_'+data.name+'_div');
      const pos =data.posxy;

      if ( div && div.getAttribute( 'data-hullCalculate' ) && typeof hull === "function" ){
        const wypts = [];

        for ( let i = 0; i < pos.length; i+=3 ){

          if ( pos[i+2] == "M") wypts.push( [ pos[i], pos[i+1] ] );

        }

        if ( wypts.length > 50 ) {

          const wyres = div.getAttribute( 'data-hullResolution' );
          const hullpts = hull( wypts, wyres );
          FW_cmd( FW_root+"?cmd=attr "+data.name+" mowingAreaHull "+JSON.stringify( hullpts )+"&XHR=1",function(data){setTimeout(()=>{window.location.reload()},500)} );

        }

      }

    }

  });

}

function AutomowerConnectSubtractHull ( path ) {
  $.getJSON( path, function( data, textStatus ) {
    console.log( 'AutomowerConnectGetHull ( \''+path+'\' ): status '+textStatus );

    if ( textStatus == 'success') {
      // data.name, data.type, data.picx, data.picy, data.scalx, data.scaly, data.errdesc, data.posxy, data.poserrxy );
      const div = document.getElementById(data.type+'_'+data.name+'_div');
      const pos =data.posxy;

      if ( div && div.getAttribute( 'data-hullSubtract' ) && typeof hull === "function" ){
        const wypts = [];
        const hsub = div.getAttribute( 'data-hullSubtract' );
        const wyres = div.getAttribute( 'data-hullResolution' );
        var hullpts = [];

        for ( let i = 0; i < pos.length; i+=3 ){

          if ( pos[i+2] == "M") wypts.push( [ pos[i], pos[i+1] ] );

        }

        for ( let i = 0; i < hsub; i++ ){

          if ( wypts.length > 50 ) {

            hullpts = hull( wypts, wyres );
            
            for ( let k = 0; k < hullpts.length; k++ ){

              for ( let m = 0; m < wypts.length; m++ ){

                if ( hullpts[k][0] == wypts[m][0] && hullpts[k][1] == wypts[m][1] ) {

                  wypts.splice( m, 1 );
                  break;
                  //~ m--;
                  //~ k++;

                }

              }

            }

          }

          hullpts = hull( wypts, wyres );

        }

       FW_cmd( FW_root+"?cmd=attr "+data.name+" mowingAreaHull "+JSON.stringify( hullpts )+"&XHR=1",function(data){setTimeout(()=>{window.location.reload()},500)} );

      }

    }

  });

}

function AutomowerConnectPanelCmd ( panelcmd ) {
  if ( typeof FW_cmd === "function" )
      FW_cmd( FW_root+"?cmd="+panelcmd+"&XHR=1" );
}

function AutomowerConnectHandleInput ( dev ) {
  let cal = JSON.parse( document.querySelector( '#amc_'+dev+'_schedule_div' ).getAttribute( 'data-amc_schedule' ) );
  let cali = document.querySelector('#amc_'+dev+'_index').value || cal.length;
  if ( cali > cal.length ) cali = cal.length;
  if ( cali > 13 ) cali = 13;

  for (let i=cal.length;i<=cali;i++) { cal.push( { "start":0, "duration":1439, "monday":false, "tuesday":false, "wednesday":false, "thursday":false, "friday":false, "saturday":false, "sunday":false } ) }
  //~ console.log('cali: '+cali+'   cal.length: '+cal.length);

  let elements = ["start", "duration"];
  elements.forEach((item, index) => {
    let val = document.getElementById('amc_'+dev+'_'+item).value;
    let hour = parseInt(val.slice(0,2)) * 60;
    let min = parseInt(val.slice(-2));

    if ( isNaN( hour ) && item == "start" ) hour = 0;
    if ( isNaN( min )  && item == "start" ) min = 0;
    if ( isNaN( hour ) && item == "duration" ) hour = 23;
    if ( isNaN( min )  && item == "duration" ) min = 59;

    cal[cali][item] = hour + min;

  });

  elements = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
  elements.forEach((item, index) => {
  cal[cali][item] = (document.getElementById('amc_'+dev+'_'+item).checked ? true : false);

  });

  let daysum = cal[cali].start + cal[cali].duration;
  if ( ! ( cal[cali].monday || cal[cali].tuesday || cal[cali].wednesday || cal[cali].thursday || cal[cali].friday || cal[cali].saturday || cal[cali].sunday ) ) {

    cal.splice( cali, 1 );

  } else {

    if ( daysum > 1439 ) {
      cal[cali].start = 1439 - cal[cali].duration;
    }

    elements = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
    elements.forEach((item, index) => {
      let cnt = 0;
      for (let i=0;i<cal.length;i++) {
        if ( cal[cali][item] && cal[i][item] ) cnt++;
      }
      if ( cnt > 2 ) cal[cali][item] = false;
    });

    let cnt = 0;
    elements.forEach((item, index) => {
      if ( cal[cali][item] ) cnt++;
    });
    if ( cnt == 0 ) cal.splice( cali, 1 );

    cal.forEach((item, index) => {
      if ( JSON.stringify( cal[cali] ) == JSON.stringify( item ) && cali != index ) {
        cal.splice( cali, 1 );
      }
    });

  }
  
  if ( cali > cal.length -1 ) cali = cal.length -1;
  if ( !cal[cali] ) {
    cal = [ { "start":0, "duration":1440, "monday":true, "tuesday":true, "wednesday":true, "thursday":true, "friday":true, "saturday":true, "sunday":true } ];
    cali = 0;
  }

  //~ console.log('index: '+cali+'   start: '+cal[cali].start+'   duration: '+cal[cali].duration+'   monday: '+cal[cali].monday+'   tuesday: '+cal[cali].tuesday+'   wednesday: '+cal[cali].wednesday+'   thursday: '+cal[cali].thursday+'   friday: '+cal[cali].friday+'   saturday: '+cal[cali].saturday+'   sunday: '+cal[cali].sunday);
  let shdl ='';
  shdl = "<div id='amc_"+dev+"_schedule_div' class='ui-dialog-content ui-widget-content' data-amc_schedule='"+JSON.stringify(cal)+"' style='width:auto; height:auto; ' title='Schedule editor'>";
  shdl += "<style>";
  shdl += ".amc_schedule_tabth{margin:auto; width:50%; text-align:left;}";
  shdl += "</style>";
  shdl += "<table id='amc_"+dev+"_schedule_table0' class='amc_schedule_table col_bg block wide' ><tbody>";
  shdl += "<tr class='even amc_schedule_tabth' ><th>Index</th><th>Start</th><th>Duration</th><th>Mon.</th><th>Tue.</th><th>Wed.</th><th>Thu.</th><th>Fri.</th><th>Sat.</th><th>Sun.</th><th></th></tr>";
  shdl += "<tr class='even'>";
  shdl += "<td><input id='amc_"+dev+"_index' type='number' value='"+cali+"' min='0' max='13' step='1' size='3' /></td>";
  shdl += "<td><input id='amc_"+dev+"_start' type='time' value='"+("0"+parseInt(cal[cali].start/60)).slice(-2)+":"+("0"+cal[cali].start%60).slice(-2)+"' /></td>";
  shdl += "<td><input id='amc_"+dev+"_duration' type='time' value='"+("0"+parseInt(cal[cali].duration/60)).slice(-2)+":"+("0"+cal[cali].duration%60).slice(-2)+"' /></td>";
  shdl += "<td><input id='amc_"+dev+"_monday' type='checkbox' "+(cal[cali].monday?"checked='checked'":"")+" /></td>";
  shdl += "<td><input id='amc_"+dev+"_tuesday' type='checkbox' "+(cal[cali].tuesday?"checked='checked'":"")+" /></td>";
  shdl += "<td><input id='amc_"+dev+"_wednesday' type='checkbox' "+(cal[cali].wednesday?"checked='checked'":"")+" /></td>";
  shdl += "<td><input id='amc_"+dev+"_thursday' type='checkbox' "+(cal[cali].thursday?"checked='checked'":"")+" /></td>";
  shdl += "<td><input id='amc_"+dev+"_friday' type='checkbox' "+(cal[cali].friday?"checked='checked'":"")+" /></td>";
  shdl += "<td><input id='amc_"+dev+"_saturday' type='checkbox' "+(cal[cali].saturday?"checked='checked'":"")+" /></td>";
  shdl += "<td><input id='amc_"+dev+"_sunday' type='checkbox' "+(cal[cali].sunday?"checked='checked'":"")+" /></td>";
  shdl += "<td><button id='amc_"+dev+"_schedule_button_plus' title='add: prepare a data set and click &plusmn;&#013;delete: unckeck each weekday and click &plusmn;&#013;reset: fill any time field with -- and click &plusmn;' onclick=' AutomowerConnectHandleInput ( \""+dev+"\" )' style='padding-bottom:4px; font-weight:bold; font-size:16pt; ' >&ensp;&plusmn;&ensp;</button></td>";
  shdl += "</tr><tr style='border-bottom:1px solid black'><td colspan='100%'></td></tr>";

  for (let i=0; i< cal.length; i++){
    shdl += "<tr class='"+( i % 2 ? 'even' : 'odd' )+"' >";
    shdl += "<td>&thinsp;"+i+"</td>";
    shdl += "<td>&thinsp;"+("0"+parseInt(cal[i].start/60)).slice(-2)+":"+("0"+cal[i].start%60).slice(-2)+"</td>";
    shdl += "<td>&thinsp;"+("0"+parseInt(cal[i].duration/60)).slice(-2)+":"+("0"+cal[i].duration%60).slice(-2)+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].monday?"&#x2611;":"&#x2610;")+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].tuesday?"&#x2611;":"&#x2610;")+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].wednesday?"&#x2611;":"&#x2610;")+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].thursday?"&#x2611;":"&#x2610;")+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].friday?"&#x2611;":"&#x2610;")+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].saturday?"&#x2611;":"&#x2610;")+"</td>";
    shdl += "<td>&thinsp;"+(cal[i].sunday?"&#x2611;":"&#x2610;")+"</td><td></td>";
    shdl += "</tr>";
    }

  shdl += "<tr>";
  let nrows = cal.length*11+2;
  shdl += "<td colspan='12' ><textarea style='font-size:10pt; ' readOnly wrap='off' cols='62' rows='"+(nrows > 35 ? 35 : nrows)+"'>"+JSON.stringify(cal,null,"  ")+"</textarea></td>";
  shdl += "</tr>";
  shdl += "</tbody></table>";
  shdl += "</div>";

  const newdiv = new DOMParser().parseFromString( shdl, "text/html" ).querySelector( '#amc_'+dev+'_schedule_div' );
  const olddiv = document.querySelector( '#amc_'+dev+'_schedule_div' );
  olddiv.parentNode.replaceChild( newdiv, olddiv );

}

function AutomowerConnectSchedule ( dev ) {

  let el = document.getElementById('amc_'+dev+'_schedule_div');
  if ( el ) el.remove();

  FW_cmd( FW_root+"?cmd={ FHEM::Devices::AMConnect::Common::getDefaultScheduleAsJSON( \""+dev+"\" ) }&XHR=1",( cal ) => {
    cal = JSON.parse( cal );
    if (cal.length == 0) cal = [ { "start":0, "duration":1440, "monday":true, "tuesday":true, "wednesday":true, "thursday":true, "friday":true, "saturday":true, "sunday":true } ];

    let cali = 0;
    let shdl = "<div id='amc_"+dev+"_schedule_div' data-amc_schedule='"+JSON.stringify(cal)+"' title='Schedule editor' class='col_fg'>";
    shdl += "<style>";
    shdl += ".amc_schedule_tabth{text-align:left;}";
    shdl += "</style>";
    shdl += "<table id='amc_"+dev+"_schedule_table0' class='amc_schedule_table col_bg block wide'><tbody>";
    shdl += "<tr class='even amc_schedule_tabth ' ><th>Index</th><th>Start</th><th>Duration</th><th>Mon.</th><th>Tue.</th><th>Wed.</th><th>Thu.</th><th>Fri.</th><th>Sat.</th><th>Sun.</td><th></th></tr>";
    shdl += "<tr class='even'>";
    shdl += "<td><input id='amc_"+dev+"_index' type='number' value='"+cali+"' min='0' max='13' step='1' size='3' /></td>";
    shdl += "<td><input id='amc_"+dev+"_start' type='time' value='"+("0"+parseInt(cal[cali].start/60)).slice(-2)+":"+("0"+cal[cali].start%60).slice(-2)+"' /></td>";
    shdl += "<td><input id='amc_"+dev+"_duration' type='time' value='"+("0"+parseInt(cal[cali].duration/60)).slice(-2)+":"+("0"+cal[cali].duration%60).slice(-2)+"' /></td>";
    shdl += "<td><input id='amc_"+dev+"_monday' type='checkbox' "+(cal[cali].monday?"checked='checked'":"")+" /></td>";
    shdl += "<td><input id='amc_"+dev+"_tuesday' type='checkbox' "+(cal[cali].tuesday?"checked='checked'":"")+" /></td>";
    shdl += "<td><input id='amc_"+dev+"_wednesday' type='checkbox' "+(cal[cali].wednesday?"checked='checked'":"")+" /></td>";
    shdl += "<td><input id='amc_"+dev+"_thursday' type='checkbox' "+(cal[cali].thursday?"checked='checked'":"")+" /></td>";
    shdl += "<td><input id='amc_"+dev+"_friday' type='checkbox' "+(cal[cali].friday?"checked='checked'":"")+" /></td>";
    shdl += "<td><input id='amc_"+dev+"_saturday' type='checkbox' "+(cal[cali].saturday?"checked='checked'":"")+" /></td>";
    shdl += "<td><input id='amc_"+dev+"_sunday' type='checkbox' "+(cal[cali].sunday?"checked='checked'":"")+" /></td>";
    shdl += "<td><button id='amc_"+dev+"_schedule_button_plus' title='add: prepare a data set and click &plusmn;&#013;delete: unckeck each weekday and click &plusmn;&#013;reset: fill any time field with -- and click &plusmn;' onclick='AutomowerConnectHandleInput ( \""+dev+"\" )' style='padding-bottom:4px; font-weight:bold; font-size:16pt; ' >&ensp;&plusmn;&ensp;</button></td>";
    shdl += "</tr><tr style='border-bottom:1px solid black'><td colspan='100%'></td></tr>";

    for (let i=0; i< cal.length; i++){
      shdl += "<tr class='"+( i % 2 ? 'even' : 'odd' )+"' >";
      shdl += "<td >&thinsp;"+i+"</td>";
      shdl += "<td>&thinsp;"+("0"+parseInt(cal[i].start/60)).slice(-2)+":"+("0"+cal[i].start%60).slice(-2)+"</td>";
      shdl += "<td>&thinsp;"+("0"+parseInt(cal[i].duration/60)).slice(-2)+":"+("0"+cal[i].duration%60).slice(-2)+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].monday?"&#x2611;":"&#x2610;")+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].tuesday?"&#x2611;":"&#x2610;")+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].wednesday?"&#x2611;":"&#x2610;")+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].thursday?"&#x2611;":"&#x2610;")+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].friday?"&#x2611;":"&#x2610;")+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].saturday?"&#x2611;":"&#x2610;")+"</td>";
      shdl += "<td>&thinsp;"+(cal[i].sunday?"&#x2611;":"&#x2610;")+"</td><td></td>";
      shdl += "</tr>";
    }
    shdl += "<tr>";
    let nrows = cal.length*11+2;
    shdl += "<td colspan='12' ><textarea style='font-size:10pt; ' readOnly wrap='off' cols='62' rows='"+(nrows > 35 ? 35 : nrows)+"'>"+JSON.stringify(cal,null,"  ")+"</textarea></td>";
    shdl += "</tr>";
    shdl += "</tbody></table>";
    shdl += "</div>";
    let schedule = new DOMParser().parseFromString( shdl, "text/html" ).querySelector( '#amc_'+dev+'_schedule_div' );
    document.querySelector('body').append( schedule );
    document.querySelector( "#amc_"+dev+"_schedule_button_plus" ).setAttribute( "onclick", "AutomowerConnectHandleInput( '"+dev+"' )" );

    $(schedule).dialog({
      dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true, 
      maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
      buttons: [{text:"Send To Attribute", click:function(){
        schedule = document.querySelector( '#amc_'+dev+'_schedule_div' );
        cal = JSON.parse( schedule.getAttribute( 'data-amc_schedule' ) );
        FW_cmd( FW_root+"?cmd=set "+dev+" sendJsonScheduleToAttribute "+JSON.stringify( cal )+"+&XHR=1" );
        
      }},{text:"Send To Mower", click:function(){
        schedule = document.querySelector( '#amc_'+dev+'_schedule_div' );
        cal = JSON.parse( schedule.getAttribute( 'data-amc_schedule' ) );
        FW_cmd( FW_root+"?cmd=set "+dev+" sendJsonScheduleToMower "+JSON.stringify( cal )+"&XHR=1" );
      }},{text:"Close", click:function(){
        $(this).dialog("close");
        document.querySelector( '#amc_'+dev+'_schedule_div' ).remove();
      }}]
    });
  });

}

//AutomowerConnectUpdateDetail (<devicename>, <type>, <detailfnfirst>, <imagesize x>, <imagesize y>, <scale x>, <scale y>, <error description>, <path array>, <error array>, <hull array>)
function AutomowerConnectUpdateDetail (dev, type, detailfnfirst, picx, picy, scalx, scaly, errdesc, pos, erray, hullxy) {
  const colorat = {
    "U" : "otherActivityPath",
    "N" : "errorPath",
    "S" : "otherActivityPath",
    "P" : "chargingStationPath",
    "C" : "chargingStationPath",
    "M" : "mowingPath",
    "K" : "mowingPath",
    "KE" : "mowingPath",
    "KS" : "mowingPath",
    "L" : "leavingPath",
    "G" : "goingHomePath"
  };
  const div = document.getElementById(type+'_'+dev+'_div');
  const canvas_0 = document.getElementById(type+'_'+dev+'_canvas_0');
  const canvas = document.getElementById(type+'_'+dev+'_canvas_1');

  if ( div && canvas && canvas_0 ) {

//    log('loop: div && canvas && canvas_0 true '+ type+' '+dev + ' detailfnfirst '+detailfnfirst);

    if ( detailfnfirst ) {

      const ctx0 = canvas_0.getContext( '2d' );
      ctx0.clearRect( 0, 0, canvas.width, canvas.height );
      const ctx = canvas.getContext( '2d' );

      // draw area limits
      const lixy = div.getAttribute( 'data-areaLimitsPath' ).split(",");
      if ( lixy.length > 0 ) AutomowerConnectLimits( ctx0, div, lixy, 'area' );
//        log('pos.length '+pos.length+' lixy.length '+lixy.length+', scalx '+scalx );

      // draw property limits
      const plixy = div.getAttribute( 'data-propertyLimitsPath' ).split( "," );
      if ( plixy.length > 0 ) AutomowerConnectLimits( ctx0, div, plixy, 'property' );

      // draw hull
      if ( div.getAttribute( 'data-hullCalculate' ) && typeof hull === "function" && hullxy.length == 0 ) {
        const pts = [];

        for ( let i = 0; i < pos.length; i+=3 ){

          if ( pos[i+2] == "M") pts.push( [ pos[i], pos[i+1] ] );

        }

        if ( pts.length > 50 ) {

          const res = div.getAttribute( 'data-hullResolution' );
          const hullpts = hull( pts, res );
          AutomowerConnectHull( ctx0, div, hullpts, 'hull' );

        }

      } else if ( hullxy.length > 0 ) {

        AutomowerConnectHull( ctx0, div, hullxy, 'hull' );

      }

      // draw scale
      AutomowerConnectScale( ctx0, picx, picy, scalx );

      // draw charging station
      var csx = div.getAttribute( 'data-cslon' );
      var csy = div.getAttribute( 'data-cslat' );
      var csrel = div.getAttribute( 'data-csimgpos' );
      AutomowerConnectIcon( ctx0, csx , csy, csrel, 'CS' );

    }
    
    const ctx = canvas.getContext( '2d' );
    ctx.clearRect( 0, 0, canvas.width, canvas.height );

    if ( pos.length > 3 ) {

      // draw mowing path color
      if ( div.getAttribute( 'data-mowingPathUseDots' ) ) {

        AutomowerConnectDrawDotColor ( ctx, div, pos, colorat );

      } else {

        AutomowerConnectDrawPathColor ( ctx, div, pos, colorat );

      }

      // draw collision tag
      if ( div.getAttribute( 'data-mowingPathShowCollisions' ) )
        AutomowerConnectTag( ctx, pos, colorat );

      // draw start
      if ( div.getAttribute( 'data-mowingPathDisplayStart' ) ) {
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.lineWidth=3;
        ctx.strokeStyle = 'white';
        ctx.fillStyle= 'black';
        ctx.arc( parseInt( pos[ pos.length-3 ] ), parseInt( pos[ pos.length-2 ] ), 4, 0, 2 * Math.PI, false );
        ctx.fill();
        ctx.stroke();
      }

      // draw mower icon
      AutomowerConnectIcon( ctx, pos[0], pos[1], AutomowerConnectTor ( pos[3], pos[4], pos[0], pos[1] ), 'M' );

    }

    // draw error icon and path
    if ( errdesc[0] != '-' ) AutomowerConnectShowError( ctx, div, dev, picx, picy, errdesc, erray );

  } else {
    setTimeout ( ()=>{
      console.log('AutomowerConnectUpdateDetail loop: div && canvas && canvas_0 false '+ type+' '+dev );
      AutomowerConnectUpdateDetail (dev, type, detailfnfirst, picx, picy, scalx, errdesc, pos, erray);
    }, 100);
  }
}
