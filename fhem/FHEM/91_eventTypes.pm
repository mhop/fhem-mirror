##############################################
# $Id$
package main;
use IO::File;

use strict;
use warnings;
sub et_addEvt($$$$);

#####################################
sub
eventTypes_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "eventTypes_Define";
  $hash->{NotifyFn} = "eventTypes_Notify";
  $hash->{ShutdownFn}="eventTypes_Shutdown";
  $hash->{GetFn}    = "eventTypes_Get";
  $hash->{SetFn}    = "eventTypes_Set";
  $hash->{AttrFn}   = "eventTypes_Attr";
  $hash->{AttrList} = "disable:0,1 ignoreList";
}


sub
et_addEvt($$$$)
{
  my ($h, $name, $evt, $cnt) = @_;
  return 0 if($evt =~ m/ CULHM (SND|RCV) /); # HM
  return 0 if($evt =~ m/RAWMSG/);            # HM
  return 0 if($evt =~ m/^R-/);               # HM register values
  return 0 if($evt =~ m/ UNKNOWNCODE /);
  return 0 if($evt =~ m/^\d+ global /);      # update
  return 0 if($evt =~ m/[<>]/);              # HTML
  return 0 if($evt =~ m/googlecom$/);        # Kalender
  return 0 if($evt =~ m/\.gif$/);            # Proplanta
  return 0 if(length($evt) > 80);            # Safety

  $evt =~ s/ *$//;                           # HM?
  $evt =~ s/(Long|LongRelease) \d+_\d+/$1 .* /; # HM?
  $evt =~ s/rgb: [0-9a-f]{6}/rgb: .*/;       # Hue
  $evt =~ s/: [0-9A-F]*$/: .*/;              # PANSTAMP
  $evt =~ s/\b-?\d*\.?\d+\b/.*/g;            # Number to .*
  $evt =~ s/\.\*.*\.\*/.*/g;                 # Multiple wildcards to one
  $evt =~ s/set_\d+/set_.*/;                 # HM
  $evt =~ s/\b\d+_next:\d+s\b/.*/g;          # HM motionCount
  $evt =~ s/^trigger: (.*_)\d+$/trigger: $1.*/; # HM
  $evt =~ s/\.\* \(\d+K\)/.*/g;              # HUE: Kelvin
  $evt =~ s/  +/ /;                          #
  $evt =~ s/HASH\(0x.*/.*/;                  # buggy event (Forum #36818)
  $evt =~ s/[\n\r].*//s;                     # typical ECMD problem

  $h->{$name}{_etCounter}++ if(!$h->{$name}{$evt});
  $h->{$name}{$evt} += $cnt;
}

#####################################
sub
eventTypes_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> eventTypes filename" if(int(@a) != 3);

  my $cnt = 0;
  my @t = localtime;
  my $f = ResolveDateWildcards($a[2], @t);
  return "Only one eventTypes can be defined" if($modules{eventTypes}{ldata});

  my ($err, @content) = FileRead($f);
  my (%h1, %h2);
  $hash->{ignoreList} = \%h2;
  $modules{eventTypes}{ldata} = \%h1;
  foreach my $l (@content) {
    next if(!defined($l));
    my @l = split(" ", $l, 3);
    if(@l != 3) {
      Log3 undef, 2, "eventTypes: $f: bogus line $l";
      next;
    }
    next if(!$h1{$l[1]} && !goodDeviceName($l[1])); # Sanitizing: 117259
    et_addEvt(\%h1, $l[1], $l[2], $l[0]);
  }

  Log3 undef, 2, "eventTypes: loaded ".int(@content)." lines from $f";

  $hash->{STATE} = "active";
  return undef;
}

#####################################
sub
eventTypes_Notify($$)
{
  my ($me, $eventSrc) = @_;
  my $ln = $me->{NAME};
  return "" if($attr{$ln} && $attr{$ln}{disable});

  my $events = deviceEvents($eventSrc, 1);
  return if(!$events);

  my $t = $eventSrc->{TYPE};
  my $n = $eventSrc->{NAME};
  return if(!defined($n) || !defined($t));
  return if($me->{ignoreList}{$n});

  my $h = $modules{eventTypes}{ldata};
  return if($h->{$n} && $h->{$n}{_etCounter} && $h->{$n}{_etCounter} >= 200);

  if($n eq "global") {
    foreach my $oe (@{$events}) {
      if($oe =~ m/^DELETED (.+)$/) {
        delete $h->{$1};
      }
      if($oe =~ m/^RENAMED (.+) (.+)$/) {
        $h->{$2} = $h->{$1};
        delete $h->{$1};
      }
    }
    return undef;
  }

  my $ret = "";
  foreach my $oe (@{$events}) {
    next if(!defined($oe) || $oe =~ m/^\s*$/);
    et_addEvt($h, $n, $oe, 1);
  }
  return undef;
}

sub
eventTypes_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "ignoreList") {
    my %h;
    my $ldata = $modules{eventTypes}{ldata};
    foreach my $i (split(',', $a[3])) {
      $h{$i} = 1;
      delete $ldata->{$i};
    }
    $defs{$a[1]}{ignoreList} = \%h;
  }

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");
  return undef;
}

###################################
sub
eventTypes_Shutdown($$)
{
  my ($hash, $name) = @_;

  my @content;
  my $fName = $hash->{DEF};
  my $ldata = $modules{eventTypes}{ldata};
  foreach my $t (sort keys %{$ldata}) {
    foreach my $e (sort keys %{$ldata->{$t}}) {
      next if($e eq "_etCounter");
      push @content, "$ldata->{$t}{$e} $t $e";
    }
  }
  FileWrite($fName, @content);
  return undef;
}

###################################
sub
eventTypes_Set($@)
{
  my ($hash, @a) = @_;

  return $modules{eventTypes}{ldata} = undef
        if($a[1] eq "clear");
  return eventTypes_Shutdown($hash, $hash->{NAME})
        if($a[1] eq "flush");
  return "Unknown argument $a[1], choose one of clear:noArg flush:noArg";
}

###################################
sub
eventTypes_Get($@)
{
  my ($hash, @a) = @_;
  my $cmd = (defined($a[1]) ? $a[1] : "");
  my $arg = $a[2];

  return "Unknown argument $cmd, choose one of list listWithCounter" 
        if($cmd ne "list" && $cmd ne "listWithCounter");
  my $out = "";
  my $ldata = $modules{eventTypes}{ldata};
  foreach my $t (sort keys %{$ldata}) {
    next if($arg && $t ne $arg);
    foreach my $e (sort keys %{$ldata->{$t}}) {
      next if($e eq "_etCounter");
      $out .=$cmd eq "listWithCounter" ? "$t $e $ldata->{$t}{$e}\n" : "$t $e\n";
    }
  }
  return $out;
}

1;

=pod
=item helper
=item summary    collects FHEM Events to be used in frontends
=item summary_DE Sammelt FHEM Events f&uuml; die Frontends.
=begin html

<a name="eventTypes"></a>
<h3>eventTypes</h3>
<ul>
  <br>
  <a name="eventTypesdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; eventTypes &lt;filename&gt;</code>
    <br><br>
    Collect event types for all devices. This service is used by frontends,
    e.g. notify and FileLog, to assist you in selecting the correct events.
    The filename is used to store the collected events before shutdown.<br>
    More than one instance of eventTypes should not be necessary.
    Examples:
    <ul>
      <code>define et eventTypes log/eventTypes.txt</code><br>
    </ul>
    <br>
  </ul>
  <br>

  <a name="eventTypesset"></a>
  <b>Set</b>
  <ul>
      <li>flush<br>
        used to write all collected event types into datafile.
      </li>
      <br/>
      <li>clear<br>
        used to clear the internal table containing all collected event types.
      </li>
  </ul>
  <br>

  <a name="eventTypesget"></a>
  <b>Get</b>
  <ul>
      <li>list [devicename]<br>
      listWithCounter [devicename]<br>
        return the list of collected event types for all devices or for
        devicename if specified.
      </li>
  </ul>
  <br>

  <a name="eventTypesattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li><br>
    <a name="ignoreList"></a>
    <li>ignoreList<br>
      Comma separated device names to ignore whe collecting the events.
      E.g. ECMD-Devices are used to post RAW data as events.
      </li><br>
  </ul>
  <br>

</ul>

=end html
=cut
