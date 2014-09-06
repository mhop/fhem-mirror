
# $Id$
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

sub
CustomReadings_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}         = "CustomReadings_Define";
  $hash->{UndefFn}       = "CustomReadings_Undef";
  $hash->{AttrList}      = "readingDefinitions " 
                         . "interval "
                         . "$readingFnAttributes";
}

sub
CustomReadings_Define($$)
{
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  CustomReadings_read($hash);
  
  return undef;
}

sub CustomReadings_read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+ AttrVal( $name, "interval", 5), "CustomReadings_read", $hash, 0);
  
  # Get the readingDefinitions and remove all newlines from the attribute
  my $readingDefinitions = AttrVal( $name, "readingDefinitions", "");
  $readingDefinitions =~ s/\n//g;
    
  my @definitionList = split(',', $readingDefinitions);
  my @used = ("state");
  
  readingsBeginUpdate($hash);
  foreach (@definitionList) {
    my @definition = split(':', $_, 2);
    push(@used, $definition[0]);
    
    my $value = eval($definition[1]);
    if($value) {
      $value =~ s/^\s+|\s+$//g;
    }
    else {
      $value = "ERROR";
    }
    
    readingsBulkUpdate($hash, $definition[0], $value);
  }
  
  readingsEndUpdate($hash, 1);

  foreach my $r (keys %{$hash->{READINGS}}) {
    if (not $r ~~ @used   ) {
      delete $hash->{READINGS}{$r};   
    }
  }
  
}


sub
CustomReadings_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  
  return undef;
}


1;

=pod
=begin html

<a name="CustomReadings"></a>
<h3>CustomReadings</h3>

<ul>
  <tr><td>
  FHEM module to define own readings.
  <br><br>
  This module allows to define own readings. The readings can be defined in an attribute so that they can get changed without changing the code of the module.<br>
  To use this module you should have some perl and linux knowledge<br>
  The examples presuppose that you run FHEM on a linux machine like a Raspberry Pi or a Cubietruck.<br>
  Note: the "bullshit" definition is an example to show what happens if you define bullshit :-)<br><br>
  <u>Example (definition in fhem.cfg)</u>
  <br><code>
define myReadings CustomReadings<br>
attr myReadings room 0-Test<br>
attr myReadings interval 2<br>
attr myReadings readingDefinitions hdd_temperature:qx(hddtemp /dev/sda 2>&1),<br>
ac_powersupply_voltage:qx(cat /sys/class/power_supply/ac/voltage_now 2>&1) / 1000000,<br>
ac_powersupply_current:qx(cat /sys/class/power_supply/ac/current_now 2>&1) / 1000000,<br>
perl_version:$],<br>
timezone:qx(cat /etc/timezone 2>&1),<br>
kernel:qx(uname -r 2>&1),<br>
device_name:$hash->{NAME},<br>
bullshit: $hash->{bullshit},<br>
fhem_backup_folder_size:qx(du -ch /opt/fhem/backup | grep total | cut -d 't' -f1 2>&1)<br>

  <br>
  <u>Resulting readings:</u><br>
  <table>
    <colgroup width="250" span="3"></colgroup>
    <tr>
      <td>ac_powersupply_current</td>
      <td>0.236</td>
      <td>2014-08-09 15:40:21<td>
    </tr>
    <tr>
      <td>ac_powersupply_voltage</td>
      <td>5.028</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>bullshit</td>
      <td>ERROR</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>device_name</td>
      <td>myReadings</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>fhem_backup_folder_size</td>
      <td>20M</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>hdd_temperature</td>
      <td>/dev/sda:  TS128GSSD320: 47°C</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>kernel</td>
      <td>3.4.103-sun7i+</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>perl_version</td>
      <td>5.014002</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
    <tr>
      <td>timezone</td>
      <td>Europe/Berlin</td>
      <td>2014-08-09 15:40:21</td>
    </tr>
  </table>
  </code>

  <br>
  <a name="CustomReadings_Define"></a>
  <b>Define</b><br>
  define &lt;name&gt; CustomReadings<br>
  <br>
  
  <a name="CustomReadings_Readings"></a>
  <b>Readings</b><br>
  As defined
  <br><br>

  <a name="CustomReadings_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
    Refresh interval in seconds</li><br>
    <li>readingDefinitions<br>
    The definitions are separated by a comma. A definition consists of two parts, separated by a colon.<br>
    The first part is the name of the reading and the second part the function.<br>
    The function gets evaluated and must return a result.<br><br>
    Example: <code>kernel:qx(uname -r 2>&1)</code><br>
    Defines a reading with the name "kernel" and evaluates the linux function uname -r<br>
    
    </li>
  </ul><br>
</ul>


=end html
=cut
