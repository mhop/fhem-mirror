
# $Id$

package main;

use strict;
use warnings;
use Blocking;

sub
speedtest_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "speedtest_Define";
  $hash->{UndefFn}  = "speedtest_Undefine";
  $hash->{SetFn}    = "speedtest_Set";
  $hash->{AttrList} = "checks-till-disable ".
                      "disable:0,1 ".
                      "path ".
                       $readingFnAttributes;
}

#####################################

sub
speedtest_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> speedtest [interval [server]]"  if(@a < 2);

  my $name = $a[0];

  my $interval = 60*60;
  $interval = $a[2] if(int(@a)>=3);
  $interval = 30*60 if( $interval < 30*60 );

  my $server = $a[3] if(int(@a)>=4);

  delete( $hash->{SERVER} );

  $hash->{NAME} = $name;

  $hash->{STATE} = "Initialized";
  $hash->{INTERVAL} = $interval;

  $hash->{SERVER} = $server if( defined( $server ) );

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "speedtest_GetUpdate", $hash, 0);

  return undef;
}

sub
speedtest_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

sub
speedtest_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  if($cmd eq 'statusRequest') {
    $hash->{LOCAL} = 1;
    speedtest_GetUpdate($hash);
    $hash->{LOCAL} = 0;
    return undef;
  }

  my $list = "statusRequest:noArg";
  return "Unknown argument $cmd, choose one of $list";
}



sub
speedtest_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "speedtest_GetUpdate", $hash, 0);
  }

  my $server ="";
  $server = $hash->{SERVER} if( defined($hash->{SERVER}) );

  if( !$hash->{LOCAL} ) {
    return undef if( AttrVal($name, "disable", 0 ) == 1 );

    my $checks = AttrVal($name, "checks-till-disable", undef );
    if( defined($checks) )
      {
        $checks -= 1;
        $attr{$name}{"checks-till-disable"} = max(0,$checks);

        $attr{$name}{"disable"} = 1 if( $checks <= 0 );
      }
  }

  $hash->{helper}{RUNNING_PID} = BlockingCall("speedtest_DoSpeedtest", $name."|".$server, "speedtest_SpeedtestDone", 300, "speedtest_SpeedtestAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
}


sub
speedtest_DoSpeedtest($)
{
  my ($string) = @_;
  my ($name, $server) = split("\\|", $string);

  my $cmd = AttrVal($name, "path", "/usr/local/speedtest-cli" );
  $cmd .= "/speedtest-cli --simple";
  $cmd .= " --server $server" if( $server );

  Log3 $name, 5, "starting speedtest";
  my $speedstr = qx($cmd);
  Log3 $name, 5, "speedtest done";
  my @speedarr = split(/\n/, $speedstr);

  for( my $i = 0; $i < 3; ++$i )
    {
      $speedarr[$i] = $1 if( $speedarr[$i] && $speedarr[$i] =~ m/^\w+: (.*)/i );
    }

  return "$name|$speedarr[0]|$speedarr[1]|$speedarr[2]";
}
sub
speedtest_SpeedtestDone($)
{
  my ($string) = @_;

  return unless(defined($string));

  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};

  delete($hash->{helper}{RUNNING_PID});

  return if($hash->{helper}{DISABLED});

  Log3 $hash, 5, "speedtest_SpeedtestDone: $string";

  return if( $a[1] eq "Invalid server ID" );

  readingsBeginUpdate($hash);

  readingsBulkUpdate($hash,"ping",$a[1]);
  readingsBulkUpdate($hash,"download",$a[2]);
  readingsBulkUpdate($hash,"upload",$a[3]);

  readingsEndUpdate($hash,1);
}
sub
speedtest_SpeedtestAborted($)
{
  my ($hash) = @_;

  delete($hash->{helper}{RUNNING_PID});
}

1;

=pod
=begin html

<a name="speedtest"></a>
<h3>speedtest</h3>
<ul>
  Provides internet speed data via <a href="https://github.com/sivel/speedtest-cli">speedtest-cli</a>.<br><br>

  Notes:
  <ul>
    <li>speedtest-cli hast to be installed on the FHEM host.</li>
  </ul>

  <a name="speedtest_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; speedtest [&lt;interval&gt; [&lt;server&gt;]]</code><br>
    <br>

    Defines a speedtest device.<br><br>

    The data is updated every &lt;interval&gt; seconds. The default is 3600 and the minimum is 1800.<br><br>

    &lt;server&gt; gives the speedtest sever id. the list of all servers is available with <PRE>speedtest-cli --list</PRE>.

    Examples:
    <ul>
      <code>define speedtest speedtest</code><br>
      <code>define speedtest speedtest 3600 2760</code><br>
    </ul>
  </ul><br>

  <a name="speedtest_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>ping</li>
    <li>download</li>
    <li>upload</li>
  </ul><br>

  <a name="speedtest_Set"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest<br>
      manualy start a test. this works even if the device is set to disable.</li>
  </ul>

  <a name="speedtest_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>path<br>
      The path to the speedtest binary.</li>
    <li>checks-till-disable<br>
      how often the speedtest should be run before it is automaticaly set to disabled. the value will be decreased by 1 for every run.</li>
    <li>disable<br>
      set to 1 to disable the test.</li>
  </ul>
</ul>

=end html
=cut
