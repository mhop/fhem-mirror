/**
 * The View for the Line Charts
 */
Ext.define('FHEM.view.LineChartView', {
    extend : 'Ext.chart.Chart',
    alias : 'widget.linechartview',
    xtype : 'chart',
    requires : [ 'FHEM.store.ChartStore' ],
    style : 'background:#fff',
    animate : true,
    shadow : true,
    theme : 'Category1',

    initComponent : function() {
        var me = this;
        me.store = Ext.create('FHEM.store.ChartStore');

        me.axes = [ {
            type : 'Numeric',
            name : 'yaxe',
            position : 'left',
            fields : [ 'VALUE' ],
            title : 'kW / h',
            grid : {
                odd : {
                    opacity : 1,
                    fill : '#ddd',
                    stroke : '#bbb',
                    'stroke-width' : 0.5
                }
            }
        }, {
            type : 'Time',
            name : 'xaxe',
            position : 'bottom',
            fields : [ 'TIMESTAMP' ],
            dateFormat : "Y-m-d H:i:s",
            minorTickSteps : 12,
            title : 'Time'
        } ];

        me.series = [ {
            type : 'line',
            axis : 'left',
            xField : 'TIMESTAMP',
            yField : 'VALUE',
            smooth: 2,
            fill: true,
            highlight: true,
            tips : {
                trackMouse : true,
                width : 140,
                height : 100,
                renderer : function(storeItem, item) {
                    this.setTitle(' Value: : ' + storeItem.get('VALUE') + 
                            '<br> Time: ' + storeItem.get('TIMESTAMP'));
                }
            }
        } ];
        
        me.callParent(arguments);
        
    }
    
});