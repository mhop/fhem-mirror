
# $Id$
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

#=======================================================================================
sub CustomReadings_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}         = "CustomReadings_Define";
  $hash->{UndefFn}       = "CustomReadings_Undef";
  $hash->{SetFn}         = "CustomReadings_Set";
  $hash->{AttrList}      = "readingDefinitions " 
                         . "interval "
                         . "$readingFnAttributes";
}

#=======================================================================================
sub CustomReadings_Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};

  CustomReadings_OnTimer($hash);
  
  return undef;
}

#=======================================================================================
sub CustomReadings_OnTimer($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+ AttrVal( $name, "interval", 5), "CustomReadings_OnTimer", $hash, 0);
  
  CustomReadings_Read($hash);
}

#=======================================================================================
sub CustomReadings_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  # Get the readingDefinitions and remove all newlines from the attribute
  my $readingDefinitions = AttrVal( $name, "readingDefinitions", "");
  $readingDefinitions =~ s/\n//g;

  my @used = ("state");
  my $isCombined = 0;
  my @combinedOutput = ();
  my $hasErrors = 0;
  
  readingsBeginUpdate($hash);
  
  my @definitionList = split(",", $readingDefinitions);
  while (@definitionList) {
    my $param = shift(@definitionList);

    while ($param && $param =~ /{/ && $param !~ /}/ ) {
      my $next = shift(@definitionList);
      last if( !defined($next) );
      $param .= ",". $next;
    }
    
    my @definition = split(':', $param, 2);
    if ($definition[0] eq "COMBINED") {
      $isCombined = 1;
      my $cmdStr = $definition[1];
      my $cmdTemp = eval("$cmdStr");
      if (ref $cmdTemp eq 'ARRAY') {
        @combinedOutput = @{ $cmdTemp };
      } else {
        @combinedOutput = split(/^/, $cmdTemp);
      }
      Log 5, "Using combined mode for customReadings: $cmdStr";
      next;
    } 
    else {
      push(@used, $definition[0]);
    }    
    
    if($definition[1] ne "") {
      $isCombined = 0;
    }
    
    my $value;
    if ($isCombined) {
      $value = shift @combinedOutput; 
            
      if (!($value)) {  
        $value = 0;
        $hasErrors = 1;
       	Log 3, "customReadings: Warning for $name: combined command for " . $definition[0] . " returned nothing or not enough lines.";
      }
    } 
    else {
      $value = eval($definition[1]);
    }
    
    if(defined $value) {
      $value =~ s/^\s+|\s+$//g;
    }
    else {
      $value = "ERROR";
      $hasErrors = 1;
    }
    
    readingsBulkUpdate($hash, $definition[0], $value);
  }
  
  readingsBulkUpdate($hash, "state", $hasErrors ? "Errors" : "OK");

  readingsEndUpdate($hash, 1);

  foreach my $r (keys %{$hash->{READINGS}}) {
    if (not $r ~~ @used) {
      delete $hash->{READINGS}{$r};   
    }
  }
  
}

#=======================================================================================
sub CustomReadings_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash);
  
  return undef;
}

#=======================================================================================
sub CustomReadings_GetHTML ($) {
	my ($name) = @_;
  my $hash = $main::defs{$name};
  my $result = "";
  
  $result .= "<table>";
  my @sortedReadings = sort keys %{$hash->{READINGS}};
  foreach my $reading (@sortedReadings) {
    $result .= "<tr>";
    $result .= "<td>$reading:&nbsp;</td><td>" . ReadingsVal($name, $reading, "???") . "</td>";
    $result .= "</tr>";
  }
  $result .= "</table>";
  
	return $result;
}

#=======================================================================================
sub CustomReadings_Set($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);
  
  my $list = "update";
  return $list if( $cmd eq '?' || $cmd eq '');
  
  if ($cmd eq "update") {
    CustomReadings_Read($hash);
  }
  else {
    return "Unknown argument $cmd, choose one of ".$list;
  }
  
  return undef;
}


1;

=pod
=item summary    Allows to define own readings.
=item summary_DE Ermöglicht eingen readings.
=begin html

<a name="CustomReadings"></a>
<h3>CustomReadings</h3>

<ul>
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
attr myReadings group Readings<br>
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

<br><br>
<b>Optionally, to display the readings:</b><br>
define myReadingsDisplay weblink htmlCode {CustomReadings_GetHTML('myReadings')}<br>
attr myReadingsDisplay group Readings<br>
attr myReadingsDisplay room 0-Test<br>
  </code>

  <br>
  <u>Resulting readings:</u><br>
  <table>
    <colgroup width="250" span="3"></colgroup>
    <tr>
      <td>ac_powersupply_current</td>
      <td>0.236</td>
      <td>2014-08-09 15:40:21</td>
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
    
    Multiline output from commands, systemcall, scripts etc. can be use for  more than one reading with <br>
    the keyword <code>COMBINED</code> as reading (which wont appear itself) while its command output<br>
    will be put line by line in the following readings defined (so they don't need a function defined<br>
    after the colon (it would be ignored)).But the lines given must match the number and order of the<br>
    following readings.<br><br>
    
    COMBINED can be used together or lets say after or even in between normal expressions if the<br>
    number of lines of the output matches exactly.
    Example: <code>COMBINED:qx(cat /proc/sys/vm/dirty_background*),dirty_bytes:,dirty_ration:</code><br>
    Defines two readings (dirty_bytes and dirty_ratio) which will get set by the lines of those <br>
    two files the cat command will find in the kernel proc directory.<br>
    In some cases this can give an noticeable performance boost as the readings are filled up all at once.    
    </li>
  </ul><br>
</ul>


=end html
=cut
