/**
 * Model for saved Charts
 */
Ext.define('FHEM.model.SavedChartsModel', {
    extend: 'Ext.data.Model',
    fields: [
        {
            name: 'VALUE',
            type: 'text'
        },{
            name: 'EVENT',
            type: 'text'
        }
    ]
});