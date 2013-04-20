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
        'FHEM.controller.ChartController',
        'FHEM.store.SavedChartsStore',
        'Ext.layout.container.Border',
        'Ext.form.field.Text',
        'Ext.layout.container.Accordion',
        'Ext.tree.Panel',
        'Ext.grid.Panel',
        'Ext.grid.Column',
        'Ext.grid.column.Action',
        'Ext.draw.Text'
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
                            width: '25%',
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
                            width: '25%',
                            items: [
                                {
                                    xtype: 'button',
                                    width: 80,
                                    margin: '30px 0 0 5px',
                                    text: 'Execute',
                                    name: 'executecommand',
                                    icon: 'app/resources/icons/arrow_left.png'
                                },
                                {
                                    xtype: 'button',
                                    width: 110,
                                    margin: '30px 0 0 5px',
                                    text: 'Save to Config',
                                    name: 'saveconfig',
                                    icon: 'app/resources/icons/database_save.png'
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
                    width: 270,
                    autoScroll: true,
                    resizable: true,
                    xtype: 'panel',
                    name: 'westaccordionpanel',
                    layout: 'accordion',
                    items: [
                        {
                            xtype: 'panel',
                            title: 'FHEM Devices',
                            name: 'devicesaccordion',
                            collapsed: false,
                            autoScroll: true,
                            items: [
                                {
                                    xtype: 'treepanel',
                                    name: 'maintreepanel',
                                    rootVisible: false,
                                    root: { 
                                        "text": "Root", 
                                        "expanded": 
                                        "true", 
                                        "children": []
                                    }
                                }
                            ]
                        },
                        {
                            xtype: 'panel',
                            title: 'LineChart',
                            name: 'linechartaccordionpanel',
                            autoScroll: true,
                            layout: 'fit',
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
                                                 icon: 'lib/ext-4.2.0.663/images/dd/drop-no.gif',
                                                 tooltip: 'Delete'
                                             }]
                                         }
                                    ],
                                    store: Ext.create('FHEM.store.SavedChartsStore', {}),
                                    name: 'savedchartsgrid'
                                    
                                }
                            ]
                        },
                        {
                            xtype: 'panel',
                            title: 'Database Tables',
                            name: 'tabledataaccordionpanel',
                            autoScroll: true
                        }
                    ]
                }, 
                {
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
                    xtype: 'panel',
                    region: 'center',
                    title: 'Welcome',
                    layout: 'hbox',
                    bodyStyle: 'padding:5px 5px 0',
                    items: [
                        {
                            xtype: 'image',
                            src: '../../fhem/images/default/fhemicon.png',
                            height: 132,
                            width: 120
                        },
                        {
                            xtype: 'text',
                            name: 'statustextfield',
                            padding: '50 0 0 20',
                            width: 400,
                            height: 130,
                            html: '<br>Welcome to the new FHEM Frontend.<br>For Informations, Problems and discussion, visit the <a href="http://forum.fhem.de/index.php?t=msg&th=10439&start=0&rid=0">FHEM Forums</a>'
                        }
                    ],
                    height: '100%'
                }
            ]
        });

        me.callParent(arguments);
    }
});
