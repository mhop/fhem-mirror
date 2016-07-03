##############################################
# $Id$
#
# Usage
# 
# define <name> pilight_smoke <protocol> <id> 
#
# Changelog
#
# V 0.10 2016-06-28 - initial alpha version 
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;

sub pilight_smoke_Parse($$);
sub pilight_smoke_Define($$);

sub pilight_smoke_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_smoke_Define";
  $hash->{Match}    = "^PISMOKE";
  $hash->{ParseFn}  = "pilight_smoke_Parse";
  $hash->{StateFn}  = "pilight_smoke_State";
  $hash->{AttrList} = "resetTime IODev ".$readingFnAttributes;
}

#####################################
sub pilight_smoke_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4) {
    my $msg = "wrong syntax: define <name> pilight_smoke <protocol> <id>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  my $protocol = $a[2];
  my $id = $a[3];

  $hash->{STATE} = "defined";
  $hash->{PROTOCOL} = lc($protocol);  
  $hash->{ID} = $id;  

  #$attr{$me}{verbose} = 5;
  
  $modules{pilight_smoke}{defptr}{lc($protocol)}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub pilight_smoke_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};
  
  #$hash->{STATE} wird nur ersetzt, wenn $hash->{STATE}  == ??? fhem.pl Z: 2469
  #machen wir es also selbst
  $hash->{STATE} = $val if ($name eq "state");
  return undef;
}

###########################################
sub pilight_smoke_resetState($)
{
  my $hash = shift;
  my $me = $hash->{NAME};
  
  RemoveInternalTimer($hash);
    
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","none");
  readingsEndUpdate($hash, 1);
}

###########################################
sub pilight_smoke_Parse($$)
{
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_smoke_Parse ($backend): RCV -> $rmsg";
  
  my ($dev,$protocol,$id,$state,@args) = split(",",$rmsg);
  return () if($dev ne "PISMOKE");
  
  my $chash;
  foreach my $n (keys %{ $modules{pilight_smoke}{defptr}{lc($protocol)} }) { 
    my $lh = $modules{pilight_smoke}{defptr}{$protocol}{$n};
    next if ( !defined($lh->{ID}) );
    if ($lh->{ID} eq $id) {
      $chash = $lh;
      last;
    }
  }
  
  return () if (!defined($chash->{NAME}));
  
  my $resetTime = AttrVal($chash->{NAME}, "resetTime",5);
  
  RemoveInternalTimer($chash);
    
  readingsBeginUpdate($chash);
  readingsBulkUpdate($chash,"state",$state);
  readingsEndUpdate($chash, 1);
  
  InternalTimer(gettimeofday()+$resetTime,"pilight_smoke_resetState", $chash, 0);
  
  return $chash->{NAME};
}


1;

=pod
=begin html

<a name="pilight_smoke"></a>
<h3>pilight_smoke</h3>
<ul>

  pilight_smoke represents a smoke sensor receiving data from pilight<br>
  You have to define the base device pilight_ctrl first.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br>
  <br>
  <a name="pilight_smoke_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_smoke protocol id</code>    
    <br><br>

    Example:
    <ul>
      <code>define myctrl pilight_smoke secudo_smoke_sensor 0</code><br>
    </ul>
  </ul>
  <br>
  <a name="pilight_smoke_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      present the current state (alarm|none)
    </li>
  </ul>
  <br>
  <a name="pilight_smoke_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="resetTime">resetTime</a><br>
      Time [sec] to reset the state to none. 
    </li>
  </ul>
</ul>

=end html

=cut
