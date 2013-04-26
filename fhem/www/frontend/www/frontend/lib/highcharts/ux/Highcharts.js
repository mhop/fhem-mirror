/**
 * @author 
 * Joe Kuan <kuan.joe@gmail.com>
 *
 * version 2.4.2
 *
 * <!-- You are not permitted to remove the author section (above) from this file. -->
 *
 * Documentation last updated: 17 Apr 2013
 *
 * A much improved & ported from ExtJs 3 Highchart adapter. 
 *
 * - Supports the latest Highcharts (3.0.0)
 * - Supports both Sencha ExtJs 4 and Touch 2
 * - Supports Highcharts animations
 *
 * In order to use this extension, you are expected to know how to use Highcharts and Sencha products (ExtJs 4 &amp; Touch 2). 
 *
 * # Configuring Highcharts Extension
 * The Highcharts extension requires a few changes from an existing Highcharts configuration. Suppose we already have a
 * configuration as follows:
 *     @example
 *     var chart = new Highcharts.Chart({
 *       chart: {
 *          renderTo: 'container',
 *          type: 'spline'
 *       },
 *       title: {
 *          text: 'A simple graph'
 *       },
 *       xAxis: {
 *          categories: [ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
 *                        'Aug', 'Sep', 'Oct', 'Nov', 'Dec' ]
 *       },
 *       series: [{
 *          dashStyle: 'DashDot',
 *          data: [54.7, 54.7, 53.9, 54.8, 54.4, 54.2, 52.4, 51.0, 49.0, 47.4, 47.0, 46 ]
 *       }]
 *     });
 * ## Step 1: Remove data related fields
 *
 * The first step is to take out the configuration 
 * object and remove any data related properties such as: *xAxis.categories* and *series[0].data*. Then removes 
 * *chart.renderTo* option as the extension will fill in that property internally. This leaves us with the following config:
 *     @example
 *     chart: {
 *        type: 'spline'
 *     },
 *     title: {
 *        text: 'A simple graph'
 *     },
 *     series: [{
 *        dashStyle: 'DashDot'
 *     }]
 * ## Step 2: Create chartConfig
 *
 * The next step is to create an object called, *chartConfig*, and put the above configuration in it. Then we extract the 
 * series array to an upper level which gives the followings:
 *     @example
 *     series: [{
 *       dashStyle: 'DashDot'
 *     }],
 *     chartConfig: {
 *       chart: {
 *           type: 'spline'
 *       },
 *       title: {
 *           text: 'A simple graph'
 *       }
 *     }
 * ## Step 3: Create ExtJs Store and data mappings
 *
 * Then we create a ExtJs Store object to map the data fields.
 *     @example
 *     Ext.define('SampleData', {
 *        extend: 'Ext.data.Model',
 *          fields: [
 *              {name: 'month', type: 'string'},
 *              {name: 'value',  type: 'float'}
 *          ]
 *     });
 *     
 *     var store = Ext.create('Ext.data.Store', {
 *        model: 'SampleData',
 *        proxy: {
 *            type: 'ajax',
 *            url: '/getData.php',
 *            reader: {
 *                type: 'json',
 *                root: 'rows'
 *            }
 *        },
 *        autoLoad: false
 *      });
 * Then we modify the series array with data mappings to Store; we add *xField* outside the series array 
 * as categories data and *dataIndex* for the y-axis values. For historical reason, we can also use *yField*, 
 * just an alias name for *dataIndex*.
 *     @example
 *     series:[{
 *        dashStyle: 'DashDot',
 *        dataIndex: 'value'
 *     }],
 *     xField: 'month',
 *     store: store,
 *     chartConfig: {
 *        chart: {
 *        ....
 *
 * ## Step 4: Create ExtJs Highcharts Component
 *
 * The final step is to create a Highcharts component with the whole config as an object specifier.
 *     @example
 *     var win = new Ext.create('Ext.window.Window', {
 *         layout: 'fit',
 *         items: [{
 *            xtype: 'highchart',
 *            series:[{
 *               dashStyle: 'DashDot',
 *               dataIndex: 'value'
 *            }],
 *            xField: 'month',
 *            store: store,
 *            chartConfig: {
 *               chart: {
 *                  type: 'spline'
 *               },
 *               title: {
 *                  text: 'A simple graph'
 *               }
 *            }
 *         }]
 *     }).show();
 *
 * # Updating Highcharts chart properties dynamically
 * Some of the Highcharts properties cannot be updated interactively such as relocating legend box, 
 * switching column charts stacking mode. The only way is to manually destroy and create the whole chart again. 
 * In Highcharts extension, this can be done in an easier fashion. The Highcharts component itself
 * contains a *chartConfig* object which holds the existing native Highcharts configurations. At runtime,
 * options inside *chartConfig* can be modified and call method *draw* which interally destroys and
 * creates a new chart. As a result, the chart appears as a dynamic smooth update
 *     @example
 *     var chart = new Ext.create('Chart.ux.Highcharts', {
 *                     ....
 *                 });
 *     chart.chartConfig.plotOptions.column.stacking = 'normal';
 *     chart.draw();
 * 
 * # Mapping between JsonStore and series data
 * The data mapping between JsonStore and chart series option is quite straightforward. Please refers
 * to the desired {@link Chart.ux.Highcharts.Serie} class and {@link Chart.ux.Highcharts.Serie#method-getData} 
 * method for more details on data mapping.
 *
 * # Multiple series with non-uniform datasets (Irregular data)
 * For plotting multiple series that do not have the same number of data points, see 
 * {@link Chart.ux.Highcharts.Serie} class and {@link Chart.ux.Highcharts.Serie#cfg-dataIndex} configuration for
 *  more details on data mapping.
 *
 * # Using the extension without Store
 * The extension can be created without necessary binding to a store. Suppose there are too many possible series
 * that are not practical to be initiated as part of chart data. Instead, the chart component can be
 * created without any datasets. However, the chart initial animation ({@link Chart.ux.Highcharts#cfg-initAnimAfterLoad})
 * must be switched off, so that the extension won't defer plotting the chart waiting for data.
 *     xtype: 'highchart',
 *     initAnimAfterLoad: false,
 *     chartConfig : {
 *         chart : {
 *             // Show the empty chart - See Highcharts option
 *             showAxes: true,
 *             ....
 *         },
 *         ...
 *     }
 * Once the chart is displayed, the dynamic series can be displayed via {@link Chart.ux.Highcharts#method-addSeries} method
 * using the 'data' field. This can further called by a separate store's load method triggered by some form of
 * interactions from the UI.
 */
Ext.define("Chart.ux.Highcharts", {
    extend : 'Ext.Component',
    alias : ['widget.highchart'],

    statics: {
        /***
         * @static
         * Version string of the current Highcharts extension
         */
        version: '2.4.2',

        /***
         * @property {Object} sencha
         * @readonly
         * Contain shorthand representations of which Sencha product is the 
         * Highcharts extension currently running in. 
         *     // Under Sencha ExtJs
         *     { product: 'e', major: 4, name: 'e4' }
         *     // Under Sencha Touch 2
         *     { product: 't', major: 2, name: 't2' }
         */
        sencha: function() {
            if (Ext.versions.extjs) {
                return {
                    product: 'e',
                    major: Ext.versions.extjs.major,
                    name: 'e' + Ext.versions.extjs.major
                };
            }
            if (Ext.versions.touch) {
                return {
                    product: 't',
                    major: Ext.versions.touch.major,
                    name: 't' + Ext.versions.touch.major
                };
            }
            return {
                product: null,
                major: null,
                name: null
            };
        }()
    },

    /***
     * @property {Boolean} debug
     * Switch on the debug logging to the console
     */
    debug: false,

    switchDebug : function() {
        this.debug = true;
    },

    /***
     * This method is called by other routines within this extension to output debugging log.
     * This method can be overrided with Ext.emptyFn for product deployment
     * @param {String} msg debug message to the console
     */
    log: function(msg) {
        (typeof console !== 'undefined' && this.debug) && console.log(msg);
    },
    
    /**
     * @cfg {Object} defaultSerieType
     * If the series.type is not defined, then it will refer to this option
     */
    defaultSerieType : 'line',
    
    /**
     * @cfg {Boolean} resizable
     * True to allow resizing, false to disable resizing (defaults to true).
     */
    resizable : true,

    /**
     * @cfg {Number} updateDelay
     * A delay to call {@link Chart.ux.Highcharts#method-draw} method
     */
    updateDelay : 0,

    /**
     * @cfg {Object} loadMask An {@link Ext.LoadMask} config or true to mask the
     * chart while
     * loading. Defaults to false.
     */
    loadMask : false,

    /***
     * @cfg {String} loadMaskMsg Message display for loadmask
     */
    loadMaskMsg: 'Loading ... ',

    /**
     * @cfg {Boolean} refreshOnChange 
     * chart refresh data when store datachanged event is triggered,
     * i.e. records are added, removed, or updated.
     * If your application is just purely showing data from store load, 
     * then you don't need this.
     */
    refreshOnChange: false,

    refreshOnLoad: true,

    /**
     * @cfg {Boolean}
     * this config enable or disable chart animation 
     */
    animation: true,
    updateAnim: true,

    /*** 
     * @cfg {Boolean} lineShift
     * The line shift is achieved by comparing the existing x values in the chart
     * and x values from the store record and work out the extra record.
     * Then append the new records with shift property. Hence, any old records with updated
     * y values are ignored
     */
    lineShift: false,

    initAnim: true,
    /**
     * @cfg {Boolean}
     * In a nutshell, keeps this option to true.
     *
     * Since Highcharts initial and update animations are not the same, 
     * if you want to make sure there is initial animation, then you should create store 
     * and extension in specific sequence. First, set the {@link Ext.data.Store#cfg-autoLoad} 
     * option to false, create the Highcharts component with the store, then call the 
     * {@link Ext.data.Store#method-load} method. The *initAnimAfterLoad* defers creating 
     * the chart internally until the store is loaded. Disabling it, the extension will create 
     * the chart instantly and you will only see the update animation after the load.
     */
    initAnimAfterLoad: true,

    /**
     * @cfg {Function} afterChartRendered 
     * callback for after the Highcharts
     * is rendered. **Note**: Do not call initial {@link Ext.data.Store#method-load} inside this handler, 
     * especially with *initAnimAfterLoad* set to true because {@link Ext.data.Store#method-load} will
     * never be called as the chart is deferring to render waiting for the store data. Here is an example
     * of how this should be called. This 'this' keyword refers to the Highcharts ExtJs component whereas
     * chart refers to the created Highcharts chart object
     *       items: [{
     *          xtype: 'highchart',
     *          listeners: {
     *              afterChartRendered: function(chart) {
     *                  // 'this' refers to the 'highchart' ExtJs component
     *                  var size = this.getSize();
     *                  // Get the average value of the first series
     *                  var temp = 0;
     *                  Ext.each(chart.series[0].data, function(data) {
     *                      temp += data;
     *                  });
     *                  temp = temp / chart.series[0].data.length;
     *                  Ext.Msg.alert('Info', 'The average value is ' + temp);
     *              }
     *          },
     *          series:[ ... ],
     *          xField: 'month',
     *          store: store,
     *          chartConfig: {
     *             ....
     *          }
     */
    afterChartRendered: null,

    constructor: function(config) {
        config.listeners && (this.afterChartRendered = config.listeners.afterChartRendered);
        this.afterChartRendered && (this.afterChartRendered = Ext.bind(this.afterChartRendered, this));
        if (config.animation == false) {
            this.animation = false;
            this.initAnim = false;
            this.updateAnim = false; 
            this.initAnimAfterLoad = false;
        }

        this.callParent(arguments);

        // Important: Sencha Touch needs this
        (this.statics().sencha.product == 't') && this.on('show', this.afterRender);

    },

    initComponent : function() {
        if(this.store) {
            this.store = Ext.data.StoreManager.lookup(this.store);
        }
        if (this.animation == false) {
            this.initAnim = false;
            this.updateAnim = false; 
            this.initAnimAfterLoad = false;
        }

        this.callParent(arguments);
    },

    /***
     * Add one or more series to the chart. The addSeries method can be used with Serie field name configurations referring to fields from the store
     * or static data using the data field as the native Highcharts series configuration
     *     // Append a series with specific data
     *     addSeries([{
     *         name: 'Series A',
     *         data: [ [ 3, 5 ], [ 4, 6 ], [ 5, 7 ] ]
     *     }], true);
     *
     * @param {Array} series An array of series configuration objects
     * @param {Boolean} append Append the series if true, otherwise replace all the existing chart series. Optional parameter, Defaults to true if not specified
     */
    addSeries : function(series, append) {

        append = (append === null || append === true) ? true : false;

        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        var n = new Array(), c = new Array(), cls, serieObject;
        // Add empty data to the serie or just leave it normal. Bug in HighCharts?
        for(var i = 0; i < series.length; i++) {
            // Clone Serie config for scope injection
            var serie = Ext.clone(series[i]);
            if(!serie.serieCls) {
                if(serie.type != null || this.defaultSerieType != null) {
                    cls = serie.type || this.defaultSerieType;
                    cls = "highcharts." + cls;  // See alternateClassName
                } else {
                    cls = "Chart.ux.Highcharts.Serie";
                }

                serieObject = Ext.create(cls, serie);
            } else {
                serieObject = serie;
            }

            serieObject.chart = this;

            c.push(serieObject.config);
            n.push(serieObject);
        }

        // Show in chart
        if(this.chart) {
            if(!append) {
                this.removeAllSeries();
                _this.series = n;
                _this.chartConfig.series = c;
            } else {
                _this.chartConfig.series = _this.chartConfig.series ? _this.chartConfig.series.concat(c) : c;
                _this.series = _this.series ? _this.series.concat(n) : n;
            }
            for(var i = 0; i < c.length; i++) {
                this.chart.addSeries(c[i], true);
            }
            this.refresh();

            // Set the data in the config.
        } else {

            if(append) {
                _this.chartConfig.series = _this.chartConfig.series ? _this.chartConfig.series.concat(c) : c;
                _this.series = _this.series ? _this.series.concat(n) : n;
            } else {
                _this.chartConfig.series = c;
                _this.series = n;
            }
        }
    },

    /***
     * Remove particular series from the chart. 
     * @param {Number} id the index value in the chart series array
     * @param {Boolean} redraw Set it to true to immediate redraw the chart to reflect the change
     */
    removeSerie : function(id, redraw) {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        redraw = redraw || true;
        if(this.chart) {
            this.chart.series[id].remove(redraw);
            _this.chartConfig.series.splice(id, 1);
        }
        _this.series.splice(id, 1);
    },

    /***
     * Remove all series in the chart. This also remove any categories
     * data along the axes
     */
    removeAllSeries : function() {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;
        var sc = _this.series.length;
        for(var i = 0; i < sc; i++) {
            this.removeSerie(0);
        }
        // Need to also clean up the previous categories data if
        // there are any
        Ext.each(_this.chartConfig.xAxis, function(xAxis) {
            delete xAxis.categories;
        });
    },

    /**
     * Set the title of the chart and redraw the chart
     * @param {String} title Text to set the subtitle
     */
    setTitle : function(title) {

        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        if(_this.chartConfig.title)
            _this.chartConfig.title.text = title;
        else
            _this.chartConfig.title = {
                text : title
            };
        if(this.chart && this.chart.container)
            this.draw();
    },

    /**
     * Set the subtitle of the chart and redraw the chart
     * @param {String} title Text to set the subtitle
     */
    setSubTitle : function(title) {

        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        if(_this.chartConfig.subtitle)
            _this.chartConfig.subtitle.text = title;
        else
            _this.chartConfig.subtitle = {
                text : title
            };
        if(this.chart && this.chart.container)
            this.draw();
    },

    initEvents : function() {

    },

    afterRender : function() {

        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        if(this.store)
            this.bindStore(this.store, true);

        this.bindComponent(true);

        // Ext.applyIf causes problem in 4.1.x but works fine with
        // 4.0.x
        Ext.apply(_this.chartConfig.chart, {
            renderTo : (this.statics().sencha.product == 't') ? this.element.dom : this.el.dom
        });

        Ext.applyIf(_this.chartConfig, {
            xAxis : [{}]
        });

        if(_this.xField && this.store) {
            this.updatexAxisData();
        }

        if(_this.series) {
            this.log("Call addSeries");
            this.addSeries(_this.series, false);
        } else
            _this.series = [];

        this.initEvents();
        // Make a delayed call to update the chart.
        this.update(0);
    },

    onMove : function() {

    },

    /***
     *  @private
     *  Build the initial data set if there are data already
     *  inside the store.
     */
    buildInitData : function() {

        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;
        var series = null, chartConfigSeries = null;
        var ptObject = null, record = null, colorField = null;

        if (!this.store || this.store.isLoading() || 
            !_this.chartConfig || this.initAnim === false ||
            _this.chartConfig.chart.animation === false) {
            return;
        }

        var data = [], seriesCount = _this.series.length, i;

        var items = this.store.data.items;
        (_this.chartConfig.series === undefined) && (_this.chartConfig.series = []);
        for( i = 0; i < seriesCount; i++) {

            if (!_this.chartConfig.series[i])
                _this.chartConfig.series[i] = { data: [] };
            else 
                _this.chartConfig.series[i].data = [];

            // Sort out the type for this series
            series = _this.series[i];
            series.buildInitData(items);
        }
    },

    /**
     * Redraw the chart. It internally destroys existing chart (if already display) and 
     * re-creates the chart object. Call this method to reflect any structural changes in chart configuration 
     */
    draw : function() {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        this.log("call draw");
        if(this.chart && this.rendered) {
            if(this.resizable) {
                for(var i = 0; i < _this.series.length; i++) {
                    _this.series[i].visible = this.chart.series[i].visible;
                }

                // Redraw the highchart means recreate the highchart
                // inside this component
                // Destroy
                this.chart.destroy();
                delete this.chart;

                this.buildInitData();

                // Create a new chart
                this.chart = new Highcharts.Chart(_this.chartConfig, this.afterChartRendered);
            }

        } else if(this.rendered) {
            // Create the chart from fresh

            if (!this.initAnimAfterLoad || (this.store && this.store.getCount() > 0)) {
                this.buildInitData();
                this.chart = new Highcharts.Chart(_this.chartConfig, this.afterChartRendered);
                this.log("initAnimAfterLoad is off, creating chart from fresh");
            } else {
                this.log("initAnimAfterLoad is on, defer creating chart");
                return;
            }
        }

        for( i = 0; i < _this.series.length; i++) {
            if(!_this.series[i].visible)
                _this.chart.series[i].hide();
        }

        // Refresh the data only if it is not loading
        // no point doing this, as onLoad will pick it up
        if (this.store && !this.store.isLoading()) {
            this.log("Call refresh from draw"); 
            this.refresh();
        }
    },

    //@deprecated
    onContainerResize : function() {
        Ext.log("onContainerResize");
        this.draw();
    },

    //private
    updatexAxisData : function() {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        var data = [], items = this.store.data.items;

        if(_this.xField && this.store) {
            for(var i = 0; i < items.length; i++) {
                data.push(items[i].data[_this.xField]);
            }
            if(this.chart)
                this.chart.xAxis[0].setCategories(data, true);
            else if (Ext.isArray(_this.chartConfig.xAxis)) {
                _this.chartConfig.xAxis[0].categories = data;
            } else {
                _this.chartConfig.xAxis.categories = data;
            } 
        }
    },

    bindComponent : function(bind) {
        if(bind) {
            this.on('move', this.onMove);
            this.on('resize', this._onResize);
        } else {
            this.un('move', this.onMove);
            this.un('resize', this._onResize);
        }
    },

    /**
     * Changes the data store bound to this chart and refreshes it.
     * @param {Store} store The store to bind to this chart
     */
    bindStore : function(store, initial) {

        if(!initial && this.store) {
            if(store !== this.store && this.store.autoDestroy) {
                this.store.destroy();
            } else {
                this.store.un("datachanged", this.onDataChange, this);
                this.store.un("load", this.onLoad, this);
                this.store.un("add", this.onAdd, this);
                this.store.un("remove", this.onRemove, this);
                this.store.un("update", this.onUpdate, this);
                this.store.un("clear", this.onClear, this);
            }
        }

        if(store) {
            store = Ext.StoreMgr.lookup(store);
            store.on({
                scope : this,
                load : this.onLoad,
                datachanged : this.onDataChange,
                add : this.onAdd,
                remove : this.onRemove,
                update : this.onUpdate,
                clear : this.onClear
            });
        }

        this.store = store;

        if (this.loadMask !== false) {
            if (this.loadMask === true) {
                this.loadMask = new Ext.LoadMask({target:this,store:this.store});
            } else {
                this.loadMask.bindStore(this.store);
            }
        }
        
        if(store && !initial) {
            this.refresh();
        }
    },

    /**
     * Complete refresh series in the chart. This method rebuilds the chart series
     * array from the current store records. Any store record changes should call 
     * this method to reflect to the chart.
     */
    refresh : function() {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        this.log("Call refresh ");
        if(this.store && this.chart) {

            var data = new Array(), seriesCount = _this.series.length, i;

            for( i = 0; i < seriesCount; i++)
                data.push(new Array());

            // We only want to go true the data once.
            // So we need to have all columns that we use in line.
            // But we need to create a point.
            var items = this.store.data.items;
            var xFieldData = [];

            for(var x = 0; x < items.length; x++) {
                var record = items[x];

                if(_this.xField) {
                    xFieldData.push(record.data[_this.xField]);
                }

                for( i = 0; i < seriesCount; i++) {
                    var serie = _this.series[i], point;
                    // if serie.config.getData is defined, it doesn't need
                    // reference to dataIndex or yField, it just direct access
                    // to fields inside the implementation
                    if (serie.dataIndex || serie.yField || 
                        serie.minDataIndex || serie.config.getData) {
                        // record.data[dataIndex] is an array, then treat it as an array of 
                        // data points
                        if (Ext.isArray(record.data[serie.dataIndex])) {
                            Ext.each(record.data[serie.dataIndex], function(dataPoint) {
                                data[i].push(dataPoint);
                            });
                        } else {
                            point = serie.getData(record, x);
                            serie.bindRecord && (point.record = record);
                            data[i].push(point);
                        }
                    } else if (serie.type == 'pie') {
                        if (serie.useTotals) {
                            if(x == 0)
                                serie.clear();
                            point = serie.getData(record, x);
                            serie.bindRecord && (point.record = record);
                        } else if (serie.totalDataField) {
                            serie.getData(record, data[i]);
                        } else {
                            point = serie.getData(record, x);
                            serie.bindRecord && (point.record = record);
                            data[i].push(point);
                        }
                    } else if (serie.type == 'gauge') {
                        // Gauge is a dial type chart, so the data can only
                        // have one value
                        data[i][0] = serie.getData(record, x); 
                    } else if (serie.data && serie.data.length) {
                        // This means the series is added within its own data
                        // not from the store
                        if (serie.data[x] !== undefined) {
                            data[i].push(serie.data[x]);
                        } else {
                            data[i].push(null);
                        }
                    }
                }
            }

            // Update the series
            if (!this.updateAnim) {
                for( i = 0; i < seriesCount; i++) {
                    if(_this.series[i].useTotals) {
                        this.chart.series[i].setData(_this.series[i].getTotals());
                    } else if(data[i].length > 0 || _this.series[i].updateNoRecord) {
                        this.chart.series[i].setData(data[i], i == (seriesCount - 1));
                        // true == redraw.
                    }
                }
                
                if(_this.xField) {
                    //this.updatexAxisData();
                    this.chart.xAxis[0].setCategories(xFieldData, true);
                }
            } else {
                var xCatStartIdx = -1;
                this.log("Update animation with line shift: " + _this.lineShift);
                for( i = 0; i < seriesCount; i++) {
                    if (_this.series[i].useTotals) {
                        this.chart.series[i].setData(_this.series[i].getTotals());
                    } else if (data[i].length > 0 || _this.series[i].updateNoRecord) {
                        if (!_this.lineShift) {
                            // Need to work out the length between the store dataset and
                            // the current series data set
                            var chartSeriesLength = this.chart.series[i].points.length;
                            var storeSeriesLength = data[i].length;
                            for (var x = 0; x < Math.min(chartSeriesLength, storeSeriesLength); x++) {
                                this.chart.series[i].points[x].update(data[i][x], false, true);
                            }

                            // Gotcha, we need to be careful with pie series, as the totalDataField
                            // can conflict with the following series data points trimming operations
                            if (_this.series[i].type === 'pie') {
                                this.chart.series[i].setData([]);
                                for (var x=0;x<data[i].length;x++) {
                                    this.chart.series[i].addPoint(data[i][x], false, false, false);
                                }
                                this.chart.series[i].animate = Highcharts.seriesTypes.pie.prototype.animate.bind(this.chart.series[i]);
                                this.chart.redraw();
                                continue;
                            }

                            // Append the rest of the points from store to chart
                            this.log("chartSeriesLength " + chartSeriesLength + ", storeSeriesLength " + storeSeriesLength);
                            if (chartSeriesLength < storeSeriesLength) {
                                for (var y = 0; y < (storeSeriesLength - chartSeriesLength); y++, x++) {
                                    if (Ext.isObject(data[i][x])) {
                                        // Can be an object if the data point includes colorField dataIndex
                                        (data[i][x].x === undefined) && (data[i][x].x = x);
                                        this.chart.series[i].addPoint(data[i][x], false, false, true);
                                    } else {
                                        this.chart.series[i].addPoint(data[i][x], false, false, true);
                                    }
                                }
                            }
                            // Remove the excessive points from the chart
                            else if (chartSeriesLength > storeSeriesLength) {
                                for (var y = 0; y < (chartSeriesLength - storeSeriesLength); y++) {
                                    // Points.length is not immediately updated after remove call, so don't use points.length
                                    var last = chartSeriesLength - y - 1;
                                    this.log("Remove point at pos " + last);
                                    this.chart.series[i].points[last].remove(false, true);
                                }
                            }
                        } else {
                            var xAxis = Ext.isArray(this.chart.xAxis) ? this.chart.xAxis[0] : this.chart.xAxis;
                            // We need to see whether compare through xAxis categories or data points x axis value
                            var startIdx = -1; 

                            if (xAxis.categories) {
                                // Since this is categories, it means multiple series share the common
                                // categories. Hence we only do it once to find the startIdx position
                                if (i == 0) {
                                    for (var x = 0 ; x < xFieldData.length; x++) {
                                        var found = false;
                                        for (var y = 0; y < xAxis.categories.length; y++) {
                                            if (xFieldData[x] == xAxis.categories[y]) {
                                                found = true
                                                break;
                                            }
                                        }
                                        if (!found) {
                                            xCatStartIdx = startIdx = x;
                                            break;
                                        } 
                                    }

                                    var categories = xAxis.categories.slice(0);
                                    categories.push(xFieldData[x]);
                                    xAxis.setCategories(categories, false);
                                } else {
                                    // Reset the startIdx
                                    startIdx = xCatStartIdx;
                                }
                                this.log("startIdx " + startIdx);
                                // Start shifting
                                if (startIdx !== -1 && startIdx < xFieldData.length) {
                                    for (var x = startIdx; x < xFieldData.length; x++) {

                                        this.chart.series[i].addPoint(data[i][x],
                                                                      false, true, true);
                                    }
                                }
                            } else { 
                                var chartSeries = this.chart.series[i].points;
                                for (var x = 0 ; x < data[i].length; x++) {
                                    var found = false;
                                    for (var y = 0; y < chartSeries.length; y++) {
                                        if (data[i][x][0] == chartSeries[y].x) {
                                            found = true
                                            break;
                                        }
                                    }
                                    if (!found) {
                                        startIdx = x;
                                        break;
                                    } 
                                }
                                this.log("startIdx " + startIdx);
                                // Start shifting
                                if (startIdx !== -1 && startIdx < data[i].length) {
                                    for (var x = startIdx; x < data[i].length; x++) {
                                        this.chart.series[i].addPoint(data[i][x], false, true, true);
                                    }
                                }

                            }
                        }
                    }
                }

                // For Line Shift it has to be setCategories before addPoint
                if(_this.xField && !_this.lineShift) {
                    //this.updatexAxisData();
                    this.chart.xAxis[0].setCategories(xFieldData, false);
                }

                this.log("Call chart redraw");
                this.chart.redraw();
            }
        }
    },

    /***
     * Update a selected row.
     */
    refreshRow : function(record) {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        var index = this.store.indexOf(record);
        if(this.chart) {
            for(var i = 0; i < this.chart.series.length; i++) {
                var serie = this.chart.series[i];
                var point = _this.series[i].getData(record, index);
                if(_this.series[i].type == 'pie' && _this.series[i].useTotals) {
                    _this.series[i].update(record);
                    this.chart.series[i].setData(_this.series[i].getTotals());
                } else
                    serie.data[index].update(point);
            }

            if(_this.xField) {
                this.updatexAxisData();
            }
        }
    },

    /**
     * A function to delay the call to {@link Chart.ux.Highcharts#method-draw} method
     * @param {Number} delay Set a custom delay
     */
    update : function(delay) {
        var cdelay = delay || this.updateDelay;
        if(!this.updateTask) {
            this.updateTask = new Ext.util.DelayedTask(this.draw, this);
        }
        this.updateTask.delay(cdelay);
    },

    // private
    onDataChange : function() {
        this.refreshOnChange && (this.refresh() && this.log("onDataChange"));
    },

    // private
    onClear : function() {
        // In Sencha Touch, load method issue clear event
        // this will call refresh twice which removes the
        // animation effect
        if (this.statics().sencha.product == 't' && this.store && !this.store.isLoading()) {
            this.refresh();
        }
    },

    // private
    onUpdate : function(ds, record) {
        this.refreshRow(record);
    },

    // private
    onAdd : function(ds, records, index) {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        var redraw = false, xFieldData = [];

        for(var i = 0; i < records.length; i++) {
            var record = records[i];
            if(i == records.length - 1)
                redraw = true;
            if(_this.xField) {
                xFieldData.push(record.data[_this.xField]);
            }

            for(var x = 0; x < this.chart.series.length; x++) {
                var serie = this.chart.series[x], s = _this.series[x];
                var point = s.getData(record, index + i);
                if(!(s.type == 'pie' && s.useTotals)) {
                    serie.addPoint(point, redraw);
                }
            }
        }
        if(_this.xField) {
            this.chart.xAxis[0].setCategories(xFieldData, true);
        }

    },

    //private
    _onResize : function() {
        this.resizable && this.update();
    },

    // private
    onRemove : function(ds, record, index, isUpdate) {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        for(var i = 0; i < _this.series.length; i++) {
            var s = _this.series[i];
            if(s.type == 'pie' && s.useTotals) {
                s.removeData(record, index);
                this.chart.series[i].setData(s.getTotals());
            } else {
                this.chart.series[i].data[index].remove(true);
            }
        }
        Ext.each(this.chart.series, function(serie) {
            serie.data[index].remove(true);
        });

        if(_this.xField) {
            this.updatexAxisData();
        }
    },

    // private
    onLoad : function() {

        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        if (!this.chart && this.initAnimAfterLoad) {
            this.log("Call refresh from onLoad for initAnim");
            this.buildInitData();
            this.chart = new Highcharts.Chart(_this.chartConfig, this.afterChartRendered);
            return;
        } 

        this.log("Call refresh from onLoad");
        this.refreshOnLoad && this.refresh();
    },

    /***
     * Destroy the Highchart component as well as the interal chart component
     */
    destroy : function() {
        // Sencha Touch uses config to access properties
        var _this = (this.statics().sencha.product == 't') ? this.config : this;

        delete _this.series;
        if(this.chart) {
            this.chart.destroy();
            delete this.chart;
        }

        this.bindStore(null);
        this.bindComponent(null);

        this.callParent(arguments);
    }

});
