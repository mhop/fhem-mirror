# $Id$
##############################################################################
#
#     98_Heating_Control.pm
#     written by Dietmar Ortmann
#     modified by Tobias Faust
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;
use strict;
use warnings;
use POSIX;

##################################### 
sub Heating_Control_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "Heating_Control_Define";
  $hash->{UndefFn} = "Heating_Control_Undef";
  $hash->{GetFn}   = "Heating_Control_Get";
  $hash->{UpdFn}   = "Heating_Control_Update";
  $hash->{AttrList}= "disable:0,1 windowSensor ".
                        $readingFnAttributes;
}
################################################################################
sub Heating_Control_Get($@)
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  $hash->{LOCAL} = 1;
  delete $hash->{LOCAL};
  my $reading= $a[1];
  my $value;

  if(defined($hash->{READINGS}{$reading})) {
        $value= $hash->{READINGS}{$reading}{VAL};
  } else {
        return "no such reading: $reading";
  }
  return "$a[0] $reading => $value";
}
################################################################################
sub Heating_Control_Define($$)
{
  my ($hash, $def) = @_;

  my %longDays =  ( "de" => ["Sonntag",  "Montag","Dienstag","Mittwoch",  "Donnerstag","Freitag", "Samstag" ],
                    "en" => ["Sunday",   "Monday","Tuesday", "Wednesday", "Thursday",  "Friday",  "Saturday"],
                    "fr" => ["Dimanche", "Lundi", "Mardi",   "Mercredi",  "Jeudi",     "Vendredi","Samedi"  ]);
  my %shortDays = ( "de" => ["so","mo","di","mi","do","fr","sa"],
                    "en" => ["su","mo","tu","we","th","fr","sa"],
                    "fr" => ["di","lu","ma","me","je","ve","sa"]);

  my  @a = split("[ \t]+", $def);
 
  return "Usage: define <name> $hash->{TYPE} <device> <language> <switching times> <condition|command>"
     if(@a < 4);

  my $name       = shift @a;
  my $type       = shift @a;
  my $device     = shift @a;

  my @switchingtimes;
  my $conditionOrCommand = "";

  # ggf. language optional Parameter
  my $language   = shift @a;
  my $langRegExp = "(";
  foreach my $l (keys(%shortDays)) {
     $langRegExp .=  $l . "|";
  }
  $langRegExp =~ s/\|$//g;
  $langRegExp .= ")";
  if ($language =~  m/^$langRegExp$/g) {
     $hash->{LANGUAGE} = $language;
  } else {
     Log3 $hash, 3, "[$name] illegal language: $language, use one of $langRegExp" if (length() == 2);
     unshift (@a,$language)    if (length($language) != 2) ;
     $hash->{LANGUAGE} = "de";
  }
  $language = $hash->{LANGUAGE};

  # test if device is defined
  return "invalid Device, given Device <$device> not found" if(!$defs{$device});

  #Altlasten bereinigen
  delete($hash->{TIME_AS_PERL})              if($hash->{TIME_AS_PERL});
  delete($hash->{helper}{CONDITION})         if($hash->{helper}{CONDITION});
  delete($hash->{helper}{COMMAND})           if($hash->{helper}{COMMAND});
  delete($hash->{helper}{SWITCHINGTIMES})    if($hash->{helper}{SWITCHINGTIMES});
  delete($hash->{helper}{SWITCHINGTIME})     if($hash->{helper}{SWITCHINGTIME});
  foreach my $l (keys(%shortDays)) {
     for (my $w=0; $w<7; $w++) {
        delete($hash->{"PROFILE ".($w).": ".$longDays{$l}[$w]}) if($hash->{"PROFILE ".($w).": ".$longDays{$l}[$w]});
     }
  }

  for(my $i=0; $i<@a; $i++) {
    #pruefen auf Angabe eines Schaltpunktes
    my @t = split(/\|/, $a[$i]);
    my $anzahl = @t;
    if ( $anzahl >= 2 && $anzahl <= 3) {
      push(@switchingtimes, $a[$i]);
    } else {
      #der Rest ist das auzufuehrende Kommando/condition
      $conditionOrCommand = trim(join(" ", @a[$i..@a-1]));
      last;
    }
  }
  # wenn keine switchintime angegeben ist, dann Fehler
  Log3 $hash, 3, "no Switchingtime found in <$conditionOrCommand>, check first parameter"  if (@switchingtimes == 0);

  $hash->{NAME}           = $name;
  $hash->{DEVICE}         = $device;
  $modules{$hash->{TYPE}}{defptr}{$hash->{NAME}} = $hash;
  $hash->{helper}{SWITCHINGTIMES} = join(" ", @switchingtimes);
  if($conditionOrCommand =~  m/^\(.*\)$/g) {         #condition (*)
     $hash->{helper}{CONDITION} = $conditionOrCommand;
  } elsif(length($conditionOrCommand) > 0 ) {
     $hash->{helper}{COMMAND} = $conditionOrCommand;
  }

  # jetzt die switchingtimes und Tagesangaben verarbeiten.
  Heating_Control_ParseSwitchingProfile($hash, \@switchingtimes, \$shortDays{$language});

  # Profile sortiert aufbauen
  for (my $d=0; $d<=6; $d++) {
    foreach my $st (sort (keys %{ $hash->{helper}{SWITCHINGTIME}{$d} })) {
      my $para = $hash->{helper}{SWITCHINGTIME}{$d}{$st};
      $hash->{"PROFILE ".($d).": ".$longDays{$language}[$d]} .= sprintf("%s %s, ", substr ($st,0,5), $para);
    }
  }

  RemoveInternalTimer($hash);
  my $now    = time();
  InternalTimer ($now+30, "$hash->{TYPE}_Update", $hash, 0);

  if (defined($hash->{TIME_AS_PERL})) {
     my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
     my $midnight  =  $now + 24*3600 -(3600*$hour + 60*$min + $sec) + 10*60;
     InternalTimer ($midnight, "$hash->{TYPE}_UpdatePerlTime", $hash, 0);
  }

  readingsBeginUpdate  ($hash);
  readingsBulkUpdate   ($hash, "nextUpdate",   strftime("Heute, %H:%M:%S",localtime($now+30)));
  readingsBulkUpdate   ($hash, "nextValue",    "???");
  readingsBulkUpdate   ($hash, "state",        "waiting...");
  readingsEndUpdate    ($hash, defined($hash->{LOCAL} ? 0 : 1));

  return undef;
}
################################################################################
sub Heating_Control_ParseSwitchingProfile($$$) {
  my ($hash, $switchingtimes, $shortDays) = @_;

  my $name     = $hash->{NAME};
  my $language = $hash->{LANGUAGE};

  my %dayNumber=();
  my $daysRegExp = "(";
  for(my $idx=0; $idx<7; $idx++) {
        my $day = @{$$shortDays}[$idx];
        $dayNumber{$day} = $idx;
        $daysRegExp .=  $day . "|";
  }
  $daysRegExp =~ s/\|$//g;
  $daysRegExp .= ")";

  my (@st, @days, $daylist, $time, $para);
  for(my $i=0; $i<@{$switchingtimes}; $i++) {

    @st = split(/\|/, @{$switchingtimes}[$i]);
    if ( @st == 2) {
      $daylist = "1234567"; #jeden Tag/Woche ist vordefiniert
      $time    = $st[0];
      $para    = $st[1];
    } elsif ( @st == 3) {
      $daylist = lc($st[0]);
      $time    = $st[1];
      $para    = $st[2];
    }

    my %hdays=();

    # Angaben der Tage verarbeiten
    # Aufzaehlung 1234 ...
    if (      $daylist =~  m/^(\d){0,7}$/g) {

        $daylist =~ s/7/0/g;
        @days = split("", $daylist);
        @hdays{@days}=1;

    # Aufzaehlung Sa,So,... | Mo-Di,Do,Fr-Mo
    } elsif ($daylist =~  m/^($daysRegExp(,|-|$)){0,7}$/g   ) {

      my $oldDay = "", my $oldDel = "";
      for (;length($daylist);) {
        my $day   = substr($daylist,0,2,"");
        my $del   = substr($daylist,0,1,"");
        my @subDays;
        if ($oldDel eq "-" ){
           # von bis Angabe: Mo-Di
           my $low  = $dayNumber{$oldDay};
           my $high = $dayNumber{$day};
           if ($low <= $high) {
              @subDays = ($low .. $high);
           } else {
             #@subDays = ($dayNumber{so} .. $high, $low .. $dayNumber{sa});
              @subDays = (           00  .. $high, $low ..            06);
           }
           @hdays{@subDays}=1;
        } else {
           #einzelner Tag: Sa
           $hdays{$dayNumber{$day}} = 1;
        }
        $oldDay = $day;
        $oldDel = $del;
      }
    } else{
      return "invalid daylist in $name <$daylist> 123... | Sa,So,... | Mo-Di,Do,Fr-Mo | Su-Th,We"
    }

    @days = sort(SortNumber keys %hdays);

    # Zeitangabe verarbeiten.
    if($time =~  m/^\{.*\}$/g) {                              # Perlausdruck {*}
      $time = eval($time);                                    # must deliver HH:MM[:SS]
      $hash->{TIME_AS_PERL} = 1;
    }

    if      ($time =~  m/^[0-2][0-9]:[0-5][0-9]$/g) {         #  HH:MM
      $time .= ":00";                                         #  HH:MM:SS erzeugen
    } elsif ($time =~  m/^[0-2][0-9](:[0-5][0-9]){2,2}$/g) {  #  HH:MM:SS
      ;                                                       #  ok.
    } else {
      Log3 $hash, 1, "[$name] invalid time in $name <$time> HH:MM[:SS]"
    }

    for (my $d=0; $d<@days; $d++) {
      Log3 $hash, 5, "[$name] Switchingtime: @{$switchingtimes}[$i] : $days[$d] -> $time -> $para ";
      $hash->{helper}{SWITCHINGTIME}{$days[$d]}{$time} = $para;
    }
  }
}
################################################################################
sub Heating_Control_Undef($$) {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  delete $modules{$hash->{TYPE}}{defptr}{$hash->{NAME}};
  return undef;
}
################################################################################
sub Heating_Control_UpdatePerlTime($)
{
    my ($hash) = @_;
    Heating_Control_Define($hash, $hash->{NAME} . " " . $hash->{TYPE} . " " . $hash->{DEF} );
}
################################################################################
sub Heating_Control_Update($)
{
  my ($hash) = @_;
  my $mod    = "[".$hash->{NAME} ."] ";
  my $name   = $hash->{NAME};
  my $now    = time() + 5;       # garantiert > als die eingestellte Schlatzeit

  # Fenserkontakte abfragen - wenn einer im Status closed, dann Schaltung um 60 Sekunden verzögern
  if (Heating_Control_FensterOffen($hash)) {
     return;
  }
  # Schaltparameter ermitteln
  my ($nowSwitch,$nextSwitch,$aktParam,$newParam,$nextParam)
     = Heating_Control_akt_next_param($now, $hash);
  # ggf. Device schalten
  if ($nowSwitch gt "" && $aktParam ne $newParam ) {
     Heating_Control_Device_Schalten($hash, $now, $nowSwitch, $newParam)
  }
  # Timer und Readings setzen.
  InternalTimer  ($nextSwitch, "$hash->{TYPE}_Update", $hash, 0);

  my $active = 1;
  if (defined $hash->{helper}{CONDITION}) {
     $active = eval ($hash->{helper}{CONDITION});
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash,  "nextUpdate", strftime("%d.%m.%Y %H:%M:%S",localtime($nextSwitch)));
  readingsBulkUpdate ($hash,  "nextValue",  $nextParam);
  readingsBulkUpdate ($hash,  "state",      $active ? $newParam : "inactive" );
  readingsEndUpdate  ($hash,  defined($hash->{LOCAL} ? 0 : 1));
  
  return 1;
}
################################################################################
sub Heating_Control_FensterOffen ($) {
  my ($hash) = @_;
  my $mod = "[".$hash->{NAME} ."]";

  my %contacts =  ( "CUL_FHTTK" => { "READING" => "Window", "STATUS" => "Open" },
                    "CUL_HM"    => { "READING" => "state",  "STATUS" => "open" },
                    "MAX"       => { "READING" => "state",  "STATUS" => "open"});

  my $fensterKontakte = AttrVal($hash->{NAME}, "windowSensor", "nF");
  Log3 $hash, 5, "$mod list of windowsenors found: '$fensterKontakte'";
  if ($fensterKontakte ne "nF" ) {
     my @kontakte = split(/ /, $fensterKontakte);
     foreach my $fk (@kontakte) {
        if(!$defs{$fk}) {
           Log3 $hash, 3, "$mod Window sensor <$fk> not found - check name.";
        } else {
           my $fk_hash = $defs{$fk};
           my $fk_typ  = $fk_hash->{TYPE};
           if (!defined($contacts{$fk_typ})) {
              Log3 $hash, 3, "$mod TYPE '$fk_typ' of $fk not yet supported, $fk ignored - inform maintainer";
           } else {
              my $reading = $contacts{$fk_typ}{READING};
              my $status  = $contacts{$fk_typ}{STATUS};
              my $windowStatus = ReadingsVal($fk,$reading,"nF");
              if ($windowStatus eq "nF") {
                 Log3 $hash, 3, "$mod READING '$reading' of $fk not found, $fk ignored - inform maintainer";
              } else {
                 Log3 $hash, 5, "$mod windowsensor '$fk' Reading '$reading' is '$windowStatus'";
                 if ($windowStatus eq $status) {
                    Log3 $hash, 3, "$mod switch of $hash->{DEVICE} delayed - windowsensor '$fk' Reading '$reading' is '$windowStatus'";
                    InternalTimer  (time()+60, "$hash->{TYPE}_Update", $hash, 0);
                    return 1
                 }
              }
           }
        }
     }
  }
  return 0;
}
################################################################################
sub Heating_Control_akt_next_param($$) {
  my ($now, $hash) = @_;

  my $mod = "[".$hash->{NAME} ."] ";

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);

  my $aktParam = ReadingsVal($hash->{DEVICE}, $hash->{helper}{DESIRED_TEMP_READING}, 0);
     $aktParam = sprintf("%.1f", $aktParam)   if ($aktParam =~ m/^[0-9]{1,3}$/i);
  my $newParam   = $aktParam;   #default#

  my ($nextParam, $next, $nextSwitch, $nowSwitch) = (0,0,0,0);
  # aktuellen und nächsten Schaltzeitpunkt ermitteln.
  my $startIdx;
  for (my $d=-1; $d>=-7; $d--) {
     my $wd = ($d+$wday) % 7;
     my $anzSwitches = keys %{ $hash->{helper}{SWITCHINGTIME}{$wd} };
     $startIdx = $d;
     last if ($anzSwitches > 0);
  }

  for (my $d=$startIdx; $d<=7; $d++) {
     #ueber jeden Tag
     last if ($nextSwitch > 0);
     my $wd = ($d+$wday) % 7;
     foreach my $st (sort (keys %{ $hash->{helper}{SWITCHINGTIME}{$wd} })) {

        # Tagediff +  Sekunden des Tages addieren
        my @t = split(/:/, $st);                #   HH                  MM              SS
        my $secondsToSwitch = $d*24*3600 + 3600*($t[0] - $hour) + 60*($t[1] - $min) + $t[2] - $sec;
        my $next = $now + $secondsToSwitch;

        if ($secondsToSwitch<=10 && $secondsToSwitch>=-20) {
           Log3 $hash,  4, $mod."Jetzt:".strftime('%d.%m.%Y %H:%M:%S',localtime($now))." -> Next: ".strftime('%d.%m.%Y %H:%M:%S',localtime($next))." -> Param: $hash->{helper}{SWITCHINGTIME}{$wd}{$st} ".$secondsToSwitch;
        }
        if ($secondsToSwitch<=0) {
          $newParam   =  $hash->{helper}{SWITCHINGTIME}{$wd}{$st};
          $newParam   =  sprintf("%.1f", $newParam)   if ($newParam =~ m/^[0-9]{1,3}$/i);
          $nowSwitch  = $next;
        } else {
          $nextParam  = $hash->{helper}{SWITCHINGTIME}{$wd}{$st};
          $nextParam  =  sprintf("%.1f", $nextParam)  if ($nextParam =~ m/^[0-9]{1,3}$/i);
          $nextSwitch = $next;
          last;
        }

     }
  }
  #$nextSwitch += get_SummerTimeOffset($now, $nextSwitch);
  Log3 $hash, 4, $mod .strftime('%d.%m.%Y %H:%M:%S',localtime($nowSwitch))." ; aktParam: $aktParam ; newParam: $newParam";
  Log3 $hash, 4, $mod .strftime('%d.%m.%Y %H:%M:%S',localtime($nextSwitch));
  return ($nowSwitch,$nextSwitch,$aktParam,$newParam,$nextParam);
}
################################################################################
sub Heating_Control_Device_Schalten($$$$) {
  my ($hash, $now, $nowSwitch, $newParam)  = @_;

  my $command = "";
  my $mod     = "[".$hash->{NAME} ."] ";

  #modifier des Zieldevices auswaehlen
  my %modifier = ("MAX"=>"desiredTemperature","FHT"=>"desired-temp","CUL_HM"=>"desired-temp","FS20"=>"");
  $hash->{helper}{DESIRED_TEMP_READING} = "";
  $hash->{helper}{DESIRED_TEMP_READING} = $modifier{$defs{$hash->{DEVICE}}{TYPE}};

  #if ($nowSwitch gt "" && $aktParam ne $newParam ) {
    if (defined $hash->{helper}{CONDITION}) {
      $command = '{ fhem("set @ '.$hash->{helper}{DESIRED_TEMP_READING}.' %") if' . $hash->{helper}{CONDITION} . '}';
    } elsif (defined $hash->{helper}{COMMAND}) {
      $command = $hash->{helper}{COMMAND};
    } else {
      $command = '{ fhem("set @ '.$hash->{helper}{DESIRED_TEMP_READING}.' %") }';
    }
  #}

  #Kommando ausführen
  my $secondsSinceSwitch = $nowSwitch - $now;
  # toDo besser eine Positivliste mit Geraeten, die geschaltet werden sollen
  my %vergangenheitNichtSchalten = ("FS20"  => 1);
  if ($vergangenheitNichtSchalten{$defs{$hash->{DEVICE}}{TYPE}} && $secondsSinceSwitch < -60) {
     ;
  } else {
     if ($command && AttrVal($hash->{NAME}, "disable", 0) == 0) {
       $newParam =~ s/:/ /g;
       $command  =~ s/@/$hash->{DEVICE}/g;
       $command  =~ s/%/$newParam/g;
       $command  = SemicolonEscape($command);
       Log3 $hash, 4, $mod."command: $command";
       my $ret  = AnalyzeCommandChain(undef, $command);
       Log3 ($hash, 3, $ret) if($ret);
     }
  }
}
################################################################################
sub Heating_Control_SetAllTemps() {  # {Heating_Control_SetAllTemps()}

  foreach my $hc ( sort keys %{$modules{Heating_Control}{defptr}} ) {
     my $hash = $modules{Heating_Control}{defptr}{$hc};

     if($hash->{helper}{CONDITION}) {
        if (!(eval ($hash->{helper}{CONDITION}))) {
           readingsSingleUpdate ($hash,  "state",      "inactive", 1);
           next;
        }
     }
     Heating_Control_Update($hash);
     Log3 undef, 3, "Heating_Control_Update() for $hash->{NAME} done!";
  }
  Log3 undef,  3, "Heating_Control_SetAllTemps() done!";
}
################################################################################
sub SortNumber {
 if($a < $b)
  { return -1; }
 elsif($a == $b)
  { return 0; }
 else
  { return 1; }
}

1;

=pod
=begin html

<a name="Heating_Control"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>Heating Control</h3>
<ul>
  <br>
  <a name="Heating_Controldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Heating_Control &lt;device&gt; [&lt;language&gt;] &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
    <br><br>

    to set a weekly profile for &lt;device&gt;, eg. a heating sink.<br>
    You can define different switchingtimes for every day.<br>

    The new temperature is sent to the &lt;device&gt; automatically with <br><br>

    <code>set &lt;device&gt; (desired-temp|desiredTemerature) &lt;temp&gt;</code><br><br>

    Because of the fhem-type of structures, a structures of heating sinks is sent "desired-temp":
    Use an explicit command if you have structures of MAX heating thermostats.<br>
    If you have defined a &lt;condition&gt; and this condition is false if the switchingtime has reached, no command will executed.<br>
    A other case is to define an own perl command with &lt;command&gt;.
    <p>
    The following parameter are defined:
    <ul><b>device</b><br>
      The device to switch at the given time.
    </ul>
    <p>
    <ul><b>language</b><br>
      Specifies the language used for definition and profiles.
      de,en,fr are possible. The parameter is optional.
    </ul>
    <p>
    <ul><b>profile</b><br>
      Define the weekly profile. All timings are separated by space. One switchingtime are defined
      by the following example: <br>
      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;</b></ul><br>
      <u>weekdays:</u> optional, if not set every day is using.<br>
        Otherwise you can define one day as number or as shortname.<br>
      <u>time:</u>define the time to switch, format: HH:MM:[SS](HH in 24 hour format) or a Perlfunction like {sunrise_abs()}<br>
      <u>parameter:</u>the temperature to be set, using a float with mask 99.9 or a sybolic value like <b>eco</b> or <b>comfort</b> - whatever your thermostat understands.
      The symbolic value can be added an additional parameter:  dayTemp:16 night-temp:15. See examples <br>
    </ul>
    <p>
    <ul><b>command</b><br>
      If no condition is set, all others is interpreted as command. Perl-code is setting up
      by well-known Block with {}.<br>
      Note: if a command is defined only this command are executed. In case of executing
      a "set desired-temp" command, you must define it explicit.<br>
      The following parameter are replaced:<br>
        <ol>
          <li>@ => the device to switch</li>
          <li>% => the new temperature</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      if a condition is defined you must declared this with () and a valid perl-code.<br>
      The returnvalue must be boolean.<br>
      The parameter @ and % will be interpreted.
    </ul>
    <p>
    <b>Example:</b>
    <ul>
        <code>define HCB Heating_Control Bad_Heizung 12345|05:20|21 12345|05:25|comfort 17:20|21 17:25|eco</code><br>
        Mo-Fr are setting the temperature at 05:20 to 21&deg;C, and at 05:25 to <b>comfort</b>.
        Every day will be set the temperature at 17:20 to 21&deg;C and 17:25 to <b>eco</b>.<p>

        <code>define HCW Heating_Control WZ_Heizung 07:00|16 Mo,Tu,Th-Fr|16:00|18.5 20:00|12
          {fhem("set dummy on"); fhem("set @ desired-temp %");}</code><br>
        At the given times and weekdays only(!) the command will be executed.<p>

        <code>define HCW Heating_Control WZ_Heizung Sa-Su,We|08:00|21 (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        The temperature is only set if the dummy variable WeAreThere is "yes".<p>

        <code>define HCW Heating_Control WZ_Heizung en Su-Fr|{sunrise_abs()}|21 Mo-Fr|{sunset_abs()}|16</code><br>
        The device is switched at sunrise/sunset. Language: english.

        <code>define HCW Heating_Control WZ_Heizung en Mo-Fr|{myFunction}|night-temp:18 Mo-Fr|{myFunction()}|dayTemp:16</code><br>
        The is switched at time myFunction(). It is sent the Command "night-temp 18" and "dayTemp 16".
    </ul>
  </ul>

  <a name="Heating_Controlset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="Heating_Controlget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="Heating_ControlLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
    <li>windowSensor<br>Defines a list of window sensors. When one of its window state readings is <b>open</b> the aktual switch is delayed.</li>  </ul><br>
</ul>

=end html
=begin html_DE

<a name="Heating_Control"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>Heating Control</h3>
<ul>
  <br>
  <a name="Heating_Controldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Heating_Control &lt;device&gt; [&lt;language&gt;] &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
    <br><br>

    Bildet ein Wochenprofil f&uumlr ein &lt;device&gt;, zb. Heizk&oumlrper, ab.<br>
    Es k&oumlnnen f&uumlr jeden Tag unterschiedliche Schaltzeiten angegeben werden.<br>
    Ist das &lt;device&gt; ein Heizk&oumlrperthermostat (zb. FHT8b, MAX) so wird bei FHT8b/MAX die
    zu setzende Temperatur im &lt;profile&gt; automatisch mittels <br><br>
    <code>set &lt;device&gt; (desired-temp|desiredTemerature) &lt;temp&gt;</code> <br><br> gesendet.
    Struktuen von Heizk&oumlrperthermostaten bekommen aufgrund des fhem-Typs auch desired-temp gesendet:
    Nutze bitte explizite Kommandos wenn Strukturen von MAX Heizthermostaten gesteuert werden sollen.<br><br>
    Ist eine &lt;condition&gt; angegeben und ist zum Schaltpunkt der Ausdruck unwahr,
    so wird dieser Schaltpunkt nicht ausgef&uumlhrt.<br>
    Alternativ zur Automatik kann stattdessen eigener Perl-Code im &lt;command&gt; ausgef&uumlhrt werden.
    <p>
    Folgende Parameter sind im Define definiert:
    <ul><b>device</b><br>
      Name des zu schaltenden Device.
    </ul>
    <p>
    <ul><b>language</b><br>
      Spezifiziert die Sprache für die Definition und die Anzeige der Profile in der Weboberfläche.
      Zurzeit sind de,en,fr definiert. Der Parameter ist optional.
    </ul>
    <p>
    <ul><b>profile</b><br>
      Angabe des Wochenprofils. Die einzelnen Schaltzeiten sind durch Leerzeichen getrennt
      Die Angabe der Schaltzeiten ist nach folgendem Muster definiert:<br>
      <ul><b>[&lt;Wochentage&gt;|]&lt;Uhrzeit&gt;|&lt;Parameter&gt;</b></ul><br>
      <u>Wochentage:</u> optionale Angabe, falls nicht gesetzt wird der Schaltpunkt jeden Tag ausgef&uumlhrt.
        F&uumlr die Tage an denen dieser Schaltpunkt aktiv sein soll, ist jeder Tag mit seiner
        Tagesnummer (Mo=1, ..., So=7) oder Name des Tages (Mo, Di, ..., So) einzusetzen.<br>
      <u>Uhrzeit:</u>Angabe der Uhrzeit zu der geschaltet werden soll, Format: HH:MM:[SS](HH im 24 Stunden Format) oder eine Perlfunction wie {sunrise_abs()}<br>
      <u>Parameter:</u>Angabe der zu setzenden Temperatur als Zahl mit Format 99.9 oder als symbolische Konstante <b>eco</b>
      or <b>comfort</b> - was immer das Heizk&oumlrperthermostat versteht.
      Symbolischen Werten kann ein zusätzlicher Parameter angehängt werden: dayTemp:16 night-temp:15. Unten folgen Beispiele<br><br>
    </ul>
    <p>
    <ul><b>command</b><br>
      Falls keine Condition in () angegeben wurde, so wird alles weitere als Command
      interpretiert. Perl-Code ist in {} zu setzen. <br>
      Wichtig: Falls ein Command definiert ist, so wird zu den definierten Schaltzeiten
      nur(!) das Command ausgef&uumlhrt. Falls ein desired-temp Befehl abgesetzt werde soll,
      so muss dies explizit angegeben werden.<br>
      Folgende Parameter werden ersetzt:<br>
        <ol>
          <li>@ => das zu schaltende Device</li>
          <li>% => die zu setzende Temperatur</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      Bei Angabe einer Condition ist diese in () zu setzen und mit validem Perl-Code zu versehen.<br>
      Der R&uumlckgabedatentyp der condition muss boolean sein.<br>
      Die Parameter @ und  % werden interpretiert.
    </ul>
    <p>
    <b>Beispiel:</b>
    <ul>
        <code>define HCW Heating_Control Bad_Heizung 12345|05:20|21 12345|05:25|comfort 17:20|21 17:25|eco</code><br>
        Mo-Fr wird die Temperatur um 05:20Uhr auf 21&deg;C, und um 05:25Uhr auf <b>comfort</b> gesetzt.
        Jeden Tag wird die Temperatur um 17:20Uhr auf 21&deg;C und 17:25Uhr auf <b>eco</b> gesetzt.<p>

        <code>define HCW Heating_Control WZ_Heizung 07:00|16 Mo,Di,Mi|16:00|18.5 20:00|12
          {fhem("set dummy on"); fhem("set @ desired-temp %");}</code><br>
        Zu den definierten Schaltzeiten wird nur(!) der in {} angegebene Perl-Code ausgef&uumlhrt.<p>

        <code>define HCW Heating_Control WZ_Heizung Sa-So,Mi|08:00|21 (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        Die zu setzende Temperatur wird nur gesetzt, falls die Dummy Variable WeAreThere = "yes" ist.<p>

        <code>define HCW Heating_Control WZ_Heizung en Su-Fr|{sunrise_abs()}|21 Mo-Fr|{sunset_abs()}|16</code><br>
        Das Gerät wird bei Sonnenaufgang und Sonnenuntergang geschaltet. Sprache: Englisch.

        <code>define HCW Heating_Control WZ_Heizung en Mo-Fr|{myFunction}|night-temp:18 Mo-Fr|{myFunction()}|dayTemp:16</code><br>
        Das Gerät wird bei myFunction() geschaltet. Es wird das Kommando "night-temp 18" bzw. "dayTemp 16" gesendet.
        <p>
    </ul>
  </ul>

  <a name="Heating_Controlset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="Heating_Controlget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="Heating_ControlLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
    <li>windowSensor<br>Definiert eine Liste mit Fensterkontakten. Wenn das Reading window state eines Fensterkontakts <b>open</b> ist, wird der aktuelle Schaltvorgang verzögert.</li>
  </ul><br>
</ul>

=end html_DE
=cut
