/**
 * Store for the Charts
 */
Ext.define('FHEM.store.ChartStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.ChartModel',
        proxy: {
            type: 'ajax',
             method: 'POST',
             url: '', //gets set by controller
             reader: {
                 type: 'json',
                 root: 'data',
                 totalProperty: 'totalCount'
             }
     },
     autoLoad: false
});