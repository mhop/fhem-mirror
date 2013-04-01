/**
 * Controller handling the charts
 */
Ext.define('FHEM.controller.ChartController', {
    extend: 'Ext.app.Controller',
    /**
     * maxValue of Y Axis gets saved here as reference
     */
    maxYValue: 0,
    
    /**
     * minValue of Y Axis gets saved here as reference
     */
    minYValue: 9999999,

    refs: [
           {
               selector: 'panel[name=chartformpanel]',
               ref: 'chartformpanel' //this.getChartformpanel()
           },
           {
               selector: 'datefield[name=starttimepicker]',
               ref: 'starttimepicker' //this.getStarttimepicker()
           },
           {
               selector: 'datefield[name=endtimepicker]',
               ref: 'endtimepicker' //this.getEndtimepicker()
           },
           {
               selector: 'button[name=requestchartdata]',
               ref: 'requestchartdatabtn' //this.getRequestchartdatabtn()
           },
           {
               selector: 'button[name=savechartdata]',
               ref: 'savechartdatabtn' //this.getSavechartdatabtn()
           },
           {
               selector: 'chart',
               ref: 'chart' //this.getChart()
           },
           {
               selector: 'linechartpanel',
               ref: 'linechartpanel' //this.getLinechartpanel()
           },
           {
               selector: 'linechartpanel toolbar',
               ref: 'linecharttoolbar' //this.getLinecharttoolbar()
           },
           {
               selector: 'grid[name=savedchartsgrid]',
               ref: 'savedchartsgrid' //this.getSavedchartsgrid()
           }
           
    ],

    /**
     * init function to register listeners
     */
    init: function() {
        this.control({
            'button[name=requestchartdata]': {
                click: this.requestChartData
            },
            'button[name=savechartdata]': {
                click: this.saveChartData
            },
            'button[name=stepback]': {
                click: this.stepchange
            },
            'button[name=stepforward]': {
                click: this.stepchange
            },
            'button[name=resetchartform]': {
                click: this.resetFormFields
            },
            'grid[name=savedchartsgrid]': {
                cellclick: this.loadsavedchart
            },
            'actioncolumn[name=savedchartsactioncolumn]': {
                click: this.deletechart
            }
        });
        
    },
    
    /**
     * Triggers a request to FHEM Module to get the data from Database
     */
    requestChartData: function(stepchangecalled) {
        
        var me = this;
        //getting the necessary values
        var devices = Ext.ComponentQuery.query('combobox[name=devicecombo]');
        var xaxes = Ext.ComponentQuery.query('combobox[name=xaxiscombo]');
        var yaxes = Ext.ComponentQuery.query('combobox[name=yaxiscombo]');
        var yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=yaxiscolorcombo]');
        var yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=yaxisfillcheck]');
        var yaxesstatistics = Ext.ComponentQuery.query('combobox[name=yaxisstatisticscombo]');
        
        var basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]');
        var basesend = Ext.ComponentQuery.query('numberfield[name=baseend]');
        var basescolors = Ext.ComponentQuery.query('combobox[name=baselinecolorcombo]');
        var basesfills = Ext.ComponentQuery.query('checkboxfield[name=baselinefillcheck]');
        
        
            
        var starttime = me.getStarttimepicker().getValue(),
            dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
            endtime = me.getEndtimepicker().getValue(),
            dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
            dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0],
            chartpanel = me.getLinechartpanel(),
            chart = me.getChart(),
            store = chart.getStore(),
            proxy = store.getProxy();
        
        //cleanup store
        store.removeAll();
        
        //cleanup chart
        for (var i = chart.series.length -1; i >= 0; i--) {
            chart.series.removeAt(i);
        }
        
        //reset zoomValues
        chartpanel.setLastYmax(null);
        chartpanel.setLastYmin(null);
        chartpanel.setLastXmax(null);
        chartpanel.setLastXmin(null);
        
        me.maxYValue = 0;
        me.minYValue = 9999999;
        
        //adding baseline values to max and min values of y-axis
        Ext.each(basesstart, function(basestart) {
            if (me.maxYValue < basestart.getValue()) {
                me.maxYValue = basestart.getValue();
            }
            if (me.minYValue > basestart.getValue()) {
                me.minYValue = basestart.getValue();
            }
        });
        Ext.each(basesend, function(baseend) {
            if (me.maxYValue < baseend.getValue()) {
                me.maxYValue = baseend.getValue();
            }
            if (me.minYValue > baseend.getValue()) {
                me.minYValue = baseend.getValue();
            }
        });
        
        //register store listeners
        store.on("beforeload", function() {
            me.getChart().setLoading(true);
        });
        
        //setting x-axis title
        chart.axes.get(1).setTitle(xaxes[0]);
     
        //check if timerange or dynamic time should be used
        dynamicradio.eachBox(function(box, idx){
            var date = new Date();
            if (box.checked && stepchangecalled !== true) {
                if (box.inputValue === "year") {
                    starttime = Ext.Date.parse(date.getUTCFullYear() + "-01-01", "Y-m-d");
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                    endtime = Ext.Date.parse(date.getUTCFullYear() +  1 + "-01-01", "Y-m-d");
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                } else if (box.inputValue === "month") {
                    starttime = Ext.Date.getFirstDateOfMonth(date);
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                    endtime = Ext.Date.getLastDateOfMonth(date);
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                } else if (box.inputValue === "week") {
                    date.setHours(0);
                    date.setMinutes(0);
                    date.setSeconds(0);
                    //monday starts with 0 till sat with 5, sund with -1
                    var dayoffset = date.getDay() - 1,
                        monday,
                        nextmonday;
                    if (dayoffset >= 0) {
                        monday = Ext.Date.add(date, Ext.Date.DAY, -dayoffset);
                    } else {
                        //we have a sunday
                        monday = Ext.Date.add(date, Ext.Date.DAY, -6);
                    }
                    nextmonday = Ext.Date.add(monday, Ext.Date.DAY, 7);
                    
                    starttime = monday;
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                    endtime = nextmonday;
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                    
                } else if (box.inputValue === "day") {
                    date.setHours(0);
                    date.setMinutes(0);
                    date.setSeconds(0);
                    
                    starttime = date;
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                    endtime = Ext.Date.add(date, Ext.Date.DAY, 1);
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                    
                } else if (box.inputValue === "hour") {
                    date.setMinutes(0);
                    date.setSeconds(0);
                    
                    starttime = date;
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                    endtime = Ext.Date.add(date, Ext.Date.HOUR, 1);
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                } else {
                    Ext.Msg.alert("Error", "Could not setup the dynamic time.");
                }
                me.getStarttimepicker().setValue(starttime);
                me.getEndtimepicker().setValue(endtime);
            }
        });
        
        var i = 0;
        Ext.each(yaxes, function(yaxis) {
            var device = devices[i].getValue(),
                xaxis = xaxes[i].getValue(),
                yaxis = yaxes[i].getValue(),
                yaxiscolorcombo = yaxescolorcombos[i].getValue(),
                yaxisfillcheck = yaxesfillchecks[i].checked,
                yaxisstatistics = yaxesstatistics[i].getValue();
            me.populateAxis(i, device, xaxis, yaxis, yaxiscolorcombo, yaxisfillcheck, yaxisstatistics, dbstarttime, dbendtime);
            i++;
        });
        
        //waiting for the first data arriving to add our baseline to it
        store.on("load", function() {
            var i = 0;
            Ext.each(basesstart, function(base) {
                var basestart = basesstart[i].getValue(),
                    baseend = basesend[i].getValue(),
                    basecolor = basescolors[i].getValue(),
                    basefill = basesfills[i].checked;
                
                    me.createBaseLine(i + 1, basestart, baseend, basefill, basecolor);
                    i++;
            });
        }, this, {single: true});
    },
    
    /**
     * creating baselines
     */
    createBaseLine: function(index, basestart, baseend, basefill, basecolor) {
        
        var me = this,
            chart = me.getChart(),
            store = chart.getStore(),
            yfield = "VALUEBASE" + index;
        
        if (!Ext.isEmpty(basestart) && basestart != "null") {
            var baseline = {
                type : 'line',
                name: 'baseline',
                axis : 'left',
                xField : 'TIMESTAMP',
                yField : yfield,
                showInLegend: false,
                highlight: true,
                fill: basefill,
                style: {
                    fill : basecolor,
                    'stroke-width': 3,
                    stroke: basecolor
                },
                tips : {
                    trackMouse : true,
                    width : 140,
                    height : 100,
                    renderer : function(storeItem, item) {
                        this.setTitle(' Value: : ' + storeItem.get(yfield) + 
                                '<br> Time: ' + storeItem.get('TIMESTAMP'));
                    }
                }
            };
            chart.series.add(baseline);
            
            store.first().set(yfield, basestart);
            store.last().set(yfield, baseend);
        }
    },
    
    /**
     * fill the axes with data
     */
    populateAxis: function(i, device, xaxis, yaxis, yaxiscolorcombo, yaxisfillcheck, yaxisstatistics, dbstarttime, dbendtime) {
        
        var me = this,
            chart = me.getChart(),
            store = chart.getStore(),
            proxy = store.getProxy(),
            generalization = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
            generalizationfactor = Ext.ComponentQuery.query('combobox[name=genfactor]')[0].getValue();
        
        if (i > 0) {
            var yseries = me.createSeries('VALUE' + (i + 1), yaxis, yaxisfillcheck, yaxiscolorcombo);
        } else {
            var yseries = me.createSeries('VALUE', yaxis, yaxisfillcheck, yaxiscolorcombo);
        }
        
        var url;
        if (!Ext.isDefined(yaxisstatistics) || yaxisstatistics === "none" || Ext.isEmpty(yaxisstatistics)) {
            url += '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
            url +=device + '+timerange+' + xaxis + '+' + yaxis;
            url += '&XHR=1'; 
        } else { //setup url to get statistics
            url += '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
            url +=device;
            
            if (yaxisstatistics.indexOf("hour") === 0) {
                url += '+hourstats+';
            } else if (yaxisstatistics.indexOf("day") === 0) {
                url += '+daystats+';
            } else if (yaxisstatistics.indexOf("week") === 0) {
                url += '+weekstats+';
            } else if (yaxisstatistics.indexOf("month") === 0) {
                url += '+monthstats+';
            } else if (yaxisstatistics.indexOf("year") === 0) {
                url += '+yearstats+';
            }
            
            url += xaxis + '+' + yaxis;
            url += '&XHR=1'; 
            
        }
        
        proxy.url = url;
        
        if (i > 0) { //make async ajax when not on first axis
            Ext.Ajax.request({
              method: 'GET',
              disableCaching: false,
              url: url,
              success: function(response){
                  
                  var json = Ext.decode(response.responseText);
                  
                  if (json.success && json.success === "false") {
                      Ext.Msg.alert("Error", "Error an adding Y-Axis number " + i + ", error was: <br>" + json.msg);
                  } else {
                      
                      //get the current value descriptor
                      var valuetext;
                      if (yaxisstatistics.indexOf("none") >= 0) {
                          valuetext = 'VALUE' + (i + 1);
                      } else if (yaxisstatistics.indexOf("sum") > 0) {
                          valuetext = 'SUM' + (i + 1);
                      } else if (yaxisstatistics.indexOf("average") > 0)  {
                          valuetext = 'AVG' + (i + 1);
                      } else if (yaxisstatistics.indexOf("min") > 0)  {
                          valuetext = 'MIN' + (i + 1);
                      }  else if (yaxisstatistics.indexOf("max") > 0)  {
                          valuetext = 'MAX' + (i + 1);
                      }  else if (yaxisstatistics.indexOf("count") > 0)  {
                          valuetext = 'COUNT' + (i + 1);
                      }
                      var timestamptext = 'TIMESTAMP' + (i + 1);
                      
                      //add records to store
                      for (var j = 0; j < json.data.length; j++) {
                          var item = Ext.create('FHEM.model.ChartModel');
                          
                          Ext.iterate(item.data, function(key, value) {
                              if (key.indexOf("TIMESTAMP") >= 0) {
                                  item.set(key, json.data[j].TIMESTAMP);
                              }
                          });
                          var valuestring = parseFloat(eval('json.data[j].' + valuetext.replace(/[0-9]/g, ''), 10));
                          item.set(valuetext, valuestring);
                          item.set(timestamptext, json.data[j].TIMESTAMP);
                          store.add(item);
                          
                          // recheck if our min and max values are still valid
                          if (me.minYValue > valuestring) {
                              me.minYValue = valuestring;
                          }
                          if (me.maxYValue < valuestring) {
                              me.maxYValue = valuestring;
                          }
                      }
                      
                      if (generalization.checked) {
                          me.generalizeChartData(generalizationfactor, i);
                      }
                      
                      delete chart.axes.get(0).maximum;
                      delete chart.axes.get(0).minimum;
                      
                      chart.axes.get(0).maximum = me.maxYValue;
                      chart.axes.get(0).minimum = me.minYValue;
                      chart.redraw();
                      
                  } 
              },
              failure: function() {
                  Ext.Msg.alert("Error", "Error an adding Y-Axis number " + i);
              }
          });
        } else {
            store.load();
        }
        
        var order = function(updatedstore) {
            
             if (generalization.checked) {
                me.generalizeChartData(generalizationfactor, i);
             }
             
             if (yaxisstatistics.indexOf("none") >= 0) {
                 if (i === 0) {
                     yseries.yField = 'VALUE';
                     if (me.maxYValue < updatedstore.max('VALUE')) {
                         me.maxYValue = updatedstore.max('VALUE');
                     }
                     if (me.minYValue > updatedstore.min('VALUE')) {
                         me.minYValue = updatedstore.min('VALUE');
                     }
                 } else {
                     yseries.yField = 'VALUE' + (i + 1);
                     if (me.maxYValue < updatedstore.max(yseries.yField)) {
                         me.maxYValue = updatedstore.max(yseries.yField);
                     }
                 }
             } else if (yaxisstatistics.indexOf("sum") > 0) {
                 if (i === 0) {
                     yseries.yField = 'SUM';
                     yseries.tips.renderer = me.setSeriesRenderer('SUM');
                     if (me.maxYValue < updatedstore.max('SUM')) {
                         me.maxYValue = updatedstore.max('SUM');
                     }
                     if (me.minYValue > updatedstore.min('SUM')) {
                         me.minYValue = updatedstore.min('SUM');
                     }
                 } else {
                     yseries.yField = 'SUM' + (i + 1);
                     yseries.tips.renderer = me.setSeriesRenderer('SUM' + (i + 1));
                 }
                 chart.axes.get(0).setTitle("SUM " + yaxis);
             } else if (yaxisstatistics.indexOf("average") > 0)  {
                 if (i === 0) {
                     yseries.yField = 'AVG';
                     yseries.tips.renderer = me.setSeriesRenderer('AVG');
                     if (me.maxYValue < updatedstore.max('AVG')) {
                         me.maxYValue = updatedstore.max('AVG');
                     }
                     if (me.minYValue > updatedstore.min('AVG')) {
                         me.minYValue = updatedstore.min('AVG');
                     }
                 } else {
                     yseries.yField = 'AVG' + (i + 1);
                     yseries.tips.renderer = me.setSeriesRenderer('AVG' + (i + 1));
                 }
                 chart.axes.get(0).setTitle("AVG " + yaxis);
             } else if (yaxisstatistics.indexOf("min") > 0)  {
                 if (i === 0) {
                     yseries.yField = 'MIN';
                     yseries.tips.renderer = me.setSeriesRenderer('MIN');
                     if (me.maxYValue < updatedstore.max('MIN')) {
                         me.maxYValue = updatedstore.max('MIN');
                     }
                     if (me.minYValue > updatedstore.min('MIN')) {
                         me.minYValue = updatedstore.min('MIN');
                     }
                 } else {
                     yseries.yField = 'MIN' + (i + 1);
                     yseries.tips.renderer = me.setSeriesRenderer('MIN' + (i + 1));
                 }
                 chart.axes.get(0).setTitle("MIN " + yaxis);
             }  else if (yaxisstatistics.indexOf("max") > 0)  {
                 if (i === 0) {
                     yseries.yField = 'MAX';
                     yseries.tips.renderer = me.setSeriesRenderer('MAX');
                     if (me.maxYValue < updatedstore.max('MAX')) {
                         me.maxYValue = updatedstore.max('MAX');
                     }
                     if (me.minYValue > updatedstore.min('MAX')) {
                         me.minYValue = updatedstore.min('MAX');
                     }
                 } else {
                     yseries.yField = 'MAX' + (i + 1);
                     yseries.tips.renderer = me.setSeriesRenderer('MAX' + (i + 1));
                 }
                 chart.axes.get(0).setTitle("MAX " + yaxis);
             }  else if (yaxisstatistics.indexOf("count") > 0)  {
                 if (i === 0) {
                     yseries.yField = 'COUNT';
                     yseries.tips.renderer = me.setSeriesRenderer('COUNT');
                     if (me.maxYValue < updatedstore.max('COUNT')) {
                         me.maxYValue = updatedstore.max('COUNT');
                     }
                     if (me.minYValue > updatedstore.min('COUNT')) {
                         me.minYValue = updatedstore.min('COUNT');
                     }
                 } else {
                     yseries.yField = 'COUNT' + (i + 1);
                     yseries.tips.renderer = me.setSeriesRenderer('COUNT' + (i + 1));
                 }
                 chart.axes.get(0).setTitle("COUNT " + yaxis);
             }
             
             //remove the old max values of y axis to get a dynamic range
             delete chart.axes.get(0).maximum;
             delete chart.axes.get(0).minimum;
             
             chart.axes.get(0).maximum = me.maxYValue;
             if (me.minYValue === 9999999) {
                 chart.axes.get(0).minimum = 0;
             } else {
                 chart.axes.get(0).minimum = me.minYValue;
             }
             
             chart.series.add(yseries);
             
             // set the x axis range dependent on user given timerange
             var starttime = me.getStarttimepicker().getValue(),
                 endtime = me.getEndtimepicker().getValue();
             chart.axes.get(1).fromDate = starttime;
             chart.axes.get(1).toDate = endtime;
             chart.axes.get(1).processView();
             chart.redraw();
             
             me.getChart().setLoading(false);
            
        };
        store.on("load", order, this, {single: true});
    },
    
    /**
     * create a single series for the chart
     */
    createSeries: function(yfield, title, fill, color) {
        var series = {
                type : 'line',
                axis : 'left',
                xField : 'TIMESTAMP',
                yField : yfield,
                title: title,
                showInLegend: true,
                smooth: 0,
                highlight: true,
                fill: fill,
                style: {
                    fill: color,
                    stroke: color
                },
                markerConfig: {
                    type: 'circle',
                    size: 3,
                    radius: 3,
                    stroke: color
                },
                tips : {
                    trackMouse : true,
                    mouseOffset: [1,1],
                    showDelay: 1000,
                    width : 280,
                    height : 50,
                    renderer : function(storeItem, item) {
                        this.setTitle(' Value: : ' + storeItem.get(yfield) + 
                                '<br> Time: ' + storeItem.get('TIMESTAMP'));
                    }
                }
            };
        return series;
    },
    
    /**
     * Setup the renderer for displaying values in chart with mouse hover
     */
    setSeriesRenderer: function(value) {
        
        var renderer = function (storeItem, item) {
            this.setTitle(' ' + value + ' : ' + storeItem.get(value) + 
                    '<br> Time: ' + storeItem.get('TIMESTAMP'));
        };
        
        return renderer;
    },
    
    /**
     * 
     */
    generalizeChartData: function(generalizationfactor, index) {

        var store = this.getChart().getStore();
        
        this.factorpositive = 1 + (generalizationfactor / 100),
            this.factornegative = 1 - (generalizationfactor / 100),
            this.lastValue = null,
            this.lastItem = null,
            this.recsToRemove = [];
        
        Ext.each(store.data.items, function(item) {
            
                var value;
                if (index === 0) {
                    value = item.get('VALUE');
                } else {
                    value = item.get('VALUE' + index);
                }
                var one = this.lastValue / 100;
                var diff = value / one / 100;
                if (diff > this.factorpositive || diff < this.factornegative) {
                    if (this.lastItem) {
                        if (index === 0) {
                            this.lastItem.set('VALUE', this.lastValue);
                        } else {
                            this.lastItem.set('VALUE' + index, this.lastValue);
                        }
                    }
                    this.lastValue = value;
                    this.lastItem = item;
                } else {
                    //keep last record
                    if (store.last() !== item) {
                        if (index === 0) {
                            item.set('VALUE', '');
                        } else {
                            item.set('VALUE' + index, '');
                        }
                    }
                    this.lastValue = value;
                    this.lastItem = item;
                }
        }, this);
        
    },
    
    /**
     * reset the form fields e.g. when loading a new chart
     */
    resetFormFields: function() {
        
        var fieldset =  this.getChartformpanel().down('fieldset[name=axesfieldset]');
        fieldset.removeAll();
        this.getLinechartpanel().createNewYAxis();
        
        Ext.ComponentQuery.query('radiofield[name=rb]')[0].setValue(true);
        Ext.ComponentQuery.query('datefield[name=starttimepicker]')[0].reset();
        Ext.ComponentQuery.query('datefield[name=endtimepicker]')[0].reset();
        Ext.ComponentQuery.query('radiofield[name=generalization]')[1].setValue(true);
    },
    
    /**
     * jump one step back / forward in timerange
     */
    stepchange: function(btn) {
        var me = this;
        
        //reset y-axis max
        me.maxYValue = 0;
        me.minYValue = 9999999;
        
        var starttime = me.getStarttimepicker().getValue(),
            dbstarttime = Ext.Date.format(starttime, 'Y-m-d H:i:s'),
            endtime = me.getEndtimepicker().getValue(),
            dbendtime = Ext.Date.format(endtime, 'Y-m-d H:i:s');
        
        if(!Ext.isEmpty(starttime) && !Ext.isEmpty(endtime)) {
            var timediff = Ext.Date.getElapsed(starttime, endtime);
            if(btn.name === "stepback") {
                me.getEndtimepicker().setValue(starttime);
                var newstarttime = Ext.Date.add(starttime, Ext.Date.MILLI, -timediff);
                me.getStarttimepicker().setValue(newstarttime);
                me.requestChartData(true);
            } else if (btn.name === "stepforward") {
                me.getStarttimepicker().setValue(endtime);
                var newendtime = Ext.Date.add(endtime, Ext.Date.MILLI, timediff);
                me.getEndtimepicker().setValue(newendtime);
                me.requestChartData(true);
            }
        }
            
    },
    
    
    /**
     * save the current chart to database
     */
    saveChartData: function() {
        
        var me = this;
        Ext.Msg.prompt("Select a name", "Enter a name to save the Chart", function(action, savename) {
            if (action === "ok" && !Ext.isEmpty(savename)) {
                //replacing spaces in name
                savename = savename.replace(/ /g, "_");
                //replacing + in name
                savename = savename.replace(/\+/g, "_");
                
                //getting the necessary values
                var devices = Ext.ComponentQuery.query('combobox[name=devicecombo]');
                var xaxes = Ext.ComponentQuery.query('combobox[name=xaxiscombo]');
                var yaxes = Ext.ComponentQuery.query('combobox[name=yaxiscombo]');
                var yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=yaxiscolorcombo]');
                var yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=yaxisfillcheck]');
                var yaxesstatistics = Ext.ComponentQuery.query('combobox[name=yaxisstatisticscombo]');
                
                var basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]');
                var basesend = Ext.ComponentQuery.query('numberfield[name=baseend]');
                var basescolors = Ext.ComponentQuery.query('combobox[name=baselinecolorcombo]');
                var basesfills = Ext.ComponentQuery.query('checkboxfield[name=baselinefillcheck]');
                    
                var starttime = me.getStarttimepicker().getValue(),
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
                    endtime = me.getEndtimepicker().getValue(),
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
                    dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0],
                    generalization = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
                    generalizationfactor = Ext.ComponentQuery.query('combobox[name=genfactor]')[0].getValue(),
                    chart = me.getChart(),
                    store = chart.getStore();
                
                //setting the start / endtime parameter in the chartconfig to the string of the radiofield, gets parsed on load
                if (this.getStarttimepicker().isDisabled()) {
                    dynamicradio.eachBox(function(box, idx) {
                        if (box.checked) {
                            dbstarttime = box.inputValue;
                            dbendtime = box.inputValue;
                        }
                    });
                }
                
                var jsonConfig = '{';
                var i = 0;
                Ext.each(devices, function(dev) {
                    
                    var device = dev.getValue(),
                        xaxis = xaxes[i].getValue(),
                        yaxis = yaxes[i].getValue(),
                        yaxiscolorcombo = yaxescolorcombos[i].getDisplayValue(),
                        yaxisfillcheck = yaxesfillchecks[i].checked,
                        yaxisstatistics = yaxesstatistics[i].getValue();
                    
                    if (i === 0) {
                        jsonConfig += '"x":"' + xaxis + '","y":"' + yaxis + '","device":"' + device + '",';
                        jsonConfig += '"yaxiscolorcombo":"' + yaxiscolorcombo + '","yaxisfillcheck":"' + yaxisfillcheck + '",';
                        if (yaxisstatistics !== "none") {
                            jsonConfig += '"yaxisstatistics":"' + yaxisstatistics + '",';
                        }
                    } else {
                        var axisname = "y" + (i + 1) + "axis",
                            devicename = "y" + (i + 1) + "device",
                            colorname = "y" + (i + 1) + "axiscolorcombo",
                            fillname = "y" + (i + 1) + "axisfillcheck",
                            statsname = "y" + (i + 1) + "axisstatistics";
                        
                        jsonConfig += '"' + axisname + '":"' + yaxis + '","' + devicename + '":"' + device + '",';
                        jsonConfig += '"' + colorname + '":"' + yaxiscolorcombo + '","' + fillname + '":"' + yaxisfillcheck + '",';
                        if (yaxisstatistics !== "none") {
                            jsonConfig += '"' + statsname + '":"' + yaxisstatistics + '",';
                        }
                    }
                    i++;
                });
                
                if(generalization.checked) {
                    jsonConfig += '"generalization":"true",';
                    jsonConfig += '"generalizationfactor":"' + generalizationfactor + '",';
                }
                
                var i = 0;
                Ext.each(basesstart, function(base) {
                    var basestart = basesstart[i].getValue(),
                        baseend = basesend[i].getValue(),
                        basecolor = basescolors[i].getDisplayValue(),
                        basefill = basesfills[i].checked;
                    
                    i++;
                    jsonConfig += '"base' + i + 'start":"' + basestart + '","base' + i + 'end":"' + baseend + '",';
                    jsonConfig += '"base' + i + 'color":"' + basecolor + '","base' + i + 'fill":"' + basefill + '",';
                });
                
                jsonConfig += '"starttime":"' + dbstarttime + '","endtime":"' + dbendtime + '"}';
            
                var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                    url +=devices[0].getValue() + '+savechart+""+""+' + savename + '+' + jsonConfig + '&XHR=1'; 
                
                chart.setLoading(true);
                
                Ext.Ajax.request({
                    method: 'POST',
                    disableCaching: false,
                    url: url,
                    success: function(response){
                        chart.setLoading(false);
                        var json = Ext.decode(response.responseText);
                        if (json.success === "true" || json.data && json.data.length === 0) {
                            me.getSavedchartsgrid().getStore().load();
                            Ext.Msg.alert("Success", "Chart successfully saved!");
                        } else if (json.msg) {
                            Ext.Msg.alert("Error", "The Chart could not be saved, error Message is:<br><br>" + json.msg);
                        } else {
                            Ext.Msg.alert("Error", "The Chart could not be saved!");
                        }
                    },
                    failure: function() {
                        chart.setLoading(false);
                        if (json && json.msg) {
                            Ext.Msg.alert("Error", "The Chart could not be saved, error Message is:<br><br>" + json.msg);
                        } else {
                            Ext.Msg.alert("Error", "The Chart could not be saved!");
                        }
                    }
                });
            }
        }, this);
        
    },
    
    /**
     * loading saved chart data and trigger the load of the chart
     */
    loadsavedchart: function(grid, td, cellIndex, record) {

        var me = this;
        
        if (cellIndex === 0) {
            var name = record.get('NAME'),
                chartdata = record.get('VALUE');
            
            if (typeof chartdata !== "object") {
                try {
                    chartdata = Ext.decode(chartdata);
                } catch (e) {
                    Ext.Msg.alert("Error", "The Chart could not be loaded! RawChartdata was: <br>" + chartdata);
                }
                
            }
            
            //cleanup the form before loading
            this.resetFormFields();
            
            if (chartdata && !Ext.isEmpty(chartdata)) {
                
                //reset y-axis max
                me.maxYValue = 0;
                me.minYValue = 9999999;
                
                //count axes
                var axescount = 0;
                Ext.iterate(chartdata, function(key, value) {
                    if (key.indexOf("device") >= 0 && value != "null") {
                        axescount++;
                    }
                });
                
                var yaxeslength = Ext.ComponentQuery.query('combobox[name=yaxiscombo]').length;
                while (yaxeslength < axescount) {
                    Ext.ComponentQuery.query('linechartpanel')[0].createNewYAxis();
                    yaxeslength++;
                }
                
                var xaxes = Ext.ComponentQuery.query('combobox[name=xaxiscombo]');
                var devices = Ext.ComponentQuery.query('combobox[name=devicecombo]');
                var yaxes = Ext.ComponentQuery.query('combobox[name=yaxiscombo]');
                var yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=yaxiscolorcombo]');
                var yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=yaxisfillcheck]');
                var yaxesstatistics = Ext.ComponentQuery.query('combobox[name=yaxisstatisticscombo]');
                
                var i = 0;
                Ext.each(yaxes, function(yaxis) {
                    if (i === 0) {
                        devices[i].setValue(chartdata.device);
                        yaxes[i].getStore().getProxy().url = url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + chartdata.device + '+getreadings&XHR=1';
                        yaxes[i].setDisabled(false);
                        yaxes[i].setValue(chartdata.y);
                        xaxes[i].setValue(chartdata.x);
                        yaxescolorcombos[i].setValue(chartdata.yaxiscolorcombo);
                        yaxesfillchecks[i].setValue(chartdata.yaxisfillcheck);
                        
                        if (chartdata.yaxisstatistics && chartdata.yaxisstatistics !== "") {
                            yaxesstatistics[i].setValue(chartdata.yaxisstatistics);
                        } else {
                            yaxesstatistics[i].setValue("none");
                        }
                        i++;
                    } else {
                        var axisdevice = "y" + (i + 1) + "device",
                            axisname = "y" + (i + 1) + "axis",
                            axiscolorcombo = axisname + "colorcombo",
                            axisfillcheck = axisname + "fillcheck",
                            axisstatistics = axisname + "statistics";
                            
                        eval('devices[i].setValue(chartdata.' + axisdevice + ')');
                        yaxes[i].getStore().getProxy().url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + eval('chartdata.' + axisdevice) + '+getreadings&XHR=1';
                        yaxes[i].setDisabled(false);
                        xaxes[i].setValue(chartdata.x);
                        eval('yaxes[i].setValue(chartdata.' + axisname + ')');
                        eval('yaxescolorcombos[i].setValue(chartdata.' + axiscolorcombo + ')');
                        eval('yaxesfillchecks[i].setValue(chartdata.' + axisfillcheck + ')');
                        
                        if (eval('chartdata.' + axisstatistics) && eval('chartdata.' + axisstatistics) !== "") {
                            eval('yaxesstatistics[i].setValue(chartdata.' + axisstatistics + ')');
                        } else {
                            yaxesstatistics[i].setValue("none");
                        }
                        i++;
                    }
                });

                //handling baselines
                var basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]'),
                    baselinecount = 0,
                    i = 1;
                
                Ext.iterate(chartdata, function(key, value) {
                    if (key.indexOf("base") >= 0 && key.indexOf("start") >= 0 && value != "null") {
                        baselinecount++;
                    }
                });
                
                var renderedbaselines = basesstart.length;
                while (renderedbaselines < baselinecount) {
                    Ext.ComponentQuery.query('linechartpanel')[0].createNewBaseLineFields();
                    renderedbaselines++;
                }
                
                var i = 0,
                    j = 1;
                    basesstart = Ext.ComponentQuery.query('numberfield[name=basestart]'),
                    basesend = Ext.ComponentQuery.query('numberfield[name=baseend]'),
                    basescolors = Ext.ComponentQuery.query('combobox[name=baselinecolorcombo]'),
                    basesfills = Ext.ComponentQuery.query('checkboxfield[name=baselinefillcheck]');
                    
                Ext.each(basesstart, function(base) {
                    var start = parseFloat(eval('chartdata.base' + j  + 'start'), 10);
                    var end = parseFloat(eval('chartdata.base' + j  + 'end'), 10);
                    
                    basesstart[i].setValue(start);
                    basesend[i].setValue(end);
                    basescolors[i].setValue(eval('chartdata.base' + j  + 'color'));
                    basesfills[i].setValue(eval('chartdata.base' + j  + 'fill'));
                    i++;
                    j++;
                });
                
                //convert time
                var dynamicradio = Ext.ComponentQuery.query('radiogroup[name=dynamictime]')[0],
                    st = chartdata.starttime;
                if (st === "year" || st === "month" || st === "week" || st === "day" || st === "hour") {
                    dynamicradio.eachBox(function(box, idx) {
                        if (box.inputValue === st) {
                            box.setValue(true);
                        }
                    });
                } else {
                    var start = chartdata.starttime.replace("_", " "),
                        end = chartdata.endtime.replace("_", " ");
                    this.getStarttimepicker().setValue(start);
                    this.getEndtimepicker().setValue(end);
                }
                
                var genbox = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
                    genfaccombo = Ext.ComponentQuery.query('combobox[name=genfactor]')[0];
                
                if (chartdata.generalization && chartdata.generalization === "true") {
                    genbox.setValue(true);
                    genfaccombo.setValue(chartdata.generalizationfactor);
                } else {
                    genfaccombo.setValue('30');
                    genbox.setValue(false);
                }
                
                this.requestChartData();
                this.getLinechartpanel().setTitle(name);
            } else {
                Ext.Msg.alert("Error", "The Chart could not be loaded! RawChartdata was: <br>" + rawchartdata);
            }
            
        }
    },
    
    /**
     * Delete a chart by its id from the database
     */
    deletechart: function(grid, td, cellIndex, par, evt, record) {
        
        var me = this,
            chartid = record.get('ID'),
            chart = this.getChart();
        
        if (Ext.isDefined(chartid) && chartid !== "") {
            
            Ext.create('Ext.window.Window', {
                width: 250,
                layout: 'fit',
                title:'Delete?',
                modal: true,
                items: [
                    {
                        xtype: 'displayfield',
                        value: 'Do you really want to delete this chart?'
                    }
                ],  
                buttons: [{ 
                    text: "Ok", 
                    handler: function(btn){ 
                        
                        var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+deletechart+""+""+' + chartid + '&XHR=1'; 
                    
                        chart.setLoading(true);
                        
                        Ext.Ajax.request({
                            method: 'GET',
                            disableCaching: false,
                            url: url,
                            success: function(response){
                                chart.setLoading(false);
                                var json = Ext.decode(response.responseText);
                                if (json && json.success === "true" || json.data && json.data.length === 0) {
                                    me.getSavedchartsgrid().getStore().load();
                                    Ext.Msg.alert("Success", "Chart successfully deleted!");
                                } else if (json && json.msg) {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted, error Message is:<br><br>" + json.msg);
                                } else {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted!");
                                }
                                btn.up().up().destroy();
                            },
                            failure: function() {
                                chart.setLoading(false);
                                if (json && json.msg) {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted, error Message is:<br><br>" + json.msg);
                                } else {
                                    Ext.Msg.alert("Error", "The Chart could not be deleted!");
                                }
                                btn.up().up().destroy();
                            }
                        });
                    }
                },
                {
                    text: "Cancel",
                    handler: function(btn){
                        btn.up().up().destroy();
                    }
                }]
            }).show();
        } else {
            Ext.Msg.alert("Error", "The Chart could not be deleted, no record id has been found");
        }
            
    } 

});