# $Id$
###########################################################################
#
# FHEM RHASSPY module (https://github.com/rhasspy)
#
# Originally initiated 2018 by Tobias Wiedenmann (Thyraz)
# as FHEM Snips.ai module (thanks to Matthias Kleine)
#
# Adapted for RHASSPY 2020-2022 by Beta-User and drhirn
#
# Thanks to rudolfkoenig, JensS, cb2sela and all the others
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
use GPUtils qw(GP_Import);
use JSON ();
use Encode;
use HttpUtils;
use utf8;
use List::Util 1.45 qw(max min uniq);
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(gettimeofday);
use POSIX qw(strftime);
use FHEM::Core::Timer::Register qw(:ALL);
#use FHEM::Meta;

sub ::RHASSPY_Initialize { goto &Initialize }

my %gets = (
    test_file      => [],
    test_sentence  => [],
    export_mapping => []
);

my %sets = (
    speak               => [],
    play                => [],
    customSlot          => [],
    textCommand         => [],
    trainRhasspy        => [qw(noArg)],
    fetchSiteIds        => [qw(noArg)],
    update              => [qw(devicemap devicemap_only slots slots_no_training language intent_filter all)],
    volume              => [],
    msgDialog           => [qw( enable disable )],
    activateVoiceInput  => []
    #text2intent  => []
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
    'DefaultError' => "Sorry but something seems not to work as expected!",
    'ContinueSession' => "Something else? | Any more wishes?",
    'NoValidResponse' => 'Error. respond function called without valid response!',
    'NoValidIntentResponse' => 'Error. respond function called by $intent without valid response!',
    'NoIntentRecognized' => 'Your input could not be assigned to one of the known intents!',
    'NoValidData' => "Sorry but the received data is not sufficient to derive any action.",
    'ParadoxData' => {
        'hint' => 'The received data is paradoxical: $val[0] and $val[1] do not fit together.',,
        'confirm' => 'Switch $val[0] based on name and site id?'
    },
    'NoDeviceFound' => "Sorry but I could not find a matching device.",
    'NoTimedOnDeviceFound' => "Sorry but device does not support requested timed on or off command.",
    'NoMappingFound' => "Sorry but I could not find a suitable mapping.",
    'NoNewValDerived' => "Sorry but I could not calculate a new value to set.",
    'NoActiveMediaDevice' => "Sorry no active playback device.",
    'NoMediaChannelFound' => "Sorry but requested channel seems not to exist.",
    'DefaultConfirmation' => "OK",
    'DefaultConfirmationBack' => "So once more.",
    'DefaultConfirmationTimeout' => "Sorry, too late to confirm.",
    'DefaultCancelConfirmation' => "Thanks, aborted.",
    'SilentCancelConfirmation' => "",
    'DefaultConfirmationReceived' => "Ok, will do it!",
    'DefaultConfirmationNoOutstanding' => "No command is awaiting confirmation!",
    'DefaultConfirmationRequestRawInput' => 'Please confirm: $rawInput!',
    'DefaultChangeIntentRequestRawInput' => 'Change command to $rawInput!',
    'RequestChoiceDevice' => 'There are several possible devices, choose between $first_items and $last_item.',
    'RequestChoiceRoom' => 'More than one possible device, please choose one of the following rooms $first_items and $last_item.',
    'RequestChoiceGeneric' => 'There are several options, choose between $options.',
    'DefaultChoiceNoOutstanding' => "No choice expected!",
    'NoMinConfidence' => 'Minimum confidence not given, level is $confidence',
    'XtendAnswers' => {
        'unknownDevs' => '$uknDevs could not be identified.'
    },
    'timerSet'   => {
        '0' => '$label in room $room has been set to $seconds seconds',
        '1' => '$label in room $room has been set to $minutes minutes $seconds',
        '2' => '$label in room $room has been set to $minutes minutes',
        '3' => '$label in room $room has been set to $hours hours $minutetext',
        '4' => '$label in room $room has been set to $hour o clock $minutes',
        '5' => '$label in room $room has been set to tomorrow $hour o clock $minutes',
        '6' => '$label in room $room is not existent',
    },
    'timerEnd'   => {
        '0' => '$label expired',
        '1' =>  '$label in room $room expired'
    },
    'timerCancellation' => '$label for $room deleted',
    'timeRequest' => 'It is $hour o clock $min minutes',
    'weekdayRequest' => 'Today is $weekDay, $month the $day., $year',
    'duration_not_understood'   => "Sorry I could not understand the desired duration",
    'reSpeak_failed'   => 'I am sorry i can not remember',
    'Change' => {
      'humidity'     => 'Air humidity in $location is $value percent',
      'battery'      => {
        '0' => 'Battery level in $location is $value',
        '1' => 'Battery level in $location is $value percent'
      },
      'brightness'   => '$device was set to $value',
      'setTarget'    => '$device is set to $value',
      'soilMoisture' => 'Soil moisture in $location is $value percent',
      'temperature'  => {
        '0' => 'Temperature in $location is $value',
        '1' => 'Temperature in $location is $value degrees',
      },
      'desired-temp' => 'Target temperature for $location is set to $value degrees',
      'volume'       => '$device set to $value',
      'waterLevel'   => 'Water level in $location is $value percent',
      'knownType'    => '$mappingType in $location is $value percent',
      'unknownType'  => 'Value in $location is $value percent'
    },
    'getStateResponses' => {
      'STATE'   => '$deviceName value is [$device:STATE]',
      'price'   => 'Current price of $reading in $deviceName is [$device:$reading:d]',
      'reading' => '[$device:$reading]',
      'update'  => 'Initiated update for $deviceName'
    },
    'getRHASSPYOptions' => {
      'generic' => 'Actions to devices may be initiated or information known by your automation can be requested',
      'control' => 'In $room amongst others the following entities can be controlled $deviceNames',
      'info'    => 'Especially $deviceNames may serve as information source in $room',
      'rooms'   => 'Amongst others i know $roomNames as rooms',
      'scenes'  => '$deviceNames in $room may be able to be set to $sceneNames'
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

BEGIN {

  GP_Import( qw(
    addToAttrList delFromDevAttrList
    addToDevAttrList delFromAttrList
    readingsSingleUpdate
    readingsBeginUpdate
    readingsBulkUpdate
    readingsEndUpdate
    readingsDelete
    Log3
    defs attr cmds modules L
    DAYSECONDS HOURSECONDS MINUTESECONDS
    init_done fhem_started
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
    FmtDateTime
    makeReadingName
    FileRead FileWrite
    getAllSets
    notifyRegexpChanged setNotifyDev
    deviceEvents
    asyncOutput
    trim
  ) )
};

# MQTT Topics die das Modul automatisch abonniert
my @topics = qw(
    hermes/intent/+
    hermes/dialogueManager/sessionStarted
    hermes/dialogueManager/sessionEnded
    hermes/nlu/intentNotRecognized
    hermes/hotword/+/detected
    hermes/hotword/toggleOn
    hermes/hotword/toggleOff
    hermes/tts/say
);

sub Initialize {
    my $hash = shift // return;

    # Consumer
    $hash->{DefFn}       = \&Define;
    $hash->{UndefFn}     = \&Undefine;
    $hash->{DeleteFn}    = \&Delete;
    #$hash->{RenameFn}    = \&Rename;
    $hash->{SetFn}       = \&Set;
    $hash->{GetFn}       = \&Get;
    $hash->{AttrFn}      = \&Attr;
    $hash->{AttrList}    = "IODev rhasspyIntents:textField-long rhasspyShortcuts:textField-long rhasspyTweaks:textField-long response:textField-long rhasspyHotwords:textField-long rhasspyMsgDialog:textField-long rhasspySpeechDialog:textField-long forceNEXT:0,1 disable:0,1 disabledForIntervals languageFile " . $readingFnAttributes; #rhasspyTTS:textField-long 
    $hash->{Match}       = q{.*};
    $hash->{ParseFn}     = \&Parse;
    $hash->{NotifyFn}    = \&Notify;
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
        push @unknown, $_ if $_ !~ m{\A(?:baseUrl|defaultRoom|language|devspec|fhemId|prefix|siteId|encoding|useGenericAttrs|sessionTimeout|handleHotword|experimental|Babble|autoTraining)\z}xm;
    }
    my $err = join q{, }, @unknown;
    return "unknown key(s) in DEF: $err" if @unknown && $init_done;
    Log3( $hash, 1, "[$name] unknown key(s) in DEF: $err") if @unknown;

    $hash->{defaultRoom} = $defaultRoom;
    my $language = $h->{language} // shift @{$anon} // lc AttrVal('global','language','en');
    $hash->{baseUrl} = $Rhasspy;
    initialize_Language($hash, $language) if !defined $hash->{LANGUAGE} || $hash->{LANGUAGE} ne $language;
    $hash->{LANGUAGE} = $language;
    my $defaultdevspec = defined $h->{useGenericAttrs} && $h->{useGenericAttrs} == 0 ? q{room=Rhasspy} : q{genericDeviceType=.+};
    $hash->{devspec} = $h->{devspec} // $defaultdevspec;
    $hash->{fhemId} = $h->{fhemId} // q{fhem};
    initialize_prefix($hash, $h->{prefix}) if !defined $hash->{prefix} || defined $h->{prefix} && $hash->{prefix} ne $h->{prefix};
    $hash->{prefix} = $h->{prefix} // q{rhasspy};
    $hash->{siteId} = $h->{siteId} // qq{${language}$hash->{fhemId}};
    $hash->{encoding} = $h->{encoding} // q{utf8};
    $hash->{useGenericAttrs} = $h->{useGenericAttrs} // 1;
    $hash->{autoTraining} = $h->{autoTraining} // 60;

    for my $key (qw( experimental handleHotword sessionTimeout Babble )) {
        delete $hash->{$key};
        $hash->{$key} = $h->{$key} if defined $h->{$key};
    }
    $hash->{'.asyncQueue'} = [];
    #Beta-User: Für's Ändern von defaultRoom oder prefix vielleicht (!?!) hilfreich: https://forum.fhem.de/index.php/topic,119150.msg1135838.html#msg1135838 (Rudi zu resolveAttrRename) 

    if ($hash->{useGenericAttrs}) {
        addToAttrList(q{genericDeviceType});
    }
    notifyRegexpChanged($hash,'',1);

    return "No Babble device available with name $hash->{Babble}!" if $init_done && defined $hash->{Babble} && InternalVal($hash->{Babble},'TYPE','none') ne 'Babble';

    return $init_done ? firstInit($hash) : InternalTimer(time+1, \&firstInit, $hash );
}

sub firstInit {
    my $hash = shift // return;

    my $name = $hash->{NAME};
    notifyRegexpChanged($hash,'',1) if !$hash->{autoTraining};

    # IO
    AssignIoPort($hash);
    my $IODev = AttrVal( $name, 'IODev', ReadingsVal( $name, 'IODev', defined InternalVal($name, 'IODev', undef ) ? InternalVal($name, 'IODev', undef )->{NAME} : undef ));

    return if !$init_done; # || !defined $IODev;
    RemoveInternalTimer($hash);
    deleteAllRegIntTimer($hash);

    fetchSiteIds($hash) if !ReadingsVal( $name, 'siteIds', 0 );
    initialize_rhasspyTweaks($hash, AttrVal($name,'rhasspyTweaks', undef ));
    initialize_rhasspyHotwords($hash, AttrVal($name,'rhasspyHotwords', undef ));
    fetchIntents($hash);
    delete $hash->{ERRORS};
    if ( !defined InternalVal($name, 'IODev',undef) ) {
        Log3( $hash, 1, "[$name] no suitable IO found, please define one and/or also add :RHASSPY: to clientOrder");
        $hash->{ERRORS} = 'no suitable IO found, please define one and/or also add :RHASSPY: to clientOrder!';
    }
    IOWrite($hash, 'subscriptions', join q{ }, @topics) 
        if defined InternalVal($name, 'IODev',undef) 
        && InternalVal( InternalVal($name, 'IODev',undef)->{NAME}, 'IODev', 'none') eq 'MQTT2_CLIENT';
    initialize_devicemap($hash);
    initialize_msgDialog($hash);
    initialize_SpeechDialog($hash);
    if ( 0 && $hash->{Babble} ) { #deactivated
        InternalVal($hash->{Babble},'TYPE','none') eq 'Babble' ? $sets{Babble} = [qw( optionA optionB )] 
        : Log3($name, 1, "[$name] error: No Babble device available with name $hash->{Babble}!");
    }

    return;
}

sub initialize_Language {
    my $hash = shift // return;
    my $lang = shift // return;
    my $cfg  = shift // AttrVal($hash->{NAME},'languageFile',undef);

    #my $cp = $hash->{encoding} // q{UTF-8};

    #default to english first
    $hash->{helper}->{lng} = $languagevars if !defined $hash->{helper}->{lng} || !$init_done;
    return if !defined $cfg;

    my ($ret, $content) = _readLanguageFromFile($hash, $cfg);
    return $ret if $ret;

    my $decoded;
    #if ( !eval { $decoded  = decode_json(encode($cp,$content)) ; 1 } ) {
    if ( !eval { $decoded  = JSON->new->decode($content) ; 1 } ) {
        Log3($hash->{NAME}, 1, "JSON decoding error in languagefile $cfg: $@");
        return "languagefile $cfg seems not to contain valid JSON!";
    }
    return if !defined $decoded;
    my $slots = $decoded->{slots};

    if ( defined $decoded->{default} && defined $decoded->{user} ) {
        $decoded = _combineHashes( $decoded->{default}, $decoded->{user} );
        Log3($hash->{NAME}, 4, "combined use user specific sentences and defaults provided in $cfg");
    }
    $hash->{helper}->{lng} = _combineHashes( $hash->{helper}->{lng}, $decoded );

    return if !$init_done;

    for my $key (keys %{$slots}) {
        updateSingleSlot($hash, $key, $slots->{$key});
    }
    return if !$hash->{autoTraining};
    resetRegIntTimer( 'autoTraining', time + $hash->{autoTraining}, \&RHASSPY_autoTraining, $hash, 0);
    return;
}

sub initialize_prefix {
    my $hash   = shift // return;
    my $prefix =  shift // q{rhasspy};
    my $old_prefix = $hash->{prefix}; #Beta-User: Marker, evtl. müssen wir uns was für Umbenennungen überlegen...

    return if defined $old_prefix && $prefix eq $old_prefix;
    # provide attributes "rhasspyName" etc. for all devices
    addToAttrList("${prefix}Name",'RHASSPY');
    addToAttrList("${prefix}Room",'RHASSPY');
    addToAttrList("${prefix}Mapping:textField-long",'RHASSPY');
    addToAttrList("${prefix}Group:textField",'RHASSPY');
    addToAttrList("${prefix}Specials:textField-long",'RHASSPY');
    for (devspec2array("${prefix}Colors=.+")) {
        addToDevAttrList($_, "${prefix}Colors:textField-long",'RHASSPY');
    }
    for (devspec2array("${prefix}Channels=.+")) {
        addToDevAttrList($_, "${prefix}Channels:textField-long",'RHASSPY');
    }

    return if !$init_done || !defined $old_prefix;
    my @devs = devspec2array("$hash->{devspec}");
    my @rhasspys = devspec2array("TYPE=RHASSPY:FILTER=prefix=$old_prefix");

    for my $detail ( qw( Name Room Mapping Group Specials Channels Colors ) ) { 
        for my $device (@devs) {
            my $aval = AttrVal($device, "${old_prefix}$detail", undef); 
            CommandAttr($hash, "$device ${prefix}$detail $aval") if $aval;
            CommandDeleteAttr($hash, "$device ${old_prefix}$detail") if @rhasspys < 2;
            delFromDevAttrList($device,"${old_prefix}$detail") if @rhasspys < 2 && ($detail eq "Channels" || $detail eq "Colors");
        }
        delFromAttrList("${old_prefix}$detail") if @rhasspys < 2;
    }

    return;
}


# Device löschen
sub Undefine {
    my $hash = shift // return;

    deleteAllRegIntTimer($hash);
    RemoveInternalTimer($hash);

    return;
}

sub Delete {
    my $hash = shift // return;

    deleteAllRegIntTimer($hash);
    RemoveInternalTimer($hash);

    return;
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

    if ($command eq 'activateVoiceInput') {
        return activateVoiceInput($hash, $anon, $h);
    }

    $dispatch = {
        speak       => \&sendSpeakCommand,
        textCommand => \&sendTextCommand,
        play        => \&setPlayWav,
        volume      => \&setVolume,
        msgDialog   => \&msgDialog
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
            deleteSingleRegIntTimer('autoTraining', $hash);
            return updateSlots($hash);
        }
        if ($values[0] eq 'devicemap_only') {
            return initialize_devicemap($hash);
        }
        if ($values[0] eq 'slots') {
            $hash->{'.needTraining'} = 1;
            deleteSingleRegIntTimer('autoTraining', $hash);
            return updateSlots($hash);
        }
        if ($values[0] eq 'slots_no_training') {
            initialize_devicemap($hash);
            return updateSlots($hash);
        }
        if ($values[0] eq 'intent_filter') {
            return fetchIntents($hash);
        }
        if ($values[0] eq 'all') {
            initialize_Language($hash, $hash->{LANGUAGE});
            initialize_devicemap($hash);
            deleteSingleRegIntTimer('autoTraining', $hash);
            $hash->{'.needTraining'} = 1;
            updateSlots($hash);
            return fetchIntents($hash);
        }
    }

    if ($command eq 'customSlot') {
        my $slotname = $h->{slotname}  // shift @values;
        my $slotdata = $h->{slotdata}  // shift @values;
        my $overwr   = $h->{overwrite} // shift @values;
        my $training = $h->{training}  // shift @values;
        return updateSingleSlot($hash, $slotname, $slotdata, $overwr, $training);
    }

    if ($command eq 'Babble') {
        if ($values[0] eq 'optionA') {
            return "rhasspy command Babble A called";
        }
        if ($values[0] eq 'optionB') {
            return "rhasspy command Babble B called";
        }
    }

    if ($command eq 'sayFinished') {
        my $data;
        $data->{id}     = $h->{id}     // shift @values // return;
        my $siteId = $h->{siteId} // shift @values;
        return sayFinished($hash,$data,$siteId);
    }

    return;
}


sub Get {
    my $hash    = shift;
    my $anon    = shift;
    my $h       = shift;

    my $name    = shift @{$anon};
    my $command = shift @{$anon} // q{};
    my @values  = @{$anon};
    return "Unknown argument $command, choose one of " 
    . join(q{ }, map {
        @{$gets{$_}} ? $_
                      .q{:}
                      .join q{,}, @{$gets{$_}} : $_} sort keys %gets)

    if !defined $gets{$command};
    
    if ($command eq 'export_mapping') {
        my $device = shift @{$anon} // return 'no device provided';
        return 'no device from devicemap provided'
            if !defined $hash->{helper}{devicemap} 
                || !defined $hash->{helper}{devicemap}{devices}
                || !defined $hash->{helper}{devicemap}{devices}{$device};
        return exportMapping($hash, $device);
    }

    if ($command eq 'test_file') {
        return 'provide a filename' if !@values;
        if ( $values[0] ne 'stop' && !defined $hash->{testline} ) {
            if($hash->{CL}) {
                my $start = gettimeofday();
                my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=> 'testResult', start=>$start};
                $hash->{asyncGet} = $tHash;
                InternalTimer(gettimeofday()+30, sub {
                  asyncOutput($tHash->{CL}, "Test file $values[0] is initiated. See if internal 'testline' is rising and check testResult reading later");
                  delete($hash->{asyncGet});
                }, $tHash, 0);
            }
            return testmode_start($hash, $values[0]);
        }
    }

    if ($command eq 'test_sentence') {
        return 'provide a sentence' if !@values;
        if ( !defined $hash->{testline} ) {
            if($hash->{CL}) {
                my $start = gettimeofday();
                my $tHash = { hash=>$hash, CL=>$hash->{CL}, reading=> 'testResult', start=>$start};
                $hash->{asyncGet} = $tHash;
                InternalTimer(gettimeofday()+4, sub { delete $hash->{testline};
                  asyncOutput($tHash->{CL}, "Timeout for test sentence - most likely this is no problem, check testResult reading later, but either intent was not recognized, RHASSPY's siteId is not configured for NLU or your system seems to be rather slow...");
                  delete($hash->{asyncGet});
                }, $tHash, 0);
            }
            my $test = join q{ }, @values;
            $hash->{testline} = 0;
            $hash->{helper}->{test}->{content} = [$test];
            $hash->{helper}->{test}->{filename} = 'none';
            return testmode_next($hash);
        }
    }

    delete $hash->{testline};
    delete $hash->{helper}->{test};
    readingsSingleUpdate($hash,'testResult','Test mode stopped (might have been running already)',1);
    return 'Test mode stopped (might have been running already)';
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
            return initialize_rhasspyTweaks($hash, $value) if $init_done;
        } 
    }

    if ( $attribute eq 'rhasspyHotwords' ) {
        for ( keys %{ $hash->{helper}{hotwords} } ) {
            delete $hash->{helper}{hotwords}{$_};
        }
        delete $hash->{helper}{hotwords};
        if ($command eq 'set') {
            return initialize_rhasspyHotwords($hash, $value) if $init_done;
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

    if ( $attribute eq 'rhasspyMsgDialog' ) {
        delete $hash->{helper}{msgDialog};
        return if !$init_done;
        return initialize_msgDialog($hash, $value, $command);
    }

    if ( $attribute eq 'rhasspyTTS' ) {
        delete $hash->{helper}{TTS};
        return if !$init_done;
        return initialize_TTS($hash, $value, $command);
    }

    if ( $attribute eq 'rhasspySpeechDialog' ) {
        delete $hash->{helper}{SpeechDialog};
        return if !$init_done;
        return initialize_SpeechDialog($hash, $value, $command);
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

        if ($line =~ m{\A[\s]*(timeouts|useGenericAttrs|timerSounds|confirmIntents|confirmIntentResponses|ignoreKeywords|gdt2groups)[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            $tweak = trim($tweak);
            return "Error in $line! No content provided!" if !length $values && $init_done;
            my($unnamedParams, $namedParams) = parseParams($values);
            return "Error in $line! Provide at least one key-value pair!" if ( @{$unnamedParams} || !keys %{$namedParams} ) && $init_done;
            $hash->{helper}{tweaks}{$tweak} = $namedParams;
            next;
        }
        if ($line =~ m{\A[\s]*(intentFilter)[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            $tweak = trim($tweak);
            return "Error in $line! No content provided!" if !length $values && $init_done;
            my($unnamedParams, $namedParams) = parseParams($values);
            return "Error in $line! Provide at least one item!" if ( !@{$unnamedParams} && !keys %{$namedParams} ) && $init_done;
            for ( @{$unnamedParams} ) {
                $namedParams->{$_} = 'false';
            }
            for ( keys %{$namedParams} ) {
                $namedParams->{$_} = 'false' if $namedParams->{$_} ne 'false' && $namedParams->{$_} ne 'true';
            }
            $hash->{helper}{tweaks}{$tweak} = $namedParams;
            next;
        }
        if ($line =~ m{\A[\s]*(extrarooms)[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            $tweak = trim($tweak);
            $values= join q{,}, split m{[\s]*,[\s]*}x, $values;
            return "Error in $line! No content provided!" if !length $values && $init_done;
            $hash->{helper}{tweaks}{$tweak} = $values;
            next;
        }
        if ($line =~ m{\A[\s]*(confidenceMin)[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            return "Error in $line! No content provided!" if !length $values && $init_done;
            my($unnamedParams, $namedParams) = parseParams($values);
            delete $hash->{helper}{tweaks}{confidenceMin};
            return "Error in $line! Provide at least one item!" if ( !@{$unnamedParams} && !keys %{$namedParams} ) && $init_done;
            for ( keys %{$namedParams} ) {
                $hash->{helper}{tweaks}{confidenceMin}->{$_} = $namedParams->{$_} if looks_like_number($namedParams->{$_});
            }
            $hash->{helper}{tweaks}{confidenceMin}{default} = $unnamedParams->[0] if @{$unnamedParams} && looks_like_number($unnamedParams->[0]);
        }
        if ($line =~ m{\A[\s]*(mappingOverwrite)[\s]*=}x) {
            ($tweak, $values) = split m{=}x, $line, 2;
            $tweak = trim($tweak);
            $values= trim($values);
            return "Error in $line! No content provided!" if !length $values && $init_done;
            $hash->{helper}{tweaks}{$tweak} = $values;
        }
    }
    return configure_DialogManager($hash) if $init_done;
    return;
}

sub configure_DialogManager {
    my $hash      = shift // return;
    my $siteId    = shift // 'null'; #ReadingsVal( $hash->{NAME}, 'siteIds', 'default' ) // return;
    my $toDisable = shift // [qw(ConfirmAction CancelAction Choice ChoiceRoom ChoiceDevice)];
    my $enable    = shift // q{false};
    my $timer     = shift;
    my $retArr    = shift;

    #option to delay execution to make reconfiguration last action after everything else has been done and published.
    if ( defined $timer ) {
        
        my $fnHash = resetRegIntTimer( $siteId, time + looks_like_number($timer) ? $timer : 0, \&RHASSPY_configure_DialogManager, $hash, 0);
        $fnHash->{toDisable} = $toDisable;
        $fnHash->{enable}    = $enable;
        return;
    }

    #loop for global initialization or for several siteId's
    if ( $siteId =~ m{,}xms ) {
        my @siteIds = split m{,}xms, $siteId;
        for (@siteIds) {
            configure_DialogManager($hash, $_, $toDisable, $enable);
        }
        return;
    }

    my @intents  = split m{,}xm, ReadingsVal( $hash->{NAME}, 'intents', '' );
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
    my $matches = join q{|}, @{$toDisable};
    for (@intents) {
        last if $enable eq 'true';
        next if $_ =~ m{$matches}xms;
        my $defaults = {intentId => "$_", enable => 'true'} ;
        $defaults = {intentId => "$_", enable => $hash->{helper}{tweaks}->{intentFilter}->{$_}} if defined $hash->{helper}->{tweaks} && defined $hash->{helper}{tweaks}->{intentFilter} && defined $hash->{helper}{tweaks}->{intentFilter}->{$_};
        push @disabled, $defaults;
    }
    for (@{$toDisable}) {
        my $id = qq(${language}.${fhemId}:$_);
        my $disable = {intentId => "$id", enable => "$enable"};
        push @disabled, $disable;
    }

    return \@disabled if $retArr;

    my $sendData = {
        siteId  => $siteId,
        intents => [@disabled]
    };

    my $json = _toCleanJSON($sendData);

    IOWrite($hash, 'publish', qq{hermes/dialogueManager/configure $json});
    return;
}


sub RHASSPY_configure_DialogManager {
    my $fnHash = shift // return;
    return configure_DialogManager( $fnHash->{HASH}, $fnHash->{MODIFIER}, $fnHash->{toDisable}, $fnHash->{enable} );
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
                }xms;                                         ##no critic qw(Capture)
        my $intent = trim($+{intent});
        return "no intent found in $line!" if (!$intent || $intent eq q{}) && $init_done;
        my $function = trim($+{function});
        return "invalid function in line $line" if $function =~ m{\s+}x;
        my $perlcommand = trim($+{perlcommand});
        my $err = perlSyntaxCheck( $perlcommand );
        return "$err in $line" if $err && $init_done;

        $hash->{helper}{custom}{$intent}{function} = $function;

        my $args = trim($+{arg});
        my @params;
        for my $ar (split m{,}x, $args) {
           $ar =trim($ar);
           #next if $ar eq q{}; #Beta-User having empty args might be intented...
           push @params, $ar;
        }

        $hash->{helper}{custom}{$intent}{args} = \@params;
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
    InternalTimer(time+125, \&initialize_devicemap, $hash ) if $fhem_started + 90 > time;
    return;
}

sub RHASSPY_autoTraining {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;

    return updateSlots($hash, 1);
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
           && !defined AttrVal($device,"${prefix}Specials",undef)
           && !defined AttrVal($device,"${prefix}Mapping",undef);

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
    delete $hash->{helper}{devicemap}{devices}{$device}{intents} if $mappingsString && defined $hash->{helper}->{tweaks} && $hash->{helper}{tweaks}->{mappingOverwrite};
    my @dones;
    for (split m{\n}x, $mappingsString) {
        my ($key, $val) = split m{:}x, $_, 2;
        next if !$val;
        delete $hash->{helper}{devicemap}{devices}{$device}{intents}->{$key} if !grep {$key} @dones;
        push @dones, $key;
        my $currentMapping = splitMappingString($val) // next;
        # Übersetzen, falls möglich:
        $currentMapping->{type} //= $key;
        $hash->{helper}{devicemap}{devices}{$device}{intents}{$key}->{$currentMapping->{type}} = $currentMapping;
    }

    #Specials
    my @lines = split m{\n}x, AttrVal($device, "${prefix}Specials", q{});
    for my $line (@lines) {
        my ($key, $val) = split m{:}x, $line, 2;
        next if !$val; 

        if ($key eq 'colorForceHue2rgb') {
            $hash->{helper}{devicemap}{devices}{$device}{color_specials}{forceHue2rgb} = $val;
        }

        my($unnamed, $named) = parseParams($val);
        if ($key eq 'group') {
            my $specials = {};
            my $partOf = $named->{partOf} // shift @{$unnamed};
            $specials->{partOf} = $partOf if defined $partOf;
            $specials->{async_delay} = $named->{async_delay} if defined $named->{async_delay};
            $specials->{prio} = $named->{prio} if defined $named->{prio};

            $hash->{helper}{devicemap}{devices}{$device}{group_specials} = $specials;
        }
        if ($key eq 'colorCommandMap') {
            $hash->{helper}{devicemap}{devices}{$device}{color_specials}{CommandMap} = $named if defined $named;
        }
        if ($key eq 'colorTempMap') {
            $hash->{helper}{devicemap}{devices}{$device}{color_specials}{Colortemp} = $named if defined $named;
        }
        if ($key eq 'numericValueMap') {
            $hash->{helper}{devicemap}{devices}{$device}{numeric_ValueMap} = $named if defined $named;
        }
        if ($key eq 'venetianBlind') {
            my $specials = {};
            my $vencmd = $named->{setter} // shift @{$unnamed};
            my $vendev = $named->{device} // shift @{$unnamed};
            $specials->{setter} = $vencmd if defined $vencmd;
            $specials->{device} = $vendev if defined $vendev;
            $specials->{CustomCommand} = $named->{CustomCommand} if defined $named->{CustomCommand};
            $specials->{stopCommand}   = $named->{stopCommand}   if defined $named->{stopCommand};

            $hash->{helper}{devicemap}{devices}{$device}{venetian_specials} = $specials if defined $vencmd || defined $vendev;
        }
        if ($key eq 'priority') {
            $hash->{helper}{devicemap}{devices}{$device}{prio}{inRoom} = $named->{inRoom} if defined $named->{inRoom};
            $hash->{helper}{devicemap}{devices}{$device}{prio}{outsideRoom} = $named->{outsideRoom} if defined $named->{outsideRoom};
        }
        if ( $key eq 'scenes' && defined $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene} ) {
            my $combined = _combineHashes( $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene}, $named);
            for (keys %{$combined}) {
                delete $combined->{$_} if $combined->{$_} eq 'none' || defined $named->{all} && $named->{all} eq 'none' || defined $named->{rest} && $named->{rest} eq 'none' && !defined $named->{$_};
            }
            keys %{$combined} ?
                $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene} = $combined
                : delete $hash->{helper}{devicemap}{devices}{$device}{intents}->{SetScene};
        }
        if ($key eq 'confirm') {
            #my($unnamed, $named) = parseParams($val);
            $hash->{helper}{devicemap}{devices}{$device}{confirmIntents} = join q{,}, (@{$unnamed}, keys %{$named});
            $hash->{helper}{devicemap}{devices}{$device}{confirmIntentResponses} = $named if $named;
        }
        if ($key eq 'confirmValueMap') {
            $hash->{helper}{devicemap}{devices}{$device}{confirmValueMap} = $named if $named;
        }
        if ($key eq 'blacklistIntents') {
            $hash->{helper}{devicemap}{devices}{$device}{blacklistIntents} = $val;
            for ( keys %{$named} ) {
                delete $hash->{helper}{devicemap}{devices}{$device}{intents}{$named->{$_}};
            }
            for ( @{$unnamed} ) {
                delete $hash->{helper}{devicemap}{devices}{$device}{intents}{$_};
            }
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

        $attrv = AttrVal($device,'gassistantName',undef);
        push @names, split m{,}x, lc $attrv if $attrv;

        my $alias = lc AttrVal($device,'alias',$device);
        $names[0] = $alias if !@names;
    }
    $hash->{helper}{devicemap}{devices}{$device}->{alias} = $names[0] if $names[0];

    @names = get_unique(\@names);
    $hash->{helper}{devicemap}{devices}{$device}->{names} = join q{,}, @names if $names[0];

    my @rooms;
    if (!defined AttrVal($device,"${prefix}Room", undef)) {
        $attrv = _clean_ignored_keywords( $hash,'rooms', AttrVal($device,'alexaRoom', undef));
        push @rooms, split m{,}x, $attrv if $attrv;

        $attrv = _clean_ignored_keywords( $hash,'rooms', AttrVal($device,'room',undef));
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

    $attrv = _clean_ignored_keywords( $hash,'group', AttrVal($device,'group', undef));
    if ( defined $hash->{helper}->{tweaks} && defined $hash->{helper}->{tweaks}->{gdt2groups} && defined $hash->{helper}->{tweaks}->{gdt2groups}->{$gdt} ) {
       $attrv = $attrv ? "$attrv,$hash->{helper}->{tweaks}->{gdt2groups}->{$gdt}" : $hash->{helper}->{tweaks}->{gdt2groups}->{$gdt};
    }
    $hash->{helper}{devicemap}{devices}{$device}{groups} = $attrv if $attrv;

    my $allset = getAllSets($device);
    my $currentMapping;

    if ( $gdt eq 'switch' || $gdt eq 'light') {
        my ($on, $off) = _getGenericOnOff($allset);
        $currentMapping = 
            { GetOnOff => { GetOnOff => {currentVal => 'state', type => 'GetOnOff', valueOff => lc $off }}, 
              SetOnOff => { SetOnOff => {cmdOff => $off, type => 'SetOnOff', cmdOn => $on}}
            } if defined $on;
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
        $currentMapping = _analyze_genDevType_setter( $hash, $device, $allset, $currentMapping );
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
        return;
    }

    if ( $gdt eq 'thermostat' ) {
        my $desTemp = $allset =~ m{\b(desiredTemp|desired)([\b:\s]|\Z)}xms ? $1 : 'desired-temp';
        my $measTemp = InternalVal($device, 'TYPE', 'unknown') eq 'CUL_HM' ? 'measured-temp' : 'temperature';
        $currentMapping = 
            { GetNumeric => { 'desired-temp' => {currentVal => $desTemp, type => 'desired-temp'},
            temperature => {currentVal => $measTemp, type => 'temperature'}}, 
            SetNumeric => {'desired-temp' => { cmd => $desTemp, currentVal => $desTemp, maxVal => '28', minVal => '10', step => '0.5', type => 'temperature'}}
            };
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
        return;
    }

    if ( $gdt eq 'thermometer' || $gdt eq 'HumiditySensor' ) {
        my $r = $defs{$device}{READINGS};
        if($r) {
            for (sort keys %{$r}) {
                if ( $_ =~ m{\A(?<id>temperature|humidity)\z}x ) {
                    $currentMapping->{GetNumeric}->{$+{id}} = {currentVal => $+{id}, type => $+{id} };
                }
            }
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
        return;
    }

    if ( $gdt eq 'blind' || $gdt eq 'blinds' || $gdt eq 'shutter' ) {
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
        } else {
            my ($on, $off) = _getGenericOnOff($allset);
            $currentMapping = { 
                GetOnOff => { GetOnOff => {currentVal => 'state', type => 'GetOnOff', valueOff => lc $off }}, 
                SetOnOff => { SetOnOff => {cmdOff => $off, type => 'SetOnOff', cmdOn => $on}}
              } if defined $on;
        }
        if ( $allset =~ m{\b(stop)([\b:\s]|\Z)}xmsi ) {
            $currentMapping->{SetNumeric}->{setTarget}->{cmdStop} = $1;
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
        return;
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

    if ( $gdt eq 'motion' || $gdt eq 'contact' || $gdt eq 'ContactSensor' || $gdt eq 'lock' || $gdt eq 'presence') {
        my $r = $defs{$device}{READINGS};
        $gdt = 'contact' if $gdt eq 'ContactSensor';
        if($r) {
            for (sort reverse keys %{$r}) {
                if ( $_ =~ m{\A(?<id>state|$gdt)\z}x ) {
                    $currentMapping->{GetState}->{$gdt} = {currentVal => $+{id}, type => '$gdt' };
                }
            }
        }
        if ( $gdt eq 'lock') {
            $currentMapping->{SetOnOff} = {cmdOff => 'unlock', type => 'SetOnOff', cmdOn => 'lock'};
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
        return;
    }

    if ( $gdt eq 'info' ) {
        $currentMapping->{GetState}->{$gdt} = {currentVal => 'STATE', type => 'STATE' };
        $currentMapping = _analyze_genDevType_setter( $hash, $device, $allset, $currentMapping );
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    if ( $gdt eq 'scene' ) {
        $currentMapping = _analyze_genDevType_setter( $hash, $device, $allset, $currentMapping );
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    return;
}

sub _getGenericOnOff {
    my $allset = shift // return (undef,undef);
    my $onoff_map= {
        'on'    => 'off',
        'open'  => 'close',
        '1'     => '0',
        'an'    => 'aus',
        'auf'   => 'zu',
        'offen' => 'zu'
        };
    my @onwords = qw(on open an auf 1);
    for (@onwords) {
        next if $allset !~ m{\b($_)([\b:\s]|\Z)}xmsi;               ##no critic qw(Capture)
        my $on = $1;                                                ##no critic qw(Capture)
        next if $allset !~ m{\b($onoff_map->{$_})([\b:\s]|\Z)}xmsi; ##no critic qw(Capture)
        return ($on,$1);                                            ##no critic qw(Capture)
    }
    return (undef,undef);
}

sub _clean_ignored_keywords {
    my $hash    = shift // return;
    my $keyword = shift // return;
    my $toclean = shift // return;
    return lc $toclean if !defined $hash->{helper}->{tweaks}
                        ||!defined $hash->{helper}->{tweaks}->{ignoreKeywords}
                        ||!defined $hash->{helper}->{tweaks}->{ignoreKeywords}->{$keyword};
    $toclean =~ s{\A$hash->{helper}->{tweaks}->{ignoreKeywords}->{$keyword}\z}{}gxi;
    return lc $toclean;
}

sub _analyze_genDevType_setter {
    my $hash    = shift;
    my $device  = shift;
    my $setter  = shift;
    my $mapping = shift // {};

    my $allValMappings = {
        MediaControls => {
            cmdPlay => 'play', cmdPause => 'pause' ,cmdStop => 'stop', cmdBack => 'previous', cmdFwd => 'next', chanUp => 'channelUp', chanDown => 'channelDown' },
        GetState => {
            update => 'reread|update|reload' },
        SetScene => {
            cmdBack => 'previousScene', cmdFwd => 'nextScene' }
        };
    for my $okey ( keys %{$allValMappings} ) {
        my $ikey = $allValMappings->{$okey};
        for ( keys %{$ikey} ) {
            my $val = $ikey->{$_};
            $mapping->{$okey}->{$okey}->{$_} = $1 if $setter =~ m{\b($val)(?:[\b:\s]|\Z)}xmsi;
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

    if ($setter =~ m{\bscene:(?<scnames>[\S]+)}xm) {            ##no critic qw(Capture)
        for my $scname (split m{,}xms, $+{scnames}) {
            my $clscene = $scname;
            # cleanup HUE scenes
            if ($clscene =~ m{[#]}xms) {
                $clscene = (split m{[#]\[id}xms, $clscene)[0] if $clscene =~ m{[#]\[id}xms; 
                $clscene =~ s{[#]}{ }gxm;
                $scname =~ s{.*[#]\[(id=.+)]}{$1}xms if $scname =~ m{[#]\[id}xms;
                $scname =~ s{[#]}{ }gxm;
            }
            $mapping->{SetScene}->{SetScene}->{$scname} = $clscene;
        }
    }
    return $mapping;
}

sub initialize_rhasspyHotwords {
    my $hash    = shift // return;
    my $attrVal = shift // return;

    for my $line (split m{\n}x, $attrVal) {
        next if !length $line;
        my ($hotword, $values) = split m{=}x, $line, 2;
        my($unnamed, $named) = parseParams($values);
        for my $site ( keys %{$named} ) {
            if ( $named->{$site} =~ m{\A\{.*\}\z}x) {
                my $err = perlSyntaxCheck( $named->{$site}, ("%DEVICE"=>"$hash->{NAME}", "%VALUE"=>"test", "%ROOM"=>"room") );
                return "$err in $line, $named->{$site}" if $err && $init_done;
            }
        }
        $hotword = trim($hotword);
        next if !$hotword;
        if ( keys %{$named} ) {
            $hash->{helper}{hotwords}->{$hotword} = $named;
        } elsif (@{$unnamed}) {
            $hash->{helper}{hotwords}->{$hotword}->{default} = join q{ }, @{$unnamed};
        }
    }
    return;
}


sub initialize_SpeechDialog {
    my $hash    = shift // return;
    my $attrVal = shift // AttrVal($hash->{NAME},'rhasspySpeechDialog',undef) // return;
    my $mode    = shift // 'set';

    for my $line (split m{\n}x, $attrVal) {
        next if !length $line;
        my ($keywd, $values) = split m{=}x, $line, 2;
        $keywd  = trim($keywd);
        $values = trim($values);
        next if !$values;

        if ( $keywd =~ m{\Aallowed\z}xms ) {
            for my $amads (split m{[\b]*,[\b]*}x,$values) {
                if ( InternalVal($amads,'TYPE','unknown') ne 'AMADDevice' ) {
                    return "$amads is not an AMADDevice!" if $init_done;
                    Log3($hash, 2, "[RHASSPY] $amads in rhasspySpeechDialog is not an AMADDevice!");
                }
            }
            $hash->{helper}->{SpeechDialog}->{config}->{$keywd} = $values;
            $hash->{helper}->{SpeechDialog}->{config}->{AMADCommBridge} = 1;
            disable_msgDialog( $hash, ReadingsVal($hash->{NAME}, 'enableMsgDialog', 1), 1 );
            next;
        }

        if ( $keywd =~ m{\AfilterFromBabble\z}xms ) {
            if ( !defined $hash->{Babble} ) {
                return "Babble useage has to be activated in DEF first!" if $init_done;
                Log3($hash, 2, "[RHASSPY] filterFromBabble in rhasspySpeechDialog not activated, Babble useage has to be activated in DEF first!");
            }
            $hash->{helper}->{SpeechDialog}->{config}->{$keywd} = _toregex($values);
            next;
        }

        if ( $keywd =~ m{\b$hash->{helper}->{SpeechDialog}->{config}->{allowed}(?:[\b:\s]|\Z)}xms ) {
            my($unnamedParams, $namedParams) = parseParams($values);
            $hash->{helper}->{SpeechDialog}->{config}->{$keywd} = $namedParams;
            $hash->{helper}->{SpeechDialog}->{config}->{wakeword}->{$namedParams->{wakeword}} = $keywd if defined $namedParams->{wakeword};
            $sets{sayFinished} = [];
        }
    }

    if ( !defined $hash->{helper}->{SpeechDialog}->{config}->{allowed} ) {
        delete $hash->{helper}->{SpeechDialog};
        disable_msgDialog($hash, ReadingsVal($hash->{NAME}, 'enableMsgDialog', 1), 1 );
        return 'Setting the allowed key in rhasspySpeechDialog is mandatory!' if $init_done;
    }

    return;
}



sub initialize_msgDialog {
    my $hash    = shift // return;
    my $attrVal = shift // AttrVal($hash->{NAME},'rhasspyMsgDialog',undef) // '';
    my $mode    = shift // 'set';

    return disable_msgDialog($hash) if $mode ne 'set';

    return 'No global configuration device defined: Please define a msgConfig device first' if !$modules{msgConfig}{defptr} && $attrVal;
    for my $line (split m{\n}x, $attrVal) {
        next if !length $line;
        my ($keywd, $values) = split m{=}x, $line, 2;
        if ( $keywd =~ m{\Aallowed|msgCommand|hello|goodbye|querymark|sessionTimeout\z}xms ) {
            $hash->{helper}->{msgDialog}->{config}->{$keywd} = trim($values);
            next;
        }
        if ( $keywd =~ m{\Aopen|close\z}xms ) {
            $hash->{helper}->{msgDialog}->{config}->{$keywd} = _toregex($values);
            next;
        }
    }

    return disable_msgDialog($hash) if !$attrVal || !keys %{$hash->{helper}->{msgDialog}->{config}};
    if ( !defined $hash->{helper}->{msgDialog}->{config}->{allowed} ) {
        delete $hash->{helper}->{msgDialog};
        return 'Setting the allowed key is mandatory!' ;
    }
    $hash->{helper}->{msgDialog}->{config}->{open}       //= q{hi.rhasspy};
    $hash->{helper}->{msgDialog}->{config}->{close}      //= q{close};
    $hash->{helper}->{msgDialog}->{config}->{hello}      //= q{Hi $you! What can I do for you?|at your service|There you go again!};
    $hash->{helper}->{msgDialog}->{config}->{goodbye}    //= q{Till next time.|Bye|CU|Cheers!|so long};
    $hash->{helper}->{msgDialog}->{config}->{querymark}  //= q{this is a feminine request};
    $hash->{helper}->{msgDialog}->{config}->{sessionTimeout} //= $hash->{sessionTimeout} // _getDialogueTimeout($hash);

    my $msgConfig  = $modules{msgConfig}{defptr}{NAME};
    #addToDevAttrList($msgConfig, "$hash->{prefix}EvalSpecials:textField-long ",'RHASSPY');
    addToDevAttrList($msgConfig, "$hash->{prefix}MsgCommand:textField ",'RHASSPY');
    if (!defined $hash->{helper}->{msgDialog}->{config}->{msgCommand} ) {
        $hash->{helper}->{msgDialog}->{config}->{msgCommand}
                = AttrVal($msgConfig, "$hash->{prefix}MsgCommand", q{msg push \@$recipients $message});
    }
    return disable_msgDialog($hash, 1, 1);

}

sub disable_msgDialog {
    my $hash    = shift // return;
    my $enable  = shift // 0;
    my $fromSTT = shift;
    readingsSingleUpdate($hash,'enableMsgDialog',$enable,1) if !$fromSTT;
    return initialize_msgDialog($hash) if $enable && !$fromSTT;

    my $devsp;
    if ( defined $hash->{helper}->{SpeechDialog} 
        && defined $hash->{helper}->{SpeechDialog}->{config}
        && defined $hash->{helper}->{SpeechDialog}->{config}->{AMADCommBridge} ) {
            $devsp = 'TYPE=(AMADCommBridge|AMADDevice)';
    }
    if ( $enable ) { 
        $devsp = $devsp ? 'TYPE=(AMADCommBridge|AMADDevice|ROOMMATE|GUEST)' : 'TYPE=(ROOMMATE|GUEST)';
    }
    if ( $hash->{autoTraining} ) {
        $devsp .= ',global' if $devsp;
        $devsp = 'global' if !$devsp;
    }

    if ( $devsp && devspec2array($devsp) ) {
        delete $hash->{disableNotifyFn};
        setNotifyDev($hash,$devsp);
    } else {
        notifyRegexpChanged($hash,'',1);
    }

    delete $hash->{helper}{msgDialog} if !$enable;
    return;
}

#Make globally available to allow later use by other functions, esp.  handleIntentConfirmAction
my $dispatchFns = {
    Shortcuts           => \&handleIntentShortcuts, 
    SetOnOff            => \&handleIntentSetOnOff,
    SetOnOffGroup       => \&handleIntentSetOnOffGroup,
    SetTimedOnOff       => \&handleIntentSetTimedOnOff,
    SetTimedOnOffGroup  => \&handleIntentSetTimedOnOffGroup,
    GetOnOff            => \&handleIntentGetOnOff,
    SetNumeric          => \&handleIntentSetNumeric,
    SetNumericGroup     => \&handleIntentSetNumericGroup,
    GetNumeric          => \&handleIntentGetNumeric,
    GetState            => \&handleIntentGetState,
    MediaControls       => \&handleIntentMediaControls,
    MediaChannels       => \&handleIntentMediaChannels,
    SetColor            => \&handleIntentSetColor,
    SetColorGroup       => \&handleIntentSetColorGroup,
    SetScene            => \&handleIntentSetScene,
    GetTime             => \&handleIntentGetTime,
    GetDate             => \&handleIntentGetDate,
    SetTimer            => \&handleIntentSetTimer,
    GetTimer            => \&handleIntentGetTimer,
    Timer               => \&handleIntentSetTimer,
    ConfirmAction       => \&handleIntentConfirmAction,
    CancelAction        => \&handleIntentCancelAction,
    ChoiceRoom          => \&handleIntentChoiceRoom,
    ChoiceDevice        => \&handleIntentChoiceDevice,
    Choice              => \&handleIntentChoice,
    MsgDialog           => \&handleIntentMsgDialog,
    ReSpeak             => \&handleIntentReSpeak
};


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

sub _AnalyzeCommand {
    my $hash   = shift // return;
    my $cmd    = shift // return;

    if ( defined $hash->{testline} ) {
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Command: ${cmd}";
        return;
    }
    # CMD ausführen
    return AnalyzeCommand( $hash, $cmd );
}

sub RHASSPY_DialogTimeout {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;

    my $identity = $fnHash->{MODIFIER};

    my $data     = shift // $hash->{helper}{'.delayed'}->{$identity};
    my $siteId = $data->{siteId};

    deleteSingleRegIntTimer($identity, $hash, 1);

    respond( $hash, $data, getResponse( $hash, 'DefaultConfirmationTimeout' ) );
    delete $hash->{helper}{'.delayed'}{$identity};

    return;
}

sub setDialogTimeout {
    my $hash     = shift // return;
    my $data     = shift // return;
    my $timeout  = shift // _getDialogueTimeout($hash);
    my $response = shift;
    my $toEnable = shift // [qw(ConfirmAction CancelAction)];

    my $siteId = $data->{siteId};
    $data->{'.ENABLED'} = $toEnable; #dialog 
    my $identity = qq($data->{sessionId});

    $response = getResponse($hash, 'DefaultConfirmationReceived') if ref $response ne 'HASH' && $response eq 'default';
    $hash->{helper}{'.delayed'}{$identity} = $data;

    resetRegIntTimer( $identity, time + $timeout, \&RHASSPY_DialogTimeout, $hash, 0);

    #interactive dialogue as described in https://rhasspy.readthedocs.io/en/latest/reference/#dialoguemanager_continuesession and https://docs.snips.ai/articles/platform/dialog/multi-turn-dialog
    my @ca_strings;
    $toEnable = split m{,}xms, $toEnable if ref $toEnable ne 'ARRAY';
    if (ref $toEnable eq 'ARRAY') {
        for (@{$toEnable}) {
            my $id = qq{$hash->{LANGUAGE}.$hash->{fhemId}:$_};
            push @ca_strings, $id;
        }
    }

    my $reaction = ref $response eq 'HASH' 
        ? $response
        : { text         => $response, 
            intentFilter => [@ca_strings],
            sendIntentNotRecognized => 'true', #'false',
            customData => $data->{customData}
          };

    respond( $hash, $data, $reaction );

    my $toTrigger = $hash->{'.toTrigger'} // $hash->{NAME};
    delete $hash->{'.toTrigger'};

    return $toTrigger;
}

sub get_unique {
    my $arr    = shift;
    my $sorted = shift; #true if shall be sorted (longest first!)

    my @unique = uniq @{$arr};
    return if !@unique;

    return @unique if !$sorted;

    my @sorted = sort { length($b) <=> length($a) } @unique;
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


# Get all room names with Rhasspy relevance
sub getAllRhasspyRooms {
    my $hash = shift // return;
    return keys %{$hash->{helper}{devicemap}{rhasspyRooms}} if defined $hash->{helper}{devicemap};
    return;
}

sub getAllRhasspyMainRooms {
    my $hash = shift // return;
    return if !$hash->{useGenericAttrs};
    my @devs = devspec2array("$hash->{devspec}");
    my @mainrooms = ();
    for my $device (@devs) {
        push @mainrooms, (split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{rooms})[0];
    }
    push @mainrooms, split m{,}x, $hash->{helper}{tweaks}->{extrarooms} if defined $hash->{helper}->{tweaks} && defined $hash->{helper}{tweaks}->{extrarooms};
    return get_unique(\@mainrooms, 1 );
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
        my $devgroups = $hash->{helper}{devicemap}{devices}{$device}->{groups} // q{};
        for (split m{,}xi, $devgroups ) {
                push @groups, $_;
        }
    }
    return get_unique(\@groups, 1);
}

# get a list of all used scenes
sub getAllRhasspyScenes {
    my $hash = shift // return;
    
    my @devices = devspec2array($hash->{devspec});
    
    my (@sentences, @names);
    for my $device (@devices) {
        next if !defined $hash->{helper}{devicemap}{devices}{$device}{intents}->{SetScene};
        push @names, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{names}; 
        my $scenes = $hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene};
        for (keys %{$scenes}) {
            push @sentences, qq{( $scenes->{$_} ){Scene:$_}} if $_ ne 'cmdBack' && $_ ne 'cmdFwd' ;
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
        push @groups, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{groups} if defined $hash->{helper}{devicemap}{devices}{$device}->{groups}; 
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

    my $siteId = $data->{siteId} // return $hash->{defaultRoom};

    my $rreading = makeReadingName("siteId2room_$siteId");
    $siteId =~ s{\A([^.]+).*}{$1}xms;
    utf8::downgrade($siteId, 1);
    $room = ReadingsVal($hash->{NAME}, $rreading, lc $siteId);
    if ($room eq 'default' || !(length $room)) {
        $room = $hash->{defaultRoom};
        Log3($hash->{NAME}, 5, "default room used");
    } else {
        Log3($hash->{NAME}, 5, "room is identified using siteId as $room");
    }

    return $room;
}


# Gerät über Raum und Namen suchen.
sub getDeviceByName {
    my $hash   = shift // return;
    my $room   = shift;
    my $name   = shift; #either of the two required
    my $droom  = shift; #oiginally included in $data?
    my $type   = shift; #for priority outside room
    my $intent = shift; #for checking if device can execute desired action

    return if !$room && !$name;

    my $device;

    return if !defined $hash->{helper}{devicemap};

    $device = $hash->{helper}{devicemap}{rhasspyRooms}{$room}{$name} if $room && $name && defined $hash->{helper}{devicemap}{rhasspyRooms}->{$room};

    if ($device) {
        Log3($hash->{NAME}, 5, "Device selected (by hash, with room and name): $device");
        return $device;
    }

    return 0 if $droom; #no further check if explicit room was requested!

    my @maybees;
    for (sort keys %{$hash->{helper}{devicemap}{rhasspyRooms}}) {
        my $dev = $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$name};
        #return $device if $device;
        if ($dev) {
            Log3($hash->{NAME}, 5, "Device selected (by hash, using only name): $dev");
            return $dev 
                if $type
                  && defined $hash->{helper}{devicemap}{devices}{$dev}->{prio} 
                  && defined $hash->{helper}{devicemap}{devices}{$dev}{prio}->{outsideRoom}
                  && $hash->{helper}{devicemap}{devices}{$dev}{prio}->{outsideRoom} =~ m{\b$type\b}xms;
            if ( $intent ) {
                if ( $type ) {
                    push @maybees, $dev if defined $hash->{helper}{devicemap}{devices}{$dev}->{intents}
                        && defined $hash->{helper}{devicemap}{devices}{$dev}{intents}->{$intent}
                        && defined $hash->{helper}{devicemap}{devices}{$dev}{intents}->{$intent}->{$type};
                } else {
                    push @maybees, $dev if defined $hash->{helper}{devicemap}{devices}{$dev}->{intents}
                        && defined $hash->{helper}{devicemap}{devices}{$dev}{intents}->{$intent};
                }
            } else { 
                push @maybees, $dev;
            }
        }
    }
    @maybees = uniq(@maybees);
    return $maybees[0] if @maybees == 1; # exactly one device matching name
    if (@maybees) {
        Log3($hash->{NAME}, 4, "[$hash->{NAME}] more than one match for >>$name<< found (provide room info to avoid request)");
        my @rooms;
        for my $dev (@maybees) {
            push @rooms, (split m{,}x, $hash->{helper}{devicemap}{devices}{$dev}->{rooms})[0];
        }
        @rooms = get_unique(\@rooms);
        my $last_item = pop @rooms;
        my $first_items = join q{ }, @rooms;
        my $response = getResponse ($hash, 'RequestChoiceRoom');
        $response =~ s{(\$\w+)}{$1}eegx;
        Log3($hash->{NAME}, 4, "[$hash->{NAME}] response: $response");

        unshift @maybees, $response;
        unshift @maybees, $maybees[1];
        return \@maybees;
    }
    $room = $room ? "especially not in room >>$room<< (also not outside)!" : 'room not provided!';
    Log3($hash->{NAME}, 1, "No device for >>$name<< found, $room");
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
        my $mapping = getMapping($hash, $devs, $intent, { type => $type, subType => $subType }, 1) // next;
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
    my $subType = shift // $type;

    #rem. Beta-User: atm function is only called by GetNumeric!
    my $device;

    # Devices sammeln
    my ($matchesInRoom, $matchesOutsideRoom) = getDevicesByIntentAndType($hash, $room, $intent, $type, $subType);
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
                    push @priority, $dev if $hash->{helper}{devicemap}{devices}{$dev}{prio}->{inRoom} =~ m{\b$subType\b}xms;
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
                    $first_items = join q{ }, @rooms;
                    $response = getResponse ($hash, 'RequestChoiceRoom');
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
    my $type   = shift;
    my $subType = shift // $type;

    my $device;
    my ($matchesInRoom, $matchesOutsideRoom) = getDevicesByIntentAndType($hash, $room, $intent, $type, $subType);

    # Anonyme Funktion zum finden des aktiven Geräts
    my $activeDevice = sub ($$) {
        my $subhash = shift;
        my $devices = shift // return;
        my $match;

        for (@{$devices}) {
            my $mapping = getMapping($subhash, $_, 'GetOnOff', undef, 1);
            if ( defined $mapping ) {
                # Gerät ein- oder ausgeschaltet?
                my $value = _getOnOffState($subhash, $_, $mapping);
                if ( $value ) {
                    $match = $_;
                    last;
                }
            }
        }
        return $match;
    };

    # Gerät finden, erst im aktuellen Raum, sonst in den restlichen
    $device = $activeDevice->($hash, $matchesInRoom);
    $device //= $activeDevice->($hash, $matchesOutsideRoom);

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Gerät mit bestimmtem Sender suchen
sub getDeviceByMediaChannel {
    my $hash    = shift // return;
    my $room    = shift;
    my $channel = shift // return;

    my $devices;
    return if !defined $hash->{helper}{devicemap};
    $devices = $hash->{helper}{devicemap}{Channels}{$room}->{$channel} if defined $room;
    my $device = ${$devices}[0] // undef;
    if ( $device ) {
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
    $room //= '';
    Log3($hash->{NAME}, 1, "No device for >>$channel<< found, especially not in room >>$room<< (also not outside)!");
    return;
}

sub getDevicesByGroup {
    my $hash    = shift // return;
    my $data    = shift // return;
    my $getVirt = shift;

    my $group = $data->{Group};
    return if !$group && !$getVirt;
    my $room  = getRoomName($hash, $data);

    my $devices = {};
    my @devs;
    my $isVirt = defined $data->{'.virtualGroup'};
    if ( $isVirt ) {
        @devs = split m{,}x, $data->{'.virtualGroup'};
    } else {
        @devs = keys %{$hash->{helper}{devicemap}{devices}};
    }

    for my $dev (@devs) {
        if ( !$isVirt ) {
            my $allrooms = $hash->{helper}{devicemap}{devices}{$dev}->{rooms} // '';
            next if $room ne 'global' && $allrooms !~ m{\b$room(?:[\b:\s]|\Z)}i; ##no critic qw(RequireExtendedFormatting)

            my $allgroups = $hash->{helper}{devicemap}{devices}{$dev}->{groups} // next;
            next if $allgroups !~ m{\b$group\b}i; ##no critic qw(RequireExtendedFormatting)
        }

        my $specials = $hash->{helper}{devicemap}{devices}{$dev}{group_specials};
        my $label = $specials->{partOf} // $dev;
        next if defined $devices->{$label};

        my $delay = $specials->{async_delay} // 0;
        my $prio  = $specials->{prio} // 0;
        $devices->{$label} = { delay => $delay, prio => $prio };
    }

    return keys %{$devices} if $getVirt;
    return $devices;
}

sub getIsVirtualGroup {
    my $hash    = shift // return;
    my $data    = shift // return;
    my $getVirt = shift;

    return if defined $data->{'.virtualGroup'};

    my @devlist;

    my @rooms = grep { m{\ARoom}x } keys %{$data};
    my @grps  = grep { m{\AGroup}x } keys %{$data};
    my @devs  = grep { m{\ADevice}x } keys %{$data};

    #do we not have more than one room or more than one device and/or group?
    return if (!@rooms || @rooms == 1) && (@grps + @devs) < 2;

    my $restdata = {};
    for ( keys %{$data} ) {
        $restdata->{$_} = $data->{$_} if $_ !~ m{\A(?:Room|Group|Device|intent)}x;
    }

    my $intent = $data->{intent} // return;
    $intent =~ s{Group\z}{}x;
    my $grpIntent = $intent.'Group';
    my $needsConfirmation;

    $rooms[0] = 'noneInData' if !defined $rooms[0];
    my $maynotbe_in_room;
    my $cleared_in_room;
    my @probrooms;

    for my $room ( @rooms ) {
        for my $dev ( @devs ) {
        my $single = getDeviceByName($hash, $room eq 'noneInData' ? getRoomName($hash, $data) : $data->{$room}, $data->{$dev}, $room eq 'noneInData' ? undef : $data->{$room}, $intent);
            next if ref $single eq 'ARRAY';
            if ( defined $single && $single ne '0' ) {
                $maynotbe_in_room->{$dev} = $room if !defined $cleared_in_room->{$dev};
                push @probrooms, $data->{$room};
            }
            next if !$single;
            push @devlist, $single;
            $needsConfirmation //= getNeedsConfirmation($hash, $restdata, $intent, $single, 1);
            delete $maynotbe_in_room->{$dev};
            $cleared_in_room->{$dev} = 1;
        }
        for my $grp ( @grps ) {
            my $checkdata = $restdata;
            $checkdata->{Group}  = $data->{$grp};
            $checkdata->{Room}   = $data->{$room} if $room ne 'noneInData' ;
            @devlist = ( @devlist, getDevicesByGroup($hash, $checkdata, 1) );
            $needsConfirmation //= getNeedsConfirmation($hash, $checkdata, $grpIntent, undef, 1);
        }
    }

    return if !@devlist;
    @devlist = uniq(@devlist);

    if (!$needsConfirmation) {
        my $checkdata = $restdata;
        $checkdata->{Group}  = 'virtualGroup';
        $needsConfirmation = getNeedsConfirmation($hash, $checkdata, $grpIntent, undef, 1);
    }
    
    if ( !$needsConfirmation && keys %{$maynotbe_in_room} ) {
        $needsConfirmation = 1;
        my @outs = keys %{$maynotbe_in_room};
        @probrooms = uniq(@probrooms);
        my $devlist = _array2andString($hash, \@outs);
        my $roomlist = _array2andString($hash, \@probrooms);
        $hash->{helper}->{lng}->{$data->{sessionId}}->{pre} = getExtrapolatedResponse($hash, 'ParadoxData', 'Room', [$devlist, $roomlist], 'hint');
    }

    $restdata->{intent}          = $grpIntent;
    $restdata->{'.virtualGroup'} = join q{,}, @devlist;

    if ( $needsConfirmation ) {
        my $response = getResponse($hash, 'DefaultConfirmationRequestRawInput');
        my $rawInput = $data->{rawInput};
        $response =~ s{(\$\w+)}{$1}eegx;
        Log3( $hash, 5, "[$hash->{NAME}] getNeedsConfirmation is true for virtual group, response is $response" );
        setDialogTimeout($hash, $restdata, _getDialogueTimeout($hash), $response);
        return $hash->{NAME};
    }

    if (ref $dispatchFns->{$grpIntent} eq 'CODE' ) {
         if ( _isUnexpectedInTestMode($hash, $restdata) ) {
             testmode_next($hash);
             return 1;
         }
         $restdata->{Confirmation} = 1;
         return $dispatchFns->{$grpIntent}->($hash, $restdata);
    }

    return;
}

sub getNeedsConfirmation {
    my $hash   = shift // return;
    my $data   = shift // return;
    my $intent = shift // return;
    my $device = shift;
    my $fromVG = shift;

    return if defined $hash->{testline} && !$fromVG;;

    my $re = defined $device ? $device : $data->{Group};
    return if !defined $re;
    my $target = defined $device ? $data->{Device} : $data->{Group};
    Log3( $hash, 5, "[$hash->{NAME}] getNeedsConfirmation called, regex is $re" );
    my $timeout = _getDialogueTimeout($hash);
    my $response;
    my $rawInput = $data->{rawInput};
    my $Value    = $data->{Value};
    $Value = $hash->{helper}{lng}->{words}->{$Value} if defined $Value && defined $hash->{helper}{lng}->{words} && defined $hash->{helper}{lng}->{words}->{$Value};

    if (defined $hash->{helper}{tweaks} 
         && defined $hash->{helper}{tweaks}{confirmIntents} 
         && defined $hash->{helper}{tweaks}{confirmIntents}{$intent} 
         && $re =~ m{\A($hash->{helper}{tweaks}{confirmIntents}{$intent})\z}xms ) { 
        return 1 if $fromVG;
        $response = defined $hash->{helper}{tweaks}{confirmIntentResponses} 
                    && defined $hash->{helper}{tweaks}{confirmIntentResponses}{$intent} ? $hash->{helper}{tweaks}{confirmIntentResponses}{$intent}
                    : getResponse($hash, 'DefaultConfirmationRequestRawInput');

        $response =~ s{(\$\w+)}{$1}eegx;
        Log3( $hash, 5, "[$hash->{NAME}] getNeedsConfirmation is true for tweak, response is $response" );
        setDialogTimeout($hash, $data, $timeout, $response);
        return 1;
    }

    return if !defined $device;

    my $confirm = $hash->{helper}{devicemap}{devices}{$device}->{confirmIntents};
    return if !defined $confirm;
    if ( $confirm =~ m{\b$intent(?:[,]|\Z)}i ) { ##no critic qw(RequireExtendedFormatting)
        return 1 if $fromVG;
        $response = defined $hash->{helper}{devicemap}{devices}{$device}->{confirmIntentResponses} 
                    && defined $hash->{helper}{devicemap}{devices}{$device}->{confirmIntentResponses}{$intent} 
                  ? $hash->{helper}{devicemap}{devices}{$device}->{confirmIntentResponses}{$intent}
                  : defined $hash->{helper}{tweaks} 
                    && defined $hash->{helper}{tweaks}{confirmIntentResponses} 
                    && defined $hash->{helper}{tweaks}{confirmIntentResponses}{$intent} ? $hash->{helper}{tweaks}{confirmIntentResponses}{$intent}
                  : getResponse($hash, 'DefaultConfirmationRequestRawInput');
        my $words = $hash->{helper}{devicemap}{devices}{$device}->{confirmValueMap} // $hash->{helper}{lng}->{words} // {};
        $Value  = $words->{$data->{Value}} if defined $data->{Value};
        $response =~ s{(\$\w+)}{$1}eegx;
        Log3( $hash, 5, "[$hash->{NAME}] getNeedsConfirmation is true on device level, response is $response" );
        $data->{'.DevName'} = $device;
        setDialogTimeout($hash, $data, $timeout, $response);
        return 1;
    }

    return;
}

sub respondNeedsChoice {
    my $hash   = shift // return;
    my $data   = shift // return $hash->{NAME};
    my $device = shift // return $hash->{NAME};

    my $first    = $device->[0];
    my $response = $device->[1];
    my $all = $device->[2];
    my $choice = $device->[3] // 'RequestChoiceRoom';
    $data->{customData} = $all;
    my $toActivate = $choice eq 'RequestChoiceDevice' ? [qw(ChoiceDevice Choice CancelAction)] : [qw(ChoiceRoom Choice CancelAction)];
    $device = $first;
    Log3($hash->{NAME}, 5, "More than one device possible, response is $response, first is $first, all are $all, type is $choice");
    return setDialogTimeout($hash, $data, _getDialogueTimeout($hash), $response, $toActivate);
}

sub getNeedsClarification {
    my $hash       = shift // return;
    my $data       = shift // return $hash->{NAME};
    my $identifier = shift // return $hash->{NAME};
    my $todelete   = shift // return $hash->{NAME};
    my $problems   = shift;

    my $re = $problems->[0];
    return respond( $hash, $data, 'code problem in getNeedsClarification!') if !defined $re;
    Log3( $hash, 5, "[$hash->{NAME}] getNeedsClarification called, regex is $re" );

    my $response = getExtrapolatedResponse($hash, $identifier, $problems, 'hint');
    my $response2 = getExtrapolatedResponse($hash, $identifier, $problems, 'confirm');

    my $timeout = _getDialogueTimeout($hash);
    for (split m{,}x, $todelete) {
        delete $data->{$_};
    }
    setDialogTimeout($hash, $data, $timeout, "$response $response2", [qw(Choice CancelAction)]);
    return $hash->{NAME};
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

    return \%parsedMapping;
}


# rhasspyMapping parsen und gefundene Settings zurückliefern
sub getMapping {
    my $hash       = shift // return;
    my $device     = shift // return;
    my $intent     = shift // return;
    my $type       = shift // $intent;
    my $disableLog = shift // 0;

    my $subType = $type;
    if (ref $type eq 'HASH') {
        $subType = $type->{subType};
        $type = $type->{type};
    }

    my $matchedMapping;

    $matchedMapping = $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$subType} if  defined $subType && defined $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$subType};
    return $matchedMapping if $matchedMapping;

    for (sort keys %{$hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}}) {
        #simply pick first item in alphabetical order...
        return $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$_};
    }

    return $matchedMapping;
}

sub exportMapping {
    my $hash   = shift // return;
    my $device = shift // return;

    my $nl = $hash->{CL} ? '<br>' : q{\n};

    my $mapping = $hash->{helper}{devicemap}{devices}{$device}{intents};
    my $result;

    for my $key ( keys %{$mapping} ) {
        my $map = $mapping->{$key};
        my @tokens;
        if ( defined $mapping->{$key}->{$key} ) {
            $map = $mapping->{$key}->{$key};
            delete $map->{type};
            $result .= $nl if $result;
            $result .= "${key}:";
            @tokens = ();
            for my $skey ( keys %{$map} ) {
                push @tokens, "${skey}=$map->{$skey}";
            }
            $result .= join q{,}, @tokens;
        } else {
            for my $skey ( keys %{$map} ) {
                $result .= $nl if $result;
                $result .= "${key}:";
                @tokens = ();
                for my $sskey ( keys %{$map->{$skey}} ) {
                    my $special = $skey eq 'desired-temp' && $map->{$skey}->{$sskey} eq 'temperature' ? 'desired-temp' : "$map->{$skey}->{$sskey}";#Beta-User: desired-temp?
                    push @tokens, "${sskey}=$special"; 
                }
                $result .= join q{,}, @tokens;
            }
        }
    }
    return $result;
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
        if ( defined $hash->{testline} ) {
            push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Perl: $cmd";
            #$hash->{helper}->{test}->{result}->[$hash->{testline}] .= " => Perl: $cmd";
            return;
        }
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
        Log3($hash->{NAME}, 5, "$cmd is a FHEM command");
        if ( defined $hash->{testline} ) {
            push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Command(s): $cmd";
            #$hash->{helper}->{test}->{result}->[$hash->{testline}] .= " => Command(s): $cmd";
            return;
        }
        $error = AnalyzeCommandChain($hash, $cmd);
        $returnVal = (split m{\s+}x, $cmd)[1];
    }
    # Soll Command auf anderes Device umgelenkt werden?
    elsif ($cmd =~ m{:}x) {
    $cmd   =~ s{:}{ }x;
        $cmd   = qq($cmd $val) if defined $val;
        Log3($hash->{NAME}, 5, "$cmd redirects to another device");
        if ( defined $hash->{testline} ) {
            push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Redirected command: $cmd";
            #$hash->{helper}->{test}->{result}->[$hash->{testline}] .= " => Redirected command: $cmd";
            return;
        }
        $error = AnalyzeCommand($hash, "set $cmd");
        $returnVal = (split q{ }, $cmd)[1];
    }
    # Nur normales Cmd angegeben
    else {
        $cmd   = qq($device $cmd);
        $cmd   = qq($cmd $val) if defined $val;
        Log3($hash->{NAME}, 5, "$cmd is a normal command");
        $error = _AnalyzeCommand($hash, "set $cmd");
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
        return InternalVal($device,'STATE',0) if $getString eq 'STATE';
        return ReadingsVal($device, $getString, 0);
    }

    # If it's only a string without quotes, return string for TTS
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

    # JSON Decode und Fehlerüberprüfung
    my $decoded;
    if ( !eval { $decoded  = JSON->new->decode($json) ; 1 } ) {
        return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
    }

    # Standard-Keys auslesen
    ($data->{intent} = $decoded->{intent}{intentName}) =~ s{\A.*.:}{}x if exists $decoded->{intent}{intentName};
    $data->{confidence} = $decoded->{intent}{confidenceScore} // 0.75;
    for my $key (qw(sessionId siteId input rawInput customData lang)) {
        $data->{$key} = $decoded->{$key} if exists $decoded->{$key};
    }

    # Überprüfen ob Slot Array existiert
    if (exists $decoded->{slots}) {
        # Key -> Value Paare aus dem Slot Array ziehen
        for my $slot (@{$decoded->{slots}}) { 
            my $slotName = $slot->{slotName};
            my $slotValue;

            $slotValue = $slot->{value}{value} if exists $slot->{value}{value} && $slot->{value}{value} ne ''; #Beta-User: dismiss effectively empty fields
            $slotValue = $slot->{value} if exists $slot->{entity} && $slot->{entity} eq 'rhasspy/duration';

            $data->{$slotName} = $slotValue;
        }
    }

    for (keys %{ $data }) {
        my $value = $data->{$_};
        #custom converter equivalent
        if ( $_ eq 'Value' ) {
            my $match = $value =~ s{\A\s*(\d+)\s*[.,]\s*(\d+)\s*\z}{$1.$2}xm;
            $data->{$_} = $value if $match;
        }
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
    my $data;

    for my $dev (@instances) {
        my $hash = $defs{$dev};
        # Name mit IODev vergleichen
        next if $ioname ne AttrVal($hash->{NAME}, 'IODev', ReadingsVal($hash->{NAME}, 'IODev', InternalVal($hash->{NAME}, 'IODev', 'none')));
        next if IsDisabled( $hash->{NAME} );
        my $topicpart = qq{/$hash->{LANGUAGE}\.$hash->{fhemId}\[._]|hermes/dialogueManager|hermes/nlu/intentNotRecognized|hermes/hotword/[^/]+/detected|hermes/hotword/toggleO[nf]+|hermes/tts/say};
        next if $topic !~ m{$topicpart}x;

        Log3($hash,5,"RHASSPY: [$hash->{NAME}] Parse (IO: ${ioname}): Msg: $topic => $value");
        $data //= parseJSONPayload($hash, $value); #Beta-User: Calling parseJSONPayload() only once should be ok, as there's no code-page dependency any longer

        #my $fret = analyzeMQTTmessage($hash, $topic, $value);
        my $fret = analyzeMQTTmessage($hash, $topic, $value, $data);
        next if !defined $fret;
        if( ref $fret eq 'ARRAY' ) {
          push (@ret, @{$fret});
          $forceNext = 1 if AttrVal($hash->{NAME},'forceNEXT',0);
        } else {
          Log3($hash->{NAME},5,"RHASSPY: [$hash->{NAME}] Parse: internal error:  onmessage returned an unexpected value: ".$fret);
        }
    }
    unshift(@ret, '[NEXT]') if !@ret || $forceNext;
    return @ret;
}

sub Notify {
    my $hash     = shift // return;
    my $dev_hash = shift // return;
    my $name = $hash->{NAME} // return;
    my $device = $dev_hash->{NAME} // return;

    Log3($name, 5, "[$name] NotifyFn called with event in $device");

    return notifySTT($hash, $dev_hash) if InternalVal($device,'TYPE', 'unknown') eq 'AMADCommBridge';
    return notifyAMADDev($hash, $dev_hash) if InternalVal($device,'TYPE', 'unknown') eq 'AMADDevice';

    if ( $device eq 'global' ) {
        return if !$hash->{autoTraining};

        my $events = $dev_hash->{CHANGED};
        return if !$events;
        my @devs = devspec2array("$hash->{devspec}");
        for my $evnt(@{$events}){
            next if $evnt !~ m{\A(?:ATTR|DELETEATTR|DELETED|RENAMED)\s+(\w+)(?:\s+)(.*)}xms;
            my $dev = $1;           ##no critic qw(Capture)
            my $rest = $2;          ##no critic qw(Capture)
            next if !grep { $dev } @devs;

            if ( $evnt =~ m{\A(?:DELETED|RENAMED)\s+\w+}xms || $rest =~ m{\A(alias|$hash->{prefix}|genericDeviceType|(alexa|siri|gassistant)Name|group)}xms ) {
                resetRegIntTimer( 'autoTraining', time + $hash->{autoTraining}, \&RHASSPY_autoTraining, $hash, 0);
                return;
            }
        }
        return;
    }

    return if !ReadingsVal($name,'enableMsgDialog',1) || !defined $hash->{helper}->{msgDialog};
    my @events = @{deviceEvents($dev_hash, 1)};

    return if !@events;
    return if $hash->{helper}->{msgDialog}->{config}->{allowed} !~ m{\b(?:$device|everyone)(?:\b|\z)}xms;

    for my $event (@events){
        next if $event !~ m{(?:fhemMsgPushReceived|fhemMsgRcvPush):.(.+)}xms;

        my $msgtext = trim($1);         ##no critic qw(Capture)
        Log3($name, 4 , qq($name received $msgtext from $device));

        my $tocheck = $hash->{helper}->{msgDialog}->{config}->{close};
        return msgDialog_close($hash, $device) if $msgtext =~ m{\A[\b]*$tocheck[\b]*\z}ix;
        $tocheck = $hash->{helper}->{msgDialog}->{config}->{open};
        return msgDialog_open($hash, $device, $msgtext) if $msgtext =~ m{\A[\b]*$tocheck}ix;
        return msgDialog_progress($hash, $device, $msgtext);
    }

    return;
}

sub notifySTT {
    my $hash     = shift // return;
    my $dev_hash = shift // return;
    my $name = $hash->{NAME} // return;
    my $device = $dev_hash->{NAME} // return;

    my @events = @{deviceEvents($dev_hash, 1)};

    return if !@events;

    for my $event (@events){
        next if $event !~ m{(?:receiveVoiceCommand):.(.+)}xms;
        my $msgtext = trim($1);         ##no critic qw(Capture)
        my $client = ReadingsVal($device,'receiveVoiceDevice',undef) // return;
        return if $hash->{helper}->{SpeechDialog}->{config}->{allowed} !~ m{\b(?:$client|everyone)(?:\b|\z)}xms;

        Log3($name, 4 , qq($name received $msgtext from $client (triggered by $device) ));

        my $tocheck = $hash->{helper}->{SpeechDialog}->{config}->{filterFromBabble};
        if ( $tocheck ) {
            return AnalyzePerlCommand( undef, Babble_DoIt($hash->{Babble},$msgtext) ) if $msgtext !~ m{\A[\b]*$tocheck[\b]*\z}ix;
            $msgtext =~ s{\A[\b]*$tocheck}{}ix;
        }
        return SpeechDialog_progress($hash, $client, $msgtext) if defined $hash->{helper}{SpeechDialog}->{$client} && defined $hash->{helper}{SpeechDialog}->{$client}->{data}; #session already opened!
        return SpeechDialog_open($hash, $client, $msgtext);
    }

    return;
}

sub notifyAMADDev{
    my $hash     = shift // return;
    my $dev_hash = shift // return;
    my $name = $hash->{NAME} // return;
    my $device = $dev_hash->{NAME} // return;

    my @events = @{deviceEvents($dev_hash, 1)};

    return if !@events;

    for my $event (@events){
        next if $event !~ m{lastSetCommandState:.setCmd_done}xms;
        return if $hash->{helper}->{SpeechDialog}->{config}->{allowed} !~ m{\b(?:$device|everyone)(?:\b|\z)}xms;

        Log3($name, 5 , qq($name: $device may have finished voice output));

        my $iscont = SpeechDialog_sayFinish($hash, $device);
        if ( $iscont && ReadingsVal($device, 'rhasspy_dialogue', 'closed') eq 'open' ) {
            AnalyzeCommand( $hash, "set $device activateVoiceInput" );
            readingsSingleUpdate($defs{$device}, 'rhasspy_dialogue', 'listening', 1);
        }
    }

    return;
}

sub activateVoiceInput {
    my $hash    = shift //return;
    my $anon    = shift;
    my $h       = shift;

    my $base = ReadingsVal($hash->{NAME},'siteIds', "$hash->{LANGUAGE}$hash->{fhemId}");
    if ($base =~ m{\b(default|base)(?:[\b]|\Z)}xms) {
        $base = $1;
    } else { 
        $base = (split m{,}x, $base)[0];
    }
    my $siteId  = $h->{siteId}  // shift @{$anon} // $base;
    my $hotword = $h->{hotword} // shift @{$anon} // $h->{modelId} // "$hash->{LANGUAGE}$hash->{fhemId}";
    my $modelId = $h->{modelId} // shift @{$anon} // "$hash->{LANGUAGE}$hash->{fhemId}";

    my $sendData =  {
        modelId             => $modelId,
        modelVersion        => '',
        modelType           => 'personal',
        currentSensitivity  => '0.5',
        siteId              => $siteId,
        sessionId           => 'null',
        sendAudioCaptured   => 'null',
        customEntities      => 'null'
    };
    my $json = _toCleanJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/hotword/$hotword/detected $json});
}

#source: https://rhasspy.readthedocs.io/en/latest/reference/#tts_say
sub sayFinished {
    my $hash    = shift // return;
    my $data    = shift // return;
    my $siteId  = shift // $hash->{siteId};

    my $id = $data->{id} // $data->{sessionId};

    my $sendData =  { 
        id           => $id,
        siteId       => $siteId 
    };
    my $json = _toCleanJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/tts/sayFinished $json});
}


#reference: https://forum.fhem.de/index.php/topic,124952.msg1213902.html#msg1213902
sub testmode_start {
    my $hash    = shift // return;
    my $file    = shift // return;

    my ($ret, @content) = FileRead( { FileName => $file, ForceType => 'file' } );
    return $ret if $ret;
    return 'file contains no content!' if !@content;
    $hash->{testline} = 0;
    $hash->{helper}->{test}->{content} = \@content;
    $hash->{helper}->{test}->{filename} = $file;
    return testmode_next($hash);
}

sub testmode_next {
    my $hash = shift // return;

    my $line = $hash->{helper}->{test}->{content}->[$hash->{testline}];
    if ( !$line || $line =~ m{\A\s*[#]}x || $line =~ m{\A\s*\z}x || $line =~ m{\A\s*(?:DIALOGUE|WAKEWORD)[:]}x ) {
        $line //= '';
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, $line;
        $hash->{helper}->{test}->{isInDialogue} = 1 if $line =~ m{\A\s*DIALOGUE[:](?!END)}x;
        delete $hash->{helper}->{test}->{isInDialogue} if $line =~ m{\A\s*DIALOGUE[:]END}x;
        $hash->{testline}++;
        return testmode_next($hash) if $hash->{testline} <= @{$hash->{helper}->{test}->{content}};
    }

    if ( $hash->{testline} < @{$hash->{helper}->{test}->{content}} ) {
        my @ca_strings = split m{,}x, ReadingsVal($hash->{NAME},'intents','');
        my $sendData =  { 
            input        => $line,
            sessionId    => "$hash->{siteId}_$hash->{testline}_testmode",
            id           => "$hash->{siteId}_$hash->{testline}",
            siteId       => $hash->{siteId},
            intentFilter => [@ca_strings]
        };

        my $json = _toCleanJSON($sendData);
        resetRegIntTimer( 'testmode_end', time + 10, \&RHASSPY_testmode_timeout, $hash ) if $hash->{helper}->{test}->{filename} ne 'none';
        return IOWrite($hash, 'publish', qq{hermes/nlu/query $json});
    }
    return testmode_end($hash);
}

sub testmode_end {
    my $hash = shift // return;
    my $fail = shift // 0;

    my $filename = $hash->{helper}->{test}->{filename} // q{none};
    $filename =~ s{[.]txt\z}{}ix;
    $filename = "${filename}_result.txt";

    my $result = $hash->{helper}->{test}->{passed} // 0;
    my $fails = $hash->{helper}->{test}->{notRecogn} // 0;
    my $failsInDialogue = $hash->{helper}->{test}->{notRecognInDialogue} // 0;
    $result = "tested $result sentences, failed total: $fails, amongst these in dialogues: $failsInDialogue.";

    if ( $filename ne 'none_result.txt' ) {
        my $duration = $result;
        my $aresult;
        $duration .= sprintf( " Testing time: %.2f seconds.", (gettimeofday() - $hash->{asyncGet}{start})*1) if $hash->{asyncGet} && $hash->{asyncGet}{reading} eq 'testResult';
        my $rawresult = $hash->{helper}->{test}->{result};
        my $text;
        for my $resu ( sort { $a <=> $b } keys %{$rawresult} ) {
            my $line = $rawresult->{$resu};
            if ( defined $line->[1] ) {
                my $single = $line->[0];
                push @{$aresult}, qq(   [RHASSPY] Input:      $single);
                for ( 1..@{$line}-1) {
                    $single = $line->[$_];
                    push @{$aresult}, qq(             $single);
                }
            } else {
                my $singl = ref $line eq 'ARRAY' ? $line->[0] : $line;
                push @{$aresult}, qq($singl);
            }
        }
        push @{$aresult}, "test ended with timeout! Last request was $hash->{helper}->{test}->{content}->[$hash->{testline}]" if $fail;
        FileWrite({ FileName => $filename, ForceType => 'file' }, @{$aresult} );
        $result = "$duration See $filename for detailed results." if !$fail;
        $result = "Test ended incomplete with timeout. See $filename for results up to failure." if $fail;
    } else {
        $result = $fails ? 'Test failed, ' : 'Test ok, ';
        $result .= 'result is: ';
        $result .= join q{ => }, @{$hash->{helper}->{test}->{result}->{0}};
    }
    readingsSingleUpdate($hash,'testResult',$result,1);
    if( $hash->{asyncGet} && $hash->{asyncGet}{reading} eq 'testResult' ) {
          my $duration = sprintf( "%.2f", (gettimeofday() - $hash->{asyncGet}{start})*1);
          RemoveInternalTimer($hash->{asyncGet});
          my $suc = $fail ? 'not completely passed!' : 'passed successfully.';
          asyncOutput($hash->{asyncGet}{CL}, "test(s) $suc Summary: $result");
          delete($hash->{asyncGet});
    }
    delete $hash->{testline};
    delete $hash->{helper}->{test};
    deleteSingleRegIntTimer('testmode_end', $hash); 

    return;
}

sub testmode_parse {
    my $hash   = shift // return;
    my $intent = shift // return;
    my $data   = shift // return;

    my $line = $hash->{helper}->{test}->{content}->[$hash->{testline}];
    my $result;
    $hash->{helper}->{test}->{passed}++;
    if ( $intent eq 'intentNotRecognized' ) {
        $result = $line;
        $result .= " => Intent not recognized." if $hash->{helper}->{test}->{filename} eq 'none';
        $hash->{helper}->{test}->{notRecogn}++;
        $hash->{helper}->{test}->{notRecognInDialogue}++ if defined $hash->{helper}->{test}->{isInDialogue};
    } else { 
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, $line if $hash->{helper}->{test}->{filename} ne 'none';
        my $json = toJSON($data);
        $result = "Confidence not sufficient! " if !_check_minimumConfidence($hash, $data, 1);
        $result .= "$intent $json";
    }
    push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, $result;
    if (ref $dispatchFns->{$intent} eq 'CODE' && $intent =~m{\ASetOnOffGroup|SetColorGroup|SetNumericGroup|SetTimedOnOffGroup\z}xms) {
        my $devices = getDevicesByGroup($hash, $data);
        $result = ref $devices ne 'HASH' || !keys %{$devices} ?
                    q{can't identify any device in group and room} 
                  : join q{,}, keys %{$devices};
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Devices in group and room: $result";
    } elsif (ref $dispatchFns->{$intent} eq 'CODE' && $intent =~m{\AGetOnOff|GetNumeric|GetState|GetTime|GetDate|MediaControls|SetNumeric|SetOnOff|SetTimedOnOff|SetScene|SetColor|SetTimer|MediaChannels|Shortcuts\z}xms) {
        $result = $dispatchFns->{$intent}->($hash, $data);
        return;
    }
    $hash->{testline}++;
    return testmode_next($hash);
}

sub RHASSPY_testmode_timeout {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;
    my $identity = $fnHash->{MODIFIER};
    deleteSingleRegIntTimer($identity, $hash, 1); 

    return testmode_end($hash, 1);
}


sub _isUnexpectedInTestMode {
    my $hash   = shift // return;
    my $data   = shift // return;
    
    return if !defined $hash->{testline};
    if ( defined $data->{'.virtualGroup'} ) {
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "redirected group intent ($data->{intent}), adressed devices: $data->{'.virtualGroup'}";
        #$hash->{helper}->{test}->{result}->[$hash->{testline}] .= " => redirected group intent ($data->{intent}), adressed devices: $data->{'.virtualGroup'}";
    } else {
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Unexpected call of $data->{intent} routine!";
        #$hash->{helper}->{test}->{result}->[$hash->{testline}] .= " => Unexpected call of $data->{intent} routine!";
    }
    $hash->{testline}++;
    return 1;
}


sub RHASSPY_msgDialogTimeout {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;
    my $identity = $fnHash->{MODIFIER};
    deleteSingleRegIntTimer($identity, $hash, 1); 
    return msgDialog_close($hash, $identity);
}

sub setMsgDialogTimeout {
    my $hash     = shift // return;
    my $data     = shift // return;
    my $timeout  = shift // _getDialogueTimeout($hash);

    my $siteId = $data->{siteId};
    my $identity = (split m{_${siteId}_}x, $data->{sessionId},3)[0] // return;
    $hash->{helper}{msgDialog}->{$identity}->{data} = $data;

    resetRegIntTimer( $identity, time + $timeout, \&RHASSPY_msgDialogTimeout, $hash, 0);
    return;
}

sub msgDialog_close {
    my $hash     = shift // return;
    my $device   = shift // return;
    my $response = shift // _shuffle_answer($hash->{helper}->{msgDialog}->{config}->{goodbye});
    Log3($hash, 5, "msgDialog_close called with $device");

    deleteSingleRegIntTimer($device, $hash);
    return if !defined $hash->{helper}{msgDialog}->{$device};;

    msgDialog_respond( $hash, $device, $response, 0 );
    delete $hash->{helper}{msgDialog}->{$device};
    return;
}

sub msgDialog_open {
    my $hash    = shift // return;
    my $device  = shift // return;
    my $msgtext = shift // return;

    my $tocheck = $hash->{helper}->{msgDialog}->{config}->{open};
    $msgtext =~ s{\A[\b]*$tocheck}{}ix;
    $msgtext = trim($msgtext);
    Log3($hash, 5, "msgDialog_open called with $device and (cleaned) $msgtext");

    my $siteId   = $hash->{siteId};
    my $id       = "${device}_${siteId}_" . time;
    my $sendData =  {
        sessionId    => $id,
        siteId       => $siteId,
        customData   => $device
    };

    setMsgDialogTimeout($hash, $sendData, $hash->{helper}->{msgDialog}->{config}->{sessionTimeout});
    return msgDialog_progress($hash, $device, $msgtext, $sendData) if $msgtext;
    my $you = AttrVal($device,'alias',$device);
    my $response = _shuffle_answer($hash->{helper}->{msgDialog}->{config}->{hello});
    $response =~ s{(\$\w+)}{$1}eegx;
    return msgDialog_respond($hash, $device, $response, 0);
}

#handle messages from FHEM/messenger side
sub msgDialog_progress {
    my $hash    = shift // return;
    my $device  = shift // return;
    my $msgtext = shift // return;
    my $data    = shift // $hash->{helper}->{msgDialog}->{$device}->{data};

    #atm. this just hands over incoming text to Rhasspy without any additional logic. 
    #This is the place to add additional logics and decission making...
    #my $data    = $hash->{helper}->{msgDialog}->{$device}->{data}; # // msgDialog_close($hash, $device);
    Log3($hash, 5, "msgDialog_progress called with $device and text $msgtext");
    #Log3($hash, 5, 'msgDialog_progress called without DATA') if !defined $data;

    return if !defined $data;

    my $sendData =  { 
        input        => $msgtext,
        sessionId    => $data->{sessionId},
        id           => $data->{id},
        siteId       => $data->{siteId}
    };
    #asrConfidence: float? = null - confidence from ASR system for input text, https://rhasspy.readthedocs.io/en/latest/reference/#nlu_query
    $sendData->{intentFilter} = $data->{intentFilter} if defined $data->{intentFilter};

    my $json = _toCleanJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/nlu/query $json});
}

sub msgDialog_respond {
    my $hash       = shift // return;
    my $recipients = shift // return;
    my $message    = shift // return;
    my $keepopen   = shift // 1;

    Log3($hash, 5, "msgDialog_respond called with $recipients and text $message");
    trim($message);
    return if !$message; # empty?

    my $msgCommand = $hash->{helper}->{msgDialog}->{config}->{msgCommand};
    $msgCommand =~ s{\\[\@]}{@}x;
    $msgCommand =~ s{(\$\w+)}{$1}eegx;
    AnalyzeCommand($hash, $msgCommand);

    resetRegIntTimer( $recipients, time + $hash->{helper}->{msgDialog}->{config}->{sessionTimeout}, \&RHASSPY_msgDialogTimeout, $hash, 0) if $keepopen;
    return $recipients;
}

#handle return messages from MQTT side
sub handleIntentMsgDialog {
    my $hash = shift // return;
    my $data = shift // return;
    my $name = $hash->{NAME};

    #Beta-User: fake function, needs review...
    Log3($hash, 5, "[$name] handleIntentMsgDialog called");

    return $name;
}

#handle tts/say messages from MQTT side
sub handleTtsMsgDialog {
    my $hash = shift // return;
    my $data = shift // return;

    my $recipient = $data->{sessionId} // return;
    my $message    = $data->{text}      // return;
    $recipient = (split m{_$hash->{siteId}_}x, $recipient,3)[0] // return;

    Log3($hash, 5, "handleTtsMsgDialog for $hash->{NAME} called with $recipient and text $message");
    if ( defined $hash->{helper}->{msgDialog} 
        && defined $hash->{helper}->{msgDialog}->{$recipient} ) {
        msgDialog_respond($hash,$recipient,$message);
        sayFinished($hash, $data->{id}, $hash->{siteId});
    } elsif ( defined $hash->{helper}->{SpeechDialog} 
        && defined $hash->{helper}->{SpeechDialog}->{config}->{$recipient} ) {
        SpeechDialog_respond($hash,$recipient,$message,0);
    }

    return $recipient;
}

sub RHASSPY_SpeechDialogTimeout {
    my $fnHash = shift // return;
    my $hash = $fnHash->{HASH} // $fnHash;
    return if !defined $hash;
    my $identity = $fnHash->{MODIFIER};
    deleteSingleRegIntTimer($identity, $hash, 1); 
    return SpeechDialog_close($hash, $identity);
}

sub setSpeechDialogTimeout {
    my $hash     = shift // return;
    my $data     = shift // return;
    my $timeout  = shift // _getDialogueTimeout($hash);

    my $siteId = $data->{siteId};
    my $identity = (split m{_${siteId}_}x, $data->{sessionId},3)[0] // return;
    $hash->{helper}{SpeechDialog}->{$identity}->{data} = $data;

    resetRegIntTimer( $identity, time + $timeout, \&RHASSPY_SpeechDialogTimeout, $hash, 0);
    return;
}


sub SpeechDialog_sayFinish{
    my $hash     = shift // return;
    my $device   = shift // return;

    return if !defined $hash->{helper}{SpeechDialog}->{$device} 
           || !defined $hash->{helper}{SpeechDialog}->{$device}->{data} 
           || !defined $hash->{helper}{SpeechDialog}->{$device}->{data}->{sessionId};
    sayFinished($hash, $hash->{helper}{SpeechDialog}->{$device}->{data}, $hash->{siteId});
    return 1;
}

sub SpeechDialog_close {
    my $hash     = shift // return;
    my $device   = shift // return;
    Log3($hash, 5, "SpeechDialog_close called with $device");

    SpeechDialog_sayFinish($hash, $device);

    deleteSingleRegIntTimer($device, $hash);
    readingsSingleUpdate($defs{$device}, 'rhasspy_dialogue', 'closed', 1);

    delete $hash->{helper}{SpeechDialog}->{$device};
    return;
}

sub SpeechDialog_open {
    my $hash    = shift // return;
    my $device  = shift // return;
    my $msgtext = shift // return;

    Log3($hash, 5, "SpeechDialog_open called with $device and $msgtext");

    my $siteId   = $hash->{siteId};
    my $id       = "${device}_${siteId}_" . time;
    my $sendData =  {
        sessionId    => $id,
        siteId       => $siteId,
        customData   => $device
    };

    my $tout = $hash->{helper}->{SpeechDialog}->{config}->{$device}->{sessionTimeout} // $hash->{sessionTimeout};
    setSpeechDialogTimeout($hash, $sendData, $tout);
    return SpeechDialog_progress($hash, $device, $msgtext, $sendData);
}

#handle messages from FHEM/messenger side
sub SpeechDialog_progress {
    my $hash    = shift // return;
    my $device  = shift // return;
    my $msgtext = shift // return;
    my $data    = shift // $hash->{helper}{SpeechDialog}->{$device}->{data};

    #atm. this just hands over incoming text to Rhasspy without any additional logic. 
    #This is the place to add additional logics and decission making...
    #my $data    = $hash->{helper}->{msgDialog}->{$device}->{data}; # // msgDialog_close($hash, $device);
    Log3($hash, 5, "SpeechDialog_progress called with $device and text $msgtext");
    Log3($hash, 5, 'SpeechDialog_progress called without DATA') if !defined $data;

    return if !defined $data;

    my $sendData =  { 
        input        => $msgtext,
        sessionId    => $data->{sessionId},
        id           => $data->{id},
        siteId       => $data->{siteId}
    };
    #asrConfidence: float? = null - confidence from ASR system for input text, https://rhasspy.readthedocs.io/en/latest/reference/#nlu_query
    $sendData->{intentFilter} = $data->{intentFilter} if defined $data->{intentFilter};

    my $json = _toCleanJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/nlu/query $json});
}

sub SpeechDialog_respond {
    my $hash       = shift // return;
    my $device     = shift // return;
    my $message    = shift // return;
    my $keepopen   = shift // 1;
    my $cntByDelay = shift // 0;

    Log3($hash, 5, "SpeechDialog_respond called with $device and text $message");
    trim($message);
    return if !$message; # empty?

    my $msgCommand = $hash->{helper}->{SpeechDialog}->{config}->{$device}->{ttsCommand};
    $msgCommand //= 'set $DEVICE ttsMsg $message' if InternalVal($device, 'TYPE', '') eq 'AMADDevice';
    return if !$msgCommand;
    my %specials = (
         '$DEVICE'  => $device,
         '$message' => $message,
         '$NAME'  => $hash->{NAME}
        );
    $msgCommand  = EvalSpecials($msgCommand, %specials);
    AnalyzeCommandChain($hash, $msgCommand);
    if ( $keepopen ) {
        my $tout = $hash->{helper}->{SpeechDialog}->{config}->{$device}->{sessionTimeout} // $hash->{sessionTimeout};
        $tout //= _getDialogueTimeout($hash) if !$cntByDelay;
        resetRegIntTimer( $device, time + $tout, \&RHASSPY_SpeechDialogTimeout, $hash, 0);
        readingsSingleUpdate($defs{$device}, 'rhasspy_dialogue', 'open', 1);
    } else {
        deleteSingleRegIntTimer($device, $hash);
        delete $hash->{helper}->{SpeechDialog}->{$device};
        readingsSingleUpdate($defs{$device}, 'rhasspy_dialogue', 'closed', 1);
    }
    return $device;
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

# Daten vom MQTT Modul empfangen -> Device und Room ersetzen, dann erneut an NLU übergeben
sub analyzeMQTTmessage {
    my $hash    = shift;# // return;
    my $topic   = shift;# // carp q[No topic provided!]   && return;
    my $message = shift;# // carp q[No message provided!] && return;;
    my $data    = shift;# // carp q[No message provided!] && return;;
    
    #my $data    = parseJSONPayload($hash, $message);
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
            my $identity = qq($data->{sessionId});
            my $data_old = $hash->{helper}{'.delayed'}->{$identity};
            if (defined $data_old) {
                $data->{text} = getResponse( $hash, 'DefaultCancelConfirmation' );
                $data->{intentFilter} = 'null' if !defined $data->{intentFilter}; #dialog II
                sendTextCommand( $hash, $data );
                delete $hash->{helper}{'.delayed'}{$identity};
                deleteSingleRegIntTimer($identity, $hash);
            }
        }
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }
    # Hotword detection
    if ($topic =~ m{\Ahermes/hotword/toggle(O[nf]+)}x) {
        my $active = $1 eq 'On' ? 1 : 0;
        return if !$siteId;
        $active = $data->{reason} if $active && defined $data->{reason};
        readingsSingleUpdate($hash, "hotwordAwaiting_" . makeReadingName($siteId), $active, 1);

        my $ret = handleHotwordGlobal($hash, $active ? 'on' : 'off', $data, $active ? 'on' : 'off');
        push @updatedList, $ret if $ret && $defs{$ret};
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($topic =~ m{\Ahermes/intent/.*[:_]SetMute}x && defined $siteId) {
        return testmode_parse($hash, 'SetMute', $data) if defined $hash->{testline};
        $type = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
        $data->{requestType} = $type;

        # update Readings
        updateLastIntentReadings($hash, $topic,$data);
        handleIntentSetMute($hash, $data);
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ( $topic =~ m{\Ahermes/hotword/([^/]+)/detected}x ) {
        my $hotword = $1;
        if ( 0 && $siteId ) { #Beta-User: deactivated
            $device = ReadingsVal($hash->{NAME}, "siteId2ttsDevice_$siteId",undef);
            #$device //= $hash->{helper}->{TTS}->{$siteId} if defined $hash->{helper}->{TTS} && defined $hash->{helper}->{TTS}->{$siteId};
            $device //= $hash->{helper}->{SpeechDialog}->{config}->{wakeword}->{$hotword} if defined $hash->{helper}->{SpeechDialog} && defined $hash->{helper}->{SpeechDialog}->{config} && defined $hash->{helper}->{SpeechDialog}->{config}->{wakeword};
            if ($device) {
                AnalyzeCommand( $hash, "set $device activateVoiceInput" );
                readingsSingleUpdate($defs{$device}, 'rhasspy_dialogue', 'listening', 1);
                push @updatedList, $device;
            }
        }
        return \@updatedList if !$hash->{handleHotword} && !defined $hash->{helper}{hotwords};
        my $ret = handleHotwordDetection($hash, $hotword, $data);
        push @updatedList, $ret if $ret && $defs{$ret};
        $ret = handleHotwordGlobal($hash, $hotword, $data, 'detected');
        push @updatedList, $ret if $ret && $defs{$ret};
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ( $topic =~ m{\Ahermes/tts/say}x ) {
        return if !$hash->{siteId} || $siteId ne $hash->{siteId};
        my $ret = handleTtsMsgDialog($hash, $data);
        push @updatedList, $ret if $ret && $defs{$ret};
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($mute) {
        $data->{requestType} = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
        respond( $hash, $data, q{ }, 'endSession', 0 );
        #Beta-User: Da fehlt mir der Soll-Ablauf für das "room-listening"-Reading; das wird ja über einen anderen Topic abgewickelt
        return \@updatedList;
    }
    
    if ($topic =~ m{\Ahermes/nlu/intentNotRecognized}x && defined $siteId) {
        return testmode_parse($hash, 'intentNotRecognized', $data) if defined $hash->{testline} && defined $hash->{siteId} && $siteId eq $hash->{siteId};
        return handleIntentNotRecognized($hash, $data);
    }

    return testmode_parse($hash, $data->{intent}, $data) if defined $hash->{testline};

    my $command = $data->{input};
    $type = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
    $data->{requestType} = $type;
    my $intent = $data->{intent};

    # update Readings
    updateLastIntentReadings($hash, $topic,$data);

    return [$hash->{NAME}] if !_check_minimumConfidence($hash, $data);

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

    Log3($hash, 4, "[$name] dispatch result is @updatedList" );

    return \@updatedList;
}


# Antwort ausgeben
sub respond {
    my $hash     = shift // return;
    my $data     = shift // return;
    my $response = shift // getResponse( $hash, 'NoValidResponse' );
    my $topic    = shift // q{endSession};
    my $delay    = shift;

    my $contByDelay = $delay // $topic ne 'endSession';
    $delay //= ReadingsNum($hash->{NAME}, "sessionTimeout_$data->{siteId}", $hash->{sessionTimeout});

    if ( defined $hash->{helper}->{lng}->{$data->{sessionId}} ) {
        $response .= " $hash->{helper}->{lng}->{$data->{sessionId}}->{post}" if defined $hash->{helper}->{lng}->{$data->{sessionId}}->{post};
        $response = "$hash->{helper}->{lng}->{$data->{sessionId}}->{pre} $response" if defined $hash->{helper}->{lng}->{$data->{sessionId}}->{pre};
        delete $hash->{helper}->{lng}->{$data->{sessionId}};
    }

    if ( defined $hash->{testline} ) {
        $response = $response->{text} if ref $response eq 'HASH';
        push @{$hash->{helper}->{test}->{result}->{$hash->{testline}}}, "Response: $response";
        $hash->{testline}++;
        return testmode_next($hash);
    }

    my $type      = $data->{requestType} // return; #voice or text

    my $sendData;

    for my $key (qw(sessionId siteId customData lang)) {
        $sendData->{$key} = $data->{$key} if defined $data->{$key} && $data->{$key} ne 'null';
    }

    if (ref $response eq 'HASH') {
        #intentFilter
        $topic = q{continueSession};
        for my $key (keys %{$response}) {
            $sendData->{$key} = $response->{$key};
        }
    } elsif ( $topic eq 'continueSession' ) {
        $sendData->{text} = $response;
        $sendData->{intentFilter} = 'null';
    } elsif ( $delay ) {
        $sendData->{text} = $response;
        $topic = 'continueSession';
        my @ca_strings = configure_DialogManager($hash,$data->{siteId}, [qw(ConfirmAction Choice ChoiceRoom ChoiceDevice)], 'false', undef, 1 );
        $sendData->{intentFilter} = [@ca_strings];
    } else {
        $sendData->{text} = $response;
        $sendData->{intentFilter} = 'null';
    }

    my $json = _toCleanJSON($sendData);
    $response = $response->{text} if ref $response eq 'HASH' && defined $response->{text};
    $response = $response->{response} if ref $response eq 'HASH' && defined $response->{response};
    readingsBeginUpdate($hash);
    $type eq 'voice' ?
        readingsBulkUpdate($hash, 'voiceResponse', $response)
      : readingsBulkUpdate($hash, 'textResponse', $response);
    readingsBulkUpdate($hash, 'responseType', $type);
    readingsEndUpdate($hash,1);
    Log3($hash->{NAME}, 5, "Response is: $response");

    #check for msgDialog or SpeechDialog sessions
    my $identity = (split m{_$hash->{siteId}_}xms, $data->{sessionId},3)[0];
    if ( defined $hash->{helper}->{msgDialog} 
      && defined $hash->{helper}->{msgDialog}->{$identity} ){
        Log3($hash, 5, "respond deviated to msgDialog_respond for $identity.");
        return msgDialog_respond($hash, $identity, $response, $topic eq 'continueSession');
    } elsif (defined $hash->{helper}->{SpeechDialog} 
        && defined $hash->{helper}->{SpeechDialog}->{config}->{$identity} ) {
        Log3($hash, 5, "respond deviated to SpeechDialog_respond for $identity.");
        return SpeechDialog_respond($hash,$identity,$response,$topic eq 'continueSession', $contByDelay);
    }

    IOWrite($hash, 'publish', qq{hermes/dialogueManager/$topic $json});
    Log3($hash, 5, "published " . qq{hermes/dialogueManager/$topic $json});

    my $secondAudio = ReadingsVal($hash->{NAME}, "siteId2doubleSpeak_$data->{siteId}",undef) // return $hash->{NAME};
    sendSpeakCommand( $hash, { 
            siteId => $secondAudio, 
            text   => $response} );
    return $hash->{NAME};
}


# Antworttexte festlegen
sub getResponse {
    my $hash = shift;
    my $identifier = shift // return 'Code error! No identifier provided for getResponse!' ;
    my $subtype = shift;

    my $responses = defined $subtype
        ? $hash->{helper}{lng}->{responses}->{$identifier}->{$subtype}
        : getKeyValFromAttr($hash, $hash->{NAME}, 'response', $identifier) // $hash->{helper}{lng}->{responses}->{$identifier};
    return $responses if ref $responses eq 'HASH';
    return _shuffle_answer($responses);
}

sub getExtrapolatedResponse {
    my $hash = shift;
    my $identifier = shift // return 'Code error! No identifier provided for getResponse!' ;
    my $values = shift // return "Code error! No values provided for $identifier response!" ;
    my $subtype = shift;

    my @val = @{$values};

    my $response = getResponse($hash, $identifier, $subtype);
    $response =~ s{(\$[\w\]\[0-9]+)}{$1}eegx;
    return $response;
}


# Send text command to Rhasspy NLU
sub sendTextCommand {
    my $hash = shift // return;
    my $text = shift // return;
    
    my $data = {
         input => $text,
         sessionId => "$hash->{fhemId}.textCommand" #,
         #canBeEnqueued => 'true'
    };
    my $message = _toCleanJSON($data);
    my $topic = q{hermes/nlu/query};

    return IOWrite($hash, 'publish', qq{$topic $message});
}

# Sprachausgabe / TTS über RHASSPY
sub sendSpeakCommand {
    my $hash = shift;
    my $cmd  = shift;

    my $sendData = {
        init => {
            type          => 'notification',
            canBeEnqueued => 'true',
            customData    => "$hash->{LANGUAGE}.$hash->{fhemId}"
        }
    };
    if (ref $cmd eq 'HASH') {
        return 'speak with explicite params needs siteId and text as arguments!' if !defined $cmd->{siteId} || !defined $cmd->{text};
        $sendData->{siteId} = _getSiteIdbyRoom($hash, $cmd->{siteId});
        $sendData->{init}->{text} =  $cmd->{text};
    } else {
        my($unnamedParams, $namedParams) = parseParams($cmd);

        if (defined $namedParams->{siteId} && defined $namedParams->{text}) {
            $sendData->{siteId} = _getSiteIdbyRoom($hash, $namedParams->{siteId});
            $sendData->{init}->{text} = $namedParams->{text};
        } else {
            return 'speak needs siteId and text as arguments!';
        }
    }
    my $json = _toCleanJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/dialogueManager/startSession $json});
}

sub _getSiteIdbyRoom {
    my $hash   = shift // return;
    my $siteId = shift // return;

    my $siteIdList = ReadingsVal($hash->{NAME}, 'siteIds', $siteId);
    my $siteId2 = ReadingsVal($hash->{NAME}, "room2siteId_$siteId", $siteId);
    for my $id ($siteId2, $siteId) {
        return $1 if $siteIdList =~ m{\b($id)(?:[,]|\Z)}xmsi;
        return $1 if $siteIdList =~ m{\b($id[^,]+)(?:[,]|\Z)}xmsi;      ##no critic qw(Capture)
    }
    return $siteId;
}

# start intent recognition by Rhasspy service, see https://rhasspy.readthedocs.io/en/latest/reference/#nlu_query
sub msgDialog {
    my $hash = shift;
    my $cmd  = shift;

    readingsSingleUpdate($hash,'enableMsgDialog', $cmd eq 'enable' ? 1 : 0 ,1);

    return initialize_msgDialog($hash) if $cmd eq 'enable';
    return disable_msgDialog($hash);
}

# Send all devices, rooms, etc. to Rhasspy HTTP-API to update the slots
sub updateSlots {
    my $hash      = shift // return;
    my $checkdiff = shift;

    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};
    my $method   = q{POST};
    my $changed;

    initialize_devicemap($hash);
    my $tweaks = $hash->{helper}{tweaks}->{updateSlots};
    my $noEmpty = !defined $tweaks || defined $tweaks->{noEmptySlots} && $tweaks->{noEmptySlots} != 1 ? 1 : 0;

    # Collect everything and store it in arrays
    my @devices   = getAllRhasspyNames($hash);
    my @rooms     = getAllRhasspyRooms($hash);
    push @rooms, split m{,}x, $hash->{helper}{tweaks}->{extrarooms} if defined $hash->{helper}->{tweaks} && defined $hash->{helper}{tweaks}->{extrarooms};
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
        $changed = 1 if ReadingsVal($hash->{NAME},'.Shortcuts.ini','') ne $deviceData;
        readingsSingleUpdate($hash,'.Shortcuts.ini',$deviceData,0);
    }

    # If there are any devices, rooms, etc. found, create JSON structure and send it the the API
    if ( !@devices && !@rooms && !@channels && !@types && !@groups ) {
        $hash->{'.needTraining'} = 1 if $checkdiff && $changed && $hash->{autoTraining};
        return;
    }

    my $json;
    $deviceData = {};
    my $overwrite = defined $tweaks && defined $tweaks->{overwrite_all} ? $tweaks->{useGenericAttrs}->{overwrite_all} : 'true';
    $url = qq{/api/slots?overwrite_all=$overwrite};

    my @gdts = (qw(switch light media blind thermostat thermometer lock contact motion presence info));
    my @aliases = ();
    my @mainrooms = ();

    if ($hash->{useGenericAttrs}) {
        for my $gdt (@gdts) {
            my @names = ();
            my @groupnames = ();
            my @roomnames = ();
            my @devs = devspec2array("$hash->{devspec}");
            
            for my $device (@devs) {
                my $attrVal = AttrVal($device, 'genericDeviceType', '');
                my $gdtmap = { blind => 'blinds|shutter' , thermometer => 'HumiditySensor' , contact  => 'ContactSensor'};
                if ($attrVal eq $gdt || defined $gdtmap->{$gdt} && $attrVal =~ m{\A$gdtmap->{$gdt}\z}x ) {
                    push @names, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{names};
                    push @aliases, $hash->{helper}{devicemap}{devices}{$device}->{alias};
                    push @groupnames, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{groups} if defined $hash->{helper}{devicemap}{devices}{$device}->{groups};
                    push @mainrooms, (split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{rooms})[0];
                    push @roomnames, split m{,}x, $hash->{helper}{devicemap}{devices}{$device}->{rooms};
                }
            }
            @names = get_unique(\@names);
            @names = ('') if !@names && $noEmpty;
            $deviceData->{qq(${language}.${fhemId}.Device-$gdt)} = \@names if @names;
            @groupnames = get_unique(\@groupnames);
            @groupnames = ('') if !@groupnames && $noEmpty;
            $deviceData->{qq(${language}.${fhemId}.Group-$gdt)} = \@groupnames if @groupnames;
            @roomnames = get_unique(\@roomnames);
            @roomnames = ('') if !@roomnames && $noEmpty;
            $deviceData->{qq(${language}.${fhemId}.Room-$gdt)} = \@roomnames if @roomnames;
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

    $changed = 1 if ReadingsVal($hash->{NAME},'.slots','') ne $json;
    readingsSingleUpdate($hash,'.slots',$json,0);
    $hash->{'.needTraining'} = 1 if $checkdiff && $changed && $hash->{autoTraining};
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

# Use the HTTP-API to fetch all available siteIds
sub fetchIntents {
    my $hash   = shift // return;
    my $url    = q{/api/intents};
    my $method = q{GET};

    Log3($hash->{NAME}, 5, 'fetchIntents called');
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
        if ( ( $urls->{$url} eq 'updateSlots' || $urls->{$url} eq 'updateSentences' ) && $hash->{'.needTraining'} ) {
            trainRhasspy($hash);
            delete $hash->{'.needTraining'};
        }
        if ( $urls->{$url} eq 'training' ) {
            configure_DialogManager($hash, undef, undef, undef, 5 )
        }
    }
    elsif ( $url =~ m{api/profile}ix ) {
        my $ref; 
        #if ( !eval { $ref = decode_json($data) ; 1 } ) {
        if ( !eval { $ref = JSON->new->decode($data) ; 1 } ) {
            readingsEndUpdate($hash, 1);
            return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
        }
        my $siteIds;
        for (keys %{$ref}) {
            next if ref $ref->{$_} ne 'HASH' || !defined $ref->{$_}{satellite_site_ids};
            if ($siteIds) {
                $siteIds .= ',' . $ref->{$_}{satellite_site_ids}; #encode($cp,$ref->{$_}{satellite_site_ids});
            } else {
                $siteIds = $ref->{$_}{satellite_site_ids}; #encode($cp,$ref->{$_}{satellite_site_ids});
            }
        }
        if ( $siteIds ) {
            my @ids = uniq(split m{,}x,$siteIds);
            readingsBulkUpdate($hash, 'siteIds', join q{,}, @ids);
        }
    }
    elsif ( $url =~ m{api/intents}ix ) {
        my $refb; 
        #if ( !eval { $refb = decode_json($data) ; 1 } ) {
        if ( !eval { $refb = JSON->new->decode($data) ; 1 } ) {
            readingsEndUpdate($hash, 1);
            return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
        }
        my $intents = join q{,}, keys %{$refb}; #encode($cp,join q{,}, keys %{$refb});
        readingsBulkUpdate($hash, 'intents', $intents);
        configure_DialogManager($hash);
    }
    else {
        Log3($name, 3, qq(error while requesting $param->{url} - $data));
    }
    readingsBulkUpdate($hash, 'state', 'online');
    readingsEndUpdate($hash, 1);
    return;
}

sub _check_minimumConfidence {
    my $hash       = shift // return;
    my $data       = shift;
    my $noResponse = shift;

    my $intent = $data->{intent};
    #check minimum confidence levels
    my $minConf = 0.66;
    if ( defined $hash->{helper}{tweaks}{confidenceMin} ) {
        $minConf = $hash->{helper}{tweaks}{confidenceMin}->{$intent} // $hash->{helper}{tweaks}{confidenceMin}->{default} // $minConf;
    }
    if ( $minConf > $data->{confidence} ) {
        return if $noResponse;
        my $probability = _round($data->{confidence}*10)/10;
        my $response = getResponse( $hash, 'NoMinConfidence' );
        $response =_shuffle_answer($response);
        $response =~ s{(\$\w+)}{$1}eegx;
        respond( $hash, $data, $response );
        return;
    }
    return 1;
}

sub handleHotwordDetection {
    my $hash       = shift // return;
    my $hotword    = shift // return;
    my $data       = shift;

    my $siteId    = $data->{siteId} // return;

    readingsSingleUpdate($hash, 'hotword', "$hotword $siteId", 1);

    return if !defined $hash->{helper}{hotwords} || !defined $hash->{helper}{hotwords}->{$hotword};
    my $command = $hash->{helper}{hotwords}->{$hotword}->{$siteId} // $hash->{helper}{hotwords}->{$hotword}->{default} // return;
    return analyzeAndRunCmd($hash, $hash->{NAME}, $command, $hotword, $siteId);
}

sub handleHotwordGlobal {
    my $hash       = shift // return;
    my $hotword    = shift // return;
    my $data       = shift;
    my $mode       = shift;

    return if !defined $hash->{helper}{hotwords} || !defined $hash->{helper}{hotwords}->{global};
    my $cmd = $hash->{helper}{hotwords}->{global}->{$mode} // $hash->{helper}{hotwords}->{global}->{default} // return;
    my %specials = (
         '$VALUE'  => $hotword,
         '$MODE'   => $mode,
         '$DEVICE' => $hash->{NAME},
         '$ROOM'   => $data->{siteId},
         '$DATA'   => toJSON($data)
        );
    $cmd  = EvalSpecials($cmd, %specials);
    return AnalyzeCommandChain($hash, $cmd);
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
      my $device = getDeviceByName($hash, $room, $data->{Device}, $data->{Room});
      $data->{Device} = $device if $device && ref $device ne 'ARRAY'; #replace rhasspyName by FHEM device name;
    }

    my $subName = $custom->{function};
    return respond( $hash, $data, getResponse( $hash, 'DefaultError' ) ) if !defined $subName;

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
        respond( $hash, $data, $response );
        return ${$error}[1]; #comma separated list of devices to trigger
    } elsif ( ref $error eq 'HASH' ) {
        return setDialogTimeout($hash, $data, $timeout, $error);
    } else {
        $response = $error; # if $error && $error !~ m{Please.define.*first}x;
    }

    $response //= getResponse($hash, 'DefaultConfirmation');

    # Antwort senden
    return respond( $hash, $data, $response );
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
    $response //= getResponse($hash, 'DefaultError');
    return respond( $hash, $data, $response );
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
    $response = _shuffle_answer($shortcut->{response}) // getResponse($hash, 'DefaultConfirmation');
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
        $device = $ret if $ret && $ret !~ m{Please.define.*first}x && !defined $device;

        $response = $ret // _replace($hash, $response, \%specials);
    } elsif ( defined $shortcut->{fhem} ) {
        $cmd = $shortcut->{fhem} // return;
        Log3($hash->{NAME}, 5, "FHEM shortcut identified: $cmd, device name is $name");
        $cmd      = _replace($hash, $cmd, \%specials);
        $response = _replace($hash, $response, \%specials);
        _AnalyzeCommand($hash, $cmd);
    }
    $response = _ReplaceReadingsVal( $hash, $response );
    respond( $hash, $data, $response );
    # update Readings
    #updateLastIntentReadings($hash, $topic,$data);

    return $device;
}

# Handle incoming "SetOnOff" intents
sub handleIntentSetOnOff {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Device AND Value must exist
    return respond( $hash, $data, getResponse($hash, 'NoValidData') ) if !defined $data->{Device} || !defined $data->{Value};

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    my $room = getRoomName($hash, $data);
    my $device = getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, 'SetOnOff', 'SetOnOff' ) // return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') );
    return getNeedsClarification( $hash, $data, 'ParadoxData', 'Room', [$data->{Device}, $data->{Room}] ) if !$device;

    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $mapping = getMapping($hash, $device, 'SetOnOff') // return respond( $hash, $data, getResponse($hash, 'NoMappingFound') );
    my $value = $data->{Value};

    # Mapping found?
    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetOnOff', $device );
    my $cmdOn  = $mapping->{cmdOn} // 'on';
    my $cmdOff = $mapping->{cmdOff} // 'off';
    my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;

    # execute Cmd
    analyzeAndRunCmd($hash, $device, $cmd);
    Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

    # Define response
    my $response;
    if ( defined $mapping->{response} ) { 
        #my $numericValue = $value eq 'on' ? 1 : 0;
        $response = _getValue($hash, $device, _shuffle_answer($mapping->{response}), $value eq 'on' ? 1 : 0, $room); 
        Log3($hash->{NAME}, 5, "Response is $response" );
    }
    else { $response = getResponse($hash, 'DefaultConfirmation'); }


    # Send response
    $response //= getResponse($hash, 'DefaultError');
    respond( $hash, $data, $response );
    return $device;
}

sub handleIntentSetOnOffGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetOnOffGroup called");

    return respond( $hash, $data, getResponse($hash, 'NoValidData') ) if !defined $data->{Value};

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetOnOffGroup' );

    my $devices = getDevicesByGroup($hash, $data);
    return testmode_next($hash) if _isUnexpectedInTestMode($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};
        
    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') ) if !keys %{$devices}; 

    my $value = $data->{Value};

    my $updatedList;
    my $delaysum = 0;
    my $init_delay = 0;
    my $needs_sorting = (@{$hash->{".asyncQueue"}});

    for my $device (@devlist) {
        my $mapping = getMapping($hash, $device, 'SetOnOff') // next;

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
    respond( $hash, $data, getResponse($hash, 'DefaultConfirmation') );
    return $updatedList;
}

# Handle incoming "SetTimedOnOff" intents
sub handleIntentSetTimedOnOff {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetTimedOnOff called");

    return respond( $hash, $data, getResponse( $hash, 'duration_not_understood' ) ) 
    if !defined $data->{Hourabs} && !defined $data->{Hour} && !defined $data->{Min} && !defined $data->{Sec};

    # Device AND Value must exist
    return respond( $hash, $data, getResponse($hash, 'NoValidData') ) if !defined $data->{Device} || !defined $data->{Value};

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    my $room = getRoomName($hash, $data);
    my $device = getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, 'SetOnOff', 'SetOnOff') // return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') );
    return getNeedsClarification( $hash, $data, 'ParadoxData', 'Room', [$data->{Device}, $data->{Room}] ) if !$device;
    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';
    my $mapping = getMapping($hash, $device, 'SetOnOff') // return respond( $hash, $data, getResponse($hash, 'NoMappingFound') );
    my $value = $data->{Value};

    # Mapping found?
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetTimedOnOff', $device );
    my $cmdOn  = $mapping->{cmdOn} // 'on';
    my $cmdOff = $mapping->{cmdOff} // 'off';
    my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;
    $cmd .= "-for-timer";

    my $allset = getAllSets($device);
    return respond( $hash, $data, getResponse($hash, 'NoTimedOnDeviceFound') ) if $allset !~ m{\b$cmd(?:[\b:\s]|\Z)}xms;

    my (undef , undef, $secsfromnow) = _getSecondsfromData($data);

    $cmd .= " $secsfromnow";
    # execute Cmd
    analyzeAndRunCmd($hash, $device, $cmd);
    Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

    # Define response
    my $response;
    if ( defined $mapping->{response} ) { 
        my $numericValue = $value eq 'on' ? 1 : 0;
        $response = _getValue($hash, $device, _shuffle_answer($mapping->{response}), $numericValue, $room); 
        Log3($hash->{NAME}, 5, "Response is $response" );
    }
    else { $response = getResponse($hash, 'DefaultConfirmation'); }
    # Send response
    $response //= getResponse($hash, 'DefaultError');
    respond( $hash, $data, $response );
    return $device; 
}


sub handleIntentSetTimedOnOffGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetTimedOnOffGroup called");

    return respond( $hash, $data, getResponse( $hash, 'NoValidData' ) ) if !defined $data->{Value}; 
    return respond( $hash, $data, getResponse( $hash, 'duration_not_understood' ) ) 
    if !defined $data->{Hourabs} && !defined $data->{Hour} && !defined $data->{Min} && !defined $data->{Sec};

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetTimedOnOffGroup' );

    my $devices = getDevicesByGroup($hash, $data);
    return testmode_next($hash) if _isUnexpectedInTestMode($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};

    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') ) if !keys %{$devices}; 

    #calculate duration for on/off-timer
    my (undef , undef, $secsfromnow) = _getSecondsfromData($data);

    my $value = $data->{Value};

    my $updatedList;
    my $init_delay = 0;
    my $delaysum = 0;
    my $needs_sorting = (@{$hash->{".asyncQueue"}});

    for my $device (@devlist) {
        my $mapping = getMapping($hash, $device, 'SetOnOff');

        # Mapping found?
        next if !defined $mapping;

        my $cmdOn  = $mapping->{cmdOn} // 'on';
        my $cmdOff = $mapping->{cmdOff} // 'off';
        my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;
        $cmd .= "-for-timer";
        my $allset = getAllSets($device);
        if ($allset !~ m{\b$cmd(?:[\b:\s]|\Z)}xms) {
            Log3($hash->{NAME}, 3, "Running command [$cmd] on device [$device] is not possible!");
            next;
        }
        $cmd .= " $secsfromnow";

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
    respond( $hash, $data, getResponse($hash, 'DefaultConfirmation') );
    return $updatedList;
}


# Handle incomint GetOnOff intents
sub handleIntentGetOnOff {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    return respond( $hash, $data, getResponse($hash, 'NoValidData') ) if !defined $data->{State} || !defined $data->{Device};

    my $response;

    my $room = getRoomName($hash, $data);
    my $device = getDeviceByName($hash, $room, $data->{Device}, undef, 'GetOnOff') // return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') );

    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $deviceName = $data->{Device};
    my $mapping = getMapping($hash, $device, 'GetOnOff') // return respond( $hash, $data, getResponse($hash, 'NoMappingFound') );

    my $value = _getOnOffState($hash, $device, $mapping);

    # Define reponse
    if ( defined $mapping->{response} ) { 
        $response = _getValue($hash, $device, _shuffle_answer($mapping->{response}), $value, $room);
    } else {
        my $stateResponseType = $internal_mappings->{stateResponseType}->{$data->{State}};
        $response = _shuffle_answer($hash->{helper}{lng}->{stateResponses}{$stateResponseType}->{$value});
        $response =~ s{(\$\w+)}{$1}eegx;
    }
    return respond( $hash, $data, $response );
}


sub isValidData {
    my $data = shift // return 0;

    return 1 if 
        exists $data->{Device} && ( exists $data->{Value} || exists $data->{Change})
        || !exists $data->{Device} && defined $data->{Change} 
            && defined $internal_mappings->{Change}->{$data->{Change}}

        # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
        #||!exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && $data->{Type} =~ 
        #m{\A$hash->{helper}{lng}->{Change}->{regex}->{volume}\z}xim;
        #|| !exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && $data->{Type} eq 'volume';
        || !exists $data->{Device} && defined $data->{Type} && exists $data->{Value}; # && $data->{Type} =~ m{\A(?:volume|temperature)\z}x;

    return 0;
}

sub handleIntentSetNumericGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentSetNumericGroup called');

    return respond( $hash, $data, getResponse($hash, 'NoValidData') ) if !exists $data->{Value} && !exists $data->{Change};

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetNumericGroup' );

    my $devices = getDevicesByGroup($hash, $data);
    return testmode_next($hash) if _isUnexpectedInTestMode($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};

    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond( $hash, $data, getResponse( $hash, 'NoDeviceFound' ) ) if !keys %{$devices}; 

    my $value = $data->{Value};

    my $updatedList;
    my $init_delay = 0;
    my $delaysum = 0;
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
    respond( $hash, $data, getResponse( $hash, 'DefaultConfirmation' ) );
    return $updatedList;
}

# Eingehende "SetNumeric" Intents bearbeiten
sub handleIntentSetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $device = $data->{'.DevName'};
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    if ( !defined $device && !isValidData($data) ) {
        return if defined $data->{'.inBulk'};
        return respond( $hash, $data, getResponse( $hash, 'NoValidData' ) );
    }

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    my $unit   = $data->{Unit};
    my $change = $data->{Change};
    my $type   = $data->{Type};
    
    if ( !defined $type && defined $change ){
        $type   = $internal_mappings->{Change}->{$change}->{Type};
        $data->{Type} = $type if defined $type;
    }
    my $subType = $data->{Type};
    $subType =  'desired-temp' if defined $subType && $subType eq 'temperature';

    my $value  = $data->{Value};
    my $room   = getRoomName($hash, $data);

    # Gerät über Name suchen, oder falls über Lautstärke ohne Device getriggert wurde das ActiveMediaDevice suchen
    if ( !defined $device && exists $data->{Device} ) {
        $device = getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, $subType, 'SetNumeric' );
    } elsif ( defined $type && $type eq 'volume' ) {
        $device = 
            getActiveDeviceForIntentAndType($hash, $room, 'SetNumeric', $type) 
            // return respond( $hash, $data, getResponse( $hash, 'NoActiveMediaDevice') );
    } elsif ( !defined $data->{'.DevName'} ) {
        $device = getDeviceByIntentAndType($hash, $room, 'SetNumeric', $type, $subType);
    }

    return respond( $hash, $data, getResponse( $hash, 'NoDeviceFound' ) ) if !defined $device;

    #more than one device
    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $mapping = getMapping($hash, $device, 'SetNumeric', { type => $type, subType => $subType });

    if ( !defined $mapping ) {
        if ( defined $data->{'.inBulk'} ) {
            #Beta-User: long forms to later add options to check upper/lower limits for pure on/off devices
            return;
        } else { 
           return respond( $hash, $data, getResponse( $hash, 'NoMappingFound' ) );
        }
    }

    # Mapping and device found -> execute command
    my $cmd     = $mapping->{cmd} // return defined $data->{'.inBulk'} ? undef : respond( $hash, $data, getResponse( $hash, 'NoMappingFound' ) );
    my $part    = $mapping->{part};
    my $minVal  = $mapping->{minVal};
    my $maxVal  = $mapping->{maxVal};
    my $useMap  = defined $hash->{helper}{devicemap}{devices}{$device}->{numeric_ValueMap} 
                  && defined $hash->{helper}{devicemap}{devices}{$device}->{numeric_ValueMap}->{$value} ? $hash->{helper}{devicemap}{devices}{$device}->{numeric_ValueMap}->{$value} : undef;

    $minVal     =   0 if defined $minVal && !looks_like_number($minVal);
    $maxVal     = 100 if defined $maxVal && !looks_like_number($maxVal);
    my $checkMinMax = defined $minVal && defined $maxVal ? 1 : 0;

    my $diff    = $value // $mapping->{step} // 10;

    my $up = $change // 0;
    if ( defined $change ) {
        $up = $internal_mappings->{Change}->{$change}->{up} 
             // $change =~ m{\A$internal_mappings->{regex}->{upward}\z}xi ? 1 : 0;
    }

    my $forcePercent = ( defined $mapping->{map} && lc $mapping->{map} eq 'percent' ) ? 1 : 0;

    # Alten Wert bestimmen
    my $oldVal  = _getValue($hash, $device, $mapping->{currentVal});

    if (defined $part) {
        my @tokens = split m{\s+}x, $oldVal;
        $oldVal = $tokens[$part] if @tokens >= $part;
    }

    # Neuen Wert bestimmen
    my $newVal;
    my $ispct = defined $unit && $unit eq 'percent' ? 1 : 0;

    if ( !defined $change ) {
        # Direkter Stellwert ("Stelle Lampe auf 50")
        #if ($unit ne 'Prozent' && defined $value && !defined $change && !$forcePercent) {
        if ( !defined $value ) {
            #do nothing...
        } elsif ( !$ispct && !$forcePercent ) {
            $newVal = $value;
        } elsif ( ( $ispct || $forcePercent ) && $checkMinMax ) { 
            # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)

            # Wert von Prozent in Raw-Wert umrechnen
            $newVal = $value;
            $newVal = _round(($newVal * (($maxVal - $minVal) / 100)) + $minVal);
        }
    } else { # defined $change
        # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
        #elsif ((!defined $unit || $unit ne 'Prozent') && defined $change && !$forcePercent) {
        if ( $change eq 'cmdStop' || $useMap ) {
            $newVal = $oldVal // 50;
        } elsif ( ( !defined $unit || !$ispct ) && !$forcePercent ) {
            $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
        }
        # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
        elsif ( ( $ispct || $forcePercent ) && $checkMinMax ) {
            my $diffRaw = _round($diff * ($maxVal - $minVal) / 100);
            $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
            $newVal = max( $minVal, min( $maxVal, $newVal ) );
        }
    }

    if ( !defined $newVal ) {
        return defined $data->{'.inBulk'} ? undef : respond( $hash, $data, getResponse( $hash, 'NoNewValDerived' ) );
    }

    # limit to min/max  (if set)
    $newVal = max( $minVal, $newVal ) if defined $minVal;
    $newVal = min( $maxVal, $newVal ) if defined $maxVal;
    $data->{Value} //= $newVal;
    $data->{Type}  //= $type;
    delete $data->{Change} if defined $data->{Change} && $data->{Change} ne 'cmdStop';

    #check if confirmation is required
    return $hash->{NAME} if !defined $data->{'.inBulk'} && !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetNumeric', $device );

    # execute Cmd
    !defined $change || $change ne 'cmdStop' || !defined $mapping->{cmdStop} 
            ? !defined $useMap ? analyzeAndRunCmd($hash, $device, $cmd, $newVal)
                               : analyzeAndRunCmd($hash, $device, $useMap)
            : analyzeAndRunCmd($hash, $device, $mapping->{cmdStop});

    #venetian blind special
    my $specials = $hash->{helper}{devicemap}{devices}{$device}{venetian_specials};
    if ( defined $specials ) {
        my $vencmd = $specials->{setter} // $cmd;
        my $vendev = $specials->{device} // $device;
        if ( defined $change && $change ne 'cmdStop' ) {
            analyzeAndRunCmd($hash, $vendev, defined $specials->{CustomCommand} ? $specials->{CustomCommand} :$vencmd , $newVal) if $device ne $vendev || $cmd ne $vencmd;
        } elsif ( defined $change && $change eq 'cmdStop' && defined $specials->{stopCommand} ) {
            analyzeAndRunCmd($hash, $vendev, $specials->{stopCommand});
        }
    }

    return $device if defined $data->{'.inBulk'};

    # get response 
    defined $mapping->{response} 
        ? $response = _getValue($hash, $device, _shuffle_answer($mapping->{response}), $newVal, $room) 
        : $response = getResponse($hash, 'DefaultConfirmation'); 

    # send response
    $response //= getResponse($hash, 'DefaultError');
    respond( $hash, $data, $response );
    return $device;
}


# Eingehende "GetNumeric" Intents bearbeiten
sub handleIntentGetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $value;

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type oder Device muss existieren
    return respond( $hash, $data, getResponse( $hash, 'DefaultError' ) ) if !exists $data->{Type} && !exists $data->{Device};

    my $type = $data->{Type};
    my $subType = $data->{subType} // $type;
    my $room = getRoomName($hash, $data);

    # Get suitable device
    my $device = exists $data->{Device}
        ? getDeviceByName($hash, $room, $data->{Device}, undef, 'GetNumeric')
        : getDeviceByIntentAndType($hash, $room, 'GetNumeric', $type)
        // return respond( $hash, $data, getResponse( $hash, 'NoDeviceFound' ) );

    #more than one device
    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $mapping = getMapping($hash, $device, 'GetNumeric', { type => $type, subType => $subType })
        // return respond( $hash, $data, getResponse( $hash, 'NoMappingFound' ) );

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
    $value = _round($value * ($maxVal - $minVal) / 100 + $minVal) if $forcePercent;

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
        return respond( $hash, $data, _getValue( $hash, $device, $mapping->{response}, $value, $location ) );
    }
    my $responses = getResponse( $hash, 'Change' );

    # Antwort falls mappingType oder type matched
    my $response = 
        $responses->{$mappingType} // $responses->{$type};
        $response = $response->{$isNumber} if ref $response eq 'HASH';

    # Antwort falls mappingType auf regex (en bzw. de) matched
    if ( !defined $response && $mappingType=~ m{\A$internal_mappings->{regex}->{setTarget}\z}xim ) {
        $response = $responses->{setTarget};
    }
    if ( !defined $response ) {
        #or not and at least know the type...?
        $response = defined $mappingType
            ? $responses->{knownType}
            : $responses->{unknownType};
    }

    # Variablen ersetzen?
    $response =_shuffle_answer($response);
    $response =~ s{(\$\w+)}{$1}eegx;
    # Antwort senden
    return respond( $hash, $data, $response );
}


# Handle incoming "GetState" intents
sub handleIntentGetState {
    my $hash = shift // return;
    my $data = shift // return;
    my $device = $data->{Device} // q{RHASSPY};

    my $response;
    Log3($hash->{NAME}, 5, 'handleIntentGetState called');

    my $room = getRoomName($hash, $data);

    my $type = $data->{Type} // $data->{type};
    my @scenes; my $deviceNames; my $sceneNames;
    if ($device eq 'RHASSPY') {
        $type  //= 'generic';
        return respond( $hash, $data, getResponse($hash, 'NoValidData')) if $type !~ m{\Ageneric|control|info|scenes|rooms\z}x;
        $response = getResponse( $hash, 'getRHASSPYOptions', $type );
        my $roomNames = '';
        if ( $type eq 'rooms' ) {
            my @rooms = getAllRhasspyMainRooms($hash);
            $roomNames = _array2andString( $hash, \@rooms);
            $response =~ s{(\$\w+)}{$1}eegx;
            return respond( $hash, $data, $response);
        }

        my @names; my @grps;
        my @intents = qw(SetNumeric SetOnOff GetNumeric GetOnOff MediaControls GetState SetScene);
        @intents = qw(GetState GetNumeric) if $type eq 'info';
        @intents = qw(SetScene) if $type eq 'scenes';

        my @devsInRoom = values %{$hash->{helper}{devicemap}{rhasspyRooms}{$room}};
        return respond( $hash, $data, getResponse($hash, 'NoDeviceFound')) if !@devsInRoom;
        @devsInRoom = get_unique(\@devsInRoom);

        for my $intent (@intents) {
            for my $dev (@devsInRoom) {
                next if !defined $hash->{helper}{devicemap}{devices}{$dev}->{intents}->{$intent};
                push @names, $hash->{helper}{devicemap}{devices}{$dev}->{alias};
                if ($intent eq 'SetScene') {
                    for my $scene (keys %{$hash->{helper}{devicemap}{devices}{$dev}{intents}{SetScene}->{SetScene}} ) {
                        next if $scene eq 'cmdFwd' || $scene eq 'cmdBack';
                        push @scenes , $hash->{helper}{devicemap}{devices}{$dev}{intents}{SetScene}->{SetScene}->{$scene};
                    }
                } elsif ( $intent =~ m{SetNumeric|SetOnOff}x ) {
                     my $devgroups = $hash->{helper}{devicemap}{devices}{$dev}->{groups} // q{};
                     push @grps, (split m{,}xi, $devgroups, 2)[0];
                }
            }
        }

        return respond( $hash, $data, getResponse($hash, 'NoDeviceFound')) if !@names;

        @names  = uniq(@names, @grps);
        @scenes = uniq(@scenes) if @scenes;

        $deviceNames = _array2andString( $hash, \@names );
        $sceneNames = !@scenes ? '' : _array2andString( $hash, \@scenes );

        $response =~ s{(\$\w+)}{$1}eegx;
        return respond( $hash, $data, $response);
    }

    my $deviceName = $device;
    my $intent = 'GetState';

    $device = getDeviceByName($hash, $room, $device, $data->{Room}) // return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') );
    return respond( $hash, $data, getExtrapolatedResponse($hash, 'ParadoxData', [$data->{Device}, $data->{Room}], 'hint') ) if !$device;

    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    if ( defined $type && $type eq 'scenes' ) {
        $response = getResponse( $hash, 'getRHASSPYOptions', $type );
        @scenes = values %{$hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene}};
        @scenes = uniq(@scenes) if @scenes;
        $sceneNames = !@scenes ? '' : _array2andString( $hash, \@scenes );
        $deviceNames = $deviceName;
        $response =~ s{(\$\w+)}{$1}eegx;
        return respond( $hash, $data, $response);
    }

    $type //= 'GetState';
    my $mapping = getMapping($hash, $device, 'GetState', $type) // return respond( $hash, $data, getResponse($hash, 'NoMappingFound') );

    if ( defined $data->{Update} ) {
        my $cmd = $mapping->{update} // return respond( $hash, $data, getResponse($hash, 'DefaultError') );
        # execute Cmd
        analyzeAndRunCmd($hash, $device, $cmd);
        $response = getResponse( $hash, 'getStateResponses', 'update');
        $response =~ s{(\$\w+)}{$1}eegx;
    } elsif ( defined $mapping->{response} ) {
        $response = _getValue($hash, $device, _shuffle_answer($mapping->{response}), undef, $room);
        $response = _ReplaceReadingsVal($hash, _shuffle_answer($mapping->{response})) if !$response; #Beta-User: case: plain Text with [device:reading]
    } elsif ( defined $data->{type} || defined $data->{Type} ) {
        my $reading = $data->{Reading} // 'STATE';
        $response = getResponse( $hash, 'getStateResponses', $type ) // getResponse( $hash, 'NoValidIntentResponse');
        $response =~ s{(\$\w+)}{$1}eegx;
        commaconversion
        $response = _ReplaceReadingsVal($hash, $response );
        $response =~ s{\.}{\,}gx if $hash->{helper}{lng}->{commaconversion} && $data->{Type} eq 'price';
    } else {
        $response = getResponse( $hash, 'getStateResponses', 'STATE' );
        $response =~ s{(\$\w+)}{$1}eegx;
        $response = _ReplaceReadingsVal($hash, $response );
    }

    # Antwort senden
    $response //= getResponse($hash, 'DefaultError');
    return respond( $hash, $data, $response );
}


# Handle incomint "MediaControls" intents
sub handleIntentMediaControls {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentMediaControls called");

    # At least one command has to be received
    return respond( $hash, $data, getResponse($hash, 'NoValidData') ) if !exists $data->{Command};

    my $room = getRoomName($hash, $data);
    my $command = $data->{Command};

    my $device;

    # Search for matching device
    if (exists $data->{Device}) {
        $device = getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, 'MediaControls', 'MediaControls' ) // return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') );
        return getNeedsClarification( $hash, $data, 'ParadoxData', 'Room', [$data->{Device}, $data->{Room}] ) if !$device;
        return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';
    } else {
        $device = getActiveDeviceForIntentAndType($hash, $room, 'MediaControls', undef) 
        // return respond( $hash, $data, getResponse($hash, 'NoActiveMediaDevice') );
    }

    my $mapping = getMapping($hash, $device, 'MediaControls') // return respond( $hash, $data, getResponse($hash, 'NoMappingFound') );

    return respond( $hash, $data, getResponse($hash, 'NoMappingFound') ) if !defined $mapping->{$command};

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'MediaControls', $device );
    my $cmd = $mapping->{$command};
    # Execute Cmd
    analyzeAndRunCmd($hash, $device, $cmd);
    # Define voice response
    my $response = defined $mapping->{response} ?
        _getValue($hash, $device, _shuffle_answer($mapping->{response}), $command, $room)
        : getResponse($hash, 'DefaultConfirmation');

    # Send voice response
    respond( $hash, $data, $response );
    return $device;
}

# Handle incoming "SetScene" intents
sub handleIntentSetScene{
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetScene called");
    return respond( $hash, $data, getResponse( $hash, 'NoValidData' ) ) if !defined $data->{Scene} && (!defined $data->{Get} || $data->{Get} ne 'scenes');

    # Device AND Scene are optimum exist

    return respond( $hash, $data, getResponse( $hash, 'NoDeviceFound' ) ) if !exists $data->{Device};

    my $room = getRoomName($hash, $data);
    my $scene = $data->{Scene};
    my $device = getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, 'SetScene','SetScene' ) // return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') );
    return getNeedsClarification( $hash, $data, 'ParadoxData', 'Room', [$data->{Device}, $data->{Room}] ) if !$device;

    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $mapping = getMapping($hash, $device, 'SetScene');

    #Welche (Szenen | Szenarien | Einstellungen){Get:scenes} (kennt|kann) [(der | die | das)] $de.fhem.Device-scene{Device}
    if ( defined $data->{Get} && $data->{Get} eq 'scenes' ) {
        delete $data->{Get};
        my $response = getResponse( $hash, 'RequestChoiceGeneric' );
        my @scenes = values %{$hash->{helper}{devicemap}{devices}{$device}{intents}{SetScene}->{SetScene}};
        @scenes = uniq(@scenes) if @scenes;
        my $options = !@scenes ? '' : _array2andString( $hash, \@scenes );
        $response =~ s{(\$\w+)}{$1}eegx;

        #until now: only extended test code
        $data->{customData} = join q{,}, @scenes;
        my $toActivate = [qw(Choice CancelAction)];
        return setDialogTimeout($hash, $data, _getDialogueTimeout($hash), $response, $toActivate);
    }

    # restore HUE scenes
    $scene = qq([$scene]) if $scene =~ m{id=.+}xms;

    # Mapping found?
    return respond( $hash, $data, getResponse( $hash, 'NoValidData' ) ) if !$device || !defined $mapping;

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetScene', $device );

    my $cmd = qq(scene $scene);
    $cmd = $scene if $scene eq 'cmdBack' || $scene eq 'cmdFwd';

    # execute Cmd
    analyzeAndRunCmd($hash, $device, $cmd);
    Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

    # Define response
    my $response = _shuffle_answer($mapping->{response}) // getResponse( $hash, 'DefaultConfirmation' );

    respond( $hash, $data, $response );
    return $device;
}

# Handle incoming "GetTime" intents
sub handleIntentGetTime {
    my $hash = shift // return;
    my $data = shift // return;
    Log3($hash->{NAME}, 5, "handleIntentGetTime called");

    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime;
    my $response = getResponse( $hash, 'timeRequest' );
    $response =~ s{(\$\w+)}{$1}eegx;
    Log3($hash->{NAME}, 5, "Response: $response");

    # Send voice reponse
    return respond( $hash, $data, $response );
}


# Handle incoming "GetDate" intents
sub handleIntentGetDate {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentGetDate called");

    my $weekDay  = strftime( '%A', localtime );
    $weekDay  = $hash->{helper}{lng}{words}->{$weekDay} if defined $hash->{helper}{lng}{words}->{$weekDay};
    my $month = strftime( '%B', localtime );
    $month  = $hash->{helper}{lng}{words}->{$month} if defined $hash->{helper}{lng}{words}->{$month};
    my $year = strftime( '%G', localtime );
    my $day = strftime( '%e', localtime );
    my $response = getResponse( $hash, 'weekdayRequest' );
    $response =~ s{(\$\w+)}{$1}eegx;

    Log3($hash->{NAME}, 5, "Response: $response");

    # Send voice reponse
    return respond( $hash, $data, $response );
}


# Eingehende "MediaChannels" Intents bearbeiten
sub handleIntentMediaChannels {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentMediaChannels called");

    # Mindestens Channel muss übergeben worden sein
    return respond( $hash, $data, getResponse($hash, 'NoMediaChannelFound') ) if !exists $data->{Channel};

    my $room = getRoomName($hash, $data);
    my $channel = $data->{Channel};

    # Passendes Gerät suchen
    my $device = exists $data->{Device}
        ? getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, 'MediaChannels', 'MediaChannels' )
        : getDeviceByMediaChannel($hash, $room, $channel);
    return respond( $hash, $data, getResponse($hash, 'NoMediaChannelFound') ) if !defined $device;
    return getNeedsClarification( $hash, $data, 'ParadoxData', 'Room', [$data->{Device}, $data->{Room}] ) if !$device;

    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $cmd = $hash->{helper}{devicemap}{devices}{$device}{Channels}{$channel} // return respond( $hash, $data, getResponse($hash, 'NoMediaChannelFound') );

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'MediaChannels', $device );
    # Cmd ausführen
    analyzeAndRunCmd($hash, $device, $cmd);

    # Antwort senden
    respond( $hash, $data, getResponse($hash, 'DefaultConfirmation') );
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
        return respond( $hash, $data, getResponse( $hash, 'NoValidData' ) );
    }

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    my $room = getRoomName($hash, $data);
    my $color = $data->{Color} // q{};

    # Search for matching device and command
    $device = getDeviceByName( $hash, $room, $data->{Device}, $data->{Room}, 'SetColor', 'SetColor' ) if !defined $device;
    return respond( $hash, $data, getResponse($hash, 'NoDeviceFound') ) if !defined $device;
    return getNeedsClarification( $hash, $data, 'ParadoxData', 'Room', [$data->{Device}, $data->{Room}] ) if !$device;

    return respondNeedsChoice($hash, $data, $device) if ref $device eq 'ARRAY';

    my $cmd = getKeyValFromAttr($hash, $device, 'rhasspyColors', $color, undef);
    my $cmd2;
    if (defined $hash->{helper}{devicemap}{devices}{$device}{color_specials}
        && defined $hash->{helper}{devicemap}{devices}{$device}{color_specials}->{CommandMap}) {
        $cmd2 = $hash->{helper}{devicemap}{devices}{$device}{color_specials}->{CommandMap}->{$color};
    }

    return if $inBulk && !defined $device;
    return respond( $hash, $data, getResponse( $hash, 'NoDeviceFound' ) ) if !defined $device;

    #check if confirmation is required
    return $hash->{NAME} if !defined $data->{'.inBulk'} && !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetColor', $device );

    if ( defined $cmd || defined $cmd2 ) {
        $response = getResponse($hash, 'DefaultConfirmation');
        # Execute Cmd
        analyzeAndRunCmd( $hash, $device, defined $cmd ? $cmd : $cmd2 );
    } else {
        $response = _runSetColorCmd($hash, $device, $data, $inBulk);
    }
    # Send voice response
    $response //= getResponse($hash, 'DefaultError');
    respond( $hash, $data, $response ) if !$inBulk;
    return $device;
}

sub _runSetColorCmd {
    my $hash   = shift // return;
    my $device = shift // return;
    my $data   = shift // return;
    my $inBulk = shift // 0;

    my $color  = $data->{Color};

    my $mapping = $hash->{helper}{devicemap}{devices}{$device}{intents}{SetColorParms} // return $inBulk ?undef : respond( $hash, $data, getResponse( $hash, 'NoMappingFound' ) );

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
            $error = _AnalyzeCommand($hash, "set $device $cmd");
            return if $inBulk;
            Log3($hash->{NAME}, 5, "Setting $device to $cmd");
            return respond( $hash, $data, $error ) if $error;
            return getResponse($hash, 'DefaultConfirmation');
        } elsif ( defined $data->{$kw} && defined $mapping->{$_} ) {
            my $value = _round( ( $mapping->{$_}->{maxVal} - $mapping->{$_}->{minVal} ) * $data->{$kw} / ( $kw eq 'Hue' ? 360 : 100 ) ) ;
            $value = min(max($mapping->{$_}->{minVal}, $value), $mapping->{$_}->{maxVal});
            $error = _AnalyzeCommand($hash, "set $device $mapping->{$_}->{cmd} $value");
            return if $inBulk;
            Log3($hash->{NAME}, 5, "Setting color to $value");
            return respond( $hash, $data, $error ) if $error;
            return getResponse($hash, 'DefaultConfirmation');
        }
    }

    #shortcut: Rgb field is used or color is in HEX value and rgb is a possible command
    if ( ( defined $data->{Rgb} || defined $color && $color =~ m{\A[[:xdigit:]]\z}x ) && defined $mapping->{rgb} ) {
        $color = $data->{Rgb} if defined $data->{Rgb};
        $error = _AnalyzeCommand($hash, "set $device $mapping->{rgb}->{cmd} $color");
        return if $inBulk;
        Log3($hash->{NAME}, 5, "Setting rgb-color to $color");
        return respond( $hash, $data, $error ) if $error;
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
        $error = _AnalyzeCommand($hash, "set $device $rgbcmd $rgb");
        return if $inBulk;
        Log3($hash->{NAME}, 5, "Setting rgb-color to $rgb using hue");
        return respond( $hash, $data, $error ) if $error;
        return getResponse($hash, 'DefaultConfirmation');
    }

    if ( defined $data->{Colortemp} && defined $mapping->{rgb} && looks_like_number($data->{Colortemp}) ) {
        
        my $ct = $data->{Colortemp}*50 + 2000; #FHEMWIKI indicates typical range from 2000 to 6500
        my ($r, $g, $b) = _ct2rgb($ct);
        my $rgb = uc sprintf( "%2.2X%2.2X%2.2X", $r, $g, $b );

        return "mapping problem in _ct2rgb" if !defined $rgb;
        $error = _AnalyzeCommand($hash, "set $device $mapping->{rgb}->{cmd} $rgb");
        return if $inBulk;
        Log3($hash->{NAME}, 5, "Setting color-temperature to $ct");
        return respond( $hash, $data, $error ) if $error;
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

    return respond( $hash, $data, getResponse( $hash, 'NoValidData' ) ) if !exists $data->{Color} && !exists $data->{Rgb} &&!exists $data->{Saturation} && !exists $data->{Colortemp} && !exists $data->{Hue};

    my $redirects = getIsVirtualGroup($hash,$data);
    return $redirects if $redirects;

    #check if confirmation is required
    return $hash->{NAME} if !$data->{Confirmation} && getNeedsConfirmation( $hash, $data, 'SetColorGroup' );

    my $devices = getDevicesByGroup($hash, $data);
    return testmode_next($hash) if _isUnexpectedInTestMode($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};

    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return respond( $hash, $data, getResponse( $hash, 'NoDeviceFound' ) ) if !keys %{$devices}; 

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
    respond( $hash, $data, getResponse( $hash, 'DefaultConfirmation' ) );
    return $updatedList;
}



# Handle incoming Timer, SetTimer and GetTimer intents
sub handleIntentTimer {
    my $hash = shift;
    my $data = shift // return;
    my $siteId = $data->{siteId} // return;
    my $name = $hash->{NAME};

    Log3($name, 5, 'handleIntentSetTimer called');

    return respond( $hash, $data, getResponse( $hash, 'duration_not_understood' ) ) 
    if !defined $data->{Hourabs} && !defined $data->{Hour} && !defined $data->{Min} && !defined $data->{Sec} && !defined $data->{CancelTimer} && !defined $data->{GetTimer};

    my $room = getRoomName($hash, $data);

    my ($calc_secs , $tomorrow, $seconds);
    ($calc_secs , $tomorrow, $seconds) = _getSecondsfromData($data) if !defined $data->{CancelTimer} && !defined $data->{GetTimer};

    my $siteIds = ReadingsVal( $name, 'siteIds',0);
    fetchSiteIds($hash) if !$siteIds;

    my $timerRoom = $siteId;

    my $responseEnd = getResponse( $hash, 'timerEnd', 1);

    if ($siteIds =~ m{\b$room\b}ix) {
        $timerRoom = $room if $siteIds =~ m{\b$room\b}ix;
        $responseEnd = getResponse( $hash, 'timerEnd', 0);
    }

    my $roomReading = "timer_".makeReadingName($room);
    my $label = $data->{Label} // q{};
    $roomReading .= "_" . makeReadingName($label) if $label ne ''; 

    my $response;
    if (defined $data->{CancelTimer}) {
        if ( !defined $hash->{testline} ) {
            CommandDelete($hash, $roomReading);
            readingsDelete($hash, $roomReading);
            Log3($name, 5, "deleted timer: $roomReading");
        }
        $response = getResponse($hash, 'timerCancellation');
        $response =~ s{(\$\w+)}{$1}eegx;
        respond( $hash, $data, $response );
        return $name;
    }

    if (defined $data->{GetTimer}) {
        $calc_secs = InternalVal($roomReading, 'TRIGGERTIME', undef) // return respond( $hash, $data, getResponse( $hash, 'timerSet', 6 ) );
    }

    if ( $calc_secs && $timerRoom ) {
        if ( !defined $data->{GetTimer} && !defined $hash->{testline}) {
            my $diff = $seconds // 0;
            my $attime = strftime( '%H', gmtime $diff );
            $attime += 24 if $tomorrow;
            $attime .= strftime( ':%M:%S', gmtime $diff );
            my $readingTime = strftime( '%H:%M:%S', localtime (time + $seconds));

            $responseEnd =~ s{(\$\w+)}{$1}eegx;

            my $soundoption = $hash->{helper}{tweaks}{timerSounds}->{$label} // $hash->{helper}{tweaks}{timerSounds}->{default};

            my $addtrigger = qq{; trigger $name timerEnd $siteId $room};
            $addtrigger   .=    " $label" if defined $label;

            if ( !defined $soundoption ) {
                CommandDefMod($hash, "-temporary $roomReading at +$attime set $name speak siteId=\"$timerRoom\" text=\"$responseEnd\";deletereading $name ${roomReading}$addtrigger");
            } else {
                $soundoption =~ m{((?<repeats>[0-9]*)[:]){0,1}((?<duration>[0-9.]*)[:]){0,1}(?<file>(.+))}x;   ##no critic qw(Capture)
                my $file = $+{file} // Log3($hash->{NAME}, 2, "no WAV file for $label provided, check attribute rhasspyTweaks (item timerSounds)!") && return respond( $hash, $data, getResponse( $hash, 'DefaultError' ) );
                my $repeats = $+{repeats} // 5;
                my $duration = $+{duration} // 15;
                CommandDefMod($hash, "-temporary $roomReading at +$attime set $name play siteId=\"$timerRoom\" path=\"$file\" repeats=$repeats wait=$duration id=${roomReading}$addtrigger");
            }

            readingsSingleUpdate($hash, $roomReading, $readingTime, 1);

            Log3($name, 5, "Created timer: $roomReading at $readingTime");
        }

        my ($range, $minutes, $hours, $minutetext);
        my @timerlimits = $hash->{helper}->{tweaks}->{timerLimits} // (91, 9*MINUTESECONDS, HOURSECONDS, 1.5*HOURSECONDS, HOURSECONDS );
        my @time = localtime($calc_secs);
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
        $response = getResponse( $hash, 'timerSet', $range);
        $response =~ s{(\$\w+)}{$1}eegx;
    }

    $response //= getResponse($hash, 'DefaultError');

    respond( $hash, $data, $response );
    return $name;
}

sub handleIntentGetTimer {
    my $hash = shift;
    my $data = shift // return;
    my $siteId = $data->{siteId} // return;
    $data->{GetTimer} = 'redirected from intent GetTimer';
    return handleIntentTimer($hash, $data);
}

sub handleIntentSetTimer {
    my $hash = shift;
    my $data = shift // return;
    my $siteId = $data->{siteId} // return;
    $data->{'.remark'} = 'redirected from intent SetTimer';
    return handleIntentTimer($hash, $data);
}



sub handleIntentNotRecognized {
    my $hash = shift // return;
    my $data = shift // return;

    Log3( $hash, 5, "[$hash->{NAME}] handleIntentNotRecognized called, input is $data->{input}" );
    my $identity = qq($data->{sessionId});
    my $siteId = $hash->{siteId};
    my $msgdev = (split m{_${siteId}_}x, $identity,3)[0];

    if ($msgdev && $msgdev ne $identity) {
        $data->{text} = getResponse( $hash, 'NoIntentRecognized' );
        return handleTtsMsgDialog($hash,$data);
    }

    #return $hash->{NAME} if !$hash->{experimental};

    my $data_old = $hash->{helper}{'.delayed'}->{$identity};

    if ( !defined $data_old ) {
        return handleCustomIntent($hash, 'intentNotRecognized', $data) if defined $hash->{helper}{custom} && defined $hash->{helper}{custom}{intentNotRecognized};
        my $entry = qq([$data->{siteId}] $data->{input});
        readingsSingleUpdate($hash, 'intentNotRecognized', $entry, 1);
        $data->{requestType} = 'text';
        return respond( $hash, $data, getResponse( $hash, 'NoIntentRecognized' ));
    }
    return; #Beta-User: End of recent changes...

=pod
    return if !defined $data->{input} || length($data->{input}) < 12; #Beta-User: silence chuncks or single words, might later be configurable
    $hash->{helper}{'.delayed'}->{$identity}->{intentNotRecognized} = $data->{input};
    Log3( $hash->{NAME}, 5, "data_old is: " . toJSON( $hash->{helper}{'.delayed'}->{$identity} ) );
    my $response = getResponse($hash, 'DefaultChangeIntentRequestRawInput');
    my $rawInput = $data->{input};
    $response =~ s{(\$\w+)}{$1}eegx;
    $data_old->{customData} = 'intentNotRecognized';

    return setDialogTimeout( $hash, $data_old, undef, $response );
=cut
}

sub handleIntentCancelAction {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentCancelAction called');

    #my $toDisable = defined $data->{'.ENABLED'} ? $data->{'.ENABLED'} : [qw(ConfirmAction CancelAction)]; #dialog

    my $identity = qq($data->{sessionId});
    my $data_old = $hash->{helper}{'.delayed'}->{$identity};
    if ( !defined $data_old ) {
        respond( $hash, $data, getResponse( $hash, 'SilentCancelConfirmation' ), undef, 0 );
        return configure_DialogManager( $hash, $data->{siteId}, undef, undef, 1 ); #global intent filter seems to be not working!
    }

    deleteSingleRegIntTimer($identity, $hash);
    delete $hash->{helper}{'.delayed'}->{$identity};
    respond( $hash, $data, getResponse( $hash, 'DefaultCancelConfirmation' ), undef, 0 );

    return $hash->{NAME};
}


sub handleIntentConfirmAction {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentConfirmAction called');
    my $mode = $data->{Mode};

    #cancellation case
    return handleIntentCancelAction($hash, $data) if !$mode || $mode ne 'OK' && $mode ne 'Back' && $mode ne 'Next';

    #confirmed case
    my $identity = qq($data->{sessionId});

    deleteSingleRegIntTimer($identity, $hash);
    my $data_old = $hash->{helper}{'.delayed'}->{$identity};

    if ( !defined $data_old ) {
        respond( $hash, $data, getResponse( $hash, 'DefaultConfirmationNoOutstanding' ) );
        return configure_DialogManager( $hash, $data->{siteId}, undef, undef, 1 ); #global intent filter seems to be not working!;
    };

    #continued session after intentNotRecognized
    if ( defined $data_old->{intentNotRecognized} 
         && defined $mode
         && (   $mode eq 'OK' 
             || $mode eq 'Back' 
             || $mode eq 'Next' ) ) {
        Log3($hash->{NAME}, 5, "ConfirmAction in $data->{Mode} after intentNotRecognized");
        if ($mode eq 'Back') {
            delete $hash->{helper}{'.delayed'}->{$identity}->{intentNotRecognized};
            return respond( $hash, $data, {text => getResponse( $hash,'DefaultConfirmationBack')} );
        }

        if ( $mode eq 'Next' 
             || $mode eq 'OK' && $data->{intent} =~ m{Choice}gxmsi ) {
            #new nlu request with stored rawInput
            my $topic = q{hermes/nlu/query};
            my $sendData;
            for my $key (qw(sessionId siteId customData lang)) {
                $sendData->{$key} = $data->{$key} if defined $data->{$key} && $data->{$key} ne 'null';
            }
            $sendData->{input} = $data_old->{intentNotRecognized}; #input: string - text to recognize intent from (required)
            $sendData->{intentFilter} = 'null'; #intentFilter: [string]? = null - valid intent names (null means all) - back to global FHEM defaults?
            #id: string? = null - unique id for request (copied to response messages)
            #siteId: string = "default" - Hermes site ID
            #sessionId: string? = null - current session ID
            #asrConfidence: float? = null
            my $json = _toCleanJSON($sendData);
            delete $hash->{helper}{'.delayed'}->{$identity};
            IOWrite($hash, 'publish', qq{$topic $json});
            return respond( $hash, $data, {text => getResponse( $hash,'DefaultConfirmation')} );
        }
        #return;
    };
    return handleIntentCancelAction($hash, $data) if $mode ne 'OK'; #modes 'Back' or 'Next' in non-dialogical context

    $data_old->{siteId} = $data->{siteId};
    $data_old->{sessionId} = $data->{sessionId};
    $data_old->{requestType} = $data->{requestType};
    $data_old->{Confirmation} = 1;

    my $intent = $data_old->{intent};
    delete $hash->{helper}{'.delayed'}{$identity};
    my $device = $hash->{NAME};

    # Passenden Intent-Handler aufrufen
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data_old);
    }

    return $device;
}

sub handleIntentChoice {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, 'handleIntentChoice called');

    my $identity = qq($data->{sessionId});
    my $data_old = $hash->{helper}{'.delayed'}->{$identity};
    delete $hash->{helper}{'.delayed'}{$identity};
    deleteSingleRegIntTimer($identity, $hash);

    return respond( $hash, $data, getResponse( $hash, 'DefaultChoiceNoOutstanding' ) ) if !defined $data_old;

    for ( qw( siteId sessionId requestType Room Device Scene ) ) {
        $data_old->{$_} = $data->{$_} if defined $data->{$_};
    }

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

    Log3($hash->{NAME}, 2, 'handleIntentChoiceRoom called, better use generic "Choice" intent now!');

    return handleIntentChoice($hash, $data);
}

sub handleIntentChoiceDevice {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 2, 'handleIntentChoiceDevice called, better use generic "Choice" intent now!');

    return handleIntentChoice($hash, $data);
}


sub handleIntentReSpeak {
    my $hash = shift // return;
    my $data = shift // return;
    my $name = $hash->{NAME};

    my $response = ReadingsVal($name,'voiceResponse',getResponse( $hash, 'reSpeak_failed' ));

    Log3($hash->{NAME}, 5, 'handleIntentReSpeak called');

    respond( $hash, $data, $response );

    return $name;
}

sub setPlayWav {
    my $hash = shift //return;
    my $cmd = shift;

    Log3($hash->{NAME}, 5, 'action playWav called');

    return 'playWav needs siteId and path to file as parameters!' if !defined $cmd->{siteId} || !defined $cmd->{path};

    my $siteId   = _getSiteIdbyRoom($hash, $cmd->{siteId});
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
    my $wait = $cmd->{wait} // 15;
    my $id   = $cmd->{id};

    $repeats--;
    my $attime = strftime( '%H:%M:%S', gmtime $wait );
    return InternalTimer(time, sub (){CommandDefMod($hash, "-temporary $id at +$attime set $name play siteId=\"$siteId\" path=\"$filename\" repeats=$repeats wait=$wait id=$id")}, $hash ) if $repeats;
    #return InternalTimer(time, sub (){CommandDefMod($hash, "-temporary $id at +$attime set $name play siteId=\"$siteId\" path=\"$filename\" repeats=$repeats wait=$wait")}, $hash ) if !$id; #Beta-User: nonsense w/o $id?!?
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
            my $nn = defined $1 ? $1 : 1;
            $val = sprintf("%.${nn}f",$val) if $s =~ m{\A:r(\d)?}x;
        }
        return $val;
    };

    $to_analyze =~s{(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])}{$readingsVal->($1,$2,$3,$4,$5)}egx;
    return $to_analyze;
}

sub _getSecondsfromData {
    my $data = shift // return;
    my $hour = 0;
    my $calc_secs = time;
    my $now = $calc_secs;
    my @time = localtime($now);
    if ( defined $data->{Hourabs} ) {
        $hour  = $data->{Hourabs};
        $calc_secs = $calc_secs - ($time[2] * HOURSECONDS) - ($time[1] * MINUTESECONDS) - $time[0]; #last midnight
    }
    elsif ($data->{Hour}) {
        $hour = $data->{Hour};
    }
    $calc_secs += HOURSECONDS * $hour;
    $calc_secs += MINUTESECONDS * $data->{Min} if $data->{Min};
    $calc_secs += $data->{Sec} if $data->{Sec};

    my $tomorrow = 0;
    if ( $calc_secs < $now ) {
        $tomorrow = 1;
        $calc_secs += +DAYSECONDS if $calc_secs < $now;
    }
    my $secsfromnow= $calc_secs - $now;

    return ($calc_secs , $tomorrow, $secsfromnow);
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
    for (@cleaned) {
        $_ =~ s{\A\s+}{}gmxsu;
    };

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

sub _toCleanJSON {
    my $data = shift // return;
    
    return $data if ref $data ne 'HASH';
    my $json = toJSON($data);
    
    $json =~ s{(":"(true|false|null)")}{": $2}gxms;
    #$json =~ s{(":"null")}{": null}gms;
    $json =~ s{":"}{": "}gxms;
    $json =~ s{("enable": (?:false|true)),("intentId": "[^"]+")}{$2,$1}gms;
    return $json;
}

sub _round { int( $_[0] + ( $_[0] < 0 ? -.5 : .5 ) ); } ##no critic qw(return unpack)

sub _toregex {
    my $toclean = shift // return;
    trim($toclean); 
    $toclean =~ s{ }{\.}g;
    return $toclean;
}

sub _shuffle_answer {
    my $txts = shift // return;
    my @arr = split m{\|}x, $txts;
    return $arr[ rand @arr ];
}

sub _array2andString {
    my $hash = shift // return;
    my $arr  = shift // return;

    return $arr if ref $arr ne 'ARRAY';

    my $and = $hash->{helper}{lng}->{words}->{and} // 'and';

    my @all = @{$arr};
    my $fin = pop @all;
    while (@all && !$fin) {
        $fin = pop @all;
    }
    return $fin if !@all;
    my $text = join q{, }, @all;
    $text .=  " $and $fin";
    return $text;
}

1;

__END__

=pod

=begin ToDo

# More than one device => nwe request path required (testing started)

# "not recognized"
Inform User => respond!
Logging?
Logging also for regognized, but not sufficient confidence level?


# Rückmeldung zu den AMAD.*-Schnittstellen 
Dialoge/Rückfragen, wann Input aufmachen (erl.?)

# auto-training
sieht funktional aus, bisher keine Beschwerden...

# mehr wie ein Device/Group/Room?
(Tests laufen, sieht prinzipiell ok aus).

# Continous mode? (Wackelig, mehr oder weniger ungetestet...)

#Who am I / Who are you?
Personenbezogene Kommunikation? möglich, erwünscht, typische Anwendungsszenarien...?

=end ToDo

=encoding utf8
=item device
=item summary Control FHEM with Rhasspy voice assistant
=item summary_DE Steuerung von FHEM mittels Rhasspy Sprach-Assistent
=begin html

<a id="RHASSPY"></a>
<h3>RHASSPY</h3>
<p>This module receives, processes and executes voice commands coming from <a href="https://rhasspy.readthedocs.io/en/latest/">Rhasspy voice assistent</a>.</p>

<p><b>General Remarks:</b><br>
<ul>
<li>
<a id="RHASSPY-dialoguemanagement"></a>For dialogues, RHASSPY relies on the mechanisms as described in <a href="https://rhasspy.readthedocs.io/en/latest/reference/#dialogue-manager">Rhasspy Dialogue Manager documentation</a>.<br>
So don't expect these parts to work if you use other options than Rhasspy's own dialogue management.</li>
<li>
<a id="RHASSPY-additional-files"></a>You may need or want some additional materials to get the best out of RHASSPY in FHEM. So have a look at the additional files and examples provided in <a href="
https://svn.fhem.de/trac/browser/trunk/fhem/contrib/RHASSPY">svn contrib</a>.<br>See especially attributes <a href="#RHASSPY-attr-languageFile">languageFile</a> and <a href="#RHASSPY-attr-rhasspyIntents">rhasspyIntents</a> for further reference.</li>
</ul>

<a id="RHASSPY-define"></a>
<h4>Define</h4>
<p><code>define &lt;name&gt; RHASSPY &lt;baseUrl&gt; &lt;devspec&gt; &lt;defaultRoom&gt; &lt;language&gt; &lt;fhemId&gt; &lt;prefix&gt; &lt;useGenericAttrs&gt; &lt;handleHotword&gt; &lt;Babble&gt; &lt;encoding&gt;</code></p>
<p><b>All parameters in define are optional, most will not be needed (!)</b>, but keep in mind: changing them later might lead to confusing results for some of them! Especially when starting with RHASSPY, do not set any other than the first three (or four if your language is neither english nor german) of these at all!</p>
<p><b>Remark:</b><br><a id="RHASSPY-parseParams"></a>
RHASSPY uses <a href="https://wiki.fhem.de/wiki/DevelopmentModuleAPI#parseParams"><b>parseParams</b></a> at quite a lot places, not only in define, but also to parse attribute values.<br>
So all parameters in define should be provided in the <i>key=value</i> form. In other places you may have to start e.g. a single line in an attribute with <code>option:key="value xy shall be z"</code> or <code>identifier:yourCode={fhem("set device off")} anotherOption=blabla</code> form.
</p>
<p><b>Parameters:</b><br>
<ul>
  <li><b>baseUrl</b>: http-address of the Rhasspy service web-interface. Optional, but needed as soon as default (<code>baseUrl=http://127.0.0.1:12101</code>) is not appropriate.<br>Make sure, this is set to correct values (ip and port) if Rhasspy is not running on the same machine or not uses default port!</li>
  <li><b>devspec</b>: All the devices you want to control by Rhasspy <b>must meet devspec</b>. If <i>genericDeviceType</i> support is enabled, it defaults to <code>genericDeviceType=.+</code>, otherwise the former default  <code>devspec=room=Rhasspy</code> will be used. See <a href="#devspec"> as a reference</a>, how to e.g. use a comma-separated list of devices or combinations like <code>devspec=room=livingroom,room=bathroom,bedroomlamp</code>.</li>
  <li><b>defaultRoom</b>: Default room name. Used to speak commands without a room name (e.g. &quot;turn lights on&quot; to turn on the lights in the &quot;default room&quot;). Optional, but also recommended. Default is <code>defaultRoom=default</code>.</li>
  <li><b>language</b>: Makes part of the topic tree, RHASSPY is listening to. Should (but needs not to) point to the language voice commands shall be spoken with. Default is derived from global, which defaults to <code>language=en</code>. Preferably language should be set appropriate in global, if possible.</li>
  <li><b>fhemId</b>: May be used to distinguishe between different instances of RHASSPY on the MQTT side. Also makes part of the topic tree the corresponding RHASSPY is listening to.<br>
  Might be usefull, if you have several instances of FHEM running, and may - in later versions - be a criteria to distinguish between different users (e.g. to only allow a subset of commands and/or rooms to be addressed). Not recommended to be set if just one RHASSPY device is defined.</li>
  <li><b>prefix</b>: May be used to distinguishe between different instances of RHASSPY on the FHEM-internal side.<br>
  Might be usefull, if you have several instances of RHASSPY in one FHEM running and want e.g. to use different identifier for groups and rooms (e.g. a different language). Not recommended to be set if just one RHASSPY device is defined.</li>
  <a id="RHASSPY-genericDeviceType"></a>
  <li><b>useGenericAttrs</b>: Formerly, RHASSPY only used it's own attributes (see list below) to identifiy options for the subordinated devices you want to control. Today, it is capable to deal with a couple of commonly used <code>genericDeviceType</code> (<i>switch</i>, <i>light</i>, <i>thermostat</i>, <i>thermometer</i>, <i>blind</i>, <i>media</i>, <i>scene</i> and <i>info</i>), so it will add <code>genericDeviceType</code> to the global attribute list and activate RHASSPY's feature to estimate appropriate settings - similar to rhasspyMapping. <code>useGenericAttrs=0</code> will deactivate this. (do not set this unless you know what you are doing!). Notes:
    <ul>
      <li>As some devices may not directly provide all their setter infos at startup time, RHASSPY will do a second automatic devicemap update 2 minutes after each FHEM start. In the meantime not all commands may work.</li>
      <li><code>homebridgeMapping</code> atm. is not used as source for appropriate mappings in RHASSPY.</li>
    </ul>
  </li>
  <li><b>handleHotword</b>: Trigger Reading <i>hotword</i> in case of a hotword is detected. See attribute <a href="#RHASSPY-attr-rhasspyHotwords">rhasspyHotwords</a> for further reference.</li>
  <li><b>Babble</b>: <a href="#RHASSPY-experimental"><b>experimental!</b></a> Points to a <a href="#Babble ">Babble</a> device. Atm. only used in case if text input from an <a href="#AMADCommBridge">AMADCommBridge</a> is processed, see <a href="#RHASSPY-attr-rhasspySpeechDialog">rhasspySpeechDialog</a> for details.</li>
  <li><b>encoding</b>: <b>most likely deprecated!</b> May be helpfull in case you experience problems in conversion between RHASSPY (module) and Rhasspy (service). Example: <code>encoding=cp-1252</code>. Do not set this unless you experience encoding problems!</li>
  <li><b>sessionTimeout</b> <a href="#RHASSPY-experimental"><b>experimental!</b></a> timout limit in seconds. By default, RHASSPY will close a sessions immediately once a command could be executed. Setting a timeout will keep session open until timeout expires. NOTE: Setting this key may result in confusing behaviour. Atm not recommended for regular useage, <b>testing only!</b> May require some non-default settings on the Rhasspy side to prevent endless self triggering.</li>
  <li><b>autoTraining</b>: <a href="#RHASSPY-experimental"><b>experimental!</b></a> deactivated by setting the timeout (in seconds) to "0", default is "60". If not set to "0", RHASSPY will try to catch all actions wrt. to changes in attributes that may contain any content relevant for Rhasspy's training. In case if, training will be initiated after timeout hast passed since last action; see also <a href="#RHASSPY-set-update">update devicemap</a> command.</li>
</ul>
<p>RHASSPY needs a <a href="#MQTT2_CLIENT">MQTT2_CLIENT</a> device connected to the same MQTT-Server as the voice assistant (Rhasspy) service.</p>
<p><b>Examples for defining an MQTT2_CLIENT device and the Rhasspy device in FHEM:</b>
<ul>
<li><b>Minimalistic version</b> - Rhasspy running on the same machine using it's internal MQTT server, MQTT2_CLIENT is only used by RHASSPY, language setting from <i>global</i> is used:
</p>
<p><code>defmod rhasspyMQTT2 MQTT2_CLIENT localhost:12183<br>
attr rhasspyMQTT2 clientOrder RHASSPY<br>
attr rhasspyMQTT2 subscriptions setByTheProgram</code></p>
<p><code>define Rhasspy RHASSPY defaultRoom=Livingroom</code></p>
</li>
<li><b>Extended version</b> - Rhasspy running on remote machine using an external MQTT server on a third machine with non-default port, MQTT2_CLIENT is also used by MQTT_GENERIC_BRIDGE and MQTT2_DEVICE, hotword events shall be generated:
</p>
<p><code>defmod rhasspyMQTT2 MQTT2_CLIENT 192.168.1.122:1884<br>
attr rhasspyMQTT2 clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE<br>
attr rhasspyMQTT2 subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded hermes/nlu/intentNotRecognized hermes/hotword/+/detected &lt;additional subscriptions for other MQTT-Modules&gt;
<p>define Rhasspy RHASSPY baseUrl=http://192.168.1.210:12101 defaultRoom="Büro Lisa" language=de devspec=genericDeviceType=.+,device_a1,device_xy handleHotword=1</code></p>
</li>
</ul>
<p><b>Additionals remarks on MQTT2-IOs:</b></p>
<p>Using a separate MQTT server (and not the internal MQTT2_SERVER) is highly recommended, as the Rhasspy scripts also use the MQTT protocol for internal (sound!) data transfers. Best way is to either use MQTT2_CLIENT (see above) or bridge only the relevant topics from mosquitto to MQTT2_SERVER (see e.g. <a href="http://www.steves-internet-guide.com/mosquitto-bridge-configuration/">http://www.steves-internet-guide.com/mosquitto-bridge-configuration</a> for the principles). When using MQTT2_CLIENT, it's necessary to set <code>clientOrder</code> to include RHASSPY (as most likely it's the only module listening to the CLIENT it could be just set to <code>attr &lt;m2client&gt; clientOrder RHASSPY</code>)</p>
<p>Furthermore, you are highly encouraged to restrict subscriptions only to the relevant topics:</p>
<p><code>attr &lt;m2client&gt; subscriptions setByTheProgram</code></p>
<p>In case you are using the MQTT server also for other purposes than Rhasspy, you have to set <code>subscriptions</code> manually to at least include the following topics additionally to the other subscriptions desired for other purposes.</p>
<p><code>hermes/intent/+<br>
hermes/dialogueManager/sessionStarted<br>
hermes/dialogueManager/sessionEnded<br>
hermes/nlu/intentNotRecognized<br>
hermes/hotword/+/detected</code></p>

<p><b>Important</b>: After defining the RHASSPY module, you are supposed to manually set the attribute <i>IODev</i> to force a non-dynamic IO assignement. Use e.g. <code>attr &lt;deviceName&gt; IODev &lt;m2client&gt;</code>.</p>

<p><a id="RHASSPY-list"></a><b>Note:</b> RHASSPY consolidates a lot of data from different sources. The <b>final data structure RHASSPY uses at runtime</b> will be shown by the <a href="#list">list command</a>. It's highly recommended to have a close look at this data structure, especially when starting with RHASSPY or in case something doesn't work as expected!<br> 
After changing something relevant within FHEM for either the data structure in</p>
<ul>
  <li><b>RHASSPY</b> (this form is used when reffering to module or the FHEM device) or for </li>
  <li><b>Rhasspy</b> (this form is used when reffering to the remote service), </li>
</ul>
<p>you have to make sure these changes are also updated in RHASSPYs internal data structure and (often, but not always) to Rhasspy. See the different versions provided by the <a href="#RHASSPY-set-update">update command</a>.</p>

<a id="RHASSPY-set"></a>
<h4>Set</h4>
<ul>
  <li>
    <a id="RHASSPY-set-update"></a><b>update</b>
    <p>Various options to update settings and data structures used by RHASSPY and/or Rhasspy. Choose between one of the following:</p>
    <ul>
      <li><b>devicemap</b><br>
      When having finished the configuration work to RHASSPY and the subordinated devices, issuing a devicemap-update is required. You may do that manually in case you have deactivated the "autoTraining" feature or do not want to wait untill timeout is reached. Issueing that command will get the RHASSPY data structure updated, inform Rhasspy on changes that may have occured (update slots) and initiate a training on updated slot values etc., see <a href="#RHASSPY-list">remarks on data structure above</a>.
      </li>
      <li><b>devicemap_only</b><br>
      This may be helpfull to make an intermediate check, whether attribute changes have found their way to the data structure. This will neither update slots nor (immediately) initiate any training towards Rhasspy.
      </li>
      <li><b>slots</b><br>
      This may be helpfull after checks on the FHEM side to immediately send all data to Rhasspy and initiate training.
      </li>
      <li><b>slots_no_training</b><br>
      This may be helpfull to make checks, whether all data is sent to Rhasspy. This will not initiate any training.
      </li>
      <li><b>language</b><br>
      Reinitialization of language file.<br>
      Be sure to execute this command after changing something within in the language configuration file!<br>
      </li>
      <li><b>intent_filter</b><br>
      Reset intent filter used by Rhasspy dialogue manager. See <a href="#RHASSPY-intentFilter">intentFilter</a> in <i>rhasspyTweaks</i> attribute for details.<br>
      </li>
      <li><b>all</b><br>
      Surprise: means language file and full update to RHASSPY and Rhasspy including training and intent filter.
      </li>
    </ul>
    <p>Example: <code>set &lt;rhasspyDevice&gt; update language</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-play"></a><b>play &lt;siteId and path+filename&gt;</b>
    <p>Send WAV file to Rhasspy.<br>
    <i>siteId</i> and <i>path and filename</i> are required!<br>
    You may optionally add a number of repeats and a wait time in seconds between repeats. <i>wait</i> defaults to 15, if only <i>repeats</i> is given.</p>
    <p>Examples:<br>
      <code>set &lt;rhasspyDevice&gt; play siteId="default" path="/opt/fhem/test.wav"</code><br>
      <code>set &lt;rhasspyDevice&gt; play siteId="default" path="./test.wav" repeats=3 wait=20</code>
    </p>
  </li>

  <li>
    <a id="RHASSPY-set-speak"></a><b>speak &lt;siteId and text&gt;</b>
    <p>Voice output over TTS.<br>
    Both arguments (siteId and text) are required!</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; speak siteId="default" text="This is a test"</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-textCommand"></a><b>textCommand &lt;text to analyze&gt;</b>
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
    <a id="RHASSPY-set-volume"></a><b>volume &lt;float value&gt;</b>
    <p>Sets volume of given siteId between 0 and 1 (float)<br>
    Both arguments (siteId and volume) are required!</p>
    <p>Example:<br>
    <code>set &lt;rhasspyDevice&gt; siteId="default" volume="0.5"</code></p>
  </li>

  <li>
    <a id="RHASSPY-set-customSlot"></a><b>customSlot &lt;parameters&gt;</b>
    <p>Creates a new - or overwrites an existing slot - in Rhasspy<br>
    Provide slotname, slotdata and (optional) info, if existing data shall be overwritten and training shall be initialized immediately afterwards.<br>
    First two arguments are required, third and fourth are optional.<br>
    <i>overwrite</i> defaults to <i>true</i>, setting any other value than <i>true</i> will keep existing Rhasspy slot data.</p>
    <p>Examples:<br>
    <code>set &lt;rhasspyDevice&gt; customSlot mySlot a,b,c overwrite training </code><br>
    <code>set &lt;rhasspyDevice&gt; customSlot slotname=mySlot slotdata=a,b,c overwrite=false</code></p>
  </li>
  <li>
    <a id="RHASSPY-set-activateVoiceInput"></a><b>activateVoiceInput</b>
    <p>Activate a satellite for voice input. <i>siteId</i>, <i>hotword</i> and <i>modelId</i> may be provided (either in order of appearance or as named arguments), otherwise some defaults will be used.</p>
  </li>
</ul>

<a id="RHASSPY-get"></a>
<h4>Get</h4>
<ul>
  <li>
    <a id="RHASSPY-get-export_mapping"></a><b>export_mapping &lt;devicename&gt;</b>
    <p>Exports a "classical" rhasspyMapping attribute value for the provided device. You may find this usefull to adopt that further to your individual needs. May not completely work in all cases, especially wrt. to SetScene and HUEBridge formated scenes.</p>
  </li>
  <li>
    <a id="RHASSPY-get-test_file"></a><b>test_file &lt;path and filename&gt;</b>
    <p>Checks the provided text file. Content will be sent to Rhasspy NLU for recognition (line by line), result will be written to the file '&lt;input without ending.txt&gt;_result.txt'. <i><b>stop</i></b> as filename will stop test mode if sth. goes wrong. No commands will be executed towards FHEM devices while test mode is active.</p>
    <p>Note: To get test results, RHASSPY's siteId has to be configured for intent recognition in Rhasspy as well.</p>
  </li>
  <li>
    <a id="RHASSPY-get-test_sentence"></a><b>test_sentence &lt;sentence to be analyzed&gt;</b>
    <p>Checks the provided sentence for recognition by Rhasspy NLU. No commands to be executed as well.</p>
    <p>Note: wrt. to RHASSPY's siteId for NLU see remark get test_file.</p>
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
    The file itself must contain a JSON-encoded keyword-value structure (partly with sub-structures) following the given structure for the mentioned english defaults. As a reference, there's one in the <a href="#RHASSPY-additional-files">additionals files</a> available in german (note the comments there!), or just make a dump of the English structure with e.g. (replace RHASSPY by your device's name): <code>{toJSON($defs{RHASSPY}->{helper}{lng})}</code>, edit the result e.g. using https://jsoneditoronline.org and place this in your own languageFile version. There might be some variables to be used - these should also work in your sentences.<br>
    languageFile also allows combining e.g. a default set of german sentences with some few own modifications by using "defaults" subtree for the defaults and "user" subtree for your modified versions. This feature might be helpful in case the base language structure has to be changed in the future.</p>
    <p>Example (placed in the same dir fhem.pl is located):</p>
    <p><code>attr &lt;rhasspyDevice&gt; languageFile ./rhasspy-de.cfg</code></p>
  </li>

  <li>
    <a id="RHASSPY-attr-response"></a><b>response</b>
    <p><b>Note:</b> Using this attribute is no longer recommended, use options provided by the <a href="#RHASSPY-attr-languageFile">languageFile attribute</a> instead.</p>
    <p>Optionally define alternative default answers. Available keywords are <code>DefaultError</code>, <code>NoActiveMediaDevice</code> and <code>DefaultConfirmation</code>.</p>
    <p>Example:</p>
    <p><code>DefaultError=<br>
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
    <p>If a simple text is returned, this will be considered as response, if return value is not defined, the default response will be used.<br>
    For more advanced use of this feature, you may return either a HASH or an ARRAY data structure. If ARRAY is returned:
    <ul><li>First element of the array is interpreted as response and may be plain text (dialog will be ended) or HASH type to continue the session. The latter will keep the dialogue-session open to allow interactive data exchange with <i>Rhasspy</i>. An open dialogue will be closed after some time, (configurable) default is 20 seconds, you may alternatively hand over other numeric values as second element of the array.
    </li>
    <li>Second element might either be a comma-separated list of devices that may have been modified (otherwise, these devices will not cast any events! See also the "d" parameter in <a href="#RHASSPY-attr-rhasspyShortcuts"><i>rhasspyShortcuts</i></a>), or (if first element is HASH type) a nummeric value as timeout.</li> 
    <li>If HASH type data (or $response in ARRAY) is returned to continue a session, make sure to hand over all relevant elements, including especially <i>intentFilter</i> if you want to restrict possible intents. It's recommended to always also activate <i>CancelAction</i> to allow user to actively exit the dialoge.
    </li>
    </ul>
    <br>See also <a href="#RHASSPY-additional-files">additionals files</a> for further examples on this.</p>
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
      <li><b>d</b> => device name(s, comma separated) that shall be handed over to fhem.pl as updated. Needed for triggering further actions and longpoll! Note: When calling Perl functions, the return value of the called function will be used if no explicit device is provided. </li>
      <li><b>r</b> => Response to be send to the caller. If not set, the return value of the called function will be used.<br>
      Response sentence will be parsed to do "set magic"-like replacements, so also a line like <code>i="what's the time for sunrise" r="at [Astro:SunRise] o'clock"</code> is valid.<br>
      You may ask for confirmation as well using the following (optional) shorts:
      <ul>
        <li><b>c</b> => either numeric or text. If numeric: Timeout to wait for automatic cancellation. If text: response to send to ask for confirmation.</li>
        <li><b>ct</b> => numeric value for timeout in seconds, default: 15.</li>
        See <a href="#RHASSPY-confirmation"><i>here</i></a> for more info about confirmations.
      </ul></li>
    </ul>
  </li>
  <br>
  <li>
    <a id="RHASSPY-attr-rhasspyTweaks"></a><b>rhasspyTweaks</b>
    <p>Place for additional settings to influence RHASSPY's global behavior on certain aspects.</p>
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
      <li><b>timeouts</b>
        <p>Atm. keywords <i>confirm</i> and/or <i>default</i> can be used to change the corresponding defaults (15 seconds / 20 seconds) used for dialogue timeouts.</p>
        <p>Example:</p>
        <p><code>timeouts: confirm=25 default=30</code></p>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-confidenceMin"></a>
      <li><b>confidenceMin</b>
        <p>By default, RHASSPY will use a minimum <i>confidence</i> level of <i>0.66</i>, otherwise no command will be executed. You may change this globally (key: default) or more granular for each intent specified.<br>
        Example: <p><code>confidenceMin= default=0.6 SetMute=0.4 SetOnOffGroup=0.8 SetOnOff=0.8</code></p>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-confirmIntents"></a>
      <li><b>confirmIntents</b>
        <p>This key may contain <i>&lt;Intent&gt;=&lt;regex&gt;</i> pairs beeing </p>
        <ul>
        <li><i>Intent</i> one of the intents supporting confirmation feature (all set type intents)  and </li>
        <li><i>regex</i> containing a regular expression matching to either the group name (for group intents) or the device name(s) - using a full match lookup. If intent and regex match, a confirmation will be requested.
        Example: <p><code>confirmIntents=SetOnOffGroup=light|blinds SetOnOff=blind.*</code></p>
        </li>
        </ul>
        <a id="RHASSPY-confirmation"></a>
        <p>To execute any action requiring confirmation, you have to send an <i>Mode:OK</i> value by the <i>ConfirmAction</i> intent. Any other <i>Mode</i> key sent to <i>ConfirmAction</i> intent will be interpretad as cancellation request. For cancellation, you may alternatively use the <i>CancelAction</i> intent. Example:<br>
            <code>[de.fhem:ConfirmAction]<br>
            ( yes, please do it | go on | that's ok | yes, please ){Mode:OK}<br>
            ( don't do it after all ){Mode}<br>
            [de.fhem:CancelAction]<br>
            ( let it be | oh no | cancel | cancellation ){Mode:Cancel}
            </code><br>
        </p>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-confirmIntentResponses"></a>
      <li><b>confirmIntentResponses</b>
        <p>By default, the answer/confirmation request will be some kind of echo to the originally spoken sentence ($rawInput as stated by <i>DefaultConfirmationRequestRawInput</i> key in <i>responses</i>). You may change this for each intent specified using $target, ($rawInput) and $Value als parameters.<br>
        Example: <p><code>confirmIntentResponses=SetOnOffGroup="really switch group $target $Value" SetOnOff="confirm setting $target $Value" </code></p>
        <i>$Value</i> may be translated with defaults from a <i>words</i> key in languageFile, for more options on <i>$Value</i> and/or more specific settings in single devices see also <i>confirmValueMap</i> key in <a href="#RHASSPY-attr-rhasspySpecials">rhasspySpecials</a>.</p>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-ignoreKeywords"></a>
      <li><b>ignoreKeywords</b>
        <p>You may have also some technically motivated settings in the attributes RHASSPY uses to generate slots, e.g. <i>MQTT, alexa, homebridge</i> or <i>googleassistant</i> in <i>room</i> attribute. The key-value pairs will sort the given <i>value</i> out while generating the content for the respective <i>slot</i> for <i>key</i> (atm. only <i>rooms</i> and <i>group</i> are supported). <i>value</i> will be treated as (case-insensitive) regex with need to exact match.<br>
        Example: <p><code>ignoreKeywords=room=MQTT|alexa|homebridge|googleassistant|logics-.*</code>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-gdt2groups"></a>
      <li><b>gdt2groups</b>
        <p>You may want to assign some default groupnames to all devices with the same genericDeviceType without repeating it in all single devices.<br>
        Example: <p><code>gdt2groups= blind=rollläden,rollladen thermostat=heizkörper light=lichter,leuchten</code>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-mappingOverwrite"></a>
      <li><b>mappingOverwrite</b>
        <p>If set, any value set in rhasspyMapping attribute will delete all content detected by automated mapping analysis (default: only overwrite keys set in devices rhasspyMapping attributes.</p>
        <p>Example: <p><code>mappingOverwrite=1</code></p>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-extrarooms"></a>
      <li><b>extrarooms</b>
        <p>You may want to add more rooms to what Rhasspy can recognize as room. Using this key, the comma-separated items will be sent as rooms for preparing the room and mainrooms slots.<br>
        Example: <p><code>extrarooms= barn,music collection,cooking recipies</code><br>
        Note: Only do this in case you really know what you are doing! Additional rooms only may be usefull in case you have some external application knowing what to do with info assinged to these rooms!
      </li>
      <li><b>updateSlots</b>
        <p>Changes aspects on slot generation and updates.</p>
        <p><code>noEmptySlots=1</code></p>
        <p>By default, RHASSPY will generate an additional slot for each of the genericDeviceType it recognizes, regardless, if there's any devices marked to belong to this type. If set to <i>1</i>, no empty slots will be generated.</p>
        <p><code>overwrite_all=false</code></p>
        <p>By default, RHASSPY will overwrite all generated slots. Setting this to <i>false</i> will change this.</p>
      </li>
      <a id="RHASSPY-attr-rhasspyTweaks-intentFilter"></a>
      <li><b>intentFilter</b>
        <p>Atm. Rhasspy will activate all known intents at startup. As some of the intents used by FHEM are only needed in case some dialogue is open, it will deactivate these intents (atm: <i>ConfirmAction, CancelAction, ChoiceRoom</i> and <i>ChoiceDevice</i>(including the additional parts derived from language and fhemId))) at startup or when no active filtering is detected. You may disable additional intents by just adding their names in <i>intentFilter</i> line or using an explicit state assignment in the form <i>intentname=true</i> (Note: activating the 4 mentionned intents is not possible!). For details on how <i>configure</i> works see <a href="https://rhasspy.readthedocs.io/en/latest/reference/#dialogue-manager">Rhasspy documentation</a>.</p>
      </li>
    </ul>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyHotwords"></a><b>rhasspyHotwords</b>
    <p>Define custom reactions as soon as a specific hotword is detected (or with "global": a toggle command is detected). This does not require any specific configuration on any other FHEM device.<br>
    One hotword per line, syntax is either a simple and an extended version. The "hotword" <i>global</i> will be treated specially and can be used to also execute custom commands when a <i>toggle</i> event is indicated.</p>
    Examples:<br>
    <p><code>bumblebee_linux = set amplifier2 mute on<br>
        porcupine_linux = livingroom="set amplifier mute on" default={Log3($DEVICE,3,"device $DEVICE - room $ROOM - value $VALUE")}<br>
        global = { rhasspyHotword($DEVICE,$VALUE,$DATA,$MODE) }</code></p>
    <p>First example will execute the command for all incoming messages for the respective hotword, second will decide based on the given <i>siteId</i> keyword; $DEVICE is evaluated to RHASSPY name, $ROOM to siteId and $VALUE to the hotword. Additionally, in "global key", $DATA will contain entire JSON-$data (as parsed internally, encoded in JSON) and $MODE will be one of <i>on</i>, <i>off</i> or <i>detected</i><br>. You may assign different commands to <i>on</i>, <i>off</i> and <i>detected</i>.
    <i>default</i> is optional. If set, this action will be executed for all <i>siteIds</i> without match to other keywords.<br>
    Additionally, if either <i>rhasspyHotwords</i> is set or key <i>handleHotword</i> in <a href="#RHASSPY-define">DEF</a> is activated, the reading <i>hotword</i> will be filled with <i>hotword</i> plus <i>siteId</i> to also allow arbitrary event handling.<br>NOTE: As all hotword messages are sent to a common topic structure, you may need additional measures to distinguish between several <i>RHASSPY</i> instances, e.g. by restricting subscriptions and/or using different entries in this attribute.</p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyMsgDialog"></a><b>rhasspyMsgDialog</b>
    <p>If some key in this attribute are set, RHASSPY will react somehow like a <a href="#msgDialog">msgDialog</a> device. This needs some configuration in the central <a href="#msgConfig">msgConfig</a> device first, and additionally for each RHASSPY instance a siteId has to be added to the intent recognition service.</p>
    Keys that may be set in this attribute:
     <ul>
        <li><i>allowed</i> The <a href="#ROOMMATE">ROOMMATE</a> or <a href="#GUEST">GUEST</a> devices allowed to interact with RHASSPY (comma-separated device names). This ist the only <b>mandatory</b> key to be set.</li>
        <li><i>open</i> A keyword or expression used to initiate a dialogue (will be converted to a regex compatible notation)</li>
        <li><i>sessionTimeout</i> timout limit in seconds (<b>recommended</b>). All sessions will be closed automatically when timeout has passed. Timer will be reset with each incoming message .</li>
        <li><i>close</i> keyword used to exit a dialogue (similar to open) before timeout has reached</li>
        <li><i>hello</i> and <i>goodbye</i> are texts to be sent when opening or exiting a dialogue</li>
        <li><i>msgCommand</i> the fhem-command to be used to send messages to the messenger service.</li>
        <li><i>siteId</i> the siteId to be used by this RHASSPY instance to identify it as satellite in the Rhasspy ecosystem</li>
        <li><i>querymark</i> Text pattern that shall be used to distinguish the queries done in intent MsgDialog from others (for the future: will be added to all requests towards Rhasspy intent recognition system automatically; not functional atm.)</li>
        <br>
      </ul>
  </li>
  <p><b>Remarks on rhasspySpeechDialog and Babble:</b><br><a id="RHASSPY-experimental"></a>
    Interaction with Babble and AMAD.*-Devices is not approved to be propperly working yet. Further tests
    may be needed and functionality may be subject to changes!
  </p>
  <li>
    <a id="RHASSPY-attr-rhasspySpeechDialog"></a><b>rhasspySpeechDialog</b>
    <a href="#RHASSPY-experimental"><b>experimental!</b></a> 
    <p>Optionally, you may want not to use the internal speach-to-text engine provided by Rhasspy (for one or several siteId's), but provide  simple text to be forwarded to Rhasspy for intent recognition. Atm. only "AMAD" is supported for this feature. For generic "msg" (and text messenger) support see <a href="#RHASSPY-attr-rhasspyMsgDialog">rhasspyMsgDialog</a> <br>Note: You will have to (de-) activate these parts of the Rhasspy ecosystem for the respective satellites manually!</p>
    Keys that may be set in this attribute:
     <ul>
        <li><i>allowed</i> A list of <a href="#AMADDevice">AMADDevice</a> devices allowed to interact with RHASSPY (comma-separated device names). This ist the only <b>mandatory</b> key to be set.</li>
        <li><i>filterFromBabble</i> 
        By default, all incoming messages from AMADDevice/AMADCommBridge will be forwarded to Rhasspy. For better interaction with <a href="#Babble ">Babble</a> you may opt to ignore all messages not matching the <i>filterFromBabble</i> by their starting words (case-agnostic, will be converted to a regex compatible notation). You additionally have to set a <i>Babble</i> key in <a href="#RHASSPY-define">DEF</a> pointing to the Babble device. All regular messages (start sequence not matching filter) then will be forwarded to Babble using <code>Babble_DoIt()</code> function.</li>
        <li><i>&lt;allowed AMAD-device&gt;</i> A list of key=value pairs to tweak default behaviours:
        <ul>
        <li><i>wakeword</i> If set, a wakeword detected message for this wakeword will lead to an 
         "activateVoiceInput" command towards this AMADDevice</li>
        <li><i>sessionTimeout</i> timeout (in seconds) used if a request (e.g. for confirmation) is open for this AMADDevice (if not set, global default value is used)</li>
        <li> Remark: This may contain additional keys in the future, e.g., to restrict wakeword effect to a specific siteId.</li>
        </ul>
        </li>
      </ul>
      Example:<br>
        <p><code>allowed=AMADDev_A <br>
                 filterFromBabble=tell rhasspy <br>
                 AMADDev_A=wakeword=alexa sessionTimeout=20</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-forceNEXT"></a><b>forceNEXT</b>
    <p>If set to 1, RHASSPY will forward incoming messages also to further MQTT2-IO-client modules like MQTT2_DEVICE, even if the topic matches to one of it's own subscriptions. By default, these messages will not be forwarded for better compability with autocreate feature on MQTT2_DEVICE. See also <a href="#MQTT2_CLIENTclientOrder">clientOrder attribute in MQTT2 IO-type commandrefs</a>; setting this in one instance of RHASSPY might affect others, too.</p>
  </li>
</ul>
<p>&nbsp;</p>
<a id="RHASSPY-attr-subdevice"></a>
<p><b>For the subordinated devices</b>, a list of the possible attributes is automatically extended by several further entries</p>
<p>The names of these attributes all start with the <i>prefix</i> previously defined in RHASSPY - except for <a href="#RHASSPY-genericDeviceType">genericDeviceType</a> (gDT).<br>
These attributes are used to configure the actual mapping to the intents and the content sent by Rhasspy.</p>
<p>Note: As the analyses of the gDT is intented to lead to fast configuration progress, it's highly recommended to use this as a starting point. All other RHASSPY-specific attributes will then be considered as a user command to <b>overwrite</b> the results provided by the automatics initiated by gDT usage.</p>
    
<p>By default, the following attribute names are used: rhasspyName, rhasspyRoom, rhasspyGroup, rhasspyChannels, rhasspyColors, rhasspySpecials.<br>
Each of the keywords found in these attributes will be sent by <a href="#RHASSPY-set-update">update</a> to Rhasspy to create the corresponding slot.</p>

<ul>
  <li>
    <a id="RHASSPY-attr-rhasspyName" data-pattern=".*Name"></a><b>rhasspyName</b>
    <p>Comma-separated "labels" for the device as used when speaking a voice-command. They will be used as keywords by Rhasspy. May contain space or mutated vovels.</p>
    <p>Example:<br>
    <code>attr m2_wz_08_sw rhasspyName kitchen lamp,ceiling lamp,workspace,whatever</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyRoom" data-pattern=".*Room"></a><b>rhasspyRoom</b>
    <p>Comma-separated "labels" for the "rooms" the device is located in. Recommended to be unique.</p>
    <p>Example:<br>
    <code>attr m2_wz_08_sw rhasspyRoom living room</code></p>
    <p>Note: If you provide more than one room, the first will be regarded as <i>mainroom</i>, which has a special role, especially in dialogues.</p>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyGroup" data-pattern=".*Group"></a><b>rhasspyGroup</b>
    <p>Comma-separated "labels" for the "groups" the device is in. Recommended to be unique.</p>
    <p>Example:
    <code>attr m2_wz_08_sw rhasspyGroup lights</code></p>
  </li>
  <li>
    <a id="RHASSPY-attr-Mapping" data-pattern=".*Mapping"></a><b>rhasspyMapping</b>
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
    <a id="RHASSPY-attr-rhasspyChannels" data-pattern=".*Channels"></a><b>rhasspyChannels</b>
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
    <a id="RHASSPY-attr-rhasspyColors" data-pattern=".*Colors"></a><b>rhasspyColors</b>
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
    <a id="RHASSPY-attr-rhasspySpecials" data-pattern=".*Specials"></a><b>rhasspySpecials</b>
    <p>Options to change a bunch of aspects how a single device behaves when addressed by voice commands. You may use several of the following lines.</p>
    <p><i>key:value</i> line by line arguments similar to <a href="#RHASSPY-attr-rhasspyTweaks">rhasspyTweaks</a>.</p>
    <ul>
      <li><b>group</b>
        <p>If set, the device will not be directly addressed, but the mentioned group - typically a FHEM <a href="#structure">structure</a> device or a HUEDevice-type group. This has the advantage of saving RF ressources and/or fits better to already implemented logics.<br>
        Note: all addressed devices will be switched, even if they are not member of the rhasspyGroup. Each group should only be addressed once, but it's recommended to put this info in all devices under RHASSPY control in the same external group logic.<br>
        All of the following options are optional.</p>
        <ul>
          <li><b>async_delay</b><br>
            Float nummeric value, just as async_delay in structure; the delay will be obeyed prior to the next sending command.</li> 
          <li><b>prio</b><br>
            Numeric value, defaults to "0". <i>prio</i> and <i>async_delay</i> will be used to determine the sending order as follows: first devices will be those with lowest prio arg, second sort argument is <i>async_delay</i> with lowest value first.</li>
          <li><b>partOf</b><br>
            Will adress an entire group directly. This group has to exist in FHEM first (could be e.g. a <i>structure</i> or a <i>ZigBee</i>-group) and needs to be switched with the same command than the single device.</li> 
        </ul>
        <p>Example:</p>
        <p><code>attr lamp1 rhasspySpecials group:async_delay=0.3 prio=1 group=lights</code></p>
      </li>
      <li><b>numericValueMap</b>
        <p>Allows mapping of numeric values from the <i>Value</i> key to individual commands. Might e.g. usefull to address special positioning commands for blinds.</p>
        <p>Example:</p>
        <p><code>attr blind1 rhasspySpecials numericValueMap:10='Event Slit' 50='myPosition'</code></p>
         <p>Note: will lead to e.g. <code>set blind1 Event Slit</code> when numeric value 10 is received in {Value} key.</p>
      </li>
      <li><b>venetianBlind</b>
        <p><code>attr blind1 rhasspySpecials venetianBlind:setter=dim device=blind1_slats stopCommand="set blind1_slats dim [blind1_slats:dim]"</code></p>
        <p>Explanation (one of the two arguments is mandatory):
        <ul>
          <li><b>setter</b> is the set command to control slat angle, e.g. <i>positionSlat</i> for CUL_HM or older ZWave type devices</li>
          <li><b>device</b> is needed if the slat command has to be issued towards a different device (applies e.g. to newer ZWave type devices)</li>
          <li><b>CustomCommand</b> arbitrary command defined by the user. Note: no variables will be evaluated. Will be executed if a regular nummeric command is detected.</li>
          <li><b>stopCommand</b> arbitrary command defined by the user. Note: no variables will be evaluated. Will be executed if a stop command is detected.</li>
        </ul>
        <p>If set, the slat target position will be set to the same level than the main device.</p>
      </li>
      <li><b>colorCommandMap</b>
        <p>Allows mapping of values from the <i>Color</i> key to individual commands.</p>
        <p>Example:</p>
        <p><code>attr lamp1 rhasspySpecials colorCommandMap:0='rgb FF0000' 120='rgb 00FF00' 240='rgb 0000FF'</code></p>
      </li>
      <li><b>colorTempMap</b>
        <p>Allows mapping of values from the <i>Colortemp</i> key to individual commands.</p>
        Works similar to colorCommandMap</p>
      </li>
      <li><b>colorForceHue2rgb</b>
        <p>Defaults to "0". If set, a rgb command will be issued, even if the device is capable to handle hue commands.</p>
        <p>Example:</p>
        <p><code>attr lamp1 rhasspySpecials colorForceHue2rgb:1</code></p>
      </li>
      <li><b>priority</b>
        <p>Keywords <i>inRoom</i> and <i>outsideRoom</i> can be used, each followed by comma separated types to give priority in <i>Set</i> or <i>Get</i> intents. This may eleminate requests in case of several possible devices or rooms to deliver requested info type.</p>
        <p>Example:</p>
        <p><code>attr sensor_outside_main rhasspySpecials priority:inRoom=temperature outsideRoom=temperature,humidity,pressure</code></p>
        <p>Note: If there's a suitable "active" device, this will be given an even higher priority in most cases (e.g. "make music louder" may increase the volume on a switched on amplifier device and not go to an MPD device in the same room)</p>
      </li>
      <li><b>confirm</b>
        <p>This is the more granular alternative to <a href="#RHASSPY-attr-rhasspyTweaks-confirmIntents">confirmIntents key in rhasspyTweaks</a> (including <i>confirmIntentResponses</i>). You may provide intent names only or <i>&lt;Intent&gt;=&lt;response&gt;</i> pairs like <code>confirm: SetOnOff="$target shall be switched $Value" SetScene</code>. 
        </p>
      </li>
      <li><b>confirmValueMap</b>
        <p>Provide a device specific translation for $Value, e.g. for a blind type device <i>rhasspySpecials</i> could look like:<br>
        <code>confirm: SetOnOff="really $Value $target"<br>
              confirmValueMap: on=open off=close</code>
        </p>
      </li>
      <li><b>scenes</b>
        <p><code>attr lamp1 rhasspySpecials scenes:scene2="Kino zu zweit" scene3=Musik scene1=none scene4=none</code></p>
        <p>Explanation:
        <p>If set, the value (e.g. "Kino zu zweit") provided will be sent to Rhasspy instead of the <i>tech names</i> (e.g. "scene2", derived from available setters). Value <i>none</i> will delete the scene from the internal list, setting the combination <i>all=none</i> will exclude the entire device from beeing recognized for SetScene, <i>rest=none</i> will only include the labeled scenes. These values finally will be what's expected to be spoken to identificate a specific scene.</p>
      </li>
      <li><b>blacklistIntents</b>
        <p><code>attr weather rhasspySpecials blacklistIntents:MediaControls</code></p>
        <p>Explanation:</p>
        <p>If set, the blacklisted intents will be deleted after automated mapping analysis.</p>
      </li>
    </ul>
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyMsgCommand" data-pattern=".*MsgCommand"></a><b>rhasspyMsgCommand</b>
    <p>Command used by RHASSPY to send messages to text dialogue partners. See also <a href="#RHASSPY-attr-rhasspyMsgDialog">rhasspyMsgDialog</a> attribute.</p>
  </li>
</ul>


<a id="RHASSPY-intents"></a>
<h4>Intents</h4>
<p>The following intents are directly implemented in RHASSPY code and the keywords used by them in sentences.ini are as follows:
<ul>
  <li>Shortcuts</li> (keywords as required by user code)
  <li>SetOnOff</li>
  {Device} and {Value} (on/off) are mandatory, {Room} is optional.<br>
  <a id="RHASSPY-multicommand">Note: As <a href="#RHASSPY-experimental"><b>experimental</b></a> feature, you may hand over additional fields, like {Device1} ("1" here and in the follwoing keys may be any additonal postfix), {Group}/{Group1} and/or {Room1}. Then the intent will be interpreted as SetOnOffGroup intent adressing all the devices matching the {Device}s or {Group}s name(s), as long as they are in (one of) the respective {Room}s.<br>
  The only restriction is: The intented {Value} (or, for other multicommand intents: Color etc.-value) has to be unique.
  <li>SetOnOffGroup</li>
  {Group} and {Value} (on/off) are mandatory, {Room} is optional, <i>global</i> in {Room} will be interpreted as "everywhere".<br>
  <a href="#RHASSPY-multicommand"><b>Experimental multicommand</b></a> feature should work also with this intent, (redirecting to itself and adding devices according to the additional keys).
  <li>SetTimedOnOff</li>Basic keywords see SetOnOff, plus timer info in at least one of the fields {Hour} (for relative additions starting now), {Hourabs} (absolute time of day), {Min} (minutes) and {Sec} (seconds). If {Hourabs} is provided, {Min} and {Sec} will also be interpreted as absolute values.
  <li>SetTimedOnOffGroup</li> (for keywords see SetOnOffGroup)
  <li>GetOnOff</li>(for keywords see SetOnOff)
  <li>SetNumeric</li>
  Dependend on the specific surrounding informations, a combination of {Device}, {Value} (nummeric value), {Change} and/or {Type} are sufficient, {Room} is optional. Additional optional field is {Unit} (value <i>percent</i> will be interprated as request to calculate, others will be ignored). {Change} can be with one of ({Type})
  <ul>
    <li>lightUp, lightDown (brightness)</li>
    <li>volUp, volDown (volume)</li>
    <li>tempUp, tempDown (temperature/desired-temp)</li>
    <li>setUp, setDown (setTarget)</li>
    <li>cmdStop (applies only for blinds)</li>
  </ul>
  allowing to decide on calculation scheme and to guess for the proper device and/or answer.
  <a href="#RHASSPY-multicommand"><b>experimental multicommand</b></a> feature should work also with this intent (switching intent to SetNumericGroup).
  <li>SetNumericGroup</li>
    (as SetNumeric, except for {Group} instead of {Device}).
  <li>GetNumeric</li> (as SetNumeric)
  <li>GetState</li> To querry existing devices, {Device} is mandatory, keys {Room}, {Update}, {Type} and {Reading} (defaults to internal STATE) are optional.
  By omitting {Device}, you may request some options RHASSPY itself provides (may vary dependend on the room). {Type} keys for RHASSPY are <i>generic</i>, <i>control</i>, <i>info</i>, <i>scenes</i> and <i>rooms</i>.
  <li>MediaControls</li>
  {Device} and {Command} are mandatory, {Room} is optional. {Command} may be one of <i>cmdStop</i>, <i>cmdPlay</i>, <i>cmdPause</i>, <i>cmdFwd</i> or <i>cmdBack</i>
  <li>MediaChannels</li> (as configured by the user)
  <li>SetColor</li> 
  {Device} and one Color option are mandatory, {Room} is optional. Color options are {Hue} (0-360), {Colortemp} (0-100), {Saturation} (as understood by your device) or {Rgb} (hex value from 000000 to FFFFFF)
  <a href="#RHASSPY-multicommand"><b>experimental multicommand</b></a> feature should work as well.
  <li>SetColorGroup</li> (as SetColor, except for {Group} instead of {Device}).
  <li>SetScene</li> {Device} and {Scene} (it's recommended to use the $lng.fhemId.Scenes slot to get that generated automatically!), {Room} is optional, {Get} with value <i>scenes</i> may be used to request all possible scenes for a device prior to make a choice.
  <li>GetTime</li>
  <li>GetDate</li>
  <li>Timer</li> Timer info as described in <i>SetTimedOnOff</i> is mandatory, {Room} and/or {Label} are optional to distinguish between different timers. {CancelTimer} key will force RHASSPY to try to remove a running timer (using optional {Room} and/or {Label} key to identify the respective timer), {GetTimer} key will be treated as request if there's a timer running (optionally also identified by {Room} and/or {Label} keys).
  <li>SetTimer</li> (Outdated, use generic "Timer" instead!) Set a timer, required info as mentionned in <i>Timer</i>
  Required tags to set a timer: at least one of {Hour}, {Hourabs}, {Min} or {Sec}. {Label} and {Room} are optional to distinguish between different timers. If {Hourabs} is provided, all timer info will be regarded as absolute time of day info, otherwise everything is calculated using a "from now" logic.
  <li>GetTimer</li> (Outdated, use generic "Timer" instead!) Get timer info as mentionned in <i>Timer</i>, key {GetTimer} is not explicitely required.
  <li>ConfirmAction</li>
  {Mode} with value 'OK'. All other calls will be interpreted as CancelAction intent call.
  <li>CancelAction</li>{Mode} is recommended.
  <li>Choice</li>One or more of {Room}, {Device} or {Scene}
  <li>ChoiceRoom</li> {Room} NOTE: Useage of generic "Choice" intent instead is highly recommended!
  <li>ChoiceDevice</li> {Device} NOTE: Useage of generic "Choice" intent instead is highly recommended!
  <li>ReSpeak</li>
</ul>

<a id="RHASSPY-readings"></a>
<h4>Readings</h4>
<p>There are some readings you may find usefull to tweak some aspects of RHASSPY's logics:
<ul>
  <li>siteId2room_&lt;siteId&gt;</li>
  Typically, RHASSPY derives room info from the name of the siteId. So naming a satellite <i>bedroom</i> will let RHASSPY assign this satellite to the same room, using the group sheme is also supported, e.g. <i>kitchen.front</i> will refer to <i>kitchen</i> as room (if not explicitly given). <br>
  You may overwrite that behaviour by setting values to siteId2room readings: <code>setreading siteId2room_mobile_phone1 kitchen</code> will force RHASSPY to link your satellite <i>phone1 kitchen</i> to kitchen as room.
  <li>room2siteId_&lt;room&gt;</li> Used to identify the satellite to speak messages addressed to a room (same for playing sound files). Should deliver exactly one possible siteId, e.g. &lt;lingingroom.04&gt;
  <li>siteId2doubleSpeak_&lt;siteId&gt;</li>
  RHASSPY will always respond via the satellite where the dialogue was initiated from. In some cases, you may want additional output to other satellites - e.g. if they don't have (always on) sound output options. Setting this type of reading will lead to (additional!) responses to the given second satellite; naming scheme is the same as for site2room.
  <li>sessionTimeout_&lt;siteId&gt;</li>
  RHASSPY will by default automatically close every dialogue after an executable commandset is detected. By setting this type of reading, you may keep open the dialoge to wait for the next command to be spoken on a "by siteId" base; naming scheme is similar as for site2room. Intent <i>CancelAction</i> will close any session immedately.
  <li>siteId2ttsDevice_&lt;siteId&gt;</li>
  <a href="#RHASSPY-experimental"><b>experimental!</b></a> If an AMADDevice TYPE device is enabled for <a href="#RHASSPY-attr-rhasspySpeechDialog">rhasspySpeechDialog</a>, RHASSPY will forward response texts to the device for own text-to-speach processing. Setting this type of reading allows redirection of adressed satellites to the given AMADDevice (device name as reading value, 0 to disable); naming scheme is the same as for site2room.
</ul>
=end html
=cut
