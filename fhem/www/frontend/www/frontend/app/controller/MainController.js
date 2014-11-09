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
            'panel[name=fhemstatusaccordion]': {
                expand: this.showFHEMStatusPanel
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
            'panel[name=statuspanel]': {
                saveconfig: this.saveObjectToUserConfig
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
        
        me.getMainviewport().show();
        me.getMainviewport().getEl().setOpacity(0);
        me.getMainviewport().getEl().animate({
            opacity: 1, 
            easing: 'easeIn',
            duration: 500,
            remove: false
        });
        
        var sp = this.getStatustextfield();
        sp.setText("Frontend Version: 1.1.1 - 2014-11-09");
        
        this.setupTree();
    },
    
    /**
     * setup west accordion / treepanel
     */
    setupTree: function() {
        var me = this,
            rootNode = { text:"root", expanded: true, children: []},
            oldRootNode = me.getMaintreepanel().getRootNode();
        
        //first cleanup
        if (oldRootNode) {
            oldRootNode.removeAll();
        }
        //sort / create items by room
        var rooms = [];
        Ext.each(FHEM.info.Results, function(result) {
            
            // get all rooms
            if (result.Attributes && result.Attributes.room) {
                var roomArray = result.Attributes.room.split(",");
                Ext.each(roomArray, function(room) {
                    if (!Ext.Array.contains(rooms, room)) {
                        var roomfolder;
                        if (room === "Unsorted") {
                            roomfolder = {text: room, leaf: false, expanded: false, children: []};
                            rootNode.children.push(roomfolder);
                        } else if (room !== "hidden") {
                            roomfolder = {text: room, leaf: false, expanded: true, children: []};
                            rootNode.children.push(roomfolder);
                        }
                        rooms.push(room);
                    }
                });
            }
        });
        
        Ext.each(FHEM.info.Results, function(result) {
                if (result.Attributes && result.Attributes.room && result.Attributes.room !== "hidden") {
                    //get room
                    Ext.each(rootNode.children, function(room) {
                        if (room.text === result.Attributes.room) {
                            var subnode = {text: result.Internals.NAME, leaf: true, data: result};
                            room.children.push(subnode);
                            return false;
                        }
                    });
                }
        });
        me.getMaintreepanel().setRootNode(rootNode);
        this.addChartsToTree();
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
                chartfolder = {text: "Charts", expanded: true, children: []},
                statusfolder = {text: "StatusRoom", expanded: true, children: []};
            rootNode.appendChild(chartfolder);
            rootNode.appendChild(statusfolder);
            var chartfoldernode = rootNode.findChild("text", "Charts", true);
            
            //add the filelogcharts to the store
            if (FHEM.filelogcharts) {
                store.add(FHEM.filelogcharts);
            }
            
            store.each(function(rec) {
                var chartchild;
                
                if (rec.raw && rec.raw.VALUE && rec.raw.VALUE.parentFolder) {
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
            
            // sort root by treeindex as inserting with index whil some objects not added may be faulty
            rootNode.sort(function(rec, rec2) {
                if (rec && rec.raw && rec.raw.data && rec.raw.data.VALUE && 
                    rec2 && rec2.raw && rec2.raw.data && rec2.raw.data.VALUE) {
                        if (rec.raw.data.VALUE.treeIndex > rec2.raw.data.VALUE.treeIndex) {
                            return 1;
                        } else {
                            return -1;
                        }
                    }
            }, true);
            
            // at last we add a chart template to the folder which wont be saved to db and cannot be deleted
            chartchild = {text: 'Create new Chart', leaf: true, data: {template: true}, iconCls:'x-tree-icon-leaf-chart'};
            chartfoldernode.appendChild(chartchild);
            
            me.getMaintreepanel().fireEvent('treeloaded');
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
                url: '../../../fhem?cmd=jsonlist2&XHR=1',
            
                success: function(response){
                    if (response.responseText !== "Unknown command JsonList2, try help↵") {
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
            (rec.raw.data.TYPE === "savedchart" || rec.raw.data.TYPE === "savedfilelogchart")) {
                this.showLineChartPanel();
        } else {
            this.showDevicePanel(treeview, rec);
        }
    },
    
    /**
     * 
     */
    showFHEMStatusPanel: function() {
        var panel = Ext.ComponentQuery.query('statuspanel')[0];
        this.hideCenterPanels();
        panel.show();
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
            if (record.raw.data.Attributes && 
                record.raw.data.Attributes.alias && 
                !Ext.isEmpty(record.raw.data.Attributes.alias)) {
                    title = record.raw.data.Attributes.alias;
            } else {
                title = record.raw.data.Internals.NAME;
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
        if (!panel) {
            this.createLineChartPanel();
            panel = Ext.ComponentQuery.query('linechartpanel')[0];
        }
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
        if (!panel) {
            this.createDatabaseTablePanel();
            panel = Ext.ComponentQuery.query('tabledatagridpanel')[0];
        }
        this.hideCenterPanels();
        panel.show();
    },
    
    /**
     * Method appending and saving a given object to the file userconfig.js, which is loaded on page load
     * The location names the accesible part where the object should be saved in
     */
    saveObjectToUserConfig: function(objectToSave, location) {
        
        var me = this;
        
        if (FHEM.userconfig && objectToSave && !Ext.isEmpty(location)) {
            
            FHEM.userconfig[location] = objectToSave;
            
            // preapre the string for the file
            var finalstring = "FHEM = {};;FHEM.userconfig = " + Ext.encode(FHEM.userconfig) + ";;";
            
            var cmd = "{ `echo '" + finalstring + "' > " + FHEM.appPath + "userconfig.js`}";
            
            Ext.Ajax.request({
                method: 'POST',
                disableCaching: false,
                url: '../../../fhem?',
                params: {
                    cmd: cmd,
                    XHR: 1
                },
                success: function(response){
                    if (response.status === 200) {
                        Ext.Msg.alert("Success", "Changes successfully saved!");
                    } else if (response.statusText) {
                        Ext.Msg.alert("Error", "The Changes could not be saved, error Message is:<br><br>" + response.statusText);
                    } else {
                        Ext.Msg.alert("Error", "The Changes could not be saved!");
                    }
                },
                failure: function(response) {
                    if (response.statusText) {
                        Ext.Msg.alert("Error", "The Changes could not be saved, error Message is:<br><br>" + response.statusText);
                    } else {
                        Ext.Msg.alert("Error", "The Changes could not be saved!");
                    }
                }
            });
            
        } else {
            Ext.Msg.alert("Error", "A save attempt was made without enough parameters!");
        }
        
    }
});