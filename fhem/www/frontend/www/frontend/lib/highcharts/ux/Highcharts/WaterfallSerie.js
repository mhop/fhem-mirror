/**
 * Serie class for water fall series type
 *
 * See {@link Chart.ux.Highcharts.Serie} class for more info
 *
 * The following is the config example converted from the original 
 * [Highcharts waterfall demo][1]
 * [1]: http://www.highcharts.com/demo/waterfall
 *
 *     series: [{
 *         type: 'waterfall',
 *         upColor: Highcharts.getOptions().colors[2],
 *         color: Highcharts.getOptions().colors[3],
 *         categorieField: 'category',
 *         yField: 'value',
 *         colorField: 'color',
 *         sumTypeField: 'sum',
 *         dataLabels: {
 *             ....
 *         }
 *     }]
 *
 * The Json data returning from the server side should look like as follows:
 * 
 *     {"root":[{ "category":"Start","value":120000 }, 
 *              { "category":"Product Revenue","value":569000 },
 *              { "category":"Service Revenue","value":231000 },
 *              { "category":"Positive Balance","color": "#0d233a", "sum": "intermediate" },
 *              { "category":"Fixed Costs","value":-342000 },
 *              { "category":"Variable Cost","value": -233000 },
 *              { "category":"Balance","color": "#0d233a", "sum": "final" }
 *     ]}
 *
 */
Ext.define('Chart.ux.Highcharts.WaterfallSerie', {
	  extend : 'Chart.ux.Highcharts.Serie',
	  alternateClassName: [ 'highcharts.waterfall' ],
	  type : 'waterfall',

    /**
     * @cfg {String} sumTypeField
     * Column value is whether derived from precious values. 
     * Possible values: 'intermediate', 'final' or null (expect dataIndex or yField contains value)
     */
    sumTypeField: null,

    constructor: function(config) {

        this.callParent(arguments);
        this.valField = this.yField || this.dataIndex;
        this.nameField = this.categorieField || this.xField;
    },

    getData: function(record, index) {

        var dataObj = {
            y: record.data[ this.valField ],
            name: record.data[ this.nameField ]
        };

        // Only define color if there is value, otherwise it column
        // won't take any global color definitiion
        record.data [ this.colorField ] && (dataObj.color = record.data[this.colorField]);

        if (this.sumTypeField) {
            if (record.data[this.sumTypeField] == "intermediate") {
                dataObj.isIntermediateSum = true;
            } else if (record.data[this.sumTypeField] == "final") {
                dataObj.isSum = true;
            }
        }

        return dataObj;
    }
});
