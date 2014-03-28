# $Id$
##############################################
# 98_cloneDummy
# Von Joachim Herold
# FHEM Modul um aus Events von FHEM2FHEM clone-Devices zu erstellen
# cloneDummy ist "readonly"
# Grundlage ist 98_dummy.pm von Rudolf Koenig
# von betateilchen gab es viel Hilfe (eigentlich wars betateilchen)
# Anleitung:
# Um die Änderung zu nutzen, einfach einen cloneDummy anlegen
# 
# Eintrag in der fhem.cfg:
# define <name> cloneDummy <quellDevice> [reading]
# attr <name> cloneIgnore <reading1,reading2,...,readingX>
#
#############################################

package main;

use strict;
use warnings;

sub cloneDummy_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}     = "cloneDummy_Define";
	$hash->{NotifyFn}  = "cloneDummy_Notify";
	$hash->{AttrList}  = "cloneIgnore ".$readingFnAttributes;
}

sub cloneDummy_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	return "Wrong syntax: use define <name> cloneDummy <sourceDevice> [reading]" if((int(@a) < 3 || int(@a) > 4)) ;
	return "Error: cloneDummy and sourceDevice must not have the same name!" if($a[0] eq $a[2]);
	my $hn = $hash->{NAME};
	$hash->{NOTIFYDEV} = $a[2];
	$hash->{NOTIFYSTATE} = $a[3] if(defined($a[3]));
	$attr{$hn}{stateFormat} = "_state" if(defined($a[3]));	
	readingsSingleUpdate($hash,'state','defined',1);
	Log3($hash,4,"cloneDummy: $a[0] defined for source $a[2]");
	return undef;
}

sub cloneDummy_Notify($$) {
	my ($hash, $dev) = @_;
	my $dn      = $dev->{NAME};
	my $hn      = $hash->{NAME};	
	my $hs      = "";	
	if(defined($hash->{NOTIFYSTATE})) {
	  $hs = $hash->{NOTIFYSTATE};
	}
	my $reading = $dev->{CHANGED}[0];
	$reading = "" if(!defined($reading));
	Log3($hash,4, "cloneDummy: $hash D: $dn R: $reading");
	my ($rname,$rval) = split(/ /,$reading,2);
	$rname = substr($rname,0,length($rname)-1);
	my %check = map { $_ => 1 } split(/,/,AttrVal($hn,'cloneIgnore',''));
	
	readingsBeginUpdate($hash);
		if (($hs ne "") && ($rname eq $hs) ){
	readingsBulkUpdate($hash,"_state", $reading);	
	}
	readingsBulkUpdate($hash,"state", "active");	
	unless (exists ($check{$rname})) {
		readingsBulkUpdate($hash, $rname, $rval);
	}
	readingsEndUpdate($hash, 1);
	
	return;
}

1;

=pod
=begin html

<a name="cloneDummy"></a>
<h3>cloneDummy</h3>
<ul>
	This module provides a cloneDummy which will receive readings from any other device sending data to fhem.<br/>
	E.g. may be used in an FHEM2FHEM environment<br/>
	<br/> 

	<a name="cloneDummydefine"></a>
	<b>Define</b>
	<ul>
		<code>define &lt;cloneDevice&gt; cloneDummy &lt;sourceDevice&gt; [reading]</code>
		<br/>
		<br/>
		Example:<br/>
		<br/>
		<ul><code>define clone_OWX_26_09FF26010000 cloneDummy OWX_26_09FF26010000</code></ul>
		<br/>
		Optional parameter [reading] will be written to STATE if provided.<br/>
		<br/>
		Example:<br/>
		<br/>
		<ul><code>define clone_OWX_26_09FF26010000 cloneDummy OWX_26_09FF26010000 temperature</code></ul>
	</ul>
	<br/>

<a name="cloneDummyset"></a>
	<b>Set</b> <ul>N/A</ul>
	<br/>

	<a name="cloneDummyget"></a>
	<b>Get</b> <ul>N/A</ul>
	<br/>

	<a name="cloneDummyattr"></a>
	<b>Attributes</b>
	<ul>
		<li><a href="#readingFnAttributes"><b>readingFnAttributes</b></a></li>
		<li><b>cloneIgnore</b> - comma separated list of readingnames that will NOT be generated.<br/>
				Usefull to prevent truncated readingnames coming from state events.</li>
	</ul>
	<br/>
	<b>Important: You MUST use different names for cloneDevice and sourceDevice!</b><br/>
</ul>

=end html

=begin html_DE

<a name="cloneDummy"></a>
<h3>cloneDummy</h3>
<ul>
	Definiert einen Clon eines Devices oder von FHEM2FHEM im Logmodus uebergebenen Devices und uebernimmt dessen Readings.
	Sinnvoll um entfernte FHEM-Installationen lesend einzubinden, zum Testen oder Programmieren. 
	<br><br>

	<a name="cloneDummydefine"></a>
	<b>Define</b>
	<ul>
	<code>define &lt;name&gt; cloneDummy &lt;Quelldevice&gt; [reading]</code>
	<br><br>
	Aktiviert den cloneDummy, der dann an das Device &lt;Quelldevice&gt; gebunden ist. Mit dem optionalen Parameter reading
		wird bestimmt, welches reading im STATE angezeigt wird, stateFormat ist auch weiterhin möglich.
	<ul>
	Beispiel: Der cloneDummy wird lesend an den Sensor OWX_26_09FF26010000 gebunden und zeigt im State temperature an.
	</ul>
	
	<ul>
		<code>define Feuchte cloneDummy OWX_26_09FF26010000 temperature</code><br>
	</ul>
	</ul>
	<br>

	<a name="cloneDummyset"></a>
	<b>Set</b> <ul>N/A</ul><br>

	<a name="cloneDummyget"></a>
	<b>Get</b> <ul>N/A</ul><br>

	<a name="cloneDummyattr"></a>
	<b>Attributes</b>
	<ul>
	<li>clonIgnore<br>
			Eine durch Kommata getrennte Liste der readings, die cloneDummy nicht in eigene readings umwandelt
		</li><br>
	<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
	</ul>
	<br>

</ul>

=end html_DE

=cut
