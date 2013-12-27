/**
 * The Panel containing the Line Charts
 */
Ext.define('FHEM.view.LineChartPanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.linechartpanel',
    requires: [
        'FHEM.store.ChartStore',
        'FHEM.store.DeviceStore',
        'FHEM.store.ReadingsStore',
        'FHEM.view.ChartGridPanel',
        'Ext.form.Panel',
        'Ext.form.field.Radio',
        'Ext.form.field.Date',
        'Ext.form.RadioGroup',
        'Ext.chart.Chart',
        'Ext.chart.axis.Numeric',
        'Ext.chart.axis.Time',
        'Ext.chart.series.Line'
    ],
    
    /**
     * generating getters and setters
     */
    config: {
        /**
         * last max value of Y axis before zoom was applied
         */
        lastYmax: null,
        
        /**
         * last min value of Y axis before zoom was applied
         */
        lastYmin: null,
        
        /**
         * last max value of Y2 axis before zoom was applied
         */
        lastY2max: null,
        
        /**
         * last min value of Y2 axis before zoom was applied
         */
        lastY2min: null,
        
        /**
         * last max value of Y axis before zoom was applied
         */
        lastXmax: null,
        
        /**
         * last min value of Y axis before zoom was applied
         */
        lastXmin: null,
        
        /**
         * 
         */
        axiscounter: 0
    },
    
    artifactSeries: [],
    
    /**
     * the title
     */
    title: 'Line Chart',
    
    /**
     * init function
     */
    initComponent: function(cfg) {
        
        var me = this;
        
        me.devicestore = Ext.create('FHEM.store.DeviceStore', {
            proxy: {
                type: 'ajax',
                noCache: false,
                method: 'POST',
                url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getdevices&XHR=1',
                reader: {
                    type: 'json',
                    root: 'data',
                    totalProperty: 'totalCount'
                }
            },
            autoLoad: true
        });
        
        var chartSettingPanel = Ext.create('Ext.form.Panel', {
            title: 'Chart Settings - Click me to edit',
            name: 'chartformpanel',
            maxHeight: 345,
            autoScroll: true,
            collapsible: true,
            titleCollapse: true,
            animCollapse: false,
            items: [
                {
                    xtype: 'fieldset',
                    title: 'Select data',
                    name: 'axesfieldset',
                    defaults: {
                        margin: '0 10 10 10'
                    },
                    items: [] //get filled in own function
                },
                {
                    xtype: 'fieldset',
                    layout: 'vbox',
                    autoScroll: true,
                    title: 'Select Timerange',
                    defaults: {
                        margin: '0 0 0 10'
                    },
                    items: [
                        {
                            xtype: 'fieldset',
                            layout: 'hbox',
                            autoScroll: true,
                            border: false,
                            defaults: {
                                margin: '0 0 0 10'
                            },
                            items: [
                                {
                                    xtype: 'radiofield',
                                    fieldLabel: 'Timerange', 
                                    labelWidth: 60,
                                    name: 'rb', 
                                    checked: false,
                                    allowBlank: true,
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
                                  allowBlank: false,
                                  labelWidth: 70,
                                  value: Ext.Date.add(new Date(), Ext.Date.DAY, -1)
                                },
                                {
                                  xtype: 'datefield',
                                  name: 'endtimepicker',
                                  format: 'Y-m-d H:i:s',
                                  fieldLabel: 'Endtime',
                                  allowBlank: false,
                                  labelWidth: 70,
                                  value: new Date()
                                }
                            ]
                        },
                        {
                            xtype: 'fieldset',
                            layout: 'hbox',
                            autoScroll: true,
                            border: false,
                            defaults: {
                                margin: '0 0 0 10'
                            },
                            items: [
                                {
                                    xtype: 'radiogroup',
                                    name: 'dynamictime',
                                    fieldLabel: 'or select a dynamic time',
                                    labelWidth: 140,
                                    width: 900,
                                    allowBlank: true,
                                    defaults: {
                                        padding: "0px 0px 0px 18px"
                                    },
                                    items: [
                                        { fieldLabel: 'yearly', name: 'rb', inputValue: 'year', labelWidth: 38 },
                                        { fieldLabel: 'monthly', name: 'rb', inputValue: 'month', labelWidth: 44 },
                                        { fieldLabel: 'weekly', name: 'rb', inputValue: 'week', labelWidth: 40 },
                                        { fieldLabel: 'daily', name: 'rb', inputValue: 'day', checked: true, labelWidth: 31 },
                                        { fieldLabel: 'hourly', name: 'rb', inputValue: 'hour', labelWidth: 38 },
                                        { fieldLabel: 'last hour', name: 'rb', inputValue: 'lasthour', labelWidth: 50 },
                                        { fieldLabel: 'last 24h', name: 'rb', inputValue: 'last24h', labelWidth: 48 },
                                        { fieldLabel: 'last 7 days', name: 'rb', inputValue: 'last7days', labelWidth: 65 },
                                        { fieldLabel: 'last month', name: 'rb', inputValue: 'lastmonth', labelWidth: 65 }
                                    ]
                                }
                            ]
                        }
                    ]
                },
                {

                    xtype: 'fieldset',
                    layout: 'hbox',
                    autoScroll: true,
                    title: 'Axis Configuration',
                    defaults: {
                        margin: '0 0 0 10'
                    },
                    items: [
                        {
                            xtype: 'radiogroup',
                            name: 'leftaxisconfiguration',
                            fieldLabel: 'Left Axis Scalerange',
                            labelWidth: 120,
                            allowBlank: true,
                            width: 310,
                            defaults: {
                                labelWidth: 55,
                                padding: "0 25px 0 0",
                                checked: false
                            },
                            items: [
                                { fieldLabel: 'automatic', name: 'rb1', inputValue: 'automatic', checked: true },
                                { fieldLabel: 'manual', name: 'rb1', inputValue: 'manual' }
                            ],
                            listeners: {
                                change: function(rb1, newval, oldval) {
                                    if (newval.rb1 === "automatic") {
                                        rb1.up().down('numberfield[name=leftaxisminimum]').setDisabled(true);
                                        rb1.up().down('numberfield[name=leftaxismaximum]').setDisabled(true);
                                    } else {
                                        rb1.up().down('numberfield[name=leftaxisminimum]').setDisabled(false);
                                        rb1.up().down('numberfield[name=leftaxismaximum]').setDisabled(false);
                                    }
                                }
                            }
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Minimum',
                            name: 'leftaxisminimum',
                            allowBlank: false,
                            disabled: true,
                            labelWidth: 60,
                            width: 120
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Maximum',
                            name: 'leftaxismaximum',
                            allowBlank: false,
                            disabled: true,
                            labelWidth: 60,
                            width: 120
                        },
                        {
                            xtype: 'radiogroup',
                            name: 'rightaxisconfiguration',
                            fieldLabel: 'Right Axis Scalerange',
                            labelWidth: 130,
                            width: 310,
                            allowBlank: true,
                            defaults: {
                                labelWidth: 55,
                                padding: "0 25px 0 0",
                                checked: false
                            },
                            items: [
                                { fieldLabel: 'automatic', name: 'rb2', inputValue: 'automatic', checked: true },
                                { fieldLabel: 'manual', name: 'rb2', inputValue: 'manual' }
                            ],
                            listeners: {
                                change: function(rb2, newval, oldval) {
                                    if (newval.rb2 === "automatic") {
                                        rb2.up().down('numberfield[name=rightaxisminimum]').setDisabled(true);
                                        rb2.up().down('numberfield[name=rightaxismaximum]').setDisabled(true);
                                    } else {
                                        rb2.up().down('numberfield[name=rightaxisminimum]').setDisabled(false);
                                        rb2.up().down('numberfield[name=rightaxismaximum]').setDisabled(false);
                                    }
                                }
                            }
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Minimum',
                            name: 'rightaxisminimum',
                            allowBlank: false,
                            disabled: true,
                            labelWidth: 60,
                            width: 120
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Maximum',
                            name: 'rightaxismaximum',
                            allowBlank: false,
                            disabled: true,
                            labelWidth: 60,
                            width: 120
                        }
                    ]
                }, 
                {
                    xtype: 'fieldset',
                    layout: 'hbox',
                    autoScroll: true,
                    title: 'Axis Title Configuration',
                    defaults: {
                        margin: '0 0 5 10'
                    },
                    items: [
                        {
                            xtype: 'textfield',
                            fieldLabel: 'Left Axis Title',
                            name: 'leftaxistitle',
                            allowBlank: true,
                            labelWidth: 100,
                            width: 340
                        },
                        {
                            xtype: 'textfield',
                            fieldLabel: 'Right Axis Title',
                            name: 'rightaxistitle',
                            allowBlank: true,
                            labelWidth: 100,
                            width: 340
                        }
                    ]
                }, 
                {
                    xtype: 'fieldset',
                    layout: 'hbox',
                    autoScroll: true,
                    defaults: {
                        margin: '10 10 10 10'
                    },
                    items: [
                        {
                          xtype: 'button',
                          width: 100,
                          text: 'Show Chart',
                          name: 'requestchartdata',
                          icon: 'app/resources/icons/accept.png'
                        },
                        {
                          xtype: 'button',
                          width: 100,
                          text: 'Save Chart',
                          name: 'savechartdata',
                          icon: 'app/resources/icons/database_save.png'
                        },
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Reset Fields',
                            name: 'resetchartform',
                            icon: 'app/resources/icons/delete.png'
                        },
                        {
                            xtype: 'button',
                            width: 110,
                            text: 'Add another Y-Axis',
                            name: 'addyaxisbtn',
                            handler: function(btn) {
                                me.createNewYAxis();
                            }
                        },
                        {
                            xtype: 'button',
                            width: 90,
                            text: 'Add Baseline',
                            name: 'addbaselinebtn',
                            handler: function(btn) {
                                me.createNewBaseLineFields(btn);
                            }      
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
        
        //add the first yaxis line
        me.createNewYAxis();
            
        me.items = [
            chartSettingPanel
        ];
        me.callParent(arguments);
        
    },
    
    /**
     * create a new fieldset for a new chart y axis
     */
    createNewYAxis: function() {
        
        var me = this;
        
        me.setAxiscounter(me.getAxiscounter() + 1);
        
        var components = 
            {
                xtype: 'fieldset',
                name: 'singlerowfieldset',
                layout: 'hbox',
                autoScroll: true,
                defaults: {
                    margin: '5 5 5 0'
                },
                items: 
                    [
                       {
                           xtype: 'radiogroup',
                           name: 'datasourceradio',
                           rowCount: me.getAxiscounter(),
                           allowBlank: false,
                           defaults: {
                               labelWidth: 40,
                               padding: "0 5px 0 0"
                           },
                           items: [
                               {
                                   fieldLabel: 'DbLog',
                                   name: 'logtype' + me.getAxiscounter(),
                                   inputValue: 'dblog',
                                   checked: true,
                                   disabled: !FHEM.dblogname
                               },
                               {
                                   fieldLabel: 'FileLog',
                                   name: 'logtype' + me.getAxiscounter(),
                                   inputValue: 'filelog',
                                   checked: false,
                                   disabled: !FHEM.filelogs
                               }
                           ]
                        },
                        {  
                          xtype: 'combobox', 
                          name: 'devicecombo',
                          fieldLabel: 'Select Device',
                          labelWidth: 90,
                          store: me.devicestore,
                          triggerAction: 'all',
                          allowBlank: false,
                          displayField: 'DEVICE',
                          valueField: 'DEVICE',
                          listeners: {
                              select: function(combo) {
                                  
                                  var device = combo.getValue(),
                                      readingscombo = combo.up().down('combobox[name=yaxiscombo]'),
                                      readingsstore = readingscombo.getStore();
                                  
                                  if (readingsstore && readingsstore.queryMode !== 'local') {
                                      var readingsproxy = readingsstore.getProxy();
                                      readingsproxy.url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + device + '+getreadings&XHR=1';
                                      readingsstore.load();
                                  }
                                  readingscombo.setDisabled(false);
                              }
                          }
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'yaxiscombo',
                            fieldLabel: 'Select Y-Axis',
                            allowBlank: false,
                            disabled: true,
                            labelWidth: 90,
                            inputWidth: 110,
                            store: Ext.create('FHEM.store.ReadingsStore', {
                                queryMode: 'remote',
                                proxy: {
                                    type: 'ajax',
                                    method: 'POST',
                                    url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+-+getreadings&XHR=1',
                                    reader: {
                                        type: 'json',
                                        root: 'data',
                                        totalProperty: 'totalCount'
                                    }
                                },
                                autoLoad: false
                            }),
                            displayField: 'READING',
                            valueField: 'READING'
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'yaxiscolorcombo',
                            fieldLabel: 'Y-Color',
                            labelWidth: 50,
                            inputWidth: 70,
                            store: Ext.create('Ext.data.Store', {
                                fields: ['name', 'value'],
                                data : [
                                    {'name':'Blue','value':'#2F40FA'},
                                    {'name':'Green', 'value':'#46E01B'},
                                    {'name':'Orange','value':'#F0A800'},
                                    {'name':'Red','value':'#E0321B'},
                                    {'name':'Yellow','value':'#F5ED16'}
                                ]
                            }),
                            displayField: 'name',
                            valueField: 'value',
                            value: '#2F40FA'
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'yaxisfillcheck',
                            boxLabel: 'Fill'
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'yaxisstepcheck',
                            boxLabel: 'Steps',
                            tooltip: 'Check, if the chart should be shown with steps instead of a linear Line'
                        },
                        {
                            xtype: 'radiogroup',
                            name: 'axisside',
                            allowBlank: false,
                            border: true,
                            defaults: {
                                padding: "0 15px 0 0",
                                checked: false
                            },
                            items: [
                                { labelWidth: 50, fieldLabel: 'Left Axis', name: 'rbc' + me.getAxiscounter(), inputValue: 'left', checked: true },
                                { labelWidth: 60, fieldLabel: 'Right Axis', name: 'rbc' + me.getAxiscounter(), inputValue: 'right' }
                            ]
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'yaxisstatisticscombo',
                            fieldLabel: 'Statistics',
                            labelWidth: 70,
                            inputWidth: 120,
                            store: Ext.create('Ext.data.Store', {
                                fields: ['name', 'value'],
                                data : [
                                    {'name':'None','value':'none'},
                                    {'name':'Hour Sum', 'value':'hoursum'},
                                    {'name':'Hour Average', 'value':'houraverage'},
                                    {'name':'Hour Min','value':'hourmin'},
                                    {'name':'Hour Max','value':'hourmax'},
                                    {'name':'Hour Count','value':'hourcount'},
                                    {'name':'Day Sum', 'value':'daysum'},
                                    {'name':'Day Average', 'value':'dayaverage'},
                                    {'name':'Day Min','value':'daymin'},
                                    {'name':'Day Max','value':'daymax'},
                                    {'name':'Day Count','value':'daycount'},
                                    {'name':'Week Sum', 'value':'weeksum'},
                                    {'name':'Week Average', 'value':'weekaverage'},
                                    {'name':'Week Min','value':'weekmin'},
                                    {'name':'Week Max','value':'weekmax'},
                                    {'name':'Week Count','value':'weekcount'},
                                    {'name':'Month Sum', 'value':'monthsum'},
                                    {'name':'Month Average', 'value':'monthaverage'},
                                    {'name':'Month Min','value':'monthmin'},
                                    {'name':'Month Max','value':'monthmax'},
                                    {'name':'Month Count','value':'monthcount'},
                                    {'name':'Year Sum', 'value':'yearsum'},
                                    {'name':'Year Average', 'value':'yearaverage'},
                                    {'name':'Year Min','value':'yearmin'},
                                    {'name':'Year Max','value':'yearmax'},
                                    {'name':'Year Count','value':'yearcount'}
                                ]
                            }),
                            displayField: 'name',
                            valueField: 'value',
                            value: 'none'
                        },
                        {
                            xtype: 'button',
                            width: 60,
                            text: 'Remove',
                            name: 'removerowbtn',
                            handler: function(btn) {
                                me.removeRow(btn);
                            }      
                        }
                ]
            };
        
        Ext.ComponentQuery.query('fieldset[name=axesfieldset]')[0].add(components);
        
    },
    
    /**
     * 
     */
    createNewBaseLineFields: function(btn) {
        var me = this;
        
        var itemsToAdd = [
            {
                xtype: 'fieldset',
                name: 'baselineowfieldset',
                layout: 'hbox',
                autoScroll: true,
                defaults: {
                    margin: '5 5 5 0'
                },
                items: 
                    [
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Startvalue',
                            name: 'basestart',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120
                        },
                        {
                            xtype: 'numberfield',
                            fieldLabel: 'Endvalue',
                            name: 'baseend',
                            allowBlank: false,
                            labelWidth: 60,
                            width: 120
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'baselinecolorcombo',
                            fieldLabel: 'Baseline Color',
                            labelWidth: 100,
                            inputWidth: 70,
                            store: Ext.create('Ext.data.Store', {
                                fields: ['name', 'value'],
                                data : [
                                    {'name':'Blue','value':'#2F40FA'},
                                    {'name':'Green', 'value':'#46E01B'},
                                    {'name':'Orange','value':'#F0A800'},
                                    {'name':'Red','value':'#E0321B'},
                                    {'name':'Yellow','value':'#F5ED16'}
                                ]
                            }),
                            displayField: 'name',
                            valueField: 'value',
                            value: '#46E01B'
                        },
                        {  
                            xtype: 'checkboxfield', 
                            name: 'baselinefillcheck',
                            boxLabel: 'Fill'
                        },
                        {
                            xtype: 'button',
                            width: 60,
                            text: 'Remove',
                            name: 'removebaselinebtn',
                            handler: function(btn) {
                                me.removeRow(btn);
                            }      
                        }
                    ]
            }
        ];
        Ext.ComponentQuery.query('fieldset[name=axesfieldset]')[0].add(itemsToAdd);
        
    },
    
    /**
     * remove the current chart configuration row
     */
    removeRow: function(btn) {
        var me = this;
        if (btn.name === "removerowbtn") {
            me.setAxiscounter(me.getAxiscounter() - 1);
        }
        btn.up().destroy();
    }
});
