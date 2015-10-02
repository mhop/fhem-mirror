// $Id$

// WORKAROUND - should be removed if a more suitable solution is found
// remove all similar informid's in all parent elements to ensure further updates.
//
// neccessary if general attribute "group" is set.
$(function () {
    $("div[arg=fbcalllist][informid]").each(function (index, obj) {
        name = $(obj).attr("dev");
        $(obj).parents('[informid="'+name+'"]').removeAttr("informid");
    });
});

function FW_processCallListUpdate(data)
{
    var table = $(this).find("table.fbcalllist").first();
    
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
        
            FW_setCallListValue(table,json_data.line,key,val);
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

function FW_setCallListValue(table,line,key,val)
{
    table.find("tr[number="+line+"] td[name="+key+"]").each(function(index, obj) {
       $(obj).html(val); 
    });
}

function FW_FbCalllistCreate(elName, devName, vArr, currVal, set, params, cmd)
{
    if(vArr[0] == "fbcalllist")
    {
        var newEl = $('div[informid="'+devName+'"]').get(0);

        newEl.setValueFn = FW_processCallListUpdate;

        return newEl;
    }
}

FW_widgets['fbcalllist'] = {
  createFn:FW_FbCalllistCreate
};
