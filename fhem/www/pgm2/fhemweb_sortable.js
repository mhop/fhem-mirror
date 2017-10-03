FW_version["fhemweb_sortable.js"] = "$Id$";

// Wrapper for the widget.
FW_widgets['sortable'] = { createFn:FW_sortableCreate, };
FW_widgets['sortable-strict'] = { createFn:FW_sortableCreate, };
FW_widgets['sortable-given'] = { createFn:FW_sortableCreate, };


function
FW_sortableCreate(elName, devName, vArr, currVal, set, params, cmd)
{
  if((vArr.length < 2 && (vArr[0] == "sortable-strict" || vArr[0] == "sortable-given")) || (vArr[0]!="sortable" && vArr[0]!="sortable-strict" && vArr[0]!="sortable-given") || (params && params.length)) return undefined;
  
  var newEl = $('<input type="text" size="30" readonly>').get(0);
  
  if(currVal)
    $(newEl).val(currVal);
  if(elName)
    $(newEl).attr("name", elName);
  
  newEl.setValueFn = function(arg){ $(newEl).val(arg) };

  // replace # with space 
  for(var i1=1; i1<vArr.length; i1++)
    vArr[i1] = vArr[i1].replace(/#/g, " ");

    $(newEl).focus(function(){
    var sel = $(newEl).val().split(","), selObj={};
  
    // create the whole table output
    var table = FW_sortableCreateTable(vArr, sel)

    var strict = (vArr[0] == "sortable-strict" || vArr[0] == "sortable-given");
    
    $('body').append(
      '<div id="sortdlg" style="display:none">'+
      '<table align=center">'+
      table+
      (!strict ? '<tr><td colspan="2" align="center"><br><input type="text" id="sort_new_item">&nbsp;&nbsp;<a href="#" id="sort_add_new_item">add</a></td></tr>' : '')+
      '<tr><td colspan="2" align="center"><br>use drag & drop to sort items</td></tr>'+
      '</table>'+
      '</div>');
     
    // make source list sortable
    $( "ul.sortable-src").sortable({
      connectWith: "ul.sortable-dest",
      placeholder: "ui-state-highlight",
      receive: function(event, ui) { FW_sortableSrcListSort(); },
      stop: function(event, ui) { FW_sortableSrcListSort(); }
    });
    
    
    // make destination list sortable
    $("ul.sortable-dest").sortable({
      connectWith: "ul.sortable-dest",
      placeholder: "ui-state-highlight",
      stop: function(event, ui) { FW_sortableUpdateLinks(); },
      create: function(event, ui) { FW_sortableUpdateLinks(); },
      receive: function(event, ui) { FW_sortableUpdateLinks(); }
    });
    
    // add click handler for item removal in destination list
    $('ul.sortable-dest').on("click", "a.sort-item-delete", function(event) {
        var el = $(this).parents("li");
        if(el.attr("key") !== undefined) {
          el.appendTo("ul.sortable-src");
          el.html(el.attr("value"));
        }
        else el.remove();
        
        FW_sortableSrcListSort();
        FW_sortableUpdateLinks();
        return false;
    });
    
    // add click handler for quick add by click on list item in source list
    $('ul.sortable-src').on("click", "li.sortable-item", function(event) {
        $(this).appendTo("ul.sortable-dest");
        FW_sortableUpdateLinks();
    });
     
    // add click handler for inserting a new custom value to destination list
    $('a#sort_add_new_item').click(function () {
        
        var new_val = $('input#sort_new_item').val().split(',');
        $.each(new_val, function(index,value) {
            var v = value.trim();
            if(v.length)
            {
                $('ul.sortable-dest').append('<li class="sortable-item ui-state-default" value="'+v+'">'+v+'</li>');
                $('input#sort_new_item').val('');
                FW_sortableUpdateLinks();
            }
        });
        return false;
    });
        
    // create the dialog
    $('#sortdlg').dialog(
      { modal:true, closeOnEscape:false, maxHeight:$(window).height()*3/4, width:'auto', height:'auto',
        buttons:[
        { text:"Cancel", click:function(){ $('#sortdlg').remove(); } },
        { text:"OK", click:function(){
          var res=[];
          $("#sortdlg ul.sortable-dest li.sortable-item").each(function(){
              res.push($(this).attr("value"));
          });
          $('#sortdlg').remove();
          $(newEl).val(res.join(","));
          if(cmd)
            cmd(res.join(","));
        }}]}).focus();
  });
  return newEl;
}

// sort all items in source list according to their original given order
function
FW_sortableSrcListSort()
{
    $('ul.sortable-src li.sortable-item').sort(function (a, b) {
        return (($(a).attr("key") < $(b).attr("key")) ? -1 : ($(a).attr("key") > $(b).attr("key")) ? 1 : 0);
    }).appendTo("ul.sortable-src");
}

// add index number and deletion link to all items in destination list
function
FW_sortableUpdateLinks()
{
    $("ul.sortable-dest li.sortable-item").each(function () {   
        $(this).html(($(this).index() + 1)+'. '+$(this).attr("value")+($(this).attr("deletable") == "false" ? '' : '<span class="sort-item-delete-link"><a href="#" class="sort-item-delete"><span class="ui-icon ui-icon-closethick" style="display:table-cell; vertical-align:bottom;"></span></a></span>'));
    });
}

// create the inital html output
function
FW_sortableCreateTable(elements, selected)
{
    var table = '<tr valign="top">';
    if(elements[0] == "sortable"  || elements[0] == "sortable-strict")
    {
        if(elements.length > 1)
        {
         
            table += '<td align="center">Available<br>';
            table += '<ul class="sortable-src">';
            
            for(var i=1; i<elements.length; i++) {
                if($.inArray(elements[i], selected) == -1)
                    table+='<li class="sortable-item ui-state-default" key="'+i+'" value="'+elements[i]+'">'+elements[i]+'</li>';
            }
            
            table += '</ul></td>';
        }
        
        table += '<td align="center"><b>Selected</b><ul class="sortable-dest">';   
      
        for(var i=0; i<selected.length; i++) {
            if(selected[i].trim().length && (elements[0] == "sortable"  || (elements[0] == "sortable-strict" && $.inArray(selected[i], elements) != -1)))
                table+='<li class="sortable-item ui-state-default" '+($.inArray(selected[i], elements) != -1 ? 'key="'+$.inArray(selected[i], elements)+'" ' : '')+'value="'+selected[i]+'">'+selected[i]+'</li>';
        }
    }
    else if(elements[0] == "sortable-given")
    {
        table += '<td>&nbsp;</td><td align="center"><ul class="sortable-dest">';   
      
        if(selected.length > 1)
        {
            for(var i=0; i<selected.length; i++) {
                if(selected[i].trim().length) 
                table+='<li class="sortable-item ui-state-default" deletable="false" value="'+selected[i]+'">'+selected[i]+'</li>';
            }
        }
        else
        {   
            for(var i=1; i<elements.length; i++) {
                if(elements[i].trim().length) 
                table+='<li class="sortable-item ui-state-default" deletable="false" value="'+elements[i]+'">'+elements[i]+'</li>';
            }
        }
        
    }
    table += '</ul></td></tr>';
    
    return table;
}


/*
=pod

=begin html

  <li>:sortable,val1,val2,... - create a new list from the elements of the
      given list, can add new elements by entering a text, or delete some from
      the list. This new list can be sorted via drag &amp; drop. The result is
      a comma separated list. </li>

  <li>:sortable-strict,val1,val2,... - it behaves like :sortable, without the
      possibility to enter text.</li>

  <li>:sortable-given,val1,val2,... - the specified list can be sorted via drag
      &amp; drop, no elements can be added or deleted.  </li>

=end html

=begin html_DE

  <li>:sortable,val1,val2,... - damit ist es m&ouml;glich aus den gegebenen
      Werten eine Liste der gew&uuml;nschten Werte durch Drag &amp; Drop
      zusammenzustellen. Die Reihenfolge der Werte kann dabei entsprechend
      ge&auml;ndert werden.  Es m&uuml;ssen keine Werte explizit vorgegeben
      werden, das Widget kann auch ohne vorgegebenen Werte benutzt werden.  Es
      k&ouml;nnen eigene Werte zur Liste hinzugef&uuml;gt und einsortiert
      werden.  Das Ergebnis ist Komma-separiert entsprechend aufsteigend
      sortiert.</li>

   <li>:sortable-strict,val1,val2,... - damit ist es m&ouml;glich aus den
      gegebenen Werten eine Liste der gew&uuml;nschten Werte durch Drag &amp;
      Drop zusammenzustellen. Die Reihenfolge der Werte kann dabei entsprechend
      ge&auml;ndert werden.  Es k&ouml;nnen jedoch keine eigenen Werte zur
      Liste hinzugef&uuml;gt werden.  Das Ergebnis ist Komma-separiert
      entsprechend aufsteigend sortiert.</li>

   <li>:sortable-given,val1,val2,... - damit ist es m&ouml;glich aus den
      gegebenen Werten eine sortierte Liste der gew&uuml;nschten Werte durch
      Drag & Drop zusammenzustellen. Es k&ouml;nnen keine Elemente
      gel&ouml;scht und hinzugef&uuml;gt werden. Es m&uuml;ssen alle gegeben
      Werte benutzt und entsprechend sortiert sein.  Das Ergebnis ist
      Komma-separiert entsprechend aufsteigend sortiert.</li>

=end html_DE

=cut
*/
