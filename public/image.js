$(document).ready(function() {
	function reloadImage() {
		d = new Date();
		origurl = $('#display').attr('src').split('&r=')[0];
		$('#display').attr('src', origurl+'&r='+d.getTime());
		setTimeout(reloadImage, 60000);
	}
	setTimeout(reloadImage, 60000);
});
