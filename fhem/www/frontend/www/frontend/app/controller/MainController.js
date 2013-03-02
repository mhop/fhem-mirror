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
           },
           {
               selector: 'textfield[name=commandfield]',
               ref: 'commandfield' //this.getCommandfield()
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
            },
            'textfield[name=commandfield]': {
                specialkey: this.checkCommand
            },
            'button[name=saveconfig]': {
                click: this.saveConfig
            },
            'button[name=executecommand]': {
                click: this.submitCommand
            },
            'button[name=shutdownfhem]': {
                click: this.shutdownFhem
            },
            'button[name=restartfhem]': {
                click: this.restartFhem
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
    saveConfig: function() {
        
        var command = this.getCommandfield().getValue();
        if (command && !Ext.isEmpty(command)) {
            this.submitCommand();
        }
        
        Ext.Ajax.request({
            method: 'GET',
            disableCaching: false,
            url: '../../../fhem?cmd=save',
            success: function(response){
                
                var win = Ext.create('Ext.window.Window', {
                    width: 110,
                    height: 60,
                    html: 'Save successful!',
                    preventHeader: true,
                    border: false,
                    closable: false,
                    plain: true
                });win.showAt(Ext.getBody().getWidth() / 2 -100, 30);
                win.getEl().animate({
                    opacity: 0, 
                    easing: 'easeOut',
                    duration: 3000,
                    delay: 2000
                });
            },
            failure: function() {
                Ext.Msg.alert("Error", "Could not save the current configuration!");
            }
        });
    },
    
    /**
     * 
     */
    checkCommand: function(field, e) {
        if (e.getKey() == e.ENTER && !Ext.isEmpty(field.getValue())) {
            this.submitCommand();
        }
    },
    
    /**
     * 
     */
    submitCommand: function() {
        
        var command = this.getCommandfield().getValue();
        
        if (command && !Ext.isEmpty(command)) {
            Ext.Ajax.request({
                method: 'GET',
                disableCaching: false,
                url: '../../../fhem?cmd=' + command + '&XHR=1',
                success: function(response){
                    
                    if(response.responseText && !Ext.isEmpty(response.responseText)) {
                        Ext.create('Ext.window.Window', {
                            maxWidth: 600,
                            maxHeight: 500,
                            autoScroll: true,
                            layout: 'fit',
                            title: "Response",
                            items: [
                                {
                                    xtype: 'panel',
                                    autoScroll: true,
                                    items:[
                                       {
                                           xtype: 'displayfield',
                                           htmlEncode: true,
                                           value: response.responseText
                                       }
                                    ]
                                }
                            ]
                        }).show();
                    } else {
                        var win = Ext.create('Ext.window.Window', {
                            width: 130,
                            height: 60,
                            html: 'Command submitted!',
                            preventHeader: true,
                            border: false,
                            closable: false,
                            plain: true
                        });win.showAt(Ext.getBody().getWidth() / 2 -100, 30);
                        win.getEl().animate({
                            opacity: 0, 
                            easing: 'easeOut',
                            duration: 3000,
                            delay: 2000
                        });
                    }
                    
                },
                failure: function() {
                    Ext.Msg.alert("Error", "Could not submit the command!");
                }
        });
        }
        
    },
    
    /**
     * 
     */
    shutdownFhem: function() {
        Ext.Ajax.request({
            method: 'GET',
            disableCaching: false,
            url: '../../../fhem?cmd=shutdown&XHR=1'
        });
        var win = Ext.create('Ext.window.Window', {
            width: 130,
            height: 60,
            html: 'Shutdown submitted!',
            preventHeader: true,
            border: false,
            closable: false,
            plain: true
        });win.showAt(Ext.getBody().getWidth() / 2 -100, 30);
        win.getEl().animate({
            opacity: 0, 
            easing: 'easeOut',
            duration: 3000,
            delay: 2000
        });
    },
    
    /**
     * 
     */
    restartFhem: function() {
        Ext.Ajax.request({
            method: 'GET',
            disableCaching: false,
            url: '../../../fhem?cmd=shutdown restart&XHR=1'
        });
        Ext.getBody().mask("Please wait while FHEM is restarting...");
        this.retryConnect();
        
    },
    
    /**
     * 
     */
    retryConnect: function() {
        var me = this;
        
        var task = new Ext.util.DelayedTask(function(){
            Ext.Ajax.request({
                method: 'GET',
                disableCaching: false,
                url: '../../../fhem?cmd=jsonlist&XHR=1',
            
                success: function(response){
                    if (response.responseText !== "Unknown command JsonList, try help↵") {
                        //restarting the frontend
                        window.location.reload();
                    } else {
                        console.log("fail..");
                        me.retryConnect();
                    }
                    
                },
                failure: function() {
                    console.log("failure..");
                    me.retryConnect();
                }
            });
        });

        task.delay(1000);
        
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
        Ext.ComponentQuery.query('panel[name=linechartpanel]')[0].hide();
        Ext.ComponentQuery.query('panel[name=tabledatagridpanel]')[0].show();
    }
    
});