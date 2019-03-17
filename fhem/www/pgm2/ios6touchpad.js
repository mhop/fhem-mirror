/* iOS 6 Theme for FHEM */
/* by Sandra Ohmayer */
/* http://www.foodcat.de */
/* jQuery is required*/


$(document).ready(function() {
	/* 
	/* Style Config
	*/
	var spaltensumme = 200;
	var menuwidth = 200;
	var paddingwidth = 60;
	var mobilepaddingwidth = 20;
	var logowidth = 28;
	var switchtomobilemode = 415;
	var hdrheight = 44;
	var inputpadding = 251;
	/* 
	/* Functions
	*/
	// Set style height and width
	var recalculateStyleHeight = function() {
		var height = window.innerHeight;
		$("#menu").height(height - hdrheight);
		$("#content").height(height - hdrheight);
		$("#right").height(height - hdrheight);
	};
	var recalculateStyleWithMenu = function() {
		var width = $("body").width();
		$("body").removeClass("hideMenu");
		if (switchtomobilemode > width) {
			$("#menu").width(width);
			$("#content").width(0);
			$("#right").width(0);
			$("#content").hide()
			$("#right").hide();
			$("#hdr input").width(width - inputpadding + menuwidth - logowidth);
		} else {
			$("#menu").width(menuwidth);
			$("#content").width(width - menuwidth - paddingwidth - 1);
			$("#right").width(width - menuwidth - paddingwidth - 1);
			$("#hdr input").width(width - inputpadding);
			$("#content").show()
			$("#right").show();
		}
	};
	var recalculateStyleWithoutMenu = function() {
		var width = $("body").width();
		$("body").addClass("hideMenu");
		if (switchtomobilemode > width) {
			$("#hdr input").width(width - inputpadding + menuwidth - logowidth);
			$("#content").width(width - mobilepaddingwidth);
			$("#right").width(width - mobilepaddingwidth);
		} else {
			$("#hdr input").width(width - inputpadding);
			$("#content").width(width - paddingwidth);
			$("#right").width(width - paddingwidth);
		}
		$("#menu").width(0);
		$("#content").show()
		$("#right").show();
	};
	// Show / Hide menu
	var toggleMenuOnFHEMIcon = function() {
		if ($("body").hasClass("hideMenu")) {
			recalculateStyleWithMenu();
			resetcolumns();
			calccolumns();
		} else {
			recalculateStyleWithoutMenu();
			resetcolumns();
			calccolumns();
		}
	};
	
	//Berechnung Spaltenbreite
	var calccolumns = function() {
		$("table.block.wide").find("table.block.wide").addClass("notrelevantcount");
		var tables = $("table.block.wide").not('.notrelevantcount');
		// Ermitteln der maximalen Spaltenanzahl im Layout
		var maxlength = 0;
		var maxtr;
		tables.each(function() {
			var td = $(this).children("tbody").children("tr").first().children("td");
			var trlength = 0;
			td.each(function() {
				trlength = trlength+$(this).prop("colSpan");
			});
			if (trlength > maxlength) {
				maxlength = trlength;
				maxtr=$(this).children("tbody").children("tr").children('td:eq('+(maxlength-1)+')').parent().first();
			}
		});

		// Setzen aller hinteren Spalten auf ein Minimum an Platzbedarf
		tables.children("tbody").children("tr").each(function() {
			var trlength = $(this).children("td").length;
			var diff = 0;
			if (trlength < maxlength) {
				diff = maxlength - trlength;
			}
			diff++;

			$(this).children("td").css("width", "1%");
			$(this).children("td").css("white-space", "nowrap");
			$(this).children("td").first().css("width", "");
			$(this).children("td").first().css("white-space", "");
			
		});

		// Ermitteln der maxwidth abhängig vom größten Spaltenelement beginnend bei Spalte 2 
		var i;
		var maxwidthtd = new Array();
		for (i = 1; i < maxlength; i++) { 
			maxwidthtd.push(0);
			var counttr = tables.children("tbody").children('tr').length;
			for (j=0; j < counttr; j++) {
				tables.children("tbody").children('tr:eq('+j+')').children('td:eq('+i+')').each(function() {
					var tdwidth = $(this).innerWidth()/$(this).prop("colSpan")+($(this).prop("colSpan")-1)*14;
					if (tdwidth > maxwidthtd[i-1]) {
						maxwidthtd[i-1] = tdwidth;
					}
				});
			}
		}

		// Anpassen der width der Spalten auf das maxwidth beginnend bei Spalte 2 
		for (i = 1; i < maxlength; i++) { 
			tables.children("tbody").children("tr").children('td:eq('+i+')').css("width",maxwidthtd[i-1]+"px");
		}

		// Berechnung der gesamten Tabellen width
		var innertablewidth = -20;
		if(maxtr) {
			maxtr.children('td').each(function() {
				innertablewidth=innertablewidth+$(this).innerWidth();
			});
			// Berechnung der hinteren Spalten
			maxwidthtd.forEach(function(column, index){
				if(column > 260) {
					maxwidthtd[index] = 260;
				}
				innertablewidth=innertablewidth-column-10;
			});
			if (innertablewidth > 750) {
				innertablewidth = 750;
			} else if (innertablewidth < 110){
				innertablewidth = 110;
			}
			spaltensumme = innertablewidth;
			tables.children("tbody").children("tr").each(function() {
				var trlength = $(this).children("td").length;
				var diff = 0;
				if (trlength < maxlength) {
					diff = maxlength - trlength;
				}
				diff++;
				$(this).children("td").last().attr('colspan',diff);
				$(this).children("td").css("white-space", "");
				$(this).children("td").css("width", "");
				$(this).children("td").first().css("width", innertablewidth);
				$(this).children("td").first().next().css("width", maxwidthtd[0]);
			});
		}
		$(".fbcalllist-container").find("tr").each(function() {
			$(this).find("td").last().attr('colspan',1);
			$(this).find("td").css("width", "");
			$(this).find("td").css("white-space", "");
		});
		
	};

	//Neuberechnung Spaltenbreite
	var resetcolumns = function() {
		$("table.block.wide").not('.notrelevantcount').children("tbody").children("tr").each(function() {
			$(this).children("td").last().attr('colspan',1);
			$(this).children("td").css("width", "");
			$(this).children("td").css("white-space", "");
		});
	};
	

	var mobiletoggle = function () {
		if($('body').hasClass("colortoggle")){}else{
			var counter=0;
			$( ".colorpicker_widget, .slider_widget" ).each(function(){
				$( '<div id="toggle_colorpicker'+counter+'" onclick="togglecolorpicker('+counter+')" style="display: table-cell;vertical-align: middle;"><svg class="icon control_plus" data-txt="control_plus" id="colorplus'+counter+'" version="1.0" xmlns="http://www.w3.org/2000/svg" width="468pt" height="474pt" viewBox="0 0 468 474" preserveAspectRatio="xMidYMid meet"> <metadata> Created by potrace 1.8, written by Peter Selinger 2001-2007 </metadata> <g transform="translate(0,474) scale(0.200000,-0.200000)" stroke="none"> <path d="M1002 2354 c-18 -9 -43 -31 -55 -48 -22 -31 -22 -35 -25 -458 l-3 -428 -397 0 c-444 0 -443 0 -490 -70 -22 -33 -23 -42 -20 -177 l3 -143 38 -37 37 -38 415 -3 415 -3 0 -422 c0 -403 1 -423 20 -455 37 -61 70 -72 210 -72 150 0 182 12 218 80 22 44 22 49 22 457 l0 413 424 0 c422 0 423 0 456 23 57 39 70 76 70 206 0 143 -19 192 -84 222 -38 17 -73 19 -453 19 l-413 0 0 418 c0 459 0 460 -63 506 -25 18 -45 21 -160 24 -107 2 -138 -1 -165 -14z m258 -599 l0 -475 470 0 470 0 0 -100 0 -100 -475 0 -475 0 0 -475 0 -476 -97 3 -98 3 0 473 0 472 -457 0 -458 0 0 100 0 100 457 2 458 3 -4 473 -3 472 106 0 106 0 0 -475z"></path> </g> </svg><svg class="icon control_minus" id="colorminus'+counter+'" data-txt="control_minus" version="1.0" xmlns="http://www.w3.org/2000/svg" width="468pt" height="95pt" viewBox="0 0 468 95" preserveAspectRatio="xMidYMid meet"> <metadata> Created by potrace 1.8, written by Peter Selinger 2001-2007 </metadata> <g transform="translate(0,95) scale(0.196639,-0.196639)" stroke="none"> <path d="M85 460 c-11 -4 -33 -22 -50 -40 -30 -31 -30 -31 -33 -168 -3 -163 7 -193 79 -230 l44 -22 1077 2 1077 3 28 21 c57 43 68 76 68 214 0 141 -11 176 -68 210 -31 19 -58 20 -1117 19 -597 0 -1094 -4 -1105 -9z m2155 -220 l0 -100 -1055 0 -1055 0 0 93 c0 52 3 97 7 100 3 4 478 7 1055 7 l1048 0 0 -100z"></path> </g> </svg></div>' ).insertBefore( $(this) );
				$(this).parent().css("white-space", "nowrap");
				$(this).parent().css("display", "table");
				$(this).attr('id', 'colorpicker'+counter);
				$(this).hide();
				$('#colorminus'+counter).hide();
				counter++;
			});
			$('body').addClass("colortoggle");
		}
	};



	
	
	/* 
	/* DOM manipulation
	*/
	// init viewport
	$('meta[name="viewport"]').remove();
	$('head').append('<meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no" />');

	var ismobile = (/iphone|ipod|android|blackberry|opera|mini|windows\sce|palm|smartphone|iemobile/i.test(navigator.userAgent.toLowerCase()));
	var istablet = (/ipad|android|android 3.0|xoom|sch-i800|playbook|tablet|kindle/i.test(navigator.userAgent.toLowerCase()));
	
	var isAndroid = function() {
			return navigator.userAgent.match(/Android/i);
	};
	
	
	if (ismobile) {
		$("body").addClass("isMobile");
		if (isAndroid()) {
			$("body").addClass("isAndroidPhone");
		}
	} else if(istablet) {
		if (isAndroid()) {
			$("body").addClass("isAndroidTablet");
		}
	}
	// init height and width
	recalculateStyleHeight();

	// hide menu
	if ($("body").width() < window.innerHeight) {
		recalculateStyleWithoutMenu();
	} else {
		recalculateStyleWithMenu();
	}

	// Logo - add toggle link
	var parentLink = $("#logo").parent("a");
	$(parentLink).unbind("click");
	if (typeof(parentLink.attr("href")) == "undefined") {
		parentLink.attr("onclick", "#");
	} else {
		parentLink.attr("href", "#");
	}
	$("#logo").closest("a").removeAttr("onclick");
	
	$("#logo").click(toggleMenuOnFHEMIcon);
	
	/* 
	/* Event Handlers
	*/
	// Resize
	$(window).resize(function() {
		recalculateStyleHeight();
		if ($("body").width() < window.innerHeight) {
			recalculateStyleWithoutMenu();
			resetcolumns();
			calccolumns();
		} else {
			recalculateStyleWithMenu();
			resetcolumns();
			calccolumns();
		}
		if (spaltensumme < 200) {
			mobiletoggle();
			resetcolumns();
			calccolumns();
		}
	});
	$(window).bind('orientationchange', function(event) {
		$(window).trigger('resize');
		//alert("orientationchange width: "+window.innerWidth+" height: "+window.innerHeight);
	});
	// Touch - Color picker
	$(document).on('touchstart', function(e) {
		var container = $("#colorpicker");
		if (!container.is(e.target) // if the target of the click isn't the container...
			&& container.has(e.target).length === 0 // ... nor a descendant of the container
			&& !$("input").is(e.target) && container.length > 0) // ... is not an input
		{
			container.remove();
		}
	});
});

function triggerResize() {
	window.dispatchEvent(new Event('resize'));
}

function togglecolorpicker(counter) {
	$('#colorpicker'+counter).toggle('fast');
	$('#colorminus'+counter).toggle();
	$('#colorplus'+counter).toggle();
}
function togglecolorpickerct(counter) {
	$('#colorpicker_ct_mired'+counter).toggle('fast');
	$('#colorctminus'+counter).toggle();
	$('#colorctplus'+counter).toggle();
}

window.addEventListener("load",triggerResize,false);