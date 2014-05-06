function
FW_multipleSelChange(name, devName, vArr)
{
  if(vArr.length < 2 || vArr[0] != "multiple")
    return undefined;
  
  var o = new Object();
  o.newEl = document.createElement('input');
  o.newEl.type='text';
  o.newEl.size=30;
  o.qFn = 'FW_multipleSetSelected(qArg, "%")';
  o.qArg = o.newEl;
  o.newEl.setAttribute('onFocus', 'FW_multipleSelect(this)');
  o.newEl.setAttribute('allVals', vArr);
  o.newEl.setAttribute('readonly', 'readonly');
  return o;
}

function
FW_multipleSelect(el)
{
  loadLink("pgm2/jquery-ui.min.css");
  loadScript("pgm2/jquery.min.js", function(){
    loadScript("pgm2/jquery-ui.min.js", function() {

      var sel = $(el).val().split(","), selObj={};
      for(var i1=0; i1<sel.length; i1++)
        selObj[sel[i1]] = 1;

      var vArr = $(el).attr("allVals").replace(/#/g, " ").split(",");
      var table = "";
      for(var i1=1; i1<vArr.length; i1++) {
        var v = vArr[i1];
        table += '<tr>'+
          '<td><input name="'+v+'" type="checkbox"'+
                          (selObj[v] ? " checked" : "")+'/></td>'+
          '<td><label for="' +v+'">'+v+'</label></td></tr>';
        delete(selObj[v]);
      }

      $('body').append(
        '<div id="multidlg" style="display:none">'+
          '<table>'+table+'</table><input id="md_freeText" '+
                'value="'+Object.keys(selObj).join(',')+'"/>'+
        '</div>');

      $('#multidlg').dialog(
        { modal:true, closeOnEscape:false, maxHeight:$(window).height()*3/4,
          buttons:[
          { text:"Cancel", click:function(){ $('#multidlg').remove(); }},
          { text:"OK", click:function(){
            var res=[];
            if($("#md_freeText").val())
              res.push($("#md_freeText").val());
            $("#multidlg table input").each(function(){
              if($(this).prop("checked"))
                res.push($(this).attr("name"));
            });
            $(el).val(res.join(","));
            $('#multidlg').remove();
          }}]});
    });
  });
  return false;
}

function
FW_multipleSetSelected(el, val)
{
  if(typeof el == 'string')
    el = document.getElementById(el);
  el.value=val;
}


FW_widgets['multiple'] = {
  selChange:FW_multipleSelChange
};
