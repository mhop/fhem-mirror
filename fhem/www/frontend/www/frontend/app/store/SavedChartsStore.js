/**
 * Store for the saved Charts
 */
Ext.define('FHEM.store.SavedChartsStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.SavedChartsModel',
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
