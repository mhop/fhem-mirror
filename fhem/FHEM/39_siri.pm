
# $Id$

package main;

use strict;
use warnings;

use vars qw(%modules);
use vars qw(%defs);
use vars qw(%attr);
use vars qw($readingFnAttributes);
sub Log($$);
sub Log3($$$);

sub
siri_Initialize($)
{
  my ($hash) = @_;

  #$hash->{ReadFn}   = "siri_Read";

  $hash->{DefFn}    = "siri_Define";
  #$hash->{NOTIFYDEV} = "global";
  #$hash->{NotifyFn} = "siri_Notify";
  $hash->{UndefFn}  = "siri_Undefine";
  #$hash->{SetFn}    = "siri_Set";
  #$hash->{GetFn}    = "siri_Get";
  #$hash->{AttrFn}   = "siri_Attr";
  $hash->{AttrList} = "$readingFnAttributes";
}

#####################################

sub
siri_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> siri"  if(@a != 2);

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
siri_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  return undef;
}

sub
siri_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete $modules{$hash->{TYPE}}{defptr};

  return undef;
}

sub
siri_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
siri_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
siri_Parse($$;$)
{
  my ($hash,$data,$peerhost) = @_;
  my $name = $hash->{NAME};
}

sub
siri_Read($)
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

  siri_Parse($hash, $buf, $hash->{CD}->peerhost);
}

sub
siri_Attr($$$)
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
=item summary    Module to control the FHEM/Siri integration
=item summary_DE Modul zur Konfiguration der FHEM/Siri Integration
=begin html

<a name="siri"></a>
<h3>siri</h3>
<ul>
  Module to control the FHEM/Siri integration.<br><br>

  Notes:
  <ul>
    <li><br>
    </li>
  </ul>

  <a name="siri_Attr"></a>
  <b>Attr</b>
  <ul>
    <li>siriName<br>
    The name to use for a device with siri.</li>
  </ul>
</ul><br>

=end html
=cut
