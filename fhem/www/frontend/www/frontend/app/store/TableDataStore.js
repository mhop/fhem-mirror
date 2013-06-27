/**
 * Store for the TableData from Database
 */
Ext.define('FHEM.store.TableDataStore', {
    extend: 'Ext.data.Store',
    model: 'FHEM.model.TableDataModel',
    buffered: true,
    trailingBufferZone: 1000,
    leadingBufferZone: 1000,
    //remoteGroup: true,
    pageSize: 1000,
        proxy: {
            type: 'ajax',
             method: 'POST',
             url: '../../../fhem?cmd=get+' + FHEM.dblogname + '+-+webchart+""+""+""+getTableData+""+""+""+""+0+100&XHR=1',
             reader: {
                 type: 'json',
                 root: 'data',
                 totalProperty: 'totalCount'
             }
     },
     autoLoad: false
});