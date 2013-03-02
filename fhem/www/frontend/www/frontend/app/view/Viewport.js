/**
 * The main application viewport, which displays the whole application
 * @extends Ext.Viewport
 */
Ext.define('FHEM.view.Viewport', {
    extend: 'Ext.Viewport',
    name: 'mainviewport',
    layout: 'border',
    requires: [
        'FHEM.view.LineChartPanel',
        'FHEM.view.TableDataGridPanel',
        'FHEM.controller.ChartController'
    ],

    initComponent: function() {
        var me = this;
        
        Ext.apply(me, {
            items: [
                {
                    region: 'north',
                    height: 85,
                    layout: 'hbox',
                    items: [
                        {
                            xtype: 'panel',
                            html: '<p><img src="../../fhem/images/default/fhemicon.png" height="70px"</></p><h1 class="x-panel-header">Frontend</h1>',
                            width: '30%',
                            border: false
                        },
                        {
                            xtype: 'textfield',
                            name: 'commandfield',
                            width: '30%',
                            padding: '30px 0 0 0',
                            fieldLabel: 'Send Commands',
                            border: false
                        },
                        {
                            xtype: 'panel',
                            border: false,
                            width: '20%',
                            items: [
                                {
                                    xtype: 'button',
                                    width: 60,
                                    margin: '30px 0 0 5px',
                                    text: 'Execute',
                                    name: 'executecommand'
                                },
                                {
                                    xtype: 'button',
                                    width: 90,
                                    margin: '30px 0 0 5px',
                                    text: 'Save to Config',
                                    name: 'saveconfig'
                                }
                            ]
                        },
                        {
                            xtype: 'panel',
                            border: false,
                            width: '20%',
                            items: [
                                {
                                    xtype: 'button',
                                    width: 75,
                                    margin: '30px 5px 0 5px',
                                    text: 'Shutdown',
                                    name: 'shutdownfhem',
                                    tooltip: 'Shutdown FHEM',
                                    icon: 'app/resources/icons/stop.png'
                                },
                                {
                                    xtype: 'button',
                                    width: 70,
                                    margin: '30px 5px 0 5px',
                                    text: 'Restart',
                                    name: 'restartfhem',
                                    tooltip: 'Restart FHEM',
                                    icon: 'app/resources/icons/database_refresh.png'
                                }
                            ]
                        }
                    ]
                }, {
                    region: 'west',
                    title: 'Navigation',
                    width: 200,
                    xtype: 'panel',
                    layout: 'accordion',
                    items: [
                        {
                            xtype: 'panel',
                            name: 'culpanel',
                            title: 'CUL'
                        },
                        {
                            xtype: 'panel',
                            title: 'LineChart',
                            name: 'linechartaccordionpanel',
                            layout: 'fit',
                            collapsed: false,
                            items: [
                                {
                                    xtype: 'grid',
                                    columns: [
                                         { 
                                             header: 'Saved Charts', 
                                             dataIndex: 'NAME', 
                                             width: '80%'
                                         },
                                         {
                                             xtype:'actioncolumn',
                                             name: 'savedchartsactioncolumn',
                                             width:'15%',
                                             items: [{
                                                 icon: 'lib/ext-4.1.1a/images/gray/dd/drop-no.gif',
                                                 tooltip: 'Delete'
                                             }]
                                         }
                                    ],
                                    store: Ext.create('FHEM.store.SavedChartsStore', {}),
                                    name: 'savedchartsgrid'
                                    
                                }
                            ]
                        },
//                        {
//                            xtype: 'panel',
//                            title: 'BarChart',
//                            name: 'barchartpanel',
//                            layout: 'fit',
//                            collapsed: false,
//                            items: [
//                                {
//                                    xtype: 'grid',
//                                    columns: [
//                                         { 
//                                             header: 'Saved Charts', 
//                                             dataIndex: 'VALUE', 
//                                             width: '80%'
//                                         },
//                                         {
//                                             xtype:'actioncolumn',
//                                             name: 'savedchartsactioncolumn',
//                                             width:'15%',
//                                             items: [{
//                                                 icon: 'lib/ext-4.1.1a/images/gray/dd/drop-no.gif',
//                                                 tooltip: 'Delete'
//                                             }]
//                                         }
//                                    ],
//                                    store: Ext.create('FHEM.store.SavedChartsStore', {}),
//                                    name: 'savedchartsgrid'
//                                    
//                                }
//                            ]
//                        },
                        {
                            xtype: 'panel',
                            title: 'Database Tables',
                            name: 'tabledataaccordionpanel'
                        },
                        {
                            xtype: 'panel',
                            title: 'Unsorted'
                        },
                        {
                            xtype: 'panel',
                            title: 'Everything'
                        },
                        {
                            xtype: 'panel',
                            title: 'Wiki'
                        },
                        {
                            xtype: 'panel',
                            title: 'Details'
                        },
                        {
                            xtype: 'panel',
                            title: 'Definition...'
                        },
                        {
                            xtype: 'panel',
                            title: 'Edit files'
                        },
                        {
                            xtype: 'panel',
                            title: 'Select style'
                        },
                        {
                            xtype: 'panel',
                            title: 'Event monitor'
                        }
                    ]
                }, {
                    xtype: 'panel',
                    region: 'south',
                    title: 'Status',
                    collapsible: true,
                    items: [{
                        xtype: 'text',
                        name: 'statustextfield',
                        text: 'Status...'
                    }],
                    split: true,
                    height: 50,
                    minHeight: 30
                }, 
                {
                    xtype: 'linechartpanel',
                    name: 'linechartpanel',
                    region: 'center',
                    layout: 'fit'
                },
                {
                    xtype: 'tabledatagridpanel',
                    name: 'tabledatagridpanel',
                    hidden: true,
                    region: 'center',
                    layout: 'fit'
                }
            ]
        });

        me.callParent(arguments);
    }
});
