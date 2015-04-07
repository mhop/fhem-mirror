Datums- und Zeitauswahl durch "Datetimepicker" Widget an FHEM adaptiert.

Der picker kommt von http://xdsoft.net/jqplugins/datetimepicker/ und steht unter der MIT-Lizenz.
Das bedeutet in kurzform, das diese uneingeschränkt benutzt werden kann. Ideal für FHEM. :)

Das ganze ist einfach zu "installieren". Den Inhalt aus dem Zip-Archive in den "www\pgm2\" von FHEM kopieren.
Reload auf 01_FHEMWEB.pm und schon kann es verwendet werden. Das widget hat zwei verschiedene themes -> default
und dark und kann zusätzlich über das eigens mitgebrachte stylesheet angepasst werden.

Der Name ist "datetime" und die Parameter werden als eine Komma separierte Liste von Key:Value Paaren spezifiziert,
das gleiche wie beim knob widget. (theme:default,format:d.m.Y,lang:en, ... ) Eine komplette Liste ist unter der oben
angebenen URL zu finden.

Simple Beispiele:

define dateTimePickerInline dummy
attr dateTimePickerInline setList state:datetime,inline:true 
attr dateTimePickerInline webCmd state


define dateTimePickerPopUp dummy
attr dateTimePickerPopUp setList state:datetime
attr dateTimePickerPopUp webCmd state


define dateTimePickerOnlyTime dummy
attr dateTimePickerOnlyTime setList state:datetime,datepicker:false
attr dateTimePickerOnlyTime webCmd state


define dateTimePickerOnlyDate dummy
attr dateTimePickerOnlyDate setList state:datetime,timepicker:false
attr dateTimePickerOnlyDate webCmd state


Vorläufige default Einstellungen:

      lang:"de",
      i18n:{
        de:{
          months:[
          "Januar","Februar","März","April",
          "Mai","Juni","Juli","August",
          "September","Oktober","November","Dezember",
          ],
         dayOfWeek:[
          "So.", "Mo", "Di", "Mi",
          "Do", "Fr", "Sa.",
         ]
        }
      },
       theme:"dark",
       format:"d.m.Y H:i"