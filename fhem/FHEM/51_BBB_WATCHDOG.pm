# $Id: 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub BBB_WATCHDOG_Initialize($){
	my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	$hash->{DefFn}		=	"BBB_WATCHDOG_Define";
	$hash->{UndefFn}	=	"BBB_WATCHDOG_Undefine";
	$hash->{ShutdownFn}	=	"BBB_WATCHDOG_Shutdown";
	$hash->{AttrList}	=	$readingFnAttributes;
}

sub BBB_WATCHDOG_Define($$){
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);
	my $dev = '/dev/watchdog@directio';

	DevIo_CloseDev($hash);
	$hash->{PARTIAL} = "";
	$hash->{DeviceName} = $dev;
	my $ret = DevIo_OpenDev($hash, 0, undef);
	triggerWD($hash);
	return $ret;
}

sub BBB_WATCHDOG_Undefine($$){
	my($hash, $name) = @_;
	DevIo_CloseDev($hash); 
	RemoveInternalTimer($hash);
	return;
}

sub BBB_WATCHDOG_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,4,"BBB_WATCHDOG $name: shutdown requested");
	DevIo_CloseDev($hash); 
	return undef;
}

sub triggerWD($) {
	my ($hash) = @_;
	Log3(undef, 4, "triggered");
	DevIo_SimpleWrite($hash, "X", undef);
	InternalTimer(gettimeofday()+40, "triggerWD", $hash, 0);
}

1;

=pod
not to be translated
=begin html

<a name="BBB_WATCHDOG"></a>
<h3>BBB_WATCHDOG</h3>
<ul>

	<b>Prerequesits</b>
	<ul><br/>
		<li><b>Module was developed for use with Beaglebone Black.</b><br/><br/></li>
		<li>To use this module, you have to create an udev-Rule for accessing /dev/watchdog<br/><br/>
		<code>SUBSYSTEM=="misc" ACTION=="add" DRIVER=="" KERNEL=="watchdog" MODE=="666"</code></li>
	</ul><br/><br/>
	
	<a name="BBB_WATCHDOGdefine"></a>
	<b>Define</b>
	<ul><br/>
		<code>define &lt;name&gt; BBB_WATCHDOG</code><br/><br/>
		This module provides a heartbeat signal to BBB internal watchdog device<br/>
		If this signal fails for more than 60 seconds, the BBB will perform a reboot.<br/>
	</ul><br/><br/>

	<a name="BBB_WATCHDOGset"></a>
	<b>Set-Commands</b><br/><br/>
	<ul>No set commands implemented.</ul><br/><br/>

	<a name="BBB_WATCHDOGget"></a>
	<b>Get-Commands</b><br/><br/>
	<ul>No get commands implemented.</ul><br/><br/>

	<a name="BBB_WATCHDOGattr"></a>
	<b>Attributes</b><br/><br/>
	<ul><a href="#readingFnAttributes">readingFnAttributes</a></ul><br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>Have fun!</ul>

</ul>

=end html
=begin html_DE

<a name="BBB_BMP180"></a>
<h3>BBB_BMP180</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#BBB_BMP180'>BBB_BMP180</a><br/>
</ul>
=end html_DE
=cut
