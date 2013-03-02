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
        'FHEM.controller.ChartController'
    ],

    launch: function() {
        
        // Gather information from FHEM to display status, devices, etc.
        var me = this,
            url = '../../../fhem?cmd=jsonlist&XHR=1';
        Ext.getBody().mask("Please wait while the Frontend is starting...");
        Ext.Ajax.request({
            method: 'GET',
            async: false,
            disableCaching: false,
            url: url,
            success: function(response){
                Ext.getBody().unmask();
                var json = Ext.decode(response.responseText);
                FHEM.version = json.Results[0].devices[0].ATTR.version;
                
                Ext.each(json.Results, function(result) {
                    //TODO: get more specific here...
                    if (result.list === "DbLog" && result.devices[0].NAME) {
                        FHEM.dblogname = result.devices[0].NAME;
                    }
                });
                if (!FHEM.dblogname && Ext.isEmpty(FHEM.dblogname)) {
                    Ext.Msg.alert("Error", "Could not find a DbLog Configuration. Do you have DbLog already running?");
                } else {
                    Ext.create("FHEM.view.Viewport");
                }
            },
            failure: function() {
                Ext.Msg.alert("Error", "The connection to FHEM could not be established");
            }
        });
        
    }
});