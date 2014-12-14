
function
FW_readingsGroupToggle(d) {
  var rg = document.getElementById( 'readingsGroup-'+d );
  if( rg ) {
    s=rg.style;
    s.display = s.display=='none' ? 'block' : 'none';

    var group = rg.getAttribute('groupId');
    if( group ) {
      var elArr = document.querySelectorAll( '[groupId='+group+']' );
      for( var k=0; k<elArr.length; k++ ){
        el = elArr[k];
        if( el != rg ) {
          el.style.display = 'none';
        }
      }
    }
  }
}

function
FW_readingsGroupShow(d,v) {
  var rg = document.getElementById( 'readingsGroup-'+d );
  if( rg ) {
    s=rg.style;
    if( s.display=='none' && v )
      FW_readingsGroupToggle(d);
    else if( s.display!='none' && !v )
      FW_readingsGroupToggle(d);
  }
}

function
FW_readingsGroupToggle2(d) {
  var rg = document.getElementById( 'readingsGroup-'+d );
  if( rg ) {
    s=rg.style;
    s.width = rg.scrollWidth+'px';
    var rows = rg.childNodes[0].childNodes;
    for(var r=0; r<rows.length; r++){
      var row = rows[r];
      var pm = row.querySelectorAll('[id=plusminus]');
      if( pm.length ) {
        for(var i=0; i<pm.length; i++){
          pm[i].innerHTML = pm[i].innerHTML == '+'? '-' : '+';
        }
      } else {
        row.style.display = row.style.display=='none' ? '' : 'none';
      }
    }

    var group = rg.getAttribute('groupId');
    if( group ) {
      var elArr = document.querySelectorAll('[groupId='+group+']');
      for(var k=0; k<elArr.length; k++){
        el = elArr[k];
        s=el.style;
        s.width = rg.scrollWidth+'px';
        if( el != rg ) {
          var rows = el.childNodes[0].childNodes;
          for(var r=0; r<rows.length; r++){
            var row = rows[r];
            var pm = row.querySelectorAll('[id=plusminus]');
            if( pm.length ) {
              for(var i=0; i<pm.length; i++){
                pm[i].innerHTML = '+';
              }
            } else {
              row.style.display = (r==1 ? '' : 'none');
            }
          }
        }
      }
    }
  }
}

function
FW_readingsGroupUpdateLine(d){
  var dd = d[0].split("-", 3);

  if(dd.length != 2)
    return;

  if( dd[1] != "visibility" )
    return

  if( d[1] == 'toggle' ) FW_readingsGroupToggle( dd[0] );
  if( d[1] == 'toggle2' ) FW_readingsGroupToggle2( dd[0] );
  if( d[1] == 'show' ) FW_readingsGroupShow( dd[0], 1 );
  if( d[1] == 'hide' ) FW_readingsGroupShow( dd[0], 0 );

  //console.log("xxx: "+d[1]);
}

FW_widgets['readingsGroup'] = {
  updateLine:FW_readingsGroupUpdateLine
};

