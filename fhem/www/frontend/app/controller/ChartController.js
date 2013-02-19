/**
 * Controller handling the charts
 */
Ext.define('FHEM.controller.ChartController', {
    extend: 'Ext.app.Controller',

    refs: [
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
               selector: 'combobox[name=devicecombo]',
               ref: 'devicecombo' //this.getDevicecombo()
           },
           {
               selector: 'combobox[name=xaxiscombo]',
               ref: 'xaxiscombo' //this.getXaxiscombo()
           },
           {
               selector: 'combobox[name=yaxiscombo]',
               ref: 'yaxiscombo' //this.getYaxiscombo()
           },
           {
               selector: 'linechartview',
               ref: 'linechartview' //this.getLinechartview()
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
            'combobox[name=devicecombo]': {
                select: this.deviceSelected
            },
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
            'linechartview': {
                afterrender: this.enableZoomInChart
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
     * loads data for the readingsstore after device has been selected
     */
    deviceSelected: function(combo){
        
        var device = combo.getValue(),
            store = this.getYaxiscombo().getStore(),
            proxy = store.getProxy();
        
        if (proxy) {
            proxy.url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+' + device + '+getreadings&XHR=1';
            store.load();
        }
        
    },
    
    /**
     * Triggers a request to FHEM Module to get the data from Database
     */
    requestChartData: function() {
        
        var me = this;
        //getting the necessary values
        var device = me.getDevicecombo().getValue(),
            xaxis = me.getXaxiscombo().getValue(),
            yaxis = me.getYaxiscombo().getValue(),
            starttime = me.getStarttimepicker().getValue(),
            dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
            endtime = me.getEndtimepicker().getValue(),
            dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
            view = me.getLinechartview(),
            store = me.getLinechartview().getStore(),
            proxy = store.getProxy();
        
        //register store listeners
        store.on("beforeload", function() {
            me.getLinechartview().setLoading(true);
        });
        store.on("load", function() {
            me.getLinechartview().setLoading(false);
        });
        
        if (proxy) {
            var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                url +=device + '+timerange+' + xaxis + '+' + yaxis + '&XHR=1'; 
            proxy.url = url;
            store.load();
        }
        
        //remove the old max values of y axis to get a dynamic range
        delete view.axes.get(0).maximum;
        
        view.axes.get(0).setTitle(yaxis);
        view.axes.get(1).setTitle(xaxis);
        
        // set the x axis range dependent on user given timerange
        view.axes.get(1).fromDate = starttime;
        view.axes.get(1).toDate = endtime;
        view.axes.get(1).processView();
        
        me.getLinechartview().redraw();
        
    },
    
    /**
     * perpare zooming
     */
    enableZoomInChart: function() {
        var view = this.getLinechartview();
        view.mon(view.getEl(), 'mousewheel', this.zoomInChart, this);
    },
    
    /**
     * zoom in chart with mousewheel
     */
    zoomInChart: function(e) {
        var wheeldelta = e.getWheelDelta(),
            view = this.getLinechartview(),
            currentmax = view.axes.get(0).prevMax,
            newmax;
        
        if (wheeldelta == 1) { //zoomin case:
            if (currentmax > 1) {
                newmax = currentmax - 1;
                view.axes.get(0).maximum = newmax;
                view.redraw();
            }
        } else if (wheeldelta == -1) { //zoomout case
            newmax = currentmax + 1;
            view.axes.get(0).maximum = newmax;
            view.redraw();
        }
        
    },
    
    /**
     * jump one step back / forward in timerange
     */
    stepchange: function(btn) {
        var me = this;
        
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
                me.requestChartData();
                
            } else if (btn.name === "stepforward") {
                me.getStarttimepicker().setValue(endtime);
                var newendtime = Ext.Date.add(endtime, Ext.Date.MILLI, timediff);
                me.getEndtimepicker().setValue(newendtime);
                me.requestChartData();
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
                
                //getting all devices, check for same name
                var store = me.getSavedchartsgrid().getStore(),
                storednames = [];
            
                store.each(function(record){
                    var name = record.get('VALUE');
                    storednames.push(name);
                });
                
                if (Ext.Array.contains(storednames, savename)) {
                    Ext.Msg.alert("Error", "There already is a chart with the name: " + savename);
                } else {
                    
                    var device = this.getDevicecombo().getValue(),
                        xaxis = this.getXaxiscombo().getValue(),
                        yaxis = this.getYaxiscombo().getValue(),
                        starttime = this.getStarttimepicker().getValue(),
                        dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
                        endtime = this.getEndtimepicker().getValue(),
                        dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
                        view = this.getLinechartview();
                
                    var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                        url +=device + '+savechart+' + xaxis + '+' + yaxis + '+' + savename + '&XHR=1'; 
                    
                    view.setLoading(true);
                    
                    Ext.Ajax.request({
                        method: 'GET',
                        disableCaching: false,
                        url: url,
                        success: function(response){
                            view.setLoading(false);
                            var json = Ext.decode(response.responseText);
                            if (json.success === true) {
                                me.getSavedchartsgrid().getStore().load();
                                Ext.Msg.alert("Success", "Chart successfully saved!");
                            } else if (json.msg) {
                                Ext.Msg.alert("Error", "The Chart could not be saved, error Message is:<br><br>" + json.msg);
                            } else {
                                Ext.Msg.alert("Error", "The Chart could not be saved!");
                            }
                        },
                        failure: function() {
                            view.setLoading(false);
                            if (json && json.msg) {
                                Ext.Msg.alert("Error", "The Chart could not be saved, error Message is:<br><br>" + json.msg);
                            } else {
                                Ext.Msg.alert("Error", "The Chart could not be saved!");
                            }
                        }
                    });
                }
            }
        }, this);
        
    },
    
    /**
     * loading saved chart data and trigger the load of the chart
     */
    loadsavedchart: function(grid, td, cellIndex, record) {
        
        if (cellIndex === 0) {
            var name = record.get('VALUE');
            var chartdata = Ext.decode(record.get('EVENT'))[0];
            
            if (chartdata && !Ext.isEmpty(chartdata)) {
                this.getDevicecombo().setValue(chartdata.device);
                // load storedata for readings after device has been selected
                this.deviceSelected(this.getDevicecombo());
                
                this.getXaxiscombo().setValue(chartdata.x);
                this.getYaxiscombo().setValue(chartdata.y);
                this.getStarttimepicker().setValue(chartdata.starttime);
                this.getEndtimepicker().setValue(chartdata.endtime);
                
                this.requestChartData();
                this.getLinechartpanel().setTitle(name);
            } else {
                Ext.Msg.alert("Error", "The Chart could not be loaded!");
            }
            
        }
    },
    
    /**
     * Delete a chart by its name from the database
     */
    deletechart: function(grid, td, cellIndex, par, evt, record) {
        
        var me = this,
            chartname = record.get('VALUE'),
            view = this.getLinechartview();
        
        if (Ext.isDefined(chartname) && chartname !== "") {
            
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
                        
                        var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+deletechart+""+""+' + chartname + '&XHR=1'; 
                    
                        view.setLoading(true);
                        
                        Ext.Ajax.request({
                            method: 'GET',
                            disableCaching: false,
                            url: url,
                            success: function(response){
                                view.setLoading(false);
                                var json = Ext.decode(response.responseText);
                                if (json && json.success === true) {
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
                                view.setLoading(false);
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
        }
            
    }

});