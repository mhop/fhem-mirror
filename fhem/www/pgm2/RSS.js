// reload image with id 
function reloadImage(id) {
    // we use a dummy query to trick the browser into reloading the image
    var d = new Date();
    var q = '?t=' + d.getTime();
    var image = document.getElementById(id);
    var url = image.getAttribute('src');
    image.setAttribute('src', url.replace(/\?.*/,'') + q );
}
