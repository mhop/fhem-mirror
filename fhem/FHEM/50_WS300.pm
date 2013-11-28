# $Id$
################################################################
#
#  Copyright notice
#
#  (c) 2007 Copyright: Martin Klerx (Martin at klerx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
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
################################################################
# examples:
# define WS300Device	WS300	/dev/ttyUSB1	(fixed name, must be first)
# define ash2200-1	WS300	0
# define ash2200-2	WS300	1
# ...
# define ash2200-8	WS300	7
# define ks300		WS300	8		(always 8)
# define ws300		WS300	9		(always 9)
# set WS300Device <interval(5-60 min.)> <height(0-2000 m)> <rainvalume(ml)>
################################################################


package main;

use strict;
use warnings;

my $DeviceName="";
my $inbuf="";

my $config;
my $cmd=0x32;
my $errcount=0;
my $ir="no";
my $willi=0;
my $oldwind=0.0;
my $polling=0;
my $acthour=99;
my $actday=99;
my $actmonth=99;
my $oldrain=0;
my $rain_hour=0;
my $rain_day=0;
my $rain_month=0;
#####################################
sub
WS300_Initialize($)
{
  my ($hash) = @_;

  # Provider
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model:ws300 loglevel:0,1,2,3,4,5,6 event-on-update-reading event-on-change-reading";
  $hash->{DefFn}     = "WS300_Define";
  $hash->{GetFn}     = "WS300_Get";
  $hash->{ParseFn}   = "WS300_Parse";
  $hash->{SetFn}     = "WS300_Set";
  $hash->{UndefFn}   = "WS300_Undef";

  $hash->{Clients}   = ":WS300:";       # Not needed
  $hash->{Match}     = "^WS300.*";      # Not needed
  $hash->{ReadFn}    = "WS300_Read";    # Not needed
  $hash->{Type}      = "FHZ1000";       # Not needed
  $hash->{WriteFn}   = "WS300_Write";   # Not needed
}

###################################
sub
WS300_Set($@)
{ 
  my ($hash, @a) = @_;
  if($hash->{NAME} eq "WS300Device")
  {
    return "wrong syntax: set WS300Device <Interval(5-60 min.)> <height(0-2000 m)> <rainvolume(ml)>" if(int(@a) < 4 || int($a[1]) < 5 || int($a[1]) > 60 || int($a[2]) > 2000);
    my $bstring = sprintf("%c%c%c%c%c%c%c%c",0xfe,0x30,(int($a[1])&0xff),((int($a[2])>>8)&0xff),(int($a[2])&0xff),((int($a[3])>>8)&0xff),(int($a[3])&0xff),0xfc);
    $hash->{PortObj}->write($bstring);
    Log 1,"WS300 synchronization started (".unpack('H*',$bstring).")";
    return "the ws300pc will now synchronize for 10 minutes";
  }
  return "No set function implemented";
}

###################################
sub
WS300_Get(@)
{
  my ($hash, @a) = @_;
  if($hash->{NAME} eq "WS300Device")
  {
    Log 5,"WS300_Get $a[0] $a[1]";
    WS300_Poll($hash);
    return undef;
  }
  return "No get function implemented";
}

#####################################
sub
WS300_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
    my $po;
  if($a[0] eq "WS300Device")
  {
    $modules{WS300}{defptr}{10} = $hash;
    return "wrong syntax: define WS300Device WS300 <DeviceName>" if(int(@a) < 3);
    $DeviceName = $a[2];
    $hash->{STATE} = "Initializing";
    $hash->{SENSOR} = 10;
    $hash->{READINGS}{WS300Device}{VAL} = "Initializing";
    $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
 
  if ($^O=~/Win/) {
    eval ("use Win32::SerialPort;");
    $po = new Win32::SerialPort ($DeviceName);
  }else{
    eval ("use Device::SerialPort;");
    $po = new Device::SerialPort ($DeviceName);
  }
    if(!$po)
    {
      $hash->{STATE} = "error opening device";
      $hash->{READINGS}{WS300Device}{VAL} = "error opening device";
      $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
      Log 1,"Error opening WS300 Device $a[2]";
      return "Can't open $a[2]: $!\n";
    }
    $po->reset_error();
    $po->baudrate(19200);
    $po->databits(8);
    $po->parity('even');
    $po->stopbits(1);
    $po->handshake('none');
    $po->rts_active(1);
    $po->dtr_active(1);
    sleep(1);
    $po->rts_active(0);
    $po->write_settings;
    $hash->{PortObj} = $po;
    $hash->{DeviceName} = $a[2];    
    $hash->{STATE} = "opened";
    $hash->{READINGS}{WS300Device}{VAL} = "opened";
    $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
    CommandDefine(undef,"WS300Device_timer at +*00:00:05 get WS300Device data");
    Log 1,"WS300 Device $a[2] opened";
    return undef;
  }
  return "wrong syntax: define <name> WS300 <sensor (0-9)>\n0-7=ASH2200\n8=KS300\n9=WS300" if(int(@a) < 3);
  return "no device: define WS300Device WS300 <DeviceName> first" if($DeviceName eq "");
  return "Define $a[0]: wrong sensor number." if($a[2] !~ m/^[0-9]$/);
  $hash->{SENSOR} = $a[2];
  $modules{WS300}{defptr}{$a[2]} = $hash;

  return undef;
}

#####################################
sub
WS300_Undef($$)
{
  my ($hash, $name) = @_;
  return undef if(!defined($hash->{SENSOR}));
  delete($modules{WS300}{defptr}{$hash->{SENSOR}});
  return undef;
}


#####################################
sub
WS300_Parse($$)
{
  my ($hash, $msg) = @_;
  my $ll = GetLogLevel("WS300Device");
  $ll = 5 if($ll == 2);

  my @c = split("", $config);
  my @cmsg = split("",unpack('H*',$config));
  my $dmsg = unpack('H*',$msg);
  my @a = split("", $dmsg);
  my $val = "";
  my $tm;
  my $h;
  my $t;
  my $b;
  my $l;
  my $value;
  my $offs=0;
  my $ref;
  my $def;
  my $zeit;
  my @txt = ( "temperature", "humidity", "wind", "rain_raw", "israining", "battery", "lost_receives", "pressure", "rain_cum", "rain_hour", "rain_day", "rain_month");
  #           1         2         3         4         5         6         7         8
  # 012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789
  # 3180800001005d4e00000000000000000000000000000000000000000000594a0634001e00f62403f1fc	stored
  #       aaaatttthhtttthhtttthhtttthhtttthhtttthhtttthhtttthhtttthhrrrrwwwwtttthhpppp
  # 3300544a0000000000000000000000000000000000000000000057470634002c00f32303ee32fc		current
  #   tttthhtttthhtttthhtttthhtttthhtttthhtttthhtttthhtttthhrrrrwwwwtttthhppppss
  # 3210000000000000001005003a0127fc								config
  #   001122334455667788iihhhhmmmm
  $offs = 2 if(hex($a[0].$a[1]) == 0x33);
  $offs = 10 if(hex($a[0].$a[1]) == 0x31);
  if($offs == 0)
  {
    Log 1,"WS300 illegal data in WS300_Parse";
    return undef;
  }
  $zeit = time;
  my $wind = hex($a[58+$offs].$a[59+$offs].$a[60+$offs].$a[61+$offs]);
  $wind /= 10.0;
  if(hex($a[0].$a[1]) == 0x33)
  {
    return undef if(hex($a[74].$a[75]) == $willi && $wind == $oldwind );
    $willi = hex($a[74].$a[75]);
    $ir="no";
    $ir="yes" if(($willi&0x80));
  }
  else
  {
    $zeit -= (hex($a[6].$a[7].$a[8].$a[9])*60);
  }
  my @lt = localtime($zeit);
  $tm = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$lt[5]+1900, $lt[4]+1, $lt[3], $lt[2], $lt[1], $lt[0]);  
  $oldwind = $wind;
  my $press = hex($a[68+$offs].$a[69+$offs].$a[70+$offs].$a[71+$offs]);
  my $hpress = hex($cmsg[22].$cmsg[23].$cmsg[24].$cmsg[25]);
  $hpress /= 8.5;
  $press += $hpress;
  $press = sprintf("%.1f",$press);
  my $rainc = hex($a[54+$offs].$a[55+$offs].$a[56+$offs].$a[57+$offs]);
  my $rain = hex($cmsg[26].$cmsg[27].$cmsg[28].$cmsg[29]);
  $rain *= $rainc;
  $rain /= 1000;
  $rain = sprintf("%.1f",$rain);

  
  for(my $s=0;$s<9;$s++)
  {
    if((ord($c[$s+1])&0x10))
    {
      my $p=($s*6)+$offs;
      Log $ll,"Sensor $s vorhanden";
      if(!defined($modules{WS300}{defptr}{$s})) 
      {
        Log 3, "WS300 Unknown device $s, please define it";
        return "UNDEFINED WS300_$s WS300 $s";
      }
      else
      {
        $def = $modules{WS300}{defptr}{$s};
        $def->{READINGS}{$txt[0]}{VAL} = 0 if(!$def->{READINGS});
        $ref = $def->{READINGS};

        $t = hex($a[$p].$a[$p+1].$a[$p+2].$a[$p+3]);
        $t -= 65535 if( $t > 32767 );
        $t /= 10.0;
        $h = hex($a[$p+4].$a[$p+5]); 
        if((ord($c[$s+1])&0xe0))
        {
          $b = "Empty"
        }
        else
        {
          $b = "Ok"
        }
        $l = (ord($c[$s+1])&0x0f);


        
        if($s < 8)
        {
          readingsBeginUpdate($def);
          # state
	  $val = "T: $t  H: $h  Bat: $b  LR: $l";
	  $def->{STATE} = $val;
          readingsBulkUpdate($def, 'state', $val);
          # temperature
          readingsBulkUpdate($def, $txt[0], $t);
          # humidity
          readingsBulkUpdate($def, $txt[1], $h);
          # battery
          readingsBulkUpdate($def, $txt[5], $b);
          # lost receives
          readingsBulkUpdate($def, $txt[6], $l);
          
          Log $ll, "WS300 $def->{NAME}: $val";

          readingsEndUpdate($def, 1);
        }
        else
        {
          readingsBeginUpdate($def);
          # state
          $val = "T: $t  H: $h  W: $wind  R: $rain  IR: $ir  Bat: $b  LR: $l";
	  $def->{STATE} = $val;
          readingsBulkUpdate($def, 'state', $val);

          $def->{CHANGED}[0] = $val;
          $def->{CHANGETIME}[0] = $tm;
          # temperature
          readingsBulkUpdate($def, $txt[0], $t);
          # humidity
          readingsBulkUpdate($def, $txt[1], $h);
          # wind
          readingsBulkUpdate($def, $txt[2], $wind);
          # rain counter
          readingsBulkUpdate($def, $txt[3], $rainc);
          # is raining
          readingsBulkUpdate($def, $txt[4], $ir);
          # battery
          readingsBulkUpdate($def, $txt[5], $b);
          # lost receives
          readingsBulkUpdate($def, $txt[6], $l);
          # rain cumulative
          readingsBulkUpdate($def, $txt[8], $rain);
          # statistics
          if($actday == 99)
          {
            $oldrain = $rain;
            $acthour = $ref->{acthour}{VAL} if(defined($ref->{acthour}{VAL}));
            $actday = $ref->{actday}{VAL} if(defined($ref->{actday}{VAL}));
            $actmonth = $ref->{actmonth}{VAL} if(defined($ref->{actmonth}{VAL}));
            $rain_day = $ref->{rain_day}{VAL} if(defined($ref->{rain_day}{VAL}));
            $rain_month = $ref->{rain_month}{VAL} if(defined($ref->{rain_month}{VAL}));
            $rain_hour = $ref->{rain_hour}{VAL} if(defined($ref->{rain_hour}{VAL}));
          }
          if($acthour != $lt[2])
          {
            $acthour = $lt[2];
            $rain_hour = sprintf("%.1f",$rain_hour);
            $rain_day = sprintf("%.1f",$rain_day);
            $rain_month = sprintf("%.1f",$rain_month);
            $ref->{acthour}{TIME} = $tm;
            $ref->{acthour}{VAL} = "$acthour";
            readingsBulkUpdate($def, $txt[9], $rain_hour);
            readingsBulkUpdate($def, $txt[10], $rain_day);
            readingsBulkUpdate($def, $txt[11], $rain_month);
            $rain_hour=0;
          }
          if($actday != $lt[3])
          {
            $actday = $lt[3];
            $ref->{actday}{TIME} = $tm;
            $ref->{actday}{VAL} = "$actday";
            $rain_day=0;
          }
          if($actmonth != $lt[4]+1)
          {
            $actmonth = $lt[4]+1;
            $ref->{actmonth}{TIME} = $tm;
            $ref->{actmonth}{VAL} = "$actmonth";
            $rain_month=0;
          }
          if($rain != $oldrain)
          {
            $rain_hour += ($rain-$oldrain);
            $rain_hour = sprintf("%.1f",$rain_hour);
            $rain_day += ($rain-$oldrain);
            $rain_day = sprintf("%.1f",$rain_day);
            $rain_month += ($rain-$oldrain);
            $rain_month = sprintf("%.1f",$rain_month);
            $oldrain = $rain;
            $ref->{acthour}{TIME} = $tm;
            $ref->{acthour}{VAL} = "$acthour";
            readingsBulkUpdate($def, $txt[9], $rain_hour);
            readingsBulkUpdate($def, $txt[10], $rain_day);
            readingsBulkUpdate($def, $txt[11], $rain_month);
          }
          Log $ll,"WS300 $def->{NAME}: $val";

          readingsEndUpdate($def, 1);
          
        }
        
      }
    }
  }

  if(!defined($modules{WS300}{defptr}{9}))
  {
    Log 3, "WS300 Unknown device 9, please define it";
    return "UNDEFINED WS300_9 WS300 9";
  }
  else
  {
    $def = $modules{WS300}{defptr}{9};
    $def->{READINGS}{$txt[0]}{VAL} = 0 if(!$def->{READINGS});
    $ref = $def->{READINGS};

    readingsBeginUpdate($def);

    $t = hex($a[62+$offs].$a[63+$offs].$a[64+$offs].$a[65+$offs]);
    $t -= 65535 if( $t > 32767 );
    $t /= 10.0;
    $h = hex($a[66+$offs].$a[67+$offs]); 
    # state
    $val = "T: $t  H: $h  P: $press  Willi: $willi";
    $def->{STATE} = $val;
    readingsBulkUpdate($def, 'state', $val);
    # temperature
    readingsBulkUpdate($def, $txt[0], $t);
    # humidity
    readingsBulkUpdate($def, $txt[1], $h);
    # pressure
    readingsBulkUpdate($def, $txt[7], $press);
    # willi
    readingsBulkUpdate($def, 'willi', $willi);
    
    Log $ll,"WS300 $def->{NAME}: $val";

    readingsEndUpdate($def, 1);
  }

  return undef;
}

#####################################
sub
WS300_Read($)
{
  my ($hash) = @_;
}
#####################################
sub
WS300_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
}

#####################################
sub
WS300_Poll($)
{
  my $hash = shift;
  my $bstring="   ";
  my $count;
  my $po;
  my $inchar='';
  my $escape=0;
  my $ll = GetLogLevel("WS300Device");
  $ll = 5 if($ll == 2);
  
  if(!$hash || !defined($hash->{PortObj}))
  {         
    return;
  }
  return if($polling);
  $polling=1;
NEXTPOLL:  
  $inbuf = $hash->{PortObj}->input();
  $bstring = sprintf("%c%c%c",0xfe,$cmd,0xfc);
  
  my $ret = $hash->{PortObj}->write($bstring);
  if($ret <= 0) 
  {

    my $devname = $hash->{DeviceName};
    Log 1, "USB device $devname disconnected, waiting to reappear";
    $hash->{PortObj}->close();
    $hash->{STATE} = "disconnected";
    $hash->{READINGS}{WS300Device}{VAL} = "disconnected";
    $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
    sleep(1);
    if ($^O=~/Win/) {
       $po = new Win32::SerialPort ($devname);
    }else{  
      $po = new Device::SerialPort ($devname);
    }
    if($po) 
    {
      $po->reset_error();
      $po->baudrate(19200);
      $po->databits(8);
      $po->parity('even');
      $po->stopbits(1);
      $po->handshake('none');
      $po->rts_active(1);
      $po->dtr_active(1);
      sleep(1);
      $po->rts_active(0);
      $po->write_settings;
      Log 1, "USB device $devname reappeared";
      $hash->{PortObj} = $po;
      $hash->{STATE} = "opened";
      $hash->{READINGS}{WS300Device}{VAL} = "opened";
      $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
      $polling=0;
      return;
    }
  }
  $inbuf = "";
  my $start=0;
  my $tout=time();
  my $rcount=0;
  my $ic=0;

  for(;;)
  {
    ($count,$inchar) = $hash->{PortObj}->read(1);
    if($count == 0)
    {
      last if($tout < time());
    }
    else
    {
      $ic = hex(unpack('H*',$inchar));
      if(!$start)
      {
        if($ic == 0xfe)
        {
          $start = 1;
        }
      }
      else
      {
        if($ic == 0xf8)
        {
          $escape = 1;
          $count = 0;
        }
        else
        {
          if($escape)
          {
            $ic--;
            $inbuf .= chr($ic);
            $escape = 0;
          }
          else
          {
            $inbuf .= $inchar;
            last if($ic == 0xfc);
          }
        }
      }    
      $rcount += $count;
      $tout=time();
    }
  }
  
  Log($ll,"WS300/RAW: ".$rcount." ".unpack('H*',$inbuf));
  if($ic != 0xfc)
  {
    $errcount++ if($errcount < 10);
    if($errcount == 10)
    {
      $hash->{STATE} = "timeout";
      $hash->{READINGS}{WS300Device}{VAL} = "timeout";
      $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
      $errcount++;
    }
    Log 1,"WS300: no data" if($rcount == 0);
    Log 1,"WS300: wrong data ".unpack('H*',$inbuf) if($rcount > 0);
    $polling=0;
    return;
  }
  if($hash->{STATE} ne "connected" && $errcount > 10)
  {
    $hash->{STATE} = "connected";
    $hash->{READINGS}{WS300Device}{VAL} = "connected";
    $hash->{READINGS}{WS300Device}{TIME} = TimeNow;    
  }
  $errcount = 0;
  $ic = ord(substr($inbuf,0,1));
  if($ic == 0x32)
  {
    $config = $inbuf if($rcount == 16);
    $cmd=0x31;
    goto NEXTPOLL;
  }
  if($ic == 0x31)
  {
    if($rcount == 42)
    {
       WS300_Parse($hash, $inbuf);
       goto NEXTPOLL;
    }
    else
    {
      $cmd=0x33;
      goto NEXTPOLL;
    }
  }
  if($ic == 0x33)
  {
    WS300_Parse($hash, $inbuf)	if($rcount == 39);
    $cmd=0x32;
  }
  $polling=0;
}

1;

=pod
=begin html

<a name="WS300"></a>
<h3>WS300</h3>
<ul>
  <br>

  <a name="WS300define"></a>
  <b>Define</b>
  <ul>
    <code>define WS300Device WS300 &lt;serial device&gt;</code><br>
    or<br>
    <code>define &lt;devname&gt WS300 [0-9]</code><br>
    <br>
    The first line is mandatory if you have a WS300 device: it defines the
    input device with its USB port. The name of this device is fixed and must
    be WS300Device. It must be the first defined WS300 device.<br>

    For each additional device (with number 0 to 9) you have to define another
    WS300 device, with an arbitrary name. The WS300 device which reports the
    readings will be defined with the port number 9, an optional KS300 with the
    port number 8.<br><br>

    Examples:
    <pre>
      define WS300Device  WS300   /dev/ttyUSB1
      define ash2200.1    WS300   0
      define ks300        WS300   8
      define ws300        WS300   9
    </pre>
  </ul>
  <br>

  <a name="WS300set"></a>
  <b>Set </b>
  <ul>
    <code>set WS300Device  &lt;interval(min.)&gt; &lt;height(m)&gt; &lt;rainvalume(ml)&gt;</code>
    <br><br>
    Set some WS300 configuration parameters.
  </ul>


  <a name="WS300get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="WS300attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a> (ws300)</li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
</ul>
  <br>
</ul>


=end html
=cut
