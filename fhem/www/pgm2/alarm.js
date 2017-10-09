//########################################################################################
// alarm.js
// Version 2.81
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

//var ah = new HashTable('l0s','','l0e','');

//------------------------------------------------------------------------------------------------------
// Write the Attribute Value
//------------------------------------------------------------------------------------------------------
function alarm_setAttribute(name, attr, val) {//set Alarm Attribute
	var location = document.location.pathname;
    if (location.substr(location.length-1,1) == '/') {location = location.substr(0,location.length-1);}
	var url = document.location.protocol+"//"+document.location.host+location;
	FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' '+encodeParm(attr)+' '+ encodeParm(val));
}

function alarm_cancel(name,level){
    var val;
    var nam;

    var location = document.location.pathname;
    if (location.substr(location.length-1,1) == '/') {location = location.substr(0,location.length-1);}
	var url = document.location.protocol+"//"+document.location.host+location;

    FW_cmd(url+'?XHR=1&cmd.'+name+'={Alarm_Exec("'+name+'",'+level+',"web","button","off")}');
   }
   
function alarm_arm(name,level){
    var val;
    var nam;
    var command = document.getElementById('l'+level+'x').checked;
    if (command == true){
        command="arm";
    }else{
        command="disarm";
    }
    var location = document.location.pathname;
    if (location.substr(location.length-1,1) == '/') {location = location.substr(0,location.length-1);}
	var url = document.location.protocol+"//"+document.location.host+location;

    FW_cmd(url+'?XHR=1&cmd.'+name+'={Alarm_Arm("'+name+'",'+level+',"web","button","'+command+'")}');
   }
   
function alarm_testaction(name,dev,type){
    var cmd;
    var nam;
    if(type == 'set'){
      cmd = document.getElementById(dev).parentElement.children[2].children[0].value;
    }else{
      cmd = document.getElementById(dev).parentElement.children[3].children[0].value;
    }
    var cmds;
    cmds = cmd.replace(/\\/g, '\\');
    cmds = cmds.replace(/\'/g, '\"');
    cmds = cmds.replace(/\$/g, '\\$');
    alert( cmds );
 
    var location = document.location.pathname;
    if (location.substr(location.length-1,1) == '/') {location = location.substr(0,location.length-1);}
	var url = document.location.protocol+"//"+document.location.host+location;

    FW_cmd(url+'?XHR=1&cmd.'+name+'={Alarm_Test("'+name+'","' + cmds + '")}');
   }
    

function alarm_set(name){
    var val;
    var nam;

    var location = document.location.pathname;
    if (location.substr(location.length-1,1) == '/') {location = location.substr(0,location.length-1);}
	var url = document.location.protocol+"//"+document.location.host+location;
    
    // saving arm data
    FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' armdelay '+ document.getElementById('armdelay').value);
    FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' armwait '+ encodeParm(document.getElementById('armwait').value));
    FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' armact '+ encodeParm(document.getElementById('armaction').value));
    FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' disarmact '+ encodeParm(document.getElementById('disarmaction').value));
    FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' cancelact '+ encodeParm(document.getElementById('cancelaction').value));
    
    // saving start and end times
    for (var i = 0; i < alarmno; i++){
        FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' level'+i+'start '+document.getElementById('l'+i+'s').value);
        FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' level'+i+'end '  +document.getElementById('l'+i+'e').value);
        FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' level'+i+'msg '  +document.getElementById('l'+i+'m').value);
        if (document.getElementById('l'+i+'x').checked == true ){
            val = "armed";
        }else{
            val = "disarmed";
        }
        FW_cmd(url+'?XHR=1&cmd.'+name+'=attr '+name+' level'+i+'xec '  + val);
   }
    //for (var k in ah.items) {
    //   ah.setItem(k,document.getElementById(k).value);
    //}
    
    // acquiring data for each sensor
    var sarr = document.getElementsByName('sensor');  
    for (var k = 0; k < sarr.length; k++){
        nam  = sarr[k].getAttribute('informId');
        val  = "";
        for (var i = 0; i < alarmno; i++){
            if (sarr[k].children[1].children[i].checked == true ){
                val += "alarm"+i+",";
            }
        }
        val += "|"+sarr[k].children[2].children[0].value;
        val += "|"+sarr[k].children[3].children[0].value;
        val += "|"+sarr[k].children[4].children[0].options[sarr[k].children[4].children[0].selectedIndex].value;
        FW_cmd(url+'?XHR=1&cmd.'+nam+'=attr '+nam+' alarmSettings ' + encodeParm(val));
    }
    
    // acquiring data for each actor
    var aarr = document.getElementsByName('actor');  
    for (var k = 0; k < aarr.length; k++){
        nam  = aarr[k].getAttribute('informId');
        val  = "";
        for (var i = 0; i < alarmno; i++){
            //alert(" Checking "+k+" "+i)
            if (aarr[k].children[1].children[i].checked == true ){
                val += "alarm"+i+",";
            }
        }
        val += "|"+aarr[k].children[2].children[0].value;
        val += "|"+aarr[k].children[3].children[0].value;
        val += "|"+aarr[k].children[4].children[0].value;
        FW_cmd(url+'?XHR=1&cmd.'+nam+'=attr '+nam+' alarmSettings ' + encodeParm(val));
    }
    
    // creating notifiers
    FW_cmd(url+'?XHR=1&cmd.' + name + ' ={main::Alarm_CreateNotifiers("' + name + '")}');

}


