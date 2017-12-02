//########################################################################################
// yaahm.js
// Version 1.30
// See 95_YAAHM for licensing
//########################################################################################
//# Prof. Dr. Peter A. Henning

function encodeParm(oldval) {
    var newval;
    newval = oldval.replace(/\+/g, '%2B');
    newval = newval.replace(/#/g, '%23');
    newval = newval.replace(/"/g, '%27');
    return newval;
}

// Tool Tips
//  $( function() {
//    $( document ).tooltip();
//  } );

//------------------------------------------------------------------------------------------------------
// Expand text box
//------------------------------------------------------------------------------------------------------

$(function () {
    $(".expand").focus(function () {
        $(this).animate({
            width: '200px'
        },
        "slow")
    });
});

$(function () {
    $(".expand").blur(function () {
        $(this).animate({
            width: '100px'
        },
        "slow")
    });
});

//------------------------------------------------------------------------------------------------------
// Write the Attribute Value
//------------------------------------------------------------------------------------------------------

function yaahm_setAttribute(name, attr, val) {
    //set Yaahm Attribute
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' ' + encodeParm(attr) + ' ' + encodeParm(val));
}

//------------------------------------------------------------------------------------------------------
// Change mode and state, set next time
//------------------------------------------------------------------------------------------------------

var hsold;
var hmold;

function yaahm_mode(name, targetmode) {
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    FW_cmd(url + '?XHR=1&cmd.' + name + '={main::YAAHM_mode("' + name + '","' + targetmode + '")}');
}

function yaahm_state(name, targetstate) {
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    FW_cmd(url + '?XHR=1&cmd.' + name + '={main::YAAHM_state("' + name + '","' + targetstate + '")}');
}

function yaahm_setnext(name, i) {
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    var nval;
    if (document.getElementById('wt' + i + '_n') !== null) {
        nval = document.getElementById('wt' + i + '_n').value;
    } else {
        nval = "undef";
    }
    
    FW_cmd(url + '?XHR=1&cmd.' + name + '={main::YAAHM_nextWeeklyTime("' + name + '","next_' + i + '","' + nval + '")}');
}

//------------------------------------------------------------------------------------------------------
// Animate housestate icon
//------------------------------------------------------------------------------------------------------

$("body").on('DOMSubtreeModified', "#hid_hs",
function () {
    var hsnew = document.getElementById("hid_hs").innerHTML;
    if (hsnew != hsold) {
        hsold = hsnew;
        var w = document.getElementById("wid_hs");
        if (w) {
            switch (hsnew) {
                case "unsecured":
                w.getElementsByClassName("hs_is")[0].setAttribute("fill", csstate[0]);
                w.getElementsByClassName("hs_smb")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hs_unlocked")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hs_locked")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hs_eye")[0].setAttribute("visibility", "hidden");
                break;
                case "secured":
                w.getElementsByClassName("hs_is")[0].setAttribute("fill", csstate[1]);
                w.getElementsByClassName("hs_smb")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hs_unlocked")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hs_locked")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hs_eye")[0].setAttribute("visibility", "hidden");
                break;
                case "protected":
                w.getElementsByClassName("hs_is")[0].setAttribute("fill", csstate[2]);
                w.getElementsByClassName("hs_smb")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hs_unlocked")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hs_locked")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hs_eye")[0].setAttribute("visibility", "hidden");
                break;
                case "guarded":
                w.getElementsByClassName("hs_is")[0].setAttribute("fill", csstate[3]);
                w.getElementsByClassName("hs_smb")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hs_unlocked")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hs_locked")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hs_eye")[0].setAttribute("visibility", "visible");
                break;
            }
        } else {
            alert("state widget not found");
        }
    }
});

$("body").on('DOMSubtreeModified', "#hid_hm",
function () {
    var hmnew = document.getElementById("hid_hm").innerHTML;
    if (hmnew != hmold) {
        hmold = hmnew;
        var w = document.getElementById("wid_hm");
        if (w) {
            switch (hmnew) {
                case "normal":
                w.getElementsByClassName("hm_is")[0].setAttribute("fill", csmode[0]);
                w.getElementsByClassName("hm_n")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hm_p")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_a")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_dnd")[0].setAttribute("visibility", "hidden");
                break;
                case "party":
                w.getElementsByClassName("hm_is")[0].setAttribute("fill", csmode[1]);
                w.getElementsByClassName("hm_n")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_p")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hm_a")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_dnd")[0].setAttribute("visibility", "hidden");
                break;
                case "absence":
                w.getElementsByClassName("hm_is")[0].setAttribute("fill", csmode[2]);
                w.getElementsByClassName("hm_n")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_p")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_a")[0].setAttribute("visibility", "visible");
                w.getElementsByClassName("hm_dnd")[0].setAttribute("visibility", "hidden");
                break;
                case "donotdisturb":
                w.getElementsByClassName("hm_is")[0].setAttribute("fill", csmode[3]);
                w.getElementsByClassName("hm_n")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_p")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_a")[0].setAttribute("visibility", "hidden");
                w.getElementsByClassName("hm_dnd")[0].setAttribute("visibility", "visible");
                break;
            }
        } else {
            alert("mode widget not found");
        }
    }
});


//------------------------------------------------------------------------------------------------------
// Start the daily timer
//------------------------------------------------------------------------------------------------------

function yaahm_startDayTimer(name) {
    
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    // saving start and end times
    for (var i = 0; i < dailyno; i++) {
        var sval, eval, xval, aval1, aval2;
        if ((dailykeys[i] != 'wakeup') && (dailykeys[i] != 'sleep')) {
            if (document.getElementById('dt' + dailykeys[i] + '_s') !== null) {
                sval = document.getElementById('dt' + dailykeys[i] + '_s').value;
            } else {
                sval = "undef"
            }
            if (document.getElementById('dt' + dailykeys[i] + '_e') !== null) {
                eval = document.getElementById('dt' + dailykeys[i] + '_e').value;
            } else {
                eval = "undef"
            }
            if (document.getElementById('dt' + dailykeys[i] + '_x') !== null) {
                xval = encodeParm(document.getElementById('dt' + dailykeys[i] + '_x').value);
            } else {
                xval = "undef"
            }
            aval1 = $("input[name='actim" + dailykeys[i] + "']:checked").map(function () {
                return $(this).val();
            }).get();
            aval2 = $("input[name='actid" + dailykeys[i] + "']:checked").map(function () {
                return $(this).val();
            }).get();
            FW_cmd(url + '?XHR=1&cmd.' + name + '={main::YAAHM_setParm("' + name + '","dt","' + dailykeys[i] + '",' + '"' + sval + '","' + eval + '","' + xval + '","' + aval1 + ';' + aval2 + '")}');
        }
    }
    // really start it now
    FW_cmd(url + '?XHR=1&cmd.' + name + ' ={main::YAAHM_startDayTimer("' + name + '")}');
    
    // change link
    $('#dtlink').html('<a href="/fhem?detail=' + name + '.dtimer.IF">' + name + '.dtimer.IF</a>');
}

//------------------------------------------------------------------------------------------------------
// Weekly profile
//------------------------------------------------------------------------------------------------------

function yaahm_startWeeklyTimer(name) {
    
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    // saving start weekly times
    // iterate over different weekly tables
    for (var i = 0; i < weeklyno; i++) {
        var xval;
        var nval;
        var aval1, aval2;
        var sval =[ "", "", "", "", "", "", ""];
        //action
        if (document.getElementById('wt' + i + '_x') !== null) {
            xval = encodeParm(document.getElementById('wt' + i + '_x').value);
        } else {
            xval = "undef"
        }
        //next time - attention, field is in toptable
        if (document.getElementById('wt' + i + '_n') !== null) {
            nval = document.getElementById('wt' + i + '_n').value;
        } else {
            nval = "undef"
        }
        //activity party/absence
        aval1 = $("input[name='acti_" + i + "_m']:checked").map(function () {
            return $(this).val();
        }).get();
        //activity vacation/holiday
        aval2 = $("input[name='acti_" + i + "_d']:checked").map(function () {
            return $(this).val();
        }).get();
        
        //iterate over days of week
        for (var j = 0; j < 7; j++) {
            if (document.getElementById('wt' + weeklykeys[j] + i + '_s') !== null) {
                sval[j] = document.getElementById('wt' + weeklykeys[j] + i + '_s').value;
            } else {
                sval[j] = "undef";
            }
        }
        
        FW_cmd(url + '?XHR=1&cmd.' + name + '={main::YAAHM_setParm("' + name + '","wt","' + i + '","' + xval + '","' + nval + '","' + aval1 + '","' + aval2 + '","' + sval.join('","') + '")}');
    }
    // really start it now
    FW_cmd(url + '?XHR=1&cmd.' + name + ' ={main::YAAHM_startWeeklyTimer("' + name + '")}');
    
    // change links
    for (var i = 0; i < weeklyno; i++) {
        $('#wt' + i + 'link').html('<a href="fhem?detail=' + name + '.wtimer_' + i + '.IF">' + name + '.wtimer_' + i + '.IF</a>');
    }
}