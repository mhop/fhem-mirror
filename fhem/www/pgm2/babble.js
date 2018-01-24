//########################################################################################
// babble.js
// Version 1.06
// See 95_Babble for licensing
//########################################################################################
//# Prof. Dr. Peter A. Henning

//------------------------------------------------------------------------------------------------------
// Determine csrfToken
//------------------------------------------------------------------------------------------------------

var req = new XMLHttpRequest();
req.open('GET', document.location, false);
req.send(null);
var csrfToken = req.getResponseHeader('X-FHEM-csrfToken');
if( csrfToken == null ){
    csrfToken = "null";
}

//------------------------------------------------------------------------------------------------------
// encode Parameters for URL
//------------------------------------------------------------------------------------------------------

function encodeParm(oldval) {
    var newval;
    newval = oldval.replace(/\$/g, '\\%24');
    newval = newval.replace(/"/g, '%27');
    newval = newval.replace(/#/g, '%23');
    newval = newval.replace(/\+/g, '%2B');
    newval = newval.replace(/&/g, '%26');
    newval = newval.replace(/'/g, '%27');
    newval = newval.replace(/=/g, '%3D');
    newval = newval.replace(/\?/g, '%3F');
    newval = newval.replace(/\|/g, '%7C');
    newval = newval.replace(/\s/g, '%20');
    return newval;
};

//------------------------------------------------------------------------------------------------------
// Add and remove places and verbs
//------------------------------------------------------------------------------------------------------


function dialog1(message) {
    $('<div></div>').appendTo('body').html('<div><h6>' + message + '</h6></div>').dialog({
        modal: true, title: 'Babble', zIndex: 10000, autoOpen: true,
        width: 'auto', resizable: false,
        buttons: {
            OK: function () {
                location.reload();
                $(this).dialog("close");
            }
        },
        close: function (event, ui) {
            $(this).remove();
        }
    });
};

function babble_addplace(name) {
    var place = document.getElementById('b_newplace').value;
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '={Babble_ModPlace("' + name + '","' + encodeParm(place) + '",1)}');
    dialog1(tt_place + ' ' + place + ' ' + tt_added);
};

function babble_modplace(name, place, num) {
    var btn = document.getElementById('b_addplace');
    var divm = document.getElementById('b_chgplacediv');
    var fld = document.getElementById('b_newplace');
    fld.value = place;
    btn.value = tt_remove;
    btn.setAttribute("onclick", "babble_remplace('" + name + "','" + place + "'," + num + ")");
    var btnm = '<input type="button" id="b_canplace" onclick="babble_cancelplace(';
    btnm += "'" + name + "')";
    btnm += '" value="' + tt_cancel + '" style="height:20px; width:100px;"/>';
    divm.innerHTML = btnm;
};

function babble_remplace(name, place, num) {
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '={Babble_ModPlace("' + name + '",' + num + ',0)}');
    dialog1(tt_place + ' ' + place + ' ' + tt_removed);
};

function babble_cancelplace(name) {
    var btn = document.getElementById('b_addplace');
    var fld = document.getElementById('b_newplace');
    var divm = document.getElementById('b_chgplacediv');
    fld.value = "";
    btn.value = tt_add;
    btn.setAttribute("onclick", "babble_addplace('" + name + "')");
    divm.innerHTML = '';
}

function babble_addverb(name) {
    var verbi = document.getElementById('b_newverbi').value;
    var verbc = document.getElementById('b_newverbc').value;
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    1
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '={Babble_ModVerb("' + name + '","' + verbi + '","' + verbc + '",1)}');
    dialog1(tt_verb + ' ' + verbi + ' ' + tt_added);
};

function babble_modverb(name, verbi, verbc, num) {
    var btna = document.getElementById('b_addverb');
    var divm = document.getElementById('b_chgverbdiv');
    var fldi = document.getElementById('b_newverbi');
    var fldc = document.getElementById('b_newverbc');
    fldi.value = verbi;
    fldc.value = verbc;
    btna.value = tt_remove;
    btna.setAttribute("onclick", "babble_remverb('" + name + "','" + verbi + "'," + num + ")");
    var btnm = '<input type="button" id="b_chgverb" onclick="babble_chgverb(';
    btnm += "'" + name + "'," + num + ")";
    btnm += '" value="' + tt_modify + '" style="height:20px; width:100px;"/>';
    var btnm2 = '<input type="button" id="b_canverb" onclick="babble_cancelverb(';
    btnm2 += "'" + name + "')";
    btnm2 += '" value="' + tt_cancel + '" style="height:20px; width:100px;"/>';
    divm.innerHTML = btnm + btnm2;
};
function babble_remverb(name, verbi, num) {
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '={Babble_ModVerb("' + name + '",' + num + ',"",0)}');
    dialog1(tt_verb + ' ' + verbi + ' ' + tt_removed);
};

function babble_chgverb(name, num) {
    var verbi = document.getElementById('b_newverbi').value;
    var verbc = document.getElementById('b_newverbc').value;
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    1
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '={Babble_ModVerb("' + name + '",' + num + ',"' + verbc + '",2)}');
    dialog1(tt_verb + ' ' + verbi + ' ' + tt_modified);
};

function babble_cancelverb(name) {
    var btna = document.getElementById('b_addverb');
    var divm = document.getElementById('b_chgverbdiv');
    var fldi = document.getElementById('b_newverbi');
    var fldc = document.getElementById('b_newverbc');
    fldi.value = "";
    fldc.value = "";
    btna.value = tt_add;
    btna.setAttribute("onclick", "babble_addverb('" + name + "')");
    divm.innerHTML = '';
}

function babble_addrow(name, devx, rowx) {
    var table = document.getElementById("devstable");
    var rown = 2;
    for (i = 0; i < devx-1; i++) {
        rown += devrows[i];
    }
    var row = table.insertRow(rown)
    devrows[devx -1] = devrows[devx -1] + 1;
    var cell0 = row.insertCell(0);
    var cell1 = row.insertCell(1);
    var cell2 = row.insertCell(2);
    var cell3 = row.insertCell(3);
    var cell4 = row.insertCell(4);
    var cell5 = row.insertCell(5);
    var cell6 = row.insertCell(6);
    //copy from existing row if such a row exists
    cell2.innerHTML = newplace;
    cell3.innerHTML = newverbs;
    cell4.innerHTML = newtargs;
    cell5.innerHTML = newfield;
}

function babble_remrow(name, devx, rowx) {
    var table = document.getElementById("devstable");
    var url = document.location.protocol + "//" + document.location.host + "/fhem";
    var rown = rowx;
    var rowdev = 1;
    for (i = 0; i < devx -1; i++) {
        rowdev += devrows[i];   
    }
    devrows[devx -1] = devrows[devx -1] -1;
    var bdev = table.rows[rowdev].cells[1].textContent;
    var place = '';
    var verb = '';
    var target = '';
    var cmd = '';
    var selector;
    var selectedanswer;
    //
    selector = table.rows[rown].cells[2].getElementsByTagName("select")[0];
    if( selector ){
      selectedanswer = selector.selectedIndex;
      place = selector.getElementsByTagName("option")[selectedanswer].value;
    }else{
      place = "none";
    }
    //
    selector = table.rows[rown].cells[3].getElementsByTagName("select")[0];
    if( selector ){
      selectedanswer = selector.selectedIndex;
      verb = selector.getElementsByTagName("option")[selectedanswer].value;
    }else{
      verb = "none";
    }
    //
    selector = table.rows[rown].cells[4].getElementsByTagName("select")[0];
    if( selector ){
      selectedanswer = selector.selectedIndex;
      target = selector.getElementsByTagName("option")[selectedanswer].value;
    }else{
      target = "none";
    }
    //
    cmd = '{Babble_RemCmd("' + name + '","' + bdev + '","' + place + '","' + verb + '","' + target + '")}';
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '=' + cmd);
    table.deleteRow(rown);
}

function babble_savedevs(name) {
    var table = document.getElementById("devstable");
    var url = document.location.protocol + "//" + document.location.host + "/fhem";
    for (idev = 1; idev <= devrows.length; idev++) {
        var rowdev = 1;
        for (ip = 0; ip < idev -1; ip++) {
          rowdev += devrows[ip];   
        }
        var fhemdev = table.rows[rowdev].cells[0].textContent;
        var bdev = table.rows[rowdev].cells[1].textContent;
        var place = '';
        var verb = '';
        var target = '';
        var cmd = '';
        var selector;
        var selectedanswer;
        var field;
        // Help text
        field = table.rows[rowdev].cells[3].getElementsByTagName("input")[0];
        cmd = field.value;
        cmd = '{Babble_ModHlp("' + name + '","' + bdev + '","' + encodeParm(cmd) + '")}';
        FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '=' + cmd);
        // Command lines
        for (j = 1; j < devrows[idev -1]; j++) {
            //
            selector = table.rows[rowdev + j].cells[2].getElementsByTagName("select")[0];
            if( selector ){ 
              selectedanswer = selector.selectedIndex;
              place = selector.getElementsByTagName("option")[selectedanswer].value;
            }else{
              place = "none";
            }
            //
            selector = table.rows[rowdev + j].cells[3].getElementsByTagName("select")[0];
            if( selector ){
              selectedanswer = selector.selectedIndex;
              verb = selector.getElementsByTagName("option")[selectedanswer].value;
            }else{
              verb = "none";
            }  
            //
            selector = table.rows[rowdev + j].cells[4].getElementsByTagName("select")[0];
            if( selector ){
              selectedanswer = selector.selectedIndex;
              target = selector.getElementsByTagName("option")[selectedanswer].value;
            }else{
              target = "none"
            }
            //
            field = table.rows[rowdev + j].cells[5].getElementsByTagName("input")[0];
            cmd = field.value;
            //
            cmd = '{Babble_ModCmd("' + name + '","' + bdev + '","' + place + '","' + verb + '","' + target + '","' + encodeParm(cmd) + '")}';
            FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '=' + cmd);
        }
    };
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '={Babble_savename("' + name + '")}');
}

var httpRequest;

function babble_testit(name) {
    var sentence = document.getElementById("d_testcommand").value;
    var exec =  document.getElementById("b_execit").checked;
    var exflag;
    if( exec ){
       exflag=1;
    }else{
       exflag=0;
    }
    var url = document.location.protocol + "//" + document.location.host + "/fhem";
    var cmd = '{Babble_TestIt("' + name + '","' + encodeParm(sentence) + '",' + exflag + ')}';
  
    httpRequest = new XMLHttpRequest();
    httpRequest.open("GET", url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '=' + cmd, true);
    httpRequest.onreadystatechange = parse;
    httpRequest.send(null);
};

function parse () {
    if (httpRequest.readyState != 3) {
        return;
    }
    var lines = httpRequest.responseText.split("\n");
    //Pop the last (maybe empty) line after the last "\n"
    //We wait until it is complete, i.e. terminated by "\n"
    lines.pop();
    document.getElementById("d_testresult").innerHTML = lines[1];
}