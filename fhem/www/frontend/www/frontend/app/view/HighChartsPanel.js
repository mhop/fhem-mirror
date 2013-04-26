/**
 * A Panel containing device specific information
 */
Ext.define('FHEM.view.HighChartsPanel', {
    extend : 'Ext.panel.Panel',
    alias : 'widget.highchartspanel',

    requires: [
        'Chart.ux.Highcharts', 
        'Chart.ux.Highcharts.Serie',
        'Chart.ux.Highcharts.SplineSerie',
        'FHEM.store.DeviceStore',
        'FHEM.store.ReadingsStore',
        'Ext.form.Panel',
        'Ext.form.field.Radio',
        'Ext.form.field.Date',
        'Ext.form.RadioGroup'
    ],
   
   /**
    * generating getters and setters
    */
    config: {
       /**
        * 
        */
       axiscounter: 0
    },

    /**
     * 
     */
    title : 'Highcharts',
    
    /**
     * init function
     */
    initComponent : function() {
        
        var me = this;
        
        var chartSettingPanel = Ext.create('Ext.form.Panel', {
            title: 'HighChart Settings - Click me to edit',
            name: 'highchartformpanel',
            maxHeight: 230,
            autoScroll: true,
            collapsible: true,
            titleCollapse: true,
            items: [
                {
                    xtype: 'fieldset',
                    layout: 'column',
                    title: 'Select data',
                    name: 'highchartaxesfieldset',
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
                            name: 'highchartrb', 
                            checked: true,
                            inputValue: 'timerange',
                            listeners: {
                                change: function(rb, newval, oldval) {
                                    if (newval === false) {
                                        rb.up().down('datefield[name=highchartstarttimepicker]').setDisabled(true);
                                        rb.up().down('datefield[name=highchartendtimepicker]').setDisabled(true);
                                    } else {
                                        rb.up().down('datefield[name=highchartstarttimepicker]').setDisabled(false);
                                        rb.up().down('datefield[name=highchartendtimepicker]').setDisabled(false);
                                    }
                                }
                            }
                        },
                        {
                          xtype: 'datefield',
                          name: 'highchartstarttimepicker',
                          format: 'Y-m-d H:i:s',
                          fieldLabel: 'Starttime',
                          labelWidth: 70
                        },
                        {
                          xtype: 'datefield',
                          name: 'highchartendtimepicker',
                          format: 'Y-m-d H:i:s',
                          fieldLabel: 'Endtime',
                          labelWidth: 70
                        },
                        {
                            xtype: 'radiogroup',
                            name: 'highchartdynamictime',
                            fieldLabel: 'or select a dynamic time',
                            labelWidth: 140,
                            allowBlank: true,
                            defaults: {
                                labelWidth: 42,
                                padding: "0 25px 0 0",
                                checked: false
                            },
                            items: [
                                { fieldLabel: 'yearly', name: 'highchartrb', inputValue: 'year' },
                                { fieldLabel: 'monthly', name: 'highchartrb', inputValue: 'month' },
                                { fieldLabel: 'weekly', name: 'highchartrb', inputValue: 'week' },
                                { fieldLabel: 'daily', name: 'highchartrb', inputValue: 'day' },
                                { fieldLabel: 'hourly', name: 'highchartrb', inputValue: 'hour' }
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
                          name: 'highchartrequestchartdata',
                          icon: 'app/resources/icons/accept.png'
                        },
                        {
                          xtype: 'button',
                          width: 100,
                          text: 'Save Chart',
                          disabled: true,
                          name: 'highchartsavechartdata',
                          icon: 'app/resources/icons/database_save.png'
                        },
                        {
                            xtype: 'button',
                            width: 100,
                            text: 'Reset Fields',
                            name: 'highchartresetchartform',
                            icon: 'app/resources/icons/delete.png'
                        },
                        {
                            xtype: 'radio',
                            width: 160,
                            fieldLabel: 'Generalization',
                            disabled: true,
                            boxLabel: 'active',
                            name: 'highchartgeneralization',
                            listeners: {
                                change: function(radio, state) {
                                    if (state) {
                                        radio.up().down('combobox[name=highchartgenfactor]').setDisabled(false);
                                    } else {
                                        radio.up().down('combobox[name=highchartgenfactor]').setDisabled(true);
                                    }
                                }
                            }
                        },
                        {
                            xtype: 'radio',
                            width: 80,
                            boxLabel: 'disabled',
                            disabled: true,
                            checked: true,
                            name: 'highchartgeneralization'
                        },
                        {
                            xtype: 'combo',
                            width: 120,
                            name: 'highchartgenfactor',
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
    
        Ext.define('HighChartData', {
            extend : 'Ext.data.Model',
            fields : [ {
                name : 'TIMESTAMP',
                type : 'string'
            }, {
                name : 'VALUE',
                type : 'float'
            }]
        });

        var store = Ext.create('Ext.data.Store', {
            model : 'HighChartData',
            data: [{}]
        });
        
        me.callParent(arguments);

        //listener used to get correct rendering dimensions
        me.on("afterrender", function() {
            
            me.add(chartSettingPanel);
            
            //add the first yaxis line
            me.createNewYAxis();
            
            var chartpanel = Ext.create('Ext.panel.Panel', {
                title : 'Highchart',
                name: 'highchartpanel',
                collapsible: true,
                titleCollapse: true,
                layout : 'fit',
                items : [ {
                    xtype : 'highchart',
                    id : 'chart',
                    defaultSeriesType : 'spline',
                    series : [ {
                        type : 'spline',
                        dataIndex : 'VALUE',
                        name : 'VALUE',
                        visible : true
                    }],
                    store : store,
                    xField : 'TIMESTAMP',
                    chartConfig : {
                        chart : {
                            marginRight : 130,
                            marginBottom : 120,
                            zoomType : 'x',
                            animation : {
                                duration : 1500,
                                easing : 'swing'
                            }
                        },
                        title : {
                            text : 'Highcharts Testing',
                            x : -20
                        },
                        xAxis : [ {
                            title : {
                                text : 'Timestamp',
                                margin : 20
                            },
                            type: 'datetime',
                            tickInterval : 40 ,
                            labels : {
                                rotation : 315,
                                y : 45
//                                formatter : function() {
//                                    if (typeof this.value == 'string') {
//                                        var dt = Ext.Date.parse(
//                                                parseInt(this.value) / 1000, "U");
//                                        return Ext.Date.format(dt, "H:i:s");
//                                    } else {
//                                        return this.value;
//                                    }
//                                }

                            }
                        } ],
                        yAxis : {
                            title : {
                                text : 'Value'
                            },
                            plotLines : [ {
                                value : 0,
                                width : 1,
                                color : '#808080'
                            } ]
                        },
                        plotOptions : {
                            series : {
                                animation : {
                                    duration : 2000,
                                    easing : 'swing'
                                }
                            }
                        },
                        tooltip : {
                            formatter : function() {
                                return '<b>' + this.series.name + '</b><br/>'
                                        + this.x + ': ' + this.y;
                            }

                        },
                        legend : {
                            layout : 'vertical',
                            align : 'right',
                            verticalAlign : 'top',
                            x : -10,
                            y : 100,
                            borderWidth : 0
                        }
                    }
                } ]
            });

            me.add(chartpanel);
            
        });

        
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
                name: 'highchartsinglerowfieldset',
                layout: 'column',
                defaults: {
                    margin: '5 5 5 0'
                },
                items: 
                    [
                        {  
                          xtype: 'combobox', 
                          name: 'highchartdevicecombo',
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
                              autoLoad: false
                          }),
                          displayField: 'DEVICE',
                          valueField: 'DEVICE',
                          listeners: {
                              select: function(combo) {
                                  var device = combo.getValue(),
                                      readingscombo = combo.up().down('combobox[name=highchartyaxiscombo]'),
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
                            name: 'highchartyaxiscombo',
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
                            name: 'highchartyaxiscolorcombo',
                            fieldLabel: 'Y-Color',
                            disabled: true,
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
                            disabled: true,
                            name: 'highchartyaxisfillcheck',
                            boxLabel: 'Fill'
                        },
                        {  
                            xtype: 'checkboxfield', 
                            disabled: true,
                            name: 'highchartyaxisstepcheck',
                            boxLabel: 'Steps',
                            tooltip: 'Check, if the chart should be shown with steps instead of a linear Line'
                        },
                        {
                            xtype: 'radiogroup',
                            disabled: true,
                            name: 'highchartaxisside',
                            allowBlank: false,
                            border: true,
                            defaults: {
                                padding: "0 15px 0 0",
                                checked: false
                            },
                            items: [
                                { labelWidth: 50, fieldLabel: 'Left Axis', name: 'highchartrbc' + me.getAxiscounter(), inputValue: 'left', checked: true },
                                { labelWidth: 60, fieldLabel: 'Right Axis', name: 'highchartrbc' + me.getAxiscounter(), inputValue: 'right' }
                            ]
                        },
                        {  
                            xtype: 'combobox', 
                            name: 'highchartyaxisstatisticscombo',
                            fieldLabel: 'Statistics',
                            disabled: true,
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
                            disabled: true,
                            width: 110,
                            text: 'Add another Y-Axis',
                            name: 'highchartaddyaxisbtn',
                            handler: function(btn) {
                                me.createNewYAxis();
                            }
                        },
                        {
                            xtype: 'button',
                            disabled: true,
                            width: 90,
                            text: 'Add Baseline',
                            name: 'highchartaddbaselinebtn',
                            handler: function(btn) {
                                me.createNewBaseLineFields(btn);
                            }      
                        }
                ]
            };
        
        Ext.ComponentQuery.query('fieldset[name=highchartaxesfieldset]')[0].add(components);
        
    }

});
