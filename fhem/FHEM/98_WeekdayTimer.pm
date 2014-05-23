# $Id$
##############################################################################
#
#     98_WeekdayTimer.pm
#     written by Dietmar Ortmann
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;
use strict;
use warnings;
use POSIX;
########################################################################
sub WeekdayTimer_Initialize($)
{
  my ($hash) = @_;

  if(!$modules{Heating_Control}{LOADED} && -f "$attr{global}{modpath}/FHEM/98_Heating_Control.pm") {
    my $ret = CommandReload(undef, "98_Heating_Control");
    Log3 undef, 1, $ret if($ret);
  }

# Consumer
  $hash->{SetFn}   = "WeekdayTimer_Set";
  $hash->{AttrFn}  = "WeekdayTimer_Attr";  
  $hash->{DefFn}   = "WeekdayTimer_Define";
  $hash->{UndefFn} = "WeekdayTimer_Undef";
  $hash->{GetFn}   = "WeekdayTimer_Get";
  $hash->{UpdFn}   = "WeekdayTimer_Update";
  $hash->{AttrList}= "disable:0,1 ".
                        $readingFnAttributes;
}
################################################################################
sub WeekdayTimer_Set($@) {
  my ($hash, @a) = @_;
  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of enable/disable refresh" if($a[1] eq "?");
  
  Heating_Control_Set($@);
  
  return undef;
}
########################################################################
sub WeekdayTimer_Get($@) {
   return Heating_Control_Get($@);
}
########################################################################
sub WeekdayTimer_Define($$){
  my ($hash, $def) = @_;

  my $ret = Heating_Control_Define($hash, $def);
  $hash->{helper}{DESIRED_TEMP_READING} = "";
  return $ret;
}
########################################################################
sub WeekdayTimer_Undef($$){
  my ($hash, $arg) = @_;
  return Heating_Control_Undef($hash, $arg);
}
########################################################################
sub WeekdayTimer_UpdatePerlTime($) {
    my ($hash) = @_;
    Heating_Control_UpdatePerlTime($hash);
}
########################################################################
sub WeekdayTimer_Update($){
my ($hash) = @_;
  return Heating_Control_Update($hash);
}
########################################################################
sub WeekdayTimer_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  if( $attrName eq "disable" ) {
     my $hash = $defs{$name};
     readingsSingleUpdate ($hash,  "disabled",  $attrVal, 1);
  }
  return undef;
}
########################################################################
sub WeekdayTimer_SetAllParms() {  # {WeekdayTimer_SetAllParms()}

  foreach my $hc ( sort keys %{$modules{WeekdayTimer}{defptr}} ) {
     my $hash = $modules{WeekdayTimer}{defptr}{$hc};

     if($hash->{helper}{CONDITION}) {
        if (!(eval ($hash->{helper}{CONDITION}))) {
           readingsSingleUpdate ($hash,  "state",      "inactive", 1);
           next;
        }
     }
     my $myHash->{HASH}=$hash;
     WeekdayTimer_Update($myHash);
     Log3 undef, 3, "WeekdayTimer_Update() for $hash->{NAME} done!";
  }
  Log3 undef,  3, "WeekdayTimer_SetAllParms() done!";
}

1;

=pod
=begin html

<a name="WeekdayTimer"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>WeekdayTimer</h3>
<ul>
  <br>
  <a name="weekdayTimer_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WeekdayTimer &lt;device&gt; &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
    <br><br>

    to set a weekly profile for &lt;device&gt;<br><br>

    You can define different switchingtimes for every day.<br>
    The new parameter is sent to the &lt;device&gt; automatically with <br><br>

    <code>set &lt;device&gt; &lt;para&gt;</code><br><br>

    If you have defined a &lt;condition&gt; and this condition is false if the switchingtime has reached, no command will executed.<br>
    An other case is to define an own perl command with &lt;command&gt;.
    <p>
    The following parameter are defined:
    <ul><b>device</b><br>
      The device to switch at the given time.
    </ul>
    <p>
    <ul><b>profile</b><br>
      Define the weekly profile. All timings are separated by space. A switchingtime is defined by the following example:<br>
      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;</b></ul><br>
      <u>weekdays:</u> optional, if not set every day is used. Otherwise you can define a day as a number or as shortname.<br>
      <u>time:</u>define the time to switch, format: HH:MM(HH in 24 hour format).<br>
      <u>parameter:</u>the parameter to be set, using any text value like <b>on</b>, <b>off</b>, <b>dim30%</b>, <b>eco</b> or <b>comfort</b> - whatever your device understands.<br>
    </ul>
    <p>
    <ul><b>command</b><br>
      If no condition is set, all other is interpreted as a command. Perl-code is setting up
      by well-known Block with {}.<br>
      Note: if a command is defined only this command is executed. In case of executing
      a "set desired-temp" command, you must define it explicit.<br>
      The following parameter are replaced:<br>
        <ol>
          <li>@ => the device to switch</li>
          <li>% => the new parameter</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      if a condition is defined you must declared this with () and a valid perl-code.<br>
      The return value must be boolean.<br>
      The parameter @ and % will be interpreted.
    </ul>
    <p>
    <b>Example:</b>
    <ul>
        <code>define shutter WeekdayTimer bath 12345|05:20|up  12345|20:30|down</code><br>
        Mo-Fr are setting the shutter at 05:20 to <b>up</b>, and at 20:30 <b>down</b>.<p>

        <code>define heatingBath WeekdayTimer bath 07:00|16 Mo,Tu,Th-Fr|16:00|18.5 20:00|eco
          {fhem("set dummy on"); fhem("set @ desired-temp %");}</code><br>
        At the given times and weekdays only(!) the command will be executed.<p>

        <code>define dimmer WeekdayTimer livingRoom Sa-Su,We|07:00|dim30% Sa-Su,We|21:00|dim90% (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        The dimmer is only set to dimXX% if the dummy variable WeAreThere is "yes"(not a real live example).<p>

        If you want to have set all WeekdayTimer their current value (after a phase of exception),
        you can call the function <b> WeekdayTimer_SetAllParms ()</b>.
        This call can be automatically coupled to a dummy by notify:
        <code>define WDStatus2 notify Dummy:. * {WeekdayTimer_SetAllParms ()}</code>

    </ul>
  </ul>

  <a name="WeekdayTimerset"></a>
  <b>Set</b>

    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    <b>disable</b>               # disables the Weekday_Timer
    <b>enable</b>                # enables  the Weekday_Timer
    </pre>

    <b><font size="+1">Examples</font></b>:
    <ul>
      <code>set wd disable</code><br>
      <code>set wd enable</code><br>
    </ul>
  </ul>  

  <a name="WeekdayTimerget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="WeekdayTimerLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
  </ul><br>
</ul>


=end html

=cut
