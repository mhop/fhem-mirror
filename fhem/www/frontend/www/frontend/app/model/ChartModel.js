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
            type: 'float',
            convert: function( v, record ) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE2',
            type: 'float',
            convert: function( v, record ) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE3',
            type: 'float',
            convert: function( v, record ) {
                return record.parseToNumber(v);
            }
        }
    ],
    parseToNumber: function(value) {
        if (value === "") {
            return 0;
        } else if (parseFloat(value, 10).toString().toUpperCase() === "NAN") {
            if (Ext.isDefined(FHEM) && Ext.isDefined(FHEM.userconfig)) {
                var convertednumber = 0;
                Ext.iterate(FHEM.userconfig.chartkeys, function(k, v) {
                    if (value === k) {
                        //return the value for the given key from userconfig
                        convertednumber = v;
                    }
                });
                return parseFloat(convertednumber, 10);
            } else {
                return value;
            }
        } else {
            return parseFloat(value, 10);
        }
    }
});