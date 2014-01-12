/**
 * The Controller handling Status Panel
 */
Ext.define('FHEM.controller.StatusController', {
    extend: 'Ext.app.Controller',
    requires: [
       'FHEM.view.StatusPanel'
    ],

    refs: [
    ],

    /**
     * boolean indicating when the charts tree is loaded
     */
    treeloaded: false,
    
    /**
     * boolean indicating when the statuspanel is rendered 
     */
    statuspanelrendered: false,
    
    /**
     * boolean indicating that we are currently updating a preview chart
     */
    updateRunning: false,
    
    /**
     * boolean indicating that we are currently updating via global autoupdater
     */
    autoUpdateRunning: false,
    
    /**
     * init function to register listeners
     */
    init: function() {
        this.control({
            'button[name=updatepreviewchart]': {
                click: this.updatePreviewChart
            },
            'button[name=loadfullchart]': {
                click: this.loadFullChart
            },
            'panel[name=statuspanel]': {
                afterrender: function() {
                    this.statuspanelrendered = true;
                    this.setupPanelsFromTreeContent();
                },
                show: this.setupGlobalUpdateTask,
                hide: function() {
                    Ext.each(Ext.TaskManager.tasks, function(task) {
                        if (task.name === 'countdowntask') {
                            Ext.TaskManager.stop(task);
                        }
                    });
                }
            },
            'panel[name=maintreepanel]': {
                treeloaded: function() {
                    this.treeloaded = true;
                    this.setupPanelsFromTreeContent();
                }
            },
            'button[name=applypreviewchartsize]': {
                click: function() {
                    this.destroyAllPreviewPanels();
                    this.setupPanelsFromTreeContent();
                }
            },
            'button[name=reloadallpreviews]': {
                click: this.triggerUpdateForAllPreviews
            },
            'treeview': {
                drop: function() {
                    this.destroyAllPreviewPanels();
                    this.setupPanelsFromTreeContent();
                }
            },
            'button[name=savepreviewchartsconfig]': {
                click: function() {
                    
                    var panel = Ext.ComponentQuery.query('panel[name=statuspanel]')[0],
                        location = 'previewchartsconfig',
                        objectToSave = {};
                    
                    objectToSave.width = Ext.ComponentQuery.query('numberfield[name=previewchartwidth]')[0].getValue();
                    objectToSave.height = Ext.ComponentQuery.query('numberfield[name=previewchartheight]')[0].getValue();
                    objectToSave.autoUpdate = Ext.ComponentQuery.query('checkbox[name=autoupdatecheckbox]')[0].getValue();
                    objectToSave.updateInterval = Ext.ComponentQuery.query('numberfield[name=updateinterval]')[0].getValue();

                    // delegate to maincontroller
                    panel.fireEvent("saveconfig", objectToSave, location);
                }
            },
            'checkbox[name=autoupdatecheckbox]': {
                change: this.setupGlobalUpdateTask
            }
        });
        
    },
    
    /**
     * 
     */
    setupGlobalUpdateTask: function() {
        
        var me = this,
            autoUpdate = Ext.ComponentQuery.query('checkbox[name=autoupdatecheckbox]')[0].getValue(),
            updateInterval = Ext.ComponentQuery.query('numberfield[name=updateinterval]')[0].getValue(),
            txt = Ext.ComponentQuery.query('text[name=countdowntext]')[0];

        if (autoUpdate === true && !Ext.isEmpty(updateInterval)) {
            
            txt.setDisabled(false);
            
            // stop all old tasks
            Ext.each(Ext.TaskManager.tasks, function(task) {
                if (task.name === 'countdowntask') {
                    Ext.TaskManager.stop(task);
                }
            });
            
            // start the countdown
            Ext.ComponentQuery.query('text[name=countdowntext]')[0].counter = updateInterval;
            var countdownTask = Ext.TaskManager.start({
                run: function() {
                    var txt = Ext.ComponentQuery.query('text[name=countdowntext]')[0];
                    if (txt.counter > 0) {
                        txt.setText('Next Update in ' + (txt.counter - 1) + 's');
                        txt.counter--;
                    } else if (txt.counter === 0 && !me.autoUpdateRunning){
                        me.autoUpdateRunning = true;
                        me.triggerUpdateForAllPreviews();
                        txt.setText('Updating...');
                        txt.counter--;
                    } else if (!me.autoUpdateRunning){
                        var currentInterval = Ext.ComponentQuery.query('numberfield[name=updateinterval]')[0].getValue();
                        txt.setText('Next Update in ' + currentInterval + 's');
                        txt.counter = currentInterval;
                    }
                },
                name: 'countdowntask',
                interval: 900
            });
            
        } else {
            Ext.each(Ext.TaskManager.tasks, function(task) {
                if (task.name === 'countdowntask') {
                    Ext.TaskManager.stop(task);
                }
            });
            txt.setText('Update disabled');
            txt.setDisabled(true);
        }
    },
    
    /**
     * 
     */
    createPreviewChartPanel: function(record) {
        var me = this,
            desiredWidth = Ext.ComponentQuery.query('numberfield[name=previewchartwidth]')[0].getValue(),
            desiredHeight = Ext.ComponentQuery.query('numberfield[name=previewchartheight]')[0].getValue(),
            savename;
        
        if (record.raw.ID) {
            savename = record.raw.ID + '.svg';
        } else {
            savename = record.raw.data.ID + '.svg';
        }
        var previewchartcontainer = Ext.ComponentQuery.query('panel[name=previewchartcontainer]')[0],
            previewpanel = Ext.create('Ext.panel.Panel', {
                width: desiredWidth,
                height: desiredHeight,
                title: record.raw.text ? record.raw.text : 'No title found...',
                record: record,
                name: 'chartpreviewpanel',
                items: [
                    {
                        xtype: 'toolbar',
                        ui: 'footer',
                        enableOverflow: true,
                        items: [
                            {
                                xtype: 'text',
                                name: 'lastupdatedtext',
                                text: "Last Updated: not yet"
                            },
                            '->',
                            {
                                text: 'Open Full Chart',
                                name: 'loadfullchart'
                            },
                            {
                                text: 'Reload',
                                name: 'updatepreviewchart'
                            }
                        ]
                    },
                    {
                        xtype: 'image',
                        layout: 'fit',
                        // add date to path to avoid cached images from browser
                        src: 'app/imagecache/' + savename + '?_' + new Date(),
                        width: desiredWidth,
                        height: desiredHeight - 53
                    }
                ]
        });
        previewchartcontainer.add(previewpanel);
    },
    
    /**
     * 
     */
    loadFullChart: function(btn) {
        var rec = btn.up('panel[name=chartpreviewpanel]').record;
        
        var centerpanels = Ext.ComponentQuery.query('panel[region=center]');
        Ext.each(centerpanels, function(panel) {
            panel.hide();
        });
        
        Ext.ComponentQuery.query('linechartpanel')[0].show();
        Ext.ComponentQuery.query('treepanel')[0].expand();
        
        btn.fireEvent('loadchart', null, rec, false);
        
    },
    
    /**
     * 
     */
    destroyAllPreviewPanels: function() {
        Ext.ComponentQuery.query('panel[name=previewchartcontainer]')[0].removeAll();
    },
    
    /**
     * 
     */
    setupPanelsFromTreeContent: function() {
        
        var me = this;
        
        if (me.statuspanelrendered && me.treeloaded) {
            var root = Ext.ComponentQuery.query('treepanel')[0].getRootNode(),
                statusfoldernode = root.findChild("text", "StatusRoom", true);
            
            if (statusfoldernode.childNodes.length > 0) {
                Ext.ComponentQuery.query('panel[name=previewchartcontainer]')[0].update('');
            } else {
                Ext.ComponentQuery.query('panel[name=previewchartcontainer]')[0].update(
                        'This panel gives you an overview of your Charts by displaying them as small windows here.<br>' + 
                        'To add Charts to this Overview, simply drop some into the folder "StatusRoom" which you<br>' +
                        'can find in the tree on the left side.<br>' +
                        'Add as much charts as you want, configure their size and update options and save your<br>' +
                        'settings by clicking on "Save configuration".<br>' +
                        'The first time you add a new chart you need to reload it, before you can see it!');
            }
            
            Ext.each(statusfoldernode.childNodes, function(node) {
                me.createPreviewChartPanel(node);
            });
            
            //initialize auto update
            me.setupGlobalUpdateTask();
        }
        
    },
    
    /**
     * 
     */
    updatePreviewChart:  function(btn, panel) {
        
        var me = this;
        if (panel && panel.down) {
            btn = panel.down('button[name=updatepreviewchart]');
        }
        
        if (me.updateRunning === true) {
            window.setTimeout(function() {
                me.updatePreviewChart(btn);
            }, 500);
            return;
        }
        
        me.updateRunning = true;
        
        // destroy all old charts
        me.destroyAllCharts();
        
        var imgcontainer = btn.up('panel').down('image');
        imgcontainer.setLoading(true);
        
        // get record from panel
        var record = btn.up('panel').record;
        // event will get caught in chartcontroller
        btn.fireEvent('loadhiddenchart', null, record, true);
        
        // now we wait till the chart is rendered
        var task = Ext.TaskManager.start({
            run: function() {
                me.checkForRenderedChart(imgcontainer, task);
            },
            name: 'hiddenchart',
            interval: 500
        });
    },
    
    /**
     * 
     */
    triggerUpdateForAllPreviews: function() {
        var me = this,
            allPanels = Ext.ComponentQuery.query('panel[name=chartpreviewpanel]');
        
        Ext.each(allPanels, function(panel) {
            me.updatePreviewChart(false, panel);
        });
    },
    
    /**
     * method destroys all rendered charts
     */
    destroyAllCharts: function() {
        var charts = Ext.ComponentQuery.query('chart');
        Ext.each(charts, function(chart) {
            chart.destroy();
        });
    },
    
    /**
     * 
     */
    checkForRenderedChart: function(imgcontainer, task){
        var me = this,
            desiredWidth = Ext.ComponentQuery.query('numberfield[name=previewchartwidth]')[0].getValue(),
            desiredHeight = Ext.ComponentQuery.query('numberfield[name=previewchartheight]')[0].getValue();
        
        var chart = Ext.ComponentQuery.query('chart')[0];
        if (chart && chart.surface && chart.surface.el && chart.surface.el.dom) {
            chart.setHeight(desiredHeight - 53); // removing the panels title and toolbar from height
            chart.setWidth(desiredWidth);
            data = chart.surface.el.dom;
            // we need to cleanup the "ext"-invisible items because they will get rendered
            textArray = data.getElementsByTagName("text");
            Ext.each(textArray, function(text) {
                if (text.getAttribute("class") && text.getAttribute("class").indexOf("x-hide-visibility") >= 0 ) {
                    text.remove();
                }
            });
            
            var serializer = new XMLSerializer(),
                svgstring = serializer.serializeToString(data),
                canvas = document.getElementById("canvas"),
                ctx = canvas.getContext("2d"),
                DOMURL = self.URL || self.webkitURL || self,
                img = new Image(),
                svg = new Blob([svgstring], {type: "image/svg+xml;charset=utf-8"}),
                url = DOMURL.createObjectURL(svg);
            
            img.onload = function() {
                ctx.drawImage(img, 0, 0);
                DOMURL.revokeObjectURL(url);
            };
            img.src = url;
            imgcontainer.setSrc(img.src);
            imgcontainer.setLoading(false);
            
            Ext.TaskManager.stop(task);
            me.destroyAllCharts();
            
            var rec = imgcontainer.up('panel').record;
            imgcontainer.up('panel').down('text[name=lastupdatedtext]').setText(Ext.Date.format(new Date(), 'Y-m-d H:i:s'));
            
            me.saveImageToDisk(svgstring, rec);
            me.updateRunning = false;
            
            // check if an autoupdate has completed
            var sp = imgcontainer.up('panel[name=previewchartcontainer]');
            if (me.autoUpdateRunning && imgcontainer.up('panel').title === sp.items.items[sp.items.items.length - 1].title) {
                me.autoUpdateRunning = false;
            }
        }
            
    },
    
    /**
     * 
     */
    saveImageToDisk: function(svgstring, rec) {

        var savename;
        
        if (rec.raw.ID) {
            savename = rec.raw.ID + '.svg';
        } else {
            savename = rec.raw.data.ID + '.svg';
        }
        
        //fhem specific fixes ...
        svgstring = svgstring.replace(/;/g, ";;");
        svgstring = svgstring.replace(/\#/g, "\\x23");
        
        var svgArr = [],
            lastMax = 0;
        
        // we split up the string in onehundredthousands-packages, so fhem will accept those posts...
        while (svgstring.length > lastMax) {
            svgArr.push(svgstring.slice(lastMax, lastMax + 100000));
            lastMax = lastMax + 100000;
        }
        
        var i = 0,
            cmd;
        Ext.each(svgArr, function(part) {
            if (i === 0) {
                cmd = "{ `echo '" + part + "' > " + FHEM.appPath + "imagecache/" + savename + "`}";
            } else {
                cmd = "{ `echo -n '" + part + "' >> " + FHEM.appPath + "imagecache/" + savename + "`}";
            }
            
            i++;
            
            Ext.Ajax.request({
                method: 'POST',
                disableCaching: false,
                async: false,
                url: '../../../fhem?',
                params: {
                    cmd: cmd,
                    XHR: 1
                },
                success: function(response){
                    if (response.status === 200) {
                        // no feedback
                    } else if (response.statusText) {
                        Ext.Msg.alert("Error", "The Chart-Image could not be saved, error Message is:<br><br>" + response.statusText);
                    } else {
                        Ext.Msg.alert("Error", "The Chart-Image could not be saved!");
                    }
                },
                failure: function(response) {
                    if (response.statusText) {
                        Ext.Msg.alert("Error", "The Chart-Image could not be saved, error Message is:<br><br>" + response.statusText);
                    } else {
                        Ext.Msg.alert("Error", "The Chart-Image could not be saved!");
                    }
                }
            });
        });
    }
});