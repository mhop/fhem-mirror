FW_version["fhemweb_weekprofile.js"] = "$Id$";

var language = 'de';
//for tooltip
$(document).ready(function(){
    $('[data-toggle="tooltip"]').tooltip();
    language = window.navigator.userLanguage || window.navigator.language;
});

var shortDays = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];

function FW_weekprofileInputDialog(title,inp,def,parent,callback)
{
  var div = $("<div id='FW_weekprofileInputDiolog'>");
  var table = $("<table>");
  var content = [];
  
  for(var i=0; i<title.length; i++){
    var tr = 
    content[i] = $('<input type="'+inp[i]+'">').get(0);
    if (def)
      content[i].value = def[i];
        
    var tr = $("<tr>");
    var td1 = $("<td>");
    
    $(td1).append(title[i]);
    if (inp[i] == 'hidden') {
      $(td1).attr("colspan","2");
      $(td1).attr("align","center");
    }
      
    var td2 = $("<td>");
    
    $(td2).append(content[i]);
    $(tr).append(td1);
    $(tr).append(td2);
    table.append(tr);
  }
  $(div).append(table);
  
  $("body").append(div);
  $(div).dialog({
    dialogClass:"no-close",modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    title: title,
    buttons: [{text:"OK", click:function(){
      $(this).dialog("close");
      $(div).remove();
      if(callback) {
        var backCont = [];
        for(var i=0; i<content.length; i++){
          backCont[i] = content[i].value;
          if (inp[i] == 'checkbox') 
            backCont[i] = content[i].checked;
        }
        callback(backCont,1);
      }
    }},{text:"CANCEL", click:function(){
      $(this).dialog("close");
      $(div).remove();
      content.value = null;
      if(callback)
        callback(null,0);
    }}]
  });

  if(parent)
    $(div).dialog( "option", "position", {
      my: "left top", at: "right bottom",
      of: parent, collision: "flipfit"
    });
}

function FW_weekprofileMultiSelDialog(title, elementNames, elementLabels, selected,freeInp,parent,callback)
{
  var table = "<table>";
  if (elementNames) {
    for(var i1=0; i1<elementNames.length; i1++){
      var n = elementNames[i1];
      var l = n;
      if (elementLabels && elementLabels.length == elementNames.length)
        l = elementLabels[i1];
        
      var sel = 0;
      if (selected && selected.indexOf(n)>=0) 
        sel=1;

      table += '<tr><td><div class="checkbox"><input name="'+n+'" type="checkbox"';
      table += (sel ? " checked" : "")+'/><label for="'+n+'"><span></span></label></div></td>';
      table += '<td><label for="' +n+'">'+l+'</label></td></tr>';
    }
  }
  table += "</table>";
  
  var div = $("<div id='FW_weekprofileMultiSelDiolog'>");
  $(div).append(title);
  $(div).append(table);
  if (freeInp && freeInp == 1)
    $(div).append('<input id="FW_weekprofileMultiSelDiologFreeText" />');
  $("body").append(div);
  
   $(div).dialog({
    dialogClass:"no-close",modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    title: title,
    buttons: [{text:"OK", click:function(){
      var res=[];
      if($("#FW_weekprofileMultiSelDiologFreeText").val())
        res.push($("#FW_weekprofileMultiSelDiologFreeText").val());
      
      $("#FW_weekprofileMultiSelDiolog table input").each(function(){
        if($(this).prop("checked"))
          res.push($(this).attr("name"));
      });
      $(this).dialog("close");
      $(div).remove();
      if(callback)
        callback(res);
    }},{text:"CANCEL", click:function(){
      $(this).dialog("close");
      $(div).remove();
      if(callback)
        callback(null);
    }}]
  });
  
  if(parent)
    $(div).dialog( "option", "position", {
      my: "left top", at: "right bottom",
      of: parent, collision: "flipfit"
    });
}

function FW_GetTranslation(widget,translate)
{
  if (widget.TRANSLATIONS == null)
    return translate;
  
  var translated = widget.TRANSLATIONS[translate];
  if (translated.length == 0)
    return translate;
  
  return translated;
}

function weekprofile_DoEditWeek(devName,newPage)
{
  var widget = $('div[informid="'+devName+'"]').get(0);
 
  if (newPage == 1) {
    var csrfToken = $("body").attr('fwcsrf');
    var url = FW_root+'?cmd={weekprofile_editOnNewpage("'+widget.DEVICE+'","'+widget.CURTOPIC+':'+widget.CURPRF+'");;}';
    if (csrfToken)
      url = url + '&fwcsrf='+ csrfToken;
    window.location.assign(url);
  } else {
    widget.MODE = 'EDIT';
    $(widget.MENU.BASE).hide();
    widget.setValueFn("REUSEPRF");
  }
}

function FW_weekprofilePRF_chached(devName,select)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  var prfName = select.options[select.selectedIndex].value;
  widget.CURPRF = prfName;
  widget.PROFILE = null;  
  FW_queryValue('get '+devName+' profile_data '+widget.CURTOPIC+':'+widget.CURPRF, widget);
}

function FW_weekprofileTOPIC_chached(devName,select)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  var topicName = select.options[select.selectedIndex].value;
  widget.CURTOPIC = topicName;
  widget.CURPRF = null;
  widget.PROFILE = null;
  FW_cmd(FW_root+'?cmd=get '+devName+' profile_names '+widget.CURTOPIC+'&XHR=1',function(data){FW_weekprofileGetValues(devName,"PROFILENAMES",data);});
}

function FW_weekprofileChacheTo(devName,topicName,profileName)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  widget.CURTOPIC = topicName;
  widget.CURPRF = profileName;
  widget.PROFILE = null;
  FW_cmd(FW_root+'?cmd=get '+devName+' profile_names '+widget.CURTOPIC+'&XHR=1',function(data){FW_weekprofileGetValues(devName,"PROFILENAMES",data);});
}

function FW_weekprofileRestoreTopic(devName,bnt)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  FW_weekprofileInputDialog(["<p>Restore topic: '"+widget.CURTOPIC+"'&nbsp;?</p>"],["hidden"],null,bnt,function(name,ok){
    if (ok == 1)
        FW_cmd(FW_root+'?cmd=set '+devName+' restore_topic '+widget.CURTOPIC+'&XHR=1',function(data){
        if (data != "")
        {
			console.log(devName+" error restore topic '" +data+"'");
			FW_errmsg(devName+" error restore topic '" +data+"'",5000);
			return;
		}
      });
    });
}

function FW_weekprofileSendToDev(devName,bnt)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  var deviceLst = null;
  bnt.setValueFn = function(data) {
    try {
      deviceLst=JSON.parse(data);
      var devicesNames = [];
      var devicesAlias = [];
      for (var k=0; k < deviceLst.length; k++) {
        devicesNames.push(deviceLst[k]['NAME']);
        devicesAlias.push(deviceLst[k]['ALIAS']);
      }
      var selected = [];
      if (widget.MASTERDEV)
        selected.push(widget.MASTERDEV);
      FW_weekprofileMultiSelDialog("<span>Device(s):</span>",devicesNames,devicesAlias,selected,1,bnt, 
        function(sndDevs) {
          if (!sndDevs || sndDevs.length==0)
            return;
          FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" send_to_device "+widget.CURTOPIC+':'+widget.CURPRF+" "+sndDevs.join(',')+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
        });
      
    } catch(e){
      console.log(devName+" error parsing json '" +data+"'");
      FW_errmsg(devName+" Parameter "+e,5000);
      return;
    }
  }

  FW_queryValue('get '+devName+' sndDevList', bnt);
 }

function FW_weekprofileCopyPrf(devName,lnk)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  var title = [];
  var inp = [];
  var def = [];
  var idx = 0;
  
  var topic = '';
  if (widget.USETOPICS==1) {
    topic=widget.CURTOPIC+":";
  }
  
  title[idx] = "<p>Create new entry from: "+topic+widget.CURPRF+"</p>";
  inp[idx] = "hidden";
  def[idx] = '';
  idx++;
  
  if (widget.USETOPICS==1) {
     title[idx] = "<p>Reference:</p>";
     inp[idx] = "checkbox";
     def[idx] = '';
     idx++;
    
     title[idx] = "<p>Topic:</p>";
     inp[idx] = "text";
     def[idx] = widget.CURTOPIC;
     idx++;
  }
    
  title[idx] = "<p>Name:</p>";
  inp[idx] = "text";
  def[idx] = '';
  
  FW_weekprofileInputDialog(title,inp,def,lnk,function(names,ok){
    if (ok < 1)
      return;
    var topic = widget.CURTOPIC;
    var name = names[names.length-1].trim();
    var ref = 0;
    if (widget.USETOPICS==1) {
      topic = names[names.length-2].trim();
      ref = names[names.length-3];
    }    
    if (topic.length < 1 || name.length < 1)
      return;
    if (ref != 0)
      FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" reference_profile "+widget.CURTOPIC+':'+widget.CURPRF+" "+topic+':'+name+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
    else
      FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" copy_profile "+widget.CURTOPIC+':'+widget.CURPRF+" "+topic+':'+name+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
    });
}

function FW_weekprofileRemovePrf(devName,lnk)
{
  var widget = $('div[informid="'+devName+'"]').get(0)
  
  FW_weekprofileInputDialog(["<p>Delete Profile: '"+widget.CURTOPIC+':'+widget.CURPRF+"'&nbsp;?</p>"],["hidden"],null,lnk,function(name,ok){
    if (ok < 1)
      return;
    FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" remove_profile "+widget.CURTOPIC+':'+widget.CURPRF+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
    });
}


function FW_weekprofileShow(widget)
{
  $(widget.MENU.BASE).show();
  
  var editIcon = $(widget.MENU.BASE).find('a[name="'+widget.DEVICE+'.edit"]').get(0);
  $(editIcon).css("visibility", "visible"); //hide() remove the element
  
  $(widget.MENU.CONTENT).empty();
  
  var selMargin=0;
  var tdStyle="style=\"padding-left:0px;padding-right:0px\"";
  
  if (widget.USETOPICS == 1) {
    selMargin = 2;
    tdStyle = "style=\"padding:0px\"";
  }
  
  if (widget.PROFILENAMES) {
    var html='';
    html += '<table style="padding-bottom:0">';
    html += "<tr><td style=\"padding:0px\">";
    if (widget.USETOPICS == 1 && widget.TOPICNAMES) {
        
        html += "<select style=\"margin-bottom:"+selMargin+"px\" name=\"TOPICS\" onchange=\"FW_weekprofileTOPIC_chached('"+widget.DEVICE+"',this)\">";
        for (var k=0; k < widget.TOPICNAMES.length; k++)
        {
            var name = widget.TOPICNAMES[k].trim();
            var selected = (widget.CURTOPIC == name) ? "selected " : "";
            html += "<option "+selected+"value=\""+name+"\">"+name+"</option>";
        }
        html += "</select>";
    }
    
    html += "</td>";
    html += "<td rowspan=\"2\" "+tdStyle+">";
    
    html += "<button type=\"button\"onclick=\"FW_weekprofileCopyPrf('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"copy profile\">+</button>";   
    
    html += "&nbsp;"
    html += "<button type=\"button\" onclick=\"FW_weekprofileRemovePrf('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"remove profile\">-</button>";   
    
    html += "&nbsp;"
    if (widget.USETOPICS == 0) {
      html += "<button type=\"button\" onclick=\"FW_weekprofileSendToDev('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"send to device\">--></button>";   
    } else {
      html += "<button type=\"button\" onclick=\"FW_weekprofileRestoreTopic('"+widget.DEVICE+"',this)\" data-toggle=\"tooltip\" title=\"restore topic\">T</button>";
    }
    
    html += "</td></tr>";
    html += "<tr><td "+tdStyle+">";    
    html += "<select style=\"margin-top:"+selMargin+"px\" name=\"PROFILES\" onchange=\"FW_weekprofilePRF_chached('"+widget.DEVICE+"',this)\">";    
    for (var k=0; k < widget.PROFILENAMES.length; k++)
    {
        var name = widget.PROFILENAMES[k];
        var selected = (widget.CURPRF == name) ? "selected " : "";
        html += "<option "+selected+"value=\""+name+"\">"+name+"</option>";
    }
    html += "</select>";
    html += "</td></tr>";
    
    if (widget.PRFREF) {
      $(editIcon).css("visibility", "hidden");
      var names =  widget.PRFREF.split(':');
      names[0] = names[0].trim();
      names[1] = names[1].trim();
      html += "<tr><td colspan=\"2\" align=\"left\" "+tdStyle+">";
      html += "&nbsp;"
      html += "<a href=\"javascript:void(0)\" onclick=\"FW_weekprofileChacheTo('"+widget.DEVICE+"','"+names[0]+"','"+names[1]+"')\">REF: "+names[0]+":"+names[1]+"</a>";
      html += "</td></tr>";
    }
    html += "</table>";
    
    $(widget.MENU.CONTENT).append(html);
    
    var select = $(widget.MENU.CONTENT).find('select[name="PROFILES"]').get(0);
    var prfName = select.options[select.selectedIndex].value;
    
    if (widget.CURPRF != prfName)
      FW_weekprofilePRF_chached(widget.DEVICE,select);
  }
  
  if (!widget.PROFILE) {
    return;
  }
  
  var table = widget.CONTENT;
  $(table).empty();
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

function FW_weekprofileEditTime_changed(inp)
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
    
    FW_weekprofileEditTime_changed(inp.get(0));
    
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

function FW_weekprofileTransDay(devName,day,bnt)
{
  var widget = $('div[informid="'+devName+'"]').get(0);
  var srcDay = $(widget.CONTENT).find("table[id*=\"weekprofile."+widget.DEVICE+"\"][data-day*=\""+shortDays[day]+"\"]");
  
  var dayNames = [];
  var dayAlias = [];
  for (var k=0; k < shortDays.length; k++) {
    if (k != day) { 
      dayNames.push(shortDays[k]);
      dayAlias.push(widget.WEEKDAYS[k]);
    }
  }
  var selected = [];  
  FW_weekprofileMultiSelDialog("<span>Days(s):</span>",dayNames,dayAlias,selected,0,bnt, 
      function(selDays) {
        if (!selDays || selDays.length==0)
          return;
        for (var k=0; k < selDays.length; k++) {
          var destDay = $(widget.CONTENT).find("table[id*=\"weekprofile."+widget.DEVICE+"\"][data-day*=\""+selDays[k]+"\"]");
          destDay.empty();
          destDay.append(srcDay.clone().contents());
        }
      });
}

function FW_weekprofileTemp_chached(select)
{
  var val = select.options[select.selectedIndex].value;
  
  $(select).find("option").removeAttr('selected');
  $(select).val(val);
  $(select.options[select.selectedIndex]).attr("selected","selected");
}

function FW_weekprofileEditDay(widget,day)
{ 
  var div = $("<div>").get(0);
  var html= '';
  html += "<div style=\"padding:5px;\">";
  html += "<span style=\"margin-right:10px;margin-left:10px\">"+widget.WEEKDAYS[day]+"</span>";
  html += "<a href=\"javascript:void(0)\" onclick=\"FW_weekprofileTransDay('"+widget.DEVICE+"',"+day+",this)\" data-toggle=\"tooltip\" title=\"transfer day\">--></a>"; 
  html += "</div>";
  $(div).append(html);
  
  var table = $("<table>").get(0);
  $(table).attr('id',"weekprofile."+widget.DEVICE).attr("data-day", shortDays[day]);
  $(table).attr('class',"block wide weekprofile");
  
  html = '';
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
    html += "<td><input type=\"text\" name=\"ENDTIME\" size=\"5\" maxlength=\"5\" align=\"center\" value=\""+endTime+"\" onblur=\"FW_weekprofileEditTime_changed(this)\"/></td>"; 
    
    //temp
    var tempOn = widget.TEMP_ON;
    var tempOff = widget.TEMP_OFF;

    if (tempOn == null)
      tempOn = 30;
    
    if (tempOff == null)
      tempOff = 5;
      
    if (tempOff > tempOn)
    {
		var tmp = tempOn;
		tempOn = tempOff;
		tempOff = tmp;
	}
    
    html += "<td><select name=\"TEMP\" size=\"1\" onchange=\"FW_weekprofileTemp_chached(this)\">";
    for (var k=tempOff; k <= tempOn; k+=.5)
    {
        var selected = (k == temps[i]) ? "selected " : "";
        if (k == widget.TEMP_OFF)
          html += "<option "+selected+"value=\"off\">off</option>";
        else if (k == widget.TEMP_ON)
          html += "<option "+selected+"value=\"on\">on</option>";
        else
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
  $(widget.MENU.CONTENT).empty();
  
  var table = widget.CONTENT; 
  var daysInRow = 2;
  
  if (widget.EDIT_DAYSINROW)
    daysInRow = widget.EDIT_DAYSINROW;
    
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
  
  tr.append("<td><input type=\"button\" value=\""+FW_GetTranslation(widget,'Speichern')+"\" onclick=\"FW_weekprofilePrepAndSendProf('"+widget.DEVICE+"')\">");
  tr.append("<td><input type=\"button\" value=\""+FW_GetTranslation(widget,'Abbrechen')+"\" onclick=\"FW_weekprofileEditAbort('"+widget.DEVICE+"')\">");
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
    
    var day = $(tableDay[i]).attr("data-day");
      
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
    FW_cmd(FW_root+"?cmd=set "+widget.DEVICE+" profile_data "+widget.CURTOPIC+':'+widget.CURPRF+" "+data+"&XHR=1",function(arg) {FW_weekprofileSendCallback(widget.DEVICE,arg);});
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
  FW_weekprofileBack(widget);
}

function FW_weekprofileBack(widget)
{
  if (widget.JMPBACK){
    var isInIframe = (window.location != window.parent.location) ? true : false;
    if (isInIframe) {
      parent.history.back();
    } else
      window.history.back();
  }
  else {
    widget.MODE = "SHOW";
    widget.setValueFn("REUSEPRF");
  }
}

function FW_weekprofileEditAbort(devName)
{
  var widget = $('div[informid="'+devName+'"]').get(0);
  FW_weekprofileBack(widget);
}

function FW_weekprofileGetProfileData(devName,data)
{ 
  var widget = $('div[informid="'+devName+'"]').get(0);
  $(widget.CONTENT).empty();
  
  var reuse = (data == "REUSEPRF") ? 1 : 0;
  var prf={};
  try {
    (reuse) ? prf = widget.PROFILE :  prf=JSON.parse(data);
  } catch(e){
    console.log(devName+" error parsing json '" +data+"'");
    FW_errmsg(devName+" Parameter "+e,5000);
    return;
  }
  
  widget.PROFILE = prf;
  widget.PRFREF = null;
  if (widget.MODE == 'SHOW')
  {
    if (reuse == 0 && widget.USETOPICS != 0) {
      //check if data is a reference
      FW_cmd(FW_root+'?cmd=get '+devName+' profile_references '+widget.CURTOPIC+':'+widget.CURPRF+'&XHR=1',function(data){
          if (data != 0) {
            var name = data.split(':');
            if (name.length == 2) {
              widget.PRFREF = data;
            } else {
              console.log(devName+" error get references '" +data+"'");
            }
          }
          FW_weekprofileShow(widget);
        });
    } else  {
      FW_weekprofileShow(widget);
    }
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
  data = data.trim();
  if(data.match(/^[\r\n]*$/)) {return;}
  
  var widget = $('div[informid="'+devName+'"]').get(0);
  
  if (what == "WEEKDAYS"){
    widget.WEEKDAYS = data.split(',');
  } else if (what == "PROFILENAMES") {
    widget.PROFILENAMES = data.split(',');
    
    if (widget.MODE != 'EDIT') {
      if (widget.CURPRF == null && widget.PROFILENAMES) {
          widget.CURPRF = widget.PROFILENAMES[0]; 
      }
      FW_queryValue('get '+devName+' profile_data '+widget.CURTOPIC+':'+widget.CURPRF, widget);
    } else {
        widget.setValueFn("REUSEPRF");
    }
  } else if (what == "TOPICNAMES") {
      widget.TOPICNAMES = data.split(',');
      var found = 0;
      for (var k = 0; k < widget.TOPICNAMES.length; ++k) {
        widget.TOPICNAMES[k] = widget.TOPICNAMES[k].trim();
        if (widget.CURTOPIC == widget.TOPICNAMES[k]) {
          found=1;
        }
      }
      if (found==0) {
        widget.CURTOPIC = widget.TOPICNAMES[0];
      }
      FW_weekprofileChacheTo(devName,widget.CURTOPIC,null);
  } else if (what == "TRANSLATE") {
      var arr = data.split(',');
      widget.TRANSLATIONS = new Array();
      for (var k = 0; k < arr.length; ++k) {
        var trans = arr[k].split(':');
        if (trans.length == 2)
          widget.TRANSLATIONS[trans[0].trim()] = trans[1].trim();
      }
  }
}

function
FW_weekprofileCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  // called from FW_replaceWidget fhemweb.js 
  if( 0 ) {
    console.log( "elName: "+elName );   
    console.log( "devName: "+devName ); // attr dev
    console.log( "vArr: "+vArr );       // attr arg split ','
    console.log( "currVal: "+currVal ); // attr current 
    console.log( "set: "+set );         // attr cmd split ' ' first entry
    console.log( "params: "+params );   // attr cmd list split ' ' without first entry
    console.log( "cmd: "+cmd );         // function for ToDo
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
  
  var menuContent = '<td style="display:inline;padding:0px;margin:0px;"><div id="weekprofile.menu.content"></td>';
  $(widget.MENU.BASE.parentElement.parentElement).append(menuContent);
  widget.MENU.CONTENT = $(widget.HEADER).find('div[id*="menu.content"]').get(0);
  
  widget.JMPBACK = null;
  widget.MODE = 'SHOW';
  widget.USETOPICS = 0;
  widget.TEMP_ON = null;
  widget.TEMP_OFF = null;

  for (var i = 1; i < vArr.length; ++i) {
    var arg = vArr[i].split(':');
    switch (arg[0]) {
      case "MODE":      widget.MODE = arg[1];           break;
      case "JMPBACK":   widget.JMPBACK = arg[1];        break;
      case "MASTERDEV": widget.MASTERDEV = arg[1];      break;
      case "USETOPICS": widget.USETOPICS = arg[1];      break;
      case "DAYINROW":  widget.EDIT_DAYSINROW = arg[1]; break;
      case "TEMP_ON":   widget.TEMP_ON = parseFloat(arg[1]); break;
      case "TEMP_OFF":  widget.TEMP_OFF = parseFloat(arg[1]);break;
    }
  }
  
  widget.DEVICE = devName;
  widget.WEEKDAYS = shortDays.slice();
  
  var current = currVal.split(':');
  widget.CURTOPIC = current[0];
  widget.CURPRF = current[1];
  
  widget.setValueFn = function(arg){FW_weekprofileGetProfileData(devName,arg);}
  widget.activateFn = function(arg){
    FW_queryValue('get '+devName+' profile_data '+widget.CURTOPIC+':'+widget.CURPRF, widget);
    FW_cmd(FW_root+'?cmd={AttrVal("'+devName+'","widgetWeekdays","")}&XHR=1',function(data){FW_weekprofileGetValues(devName,"WEEKDAYS",data);});
    FW_cmd(FW_root+'?cmd={AttrVal("'+devName+'","widgetTranslations","")}&XHR=1',function(data){FW_weekprofileGetValues(devName,"TRANSLATE",data);}); 
    if (widget.USETOPICS == 1) {
      FW_cmd(FW_root+'?cmd=get '+devName+' topic_names&XHR=1',function(data){FW_weekprofileGetValues(devName,"TOPICNAMES",data);});
    } else {
      FW_cmd(FW_root+'?cmd=get '+devName+' profile_names '+widget.CURTOPIC+'&XHR=1',function(data){FW_weekprofileGetValues(devName,"PROFILENAMES",data);});
    }
  };
  
  //inform profile_count changed
  var prfCnt = $('<div informid="'+devName+'-profile_count" style="display:none">').get(0);
  prfCnt.setValueFn = function(arg){
    if (widget.USETOPICS == 1) {
      FW_cmd(FW_root+'?cmd=get '+devName+' topic_names&XHR=1',function(data){FW_weekprofileGetValues(devName,"TOPICNAMES",data);});
    } else {
      FW_cmd(FW_root+'?cmd=get '+devName+' profile_names '+widget.CURTOPIC+'&XHR=1',function(data){FW_weekprofileGetValues(devName,"PROFILENAMES",data);});
    }
  }
  $(widget.HEADER).append(prfCnt);
  return widget;
}

FW_widgets['weekprofile'] = {
  createFn:FW_weekprofileCreate,
};

/*
=pod
=begin html

=end html

=begin html_DE

=end html_DE
=cut
*/
