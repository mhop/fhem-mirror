
FW_version["automowerconnect.js"] = "$Id$";

function AutomowerConnectShowError( ctx, div, dev, picx, picy, errdesc, erray ) {
//~ log( 'AutomowerConnectShowError: ' + erray[0]+'  '+erray[1]+'  '+erray[2]+'  '+erray[3]+'  '+erray[4]+'  '+erray[5]);
  // ERROR BANNER
  ctx.beginPath();
  ctx.fillStyle = div.getAttribute( 'data-errorBackgroundColor' );;
  ctx.font = div.getAttribute( 'data-errorFont' );
  var m = ctx.measureText( errdesc[ 1 ] + ', ' + dev + ': ' + errdesc[ 0 ] ).width > picy - 6;

  if ( m ) {

    ctx.fillRect( 0, 0, picx, 35);

  } else {

    ctx.fillRect( 0, 0, picx, 20);

  }

  ctx.fillStyle = div.getAttribute( 'data-errorFontColor' );
  ctx.textAlign = "left";

  if ( m ) {

  ctx.fillText( errdesc[ 1 ] + ', ' + dev + ':', 3, 15 );
  ctx.fillText( errdesc[ 0 ], 3, 30 );

  } else {

  ctx.fillText( errdesc[ 1 ] + ', ' + dev + ': ' + errdesc[ 0 ], 3, 15 );

  }

  ctx.stroke();

  if ( erray[ 0 ] && erray[ 1 ] && erray.length > 3) {

    AutomowerConnectIcon( ctx,  erray[ 4 ], erray[ 5 ], 'top', 'E' );

  }

  if ( erray.length > 8 ) {

    var pos = erray.slice(4);
    AutomowerConnectDrawPath ( ctx, div, pos, 'errorPath' );

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

function AutomowerConnectDrawPath ( ctx, div, pos, type ) {
  // draw path
  ctx.beginPath();
  ctx.strokeStyle = div.getAttribute( 'data-'+ type + 'LineColor' );
  ctx.lineWidth=div.getAttribute( 'data-'+ type + 'LineWidth' );
  ctx.setLineDash( div.getAttribute( 'data-'+ type + 'LineDash' ).split(",") );

  ctx.moveTo(parseInt(pos[0]),parseInt(pos[1]));
  for (var i=2;i<pos.length-1;i+=2){
    ctx.lineTo(parseInt(pos[i]),parseInt(pos[i+1]));
  }
  ctx.stroke();

}

//AutomowerConnectUpdateDetail (<devicename>, <type> <background-image path>, <imagesize x>, <imagesize y>, <relative positio of CS marker>,<scale x>, <error description>, <path array>, <area limits array>, <property limits array>, <error array>, <other positions>)
function AutomowerConnectUpdateDetail (dev, type, imgsrc, picx, picy, csx, csy, csrel, scalx, errdesc, pos, lixy, plixy, posc, erray, poso) {
//  log('pos.length '+pos.length+' lixy.length '+lixy.length+', scalx '+scalx );
//  log('loop: Start '+ type+' '+dev );
  if (FW_urlParams.detail == dev || 1) {
//  if (FW_urlParams.detail == dev) {
    const canvas = document.getElementById(type+'_'+dev+'_canvas');
    const div = document.getElementById(type+'_'+dev+'_div');
    if (canvas) {
//        log('loop: canvas true '+ type+' '+dev );
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // draw property limits
        if ( lixy.length > 0 ) AutomowerConnectLimits( ctx, div, lixy, 'area' );
        // draw area limits
        if ( plixy.length > 0 ) AutomowerConnectLimits( ctx, div, plixy, 'property' );
        // draw scale
        AutomowerConnectScale( ctx, div, picx, picy, scalx, 'scale' );
        // draw charging station path
        AutomowerConnectDrawPath ( ctx, div, posc, 'chargingStationPath' );
        // draw path for other activity
        if ( poso.length > 1 ) AutomowerConnectDrawPath ( ctx, div, poso, 'otherActivityPath' );

      if ( pos.length > 4 ) {
        // draw mowing path
        var mowpos = pos.slice(4);
        AutomowerConnectDrawPath ( ctx, div, mowpos, 'mowingPath' );

        // draw start
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.lineWidth=3;
        ctx.strokeStyle = 'white';
        ctx.fillStyle= 'black';
        ctx.arc(parseInt(pos[pos.length-2]), parseInt(pos[pos.length-1]), 4, 0, 2 * Math.PI, false);
        ctx.fill();
        ctx.stroke();

        // draw mower icon
        AutomowerConnectIcon( ctx, pos[0], pos[1], 'bottom', 'M' );

        //draw last line
        ctx.beginPath();
        ctx.lineWidth=1;
        ctx.setLineDash([6, 2]);
        ctx.moveTo(parseInt(pos[0]),parseInt(pos[1]));
        ctx.lineTo(parseInt(pos[2]),parseInt(pos[3]));
        ctx.strokeStyle = '#ff0000';
        ctx.stroke();

      }

        // draw charging station
        AutomowerConnectIcon( ctx, csx, csy, csrel, 'CS' );
        // draw error icon and path
        if ( errdesc[0] != '-' ) AutomowerConnectShowError( ctx, div, dev, picx, picy, errdesc, erray );
//      }
//      img.src = imgsrc;
    } else {
      setTimeout(()=>{
//        log('loop: canvas false '+ type+' '+dev );
        AutomowerConnectUpdateDetail (dev, type, imgsrc, picx, picy, csx, csy, csrel, scalx, errdesc, pos, lixy, plixy, posc, erray, poso);
      }, 100);
    }
  } else {
    setTimeout(()=>{
//      log('loop: detail false '+ type+' '+dev );
      AutomowerConnectUpdateDetail (dev, type, imgsrc, picx, picy, csx, csy, csrel, scalx, errdesc, pos, lixy, plixy, posc, erray, poso);
    }, 100);
  }
}
