# $Id: $
#
# See: http://www.fhemwiki.de/wiki/Jawbone_Up
# Forum: http://forum.fhem.de/index.php/topic,24889.msg179505.html#msg179505

package main;

use strict;
use warnings;

use 5.14.0;
use LWP::UserAgent 6;
use IO::Socket::SSL;
use WWW::Jawbone::Up;

sub
jawboneUp_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "jawboneUp_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "jawboneUp_Notify";
  $hash->{UndefFn}  = "jawboneUp_Undefine";
  #$hash->{SetFn}    = "jawboneUp_Set";
  $hash->{GetFn}    = "jawboneUp_Get";
  $hash->{AttrFn}   = "jawboneUp_Attr";
  $hash->{AttrList} = "disable:1 ".
                      "interval ".
                      $readingFnAttributes;
}

#####################################

sub
jawboneUp_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> JawboneUp <user> <password> [<interval>]"  if(@a < 4);

  my $name = $a[0];
  my $user = $a[2];
  my $password = $a[3];
    
  $hash->{"module_version"} = "0.1.1";
  
  $hash->{user}=$user;
  $hash->{password}=$password;
  $hash->{NAME} = $name;
  
  $hash->{"API_Failures"} = 0;
  $hash->{"API_Timeouts"} = 0;
  $hash->{"API_Success"} = 0;
  $hash->{"API_Status"} = "Initializing...";
  
  $hash->{INTERVAL} = 3600;
  if (defined($a[4])) {
	  $hash->{INTERVAL} = $a[4];
	  }

  if ($hash->{INTERVAL} < 900) {
  	  $hash->{INTERVAL} = 900;
  }
  
  delete($hash->{helper}{RUNNING_PID});
  $hash->{STATE} = "Initialized";

  if( $init_done ) {
    jawboneUp_Connect($hash);
  } 
  
  
  return undef;
}

sub
jawboneUp_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  jawboneUp_Connect($hash);
}

sub
jawboneUp_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );
  
  jawboneUp_poll($hash);
}

sub
jawboneUp_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);
  $hash->{STATE} = "Disconnected";
  $hash->{"API_Status"} = "Disconnected";
  $hash->{"API_NextSchedule"} = "- - -";

}

sub
jawboneUp_Undefine($$)
{
  my ($hash, $arg) = @_;

  jawboneUp_Disconnect($hash);

  return undef;
}

sub
jawboneUp_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";
  return "Unknown argument $cmd, choose one of $list";
}

############ Background Worker ################
sub jawboneUp_DoBackground($)
{
  my ($hash) = @_;

  # Expensive API-call:
  my $up = WWW::Jawbone::Up->connect($hash->{user}, $hash->{password});
  if (defined($up)) {
    # Expensive API-call:
    my $score = $up->score;
    
    my $na=$hash->{NAME};
    my $st=$score->{"move"}{"bg_steps"};
    my $ca=$score->{"move"}{"calories"};
    my $di=$score->{"move"}{"distance"};
    my $bc=$score->{"move"}{"bmr_calories"};
    my $bd=$score->{"move"}{"bmr_calories_day"};
    my $at=$score->{"move"}{"active_time"};
    my $li=$score->{"move"}{"longest_idle"};
    return "OK|$na|$st|$ca|$di|$bc|$bd|$at|$li";    
  } 
  #Error: API doesn't return any information about errors...
  my $na=$hash->{NAME};
  return "ERR|$na";    
}

############ Accept result from background process: ##############
sub jawboneUp_DoneBackground($)
{
  my ($string) = @_;
  if (!defined($string)) {
     # Internal error.
     print ("Internal error at DoneBackground (0x001).\n");
     return undef;
     }

  my @a = split("\\|",$string);
  if (@a < 2) {
     print ("Internal error at DoneBackground (0x002).\n");
     return undef;
  }
  my $hash = $defs{$a[1]};
  delete($hash->{helper}{RUNNING_PID});
    
  if ($a[0] eq "ERR") {
    $hash->{"API_LastError"} = FmtDateTime(gettimeofday());
    $hash->{"API_Status"} = "API Failure. Check credentials and internet connectivity, retrying...";
    $hash->{"API_Success"} = 0;
    $hash->{"API_Failures"} = $hash->{"API_Failures"}+1;
    if ($hash->{"API_Failures"} > 2) {
      $hash->{STATE} = "Disconnected - disabled";
      $attr{$hash->{NAME}}{"disable"} = 1;
      RemoveInternalTimer($hash);
      $hash->{"API_NextSchedule"} = "- - -";
      $hash->{"API_Status"} = "API Failure. Check credentials and internet connectivity, disabled. (Use manual 'get update' to re-enable.)";
    } else {
      $hash->{STATE} = "Connect-failure, retries: ".$hash->{"API_Failures"};
    }
  } else {  
    if (@a < 9) {
      print ("Internal error at DoneBackground (0x003).\n");
      $hash->{STATE} = "Disconnected - disabled";
      $attr{$hash->{NAME}}{"disable"} = 1;
      RemoveInternalTimer($hash);
      $hash->{"API_NextSchedule"} = "- - -";
      $hash->{"API_Status"} = "API Failure. Unexpected format of return values: )".$string;
     return undef;
     }
    readingsSingleUpdate($hash,"bg_steps",$a[2],1);
    readingsSingleUpdate($hash,"calories",$a[3],1);
    readingsSingleUpdate($hash,"distance",$a[4],1);
    readingsSingleUpdate($hash,"bmr_calories",$a[5],1);
    readingsSingleUpdate($hash,"bmr_calories_day",$a[6],1);
    readingsSingleUpdate($hash,"active_time",$a[7],1);
    readingsSingleUpdate($hash,"longest_idle",$a[8],1);

    $hash->{LAST_POLL} = FmtDateTime( gettimeofday() );

    $hash->{STATE} = "Connected";
    $hash->{"API_Success"} = $hash->{"API_Success"}+1;
    $hash->{"API_Status"} = "API OK Success.";
    $hash->{"API_LastSuccess"} = FmtDateTime(gettimeofday());
  }
  return undef;
}   

############ Background Worker timeout #########################        
sub jawboneUp_AbortBackground($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  $hash->{"API_Timeouts"} = $hash->{"API_Timeouts"}+1;
	
  $hash->{STATE} = "Timeout";
  $hash->{"API_Status"} = "Timeout, retrying...";
  $hash->{"API_LastError"} = FmtDateTime(gettimeofday());

  return undef if( AttrVal($hash->{NAME}, "disable", 0 ) == 1 );
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "jawboneUp_poll", $hash, 0);
  $hash->{"API_NextSchedule"} = FmtDateTime(gettimeofday()+$hash->{INTERVAL});
  return undef;
}
        
# Request update from Jawbone servers by spawning a background task (via BlockingCall)                          
sub
jawboneUp_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  $hash->{"API_NextSchedule"} = "- - -";

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  # Getting values from Jawbone server sometimes takes several seconds - therefore we background the request.
  if (exists($hash->{helper}{RUNNING_PID})) {
    $hash->{"API_ReentranceAvoided"} = $hash->{"API_ReentranceAvoided"}+1;
      if ($hash->{"API_ReentranceAvoided"} > 1) {
          $hash->{"API_ReentranceAvoided"} = 0;
          $hash->{"API_Failures"} = $hash->{"API_Failures"}+1;
          $hash->{"API_Status"} = "Reentrance-Problem, retrying...";
          # This is potentially dangerous, because it cannot be verified if the old process is still running,
          # However there were cases when neither the Abort nor the Done callback were activitated, leading
          # to a stall of the module
          delete($hash->{helper}{RUNNING_PID});
        }
  } else {
    $hash->{helper}{RUNNING_PID} = BlockingCall("jawboneUp_DoBackground",$hash,"jawboneUp_DoneBackground",60,"jawboneUp_AbortBackground",$hash);
  }
  return undef if( AttrVal($hash->{NAME}, "disable", 0 ) == 1 );
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "jawboneUp_poll", $hash, 0);
  $hash->{"API_NextSchedule"} = FmtDateTime(gettimeofday()+$hash->{INTERVAL});
  return undef;
}


sub
jawboneUp_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "update:noArg";

  if( $cmd eq "update" ) {
      if ( AttrVal($hash->{NAME}, "disable", 0 ) == 1 ) {
        $attr{$hash->{NAME}}{"disable"} = 0;
      }
      jawboneUp_poll($hash);
      return undef;
  }
  return "Unknown argument $cmd, choose one of $list";
}

sub
jawboneUp_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 900 if($attrName eq "interval" && $attrVal < 900 && $attrVal != 0);

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    $hash->{INTERVAL} = 900 if( !$attrVal );
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    $hash->{"API_NextSchedule"} = "- - -";
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
      jawboneUp_poll($hash);
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;}

1;

=pod
=begin html

<a name="JawboneUp"></a>
<h3>JawboneUp</h3>
<ul>
  This module supports the Jawbone Up[24] fitness tracker. The module collects calories, steps and distance walked (and a few other metrics) on a given day.<br><br>
  All communication with the Jawbone services is handled as background-tasks, in order not to interfere with other FHEM services.
  <br><br>
  <b>Installation</b>
  Among the perl modules required for this module are: LWP::UserAgent, IO::Socket::SSL, WWW::Jawbone::Up.<br>
  At least WWW:Jawbone::Up doesn't seem to have a debian equivalent, so you'll need CPAN to install the modules.<br>
  Example: <code>cpan -i WWW::Jawbone::Up</code> should install the required perl modules for the Jawbone up.<br>
  Unfortunately the WWW::Jawbone::Up module relies on quite a number of dependencies, so in case of error, check the CPAN output for missing modules.<br>
  Some dependent modules might fail during self-test, in that case try a forced install: <code>cpan -i -f module-name</code>
  <br><br>
  <b>Error handling</b>
  If there are more than three consecutive API errors, the module disables itself. A "get update" re-enables the module.<br>
  API errors can be caused by wrong credentials or missing internet-connectivity or by a failure of the Jawbone server.<br><br>
  <b>Configuration</b>
  <a name="jawboneUp_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; JawboneUp &lt;user&gt; &lt;password&gt; [&lt;interval&gt;] </code><br>
    <br>
    Defines a JawboneUp device.<br>
 <b>Parameters</b>
 <ul>
    <li>name<br>
      A name for your jawbone device.</li>
    <li>user<br>
      Username (email) used as account-name for the jawbone service.</li>
    <li>password<br>
      The password for the jawbone service.</li>
    <li>interval<br>
      Optional polling intervall in seconds. Default is 3600, minimum is 900 (=5min).</li>
  </ul><br>

    Example:
    <ul>
      <code>define myJawboneUp JawboneUp me@foo.org myS3cret 3600</code><br>
      <code>attr myJawboneUp room Jawbone</code><br>
    </ul>
  </ul><br>
  <a name="jawboneUp_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>active_time<br>
    (Active time (seconds))</li>
    <li>bg_steps<br>
    (Step count)</li>
    <li>bmr_calories<br>
    (Resting calories)</li>
    <li>bmr_calories_day<br>
    (Average daily calories (without activities))</li>
    <li>calories<br>
    (Activity calories)</li>
    <li>distance<br>
    (Distance in km)</li>
    <li>longest_idle<br>
    (Inactive time in seconds)</li>
  </ul><br>

  <a name="jawboneUp_Get"></a>
  <b>Get</b>
  <ul>
    <li>update<br>
      trigger an update</li>
  </ul><br>

  <a name="jawboneUp_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds for updates. the default ist 3600 (=1h), minimum is 900 (=15min).</li>
    <li>disable<br>
      1 -> disconnect and stop polling</li>
  </ul>
</ul>

=end html
=cut
