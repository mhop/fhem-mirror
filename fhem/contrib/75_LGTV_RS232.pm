##############################################
# $Id$
#
# created by Markus Bloch (Notausstieg0309@googlemail.com)
#
# This modules controls LG Smart TV's which are connected via
# a USB to Serial converter to FHEM.
#
# Detailed Information about the hardware setup and more possible control commands: http://www.lgrs232.com/
#
# This modules is able to switch the input channels, which
# is not possible via the ethernet interface.
#
# Define:  define TV LGTV_RS232 /dev/ttyUSB0
#
# Set: statusRequest input:hmdi1,hdmi2, ...
#
#
# 

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use DevIo;

my %LGTV_RS232_response = (

"a" =>  {   
            "power" => {"00" => "off",
                        "01" => "on"
                       },
            "state" => {"00" => "off",
                        "01" => "on"
                       }            
        },
"b" =>  {
            "input" => {"00" => "digitalTV",
                        "01"  => "analogueTV",
                        "02" => "video1",
                        "03" => "video2",
                        "04" => "component1",
                        "05" => "component2",
                        "06" => "rgbDTV",
                        "07" => "rgbPC",
                        "08" => "hdmi1",
                        "09" => "hdmi2"
                        }
            
        },
"c" =>  {   
            "aspectRatio" => {  "01" => "normal",
                                "02" => "wide",
                                "03" => "horizon",
                                "04" => "zoom1",
                                "05" => "zoom2",
                                "06" => "auto",
                                "07" => "14:9",
                                "08" => "full",
                                "09" => "justScan",
                                "0a" => "zoom3",
                                "0b" => "fullWide",
                                "10" => "cinemaZoom1",
                                "11" => "cinemaZoom16"
                             }
        },
"d" =>  {
            "screenMute"    => {"00" => "off",
                                "01" => "on"
                               },
            "videoOutMute"  => {"00" => "off",
                                "10" => "on"
                               }
        },        
"e" =>  {
            "volumeMute" => {"00" => "on",
                             "01" => "off"
                            }
        }
);

my %LGTV_RS232_set = (
"input" => {
            "digitalTV" => "kb 01 00",
            "video1"    => "kb 01 02",
            "video2"    => "kb 01 03",
            "component" => "kb 01 04",
            "hdmi1"     => "kb 01 08",
            "hdmi2"     => "kb 01 09",
           },
"power" => {
	    "on"        => "ka 01 01",
	    "off"       => "ka 01 00",
           }
);



#####################################
sub
LGTV_RS232_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "LGTV_RS232_Define";
  $hash->{UndefFn}  = "LGTV_RS232_Undef";
  $hash->{SetFn}    = "LGTV_RS232_Set";
  $hash->{ReadFn}   = "LGTV_RS232_Read";
  $hash->{ReadyFn}  = "LGTV_RS232_Ready";
  $hash->{AttrList} = " ".$readingFnAttributes;
}

#####################################
sub
LGTV_RS232_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);



  my $name = $a[0];
  my $dev = $a[2];


  
  $hash->{helper}{RECEIVE_BUFFER} = "";
  
  $dev .= "\@9600" if(not $dev =~ m/\@\d+/);
  
  $hash->{DeviceName} = $dev;
  
  DevIo_CloseDev($hash);
  
  my $ret = DevIo_OpenDev($hash, 0, undef);
  
  delete($hash->{PARTIAL});
  RemoveInternalTimer($hash);
  LGTV_RS232_GetStatus($hash);
  return undef;
}

#####################################
sub
LGTV_RS232_Undef($$)
{
  my ($hash, $arg) = @_;
  
  DevIo_CloseDev($hash); 
  return undef;
}


#####################################
sub
LGTV_RS232_Set($@)
{
    my ($hash, @a) = @_;

    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of statusRequest";

    foreach my $cmd (sort keys %LGTV_RS232_set)
    {
       $usage .= " $cmd:".join(",", sort keys %{$LGTV_RS232_set{$cmd}});
    }

    if($what eq "statusRequest")
    {
        LGTV_RS232_GetStatus($hash, 1);
    }
    elsif(exists($LGTV_RS232_set{$what}) and exists($LGTV_RS232_set{$what}{$a[2]}))
    {
        DevIo_SimpleWrite($hash, $LGTV_RS232_set{$what}{$a[2]}."\n", 0);
    }
    else
    {
      return $usage;
    }
   
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
LGTV_RS232_Read($)
{
    my ($hash) = @_;

    my $buf = DevIo_SimpleRead($hash);
    return "" if(!defined($buf));
    my $name = $hash->{NAME};

    my $partial = $hash->{helper}{RECEIVE_BUFFER};

    Log3 $name, 5, "LGTV_RS232 ($name) - ".($partial ne "" ? "(buffer contains: $partial) " : "")."received: $buf"; 
   
    $partial .= $buf;

    while($partial =~ /(\w\s\d{2}\s[0-9a-zA-Z]+?x)(.*)/)
    {
        my $msg = $1;
        $partial = $2;
        $msg =~ s/x$//;

        LGTV_RS232_ParseResponse($hash, $msg);
    }
    
    $hash->{helper}{RECEIVE_BUFFER} = $partial;
    
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+15, "LGTV_RS232_GetStatus", $hash, 0);
}


#####################################
# receives incoming data
sub
LGTV_RS232_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, undef) if($hash->{STATE} eq "disconnected");
}

sub
LGTV_RS232_ParseResponse($$)
{
    my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
    
    Log3 $name, 4, "LGTV_RS232 ($name) - processing response: ".$msg;

    my ($code, $glue, $result, $val) = unpack("A2 A3 A2 A*", $msg);
    
    Log3 $name, 5, "LGTV_RS232 ($name) - processed code: $code - glue: $glue - result: $result - val: $val";
    
    readingsBeginUpdate($hash);
    
    if($result eq "OK")
    {
         readingsBulkUpdate($hash, "CommandAccepted", "yes");
    }
    elsif($result eq "NG")
    {
         readingsBulkUpdate($hash, "CommandAccepted", "no");    
         return;
         
    }
    
    foreach my $reading (keys %{$LGTV_RS232_response{$code}})
    {
        if(exists($LGTV_RS232_response{$code}{$reading}{$val}))
        {
            readingsBulkUpdate($hash, $reading, $LGTV_RS232_response{$code}{$reading}{$val});
        }
    }
    
    if($code eq "f")
    {
        readingsBulkUpdate($hash, "volume", hex($val)." %");
    }
    readingsBulkUpdate($hash, "presence", "present");
    readingsEndUpdate($hash, 1);

}

#####################################
# request the current state
sub
LGTV_RS232_GetStatus($;$)
{
    my ($hash, $local) = @_;
    
    DevIo_SimpleWrite($hash, "ka 01 ff\n", 0);
    DevIo_SimpleWrite($hash, "kb 01 ff\n", 0);
    DevIo_SimpleWrite($hash, "kc 01 ff\n", 0);
    DevIo_SimpleWrite($hash, "kd 01 ff\n", 0);
    DevIo_SimpleWrite($hash, "kf 01 ff\n", 0);
    DevIo_SimpleWrite($hash, "ke 01 ff\n", 0);

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+2, "LGTV_RS232_TimeOut", $hash, 0);

}

#####################################
# Is executed when a request via serial connection was not answered
sub 
LGTV_RS232_TimeOut($)
{
    my ($hash) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "presence", "absent");
    readingsBulkUpdate($hash, "state", "off");
    readingsEndUpdate($hash, 1);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+15, "LGTV_RS232_GetStatus", $hash, 0);
}

1;