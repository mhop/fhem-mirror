# Id ##########################################################################
# $Id$

# copyright ###################################################################
#
# 74_Nmap.pm
#
# Copyright by igami
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# FHEM is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FHEM.  If not, see <http://www.gnu.org/licenses/>.

# packages ####################################################################
package main;
  use strict;
  use warnings;

  use Blocking;

# forward declarations ########################################################
sub Nmap_Initialize($);

sub Nmap_Define($$);
sub Nmap_Undefine($$);
sub Nmap_Set($@);
sub Nmap_Attr(@);

sub Nmap_statusRequest($);
sub Nmap_blocking_statusRequest($);
sub Nmap_done($);
sub Nmap_aborted($);

sub Nmap_deleteOldReadings($$);
sub Nmap_updateUptime($$;$);

# initialize ##################################################################
sub Nmap_Initialize($) {
  my ($hash) = @_;
  my $TYPE = "Nmap";

  $hash->{DefFn}    = $TYPE."_Define";
  $hash->{UndefFn}  = $TYPE."_Undefine";
  $hash->{SetFn}    = $TYPE."_Set";
  $hash->{AttrFn}   = $TYPE."_Attr";

  $hash->{AttrList} =
      "absenceThreshold "
    . "args "
    . "deleteOldReadings "
    . "devAlias:textField-long "
    . "disable:1,0 "
    . "excludeHosts "
    . "interval "
    . "keepReadings:1,0 "
    . "leadingZeros:1,0 "
    . "metaReading:alias,hostname,ip,macAddress "
    . "path "
    . "sudo:1,0 "
    . $readingFnAttributes
  ;
}

# regular Fn ##################################################################
sub Nmap_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, $targets) = split(/[\s]+/, $def, 3);
  my $rc = eval{
    require Nmap::Parser;
    Nmap::Parser->import();
    1;
  };

  return(
      "Error loading Nmap::Parser. Maybe this module is not installed? "
    . "\nUnder debian (based) system it can be installed using "
    . "\n\"apt-get install libnmap-parser-perl\""
  ) unless($rc);
  return("Usage: define <name> $TYPE <target specification>") if(!$targets);

  my $interval = AttrVal($SELF, "interval", 900);
  $interval = 900 if(!looks_like_number($interval));
  $interval = 30 if($interval < 30);

  $hash->{ARGS} = AttrVal($SELF, "args", "-sn");
  $hash->{INTERVAL} = $interval;
  $hash->{PATH} = AttrVal($SELF, "path", "/usr/bin/nmap");

  readingsSingleUpdate($hash, "state", "Initialized", 1);

  RemoveInternalTimer($hash);
  InternalTimer(
    gettimeofday() + $hash->{INTERVAL}, "Nmap_statusRequest", $hash
  );

  return;
}

sub Nmap_Undefine($$) {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID})
    if(defined($hash->{helper}{RUNNING_PID}));

  return;
}

sub Nmap_Set($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return "\"set $TYPE\" needs at least one argument" if(@a < 2);

  my $SELF = shift @a;
	my $argument = shift @a;
  my $value = join(" ", @a) if (@a);
  my %Nmap_sets = (
    "clear"             => "clear:readings",
    "deleteOldReadings" => "deleteOldReadings",
    "interrupt"         => "interrupt:noArg",
    "statusRequest"     => "statusRequest:noArg"
  );

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_Set");

  return(
      "Unknown argument $argument, choose one of "
    . join(" ", values %Nmap_sets)
  ) if(!exists($Nmap_sets{$argument}));

  if($argument eq "clear" && $value eq "readings"){
    foreach (keys %{$hash->{READINGS}}) {
      delete $hash->{READINGS}->{$_} if($_ ne "state");
    }
  }
  elsif($argument eq "deleteOldReadings" && $value){
    my $ret = Nmap_deleteOldReadings($hash, $value);

    return($ret) if($ret);

    readingsSingleUpdate($hash, "state", "deleteOldReadings $value", 1);
  }
  elsif(!IsDisabled($SELF)){
    if($argument eq "interrupt"){
      BlockingKill($hash->{helper}{RUNNING_PID})
        if(defined($hash->{helper}{RUNNING_PID}));

      Nmap_aborted($hash);

      RemoveInternalTimer($hash);
      InternalTimer(
        gettimeofday() + $hash->{INTERVAL}, "Nmap_statusRequest", $hash
      );
    }
    elsif($argument eq "statusRequest"){
      Nmap_statusRequest($hash);
    }
  }

  return;
}

sub Nmap_Attr(@) {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my $hash = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_Attr");

  if($attribute eq "args"){
    $hash->{ARGS} = $cmd eq "set" ? $value : "-sn";
  }
  elsif(
       $attribute eq "devAlias"
    && $cmd eq "set"
  ){
    return(
        "$SELF: Value \"$value\" is not allowed for devAlias!\n"
      . "Must be \"&lt;ID>:<ALIAS> &lt;ID2>:<ALIAS2> ...\", "
      . "e.g. 123abc:MyAndroid\n"
      . "Only these characters are allowed: [alphanumeric - _ .]"
    )if($value !~ /^([\w\.\-]+:[\w\.\-]+\s*)+$/s);
  }
  elsif($attribute eq "disable"){
    if($value && $value == 1){
      BlockingKill($hash->{helper}{RUNNING_PID})
        if(defined($hash->{helper}{RUNNING_PID}));
      RemoveInternalTimer($hash);
      readingsSingleUpdate($hash, "state", "disabled", 1);
    }
    elsif($cmd eq "del" || !$value){
      InternalTimer(
        gettimeofday() + $hash->{INTERVAL}, "Nmap_statusRequest", $hash
      );
      readingsSingleUpdate($hash, "state", "Initialized", 1);
    }
  }
  elsif($attribute eq "leadingZeros"){
    foreach (keys %{$hash->{READINGS}}){
      my $newkey = $_;
      $newkey =~
        s/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/sprintf('%03d',$1).".".sprintf('%03d',$2).".".sprintf('%03d',$3).".".sprintf('%03d',$4)/e
        if($value and $value == 1);
      $newkey =~
        s/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/sprintf('%00d',$1).".".sprintf('%00d',$2).".".sprintf('%00d',$3).".".sprintf('%00d',$4)/e
        if($cmd eq "del" or !$value);
      $hash->{READINGS}{$newkey} = delete $hash->{READINGS}{$_};
    }

    my $knownHosts = ReadingsVal($SELF, ".knownHosts", "");
    $knownHosts =~
      s/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/sprintf('%03d',$1).".".sprintf('%03d',$2).".".sprintf('%03d',$3).".".sprintf('%03d',$4)/ge
      if($value and $value == 1);
    $knownHosts =~
      s/([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/sprintf('%00d',$1).".".sprintf('%00d',$2).".".sprintf('%00d',$3).".".sprintf('%00d',$4)/ge
      if($cmd eq "del" or !$value);

    readingsSingleUpdate($hash, ".knownHosts", $knownHosts, 0);
  }
  elsif($attribute eq "path"){
    $hash->{PATH} = $cmd eq "set" ? $value : "/usr/bin/nmap";
  }

  return if(IsDisabled($SELF));

  if($attribute eq "interval"){
    my $interval = $cmd eq "set" ? $value : 900;
    $interval = 900 if(!looks_like_number($interval));
    $interval = 30 if($interval < 30);

    $hash->{INTERVAL} = $interval;

    RemoveInternalTimer($hash);
    InternalTimer(
      gettimeofday() + $hash->{INTERVAL}, "Nmap_statusRequest", $hash
    );
  }

  return;
}

# blocking Fn #################################################################
sub Nmap_statusRequest($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $interval = $hash->{INTERVAL};
  my $timeout = $interval - 1;
  my $path = $hash->{PATH};

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_statusRequest");

  BlockingKill($hash->{helper}{RUNNING_PID})
    if(defined($hash->{helper}{RUNNING_PID}));
  RemoveInternalTimer($hash);

  return if(IsDisabled($SELF));

  InternalTimer(
    gettimeofday() + $interval, "Nmap_statusRequest", $hash
  );

  unless(-X $path){
    readingsSingleUpdate($hash, "state", "aborted", 1);
    Log3(
        $SELF, 1, "$TYPE ($SELF) - "
      . "please check if Nmap ist installed and available at path $path"
    );

    return;
  }

  if(
       AttrVal($SELF, "sudo", 0) == 1
    && qx(sudo -n $path -V 2>&1 > /dev/null)
  ){
    readingsSingleUpdate($hash, "state", "aborted", 1);
    Log3($SELF, 1, "$TYPE ($SELF) - sudo password required");

    return;
  }

  readingsSingleUpdate($hash, "state", "running", 1);
  Log3($SELF, 3, "$TYPE ($SELF) - starting network scan");
  Log3($SELF, 5, "$TYPE ($SELF) - BlockingCall Nmap_blocking_statusRequest");

  $hash->{helper}{RUNNING_PID} = BlockingCall(
      "Nmap_blocking_statusRequest", $SELF, "Nmap_done"
    , $timeout, "Nmap_aborted", $hash
  ) unless(exists($hash->{helper}{RUNNING_PID}));

  return;
}

sub Nmap_blocking_statusRequest($) {
  my ($SELF) = @_;
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};
  my @ret = $SELF;
  my $NP = new Nmap::Parser;
  my $path =
      (AttrVal($SELF, "sudo", 0) == 1 ? "sudo " : "")
    . $hash->{PATH}
  ;
  my $excludeHosts = AttrVal($SELF, "excludeHosts", undef);
  my $args = $hash->{ARGS};
  $args .= " --exclude $excludeHosts" if($excludeHosts);
  my $STDERR = "";

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_blocking_statusRequest");

  close STDERR;
  open(STDERR, ">", \$STDERR);

  $NP->parsescan($path, $args, $hash->{DEF});

  close (STDERR);

  Log3($SELF, 4, "$TYPE ($SELF) - $_")
    foreach(split( "\n", $STDERR));

  my $NPS = $NP->get_session();

  push(@ret, $NPS->nmap_version());
  push(@ret, int($NP->all_hosts()));
  push(@ret, $NPS->finish_time() - $NPS->start_time());

  my @hostsUp = $NP->all_hosts("up");

  foreach (@hostsUp){
    my $hostname = $_->hostname() ? $_->hostname() : $_->ipv4_addr();
    my $macAddress = $_->mac_addr() ? $_->mac_addr() : "Unknown";
    my $macVendor = $_->mac_vendor() ? $_->mac_vendor() : "Unknown";

    push(@ret, $_->ipv4_addr()."|$hostname|$macAddress|$macVendor");
  }

  return (join("||", @ret));
}

sub Nmap_done($) {
  my ($string) = @_;

  return unless(defined($string));

  my ($SELF, $NmapVersion, $hostsScanned, $scanDuration, @hostsUp) =
    split("\\|\\|", $string);
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};
  my $devAliases = AttrVal($SELF, "devAlias", undef);
  my %knownHosts = map{$_, 0} split(",", ReadingsVal($SELF, ".knownHosts", ""));
  my $metaReadingAttrVal = AttrVal($SELF, "metaReading", "ip");

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_done");

  delete($hash->{helper}{RUNNING_PID});

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "NmapVersion", $NmapVersion);
  readingsBulkUpdate($hash, "hostsScanned", $hostsScanned);
  readingsBulkUpdate($hash, "hostsUp", int(@hostsUp));
  readingsBulkUpdate($hash, "scanDuration", $scanDuration);

  foreach (@hostsUp){
    my ($ip, $hostname, $macAddress, $macVendor) = split("\\|", $_);
    my ($oldMetaReading, $metaReading);
    my $alias = $hostname;

    if(
         $devAliases && $devAliases =~ /$macAddress:(.+?)(\s|$)/
      || $devAliases && $devAliases =~ /$hostname:(.+?)(\s|$)/
      || $devAliases && $devAliases =~ /$ip:(.+?)(\s|$)/
    ){
      $alias = $1;
    }

    if($metaReadingAttrVal eq "ip"){
      $metaReading = $ip;
    }
    elsif($metaReadingAttrVal eq "macAddress"){
      $metaReading = $macAddress ne "Unknown" ? $macAddress : $ip;
    }
    elsif($metaReadingAttrVal eq "alias"){
      $metaReading = $alias;
    }
    elsif($metaReadingAttrVal eq "hostname"){
      $metaReading = $hostname;
    }

    $metaReading =~ s/([0-9]+)/sprintf('%03d',$1)/ge
      if(AttrVal($SELF, "leadingZeros", 0) == 1 && $metaReading eq $ip);
    $metaReading =~ s/:/-/g;
    $knownHosts{$metaReading} = 1;

    if($macAddress ne "Unknown"){
      foreach (keys %knownHosts){
        $oldMetaReading = $_
          if(ReadingsVal($SELF, $_."_macAddress", "") eq $macAddress);

        next unless($oldMetaReading);

        last;
      }
      if(
           $oldMetaReading
        && ReadingsVal($SELF, $oldMetaReading."_ip", "") ne $ip
      ){
        Log3($SELF, 4, "$TYPE ($SELF) - new IP: $hostname ($ip)");

        DoTrigger($SELF, "new IP: $hostname ($ip)");
      }
    }

    unless($hash->{READINGS}{$metaReading."_hostname"} || $oldMetaReading){
      Log3($SELF, 4, "$TYPE ($SELF) - new host: $hostname ($ip)");

      DoTrigger($SELF, "new host: $hostname ($ip)");
    }

    if(
         $oldMetaReading && $oldMetaReading ne $metaReading
      && AttrVal($SELF, "keepReadings", 0) == 0
    ){
      delete $knownHosts{$oldMetaReading};
      CommandDeleteReading(undef, "$SELF $oldMetaReading.*");

      Log3($SELF, 4, "$TYPE ($SELF) - delete old host: $oldMetaReading");
    }

    readingsBulkUpdate($hash, $metaReading."_alias", $alias);
    readingsBulkUpdate($hash, $metaReading."_hostname", $hostname);
    readingsBulkUpdate($hash, $metaReading."_ip", $ip);
    readingsBulkUpdate($hash, $metaReading."_lastSeen", TimeNow());
    readingsBulkUpdate($hash, $metaReading."_macAddress", $macAddress)
      if($macAddress ne "Unknown");
    readingsBulkUpdate($hash, $metaReading."_macVendor", $macVendor)
      if($macVendor ne "Unknown");
    readingsBulkUpdate($hash, $metaReading."_state", "present");

    Nmap_updateUptime($hash, $metaReading);
  }

  foreach (keys %knownHosts){
    next if(
         $knownHosts{$_} == 1
      || ReadingsVal($SELF, $_."_state", "present") eq "absent"
    );

    my $absenceThreshold = ReadingsVal($SELF, ".".$_."_absenceThreshold", 1);

    if($absenceThreshold >= AttrVal($SELF, "absenceThreshold", 1)){
      delete $hash->{READINGS}{".".$_."_absenceThreshold"};

      readingsBulkUpdate($hash, $_."_state", "absent");

      Nmap_updateUptime($hash, $_, 0);
    }
    else{
      $absenceThreshold ++;

      readingsBulkUpdate($hash, ".".$_."_absenceThreshold", $absenceThreshold);
      readingsBulkUpdate($hash, $_."_state", "present");

      Nmap_updateUptime($hash, $_);
    }
  }

  readingsBulkUpdate($hash, ".knownHosts", join(",", sort(keys %knownHosts)));
  readingsBulkUpdate($hash, "knownHosts", int(keys %knownHosts));
  readingsBulkUpdate($hash, "state", "done");
  readingsEndUpdate($hash, 1);

  my $deleteOldReadings = AttrVal($SELF, "deleteOldReadings", 0);
  Nmap_deleteOldReadings($hash, $deleteOldReadings)
    if($deleteOldReadings ne "0");

  Log3($SELF, 3, "$TYPE ($SELF) - network scan done");

  return;
}

sub Nmap_aborted($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  delete($hash->{helper}{RUNNING_PID});

  Log3($SELF, 2, "$TYPE ($SELF) - network scan aborted");
  readingsSingleUpdate($hash, "state", "aborted", 1);

  return;
}

# module Fn ###################################################################
sub Nmap_deleteOldReadings($$) {
  my ($hash, $value) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  $value = eval($value);

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_deleteOldReadings");

  unless(looks_like_number($value)){
    my $ret = "no numeric value given for deleteOldReadings";

    Log3($SELF, 2, "$TYPE ($SELF) - $ret");

    return($ret);
  }

  my %knownHosts =
    map{$_, 0} split(",", ReadingsVal($SELF, ".knownHosts", ""));

    foreach (keys %knownHosts) {
      if(ReadingsAge($SELF, $_."_lastSeen", 0) >= $value){
        CommandDeleteReading(undef, "$SELF $_.*");
        delete $knownHosts{$_};
      }
    }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, ".knownHosts", join(",", sort(keys %knownHosts)));
  readingsBulkUpdate($hash, "knownHosts", int(keys %knownHosts));
  readingsEndUpdate($hash, 1);

  Log3($SELF, 4, "$TYPE ($SELF) - delete Readings older than $value seconds");

  return;
}

sub Nmap_updateUptime($$;$) {
  my ($hash, $metaReading, $uptime) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering Nmap_updateUptime");

  $uptime = (
      ReadingsVal($SELF, $metaReading."_uptime", 0)
    + ReadingsAge($SELF, $metaReading."_uptime", 0)
  ) unless(defined($uptime));

  my $s = $uptime;
  my $d = int($s / 86400);
  $s -= $d * 86400;
  my $h = int($s / 3600);
  $s -= $h * 3600;
  my $m = int($s / 60);
  $s -= $m * 60;

  my $uptimeText = sprintf(
      "%d days, %02d hours, %02d minutes, %02d seconds"
    , $d, $h, $m, $s
  );

  readingsBulkUpdate($hash, $metaReading."_uptime", $uptime);
  readingsBulkUpdate($hash, $metaReading."_uptimeText", $uptimeText);

  return;
}

1;

# commandref ##################################################################
=pod
=item device
=item summary    Interpret of an Nmap network scans
=item summary_DE Auswertung eines Nmap Netzwerkscans

=begin html

<a name="Nmap"></a>
<h3>Nmap</h3>
( en | <a href="commandref_DE.html#Nmap"><u>de</u></a> )
<div>
  <ul>
    Nmap is the FHEM module to perform a network scan with Nmap and to display information about the available network devices.<br>
    If a new device is detected, an event
    <code>"&lt;name&gt; new host: &lt;hostname&gt; (&lt;IPv4&gt;)"</code>
    is generated.<br>
    If a device with a known MAC address has been given a new IP, an event
    <code>"&lt;name&gt; new IP: &lt;hostname&gt; (&lt;IPv4&gt;)"</code>
    is generated.<br>
    <br>
    Prerequisites:
    <ul>
      The "Nmap" program and the Perl module "Nmap::Parser" are required.<br>
      Under Debian (based) system, these can be installed using
      <code>"apt-get install nmap libnmap-parser-perl"</code>
      .
    </ul>
    <br>
    <a name="Nmapdefine"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; Nmap &lt;target specification&gt;</code><br>
      In the &lt;target specification&gt; are all target hosts, which are to be
      scanned.<br>
      The simplest case is the description of an IP destination address or a
      target host name for scanning.<br>
      To scan an entire network of neighboring hosts, Nmap supports CIDR-style
      addresses. Numbits can be appended to an IPv4 address or hostname, and
      Nmap will scan all IP addresses where the first numbits match those of
      the given IP or host name. For example, 192.168.10.0/24 would scan the
      256 hosts between 192.168.10.0 and 192.168.10.255. 192.168.10.40/24 would
      scan exactly the same targets.<br>
      See
      <a href="https://nmap.org/man/de/man-target-specification.html">
        <u>Nmap Manpage (Specifying Destinations)</u>
      </a>.
    </ul><br>
    <a name="Nmapset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>clear readings</code><br>
        Deletes all readings except "state".
      </li>
      <li>
        <code>deleteOldReadings &lt;s&gt;</code><br>
        Deletes all readings older than &lt;s&gt; seconds.
      </li>
      <li>
        <code>interrupt</code><br>
        Cancels a running scan.
      </li>
      <li>
        <code>statusRequest</code><br>
        Starts a network scan.
      </li>
    </ul><br>
    <a name="Nmapreadings"></a>
    <b>Readings</b><br>
    <ul>
      General Readings:
      <ul>
        <li>
          <code>NmapVersion</code><br>
          The version number of the installed Nmap program.
        </li>
        <li>
          <code>hostsScanned</code><br>
          The number of scanned addresses.
        </li>
        <li>
          <code>hostsUp</code><br>
          The number of available network devices.
        </li>
        <li>
          <code>knownHosts</code><br>
          The number of known network devices.
        </li>
        <li>
          <code>scanDuration</code><br>
          The scan time in seconds.
        </li>
        <li>
          <code>state</code><br>
          <ul>
            <li>
              <code>Initialized</code><br>
              Nmap has been defined or enabled.
            </li>
            <li>
              <code>running</code><br>
              A network scan is running.
            </li>
            <li>
              <code>done</code><br>
              Network scan completed successfully.
            </li>
            <li>
              <code>aborted</code><br>
              The network scan was aborted due to a timeout or by the user.
            </li>
            <li>
              <code>disabled</code><br>
              Nmap has been disabled.
            </li>
          </ul>
        </li>
      </ul>
      <br>
      Host-specific readings:
      <ul>
        <li>
          <code>&lt;metaReading&gt;_alias</code><br>
          Alias ​​which is specified under the attribute "devAlias" for the
          network device. If no alias is specified, the hostname is displayed.
        </li>
        <li>
          <code>&lt;metaReading&gt;_hostname</code><br>
          Hostname of the network device. If this can not be determined, the IPv4
          address is displayed.
        </li>
        <li>
          <code>&lt;metaReading&gt;_ip</code><br>
          IPv4 address of the network device.
        </li>
        <li>
          <code>&lt;metaReading&gt;_lastSeen</code><br>
          The time at which the network device was last seen as.
        </li>
        <li>
          <code>&lt;metaReading&gt;_macAddress</code><br>
          MAC address of the network device. This can only be determined if the
          scan is executed with root privileges.
        </li>
        <li>
          <code>&lt;metaReading&gt;_macVendor</code><br>
          Probable manufacturer of the network device. This can only be
          determined if the scan is executed with root privileges.
        </li>
        <li>
          <code>&lt;metaReading&gt;_state</code><br>
          State of the network device. Can be either "absent" or "present".
        </li>
        <li>
          <code>&lt;metaReading&gt;_uptime</code><br>
          Time in seconds since the network device is reachable.
        </li>
        <li>
          <code>&lt;metaReading&gt;_uptimeText</code><br>
          Time in "d days, hh hours, mm minutes, ss seconds" since the network
          device is reachable.
        </li>
      </ul>
    </ul><br>
    <a name="Nmapattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>absenceThreshold &lt;n&gt;</code><br>
        The number of network cans that must result in "absent" before the
        state of a network device changes to "absent". With this function you
        can verify the absence of a device before the status is changed to
        "absent". If this attribute is set to a value &gt;1, the reading
        "&lt;metaReading&gt;_state" remains on "present" until the final status
        changes to "absent".
      </li>
      <li>
        <code>args &lt;args&gt;</code><br>
        Arguments for the Nmap scan.<br>
        The default is "-sn".
      </li>
      <li>
        <code>deleteOldReadings &lt;s&gt;</code><br>
        After a network scan, all host-specific readings older than &lt;s&gt;
        seconds are deleted
      </li>
      <li>
        <code>
          devAlias &lt;ID&gt;:&lt;ALIAS&gt; &lt;ID2&gt;:&lt;ALIAS2&gt; ...
        </code><br>
        A whitespace separated list of &lt;ID&gt;:&lt;ALIAS&gt; pairs that can be used to give an alias to network devices.<br>
        The ID can be MAC address, hostname or IPv4 address.<br>
        Examples:
        <ul>
          MAC address:
          <code>
            attr &lt;name&gt; devAlias 5C:51:88:A5:94:1F:Michaels_Handy_byMAC
          </code><br>
          Hostname:
          <code>
            attr &lt;name&gt; devAlias
            android-87c7a6221093d830:Michaels_Handy_byHOST
          </code><br>
          IPv4 address:
          <code>
            attr &lt;name&gt; devAlias 192.168.1.130:Michaels_Handy_byIP
          </code><br>
        </ul>
      </li>
      <li>
        <code>disable 1</code><br>
        A running scan is canceled and no new scans are started.
      </li>
      <li>
        <code>excludeHosts &lt;target specification&gt;</code><br>
        All target hosts in the &lt;target specification&gt; are skipped during the scan.
      </li>
      <li>
        <code>interval &lt;seconds&gt;</code><br>
        Interval in seconds in which the scan is performed.<br>
        The default value is 900 seconds and the minimum value is 30 seconds.
      </li>
      <li>
        <code>keepReadings 1</code><br>
        If a new IP address is recognized for a device with a known MAC
        address, the invalid readings are deleted unless this attribute is set.
      </li>
      <li>
        <code>leadingZeros 1</code><br>
        For the readings, the IPv4 addresses are displayed with leading zeros.
      </li>
      <li>
        <code>metaReading &lt;metaReading&gt;</code><br>
        You can specify "alias", "hostname", "ip" or "macAddress" as
        &lt;metaReading&gt; and is the identifier for the readings.<br>
        The default is "ip".
      </li>
      <li>
        <code>path</code><br>
        Path under which the Nmap program is to be reached.<br>
        The default is "/urs/bin/nmap".
      </li>
      <li>
        <a href="#readingFnAttributes">
          <u><code>readingFnAttributes</code></u>
        </a>
      </li>
      <li>
        <code>sudo 1</code><br>
        The scan runs with root privileges.<br>
        The prerequisite is that the user has these rights under the FHEM. For
        the user "fhem", on a Debian (based) system, they can be set in the
        "/etc/sudoers" file. For this, the line "fhem    ALL=(ALL) NOPASSWD:
        /usr/bin/nmap" must be inserted in the section "#User privilege
        specification".
      </li>
    </ul>
  </ul>
</div>

=end html

=begin html_DE

<a name="Nmap"></a>
<h3>Nmap</h3>
( <a href="commandref.html#Nmap"><u>en</u></a> | de )
<div>
  <ul>
    Nmap ist das FHEM Modul um einen Netzwerkscan mit Nmap durchzuf&uuml;hren
    und Informationen &uuml;ber die erreichbaren Netzwerkger&auml;te
    darzustellen.<br>
    Wird ein neues Gerät erkannt wird ein Event
    <code>"&lt;name&gt; new host: &lt;hostname&gt; (&lt;IPv4&gt;)"</code>
    erzeugt.<br>
    Wird erkannt, dass ein Gerät mit bekannter MAC-Adresse eine neue IP
    erhalten hat wird ein Event
    <code>"&lt;name&gt; new IP: &lt;hostname&gt; (&lt;IPv4&gt;)"</code>
    erzeugt.<br>
    <br>
    Vorraussetzungen:
    <ul>
      Das Programm "Nmap" sowie das Perl-Modul "Nmap::Parser" werden
      ben&ouml;tigt.<br>
      Unter Debian (basierten) System, k&ouml;nnen diese mittels
      <code>"apt-get install nmap libnmap-parser-perl"</code>
      installiert werden.
    </ul>
    <br>
    <a name="Nmapdefine"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; Nmap &lt;target specification&gt;</code><br>
      In der &lt;target specification&gt; stehen alle Zielhosts, die gescannet
      werden sollen. <br>
      Der einfachste Fall ist die Beschreibung einer IP-Zieladresse oder eines
      Zielhostnamens zum Scannen. <br>
      Um ein ganzes Netzwerk benachbarter Hosts zu scannen unterst&uuml;tzt
      Nmap Adressen im CIDR-Stil. Es k&ouml;nnen /numbits an eine IPv4-Adresse
      oder an einen Hostnamen angef&uuml;gt werden, und Nmap wird alle
      IP-Adressen scannen, bei denen die ersten numbits mit denen der gegebenen
      IP oder des gegebenen Hostnamens &uuml;bereinstimmen. Zum Beispiel
      w&uuml;rde 192.168.10.0/24 die 256 Hosts zwischen 192.168.10.0 und
      192.168.10.255 scannen. 192.168.10.40/24 w&uuml;rde genau dieselben Ziele
      scannen.<br>
      Siehe
      <a href="https://nmap.org/man/de/man-target-specification.html">
        <u>Nmap Man Page (Angabe von Zielen)</u>
      </a>.
    </ul><br>
    <a name="Nmapset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>clear readings</code><br>
        L&ouml;scht alle Readings außer "state".
      </li>
      <li>
        <code>deleteOldReadings &lt;s&gt;</code><br>
        Löscht alle Readings die älter sind als &lt;s&gt; Sekunden.
      </li>
      <li>
        <code>interrupt</code><br>
        Bricht einen laufenden Scan ab.
      </li>
      <li>
        <code>statusRequest</code><br>
        Startet einen Netzwerkscan.
      </li>
    </ul><br>
    <a name="Nmapreadings"></a>
    <b>Readings</b><br>
    <ul>
      Allgemeine Readings:
      <ul>
        <li>
          <code>NmapVersion</code><br>
          Die Versionsnummer des installierten Nmap Programms.
        </li>
        <li>
          <code>hostsScanned</code><br>
          Die Anzahl der gescannten Adressen.
        </li>
        <li>
          <code>hostsUp</code><br>
          Die Anzahl der erreichbaren Netzwerkger&auml;te.
        </li>
        <li>
          <code>knownHosts</code><br>
          Die Anzahl der bekannten Netzwerkger&auml;te.
        </li>
        <li>
          <code>scanDuration</code><br>
          Die Scan-Dauer in Sekunden.
        </li>
        <li>
          <code>state</code><br>
          <ul>
            <li>
              <code>Initialized</code><br>
              Nmap wurde definiert oder enabled.
            </li>
            <li>
              <code>running</code><br>
              Ein Netzwerkscan wird ausgef&uuml;hrt.
            </li>
            <li>
              <code>done</code><br>
              Der Netzwerkscan wurde erfolgreich abgeschlossen.
            </li>
            <li>
              <code>aborted</code><br>
              Der Netzwerkscan wurde aufgrund einer Zeit&uuml;berschreitung oder
              durch den Benutzer abgebrochen.
            </li>
            <li>
              <code>disabled</code><br>
              Nmap wurde deaktiviert.
            </li>
          </ul>
        </li>
      </ul>
      <br>
      Hostspezifische Readings:
      <ul>
        <li>
          <code>&lt;metaReading&gt;_alias</code><br>
          Alias welcher unter dem Attribut "devAlias" für das Netzwerkger&auml;t
          angegeben ist. Ist kein Alias angegeben wird der Hostname angezeigt.
        </li>
        <li>
          <code>&lt;metaReading&gt;_hostname</code><br>
          Hostname des Netzwerkger&auml;ts. Kann dieser nicht ermittel werden
          wird die IPv4-Adresse angezeigt.
        </li>
        <li>
          <code>&lt;metaReading&gt;_ip</code><br>
          IPv4-Adresse des Netzwerkger&auml;ts.
        </li>
        <li>
          <code>&lt;metaReading&gt;_lastSeen</code><br>
          Der Zeitpunkt zu dem das Netzwerkger&auml;t das letzte mal als gesehen
          wurde.
        </li>
        <li>
          <code>&lt;metaReading&gt;_macAddress</code><br>
          MAC-Adresse des Netzwerkger&auml;ts. Diese kann nur ermittelt werden,
          wenn der Scan mit Root-Rechten ausgef&uuml;hrt wird.
        </li>
        <li>
          <code>&lt;metaReading&gt;_macVendor</code><br>
          Vermutlicher Hersteller des Netzwerkger&auml;ts. Dieser kann nur
          ermittelt werden, wenn der Scan mit Root-Rechten ausgef&uuml;hrt wird.
        </li>
        <li>
          <code>&lt;metaReading&gt;_state</code><br>
          Status des Netzwerkger&auml;ts. Kann entweder "absent" oder "present"
          sein.
        </li>
        <li>
          <code>&lt;metaReading&gt;_uptime</code><br>
          Zeit in Sekunden seit der das Netzwerkger&auml;t erreichbar ist.
        </li>
        <li>
          <code>&lt;metaReading&gt;_uptimeText</code><br>
          Zeit in "d days, hh hours, mm minutes, ss seconds" seit der das
          Netzwerkger&auml;t erreichbar ist.
        </li>
      </ul>
    </ul><br>
    <a name="Nmapattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <code>absenceThreshold &lt;n&gt;</code><br>
        Die Anzahl an Netzwerkscans, welche in "absent" resultieren
        m&uuml;ssen, bevor der Status eines Netzwerkger&auml;ts auf "absent"
        wechselt. Mit dieser Funktion kann man die Abwesenheit eines
        Ger&auml;tes verifizieren bevor der Status final auf "absent"
        ge&auml;ndert wird. Wenn dieses Attribut auf einen Wert &gt;1 gesetzt
        ist, verbleibt das Reading "&lt;metaReading&gt;_state" auf "present",
        bis der Status final auf "absent" wechselt.
      </li>
      <li>
        <code>args &lt;args&gt;</code><br>
        Argumente für den Nmap-Scan.<br>
        Die Vorgabe ist "-sn".
      </li>
      <li>
        <code>deleteOldReadings &lt;s&gt;</code><br>
        Nach einem Netzwerkscan werden alle hostspezifischen Readings, die
        älter sind als &lt;s&gt; Sekunden, gelöscht
      </li>
      <li>
        <code>
          devAlias &lt;ID&gt;:&lt;ALIAS&gt; &lt;ID2&gt;:&lt;ALIAS2&gt; ...
        </code><br>
        Eine Leerzeichen-getrennte getrennte Liste von &lt;ID&gt;:&lt;ALIAS&gt;
        Paaren, die dazu genutzt werden kann um Netzwerkger&auml;ten einen
        Alias zu geben.<br>
        Die ID kann dabei MAC-Adresse, hostname oder IPv4-Adresse sein.<br>
        Beispiele:
        <ul>
          MAC-Adresse:
          <code>
            attr &lt;name&gt; devAlias 5C:51:88:A5:94:1F:Michaels_Handy_byMAC
          </code><br>
          hostname:
          <code>
            attr &lt;name&gt; devAlias
            android-87c7a6221093d830:Michaels_Handy_byHOST
          </code><br>
          IPv4-Adresse:
          <code>
            attr &lt;name&gt; devAlias 192.168.1.130:Michaels_Handy_byIP
          </code><br>
        </ul>
      </li>
      <li>
        <code>disable 1</code><br>
        Ein laufender Scan wird abgebrochen und es werden keine neuen Scans
        gestartet.
      </li>
      <li>
        <code>excludeHosts &lt;target specification&gt;</code><br>
        In der &lt;target specification&gt; stehen alle Zielhosts, die beim
        Scan &uuml;bersprungen werden sollen.
      </li>
      <li>
        <code>interval &lt;seconds&gt;</code><br>
        Intervall in Sekunden in dem der Scan durchgef&uuml;hrt wird.<br>
        Der Vorgabewert ist 900 Sekunden und der Mindestwert 30 Sekunden.
      </li>
      <li>
        <code>keepReadings 1</code><br>
        Wird für ein Gertät mit bekannter MAC-Adresse eine neue IP-Adresse
        erkannt, werden die ungültig gewordenen Readings gelöscht es sei denn
        dieses Attribut ist gesetzt.
      </li>
      <li>
        <code>leadingZeros 1</code><br>
        Bei den Readings-Namen werden die IPv4-Adressen mit f&uuml;hrenden
        Nullen dargestellt.
      </li>
      <li>
        <code>metaReading &lt;metaReading&gt;</code><br>
        Als &lt;metaReading&gt; kann "alias", "hostname", "ip" oder
        "macAddress" angegeben werden und ist der Bezeichner für die
        Readings.<br>
        Die Vorgabe is "ip".
      </li>
      <li>
        <code>path</code><br>
        Pfad unter dem das Nmap Programm zu erreichen ist.<br>
        Die Vorgabe ist "/urs/bin/nmap".
      </li>
      <li>
        <a href="#readingFnAttributes">
          <u><code>readingFnAttributes</code></u>
        </a>
      </li>
      <li>
        <code>sudo 1</code><br>
        Der Scan wird mit Root-Rechten ausgef&uuml;hrt.<br>
        Voraussetzung ist, dass der Benutzer unter dem FHEM ausgef&uuml;hrt
        diese Rechte besitzt. F&uuml;r den Benutzer "fhem", auf einem Debian
        (basierten) System, lassen sich diese in der Datei "/etc/sudoers"
        festlegen. Daf&uuml;r muss im Abschnitt "# User privilege
        specification" die Zeile "fhem    ALL=(ALL) NOPASSWD: /usr/bin/nmap"
        eingef&uuml;gt werden.
      </li>
    </ul>
  </ul>
</div>

=end html_DE
=cut
