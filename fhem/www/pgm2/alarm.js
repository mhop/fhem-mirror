//########################################################################################
// alarm.js
// Version 3.1
// See 95_Alarm for licensing
//########################################################################################
//# Prof. Dr. Peter A. Henning

function encodeParm(oldval) {
    var newval;
    newval = oldval.replace(/\+/g, '%2B');
    newval = newval.replace(/#/g, '%23');
    newval = newval.replace(/"/g, '%27');
    return newval;
}

//------------------------------------------------------------------------------------------------------
// Animated Icon
//------------------------------------------------------------------------------------------------------

var bellfill;

function blinkbell() {
    var w = document.getElementById("alarmicon");
    if (w) {
        if (bellfill == alarmcolor) {
            bellfill = "white";
            w.getElementsByClassName("alarmst_b")[0].setAttribute("fill", "white");
            w.getElementsByClassName("alarmst_sb")[0].setAttribute("fill", "white");
        } else {
            bellfill = alarmcolor;
            w.getElementsByClassName("alarmst_b")[0].setAttribute("fill", alarmcolor);
            w.getElementsByClassName("alarmst_sb")[0].setAttribute("fill", alarmcolor);
        }
    }
}

function updateIcon(name, alarmst) {
    var w = document.getElementById(name);
    if (w) {
        switch (alarmst) {
            case "disarmed":
            w.getElementsByClassName("alarmst_b")[0].setAttribute("fill", "white");
            w.getElementsByClassName("alarmst_sb")[0].setAttribute("fill", "white");
            if (blinking == 1) {
                clearInterval(blinker);
                blinking = 0;
            }
            break;
            
            case "mixed":
            w.getElementsByClassName("alarmst_b")[0].setAttribute("fill", armwaitcolor);
            w.getElementsByClassName("alarmst_sb")[0].setAttribute("fill", "white");
            if (blinking == 1) {
                clearInterval(blinker);
                blinking = 0;
            }
            break;
            
            case "armed":
            w.getElementsByClassName("alarmst_b")[0].setAttribute("fill", armcolor);
            w.getElementsByClassName("alarmst_sb")[0].setAttribute("fill", "white");
            if (blinking == 1) {
                clearInterval(blinker);
                blinking = 0;
            }
            break;
            
            default:
            if (blinking == 0) {
                blinker = setInterval('blinkbell()', 250);
                blinking = 1;
            }
        }
    }
}

$("body").on('DOMSubtreeModified', "#hid_levels", function () {
    var w = document.getElementById("hid_levels");
    var v = document.getElementById("alarmicon");
    var t = v.getElementsByClassName("arec");
    var ifnd;
    var sfnd;
    var col;
    for (i = 0; i < alarmno; i++) {
        var s = w.getElementsByClassName("hid_lx")[i].innerHTML;
        if (ast[i] != s) {
            switch(s){
                case "disarmed":
                    col = disarmcolor;
                    break;
                case "armwait":
                    col = armwaitcolor;
                    break;
                case "armed":
                    col = armcolor;
                    break;
                default:
                    col = alarmcolor
            }
            t[i].setAttribute("fill",col);
            ast[i] = s;
            ifnd = i;
            sfnd = s;
        }
    }
    if (ifnd && (iconmap.includes(ifnd))) {
        var aan = true;
        var adn = true;
        var aln = "";
        var atn = "";
        for (i = 0; i < alarmno; i++) {
            if (iconmap.includes(i)) {
                var s = ast[i];
                if (s != "disarmed" && s != "armwait" && s != "armed") {
                    aln = aln + i + ",";
                    atn = atn + s + ",";
                } else {
                    adn = adn && ((s == "disarmed")||(s == "armwait"));
                    aan = aan && (s == "armed");
                }
            }
        }
        
        if (adn != ad || aan != aa || aln != al) {
            aa = aan;
            ad = adn;
            al = aln;
            at = atn;
            
            var iconstate;
            if (al != "") {
                iconstate = al;
            } else {
                if (aa && (! ad)) {
                    iconstate = "armed";
                } else {
                    if ((! aa) && ad) {
                        iconstate = "disarmed";
                    } else {
                        iconstate = "mixed";
                    }
                }
            }
            updateIcon('alarmicon', iconstate);
        }
    }
});

//------------------------------------------------------------------------------------------------------
// Write the Attribute Value
//------------------------------------------------------------------------------------------------------

function alarm_setAttribute(name, attr, val) {
    //set Alarm Attribute
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' ' + encodeParm(attr) + ' ' + encodeParm(val));
}

function alarm_cancel(name, level) {
    var val;
    var nam;
    
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    FW_cmd(url + '?XHR=1&cmd.' + name + '={Alarm_Exec("' + name + '",' + level + ',"web","button","off")}');
}

function alarm_arm(name, level) {
    var val;
    var nam;
    var command = document.getElementById('l' + level + 'x').checked;
    if (command == true) {
        command = "arm";
    } else {
        command = "disarm";
    }
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    FW_cmd(url + '?XHR=1&cmd.' + name + '={Alarm_Arm("' + name + '",' + level + ',"web","button","' + command + '")}');
}

function alarm_testaction(name, dev, type) {
    var cmd;
    var nam;
    if (type == 'set') {
        cmd = document.getElementById(dev).parentElement.children[2].children[0].value;
    } else {
        cmd = document.getElementById(dev).parentElement.children[3].children[0].value;
    }
    var cmds;
    cmds = cmd.replace(/\\/g, '\\');
    cmds = cmds.replace(/\'/g, '\"');
    cmds = cmds.replace(/\$/g, '\\$');
    alert(cmds);
    
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    FW_cmd(url + '?XHR=1&cmd.' + name + '={Alarm_Test("' + name + '","' + cmds + '")}');
}


function alarm_set(name) {
    var val;
    var nam;
    
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    
    // saving arm data
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' armdelay ' + document.getElementById('armdelay').value);
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' armwait ' + encodeParm(document.getElementById('armwait').value));
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' armact ' + encodeParm(document.getElementById('armaction').value));
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' disarmact ' + encodeParm(document.getElementById('disarmaction').value));
    FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' cancelact ' + encodeParm(document.getElementById('cancelaction').value));
    
    // saving start and end times
    for (var i = 0;
    i < alarmno;
    i++) {
        FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' level' + i + 'start ' + document.getElementById('l' + i + 's').value);
        FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' level' + i + 'end ' + document.getElementById('l' + i + 'e').value);
        FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' level' + i + 'msg ' + document.getElementById('l' + i + 'm').value);
        if (document.getElementById('l' + i + 'x').checked == true) {
            val = "armed";
        } else {
            val = "disarmed";
        }
        FW_cmd(url + '?XHR=1&cmd.' + name + '=attr ' + name + ' level' + i + 'xec ' + val);
    }
    //for (var k in ah.items) {
    //   ah.setItem(k,document.getElementById(k).value);
    //}
    
    // acquiring data for each sensor
    var sarr = document.getElementsByName('sensor');
    for (var k = 0;
    k < sarr.length;
    k++) {
        nam = sarr[k].getAttribute('informId');
        val = "";
        for (var i = 0;
        i < alarmno;
        i++) {
            if (sarr[k].children[1].children[i].checked == true) {
                val += "alarm" + i + ",";
            }
        }
        val += "|" + sarr[k].children[2].children[0].value;
        val += "|" + sarr[k].children[3].children[0].value;
        val += "|" + sarr[k].children[4].children[0].options[sarr[k].children[4].children[0].selectedIndex].value;
        FW_cmd(url + '?XHR=1&cmd.' + nam + '=attr ' + nam + ' alarmSettings ' + encodeParm(val));
    }
    
    // acquiring data for each actor
    var aarr = document.getElementsByName('actor');
    for (var k = 0;
    k < aarr.length;
    k++) {
        nam = aarr[k].getAttribute('informId');
        val = "";
        for (var i = 0;
        i < alarmno;
        i++) {
            //alert(" Checking "+k+" "+i)
            if (aarr[k].children[1].children[i].checked == true) {
                val += "alarm" + i + ",";
            }
        }
        val += "|" + aarr[k].children[2].children[0].value;
        val += "|" + aarr[k].children[3].children[0].value;
        val += "|" + aarr[k].children[4].children[0].value;
        FW_cmd(url + '?XHR=1&cmd.' + nam + '=attr ' + nam + ' alarmSettings ' + encodeParm(val));
    }
    
    // creating notifiers
    FW_cmd(url + '?XHR=1&cmd.' + name + ' ={main::Alarm_CreateNotifiers("' + name + '")}');
}