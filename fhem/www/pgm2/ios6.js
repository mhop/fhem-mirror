/* iOS 6 Theme for FHEM */
/* by Sandra Ohmayer */
/* http://www.animeschatten.net */
/* jQuery is required*/
$(document).ready(function() {
	/* 
	/* Style Config
	*/
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
		} else {
			recalculateStyleWithoutMenu();
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
	$("#logo").click(toggleMenuOnFHEMIcon);
	/* 
	/* Event Handlers
	*/
	// Resize
	$(window).resize(function() {
		recalculateStyleHeight();
		if ($("body").width() < window.innerHeight) {
			recalculateStyleWithoutMenu();
		} else {
			recalculateStyleWithMenu();
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
