/**
 * The main application viewport, which displays the charts
 * @extends Ext.Viewport
 */
Ext.define('FHEM.view.ChartViewport', {
    extend: 'Ext.Viewport',
    name: 'chartviewport',
    layout: 'fit',
    requires: [
        'FHEM.view.LineChartPanel',
        'Ext.panel.Panel'
    ],
    /**
     * the given chart reference
     */
    chartid: null,

    initComponent: function() {
        var me = this;
        
        Ext.apply(me, {
            items: [
                {
                	xtype: 'linechartpanel',
                    name: 'linechartpanel',
                    hideSettingsPanel: true,
                    preventHeader: true
                }
            ]
        });
        me.callParent(arguments);
    }
});
