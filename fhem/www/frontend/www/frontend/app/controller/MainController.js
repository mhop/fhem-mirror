/**
 * The Main Controller handling Main Application Logic
 */
Ext.define('FHEM.controller.MainController', {
    extend: 'Ext.app.Controller',
    requires: [
       'FHEM.view.DevicePanel'
    ],

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
               selector: 'panel[name=westaccordionpanel]',
               ref: 'westaccordionpanel' //this.getWestaccordionpanel()
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
    viewportRendered: function() {
        
        var me = this;
        
        if (Ext.isDefined(FHEM.version)) {
            var sp = this.getStatustextfield();
            sp.setText(FHEM.version + "; Frontend Version: 0.2 - 2013-03-08");
        }
        
        //setup west accordion
        var wp = this.getWestaccordionpanel();
        
        Ext.each(FHEM.info.Results, function(result) {
            if (result.list && !Ext.isEmpty(result.list)) {
                var panelToAdd = Ext.create('Ext.panel.Panel', {
                      name: result.list,
                      title: result.list,
                      autoScroll: true,
                      items: []
                });
                
                if (result.devices && result.devices.length > 0) {
                    //creating a store holding fhem devices
                    var deviceStore = Ext.create('Ext.data.Store', {
                        fields:['NAME'],
                        data: result.devices,
                        proxy: {
                            type: 'memory',
                            reader: {
                                type: 'json',
                                root: 'devices'
                            }
                        }
                    });
                    
                    var devicesgrid = {
                        xtype: 'grid',
                        hideHeaders: true,
                        columns: [
                             { 
                                 dataIndex: 'NAME', 
                                 width: '95%'
                             }
                        ],
                        store: deviceStore,
                        listeners: {
                            itemclick: function(gridview, record) {
                                var panel = {
                                      xtype: 'devicepanel',
                                      title: record.raw.NAME,
                                      region: 'center',
                                      layout: 'fit',
                                      record: record
                                };
                                me.hideCenterPanels();
                                me.getMainviewport().add(panel);
                            }
                        }
                    };
                    
                    panelToAdd.add(devicesgrid);
                }
                wp.add(panelToAdd);
            }
        });
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
                    delay: 2000,
                    remove: true
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
                            delay: 2000,
                            remove: true
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
            delay: 2000,
            remove: true
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
                        me.retryConnect();
                    }
                    
                },
                failure: function() {
                    me.retryConnect();
                }
            });
        });

        task.delay(1000);
        
    },
    
    /**
     * 
     */
    hideCenterPanels: function() {
        var panels = Ext.ComponentQuery.query('panel[region=center]');
        Ext.each(panels, function(panel) {
            panel.hide();
        });
    },
    
    /**
     * 
     */
    showLineChartPanel: function() {
        this.hideCenterPanels();
        Ext.ComponentQuery.query('panel[name=linechartpanel]')[0].show();
    },
    
    /**
     * 
     */
    showDatabaseTablePanel: function() {
        this.hideCenterPanels();
        Ext.ComponentQuery.query('panel[name=tabledatagridpanel]')[0].show();
    }
    
});