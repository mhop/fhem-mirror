/***
 * Serie class is the base class for all the series types. Users shouldn't use any of the 
 * series classes directly, they are created internally from Chart.ux.Highcharts depending on the
 * series configuration.
 *
 * Serie class is a general class for series data representation. 
 * # Mapping data fields 
 * In the Highcharts extension, the series option is declared outside of chartConfig, so as the *xField*. 
 * There is a subtle difference for declaring xField outside or inside a series. For example:
 *
 *     series:[{
 *        name: 'Share A',
 *        type: 'line',
 *        yField: 'sharePriceA'
 *     }, {
 *        name: 'Share B',
 *        type: 'line',
 *        yField: 'sharePriceB'
 *     }],
 *     xField: 'datetime',
 *     ....
 * This means both series share the same categories and each series has it own set of y-values. 
 * In this case, the datetime field can be either string or numerical representation of date time.
 *     series:[{
 *        name: 'Share A',
 *        type: 'line',
 *        yField: 'sharePriceA',
 *        xField: 'datetimeA'
 *     }, {
 *        name: 'Share B',
 *        type: 'line',
 *        yField: 'sharePriceB',
 *        xField: 'datetimeB'
 *     }],
 * This means both series have their own (x,y) data. In this case, the xField must refer to numerical values.
 * 
 * # Mapping multiple series with irregular datasets
 * Suppose we have 3 series with different set of data points. To map the store with the series, first
 * the store is required to return Json data in the following format:
 *     { root: [ 
 *           series1: [ [ 1, 3 ], [ 2, 5 ], [ 7, 1 ] ],
 *           series2: [ [ 2, 4 ], [ 5, 7 ] ],
 *           series3: [ [ 1, 8 ], [ 4, 6 ], [ 5, 1 ], [ 9, 4 ] ]
 *       ]
 *     }
 *
 * Then use {@link Chart.ux.Highcharts.Serie#cfg-dataIndex} to map the series data array
 *     series: [{
 *         name: 'Series A',
 *         dataIndex: 'series1'
 *     }, {
 *         name: 'Series B',
 *         dataIndex: 'series2'
 *     }, {
 *         name: 'Series C',
 *         dataIndex: 'series3'
 *     }]
 */
Ext.define('Chart.ux.Highcharts.Serie', {
    requires: [ 'Chart.ux.Highcharts',
                'Ext.util.Observable'
              ],
    mixins: {
        observable: 'Ext.util.Observable'
    },

    /***
     * @cfg {String} type 
     * Highcharts series type name. This field must be specified.
     *
     * Line, area, scatter and column series are the simplest form of charts 
     * (includes Polar) which has the simple data mappings: *dataIndex* or *yField* 
     * for y-axis values and xField for either x-axis category field or data point's 
     * x-axis coordinate.
     *     series: [{
     *        type: 'scatter',
     *        xField: 'xValue',
     *        yField: 'yValue'
     *     }]
     */
    type : null,

    /**
     * @readonly
     * The {@link Chart.ux.Highcharts} chart object owns this serie.
     * @type Object/Chart.ux.Highcharts
     *
     * This can be useful with pointclick event when you need to use an Ext.Component.
     *     pointclick:{
     *         fn:function(serie,point,record,event){
     *         //Get parent window to replace the chart inside (me)
     *         var window=this.chart.up('windows');
     *         }
     *     }
     * Setting the scope on the listeners at runtime can cause trouble in Highcharts on 
     * parsing the listener
     */
    chart: null,

    /**
     * @private
     * The default action for series point data is to use array instead of point object
     * unless desired to set point particular field. This changes the default behaviour
     * of getData template method
     * Default: false
     *
     * @type Boolean
     */
    pointObject: false,

    /**
     * @cfg {String} xField
     * The field used to access the x-axis value from the items from the data
     * source. Store's record
     */
    xField : null,

    /**
     * @cfg {String} yField
     * The field used to access the y-axis value from the items from the data
     * source. Store's record
     */
    yField : null,

    /**
     * @cfg {String} dataIndex can be either an alias of *yField* 
     * (which has higher precedence if both are defined) or mapping to store's field
     * with array of data points
     */
    dataIndex : null,

    /**
     * @cfg {String} colorField
     * This field is used for setting data point color
     * number or color hex in '#([0-9])'. Otherwise, the option
     * is treated as a field name and the store should return 
     * rows with the same color field name. For column type series, if you
     * want Highcharts to automatically color each data point,
     * then you should use [plotOptions.column.colorByPoint][link2] option in the series config
     * [link2]: http://api.highcharts.com/highcharts#plotOptions.column.colorByPoint
     */
    colorField: null,

    /**
     * @cfg {Boolean} visible
     * The field used to hide the serie initial. Defaults to true.
     */
    visible : true,

    clear : Ext.emptyFn,

    /***
     * @cfg {Boolean} updateNoRecord
     * Setting this option to true will enforce the chart to clear the series if 
     * there is no record returned for the series
     */
    updateNoRecord: false,

    /***
     * @private
     * Resolve color based on the value of colorField
     */
    resolveColor: function(colorField, record, dataPtIdx) {

        var color = null;
        if (colorField) {
            if (Ext.isNumeric(colorField)) {
                color = colorField;
            } else if (Ext.isString(colorField)) {
                if (/^(#)?([0-9a-fA-F]{3})([0-9a-fA-F]{3})?$/.test(colorField)) {
                    color = colorField;
                } else {
                    color = record.data[colorField];
                }
            }
        }
        return color;
    },

    /***
     * @private
     * object style of getData
     */
    obj_getData : function(record, index) {
        var yField = this.yField || this.dataIndex, point = {
            data : record.data,
            y : record.data[yField]
        };
        this.xField && (point.x = record.data[this.xField]);
        this.colorField && (point.color = this.resolveColor(this.colorField, record, index));
        this.bindRecord && (point.record = record);
        return point;
    },

    /***
     * @private
     * single value data version of getData - Common category, individual y-data
     */
    arr_getDataSingle: function(record, index) {
        return record.data[this.yField];
    },

    /***
     * @private
     * each data point in the series is represented in it's own x and y values
     */
    arr_getDataPair: function(record, index) {
        return [ record.data[ this.xField ], record.data[ this.yField ] ];
    },

    /***
     * @method getData
     * getData is the core mechanism for transferring from Store's record data into the series data array.
     * This routine acts as a Template Method for any series class, i.e. any new series type class must 
     * support this method.
     * 
     * Generally, you don't need to override this method in the config because this method is internally
     * created once the serie class is instantiated. Depending on whether *xField*, *yField* and 
     * *colorField* are defined, the class constructor creates a *getData* method which either returns a single value,
     * tuple array or a data point object. This is done for performance reason. See Highcharts API document
     * [Series.addPoint][link1] for more details.
     *
     * If your data model requires specific data processing in the record data, then you may need to
     * override this method. The return for the method must confine to the [Series.addPoint][link1]
     * prototype. Note that if this method is manually defined, there is no need to define field name options
     * because this can be specified inside the implementation anyway
     *     series: [{
     *         type: 'spline',
     *         // Return avg y values
     *         getData: function(record) {
     *             return (record.data.y1 + record.data.y2) / 2;
     *         }
     *     }],
     *     xField: 'time',
     *     ....
     *
     * [link1]: http://api.highcharts.com/highcharts#Series.addPoint()
     *
     * @param {Object} record Store's record which contains the series data at particular instance
     * @param {Number} index the index value of the record inside the Store
     * @return {Object|Array|Number}
     */
    getData: null,

    serieCls : true,

    constructor : function(config) {
        config.type = this.type;
        if(!config.data) {
            config.data = [];
        }

        this.mixins.observable.constructor.call(this, config);

        this.addEvents(
            /**
             * @event pointclick
             * Fires when the point of the serie is clicked.
             * @param {Chart.ux.Highcharts.Serie}  serie the serie where is fired
             * @param {Object} point the point clicked
             * @param {Ext.data.Record} record the record associated to the point
             * @param {Object} evt the event param
             */
            'pointclick'
        );

        this.config = config;

        this.yField = this.yField || this.config.dataIndex;

        this.bindRecord = (this.config.listeners && this.config.listeners.pointclick !== undefined);

        // If Highcharts series event is already defined, then don't support this
        // pointclick event
        Ext.applyIf(config,{
            events:{
                click: Ext.bind(this.onPointClick, this)
            }
        });

        // If colorField is defined, then we have to use data point
        // as object
        (this.colorField || this.bindRecord) && (this.pointObject = true);

        // If getData method is already defined, then overwrite it
        if (!this.getData) {
            if (this.pointObject) {
                this.getData = this.obj_getData;
            } else if (this.xField) {
                this.getData = this.arr_getDataPair;
            } else {
                this.getData = this.arr_getDataSingle;
            }
        }
    },

    /***
     *  @private
     *  Build the initial data set if there are data already
     *  inside the store.
     */
    buildInitData:function(items, data) {
        var chartConfig = (Chart.ux.Highcharts.sencha.product == 't') ? 
            this.chart.config.chartConfig : this.chart.chartConfig;
        
        var record;
        var data = this.config.data = [];

        record = items[0];
        if (this.dataIndex && record && Ext.isArray(record.data[this.dataIndex])) {
            this.config.data = record.data[this.dataIndex];
        } else {
            for (var x = 0; x < items.length; x++) {
                record = items[x];
                // Should use the pre-constructed getData template method to extract
                // record data into the data point (Array of values or Point object)
                data.push(this.getData(record, x));
            }
        }
        
        var xAxis = (Ext.isArray(chartConfig.xAxis)) ? chartConfig.xAxis[0] : chartConfig.xAxis;
        
        // Build the first x-axis categories
        if (this.chart.xField && (!xAxis.categories || xAxis.categories.length < items.length)) {
            xAxis.categories = xAxis.categories || [];
            for (var x = 0; x < items.length; x++) {
                xAxis.categories.push(items[x].data[this.chart.xField]);
            }
        }
    },

    onPointClick:function(evt){
        this.fireEvent('pointclick',this,evt.point,evt.point.record,evt);
    },

    destroy: function() {
        this.clearListeners();
        this.mixins.observable.destroy();
    }

});
