/**
 * The Panel containing the Line Charts
 */
Ext.define('FHEM.view.LineChartPanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.linechartpanel',
    xtype : 'chart',
    requires: [
        'FHEM.view.LineChartView',
        'FHEM.store.ChartStore'
    ],
    
    title: 'Line Chart',
    
    /**
     * init function
     */
    initComponent: function() {
        
        var me = this;
        
        // set up the local db columnname store
        // as these columns are fixed, we dont have to request them
        me.comboAxesStore = Ext.create('Ext.data.Store', {
            fields: ['name'],
            data : [
                {'name':'TIMESTAMP'},
                {'name':'DEVICE'},
                {'name':'TYPE'},
                {'name':'EVENT'},
                {'name':'READING'},
                {'name':'VALUE'},
                {'name':'UNIT'}
            ]
        });
        
        me.comboDeviceStore = Ext.create('FHEM.store.DeviceStore');
        me.comboDeviceStore.on("load", function(store, e, success) {
            if(!success) {
                Ext.Msg.alert("Error", "Connection to database failed! Check your configuration.");
            }
        });
        
        me.comboReadingsStore = Ext.create('FHEM.store.ReadingsStore');
        
        me.dockedItems = [{
            xtype: 'toolbar',
            dock: 'top',
            layout: 'column',
            minheight: 60,
            maxHeight: 90,
            items: [
                {  
                    xtype: 'combobox', 
                    name: 'devicecombo',
                    fieldLabel: 'Select Device',
                    store: me.comboDeviceStore,
                    displayField: 'DEVICE',
                    valueField: 'DEVICE'
                },
                {  
                    xtype: 'combobox', 
                    name: 'xaxiscombo',
                    fieldLabel: 'Select X Axis',
                    store: me.comboAxesStore,
                    displayField: 'name',
                    valueField: 'name'
                },
                {  
                    xtype: 'combobox', 
                    name: 'yaxiscombo',
                    fieldLabel: 'Select Y Axis',
                    store: me.comboReadingsStore,
                    displayField: 'READING',
                    valueField: 'READING'
                },
                {
                    xtype: 'datefield',
                    name: 'starttimepicker',
                    format: 'Y-m-d H:i:s',
                    fieldLabel: 'Select Starttime'
                },
                {
                    xtype: 'datefield',
                    name: 'endtimepicker',
                    format: 'Y-m-d H:i:s',
                    fieldLabel: 'Select Endtime'
                },
                {
                    xtype: 'button',
                    width: 100,
                    text: 'Show Chart',
                    name: 'requestchartdata'
                },
                {
                    xtype: 'button',
                    width: 100,
                    text: 'Save Chart',
                    name: 'savechartdata'
                },
                {
                    xtype: 'button',
                    width: 100,
                    text: 'Step back',
                    name: 'stepback'
                },
                {
                    xtype: 'button',
                    width: 100,
                    text: 'Step forward',
                    name: 'stepforward'
                }
            ]
        }];
        
        me.items = [
                {
                    xtype: 'linechartview',
                    width: '100%'
                }
        ];
        
        me.callParent(arguments);
        
    }
    
});
