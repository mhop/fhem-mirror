/**
 * Controller handling the charts
 */
Ext.define('FHEM.controller.ChartController', {
    extend: 'Ext.app.Controller',

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
               selector: 'button[name=addyaxisbtn]',
               ref: 'addyaxisbtn' //this.getAddyaxisbtn()
           },
           {
               selector: 'button[name=addbaselinebtn]',
               ref: 'addbaselinebtn' //this.getAddbaselinebtn()
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
               selector: 'combobox[name=device2combo]',
               ref: 'device2combo' //this.getDevicecombo()
           },
           {
               selector: 'combobox[name=y2axiscombo]',
               ref: 'y2axiscombo' //this.getY2axiscombo()
           },
           {
               selector: 'combobox[name=device3combo]',
               ref: 'device3combo' //this.getDevicecombo()
           },
           {
               selector: 'combobox[name=y3axiscombo]',
               ref: 'y3axiscombo' //this.getY3axiscombo()
           },
           {
               selector: 'combobox[name=yaxiscombo]',
               ref: 'yaxiscombo' //this.getYaxiscombo()
           },
           {
               selector: 'combobox[name=yaxiscolorcombo]',
               ref: 'yaxiscolorcombo' //this.getYaxiscombo()
           },
           {
               selector: 'combobox[name=y2axiscolorcombo]',
               ref: 'y2axiscolorcombo' //this.getYaxiscombo()
           },
           {
               selector: 'combobox[name=y3axiscolorcombo]',
               ref: 'y3axiscolorcombo' //this.getYaxiscombo()
           },
           {
               selector: 'checkboxfield[name=yaxisfillcheck]',
               ref: 'yaxisfillcheck' //this.getYaxiscombo()
           },
           {
               selector: 'checkboxfield[name=y2axisfillcheck]',
               ref: 'y2axisfillcheck' //this.getYaxiscombo()
           },
           {
               selector: 'checkboxfield[name=y3axisfillcheck]',
               ref: 'y3axisfillcheck' //this.getYaxiscombo()
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
           },
           {
               selector: 'numberfield[name=base1start]',
               ref: 'base1start' //this.getSavedchartsgrid()
           },
           {
               selector: 'numberfield[name=base1end]',
               ref: 'base1end' //this.getSavedchartsgrid()
           },
           {
               selector: 'combobox[name=baseline1colorcombo]',
               ref: 'base1color' //this.getSavedchartsgrid()
           },
           {
               selector: 'checkboxfield[name=baseline1fillcheck]',
               ref: 'base1fill' //this.getSavedchartsgrid()
           },
           {
               selector: 'numberfield[name=base2start]',
               ref: 'base2start' //this.getSavedchartsgrid()
           },
           {
               selector: 'numberfield[name=base2end]',
               ref: 'base2end' //this.getSavedchartsgrid()
           },
           {
               selector: 'combobox[name=baseline2colorcombo]',
               ref: 'base2color' //this.getSavedchartsgrid()
           },
           {
               selector: 'checkboxfield[name=baseline2fillcheck]',
               ref: 'base2fill' //this.getSavedchartsgrid()
           },
           {
               selector: 'numberfield[name=base3start]',
               ref: 'base3start' //this.getSavedchartsgrid()
           },
           {
               selector: 'numberfield[name=base3end]',
               ref: 'base3end' //this.getSavedchartsgrid()
           },
           {
               selector: 'combobox[name=baseline3colorcombo]',
               ref: 'base3color' //this.getSavedchartsgrid()
           },
           {
               selector: 'checkboxfield[name=baseline3fillcheck]',
               ref: 'base3fill' //this.getSavedchartsgrid()
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
            'combobox[name=device2combo]': {
                select: this.deviceSelected
            },
            'combobox[name=device3combo]': {
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
            'button[name=resetchartform]': {
                click: this.resetFormFields
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
            store,
            proxy;
        
        if (combo.name === "devicecombo") {
            store = this.getYaxiscombo().getStore(),
            proxy = store.getProxy();
        } else if (combo.name === "device2combo") {
            store = this.getY2axiscombo().getStore(),
            proxy = store.getProxy();
        } else if (combo.name === "device3combo") {
            store = this.getY3axiscombo().getStore(),
            proxy = store.getProxy();
        }
        
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
            yaxiscolorcombo = me.getYaxiscolorcombo().getValue(),
            yaxisfillcheck = me.getYaxisfillcheck().checked,
            y2device = me.getDevice2combo().getValue(),
            y2axis = me.getY2axiscombo().getValue(),
            y2axiscolorcombo = me.getY2axiscolorcombo().getValue(),
            y2axisfillcheck= me.getY2axisfillcheck().checked,
            y3device = me.getDevice3combo().getValue(),
            y3axis = me.getY3axiscombo().getValue(),
            y3axiscolorcombo = me.getY3axiscolorcombo().getValue(),
            y3axisfillcheck = me.getY3axisfillcheck().checked,
            
            base1start = me.getBase1start().getValue(),
            base1end = me.getBase1end().getValue(),
            base1color = me.getBase1color().getValue(),
            base1fill = me.getBase1fill().checked,
            base2start = me.getBase2start().getValue(),
            base2end = me.getBase2end().getValue(),
            base2color = me.getBase2color().getValue(),
            base2fill = me.getBase2fill().checked,
            base3start = me.getBase3start().getValue(),
            base3end = me.getBase3end().getValue(),
            base3color = me.getBase3color().getValue(),
            base3fill = me.getBase3fill().checked,
            
            starttime = me.getStarttimepicker().getValue(),
            dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
            endtime = me.getEndtimepicker().getValue(),
            dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
            view = me.getLinechartview(),
            store = me.getLinechartview().getStore(),
            proxy = store.getProxy();
        
        //cleanup store
        store.removeAll();
        
        //cleanup chart
        for (var i = view.series.length -1; i >= 0; i--) {
            view.series.removeAt(i);
        }
        
        //register store listeners
        store.on("beforeload", function() {
            me.getLinechartview().setLoading(true);
        });
        
        //setting x-axis title
        view.axes.get(1).setTitle(xaxis);
        
        // set the x axis range dependent on user given timerange
        view.axes.get(1).fromDate = starttime;
        view.axes.get(1).toDate = endtime;
        view.axes.get(1).processView();
        
        //setup the first y series
        var y1series = {
            type : 'line',
            axis : 'left',
            xField : 'TIMESTAMP',
            yField : 'VALUE',
            title: yaxis,
            showInLegend: true,
            smooth: 2,
            highlight: true,
            fill: yaxisfillcheck,
            style: {
                fill: yaxiscolorcombo,
                stroke: yaxiscolorcombo
            },
            markerConfig: {
                type: 'circle',
                size: 3,
                radius: 3,
                stroke: yaxiscolorcombo
            },
            tips : {
                trackMouse : true,
                width : 140,
                height : 100,
                renderer : function(storeItem, item) {
                    this.setTitle(' Value: : ' + storeItem.get('VALUE') + 
                            '<br> Time: ' + storeItem.get('TIMESTAMP'));
                }
            }
        };
      
        view.series.add(y1series);

        if (proxy) {
            var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                url +=device + '+timerange+' + xaxis + '+' + yaxis;
                url += '&XHR=1'; 
            proxy.url = url;
            store.load();
            store.on("load", function() {
                
                if (!Ext.isEmpty(y2axis)) {
                    
                    //setup the second y series
                    var y2series = {
                        type: 'line',
                        title: y2axis,
                        style: {
                            fill: y2axiscolorcombo,
                            stroke: y2axiscolorcombo
                        },
                        axis: 'left',
                        fill: y2axisfillcheck,
                        smooth: 2,
                        highlight: true,
                        showInLegend: true,
                        xField: 'TIMESTAMP2',
                        yField: 'VALUE2',
                        markerConfig: {
                            type: 'circle',
                            size: 3,
                            radius: 3,
                            stroke: y2axiscolorcombo
                        },
                        tips : {
                            trackMouse : true,
                            width : 140,
                            height : 100,
                            renderer : function(storeItem, item) {
                                this.setTitle(' Value: : ' + storeItem.get('VALUE2') + 
                                        '<br> Time: ' + storeItem.get('TIMESTAMP2'));
                            }
                        }
                    };
                    
                    view.series.add(y2series);
                    
                    var url2 = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                    url2 +=y2device + '+timerange+' + xaxis + '+' + y2axis;
                    url2 += '&XHR=1';
                    
                    Ext.Ajax.request({
                        method: 'GET',
                        disableCaching: false,
                        url: url2,
                        success: function(response){
                            var json = Ext.decode(response.responseText);
                            
                            if (json.success && json.success === "false") {
                                Ext.Msg.alert("Error", "Error an adding 2nd Y-Axis, error was: <br>" + json.msg);
                            } else {
                                    
                                //rewrite valuedescription to differ from other series / axes
                                store.each(function(rec, index) {
                                    if (json.data[index]) {
                                        rec.set('VALUE2', json.data[index].VALUE);
                                        rec.set('TIMESTAMP2', json.data[index].TIMESTAMP);
                                    }
                                    
                                });
                                
                                //add records if y2 contains more than y1
                                var storelength = store.getCount();
                                if (json.data.length > storelength) {
                                    for (var i = storelength; i < json.data.length; i++) {
                                        store.add(
                                            {
                                                "VALUE2": json.data[i].VALUE,
                                                "TIMESTAMP2": json.data[i].TIMESTAMP
                                            }
                                        );
                                    }
                                    
                                }
                                
                                if (!Ext.isEmpty(y3axis)) {
                                    
                                    var y3series = {
                                        type: 'line',
                                        title: y3axis,
                                        highlight: true,
                                        style: {
                                            fill: y3axiscolorcombo,
                                            stroke: y3axiscolorcombo
                                        },
                                        axis: 'left',
                                        fill: y3axisfillcheck,
                                        smooth: 2,
                                        showInLegend: true,
                                        xField: 'TIMESTAMP3',
                                        yField: 'VALUE3',
                                        markerConfig: {
                                            type: 'circle',
                                            size: 3,
                                            radius: 3,
                                            stroke: y3axiscolorcombo
                                        },
                                        tips : {
                                            trackMouse : true,
                                            width : 140,
                                            height : 100,
                                            renderer : function(storeItem, item) {
                                                this.setTitle(' Value: : ' + storeItem.get('VALUE3') + 
                                                        '<br> Time: ' + storeItem.get('TIMESTAMP3'));
                                            }
                                        }
                                    };
                                    
                                    view.series.add(y3series);
                                    
                                    var url3 = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                                    url3 +=y3device + '+timerange+' + xaxis + '+' + y3axis;
                                    url3 += '&XHR=1';
                                    
                                    Ext.Ajax.request({
                                        method: 'GET',
                                        disableCaching: false,
                                        url: url3,
                                        success: function(response){
                                            
                                            var json = Ext.decode(response.responseText);
                                            
                                            if (json.success && json.success === "false") {
                                                Ext.Msg.alert("Error", "Error an adding 3rd Y-Axis, error was: <br>" + json.msg);
                                            } else {
                                                
                                                //rewrite valuedescription to differ from other series / axes
                                                store.each(function(rec, index) {
                                                    if (json.data[index]) {
                                                        rec.set('VALUE3', json.data[index].VALUE);
                                                        rec.set('TIMESTAMP3', json.data[index].TIMESTAMP);
                                                    }
                                                    
                                                });
                                                
                                                //add records if y3 contains more than y2
                                                var storelength = store.getCount();
                                                if (json.data.length > storelength) {
                                                    for (var i = storelength; i < json.data.length; i++) {
                                                        store.add(
                                                            {
                                                                "VALUE3": json.data[i].VALUE,
                                                                "TIMESTAMP3": json.data[i].TIMESTAMP
                                                            }
                                                        );
                                                    }
                                                    
                                                }
                                            } 
                                        },
                                        failure: function() {
                                            Ext.Msg.alert("Error", "Error an adding 3rd Y-Axis");
                                        }
                                    });
                                }
                            } 
                        },
                        failure: function() {
                            Ext.Msg.alert("Error", "Error an adding 2nd Y-Axis");
                        }
                    });
                } 
                
                //adding base lines if neccessary
                if (!Ext.isEmpty(base1start) && base1start != "null") {
                    var bl1 = {
                        type : 'line',
                        name: 'baseline1',
                        axis : 'left',
                        xField : 'TIMESTAMP',
                        yField : 'VALUEBASE1',
                        showInLegend: false,
                        highlight: true,
                        fill: base1fill,
                        style: {
                            fill : base1color,
                            'stroke-width': 3,
                            stroke: base1color
                        },
                        tips : {
                            trackMouse : true,
                            width : 140,
                            height : 100,
                            renderer : function(storeItem, item) {
                                this.setTitle(' Value: : ' + storeItem.get('VALUEBASE1') + 
                                        '<br> Time: ' + storeItem.get('TIMESTAMP'));
                            }
                        }
                    };
                    view.series.add(bl1);
                    
                    store.first().set('VALUEBASE1', base1start);
                    store.last().set('VALUEBASE1', base1end);
                }
                
                if (!Ext.isEmpty(base2start)  && base2start != "null") {
                    var bl2 = {
                        type : 'line',
                        name: 'baseline2',
                        axis : 'left',
                        xField : 'TIMESTAMP',
                        yField : 'VALUEBASE2',
                        showInLegend: false,
                        highlight: true,
                        fill: base2fill,
                        style: {
                            fill : base2color,
                            'stroke-width': 3,
                            stroke: base2color
                        },
                        tips : {
                            trackMouse : true,
                            width : 140,
                            height : 100,
                            renderer : function(storeItem, item) {
                                this.setTitle(' Value: : ' + storeItem.get('VALUEBASE2') + 
                                        '<br> Time: ' + storeItem.get('TIMESTAMP'));
                            }
                        }
                    };
                    view.series.add(bl2);
                    store.first().set('VALUEBASE2', base2start);
                    store.last().set('VALUEBASE2', base2end);
                }
                if (!Ext.isEmpty(base3start) && base3start != "null") {
                    var bl3 = {
                        type : 'line',
                        name: 'baseline3',
                        axis : 'left',
                        xField : 'TIMESTAMP',
                        yField : 'VALUEBASE3',
                        showInLegend: false,
                        highlight: true,
                        fill: base3fill,
                        style: {
                            fill : base3color,
                            'stroke-width': 3,
                            stroke: base3color
                        },
                        tips : {
                            trackMouse : true,
                            width : 140,
                            height : 100,
                            renderer : function(storeItem, item) {
                                this.setTitle(' Value: : ' + storeItem.get('VALUEBASE3') + 
                                        '<br> Time: ' + storeItem.get('TIMESTAMP'));
                            }
                        }
                    };
                    view.series.add(bl3);
                    store.first().set('VALUEBASE3', base3start);
                    store.last().set('VALUEBASE3', base3end);
                    
                }
                
                //remove the old max values of y axis to get a dynamic range
                delete view.axes.get(0).maximum;
                
                me.getLinechartview().setLoading(false);
                
            }, this, {single: true});
            
            
        }
        
        
    },
    
    /**
     * reset the form fields e.g. when loading a new chart
     */
    resetFormFields: function() {
        this.getChartformpanel().getForm().reset();
        this.getDevice2combo().hide();
        this.getY2axiscombo().hide();
        this.getY2axiscolorcombo().hide();
        this.getY2axisfillcheck().hide();
        this.getDevice3combo().hide();
        this.getY3axiscombo().hide();
        this.getY3axiscolorcombo().hide();
        this.getY3axisfillcheck().hide();
        this.getAddyaxisbtn().setDisabled(false);
        this.getBase1start().hide();
        this.getBase1end().hide();
        this.getBase1color().hide();
        this.getBase1fill().hide();
        this.getBase2start().hide();
        this.getBase2end().hide();
        this.getBase2color().hide();
        this.getBase2fill().hide();
        this.getBase3start().hide();
        this.getBase3end().hide();
        this.getBase3color().hide();
        this.getBase3fill().hide();
        this.getAddbaselinebtn().setDisabled(false);
        
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
                
                //replacing spaces in name
                savename = savename.replace(/ /g, "_");
                
                //replacing + in name
                savename = savename.replace(/\+/g, "_");
                
                var device = this.getDevicecombo().getValue(),
                    xaxis = this.getXaxiscombo().getValue(),
                    yaxis = this.getYaxiscombo().getValue(),
                    
                    yaxiscolorcombo = me.getYaxiscolorcombo().getDisplayValue(),
                    yaxisfillcheck = me.getYaxisfillcheck().checked,
                    y2device = me.getDevice2combo().getValue(),
                    y2axis = me.getY2axiscombo().getValue(),
                    y2axiscolorcombo = me.getY2axiscolorcombo().getDisplayValue(),
                    y2axisfillcheck= me.getY2axisfillcheck().checked,
                    y3device = me.getDevice3combo().getValue(),
                    y3axis = me.getY3axiscombo().getValue(),
                    y3axiscolorcombo = me.getY3axiscolorcombo().getDisplayValue(),
                    y3axisfillcheck = me.getY3axisfillcheck().checked,
                    base1start = me.getBase1start().getValue(),
                    base1end = me.getBase1end().getValue(),
                    base1color = me.getBase1color().getDisplayValue(),
                    base1fill = me.getBase1fill().checked,
                    base2start = me.getBase2start().getValue(),
                    base2end = me.getBase2end().getValue(),
                    base2color = me.getBase2color().getDisplayValue(),
                    base2fill = me.getBase2fill().checked,
                    base3start = me.getBase3start().getValue(),
                    base3end = me.getBase3end().getValue(),
                    base3color = me.getBase3color().getDisplayValue(),
                    base3fill = me.getBase3fill().checked,
                    
                    starttime = this.getStarttimepicker().getValue(),
                    dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s'),
                    endtime = this.getEndtimepicker().getValue(),
                    dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s'),
                    view = this.getLinechartview();
                
                var jsonConfig = '{\\"x\\":\\"' + xaxis + '\\",\\"y\\":\\"' + yaxis + '\\",\\"device\\":\\"' + device + '\\",';
                    jsonConfig += '\\"yaxiscolorcombo\\":\\"\\' + yaxiscolorcombo + '\\",\\"yaxisfillcheck\\":\\"' + yaxisfillcheck + '\\",';
                    jsonConfig += '\\"y2device\\":\\"' + y2device + '\\",';
                    jsonConfig += '\\"y2axis\\":\\"' + y2axis + '\\",\\"y2axiscolorcombo\\":\\"' + y2axiscolorcombo + '\\",';
                    jsonConfig += '\\"y2axisfillcheck\\":\\"' + y2axisfillcheck + '\\",\\"y3axis\\":\\"' + y3axis + '\\",';
                    jsonConfig += '\\"y3device\\":\\"' + y3device + '\\",';
                    jsonConfig += '\\"y3axiscolorcombo\\":\\"' + y3axiscolorcombo + '\\",\\"y3axisfillcheck\\":\\"' + y3axisfillcheck + '\\",';
                    jsonConfig += '\\"base1start\\":\\"' + base1start + '\\",\\"base1end\\":\\"' + base1end + '\\",';
                    jsonConfig += '\\"base1color\\":\\"' + base1color + '\\",\\"base1fill\\":\\"' + base1fill + '\\",';
                    jsonConfig += '\\"base2start\\":\\"' + base2start + '\\",\\"base2end\\":\\"' + base2end + '\\",';
                    jsonConfig += '\\"base2color\\":\\"' + base2color + '\\",\\"base2fill\\":\\"' + base2fill + '\\",';
                    jsonConfig += '\\"base3start\\":\\"' + base3start + '\\",\\"base3end\\":\\"' + base3end + '\\",';
                    jsonConfig += '\\"base3color\\":\\"' + base3color + '\\",\\"base3fill\\":\\"' + base3fill + '\\",';
                    jsonConfig += '\\"starttime\\":\\"' + dbstarttime + '\\",\\"endtime\\":\\"' + dbendtime + '\\"}';
            
                var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                    url +=device + '+savechart+""+""+' + savename + '+' + jsonConfig + '&XHR=1'; 
                
                view.setLoading(true);
                
                Ext.Ajax.request({
                    method: 'GET',
                    disableCaching: false,
                    url: url,
                    success: function(response){
                        view.setLoading(false);
                        var json = Ext.decode(response.responseText);
                        if (json.success === "true") {
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
        }, this);
        
    },
    
    /**
     * loading saved chart data and trigger the load of the chart
     */
    loadsavedchart: function(grid, td, cellIndex, record) {

        if (cellIndex === 0) {
            var name = record.get('NAME'),
                rawchartdata = record.get('VALUE'),
                chartdata = Ext.decode(rawchartdata);
            
            //cleanup the form before loading
            this.resetFormFields();
            
            if (chartdata && !Ext.isEmpty(chartdata)) {
                
                this.getDevicecombo().setValue(chartdata.device);
                // load storedata for readings after device has been selected
                this.deviceSelected(this.getDevicecombo());
                
                this.getXaxiscombo().setValue(chartdata.x);
                this.getYaxiscombo().setValue(chartdata.y);
                
                if (chartdata.y2device && !Ext.isEmpty(chartdata.y2device) && chartdata.y2device != "null") {
                    this.getDevice2combo().setValue(chartdata.y2device);
                    this.getDevice2combo().show();
                    this.getY2axiscombo().setValue(chartdata.y2axis);
                    this.getY2axiscombo().show();
                    this.getY2axiscolorcombo().setValue(chartdata.y2axiscolorcombo);
                    this.getY2axiscolorcombo().show();
                    this.getY2axisfillcheck().setValue(chartdata.y2axisfillcheck);
                    this.getY2axisfillcheck().show();
                }
                if (chartdata.y3device && !Ext.isEmpty(chartdata.y3device) && chartdata.y3device != "null") {
                    this.getDevice3combo().setValue(chartdata.y3device);
                    this.getDevice3combo().show();
                    this.getY3axiscombo().setValue(chartdata.y3axis);
                    this.getY3axiscombo().show();
                    this.getY3axiscolorcombo().setValue(chartdata.y3axiscolorcombo);
                    this.getY3axiscolorcombo().show();
                    this.getY3axisfillcheck().setValue(chartdata.y3axisfillcheck);
                    this.getY3axisfillcheck().show();
                }
                
                if (chartdata.base1start && !Ext.isEmpty(chartdata.base1start) && chartdata.base1start != "null") {
                    this.getBase1start().setValue(chartdata.base1start);
                    this.getBase1start().show();
                    this.getBase1end().setValue(chartdata.base1end);
                    this.getBase1end().show();
                    this.getBase1color().setValue(chartdata.base1color);
                    this.getBase1color().show();
                    this.getBase1fill().setValue(chartdata.base1fill);
                    this.getBase1fill().show();
                }
                
                if (chartdata.base2start && !Ext.isEmpty(chartdata.base2start) && chartdata.base2start != "null") {
                    this.getBase2start().setValue(chartdata.base2start);
                    this.getBase2start().show();
                    this.getBase2end().setValue(chartdata.base2end);
                    this.getBase2end().show();
                    this.getBase2color().setValue(chartdata.base2color);
                    this.getBase2color().show();
                    this.getBase2fill().setValue(chartdata.base2fill);
                    this.getBase2fill().show();
                }
                
                if (chartdata.base3start && !Ext.isEmpty(chartdata.base3start) && chartdata.base3start != "null") {
                    this.getBase3start().setValue(chartdata.base3start);
                    this.getBase3start().show();
                    this.getBase3end().setValue(chartdata.base3end);
                    this.getBase3end().show();
                    this.getBase3color().setValue(chartdata.base3color);
                    this.getBase3color().show();
                    this.getBase3fill().setValue(chartdata.base3fill);
                    this.getBase3fill().show();
                }
                
                //convert time
                var start = chartdata.starttime.replace("_", " "),
                    end = chartdata.endtime.replace("_", " ");
                this.getStarttimepicker().setValue(start);
                this.getEndtimepicker().setValue(end);
                
                this.requestChartData();
                this.getLinechartpanel().setTitle(name);
            } else {
                Ext.Msg.alert("Error", "The Chart could not be loaded! RawChartdata was: <br>" + rawchartdata);
            }
            
        }
    },
    
    /**
     * Delete a chart by its name from the database
     */
    deletechart: function(grid, td, cellIndex, par, evt, record) {
        
        var me = this,
            chartid = record.get('ID'),
            view = this.getLinechartview();
        
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
                    
                        view.setLoading(true);
                        
                        Ext.Ajax.request({
                            method: 'GET',
                            disableCaching: false,
                            url: url,
                            success: function(response){
                                view.setLoading(false);
                                var json = Ext.decode(response.responseText);
                                if (json && json.success === "true") {
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
        } else {
            Ext.Msg.alert("Error", "The Chart could not be deleted, no record id has been found");
        }
            
    } 

});