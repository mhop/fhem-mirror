/**
 * The Main Controller handling Main Application Logic
 */
Ext.define('FHEM.controller.MainController', {
    extend: 'Ext.app.Controller',

    refs: [
           {
               selector: 'viewport[name=mainviewport]',
               ref: 'mainviewport' //this.getMainviewport()
           },
           {
               selector: 'text[name=statustextfield]',
               ref: 'statustextfield' //this.getStatustextfield()
           },
           {
               selector: 'panel[name=culpanel]',
               ref: 'culpanel' //this.getCulpanel()
           }
           
    ],

    /**
     * init function to register listeners
     */
    init: function() {
        this.control({
            'viewport[name=mainviewport]': {
                afterrender: this.viewportRendered
            },
            'panel[name=linechartaccordionpanel]': {
                expand: this.showLineChartPanel
            },
            'panel[name=tabledataaccordionpanel]': {
                expand: this.showDatabaseTablePanel
            }
        
        });
    },
    
    /**
     * load the FHEM devices and state on viewport render completion
     */
    viewportRendered: function(){
        
        if (Ext.isDefined(FHEM.version)) {
            var sp = this.getStatustextfield();
            sp.setText(FHEM.version);
        }
        
//        var cp = me.getCulpanel();
//        if (result.list === "CUL") {
//            var culname = result.devices[0].NAME;
//            cp.add(
//                {
//                    xtype: 'text',
//                    text: culname
//                }
//            );
//        }
    },
    
    /**
     * 
     */
    showLineChartPanel: function() {
        Ext.ComponentQuery.query('panel[name=tabledatagridpanel]')[0].hide();
        Ext.ComponentQuery.query('panel[name=linechartpanel]')[0].show();
    },
    
    /**
     * 
     */
    showDatabaseTablePanel: function() {
        //TODO: use this when new dblog module is deployed
        //Ext.ComponentQuery.query('panel[name=linechartpanel]')[0].hide();
        //Ext.ComponentQuery.query('panel[name=tabledatagridpanel]')[0].show();
    }
    
});