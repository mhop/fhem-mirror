FW_version["todoist.js"] = "$Id$";

if (typeof todoist_checkVar === 'undefined') {
  
  var todoist_checkVar=1;
  
  var req = new XMLHttpRequest();
  req.open('GET', document.location, false);
  req.send(null);
  var csrfToken = req.getResponseHeader('X-FHEM-csrfToken');
  
  var todoist_icon={};
  
  var todoist_svgPrefix='<svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg"><path ';
  
  todoist_icon.ref=todoist_svgPrefix+'d="M440.935 12.574l3.966 82.766C399.416 41.904 331.674 8 256 8 134.813 8 33.933 94.924 12.296 209.824 10.908 217.193 16.604 224 24.103 224h49.084c5.57 0 10.377-3.842 11.676-9.259C103.407 137.408 172.931 80 256 80c60.893 0 114.512 30.856 146.104 77.801l-101.53-4.865c-6.845-.328-12.574 5.133-12.574 11.986v47.411c0 6.627 5.373 12 12 12h200.333c6.627 0 12-5.373 12-12V12c0-6.627-5.373-12-12-12h-47.411c-6.853 0-12.315 5.729-11.987 12.574zM256 432c-60.895 0-114.517-30.858-146.109-77.805l101.868 4.871c6.845.327 12.573-5.134 12.573-11.986v-47.412c0-6.627-5.373-12-12-12H12c-6.627 0-12 5.373-12 12V500c0 6.627 5.373 12 12 12h47.385c6.863 0 12.328-5.745 11.985-12.599l-4.129-82.575C112.725 470.166 180.405 504 256 504c121.187 0 222.067-86.924 243.704-201.824 1.388-7.369-4.308-14.176-11.807-14.176h-49.084c-5.57 0-10.377 3.842-11.676 9.259C408.593 374.592 339.069 432 256 432z"/></svg>';
  todoist_icon.del=todoist_svgPrefix+'d="M0 84V56c0-13.3 10.7-24 24-24h112l9.4-18.7c4-8.2 12.3-13.3 21.4-13.3h114.3c9.1 0 17.4 5.1 21.5 13.3L312 32h112c13.3 0 24 10.7 24 24v28c0 6.6-5.4 12-12 12H12C5.4 96 0 90.6 0 84zm416 56v324c0 26.5-21.5 48-48 48H80c-26.5 0-48-21.5-48-48V140c0-6.6 5.4-12 12-12h360c6.6 0 12 5.4 12 12zm-272 68c0-8.8-7.2-16-16-16s-16 7.2-16 16v224c0 8.8 7.2 16 16 16s16-7.2 16-16V208zm96 0c0-8.8-7.2-16-16-16s-16 7.2-16 16v224c0 8.8 7.2 16 16 16s16-7.2 16-16V208zm96 0c0-8.8-7.2-16-16-16s-16 7.2-16 16v224c0 8.8 7.2 16 16 16s16-7.2 16-16V208z"/></svg>';
  todoist_icon.loading='<svg xmlns:svg="http://www.w3.org/2000/svg" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.0" viewBox="0 0 128 128" xml:space="preserve"><g transform="rotate(-32.1269 64 64)"><path d="M78.75 16.18V1.56a64.1 64.1 0 0 1 47.7 47.7H111.8a49.98 49.98 0 0 0-33.07-33.08zM16.43 49.25H1.8a64.1 64.1 0 0 1 47.7-47.7V16.2a49.98 49.98 0 0 0-33.07 33.07zm33.07 62.32v14.62A64.1 64.1 0 0 1 1.8 78.5h14.63a49.98 49.98 0 0 0 33.07 33.07zm62.32-33.07h14.62a64.1 64.1 0 0 1-47.7 47.7v-14.63a49.98 49.98 0 0 0 33.08-33.07z" fill-opacity="1"/><animateTransform attributeName="transform" type="rotate" from="0 64 64" to="-90 64 64" dur="1800ms" repeatCount="indefinite"/></g></svg>';

  function todoist_encodeParm(oldVal) {
      var newVal;
      newVal = oldVal.replace(/\$/g, '\\%24');
      newVal = newVal.replace(/"/g, '%27');
      newVal = newVal.replace(/#/g, '%23');
      newVal = newVal.replace(/\+/g, '%2B');
      newVal = newVal.replace(/&/g, '%26');
      newVal = newVal.replace(/'/g, '%27');
      newVal = newVal.replace(/=/g, '%3D');
      newVal = newVal.replace(/\?/g, '%3F');
      newVal = newVal.replace(/\|/g, '%7C');
      newVal = newVal.replace(/\s/g, '%20');
      return newVal;
  };

  function todoist_dialog(message,title) {
      if (typeof title === 'undefined') title="Message";
      $('<div></div>').appendTo('body').html('<div>' + message + '</div>').dialog({
          modal: true, title: 'Todoist '+title, zIndex: 10000, autoOpen: true,
          width: 'auto', resizable: false,
          buttons: {
              OK: function () {
                  $(this).dialog("close");
              }
          },
          close: function (event, ui) {
              $(this).remove();
          }
      });
      setTimeout(function(){
        $('.ui-dialog').remove();
      },10000);
  };
  
  function todoist_refreshTable(name,sortit) {
    var i=1;
    $('#todoistTable_' + name).find('tr.todoist_data').each(function() {
      // order
      var tid = $(this).attr("data-line-id");
      $(this).removeClass("odd even");
      if (i%2==0) $(this).addClass("even");
      else $(this).addClass("odd");
      if (typeof sortit != 'undefined') todoist_sendCommand('set ' + name + ' updateTask ID:'+ tid + ' order="' + i + '"');
      i++;
    });
    if (i!=1) $('#todoistTable_' + name).find("tr.todoist_ph").hide();
    if (i==1) $('#todoistTable_' + name).find("tr.todoist_ph").show();
    refreshInput(name);
    refreshInputs(name);
    todoist_removeLoading(name);
  }
  
  function todoist_refreshTableWidth() {
    $('.sortable').each(function() {
      $(this).css('width','');
    });
  }
  
  function todoist_reloadTable(name,val) {
    var todoist_small = (screen.width < 480 || screen.height < 480);
    $('#todoistTable_' + name).find('tr.todoist_data').remove();
    $('#todoistTable_' + name).find('#newEntry_'+name).parent().parent().before(val);
    todoist_refreshTable(name);
    if (!todoist_small) $('#newEntry_' + name).focus();
  }
  
  function refreshInputs(name) {
    $('#todoistTable_' + name).find('tr.todoist_data').find('td.todoist_input').find('input[type=text]').each(function() {
      var w = $(this).prev('span').width()+5;
      $(this).width(w); 
    });
  }
  
  function refreshInput(name) {
    $('#newEntry_'+name).width(0);
    var w = $('#newEntry_'+name).parent('td').width()-4;
    $('#newEntry_'+name).width(w); 
  }

  function todoist_sendCommand(cmd) {
    var name = cmd.split(" ")[1];
    todoist_addLoading(name);
    var location = document.location.pathname;
    if (location.substr(location.length -1, 1) == '/') {
        location = location.substr(0, location.length -1);
    }
    var url = document.location.protocol + "//" + document.location.host + location;
    FW_cmd(url + '?XHR=1&fwcsrf=' + csrfToken + '&cmd.' + name + '=' + cmd);
  }
  
  function todoist_addLoading(name) {
    if ( $('.todoist_devType_' + name).find('.todoist_loadingDiv').length ) {
      $('.todoist_devType_' + name).find('.todoist_loadingDiv').remove();
    }
    else {
      $('.todoist_devType_' + name).append('<div class="todoist_icon todoist_loadingDiv">' + todoist_icon.loading + '</div>');
      setTimeout(function(){ 
        todoist_removeLoading(name);
      }, 10000);
    }
  }
  
  function todoist_removeLoading(name) {
    $('.todoist_devType_' + name).find('.todoist_loadingDiv').remove();
  }

  function todoist_ErrorDialog(name,text,title) {
    todoist_dialog(text,title);
    todoist_removeLoading(name);
  }

  function todoist_removeLine(name,id) {
    var i=1;
    $('#todoistTable_' + name).find('tr.todoist_data').each(function() {
      var tid = $(this).attr("data-line-id");
      if (tid==id) $(this).remove();
      else {
        $(this).removeClass("odd even");
        if (i%2==0) $(this).addClass("even");
        else $(this).addClass("odd");
        i++;
      }
    });
    if (i==1) $('#todoistTable_' + name).find("tr.todoist_ph").show();
    todoist_refreshTable(name);
    todoist_getSizes();
  }

  function todoist_addLine(name,id,title) {
    var lastEl=$('#todoistTable_' + name).find('tr').last();
    var prevEl=$(lastEl).prev('tr');
    var cl="odd";
    if (prevEl != 'undefined') {
      cl = $(prevEl).attr('class');
      if (cl=="odd") cl="even";
      else cl="odd"
    }
    $(lastEl).before('<tr id="'+ name + "_" + id +'" data-data="true" data-line-id="' + id +'" class="sortit todoist_data ' + cl +'">\n' +
              ' <td class="col1  todoist_col1">\n'+
              '   <div class=\"todoist_move\"></div>\n'+
              '   <input title=\"' + todoist_tt.check + '\" class="todoist_checkbox_' + name + '" type="checkbox" id="check_' + id + '" data-id="' + id + '" />\n'+
              ' </td>\n' +
              ' <td class="col1 todoist_input">\n'+
              '   <span class="todoist_task_text" data-id="' + id + '">' + title + '</span>\n'+
              '   <input type="text" data-id="' + id + '" style="display:none;" class="todoist_input_' + name +'" value="' + title + '" />'+
              ' </td>\n' +
              ' <td class="col2 todoist_delete">\n' +
              '   <a title=\"' + todoist_tt.delete + '\" href="#" class="todoist_delete_' + name + '" data-id="' + id +'">\n'+
              '     x\n'+
              '   </a>\n'+
              ' </td>\n'+
              '</tr>\n'
    );
    $('#todoistTable_' + name).find("tr.todoist_ph").hide();
    todoist_getSizes();
    todoist_refreshTable(name);
  }
  
  function resizable (el, factor) {
    var int = Number(factor) || 7.7;
    function resize() {el.style.width = ((el.value.length+1) * int) + 'px'}
    var e = 'keyup,keypress,focus,blur,change'.split(',');
    for (var i in e) el.addEventListener(e[i],resize,false);
    resize();
  }

  
  function todoist_getSizes() {
    var height = 0;
    var width = 0;
    $('.sortable .sortit').each(function() {
      var tHeight = $(this).outerHeight();
      if (tHeight > height) height = tHeight;
    });
    $('.sortable').css('max-height',height).css('height',height);
  }
  
  function todoist_addHeaders() {
    $("<div class='todoist_refresh todoist_icon' title='" + todoist_tt.refreshList + "'> </div>").appendTo($('.todoist_devType')).html(todoist_icon.ref);
    $("<div class='todoist_deleteAll todoist_icon' title='" + todoist_tt.clearList + "'> </div>").appendTo($('.todoist_devType')).html(todoist_icon.del);
  }

  $(document).ready(function(){
    todoist_getSizes();
    todoist_addHeaders();
    $('.todoist_name').each(function() {
      var name = $(this).val();
      todoist_refreshTable(name);
      
      $('.todoist_devType_' + name).on('click','div.todoist_deleteAll',function(e) {
        if (confirm(todoist_tt.clearconfirm)) {
          todoist_sendCommand('set ' + name + ' clearList');
        }
      });
      $('.todoist_devType_' + name).on('click','div.todoist_refresh',function(e) {
        todoist_sendCommand('set ' + name + ' getTasks');
      });
      
      $('#todoistTable_' + name).on('mouseover','.sortit',function(e) {
        $(this).find('div.todoist_move').addClass('todoist_sortit_handler');
      });
      $('#todoistTable_' + name).on('mouseout','.sortit',function(e) {
        $(this).find('div.todoist_move').removeClass('todoist_sortit_handler');
      });
      $('#todoistTable_' + name).on('blur keypress','#newEntry_' + name,function(e) {
        if (e.type!='keypress' || e.which==13) {
          e.preventDefault();
          var v=todoist_encodeParm($(this).val());
          if (v!="") {
            todoist_sendCommand('set '+ name +' addTask ' + v);
            $(this).val("");
          }
        }
      });
      $('#todoistTable_' + name).on('click','input[type="checkbox"]',function(e) {
        var val=$(this).attr('checked');
        if (!val) {
          var id=$(this).attr('data-id');
          todoist_sendCommand('set ' + name + ' closeTask ID:'+ id);
        }
      });
      $('#todoistTable_' + name).on('click','a.todoist_delete_'+name,function(e) {
        if (confirm(todoist_tt.delconfirm)) {
          var id=$(this).attr('data-id');
          todoist_sendCommand('set ' + name + ' deleteTask ID:'+ id);
        }
        return false;
      });
      $('#todoistTable_' + name).on('click','span.todoist_task_text',function(e) {
        var id = $(this).attr("data-id");
        var val=$(this).html();
        var width=$(this).width()+20;
        $(this).hide();
        $("input[data-id='" + id +"']").show().focus().val("").val(val);
      });
      $('#todoistTable_' + name).on('blur keypress','input.todoist_input_'+name,function(e) {
        if (e.type!='keypress' || e.which==13) {
          e.preventDefault();
          var val = $(this).val();
          
          var comp = $(this).prev().html();
          var id = $(this).attr("data-id");
          var val = $(this).val();
          $(this).hide();
          $("span.todoist_task_text[data-id='" + id +"']").show();
          if (val != "" && comp != val) {
            $("span.todoist_task_text[data-id='" + id +"']").html(val);
            todoist_sendCommand('set ' + name + ' updateTask ID:'+ id + ' title="' + val + '"');
          }
          
          if (val == "" && e.which==13) {
            if (confirm('Are you sure?')) {
              $('#newEntry_' + name).focus();
              todoist_sendCommand('set ' + name + ' deleteTask ID:'+ id);
            }
          }
          todoist_refreshTable(name);
        }
        if (e.type=='keypress') {
          resizable(this,7);
          refreshInput(name);
        }
      });
    });
    var fixHelper = function(e, ui) {  
      ui.children().each(function() {  
      console.log(e);
        $(this).width($(this).width());  
      });  
      return ui;  
    };
    $( ".todoist_table table.sortable" ).sortable({
      //axis: 'y',
      revert: true,
      items: "> tbody > tr.sortit",
      handle: ".todoist_sortit_handler",
      forceHelperSize: true,
      placeholder: "sortable-placeholder",
      connectWith: '.todoist_table table.sortable',
      helper: fixHelper,
      start: function( event, ui ) { 
        var width = ui.item.innerWidth();
        var height = ui.item.innerHeight();
        ui.placeholder.css("width",width).css("height",height); 
      },
      stop: function (event,ui) {
        var parent = ui.item.parent().parent();
        var id = $(parent).attr('id');
        var name = id.split(/_(.+)/)[1];
        if (ui.item.attr('data-remove')==1) ui.item.remove();
        todoist_refreshTable(name,1);
        todoist_refreshTableWidth();
      },
      remove: function (event,ui) {
        var id=ui.item.attr('data-line-id');
        var tid = ui.item.attr('id');
        var nameHT = tid.split("_");
        var lastVal = nameHT.pop();       // Get last element
        var nameH = nameHT.join("_"); 
        todoist_sendCommand('set ' + nameH + ' deleteTask ID:'+ id);
      },
      over: function (event,ui) {
        var width = ui.item.innerWidth();
        var height = ui.item.innerHeight();
        var hwidth = ui.placeholder.innerWidth();
        if (width>hwidth) ui.placeholder.parent().parent().css("width",width).css("height",height); 
        if (width<hwidth) ui.item.css("width",hwidth).css("height",height); 
      },
      out: function (event,ui) { 
        var parent = ui.sender;
        var id = $(parent).attr('id');
        var name = id.split(/_(.+)/)[1];
        $(parent).css('width','');
        refreshInput(name);
        todoist_refreshTable(name);
        todoist_refreshTableWidth();
      },
      receive: function (event,ui) {
        var parent = ui.item.parent().parent();
        var id = ui.item.attr('data-line-id');
        var tid = parent.attr('id');
        var nameR = tid.split(/_(.+)/)[1];
        var value = ui.item.find('span').html();
        todoist_sendCommand('set '+ nameR +' addTask ' + value);
        ui.item.attr('data-remove','1');
      }
    }).disableSelection();
  });
}