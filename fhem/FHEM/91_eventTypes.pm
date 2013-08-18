##############################################
# $Id: 91_eventTypes.pm 2982 2013-03-24 17:47:28Z rudolfkoenig $
package main;
use IO::File;

use strict;
use warnings;

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
  $hash->{AttrList} = "disable:0,1";
}


#####################################
sub
eventTypes_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> eventTypes filename" if(int(@a) != 3);

  my @t = localtime;
  my $f = ResolveDateWildcards($a[2], @t);
  my $fh = new IO::File "$f";
  
  if($fh) {
    while(my $l = <$fh>) {
      chomp($l);
      my @a = split(" ", $l, 3);
      $modules{eventTypes}{ldata}{$a[1]}{$a[2]} = $a[0];
    }
    close($fh);
  }

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

  return if(!$eventSrc->{CHANGED});

  my $t = $eventSrc->{TYPE};
  my $n = $eventSrc->{NAME};

  my $ret = "";
  foreach my $oe (@{$eventSrc->{CHANGED}}) {
    $oe = "" if(!defined($oe));
    my $ne = $oe;
    $ne =~ s/\b-?\d*\.?\d+\b/.*/g;
    $ne =~ s/set_\d+/set_.*/;   # HM special :/
    Log3 $ln, 4, "$ln: $t $n $oe -> $ne";
    $modules{eventTypes}{ldata}{$n}{$ne}++;
  }
  return undef;
}

sub
eventTypes_Attr(@)
{
  my @a = @_;
  my $do = 0;

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

  my $fName = $hash->{DEF};
  my $fh = new IO::File ">$fName";
  return "Can't open $fName: $!" if(!defined($fh));
  my $ldata = $modules{eventTypes}{ldata};

  foreach my $t (sort keys %{$ldata}) {
    foreach my $e (sort keys %{$ldata->{$t}}) {
      print $fh "$ldata->{$t}{$e} $t $e\n";
    }
  }
  close($fh);
  return undef;
}

###################################
sub
eventTypes_Set($@)
{
  my ($hash, @a) = @_;

  return "Unknown argument $a[1], choose one of flush" if($a[1] ne "flush");
  return eventTypes_Shutdown($hash, $hash->{NAME});
}

###################################
sub
eventTypes_Get($@)
{
  my ($hash, @a) = @_;
  my $cmd = (defined($a[1]) ? $a[1] : "");
  my $arg = $a[2];

  return "Unknown argument $cmd, choose one of list" if($cmd ne "list");
  my $out = "";
  my $ldata = $modules{eventTypes}{ldata};
  foreach my $t (sort keys %{$ldata}) {
    next if($arg && $t ne $arg);
    foreach my $e (sort keys %{$ldata->{$t}}) {
      $out .= "$t $e\n";
    }
  }
  return $out;
}

1;

=pod
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
    Collect event types for all devices. This service is used by frontends.
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
  <b>Set</b> <ul>N/A</ul><br>

  <a name="eventTypesget"></a>
  <b>Get</b>
  <ul>
      <li>list [devicename]<br>
        return the list of collected event types for all devices or for
        devicename if specified.
      </li>
  </ul>
  <br>

  <a name="eventTypesattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
  </ul>
  <br>

</ul>

=end html
=cut
