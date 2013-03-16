/**
 * The Panel containing the Line Charts
 */
Ext.define('FHEM.view.LineChartPanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.linechartpanel',
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
        
        me.comboColorStore = Ext.create('Ext.data.Store', {
            fields: ['name', 'value'],
            data : [
                {'name':'Blue','value':'#2F40FA'},
                {'name':'Green', 'value':'#46E01B'},
                {'name':'Orange','value':'#F0A800'},
                {'name':'Red','value':'#E0321B'},
                {'name':'Yellow','value':'#F5ED16'}
            ]
        });
        
        me.comboDeviceStore = Ext.create('FHEM.store.DeviceStore');
        me.comboDevice2Store = Ext.create('FHEM.store.DeviceStore');
        me.comboDevice3Store = Ext.create('FHEM.store.DeviceStore');
        
        me.comboDeviceStore.on("load", function(store, recs, success, operation) {
            if(!success) {
                Ext.Msg.alert("Error", "Something went wrong. Store Items: " + store.getCount() + ", loaded Items: " + recs.length + ", Reader rawrecords: " + store.getProxy().getReader().rawData.data.length + ", proxyURL: " + store.getProxy().url);
            }
        });
        
        me.comboReadingsStore = Ext.create('FHEM.store.ReadingsStore');
        me.comboReadings2Store = Ext.create('FHEM.store.ReadingsStore');
        me.comboReadings3Store = Ext.create('FHEM.store.ReadingsStore');
        
        var chartSettingPanel = Ext.create('Ext.form.Panel', {
            title: 'Chart Settings - Click me to edit',
            name: 'chartformpanel',
            maxHeight: 285,
            autoScroll: true,
            collapsible: true,
            titleCollapse: true,
            listeners: {
                collapse: me.layoutChart,
                expand: me.layoutChart
            },
            items: [
                {
                    xtype: 'fieldset',
                    layout: 'column',
                    title: 'Select data',
                    defaults: {
                        margin: '0 10 10 10'
                    },
                    items: [
                        {  
                          xtype: 'combobox', 
                          name: 'devicecombo',
                          fieldLabel: 'Select Device',
                          labelWidth: 90,
                          store: me.comboDeviceStore,
                          displayField: 'DEVICE',
                          valueField: 'DEVICE'
                        },
                        {  
                          xtype: 'combobox', 
                          name: 'xaxiscombo',
                          fieldLabel: 'Select X Axis',
                          labelWidth: 90,
                          inputWidth: 100,
                          store: me.comboAxesStore,
                          displayField: 'name',
                          valueField: 'name'
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'yaxiscombo',
                            fieldLabel: 'Select Y-Axis',
                            labelWidth: 90,
                            inputWidth: 110,
                            store: me.comboReadingsStore,
                            displayField: 'READING',
                            valueField: 'READING'
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'yaxiscolorcombo',
                            fieldLabel: 'Y-Color',
                            labelWidth: 50,
                            inputWidth: 70,
                            store: me.comboColorStore,
                            displayField: 'name',
                            valueField: 'value',
                            value: me.comboColorStore.getAt(0)
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'yaxisfillcheck',
                            boxLabel: 'Fill'
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'device2combo',
                            fieldLabel: 'Select 2. Device',
                            labelWidth: 100,
                            store: me.comboDevice2Store,
                            displayField: 'DEVICE',
                            valueField: 'DEVICE',
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'y2axiscombo',
                            fieldLabel: 'Y2',
                            labelWidth: 20,
                            store: me.comboReadings2Store,
                            displayField: 'READING',
                            valueField: 'READING',
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'y2axiscolorcombo',
                            fieldLabel: 'Y2-Color',
                            labelWidth: 60,
                            inputWidth: 70,
                            store: me.comboColorStore,
                            displayField: 'name',
                            valueField: 'value',
                            value: me.comboColorStore.getAt(1),
                            hidden: true
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'y2axisfillcheck',
                            boxLabel: 'Fill',
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'device3combo',
                            fieldLabel: 'Select 3. Device',
                            labelWidth: 100,
                            store: me.comboDevice3Store,
                            displayField: 'DEVICE',
                            valueField: 'DEVICE',
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'y3axiscombo',
                            fieldLabel: 'Y3',
                            labelWidth: 20,
                            store: me.comboReadings3Store,
                            displayField: 'READING',
                            valueField: 'READING',
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'y3axiscolorcombo',
                            fieldLabel: 'Y3-Color',
                            labelWidth: 60,
                            inputWidth: 70,
                            store: me.comboColorStore,
                            displayField: 'name',
                            valueField: 'value',
                            value: me.comboColorStore.getAt(2),
                            hidden: true
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'y3axisfillcheck',
                            boxLabel: 'Fill',
                            hidden: true
                        },
                        {
                          xtype: 'button',
                          width: 110,
                          text: 'Add another Y-Axis',
                          name: 'addyaxisbtn',
                          handler: function(btn) {
                              var y2device = btn.up().down('combobox[name=device2combo]');
                              var y2 = btn.up().down('combobox[name=y2axiscombo]');
                              var y2color = btn.up().down('combobox[name=y2axiscolorcombo]');
                              var y2fill = btn.up().down('checkboxfield[name=y2axisfillcheck]');
                              
                              var y3device = btn.up().down('combobox[name=device3combo]');
                              var y3 = btn.up().down('combobox[name=y3axiscombo]');
                              var y3color = btn.up().down('combobox[name=y3axiscolorcombo]');
                              var y3fill = btn.up().down('checkboxfield[name=y3axisfillcheck]');
                              
                              if (y2.hidden) {
                                  y2device.show();
                                  y2.show();
                                  y2color.show();
                                  y2fill.show();
                              } else if (y3.hidden) {
                                  y3device.show();
                                  y3.show(); 
                                  y3color.show();
                                  y3fill.show();
                                  btn.setDisabled(true);
                              }
                          }
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Startvalue',
                            name: 'base1start',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120,
                            hidden: true
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Endvalue',
                            name: 'base1end',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120,
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'baseline1colorcombo',
                            fieldLabel: 'Baseline 1 Color',
                            labelWidth: 100,
                            inputWidth: 70,
                            store: me.comboColorStore,
                            displayField: 'name',
                            valueField: 'value',
                            value: me.comboColorStore.getAt(0),
                            hidden: true
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'baseline1fillcheck',
                            boxLabel: 'Fill',
                            hidden: true
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Startvalue',
                            name: 'base2start',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120,
                            hidden: true
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Endvalue',
                            name: 'base2end',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120,
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'baseline2colorcombo',
                            fieldLabel: 'Baseline 2 Color',
                            labelWidth: 100,
                            inputWidth: 70,
                            store: me.comboColorStore,
                            displayField: 'name',
                            valueField: 'value',
                            value: me.comboColorStore.getAt(1),
                            hidden: true
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'baseline2fillcheck',
                            boxLabel: 'Fill',
                            hidden: true
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Startvalue',
                            name: 'base3start',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120,
                            hidden: true
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Endvalue',
                            name: 'base3end',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120,
                            hidden: true
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'baseline3colorcombo',
                            fieldLabel: 'Baseline 3 Color',
                            labelWidth: 100,
                            inputWidth: 70,
                            store: me.comboColorStore,
                            displayField: 'name',
                            valueField: 'value',
                            value: me.comboColorStore.getAt(2),
                            hidden: true
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'baseline3fillcheck',
                            boxLabel: 'Fill',
                            hidden: true
                        },
                        {
                            xtype: 'button',
                            width: 110,
                            text: 'Add Baseline',
                            name: 'addbaselinebtn',
                            handler: function(btn) {
                                var b1start = btn.up().down('numberfield[name=base1start]');
                                var b1end = btn.up().down('numberfield[name=base1end]');
                                var b1color = btn.up().down('combobox[name=baseline1colorcombo]');
                                var b1fill = btn.up().down('checkboxfield[name=baseline1fillcheck]');
                                var b2start = btn.up().down('numberfield[name=base2start]');
                                var b2end = btn.up().down('numberfield[name=base2end]');
                                var b2color = btn.up().down('combobox[name=baseline2colorcombo]');
                                var b2fill = btn.up().down('checkboxfield[name=baseline2fillcheck]');
                                var b3start = btn.up().down('numberfield[name=base3start]');
                                var b3end = btn.up().down('numberfield[name=base3end]');
                                var b3color = btn.up().down('combobox[name=baseline3colorcombo]');
                                var b3fill = btn.up().down('checkboxfield[name=baseline3fillcheck]');
                                
                                if (b1start.hidden) {
                                    b1start.show();
                                    b1end.show();
                                    b1color.show();
                                    b1fill.show();
                                } else if (b2start.hidden) {
                                    b2start.show();
                                    b2end.show();
                                    b2color.show();
                                    b2fill.show();
                                } else if (b3start.hidden) {
                                    b3start.show();
                                    b3end.show();
                                    b3color.show();
                                    b3fill.show();
                                    btn.setDisabled(true);
                                }
                                    
                            }
                         }
                    ]
                },
                {
                    xtype: 'fieldset',
                    layout: 'column',
                    title: 'Select Timerange',
                    defaults: {
                        margin: '0 0 0 10'
                    },
                    items: [
                        {
                            xtype: 'radiofield',
                            fieldLabel: 'Timerange', 
                            labelWidth: 60,
                            name: 'rb', 
                            checked: true,
                            inputValue: 'timerange',
                            listeners: {
                                change: function(rb, newval, oldval) {
                                    if (newval === false) {
                                        rb.up().down('datefield[name=starttimepicker]').setDisabled(true);
                                        rb.up().down('datefield[name=endtimepicker]').setDisabled(true);
                                    } else {
                                        rb.up().down('datefield[name=starttimepicker]').setDisabled(false);
                                        rb.up().down('datefield[name=endtimepicker]').setDisabled(false);
                                    }
                                }
                            }
                        },
                        {
                          xtype: 'datefield',
                          name: 'starttimepicker',
                          format: 'Y-m-d H:i:s',
                          fieldLabel: 'Starttime',
                          labelWidth: 70
                        },
                        {
                          xtype: 'datefield',
                          name: 'endtimepicker',
                          format: 'Y-m-d H:i:s',
                          fieldLabel: 'Endtime',
                          labelWidth: 70
                        },
                        {
                            xtype: 'radiogroup',
                            name: 'dynamictime',
                            fieldLabel: 'or select a dynamic time',
                            labelWidth: 140,
                            allowBlank: true,
                            defaults: {
                                labelWidth: 42,
                                padding: "0 25px 0 0",
                                checked: false
                            },
                            items: [
                                { fieldLabel: 'yearly', name: 'rb', inputValue: 'year' },
                                { fieldLabel: 'monthly', name: 'rb', inputValue: 'month' },
                                { fieldLabel: 'weekly', name: 'rb', inputValue: 'week' },
                                { fieldLabel: 'daily', name: 'rb', inputValue: 'day' },
                                { fieldLabel: 'hourly', name: 'rb', inputValue: 'hour' }
                            ]
                        }
                    ]
                }, 
                {
                    xtype: 'fieldset',
                    layout: 'column',
                    defaults: {
                        margin: '0 0 0 10'
                    },
                    items: [
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
                            text: 'Reset Fields',
                            name: 'resetchartform'
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
                        },
                        {
                            xtype: 'radio',
                            width: 160,
                            fieldLabel: 'Generalization',
                            boxLabel: 'active',
                            name: 'generalization',
                            listeners: {
                                change: function(radio, state) {
                                    if (state) {
                                        radio.up().down('combobox[name=genfactor]').setDisabled(false);
                                    } else {
                                        radio.up().down('combobox[name=genfactor]').setDisabled(true);
                                    }
                                }
                            }
                        },
                        {
                            xtype: 'radio',
                            width: 80,
                            boxLabel: 'disabled',
                            checked: true,
                            name: 'generalization'
                        },
                        {
                            xtype: 'combo',
                            width: 120,
                            name: 'genfactor',
                            disabled: true,
                            fieldLabel: 'Factor',
                            labelWidth: 50,
                            store: Ext.create('Ext.data.Store', {
                                fields: ['displayval', 'val'],
                                data : [
                                        {"displayval": "10%", "val":"10"},
                                        {"displayval": "20%", "val":"20"},
                                        {"displayval": "30%", "val":"30"},
                                        {"displayval": "40%", "val":"40"},
                                        {"displayval": "50%", "val":"50"},
                                        {"displayval": "60%", "val":"60"},
                                        {"displayval": "70%", "val":"70"},
                                        {"displayval": "80%", "val":"80"},
                                        {"displayval": "90%", "val":"90"}
                                ]
                            }),
                            fields: ['displayval', 'val'],
                            displayField: 'displayval',
                            valueField: 'val',
                            value: '30'
                        }
                    ]
                }
            ]
        });
        
        var linechartview = Ext.create('Ext.panel.Panel', {
            title: 'Chart',
            autoScroll: true,
            collapsible: true,
            titleCollapse: true,
            items: [
                {
                  xtype: 'linechartview'
                }    
            ]
        });
            
        me.items = [
                chartSettingPanel,
                linechartview
        ];
        
        me.callParent(arguments);
        
        me.on("resize", me.layoutChart);
        
    },
    
    /**
     * helper function to relayout the chartview dependent on free space
     */
    layoutChart: function() {
        var lcp = Ext.ComponentQuery.query('linechartpanel')[0];
        var lcv = Ext.ComponentQuery.query('linechartview')[0];
        var cfp = Ext.ComponentQuery.query('form[name=chartformpanel]')[0];
        var chartheight = lcp.getHeight() - cfp.getHeight() - 85;
        var chartwidth = lcp.getWidth() - 25;
        lcv.setHeight(chartheight);
        lcv.setWidth(chartwidth);
    }
    
});
