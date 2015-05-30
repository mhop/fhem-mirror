##############################################
# $Id: 30_pilight_switch.pm 0.13 2015-05-30 Risiko $
#
# Usage
# 
# define <name> pilight_switch <protocol> <id> <unit> 
#
# Changelog
#
# V 0.10 2015-02-22 - initial beta version
# V 0.11 2015-03-29 - FIX:  $readingFnAttributes
# V 0.12 2015-05-18 - FIX:  add version information
# V 0.13 2015-05-30 - FIX:  StateFn
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;

sub pilight_switch_Parse($$);
sub pilight_switch_Define($$);


sub pilight_switch_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_switch_Define";
  $hash->{Match}    = "^PISWITCH";
  $hash->{ParseFn}  = "pilight_switch_Parse";
  $hash->{SetFn}    = "pilight_switch_Set";
  $hash->{StateFn}  = "pilight_switch_State";
  $hash->{AttrList} = $readingFnAttributes;
}

#####################################
sub pilight_switch_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 5) {
    my $msg = "wrong syntax: define <name> pilight_switch <protocol> <id> <unit>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  my $protocol = $a[2];
  my $id = $a[3];
  my $unit = $a[4];

  $hash->{STATE} = "defined";
  $hash->{PROTOCOL} = lc($protocol);  
  $hash->{ID} = $id;  
  $hash->{UNIT} = $unit;

  #$attr{$me}{verbose} = 5;
  
  $modules{pilight_switch}{defptr}{lc($protocol)}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub pilight_switch_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};
  
  #$hash->{STATE} wird nur ersetzt, wenn $hash->{STATE}  == ??? fhem.pl Z: 2469
  #machen wir es also selbst
  $hash->{STATE} = $val if ($name eq "state");
  return undef;
}

###########################################
sub pilight_switch_Parse($$)
{
  
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_switch_Parse: RCV -> $rmsg";
  
  my ($dev,$protocol,$id,$unit,$state,@args) = split(",",$rmsg);
  return () if($dev ne "PISWITCH");
  
  my $chash;
  foreach my $n (keys %{ $modules{pilight_switch}{defptr}{lc($protocol)} }) { 
    my $lh = $modules{pilight_switch}{defptr}{$protocol}{$n};
    next if ( !defined($lh->{ID}) || !defined($lh->{UNIT}) );
    if ($lh->{ID} eq $id && $lh->{UNIT} eq $unit) {
      $chash = $lh;
      last;
    }
  }
  
  return () if (!defined($chash->{NAME}));
  
  readingsBeginUpdate($chash);
  readingsBulkUpdate($chash,"state",$state);
  readingsEndUpdate($chash, 1); 
  
  return $chash->{NAME};
}

#####################################
sub pilight_switch_Set($$)
{  
  my ($hash, @a) = @_;
  my $me = shift @a;

  return "no set value specified" if(int(@a) < 1);
  return "Unknown argument ?, choose one of on off" if($a[0] eq "?");

  my $v = join(" ", @a);
  Log3 $me, 4, "$me(Set): $v";

  #readingsSingleUpdate($hash,"state",$v,1);
  
  my $msg = "$me,$v";
  IOWrite($hash, $msg);
  return undef;
}


1;

=pod
=begin html

<a name="pilight_switch"></a>
<h3>pilight_switch</h3>
<ul>

  pilight_switch represents a switch controled with\from pilight<br>
  You have to define the base device pilight_ctrl first.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br>
  Supported switches: <a href="http://wiki.pilight.org/doku.php/protocols#switches">http://wiki.pilight.org/doku.php/protocols#switches</a><br>     
  <br>
  <a name="pilight_switch_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_switch protocol id unit</code>    
    <br><br>

    Example:
    <ul>
      <code>define myctrl pilight_switch kaku_switch_old 0 0</code><br>
    </ul>
  </ul>
  <br>
  <a name="pilight_switch_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <b>on</b>
    </li>
    <li>
      <b>off</b>
    </li>
  </ul>
  <br>
  <a name="pilight_switch_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      state of the switch on or off
    </li>
  </ul>
  <br>
</ul>

=end html

=cut
