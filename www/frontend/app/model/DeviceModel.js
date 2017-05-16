/**
 * Model for Devices
 */
Ext.define('FHEM.model.DeviceModel', {
    extend: 'Ext.data.Model',
    fields: [
         {
             name: 'DEVICE',
             type: 'text'
         }
    ]
});