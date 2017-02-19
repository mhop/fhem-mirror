###############################################################################
#
# $Id$
# 96_SIP.pm 
# Based on FB_SIP from  werner.meines@web.de
#
#
###############################################################################
#
#  (c) 2017 Copyright: Wzut & plin
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and imPORTant notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
##################################################################################


#######################################################################
# need: Net::SIP (cpan install Net::SIP)
#					
#
#  convert audio to PCM 8000 :
#  sox <file>.wav -t raw -r 8000 -c 1 -e a-law <file>.alaw
#  oder
#  sox <file>  -r 8000 -c 1 -e a-law <file>.wav
#
########################################################################


package main;
use strict;
use warnings;

use Net::SIP qw//;
use IO::Socket;
use Socket;
use Net::Domain qw( hostfqdn );
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call
#use Data::Dumper;

my $ua;			# SIP user agent
my $my_name;
my $call;

my %sets = (
   "call"         => "",
   "listen:noArg" => "",
   "reset:noArg"  => "",
   "fetch:noArg"  => "",
   );


sub SIP_Initialize($$)
{
  my ($hash) = @_;

  $hash->{DefFn}        = "SIP_Define";
  $hash->{UndefFn}      = "SIP_Undef";
  $hash->{ShutdownFn}   = "SIP_Undef";
  $hash->{SetFn}        = "SIP_Set";
  $hash->{GetFn}        = "SIP_Get";
  $hash->{AttrList}     = "sip_waits ".
                          "sip_ringtime ".
                          "sip_waittime ". 
                          "sip_ip ".
                          "sip_port ". 
                          "sip_user ".
                          "sip_password ". 
                          "sip_registrar ".
                          "sip_from ".
                          "sip_audiofile ".
                          "sip_listen:none,dtmf,wfp ". 
                          "disabled:0,1 ".$readingFnAttributes;
}						

sub SIP_Define($$) 
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = shift @a;
  my $host = hostfqdn();
  my $addr = inet_ntoa(scalar(gethostbyname($host)));

  $hash->{STATE}          = "defined"; 	
  $attr{$name}{sip_ringtime}  = '10'        unless (exists($attr{$name}{sip_ringtime}));
  $attr{$name}{sip_user}      = '620'       unless (exists($attr{$name}{sip_user}));
  $attr{$name}{sip_password}  = 'test'      unless (exists($attr{$name}{sip_password}));
  $attr{$name}{sip_ip}        = $addr       unless (exists($attr{$name}{sip_ip}));
  $attr{$name}{sip_port}      = '5060'      unless (exists($attr{$name}{sip_port}));
  $attr{$name}{sip_registrar} = 'fritz.box' unless (exists($attr{$name}{sip_registrar}));
  $attr{$name}{sip_listen}    = 'none'      unless (exists($attr{$name}{sip_listen}));
  $attr{$name}{sip_from}      = 'sip:'.$attr{$name}{sip_user}.'@'.$attr{$name}{sip_registrar} unless (exists($attr{$name}{sip_from}));

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "SIP_updateConfig", $hash, 0);
  return undef;
}

sub SIP_updateConfig($)
{
    # this routine is called 5 sec after the last define of a restart
    # this gives FHEM sufficient time to fill in attributes

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $error;

    if (!$init_done)
    {
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday()+5,"SIP_updateConfig", $hash, 0);
	return;
    }
    ## kommen wir via reset Kommando ?
    if ($hash->{".reset"})
    {
	$hash->{".reset"} = 0;
	RemoveInternalTimer($hash);
	if(defined($hash->{LPID}))
	{
                    Log3 $name,4, "$name, Listen Kill PID : ".$hash->{LPID};
	    BlockingKill($hash->{helper}{LISTEN_PID});
	    delete $hash->{helper}{LISTEN_PID};
	    delete $hash->{LPID};
	    Log3 $name,4,"$name, Reset Listen done";
	}
	if(defined($hash->{CPID}))
	{
                    Log3 $name,4, "$name, CALL Kill PID : ".$hash->{CPID};
	    BlockingKill($hash->{helper}{CALL_PID});
	    delete $hash->{helper}{CALL_PID};
                    delete $hash->{CPID};
	    Log3 $name,4,"$name, Reset Call done";
	}
    } 

    if (IsDisabled($name))
    {
	readingsSingleUpdate($hash,"state","disabled",1);
	return undef;
    }

        if (AttrVal($name,"sip_listen", "none") ne "none")
        {
      
         $error = SIP_try_listen($hash);
         if ($error)
         { 
          Log3 $name, 1, $name.", listen -> $error";
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"state","error");
          readingsBulkUpdate($hash,"last_error",$error);
          readingsEndUpdate($hash, 1 );
          return undef;
         }
        }
       else { readingsSingleUpdate($hash, "state","initialized",1);}
       return undef;
}
    

sub SIP_Register($$)
{
  my ($hash,$port) = @_;
  my $name = $hash->{NAME};
  my $ip   = AttrVal($name,"sip_ip","");
  return "missing attr sip_ip" if (!$ip);

  my $leg = IO::Socket::INET->new(
    Proto => 'udp',
    LocalHost => $ip,
    LocalPort => $port);

#  if  port is already used try another one
   if (!$leg) 
   {
   Log3 $name,2,"$name, cannot open port $port at $ip: $!";
   $port += 10;
   $leg = IO::Socket::INET->new(
    Proto => 'udp',
    LocalHost => $ip,
    LocalPort => $port) || return "cannot open port ".($port-10)." or $port at $ip: $!";
    Log3 $name,2,"$name, using port $port";
   }

  close($leg);

  my $registrar = AttrVal($name,"sip_registrar","fritz.box");

  $leg = $ip.":".$port;

  # create new agent
  $ua = Net::SIP::Simple->new(
        registrar => $registrar,
        domain => $registrar,
        leg => $leg,
        from => AttrVal($name,"sip_from",'sip:620@fritz.box'),
        auth => [ AttrVal($name,"sip_user","620") , AttrVal($name,"sip_password","test") ]);
  # Register agent

# optional registration
my $sub_register;
$sub_register = sub {
	my $expire = $ua->register(registrar => $registrar ) || return "registration failed: ".$ua->error;
	Log3 $name,4,"$name, register new expire : ".localtime(time()+$expire);
	# need to refresh registration periodically
	$ua->add_timer( $expire/2, $sub_register );
                };
    $sub_register->();


  if($ua->register) # returned  expires time or undef if failed
  {
   #Log3 $name,4,"$name, ua register : ".$ua->register;
   return 0;
  }

  my $ret = ($ua->error) ? $ua->error : "registration error"; 
  return $ret;

}			

sub SIP_CALLStart($)
{
  my ($arg) = @_;
  return unless(defined($arg));
  my ($name,$nr,$ringtime,$msg) = split("\\|",$arg);
  my $hash = $defs{$name};
  my $rtp_done = 0;
  my $final;
  my $peer_hangup;
  my $stopvar;
  my $dtmf  = 'ABCD*#123--4567890';
  my $port = AttrVal($name,"sip_port","5060");
  $ua = undef;

  my $error = SIP_Register($hash,$port);
  return $name."|0|CallRegister: $error" if ($error);

 
  if ((substr($msg,0,1) ne "-") && $msg)
  {
    Log3 $name,4,"$name, msg : $msg";
    $call = $ua->invite( $nr,
    init_media => $ua->rtp('send_recv', $msg),
    cb_rtp_done => \$rtp_done,
    cb_final => \$final,
    recv_bye => \$peer_hangup,
    asymetric_rtp => 0,
    rtp_param => [8, 160, 160/8000, 'PCMA/8000']) || return $name."|0|invite failed: ".$ua->error;
  }
   else
  {
    $dtmf = (substr($msg,0,1) eq "-") ? substr($msg,1) : $dtmf; 
    Log3 $name,4,"$name, DTMF : $dtmf";
    $call = $ua->invite($nr, 
    init_media => $ua->rtp( 'recv_echo',undef,0 ),
    cb_final => \$final,
    recv_bye => \$peer_hangup) || return $name."|0|invite failed ".$ua->error;
    $call->dtmf( $dtmf, cb_final => \$rtp_done );
  }

  return "$name|0|invite failed ".$call->error if ($call->error);
 
  $ua->add_timer($ringtime,\$stopvar);
  $ua->loop( \$stopvar,\$peer_hangup,\$rtp_done );

  # timeout or dtmf done, hang up
  if ( $stopvar || $rtp_done ) 
  {
    $stopvar = undef;
    $call->bye( cb_final => \$stopvar );
    $ua->loop( \$stopvar );
  }

  $final = "unknow" if !defined($final);
  # $ua->cleanup;
  return $name."|1|".$final."|".$peer_hangup if defined($peer_hangup);
  return $name."|1|".$final."|".$stopvar     if defined($stopvar);
  return $name."|1|".$final;
}

sub SIP_CALLDone($)
{
   my ($string) = @_;
   return unless(defined($string));

   my @r = split("\\|",$string);
   my $hash   = $defs{$r[0]};
   my $error  = (defined($r[1])) ? $r[1] : "0";
   my $final  = (defined($r[2])) ? $r[2] : "???";
   my $hangup = (defined($r[3])) ? $r[3] : undef;
   my $name   = $hash->{NAME};

   Log3 $name, 4,"$name, CALLDone -> $string";
   
   delete($hash->{helper}{CALL_PID}) if (defined($hash->{helper}{CALL_PID}));
   delete($hash->{CPID}) if (defined($hash->{CPID}));

   if ($error ne "1")
   {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state","call fail");
    readingsBulkUpdate($hash, "last_error",$final);
    readingsEndUpdate($hash, 1);
   }
   else
   { readingsSingleUpdate($hash, "state","$final call done",1); }

   return undef;
}



#####################################

sub SIP_Set($@) 
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME}; 
  my $cmd  = $a[1];
  my $subcmd;

  return join(" ", sort keys %sets) if ($cmd eq "?");
 
  if  ($cmd eq "call") 
  {
    my $nr       = (defined($a[2])) ? $a[2] : "";
    my $ringtime = (defined($a[3])) ? $a[3] : AttrVal($name, "sip_ringtime", "10");;
    my $msg      = (defined($a[4])) ? $a[4] : "";;
    return "there is already a call activ with pid ".$hash->{CPID} if exists($hash->{CPID});
    return "missung call number" if (!$nr);

    my $arg;
    if ($msg)
    {
      Log3 $name, 4, $name.", sending file $msg to $nr, ringtime: $ringtime"; 

      if((-e $msg) || (substr($msg,0,1) eq "-")) { Log3 $name, 4, $name.", $msg found"; } 
      else 
      { 
        Log3 $name, 3, $name.", message $msg NOT found !";
        $msg = ""; 
      }
    }
    else { Log3 $name, 4, $name.", calling $nr, ringtime: $ringtime"; }

    $arg = "$name|$nr|$ringtime|$msg"; 
    #BlockingCall($blockingFn, $arg, $finishFn, $timeout, $abortFn, $abortArg);
    $hash->{helper}{CALL_PID} = BlockingCall("SIP_CALLStart",$arg, "SIP_CALLDone") unless(exists($hash->{helper}{CALL_PID}));

    if($hash->{helper}{CALL_PID})
    { 
     $hash->{CPID} = $hash->{helper}{CALL_PID}{pid};
     Log3 $name, 5,  "$name, call has pid ".$hash->{CPID};  
     readingsSingleUpdate($hash, "state","calling $nr",1);
     return undef;
    }
     else  
    { # das war wohl nix :(
      Log3 $name, 3,  "$name, CALL process start failed, arg : $arg"; 
      my $txt = "can't execute call number $nr as NonBlockingCall";
      readingsSingleUpdate($hash, "last_error",$txt,1);
      return $txt;
    }
  }

  elsif ($cmd eq "listen")
  {
   my $type = AttrVal($name,"sip_listen","none");
   return "there is already a listen process running with pid ".$hash->{LPID} if exists($hash->{LPID});
   return "please set attr sip_listen to dtmf or wfp first" if (AttrVal($name,"sip_listen","none") eq "none");
   my $error = SIP_try_listen($hash);
   if ($error)
   { 
    Log3 $name, 1, $name.", listen -> $error";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","error");
    readingsBulkUpdate($hash,"last_error",$error);
    readingsEndUpdate($hash, 1 );
    return $error;
   }
   
   else {readingsSingleUpdate($hash, "state","listen_for_$type",1);}
   return undef;
  }
  elsif (($cmd eq "dtmf_event") && defined($a[2]))
  {
    readingsSingleUpdate($hash, "dtmf",$a[2],1);
    return undef;
  }
  elsif ($cmd eq "caller")
  {
    # die ersten beiden brauchen wir nicht mehr
   shift @a;
   shift @a;
   # den Rest als ein String
   $subcmd = join(" ",@a);
   readingsSingleUpdate($hash, "caller",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "fetch")
  {
   readingsSingleUpdate($hash, "caller","fetch",1);
   return undef;
  }
  elsif ($cmd eq "reset")
  {
   $hash->{".reset"} =1;
   SIP_updateConfig($hash);
   return undef;
  }
  return "Unknown argument: $cmd, choose one of ".join(" ", sort keys %sets);
}	

sub SIP_Get($@) 
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME}; 
  my $cmd  = $a[1];
  return ReadingsVal($name,"caller","???") if ($cmd eq "caller");
  #return "Unknown argument: $cmd, choose one of caller:noArg";
  return undef;
} 


sub SIP_Undef($$) 
{
  my ($hash, $name) = @_;
  $ua->cleanup if (defined($ua));

  BlockingKill($hash->{helper}{LISTEN_PID}) if (defined($hash->{helper}{LISTEN_PID}));
  RemoveInternalTimer($hash);
  return undef;
}


sub SIP_ListenStart($)
{
 my ($name) = @_;
 $my_name   = $name;
 
 return unless(defined($name));
 my $hash             = $defs{$name};
 $hash->{telnetPort}  = undef;

 # Suche das Telnet Device ohne Passwort
 # Code geklaut aus Blocking.pm :)

 foreach my $d (sort keys %defs) 
 {  
    my $h = $defs{$d};
    next if(!$h->{TYPE} || $h->{TYPE} ne "telnet" || $h->{SNAME});
    next if($attr{$d}{SSL} || AttrVal($d, "allowfrom", "127.0.0.1") ne "127.0.0.1");
    next if($h->{DEF} !~ m/^\d+( global)?$/);
    next if($h->{DEF} =~ m/IPV6/);
    my %cDev = ( SNAME=>$d, TYPE=>$h->{TYPE}, NAME=>$d.time() );
    next if(Authenticate(\%cDev, undef) == 2);    # Needs password
    $hash->{telnetPort} = $defs{$d}{"PORT"};
    last;
 }

 return $name."|no telnet port without password found" if (!$hash->{telnetPort}); 

 my $port = AttrVal($name,"sip_port","5060");
 $port += 10;
 $ua = undef;
 my $error = SIP_Register($hash,$port);
 return $name."|ListenRegister: $error" if ($error);

 my $msg = AttrVal($name, "sip_audiofile", "");

 $hash->{dtmf} = 0;
 #$ua->listen(init_media => $ua->rtp( 'recv_echo' ), cb_dtmf => \&SIP_dtmf); # echo everything back

 
 if (AttrVal($name,"sip_listen", "none") eq "dtmf")
 {
     $hash->{dtmf} = 0;
     $ua->listen(init_media =>  $ua->rtp( 'recv_echo' ), # echo everything back
                   cb_dtmf  => \&SIP_dtmf ,
                   filter   => \&SIP_filter, 
                  #recv_bye => \&SIP_bye
                  ) 
 } 
 elsif (AttrVal($my_name,"sip_listen", "none") eq "wfp")
 {
   $ua->listen(
	cb_invite => \&SIP_invite, 
	filter    => \&SIP_filter, 
	recv_bye  => \&SIP_bye,
        init_media => ($msg) ? $ua->rtp('send_recv', $msg) : $ua->rtp( 'recv_echo' ),
        asymetric_rtp => 0,
        rtp_param => [8, 160, 160/8000, 'PCMA/8000']
	); # options are invite and hangup
 }
 else { return $name."|end"; }  
 $ua->loop;
 $ua->cleanup;
 return $name."|end";
} 

sub SIP_dtmf{
  my ($event,$dur) = @_;
  my $hash         = $defs{$my_name};
  if ($event eq "#")
  {
    $hash->{dtmf} = 1;
    $hash->{old}  = $event;
    return;
  }
  if (($event ne $hash->{old}) && $hash->{dtmf})
  {
   $hash->{dtmf} ++;
   $hash->{dtmf_event} .= $event;
   $hash->{old} = $event;
   if ($hash->{dtmf} > 2)
   {
      SIP_telnet($hash,"set $my_name dtmf_event ".$hash->{dtmf_event});
      $hash->{dtmf}       = 0;
      $hash->{dtmf_event} = "";
      $hash->{old}        ="-";
   }
  }
 return;
}

sub SIP_invite{
  my ($a,$b,$c,$d) = @_;
  my $hash         = $defs{$my_name};
  my $waittime     = AttrVal($my_name, "sip_waittime", "10");
  my $action;
  my $i=0;

  for($i=0; $i<$waittime; $i++) 
  {
   sleep 1;
   ######## $$$ read state of my device
   $action = SIP_telnet($hash,"get $my_name caller\n");
   Log3 $my_name, 4,  "$my_name, SIP_invite ->ringing $i : $action";
   if ( $action eq "fetch" ) { last; }
   #$call->bye();
  }
  return;
}

sub SIP_filter{
  my ($a,$b) = @_;
  my $hash   = $defs{$my_name};
  my ($caller,undef)  = split("\;", $a);
  $caller =~ s/\"//g;
  $caller =~ s/\>//g;
  $caller =~ s/\<//g; # fhem mag keine <> in ReadingsVal :(
  $caller = "???" if (!$caller);
 
  SIP_telnet($hash, "set $my_name caller $caller\nexit\n");
  Log3 $my_name, 5, "$my_name, SIP_filter : a:$a | b:$b";
  return 1;
}

sub SIP_bye{
  my ($event) = @_;
  my $hash    = $defs{$my_name};
  Log3 $my_name, 5,  "$my_name, SIP_bye : $event";
  #print Dumper($event);
  SIP_telnet($hash, "set $my_name caller hangup\nexit\n");
  return 1;
}

sub SIP_ListenDone($)
{
  my ($string) = @_;
  return unless(defined($string));

  my @r = split("\\|",$string);
  my $hash = $defs{$r[0]};
  my $ret = (defined($r[1])) ? $r[1] : "unknow error";
  my $name = $hash->{NAME};

  Log3 $name, 5,"$name, ListenDone -> $string";
  
  delete($hash->{helper}{LISTEN_PID});
  delete $hash->{LPID};
  RemoveInternalTimer($hash);

  if ($ret ne "end")
  { 
   readingsBeginUpdate($hash);
   readingsBulkUpdate($hash,"state","error");
   readingsBulkUpdate($hash,"last_error",$ret);
   readingsEndUpdate($hash, 1 );
   Log3 $name, 3 , "$name, listen error -> $ret";
   return if(IsDisabled($name));
   InternalTimer(gettimeofday()+AttrVal($name, "sip_waits", 60), "SIP_try_listen", $hash, 0);
  }
  else 
  { 
   readingsSingleUpdate($hash,"state","ListenDone",1);
   return if(IsDisabled($name));
   return if(!AttrVal($name, "sip_dtmf", 0));
   SIP_try_listen($hash); 
  }
  return;
}

sub SIP_try_listen($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $waits  = AttrVal($name, "sip_waits", 60);

  $hash->{helper}{LISTEN_PID} = BlockingCall("SIP_ListenStart",$name, "SIP_ListenDone") unless(exists($hash->{helper}{LISTEN_PID}));

  if ($hash->{helper}{LISTEN_PID})
  {
    $hash->{LPID} = $hash->{helper}{LISTEN_PID}{pid};
    Log3 $name, 4 , $name.", Listen new PID : ".$hash->{LPID};
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$waits, "SIP_watch_listen", $hash, 0); # starte die Überwachung
    my $state = "listen_for_".AttrVal($name,"sip_listen",undef);
    readingsSingleUpdate($hash, "state", $state, 1);
    return 0;
  }
  else 
  {
    Log3 $name, 2 , $name.", Listen Start failed, waiting $waits seconds for next try";
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$waits, "SIP_try_listen", $hash, 0);
    return "Listen Start failed";
  }
}

sub SIP_watch_listen($)
{
  # Lebt denn der Listen Prozess überhaupt noch ? 
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);
  return if (IsDisabled($name));
  return if (!defined($hash->{LPID}));

  my $waits  = AttrVal($name, "sip_waits", 60);
  my $cmd    = "ps -e | grep '".$hash->{LPID}." '";
  my $result = qx($cmd); 

  if  (index($result,"perl") == -1)
  {
   Log3 $name, 2 , $name.", cant find listen prozess ".$hash->{LPID}." in process list !";
   BlockingKill($hash->{helper}{LISTEN_PID});
   delete $hash->{helper}{LISTEN_PID};
   delete $hash->{LPID};
   InternalTimer(gettimeofday()+2, "SIP_try_listen", $hash, 0);
  }
  else { Log3 $name, 5 , $name.", listen prozess ".$hash->{LPID}." found"; }

  InternalTimer(gettimeofday()+$waits, "SIP_watch_listen", $hash, 0);
  return;
}


sub SIP_telnet($$)
{
  my ($hash,$cmd) = @_;
  Log3 $my_name, 5,  "$my_name, telnet : $cmd";

  my $sock  = IO::Socket::INET->new(
              PeerHost => "127.0.0.1",
              PeerPort => $hash->{telnetPort},
              Proto    => 'tcp',
              Timeout  => 2);
  if ($sock)
 {
      print $sock "$cmd";
      if (substr($cmd,0,3) eq "get") 
      {
         while (<$sock>)  { last if $_ ; } # end of output
         #$_ =~ s/.* //; # ?? warum ?
         $_ =~ s/\n//;
         print $sock "exit\n";
      }
      close($sock);
      return $_;
 } 
 return undef;
}

1;

=pod
=item helper
=item summary    SIP device
=item summary_DE SIP Ger&auml;t
=begin html

<a name="SIP"></a>
<h3>SIP</h3>
<ul>

  Define a SIP-Client device. 
  <br><br>

  <a name="SIPdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SIP</code>
    <br><br>

    Example:
    <ul>
      <code>define MySipClient SIP</code><br>
    </ul>
  </ul>
  <br>

  <a name="SIPset"></a>
  <b>Set</b>
  <ul>
   <li>
    <code>set &lt;name&gt; reset</code><br>
    Stop any listen process and initialize device.<br>
   </li>
   <li>
    <code>set &lt;name&gt; call &lt;number&gt [&lt;ringtime&gt] [&lt;message&gt]</code><br>
    Start a call to the given number.<br>
    Optionally you can supply a ringtime. If not given the value from attribute sip_ringtime is taken. Default is 10.
    Optionally you can supply a message which is either a full path to an audio file or a relativ path starting from the home directory of the fhem.pl.
   </li>
   <li>
    <code>set &lt;name&gt; listen</code><br>
    attr sip_listen = dtmf :<br>
    Start a listening process that receives calls. The device goes into an echo mode when a call comes in. If you press # on the keypad followed by 2 numbers and hang up the reading <b>dtmf</b> will reflect that number.<br>
    attr sip_listen = wfp :<br>
    Start a listening process that waits for incoming calls. If a call comes in for the SIP-Client the state will change to <b>ringing</b>. If you manually set the state to <b>fetch</b> the call will be picked up and the sound file given in attribute sip_audiofile will be played to the caller. After that the devive will go gack into state <b>listenwfp</b>.<br>
   </li>

  </ul>
  <br>

  <a name="SIPattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#sip_audiofile">sip_audiofile</a><br>
      Audio file that will be played after <b>fetch</b> command. The audio file has to be generated via <br>
      sox &lt;file&gt;.wav -t raw -r 8000 -c 1 -e a-law &lt;file&gt;.alaw<br>
      since only raw audio format is supported. 
      </li>
    <li><a href="#sip_listen">sip_listen</a>(none , dtmf , wfp)</li>
    <li><a name="#sip_from">sip_from</a><br>
      My sip client info, defaults to sip:620@fritz.box
      </li>
    <li><a name="#sip_ip">sip_ip</a><br>
      IP address of my FHEM server.
      </li>
    <li><a name="#sip_port">sip_port</a><br>
      Port used for sip client, defaults to 5060 and will be automatically increased by 10 if not available.
      </li>
    <li><a name="#sip_registar">sip_registar</a><br>
      Hostname or IP address of the SIP server you are connecting to, defaults to fritz.box.
      </li>
    <li><a name="#sip_ringtime">sip_ringtime</a><br>
      Ringtime for outgoing calls
      </li>
    <li><a name="#sip_user">sip_user</a><br>
      User name of the SIP client, defaults to 620.  
      </li>
    <li><a name="#sip_waits">sip_waits</a><br>
      ...  
      </li>
    <li><a name="#sip_waittime">sip_waittime</a><br>
       Maximum waiting time in state listen_for_nwfp it will wait to pick up the call.  
      </li>
  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="SIP"></a>
<h3>SIP</h3>
<ul>

  Definiert ein SIP-Client Device.
  <br><br>

  <a name="SIPdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SIP</code>
    <br><br>

    Beispiel:
    <ul>
      <code>define MySipClient SIP</code><br>
    </ul>
  </ul>
  <br>

  <a name="SIPset"></a>
  <b>Set</b>
  <ul>
   <li>
    <code>set &lt;name&gt; reset</code><br>
    Stoppt laufende listen-Prozess und initalisiert das Device.<br>
   </li>
   <li>
    <code>set &lt;name&gt; call &lt;nummer&gt [&lt;ringtime&gt] [&lt;nachricht&gt]</code><br>
    Startet einen Anruf an die angegebene Nummer.<br>
    Optional kann die ringtime angegeben werden. Wird keine angegeben zieht das Attribut sip_ringtime. Default ist 10.<br>
    Optional kann eine Nachricht in Form eines Audiofiles angegeben werden . Das File ist mit dem vollen Pfad oder dem relativen ab dem Verzeichnis mit fhem.pl anzugeben..
   </li>
   <li>
    <code>set &lt;name&gt; listen</code><br>
    Attribut sip_listen = dtmf :
    Der SIP-Client wird in einen Status versetzt in dem er Anrufe annimmt. Der Ton wird als Echo zurückgespielt. Über die Eingabe von # gefolgt von 2 unterschiedlichen Zahlen und anschließendem Auflegen kann eine Zahl in das Reading <b>dtmf</b> übergeben werden.<br>
    Attribut sip_listen = wfp :
    Der SIP-Client wird in einen Status versetzt in dem er auf Anrufe wartet. Erfolgt an Anruf an den Client, wechselt der Status zu <b>ringing</b>. Nun kann das Gespräch via set-Command <b>fetch</b> angenommen werden. Das als sip_audiofile angegebene File wird abgespielt. Anschließend wechselt der Status wieder zu <b>listenwfp</b>.<br>
   </li>
  </ul>
  <br>

  <a name="SIPattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#sip_audiofile">sip_audiofile</a><br>
      Audiofile das nach dem Command <b>fetch</b> abgespielt wird. Das Audiofile muss mit folgendem Command erzeugt werden<br>
      sox &lt;file&gt;.wav -t raw -r 8000 -c 1 -e a-law &lt;file&gt;.alaw<br>
      da nur das raw audio format unterstützt wird. 
</li>
    <li><a href="#sip_listen">sip_listen</a> (none , dtmf, wfp)</li>
    <li><a name="#sip_from">sip_from</a><br>
      Meine SIP-Client-Info. Default ist sip:620@fritz.box
      </li>
    <li><a name="#sip_ip">sip_ip</a><br>
      Die IP-Addresse meines FHEM-Servers.
      </li>
    <li><a name="#sip_port">sip_port</a><br>
      Port der für den SIP-Client genutzt wird. Default ist 5060 und wird automatisch um 10 erhöht wenn der Port nicht frei ist.
      </li>
    <li><a name="#sip_registar">sip_registar</a><br>
      Hostname oder IP-Addresse des SIP-Servers mit dem sich der Client verbindet. Default ist fritz.box.
      </li>
    <li><a name="#sip_ringtime">sip_ringtime</a><br>
      Klingelzeit für ausgehende Anrufe.
      </li>
    <li><a name="#sip_user">sip_user</a><br>
      User Name des SIP-Clients. Default ist 620.
      </li>
    <li><a name="#sip_waits">sip_waits</a><br>
      ...
      </li>
    <li><a name="#sip_waittime">sip_waittime</a><br>
       Maximale Wartezeit im Status listen_for_wfp bis das Gespräch automatisch angenommen wird.
      </li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
