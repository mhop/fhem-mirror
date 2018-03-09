################################################################
#
#  $Id$
#
#  (c) 2014 Copyright: Wzut based on 98_EDIPLUG.pm tre (ternst)
#  All rights reserved
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
#
################################################################
#  Changelog:
#
#	2014-11-28	Initialversion by tre
#	2014-12-05	edit (Wzut)
#	2014-12-08	add schedule and list (Wzut) 
#	2014-12-09	add dellist (Wzut)
#	2015-02-21	V1.00 first svn version (Wzut)
#	2015-02-22	V1.01 add attr read-only, fix attr interval, update command.ref
#	2015-03-07	V1.02 fix schedule
#       2015-09-12	V1.03 fix errorcount and interval
#       2016-01-20      V1.04 add Reading onoff for SP2101W
#       2016-10-28      V1.05 fix wrong user on first start
#
################################################################

package main;

use strict;
use warnings;

use Time::HiRes qw(gettimeofday);    
use HttpUtils;
use SetExtensions;
use XML::Simple qw(:strict);

sub EDIPLUG_Initialize($);
sub EDIPLUG_Define($$);
sub EDIPLUG_Undef($$);
sub EDIPLUG_Set($@);
sub EDIPLUG_Get($@);
sub EDIPLUG_GetUpdate($);
sub EDIPLUG_Read($$$);


my %gets = (
   "status:noArg"   => "",
   "info:noArg"     => "",
   "power:noArg"    => "",
   "schedule:noArg" => ""
 );

my %sets = (
   "on:noArg"   => "",
   "off:noArg"  => "",
   "list"       => "",
   "addlist"    => "",
   "dellist"    => "",
   "delete:0,1,2,3,4,5,6"     => "",
   "day" => "",
   "clear_error" => ""
 );

my $data_s = "\'<?xml version=\"1.0\" encoding=\"UTF8\"?><SMARTPLUG id=\"edimax\"><CMD id=\"";
my $data_e = "></CMD></SMARTPLUG>\'";

my %datas = (
   "status"    => $data_s."get\"><Device.System.Power.State/".$data_e,
   "info"      => $data_s."get\"><SYSTEM_INFO/".$data_e,
   "power"     => $data_s."get\"><NOW_POWER/".$data_e,
   "on"        => $data_s."setup\"><Device.System.Power.State>ON</Device.System.Power.State".$data_e, 
   "off"       => $data_s."setup\"><Device.System.Power.State>OFF</Device.System.Power.State".$data_e,
   "schedule"  => $data_s."get\"><SCHEDULE/".$data_e
);

#########################################################################

sub EDIPLUG_Initialize($)
{
    my ($hash) = @_;

    $hash->{DefFn}    = "EDIPLUG_Define";
    $hash->{UndefFn}  = "EDIPLUG_Undef";
    $hash->{SetFn}    = "EDIPLUG_Set";
    $hash->{GetFn}    = "EDIPLUG_Get";
    $hash->{AttrFn}   = "EDIPLUG_Attr";
    $hash->{AttrList} = "interval timeout disable:0,1 model:SP1101W,SP2101W,unknow read-only:0,1 user password ".$readingFnAttributes;
}


################################################################################

sub EDIPLUG_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    return "wrong syntax: define <name> EDIPLUG <IP or FQDN>" if(int(@a) != 3);

    $hash->{NAME}  = $a[0];
    $hash->{host}  = $a[2];

    if( !defined( $attr{$a[0]}{interval} ) ) { $attr{$a[0]}{interval} = "60"}
    $hash->{INTERVAL}   = $attr{$a[0]}{interval};

    if( !defined( $attr{$a[0]}{user} ) ) { $attr{$a[0]}{user} = "admin"}
    $hash->{user}       = $attr{$a[0]}{user};

    if( !defined( $attr{$a[0]}{password} ) ) { $attr{$a[0]}{password} = "1234"}
    $hash->{pwd}        = $attr{$a[0]}{password};

    if( !defined( $attr{$a[0]}{model} ) ) { $attr{$a[0]}{model} = "unknow"}
    $hash->{MODEL}      = $attr{$a[0]}{model};

    if( !defined($attr{$a[0]}{'read-only'} ) ) { $attr{$a[0]}{'read-only'} = "0"}

    $hash->{POWER}           = "?";
    $hash->{LASTCMD}         = "";
    $hash->{helper}{current} = "";
    $hash->{helper}{power}   = "";

    # for non blocking HTTP Get

    $hash->{port}	= "10000";
    $hash->{url}	= "http://$hash->{user}:$hash->{pwd}\@$hash->{host}:$hash->{port}/smartplug.cgi";
    $hash->{callback}   = \&EDIPLUG_Read;
    $hash->{timeout}    = 2;
    $hash->{code}       = "";
    $hash->{httpheader} = "";
    $hash->{conn}       = "";
    $hash->{data}       = "";
    $hash->{".firststart"}    = 1;

    readingsSingleUpdate($hash, "state", "defined",0);

    for (my $i=0; $i<8; $i++) { $hash->{helper}{"list"}[$i] = ""; } # einer mehr als Tage :)

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, "EDIPLUG_GetUpdate", $hash, 0);
    #EDIPLUG_Get($hash,$hash->{NAME},"info");
    return undef;
}

################################################################################

sub EDIPLUG_Undef($$) {
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

################################################################################
 
sub EDIPLUG_GetUpdate($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if (!$init_done)
    {
     RemoveInternalTimer($hash);
     InternalTimer(gettimeofday()+5,"EDIPLUG_GetUpdate", $hash, 0);
     return;
    }

    $hash->{INTERVAL}  = AttrVal($name, "interval", $hash->{INTERVAL}) if ($hash->{INTERVAL} != 3600);

   if (($hash->{".firststart"}) && !IsDisabled($name))
   {
    Log3 $name, 5, $name.", GetUpdate (firststart)";
    $hash->{".firststart"}  = 0;
    EDIPLUG_Get($hash,$name,"info");
    InternalTimer(gettimeofday()+$hash->{timeout}+2, "EDIPLUG_GetUpdate", $hash, 1) if ($hash->{INTERVAL});
    return;
   }

    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "EDIPLUG_GetUpdate", $hash, 1) if ($hash->{INTERVAL});
    return if(IsDisabled($name));
    Log3 $name, 5, $name.", GetUpdate";
    EDIPLUG_Get($hash,$name,"status") if ($hash->{INTERVAL}); 
    return ;
}
################################################################################

sub EDIPLUG_Read($$$)
{
    my ($hash, $err, $buffer) = @_;
    my $name = $hash->{NAME};
    my $state;

    Log3 $name, 5, $name.", Read : $hash , $buffer\r\n";
    
    if ($err) 
    {
        my $error = "error";
        $error .=  " ".$hash->{code} if ($hash->{code} && ($hash->{code} ne "")); 
        $hash->{ERROR}     = $err;
        $hash->{ERRORTIME} = TimeNow();
        $hash->{ERRORCOUNT}++;
        Log3 $name, 3, "$name, return ".$error."[".$hash->{ERRORCOUNT}."] -> ".$err;
        if ($hash->{ERRORCOUNT} > 5)
        {
           Log3 $name, 3, "$name, too many errors, setting interval from ".$hash->{INTERVAL}." to 3600 seconds" if($hash->{INTERVAL} != 3600);
           $hash->{INTERVAL} = 3600;
        }
        readingsSingleUpdate($hash, "state", $error, 0);
        return;
    }

    if ($hash->{INTERVAL} == 3600) 
    { 
      my $interval = AttrVal($name, "interval", 60);
      Log3 $name, 3, "$name, set interval back to $interval seconds";
      $hash->{INTERVAL} = $interval;
    }

    # auswerten der Rueckgabe
    if (!$buffer)
    {
      # sollte eigentlich gar nicht vorkommen bzw. nur bei fehlerhaften uebergebenen XML String  
      $hash->{ERRORCOUNT}++;
      Log3 $name, 3, "$name, empty return buffer [".$hash->{ERRORCOUNT}."]";
      $hash->{ERROR}     = "empty return buffer";
      $hash->{ERRORTIME} = TimeNow();
      return;
    }

    $hash->{ERRORCOUNT} = 0;

    readingsBeginUpdate($hash);

    # EDIPLUGs geben ein nicht gueltigen Zeichensatz zurueck ( UTF8 instead utf-8 )
    $buffer =~s/UTF8/utf-8/g;

    my $xml = XML::Simple->new(ForceArray => ['entry', 'link'], KeyAttr => []);
    my $xmlres = $xml->XMLin($buffer);

    # Device.System.Power.State (Status der Steckdose)
    if (exists $xmlres->{CMD}->{'Device.System.Power.State'}) 
    {
        if ($hash->{MODEL} eq "SP2101W")
        {
          $hash->{POWER} = uc($xmlres->{CMD}->{'Device.System.Power.State'});
          readingsBulkUpdate($hash, "onoff", lc($hash->{POWER}));
          $state = ($hash->{POWER} ne "OFF") ? $hash->{POWER}." / ".$hash->{helper}{power}. " W / ".$hash->{helper}{current}." A" : $hash->{POWER};
        }
        else
        {
          $state = lc($xmlres->{CMD}->{'Device.System.Power.State'});
        }
    }

    # SYSTEM_INFO 
    if (exists $xmlres->{CMD}->{SYSTEM_INFO}) 
    {
	$hash->{'MODEL'} = $xmlres->{CMD}->{SYSTEM_INFO}->{'Run.Model'};
	$hash->{'VERSION'} = $xmlres->{CMD}->{SYSTEM_INFO}->{'Run.FW.Version'};
	$hash->{'MAC'} = $xmlres->{CMD}->{SYSTEM_INFO}->{'Run.LAN.Client.MAC.Address'};
        $hash->{'PName'} = $xmlres->{CMD}->{SYSTEM_INFO}->{'Device.System.Name'};
    }

    if ((exists $xmlres->{CMD}->{NOW_POWER}) && ($hash->{MODEL} eq "SP2101W"))
    {
     # POWER_NOW
     my $ltt = $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.LastToggleTime'};
     my $ltt_s = substr($ltt,8,2).":".substr($ltt,10,2).":".substr($ltt,12,2) ." ".substr($ltt,6,2).".".substr($ltt,4,2).".".substr($ltt,0,4);
     
     readingsBulkUpdate($hash, "last_Toggle_Time", $ltt_s) if ($ltt ne "0");
     
     $hash->{helper}{current} = $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowCurrent'};
     readingsBulkUpdate($hash, "current", $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowCurrent'}." A");
     
     $hash->{helper}{power}  = $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowPower'};
     
     readingsBulkUpdate($hash, "power_now", $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowPower'}." W");
     readingsBulkUpdate($hash, "power_day", $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowEnergy.Day'}." kWh");
     readingsBulkUpdate($hash, "power_week", $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowEnergy.Week'}." kWh");
     readingsBulkUpdate($hash, "power_month", $xmlres->{CMD}->{NOW_POWER}->{'Device.System.Power.NowEnergy.Month'}." kWh");
     
     $state = ($hash->{POWER} ne "OFF") ? $hash->{POWER}." / ".$hash->{helper}{power}. " W / ".$hash->{helper}{current}." A" : $hash->{POWER};
    }

    
    my @days=("0.So","1.Mo","2.Di","3.Mi","4.Do","5.Fr","6.Sa");
    for (my $i=0; $i<7; $i++)
    {
     if (exists $xmlres->{CMD}{SCHEDULE}{'Device.System.Power.Schedule.'.$i.'.List'}) 
     {
      $hash->{helper}{"list"}[$i] = $xmlres->{CMD}{SCHEDULE}{'Device.System.Power.Schedule.'.$i.'.List'}; # die heben wir auf
      $hash->{helper}{"list"}[7] = "1"; # es ist eine aktuelle Liste vorhanden

      my $zeit = decode_list($hash->{helper}{"list"}[$i]);
      readingsBulkUpdate($hash, $days[$i] , lc($xmlres->{CMD}{SCHEDULE}{'Device.System.Power.Schedule.'.$i}{value}));
      if ($zeit ne "") { readingsBulkUpdate($hash, $days[$i].".list" ,  $zeit); }
                  else { readingsBulkUpdate($hash, $days[$i].".list" ,  "no list on device");}
     }
    }

    readingsBulkUpdate($hash,"state",$state) if ($state);
    readingsEndUpdate($hash, 1 );

    # nach set on/off oder erstem Durchlauf sofort neuen Status holen 
    if (($hash->{LASTCMD} eq "on")     ||
        ($hash->{LASTCMD} eq "off")    || 
        ($hash->{STATE}   eq "defined"))
     { 
       $hash->{LASTCMD} = "";
       select(undef, undef, undef, 1); # TODO , sehr hässlich - aber irgend eine Wartezeit muss sein
       EDIPLUG_Get($hash,$name,"status");
     }    
     # und nach dem Status noch fuer die 2101 die aktuellen Power Werte
     elsif (($hash->{LASTCMD} eq "status") && ($hash->{MODEL} eq "SP2101W")) 
       { 
         EDIPLUG_Get($hash,$name,"power"); 
       }    
     elsif (($hash->{LASTCMD} eq "addlist") || 
            ($hash->{LASTCMD} eq "list")    ||
            ($hash->{LASTCMD} eq "dellist") ||
            ($hash->{LASTCMD} eq "delete")  ||
            ($hash->{LASTCMD} eq "day")) 
       { 
         select(undef, undef, undef, 2); # TODO , sehr hässlich - aber irgend eine Wartezeit muss sein
         EDIPLUG_Get($hash,$name,"schedule"); # geaenderte Liste holen
       }    

     return;
}


################################################################################

sub EDIPLUG_Attr(@) 
{

 my ($cmd,$name, $attrName,$attrVal) = @_;
 my $hash = $defs{$name};

 if ($cmd eq "set")
 {
  if ($attrName eq "disable")
   {
     RemoveInternalTimer($hash);
     $hash->{INTERVAL}  = 0 if $attrVal;
     readingsSingleUpdate($hash, "state", "disabled",0) if (!$hash->{INTERVAL});
     InternalTimer(gettimeofday()+$hash->{INTERVAL}, "EDIPLUG_GetUpdate", $hash, 1) if ($hash->{INTERVAL}>0);
   }
   elsif ($attrName eq "timeout")
   {
     $hash->{timeout}  = $attrVal;
     $attr{$name}{timeout} = $attrVal;
   }
  elsif ($attrName eq "interval")
   {
       $hash->{INTERVAL}   = $attrVal;
       $attr{$name}{interval} = $attrVal;
   }
  elsif ($attrName eq "model")
   {
       $hash->{MODEL}   = $attrVal;
       $attr{$name}{model} = $attrVal;
   }
  elsif ($attrName eq "user")
   {
       $hash->{user}   = $attrVal;
       $attr{$name}{user} = $attrVal;
       $hash->{url}	= "http://$hash->{user}:$hash->{pwd}\@$hash->{host}:$hash->{port}/smartplug.cgi";
   }
  elsif ($attrName eq "password")
   {
       $hash->{pwd}   = $attrVal;
       $attr{$name}{password} = $attrVal;
       $hash->{url}	= "http://$hash->{user}:$hash->{pwd}\@$hash->{host}:$hash->{port}/smartplug.cgi";
   }

 }
 elsif ($cmd eq "del")
 {
   if ($attrName eq "disable")
   {
    RemoveInternalTimer($hash);
    readingsSingleUpdate($hash, "state", "???",0) if (!$hash->{INTERVAL});
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "EDIPLUG_GetUpdate", $hash, 1) if ($hash->{INTERVAL});
   }
   elsif ($attrName eq "interval")
   {
    $hash->{INTERVAL}   = 60;
   } 
 }
   return undef;
}

################################################################################

sub EDIPLUG_Set($@) {
   my ($hash, $name , @a) = @_;
   my $cmd = $a[0];
   

  return "set $name needs at least one argument" if(int(@a) < 1);
  return  ($cmd eq "?") ? undef : "no set commands are allowed on a read-only device !" if ($attr{$name}{'read-only'} eq "1");
  return  ($cmd eq "?") ? undef : "no set commands are allowed on a disabled device!" if(IsDisabled($name));

   my $list = "on off list addlist delete:0,1,2,3,4,5,6 dellist day clear_error";

   return SetExtensions($hash, $list, $name, @a) if( $cmd eq "?" );
   return SetExtensions($hash, $list, $name, @a) if( !grep( $_ =~ /^$cmd($|:)/, split( ' ', $list)));


   $hash->{timeout} = AttrVal($name, "timeout", 2);

   my $oldcmd = $hash->{LASTCMD}; $hash->{LASTCMD}="";

      if($cmd eq "clear_error")
   {
      $hash->{ERROR}      = undef;
      $hash->{ERRORCOUNT} = 0;
      $hash->{LASTCMD}    = $cmd;
      return undef;
   }

   if(($cmd eq "on") || ($cmd eq "off"))
   {
    $hash->{LASTCMD} = $cmd;
    $hash->{data}    = $datas{$cmd};
   }
   elsif(($cmd eq "list") || ($cmd eq "addlist") || ($cmd eq "dellist"))
   {
      return "set $name $cmd : DayOfWeek(0-6) Starttime(hh:mm) Endtime(hh:mm) Command(on/off) e.g. 1 10:00 11:30 on" if(int(@a) < 4);

      shift @a; 
      my $day = $a[0];
      shift @a;

      return "set $name $cmd : wrong day $day, please use 0-6" if (($day >6) || ($day <0));
      return "set $name $cmd : wrong start time,missing : !" if (index($a[0],":") < 0);
      return "set $name $cmd : wrong end time, missing :  !" if (index($a[1],":") < 0);
      return "set $name $cmd : don't use the same start and end time !" if ($a[0] eq $a[1]);
      return "set $name $cmd : wrong on/off command, use on or off" if (($a[2] ne "on") && ($a[2] ne "off") && ($cmd ne "dellist")) ;

      my $ret = encode_list(@a);
      return "set $name $cmd is to short ($ret)" if (length($ret) != 5);

      if ($cmd eq "addlist") 
      { 
        return "set $name $cmd : internal schedule list is empty, please use 'get $name schedule' first" if($hash->{helper}{"list"}[7] eq "");
        return "set $name $cmd : start and end time block already exist !" if (index($hash->{helper}{"list"}[$day],$ret) > -1) ;

        # Time Block schon vorhanden , aber jetzt on/off Umschaltung ?
        my $reverse_cmd = substr($ret,0,4);
        $reverse_cmd .= ($a[2] eq "on") ? "0" : "1";
        $hash->{helper}{"list"}[$day] =~ s/$reverse_cmd/$ret/g; # alt gegen neu tauschen
        # Block hinzufügen oder fertig ?
        if (index($hash->{helper}{"list"}[$day],$ret) > -1) 
             { $ret = $hash->{helper}{"list"}[$day]; }
        else 
             { $ret = $hash->{helper}{"list"}[$day]."-".$ret; }

      }
      elsif ($cmd eq "dellist") 
      { 
        $ret = substr($ret,0,4)."0"; # ist er als off definert ?
        my $pos = index($hash->{helper}{"list"}[$day],$ret);
        if ($pos<0) # oder doch als on ?
         {
           $ret = substr($ret,0,4)."1"; 
           $pos = index($hash->{helper}{"list"}[$day],$ret);
         }
 
        return "set $name $cmd : day $day, start and end time block do not exist" if ($pos<0);

        $hash->{helper}{"list"}[$day] =~ s/$ret//g; # raus aus der Liste
        $hash->{helper}{"list"}[$day] =~ s/\--/\-/g; # eventuelle jetzt noch vorhandene doppelte Minuszeichen bereinigen
        # war das erste von mehr als einem ?
        if (index($hash->{helper}{"list"}[$day], "-")  == 0) { $hash->{helper}{"list"}[$day] = substr($hash->{helper}{"list"}[$day],1); }
        # oder der letzte von mehr als einem ?
        if (rindex($hash->{helper}{"list"}[$day], "-") == length($hash->{helper}{"list"}[$day])-1) { chop($hash->{helper}{"list"}[$day]); }

        $ret = $hash->{helper}{"list"}[$day];
      }
      
      $hash->{LASTCMD} = $cmd; # merken und später Liste neu holen

      $hash->{data}  = $data_s."setup\"><SCHEDULE><Device.System.Power.Schedule.".$day.".List>".$ret;
      $hash->{data} .= "</Device.System.Power.Schedule.".$day.".List></SCHEDULE".$data_e;
   }
   elsif($cmd eq "day") 
   {
      return "set $name $cmd : DayOfWeek(0-6) Command(on/off) e.g. 1 on" if(int(@a) < 3);
      shift @a; 
      my $day    = $a[0];
      my $oocmd =  $a[1];
      return "set $name $cmd : wrong day $day, use 0-6" if (($day >6) || ($day <0));
      return "set $name $cmd : wrong on/off command, please use on or off" if (($oocmd ne "on") && ($oocmd ne "off"));
      return "set $name $cmd : schedule list is empty, please use 'get $name schedule' first" if($hash->{helper}{"list"}[7] eq "");

      $hash->{LASTCMD} = $cmd;
      $hash->{data}  = $data_s."setup\"><SCHEDULE><Device.System.Power.Schedule.".$day." value=\"".uc($oocmd)."\"></Device.System.Power.Schedule.".$day."></SCHEDULE".$data_e;

   }
   elsif($cmd eq "delete")
   {
      return "set $name $cmd : DayOfWeek(0-6)" if(int(@a) < 2);
      shift @a; 
      my $day    = $a[0];
      return "set $name $cmd : wrong day $day, please use 0-6" if (($day >6) || ($day <0));
      $hash->{LASTCMD} = $cmd; 

      $hash->{data}  = $data_s."setup\"><SCHEDULE><Device.System.Power.Schedule.".$day.".List /".$data_e;
   }

   # Haben wir jetzt ein neues Set Kommando ?
   if ($hash->{LASTCMD}) 
   { 
      #return $hash->{data}; # Debug nur anzeigem
      $hash->{code}       = "";
      HttpUtils_NonblockingGet($hash);
      return undef;
   }


 # Hier sollten wir eigentlich nie hinkommen ..
 $hash->{LASTCMD} = $oldcmd;

 return "$name set with unknown argument $cmd, choose one of " . join(" ", sort keys %sets); 

}
                                                                                                             

################################################################################

sub EDIPLUG_Get($@) {
   my ($hash, @a) = @_;
   my $name= $hash->{NAME};

   return "get $name needs at least one argument" if(int(@a) < 2);
   return "no get commands are allowed on a disabled device !" if(IsDisabled($name));
   my $cmd = $a[1];

   return "$name get power is not supported by this model !" if (($cmd eq "power") && ($hash->{MODEL} ne "SP2101W"));

   $hash->{data} = $datas{$cmd};

    if($hash->{data})
    {
     $hash->{LASTCMD}    = $cmd;
     $hash->{timeout}    = AttrVal($name, "timeout", 2);
     #$hash->{buf}        = "";
     $hash->{code}       = "";
     #$hash->{httpheader} = "";
     #$hash->{conn}       = "";
     #$hash->{data}       = "";
     HttpUtils_NonblockingGet($hash);
     return ;
    }

   return "$name get with unknown argument $cmd, choose one of " . join(" ", sort keys %gets); 

}

################################################################################
sub decode_list($)
{
  # Bsp : 10111-01020-nX001
  my ($string) = @_ ;
  return "" if (length($string)<5); # zu kurz
  # die beiden Sonderfaelle - ganzer Tag an  oder aus 
  return "00:00-24:00 on" if ($string eq "00001");
  return "00:00-24:00 off" if ($string eq "00000");

  my @a = split("-",$string);
  my @sorted = sort @a;
  my $s="";  

  my $timetab = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";  # nur 0 - 59 wird gebraucht

  foreach(@sorted)
  {
     my $cmd = $_;

     return "" if (index($timetab, substr($cmd,0,1)) > 23); #TODO den HASH besser erkennen

     $s .= (length($s)) ? " / " : "";

     # Begin Stunde
     $s .= sprintf("%02d:",index($timetab, substr($cmd,0,1)));
     # Begin Minute
     $s .= sprintf("%02d-",index($timetab, substr($cmd,1,1))); 
     # Ende Stunde
     $s .= sprintf("%02d:", index($timetab, substr($cmd,2,1))); 
     # Ende Minute
     $s .= sprintf("%02d", index($timetab, substr($cmd,3,1))); 
     # ON or OFF ?
     $s .= (substr($cmd,4,1) eq "0") ? " off"  : " on";
  }
  return $s;
}
################################################################################
sub encode_list(@)
{
  my ($start,$end,$cmd) = @_;
  my $ret;

  my $timetab = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWX";  # 0 - 59
  
  my ($sh,$sm) = split(":",$start);
  $sh++; $sh--; $sm++; $sm--; # fuuehrende Nullen weg
  return "wrong start hour !"   if ($sh > 23);
  return "wrong start minute !" if ($sm > 59);
  $ret  = substr($timetab,$sh,1); 
  $ret .= substr($timetab,$sm,1);
  
  my ($eh, $em) = split(":",$end);
  $eh++; $eh--; $em++; $em--; 
  $eh = 0 if (($eh == 24) && ($em == 0)); # den Sonderfall 24:00 Uhr zulassen !
  return "wrong end hour !"   if ($eh > 23);
  return "wrong end minute !" if ($em > 59);
  return "starttime is after endtime !" if ($sh > $eh);
  return "starttime is after endtime !" if (($sh == $eh) && ($sm > $em));

  $ret .= substr($timetab,$eh,1); 
  $ret .= substr($timetab,$em,1);

  return "don't use the same start and end time !" if (substr($ret,0,2) eq substr($ret,2,2)) && (($eh != 0) && ($em != 0));

  $ret .= ($cmd eq "on") ? "1" : "0";
  return $ret;

} 
################################################################################

1;

=pod
=item device
=item summary  controls EDIPLUG SP2101W / SP1101W WLAN switches
=item summary_DE steuert EDIPLUG SP2101W / SP1101W WLAN Schaltsteckdosen
=begin html

<a name="EDIPLUG"></a>
<h3>EDIPLUG</h3>
FHEM module to control the Edimax Smart Plug Switches SP-2101W and SP-1101W (http://www.edimax.com)<br>
FHEM Forum : <a href="http://forum.fhem.de/index.php/topic,29541.0.html">http://forum.fhem.de/index.php/topic,29541.0.html</a><br> 
SP-2101W - Edimax Smart Plug Switch with Power Meter<br>
SP-1101W - Edimax Smart Plug Switch<br>
requires XML:Simple -> sudo apt-get install libxml-simple-perl<br>
<br>
<ul>
 <a name="EDIPLUGdefine"></a>
  <b>Define</b>
  <ul>
  define &lt;name&gt; EDIPLUG &lt; IP_EDIMAX_Device (or FQDN) &gt;<br>
  Example:<br>
  <li>define myediplug EDIPLUG 192.168.0.99</li>
  <li>define myediplug EDIPLUG ediplug.myhome.net</li>
  </ul>
  <a name="EDIPLUGset"></a>
  <b>Set</b>
  <ul>
  <li>on        => switch power on</li>
  <li>off       => switch power off</li>
  <li>list      => set a new list for one day with one entry : DayOfWeek(0-6) Starttime(hh:mm) Endtime(hh:mm) Command(on/off) e.g. 1 10:00 11:30 on<br>
                   use (DayOfWeek) 00:00 24:00 on to switch the complete day on</li>
  <li>addlist   => add a new on/off time : DayOfWeek(0-6) Starttime(hh:mm) Endtime(hh:mm) Command(on/off) e.g. 1 10:00 11:30 on</li>
  <li>dellist   => remove a existing on/off time : DayOfWeek(0-6) Starttime(hh:mm) Endtime(hh:mm) e.g. 1 10:00 11:30</li>
  <li>delete    => delete timelist of one day : DayOfWeek(0-6)</li>
  <li>day       => enable/disable timeschedule for one day : DayOfWeek(0-6) on/off</li>
  </ul>
  <a name="EDIPLUGget"></a>
  <b>Get</b><ul>
  <li>info     => shows MAC , Firmware Version , Model , Name</li>
  <li>power    => shows all Power informations ( model SP-2101W only)</li>
  <li>schedule => show all internal on/off timetables</li>
  <li>status   => show on/off state</li>
  </ul>
  <a name="EDIPLUGattr"></a>
  <b>Attributes</b>
  <ul>
  <li>interval  => polling interval (default 60)</li>
  <li>timeout   => max. time to wait in seconds (default 2)</li>
  <li>read-only => only read (Get) from device (default 0)</li>
  <li>user      => username (default admin)</li>
  <li>password  => password (default 1234)</li>
 </ul>
  <br>
  <b>Readings</b>
  <ul>
  <li>0.So       -> switching times Sunday</li>
  <li>0.So.state -> Sunday switching on/off</li>
  <li>.</li>
  <li>.</li>
  <li>.</li>
  <li>6.Sa       -> switching times Saturday</li>
  <li>6.Sa.state -> Saturday switching on/off ( model SP-2101W only )</li>
  <li>last_Toggle_Time ( model SP-2101W only )</li>
  <li>current ( model SP-2101W only )</li>
  <li>power_now ( model SP-2101W only )</li>
  <li>power_day ( model SP-2101W only )</li>
  <li>power_week ( model SP-2101W only )</li>
  <li>power_month ( model SP-2101W only )</li>
  </ul>
</ul>
=end html

=begin html_DE

<a name="EDIPLUG"></a>
<h3>EDIPLUG</h3>
FHEM Module f&uuml;r die Edimax Smart Plug Switches SP-2101W und SP-1101W (http://www.edimax.com)<br>
FHEM Forum : <a href="http://forum.fhem.de/index.php/topic,29541.0.html">http://forum.fhem.de/index.php/topic,29541.0.html</a><br> 
SP-2101W - Edimax Smart Plug Switch mit Strom Verbrauchsmessung<br>
SP-1101W - Edimax Smart Plug Switch<br>
ben&oml;ntigt XML:Simple -> sudo apt-get install libxml-simple-perl
<br>
<ul>
 <a name="EDIPLUGdefine"></a>
  <b>Define</b>
  <ul>
  define &lt;name&gt; EDIPLUG  IP_des_EDIPlug (oder FQDN Name)<br>
  Beispiel:<br>
  <li>define myediplug EDIPLUG 192.168.0.99</li>
  <li>define myediplug EDIPLUG ediplug.fritz.box</li>
  </ul>
  <br>
  <a name="EDIPLUGset"></a>
  <b>Set</b>
  <ul>
  <li>on        => schalte an</li>
  <li>off       => schalte aus</li>
  <li>list      => erzeugt eine neue Zeitplan Liste mit einem Eintrag : Wochentag(0-6) Startzeit(hh:mm) Endezeit(hh:mm) Kommando(on/off) Bsp. 1 10:00 11:30 on<br>
                   mit Wochentag 00:00 24:00 on kann man den kompletten Tag einschalten</li>
  <li>addlist   => f&uuml;gt eine neue Schaltzeit einer bestehenden Zeitplan Liste hinzu : Wochentag(0-6) Startzeit(hh:mm) Endtezeit(hh:mm) Kommando(on/off) Bsp. 1 10:00 11:30 on</li>
  <li>dellist   => l&ouml;scht eine bestimmte Schaltzeit eines Tages : Wochentag(0-6) Startzeit(hh:mm) Endezeit(hh:mm) Bsp. 1 10:00 11:30</li>
  <li>delete    => l&ouml;scht die Liste eines ganzen Tages : Wochentag(0-6)</li>
  <li>day       => schaltet die Zeitplanung eines Tages ein oder aus : Wochentag(0-6) on/off Bsp. 5 on</li>
  </ul>
  <br>
  <a name="EDIPLUGget"></a>
  <b>Get</b>
  <ul>
  <li>info     => Anzeige von MAC , Firmware Version , Modell , Name</li>
  <li>power    => zeigt alle Stromverbrauchswerte ( nur Modell SP-2101W )</li>
  <li>schedule => zeigt alle internen Schaltzeiten (ACHTUNG : Firmware Version beachten !)</li>
  <li>status   => zeigt an/aus Status der Schaltdose</li>
  </ul>
  <br>
  <a name="EDIPLUGattr"></a>
  <b>Attributes</b>
  <ul>
  <li>interval  => polling interval (default 60)</li>
  <li>timeout   => max. Wartezeit in Sekunden (default 2)</li>
  <li>read-only => es ist nur lesen (Get) erlaubt (default 0)</li>
  <li>user      => Username (default admin)</li>
  <li>password  => Passwort (default 1234)</li>
  </ul>
  <br>
  <b>Readings</b>
  <ul>
  <li>0.So       -> Schaltzeiten Sonntag</li>
  <li>0.So.state -> Sonntag an/aus</li>
  <li>.</li>
  <li>.</li>
  <li>.</li>
  <li>6.Sa       -> Schaltzeiten Samstag</li>
  <li>6.Sa.state -> Samstag an/aus</li>
  <li>last_Toggle_Time ( nur Modell SP-2101W)</li>
  <li>current (nur Modell SP-2101W)</li>
  <li>power_now (nur Modell SP-2101W)</li>
  <li>power_day (nur Modell SP-2101W)</li>
  <li>power_week (nur Modell SP-2101W)</li>
  <li>power_month (nur Modell SP-2101W)</li>
  </ul>
</ul>

=end html_DE

=cut
