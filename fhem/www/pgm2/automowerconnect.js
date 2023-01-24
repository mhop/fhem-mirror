
FW_version["automowerconnect.js"] = "$Id$";

function AutomowerConnectLimits( ctx, pos, format ) {
//  log("array length: "+pos.length);
  if ( pos.length > 3 ) {
    // draw limits
    ctx.beginPath();

    if ( format == 0 ) {
      ctx.lineWidth=1;
      ctx.strokeStyle = '#ff8000';
      ctx.setLineDash([]);
    }
    if ( format == 1 ) {
      ctx.lineWidth=1;
      ctx.strokeStyle = '#33cc33';
      ctx.setLineDash([]);
    }

    ctx.moveTo(parseInt(pos[0]),parseInt(pos[1]));
    for (var i=2;i < pos.length - 1; i+=2 ) {
      ctx.lineTo(parseInt(pos[i]),parseInt(pos[i+1]));
    }
    ctx.lineTo(parseInt(pos[0]),parseInt(pos[1]));
    ctx.stroke();

    // limits connector
    if ( format == 1 ) {
      for (var i=0;i < pos.length - 1; i+=2 ) {
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.lineWidth=1;
        ctx.strokeStyle = '#33cc33';
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

function AutomowerConnectChargingStation( ctx, csx, csy, csrel ) {
  if (parseInt(csx) > 0 && parseInt(csy) > 0) {
    // draw chargingstation
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

    ctx.font = "16px Arial";
    ctx.fillStyle = "#f15422";
    ctx.textAlign = "center";
    if (csrel == 'right') ctx.fillText("CS", parseInt(csx)+13, parseInt(csy)+6);
    if (csrel == 'bottom') ctx.fillText("CS", parseInt(csx), parseInt(csy)+6+13);
    if (csrel == 'left') ctx.fillText("CS", parseInt(csx)-13, parseInt(csy)+6);
    if (csrel == 'top') ctx.fillText("CS", parseInt(csx), parseInt(csy)+6-13);
    if (csrel == 'center') ctx.fillText("CS", parseInt(csx), parseInt(csy)+6);

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

function AutomowerConnectChargingStationPath ( ctx, pos ) {
  // draw path
  ctx.beginPath();
  ctx.lineWidth=1;
  ctx.setLineDash([6, 2]);
  ctx.strokeStyle = '#999999';
  ctx.moveTo(parseInt(pos[0]),parseInt(pos[1]));
  for (var i=2;i<pos.length-1;i+=2){
    ctx.lineTo(parseInt(pos[i]),parseInt(pos[i+1]));
  }
  ctx.stroke();
}

//AutomowerConnectUpdateDetail (<devicename>, <type> <background-image path>, <imagesize x>, <imagesize y>, <relative positio of CS marker>,scalx <path array>, <property limits array>, <property limits array>)
function AutomowerConnectUpdateDetail (dev, type, imgsrc, picx, picy, csx, csy, csrel, scalx, pos, lixy, plixy, posc) {
//  log('pos.length '+pos.length+' lixy.length '+lixy.length+', scalx '+scalx );
//  log('loop: Start '+ type+' '+dev );
  if (FW_urlParams.detail == dev || 1) {
//  if (FW_urlParams.detail == dev) {
    const canvas = document.getElementById(type+'_'+dev+'_canvas');
    if (canvas) {
//        log('loop: canvas true '+ type+' '+dev );
        const ctx = canvas.getContext('2d');
	ctx.clearRect(0, 0, canvas.width, canvas.height);

        // draw limits
        if ( lixy.length > 0 ) AutomowerConnectLimits( ctx, lixy, 0 );
        if ( plixy.length > 0 ) AutomowerConnectLimits( ctx, plixy, 1 );
        // draw scale
        AutomowerConnectScale( ctx, picx, picy, scalx );
        // draw charging station path
        AutomowerConnectChargingStationPath ( ctx, posc );

      if ( pos.length > 4 ) {
        // draw path
        ctx.beginPath();
        ctx.lineWidth=1;
        ctx.setLineDash([6, 2]);
        ctx.strokeStyle = '#ff0000';
        ctx.moveTo(parseInt(pos[2]),parseInt(pos[3]));
        for (var i=4;i<pos.length-1;i+=2){
          ctx.lineTo(parseInt(pos[i]),parseInt(pos[i+1]));
        }
        ctx.stroke();

        // draw start
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.lineWidth=3;
        ctx.strokeStyle = 'white';
        ctx.fillStyle= 'black';
        ctx.arc(parseInt(pos[pos.length-2]), parseInt(pos[pos.length-1]), 4, 0, 2 * Math.PI, false);
        ctx.fill();
        ctx.stroke();

        // draw mower
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.lineWidth=3;
        ctx.strokeStyle = '#ffffff';
        ctx.fillStyle= '#3d3d3d';
        ctx.arc(parseInt(pos[0]), parseInt(pos[1]-13), 13, 0, 2 * Math.PI, false);
        ctx.fill();
        ctx.stroke();

        ctx.font = "20px Arial";
        ctx.fillStyle = "#f15422";
        ctx.textAlign = "center";
        ctx.fillText("M", parseInt(pos[0]), parseInt(pos[1]-7)); 
        // draw mark
        ctx.beginPath();
        ctx.setLineDash([]);
        ctx.lineWidth=1;
        ctx.strokeStyle = '#f15422';
        ctx.fillStyle= '#3d3d3d';
        ctx.arc(parseInt(pos[0]), parseInt(pos[1]), 2, 0, 2 * Math.PI, false);
        ctx.fill();
        ctx.stroke();
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
        AutomowerConnectChargingStation( ctx, csx, csy, csrel );
//      }
//      img.src = imgsrc;
    } else {
      setTimeout(()=>{
//        log('loop: canvas false '+ type+' '+dev );
        AutomowerConnectUpdateDetail (dev, type, imgsrc, picx, picy, csx, csy, csrel, scalx, pos, lixy, plixy);
      }, 100);
    }
  } else {
    setTimeout(()=>{
//      log('loop: detail false '+ type+' '+dev );
      AutomowerConnectUpdateDetail (dev, type, imgsrc, picx, picy, csx, csy, csrel, scalx, pos, lixy, plixy);
    }, 100);
  }
}
