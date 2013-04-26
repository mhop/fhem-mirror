/**
 * Serie class for Funnel series type
 *
 * See {@link Chart.ux.Highcharts.Serie} class for more info
 *
 * Example of series config:
 *
 *     series: [{
 *         type: 'funnel',
 *         // or xField
 *         categorieField: 'category',
 *         yField: 'value',
 *     }]
 *
 * **Note**: You must load Highcharts module http://code.highcharts.com/modules/funnel.js in 
 * your HTML file, otherwise you get unknown series type error 
 */
Ext.define('Chart.ux.Highcharts.FunnelSerie', {
	  extend : 'Chart.ux.Highcharts.WaterfallSerie',
	  alternateClassName: [ 'highcharts.funnel' ],
	  type : 'funnel',

    /**
     * @cfg sumTypeField
     * @hide
     */

    getData: function(record, index) {

        var dataObj = {
            y: record.data[ this.valField ],
            name: record.data[ this.nameField ]
        };

        // Only define color if there is value, otherwise it column
        // won't take any global color definitiion
        record.data [ this.colorField ] && (dataObj.color = record.data[this.colorField]);

        return dataObj;
    }
});
