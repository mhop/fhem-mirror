# $Id$
###########################################################################
#
# FHEM RHASSPY modul  (https://github.com/rhasspy)
#
# Originally written 2018 by Tobias Wiedenmann (Thyraz)
# as FHEM Snips.ai module (thanks to Matthias Kleine)
#
# Adapted for RHASSPY 2020/2021 by Beta-User and drhirn
#
# Thanks to Beta-User, rudolfkoenig, JensS, cb2sela and all the others
# who did a great job getting this to work!
#
# This file is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# 
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###########################################################################

package RHASSPY; ##no critic qw(Package)
use strict;
use warnings;
use Carp qw(carp);
use GPUtils qw(:all);
use JSON;
use Encode;
use HttpUtils;
use utf8;
use List::Util 1.45 qw(max min uniq);
use Data::Dumper;
use Scalar::Util qw(weaken);

sub ::RHASSPY_Initialize { goto &Initialize }

#Beta-User: no GefFn defined...?
my %gets = (
    version => q{},
    status  => q{}
);

my %sets = (
    speak        => [],
    play         => [],
    customSlot   => [],
    textCommand  => [],
    trainRhasspy => [qw(noArg)],
    fetchSiteIds => [qw(noArg)],
    update       => [qw(devicemap devicemap_only slots slots_no_training language all)],
    volume       => []
);

my $languagevars = {
  'units' => {
      'unitHours' => {
          0    => 'hours',
          1    => 'one hour'
      },
      'unitMinutes' => {
          0    => 'minutes',
          1    => 'one minute'
      },
      'unitSeconds' => {
          0    => 'seconds',
          0    => 'seconds',
          1    => 'one second'
      }
   },
  'responses' => { 
    'DefaultError' => "Sorry but something seems not to work as expected",
    'NoValidData' => "Sorry but the received data is not sufficient to derive any action",
    'NoDeviceFound' => "Sorry but I could not find a matching device",
    'NoMappingFound' => "Sorry but I could not find a suitable mapping",
    'NoNewValDerived' => "Sorry but I could not calculate a new value to set",
    'NoActiveMediaDevice' => "Sorry no active playback device",
    'NoMediaChannelFound' => "Sorry but requested channel seems not to exist",
    'DefaultConfirmation' => "OK",
    'DefaultConfirmationTimeout' => "Sorry too late to confirm",
    'DefaultCancelConfirmation' => "Thanks aborted",
    'SilentCancelConfirmation' => "",
    'DefaultConfirmationReceived' => "ok will do it",
    'DefaultConfirmationNoOutstanding' => "no command is awaiting confirmation",
    'DefaultConfirmationRequest' => 'please confirm switching $device $wanted',
    'RequestChoiceDevice' => 'there are several possible devices, choose between $first_items and $last_item',
    'RequestChoiceRoom' => 'more than one possible device, please choose one of the following rooms $first_items and $last_item',
    'DefaultChoiceNoOutstanding' => "no choice expected",
    'timerSet'   => {
        '0' => '$label in room $room has been set to $seconds seconds',
        '1' => '$label in room $room has been set to $minutes minutes $seconds',
        '2' => '$label in room $room has been set to $minutes minutes',
        '3' => '$label in room $room has been set to $hours hours $minutetext',
        '4' => '$label in room $room has been set to $hour o clock $minutes',
        '5' => '$label in room $room has been set to tomorrow $hour o clock $minutes'
    },
    'timerEnd'   => {
        '0' => '$label expired',
        '1' =>  '$label in room $room expired'
    },
    'timerCancellation' => '$label for $room deleted',
    'timeRequest' => 'it is $hour o clock $min minutes',
    'weekdayRequest' => 'today it is $weekDay',
    'duration_not_understood'   => "Sorry I could not understand the desired duration",
    'reSpeak_failed'   => 'i am sorry i can not remember',
    'Change' => {
      'humidity'     => 'air humidity in $location is $value percent',
      'battery'      => {
        '0' => 'battery level in $location is $value',
        '1' => 'battery level in $location is $value percent'
      },
      'brightness'   => '$device was set to $value',
      'setTarget'    => '$device is set to $value',
      'soilMoisture' => 'soil moisture in $location is $value percent',
      'temperature'  => {
        '0' => 'temperature in $location is $value',
        '1' => 'temperature in $location is $value degrees',
      },
      'desired-temp' => 'target temperature for $location is set to $value degrees',
      'volume'       => '$device set to $value',
      'waterLevel'   => 'water level in $location is $value percent',
      'knownType'    => '$mappingType in $location is $value percent',
      'unknownType'  => 'value in $location is $value percent'
    }
  },
  'stateResponses' => {
     'inOperation' => {
       '0' => '$deviceName is ready',
       '1' => '$deviceName is still running'
     },
     'inOut'       => {
       '0' => '$deviceName is out',
       '1' => '$deviceName is in'
     },
     'onOff'       => {
       '0' => '$deviceName is off',
       '1' => '$deviceName is on'
     },
     'openClose'   => {
       '0' => '$deviceName is open',
       '1' => '$deviceName is closed'
     }
  }
};

my $internal_mappings = {
  'Change' => {
    'lightUp' => { 
      'Type' => 'brightness',
      'up'  => '1'
    },
    'lightDown' => { 
      'Type' => 'brightness',
      'up'  => '0'
    },
    'tempUp' => { 
      'Type' => 'temperature',
      'up'  => '1'
    },
    'tempDown' => { 
      'Type' => 'temperature',
      'up'  => '0'
    },
    'volUp' => { 
      'Type' => 'volume',
      'up'  => '1'
    },
    'volDown' => { 
      'Type' => 'volume',
      'up'  => '0'
    },
    'setUp' => { 
      'Type' => 'setTarget',
      'up'  => '1'
    },
    'setDown' => { 
      'Type' => 'setTarget',
      'up'  => '0'
    }
  },
  'regex' => {
    'upward' => '(higher|brighter|louder|rise|warmer)',
    'setTarget' => '(brightness|volume|target.volume)'
  },
  'stateResponseType' => {
    'on'     => 'onOff',
    'off'    => 'onOff',
    'open'   => 'openClose',
    'closed' => 'openClose',
    'in'     => 'inOut',
    'out'    => 'inOut',
    'ready'  => 'inOperation',
    'acting' => 'inOperation'
  }
};

my $de_mappings = {
  'on'      => 'an',
  'percent' => 'Prozent',
  'stateResponseType' => {
    'an'            => 'onOff',
    'aus'           => 'onOff',
    'auf'           => 'openClose',
    'zu'            => 'openClose',
    'eingefahren'   => 'inOut',
    'ausgefahren'   => 'inOut',
    'läuft'         => 'inOperation',
    'fertig'        => 'inOperation'
  },
  'ToEn' => {
    'Temperatur'       => 'temperature',
    'Luftfeuchtigkeit' => 'humidity',
    'Batterie'         => 'battery',
    'Wasserstand'      => 'waterLevel',
    'Bodenfeuchte'     => 'soilMoisture',
    'Helligkeit'       => 'brightness',
    'Sollwert'         => 'setTarget',
    'Lautstärke'       => 'volume',
    'kälter' => 'tempDown',
    'wärmer' => 'tempUp',
    'dunkler' => 'lightDown',
    'heller' => 'lightUp',
    'lauter' => 'volUp',
    'leiser' => 'volDown',

  },
  'regex' => {
    'upward' => '(höher|heller|lauter|wärmer)',
    'setTarget' => '(Helligkeit|Lautstärke|Sollwert)'
  }

};

BEGIN {

  GP_Import(qw(
    addToAttrList
    delFromDevAttrList
    delFromAttrList
    readingsSingleUpdate
    readingsBeginUpdate
    readingsBulkUpdate
    readingsEndUpdate
    readingsDelete
    Log3
    defs
    attr
    cmds
    L
    DAYSECONDS
    HOURSECONDS
    MINUTESECONDS
    init_done
    InternalTimer
    RemoveInternalTimer
    AssignIoPort
    CommandAttr
    CommandDeleteAttr
    IOWrite
    readingFnAttributes
    IsDisabled
    AttrVal
    InternalVal
    ReadingsVal
    ReadingsNum
    devspec2array
    gettimeofday
    toJSON
    setVolume
    AnalyzeCommandChain
    AnalyzeCommand
    CommandDefMod
    CommandDelete
    EvalSpecials
    AnalyzePerlCommand
    perlSyntaxCheck
    parseParams
    ResolveDateWildcards
    HttpUtils_NonblockingGet
    round
    strftime
    FmtDateTime
    makeReadingName
    FileRead
    trim
    looks_like_number
    getAllSets
  ))

};

# MQTT Topics die das Modul automatisch abonniert
my @topics = qw(
    hermes/intent/+
    hermes/dialogueManager/sessionStarted
    hermes/dialogueManager/sessionEnded
);

sub Initialize {
    my $hash = shift // return;

    # Consumer
    $hash->{DefFn}       = \&Define;
    $hash->{UndefFn}     = \&Undefine;
    $hash->{DeleteFn}    = \&Delete;
    $hash->{RenameFn}    = \&Rename;
    $hash->{SetFn}       = \&Set;
    $hash->{AttrFn}      = \&Attr;
    $hash->{AttrList}    = "IODev rhasspyIntents:textField-long rhasspyShortcuts:textField-long rhasspyTweaks:textField-long response:textField-long forceNEXT:0,1 disable:0,1 disabledForIntervals languageFile " . $readingFnAttributes;
    $hash->{Match}       = q{.*};
    $hash->{ParseFn}     = \&Parse;
    $hash->{parseParams} = 1;

    return;
}

# Device anlegen
sub Define {
    my $hash = shift;
    my $anon = shift;
    my $h    = shift;
    #parseParams: my ( $hash, $a, $h ) = @_;

    my $name = shift @{$anon};
    my $type = shift @{$anon};
    my $Rhasspy  = $h->{baseUrl} // shift @{$anon} // q{http://127.0.0.1:12101};
    my $defaultRoom = $h->{defaultRoom} // shift @{$anon} // q{default}; 

    my @unknown;
    for (keys %{$h}) {
        push @unknown, $_ if $_ !~ m{\A(baseUrl|defaultRoom|language|devspec|fhemId|prefix|encoding|useGenericAttrs)\z}xm;
    }
    my $err = join q{, }, @unknown;
    return "unknown key(s) in DEF: $err" if @unknown && $init_done;
    Log3( $hash, 1, "[$name] unknown key(s) in DEF: $err") if @unknown;

    $hash->{defaultRoom} = $defaultRoom;
    my $language = $h->{language} // shift @{$anon} // lc AttrVal('global','language','en');
    $hash->{MODULE_VERSION} = '0.4.15';
    $hash->{baseUrl} = $Rhasspy;
    #$hash->{helper}{defaultRoom} = $defaultRoom;
    initialize_Language($hash, $language) if !defined $hash->{LANGUAGE} || $hash->{LANGUAGE} ne $language;
    $hash->{LANGUAGE} = $language;
    $hash->{devspec} = $h->{devspec} // q{room=Rhasspy};
    $hash->{fhemId} = $h->{fhemId} // q{fhem};
    #$hash->{baseId} = $h->{baseId} // q{default};
    initialize_prefix($hash, $h->{prefix}) if !defined $hash->{prefix} || defined $h->{prefix} && $hash->{prefix} ne $h->{prefix};
    $hash->{prefix} = $h->{prefix} // q{rhasspy};
    $hash->{encoding} = $h->{encoding} // q{utf8};
    $hash->{useGenericAttrs} = $h->{useGenericAttrs} // 1;
    $hash->{'.asyncQueue'} = [];
    #Beta-User: Für's Ändern von defaultRoom oder prefix vielleicht (!?!) hilfreich: https://forum.fhem.de/index.php/topic,119150.msg1135838.html#msg1135838 (Rudi zu resolveAttrRename) 

    if ($hash->{useGenericAttrs}) {
        addToAttrList(q{genericDeviceType});
        #addToAttrList(q{homebridgeMapping});
    }

    return $init_done ? firstInit($hash) : InternalTimer(time+1, \&firstInit, $hash );
}

sub firstInit {
    my $hash = shift // return;

    my $name = $hash->{NAME};

    # IO
    AssignIoPort($hash);
    my $IODev = AttrVal( $name, 'IODev', ReadingsVal( $name, 'IODev', InternalVal($name, 'IODev', undef )));

    return if !$init_done || !defined $IODev;
    RemoveInternalTimer($hash);

    IOWrite($hash, 'subscriptions', join q{ }, @topics) if InternalVal($IODev,'TYPE',undef) eq 'MQTT2_CLIENT';

    fetchSiteIds($hash) if !ReadingsVal( $name, 'siteIds', 0 );
    initialize_rhasspyTweaks($hash, AttrVal($name,'rhasspyTweaks', undef ));
    configure_DialogManager($hash);
    initialize_devicemap($hash);

    return;
}

sub initialize_Language {
    my $hash = shift // return;
    my $lang = shift // return;
    my $cfg  = shift // AttrVal($hash->{NAME},'languageFile',undef);

    my $cp = $hash->{encoding} // q{UTF-8};

    #default to english first
    $hash->{helper}->{lng} = $languagevars if !defined $hash->{helper}->{lng} || !$init_done;

    my ($ret, $content) = _readLanguageFromFile($hash, $cfg);
    return $ret if $ret;

    my $decoded;
    if ( !eval { $decoded  = decode_json(encode($cp,$content)) ; 1 } ) {
        Log3($hash->{NAME}, 1, "JSON decoding error in languagefile $cfg:  $@");
        return "languagefile $cfg seems not to contain valid JSON!";
    }
                                   
    my $slots = $decoded->{slots}; 

    if ( defined $decoded->{default} ) {
        $decoded = _combineHashes( $decoded->{default}, $decoded->{user} );
        Log3($hash->{NAME}, 4, "try to use user specific sentences and defaults in languagefile $cfg");
    }
    $hash->{helper}->{lng} = _combineHashes( $hash->{helper}->{lng}, $decoded);
    
    return if !$init_done;
    for my $key (keys %{$slots}) {
        updateSingleSlot($hash, $key, $slots->{$key});
    }

    return;
}

sub initialize_prefix {
    my $hash   = shift // return;
    my $prefix =  shift // q{rhasspy};
    my $old_prefix = $hash->{prefix}; #Beta-User: Marker, evtl. müssen wir uns was für Umbenennungen überlegen...
    
    return if defined $old_prefix && $prefix eq $old_prefix;
    # provide attributes "rhasspyName" etc. for all devices
    addToAttrList("${prefix}Name");
    addToAttrList("${prefix}Room");
    addToAttrList("${prefix}Mapping:textField-long");
    #addToAttrList("${prefix}Channels:textField-long");
    #addToAttrList("${prefix}Colors:textField-long");
    addToAttrList("${prefix}Group:textField");
    addToAttrList("${prefix}Specials:textField-long");
    
    return if !$init_done || !defined $old_prefix;
    my @devs = devspec2array("$hash->{devspec}");
    my @rhasspys = devspec2array("TYPE=RHASSPY:FILTER=prefix=$old_prefix");

    for my $detail (qw( Name Room Mapping Group Specials)) { 
        for my $device (@devs) {
            my $aval = AttrVal($device, "${old_prefix}$detail", undef);
            CommandAttr($hash, "$device ${prefix}$detail $aval") if $aval;
            CommandDeleteAttr($hash, "$device ${old_prefix}$detail") if @rhasspys < 2;
        }
        delFromAttrList("${old_prefix}$detail") if @rhasspys < 2;
    }

    return;
}


# Device löschen
sub Undefine {
    my $hash = shift // return;

    deleteAllRegisteredInternalTimer($hash);
    RemoveInternalTimer($hash);


    return;
}

sub Delete {
    my $hash = shift // return;
    #my $prefix = $hash->{prefix} // return;

    deleteAllRegisteredInternalTimer($hash);
    RemoveInternalTimer($hash);

# DELETE POD AFTER TESTS ARE COMPLETED
#Beta-User: Most likely removing attributes isn't a good idea; additionally: if, then attributes should be removed from global
=begin comment
    
    #Beta-User: globale Attribute löschen
    for (devspec2array("${prefix}Mapping=.+")) {
        delFromDevAttrList($_,"${prefix}Mapping:textField-long");
    }
    for (devspec2array("${prefix}Name=.+")) {
        delFromDevAttrList($_,"${prefix}Name");
    }
    for (devspec2array("${prefix}Room=.+")) {
        delFromDevAttrList($_,"${prefix}Room");
    }
    for (devspec2array("${prefix}Channels=.+")) {
        delFromDevAttrList($_,"${prefix}Channels");
    }
    for (devspec2array("${prefix}Colors=.+")) {
        delFromDevAttrList($_,"${prefix}Colors");
    }
    for (devspec2array("${prefix}Specials=.+")) {
        delFromDevAttrList($_,"${prefix}Specials");
    }
    for (devspec2array("${prefix}Group=.+")) {
        delFromDevAttrList($_,"${prefix}Group");
    }
=end comment
=cut
    return;
}

sub Rename {
    my $new_name = shift // return;
    my $old_name = shift // return;

    my $hash = $defs{$new_name} // return;
    return renameAllRegisteredInternalTimer($hash, $new_name, $old_name);
}

# Set Befehl aufgerufen
sub Set {
    my $hash    = shift;
    my $anon    = shift;
    my $h       = shift;
    #parseParams: my ( $hash, $a, $h ) = @_;
    my $name    = shift @{$anon};
    my $command = shift @{$anon} // q{};
    my @values  = @{$anon};
    return "Unknown argument $command, choose one of " 
    . join(q{ }, map {
        @{$sets{$_}} ? $_
                      .q{:}
                      .join q{,}, @{$sets{$_}} : $_} sort keys %sets)

    if !defined $sets{$command};

    Log3($name, 5, "set $command - value: " . join q{ }, @values);

    my $dispatch = {
        updateSlots  => \&updateSlots,
        trainRhasspy => \&trainRhasspy,
        fetchSiteIds => \&fetchSiteIds
    };
    
    return $dispatch->{$command}->($hash) if ref $dispatch->{$command} eq 'CODE';
    
    $values[0] = $h->{text} if ( $command eq 'speak' || $command eq 'textCommand' ) && defined $h->{text};
    
    if ( $command eq 'play' || $command eq 'volume' ) {
        $values[0] = $h->{siteId} if defined $h->{siteId};
        $values[1] = $h->{path}   if defined $h->{path};
        $values[1] = $h->{volume} if defined $h->{volume};
    }

    $dispatch = {
        speak       => \&sendSpeakCommand,
        textCommand => \&sendTextCommand,
        play        => \&setPlayWav,
        volume      => \&setVolume
    };

    return Log3($name, 3, "set $name $command requires at least one argument!") if !@values;

    my $params = join q{ }, @values; #error case: playWav => PERL WARNING: Use of uninitialized value within @values in join or string
    $params = $h if defined $h->{text} || defined $h->{path} || defined $h->{volume};
    return $dispatch->{$command}->($hash, $params) if ref $dispatch->{$command} eq 'CODE';

    if ($command eq 'update') {
        if ($values[0] eq 'language') {
            return initialize_Language($hash, $hash->{LANGUAGE});
        }
        if ($values[0] eq 'devicemap') {
            initialize_devicemap($hash);
            $hash->{'.needTraining'} = 1;
            return updateSlots($hash);
        }
        if ($values[0] eq 'devicemap_only') {
            return initialize_devicemap($hash);
        }
        if ($values[0] eq 'slots') {
            $hash->{'.needTraining'} = 1;
            return updateSlots($hash);
        }
        if ($values[0] eq 'slots_no_training') {
            initialize_devicemap($hash);
            return updateSlots($hash);
        }
        if ($values[0] eq 'all') {
            initialize_Language($hash, $hash->{LANGUAGE});
            initialize_devicemap($hash);
            $hash->{'.needTraining'} = 1;
            return updateSlots($hash);
        }
    }

    if ($command eq 'customSlot') {
        my $slotname = $h->{slotname}  // shift @values;
        my $slotdata = $h->{slotdata}  // shift @values;
        my $overwr   = $h->{overwrite} // shift @values;
        my $training = $h->{training}  // shift @values;
        return updateSingleSlot($hash, $slotname, $slotdata, $overwr, $training);
    }
    return;
}

# Attribute setzen / löschen
sub Attr {
    my $command = shift;
    my $name = shift;
    my $attribute = shift // return;
    my $value = shift;
    my $hash = $defs{$name} // return;

    # IODev Attribut gesetzt
    if ($attribute eq 'IODev') {
        return;
    }

    if ( $attribute eq 'rhasspyShortcuts' ) {
        for ( keys %{ $hash->{helper}{shortcuts} } ) {
            delete $hash->{helper}{shortcuts}{$_};
        }
        if ($command eq 'set') {
            return init_shortcuts($hash, $value); 
        } 
    }

    if ( $attribute eq 'rhasspyIntents' ) {
        for ( keys %{ $hash->{helper}{custom} } ) {
            delete $hash->{helper}{custom}{$_};
        }
        if ($command eq 'set') {
            return init_custom_intents($hash, $value); 
        } 
    }

    if ( $attribute eq 'rhasspyTweaks' ) {
        for ( keys %{ $hash->{helper}{tweaks} } ) {
            delete $hash->{helper}{tweaks}{$_};
        }
        if ($command eq 'set') {
            return initialize_rhasspyTweaks($hash, $value); 
        } 
    }

    if ( $attribute eq 'languageFile' ) {
        if ($command ne 'set') {
            delete $hash->{CONFIGFILE};
            delete $attr{$name}{languageFile}; 
            delete $hash->{helper}{lng};
            $value = undef;
        }
        return initialize_Language($hash, $hash->{LANGUAGE}, $value); 
    }

    return;
}

sub init_shortcuts {
    my $hash    = shift // return;
    my $attrVal = shift // return;

    my ($intent, $perlcommand, $device, $err );
    for my $line (split m{\n}x, $attrVal) {
        #old syntax
        if ($line !~ m{\A[\s]*i=}x) {
            ($intent, $perlcommand) = split m{=}x, $line, 2;
            $err = perlSyntaxCheck( $perlcommand );
            return "$err in $line" if $err && $init_done;
            $hash->{helper}{shortcuts}{$intent}{perl} = $perlcommand;
            $hash->{helper}{shortcuts}{$intent}{NAME} = $hash->{NAME};
            next;
        }
        next if !length $line;
        my($unnamed, $named) = parseParams($line); 
        #return "unnamed parameters are not supported! (line: $line)" if ($unnamed) > 1 && $init_done;
        $intent = $named->{i};
        if (defined($named->{f})) {
            $hash->{helper}{shortcuts}{$intent}{fhem} = $named->{f};
        } elsif (defined($named->{p})) {
            $err = perlSyntaxCheck( $perlcommand );
            return "$err in $line" if $err && $init_done;
            $hash->{helper}{shortcuts}{$intent}{perl} = $named->{p};
        } elsif ($init_done && !defined $named->{r}) {
            return "Either a fhem or perl command or a response have to be provided!";
        }
        $hash->{helper}{shortcuts}{$intent}{NAME} = $named->{d} if defined $named->{d};
        $hash->{helper}{shortcuts}{$intent}{response} = $named->{r} if defined $named->{r};
        if ( defined $named->{c} ) {
            $hash->{helper}{shortcuts}{$intent}{conf_req} = !looks_like_number($named->{c}) ? $named->{c} : 'default';
            if (defined $named->{ct}) {
                $hash->{helper}{shortcuts}{$intent}{conf_timeout} = looks_like_number($named->{ct}) ? $named->{ct} : _getDialogueTimeout($hash, 'confirm');
            } else {
                $hash->{helper}{shortcuts}{$intent}{conf_timeout} = looks_like_number($named->{c}) ? $named->{c} : _getDialogueTimeout($hash, 'confirm');
            }
        }
    }
    return;
}

sub initialize_rhasspyTweaks {
    my $hash    = shift // return;
    my $attrVal = shift // return;

    my ($tweak, $values, $device, $err );
    for my $line (split m{\n}x, $attrVal) {
        next if !length $line;
        if ($line =~ m{\A[\s]*timerLimits[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            $tweak = trim($tweak);
            return "Error in $line! Provide 5 comma separated numeric values!" if !length $values && $init_done;
            my @test = split m{,}x, $values;
            return "Error in $line! Provide 5 comma separated numeric values!" if @test != 5 && $init_done;
            #$values = qq{($values)} if $values !~ m{\A([^()]*)\z}x;
            $hash->{helper}{tweaks}{$tweak} = [@test];
            next;
        }

        if ($line =~ m{\A[\s]*(timeouts|useGenericAttrs|timerSounds)[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            $tweak = trim($tweak);
            return "Error in $line! No content provided!" if !length $values && $init_done;
            my($unnamedParams, $namedParams) = parseParams($values);
            return "Error in $line! Provide at least one key-value pair!" if ( @{$unnamedParams} || !keys %{$namedParams} ) && $init_done;
            $hash->{helper}{tweaks}{$tweak} = $namedParams;
            next;
        }

    }
    return;
}

sub configure_DialogManager {
    my $hash      = shift // return;
    my $siteId    = shift;
    my $toDisable = shift // [qw(ConfirmAction CancelAction ChoiceRoom ChoiceDevice)];
    my $enable    = shift // q{false};
    #return if !$hash->{testing};

    #loop for global initialization or for several siteId's
    if (!defined $siteId || $siteId =~ m{,}xms) {
        $siteId = ReadingsVal( $hash->{NAME}, 'siteIds', 'default' ) if !defined $siteId;
        my @siteIds = split m{,}xms, $siteId;
        for (@siteIds) {
            configure_DialogManager($hash, $_, $toDisable, $enable);
        }
    }

    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};

=pod    disable some intents by default https://rhasspy.readthedocs.io/en/latest/reference/#dialogue-manager
hermes/dialogueManager/configure (JSON)

    Sets the default intent filter for all subsequent dialogue sessions
    intents: [object] - Intents to enable/disable (empty for all intents)
        intentId: string - Name of intent
        enable: bool - true if intent should be eligible for recognition
    siteId: string = "default" - Hermes site ID
    
    Further reading on continuing sessions:
    https://rhasspy-hermes-app.readthedocs.io/en/latest/usage.html#continuing-a-session
=cut

    my @disabled;
    for (@{$toDisable}) {
        my $id = qq(${language}.${fhemId}:$_);
        my $disable = {intentId => "$id", enable => "$enable"};
        push @disabled, $disable;
    }
    #my $disable = {intentId => [@disabled], enable => "$enable"};
    my $sendData = {
        siteId  => $siteId,
        intents => [@disabled]
    };

    my $json = toJSON($sendData);

    IOWrite($hash, 'publish', qq{hermes/dialogueManager/configure $json});
    return;
}

sub init_custom_intents {
    my $hash    = shift // return;
    my $attrVal = shift // return;
    
    for my $line (split m{\n}x, $attrVal) {
        next if !length $line;
        #return "invalid line $line" if $line !~ m{(?<intent>[^=]+)\s*=\s*(?<perlcommand>(?<function>([^(]+))\((?<arg>.*)\)\s*)}x;
        return "invalid line $line" if $line !~ m{ 
            (?<intent>[^=]+)\s*     #string up to  =, w/o ending whitespace 
            =\s*                    #separator = and potential whitespace
            (?<perlcommand>         #identifier
                (?<function>([^(]+))#string up to opening bracket
                \(                  #opening bracket
                (?<arg>.*)\))\s*    #everything up to the closing bracket, w/o ending whitespace
                }xms; 
        my $intent = trim($+{intent});
        return "no intent found in $line!" if (!$intent || $intent eq q{}) && $init_done;
        my $function = trim($+{function});
        return "invalid function in line $line" if $function =~ m{\s+}x;
        my $perlcommand = trim($+{perlcommand});
        my $err = perlSyntaxCheck( $perlcommand );
        return "$err in $line" if $err && $init_done;
        
        #$hash->{helper}{custom}{$+{intent}}{perl} = $perlcommand; #Beta-User: delete after testing!
        $hash->{helper}{custom}{$intent}{function} = $function;

        my $args = trim($+{arg});
        my @params;
        for my $ar (split m{,}x, $args) {
           $ar =trim($ar);
           #next if $ar eq q{}; #Beta-User having empty args might be intented...
           push @params, $ar; 
        }

        $hash->{helper}{custom}{$+{intent}}{args} = \@params;
    }
    return;
}


sub initialize_devicemap {
    my $hash = shift // return;
    
    my $devspec = $hash->{devspec};
    delete $hash->{helper}{devicemap};

    my @devices = devspec2array($devspec);

    # when called with just one keyword, devspec2array may return the keyword, even if the device doesn't exist...
    return if !@devices;
    
    for (@devices) {
        _analyze_genDevType($hash, $_) if $hash->{useGenericAttrs};
        _analyze_rhassypAttr($hash, $_);
    }

    return;
}


sub _analyze_rhassypAttr {
    my $hash   = shift // return;
    my $device = shift // return;

    my $prefix = $hash->{prefix};

    return if !defined AttrVal($device,"${prefix}Room",undef) 
           && !defined AttrVal($device,"${prefix}Name",undef)
           && !defined AttrVal($device,"${prefix}Channels",undef) 
           && !defined AttrVal($device,"${prefix}Colors",undef)
           && !defined AttrVal($device,"${prefix}Group",undef)
           && !defined AttrVal($device,"${prefix}Specials",undef);

    #rhasspyRooms ermitteln
    my @rooms;
    my $attrv = AttrVal($device,"${prefix}Room",undef);
    @rooms = split m{,}x, lc $attrv if defined $attrv;
    @rooms = split m{,}xi, $hash->{helper}{devicemap}{devices}{$device}->{rooms} if !@rooms && defined $hash->{helper}{devicemap}{devices}{$device}->{rooms};
    if (!@rooms) {
        $rooms[0] = $hash->{defaultRoom};
    }
    $hash->{helper}{devicemap}{devices}{$device}->{rooms} = join q{,}, @rooms;

    #rhasspyNames ermitteln
    my @names;
    $attrv = AttrVal($device,"${prefix}Name",AttrVal($device,'alias',$device));
    push @names, split m{,}x, lc $attrv;
    $hash->{helper}{devicemap}{devices}{$device}->{alias} = $names[0];

    for my $dn (@names) {
       for (@rooms) {
           $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$dn} = $device;
       }
    }
    $hash->{helper}{devicemap}{devices}{$device}->{names} = join q{,}, @names;

    for my $item ('Channels', 'Colors') {
        my @rows = split m{\n}x, AttrVal($device, "${prefix}${item}", q{});

        for my $row (@rows) {
            my ($key, $val) = split m{=}x, $row, 2;
            next if !$val; 
            for my $rooms (@rooms) {
                push @{$hash->{helper}{devicemap}{$item}{$rooms}{$key}}, $device if !grep { m{\A$device\z}x } @{$hash->{helper}{devicemap}{$item}{$rooms}{$key}};
            }
            $hash->{helper}{devicemap}{devices}{$device}{$item}{$key} = $val;
        }
    }

    #Hash mit {FHEM-Device-Name}{$intent}{$type}?
    my $mappingsString = AttrVal($device, "${prefix}Mapping", q{});
    for (split m{\n}x, $mappingsString) {
        my ($key, $val) = split m{:}x, $_, 2;
        #$key = lc($key);
        #$val = lc($val);
        my %currentMapping = splitMappingString($val);
        next if !%currentMapping;
        # Übersetzen, falls möglich:
        $currentMapping{type} = 
            defined $currentMapping{type} ?
            $de_mappings->{ToEn}->{$currentMapping{type}} // $currentMapping{type} // $key
            : $key;
        $hash->{helper}{devicemap}{devices}{$device}{intents}{$key}->{$currentMapping{type}} = \%currentMapping;
    }

    #Specials
    my @lines = split m{\n}x, AttrVal($device, "${prefix}Specials", q{});
    for my $line (@lines) {
        my ($key, $val) = split m{:}x, $line, 2;
        next if !$val; 
        
        if ($key eq 'group') {
            my($unnamed, $named) = parseParams($val); 
            my $specials = {};
            my $partOf = $named->{partOf} // shift @{$unnamed};
            $specials->{partOf} = $partOf if defined $partOf;
            $specials->{async_delay} = $named->{async_delay} if defined $named->{async_delay};
            $specials->{prio} = $named->{prio} if defined $named->{prio};

            $hash->{helper}{devicemap}{devices}{$device}{group_specials} = $specials;
        }
        if ($key eq 'colorForceHue2rgb') {
            $hash->{helper}{devicemap}{devices}{$device}{color_specials}{forceHue2rgb} = $val;
        }
        if ($key eq 'colorCommandMap') {
            my($unnamed, $named) = parseParams($val);
            $hash->{helper}{devicemap}{devices}{$device}{color_specials}{CommandMap} = $named if defined $named;
        }
        if ($key eq 'colorTempMap') {
            my($unnamed, $named) = parseParams($val);
            $hash->{helper}{devicemap}{devices}{$device}{color_specials}{Colortemp} = $named if defined $named;
        }
        if ($key eq 'venetianBlind') {
            my($unnamed, $named) = parseParams($val);
            my $specials = {};
            my $vencmd = $named->{setter} // shift @{$unnamed};
            my $vendev = $named->{device} // shift @{$unnamed};
            $specials->{setter} = $vencmd if defined $vencmd;
            $specials->{device} = $vendev if defined $vendev;
            $specials->{CustomCommand} = $named->{CustomCommand} if defined $named->{CustomCommand};

            $hash->{helper}{devicemap}{devices}{$device}{venetian_specials} = $specials if defined $vencmd || defined $vendev;
        }
        if ($key eq 'priority') {
            my($unnamed, $named) = parseParams($val);
            $hash->{helper}{devicemap}{devices}{$device}{prio}{inRoom} = $named->{inRoom} if defined $named->{inRoom};
            $hash->{helper}{devicemap}{devices}{$device}{prio}{outsideRoom} = $named->{outsideRoom} if defined $named->{outsideRoom};
        }
        if ( $key eq 'scenes' && defined $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene} ) {
            my($unnamed, $named) = parseParams($val);
            my $combined = _combineHashes( $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene}, $named);
            for (keys %{$combined}) {
                delete $combined->{$_} if $combined->{$_} eq 'none';
            }
            keys %{$combined} ?
                $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene} = $combined
                : delete $hash->{helper}{devicemap}{devices}{$device}{intents}->{SetScene};
        }
    }

    my @groups;
    $attrv = AttrVal($device,"${prefix}Group", undef);
    $attrv = $attrv // AttrVal($device,'group', undef);
    $hash->{helper}{devicemap}{devices}{$device}{groups} = lc $attrv if $attrv;

    return;
}


sub _analyze_genDevType {
    my $hash   = shift // return;
    my $device = shift // return;

    my $prefix = $hash->{prefix};

    #prerequesite: gdt has to be set!
    my $gdt = AttrVal($device, 'genericDeviceType', undef) // return; 

    my @names;
    my $attrv;
    #additional names?
    if (!defined AttrVal($device,"${prefix}Name", undef)) {

        $attrv = AttrVal($device,'alexaName', undef);
        push @names, split m{;}x, lc $attrv if $attrv;

        $attrv = AttrVal($device,'siriName',undef);
        push @names, split m{,}x, lc $attrv if $attrv;

        my $alias = lc AttrVal($device,'alias',$device);
        $names[0] = $alias if !@names;
    }
    $hash->{helper}{devicemap}{devices}{$device}->{alias} = $names[0] if $names[0];

    @names = get_unique(\@names);
    $hash->{helper}{devicemap}{devices}{$device}->{names} = join q{,}, @names if $names[0];

    my @rooms;
    if (!defined AttrVal($device,"${prefix}Room", undef)) {
        $attrv = AttrVal($device,'alexaRoom', undef);
        push @rooms, split m{,}x, lc $attrv if $attrv;

        $attrv = AttrVal($device,'room',undef);
        push @rooms, split m{,}x, lc $attrv if $attrv;
        $rooms[0] = $hash->{defaultRoom} if !@rooms;
    }

    @rooms = get_unique(\@rooms);

    for my $dn (@names) {
       for (@rooms) {
           $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$dn} = $device;
       }
    }
    $hash->{helper}{devicemap}{devices}{$device}->{rooms} = join q{,}, @rooms;

    $attrv = AttrVal($device,'group', undef);
    $hash->{helper}{devicemap}{devices}{$device}{groups} = lc $attrv if $attrv;

    my $hbmap  = AttrVal($device, 'homeBridgeMapping', q{}); 
    my $allset = getAllSets($device);
    my $currentMapping;

    if ( ($gdt eq 'switch' || $gdt eq 'light') && $allset =~ m{\bo[nf]+([\b:\s]|\Z)}xms ) {
        $currentMapping = 
            { GetOnOff => { GetOnOff => {currentVal => 'state', type => 'GetOnOff', valueOff => 'off'}}, 
              SetOnOff => { SetOnOff => {cmdOff => 'off', type => 'SetOnOff', cmdOn => 'on'}}
            };
        if ( $gdt eq 'light' && $allset =~ m{\bdim([\b:\s]|\Z)}xms ) {
            my $maxval = InternalVal($device, 'TYPE', 'unknown') eq 'ZWave' ? 99 : 100;
            $currentMapping->{SetNumeric} = {
            brightness => { cmd => 'dim', currentVal => 'state', maxVal => $maxval, minVal => '0', step => '3', type => 'brightness'}};
        }

        elsif ( $gdt eq 'light' && $allset =~ m{\bpct([\b:\s]|\Z)}xms ) {
            $currentMapping->{SetNumeric} = {
            brightness => { cmd => 'pct', currentVal => 'pct', maxVal => '100', minVal => '0', step => '5', type => 'brightness'}};
        }

        elsif ( $gdt eq 'light' && $allset =~ m{\bbrightness([\b:\s]|\Z)}xms ) {
            $currentMapping->{SetNumeric} = {
                brightness => { cmd => 'brightness', currentVal => 'brightness', maxVal => '255', minVal => '0', step => '10', map => 'percent', type => 'brightness'}};
        }
        $currentMapping = _analyze_genDevType_setter( $allset, $currentMapping, $device );
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }
    elsif ( $gdt eq 'thermostat' ) {
        my $desTemp = $allset =~ m{\b(desiredTemp)([\b:\s]|\Z)}xms ? $1 : 'desired-temp';
        my $measTemp = InternalVal($device, 'TYPE', 'unknown') eq 'CUL_HM' ? 'measured-temp' : 'temperature';
        $currentMapping = 
            { GetNumeric => { 'desired-temp' => {currentVal => $desTemp, type => 'desired-temp'},
            temperature => {currentVal => $measTemp, type => 'temperature'}}, 
            SetNumeric => {'desired-temp' => { cmd => $desTemp, currentVal => $desTemp, maxVal => '28', minVal => '10', step => '0.5', type => 'temperature'}}
            };
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    elsif ( $gdt eq 'thermometer' ) {
        my $r = $defs{$device}{READINGS};
        if($r) {
            for (sort keys %{$r}) {
                if ( $_ =~ m{\A(?<id>temperature|humidity)\z}x ) {
                    $currentMapping->{GetNumeric}->{$+{id}} = {currentVal => $+{id}, type => $+{id} };
                }
            }
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    elsif ( $gdt eq 'blind' ) {
        if ( $allset =~ m{\bdim([\b:\s]|\Z)}xms ) {
            my $maxval = InternalVal($device, 'TYPE', 'unknown') eq 'ZWave' ? 99 : 100;
            $currentMapping = 
            { GetNumeric => { dim => {currentVal => 'state', type => 'setTarget' } },
            GetOnOff => { GetOnOff => { currentVal=>'dim', valueOn=>$maxval } },
            SetOnOff => { SetOnOff => {cmdOff => 'dim 0', type => 'SetOnOff', cmdOn => "dim $maxval"} },
            SetNumeric => { setTarget => { cmd => 'dim', currentVal => 'state', maxVal => $maxval, minVal => '0', step => '11', type => 'setTarget'} }
            };
        }

        elsif ( $allset =~ m{\bpct([\b:\s]|\Z)}xms ) {
            $currentMapping = { 
            GetNumeric => { 'pct' => {currentVal => 'pct', type => 'setTarget'} },
            GetOnOff => { GetOnOff => {currentVal=>'pct', valueOn=>'100' } },
            SetOnOff => { SetOnOff => {cmdOff => 'pct 0', type => 'SetOnOff', cmdOn => 'pct 100'} },
            SetNumeric => { setTarget => { cmd => 'pct', currentVal => 'pct', maxVal => '100', minVal => '0', step => '13', type => 'setTarget'} }
            };
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    if ( $gdt eq 'media' ) { #genericDeviceType media
        $currentMapping = { 
            GetOnOff => { GetOnOff => {currentVal => 'state', type => 'GetOnOff', valueOff => 'off'}},
            SetOnOff => { SetOnOff => {cmdOff => 'off', type => 'SetOnOff', cmdOn => 'on'} },
            GetNumeric => { 'volume' => {currentVal => 'volume', type => 'volume' } }
            };

        $currentMapping = _analyze_genDevType_setter( $hash, $device, $allset, $currentMapping );
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    return;
}

sub _analyze_genDevType_setter {
    my $hash    = shift;
    my $device  = shift;
    my $setter  = shift;
    my $mapping = shift // {};

    my $allValMappings = {
        MediaControls => { 
            cmdPlay => 'play', cmdPause => 'pause' ,cmdStop => 'stop', cmdBack => 'previous', cmdFwd => 'next', chanUp => 'channelUp', chanDown => 'channelDown' }
        };
    for my $okey ( keys %{$allValMappings} ) {
        my $ikey = $allValMappings->{$okey};
        for ( keys %{$ikey} ) {
            my $val = $ikey->{$_};
            $mapping->{$okey}->{$okey}->{$_} = $val if $setter =~ m{\b$val([\b:\s]|\Z)}xms;
        }
    }
    my $allKeyMappings = {
        SetNumeric => { 
            volume => { cmd => 'volume', currentVal => 'volume', maxVal => '100', minVal => '0', step => '2', type => 'volume'},
            channel => { cmd => 'channel', currentVal => 'channel', step => '1', type => 'channel'}
            },
        SetColorParms => { hue => { cmd => 'hue', currentVal => 'hue', type => 'hue', map => 'percent'},
            color => { cmd => 'color', currentVal => 'color', type => 'color', map => 'percent'},
            sat => { cmd => 'sat', currentVal => 'sat', type => 'sat', map => 'percent'},
            ct => { cmd => 'ct', currentVal => 'ct', type => 'ct', map => 'percent'},
            rgb => { cmd => 'rgb', currentVal => 'rgb', type => 'rgb'},
            color_temp => { cmd => 'color_temp', currentVal => 'color_temp', type => 'ct', map => 'percent'},
            RGB => { cmd => 'RGB', currentVal => 'RGB', type => 'rgb'},
            hex => { cmd => 'hex', currentVal => 'hex', type => 'rgb'},
            saturation => { cmd => 'saturation', currentVal => 'saturation', type => 'sat', map => 'percent'}
            }
        };
    for my $okey ( keys %{$allKeyMappings} ) {
        my $ikey = $allKeyMappings->{$okey};
        for ( keys %{$ikey} ) {
            $mapping->{$okey}->{$ikey->{$_}->{type}} = $ikey->{$_} if $setter =~ m{\b$_([\b:\s]|\Z)}xms;
            #for my $col (qw(ct hue color sat)) {
            if ( $okey eq 'SetColorParms') { #=~ m{\A(ct|hue|color|sat)\z}xms ) {
                my $col = $_;
                if ($setter =~ m{\b${col}:[^\s\d]+,(?<min>[0-9.]+),(?<step>[0-9.]+),(?<max>[0-9.]+)\b}xms) {
                    $mapping->{$okey}->{$ikey->{$_}->{type}}->{maxVal} = $+{max};
                    $mapping->{$okey}->{$ikey->{$_}->{type}}->{minVal} = $+{min};
                    $mapping->{$okey}->{$ikey->{$_}->{type}}->{step} = $+{step};
                }
            }
        }
    }

    if ($setter =~ m{\bscene:(?<scnames>[\S]+)}xm) {
        for my $scname (split m{,}xms, $+{scnames}) {
            $mapping->{SetScene}->{SetScene}->{$scname} = $scname;
        }
    }
    return $mapping;
}


sub perlExecute {
    my $hash   = shift // return;
    my $device = shift;
    my $cmd    = shift;
    my $value  = shift;
    my $siteId = shift // $hash->{defaultRoom};
    $siteId = $hash->{defaultRoom} if $siteId eq 'default';

    # Nutzervariablen setzen
    my %specials = (
         '$DEVICE' => $device,
         '$VALUE'  => $value,
         '$ROOM'   => $siteId
    );

    $cmd  = EvalSpecials($cmd, %specials);

    # CMD ausführen
    return AnalyzePerlCommand( $hash, $cmd );
}

sub RHASSPY_DialogTimeout {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;

    my $identiy = $fnHash->{MODIFIER};

    my $data     = shift // $hash->{helper}{'.delayed'}->{$identiy};
    delete $hash->{helper}{'.delayed'}{$identiy};
    deleteSingleRegisteredInternalTimer($identiy, $hash); 

    my $siteId = $data->{siteId};
    my $toDisable = defined $data->{'.ENABLED'} ? $data->{'.ENABLED'} : [qw(ConfirmAction CancelAction)];

    my $response = $hash->{helper}{lng}->{responses}->{DefaultConfirmationTimeout};
    respond ($hash, $data->{requestType}, $data->{sessionId}, $siteId, $response);
    configure_DialogManager($hash, $siteId, $toDisable, 'false');

    return;
}

sub setDialogTimeout {
    my $hash     = shift // return;
    my $data     = shift // return; # $hash->{helper}{'.delayed'};
    my $timeout  = shift;
    my $response = shift;
    my $toEnable = shift // [qw(ConfirmAction CancelAction)];

    my $siteId = $data->{siteId};
    $data->{'.ENABLED'} = $toEnable;
    my $identiy = qq($data->{sessionId});

    $response = $hash->{helper}{lng}->{responses}->{DefaultConfirmationReceived} if $response eq 'default';
    $hash->{helper}{'.delayed'}{$identiy} = $data;

    resetRegisteredInternalTimer( $identiy, time + $timeout, \&RHASSPY_DialogTimeout, $hash, 0);
    #InternalTimer(time + $timeout, \&RHASSPY_DialogTimeout, $hash, 0);

    #interactive dialogue as described in https://rhasspy.readthedocs.io/en/latest/reference/#dialoguemanager_continuesession and https://docs.snips.ai/articles/platform/dialog/multi-turn-dialog
    my @ca_strings;
    for (@{$toEnable}) {
        my $id = qq{$hash->{LANGUAGE}.$hash->{fhemId}:$_};
        push @ca_strings, $id;
    }
    
    #my $ca_part = qq{$hash->{LANGUAGE}.$hash->{fhemId}:ConfirmAction};
    #push @ca_strings, $ca_part;
    #$ca_part = qq{$hash->{LANGUAGE}.$hash->{fhemId}:CancelAction};
    #push @ca_strings, $ca_part;
    my $reaction = ref $response eq 'HASH' 
        ? $response
        : { text         => $response, 
            intentFilter => [@ca_strings],
            #customData => $data
          };

    configure_DialogManager($hash, $siteId, $toEnable, 'true');
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $reaction);
    
    my $toTrigger = $hash->{'.toTrigger'} // $hash->{NAME};
    delete $hash->{'.toTrigger'};

    return $toTrigger;
}

#from https://stackoverflow.com/a/43873983, modified...
sub get_unique {
    my $arr    = shift;
    my $sorted = shift; #true if shall be sorted (longest first!)

    my @unique = uniq @{$arr};
    return if !@unique;

    return @unique if !$sorted;

    my @sorted = sort { length($b) <=> length($a) } @unique;
    #Log3(undef, 5, "get_unique sorted to ".join q{ }, @sorted);
    return @sorted;
}

#small function to replace variables
sub _replace {
    my $hash  = shift // return;
    my $cmd   = shift // return;
    my $hash2 = shift;
    my $self = $hash2->{'$SELF'} // $hash->{NAME};
    my $name = $hash2->{'$NAME'} // $hash->{NAME};
    my $parent = ( caller(1) )[3];
    Log3($hash->{NAME}, 5, "_replace from $parent starting with: $cmd");

    my %specials = (
        '$SELF' => $self,
        '$NAME' => $name
    );
    %specials = (%specials, %{$hash2});
    for my $key (keys %specials) {
        my $val = $specials{$key};
        $cmd =~ s{\Q$key\E}{$val}gxms;
    }
    Log3($hash->{NAME}, 5, "_replace from $parent returns: $cmd");
    return $cmd;
}

#based on compareHashes https://stackoverflow.com/a/56128395
sub _combineHashes {
    my ($hash1, $hash2, $parent) = @_;
    my $hash3 = {};
   
    for my $key (keys %{$hash1}) {
        $hash3->{$key} = $hash1->{$key};
        if (!exists $hash2->{$key}) {
            next;
        }
        if ( ref $hash3->{$key} eq 'HASH' and ref $hash2->{$key} eq 'HASH' ) {
            $hash3->{$key} = _combineHashes($hash3->{$key}, $hash2->{$key}, $key);
        } elsif ( !ref $hash3->{$key} && !ref $hash2->{$key} ) {
            $hash3->{$key} = $hash2->{$key};
        }
    }
    for (qw(commaconversion mutated_vowels words)) {
        $hash3->{$_} = $hash2->{$_} if defined $hash2->{$_};
    }
    return $hash3;
}

# derived from structure_asyncQueue
sub RHASSPY_asyncQueue {
    my $hash = shift // return;
    my $next_cmd = shift @{$hash->{'.asyncQueue'}};
    if (defined $next_cmd) {
        analyzeAndRunCmd($hash, $next_cmd->{device}, $next_cmd->{cmd}) if defined $next_cmd->{cmd};
        handleIntentSetNumeric($hash, $next_cmd->{SetNumeric}) if defined $next_cmd->{SetNumeric};
        my $async_delay = $next_cmd->{delay} // 0;
        InternalTimer(time+$async_delay,\&RHASSPY_asyncQueue,$hash,0);
    }
    return;
}

sub _sortAsyncQueue {
    my $hash = shift // return;
    my $queue = @{$hash->{'.asyncQueue'}};

    my @devlist = sort {
        $a->{prio} <=> $b->{prio}
        or
        $a->{delay} <=> $b->{delay}
        } @{$queue};
    $hash->{'.asyncQueue'} = @devlist;
    return;
}

# Get all devicenames with Rhasspy relevance
sub getAllRhasspyNames {
    my $hash = shift // return;
    return if !defined $hash->{helper}{devicemap};

    my @devices;
    my $rRooms = $hash->{helper}{devicemap}{rhasspyRooms};
    for my $key (keys %{$rRooms}) {
        push @devices, keys %{$rRooms->{$key}};
    }
    return get_unique(\@devices, 1 );
}

# Alle Raumbezeichnungen sammeln
sub getAllRhasspyRooms {
    my $hash = shift // return;
    return keys %{$hash->{helper}{devicemap}{rhasspyRooms}} if defined $hash->{helper}{devicemap};
    return;
}


# Alle Sender sammeln
sub getAllRhasspyChannels {
    my $hash = shift // return;
    return if !defined $hash->{helper}{devicemap};

    my @channels;
    for my $room (keys %{$hash->{helper}{devicemap}{Channels}}) {
        push @channels, keys %{$hash->{helper}{devicemap}{Channels}{$room}}
    }
    return get_unique(\@channels, 1 );
}


# Collect all NumericTypes 
sub getAllRhasspyTypes {
    my $hash = shift // return;
    return if !defined $hash->{helper}{devicemap};

    my @types;
    for my $dev (keys %{$hash->{helper}{devicemap}{devices}}) {
        for my $intent (keys %{$hash->{helper}{devicemap}{devices}{$dev}{intents}}) {
            my $type;
            $type = $hash->{helper}{devicemap}{devices}{$dev}{intents}{$intent};
            push @types, keys %{$type} if $intent =~ m{\A[GS]etNumeric}x;
        }
    }
    return get_unique(\@types, 1 );
}


# Collect all clours
sub getAllRhasspyColors {
    my $hash = shift // return;
    return if !defined $hash->{helper}{devicemap};

    my @colors;
    for my $room (keys %{$hash->{helper}{devicemap}{Colors}}) {
        push @colors, keys %{$hash->{helper}{devicemap}{Colors}{$room}}
    }
    return get_unique(\@colors, 1 );
}


# get a list of all used groups
sub getAllRhasspyGroups {
    my $hash = shift // return;
    my @groups;
    
    for my $device (keys %{$hash->{helper}{devicemap}{devices}}) {
        my $devgroups = $hash->{helper}{devicemap}{devices}{$device}->{groups} // q{};;
        #for (@{$devgroups}) {
        for (split m{,}xi, $devgroups ) {
            push @groups, $_;
        }
    }
    return get_unique(\@groups, 1);
}

sub getAllRhasspyScenes {
    my $hash = shift // return;
    
    my @devices = devspec2array($hash->{devspec});
    
    my (@sentences, @names);
    for my $device (@devices) {
        next if !defined $hash->{helper}{devicemap}{devices}{$device}{intents}->{SetScene};
        push @names, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{names}; 
        my $scenes = $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene};
        for (keys %{$scenes}) {
            push @sentences, qq{( $scenes->{$_} ){Scene:$_}};
        }
    }

    @sentences = get_unique(\@sentences);
    @names = get_unique(\@names);
    return (\@sentences, \@names);
}


sub getAllRhasspyNamesAndGroupsByIntent {
    my $hash = shift // return;
    my $intent = shift // return;

    my @names;
    my @groups;
    for my $device (devspec2array($hash->{devspec})) {
        next if !defined $hash->{helper}{devicemap}{devices}{$device}{intents}->{$intent};
        push @names, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{names}; 
        push @groups, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{groups}; 
    }

    @names  = uniq(@names);
    @groups = uniq(@groups);
    return (\@names, \@groups);
}


# Derive room info from spoken text, siteId or additional logics around siteId
sub getRoomName {
    my $hash = shift // return;
    my $data = shift // return;

    # Slot "Room" in JSON? Otherwise use info from used satellite
    return $data->{Room} if exists($data->{Room});

    my $room;

    #Beta-User: This might be the right place to check, if there's additional logic implemented...

    my $siteId = $data->{siteId};

    my $rreading = makeReadingName("siteId2room_$siteId");
    $siteId =~ s{\A([^.]+).*}{$1}xms;
    utf8::downgrade($siteId, 1);
    $room = ReadingsVal($hash->{NAME}, $rreading, lc $siteId);
    #$room = ReadingsVal($hash->{NAME}, $rreading, $siteId);
    $room = $hash->{defaultRoom} if $room eq 'default' || !(length $room);
    Log3($hash->{NAME}, 5, "room is identified using siteId as $room");

    return $room;
}


# Gerät über Raum und Namen suchen.
sub getDeviceByName {
    my $hash = shift // return;
    my $room = shift; 
    my $name = shift; #either of the two required
    
    return if !$room && !$name;
    
    my $device;
    
    return if !defined $hash->{helper}{devicemap};
    
    $device = $hash->{helper}{devicemap}{rhasspyRooms}{$room}{$name};
        #return $device if $device;
    if ($device) {
        Log3($hash->{NAME}, 5, "Device selected (by hash, with room and name): $device");
        return $device ;
    }
    for (keys %{$hash->{helper}{devicemap}{rhasspyRooms}}) {
        $device = $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$name};
        #return $device if $device;
        if ($device) {
            Log3($hash->{NAME}, 5, "Device selected (by hash, using only name): $device");
            return $device ;
        }
    }
    Log3($hash->{NAME}, 1, "No device for >>$name<< found, especially not in room >>$room<< (also not outside)!");
    return;
}


# returns lists of "might be relevant" devices via room, intent and (optional) Type info
sub getDevicesByIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?
    my $subType = shift // $type;

    my @matchesInRoom; my @matchesOutsideRoom;

    return if !defined $hash->{helper}{devicemap};
    for my $devs (keys %{$hash->{helper}{devicemap}{devices}}) {
        my $mapping = getMapping($hash, $devs, $intent, { type => $type, subType => $subType }, 1, 1) // next;
        my $mappingType = $mapping->{type};
        my $rooms = $hash->{helper}{devicemap}{devices}{$devs}->{rooms};

        # get lists of devices that may fit to requirements
        if ( !defined $type ) {
            $rooms =~ m{\b$room\b}ix
            ? push @matchesInRoom, $devs 
            : push @matchesOutsideRoom, $devs;
        }
        elsif ( defined $type && $mappingType && $type =~ m{\A$mappingType\z}ix ) {
            $rooms =~ m{\b$room\b}ix
            ? push @matchesInRoom, $devs
            : push @matchesOutsideRoom, $devs;
        }
    }
    return (\@matchesInRoom, \@matchesOutsideRoom);
}

# Identify single device via room, intent and (optional) Type info
sub getDeviceByIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?
    #my $inBulk = shift // 0;

    #rem. Beta-User: atm function is only called by GetNumeric!
    my $device;

    # Devices sammeln
    my ($matchesInRoom, $matchesOutsideRoom) = getDevicesByIntentAndType($hash, $room, $intent, $type);
    Log3($hash->{NAME}, 5, "matches in room: @{$matchesInRoom}, matches outside: @{$matchesOutsideRoom}");
    my ($response, $last_item, $first_items);

    my @priority;
    # Erstes Device im passenden Raum zurückliefern falls vorhanden, sonst erstes Device außerhalb
    if ( @{$matchesInRoom} ) {
        if ( @{$matchesInRoom} == 1) {
            $device = shift @{$matchesInRoom};
        } else {
            my @aliases;
            for my $dev (@{$matchesInRoom}) {
                push @aliases, $hash->{helper}{devicemap}{devices}{$dev}->{alias};
                if (defined $hash->{helper}{devicemap}{devices}{$dev}->{prio} && defined $hash->{helper}{devicemap}{devices}{$dev}{prio}->{inRoom}) {
                    push @priority, $dev if $hash->{helper}{devicemap}{devices}{$dev}{prio}->{inRoom} =~ m{\b$type\b}xms;
                }
            }
            if (@priority) { 
                $device = shift @priority;
            } else {
                push @{$device}, join q{,}, @aliases;
                $last_item = pop @aliases;
                $first_items = join q{ }, @aliases;
                $response = getResponse ($hash, 'RequestChoiceDevice');
                $response =~ s{(\$\w+)}{$1}eegx;
                unshift @{$device}, $response;
                unshift @{$device}, $matchesInRoom->[0];
                push @{$device}, 'RequestChoiceDevice';
            }
        }
    } elsif ( @{$matchesOutsideRoom} ) { 
        if ( @{$matchesOutsideRoom} == 1 ) {
            $device = shift @{$matchesOutsideRoom};
        } else {
            my @rooms;
            for my $dev (@{$matchesOutsideRoom}) {
                push @rooms, (split m{,}x, $hash->{helper}{devicemap}{devices}{$dev}->{rooms})[0];
                if (defined $hash->{helper}{devicemap}{devices}{$dev}->{prio} && defined $hash->{helper}{devicemap}{devices}{$dev}{prio}->{outsideRoom}) {
                    push @priority, $dev if $hash->{helper}{devicemap}{devices}{$dev}{prio}->{outsideRoom} =~ m{\b$type\b}xms;
                }
            }
            @rooms = get_unique(\@rooms);
            if ( @rooms == 1 ) {
                my @aliases;
                for my $dev (@{$matchesOutsideRoom}) {
                    push @aliases, $hash->{helper}{devicemap}{devices}{$dev}->{alias};
                    if (defined $hash->{helper}{devicemap}{devices}{$dev}->{prio} && defined $hash->{helper}{devicemap}{devices}{$dev}{prio}->{inRoom}) {
                        unshift @priority, $dev if $hash->{helper}{devicemap}{devices}{$dev}{prio}->{inRoom} =~ m{\b$type\b}xms;
                    }
                }
                if (@priority) { 
                    $device = shift @priority;
                } else {
                    push @{$device}, join q{,}, @aliases;
                    $last_item = pop @aliases;
                    $first_items = join q{ }, @aliases;
                    $response = getResponse ($hash, 'RequestChoiceDevice');
                    $response =~ s{(\$\w+)}{$1}eegx;
                    unshift @{$device}, $response;
                    unshift @{$device}, $matchesOutsideRoom->[0];
                    push @{$device}, 'RequestChoiceDevice';
                }
            } else {
                if (@priority) { 
                    $device = shift @priority;
                } else {
                    push @{$device}, join q{,}, @rooms;
                    $last_item = pop @rooms;
                    my $first_items = join q{ }, @rooms;
                    my $response = getResponse ($hash, 'RequestChoiceRoom');
                    $response =~ s{(\$\w+)}{$1}eegx;
                    unshift @{$device}, $response;
                    unshift @{$device}, $matchesOutsideRoom->[0];
                    push @{$device}, 'RequestChoiceRoom';
                }
            }
        }
    }
    #$device = (@{$matchesInRoom}) ? shift @{$matchesInRoom} : shift @{$matchesOutsideRoom};

    Log3($hash->{NAME}, 5, "Device selected: ". defined $response ? 'more than one' : $device ? $device : "none");

    return $device;
}


# Eingeschaltetes Gerät mit bestimmten Intent und optional Type suchen
sub getActiveDeviceForIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?
    
    my $device;
    my ($matchesInRoom, $matchesOutsideRoom) = getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Anonyme Funktion zum finden des aktiven Geräts
    my $activeDevice = sub ($$) {
        my $subhash = shift;
        my $devices = shift // return;
        my $match;

        for (@{$devices}) {
            my $mapping = getMapping($subhash, $_, 'GetOnOff', undef, defined $hash->{helper}{devicemap}, 1);
            if (defined $mapping ) {
                # Gerät ein- oder ausgeschaltet?
                my $value = _getOnOffState($subhash, $_, $mapping);
                if ($value) {
                    $match = $_;
                    last;
                }
            }
        }
        return $match;
    };

    # Gerät finden, erst im aktuellen Raum, sonst in den restlichen
    $device = $activeDevice->($hash, $matchesInRoom);
    $device = $activeDevice->($hash, $matchesOutsideRoom) if !defined $device;

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Gerät mit bestimmtem Sender suchen
sub getDeviceByMediaChannel {
    my $hash    = shift // return;
    my $room    = shift;
    my $channel = shift; #Beta-User: any necessary parameters...?
    
    my $device;
    
    return if !defined $hash->{helper}{devicemap};
    my $devices = $hash->{helper}{devicemap}{Channels}{$room}->{$channel};
    $device = ${$devices}[0];
    if ($device) {
        Log3($hash->{NAME}, 5, "Device selected (by hash, with room and channel): $device");
        return $device ;
    }
    for (sort keys %{$hash->{helper}{devicemap}{Channels}}) {
        $devices = $hash->{helper}{devicemap}{Channels}{$_}{$channel};
        $device = ${$devices}[0];
    
        #return $device if $device;
        if ($device) {
            Log3($hash->{NAME}, 5, "Device selected (by hash, using only channel): $device");
            return $device ;
        }
    }
    Log3($hash->{NAME}, 1, "No device for >>$channel<< found, especially not in room >>$room<< (also not outside)!");
    return;
}

sub getDevicesByGroup {
    my $hash = shift // return;
    my $data = shift // return;

    my $group = $data->{Group} // return;
    my $room  = $data->{Room}  // return;

    my $devices = {};

    for my $dev (keys %{$hash->{helper}{devicemap}{devices}}) {
        my $allrooms = $hash->{helper}{devicemap}{devices}{$dev}->{rooms};
        next if $room ne 'global' && $allrooms !~ m{\b$room\b}x;

        my $allgroups = $hash->{helper}{devicemap}{devices}{$dev}->{groups} // next;
        next if $allgroups !~ m{\b$group\b}x;

        my $specials = $hash->{helper}{devicemap}{devices}{$dev}{group_specials};
        my $label = $specials->{partOf} // $dev;
        next if defined $devices->{$label};

        my $delay = $specials->{async_delay} // 0;
        my $prio  = $specials->{prio} // 0;
        $devices->{$label} = { delay => $delay, prio => $prio };
    }
    return $devices;
}


# Mappings in Key/Value Paare aufteilen
sub splitMappingString {
    my $mapping = shift // return;
    my @tokens; my $token = q{};
    #my $char, 
    my $lastChar = q{};
    my $bracketLevel = 0;
    my %parsedMapping;

    # String in Kommagetrennte Tokens teilen
    for my $char ( split q{}, $mapping ) {
        if ($char eq q<{> && $lastChar ne '\\') {
            $bracketLevel += 1;
            $token .= $char;
        }
        elsif ($char eq q<}> && $lastChar ne '\\') {
            $bracketLevel -= 1;
            $token .= $char;
        }
        elsif ($char eq ',' && $lastChar ne '\\' && !$bracketLevel) {
            push(@tokens, $token);
            $token = q{};
        }
        else {
            $token .= $char;
        }

        $lastChar = $char;
    }
    push @tokens, $token if length $token > 2 && $token =~ m{=}xms;

    # Tokens in Keys/Values trennen
    %parsedMapping = map {split m{=}x, $_, 2} @tokens; #Beta-User: Odd number of elements in hash assignment

    return %parsedMapping;
}


# rhasspyMapping parsen und gefundene Settings zurückliefern
sub getMapping {
    my $hash       = shift // return;
    my $device     = shift // return;
    my $intent     = shift // return;
    my $type       = shift // $intent; #Beta-User: seems first three parameters are obligatory...?
    my $fromHash   = shift // 0;
    my $disableLog = shift // 0;

    my $subType = $type;
    if (ref $type eq 'HASH') {
        $subType = $type->{subType};
        $type = $type->{type};
    }

    my $matchedMapping;

    if ( $fromHash ) {
        $matchedMapping = $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$subType} if  defined $subType && defined $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$subType};
        return $matchedMapping if $matchedMapping;
        
        for (sort keys %{$hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}}) {
            #simply pick first item in alphabetical order...
            return $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$_};
        }
    }

    my $prefix = $hash->{prefix};
    my $mappingsString = AttrVal($device, "${prefix}Mapping", undef) // return;

    for (split m{\n}x, $mappingsString) {

        # Nur Mappings vom gesuchten Typ verwenden
        next if $_ !~ qr/^$intent/x;
        $_ =~ s/$intent://x;
        my %currentMapping = splitMappingString($_);

        # Erstes Mapping vom passenden Intent wählen (unabhängig vom Type), dann ggf. weitersuchen ob noch ein besserer Treffer mit passendem Type kommt
        if (!defined $matchedMapping 
            || lc($matchedMapping->{type}) ne lc($type) && lc($currentMapping{type}) eq lc($type)
            || $de_mappings->{ToEn}->{$matchedMapping->{type}} ne $type && $de_mappings->{ToEn}->{$currentMapping{type}} eq $type
            ) {
            $matchedMapping = \%currentMapping;
            #Beta-User: könnte man ergänzen durch den match "vorne" bei Reading, kann aber sein, dass es effektiver geht, wenn wir das künftig sowieso anders machen...

            Log3($hash->{NAME}, 5, "${prefix}Mapping selected: $_") if !$disableLog;
        }
    }
    return $matchedMapping;
}


# Cmd von Attribut mit dem Format value=cmd pro Zeile lesen
sub getKeyValFromAttr {
    my $hash       = shift // return;
    my $device     = shift;
    my $reading    = shift;
    my $key        = shift; #Beta-User: any necessary parameters...?
    my $disableLog = shift // 0;

    my $cmd;

    # String in einzelne Mappings teilen
    my @rows = split(m{\n}x, AttrVal($device, $reading, q{}));

    for (@rows) {
        # Nur Zeilen mit gesuchten Identifier verwenden
        next if $_ !~ qr/^$key=/ix;
        $_ =~ s{$key=}{}ix;
        $cmd = $_;

        Log3($hash->{NAME}, 5, "cmd selected: $_") if !$disableLog;
        last;
    }

    return $cmd;
}

# Cmd String im Format 'cmd', 'device:cmd', 'fhemcmd1; fhemcmd2' oder '{<perlcode}' ausführen
sub analyzeAndRunCmd {
    my $hash   = shift // return;
    my $device = shift;
    my $cmd    = shift;
    my $val    = shift; 
    my $siteId = shift // $hash->{defaultRoom};
    my $error;
    my $returnVal;
    $siteId = $hash->{defaultRoom} if $siteId eq 'default';

    Log3($hash->{NAME}, 5, "analyzeAndRunCmd called with command: $cmd");

    # Perl Command
    if ($cmd =~ m{\A\s*\{.*\}\s*\z}x) { #escaping closing bracket for editor only
        # CMD ausführen
        Log3($hash->{NAME}, 5, "$cmd is a perl command");
        return perlExecute($hash, $device, $cmd, $val,$siteId);
    }

    # String in Anführungszeichen (mit ReplaceSetMagic)
    if ($cmd =~ m{\A\s*"(?<inner>.*)"\s*\z}x) {
        my $DEVICE = $device;
        my $ROOM   = $siteId;
        my $VALUE  = $val;

        Log3($hash->{NAME}, 5, "$cmd has quotes...");

        # Anführungszeichen entfernen
        $cmd = $+{inner} // q{};

        # Variablen ersetzen?
        if ( !eval { $cmd =~ s{(\$\w+)}{$1}eegx; 1 } ) {
            Log3($hash->{NAME}, 1, "$cmd returned Error: $@");
            return;
        }
        # [DEVICE:READING] Einträge ersetzen
        $returnVal = _ReplaceReadingsVal($hash, $cmd);
        # Escapte Kommas wieder durch normale ersetzen
        $returnVal =~ s{\\,}{,}x;
        Log3($hash->{NAME}, 5, "...and is now: $cmd ($returnVal)");
    }
    # FHEM Command oder CommandChain
    elsif (defined $cmds{ (split m{\s+}x, $cmd)[0] }) {
        #my @test = split q{ }, $cmd;
        Log3($hash->{NAME}, 5, "$cmd is a FHEM command");
        $error = AnalyzeCommandChain($hash, $cmd);
        $returnVal = (split m{\s+}x, $cmd)[1];
    }
    # Soll Command auf anderes Device umgelenkt werden?
    elsif ($cmd =~ m{:}x) {
    $cmd   =~ s{:}{ }x;
        $cmd   = qq($cmd $val) if defined($val);
        Log3($hash->{NAME}, 5, "$cmd redirects to another device");
        $error = AnalyzeCommand($hash, "set $cmd");
        $returnVal = (split q{ }, $cmd)[1];
    }
    # Nur normales Cmd angegeben
    else {
        $cmd   = qq($device $cmd);
        $cmd   = qq($cmd $val) if defined $val;
        Log3($hash->{NAME}, 5, "$cmd is a normal command");
        $error = AnalyzeCommand($hash, "set $cmd");
        $returnVal = (split q{ }, $cmd)[1];
    }
    Log3($hash->{NAME}, 1, $_) if defined $error;

    return $returnVal;
}


# Wert über Format 'reading', 'device:reading' oder '{<perlcode}' lesen
sub _getValue {
    my $hash      = shift // return;
    my $device    = shift // return;
    my $getString = shift // return;
    my $val       = shift;
    my $siteId    = shift;
    
    # Perl Command oder in Anführungszeichen? -> Umleiten zu analyzeAndRunCmd
    if ($getString =~ m{\A\s*\{.*\}\s*\z}x || $getString =~ m{\A\s*".*"\s*\z}x) {
        return analyzeAndRunCmd($hash, $device, $getString, $val, $siteId);
    }

    # Soll Reading von einem anderen Device gelesen werden?
    if ($getString =~ m{:}x) {
        $getString =~ s{\[([^]]+)]}{$1}x; #remove brackets
        my @replace = split m{:}x, $getString;
        $device = $replace[0];
        $getString = $replace[1] // $getString;
        return ReadingsVal($device, $getString, 0);
    }

    # If it's only a string without quotes, return string for TTS
    #return ReadingsVal($device, $getString, $getString);
    return ReadingsVal($device, $getString, $getString);
}


# Zustand eines Gerätes über GetOnOff Mapping abfragen
sub _getOnOffState {
    my $hash     = shift // return;
    my $device   = shift // return; 
    my $mapping  = shift // return;
    
    my $valueOn  = $mapping->{valueOn};
    my $valueOff = $mapping->{valueOff};
    my $value    = lc(_getValue($hash, $device, $mapping->{currentVal}));

    # Entscheiden ob $value 0 oder 1 ist
    if ( defined $valueOff ) {
        $value eq lc($valueOff) ? return 0 : return 1;
    } 
    if ( defined $valueOn ) {
        $value eq lc($valueOn) ? return 1 : return 0;
    } 

    # valueOn und valueOff sind nicht angegeben worden, alles außer "off" wird als eine 1 gewertet
    return $value eq 'off' ? 0 : 1;
}


# JSON parsen
sub parseJSONPayload {
    my $hash = shift;
    my $json = shift // return;
    my $data;
    my $cp = $hash->{encoding} // q{UTF-8};

    # JSON Decode und Fehlerüberprüfung
    my $decoded;
    if ( !eval { $decoded  = decode_json(encode($cp,$json)) ; 1 } ) {
        return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
    }

    # Standard-Keys auslesen
    ($data->{intent} = $decoded->{intent}{intentName}) =~ s{\A.*.:}{}x if exists $decoded->{intent}{intentName};
    $data->{probability} = $decoded->{intent}{confidenceScore}         if exists $decoded->{intent}{confidenceScore};
    for my $key (qw(sessionId siteId input rawInput customData)) {
        $data->{$key} = $decoded->{$key} if exists $decoded->{$key};
    }
    #$data->{sessionId}   = $decoded->{sessionId}                       if exists $decoded->{sessionId};
    #$data->{siteId}      = $decoded->{siteId}                          if exists $decoded->{siteId};
    #$data->{input}      = $decoded->{input}                           if exists $decoded->{input};
    #$data->{rawInput}   = $decoded->{rawInput}                        if exists $decoded->{rawInput};
    #$data->{customData} = $decoded->{custom_data}                     if exists $decoded->{custom_data};

    # Überprüfen ob Slot Array existiert
    if (exists $decoded->{slots}) {
        # Key -> Value Paare aus dem Slot Array ziehen
        for my $slot (@{$decoded->{slots}}) { 
            my $slotName = $slot->{slotName};
            my $slotValue;

            $slotValue = $slot->{value}{value} if exists $slot->{value}{value} && $slot->{value}{value} ne '';#Beta-User: dismiss effectively empty fields
            $slotValue = $slot->{value} if exists $slot->{entity} && $slot->{entity} eq 'rhasspy/duration';

            $data->{$slotName} = $slotValue;
        }
    }

    for (keys %{ $data }) {
        my $value = $data->{$_};
        Log3($hash->{NAME}, 5, "Parsed value: $value for key: $_") if defined $value;
    }

    return $data;
}

# Call von IODev-Dispatch (e.g.MQTT2)
sub Parse {
    my $iodev = shift // carp q[No IODev provided!] && return;
    my $msg   = shift // carp q[No message to analyze!] && return;

    my $ioname = $iodev->{NAME};
    $msg =~ s{\Aautocreate=([^\0]+)\0(.*)\z}{$2}sx;
    my ($cid, $topic, $value) = split m{\0}xms, $msg, 3;
    my @ret=();
    my $forceNext = 0;
    my $shorttopic = $topic =~ m{([^/]+/[^/]+/)}x ? $1 : return q{[NEXT]};
    
    return q{[NEXT]} if !grep( { m{\A$shorttopic}x } @topics);
    
    my @instances = devspec2array('TYPE=RHASSPY');

    for my $dev (@instances) {
        my $hash = $defs{$dev};
        # Name mit IODev vergleichen
        next if $ioname ne AttrVal($hash->{NAME}, 'IODev', ReadingsVal($hash->{NAME}, 'IODev', InternalVal($hash->{NAME}, 'IODev', 'none')));
        next if IsDisabled( $hash->{NAME} );
        my $topicpart = qq{/$hash->{LANGUAGE}\.$hash->{fhemId}\[._]|hermes/dialogueManager};
        next if $topic !~ m{$topicpart}x;

        Log3($hash,5,"RHASSPY: [$hash->{NAME}] Parse (IO: ${ioname}): Msg: $topic => $value");

        my $fret = analyzeMQTTmessage($hash, $topic, $value);
        next if !defined $fret;
        if( ref $fret eq 'ARRAY' ) {
          push (@ret, @{$fret});
          $forceNext = 1 if AttrVal($hash->{NAME},'forceNEXT',0);
        } else {
          Log3($hash->{NAME},5,"RHASSPY: [$hash->{NAME}] Parse: internal error:  onmessage returned an unexpected value: ".$fret);  
        }
    }
    unshift(@ret, '[NEXT]') if !(@ret) || $forceNext;
    #Log3($iodev, 4, "Parse collected these devices: ". join q{ },@ret);
    return @ret;
}

# Update the readings lastIntentPayload and lastIntentTopic
# after and intent is received
sub updateLastIntentReadings {
    my $hash  = shift;
    my $topic = shift;
    my $data  = shift // return;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'lastIntentTopic', $topic);
    readingsBulkUpdate($hash, 'lastIntentPayload', toJSON($data));
    readingsEndUpdate($hash, 1);
    return;
}


#Make globally available to allow later use by other functions, esp.  handleIntentConfirmAction
my $dispatchFns = {
    Shortcuts       => \&handleIntentShortcuts, 
    SetOnOff        => \&handleIntentSetOnOff,
    SetOnOffGroup   => \&handleIntentSetOnOffGroup,
    GetOnOff        => \&handleIntentGetOnOff,
    SetNumeric      => \&handleIntentSetNumeric,
    SetNumericGroup => \&handleIntentSetNumericGroup,
    GetNumeric      => \&handleIntentGetNumeric,
    GetState        => \&handleIntentGetState,
    MediaControls   => \&handleIntentMediaControls,
    MediaChannels   => \&handleIntentMediaChannels,
    SetColor        => \&handleIntentSetColor,
    SetColorGroup   => \&handleIntentSetColorGroup,
    SetScene        => \&handleIntentSetScene,
    GetTime         => \&handleIntentGetTime,
    GetWeekday      => \&handleIntentGetWeekday,
    SetTimer        => \&handleIntentSetTimer,
    ConfirmAction   => \&handleIntentConfirmAction,
    CancelAction    => \&handleIntentCancelAction,
    ChoiceRoom      => \&handleIntentChoiceRoom,
    ChoiceDevice    => \&handleIntentChoiceDevice,
    ReSpeak         => \&handleIntentReSpeak
};


# Daten vom MQTT Modul empfangen -> Device und Room ersetzen, dann erneut an NLU übergeben
sub analyzeMQTTmessage {
    my $hash    = shift;# // return;
    my $topic   = shift;# // carp q[No topic provided!]   && return;
    my $message = shift;# // carp q[No message provided!] && return;;
    
    my $data    = parseJSONPayload($hash, $message);
    my $fhemId  = $hash->{fhemId};

    my $input = $data->{input};
    
    my $device;
    my @updatedList;

    my $type      = $data->{type} // q{text};
    my $sessionId = $data->{sessionId};
    my $siteId    = $data->{siteId};
    my $mute = 0;
    
    if (defined $siteId) {
        my $reading = makeReadingName($siteId);
        $mute = ReadingsNum($hash->{NAME},"mute_$reading",0);
    }

    # Hotword detection
    if ($topic =~ m{\Ahermes/dialogueManager}x) {
        my $room = getRoomName($hash, $data);

        return if !defined $room;
        my $mutated_vowels = $hash->{helper}{lng}->{mutated_vowels};
        if (defined $mutated_vowels) {
            for (keys %{$mutated_vowels}) {
                $room =~ s{$_}{$mutated_vowels->{$_}}gx;
            }
        }

        if ( $topic =~ m{sessionStarted}x ) {
            readingsSingleUpdate($hash, "listening_" . makeReadingName($room), 1, 1);
        } elsif ( $topic =~ m{sessionEnded}x ) {
            readingsSingleUpdate($hash, 'listening_' . makeReadingName($room), 0, 1);
        }
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($topic =~ m{\Ahermes/intent/.*[:_]SetMute}x && defined $siteId) {
        $type = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
        $data->{requestType} = $type;

        # update Readings
        updateLastIntentReadings($hash, $topic,$data);
        handleIntentSetMute($hash, $data);
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($mute) {
        $data->{requestType} = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
        respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, q{ });
        #Beta-User: Da fehlt mir der Soll-Ablauf für das "room-listening"-Reading; das wird ja über einen anderen Topic abgewickelt
        return \@updatedList;
    }

    my $command = $data->{input};
    $type = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
    $data->{requestType} = $type;
    my $intent = $data->{intent};

    # update Readings
    updateLastIntentReadings($hash, $topic,$data);

    # Passenden Intent-Handler aufrufen
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data);
    } else {
        $device = handleCustomIntent($hash, $intent, $data);
    }

    my $name = $hash->{NAME};
    $device = $device // $name;
    $device .= ",$name" if $device !~ m{$name}x;
    my @candidates = split m{,}x, $device;
    for (@candidates) {
        push @updatedList, $_ if $defs{$_}; 
    }

    return \@updatedList;
}


# Antwort ausgeben
sub respond {
    my $hash      = shift // return;
    my $type      = shift // return;
    my $sessionId = shift // return;
    my $siteId    = shift // return;
    my $response  = shift // return;

    my $topic = q{endSession};

    my $sendData =  {
        sessionId => $sessionId,
        siteId    => $siteId
    };

    if (ref $response eq 'HASH') {
        #intentFilter
        $topic = q{continueSession};
        for my $key (keys %{$response}) {
            $sendData->{$key} = $response->{$key};
        }
    } else {
        $sendData->{text} = $response
    }

    my $json = toJSON($sendData);
    $response = $response->{response} if ref $response eq 'HASH' && defined $response->{response};
    readingsBeginUpdate($hash);
    $type eq 'voice' ?
        readingsBulkUpdate($hash, 'voiceResponse', $response)
      : readingsBulkUpdate($hash, 'textResponse', $response);
    readingsBulkUpdate($hash, 'responseType', $type);
    readingsEndUpdate($hash,1);
    IOWrite($hash, 'publish', qq{hermes/dialogueManager/$topic $json});
    Log3($hash->{NAME}, 5, "Response is: $response");
    return;
}


# Antworttexte festlegen
sub getResponse {
    my $hash = shift;
    my $identifier = shift // return 'Code error! No identifier provided for getResponse!' ;

    return getKeyValFromAttr($hash, $hash->{NAME}, 'response', $identifier) // $hash->{helper}{lng}->{responses}->{$identifier};
}


# Send text command to Rhasspy NLU
sub sendTextCommand {
    my $hash = shift // return;
    my $text = shift // return;
    
    my $data = {
         input => $text,
         sessionId => "$hash->{fhemId}.textCommand"
    };
    my $message = toJSON($data);

    # Send fake command, so it's forwarded to NLU
    # my $topic2 = "hermes/intent/FHEM:TextCommand";
    my $topic = q{hermes/nlu/query};
    
    return IOWrite($hash, 'publish', qq{$topic $message});
}


# Sprachausgabe / TTS über RHASSPY
sub sendSpeakCommand {
    my $hash = shift;
    my $cmd  = shift;
    
    my $sendData =  {
        id => '0',
        sessionId => '0'
    };
    if (ref $cmd eq 'HASH') {
        return 'speak with explicite params needs siteId and text as arguments!' if !defined $cmd->{siteId} || !defined $cmd->{text};
        $sendData->{siteId} =  $cmd->{siteId};
        $sendData->{text} =  $cmd->{text};
    } else {    #Beta-User: might need review, as parseParams is used by default...!
        my $siteId = 'default';
        my $text = $cmd;
        my($unnamedParams, $namedParams) = parseParams($cmd);

        if (defined $namedParams->{siteId} && defined $namedParams->{text}) {
            $sendData->{siteId} = $namedParams->{siteId};
            $sendData->{text} = $namedParams->{text};
        } else {
            return 'speak needs siteId and text as arguments!';
        }
    }
    my $json = toJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/tts/say $json});
}

# Send all devices, rooms, etc. to Rhasspy HTTP-API to update the slots
sub updateSlots {
    my $hash = shift // return;
    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};
    my $method   = q{POST};
    
    initialize_devicemap($hash);
    my $tweaks = $hash->{helper}{tweaks}->{updateSlots};
    my $noEmpty = !defined $tweaks || defined $tweaks->{noEmptySlots} && $tweaks->{noEmptySlots} != 1 ? 1 : 0;

    # Collect everything and store it in arrays
    my @devices   = getAllRhasspyNames($hash);
    my @rooms     = getAllRhasspyRooms($hash);
    my @channels  = getAllRhasspyChannels($hash);
    my @colors    = getAllRhasspyColors($hash);
    my @types     = getAllRhasspyTypes($hash);
    my @groups    = getAllRhasspyGroups($hash);
    my ($scenes,
        $scdevs)  = getAllRhasspyScenes($hash);
    my @shortcuts = keys %{$hash->{helper}{shortcuts}};

    if ($noEmpty) { 
        @devices    =  ('') if !@devices;
        @rooms     = ('') if !@rooms;
        @channels  = ('') if !@channels;
        @colors    = ('') if !@colors;
        @types     = ('') if !@types;
        @groups    = ('') if !@groups;
        #@shortcuts = ('') if !@shortcuts; # forum: https://forum.fhem.de/index.php/topic,119447.msg1157700.html#msg1157700
        #$scenes    = []   if !@{$scenes};
        #$scdevs    = []   if !@{$scdevs};
    }

    my $deviceData;
    my $url = q{/api/sentences};

    if (@shortcuts) {
        $deviceData =qq({"intents/${language}.${fhemId}.Shortcuts.ini":"[${language}.${fhemId}:Shortcuts]\\n);
        for (@shortcuts) {
            $deviceData = $deviceData . ($_) . '\n';
        }
        $deviceData = $deviceData . '"}';
        Log3($hash->{NAME}, 5, "Updating Rhasspy Sentences with data: $deviceData");
        _sendToApi($hash, $url, $method, $deviceData);
    }
    
    # If there are any devices, rooms, etc. found, create JSON structure and send it the the API
    return if !@devices && !@rooms && !@channels && !@types && !@groups;

    my $json;
    $deviceData = {};
    my $overwrite = defined $tweaks && defined $tweaks->{overwrite_all} ? $tweaks->{useGenericAttrs}->{overwrite_all} : 'true';
    $url = qq{/api/slots?overwrite_all=$overwrite};

    my @gdts = (qw(switch light media blind thermostat thermometer));
    my @aliases = ();
    my @mainrooms = ();

    if ($hash->{useGenericAttrs}) {
        for my $gdt (@gdts) {
            my @names = ();
            my @groupnames = ();
            my @devs = devspec2array("$hash->{devspec}");
            for my $device (@devs) {
                if (AttrVal($device, 'genericDeviceType', '') eq $gdt) {
                    push @names, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{names};
                    push @aliases, $hash->{helper}{devicemap}{devices}{$device}->{alias};
                    push @groupnames, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{groups} if defined $hash->{helper}{devicemap}{devices}{$device}->{groups};
                    push @mainrooms, (split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{rooms})[0];
                }
            }
            @names = get_unique(\@names);
            @names = ('') if !@names && $noEmpty;
            $deviceData->{qq(${language}.${fhemId}.Device-${gdt})} = \@names if @names;
            @groupnames = get_unique(\@groupnames);
            @groupnames = ('') if !@groupnames && $noEmpty;
            $deviceData->{qq(${language}.${fhemId}.Group-${gdt})} = \@groupnames if @groupnames;
        }
        @mainrooms = get_unique(\@mainrooms);
        @mainrooms = ('') if !@mainrooms && $noEmpty;
        $deviceData->{qq(${language}.${fhemId}.MainRooms)} = \@mainrooms if @mainrooms;
        @aliases = get_unique(\@aliases);
        @aliases = ('') if !@aliases && $noEmpty;
        $deviceData->{qq(${language}.${fhemId}.Aliases)} = \@aliases if @aliases;
    }

    for (qw(SetNumeric SetOnOff GetNumeric GetOnOff MediaControls GetState)) {
        my ($alias, $grps) = getAllRhasspyNamesAndGroupsByIntent($hash, $_);
        $deviceData->{qq(${language}.${fhemId}.Device-$_)} = $alias if @{$alias} || $noEmpty;
        $deviceData->{qq(${language}.${fhemId}.Group-$_)}  = $grps  if (@{$grps}  || $noEmpty) 
                                                                        && ( $_ eq 'SetOnOff' || $_ eq 'SetNumeric' );
    }


    my @allKeywords = uniq(@groups, @rooms, @devices);

    $deviceData->{qq(${language}.${fhemId}.Device)}        = \@devices if @devices;
    $deviceData->{qq(${language}.${fhemId}.Room)}          = \@rooms if @rooms;
    $deviceData->{qq(${language}.${fhemId}.MediaChannels)} = \@channels if @channels;
    $deviceData->{qq(${language}.${fhemId}.Color)}         = \@colors if @colors;
    $deviceData->{qq(${language}.${fhemId}.NumericType)}   = \@types if @types;
    $deviceData->{qq(${language}.${fhemId}.Group)}         = \@groups if @groups;
    $deviceData->{qq(${language}.${fhemId}.Scenes)}        = $scenes if @{$scenes};
    $deviceData->{qq(${language}.${fhemId}.Device-scene)}  = $scdevs if @{$scdevs};
    $deviceData->{qq(${language}.${fhemId}.AllKeywords)}   = \@allKeywords if @allKeywords;
    
    $json = eval { toJSON($deviceData) };

    Log3($hash->{NAME}, 5, "Updating Rhasspy Slots with data ($language): $json");

    _sendToApi($hash, $url, $method, $json);
    return;
}

# Send all devices, rooms, etc. to Rhasspy HTTP-API to update the slots
sub updateSingleSlot {
    my $hash     = shift // return;
    my $slotname = shift // return;
    my $slotdata = shift // return;
    my $overwr   = shift // q{true};
    my $training = shift;
    $overwr = q{false} if $overwr ne 'true';
    my @data = split m{,}xms, $slotdata;
    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};
    my $method   = q{POST};
    
    my $url = qq{/api/slots?overwrite_all=$overwr};

    my $deviceData->{qq(${language}.${fhemId}.$slotname)} = \@data;

    my $json = eval { toJSON($deviceData) };

    Log3($hash->{NAME}, 5, "Updating Rhasspy single slot with data ($language): $json");

    _sendToApi($hash, $url, $method, $json);
    return trainRhasspy($hash) if $training;

    return;
}

# Use the HTTP-API to instruct Rhasspy to re-train it's data
sub trainRhasspy {
    my $hash = shift // return;
    my $url         = q{/api/train};
    my $method      = q{POST};
    my $contenttype = q{application/json};

    Log3($hash->{NAME}, 5, 'Starting training on Rhasspy');
    return _sendToApi($hash, $url, $method, undef);
}

# Use the HTTP-API to fetch all available siteIds
sub fetchSiteIds {
    my $hash   = shift // return;
    my $url    = q{/api/profile?layers=profile};
    my $method = q{GET};

    Log3($hash->{NAME}, 5, 'fetchSiteIds called');
    return _sendToApi($hash, $url, $method, undef);
}
    
=pod
# Check connection to HTTP-API
# Seems useless, because fetchSiteIds is called after DEF
sub RHASSPY_checkHttpApi {
    my $hash   = shift // return;
    my $url    = q{/api/unknown-words};
    my $method = q{GET};

    Log3($hash->{NAME}, 5, "check connection to Rhasspy HTTP-API");
    return _sendToApi($hash, $url, $method, undef);
}
=cut

# Send request to HTTP-API of Rhasspy
sub _sendToApi {
    my $hash   = shift // return;
    my $url    = shift;
    my $method = shift;
    my $data   = shift;
    my $base   = $hash->{baseUrl}; #AttrVal($hash->{NAME}, 'rhasspyMaster', undef) // return;

    #Retrieve URL of Rhasspy-Master from attribute
    $url = $base.$url;

    my $apirequest = {
        url        => $url,
        hash       => $hash,
        timeout    => 120,
        method     => $method,
        data       => $data,
        header     => 'Content-Type: application/json',
        callback   => \&RHASSPY_ParseHttpResponse
    };

    HttpUtils_NonblockingGet($apirequest);
    return;
}

# Parse the response of the request to the HTTP-API
sub RHASSPY_ParseHttpResponse {
    my $param = shift // return;
    my $err   = shift;
    my $data  = shift;
    my $hash  = $param->{hash};
    my $url   = lc $param->{url};

    my $name  = $hash->{NAME};
    my $base  = $hash->{baseUrl}; #AttrVal($name, 'rhasspyMaster', undef) // return;
    my $cp    = $hash->{encoding} // q{UTF-8};

    readingsBeginUpdate($hash);

    if ($err) {
        readingsBulkUpdate($hash, 'state', $err);
        readingsEndUpdate($hash, 1);
        Log3($hash->{NAME}, 1, "Connection to Rhasspy base failed: $err");
        return;
    }

    my $urls = { 
        $base.'/api/train'                      => 'training',
        $base.'/api/sentences'                  => 'updateSentences',
        $base.'/api/slots?overwrite_all=true'   => 'updateSlots'
    };

    if ( defined $urls->{$url} ) {
        readingsBulkUpdate($hash, $urls->{$url}, $data);
        if ( $urls->{$url} eq 'updateSlots' && $hash->{'.needTraining'} ) {
            trainRhasspy($hash);
            delete $hash->{'.needTraining'};
        }
    }
    elsif ( $url =~ m{api/profile}ix ) {
        my $ref; 
        if ( !eval { $ref = decode_json($data) ; 1 } ) {
            readingsEndUpdate($hash, 1);
            return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
        }
        #my $ref = decode_json($data);
        my $siteIds = encode($cp,$ref->{dialogue}{satellite_site_ids});
        readingsBulkUpdate($hash, 'siteIds', $siteIds);
    }
    else {
        Log3($name, 3, qq(error while requesting $param->{url} - $data));
    }
    readingsBulkUpdate($hash, 'state', 'online');
    readingsEndUpdate($hash, 1);
    return;
}


# Eingehender Custom-Intent
sub handleCustomIntent {
    my $hash       = shift // return;
    my $intentName = shift;
    my $data       = shift;
   
    if ( !defined $hash->{helper}{custom} || !defined $hash->{helper}{custom}{$intentName} ) {
        Log3($hash->{NAME}, 2, "handleIntentCustomIntent called with invalid $intentName key");
        return;
    }
    my $custom = $hash->{helper}{custom}{$intentName};
    Log3($hash->{NAME}, 5, "handleCustomIntent called with $intentName key");
   
    my ($intent, $response, $room);

    if ( exists $data->{Device} ) {
      $room = getRoomName($hash, $data);
      $data->{Device} = getDeviceByName($hash, $room, $data->{Device}); #Beta-User: really...?
    }

    my $subName = $custom->{function};
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'DefaultError')) if !defined $subName;

    my $params = $custom->{args};
    my @rets = @{$params};

    for (@rets) {
        if ($_ eq 'NAME') {
            $_ = qq{"$hash->{NAME}"};
        } elsif ($_ eq 'DATA') {
            my $json = toJSON($data);
            $_ = qq{'$json'};
        } elsif (defined $data->{$_}) {
            $_ = qq{"$data->{$_}"};
        } else {
            $_ = "undef";
        }
    }

    my $args = join q{,}, @rets;
    my $cmd = qq{ $subName( $args ) };
    Log3($hash->{NAME}, 5, "Calling sub: $cmd" );
    my $error = AnalyzePerlCommand($hash, $cmd);
    my $timeout = _getDialogueTimeout($hash);

    if ( ref $error eq 'ARRAY' ) {
        $response = ${$error}[0] // getResponse($hash, 'DefaultConfirmation');
        if ( ref ${$error}[0] eq 'HASH') {
            $timeout = ${$error}[1] if looks_like_number( ${$error}[1] );
            return setDialogTimeout($hash, $data, $timeout, ${$error}[0]);
        }
        respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        return ${$error}[1]; #comma separated list of devices to trigger
    } elsif ( ref $error eq 'HASH' ) {
        return setDialogTimeout($hash, $data, $timeout, $error);
    } else {
        $response = $error; # if $error && $error !~ m{Please.define.*first}x;
    }

    $response = getResponse($hash, 'DefaultConfirmation') if !defined $response;

    # Antwort senden
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incoming "SetMute" intents
sub handleIntentSetMute {
    my $hash = shift // return;
    my $data = shift // return;
    my $response;
    
    Log3($hash->{NAME}, 5, "handleIntentSetMute called");
    
    if ( exists $data->{Value} && exists $data->{siteId} ) {
        my $siteId = makeReadingName($data->{siteId});
        readingsSingleUpdate($hash, "mute_$siteId", $data->{Value} eq 'on' ? 1 : 0, 1);
        $response = getResponse($hash, 'DefaultConfirmation');
    }
    $response = $response  // getResponse($hash, 'DefaultError');
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}

# Handle custom Shortcuts
sub handleIntentShortcuts {
    my $hash = shift // return;
    my $data = shift // return;
    my $cfdd = shift // 0;
    
    my $shortcut = $hash->{helper}{shortcuts}{$data->{input}};
    Log3($hash->{NAME}, 5, "handleIntentShortcuts called with $data->{input} key");
    
    my $response;
    if ( defined $hash->{helper}{shortcuts}{$data->{input}}{conf_timeout} && !$data->{Confirmation} ) {
        my $timeout = $hash->{helper}{shortcuts}{$data->{input}}{conf_timeout};
        $response = $hash->{helper}{shortcuts}{$data->{input}}{conf_req};
        return setDialogTimeout($hash, $data, $timeout, $response);
    }
    $response = $shortcut->{response} // getResponse($hash, 'DefaultConfirmation');
    my $ret;
    my $device = $shortcut->{NAME};
    my $cmd    = $shortcut->{perl};

    my $self   = $hash->{NAME};
    my $name   = $shortcut->{NAME} // $self;
    my %specials = (
         '$DEVICE' => $name,
         '$SELF'   => $self,
         '$NAME'   => $name
        );

    if ( defined $cmd ) {
        Log3($hash->{NAME}, 5, "Perl shortcut identified: $cmd, device name is $name");

        $cmd  = _replace($hash, $cmd, \%specials);
        #execute Perl command
        $cmd = qq({$cmd}) if ($cmd !~ m{\A\{.*\}\z}x); 

        $ret = analyzeAndRunCmd($hash, undef, $cmd, undef, $data->{siteId});
        $device = $ret if $ret && $ret !~ m{Please.define.*first}x;

        $response = $ret // _replace($hash, $response, \%specials);
    } elsif ( defined $shortcut->{fhem} ) {
        $cmd = $shortcut->{fhem} // return;
        Log3($hash->{NAME}, 5, "FHEM shortcut identified: $cmd, device name is $name");
        $cmd      = _replace($hash, $cmd, \%specials);
        $response = _replace($hash, $response, \%specials);
        AnalyzeCommand($hash, $cmd);
    }
    $response = _ReplaceReadingsVal( $hash, $response );
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    # update Readings
    #updateLastIntentReadings($hash, $topic,$data);

    return $device;
}

# Handle incoming "SetOnOff" intents
sub handleIntentSetOnOff {
    my $hash = shift // return;
    my $data = shift // return;
    my ($value, $numericValue, $device, $room, $siteId, $mapping, $response);

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Device AND Value must exist
    if ( exists $data->{Device} && exists $data->{Value} ) {
        $room = getRoomName($hash, $data);
        $value = $data->{Value};
        $value = $value eq $de_mappings->{on} ? 'on' : $value; #Beta-User: compability
        $device = getDeviceByName($hash, $room, $data->{Device});
        $mapping = getMapping($hash, $device, 'SetOnOff', undef, defined $hash->{helper}{devicemap});

        # Mapping found?
        if ( defined $device && defined $mapping ) {
            my $cmdOn  = $mapping->{cmdOn} // 'on';
            my $cmdOff = $mapping->{cmdOff} // 'off';
            my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;

            # execute Cmd
            analyzeAndRunCmd($hash, $device, $cmd);
            Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

            # Define response
            if ( defined $mapping->{response} ) { 
                $numericValue = $value eq 'on' ? 1 : 0;
                $response = _getValue($hash, $device, $mapping->{response}, $numericValue, $room); 
                Log3($hash->{NAME}, 5, "Response is $response" );
            }
            else { $response = getResponse($hash, 'DefaultConfirmation'); }
        }
    }
    # Send response
    $response = $response  // getResponse($hash, 'DefaultError');
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}

sub handleIntentSetOnOffGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetOnOffGroup called");

    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData')) if !defined $data->{Value}; 

    my $devices = getDevicesByGroup($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};
        
    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound')) if !keys %{$devices}; 

    my $delaysum = 0;
    
    my $value = $data->{Value};
    $value = $value eq $de_mappings->{on} ? 'on' : $value;

    my $updatedList;

    my $init_delay = 0;
    my $needs_sorting = (@{$hash->{".asyncQueue"}});

    for my $device (@devlist) {
        my $mapping = getMapping($hash, $device, 'SetOnOff', undef, defined $hash->{helper}{devicemap});

        # Mapping found?
        next if !defined $mapping;
        
        my $cmdOn  = $mapping->{cmdOn} // 'on';
        my $cmdOff = $mapping->{cmdOff} // 'off';
        my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;

        # execute Cmd
        if ( !$delaysum ) {
            analyzeAndRunCmd($hash, $device, $cmd);
            Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );
            $delaysum += $devices->{$device}->{delay};
            $updatedList = $updatedList ? "$updatedList,$device" : $device;
        } else {
            my $hlabel = $devices->{$device}->{delay};
            push @{$hash->{".asyncQueue"}}, {device => $device, cmd => $cmd, prio => $devices->{$device}->{prio}, delay => $hlabel};
            InternalTimer(time+$delaysum,\&RHASSPY_asyncQueue,$hash,0) if !$init_delay;
            $init_delay = 1;
        }
    }

    _sortAsyncQueue($hash) if $init_delay && $needs_sorting;

    # Send response
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'DefaultConfirmation'));
    return $updatedList;
}

# Handle incomint GetOnOff intents
sub handleIntentGetOnOff {
    my $hash = shift // return;
    my $data = shift // return;
    my $device;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    # Device AND Status must exist
    if ( exists $data->{Device}  && exists $data->{State} ) {
        my $room = getRoomName($hash, $data);
        $device = getDeviceByName($hash, $room, $data->{Device});
        my $deviceName = $data->{Device};
        my $mapping;
        $mapping = getMapping($hash, $device, 'GetOnOff', undef, defined $hash->{helper}{devicemap}, 0) if defined $device;
        my $status = $data->{State};

        # Mapping found?
        if ( defined $mapping ) {
            # Device on or off?
            my $value = _getOnOffState($hash, $device, $mapping);

            # Define reponse
            if ( defined $mapping->{response} ) { 
                $response = _getValue($hash, $device, $mapping->{response}, $value, $room); 
            }
            else {
                my $stateResponseType = $internal_mappings->{stateResponseType}->{$status} // $de_mappings->{stateResponseType}->{$status};
                $response = $hash->{helper}{lng}->{stateResponses}{$stateResponseType}->{$value};
                $response =~ s{(\$\w+)}{$1}eegx;
            }
        }
    }
    # Send response
    $response = getResponse($hash, 'DefaultError')  if !defined $response;
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


sub isValidData {
    my $data = shift // return 0;
    my $validData = 0;
    
    $validData = 1 if exists $data->{Device} && ( exists $data->{Value} || exists $data->{Change}) #);

    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    #|| exists $data->{Device} && exists $data->{Change}
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    #|| !exists $data->{Device} && defined $data->{Change} 
    #    && defined $hash->{helper}{lng}->{regex}->{$data->{Change}}
    || !exists $data->{Device} && defined $data->{Change} 
        && (defined $internal_mappings->{Change}->{$data->{Change}} ||defined $de_mappings->{ToEn}->{$data->{Change}})
        #$data->{Change}=  =~ m/^(lauter|leiser)$/i);


    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    #||!exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && $data->{Type} =~ 
    #m{\A$hash->{helper}{lng}->{Change}->{regex}->{volume}\z}xim;
    || !exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && ( $data->{Type} eq 'volume' || $data->{Type} eq 'Lautstärke' );

    return $validData;
}

sub handleIntentSetNumericGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentSetNumericGroup called');

    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData')) if !exists $data->{Value} && !exists $data->{Change}; 

    my $devices = getDevicesByGroup($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};

    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound')) if !keys %{$devices}; 

    my $delaysum = 0;

    my $value = $data->{Value};
    $value = $value eq $de_mappings->{on} ? 'on' : $value;

    my $updatedList;

    my $init_delay = 0;
    my $needs_sorting = (@{$hash->{'.asyncQueue'}});

    for my $device (@devlist) {
        my $tempdata = $data;
        $tempdata->{'.DevName'} = $device;
        $tempdata->{'.inBulk'} = 1;
        
        # execute Cmd
        if ( !$delaysum ) {
            handleIntentSetNumeric($hash, $tempdata);
            Log3($hash->{NAME}, 5, "Running SetNumeric on device [$device]" );
            $delaysum += $devices->{$device}->{delay};
            $updatedList = $updatedList ? "$updatedList,$device" : $device;
        } else {
            my $hlabel = $devices->{$device}->{delay};
            push @{$hash->{'.asyncQueue'}}, {device => $device, SetNumeric => $tempdata, prio => $devices->{$device}->{prio}, delay => $hlabel};
            InternalTimer(time+$delaysum,\&RHASSPY_asyncQueue,$hash,0) if !$init_delay;
            $init_delay = 1;
        }
    }

    _sortAsyncQueue($hash) if $init_delay && $needs_sorting;

    # Send response
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'DefaultConfirmation'));
    return $updatedList;
}

# Eingehende "SetNumeric" Intents bearbeiten
sub handleIntentSetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $device = $data->{'.DevName'};
    #my $mapping;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    if ( !defined $device && !isValidData($data) ) {
        return if defined $data->{'.inBulk'};
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData'));
    }

    my $unit   = $data->{Unit};
    my $change = $data->{Change};
    my $type   = $data->{Type};
    if ( !defined $type && defined $change ){
        $type   = $internal_mappings->{Change}->{$change}->{Type} 
                // $internal_mappings->{Change}->{$de_mappings->{ToEn}->{$change}}->{Type};
    }
    my $value  = $data->{Value};
    my $room   = getRoomName($hash, $data);


    # Gerät über Name suchen, oder falls über Lautstärke ohne Device getriggert wurde das ActiveMediaDevice suchen
    if ( !defined $device && exists $data->{Device} ) {
        $device = getDeviceByName($hash, $room, $data->{Device});
    } elsif ( defined $type && ( $type eq 'volume' || $type eq 'Lautstärke' ) ) {
        $device = 
            getActiveDeviceForIntentAndType($hash, $room, 'SetNumeric', $type) 
            // return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoActiveMediaDevice'));
    }

    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound')) if !defined $device;

    my $mapping = getMapping($hash, $device, 'SetNumeric', $type, defined $hash->{helper}{devicemap}, 0);

    if ( !defined $mapping ) {
        if ( defined $data->{'.inBulk'} ) {
            #Beta-User: long forms to later add options to check upper/lower limits for pure on/off devices
            return;
        } else { 
           return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoMappingFound'));
        }
    }

    # Mapping and device found -> execute command
    my $cmd     = $mapping->{cmd} // return defined $data->{'.inBulk'} ? undef : respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoMappingFound'));
    my $part    = $mapping->{part};
    my $minVal  = $mapping->{minVal};
    my $maxVal  = $mapping->{maxVal};

    $minVal     =   0 if defined $minVal && !looks_like_number($minVal);
    $maxVal     = 100 if defined $maxVal && !looks_like_number($maxVal);
    my $checkMinMax = defined $minVal && defined $maxVal ? 1 : 0;

    my $diff    = $value // $mapping->{step} // 10;

    #my $up      = (defined($change) && ($change =~ m/^(höher|heller|lauter|wärmer)$/)) ? 1 : 0;
    my $up = $change;
    $up    = $internal_mappings->{Change}->{$change}->{up} 
          // $internal_mappings->{Change}->{$de_mappings->{ToEn}->{$change}}->{up}
          // defined $change && ($change =~ m{\A$internal_mappings->{regex}->{upward}\z}xi || $change =~ m{\A$de_mappings->{regex}->{upward}\z}xi ) ? 1 
           : 0;

    my $forcePercent = ( defined $mapping->{map} && lc $mapping->{map} eq 'percent' ) ? 1 : 0;

    # Alten Wert bestimmen
    my $oldVal  = _getValue($hash, $device, $mapping->{currentVal});

    if (defined $part) {
        my @tokens = split m{\s+}x, $oldVal;
        $oldVal = $tokens[$part] if @tokens >= $part;
    }

    # Neuen Wert bestimmen
    my $newVal;
    my $ispct = defined $unit && ( $unit eq 'percent' || $unit eq $de_mappings->{percent} ) ? 1 : 0;

    if ( !defined $change ) {
        # Direkter Stellwert ("Stelle Lampe auf 50")
        #if ($unit ne 'Prozent' && defined $value && !defined $change && !$forcePercent) {
        if ( !defined $value ) {
            #do nothing...
        } elsif ( !$ispct && !$forcePercent ) {
            $newVal = $value;
        } elsif ( ( $ispct || $forcePercent ) && $checkMinMax ) { 
            # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)
            #elsif (defined $value && ( defined $unit && $unit eq 'Prozent' || $forcePercent ) && !defined $change && defined $minVal && defined $maxVal) {

            # Wert von Prozent in Raw-Wert umrechnen
            $newVal = $value;
            #$newVal =   0 if ($newVal <   0);
            #$newVal = 100 if ($newVal > 100);
            $newVal = round((($newVal * (($maxVal - $minVal) / 100)) + $minVal), 0);
        }
    } else { # defined $change
        # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
        #elsif ((!defined $unit || $unit ne 'Prozent') && defined $change && !$forcePercent) {
        if ( ( !defined $unit || !$ispct ) && !$forcePercent ) {
            $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
        }
        # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
        #elsif (($unit eq 'Prozent' || $forcePercent) && defined($change)  && defined $minVal && defined $maxVal) {
        elsif ( ( $ispct || $forcePercent ) && $checkMinMax ) {
            #$maxVal = 100 if !looks_like_number($maxVal); #Beta-User: Workaround, should be fixed in mapping (tbd)
            #my $diffRaw = round((($diff * (($maxVal - $minVal) / 100)) + $minVal), 0);
            my $diffRaw = round(($diff * ($maxVal - $minVal) / 100), 0);
            $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
            $newVal = max( $minVal, min( $maxVal, $newVal ) );
        }
    }

    if ( !defined $newVal ) {
        return defined $data->{'.inBulk'} ? undef : respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoNewValDerived'));
    }

    # limit to min/max  (if set)
    $newVal = max( $minVal, $newVal ) if defined $minVal;
    $newVal = min( $maxVal, $newVal ) if defined $maxVal;

    # execute Cmd
    analyzeAndRunCmd($hash, $device, $cmd, $newVal);

    #venetian blind special
    my $specials = $hash->{helper}{devicemap}{devices}{$device}{venetian_specials};
    if ( defined $specials ) {
        my $vencmd = $specials->{setter} // $cmd;
        my $vendev = $specials->{device} // $device;
        analyzeAndRunCmd($hash, $vendev, defined $specials->{CustomCommand} ? $specials->{CustomCommand} :$vencmd , $newVal) if $device ne $vendev || $cmd ne $vencmd;
    }
                                                 
    # get response 
    defined $mapping->{response} 
        ? $response = _getValue($hash, $device, $mapping->{response}, $newVal, $room) 
        : $response = getResponse($hash, 'DefaultConfirmation'); 

    # send response
    $response = getResponse($hash, 'DefaultError') if !defined $response;
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response) if !defined $data->{'.inBulk'};
    return $device;
}


# Eingehende "GetNumeric" Intents bearbeiten
sub handleIntentGetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $value;

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type oder Device muss existieren
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'DefaultError')) if !exists $data->{Type} && !exists $data->{Device};

    my $type = $data->{Type};
    my $subType = $data->{subType} // $type;
    my $room = getRoomName($hash, $data);

    # Get suitable device
    my $device = exists $data->{Device}
        ? getDeviceByName($hash, $room, $data->{Device})
        : getDeviceByIntentAndType($hash, $room, 'GetNumeric', $type)
        // return respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound'));

    #more than one device 
    if (ref $device eq 'ARRAY') {
        #until now: only extended test code
        my $first = $device->[0];
        my $response = $device->[1];
        my $all = $device->[2];
        my $choice = $device->[3];
        my $toActivate = $choice eq 'RequestChoiceDevice' ? [qw(ChoiceDevice CancelAction)] : [qw(ChoiceRoom CancelAction)];
        $device = $first;
        Log3($hash->{NAME}, 5, "More than one device possible, response is $response, first is $first, all are $all, type is $choice");
        return setDialogTimeout($hash, $data, _getDialogueTimeout($hash), $response, $toActivate);
    }

    my $mapping = getMapping($hash, $device, 'GetNumeric', { type => $type, subType => $subType }, defined $hash->{helper}{devicemap}, 0)
        // return respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoMappingFound'));

    # Mapping found
    my $part = $mapping->{part};
    my $minVal  = $mapping->{minVal};
    my $maxVal  = $mapping->{maxVal};
    my $mappingType = $mapping->{type};
    my $forcePercent = defined $mapping->{map} && lc($mapping->{map}) eq 'percent' && defined $minVal && defined $maxVal ? 1 : 0;
    
    # Get value for response
    $value = _getValue($hash, $device, $mapping->{currentVal});
    if ( defined $part ) {
      my @tokens = split m{\s+}x, $value;
      $value = $tokens[$part] if @tokens >= $part;
    }
    $value = round( ($value * ($maxVal - $minVal) / 100 + $minVal), 0) if $forcePercent;

    my $isNumber = looks_like_number($value);
    # replace dot by comma if needed
    $value =~ s{\.}{\,}gx if $hash->{helper}{lng}->{commaconversion};

    my $location = $data->{Device};
    if ( !defined $location ) {
        my $rooms = $hash->{helper}{devicemap}{devices}{$device}->{rooms};
        $location = $data->{Room} if defined $data->{Room} && defined $rooms && $rooms =~ m{\b$data->{Room}\b}ix;

        #Beta-User: this might be the place to implement the "no device in room" branch
        ($location, my $nn) = split m{,}x, $rooms if !defined $location;
    }
    my $deviceName = $hash->{helper}{devicemap}{devices}{$device}->{alias} // $device;

    # Antwort falls Custom Response definiert ist
    if ( defined $mapping->{response} ) {
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, _getValue($hash, $device, $mapping->{response}, $value, $location));
    }
    my $responses = $hash->{helper}{lng}->{responses}->{Change};

    # Antwort falls mappingType oder type matched
    my $response = 
        $responses->{$mappingType}
        //  $responses->{$de_mappings->{ToEn}->{$mappingType}}
        //  $responses->{$type}
        //  $responses->{$de_mappings->{ToEn}->{$type}};
        $response = $response->{$isNumber} if ref $response eq 'HASH';

    # Antwort falls mappingType auf regex (en bzw. de) matched
    if (!defined $response && (
            $mappingType=~ m{\A$internal_mappings->{regex}->{setTarget}\z}xim 
            || $mappingType=~ m{\A$de_mappings->{regex}->{setTarget}\z}xim)) { 
        $response = $responses->{setTarget};
    }
    if (!defined $response) {
        #or not and at least know the type...?
        $response = defined $mappingType
            ? $responses->{knownType}
            : $responses->{unknownType};
    }

    # Variablen ersetzen?
    $response =~ s{(\$\w+)}{$1}eegx;
    # Antwort senden
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incoming "GetState" intents
sub handleIntentGetState {
    my $hash = shift // return;
    my $data = shift // return;
    my $device = $data->{Device} // return;
    my $response;

    Log3($hash->{NAME}, 5, 'handleIntentGetState called');

    # Mindestens Device muss existieren
    if (exists $data->{Device}) {
        my $room = getRoomName($hash, $data);
        $device = getDeviceByName($hash, $room, $device);
        my $mapping = getMapping($hash, $device, 'GetState', undef, defined $hash->{helper}{devicemap}, 0);

        if ( defined $mapping->{response} ) {
            $response = _getValue($hash, $device, $mapping->{response}, undef, $room);
            $response = _ReplaceReadingsVal($hash, $mapping->{response}) if !$response; #Beta-User: case: plain Text with [device:reading]
        }
    }
    # Antwort senden
    $response = getResponse($hash, 'DefaultError') if !defined $response;
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incomint "MediaControls" intents
sub handleIntentMediaControls {
    my $hash = shift // return;
    my $data = shift // return;
    my $command, my $device, my $room;
    my $mapping;
    my $response = getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentMediaControls called");

    # At least one command has to be received
    if (exists $data->{Command}) {
        $room = getRoomName($hash, $data);
        $command = $data->{Command};

        # Search for matching device
        if (exists $data->{Device}) {
            $device = getDeviceByName($hash, $room, $data->{Device});
        } else {
            $device = getActiveDeviceForIntentAndType($hash, $room, 'MediaControls', undef);
            $response = getResponse($hash, 'NoActiveMediaDevice') if !defined $device;
        }

        $mapping = getMapping($hash, $device, 'MediaControls', undef, defined $hash->{helper}{devicemap}, 0);

        if (defined $device && defined $mapping) {
            my $cmd = $mapping->{$command};

            #Beta-User: backwards compability check; might be removed later...
            if (!defined $cmd) {
                my $Media = { 
                    play => 'cmdPlay', pause => 'cmdPause', 
                    stop => 'cmdStop', vor => 'cmdFwd', next => 'cmdFwd',
                    'zurück' => 'cmdBack', previous => 'cmdBack'
                };
                $cmd = $mapping->{ $Media->{$command} } if defined $mapping->{ $Media->{$command} };
                Log3($hash->{NAME}, 4, "MediaControls with outdated mapping $command called. Please change to avoid future problems...");
            }

            else {
                # Execute Cmd
                analyzeAndRunCmd($hash, $device, $cmd);
                
                # Define voice response
                $response = defined $mapping->{response} ?
                     _getValue($hash, $device, $mapping->{response}, $command, $room)
                     : getResponse($hash, 'DefaultConfirmation');
            }
        }
    }
    # Send voice response
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}

# Handle incoming "SetScene" intents
sub handleIntentSetScene{
    my $hash = shift // return;
    my $data = shift // return;
    my ($scene, $device, $room, $siteId, $mapping, $response);

    Log3($hash->{NAME}, 5, "handleIntentSetScene called");
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData')) if !defined $data->{Scene};

    # Device AND Scene are optimum exist
    if ( !exists $data->{Device} ) {
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound'));
    } else {
        $room = getRoomName($hash, $data);
        $scene = $data->{Scene};
        $device = getDeviceByName($hash, $room, $data->{Device});
        $mapping = getMapping($hash, $device, 'SetScene', undef, defined $hash->{helper}{devicemap});

        # Mapping found?
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData')) if !$device || !defined $mapping;
        my $cmd = qq(scene $scene);

        # execute Cmd
        analyzeAndRunCmd($hash, $device, $cmd);
        Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

        # Define response
        $response = $mapping->{response} // getResponse($hash, 'DefaultConfirmation');
    }

    # Send response
    $response = $response  // getResponse($hash, 'DefaultError');
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}

# Handle incoming "GetTime" intents
sub handleIntentGetTime {
    my $hash = shift // return;
    my $data = shift // return;
    Log3($hash->{NAME}, 5, "handleIntentGetTime called");

    (my $sec,my $min,my $hour,my $mday,my $mon,my $year,my $wday,my $yday,my $isdst) = localtime;
    my $response = $hash->{helper}{lng}->{responses}->{timeRequest};
    $response =~ s{(\$\w+)}{$1}eegx;
    Log3($hash->{NAME}, 5, "Response: $response");

    # Send voice reponse
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incoming "GetWeekday" intents
sub handleIntentGetWeekday {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentGetWeekday called");

    my $weekDay  = strftime( '%A', localtime );
    my $response = $hash->{helper}{lng}->{responses}->{weekdayRequest};
    $response =~ s{(\$\w+)}{$1}eegx;
    
    Log3($hash->{NAME}, 5, "Response: $response");

    # Send voice reponse
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "MediaChannels" Intents bearbeiten
sub handleIntentMediaChannels {
    my $hash = shift // return;
    my $data = shift // return;
    my $channel; my $device; my $room;
    my $cmd;
    my $response; # = getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentMediaChannels called");

    # Mindestens Channel muss übergeben worden sein
    if ( exists $data->{Channel} ) {
        $room = getRoomName($hash, $data);
        $channel = $data->{Channel};

        # Passendes Gerät suchen
        if ( exists $data->{Device} ) {
            $device = getDeviceByName($hash, $room, $data->{Device});
        } else {
            $device = getDeviceByMediaChannel($hash, $room, $channel);
        }
        
        if (defined $hash->{helper}{devicemap}) {
            $cmd = $hash->{helper}{devicemap}{devices}{$device}{Channels}{$channel};
        }
        else {
            $cmd = getKeyValFromAttr($hash, $device, 'rhasspyChannels', $channel, undef);
        }
        #$cmd = (split m{=}x, $cmd, 2)[1];

        if ( defined $device && defined $cmd ) {
            $response = getResponse($hash, 'DefaultConfirmation');
            # Cmd ausführen
            analyzeAndRunCmd($hash, $device, $cmd);
        }
    }

    # Antwort senden
    $response = getResponse($hash, 'NoMediaChannelFound') if !defined $response;
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Handle incoming "SetColor" intents
sub handleIntentSetColor {
    my $hash = shift // return;
    my $data = shift // return;

    my $inBulk = $data->{'.inBulk'} // 0;
    my $device = $data->{'.DevName'};

    Log3($hash->{NAME}, 5, "handleIntentSetColor called");
    my $response;

    # At least Device AND Color have to be received
    if ( !exists $data->{Color} && !exists $data->{Rgb} &&!exists $data->{Saturation} && !exists $data->{Colortemp} && !exists $data->{Hue} || !exists $data->{Device} && !defined $device) {
        return if $inBulk;
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData')) ;
    }

    #if (exists $data->{Color} && exists $data->{Device}) {
    my $room = getRoomName($hash, $data);
    my $color = $data->{Color} // q{};

    # Search for matching device and command
    $device = getDeviceByName($hash, $room, $data->{Device}) if !defined $device;
    my $cmd = getKeyValFromAttr($hash, $device, 'rhasspyColors', $color, undef);
    my $cmd2;
    if (defined $hash->{helper}{devicemap}{devices}{$device}{color_specials}
        && defined $hash->{helper}{devicemap}{devices}{$device}{color_specials}->{CommandMap}) {
        $cmd2 = $hash->{helper}{devicemap}{devices}{$device}{color_specials}->{CommandMap}->{$color};
    }

    return if $inBulk && !defined $device;
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound')) if !defined $device;

    if ( defined $cmd || defined $cmd2 ) {
        $response = getResponse($hash, 'DefaultConfirmation');
        # Execute Cmd
        analyzeAndRunCmd( $hash, $device, defined $cmd ? $cmd : $cmd2 );
    } else {
        $response = _runSetColorCmd($hash, $device, $data, $inBulk);
    }
    # Send voice response
    $response = getResponse($hash, 'DefaultError') if !defined $response;
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response) if !$inBulk;
    return $device;
}

sub _runSetColorCmd {
    my $hash   = shift // return;
    my $device = shift // return;
    my $data   = shift // return;
    my $inBulk = shift // 0;

    my $color  = $data->{Color};
    
    my $mapping = $hash->{helper}{devicemap}{devices}{$device}{intents}{SetColorParms} // return $inBulk ?undef : respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoMappingFound'));

    my $error;

    #shortcuts: hue, sat or CT are directly addressed and possible commands
    my $keywords = {hue => 'Hue', sat => 'Saturation', ct => 'Colortemp'};
    for (keys %{$keywords}) {
        my $kw = $keywords->{$_};

        my $forceRgb = $hash->{helper}{devicemap}{devices}{$device}{color_specials}->{forceHue2rgb} // 0;
        next if defined $kw && $kw eq 'Hue' && $forceRgb == 1;

        my $specialmapping = $hash->{helper}{devicemap}{devices}{$device}{color_specials}{$kw};
        if (defined $data->{$kw} && defined $specialmapping && defined $specialmapping->{$data->{$kw}}) {
            my $cmd = $specialmapping->{$data->{$kw}};
            $error = AnalyzeCommand($hash, "set $device $cmd");
            return if $inBulk;
            Log3($hash->{NAME}, 5, "Setting $device to $cmd");
            return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $error) if $error;
            return getResponse($hash, 'DefaultConfirmation');
        } elsif ( defined $data->{$kw} && defined $mapping->{$_} ) {
            my $value = round( ($mapping->{$_}->{maxVal} - $mapping->{$_}->{minVal}) * $data->{$kw} / ($kw eq 'Hue' ? 360 : 100) , 0);
            $value = min(max($mapping->{$_}->{minVal}, $value), $mapping->{$_}->{maxVal});
            $error = AnalyzeCommand($hash, "set $device $mapping->{$_}->{cmd} $value");
            return if $inBulk;
            Log3($hash->{NAME}, 5, "Setting color to $value");
            return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $error) if $error;
            return getResponse($hash, 'DefaultConfirmation');
        }
    }

    #shortcut: Rgb field is used or color is in HEX value and rgb is a possible command
    if ( ( defined $data->{Rgb} || defined $color && $color =~ m{\A[[:xdigit:]]\z}x ) && defined $mapping->{rgb} ) {
        $color = $data->{Rgb} if defined $data->{Rgb};
        $error = AnalyzeCommand($hash, "set $device $mapping->{rgb}->{cmd} $color");
        return if $inBulk;
        Log3($hash->{NAME}, 5, "Setting rgb-color to $color");
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $error) if $error;
        return getResponse($hash, 'DefaultConfirmation');
    }

    #only matches, if there's no native hue command 
    if ( defined $data->{Hue} && defined $mapping->{rgb} ) {
        my $angle = int($data->{Hue} / 24)*15;
        my $angle2rgb = {
            # from https://en.wikipedia.org/wiki/Hue#24_hues_of_HSL/HSV
            # hue angle color code luminance
            0 => {rgb => 'FF0000' , brightness => '30'}, 
            15=> { rgb => 'FF4000', brightness => '45' },
            30=> { rgb => 'FF8000', brightness => '59' },
            45=> { rgb => 'FFBF00', brightness => '74' },
            60=> { rgb => 'FFFF00', brightness => '89' },
            75=> { rgb => 'BFFF00', brightness => '81' },
            90=> { rgb => '80FF00', brightness => '74' },
            105=> { rgb => '40FF00', brightness => '66' },
            120=> { rgb => '00FF00', brightness => '59' },
            135=> { rgb => '00FF40', brightness => '62' },
            150=> { rgb => '00FF80', brightness => '64' },
            165=> { rgb => '00FFBF', brightness => '67' },
            180=> { rgb => '00FFFF', brightness => '70' },
            195=> { rgb => '00BFFF', brightness => '55' },
            210=> { rgb => '0080FF', brightness => '41' },
            225=> { rgb => '0040FF', brightness => '26' },
            240=> { rgb => '0000FF', brightness => '11' },
            255=> { rgb => '4000FF', brightness => '19' },
            270=> { rgb => '8000FF', brightness => '26' },
            285=> { rgb => 'BF00FF', brightness => '34' },
            300=> { rgb => 'FF00FF', brightness => '41' },
            315=> { rgb => 'FF00BF', brightness => '38' },
            330=> { rgb => 'FF0080', brightness => '36' },
            345=> { rgb => 'FF0040', brightness => '33' }
        };
        my $rgb = $angle2rgb->{$angle}->{rgb};
        return "mapping problem in Hue2rgb" if !defined $rgb;
        my $rgbcmd = $mapping->{rgb}->{cmd}; 
        $rgb = lc $rgb if $rgbcmd eq 'hex';
        $error = AnalyzeCommand($hash, "set $device $rgbcmd $rgb");
        return if $inBulk;
        Log3($hash->{NAME}, 5, "Setting rgb-color to $rgb using hue");
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $error) if $error;
        return getResponse($hash, 'DefaultConfirmation');
    }

    if ( defined $data->{Colortemp} && defined $mapping->{rgb} && looks_like_number($data->{Colortemp}) ) {
        
        my $ct = $data->{Colortemp}*50 + 2000; #FHEMWIKI indicates typical range from 2000 to 6500
        my ($r, $g, $b) = _ct2rgb($ct);
        my $rgb = uc sprintf( "%2.2X%2.2X%2.2X", $r, $g, $b );

        return "mapping problem in _ct2rgb" if !defined $rgb;
        $error = AnalyzeCommand($hash, "set $device $mapping->{rgb}->{cmd} $rgb");
        return if $inBulk;
        Log3($hash->{NAME}, 5, "Setting color-temperature to $ct");
        return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $error) if $error;
        return getResponse($hash, 'DefaultConfirmation');
    }

    return if $inBulk;
    return getResponse($hash, 'NoMappingFound');
}

#clone from Color.pm
sub _ct2rgb { 
    my $ct = shift // return;

    # calculation from http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code

    # kelvin -> mired
    $ct = 1000000/$ct if( $ct > 1000 );

    # adjusted by 1000K
    my $temp = 10000/$ct + 10;

    my $r = 255;
    $r = 329.698727446 * ($temp - 60) ** -0.1332047592 if $temp > 66;
    $r = max( 0, min ( $r , 255 ) );
    
    my $g = $temp <= 66 ?
        99.4708025861 * log($temp) - 161.1195681661
        : 288.1221695283 * ($temp - 60) ** -0.0755148492;
    $g = max( 0, min ( $g , 255 ) );

    my $bl = $temp <= 19 ? 0 : 255;
    $bl = 138.5177312231 * log($temp-10) - 305.0447927307 if $temp < 66;
    $bl = max( 0, min ( $b , 255 ) );

    return( $r, $g, $bl );
}

sub handleIntentSetColorGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentSetColorGroup called');

    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoValidData')) if !exists $data->{Color} && !exists $data->{Rgb} &&!exists $data->{Saturation} && !exists $data->{Colortemp} && !exists $data->{Hue};

    my $devices = getDevicesByGroup($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};

    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'NoDeviceFound')) if !keys %{$devices}; 

    my $delaysum = 0;
    my $updatedList;
    my $init_delay = 0;
    my $needs_sorting = (@{$hash->{'.asyncQueue'}});

    for my $device (@devlist) {
        my $tempdata = $data;
        $tempdata->{'.DevName'} = $device;
        $tempdata->{'.inBulk'} = 1;

        # execute Cmd
        if ( !$delaysum ) {
            handleIntentSetColor($hash, $data);
            Log3($hash->{NAME}, 5, "Running SetColor on device [$device]" );
            $delaysum += $devices->{$device}->{delay};
            $updatedList = $updatedList ? "$updatedList,$device" : $device;
        } else {
            my $hlabel = $devices->{$device}->{delay};
            push @{$hash->{'.asyncQueue'}}, {device => $device, SetColor => $tempdata, prio => $devices->{$device}->{prio}, delay => $hlabel};
            InternalTimer(time+$delaysum,\&RHASSPY_asyncQueue,$hash,0) if !$init_delay;
            $init_delay = 1;
        }
    }

    _sortAsyncQueue($hash) if $init_delay && $needs_sorting;

    # Send response
    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'DefaultConfirmation'));
    return $updatedList;
}



# Handle incoming SetTimer intents
sub handleIntentSetTimer {
    my $hash = shift;
    my $data = shift // return;
    my $siteId = $data->{siteId} // return;
    my $name = $hash->{NAME};

    Log3($name, 5, 'handleIntentSetTimer called');

    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $hash->{helper}{lng}->{responses}->{duration_not_understood}) 
    if !defined $data->{Hourabs} && !defined $data->{Hour} && !defined $data->{Min} && !defined $data->{Sec} && !defined $data->{CancelTimer};

    my $room = getRoomName($hash, $data);

    my $hour = 0;
    my $value = time;
    my $now = $value;
    my @time = localtime($now);
    if ( defined $data->{Hourabs} ) {
        $hour  = $data->{Hourabs};
        $value = $value - ($time[2] * HOURSECONDS) - ($time[1] * MINUTESECONDS) - $time[0]; #last midnight
    }
    elsif ($data->{Hour}) {
        $hour = $data->{Hour};
    }
    $value += HOURSECONDS * $hour;
    $value += MINUTESECONDS * $data->{Min} if $data->{Min};
    $value += $data->{Sec} if $data->{Sec};

    my $tomorrow = 0;
    if ( $value < $now ) {
        $tomorrow = 1;
        $value += +DAYSECONDS;
    }

    my $siteIds = ReadingsVal( $name, 'siteIds',0);
    fetchSiteIds($hash) if !$siteIds;

    my $timerRoom = $siteId;

    my $responseEnd = $hash->{helper}{lng}->{responses}->{timerEnd}->{1};

    if ($siteIds =~ m{\b$room\b}ix) {
        $timerRoom = $room if $siteIds =~ m{\b$room\b}ix;
        $responseEnd = $hash->{helper}{lng}->{responses}->{timerEnd}->{0};
    }
    
    my $roomReading = "timer_".makeReadingName($room);
    my $label = $data->{Label} // q{};
    $roomReading .= "_$label" if $label ne ''; 

    my $response;
    if (defined $data->{CancelTimer}) {
        CommandDelete($hash, $roomReading);
        #readingsSingleUpdate( $hash,$roomReading, 0, 1 );
        readingsDelete($hash, $roomReading);
        Log3($name, 5, "deleted timer: $roomReading");
        $response = getResponse($hash, 'timerCancellation');
        $response =~ s{(\$\w+)}{$1}eegx;
        respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        return $name;
    }

    if( $value && $timerRoom ) {
        my $seconds = $value - $now;
        my $diff = $seconds;
        my $attime = strftime( '%H', gmtime $diff );
        $attime += 24 if $tomorrow;
        $attime .= strftime( ':%M:%S', gmtime $diff );
        my $readingTime = strftime( '%H:%M:%S', localtime (time + $seconds));

        $responseEnd =~ s{(\$\w+)}{$1}eegx;

        my $soundoption = $hash->{helper}{tweaks}{timerSounds}->{$label} // $hash->{helper}{tweaks}{timerSounds}->{default};
        #my $timerTrigger = $hash->{helper}{tweaks}->{timerTrigger};
        #my $addtrigger = defined $timerTrigger  && ( $timerTrigger eq 'default' || $timerTrigger =~ m{\b$label\b}x ) ? 
        #my $addtrigger = defined $timerTrigger && $label ne '' && $timerTrigger =~ m{\bdefault|$label\b}x ? 
        my $addtrigger =    qq{; trigger $name timerEnd $siteId $room};
        $addtrigger .= " $label" if defined $label;
        #    : q{};

        if ( !defined $soundoption ) {
            CommandDefMod($hash, "-temporary $roomReading at +$attime set $name speak siteId=\"$timerRoom\" text=\"$responseEnd\";deletereading $name ${roomReading}$addtrigger");
        } else {
            $soundoption =~ m{((?<repeats>[0-9]*)[:]){0,1}((?<duration>[0-9.]*)[:]){0,1}(?<file>(.+))}x;
            my $file = $+{file} // Log3($hash->{NAME}, 2, "no WAV file for $label provided, check attribute rhasspyTweaks (item timerSounds)!") && return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse($hash, 'DefaultError'));
            my $repeats = $+{repeats} // 5;
            my $duration = $+{duration} // 15;
            CommandDefMod($hash, "-temporary $roomReading at +$attime set $name play siteId=\"$timerRoom\" path=\"$file\" repeats=$repeats wait=$duration id=${roomReading}$addtrigger");
        }

        #readingsSingleUpdate($hash, $roomReading, 1, 1);
        readingsSingleUpdate($hash, $roomReading, $readingTime, 1);

        #Log3($name, 5, "Created timer: $roomReading at +$attime");
        Log3($name, 5, "Created timer: $roomReading at $readingTime");

        my ($range, $minutes, $hours, $minutetext);
        my @timerlimits = $hash->{helper}->{tweaks}->{timerLimits} // (91, 9*MINUTESECONDS, HOURSECONDS, 1.5*HOURSECONDS, HOURSECONDS );
        @time = localtime($value);
        if ( $seconds < $timerlimits[0] && ( !defined $data->{Hourabs} || defined $data->{Hourabs} && $seconds < $timerlimits[4] ) ) { 
            $range = 0;
        } elsif (  $seconds < $timerlimits[2] && ( !defined $data->{Hourabs} || defined $data->{Hourabs} && $seconds < $timerlimits[4] ) ) {
            $minutes = int ($seconds/MINUTESECONDS);
            $range = $seconds < $timerlimits[1] ? 1 : 2;
            $seconds = $seconds % MINUTESECONDS;
            $range = 2 if !$seconds;
            $minutetext =  $hash->{helper}{lng}->{units}->{unitMinutes}->{$minutes > 1 ? 0 : 1};
            $minutetext = qq{$minutes $minutetext} if $minutes > 1;
        } elsif (  $seconds < $timerlimits[3] && ( !defined $data->{Hourabs} || defined $data->{Hourabs} && $seconds < $timerlimits[4] ) ) {
            $hours = int ($seconds/HOURSECONDS);
            $seconds = $seconds % HOURSECONDS;
            $minutes = int ($seconds/MINUTESECONDS);
            $range = 3;
            $minutetext =  $minutes ? $hash->{helper}{lng}->{units}->{unitMinutes}->{$minutes > 1 ? 0 : 1} : q{};
            $minutetext = qq{$minutes $minutetext} if $minutes > 1;
        } else {
            $hours = $time[2];
            $minutes = $time[1];
            $range = 4 + $tomorrow;
        }
        $response = $hash->{helper}{lng}->{responses}->{timerSet}->{$range};
        $response =~ s{(\$\w+)}{$1}eegx;
    }

    $response = getResponse($hash, 'DefaultError') if !defined $response;

    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $name;
}


sub handleIntentCancelAction {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentCancelAction called');

    my $toDisable = defined $data->{customData} && defined $data->{customData}->{'.ENABLED'} ? $data->{customData}->{'.ENABLED'} : [qw(ConfirmAction CancelAction)];
    
    my $response = $hash->{helper}{lng}->{responses}->{ 'SilentCancelConfirmation' };

    return respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response) if !defined $data->{customData};

    #might lead to problems, if there's more than one timeout running...
    #RemoveInternalTimer( $hash, \&RHASSPY_DialogTimeout );
    my $identiy = qq($data->{sessionId});
    deleteSingleRegisteredInternalTimer($identiy, $hash);
    $response = $hash->{helper}{lng}->{responses}->{ 'DefaultCancelConfirmation' };
    configure_DialogManager($hash, $data->{siteId}, $toDisable, 'false');

    return $hash->{NAME};
}


sub handleIntentConfirmAction {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentConfirmAction called');

    #cancellation case
    #return RHASSPY_DialogTimeout($hash, 1, $data) if $data->{Mode} ne 'OK';
    return handleIntentCancelAction($hash, $data) if $data->{Mode} ne 'OK';
       
    #confirmed case
    my $identiy = qq($data->{sessionId});
    my $data_saved = $hash->{helper}{'.delayed'}->{$identiy};
    delete $hash->{helper}{'.delayed'}{$identiy};
    deleteSingleRegisteredInternalTimer($identiy, $hash);
    
    #my $data_old = $hash->{helper}{'.delayed'};
    #my $data_old = $data->{customData} // $data_saved;
    my $data_old = $data_saved;

    #my $toDisable = defined $data->{customData} && defined $data->{customData}->{'.ENABLED'} ? $data->{customData}->{'.ENABLED'} : [qw(ConfirmAction CancelAction)];
    my $toDisable = defined $data_old && defined $data_old->{'.ENABLED'} ? $data_old->{'.ENABLED'} : [qw(ConfirmAction CancelAction)];
    configure_DialogManager($hash, $data->{siteId}, $toDisable, 'false');

    return respond( $hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse( $hash, 'DefaultConfirmationNoOutstanding' ) ) if ! defined $data_old;
    #delete $hash->{helper}{'.delayed'};

    $data_old->{siteId} = $data->{siteId};
    $data_old->{sessionId} = $data->{sessionId};
    $data_old->{requestType} = $data->{requestType};
    $data_old->{Confirmation} = 1;

    my $intent = $data_old->{intent};
    my $device = $hash->{NAME};

    # Passenden Intent-Handler aufrufen
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data_old);
    }

    return $device;
}

sub handleIntentChoiceRoom {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentChoiceRoom called');

    #my $data_old = $data->{customData};
    my $identiy = qq($data->{sessionId});
    my $data_old = $hash->{helper}{'.delayed'}->{$identiy};
    delete $hash->{helper}{'.delayed'}{$identiy};
    deleteSingleRegisteredInternalTimer($identiy, $hash);

    return respond( $hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse( $hash, 'DefaultChoiceNoOutstanding' ) ) if !defined $data_old;

    $data_old->{siteId} = $data->{siteId};
    $data_old->{sessionId} = $data->{sessionId};
    $data_old->{requestType} = $data->{requestType};
    $data_old->{Room} = $data->{Room};

    my $intent = $data_old->{intent};
    my $device = $hash->{NAME};

    # Passenden Intent-Handler aufrufen
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data_old);
    }

    return $device;
}

sub handleIntentChoiceDevice {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentChoiceDevice called');

    #my $data_old = $data->{customData};
    my $identiy = qq($data->{sessionId});
    my $data_old = $hash->{helper}{'.delayed'}->{$identiy};
    delete $hash->{helper}{'.delayed'}{$identiy};
    deleteSingleRegisteredInternalTimer($identiy, $hash);

    return respond( $hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, getResponse( $hash, 'DefaultChoiceNoOutstanding' ) ) if ! defined $data_old;

    $data_old->{siteId} = $data->{siteId};
    $data_old->{sessionId} = $data->{sessionId};
    $data_old->{requestType} = $data->{requestType};
    $data_old->{Device} = $data->{Device};

    my $intent = $data_old->{intent};
    my $device = $hash->{NAME};

    # Passenden Intent-Handler aufrufen
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data_old);
    }

    return $device;
}


sub handleIntentReSpeak {
    my $hash = shift // return;
    my $data = shift // return;
    my $name = $hash->{NAME};

    my $response = ReadingsVal($name,'voiceResponse',$hash->{helper}{lng}->{responses}->{reSpeak_failed});

    Log3($hash->{NAME}, 5, 'handleIntentReSpeak called');

    respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);

    return $name;
}

sub setPlayWav {
    my $hash = shift //return;
    my $cmd = shift;

    Log3($hash->{NAME}, 5, 'action playWav called');

    return 'playWav needs siteId and path to file as parameters!' if !defined $cmd->{siteId} || !defined $cmd->{path};

    my $siteId   = $cmd->{siteId};
    my $filename = $cmd->{path};
    my $repeats  = $cmd->{repeats};
    my $encoding = q{:raw :bytes};
    my $handle   = undef;
    my $topic = "hermes/audioServer/$siteId/playBytes/999";

    Log3($hash->{NAME}, 3, "Playing file $filename on $siteId");

    if (-e $filename) {
        open $handle, "< $encoding", $filename || carp "$0: can't open $filename for reading: $!"; ##no critic qw(RequireBriefOpen)
        while ( read $handle, my $file_contents, 1000000 ) { 
            IOWrite($hash, 'publish', qq{$topic $file_contents});
        }
        close $handle;
    }

    return if !$repeats;
    my $name = $hash->{NAME};
    my $wait     = $cmd->{wait} // 15;
    my $id       = $cmd->{id};

    $repeats--;
    my $attime = strftime( '%H:%M:%S', gmtime $wait );
    return InternalTimer(time, sub (){CommandDefMod($hash, "-temporary $id at +$attime set $name play siteId=\"$siteId\" path=\"$filename\" repeats=$repeats wait=$wait id=$id")}, $hash ) if $repeats;
    return InternalTimer(time, sub (){CommandDefMod($hash, "-temporary $id at +$attime set $name play siteId=\"$siteId\" path=\"$filename\" repeats=$repeats wait=$wait")}, $hash ) if !$id;
    return InternalTimer(time, sub (){CommandDefMod($hash, "-temporary $id at +$attime set $name play siteId=\"$siteId\" path=\"$filename\" repeats=$repeats wait=$wait; deletereading $name $id")}, $hash );
}

# Set volume on specific siteId
sub setVolume {
    my $hash = shift // return;
    my $cmd = shift;

    return 'setVolume needs siteId and volume as parameters!' if !defined $cmd->{siteId} || !defined $cmd->{volume};

    my $sendData =  {
        id => '0',
        sessionId => '0'
    };

    Log3($hash->{NAME}, 5, 'setVolume called');

    $sendData->{siteId} = $cmd->{siteId};
    $sendData->{volume} = 0 + $cmd->{volume};

    my $json = toJSON($sendData);
    return IOWrite($hash, 'publish', qq{rhasspy/audioServer/setVolume $json});

}


# Abgespeckte Kopie von ReplaceSetMagic aus fhem.pl
sub _ReplaceReadingsVal {
    my $hash = shift;
    my $arr  = shift // return;

    my $to_analyze = $arr;

    my $readingsVal = sub ($$$$$) {
        my $all = shift;
        my $t = shift;
        my $d = shift;
        my $n = shift;
        my $s = shift;
        my $val;
        my $dhash = $defs{$d};
        return $all if !$dhash;

        if(!$t || $t eq 'r:') {
            my $r = $dhash->{READINGS};
            if($s && ($s eq ':t' || $s eq ':sec')) {
                return $all if !$r || !$r->{$n};
                $val = $r->{$n}{TIME};
                $val = int(gettimeofday()) - time_str2num($val) if $s eq ':sec';
                return $val;
            }
            $val = $r->{$n}{VAL} if $r && $r->{$n};
        }
        $val = $dhash->{$n}  if !defined $val && (!$t || $t eq 'i:');
        $val = $attr{$d}{$n} if !defined $val && (!$t || $t eq 'a:') && $attr{$d};
        return $all if !defined $val;

        if($s && $s =~ m{:d|:r|:i}x && $val =~ m{(-?\d+(\.\d+)?)}x) {
            $val = $1;
            $val = int($val) if $s eq ':i';
            $val = round($val, defined $1 ? $1 : 1) if $s =~ m{\A:r(\d)?}x;
        }
        return $val;
    };

    $to_analyze =~s{(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])}{$readingsVal->($1,$2,$3,$4,$5)}egx;
    return $to_analyze;
}

sub _getDataFile {
    my $hash     = shift // return;
    my $filename = shift;
    my $name = $hash->{NAME};
    my $lang = $hash->{LANGUAGE};
    $filename = $filename // AttrVal($name,'languageFile',undef);
    my @t = localtime gettimeofday();
    $filename = ResolveDateWildcards($filename, @t);
    $hash->{CONFIGFILE} = $filename; # for configDB migration
    return $filename;
}

sub _readLanguageFromFile {
    my $hash = shift // return;
    my $cfg  = shift // return 0, toJSON($languagevars);

    my $name = $hash->{NAME};
    my $filename = _getDataFile($hash, $cfg);
    Log3($name, 5, "trying to read language from $filename");
    my ($ret, @content) = FileRead($filename);
    if ($ret) {
        Log3($name, 1, "$name failed to read languageFile $filename!") ;
        return $ret, undef;
    }
    my @cleaned = grep { $_ !~ m{\A\s*[#]}x } @content;

    return 0, join q{ }, @cleaned;
}

sub _getDialogueTimeout {
    my $hash = shift // return;
    my $type = shift // q{default};

    my $timeout = $type eq 'confirm' ? 15 : 20;
    $timeout = $hash->{helper}{tweaks}{timeouts}->{$type} 
        if defined $hash->{helper}->{tweaks} 
        && defined $hash->{helper}{tweaks}->{timeouts} 
        && defined $hash->{helper}{tweaks}{timeouts}->{$type} 
        && looks_like_number( $hash->{helper}{tweaks}{timeouts}->{$type} );
    return $timeout;
}


# borrowed from Twilight
################################################################################
################################################################################
sub resetRegisteredInternalTimer {
    my ( $modifier, $tim, $callback, $hash, $waitIfInitNotDone ) = @_;
    deleteSingleRegisteredInternalTimer( $modifier, $hash, $callback );
    return setRegisteredInternalTimer ( $modifier, $tim, $callback, $hash, $waitIfInitNotDone );
}

################################################################################
sub setRegisteredInternalTimer {
    my ( $modifier, $tim, $callback, $hash, $waitIfInitNotDone ) = @_;

    my $timerName = "$hash->{NAME}_$modifier";
    my $fnHash     = {
        HASH     => $hash,
        NAME     => $timerName,
        MODIFIER => $modifier
    };
    weaken($fnHash->{HASH});

    if ( defined( $hash->{TIMER}{$timerName} ) ) {
        Log3( $hash, 1, "[$hash->{NAME}] possible overwriting of timer $timerName - please delete it first" );
        stacktrace();
    }
    else {
        $hash->{TIMER}{$timerName} = $fnHash;
    }

    Log3( $hash, 5, "[$hash->{NAME}] setting  Timer: $timerName " . FmtDateTime($tim) );
    InternalTimer( $tim, $callback, $fnHash, $waitIfInitNotDone );
    return $fnHash;
}

################################################################################
sub deleteSingleRegisteredInternalTimer {
    my $modifier = shift;
    my $hash = shift // return;

    my $timerName = "$hash->{NAME}_$modifier";
    my $fnHash    = $hash->{TIMER}{$timerName};
    if ( defined($fnHash) ) {
        Log3( $hash, 5, "[$hash->{NAME}] removing Timer: $timerName" );
        RemoveInternalTimer($fnHash);
        delete $hash->{TIMER}{$timerName};
    }
    return;
}

################################################################################
sub deleteAllRegisteredInternalTimer {
    my $hash = shift // return;

    for my $key ( keys %{ $hash->{TIMER} } ) {
        deleteSingleRegisteredInternalTimer( $hash->{TIMER}{$key}{MODIFIER}, $hash );
    }
    return;
}



1;

__END__

=pod

=begin ToDo

# Farben:
  Warum die Abfrage nach rgb? <code>if ( defined $data->{Colortemp} && defined $mapping->{rgb} && looks_like_number($data->{Colortemp}) ) {</code>
  Gibt auch Lampen, die können nur ct

# Custom Intents
 - Bei Verwendung des Dialouges wenn man keine Antwort spricht, bricht Rhasspy ab. Die voice response "Tut mir leid, da hat etwas zu lange gedauert" wird
   also gar nicht ausgegeben und:

   PERL WARNING: Use of uninitialized value $cmd in pattern match (m//) at fhem.pl line 5868.

# "rhasspySpecials" bzw. rhasspyTweaks als weitere Attribute
Denkbare Verwendung:
- siteId2room für mobile Geräte (Denkbare Anwendungsfälle: Auswertung BT-RSSI per Perl, aktives Setzen über ein Reading? Oder einen intent? (tweak)
- Bestätigungs-Mapping (special)

# Sonstiges, siehe insbes. https://forum.fhem.de/index.php/topic,119447.msg1148832.html#msg1148832
- kein "match in room" bei GetNumeric
- "kind" und wie man es füllen könnte (mehr Dialoge)
- Bestätigungsdialoge - weitere Anwendungsfelder
- gDT: mehr und bessere mappings?
- Farbe und Farbtemperatur (fast fertig?)
- Hat man in einem Raum einen Satelliten aber kein Device mit der siteId/Raum, kann man den Satelliten bei z.B. dem Timer nicht ansprechen, weil der Raum nicht in den Slots ist.
  Irgendwie müssen wir die neue siteId in den Slot Rooms bringen

# Parameter-Check für define? Anregung DrBasch aus https://forum.fhem.de/index.php/topic,119447.msg1157700.html#msg1157700

# Keine shortcuts-Intents, wenn Attribut nicht gesetzt: Anregung DrBasch aus https://forum.fhem.de/index.php/topic,119447.msg1157700.html#msg1157700

=end ToDo

=begin ToClarify

#defaultRoom (JensS):
- überhaupt erforderlich?
- Schreibweise: RHASSPY ist raus, Rhasspy scheint der überkommene Raumname für die devspec zu sein => ist erst mal weiter beides drin

# GetTimer implementieren?
https://forum.fhem.de/index.php/topic,113180.msg1130139.html#msg1130139

# Wetterdurchsage
Ist möglich. Dazu hatte ich einen rudimentären Intent in diesem Thread erstellt. Müsste halt nur erweitert werden.
https://forum.fhem.de/index.php/topic,113180.msg1130754.html#msg1130754

=end ToClarify

=encoding utf8
=item device
=item summary Control FHEM with Rhasspy voice assistant
=item summary_DE Steuerung von FHEM mittels Rhasspy Sprach-Assistent
=begin html

<a id="RHASSPY"></a>
<h3>RHASSPY</h3>
<p>This module receives, processes and executes voice commands coming from <a href="https://rhasspy.readthedocs.io/en/latest/">Rhasspy voice assistent</a>.</p>

<a id="RHASSPY-define"></a>
<h4>Define</h4>
<p><code>define &lt;name&gt; RHASSPY &lt;baseUrl&gt; &lt;devspec&gt; &lt;defaultRoom&gt; &lt;language&gt; &lt;fhemId&gt; &lt;prefix&gt; &lt;useGenericAttrs&gt; &lt;encoding&gt;</code></p>
<p><b>All parameters in define are optional, but changing them later might lead to confusing results!</b></p>
<p><a id="RHASSPY-parseParams"></a><b>General Remark:</b> RHASSPY uses <a href="https://wiki.fhem.de/wiki/DevelopmentModuleAPI#parseParams"><b>parseParams</b></a> at quite a lot places, not only in define, but also to parse attribute values.<br>
So all parameters in define should be provided in the <i>key=value</i> form. In other places you may have to start e.g. a single line in an attribute with <code>option:key="value xy shall be z"</code> or <code>identifier:yourCode={fhem("set device off")} anotherOption=blabla</code> form.</p>

<ul>
  <li><b>baseUrl</b>: http-address of the Rhasspy service web-interface. Optional. Default is <code>baseUrl=http://127.0.0.1:12101</code>.<br>Make sure, this is set to correct values (ip and port)</li>
  <li><b>devspec</b>: A description of devices that should be controlled by Rhasspy. Optional. Default is <code>devspec=room=Rhasspy</code>, see <a href="#devspec"> as a reference</a>, how to e.g. use a comma-separated list of devices or combinations like <code>devspec=room=livingroom,room=bathroom,bedroomlamp</code>.</li>
  <li><b>defaultRoom</b>: Default room name. Used to speak commands without a room name (e.g. &quot;turn lights on&quot; to turn on the lights in the &quot;default room&quot;). Optional. Default is <code>defaultRoom=default</code>.</li>
  <li><b>language</b>: Makes part of the topic tree, RHASSPY is listening to. Should (but needs not to) point to the language voice commands shall be spoken with. Default is derived from global, which defaults to <code>language=en</code></li>
  <li><b>encoding</b>: May be helpfull in case you experience problems in conversion between RHASSPY (module) and Rhasspy (service). Example: <code>encoding=cp-1252</code></li>
  <li><b>fhemId</b>: May be used to distinguishe between different instances of RHASSPY on the MQTT side. Also makes part of the topic tree the corresponding RHASSPY is listening to.<br>
  Might be usefull, if you have several instances of FHEM running, and may - in later versions - be a criteria to distinguish between different users (e.g. to only allow a subset of commands and/or rooms to be addressed).</li>
  <li><b>prefix</b>: May be used to distinguishe between different instances of RHASSPY on the FHEM-internal side.<br>
  Might be usefull, if you have several instances of RHASSPY in one FHEM running and want e.g. to use different identifier for groups and rooms (e.g. a different language).</li>
  <li><b>useGenericAttrs</b>: By default, RHASSPY only uses it's own attributes (see list below) to identifiy options for the subordinated devices you want to control. Activating this with <code>useGenericAttrs=1</code> adds <code>genericDeviceType</code> to the global attribute list and activates RHASSPY's feature to estimate appropriate settings - similar to rhasspyMapping. In later versions <code>homebridgeMapping</code> may also be on the list.</li>
</ul>

<p>RHASSPY needs a <a href="#MQTT2_CLIENT">MQTT2_CLIENT</a> device connected to the same MQTT-Server as the voice assistant (Rhasspy) service.</p>
<p><b>Example for defining an MQTT2_CLIENT device and the Rhasspy device in FHEM:</b></p>
<p><code>defmod rhasspyMQTT2 MQTT2_CLIENT 192.168.1.122:12183<br>
attr rhasspyMQTT2 clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE<br>
attr rhasspyMQTT2 subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded</code></p>
<p><code>define Rhasspy RHASSPY devspec=room=Rhasspy defaultRoom=Livingroom language=en</code></p>

<p><b>Additionals remarks on MQTT2-IOs:</b></p>
<p>Using a separate MQTT server (and not the internal MQTT2_SERVER) is highly recommended, as the Rhasspy scripts also use the MQTT protocol for internal (sound!) data transfers. Best way is to either use MQTT2_CLIENT (see above) or bridge only the relevant topics from mosquitto to MQTT2_SERVER (see e.g. <a href="http://www.steves-internet-guide.com/mosquitto-bridge-configuration/">http://www.steves-internet-guide.com/mosquitto-bridge-configuration</a> for the principles). When using MQTT2_CLIENT, it's necessary to set <code>clientOrder</code> to include RHASSPY (as most likely it's the only module listening to the CLIENT it could be just set to <code>attr &lt;m2client&gt; clientOrder RHASSPY</code>)</p>
<p>Furthermore, you are highly encouraged to restrict subscriptions only to the relevant topics:</p>
<p><code>attr &lt;m2client&gt; subscriptions setByTheProgram</code></p>
<p>In case you are using the MQTT server also for other purposes than Rhasspy, you have to set <code>subscriptions</code> manually to at least include the following topics additionally to the other subscriptions desired for other purposes.</p>
<p><code>hermes/intent/+<br>
hermes/dialogueManager/sessionStarted<br>
hermes/dialogueManager/sessionEnded</code></p>

<p><b>Important</b>: After defining the RHASSPY module, you are supposed to manually set the attribute <i>IODev</i> to force a non-dynamic IO assignement. Use e.g. <code>attr &lt;deviceName&gt; IODev &lt;m2client&gt;</code>.</p>

<p><a id="RHASSPY-list"></a><b>Note:</b> RHASSPY consolidates a lot of data from different sources. The <b>final data structure RHASSPY uses</b> at runtime can be viewed using the <a href="#list">list command</a>. It's highly recommended to have a close look at this data structure, especially when starting with RHASSPY or in case something doesn't work as expected!<br> 
When changing something relevant within FHEM for either the data structure in</p>
<ul>
  <li><b>RHASSPY</b> (this form is used when reffering to module or the FHEM device) or for </li>
  <li><b>Rhasspy</b> (this form is used when reffering to the remote service), </li>
</ul>
<p>these changes must be get to known to RHASSPY and (often, but not allways) to Rhasspy. See the different versions provided by the <a href="#RHASSPY-set-update">update command</a>.</p>

<a id="RHASSPY-set"></a>
<h4>Set</h4>
<ul>
  <li>
    <a id="RHASSPY-set-update"></a><b>update</b>
    <p>Choose between one of the following:</p>
    <ul>
      <li><b>devicemap</b><br>
      When having finished the configuration work to RHASSPY and the subordinated devices, issuing a devicemap-update is mandatory, to get the RHASSPY data structure updated, inform Rhasspy on changes that may have occured (update slots) and initiate a training on updated slot values etc., see <a href="#RHASSPY-list">remarks on data structure above</a>.
      </li>
      <li><b>devicemap_only</b><br>
      This may be helpfull to make an intermediate check, whether attribute changes have found their way to the data structure. This will neither update slots nor initiate any training towards Rhasspy.
      </li>
      <li><b>slots</b><br>
      This may be helpfull after checks on the FHEM side to send all data to Rhasspy and initiate training.
      </li>
      <li><b>slots_no_training</b><br>
      This may be helpfull to make checks, whether all data is sent to Rhasspy. This will not initiate any training.
      </li>
      <li><b>language</b><br>
      Reinitialization of language file.<br>
      Be sure to execute this command after changing something within in the language configuration file!<br>
      </li>
      <li><b>all</b><br>
      Surprise: means language file and full update to RHASSPY and Rhasspy including training.
      </li>
    </ul>
    <p>Example: <code>set &lt;rhasspyDevice&gt; update language</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-play"></a><b>play</b>
    <p>Send WAV file to Rhasspy.<br>
    <i>siteId</i> and <i>path</i> are required!<br>
    You may optionally add a number of repeats and a wait time in seconds between repeats. <i>wait</i> defaults to 15, if only <i>repeats</i> is given.</p>
    <p>Examples:<br>
      <code>set &lt;rhasspyDevice&gt; play siteId="default" path="/opt/fhem/test.wav"</code><br>
      <code>set &lt;rhasspyDevice&gt; play siteId="default" path="./test.wav" repeats=3 wait=20</code>
    </p>
  </li>

  <li>
    <a id="RHASSPY-set-speak"></a><b>speak</b>
    <p>Voice output over TTS.<br>
    Both arguments (siteId and text) are required!</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; speak siteId="default" text="This is a test"</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-textCommand"></a><b>textCommand</b>
    <p>Send a text command to Rhasspy.</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; textCommand turn the light on</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-fetchSiteIds"></a><b>fetchSiteIds</b>
    <p>Send a request to Rhasspy to send all siteId's. This by default is done once, so in case you add more satellites to your system, this may help to get RHASSPY updated.</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; fetchSiteIds</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-trainRhasspy"></a><b>trainRhasspy</b>
    <p>Sends a train-command to the HTTP-API of the Rhasspy master<br>
    Might be removed in the future versions in favor of the update features</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; trainRhasspy</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-volume"></a><b>volume</b>
    <p>Sets volume of given siteId between 0 and 1 (float)<br>
    Both arguments (siteId and volume) are required!</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; siteId="default" volume="0.5"</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-customSlot"></a><b>customSlot</b>
    <p>Creates a new - or overwrites an existing slot - in Rhasspy<br>
    Provide slotname, slotdata and (optional) info, if existing data shall be overwritten and training shall be initialized immediately afterwards.<br>
    First two arguments are required, third and fourth are optional.<br>
    <i>overwrite</i> defaults to <i>true</i>, setting any other value than <i>true</i> will keep existing Rhasspy slot data.</p>
    <p>Examples:<br>
    <code>set &lt;rhasspyDevice&gt; customSlot mySlot a,b,c overwrite training </code><br>
    <code>set &lt;rhasspyDevice&gt; customSlot slotname=mySlot slotdata=a,b,c overwrite=false</code></p>
  </li>
</ul>

<a id="RHASSPY-attr"></a>
<h4>Attributes</h4>
<p>Note: To get RHASSPY working properly, you have to configure attributes at RHASSPY itself and the subordinated devices as well.</p>

<a id="RHASSPY-attr-device"></a>
<p><b>RHASSPY itself</b> supports the following attributes:</p>
<ul>
  <li>
    <a id="RHASSPY-attr-languageFile"></a><b>languageFile</b><br>
    <p>Path to the language-config file. If this attribute isn't set, a default set of english responses is used for voice responses.<br>
    The file itself must contain a JSON-encoded keyword-value structure (partly with sub-structures) following the given structure for the mentioned english defaults. As a reference, there's one available in german, or just make a dump of the English structure with e.g. (replace RHASSPY by your device's name): <code>{toJSON($defs{RHASSPY}->{helper}{lng})}</code>, edit the result e.g. using https://jsoneditoronline.org and place this in your own languageFile version. There might be some variables to be used - these should also work in your sentences.<br>
    languageFile also allows combining e.g. a default set of german sentences with some few own modifications by using "defaults" subtree for the defaults and "user" subtree for your modified versions. This feature might be helpful in case the base language structure has to be changed in the future.</p>
    <p>Example (placed in the same dir fhem.pl is located):</p>
    <p><code>attr &lt;rhasspyDevice&gt; languageFile ./rhasspy-de.cfg</code></p>
  </li>

  <li>
    <a id="RHASSPY-attr-response"></a><b>response</b>
    <p><b>Not recommended. Use the language-file instead.</b></p>
    <p>Optionally define alternative default answers. Available keywords are <code>DefaultError</code>, <code>NoActiveMediaDevice</code> and <code>DefaultConfirmation</code>.</p>
    <p>Example:</p>
    <p><code>DefaultError=
DefaultConfirmation=Klaro, mach ich</code></p>
  </li>

  <li>
    <a id="RHASSPY-attr-rhasspyIntents"></a><b>rhasspyIntents</b>
    <p>Defines custom intents. See <a href="https://github.com/Thyraz/Snips-Fhem#f%C3%BCr-fortgeschrittene-eigene-custom-intents-erstellen-und-in-fhem-darauf-reagieren" hreflang="de">Custom Intent erstellen</a>.<br>
    One intent per line.</p>
    <p>Example:</p>
    <p><code>attr &lt;rhasspyDevice&gt; rhasspyIntents SetCustomIntentsTest=SetCustomIntentsTest(siteId,Type)</code></p>
    <p>together with the following myUtils-Code should get a short impression of the possibilities:</p>
    <p><code>sub SetCustomIntentsTest {<br>
        my $room = shift;<br>
        my $type = shift;<br>
        Log3('rhasspy',3 , "RHASSPY: Room $room, Type $type");<br>
        return "RHASSPY: Room $room, Type $type";<br>
    }</code></p>
    <p>The following arguments can be handed over:</p>
    <ul>
    <li>NAME => name of the RHASSPY device addressed, </li>
    <li>DATA => entire JSON-$data (as parsed internally), encoded in JSON</li>
    <li>siteId, Device etc. => any element out of the JSON-$data.</li>
    </ul>
    <p>If a simple text is returned, this will be considered as response.<br>
    For more advanced use of this feature, you may return an array. First element of the array will be interpreted as comma-separated list of devices that may have been modified (otherwise, these devices will not cast any events! See also the "d" parameter in <a href="#RHASSPY-attr-rhasspyShortcuts"><i>rhasspyShortcuts</i></a>). The second element is interpreted as response and may either be simple text or HASH-type data. This will keep the dialogue-session open to allow interactive data exchange with <i>Rhasspy</i>. An open dialogue will be closed after some time, default is 20 seconds, you may alternatively hand over other numeric values as third element of the array.</p>
  </li>

  <li>
    <a id="RHASSPY-attr-rhasspyShortcuts"></a><b>rhasspyShortcuts</b>
    <p>Define custom sentences without editing Rhasspys sentences.ini<br>
    The shortcuts are uploaded to Rhasspy when using the updateSlots set-command.<br>
    One shortcut per line, syntax is either a simple and an extended version.</p>
    <p>Examples:</p>
    <p><code>mute on=set amplifier2 mute on<br>
lamp off={fhem("set lampe1 off")}<br>
i="you are so exciting" f="set $NAME speak siteId='livingroom' text='Thanks a lot, you are even more exciting!'"<br>
i="mute off" p={fhem ("set $NAME mute off")} n=amplifier2 c="Please confirm!"<br>
i="i am hungry" f="set Stove on" d="Stove" c="would you like roast pork"</code></p>
    <p>Abbreviations explanation:</p>
    <ul>
      <li><b>i</b> => intent<br>
      Lines starting with "i:" will be interpreted as extended version, so if you want to use that syntax style, starting with "i:" is mandatory.</li> 
      <li><b>f</b> => FHEM command<br>
      Syntax as usual in FHEMWEB command field.</li>
      <li><b>p</b> => Perl command<br>
      Syntax as usual in FHEMWEB command field, enclosed in {}; this has priority to "f=".</li>
      <li><b>d</b> => device name(s, comma separated) that shall be handed over to fhem.pl as updated. Needed for triggering further actions and longpoll! If not set, the return value of the called function will be used. </li>
      <li><b>r</b> => Response to be send to the caller. If not set, the return value of the called function will be used.<br>
      Response sentence will be parsed to do "set magic"-like replacements, so also a line like <code>i="what's the time for sunrise" r="at [Astro:SunRise] o'clock"</code> is valid.<br>
      You may ask for confirmation as well using the following (optional) shorts:
      <ul>
        <li><b>c</b> => either numeric or text. If numeric: Timeout to wait for automatic cancellation. If text: response to send to ask for confirmation.</li>
        <li><b>ct</b> => numeric value for timeout in seconds, default: 15.</li>
      </ul></li>
    </ul>
  </li>

  <li>
    <a id="RHASSPY-attr-rhasspyTweaks"></a><b>rhasspyTweaks</b>
    <p>Currently sets additional settings for timers and slot-updates to Rhasspy. May contain further custom settings in future versions like siteId2room info or code links, allowed commands, confirmation requests etc.</p>
    <ul>
      <li><b>timerLimits</b>
        <p>Used to determine when the timer should response with e.g. "set to 30 minutes" or with "set to 10:30"</p>
        <p><code>timerLimits=90,300,3000,2*HOURSECONDS,50</code></p>
        <p>Five values have to be set, corresponding with the limits to <i>timerSet</i> responses. so above example will lead to seconds response for less then 90 seconds, minute+seconds response for less than 300 seconds etc.. Last value is the limit in seconds, if timer is set in time of day format.</p>
      </li>
      <li><b>timerSounds</b>
        <p>Per default the timer responds with a voice command if it has elapsed. If you want to use a wav-file instead, you can set this here.</p>
        <p><code>timerSounds= default=./yourfile1.wav eggs=3:20:./yourfile2.wav potatoes=5:./yourfile3.wav</code></p>
        <p>Above keys are some examples and need to match the "Label"-tags for the timer provided by the Rhasspy-sentences.<br>
        <i>default</i> is optional. If set, this file will be used for all labeled timer without match to other keywords.<br>
        The two numbers are optional. The first one sets the number of repeats, the second is the waiting time between the repeats.<br>
        <i>repeats</i> defaults to 5, <i>wait</i> to 15<br>
        If only one number is set, this will be taken as <i>repeats</i>.</p>
      </li>
      <li><b>updateSlots</b>
        <p>Changes aspects on slot generation and updates.</p>
        <p><code>noEmptySlots=1</code></p>
        <p>By default, RHASSPY will generate an additional slot for each of the genericDeviceType it recognizes, regardless, if there's any devices marked to belong to this type. If set to <i>1</i>, no empty slots will be generated.</p>
        <p><code>overwrite_all=false</code></p>
        <p>By default, RHASSPY will overwrite all generated slots. Setting this to <i>false</i> will change this.</p>
      </li>
      <li><b>timeouts</b>
        <p>Atm. keywords <i>confirm</i> and/or <i>default</i> can be used to change the corresponding defaults (15 seconds / 20 seconds) used for dialogue timeouts.</p>
        <p>Example:</p>
        <p><code>timeouts: confirm=25 default=30</code></p>
      </li>

    </ul>
  </li>

  <li>
    <a id="RHASSPY-attr-forceNEXT"></a><b>forceNEXT</b>
    <p>If set to 1, RHASSPY will forward incoming messages also to further MQTT2-IO-client modules like MQTT2_DEVICE, even if the topic matches to one of it's own subscriptions. By default, these messages will not be forwarded for better compability with autocreate feature on MQTT2_DEVICE. See also <a href="#MQTT2_CLIENTclientOrder">clientOrder attribute in MQTT2 IO-type commandrefs</a>; setting this in one instance of RHASSPY might affect others, too.</p>
  </li>
</ul>

<p>&nbsp;</p>
<a id="RHASSPY-attr-subdevice"></a>
<p><b>For the subordinated devices</b>, a list of the possible attributes is automatically extended by several further entries.</p>
<p>There are two ways to tell RHASSPY which devices it should control:</p>
<ul>
  <li><a href="#RHASSPY-genericDeviceType">genericDeviceType</a> (gDT)</li>
  <li><a href="#RHASSPY-rhasspySpecificAttributes">RHASSPY specific attributes</a></li>
</ul>
<p>It's also possible to mix these two options if one of it isn't enough.</p>

<a id="RHASSPY-genericDeviceType"></a><p><b>genericDeviceType</b></p>
<p>If this attribute is set, RHASSPY will try to determine mapping (and other) information from the attributes already present (if devices match devspec). Currently the following subset of genericDeviceType is supported:</p>
<ul>
  <li>switch</li>
  <li>light</li>
  <li>thermostat</li>
  <li>thermometer</li>
  <li>blind</li>
  <li>media</li>
</ul>
<p>When using genericDeviceType, collected information about the device are for example:</p>
<ul>
  <li>the name (NAME or alias)</li>
  <li>the ROOM or GROUP the device is in</li>
  <li>how to GET information from the device</li>
  <li>how to SET state/values</li>
</ul>
<p>This is the easiest way to get devices to work with RHASSPY. In some cases it may happen that gDT delivers to less or not suitable information for this particular device. Then it's possible to overwrite this with the following RHASSPY specific device attributes.</p>
<a href="#RHASSPY-rhasspySpecificAttributes"></a><p><b>RHASSPY specific attributes</b></p>
<p>The names of these attributes all start with the <i>prefix</i> previously defined in RHASSPY<br>
These attributes are used to configure the actual mapping to the intents and the content sent by Rhasspy.</p>
<p>By default, the following attribute names are used: rhasspyName, rhasspyRoom, rhasspyGroup, rhasspyChannels, rhasspyColors, rhasspySpecials.<br>
Each of the keywords found in these attributes will be sent by <a href="#RHASSPY-set-update">update</a> to Rhasspy to create the corresponding slot.</p>
<ul>
  <li>
    <a id="RHASSPY-attr-rhasspyName"></a><b>rhasspyName</b>
    <p>Comma-separated "labels" for the device as used when speaking a voice-command. They will be used as keywords by Rhasspy. May contain space or mutated vovels.</p>
    <p>Example:<br>
    <code>attr m2_wz_08_sw rhasspyName kitchen lamp,ceiling lamp,workspace,whatever</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyRoom"></a><b>rhasspyRoom</b>
    <p>Comma-separated "labels" for the "rooms" the device is located in. Recommended to be unique.</p>
    <p>Example:<br>
    <code>attr m2_wz_08_sw rhasspyRoom living room</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyGroup"></a><b>rhasspyGroup</b>
    <p>Comma-separated "labels" for the "groups" the device is in. Recommended to be unique.</p>
    <p>Example:
    <code>attr m2_wz_08_sw rhasspyGroup lights</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-Mapping"></a><b>rhasspyMapping</b>
    <p>If automatic detection (gDT) does not work or is not desired, this is the place to tell RHASSPY how your device can be controlled.</p>
    <p>Example:</p>
    <p><code>attr lamp rhasspyMapping SetOnOff:cmdOn=on,cmdOff=off,response="All right"<br>
GetOnOff:currentVal=state,valueOff=off<br>
GetNumeric:currentVal=pct,type=brightness<br>
SetNumeric:currentVal=brightness,cmd=brightness,minVal=0,maxVal=255,map=percent,step=1,type=brightness<br>
GetState:response=The temperature in the kitchen is at [lamp:temperature] degrees<br>
MediaControls:cmdPlay=play,cmdPause=pause,cmdStop=stop,cmdBack=previous,cmdFwd=next</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyChannels"></a><b>rhasspyChannels</b>
    <p>Used to change the channels of a tv, set light-scenes, etc.<br>
    <i>key=value</i> line by line arguments mapping command strings to fhem- or Perl commands.</p>
    <p>Example:</p>
    <p><code>attr TV rhasspyChannels orf eins=channel 201<br>
orf zwei=channel 202<br>
orf drei=channel 203<br>
</code></p>
    <p>Note: This attribute is not added to global attribute list by default. Add it using userattr or by editing the global userattr attribute.</p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyColors"></a><b>rhasspyColors</b>
    <p>Used to change to colors of a light<br>
    <i>key=value</i> line by line arguments mapping keys to setter strings on the same device.</p>
    <p>Example:</p>
    <p><code>attr lamp1 rhasspyColors red=rgb FF0000<br>
green=rgb 008000<br>
blue=rgb 0000FF<br>
yellow=rgb FFFF00</code></p>
    <p>Note: This attribute is not added to global attribute list by default. Add it using userattr or by editing the global userattr attribute. You may consider using <a href="#RHASSPY-attr-rhasspySpecials">rhasspySpecials</a> (<i>colorCommandMap</i> and/or <i>colorForceHue2rgb</i>) instead.</p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspySpecials"></a><b>rhasspySpecials</b>
    <p>Currently some colour light options besides group and venetian blind related stuff is implemented, this could be the place to hold additional options, e.g. for confirmation requests. You may use several of the following lines.</p>
    <p><i>key:value</i> line by line arguments similar to <a href="#RHASSPY-attr-rhasspyTweaks">rhasspyTweaks</a>.</p>
    <ul>
      <li><b>group</b>
        <p>If set, the device will not be directly addressed, but the mentioned group - typically a FHEM <a href="#structure">structure</a> device or a HUEDevice-type group. This has the advantage of saving RF ressources and/or already implemented logics.<br>
        Note: all addressed devices will be switched, even if they are not member of the rhasspyGroup. Each group should only be addressed once, but it's recommended to put this info in all devices under RHASSPY control in the same external group logic.<br>
        All of the following options are optional.</p>
        <ul>
          <li><b>async_delay</b><br>
            Float nummeric value, just as async_delay in structure; the delay will be obeyed prior to the next sending command.</li> 
          <li><b>prio</b><br>
            Numeric value, defaults to "0". <i>prio</i> and <i>async_delay</i> will be used to determine the sending order as follows: first devices will be those with lowest prio arg, second sort argument is <i>async_delay</i> with lowest value first.</li>
        </ul>
        <p>Example:</p>
        <p><code>attr lamp1 rhasspySpecials group:async_delay=100 prio=1 group=lights</code></p>
      </li>
      <li><b>venetianBlind</b>
        <p><code>attr blind1 rhasspySpecials venetianBlind:setter=dim device=blind1_slats</code></p>
        <p>Explanation (one of the two arguments is mandatory):
        <ul>
          <li><b>setter</b> is the set command to control slat angle, e.g. <i>positionSlat</i> for CUL_HM or older ZWave type devices</li>
          <li><b>device</b> is needed if the slat command has to be issued towards a different device (applies e.g. to newer ZWave type devices)</li>
        </ul>
        <p>If set, the slat target position will be set to the same level than the main device.</p>
      </li>
      <li><b>colorCommandMap</b>
        <p>Allows mapping of values from the <i>Color</i> key to individual commands.</p>
        <p>Example:</p>
        <p><code>attr lamp1 rhasspySpecials colorCommandMap:0='rgb FF0000' 120='rgb 00FF00' 240='rgb 0000FF'</code></p>
      </li>
      <li><b>colorForceHue2rgb</b>
        <p>Defaults to "0". If set, a rgb command will be issued, even if the device is capable to handle hue commands.</p>
        <p>Example:</p>
        <p><code>attr lamp1 rhasspySpecials colorForceHue2rgb:1</code></p>
      </li>
      <li><b>priority</b>
        <p>Keywords <i>inRoom</i> and <i>outsideRoom</i> can be used, each followed by comma separated types to give priority in <i>GetNumeric</i>. This may eleminate requests in case of several possible devices or rooms to deliver requested info type.</p>
        <p>Example:</p>
        <p><code>attr sensor_outside_main rhasspySpecials priority:inRoom=temperature outsideRoom=temperature,humidity,pressure</code></p>
      </li>
    </ul>
  </li>
</ul>


<a id="RHASSPY-intents"></a>
<h4>Intents</h4>
<p>The following intents are directly implemented in RHASSPY code:
<ul>
  <li>Shortcuts</li>
  <li>SetOnOff</li>
  <li>SetOnOffGroup</li>
  <li>GetOnOff</li>
  <li>SetNumeric</li>
  <li>SetNumericGroup</li>
  <li>GetNumeric</li>
  <li>GetState</li>
  <li>MediaControls</li>
  <li>MediaChannels</li>
  <li>SetColor</li>
  <li>SetColorGroup</li>
  <li>GetTime</li>
  <li>GetWeekday</li>
  <li>SetTimer</li>
  <li>ConfirmAction</li>
  <li>CancelAction</li>
  <li>ChoiceRoom</li>
  <li>ChoiceDevice</li>
  <li>ReSpeak</li>
</ul>

=end html
=cut
