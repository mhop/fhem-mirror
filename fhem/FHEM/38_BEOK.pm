################################################################
#
#  $Id$
#
#  (c) 2019 Copyright: Wzut
#  All rights reserved
#
#  FHEM Forum : https://forum.fhem.de/index.php/topic,80703.msg891666.html#msg891666
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

# based on Broadlink Python script at https://github.com/ralphm2004/broadlink-thermostat
# Broadlink protocol parts are stolen from 38_Broadlink.pm :) , THX to daniel2311

package main;
use strict;
use warnings;
use SetExtensions;
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call
use Time::Local;
use IO::Socket::INET;
use IO::Select;

my $version = 'V1.11 / 05.02.19';

my %gets = ('status:noArg' => '', 'auth:noArg' =>'' , 'temperature:noArg' => '');

sub BEOK_Initialize($) 
{
    my ($hash) = @_;

    $hash->{DefFn}        = 'BEOK_Define';
    $hash->{UndefFn}      = 'BEOK_Undef';
    $hash->{ShutdownFn}   = 'BEOK_Undef';
    $hash->{SetFn}        = 'BEOK_Set';
    $hash->{GetFn}        = 'BEOK_Get';
    $hash->{AttrFn}       = 'BEOK_Attr';
    $hash->{FW_summaryFn} = 'BEOK_summaryFn';
    $hash->{AttrList}     = 'interval timeout disable:0,1 timesync:0,1 language model:BEOK,Floureon,Hysen,unknown '.$readingFnAttributes;
}

sub BEOK_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    my $name = $hash->{NAME};

    eval "use Crypt::CBC";
    return "please install Crypt::CBC first"          if ($@);
    eval "use Crypt::OpenSSL::AES";
    return "please install Crypt::OpenSSL::AES first" if ($@);
    eval "use MIME::Base64";
    return "please install MIME::Base64 first"        if ($@);
    return "wrong syntax: define <name> BEOK <ip> [<mac>]" if(int(@param) < 2);

    $hash->{'.ip'} = $param[2];
    $hash->{'MAC'} = (defined($param[3])) ? $param[3] : 'de:ad:be:ef:08:15';

    $hash->{'.key'} = pack('C*', 0x09, 0x76, 0x28, 0x34, 0x3f, 0xe9, 0x9e, 0x23, 0x76, 0x5c, 0x15, 0x13, 0xac, 0xcf, 0x8b, 0x02);
    $hash->{'.iv'}  = pack('C*', 0x56, 0x2e, 0x17, 0x99, 0x6d, 0x09, 0x3d, 0x28, 0xdd, 0xb3, 0xba, 0x69, 0x5a, 0x2e, 0x6f, 0x58);
    $hash->{'.id'}  = pack('C*', 0, 0, 0, 0);

    $hash->{'counter'}   = 1;
    $hash->{'isAuth'}    = 0;
    $hash->{'lastCMD'}   = '';
    $hash->{'TIME'}      = gettimeofday();
    $hash->{VERSION}     = $version;
    $hash->{ERRORCOUNT}  = 0;
    $hash->{weekprofile} = "none";
    $hash->{CmdStack}    = ();
    $hash->{'.CmdStack'} = 0;

    # wird mit dem ersten Full Status ueberschrieben
    $hash->{helper}{power}       = 0;
    $hash->{helper}{remote_lock} = 0;
    $hash->{helper}{loop_mode}   = 0;
    $hash->{helper}{SEN}         = 0;
    $hash->{helper}{OSV}         = 0;
    $hash->{helper}{dIF}         = 0;
    $hash->{helper}{SVH}         = 0;
    $hash->{helper}{SVL}         = 0;
    $hash->{helper}{AdJ}         = 0;
    $hash->{helper}{FrE}         = 0; 
    $hash->{helper}{PoM}         = 0;
    $hash->{helper}{0}{temp}     = 10;
    $hash->{helper}{0}{time}     = '05:00';
    $hash->{helper}{1}{temp}     = 15;
    $hash->{helper}{1}{time}     = '08:00';
    $hash->{helper}{2}{temp}     = 20;
    $hash->{helper}{2}{time}     = '11:00';
    $hash->{helper}{3}{temp}     = 25;
    $hash->{helper}{3}{time}     = '12:00';
    $hash->{helper}{4}{temp}     = 30;
    $hash->{helper}{4}{time}     = '17:00';
    $hash->{helper}{5}{temp}     = 35;
    $hash->{helper}{5}{time}     = '22:00';
    $hash->{helper}{6}{temp}     = 40;
    $hash->{helper}{6}{time}     = '08:00';
    $hash->{helper}{7}{temp}     = 45;
    $hash->{helper}{7}{time}     = '23:00';

    CommandAttr(undef,$name.' devStateIcon on:on off:off close:secur_locked open:secur_open hon:on hoff:off') unless (exists($attr{$name}{devStateIcon}));
    CommandAttr(undef,$name.' interval 60')     unless (exists($attr{$name}{interval}));
    CommandAttr(undef,$name.' timeout 5')       unless (exists($attr{$name}{timeout}));
    CommandAttr(undef,$name.' timesync 1')      unless (exists($attr{$name}{timesync}));
    CommandAttr(undef,$name.' model unknown')   unless (exists($attr{$name}{model}));

    readingsSingleUpdate($hash,'state','defined',1);
    return undef;
}

sub BEOK_Undef($$) 
{
 my ($hash, $arg) = @_; 
 RemoveInternalTimer($hash);
 if(defined($hash->{helper}{RUNNING_PID}))
 {
  BlockingKill($hash->{helper}{RUNNING_PID});
 }
 return undef;
}

sub BEOK_update($) 
{
 my ($hash) = @_; 
 my $name   = $hash->{NAME};

 RemoveInternalTimer($hash);
 my $interval      = AttrVal($name,'interval',60);
 $hash->{INTERVAL} = $interval;
 $hash->{MODEL}    = AttrVal($name,'model','unknown');

 if ($interval)
 {
  InternalTimer(gettimeofday()+int($interval), "BEOK_update", $hash,0);

  return if (!$init_done || IsDisabled($name));

  if ((time()-($interval*5)) > $hash->{TIME}) { readingsSingleUpdate($hash,'alive','no',1);}

  CommandGet(undef,$name.' auth')   if (!$hash->{isAuth});
  CommandGet(undef,$name.' status') if  ($hash->{isAuth});
 }
 return undef;
}

sub BEOK_Get($@) 
{
 my ($hash, @a) = @_;
 my $name= $hash->{NAME};
 my $ret;
 my $cmd = $a[1];

 return 'get '.$name.' needs at least one argument' if(int(@a) < 2);
 return $name.' get with unknown argument '.$cmd.', choose one of ' . join(' ', sort keys %gets) if (($cmd ne 'status') && ($cmd ne 'auth') && ($cmd ne 'temperature')); 

 $hash->{'.CmdStack'}  = 0;

 if ($cmd eq 'auth') 
 {
   return 'device auth key already stored' if ($hash->{isAuth});

   my @payload = ((0x00) x 80);
   $payload[0x04] = 0x31;
   $payload[0x05] = 0x31;
   $payload[0x06] = 0x31;
   $payload[0x07] = 0x31;
   $payload[0x08] = 0x31;
   $payload[0x09] = 0x31;
   $payload[0x0a] = 0x31;
   $payload[0x0b] = 0x31;
   $payload[0x0c] = 0x31;
   $payload[0x0d] = 0x31;
   $payload[0x0e] = 0x31;
   $payload[0x0f] = 0x31;
   $payload[0x10] = 0x31;
   $payload[0x11] = 0x31;
   $payload[0x12] = 0x31;
   $payload[0x1e] = 0x01;
   $payload[0x2d] = 0x01;
   $payload[0x30] = ord('T');
   $payload[0x31] = ord('e');
   $payload[0x32] = ord('s');
   $payload[0x33] = ord('t');
   $payload[0x34] = ord(' ');
   $payload[0x35] = ord(' ');
   $payload[0x36] = ord('1');

   $hash->{lastCMD} = 'get auth';
 
   $ret = BEOK_send_packet($hash, 0x65, @payload);
 }
 elsif (($cmd eq 'status') || ($cmd eq 'temperature'))
 {
    return 'you must run get '.$name.' auth first !' if (!$hash->{isAuth});

  if ($cmd eq 'status')
  {
   my @payload = (1,3,0,0,0,22);

   $hash->{lastCMD} = 'get status';
   $ret = BEOK_send_packet($hash, 0x6a, @payload);
  }
  elsif ($cmd eq 'temperature') 
  {
   # Get current external temperature in degrees celsius
   # [0x01,0x03,0x00,0x00,0x00,0x08]
   # return payload[5] / 2.0
   # return payload[18] / 2.0

   my @payload = (1,3,0,0,0,8);

   $hash->{lastCMD} = 'get temperature';

   $ret = BEOK_send_packet($hash, 0x6a, @payload);
  }
 }

 return $ret;
}

sub BEOK_Set(@) 
{
  my ($hash, $name , @a) = @_;
  my $cmd        = $a[0]; 
  my $subcmd     = (defined $a[1]) ? $a[1] : "";
  my $ret;
  my @payload;
  my $len;

  Log3 $name,4,"BEOK set $name $cmd $subcmd" if (($cmd ne '?') && $subcmd);

  my $cmdList  = "desired-temp off:noArg on:noArg mode:auto,manual loop:12345.67,123456.7,1234567 ";
  $cmdList    .= " sensor:external,internal,both time:noArg active:noArg inactive:noArg lock:on,off";
  $cmdList    .= " power-on-memory:on,off fre:open,close room-temp-adj:";

  for (my $i=-10;$i<9;$i++) {$cmdList .= sprintf('%.1f',$i/2).',';}

  $cmdList .= "4.5,5.0 osv svh svl dif:1,2,3,4,5,6,7,8,9 weekprofile";

  for (my $i=1;$i<7;$i++) {$cmdList .= " day-profile".$i."-temp day-profile".$i."-time";}
  for (my $i=7;$i<9;$i++) {$cmdList .= " we-profile".$i."-temp we-profile".$i."-time";}


 if ($cmd eq '?') { return SetExtensions($hash,$cmdList,$name,@a); }

 if ($subcmd) { Log3 $name,5,"BEOK set $name $cmd $subcmd"; }
 else  { Log3 $name,5,"BEOK set $name $cmd"; }

 return 'no set commands allowed, auth key and device id are missing ! ( need run get auth first )' if (!$hash->{isAuth});

 $hash->{'.CmdStack'} = 0;

 if (($cmd eq 'inactive') && !IsDisabled($name)) 
 {
  readingsSingleUpdate($hash,'state','inactive',1); 
  BEOK_Undef($hash,undef);
 }
 elsif (($cmd eq 'active') && IsDisabled($name)) 
 {
  readingsSingleUpdate($hash,'state','active',1); 
  BEOK_Update($hash); 
 }
 elsif (($cmd eq 'on') || ($cmd eq 'off') || ($cmd eq 'lock'))
 {
  # Set device on(1) or off(0), does not deactivate Wifi connectivity
  #[0x01,0x06,0x00,0x00,remote_lock,power]

  $hash->{helper}{power}       = 1 if ($cmd  eq 'on');
  $hash->{helper}{power}       = 0 if ($cmd  eq 'off');
  $hash->{helper}{remote_lock} = 1 if (($cmd eq 'lock') && ($subcmd eq "on" ));
  $hash->{helper}{remote_lock} = 0 if (($cmd eq 'lock') && ($subcmd eq "off"));

  @payload = (1,6,0,0,$hash->{helper}{remote_lock},$hash->{helper}{power});

  readingsSingleUpdate($hash,'state','set_'.$cmd,0)   if ($cmd ne 'lock');
  readingsSingleUpdate($hash,'look','set_'.$subcmd,0) if ($cmd eq 'lock');

  $hash->{lastCMD} = 'set '.$cmd;
  $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif (($cmd eq "mode") || ($cmd eq "sensor") || ($cmd eq "loop"))
 {
  # mode_byte = ( (loop_mode + 1) << 4) + auto_mode
  # [0x01,0x06,0x00,0x02,mode_byte,sensor

  $hash->{helper}{'auto_mode'} = ($subcmd eq "auto") ? 1 : 0 if ($cmd eq "mode");

  # Sensor control option | 0:internal sensor 1:external sensor 2:internal control temperature, external limit temperature

    if ($cmd eq 'sensor')
    {
     $hash->{helper}{SEN} = 2 if ($subcmd eq "both");
     $hash->{helper}{SEN} = 0 if ($subcmd eq "internal");
     $hash->{helper}{SEN} = 1 if ($subcmd eq "external");
    }

    # loop_mode refers to index in [ "12345,67", "123456,7", "1234567" ]
    # E.g. loop_mode = 0 ("12345,67") means Saturday and Sunday follow the "weekend" schedule
    # loop_mode = 2 ("1234567") means every day (including Saturday and Sunday) follows the "weekday" schedule
 
    if ($cmd eq 'loop')
    {
     $hash->{helper}{'loop_mode'} = 2 if ($subcmd eq "1234567");
     $hash->{helper}{'loop_mode'} = 0 if ($subcmd eq "12345.67");
     $hash->{helper}{'loop_mode'} = 1 if ($subcmd eq "123456.7");
    }

    @payload = (1,6,0,2);
    push @payload , (($hash->{helper}{'loop_mode'} << 4) + $hash->{helper}{'auto_mode'});
    push @payload , $hash->{helper}{'SEN'};

    readingsSingleUpdate($hash,$cmd,'set_'.$subcmd,0);

    $hash->{lastCMD} = "set $cmd $subcmd";
    $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif (($cmd eq "power-on-memory") || ($cmd eq "fre") || ($cmd eq "room-temp-adj") 
     || ($cmd eq "osv") || ($cmd eq "svh") || ($cmd eq "svl") || ($cmd eq "dif"))
 {
  # 1 | SEN | Sensor control option | 0:internal sensor 1:external sensor 2:internal control temperature, external limit temperature 
  # 2 | OSV | Limit temperature value of external sensor | 5-99C 
  # 3 | dIF | Return difference of limit temperature value of external sensor | 1-9C 
  # 4 | SVH | Set upper limit temperature value | 5-99C 
  # 5 | SVL | Set lower limit temperature value | 5-99C 
  # 6 | AdJ | Measure temperature | Measure temperature,check and calibration | 0.1C precision Calibration (actual temperature)
  # 7 | FrE | Anti-freezing function | 0:anti-freezing function shut down 1:anti-freezing function open
  # 8 | PoM | Power on memory | 0:Power on no need memory 1:Power on need memory
  #  set_advanced(loop_mode, sensor, osv, dif, svh, svl, adj, fre, poweron):
  #  input_payload = bytearray([0x01,0x10,0x00,0x02,0x00,0x05,0x0a, 
  #                             loop_mode, sensor, osv, dif, 
  #                             svh, svl, (int(adj*2)>>8 & 0xff), (int(adj*2) & 0xff), 
  #                             fre, poweron])

  $hash->{helper}{PoM} = 1 if ( ($cmd eq 'power-on-memory') && ($subcmd eq 'off') );
  $hash->{helper}{PoM} = 0 if ( ($cmd eq 'power-on-memory') && ($subcmd eq 'on') );
  $hash->{helper}{FrE} = 1 if ( ($cmd eq 'fre')             && ($subcmd eq 'open') );
  $hash->{helper}{FrE} = 0 if ( ($cmd eq 'fre')             && ($subcmd eq 'close') );

  $hash->{helper}{SVH} = int($subcmd) if ( ($cmd eq 'svh') && (int($subcmd) > 4) && (int($subcmd) < 100));
  $hash->{helper}{SVL} = int($subcmd) if ( ($cmd eq 'svl') && (int($subcmd) > 4) && (int($subcmd) < 100));
  $hash->{helper}{OSV} = int($subcmd) if ( ($cmd eq 'osv') && (int($subcmd) > 4) && (int($subcmd) < 100));
  $hash->{helper}{dIF} = int($subcmd) if ( ($cmd eq 'dif') && (int($subcmd) > 0) && (int($subcmd) < 10));

  if ($cmd eq 'room-temp-adj')
  {
    my $temp = int($subcmd*2);
    if (($temp   >=  0 ) && ($temp <=  10)) { $hash->{helper}{AdJ} = $temp; }
    elsif (($temp  < 0 ) && ($temp >= -10)) { $hash->{helper}{AdJ} = 0x10000 + $temp; }
  }

  # WICHTIG : Loop Mode und Auto Mode werden sonst mit geändert !
  $hash->{helper}{'loop_mode'} = (($hash->{helper}{'loop_mode'} << 4) + $hash->{helper}{'auto_mode'});

  @payload = (0x01,0x10,0x00,0x02,0x00,0x05,0x0a,
             $hash->{helper}{loop_mode},
             $hash->{helper}{SEN},
             $hash->{helper}{OSV},
             $hash->{helper}{dIF},
             $hash->{helper}{SVH},
             $hash->{helper}{SVL},
             $hash->{helper}{AdJ}>>8 & 0xff,
             $hash->{helper}{AdJ} & 0xff,
             $hash->{helper}{FrE},
             $hash->{helper}{PoM});

   readingsSingleUpdate($hash,$cmd,'set_'.$subcmd,0);

   $hash->{lastCMD} = "set $cmd $subcmd";
   $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif ($cmd eq "time")
 {

   my ($sec,$min,$hour,undef,undef,undef,$wday,undef,undef) = localtime(gettimeofday());
   $wday = 7 if (!$wday); # Local 0..6 Sun-Sat, Thermo 1..7 Mon-Sun

   @payload = (1,16,0,8,0,2,4, $hour, $min, $sec, $wday);
   Log3 $name,4,"BEOK set $name time $hour:$min:$sec, $wday";
 
   readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'time',"set_$hour:$min:$sec",0);
    readingsBulkUpdate($hash,'dayofweek','set_'.$wday,0);
   readingsEndUpdate($hash,0);

   $hash->{lastCMD} = 'set '.$cmd;
   $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif ($cmd eq "desired-temp")
 {
  return undef if (!$subcmd);

  my $temp = int($subcmd*2);
  return "Temperature must be between 5 and 99" if (($temp < 10) || ($temp > 198));

  @payload             =  (1,6,0,1,0,$temp);  # setzt angeblich auch mode manu
  $hash->{lastCMD}     = "set $cmd $subcmd";
  $hash->{'.CmdStack'} = 1;
  $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif ( $cmd =~ /^(day|we)-profile[1-8]-time$/ )
 {
   return "Time must be between 0:00 and 23:59" if $subcmd !~ /^([0-9]|0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$/; #Uhrzeit
   my $day = $cmd;
   $day =~ s/(day|we)-profile//;
   $day =~ s/-time//;
   $day--;  # 0 - 7
   $hash->{helper}{$day}{time} = $subcmd;

   @payload = BEOK_set_timer_schedule($hash);

   $hash->{lastCMD} = "set $cmd $subcmd";
   $hash->{weekprofile} = "???";
   $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif ( $cmd =~ /^(day|we)-profile[1-8]-temp$/ )
 {
   my $temp = int($subcmd*2);
   return "Temperature must be between 5 and 99" if (($temp < 10) || ($temp > 198));

   my $day = $cmd;
   $day =~ s/(day|we)-profile//;
   $day =~ s/-temp//;
   $day--;
   $hash->{helper}{$day}{temp} = $temp;
   @payload = BEOK_set_timer_schedule($hash);

   readingsSingleUpdate($hash,$cmd,$subcmd,0);

   $hash->{lastCMD} = "set $cmd $subcmd";
   $hash->{weekprofile} = "???";
   $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }
 elsif ($cmd eq 'weekprofile')
 {
    my ($wpd,$wpp,$wpday) = split(":",$subcmd);
    return "use set $name weekprofile <weekday_device_name:profile_name[:day]>" if ((!$wpd) || (!$wpp));
    $wpday= ' ' if(!$wpday);

    eval "use JSON";
    return "please install JSON first"  if ($@);

    my $json = CommandGet(undef,"$wpd profile_data $wpp");
    if (substr($json,0,2) ne "{\"") #} kein JSON , Fehlermeldung FHEM Device nicht vorhanden oder Fehler von weekprofile
    {
     Log3 $name, 2, "BEOK $name, $json";
     readingsSingleUpdate($hash,"error",$json,1);
     return $json;
    }

    my @days = ('Mon','Tue','Wed','Thu','Fri','Sat','Sun');

    my $today = ($wpday eq ' ') ? $days[ (localtime(time))[6] -1 ] : $wpday;
    return "$today is not a valid weekprofile day, please use on of ".join(",",@days) if  !grep {/$today/} @days;

    my $j;

    eval { $j = decode_json($json); 1; } or do 
           {
             $ret = $@;
             Log3 $name, 2, "BEOK $name, $ret";
             readingsSingleUpdate($hash,"error",$ret,1);
             return $ret;
           };

    for (my $i=0;$i<6;$i++)
    {
      if (!defined($j->{$today}{time}[$i]))
      {
       $ret = "Day $today time #".($i+1)." is missing in weekprofile $wpd profile_data $wpp";
       Log3 $name, 2, "BEOK $name, $ret";
       readingsSingleUpdate($hash,"error",$ret,1);
       return $ret;
      }
      else
      {
        if (int(substr($j->{$today}{time}[$i],0,2)) > 23)
        {
          $ret = "Day $today time #".($i+1)." hour ".substr($j->{$today}{time}[$i],0,2)." is invalid";
          Log3 $name, 2, "BEOK $name, $ret";
          readingsSingleUpdate($hash,"error",$ret,1);
          return $ret;
        }
      }

      if (!defined($j->{$today}{temp}[$i])) # eigentlich überflüssig 
      {
       $ret = "Day $today temperature #".($i+1)." is missing in weekprofile $wpd profile_data $wpp";
       Log3 $name, 2, "BEOK $name, $ret";
       readingsSingleUpdate($hash,"error",$ret,1);
       return $ret;
      }

    }

    for (my $i=0;$i<6;$i++)
    {
      $hash->{helper}{$i}{time} = $j->{$today}{time}[$i];
      $hash->{helper}{$i}{temp} = int($j->{$today}{temp}[$i]*2);
    }

   @payload = BEOK_set_timer_schedule($hash);
   $hash->{lastCMD}     = "set $cmd $subcmd";
   $hash->{weekprofile} = "$wpd:$wpp:$today";
   $hash->{'.CmdStack'} = 1;
   $ret = BEOK_send_packet($hash, 0x6a, @payload);
 }

    return $ret;
}

sub BEOK_NBStart($)
{
  my ($arg) = @_;
  return unless(defined($arg));

  my ($name,$cmd) = split("\\|",$arg);
  my $hash              = $defs{$name};
  my $logname           = $name."[".$$."]";
  my $timeout           = AttrVal($name, 'timeout', 3);
  my $data;
  Log3 $name,5,'BEOK '.$logname.' NBStart '.$cmd;
  my $error = 'no data from device';

   my $sock = IO::Socket::INET->new(
            PeerAddr  => $hash->{'.ip'},
            PeerPort  => '80',
            Proto     => 'udp',
            ReuseAddr => 1,
            Timeout   => $timeout);

  return $name.'|1|NBStart: '.$! if (!$sock);
 
  my $select = IO::Select->new($sock);

  $cmd = decode_base64($cmd);

  $sock->send($cmd);
  if ($select->can_read($timeout)) 
  {
   $sock->recv($data, 1024);
  }
  else
  {
   Log3 $name, 2, 'BEOK '.$logname.' '.$error;
   return "$name|1|$error";
  }
  $sock->close();

 if (!$data)
{ 
  Log3 $name, 2, 'BEOK '.$logname.' '.$error." 2";
  return "$name|1|$error 2";
}


 return $name.'|1|Timeout' if ( $@ && $@ =~ /Timeout/ );
 return $name.'|1|Error: eval corrupted '.$@ if ($@);
 return $name.'|0|'.encode_base64($data,'');
}

sub BEOK_NBAbort($)
{
 my ($hash) = @_;
 my $name   = $hash->{NAME};
 my $error  = 'BlockingCall Timeout';
 $hash->{ERRORCOUNT}++;
 $error .= ' ['.$hash->{ERRORCOUNT}.']';
 Log3 $name,3,"BEOK $name $error" if ($hash->{ERRORCOUNT} < 20);
 readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,'error', $error);
  readingsBulkUpdate($hash,'state', 'error');
  readingsBulkUpdate($hash,'alive', 'no');
 readingsEndUpdate($hash,1);
 delete($hash->{helper}{RUNNING_PID});
 return $error;
}

sub BEOK_NBDone($)
{
   my ($string) = @_;
   return unless(defined($string));

   my @r = split("\\|",$string);
   my $name     = $r[0];
   my $hash     = $defs{$name};
   my $error    = (defined($r[1])) ? $r[1] : "1";
   my $data     = (defined($r[2])) ? $r[2] : "???";
 
   Log3 $name,5,"BEOK $name NBDone : $string";

   delete($hash->{helper}{RUNNING_PID});

   if ($error)
   {
    $hash->{ERRORCOUNT}++;
    $data .= ' ['.$hash->{ERRORCOUNT}.']';
    readingsBeginUpdate($hash);
     readingsBulkUpdate($hash, 'error', $data);
     readingsBulkUpdate($hash, 'state', 'error');
     readingsBulkUpdate($hash, 'alive', 'no');
    readingsEndUpdate($hash,1);
    Log3 $name,3,"BEOK $name $data" if ($hash->{ERRORCOUNT} < 20);
    return $data;
   }

   $data = decode_base64($data);

   if ((length($data) > 0x38) && ($hash->{lastCMD} eq 'get auth'))
   {
     my $cipher = BEOK_getCipher($hash);
     my $dData  = $cipher->decrypt(substr($data, 0x38));

    if (length($dData) < 32)
    {
     Log3 $name,3,"BEOK $name auth -> decrypt data to short : ".length($dData);
     readingsSingleUpdate($hash, "alive", "yes",1);
     return undef;
    }

    $hash->{'.key'} = substr($dData, 4, 16);
    $hash->{'.id'}  = substr($dData, 0,  4);

    $hash->{isAuth} = 1;
    readingsBeginUpdate($hash);
     readingsBulkUpdate($hash,'state','auth');
     readingsBulkUpdate($hash,'alive','yes');
    readingsEndUpdate($hash,1);
    return CommandGet(undef, "$name status"); # gleich die aktuellen Werte holen
   }

  if ((length($data) < 0x39) || unpack("C*", substr($data, 0x22, 1)) | (unpack("C*", substr($data, 0x23, 1)) << 8))
   {
      $error = 'wrong data, '.unpack("C*", substr($data, 0x22, 1)).' | '.(unpack("C*", substr($data, 0x23, 1)) << 8);
      $error = 'to short data, length '.length($data) if (length($data) < 0x39);
   }
   else
   {
     my $cipher = BEOK_getCipher($hash);
     my $dData  = $cipher->decrypt(substr($data, 0x38));

     my $payload_len = unpack("C*", substr($dData, 0, 1));

     my @payload;
     if (length($dData) > $payload_len)
     {
      for my $i (2..$payload_len+1) # Payload ohne Header aber mit CRC
      {
       push @payload, unpack("C*",substr($dData, $i,1));
      }
      my $crc1 = int(((pop @payload) <<8) + pop @payload); # CRC entfernen und merken

      @payload = BEOK_CRC16(@payload); # CRC selbst berechnen

      my $crc2 = int(((pop @payload) <<8) + pop @payload);

      if ($crc1 != $crc2) 
      {
       $error = "CRC Error $crc1 / $crc2";
      }
     }
     else { $error = "response to short $payload_len / ".length($dData);}

     if ($error)
     {
      $hash->{ERRORCOUNT}++;
      $error .= ' ['.$hash->{ERRORCOUNT}.']';
      readingsBeginUpdate($hash);
       readingsBulkUpdate($hash, 'error', $error);
       readingsBulkUpdate($hash, 'state', 'error');
       readingsBulkUpdate($hash, 'alive', 'yes');
      readingsEndUpdate($hash,1);
      Log3 $name,2,"BEOK $name $error";
      return $error;
     }

     $hash->{ERRORCOUNT} = 0;
     $hash->{TIME}       = time();

     #shift @{$hash->{CmdStack}} if ($hash->{'.CmdStack'}); # war das letzte Kommando ein Stack Kommando ?

     return BEOK_UpdateTemp($hash,@payload)   if ($hash->{lastCMD} eq 'get temperature'); 
     return CommandGet(undef, "$name status") if ($hash->{lastCMD} ne 'get status');
     BEOK_UpdateStatus($hash,@payload)        if ($hash->{lastCMD} eq 'get status');
   }
  return undef;
}

sub BEOK_UpdateTemp(@)
{
  my ($hash,@data) = @_;
  my $name   = $hash->{NAME};

  Log3 $name,5,"BEOK $name UpdateTemp";

  if (int(@data) < 19)
  {
    # Bug ?
    Log3 $name,3,"BEOK $name UpdateTemp data to short ".int(@data);
    return undef;
  }

   readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, "alive", "yes");
    readingsBulkUpdate ($hash, "room-temp",  sprintf("%0.1f",$data[5] /2));
    readingsBulkUpdate ($hash, "floor-temp", sprintf("%0.1f",$data[18]/2));
   readingsEndUpdate($hash,1);

  return undef;
}

sub BEOK_UpdateStatus(@) 
{
  my ($hash,@data) = @_;
  my $name = $hash->{NAME};
  my $t;
  my $val;

  Log3 $name,5,"BEOK $name UpdateStatus";

  if (int(@data) < 47)
  {
    # Bug ?
    Log3 $name,3,"BEOK $name UpdateStatus data to short ".int(@data);
    return undef;
  }

  readingsBeginUpdate($hash);

     readingsBulkUpdate ($hash, 'alive', 'yes');

     $val = $data[3] & 1;
     $hash->{helper}{'remote_lock'} = $val;
     readingsBulkUpdate ($hash, "remote-lock",$val);

     $val = $data[4] & 1;
     $hash->{helper}{power} = $val;
     readingsBulkUpdate ($hash, "power",$val);

     readingsBulkUpdate ($hash, "relay",        ($data[4] >> 4) & 1);
     readingsBulkUpdate ($hash, "temp-manual",  ($data[4] >> 6) & 1);
     readingsBulkUpdate ($hash, "room-temp",     sprintf("%0.1f",$data[5] / 2));
     readingsBulkUpdate ($hash, "desired-temp",  sprintf("%0.1f",$data[6] / 2));

     $val = $data[7]  & 15;
     $hash->{helper}{auto_mode} = $val;
     readingsBulkUpdate ($hash, "mode", ($val) ? "auto" : "manual");

     $val = ($data[7] >> 4) & 15;
     $hash->{helper}{loop_mode} = $val;

     my $loop = "???";
     if    ($val == 0) {$loop = "12345.67";}
     elsif ($val == 1) {$loop = "123456.7";}
     elsif ($val == 2) {$loop = "1234567"; }
     readingsBulkUpdate ($hash, "loop", $loop);

     $val = $data[8];
     $hash->{helper}{SEN} = $data[8];

     $t = '???';
     if    ($data[8] == 0) { $t = 'internal'; }
     elsif ($data[8] == 1) { $t = 'external'; }
     elsif ($data[8] == 2) { $t = 'both';     }
     readingsBulkUpdate ($hash, "sensor", $t);

     $val = sprintf("%.1f",$data[9]);
     $hash->{helper}{OSV} = $data[9];  # 6 - 99 Bodentemp
     readingsBulkUpdate ($hash, "osv", $val);

     $val = sprintf("%.1f",$data[10]);
     $hash->{helper}{dIF} = $data[10]; # 1 - 9 Bodentemp diff
     readingsBulkUpdate ($hash, "dif", $val);

     $val = sprintf("%.1f",$data[11]);
     $hash->{helper}{SVH} = $data[11]; # Raumtemp max. 5 - 99
     readingsBulkUpdate ($hash, "svh", $val);

     $val = sprintf("%.1f",$data[12]);
     $hash->{helper}{SVL} = $data[12]; # Raumtemp min 5 - 99
     readingsBulkUpdate ($hash, "svl", $val);

     $val = ($data[13] << 8) + $data[14];
     $hash->{helper}{AdJ} = $val; #  Raumtemp adj -5 - 0 - +5
     my $adj;
     if (($val >=  0) && ($val <= 10)) { $adj = sprintf("%.1f",$val/2);}
     else  { $adj = sprintf("%.1f",(0x10000 - $val) / -2);}

     readingsBulkUpdate ($hash, "room-temp-adj", $adj);

     $hash->{helper}{FrE} = $data[15];
     readingsBulkUpdate ($hash, "fre", ($data[15]) ? 'open' : 'close');

     $hash->{helper}{PoM} = $data[16];
     readingsBulkUpdate ($hash, "power-on-mem",  ($data[16]) ? 'off' : 'on');

     #readingsBulkUpdate ($hash, "unknown",    $data[17]); # ???
     readingsBulkUpdate ($hash, "floor-temp", sprintf("%0.1f", $data[18] / 2));
     readingsBulkUpdate ($hash, "time",       sprintf("%02d:%02d:%02d", $data[19],$data[20],$data[21]));
     readingsBulkUpdate ($hash, "dayofweek",  $data[22]);

     for (my $i=0;$i<6;$i++)
     {
       $hash->{helper}{$i}{time} = sprintf("%02d:%02d" , $data[2*$i+23] , $data[2*$i+24]);
       readingsBulkUpdate ($hash, "day-profile".($i+1)."-time", $hash->{helper}{$i}{time});
       $hash->{helper}{$i}{temp} = $data[$i+39];
       readingsBulkUpdate ($hash, "day-profile".($i+1)."-temp", sprintf("%.1f",$hash->{helper}{$i}{temp}/2));
     }

     for (my $i=6;$i<8;$i++)
     {
       $hash->{helper}{$i}{time} = sprintf("%02d:%02d" , $data[2*$i+23] , $data[2*$i+24]);
       readingsBulkUpdate ($hash, "we-profile".($i+1)."-time", $hash->{helper}{$i}{time});
       $hash->{helper}{$i}{temp} = $data[$i+39];
       readingsBulkUpdate ($hash, "we-profile".($i+1)."-temp", sprintf("%.1f",$hash->{helper}{$i}{temp}/2));
     }

   readingsBulkUpdate ($hash, "state", ($hash->{helper}{power}) ? "on" : "off");
  readingsEndUpdate($hash,1);

  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
  my $time1 = timelocal( $sec, $min, $hour,$mday,$month,$year);
  my $time2 = timelocal($data[21],$data[20],$data[19],$mday,$month,$year);
  $data[22] = 0 if ($data[22] == 7);

  # falscher Wochentag oder Zeit Diff mehr als eine Minute ?

  if (($wday != $data[22]) || (($time1-$time2) > 60) || (($time1-$time2) < -60))
  {
   my @days =('Sun','Mon','Tue','Wed','Thu','Fri','Sat','Sun');
   my $time1_s = sprintf("%02d:%02d:%02d , %3s" , $hour,$min,$sec,$days[$wday]);
   my $time2_s = sprintf("%02d:%02d:%02d , %3s" , $data[19],$data[20],$data[21],$days[$data[22]]);

   if (!AttrVal($name,'timesync',0))
   {
    Log3 $name,3,"BEOK $name time on device is wrong. FHEM : $time1_s / $name : $time2_s - run set $name time";
   }
    else
   {
      Log3 $name,4,"BEOK $name time autosync : $time1_s / $time2_s";
      CommandSet(undef,$name.' time');
   }
  }

  return undef;
}

sub BEOK_getCipher(@)
{
  my ($hash) = @_;
  return Crypt::CBC->new(
			-key         => $hash->{'.key'},
			-cipher      => "Crypt::OpenSSL::AES",
			-header      => "none",
			-iv          => $hash->{'.iv'},
			-literal_key => 1,
			-keysize     => 16,
			-padding     => 'space'
			);
}

sub BEOK_send_packet(@)
{
 my ($hash,$command,@payload) = @_;
 my $name = $hash->{NAME};
 my $error;
 my $len;
 Log3 $name,5,"BEOK $name send_packet ". join(' ', @payload);

 if ($command != 0x65) # auth payload ist bereits fertig
 {
   $len = int(@payload)+2; 
   @payload  = BEOK_CRC16(@payload);

   unshift @payload, 0;
   unshift @payload, $len;

   $len +=2; # neue Länge und dann mit Nullen auffüllen bis Länge ohne Rest durch 16 teilbar ist

   for (my $i=16;$i<96;$i+=16)
   {
    if (( $len > ($i-16) ) && ( $len < $i ))  { while (int(@payload) < $i) { push @payload, 0; } }
   }

  }

  $hash->{'counter'} = ($hash->{'counter'} + 1) & 0xffff;

  my @id  = split(//, $hash->{'.id'});
  my @mac = split(':', $hash->{MAC});

  my @packet = (0) x 56;

  $packet[0x00] = 0x5a;
  $packet[0x01] = 0xa5;
  $packet[0x02] = 0xaa;
  $packet[0x03] = 0x55;
  $packet[0x04] = 0x5a;
  $packet[0x05] = 0xa5;
  $packet[0x06] = 0xaa;
  $packet[0x07] = 0x55;
  $packet[0x24] = 0x2a;
  $packet[0x25] = 0x27;
  $packet[0x26] = $command;
  $packet[0x28] = $hash->{'counter'} & 0xff;
  $packet[0x29] = $hash->{'counter'} >> 8;
  $packet[0x2a] = hex ($mac[5]);
  $packet[0x2b] = hex ($mac[4]);
  $packet[0x2c] = hex ($mac[3]);
  $packet[0x2d] = hex ($mac[2]);
  $packet[0x2e] = hex ($mac[1]);
  $packet[0x2f] = hex ($mac[0]);
  $packet[0x30] = unpack('C', $id[0]);
  $packet[0x31] = unpack('C', $id[1]);
  $packet[0x32] = unpack('C', $id[2]);
  $packet[0x33] = unpack('C', $id[3]);

  #calculate payload checksum of original data
  my $checksum = 0xbeaf;
  $len = int(@payload);
  for(my $i = 0; $i < $len; $i++) 
  {
     $checksum += $payload[$i];
     $checksum  = $checksum & 0xffff;
  }

  $packet[0x34] = $checksum & 0xff;
  $packet[0x35] = $checksum >> 8;

  #crypt payload
  my $cipher       = BEOK_getCipher($hash);
  my $payloadCrypt = $cipher->encrypt(pack('C*', @payload));

  #add the crypted data to packet
  my @values = split(//,$payloadCrypt);

  foreach  (@values) { push @packet, unpack('C*', $_); }

  #create checksum of whole packet
  $checksum = 0xbeaf;
  $len      = int(@packet);
  for(my $i = 0; $i < $len; $i++) 
  {
    $checksum += $packet[$i];
    $checksum  = $checksum & 0xffff;
  }

  $packet[0x20] = $checksum & 0xff;
  $packet[0x21] = $checksum >> 8;

  my $timeout = AttrVal($name, 'timeout', 3)*2;

  Log3 $name,5,"BEOK $name send_packet ". join(' ', @packet);
  my $arg = encode_base64(pack('C*',@packet));

  #push(@{$hash->{CmdStack}}, $arg) if $hash->{'.CmdStack'};

  $arg = $name.'|'.$arg;

  if(defined($hash->{helper}{RUNNING_PID}))
  {
   Log3 $name,3,"BEOK $name last BC ".$hash->{helper}{RUNNING_PID}{pid}.' has not ended yet !';
  }
  $hash->{helper}{RUNNING_PID} = BlockingCall('BEOK_NBStart',$arg, 'BEOK_NBDone',$timeout,'BEOK_NBAbort',$hash);# unless(exists($hash->{helper}{RUNNING_PID}));

  if(!$hash->{helper}{RUNNING_PID})
  {
   $hash->{ERRORCOUNT}++;
   my $error = 'can`t start BlockingCall ['.$hash->{ERRORCOUNT}.']';
   Log3 $name, 3, "BEOK $name $error" if ($hash->{ERRORCOUNT} <20);
   readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, 'error', $error);
    readingsBulkUpdate ($hash, 'state', 'error');
   readingsEndUpdate($hash,1);
   return $error;
  }

  return undef;
}

sub BEOK_CRC16(@)
{
    my (@a) = @_;
    my $crc = 0xFFFF;
    foreach(@a)
    {
     $crc ^= 0xFF & $_;
     for (1..8)
     {
      if ($crc & 0x0001)
            { $crc = (($crc >> 1) & 0xFFFF) ^ 0xA001; }
      else  { $crc =  ($crc >> 1) & 0xFFFF; }
     }
    }
    push @a, $crc & 0xFF; 
    push @a, $crc >>8;
    return @a;
}

sub BEOK_set_timer_schedule($)
{
 my ($hash) = @_;

  # Set timer schedule
  # Format is the same as you get from get_full_status.
  # weekday is a list (ordered) of 6 dicts like:
  # {'start_hour':17, 'start_minute':30, 'temp': 22 }
  # Each one specifies the thermostat temp that will become effective at start_hour:start_minute
  # weekend is similar but only has 2 (e.g. switch on in morning and off in afternoon)

    # Begin with some magic values ...
    my @payload = (1,16,0,10,0,0x0c,0x18);
    my $i;

    # Now simply append times/temps

    for ($i=0;$i<8;$i++)
    {
      my ($h,$m) = split(":",$hash->{helper}{$i}{time});
      push @payload,int($h); push @payload,int($m);
    }

    for ($i=0;$i<8;$i++)
    {
     push @payload, $hash->{helper}{$i}{temp}; # temperatures
    }

   return @payload;
}

sub BEOK_Attr (@)
{

 my ($cmd, $name, $attrName, $attrVal) = @_;
 my $hash  = $defs{$name};

 if ($cmd eq "set")
 {
   if ($attrName eq 'interval')
   {
     $_[3] = $attrVal;
     BEOK_update($hash); # Polling Start
   }
 }
 elsif ($cmd eq "del")
 {
   if ($attrName eq 'interval')
   {
     $_[3] = $attrVal;
    RemoveInternalTimer($hash);
   }
 }
}

sub BEOK_summaryFn($$$$) 
{
 my ($FW_wname, $name, $room, $pageHash) = @_;
 return if (AttrVal($name, "stateFormat", ""));

 my $hash         = $defs{$name};
 my $state        = ReadingsVal($name,'state', '');
 my $power        = ($hash->{helper}{power}) ? 'on' : 'off';
 my $relay        = (ReadingsNum($name,'relay',1)) ? 'hon' : 'hoff';
 my $sensor       = $hash->{helper}{SEN};
 my $locked       = ($hash->{helper}{remote_lock}) ? 'closed' : 'open';
 my $mode         = ($hash->{helper}{auto_mode}) ? 'auto' : 'manual';
 my $csrf         = ($FW_CSRF ? "&fwcsrf=$defs{$FW_wname}{CSRFTOKEN}" : '');
 my $sel          = '';
 my $html         = '';
 my $icon;
 my @names;

 if (lc(AttrVal($name,'language','')) eq 'de')
      { @names = ('Raum ','Boden ','Soll','Modus'); }
 else { @names = ('Room ','Floor ','desired-temp','Mode'); }

 if ($state =~ /^(on|off)$/ )
 {

  ($icon, undef, undef) = FW_dev2image($name,$power);
  $power = FW_makeImage($icon, $power) if ($icon);

  $html .= '<table border="0" class="header"><tr><td>'.$power.'</td>';

  if ($state eq 'on')
  {
   ($icon, undef, undef) = FW_dev2image($name,$relay);
   $relay = FW_makeImage($icon, $relay) if ($icon);

   ($icon, undef, undef) = FW_dev2image($name,$locked);
   $locked = FW_makeImage($icon, $locked) if ($icon);

   $html .= '<td>'.$relay.'</td><td>'.$locked.'</td>';

   $html .= '<td align="right">'.$names[0].ReadingsNum($name,'room-temp',0).' &deg;C<br>'.$names[1].ReadingsNum($name,'floor-temp',0).' &deg;C</td>';

   $html .= "<td align=\"center\">".$names[2]."<br><select  id=\"".$name."_tempList\" name=\"".$name."_tempList\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1$csrf&cmd.$name=set $name desired-temp ' + this.options[this.selectedIndex].value)\">";
    for (my $i=10;$i<199;$i++)
    {
      $sel = (($i/2) == ReadingsNum($name,'desired-temp',5)) ? ' selected' : '';
      $html .= "<option".$sel." value=\"".sprintf("%.1f",$i/2)."\">".sprintf("%.1f",$i/2)."</option>";
    }
   $html .= '</select></td>';

   $html .= "<td align=\"center\">".$names[3]."<br><select  id=\"".$name."_modeList\" name=\"".$name."_modeList\" class=\"dropdown\" onchange=\"FW_cmd('/fhem?XHR=1$csrf&cmd.$name=set $name mode ' + this.options[this.selectedIndex].value)\">";
   $sel   = ($mode eq 'auto') ? ' selected' : '';
   $html .= "<option".$sel." value=\"auto\">auto</option>";
   $sel   = ($mode eq 'manual') ? ' selected' : '';
   $html .= "<option".$sel." value=\"manual\">manual</option>";
   $html .= '</select></td>';
  }

  $html .='</tr></table>';

 } else { $html .= $state };
return $html;
}

1;

=pod
=item device
=item summary    implements a connection to BEOK / Floureon / Hysen WiFi room thermostat
=item summary_DE implementiert die Verbindung zu BEOK / Floureon / Hysen WiFi Raumthermostaten
=begin html

<a name="BEOK"></a>
<h3>BEOK</h3>
<ul>
    BEOK implements a connection to BEOK / Floureon / Hysen WiFi room thermostat
    <br>
	AES Encyrption is needed. Maybe you must first install extra Perl modules.<br>
        E.g. for Debian/Raspian :<br>
	<code>
        sudo apt-get install libcrypt-cbc-perl<br>
	sudo apt-get install libcrypt-rijndael-perl<br>
        sudo apt-get install libssl-dev<br>
	sudo cpan Crypt/OpenSSL/AES.pm</code>
    <br>
    <br>
    <a name="BEOKdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; BEOK &lt;ip&gt; [mac]</code>
        <br>
        <br>
        Example: <code>define Thermo BEOK 192.168.1.100</code>
    </ul>
    <br>
    <a name="BEOKset"></a>
    <b>Set</b>
    <br>
    <ul>
    <li><code>desired-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>mode &lt;auto manual&gt;</code>
    </li><br>
    <li><code>loop &lt;12345.67 123456.7 1234567&gt;</code><br>
    12345.67 means Saturday and Sunday follow the "weekend" schedule<br>
    1234567 means every day (including Saturday and Sunday) follows the "weekday" schedule
    </li><br>
    <li><code>sensor &lt;external internal both&gt;</code><br>
    both = internal control temperature, external limit temperature
    </li><br>
    <li><code>time</code><br>
    sets time and day of week on device to FHEM time & day
    </li><br>
    <li><code>lock &lt;on off&gt;</code>
    </li><br>
    <li><code>power-on-memory &lt;on off&gt;</code>
    </li><br> 
    <li><code>fre &lt;open close&gt;</code> 
     Anti-freezing function
    </li><br>
    <li><code>room-temp-adj  &lt;-5 +5&gt;</code>
    </li><br>
    <li><code>osv &lt;5 - 99&gt;</code><br>
    Limit temperature value of external sensor
    </li><br>
    <li><code>svh &lt;5 - 99&gt;</code><br>
    Set upper limit temperature value
    </li><br>
    <li><code>svl &lt;5 - 99&gt;</code><br>
    Set lower limit temperature value
    </li><br>
    <li><code>dif &lt;1 - 9&gt;</code><br>
    difference of limit temperature value of external sensor
    </li><br>
    <li><code>day-profil[1-6]-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>day-profil[1-6]-time &lt;00:00 - 23:59&gt;</code>
    </li><br>
    <li><code>we-profile[7-8]-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>we-profile[7-8]-time &lt;00:00 - 23:59&gt;</code>
    </li><br>
    <li><code>weekprofile</code><br>
    Set all weekday setpoints and temperatures with values from a weekprofile day.<br>
    Syntax : set <name> weekprofile  &lt;weekprofile_device:profil_name[:weekday]&gt;<br>
    see also <a href='https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303'>https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303</a>
    </li><br>

    </ul>
    <a name="BEOKattr"></a>
    <b>Attributes</b>
    <br>
    <ul>
        <li><code>timeout</code>
        <br>
        timeout for network device communication, default 5
        </li>
    </ul>
    <br>
    <ul>
        <li><code>interval</code>
        <br>
        poll time interval in seconds, set to 0 for no polling , default 60
        </li>
    </ul>
    <br>
    <ul>
        <li><code>timesync</code>
        <br>
	 set device time and day of week automatic to FHEM time, default 1 (on)
        </li>
    </ul>
    <br>
    <ul>
        <li><code>language</code>
        <br>
	 set to de or DE for german names of Room, Floor , etc.
        </li>
    </ul>
    <br>
    <ul>
        <li><code>model</code>
        <br>
	  only for FHEM modul statistics at <a href="https://fhem.de/stats/statistics.html">https://fhem.de/stats/statistics.html</a>
        </li>
    </ul>

</ul>

=end html
=begin html_DE

<a name="BEOK"></a>
<h3>BEOK</h3>
<ul>
    BEOK implementiert die Verbindung zu einem BEOK / Floureon / Hysen WiFi Raum Thermostaten
	<br>
	Da das Modul AES-Verschl&uuml;sselung ben&ouml;tigt m&uuml;ssen ggf. noch zus&auml;tzliche Perl Module installiert werden.<br>
        Bsp. f&uuml;r Debian/Raspian :<br>
	<code>
        sudo apt-get install libcrypt-cbc-perl<br>
	sudo apt-get install libcrypt-rijndael-perl<br>
        sudo apt-get install libssl-dev<br>
	sudo cpan Crypt/OpenSSL/AES.pm</code><br>
    <br><br>
    <a name="BEOKdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; BEOK &lt;ip&gt; [mac]</code>
        <br>
        <br>
        Beispiel: <code>define WT BEOK 192.178.1.100</code>
    </ul>
    <br>
    <br>
    <a name="BEOKset"></a>
    <b>Set</b><br>
    <ul>
    <li><code>desired-temp &lt;5 - 99&gt;</code>
    </li><br>
    <li><code>mode &lt;auto manual&gt;</code>
    </li><br>
    <li><code>loop &lt;12345.67 123456.7 1234567&gt;</code><br>
    12345.67 Montag - Freitag Werktag, Samstag & Sonntag sind Wochenende<br>
    123456.7 Montag - Samstag Werktag, nur Sonntag ist Wochendende<br>
    1234567 jeder Tag (inklusive Samstag & Sonntag) ist ein Werktag, kein Wochenende
    </li><br>
    <li><code>sensor &lt;external internal both&gt;</code><br>
    both = internal control temperature, external limit temperature
    </li><br>
    <li><code>time</code><br>
    setzt Uhrzeit und Wochentag
    </li><br>
    <li><code>lock &lt;on off&gt;</code>
    </li><br>
    <li><code>power-on-memory &lt;on off&gt;</code>
    </li><br> 
    <li><code>fre &lt;open close&gt;</code><br>
     Frostschutz Funktion
    </li><br>
    <li><code>room-temp-adj  &lt;-5 - +5&gt;</code><br>
    Korrekturwert (Offset) Raumtemperatur
    </li><br>
    <li><code>osv &lt;5 - 99&gt;</code><br>
    Maximum Temperatur f&uuml;r externen Sensor
    </li><br>
    <li><code>svh &lt;5 - 99&gt;</code><br>
    Raumtemperatur Maximum
    </li><br>
    <li><code>svl &lt;5 - 99&gt;</code><br>
    Raumtemperatur Minimum
    </li><br>
    <li><code>dif &lt;1 - 9&gt;</code><br>
    difference of limit temperature value of external sensor
    </li><br>
    <li><code>day-profil[1-6]-temp &lt;5 - 99&gt;</code><br>
    Werktagprofil Temperatur
    </li><br>
    <li><code>day-profil[1-6]-time &lt;00:00 - 23:59&gt;</code><br>
    Werktagprofil Zeit
    </li><br>
    <li><code>we-profile[7-8]-temp &lt;5 - 99&gt;</code><br>
    Wochenendprofil Temperatur
    </li><br>
    <li><code>we-profile[7-8]-time &lt;00:00 - 23:59&gt;</code><br>
    Wochenendprofil Zeit
    </li><br>
    <li><code>weekprofile</code><br>
    Setzt alle Wochentag Schaltzeiten und Temperaturen mit Werten aus einem Profil des Moduls weekprofile.<br>
    Syntax : set <name> weekprofile &lt;weekprofile_device:profil_name[:Wochentag]&gt;<br>
    siehe auch Erkl&auml;rung im Forum : <a href='https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303'>https://forum.fhem.de/index.php/topic,80703.msg901303.html#msg901303</a>
    </li><br>
  </ul>
    <a name="BEOKattr"></a>
    <b>Attribute</b>
    <br>
    <ul>
        <li><code>interval</code>
        <br>
	  Poll Intevall in Sekunden,  0 = kein Polling , default 60
        </li>
    </ul>
    <br>
    <ul>
        <li><code>timesync</code>
        <br>
	 Uhrzeit und Wochentag automatisch mit FHEM synchronisieren, default 1 (an)
        </li>
    </ul>
    <br>
    <ul>
        <li><code>timeout</code>
        <br>
	  Timeout in Sekunden für die Netzwerk Kommunikation, default 5
        </li>
    </ul>
    <br>
    <ul>
        <li><code>language</code>
        <br>
	  de oder DE f&uuml;r deutsche Bezeichnungen, Raum statt Room , usw.
        </li>
    </ul>
    <br>
    <ul>
        <li><code>model</code>
        <br>
	  nur f&uuml;r die FHEM Modul Statistik unter <a href="https://fhem.de/stats/statistics.html">https://fhem.de/stats/statistics.html</a>
        </li>
    </ul>
</ul>

=end html_DE
=cut