// MSwitch_Web.js
// Autor:Byte09
// #########################

	var version = '0';
	var info = '';
	var debug ='on';
	
//####################################################################################################



function teststart(){
if (debug == 'on'){ alert(devicename+' Debug MSwitchweb an') };
	return;
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
	
// unbekannt
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
		
	
	
//######################################################################################	
	
	

// clickfunktions

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
	event= event.replace(/\\|/g,'[bs]');
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
	
	
	
