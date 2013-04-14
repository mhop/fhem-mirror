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
        
        var chartSettingPanel = Ext.create('Ext.form.Panel', {
            title: 'Chart Settings - Click me to edit',
            name: 'chartformpanel',
            maxHeight: 230,
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
                    name: 'axesfieldset',
                    defaults: {
                        margin: '0 10 10 10'
                    },
                    items: [] //get filled in own function
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
        
        //creating the chart
        var chartstore = Ext.create('FHEM.store.ChartStore');
        var linechartview = Ext.create('Ext.panel.Panel', {
            title: 'Chart',
            autoScroll: true,
            collapsible: true,
            titleCollapse: true,
            items: [
                {
                    xtype: 'toolbar',
                    items: [
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Step back',
                            name: 'stepback',
                            icon: 'app/resources/icons/resultset_previous.png'
                        },
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Step forward',
                            name: 'stepforward',
                            icon: 'app/resources/icons/resultset_next.png'
                        },
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Reset Zoom',
                            name: 'resetzoom',
                            icon: 'app/resources/icons/delete.png',
                            scope: me,
                            handler: function(btn) {
                                var chart = me.down('chart');
                                chart.restoreZoom();
                                
                                chart.axes.get(0).minimum = me.getLastYmin();
                                chart.axes.get(0).maximum = me.getLastYmax();
                                chart.axes.get(1).minimum = me.getLastY2min();
                                chart.axes.get(1).maximum = me.getLastY2max();
                                chart.axes.get(2).minimum = me.getLastXmin();
                                chart.axes.get(2).maximum = me.getLastXmax();
                                
                                chart.redraw();
                                //helper to reshow the hidden items after zooming back out
                                if (me.artifactSeries && me.artifactSeries.length > 0) {
                                    Ext.each(me.artifactSeries, function(serie) {
                                        serie.showAll();
                                        Ext.each(serie.group.items, function(item) {
                                            if (item.type === "circle") {
                                                item.show();
                                                item.redraw();
                                            }
                                        });
                                    });
                                    me.artifactSeries = [];
                                }
                            }
                        }
                    ]
                },
                {
                    xtype: 'chart',
                    legend: {
                        position: 'right'
                    },
                    axes: [ 
                        {
                            type : 'Numeric',
                            name : 'yaxe',
                            position : 'left',
                            fields : [],
                            title : '',
                            grid : {
                                odd : {
                                    opacity : 1,
                                    fill : '#ddd',
                                    stroke : '#bbb',
                                    'stroke-width' : 0.5
                                }
                            }
                        }, 
                        {
                            type : 'Numeric',
                            name : 'yaxe2',
                            position : 'right',
                            fields : [],
                            title : ''
                        }, 
                        {
                            type : 'Time',
                            name : 'xaxe',
                            position : 'bottom',
                            fields : [ 'TIMESTAMP' ],
                            dateFormat : "Y-m-d H:i:s",
                            title : 'Time'
                        }
                    ],
                    animate: true,
                    store: chartstore,
                    enableMask: true,
                    mask: true,//'vertical',//true, //'horizontal',
                    listeners: {
                        mousedown: function(evt) {
                            // fix for firefox, not dragging images
                            evt.preventDefault();
                        },
                        select: {
                            fn: function(chart, zoomConfig, evt) {
                                
                                delete chart.axes.get(2).fromDate;
                                delete chart.axes.get(2).toDate;
                                me.setLastYmax(chart.axes.get(0).maximum);
                                me.setLastYmin(chart.axes.get(0).minimum);
                                me.setLastY2max(chart.axes.get(1).maximum);
                                me.setLastY2min(chart.axes.get(1).minimum);
                                me.setLastXmax(chart.axes.get(2).maximum);
                                me.setLastXmin(chart.axes.get(2).minimum);
                                
                                chart.setZoom(zoomConfig);
                                chart.mask.hide();
                                
                                //helper hiding series and items which are out of scope
                                    //var me = this;
                                Ext.each(chart.series.items, function(serie) {
                                    if (serie.items.length === 0) {
                                        me.artifactSeries.push(serie);
                                        Ext.each(serie.group.items, function(item) {
                                            item.hide();
                                            item.redraw();
                                        });
                                        serie.hideAll();
                                        
                                    }
                                });
                            }
                        }
                    }
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
        var lcv = Ext.ComponentQuery.query('chart')[0];
        var cfp = Ext.ComponentQuery.query('form[name=chartformpanel]')[0];
        var chartheight = lcp.getHeight() - cfp.getHeight() - 85;
        var chartwidth = lcp.getWidth() - 25;
        lcv.setHeight(chartheight);
        lcv.setWidth(chartwidth);
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
                layout: 'column',
                defaults: {
                    margin: '5 5 5 0'
                },
                items: 
                    [
                        {  
                          xtype: 'combobox', 
                          name: 'devicecombo',
                          fieldLabel: 'Select Device',
                          labelWidth: 90,
                          store: Ext.create('FHEM.store.DeviceStore', {
                              proxy: {
                                  type: 'ajax',
                                  method: 'POST',
                                  url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getdevices&XHR=1',
                                  reader: {
                                      type: 'json',
                                      root: 'data',
                                      totalProperty: 'totalCount'
                                  }
                              },
                              autoLoad: true
                          }),
                          displayField: 'DEVICE',
                          valueField: 'DEVICE',
                          listeners: {
                              select: function(combo) {
                                  var device = combo.getValue(),
                                      readingscombo = combo.up().down('combobox[name=yaxiscombo]'),
                                      readingsstore = readingscombo.getStore(),
                                      readingsproxy = readingsstore.getProxy();
                                  
                                  readingsproxy.url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + device + '+getreadings&XHR=1';
                                  readingsstore.load();
                                  readingscombo.setDisabled(false);
                              }
                          }
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'yaxiscombo',
                            fieldLabel: 'Select Y-Axis',
                            disabled: true,
                            labelWidth: 90,
                            inputWidth: 110,
                            store: Ext.create('FHEM.store.ReadingsStore', {
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
                        }
                ]
            };
        
        Ext.ComponentQuery.query('fieldset[name=axesfieldset]')[0].add(components);
        
    },
    
    /**
     * 
     */
    createNewBaseLineFields: function(btn) {
        var itemsToAdd = [
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
            }
        ];
        if (Ext.isDefined(btn)) {
            btn.up().add(itemsToAdd);
        } else {
            this.down('fieldset[name=singlerowfieldset]').add(itemsToAdd);
        }
        
    }
});
