/**
 * Serie class for bubble type series
 *
 * The bubble series support two types of data input
 *
 * # Single Bubble Series
 * For single bubble series, the series can be specified as 
 *     series: [{
 *         xField: 'x',
 *         yField: 'y',
 *         radiusField: 'r'
 *         type: 'bubble'
 *     }]
 *
 * # Single / Multiple Bubble Series
 * For single/multiple bubble series, the series should be specified as 
 * the Irregular data example, i.e.
 *     series: [{
 *         type: 'bubble',
 *         dataIndex: 'series1'
 *     }, {
 *         type: 'bubble',
 *         dataIndex: 'series2'
 *     }]
 *
 * The Json data returning from the server side should looking like the following:
 *     'root': [{
 *         'series1': [ [ 97,36,79],[94,74,60],[68,76,58], .... ] ],
 *         'series2': [ [25,10,87],[2,75,59],[11,54,8],[86,55,93] .... ] ],
 *      }]
 * 
 * See {@link Chart.ux.Highcharts.Serie} class for more info
 */
Ext.define('Chart.ux.Highcharts.BubbleSerie', {
	  extend : 'Chart.ux.Highcharts.Serie',
	  alternateClassName: [ 'highcharts.bubble' ],
	  type : 'bubble',
    
    /**
     * @cfg {String} radiusField
     * The field stores the radius value of a bubble data point
     */
    radiusField : null,

    /***
     * @cfg {Array} dataIndex 
     * dataIndex should be used for specifying mutliple bubble series, i.e.
     * the server side returns an array of truples which has values of [ x, y, r ] 
     */
    dataIndex: null,

    /***
     * @private
     * each data point in the series is represented in it's own x and y values
     */
    arr_getDataPair: function(record, index) {
        return [ 
            record.data[ this.xField ], 
            record.data[ this.yField ],
            record.data[ this.radiusField ]
        ];
    }


});
