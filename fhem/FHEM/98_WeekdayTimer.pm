# $Id$
#############################################################################
#
#     98_WeekdayTimer.pm
#     written by Dietmar Ortmann
#     modified by Tobias Faust
#     Maintained by Beta-User since 11-2019
#     Thanks Dietmar for all you did for FHEM, RIP
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
##############################################################################

package FHEM::WeekdayTimer;    ## no critic 'Package declaration'

use strict;
use warnings;

use Time::Local qw( timelocal_nocheck );
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Scalar::Util qw( weaken );
use FHEM::Core::Timer::Register qw(:ALL);

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          defs
          modules
          attr
          init_done
          DAYSECONDS
          MINUTESECONDS
          readingFnAttributes
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          AttrVal
          ReadingsVal
          ReadingsNum
          InternalVal
          Value
          IsWe
          Log3
          InternalTimer
          RemoveInternalTimer
          CommandAttr
          CommandDeleteAttr
          CommandGet
          getAllSets
          AnalyzeCommandChain
          AnalyzePerlCommand
          EvalSpecials
          perlSyntaxCheck
          devspec2array
          addToDevAttrList
          FmtDateTime
          sunrise_abs
          sunset_abs
          trim
          stacktrace
          decode_json
          looks_like_number
          )
    );
}

sub ::WeekdayTimer_Initialize { goto &Initialize }
sub ::WeekdayTimer_SetParm { goto &WeekdayTimer_SetParm }
sub ::WeekdayTimer_SetAllParms { goto &WeekdayTimer_SetAllParms }

################################################################################
sub Initialize {
  my $hash = shift // return;

# Consumer
  $hash->{SetFn}    = \&Set;
  $hash->{DefFn}    = \&Define;
  $hash->{UndefFn}  = \&Undef;
  $hash->{DeleteFn} = \&Delete;
  $hash->{GetFn}    = \&Get;
  $hash->{AttrFn}   = \&Attr;
  $hash->{UpdFn}    = \&WeekdayTimer_Update;
  $hash->{AttrList} = "disable:0,1 delayedExecutionCond WDT_delayedExecutionDevices WDT_Group switchInThePast:0,1 commandTemplate WDT_eventMap:textField-long WDT_sendDelay:slider,0,1,300,1 $readingFnAttributes";
  return;
}

################################################################################
sub Define {
  my $hash = shift;
  my $def  = shift // return;
  _InitHelper($hash);
  my @arr = split m{\s+}xms, $def;

  return "Usage: define <name> $hash->{TYPE} <device> <language> <switching times> <condition|command>"
     if(@arr < 4);

  #fuer den modify Altlasten bereinigen
  delete $hash->{helper};

  my $name     = shift @arr;
  my $type     = shift @arr;
  my $device   = shift @arr;

  #_DeleteTimer($hash);
  deleteAllRegIntTimer($hash);
  my $delVariables = "(CONDITION|COMMAND|profile|Profil)";
  map { delete $hash->{$_} if m{\A$delVariables.*}xms }  keys %{$hash};

  $hash->{NAME}            = $name;
  $hash->{DEVICE}          = $device;
  my $language = getWDTLanguage  ($hash, \@arr);

  my $idx = 0;
  
  $hash->{'.dayNumber'}    = {map {$_ => $idx++}     @{$hash->{'.shortDays'}{$language}}};
  $hash->{helper}{daysRegExp}        = '(' . join (q{|},        @{$hash->{'.shortDays'}{$language}}) . ')';
  $hash->{helper}{daysRegExpMessage} = $hash->{helper}{daysRegExp};

  $hash->{helper}{daysRegExp}   =~ s{\$}{\\\$}gxms;
  $hash->{helper}{daysRegExp}   =~ s{\!}{\\\!}gxms;

  $hash->{CONDITION}  = q{}; 
  $hash->{COMMAND}    = q{};

  addToDevAttrList($name, 'weekprofile') if $def =~ m{weekprofile}xms;
  
  if (!$init_done) { 
    InternalTimer(time, \&WDT_Start,$hash,0) ;
    return;
  }
  WDT_Start($hash);
  return; 
}

################################################################################
sub Undef {
  my $hash = shift;
  my $arg = shift // return;

  deleteAllRegIntTimer($hash);
  deleteSingleRegIntTimer($hash->{VERZOEGRUNG_IDX},$hash) if defined $hash->{VERZOEGRUNG_IDX}; 

  #delete $modules{$hash->{TYPE}}{defptr}{$hash->{NAME}};
  return deleteSingleRegIntTimer('SetTimerOfDay', $hash);
}

################################################################################
sub WDT_Start {
  my $hash = shift // return;
  my $name = $hash->{NAME};
  my $def = $hash->{DEF};
  deleteSingleRegIntTimer($hash->{VERZOEGRUNG_IDX},$hash) if defined ($hash->{VERZOEGRUNG_IDX}); 
  my @arr = split m{\s+}xms, $def;
  my $device   = shift @arr;

  my $language = getWDTLanguage  ($hash, \@arr);
  
  _GlobalDaylistSpec ($hash, \@arr);

  my @switchingtimes       = gatherSwitchingTimes ($hash, \@arr);
  my $conditionOrCommand   = join q{ }, @arr;
  my @errors;
  # test if device is defined
  if ( !$defs{$device} ) { 
    Log3( $hash, 3, "[$name] device <$device> in fhem not defined, but accepted") ;
    if ( $init_done ) { push @errors, qq(device <$device> in fhem not defined) };
  }
  # wenn keine switchintime angegeben ist, dann Fehler
  if (@switchingtimes == 0) {
    Log3( $hash, 3, "[$name] no valid Switchingtime found in <$conditionOrCommand>, check parameters or make sure weekprofile device exists and returns valid data." ) ;
    if($init_done) { push @errors, qq(no valid switchingtime found in <$conditionOrCommand>, check parameters or make sure weekprofile device exists and returns valid data.) };
  }
  $hash->{STILLDONETIME}  = 0;
  $hash->{SWITCHINGTIMES} = \@switchingtimes;
  $attr{$name}{verbose}   = 5 if !defined $attr{$name}{verbose} && $name =~ m{\Atst.*}xms;
  $defs{$device}{STILLDONETIME} = 0 if $defs{$device};

  #$modules{$hash->{TYPE}}{defptr}{$hash->{NAME}} = $hash;

  if ( $conditionOrCommand =~  m{\A\(.*\)\z}xms ) {         #condition (*)
    $hash->{CONDITION} = $conditionOrCommand;
    my %specials   = ( "%NAME" => $hash->{DEVICE}, "%EVENT" => "0");
    my $r = perlSyntaxCheck(qq({$conditionOrCommand}),%specials);
    if ( $r ) { 
      Log3( $hash, 2, "[$name] check syntax of CONDITION <$conditionOrCommand>" ) ;
      if ( $init_done ) { push @errors, qq(check syntax of CONDITION <$conditionOrCommand>: $r) };
    }
  } elsif ( length($conditionOrCommand) > 0 ) {
    $hash->{COMMAND} = $conditionOrCommand;
  }

  _Profile ($hash);
  delete $hash->{VERZOEGRUNG};
  delete $hash->{VERZOEGRUNG_IDX};

  $attr{$name}{commandTemplate} =
     'set $NAME '. checkIfDeviceIsHeatingType($hash) .' $EVENT' if !defined $attr{$name}{commandTemplate};

  WeekdayTimer_SetTimerOfDay({ HASH => $hash});

  return if !$init_done;
  return join('\n', @errors) if (@errors); 
  return;
}

sub Delete {
  my $hash = shift // return;

  deleteAllRegIntTimer($hash);
  RemoveInternalTimer($hash);
  deleteSingleRegIntTimer($hash->{VERZOEGRUNG_IDX},$hash) if defined $hash->{VERZOEGRUNG_IDX}; 
  return;
}

################################################################################
sub Set {
  my ($hash,@arr) = @_;

  return "no set value specified" if int(@arr) < 2;
  return "Unknown argument $arr[1], choose one of enable:noArg disable:noArg WDT_Params:single,WDT_Group,all weekprofile" if $arr[1] eq '?';

  my $name = shift @arr;
  my $v    = join q{ }, @arr;

  if ($v eq 'enable') {
    Log3( $hash, 3, "[$name] set $name $v" );
    if (AttrVal($name, "disable", 0)) {
      CommandAttr(undef, "$name disable 0");
    } else {
      WeekdayTimer_SetTimerOfDay({ HASH => $hash});
    }
    return;
  } 
  if ($v eq 'disable') {
    Log3( $hash, 3, "[$name] set $name $v" );
    return CommandAttr(undef, "$name disable 1");
  }
  if ($v =~ m{\AWDT_Params}xms) {
    if ($v =~  m{single}xms) {
      Log3( $hash, 4, "[$name] set $name $v called" );
      return WeekdayTimer_SetParm($name);
    } 
    if ($v =~  m{WDT_Group}xms) {
      my $group = AttrVal($hash->{NAME},"WDT_Group",undef) // return Log3( $hash, 3, "[$name] set $name $v cancelled: group attribute not set for $name!" );
      return WeekdayTimer_SetAllParms($group);
    } elsif ($v =~ m{all}xms){
      Log3( $hash,3, "[$name] set $name $v called; params in all WeekdayTimer instances will be set!" );
      return WeekdayTimer_SetAllParms('all');
    }
    return;
  } 
  if ($v =~ m{\Aweekprofile[ ]([^: ]+):([^:]+):([^: ]+)\b}xms) {
    Log3( $hash, 3, "[$name] set $name $v" );
    return if !updateWeekprofileReading($hash, $1, $2, $3);
    _DeleteTimer($hash);
    return WDT_Start($hash);
  }
  return;
}

################################################################################
sub Get {
  my ($hash, @arr) = @_;
  return "argument is missing" if int(@arr) != 2;

  $hash->{LOCAL} = 1;
  delete $hash->{LOCAL};
  my $reading= $arr[1];
  my $value;

  if ( defined $hash->{READINGS}{$reading} ) {
    $value= $hash->{READINGS}{$reading}{VAL};
  } else {
    return "no such reading: $reading";
  }
  return "$arr[0] $reading => $value";
}


################################################################################
sub _InitHelper {
  my $hash = shift // return;
  
  delete $hash->{setModifier};
  
  $hash->{'.longDays'} =  { de => ["Sonntag",  "Montag","Dienstag","Mittwoch",  "Donnerstag","Freitag", "Samstag",  "Wochenende", "Werktags" ],
                         en => ["Sunday",   "Monday","Tuesday", "Wednesday", "Thursday",  "Friday",  "Saturday", "weekend",    "weekdays" ],
                         fr => ["Dimanche", "Lundi", "Mardi",   "Mercredi",  "Jeudi",     "Vendredi","Samedi",   "weekend",    "jours de la semaine"],
                         nl => ["Zondag", "Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag", "weekend", "werkdagen"]};
  $hash->{'.shortDays'} = { de => ["so","mo","di","mi","do","fr","sa",'$we','!$we'],
                         en => ["su","mo","tu","we","th","fr","sa",'$we','!$we'],
                         fr => ["di","lu","ma","me","je","ve","sa",'$we','!$we'],
                         nl => ["zo","ma","di","wo","do","vr","za",'$we','!$we']};

  return;
}

################################################################################

sub _Profile {
  my $hash = shift // return;

  my $language =   $hash->{LANGUAGE};
  my %longDays = %{$hash->{'.longDays'}};

  delete $hash->{profil};
  my $now = time;
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($now);
    
# ---- Zeitpunkte den Tagen zuordnen -----------------------------------
  my $idx = 0;
  for  my $st ( @{$hash->{SWITCHINGTIMES}} ) {
    my ($tage,$time,$parameter,$overrulewday) = _SwitchingTime ($hash, $st);

    
    $idx++;
    for  my $d (@{$tage}) {
      my    @listeDerTage = ($d);
      push  (@listeDerTage, _getDaysList($hash, $d, $time)) if ($d>=7);
      
      for my $day (@listeDerTage) {
        my $dayOfEchteZeit = $day;
        #####
        if ($day < 7) {
          my $relativeDay = ($day - $wday ) % 7;
          #my $relativeDay = $day - $wday; 
          #$relativeDay = $relativeDay + 7 if $relativeDay < 0 ;
          $dayOfEchteZeit = undef if ($hash->{helper}{WEDAYS}{$relativeDay} && $overrulewday);
        }
        $dayOfEchteZeit = ($wday>=1&&$wday<=5) ? 6 : $wday  if ($day==7); # ggf. Samstag $wday ~~ [1..5]
        $dayOfEchteZeit = ($wday==0||$wday==6) ? 1 : $wday  if ($day==8); # ggf. Montag  $wday ~~ [0, 6]
        if (defined $dayOfEchteZeit) { 
          my $echtZeit = _getHHMMSS($hash, $dayOfEchteZeit, $time);
          $hash->{profile}    {$day}{$echtZeit} = $parameter;
          $hash->{profile_IDX}{$day}{$echtZeit} = $idx;
        }
      };
    }
  }
# ---- Zeitpunkte des aktuellen Tages mit EPOCH ermitteln --------------
  $idx = 0;
  for  my $st (@{$hash->{SWITCHINGTIMES}}) {
    my ($tage,$time,$parameter,$overrulewday)       = _SwitchingTime ($hash, $st);
    my $echtZeit                      = _getHHMMSS     ($hash, $wday, $time);
    my ($stunde, $minute, $sekunde)   = split m{:}xms, $echtZeit;

    $idx++;
    $hash->{profil}{$idx}{TIME}  = $time;
    $hash->{profil}{$idx}{PARA}  = $parameter;
    $hash->{profil}{$idx}{EPOCH} = getSwitchtimeEpoch ($now, $stunde, $minute, $sekunde, 0);
    $hash->{profil}{$idx}{TAGE}  = $tage;
    $hash->{profil}{$idx}{WE_Override} = $overrulewday;
  }
# ---- Texte Readings aufbauen -----------------------------------------
  Log3( $hash, 4,  "[$hash->{NAME}] " . sunrise_abs() . " " . sunset_abs() . " " . $longDays{$language}[$wday] );
  for  my $d (sort keys %{$hash->{profile}}) {
    my $profiltext = q{};
    for  my $t (sort keys %{$hash->{profile}{$d}}) {
      $profiltext .= "$t " .  $hash->{profile}{$d}{$t} . ", ";
    }
    my $profilKey  = "Profil $d: $longDays{$language}[$d]";
    $profiltext =~ s{, $}{}xms;
    $hash->{$profilKey} = $profiltext;
    Log3( $hash, 4,  "[$hash->{NAME}] $profiltext ($profilKey)" );
  }

  # für logProxy umhaengen
  $hash->{helper}{SWITCHINGTIME} = $hash->{profile};
  delete $hash->{profile};
  return;
}

################################################################################
sub _getDaysList {
  my ($hash, $d, $time) = @_;
  my %hdays=();
  if (AttrVal('global', 'holiday2we', '') !~ m{\bweekEnd\b}xms) {
    @hdays{(0, 6)} = undef  if ($d==7); # sa,so   ( $we)
    @hdays{(1..5)} = undef  if ($d==8); # mo-fr   (!$we)
  } else {
    @hdays{(0..6)} = undef  if ($d==8); # mo-fr   (!$we)
  }
  my ($sec,$min,$hour,$mday,$mon,$year,$nowWday,$yday,$isdst) = localtime(time);
  for (0..6) {
    my $relativeDay = ( $_ - $nowWday ) % 7;
    if ($hash->{helper}{WEDAYS}{$relativeDay}) {
      $hdays{$_} = undef if ($d==7); # $we Tag aufnehmen
      delete $hdays{$_} if ($d==8);  # !$we Tag herausnehmen
    }
  }

  #Log 3, "result------------>" . join (" ", sort keys %hdays);
  return keys %hdays;
}

################################################################################
sub _SwitchingTime {
  my $hash = shift;
  my $switchingtime = shift // return;

  my $name = $hash->{NAME};
  my $globalDaylistSpec = $hash->{GlobalDaylistSpec};
  my @tageGlobal = @{_daylistAsArray($hash, $globalDaylistSpec)};

  my (@st, $daylist, $time, $timeString, $para);
  @st = split m{\|}xms, $switchingtime;
  my $overrulewday = 0;
  if ( @st == 2 || @st == 3 && $st[2] eq 'w') {
    $daylist = ($globalDaylistSpec ne '') ? $globalDaylistSpec : '0123456';
    $time    = $st[0];
    $para    = $st[1];
    $overrulewday = 1 if defined $st[2] && $st[2] eq 'w';
  } elsif ( @st == 3 || @st == 4) {
    $daylist  = $st[0];
    $time     = $st[1];
    $para     = $st[2];
    $overrulewday = 1 if defined $st[3] && $st[3] eq 'w';
  }

  my @tage = @{_daylistAsArray($hash, $daylist)};
  #my $tage=@tage;
  Log3( $hash, 1, "[$name] invalid daylist in $name <$daylist> use one of 012345678 or $hash->{helper}{daysRegExpMessage}" ) if !(@tage);

  my %hdays=();
  @hdays{@tageGlobal} = undef;
  @hdays{@tage}       = undef;
  #@tage = sort keys %hdays;

  #Log3 $hash, 3, "Tage: " . Dumper \@tage;
  #return (\@tage,$time,$para,$overrulewday);
  return ([sort keys %hdays], $time, $para, $overrulewday);
}

################################################################################
sub _daylistAsArray {
  my ($hash, $daylist) = @_;

  my $name = $hash->{NAME};
  my @days;

  my %hdays=();
  $daylist = lc($daylist);

  # Analysis of daylist setting by user
  # first replace textual settings by numbers 
  if ( $daylist =~ m{\A($hash->{helper}{daysRegExp}(,|-|$)){0,7}\z}gxms ) {
    my @subDays;
    my @aufzaehlungen = split m{,}xms, $daylist;
    for my $einzelAufzaehlung (@aufzaehlungen) {
      @days = split m{-}xms, $einzelAufzaehlung;
      if (@days == 1) {
        #einzelner Tag: Sa
        $hdays{$hash->{'.dayNumber'}{$days[0]}} = undef;
      } else {
        # von bis Angabe: Mo-Di
        my $von  = $hash->{'.dayNumber'}{$days[0]};
        my $bis  = $hash->{'.dayNumber'}{$days[1]};
        if ($von <= $bis) {
          @subDays = ($von .. $bis);
        } else {
          #@subDays = ($dayNumber{so} .. $bis, $von .. $dayNumber{sa});
          # was until percritic: @subDays = (           00  .. $bis, $von ..            06);

          @subDays = (           0  .. $bis, $von ..            6);
        }
        @hdays{@subDays}=undef;
      }
    }
    if ($daylist =~ m{\$we.+\$we}xms && $daylist =~ m{\!\$we}xms) {
      Log3( $hash, 4, "[$name] useless double setting of textual \$we and !\$we found" );
      delete $hdays{8};
      delete $hdays{7};
      @subDays = (0..6);
      @hdays{@subDays}=undef;
    } 
    #replace all text in $daylist by numbers
    $daylist = join q{}, sort keys %hdays;
  }

  # Angaben der Tage verarbeiten
  # Aufzaehlung 1234 ...
  if ( $daylist =~ m{\A[0-8]{0,9}\z}xms ) {

    #avoid 78 settings:
    if ($daylist =~ m{[7]}xms && $daylist =~ m{[8]}xms) {
      Log3( $hash, 4, "[$name] useless double setting of \$we and !\$we found" );
      $daylist = '0123456';
    }
    
    @days = split m{}x, $daylist;
    @hdays{@days} = undef;

  }

  my @tage = sort keys %hdays;

  return \@tage;
}

################################################################################
sub _getHHMMSS {
  my ($hash, $d, $time)  = @_;

  my $name = $hash->{NAME};

  my $now = time;
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($now);

  my $listOfDays = q{};

  # Zeitangabe verarbeiten.
  $time = qq{"$time"} if $time !~  m{\A\{.*\}\z}xms;
  my $date           = $now+($d-$wday)*DAYSECONDS;
  my $timeString     = '{ my $date='."$date;" .$time."}";
  my $eTimeString    = AnalyzePerlCommand( $hash, $timeString );                            # must deliver HH:MM[:SS]

  if ($@) {
    $@ =~ s{\n}{ }gxms;
    Log3( $hash, 3, "[$name] " . $@ . ">>>$timeString<<<" );
    $eTimeString = "00:00:00";
  }

  if      ($eTimeString =~  m{\A[0-2][0-9]:[0-5][0-9]\z}xms) {          #  HH:MM
    $eTimeString .= ":00";                                          #  HH:MM:SS erzeugen
  } elsif ($eTimeString !~  m{\A[0-2][0-9]:[0-5][0-9]:[0-5][0-9]\z}xms) {   # not HH:MM:SS
    Log3( $hash, 1, "[$name] invalid time <$eTimeString> HH:MM[:SS]" );
    $eTimeString = "00:00:00";
  }
  return $eTimeString;
}
################################################################################

sub getSwitchtimeEpoch {
  my ($now, $hour, $min, $sec, $days) = @_;

  my @jetzt_arr = localtime($now);
  #Stunden               Minuten               Sekunden
  $jetzt_arr[2]  = $hour; $jetzt_arr[1] = $min; $jetzt_arr[0] = $sec;
  $jetzt_arr[3] += $days;
  my $next = timelocal_nocheck(@jetzt_arr);
  return $next;
}

################################################################################
sub gatherSwitchingTimes {
  my $hash = shift;
  my $arr    = shift // return;

  my $name = $hash->{NAME};
  my @switchingtimes = ();
  my $conditionOrCommand;

  # switchingtime einsammeln
  while ( @{ $arr } > 0 ) {

    #pruefen auf Angabe eines Schaltpunktes
    my $element = q{};
    my @restoreElements = ();
E:  while ( @{ $arr } > 0 ) {

      my $actualElement = shift @{ $arr };
      push @restoreElements, $actualElement;
      #$element = $element . $actualElement . " ";
      $element .= "$actualElement ";
      Log3( $hash, 5, "[$name] $element - trying to accept as a switchtime" );

      my $balancedSign1 = $element =~ tr/'//; #'
      my $balancedSign2 = $element =~ tr/"//; #" 

      if ( $balancedSign1 % 2 || $balancedSign2 % 2 ) { # ungerade Anzahl quotes, dann verlängern
        Log3( $hash, 5, "[$name] $element - unbalanced quotes: $balancedSign1 single and $balancedSign2 double quotes found" );
        next E;
      }
      
      my $balancedSignA1 = $element =~ tr/(//;
      my $balancedSignA2 = $element =~ tr/)//;
      my $balancedSignB1 = $element =~ tr/{//;
      my $balancedSignB2 = $element =~ tr/}//;
    
      my $balancedSignA = $balancedSignA1 - $balancedSignA2;
      my $balancedSignB = $balancedSignB1 - $balancedSignB2;

      if ( $balancedSignA || $balancedSignB ) { # öffnende/schließende Klammern nicht gleich, dann verlängern
        Log3( $hash, 5, "[$name] $element - unbalanced brackets (: $balancedSignA1 ): $balancedSignA2 {: $balancedSignB1 }: $balancedSignB2" );
        next E;
      }
      last;
    }

    # ein space am Ende wieder abschneiden
    chop $element;
    my @t = split m{\|}xms, $element;

    if ( (@t > 1 && @t < 5) && $t[0] ne '' && $t[1] ne '' ) {
      Log3( $hash, 4, "[$name] $element - accepted");

      #transform daylist to pure nummeric notation
      if ( @t > 2) {
        $t[0] = join q{}, @{_daylistAsArray($hash, $t[0])};
        if ( $t[0] eq '' ) {
          $t[0] = '0123456' ;
          Log3( $hash, 2, "[$name] $element seems to be not valid and has been replaced by all days!");
        }
        $element = join q{|}, @t;
      }

      push(@switchingtimes, $element);
    } elsif ($element =~ m{\Aweekprofile}xms ) {
      my @wprof = split m{:}xms, $element;
      my $wp_name = $wprof[1];
      my $triplett = getWeekprofileReadingTriplett($hash, $wp_name, $wprof[2]);
      my ($unused,$wp_profile);
      ($unused,$wp_profile) = split m{:}xms, $triplett,2 if defined $triplett;
      $triplett = getWeekprofileReadingTriplett($hash, $wp_name, 'default');

      ($unused,$wp_profile) = split m{:}xms, $triplett,2 if defined $triplett && !$wp_profile && $wprof[2] ne 'default';

      return if !$wp_profile;

      my $wp_sunaswe = $wprof[2] // 0;
      my $wp_profile_data = CommandGet(undef,"$wp_name profile_data $wp_profile 0");
      if ($wp_profile_data =~ m{(profile.*not.found|usage..profile_data..name)}xms ) {
        Log3( $hash, 3, "[$name] weekprofile $wp_name: no profile named \"$wp_profile\" available" );
        return;
      }
      my $wp_profile_unpacked = decode_json($wp_profile_data);
      $hash->{weekprofiles}{$wp_name} = {'PROFILE'=>$wp_profile,'PROFILE_JSON'=>$wp_profile_data,'SunAsWE'=>$wp_sunaswe,'PROFILE_DATA'=>$wp_profile_unpacked };
      my %wp_shortDays = ("Mon"=>1,"Tue"=>2,"Wed"=>3,"Thu"=>4,"Fri"=>5,"Sat"=>6,"Sun"=>0);
      for my $wp_days (sort keys %{$hash->{weekprofiles}{$wp_name}{PROFILE_DATA}}) {
        my $wp_times = $hash->{weekprofiles}{$wp_name}{PROFILE_DATA}{$wp_days}{time};
        my $wp_temps = $hash->{weekprofiles}{$wp_name}{PROFILE_DATA}{$wp_days}{temp};
        my $wp_shortDay = $wp_shortDays{$wp_days};
        for ( 0..@{ $wp_temps }-1 ) {
          my $itime = $_ ? $hash->{weekprofiles}{$wp_name}{PROFILE_DATA}{$wp_days}{time}[$_-1] 
                         : '00:10';
          my $itemp = $hash->{weekprofiles}{$wp_name}{PROFILE_DATA}{$wp_days}{temp}[$_];
          my $wp_dayprofile = "$wp_shortDay"."|$itime" . "|$itemp";
          $wp_dayprofile .= "|w" if $wp_sunaswe eq "true";
          push(@switchingtimes, $wp_dayprofile);
          if ($wp_sunaswe eq "true" && !$wp_shortDay) {
            $wp_dayprofile = "7|$itime" . "|$itemp";
            push(@switchingtimes, $wp_dayprofile);
          }
        }
      }
    } else {
      Log3( $hash, 4, "[$name] $element - NOT accepted, must be command or condition" );
      unshift @{ $arr }, @restoreElements;
      last;
    }
  }
  return (@switchingtimes);
}

################################################################################
sub getWDTLanguage {
  my ($hash, $arr) = @_;

  my $name = $hash->{NAME};

  # ggf. language optional Parameter
  my $langRegExp = "(" . join ( q{|}, keys(%{$hash->{'.shortDays'}})) . ")";
  my $language   = shift @{ $arr };

  if ( $language !~  m{\A$langRegExp\z}xms ) {
  Log3( $hash, 3, "[$name] language: $language not recognized, use one of $langRegExp" ) if ( length($language) == 2 && $language !~  m{\A[0-9]+\z}gmx );
    unshift @{ $arr }, $language;
    $language = lc(AttrVal('global','language','en'));
    $language = $language =~  m{\A$langRegExp\z}xms ? $language : 'en';
  }
  $hash->{LANGUAGE} = $language;

  return ($langRegExp, $language);
}

################################################################################
sub _GlobalDaylistSpec {
  my ($hash, $arr) = @_;

  my $daylist = shift @{ $arr };

  my @tage = @{ _daylistAsArray( $hash, $daylist ) };

  unshift @{ $arr }, $daylist if !@tage;

  $hash->{GlobalDaylistSpec} = join q{}, @tage;
  return;
}

################################################################################
sub _SetTimerForMidnightUpdate {
  my $fnHash = shift;
  my $hash = $fnHash->{HASH} // $fnHash;
  return if !defined $hash;

  my $now = time;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);

  my $midnightPlus5Seconds = getSwitchtimeEpoch  ($now, 0, 0, 5, 1);
  deleteSingleRegIntTimer('midnight', $hash,\&WeekdayTimer_SetTimerOfDay);
  $fnHash = setRegIntTimer('midnight', $midnightPlus5Seconds, \&WeekdayTimer_SetTimerOfDay, $hash, 0) if !AttrVal($hash->{NAME},'disable',0);
  $fnHash->{SETTIMERATMIDNIGHT} = 1;

  return;
}

################################################################################
sub WeekdayTimer_SetTimerOfDay {
  my $fnHash = shift // return;
  my $hash = $fnHash->{HASH} // $fnHash;
  return if !defined $hash;
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $secSinceMidnight = 3600*$hour + 60*$min + $sec;

  my %wedays =();

  my $iswe = IsWe();
  $wedays{(0)} = $iswe if $iswe;
  $iswe = IsWe('tomorrow');
  $wedays{(1)} = $iswe if $iswe;

  for (2..6) {
    my $noWeekEnd = 0;
    my $ergebnis = 'none';
    my $izeit = time + DAYSECONDS * $_;
    my ($isec,$imin,$ihour,$imday,$imon,$iyear,$iwday,$iyday,$iisdst) = localtime($izeit);
  
    for my $h2we (split m{,}xms, AttrVal('global', 'holiday2we', '')) {
      if($h2we && ( $ergebnis eq 'none' || $h2we eq "noWeekEnd" )  && InternalVal($h2we, 'TYPE', '') eq 'holiday' && !$noWeekEnd) {
        $ergebnis = CommandGet(undef,$h2we . ' ' . sprintf("%02d-%02d",$imon+1,$imday));
        if ($ergebnis ne 'none' && $h2we eq 'noWeekEnd') {
          $ergebnis = 'none';
          $noWeekEnd = 1;
        }
      }
    }
    if ($ergebnis ne 'none') {
      $wedays{$_} = $ergebnis ;
    } else {
      if ($iwday == 0 || $iwday == 6) { 
        $wedays{$_} = 1;
        delete $wedays{$_} if AttrVal('global', 'holiday2we', '') =~ m{\bweekEnd\b}xms; 
      } else {
        delete $wedays{$_};
      }
    }
  }
  $hash->{helper}{WEDAYS} = \%wedays;
  $hash->{SETTIMERATMIDNIGHT} = $fnHash->{SETTIMERATMIDNIGHT}; 
  _DeleteTimer($hash);
  _Profile    ($hash);
  _SetTimer   ($hash) if !AttrVal($hash->{NAME},'disable',0);
  delete $hash->{SETTIMERATMIDNIGHT};
  _SetTimerForMidnightUpdate( $hash );
  return;
}

################################################################################
sub _SetTimer {
  my $hash = shift // return;
  my $name = $hash->{NAME};

  my $now  = time;

  my $isHeating         = checkIfDeviceIsHeatingType($hash);
  my $swip              = AttrVal($name, 'switchInThePast', 0);
  my $switchInThePast   = ($swip || $isHeating);

  Log3( $hash, 4, "[$name] Heating recognized - switch in the past activated" ) if ($isHeating);
  Log3( $hash, 4, "[$name] no switch in the yesterdays because of the devices type($hash->{DEVICE} is not recognized as heating) - use attr switchInThePast" ) if ( !$switchInThePast && !defined $hash->{SETTIMERATMIDNIGHT} );

  my @switches = sort keys %{$hash->{profil}};
  return Log3( $hash, 3, "[$name] no switches to send, due to possible errors." ) if !@switches;

  readingsSingleUpdate ($hash, 'state', 'inactive', 1) if !defined $hash->{SETTIMERATMIDNIGHT};
  for(my $i=0; $i<=$#switches; $i++) {

    my $idx = $switches[$i];

    my $time        = $hash->{profil}{$idx}{TIME};
    my $timToSwitch = $hash->{profil}{$idx}{EPOCH};
    my $tage        = $hash->{profil}{$idx}{TAGE};
    my $para        = $hash->{profil}{$idx}{PARA};
    my $overrulewday = $hash->{profil}{$idx}{WE_Override};

    my $isActiveTimer = isAnActiveTimer ($hash, $tage, $para, $overrulewday);
    readingsSingleUpdate ($hash, 'state', 'active', 1)
      if !defined $hash->{SETTIMERATMIDNIGHT} && $isActiveTimer;

    if ( $timToSwitch - $now > -5 || defined $hash->{SETTIMERATMIDNIGHT} ) {
      if($isActiveTimer) {
        Log3( $hash, 4, "[$name] setTimer - timer seems to be active today: ".join( q{},@{$tage})."|$time|$para" );
        resetRegIntTimer("$idx", $timToSwitch + AttrVal($name,'WDT_sendDelay',0), \&WeekdayTimer_Update, $hash, 0);
      } else {
        Log3( $hash, 4, "[$name] setTimer - timer seems to be NOT active today: ".join(q{},@{$tage})."|$time|$para ". $hash->{CONDITION} );
        deleteSingleRegIntTimer("$idx", $hash);
      }
    }
  }

  return if defined $hash->{SETTIMERATMIDNIGHT};

  my ($aktIdx,$aktTime,$aktParameter,$nextTime,$nextParameter) =
    _searchAktNext($hash, time + 5);
  Log3( $hash, 3, "[$name] can not compute past switching time" ) if !defined $aktTime;

  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, 'nextUpdate', FmtDateTime($nextTime));
  readingsBulkUpdate ($hash, 'nextValue',  $nextParameter);
  readingsBulkUpdate ($hash, 'currValue',  $aktParameter);
  readingsEndUpdate  ($hash, 1);

  return if !$switchInThePast || !defined $aktTime || checkDelayedExecution($hash, $aktParameter, $aktIdx );
    # alle in der Vergangenheit liegenden Schaltungen sammeln und
    # nach 5 Sekunden in der Reihenfolge der Schaltzeiten
    # durch WeekdayTimer_delayedTimerInPast() als Timer einstellen
    # die Parameter merken wir uns kurzzeitig im hash
    #    modules{WeekdayTimer}{timerInThePast}
    my $device = $hash->{DEVICE};
    Log3( $hash, 4, "[$name] past timer on $hash->{DEVICE} at ". FmtDateTime($aktTime). " with  $aktParameter activated" );

    #my $parameter = $modules{WeekdayTimer}{timerInThePast}{$device}{$aktTime} // [];
    my $parameter = $hash->{helper}{timerInThePast}{$aktTime} // [];
    push @{$parameter},["$aktIdx", $aktTime, \&WeekdayTimer_Update, $hash, 0];
    $hash->{helper}{timerInThePast}{$device}{$aktTime} = $parameter;
    #$modules{WeekdayTimer}{timerInThePast}{$device}{$aktTime} = $parameter;

    #my $tipHash = $modules{WeekdayTimer}{timerInThePastHash} // $hash;
    my $tipHash = $hash->{helper}{timerInThePastHash} // $hash;
    #$tipHash    = $hash if !defined $tipHash;
    #$modules{WeekdayTimer}{timerInThePastHash} = $tipHash;
    #$tipHash = $hash->{helper}{timerInThePastHash} = $tipHash;
    $hash->{helper}{timerInThePastHash} = $tipHash;
    

    resetRegIntTimer('delayed', time + 5 + AttrVal($name,'WDT_sendDelay',0), \&WeekdayTimer_delayedTimerInPast, $tipHash, 0);
    

  return;
}

################################################################################
sub WeekdayTimer_delayedTimerInPast {
  my $fnHash = shift // return;
  my ($hash, $modifier) = ($fnHash->{HASH}, $fnHash->{MODIFIER});

  return if !defined($hash);

  my $tim = time;

  #my $tipIpHash = $modules{WeekdayTimer}{timerInThePast};
  my $tipIpHash = $hash->{helper}{timerInThePast};

  for my $device ( keys %{$tipIpHash} ) {
    for my $time ( sort keys %{$tipIpHash->{$device}} ) {
      Log3( $hash, 4, "[$hash->{NAME}] $device ".FmtDateTime($time).' '.($tim-$time).'s ' );

      for my $para ( @{$tipIpHash->{$device}{$time}} ) {
        my $mHash = resetRegIntTimer(@{$para}[0],@{$para}[1],@{$para}[2],@{$para}[3],@{$para}[4]);
        $mHash->{forceSwitch} = 1;
      }
    }
  }
  #delete $modules{WeekdayTimer}{timerInThePast};
  #delete $modules{WeekdayTimer}{timerInThePastHash};
  delete $hash->{helper}{timerInThePast};
  delete $hash->{helper}{timerInThePastHash};
  deleteSingleRegIntTimer('delayed', $hash, 1);
  return;
}

################################################################################
sub _searchAktNext {
  my ($hash, $now) = @_;
  my $name = $hash->{NAME};

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
  #Log3 $hash, 3, "[$name] such--->".FmtDateTime($now);

  my ($oldTag,  $oldTime,  $oldPara , $oldIdx);
  my ($nextTag, $nextTime, $nextPara, $nextIdx);

  my $language  =   $hash->{LANGUAGE};
  my %shortDays = %{$hash->{'.shortDays'}};

  my @realativeWdays  = ($wday..6,0..$wday-1,$wday..6,0..6);
  for (my $i=0;$i<=$#realativeWdays;$i++) {

    my $relativeDay = $i-7;
    my $relWday     = $realativeWdays[$i];

    for my $time (sort keys %{$hash->{helper}{SWITCHINGTIME}{$relWday}}) {
      my ($stunde, $minute, $sekunde) = split m{:}xms, $time;

      $oldTime  = $nextTime;
      $oldPara  = $nextPara;
      $oldIdx   = $nextIdx;
      $oldTag   = $nextTag;

      $nextTime = getSwitchtimeEpoch ($now, $stunde, $minute, $sekunde, $relativeDay);
      $nextPara = $hash->{helper}{SWITCHINGTIME}{$relWday}{$time};
      #$nextIdx  = $hash->{helper}{SWITCHINGTIME}{$relWday}{$time};
      $nextIdx  = $hash->{profile_IDX}{$relWday}{$time};
      $nextTag  = $relWday;

      #Log3 $hash, 3, $shortDays{$language}[$nextTag]." ".FmtDateTime($nextTime)." ".$nextPara." ".$nextIdx;
      my $ignore = 0;
      my $wend = 0;
      my $tage = $hash->{profil}{$nextIdx}{TAGE}[0];
      if ($wday==$relWday) {
        $wend = $hash->{helper}{WEDAYS}{0};
        $ignore = (($tage == 7 && !$wend ) || ($tage == 8 && $wend ));
      } elsif ( $wday==$relWday+1) {
        $wend = $hash->{helper}{WEDAYS}{1};
        $ignore = (($tage == 7 && !$wend ) || ($tage == 8 && $wend ));
      }
      if (!$ignore && $nextTime >= $now ) {
        return ($oldIdx, $oldTime, $oldPara, $nextTime, $nextPara);
      }
    }
  }
  return (undef,undef,undef,undef);
}

################################################################################
sub _DeleteTimer {
  my $hash = shift // return;
  map {deleteSingleRegIntTimer($_, $hash)} keys %{$hash->{profil}};
  return;
}

################################################################################
sub WeekdayTimer_Update {
  my $fnHash = shift // return;
  my $hash = $fnHash->{HASH} // $fnHash;
  return if (!defined($hash));

  my $name     = $hash->{NAME};
  my $idx      = $fnHash->{MODIFIER};
  my $now      = time;

  # Schaltparameter ermitteln
  my $tage        = $hash->{profil}{$idx}{TAGE};
  my $time        = $hash->{profil}{$idx}{TIME};
  my $newParam    = $hash->{profil}{$idx}{PARA};
  my $timToSwitch = $hash->{profil}{$idx}{EPOCH};
  my $overrulewday = $hash->{profil}{$idx}{WE_Override};

  #Log3 $hash, 3, "[$name] $idx ". $time . " " . $newParam . " " . join("",@$tage);

  # Fenserkontakte abfragen - wenn einer im Status closed, dann Schaltung um 60 Sekunden verzögern
  my $winopen = checkDelayedExecution($hash, $newParam, $idx);
  if ($winopen) {
    readingsSingleUpdate ($hash,  'state', ($winopen eq '1' or lc($winopen) eq 'true') ? 'open window' : $winopen, 1);
    return;
  }

  my $dieGanzeWoche = $hash->{helper}{WEDAYS}{0} ? [7]:[8];

  my ($activeTimer, $activeTimerState);
  if (defined $fnHash->{forceSwitch}) { #timer is delayed
    $activeTimer      = isAnActiveTimer ($hash, $dieGanzeWoche, $newParam, $overrulewday);
    $activeTimerState = isAnActiveTimer ($hash, $tage, $newParam, $overrulewday);
    Log3( $hash, 4, "[$name] Update   - past timer activated" );
    resetRegIntTimer("$idx", $timToSwitch, \&WeekdayTimer_Update, $hash, 0) if $timToSwitch > $now && ($activeTimerState || $activeTimer );
  } else {
    $activeTimer = isAnActiveTimer ($hash, $tage, $newParam, $overrulewday);
    $activeTimerState = $activeTimer;
    Log3( $hash, 4, "[$name] Update   - timer seems to be active today: ".join(q{},@{$tage})."|$time|$newParam" ) if ( $activeTimer && (@{$tage}) );
    Log3( $hash, 2, "[$name] Daylist is missing!") if !(@{$tage});
    deleteSingleRegIntTimer($idx, $hash, 1);
  }
  #Log3 $hash, 3, "activeTimer------------>$activeTimer";
  #Log3 $hash, 3, "activeTimerState------->$activeTimerState";
  my ($aktIdx, $aktTime,  $aktParameter, $nextTime, $nextParameter) =
    _searchAktNext($hash, time + 5);

  my $device   = $hash->{DEVICE};
  my $disabled = AttrVal($hash->{NAME}, 'disable', 0);

  # ggf. Device schalten
  Switch_Device($hash, $newParam, $tage)   if $activeTimer;

  readingsBeginUpdate($hash);
  readingsBulkUpdate ($hash, 'nextUpdate', FmtDateTime($nextTime));
  readingsBulkUpdate ($hash, 'nextValue',  $nextParameter);
  readingsBulkUpdate ($hash, 'currValue',  $aktParameter); # HB
  readingsBulkUpdate ($hash, 'state',      $newParam ) if $activeTimerState;
  readingsEndUpdate  ($hash, 1);

  return 1;

}

################################################################################
sub isAnActiveTimer {
  my ($hash, $tage, $newParam, $overrulewday)  = @_;

  my $name = $hash->{NAME};
  my %specials   = ( "%NAME" => $hash->{DEVICE}, "%EVENT" => $newParam);

  my $condition  = checkWDTCondition ($hash, $tage, $overrulewday);
  my $tageAsHash = getDaysAsHash($hash, $tage);
  my $xPression  = qq( { $tageAsHash ;; $condition } );
     $xPression  = EvalSpecials($xPression, %specials);
  Log3( $hash, 5, "[$name] condition: $xPression" );

  my $ret = AnalyzeCommandChain(undef, $xPression);
  Log3( $hash, 5, "[$name] result of condition: $ret" );
  return $ret;
}

################################################################################
sub checkIfDeviceIsHeatingType {
  my $hash  = shift // return q{};

  my $name = $hash->{NAME};

  return $hash->{setModifier} if defined $hash->{setModifier};

  my $dHash = $defs{$hash->{DEVICE}};
  return q{} if (!defined $dHash); # vorzeitiges Ende wenn das device nicht existiert

  my $dType = $dHash->{TYPE};
  return ""   if (!defined($dType) || $dType eq 'dummy' );

  my $dName = $dHash->{NAME};

  my @tempSet = qw(desired-temp desiredTemperature desired thermostatSetpointSet);
  my $allSets = getAllSets($dName);

  for my $ts (@tempSet) {
  if ($allSets =~ m{$ts}xms) {
      Log3( $hash, 4, "[$name] device type heating recognized, setModifier:$ts" );
      $hash->{setModifier} = $ts;
      return $ts
    }
  }
  $hash->{setModifier} = q{};
  return q{};
}

################################################################################
sub checkDelayedExecution {
  my ($hash, $event, $time) = @_;
  my $name = $hash->{NAME};

  my %specials = (
         '%WEEKDAYTIMER'     => $hash->{NAME},
         '%NAME'             => $hash->{DEVICE},
         '%EVENT'            => $event,
         '%TIME'             => $hash->{profil}{$time}{TIME},
         '$WEEKDAYTIMER'     => $hash->{NAME},
         '$NAME'             => $hash->{DEVICE},
         '$EVENT'            => $event,
         '$TIME'             => $hash->{profil}{$time}{TIME},
  );

  my $verzoegerteAusfuehrungCond = AttrVal($hash->{NAME}, 'delayedExecutionCond', 0);

  my $nextRetry = time + 55 + int(rand(10));
  my $epoch = $hash->{profil}{$time}{EPOCH};
  if (!$epoch) {                             #prevent FHEM crashing when profile is somehow damaged or incomlete, forum #109164
    my $actual_wp_reading = ReadingsVal($name,'weekprofiles','none');
    Log3( $hash, 0, "[$name] profile $actual_wp_reading, item $time seems to be somehow damaged or incomplete!" );
    $epoch = int(time) - 10*MINUTESECONDS;
    readingsSingleUpdate( $hash, 'corrupt_wp_count', ReadingsNum($name,'corrupt_wp_count', 0) + 1, 1 );
  }
  my $delay = int(time) - $epoch;
  my $nextDelay = int($delay/60.+1.5)*60;  # round to multiple of 60sec
  $nextRetry = $epoch + $nextDelay + AttrVal($name,'WDT_sendDelay',0);
  Log3( $hash, 4, "[$name] time=".$hash->{profil}{$time}{TIME}."/$epoch delay=$delay, nextDelay=$nextDelay, nextRetry=$nextRetry" );

  for my $key (keys %specials) {
    my $val = $specials{$key};
    $key =~ s{\$}{\\\$}gxms;
    $verzoegerteAusfuehrungCond =~ s{$key}{$val}gxms
  }
  Log3( $hash, 4, "[$name] delayedExecutionCond:$verzoegerteAusfuehrungCond" );

  my $verzoegerteAusfuehrung = AnalyzePerlCommand( $hash, $verzoegerteAusfuehrungCond );

  my $logtext = $verzoegerteAusfuehrung // 'no condition attribute set';
  Log3( $hash, 4, "[$name] result of delayedExecutionCond: $logtext" );

  if ($verzoegerteAusfuehrung) {
    if ( !defined $hash->{VERZOEGRUNG} ) {
      Log3( $hash, 3, "[$name] switch of $hash->{DEVICE} delayed - delayedExecutionCond: '$verzoegerteAusfuehrungCond' is TRUE" );
    }
    if ( defined $hash->{VERZOEGRUNG_IDX} && $hash->{VERZOEGRUNG_IDX}!=$time) {
      #Prüfen, ob der nächste Timer überhaupt für den aktuellen Tag relevant ist!

      Log3( $hash, 3, "[$name] timer at $hash->{profil}{$hash->{VERZOEGRUNG_IDX}}{TIME} skipped by new timer at $hash->{profil}{$time}{TIME}, delayedExecutionCond returned $verzoegerteAusfuehrung" );
      deleteSingleRegIntTimer($hash->{VERZOEGRUNG_IDX},$hash);
      #xxxxx add logic for last timer of day
      resetRegIntTimer($time, $hash->{profil}{$time}{EPOCH}, \&WeekdayTimer_Update, $hash, 0) 
        if $hash->{profil}{$time}{EPOCH} > time 
        && (isAnActiveTimer ($hash, $hash->{profil}{$time}{TAGE}, $hash->{profil}{$time}{PARA}, $hash->{profil}{$time}{WE_Override}) 
        || isAnActiveTimer ($hash, $hash->{helper}{WEDAYS}{0} ? [7]:[8], $hash->{profil}{$time}{PARA}, $hash->{profil}{$time}{WE_Override}) );
    }
    $hash->{VERZOEGRUNG_IDX} = $time;
    resetRegIntTimer("$time", $nextRetry, \&WeekdayTimer_Update, $hash, 0);
    $hash->{VERZOEGRUNG} = 1;
    return $verzoegerteAusfuehrung;
  }

  my %contacts =  ( CUL_FHTTK    => { READING => 'Window',          STATUS => '(Open)',               MODEL => 'r' },
                    CUL_HM       => { READING => 'state',           STATUS => '(open|tilted)',        MODEL => 'r' },
                    EnOcean      => { READING => 'state',           STATUS => '(open)',               MODEL => 'r' },
                    ZWave        => { READING => 'state',           STATUS => '(open)',               MODEL => 'r' },
                    MAX          => { READING => 'state',           STATUS => '(open.*)',             MODEL => 'r' },
                    dummy        => { READING => 'state',           STATUS => '(([Oo]pen|[Tt]ilt).*)',MODEL => 'r' },
                    HMCCUDEV     => { READING => 'state',           STATUS => "(open|tilted)",        MODEL => 'r' },
                    WeekdayTimer => { READING => 'delayedExecution',STATUS => '^1\$',                 MODEL => 'a' }
                  );

  my $fensterKontakte = $hash->{NAME} ." ". AttrVal($hash->{NAME}, 'WDT_delayedExecutionDevices', '');
  my $HC_fensterKontakte = AttrVal($hash->{NAME}, 'windowSensor', undef);
  $fensterKontakte .= " $HC_fensterKontakte" if defined $HC_fensterKontakte;
  $fensterKontakte = trim($fensterKontakte);

  Log3( $hash, 4, "[$name] list of window sensors found: '$fensterKontakte'" );
  for my $fk (split m{\s+}xms, $fensterKontakte) {
      #hier flexible eigene Angaben ermöglichen?, Schreibweise: Device[:Reading[:ValueToCompare[:Comparator]]]; defaults: Reading=state, ValueToCompare=0/undef/false, all other true, Comparator=eq (options: eq, ne, lt, gt, ==, <,>,<>)
      my $fk_hash = $defs{$fk};
      if (!$fk_hash) {
          Log3( $hash, 3, "[$name] sensor <$fk> not found - check name." );
          next;
      }
      my $fk_typ  = $fk_hash->{TYPE};
      if ( !defined $contacts{$fk_typ} ) {
          Log3( $hash, 3, "[$name] TYPE '$fk_typ' of $fk not yet supported, $fk ignored - inform maintainer" );
          next;
      }

      my $reading      = $contacts{$fk_typ}{READING};
      my $statusReg    = $contacts{$fk_typ}{STATUS};
      my $model        = $contacts{$fk_typ}{MODEL};

      my $windowStatus = $model eq 'r' ? ReadingsVal($fk,$reading,'nF')
                                       : AttrVal    ($fk,$reading,'nF');

      if ( $windowStatus eq 'nF' ) {
          Log3( $hash, 3, "[$name] Reading/Attribute '$reading' of $fk not found, $fk ignored - inform maintainer" ) if ( $model eq 'r' );
          next;
      }
      Log3( $hash, 5, "[$name] sensor '$fk' Reading/Attribute '$reading' is '$windowStatus'" );

      if ( $windowStatus =~  m{\A$statusReg\z}xms ) {
          if ( !defined $hash->{VERZOEGRUNG} ) {
              Log3( $hash, 3, "[$name] switch of $hash->{DEVICE} delayed - sensor '$fk' Reading/Attribute '$reading' is '$windowStatus'" );
          }
          if ( defined $hash->{VERZOEGRUNG_IDX} && $hash->{VERZOEGRUNG_IDX} != $time ) {
              Log3( $hash, 3, "[$name] timer at $hash->{profil}{$hash->{VERZOEGRUNG_IDX}}{TIME} skipped by new timer at $hash->{profil}{$time}{TIME} while window contact returned open state");
              deleteSingleRegIntTimer($hash->{VERZOEGRUNG_IDX},$hash);
              #xxxxx add logic for last timer of day
              resetRegIntTimer($time, $hash->{profil}{$time}{EPOCH}, \&WeekdayTimer_Update, $hash, 0) 
                if $hash->{profil}{$time}{EPOCH} > time 
                && (isAnActiveTimer ($hash, $hash->{profil}{$time}{TAGE}, $hash->{profil}{$time}{PARA}, $hash->{profil}{$time}{WE_Override}) 
                || isAnActiveTimer ($hash, $hash->{helper}{WEDAYS}{0} ? [7]:[8], $hash->{profil}{$time}{PARA}, $hash->{profil}{$time}{WE_Override}) );
          }
          $hash->{VERZOEGRUNG_IDX} = $time;
          resetRegIntTimer("$time", $nextRetry, \&WeekdayTimer_Update, $hash, 0);
          $hash->{VERZOEGRUNG} = 1;
          return 1
      }
  }
  if ( $hash->{VERZOEGRUNG} ) {
    Log3( $hash, 3, "[$name] delay of switching $hash->{DEVICE} stopped." );
  }
  delete $hash->{VERZOEGRUNG};
  delete $hash->{VERZOEGRUNG_IDX} if defined $hash->{VERZOEGRUNG_IDX};
  return 0;
}

################################################################################
sub Switch_Device {
  my ($hash, $newParam, $tage)  = @_;

  my ($command, $condition, $tageAsHash) = q{};
  my $name  = $hash->{NAME};

  my $now = time;
  #modifier des Zieldevices auswaehlen
  my $setModifier = checkIfDeviceIsHeatingType($hash);
  $setModifier .= ' ' if length $setModifier;

  $attr{$name}{commandTemplate} =
     'set $NAME ' . $setModifier . '$EVENT' if !defined $attr{$name}{commandTemplate};

  $command = AttrVal($hash->{NAME}, 'commandTemplate', 'commandTemplate not found');
  $command = 'set $NAME $EVENT' if defined $hash->{WDT_EVENTMAP} && defined $hash->{WDT_EVENTMAP}{$newParam};
  $command = $hash->{COMMAND} if defined $hash->{COMMAND} && $hash->{COMMAND} ne '';
  
  
  my $activeTimer = 1;

  my $isHeating = $setModifier ? 1 : 0;
  my $aktParam  = ReadingsVal($hash->{DEVICE}, $setModifier, '');
     $aktParam  = sprintf("%.1f", $aktParam) if $isHeating && $aktParam =~ m{\A[0-9]{1,3}\z}ixms;

  my $disabled = AttrVal($hash->{NAME}, 'disable', 0);
  my $disabled_txt = $disabled ? '' : ' not';
  Log3( $hash, 4, "[$name] aktParam:$aktParam newParam:$newParam - is$disabled_txt disabled" );

  #Kommando ausführen
  if ($command && !$disabled && $activeTimer
    && $aktParam ne $newParam
    ) {
    if ( defined $hash->{WDT_EVENTMAP} && defined $hash->{WDT_EVENTMAP}{$newParam} ) {
      $newParam = $hash->{WDT_EVENTMAP}{$newParam};
    } else {
      $newParam =~ s{\\:}{|}gxms;
      $newParam =~ s{:}{ }gxms;
      $newParam =~ s{\|}{:}gxms;
    }

    my %specials = ( "%NAME" => $hash->{DEVICE}, "%EVENT" => $newParam );
    $command = EvalSpecials($command, %specials);

    Log3( $hash, 4, "[$name] command: '$command' executed with ".join(",", map { "$_=>$specials{$_}" } keys %specials) );
    my $ret  = AnalyzeCommandChain(undef, $command);
    Log3( $hash, 3, $ret ) if $ret;
  }
  return;
}

################################################################################
sub getDaysAsHash {
  my $hash = shift;
  my $tage = shift //return {};

my %days = map {$_ => 1} @{$tage};
  delete @days{7,8};

  return 'my $days={};map{$days->{$_}=1}('. join (q{,}, sort keys %days ) .')';
}

################################################################################
sub checkWDTCondition {
  my $hash = shift;
  my $tage = shift // return 0;
  my $overrulewday = shift;

  my $name = $hash->{NAME};
  Log3( $hash, 4, "[$name] condition:$hash->{CONDITION} - Tage:" . join q{,}, @{$tage} );

  my $condition  = q{( };
  $condition .= (defined $hash->{CONDITION} && $hash->{CONDITION} ne '') ? $hash->{CONDITION} : 1 ;
  $condition .= ' && ' . getDaysAsCondition($tage, $overrulewday);
  $condition .= ')';

  return $condition;
}

################################################################################
sub getDaysAsCondition {
  my $tage         = shift;
  my $overrulewday = shift // return;

  my %days     = map {$_ => 1} @{$tage};

  my $we       = $days{7}; delete $days{7};  # $we
  my $notWe    = $days{8}; delete $days{8};  #!$we

  my $tageExp  = '(defined $days->{$wday}';
     $tageExp .= ' && !$we' if $overrulewday;
     $tageExp .= ' ||  $we' if defined $we;
     $tageExp .= ' || !$we' if defined $notWe;
     $tageExp .= ')';

  return $tageExp;
}

################################################################################
sub Attr {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  $attrVal = 0 if !defined $attrVal;

  my $hash = $defs{$name};
  if ( $attrName eq 'WDT_eventMap' ) {
    if($cmd eq 'set') {
      my @ret = split m{[: \r\n]}x, $attrVal;
      return "WDT_eventMap: Odd number of elements" if int(@ret) % 2;
      my %ret = @ret;
      for (keys %ret) {
        $ret{$_} =~ s{\+}{ }gxms;
      }
      $hash->{WDT_EVENTMAP} = \%ret;
    } else {
      delete $hash->{WDT_EVENTMAP};
    }
    $attr{$name}{$attrName} = $attrVal;
    return if (!$init_done);
    return WDT_Start($hash);
  }
  return if !$init_done;
  if( $attrName eq 'disable' ) {
    _DeleteTimer($hash);
    ###RemoveInternalTimer($fnHash);
    readingsSingleUpdate ($hash, 'disabled',  $attrVal, 1);
    $attr{$name}{$attrName} = $attrVal;
    return RemoveInternalTimer($hash,\&WeekdayTimer_SetTimerOfDay) if $attrVal;
    return WDT_Start($hash);
    #return WeekdayTimer_SetTimerOfDay( { HASH => $hash} ) if !$attrVal;
  }
  if ( $attrName eq 'weekprofile' ) {
    $attr{$name}{$attrName} = $attrVal;
    #return WDT_Start($hash);
  } 
  if ( $attrName eq 'switchInThePast' ) {
    $attr{$name}{$attrName} = $attrVal;
    return WDT_Start($hash);
  }
  if ( $attrName eq 'delayedExecutionCond' ) {
    my %specials = (
         '$WEEKDAYTIMER'     => $hash->{NAME},
         '$NAME'             => $hash->{DEVICE},
         '$EVENT'            => '1',
         '$TIME'             => '08:08',
    );
    my $err = perlSyntaxCheck( $attrVal, %specials );
    return $err if ( $err );
    $attr{$name}{$attrName} = $attrVal;
  }
  if ($attrName eq 'WDT_sendDelay' ) {
    if ($cmd eq 'set' && $init_done ) {
      return "WDT_sendDelay is in seconds, so only numbers are allowed" if !looks_like_number($attrVal);
      return "WDT_sendDelay is limited to 300 seconds" if $attrVal > 300;
    }
    $attr{$name}{$attrName} = $attrVal;
    return WDT_Start($hash);
  }

  return;
}


################################################################################
sub WeekdayTimer_SetParm {
  my $name = shift // return;
  my $hash = $defs{$name} // return qq(No Device named $name found!);;
  _DeleteTimer($hash);
  return _SetTimer($hash);
}

################################################################################
sub WeekdayTimer_SetAllParms {
  my $group = shift // q{all}; 
  my @wdtNames = $group eq 'all' ? devspec2array('TYPE=WeekdayTimer:FILTER=disable!=1')
                                 : devspec2array("TYPE=WeekdayTimer:FILTER=WDT_Group=$group:FILTER=disable!=1");

  for my $wdName ( @wdtNames ) {
    WeekdayTimer_SetParm($wdName);
  }
  Log3( undef,  3, "WeekdayTimer_SetAllParms() done on: ".join q{ }, @wdtNames );
  return;
}

################################################################################
sub updateWeekprofileReading {
  my ($hash,$wp_name,$wp_topic,$wp_profile) = @_;
  my $name = $hash->{NAME};
  if (!defined $defs{$wp_name} || InternalVal($wp_name,'TYPE','false') ne 'weekprofile')  {
    Log3( $hash, 3, "[$name] weekprofile $wp_name not accepted, device seems not to exist or not to be of TYPE weekprofile" );
    return;
  }
  if ($hash->{DEF} !~ m{weekprofile:$wp_name\b}xms) {
    Log3( $hash, 3, "[$name] weekprofile $wp_name not accepted, device is not correctly listed as weekprofile in the WeekdayTimer definition" );
    return;
  }
  my @t     = split m{\s+}xms, ReadingsVal( $name, 'weekprofiles', '');
  my @newt  = ( qq($wp_name:$wp_topic:$wp_profile) );
  push @newt, grep { $_ !~ m{\A$wp_name\b}xms } @t;
  readingsSingleUpdate( $hash, 'weekprofiles', join (q{ }, @newt), 1 );
  return 1;
}

################################################################################
sub getWeekprofileReadingTriplett {
  my $hash       = shift;
  my $wp_name    = shift // return;
  my $wp_profile = shift // q{default};
  my $wp_topic   = q{default};

  my $name = $hash->{NAME};
  if (!defined $defs{$wp_name} || InternalVal($wp_name,'TYPE','false') ne 'weekprofile')  {
    Log3( $hash, 3, "[$name] weekprofile $wp_name not accepted, device seems not to exist or not to be of TYPE weekprofile" );
    return;
  }
  my $newtriplett = qq($wp_name:$wp_topic:$wp_profile);
  my $actual_wp_reading = ReadingsVal($name, 'weekprofiles', 0);
  if (!$actual_wp_reading) {
    readingsSingleUpdate ($hash, 'weekprofiles', $newtriplett, 0);
    $actual_wp_reading = $newtriplett;
  }
  my @t = split m{\s+}xms, $actual_wp_reading;
  for my $triplett (@t){
    return $triplett if $triplett =~ m{$wp_name\b}xms;
  }
  return;
}
################################################################################
1;

__END__

=pod
=encoding utf8
=item helper
=item summary    sends parameter to devices at defined times
=item summary_DE sendet Parameter an Devices zu einer Liste mit festen Zeiten
=begin html

<a id="WeekdayTimer"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>WeekdayTimer</h3>
<ul>
  <br>
  <a id="weekdayTimer-define"></a>
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
      de,en,fr,nl are possible. The parameter is optional.
    </ul>
    <p>
    <ul><b>weekdays</b><br>
      Specifies the days for all timer in the <b>WeekdayTimer</b>.
      The parameter is optional. For details see the weekdays part in profile.
    </ul>
    <p>
    <ul><b>profile</b><br>
      Define the weekly profile. All timings are separated by space. A switchingtime can be defined
      in two ways: the classic definition or via the use of a <b><a href="#weekprofile">weekprofile</a></b> (see below, only temperature profiles can be set). Example for a classic definition: <br><br>
      
      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;</b></ul><br>

      <u>weekdays:</u> <b>optional</b>, if not set every day of the week is used.</><br>
      NOTE: It's highly recommended to not set weekdays if you just want your WeekdayTimer to switch all week long. Especially notations like "78" or "$we!$we" <b>are contraproductive!</b><br>
      <br>
        <b>Otherwise</b> you can define a day with its number or its shortname.<br>
        <ul>
        <li>0,su  sunday</li>
        <li>1,mo  monday</li>
        <li>2,tu  tuesday</li>
        <li>3,we  wednesday</li>
        <li>4 ...</li>
        <li>7,$we  weekend  ($we)</li>
        <li>8,!$we weekday  (!$we)</li>
        </ul><br>
         It is possible to define $we or !$we in daylist to easily allow weekend an holiday. $we !$we are coded as 7 8, when using a numeric daylist. <br>
         Note: $we will use general IsWe() function to determine $we handling for today and tomorrow. The complete daylist for all other days will reflect the results of holiday devices listed as holiday2we devices in global, including weekEnd and noWeekEnd (see global - holiday2we attribute).<br><br>
      <u>time:</u>define the time to switch, format: HH:MM:[SS](HH in 24 hour format) or a Perlfunction like {sunrise_abs()}. Within the {} you can use the variable $date(epoch) to get the exact switchingtimes of the week. Example: {sunrise_abs_dat($date)}<br><br>
      <u>parameter:</u>the parameter to be set, using any text value like <b>on</b>, <b>off</b>, <b>dim30%</b>, <b>eco</b> or <b>comfort</b> - whatever your device understands.<br>
      NOTE: Use ":" to replace blanks in parameter and escape ":" in case you need it. So e.g. <code>on-till:06\:00</code> will be a valid parameter.<br><br>
      NOTE: When using $we in combination with regular weekdays (from 0-6), switchingtimes may be combined. If you want $we to be given priority when true, add a "|w" at the end of the respective profile:<br><br>
      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;|w</b></ul><br>
      </ul>
      <ul>Example for a <b><a href="#weekprofile">weekprofile</a></b> definition:</ul><br>
      <ul><ul><b>weekprofile:&lt;weekprofile-device-name&gt;</b></ul></ul><br>  
      <ul>Example for a <b>weekprofile</b> definition using sunday profile for all $we days, giving exclusive priority to the $we profile:</ul><br>
      <ul><ul><b>weekprofile:&lt;weekprofile-device-name&gt;:true</b></ul><br>  
      NOTE: only temperature profiles can be set via weekprofile, but they have the advantage of possible updates from weekprofile side (including the use of so-called topics) or via the command: 
      <code>set &lt;device&gt; weekprofile &lt;weekprofile-device:topic:profile&gt;</code><br><br>  
    </ul>
    <p>
    <ul><b>command</b><br>
      If no condition is set, all the rest is interpreted as a command. Perl-code is setting up
      by the well-known Block with {}.<br>
      Note: if a command is defined only this command is executed. In case of executing
      a "set desired-temp" command, you must define the hole commandpart explicitly by yourself.<br>
      

  <!----------------------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
      The following parameter are replaced:<br>
        <ol>
          <li>$NAME  => the device to switch</li>
          <li>$EVENT => the new temperature</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      if a condition is defined you must declare this with () and a valid perl-code.<br>
      The return value must be boolean.<br>
      The parameters $NAME and $EVENT will be interpreted.
    </ul>
    <p>
    <b>Examples:</b>
    <ul>
        <code>define shutter WeekdayTimer bath 12345|05:20|up  12345|20:30|down</code><br>
        Mo-Fr are setting the shutter at 05:20 to <b>up</b>, and at 20:30 <b>down</b>.<p>

        <code>define heatingBath WeekdayTimer bath 07:00|16 Mo,Tu,Th-Fr|16:00|18.5 20:00|eco
          {fhem("set dummy on"); fhem("set $NAME desired-temp $EVENT");}</code><br>
        At the given times and weekdays only(!) the command will be executed.<p>

        <code>define dimmer WeekdayTimer livingRoom Sa-Su,We|07:00|dim30% Sa-Su,We|21:00|dim90% (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        The dimmer is only set to dimXX% if the dummy variable WeAreThere is "yes"(not a real live example).<p>

        If you want to have set all WeekdayTimer their current value (e.g. after a temperature lowering phase holidays)
        you can call the function <b>WeekdayTimer_SetParm("WD-device")</b> or <b>WeekdayTimer_SetAllParms()</b>.<br>
        To limit the affected WeekdayTimer devices to a subset of all of your WeekdayTimers, use the WDT_Group attribute and <b>WeekdayTimer_SetAllParms("<group name>")</b>.<br> This offers the same functionality than <code>set wd WDT_Params WDT_Group</code>
        This call can be automatically coupled to a dummy by a notify:<br>
        <code>define dummyNotify notify Dummy:. * {WeekdayTimer_SetAllParms()}</code>
        <br><p>
        Some definitions without comment:
        <code>
        <pre>
        define wd    Weekdaytimer  device de         7|23:35|25        34|23:30|22 23:30|16 23:15|22     8|23:45|16
        define wd    Weekdaytimer  device de         fr,$we|23:35|25   34|23:30|22 23:30|16 23:15|22    12|23:45|16
        define wd    Weekdaytimer  device de         20:35|25          34|14:30|22 21:30|16 21:15|22    12|23:00|16

        define wd    Weekdaytimer  device de         mo-so, $we|{sunrise_abs_dat($date)}|on       mo-so, $we|{sunset_abs_dat($date)}|off
        define wd    Weekdaytimer  device de         mo-so,!$we|{sunrise_abs_dat($date)}|aus      mo-so,!$we|{sunset_abs_dat($date)}|aus

        define wd    Weekdaytimer  device de         {sunrise_abs_dat($date)}|19           {sunset_abs_dat($date)}|21
        define wd    Weekdaytimer  device de         22:35|25  23:00|16
        </code></pre>
        The daylist can be given globaly for the whole Weekdaytimer:<p>
        <code><pre>
        define wd    Weekdaytimer device de  !$we     09:00|19  (function("Ein"))
        define wd    Weekdaytimer device de   $we     09:00|19  (function("Ein"))
        define wd    Weekdaytimer device de           09:00|19  (function("exit"))
        define wd    Weekdaytimer device de   57      09:00|19  (function("exit"))
        define wd    Weekdaytimer device de  fr,$we   09:00|19  (function("exit"))
        </code></pre>
    </ul>
  </ul>

  <a id="WeekdayTimer-set"></a>
  <b>Set</b>
    <ul><br>
    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    <b>disable</b>               # disables the WeekdayTimer
    <b>enable</b>                # enables  the WeekdayTimer, switching times will be recaltulated. 
    <b>WDT_Params [one of: single, WDT_Group or all]</b>
    <b>weekprofile &lt;weekprofile-device:topic:profile&gt;</b></pre>
    <br>
    You may especially use <b>enable</b> in case one of your global holiday2we devices has changed since 5 seconds past midnight.
    <br><br>
    <b>Examples</b>:
    <ul>
      <code>set wd disable</code><br>
      <code>set wd enable</code><br>
      <code>set wd WDT_Params WDT_Group</code><br>
      <code>set wd weekprofile myWeekprofiles:holiday:livingrooms</code><br>
    </ul>
    <ul><li>
    <a id="WeekdayTimer-set-WDT_Params"></a>
    The <i>WDT_Params</i> function can be used to reapply the current switching value to the device, all WDT devices with identical WDT_Group attribute or all WeekdayTimer devices; delay conditions will be obeyed, for non-heating type devices, switchInThePast has to be set.
    </li>
    </ul>
    <ul>
    <br>
    NOTES on <b>weekprofile</b> usage:<br><br>
    <ul>
      <li><a id="WeekdayTimer-set-weekpofile"></a>
      The <i>weekprofile</i> set will only be successfull, if the <i>&lt;weekprofile-device&gt;</i> is part of the definition of the WeekdayTimer, the mentionned device exists and it provides data for the <i>&lt;topic:profile&gt;</i> combination. If you haven't activated the "topic" feature in the weekprofile device, use "default" as topic.</li> 
      <li>Once you set a weekprofile for any weekprofile device, you'll find the values set in the reading named "weekprofiles"; for each weekprofile device there's an entry with the set triplett.</li>
      <li>As WeekdayTimer will recalculate the switching times for each day a few seconds after midnight, 10 minutes pas midnight will be used as a first switching time for weekpofile usage.</li>
      <li>This set is the way the weekprofile module uses to update a WeekdayTimer device. So aforementioned WeekdayTimer command<br>
      <code>set wd weekprofile myWeekprofiles:holiday:livingrooms</code><br>
      is aequivalent to weekprofile command<br>
      <code>set myWeekprofiles send_to_device holiday:livingrooms wd</code><br>
      </li>
      <li>Although it's possible to use more than one weekprofile device in a WeekdayTimer, this is explicitly not recommended unless you are exactly knowing what you are doing.</li>
      <li>Note: The userattr <i>weekprofile</i> will automatically be added to the list and can't be removed. The attribute itself is intended to be set to the corresponding profile name (no topic name, just the second part behind the ":") in your weekprofile device allowing easy change using the topic feature.</li>
      </ul>
    </ul>
  </ul>
  <a id="WeekdayTimer-get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a id="WeekdayTimer-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a id="WeekdayTimer-attr-delayedExecutionCond"></a>
    delayedExecutionCond <br>
    defines a delay Function. When returning true, the switching of the device is delayed until the function returns a false value. The behavior is the same as if one of the WDT_delayedExecutionDevices returns "open".

    <br><br>
    <b>Example:</b>
    <pre>
    attr wd delayedExecutionCond isDelayed("$WEEKDAYTIMER","$TIME","$NAME","$EVENT")
    </pre>
    the parameter $WEEKDAYTIMER(timer name) $TIME $NAME(device name) $EVENT are replaced at runtime by the correct value.
    <br><br>Note: If the function returns "1" or "true", state of the WeekdayTimer will be "open window", other return values will be used as values for state.<br>
    <b>Example of a function:</b>
    <pre>
    sub isDelayed($$$$) {
       my($wdt, $tim, $nam, $event ) = @_;

       my $theSunIsStillshining = ...

       return ($tim eq "16:30" && $theSunIsStillshining) ;
    }
    </pre>
    </li>
    <li><a id="WeekdayTimer-attr-WDT_delayedExecutionDevices"></a>
    WDT_delayedExecutionDevices<br>
    May contain a space separated list of devices (atm. only window sensors are supported). When one of them states to be <b>open</b> (typical reading names and values are known) the aktual switch is delayed, until either the window is closed or the next switching time is reached (this one will also be delayed). This is especially intended to prevent heating commands while windows are opened.</li><br>
    <br>
    <li><a id="WeekdayTimer-attr-WDT_Group"></a>
    WDT_Group<br>
    Used to generate groups of WeekdayTimer devices to be switched together in case one of them is set to WDT_Params with the WDT_Group modifier, e.g. <code>set wd WDT_Params WDT_Group</code>.<br>This originally was intended to allow Heating_Control devices to be migrated to WeekdayTimer by offering an alternative to the former Heating_Control_SetAllTemps() functionality.</li><br>

    <br>

    <li><a id="WeekdayTimer-attr-WDT_sendDelay"></a>
    WDT_sendDelay<br>
    This will add some seconds to each of the switching timers to avoid collissions in RF traffic, especially, when <i>weekprofile</i> option is used and e.g. a topic change may affect not only a single target device but many or a single profile is used for many devices. <br>
    Make sure, the effective switch time for day's last switch is still taking place before midnight, otherwise it may not be executed at all!
    </li>

    <br>
    <li><a id="WeekdayTimer-attr-WDT_eventMap"></a>
    WDT_eventMap<br>
    This will translate parameters from the profile to a different command. Syntax is (space separated): "&ltparameter&gt:&ltnew command&gt", spaces have to be replaced by "+". <br>
    Example:<br>
    <code>attr wd WDT_eventMap 22.0:dtp20+01 12.0:dtp20+02 18.0:dtp20+03</code><br>
    Notes:<br>
    <ul>
    <li>New command will be addressed directly to the device, especially commandTemplate content will be ignored. So e.g. if commandTemplate is set to <code>set $NAME desired-temp $EVENT</code>, parameter 22.0 will lead to <code>set $NAME dtp20 01</code>.</li>
    <li>When using Perl command syntax for <i>command</i>, $EVENT will be replaced by the new command.</li>
    </ul>
    </li>
    <li><a id="WeekdayTimer-attr-switchInThePast"></a>
    switchInThePast<br>
    defines that the depending device will be switched in the past in definition and startup phase when the device is not recognized as a heating.
    Heatings are always switched in the past.
    </li>

    <li><a href="#disable">disable</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
  <br>
  </ul>
</ul>

=end html

=for :application/json;q=META.json 98_WeekdayTimer.pm
{
   "abstract" : "sends parameter to devices at defined times",
   "x_lang" : {
      "de" : {
         "abstract" : "sendet Parameter an Devices zu einer Liste mit festen Zeiten"
      }
   },
   "keywords" : [
      "heating",
      "Heizung",
      "timer",
      "weekprofile"
   ],
   "prereqs" : {
      "runtime" : {
         "requires" : {
            "Data::Dumper" : "0",
            "Time::Local" : "0",
            "strict" : "0",
            "warnings" : "0"
         }
      }
   }
}
=end :application/json;q=META.json

=cut
