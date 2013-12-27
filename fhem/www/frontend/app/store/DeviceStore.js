/**
 * Store for the Devices
 */
Ext.define('FHEM.store.DeviceStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.DeviceModel',
    id: 'devicestore',
    proxy: {
        type: 'ajax',
        method: 'POST',
        noCache : false,
        url: '', //gets set by controller
        reader: {
            type: 'json',
            root: 'data',
            totalProperty: 'totalCount'
        }
    },
    autoLoad: false
});
