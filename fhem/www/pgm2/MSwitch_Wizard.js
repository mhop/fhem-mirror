// MSwitch_Wizard.js
// Autor:Byte09
// #########################



	var version = 'V1.2';
	var info = '';
	var logging ='off';
	var observer;
	var target;
	var lastevent;
	var show = 'off';
	var offtime =50;
	var sets = new Object();
	
	var preconfparts = new Array;
	var preconfpartsname = new Array;
	var preconfpartshelp = new Array;
	
	var configstart = [
	'#V Version',
	'#VS V2.00',
	'#S .First_init -> done',
	'#S .Trigger_off -> no_trigger',
	'#S .Trigger_cmd_off -> no_trigger',
	'#S Trigger_device -> no_trigger',
	'#S Trigger_log -> off',
	'#S .Trigger_on -> no_trigger',
	'#S .Trigger_cmd_on -> no_trigger',
	'#S .Trigger_condition -> ',
	'#S .V_Check -> V2.00',
	'#S .Device_Events -> no_trigger',
	'#S .Device_Affected -> no_device',
	'#S .Trigger_time -> ',
	'#A MSwitch_Debug -> 0',
	'#A MSwitch_Delete_Delays -> 0',
	'#A MSwitch_Eventhistory -> 0',
	'#A MSwitch_Safemode -> 1',
	'#A MSwitch_Lock_Quickedit -> 1',
	'#A MSwitch_Help -> 0',
	'#A room -> MSwitch_Devices',
	'#A MSwitch_Extensions -> 0',
	'#A MSwitch_Ignore_Types -> notify allowed at watchdog doif fhem2fhem telnet FileLog readingsGroup FHEMWEB autocreate eventtypes readingsproxy svg cul',
	'#A MSwitch_Include_Webcmds -> 0',
	'#A MSwitch_Include_MSwitchcmds -> 0',
	'#A MSwitch_Mode -> Notify',
	'#A MSwitch_Expert -> 0',
	'#A MSwitch_Include_Devicecmds -> 1'];

// starte Hauptfenster
conf('importWIZARD','wizard');

//####################################################################################################
// init eventmonitor

// Konfiguration des Observers: alles melden - Änderungen an Daten, Kindelementen und Attributen
	var config = { attributes: true, childList: true, characterData: true };
// test observer
// zu überwachende Zielnode (target) auswählen
	target = document.querySelector('div[informid="'+devicename+'-EVENTCONF"]');
 
// eine Instanz des Observers erzeugen
	observer = new MutationObserver(function(mutations) {
		mutations.forEach(function(mutation) {

	var test = $( "div[informId='"+devicename+"-EVENTCONF']" ).text();
	test = test.replace(/ /gi,"");

	if(o[test]){return;}

	var event = test.split(':');
	var newevent =  event[1]+':'+event[2]
	if (event[0] != document.getElementById('3').value)
		{
			return;
		}
	if (logging == 'off')
		{
			return;
		}
	lastevent=newevent;
	o[test] = test;		
		
	// eintrag in dropdown und fenster ausblenden
	newselect = $('<option value="'+newevent+'">'+newevent+'</option>');
	$(newselect).appendTo('#6step');

	// umwandlung des objekts in standartarray
	var a3 = Object.keys(o).map(function (k) { return o[k];})
	// array umdrehen
	a3.reverse();
	$( '#eventcontrol' ).text( '' );
	var i;
	for (i = 0; i < 30; i++) 
		{
		if (a3[i])
			{
			var newselect = $('<option value=\"'+a3[i]+'\">'+a3[i]+'</option>');
			$(newselect).appendTo('#eventcontrol'); 
			}
		}  
  });    
});


//####################################################################################################


function eventmonitorstop(){
	if (observer){
		observer.disconnect();
	}	
	return;
}

function eventmonitorstart(){
	
	var newselect = $('<option value="Event wählen">Event wählen:</option>');
	$(newselect).appendTo('#6step');
	observer.observe(target, config);
	
	return;
}

function closeall(){
	
		logging ='off';
		o = new Object();
		eventmonitorstop()
		
		if (show == 'off'){
		document.getElementById('4step1').style.display='none';
		document.getElementById('4step2').style.display='none';
		document.getElementById('5step1').style.display='none';
		document.getElementById('5step2').style.display='none';
		document.getElementById('2step1').style.display='none';
		document.getElementById('2step2').style.display='none';
		document.getElementById('3step1').style.display='none';
		document.getElementById('3step2').style.display='none';
		
		document.getElementById('part2').innerHTML ='';
		}
		document.getElementById('monitor').style.display='none';
	
	return;
}
// settyp
function settypptime(inhalt,open,fill) {
	openraw=open;
	//  #inh1 =inhalt
	//  #open = freizuschaltendezeile
	//  #fill = zu füllendes feld
	open=openraw+'1';
	open1=openraw+'2';
	
	if (open == '3step1')
	{
		document.getElementById('help').innerHTML = 'Bitte in der Dropdownliste das Gerät wählen , dessen Events als Auslöser dienen soll.';	
	}
	
	if (open == '2step1')
	{
		document.getElementById('help').innerHTML = 'Bitte die Zeit angeben, zu der das MSwitch-Device auslösen soll.<br>';	
		document.getElementById('help').innerHTML += 'Hier stehen mehrere Formate zur Verfügung<br>';
		document.getElementById('help').innerHTML += 'Bitte in der Dropdownliste eine Vorauswahl treffen :<br>&nbsp;<br>';
	}
		
	if (open == '4step1')
	{
		
		if (inhalt == 'select')
		{
			document.getElementById('monitor').style.display='none';
			document.getElementById('4step1').style.display='none';

			return;
		}

		document.getElementById('monitor').style.display='block';
		document.getElementById('help').innerHTML = 'Bitte das entsprechende Event des gewählen Gerätes auslösen. Entweder durch betätigen gewählter Hardware, oder durch schalten des entsprechenden Devices in Fhem.<br>Wenn das gewünschte Event im Monitor sichtbar ist auf den Button \'Event eingetroffen\' klicken';	

		$( '#6step' ).text( '' );
		$( '#eventcontrol' ).text( '' );
		text = 'Warte auf eingehende Events des Devices '+inhalt+' ... ';
		text =text+'<input name=\"5th\" id=\"5step\" type=\"button\" value=\"Event eingetroffen\" onclick=\"javascript: settypptime(this.value,id,name)\">&nbsp;';
		document.getElementById('4step1').innerHTML = text;
	
		logging='on';
		eventmonitorstart();
	}	
	
	if (open == '5step1')
	{
		eventmonitorstop();
		logging = 'off';
		document.getElementById('monitor').style.display='none';
		document.getElementById('5').value=lastevent;
		document.getElementById('help').innerHTML = 'Bitte das auslösende Event aus der Dropdownliste wählen. Im rechten Feld kann das Event manuell angepasst werden.';	
	}

	if (document.getElementById(fill)){document.getElementById(fill).value=inhalt;}

	if (document.getElementById(open)) {
		document.getElementById(open).style.display='block';
	}
	if (document.getElementById(open1)) {
		document.getElementById(open1).style.display='block';
	}
	
	if (open == '6step1')
	{
		// wird von fertig gewähltem event aufgerufen
		// starte Teil2
		// endptime();
		setTimeout(endptime, offtime);
	}
	
	if (open == '7step1')
	{
		// auswahl time event fertig 
		// starte Teil2
		setTimeout(endptime, offtime);
	}
	 
	return;
	}
	
	
function reset() {
	var nm = devicename;
	var  def = nm+' reset_device checked';
	location = location.pathname+'detail='+devicename+'&cmd=set '+addcsrf(def);
	return;
	}
	
function endptime() {

	// starte teil2
	createpart2();
	return;
	}
	
function togglep1() {
		//show = 'on';

		if (show == 'on'){
			show = 'off';
			insert = 'none';
		}
		else if(show == 'off'){
			show = 'on';
			insert = 'block';
		}
		
		// schliessen aller P1Fenster
		document.getElementById('help').innerHTML = '';
		document.getElementById('1step1').style.display=insert;
		document.getElementById('1step2').style.display=insert;
		document.getElementById('4step1').style.display=insert;
		document.getElementById('4step2').style.display=insert;
		document.getElementById('5step1').style.display=insert;
		document.getElementById('5step2').style.display=insert;
		document.getElementById('2step1').style.display=insert;
		document.getElementById('2step2').style.display=insert;
		document.getElementById('3step1').style.display=insert;
		document.getElementById('3step2').style.display=insert;
		document.getElementById('monitor').style.display='block';

	return;
	}
	
	
// hauptfenster wählen
function conf(typ,but){
	eventmonitorstop()
	closeall();
	document.getElementById('help').innerHTML = '';	

	document.getElementById('importAT').style.display='none';
	document.getElementById('importNOTIFY').style.display='none';
	document.getElementById('importCONFIG').style.display='none';
	document.getElementById('importWIZARD').style.display='none';
	document.getElementById('importPRECONF').style.display='none';
	
	document.getElementById('wizard').style.backgroundColor='';
	document.getElementById('config').style.backgroundColor='';
	document.getElementById('importat').style.backgroundColor='';
	document.getElementById('importnotify').style.backgroundColor='';
	document.getElementById('importpreconf').style.backgroundColor='';
	
	document.getElementById(typ).style.display='block';
	document.getElementById(but).style.backgroundColor='#ffb900';

	if (but == 'wizard'){
		// neustart wizard
		
		startwizardtrigger();
	}
	
	if (but == 'config'){
		// neustart wizard
		startconfig();
	}
	
	if (but == 'importat'){
	// neustart wizard
	startimportat();
	}
	
	if (but == 'importnotify'){
	// neustart wizard
	startimportnotify();
	}
	
	if (but == 'importpreconf'){
	// neustart wizard
	//alert('aufruf');
	startimportpreconf();
	}
	
	return;
}	
	
function start1(name){
	
	    // this code will run after all other $(document).ready() scripts
        // have completely finished, AND all page elements are fully loaded.
		$( ".makeSelect" ).text( "" );
		$( "[class='makeTable wide readings']" ).hide();
		$( "[class='makeTable wide internals']" ).hide();
		$( "[class='makeTable wide attributes']" ).hide();
		$( "[class=\"detLink iconFor\"]" ).hide();
		$( "[class=\"detLink rawDef\"]" ).hide();
		$( "[class=\"detLink devSpecHelp\"]" ).hide();
		$( "[class=\"detLink showDSI\"]" ).text( "" );
		r3 = $('<a href=\"javascript: reset()\">Reset this device ('+name+')</a>');
		$(r3).appendTo('[class=\"detLink showDSI\"]');

		document.getElementById('mode').innerHTML += '<br>Wizard Version:'+version+'<br>Info:'+info;
		// fülle configfenster
		fillconfig('rawconfig');
		startwizardtrigger();
			
setTimeout(function() {
	//document.getElementById('wizard').value+=' N/A';
	//document.getElementById('config').value+=' N/A';
	//document.getElementById('importat').value+=' N/A';
	//document.getElementById('importnotify').value+=' N/A';
  	//document.getElementById('wizard').disabled = true;
	//document.getElementById('config').disabled = true;
	//document.getElementById('importat').disabled = true;
	//document.getElementById('importnotify').disabled = true;
	//document.getElementById('importpreconf').disabled = true;
 // conf('importPRECONF','importpreconf');
}, 50);

		
}

function startwizardtrigger(){	
	

	document.getElementById('saveconf').style.backgroundColor='#ff0000';
	document.getElementById('saveconf').disabled = true;
// help
	document.getElementById('help').innerHTML = 'Auslöser: Bitte wählen ob die Auslösung zeit- oder eventgesteuert sein soll ( Button \'time\' oder \'event\' )';	
// htmlaufbau	
// document.getElementById('showall').disabled = true;


		document.getElementById('monitor').style.display='none';
		
		line = 'Was für ein Ereigniss soll das MSwitch auslösen ( Trigger ) ?&nbsp;&nbsp;&nbsp;&nbsp;';
		line =line+'<input name=\"first\" id=\"2step\" type=\"button\" value=\"time\" onclick=\"javascript: settypptime(this.value,id,name)\">&nbsp;';
		line =line+'<input name=\"first\" id=\"3step\" type=\"button\" value=\"event\" onclick=\"javascript: settypptime(this.value,id,name)\">&nbsp;';
		document.getElementById('1step1').innerHTML = line;

		line ='<input id =\"first\" type=\"text\" value=\"\" disabled=\"disabled\">';
		document.getElementById('1step2').innerHTML = line;

		line = '<table border ="0"><tr>';
		line += '<td>';
		
		line += '<select id="timetyps" name="timetyp" name="timetyp" onchange=\"javascript: settimetyp(this.value)\">';
		line += '<option id ="" value="typ0">wähle Zeit-Typ:</option>';
		line += '<option id ="" value="typ1">exakte Zeitangabe</option>';
		line += '<option id ="" value="typ2">zufällige Schaltzeit zwischen zwei Zeitpunkten</option>';
		line += '<option id ="" value="typ3">periodische Auslösung zwischen zwei Zeitpunkten</option>';
		line += '</select>';
		line += '</td>'
		line += '</tr>'
		line += '<tr>'
		
		line += '<td>';
		
		fbutton = '<input name=\"selecttyp\" id=\"selecttyp\" type=\"button\" value=\"übernehmen\" onclick=\"javascript: settime()\">';
			
		line += '<div id ="typ1" style="display:none">Um '+gettime('normal')+' Uhr '+getday('day1')+fbutton+'</div>';
		line += '<div id ="typ2" style="display:none">zwischen '+gettime('zufall')+' Uhr und '+gettime('zufall1') +'Uhr '+getday('zufal3')+fbutton+'</div>';
		line += '<div id ="typ3" style="display:none">periodisch alle '+gettime('periodic')+' zwischen '+gettime('periodic1') +'Uhr und'+gettime('periodic3')+'Uhr'+getday('periodic4')+fbutton+'</div>';
			
		line += '</td>'
		line += '</tr></table>';		

		document.getElementById('2step1').innerHTML = line;
		document.getElementById('2step1').style.display='none';
		line ='<input id=\"2\" type=\"text\" value=\"\" disabled=\"disabled\"> ';
		document.getElementById('2step2').innerHTML = line;
		document.getElementById('2step2').style.display='none';
		document.getElementById('1step1').style.display='block';
		document.getElementById('1step2').style.display='block';

		line = 'Welches Gerärt soll der Auslöser sein ? &nbsp;&nbsp;&nbsp;&nbsp;';
		line += devicelist('4step','3','settypptime');

		document.getElementById('3step1').innerHTML = line;
		document.getElementById('3step1').style.display='none';
		line ='<input id=\"3\" type=\"text\" value=\"\" disabled=\"disabled\">';
		document.getElementById('3step2').innerHTML = line;
		document.getElementById('3step2').style.display='none';
	
		line = 'Warte auf eingehende Events des Devices ';
		document.getElementById('4step1').innerHTML = line;
		document.getElementById('4step1').style.display='none';
		
		line = 'Auslösendes Event wählen ? &nbsp;&nbsp;&nbsp;&nbsp;';
		line =line+'<select id =\"6step\" name=\"5\" onchange=\"javascript: settypptime(this.value,id,name)\">';
	
		line =line+'</select>';
		document.getElementById('5step1').innerHTML = line;
		document.getElementById('5step1').style.display='none';
		line ='<input id=\"5\" type=\"text\" value=\"\" >';
		document.getElementById('5step2').innerHTML = line;
		document.getElementById('5step2').style.display='none';

	return ;

	}
	
function makeconfig(){
	// configstart[0] = '#V '+mVersion;
	if (document.getElementById('first').value == 'time'){
		// ändere config für timeevent
		string = document.getElementById('2').value;
		// ersetze dp durch #[dp]
		string = string.replace(/:/gi,"#[dp]");
		configstart[13] ='#S .Trigger_time -> on~off~ononly'+ string +'~offonly~onoffonly';
	}

	if (document.getElementById('first').value == 'event'){
		// ändere config für triggerevent
		configstart[5] ='#S Trigger_device -> '+ document.getElementById('3').value;
		configstart[8] ='#S .Trigger_cmd_on -> '+ document.getElementById('5').value;
	}
	
	// ############ nur für volle befehlseingabe
	// affected devices und befehl
	
	if (document.getElementById('a11').value == 'FreeCmd')
	{
	// nur für freie befehlseingabe
	// alert('zweig nicht definiert');
	var cmdstring = document.getElementById('tra23end').value;
	configstart[12] ='#S .Device_Affected -> '+ document.getElementById('a11').value +'-AbsCmd1';
    var newcmdline = '#S .Device_Affected_Details -> '+ document.getElementById('a11').value +'-AbsCmd1'+'#[NF]undefined#[NF]cmd#[NF]'+cmdstring+'#[NF]#[NF]delay1#[NF]delay1#[NF]00:00:00#[NF]00:00:00#[NF]#[NF]#[NF]undefined#[NF]undefined#[NF]1#[NF]0#[NF]#[NF]0#[NF]0#[NF]1#[NF]0';
	configstart[29]=newcmdline;
	}
	else{
		
		
	// nur für definierte befehlseingabe
	configstart[12] ='#S .Device_Affected -> '+ document.getElementById('a11').value +'-AbsCmd1';
	// befehl aufteilen
	savedcmd = document.getElementById('tra33end').value;
	
	cmdarray= savedcmd.split(" ");
	if (cmdarray[1] != " "){
	secondstring = cmdarray[1];
	}
	if (cmdarray[2] != " "){
	secondstring = cmdarray[2];
	}
	
    var newcmdline = '#S .Device_Affected_Details -> '+ document.getElementById('a11').value +'-AbsCmd1'+'#[NF]'+cmdarray[0]+'#[NF]no_action#[NF]'+secondstring+'#[NF]#[NF]delay1#[NF]delay1#[NF]00:00:00#[NF]00:00:00#[NF]#[NF]#[NF]undefined#[NF]undefined#[NF]1#[NF]0#[NF]#[NF]0#[NF]0#[NF]1#[NF]0';
	
	configstart[29]=newcmdline;
		
	}

   // #########################################
	fillconfig('rawconfig')
	
	return;
}

function fillconfig(name){
	var showconf='';
	configstart[0] = '#V '+mVersion;
	conflines =  configstart.length ;
	for (i = 0; i < conflines; i++) 
		{
			showconf = showconf+configstart[i]+'\n';
		}
	document.getElementById(name).innerHTML = showconf;
	
}

function saveconfig(name,mode){
	
	if (mode == 'wizard'){
	makeconfig();
	}
	conf = document.getElementById(name).value;
	conf = conf.replace(/\n/g,'#[EOL]');
	conf = conf.replace(/:/g,'#c[dp]');
	conf = conf.replace(/;/g,'#c[se]');
	conf = conf.replace(/ /g,'#c[sp]');
	
	var nm = devicename;
	var def = nm+' saveconfig '+encodeURIComponent(conf);

	location = location.pathname+'?detail='+devicename+'&cmd=set '+addcsrf(def);
	return;
}

function getday(name){
	var addon = '<select id="'+name+'day">';
	addon += '<option value="">jeden Tag</option>';
	addon += '<option value="|$we">am Wochenende</option>';
	addon += '<option value="|!$we">an Wochentagen</option>';
	addon += '<option value="|1">Montag</option>';
	addon += '<option value="|2">Dienstag</option>';
	addon += '<option value="|3">Mitwoch</option>';
	addon += '<option value="|4">Donnerstag</option>';
	addon += '<option value="|5">Freitag</option>';
	addon += '<option value="|6">Samstag</option>';
	addon += '<option value="|7">Sonntag</option>';
	addon += '</select>';
	return addon;
}


function settimetyp(name){
	
	document.getElementById('typ1').style.display='none';
	document.getElementById('typ2').style.display='none';
	document.getElementById('typ3').style.display='none';

	if (name == 'typ0'){
		document.getElementById('help').innerHTML = 'Bitte die Zeit angeben, zu der das MSwitc-Device auslösen soll.<br>';	
		document.getElementById('help').innerHTML += 'Hier stehen mehrere Formate zur Verfügung<br>';
		document.getElementById('help').innerHTML += 'Bitte eine Vorauswahl treffen :<br>&nbsp;<br>';
		return;
		}
	
	document.getElementById('help').innerHTML = 'Bitte die gewünschten Zeiten angeben.';	
	document.getElementById(name).style.display='block';
	return;
	
}


function gettime(name){	
	var hour;
	for (i=0; i<24; i++)
				{
				change = ("00" + i).slice(-2);
				hour += '<option>'+change+'</option>';
				}
	var min;
	for (i=0; i<60; i++)
				{
				change=("00" + i).slice(-2);
				min += '<option>'+change+'</option>';
				}

	var sel1 = '<select id="'+name+'1">';
	sel1 += hour;
	sel1 += '</select>';
	sel1 += ':';
	sel1 += '<select id="'+name+'2">';
	sel1 += min;
	sel1 += '</select>';

return sel1;
}

function settime(){	
	typ = document.getElementById('timetyps').value;
	//alert(typ)
	var ret;
	if ( typ =='typ0'){
		return;
	}
	
	if ( typ =='typ1'){
		// exakte Zeitangabe
		hh = document.getElementById('normal1').value;
		mm = document.getElementById('normal2').value;
		// tag
		dd = document.getElementById('day1day').value;
		ret = '['+hh+':'+mm+dd+']';
		//alert(ret);
	}
	
	if ( typ =='typ2'){
		// exakte Zeitangabe
		// zeitpunkt 1
		hh = document.getElementById('zufall1').value;
		mm = document.getElementById('zufall2').value;
		// zeitpunkt 2
		hh1 = document.getElementById('zufall11').value;
		mm1 = document.getElementById('zufall12').value;
		//  tag
		dd1 = document.getElementById('zufal3day').value;
		ret = '[?'+hh+':'+mm+'-'+hh1+':'+mm1+dd1+']';
	}
	
	if ( typ =='typ3'){
		// exakte Zeitangabe
		// zeitpunkt 1
		hh = document.getElementById('periodic11').value;
		mm = document.getElementById('periodic12').value;
		// zeitpunkt 2
		hh1 = document.getElementById('periodic31').value;
		mm1 = document.getElementById('periodic32').value;
		//  tag
		dd1 = document.getElementById('periodic4day').value;
		// intrtvall
		intervallhh=document.getElementById('periodic1').value;
		intervallmm=document.getElementById('periodic2').value;

		ret = '['+intervallhh+':'+intervallmm+'*'+hh+':'+mm+'-'+hh1+':'+mm1+dd1+']';
	}

	settypptime(ret,'7step','2');
	return;
}

function createpart2(){

	eventmonitorstop();
	// hole geräteliste
	ret = devicelist('a1','a1','setaffected',1); 
	// hole befehlsliste dur gewähltes gerät
	
	line = '<table border = \'0\'><tr>';
	line += '<td>Teil 2 (auszuführende Aktion des MSwitch-Devices)';
	line += '<br>&nbsp;</td>';
	line += '<td></td>';
	line += '<td></td>';
	line += '</tr>';

	line +='<tr>';
	line +='<td>Welches Gerät soll geschaltet werden ?</td>';
	line +='<td>'+ret+'</td>';
	line +='<td><input id=\"a11\" type=\"text\" value=\"\" disabled=\"disabled\"></td>';
	line +='</tr>';
	line +='<tr id=\"tra2\">';
	line +='<td><div style=\"display:none\" id=\"tra21\">Auszuführender Befehl:</div></td>';
	line +='<td style=\" text-align: center; vertical-align: middle;\"><div style=\"display:none\" id=\"tra22\"><textarea id=\"freecmd\" cols=\"50\" name=\"TextArea1\" rows=\"4\"></textarea>';
	line +='<br><input type=\"button\" value=\"übernehmen\" onclick=\"javascript: setaffected(\'a2\',\'a2\',\'a2\'); \">';
	line +='</div></td>';
	line +='<td><div style=\"display:none\" id=\"tra23\"><input id=\"tra23end\" type=\"text\" value=\"\" disabled=\"disabled\"></div></td>';
	line +='</tr>';
	line +='<tr id=\"tra3\">';
	line +='<td><div style=\"display:none\" id=\"tra31\">Auszuführender Befehl:</div></td>';
	line +='<td><div style=\"display:none\" id=\"tra32\">';
	line +='<span id =\"setcmd\"></span>';
	line +='<span id=\"setcmd1\"></span>';
	line +='<span id=\"setcmd2\">test</span>';
	line +='</div></td>';
	line +='<td><div style=\"display:none\" id=\"tra33\"><input id=\"tra33end\" type=\"text\" value=\"\" disabled=\"disabled\"></div></td>';
	line +='</tr>';
	line += '</table>';
	document.getElementById('part2').innerHTML =line;
	document.getElementById('help').innerHTML = 'Bitte das zu schaltende Gerät in der Dropdownliste auswählen';	
		

}

function devicelist(id,name,script,flag){
	
	// erstelle geräteliste'+id+'+name+'
	ret = '<select id =\"'+id+'\" name=\"'+name+'\" onchange=\"javascript: '+script+'(this.value,id,name)\">';
	count =0;
	
	ret +='<option value=\"select\">bitte wählen:</option>';
	if (flag == '1'){
		ret +='<option value=\"free\">freie Befehlseingabe</option>';
	}
	
	for (i=count; i<len; i++)
		{
			
		if (flag == '1'){
			ret +='<option value='+i+'>'+devices[i]+'</option>';
			}
		else{
			
			ret +='<option value='+devices[i]+'>'+devices[i]+'</option>';
			}
		}
		
	ret +='</select>';
	return ret;
		
}

function setaffected(inhalt,id,name){
	
	if (inhalt == 'select'){
		document.getElementById('tra31').style.display='none';
		document.getElementById('tra32').style.display='none';
		document.getElementById('tra33').style.display='none';
		document.getElementById('tra21').style.display='none';
		document.getElementById('tra22').style.display='none';
		document.getElementById('tra23').style.display='none';
		return;
	}
	if (inhalt == 'free'){
		// wähle fenster 'freie eingabe'
		document.getElementById('tra31').style.display='none';
		document.getElementById('tra32').style.display='none';
		document.getElementById('tra33').style.display='none';
		document.getElementById('tra21').style.display='block';
		document.getElementById('tra22').style.display='block';
		document.getElementById('tra23').style.display='block';
		document.getElementById(id+'1').value='FreeCmd';
		return;
	}
	
	
	if (id == 'a1'){
		//schritt 1 deviceauswahl
		device  = devices[inhalt];
		document.getElementById(id+'1').value= device;
		seloptions = makecmdhash(cmds[inhalt]);
		document.getElementById('setcmd').innerHTML = 'set '+device+' ';
		document.getElementById('setcmd').innerHTML += seloptions;
		document.getElementById('setcmd1').innerHTML ='';
		out = '<input type=\"button\" value=\"übernehmen\" onclick=\"javascript: setaffected(\'a3\',\'a3\',\'a3\'); \">';
		document.getElementById('setcmd2').innerHTML =out;
		document.getElementById('tra31').style.display='block';
		document.getElementById('tra32').style.display='block';
		document.getElementById('tra33').style.display='block';
		document.getElementById('tra21').style.display='none';
		document.getElementById('tra22').style.display='none';
		document.getElementById('tra23').style.display='none';
		
		document.getElementById('help').innerHTML = 'Bitte auszuführenden Befehl eingeben und übernehmen drücken.';	
	}
	
	
	if (id == 'a2'){
		//übernahme der befehle aus schritt 2 - freie befehlseingabe
		comand1 = document.getElementById('freecmd').value;
		document.getElementById('help').innerHTML = 'Bitte auszuführenden Befehl eingeben und übernehmen drücken.';
		if (comand1 == ''){
			comand1='';
			FW_okDialog('Bitte Befehl eingeben');
			return;
			}

		comand1 = comand1.replace(/\n/g,';;');
	
		document.getElementById('tra23end').value=comand1;
		document.getElementById('tra33end').value='';
		document.getElementById('saveconf').style.backgroundColor='';
		document.getElementById('saveconf').disabled = false;
	}
	
	if (id == 'a3'){
	//übernahme der befehle aus schritt 3
	comand1='';
	comand2='';
	comand3='';
	device = document.getElementById('a11').value;
	comand1 = document.getElementById('comand').value;
	if (comand1 == '0'){
			comand1='';
			FW_okDialog('Bitte Befehl wählen');
			return;
			}

	if (document.getElementById('comand1')){
		comand2 = document.getElementById('comand1').value  ;
		if (comand2 == '0'){
			comand2='';
			FW_okDialog('Bitte Befehlszusatz wählen');
			return;
			}
	}
	
	if (document.getElementById('comand2')){
			//alert('test cmd2');
			comand3 = document.getElementById('comand2').value ; 
		}
	document.getElementById('tra23end').value='';
	document.getElementById('tra33end').value=comand1+' '+comand2+' '+comand3;
	
	document.getElementById('saveconf').style.backgroundColor='';
	document.getElementById('saveconf').disabled = false;
	}
	return;
}

function makecmdhash(line){
	document.getElementById('setcmd1').value='';	
	document.getElementById('setcmd2').value='';	
	
	if (line === undefined){
		return;
	}
	var retoption = '<select id =\"comand\" name=\"\" onchange=\"javascript: selectcmdoptions(this.value)\">';
	retoption +='<option selected value=\"0\">Befehl wählen</option>';
	
	sets = new Object();
	var cmdset = new Array;
	cmdset = line.split(" ");
	var anzahl = cmdset.length;
	
	for (i=0; i<anzahl; i++)
		{
		aktset = cmdset[i].split(":");	
		sets[aktset[0]]=aktset[1];
		if (aktset[0] != ""){
		retoption +='<option value='+aktset[0]+'>'+aktset[0]+'</option>';
			}
		}
	retoption +='</select>';
	var arraysetskeys = Object.keys(sets);
	return retoption;
}

function selectcmdoptions(inhalt){
	document.getElementById('setcmd1').innerHTML ='';
	// wenn undefined textfeld erzeugen
	if (sets[inhalt] == 'noArg'){ return;}
	// wenn noarg befehl übernehmen
	if (sets[inhalt] === undefined){ 
	
	retoption1 = '<input name=\"\" id=\"comand2\" type=\"text\" value=\"\">&nbsp;';
	document.getElementById('setcmd1').innerHTML = retoption1;
	return;
	}
	// wenn liste subcmd erzeugen

	var retoption1;
	retoption1 = '<select id =\"comand1\" name=\"\">';
	retoption1 +='<option selected value=\"0\">Option wählen</option>';
	
	var cmdset1= new Array;
	cmdset1= sets[inhalt].split(",");
	console.log(cmdset1);
	var anzahl = cmdset1.length;
	for (i=0; i<anzahl; i++)
		{
		retoption1 +='<option value='+cmdset1[i]+'>'+cmdset1[i]+'</option>';
		}
	retoption1 +='</select>';
	document.getElementById('setcmd1').innerHTML = retoption1;
}


function startconfig(){
	var html='<table><tr><td style=\"text-align: center; vertical-align: middle;\">';
	html+='<textarea id=\"rawconfig3\" style=\"width: 950px; height: 600px\"></textarea>';
	html+='</td>';
	html+='</tr>';
	html+='<tr><td style=\"text-align: center; vertical-align: middle;\">';
	html+='<input name=\"saveconf\" id=\"saveconf\" type=\"button\" value=\"Konfiguration speichern\" onclick=\"javascript: saveconfig(\'rawconfig3\')\"\">';
	html+='</td>';
	html+='</tr>';
	html+='</table>';
	document.getElementById('importCONFIG').innerHTML = html;
	document.getElementById('help').innerHTML = 'Hier können MSwitch_Konfigurationsdateien eingespielt werden. Dieses sollte nur von erfahrenen Usern genutzt werden. Es findet keine Prüfung auf Fehler statt und fehlerhafte Dateien können Fhem zum Absturz bringen.<br>Die vorgegebene Datei entspricht einem unkonfigurierten MSwitch';
	fillconfig('rawconfig3');
	return;
}


function startimportat(){
	script = 'setat';
	ret = '<select id =\"\" name=\"\" onchange=\"javascript: '+script+'(this.value)\">';
	ret +='<option value=\"empty\">bitte zu importierendes AT wählen</option>';
	
	count =0;

	var len = at.length;
	for (i=count; i<len; i++)
		{
			ret +='<option value='+i+'>'+at[i]+'</option>';
		}
		 
	ret +='</select>';
	
	var html='';
	html+='<table border=\"0\">';
	html+='<tr><td style=\"vertical-align: top;\">';
	html+='<table border=\"0\">';
	html+='<tr><td colspan=\"3\">';
	html+='';
	html+='</td></tr>';
	html+='<tr><td style=\"text-align: center;\">';
	html+=ret;
	html+='<br><br><input disabled name=\"\" id=\"sat\" type=\"button\" value=\"importiere dieses AT\" onclick=\"javascript: saveat()\"\">';
	html+='</td>';
	html+='<td>';
	html+='Definition:<br>';
	html+='Comand:<br>';
	html+='Timespec:<br>';
	html+='Steuerflag:<br>';
	html+='Triggertime:<br>';
	html+='</td>';
	html+='<td>';
	html+='<input id=\"def\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"defcmd\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"deftspec\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"defflag\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"trigtime\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='</td>';
	html+='</tr>';
	html+='<tr><td colspan=\"3\" style=\"text-align: center; vertical-align: middle;\">';
	html+='</td>';
	html+='</tr>';
	html+='</table>';
	html+='</td>';
	html+='<td>';
	html+='<textarea disabled id=\'rawconfig1\' style=\'width: 450px; height: 600px\'></textarea>';
	html+='</td>';
	html+='</tr>';
	html+='</table>';
	

	document.getElementById('help').innerHTML = 'Es können nur periodisch wiederkehrende ATs importiert werden und nur diese werden zur Auswahl angeboten. Mswitch ist für einmalige Ats ungeeignet. Bei importiertem At berücksichtigt MSwitch keine Sekundenangaben.<br>Es ist darauf zu achten , das nach dem Import sowohl das AT, als auch das MSwitch aktiv sind und eines der beiden deaktiviert werden sollte.';
	document.getElementById('importAT').innerHTML = html;
	document.getElementById('sat').style.backgroundColor='#ff0000';
	fillconfig('rawconfig1');
	return;
}


function setat(name){
	if (name == "empty"){
		document.getElementById('sat').disabled = true;
		document.getElementById('def').value='';
		document.getElementById('defcmd').value='';
		document.getElementById('deftspec').value='';
		document.getElementById('defflag').value='';
		document.getElementById('trigtime').value='';
		document.getElementById('sat').style.backgroundColor='#ff0000';
		return;
	}
	document.getElementById('sat').style.backgroundColor='';
	document.getElementById('sat').disabled = false;
	document.getElementById('def').value=atdef[name];
	document.getElementById('defcmd').value=atcmd[name];
	document.getElementById('deftspec').value=atspec[name];
	defflag = atdef[name].substr(0,1);
	document.getElementById('defflag').value=defflag;
	document.getElementById('trigtime').value=triggertime[name];
	return;
}


function saveat(){

	var cmdstring = document.getElementById('defcmd').value;
	configstart[12] ='#S .Device_Affected -> FreeCmd-AbsCmd1';
    var newcmdline = '#S .Device_Affected_Details -> FreeCmd-AbsCmd1'+'#[NF]undefined#[NF]cmd#[NF]'+cmdstring+'#[NF]#[NF]delay1#[NF]delay1#[NF]00:00:00#[NF]00:00:00#[NF]#[NF]#[NF]undefined#[NF]undefined#[NF]1#[NF]0#[NF]#[NF]0#[NF]0#[NF]1#[NF]0';

	configstart[29]=newcmdline;
	
	if (document.getElementById('defflag').value == "*")
	{
		string = document.getElementById('deftspec').value;
		// ersetze dp durch #[dp]
		string ="["+string+"]";
		string = string.replace(/:/gi,"#[dp]");
		configstart[13] ='#S .Trigger_time -> on~off~ononly'+ string +'~offonly~onoffonly';
	}
	

	if (document.getElementById('defflag').value == "+")
	{
		string = document.getElementById('deftspec').value;
		// ersetze dp durch #[dp]
		string = '['+string+'*00:01-23:59]';
		string = string.replace(/:/gi,"#[dp]");
		configstart[13] ='#S .Trigger_time -> on~off~ononly'+ string +'~offonly~onoffonly';
	}
	
	fillconfig('rawconfig1');
	saveconfig('rawconfig1');
	return;
}


function startimportnotify(){
	script = 'setnotify';
	ret = '<select id =\"\" name=\"\" onchange=\"javascript: '+script+'(this.value)\">';
	ret +='<option value=\"empty\">bitte zu importierendes NOTIFY wählen</option>';
	count =0;
	len = notify.length;
	for (i=count; i<len; i++)
		{

			ret +='<option value='+i+'>'+notify[i]+'</option>';
			
		}
		
	ret +='</select>';
	
	var html='';
	html+='<table border=\"0\">';
	html+='<tr><td style=\"vertical-align: top;\">';
	html+='<table border=\"0\">';
	html+='<tr><td colspan=\"3\">';
	html+='</td></tr>';
	html+='<tr><td style=\"text-align: center;\">';
	html+=ret;
	html+='<br><br><input disabled name=\"\" id=\"not\" type=\"button\" value=\"import this NOTIFY\" onclick=\"javascript: savenot()\"\">';

	html+='</td>';
	html+='<td>';
	html+='Definition:<br>';
	html+='Comand:<br>';
	html+='Trigger-Device:<br>';
	html+='Trigger-Event:<br>';
	html+='</td>';
	html+='<td>';
	html+='<input id=\"defnotify\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"comandnotify\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"trigdev\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='<input id=\"trigevent\" type=\"text\" value=\"\" disabled=\"\" style=\"width:400pt;\"><br>';
	html+='</td>';
	html+='</tr>';
	html+='<tr><td colspan=\"3\" style=\"text-align: center; vertical-align: middle;\">';
	html+='</td>';
	html+='</tr>';
	html+='</table>';
	html+='</td>';
	html+='<td>';
	html+='<textarea disabled id=\'rawconfig2\' style=\'width: 450px; height: 600px\'></textarea>';
	html+='</td>';
	html+='</tr>';
	html+='</table>';

	document.getElementById('help').innerHTML = 'Es ist darauf zu achten, das nach dem Import sowohl das Notify, als auch das MSwitch aktiv sind und eines der beiden deaktiviert werden sollte.';
	document.getElementById('importNOTIFY').innerHTML = html;
	document.getElementById('not').style.backgroundColor='#ff0000';
	fillconfig('rawconfig2');
	return;
	
}

function setnotify(name){
	
	if (name == "empty"){
		document.getElementById('not').disabled = true;
		document.getElementById('not').style.backgroundColor='#ff0000';
		document.getElementById('defnotify').value='';
		document.getElementById('comandnotify').value='';
		document.getElementById('trigdev').value='';
		document.getElementById('trigevent').value='';
		return;
		}
	
	document.getElementById('not').style.backgroundColor='';
	document.getElementById('not').disabled = false;
	document.getElementById('defnotify').value=notifydef[name];
	var first =  notifydef[name].indexOf(" ");
	var laenge = notifydef[name].length;
	var cmd = notifydef[name].substring(first+1,laenge);
	document.getElementById('comandnotify').value=cmd;
	var trigger = notifydef[name].substring(0,first);
	var tlaenge = trigger.length;
	var trenner =  trigger.indexOf(":");
	var tdevice = notifydef[name].substring(0,trenner);
	document.getElementById('trigdev').value=tdevice;
	var tevent = notifydef[name].substring(trenner+1,tlaenge);
	document.getElementById('trigevent').value=tevent;
	return;	
}


function savenot(){
	var cmdstring = document.getElementById('comandnotify').value;
	configstart[12] ='#S .Device_Affected -> FreeCmd-AbsCmd1';
    var newcmdline = '#S .Device_Affected_Details -> FreeCmd-AbsCmd1'+'#[NF]undefined#[NF]cmd#[NF]'+cmdstring+'#[NF]#[NF]delay1#[NF]delay1#[NF]00:00:00#[NF]00:00:00#[NF]#[NF]#[NF]undefined#[NF]undefined#[NF]1#[NF]0#[NF]#[NF]0#[NF]0#[NF]1#[NF]0';
	configstart[29]=newcmdline;
	configstart[5] ='#S Trigger_device -> '+ document.getElementById('trigdev').value;
	configstart[8] ='#S .Trigger_cmd_on -> '+ document.getElementById('trigevent').value;
	fillconfig('rawconfig2');
	saveconfig('rawconfig2');
	return;
}

function startimportpreconf(){
	preconfparts = preconf.split("#-NEXT-");
	var anzahl = preconfparts.length;
	var count =0;
	for (i=count; i<anzahl; i++)
		{
		treffer = preconfparts[i].match(/#NAME.(.*?)(#\[NEWL\])/);
		help = preconfparts[i].match(/#HELP.(.*?)(#\[NEWL\])/);
		preconfparts[i] = (preconfparts[i].split(treffer[0]).join(''));
		preconfparts[i] = (preconfparts[i].split(help[0]).join(''));
		preconfparts[i] = preconfparts[i].replace(/#\[NEWL\]/gi,"\n");
		preconfpartsname.push(treffer[1]);
		preconfpartshelp.push(help[1]); 
		}
	script = 'setpreconf';
	ret = '<select id =\"\" name=\"\" onchange=\"javascript: '+script+'(this.value)\">';
	ret +='<option value=\"empty\">bitte Device wählen</option>';
	count =0;
	for (i=count; i<anzahl; i++)
		{
			ret +='<option value='+i+'>'+preconfpartsname[i]+'</option>';
		}
	ret +='</select>';
	
	var html='';
	html+='<table width=\"100%\" border=\"0\">';
	html+='<tr>';
	html+='<td width=\"100%\" style=\"vertical-align: top;\">';
	html+='';
	html+='<table width = \"100%\" border=\"0\">';
	
	html+='<tr>';
	html+='<td style=\"text-align: center; vertical-align: middle;\">';
	html+=ret;
	html+='<br><br><input disabled name=\"\" id=\"prec\" type=\"button\" value=\"importiere dieses MSwitch\" onclick=\"javascript: savepreconf()\"\">';
	html+='</td>';
	html+='</tr>';
	
	html+='<tr>';
	html+='<td id=\"infotext\" style=\"text-align: center; vertical-align: middle;\">';
	html+='&nbsp;';
	html+='</td>';
	html+='</tr>';
	
	html+='<tr>';
	html+='<td height=300 id=\"infotext1\" style=\"text-align: center;vertical-align: top;\">';
	html+='';
	html+='</td>';
	html+='</tr>';
	
	html+='<tr>';
	html+='<td id=\"infotext2\" style=\"text-align: center; vertical-align: middle;\">';
	//html+='<input disabled name=\"\" id=\"prec\" type=\"button\" value=\"importiere dieses MSwitch\" onclick=\"javascript: savepreconf()\"\">';
	html+='</td>';
	html+='</tr>';

	html+='</table>';

	html+='</td>';
	html+='<td>';
	html+='<textarea disabled id=\"rawconfig4\" style=\"width: 400px; height: 400px\"></textarea>';
	html+='</td>';
	
	html+='</tr>';
	html+='</table>';
	
	document.getElementById('help').innerHTML = 'Hier können vorkonfigurierte Mswitch-Devices importiert werden. Bei diesen müssen in der Regel keine weiteren Einstellungen mehr vorgenommen werden. Falls doch Änderungen notwendig sind wird im Device darauf hingewiesen.';
	document.getElementById('importPRECONF').innerHTML = html;
	document.getElementById('prec').style.backgroundColor='#ff0000';
	return;
}

function setpreconf(name){
	if (name == "empty"){
		document.getElementById('rawconfig4').innerHTML = "";
		
		document.getElementById('prec').disabled = true;
		document.getElementById('prec').style.backgroundColor='#ff0000';
		return;
	}
	document.getElementById('rawconfig4').innerHTML = preconfparts[name];
	document.getElementById('infotext1').innerHTML = preconfpartshelp[name];
	document.getElementById('prec').disabled = false;
	document.getElementById('prec').style.backgroundColor='';
}

function savepreconf(name){
	mode = 'preconf';
	saveconfig('rawconfig4',mode);
	return;
}