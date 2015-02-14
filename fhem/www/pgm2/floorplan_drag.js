function increment(e,field) {
    var keynum

    var step = 1;
    if( e.shiftKey ) step = 10;
	if( e.ctrlKey  ) step = 3;

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
		$( "div#div-" + cl ).css('top', $(this).val() + "px");
	});

	$( "#fp_ar_input_left" ).change(function(e) {
		var cl = $(this).attr("name").replace(/left./,"");
		$( "div#div-" + cl ).css('left', $(this).val() + "px");
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
			    grid = 3;
			}			

			var topRemainder = ui.position.top % grid;
			var leftRemainder = ui.position.left % grid;

			if (topRemainder <= snapTolerance && !isCtrlPressed) {
			    ui.position.top = ui.position.top - topRemainder;
			}

			if (leftRemainder <= snapTolerance && !isCtrlPressed) {
			    ui.position.left = ui.position.left - leftRemainder;
			}

                        var device = ui.helper.context.id.replace(/div-/,"");
                        var X = ui.position.left;
                        var Y = ui.position.top;
			$( "input#fp_ar_input_left." + device ).val(X);
			$( "input#fp_ar_input_top." + device ).val(Y);

		},
  
                stop: function( event, ui) {

			$('body').css('cursor','auto');

                        var device = ui.helper.context.id.replace(/div-/,"");
                        var X = ui.position.left;
                        var Y = ui.position.top;
                        var style = ui.helper.context.getAttribute("fp_style", "");
                        var text = ui.helper.context.getAttribute("fp_text", "");
                        var text2 = ui.helper.context.getAttribute("fp_text2", "");
                        var fp_name = ui.helper.context.getAttribute("fp_name", "");
                        var cmd = "attr " + device + " fp_" + fp_name + " " + Y + "," + X + "," + style + "," + text + "," + text2;
                        FW_cmd('/fhem/floorplan/'+fp_name+'?XHR=1&cmd='+cmd);

                }
        });

});
