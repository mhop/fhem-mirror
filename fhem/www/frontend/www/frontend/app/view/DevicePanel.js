/**
 * A Panel containing device specific information
 */
Ext.define('FHEM.view.DevicePanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.devicepanel',
    
    requires: [
           'Ext.form.FieldSet',
           'Ext.layout.container.Column',
           'Ext.form.field.ComboBox'
    ],
    
    /**
     * 
     */
    title: null,
    
    /**
     * 
     */
    region: 'center',
    
    /**
     * 
     */
    record: null,
    
    /**
     * init function
     */
    initComponent: function() {
        
        var me = this;
        
        me.items = [{
            xtype: 'panel',
            autoScroll: true,
            name: 'container'
        }];
        
        me.callParent(arguments);
        
        var controlFieldset = Ext.create('Ext.form.FieldSet', {
            title: 'Controls',
            name: 'controlfieldset',
            layout: 'column',
            hidden: true,
            bodyStyle: 'padding:5px 5px 0',
            defaults: {
                margin: '0 10 10 10',
                height: 65
            }
        });
        me.down('panel[name=container]').add(controlFieldset);
        
        var devicedatastore = Ext.create('Ext.data.Store', {
            fields: ['key', 'value'],
            data: [], 
            proxy: {
                type: 'memory',
                reader: {
                    type: 'json'
                }
            }
        });
        var devicedatagrid = {
            xtype: 'grid',
            title: 'Device Data',
            name: 'devicedata',
            columns: [
                 { 
                     header: 'KEY',
                     dataIndex: 'key', 
                     width: '49%'
                 },
                 { 
                     header: 'VALUE',
                     dataIndex: 'value', 
                     width: '49%'
                 }
            ],
            store: devicedatastore
        };
        me.down('panel[name=container]').add(devicedatagrid);
            
        var devicereadingsstore = Ext.create('Ext.data.Store', {
            fields: ['key', 'value', 'measured'],
            data: [], 
            proxy: {
                type: 'memory',
                reader: {
                    type: 'json'
                }
            }
        });
        var devicereadingsgrid = {
            xtype: 'grid',
            title: 'Device Readings',
            name: 'readingsgrid',
            columns: [
                 { 
                     header: 'KEY',
                     dataIndex: 'key', 
                     width: '33%'
                 },
                 { 
                     header: 'VALUE',
                     dataIndex: 'value', 
                     width: '33%'
                 },
                 { 
                     header: 'MEASURED',
                     dataIndex: 'measured', 
                     width: '33%'
                 }
            ],
            store: devicereadingsstore
        };
        me.down('panel[name=container]').add(devicereadingsgrid);
        
        me.on("show", function() {
            me.setLoading(true);
            
            // Stop all old tasks
            Ext.TaskManager.stopAll();
            
            //remove old controls to rerender them on devicechange
            me.down('fieldset[name=controlfieldset]').removeAll();
            me.down('fieldset[name=controlfieldset]').hide();
            
            // Starting a task to update the device readings
            var task = {
                run: function(){
                    me.getDeviceData(me.record.raw.data.NAME);
                },
                interval: 5000 //5 seconds
            };
            Ext.TaskManager.start(task);
        });
        
        me.on("hide", function() {
            Ext.TaskManager.stopAll();
        });
        
    },
    
    /**
     * 
     */
    sendCommand: function(command, value) {
        var me = this,
            url = '../../../fhem?cmd=set ' + me.record.raw.data.NAME + ' '+ command;
        
        if (value && !Ext.isEmpty(value)) {
            url += ' ' + value;
        }
        url += '&XHR=1';
        
        Ext.Ajax.request({
            method: 'GET',
            disableCaching: false,
            url: url,
            success: function(response){
                if (response.status === 200) {
                    //all ok
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
                    
                    // trigger an update nearly immediately to set new values
                    var task = new Ext.util.DelayedTask(function(){
                        me.getDeviceData(me.record.raw.data.NAME);
                    });
                    task.delay(1000);
                    
                }
                
            },
            failure: function() {
                Ext.Msg.alert("Error", "Could not send command!");
            }
        });
        
    },
    
    /**
     * 
     */
    updateControls: function(results) {

        var me = this,
            allSets = results.sets,
            controlfieldset = me.down('panel[name=container] fieldset[name=controlfieldset]');
        
        if (controlfieldset.items.length <= 0) {
            
            if (results.ATTR.webCmd) {
                Ext.each(results.sets, function(set) {
                    var split = set.split(":");
                    if (split[0] === results.ATTR.webCmd) {
                        // overriding all sets as we only need the user defined webcmd now
                        allSets = set;
                    }
                });
            } 
            
            Ext.each(allSets, function(set) {
                //check for button / slider
                if (set.indexOf(":") > 0) {
                    var split = set.split(":");
                    var text = split[0];
                    
                    if (split[1].indexOf(",") > 0) { // we currently only use sets that have more than just a text
                        var splitvals = split[1].split(",");
                        
                        var subfieldset = Ext.create('Ext.form.FieldSet', {
                            title: text,
                            name: 'subcontrolfieldset'
                        });
                        controlfieldset.add(subfieldset);
                        controlfieldset.setVisible(true);
                        
                        if (splitvals.length > 3) { //make a dropdown
                            
                            var dataset = [];
                            Ext.each(splitvals, function(val) {
                                var entry = {
                                    'name':val  
                                };
                                dataset.push(entry);
                            });
                            
                            var comboStore = Ext.create('Ext.data.Store', {
                                fields: ['name'],
                                data : dataset
                            });
                            
                            var current;
                            Ext.each(results.READINGS, function(reading) {
                                Ext.iterate(reading, function(k,v) {
                                    if (k === text) {
                                        current = v;
                                    }
                                });
                            });
                            
                            var combo = Ext.create('Ext.form.ComboBox', {
                                store: comboStore,
                                padding: 8,
                                queryMode: 'local',
                                displayField: 'name',
                                valueField: 'name',
                                value: current,
                                listeners: {
                                    select: function(combo, records) {
                                        var value = records[0].data.name;
                                        me.sendCommand(text, value);
                                    }
                                }
                            });
                            subfieldset.add(combo);
                            
                        } else { // give some buttons
                            
                            Ext.each(splitvals, function(val) {
                                
                                var pressed = false;
                                Ext.each(results.READINGS, function(reading) {
                                    Ext.iterate(reading, function(k,v) {
                                        if (k === text && v === val || k === text && val === "0" && v === "null") {
                                            pressed = true;
                                        } 
                                    });
                                });
                                
                                var control = Ext.create('Ext.button.Button', {
                                   text: val,
                                   width: 120,
                                   height: 40,
                                   enableToggle: true,
                                   pressed: pressed,
                                   listeners: {
                                       click: function(btn) {
                                           var command = text,
                                               value = btn.text;
                                           me.sendCommand(command, value);
                                       }
                                   }
                                });
                                subfieldset.add(control);
                            });
                        }
                    } 
                    
                }
            });
        } else { // we already have controls added, just checkin the state if everything is up2date
            
            Ext.each(controlfieldset.items.items, function(subfieldset) {
                
                Ext.each(subfieldset.items.items, function(item) {
                    
                    var xtype = item.getXType(),
                        current;
                    
                    Ext.each(results.READINGS, function(reading) {
                        Ext.iterate(reading, function(k,v) {
                            if (k === subfieldset.title) {
                                current = v;
                            }
                        });
                    });
                    
                    if (xtype === "combobox") {
                        item.setValue(current);
                    } else if (xtype === "button") {
                        if (item.text === current || item.text === "0" && current === "null") {
                            item.toggle(true);
                        } else {
                            item.toggle(false);
                        }
                    }
                });
            });
        }
        if (controlfieldset.items.length <= 0) {
            controlfieldset.hide();
        } else {
            controlfieldset.show();
        }
        
    },
    
    /**
     * 
     */
    processReadings: function(readings) {
        
        var me = this,
            devicedata = [],
            devicegrid = me.down('panel[name=container] grid[name=devicedata]'),
            devicestore = devicegrid.getStore(),
            readingsgrid = me.down('panel[name=container] grid[name=readingsgrid]'),
            readingsstore = readingsgrid.getStore();
        
        Ext.iterate(readings, function(key, value) {
            if (key !== 'ATTR' && key !== 'attrs' &&
                key !== 'ATTRIBUTES' && key !== 'sets' && 
                key !== 'READINGS' && key !== 'CHANGETIME') {
                
                if (typeof value === "object") {
                    Ext.iterate(value, function(k, v) {
                        var obj = {
                                key: k,
                                value: v
                        };
                        devicedata.push(obj);
                    });
                    
                } else {
                    var obj = {
                            key: key,
                            value: value
                    };
                    devicedata.push(obj);
                }
            }
        });
        
        devicestore.loadData(devicedata);
        
        var readingcollection = readings.READINGS,
            readingsdata = [];
        
        Ext.each(readingcollection, function(readings) {
            Ext.each(readings, function(reading) {
                Ext.iterate(reading, function(key, value) {
                    
                    var obj;
                    if (typeof value === "object") {
                        obj = {
                                key: key,
                                value: value.VAL,
                                measured: value.TIME
                        };
                        readingsdata.push(obj);
                        
                    } else if (key !== "measured") {
                        obj = {
                                key: key,
                                value: value,
                                measured: ''
                        };
                        readingsdata.push(obj);
                    } else {
                        // as the measured time belongs to the last dataset, we merge it..
                        readingsdata[readingsdata.length - 1].measured = value;
                    }
                    
                });
            });
        });
        
        readingsstore.loadData(readingsdata);
    },
    
    /**
     * 
     */
    getDeviceData: function(name) {
        var me = this;
        Ext.Ajax.request({
            method: 'GET',
            disableCaching: false,
            url: '../../../fhem?cmd=jsonlist&XHR=1',
            scope: me,
            success: function(response){
                me.setLoading(false);
                
                var json = Ext.decode(response.responseText);
                
                var devicejson;
                Ext.each(json.Results, function(result) {
                    Ext.each(result.devices, function(device) {
                        if (device.NAME === name) {
                            devicejson = device;
                        }
                    });
                });
                if (devicejson && devicejson !== "") {
                    me.updateControls(devicejson);
                    me.processReadings(devicejson);
                } else {
                    Ext.Msg.alert("Error", "Could not get any devicedata!");
                    Ext.TaskManager.stopAll();
                }
                
                
            },
            failure: function() {
                me.setLoading(false);
                Ext.Msg.alert("Error", "Could not get any devicedata!");
                Ext.TaskManager.stopAll();
            }
        });
        
    }
});
