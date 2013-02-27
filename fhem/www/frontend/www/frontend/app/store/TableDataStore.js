/**
 * Store for the TableData from Database
 */
Ext.define('FHEM.store.TableDataStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.TableDataModel',
    buffered: true,
    trailingBufferZone: 200,
    leadingBufferZone: 200,
    //remoteGroup: true,
    pageSize: 200,
        proxy: {
            type: 'ajax',
             method: 'POST',
             url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getTableData+""+""+""+0+100&XHR=1',
             reader: {
                 type: 'json',
                 root: 'data',
                 totalProperty: 'totalCount'
             }
     },
     autoLoad: true,
     listeners: {
         beforeprefetch: function(store, operation) {
             //override stores url to contain start and limit params in our needed notation
             store.proxy.url = '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""';
             store.proxy.url += '+getTableData+""+""+""+' + operation.start +'+' + operation.limit +'&XHR=1';
         }
     }
});