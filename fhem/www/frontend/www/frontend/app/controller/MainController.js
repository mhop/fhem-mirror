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
               selector: 'panel[name=maintreepanel]',
               ref: 'maintreepanel' //this.getMaintreepanel()
           },
           {
               selector: 'textfield[name=commandfield]',
               ref: 'commandfield' //this.getCommandfield()
           },
           {
               selector: 'grid[name=savedchartsgrid]',
               ref: 'savedchartsgrid' //this.getSavedchartsgrid()
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
            'treepanel[name=maintreepanel]': {
                itemclick: this.showDevicePanel
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
     * fade-in viewport, load the FHEM devices and state on viewport render completion
     */
    viewportRendered: function() {
        
        var me = this;
        
        me.getMainviewport().show();
        me.getMainviewport().getEl().setOpacity(0);
        me.getMainviewport().getEl().animate({
            opacity: 1, 
            easing: 'easeIn',
            duration: 500,
            remove: false
        });
        
        //load the saved charts store with configured dblog name
        var store = this.getSavedchartsgrid().getStore();
        store.getProxy().url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getcharts&XHR=1';
        store.load();
        
        if (Ext.isDefined(FHEM.version)) {
            var sp = this.getStatustextfield();
            sp.setText(FHEM.version + "; Frontend Version: 0.4 - 2013-04-09");
        }
        
        //setup west accordion / treepanel
        var wp = this.getWestaccordionpanel(),
            rootNode = { text:"root", expanded: true, children: []};
        
        Ext.each(FHEM.info.Results, function(result) {
            
            if (result.list && !Ext.isEmpty(result.list)) {
                
                if (result.devices && result.devices.length > 0) {
                    node = {text: result.list, expanded: true, children: []};
                    
                    Ext.each(result.devices, function(device) {
                        
                        var subnode = {text: device.NAME, leaf: true, data: device};
                        node.children.push(subnode);
                        
                    }, this);
                } else {
                    node = {text: result.list, leaf: true};
                }
            
                rootNode.children.push(node);
                
            }
        });
        
        this.getMaintreepanel().setRootNode(rootNode);
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
                });
                win.showAt(Ext.getBody().getWidth() / 2 -100, 30);
                win.getEl().animate({
                    opacity: 0, 
                    easing: 'easeOut',
                    duration: 3000,
                    delay: 2000,
                    remove: false,
                    listeners: {
                        afteranimate:  function() {
                            win.destroy();
                        }
                    }
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
                        });
                        win.showAt(Ext.getBody().getWidth() / 2 -100, 30);
                        win.getEl().animate({
                            opacity: 0, 
                            easing: 'easeOut',
                            duration: 3000,
                            delay: 2000,
                            remove: false,
                            listeners: {
                                afteranimate:  function() {
                                    win.destroy();
                                }
                            }
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
        });
        win.showAt(Ext.getBody().getWidth() / 2 -100, 30);
        win.getEl().animate({
            opacity: 0, 
            easing: 'easeOut',
            duration: 3000,
            delay: 2000,
            remove: false,
            listeners: {
                afteranimate:  function() {
                    win.destroy();
                }
            }
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
    destroyCenterPanels: function() {
        var panels = Ext.ComponentQuery.query('panel[region=center]');
        Ext.each(panels, function(panel) {
            panel.destroy();
        });
    },
    
    /**
     * 
     */
    showDevicePanel: function(view, record) {
        
        var title;
        if (record.raw.ATTR && record.raw.ATTR.alias && !Ext.isEmpty(record.raw.ATTR.alias)) {
            title = record.raw.data.ATTR.alias;
        } else {
            title = record.raw.data.NAME;
        }
        var panel = {
            xtype: 'devicepanel',
            title: title,
            region: 'center',
            layout: 'fit',
            record: record,
            hidden: true
        };
        this.destroyCenterPanels();
        this.getMainviewport().add(panel);
        
        var createdpanel = this.getMainviewport().down('devicepanel');
        
        createdpanel.getEl().setOpacity(0);
        createdpanel.show();
        
        createdpanel.getEl().animate({
            opacity: 1, 
            easing: 'easeIn',
            duration: 500,
            remove: false
        });
        
    },
    
    /**
     * 
     */
    showLineChartPanel: function() {
        
        var panel = {
            xtype: 'linechartpanel',
            name: 'linechartpanel',
            region: 'center',
            layout: 'fit',
            hidden: true
        };
        this.destroyCenterPanels();
        this.getMainviewport().add(panel);
        
        var createdpanel = this.getMainviewport().down('linechartpanel');
        
        createdpanel.getEl().setOpacity(0);
        createdpanel.show();
        
        createdpanel.getEl().animate({
            opacity: 1, 
            easing: 'easeIn',
            duration: 500,
            remove: false
        });
        
    },
    
    /**
     * 
     */
    showDatabaseTablePanel: function() {
        var panel = {
            xtype: 'tabledatagridpanel',
            name: 'tabledatagridpanel',
            region: 'center',
            layout: 'fit',
            hidden: true
        };
        this.destroyCenterPanels();
        this.getMainviewport().add(panel);
        
        var createdpanel = this.getMainviewport().down('tabledatagridpanel');
        
        createdpanel.getEl().setOpacity(0);
        createdpanel.show();
        
        createdpanel.getEl().animate({
            opacity: 1, 
            easing: 'easeIn',
            duration: 500,
            remove: false
        });
    }
    
});