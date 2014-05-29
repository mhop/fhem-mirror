# $Id$
##############################################################################
#
#     71_YAMAHA_BD.pm
#     An FHEM Perl module for controlling Yamaha Blu-Ray players
#     via network connection. As the interface is standardized
#     within all Yamaha Blue-Ray players, this module should work
#     with any player which has an ethernet or wlan connection.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use HttpUtils;
 
sub YAMAHA_BD_Get($@);
sub YAMAHA_BD_Define($$);
sub YAMAHA_BD_GetStatus($;$);
sub YAMAHA_BD_Attr(@);
sub YAMAHA_BD_ResetTimer($;$);
sub YAMAHA_BD_Undefine($$);

###################################
sub
YAMAHA_BD_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "YAMAHA_BD_Get";
  $hash->{SetFn}     = "YAMAHA_BD_Set";
  $hash->{DefFn}     = "YAMAHA_BD_Define";
  $hash->{AttrFn}    = "YAMAHA_BD_Attr";
  $hash->{UndefFn}   = "YAMAHA_BD_Undefine";
  $hash->{AttrList}  = "do_not_notify:0,1 disable:0,1 request-timeout:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 model ".
                      $readingFnAttributes;
}

###################################
sub
YAMAHA_BD_GetStatus($;$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $power;
    my $return;
    
    $local = 0 unless(defined($local));

    return "" if(!defined($hash->{helper}{ADDRESS}) or !defined($hash->{helper}{ON_INTERVAL}) or !defined($hash->{helper}{OFF_INTERVAL}));

    # get the model informations if no informations are available
    if((not defined($hash->{MODEL})) or (not defined($hash->{FIRMWARE})))
    {
		YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>", "statusRequest","systemConfig");
    }

    Log3 $name, 4, "YAMAHA_BD ($name) - Requesting system status";
    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Service_Info>GetParam</Service_Info></System></YAMAHA_AV>", "statusRequest","systemStatus");

    Log3 $name, 4, "YAMAHA_BD ($name) - Requesting power state";
    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Power_Control><Power>GetParam</Power></Power_Control></Main_Zone></YAMAHA_AV>", "statusRequest","powerStatus");
    
	Log3 $name, 4, "YAMAHA_BD ($name) - Requesting playing info";
    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Play_Info>GetParam</Play_Info></Main_Zone></YAMAHA_AV>", "statusRequest","playInfo");
    
	Log3 $name, 4, "YAMAHA_BD ($name) - Requesting trickPlay info";
    YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Play_Control>GetParam</Play_Control></Main_Zone></YAMAHA_AV>", "statusRequest","trickPlayInfo");

    # Reset timer if this is not a local run
    YAMAHA_BD_ResetTimer($hash) unless($local == 1);

}

###################################
sub
YAMAHA_BD_Get($@)
{
    my ($hash, @a) = @_;
    my $what;
    my $return;
	
    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    if(exists($hash->{READINGS}{$what}))
    {
        YAMAHA_BD_GetStatus($hash, 1);

        if(defined($hash->{READINGS}{$what}))
        {
			return $hash->{READINGS}{$what}{VAL};
		}
		else
		{
			return "no such reading: $what";
		}
    }
    else
    {
		$return = "unknown argument $what, choose one of";
		
		foreach my $reading (keys %{$hash->{READINGS}})
		{
			$return .= " $reading:noArg";
		}
		
		return $return;
	}
}


###################################
sub
YAMAHA_BD_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $result = "";
    
    return "No Argument given" if(!defined($a[1]));  
   
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on:noArg off:noArg statusRequest:noArg tray:open,close remoteControl:up,down,left,right,return,enter,OSDonScreen,OSDstatus,topMenu,popupMenu,red,green,blue,yellow,0,1,2,3,4,5,6,7,8,9,setup,home,clear,program,search,repeat,repeat-AB,subtitle,angle,audio,pictureInPicture,secondVideo,secondAudio fast:forward,reverse slow:forward,reverse skip:forward,reverse play:noArg pause:noArg stop:noArg trickPlay:normal,repeatChapter,repeatTitle,repeatFolder,repeat-AB,randomChapter,randomTitle,randomAll,shuffleChapter,shuffleTitle,shuffleAll,setApoint";

    if($what eq "on")
    {		
         YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>On</Power></Power_Control></Main_Zone></YAMAHA_AV>","on",undef);
    }
    elsif($what eq "off")
    {
        YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>Network Standby</Power></Power_Control></Main_Zone></YAMAHA_AV>","off",undef);
    }
    elsif($what eq "remoteControl")
    {
        if($a[2] eq "up")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Up</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","up");
        }
        elsif($a[2] eq "down")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Down</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","down");
        }
        elsif($a[2] eq "left")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Left</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","left");
        }
        elsif($a[2] eq "right")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Right</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","right");
        }
        elsif($a[2] eq "enter")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Enter</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","enter");
        }
        elsif($a[2] eq "return")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Cursor>Return</Cursor></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","return");
        }
        elsif($a[2] eq "OSDonScreen")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><OSD>OnScreen</OSD></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","OSDonScreen");
        }
        elsif($a[2] eq "OSDstatus")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><OSD>Status</OSD></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","OSDstatus");
        }
        elsif($a[2] eq "topMenu")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Menu>TOP MENU</Menu></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","topMenu");
        }
        elsif($a[2] eq "popupMenu")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Menu>POPUP MENU</Menu></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","popupMenu");
        }
        elsif($a[2] eq "red")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>RED</Color></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","red");
        }
        elsif($a[2] eq "green")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>GREEN</Color></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","green");
        }
        elsif($a[2] eq "blue")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>BLUE</Color></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","blue");
        }
        elsif($a[2] eq "yellow")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Color>YELLOW</Color></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","yellow");
        }
        elsif($a[2] eq "0")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>0</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","0");
        }
        elsif($a[2] eq "1")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>1</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","1");
        }
        elsif($a[2] eq "2")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>2</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","2");
        }
        elsif($a[2] eq "3")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>3</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","3");
        }
        elsif($a[2] eq "4")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>4</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","4");
        }
        elsif($a[2] eq "5")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>5</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","5");
        }
        elsif($a[2] eq "6")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>6</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","6");
        }
        elsif($a[2] eq "7")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>7</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","7");
        }
        elsif($a[2] eq "8")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>8</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","8");
        }
        elsif($a[2] eq "9")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Numeric>9</Numeric></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","9");
        }
        elsif($a[2] eq "setup")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>SETUP</Function></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","setup");
        } 
        elsif($a[2] eq "home")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>HOME</Function></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","home");
        } 
        elsif($a[2] eq "clear")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>CLEAR</Function></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","clear");
        }
        elsif($a[2] eq "program")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><Function>PROGRAM</Function></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","program");
        }
        elsif($a[2] eq "search")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><RC_Code>7C9E</RC_Code></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","search");
        }
        elsif($a[2] eq "repeat")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><RC_Code>7CA3</RC_Code></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","repeat");
        }
        elsif($a[2] eq "repeat-AB")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Remote_Control><RC_Code>7CA4</RC_Code></Remote_Control></Main_Zone></YAMAHA_AV>","remoteControl","repeat-AB");
        }
        elsif($a[2] eq "subtitle")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>SUBTITLE</Stream></Play_Control></Main_Zone></YAMAHA_AV>","remoteControl","subtitle");
        }
        elsif($a[2] eq "angle")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>ANGLE</Stream></Play_Control></Main_Zone></YAMAHA_AV>","remoteControl","angle");
        }
        elsif($a[2] eq "audio")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>AUDIO</Stream></Play_Control></Main_Zone></YAMAHA_AV>","remoteControl","audio");
        }
        elsif($a[2] eq "pictureInPicture")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>PinP</Stream></Play_Control></Main_Zone></YAMAHA_AV>","remoteControl","pictureInPicture");
        }
        elsif($a[2] eq "secondVideo")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>2nd Video</Stream></Play_Control></Main_Zone></YAMAHA_AV>","remoteControl","secondVideo");
        }
        elsif($a[2] eq "secondAudio")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Stream>2nd Audio</Stream></Play_Control></Main_Zone></YAMAHA_AV>","remoteControl","secondAudio");
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "trickPlay")
    {
        if($a[2] eq "normal")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Normal</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","normal");
        }
        elsif($a[2] eq "repeatChapter")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Repeat Chapter/Track/File</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","repeatChapter");
        }
        elsif($a[2] eq "repeatTitle")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Repeat Title</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","repeatTitle");
        }
        elsif($a[2] eq "repeatFolder")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Repeat Folder</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","repeatFolder");
        }
        elsif($a[2] eq "randomChapter")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Random Chapter/Track/File</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","randomChapter");
        }
        elsif($a[2] eq "randomTitle")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Random title</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","randomTitle");
        }
        elsif($a[2] eq "randomAll")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Random All</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","randomAll");
        }
        elsif($a[2] eq "shuffleChapter")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Shuffle Chapter/Track/File</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","shuffleChapter");
        }
        elsif($a[2] eq "shuffleTitle")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Shuffle title</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","shuffleTitle");
        }
        elsif($a[2] eq "shuffleAll")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>Shuffle All</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","shuffleAll");
        }
        elsif($a[2] eq "setApoint")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>SetA point</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","setApoint");
        }
        elsif($a[2] eq "repeat-AB")
        {
            YAMAHA_BD_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Trick_Play>A-B Repeat</Trick_Play></Play_Control></Main_Zone></YAMAHA_AV>","trickPlay","ABrepeat");
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "tray")
    {
        if($a[2] eq "open")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Tray_Control><Tray>Open</Tray></Tray_Control></Main_Zone></YAMAHA_AV>","tray","open");
        }
        elsif($a[2] eq "close")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Tray_Control><Tray>Close</Tray></Tray_Control></Main_Zone></YAMAHA_AV>","tray","close");
        }	
    }
    elsif($what eq "skip")
    {
        if($a[2] eq "forward")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Skip>Fwd</Skip></Play_Control></Main_Zone></YAMAHA_AV>","skip","forward");
        }
        elsif($a[2] eq "reverse")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Skip>Rev</Skip></Play_Control></Main_Zone></YAMAHA_AV>","skip","reverse");
        }	
    }
    elsif($what eq "fast")
    {
        if($a[2] eq "forward")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Fast>Fwd</Fast></Play_Control></Main_Zone></YAMAHA_AV>","fast","forward");
        }
        elsif($a[2] eq "reverse")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Fast>Rev</Fast></Play_Control></Main_Zone></YAMAHA_AV>","fast","reverse");
        }	
    }
    elsif($what eq "slow")
    {
        if($a[2] eq "forward")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Slow>Fwd</Slow></Play_Control></Main_Zone></YAMAHA_AV>","slow","forward");
        }
        elsif($a[2] eq "reverse")
        {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Slow>Rev</Slow></Play_Control></Main_Zone></YAMAHA_AV>","slow","reverse");
        }	
    }
    elsif($what eq "play")
    {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Play>Play</Play></Play_Control></Main_Zone></YAMAHA_AV>","play", undef);
    }
    elsif($what eq "pause")
    {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Play>Pause</Play></Play_Control></Main_Zone></YAMAHA_AV>","pause", undef);
    }
    elsif($what eq "stop")
    {
            YAMAHA_BD_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Play_Control><Play>Stop</Play></Play_Control></Main_Zone></YAMAHA_AV>", "play",undef);
    }
    elsif($what ne "statusRequest")
    {
        return $usage;
    }
	
    
    # Call the GetStatus() Function to retrieve the new values after setting something (with local flag, so the internal timer is not getting interupted)
    YAMAHA_BD_GetStatus($hash, 1);
    
    return undef;
    
}


#############################
sub
YAMAHA_BD_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(! @a >= 3)
    {
	my $msg = "wrong syntax: define <name> YAMAHA_BD <ip-or-hostname> [<statusinterval>] [<presenceinterval>]";
	Log 2, $msg;
	return $msg;
    }

    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;
    
    # if an update interval was given which is greater than zero, use it.
    if(defined($a[3]) and $a[3] > 0)
    {
		$hash->{helper}{OFF_INTERVAL}=$a[3];
    }
    else
    {
		$hash->{helper}{OFF_INTERVAL}=30;
    }
    
    # if a second update interval is given, use this as ON_INTERVAL, otherwise use OFF_INTERVAL instead.
    if(defined($a[4]) and $a[4] > 0)
    {
		$hash->{helper}{ON_INTERVAL}=$a[4];
    }
    else
    {
		$hash->{helper}{ON_INTERVAL}=$hash->{helper}{OFF_INTERVAL};
    } 


    # start the status update timer
    $hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));
	YAMAHA_BD_ResetTimer($hash, 2);
  
  return undef;
}

##########################
sub
YAMAHA_BD_Attr(@)
{
    my @a = @_;
    my $hash = $defs{$a[1]};

    if($a[0] eq "set" && $a[2] eq "disable")
    {
        if($a[3] eq "0")
        {
             $hash->{helper}{DISABLED} = 0;
             YAMAHA_BD_GetStatus($hash, 1);
        }
        elsif($a[3] eq "1")
        {
            $hash->{helper}{DISABLED} = 1;
        }
    }
    elsif($a[0] eq "del" && $a[2] eq "disable")
    {
        $hash->{helper}{DISABLED} = 0;
        YAMAHA_BD_GetStatus($hash, 1);
    }

    # Start/Stop Timer according to new disabled-Value
    YAMAHA_BD_ResetTimer($hash);
    
    return undef;
}

#############################
sub
YAMAHA_BD_Undefine($$)
{
    my($hash, $name) = @_;
  
    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);
    return undef;
}


#############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################



#############################
sub
YAMAHA_BD_SendCommand($$$$)
{
    my ($hash, $data,$cmd,$arg) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $response;
     
    Log3 $name, 4, "YAMAHA_BD ($name) - execute \"$cmd".(defined($arg) ? " ".$arg : "")."\": $data";
    
    # In case any URL changes must be made, this part is separated in this function".
    

    HttpUtils_NonblockingGet({
                                url        => "http://".$address.":50100/YamahaRemoteControl/ctrl",
                                timeout    => AttrVal($name, "request-timeout", 4),
                                noshutdown => 1,
                                data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data,
                                loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                                hash       => $hash,
                                cmd        => $cmd,
                                arg        => $arg,
                                callback   => \&YAMAHA_BD_ParseResponse
                            }
    );
    
}

sub
YAMAHA_BD_ParseResponse($$$)
{

    my ( $param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    
    my $cmd = $param->{cmd};
    my $arg = $param->{arg};
    
    
    if($err)
    {
        Log3 $name, 4, "YAMAHA_BD ($name) - error while executing \"$cmd".(defined($arg) ? " ".$arg : "")."\": $err";
        
        if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1))
		{
			Log3 $name, 3, "YAMAHA_BD ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress: $err";
			readingsSingleUpdate($hash, "presence", "absent", 1);
            readingsSingleUpdate($hash, "state", "absent", 1);
		}
    
    }
    elsif($data)
    {
    
        Log3 $name, 5, "YAMAHA_BD ($name) - got HTTP response for \"$cmd".(defined($arg) ? " ".$arg : "")."\": $data";
    
   
		if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} == 0)
		{
			Log3 $name, 3, "YAMAHA_BD: device $name reappeared";
			readingsSingleUpdate($hash, "presence", "present", 1);            
		}
        
        readingsBeginUpdate($hash);
        
         if(not $data =~ /RC="0"/)
		{
			# if the returncode isn't 0, than the command was not successful
			Log3 $name, 3, "YAMAHA_BD ($name) - Could not execute \"$cmd".(defined($arg) ? " ".$arg : "")."\"";
		}
        
        if($cmd eq "statusRequest" and $arg eq "systemStatus")
        {
            if($data =~ /<Error_Info>(.+?)<\/Error_Info>/)
            {
                readingsBulkUpdate($hash, "error", lc($1));
    
            }
        }
        elsif($cmd eq "statusRequest" and $arg eq "systemConfig")
        {
                if($data =~ /<Model_Name>(.+?)<\/Model_Name>.*<Version>(.+?)<\/Version>/)
                {
                    $hash->{MODEL} = $1;
                    $hash->{FIRMWARE} = $2;
                    
                    $hash->{MODEL} =~ s/\s*YAMAHA\s*//g;
    
                    $attr{$name}{"model"} = $hash->{MODEL};
                }
                
        }   
        elsif($cmd eq "statusRequest" and $arg eq "powerStatus")
        {
            if($data =~ /<Power>(.+?)<\/Power>/)
            {   
                my $power = $1;
           
                if($power eq "Standby" or $power eq "Network Standby")
                {	
                    $power = "off";
                }
               readingsBulkUpdate($hash, "power", lc($power));
               readingsBulkUpdate($hash, "state", lc($power));
            }
        
        }
        elsif($cmd eq "on")
        {
            if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)	
			{
				# As the player startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
				
				readingsBulkUpdate($hash, "power", "on");
				readingsBulkUpdate($hash, "state","on");
					
			}
			else
			{
				Log3 $name, 3, "YAMAHA_BD ($name) - Could not set power to on";
			}
        }


        elsif($cmd eq "statusRequest" and $arg eq "trickPlayInfo")
        {
            if($data =~ /<Trick_Play>(.+?)<\/Trick_Play>/)
            {
    			readingsBulkUpdate($hash, "trickPlay", $1);	
            }       
        }
        elsif($cmd eq "statusRequest" and $arg eq "playInfo")
        {
            if($data =~ /<Status>(.+?)<\/Status>/)
            {
                readingsBulkUpdate($hash, "playStatus", lc($1));
            }
            
            if($data =~ /<Contents>.*?<Chapter>(.+?)<\/Chapter>.*?<\/Contents>/)
            {
                readingsBulkUpdate($hash, "currentChapter", $1);
            }
            
            if($data =~ /<Contents>.*?<Track>(.+?)<\/Track>.*?<\/Contents>/)
            {
                readingsBulkUpdate($hash, "currentTrack", $1);
            }
            
            if($data =~ /<Contents>.*?<Title>(.+?)<\/Title>.*?<\/Contents>/)
            {
                readingsBulkUpdate($hash, "currentTitle", $1);
            }
            
            if($data =~ /<Disc_Info>.*?<Track_Num>(.+?)<\/Track_Num>.*?<\/Disc_Info>/)
            {
                readingsBulkUpdate($hash, "totalTracks", $1);
            }
            
            if($data =~ /<Contents>.*?<Type>(.+?)<\/Type>.*?<\/Contents>/)
            {
                readingsBulkUpdate($hash, "contentType", lc($1));
            }
            
            if($data =~ /<File_Name>(.+?)<\/File_Name>/)
            {
                readingsBulkUpdate($hash, "currentMedia", $1);
            }
            
            if($data =~ /<Disc_Type>(.+?)<\/Disc_Type>/)
            {
                readingsBulkUpdate($hash, "discType", $1);
            }
            
            if($data =~ /<Input_Info><Status>(.+?)<\/Status><\/Input_Info/)
            {
                readingsBulkUpdate($hash, "input", $1);	
            }
            elsif($data =~ /<Input_Info>(.+?)<\/Input_Info/)
            {
                readingsBulkUpdate($hash, "input", $1);
            }
            
            if($data =~ /<Tray>(.+?)<\/Tray>/)
            {
                readingsBulkUpdate($hash, "trayStatus", lc($1));
            }
            
            if($data =~ /<Current_PlayTime>(.+?)<\/Current_PlayTime>/)
            {
                readingsBulkUpdate($hash, "playTimeCurrent", YAMAHA_BD_formatTimestamp($1));
            }    
             
            if($data =~ /<Total_Time>(.+?)<\/Total_Time>/)
            {
                readingsBulkUpdate($hash, "playTimeTotal", YAMAHA_BD_formatTimestamp($1));
            }
        }
             
        readingsEndUpdate($hash, 1);
   
        YAMAHA_BD_GetStatus($hash, 1) if($cmd ne "statusRequest");
    
    }
    
    $hash->{helper}{AVAILABLE} = ($err ? 0 : 1);

}


#############################
# resets the StatusUpdate Timer according to the device state and respective interval
sub
YAMAHA_BD_ResetTimer($;$)
{
    my ($hash, $interval) = @_;
    
    RemoveInternalTimer($hash);
    
    if($hash->{helper}{DISABLED} == 0)
    {
        if(defined($interval))
        {
            InternalTimer(gettimeofday()+$interval, "YAMAHA_BD_GetStatus", $hash, 0);
        }
        elsif(exists($hash->{READINGS}{presence}{VAL}) and $hash->{READINGS}{presence}{VAL} eq "present" and exists($hash->{READINGS}{power}{VAL}) and $hash->{READINGS}{power}{VAL} eq "on")
        {
            InternalTimer(gettimeofday()+$hash->{helper}{ON_INTERVAL}, "YAMAHA_BD_GetStatus", $hash, 0);
        }
        else
        {
            InternalTimer(gettimeofday()+$hash->{helper}{OFF_INTERVAL}, "YAMAHA_BD_GetStatus", $hash, 0);
        }
    }
}


#############################
# formats a 3 byte Hex Value into human readable time duration
sub YAMAHA_BD_formatTimestamp($) 
{
    my ($hex) = @_;
    
    my ($hour) = sprintf("%02d", unpack("s", pack "s", hex(substr($hex, 0, 2))));
    my ($min) =  sprintf("%02d", unpack("s", pack "s", hex(substr($hex, 2, 2))));
    my ($sec) =  sprintf("%02d", unpack("s", pack "s", hex(substr($hex, 4, 2))));
    
    return "$hour:$min:$sec";
    
    
}

1;


=pod
=begin html

<a name="YAMAHA_BD"></a>
<h3>YAMAHA_BD</h3>
<ul>

  <a name="YAMAHA_BDdefine"></a>
  <b>Define</b>
  <ul>
    <code>
    define &lt;name&gt; YAMAHA_BD &lt;ip-address&gt; [&lt;status_interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_BD &lt;ip-address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>

    This module controls Blu-Ray players from Yamaha via network connection. You are able
    to switch your player on and off, query it's power state,
    control the playback, open and close the tray and send all remote control commands.<br><br>
    Defining a YAMAHA_BD device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of the player (power state, current disc, tray status,...)
    and triggers notify/filelog commands.
    <br><br>
    Different status update intervals depending on the power state can be given also. 
    If two intervals are given to the define statement, the first interval statement represents the status update 
    interval in seconds in case the device is off, absent or any other non-normal state. The second 
    interval statement is used when the device is on.
   
    Example:<br><br>
    <ul><code>
       define BD_Player YAMAHA_BD 192.168.0.10
       <br><br>
       # With custom status interval of 60 seconds<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60 
       <br><br>
       # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60 10
    </code></ul>
   
  </ul>
  <br><br>
  <a name="YAMAHA_BDset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; shuts down the device </li>
<li><b>tray</b> open,close &nbsp;&nbsp;-&nbsp;&nbsp; open or close the disc tray</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands as listed in the following chapter</li>
</ul><br>
<u>Playback control commands</u>
<ul>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playing the current media</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause the current media playback</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop the current media playback</li>
<li><b>skip</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; skip the current track or chapter</li>
<li><b>fast</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; fast forward or reverse playback</li>
<li><b>slow</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; slow forward or reverse playback</li>
<li><b>trickPlay</b> normal,repeatChapter,repeatTitle,... &nbsp;&nbsp;-&nbsp;&nbsp; controls the Trick-Play features</li>


</ul>
</ul><br><br>
<u>Remote control</u><br><br>
<ul>
    The following commands are available:<br><br>

    <u>Number Buttons (0-9):</u><br><br>
    <ul><code>
    remoteControl 0<br>
    remoteControl 1<br>
    remoteControl 2<br>
    ...<br>
    remoteControl 9<br>
    </code></ul><br><br>
    
    <u>Cursor Selection:</u><br><br>
    <ul><code>
    remoteControl up<br>
    remoteControl down<br>
    remoteControl left<br>
    remoteControl right<br>
    remoteControl enter<br>
    remoteControl return<br>
    </code></ul><br><br>

    <u>Menu Selection:</u><br><br>
    <ul><code>
    remoteControl OSDonScreen<br>
    remoteControl OSDstatus<br>
    remoteControl popupMenu<br>
    remoteControl topMenu<br>
    remoteControl setup<br>
    remoteControl home<br>
    remoteControl clear<br>
    </code></ul><br><br>
    
    <u>Color Buttons:</u><br><br>
    <ul><code>
    remoteControl red<br>
    remoteControl green<br>
    remoteControl yellow<br>
    remoteControl blue<br>
    </code></ul><br><br>
    
    <u>Play Control Buttons:</u><br><br>
    <ul><code>
    remoteControl program<br>
    remoteControl search<br>
    remoteControl repeat<br>
    remoteControl repeat-AB<br>
    remoteControl subtitle<br>
    remoteControl audio<br>
    remoteControl angle<br>
    remoteControl pictureInPicture<br>
    remoteControl secondAudio<br>
    remoteControl secondVideo<br>
    </code></ul><br><br>
    The button names are the same as on your remote control.<br><br>
  
  </ul>

  <a name="YAMAHA_BDget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code>
    <br><br>
    Currently, the get command only returns the reading values. For a specific list of possible values, see section "Generated Readings/Events".
	<br><br>
  </ul>
  <a name="YAMAHA_BDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="disable">disable</a></li>
	Optional attribute to disable the internal cyclic status update of the player. Manual status updates via statusRequest command is still possible.
	<br><br>
	Possible values: 0 => perform cyclic status update, 1 => don't perform cyclic status updates.<br><br>
	<li><a name="request-timeout">request-timeout</a></li>
	Optional attribute change the response timeout in seconds for all queries to the player.
	<br><br>
	Possible values: 1-5 seconds. Default value is 4 seconds.<br><br>
  </ul>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>input</b> - The current playback source (can be "DISC", "USB" or "Network")</li>
  <li><b>discType</b> - The current type of disc, which is inserted (e.g. "No Disc", "CD", "DVD", "BD",...)</li>
  <li><b>contentType</b> - The current type of content, which is played (e.g. "audio", "video", "photo" or "no contents")</li>
  <li><b>error</b> - indicates an hardware error of the player (can be "none", "fan error" or "usb overcurrent")</li>
  <li><b>power</b> - Reports the power status of the player or zone (can be "on" or "off")</li>
  <li><b>presence</b> - Reports the presence status of the player or zone (can be "absent" or "present"). In case of an absent device, it cannot be controlled via FHEM anymore.</li>
  <li><b>trayStatus</b> - The disc tray status (can be "open" or "close")</li>
  <li><b>trickPlay</b> - The current trickPlay mode</li>
  <li><b>state</b> - Reports the current power state and an absence of the device (can be "on", "off" or "absent")</li>
  <br><br><u>Input dependent Readings/Events:</u><br>
  <li><b>currentChapter</b> - Number of the current DVD/BD Chapter (only at DVD/BD's)</li>
  <li><b>currentMedia</b> - Name of the current file (only at USB)</li>
  <li><b>currentTrack</b> - Number of the current CD-Audio title (only at CD-Audio)</li>
  <li><b>currentTitle</b> - Number of the current title (only at DVD/BD's)</li>
  <li><b>playTimeCurrent</b> - current timecode of played media</li>
  <li><b>playTimeTotal</b> - the total time of the current movie (only at DVD/BD's)</li>
  <li><b>playStatus</b> - indicates if the player plays media or not (can be "play", "pause", "stop", "fast fwd", "fast rev", "slow fwd", "slow rev")</li>
  <li><b>totalTracks</b> - The number of total tracks on inserted CD-Audio</li>
  </ul>
<br>
  <b>Implementator's note</b><br>
  <ul>
  <li>Some older models (e.g. BD-S671) cannot be controlled over networked by delivery. A <u><b>firmware update is neccessary</b></u> to control these models via FHEM. In general it is always recommended to use the latest firmware.</li> 
   <li>The module is only usable if you activate "Network Control" on your player. Otherwise it is not possible to communicate with the player.</li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="YAMAHA_BD"></a>
<h3>YAMAHA_BD</h3>
<ul>

  <a name="YAMAHA_BDdefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; YAMAHA_BD &lt;IP-Addresse&gt; [&lt;Status_Interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_BD &lt;IP-Addresse&gt; [&lt;Off_Interval&gt;] [&lt;On_Interval&gt;]
    </code>
    <br><br>

    Dieses Modul steuert Blu-Ray Player des Herstellers Yamaha &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit den Player an-/auszuschalten, die Schublade zu &ouml;ffnen und schlie&szlig;en,
    die Wiedergabe beeinflussen, s&auml;mtliche Fernbedieungs-Befehle zu senden, sowie den aktuellen Status abzufragen.
    <br><br>
    Bei der Definition eines YAMAHA_BD-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter <code>&lt;Status_Interval&gt;</code>; falls nicht gesetzt ist der Standardwert 30 Sekunden)
    den Status des Players abfragt und entsprechende Notify-/FileLog-Definitionen triggert.
    <br><br>
    Sofern 2 Interval-Argumente &uuml;bergeben werden, wird der erste Parameter <code>&lt;Off_Interval&gt;</code> genutzt
    sofern der Player ausgeschaltet oder nicht erreichbar ist. Der zweiter Parameter <code>&lt;On_Interval&gt;</code> 
    wird verwendet, sofern der Player eingeschaltet ist. 
    <br><br>
    Beispiel:<br><br>
    <ul><code>
       define BD_Player YAMAHA_BD 192.168.0.10
       <br><br>
       # Mit modifiziertem Status Interval (60 Sekunden)<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60
       <br><br>
       # Mit gesetztem "Off"-Interval (60 Sekunden) und "On"-Interval (10 Sekunden)<br>
       define BD_Player YAMAHA_BD 192.168.0.10 60 10
    </code></ul><br><br>
  </ul>

  <a name="YAMAHA_BDset"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <br><br>
    Aktuell werden folgende Kommandos unterst&uuml;tzt.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; schaltet den Player ein</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; schaltet den Player aus </li>
<li><b>tray</b> open,close &nbsp;&nbsp;-&nbsp;&nbsp; &ouml;ffnet oder schlie&szlig;t die Schublade</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; fragt den aktuellen Status ab</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sendet Fernbedienungsbefehle wie im folgenden Kapitel beschrieben.</li>
</ul><br>
<u>Wiedergabespezifische Kommandos</u>
<ul>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; startet die Wiedergabe des aktuellen Mediums</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pausiert die Wiedergabe</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stoppt die Wiedergabe</li>
<li><b>skip</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; &uuml;berspringt das aktuelle Kapitel oder den aktuellen Titel</li>
<li><b>fast</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; schneller Vor- oder R&uuml;cklauf</li>
<li><b>slow</b> forward,reverse &nbsp;&nbsp;-&nbsp;&nbsp; langsamer Vor- oder R&uuml;cklauf</li>
<li><b>trickPlay</b> normal,repeatChapter,repeatTitle,... &nbsp;&nbsp;-&nbsp;&nbsp; aktiviert Trick-Play Funktionen (Wiederholung, Zufallswiedergabe, ...)</li>

</ul>
<br><br>
</ul>
<u>Fernbedienung</u><br><br>
<ul>
    Es stehen folgende Befehle zur Verf&uuml;gung:<br><br>

    <u>Zahlen Tasten (0-9):</u><br><br>
    <ul><code>
    remoteControl 0<br>
    remoteControl 1<br>
    remoteControl 2<br>
    ...<br>
    remoteControl 9<br>
    </code></ul><br><br>
    
    <u>Cursor Steuerung:</u><br><br>
    <ul><code>
    remoteControl up<br>
    remoteControl down<br>
    remoteControl left<br>
    remoteControl right<br>
    remoteControl enter<br>
    remoteControl return<br>
    </code></ul><br><br>

    <u>Men&uuml; Auswahl:</u><br><br>
    <ul><code>
    remoteControl OSDonScreen<br>
    remoteControl OSDstatus<br>
    remoteControl popupMenu<br>
    remoteControl topMenu<br>
    remoteControl setup<br>
    remoteControl home<br>
    remoteControl clear<br>
    </code></ul><br><br>
    
    <u>Farbtasten:</u><br><br>
    <ul><code>
    remoteControl red<br>
    remoteControl green<br>
    remoteControl yellow<br>
    remoteControl blue<br>
    </code></ul><br><br>
  
    <u>Wiedergabetasten:</u><br><br>
    <ul><code>
    remoteControl program<br>
    remoteControl search<br>
    remoteControl repeat<br>
    remoteControl repeat-AB<br>
    remoteControl subtitle<br>
    remoteControl audio<br>
    remoteControl angle<br>
    remoteControl pictureInPicture<br>
    remoteControl secondAudio<br>
    remoteControl secondVideo<br>
    </code></ul><br><br>
    
    Die Befehlsnamen entsprechen den Tasten auf der Fernbedienung.<br><br>
  </ul>

  <a name="YAMAHA_BDget"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Readingname&gt;</code>
    <br><br>
    Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".
  </ul>
  <br><br>
  <a name="YAMAHA_BDattr"></a>
  <b>Attribute</b>
  <ul>
  
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="disable">disable</a></li>
	Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
	<br><br>
	M&ouml;gliche Werte: 0 => zyklische Status-Updates, 1 => keine zyklischen Status-Updates.<br><br>
	<li><a name="request-timeout">request-timeout</a></li>
	Optionales Attribut. Maximale Dauer einer Anfrage in Sekunden zum Player.
	<br><br>
	M&ouml;gliche Werte: 1-5 Sekunden. Standartwert ist 4 Sekunden<br><br>
  </ul>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>input</b> - Die aktuelle Wiedergabequelle ("DISC", "USB" oder "Network")</li>
  <li><b>discType</b> - Die Art der eingelegten Disc (z.B "No Disc" => keine Disc eingelegt, "CD", "DVD", "BD",...)</li>
  <li><b>contentType</b> - Die Art des Inhaltes, der gerade abgespielt wird ("audio", "video", "photo" oder "no contents")</li>
  <li><b>error</b> - zeigt an, ob ein interner Fehler im Player vorliegt ("none" => kein Fehler, "fan error" => L&uuml;fterdefekt, "usb overcurrent" => USB Spannungsschutz)</li>
  <li><b>power</b> - Der aktuelle Betriebsstatus ("on" => an, "off" => aus)</li>
  <li><b>presence</b> - Die aktuelle Empfangsbereitschaft ("present" => empfangsbereit, "absent" => nicht empfangsbereit, z.B. Stromausfall)</li>
  <li><b>trayStatus</b> - Der Status der Schublade("open" => ge&ouml;ffnet, "close" => geschlossen)</li>
  <li><b>trickPlay</b> - Der aktuell aktive Trick-Play Modus</li>
  <li><b>state</b> - Der aktuelle Schaltzustand (power-Reading) oder die Abwesenheit des Ger&auml;tes (m&ouml;gliche Werte: "on", "off" oder "absent")</li>
  <br><br><u>Quellenabh&auml;ngige Readings/Events:</u><br>
  <li><b>currentChapter</b> - Das aktuelle Kapitel eines DVD- oder Blu-Ray-Films</li>
  <li><b>currentTitle</b> - Die Titel-Nummer des aktuellen DVD- oder Blu-Ray-Films</li>
  <li><b>currentTrack</b> - Die aktuelle Track-Nummer der wiedergebenden Audio-CD</li>
  <li><b>currentMedia</b> -  Der Name der aktuell wiedergebenden Datei (Nur bei der Wiedergabe &uuml;ber USB)</li>
  <li><b>playTimeCurrent</b> - Der aktuelle Timecode an dem sich die Wiedergabe momentan befindet.</li>
  <li><b>playTimeTotal</b> - Die komplette Spieldauer des aktuellen Films (Nur bei der Wiedergabe von DVD/BD's)</li>
  <li><b>playStatus</b> - Wiedergabestatus des aktuellen Mediums</li>
  <li><b>totalTracks</b> - Gesamtanzahl aller Titel einer Audio-CD</li>
  </ul>
<br>
  <b>Hinweise des Autors</b>
  <ul>
   <li>Einige &auml;ltere Player-Modelle (z.B. BD-S671) k&ouml;nnen im Auslieferungszustand nicht via Netzwerk gesteuert werden. Um eine Steuerung via FHEM zu erm&ouml;glichen ist ein <u><b>Firmware-Update notwending</b></u>!</li> 
    <li>Dieses Modul ist nur nutzbar, wenn die Option "Netzwerksteuerung" am Player aktiviert ist. Ansonsten ist die Steuerung nicht m&ouml;glich.</li>
  </ul>
  <br>
</ul>
=end html_DE

=cut

