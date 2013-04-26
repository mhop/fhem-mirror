/**
 * Serie class for BoxPlot series type
 *
 * See {@link Chart.ux.Highcharts.RangeSerie} class for more info
 * 
 * Here is an example of BoxPlot series config:
 *      series: [{
 *          type: 'boxplot',
 *          minDataIndex: 'min',
 *          lowQtrDataIndex: 'q1',
 *          medianDataIndex: 'med',
 *          highQtrDataIndex: 'q2',
 *          maxDataIndex: 'max',
 *          xField: 'date'
 *      }]     
 *
 */
Ext.define('Chart.ux.Highcharts.BoxPlotSerie', {
	  extend : 'Chart.ux.Highcharts.RangeSerie',
	  alternateClassName: [ 'highcharts.boxplot' ],
	  type : 'boxplot',

    /**
     * @cfg {String} lowQtrDataIndex
     * The low Quartile data field 
     */
    lowQtrDataIndex: null,

    /**
     * @cfg {String} highQtrDataIndex
     * The high Quartile data field 
     */
    highQtrDataIndex: null,

    /**
     * @cfg {String} medianDataIndex
     * The median data field
     */
    medianDataIndex: null,

    getData: function(record, index) {
        return [ 
            record.data[ this.minDataIndex ], 
            record.data[ this.lowQtrDataIndex ],
            record.data[ this.medianDataIndex ],
            record.data[ this.highQtrDataIndex ],
            record.data[ this.maxDataIndex ]
        ];
    }
});
