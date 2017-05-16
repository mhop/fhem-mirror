/**
 * Store for the saved Charts
 */
Ext.define('FHEM.store.SavedChartsStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.SavedChartsModel',
        proxy: {
            type: 'ajax',
             method: 'POST',
             url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getcharts&XHR=1',
             reader: {
                 type: 'json',
                 root: 'data',
                 totalProperty: 'totalCount'
             }
     },
     autoLoad: true
});
