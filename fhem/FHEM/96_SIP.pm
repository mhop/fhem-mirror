###############################################################################
#
# $Id$
# 96_SIP.pm 
# Based on FB_SIP from  werner.meines@web.de
#
# Forum : https://forum.fhem.de/index.php/topic,67443.0.html
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

use POSIX qw( strftime );
use Net::SIP qw//;
use Net::SIP::Packet;
use IO::Socket;
use Socket;
use Net::Domain qw(hostname hostfqdn);
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call
#use Data::Dumper;

my $sip_version ="V1.61 / 30.10.17";
my $ua;	# SIP user agent
my @fifo;

my %sets = (
   "call"         => "",
   "listen:noArg" => "",
   "reject:noArg" => "",
   "reset:noArg"  => "",
   "fetch:noArg"  => "",
   "password"     => ""
   );


sub SIP_Initialize($$)
{
  my ($hash) = @_;

  $hash->{DefFn}        = "SIP_Define";
  $hash->{UndefFn}      = "SIP_Undef";
  $hash->{ShutdownFn}   = "SIP_Undef";
  $hash->{SetFn}        = "SIP_Set";
  $hash->{GetFn}        = "SIP_Get";
  $hash->{NotifyFn}     = "SIP_Notify";
  $hash->{AttrFn}       = "SIP_Attr";
  $hash->{AttrList}     = "sip_watch_listen ".   #
                          "sip_ringtime ".       #
                          "sip_waittime ".       # 
                          "sip_ip ".             #
                          "sip_port ".           #
                          "sip_user ".           #
                          "sip_registrar ".      #
                          "sip_from ".           #
                          "sip_call_audio_delay:0,0.25,0.5,0.75,1,1.25,1.5,1.75,2,2.25,2.5,2.75,3 ". #
                          "sip_audiofile_call ". #
                          "sip_audiofile_dtmf ". #
                          "sip_audiofile_ok ".   #
                          "sip_audiofile_wfp ".  # CE
                          "sip_dtmf_size:1,2,3,4 ".  #
                          "sip_dtmf_send:audio,rfc2833 ". #
                          "sip_dtmf_loop:once,loop ".     #
                          "sip_listen:none,dtmf,wfp,echo ". #
                          "sip_filter ".                  #
                          "sip_blocking ".                #
                          "sip_elbc:yes,no ".             #
                          "sip_force_interval ".          #
                          "T2S_Device ".                  #
                          "T2S_Timeout ".                 #
                          "audio_converter:sox,ffmpeg ".  #
                          "disabled:0,1 ".$readingFnAttributes;
}						

sub SIP_Define($$) 
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = shift @a;
  my $addr = "0.0.0.0";

  $hash->{STATE}              = "defined"; 	
  $hash->{VERSION}            = $sip_version;
  $hash->{NOTIFYDEV}          = "global";
  $hash->{".reset"}           = 0;
  $attr{$name}{sip_ringtime}  = '3'         unless (exists($attr{$name}{sip_ringtime}));
  $attr{$name}{sip_user}      = '620'       unless (exists($attr{$name}{sip_user}));
  $attr{$name}{sip_registrar} = 'fritz.box' unless (exists($attr{$name}{sip_registrar}));
  $attr{$name}{sip_listen}    = 'none'      unless (exists($attr{$name}{sip_listen}));
  $attr{$name}{sip_dtmf_size} = '2'         unless (exists($attr{$name}{sip_dtmf_size}));
  $attr{$name}{sip_dtmf_loop} = 'once'      unless (exists($attr{$name}{sip_dtmf_loop}));
  $attr{$name}{sip_dtmf_send} = 'audio'     unless (exists($attr{$name}{sip_dtmf_send}));
  $attr{$name}{sip_elbc}      = 'yes'       unless (exists($attr{$name}{sip_elbc}));
  $attr{$name}{sip_from}      = 'sip:'.$attr{$name}{sip_user}.'@'.$attr{$name}{sip_registrar} unless (exists($attr{$name}{sip_from}));
 
  unless (exists($attr{$name}{sip_ip})) 
  {
   eval { $addr = inet_ntoa(scalar(gethostbyname(hostfqdn()))); };
   if ($@)
   {
    Log3 $name,2,"$name, please check your FQDN hostname -> $@";
    eval { $addr = inet_ntoa(scalar(gethostbyname(hostname()))); };
    Log3 $name,2,"$name, please check your hostname -> ".$@ if ($@);
   }
   $attr{$name}{sip_ip} = $addr; 
  }

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+5, "SIP_updateConfig", $hash);
  return undef;
}

sub SIP_Notify($$) 
{
  # $hash is my hash, $dev_hash is the hash of the changed device
  my ($hash, $dev_hash) = @_;
  my $events = deviceEvents($dev_hash,0);

  return undef if ($dev_hash->{NAME} ne AttrVal($hash->{NAME},"T2S_Device",""));
  my $val = ReadingsVal($dev_hash->{NAME},"lastFilename","");
  return undef if ((!$val) || (index(@{$events}[0],"lastFilename") == -1));

   if (defined($hash->{audio1}) || 
       defined($hash->{audio2}) || 
       defined($hash->{audio3}) ||
      (defined($hash->{callnr}) && defined($hash->{ringtime})))
      { SIP_wait_for_t2s($hash);}
  
  return undef;
}

sub SIP_Attr (@) 
{

 my ($cmd, $name, $attrName, $attrVal) = @_;
 my $hash  = $defs{$name};
 #Log3 $name,5,"$name , SIP_Attr : $cmd, $attrName, $attrVal";

 if ($cmd eq "set")
 {
   if (substr($attrName ,0,4) eq "sip_") 
   {
     $_[3] = $attrVal;
     $hash->{".reset"} = 1 if defined($hash->{LPID});
   }
   elsif (($attrName eq "disable") && ($attrVal == 1))
   {
     readingsSingleUpdate($hash,"state","disabled",1);
     $_[3] = $attrVal;
     $hash->{".reset"} = 1 if defined($hash->{LPID});
   }
   elsif ($attrName eq "audio_converter")
   {
      my $res = qx(which $attrVal);
      $res =~ s/\n//;
      $hash->{AC} = ($res) ? $res : undef;
   }
   elsif ($attrName eq "T2S_Device")
   {
    $_[3] = $attrVal;
    $hash->{NOTIFYDEV} = $attrVal;
   }

 }
 elsif ($cmd eq "del")
 {
   if (substr($attrName,0,4) eq "sip_")
   {
     $_[3] = $attrVal;
     $hash->{".reset"} = 1 if defined($hash->{LPID});
   } 
   elsif ($attrName eq "audio_converter")
   {
    $_[3] = $attrVal;
    delete $hash->{AC};
   }
   elsif ($attrName eq "T2S_Device")
   {
    $_[3] = $attrVal;
    delete $hash->{NOTIFYDEV};
   }

 }

 if ($hash->{".reset"})
 {
  Log3 $name,5,"$name , SIP_Attr : reset";
  InternalTimer(gettimeofday()+1,"SIP_updateConfig",$hash);
 }
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
	InternalTimer(gettimeofday()+5,"SIP_updateConfig", $hash);
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
            readingsSingleUpdate($hash,"listen_alive","no",1);
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

    my $t2s = AttrVal($name,"T2S_Device",undef);
    $hash->{NOTIFYDEV}    = $t2s if defined($t2s);

    if (AttrVal($name,"audio_converter","") && defined($t2s))
    {
       my $converter = AttrVal($name,"audio_converter","");
       my $res = qx(which $converter);
       $res =~ s/\n//;
       $hash->{AC} = ($res) ? $res : undef;
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
       readingsBulkUpdate($hash,"listen_alive","no");
      readingsEndUpdate($hash, 1 );
      return undef;
     }
    }
    else 
    { 
      readingsBeginUpdate($hash);
       readingsBulkUpdate($hash,"state","initialized");
       readingsBulkUpdate($hash,"listen_alive","no");
      readingsEndUpdate($hash, 1 );
    }
  return undef;
}
    

sub SIP_Register($$$)
{
  my ($hash,$port,$type) = @_;
  my $name    = $hash->{NAME};
  $hash->{LPID} = $$;
  my $logname = $name."[".$hash->{LPID}."]";
  my $ip      = AttrVal($name,"sip_ip","");
  return "missing attribute sip_ip" if (!$ip);
  return "this is the IP address of your registrar , not your FHEM !" if ($ip eq AttrVal($name,"sip_registrar","")); 
  return "invalid IP address $ip" if (($ip eq "0.0.0.0") || ($ip eq "127.0.0.1")); 

  my $leg = IO::Socket::INET->new(Proto => 'udp', LocalHost => $ip, LocalPort => $port);

  # if  port is already used try another one
  if (!$leg) 
  {
   Log3 $name,2,"$logname, cannot open port $port at $ip: $!";
   $port += 10;
   $leg = IO::Socket::INET->new(
        Proto => 'udp',
    LocalHost => $ip,
    LocalPort => $port) || return "can't open port ".($port-10)." or $port at $ip: $!";
    Log3 $name,2,"$logname, using secundary port $port with IP $ip";
  }

  close($leg);
  $leg = $ip.":".$port;
  
  my $registrar = AttrVal($name,"sip_registrar","fritz.box");
  my $user      = AttrVal($name,"sip_user","620");
  my $from      = AttrVal($name,"sip_from","sip:".$user."@".$registrar);   

  # create new agent
  $ua = Net::SIP::Simple->new(
        registrar => $registrar,
           domain => $registrar,
              leg => $leg,
             from => $from,
             auth => [ $user , SIP_readPassword($name) ]);
  # Register agent

  # optional registration
  my $sub_register;
  $sub_register = sub 
  {
	my $expire = $ua->register(registrar => $registrar ) || return "registration failed: ".$ua->error;
        my $cmd    = "ps -e | grep '".$hash->{parent}." '";
        my $result = qx($cmd); 
        if  (index($result,"perl") == -1)
        {
          Log3 $name,1,"$logname, can´t find my parent ".$hash->{parent}." in process list !";
          die;
        }
    	
        Log3 $name,4,"$logname, register new expire : ".FmtDateTime(time()+$expire);
    
        if (AttrVal($name,"sip_listen","none") ne "none")
        { SIP_telnet($hash,"set $name state $type\nset $name listen_alive PID_".$hash->{LPID}."\nset $name expire $expire\nexit\n"); }
        else
        { SIP_telnet($hash,"set $name state $type\nexit\n"); }
	# need to refresh registration periodically
	$ua->add_timer( $expire/2, $sub_register );
  };

  $sub_register->();

  if($ua->register) # returned  expires time or undef if failed
  {
   return 0;
  }

  my $ret = ($ua->error) ? $ua->error : "registration error"; 
  return $ret;

}			

sub SIP_CALLStart($)
{
  my ($arg) = @_;
  return unless(defined($arg));
  my ($name,$nr,$ringtime,$msg,$repeat) = split("\\|",$arg);
  my $hash              = $defs{$name};
  my $logname           = $name."[".$$."]";
     $hash->{telnetPort}= undef;
     $ua                = undef;
  my $rtp_done          = 0;
  my $dtmf              = 'ABCD*#123--4567890';
  my $port              = AttrVal($name,"sip_port",0);
  my $delay             = AttrVal($name,"sip_call_audio_delay",0); # Verzoegerung in 1/4 Sekunden Schritten 
  my $w                 = ($delay) ? -1 : 0;
  my $fi                = 0;
     #$repeat            = 0 if (!$repeat); 
  my $packets           = int($delay)*50;
  my $timeout           = 0;
  my $final;
  my $peer_hangup;
  my $peer_hangup2;
  my $stopvar;
  my $state;
  my $no_answer; 
  my $call; 
  my $codec;
  my $call_established;
  my @files;
  my $anz;
  my $stat;
  my $ph_ok = 0;
  my $sound_of_silence = sub 
     {
       return unless $packets-- > 0;
       return chr(0) x 160; # 160 bytes for PCMU/8000 = 1/50 Sekunde Sound
     };

  $hash->{parent} = getppid();
  Log3 $name,4,"$logname, my parent is ".$hash->{parent};

  $hash->{telnetPort} = SIP_telnetPort();
  return $name."|no telnet port without password found" if (!$hash->{telnetPort}); 

  if (!$port)
  { 
   srand $$;
   $port = int(rand(500)+44000); 
   Log3 $name,4,"$logname, using random port $port";
  }

  my $error = SIP_Register($hash,$port,"calling");
  return $name."|0|CallRegister: $error" if ($error);
 
  if ((substr($msg,0,1) ne "-") && $msg)
  {
    $codec = "PCMA/8000" if ($msg =~ /\.al(.+)$/);
    $codec = "PCMU/8000" if ($msg =~ /\.ul(.+)$/);
    return $name."|0|CallStart: please use filetype .alaw (for a-law) or .ulaw (for u-law)" if !defined($codec);


    push @files,$sound_of_silence if ($delay);

    if ($repeat < 0) { $repeat = $repeat * -1; $ph_ok= 1; }

    for(my $i=0; $i<=$repeat; $i++)  { push @files,$msg; }
    $anz = @files; 
    Log3 $name,4,"$logname, CallStart with $anz files - first file : $files[0] - $codec , repeat $repeat";

     $call = $ua->invite( $nr,
     init_media => $ua->rtp('send_recv', $files[0]),
    cb_rtp_done => \$rtp_done,
       cb_final => sub { my ($status,$self,%info) = @_; 
                         $final = $info{code};
                         $stat  = $status;
                         Log3 $name,4,"$logname, cb_final - status : $status" if (!defined($final));
                         Log3 $name,4,"$logname, cb_final - status : $status - final : $final" if (defined($final));
                         if (($status eq "FAIL") && defined($final))
                          {
                            if    (int($final) == 481) { SIP_telnet($hash,"set $name call_state ringing\nexit\n"); }
                            elsif (int($final) == 486) { $fi=1 ; } # Anruf abgelehnt
                          }
                          elsif (($status eq "OK") && !defined($final) && !$call_established) # der Angrufene hat abgenommen
                          {
                            Log3 $name,4, $logname.", call established";
                            SIP_telnet($hash,"set $name call_state established\nexit\n");
                            $call_established++; # nur 1x , bei mehr als einem File kommen wir ofters hier vorbei
                          }
                       },
       recv_bye => \$peer_hangup,
     #ring_time => 5,
   #cb_noanswer => \$no_answer, klappt hier nicht wir gehen ueber add_timer
      rtp_param => [8, 160, 160/8000, $codec]) || return $name."|0|invite failed: ".$ua->error;
  }
   else
  {
    $dtmf = (substr($msg,0,1) eq "-") ? substr($msg,1) : $dtmf; 
    Log3 $name,4,"$logname, CallStart DTMF : $dtmf";
    $delay  = 0; # wenn delay sein muss dann ueber DTMF ----
    $repeat = 0; # keine Wiederholungen
    $call = $ua->invite($nr, 
     init_media => $ua->rtp( 'recv_echo',undef,0 ),
      rtp_param => [0, 160, 160/8000, 'PCMU/8000'],
       cb_final => sub { my ($status,$self,%info) = @_; 
                         $final = $info{code};
                         Log3 $name,4,"$logname, cb_final - Status : $status" if (!defined($final));
                         Log3 $name,4,"$logname, cb_final - status : $status - final : $final" if (defined($final));
                         if (($status eq "FAIL") && defined($final)) 
                         {
                          if    (int($final) == 481) { SIP_telnet($hash,"set $name call_state ringing\nexit\n"); }
                          elsif (int($final) == 486) { $fi=1 };
                         }
                         elsif (($status eq "OK") && !defined($final)) # der Angrufene hat abgenommen
                         {
                          Log3 $name,4, $logname.", call established";
                          SIP_telnet($hash,"set $name call_state established\nexit\n");
                         }
                       },
    #cb_noanswer => \$no_answer,
      #ring_time => 5,  siehe oben -> add_timer
     cb_cleanup => sub {0},
       recv_bye => \$peer_hangup) || return $name."|0|invite failed ".$ua->error;

    if (AttrVal($name,"sip_dtmf_send","audio") eq "audio")
    { $call->dtmf( $dtmf, methods => 'audio', duration => 500, cb_final => \$rtp_done); }
    else  { $call->dtmf( $dtmf,  cb_final => \$rtp_done); }
  }

  return "$name|0|invite call failed ".$call->error if ($call->error);

  Log3 $name,4,"$logname, calling : $nr";
  SIP_telnet($hash,"set $name call_state calling $nr\nexit\n"); 

  #return "$name|1|no answer" if ($no_answer);

  $ua->add_timer($ringtime,\$stopvar);
  $ua->loop( \$stopvar,\$peer_hangup,\$rtp_done,\$fi );

  $timeout = 1 if defined($stopvar); # hat der bereits zugeschlagen ?

  Log3 $name,5,"$logname, 0. Ende des ersten Loops";
  Log3 $name,5,"$logname, 1. rtp_done : $rtp_done"       if defined($rtp_done);
  Log3 $name,5,"$logname, 2. fi : $fi"                   if defined($fi);
  Log3 $name,5,"$logname, 3. timeout : $timeout";
  Log3 $name,5,"$logname, 4. peer_hangup : $peer_hangup" if defined($peer_hangup);
 
  
  # Lebt der Call noch und gibt es ueberhaupt etwas zum wiederholen ?
  while  ( !$peer_hangup && !$peer_hangup2 && !$fi && !$stopvar && $msg && ($anz > 1)) 
  {
    shift(@files); # done with file
    @files || last; # raus hier sobald kein File mehr da ist 
    
    Log3 $name,4,"$logname, next file : $files[0]"  if  defined($files[0]);
    Log3 $name,3,"$logname, opps no file"           if !defined($files[0]);

    # re-invite on current call for next file
    $rtp_done = undef; # wichtig ! u.U. haengen wir hier fest wenn der Anrufer jetzt auflegt
    select(undef, undef, undef, 0.1); # minimale pause

    $call->reinvite(
     init_media => $ua->rtp('send_recv', $files[0]),
      #rtp_param => [0, 160, 160/8000, 'PCMU/8000'], unebeding weglassen ! fuehrt zu Verzerrungen bei der Wiedergabe :(
    cb_rtp_done => \$rtp_done,
       recv_bye => \$peer_hangup2, # FIXME: do we need to repeat this? Wzut : I think so ...
                   ) || return $name."|0|reinvite failed: ".$ua->error;

    $ua->loop( \$rtp_done,\$peer_hangup2,\$peer_hangup,\$stopvar );
    Log3 $name,4,"$logname, loop rtp_done : $rtp_done"       if defined($rtp_done);
    $w++;
 }
 
  $timeout = 1 if defined($stopvar); # nach eventuellen reinvte nochmal testen
  # timeout or dtmf done, hang up
  if ( $timeout || $rtp_done) 
  {
    $stopvar = undef;
    $call->bye( cb_final => \$stopvar );
    $ua->loop( \$stopvar );
  }
 
 
  Log3 $name,5,"$logname, RTP done : $rtp_done"     if defined($rtp_done);
  Log3 $name,5,"$logname, Hangup   : $peer_hangup"  if defined($peer_hangup);
  Log3 $name,5,"$logname, Hangup2  : $peer_hangup2" if defined($peer_hangup2);
  Log3 $name,5,"$logname, Timeout  : $timeout";
  Log3 $name,5,"$logname, Final    : $final"        if defined($final);
  Log3 $name,5,"$logname, while    : $w"            if defined($w);
  Log3 $name,5,"$logname, Status   : $stat"         if defined($stat);

  if (defined($rtp_done))
  {
   if ($rtp_done eq "OK") {return $name."|1|ok";} # kein Audio
   else 
   {
     if (defined($final))
     {
       my $txt;
       $txt = "canceled"  if (int($final) == 486);
       $txt = "no answer" if (int($final) == 487);
       $txt = "declined"  if (int($final) == 603);
       return $name."|1|$txt" if $txt;
     }
     else {return $name."|1|ok" if ($rtp_done !=0);}
   }
  }

  # immer noch kein richtiger Test zur Rueckgabe ?

  $final  = "unknown"     if (!defined($final) && !$timeout);
  $final  = "timeout"     if (!defined($final) && $timeout);
  $final  = "peer hangup" if defined($peer_hangup);
  $final  = "peer_hangup" if defined($peer_hangup2); # ts,ts hat der doch glatt im reinvite noch abgebochen 

  # geben wir doch ok zurueck wenn er sich die Nachricht min 1x angehört hat
  return $name."|1|ok peer hangup" if ($ph_ok && defined($peer_hangup2) && ($stat eq "OK") && ($w>0)); # bei delay 1x mehr !
  return $name."|1|".$final;
}

sub SIP_CALLDone($)
{
   my ($string) = @_;
   return unless(defined($string));

   my @r = split("\\|",$string);
   my $hash    = $defs{$r[0]};
   my $error   = (defined($r[1])) ? $r[1] : "0";
   my $final   = (defined($r[2])) ? $r[2] : "???";
   my $name    = $hash->{NAME};
   my $success = (substr($final,0,2) eq "ok") ? 1 : 0;
   my @a;

   Log3 $name, 4,"$name, CALLDone -> $string";
   
   my $calltime = time() - $hash->{helper}{CALL_START};
   delete($hash->{helper}{CALL_PID}) if (defined($hash->{helper}{CALL_PID}));
   delete($hash->{CPID})             if (defined($hash->{CPID}));
   delete $hash->{lastnr}            if (defined($hash->{lastnr}));
   delete($hash->{helper}{CALL_START}) if (defined($hash->{helper}{CALL_START}));
   
   if ($error ne "1")
   {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "call","done");
    readingsBulkUpdate($hash, "call_time",int($calltime)) if defined($calltime);
    readingsBulkUpdate($hash, "last_error",$final);
    readingsBulkUpdate($hash, "call_state","fail");
    readingsBulkUpdate($hash, "call_success","0");
    readingsBulkUpdate($hash, "state",$hash->{'.oldstate'}) if defined($hash->{'.oldstate'});
    readingsEndUpdate($hash, 1);
   }
   else
   { 
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "call","done");
    readingsBulkUpdate($hash, "call_state",lc($final));
    readingsBulkUpdate($hash, "call_success",$success);
    readingsBulkUpdate($hash, "call_time",int($calltime)) if defined($calltime);
    readingsBulkUpdate($hash, "state",$hash->{'.oldstate'}) if defined($hash->{'.oldstate'});
    readingsEndUpdate($hash, 1);
   }

   my (undef,$nr,$ringtime,$msg,$repeat,$force) = split("\\|",$hash->{CALL}); # zerlegen wir den Original Call

   if ($force && !$success)
    {
     #$repeat = "0" if (!defined($repeat) || ($repeat eq "")) ;
     $repeat++; $repeat--; 
     $force =~ s/^\&//;
     $force++; $force--;

     my $nr2 = $nr;
     $nr2 =~ tr/0-9//cd;

     my $t = ($force) ? $force : int(AttrVal($name,"sip_force_interval",60));

     my $time_s = strftime("\%H:\%M:\%S", gmtime($t));
     $error = CommandDefine(undef, "at_forcecall_".$nr2." at +".$time_s." set $name call $nr $ringtime $msg *".$repeat." &".$t);
     if (!$error) { $attr{"at_forcecall_".$nr2}{room} = AttrVal($name,"room","Unsorted"); } 
     else { Log3 $name,2,"$name, $error"; }
     Log3 $name,4,"$name, at_forcecall_".$nr2." at +".$time_s." set $name call $nr $ringtime $msg *".$repeat." &".$force;
    }
 
   my $nextcall = shift @fifo; # sind da noch Calls in der Queue ?
   if ($nextcall)
    { 
     @a = split(" ",$nextcall);
     $error = SIP_Set($hash,@a); 
     Log3 $name,3,"$name, error setting nextcall $nextcall -> $error" if ($error);
     return undef;
    } else { Log3 $name,5,"$name, fifo is empty"; }
    
   if (exists($hash->{'.elbc'}))
    {
     @a = (undef,"listen"); 
     Log3 $name,4,"$name, try restarting listen process after call ends";
     $error = SIP_Set($hash,@a);
     Log3 $name,3,"$name, error restarting listen -> $error" if ($error);
     delete $hash->{'.elbc'};
    } else { Log3 $name,5,"$name, no elbc"; }

   delete $hash->{CALL};
   return undef;
}

#####################################

sub SIP_Set($@) 
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME}; 
  my $cmd  = (defined($a[1])) ? $a[1] : "?";
  my $subcmd;
  my $ret;

  return join(" ", sort keys %sets) if ($cmd eq "?");

  if (($cmd eq "call") || ($cmd eq "listen"))
  {
   my $pwd = SIP_readPassword($name);
   unless (defined $pwd)  
   {
    my $ret = "Error: no SIP user password set. Please define it with 'set $name password Your_SIP_User_Password'";
    Log3 $name,2,"$name, $ret";
    return $ret;
   }
  }

  if  ($cmd eq "call") 
  {
    my $nr       = (defined($a[2])) ? $a[2] : "";
    my $ringtime = (defined($a[3])) ? $a[3] : 30;
    my $msg      = (defined($a[4])) ? $a[4] : AttrVal($name, "sip_audiofile_call", "");
    return "missing target call number" if (!$nr);
    return "invalid max time : $ringtime" unless $ringtime =~ m/^\d+$/;

    if (exists($hash->{CPID}))
     {
        return "there is already a call activ for target $nr" if (defined($hash->{lastnr}) && ($hash->{lastnr} eq $nr));
        my $call = join(" ",@a); 
        push (@fifo,$call);
        Log3 $name ,4,"$name, add call $call to fifo so we can do it later !";
        return undef;
     }

    my $anz = @a;
    $anz--; # letztes Element
    my $force  = (substr($a[$anz],0,1) eq "&") ? $a[$anz] : 0;
    $anz-- if ($force); # checken wir dann noch auf repeat 
    my $repeat = 0;
    if (substr($a[$anz],0,1) eq "*")
    { 
      $repeat = $a[$anz];
      $repeat =~ s/^\*//;
      $repeat ++; $repeat --;
    } # * weg , Rest als Int
  
    Log3 $name,3,"$name, force call" if ($force);
    Log3 $name,4,"$name, msg will be repeat $repeat times" if ($repeat);

     if (exists($hash->{LPID}) && (AttrVal($name,"sip_elbc","no") ne "no"))
     {
      Log3 $name,4,"$name, listen process ".$hash->{LPID}." must be killed befor we start a new call !";
      BlockingKill($hash->{helper}{LISTEN_PID});
      delete $hash->{helper}{LISTEN_PID};
      delete $hash->{LPID};
      readingsSingleUpdate($hash,"listen_alive","no",1);
      $hash->{'.elbc'} = 1; # haben wir gerade einen listen Prozess abgeschossen ?
     }

    if ($msg)
    {
      if (substr($msg,0,1) eq "-") 
      { 
        Log3 $name, 4, $name.", message DTMF = $msg"; 
      } 
      elsif (substr($msg,0,1) eq "!") # Text2Speech Text ?
      {
       shift @a;
       shift @a;
       $a[0] = "t2s_name"; # ist egal wird eh verworfen
       $a[1] = "tts"; # Kommando des Set Befehls
       $a[2] =~ s/^\!//; # das ! muss weg
       pop @a if ($force); # das & muss ggf. auch noch weg
       pop @a if ($repeat); # das * muss ggf. auch weg

       # die nachsten vier brauchen wir unbedingt fuer T2S
       $hash->{callnr}    = $nr;
       $hash->{ringtime}  = $ringtime;
       $hash->{forcecall} = $force;
       $hash->{repeat}    = $repeat; 

       my $ret = SIP_create_T2S_File($hash,@a); # na dann lege schon mal los
       return $ret if defined($ret); # Das ging leider schief

       readingsSingleUpdate($hash,"call_state","waiting T2S",0);

       RemoveInternalTimer($hash);
       # geben wir T2S mal ein paar Sekunden
       InternalTimer(gettimeofday()+int(AttrVal($name,"T2S_Timeout",5)), "SIP_wait_for_t2s", $hash);
       return undef;
      }
      elsif (-e $msg) 
      { 
        Log3 $name, 4, $name.", audio file $msg found"; 
        return "unknown audio type, please use only .alaw or .ulaw" if (($msg !~ /\.al(.+)$/) && ($msg !~ /\.ul(.+)$/));
      } 
      else
      { 
        $ret = "audio file $msg not found";
        readingsBulkUpdate($hash, "last_error",$ret);
        Log3 $name, 3, "$name, $ret !";
        $hash->{repeat}    = 0;
        $hash->{forcecall} = 0;
        $msg = ""; 
      }
    }
    else { Log3 $name, 4, $name.", calling $nr, ringtime: $ringtime , no message"; }

    $hash->{lastnr} = $nr;
    my $arg = "$name|$nr|$ringtime|$msg|$repeat"; # da muss force nicht mit 
    Log3 $name, 4, "$name, $arg";
    #BlockingCall($blockingFn, $arg, $finishFn, $timeout, $abortFn, $abortArg);
    $hash->{helper}{CALL_PID} = BlockingCall("SIP_CALLStart",$arg, "SIP_CALLDone") unless(exists($hash->{helper}{CALL_PID}));

    if($hash->{helper}{CALL_PID})
    { 
     $hash->{CPID} = $hash->{helper}{CALL_PID}{pid};
     $hash->{CALL} = $arg."|$force"; # hier retten wir aber force
     
     Log3 $name, 4,  "$name, call -> ".$hash->{CALL};
     Log3 $name, 5,  "$name, call has pid ".$hash->{CPID};
     $hash->{helper}{CALL_START} = time();
     readingsBeginUpdate($hash);
     readingsBulkUpdate($hash, "call_state","invite");
     readingsBulkUpdate($hash, "call",$nr);
     readingsEndUpdate($hash, 1);
     $hash->{'.oldstate'} = ReadingsVal($name,"state",undef);
     return undef;
    }
     else  
    { # das war wohl nix :(
      Log3 $name, 3,  "$name, CALL process start failed, arg : $arg"; 
      $ret = "can't execute call number $nr as NonBlockingCall";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "last_error",$ret);
      readingsBulkUpdate($hash, "call_state","fail");
      readingsEndUpdate($hash, 1);
      delete $hash->{lastnr} if (defined($hash->{lastnr}));
      return $ret;
    }
  }
  elsif ($cmd eq "listen")
  {
   my $type = AttrVal($name,"sip_listen","none");
   return "there is already a listen process running with pid ".$hash->{LPID} if exists($hash->{LPID});
   return "please set attr sip_listen to dtmf or wfp or echo first" if (AttrVal($name,"sip_listen","none") eq "none");
   $ret = SIP_try_listen($hash);
   if ($ret)
   { 
    Log3 $name, 1, $name.", listen -> $ret";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","error");
    readingsBulkUpdate($hash,"last_error",$ret);
    readingsBulkUpdate($hash,"listen_alive","no");
    readingsEndUpdate($hash, 1 );
    return $ret;
   }
   return undef;
  }
  elsif (($cmd eq "dtmf_event") && defined($a[2]))
  {
    readingsSingleUpdate($hash, "dtmf",$a[2],1);
    return undef;
  }
  elsif ($cmd eq "fetch")
  {
   readingsSingleUpdate($hash, "caller","fetch",1);
   return undef;
  }
  elsif ($cmd eq "reject")
  {
   readingsSingleUpdate($hash, "caller","reject",1);
   return undef;
  }

  elsif ($cmd eq "reset")
  {
   $hash->{".reset"} = 1;
   SIP_updateConfig($hash);
   return undef;
  }

  # die ersten beiden brauchen wir nicht mehr
  shift @a;
  shift @a;
  # den Rest als ein String
  $subcmd = join(" ",@a);

  if ($cmd eq "state")
  {
   readingsSingleUpdate($hash, "state",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "listen_alive")
  {
   readingsSingleUpdate($hash, "listen_alive",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "expire")
  {
   readingsSingleUpdate($hash, "expire",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "caller")
  {
   readingsSingleUpdate($hash, "caller",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "caller_state")
  {
   readingsSingleUpdate($hash, "caller_state",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "call_state")
  {
   readingsSingleUpdate($hash, "call_state",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "caller_time")
  {
   readingsSingleUpdate($hash, "caller_time",$subcmd,1);
   return undef;
  }
  elsif ($cmd eq "password")
  {
    return SIP_storePassword($name,$subcmd);
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
  #RemoveInternalTimer($hash);
  #RemoveInternalTimer($name);
  return undef;
}


sub SIP_ListenStart($)
{
 my ($name) = @_;
 return unless(defined($name));
 my $logname          = $name."[".$$."]"; 
 my $hash             = $defs{$name}; # $hash / $name gueltig in diesem Block 
 $hash->{parent} = getppid();
 Log3 $name,4,"$logname, my parent is ".$hash->{parent};
 $hash->{telnetPort}  = undef;

 my $dtmfloop;		# Ende-Flag für die DTMF-Schleife
 my $okloop;		# Ende-Flag für die OK-Ansage
 my $okloopbye = 0;	# Ende-Flag für recv_bye währne der OK-Ansage
 my $byebye    = 0;	# Anrufer hat aufgelegt
 my $packets   = 50;
 my $block_it;

 my $sub_create;
 my $sub_invite_wfp;
 my $sub_filter;
 my $sub_bye;
 my $sub_dtmf;
 my $send_something;

 $hash->{telnetPort} = SIP_telnetPort();

 return $name."|no telnet port without password found" if (!$hash->{telnetPort}); 

 my $port = AttrVal($name,"sip_port",0);
 if (!$port)
 {  
   srand $$;
   $port = int(rand(500)+44500);
   Log3 $name,4,"$logname, using random port $port"; 
 }
 else { $port += 10; }
 $ua = undef;
 my $error = SIP_Register($hash,$port,"listen_".AttrVal($name,"sip_listen",""));
 return $name."|ListenRegister: $error" if ($error);
 
 my $msg1 = AttrVal($name, "sip_audiofile_dtmf", "");
 my $msg2 = AttrVal($name, "sip_audiofile_ok",   "");
 my $msg3 = AttrVal($name, "sip_audiofile_wfp",  "");

 $msg1 = $hash->{audio1} if (defined($hash->{audio1}) && $msg1); 
 $msg1 = SIP_check_file($hash,$msg1) if (!defined($hash->{audio1}) && $msg1);;

 $msg2 = $hash->{audio2} if (defined($hash->{audio2}) && $msg2); 
 $msg2 = SIP_check_file($hash,$msg2) if (!defined($hash->{audio2}) && $msg2);;

 $msg3 = $hash->{audio3} if (defined($hash->{audio3}) && $msg3); 
 $msg3 = SIP_check_file($hash,$msg3) if (!defined($hash->{audio3}) && $msg3);;

 Log3 $name,4,"$logname, using $msg1 for audio_dtmf" if ($msg1);
 Log3 $name,4,"$logname, using $msg2 for audio_ok"   if ($msg2);
 Log3 $name,4,"$logname, using $msg3 for audio_wfp"  if ($msg3);

 $hash->{dtmf}       = 0;
 $hash->{dtmf_event} = "";
 $hash->{old}        ="-";

 $send_something = sub 
 {
   return unless $packets-- > 0;
   my $buf = sprintf "%010d",$packets;
   $buf .= "1234567890" x 15;
   return $buf; # 160 bytes for PCMU/8000
 };

 $sub_dtmf = sub 
 {
  my ($event,$dur) = @_;
  Log3 $name,5,"$logname, DTMF Event: $event - $dur ms";
  return if (int($dur) < 100);

  if ($event eq "#")
  {
      $hash->{dtmf}       = 1;
      $hash->{dtmf_event} = "";
      $hash->{old}        = $event;
      return;
  }

  if (($event ne $hash->{old}) && $hash->{dtmf})
  {
   
   $hash->{dtmf} ++;
   $hash->{old} = $event;
   $hash->{dtmf_event} .= $event;
   Log3 $name,5,"$logname, DTMF: ".$hash->{dtmf_event}." , Anz: ".$hash->{dtmf};
   
   if ($hash->{dtmf} > int(AttrVal($name,"sip_dtmf_size",2)))
   {
      SIP_telnet($hash,"set $name dtmf_event ".$hash->{dtmf_event}."\n");
      $hash->{dtmf}       = 0;
      $hash->{dtmf_event} = "";
      $hash->{old}        = "-";
      $dtmfloop           = 1;
   }
  }
  return;
 };

 $sub_create = sub
 {
  my ($call,$request,$leg,$from) = @_;
  $hash->{call}    = $call;
  $hash->{request} = $request;
  $hash->{leg}     = $leg;
  $hash->{from}    = $from;
  Log3 $name,4,"$logname, cb_create : ".$request->method;
  my $response = ($block_it) ? $request->create_response('487','Request Terminated') : $request->create_response('180','Ringing');
  $call->{endpoint}->new_response( $call->{ctx},$response,$leg,$from );
  1;
 };
 
 $sub_invite_wfp = sub 
 {
  my ($a,$b,$c,$d) = @_;
  my $waittime     = int(AttrVal($name, "sip_waittime", 10));
  my $i;
 
  $packets = 50;
  for($i=1; $i<=$waittime; $i++) 
  {
   if ($block_it) #und gleich wieder weg
   {
    sleep int(AttrVal($name, "sip_waittime", 2)); # kleine Pause
    last;
   }

   Log3 $name, 4,"$logname, SIP_invite -> ringing $i";
   SIP_telnet($hash,"set $name caller_state ringing_$i\nexit\n");
   sleep 1;
   ######## $$$ read state of my device
   my $action = SIP_telnet($hash,"get $name caller\n");
   if ( $action eq "fetch" ) 
   { 
    Log3 $name, 4,"$logname, SIP_invite fetch !";
    SIP_telnet($hash,"set $name caller_state fetching\nexit\n");
    last; 
   }
   elsif ( $action eq "reject" ) 
   { 
    Log3 $name, 4,"$logname, SIP_invite block !";
    SIP_telnet($hash,"set $name caller_state rejected\nexit\n");
    
    my $call    = $hash->{call};
    my $request = $hash->{request};
    my $leg     = $hash->{leg};
    my $from    = $hash->{from};

    my $response = $request->create_response('603','Declined');
    $call->{endpoint}->new_response( $call->{ctx},$response,$leg,$from );
 
    last; 
   }


  }
  SIP_telnet($hash, "set $name caller none\nset $name caller_state waiting\nexit\n") if (($i>$waittime) || $block_it);

  return 0;
 };

 $sub_filter = sub 
 {
  my ($a,$b) = @_;
  Log3 $name, 5, "$logname, SIP_filter : a:$a | b:$b";
  $block_it  = 0; # 
 
  my ($caller,undef)  = split("\;", $a);
  my @callers;
  $caller =~ s/\"//g;
  $caller =~ s/\>//g;
  $caller =~ s/\<//g; # fhem mag keine <> in ReadingsVal :(
  $caller = "???" if (!$caller);
  SIP_telnet($hash, "set $name caller $caller\nexit\n");

  my ($callnr,undef)  = split("\@", $caller);
 
  my $block = AttrVal($name,"sip_blocking",undef);
  if (defined($block))
  {
    my @blockers = split (/,/,$block); 
    foreach (@blockers)
    {
     if ((index($callnr, $_) > -1) || ($_ eq ".*"))
     {
       SIP_telnet($hash,"set $name caller_state blocking\nexit\n");
       Log3 $name, 4, "$logname, blocking $callnr found on $block";
       $block_it = 1;
       #$byebye = 1;
     }
    }
  }

  my $filter = AttrVal($name,"sip_filter",undef);
  if (defined($filter))
  {
    @callers = split (/,/,$filter); 
    foreach (@callers) { return 1 if (index($callnr, $_) > -1); }
    SIP_telnet($hash,"set $name caller_state ignoring\nexit\n");
    Log3 $name, 4, "$logname, ignoring $callnr number not found in $filter"; 
    return 0;
  }
  return 1;
 };

 $sub_bye = sub 
 {
  my ($event) = @_;
  Log3 $name, 5,  "$logname, SIP_bye : $event";
  my $calltime = int(time()-$hash->{CALL_START});
  SIP_telnet($hash, "set $name caller none\nset $name caller_state hangup\nset $name caller_time $calltime\nexit\n") ;
  $byebye = 1;
  return 1;
 };

################

 if (AttrVal($name,"sip_listen", "none") eq "dtmf")
 {
     $hash->{dtmf} = 0;
     $dtmfloop     = 0;	# Ende-Flag für die DTMF-Schleife
     $okloop       = 0;	# Ende-Flag für die OK-Ansage
     $okloopbye    = 0;	# Ende-Flag für recv_bye währne der OK-Ansage
     $byebye       = 0;	# Anrufer hat aufgelegt

     while(1)
     {
     my $call;
     $hash->{dtmf}       = 0;
     $hash->{dtmf_event} = "";
     $hash->{old}        ="-";

     SIP_telnet($hash, "set $name caller none\nset $name caller_state waitting\nexit\n") ;

     $ua->listen (cb_create => \&$sub_create,
                  cb_invite =>  sub {
                                     if (!$block_it)
                                     {  
                                      SIP_telnet($hash,"set $name caller_state ringing\nexit\n");
                                      sleep int(AttrVal($name, "sip_ringtime", 3)); #Anrufer hört das typische Klingeln wenn die Gegenseite nicht abnimmt
                                     }
                                    }, 
                   filter   => \&$sub_filter, 
             cb_established => sub { 
                                     (my $status,$call) = @_; 
                                     if (!$block_it)
                                          { 
                                             $hash->{CALL_START} = time();
                                             SIP_telnet($hash,"set $name caller_state established\nexit\n"); return 1; 
                                          } 
                                     else { 
                                            sleep 1;
                                            #SIP_telnet($hash, "set $name caller none\nset $name caller_state waitting\nexit\n") ;
                                            return 0; } 
                                   } # sobald invite verlassen wird, wird in cb_established verzweigt
              ); 
     
     $ua->loop(\$call);
     # Der SIP-Client ist jetzt im echo-Modus und zwar so lange, bis der Anrufer auflegt, 
     # das bekommen wir durch recv_bye mit

     my $dtmf_loop = 1; # für jeden Anruf neu setzen

      while ($dtmf_loop) # Schleife für Code-Ansage, DTMF-Erkennung, okay-Ansage
      {
       $dtmfloop  = 0;
       $okloop    = 0;
       $okloopbye = 0;

       $call->reinvite( 
        init_media => $ua->rtp('send_recv',($msg1) ? $msg1 : $send_something),
         rtp_param => [8, 160, 160/8000, 'PCMA/8000'],
       cb_rtp_done => sub { $packets = 25; },
           cb_dtmf => \&$sub_dtmf,
          recv_bye => \&$sub_bye,
         );

       $ua->loop(\$dtmfloop, \$byebye);

       if (!$byebye) 
       { # Anrufer hat nicht aufgelegt
        $call->reinvite(
        init_media => $ua->rtp('send_recv',($msg2) ? $msg2 : $send_something),
         rtp_param => [8, 160, 160/8000, 'PCMA/8000'],
       cb_rtp_done => sub { select(undef, undef, undef, 0.1); $okloop = 1; $packets = 50;},
          recv_bye => sub { $okloopbye = 1; },
        cb_cleanup => sub {0},
        );

        $ua->loop(\$okloop,\$okloopbye);   # ohne diese loop endet der Anruf sofort
       } 
       else { $dtmf_loop = 0; }  # Schleife beenden, Anrufer hat aufgelegt

       if ( ( defined $okloopbye && $okloopbye ) || $byebye ) 
       { # wenn jemand mitten im "okay" auflegt 
         $dtmf_loop = 0; # beende die inner loop 
         $byebye    = 1;
       } 
        else { $dtmf_loop = ((AttrVal($name,"sip_dtmf_loop","once") eq 'once')) ? 0 : 1;
               my $calltime = int(time()-$hash->{CALL_START});
               SIP_telnet($hash, "set $name caller_state hangup\nset $name caller_time $calltime\nexit\n") if(!$dtmf_loop);
             } # führt ggf. zum Schleifenende
     } # end inner loop

     if (!$byebye) 
     {		     # Anrufer hat nicht aufgelegt und nur ein DTMF angefordert
      my $hanguploop;
      $call->bye( cb_final => \$hanguploop );
      $ua->loop( \$hanguploop );
     }
   } # while(1)
 }
 elsif (AttrVal($name,"sip_listen", "none") eq "wfp")
 {
   $ua->listen(
          cb_create => \&$sub_create,
	  cb_invite => \&$sub_invite_wfp,
     cb_established => sub { $hash->{CALL_START} = time(); },  
	     filter => \&$sub_filter, 
	   recv_bye => \&$sub_bye,
         init_media => $ua->rtp('send_recv',($msg3) ? $msg3 : $send_something),
        #cb_rtp_done => sub { $packets = 50; return 1;},
          rtp_param => [8, 160, 160/8000, 'PCMA/8000']
	); # options are invite and hangup
  }
 elsif (AttrVal($name,"sip_listen", "none") eq "echo")
 {
   $ua->listen(
                  filter => \&$sub_filter,
               cb_create => \&$sub_create,
               cb_invite =>  sub {
                                  if (!$block_it)
                                  {  
                                   SIP_telnet($hash,"set $name caller_state ringing\nexit\n");
                                   sleep int(AttrVal($name, "sip_ringtime", 3)); #Anrufer hört das typische Klingeln wenn die Gegenseite nicht abnimmt
                                  }
                                 }, 
          cb_established => sub { $hash->{CALL_START} = time(); },
              init_media => $ua->rtp( 'recv_echo',undef,0 ),
               rtp_param => [8, 160, 160/8000, 'PCMA/8000'],
                recv_bye => \&$sub_bye,
              );
 }
 else { return $name."|end"; }  

 $ua->loop;
 return $name."|end"; # hier sollten wir eigentlich nie himkommen !
} 


sub SIP_ListenDone($)
{
  my ($string) = @_;
  return unless(defined($string));

  my @r = split("\\|",$string);
  my $hash = $defs{$r[0]};
  my $ret = (defined($r[1])) ? $r[1] : "unknown error";
  my $name = $hash->{NAME};

  Log3 $name, 5,"$name, ListenDone -> $string";
  
  delete($hash->{helper}{LISTEN_PID});
  delete $hash->{LPID};
  RemoveInternalTimer($name);

  if ($ret ne "end")
  { 
   readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","error");
    readingsBulkUpdate($hash,"last_error",$ret);
    readingsBulkUpdate($hash,"listen_alive","no");
   readingsEndUpdate($hash, 1 );
   Log3 $name, 3 , "$name, listen error -> $ret";
   return if(IsDisabled($name));
   InternalTimer(gettimeofday()+AttrVal($name, "sip_watch_listen", 60), "SIP_try_listen", $hash);
  }
  else 
  { 
   readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"state","ListenDone");
    readingsBulkUpdate($hash,"listen_alive","no");
   readingsEndUpdate($hash, 1 );
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
  my $waits  = AttrVal($name, "sip_watch_listen", 60);
  my $audio1 = AttrVal($name, "sip_audiofile_dtmf","-");
  my $audio2 = AttrVal($name, "sip_audiofile_ok",  "-");
  my $audio3 = AttrVal($name, "sip_audiofile_wfp", "-");
  my @a = ("tts","tts", "-");;
  
  if (AttrVal($name,"sip_listen","none") eq "dtmf")
  {
   if ((substr($audio1,0,1) eq "!") && !defined($hash->{audio1})) # muss erst T2S gefragt werden ?
    { 
     $audio1 =~ s/^\!//;
     $hash->{audio1} = $audio1;
     $a[2] = $audio1;
     Log3 $name ,4,"$name, hole $audio1";
    }
    elsif ((substr($audio2,0,1) eq "!") && !defined($hash->{audio2})) # muss erst T2S gefragt werden ?
    {
     $audio2 =~ s/^\!//;
     $hash->{audio2} = $audio2;
     $a[2] = $audio2;
     Log3 $name ,4,"$name, hole $audio2";
    }
  }
  elsif ((substr($audio3,0,1) eq "!") && !defined($hash->{audio3}) && (AttrVal($name,"sip_listen","none") eq "wfp")) # muss erst T2S gefragt werden ?
  {
   $audio3 =~ s/^\!//;
   $hash->{audio3} = $audio3;
   $a[2] = $audio3;
   Log3 $name ,4,"$name, hole $audio3";
  }

  if ($a[2] ne "-")
  {
    my $ret = SIP_create_T2S_File($hash,@a);
    if ($ret)
    {
      delete $hash->{audio1} if defined($hash->{audio1});
      delete $hash->{audio2} if defined($hash->{audio2});
      delete $hash->{audio3} if defined($hash->{audio3});
      return $ret;
    }
    #starte die Überwachung von T2S
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+int(AttrVal($name,"T2S_Timeout",5)), "SIP_watchdog_T2S", $hash);
    return undef;
  }


  $hash->{helper}{LISTEN_PID} = BlockingCall("SIP_ListenStart",$name, "SIP_ListenDone") unless(exists($hash->{helper}{LISTEN_PID}));

  if ($hash->{helper}{LISTEN_PID})
  {
    $hash->{LPID} = $hash->{helper}{LISTEN_PID}{pid};
    Log3 $name, 4 , $name.", Listen new PID : ".$hash->{LPID};
    RemoveInternalTimer($name);
    InternalTimer(gettimeofday()+$waits, "SIP_watch_listen", $name); # starte die Überwachung
    delete $hash->{audio1};
    delete $hash->{audio2};
    delete $hash->{audio3};
    return 0;
  }
  else 
  {
    Log3 $name, 2 , $name.", Listen Start failed, waiting $waits seconds for next try";
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$waits, "SIP_try_listen", $hash);
    return "Listen Start failed";
  }
}

sub SIP_watch_listen($)
{
  # Lebt denn der Listen Prozess überhaupt noch ? 
  my ($name) = @_;
  my $hash   = $defs{$name};
  my $listen_dead = 0;
  RemoveInternalTimer($name);
  return if (IsDisabled($name));
  return if (!defined($hash->{LPID}));

  my $cmd    = "ps -e | grep '".$hash->{LPID}." '";
  my $result = qx($cmd); 
  
  my $age    = int(ReadingsAge($name, "expire", 0));
  my $maxage = int(ReadingsNum($name,"expire",300)*0.7);
  my $alive  = ReadingsVal($name,"listen_alive","no");
  my $waits  = AttrVal($name, "sip_watch_listen", 60);

  if (($age > $maxage) && ($alive ne "no")) # nach  expire/2  Sekunden sollte sich der listen Prozess erneut melden
  { 
   Log3 $name, 2 , "$name, expire timestamp is $age seconds old, restarting listen process";
   readingsSingleUpdate($hash,"listen_alive","no",1);
   $alive = "no";
  }
  elsif  (index($result,"perl") == -1)
  {
   Log3 $name, 2 , $name.", cant find listen process ".$hash->{LPID}." in process list !";
   $alive = "no";;
  }
  else { Log3 $name, 5 , $name.", listen process ".$hash->{LPID}." found"; }

  if ($alive eq "no")
  {
   BlockingKill($hash->{helper}{LISTEN_PID});
   delete $hash->{helper}{LISTEN_PID};
   delete $hash->{LPID};
   InternalTimer(gettimeofday()+2, "SIP_try_listen", $hash, 0);
  }

  InternalTimer(gettimeofday()+$waits, "SIP_watch_listen", $name, 0);
  return;
}

sub SIP_wait_for_t2s($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  RemoveInternalTimer($hash);

  my $t2s_name = AttrVal($name,"T2S_Device",undef);
  my $file     = ReadingsVal($t2s_name,"lastFilename","");
  my $msg      = "";
  Log3 $name,4,"$name, wait_for_t2s file : $file";

  if ($file)
  {
   Log3 $name,4,"$name, new T2S file $file";
 
   my $out = $file;
   $out  =~ s/mp3/alaw/;
   if (-e $out)
   { 
     Log3 $name,5,"$name, not converted using $out from cache";
     $msg = $out; 
   } 
    else
   {    
    my $ret;
    my $cmd;
    my $converter = AttrVal($name,"audio_converter","sox");
    if (($converter eq "sox") && defined($hash->{AC}))
    {
     $cmd = $hash->{AC}." ".$file." -t raw -r 8000 -c 1 -e a-law ".$out;
     Log3 $name,5,"$name, $cmd";
     $_ = qx($cmd);
    }
    elsif (($converter eq "ffmpeg") && defined($hash->{AC}))
    {
     $cmd = $hash->{AC}." -v quiet -y -i ".$file." -f alaw -ar 8000 ".$out;
     Log3 $name,5,"$name, $cmd";
     $_ = qx($cmd);
    }


    if ($_)
     {
      Log3 $name,4,"$name, $converter : $_ , $?";
      readingsSingleUpdate($hash,"last_error","$converter error $_",1);
     }
     else { $msg = $out; }
   }
  }        
  else
  {
   Log3 $name,3,"$name, timeout waiting for T2S";
   readingsSingleUpdate($hash,"call_state","T2S timeout",1);
  }
   
  if ($msg && defined($hash->{audio3}))
  {
     $hash->{audio3} = $msg;
     SIP_try_listen($hash);
     return undef;
  }

  if ($msg && defined($hash->{audio2}))
  {
     $hash->{audio2} = $msg;
     SIP_try_listen($hash);
     return undef;
  }

  if ($msg && defined($hash->{audio1}))
  {
     $hash->{audio1} = $msg;
     SIP_try_listen($hash);
     return undef;
  }

  # nun aber calling
  my $repeat =  "*".$hash->{repeat};

  my @a;
  if ($hash->{forcecall})  
  { @a = ($name,"call",$hash->{callnr}, $hash->{ringtime},$msg,$repeat,$hash->{forcecall}) ; }
  else
  { @a = ($name,"call",$hash->{callnr}, $hash->{ringtime},$msg,$repeat) ; }

  delete($hash->{callnr});
  delete($hash->{ringtime});
  delete($hash->{forcecall});
  delete($hash->{repeat});
  my $ret = SIP_Set($hash , @a);
  Log3 $name,3,"$name, error T2S Call : $ret" if defined($ret);
  return undef;
}

sub SIP_telnetPort()
{
 foreach my $d (sort keys %defs) 
 {  
    my $h = $defs{$d};
    next if(!$h->{TYPE} || $h->{TYPE} ne "telnet" || $h->{SNAME});
    next if($attr{$d}{SSL} || AttrVal($d, "allowfrom", "127.0.0.1") ne "127.0.0.1");
    next if($h->{DEF} !~ m/^\d+( global)?$/);
    next if($h->{DEF} =~ m/IPV6/);
    my %cDev = ( SNAME=>$d, TYPE=>$h->{TYPE}, NAME=>$d.time() );
    next if(Authenticate(\%cDev, undef) == 2);    # Needs password
    #$hash->{telnetPort} = $defs{$d}{"PORT"};
    #last;
    return $defs{$d}{"PORT"};
 }
 return 0;
}

sub SIP_telnet($$)
{
  my ($hash,$cmd) = @_;
  my $name        = $hash->{NAME};
  my $logname     = $name."[".$$."]";
  my $txt         = $cmd;
  $txt            =~ s/\n/ /g;
  Log3 $name, 5,  "$logname, telnet : $txt";

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
######################################################
# storePW & readPW Code geklaut aus 72_FRITZBOX.pm :)
######################################################
sub SIP_storePassword($$)
{
    my ($name, $password) = @_;
    my $index = "SIP_".$name."_passwd";
    my $key   = getUniqueId().$index;
    my $e_pwd = "";
    
    if (eval "use Digest::MD5;1")
    {
        $key  = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $e_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }

    my $error = setKeyValue($index, $e_pwd);
    return "error while saving SIP user password : $error" if(defined($error));
    return "SIP user password successfully saved in FhemUtils/uniqueID Key $index";
} 

sub SIP_readPassword($)
{
   my ($name) = @_;
   my $index  = "SIP_".$name."_passwd";
   my $key    = getUniqueId().$index;

   my ($password, $error);

   #Log3 $name,5,"$name, read SIP user password from FhemUtils/uniqueID Key $key";
   ($error, $password) = getKeyValue($index);

   if ( defined($error) ) 
   {
      Log3 $name,3, "$name, cant't read SIP user password from FhemUtils/uniqueID: $error";
      return undef;
   }  
    
   if ( defined($password) ) 
   {
      if (eval "use Digest::MD5;1") 
      {
         $key  = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }

      my $dec_pwd = '';
     
      for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) 
      {
         my $decode=chop($key);
         $dec_pwd.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
      return $dec_pwd;
   }
   else 
   {
      Log3 $name,3,"$name, no SIP user password found in FhemUtils/uniqueID";
      return undef;
   }
} 
   
##################################### 

 sub SIP_check_file($$)
 {
   my ($hash,$file) = @_;
   my $name        = $hash->{NAME};
   my $logname     = $name."[".$$."]";

   if (substr($file,0,1) eq "!")
   {
    Log3 $name,3,"$logname, Text : $file found, ignoring it";
    return "";
   }
   if (!-e $file)
   {
    Log3 $name,3,"$logname, audio file $file not found, ignoring it";
    return "";
   }
   if (($file !~ /\.al(.+)$/) && ($file !~ /\.ul(.+)$/))
   {
    Log3 $name,3,"$logname, audio file $file not type .alaw or .ulaw, ignoring it";
    return "";
   }
   return $file;
 }

 sub SIP_create_T2S_File($@)
 {
   my ($hash,@a) = @_;
   my $name        = $hash->{NAME};
 
   my $t2s_name = AttrVal($name,"T2S_Device",undef);
   return "attr T2S_Device not set !" if !defined($t2s_name);
   my $t2s_hash = $defs{$t2s_name};
   return "T2S_Device $t2s_name not found" if !defined($t2s_hash);

   return "attr audio_converter not set" if !AttrVal($name,"audio_converter","");
   return "external sox or ffmpeg programm not found, please install sox or ffmpeg first and set attr audio_converter" if !defined($hash->{AC});

   my $t2s_file = ReadingsVal($t2s_name,"lastFilename",undef);
   Log3 $name,3,"$name, Reading lastFilename not found at device $t2s_name, are you using a old version ?" if !defined($t2s_file);

   readingsSingleUpdate($t2s_hash,"lastFilename","",0);

   my $ret = Text2Speech_Set($t2s_hash, @a); # na dann lege schon mal los
   if (defined($ret))
   {
    Log3 $name,3,"$name, T2S error : $ret"; 
    readingsSingleUpdate($hash,"last_error",$ret,0);
    return $ret; # Das ging leider schief
   }

  return undef; # alles klar
 }

 sub SIP_watchdog_T2S($)
 {
   my ($hash) = @_;
   my $name   = $hash->{NAME};
   Log3 $name,3,"$name, Timeout waiting for T2S";

   if (defined($hash->{audio1}))
   {
    $hash->{audio1}="!T2S Timeout";
    SIP_try_listen($hash);
    return undef;
   }

   if (defined($hash->{audio2}))
   {
    $hash->{audio2}="!T2S Timeout";
    SIP_try_listen($hash);
    return undef;
   }

   if (defined($hash->{audio3}))
   {
    $hash->{audio3}="!T2S Timeout";
    SIP_try_listen($hash);
    return undef;
   }
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
    <code>set &lt;name&gt; &lt;SIP password&gt;</code><br>
    Stores the password for the SIP users. Without stored password the functions set call and set listen are blocked !<br>
    IMPORTANT : if you rename the fhem Device you must set the password again!
   </li>
   <li>
    <code>set &lt;name&gt; reset</code><br>
    Stop any listen process and initialize device.<br>
   </li>
   <li>
    <code>set &lt;name&gt; call &lt;number&gt [&lt;maxtime&gt;] [&lt;message&gt;]</code><br>
    Start a call to the given number.<br>
    Optionally you can supply a max time. Default is 30.
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
    <li><a href="#sip_audiofile_wfp">sip_audiofile_wfp</a><br>
      Audio file that will be played after <b>fetch</b> command. The audio file has to be generated via <br>
      sox &lt;file&gt;.wav -t raw -r 8000 -c 1 -e a-law &lt;file&gt;.al<br>
      since only raw audio format is supported. 
      </li>
     <li><a href="#sip_audiofile_call">sip_audiofile_call</a></li>
     <li><a href="#sip_audiofile_dtmf">sip_audiofile_dtmf</a></li>
     <li><a href="#sip_audiofile_ok">sip_audiofile_ok</a></li>
    <li><a href="#sip_listen">sip_listen</a>(none , dtmf , wfp)</li>
    <li><a name="#sip_from">sip_from</a><br>
      My sip client info, defaults to sip:620@fritz.box
      </li>
    <li><a name="#sip_ip">sip_ip</a><br>
      external IP address of the FHEM server.
      </li>
    <li><a name="#sip_port">sip_port</a><br>
      Optionally portnumber used for sip client<br>
      If attribute is not set a random port number between 44000 and 45000 will be used
      </li>
    <li><a name="#sip_registrar">sip_registrar</a><br>
      Hostname or IP address of the SIP server you are connecting to, defaults to fritz.box.
      </li>
    <li><a name="#sip_ringtime">sip_ringtime</a><br>
      Ringtime for incomming calls (dtmf &wfp)
      </li>
    <li><a name="#sip_user">sip_user</a><br>
      User name of the SIP client, defaults to 620.
      </li>
    <li><a name="#sip_waittime">sip_waittime</a><br>
       Maximum waiting time in state listen_for_wfp it will wait to pick up the call.  
      </li>
    <li><a name="#sip_dtmf_size">sip_dtmf_size</a><br>
    1 to 4 , default is 2      ...
    </li>
    <li><a name="#sip_dtmf_loop">sip_dtmf_loop</a><br>
    once or loop , default once      ...
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
    <code>set &lt;name&gt; &lt;SIP Passwort&gt;</code><br>
    Speichert das Passwort des SIP Users. Ohne gespeichertes Passwort sind die set call und set listen Funktionen gesperrt !<br>
    WICHTIG : wird das SIP Device umbenannt muss dieser Befehl unbedingt wiederholt werden !
   </li>
   <li>
    <code>set &lt;name&gt; reset</code><br>
    Stoppt laufende listen-Prozess und initalisiert das Device.<br>
   </li>
   <li>
    <code>set &lt;name&gt; call &lt;nummer&gt; [&lt;maxtime&gt;] [&lt;nachricht&gt;]</code><br>
    Startet einen Anruf an die angegebene Nummer.<br>
    Optional kann die maximale Zeit angegeben werden. Default ist 30.<br>
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
    <li><a name="#sip_user">sip_user</a><br>
       User Name des SIP-Clients. Default ist 620 (Fritzbox erstes SIP Telefon) 
    </li>
    <li><a name="#sip_registrar">sip_registrar</a><br>
      Hostname oder IP-Addresse des SIP-Servers mit dem sich das Modul verbinden soll. (Default fritz.box)
      </li>
    <li><a name="#sip_from">sip_from</a><br>
      SIP-Client-Info. Syntax : sip:sip_user@sip_registrar Default ist sip:620@fritz.box
     </li>
    <li><a name="#sip_ip">sip_ip</a><br>
      Die IP-Addresse von FHEM im Heimnetz. Solange das Attribut nicht gesetzt ist versucht das Modul diese beim Start zu ermitteln.
      </li>
    <li><a name="#sip_port">sip_port</a><br>
      Optinale Portnummer die vom Modul benutzt wird.<br>
      Wenn dem Attribut kein Wert zugewiesen wurde verwendet das Modul eine zuf&auml;llige Portnummer zwichen 44000 und 45000
      </li>
  
     <li><b>Audiofiles</b>
      Audiofiles k&ouml;nnen einfach mit dem externen Programm sox erzeugt werden :<br>
      sox &lt;file&gt;.wav -t raw -r 8000 -c 1 -e a-law &lt;file&gt;.al<br>
      Unterst&uuml;tzt werden nur die beiden RAW Audio Formate a-law und u-law !<br>
      Statt eines echten Audiofiles kann auch eine Text2Speech Nachricht eingetragen werden.<br>
      Bsp : attr mySIP sip_audiofile_call !Hier ist dein FHEM Server
     </li>
    <li><a href="#sip_audiofile_wfp">sip_audiofile_wfp</a><br>
      Audiofile das nach dem Command <b>fetch</b> abgespielt wird. 
    </li>
    <li><a href="#sip_audiofile_call">sip_audiofile_call</a></li>
    Audiofile das dem Angerufenen bei set call vorgespielt wird.
    <li><a href="#sip_audiofile_dtmf">sip_audiofile_dtmf</a></li>
    Audiofile das dem Anrufer bei listen_for_dtmf abgespielt wird.
    <li><a href="#sip_audiofile_ok">sip_audiofile_ok</a></li>
    Audiofile das bei erkannter DTMF Sequenz abgespielt wird.
    <li><a href="#sip_listen">sip_listen</a> (none , dtmf, wfp)</li>
    <li><a name="#sip_ringtime">sip_ringtime</a><br>
      Klingelzeit für eingehende Anrufe bei listen_for_dtmf 
      </li>
    <li><a name="#sip_dtmf_size">sip_dtmf_size</a><br>
    1 bis 4 , default 2 Legt die L&auml;ge des erwartenden DTMF Events fest.
    </li>
    <li><a name="#sip_dtmf_loop">sip_dtmf_loop</a><br>
    once oder loop , default once      ...
    </li>
    <li><a name="#sip_waittime">sip_waittime</a><br>
       Maximale Wartezeit im Status listen_for_wfp bis das Gespr&auml;ch automatisch angenommen wird.
      </li>
    <li>T2S_Device<br>
    Name des Text2Speech Devices (Wird nur ben&ouml;tigt wenn Sprachnachrichten statt Audiofiles verwendet werden)
    </li>
     <li>T2S_Timeout<br>
     Wartezeit in Sekunden wie lange maximal auf Text2Speech gewartet wird.
     </li>
    <li>audo_converter<br>sox oder ffmpeg, default sox<br>
     Ist f&uml;r Text2Speech unbedingt erforderlich um die mp3 Dateien in Raw Audio umzuwandeln.<br>
     Installation z.B. mit sudo apt-get install sox und noch die mp3 Unterst&uuml;tzung mit sudo apt-get install libsox-fmt-mp3
    </li>
  </ul>
  <br>

</ul>

=end html_DE

=cut
