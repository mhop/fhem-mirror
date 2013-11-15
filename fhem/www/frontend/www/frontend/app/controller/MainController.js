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
            'panel[name=fhemaccordion]': {
                expand: this.showFHEMPanel
            },
            'panel[name=tabledataaccordionpanel]': {
                expand: this.showDatabaseTablePanel
            },
            'treepanel[name=maintreepanel]': {
                itemclick: this.showDeviceOrChartPanel,
                treeupdated: this.setupTree
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
            },
            'button[name=unsortedtree]': {
                click: this.setupTree
            },
            'button[name=sortedtree]': {
                click: this.setupTree
            }
        });
    },
    
    /**
     * fade-in viewport, load the FHEM devices and state on viewport render completion
     */
    viewportRendered: function() {
        
        var me = this;
        
        me.createFHEMPanel();
        me.createDevicePanel();
        me.createLineChartPanel();
        me.createDatabaseTablePanel();
        
        me.getMainviewport().show();
        me.getMainviewport().getEl().setOpacity(0);
        me.getMainviewport().getEl().animate({
            opacity: 1, 
            easing: 'easeIn',
            duration: 500,
            remove: false
        });
        
        if (Ext.isDefined(FHEM.version)) {
            var sp = this.getStatustextfield();
            sp.setText(FHEM.version + "; Frontend Version: 1.0 - 2013-11-15");
        }
        
        this.setupTree(false);
    },
    
    /**
     * setup west accordion / treepanel
     */
    setupTree: function(unsorted) {
        var me = this,
            rootNode = { text:"root", expanded: true, children: []},
            oldRootNode = me.getMaintreepanel().getRootNode();
        
        //first cleanup
        if (oldRootNode) {
            oldRootNode.removeAll();
        }
        if (unsorted && unsorted.name === 'unsortedtree') {
            //setup the tree "unsorted"
            Ext.each(FHEM.info.Results, function(result) {
                if (result.list && !Ext.isEmpty(result.list)) {
                    if (result.devices && result.devices.length > 0) {
                        var blacklist = ['dummy', 'notify', 'Global', 'telnet', 'DbLog', 'FileLog', 'FHEMWEB', 'weblink'];
                        if (Ext.Array.contains(blacklist, result.list)) {
                            node = {text: result.list, expanded: false, children: []};
                        } else {
                            node = {text: result.list, expanded: true, children: []};
                        }
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
            this.addChartsToTree();
        } else {
            //sort / create items by room
            me.getMaintreepanel().setRootNode(rootNode);
            var root = me.getMaintreepanel().getRootNode();
            Ext.each(FHEM.info.Results, function(result) {
                if (result.list && !Ext.isEmpty(result.list)) {
                    if (result.devices && result.devices.length > 0) {
                        Ext.each(result.devices, function(device) {
                            if (device.ATTR && device.ATTR.room) {
                                //check if room exists
                                var resultnode = root.findChild("text", device.ATTR.room, true),
                                    subnode = {text: device.NAME, leaf: true, data: device};
                                if (!resultnode) {
                                    //create roomfolder
                                    var roomfolder;
                                    if (device.ATTR.room !== "hidden") {
                                        roomfolder = {text: device.ATTR.room, leaf: false, expanded: true, children: []};
                                        roomfolder.children.push(subnode);
                                        root.appendChild(roomfolder);
                                    }
                                } else {
                                    resultnode.appendChild(subnode);
                                    root.appendChild(resultnode);
                                }
                            }
                        }, this);
                    } else {
                        node = {text: result.list, leaf: true};
                        root.appendChild(node);
                    }
                }
            });
            this.addChartsToTree();
        }
    },
    
    /**
     * 
     */
    addChartsToTree: function() {
      //load the saved charts store with configured dblog name
        var me = this,
            store = Ext.create('FHEM.store.SavedChartsStore', {});
        store.getProxy().url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getcharts&XHR=1';
        store.load();
        //add the charts to the tree
        store.on("load", function() {
            var rootNode = me.getMaintreepanel().getRootNode(),
                chartfolder = {text: "Charts", expanded: true, children: []};
            rootNode.appendChild(chartfolder);
            var chartfoldernode = rootNode.findChild("text", "Charts", true);
            
            store.each(function(rec) {
                var chartchild,
                    unsortedMode = Ext.ComponentQuery.query('button[name=unsortedtree]')[0].pressed;
                
                if (!unsortedMode && rec.raw && rec.raw.VALUE && rec.raw.VALUE.parentFolder) {
                    var ownerFolder = rec.raw.VALUE.parentFolder,
                        index = rec.raw.VALUE.treeIndex,
                        parentNode = rootNode.findChild("text", ownerFolder, true);
                    
                    chartchild = {text: rec.raw.NAME, leaf: true, data: rec.raw, iconCls:'x-tree-icon-leaf-chart'};
                    if (parentNode === null) {
                        rootNode.insertChild(index, chartchild);
                    } else {
                        parentNode.insertChild(index, chartchild);
                    }
                } else {
                    chartchild = {text: rec.raw.NAME, leaf: true, data: rec.raw, iconCls:'x-tree-icon-leaf-chart'};
                    chartfoldernode.appendChild(chartchild);
                }
            });
            
            // at last we add a chart template to the folder which wont be saved to db and cannot be deleted
            chartchild = {text: 'Create new Chart', leaf: true, data: {template: true}, iconCls:'x-tree-icon-leaf-chart'};
            chartfoldernode.appendChild(chartchild);
            
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
    hideCenterPanels: function() {
        var panels = Ext.ComponentQuery.query('panel[region=center]');
        Ext.each(panels, function(panel) {
            panel.hide();
        });
    },
    
    /**
     * 
     */
    showDeviceOrChartPanel: function(treeview, rec) {
        var me = this;
        if (rec.raw.data.template === true || rec.get('leaf') === true && 
            rec.raw.data &&
            rec.raw.data.TYPE && 
            rec.raw.data.TYPE === "savedchart") {
                this.showLineChartPanel();
        } else {
            this.showDevicePanel(treeview, rec);
        }
    },
    
    /**
     * 
     */
    showFHEMPanel: function() {
        var panel = Ext.ComponentQuery.query('panel[name=fhempanel]')[0];
        this.hideCenterPanels();
        panel.show();
    },
    
    /**
     * 
     */
    createFHEMPanel: function() {
        var panel = {
            xtype: 'panel',
            name: 'fhempanel',
            title: 'FHEM',
            region: 'center',
            layout: 'fit',
            hidden: true,
            items : [
                {
                    xtype : 'component',
                    autoEl : {
                        tag : 'iframe',
                        src : '../../fhem?'
                    }
                }
            ]
        };
        this.getMainviewport().add(panel);
    },
    
    /**
     * 
     */
    showDevicePanel: function(view, record) {
        
        if (record.raw.leaf === true) {
            var panel = Ext.ComponentQuery.query('devicepanel')[0];
            var title;
            if (record.raw.ATTR && 
                record.raw.ATTR.alias && 
                !Ext.isEmpty(record.raw.ATTR.alias)) {
                    title = record.raw.data.ATTR.alias;
            } else {
                title = record.raw.data.NAME;
            }
            panel.setTitle(title);
            panel.record = record;
            
            this.hideCenterPanels();
            panel.show();
        }
        
    },
    
    /**
     * 
     */
    createDevicePanel: function() {
        var panel = {
            xtype: 'devicepanel',
            title: null,
            region: 'center',
            layout: 'fit',
            record: null,
            hidden: true
        };
        this.getMainviewport().add(panel);
    },
    
    /**
     * 
     */
    showLineChartPanel: function() {
        var panel = Ext.ComponentQuery.query('linechartpanel')[0];
        this.hideCenterPanels();
        panel.show();
    },
    
    /**
     * 
     */
    createLineChartPanel: function() {
        var panel = {
            xtype: 'linechartpanel',
            name: 'linechartpanel',
            region: 'center',
            layout: 'fit',
            hidden: true
        };
        this.getMainviewport().add(panel);
    },
    
    /**
     * 
     */
    createDatabaseTablePanel: function() {
        var panel = {
            xtype: 'tabledatagridpanel',
            name: 'tabledatagridpanel',
            region: 'center',
            layout: 'fit',
            hidden: true
        };
        this.getMainviewport().add(panel);
        
    },
    
    /**
     * 
     */
    showDatabaseTablePanel: function() {
        var panel = Ext.ComponentQuery.query('tabledatagridpanel')[0];
        this.hideCenterPanels();
        panel.show();
    }
    
});