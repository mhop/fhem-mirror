//###########################################################################################################################################
// dashboard.js
//###########################################################################################################################################
// Released : 14.11.2013 Sascha Hermann
// Modified : 24.09.2019 Heiko Maaz
//
// Version : 
// 2.0.8:   dashboard_load_tab(tabIndex) test of defined fhemUrl
// 2.0.7:   Insert Configdialog for Tabs. Change handling of parameters in both directions.
// 2.0.6:   change Set and Detail Button.
// 2.0.5:   Delete function for set lockstate
// 2.0.4:   Dashboard position near Top in showfullsize-mode. Restore ActiveTab funktion
// 2.0.3:   Fix showhelper Bug on lock/unlock. The error that after a trigger action the curren tab is changed to the "old" activetab tab has 
//			been fixed.
// 2.0.2:   Tabs can set on top, bottom or hidden
// 2.0.1:   Add Longpoll function. Dashboard can hide FHEMWEB Roomliste and Header.
// 2.0.0:   First Changes vor Dashboard Tabs. Change method store Positiondata. optimization restore Positiondata. Clear poor routines.
//		    Change max/min Values for Groupresize.	Top- and Bottom-Row always 100%
// 1.0.2:   Add DebugMsg. Fix independent Groupsize adjustment after set & siterefresh. Fix
//			wrong set of +Toogle Icon on Siderefresh
// 1.0.1:   Released to testers 
//
//###########################################################################################################################################

var DashboardConfigHash = {};
var dashboard_buttonbar = "top";
var DashboardDraggable = true;

/* evol.colorpicker 2.2
   (c) 2014 Olivier Giulieri
   http://www.codeproject.com/Articles/452401/ColorPicker-a-jQuery-UI-Widget*/
!function(a){var b=0,c=!a.support.cssFloat,d=c?"-ie":"",e=c?!1:/mozilla/.test(navigator.userAgent.toLowerCase())&&!/webkit/.test(navigator.userAgent.toLowerCase()),f=[],g=["ffffff","000000","eeece1","1f497d","4f81bd","c0504d","9bbb59","8064a2","4bacc6","f79646"],h=["f2f2f2","7f7f7f","ddd9c3","c6d9f0","dbe5f1","f2dcdb","ebf1dd","e5e0ec","dbeef3","fdeada","d8d8d8","595959","c4bd97","8db3e2","b8cce4","e5b9b7","d7e3bc","ccc1d9","b7dde8","fbd5b5","bfbfbf","3f3f3f","938953","548dd4","95b3d7","d99694","c3d69b","b2a2c7","92cddc","fac08f","a5a5a5","262626","494429","17365d","366092","953734","76923c","5f497a","31859b","e36c09","7f7f7f","0c0c0c","1d1b10","0f243e","244061","632423","4f6128","3f3151","205867","974806"],i=["c00000","ff0000","ffc000","ffff00","92d050","00b050","00b0f0","0070c0","002060","7030a0"],j=[["003366","336699","3366cc","003399","000099","0000cc","000066"],["006666","006699","0099cc","0066cc","0033cc","0000ff","3333ff","333399"],["669999","009999","33cccc","00ccff","0099ff","0066ff","3366ff","3333cc","666699"],["339966","00cc99","00ffcc","00ffff","33ccff","3399ff","6699ff","6666ff","6600ff","6600cc"],["339933","00cc66","00ff99","66ffcc","66ffff","66ccff","99ccff","9999ff","9966ff","9933ff","9900ff"],["006600","00cc00","00ff00","66ff99","99ffcc","ccffff","ccccff","cc99ff","cc66ff","cc33ff","cc00ff","9900cc"],["003300","009933","33cc33","66ff66","99ff99","ccffcc","ffffff","ffccff","ff99ff","ff66ff","ff00ff","cc00cc","660066"],["333300","009900","66ff33","99ff66","ccff99","ffffcc","ffcccc","ff99cc","ff66cc","ff33cc","cc0099","993399"],["336600","669900","99ff33","ccff66","ffff99","ffcc99","ff9999","ff6699","ff3399","cc3399","990099"],["666633","99cc00","ccff33","ffff66","ffcc66","ff9966","ff6666","ff0066","d60094","993366"],["a58800","cccc00","ffff00","ffcc00","ff9933","ff6600","ff0033","cc0066","660033"],["996633","cc9900","ff9900","cc6600","ff3300","ff0000","cc0000","990033"],["663300","996600","cc3300","993300","990000","800000","993333"]],k=function(a){var b=a.toString(16);return 1==b.length&&(b="0"+b),b},l=function(a){return k(Number(a))},m=function(a){var b=k(a);return b+b+b},n=function(a){if(a.length>10){var b=1+a.indexOf("("),c=a.indexOf(")"),d=a.substring(b,c).split(",");return["#",l(d[0]),l(d[1]),l(d[2])].join("")}return a};a.widget("evol.colorpicker",{version:"2.2",options:{color:null,showOn:"both",displayIndicator:!0,history:!0,strings:"Theme Colors,Standard Colors,More Colors,Less Colors,Back to Palette,History,No history yet."},_create:function(){this._paletteIdx=1,this._id="evo-cp"+b++,this._enabled=!0;var f=this;switch(this.element.get(0).tagName){case"INPUT":var g=this.options.color,h=this.element;if(this._isPopup=!0,this._palette=null,null!==g)h.val(g);else{var i=h.val();""!==i&&(g=this.options.color=i)}h.addClass("colorPicker "+this._id).wrap('<div style="width:'+(this.element.width()+124)+"px;"+(c?"margin-bottom:-21px;":"")+(e?"padding:1px 0;":"")+'"></div>').after('<div class="'+("focus"===this.options.showOn?"":"evo-pointer ")+"evo-colorind"+(e?"-ff":d)+'" '+(null!==g?'style="background-color:'+g+'"':"")+"></div>").on("keyup onpaste",function(){var b=a(this).val();b!=f.options.color&&f._setValue(b,!0)});var j=this.options.showOn;("both"===j||"focus"===j)&&h.on("focus",function(){f.showPalette()}),("both"===j||"button"===j)&&h.next().on("click",function(a){a.stopPropagation(),f.showPalette()});break;default:this._isPopup=!1,this._palette=this.element.html(this._paletteHTML()).attr("aria-haspopup","true"),this._bindColors()}null!==g&&this.options.history&&this._add2History(g)},_paletteHTML:function(){var a=[],b=this._paletteIdx=Math.abs(this._paletteIdx),c=this.options,e=c.strings.split(",");return a.push('<div class="evo-pop',d,' ui-widget ui-widget-content ui-corner-all"',this._isPopup?' style="position:absolute"':"",">"),a.push("<span>",this["_paletteHTML"+b](),"</span>"),a.push('<div class="evo-more"><a href="javascript:void(0)">',e[1+b],"</a>"),c.history&&a.push('<a href="javascript:void(0)" class="evo-hist">',e[5],"</a>"),a.push("</div>"),c.displayIndicator&&a.push(this._colorIndHTML(this.options.color,"left"),this._colorIndHTML("","right")),a.push("</div>"),a.join("")},_colorIndHTML:function(a){var b=[];return b.push('<div class="evo-color" style="float:left"><div style="'),b.push(a?"background-color:"+a:"display:none"),c?b.push('" class="evo-colorbox-ie"></div><span class=".evo-colortxt-ie" '):b.push('"></div><span '),b.push(a?">"+a+"</span>":"/>"),b.push("</div>"),b.join("")},_paletteHTML1:function(){var a=[],b=this.options.strings.split(","),e='<td style="background-color:#',f=c?'"><div style="width:2px;"></div></td>':'"><span/></td>',j='<tr><th colspan="10" class="ui-widget-content">';a.push('<table class="evo-palette',d,'">',j,b[0],"</th></tr><tr>");for(var k=0;10>k;k++)a.push(e,g[k],f);for(a.push("</tr>"),c||a.push('<tr><th colspan="10"></th></tr>'),a.push('<tr class="top">'),k=0;10>k;k++)a.push(e,h[k],f);for(var l=1;4>l;l++)for(a.push('</tr><tr class="in">'),k=0;10>k;k++)a.push(e,h[10*l+k],f);for(a.push('</tr><tr class="bottom">'),k=40;50>k;k++)a.push(e,h[k],f);for(a.push("</tr>",j,b[1],"</th></tr><tr>"),k=0;10>k;k++)a.push(e,i[k],f);return a.push("</tr></table>"),a.join("")},_paletteHTML2:function(){var a,b=[],e='<td style="background-color:#',f=c?'"><div style="width:5px;"></div></td>':'"><span/></td>',g='<table class="evo-palette2'+d+'"><tr>',h="</tr></table>";b.push('<div class="evo-palcenter">');for(var i=0,k=j.length;k>i;i++){b.push(g);var l=j[i];for(a=0,iMax=l.length;iMax>a;a++)b.push(e,l[a],f);b.push(h)}b.push('<div class="evo-sep"/>');var n=[];for(b.push(g),a=255;a>10;a-=10)b.push(e,m(a),f),a-=10,n.push(e,m(a),f);return b.push(h,g,n.join(""),h),b.push("</div>"),b.join("")},_switchPalette:function(b){if(this._enabled){var c,d,e,g=this.options.strings.split(",");if(a(b).hasClass("evo-hist")){var h=['<table class="evo-palette"><tr><th class="ui-widget-content">',g[5],"</th></tr></tr></table>",'<div class="evo-cHist">'];if(0===f.length)h.push("<p>&nbsp;",g[6],"</p>");else for(var i=f.length-1;i>-1;i--)h.push('<div style="background-color:',f[i],'"></div>');h.push("</div>"),c=-this._paletteIdx,d=h.join(""),e=g[4]}else this._paletteIdx<0?(c=-this._paletteIdx,this._palette.find(".evo-hist").show()):c=2==this._paletteIdx?1:2,d=this["_paletteHTML"+c](),e=g[c+1],this._paletteIdx=c;this._paletteIdx=c;var j=this._palette.find(".evo-more").prev().html(d).end().children().eq(0).html(e);0>c&&j.next().hide()}},showPalette:function(){if(this._enabled&&(a(".colorPicker").not("."+this._id).colorpicker("hidePalette"),null===this._palette)){this._palette=this.element.next().after(this._paletteHTML()).next().on("click",function(a){a.stopPropagation()}),this._bindColors();var b=this;a(document.body).on("click."+this._id,function(a){a.target!=b.element.get(0)&&b.hidePalette()})}return this},hidePalette:function(){if(this._isPopup&&this._palette){a(document.body).off("click."+this._id);var b=this;this._palette.off("mouseover click","td").fadeOut(function(){b._palette.remove(),b._palette=b._cTxt=null}).find(".evo-more a").off("click")}return this},_bindColors:function(){var b=this._palette.find("div.evo-color"),c=this.options.history?"td,.evo-cHist div":"td";this._cTxt1=b.eq(0).children().eq(0),this._cTxt2=b.eq(1).children().eq(0);var d=this;this._palette.on("click",c,function(){if(d._enabled){var b=n(a(this).attr("style").substring(17));d._setValue(b)}}).on("mouseover",c,function(){if(d._enabled){var b=n(a(this).attr("style").substring(17));d.options.displayIndicator&&d._setColorInd(b,2),d.element.trigger("mouseover.color",b)}}).find(".evo-more a").on("click",function(){d._switchPalette(this)})},val:function(a){return"undefined"==typeof a?this.options.color:(this._setValue(a),this)},_setValue:function(a,b){a=a.replace(/ /g,""),this.options.color=a,this._isPopup?(b||this.hidePalette(),this.element.val(a).next().attr("style","background-color:"+a)):this._setColorInd(a,1),this.options.history&&this._paletteIdx>0&&this._add2History(a),this.element.trigger("change.color",a)},_setColorInd:function(a,b){this["_cTxt"+b].attr("style","background-color:"+a).next().html(a)},_setOption:function(a,b){"color"==a?this._setValue(b,!0):this.options[a]=b},_add2History:function(a){for(var b=f.length,c=0;b>c;c++)if(a==f[c])return;b>27&&f.shift(),f.push(a)},enable:function(){var a=this.element;return this._isPopup?a.removeAttr("disabled"):a.css({opacity:"1","pointer-events":"auto"}),"focus"!==this.options.showOn&&this.element.next().addClass("evo-pointer"),a.removeAttr("aria-disabled"),this._enabled=!0,this},disable:function(){var a=this.element;return this._isPopup?a.attr("disabled","disabled"):(this.hidePalette(),a.css({opacity:"0.3","pointer-events":"none"})),"focus"!==this.options.showOn&&this.element.next().removeClass("evo-pointer"),a.attr("aria-disabled","true"),this._enabled=!1,this},isDisabled:function(){return!this._enabled},destroy:function(){a(document.body).off("click."+this._id),this._palette&&(this._palette.off("mouseover click","td").find(".evo-more a").off("click"),this._isPopup&&this._palette.remove(),this._palette=this._cTxt=null),this._isPopup&&this.element.next().off("click").remove().end().off("focus").unwrap(),this.element.removeClass("colorPicker "+this.id).empty(),a.Widget.prototype.destroy.call(this)}})}(jQuery);

!function(e){"function"==typeof define&&define.amd?define(["jquery"],e):"object"==typeof exports?module.exports=e(require("jquery")):e(jQuery)}(function(e){function n(e){return u.raw?e:encodeURIComponent(e)}function o(e){return u.raw?e:decodeURIComponent(e)}function i(e){return n(u.json?JSON.stringify(e):String(e))}function t(e){0===e.indexOf('"')&&(e=e.slice(1,-1).replace(/\\"/g,'"').replace(/\\\\/g,"\\"));try{return e=decodeURIComponent(e.replace(c," ")),u.json?JSON.parse(e):e}catch(n){}}function r(n,o){var i=u.raw?n:t(n);return e.isFunction(o)?o(i):i}var c=/\+/g,u=e.cookie=function(t,c,s){if(arguments.length>1&&!e.isFunction(c)){if(s=e.extend({},u.defaults,s),"number"==typeof s.expires){var a=s.expires,d=s.expires=new Date;d.setMilliseconds(d.getMilliseconds()+864e5*a)}return document.cookie=[n(t),"=",i(c),s.expires?"; expires="+s.expires.toUTCString():"",s.path?"; path="+s.path:"",s.domain?"; domain="+s.domain:"",s.secure?"; secure":""].join("")}for(var f=t?void 0:{},p=document.cookie?document.cookie.split("; "):[],l=0,m=p.length;m>l;l++){var x=p[l].split("="),g=o(x.shift()),j=x.join("=");if(t===g){f=r(j,c);break}t||void 0===(j=r(j))||(f[g]=j)}return f};u.defaults={},e.removeCookie=function(n,o){return e.cookie(n,"",e.extend({},o,{expires:-1})),!e.cookie(n)}});

//Only use for debugging
function showdebugMessage(msg){
	document.getElementById("dashboard_jsdebug").value = msg;
}
//------------------------------------------------------------------------------------------------------
// Pagerefresh
//------------------------------------------------------------------------------------------------------
function dashboard_reloadpage() {
	location.reload();
}
//------------------------------------------------------------------------------------------------------
// "Search" SVG Icon in every iconDir and Load the Icon
//------------------------------------------------------------------------------------------------------
function dashboard_loadsvgIcon(svgIcon, svgColor, destObj) { //search Icon in every iconDir
 var groupdata = (DashboardConfigHash['icondirs'].split(",")); 
 for (var i = 0; i < groupdata.length; i++) {
  if (groupdata[i] != "") {
	if (!svgIcon.match('.svg')) {svgIcon = svgIcon+'.svg';}
		groupdata[i] = groupdata[i].replace('.','');
		groupdata[i] = groupdata[i].replace('/opt/fhem','');
		dashboard_showsvgIcon(
			fhemUrl+groupdata[i]+"/"+svgIcon, svgColor, destObj
		);
  	}
 }
}
function dashboard_showsvgIcon(svgIcon, svgColor, destObj) {
	$.ajax({
		type: "GET",
		contentType: "application/json",
		data: "{}",
		url: svgIcon + "&XHR=1&fwcsrf=" + $('body').attr('fwcsrf'),
		dataType: "text",
		success: function(data) {
			if (data) {
				$.get(fhemUrl + '/images/' + data, null, function(data) {
					var svgNode = $("svg", data);
					svgNode.attr('class','ui-tabs-icon');
					svgNode.find('g').attr({ fill : svgColor});
					svgNode.find('g').removeAttr('style');
					svgNode.find('g path').removeAttr('style');
					var docNode = document.adoptNode(svgNode[0]);	
					var pageNode = $(destObj);
					pageNode.html(docNode);		
					if (gridSize = is_dashboard_flexible()) {
						  // update containment for draggable to avoid issues with async loaded icons and tab list height
						  var $container = $(".dashboard_rowcenter");
						  $(".dashboard_widget").draggable('option', 'containment', [$container.offset().left,$container.offset().top]);
					}
			    }, 'xml');
			}
		}
	});
	
	return;
}
//------------------------------------------------------------------------------------------------------
// Get Data from URL in JSON Format
//------------------------------------------------------------------------------------------------------
function dashboard_getData(jsonurl, get, dType, cb) {//get Dashboard config
	$.ajax({
		type: "POST",
		contentType: "application/json",
		data: "{}",
		url: jsonurl+" "+get+"&XHR=1&fwcsrf=" + $('body').attr('fwcsrf'),
		dataType: dType,
		success: function(data) {
			if (get == "config") {for (var key in data.CONFIG) {if (data.CONFIG.hasOwnProperty(key)) {DashboardConfigHash[key] = data.CONFIG[key];} } }
			if (get.indexOf('groupWidget') != -1) {
				dashboard_test2(data);
			}
			if (cb) {
				cb(data);
			}
			return;			
		}
	}); 
}
//------------------------------------------------------------------------------------------------------
// Write the Attribute Value
//------------------------------------------------------------------------------------------------------
function dashboard_setAttribute(Attr, Val) {//set Dashboard Attribute
	var url = document.location.protocol+"//"+document.location.host+fhemUrl;
	FW_cmd(url+'?XHR=1&cmd.'+DashboardConfigHash['name']+'=attr '+DashboardConfigHash['name']+' '+Attr+' '+Val);
}
//------------------------------------------------------------------------------------------------------
// Delete the Attribute
//------------------------------------------------------------------------------------------------------
function dashboard_delAttribute(Attr) {//delete Dashboard Attribute
	var url = document.location.protocol+"//"+document.location.host+fhemUrl;
	FW_cmd(url+'?XHR=1&cmd.'+DashboardConfigHash['name']+'=deleteattr '+DashboardConfigHash['name']+' '+Attr);	
}
//------------------------------------------------------------------------------------------------------
//
//
//
// Dynamic load Group Widgets, comming soon
/*function dashboard_test() {
//alert(DashboardConfigHash['dashboard_tab2groups']);

var groupdata = (DashboardConfigHash['dashboard_tab2groups'].split(",")); 
 for (var i = 0; i < groupdata.length; i++) {
 //alert(groupdata[i]);
 dashboard_getData(fhemUrl+"?cmd=get "+$('#dashboard_define').text(), "groupWidget "+groupdata[i], "html");
 }
}

function dashboard_test2(data) {
//alert("test2");
$('#dashboard_tab1column0').append(data);
}*/


//------------------------------------------------------------------------------------------------------
function saveOrder() {
	var EndSaveResult = "";
	var ActiveTab = getTabIndexFromTab($("#dashboardtabs .ui-tabs-panel:visible"));
	//------------------- Build new Position string ----------------------
	$("#dashboard_tab" + ActiveTab + " .dashboard_widget").each(function (index, value) {
		var SaveResult = "";
		var $widget = $(value);
		var column = $widget.parent().attr("id").replace(new RegExp('dashboard_tab' + ActiveTab + 'column'), '');
		var groupdata = ($widget.data("groupwidget").split(",")); //get curren Group-Configuration			
		if (groupdata[1] != ''){
			groupdata[0] = "t"+ActiveTab+"c"+column;
			groupdata[2] = true; //ever collapsed
			groupdata[3] = $widget.outerWidth();				
			
			if (this.style.height) {
				if (groupdata[4] == 0) {groupdata[4] = $widget.outerHeight();}
				if (groupdata[2] == true) {	
					groupdata[4] = $widget.outerHeight();
					$widget.find(".dashboard_content").data("userheight", $widget.outerHeight()); 
				}								
			}
			// store positions relative to the center row
			groupdata[5] = Math.round($widget.offset().left - $('#dashboard_rowcenter_tab' + ActiveTab).offset().left);
			groupdata[6] = Math.round($widget.offset().top - $('#dashboard_rowcenter_tab' + ActiveTab).offset().top);

			$widget.data("groupwidget",groupdata.join(',')); //store in current Widget
			SaveResult = SaveResult+groupdata.join(',')+":";
		}
		if (SaveResult != ""){ EndSaveResult = EndSaveResult + SaveResult; } //NewResult: <tab><column>,<portlet-1>,<status>,<height>,<width>,<portlet-n>,<status>,<height>,<width>:<columNumber.....	
	});

	//------------------------------------------------------------------------		
	//--------------------- Store new Positions ------------------------
	if (EndSaveResult != "") { $("#dashboardtabs .ui-tabs-panel:visible").data("tabwidgets",EndSaveResult); } //store widgetposition in active tab Widget
	$("#setPosition").button({disabled: false}); //Mark that the Changes are not saved
	//------------------------------------------------------------------------
}

function getTabIndexFromTab ($tab) {
  return $tab.attr("id").replace(/dashboard_tab/, '');
}

function restoreOrder(ActiveTabId) {
 var params = dashboard_get_params();

 if (isNaN(ActiveTabId)) {
   var ActiveTab = $("#dashboardtabs .ui-tabs-panel:visible");
   ActiveTabId = getTabIndexFromTab(ActiveTab);
 }
 else {
   var ActiveTab = $("#dashboard_tab" + ActiveTabId);
 }

 var colCount  = $('#dashboard_tab' + ActiveTabId + ' .dashboard_column').length;
 var colWidths = $('#dashboard_tab' + ActiveTabId).attr('data-tabcolwidths');

 if (!colWidths) {
   colWidths = params[7];
 }

 var aColWidth = GetColWidth(colCount, colWidths);

 //--------------------------------------------- Set Row and Column Settings --------------------------------------------------------------------------------------------
 $("#dashboard").width(params[1]);
 if (ActiveTab.has("#dashboard_rowtop_tab"+ActiveTabId).length){ $("#dashboard_rowtop_tab"+ActiveTabId).css('min-height', params[8] + 'px');  }
 if (ActiveTab.has("#dashboard_rowcenter_tab"+ActiveTabId).length){ $("#dashboard_rowcenter_tab"+ActiveTabId).css('min-height', params[5] + 'px'); } 
 if (ActiveTab.has("#dashboard_rowbottom_tab"+ActiveTabId).length){ $("#dashboard_rowbottom_tab"+ActiveTabId).css('min-height', params[9] + 'px'); } 

 for (var i = 0, n = colCount; i <= n; i++) {  
	if (ActiveTab.has("#dashboard_tab"+ActiveTabId+"column"+i).length) { $("#dashboard_tab"+ActiveTabId+"column"+i).width(aColWidth[i]+"%"); }
 }	
 if (DashboardConfigHash['lockstate'] == "unlock") { $(".ui-row").addClass("dashboard_columnhelper"); } else { $(".ui-row").removeClass("dashboard_columnhelper"); }//set showhelper
 //--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
     
 $(".dashboard_widget").each(function(index, value) {
	var groupdata = $(this).data("groupwidget").split(","); //get the position string from the data
	var TabId = groupdata[0].replace(/c.*/, '').substr(1);
	var ColumnId = groupdata[0].replace(new RegExp('t' + TabId + 'c', ''));
	
	if (TabId == ActiveTabId){ //Restore only for the current active tab
		var groupname = groupdata[1];
		var visible = true; // var visible = groupdata[2]; ever collapsed
                var grid    = (is_flexible = is_dashboard_flexible()) ? is_flexible : 1;
		var width   = Math.round(groupdata[3]/grid)*grid;
		var height  = Math.round(groupdata[4]/grid)*grid;		
		var left    = Math.round(groupdata[5]/grid)*grid;
		var top     = Math.round(groupdata[6]/grid)*grid;

		//---------- Max. Width of an Group. Reduce group-with if need | Min. Width if need ----------	
		if (!is_flexible) {
			var widgetmaxwidth = $(this).parent().width();
			if (width == 0) {
				width = $(this).find(".dashboard_content").children().outerWidth()+10;
			}
		}
		if (width) {
		  $(this).outerWidth(width);
  		}
		//---------------------------------------------------------------------------------------------------------------	
		//-------------------------------- Height of an Group. | Min. Height if need ---------------------------	
		
		if (!is_flexible && height > 0) {
			$(this).outerHeight(height); //set heigh only if > group min. height
		}
		//---------------------------------------------------------------------------------------------------------------	
		//-------------------------------- Corrent height for inner div.  -------------------------------------
		var innerHeight = $(this).children('.dashboard_widgetinner').outerHeight();
		if (this.style.height && $(this).outerHeight() < innerHeight) {
			$(this).css('height', innerHeight + 'px');
		}
		//---------------------------------------------------------------------------------------------------------------	
		//-------------------------------- position of a Group.  --------------------------------------------------------
                if (is_flexible) {
			if (!left) left = 0;
			if (!top) top   = 0;
			$(this).css('position', 'absolute').css('left', left + 'px').css('top', top + 'px');
  		}
		//---------------------------------------------------------------------------------------------------------------	
		$(this).find(".dashboard_content").data("userheight", height-5);		
		if (DashboardConfigHash['lockstate'] == "unlock") { $(this).addClass("dashboard_widgethelper"); } else { $(this).removeClass("dashboard_widgethelper"); }//Show Widget-Helper Frame
		
		if (visible === 'false') {
			if ($(this).find("span").hasClass("dashboard_button_iconminus")){
				$(this).find("span")
					.removeClass( "dashboard_button_iconminus" )
					.addClass( "dashboard_button_iconplus" ); 
			}						
			$(this).find(".dashboard_content").hide();	
			$(this).height($(this).find(".dashboard_widgetinner").height()+5);	
			$(this).find(".dashboard_widgetheader").addClass("dashboard_widgetmin");			
		}	else {$(this).find(".dashboard_widgetheader").addClass("dashboard_widgetmax"); }					
	}
 });
} 

function GetColWidth(ColCount, ColWidth){
 var aColWidth = ColWidth.replace(/%/g, "").split(":");
 if (aColWidth.length > ColCount) { aColWidth.length = ColCount; }
 if (aColWidth.length < ColCount) { for (var i = aColWidth.length; i < ColCount; i++) { aColWidth[i] = "20"; } }   //fill missin width parts with 20%
 var ColWidthCount = aColWidth.length; 
 var ColWidthSum = 0;
 for (var i = 0; i < ColWidthCount; i++) { ColWidthSum = parseInt(aColWidth[i]) + ColWidthSum; } 

 if (ColWidthSum > 100) { //reduce width down to 100%
    while (ColWidthSum > 100){
		ColWidthSum = 0;
		for (var i = 0; i < ColWidthCount; i++) { 
			if (parseInt(aColWidth[i]) > 10) { aColWidth[i] = parseInt(aColWidth[i])-1; }
			ColWidthSum = parseInt(aColWidth[i]) + ColWidthSum; 
		} 		
	}
 }
 if (ColWidthSum < 100) { aColWidth[ColWidthCount-1] = parseInt(aColWidth[ColWidthCount-1]) + (100 - ColWidthSum); } //fill up to 100% width  

 aColWidth[0] = parseInt(aColWidth[0])-(0.3 * ColCount);
 return aColWidth;
}

function is_dashboard_flexible() {
	var params = dashboard_get_params();
	return parseInt(params[15]);
}

function dashboard_get_params() {
	if (!dashboard_get_params.dashboard_params) {
		dashboard_get_params.dashboard_params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
	}
	return dashboard_get_params.dashboard_params;
}

function dashboard_setlock(iTabIndex){
        if(is_dashboard_flexible()) {
		$( "#dashboard_tab" + iTabIndex + " .dashboard_widget" ).draggable( "destroy");
        }
        else {
		$( "#dashboard_tab" + iTabIndex + " .dashboard_column" ).sortable( "destroy");
        }
	$( ".dashboard_widget" ).removeClass("dashboard_widgethelper");
	$( "#dashboard_tab" + iTabIndex + " .dashboard_widget" ).resizable("destroy");
	$( ".dashboard_column" ).removeClass("dashboard_columnhelper");
}

function dashboard_unsetlock(iTabIndex){
	if (DashboardConfigHash['lockstate'] == "unlock") { $( ".dashboard_widget" ).addClass("dashboard_widgethelper"); } else { $( ".dashboard_widget" ).removeClass("dashboard_widgethelper"); }//Show Widget-Helper Frame
	if (DashboardConfigHash['lockstate'] == "unlock") { $( ".dashboard_column" ).addClass("dashboard_columnhelper"); } else { $( ".dashboard_column" ).removeClass("dashboard_columnhelper"); }//Show Widget-Helper Frame
	dashboard_modifyWidget();
}

function dashboard_setposition(){ 
 //------------------- store group position ----------------------------
 for (var i = 0, n = DashboardConfigHash['dashboard_tabcount']; i < n; i++ ) {		
	if ($("#dashboard_tab"+i).data("tabwidgets") != null) {	
		var j = i+1;
		FW_cmd(fhemUrl+'?XHR=1&cmd.'+DashboardConfigHash['name']+'=attr '+DashboardConfigHash['name']+' dashboard_tab'+j+'sorting '+$("#dashboard_tab"+i).data("tabwidgets"));
	}
 }
 $("#setPosition").button({disabled: true});
 //--------------------------------------------------------------------- 
 //--------------------- store active Tab ------------------------------
 // Set only over Dashborad-Dialog or fhem Attribute
 //var activeTab = ($( "#dashboardtabs" ).tabs( "option", "active" ))+1;
 //if (DashboardConfigHash['dashboard_activetab'] != activeTab){
 //	FW_cmd(fhemUrl+'?XHR=1&cmd.'+DashboardConfigHash['name']+'=attr '+DashboardConfigHash['name']+' dashboard_activetab '+activeTab);
 //}
 //--------------------------------------------------------------------- 
}

function dashboard_modifyWidget(){
	makeResizable('.dashboard_widget');
}

function makeResizable (sSelector) {
	var grid = is_dashboard_flexible();
	$( sSelector ).resizable({ 
		start: function(e, ui) {
			if (!is_dashboard_flexible()) {
				var params = dashboard_get_params();
				var groupdata = $(this).data("groupwidget").split(","); //get the position string from the data
				var TabId = getTabIndexFromTab($(this).parent());
				var ColumnId = $(this).parent().attr("id").replace(new RegExp('dashboard_tab' + TabId + 'column'), '');
				var widgetmaxwidth = $(this).parent().width();
				
				if (ColumnId == "100") { var widgetmaxheight = params[8]; }
				if ((ColumnId != "100") && (ColumnId != "200")) { var widgetmaxheight = params[5]; }
				if (ColumnId == "200") { var widgetmaxheight = params[9]; }
				
				maxWidthOffset = widgetmaxwidth;
				$(this).resizable("option","maxWidth",widgetmaxwidth-5);
				$(this).resizable("option","maxHeight",widgetmaxheight);
			}
		},
		resize: function(e, ui) {
			if ($(this).find(".dashboard_widgetheader").outerWidth() < $(this).find(".dashboard_content").children().outerWidth()) {$(this).resizable("option","minWidth", $(this).find(".dashboard_content").children().outerWidth()+5 ); }
			if ($(this).find(".dashboard_widget").outerHeight() < $(this).find(".dashboard_widgetinner").outerHeight()) { $(this).resizable("option","minHeight",  $(this).find(".dashboard_widgetinner").outerHeight()); }
		},
		stop: function() { 
			saveOrder(); 
		},
		grid: grid ? [grid,grid] : false
	});
}

function dashboard_openModal(tabid) {
	$("#dashboard-dialog-tabs").tabs();
	$("#tabID").html("TabID: "+tabid);
	$("#tabTitle").val(DashboardConfigHash['dashboard_tab'+(tabid+1)+'name']);
	$("#tabGroups").val(DashboardConfigHash['dashboard_tab'+(tabid+1)+'groups']);
	$("#tabIcon").val(DashboardConfigHash['dashboard_tab'+(tabid+1)+'icon']);
	$("#tabIconColor").val(DashboardConfigHash['dashboard_tab'+(tabid+1)+'iconcolor']);
	$('#tabIconColor').colorpicker({color: $("#tabIconColor").val(), history: false});	
	if (DashboardConfigHash['dashboard_activetab'] == (tabid+1)) { $('#tabActiveTab').prop('checked', 'checked'); } else { $('#tabActiveTab').removeAttr('checked'); }

	$("#tabEdit").dialog( { 
		modal: true, 
		title: "Dashboard-Tab Details",
		resizable: false,
		width:350,
		buttons: {
			"Ok": function() {
					if ($("#tabTitle").val() != "") {dashboard_setAttribute('dashboard_tab'+(tabid+1)+'name', $("#tabTitle").val());}	
					else if (DashboardConfigHash['dashboard_tab'+(tabid+1)+'name']) {dashboard_delAttribute('dashboard_tab'+(tabid+1)+'name');}					
					if ($("#tabGroups").val() != "") {dashboard_setAttribute('dashboard_tab'+(tabid+1)+'groups', $("#tabGroups").val());	} 
					else if (DashboardConfigHash['dashboard_tab'+(tabid+1)+'groups']) {dashboard_delAttribute('dashboard_tab'+(tabid+1)+'groups');}
					if ($("#tabIcon").val() != "") {
						var color = $("#tabIconColor").val();
						if (color.substr(0,1) == '#') {	color = "%23"+color.substr(1,color.length);}
						if (color != "") {dashboard_setAttribute('dashboard_tab'+(tabid+1)+'icon', $("#tabIcon").val()+'@'+color);}
						else {dashboard_setAttribute('dashboard_tab'+(tabid+1)+'icon', $("#tabIcon").val());}					
					} else if (DashboardConfigHash['dashboard_tab'+(tabid+1)+'icon']) {dashboard_delAttribute('dashboard_tab'+(tabid+1)+'icon');}					
					if ($('#tabActiveTab').is(':checked')) {dashboard_setAttribute('dashboard_activetab', tabid+1);	}
					setTimeout(dashboard_reloadpage, 1500);
					$(this).dialog("close");
					$(this).dialog("destroy");
				},
			"Cancel": function() {
					$(this).dialog("close");
					$(this).dialog("destroy");
				}
		},
		create: function( event, ui ) {
			$(this).parent().attr('id', "dashboard-dialog");
			$(this).parent().removeClass().addClass( "dashboard dashboard-dialog ui-dialog ui-widget ui-widget-content ui-corner-all ui-front ui-dialog-buttons ui-draggable" ); 
		}
	});
}

function adddashboardButton(position, text, id, hint) {
    $("#" + id).button();
	var my_button = '<span id="' + id + '" title="'+hint+'" class="dashboard dashboard-button dashboard-button-custom dashboard-button-'+id+' dashboard-state-default" style="">'+text+'</span>';
	$("#dashboard_tabnav").prepend(my_button);	 
}

function dashboard_buildButtons() {
	adddashboardButton("top", "", "defineDetails", "Show Details");
	$("#defineDetails").click(function () {location.href=fhemUrl+'?detail='+DashboardConfigHash['name'];});
	
	if (DashboardConfigHash['lockstate']  != "lock"){
		adddashboardButton("top", "", "setPosition", "Set Position");
		$("#setPosition").button({disabled: true});		
		$("#setPosition").click(function () {dashboard_setposition()});	
		
		adddashboardButton("top", "", "editTab", "Edit Tab");	
		$("#editTab").click(function () {dashboard_openModal($( "#dashboardtabs" ).tabs( "option", "active" ))});
	}
	if (DashboardConfigHash['dashboard_showfullsize'] == 1) {
		adddashboardButton("top", "", "goBack", "Back");
		//$("body").addClass("hideMenu");
		$("#goBack").click(function () {location.href=fhemUrl;});
	}
	
	//adddashboardButton("top", "", "testButton", "TEST");
	//$("#testButton").click(function () {dashboard_test()});

	$(".dashboard_tab").click(function () {
		var tabIndex = $(this).parent().children('li').index(this);
		dashboard_load_tab(tabIndex);
	});
}

function dashboard_load_tab(tabIndex) {
	// in case the tab is already loaded, do nothing
        if ($('#dashboard_tab' + tabIndex).length) {
		return;
        }
    
	if (typeof(fhemUrl) !== 'undefined') {
		dashboard_getData(
			fhemUrl+"?cmd=get "+$('#dashboard_define').text(),
			"tab " + tabIndex,
			"html",
			function (tabIndex, data) {
				dashboard_insert_tab(tabIndex, data);
			}.bind(null, tabIndex)
		);
	}
}

function dashboard_insert_tab(tabIndex, content) {
  $('#dashboardtabs').append(content);
  $("#dashboardtabs").tabs('refresh');

  // call FHEM specific widget replacement
  FW_replaceWidgets($("#dashboard_tab" + tabIndex));

  dashboard_init_tab(tabIndex);
}

function dashboard_init_tab(tabIndex) {
	if (DashboardConfigHash['dashboard_showtogglebuttons'] == 1){ //ToggleButton show/hide	
		$("#dashboard_tab" + tabIndex + " .dashboard_widget")
				.addClass( "dashboard_widget ui-corner-all" )
				.find(".dashboard_widgetheader")
				.addClass( "dashboard_widgetheader ui-corner-all" )
				.prepend('<span class="dashboard_button_icon dashboard_button_iconminus"></span>')  
				.end();
	
		$("#dashboard_tab" + tabIndex + " .dashboard_widgetheader .dashboard_button_icon").click(function(event) {				
			if ($(this).hasClass("dashboard_button_iconplus")) {
				showGroupForButton(this);			
			} else {
				hideGroupForButton(this);			
			}				 
			//saveOrder();
			event.stopImmediatePropagation();
		});
	} else { $("#dashboard_tab" + tabIndex + " .dashboard_widgetheader").addClass( "dashboard_widgetheader ui-corner-all" );}

	  // call FHEMWEB specific link replacement
	  $("#dashboard_tab" + tabIndex + " a").each(function() { FW_replaceLink(this); });

	  restoreOrder(tabIndex);
	  if (gridSize = is_dashboard_flexible()) {
		  var $container = $("#dashboard_rowcenter_tab" + tabIndex);
		  $("#dashboard_tab" + tabIndex + " .dashboard_widget").draggable({
			cursor: 'move',
			grid: [gridSize,gridSize],
			containment: [$container.offset().left,$container.offset().top],
			stop: function() { saveOrder(); }
		  });
	  }
	  else {
		  $("#dashboard_tab" + tabIndex + " .dashboard_column").sortable({
			connectWith: ['.dashboard_column', '.ui-row'],
			cursor: 'move',
			tolerance: 'pointer',
		stop: function() { saveOrder(); }
		  });
	  }
	  makeResizable('#dashboard_tab' + tabIndex + ' .dashboard_widget');

	  // call the initialization of reading groups
	  FW_readingsGroupReadyFn($('#dashboard_tab' + tabIndex));

	  if ((DashboardConfigHash['lockstate']  == "lock") || (dashboard_buttonbar == "hidden")) {
		dashboard_setlock(tabIndex);
	  } else {
		dashboard_unsetlock(tabIndex);
	  }
	  restoreGroupVisibility(tabIndex);
}

function restoreGroupVisibility(tabId) {
  $("#dashboard_tab" + tabId + ' .dashboard_button_icon').each(function(index, button) {
	var $parentElement = $(button).parents(".dashboard_widget:first");
        var id = $parentElement.attr('id');
        if ($.cookie(id + '_hidden')) {
		hideGroupForButton(button);
        }
  });
}

function hideGroupForButton(button) {
	$(button).removeClass( "dashboard_button_iconminus" );
	$(button).addClass( "dashboard_button_iconplus" );			
	var $parentElement = $(button).parents(".dashboard_widget:first");
	var currHeight = Math.round($parentElement.height());
	$parentElement.find(".dashboard_content").data("userheight", currHeight);
	$parentElement.find(".dashboard_content").hide();	
	var newHeight = $parentElement.find(".dashboard_widgetinner").height()+5;
	$parentElement.height(newHeight);
				
	$(button).parent().removeClass("dashboard_widgetmax");			
	$(button).parent().addClass("dashboard_widgetmin");
	$.cookie($parentElement.attr('id') + '_hidden', '1', {expires : 365});
}

function showGroupForButton(button) {
	$(button).removeClass( "dashboard_button_iconplus" );
	var $parentElement = $(button).parents(".dashboard_widget:first");
        $(button).addClass( "dashboard_button_iconminus" );
        $parentElement.find(".dashboard_content").show();
        var newHeigth = $parentElement.find(".dashboard_content").data("userheight");

        $(button).parent().removeClass("dashboard_widgetmin");
        $(button).parent().addClass("dashboard_widgetmax");

        //-------- set heigh only if > group min. height -------------
        if ($(button).parents(".dashboard_widgetinner").outerHeight() > newHeigth) {
        	$parentElement.outerHeight($(button).parents(".dashboard_widgetinner").outerHeight()+10);
        } else { $parentElement.outerHeight(newHeigth);}
        //------------------------------------------------------------
	$.removeCookie($parentElement.attr('id') + '_hidden');
}

function dashboard_buildDashboard(){
	var params = dashboard_get_params();
	dashboard_buttonbar = params[4];


        if (DashboardConfigHash['dashboard_showfullsize'] == 1){ //disable roomlist and header	
		//$("#menuScrollArea").remove();
		//$("#hdr").remove();
		//$(".roomoverview:first").remove();
		//$("br:first").remove();
		//$("#content").css({position:   'inherit', 'overflow' : 'visible', 'float' : 'none', 'width' : '100%', 'height' : '100%', 'padding' : '0px', 'border' : 'none'});
	}
		
	//--------------------------------- Dashboard Tabs ------------------------------------------------------------------------------
	$("#dashboardtabs").tabs({
		active: 0,
		create: function(event, ui) { 
			/*$( "#dashboardtabs" ).tabs( "option", "active", 2);//set active Tab
			restoreOrder(); 
			restoreGroupVisibility(0);*/
		},
		activate: function (event, ui) {
			var tabIndex = ui.newTab.parent().children('li').index(ui.newTab);
			$.cookie('dashboard_activetab', tabIndex + 1, {expires : 365});
			//restoreOrder(tabIndex); 
			//restoreGroupVisibility(tabIndex);
		}		
	});	

        var iActiveTab = getTabIndexFromTab($('#dashboardtabs .dashboard_tabpanel'));
        
	$( "#dashboardtabs" ).tabs( "option", "active", iActiveTab);//set active Tab
	dashboard_init_tab(iActiveTab);
	restoreOrder(iActiveTab); 
	restoreGroupVisibility(iActiveTab);

	if ($("#dashboard_tabnav").hasClass("dashboard_tabnav_bottom")) { $(".dashboard_tabnav").appendTo(".dashboard_tabs"); } //set Tabs on the Bottom	
	$(".dashboard_tab_hidden").css("display", "none"); //hide Tabs

	//---------------------- Dashboard Tab Icons ---------------------------------------------------
		for ( var i = 0, n = $('#dashboardtabs >ul >li').size(); i < n; i++ ) {		
			if (DashboardConfigHash['dashboard_tab'+(i+1)+'icon']) {
				if (DashboardConfigHash['dashboard_tab'+(i+1)+'iconcolor']) {
					var svgColor = DashboardConfigHash['dashboard_tab'+(i+1)+'iconcolor'];
				} else {
					svgColor = "#FFFFFF";
				}

				$('#dashboardtabs ul:first li:eq('+i+')').children().prepend('<a id="dashboard_tab'+(i+1)+'icon"/>');
				//dashboard_loadsvgIcon(DashboardConfigHash['dashboard_tab'+(i+1)+'icon'], svgColor, "#dashboard_tab"+(i+1)+"icon");
 				dashboard_showsvgIcon (
					fhemUrl + '?cmd=get ' + $('#dashboard_define').text() + ' icon ' + DashboardConfigHash['dashboard_tab'+(i+1)+'icon'],
					svgColor, "#dashboard_tab"+(i+1)+"icon"
				);
			}		
		}
	//-----------------------------------------------------------------------------------------------
	//-------------------------------------------------------------------------------------------------------------------------------------		

  	if (gridSize = is_dashboard_flexible()) {
		  var $container = $(".dashboard_rowcenter");
		  $(".dashboard_widget").draggable({
			cursor: 'move',
			grid: [gridSize,gridSize],
			containment: [$container.offset().left,$container.offset().top],
			stop: function() { saveOrder(); }
		  });
	}
	else {
		$(".dashboard_column").sortable({
			connectWith: ['.dashboard_column', '.ui-row'],
			cursor: 'move',
			tolerance: 'pointer',
			stop: function() { saveOrder(); }
		});
	}

	dashboard_modifyWidget();
	if (dashboard_buttonbar != "hidden") dashboard_buildButtons();
	if ((DashboardConfigHash['lockstate']  == "lock") || (dashboard_buttonbar == "hidden")) {dashboard_setlock(iActiveTab);} else {dashboard_unsetlock(iActiveTab);}	
	if (DashboardConfigHash['dashboard_customcss']) {$('<style type="text/css">'+DashboardConfigHash['dashboard_customcss']+'</style>').appendTo($('head')); }	
}

$(document).ready( function () {
  var dbattr = document.getElementById("dashboard_attr");
  if (dbattr) {
	$("body").attr("longpollfilter", ".*") //need for longpoll
	//--------------------------------- Attribute des Dashboards ------------------------------------------------------------------
	dashboard_getData(fhemUrl + "?cmd=get "+$('#dashboard_define').text(), "config", "json", dashboard_buildDashboard);
	//----------------------------------------------------------------------------------------------------------------------------
    	$(window).off('resize');
  }	
});
