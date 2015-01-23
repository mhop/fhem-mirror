/* iOS 6 Theme for FHEM */
/* by Sandra Ohmayer */
/* http://www.animeschatten.net */
/* jQuery is required*/

$( document ).ready(function() {
	/* 
	/* Style Config
	*/
	var menuwidth = 200;
	var paddingwidth = 60;
	var logowidth = 28;
	var switchtomobilemode = 376;
	var hdrheight = 44;
	var inputpadding = 251;
	
	/* 
	/* Functions
	*/	

	// Set style height and width
	var recalculateStyleHeight = function() {
		var height = window.innerHeight;
		$("#menu").height(height-hdrheight);
		$("#content").height(height-hdrheight);
		$("#right").height(height-hdrheight);	
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
			$("#hdr input").width(width-inputpadding+menuwidth-logowidth);
		} else {
			$("#menu").width(menuwidth);
			$("#content").width(width-menuwidth-paddingwidth-1);
			$("#right").width(width-menuwidth-paddingwidth-1);
			$("#hdr input").width(width-inputpadding);
			$("#content").show()
			$("#right").show();
		}
	};
	var recalculateStyleWithoutMenu = function() {
		var width = $("body").width();
		$("body").addClass("hideMenu");
		
		if (switchtomobilemode > width) {
			$("#hdr input").width(width-inputpadding+menuwidth-logowidth);
		} else {
			$("#hdr input").width(width-inputpadding);
		}
		
		$("#menu").width(0);
		$("#content").width(width-paddingwidth);
		$("#right").width(width-paddingwidth);	
		$("#content").show()
		$("#right").show();
	};
	
	// Show / Hide menu
	var toggleMenuOnFHEMIcon = function() {
			if ($("body").hasClass("hideMenu")) {
				recalculateStyleWithMenu();
			} else {
				recalculateStyleWithoutMenu();
			}	
	};
	


	/* 
	/* DOM manipulation
	*/	
	
	// init viewport
	$('meta[name="viewport"]').attr('content', 'width=device-width, user-scalable=0, initial-scale=1.0');
	
	// init height and width
	recalculateStyleHeight();
	
	
	// hide menu
	if($("body").width() < window.innerHeight) {
		recalculateStyleWithoutMenu();
	} else {
		recalculateStyleWithMenu();
	}
	
	// Logo - add toggle link
	var parentLink = $("#logo").parent("a");
	if (typeof(parentLink.attr("href")) == "undefined") {
		parentLink.attr("onclick", "#");
	} else {
		parentLink.attr("href", "#");
	}
	$("#logo").click(toggleMenuOnFHEMIcon);
	
	/* 
	/* Event Handlers
	*/
	
	// Resize
	$(window).resize(function() {
		recalculateStyleHeight();
		if($("body").width() < window.innerHeight) {
			recalculateStyleWithoutMenu();
		} else {
			recalculateStyleWithMenu();
		}
    });
	$(window).bind('orientationchange', function(event) {
		//alert("orientationchange width: "+window.innerWidth+" height: "+window.innerHeight);
		recalculateStyleHeight();
		if($("body").width() < window.innerHeight) {
			recalculateStyleWithoutMenu();
		} else {
			recalculateStyleWithMenu();
		}
	});
	// Touch - Color picker
	$(document).on('touchstart', function (e) {
		var container = $("#colorpicker");
		
		if (!container.is(e.target) // if the target of the click isn't the container...
		&& container.has(e.target).length === 0  // ... nor a descendant of the container
		&& !$("input").is(e.target) && container.length > 0) // ... is not an input
			{
				container.remove();
			}
	});
	
});
