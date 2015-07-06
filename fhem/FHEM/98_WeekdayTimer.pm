# $Id$
##############################################################################
#
#     98_WeekdayTimer.pm
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

use Time::Local 'timelocal_nocheck';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

################################################################################
sub WeekdayTimer_Initialize($){
  my ($hash) = @_;

  if(!$modules{Twilight}{LOADED} && -f "$attr{global}{modpath}/FHEM/59_Twilight.pm") {
    my $ret = CommandReload(undef, "59_Twilight");
    Log3 undef, 1, $ret if($ret);
  }

# Consumer
  $hash->{SetFn}   = "WeekdayTimer_Set";
  $hash->{DefFn}   = "WeekdayTimer_Define";
  $hash->{UndefFn} = "WeekdayTimer_Undef";
  $hash->{GetFn}   = "WeekdayTimer_Get";
  $hash->{AttrFn}  = "WeekdayTimer_Attr";  
  $hash->{UpdFn}   = "WeekdayTimer_Update";
  $hash->{AttrList}= "disable:0,1 delayedExecutionCond switchInThePast:0,1 ".
     $readingFnAttributes;                                               
}
################################################################################
sub WeekdayTimer_InitHelper($) {
  my ($hash) = @_;
   
  $hash->{longDays} =  { "de" => ["Sonntag",  "Montag","Dienstag","Mittwoch",  "Donnerstag","Freitag", "Samstag",  "Wochenende", "Werktags" ],
                         "en" => ["Sunday",   "Monday","Tuesday", "Wednesday", "Thursday",  "Friday",  "Saturday", "weekend",    "weekdays" ],
                         "fr" => ["Dimanche", "Lundi", "Mardi",   "Mercredi",  "Jeudi",     "Vendredi","Samedi",   "weekend",    "jours de la semaine"]};
  $hash->{shortDays} = { "de" => ["so",       "mo",    "di",      "mi",        "do",        "fr",      "sa",       '$we',        '!$we'     ],    
                         "en" => ["su",       "mo",    "tu",      "we",        "th",        "fr",      "sa",       '$we',        '!$we'     ],
                         "fr" => ["di",       "lu",    "ma",      "me",        "je",        "ve",      "sa",       '$we',        '!$we'     ]};
}
################################################################################
sub WeekdayTimer_Set($@) {
  my ($hash, @a) = @_;
  
  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of enable disable " if($a[1] eq "?");
  
  my $name = shift @a;
  my $v = join(" ", @a);

  Log3 $hash, 3, "[$name] set $name $v";
  
  if      ($v eq "enable") {
     fhem("attr $name disable 0"); 
  } elsif ($v eq "disable") {
     fhem("attr $name disable 1"); 
  }
  return undef;
}
################################################################################
sub WeekdayTimer_Get($@) {
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
sub WeekdayTimer_Undef($$) {
  my ($hash, $arg) = @_;

  foreach my $idx (keys %{$hash->{profil}}) {
     myRemoveInternalTimer($idx, $hash);
  }
  myRemoveInternalTimer("SetTimerOfDay", $hash);
  delete $modules{$hash->{TYPE}}{defptr}{$hash->{NAME}};
  return undef;
}  
################################################################################
sub WeekdayTimer_Define($$) {
  my ($hash, $def) = @_;
  WeekdayTimer_InitHelper($hash);

  my  @a = split("[ \t]+", $def);

  return "Usage: define <name> $hash->{TYPE} <device> <language> <switching times> <condition|command>"
     if(@a < 4);

  #fuer den modify Altlasten bereinigen
  delete($hash->{helper});

  my $name     = shift @a;
  my $type     = shift @a;
  my $device   = shift @a;
  
  WeekdayTimer_DeleteTimer($hash);
  my $delVariables = "(CONDITION|COMMAND|profile|Profil)";   
  map { delete $hash->{$_} if($_=~ m/^$delVariables.*/g) }  keys %{$hash};
  
  my $language = WeekdayTimer_Language  ($hash, \@a);
  
  my $idx = 0; 
  $hash->{dayNumber}    = {map {$_ => $idx++}     @{$hash->{shortDays}{$language}}};  
  $hash->{helper}{daysRegExp}        = '(' . join ("|",        @{$hash->{shortDays}{$language}}) . ")";
  $hash->{helper}{daysRegExpMessage} = $hash->{helper}{daysRegExp};
  
  $hash->{helper}{daysRegExp}   =~ s/\$/\\\$/g; 
  $hash->{helper}{daysRegExp}   =~ s/\!/\\\!/g; 

  WeekdayTimer_GlobalDaylistSpec ($hash, \@a);
   
  my @switchingtimes       = WeekdayTimer_gatherSwitchingTimes (\@a);
  my $conditionOrCommand   = join (" ", @a);

  # test if device is defined
  Log3 ($hash, 3, "[$name] invalid device, <$device> not found") if(!$defs{$device});
  
  # wenn keine switchintime angegeben ist, dann Fehler
  Log3 ($hash, 3, "[$name] no valid Switchingtime found in <$conditionOrCommand>, check first parameter")  if (@switchingtimes == 0);

  $hash->{TYPE}           = $type;  
  $hash->{NAME}           = $name;
  $hash->{DEVICE}         = $device;
  $hash->{SWITCHINGTIMES} = \@switchingtimes;
  $attr{$name}{verbose}   = 4 if (!defined $attr{$name}{verbose} && $name =~ m/^tst.*/ );
 #$attr{$name}{verbose}   = 4;  

  $modules{$hash->{TYPE}}{defptr}{$hash->{NAME}} = $hash;
  
  if($conditionOrCommand =~  m/^\(.*\)$/g) {         #condition (*)
     $hash->{CONDITION} = $conditionOrCommand;
  } elsif(length($conditionOrCommand) > 0 ) {
     $hash->{COMMAND} = $conditionOrCommand;
  }
  
 #WeekdayTimer_DeleteTimer($hash);  am Anfang dieser Routine
  WeekdayTimer_Profile    ($hash);
  #WeekdayTimer_SetTimer   ($hash); # per timer - nach init
  InternalTimer(time(), "$hash->{TYPE}_SetTimer", $hash, 0);

  WeekdayTimer_SetTimerForMidnightUpdate( { HASH => $hash} );
  
  return undef;
}
################################################################################
sub WeekdayTimer_Profile($) {   
  my $hash = shift;
  
  my $nochZuAendern  = 0;  #  $d
  my $language =   $hash->{LANGUAGE};
  my %longDays = %{$hash->{longDays}}; 
  
  delete $hash->{profil};
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time()); 
  
  my $now = time();   
# ------------------------------------------------------------------------------
  foreach  my $st (@{$hash->{SWITCHINGTIMES}}) {
     my ($tage,$time,$parameter) = WeekdayTimer_SwitchingTime ($hash, $st);
     
     foreach  my $d (@{$tage}) {

        my    @listeDerTage = ($d);
        push (@listeDerTage, (0, 6) ) if ($d==7);
        push (@listeDerTage, (1..5) ) if ($d==8);

        map { my $day = $_; 
           my $dayOfEchteZeit = $day;
              $dayOfEchteZeit = ($wday>=1&&$wday<=5) ? 6 : $wday  if ($day==7); # ggf. Samstag $wday ~~ [1..5]  
              $dayOfEchteZeit = ($wday==0||$wday==6) ? 1 : $wday  if ($day==8); # ggf. Montag  $wday ~~ [0, 6]
            my $echtZeit = WeekdayTimer_EchteZeit($hash, $dayOfEchteZeit, $time); 
            $hash->{profile}{$day}{$echtZeit} = $parameter;
        } @listeDerTage;      
     }
  }
# ------------------------------------------------------------------------------
  my $idx = 0;
  foreach  my $st (@{$hash->{SWITCHINGTIMES}}) {
     my ($tage,$time,$parameter)       = WeekdayTimer_SwitchingTime ($hash, $st);
     my $echtZeit                      = WeekdayTimer_EchteZeit     ($hash, $wday, $time); 
     my ($stunde, $minute, $sekunde)   = split (":",$echtZeit);              
     
     $idx++;
     $hash->{profil}{$idx}{TIME}  = $time;
     $hash->{profil}{$idx}{PARA}  = $parameter;
     $hash->{profil}{$idx}{EPOCH} = WeekdayTimer_zeitErmitteln ($now, $stunde, $minute, $sekunde, 0);
     $hash->{profil}{$idx}{TAGE}  = $tage;
  }
# ------------------------------------------------------------------------------
  Log3 $hash, 4,  "[$hash->{NAME}] " . sunrise_abs() . " " . sunset_abs() . " " . $longDays{$language}[$wday]; 
  foreach  my $d (sort keys %{$hash->{profile}}) {
       my $profiltext = "";
       foreach  my $t (sort keys %{$hash->{profile}{$d}}) {
           $profiltext .= "$t " .  $hash->{profile}{$d}{$t} . ", "; 
       }
       my $profilKey  = "Profil $d: $longDays{$language}[$d]";
       $profiltext =~ s/, $//;
       $hash->{$profilKey} = $profiltext;
       Log3 $hash, 4,  "[$hash->{NAME}] $profiltext ($profilKey)";  
  }

  # Log 3, $hash->{NAME}  ."--->\n".   Dumper $hash->{profile};
  # für logProxy umhaengen
  $hash->{helper}{SWITCHINGTIME} = $hash->{profile};
  delete $hash->{profile};
}
################################################################################   
sub WeekdayTimer_SwitchingTime($$) {
    my ($hash, $switchingtime) = @_;
    
    my $name = $hash->{NAME};
    my $globalDaylistSpec = $hash->{GlobalDaylistSpec};
    my @tageGlobal = @{WeekdayTimer_daylistAsArray($hash, $globalDaylistSpec)}; 
    
    my (@st, $daylist, $time, $timeString, $para);
    @st = split(/\|/, $switchingtime);
    
    if ( @st == 2) {    
      $daylist = ($globalDaylistSpec gt "") ? $globalDaylistSpec : "0123456";
      $time    = $st[0];
      $para    = $st[1];
    } elsif ( @st == 3) {
      $daylist  = $st[0];
      $time     = $st[1];
      $para     = $st[2];
    }
    
    my @tage = @{WeekdayTimer_daylistAsArray($hash, $daylist)}; 
    my $tage=@tage;
    if ( $tage==0 ) {
       Log3 ($hash, 1, "[$name] invalid daylist in $name <$daylist> use one of 012345678 or $hash->{helper}{daysRegExpMessage}");
    }       

    my %hdays=();
    @hdays{@tageGlobal} = undef;
    @hdays{@tage}       = undef;
    @tage = sort keys %hdays;
    
   #Log3 $hash, 3, "Tage: " . Dumper \@tage;
    return (\@tage,$time,$para);
}

################################################################################   
sub WeekdayTimer_daylistAsArray($$){
    my ($hash, $daylist) = @_;
    
    my $name = $hash->{NAME};
    my @days;
    
    my %hdays=();

    $daylist = lc($daylist); 
    # Angaben der Tage verarbeiten
    # Aufzaehlung 1234 ...
    if (      $daylist =~  m/^[0-8]{0,9}$/g) {
        
        Log3 ($hash, 3, "[$name] " . '"7" in daylist now means $we(weekend) - see dokumentation!!!' ) 
           if (index($daylist, '7') != -1);
        
        @days = split("", $daylist);
        @hdays{@days} = undef;

    # Aufzaehlung Sa,So,... | Mo-Di,Do,Fr-Mo
    } elsif ($daylist =~  m/^($hash->{helper}{daysRegExp}(,|-|$)){0,7}$/g   ) {
      my @subDays;
      my @aufzaehlungen = split (",", $daylist);
      foreach my $einzelAufzaehlung (@aufzaehlungen) {
         my @days = split ("-", $einzelAufzaehlung);
         my $days = @days; 
         if ($days == 1) {
           #einzelner Tag: Sa
           $hdays{$hash->{dayNumber}{$days[0]}} = undef;    
         } else {  
           # von bis Angabe: Mo-Di
           my $von  = $hash->{dayNumber}{$days[0]};
           my $bis  = $hash->{dayNumber}{$days[1]};
           if ($von <= $bis) {
              @subDays = ($von .. $bis);
           } else {
             #@subDays = ($dayNumber{so} .. $bis, $von .. $dayNumber{sa});
              @subDays = (           00  .. $bis, $von ..            06);
           }
           @hdays{@subDays}=undef;           
         }
      }
    } else{
      %hdays = ();
    }
    
    my @tage = sort keys %hdays;
    return \@tage;
}
################################################################################   
sub WeekdayTimer_EchteZeit($$$) {
    my ($hash, $d, $time)  = @_; 
    
    my $name = $hash->{NAME};
    
    my $now = time();
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($now); 

    my $listOfDays = "";

    # Zeitangabe verarbeiten.    
    $time = '"' . "$time" . '"'       if($time !~  m/^\{.*\}$/g);       
    my $date           = $now+($d-$wday)*86400;
    my $timeString     = '{ my $date='."$date;" .$time."}";    
    my $eTimeString    = eval( $timeString );                            # must deliver HH:MM[:SS]
    if ($@) {
       $@ =~ s/\n/ /g; 
       Log3 ($hash, 3, "[$name] " . $@ . ">>>$timeString<<<");
       $eTimeString = "00:00:00";
    }
    
    if      ($eTimeString =~  m/^[0-2][0-9]:[0-5][0-9]$/g) {          #  HH:MM
      $eTimeString .= ":00";                                          #  HH:MM:SS erzeugen
    } elsif ($eTimeString =~  m/^[0-2][0-9](:[0-5][0-9]){2,2}$/g) {   #  HH:MM:SS
      ;                                                               #  ok.
    } else {
      Log3 ($hash, 1, "[$name] invalid time <$eTimeString> HH:MM[:SS]");
      $eTimeString = "00:00:00";
    }
    return $eTimeString;
}
################################################################################
sub WeekdayTimer_zeitErmitteln  ($$$$$) {
   my ($now, $hour, $min, $sec, $days) = @_;

   my @jetzt_arr = localtime($now);
   #Stunden               Minuten               Sekunden
   $jetzt_arr[2]  = $hour; $jetzt_arr[1] = $min; $jetzt_arr[0] = $sec;
   $jetzt_arr[3] += $days;
   my $next = timelocal_nocheck(@jetzt_arr);
   return $next;
}
################################################################################
sub WeekdayTimer_gatherSwitchingTimes {
  my $a = shift;

  my @switchingtimes = ();
  my $conditionOrCommand;
  
  # switchingtime einsammeln
  while (@$a > 0) {

    #pruefen auf Angabe eines Schaltpunktes
    my $element = shift @$a;
    my @t = split(/\|/, $element);
    my $anzahl = @t;
    if ( $anzahl >= 2 && $anzahl <= 3) {
      push(@switchingtimes, $element);
    } else {
      unshift @$a, $element; 
      last;
    }
  }
  return (@switchingtimes);
}    
################################################################################
sub WeekdayTimer_Language {
  my ($hash, $a) = @_;
    
  my $name = $hash->{NAME};  

  # ggf. language optional Parameter
  my $langRegExp = "(" . join ("|", keys(%{$hash->{shortDays}})) . ")";
  my $language   = shift @$a;

  if ($language =~  m/^$langRegExp$/g) {
  } else {
     Log3 ($hash, 3, "[$name] language: $language not recognized, use one of $langRegExp") if (length($language) == 2);
     unshift @$a, $language; 
     $language   = "de";
  }
  $hash->{LANGUAGE} = $language;

  $language = $hash->{LANGUAGE};
    return ($langRegExp, $language);
}
################################################################################
sub WeekdayTimer_GlobalDaylistSpec {
  my ($hash, $a) = @_;
    
  my $daylist = shift @$a;

  my @tage = @{WeekdayTimer_daylistAsArray($hash, $daylist)}; 
  my $tage = @tage; 
  if ($tage > 0) {
    ;
  } else {
    unshift (@$a,$daylist);     
    $daylist = "";
  }
  
  $hash->{GlobalDaylistSpec} = $daylist;
}
################################################################################
sub WeekdayTimer_SetTimerForMidnightUpdate($) {
    my ($myHash) = @_;
    my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
    return if (!defined($hash));

   my $now = time();
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
   my $secToMidnight = 24*3600 -(3600*$hour + 60*$min + $sec) + 5;
  #my $secToMidnight =                                        + 01*60;

   myRemoveInternalTimer("SetTimerOfDay", $hash);
   myInternalTimer      ("SetTimerOfDay", $now+$secToMidnight, "$hash->{TYPE}_SetTimerOfDay", $hash, 0);

}
################################################################################
sub WeekdayTimer_SetTimerOfDay($) {
    my ($myHash) = @_;
    my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
    return if (!defined($hash));
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time());
    my $secSinceMidnight = 3600*$hour + 60*$min + $sec;    
    
    $hash->{SETTIMERATMIDNIGHT} = 1  if ($secSinceMidnight <= 10);
    WeekdayTimer_DeleteTimer($hash);
    WeekdayTimer_Profile    ($hash);
    WeekdayTimer_SetTimer   ($hash);
    delete $hash->{SETTIMERATMIDNIGHT};
    
    WeekdayTimer_SetTimerForMidnightUpdate( { HASH => $hash} );
}
################################################################################
sub WeekdayTimer_SetTimer($) {
  my $hash = shift; 
  my $name = $hash->{NAME};
  
  my $now  = time();  
  
  my $isHeating         = WeekdayTimer_isHeizung($hash);
  my $swip              = AttrVal($name, "switchInThePast", 0);
  my $switchInThePast   = ($swip || $isHeating) && !defined $hash->{SETTIMERATMIDNIGHT};
  
  Log3 $hash, 4, "[$name] Heating recognized - switch in the past activated" if ($isHeating);
  Log3 $hash, 4, "[$name] no switch in the yesterdays because of the devices type($hash->{DEVICE} is not recognized as heating) - use attr switchInThePast" if (!$switchInThePast && !defined $hash->{SETTIMERATMIDNIGHT});
  
  my @switches = sort keys %{$hash->{profil}};
  if ($#switches < 0) {
     Log3 $hash, 3, "[$name] no switches to send, due to possible errors.";
     return; 
  }   
  
  readingsSingleUpdate ($hash,  "state", "inactive", 1) if (!defined $hash->{SETTIMERATMIDNIGHT});
  for(my $i=0; $i<=$#switches; $i++) {
  
     my $idx = $switches[$i];
     
     my $time        = $hash->{profil}{$idx}{TIME};
     my $timToSwitch = $hash->{profil}{$idx}{EPOCH};
     my $tage        = $hash->{profil}{$idx}{TAGE};
     my $para        = $hash->{profil}{$idx}{PARA};
     
     my $secondsToSwitch = $timToSwitch - $now;
     
     my $isActiveTimer = WeekdayTimer_isAnActiveTimer ($hash, $tage, $para);
     readingsSingleUpdate ($hash,  "state",      "active",    1) 
        if (!defined $hash->{SETTIMERATMIDNIGHT} && $isActiveTimer);
     
     if ($secondsToSwitch>-5) {
        Log3 $hash, 4, "[$name] setTimer - timer seems to be active today: ".join("",@$tage)."|$time|$para" if($isActiveTimer);
        myInternalTimer ("$idx", $timToSwitch, "$hash->{TYPE}_Update", $hash, 0);
     }
  }
  
  if (defined $hash->{SETTIMERATMIDNIGHT}) {
     return;
  }
  
  my ($idx, $aktTime,$aktParameter,$nextTime,$nextParameter) = 
     WeekdayTimer_searchAktNext($hash, time()+5);
  readingsSingleUpdate ($hash,  "nextUpdate", FmtDateTime($nextTime), 1);
  readingsSingleUpdate ($hash,  "nextValue",  $nextParameter,         1);  
  
  if ($switchInThePast) {  
     # Fenserkontakte abfragen - wenn einer im Status closed, dann Schaltung um 60 Sekunden verzögern
     if (WeekdayTimer_FensterOffen($hash, $aktParameter, $idx)) {
        return;
     }
     WeekdayTimer_Device_Schalten($hash,    $aktParameter, [7,8]);
     my $active = 1;
     if (defined $hash->{CONDITION}) {
        $active = AnalyzeCommandChain(undef, "{".$hash->{CONDITION}."}");
     }
     readingsSingleUpdate ($hash,  "state", $aktParameter, 1) if ($active);
  }     
}
################################################################################
sub WeekdayTimer_searchAktNext($$) {
  my ($hash, $now) = @_;
  my $name = $hash->{NAME};
 
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
 #Log3 $hash, 3, "[$name] such--->".FmtDateTime($now);
  
  my ($nextTag, $nextTime, $nextParameter);
  my ($aktTag,  $aktTime,  $aktParameter);
  
  my $language = $hash->{LANGUAGE};
  
  my @realativeWdays  = ($wday..6,0..$wday-1,$wday..6,0..6);  
 #Log3 $hash, 3, "[$name] wdays @realativeWdays";
  for (my $i=0;$i<=$#realativeWdays;$i++) {
     
     my $relativeDay = $i-7;
     my $relWday     = $realativeWdays[$i];
     
    #Log3 $hash, 3, "[$name] $i relWday  $relWday $relativeDay";
     my $idx=0;
     foreach my $time (sort keys %{$hash->{helper}{SWITCHINGTIME}{$relWday}}) {
        
        $idx++;
        my ($stunde, $minute, $sekunde)   = split (":",$time);              
        my $epoch = WeekdayTimer_zeitErmitteln ($now, $stunde, $minute, $sekunde, $relativeDay);

       #Log3 $hash, 3, "[$name] $time---->".FmtDateTime($epoch);
  
        if ($epoch >= $now) {
           $nextTag       = $relWday;
           $nextTime      = $epoch;
           $nextParameter = $hash->{helper}{SWITCHINGTIME}{$relWday}{$time};
           Log3 $hash, 4, "[$name] akt:  ".FmtDateTime($aktTime) ."(".$hash->{shortDays}{$language}[$aktTag]. ") -->> $aktParameter";
           Log3 $hash, 4, "[$name] next: ".FmtDateTime($nextTime)."(".$hash->{shortDays}{$language}[$nextTag].") -->> $nextParameter";
           return ($idx, $aktTime,  $aktParameter, $nextTime, $nextParameter);
        }
        $aktTag       = $relWday;
        $aktTime      = $epoch;
        $aktParameter = $hash->{helper}{SWITCHINGTIME}{$relWday}{$time};        
    } 
  } 
  return (undef,undef,undef,undef);  
}   
################################################################################
sub WeekdayTimer_DeleteTimer($) {
  my $hash = shift; 
  map {myRemoveInternalTimer ($_, $hash)}      keys %{$hash->{profil}};
}
################################################################################
sub WeekdayTimer_Update($) {
  my ($myHash) = @_;
  my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
  return if (!defined($hash));

  my $name     = $hash->{NAME};
  my $idx      = $myHash->{MODIFIER};
  my $now      = time();

  # Schaltparameter ermitteln
  my $tage        = $hash->{profil}{$idx}{TAGE};
  my $time        = $hash->{profil}{$idx}{TIME};
  my $newParam    = $hash->{profil}{$idx}{PARA};

  # Fenserkontakte abfragen - wenn einer im Status closed, dann Schaltung um 60 Sekunden verzögern
  if (WeekdayTimer_FensterOffen($hash, $newParam, $idx)) {
     readingsSingleUpdate ($hash,  "state", "open window", 1);
     return;
  }
  
  my $activeTimer = WeekdayTimer_isAnActiveTimer ($hash, $tage, $newParam);
  Log3 $hash, 4, "[$name] Update   - timer seems to be active today: ".join("",@$tage)."|$time|$newParam" if($activeTimer);
  
  my ($indx, $aktTime,  $aktParameter, $nextTime, $nextParameter) =
     WeekdayTimer_searchAktNext($hash, time()+5);

  if ($newParam ne $aktParameter ) {
    #Log3 $hash, 3, "[$name]*Update   - $newParam overwritten by $aktParameter (" . FmtDateTime($aktTime). ")"; 
     Log3 $hash, 3, "[$name] Update   - $newParam overwritten by $aktParameter (" . FmtDateTime($aktTime). ")" if($activeTimer); 
     $newParam = $aktParameter;
  }   

  # ggf. Device schalten
  WeekdayTimer_Device_Schalten($hash, $newParam, $tage)   if($activeTimer);
     
  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash,  "nextUpdate", FmtDateTime($nextTime));
  readingsBulkUpdate ($hash,  "nextValue",  $nextParameter);
  readingsBulkUpdate ($hash,  "state",      $activeTimer ? $newParam : "inactive" );
  readingsEndUpdate  ($hash,  defined($hash->{LOCAL} ? 0 : 1));

  return 1; 
     
}
################################################################################
sub WeekdayTimer_isAnActiveTimer ($$$) {
  my ($hash, $tage, $newParam)  = @_;
  
  my %specials   = ( "%NAME" => $hash->{DEVICE}, "%EVENT" => $newParam);
  
  my $condition  = WeekdayTimer_Condition ($hash, $tage);
  my $tageAsHash = WeekdayTimer_tageAsHash($hash, $tage);
  my $xPression  = "{".$tageAsHash.";;".$condition ."}";
     $xPression  = EvalSpecials($xPression, %specials);  
  
  my $ret = AnalyzeCommandChain(undef, $xPression);
  return  $ret;
}
################################################################################
sub WeekdayTimer_isHeizung($) {
  my ($hash)  = @_;
  
  my $name = $hash->{NAME};

  my %setmodifiers =
     ("FHT"     =>  "desired-temp",
      "PID20"   =>  "desired",
      "EnOcean" =>  {  "subTypeReading" => "subType", "setModifier" => "desired-temp",
                       "roomSensorControl.05"  => 1,
                       "hvac.01"               => 1 },
      "MAX"     =>  {  "subTypeReading" => "type", "setModifier" => "desiredTemperature",
                       "HeatingThermostatPlus" => 1,
                       "HeatingThermostat"     => 1,
                       "WallMountedThermostat" => 1 },
      "CUL_HM"  =>  {  "subTypeReading" => "model","setModifier" => "desired-temp",
                       "HM-CC-TC"              => 1,
                       "HM-TC-IT-WM-W-EU"      => 1,
                       "HM-CC-RT-DN"           => 1 } );
  
  my $model = "";
  my $dHash = $defs{$hash->{DEVICE}};                                           
  my $dType = $dHash->{TYPE};
  return ""   if (!defined($dType));  

  my $setModifier = $setmodifiers{$dType};
     $setModifier = ""  if (!defined($setModifier));
  if (ref($setModifier)) {

      my $subTypeReading = $setmodifiers{$dType}{subTypeReading};
      
      if ($subTypeReading eq "type" ) {
         $model = $dHash->{type};
      } else {   
         $model = AttrVal($hash->{DEVICE}, $subTypeReading, "nF");
      }        
      
      if (defined($setmodifiers{$dType}{$model})) {
         $setModifier = $setmodifiers{$dType}{setModifier}
      } else {
         $setModifier = "";
      }
  }
  Log3 $hash, 4, "[$name] device type $dType:$model recognized, setModifier:$setModifier";  
  return $setModifier;
}
################################################################################
#
sub WeekdayTimer_FensterOffen ($$$) {
  my ($hash, $event, $time) = @_;
  my $name = $hash->{NAME};
  
  my $verzoegerteAusfuehrungCond = AttrVal($hash->{NAME}, "delayedExecutionCond", "0");

  my %specials= (
         "%HEATING_CONTROL"  => $hash->{NAME},
         "%WEEKDAYTIMER"     => $hash->{NAME},
         "%NAME"             => $hash->{DEVICE},
         "%EVENT"            => $event
  );
  $verzoegerteAusfuehrungCond = EvalSpecials($verzoegerteAusfuehrungCond, %specials);
  my $verzoegerteAusfuehrung = eval($verzoegerteAusfuehrungCond);
  
  if ($verzoegerteAusfuehrung) {
     if (!defined($hash->{VERZOEGRUNG})) {
        Log3 $hash, 3, "[$name] switch of $hash->{DEVICE} delayed - $verzoegerteAusfuehrungCond is TRUE";
     }
     myRemoveInternalTimer("Update", $hash);
     myInternalTimer      ("$time",  time()+55+int(rand(10)), "$hash->{TYPE}_Update", $hash, 0);
     $hash->{VERZOEGRUNG} = 1;
     return 1
  }
  
  my %contacts =  ( "CUL_FHTTK"       => { "READING" => "Window",          "STATUS" => "(Open)",        "MODEL" => "r" },
                    "CUL_HM"          => { "READING" => "state",           "STATUS" => "(open|tilted)", "MODEL" => "r" },
                    "MAX"             => { "READING" => "state",           "STATUS" => "(open.*)",      "MODEL" => "r" },
                    "WeekdayTimer"    => { "READING" => "delayedExecution","STATUS" => "^1\$",          "MODEL" => "a" },
                    "Heating_Control" => { "READING" => "delayedExecution","STATUS" => "^1\$",          "MODEL" => "a" }
                  );
                  
  my $fensterKontakte = AttrVal($hash->{NAME}, "windowSensor", "")." ".$hash->{NAME};
  $fensterKontakte =~ s/^\s+//;
  $fensterKontakte =~ s/\s+$//;
  
  Log3 $hash, 5, "[$name] list of window sensors found: '$fensterKontakte'";
  if ($fensterKontakte ne "" ) {
     my @kontakte = split("[ \t]+", $fensterKontakte);
     foreach my $fk (@kontakte) {
        if(!$defs{$fk}) {
           Log3 $hash, 3, "[$name] sensor <$fk> not found - check name.";
        } else {
           my $fk_hash = $defs{$fk};
           my $fk_typ  = $fk_hash->{TYPE};
           if (!defined($contacts{$fk_typ})) {
              Log3 $hash, 3, "[$name] TYPE '$fk_typ' of $fk not yet supported, $fk ignored - inform maintainer";
           } else {
           
              my $reading      = $contacts{$fk_typ}{READING};
              my $statusReg    = $contacts{$fk_typ}{STATUS};
              my $model        = $contacts{$fk_typ}{MODEL};
              
              my $windowStatus;
              if ($model eq "r")  {   ### Reading, sonst Attribut
                 $windowStatus = ReadingsVal($fk,$reading,"nF");
              }else{
                 $windowStatus = AttrVal    ($fk,$reading,"nF");              
              }
              
              if ($windowStatus eq "nF") {
                 Log3 $hash, 3, "[$name] Reading/Attribute '$reading' of $fk not found, $fk ignored - inform maintainer" if ($model eq "r");
              } else {
                 Log3 $hash, 5, "[$name] sensor '$fk' Reading/Attribute '$reading' is '$windowStatus'";

                 if ($windowStatus =~  m/^$statusReg$/g) {
                    if (!defined($hash->{VERZOEGRUNG})) {
                       Log3 $hash, 3, "[$name] switch of $hash->{DEVICE} delayed - sensor '$fk' Reading/Attribute '$reading' is '$windowStatus'";
                    }
                    myRemoveInternalTimer("Update", $hash);
                    myInternalTimer      ("$time",  time()+55+int(rand(10)), "$hash->{TYPE}_Update", $hash, 0);
                    $hash->{VERZOEGRUNG} = 1;
                    return 1
                 }
              }
           }
        }
     }
  }
  if ($hash->{VERZOEGRUNG}) {
     Log3 $hash, 3, "[$name] delay of switching $hash->{DEVICE} stopped.";
  }
  delete $hash->{VERZOEGRUNG};
  return 0;
}
################################################################################
sub WeekdayTimer_Device_Schalten($$$) {
  my ($hash, $newParam, $tage)  = @_;

  my ($command, $condition, $tageAsHash) = "";
  my $name = $hash->{NAME};                                        ###

  my $now = time();
  #modifier des Zieldevices auswaehlen
  my $setModifier = WeekdayTimer_isHeizung($hash);
  
  $command = "set @ " . $setModifier . " %";
  $command = $hash->{COMMAND}   if (defined $hash->{COMMAND});

#ort!!! vorverlegt
 #my $activeTimer = WeekdayTimer_isAnActiveTimer ($hash, $tage, $newParam); 
  my $activeTimer = 1;
  
  my $isHeating = $setModifier gt "";
  my $aktParam  = ReadingsVal($hash->{DEVICE}, $setModifier, "");
     $aktParam  = sprintf("%.1f", $aktParam)   if ($isHeating && $aktParam =~ m/^[0-9]{1,3}$/i);
     $newParam  = sprintf("%.1f", $newParam)   if ($isHeating && $newParam =~ m/^[0-9]{1,3}$/i);

  my $disabled = AttrVal($hash->{NAME}, "disable", 0);
  my $disabled_txt = $disabled ? " " : " not";
  Log3 $hash, 4, "[$name] aktParam:$aktParam newParam:$newParam - is $disabled_txt disabled";

  #Kommando ausführen
  if ($command && !$disabled && $aktParam ne $newParam && $activeTimer) {
    $newParam =~ s/:/ /g;
    
    my %specials = ( "%NAME" => $hash->{DEVICE}, "%EVENT" => $newParam);
    $command= EvalSpecials($command, %specials);
    
    Log3 $hash, 4, "[$name] command: $command executed";
    my $ret  = AnalyzeCommandChain(undef, $command);
    Log3 ($hash, 3, $ret) if($ret);
  } 
}
################################################################################
sub WeekdayTimer_tageAsHash($$) {
   my ($hash, $tage)  = @_;   
   
   my %days = map {$_ => 1} @$tage;
   map {delete $days{$_}} (7,8);   
   
   return 'my $days={};map{$days->{$_}=1}'.'('.join (",", sort keys %days).')';
}
################################################################################
sub WeekdayTimer_Condition($$) {  
  my ($hash, $tage)  = @_;
  
  my $condition  = "( ";
  $condition .= (defined $hash->{CONDITION}) ? $hash->{CONDITION}  : 1 ; 
  $condition .= " && " . WeekdayTimer_TageAsCondition($tage);
  $condition .= ")";
  
  return $condition;
  
}
################################################################################
sub WeekdayTimer_TageAsCondition ($) {
   my $tage = shift;
   
   my %days     = map {$_ => 1} @$tage;
    
   my $we       = $days{7}; delete $days{7};  # $we
   my $notWe    = $days{8}; delete $days{8};  #!$we
   
   my $tageExp  = '(defined $days->{$wday}';
      $tageExp .= ' ||  $we' if defined $we; 
      $tageExp .= ' || !$we' if defined $notWe;
      $tageExp .= ')';
      
   return $tageExp;
   
}
################################################################################
sub WeekdayTimer_Attr($$$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  $attrVal = 0 if(!defined $attrVal);  
  
  my $hash = $defs{$name};
  if(       $attrName eq "disable" ) {
     readingsSingleUpdate ($hash,  "disabled",  $attrVal, 1);
  } elsif ( $attrName eq "switchInThePast" ) {
     $attr{$name}{$attrName} = $attrVal;     
####$hash->{TYPE}_SetTimerOfDay({ HASH => $hash});      
     WeekdayTimer_SetTimerOfDay({ HASH => $hash}); 
  }
  return undef;
}
########################################################################
sub WeekdayTimer_SetParm($) {
  my ($name) = @_;
  
  my $hash = $modules{WeekdayTimer}{defptr}{$name};
  if(defined $hash) {
     WeekdayTimer_DeleteTimer($hash);
     WeekdayTimer_SetTimer($hash);
     Log3 undef, 3, "WeekdayTimer_SetParm() for $hash->{NAME} done!";
  }   
}
################################################################################
sub WeekdayTimer_SetAllParms() {            # {WeekdayTimer_SetAllParms()}

  foreach my $wdName ( sort keys %{$modules{WeekdayTimer}{defptr}} ) {
     WeekdayTimer_SetParm($wdName);
  }
  Log3 undef,  3, "WeekdayTimer_SetAllParms() done!";
}

1;

=pod
=begin html

<a name="WeekdayTimer"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>WeekdayTimer</h3>
<ul>
  <br>
  <a name="weekdayTimer_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WeekdayTimer &lt;device&gt; [&lt;language&gt;] [<u>weekdays</u>] &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
    <br><br>

    to set a weekly profile for &lt;device&gt;<br><br>

    You can define different switchingtimes for every day.<br>
    The new parameter is sent to the &lt;device&gt; automatically with <br><br>

    <code>set &lt;device&gt; &lt;para&gt;</code><br><br>

    If you have defined a &lt;condition&gt; and this condition is false if the switchingtime has reached, no command will executed.<br>
    An other case is to define an own perl command with &lt;command&gt;.
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
    <ul><b>weekdays</b><br>
      Specifies the days for all timer in the <b>WeekdayTimer</b>.
      The parameter is optional. For details see the weekdays part in profile.
    </ul>
    <p>
    <ul><b>profile</b><br>
      Define the weekly profile. All timings are separated by space. A switchingtime is defined
      by the following example: <br><br>
      
      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;</b></ul><br>
      
      <u>weekdays:</u> optional, if not set every day of the week is used.<br>
        Otherwise you can define a day with its number or its shortname.<br>
        <ul> 
        <li>0,su  sunday</li>
        <li>1,mo  monday</li>
        <li>2,tu  tuesday</li>
        <li>3,we  wednesday</li>
        <li>4 ...</li>
        <li>7,$we  weekend  ($we)</li>
        <li>8,!$we weekday  (!$we)</li>
        </ul><br>
         It is possible to define $we or !$we in daylist to easily allow weekend an holiday. $we !$we are coded as 7 8, when using a numeric daylist.<br><br>
      <u>time:</u>define the time to switch, format: HH:MM:[SS](HH in 24 hour format) or a Perlfunction like {sunrise_abs()}. Within the {} you can use the variable $date(epoch) to get the exact switchingtimes of the week. Example: {sunrise_abs_dat($date)}<br><br>
      <u>parameter:</u>the parameter to be set, using any text value like <b>on</b>, <b>off</b>, <b>dim30%</b>, <b>eco</b> or <b>comfort</b> - whatever your device understands.<br>
    </ul>
    <p>
    <ul><b>command</b><br>
      If no condition is set, all the rest is interpreted as a command. Perl-code is setting up
      by the well-known Block with {}.<br>
      Note: if a command is defined only this command is executed. In case of executing
      a "set desired-temp" command, you must define the hole commandpart explicitly by yourself.<br>
  <!-- -------------------------------------------------------------------------- -->
  <!----------------------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
      <li>in the command section you can access the event:
      <ul>
        <li>The variable $EVENT will contain the complete event, e.g.
          <code>measured-temp: 21.7 (Celsius)</code></li>
        <li>$EVTPART0,$EVTPART1,$EVTPART2,etc contain the space separated event
          parts (e.g. <code>$EVTPART0="measured-temp:", $EVTPART1="21.7",
          $EVTPART2="(Celsius)"</code>. This data is available as a local
          variable in perl, as environment variable for shell scripts, and will
          be textually replaced for FHEM commands.</li>
        <li>$NAME contains the device to send the event, e.g.
          <code>myFht</code></li>
       </ul></li>

      <li>Note: the following is deprecated and will be removed in a future
        release. The described replacement is attempted if none of the above
        variables ($NAME/$EVENT/etc) found in the command.
      <ul>
        <li>The character <code>%</code> will be replaced with the received
        event, e.g. with <code>on</code> or <code>off</code> or
        <code>measured-temp: 21.7 (Celsius)</code><br> It is advisable to put
        the <code>%</code> into double quotes, else the shell may get a syntax
        error.</li>

        <li>The character <code>@</code> will be replaced with the device
        name.</li>

        <li>To use % or @ in the text itself, use the double mode (%% or
        @@).</li>

        <li>Instead of <code>%</code> and <code>@</code>, the parameters
        <code>%EVENT</code> (same as <code>%</code>), <code>%NAME</code> (same
        as <code>@</code>) and <code>%TYPE</code> (contains the device type,
        e.g.  <code>FHT</code>) can be used. The space separated event "parts"
        are available as %EVTPART0, %EVTPART1, etc.  A single <code>%</code>
        looses its special meaning if any of these parameters appears in the
        definition.</li>
      </ul></li>
  <!-- -------------------------------------------------------------------------- -->
  <!----------------------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
      The following parameter are replaced:<br>
        <ol>
          <li>@ => the device to switch</li>
          <li>% => the new temperature</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      if a condition is defined you must declared this with () and a valid perl-code.<br>
      The return value must be boolean.<br>
      The parameter @ and % will be interpreted.
    </ul>
    <p>
    <b>Example:</b>
    <ul>
        <code>define shutter WeekdayTimer bath 12345|05:20|up  12345|20:30|down</code><br>
        Mo-Fr are setting the shutter at 05:20 to <b>up</b>, and at 20:30 <b>down</b>.<p>

        <code>define heatingBath WeekdayTimer bath 07:00|16 Mo,Tu,Th-Fr|16:00|18.5 20:00|eco
          {fhem("set dummy on"); fhem("set @ desired-temp %");}</code><br>
        At the given times and weekdays only(!) the command will be executed.<p>

        <code>define dimmer WeekdayTimer livingRoom Sa-Su,We|07:00|dim30% Sa-Su,We|21:00|dim90% (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        The dimmer is only set to dimXX% if the dummy variable WeAreThere is "yes"(not a real live example).<p>

        If you want to have set all WeekdayTimer their current value (after a temperature lowering phase holidays)
        you can call the function <b>WeekdayTimer_SetParm(&lt;"WD-device"&gt;)</b> or <b>WeekdayTimer_SetAllParms()</b>.<br>
        This call can be automatically coupled to a dummy by a notify:<br>
        <code>define dummyNotify notify Dummy:. * {WeekdayTimer_SetAllTemps()}</code>
        <br><p>
        Some definitions without comment:
        <code>
        <pre> 
        define hc    Heating_Control  HeizungKueche de        7|23:35|25        34|23:30|22 23:30|16 23:15|22     8|23:45|16 
        define hc    Heating_Control  HeizungKueche de        fr,$we|23:35|25   34|23:30|22 23:30|16 23:15|22    12|23:45|16  
        define hc    Heating_Control  HeizungKueche de        20:35|25          34|14:30|22 21:30|16 21:15|22    12|23:00|16 
        
        define hw    Heating_Control  HeizungKueche de        mo-so, $we|{sunrise_abs_dat($date)}|18      mo-so, $we|{sunset_abs_dat($date)}|22  
        define ht    Heating_Control  HeizungKueche de        mo-so,!$we|{sunrise_abs_dat($date)}|18      mo-so,!$we|{sunset_abs_dat($date)}|22 
        
        define hh    Heating_Control  HeizungKueche de        {sunrise_abs_dat($date)}|19           {sunset_abs_dat($date)}|21  
        define hx    Heating_Control  HeizungKueche de        22:35|25  23:00|16    
        </code></pre>
        The daylist can be given globaly for the whole Heating_Control:<p>
        <code><pre>
        define HeizungWohnen_an_wt    Heating_Control HeizungWohnen de  !$we     09:00|19  (heizungAnAus("Ein"))  
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   $we     09:00|19  (heizungAnAus("Ein"))  
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   78      09:00|19  (heizungAnAus("Ein"))  
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   57      09:00|19  (heizungAnAus("Ein"))  
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de  fr,$we   09:00|19  (heizungAnAus("Ein"))  
        </code></pre>
    </ul>
  </ul>

  <a name="WeekdayTimerset"></a>
  <b>Set</b>

    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    <b>disable</b>               # disables the Weekday_Timer
    <b>enable</b>                # enables  the Weekday_Timer
    </pre>

    <b><font size="+1">Examples</font></b>:
    <ul>
      <code>set wd disable</code><br>
      <code>set wd enable</code><br>
    </ul>
  </ul>  

  <a name="WeekdayTimerget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="WeekdayTimerLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li>delayedExecutionCond <br> 
    defines a delay Function. When returning true, the switching of the device is delayed until the function retruns a false value. The behavior is just like a windowsensor in Heating_Control.
    
    <br><br>
    <b>Example:</b>    
    <pre>
    attr wd delayedExecutionCond isDelayed("%HEATING_CONTROL","%WEEKDAYTIMER","%TIME","%NAME","%EVENT")  
    </pre>
    the parameter %WEEKDAYTIMER(timer name) %TIME %NAME(device name) %EVENT are replaced at runtime by the correct value.
    
    <br><br>
    <b>Example of a function:</b>    
    <pre>
    sub isDelayed($$$$$) {
       my($hc, $wdt, $tim, $nam, $event ) = @_;
       
       my $theSunIsStillshining = ...
    
       return ($tim eq "16:30" && $theSunIsStillshining) ;    
    }
    </pre>    
    </li>
    <li>switchInThePast<br> 
    defines that the depending device will be switched in the past in definition and startup phase when the device is not recognized as a heating.
    Heatings are always switched in the past.
    </li>    
    
    <li><a href="#disable">disable</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
  </ul><br>

=end html

=cut