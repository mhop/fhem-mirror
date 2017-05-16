/**
 * The GridPanel containing a table with rawdata from Database
 */
Ext.define('FHEM.view.TableDataGridPanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.tabledatagridpanel',
    //xtype : 'gridpanel',
    requires: [
        'FHEM.store.TableDataStore'
    ],
    
    title: 'Table Data',
    
    /**
     * 
     */
    initComponent: function() {
        
        var me = this;
        
        var tablestore = Ext.create('FHEM.store.TableDataStore');
        
        me.items = [
            {
                xtype: 'panel',
                items: [
                    {
                        xtype: 'fieldset',
                        title: 'Configure Database Query',
                        items: [
                            {
                                xtype: 'displayfield',
                                value: 'The configuration of the Databasequery will follow here...'
                            }
                        ]
                    },
                    {
                        xtype: 'gridpanel',
                        height: 400,
                        collapsible: true,
                        store: tablestore,
                        width: '100%',
                        loadMask: true,
                        selModel: {
                            pruneRemoved: false
                        },
                        multiSelect: true,
                        viewConfig: {
                            trackOver: false
                        },
                        verticalScroller:{
                            //trailingBufferZone: 20,  // Keep 200 records buffered in memory behind scroll
                            //leadingBufferZone: 50   // Keep 5000 records buffered in memory ahead of scroll
                        },
                        columns: [
                              { text: 'TIMESTAMP',  dataIndex: 'TIMESTAMP' },
                              { text: 'DEVICE', dataIndex: 'DEVICE' },
                              { text: 'TYPE',  dataIndex: 'TYPE' },
                              { text: 'EVENT',  dataIndex: 'EVENT' },
                              { text: 'READING', dataIndex: 'READING' },
                              { text: 'VALUE', dataIndex: 'VALUE' },
                              { text: 'UNIT', dataIndex: 'UNIT' }
                        ]
                    } 
                ]
            }
        ];
        
        me.callParent(arguments);
        
    }
    
});
