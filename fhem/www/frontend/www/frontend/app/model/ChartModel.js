/**
 * Model for Charts
 */
Ext.define('FHEM.model.ChartModel', {
    extend: 'Ext.data.Model',
    fields: [
        {
            name: 'TIMESTAMP',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP2',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP3',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'VALUE',
            type: 'float'
        },{
            name: 'VALUE2',
            type: 'float'
        },{
            name: 'VALUE3',
            type: 'float'
        }
    ]
});