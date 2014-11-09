/**
 * Setup the application
 */

Ext.Loader.setConfig({
    enabled: true,
    disableCaching: true,
    paths: {
        'FHEM': 'app'
    }
});

//get url params in order to detect which app to start (fullfeatured or just simpleviewer)
var paramArr = document.URL.split("?");
if (paramArr && paramArr.length > 1 && paramArr[1].indexOf("showchart") > -1) {
	var params = Ext.Object.fromQueryString(paramArr[1]),
	    chartid = params.showchart;
	
	Ext.application({
	    name: 'FHEM Chartviewer',
	    requires: [
	        'FHEM.view.ChartViewport'
	    ],
	    controllers: [
	        'FHEM.controller.ChartController'
	    ],

	    launch: function() {
	    	
	    	// Gather information from FHEM
	        var me = this,
	            url = '../../../fhem?cmd=jsonlist2&XHR=1';
	        
	        Ext.Ajax.request({
	            method: 'GET',
	            async: false,
	            disableCaching: false,
	            url: url,
	            success: function(response){
	                Ext.getBody().unmask();
	                
                    FHEM.info = Ext.decode(response.responseText);
                    if (window.location.href.indexOf("frontenddev") > 0) {
                        FHEM.appPath = 'www/frontenddev/app/';
                    } else {
                        FHEM.appPath = 'www/frontend/app/';
                    }
                    FHEM.filelogs = [];
                    Ext.each(FHEM.info.Results, function(result) {
                        if (result.Internals.TYPE === "DbLog" && result.Internals.NAME) {
                            FHEM.dblogname = result.Internals.NAME;
                        }
                        if (result.Internals.TYPE === "FileLog") {
                            FHEM.filelogs.push(result);
                        }
                    });
                    if ((!FHEM.dblogname || Ext.isEmpty(FHEM.dblogname)) && Ext.isEmpty(FHEM.filelogs)) {
                        Ext.Msg.alert("Error", "Could not find a DbLog or FileLog Configuration. Do you have them already defined?");
                    } else {
                    	Ext.create("FHEM.view.ChartViewport", {chartid:chartid});
                        
                        //removing the loadingimage
                        var p = Ext.DomQuery.select('p[class=loader]')[0],
                            img = Ext.DomQuery.select('#loading-overlay')[0];
                        p.removeChild(img);
                        // further configuration of viewport starts in maincontroller
                    }
	            },
	            failure: function() {
	                Ext.Msg.alert("Error", "The connection to FHEM could not be established");
	            }
	        });
	    }
	});
} else {
	Ext.application({
	    name: 'FHEM Frontend',
	    requires: [
	        'FHEM.view.Viewport'
	    ],

	    controllers: [
	        'FHEM.controller.StatusController',
	        'FHEM.controller.MainController',
	        'FHEM.controller.ChartController',
	        'FHEM.controller.TableDataController'
	    ],

	    launch: function() {
	        
	        // Gather information from FHEM to display status, devices, etc.
	        var me = this,
	            url = '../../../fhem?cmd=jsonlist2&XHR=1';
	        
	        Ext.Ajax.request({
	            method: 'GET',
	            async: false,
	            disableCaching: false,
	            url: url,
	            success: function(response){
	                Ext.getBody().unmask();
	                try {
	                    FHEM.info = Ext.decode(response.responseText);
	                    
	                    if (window.location.href.indexOf("frontenddev") > 0) {
	                        FHEM.appPath = 'www/frontenddev/app/';
	                    } else {
	                        FHEM.appPath = 'www/frontend/app/';
	                    }
	                    FHEM.filelogs = [];
	                    Ext.each(FHEM.info.Results, function(result) {
	                        if (result.Internals.TYPE === "DbLog" && result.Internals.NAME) {
	                            FHEM.dblogname = result.Internals.NAME;
	                        }
	                        if (result.Internals.TYPE === "FileLog") {
	                            FHEM.filelogs.push(result);
	                        }
	                    });
	                    if ((!FHEM.dblogname || Ext.isEmpty(FHEM.dblogname)) && Ext.isEmpty(FHEM.filelogs)) {
	                        Ext.Msg.alert("Error", "Could not find a DbLog or FileLog Configuration. Do you have them already defined?");
	                    } else {
	                        Ext.create("FHEM.view.Viewport", {
	                            hidden: true
	                        });
	                        
	                        //removing the loadingimage
	                        var p = Ext.DomQuery.select('p[class=loader]')[0],
	                            img = Ext.DomQuery.select('#loading-overlay')[0];
	                        p.removeChild(img);
	                        // further configuration of viewport starts in maincontroller
	                    }
	                } catch (e) {
	                    Ext.Msg.alert("Oh no!", "JsonList did not respond correctly. This is a bug in FHEM. This Frontend cannot work without a valid JsonList response. See this link for details and complain there: http://forum.fhem.de/index.php/topic,17292.msg113132.html#msg113132");
	                }
	            },
	            failure: function() {
	                Ext.Msg.alert("Error", "The connection to FHEM could not be established");
	            }
	        });
	    }
	});
}