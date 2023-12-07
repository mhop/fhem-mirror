/* FTUI Plugin
 *
 * This widget "widget_forecast.js" was created to make use of the get html functionality of the 
 * SolarForecast Module by DS_Starter, see:
 * https://wiki.fhem.de/wiki/SolarForecast_-_Solare_Prognose_(PV_Erzeugung)_und_Verbrauchersteuerung
 * 
 * It was adapted from widget_smaportalspg.js which had:
 * Copyright (c) 2016 Mario Stephan <mstephan@shared-files.de>
 * originally created by Thomas Nesges,
 * Under MIT License (http://www.opensource.org/licenses/mit-license.php)
 *
 * Usage Example:
 *
 *			<li data-row="1" data-col="1" data-sizey="3" data-sizex="4">
 *			 <header>PV Forecast</header>
 *            <div class="cell">
 *              <div data-type="forecast" data-device="ForecastDevice" data-get="state" data-html="both"></div>
 *            </div>
 *			</li>
 *
 *
 * Versions:
 *  1.0.1	07.12.2023	get=state,html=both as default, compatibility to SolarForecast V.1.5.1 DS_Starter
 *  1.0.0	30.11.2023	initial version		stefanru
*/


"use strict";

function depends_forecast (){
    var deps = [];

	var userCSS = $('head').find("[href$='css/fhem-tablet-ui.css']");

	if (userCSS.length)
		userCSS.before('<link rel="stylesheet" href="'+ ftui.config.basedir + 'css/ftui_forecast.css" type="text/css" />')
	else
		$('head').append('<link rel="stylesheet" href="'+ ftui.config.basedir + 'css/ftui_forecast.css" type="text/css" />');
			
    return deps;
};

var Modul_forecast = function () {

    function init_attr(elem) {
        elem.initData('get', 'state');
		elem.initData('html', 'both');
        elem.initData('max-update', 2);

        me.addReading(elem, 'get');
    }

    //usage of "function init()" from Modul_widget()

    function update(dev, par) {

        me.elements.filterDeviceReading('get', dev, par)
            .each(function (index) {
                var elem = $(this);
                var value = elem.getReading('get').val;
                //console.log('forecast:',value);
                if (ftui.isValid(value)) {
                    var dNow = new Date();

                    var lUpdate = elem.data('lastUpdate') || null;
                    var lMaxUpdate = parseInt(elem.data('max-update'));
                    if (isNaN(lMaxUpdate) || (lMaxUpdate < 1))
                        lMaxUpdate = 10;

                    //console.log('forecast update time stamp diff : ', dNow - lUpdate, '   param maxUPdate :' + lMaxUpdate + '    : ' + $(this).data('max-update') );
                    lUpdate = (((dNow - lUpdate) / 1000) > lMaxUpdate) ? null : lUpdate;
                    if (lUpdate === null) {
                        //console.log('forecast DO update' );
                        elem.data('lastUpdate', dNow);
                        var cmd = [ 'get', elem.data('device'), 'ftui ' + elem.data('html') ].join(' ');
                        ftui.log('forecast update', dev, ' - ', cmd);
                        
                        ftui.sendFhemCommand(cmd)
                            .done(function (data, dev) {
                            //console.log('forecast received update for dynamic html : ', $(this) );
                            elem.html(data);
                        });
                    }
                }
            });
    }

    // public
    // inherit all public members from base class
    var me = $.extend(new Modul_widget(), {
        //override or own public members
        widgetname: 'forecast',
        init_attr: init_attr,
        update: update,
    });

    return me;
};