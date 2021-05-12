
#
# $Id$
#
# 89_AndroidDB
#
# Version 0.1
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
   $hash->{AttrList} = 'macros:textField-long preset:MagentaTVStick,SonyTV';
}

package AndroidDB;

use strict;
use warnings;

use Data::Dumper;

use SetExtensions;

use GPUtils qw(:all); 

BEGIN {
	GP_Import(qw(
		readingsSingleUpdate
		readingsBulkUpdate
		readingsBulkUpdateIfChanged
		readingsBeginUpdate
		readingsEndUpdate
		Log3
		AttrVal
		ReadingsVal
		AssignIoPort
		defs
	))
};

# Remote control presets
my %PRESET = (
	'MagentaTVStick' => {
		'APPS'     => 'KEYCODE_ALL_APPS',
		'BACK'     => 'KEYCODE_BACK',
		'EPG'      => 'KEYCODE_TV_INPUT_HDMI_2',
		'HOME'     => 'KEYCODE_HOME',
		'INFO'     => 'KEYCODE_INFO',
		'MEGATHEK' => 'KEYCODE_TV_INPUT_HDMI_3',
		'MUTE'     => 'KEYCODE_MUTE',
		'OK'       => 'KEYCODE_DPAD_CENTER',
		'POWER'    => 'KEYCODE_POWER',
		'PROG+'    => 'KEYCODE_CHANNEL_UP',
		'PROG-'    => 'KEYCODE_CHANNEL_DOWN',
		'RECORD'   => 'KEYCODE_MEDIA_RECORD',
		'SEARCH'   => 'KEYCODE_TV_INPUT_HDMI_1',
		'TV'       => 'KEYCODE_TV_INPUT_HDMI_4'
	},
	'SonyTV' => {
		'POWER'    => 'KEYCODE_POWER'
	}
);

sub Define ($$$)
{
   my ($hash, $a, $h) = @_;
   
	my $usage = "define $hash->{NAME} AndroidDB {NameOrIP}";
	
	return $usage if (scalar(@$a) < 3);

	# Set parameters
	my ($devName, $devPort) = split (':', $$a[2]);
	$hash->{ADBDevice} = $devName.':'.($devPort // '5555');
	
	AssignIoPort ($hash);
	
   return undef;
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

	# Preprare list of available commands
	my $options = 'reboot sendKey shell';
	my @macroList = ();
	my $preset = AttrVal ($hash->{NAME}, 'preset', '');
	my $macros = AttrVal ($hash->{NAME}, 'macros', '');
	push @macroList, sort keys %{$PRESET{$preset}} if ($preset ne '' && exists($PRESET{$preset}));
	push @macroList, sort keys %{$PRESET{_custom_}} if ($macros ne '' && exists($PRESET{_custom_}));
	my %e;
	$options .= ' remoteControl:'.join(',', sort grep { !$e{$_}++ } @macroList) if (scalar(@macroList) > 0);
	$opt = lc($opt);

	if ($opt eq 'sendkey') {
		my $key = shift @$a // return "Usage: set $name $opt KeyCode";
		my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'keyevent', $key);
		return $error if ($rc == 0);
	}
	elsif ($opt eq 'reboot') {
		my ($rc, $result, $error) = AndroidDBHost::Run ($hash, $opt);
		return $error if ($rc == 0);
	}
	elsif ($opt eq 'shell') {
		return "Usage: set $name $opt ShellCommand" if (scalar(@$a) == 0);
		my ($rc, $result, $error) = AndroidDBHost::Run ($hash, $opt, '.*', @$a);
		return $result.$error,
	}
	elsif ($opt eq 'remotecontrol') {
		my $macroName = shift @$a // return "Usage: set $name $opt MacroName";
		$preset = '_custom_' if (exists($PRESET{_custom_}) && exists($PRESET{_custom_}{$macroName}));
		return "Preset and/or macro $macroName not defined" if ($preset eq '' || !exists($PRESET{$preset}{$macroName}));
		my ($rc, $result, $error) = AndroidDBHost::Run ($hash, 'shell', '.*', 'input', 'keyevent',
			split (',', $PRESET{$preset}{$macroName}));
		return $error if ($rc == 0);
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
	
	my $options = 'presets';
	
	$opt = lc($opt);
	
	if ($opt eq 'presets') {
		return Dumper (\%PRESET);
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
			foreach my $macroDef (split /\s+/, $attrVal) {
				my ($macroName, $macroKeycodes) = split (':', $macroDef);
				$PRESET{_custom_}{$macroName} = $macroKeycodes;
			}
		}
	}
	elsif ($cmd eq 'del') {
		delete $PRESET{_custom_} if (exists($PRESET{_custom_}));
	}

	return undef;
}

1;

=pod
=item device
=item summary Allows to control an Android device via ADB
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
      <code>define &lt;name&gt; AndroidDB {&lt;NameOrIP&gt;}</code>
		The parameter 'NameOrIP' is the hostname or the IP address of the Android device.
   </ul>
   <br/>
</ul>

<a name="AndroidDBset"></a>
<b>Set</b><br/><br/>
<ul>
	<li><b>set &lt;name&gt; reboot</b><br/>
		Reboot the device.
	</li><br/>
	<li><b>set &lt;name&gt; remoteControl &lt;MacroName&gt;</b><br/>
		Send key codes associated with 'MacroName' to the Android device. Either attribute
		'macros' or 'preset' must be set to make this command available. Macro names defined
		in attribute 'macros' are overwriting macros with the same name in a preset selected
		by attribute 'preset'.
	</li><br/>
	<li><b>set &lt;name&gt; sendKey &lt;KeyCode&gt;</b><br/>
		Send a key code to the Android device.
	</li><br/>
	<li><b>set &lt;name&gt; shell &lt;Command&gt; [&lt;Arguments&gt;]</b><br/>
		Execute shell command on Android device.
	</li><br/>
</ul>

<a name="AndroidDBattr"></a>
<b>Attributes</b><br/><br/>
<ul>
	<a name="macros"></a>
	<li><b>macros &lt;MacroDef&gt; [...]</b><br/>
		Define a list of keycode macros to be sent to an Android device with 'remoteControl'
		command. A 'MacroDef' is using the following syntax:<br/>
		MacroName:KeyCode[,...]<br/>
		Several macro definitions can be specified by seperating them using a blank character.
	</li><br/>
	<a name="preset"></a>
	<li><b>preset &lt;Preset&gt;</b><br/>
		Select a preset of keycode macros. If the same macro name is defined in the selected
		preset and in attribute 'macros', the definition in the 'macros' attribute overwrites
		the definition in the preset.
	</li><br/>
</ul>

=end html
=cut


