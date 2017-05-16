/**
 * Store for the Devices
 */
Ext.define('FHEM.store.DeviceStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.DeviceModel',
    proxy: {
        type: 'ajax',
        method: 'POST',
        url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getdevices&XHR=1',
        reader: {
            type: 'json',
            root: 'data',
            totalProperty: 'totalCount'
        }
    },
    autoLoad: false
});
