//########################################################################################
// dashboard.js
//########################################################################################
// Released : 14.11.2013 @svenson08
// Version : 
// 1.01: Released to testers 
// 1.02: Add DebugMsg. Fix independent Groupsize adjustment after set & siterefresh. Fix
//			wrong set of +Toogle Icon on Siderefresh
// 2.00: First Changes vor Dashboard Tabs. Change method store Positiondata. optimization restore Positiondata. Clear poor routines.
//			  Change max/min Values for Groupresize.	Top- and Bottom-Row always 100%
// 2.01: Add Longpoll function. Dashboard can hide FHEMWEB Roomliste and Header.
// 2.02: Tabs can set on top, bottom or hidden
// 2.03: Fix showhelper Bug on lock/unlock. The error that after a trigger action the curren tab is changed to the "old" activetab tab has 
//			 been fixed.
// 2.04: Dashboard position near Top in showfullsize-mode. Restore ActiveTab funktion
// 2.05: Delete function for set lockstate
//
// Known Bugs/Todo's
// See 95_Dashboard.pm
//########################################################################################
//########################################################################################

function saveOrder() {
	var EndSaveResult = "";
	var ActiveTab = $("#tabs .ui-tabs-panel:visible").attr("id").substring(14,13);	
	//------------------- Build new Position string ----------------------
    $(".dashboard_column").each(function(index, value){        
		var colid = value.id;
		var SaveResult = "";
		var neworder = $('#' + colid).sortable("toArray");		
		for ( var i = 0, n = neworder.length; i < n; i++ ) {
			var tab = $('#' + neworder[i]).parent().attr("id").substring(14,13); 
			var column = $('#' + neworder[i]).parent().attr("id").substring(20);	
			if (ActiveTab == tab) {
				var groupdata = ($('#' + neworder[i]).data("groupwidget").split(",")); //get curren Group-Configuration			
				if (groupdata[1] != ''){
					groupdata[0] = "t"+tab+"c"+$('#' + neworder[i]).parent().attr("id").substring(20);
					groupdata[2] = $('#' + neworder[i]).find('.dashboard_content').is(':visible');
					groupdata[3] = $('#' + neworder[i]).outerWidth();				
					
					if (groupdata[4] == 0) {groupdata[4] = $('#' + neworder[i]).outerHeight();}
					if (groupdata[2] == true) {	
						groupdata[4] = $('#' + neworder[i]).outerHeight();
						$('#' + neworder[i]).find(".dashboard_content").data("userheight", $('#' + neworder[i]).outerHeight()); 
					}								
					$(neworder[i]).data("groupwidget",groupdata); //store in current Widget
					SaveResult = SaveResult+groupdata+":";
				}				
			}
		}		
		if (SaveResult != ""){ EndSaveResult = EndSaveResult + SaveResult; } //NewResult: <tab><column>,<portlet-1>,<status>,<height>,<width>,<portlet-n>,<status>,<height>,<width>:<columNumber.....	
    });	
	//------------------------------------------------------------------------		
	//--------------------- Store new Positions ------------------------
	if (EndSaveResult != "") { $("#tabs .ui-tabs-panel:visible").data("tabwidgets",EndSaveResult); } //store widgetposition in active tab Widget
	document.getElementById("dashboard_button_set").classList.add('dashboard_button_changed'); //Mark that the Changes are not saved
	//------------------------------------------------------------------------
}

function restoreOrder() {
 var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
 var ActiveTab = $("#tabs .ui-tabs-panel:visible");
 var ActiveTabId = ActiveTab.attr("id").substring(14,13);
 var aColWidth = GetColWidth(params[7],params[12]);

 //--------------------------------------------- Set Row and Column Settings --------------------------------------------------------------------------------------------
 $("#dashboard").width(params[1]);
 if (ActiveTab.has("#dashboard_rowtop_tab"+ActiveTabId).length){ $("#dashboard_rowtop_tab"+ActiveTabId).height(params[8]);  }
 if (ActiveTab.has("#dashboard_rowcenter_tab"+ActiveTabId).length){ $("#dashboard_rowcenter_tab"+ActiveTabId).height(params[5]); } 
 if (ActiveTab.has("#dashboard_rowbottom_tab"+ActiveTabId).length){ $("#dashboard_rowbottom_tab"+ActiveTabId).height(params[9]); } 

 for (var i = 0, n = params[7]; i <= n; i++) {  
	if (ActiveTab.has("#dashboard_tab"+ActiveTabId+"column"+i).length) { $("#dashboard_tab"+ActiveTabId+"column"+i).width(aColWidth[i]+"%"); }
 }	
 if (params[2] == 1) { $(".ui-row").addClass("dashboard_columnhelper"); } else { $(".ui-row").removeClass("dashboard_columnhelper"); }//set showhelper
 //--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
     
 $(".dashboard_widget").each(function(index, value) {
	var groupdata = $(this).data("groupwidget").split(","); //get the position string from the data
	var TabId = groupdata[0].substring(1,2);
	var ColumnId = groupdata[0].substring(3,groupdata[0].length);
	
	if (TabId == ActiveTabId){ //Restore only for the current active tab
		var groupname = groupdata[1];
		var visible = groupdata[2];
		var width = groupdata[3];
		var height = groupdata[4];		

		//---------- Max. Width of an Group. Reduce group-with if need | Min. Width if need ----------	
		var widgetmaxwidth = $(this).parent().width();
		if (width == 0) { width = $(this).find(".dashboard_content").children().outerWidth()+10;}   
		if (width > widgetmaxwidth) {width = widgetmaxwidth}; //width is =< columnwith
		$(this).outerWidth(width);
		//---------------------------------------------------------------------------------------------------------------	
		//-------------------------------- Height of an Group. | Min. Height if need ---------------------------	
		if (height == 0) { height = $(this).outerHeight();}		
		if ($(this).outerHeight() > height) {$(this).outerHeight(height); } //set heigh only if > group min. height
		//---------------------------------------------------------------------------------------------------------------	
		
		$(this).find(".dashboard_content").data("userheight", height-5);		
		if (params[2] == 1) { $(this).addClass("dashboard_widgethelper"); } else { $(this).removeClass("dashboard_widgethelper"); }//Show Widget-Helper Frame
		
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

 aColWidth[0] = parseInt(aColWidth[0])-(0.2 * ColCount);
 return aColWidth;
}

//Only use for debugging
function showdebugMessage(msg){
	document.getElementById("dashboard_jsdebug").value = msg;
}

function dashboard_setlock(){
	$("#dashboard_button_lock").prepend('<span class="dashboard_button_icon dashboard_button_iconlock"></span>');  
	//############################################################
	$( ".dashboard_column" ).sortable( "option", "disabled", true );
	$( ".dashboard_widget" ).removeClass("dashboard_widgethelper");
	if ($( ".dashboard_widget" ).hasClass("ui-resizable")) { $( ".dashboard_widget" ).resizable("destroy"); };
	$( ".dashboard_column" ).removeClass("dashboard_columnhelper");
	//############################################################
}

function dashboard_unsetlock(){
	var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration

	$("#dashboard_button_lock").prepend('<span class="dashboard_button_icon dashboard_button_iconunlock"></span>');
	//############################################################
	$( ".dashboard_column" ).sortable( "option", "disabled", false );
	if (params[2] == 1) { $( ".dashboard_widget" ).addClass("dashboard_widgethelper"); } else { $( ".dashboard_widget" ).removeClass("dashboard_widgethelper"); }//Show Widget-Helper Frame
	if (params[2] == 1) { $( ".dashboard_column" ).addClass("dashboard_columnhelper"); } else { $( ".dashboard_column" ).removeClass("dashboard_columnhelper"); }//Show Widget-Helper Frame

	dashboard_modifyWidget();
	//############################################################
}

function dashboard_setposition(){ 
 var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
 //------------------- store group position ----------------------------
 for (var i = 0, n = params[10]; i < n; i++ ) {
	if ($("#dashboard_tab"+i).data("tabwidgets") != null) {	
		var j = i+1;
		FW_cmd(document.location.pathname+'?XHR=1&cmd.'+params[0]+'=attr '+params[0]+' dashboard_tab'+j+'sorting '+$("#dashboard_tab"+i).data("tabwidgets"));
	}
 }
 document.getElementById("dashboard_button_set").classList.remove('dashboard_button_changed'); 
 //--------------------------------------------------------------------- 
 //--------------------- store active Tab ------------------------------
 var activeTab = ($( "#tabs" ).tabs( "option", "active" ))+1;
 if (params[11] != activeTab){
	FW_cmd(document.location.pathname+'?XHR=1&cmd.'+params[0]+'=attr '+params[0]+' dashboard_activetab '+activeTab);
 }
 //--------------------------------------------------------------------- 
}

function dashboard_modifyWidget(){
		$( ".dashboard_widget" ).resizable({ 
			'grid': 5,
			start: function(e, ui) {
				var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
				var groupdata = $(this).data("groupwidget").split(","); //get the position string from the data
				var TabId = $(this).parent().attr("id").substring(14,13);
				var ColumnId = $(this).parent().attr("id").substring(20);	
				var widgetmaxwidth = $(this).parent().width();
				
				if (ColumnId == "100") { var widgetmaxheight = params[8]; }
				if ((ColumnId != "100") && (ColumnId != "200")) { var widgetmaxheight = params[5]; }
				if (ColumnId == "200") { var widgetmaxheight = params[9]; }
				
				maxWidthOffset = widgetmaxwidth;
				$(this).resizable("option","maxWidth",widgetmaxwidth-5);
				$(this).resizable("option","maxHeight",widgetmaxheight);
			},
			resize: function(e, ui) {
				if ($(this).find(".dashboard_widgetheader").outerWidth() < $(this).find(".dashboard_content").children().outerWidth()) {$(this).resizable("option","minWidth", $(this).find(".dashboard_content").children().outerWidth()+5 ); }
				if ($(this).find(".dashboard_widget").outerHeight() < $(this).find(".dashboard_widgetinner").outerHeight()) { $(this).resizable("option","minHeight",  $(this).find(".dashboard_widgetinner").outerHeight()); }
			},
			stop: function() { 
				saveOrder(); 
			} 
		});		
}

$(document).ready( function () {
  var dbattr = document.getElementById("dashboard_attr");
  if (dbattr) {
	//--------------------------------- Attribute des Dashboards ------------------------------------------------------------------
	var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
	//-------------------------------------------------------------------------------------------------------------------------------------
	$("body").attr("longpollfilter", ".*") //need for longpoll

	if (params[13] == 1){ //disable roomlist and header	
		$("#menuScrollArea").remove();
		$("#hdr").remove();
		$(".roomoverview:first").remove();
		$("br:first").remove();
		$("#content").css({position:   'inherit'});	
	}
	
    $(".dashboard_column").sortable({
        connectWith: ['.dashboard_column', '.ui-row'],
		cursor: 'move',
        stop: function() { saveOrder(); }
    }); 
	
	if (params[4] == "hidden") {	
		dashboard_modifyWidget();
		dashboard_setlock();		
	} 

	if (params[6] == 1){ //ToogleButton show/hide	
		$(".dashboard_widget")
				.addClass( "dashboard_widget ui-corner-all" )
				.find(".dashboard_widgetheader")
				.addClass( "dashboard_widgetheader ui-corner-all" )
				.prepend('<span class="dashboard_button_icon dashboard_button_iconminus"></span>')  
				.end();
	
		$(".dashboard_widgetheader .dashboard_button_icon").click(function(event) {				
			if ($(this).hasClass("dashboard_button_iconplus")) {
				$(this).removeClass( "dashboard_button_iconplus" );
				$(this).addClass( "dashboard_button_iconminus" );
				$(this).parents(".dashboard_widget:first").find(".dashboard_content").show();				
				var newHeigth = $(this).parents(".dashboard_widget:first").find(".dashboard_content").data("userheight");				
				
				$(this).parent().removeClass("dashboard_widgetmin");			
				$(this).parent().addClass("dashboard_widgetmax");

				
				//-------- set heigh only if > group min. height -------------
				if ($(this).parents(".dashboard_widgetinner").outerHeight() > newHeigth) { 
					$(this).parents(".dashboard_widget:first").outerHeight($(this).parents(".dashboard_widgetinner").outerHeight()+10); 
				} else { $(this).parents(".dashboard_widget:first").outerHeight(newHeigth);}
				//------------------------------------------------------------
			} else {
				$(this).removeClass( "dashboard_button_iconminus" );
				$(this).addClass( "dashboard_button_iconplus" );			
				var currHeigth = Math.round($(this).parents(".dashboard_widget:first").height());
				$(this).parents(".dashboard_widget:first").find(".dashboard_content").data("userheight", currHeigth);
				$(this).parents(".dashboard_widget:first").find(".dashboard_content").hide();	
				var newHeigth = $(this).parents(".dashboard_widget:first").find(".dashboard_widgetinner").height()+5;
				$(this).parents(".dashboard_widget:first").height(newHeigth);		
				
				$(this).parent().removeClass("dashboard_widgetmax");			
				$(this).parent().addClass("dashboard_widgetmin");
			}				 
			saveOrder();
			event.stopImmediatePropagation();
		});
	}
		
	//--------------------------------- Dashboard Tabs ------------------------------------------------------------------------------
	$("#tabs").tabs({
		active: 0,
		create: function(event, ui) { 
			$( "#tabs" ).tabs( "option", "active", params[11]-1 ); //set active Tab
			restoreOrder(); 
			},
		activate: function (event, ui) {
			restoreOrder(); 
		}   
	});	
	if ($("#dashboard_tabnav").hasClass("dashboard_tabnav_bottom")) { $(".dashboard_tabnav").appendTo(".dashboard_tabs"); } //set Tabs on the Bottom	
	$(".dashboard_tab_hidden").css("display", "none"); //hide Tabs
	//-------------------------------------------------------------------------------------------------------------------------------------		
	
	
	$("#dashboard_button_set").button({
		create: function( event, ui ) {
			$(this).addClass("dashboard_button_iconset");
		}
	});
	
	$("#dashboard_button_detail").button({
		create: function( event, ui ) {
			$(this).addClass("dashboard_button_icondetail");
		}
	});	
	
	dashboard_modifyWidget();
	if (params[3] == "lock") {dashboard_setlock();} else {dashboard_unsetlock();}	
	if (params[14] != "none" ) {$('<style type="text/css">'+params[14]+'</style>').appendTo($('head')); }
  }	
});