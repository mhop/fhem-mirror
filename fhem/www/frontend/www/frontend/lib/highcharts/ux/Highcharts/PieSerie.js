/**
 * # Plotting Pie Series
 * There are two ways to plot pie chart from record data: a data point per record and
 * total values of all the records
 *
 * ## Data point per record
 * Pie series uses two options for mapping category name and data fields: 
 * *categoryField* and *dataField*, (This is historical reason instead of 
 * using *xField* and *dataIndex*). Suppose we have data model in the following format:
 *
 * <table>
 *    <tbody>
 *       <tr><td>productName</td><td>sold</td></tr>
 *       <tr><td>Product A</td><td>15,645,242</td></tr>
 *       <tr><td>Product B</td><td>22,642,358</td></tr>
 *       <tr><td>Product C</td><td>21,432,330</td></tr>
 *    </tbody>
 * </table>
 * Then we can define the series data as:
 * 
 *     series: [{
 *        type: 'pie',
 *        categoryField: 'productName',
 *        dataField: 'sold'
 *     }]
 *
 * # Data point as total value of all the records
 * Instead of mapping *dataField* and *categorieField* fields to the store record for each
 * pie data point, this approach uses the total value of a category as a data point. 
 * E.g. we have a class of pupils with a set of subject scores
 * <table>
 *    <tbody>
 *       <tr><td>Name</td><td>English</td><td>Math</td><td>Science</td></tr>
 *       <tr><td>Joe</td><td>77</td><td>81</td><td>78</td></tr>
 *       <tr><td>David</td><td>67</td><td>56</td><td>69</td><tr>
 *       <tr><td>Nora</td><td>44</td><td>50</td><td>39</td><tr>
 *    </tbody>
 * </table>
 * All we want is to plot distribution of total scores for each subject. Hence, we define
 * the pie series as follows:
 *     series: [{
 *        type: 'pie',
 *        useTotals: true,
 *        column: [ 'english', 'math', 'science' ]
 *     }]
 * whereas the server-side should return JSON data as follows:
 *     { "root": [{ "english": 77, "math": 81, "science": 78 },
 *                { "english": 67, "math": 56, "science": 69 },
 *                { "english": 44, "math": 50, "science": 39 },
 *                .....                                         ]
 *     } 
 * and the data model for the store is defined as follows:
 *     Ext.define('ExamResults', {
 *        extend: 'Ext.data.Model',
 *          fields: [
 *              {name: 'english', type: 'int'},
 *              {name: 'math',  type: 'int'},
 *              {name: 'science',  type: 'int'}
 *          ]
 *     });
 *  
 * # Multiple Pie Series (Donut chart)
 * A donut chart is really two pie series which a second pie series lay outside of the 
 * first series. The second series is subcategory data of the first series.
 * Suppose we want to plot a more detail chart with the breakdown of sold items into regions:
 * <table>
 *    <tbody>
 *       <tr><td>productName</td><td>sold</td><td>Europe</td><td>Asia</td><td>Americas</td></tr>
 *       <tr><td>Product A</td><td>15,645,242</td><td>10,432,542</td><td>2,425,432</td><td>2,787,268</td></tr>
 *       <tr><td>Product B</td><td>22,642,358</td><td>4,325,421</td><td>4,325,321</td><td>13,991,616</td></tr>
 *       <tr><td>Product C</td><td>21,432,330</td><td>2,427,431</td><td>6,443,234</td><td>12,561,665</td></tr>
 *    </tbody>
 * </table>
 * The data model for the donut chart store should be refined with fields: productName, 
 * sold and region. The rows returning from the store should look like:
 * <table>
 *    <tbody>
 *       <tr> <td>productName</td> <td>sold</td> <td>region</td> </tr>
 *       <tr> <td>Product A</td> <td>10,432,542</td> <td>Europe</td> <td></td> </tr>
 *       <tr> <td>Product A</td> <td>2,425,432</td> <td>Asia</td> <td></td> </tr>
 *       <tr> <td>Product A</td> <td>2,787,268</td> <td>Americas</td> <td></td> </tr>
 *       <tr> <td>Product B</td> <td>4,325,421</td> <td>Europe</td> <td></td> </tr>
 *       <tr> <td>Product B</td> <td>4,325,321</td> <td>Asia</td> <td></td> </tr>
 *    </tbody>
 * </table>
 The series definition for the donut chart should look like this:
 *     series: [{
 *        // Inner pie series
 *        type: 'pie',
 *        categoryField: 'productName',
 *        dataField: 'sold',
 *        size: '60%',
 *        totalDataField: true
 *     }, {
 *        // Outer pie series
 *        type: 'pie',
 *        categoryField: 'region',
 *        dataField: 'sold',
 *        innerSize: '60%',
 *        size: '75%'
 *     }]
 * The *totalDataField* informs the first series to take the sum of *dataField* (sold) 
 * on entries with the same *categoryField* value, whereas the second series displays 
 * a section on each region (i.e. each record). The *innerSize* is just the Highcharts 
 * option to make the outer pie series appear as ring form.
 *
 * If you want to have a fix set of colours in the outer ring along each slice, then 
 * you can create an extra field in your store for the color code and use the 
 * *colorField* option to map the field.
 */
Ext.define('Chart.ux.Highcharts.PieSerie', {
    extend : 'Chart.ux.Highcharts.Serie',
    alternateClassName: [ 'highcharts.pie' ],
    type : 'pie',

    /***
     * @cfg xField
     * @hide
     */

    /***
     * @cfg yField
     * @hide
     */

    /***
     * @cfg dataIndex
     * @hide
     */

    /**
     * @cfg {String} categorieField
     * the field name mapping to store records for pie category data 
     */
    categorieField : null,

    /**
     * @cfg {Boolean} totalDataField
     * See above. This is used for producing donut chart. Bascially informs
     * getData method to take the total sum of dataField as the data point value
     * for those records with the same matching string in the categorieField.
     */
    totalDataField : false,

    /**
     * @cfg {String} dataField
     * the field name mapping to store records for value data 
     */
    dataField : null,

    /***
     * @cfg {Boolean} useTotals
     * use the total value of a categorie of all the records as a data point
     */
    useTotals : false,

    /***
     * @cfg {Array} columns
     * a list of category names that match the record fields
     */
    columns : [],

    constructor : function(config) {
        this.callParent(arguments);
        if(this.useTotals) {
            this.columnData = {};
            var length = this.columns.length;
            for(var i = 0; i < length; i++) {
                this.columnData[this.columns[i]] = 100 / length;
            }
        }
    },

    //private
    addData : function(record) {
        for(var i = 0; i < this.columns.length; i++) {
            var c = this.columns[i];
            this.columnData[c] = this.columnData[c] + record.data[c];
        }
    },

    //private
    update : function(record) {
        for(var i = 0; i < this.columns.length; i++) {
            var c = this.columns[i];
            if(record.modified[c])
                this.columnData[c] = this.columnData[c] + record.data[c] - record.modified[c];
        }
    },

    //private
    removeData : function(record, index) {
        for(var i = 0; i < this.columns.length; i++) {
            var c = this.columns[i];
            this.columnData[c] = this.columnData[c] - record.data[c];
        }
    },

    //private
    clear : function() {
        for(var i = 0; i < this.columns.length; i++) {
            var c = this.columns[i];
            this.columnData[c] = 0;
        }
    },

    /***
     * As the implementation of pie series is quite different to other series types,
     * it is not recommended to override this method
     */
    getData : function(record, seriesData) {

        var _this = (Chart.ux.Highcharts.sencha.product == 't') ? this.config : this;

        // Summed up the category among the series data
        if(this.totalDataField) {
            var found = null;
            for(var i = 0; i < seriesData.length; i++) {
                if(seriesData[i].name == record.data[_this.categorieField]) {
                    found = i;
                    seriesData[i].y += record.data[_this.dataField];
                    break;
                }
            }
            if(found === null) {
                if (this.colorField && record.data[_this.colorField]) {
                    seriesData.push({
                        name: record.data[_this.categorieField],
                        y: record.data[_this.dataField],
                        color: record.data[_this.colorField],
                        record: this.bindRecord ? record : null,
                        events: this.dataEvents
                    });
                } else {
                    seriesData.push({
                        name: record.data[_this.categorieField],
                        y: record.data[_this.dataField],
                        record: this.bindRecord ? record : null,
                        events: this.dataEvents
                    });
                }
                i = seriesData.length - 1;
            }
            return seriesData[i];
        }

        if(this.useTotals) {
            this.addData(record);
            return [];
        }

        if (this.colorField && record.data[this.colorField]) {
            return {
                name: record.data[_this.categorieField],
                y: record.data[_this.dataField],
                color: record.data[_this.colorField],
                record: this.bindRecord ? record : null,
                events: this.dataEvents
            };
        } else {
            return {
                name: record.data[_this.categorieField],
                y: record.data[_this.dataField],
                record: this.bindRecord ? record : null,
                events: this.dataEvents
            };
        }
    },

    getTotals : function() {
        var a = new Array();
        for(var i = 0; i < this.columns.length; i++) {
            var c = this.columns[i];
            a.push([c, this.columnData[c]]);
        }
        return a;
    },

    /***
     *  @private
     *  Build the initial data set if there are data already
     *  inside the store.
     */
    buildInitData:function(items, data) {
        // Summed up the category among the series data
        var record;
        var data = this.config.data = [];
        if (this.config.totalDataField) {
            for (var x = 0; x < items.length; x++) {
                record = items[x];
                this.getData(record,data);
            }
        } else {
            for (var x = 0; x < items.length; x++) {
                record = items[x];
                data.push(this.getData(record));
            }
        }
    }

});
