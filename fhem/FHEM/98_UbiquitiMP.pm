################################################################
#
#  $Id$
#
#  (c) 2015 Copyright: Wzut
#  forum : http://forum.fhem.de/index.php/topic,35722.0.html
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
#  25.3.15 add force for set on and off
#  10.04.15 add enable/disable 
#  18.04.15 add toggle
#  20.04.15 add Groups
#  first svn Version
#  23.04.15 add Set Extensions for 1 Port Ubi , change Client to UbiquitiOut, 
#  25.06.15 add german docu, fix some timing problems

package main;


use strict;
use warnings;
use Time::HiRes qw(gettimeofday);    
use Blocking; # http://www.fhemwiki.de/wiki/Blocking_Call
use SetExtensions;
use Net::Telnet;
use JSON;

my %sets = ();
my $setcmds = "on,off,toggle,enable,disable,lock,unlock,reset";

#########################################################################

sub UbiquitiMP_Initialize($)
{
    my ($hash) = @_;
    $hash->{DefFn}    = "UbiquitiMP_Define";
    $hash->{UndefFn}  = "UbiquitiMP_Undef";
    $hash->{SetFn}    = "UbiquitiMP_Set";
    $hash->{GetFn}    = "UbiquitiMP_Get";
    $hash->{AttrFn}   = "UbiquitiMP_Attr";
    $hash->{FW_summaryFn} = "UbiquitiMP_summaryFn";
    $hash->{AttrList} = "interval timeout user password subDevices:0,1 ignoreList ledconnect:off,blue,yellow,both,alternate groupPorts ".$readingFnAttributes;
}

sub UbiquitiMP_updateConfig($)
{
  # this routine is called 5 sec after the last define of a restart
  # this gives FHEM sufficient time to fill in attributes

 my ($hash) = @_;
 my $name = $hash->{NAME};
 
 if (!$init_done)
 {
   RemoveInternalTimer($hash);
   InternalTimer(gettimeofday()+5,"UbiquitiMP_updateConfig", $hash, 0);
   return;
 }


 $hash->{INTERVAL} = AttrVal($name, "interval", 300);
 $hash->{".led"}   = AttrVal($name, "ledconnect", 0);

 if ($hash->{".led"}) # Farben nach Kommando
 {
    $hash->{".led"} = "0" if ($hash->{".led"} eq "off");
    $hash->{".led"} = "1" if ($hash->{".led"} eq "blue");
    $hash->{".led"} = "2" if ($hash->{".led"} eq "yellow");
    $hash->{".led"} = "3" if ($hash->{".led"} eq "both");
    $hash->{".led"} = "4" if ($hash->{".led"} eq "alternate");
 }

 $hash->{MAC} = "";
 $hash->{lastcmd} = "Init";
 $hash->{".init"} = 1;
 RemoveInternalTimer($hash);
 InternalTimer(gettimeofday()+5, "UbiquitiMP_GetStatus",$hash, 0);

  return undef;
}

################################################################################

sub UbiquitiMP_Define($$) {

    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @a = split("[ \t][ \t]*", $def);

    return "wrong syntax: define <name> UbiquitiMP <IP or FQDN>" if(int(@a) < 3);

    $hash->{".host"}  = $a[2];

    if( !defined( $attr{$a[0]}{user} ) ) { $attr{$a[0]}{user} = "ubnt";}
    $hash->{".user"}       = $attr{$a[0]}{user};

    if( !defined( $attr{$a[0]}{password} ) ) { $attr{$a[0]}{password} = "ubnt";}
    $hash->{".pwd"}        = $attr{$a[0]}{password};

    if( !defined( $attr{$a[0]}{subDevices} ) ) { $attr{$a[0]}{subDevices} = "1";}

    if( !defined( $attr{$a[0]}{timeout} ) ) { $attr{$a[0]}{timeout} = "5"}
    $hash->{".timeout"} = (int($attr{$a[0]}{timeout}) > 1) ? $attr{$a[0]}{timeout} : "5";

    if( !defined( $attr{$a[0]}{subDevices} ) ) { $attr{$a[0]}{subDevices} = "1"}
    $hash->{".subdevices"} = $attr{$a[0]}{subDevices};

    $hash->{Clients}    = ":UbiquitiOut:";
    $hash->{PORTS}      = 0;
    $hash->{force}      = 0;
    $hash->{ERRORCOUNT} = 0;

    readingsSingleUpdate($hash, "state", "defined",0);

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, "UbiquitiMP_updateConfig",$hash,0); # in 5 Sekunden machen wir den Rest

    return undef;
}

################################################################################

sub UbiquitiMP_Undef($$) 
{
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    if(defined($hash->{helper}{RUNNING_PID}))
    {
     BlockingKill($hash->{helper}{RUNNING_PID});
    }
    return undef;
}

################################################################################

sub UbiquitiMP_force($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $cmdlist = $hash->{lastcmd};

  Log3 $name, 4, "$name, force called for $cmdlist";

  $hash->{helper}{RUNNING_PID} = BlockingCall("UbiquitiMP_BCStart", $cmdlist, "UbiquitiMP_BCDone",(int($hash->{".timeout"})*3),"UbiquitiMP_BCAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));

  RemoveInternalTimer($hash);

  if($hash->{helper}{RUNNING_PID})
  { 
    Log3 $name, 5, "$name, BC force process started with PID(".$hash->{helper}{RUNNING_PID}{pid}.") cmd : $cmdlist";
  }
   else
  { # das war wohl schon wieder nix :(
   InternalTimer(gettimeofday()+(int($hash->{".timeout"})*3), "UbiquitiMP_force",$hash, 0);
  }

  return undef;
}

################################################################################

sub UbiquitiMP_Attr(@) 
{

 my ($cmd,$name, $attrName,$attrVal) = @_;
 my $hash = $defs{$name};

 if ($cmd eq "set")
 {

   if ($attrName eq "timeout")
   {
     if (int($attrVal) < 2) {$attrVal="5";}
     $hash->{".timeout"}  = $attrVal;
     $attr{$name}{timeout} = $attrVal;
   }
   elsif ($attrName eq "user")
   {
       $hash->{".user"}   = $attrVal;
       $attr{$name}{user} = $attrVal;
   }
  elsif ($attrName eq "password")
   {
       $hash->{".pwd"}   = $attrVal;
       $attr{$name}{password} = $attrVal;
   }
   elsif ($attrName eq "interval")
   {
       $hash->{INTERVAL}   = $attrVal;
       $attr{$name}{interval} = $attrVal;
   }

   elsif ($attrName eq "subDevices")
   {
       $hash->{".subdevices"}   = $attrVal;
       $attr{$name}{subDevices} = $attrVal;
   }
   elsif ($attrName eq "ledconnect")
   {
       $hash->{".led"} = "0" if ($attrVal eq "off");
       $hash->{".led"} = "1" if ($attrVal eq "blue");
       $hash->{".led"} = "2" if ($attrVal eq "yellow");
       $hash->{".led"} = "3" if ($attrVal eq "both");
       $hash->{".led"} = "4" if ($attrVal eq "alternate");
       $attr{$name}{ledconnect} = $attrVal;
   }
   elsif ($attrName eq "groupPorts")
   {
     $attr{$name}{groupPorts} = $attrVal;
     UbiquitiMP_createSets($hash);
   }
 }

   return undef;
}

################################################################################

sub UbiquitiMP_Get($@) {
   my ($hash, $name , @a) = @_;
   my $cmd = $a[0];

   return "get $name needs one argument" if (int(@a) != 1);

   return "Unknown argument $cmd, choose one of status:noArg info:noArg reboot:noArg" if($cmd !~ /^(status|info|reboot)$/);

  $hash->{force} = 0; # Get setzt IMMER force zurueck !

  if ($cmd eq "info")
  { $cmd = $name."#info#cat /etc/board.info | grep board;"; $hash->{lastcmd} ="GetInfo";}
  elsif ($cmd eq "status") 
  { $cmd = $name."#status#/sbin/cgi /usr/www/mfi/sensors.cgi#awk '{print \"u=\"\$1}' < /proc/uptime#awk '{print \"l=\"\$1\" \"\$2\" \"\$3}' < /proc/loadavg#cat /proc/power/energy_sum* | tr '\\n' ' '"; $hash->{lastcmd} ="GetStatus";}
  elsif ($cmd eq "reboot") 
  { $cmd = $name."#reboot#reboot"; $hash->{lastcmd} ="GetReboot";}
  else { return undef; } # sollte eigentlich nie vorkommen 

  $hash->{helper}{RUNNING_PID} = BlockingCall("UbiquitiMP_BCStart", $cmd, "UbiquitiMP_BCDone",(int($hash->{".timeout"})*2),"UbiquitiMP_BCAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
  if($hash->{helper}{RUNNING_PID})
  { 
    RemoveInternalTimer($hash);
    Log3 $name, 5, "$name, BC process started with PID(".$hash->{helper}{RUNNING_PID}{pid}.") cmd : $cmd"; 
  }
   else  
  { # das war wohl nix :(
    Log3 $name, 3,  "$name, BC process start failed, cmd : $cmd "; 
    return $name.", can't execute get command as NonBlockingCall";
  }

   return undef;
}

################################################################################

sub UbiquitiMP_Set($@) {
   my ($hash,  @a) = @_;
   my $name = $hash->{NAME};
   my ($port,$cmd,$subcmd);

   return undef if (!$hash->{PORTS}); # ohne bekannte Ports geht hier nichts :)

   UbiquitiMP_createSets($hash) if(!defined($sets{Out1}) && $hash->{PORTS}); # neu aufbauen nach reload;
 
   if (int($hash->{PORTS}) > 1)
   {
     $port    = (defined($a[1])) ? $a[1] : "?" ;
     $cmd     = (defined($a[2])) ? $a[2] : "";
     $subcmd  = (defined($a[3])) ? $a[3] : "";

     if(!defined($sets{$port})) 
     {
      my @commands = ();
      foreach my $key (sort keys %sets) 
      {
       push @commands, $sets{$key} ? $key.":".join(",",$sets{$key}) : $key;
      }
      return "Unknown port $port, choose one of " . join(" ", @commands);
     }
      return "$name wrong command, please use on of on,off,toggle,lock,unlock,enable,disable or reset" if($cmd !~ /^(on|off|lock|unlock|reset|enable|disable|toggle)$/);
   }
   else # die mPower mini
   {
     $port    = "Out1";
     $cmd     = (defined($a[1])) ? $a[1] : "";
     $subcmd  = (defined($a[2])) ? $a[2] : "";
     $setcmds =~ s/\,/ /g;
     shift(@a);
     return SetExtensions($hash,$setcmds,$name,@a) if($cmd !~ /^(on|off|lock|unlock|reset|enable|disable|toggle)$/);
   }

   my $cmdlist = "$name#$cmd";

    if ($hash->{force})
    {
       my $ret = "a force command is already active -> PID ".$hash->{force}." cmd : ".$hash->{lastcmd};
       Log3 $name, 3, "$name, $ret";
       return $ret;
    }


    if ((substr($port,0,3) eq "Out") && (int(substr($port,3,1)) > 0) && (int(substr($port,3,1)) <= int($hash->{PORTS})))
     { $cmdlist .= "#".substr($port,3,1); }  # normaler einzelner Port
    else # oder doch eine Port Gruppe ?
     { 
        @a = split("," ,$hash->{"group_".$port});
        foreach (@a) 
        { 
         return "Unknown port $_ in group list $port !" if ((int($_) < 1) || (int($_) > int($hash->{PORTS}))); 
         $cmdlist .="#".$_; 
        }
     }

  $hash->{lastcmd} = $cmdlist;

  $hash->{helper}{RUNNING_PID} = BlockingCall("UbiquitiMP_BCStart", $cmdlist, "UbiquitiMP_BCDone",(int($hash->{".timeout"})*3),"UbiquitiMP_BCAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));

  if($hash->{helper}{RUNNING_PID})
  { 
    RemoveInternalTimer($hash);
    $hash->{force}   = ($subcmd eq "force") ? $hash->{helper}{RUNNING_PID}{pid} : 0;
    Log3 $name, 5, "$name, BC process started with PID(".$hash->{helper}{RUNNING_PID}{pid}.") cmd : $cmdlist , subcmd : $subcmd"; 
  }
   else
  { # das war wohl nix :(
    Log3 $name, 3,  "$name, BC process start failed , cmd : $cmdlist , subcmd : $subcmd";
    UbiquitiMP_force($hash) if ($hash->{force}) ; # muessen wir das wiederholen ?
    return $name.", can't execute set as NonBlockingCall";
  }

   return undef;
}

################################################################################

sub UbiquitiMP_BCStart($)
{
 my ($string) = @_;
 return unless(defined($string));

 my (@ret, $c, $v);

 my @a = split("\#" ,$string); 

 my $output   = $a[0]; # Name
 shift(@a);
 my $cmd      = $a[0]; 
 shift(@a);    

 my $hash     = $defs{$output};
 my $name     = $hash->{NAME};
 my $onoff    = (($cmd eq "on") || ($cmd eq "lock") || ($cmd eq "enable"))  ? "1" : "0";

 Log3 $name, 5, "$name, BC cmd : $cmd -> ".join(" ",@a);

   my $sock = new Net::Telnet(Timeout => $hash->{".timeout"}, Errmode => 'return');
   $sock->open( Host => $hash->{".host"}, Port => 23 );
   if (!$sock->errmsg)
   {
    $sock->login( Name => $hash->{".user"}, Password => $hash->{".pwd"} );
    if (!$sock->errmsg)
    {
      $sock->cmd("echo '".$hash->{".led"}."' >/proc/led/status") if ($hash->{".led"} ne "0");
      
      if (($cmd eq "reset")  || ($cmd eq "toggle")  || 
          ($cmd eq "lock")   || ($cmd eq "unlock")  ||
          ($cmd eq "enable") || ($cmd eq "disable") ||
          ($cmd eq "on")     || ($cmd eq "off"))
      {
         $output .= "|1|status|"; # Rueckgabe wie eine Statusabfrage
         foreach (@a)
         {
          if ($cmd eq "reset")
          {
            $sock->cmd("cat /proc/power/relay".$_." > /tmp/relay".$_.".tmp"); # Akt. Zustand retten
            $sock->cmd("echo 0 > /proc/power/reset".$_);  # Messwerte Reset
            $sock->cmd("cat /tmp/relay".$_.".tmp > /proc/power/output".$_); # alter Zustand wiederherstellen
          }
          elsif ($cmd eq "toggle")
          {
            @ret = $sock->cmd("awk '{print \$1=!\$1}' < /proc/power/relay".$_); # Akt. Zustand invers
            $sock->cmd("echo '".$ret[0]."' > /proc/power/output".$_); 
            # ToDo : wer weiss wie man es in nur einer Zeile macht ?
            # ala : awk '{print $1=!$1}' < /proc/power/relayX > /proc/power/outputX 
          }
          elsif (($cmd eq "on") || ($cmd eq "off"))
          {
            $sock->cmd("echo $onoff > /proc/power/output".$_); 
          }
          elsif (($cmd eq "lock") || ($cmd eq "unlock")) 
          {
            $sock->cmd("echo $onoff > /proc/power/lock".$_); 
          }
          elsif (($cmd eq "enable") || ($cmd eq "disable")) 
          {
            $sock->cmd("echo $onoff > /proc/power/enabled".$_); 
          }
         } # foreach

         select(undef, undef, undef, 0.25); # 250 ms warten !

         @ret = $sock->cmd("/sbin/cgi /usr/www/mfi/sensors.cgi"); # neue Statuswerte holen
         if($ret[2]) 
         { 
          ($ret[2],undef) = split("MF",$ret[2]); $output .= $ret[2]; 
         } 
      }
       else #
      {
       $output .= "|1|$cmd|";
       foreach(@a)
       {
        select(undef, undef, undef, 0.25); 
        @ret = $sock->cmd($_); 
        Log3 $name, 5, "$name, ret -> ".$ret[0] if ($ret[0]); 
        if ($cmd eq "status") { if($ret[2]) { ($ret[2],undef) = split("MF",$ret[2]); $output .= $ret[2]; } else { if ($ret[0]) {$ret[0] =~s/^MF.*//g; $output .= "|".$ret[0];}}}
        if ($cmd eq "info")   { $c = join(";",@ret); $c =~s/\$//g; $c =~s/\"//g; ($c,$v) = split("MF.v",$c); $output .= $c; $output .= "version=$v";}
       }
      }

      $sock->cmd("echo '0' >/proc/led/status") if ($hash->{".led"} ne "0");
      $sock->close;

      $output =~s/\n//g;
      return $output;
    } else { return $output."|0|$cmd|".$sock->errmsg; } 
   }  else { return $output."|0|$cmd|".$sock->errmsg; }
} 

sub UbiquitiMP_BCDone($)
{
  my ($string) = @_;
  return unless(defined($string));

  my ($h,$ret,$cmd,$msg,@a) = split("\\|",$string);
  my $hash = $defs{$h};

  $msg = "" if (!defined($msg)) ;

  if ($hash->{helper}{RUNNING_PID}{pid})
  {
   Log3 $h, 4, "$h, BCDone : PID ".$hash->{helper}{RUNNING_PID}{pid};
   delete($hash->{helper}{RUNNING_PID});
  }

  Log3 $h, 5, "$h, BCDone : $string";  
  if ($ret eq "0")
  {
    $hash->{ERRORMSG}  = $msg;
    $hash->{ERRORTIME} = TimeNow();
    $hash->{ERRORCOUNT}++;
    Log3 $h, 2, "$h, Error[".$hash->{ERRORCOUNT}."] cmd $cmd -> $msg";
    $hash->{INTERVAL} = 3600 if ($hash->{INTERVAL} && ($hash->{ERRORCOUNT}>9));
    readingsSingleUpdate($hash,"state","error",1); 
    if ($hash->{force})  # muessen wir wiederholen ?
    {     
     UbiquitiMP_force($hash);
     return;
    }
  }
  else # das ging ja schon mal gut
  {
     $hash->{INTERVAL}   = AttrVal($h, "interval", 300) if ($hash->{ERRORCOUNT} >9); 
     $hash->{ERRORCOUNT} = 0;
     $hash->{force}      = 0;
     if    ($cmd eq "info")   { UbiquitiMP_Info($hash,$msg); }
     elsif ($cmd eq "status") 
           {
            if($msg ne "")   # haben wir wieder mal einen leeren Status bekommen ?
            {
             UbiquitiMP_Status($hash,$msg,@a) if($msg ne "") ; 
            }
            else
            { 
             # etwas warten und versuchen den Status doch noch abzuschliessen
             InternalTimer(gettimeofday()+$hash->{".timeout"}, "UbiquitiMP_GetStatus",$hash, 0);
             return ;
            }          
           }
  }

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "UbiquitiMP_GetStatus",$hash, 0) if ($hash->{INTERVAL});
}

################################################################################

sub UbiquitiMP_BCAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  $hash->{ERRORCOUNT}++;
  $hash->{ERRORTIME} = TimeNow();
  Log3 $hash->{NAME}, 3, $hash->{NAME}.", BlockingCall for ".$hash->{NAME}." cmd ".$hash->{lastcmd}." aborted EC : ".$hash->{ERRORCOUNT};
  $hash->{INTERVAL} = 3600 if ($hash->{INTERVAL} && ($hash->{ERRORCOUNT}>9));

  if ($hash->{force}) # ein abgebrochenes force ?
  {
    UbiquitiMP_force($hash);
  }
  elsif  ($hash->{lastcmd} eq "GetStatus") # war das ein erfolgloses auto status update ?
  {
   InternalTimer(gettimeofday()+$hash->{INTERVAL}, "UbiquitiMP_GetStatus",$hash, 0) if($hash->{INTERVAL});
  }
  
  return;
}

################################################################################

sub UbiquitiMP_Status($$@) 
{
  my ($hash,$js,@a) = @_;
  my $name = $hash->{NAME};

  my $devstate;
  my $devname;
  my $state;

  my $sum_current;
  my $sum_power;
  my $sum_month;
  my $sum_prevmonth;
  my $sum_energy;
  my @ener;

  my $json = ();
  $json = JSON->new->utf8(0)->decode($js);

  my $sensors = scalar keys $json->{sensors};

  if ((!$hash->{PORTS}) && ($sensors > 0)) # nur einmal zu Begin bzw nach reload
  {
    $hash->{PORTS} = $sensors;
    UbiquitiMP_createSets($hash);
  }

  # bei der 1 Port Ubi default keine Subdevices , bei den anderen ja
  my $subdev = (int($hash->{PORTS}) >1) ? AttrVal($name, "subDevices", 1) : AttrVal($name, "subDevices", 0);

  @ener = split(" ",$a[2]) if (defined($a[2]));
 
  readingsBeginUpdate($hash);

  for (my $i=0; $i<$sensors; $i++)
  {
   if (index(AttrVal($name, "ignoreList", "") , $i+1) == -1) # welche Ports ignorieren ?
   {
   my $thismonth   = ($json->{sensors}[$i]{thismonth}) ? sprintf("%.0f", $json->{sensors}[$i]{thismonth}*0.3125) : 0; # Verbrauch aktueller Monat
   my $prevmonth   = ($json->{sensors}[$i]{prevmonth}) ? sprintf("%.0f", $json->{sensors}[$i]{prevmonth}*0.3125) : 0; # Verbrauch letzter  Monat , in welcher Einheit ?
   my $powerfactor = sprintf("%.2f", $json->{sensors}[$i]{powerfactor}); $powerfactor +=0; # wer will 0.00 ?
   my $output      = $json->{sensors}[$i]{output}; # 1/0 fuer on/off 
   my $port        = $json->{sensors}[$i]{port}; # Port Nr. 1- n
   my $voltage     = sprintf("%.0f", $json->{sensors}[$i]{voltage}); # V
   my $power       = sprintf("%.0f", $json->{sensors}[$i]{power});   # W
   my $current     = sprintf("%.2f", $json->{sensors}[$i]{current}); $current +=0; # A 
   my $lock        = $json->{sensors}[$i]{lock};
   my $label       = $json->{sensors}[$i]{label}; 
   my $enabled     = $json->{sensors}[$i]{enabled}; # wann wird das angefasst ?
   my $energy      = (defined($ener[$i])) ? sprintf("%.2f",$ener[$i]*0.3125) : 0; 
      $energy      += 0;

   my $eState ="E:$energy P:$power I:$current U:$voltage i:$powerfactor";
   
   $sum_current   += (defined($json->{sensors}[$i]{current}))   ? $json->{sensors}[$i]{current}          : 0;
   $sum_month     += (defined($json->{sensors}[$i]{thismonth})) ? $json->{sensors}[$i]{thismonth}*0.3125 : 0;
   $sum_prevmonth += (defined($json->{sensors}[$i]{prevmonth})) ? $json->{sensors}[$i]{prevmonth}*0.3125 : 0;
   $sum_power     += (defined($json->{sensors}[$i]{power}))     ? $json->{sensors}[$i]{power}            : 0;
   $sum_energy    += (defined($ener[$i]))                       ? $ener[$i]*0.3125                       : 0;

   $devstate = ($output eq "0") ? "off" : "on"; 
   $state .= ($i == $sensors) ? $devstate : $devstate." ";
   $devname = "Out".$port; # Port kann eigenen Namen haben

   $hash->{helper}{$devname}{state} = $output;
   $hash->{helper}{$devname}{name}  = $devname;
   $hash->{helper}{$devname}{lock}  = $lock;
  
   if ($subdev) # aufteilen oder lieber alles am Stueck ?
   {
     my $defptr = $modules{UbiquitiOut}{defptr}{$name.$port};
     if (defined($defptr)) 
     { 
       readingsBeginUpdate($defptr);
       readingsBulkUpdate($defptr, "state"     , $devstate); 
       readingsBulkUpdate($defptr, "eState"    , $eState);
       readingsBulkUpdate($defptr, "power"     , $power);
       readingsBulkUpdate($defptr, "voltage"   , $voltage);
       readingsBulkUpdate($defptr, "current"   , $current);
       readingsBulkUpdate($defptr, "pf"        , $powerfactor);
       readingsBulkUpdate($defptr, "month"     , $thismonth);
       readingsBulkUpdate($defptr, "prevmonth" , $prevmonth) if ($prevmonth);
       readingsBulkUpdate($defptr, "lock"      , $lock);
       readingsBulkUpdate($defptr, "label"     , $label) if ($label);
       readingsBulkUpdate($defptr, "enabled"   , $enabled);
       readingsBulkUpdate($defptr, "energy"    , $energy);
       readingsEndUpdate($defptr, 1 );
    }
    else
    {
     Log3 $name, 3, "$name, autocreate sub device for $devname Port $port";
     CommandDefine(undef, $name."_".$devname." UbiquitiOut $name $port");
    }
   }
   else # all in one
   {
    if (int($hash->{PORTS}) > 1)
    {
     readingsBulkUpdate($hash, $devname."_state"     , $devstate);
     readingsBulkUpdate($hash, $devname."_eState"    , $eState);
     readingsBulkUpdate($hash, $devname."_power"     , $power);
     readingsBulkUpdate($hash, $devname."_voltage"   , $voltage);
     readingsBulkUpdate($hash, $devname."_current"   , $current);
     readingsBulkUpdate($hash, $devname."_pf"        , $powerfactor);
     readingsBulkUpdate($hash, $devname."_month"     , $thismonth);
     readingsBulkUpdate($hash, $devname."_prevmonth" , $prevmonth) if ($prevmonth);
     readingsBulkUpdate($hash, $devname."_lock"      , $lock);
     readingsBulkUpdate($hash, $devname."_label"     , $label) if ($label);
     readingsBulkUpdate($hash, $devname."_enabled"   , $enabled);
     readingsBulkUpdate($hash, $devname."_energy"    , $energy);
    }
    else # 1 Port Dose
    {
     readingsBulkUpdate($hash, "eState"    , $eState);
     readingsBulkUpdate($hash, "power"     , $power);
     readingsBulkUpdate($hash, "voltage"   , $voltage);
     readingsBulkUpdate($hash, "current"   , $current);
     readingsBulkUpdate($hash, "pf"        , $powerfactor);
     readingsBulkUpdate($hash, "month"     , $thismonth);
     readingsBulkUpdate($hash, "prevmonth" , $prevmonth) if ($prevmonth);
     readingsBulkUpdate($hash, "lock"      , $lock);
     readingsBulkUpdate($hash, "label"     , $label) if ($label);
     readingsBulkUpdate($hash, "enabled"   , $enabled);
     readingsBulkUpdate($hash, "energy"    , $energy);
    } # 1 Port
   } # all in one
  } # if 
  } # for 

  if(defined($a[0]) && (substr($a[0],0,2) eq "u=")) # uptime
  {
    my $sec;
    (undef,$sec) = split("=",$a[0]); # u=xxxx.yyy
    if (int($sec) > 0)
    {
     my ($seconds, $microseconds) = gettimeofday();
     my @t = localtime($seconds-int($sec));
     $hash->{powerd_on} = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]);
     my($d,$h,$m,$s,$up);
     $d=int($sec/(24*60*60));
     $h=($sec/(60*60))%24;
     $m=($sec/60)%60;
     $s=$sec%60;
     $up = "$d days, " if($d >  1);
     $up = "1 day, "   if($d == 1);
     $up .= sprintf("%02s:%02s:%02s", $h, $m, $s);
     readingsBulkUpdate($hash, "uptime", $up); 
    }
  }
  
  if  (defined($a[1]) && (substr($a[1],0,2) eq "l=")) # load
  {
    my $load;
   (undef , $load) = split("=",$a[1]); # l=xxx yyy zzz
   $hash->{load} = $load if ($load);
  }

  if(int($hash->{PORTS}) > 1)
  {
    readingsBulkUpdate($hash, "all_current",   sprintf("%.2f", $sum_current));
    readingsBulkUpdate($hash, "all_power",     sprintf("%.2f", $sum_power));
    readingsBulkUpdate($hash, "all_month",     sprintf("%.2f", $sum_month/1000));
    readingsBulkUpdate($hash, "all_prevmonth", sprintf("%.2f", $sum_prevmonth/1000));
    readingsBulkUpdate($hash, "all_energy",    sprintf("%.2f", $sum_energy));
  }

  readingsBulkUpdate($hash, "state",$state);
  readingsEndUpdate($hash, 1 );

  return undef;

}

################################################################################

sub UbiquitiMP_Info($$) 
{
  my ($hash,$info) = @_;
  my $name = $hash->{NAME};
  my $var;
  my $val;
  my $ports;
  my $board_id;

  my @a = split(";" , $info);
  foreach (@a)
  {
   ($var,$val)  = split("=" , $_);
   Log3 $name, 5, "$name, $var = $val";
   $board_id            = $val if ($var eq "board.sysid");
   $hash->{BNAME}       = $val if ($var eq "board.name");
   $hash->{SNAME}       = $val if ($var eq "board.shortname");
   $hash->{VERSION}     = $val if ($var eq "version");
   $hash->{MAC}         = $val if ($var eq "board.hwaddr");
  }

  if (($board_id) && (!$hash->{PORTS}))
  {
    if      ($board_id eq "0xe648") { $ports = 8; }
    elsif   ($board_id eq "0xe656") { $ports = 6; }
     elsif (($board_id eq "0xe653") || 
            ($board_id eq "0xe643")){ $ports = 3; }
      elsif ($board_id eq "0xe642") { $ports = 2; }
       else                         { $ports = 1; }

    if ($ports > 0)
    {
      $hash->{PORTS} = $ports; 
      UbiquitiMP_createSets($hash);
    }
  }

  if (defined($hash->{VERSION})) 
  {
    my $v    = $hash->{VERSION};
    my $msg  = "Old version ".$hash->{VERSION}." found, please update to >= 2.1.8 !";
    $v =~s/\.//g;
    if (int($v) < 218)
    { 
      $hash->{VERSION} = $msg;
      Log3 $name, 1, "$name, $msg"; 
    }
  } 

  if ($hash->{".init"}) # kommen wir ueber einen Neustart ?
  {
   readingsSingleUpdate($hash,"state","Initialized",1); 
   delete($hash->{".init"});
   InternalTimer(gettimeofday()+$hash->{".timeout"}, "UbiquitiMP_GetStatus",$hash, 0);
  }

  return undef;
}

################################################################################

sub UbiquitiMP_GetStatus($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $cmd = $name;

  Log3 $name, 5, "$name, GetStatus Interval : ".$hash->{INTERVAL};
  
  if ($hash->{".init"}) # kommen wir ueber einen Neustart ?
  { 
   $cmd .=  "#info#cat /etc/board.info | grep board";
  }
  else
  {
   $cmd .= "#status#/sbin/cgi /usr/www/mfi/sensors.cgi";
   $cmd .= "#awk '{print\"u=\" \$1}' /proc/uptime";
   $cmd .= "#awk '{print \"l=\"\$1\" \"\$2\" \"\$3}' < /proc/loadavg";
   $cmd .= "#cat /proc/power/energy_sum* | tr '\\n' ' '";
  }

  $hash->{helper}{RUNNING_PID} = BlockingCall("UbiquitiMP_BCStart", $cmd, "UbiquitiMP_BCDone",(int($hash->{".timeout"})*2),"UbiquitiMP_BCAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
  if($hash->{helper}{RUNNING_PID})
  { 
    Log3 $name, 5, "$name, BC process started with PID(".$hash->{helper}{RUNNING_PID}{pid}.") cmd : $cmd"; 
    $hash->{lastcmd} = "GetStatus";
  }
  else  
  { # das ging schief wiederholen nach doppelter timeout Wartezeit 
    Log3 $name, 3,  "$name, BC process GetStatus start failed !"; 
    InternalTimer(gettimeofday()+(int($hash->{".timeout"})*2), "UbiquitiMP_GetStatus",$hash, 0);
  }

  return;
}

################################################################################

sub UbiquitiMP_summaryFn($$$$) {
	my ($FW_wname, $hash, $room, $pageHash) = @_;
        $hash            = $defs{$hash};
        my $state        = $hash->{STATE};
        my $name         = $hash->{NAME};
   
        return if ((AttrVal($name, "stateFormat", "")) || (int($hash->{PORTS}) < 2));

        my ($icon,$html,$cmd,$i,$title,$txt,$a,$b);

	$html  ="<nobr>";
        if (($state ne "defined") && ($state ne "error") && ($state ne "Initialized"))
        { 
         for ($i=1; $i<= $hash->{PORTS}; $i++)
         {
          if  (defined($hash->{helper}{"Out".$i}{state}))
          {
           if ($hash->{helper}{"Out".$i}{state})
           {
            $cmd  =  "Out".$i." off"; 
            $title = $hash->{helper}{"Out".$i}{name}. " on";
            ($icon, undef, undef) = FW_dev2image($name,"on");
            ($a,$b) = split('title=\"on\"' , FW_makeImage($icon, "on"));
            $txt = $a."title=\"".$title."\"".$b;
           }
           else
           {
            $cmd   = "Out".$i." on"; 
            $title = $hash->{helper}{"Out".$i}{name}. " off";
            ($icon, undef, undef) = FW_dev2image($name,"off");
            ($a,$b) = split('title=\"off\"' , FW_makeImage($icon, "off"));
            $txt = $a."title=\"".$title."\"".$b;
           }

           if (!$hash->{helper}{"Out".$i}{lock})
           {
            $html .= "<a href=\"/fhem?cmd.$name=set $name ".$cmd."&room=$room&amp;room=$room\">$txt</a>";
           }
           else { $html .= $txt; }
         
           $html .= "&nbsp;&nbsp;";

         }
         }
        } else { $html .= $state };

        $html .= "</nobr>";
        return $html;
}

################################################################################

sub UbiquitiMP_createSets($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $list = AttrVal($name, "groupPorts", "");
  my (@a, @b);

  return if (!$hash->{PORTS});

  %sets = (); 
  # bei nur einem Port macht eine Gruppe keinen Sinn
  if (int($hash->{PORTS}) == 1) 
  {
    @a = split("," ,$setcmds);
    foreach (@a) { $sets{$_} = "noArg"; }
     #%sets = ($setcmds);  
    return; 
  }

  $hash->{group_ALL} = "";

  for (my $j=1; $j<= $hash->{PORTS}; $j++) { $sets{"Out".$j}  = $setcmds; $hash->{group_ALL} .= "$j,"; }
  $sets{"ALL"}  = $setcmds;
  chop($hash->{group_ALL}); # das letzte Komma weg
 
  if ($list)
  { 
  @a = split(" " , $list);
  foreach (@a)
  {
    @b = split("=" , $_);
    if ($b[0] && $b[1])
      {
       $hash->{"group_".$b[0]} = $b[1];
       $sets{$b[0]}  = $setcmds; 
      }
    }
  } 
  return;
}

1;

=pod
=begin html

<a name="UbiquitiMP"></a>
<h3>UbiquitiMP</h3>
<ul>
  <table>
  <tr><td>
  FHEM module for the Ubiquiti mFi mPower modules<br>
  Please read also the <a href="http://www.fhemwiki.de/wiki/Ubiquit_mFi/mPower">Wiki</a> at http://www.fhemwiki.de/wiki/Ubiquit_mFi/mPower<br>
  FHEM Forum : http://forum.fhem.de/index.php/topic,35722.0.html 
  </td></tr></table>
  <a name="UbiquitiMPdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; UbiquitiMP &lt;IP or FQDN&gt;</code><br> 
    example :<br>
    define myPM UbiquitiMP 192.168.0.100<br>
    define myPM UbiquitiMP myhost.dyndns.org<br>
    Perl Net::Telnet and JSON module are required. On a Raspberry you can install them with :<br>
    apt-get install libjson-perl<br>
    apt-get install libnet-telnet-perl
  </ul>
  <br>
  <a name="UbiquitiMPset"></a>
  <b>Set </b>
  <ul>
    <li>Outx on / off (force) -> turns Port x on or off</li>
    <li>Outx toggle -> toggle port </li>
    <li>Outx lock / unlock -> protects port to switch port on/off</li>
    <li>Outx reset -> reset power counter for this port</li>
    <li>Outx enable / disable -> power counting for this port</li>
   </ul>
  <a name="UbiquitiMPget"></a>
  <b>Get</b>
  <ul>
   <li>status -> returns the status of all Outs</li>
   <li>info -> returns some internal informations of the device</li>
   <li>reboot -> reboot the device</li><br>
  </ul>
  <a name="UbiquitiMPattr"></a>
  <b>Attributes</b>
  <ul>
    <li>ignoreList -> list of ignored ports<br> e.g. attr name ignoreList 456<br>ignores all values of ports 4,5 & 6<br></li>
    <li>groupPorts -> space separeted list to group ports so you can use them like a single device<br>
    e.g. attr name groupPorts TV=12 Media=4,5,6 (GroupName=Port numbers in the group)<br>
    set name TV on  or set name Media toggle </li>
    <li>ledconnect -> led color since fhem connect</li>
    <li>subDevices -> use a single sub devices for each out port<br> 
    (default 1 for the 3 and 6 port mPower, default 0 for the mPower mini) requires 98_UbiquitiOut.pm</li>
    <li>interval -> polling interval in seconds, set to 0 to disable polling (default 300)</li>
    <li>timeout -> seconds to wait for a answer from the Power Module (default 5 seconds)</li>
    <li>user -> defined user on the Power Module (default ubnt)</li>
    <li>password -> password for user (default ubnt)</li>
  </ul>
 <br>
 </ul>
=end html

=begin html_DE

<a name="UbiquitiMP"></a>
<h3>UbiquitiMP</h3>
<ul>
  <table>
  <tr><td>
  FHEM Modul f&uuml;r die Ubiquiti mFi mPower Schaltsteckdosen<br>
  Mehr Informationen zu den verschiedenen mPower Modellen im <a href="http://www.fhemwiki.de/wiki/Ubiquit_mFi/mPower">Wiki</a> unter http://www.fhemwiki.de/wiki/Ubiquit_mFi/mPower<br>
  FHEM Forum : http://forum.fhem.de/index.php/topic,35722.0.html 
  </td></tr></table>
  <a name="UbiquitiMPdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; UbiquitiMP &lt;IP or FQDN&gt;</code><br> 
    Beispiel :<br>
    define Ubi UbiquitiMP 192.168.0.100<br>
    define Ubi UbiquitiMP myhost.dyndns.org<br>
    Perl Net::Telnet und das Perl JSON Modul werden ben&ouml;tigt. 
    Bei einem Raspberry Pi k&ouml;nnen diese leicht mit den folgenden beiden Befehlen installiert werden:<br>
    apt-get install libjson-perl<br>
    apt-get install libnet-telnet-perl
  </ul>
  <br>
  <a name="UbiquitiMPset"></a>
  <b>Set </b>
  <ul>
    <li>Outx on / off (force) -> schaltet den Port x an oder aus</li>
    <li>Outx toggle -> schaltet den Port aus wenn er an ist und umgekehrt</li>
    <li>Outx lock / unlock -> Ist lock bei einem Port gesetzt kann er nicht mehr an oder aus geschaltet werden</li>
    <li>Outx reset -> setzt den internen Verbrauchsz&auml;hler f&uuml;r diesen Port zur&uuml;ck</li>
    <li>Outx enable / disable -> interne Verbrauchsmessung f&uuml;r diesen Port ein / aus schalten</li>
    <br><b>Bei der mPower mini entf&auml;llt die Angabe von Outx !</b><br>
    Zus&auml;tzlich unterst&uuml;tzt die mini die <a href="#setExtensions">set Extensions</a> direkt
   </ul>
  <a name="UbiquitiMPget"></a>
  <b>Get</b>
  <ul>
   <li>status -> Gibt den aktuellen Status aller Ports zur&uuml;ck</li>
   <li>info -> liefert einige interne Parameter des Ger&auml;tes</li>
   <li>reboot -> Startet das Ger&auml;t neu</li><br>
  </ul>
  <a name="UbiquitiMPattr"></a>
  <b>Attributes</b>
  <ul>
    <li>ignoreList -> Liste der Ports die bei Abfragen ignoriert werden sollen, Bsp. <code>attr Ubi ignoreList 456</code><br>
    ignoriert alle Werte der Ports 4,5 und 6</li><br>
    <li>groupPorts -> Durch Kommatas getrennte Liste um Ports in Gruppen zusammen zu fassen.<br>
    Die Gruppen k&ouml;nnen danach wie win einzelner Port behandelt werden.<br>
    Bsp. <code>attr Ubi groupPorts TV=12 Media=4,5,6</code> (GruppenName=Port Nummer des Ports in der Gruppe)<br>
    <code>set Ubi TV on</code> oder <code>set Ubi Media toggle</code></li><br>
    <li>ledconnect -> Farbe der LED beim Zugriff mit fhem</li><br>
    <li>subDevices -> Legt f&uuml;r jeden Port ein eigenes Subdevice an<br> 
    (Default 1 f&uuml;r die 3 and 6 Port mPower, Default 0 f&uuml;r die mPower 1 Port mini) ben&ouml;tigt zus&auml;tzlich das Modul 98_UbiquitiOut.pm</li><br>
    <li>interval -> Abfrage Interval in Sekunden, kann ausgeschaltet werden mit dem Wert 0 (Default ist 300)</li><br>
    <li>timeout -> Wartezeit in Sekunden bevor eine Abfrage mit einer Fehlermeldung abgebrochen wird (Default ist 5 Sekunden)<br>
    Werte unter zwei Sekunden werden vom Modul nicht angenommen !</li><br>
    <li>user -> Login Username (Default ubnt)</li><br>
    <li>password -> Login Passwort (Default ubnt)</li>
  </ul>
 <br>
 </ul>
=end html_DE
=cut

