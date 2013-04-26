/**
 * Serie class for gauge series type
 *
 * See {@link Chart.ux.Highcharts.Serie} class for more info
 *
 * Gauge series is a one dimensional series type, i.e only y-axis data
 */
Ext.define('Chart.ux.Highcharts.GaugeSerie', {
	extend : 'Chart.ux.Highcharts.Serie',
	alternateClassName: [ 'highcharts.gauge' ],
	type : 'gauge'

  /***
   * @cfg xField
   * @hide
   */
});
