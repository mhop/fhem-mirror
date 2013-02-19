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
        },{
            name: 'VALUE',
            type: 'float'
        }
    ]
});