/**
 * Model for DatabaseTables
 */
Ext.define('FHEM.model.TableDataModel', {
    extend: 'Ext.data.Model',
    fields: [
        {
            name: 'TIMESTAMP',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'DEVICE',
            type: 'text'
        },
        {
            name: 'TYPE',
            type: 'text'
        },
        {
            name: 'EVENT',
            type: 'text'
        },
        {
            name: 'READING',
            type: 'text'
        },
        {
            name: 'VALUE',
            type: 'text'
        },
        {
            name: 'UNIT',
            type: 'text'
        }
    ]
});