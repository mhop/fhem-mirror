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
                                        { fieldLabel: 'last hour', name: 'rb', inputValue: 'lasthour', labelWidth: 60 },
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
        var countForThisRow = me.getAxiscounter();
        
        var components = 
            {
                xtype: 'fieldset',
                name: 'singlerowfieldset' + countForThisRow,
                commonName: 'singlerowfieldset', 
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
                           rowCount: countForThisRow,
                           allowBlank: false,
                           defaults: {
                               labelWidth: 40,
                               padding: "0 5px 0 0"
                           },
                           items: [
                               {
                                   fieldLabel: 'DbLog',
                                   name: 'logtype' + countForThisRow,
                                   inputValue: 'dblog',
                                   checked: true,
                                   disabled: !FHEM.dblogname
                               },
                               {
                                   fieldLabel: 'FileLog',
                                   name: 'logtype' + countForThisRow,
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
                            xtype: 'button',
                            text: 'Styling...',
                            handler: function() {
                                Ext.create('Ext.window.Window', {
                                    width: 470,
                                    height: 600,
                                    name: 'stylerwindow',
                                    title: 'Set the Style for this Axis',
                                    modal: true,
                                    constrainHeader: true,
                                    items: [
                                        {
                                            xtype: 'panel',
                                            title: 'Preview',
                                            height: 200,
                                            items: [
                                                me.createPreviewChart(countForThisRow)
                                            ]
                                        },
                                        {
                                            xtype: 'panel',
                                            title: 'Configuration',
                                            autoScroll: true,
                                            height: 335,
                                            defaults: {
                                                padding: '5px 5px 5px 5px'
                                            },
                                            items: [
                                                {
                                                    xtype: 'fieldset',
                                                    layout: 'vbox',
                                                    title: 'Line Settings',
                                                    items: [
                                                        {
                                                            xtype: 'numberfield',
                                                            name: 'linestrokewidth',
                                                            fieldLabel: 'Line Stroke Width',
                                                            editable: false,
                                                            labelWidth: 150,
                                                            value: me.getStyleConfig(countForThisRow).linestrokewidth,
                                                            maxValue: 10,
                                                            minValue: 1,
                                                            listeners: {
                                                                change: function(field, val) {
                                                                    me.createPreviewChart(countForThisRow);
                                                                }
                                                            }
                                                        },
                                                        {
                                                            xtype: 'container',
                                                            name: 'linecolorcontainer',
                                                            layout: 'hbox',
                                                            items: [
                                                                {
                                                                    xtype: 'displayfield',
                                                                    value: 'Select your Linecolor: ',
                                                                    width: 155
                                                                },
                                                                {
                                                                    xtype: 'colorpicker',
                                                                    listeners: {
                                                                        select: function(picker, selColor) {
                                                                            picker.up().down('textfield').setValue(selColor);
                                                                            me.createPreviewChart(countForThisRow);
                                                                        }
                                                                    }
                                                                },
                                                                {
                                                                    xtype: 'textfield',
                                                                    padding: '0 0 0 5px',
                                                                    labelWidth: 50,
                                                                    width: 120,
                                                                    name: 'linecolorhexcode',
                                                                    fieldLabel: 'Hexcode',
                                                                    value: me.getStyleConfig(countForThisRow).linecolorhexcode.indexOf("#") >= 0 ? me.getStyleConfig(countForThisRow).linecolorhexcode.split("#")[1] : me.getStyleConfig(countForThisRow).linecolorhexcode,
                                                                    listeners: {
                                                                        change: function(field, val) {
                                                                            me.createPreviewChart(countForThisRow);
                                                                        }
                                                                    }        
                                                                }
                                                            ]
                                                        }
                                                    ]
                                                },
                                                {
                                                    xtype: 'fieldset',
                                                    layout: 'vbox',
                                                    title: 'Fill Color',
                                                    items: [
                                                        {  
                                                            xtype: 'checkboxfield', 
                                                            name: 'yaxisfillcheck',
                                                            fieldLabel: 'Use a Fill below the line?',
                                                            labelWidth: 150,
                                                            checked: (me.getStyleConfig(countForThisRow).yaxisfillcheck === "false" || !me.getStyleConfig(countForThisRow).yaxisfillcheck) ? false : true,
                                                            listeners: {
                                                                change: function(box, state) {
                                                                    if (state === true) {
                                                                        box.up().down('numberfield').show();
                                                                        box.up().down('container[name=fillcolorcontainer]').show();
                                                                        me.createPreviewChart(countForThisRow);
                                                                    } else {
                                                                        box.up().down('numberfield').hide();
                                                                        box.up().down('container[name=fillcolorcontainer]').hide();
                                                                        me.createPreviewChart(countForThisRow);
                                                                    }
                                                                }
                                                            }
                                                        },
                                                        {
                                                            xtype: 'numberfield',
                                                            name: 'fillopacity',
                                                            fieldLabel: 'Opacity for Fill',
                                                            editable: false,
                                                            hidden: (me.getStyleConfig(countForThisRow).yaxisfillcheck === "false" || me.getStyleConfig(countForThisRow).yaxisfillcheck === false) ? true : false,
                                                            labelWidth: 150,
                                                            value: me.getStyleConfig(countForThisRow).fillopacity,
                                                            maxValue: 1.0,
                                                            minValue: 0.1,
                                                            step: 0.1,
                                                            listeners: {
                                                                change: function(field, val) {
                                                                    me.createPreviewChart(countForThisRow);
                                                                }
                                                            }
                                                        },
                                                        {
                                                            xtype: 'container',
                                                            name: 'fillcolorcontainer',
                                                            layout: 'hbox',
                                                            hidden: (me.getStyleConfig(countForThisRow).yaxisfillcheck === "false" || me.getStyleConfig(countForThisRow).yaxisfillcheck === false) ? true : false,
                                                            items: [
                                                                {
                                                                    xtype: 'displayfield',
                                                                    value: 'Select your Fillcolor: ',
                                                                    width: 155
                                                                },
                                                                {
                                                                    xtype: 'colorpicker',
                                                                    listeners: {
                                                                        select: function(picker, selColor) {
                                                                            picker.up().down('textfield').setValue(selColor);
                                                                            me.createPreviewChart(countForThisRow);
                                                                        }
                                                                    }
                                                                },
                                                                {
                                                                    xtype: 'textfield',
                                                                    padding: '0 0 0 5px',
                                                                    labelWidth: 50,
                                                                    width: 120,
                                                                    name: 'fillcolorhexcode',
                                                                    fieldLabel: 'Hexcode',
                                                                    value: me.getStyleConfig(countForThisRow).fillcolorhexcode.indexOf("#") >= 0 ? me.getStyleConfig(countForThisRow).fillcolorhexcode.split("#")[1] : me.getStyleConfig(countForThisRow).fillcolorhexcode,
                                                                    listeners: {
                                                                        change: function(field, val) {
                                                                            me.createPreviewChart(countForThisRow);
                                                                        }
                                                                    }
                                                                }
                                                            ]
                                                        }
                                                    ]
                                                },
                                                {
                                                    xtype: 'fieldset',
                                                    layout: 'vbox',
                                                    title: 'Point Settings',
                                                    items: [
                                                        {
                                                            xtype: 'displayfield',
                                                            value: 'Configure how the Points representing Readings should be displayed.<br>'
                                                        },
                                                        {  
                                                            xtype: 'checkboxfield', 
                                                            name: 'yaxisshowpoints',
                                                            checked: (me.getStyleConfig(countForThisRow).yaxisshowpoints === "false" || me.getStyleConfig(countForThisRow).yaxisshowpoints === false) ? false : true,
                                                            fieldLabel: 'Show Points? (if not, you will only see the line)',
                                                            labelWidth: 150,
                                                            listeners: {
                                                                change: function(box, state) {
                                                                    if (state === true) {
                                                                        box.up().down('container[name=pointfillcolorcontainer]').show();
                                                                        box.up().down('combo').show();
                                                                        box.up().down('numberfield[name=pointradius]').show();
                                                                        me.createPreviewChart(countForThisRow);
                                                                    } else {
                                                                        box.up().down('container[name=pointfillcolorcontainer]').hide();
                                                                        box.up().down('combo').hide();
                                                                        box.up().down('numberfield[name=pointradius]').hide();
                                                                        me.createPreviewChart(countForThisRow);
                                                                    }
                                                                }
                                                            }
                                                        },
                                                        {
                                                            xtype: 'combo',
                                                            fieldLabel: 'Choose the Shape',
                                                            name: 'shapecombo',
                                                            labelWidth: 150,
                                                            editable: false,
                                                            allowBlank: false,
                                                            store: ['circle', 'line', 'triangle', 'diamond', 'cross', 'plus', 'arrow'],
                                                            queryMode: 'local',
                                                            value: me.getStyleConfig(countForThisRow).pointshape,
                                                            listeners: {
                                                                change: function(combo, val) {
                                                                    me.createPreviewChart(countForThisRow);
                                                                }
                                                            }
                                                        },
                                                        {
                                                            xtype: 'numberfield',
                                                            name: 'pointradius',
                                                            fieldLabel: 'Point Radius',
                                                            editable: false,
                                                            labelWidth: 150,
                                                            value: me.getStyleConfig(countForThisRow).pointradius,
                                                            maxValue: 10,
                                                            minValue: 1,
                                                            listeners: {
                                                                change: function(field, val) {
                                                                    me.createPreviewChart(countForThisRow);
                                                                }
                                                            }
                                                        },
                                                        {
                                                            xtype: 'container',
                                                            name: 'pointfillcolorcontainer',
                                                            layout: 'hbox',
                                                            items: [
                                                                {
                                                                    xtype: 'displayfield',
                                                                    value: 'Select your Point-Fillcolor: ',
                                                                    width: 155
                                                                },
                                                                {
                                                                    xtype: 'colorpicker',
                                                                    listeners: {
                                                                        select: function(picker, selColor) {
                                                                            picker.up().down('textfield').setValue(selColor);
                                                                            me.createPreviewChart(countForThisRow);
                                                                        }
                                                                    }
                                                                },
                                                                {
                                                                    xtype: 'textfield',
                                                                    padding: '0 0 0 5px',
                                                                    labelWidth: 50,
                                                                    width: 120,
                                                                    name: 'pointcolorhexcode',
                                                                    fieldLabel: 'Hexcode',
                                                                    value: me.getStyleConfig(countForThisRow).pointcolorhexcode.indexOf("#") >= 0 ? me.getStyleConfig(countForThisRow).pointcolorhexcode.split("#")[1] : me.getStyleConfig(countForThisRow).pointcolorhexcode,
                                                                    listeners: {
                                                                        change: function(field, val) {
                                                                            me.createPreviewChart(countForThisRow);
                                                                        }
                                                                    }
                                                                }
                                                            ]
                                                        }
                                                    ]
                                                },
                                                {
                                                    xtype: 'fieldset',
                                                    layout: 'vbox',
                                                    title: 'Advanced Settings',
                                                    items: [
                                                        {  
                                                            xtype: 'checkboxfield', 
                                                            name: 'yaxisstepcheck',
                                                            fieldLabel: 'Show Steps for this Axis?',
                                                            checked: (me.getStyleConfig(countForThisRow).yaxisstepcheck === "false" || me.getStyleConfig(countForThisRow).yaxisstepcheck === false) ? false : true,
                                                            labelWidth: 200,
                                                            listeners: {
                                                                change: function(box, checked) {
                                                                    if (checked) {
                                                                        box.up().down('numberfield').setDisabled(true);
                                                                    } else {
                                                                        box.up().down('numberfield').setDisabled(false);
                                                                    }
                                                                }
                                                            }
                                                        },
                                                        {  
                                                            xtype: 'numberfield', 
                                                            name: 'yaxissmoothing',
                                                            fieldLabel: 'Smoothing for this Axis (0 for off)',
                                                            editable: false,
                                                            value: me.getStyleConfig(countForThisRow).yaxissmoothing,
                                                            maxValue: 10,
                                                            minValue: 0,
                                                            labelWidth: 200,
                                                            listeners: {
                                                                change: function(field, val) {
                                                                    me.createPreviewChart(countForThisRow);
                                                                }
                                                            }
                                                        },
                                                        {  
                                                            xtype: 'checkboxfield', 
                                                            name: 'yaxislegendcheck',
                                                            fieldLabel: 'Show this Axis in Legend?',
                                                            labelWidth: 200,
                                                            checked: (me.getStyleConfig(countForThisRow).yaxislegendcheck === "false" || me.getStyleConfig(countForThisRow).yaxislegendcheck === false) ? false : true
                                                        }
                                                    ]
                                                }
                                            ]
                                        }
                                    ],
                                    buttons: [
                                        {
                                            text: "Cancel",
                                            handler: function(btn) {
                                                btn.up('window').destroy();
                                            }
                                        },
                                        {
                                            text: "Save settings",
                                            handler: function(btn) {
                                                var win = btn.up('window'),
                                                    styleConfig = me.getStyleConfig(countForThisRow);
                                                
                                                // set all values
                                                styleConfig.linestrokewidth = win.down('numberfield[name=linestrokewidth]').getValue();
                                                styleConfig.linecolorhexcode = win.down('textfield[name=linecolorhexcode]').getValue();
                                                styleConfig.yaxisfillcheck = win.down('checkboxfield[name=yaxisfillcheck]').getValue();
                                                styleConfig.fillopacity = win.down('numberfield[name=fillopacity]').getValue();
                                                styleConfig.fillcolorhexcode = win.down('textfield[name=fillcolorhexcode]').getValue();
                                                styleConfig.yaxisshowpoints = win.down('checkboxfield[name=yaxisshowpoints]').getValue();
                                                styleConfig.pointshape = win.down('combo[name=shapecombo]').getValue();
                                                styleConfig.pointradius = win.down('numberfield[name=pointradius]').getValue();
                                                styleConfig.pointcolorhexcode = win.down('textfield[name=pointcolorhexcode]').getValue();
                                                styleConfig.yaxisstepcheck = win.down('checkboxfield[name=yaxisstepcheck]').getValue();
                                                styleConfig.yaxissmoothing = win.down('numberfield[name=yaxissmoothing]').getValue();
                                                styleConfig.yaxislegendcheck = win.down('checkboxfield[name=yaxislegendcheck]').getValue();
                                                
                                                btn.up('window').destroy();
                                            }
                                        }
                                    ]
                                }).show();
                            }
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
                                { labelWidth: 60, fieldLabel: 'Left Axis', name: 'rbc' + me.getAxiscounter(), inputValue: 'left', checked: true },
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
                ],
                styleConfig: {
                    linestrokewidth: 2,
                    linecolorhexcode: 'FF0000',
                    yaxisfillcheck: false,
                    fillopacity: 0.5,
                    fillcolorhexcode: 'FF0000',
                    yaxisshowpoints: true,
                    pointshape: 'circle',
                    pointradius: 2,
                    pointcolorhexcode: 'FF0000',
                    yaxisstepcheck: false,
                    yaxissmoothing: 3,
                    yaxislegendcheck: true
                }
            };
        
        Ext.ComponentQuery.query('fieldset[name=axesfieldset]')[0].add(components);
        
    },
    
    /**
     * 
     */
    createPreviewChart: function(countForThisRow) {
        var me = this,
            win = Ext.ComponentQuery.query('window[name=stylerwindow]')[0],
            styleConfig = me.getStyleConfig(countForThisRow),
            chart = Ext.create('Ext.chart.Chart', {
                name: 'previewchart',
                store: Ext.create('Ext.data.Store', {
                    model: Ext.define('WeatherPoint', {
                        extend: 'Ext.data.Model',
                        fields: ['temperature', 'date']
                    }),
                    data: [
                        { temperature: 2, date: new Date(2011, 1, 1, 3) },
                        { temperature: 20, date: new Date(2011, 1, 1, 4) },
                        { temperature: 6, date: new Date(2011, 1, 1, 5) },
                        { temperature: 4, date: new Date(2011, 1, 1, 6) },
                        { temperature: 30, date: new Date(2011, 1, 1, 7) },
                        { temperature: 58, date: new Date(2011, 1, 1, 8) },
                        { temperature: 63, date: new Date(2011, 1, 1, 9) },
                        { temperature: 73, date: new Date(2011, 1, 1, 10) },
                        { temperature: 78, date: new Date(2011, 1, 1, 11) },
                        { temperature: 81, date: new Date(2011, 1, 1, 12) },
                        { temperature: 64, date: new Date(2011, 1, 1, 13) },
                        { temperature: 53, date: new Date(2011, 1, 1, 14) },
                        { temperature: 21, date: new Date(2011, 1, 1, 15) },
                        { temperature: 4, date: new Date(2011, 1, 1, 16) },
                        { temperature: 6, date: new Date(2011, 1, 1, 17) },
                        { temperature: 35, date: new Date(2011, 1, 1, 18) },
                        { temperature: 8, date: new Date(2011, 1, 1, 19) },
                        { temperature: 24, date: new Date(2011, 1, 1, 20) },
                        { temperature: 22, date: new Date(2011, 1, 1, 21) },
                        { temperature: 18, date: new Date(2011, 1, 1, 22) }
                    ]
                }),
                axes: [
                    {
                        type: 'Numeric',
                        position: 'left',
                        fields: ['temperature'],
                        minimum: 0,
                        maximum: 100
                    },
                    {
                        type: 'Time',
                        position: 'bottom',
                        fields: ['date'],
                        dateFormat: 'ga'
                    }
                ],
                series: [
                    {
                        type: 'line',
                        xField: 'date',
                        yField: 'temperature',
                        smooth: win ? win.down('numberfield[name=yaxissmoothing]').getValue() : styleConfig.yaxissmoothing,
                        fill: win ? win.down('checkboxfield[name=yaxisfillcheck]').getValue() : ((styleConfig.yaxisfillcheck === "false" || !styleConfig.yaxisfillcheck) ? false: true),
                        style: {
                            fill: win ? '#' + win.down('textfield[name=fillcolorhexcode]').getValue() : '#' + styleConfig.fillcolorhexcode,
                            opacity: win ? win.down('numberfield[name=fillopacity]').getValue() : styleConfig.fillopacity,
                            stroke: win ? '#' + win.down('textfield[name=linecolorhexcode]').getValue() : '#' + styleConfig.linecolorhexcode,
                            'stroke-width': win ? win.down('numberfield[name=linestrokewidth]').getValue() : styleConfig.linestrokewidth
                        },
                        markerConfig: {
                            type: win ? win.down('combo[name=shapecombo]').getValue() : styleConfig.pointshape,
                            radius: win ? win.down('numberfield[name=pointradius]').getValue() : styleConfig.pointradius,
                            stroke: win ? '#' + win.down('textfield[name=pointcolorhexcode]').getValue() : '#' + styleConfig.pointcolorhexcode,
                            fill: win ? '#' + win.down('textfield[name=pointcolorhexcode]').getValue() : '#' + styleConfig.pointcolorhexcode
                        },
                        showMarkers: win ? win.down('checkboxfield[name=yaxisshowpoints]').getValue() : ((styleConfig.yaxisshowpoints === "false" || !styleConfig.yaxisshowpoints) ? false: true)
                    }
                ],
                width: 455,
                height: 170
        });
        
        // find exisitng chart
        var existingChart = Ext.ComponentQuery.query('chart[name=previewchart]')[0];
        if (existingChart && existingChart !== chart) {
            var parent = existingChart.up();
            existingChart.destroy();
            parent.add(chart);
        } else {
            return chart;
        }
    },
    
    /**
     * 
     */
    getStyleConfig: function(axiscount) {
        var fs = Ext.ComponentQuery.query('fieldset[name=singlerowfieldset' + axiscount + ']')[0];
        return fs.styleConfig;
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
