// MSwitch_Web.js
// Autor:Byte09
// #########################

	var version = '1.0';
	var info = '';
	var debug ='off';
	
//####################################################################################################

	var globaldetails2 = 'start';
	var globallock='';
	var t=$("#MSwitchWebTR"), ip=$(t).attr("ip"), ts=$(t).attr("ts");
	FW_replaceWidget("[name=aw_ts]", "aw_ts", ["time"], "12:00");
	$("[name=aw_ts] input[type=text]").attr("id", "aw_ts");  
	
	var randomdev=[];
	
	
	var globalaffected;
	var auswfirst=document.getElementById('devices');

function teststart(){
// alle startfunktionen ausführen 
if (debug == 'on'){ alert(devicename+' Debug MSwitchweb an') };

	var r1 = $('<input type="button" value="'+RENAMEBUTTON+'" onclick=" javascript: newname() "/>');
	var r2 = $('<input type="button" value="'+RELOADBUTTON+'" onclick=" javascript: reload() \"/>');
	var r3 = $('<input type="text" id = "newname" value="'+devicename+'"/>');
	$( ".col1" ).text( "" );
	$(r3).appendTo('.col1');
	$(r2).appendTo('.col1');
	$(r1).appendTo('.col1');
	
	// next teste auf quickedit an
	if (QUICKEDIT == '0'){
	$("#devices").prop("disabled", false);
	document.getElementById('aw_great').value='schow greater list';
	document.getElementById('lockedit').checked = false  ;
	}
	
// EXEC1   ##################################################
	
	if (EXEC1 == '1'){
	//alert('aus java '+EXEC1);
	if (debug == 'on'){ alert('EXEC1') };	
	var affected = document.getElementById('affected').value ;
	var devices = affected.split(",");
	var i;
	var len = devices.length;
	for (i=0; i<len; i++)
		{
		testname = devices[i].split("-");
		if (testname[0] == "FreeCmd") 
			{
			continue;
			}
		sel = devices[i] + '_on';
		sel1 = devices[i] + '_on_sel';
		sel2 = 'cmdonopt' +  devices[i] + '1';
		sel3 = 'cmdseton' +  devices[i];
		aktcmd = document.getElementById(sel).value;
		aktset = document.getElementById(sel3).value;
		
		if (debug == 'on1')
		{ 
			alert('document: '+document.getElementById(sel).value+'\n sel: '+sel1+'\n aktset: '+aktset+'\n sel12: '+sel2) 
		}
		
		
		activate(document.getElementById(sel).value,sel1,aktset,sel2);
		sel = devices[i] + '_off';
		sel1 = devices[i] + '_off_sel';
		sel2 = 'cmdoffopt' +  devices[i] + '1';
		sel3 = 'cmdsetoff' +  devices[i];
		aktcmd = document.getElementById(sel).value;
		aktset = document.getElementById(sel3).value;
		
		if (debug == 'on1')
		{ 
			alert(document.getElementById(sel).value+' '+sel1+' '+aktset+' '+sel2) 
		}
		
		
		activate(document.getElementById(sel).value,sel1,aktset,sel2); 
		}
	}
	
// EXEC2   ##################################################
	
	var olddest;
	// init reaktion auf auf Änderungen der INFORMID
	$("body").on('DOMSubtreeModified', "div[informId|='"+devicename+"-Debug']", function() {
	if (debug == 'on'){ alert('EXEC2') };	
	var test = $( "div[informId|='"+devicename+"-Debug']" ).text();
	test= test.substring(0, test.length - 19);
	var old = document.getElementById("log").value;
	if (olddest != test)
		{
		olddest = test;
		document.getElementById("log").value=old+'\n'+test;
		var textarea = document.getElementById('log');
		textarea.scrollTop = textarea.scrollHeight;
		}
	return;
	})
	

	var x = document.getElementsByClassName('randomidclass');
    for (var i = 0; i < x.length; i++) 
		{
		var t  = x[i].id;
		randomdev.push(t);
		} 
	
	
	// --------------------
	
	globaldetails2='undefined';
	
	
	var x = document.getElementsByClassName('devdetails2');
    for (var i = 0; i < x.length; i++) 
	{
    var t  = x[i].id;
	globaldetails2 +=document.getElementById(t).value;
	}

	var globaldetails='undefined';
	var x = document.getElementsByClassName('devdetails');
    for (var i = 0; i < x.length; i++) 
	{
    var t  = x[i].id;
	globaldetails +=document.getElementById(t).value;
	
	document.getElementById(t).onchange = function() 
	{
	//alert('changed');
	var changedetails;
	var y = document.getElementsByClassName('devdetails');
    for (var i = 0; i < y.length; i++) 
	{
    var t  = y[i].id;
	changedetails +=document.getElementById(t).value;
	}
	if( changedetails != globaldetails)
		{
		globallock =' unsaved device actions';
		[ "aw_trig","aw_md1","aw_md2","aw_addevent","aw_dev"].forEach (lock,);
		randomdev.forEach (lock);
		}
	if( changedetails == globaldetails)
		{
		[ "aw_trig","aw_md1","aw_md2","aw_addevent","aw_dev"].forEach (unlock,);
			randomdev.forEach (unlock);
		}
	}

	}
	

// next   ##################################################
	

if ( DEVICETYP != 'dummy')
{
	var triggerdetails = document.getElementById('MSwitchWebTRDT').innerHTML;
	var saveddevice = TRIGGERDEVICEHTML;
	var sel = document.getElementById('trigdev');
	sel.onchange = function() 
	{
	trigdev = this.value;
	if (trigdev != TRIGGERDEVICEHTML)
		{
		globallock =' unsaved trigger';
		["aw_dev", "aw_det"].forEach (lock);
		randomdev.forEach (lock,);
		}
	else
		{	
		["aw_dev", "aw_det"].forEach (unlock);
		randomdev.forEach (unlock);
		document.getElementById('MSwitchWebTRDT').innerHTML = triggerdetails;	
		}
	
	if (trigdev == 'all_events')
		{
		document.getElementById("triggerwhitelist").style.visibility = "visible"; 
		}
	else
		{
		document.getElementById("triggerwhitelist").style.visibility = "collapse"; 
		}
	}

}

// next   ##################################################


if (document.getElementById('trigon'))
{
	var trigonfirst = document.getElementById('trigon').value;
	var sel2 = document.getElementById('trigon');
	sel2.onchange = function() 
		{
		if (trigonfirst != document.getElementById('trigon').value)
			{
			closetrigger();
			}
			else{
			opentrigger();
			}
		}
	}
	
	if (document.getElementById('trigoff')){
	var trigofffirst = document.getElementById('trigoff').value;
	var sel3 = document.getElementById('trigoff');
	sel3.onchange = function() 
		{
		if (trigofffirst != document.getElementById('trigoff').value)
			{
			closetrigger();
			}
			else{
			opentrigger();
			}
		}
	}
	
	if (document.getElementById('trigcmdoff')){
	var trigcmdofffirst = document.getElementById('trigcmdoff').value;
	var sel4 = document.getElementById('trigcmdoff');
	sel4.onchange = function() 
		{
		if (trigcmdofffirst != document.getElementById('trigcmdoff').value)
			{
			closetrigger();
			}
			else{
			opentrigger();
			}
		}
	}
	
if (document.getElementById('trigcmdon'))
	{
		var trigcmdonfirst = document.getElementById('trigcmdon').value;
		var sel5 = document.getElementById('trigcmdon');
		sel5.onchange = function() 
		{
		if (trigcmdonfirst != document.getElementById('trigcmdon').value)
				{
				closetrigger();
				}
			else
				{
				opentrigger();
				}
		}
	}


// next   ##################################################


	// eventmonitor
	var o = new Object();
	var atriwaaray = new Object();
	var atriwaaray = { SCRIPTTRIGGERS };

	// init reaktion auf Änderungen der INFORMID
	$("body").on('DOMSubtreeModified', "div[informId|='"+devicename+"-EVENT']", function() {
	
	// abbruch wenn checkbox nicht aktiv
	
	var check = $("[name=eventmonitor]").prop("checked") ? "1":"0";
	if (check == 0)
		{
		$( "#log2" ).text( "" );
		$( "#log1" ).text( "" );
		$( "#log3" ).text( "" );
		return;
		}

	// neustes event aus html extrahieren
	var test = $( "div[informId|='"+devicename+"-EVENT']" ).text();
 
	// datum entfernen
	test= test.substring(0, test.length - 19);
	o[test] = test;

	// löschen der anzeige
	
	$( "#log2" ).text( "" );
	$( "#log1" ).text( "eingehende events:" );
	$( "#log3" ).text( "" );
	 
	var field = $('<select style="width: 30em;" size="5" id ="lf" multiple="multiple" name="lf" size="6"  ></select>');
	
	$(field).appendTo('#log2');
	
	var field = $('<input id ="editevent" type="button" value="'+editevent+'"/>');   // !!!!! #######
	
	$(field).appendTo('#log3');
	$("#editevent").click(function(){
	transferevent();
	return;
	});

	// umwandlung des objekts in standartarray
	var a3 = Object.keys(o).map(function (k) { return o[k];})
 
	// array umdrehen
	a3.reverse();
  
	// eintrag in dropdown
	if (atriwaaray[test] != 1)
		{
		atriwaaray[test]=1;
		var newselect = $('<option value="'+test+'">'+test+'</option>');
		$(newselect).appendTo('#trigcmdon');
		var newselect = $('<option value="'+test+'">'+test+'</option>');
		$(newselect).appendTo('#trigcmdoff');
		var newselect = $('<option value="'+test+'">'+test+'</option>');
		$(newselect).appendTo('#trigon');
		var newselect = $('<option value="'+test+'">'+test+'</option>');
		$(newselect).appendTo('#trigoff');
		}
  
	// aktualisierung der divx max 5
	var i;
	for (i = 0; i < 10; i++) 
		{
		if (a3[i])
			{
			var newselect = $('<option value="'+a3[i]+'">'+a3[i]+'</option>');
			$(newselect).appendTo('#lf'); 
			}
		}  

});

// next   ##################################################
	
	
	
	
	if (HASHINIT != 'define')
	{
		
		for (i=0; i<auswfirst.options.length; i++)
			{
			var pos=auswfirst.options[i];
				if(pos.selected)
				{
				//alert (pos.value);
				globalaffected +=pos.value;
				}
			}
		//alert (globalaffected);
		 var sel1 = document.getElementById('devices');
			
			if (UNLOCK == '1')
			{
				globallock =' this device is locked !';
				[ "aw_dev","aw_det","aw_trig","aw_md","aw_md1","aw_md2","aw_addevent"].forEach (lock,);
				randomdev.forEach (lock);
			}
			
			if (UNLOCK == '2')
			{
				globallock =' only trigger is changeable';
				[ "aw_dev","aw_det","aw_md","aw_md1","aw_md2","aw_addevent"].forEach (lock,);
				randomdev.forEach (lock);
			}
			
		sel1.onchange = function() 
		{
			var actaffected;
			var auswfirst=document.getElementById('devices');
			for (i=0; i<auswfirst.options.length; i++)
				{
				var pos=auswfirst.options[i];
				if(pos.selected)
					{
					//alert (pos.value);
					actaffected +=pos.value;
					}
				}

			if (actaffected != globalaffected)
				{
				globallock =' unsaved affected device';
				[ "aw_det","aw_trig","aw_md","aw_md1","aw_md2","aw_addevent"].forEach (lock,);
				randomdev.forEach (lock);
				}
			else
				{
				[ "aw_det","aw_trig","aw_md","aw_md1","aw_md2","aw_addevent"].forEach (unlock,);
				randomdev.forEach (unlock);
				}
		}	 
	}
	
	
return;
} // ende startfunktionen


//#####################################################################################################



function noarg(target,copytofield){
	if (debug == 'on'){ alert('noarg') };
	document.getElementById(copytofield).value = '';
	document.getElementById(target).innerHTML = '';
	return;
	}



function noaction(target,copytofield){
	if (debug == 'on'){ alert('noaction') };
	document.getElementById(copytofield).value = '';
	document.getElementById(target).innerHTML = '';
	return;}

 function slider(first,step,last,target,copytofield){
	if (debug == 'on'){ alert('slider') };
	var selected =document.getElementById(copytofield).value;
	var selectfield = "<input type='text' id='" + target +"_opt' size='3' value='' readonly>&nbsp;&nbsp;&nbsp;" + first +"<input type='range' min='" + first +"' max='" + last + "' value='" + selected +"' step='" + step + "' onchange=\"javascript: showValue(this.value,'" + copytofield + "','" + target + "')\">" + last  ;
	document.getElementById(target).innerHTML = selectfield + '<br>';
	var opt = target + '_opt';
	document.getElementById(opt).value=selected;
	return;
	}  

function textfield(copytofield,target)
	{
	if (debug == 'on'){ alert('textfield') };
		var selected =document.getElementById(copytofield).value;
		if (copytofield.indexOf('cmdonopt') != -1) {
		var selectfield = "<input type='text' size='30' value='" + selected +"' onchange=\"javascript: showtextfield(this.value,'" + copytofield + "','" + target + "')\">"  ;
		document.getElementById(target).innerHTML = selectfield + '<br>';	
		}
		else{
		var selectfield = "<input type='text' size='30' value='" + selected +"' onchange=\"javascript: showtextfield(this.value,'" + copytofield + "','" + target + "')\">"  ;
		document.getElementById(target).innerHTML = selectfield + '<br>';
		}
		return;
	}

function selectfield(args,target,copytofield){
	if (debug == 'on'){ alert('selectfield') };
	var cmdsatz = args.split(",");
	var selectstart = "<select id=\"" +target +"1\" name=\"" +target +"1\" onchange=\"javascript: aktvalue('" + copytofield + "',document.getElementById('" +target +"1').value)\">"; 
	var selectend = '<\select>';
	var option ='<option value="noArg">noArg</option>'; 
	var i;
	var len = cmdsatz.length;
	var selected =document.getElementById(copytofield).value;
	for (i=0; i<len; i++){
	if (selected == cmdsatz[i]){
	option +=  '<option selected value="' + cmdsatz[i] + '">' + cmdsatz[i] + '</option>';
	}
	else{
	option +=  '<option value="' + cmdsatz[i] + '">' + cmdsatz[i] + '</option>';
	}
	}
	var selectfield = selectstart + option + selectend;
	document.getElementById(target).innerHTML = selectfield + '<br>';	
	return;
	}
	
	

	function activate(state,target,options,copytofield) ////aufruf durch selctfield
	{
	if (debug == 'on'){ alert('activate') };
	debug = 'state: '+state+'<br>';
	debug += 'target: '+target+'<br>';
	debug += 'options: '+options+'<br>';
	debug += 'copytofield: '+copytofield+'<br>';
	var globaldetails3='undefined';
	var x = document.getElementsByClassName('devdetails2');
    for (var i = 0; i < x.length; i++) 
		{
		var t  = x[i].id;
		globaldetails3 +=document.getElementById(t).value;
		}
	if ( globaldetails2 && globaldetails2 != 'start')
		{
		if (globaldetails3 != globaldetails2)
			{
			globallock =' unsaved device actions';
				[ "aw_trig","aw_md1","aw_md2","aw_addevent","aw_dev"].forEach (lock,);
				randomdev.forEach (lock);
			}
		else
			{
			[ "aw_trig","aw_md1","aw_md2","aw_addevent","aw_dev"].forEach (unlock,);
					randomdev.forEach (unlock);
			}
		}
	if (state == 'no_action')
		{
		return;
		}
	var optionarray = options.split(" ");
	var werte = new Array();
	for (var key in optionarray )
	{
		var satz = optionarray[key].split(":");
		var wert1 = satz[0];
		wert3 = satz[1];
		satz.shift() ;
		var wert2 = satz.join(":");
		werte[wert1] = wert2;
	}
	var devicecmd = new Array();
	if ( werte[state] == '') 
		{
		werte[state]='textField';
		}	
	devicecmd = werte[state].split(",");
	if (devicecmd[0] == 'noArg')
		{
		noarg(target,copytofield);
		return;
		}
	else if (devicecmd[0] == 'slider'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'undefined'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'textField'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'colorpicker'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'RGB'){textfield(copytofield,target);return;}
	else if (devicecmd[0] == 'no_Action'){noaction();return;}
	else {selectfield(werte[state],target,copytofield);return;}
	alert('beende activate');
	return;
	}
	
	
	
	
	
	
	
	
	
	
	

function testcmd(field,devicename,opt){
if (debug == 'on'){ alert('testcmd') };
	comand = $("[name="+field+"]").val();
 	if (comand == 'no_action')
		{
		return;
		}
	comand1 = $("[name="+opt+"]").val()
	if (devicename != 'FreeCmd')
		{
		comand =comand+" "+comand1;
		}
	comand = comand.replace(/$SELF/g, devicename); // !!!!
	alert(comand);
	if (devicename != 'FreeCmd')
		{
		cmd ='set '+devicename+' '+comand;
		FW_cmd(FW_root+'?cmd='+encodeURIComponent(cmd)+'&XHR=1');
		FW_okDialog(EXECCMD+' '+cmd); // !!!
		FW_errmsg(cmd, 5);
		} 
	 else
		{
			comand = comand.replace(/;;/g,'[DS]');
			comand = comand.replace(/;/g,';;');
			comand = comand.replace(/\\[DS\\]/g,';;');
			var t0 = comand.substr(0, 1);
			var t1 = comand.substr(comand.length-1,1 );
			if (t1 == ' ')
				{
				var space = '".$NOSPACE."'; // !!!
				var textfinal = "<div style ='font-size: medium;'>"+space+"</div>";
				FW_okDialog(textfinal);
				return;
				}
			
			if (t0 == '{' && t1 == '}') 
				{
				}
			else
				{
				comand = '{fhem("'+comand+'")}';
				}
			
			cmd = comand;
			FW_cmd(FW_root+'?cmd='+encodeURIComponent(cmd)+'&XHR=1');
			FW_okDialog('".$EXECCMD." '+cmd);
		} 
	}



function  switchlock()
{	
	if (debug == 'on'){ alert('switchlock') };
	test = document.getElementById('lockedit').checked ;	
	if (test)
		{
		$("#devices").prop("disabled", 'disabled');
			if (LANGUAGE == 'DE')
				{
				document.getElementById('aw_great').value='Liste editieren';
				}
			else
				{
				document.getElementById('aw_great').value='edit list';
				}
		}
	else
		{
		$("#devices").prop("disabled", false);
			if (LANGUAGE == 'DE')
				{
				document.getElementById('aw_great').value='öffne grosse Liste';
				}
			else
				{
				document.getElementById('aw_great').value='schow greater list';
				}
		}
}
	

function closetrigger(){
			globallock =' unsaved trigger details';
			["aw_dev", "aw_det","aw_trig","aw_md1","aw_md2","aw_addevent"].forEach (lock,);
			randomdev.forEach (lock);
	}
	
function opentrigger(){
			[ "aw_dev","aw_det","aw_trig","aw_md1","aw_md2","aw_addevent"].forEach (unlock,);
			randomdev.forEach (unlock);
	}


function reload(){
if (debug == 'on'){ alert('reload') }
	window.location.href="/fhem?detail="+devicename;
	}

 function newname(){
if (debug == 'on'){ alert('newname') }
	newname = document.getElementById('newname').value;
	comand = 'rename+Timer1+'+newname;
	cmd = comand;
	if (devicename == newname){return;}
	if (newname == ''){return;}
	window.location.href="/fhem?cmd=rename "+devicename+" "+newname+"&detail="+newname+""+CSRF;
	} 
	

function lock(elem, text){
if (debug == 'on'){ alert('lock') }
	if (document.getElementById(elem)){
	document.getElementById(elem).style.backgroundColor = "#ADADAD";
	document.getElementById(elem).disabled = true;
	if (!document.getElementById(elem).model)
	{
	document.getElementById(elem).model=document.getElementById(elem).value;
	}
	document.getElementById(elem).value = 'N/A'+globallock;
	}
	}

function unlock(elem, index){
if (debug == 'on'){ alert('unlock') }

//alert('unlock: '+elem+' --- '+index) ;

	if (document.getElementById(elem)){
	
	//alert(elem+' '+document.getElementById(elem).model);
		
	document.getElementById(elem).style.backgroundColor = "";
	document.getElementById(elem).disabled = false;
	document.getElementById(elem).value=document.getElementById(elem).model;
	}
}
	
function saveconfig(conf){
	if (debug == 'on'){ alert('saveconfig') };
	conf = conf.replace(/\n/g,'#[EOL]'); // !!!
	conf = conf.replace(/:/g,'#c[dp]');
	conf = conf.replace(/;/g,'#c[se]');
	conf = conf.replace(/ /g,'#c[sp]');
	var nm = $(t).attr("nm");
	var  def = nm+" saveconfig "+encodeURIComponent(conf);
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}

 
function vupdate(){
	if (debug == 'on'){ alert('vupdate') };
    conf='';
	var nm = $(t).attr("nm");
	var  def = nm+" VUpdate "+encodeURIComponent(conf);
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}



// Fenster für Schaltbedingungen	
function bigwindow(targetid){
if (debug == 'on'){ alert('bigwindow') };
	targetval =document.getElementById(targetid).value;
	sel ='<div style="white-space:nowrap;"><br>';
	sel = sel+'<textarea id="valtrans" cols="80" name="TextArea1" rows="10" onChange=" document.getElementById(\''+targetid+'\').value=this.value; ">'+targetval+'</textarea>';
	sel = sel+'</div>';
	FW_okDialog(sel,''); 
	}	

// Deviceauswahl
function  deviceselect(){
if (debug == 'on'){ alert('deviceselect') };
	sel ='<div style="white-space:nowrap;"><br>';
	var ausw=document.getElementById('devices');
	for (i=0; i<ausw.options.length; i++)
		{
		var pos=ausw.options[i];
			if(pos.selected)
			{
			sel = sel+'<input id ="Checkbox-'+i+'" checked="checked" name="Checkbox-'+i+'" type="checkbox" value="test" /> '+pos.value+'<br />';
			}
			else 
			{
			sel = sel+'<input id ="Checkbox-'+i+'" name="Checkbox-'+i+'" type="checkbox" /> '+pos.value+'<br />';
			}
		} 
	sel = sel+'</div>';
	FW_okDialog(sel,'',removeFn) ; 
	}
	 
	 
 		 
// lösche log
function deletelog() {
if (debug == 'on'){ alert('deletelog') };
	anzahl =document.getElementById('dellog').value;
	arg ='';
	for (i = 1; i <  anzahl; i++) {
	test = document.getElementById('Checkbox-' + i).checked;
	if (document.getElementById('Checkbox-' + i).checked)
	{
	arg=arg+i+',';
	}
	}
	conf=arg;
	var nm = $(t).attr("nm");
	var  def = nm+" deletesinglelog "+encodeURIComponent(conf);
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	return;
	}
	
	
// löscht vergösserte Fenster
function removeFn() {
if (debug == 'on'){ alert('removefn') };
    var targ = document.getElementById('devices');
    for (i = 0; i < targ.options.length; i++)
		{
		test = document.getElementById('Checkbox-' + i).checked;
		targ.options[i].selected = false;
		if (test)
			{
			targ.options[i].selected = true;
			}
		}
	}
	

	
// reset device	
function reset() {
if (debug == 'on'){ alert('reset') };
	var nm = $(t).attr("nm");
	var  def = nm+" reset_device checked";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	return;
	}	
	
		
	
// events from monitor to edit
function transferevent(){
if (debug == 'on'){ alert('transferevent') };
		var values = $('#lf').val();
		if (values){
		var string = values.join(',');
		document.getElementById('add_event').value = string;
		}
	}
	
	
// Sortierung ändern
function changesort(){
if (debug == 'on'){ alert('changesort') };
	sortby = $("[name=sort]").val();
	var nm = $(t).attr("nm");
	var  def = nm+" sort_device "+sortby;
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}

// device zufügen
function addevice(device){
if (debug == 'on'){ alert('adddevice') };
	var nm = $(t).attr("nm");
	var  def = nm+" add_device "+device;
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}
	
// device löschen
function deletedevice(device){
if (debug == 'on'){ alert('deletedevice') };
	var nm = $(t).attr("nm");
	var  def = nm+" del_device "+device;
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}

// unbekannt		
function aktvalue(target,cmd){
if (debug == 'on'){ alert('aktvalue') };
	document.getElementById(target).value = cmd; 
	return;
	}



// unbekannt
function writeattr(){
if (debug == 'on'){ alert('writeattr') };
    conf='';
	var nm = $(t).attr("nm");
	var  def = nm+" Writesequenz "+encodeURIComponent(conf);
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}

// lösche log
function clearlog(){
if (debug == 'on'){ alert('clearlog') };
     conf='';
	 var nm = $(t).attr("nm");
	 var  def = nm+" clearlog "+encodeURIComponent(conf);
	 location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	 }
	 
// unbekannt	 
function savesys(conf){
if (debug == 'on'){ alert('savesys') };
	conf = conf.replace(/:/g,'#[dp]');
	conf = conf.replace(/;/g,'#[se]');
	conf = conf.replace(/ /g,'#[sp]');
	conf = conf.replace(/'/g,'#[st]');
	var nm = $(t).attr("nm");
	var  def = nm+" savesys "+encodeURIComponent(conf);
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}

// unbekannt
 function showValue(newValue,copytofield,target){
	if (debug == 'on'){ alert('showValue') };
	var opt = target + '_opt';
	document.getElementById(opt).value=newValue;
	document.getElementById(copytofield).value = newValue;
	}

// unbekannt
function showtextfield(newValue,copytofield,target)
	{
	if (debug == 'on'){ alert('showtextfield') };
	document.getElementById(copytofield).value = newValue;
	}

// unbekannt
function checkevent(event){	
if (debug == 'on'){ alert('checkevent') };
	event = event.replace(/ /g,'~');
	cmd ='get " . $Name . " checkevent '+event;
	FW_cmd(FW_root+'?cmd='+encodeURIComponent(cmd)+'&XHR=1');
	}
	
	
function checkcondition(condition,event){	
if (debug == 'on'){ alert('checkcondition') }
	var selected =document.getElementById(condition).value;
	if (selected == '')
		{
		var textfinal = "<div style ='font-size: medium;'>"+NOCONDITION+"</div>";
		FW_okDialog(textfinal);
		return;
		}
	selected = selected.replace(/\|/g,'(DAYS)'); // !!!
	selected = selected.replace(/\./g,'#[pt]'); // !!!
	selected = selected.replace(/:/g,'#[dp]');
	selected= selected.replace(/~/g,'#[ti]');
	selected = selected.replace(/ /g,'#[sp]');
	event = event.replace(/~/g,'#[ti]');
	event = event.replace(/ /g,'#[sp]');
	cmd ='get '+devicename+' checkcondition '+selected+'|'+event;
	FW_cmd(FW_root+'?cmd='+encodeURIComponent(cmd)+'&XHR=1', function(resp){FW_okDialog(resp);});
	}
	
	
// next
	
	$("#eventmonitor").click(function(){
	var check = $("[name=eventmonitor]").prop("checked") ? "1":"0";
	if (check == 1)
		{
		$( "#log2" ).text( "" );
		$( "#log1" ).text( "eingehende events:" );
		$( "#log3" ).text( "" );
		var field = $('<select style="width: 30em;" size="5" id ="lf" multiple="multiple" name="lf" size="6"  ></select>');
		$(field).appendTo('#log2');
		var field = $('<input id ="editevent" type="button" value="'+editevent+'"/>');
		$(field).appendTo('#log3');
		return;
		}
	});
	
	
	
	

// clickfunktions


// details speichern
/* 	$("#aw_det").click(function(){
	var nm = $(t).attr("nm");
	devices = '';
	eval(JAVAFORM);
	devices = devices.replace(/:/g,'#[dp]');
	devices = devices.replace(/;/g,'#[se]');
	devices = devices.replace(/ /g,'#[sp]');
	devices = devices.replace(/%/g,'#[pr]');
	devices =  encodeURIComponent(devices);
	var  def = nm+" details "+devices+" ";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});
	 */

// modify trigger aw_save
	$("#aw_md").click(function(){
	if (debug == 'on'){ alert('#aw_md') };
	var nm = $(t).attr("nm");
	trigon = $("[name=trigon]").val();
	trigon = trigon.replace(/ /g,'~');
	trigoff = $("[name=trigoff]").val();
	trigoff = trigoff.replace(/ /g,'~');
	trigcmdon = $("[name=trigcmdon]").val();
	trigcmdon = trigcmdon.replace(/ /g,'~');
	trigcmdoff = $("[name=trigcmdoff]").val();
	if(typeof(trigcmdoff)=="undefined"){trigcmdoff="no_trigger"}
	trigcmdoff = trigcmdoff.replace(/ /g,'~');
	trigsave = $("[name=aw_save]").prop("checked") ? "ja":"nein";
	trigwhite = $("[name=triggerwhitelist]").val();
	if (trigcmdon == trigon  && trigcmdon != 'no_trigger' && trigon != 'no_trigger'){
	FW_okDialog('on triggers for \'switch Test on + execute on commands\' and \'execute on commands only\' may not be the same !');
	return;
	} 
	if (trigcmdoff == trigoff && trigcmdoff != 'no_trigger' && trigoff != 'no_trigger'){
	FW_okDialog('off triggers for \'switch Test off + execute on commands\' and \'execute off commands only\' may not be the same !');
	return;
	} 
	if (trigon == trigoff && trigon != 'no_trigger'){
	FW_okDialog('trigger for \'switch Test on + execute on commands\' and \'switch Test off + execute off commands\' must not both be \'*\'');
	return;
	} 
	var  def = nm+" trigger "+trigon+" "+trigoff+" "+trigsave+" "+trigcmdon+" "+trigcmdoff+" "  ;
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});



	// unbekannt
	$("#aw_little").click(function(){
	if (debug == 'on'){ alert('#aw_little') };
	var veraenderung = 3; // Textfeld veraendert sich stets um 3 Zeilen
	var sel = document.getElementById('textfie').innerHTML;
	var show = document.getElementById('textfie2');
	var2 = "size=\"6\"";
	var result = sel.replace(/size=\"15\"/g,var2);
	document.getElementById('textfie').innerHTML = result;      
	});
	
	//delete trigger
	$("#aw_md2").click(function(){
	if (debug == 'on'){ alert('#aw_md2') };
	var nm = $(t).attr("nm");
	var  def = nm+" del_trigger ";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});
		
	//delete svedcmds
	$("#del_savecmd").click(function(){
	if (debug == 'on'){ alert('#del_savecmd') };
	var nm = $(t).attr("nm");
	var  def = nm+" delcmds ";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});	
	
// unbekannt
	$("#aw_dev").click(function(){
	if (debug == 'on'){ alert('#aw_dev') };
	var nm = $(t).attr("nm");
	devices = $("[name=affected_devices]").val();
	var  def = nm+" devices "+devices+" ";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	}); 
	
//unbekannt
	$("#aw_show").click(function(){
	if (debug == 'on'){ alert('#aw_show') };
	$("[name=noshow]").css("display","block");
	$("[name=noshowtask]").css("display","none");
	});

//unbekannt	
	$("#aw_addevent").click(function(){
	if (debug == 'on'){ alert('#aw_addevent') };
	var nm = $(t).attr("nm");
	event = $("[name=add_event]").val();
	event= event.replace(/ /g,'[sp]');
	event= event.replace(/\|/g,'[bs]');
	if (event == '')
		{
		return; 
		}	  
	var  def = nm+" addevent "+event+" ";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});
	
//aplly filter to trigger
	$("#aw_md1").click(function(){
	if (debug == 'on'){ alert('#aw_md1') };	
	var nm = $(t).attr("nm");
	var  def = nm+" filter_trigger ";
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});

//unbekannt
	$("#aw_trig").click(function(){
	if (debug == 'on'){ alert('#aw_trig') };	
	var nm = $(t).attr("nm");
	trigdev = $("[name=trigdev]").val();
	timeon =  $("[name=timeon]").val();
	timeoff =  $("[name=timeoff]").val();
	timeononly =  $("[name=timeononly]").val();
	timeoffonly =  $("[name=timeoffonly]").val();
	if(typeof(timeoffonly)=="undefined"){timeoffonly=""}
	timeonoffonly =  $("[name=timeonoffonly]").val();
	if(typeof(timeonoffonly)=="undefined"){timeonoffonly=""}
	trigdevcond = $("[name=triggercondition]").val();
	trigdevcond = trigdevcond.replace(/\\./g,'#[pt]');
	trigdevcond = trigdevcond.replace(/:/g,'#[dp]');
	trigdevcond= trigdevcond.replace(/~/g,'#[ti]');
	trigdevcond = trigdevcond.replace(/ /g,'#[sp]');
	trigdevcond = trigdevcond+':';
	timeon = timeon.replace(/ /g, '');
	timeoff = timeoff.replace(/ /g, '');
	timeononly = timeononly.replace(/ /g, '');
	timeoffonly = timeoffonly.replace(/ /g, '');
	timeonoffonly = timeonoffonly.replace(/ /g, '');
	timeon = timeon.replace(/:/g, '#[dp]');
	timeoff = timeoff.replace(/:/g, '#[dp]');
	timeononly = timeononly.replace(/:/g, '#[dp]');
	timeoffonly = timeoffonly.replace(/:/g, '#[dp]');
	timeonoffonly = timeonoffonly.replace(/:/g, '#[dp]');
	timeon = timeon+':';
	timeoff = timeoff+':';
	timeononly = timeononly+':';
	timeoffonly = timeoffonly+':';
	timeonoffonly = timeonoffonly+':';
	trigwhite = $("[name=triggerwhitelist]").val();
	var  def = nm+" set_trigger  "+trigdev+" "+timeon+" "+timeoff+" "+timeononly+" "+timeoffonly+" "+timeonoffonly+" "+trigdevcond+" "+trigwhite+" " ;
	def =  encodeURIComponent(def);
	location = location.pathname+"?detail="+devicename+"&cmd=set "+addcsrf(def);
	});
	








