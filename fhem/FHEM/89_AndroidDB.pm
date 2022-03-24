
#
# $Id$
#
# 89_AndroidDB
#
# Version 0.8
#
# FHEM Integration for Android Devices
#
# Dependencies:
#
#   89_AndroidDBHost
#
# Prerequisits:
#
#   - Enable developer mode on Android device
#   - Allow USB debugging on Android device
#


package main;

use strict;
use warnings;
use SetExtensions;

sub AndroidDB_Initialize ($)
{
    my ($hash) = @_;

    $hash->{DefFn}      = "AndroidDB::Define";
    $hash->{UndefFn}    = "AndroidDB::Undef";
    $hash->{SetFn}      = "AndroidDB::Set";
    $hash->{GetFn}      = "AndroidDB::Get";
    $hash->{AttrFn}     = "AndroidDB::Attr";
    $hash->{ShutdownFn} = "AndroidDB::Shutdown";

    $hash->{parseParams} = 1;
    $hash->{AttrList} = 'connect:0,1 createReadings macros:textField-long preset presetFile '.$readingFnAttributes;

    $data{RC_layout}{MagentaTVStick} = "AndroidDB::RCLayoutMagentaTVStick";
    $data{RC_layout}{MagentaOne} = "AndroidDB::RCLayoutMagentaOne";
    $data{RC_layout}{MagentaTVExtended} = "AndroidDB::RCLayoutMagentaTVExt";
}

package AndroidDB;

use strict;
use warnings;
use SetExtensions;
use Storable qw(dclone);
use GPUtils qw(:all); 

BEGIN {
    GP_Import(qw(
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBulkUpdateIfChanged
        readingsBeginUpdate
        readingsEndUpdate
        makeReadingName
        setDevAttrList
        CommandDefine
        CommandSet
        CommandAttr
        Log3
        AttrVal
        ReadingsVal
        AssignIoPort
        InternalTimer
        asyncOutput
        gettimeofday
        parseParams
        defs
        attr
        modules
        data
        init_done
    ))
};

# Remote control presets
my $PRESET = {
    'MagentaTVStick' => {
       'ASSISTANT'  => 'KEYCODE_ASSIST',
        'APPS'       => 'KEYCODE_ALL_APPS',
        'BACK'       => 'KEYCODE_BACK',
        'EPG'        => 'KEYCODE_TV_INPUT_HDMI_2',
        'HOME'       => 'KEYCODE_HOME',
        'LEFT'       => 'KEYCODE_DPAD_LEFT',
        'RIGHT'      => 'KEYCODE_DPAD_RIGHT',
        'UP'         => 'KEYCODE_DPAD_UP',
        'DOWN'       => 'KEYCODE_DPAD_DOWN',
        'INFO'       => 'KEYCODE_INFO',
        'MEGATHEK'   => 'KEYCODE_TV_INPUT_HDMI_3',
        'MUTE'       => 'KEYCODE_VOLUME_MUTE',
        'OK'         => 'KEYCODE_DPAD_CENTER',
        'PLAYPAUSE'  => 'KEYCODE_MEDIA_PLAY_PAUSE',
        'POWER'      => 'KEYCODE_POWER',
        'PROG+'      => 'KEYCODE_CHANNEL_UP',
        'PROG-'      => 'KEYCODE_CHANNEL_DOWN',
        'RECORD'     => 'KEYCODE_MEDIA_RECORD',
        'SEARCH'     => 'KEYCODE_TV_INPUT_HDMI_1',
        'STREAMINFO' => '--longpress,KEYCODE_INFO',
        'TV'         => 'KEYCODE_TV_INPUT_HDMI_4',
        'VOL+'       => 'KEYCODE_VOLUME_UP',
        'VOL-'       => 'KEYCODE_VOLUME_DOWN'
    },
    'MagentaOne' => {
       'ASSISTANT'  => 'KEYCODE_ASSIST',
        'APPS'       => 'KEYCODE_ALL_APPS',
        'BACK'       => 'KEYCODE_BACK',
        'EPG'        => 'KEYCODE_TV_INPUT_HDMI_2',
        'HOME'       => 'KEYCODE_HOME',
        'LEFT'       => 'KEYCODE_DPAD_LEFT',
        'RIGHT'      => 'KEYCODE_DPAD_RIGHT',
        'UP'         => 'KEYCODE_DPAD_UP',
        'DOWN'       => 'KEYCODE_DPAD_DOWN',
        'INFO'       => 'KEYCODE_INFO',
        'MEGATHEK'   => 'KEYCODE_TV_INPUT_HDMI_3',
        'MUTE'       => 'KEYCODE_VOLUME_MUTE',
        'OK'         => 'KEYCODE_DPAD_CENTER',
        'PLAYPAUSE'  => 'KEYCODE_MEDIA_PLAY_PAUSE',
        'POWER'      => 'KEYCODE_POWER',
        'PROG+'      => 'KEYCODE_CHANNEL_UP',
        'PROG-'      => 'KEYCODE_CHANNEL_DOWN',
        'RECORD'     => 'KEYCODE_MEDIA_RECORD',
        'SEARCH'     => 'KEYCODE_TV_INPUT_HDMI_1',
        'STREAMINFO' => '--longpress,KEYCODE_INFO',
        'TV'         => 'KEYCODE_TV_INPUT_HDMI_4',
        'VOL+'       => 'KEYCODE_VOLUME_UP',
        'VOL-'       => 'KEYCODE_VOLUME_DOWN'
    },
    'AndroidTV' => {
        'APPS'       => 'KEYCODE_ALL_APPS',
        'BACK'       => 'KEYCODE_BACK',
        'EPG'        => 'KEYCODE_GUIDE',
        'HOME'       => 'KEYCODE_HOME',
        'LEFT'       => 'KEYCODE_DPAD_LEFT',
        'RIGHT'      => 'KEYCODE_DPAD_RIGHT',
        'UP'         => 'KEYCODE_DPAD_UP',
        'DOWN'       => 'KEYCODE_DPAD_DOWN',
        'INFO'       => 'KEYCODE_INFO',
        'MUTE'       => 'KEYCODE_VOLUME_MUTE',
        'OK'         => 'KEYCODE_DPAD_CENTER',
        'PLAYPAUSE'  => 'KEYCODE_MEDIA_PLAY_PAUSE',
        'POWER'      => 'KEYCODE_POWER',
        'PROG+'      => 'KEYCODE_CHANNEL_UP',
        'PROG-'      => 'KEYCODE_CHANNEL_DOWN',
        'RECORD'     => 'KEYCODE_MEDIA_RECORD',
        'SEARCH'     => 'KEYCODE_SEARCH',
        'VOL+'       => 'KEYCODE_VOLUME_UP',
        'VOL-'       => 'KEYCODE_VOLUME_DOWN',
        'RED'        => 'KEYCODE_PROG_RED',
        'GREEN'      => 'KEYCODE_PROG_GREEN',
        'BLUE'       => 'KEYCODE_PROG_BLUE',
        'YELLOW'     => 'KEYCODE_PROG_YELLOW'
    }
};

# Command presets
my $MACRO = { };

sub Define ($$$)
{
   my ($hash, $a, $h) = @_;

   my $usage = "define $hash->{NAME} AndroidDB {NameOrIP[:Port]}";

   return $usage if (scalar(@$a) < 3);

   # Set parameters
   my ($devName, $devPort) = split (':', $$a[2]);
   $hash->{ADBDevice} = $devName.':'.($devPort // '5555');

   AssignIoPort ($hash);

   $attr{$hash->{NAME}}{webCmd} = 'remoteControl';

   # Clone predefined presets and macros
   $hash->{adb}{preset} = dclone $PRESET;
   $hash->{adb}{macro} = dclone $MACRO;

   InitAfterStart ($hash) if ($init_done);

   return undef;
}

sub InitAfterStart ($)
{
    my ($hash) = @_;
    
    my @presets = map { $_ eq '_custom_' ? () : $_ } keys %{$hash->{adb}{preset}};

    if (scalar(@presets) > 0) {
        my $attrPreset = 'preset:select,'.join(',',@presets);
        my $attributes = $modules{AndroidDB}{AttrList};
        $attributes =~ s/preset/$attrPreset/;
        setDevAttrList ($hash->{NAME}, $attributes);
    }
}

sub Undef ($$)
{
   my ($hash, $name) = @_;

    AndroidDBHost::Disconnect ($hash);
   
   return undef;
}

sub Shutdown ($)
{
    my ($hash) = @_;
    
    AndroidDBHost::Disconnect ($hash);
}

sub Set ($@)
{
    my ($hash, $a, $h) = @_;
    
    my $name = shift @$a;
    my $opt = shift @$a // return 'No set command specified';

    #
    # Preprare list of available commands
    #
    
    # Standard commands
    my $options = 'exportPresets reboot rollHorz rollVert sendKey sendNumKeys sendText shell tap';
    
    # Add remote control key presets to command remoteControl
    my @presetList = ();
    my $preset   = AttrVal ($name, 'preset', '');
    push @presetList, sort keys %{$hash->{adb}{preset}{$preset}} if ($preset ne '' && exists($hash->{adb}{preset}{$preset}));
    push @presetList, sort keys %{$hash->{adb}{preset}{_custom_}} if (exists($hash->{adb}{preset}{_custom_}));
    my %e1;
    $options .= ' remoteControl:'.join(',', sort grep { !$e1{$_}++ } @presetList) if (scalar(@presetList) > 0);
    
    # Add remote control layouts to command createRemote
    my @layouts = keys %{$data{RC_layout}};
    $options .= ' createRemote:'.join(',', sort @layouts) if (scalar(@layouts) > 0);
    
    # Add command macros to command list
    my @macroList = ();
    push @macroList, sort keys %{$hash->{adb}{macro}{$preset}} if ($preset ne '' && exists($hash->{adb}{macro}{$preset}));
    push @macroList, sort keys %{$hash->{adb}{macro}{_custom_}} if (exists($hash->{adb}{macro}{_custom_}));
    my %e2;
    $options .= ' '.join(' ', sort grep { !$e2{$_}++ } @macroList) if (scalar(@macroList) > 0);

    my $lcopt = lc($opt);

    if ($lcopt eq 'sendkey') {
        return "Usage: set $name $opt [--longpress] KeyCode [...]" if (scalar(@$a) == 0);
        return "Only one KeyCode allowed when option '--longpress' is specified"
            if ($$a[0] eq '--longpress' && scalar(@$a) > 2);
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'keyevent', @$a);
        return $error if ($rc == 0);
    }
    elsif ($lcopt eq 'sendnumkeys') {
        my $number = shift @$a // return "Usage: set $name $opt Number";
        return 'Parameter Number must be in range 1-9999' if ($number !~ /^[0-9]+$/ || $number < 1 || $number > 9999);
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'text', $number);
        return $error if ($rc == 0);
    }
    elsif ($lcopt eq 'sendtext') {
        return "Usage: set $name $opt Text" if (scalar(@$a) < 1);
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'text', join(' ',@$a));
        return $error if ($rc == 0);
    }
    elsif ($lcopt eq 'reboot') {
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, $opt);
        return $error if ($rc == 0);
    }
    elsif ($lcopt eq 'shell') {
        return "Usage: set $name $opt ShellCommand" if (scalar(@$a) == 0);
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, $opt, '.*', @$a);
        return $error if ($rc == 0);
        my $createReadings = AttrVal ($name, 'createReadings', '');
        return $result if ($createReadings eq '' || $createReadings !~ /$createReadings/);
        UpdateReadings ($hash, $result);
    }
    elsif ($lcopt eq 'remotecontrol') {
        my $macroName = shift @$a // return "Usage: set $name $opt MacroName";
        $preset = '_custom_' if (exists($hash->{adb}{preset}{_custom_}) && exists($hash->{adb}{preset}{_custom_}{$macroName}));
        return "Preset and/or macro $macroName not defined in preset $preset"
            if ($preset eq '' || !exists($hash->{adb}{preset}{$preset}{$macroName}));
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'keyevent',
            split (',', $hash->{adb}{preset}{$preset}{$macroName}));
        return $error if ($rc == 0);
    }
    elsif ($lcopt eq 'tap') {
        my ($x, $y) = @$a;
        return "Usage: set $name $opt tap X Y" if (!defined($y));
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'tap', $x, $y);
        return $error if ($rc == 0);		
    }
    elsif ($lcopt eq 'rollhorz' || $lcopt eq 'rollvert') {
        my $delta = shift @$a // return "Usage: set $name $opt Delta";
        my ($dx, $dy) = $opt eq 'rollhorz' ? ($delta, 0) : (0, $delta);
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'roll', $dx, $dy);
        return $error if ($rc == 0);
    }
    elsif ($lcopt eq 'createremote') {
        my $layout = shift @$a // return "Usage: set $name $opt LayoutName";
        my $rcName = $name.'_RC';
        return "$name: Can't create remotecontrol device $rcName"
            if (CommandDefine (undef, "$rcName remotecontrol"));
        Log3 $name, 2, "$name: Created remotecontrol device $rcName";
        return "$name: Can't select layout $layout for remotecontrol device $rcName"
            if (CommandSet (undef, "$rcName layout $layout"));
        Log3 $name, 2, "Selected layout $layout for $rcName";
        my $room = AttrVal ($name, 'room', '');
        if ($room ne '') {
            Log3 $name, 2, "$name: Assigning $rcName to room $room";
            CommandAttr (undef, "$rcName room $room");
        }
        CommandSet (undef, "$rcName makenotify $name");
        CommandAttr (undef, "$name group $name");
        CommandAttr (undef, "$rcName group $name");
        Log3 $name, 2, "Created notify device notify_$rcName";
    }
    elsif ($lcopt eq 'exportpresets') {
        my $filename = shift @$a // return "Usage: set $name $opt Filename";
        my $rc = ExportPresets ($hash, $filename);
        return "Error while saving presets to file $filename" if ($rc == 0);
        return "Presets saved to file $filename";
    }
    elsif (exists($hash->{adb}{macro}{_custom_}) && exists($hash->{adb}{macro}{_custom_}{$opt})) {
        my ($args, $pars) = parseParams ($hash->{adb}{macro}{_custom_}{$opt});
        my $cmd = shift @$args;
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, $cmd, '.*', @$args);
        return $rc == 0 ? $error : $result;	
    }
    elsif ($preset ne '' && exists($hash->{adb}{macro}{$preset}) && exists($hash->{adb}{macro}{$preset}{$opt})) {
        my ($args, $pars) = parseParams ($hash->{adb}{macro}{$preset}{$opt});
        my $cmd = shift @$args;
        my ($rc, $result, $error) = AndroidDBHost::Run ($hash, $cmd, '.*', @$args);
        return $rc == 0 ? $error : $result;	
    }
    else {
        return "Unknown argument $opt, choose one of $options";
    }
}

sub Get ($@)
{
    my ($hash, $a, $h) = @_;

    my $name = shift @$a;
    my $opt = shift @$a // return 'No get command specified';
    
    my $options = 'keyPreset';
    my @presetList = sort keys %{$hash->{adb}{preset}};
    $options .= ':'.join(',', @presetList) if (scalar(@presetList) > 0);
    my @macroList = sort keys %{$hash->{adb}{macro}};
    $options .= ' cmdPreset:'.join(',', @macroList) if (scalar(@macroList) > 0);
    
    my $attrPreset = AttrVal ($name, 'preset', '');
    
    my $lcopt = lc($opt);
    
    if ($lcopt eq 'keypreset') {
        my $preset = shift @$a // $attrPreset;
        return "Usage: get $name $opt PresetName" if ($preset eq '');
        return "Key preset $preset not found" if (!exists($hash->{adb}{preset}{$preset}));
        my $presetDef = "Definition of key preset $preset:<br/><br/>";
        foreach my $macro (sort keys %{$hash->{adb}{preset}{$preset}}) {
            $presetDef .= "$macro = $hash->{adb}{preset}{$preset}{$macro}<br/>";
        }
        return $presetDef;
    }
    elsif ($lcopt eq 'cmdpreset') {
        my $preset = shift @$a // $attrPreset;
        return "Usage: get $name $opt PresetName" if ($preset eq '');
        return "Command preset $preset not found" if (!exists($hash->{adb}{macro}{$preset}));	
        my $macroDef = "Definition of command preset $preset:<br/><br/>";
        foreach my $macro (sort keys %{$hash->{adb}{macro}{$preset}}) {
            $macroDef .= "$macro = $hash->{adb}{macro}{$preset}{$macro}<br/>";
        }
        return $macroDef;
    }
    else {
        return "Unknown argument $opt, choose one of $options";
    }
}

sub Attr ($@)
{
    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};

    if ($cmd eq 'set') {
        if ($attrName eq 'macros') {
           delete $hash->{adb}{preset}{_custom_} if (exists($hash->{adb}{preset}{_custom_}));
           delete $hash->{adb}{macro}{_custom_} if (exists($hash->{adb}{macro}{_custom_}));
            foreach my $macroDef (split /;/, $attrVal) {
                my ($macroName, $macroPar) = split (':', $macroDef, 2);
                if (!defined($macroDef)) {
                    Log3 $name, 2, "Missing defintion for macro $macroName";
                    return "Missing definition for macro $macroName";
                }
                if ($macroPar =~ /^[0-9]+/ || $macroPar =~ /^KEYCODE_/) {
                    $hash->{adb}{preset}{_custom_}{$macroName} = $macroPar;
                }
                else {
                    $hash->{adb}{macro}{_custom_}{$macroName} = $macroPar;
                }
            }
        }
        elsif ($attrName eq 'presetFile') {
            if (!LoadPresets ($hash, $attrVal)) {
                return "Cannot load presets from file $attrVal";
            }
        }
        elsif ($attrName eq 'connect') {
            AndroidDBHost::Connect ($hash) if (!$init_done && $attrVal eq '1');
        }
    }
    elsif ($cmd eq 'del') {
        delete $hash->{adb}{preset}{_custom_} if (exists($hash->{adb}{preset}{_custom_}));
        delete $hash->{adb}{macro}{_custom_} if (exists($hash->{adb}{macro}{_custom_}));
    }

    return undef;
}

##############################################################################
# Load macro definitions from file
# File format:
#  - Lines starting with a # are treated as comments
#  - Empty lines are ignored
#  - Lines containing a single word are setting the preset name for the
#    following lines
#  - Lines in format Name:KeyList are defining a macro. KeyList is a comma 
#    separated list of keycodes.
#  - Lines in format Name:Command:Parameters are defining a command macro.
##############################################################################

sub LoadPresets ($$)
{
    my ($hash, $fileName) = @_;

    # Read file
    my @lines;
    if (open (PRESETFILE, "<$fileName")) {
        @lines = <PRESETFILE>;
        close (PRESETFILE);
    }
    else {
        ShowMessage ($hash, 2, "Can't open file $fileName");
        return 0;
    }

    # Delete old presets
    my @presets = keys %{$hash->{adb}{preset}};
    my @macros = keys %{$hash->{adb}{macro}};
    foreach my $e (@presets) { delete $hash->{adb}{preset}{$e} if ($e ne '_custom_'); }	
    foreach my $e (@macros) { delete $hash->{adb}{macro}{$e} if ($e ne '_custom_'); }	

    chomp @lines;
    my $presetName = '';
    
    foreach my $l (@lines) {
        next if ($l =~ /^#/);	# Comments are allowed

        my ($macroName, $macroPar) = split (':', $l, 2);
        if (!defined($macroPar)) {
            next if (!defined($macroName) || $macroName eq '');
            if ($macroName !~ /^[a-zA-Z0-9-_]+$/) {
                ShowMessage ($hash, 2, "Invalid character in macro name $macroName in file $fileName");
                return 0;
            }
            $presetName = $macroName;
        }
        else {
            if ($presetName eq '') {
                ShowMessage ($hash, 2, "No preset name set for macro name $macroName in file $fileName");
                return 0;
            }
            if ($macroPar =~ /^[0-9]+/ || $macroPar =~ /^(KEYCODE_|--longpress)/) {
                $hash->{adb}{preset}{$presetName}{$macroName} = $macroPar;
            }
            else {
                $hash->{adb}{macro}{$presetName}{$macroName} = $macroPar;
            }
        }
    }
    
    # Init options of attribute 'preset'
    InitAfterStart ($hash);
    
    return 1;
}

sub ExportPresets ($$)
{
    my ($hash, $filename) = @_;

    if (open (PRESETFILE, ">$filename")) {
        foreach my $preset (sort keys %{$hash->{adb}{preset}}) {
            next if ($preset eq '_custom_');
            print PRESETFILE "#\n# Preset $preset\n#\n$preset\n#\n";
            foreach my $macro (sort keys %{$hash->{adb}{preset}{$preset}}) {
                print PRESETFILE "$macro:$hash->{adb}{preset}{$preset}{$macro}\n";
            }
            if (exists($hash->{adb}{macro}{$preset})) {
                foreach my $macro (sort keys %{$hash->{adb}{macro}{$preset}}) {
                    print PRESETFILE "$macro:$hash->{adb}{macro}{$preset}{$macro}\n";
                }
            }
        }
        foreach my $preset (sort keys %{$hash->{adb}{macro}}) {
            next if ($preset eq '_custom_' || exists($hash->{adb}{preset}{$preset}));
            print PRESETFILE "#\n# Preset $preset\n#\n$preset\n#\n";
            foreach my $macro (sort keys %{$hash->{adb}{macro}{$preset}}) {
                print PRESETFILE "$macro:$hash->{adb}{macro}{$preset}{$macro}\n";
            }
        }
        close (PRESETFILE);
        return 1;
    }
    
    return 0;
}

sub UpdateReadings ($$)
{
   my ($hash, $data) = @_;

   readingsBeginUpdate ($hash);

   foreach my $line (split /[\n\r]+/, $data) {
      $line =~ s/^\s+//;      # Remove leading whitespace characters 
      next if ($line eq '');  # Ignore empty lines
      my @a = split('=', $line);
      next if (scalar(@a) != 2);
      my $r = makeReadingName ($a[0]);
      readingsBulkUpdate ($hash, $r, $a[1]);
   }

   readingsEndUpdate ($hash, 1);
}

sub ShowMessage ($$$)
{
    my ($hash, $level, $msg) = @_;
    
    Log3 $hash->{NAME}, $level, $msg;
    
    if ($init_done && exists($hash->{CL})) {
        my $cl = $hash->{CL};
        InternalTimer (gettimeofday()+1, sub { asyncOutput ($cl, $msg) }, undef, 1);
    }
}

##############################################################################
# Remote control layout for Magenta TV Stick
##############################################################################

sub RCLayoutMagentaTVStick () {
    my @row = (
        'sendKey KEYCODE_POWER:POWEROFF,:blank,sendKey KEYCODE_VOLUME_MUTE:MUTE',
        ':blank,sendKey KEYCODE_TV_INPUT_HDMI_3:PS3Rectangle,:blank',
        ':blank,sendKey KEYCODE_ALL_APPS:TOOLS,:blank',
        'sendKey KEYCODE_TV_INPUT_HDMI_4:TV,:blank,sendKey KEYCODE_TV_INPUT_HDMI_2:GUIDE',
        ':blank,sendKey KEYCODE_DPAD_UP:UP,:blank',
        'sendKey KEYCODE_DPAD_LEFT:LEFT,sendKey KEYCODE_DPAD_CENTER:OK,sendKey KEYCODE_DPAD_RIGHT:RIGHT',
        ':blank,sendKey KEYCODE_DPAD_DOWN:DOWN,:blank',
        'sendKey KEYCODE_BACK:BACKDroid,sendKey KEYCODE_HOME:HOMEDroid,sendKey KEYCODE_INFO:INFO',
        'sendKey KEYCODE_MEDIA_RECORD:REC,sendKey KEYCODE_TV_INPUT_HDMI_1:SEARCH,sendKey KEYCODE_VOLUME_UP:VOLUP',
        'sendKey KEYCODE_MEDIA_PLAY_PAUSE:PLAYPAUSE,sendKey KEYCODE_ASSIST:SOURCE,sendKey KEYCODE_VOLUME_DOWN:VOLDOWN',
        'attr rc_iconpath icons/remotecontrol',
        'attr rc_iconprefix black_btn_'
    );
    
    return @row;
}

##############################################################################
# Remote control layout for Magenta One 
##############################################################################

sub RCLayoutMagentaOne () {
    my @row = (
        'sendKey KEYCODE_POWER:POWEROFF,:blank,sendKey KEYCODE_VOLUME_MUTE:MUTE',
        ':blank,:blank,:blank',
        'sendKey KEYCODE_TV_INPUT_HDMI_1:SEARCH,sendKey KEYCODE_ASSIST:SOURCE,sendKey KEYCODE_GUIDE:GUIDE',
        'sendKey KEYCODE_BACK:BACKDroid,sendKey KEYCODE_HOME:HOMEDroid,sendKey KEYCODE_ALL_APPS:MENUDroid',
        ':blank,sendKey KEYCODE_DPAD_UP:UP,:blank',
        'sendKey KEYCODE_DPAD_LEFT:LEFT,sendKey KEYCODE_DPAD_CENTER:OK,sendKey KEYCODE_DPAD_RIGHT:RIGHT',
        ':blank,sendKey KEYCODE_DPAD_DOWN:DOWN,:blank',
        'sendKey KEYCODE_VOLUME_UP:VOLUP,sendKey KEYCODE_MEDIA_PLAY_PAUSE:PLAYPAUSE,sendKey KEYCODE_CHANNEL_UP:CHUP',
        'sendKey KEYCODE_VOLUME_DOWN:VOLDOWN,:blank,sendKey KEYCODE_CHANNEL_DOWN:CHDOWN',
        'sendKey KEYCODE_1:1,sendKey KEYCODE_2:2,sendKey KEYCODE_3:3',
        'sendKey KEYCODE_4:4,sendKey KEYCODE_5:5,sendKey KEYCODE_6:6',
        'sendKey KEYCODE_7:7,sendKey KEYCODE_8:8,sendKey KEYCODE_9:9',
        'sendKey KEYCODE_INFO:INFO,sendKey KEYCODE_0:0,sendKey KEYCODE_MEDIA_RECORD:REC',
        'attr rc_iconpath icons/remotecontrol',
        'attr rc_iconprefix black_btn_'
    );
    
    return @row;
}

##############################################################################
# Extended remote control layout for Magenta TV 
##############################################################################

sub RCLayoutMagentaTVExt () {
    my @row = (
        'sendKey KEYCODE_POWER:POWEROFF,:blank,sendKey KEYCODE_VOLUME_MUTE:MUTE,:blank',
        ':blank,:blank,:blank,:blank',
        'sendKey KEYCODE_TV_INPUT_HDMI_1:SEARCH,sendKey KEYCODE_ASSIST:SOURCE,sendKey KEYCODE_GUIDE:GUIDE,sendKey KEYCODE_TV_INPUT_HDMI_4:TV',
        'sendKey KEYCODE_BACK:BACKDroid,sendKey KEYCODE_HOME:HOMEDroid,sendKey KEYCODE_ALL_APPS:MENUDroid,:blank',
        ':blank,sendKey KEYCODE_DPAD_UP:UP,:blank,:blank',
        'sendKey KEYCODE_DPAD_LEFT:LEFT,sendKey KEYCODE_DPAD_CENTER:OK,sendKey KEYCODE_DPAD_RIGHT:RIGHT,:blank',
        ':blank,sendKey KEYCODE_DPAD_DOWN:DOWN,:blank,:blank',
        'sendKey KEYCODE_VOLUME_UP:VOLUP,sendKey KEYCODE_MEDIA_PLAY_PAUSE:PLAYPAUSE,sendKey KEYCODE_CHANNEL_UP:CHUP,:blank',
        'sendKey KEYCODE_VOLUME_DOWN:VOLDOWN,:blank,sendKey KEYCODE_CHANNEL_DOWN:CHDOWN,:blank',
        'sendKey KEYCODE_1:1,sendKey KEYCODE_2:2,sendKey KEYCODE_3:3,:blank',
        'sendKey KEYCODE_4:4,sendKey KEYCODE_5:5,sendKey KEYCODE_6:6,:blank',
        'sendKey KEYCODE_7:7,sendKey KEYCODE_8:8,sendKey KEYCODE_9:9,:blank',
        'sendKey KEYCODE_INFO:INFO,sendKey KEYCODE_0:0,sendKey KEYCODE_MEDIA_RECORD:REC,:blank',
        'sendKey KEYCODE_PROG_RED:RED,sendKey KEYCODE_PROG_GREEN:GREEN,sendKey KEYCODE_PROG_YELLOW:YELLOW,sendKey KEYCODE_PROG_BLUE:BLUE',
        'attr rc_iconpath icons/remotecontrol',
        'attr rc_iconprefix black_btn_'
    );
    
    return @row;
}

1;

=pod
=item device
=item summary Allows to control an Android device via ADB (Android Debug Bridge)
=begin html

<a name="AndroidDB"></a>
<h3>AndroidDB</h3>
<ul>
   The module allows to control an Android device by using the Android Debug Bridge (ADB).
    Before one can define an Android device, an AndroidDBHost I/O device must exist.
    <br/><br/>
    Dependencies: 89_AndroidDBHost
   <br/><br/>
   <a name="AndroidDBdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; AndroidDB &lt;NameOrIP&gt;[&lt;Port&gt;]</code>
        The parameter <i>NameOrIP</i> is the hostname or the IP address of the Android device.
        The parameter <i>Port</i> specifies the TCP port to be used for the device connection.
        The default port is 5555.
   </ul>
   <br/>
</ul>

<a name="AndroidDBset"></a>
<b>Set</b><br/><br/>
<ul>
    <li><b>set &lt;Name&gt; createRemote &lt;Layout&gt;</b><br/>
        Create a remote control device for the Android device. Create a notify device for
        the remote control to send button events to the AndroidDB device.
    </li>br/>
    <li><b>set &lt;Name&gt; exportPresets &lt;Filename&gt;</b><br/>
       Export the currently loaded presets to file. This file can be modified and assigned 
       again by using attribute 'preset'.
    </li><br/>
    <li><b>set &lt;name&gt; reboot</b><br/>
        Reboot the device.
    </li><br/>
    <li><b>set &lt;name&gt; remoteControl &lt;MacroName&gt;</b><br/>
        Send key codes associated with 'MacroName' to the Android device. Either attribute
        'macros' or 'preset' must be set to make this command available. Macro names defined
        in attribute 'macros' are overwriting macros with the same name in a preset selected
        by attribute 'preset'.
    </li><br/>
    <li><b>set &lt;name&gt; rollHorz &lt;DeltaX&gt;</b><br/>
        Scroll display horizontally. Not supported on all types of Android devices.
    </li><br/> 
    <li><b>set &lt;name&gt; rollVert &lt;DeltaY&gt;</b><br/>
        Scroll display vertically. Not supported on all types of Android devices.
    </li><br/> 
    <li><b>set &lt;name&gt; sendKey [longpress] &lt;KeyCode&gt;</b> [...]<br/>
        Send a key code to the Android device. If option 'longpress' is specified, only one
        <i>KeyCode</i> is allowed.
    </li><br/>
    <li><b>set &lt;name&gt; sendNumKeys &lt;Number&gt;</b><br/>
        Send digits of <i>Number</i> to the Android device. <i>Number</i> must be in range 0-9999.
    </li><br/>
    <li><b>set &lt;name&gt; sendText &lt;Text&gt;</b><br/>
        Send <i>Text</i> to the Android device.
    </li><br/>
    <li><b>set &lt;name&gt; shell &lt;Command&gt; [&lt;Arguments&gt;]</b><br/>
        Execute shell command on Android device.
    </li><br/>
    <li><b>set &lt;name&gt; tap &lt;X&gt; &lt;Y&gt;</b><br/>
        Simulate a tap on a touchscreen (only available an devices having a touchscreen).
    </li><br/>
</ul>

<a name="AndroidDBget"></a>
<b>Get</b><br/><br/>
<ul>
    <li><b>set &lt;Name&gt; keyPreset &lt;PresetName&gt;</b><br/>
        List key preset definition.
    </li>br/>
    <li><b>set &lt;Name&gt; cmdPreset &lt;PresetName&gt;</b><br/>
        List command preset definition.
    </li>br/>
</ul>

<a name="AndroidDBattr"></a>
<b>Attributes</b><br/><br/>
<ul>
   <a name="connect"></a>
   <li><b>connect 0|1</b><br/>
       If set to 1, a connection to the Android device will be established during
       FHEM start. Note: Set this attribute for one Android device only!
   </li><br/>
   <a name="createReadings"></a>
   <li><b>createReadings &lt;command-expression&gt;</b><br/>
       Create readings for shell <i>command-expression</i>. Output must contain lines in format key=value.<br/>
       Example: attr myDev createReadings dumpsys
   </li><br/>
    <a name="macros"></a>
    <li><b>macros &lt;MacroDef&gt;[;...]</b><br/>
        Define a list of keycode macros to be sent to an Android device with 'remoteControl'
        command or define shortcuts for remote commands.<br/>
        A 'MacroDef' is using the following syntax:<br/>
        MacroName:KeyCode[,...]<br/>
        or<br/>
        MacroName:Command<br/><br/>
        Parameter <i>Command</i> is a adb command.<br/>
        Example, define a command 'set listpackages':<br/>
        <pre>attr myDev macros listpackages:shell pm list packages -f</pre><br/>
        Several macro definitions can be specified by seperating them using a semicolon.
    </li><br/>
    <a name="preset"></a>
    <li><b>preset &lt;PresetName&gt;</b><br/>
        Select a preset of keycode macros.
    </li><br/>
    <a name="presetFile"></a>
    <li><b>presetFile &lt;Filename&gt;</b><br/>
       Load a set of macros from a preset defintion file.
        If the same macro name is defined in the selected
        preset and in attribute 'macros', the definition in the 'macros' attribute overwrites
        the definition in the preset.<br/>
        A preset defintion file is using the following format:<br/>
        <pre>
        # Comment
        PresetName1
        MacroDef1
        MacroDef2
        ...
        PresetName2
        ...
        </pre>
        A 'MacroDef' is using the following syntax:<br/>
        MacroName:KeyCode[,...]<br/>
        or<br/>
        MacroName:Command:Parameters<br/><br/>
        Usually <i>Command</i> is 'shell'.
    </li><br/>
</ul>

=end html
=cut


