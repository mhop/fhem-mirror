//########################################################################################
// fbtam.js
// Version 0.2
// See 72_FBTAM for licensing
//########################################################################################
//# Prof. Dr. Peter A. Henning

//------------------------------------------------------------------------------------------------------
// Determine csrfToken
//------------------------------------------------------------------------------------------------------

var req = new XMLHttpRequest();
req.open('GET', document.location.href, false);
req.send(null);
var csrfToken = req.getResponseHeader('X-FHEM-csrfToken');
if (csrfToken == null) {
    csrfToken = "null";
}

//------------------------------------------------------------------------------------------------------
// Button action
//------------------------------------------------------------------------------------------------------

function callTAMAction(action, device, index) {
    let url = "/fhem?XHR=1&cmd=set%20" + device + "%20" + action + "%20" + index;
    fetch(url).then(response => response.text()).then(result => {
        console.log('FBTAM action:', result);
    }). catch (error => {
        console.error('Error: FBTAM REST call:', error);
    });
}


