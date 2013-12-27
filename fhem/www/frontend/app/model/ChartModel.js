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
            name: 'TIMESTAMP4',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP5',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP6',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP7',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP8',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'TIMESTAMP9',
            type: 'date',
            dateFormat: "Y-m-d H:i:s"
        },
        {
            name: 'VALUE',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE2',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE3',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE4',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE5',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE6',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE7',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE8',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },{
            name: 'VALUE9',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM2',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM3',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM4',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM5',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM6',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM7',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM8',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'SUM9',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG2',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG3',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG4',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG5',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG6',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG7',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG8',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'AVG9',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN2',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN3',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN4',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN5',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN6',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN7',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN8',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MIN9',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX2',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX3',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX4',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX5',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX6',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX7',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX8',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'MAX9',
            type: 'float',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT2',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT3',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT4',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT5',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT6',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT7',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT8',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        },
        {
            name: 'COUNT9',
            type: 'integer',
            convert: function(v,record) {
                return record.parseToNumber(v);
            }
        }
    ],
    parseToNumber: function(value) {
        
        if (value === "") {
            //we will return nothing
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