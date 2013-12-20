//########################################################################################
// dashboard.js
//########################################################################################
// Released : 14.11.2013 @svenson08
// Version  : 1.00
// Revisions:
// 0001: Released to testers 
// 0002: Add DebugMsg. Fix independent Groupsize adjustment after set & siterefresh.
//       First Release to FHEM SVN
//
//
// Known Bugs/Todo's
// See 95_Dashboard.pm
//########################################################################################

function saveOrder() {
    var SaveResult = "";
	//------------- Build new Position string ---------------
    $(".dashboard_column").each(function(index, value){        
		var colid = value.id;
        var order = $('#' + colid).sortable("toArray");
        for ( var i = 0, n = order.length; i < n; i++ ) {
            var v = $('#' + order[i]).find('.dashboard_content').is(':visible');
			var w = $('#' + order[i]).outerWidth();
			if ( $('#' + order[i]).find(".dashboard_content").data("userheight") == null ) { 
				var h = $('#' + order[i]).outerHeight(); 
			} else {
				var h = $('#' + order[i]).find(".dashboard_content").data("userheight"); 
				if (h.length == 0) { var h = $('#' + order[i]).outerHeight(); }
			}
            order[i] = order[i]+","+v+","+h+","+w;	
        }
		SaveResult = SaveResult + index+','+order+':';
		//Result: <ColumNumber>,<portlet-1>,<status>,<height>,<width>,<portlet-n>,<status>,<height>,<width>:<columNumber.....		
    });	
	//-------------------------------------------------------	
	//------------ Set the new href String ------------------
	document.getElementById("dashboard_currentsorting").value = SaveResult;	
	if (document.getElementById("dashboard_button_set")) {
		document.getElementById("dashboard_button_set").classList.add('dashboard_button_changed'); //Mark that the Changes are not saved
	}
	//-------------------------------------------------------
}

function restoreOrder() {
  $(".dashboard_column").each(function(index, value) {
	var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
	var coldata = (document.getElementById("dashboard_currentsorting").value).split(":");	//get the position string from the hiddenfield
	var rowwidth = params[7] * params[1];
	//------------------------------------------------------------

	$(".dashboard_column").width(params[1]); //Set Columwidth
	$(".ui-row").width(rowwidth); //Set Rowwidth
	if (value.id == "sortablecolumn100") { //Set RowHeight
		$('#' + value.id).height(params[8]); 
		$('#' + value.id).width(rowwidth);
		var widgetmaxwidth = rowwidth;
	} else {
		if (value.id == "sortablecolumn200") { 
			$('#' + value.id).height(params[9]);
			$('#' + value.id).width(rowwidth);
			var widgetmaxwidth = rowwidth;
		} else { 
			$('#' + value.id).height(params[5]); 
			var widgetmaxwidth = params[1];
		}
	}
	
	if (params[2] == 1) { $(".dashboard_column").addClass("dashboard_columnhelper"); } else { $(".dashboard_column").removeClass("dashboard_columnhelper"); }//set helperclass

	for (var i = 0, n = coldata.length; i < n; i++ ) { //for each column (Value = 1,name1,state1,name2,state2)
		var portletsdata = coldata[i].split(","); //protlet array / all portlets in this (=index) column
		
		//alert("Load Event (1) \nColumn="+index+"\nSaveResult="+coldata+"\nColumndata=("+i+"/"+coldata.length+") "+portletsdata);
		for (var j = 1, m = portletsdata.length; j < m; j += 4 ) { 
			//alert("Load Event (2) \nColumn="+index+"\nSaveResult="+coldata+"\nColumndata=("+i+"/"+coldata.length+"|"+j+"/"+portletsdata.length+") "+portletsdata+
			//"\n\nPortletdata (ID)="+portletsdata[j]+"\nPortletdata (Visible)="+portletsdata[j+1]+"\nPortletheight (Height)="+portletsdata[j+2]+"\nPortletwidth (Width)="+portletsdata[j+3]);	
			if (portletsdata[0] == index && portletsdata[0] != '' && portletsdata[j] != '' && portletsdata[j+1] != '') {
				var portletID = portletsdata[j];
				var visible   = portletsdata[j+1];
				var height    = portletsdata[j+2]-5; //( limited -5 by CSS)
				var width     = portletsdata[j+3]-5; //( limited -5 by CSS)

				if (width > widgetmaxwidth) {width = widgetmaxwidth}; //Fix with ist widget width > current column width.
				var portlet = $(".dashboard_column").find('#' + portletID);
				portlet.appendTo($('#' + value.id));				
				portlet.outerHeight(height);					
				portlet.outerWidth(width);					
				if (params[2] == 1) { portlet.addClass("dashboard_widgethelper"); } else { portlet.removeClass("dashboard_widgethelper"); }//Show Widget-Helper Frame
				if (visible === 'false') {			
// Icon plus is not set on restore order, why?
				if (portlet.find(".dashboard_widgetheader").find(".dashboard_button_icon").hasClass("dashboard_button_iconminus")) { 
						portlet.find(".dashboard_widgetheader").find(".dashboard_button_icon").removeClass( "dashboard_button_iconminus" ); 
						portlet.find(".dashboard_widgetheader").find(".dashboard_button_icon").addClass( "dashboard_button_iconplus" ); 
					}
					var currHeigth = Math.round(portlet.height());
					portlet.find(".dashboard_content").data("userheight", currHeigth);
					portlet.find(".dashboard_content").hide();	
					var newHeigth = portlet.find(".dashboard_widgetinner").height()+5;		
					portlet.height(newHeigth);								
				}
			}
		}	
	} 
  });	
} 

//Only use vor debugging
function showdebugMessage(msg){
	document.getElementById("dashboard_jsdebug").value = document.getElementById("dashboard_jsdebug").value+" "+msg;
}

function dashboard_tooglelock(){
 var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
 if (params[3] == "lock"){ //current state lock, do unlock
	params[3] = "unlock"; 	
	$("#dashboard_button_lock").button( "option", "label", "Lock" );
	dashboard_unsetlock();
 } else { //current state unlock, set lock
	params[3] = "lock"; 
	$("#dashboard_button_lock").button( "option", "label", "Unlock" );
	dashboard_setlock();
 } 
 document.getElementById("dashboard_attr").value = params; 
 FW_cmd(document.location.pathname+'?XHR=1&cmd.'+params[0]+'=attr '+params[0]+' dashboard_lockstate '+params[3]);
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
	var sorting = document.getElementById("dashboard_currentsorting").value;
	FW_cmd(document.location.pathname+'?XHR=1&cmd.'+params[0]+'=attr '+params[0]+' dashboard_sorting '+sorting);
	document.getElementById("dashboard_button_set").classList.remove('dashboard_button_changed'); 
}

function dashboard_modifyWidget(){
		$( ".dashboard_widget" ).resizable({ 
			'grid': 1,
			'minWidth':  150,
			start: function(e, ui) {
				var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
				//-------- Widgetbegrenzung festlegen -------------------
				var rowid = $(this).parent().attr("id");
				if (rowid == "sortablecolumn100") { 
					var widgetmaxwidth = (params[7] * params[1]) - 5; 
					var widgetmaxheight = params[8] - 5;
				}
				else { if (rowid == "sortablecolumn200") { 
						var widgetmaxwidth = (params[7] * params[1]) - 5; 
						var widgetmaxheight = params[9] -5 ;
					 }
					   else { 
						var widgetmaxwidth = params[1] - 5;
						var widgetmaxheight = params[5] -5;						
					   }	
				}
				//-------------------------------------------------------
				
				maxWidthOffset = widgetmaxwidth;
				$(this).resizable("option","maxWidth",widgetmaxwidth);
				$(this).resizable("option","maxHeight",widgetmaxheight);
			},
			resize: function(e, ui) {
				minHeightOffset = $(this).find(".dashboard_widgetinner").height()+5;
				ui.size.width = Math.round(ui.size.width);
				if (ui.size.width > (maxWidthOffset)) {	$(this).resizable("option","maxWidth",maxWidthOffset); }
				if (ui.size.height < (minHeightOffset)) { $(this).resizable("option","minHeight",minHeightOffset); }	
			},
			stop: function() { 
				minHeightOffset = $(this).find(".dashboard_widgetinner").height()+5;
				$(this).resizable("option","minHeight",minHeightOffset);
				saveOrder(); 
			} 
		});		
}

$(document).ready( function () {
	var params = (document.getElementById("dashboard_attr").value).split(","); //get current Configuration
	
    $(".dashboard_column").sortable({
        connectWith: ['.dashboard_column', '.ui-row'],
        stop: function() { saveOrder(); }
    }); 

	if (params[4] == 0){ //set if buttonbar not show
		dashboard_modifyWidget();
		dashboard_setlock();		
	} 

    restoreOrder(); 

	if (params[6] == 1){ //ToogleButton show/hide	
		$(".dashboard_widget")
				.addClass( "dashboard_widget dashboard_content ui-corner-all" )
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
			} else {
				$(this).removeClass( "dashboard_button_iconminus" );
				$(this).addClass( "dashboard_button_iconplus" );			
				var currHeigth = Math.round($(this).parents(".dashboard_widget:first").height());
				$(this).parents(".dashboard_widget:first").find(".dashboard_content").data("userheight", currHeigth);
				$(this).parents(".dashboard_widget:first").find(".dashboard_content").hide();	
				var newHeigth = $(this).parents(".dashboard_widget:first").find(".dashboard_widgetinner").height()+5;			
			}				 
			$(this).parents(".dashboard_widget:first").height(newHeigth);
			saveOrder();
			event.stopImmediatePropagation();
		});
	}

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
	
	$("#dashboard_button_lock").button({
		create: function( event, ui ) {
			dashboard_modifyWidget();
			if (params[3] == "lock") { 
				$(this).button( "option", "label", "Unlock" );
				dashboard_setlock(); 
			} else {
				$(this).button( "option", "label", "Lock" );
				dashboard_unsetlock();				
			}
		}
	});
});




