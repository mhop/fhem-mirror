# $Id$
################################################################################
#
#  Copyright (c) 2017 dev0
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################################

my $module_version = "1.12";

package main;

use strict;
use warnings;
use POSIX;
use Encode;

sub expandJSON_expand($$$$;$$);  # Forum #66761

sub expandJSON_Initialize($$) {
  my ($hash) = @_;
  $hash->{DefFn}    = "expandJSON_Define";
  $hash->{NotifyFn} = "expandJSON_Notify";
  $hash->{AttrFn}   = "expandJSON_Attr";
  $hash->{AttrList} = "addStateEvent:1,0 "
                    . "addReadingsPrefix:1,0 "
                    . "disable:1,0 "
                    . "disabledForIntervals "
                    . "do_not_notify:1,0";
}


sub expandJSON_Define(@) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $usg = "\nUse 'define <name> expandJSON <event regexp>"
          . " [<target reading regexp>]";
  return "Wrong syntax: $usg" if(int(@a) < 3);
  return "ERROR: Perl module JSON is not installed" 
    if (expandJSON_isPmInstalled($hash,"JSON"));

  my $name = $a[0];
  my $type = $a[1];

  # source regexp
  my $re   = $a[2];
  return "Bad regexp: starting with *" if($re =~ m/^\*/);
  eval { "test" =~ m/^$re$/ };
  return "Bad regexp $re: $@" if($@);

  $hash->{s_regexp} = $re;
  InternalTimer(gettimeofday(), sub(){notifyRegexpChanged($hash, $re);}, $hash);

  # dest regexp
  if (defined $a[3]) {
    $re  = $a[3];
    return "Bad regexp: starting with *" if($re =~ m/^\*/);
    eval { "test" =~ m/^$re$/ };
    return "Bad regexp $re: $@" if($@);
    $hash->{t_regexp} = $re;
  }
  else {
    $hash->{t_regexp} = ".*";
  }

  my $doTrigger = ($name !~ m/^$re$/);            # Forum #34516
  readingsSingleUpdate($hash, "state", "active", $doTrigger);
  $hash->{version} = $module_version;

  return undef;
}


sub expandJSON_Attr($$) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $ret;

  if ($cmd eq "set" && !defined $aVal) {
    $ret = "not empty"
  }

  elsif ($aName eq "addReadingsPrefix") {
    $cmd eq "set" 
      ? $aVal =~ m/^[01]$/ ? ($hash->{helper}{$aName} = $aVal) : ($ret = "0|1") 
      : delete $hash->{helper}{$aName}
  }

  elsif ($aName eq "do_not_notify") {
    $ret = "0|1" if $cmd eq "set" && $aVal !~ m/^[01]$/;
  }

  elsif ($aName eq "disable") {
    if  ($cmd eq "set") {
      if ($aVal !~ m/^[01]$/) { $ret = "0|1" }
      else { readingsSingleUpdate($hash, "state", $aVal?"disabled":"active", 1) }
    }
    elsif ($cmd eq "del") { readingsSingleUpdate($hash, "state", "active", 1) }
  }
  
  if ($ret) {
    my $v = defined $aVal ? $aVal : "";
    my $msg = "$type: attr $name $aName $v: value must be: ";
    Log3 $name, 2, $msg.$ret;
    return $msg.$ret;
  }

  return undef;
}


sub expandJSON_Notify($$) {
  my ($hash, $dhash) = @_;
  my $name = $hash->{NAME};
  return "" if(IsDisabled($name));

  my $events = deviceEvents($dhash, AttrVal($name, "addStateEvent", 0));
  return if( !grep { m/{.*}\s*$/s } @{ $events } ); #there is no JSON content

  for (my $i = 0; $i < int(@{$events}); $i++) {
    my $event = $events->[$i];
    $event = "" if(!defined($event));

    my $re = $hash->{s_regexp};
    my $devName = $dhash->{NAME};
    my $found = ($devName =~ m/^$re$/ || "$devName:$event" =~ m/^$re$/s);
    if ($found) {
      my $type = $hash->{TYPE};
      Log3 $name, 5, "$type $name: Found $devName:$event";

      my ($reading,$value) = $event =~ m/^\s*{.*}\s*$/s 
        ? ("state", $event)
        : split(": ", $event, 2);

      $hash->{STATE} = $dhash->{NTFY_TRIGGERTIME};

      if ($value !~ m/^\s*{.*}\s*$/s) { # eg. state with an invalid json
        Log3 $name, 5, "$type $name: Invalid JSON: $value";
        return;
      }

      Log3 $name, 5, "$type $name: Yield decode: $hash | $devName | $reading "
                   . "| $value";

      InternalTimer(
        gettimeofday(), 
        sub(){ expandJSON_decode($hash,$devName,$reading,$value) },
        $hash);
    }
  }

  return undef;
}


sub expandJSON_decode($$$$) {
  my ($p) = @_;
  my ($hash,$dname,$dreading,$dvalue) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  my $dhash = $defs{$dname};
  my $h;
  eval { $h = decode_json(encode_utf8($dvalue)); 1; };
  if ( $@ ) {
    Log3 $name, 2, "$type $name: Bad JSON: $dname $dreading: $dvalue";
    Log3 $name, 2, "$type $name: $@";
    return undef;
  }

  my $sPrefix = $hash->{helper}{addReadingsPrefix} ? $dreading."_" : "";
  readingsBeginUpdate($dhash);
  expandJSON_expand($hash,$dhash,$sPrefix,$h);
  readingsEndUpdate($dhash, AttrVal($name,"do_not_notify",0) ? 0 : 1);

  return undef;
}


sub expandJSON_expand($$$$;$$) {
  # thanx to bgewehr for the root position of this recursive snippet
  # https://github.com/bgewehr/fhem
  my ($hash,$dhash,$sPrefix,$ref,$prefix,$suffix) = @_;
  $prefix = "" if( !$prefix );
  $suffix = "" if( !$suffix );
  $suffix = "_$suffix" if( $suffix );

  if( ref( $ref ) eq "ARRAY" ) {
    while( my ($key,$value) = each @{ $ref } ) {
      expandJSON_expand($hash,$dhash,$sPrefix,$value,
                        $prefix.sprintf("%02i",$key+1)."_");
    }
  }
  elsif( ref( $ref ) eq "HASH" ) {
    while( my ($key,$value) = each %{ $ref } ) {
      if( ref( $value ) ) {
        expandJSON_expand($hash,$dhash,$sPrefix,$value,$prefix.$key.$suffix."_");
      }
      else {
        # replace illegal characters in reading names
        (my $reading = $sPrefix.$prefix.$key.$suffix) =~ s/[^A-Za-z\d_\.\-\/]/_/g;
        readingsBulkUpdate($dhash, $reading, $value) 
          if $reading =~ m/^$hash->{t_regexp}$/;
      }
    }
  }
  elsif( ref( $ref ) eq "JSON::PP::Boolean" ) { # Forum #82734
    (my $reading = $sPrefix.$prefix) =~ s/[^A-Za-z\d_\.\-\/]/_/g;
    $reading = substr($reading, 0, -1); #remove tailing _
    readingsBulkUpdate($dhash, $reading, $ref ? 1 : 0) 
      if $reading =~ m/^$hash->{t_regexp}$/;
  }
}


sub expandJSON_isPmInstalled($$)
{
  my ($hash,$pm) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  if (not eval "use $pm;1") 
  {
    Log3 $name, 1, "$type $name: perl modul missing: $pm. Install it, please.";
    $hash->{MISSING_MODULES} .= "$pm ";
    return "failed: $pm";
  }
  
  return undef;
}


1;


=pod
=item helper
=item summary Expand a JSON string from a reading into individual readings
=item summary_DE Expandiert eine JSON Zeichenkette in individuelle Readings
=begin html

<a name="expandJSON"></a>
<h3>expandJSON</h3>

<ul>
  <p>Expand a JSON string from a reading into individual readings</p>

  <ul>
    <li>Requirement: perl module JSON<br>
      Use "cpan install JSON" or operating system's package manager to install
      Perl JSON Modul. Depending on your os the required package is named: 
      libjson-perl or perl-JSON.
    </li>
  </ul><br>
  
  <a name="expandJSONdefine"></a>
  <b>Define</b><br><br>
  
  <ul>
    <code>define &lt;name&gt; expandJSON &lt;source_regex&gt; 
      [&lt;target_regex&gt;]</code><br><br>

    <li>
      <a name="">&lt;name&gt;</a><br>
      A name of your choice.</li><br>

    <li>
      <a name="">&lt;source_regex&gt;</a><br>
      Regexp that must match your devices, readings and values that contain
      the JSON strings. Regexp syntax is the same as used by notify and must not
      contain spaces.<br>
      </li><br>
      
    <li>
      <a name="">&lt;target_regex&gt;</a><br>
      Optional: This regexp is used to determine whether the target reading is
      converted or not at all. If not set then all readings will be used. If set
      then only matching readings will be used. Regexp syntax is the same as
      used by notify and must not contain spaces.<br>
      </li><br>

    <li>
      Examples:<br>
      <br>
      <u>Source reading:</u><br>
      <code>
        device:{.*} #state without attribute addStateEvent<br>
        device:state:.{.*} #state with attribute addStateEvent<br>
        device:reading:.{.*}<br>
        Sonoff.*:ENERGY.*:.{.*}<br>
        .*wifiIOT.*:.*sensor.*:.{.*}<br>
        (?i)dev.*:(sensor1|sensor2|teleme.*):.{.*}<br>
        (devX:{.*}|devY.*:jsonY:.{.*Wifi.*{.*SSID.*}.*})
      </code><br>
      <br>

      <u>Target reading:</u><br>
      <code>.*power.*</code><br>
      <code>(Power|Current|Voltage|.*day)</code><br><br>

      <u>Complete definitions:</u><br>
      <code>define ej1 expandJSON device:sourceReading:.{.*} targetReading
      </code><br>
      <code>define ej2 expandJSON Sonoff.*:ENERGY.*:.{.*} (Power|.*day)
      </code><br>
      <code>define ej3 expandJSON (?i).*_sensordev_.*:.*:.{.*}
      </code><br><br>
   
    </li><br>
  </ul>

  <a name="expandJSONset"></a>
  <b>Set</b><br><br>
  <ul>
    N/A<br><br>
  </ul>
  
  <a name="expandJSONget"></a>
  <b>Get</b><br><br>
  <ul>
    N/A<br><br>
  </ul>
  
  <a name="expandJSON_attr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a name="expandJSON_attr_addReadingsPrefix">addReadingsPrefix</a><br>
      Add source reading as prefix to new generated readings. Useful if you have
      more than one reading with a JSON string that should be converted.
    </li><br>

    <li><a name="expandJSON_attr_disable">disable</a><br>
      Used to disable this device.
    </li><br>
    
    <li><a name="expandJSON_attr_do_not_notify">do_not_notify</a><br>
      Do not generate events for converted readings at all. Think twice before
      using this attribute. In most cases, it is more appropriate to use 
      event-on-change-reading in target devices.
    </li><br>

    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#addStateEvent">addStateEvent</a></li>
  </ul>
</ul>

=end html
=cut
