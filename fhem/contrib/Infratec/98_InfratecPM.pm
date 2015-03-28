################################################################
#
#  $Id$
#
#  (c) 2015 Copyright: Wzut
#  forum : http://forum.fhem.de/index.php/topic,34131.0.html
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
#  28.3.15 fix delete Outs

package main;


use strict;
use warnings;
use Time::HiRes qw(gettimeofday);    
use HttpUtils;

#my %sets = ( "Out1" => "on,off,toggle" , "Out2" => "on,off,toggle");

my %sets = ();

#########################################################################

sub InfratecPM_Initialize($)
{
    my ($hash) = @_;
    $hash->{DefFn}    = "InfratecPM_Define";
    $hash->{UndefFn}  = "InfratecPM_Undef";
    $hash->{SetFn}    = "InfratecPM_Set";
    $hash->{GetFn}    = "InfratecPM_Get";
    $hash->{AttrFn}   = "InfratecPM_Attr";
    $hash->{FW_summaryFn} = "InfratecPM_summaryFn";
    $hash->{AttrList} = "interval timeout user password autocreate:0,1 ".$readingFnAttributes;
}

sub InfratecPM_updateConfig($)
{
  # this routine is called 10 sec after the last define of a restart
  # this gives FHEM sufficient time to fill in attributes

 my ($hash) = @_;
 my $name = $hash->{NAME};
 
 $hash->{INTERVAL} = AttrVal($name, "interval", 30);

 readingsSingleUpdate($hash,"state","Initialized",1); 

 InternalTimer(gettimeofday()+$hash->{INTERVAL}, "InfratecPM_Status",$hash, 0) if ($hash->{INTERVAL});

 #InfratecPM_Get($hash,$name,"status");
 return undef;

}

################################################################################

sub InfratecPM_Define($$) {

    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @a = split("[ \t][ \t]*", $def);

    return "wrong syntax: define <name> InfratecPM <IP or FQDN> [<Port>]" if(int(@a) < 3);
     
    $hash->{host}  = $a[2];
    $hash->{port}  = (defined($a[3])) ? $a[3] : "80";

    if( !defined( $attr{$a[0]}{user} ) ) { $attr{$a[0]}{user} = "admin";}
    $hash->{user}       = $attr{$a[0]}{user};

    if( !defined( $attr{$a[0]}{password} ) ) { $attr{$a[0]}{password} = "1234";}
    $hash->{pwd}        = $attr{$a[0]}{password};

    if( !defined( $attr{$a[0]}{timeout} ) ) { $attr{$a[0]}{timeout} = "2"}
    $hash->{timeout} = (int($attr{$a[0]}{timeout}) > 1) ? $attr{$a[0]}{timeout} : "2";

    if( !defined( $attr{$a[0]}{autocreate} ) ) { $attr{$a[0]}{autocreate} = "1";}

    $hash->{Clients}    = ":InfratecOut:";
    $hash->{PORTS}      = 0;
    $hash->{force}      = 0;
    $hash->{code}       = "";
    $hash->{callback}   = \&InfratecPM_Read;
    readingsSingleUpdate($hash, "state", "defined",0);

    InternalTimer(gettimeofday()+10, "InfratecPM_updateConfig",$hash,1);

    return undef;
}

################################################################################

sub InfratecPM_Undef($$) 
{
    my ($hash, $arg) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

################################################################################

sub InfratecPM_force($) 
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "Force : ".$hash->{lastcmd};
    if ($hash->{force})
    {
     CommandSet(undef,$name." Out".$hash->{lastcmd}. " force");
    }    
    else 
    {
     InfratecPM_unforce($hash);
    }
return undef;
}

################################################################################

sub InfratecPM_unforce($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{force} = 0;
  Log3 $name, 5, "Unforce : ".$hash->{lastcmd};
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "InfratecPM_Status",$hash, 0) if ($hash->{INTERVAL});
  return undef;
}

################################################################################

sub InfratecPM_Read($$$)
{
    my ($hash, $err, $buffer) = @_;
    my $name = $hash->{NAME};
    my $state = "???";

    if ($err) 
    {
        $hash->{ERROR} = $err;
        $hash->{ERRORTIME} = TimeNow();
        my $msg = "$name: Error ";
        $msg .= ($hash->{code}) ? "[".$hash->{code}."] -> $err" : "-> $err";
        Log3 $name, 3, $msg;
        $hash->{ERRORCOUNT} ++;
        readingsSingleUpdate($hash, "state", "error", 0);
        $hash->{INTERVAL} = 3600 if ($hash->{ERRORCOUNT} >9);
        InternalTimer(gettimeofday()+$hash->{timeout}, "InfratecPM_force",$hash,0) if ($hash->{force});
        return;
    }

    if (!$buffer)
    {
      # sollte eigentlich gar nicht vorkommen   
      Log3 $name, 3, "$name: empty return buffer";
      $hash->{ERRORCOUNT} ++;
      $hash->{ERROR} = "empty return buffer";
      $hash->{ERRORTIME} = TimeNow();
      $hash->{INTERVAL} = 3600 if ($hash->{ERRORCOUNT} >9);
      InternalTimer(gettimeofday()+$hash->{timeout}, "InfratecPM_force",$hash,0) if ($hash->{force});
      return;
    }

   $hash->{RETURNED} = "";
   Log3 $name, 5, "$name, [".$hash->{code}."] Message1: $buffer\r";
   $buffer =~s/\n//g;
   $buffer =~s/ //g;
   $buffer =~s/<br>/-/g;
   $buffer =~s/--/-/g;
   $buffer =~s/<[^>]*>//gis;
 
   Log3 $name, 4, "$name, Message2: $buffer\r";

   $hash->{ERRORCOUNT} = 0;
   $hash->{INTERVAL}   = AttrVal($name, "interval", 30);

   readingsBeginUpdate($hash);

   my @ret = split("-" , $buffer);
   my $i = 0;
   my $devstate;

   foreach (@ret)
   {
     Log3 $name, 5, "$name , ret -> $_";

     my @val = split(":" , $_);

     if (!defined($val[1])) { $val[1] = "" }

     if(($val[1] eq "0") || ($val[1] eq "1")) # hier wollen wir nur die on/ff haben
     { 
      #$val[0] =~s/ //g;
      if (!$i) {$state="";} # erster Port
      $i++; 
      $devstate = ($val[1] eq "0") ? "off" : "on"; 
      $state .= $devstate." ";

      $hash->{helper}{$i."state"} = $val[1]; 
      $hash->{helper}{$i."name"} = $val[0];
      #Log3 $name, 5, "$name , Status $i: ".$hash->{helper}{$i."state"}."\r";
      
      readingsBulkUpdate($hash, $val[0], $devstate);

      my $defptr = $modules{InfratecOut}{defptr}{$name.$i};

      if (defined($defptr)) { readingsSingleUpdate($defptr, "state", $devstate, 1); }
      elsif(AttrVal($name, "autocreate", 1))
      {
  	Log3 $name, 3, "$name, autocreate InfratecOut for Out".$i;
        CommandDefine(undef, $val[0]." InfratecOut $name $i");
      }
     } elsif (defined($val[0]) ne "") 
              {
               $hash->{RETURNED} =$val[0]; 
               InfratecPM_unforce($hash) if (($hash->{RETURNED} eq "Done.") && $hash->{force});
              }
   }

    if (($hash->{RETURNED} eq "Done.") || ($hash->{RETURNED} eq "Status"))
    {
     readingsBulkUpdate($hash, "state",$state);
    }
     else
    {
     Log3 $name, 2, "$name , Return : ".$hash->{RETURNED};
     readingsBulkUpdate($hash, "state", $hash->{RETURNED});
    }     
   
    readingsEndUpdate($hash, 1 );

    # und wie viele Ports hat denn nun das Ding wirklich ?
    if($i && ($hash->{RETURNED} eq "Status") && !$hash->{PORTS})
    {
      $hash->{PORTS} = $i;  
      for (my $j=1; $j<= $i; $j++) { $sets{"Out".$j}  = "on,off,toggle"; }
    }
     return;
}


################################################################################

sub InfratecPM_Attr(@) 
{

 my ($cmd,$name, $attrName,$attrVal) = @_;
 my $hash = $defs{$name};

 if ($cmd eq "set")
 {

   if ($attrName eq "timeout")
   {
     if (int($attrVal)<"2") {$attrVal="2";}
     $hash->{timeout}  = $attrVal;
     $attr{$name}{timeout} = $attrVal;
   }
   elsif ($attrName eq "user")
   {
       $hash->{user}   = $attrVal;
       $attr{$name}{user} = $attrVal;
   }
  elsif ($attrName eq "password")
   {
       $hash->{pwd}   = $attrVal;
       $attr{$name}{password} = $attrVal;
   }
   elsif ($attrName eq "interval")
   {
       $hash->{INTERVAL}   = $attrVal;
       $attr{$name}{interval} = $attrVal;
   }

 }

   return undef;
}

################################################################################

sub InfratecPM_Get($@) {
   my ($hash, $name , @a) = @_;
   my $cmd = $a[0];
   Log3 $name, 5, "Get: ".join(" ", @a);

   return "get $name needs one argument" if (int(@a) != 1);

   return "Unknown argument $cmd, choose one of status:noArg " if ($cmd ne "status");

   InfratecPM_unforce($hash) if ($hash->{force});
   InfratecPM_Status($hash); 

   return undef;
}

################################################################################

sub InfratecPM_Set($@) {
   my ($hash,  @a) = @_;
   my $name = $hash->{NAME};
   my $port    = (defined($a[1])) ? $a[1] : "?" ;
   my $cmd     = (defined($a[2])) ? $a[2] : "";
   my $subcmd  = (defined($a[3])) ? $a[3] : "";

   Log3 $name, 5, "Set: ".join(" ", @a);
 
   if(!defined($sets{Out1}) && $hash->{PORTS}) # neu aufbauen nach reload;
   {
    for (my $j=1; $j<= $hash->{PORTS}; $j++) { $sets{"Out".$j}  = "on,off,toggle"; }
   }

  if(!defined($sets{$port})) 
   {
     my @commands = ();
     foreach my $key (sort keys %sets) 
     {
      push @commands, $sets{$key} ? $key.":".join(",",$sets{$key}) : $key;
     }
     return "Unknown argument for $port, choose one of " . join(" ", @commands);
   }

   return "wrong command, please use on, off or toggle" if($cmd !~ /^(on|off|toggle)$/);

    $port = substr($port,3,1);
    return "wrong port $port, please use 1 - ".$hash->{PORTS} if ((int($port)<1) || (int($port)>$hash->{PORTS})) ;

    $hash->{url}  = "http://$hash->{host}:$hash->{port}/sw?u=$hash->{user}&p=$hash->{pwd}&o=";
    $hash->{url} .= $port."&f=".$cmd;
 
    $hash->{lastcmd} = $port." ".$cmd;
    $hash->{force}   = ($subcmd eq "force") ? 1 : 0;
    RemoveInternalTimer($hash) if ($hash->{force});
    HttpUtils_NonblockingGet($hash);
    return undef;

}
                                                                                                     



################################################################################

sub InfratecPM_Status($) 
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "GetUpdate, Interval : ".$hash->{INTERVAL};

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "InfratecPM_Status",$hash, 0) if ($hash->{INTERVAL});

  $hash->{url}     = "http://$hash->{host}:$hash->{port}/sw?s=0";
  $hash->{lastcmd} = "status";
  HttpUtils_NonblockingGet($hash);

   return undef;
}

################################################################################

sub InfratecPM_summaryFn($$$$) {
	my ($FW_wname, $hash, $room, $pageHash) = @_;
        $hash            = $defs{$hash};
        my $state        = $hash->{STATE};
        my $name         = $hash->{NAME};
   
        return if(AttrVal($name, "stateFormat", ""));

        my ($icon,$html,$cmd,$i,$title,$txt,$a,$b);

	$html  ="<nobr>";
        if (($state ne "defined") && ($state ne "error") && ($state ne "Initialized"))
        { 
         for ($i=1; $i<= $hash->{PORTS}; $i++)
         {
          if  (defined($hash->{helper}{$i."state"}))
          {
           if ($hash->{helper}{$i."state"})
           {
            $cmd  =  "Out".$i." off"; 
            $title = $hash->{helper}{$i."name"}. " on";
            ($icon, undef, undef) = FW_dev2image($name,"on");
            ($a,$b) = split('title=\"on\"' , FW_makeImage($icon, "on"));
            $txt = $a."title=\"".$title."\"".$b;
           }
           else
           {
            $cmd   = "Out".$i." on"; 
            $title = $hash->{helper}{$i."name"}. " off";
            ($icon, undef, undef) = FW_dev2image($name,"off");
            ($a,$b) = split('title=\"off\"' , FW_makeImage($icon, "off"));
            $txt = $a."title=\"".$title."\"".$b;
           }

           $html .= "<a href=\"/fhem?cmd.$name=set $name ".$cmd."&room=$room&amp;room=$room\">$txt</a>&nbsp;&nbsp;";
         }
         }
        } else { $html .= $state };
	
        $html .= "</nobr>";
	return $html;	
}

1;

=pod
=begin html

<a name="InfratecPM"></a>
<h3>InfratecPM</h3>
<ul>
  <table>
  <tr><td>
  Device for Infratec Power Modules , see <a href='http://www.infratec-plus.de/produktlinien/powerdistribution/switched-pdu/pm4-ip/'>
  http://www.infratec-plus.de/produktlinien/powerdistribution/switched-pdu/pm4-ip/</a> for details
  <br>
  FHEM Forum : <a href='http://forum.fhem.de/index.php/topic,34131.0.html'>http://forum.fhem.de/index.php/topic,34131.0.html</a>
  </td>
</tr>
  </table>

  <a name="InfratecPMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; InfratecPM &lt;IP or FQDN&gt; [&lt;PORT&gt;] (Port 80 default)</code><br> 
    example :<br>
    define myPM InfratecPM 192.168.0.100<br>
    define myPM InfratecPM myhost.dyndns.org 88<br>
  </ul>
  <br>
  <a name="InfratecPMset"></a>
  <b>Set </b>
  <ul>
    <li>Outx on (force)<br>
	turns Outx on</li><br>
    <li>Outx off (force)<br>
        turns Outx off</li><br>
    <li>Outx toggle<br>
        toggle Outx</li><br>
  </ul>

  <a name="InfratecPMget"></a>
  <b>Get</b>
  <ul>
    <li>status<br>
        returns the status of all Outs
        </li><br>
  </ul>

  <a name="InfratecPMattr"></a>
  <b>Attributes</b>
  <ul>
    <li>autocreate<br>
        autocreate sub devices for each reading (default 1)<br>
        requires 98_InfratecOut.pm</li><br>
    <li>interval<br>
        polling interval in seconds, set to 0 to disable polling (default 30)</li><br>
    <li>timeout<br>
        seconds to wait for a answer from the Power Module</li><br>
    <li>user<br>
        defined user on the Power Module</li><br>
    <li>password<br>
        password for user</li>
  </ul>
 <br>
 </ul>
=end html

