
# $Id$

package main;

use strict;
use warnings;

#use IO::Socket::INET;

sub
alexa_Initialize($)
{
  my ($hash) = @_;

  #$hash->{ReadFn}   = "alexa_Read";

  $hash->{DefFn}    = "alexa_Define";
  #$hash->{NOTIFYDEV} = "global";
  #$hash->{NotifyFn} = "alexa_Notify";
  $hash->{UndefFn}  = "alexa_Undefine";
  $hash->{SetFn}    = "alexa_Set";
  $hash->{GetFn}    = "alexa_Get";
  #$hash->{AttrFn}   = "alexa_Attr";
  $hash->{AttrList} = "$readingFnAttributes";
}

#####################################

sub
alexa_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> alexa"  if(@a != 2);

  my $name = $a[0];
  $hash->{NAME} = $name;

  my $d = $modules{$hash->{TYPE}}{defptr};
  return "$hash->{TYPE} device already defined as $d->{NAME}." if( defined($d) );
  $modules{$hash->{TYPE}}{defptr} = $hash;

  addToAttrList("$hash->{TYPE}Name");

  $hash->{STATE} = 'active';

  return undef;
}

sub
alexa_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  return undef;
}

sub
alexa_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
alexa_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "reload";

  if( $cmd eq 'reload' ) {
    $hash->{".triggerUsed"} = 1;
    if( @args ) {
      FW_directNotify($name, "reload $args[0]");
    } else {
      FW_directNotify($name, 'reload');
    }

    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
alexa_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "customSlotTypes";

  if( lc($cmd) eq 'customslottypes' ) {
    if( $hash->{CL} ) {
      FW_directNotify($name, "customSlotTypes $hash->{CL}{NAME}");
    } else {
      FW_directNotify($name, 'customSlotTypes');
    }

    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
alexa_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}

sub
alexa_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $len;
  my $buf;

  $len = $hash->{CD}->recv($buf, 1024);
  if( !defined($len) || !$len ) {
Log 1, "!!!!!!!!!!";
    return;
  }

  alexa_Parse($hash, $buf, $hash->{CD}->peerhost);
}

sub
alexa_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  my $hash = $defs{$name};
  if( $attrName eq "disable" ) {
  }

  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=item summary    Module to control the FHEM/Alexa integration
=item summary_DE Modul zur Konfiguration der FHEM/Alexa Integration
=begin html

<a name="alexa"></a>
<h3>alexa</h3>
<ul>
  Module to control the FHEM/Alexa integration.<br><br>

  Notes:
  <ul>
    <li><br>
    </li>
  </ul>

  <a name="alexa_Set"></a>
  <b>Set</b>
  <ul>
    <li>reload [name]<br>
      Reloads the device <it>name</it> or all devices in alexa-fhem. Subsequently you have to start a device discovery in alexa.
    </li>
  </ul>

  <a name="alexa_Get"></a>
  <b>Get</b>
  <ul>
    <li>customSlotTypes<br>
      Instructs alexa-fhem to write the Custom Slot Types for the Interaction Model to the alexa-fhem console
      and if possible to the requesting fhem frontend.
    </li>
  </ul>

  <a name="alexa_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>alexaName<br>
      The name to use for a device with alexa.
    </li>
  </ul>
</ul><br>

=end html
=cut
