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
                    html: '<p align="center"><img align="center" src="../../fhem/images/default/fhemicon.png" height="70px"</></p><h1 class="x-panel-header" align="center">Frontend</h1>',
                    height: 85
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
                                             dataIndex: 'VALUE', 
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
