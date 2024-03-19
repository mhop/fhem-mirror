
"use strict";

var Modul_automowerconnect = function () {

  function init () {

    me.elements = $('div[data-type="'+me.widgetname+'"]');
    me.elements.each(function(index) {

      var elem = $(this);  
      elem.initData('get', 'mower_wsEvent');
      me.addReading(elem, 'get');
      var cmd = [ 'get', elem.data('device'), "html" ].join(' ');
      ftui.log('automowerconnect init map', elem.data('device'), ' - ', cmd);
      
      ftui.sendFhemCommand(cmd)
          .done(function (data, dev) {
            elem.html(data);
      });

    });
  };

  // mandatory function, get called after start up once and on every FHEM poll
  function update(device, par) {

    me.elements.filterDeviceReading('get', device, par)
      .each(function (index) {
          var elem = $(this);
          var value = elem.getReading('get').val;
          //console.log('automowerconnect:',value);
          if (ftui.isValid(value)) {

            AutomowerConnectUpdateJsonFtui ( elem.data('jsonurl') );

          }
      });
  }
  // public
  // inherit members from base class
  var me = $.extend(new Modul_widget(), {
      //override members
      widgetname: 'automowerconnect',
      init:init,
      update:update,
  });

    return me;
};

