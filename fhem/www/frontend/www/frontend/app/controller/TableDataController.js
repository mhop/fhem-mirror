/**
 * The Controller handling Table Data retrieval
 */
Ext.define('FHEM.controller.TableDataController', {
    extend: 'Ext.app.Controller',
    requires: [
       'FHEM.view.TableDataGridPanel'
    ],

    refs: [
           {
               selector: 'button[name=applytablefilter]',
               ref: 'applytablefilterbtn' //this.getApplytablefilterbtn()
           }
    ],

    /**
     * init function to register listeners
     */
    init: function() {
        this.control({
            'button[name=applytablefilter]': {
                click: this.filterTableData
            }
        });
    },
    
    /**
     * function handling the filtering of tabledata, preparing querystring
     */
    filterTableData: function() {
        
        var me = this,
            devicecombo = Ext.ComponentQuery.query('combo[name=tddevicecombo]')[0],
            readingscombo = Ext.ComponentQuery.query('combo[name=tdreadingscombo]')[0],
            checkedradio = Ext.ComponentQuery.query('radiogroup[name=tddynamictime]')[0],
            starttimepicker = Ext.ComponentQuery.query('datefield[name=tdstarttimepicker]')[0],
            endtimepicker = Ext.ComponentQuery.query('datefield[name=tdendtimepicker]')[0],
            gridpanel = Ext.ComponentQuery.query('gridpanel[name=tabledatagridpanel]')[0];
         
        //check if timerange or dynamic time should be used
        checkedradio.eachBox(function(box, idx){
            var date = new Date();
            if (box.checked) {
                if (box.inputValue === "year") {
                    starttime = Ext.Date.parse(date.getUTCFullYear() + "-01-01", "Y-m-d");
                    endtime = Ext.Date.parse(date.getUTCFullYear() +  1 + "-01-01", "Y-m-d");
                } else if (box.inputValue === "month") {
                    starttime = Ext.Date.getFirstDateOfMonth(date);
                    endtime = Ext.Date.getLastDateOfMonth(date);
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
                    endtime = nextmonday;
                } else if (box.inputValue === "day") {
                    date.setHours(0);
                    date.setMinutes(0);
                    date.setSeconds(0);
                    starttime = date;
                    endtime = Ext.Date.add(date, Ext.Date.DAY, 1);
                } else if (box.inputValue === "hour") {
                    date.setMinutes(0);
                    date.setSeconds(0);
                    starttime = date;
                    endtime = Ext.Date.add(date, Ext.Date.HOUR, 1);
                } else {
                    Ext.Msg.alert("Error", "Could not setup the dynamic time.");
                }
                dbstarttime = Ext.Date.format(starttime, 'Y-m-d_H:i:s');
                dbendtime = Ext.Date.format(endtime, 'Y-m-d_H:i:s');
                
                starttimepicker.setValue(starttime);
                endtimepicker.setValue(endtime);
            } else {
                dbstarttime = Ext.Date.format(starttimepicker.getValue(), 'Y-m-d_H:i:s');
                dbendtime = Ext.Date.format(endtimepicker.getValue(), 'Y-m-d_H:i:s');
            }
        });
        
        if (Ext.isEmpty(dbstarttime) || Ext.isEmpty(dbendtime)) {
            Ext.Msg.alert("Error", "Please select a timerange first!");
        } else {
            //cleanup store
            gridpanel.getStore().clearData();
            
            var firststart = true;
                
            gridpanel.getStore().on("beforeprefetch", function(store, operation, eOpts) {
                
                var url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+' + dbstarttime + '+' + dbendtime + '+';
                if (!Ext.isEmpty(devicecombo.getValue())) {
                    url += devicecombo.getValue();
                } else {
                    url += '""';
                }
                    
                url += '+getTableData+""+';
                if (!Ext.isEmpty(readingscombo.rawValue)) {
                    url += readingscombo.rawValue;
                } else {
                    url += '""';
                }
                url += '+""+""+';
                if (firststart) {
                    url += "0+";
                    firststart = false;
                } else {
                    url += operation.start + "+";
                }
                url += operation.limit + "&XHR=1";
                
                if (operation.request) {
                    operation.request.url = url;
                }
                
                store.proxy.url = url;
            });
            gridpanel.getStore().load();
            
        }
    }
    
});