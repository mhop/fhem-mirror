/**
 * A Panel containing device specific information
 */
Ext.define('FHEM.view.ChartGridPanel', {
    extend: 'Ext.panel.Panel',
    alias : 'widget.chartgridpanel',
    
    requires: [
           'Ext.form.FieldSet',
           'Ext.layout.container.Column',
           'Ext.form.field.ComboBox'
    ],
    
    /**
     * 
     */
    title: 'Chart data',
    
    /**
     * 
     */
    jsonrecords: null,
    
    /**
     * 
     */
    collapsible: true,
    
    titleCollapse: true,
    
    animCollapse: false,
    
    /**
     * init function
     */
    initComponent: function() {
        
        var me = this;
        
        var chartdatastore = Ext.create('Ext.data.Store', {
            fields: [],
            data: [], 
            proxy: {
                type: 'memory',
                reader: {
                    type: 'json'
                }
            }
        });
        var chartdatagrid = {
            xtype: 'grid',
            height: 170,
            name: 'chartdata',
            columns: [
            ],
            store: chartdatastore
        };
        
        me.items = [chartdatagrid];
            
        me.callParent(arguments);
    }
    
});
