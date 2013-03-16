/**
 * A Panel containing device specific information
 */
Ext.define('FHEM.view.DevicePanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.devicepanel',
    
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
        
        var devicedata = [];
        
        Ext.iterate(me.record.raw.data, function(key, value) {
            if (key !== 'ATTR' && key !== 'attrs' && key !== 'sets' && key !== 'READINGS') {
                var obj = {
                     key: key,
                     value: value
                };
                
                devicedata.push(obj);
            }
        });
        
        if (devicedata.length > 0) {
            var devicedatastore = Ext.create('Ext.data.Store', {
                fields: ['key', 'value'],
                data: devicedata, 
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
                //hideHeaders: true,
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
        }
        
        var readingcollection = me.record.raw.data.READINGS;
        if (readingcollection && !Ext.isEmpty(readingcollection) && readingcollection.length > 0) {
            
            var readingsdata = [];
            Ext.each(readingcollection, function(readings) {
                Ext.each(readings, function(reading) {
                    Ext.iterate(reading, function(key, value) {
                        
                        if (key !== "measured") {
                            var obj = {
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
            
            var devicereadingsstore = Ext.create('Ext.data.Store', {
                fields: ['key', 'value', 'measured'],
                data: readingsdata, 
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
        }
        
    }
    
});
