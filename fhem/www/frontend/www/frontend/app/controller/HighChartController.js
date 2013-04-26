/**
 * Controller handling the charts
 */
Ext.define('FHEM.controller.HighChartController', {
    extend: 'Ext.app.Controller',

    refs: [
           {
               selector: 'panel[name=highchartformpanel]',
               ref: 'chartformpanel' //this.getChartformpanel()
           },
           {
               selector: 'datefield[name=highchartstarttimepicker]',
               ref: 'starttimepicker' //this.getStarttimepicker()
           },
           {
               selector: 'datefield[name=highchartendtimepicker]',
               ref: 'endtimepicker' //this.getEndtimepicker()
           },
           {
               selector: 'button[name=highchartrequestchartdata]',
               ref: 'requestchartdatabtn' //this.getRequestchartdatabtn()
           },
           {
               selector: 'button[name=highchartsavechartdata]',
               ref: 'savechartdatabtn' //this.getSavechartdatabtn()
           },
           {
               selector: 'chart',
               ref: 'chart' //this.getChart()
           },
           {
               selector: 'chartformpanel',
               ref: 'panel[name=highchartchartformpanel]' //this.getChartformpanel()
           },
           {
               selector: 'highchartspanel',
               ref: 'highchartpanel' //this.getHighchartpanel()
           }
//           {
//               selector: 'linechartpanel toolbar',
//               ref: 'linecharttoolbar' //this.getLinecharttoolbar()
//           },
//           {
//               selector: 'grid[name=highchartsavedchartsgrid]',
//               ref: 'savedchartsgrid' //this.getSavedchartsgrid()
//           },
//           {
//               selector: 'grid[name=highchartchartdata]',
//               ref: 'chartdatagrid' //this.getChartdatagrid()
//           }
           
    ],

    /**
     * init function to register listeners
     */
    init: function() {
        this.control({
            'button[name=highchartrequestchartdata]': {
                click: this.requestChartData
            },
//            'button[name=savechartdata]': {
//                click: this.saveChartData
//            },
//            'button[name=stepback]': {
//                click: this.stepchange
//            },
//            'button[name=stepforward]': {
//                click: this.stepchange
//            },
            'button[name=highchartresetchartform]': {
                click: this.resetFormFields
            },
//            'grid[name=savedchartsgrid]': {
//                cellclick: this.loadsavedchart
//            },
//            'actioncolumn[name=savedchartsactioncolumn]': {
//                click: this.deletechart
//            },
//            'grid[name=chartdata]': {
//                itemclick: this.highlightRecordInChart
//            },
            'panel[name=highchartchartpanel]': {
                collapse: this.resizeChart,
                expand: this.resizeChart
            },
            'panel[name=highchartformpanel]': {
                collapse: this.resizeChart,
                expand: this.resizeChart
            }
//            'panel[name=chartgridpanel]': {
//                collapse: this.resizeChart,
//                expand: this.resizeChart
//            }
        });
        
    },
    
    /**
     * Triggers a request to FHEM Module to get the data from Database
     */
    requestChartData: function(stepchangecalled) {
        
        var me = this;
        
        //show loadmask
        me.getHighchartpanel().setLoading(true);
        
        // fit chart
        me.resizeChart();
        
        //cleanup
        hc = Ext.ComponentQuery.query('highchart')[0];
        hc.store.removeAll();
        hc.refresh();
        
        //getting the necessary values
        var devices = Ext.ComponentQuery.query('combobox[name=highchartdevicecombo]'),
            yaxes = Ext.ComponentQuery.query('combobox[name=highchartyaxiscombo]'),
            yaxescolorcombos = Ext.ComponentQuery.query('combobox[name=highchartyaxiscolorcombo]'),
            yaxesfillchecks = Ext.ComponentQuery.query('checkbox[name=highchartyaxisfillcheck]'),
            yaxesstepcheck = Ext.ComponentQuery.query('checkbox[name=highchartyaxisstepcheck]'),
            yaxesstatistics = Ext.ComponentQuery.query('combobox[name=highchartyaxisstatisticscombo]'),
            axissideradio = Ext.ComponentQuery.query('radiogroup[name=highchartaxisside]');
        
        var starttime = me.getStarttimepicker().getValue(),
            dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
            endtime = me.getEndtimepicker().getValue(),
            dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
            dynamicradio = Ext.ComponentQuery.query('radiogroup[name=highchartdynamictime]')[0],
            chartpanel = me.getHighchartpanel(),
            chart = me.getChart();
        
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
        Ext.each(yaxes, function(y) {
            var device = devices[i].getValue(),
                yaxis = yaxes[i].getValue(),
                yaxiscolorcombo = yaxescolorcombos[i].getValue(),
                yaxisfillcheck = yaxesfillchecks[i].checked,
                yaxisstepcheck = yaxesstepcheck[i].checked,
                yaxisstatistics = yaxesstatistics[i].getValue(),
                axisside = axissideradio[i].getChecked()[0].getSubmitValue();
            if(yaxis === "" || yaxis === null) {
                yaxis = yaxes[i].getRawValue();
            }
            
            me.populateAxis(i, yaxes.length, device, yaxis, yaxiscolorcombo, yaxisfillcheck, yaxisstepcheck, axisside, yaxisstatistics, dbstarttime, dbendtime);
            i++;
        });
        
    },
    
    /**
     * resize the chart to fit the centerpanel
     */
    resizeChart: function() {
        
        
        var lcp = Ext.ComponentQuery.query('highchartspanel')[0];
        var lcv = Ext.ComponentQuery.query('panel[name=highchartpanel]')[0];
        var cfp = Ext.ComponentQuery.query('form[name=highchartformpanel]')[0];
        
        if (lcp && lcv && cfp) {
            var chartheight = lcp.getHeight() - cfp.getHeight() -55;
            var chartwidth = lcp.getWidth() - 25;
            lcv.setHeight(chartheight);
            lcv.setWidth(chartwidth);
            lcv.down('highchart').setHeight(chartheight);
            lcv.down('highchart').setWidth(chartwidth);
            lcv.down('highchart').render();
        }
        
    },
    
    /**
     * fill the axes with data
     */
    populateAxis: function(i, axeslength, device, yaxis, yaxiscolorcombo, yaxisfillcheck, yaxisstepcheck, axisside, yaxisstatistics, dbstarttime, dbendtime) {
        
        var me = this,
            yseries,
            generalization = Ext.ComponentQuery.query('radio[boxLabel=active]')[0],
            generalizationfactor = Ext.ComponentQuery.query('combobox[name=highchartgenfactor]')[0].getValue();
        
        var url;
        if (!Ext.isDefined(yaxisstatistics) || yaxisstatistics === "none" || Ext.isEmpty(yaxisstatistics)) {
            url += '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
            url +=device + '+timerange+' + "TIMESTAMP" + '+' + yaxis;
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
            
            url += 'TIMESTAMP' + '+' + yaxis;
            url += '&XHR=1'; 
            
        }
        
        Ext.Ajax.request({
          method: 'GET',
          async: false,
          disableCaching: false,
          url: url,
          success: function(response){
              
              var json = Ext.decode(response.responseText);
              
              if (json.success && json.success === "false") {
                  Ext.Msg.alert("Error", "Error an adding Y-Axis number " + i + ", error was: <br>" + json.msg);
              } else {
                  hc = Ext.ComponentQuery.query('highchart')[0];
                  hc.store.add(json.data);
                  
              } 
          },
          failure: function() {
              Ext.Msg.alert("Error", "Error an adding Y-Axis number " + i);
          }
        });
      
        //check if we have added the last dataset
        if ((i + 1) === axeslength) {
            me.getHighchartpanel().setLoading(false);
        }
        
    },
    
    /**
     * reset the form fields e.g. when loading a new chart
     */
    resetFormFields: function() {
        
        var fieldset =  this.getChartformpanel().down('fieldset[name=highchartaxesfieldset]');
        fieldset.removeAll();
        this.getHighchartpanel().createNewYAxis();
        
        Ext.ComponentQuery.query('radiofield[name=highchartrb]')[0].setValue(true);
        Ext.ComponentQuery.query('datefield[name=highchartstarttimepicker]')[0].reset();
        Ext.ComponentQuery.query('datefield[name=highchartendtimepicker]')[0].reset();
        Ext.ComponentQuery.query('radiofield[name=highchartgeneralization]')[1].setValue(true);
    }
  
});