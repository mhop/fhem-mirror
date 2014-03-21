# $Id: $
##############################################
# 98_cloneDummy
#
# FHEM Modul um aus Events von FHEM2FHEM clone-Devices zu erstellen
# cloneDummy ist "readonly"
# Grundlage ist 98_dummy.pm von Rudolf Koenig
# von betateilchen gab es viel Hilfe (eigentlich wars betateilchen)
# Anleitung:
# Um die Änderung zu nutzen, einfach einen cloneDummy anlegen
# 
# Eintrag in der fhem.cfg:
# define <name> cloneDummy <quellDevice>
#
#
#############################################

package main;

use strict;
use warnings;

sub cloneDummy_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}     = "cloneDummy_Define";
	$hash->{NotifyFn}  = "cloneDummy_Notify";
	$hash->{AttrList}  = $readingFnAttributes;
}

sub cloneDummy_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
  return "Wrong syntax: use define <name> cloneDummy <sourceDevice>" if((int(@a) != 3)) ;
  return "Wrong syntax: <name> must different to <sourceDevice>" if($a[0] eq $a[2]) ;
	
	$hash->{NOTIFYDEV} = $a[2];
	readingsSingleUpdate($hash,'state','defined',1);
	Log3($hash,4,"cloneDummy: $a[0] defined for source $a[2]");
	return undef;
}

sub cloneDummy_Notify($$) {
	my ($hash, $dev) = @_;
	my $dn      = $dev->{NAME};
	my $hn      = $hash->{NAME};
	my $reading = $dev->{CHANGED}[0];
	$reading = "" if(!defined($reading));
	Log3($hash,3, "cloneDummy: $hn D: $dn R: $reading");
	
	my ($rname,$rval) = split(/ /,$reading,2);
	$rname = substr($rname,0,length($rname)-1);
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, $rname, $rval);
	readingsBulkUpdate($hash,'state','active');
	readingsEndUpdate($hash, 1);
	
	return;
}

1;

=pod
=begin html

<a name="cloneDummy"></a>
<h3>cloneDummy</h3>
<ul>

  Defines a clone of a device or transferred by FHEM2FHEM in log mode devices and is taking its readings.
   It makes sense to call remote FHEM installations involve reading , testing or programming. 
  <br><br>

  <a name="cloneDummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; cloneDummy &lt;sourcedevice&gt;</code>
    <br><br>

    Example:
    <ul>
      <code>define clone_OWX_26_09FF26010000 cloneDummy OWX_26_09FF26010000</code><br>
    </ul>
  </ul>
  <br>

  <a name="dummyset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="dummyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dummyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="cloneDummy"></a>
<h3>cloneDummy</h3>
<ul>

     Definiert einen Clon eines Devices oder von FHEM2FHEM im Logmodus uebergebenen Devices und uebernimmt dessen Readings.
     Sinnvoll um entfernte FHEM-Installationen lesend einzubinden,zum Testen oder Programmieren. 
  <br><br>

  <a name="cloneDummydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; cloneDummy &lt;Quelldevice&gt;</code>
    <br><br>

    Example:
    <ul>
      <code>define clone_OWX_26_09FF26010000 cloneDummy OWX_26_09FF26010000</code><br>
    </ul>
  </ul>
  <br>

  <a name="dummyset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="dummyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="dummyattr"></a>
  <b>Attributes</b>
  <ul>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
