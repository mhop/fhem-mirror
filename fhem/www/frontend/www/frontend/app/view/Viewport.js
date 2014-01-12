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
        'FHEM.view.StatusPanel',
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
                    height: 45,
                    layout: 'hbox',
                    items: [
                        {
                            xtype: 'container',
                            html: 'FHEM Webfrontend',
                            width: '25%',
                            padding: '15px 0 0 5px',
                            border: false
                        },
                        {
                            xtype: 'textfield',
                            name: 'commandfield',
                            width: '30%',
                            padding: '10px 0 0 0',
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
                                    margin: '10px 0 0 5px',
                                    text: 'Execute',
                                    name: 'executecommand',
                                    icon: 'app/resources/icons/arrow_left.png'
                                },
                                {
                                    xtype: 'button',
                                    width: 110,
                                    margin: '10px 0 0 5px',
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
                                    margin: '10px 5px 0 5px',
                                    text: 'Shutdown',
                                    name: 'shutdownfhem',
                                    tooltip: 'Shutdown FHEM',
                                    icon: 'app/resources/icons/stop.png'
                                },
                                {
                                    xtype: 'button',
                                    width: 70,
                                    margin: '10px 5px 0 5px',
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
                    width: 300,
                    autoScroll: true,
                    resizable: true,
                    xtype: 'panel',
                    name: 'westaccordionpanel',
                    layout: {
                        type: 'accordion'
                    },
                    items: [
                        {
                            title: 'FHEM Status',
                            name: 'fhemstatusaccordion',
                            expanded: true,
                            bodyPadding: '5 5 5 5',
                            html: 'See your current FHEM Status / Overview Information here.'
                        },
                        {
                            title: 'FHEM',
                            name: 'fhemaccordion',
                            collapsed: true,
                            bodyPadding: '5 5 5 5',
                            html: 'You can see and use the original FHEM Frontend here. <br> If you make changes to your config, it may be neccessary to reload this page to get the updated information.'
                        },
                        {
                            xtype: 'treepanel',
                            title: 'Charts / Devices / Rooms',
                            name: 'maintreepanel',
                            collapsed: false,
                            border: false,
                            rootVisible: false,
                            viewConfig: {
                                plugins: { ptype: 'treeviewdragdrop' }
                            },
                            root: { 
                                "text": "Root", 
                                "expanded": 
                                "true", 
                                "children": []
                            },
                            tbar: [
                                { 
                                    xtype: 'button', 
                                    name: 'unsortedtree',
                                    toggleGroup: 'treeorder',
                                    allowDepress: false,
                                    text: 'Unsorted'
                                },
                                { 
                                    xtype: 'button', 
                                    name: 'sortedtree',
                                    toggleGroup: 'treeorder',
                                    allowDepress: false,
                                    text: 'Order by Room',
                                    pressed: true
                                }
                            ],
                            listeners: {
                                'itemcontextmenu': function(scope, rec, item, index, e, eOpts) {
                                    e.preventDefault();
                                    
                                    if (rec.raw.data.TYPE &&
                                        (rec.raw.data.TYPE === "savedchart" || rec.raw.data.TYPE === "savedfilelogchart")) {
                                        var menu = Ext.ComponentQuery.query('menu[id=treecontextmenu]')[0];
                                        if (menu) {
                                            menu.destroy();
                                        }
                                        Ext.create('Ext.menu.Menu', {
                                            id: 'treecontextmenu',
                                            items: [
                                                {
                                                    text: 'Delete Chart',
                                                    name: 'deletechartfromcontext',
                                                    record: rec
                                                }, '-', {
                                                    text: 'Rename Chart',
                                                    name: 'renamechartfromcontext',
                                                    record: rec
                                                }
                                            ]
                                        }).showAt(e.xy);
                                    }
                                }
                            }
                        },
                        {
                            title: 'Database Tables',
                            name: 'tabledataaccordionpanel',
                            autoScroll: true,
                            bodyPadding: '5 5 5 5',
                            html: 'You can search your database here. <br> Specify your queries by selecting a specific device, reading and timerange.'
                        }
                    ]
                }, 
                {
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
                    xtype: 'statuspanel'
                }
//                {
//                    region: 'center',
//                    title: 'Welcome',
//                    layout: 'hbox',
//                    bodyStyle: 'padding:5px 5px 0',
//                    items: [
//                        {
//                            xtype: 'image',
//                            src: '../../fhem/images/default/fhemicon.png',
//                            height: 132,
//                            width: 120
//                        },
//                        {
//                            xtype: 'text',
//                            name: 'statustextfield',
//                            padding: '50 0 0 20',
//                            width: 400,
//                            height: 130,
//                            html: '<br>Welcome to the new FHEM Frontend.<br>For Informations, Problems and discussion, visit the <a href="http://forum.fhem.de/index.php?t=msg&th=10439&start=0&rid=0">FHEM Forums</a>'
//                        }
//                    ],
//                    height: '100%'
//                }
            ]
        });

        me.callParent(arguments);
    }
});
