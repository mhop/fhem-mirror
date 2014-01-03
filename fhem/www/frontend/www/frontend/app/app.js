/**
 * Setup the application
 */

Ext.Loader.setConfig({
    enabled: true,
    disableCaching: false,
    paths: {
        'FHEM': 'app'
    }
});

Ext.application({
    name: 'FHEM Frontend',
    requires: [
        'FHEM.view.Viewport'        
    ],

    controllers: [
        'FHEM.controller.MainController',
        'FHEM.controller.ChartController',
        'FHEM.controller.TableDataController'
    ],

    launch: function() {
        
        // Gather information from FHEM to display status, devices, etc.
        var me = this,
            url = '../../../fhem?cmd=jsonlist&XHR=1';
        
        Ext.Ajax.request({
            method: 'GET',
            async: false,
            disableCaching: false,
            url: url,
            success: function(response){
                Ext.getBody().unmask();
                try {
                    FHEM.info = Ext.decode(response.responseText);
                    FHEM.version = FHEM.info.Results[0].devices[0].ATTR.version;
                    Ext.each(FHEM.info.Results, function(result) {
                        if (result.list === "DbLog" && result.devices[0].NAME) {
                            FHEM.dblogname = result.devices[0].NAME;
                        }
                        if (result.list === "FileLog" && result.devices.length > 0) {
                            FHEM.filelogs = result.devices;
                        }
                    });
                    if ((!FHEM.dblogname || Ext.isEmpty(FHEM.dblogname)) && !FHEM.filelogs) {
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