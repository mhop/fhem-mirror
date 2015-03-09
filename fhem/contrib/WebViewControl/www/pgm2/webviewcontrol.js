/***********************
 * TTS Phonegap Plugin *
 ***********************/
function TTS() {
//	var STOPPED			= 0;
//	var INITIALIZING	= 1;
//	var STARTED			= 2;

	/**
	 * Play the passed in text as synthesized speech
	 *
	 * @param   {String}    text
	 * @param   {Object}    successCallback
	 * @param   {Object}    errorCallback
	 */
	this.speak = function (text, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "speak", [text]);
	};

	/**
	 * Interrupt any existing speech, then speak the passed in text as synthesized speech
	 *
	 * @param	{String}	text
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.interrupt = function (text, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "interrupt", [text]);
	};

	/**
	 * Stop any queued synthesized speech
	 *
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.stop = function (successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "stop", []);
	};

	/**
	 * Play silence for the number of ms passed in as duration
	 *
	 * @param   {number} duration
	 * @param   {object} successCallback
	 * @param   {object} errorCallback
	 * @returns {*}
	 */
	this.silence = function(duration, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "silence", [duration]);
	};

	/**
	 * Set speed of speech.  Usable from 30 to 500.  Higher values make little difference.
	 *
	 * @param   {number} speed
	 * @param   {Object} successCallback
	 * @param   {Object} errorCallback
	 * @returns {*}
	 */
	this.speed = function(speed, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "speed", [speed]);
	};

	/**
	 * Set pitch of speech.  Useful values are approximately 30 - 300
	 *
	 * @param	{number}		pitch
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.pitch = function(pitch, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "pitch", [pitch]);
	};

	/**
	 * Starts up the TTS Service
	 *
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.startup = function(successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "startup", []);
	};

	/**
	 * Shuts down the TTS Service if you no longer need it.
	 *
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.shutdown = function(successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "shutdown", []);
	};

	/**
	 * Finds out if the language is currently supported by the TTS service.
	 *
	 * @param	{Sting}	lang
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.isLanguageAvailable = function(lang, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "isLanguageAvailable", [lang]);
	};

	/**
	 * Finds out the current language of the TTS service.
	 *
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.getLanguage = function(successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "getLanguage", []);
	};

	/**
	 * Sets the language of the TTS service.
	 *
	 * @param	{String}	lang
	 * @param	{Object}	successCallback
	 * @param	{Object}	errorCallback
	 */
	this.setLanguage = function(lang, successCallback, errorCallback) {
		return cordova.exec(successCallback, errorCallback, "TTS", "setLanguage", [lang]);
	};
}
/**
 * Load TTS
 */
if(!window.plugins) {
	window.plugins = {};
}
if (!window.plugins.tts) {
	window.plugins.tts = new TTS();
}

/**********************************************
* HeadsetListener plugin for Cordova/Phonegap *
 **********************************************/
cordova.define("cordova/plugin/headset", function(require, exports, module) {
	/**
	 * This class contains information about the current headset status.
	 * @constructor
	 */
	var cordova = require('cordova'),
		exec = require('cordova/exec');

	/**
	 * @return {Number}
	 */
	function handlers() {
		return headset.channels.headsetstatus.numHandlers;
	}

	/**
	 * @constructor
	 */
	var Headset = function() {
		this._isPlugged = false;

		// Create new event handlers on the window (returns a channel instance)
		this.channels = {
			headsetstatus:cordova.addWindowEventHandler('headsetstatus')
		};

		for (var key in this.channels) {
			this.channels[key].onHasSubscribersChange = Headset.onHasSubscribersChange;
		}
	};

	/**
	 * Event handlers for when callbacks get registered for the headset.
	 * Keep track of how many handlers we have so we can start and stop the native headset listener.
	 */
	Headset.onHasSubscribersChange = function() {
		// If we just registered the first handler, make sure native listener is started.
		if (this.numHandlers === 1 && handlers() === 1) {
			//exec(successFunc, failureFunc, 'service', 'action', [jsonArgs]);
			exec(headset._status, headset._error, 'HeadsetListener', 'start', []);
		} else if (handlers() === 0) {
			exec(null, null, 'HeadsetListener', 'stop', []);
		}
	};

	/**
	 * Callback for headset status
	 *
	 * @param {Object} info	keys: isPlugged
	 */
	Headset.prototype._status = function(info) {
		if (info) {
			var me = headset;
			if (me._isPlugged !== info.isPlugged) {
				// Fire headsetstatus event
				cordova.fireWindowEvent('headsetstatus', info);
			}
			me._isPlugged = info.isPlugged;
		}
	};

	/**
	 * Error callback for battery start
	 */
	Headset.prototype._error = function(e) {
		console.log("Error initializing Headset listener: " + e);
	};

	var headset = new Headset();

	module.exports = headset;
});
var headset = cordova.require('cordova/plugin/headset');

/************************************
 * VoiceRecognition Phonegap Plugin *
 ************************************/
cordova.define("cordova/plugin/voiceRecognition", function(require, exports, module) {
	/**
	 * This class contains voiceRecognition functions.
	 * @constructor
	 */
	var cordova = require('cordova'),
		exec = require('cordova/exec');

	var errorCodes = {
		1:'Network operation timed out',
		2:'Other network related errors',
		3:'Audio recording error',
		4:'Server sends error status',
		5:'Other client side errors',
		6:'No speech input',
		7:'No recognition result matched',
		8:'RecognitionService busy',
		9:'Insufficient permissions'
	};

	var states = {
		STATE_RECOGNISE_END:	0,
		STATE_RECOGNISE_READY:	1,
		STATE_RECOGNISE_BEGIN:	2,
		STATE_RECOGNISE_RESULTS:3,
		STATE_RECOGNISE_ERROR:	9
	};

	function handlers() {
		return	voiceRecognition.channels.voicerecognition_begin.numHandlers +
				voiceRecognition.channels.voicerecognition_end.numHandlers +
				voiceRecognition.channels.voicerecognition_error.numHandlers +
				voiceRecognition.channels.voicerecognition_ready.numHandlers +
				voiceRecognition.channels.voicerecognition_result.numHandlers;
	}

	var VoiceRecognition = function() {
		this._state = 0;

		// Create new event handlers on the window (returns a channel instance)
		this.channels = {
			voicerecognition_begin:cordova.addWindowEventHandler('voicerecognition_begin'),
			voicerecognition_end:cordova.addWindowEventHandler('voicerecognition_end'),
			voicerecognition_error:cordova.addWindowEventHandler('voicerecognition_error'),
			voicerecognition_ready:cordova.addWindowEventHandler('voicerecognition_ready'),
			voicerecognition_result:cordova.addWindowEventHandler('voicerecognition_result')
		};
		for (var key in this.channels) {
			this.channels[key].onHasSubscribersChange = VoiceRecognition.onHasSubscribersChange;
		}
	};

	/**
	 * Event handlers for when callbacks get registered for the voiceRecognition.
	 * Keep track of how many handlers we have so we can start and stop the voiceRecognition listener
	 */
	VoiceRecognition.onHasSubscribersChange = function() {
		// If we just registered the first handler, make sure native listener is started.
		if (this.numHandlers === 1 && handlers() === 1) {
			exec(voiceRecognition._status, voiceRecognition._error, "VoiceRecognition", "start", []);
		} else if (handlers() === 0) {
			exec(null, null, "VoiceRecognition", "stop", []);
		}
	};

	/**
	 * Callback for battery status
	 *
	 * @param {Object} info            keys: level, isPlugged
	 */
	VoiceRecognition.prototype._status = function(info) {
		if (info) {
			var me = voiceRecognition;
			var state = info.state;

			if (me._state !== state) {
				// Fire events
				if (state == states.STATE_RECOGNISE_END) {
					cordova.fireWindowEvent('voicerecognition_end', null);
				} else if (state == states.STATE_RECOGNISE_READY) {
					cordova.fireWindowEvent('voicerecognition_ready', null);
				} else if (state == states.STATE_RECOGNISE_BEGIN) {
					cordova.fireWindowEvent('voicerecognition_begin', null);
				} else if (state == states.STATE_RECOGNISE_RESULTS) {
					cordova.fireWindowEvent('voicerecognition_result', {word: info.result});
				} else if (state == states.STATE_RECOGNISE_ERROR) {
					cordova.fireWindowEvent('voicerecognition_error', {code: info.errorCode, description: errorCodes[info.errorCode]});
				}
			}
			me._state = state;
		}
	};

	/**
	 * Error callback for voice recognition start
	 */
	VoiceRecognition.prototype._error = function(e) {
		console.log("Error initializing voice recognition listener: " + e);
	};

	var voiceRecognition = new VoiceRecognition();

	module.exports = voiceRecognition;
});
var voiceRecognition = cordova.require('cordova/plugin/voiceRecognition');


/******************************
 * Begin WebViewControl parts * 
 ******************************/

var deviceControl = {
	exec: function(command, params) {
		if(cordova.exec) {
			cordova.exec(
				function(winParam) {},
				function(error) {},
				'DeviceControl',
				command,
				params
			);
		}
	},

	/**
	 * Set screen brightness
	 * @param level
	 */
	screenBrightness: function(level) {
		deviceControl.exec('setScreenBrightness', [level]);
	},

	/**
	 * Set volume
	 * @param level
	 */
	volume: function(level) {
		deviceControl.exec('setVolume', [level]);
	},

	/**
	 * Set keep screen on / off
	 * @param value
	 */
	keepScreenOn: function(value) {
		deviceControl.exec('setKeepScreenOn', [value]);
	},

	/**
	 * Set Toast Message
	 * @param message
	 */
	toastMessage: function(message) {
		deviceControl.exec('showToast', [message]);
	},

	/**
	 * Perform a reload
	 */
	reload: function() {
		window.location.reload();		
	},

	//"http://audio.ibeat.org/content/p1rj1s/p1rj1s_-_rockGuitar.mp3"
	audioPlay: function(value) {
		audioPlayer.playAudio(value);		
	},

	audioStop: function() {
		audioPlayer.stopAudio();		
	},

	ttsSay: function(txt) {
		ttsPlayer.say(txt);		
	},

	voiceRec: function(opt) {
		fhemWVC.startVoiceRecognition();
	},

	newUrl: function(opt) {
		location.href = decodeURIComponent(opt);
	}
};

var audioPlayer = {
	media: null,

	// Play audio
	playAudio: function(src, showToast) {
		showToast = (typeof(showToast) == 'undefined') ? true : showToast;
		if (showToast) {
			deviceControl.toastMessage('playAudio(' + src + ')');
		}

		audioPlayer.media = new Media(
			src,
			function() {},
			function(error) {
				deviceControl.toastMessage('Error: playAudio(' + error.message + ' [' + error.code + '])');
			}
		);
	
		// Play audio
		audioPlayer.media.play();
	},

	// Stop audio
	stopAudio: function() {
		if (audioPlayer.media) {
			audioPlayer.media.stop();
		}
	}
};

var ttsPlayer = {
	init: function() {
		window.plugins.tts.setLanguage('de', function(){}, function(){});
		window.plugins.tts.startup(
			function() {}, // Success
			function() {deviceControl.toastMessage('TTS startup error.');}
		);			
	},
	
	say: function(txt) {
		if (txt) {
			deviceControl.toastMessage('TTS Say: ' + txt);
			window.plugins.tts.speak(
				txt,
				function() {}, // Success
				function() {deviceControl.toastMessage('TTS error.');}
			);
		}
	}
};

var wvcApp;
wvcApp = {
	exitOnBackKey:false,

	// Application Constructor
	initialize:function (callback) {
		document.addEventListener('deviceready', function () {

//			console.log('cordova ready?');
			wvcApp.onDeviceReady();

			if (callback) {
				callback();
			}
		}, false);
	},

	// deviceready Event Handler
	onDeviceReady:function () {
		if (wvcApp.exitOnBackKey) {
			document.addEventListener('backbutton', wvcApp.onBackKeyDown, false);
		}
		document.addEventListener('offline', wvcApp.onOffline, false);
		document.addEventListener('online', wvcApp.onOnline, false);
		document.addEventListener('pause', wvcApp.onPause, false);
		document.addEventListener('resume', wvcApp.onResume, false);
		window.addEventListener('batterystatus', wvcApp.onBatteryStatus, false);

		window.addEventListener('voicerecognition_begin', wvcApp.onVoiceRecognitionBegin, false);
		window.addEventListener('voicerecognition_end', wvcApp.onVoiceRecognitionEnd, false);
		window.addEventListener('voicerecognition_error', wvcApp.onVoiceRecognitionError, false);
		window.addEventListener('voicerecognition_ready', wvcApp.onVoiceRecognitionReady, false);
		window.addEventListener('voicerecognition_result', wvcApp.onVoiceRecognitionResult, false);

		window.addEventListener('headsetstatus', wvcApp.onHeadsetStatus, false);

		ttsPlayer.init();
//		document.addEventListener('menubutton', wvcApp.onMenuKeyDown, false);
	},

	removeEventListener:function () {
		document.removeEventListener('offline', wvcApp.onOffline, false);
		document.removeEventListener('online', wvcApp.onOnline, false);
		document.removeEventListener('pause', wvcApp.onPause, false);
		document.removeEventListener('resume', wvcApp.onResume, false);
		window.removeEventListener('batterystatus', wvcApp.onBatteryStatus, false);

		window.removeEventListener('voicerecognition_begin', wvcApp.onVoiceRecognitionBegin, false);
		window.removeEventListener('voicerecognition_end', wvcApp.onVoiceRecognitionEnd, false);
		window.removeEventListener('voicerecognition_error', wvcApp.onVoiceRecognitionError, false);
		window.removeEventListener('voicerecognition_ready', wvcApp.onVoiceRecognitionReady, false);
		window.removeEventListener('voicerecognition_result', wvcApp.onVoiceRecognitionResult, false);

		window.removeEventListener('headsetstatus', wvcApp.onHeadsetStatus, false);
	},


	onVoiceRecognitionBegin:function () {
//		deviceControl.toastMessage('Voice recognition Begin');
	},

	onVoiceRecognitionEnd:function () {
		var recRing = document.getElementById('voiceRecRing');
		if (recRing) {
			document.getElementById('voiceRecImg').removeChild(recRing);
		}

		setTimeout(function() {
			var recDiv = document.getElementById('voiceRecOuterWrapper');
			if (recDiv) {
				document.body.removeChild(recDiv);
			}
		}, 2000);
	},

	onVoiceRecognitionError:function (error) {
//		deviceControl.toastMessage('Voice recognition error: ' + error.description + ' (' + error.code + ')');
		audioPlayer.playAudio('/android_asset/sounds/voice_recognition_error.mp3', false);

		var recDiv = document.createElement('div');
		recDiv.setAttribute('id','voiceRecState');
		recDiv.innerHTML = error.description;

		var recImg = document.getElementById('voiceRecImg');
		recImg.appendChild(recDiv);
		recImg.setAttribute('class','error');

		fhemWVC.informFhem('voiceRecognitionLastError', error.code + ':' + error.description);
	},

	onVoiceRecognitionReady:function () {
		audioPlayer.playAudio('/android_asset/sounds/voice_recognition_start.mp3', false);

		var recDiv = document.createElement('div');
		recDiv.setAttribute('id','voiceRecOuterWrapper');
		recDiv.innerHTML = '<div id="voiceRecWrapper"><div id="voiceRecImg"><div id="voiceRecRing"></div></div></div>';
		document.body.appendChild(recDiv);
	},

	onVoiceRecognitionResult:function (result) {
		audioPlayer.playAudio('/android_asset/sounds/voice_recognition_ok.mp3', false);

		var recImg = document.getElementById('voiceRecImg');
		recImg.setAttribute('class','success');

		fhemWVC.informFhem('voiceRecognitionLastResult', result.word);

		deviceControl.toastMessage('Voice recognition result: ' + result.word);
//		deviceControl.ttsSay(result.word);
	},

	onHeadsetStatus:function (info) {
		if (info.isPlugged) {
			deviceControl.toastMessage('The headphones have been plugged in!');
		} else {
			deviceControl.toastMessage('The headphones have been unplugged!');
		}
	},

	// Back key event handler
	onBackKeyDown:function () {
		overrideBackKey = false;
		if (typeof(container.wvcApp.onBackKeyDown) == 'function') {
			overrideBackKey = container.wvcApp.onBackKeyDown();
		}
		if (!overrideBackKey) {
			navigator.app.exitApp();
		}
	},

	onOffline:function () {
		if (typeof(fhemWVC.onOffline) == 'function') {
			fhemWVC.onOffline()
		}
	},

	onOnline:function () {
		if (typeof(fhemWVC.onOnline) == 'function') {
			fhemWVC.onOnline()
		}
	},

	onPause:function () {
		if (typeof(fhemWVC.onPause) == 'function') {
			fhemWVC.onPause()
		}
	},

	onResume:function () {
		if (typeof(fhemWVC.onResume) == 'function') {
			fhemWVC.onResume()
		}
	},

	onBatteryStatus:function (info) {
		if (typeof(fhemWVC.onBatteryStatus) == 'function') {
			fhemWVC.onBatteryStatus(info);
		}
	},

	onConnectionError:function (errorCode, description, failingUrl) {
		if (typeof(fhemWVC.onConnectionError) == 'function') {
			fhemWVC.onConnectionError(errorCode, description, failingUrl);
		}
	}

};

/* ************************************************************************ */

var fhemWVC = {
	httpRequest: null,
	currResponseLine: 0,
	appId: 12345,
	debug: false,

	deviceState: {
		powerLevel: null,
		powerIsPlugged: null
	},

	reconnect: function(timeout) {
		setTimeout(function() {
			fhemWVC.connect();
		}, timeout);
	},

	connect: function () {
		fhemWVC.currResponseLine = 0;
		fhemWVC.httpRequest = new XMLHttpRequest();
		fhemWVC.httpRequest.open("GET", '?XHR=1&inform=type=status;filter=room=all&timestamp=' + new Date().getTime(), true);

		fhemWVC.httpRequest.onreadystatechange = fhemWVC.parse;
		fhemWVC.httpRequest.send(null);
	},

	parse: function() {
		var httpRequest = fhemWVC.httpRequest;
		if (!fhemWVC.haveAppDevices()) {
			return;
		}
		if(httpRequest.readyState == 4) {
			fhemWVC.reconnect(100);
			return;
		}

		if(httpRequest.readyState != 3) {
			return;
		}

		var lines = httpRequest.responseText.split("\n");
		//Pop the last (maybe empty) line after the last "\n"
		//We wait until it is complete, i.e. terminated by "\n"
		lines.pop();

		for(var i = fhemWVC.currResponseLine; i < lines.length; i++) {
			var params = lines[i].split('<<', 3);		// Complete arg, 0 -> name, 1 -> value
			if(params.length != 3) {
				continue;
			}

			if (wvcDevices[fhemWVC.appId] && wvcDevices[fhemWVC.appId] == params[0]) {
				var fnValue = params[1].split(' ');	// fn and value
				var fn = fnValue.shift();
				var value = fnValue.join(' ');

				fhemWVC.log(fn + " / " + value);
				if (typeof(deviceControl[fn]) != 'undefined' && typeof(deviceControl[fn]) == 'function') {
					deviceControl[fn](value);
				}
				break;
			}
		}

		//Next time, we continue at the next line
		fhemWVC.currResponseLine = lines.length;
	},

	haveAppDevices: function() {
		var retVal = false;
		if (wvcDevices) {
			retVal = true;
		}
		return retVal;
	},

    /**
     *
     */
	initialize: function() {
		var wvcDevices = {};

		wvcApp.initialize(function(){
			fhemWVC.createIcons();

			if (typeof(wvcUserCssFile) != 'undefined') {
				fhemWVC.injectCss(wvcUserCssFile);
			}

			fhemWVC.reconnect(50);
			fhemWVC.setConnectionState(navigator.connection.type);

			if (typeof(window.appInterface) != 'undefined' && typeof(window.appInterface) == 'object') {
				if (typeof(window.appInterface.getAppId) != 'undefined' && typeof(window.appInterface.getAppId) == 'function') {
					fhemWVC.appId = window.appInterface.getAppId();
				}
			}
		});

		window.onunload=function(){
			wvcApp.removeEventListener();
		};
	},

	createIcons: function() {
		fhemWVC.injectCss('webviewcontrol.css');

		var iconDiv = document.createElement('div');
		iconDiv.innerHTML = '<div> <div class="onlineIconWrapper"><div id="fhemWVC_onlineIcon" class="onlineIcon"></div></div>';
		iconDiv.innerHTML+= '<div onClick="fhemWVC.startVoiceRecognition();" class="batteryIconWrapper"><div id="fhemWVC_batteryIcon" class="batteryIcon bat0"><div id="fhemWVC_acConnectedIcon" class="acConnected"></div><div id="fhemWVC_batteryPercent" class="txtPercent">?%</div></div></div> </div>';
		iconDiv.setAttribute('id','htIcons');
		iconDiv.setAttribute('style','position: fixed; right: 0px; bottom: 0px; width: 32px; height: 80px;');

		document.body.appendChild(iconDiv);
	},

	startVoiceRecognition: function() {
		cordova.exec(null, fhemWVC.voiceRecognitionNotPresentError, "VoiceRecognition", "init", []);
		cordova.exec(null, null, "VoiceRecognition", "startRecognition", []);
	},

	voiceRecognitionNotPresentError: function (errTxt) {
		deviceControl.toastMessage(errTxt);
		fhemWVC.informFhem('voiceRecognitionLastError', '-1:' + errTxt);
	},

	updateBatteryIcon: function(percent, isPlugged) {
		var txtPercent = document.getElementById('fhemWVC_batteryPercent');
	    var batteryIcon = document.getElementById('fhemWVC_batteryIcon');
	    var acConnectedIcon = document.getElementById('fhemWVC_acConnectedIcon');

	    if (isPlugged) {
	    	acConnectedIcon.className = 'acConnected';
	    } else {
	    	acConnectedIcon.className = 'hidden';
	    }

	    percent = parseInt(percent);
		percent = (percent > 0 ) ? percent : 0;
		percent = (percent < 100 ) ? percent : 100;

	    txtPercent.innerText = percent + '%';

		var color = (percent > 25) ? 'yellow' : 'red';
		color = (percent > 50) ? 'green' : color;

		percent = (percent > 0 && percent < 10) ? 10 : percent;
		percent = parseInt(percent/10) * 10;
		var batClass = (percent > 0) ? 'bat' + percent + color : 'bat0';

		batteryIcon.className = 'batteryIcon ' + batClass;
	},

	/**
	 * Inject given css file
	 * @param cssFile
	 */
	injectCss: function(cssFile) {
		var css = document.createElement('link');
		css.setAttribute('href','/fhem/pgm2/' + cssFile);
		css.setAttribute('rel','stylesheet');
		document.getElementsByTagName('head')[0].appendChild(css);
	},

    injectRemoteDebugger: function() {
        var js = document.createElement('script');
        js.setAttribute('src','http://debug.phonegap.com/target/target-script-min.js#webViewControl');
        js.setAttribute('type','text/javascript');
        document.getElementsByTagName('head')[0].appendChild(js);
    },

	informFhem: function(command, value) {
		var webViewClientId = (typeof(wvcDevices[fhemWVC.appId]) != 'undefined') ? wvcDevices[fhemWVC.appId] : 'undefined';
		var getVars = '?id=' + webViewClientId;

		if (command == 'powerState') {
			getVars+= '&powerLevel=' + fhemWVC.deviceState.powerLevel;
			getVars+= '&powerPlugged=' + fhemWVC.deviceState.powerIsPlugged;
		} else {
			getVars+= '&' + command + '=' + value;
		}

		var httpRequest = new XMLHttpRequest();
		httpRequest.open("GET", '/fhem/webviewcontrol' + getVars, true);
		httpRequest.send(null);
	},

	setConnectionState: function(networkState) {
	    var onlineIcon = document.getElementById('fhemWVC_onlineIcon');
	    var onlineClass =  'offline';

	    // we set the network icon on green on wifi or ethernet connection only
		if (networkState == Connection.ETHERNET || networkState == Connection.WIFI) {
			onlineClass = 'online';
		}

		onlineIcon.className = 'onlineIcon ' + onlineClass;
	},

	onConnectionError: function(errorCode, description, failingUrl) {
	},

	onBatteryStatus: function(info) {
		var inform = false;
		if (fhemWVC.deviceState.powerLevel != info.level || fhemWVC.deviceState.powerIsPlugged != info.isPlugged) {
			inform = true;
		}

		fhemWVC.updateBatteryIcon(info.level, info.isPlugged);
		fhemWVC.deviceState.powerLevel = info.level;
		fhemWVC.deviceState.powerIsPlugged = info.isPlugged;

		if (inform) {
			fhemWVC.informFhem('powerState');
		}
	},

	onResume: function() {
		deviceControl.toastMessage('App resumes from pause.')
	},

	onPause: function() {
		deviceControl.toastMessage('App go to pause.')
	},

	onOnline: function() {
		deviceControl.toastMessage('Network online')
	},

	onOffline: function() {
		deviceControl.toastMessage('Network offline')
	},

	log: function(dbgObj) {
		if (fhemWVC.debug) {
			console.log (dbgObj);
		}
	}
};

//fhemWVC.injectRemoteDebugger();
fhemWVC.initialize();

/*
// uncomment this for testing without the device
document.addEventListener("DOMContentLoaded", function() {
	fhemWVC.appId = '00001234';		// Set alternative appId here
	fhemWVC.createIcons();
	fhemWVC.reconnect(50);
	fhemWVC.debug = true;
	fhemWVC.onBatteryStatus({level: 53, isPlugged: false});
},false);
*/
