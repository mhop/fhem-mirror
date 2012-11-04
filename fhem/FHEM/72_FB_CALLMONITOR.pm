##############################################
#
# Modul: FB_CALLMONITOR
#
# Connects to a FritzBox Fon via network.
#
# When a call is received or takes place it creates an event with further call informations.
#
# This module has no sets or gets as it is only used for event triggering.
#
# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub FB_CALLMONITOR_Read($);

sub
FB_CALLMONITOR_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{SetFn}   = "FB_CALLMONITOR_Set";
  $hash->{ReadFn}  = "FB_CALLMONITOR_Read";  
  $hash->{DefFn}   = "FB_CALLMONITOR_Define";
  $hash->{UndefFn} = "FB_CALLMONITOR_Undef";
  $hash->{AttrList}= "event-on-update-reading event-on-change-reading";

}

#####################################
sub
FB_CALLMONITOR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> FB_CALLMONITOR ip[:port]";
    Log 2, $msg;
    return $msg;
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $dev .= ":1012" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);


  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "FB_CALLMONITOR_DoInit");
  return $ret;
}


#####################################
sub
FB_CALLMONITOR_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  DevIo_CloseDev($hash); 
  return undef;
}



#####################################
# Nothing can be set
sub
FB_CALLMONITOR_Set($@)
{
  my ($hash, @a) = @_;


  return "Set command is not supported by this module";
}


#####################################
# No get commands possible, as we just receive the events from the FritzBox.
sub
FB_CALLMONITOR_ReadAnswer($$$)
{

return "Get command is not supported by this module";

}

#####################################
# Receives an event and creates several readings for event triggering
sub
FB_CALLMONITOR_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  my @array;
  my $data = "";
  $data .= $buf;

 
   @array = split(";", $data);
   readingsBeginUpdate($hash);
   readingsUpdate($hash, "event", lc($array[1]));
   readingsUpdate($hash, "external_number", $array[3]) if(not $array[3] eq "0" and $array[1] eq "RING");
   readingsUpdate($hash, "internal_number", $array[4]) if($array[1] eq "RING");
   readingsUpdate($hash, "external_number" , $array[5]) if($array[1] eq "CALL");
   readingsUpdate($hash, "internal_number", $array[4]) if($array[1] eq "CALL");
   readingsUpdate($hash, "used_connection", $array[5]) if($array[1] eq "RING");
   readingsUpdate($hash, "used_connection", $array[6]) if($array[1] eq "CALL");

 
   readingsEndUpdate($hash, 1);

}

sub
FB_CALLMONITOR_DoInit($)
{

# No Initialization needed
return undef;

}

1;

=pod
=begin html

<a name="FB_CALLMONITOR"></a>
<h3>FB_CALLMONITOR</h3>
<ul>
  <tr><td>
  The FB_CALLMONITOR module connects to a AVM FritzBox Fon and listens for telephone
  events (Receiving incoming call, Making a call)
  <br><br>
  In order to use this module with fhem you <b>must</b> enable the CallMonitor feature via 
  telephone shortcode.<br><br>
  <ul>
      <code>#96*5* - for activating<br>#96*4* - for deactivating</code>
  </ul>
  
  <br>
  Just dial the shortcode for activating on one of your phones, after 3 seconds just hang up. The feature is now activated.
  <br>
  After activating the CallMonitor-Support in your FritzBox, this module is able to 
  generate an event for each call.
  <br><br>
  This module work with any FritzBox Fon model.
  <br><br>
  
  <a name="FB_CALLMONITORdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FB_CALLMONITOR &lt;ip-address&gt;[:port]</code><br>
    <br>
    port is 1012 by default.
    <br>
  </ul>
  <br>

  <a name="FB_CALLMONITORset"></a>
  <b>Set</b>
  <ul>
  N/A 
  </ul>
  <br>

  <a name="FB_CALLMONITORget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>
  <br>

  <a name="FB_CALLMONITORattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
  </ul>
</ul>


=end html
=cut
