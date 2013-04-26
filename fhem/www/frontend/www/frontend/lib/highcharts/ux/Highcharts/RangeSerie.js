/**
 * Serie class for general range series type
 *
 * See {@link Chart.ux.Highcharts.Serie} class for more info
 *
 * This is the base class for dealing range series type. RangeSerie offers
 * sorted and unsorted ways of specifying range data. If it is desired to
 * plot range data that are natively in sorted manner, the series can be specified as
 *     series:[{
 *         minDataIndex: 'low',
 *         maxDataIndex: 'high',
 *         type: 'columnrange'
 *     }]
 * As for plotting range series data that are naturally without high and low ends, do
 *     series:[{
 *         dataIndex: [ 'marketOpen', 'marketClose' ],
 *         type: 'columnrange'
 *     }]
 */
Ext.define('Chart.ux.Highcharts.RangeSerie', {
	extend : 'Chart.ux.Highcharts.Serie',

  /***
   * @cfg {String}
   * data field mapping to store record which has minimum value
   */
	minDataIndex: null,
  /***
   * @cfg {String}
   * data field mapping to store record which has maximum value
   */
	maxDataIndex: null,
  /***
   * @private
   */
	needSorting: null,

  /***
   * @cfg {Array}
   * dataIndex in the range serie class is treated as an array of 
   * [ field1, field2 ] if it is defined
   */
  dataIndex: null,

  /***
   * @cfg yField
   * @hide
   */

	constructor: function(config) {
		if (Ext.isArray(config.dataIndex)) {
			this.field1 = config.dataIndex[0];
			this.field2 = config.dataIndex[1];
			this.needSorting = true;
		} else if (config.minDataIndex && config.maxDataIndex) {
			this.minDataIndex = config.minDataIndex;
			this.maxDataIndex = config.maxDataIndex;
			this.needSorting = false;
		}
		this.callParent(arguments);
	},

	getData: function(record, index) {
		if (this.needSorting === true) {
			return (record.data[this.field1] > record.data[this.field2]) ? [ record.data[this.field2], record.data[this.field1] ] : [ record.data[this.field1], record.data[this.field2] ];
		}

		if (record.data[this.minDataIndex] !== undefined && record.data[this.maxDataIndex] !== undefined) {
			return ([record.data[this.minDataIndex], record.data[this.maxDataIndex]]);
		}
	}
});
