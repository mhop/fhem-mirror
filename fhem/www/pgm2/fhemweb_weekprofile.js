//fhemweb_weekprofile.js 0.01 2015-12-23 Risiko 

//for tooltip
$(document).ready(function(){
    $('[data-toggle="tooltip"]').tooltip(); 
});

var shortDays = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];

function FW_weekprofileInputDialog(title,inp,parent, callback)
{
  var div = $("<div id='FW_weekprofileInputDiolog'>");
  var content = $('<input type="'+inp+'">').get(0);
  $(div).append(title);
  $(div).append(content);
  $("body").append(div);
  $(div).dialog({
    dialogClass:"no-close",modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    title: title,
    buttons: [{text:"OK", click:function(){
      $(this).dialog("close");
      $(div).remove();
      if(callback)
        callback(content.value,1);
    }},{text:"CANCEL", click:function(){
      $(this).dialog("close");
      $(div).remove();
      content.value = null;
      if(callback)
        callback(content.value,0);
    }}]
  });

  if(parent)
    $(div).dialog( "option", "position", {
      my: "left top", at: "right bottom",
      of: parent, collision: "flipfit"
    });
}

function weekprofile_DoEditWeek(devName)
{
  var widget = $('div[informid="'+devName+'"]').get(0);
  widget.MODE = 'EDIT';
  
  $(widget.MENU.BASE).hide();

  widget.setValueFn("REUSEPRF");
}

function FW_weekprofilePRFChached(devName,select)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  var prfName = select.options[select.selectedIndex].value;
  widget.CURPRF = prfName;
  widget.PROFILE = null;  
  FW_queryValue('get '+devName+' profile_data '+prfName, widget);
}

function FW_weekprofileSendToDev(devName,lnk)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  FW_weekprofileInputDialog("<span>Device:</span>","text",lnk,function(device,ok){
    if (!device || device.length <=0)
      return;  
    FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" send_to_device "+widget.CURPRF+" "+device+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
    });
}

function FW_weekprofileCopyPrf(devName,lnk)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  FW_weekprofileInputDialog("<span>Name:</span>","text",lnk,function(name,ok){
    if (!name || name.length <=0)
      return;
    FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" copy_profile "+widget.CURPRF+" "+name+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
    });
}

function FW_weekprofileRemovePrf(devName,lnk)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  FW_weekprofileInputDialog("<p>Delete Profile: '"+widget.CURPRF+"'&nbsp;?</p>","hidden",lnk,function(name,ok){
    if (ok < 1)
      return;
    FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" remove_profile "+widget.CURPRF+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
    });
}


function FW_weekprofileShow(widget)
{
  $(widget.MENU.BASE).show();
  $(widget.MENU.CONTENT).empty();
  
  var html='';
  
  if (widget.PROFILENAMES) {
    html += "&nbsp;"
    html += "<select name=\"PROFILES\" onchange=\"FW_weekprofilePRFChached('"+widget.DEVICE+"',this)\">";
    for (var k=0; k < widget.PROFILENAMES.length; k++)
    {
        var selected = (widget.CURPRF == widget.PROFILENAMES[k]) ? "selected " : "";
        html += "<option "+selected+"value=\""+widget.PROFILENAMES[k]+"\">"+widget.PROFILENAMES[k]+"</option>";
    }
    html += "</select>";
    
    html += "&nbsp;"
    html += "<button type=\"button\"onclick=\"FW_weekprofileCopyPrf('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"copy profile\">+</button>";   
    
    html += "&nbsp;"
    html += "<button type=\"button\" onclick=\"FW_weekprofileRemovePrf('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"remove profile\">-</button>";   
    
    html += "&nbsp;"
    html += "<button type=\"button\" onclick=\"FW_weekprofileSendToDev('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"send to device\">--></button>";   
    
    $(widget.MENU.CONTENT).append(html);
    
    var select = $(widget.MENU.CONTENT).find('select[name="PROFILES"]').get(0);
    var prfName = select.options[select.selectedIndex].value;
    if (widget.CURPRF != prfName)
      FW_weekprofilePRFChached(widget.DEVICE,select);
  }
  
  if (!widget.PROFILE) {
    return;
  }
  
  var table = widget.CONTENT;    
  for (var i = 0; i < shortDays.length; ++i) {
    $(table).append('<tr class="'+ ( (i+1)%2==0 ? 'even':'odd')+ '"><td>'+widget.WEEKDAYS[i]+'</td></tr>');
    
    var tr = $(table).find("tr").get(i);
    
    for (var k = 0; k < widget.PROFILE[shortDays[i]]['temp'].length; ++k) {
      
      var str = '';
      k>0 ? str = widget.PROFILE[shortDays[i]]['time'][k-1] : str = '00:00';
      str = str + '-' + widget.PROFILE[shortDays[i]]['time'][k];
      
      $(tr).append('<td>'+str+ '</td>');
      
      str = widget.PROFILE[shortDays[i]]['temp'][k]+' °C';
      $(tr).append('<td>'+str+ '</td>');
    }
  }
}

function FW_weekprofileEditTimeChanged(inp)
{
  if (inp == null) {return;}
  var times = inp.value.split(':');
  if (times.length == 0)
    return;
    
  var hour = parseInt(times[0]);
  var min = (times.length==2) ? parseInt(times[1]): 0;
  
  inp.value = ((hour<10)?("0"+hour):hour) +":"+ ((min<10)?("0"+min):min);
  
  //set new end time as new start time for the next interval
  var nexttr = inp.parentNode.parentNode.nextSibling;
  if (nexttr!=null){
    nexttr.firstChild.firstChild.innerHTML=inp.value;
  }
}

function FW_weekprofileEditRowStyle(table)
{
  var alltr = $(table).find("tr");
  for (var i = 0; i < alltr.length; ++i){
    var delButton = $(alltr[i]).find('input[name="DEL"]');
    var addButton = $(alltr[i]).find('input[name="ADD"]');
    var inp = $(alltr[i]).find('input[name="ENDTIME"]');
    
    $(alltr[i]).attr('class',(i%2==0)? "odd":"even");
    delButton.attr('type',"button");
    addButton.attr('type',"button");
    inp.removeAttr('style');
    inp.removeAttr('readonly');
    
    FW_weekprofileEditTimeChanged(inp.get(0));
    
    if (i==0){
      $(alltr[i]).find('span[name="STARTTIME"]').get(0).innerHTML = "00:00";
      if (alltr.length == 1){
        delButton.attr('type',"hidden");
      }
    }
    
    if (i==alltr.length-1){
      if (alltr.length > 1){
        addButton.attr('type',"hidden");
      }
      inp.attr('style',"border:none;background:transparent;box-shadow:none");
      inp.get(0).value = "24:00";
      inp.attr('readonly',true);
    }
  }
}

function FW_weekprofileEditAddInterval(tr)
{
  var newtr = $(tr).clone(true);
  
  var alltr = $(tr).parent().children();
  for (var i = 0; i < alltr.length; ++i) {
    if ( $(alltr[i]).is($(tr))) {
      newtr.insertAfter($(alltr[i]));
      break;
    }
  }
  
  FW_weekprofileEditRowStyle($(tr).parent());
  
  var timSel = newtr.find('input[name="ENDTIME"]');
  
  if (alltr.length == 1)
    timSel = $(tr).find('input[name="ENDTIME"]');
    
  timSel.focus();
  timSel.select();
}

function FW_weekprofileEditDelInterval(tr)
{
  var parent = $(tr).parent();
  $(tr).remove();
  FW_weekprofileEditRowStyle(parent)
}

function FW_weekprofileEditDay(widget,day)
{ 
  var div = $("<div>").get(0);
  $(div).append("<div style=\"margin-left:10px;margin:5px\">"+widget.WEEKDAYS[day]+"</div>");
  
  var table = $("<table>").get(0);
  $(table).attr('id',"weekprofile."+widget.DEVICE+"."+shortDays[day]);
  $(table).attr('class',"block wide weekprofile");
  
  var html;
  var times = widget.PROFILE[shortDays[day]]['time'];
  var temps = widget.PROFILE[shortDays[day]]['temp'];
  
  for (var i = 0; i < times.length; ++i) {
    var startTime = (i>0) ? times[i-1] : "00:00";
    var endTime   = (i<times.length-1) ? times[i] : "24:00";
    
    html += "<tr>";
    //from
    html += "<td><span name=\"STARTTIME\">"+startTime+"</span></td>";
   
    html += "<td>-</td>";
    //to
    html += "<td><input type=\"text\" name=\"ENDTIME\" size=\"5\" maxlength=\"5\" align=\"center\" value=\""+endTime+"\" onblur=\"FW_weekprofileEditTimeChanged(this)\"/></td>"; 
    
    //temp
    html += "<td><select name=\"TEMP\" size=\"1\">";
    for (var k=5; k <= 30; k+=.5)
    {
        var selected = (k == temps[i]) ? "selected " : "";
        html += "<option "+selected+"value=\""+k.toFixed(1)+"\">"+k.toFixed(1)+"</option>";
    }
    html += "</select></td>";    
    //ADD-Button
    html += "<td><input type=\"button\" name=\"ADD\" value=\"+\" onclick=\"FW_weekprofileEditAddInterval(this.parentNode.parentNode)\"></td>";
    //DEL-Button
    html += "<td><input type=\"button\" name=\"DEL\" value=\"-\" onclick=\"FW_weekprofileEditDelInterval(this.parentNode.parentNode)\"></td>";
    html += "</tr>";
  }
  $(table).append(html);
  $(div).append(table);
  FW_weekprofileEditRowStyle(table);
  return div;
}

function FW_weekprofileEditWeek(widget)
{
  var table = widget.CONTENT; 
  var daysInRow = 2;
  
  $(table).append('<tr>');
  var tr = $(table).find("tr:last");
  
  for (var i = 0; i < shortDays.length; ++i) {    
    tr.append('<td>');
    tr.find('td:last').append(FW_weekprofileEditDay(widget,i));
    
    if ((i+1)%daysInRow == 0){
      $('<tr>').insertAfter(tr);
      tr = $(table).find("tr:last");
    }
  }
  
  tr.append("<td><table><tr>");
  tr = tr.find("tr:last");
  tr.append("<td><input type=\"button\" value=\"Speichern\" onclick=\"FW_weekprofilePrepAndSendProf('"+widget.DEVICE+"')\">");
  tr.append("<td><input type=\"button\" value=\"Abbrechen\" onclick=\"FW_weekprofileEditAbort('"+widget.DEVICE+"')\">");
}

function FW_weekprofileSendCallback(devName, data)
{
  var widget = $('div[informid="'+devName+'"]').get(0);
  if(!data.match(/^[\r\n]*$/)) // ignore empty answers
    FW_okDialog('<pre>'+data+'</pre>',widget);
}

function FW_weekprofilePrepAndSendProf(devName)
{
  var widget = $('div[informid="'+devName+'"]').get(0);

  var tableDay = $(widget).find("table[id*=\"weekprofile."+devName+"\"]");
  
  if (tableDay.length == 0){
    FW_errmsg(widget.DEVICE+" internal error ",10000);
    return;
  }
  
  var prf=new Object();
  for (var i = 0; i < tableDay.length; ++i) {
    var timeEL = $(tableDay[i]).find('input[name="ENDTIME"]');
    var tempEL = $(tableDay[i]).find('select[name="TEMP"]');    
    
    if (timeEL.length != tempEL.length){
      FW_errmsg(widget.DEVICE+" internal error ",10000);
      return;
    }
    
    var id = $(tableDay[i]).attr('id').split('.');
    var day = id[2];
    
    prf[day] = new Object();
    prf[day]['time'] = new Array();
    prf[day]['temp'] = new Array();
      
    for (var k = 0; k < timeEL.length; ++k) {
      prf[day]['time'].push(timeEL[k].value);      
      prf[day]['temp'].push(tempEL[k].value);
    }
  }
  try {
    var data=JSON.stringify(prf);
    FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" profile_data "+widget.CURPRF+" "+data+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
  } catch(e){
    FW_errmsg(devName+" Parameter "+e,5000);
    return;
  }
  
  for (var i = 0; i < shortDays.length; ++i) {
    var day = shortDays[i];
    if (prf[day] != null){
      widget.PROFILE[day] = prf[day];
    }
  }
  widget.MODE = "SHOW";
  widget.setValueFn("REUSEPRF");  
}

function FW_weekprofileEditAbort(devName)
{
  var widget = $('div[informid="'+devName+'"]').get(0);
  widget.MODE = "SHOW";
  widget.setValueFn("REUSEPRF");
}

function FW_weekprofileSetValue(devName,data)
{ 
  var widget = $('div[informid="'+devName+'"]').get(0);
  $(widget.CONTENT).empty();
  
  var prf={};
  try {
    (data == "REUSEPRF") ? prf = widget.PROFILE :  prf=JSON.parse(data);
  } catch(e){
    console.log(devName+" error parsing json '" +data+"'");
    FW_errmsg(devName+" Parameter "+e,5000);
    return;
  }
  
  widget.PROFILE = prf;
  if (widget.MODE == 'SHOW' || widget.MODE == 'CREATE')
  {
    FW_weekprofileShow(widget);
  }
  else if (widget.MODE == 'EDIT')
  {
    FW_weekprofileEditWeek(widget);
  }
  else
  {
    FW_errmsg(devName+" unknown Mode",10000);
  }
}

function FW_weekprofileGetValues(devName,what,data)
{
  if(data.match(/^[\r\n]*$/)) {return;}
  
  var widget = $('div[informid="'+devName+'"]').get(0);
  
  if (what == "WEEKDAYS"){
    widget.WEEKDAYS = data.split(',');
  } else if (what == "PROFILENAMES") {
    widget.PROFILENAMES = data.split(',');
    if (widget.MODE != 'EDIT') {      
      widget.setValueFn("REUSEPRF");
    }
  }
}

function
FW_weekprofileCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if( 0 ) {
    console.log( "elName: "+elName );
    console.log( "devName: "+devName );
    console.log( "vArr: "+vArr );
    console.log( "currVal: "+currVal );
    console.log( "set: "+set );
    console.log( "params: "+params );
    console.log( "cmd: "+cmd );
  }

  if(!vArr.length || vArr[0] != "weekprofile")
    return undefined;

  var widget = $('div[informid="'+devName+'"]').get(0);
  
  var content = $('<table class="block wide weekprofile" id="weekprofile_content">').get(0);
  $(widget).append(content);

  widget.CONTENT = content; 
  widget.HEADER = $('div[id="weekprofile.'+devName+'.header"]').get(0);
  
  widget.MENU = new Object();
  widget.MENU.BASE = $(widget.HEADER).find('div[id*="menu.base"]').get(0);  
  
  var menu = $('<div class="devType" id="weekprofile.menu.content" style="display:inline;padding:0px;margin:0px;">').get(0);
  $(widget.MENU.BASE).append(menu);
  widget.MENU.CONTENT = menu;
  
  //inform profile_count changed
  var prfCnt = $('<div informid="'+devName+'-profile_count" style="display:none">').get(0);
  prfCnt.setValueFn = function(arg){
    FW_cmd(FW_root+'?cmd=get '+devName+' profile_names&XHR=1',function(data){FW_weekprofileGetValues(devName,"PROFILENAMES",data);});
    }  
  $(widget.HEADER).append(prfCnt);
  
  widget.MODE = 'CREATE';
  widget.DEVICE = devName;
  widget.WEEKDAYS = shortDays.slice();
  widget.CURPRF = currVal;
  
  widget.setValueFn = function(arg){FW_weekprofileSetValue(devName,arg);}
  widget.activateFn = function(arg){
    FW_queryValue('get '+devName+' profile_data '+widget.CURPRF, widget);
    FW_cmd(FW_root+'?cmd={AttrVal("'+devName+'","widgetWeekdays","")}&XHR=1',function(data){FW_weekprofileGetValues(devName,"WEEKDAYS",data);});
    FW_cmd(FW_root+'?cmd=get '+devName+' profile_names&XHR=1',function(data){FW_weekprofileGetValues(devName,"PROFILENAMES",data);});
  };
  return widget;
}

FW_widgets['weekprofile'] = {
  createFn:FW_weekprofileCreate,
};
