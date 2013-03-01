/**
 * The View for the Line Charts
 */
Ext.define('FHEM.view.LineChartView', {
    extend : 'Ext.chart.Chart',
    alias : 'widget.linechartview',
    xtype : 'chart',
    requires : [ 'FHEM.store.ChartStore' ],
    animate : true,
    legend: {
        position: 'right'
    },

    initComponent : function() {
        var me = this;
        me.store = Ext.create('FHEM.store.ChartStore');

        me.axes = [ 
            {
                type : 'Numeric',
                name : 'yaxe',
                position : 'left',
                fields : [ 'VALUE', 'VALUE2', 'VALUE3', 'VALUEBASE1', 'VALUEBASE2', 'VALUEBASE3' ],
                title : 'VALUE',
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
                type : 'Time',
                name : 'xaxe',
                position : 'bottom',
                fields : [ 'TIMESTAMP' ],
                dateFormat : "Y-m-d H:i:s",
                minorTickSteps : 12,
                title : 'Time'
            } ];

        me.series = null;
        
        me.callParent(arguments);
        
    }
    
});