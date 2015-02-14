
$(document).ready(function($){ 

	$("div.fp_device_div.style_1, tr.devicestate").on("click", function(e) {
		if (!$(e.target).is('a')) {
			$(this).find("a").trigger('click');
			return false;
		}
		return true;
	});

});
