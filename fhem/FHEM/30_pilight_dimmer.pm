##############################################
#
# Usage
# 
# define <name> pilight_dimmer <protocol> <id> <unit> 
#
# Changelog
#
# V 0.10 2015-02-26 - initial beta version 
############################################## 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;

sub pilight_dimmer_Parse($$);
sub pilight_dimmer_Define($$);
sub pilight_dimmer_Fingerprint($$);

sub pilight_dimmer_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "pilight_dimmer_Define";
  $hash->{Match}    = "^SWITCH|^DIMMER";
  $hash->{ParseFn}  = "pilight_dimmer_Parse";
  $hash->{SetFn}    = "pilight_dimmer_Set";
  $hash->{AttrList} = "dimlevel_max ".$readingFnAttributes;
}

#####################################
sub pilight_dimmer_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 5) {
    my $msg = "wrong syntax: define <name> pilight_dimmer <protocol> <id> <unit>";
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
  
  $modules{pilight_dimmer}{defptr}{lc($id)}{$me} = $hash;
  AssignIoPort($hash);
  return undef;
}

###########################################
sub pilight_dimmer_Parse($$)
{
  
  my ($mhash, $rmsg, $rawdata) = @_;
  my $backend = $mhash->{NAME};

  Log3 $backend, 4, "pilight_dimmer_Parse: RCV -> $rmsg";
  
  my ($dev,$protocol,$id,$unit,$state,$dimlevel) = split(",",$rmsg);
  return () if($dev ne "SWITCH" && $dev ne "DIMMER");
  
  my $chash;
  foreach my $n (keys %{ $modules{pilight_dimmer}{defptr}{lc($id)} }) { 
    my $lh = $modules{pilight_dimmer}{defptr}{$id}{$n};
    next if ( !defined($lh->{UNIT}) );
    if ($lh->{ID} eq $id && $lh->{UNIT} eq $unit) {
      $chash = $lh;
      last;
    }
  }
  
  return () if (!defined($chash->{NAME}));
  
  readingsBeginUpdate($chash);
  readingsBulkUpdate($chash,"state",$state);
  readingsBulkUpdate($chash,"dimlevel",$dimlevel) if (defined($dimlevel));
  readingsEndUpdate($chash, 1); 
  
  return $chash->{NAME};
}

#####################################
sub pilight_dimmer_Set($$)
{  
  my ($hash, @a) = @_;
  my $me = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my $maxlevel =  $attr{$me}{dimlevel_max};
  $maxlevel = 15 if (!defined($maxlevel));
  return "Unknown argument ?, choose one of on off dimlevel:slider,0,1,$maxlevel" if($a[0] eq "?");
  
  my $msg = "$me,";
  
  if ($a[0] eq "dimlevel") {
    $msg .= "on,".$a[1]; 
  } else {
    $msg .= $a[0];
  }
  
  Log3 $me, 4, "$me(Set): $msg";
  
  IOWrite($hash, $msg);
  return undef;
}


1;

=pod
=begin html

<a name="pilight_dimmer"></a>
<h3>pilight_dimmer</h3>
<ul>

  pilight_dimmer represents a dimmmer controled with\from pilight<br>
  You have to define the base device pilight_ctrl first.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br>
  Supported dimmers: <a href="http://wiki.pilight.org/doku.php/protocols#dimmers">http://wiki.pilight.org/doku.php/protocols#dimmers</a><br>
  <br><br>

  <a name="pilight_dimmer_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_dimmer protocol id unit</code>    
    <br><br>

    Example:
    <ul>
      <code>define myctrl pilight_dimmer kaku_dimmer 13483668 0</code><br>
    </ul>
  </ul>
  <br>
  <a name="pilight_dimmer_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <b>on</b>
    </li>
    <li>
      <b>off</b>
    </li>
    <li>
      <b>dimlevel</b>
    </li>
  </ul>
  <br>
  <a name="pilight_dimmer_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      state<br>
      state of the dimmer on or off
    </li>
    <li>
      dimlevel<br>
      dimlevel of the dimmer 
    </li>
  </ul>
  <br>
  <a name="pilight_dimmer_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="dimlevel_max">dimlevel_max</a><br>
        Maximum of the dimlevel - default 15<br>
    </li>
   
  </ul>
  <br>
</ul>

=end html

=cut
