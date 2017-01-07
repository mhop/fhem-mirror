// $Id: fhemweb_doorpicalllist.js 9346 2015-10-02 19:30:04Z pahenning $

// This code is shamelessly lifted from fhemweb_fbcalllist by Markus Bloch
// Hopefully we can merge these into a more versatile joint effort
// Prof. Dr. Peter A. Henning

// Take away informid from table with attribute arg=doorpicalllist ??

$(function () {
    $("div[arg=doorpicalllist][informid]").each(function (index, obj) {
        name = $(obj).attr("dev");
        $(obj).parents('[informid="'+name+'"]').removeAttr("informid");
    });
});

function FX_processCallListUpdate(data)
{  
    var table = $(this).find("table.doorpicalllist").first();
    
    // clear the list if data starts with "clear"
    if(/^clear/.test(data))
    {
        // if the table isn't already empty
        if(!table.find("tr[name=empty]").length)
        {
            var tmp = data.split(",");
            
            table.find("tr[number]").remove();
            table.append("<tr align=\"center\" name=\"empty\"><td style=\"padding:10px;\" colspan=\""+tmp[1]+"\"><i>"+tmp[2]+"</i></td></tr>");  
        }
        return;    
    }
   
    // clear all lines greater than max-lines (e.g. after activate a filter statement)
    if(/^max-lines/.test(data))
    {
        var tmp = data.split(",");
        table.find("tr[number]").filter(function(index,obj) {return (parseInt($(obj).attr("number")) > parseInt(tmp[1]));}).remove();
        return;    
    }
   
    // else it's JSON data with row updates
    var json_data = jQuery.parseJSON(data)
   
    if(table.find("tr[number="+json_data.line+"]").length)
    {
         $.each(json_data, function (key, val) {
             
            if(key == "line")
            { return true; }
        
            FX_setCallListValue(table,json_data.line,key,val);
         });
    }
    else // add new tr row with the values)
    {
        // delete the empty tr row if it may exist
        table.find("tr[name=empty]").remove();
        
        var new_tr = '<tr align="center" number="'+json_data.line+'" class="'+((json_data.line % 2) == 1 ? "odd" : "even")+'">';
        var style = "style=\"padding-left:6px;padding-right:6px;\"";
        
        
         // create the corresponding <td> tags with the received data
        $.each(json_data, function (key, val) {
            if(key == "line")
            { return true; }
            new_tr += '<td name="'+key+'" '+style+'>'+val+'</td>';
         });
        
        new_tr += "</tr>";
        
        // insert new tr into table
        table.append(new_tr);
    }
}

function FX_setCallListValue(table,line,key,val)
{
    table.find("tr[number="+line+"] td[name="+key+"]").each(function(index, obj) {
       $(obj).html(val); 
    });
}

function FW_DoorpiCalllistCreate(elName, devName, vArr, currVal, set, params, cmd)
{
    if(vArr[0] == "doorpicalllist")
    {
        var newEl = $('div[informid="'+devName+'"]').get(0);

        newEl.setValueFn = FX_processCallListUpdate;

        return newEl;
    }
}

FW_widgets['doorpicalllist'] = {
  createFn:FW_DoorpiCalllistCreate
};
