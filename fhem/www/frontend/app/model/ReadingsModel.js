/**
 * Model for Readings
 */
Ext.define('FHEM.model.ReadingsModel', {
    extend: 'Ext.data.Model',
    fields: [
         {
             name: 'READING',
             type: 'text'
         }
    ]
});