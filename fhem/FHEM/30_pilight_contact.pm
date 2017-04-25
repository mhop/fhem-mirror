##############################################
# $Id$
#
# Usage
# 
# define <name> pilight_contact <protocol> <id>  [unit]
#
# Changelog
#
# V 0.10 2016-11-13 - initial alpha version 
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;

sub pilight_contact_Parse($$);
sub pilight_contact_Define($$);

sub pilight_contact_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_contact_Define";
  $hash->{Match}    = "^PICONTACT";
  $hash->{ParseFn}  = "pilight_contact_Parse";
  $hash->{StateFn}  = "pilight_contact_State";
  $hash->{AttrList} = "IODev ".$readingFnAttributes;
}

#####################################
sub pilight_contact_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4) {
    my $msg = "wrong syntax: define <name> pilight_contact <protocol> <id> [unit]";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $me = $a[0];
  my $protocol = $a[2];
  my $id = $a[3];
  my $unit = undef;
  $unit = $a[4] if (@a == 5);

  $hash->{STATE} = "defined";
  $hash->{PROTOCOL} = $protocol;  
  $hash->{ID} = $id;  
  $hash->{UNIT} = $unit;

  #$attr{$me}{verbose} = 5;
  
  $modules{pilight_contact}{defptr}{$protocol}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub pilight_contact_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};
  
  #$hash->{STATE} wird nur ersetzt, wenn $hash->{STATE}  == ??? fhem.pl Z: 2469
  #machen wir es also selbst
  $hash->{STATE} = $val if ($name eq "state");
  return undef;
}


###########################################
sub pilight_contact_Parse($$)
{
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_contact_Parse ($backend): RCV -> $rmsg";
   
  my ($dev,$protocol,$id,$unit,$state,@args) = split(",",$rmsg);
  return () if($dev ne "PICONTACT");
  
  my $chash;
  foreach my $n (keys %{ $modules{pilight_contact}{defptr}{$protocol} }) { 
    my $lh = $modules{pilight_contact}{defptr}{$protocol}{$n};  
    next if ( !defined($lh->{ID}) );    
    if ($lh->{ID} eq $id) {
      if (defined($lh->{UNIT})) {
        next if ($lh->{UNIT} ne $unit);
      }
      $chash = $lh;
      last;
    }
  }
  
  return () if (!defined($chash->{NAME}));
  
  readingsBeginUpdate($chash);
  
  foreach my $arg (@args){
    my($feature,$value) = split(":",$arg);
    readingsBulkUpdate($chash,$feature,$value);
  }
    
  readingsBulkUpdate($chash,"state",$state);
  readingsEndUpdate($chash, 1);
  
  return $chash->{NAME};
}


1;

=pod
=item summary    pilight contact sensors  
=item summary_DE pilight Kontaktsensoren
=begin html

<a name="pilight_contact"></a>
<h3>pilight_contact</h3>
<ul>

  pilight_contact represents a contact sensor receiving data from pilight<br>
  You have to define the base device pilight_ctrl first.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br>
  <br>
  <a name="pilight_contact_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_contact protocol id [unit]</code>    
    <br><br>

    Example:
    <ul>
      <code>define myctrl pilight_contact arctech_contact 12836682 1</code><br>
    </ul>
  </ul>
  <br>
  <a name="pilight_contact_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      present the current state (open|closed)
    </li>
  </ul>
</ul>

=end html

=cut
