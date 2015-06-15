function increment(e,field) {
    var keynum

    var step = 1;
    if( e.shiftKey ) step = 10;

    if(window.event) {// IE 
        keynum = e.keyCode
    } else if(e.which) {// Netscape/Firefox/Opera 
        keynum = e.which
    }
    if (keynum == 38) {
        field.value = parseInt(field.value)+ step;
    } else if (keynum == 40) {
        field.value = parseInt(field.value) - step;
    }

	if ("createEvent" in document) {
	    var evt = document.createEvent("HTMLEvents");
	    evt.initEvent("change", false, true);
	    field.dispatchEvent(evt);
	}
	else
	    field.fireEvent("onchange");

    return true;
}

$(document).ready(function($){

	$( "#fp_ar_input_top" ).change(function(e) {
		var cl = $(this).attr("name").replace(/top./,"");
		$( 'div.ui-draggable[id="div-' + cl + '"]' ).css('top', $(this).val() + "px");
	});

	$( "#fp_ar_input_left" ).change(function(e) {
		var cl = $(this).attr("name").replace(/left./,"");
		$( 'div.ui-draggable[id="div-' + cl + '"]' ).css('left', $(this).val() + "px");
	});

	$( ".fp_device_div, .fp_weblink_div" ).draggable({
		snap: true,
		snapTolerance: 8,

		drag: function( event, ui ) {

			$('body').css('cursor','move');

			var isCtrlPressed = event.ctrlKey;
			var isShiftPressed = event.shiftKey;

			var snapTolerance = $(this).draggable('option', 'snapTolerance');

			var grid = 1;
			if(isShiftPressed) {
			    grid = 10;
			} 

			if(isCtrlPressed) {
				$(this).draggable('option', 'snap', false);
			}

			var topRemainder = ui.position.top % grid;
			var leftRemainder = ui.position.left % grid;

			if (topRemainder <= snapTolerance) {
			    ui.position.top = ui.position.top - topRemainder;
			}

			if (leftRemainder <= snapTolerance) {
			    ui.position.left = ui.position.left - leftRemainder;
			}

                        var device = ui.helper.context.id.replace(/div-/,"");
                        var X = ui.position.left;
                        var Y = ui.position.top;
			$( 'input#fp_ar_input_left[class="' + device + '"]' ).val(X);
			$( 'input#fp_ar_input_top[class="' + device + '"]' ).val(Y);

					    event = event || window.event;
		    //event.preventDefault();
		    if (typeof event.stopPropagation != "undefined") {
		        event.stopPropagation();
		    } else {
		        event.cancelBubble = true;
		    }

		},
  
		stop: function( event, ui) {

			$('body').css('cursor','auto');
			$(this).draggable('option', 'snap', true);

			var device = ui.helper.context.id.replace(/div-/,"");
			var X = ui.position.left;
			var Y = ui.position.top;
			var style = ui.helper.context.getAttribute("fp_style", "");
			var text = ui.helper.context.getAttribute("fp_text", "");
			var text2 = ui.helper.context.getAttribute("fp_text2", "");
			var fp_name = ui.helper.context.getAttribute("fp_name", "");
			var cmd = "attr " + device + " fp_" + fp_name + " " + Y + "," + X + "," + style + "," + text + "," + text2;
			FW_cmd('/fhem/floorplan/'+fp_name+'?XHR=1&cmd='+cmd);

			// prevent from further propagating event 
			$( event.originalEvent.target ).one('click', function(e){ e.stopImmediatePropagation(); } );

        }
    });

});
