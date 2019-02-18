#####################################################################################
# $Id$
#
# Usage
# 
# define <name> serviced <service name> [user@ip-address]
#
#####################################################################################

package main;

use strict;
use warnings;

use Blocking;
use Time::HiRes;
use vars qw{%defs};

my $servicedVersion = "1.2.4";

sub serviced_shutdownwait($);

sub serviced_Initialize($)
{
  my ($hash) = @_;
  $hash->{AttrFn}     = "serviced_Attr";
  $hash->{DefFn}      = "serviced_Define";
  $hash->{GetFn}      = "serviced_Get";
  $hash->{NotifyFn}   = "serviced_Notify";
  $hash->{SetFn}      = "serviced_Set";
  $hash->{ShutdownFn} = "serviced_Shutdown";
  $hash->{UndefFn}    = "serviced_Undef";
  $hash->{AttrList}   = "disable:1,0 ".
                        "serviceAutostart ".
                        "serviceAutostop ".
                        "serviceGetStatusOnInit:0,1 ".
                        "serviceInitd:1,0 ".
                        "serviceLogin ".
                        "serviceRegexFailed ".
                        "serviceRegexStarted ".
                        "serviceRegexStarting ".
                        "serviceRegexStopped ".
                        "serviceStatusInterval ".
                        "serviceStatusLine:1,2,3,4,5,6,7,8,9,last ".
                        "serviceSudo:0,1 ".
                        $readingFnAttributes;
}

sub serviced_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  return "Usage: define <name> serviced <service name> [user\@ip-address]"
    if (@args < 3 || @args > 4);
  my ($name,$type,$service,$remote) = @args;
  return "Remote host must be like 'pi\@192.168.2.22' or 'pi\@myserver'!"
    if ($remote && $remote !~ /^\w{2,}@(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|[\w\.\-_]{2,})$/);
  RemoveInternalTimer($hash);
  $hash->{NOTIFYDEV}   = "global";
  $hash->{SERVICENAME} = $service;
  $hash->{VERSION}     = $servicedVersion;
  if ($init_done && !defined $hash->{OLDDEF})
  {
    $attr{$name}{alias}         = "Service $service";
    $attr{$name}{cmdIcon}       = "restart:rc_REPEAT stop:rc_STOP status:rc_INFO start:rc_PLAY";
    $attr{$name}{devStateIcon}  = "Initialized|status:light_question error|failed:light_exclamation running:audio_play:stop stopped:audio_stop:start stopping:audio_stop .*starting:audio_repeat";
    $attr{$name}{room}          = "Services";
    $attr{$name}{icon}          = "hue_room_garage";
    $attr{$name}{serviceLogin}  = $remote if ($remote);
    $attr{$name}{webCmd}        = "start:restart:stop:status";
    if (grep /^homebridgeMapping/,split(" ",AttrVal("global","userattr","")))
    {
      $attr{$name}{genericDeviceType} = "switch";
      $attr{$name}{homebridgeMapping} = "On=state,valueOff=/stopped|failed/,cmdOff=stop,cmdOn=start\n".
                                        "StatusJammed=state,values=/error|failed/:JAMMED;/.*/:NOT_JAMMED";
    }
  }
  readingsSingleUpdate($hash,"state","Initialized",1) if ($init_done);
  serviced_GetUpdate($hash);
  return undef;
}

sub serviced_Undef($$)
{                     
  my ($hash,$name) = @_;
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
  return undef;                  
}

sub serviced_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $devname = $dev->{NAME};
  return if (IsDisabled($name));
  my $events = deviceEvents($dev,0);
  return if (!$events);
  if ($devname eq "global" && grep /^INITIALIZED$/,@{$events})
  {
    if (AttrNum($name,"serviceGetStatusOnInit",1) && !AttrNum($name,"serviceStatusInterval",0))
    {
      Log3 $name,3,"$name: get status of service \"$hash->{SERVICENAME}\" due to startup";
      serviced_Set($hash,$name,"status");
    }
    my $delay = AttrVal($name,"serviceAutostart",0);
    $delay = $delay > 300 ? 300 : $delay;
    if ($delay)
    {
      Log3 $name,3,"$name: starting service \"$hash->{SERVICENAME}\" with delay of $delay seconds";
      InternalTimer(gettimeofday() + $delay,"serviced_Set","$name|start");
    }
  }
  return;
}

sub serviced_Get($@)
{
  my ($hash,$name,$cmd) = @_;
  return if (IsDisabled($name) && $cmd ne "?");
  my $params =  "status:noArg";
  if ($cmd eq "status")
  {
    return "Work already/still in progress... Please wait for the current process to finish."
      if ($hash->{helper}{RUNNING_PID} && !$hash->{helper}{RUNNING_PID}{terminated});
    serviced_Set($hash,$name,"status");
  }
  else
  {
    return "Unknown argument $cmd for $name, choose one of $params";
  }
}

sub serviced_Set($@)
{
  my ($hash,$name,$cmd) = @_;
  if (ref $hash ne "HASH")
  {
    ($name,$cmd) = split /\|/,$hash;
    $hash = $defs{$name};
  }
  return if (IsDisabled($name) && $cmd ne "?");
  my $params = "start:noArg stop:noArg restart:noArg status:noArg";
  return "$cmd is not a valid command for $name, please choose one of $params"
    if (!$cmd || $cmd eq "?" || !grep(/^$cmd:noArg$/,split " ",$params));
  return "Work already/still in progress... Please wait for the current process to finish."
    if ($hash->{helper}{RUNNING_PID} && !$hash->{helper}{RUNNING_PID}{terminated});
  $cmd = "restart"
    if ($cmd eq "start" && ReadingsVal($name,"state","") =~ /^running|starting|failed$/);
  my $service = $hash->{SERVICENAME};
  my $login = AttrVal($name,"serviceLogin","");
  my $sudo = AttrNum($name,"serviceSudo",1) || $login !~ /^root@/ ? "sudo " : "";
  my $line = AttrVal($name,"serviceStatusLine",3);
  my $com;
  $com .= "ssh $login '" if ($login);
  $com .= $sudo;
  if (AttrNum($name,"serviceInitd",0))
  {
    $com .= "service $service $cmd";
  }
  else
  {
    $com .= "systemctl $cmd $service";
  }
  $com .= "'" if ($login);
  Log3 $name,5,"$name: serviced_Set executing shell command: $com";
  $com = encode_base64($com,"");
  if ($hash->{LOCKFILE})
  {
    $hash->{helper}{RUNNING_PID} = BlockingCall("serviced_ExecCmd","$name|$cmd|$com|$line","serviced_ExecFinished");
  }
  else
  {
    $hash->{helper}{RUNNING_PID} = BlockingCall("serviced_ExecCmd","$name|$cmd|$com|$line","serviced_ExecFinished",301,"serviced_ExecAborted",$hash);
  }
  my $state = $cmd eq "status" ? $cmd : $cmd =~ /start/ ? $cmd."ing" : $cmd."ping";
  readingsSingleUpdate($hash,"state",$state,1);
  return;
}

sub serviced_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $defs{$name};
  if ($cmd eq "set")
  {
    if ($attr_name =~ /^disable|serviceGetStatusOnInit|serviceInitd|serviceSudo$/)
    {
      return "$attr_value not valid, can only be 0 or 1!"
        if ($attr_value !~ /^1|0$/);
      if ($attr_name eq "disable")
      {
        BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
        serviced_GetUpdate($hash) if (AttrNum($name,"serviceStatusInterval",0));
      }
    }
    elsif ($attr_name =~ /^serviceAutostart|serviceAutostop$/)
    {
      my $er = "$attr_value not valid for $attr_name, must be a number in seconds like 5 to automatically (re)start service after init of fhem (min: 1, max: 300)!";
      $er = "$attr_value not valid for $attr_name, must be a timeout in seconds like 1 to automatically stop service while shutdown of fhem (min: 1, max: 300)!" if ($attr_name eq "serviceAutostop");
      return $er
        if ($attr_value !~ /^(\d{1,3})$/ || $1 > 300 || $1 < 1);
    }
    elsif ($attr_name eq "serviceLogin")
    {
      return "$attr_value not valid for $attr_name, must be a ssh login string like 'pi\@192.168.2.22' or 'pi\@myserver'!"
        if ($attr_value !~ /^\w{2,}@(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|[\w\.\-_]{2,})$/);
    }
    elsif ($attr_name =~ /^serviceRegexFailed|serviceRegexStopped|serviceRegexStarted|serviceRegexStarting$/)
    {
      my $ex = "dead|failed|exited";
      $ex = "inactive|stopped" if ($attr_name eq "serviceRegexStopped");
      $ex = "running|active" if ($attr_name eq "serviceRegexStarted");
      $ex = "activating|starting" if ($attr_name eq "serviceRegexStarting");
      return "$attr_value not valid for $attr_name, must be a regex like '$ex'!"
        if ($attr_value !~ /^[\w\-_]{3,}(\|[\w\-_]{3,}){0,}$/);
    }
    elsif ($attr_name eq "serviceStatusInterval")
    {
      return "$attr_value not valid for $attr_name, must be a number in seconds like 300 (min: 5, max: 999999)!"
        if ($attr_value !~ /^(\d{1,6})$/ || $1 < 5);
      $hash->{helper}{interval} = $attr_value;
      serviced_GetUpdate($hash);
    }
    elsif ($attr_name eq "serviceStatusLine")
    {
      return "$attr_value not valid for $attr_name, must be a number like 2, for 2nd line of status output, or 'last' for last line of status output!"
        if ($attr_value !~ /^(\d{1,2}|last)$/);
    }
  }
  else
  {
    if ($attr_name eq "disable")
    {
      serviced_GetUpdate($hash);
    }
    elsif ($attr_name eq "serviceStatusInterval")
    {
      $hash->{helper}{interval} = 0;
      serviced_GetUpdate($hash);
    }
  }
  return;
}

sub serviced_ExecCmd($)
{
  my ($string) = @_;
  my @a = split /\|/,$string;
  my $name = $a[0];
  my $cmd = $a[1];
  my $com = decode_base64($a[2]);
  my $line = $a[3];
  my $hash = $defs{$name};
  my $lockfile = $hash->{LOCKFILE};
  my $er = 0;
  $com .= " 2>&1" if ($cmd ne "status");
  my @qx = qx($com);
  if (!@qx && $cmd eq "status")
  {
    $com .= " 2>&1";
    @qx = qx($com);
    $er = 1;
  }
  Log3 $name,5,"$name: serviced_ExecCmd com: $com, line: $line";
  my @ret;
  my $re = "";
  foreach (@qx)
  {
    chomp;
    $_ =~ s/[\s\t ]{1,}/ /g;
    $_ =~ s/(^ {1,}| {1,}$)//g;
    push @ret,$_ if ($_);
  }
  $er = 1 if (@ret && $cmd ne "status");
  if (!$er && @ret)
  {
    $re = $ret[@ret-1] if ($line eq "last" && $ret[@ret-1]);
    $re = $ret[$line-1] if ($line =~ /^\d/ && $ret[$line-1]);
  }
  elsif (@ret)
  {
    $re = join " ",@ret;
  }
  if ($lockfile)
  {
    Log3 $name,3,"$name: shutdown sequence of service $name finished";
    my $er = FileDelete($lockfile);
    if ($er)
    {
      Log3 $name,2,"$name: error while deleting controlfile \"$lockfile\": $er";
    }
    else
    {
      Log3 $name,4,"$name: controlfile \"$lockfile\" deleted successfully";
    }
  }
  $re = encode_base64($re,"");
  return "$name|$er|$re";
}

sub serviced_ExecFinished($)
{
  my ($string) = @_;
  my @a = split /\|/,$string;
  my $name = $a[0];
  my $er = $a[1];
  my $ret = decode_base64($a[2]) if ($a[2]);
  my $hash = $defs{$name};
  my $service = $hash->{SERVICENAME};
  delete $hash->{helper}{RUNNING_PID};
  if ($er)
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","error");
    readingsBulkUpdate($hash,"error",$ret);
    readingsEndUpdate($hash,1);
    Log3 $name,3,"$name: Error: $ret";
  }
  elsif ($ret)
  {
    my $refail = AttrVal($name,"serviceRegexFailed","dead|failed|exited");
    my $restop = AttrVal($name,"serviceRegexStopped","inactive|stopped");
    my $restart = AttrVal($name,"serviceRegexStarted","running|active");
    my $restarting = AttrVal($name,"serviceRegexStarting","activating|starting");
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"error","none");
    readingsBulkUpdate($hash,"status",$ret);
    if ($ret =~ /$restarting/)
    {
      readingsBulkUpdate($hash,"state","starting");
      Log3 $name,4,"$name: Service \"$hash->{SERVICENAME}\" is starting";
    }
    elsif ($ret =~ /$restop/)
    {
      readingsBulkUpdate($hash,"state","stopped");
      Log3 $name,4,"$name: Service \"$hash->{SERVICENAME}\" is stopped";
    }
    elsif ($ret =~ /$refail/)
    {
      readingsBulkUpdate($hash,"state","failed");
      Log3 $name,4,"$name: Service \"$hash->{SERVICENAME}\" is failed";
    }
    elsif ($ret =~ /$restart/)
    {
      readingsBulkUpdate($hash,"state","running");
      Log3 $name,4,"$name: Service \"$hash->{SERVICENAME}\" is started";
    }
    readingsEndUpdate($hash,1);
  }
  else
  {
    if (AttrNum($name,"serviceStatusInterval",0))
    {
      serviced_GetUpdate($hash);
    }
    else
    {
      serviced_Set($hash,$name,"status");
    }
  }
  return undef;
}

sub serviced_ExecAborted($)
{
  my ($hash,$cause) = @_;
  $cause = "BlockingCall was aborted due to 301 seconds timeout" if (!$cause);
  my $name = $hash->{NAME};
  delete $hash->{helper}{RUNNING_PID};
  Log3 $name,2,"$name: BlockingCall aborted: $cause";
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","error");
  readingsBulkUpdate($hash,"error",$cause);
  readingsEndUpdate($hash,1);
  return undef;
}

sub serviced_GetUpdate(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $sec = defined $hash->{helper}{interval} ? $hash->{helper}{interval} : AttrNum($name,"serviceStatusInterval",undef);
  delete $hash->{helper}{interval} if (defined $hash->{helper}{interval});
  RemoveInternalTimer($hash);
  return if (IsDisabled($name) || !$sec);
  InternalTimer(gettimeofday() + $sec,"serviced_GetUpdate",$hash);
  serviced_Set($hash,$name,"status");
  return undef;
}

sub serviced_Shutdown($)
{  
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $autostop = AttrNum($name,"serviceAutostop",0);
  $autostop = $autostop > 300 ? 300 : $autostop;
  if ($autostop)
  {
    $hash->{SHUTDOWNTIME} = time;
    Log3 $name,3,"$name: stopping service \"$hash->{SERVICENAME}\" due to shutdown";
    my $lockfile = AttrVal("global","modpath",".")."/log/".$name."_shut.lock";
    my $er = FileWrite($lockfile,"controlfile shutdown sequence");
    if ($er)
    {
      Log3 $name,2,"$name: error while creating controlfile \"$lockfile\": $er";
    }
    else
    {
      Log3 $name,4,"$name: controlfile \"$lockfile\" created successfully for shutdown-sequence \"$hash->{SERVICENAME}\" ";
      $hash->{LOCKFILE} = $lockfile;
      serviced_Set($hash,$name,"stop");
      serviced_shutdownwait($hash);
    }
  }
  return undef; 
}

sub serviced_shutdownwait($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $autostop = AttrVal($name,"serviceAutostop",0);
  $autostop = $autostop > 300 ? 300 : $autostop;
  my $lockfile = $hash->{LOCKFILE};
  my ($er,undef) = FileRead($lockfile);
  if (!$er)
  {
    sleep 1;
    if (time > $hash->{SHUTDOWNTIME} + $autostop)
    {
      $er = FileDelete($lockfile);
      if ($er)
      {
        Log3 $name,2,"$name: Error while deleting controlfile \"$lockfile\": $er";
        Log3 $name,3,"$name: Maximum shutdown waittime of $autostop seconds excceeded, force shutdown.";
      }
      else
      {
        Log3 $name,3,"$name: Maximum shutdown waittime of $autostop seconds excceeded. Controlfile \"$lockfile\" deleted and force sutdown.";
      }
    }
    else
    {
      return serviced_shutdownwait($hash);
    }
  }
  return undef;
}

1;

=pod
=item device
=item summary    local/remote services management
=item summary_DE lokale/entfernte Dienste Verwaltung
=begin html

<a name="serviced"></a>
<h3>serviced</h3>
<ul>
  With <i>serviced</i> you are able to control running services either running on localhost or a remote host.<br>
  The usual command are available: start/restart/stop/status.<br>
  <br>
  <a name="serviced_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; serviced &lt;service name&gt; [&lt;user@ip-address&gt;]</code><br>
  </ul>
  <br>
  Example for running serviced for local service(s):
  <br><br>
  <ul>
    <code>define hb serviced homebridge</code><br>
  </ul>
  <br>
  Example for running serviced for remote service(s):
  <br><br>
  <ul>
    <code>define hyp serviced hyperion pi@192.168.1.4</code><br>
  </ul>
  <br>
  For remote services you have to grant passwordless ssh access for the user which is running FHEM (usually fhem). You'll find a tutorial how to do that by visiting <a target="_blank" href="http://www.linuxproblem.org/art_9.html">this link</a>.
  <br><br>
  To use systemctl (systemd) or service (initd) you have to grant permissions to the system commands for the user which is running FHEM (usually fhem) by editing the sudoers file (/etc/sudoers) (visudo).
  <br><br>
  For systemd (please check your local paths):
  <br>
  <ul>
    <code>fhem    ALL=(ALL) NOPASSWD:/bin/systemctl</code>
  </ul>
  <br>
  For initd (please check your local paths):
  <br>
  <ul>
    <code>fhem    ALL=(ALL) NOPASSWD:/usr/sbin/service</code>
  </ul>
  <br><br>
  If you have homebridgeMapping in your attributes an appropriate mapping will be added, genericDeviceType as well.
  <br>
  <a name="serviced_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>start</i><br>
      start the stopped service
    </li>
    <li>
      <i>stop</i><br>
      stop the started service
    </li>
    <li>
      <i>restart</i><br>
      restart the service
    </li>
    <li>
      <i>status</i><br>
      get status of service
    </li>
  </ul>  
  <br>
  <a name="serviced_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>status</i><br>
      get status of service<br>
      same like 'set status'
    </li>
  </ul>
  <br>
  <a name="serviced_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      stop polling and disable device completely<br>
      default: 0
    </li>
    <li>
      <i>serviceAutostart</i><br>
      delay in seconds to automatically (re)start service after start of FHEM<br>
      default:
    </li>
    <li>
      <i>serviceAutostop</i><br>
      timeout in seconds to automatically stop service while shutdown of FHEM<br>
      default:
    </li>
    <li>
      <i>serviceGetStatusOnInit</i><br>
      get status of service automatically on FHEM start<br>
      default: 1
    </li>
    <li>
      <i>serviceInitd</i><br>
      use initd (system) instead of systemd (systemctl)<br>
      default: 0
    </li>
    <li>
      <i>serviceLogin</i><br>
      ssh login string for services running on remote hosts<br>
      passwordless ssh is mandatory<br>
      default:
    </li>
    <li>
      <i>serviceRegexFailed</i><br>
      regex for failed status<br>
      default: dead|failed|exited
    </li>
    <li>
      <i>serviceRegexStarted</i><br>
      regex for running status<br>
      default: running|active
    </li>
    <li>
      <i>serviceRegexStarting</i><br>
      regex for starting status<br>
      default: activating|starting
    </li>
    <li>
      <i>serviceRegexStopped</i><br>
      regex for stopped status<br>
      default: inactive|stopped
    </li>
    <li>
      <i>serviceStatusInterval</i><br>
      interval of getting status automatically<br>
      default:
    </li>
    <li>
      <i>serviceStatusLine</i><br>
      line number of status output containing the status information<br>
      default: 3
    </li>
    <li>
      <i>serviceSudo</i><br>
      use sudo<br>
      default: 1
    </li>
  </ul>
  <br>
  <a name="serviced_read"></a>
  <p><b>Readings</b></p>
  <p>All readings updates will create events.</p>
  <ul>
    <li>
      <i>error</i><br>
      last occured error, none if no error occured<br>
    </li>
    <li>
      <i>state</i><br>
      current state
    </li>
    <li>
      <i>status</i><br>
      last status line from 'get/set status'
    </li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="serviced"></a>
<h3>serviced</h3>
<ul>
  Mit <i>serviced</i> k&ouml;nnen lokale und entfernte Dienste verwaltet werden.<br>
  Die &uuml;blichen Kommandos sind verf&uuml;gbar: start/restart/stop/status.<br>
  <br>
  <a name="serviced_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; serviced &lt;Dienst Name&gt; [&lt;user@ip-adresse&gt;]</code><br>
  </ul>
  <br>
  Beispiel serviced f&uuml;r lokale Dienste:
  <br><br>
  <ul>
    <code>define hb serviced homebridge</code><br>
  </ul>
  <br>
  Beispiel serviced f&uuml;r entfernte Dienste:
  <br><br>
  <ul>
    <code>define hyp serviced hyperion pi@192.168.1.4</code><br>
  </ul>
  <br>
  F&uuml;r entfernte Dienste muss dem Benutzer unter dem FHEM l&auml;uft dass passwortlose Anmelden per SSH erlaubt werden. Eine Anleitung wie das zu machen geht ist unter <a target="_blank" href="http://www.linuxproblem.org/art_9.html">diesem Link</a> abrufbar.
  <br><br>
  Zur Benutzung von systemctl (systemd) oder service (initd) m&uuml;ssen dem Benutzer unter dem FHEM l&auml;uft die entsprechenden Rechte in der sudoers Datei erteilt werden (/etc/sudoers) (visudo).
  <br><br>
  F&uuml;r systemd (bitte mit eigenen Pfaden abgleichen):
  <br>
  <ul>
    <code>fhem    ALL=(ALL) NOPASSWD:/bin/systemctl</code>
  </ul>
  <br>
  F&uuml;r initd (bitte mit eigenen Pfaden abgleichen):
  <br>
  <ul>
    <code>fhem    ALL=(ALL) NOPASSWD:/usr/sbin/service</code>
  </ul>
  <br><br>
  Wenn homebridgeMapping in der Attributliste ist, so wird ein entsprechendes Mapping hinzugef&uuml;gt, ebenso genericDeviceType.
  <br>
  <a name="serviced_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>start</i><br>
      angehaltenen Dienst starten
    </li>
    <li>
      <i>stop</i><br>
      laufenden Dienst anhalten
    </li>
    <li>
      <i>restart</i><br>
      Dienst neu starten
    </li>
    <li>
      <i>status</i><br>
      Status des Dienstes abrufen
    </li>
  </ul>  
  <br>
  <a name="serviced_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>status</i><br>
      Status des Dienstes abrufen<br>
      identisch zu 'set status'
    </li>
  </ul>
  <br>
  <a name="serviced_attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      Anhalten der automatischen Abfrage und komplett deaktivieren<br>
      Voreinstellung: 0
    </li>
    <li>
      <i>serviceAutostart</i><br>
      Verz&ouml;gerung in Sekunden um den Dienst nach Start von FHEM (neu) zu starten<br>
      Voreinstellung:
    </li>
    <li>
      <i>serviceAutostop</i><br>
      Timeout in Sekunden um den Dienst bei Beenden von FHEM ebenso zu beenden<br>
      Voreinstellung:
    </li>
    <li>
      <i>serviceGetStatusOnInit</i><br>
      beim Start von FHEM automatisch den Status des Dienstes abrufen<br>
      Voreinstellung: 1
    </li>
    <li>
      <i>serviceInitd</i><br>
      benutze initd (system) statt systemd (systemctl)<br>
      Voreinstellung: 0
    </li>
    <li>
      <i>serviceLogin</i><br>
      SSH Anmeldedaten f&uuml;r entfernten Dienst<br>
      passwortloser SSH Zugang ist Grundvoraussetzung<br>
      Voreinstellung:
    </li>
    <li>
      <i>serviceRegexFailed</i><br>
      Regex f&uuml;r failed Status<br>
      Voreinstellung: dead|failed|exited
    </li>
    <li>
      <i>serviceRegexStarted</i><br>
      Regex f&uuml;r running Status<br>
      Voreinstellung: running|active
    </li>
    <li>
      <i>serviceRegexStarting</i><br>
      Regex f&uuml;r starting Status<br>
      Voreinstellung: activating|starting
    </li>
    <li>
      <i>serviceRegexStopped</i><br>
      Regex f&uuml;r stopped Status<br>
      Voreinstellung: inactive|stopped
    </li>
    <li>
      <i>serviceStatusInterval</i><br>
      Interval um den Status automatisch zu aktualisieren<br>
      Voreinstellung:
    </li>
    <li>
      <i>serviceStatusLine</i><br>
      Zeilennummer der Status R&uuml;ckgabe welche die Status Information enth&auml;lt<br>
      Voreinstellung: 3
    </li>
    <li>
      <i>serviceSudo</i><br>
      sudo benutzen<br>
      Voreinstellung: 1
    </li>
  </ul>
  <br>
  <a name="serviced_read"></a>
  <p><b>Readings</b></p>
  <p>Alle Aktualisierungen der Readings erzeugen Events.</p>
  <ul>
    <li>
      <i>error</i><br>
      letzter aufgetretener Fehler, none wenn kein Fehler aufgetreten ist
    </li>
    <li>
      <i>state</i><br>
      aktueller Zustand
    </li>
    <li>
      <i>status</i><br>
      letzte Statuszeile von 'get/set status'
    </li>
  </ul>
</ul>

=end html_DE
=cut
