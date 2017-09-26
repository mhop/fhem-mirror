# $Id$
##############################################################################
#
#     71_YAMAHA_AVR.pm
#     An FHEM Perl module for controlling Yamaha AV-Receivers
#     via network connection. As the interface is standardized
#     within all Yamaha AV-Receivers, this module should work
#     with any receiver which has an ethernet or wlan connection.
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
use Time::HiRes qw(gettimeofday sleep);
use Encode qw(decode encode);
use HttpUtils;
 
sub YAMAHA_AVR_Get($@);
sub YAMAHA_AVR_Define($$);
sub YAMAHA_AVR_GetStatus($;$);
sub YAMAHA_AVR_Attr(@);
sub YAMAHA_AVR_ResetTimer($;$);
sub YAMAHA_AVR_Undefine($$);

###################################
sub
YAMAHA_AVR_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "YAMAHA_AVR_Get";
  $hash->{SetFn}     = "YAMAHA_AVR_Set";
  $hash->{DefFn}     = "YAMAHA_AVR_Define";
  $hash->{AttrFn}    = "YAMAHA_AVR_Attr";
  $hash->{UndefFn}   = "YAMAHA_AVR_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 ".
                       "disable:0,1 ".
                       "disabledForIntervals ".
                       "request-timeout:1,2,3,4,5 ".
                       "radioTitleDelimiter ".
                       "model ".
                       "volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 ".
                       "volumeMax ".
                       "volume-smooth-change:0,1 ".
                       "volume-smooth-steps:1,2,3,4,5,6,7,8,9,10 ".
                       $readingFnAttributes;
}

#############################
sub
YAMAHA_AVR_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(!@a >= 4)
    {
        my $msg = "wrong syntax: define <name> YAMAHA_AVR <ip-or-hostname> [<zone>] [<ON-statusinterval>] [<OFF-statusinterval>] ";
        Log3 $name, 2, $msg;
        return $msg;
    }

    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;

    # if a zone was given, use it, otherwise use the mainzone
    if(defined($a[3]))
    {
        $hash->{helper}{SELECTED_ZONE} = $a[3];
    }
    else
    {
        $hash->{helper}{SELECTED_ZONE} = "mainzone";
    }
    
    # if an update interval was given which is greater than zero, use it.
    if(defined($a[4]) and $a[4] > 0)
    {
        $hash->{helper}{OFF_INTERVAL} = $a[4];
    }
    else
    {
        $hash->{helper}{OFF_INTERVAL} = 30;
    }
      
    if(defined($a[5]) and $a[5] > 0)
    {
        $hash->{helper}{ON_INTERVAL} = $a[5];
    }
    else
    {
        $hash->{helper}{ON_INTERVAL} = $hash->{helper}{OFF_INTERVAL};
    }
    
    $hash->{helper}{CMD_QUEUE} = [];
    delete($hash->{helper}{".HTTP_CONNECTION"}) if(exists($hash->{helper}{".HTTP_CONNECTION"}));
    
    # In case of a redefine, check the zone parameter if the specified zone exist, otherwise use the main zone
    if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
    {
        if(defined(YAMAHA_AVR_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES})))
        {
            $hash->{ACTIVE_ZONE} = lc $hash->{helper}{SELECTED_ZONE}; 
        }
        else
        {
            Log3 $name, 2, "YAMAHA_AVR ($name) - selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available on device ".$hash->{NAME}.". Using Main Zone instead";
            $hash->{ACTIVE_ZONE} = "mainzone";
        }
        YAMAHA_AVR_getInputs($hash);
    }

    unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
    {
        $hash->{helper}{AVAILABLE} = 1;
        readingsSingleUpdate($hash, "presence", "present", 1);
    }

    # start the status update timer
    YAMAHA_AVR_ResetTimer($hash,1);
  
    return undef;
}

###################################
sub
YAMAHA_AVR_GetStatus($;$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $power;
   
    $local = 0 unless(defined($local));

    return "" if(!defined($hash->{helper}{ADDRESS}) or !defined($hash->{helper}{OFF_INTERVAL}) or !defined($hash->{helper}{ON_INTERVAL}));

    my $device = $hash->{helper}{ADDRESS};

    # get the model informations and available zones if no informations are available
    if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{helper}{ZONES}) or not defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
        YAMAHA_AVR_getModel($hash);
    }

    # get all available inputs and scenes if nothing is available
    if((not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0))
    {
        YAMAHA_AVR_getInputs($hash);
    }
    
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    if(not defined($zone))
    {
        YAMAHA_AVR_ResetTimer($hash) unless($local == 1);
        return "No Zone available";
    }
    
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus");

    if($hash->{ACTIVE_ZONE} eq "mainzone" and (!exists($hash->{helper}{SUPPORT_PARTY_MODE}) or $hash->{helper}{SUPPORT_PARTY_MODE}))
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Party_Mode><Mode>GetParam</Mode></Party_Mode></System></YAMAHA_AV>", "statusRequest", "partyModeStatus", {options => {can_fail => 1}});
    }
    elsif($hash->{ACTIVE_ZONE} ne "mainzone" and (!exists($hash->{helper}{SUPPORT_PARTY_MODE}) or $hash->{helper}{SUPPORT_PARTY_MODE}))
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Party_Mode><Target_Zone>GetParam</Target_Zone></Party_Mode></System></YAMAHA_AV>", "statusRequest", "partyModeZones", {options => {can_fail => 1}});
    }
    
    if($hash->{ACTIVE_ZONE} eq "mainzone" and (!exists($hash->{helper}{SUPPORT_SURROUND_DECODER}) or $hash->{helper}{SUPPORT_SURROUND_DECODER}))
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Surround><Sound_Program_Param><SUR_DECODE>GetParam</SUR_DECODE></Sound_Program_Param></Surround></$zone></YAMAHA_AV>", "statusRequest", "surroundDecoder", {options => {can_fail => 1}});
    }
   
    if($hash->{ACTIVE_ZONE} eq "mainzone" and (!exists($hash->{helper}{SUPPORT_DISPLAY_BRIGHTNESS}) or $hash->{helper}{SUPPORT_DISPLAY_BRIGHTNESS}))
    {
        if(YAMAHA_AVR_isModel_DSP($hash))
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Display><FL>GetParam</FL></Display></System></YAMAHA_AV>", "statusRequest", "displayBrightness", {options => {can_fail => 1}});
        }
        else
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Display><FL>GetParam</FL></Display></Misc></System></YAMAHA_AV>", "statusRequest", "displayBrightness", {options => {can_fail => 1}});
        }
    }
    
    if(!exists($hash->{helper}{SUPPORT_TONE_STATUS}) or (exists($hash->{helper}{SUPPORT_TONE_STATUS}) and exists($hash->{MODEL}) and $hash->{helper}{SUPPORT_TONE_STATUS}))
    {   
        if(YAMAHA_AVR_isModel_DSP($hash))
        {
            if($zone eq "Main_Zone")
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Tone><Speaker><Bass>GetParam</Bass></Speaker></Tone></$zone></YAMAHA_AV>", "statusRequest", "toneStatus", {options => {can_fail => 1}});
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Tone><Speaker><Treble>GetParam</Treble></Speaker></Tone></$zone></YAMAHA_AV>", "statusRequest", "toneStatus", {options => {can_fail => 1}});
            }
            else
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Tone><Bass>GetParam</Bass></Tone></$zone></YAMAHA_AV>", "statusRequest", "toneStatus", {options => {can_fail => 1}});
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Tone><Treble>GetParam</Treble></Tone></$zone></YAMAHA_AV>", "statusRequest", "toneStatus", {options => {can_fail => 1}});
            }
        }
        else
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Sound_Video><Tone><Bass>GetParam</Bass></Tone></Sound_Video></$zone></YAMAHA_AV>", "statusRequest", "toneStatus", {options => {can_fail => 1}});
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Sound_Video><Tone><Treble>GetParam</Treble></Tone></Sound_Video></$zone></YAMAHA_AV>", "statusRequest", "toneStatus", {options => {can_fail => 1}});
        }
    }
    
    # check for FW update
    if(defined($hash->{MODEL}))
    {
        if($hash->{MODEL} =~ /^RX-(?:A\d{1,2}10|V\d{1,2}71)$/) # RX-Vx71 / RX-Ax10 have different firmware status request
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Update><Status>GetParam</Status></Update></Network></Misc></System></YAMAHA_AV>", "statusRequest", "fwUpdate", {options => {can_fail => 1}});
        }
        elsif($hash->{MODEL} =~ /^RX-(?:A\d{1,2}20|V\d{1,2}73)$/) # RX-Vx73 / RX-Ax20 have different firmware status request
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Update><YAMAHA_Network_Site><Status>GetParam</Status></YAMAHA_Network_Site></Update></Misc></System></YAMAHA_AV>", "statusRequest", "fwUpdate", {options => {can_fail => 1}});
        }
    }
    
    # check hdmi output state, if supported
    if($hash->{ACTIVE_ZONE} eq "mainzone" and $hash->{helper}{SUPPORT_HDMI_OUT})
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Sound_Video><HDMI><Output><OUT_1>GetParam</OUT_1></Output></HDMI></Sound_Video></System></YAMAHA_AV>", "statusRequest", "hdmiOut1", {options => {can_fail => 1}});
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Sound_Video><HDMI><Output><OUT_2>GetParam</OUT_2></Output></HDMI></Sound_Video></System></YAMAHA_AV>", "statusRequest", "hdmiOut2", {options => {can_fail => 1}});
    }
    
    YAMAHA_AVR_ResetTimer($hash) unless($local == 1);
    
    return undef;
}

###################################
sub
YAMAHA_AVR_Get($@)
{
    my ($hash, @a) = @_;
    my $what;
    my $return;
    
    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    return ReadingsVal($hash->{NAME}, $what, "") if(defined(ReadingsVal($hash->{NAME}, $what, undef)));
     
    $return = "unknown argument $what, choose one of";
    
    foreach my $reading (keys %{$hash->{READINGS}})
    {
        $return .= " $reading:noArg";
    }
    
    return $return;
}


###################################
sub
YAMAHA_AVR_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    
    # get the model informations and available zones if no informations are available
    if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{helper}{ZONES}))
    {
        YAMAHA_AVR_getModel($hash);
    }

    # get all available inputs if nothing is available
    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
        YAMAHA_AVR_getInputs($hash);
    }
    
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    my $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
    my $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{INPUTS}), 1) : "" ;

    my $scenes_piped = defined($hash->{helper}{SCENES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{SCENES}), 0) : "" ;
    my $scenes_comma = defined($hash->{helper}{SCENES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{SCENES}), 1) : "" ;
    
    my $dsp_modes_piped = defined($hash->{helper}{DSP_MODES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{DSP_MODES}), 0) : "" ;
    my $dsp_modes_comma = defined($hash->{helper}{DSP_MODES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{DSP_MODES}), 1) : "" ;
    
    my $decoders_piped = defined($hash->{helper}{SURROUND_DECODERS}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{SURROUND_DECODERS}), 0) : "" ;
    my $decoders_comma = defined($hash->{helper}{SURROUND_DECODERS}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{SURROUND_DECODERS}), 1) : "" ;
       
    return "No Argument given" if(!defined($a[1]));     
    
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of ". "on:noArg ".
                                                          "off:noArg ".
                                                          "volumeStraight:slider,-80,1,16 ".
                                                          "volume:slider,0,1,100 ".
                                                          (defined(ReadingsVal($name, "volume", undef)) ? "volumeUp volumeDown " : "").
                                                          (exists($hash->{helper}{INPUTS}) ? "input:".$inputs_comma." " : "").
                                                          "mute:on,off,toggle ".
                                                          "remoteControl:setup,up,down,left,right,return,option,display,tunerPresetUp,tunerPresetDown,enter ".
                                                          (exists($hash->{helper}{SCENES}) ? "scene:".$scenes_comma." " : "").
                                                          ((exists($hash->{ACTIVE_ZONE}) and $hash->{ACTIVE_ZONE} eq "mainzone") ? 
                                                            "straight:on,off 3dCinemaDsp:off,auto adaptiveDrc:off,auto ".
                                                            (exists($hash->{helper}{DIRECT_TAG}) ? "direct:on,off " : "").
                                                            (exists($hash->{helper}{SURROUND_DECODERS}) ? "surroundDecoder:".$decoders_comma." " : "").
                                                            ($hash->{helper}{SUPPORT_DISPLAY_BRIGHTNESS} ? "displayBrightness:slider,-4,1,0 " : "").
                                                            (exists($hash->{helper}{DSP_MODES}) ? "dsp:".$dsp_modes_comma." " : "").
                                                            "enhancer:on,off ".
                                                            ($hash->{helper}{SUPPORT_HDMI_OUT} ? "hdmiOut1:on,off hdmiOut2:on,off " : "")
                                                          :"").
                                                          (exists($hash->{helper}{CURRENT_INPUT_TAG}) ? 
                                                            "navigateListMenu play:noArg pause:noArg stop:noArg skip:reverse,forward ".
                                                            "preset:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40 ".
                                                            "presetUp:noArg presetDown:noArg ".
                                                            (($hash->{helper}{SUPPORT_SHUFFLE_REPEAT}) ? "shuffle:on,off repeat:off,one,all " : "") 
                                                          :"").
                                                          "sleep:off,30min,60min,90min,120min,last ".
                                                          (($hash->{helper}{SUPPORT_TONE_STATUS} and exists($hash->{ACTIVE_ZONE}) and $hash->{ACTIVE_ZONE} eq "mainzone") ? "bass:slider,-6,0.5,6 treble:slider,-6,0.5,6 " : "").
                                                          (($hash->{helper}{SUPPORT_TONE_STATUS} and exists($hash->{ACTIVE_ZONE}) and ($hash->{ACTIVE_ZONE} ne "mainzone") and YAMAHA_AVR_isModel_DSP($hash)) ? "bass:slider,-10,1,10 treble:slider,-10,1,10 " : "").
                                                          (($hash->{helper}{SUPPORT_TONE_STATUS} and exists($hash->{ACTIVE_ZONE}) and ($hash->{ACTIVE_ZONE} ne "mainzone") and not YAMAHA_AVR_isModel_DSP($hash)) ? "bass:slider,-10,2,10 treble:slider,-10,2,10 " : "").
                                                          ($hash->{helper}{SUPPORT_PARTY_MODE} ? "partyMode:on,off " : "").
                                                          ($hash->{helper}{SUPPORT_EXTRA_BASS} ? "extraBass:off,auto " : "").
                                                          ($hash->{helper}{SUPPORT_YPAO_VOLUME} ? "ypaoVolume:off,auto " : "").
                                                          
                                                          "tunerFrequency ".
                                                          "displayBrightness:slider,-4,1,0 ".
                                                          "statusRequest:noArg";
                           
    # number of seconds to wait after on/off was executed (DSP based: 3 sec, other models: 2 sec)
    my $powerCmdDelay = (YAMAHA_AVR_isModel_DSP($hash) ? "3" : "2"); 
                                                          
    Log3 $name, 5, "YAMAHA_AVR ($name) - set ".join(" ", @a);
    
    if($what eq "on")
    {        
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Power>On</Power></Power_Control></$zone></YAMAHA_AV>" ,$what, undef, {options => {wait_after_response => $powerCmdDelay}});
    }
    elsif($what eq "off")
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Power>Standby</Power></Power_Control></$zone></YAMAHA_AV>", $what, undef,{options => {wait_after_response => $powerCmdDelay}});
    }
    elsif($what eq "input")
    {
        if(defined($a[2]))
        {
            if(not $inputs_piped eq "")
            {
                if($a[2] =~ /^($inputs_piped)$/)
                {
                    my $command = YAMAHA_AVR_getParamName($hash, $a[2], $hash->{helper}{INPUTS});
                    if(defined($command) and length($command) > 0)
                    {
                         YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Input><Input_Sel>".$command."</Input_Sel></Input></$zone></YAMAHA_AV>", $what, $a[2]);
                    }
                    else
                    {
                        return "invalid input: ".$a[2];
                    } 
                }
                else
                {
                    return $usage;
                }
            }
            else
            {
                return "No inputs are avaible. Please try an statusUpdate.";
            }
        }
        else
        {
            return (($inputs_piped eq "") ? "No inputs are available. Please try an statusUpdate." : "No input parameter was given");
        }
    }
    elsif($what eq "scene")
    {
        if(defined($a[2]))
        {
            
            if(not $scenes_piped eq "")
            {
                if($a[2] =~ /^($scenes_piped)$/)
                {
                    my $command = YAMAHA_AVR_getParamName($hash, $a[2], $hash->{helper}{SCENES});
                    
                    if(defined($command) and length($command) > 0)
                    {
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Scene><Scene_Sel>".$command."</Scene_Sel></Scene></$zone></YAMAHA_AV>", $what, $a[2]);
                    }
                    else
                    {
                        return "invalid input: ".$a[2];
                    }
                }
                else
                {
                    return $usage;
                }
            }
            else
            {
                return "No scenes are avaible. Please try an statusUpdate.";
            }
        }
        else
        {
            return (($scenes_piped eq "") ? "No scenes are available. Please try an statusUpdate." : "No scene parameter was given");
        }
    }  
    elsif($what eq "mute" and defined($a[2]))
    {

        # Depending on the status response, use the short or long Volume command
        my $volume_cmd = (YAMAHA_AVR_isModel_DSP($hash) ? "Vol" : "Volume");
    
        if( $a[2] eq "on" or ($a[2] eq "toggle" and ReadingsVal($name, "mute", "off") eq "off"))
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Mute>On</Mute></$volume_cmd></$zone></YAMAHA_AV>", $what, "on");
        }
        elsif($a[2] eq "off" or ($a[2] eq "toggle" and ReadingsVal($name, "mute", "off") eq "on"))
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Mute>Off</Mute></$volume_cmd></$zone></YAMAHA_AV>", $what, "off"); 
        }
        else
        {
            return $usage;
        }
        
    }
    elsif($what =~ /^(volumeStraight|volume|volumeUp|volumeDown)$/)
    {
        my $target_volume;
        
        if($what eq "volume" and defined($a[2]) and $a[2] =~ /^\d{1,3}$/ and $a[2] >= 0 &&  $a[2] <= 100)
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs($a[2]);
        }
        elsif($what eq "volumeDown" and defined(ReadingsVal($name, "volume", undef)))
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs(ReadingsVal($name, "volume", -45) - ((defined($a[2]) and $a[2] =~ /^\d+$/) ? $a[2] : AttrVal($hash->{NAME}, "volumeSteps",5)));
        }
        elsif($what eq "volumeUp" and defined(ReadingsVal($name, "volume", undef)))
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs(ReadingsVal($name, "volume", -45) + ((defined($a[2]) and $a[2] =~ /^\d+$/) ? $a[2] : AttrVal($hash->{NAME}, "volumeSteps",5)));
        }
        elsif(defined($a[2]) and $a[2] =~ /^-?\d+(?:\.\d)?$/)
        {
            $target_volume = $a[2];
        }
        else
        {
            return $usage;
        }
        
        if($target_volume > YAMAHA_AVR_volume_rel2abs(AttrVal($name, "volumeMax","100")))
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs(AttrVal($name, "volumeMax","100"));
        }
         
        # if lower than minimum (-80.5) or higher than max (16.5) set target volume to the corresponding boundary
        $target_volume = -80.5 if(defined($target_volume) and $target_volume < -80.5);
        $target_volume = 16.5 if(defined($target_volume) and $target_volume > 16.5);
        
        Log3 $name, 4, "YAMAHA_AVR ($name) - new target volume: $target_volume";
        
        if(defined($target_volume))
        {
            # DSP based models use "Vol" instead of "Volume"
            my $volume_cmd = (YAMAHA_AVR_isModel_DSP($hash) ? "Vol" : "Volume");
            
            if(AttrVal($name, "volume-smooth-change", "1") eq "1")
            {
                my $steps = AttrVal($name, "volume-smooth-steps", 5);
                my $diff = int(($target_volume - ReadingsVal($name, "volumeStraight", $target_volume)) / $steps / 0.5) * 0.5;
                my $current_volume = ReadingsVal($name, "volumeStraight", undef); 

                if($diff > 0)
                {
                    Log3 $name, 4, "YAMAHA_AVR ($name) - use smooth volume change (with $steps steps of +$diff volume change to reach $target_volume)";
                }
                else
                {
                    Log3 $name, 4, "YAMAHA_AVR ($name) - use smooth volume change (with $steps steps of $diff volume change to reach $target_volume)";
                }
        
                # Only if a volume reading exists and smoohing is really needed (step difference is not zero)
                if(defined($current_volume) and $diff != 0 and not (defined($a[3]) and $a[3] eq "direct"))
                {        
                    Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".($current_volume + $diff)." dB (target is $target_volume dB)";
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".(($current_volume + $diff)*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", ($current_volume + $diff), {options => {volume_diff => $diff, volume_target => $target_volume}});
                }
                else
                {
                    # Set the desired volume
                    Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB";
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", $target_volume, {options => {volume_diff => $diff, volume_target => $target_volume}});
                }
            }
            else
            {
                # Set the desired volume
                Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB";
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", $target_volume, {options => {volume_diff => 0, volume_target => $target_volume}});
            }
        }
    }
    elsif($what eq "bass" and defined($a[2]))
    {
        my $bassVal = $a[2];
        if((exists($hash->{ACTIVE_ZONE})) && ($hash->{ACTIVE_ZONE} eq "mainzone"))
        {
            $bassVal = int($a[2]) if not (($a[2] =~ /^\d$/ ) || ($a[2] =~ /\.5/) || ($a[2] =~ /\.0/));
            $bassVal = -6 if($bassVal < -6);
            $bassVal = 6 if($bassVal > 6);
            
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Tone><Speaker><Bass><Cross_Over><Val>" . ReadingsVal($name,"bassCrossover","125") . "</Val><Exp>0</Exp><Unit>Hz</Unit></Cross_Over><Lvl><Val>" . $bassVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Bass></Speaker></Tone></$zone></YAMAHA_AV>", $what, $bassVal);
            }
            else
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Tone><Bass><Val>" . $bassVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Bass></Tone></Sound_Video></$zone></YAMAHA_AV>", $what, $bassVal);
            }
        }
        else
        {
            $bassVal = int($a[2]);

            $bassVal = -10 if($bassVal < -10);
            $bassVal = 10 if($bassVal > 10);
            
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Tone><Bass><Val>" . $bassVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Bass></Tone></$zone></YAMAHA_AV>", $what, $bassVal);
            }
            else
            {
                # step range is 2 dB for non DSP based models. add/subtract 1 if modulus 2 != 0
                $bassVal-- if(($bassVal % 2 != 0) && ($bassVal > 0));
                $bassVal++ if(($bassVal % 2 != 0) && ($bassVal < 0));
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Tone><Bass><Val>" . $bassVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Bass></Tone></Sound_Video></$zone></YAMAHA_AV>", $what, $bassVal);
            }
        }
    }
    elsif($what eq "treble" and defined($a[2]))
    {
        my $trebleVal = $a[2];
        if((exists($hash->{ACTIVE_ZONE})) && ($hash->{ACTIVE_ZONE} eq "mainzone"))
        {
            $trebleVal = int($a[2]) if not (($a[2] =~ /^\d$/ ) || ($a[2] =~ /\.5/) || ($a[2] =~ /\.0/));
            $trebleVal = -6 if($trebleVal < -6);
            $trebleVal = 6 if($trebleVal > 6);
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Tone><Speaker><Treble><Cross_Over><Val>" . ReadingsVal($name,"trebleCrossover","35") . "</Val><Exp>1</Exp><Unit>kHz</Unit></Cross_Over><Lvl><Val>" . $trebleVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Treble></Speaker></Tone></$zone></YAMAHA_AV>", $what, $trebleVal);
            }
            else
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Tone><Treble><Val>" . $trebleVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Treble></Tone></Sound_Video></$zone></YAMAHA_AV>", $what, $trebleVal);
            }
        }
        else
        {
            $trebleVal = int($trebleVal);
            $trebleVal = -10 if($trebleVal < -10);
            $trebleVal = 10 if($trebleVal > 10);
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Tone><Treble><Val>" . $trebleVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Treble></Tone></$zone></YAMAHA_AV>", $what, $trebleVal);
            }
            else
            {
                # step range is 2 dB for non DSP based models. add/subtract 1 if modulus 2 != 0
                $trebleVal-- if(($trebleVal % 2 != 0) && ($trebleVal > 0));
                $trebleVal++ if(($trebleVal % 2 != 0) && ($trebleVal < 0));
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Tone><Treble><Val>" . $trebleVal*10 . "</Val><Exp>1</Exp><Unit>dB</Unit></Treble></Tone></Sound_Video></$zone></YAMAHA_AV>", $what, $trebleVal);
            }
        }
    }
    elsif($what eq "dsp")
    {
        if(defined($a[2]))
        {
            if(not $dsp_modes_piped eq "")
            {
                if($a[2] =~ /^($dsp_modes_piped)$/)
                {
                    my $command = YAMAHA_AVR_getParamName($hash, $a[2],$hash->{helper}{DSP_MODES});
                    
                    if(defined($command) and length($command) > 0)
                    {
                        if(YAMAHA_AVR_isModel_DSP($hash))
                        {
                            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surr><Pgm_Sel><Pgm>$command</Pgm></Pgm_Sel></Surr></$zone></YAMAHA_AV>", $what, $a[2]);
                        }
                        else
                        {
                            my $straight_command = ((defined($hash->{MODEL}) && $hash->{MODEL} =~ /^RX-(?:A\d{1,2}00|V\d{1,2}67)$/) ? "<Straight>Off</Straight>" : "");
                            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current>$straight_command<Sound_Program>$command</Sound_Program></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
                        }
                    }
                    else
                    {
                        return "invalid dsp mode: ".$a[2];
                    }
                }
                else
                {
                    return $usage;
                }
            }
            else
            {
                return "No DSP presets are avaible. Please try an statusUpdate.";
            }
        }
        else
        {
            return (($dsp_modes_piped eq "") ? "No dsp presets are available. Please try an statusUpdate." : "No dsp preset was given");
        }
    }
    elsif($what eq "straight" and defined($a[2]))
    {
        if($a[2] eq "on")
        {
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surr><Pgm_Sel><Straight>On</Straight></Pgm_Sel></Surr></$zone></YAMAHA_AV>", $what, $a[2]);
            }
            else
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Straight>On</Straight></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
            }
        }
        elsif($a[2] eq "off")
        {
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surr><Pgm_Sel><Straight>Off</Straight></Pgm_Sel></Surr></$zone></YAMAHA_AV>", $what, $a[2]);
            }
            else
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Straight>Off</Straight></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
            }
        }
        else
        {
            return $usage;
        } 
    }
    elsif($what eq "3dCinemaDsp" and defined($a[2]))
    {  
        if($a[2] eq "auto")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><_3D_Cinema_DSP>Auto</_3D_Cinema_DSP></Surround></$zone></YAMAHA_AV>", "3dCinemaDsp", "auto");
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><_3D_Cinema_DSP>Off</_3D_Cinema_DSP></Surround></$zone></YAMAHA_AV>", "3dCinemaDsp", "off");
        }
        else
        {
            return $usage;
        }      
    }
    elsif($what eq "adaptiveDrc" and defined($a[2]))
    {    
        if($a[2] eq "auto")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Adaptive_DRC>Auto</Adaptive_DRC></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Adaptive_DRC>Off</Adaptive_DRC></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "enhancer" and defined($a[2]))
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Enhancer>On</Enhancer></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Enhancer>Off</Enhancer></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "direct" and defined($a[2]))
    {
        if(exists($hash->{helper}{DIRECT_TAG}))
        {                
            if($a[2] eq "on")
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><".$hash->{helper}{DIRECT_TAG}."><Mode>On</Mode></".$hash->{helper}{DIRECT_TAG}."></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
            }
            elsif($a[2] eq "off")
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><".$hash->{helper}{DIRECT_TAG}."><Mode>Off</Mode></".$hash->{helper}{DIRECT_TAG}."></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
            }
            else
            {
                return $usage;
            }  
        }
        else
        {
            return "Unable to execute \"$what ".$a[2]."\" - please execute a statusUpdate first before you use this command";
        } 
    }
    elsif($what eq "sleep" and defined($a[2]))
    {
        if($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>Off</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "30min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>30 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "60min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>60 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "90min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>90 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "120min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>120 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "last")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>Last</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        } 
    }
    elsif($what eq "remoteControl" and defined($a[2]))
    {
        # the RX-Vx71, RX-Vx73, RX-Ax10, RX-Ax20 series use a different tag name to access the remoteControl commands
        my $control_tag = (exists($hash->{MODEL}) and $hash->{MODEL} =~ /^RX-V\d{1,2}7(1|3)|RX-A\d{1,2}(1|2)0$/ ? "List_Control" : "Cursor_Control");
        
        if($a[2] eq "up")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Up</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "down")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Down</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "left")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Left</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "right")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Right</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "display")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Menu_Control>Display</Menu_Control></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "return")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Return</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "enter")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Sel</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "setup")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Menu_Control>On Screen</Menu_Control></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "option")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Menu_Control>Option</Menu_Control></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "tunerPresetUp")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><Preset_Sel>Up</Preset_Sel></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "tunerPresetDown")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><Preset_Sel>Down</Preset_Sel></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "play")
    {
         YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Playback>Play</Playback></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
    }
    elsif($what eq "stop")
    {
         YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Playback>Stop</Playback></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
    }
    elsif($what eq "pause")
    {
         YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Playback>Pause</Playback></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
    }
    elsif($what eq "navigateListMenu")
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus", {options => {no_playinfo => 1}});
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><[CURRENT_INPUT_TAG]><List_Info>GetParam</List_Info></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, join(" ", @a[2..$#a]), {options => {init => 1}});
    }
    elsif($what eq "preset" and $a[2] =~ /^\d+$/ and $a[2] >= 1 and $a[2] <= 40)
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus", {options => {no_playinfo => 1}});
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Preset><Preset_Sel>".$a[2]."</Preset_Sel></Preset></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2], {options => {can_fail => 1}});
    }
    elsif($what eq "presetUp")
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus", {options => {no_playinfo => 1}});
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Preset><Preset_Sel>Up</Preset_Sel></Preset></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2], {options => {can_fail => 1}});
    }
    elsif($what eq "presetDown")
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus", {options => {no_playinfo => 1}});
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Preset><Preset_Sel>Down</Preset_Sel></Preset></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2], {options => {can_fail => 1}});
    }
    elsif($what eq "skip" and defined($a[2]))
    {
        if($a[2] eq "forward")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Playback>Skip Fwd</Playback></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "reverse")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Playback>Skip Rev</Playback></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "shuffle" and defined($a[2]))
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Play_Mode><Shuffle>On</Shuffle></Play_Mode></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Play_Mode><Shuffle>Off</Shuffle></Play_Mode></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "repeat" and defined($a[2]))
    {
        if($a[2] eq "one")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Play_Mode><Repeat>One</Repeat></Play_Mode></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Play_Mode><Repeat>Off</Repeat></Play_Mode></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "all")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><Play_Control><Play_Mode><Repeat>All</Repeat></Play_Mode></Play_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "partyMode" and defined($a[2]))
    {
        if($hash->{helper}{SUPPORT_PARTY_MODE} and $hash->{ACTIVE_ZONE} eq "mainzone")
        {
            if($a[2] eq "on")
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><System><Party_Mode><Mode>On</Mode></Party_Mode></System></YAMAHA_AV>", $what, $a[2]);
            }
            elsif($a[2] eq "off")
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><System><Party_Mode><Mode>Off</Mode></Party_Mode></System></YAMAHA_AV>", $what, $a[2]);
            }
        }
        elsif($hash->{helper}{SUPPORT_PARTY_MODE} and $hash->{ACTIVE_ZONE} ne "mainzone")
        {
            if($a[2] eq "on")
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><System><Party_Mode><Target_Zone><$zone>Enable</$zone></Target_Zone></Party_Mode></System></YAMAHA_AV>", $what, $a[2]);
            }
            elsif($a[2] eq "off")
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><System><Party_Mode><Target_Zone><$zone>Disable</$zone></Target_Zone></Party_Mode></System></YAMAHA_AV>", $what, $a[2]);
            }
        }
    }
    elsif($what eq "tunerFrequency" and defined($a[2]))
    {
        if($a[2] =~ /^\d+(?:(?:\.|,)\d{1,2})?$/)
        {
            $a[2] =~ s/,/./;
            if((defined($a[3]) and $a[3] eq "AM" )) # AM Band 
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Tuning><Band>AM</Band><Freq><AM><Val>".$a[2]."</Val><Exp>0</Exp><Unit>kHz</Unit></AM></Freq></Tuning></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2], {options => {can_fail => 1}});
            }
            else # FM Band
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Tuning><Band>FM</Band><Freq><FM><Val>".($a[2] * 100)."</Val><Exp>2</Exp><Unit>MHz</Unit></FM></Freq></Tuning></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2], {options => {can_fail => 1}});
            }
        }
        else
        {
            return "invalid tuner frequency value: ".$a[2];
        }
    }
    elsif($what eq "surroundDecoder")
    {
        if(defined($a[2]))
        {
            if(not $decoders_piped eq "")
            {
                if($a[2] =~ /^($decoders_piped)$/)
                {
                    my $command = YAMAHA_AVR_getParamName($hash, $a[2],$hash->{helper}{SURROUND_DECODERS});
                    
                    if(defined($command) and length($command) > 0)
                    {
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Sound_Program_Param><SUR_DECODE><Decoder_Type>$command</Decoder_Type></SUR_DECODE></Sound_Program_Param></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
                    }
                    else
                    {
                        return "invalid surround decoder: ".$a[2];
                    }
                }
                else
                {
                    return $usage;
                }
            }
            else
            {
                return "No surround decoders are avaible. Please try an statusUpdate.";
            }
        }
        else
        {
            return (($decoders_piped eq "") ? "No surround decoders are available. Please try an statusUpdate." : "No surround decoder was given");
        }
    }
    elsif($what eq "displayBrightness")
    {
        if($a[2] =~ /^-?\d+$/ and $a[2] >= -4 and $a[2] <= 0)
        {
            if(YAMAHA_AVR_isModel_DSP($hash))
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><System><Display><FL><Dimmer><Val>".$a[2]."</Val><Exp>0</Exp><Unit></Unit></Dimmer></FL></Display></System></YAMAHA_AV>", $what, $a[2]);
            }
            else 
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><System><Misc><Display><FL><Dimmer>".$a[2]."</Dimmer></FL></Display></Misc></System></YAMAHA_AV>", $what, $a[2]);
            }
        }
        else
        {
            return "invalid tuner frequency value: ".$a[2];
        }
    }
    elsif($what eq "ypaoVolume" and defined($a[2]))
    {
        if($a[2] eq "auto")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><YPAO_Volume>Auto</YPAO_Volume></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><YPAO_Volume>Off</YPAO_Volume></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "extraBass" and defined($a[2]))
    {
        if($a[2] eq "auto")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Extra_Bass>Auto</Extra_Bass></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Extra_Bass>Off</Extra_Bass></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "hdmiOut1" and defined($a[2]))
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Sound_Video><HDMI><Output><OUT_1>On</OUT_1></Output></HDMI></Sound_Video></System></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Sound_Video><HDMI><Output><OUT_1>Off</OUT_1></Output></HDMI></Sound_Video></System></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "hdmiOut2" and defined($a[2]))
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Sound_Video><HDMI><Output><OUT_2>On</OUT_2></Output></HDMI></Sound_Video></System></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Sound_Video><HDMI><Output><OUT_2>Off</OUT_2></Output></HDMI></Sound_Video></System></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "statusRequest")
    {
        YAMAHA_AVR_GetStatus($hash, 1);
    }
    else
    {
        return $usage;
    } 
}

##########################
sub
YAMAHA_AVR_Attr(@)
{
    my ($cmd, $name, $attr, $val) = @_;
    
    my $hash = $defs{$name};

    return unless($hash);
    
    if($attr eq "disable")
    {
        # Start/Stop Timer according to new disabled-Value
        YAMAHA_AVR_ResetTimer($hash, 1);
    }
    
    if($cmd eq "set")
    {
        if($attr =~ /^(?:volumeMax|volumeSteps)$/)
        {
            if($val !~ /^\d+$/)
            {
                return "invalid attribute value for attribute $attr: $val";
            }
            
            if($attr eq "volumeMax" and ($val < 0 or $val > 100))
            {
                return "value is out of range (0-100) for attribute $attr: $val";
            }
            
            if($attr eq "volumeSteps" and ($val < 1))
            {
                return "value is out of range (1-*) for attribute $attr: $val";
            }
        }
    }
 

    return undef;
}

#############################
sub
YAMAHA_AVR_Undefine($$)
{
    my($hash, $name) = @_;

    # Stop all timers and exit
    RemoveInternalTimer($hash);
    
    if(exists($hash->{SYSTEM_ID}) and exists($hash->{ACTIVE_ZONE}) and exists($modules{YAMAHA_AVR}{defptr}{$hash->{SYSTEM_ID}}{$hash->{ACTIVE_ZONE}}))
    {
       delete($modules{YAMAHA_AVR}{defptr}{$hash->{SYSTEM_ID}}{$hash->{ACTIVE_ZONE}});
    }
    
    return undef;
}


############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

#
# Structure of a request hash
# ===========================
#
#   { 
#      data          => XML data to send without <?xml> prefix
#      cmd           => name of the command which is related to the request
#      arg           => optional argument related to the command and request
#      original_hash => $hash of the originating definition. must be set, if a zone definition sends a request via the mainzones command queue.
#      options       => optional values, see following list of possibilities.
#   }
#
# following option values can be used to control the execution of the command:
#
#   {
#      unless_in_queue     => don't insert the command if an equivalent command already exists in the queue. (flag: 0,1 - default: 0)
#      priority            => integer value of priority. lower values will be executed before higher values in the appropriate order. (integer value - default value: 3)
#      at_first            => insert the command at the beginning of the queue, not at the end. (flag: 0,1 - default: 0)
#      not_before          => don't execute the command before the given Unix timestamp is reached (integer/float value)
#      wait_after_response => wait the given number of seconds before processing further queue commands (integer/float value)
#      can_fail            => the request can return an error. If this flag is set, don't treat this as an communication error, ignore it instead. (flag: 0,1 - default: 0)
#      no_playinfo         => (only relevant for "statusRequest basicStatus") - don't retrieve extended playback information, after receiving a successful response (flag: 0,1 - default: 0)
#      init                => (only relevant for navigateListMenu) - marks the initial request to obtain the current menu level (flag: 0,1 - default: 0)
#      last_layer          => (only relevant for navigateListMenu) - the menu layer that was reached within the last request (integer value)
#      item_selected       => (only relevant for navigateListMenu) - is set, when the final item is going to be selected with the current request. (flag: 0,1 - default: 0)
#      volume_target       => (only relevant for volume) - the target volume, that should be reached by smoothing. (float value)
#      volume_diff         => (only relevant for volume) - the volume difference between each step to reach the target volume (float value)
#      input_tag           => (only relevant for "statusRequest playInfo") - contains the input tag name when requesting playInfo
#   }
#


#############################
# sends a command to the receiver via HTTP
sub
YAMAHA_AVR_SendCommand($$$$;$)
{
    my ($hash, $data,$cmd,$arg,$additional_args) = @_;
    my $name = $hash->{NAME};
    my $options;
    
    $data = "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data if($data);
    
    # In case any URL changes must be made, this part is separated in this function".
    
    my $param = {
                    data       => $data,
                    cmd        => $cmd,
                    arg        => $arg
                };     
    
    map {$param->{$_} = $additional_args->{$_}} keys %{$additional_args};
    
    $options = $additional_args->{options} if(exists($additional_args->{options}));
    
    my $device = $hash;
       
    # if device is not mainzone and mainzone is defined via defptr
    if(exists($hash->{SYSTEM_ID}) and exists($hash->{ACTIVE_ZONE}) and $hash->{ACTIVE_ZONE} ne "mainzone" and exists($modules{YAMAHA_AVR}{defptr}{$hash->{SYSTEM_ID}}{mainzone}))
    {
        $hash->{MAIN_ZONE} = $modules{YAMAHA_AVR}{defptr}{$hash->{SYSTEM_ID}}{mainzone}->{NAME};
        
        # DSP based models only: use the http queue from mainzone to execute command
        if(YAMAHA_AVR_isModel_DSP($hash))
        {
            $device = $modules{YAMAHA_AVR}{defptr}{$hash->{SYSTEM_ID}}{mainzone};

            $param->{original_hash} = $hash;
        }
    }
    else
    {
        delete($hash->{MAIN_ZONE}) if(exists($hash->{MAIN_ZONE}));
    }
    
    if($options->{unless_in_queue} and grep( ($_->{cmd} eq $cmd and ( (not(defined($arg) or defined($_->{arg}))) or  $_->{arg} eq $arg)) ,@{$device->{helper}{CMD_QUEUE}}))
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - comand \"$cmd".(defined($arg) ? " ".$arg : "")."\" is already in queue, skip adding another one";
    }
    else
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - append to queue ".($options->{at_first} ? "(at first) ":"")."of device ".$device->{NAME}." \"$cmd".(defined($arg) ? " ".$arg : "")."\": $data";
        
        if($options->{at_first})
        {
            unshift @{$device->{helper}{CMD_QUEUE}}, $param;  
        }
        else
        {
            push @{$device->{helper}{CMD_QUEUE}}, $param;  
        }
    }
    
    YAMAHA_AVR_HandleCmdQueue($device);
    
    return undef;
}

#############################
# starts http requests from cmd queue
sub
YAMAHA_AVR_HandleCmdQueue($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    
    if(not($hash->{helper}{RUNNING_REQUEST}) and @{$hash->{helper}{CMD_QUEUE}})
    {
        Log3 $name, 5, "YAMAHA_AVR ($name) - no commands currently running, but queue has pending commands. preparing new request";
        my $params =  {
                        url        => "http://".$address."/YamahaRemoteControl/ctrl",
                        timeout    => AttrVal($name, "request-timeout", 4),
                        noshutdown => 1, 
                        keepalive => 0,
                        httpversion => "1.1",
                        loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                        hash       => $hash,
                        callback   => \&YAMAHA_AVR_ParseResponse
                      };
   
        my $request = YAMAHA_AVR_getNextRequestHash($hash);

        unless(defined($request))
        {
            # still request in queue, but not mentioned to be executed now
            Log3 $name, 5, "YAMAHA_AVR ($name) - still requests in queue, but no command shall be executed at the moment. Retry in 1 second.";
            RemoveInternalTimer($hash, "YAMAHA_AVR_HandleCmdQueue");
            InternalTimer(gettimeofday()+1,"YAMAHA_AVR_HandleCmdQueue", $hash);
            return undef;
        }
        
        $request->{options}{priority} = 3 unless(exists($request->{options}{priority}));
        delete($request->{data}) if(exists($request->{data}) and !$request->{data});
        $request->{data}=~ s/\[CURRENT_INPUT_TAG\]/$hash->{helper}{CURRENT_INPUT_TAG}/g if(exists($request->{data}) and exists($hash->{helper}{CURRENT_INPUT_TAG}));

        
        map {$hash->{helper}{".HTTP_CONNECTION"}{$_} = $params->{$_}} keys %{$params};
        map {$hash->{helper}{".HTTP_CONNECTION"}{$_} = $request->{$_}} keys %{$request};
       
        $hash->{helper}{RUNNING_REQUEST} = 1;
        Log3 $name, 4, "YAMAHA_AVR ($name) - send command \"$request->{cmd}".(defined($request->{arg}) ? " ".$request->{arg} : "")."\"".(exists($request->{data}) ? ": ".$request->{data} : "");
        HttpUtils_NonblockingGet($hash->{helper}{".HTTP_CONNECTION"});
    }
    
    $hash->{CMDs_pending} = @{$hash->{helper}{CMD_QUEUE}};
    delete($hash->{CMDs_pending}) unless($hash->{CMDs_pending}); 
    
    return undef;
}

#############################
# selects the next command from command queue that has to be executed (undef if no command has to be executed now)
sub YAMAHA_AVR_getNextRequestHash($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if(@{$hash->{helper}{CMD_QUEUE}})
    {
        my $last = $#{$hash->{helper}{CMD_QUEUE}};
        
        my $next_item;
        my $next_item_prio;
        
        for my $item (0 .. $last)
        {
            my $param = $hash->{helper}{CMD_QUEUE}[$item];
            
            if(defined($param))
            {
                my $cmd = (defined($param->{cmd}) ? $param->{cmd} : "");
                my $arg = (defined($param->{arg}) ? $param->{arg} : "");
                my $data = (defined($param->{data}) ? "1" : "0");
                my $options = $param->{options};
                
                my $opt_not_before = (exists($options->{not_before}) ? sprintf("%.2fs", ($options->{not_before} - gettimeofday())): "0");
                my $opt_priority = (exists($options->{priority}) ? $options->{priority} : "-");
                my $opt_at_first = (exists($options->{at_first}) ? $options->{at_first} : "0");
                
                Log3 $name, 5, "YAMAHA_AVR ($name) - checking cmd queue item: $item (cmd: $cmd, arg: $arg, data: $data, priority: $opt_priority, at_first: $opt_at_first, not_before: $opt_not_before)";
            
                if(exists($param->{data}))
                {
                    if(defined($next_item) and ((defined($next_item_prio) and exists($options->{priority}) and  $options->{priority} < $next_item_prio) or (defined($options->{priority}) and not defined($next_item_prio))))
                    {
                        # choose actual item if priority of previous selected item is higher or not set
                        $next_item = $item;
                        $next_item_prio = $options->{priority};
                    }
            
                    unless((exists($options->{not_before}) and $options->{not_before} > gettimeofday()) or (defined($next_item)))
                    {
                        $next_item = $item;
                        $next_item_prio = $options->{priority};
                    }
                }
                else # dummy command to delay the execution of further commands in queue 
                {
                    if(exists($options->{not_before}) and $options->{not_before} <= gettimeofday() and not(defined($next_item)))
                    {
                        # if not_before timestamp of dummy item is reached, delete it and continue processing for next command
                        Log3 $name, 5, "YAMAHA_AVR ($name) - item $item is a dummy cmd item with 'not_before' set which is already expired, delete it and recheck index $item again";
                        splice(@{$hash->{helper}{CMD_QUEUE}}, $item, 1);
                        redo;
                    }
                    elsif(exists($options->{not_before}) and not(defined($next_item) and defined($next_item_prio)))
                    {
                        Log3 $name, 5, "YAMAHA_AVR ($name) - we have to wait ".sprintf("%.2fs", ($options->{not_before} - gettimeofday()))." seconds before next item can be checked"; 
                        last;
                    }
                }
            }
        }
        
        if(defined($next_item))
        {
            if(exists($hash->{helper}{CMD_QUEUE}[$next_item]{options}{not_before}))
            {
                delete($hash->{helper}{CMD_QUEUE}[$next_item]{options}{not_before});
            }
        
            my $return = $hash->{helper}{CMD_QUEUE}[$next_item];
            
            splice(@{$hash->{helper}{CMD_QUEUE}}, $next_item, 1);
            $hash->{helper}{CMD_QUEUE} = () unless(defined($hash->{helper}{CMD_QUEUE}));
            
            Log3 $name, 5, "YAMAHA_AVR ($name) - choosed item $next_item as next command";
            return $return;
        }
        
        Log3 $name, 5, "YAMAHA_AVR ($name) - no suitable command item found";
        return undef;
    }
}

#############################
# parses the receiver response
sub
YAMAHA_AVR_ParseResponse($$$)
{
    my ( $param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $queue_hash = $param->{hash};

    my $cmd = $param->{cmd};
    my $arg = $param->{arg};
    my $options = $param->{options};

    $data = "" unless(defined($data));
    $err = "" unless(defined($err));
    
    $hash->{helper}{RUNNING_REQUEST} = 0;
    delete($hash->{helper}{".HTTP_CONNECTION"}) unless($param->{keepalive});
    
    # if request is from an other definition (zone2, zone3, ...)
    $hash = $param->{original_hash} if(exists($param->{original_hash}));

    my $name = $hash->{NAME};
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    if(exists($param->{code}))
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - received HTTP code ".$param->{code}." for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
        
        if($cmd eq "statusRequest" and $param->{code} ne "200")
        {
            if($arg eq "playShuffle")
            {
                $hash->{helper}{SUPPORT_SHUFFLE_REPEAT} = 0;
            }
            elsif($arg eq "toneStatus")
            {
                $hash->{helper}{SUPPORT_TONE_STATUS} = 0;
            }
            elsif($arg eq "partyModeStatus" or $arg eq "partyModeZones")
            {
                $hash->{helper}{SUPPORT_PARTY_MODE} = 0;
            }
            elsif($arg eq "surroundDecoder")
            {
                $hash->{helper}{SUPPORT_SURROUND_DECODER} = 0;
            }
            elsif($arg eq "displayBrightness")
            {
                $hash->{helper}{SUPPORT_DISPLAY_BRIGHTNESS} = 0;
            }
            elsif($arg eq "hdmiOut1" or $arg eq "hdmiOut2")
            {
                $hash->{helper}{SUPPORT_HDMI_OUT} = 0;
            }
        }
    }
    
    if($err ne "" and not $options->{can_fail})
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $err";

        if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1))
        {
            Log3 $name, 3, "YAMAHA_AVR ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
            readingsSingleUpdate($hash, "presence", "absent", 1);
            readingsSingleUpdate($hash, "state", "absent", 1);
        }  

        $hash->{helper}{AVAILABLE} = 0;
    }
    
    if($data ne "")
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - got response for \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $data";
    
         # add a dummy queue entry to wait a specific time before next command starts
        if($options->{wait_after_response})
        {
            Log3 $name, 5, "YAMAHA_AVR ($name) - next command for device ".$queue_hash->{NAME}." has to wait at least ".$options->{wait_after_response}." seconds before execution";
            unshift @{$queue_hash->{helper}{CMD_QUEUE}}, {options=> { priority => 1, not_before => (gettimeofday()+$options->{wait_after_response})} };
        }
        
        if(defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
        {
            Log3 $name, 3, "YAMAHA_AVR ($name) - device $name reappeared";
            readingsSingleUpdate($hash, "presence", "present", 1); 
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus", {options => {at_first => 1}}) if(defined($zone));
        }
        
        $hash->{helper}{AVAILABLE} = 1;
        
        if(not $data =~ / RC="0"/ and $data =~ / RC="(\d+)"/ and not $options->{can_fail})
        {
            # if the returncode isn't 0, than the command was not successful
            Log3 $name, 3, "YAMAHA_AVR ($name) - Could not execute \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": received return code $1";
        }
        
        readingsBeginUpdate($hash);
        
        if($cmd eq "statusRequest")
        {
            if($arg eq "unitDescription")
            {
                if($data =~ /<URL>(.+?)<\/URL>/)
                { 
                    $hash->{helper}{XML} = $1;
                }
                else
                {
                    $hash->{helper}{XML} = "/YamahaRemoteControl/desc.xml";
                }
                
                Log3 $name, 5, "YAMAHA_AVR ($name) - requesting unit description XML: http://".$hash->{helper}{ADDRESS}.$hash->{helper}{XML};
                
               YAMAHA_AVR_SendCommand($hash,0,"statusRequest","retrieveDescXML", {
                                                                                    url        => "http://".$hash->{helper}{ADDRESS}.$hash->{helper}{XML} ,
                                                                                    callback   => \&YAMAHA_AVR_ParseXML,
                                                                                    options    => {priority => 2}
                                                                                 });
            }
            elsif($arg eq "systemConfig")
            {
                if($data =~ /<Model_Name>(.+?)<\/Model_Name>.*?<System_ID>(.+?)<\/System_ID>.*?<Version>.*?<Main>(.+?)<\/Main>.*?<Sub>(.+?)<\/Sub>.*?<\/Version>/) # DSP based models
                {
                    $hash->{MODEL} = $1;
                    $hash->{SYSTEM_ID} = $2;
                    $hash->{FIRMWARE} = $3."  ".$4;
                }
                elsif($data =~ /<Model_Name>(.+?)<\/Model_Name>.*?<System_ID>(.+?)<\/System_ID>.*?<Version>(.+?)<\/Version>/)
                {
                    $hash->{MODEL} = $1;
                    $hash->{SYSTEM_ID} = $2;
                    $hash->{FIRMWARE} = $3;
                }
                
                $attr{$name}{"model"} = $hash->{MODEL};
            }
            elsif($arg eq "getInputs")
            {
                delete($hash->{helper}{INPUTS}) if(exists($hash->{helper}{INPUTS}));

                while($data =~ /<Param>(.+?)<\/Param>/gc)
                {
                    if(defined($hash->{helper}{INPUTS}) and length($hash->{helper}{INPUTS}) > 0)
                    {
                        $hash->{helper}{INPUTS} .= "|";
                    }
                    Log3 $name, 4, "YAMAHA_AVR ($name) - found input: $1";
                    $hash->{helper}{INPUTS} .= $1;
                }
                
                $hash->{helper}{INPUTS} = join("|", sort split("\\|", $hash->{helper}{INPUTS}));  
            }
            elsif($arg eq "getScenes")
            {
                delete($hash->{helper}{SCENES}) if(exists($hash->{helper}{SCENES}));
             
                # get all available scenes from response
                while($data =~ /<Item_\d+>.*?<Param>(.+?)<\/Param>.*?<RW>(\w+)<\/RW>.*?<\/Item_\d+>/gc)
                {
                  # check if the RW-value is "W" (means: writeable => can be set through FHEM)
                    if($2 eq "W")
                    {
                        if(defined($hash->{helper}{SCENES}) and length($hash->{helper}{SCENES}) > 0)
                        {
                            $hash->{helper}{SCENES} .= "|";
                        }
                        Log3 $name, 4, "YAMAHA_AVR ($name) - found scene: $1";
                        $hash->{helper}{SCENES} .= $1;
                    }
                }
            }
            elsif($arg eq "partyModeStatus")
            {            
                if($hash->{ACTIVE_ZONE} eq "mainzone" and $data =~ /<Mode>(.+?)<\/Mode>/)
                {
                    $hash->{helper}{SUPPORT_PARTY_MODE} = 1;
                    readingsBulkUpdate($hash, "partyMode", lc($1));
                }
                else
                {
                    $hash->{helper}{SUPPORT_PARTY_MODE} = 0;
                }
            }  
            elsif($arg eq "partyModeZones")
            {
                if($hash->{ACTIVE_ZONE} ne "mainzone" and $data =~ /<Target_Zone>.*?<$zone>(.+?)<\/$zone>.*?<\/Target_Zone>/)
                {
                    $hash->{helper}{SUPPORT_PARTY_MODE} = 1;
                    
                    if($1 eq "Enable")
                    {
                        readingsBulkUpdate($hash, "partyModeStatus", "on");  
                    
                    }
                    elsif($1 eq "Disable")
                    {
                        readingsBulkUpdate($hash, "partyModeStatus", "off");  
                    }
                }
                else
                {
                    $hash->{helper}{SUPPORT_PARTY_MODE} = 0;
                }
            }
            elsif($arg eq "toneStatus")
            {
                if(($data =~ /<Tone><Speaker><Bass><Cross_Over><Val>(.+?)<\/Val><Exp>.*?<\/Exp><Unit>.*?<\/Unit><\/Cross_Over><Lvl><Val>(.+?)<\/Val>.*?<\/Lvl><\/Bass><\/Speaker><\/Tone>/) or ($data =~ /<Tone><Bass><Val>(.+?)<\/Val><Exp>1<\/Exp><Unit>dB<\/Unit><\/Bass><\/Tone>/))
                {
                    $hash->{helper}{SUPPORT_TONE_STATUS} = 1;
                    
                    if((exists($hash->{ACTIVE_ZONE})) && ($hash->{ACTIVE_ZONE} eq "mainzone"))
                    {
                        if(defined($2))
                        {
                            readingsBulkUpdate($hash, "bass", int($2)/10);
                            readingsBulkUpdate($hash, "bassCrossover", lc($1));
                        }
                        else
                        {
                            readingsBulkUpdate($hash, "bass", int($1)/10);
                        }
                    }
                    else
                    { 
                        readingsBulkUpdate($hash, "bass", int($1)/10);
                    }
                }
                elsif(($data =~ /<Tone><Speaker><Treble><Cross_Over><Val>(.+?)<\/Val><Exp>.*?<\/Exp><Unit>.*?<\/Unit><\/Cross_Over><Lvl><Val>(.+?)<\/Val>.*?<\/Lvl><\/Treble><\/Speaker><\/Tone>/) or ($data =~ /<Tone><Treble><Val>(.+?)<\/Val><Exp>1<\/Exp><Unit>dB<\/Unit><\/Treble><\/Tone>/))
                {
                    $hash->{helper}{SUPPORT_TONE_STATUS} = 1;
                    
                    if((exists($hash->{ACTIVE_ZONE})) && ($hash->{ACTIVE_ZONE} eq "mainzone"))
                    {
                        if(defined($2))
                        {
                            readingsBulkUpdate($hash, "treble", int($2)/10);
                            readingsBulkUpdate($hash, "trebleCrossover", lc($1));
                        }
                        else
                        {
                            readingsBulkUpdate($hash, "treble", int($1)/10);
                        }
                    }
                    else
                    {
                        readingsBulkUpdate($hash, "treble", int($1)/10);
                    }
                }
                else
                {
                    $hash->{helper}{SUPPORT_TONE_STATUS} = 0;
                }
            }
            elsif($arg eq "basicStatus")
            {
                if($data =~ /<Power>(.+?)<\/Power>/)
                {
                    my $power = $1;
                   
                    if($power eq "Standby")
                    {    
                        $power = "off";
                    }
                    readingsBulkUpdate($hash, "power", lc($power));
                    readingsBulkUpdate($hash, "state", lc($power));
                }
                
                # current volume and mute status
                if($data =~ /<Volume><Lvl><Val>(.+?)<\/Val><Exp>(.+?)<\/Exp><Unit>.+?<\/Unit><\/Lvl><Mute>(.+?)<\/Mute>.*?<\/Volume>/)
                {
                    readingsBulkUpdate($hash, "volumeStraight", ($1 / 10 ** $2));
                    readingsBulkUpdate($hash, "volume", YAMAHA_AVR_volume_abs2rel(($1 / 10 ** $2)));
                    readingsBulkUpdate($hash, "mute", lc($3));
                }
                elsif($data =~ /<Vol><Lvl><Val>(.+?)<\/Val><Exp>(.+?)<\/Exp><Unit>.+?<\/Unit><\/Lvl><Mute>(.+?)<\/Mute>.*?<\/Vol>/) # DSP based models
                {
                    readingsBulkUpdate($hash, "volumeStraight", ($1 / 10 ** $2));
                    readingsBulkUpdate($hash, "volume", YAMAHA_AVR_volume_abs2rel(($1 / 10 ** $2)));
                    readingsBulkUpdate($hash, "mute", lc($3));
                }
                
                # (only available in zones other than mainzone) absolute or relative volume change to the mainzone
                if($data =~ /<Volume>.*?<Output>(.+?)<\/Output>.*?<\/Volume>/)
                {
                    readingsBulkUpdate($hash, "output", lc($1));
                }
                elsif($data =~ /<Vol>.*?<Output>(.+?)<\/Output>.*?<\/Vol>/) # DSP based models
                {
                    readingsBulkUpdate($hash, "output", lc($1));
                }
                else
                {
                    # delete the reading if this information is not available
                    delete($hash->{READINGS}{output}) if(exists($hash->{READINGS}{output}));
                }
                
                # current input same as the corresponding set command name
                if($data =~ /<Input_Sel>(.+?)<\/Input_Sel>/)
                {
                    readingsBulkUpdate($hash, "input", YAMAHA_AVR_Param2Fhem(lc($1), 0));
                    
                    if($data =~ /<Power>On<\/Power>/ and $data =~ /<Src_Name>(.+?)<\/Src_Name>/)
                    {
                        $hash->{helper}{LAST_INPUT_TAG} = $hash->{helper}{CURRENT_INPUT_TAG} if(exists($hash->{helper}{CURRENT_INPUT_TAG}));
                        $hash->{helper}{CURRENT_INPUT_TAG} = $1;
                        
                        unless($options->{no_playinfo})
                        {
                            Log3 $name, 4, "YAMAHA_AVR ($name) - check for extended input informations on <$1>";
                        
                            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$1><Play_Info>GetParam</Play_Info></$1></YAMAHA_AV>", "statusRequest", "playInfo", {options => {can_fail => 1, input_tag => $1}});
                            
                            if(!exists($hash->{helper}{LAST_INPUT_TAG}) or ($hash->{helper}{LAST_INPUT_TAG} ne $hash->{helper}{CURRENT_INPUT_TAG}) or $hash->{helper}{SUPPORT_SHUFFLE_REPEAT})
                            {
                                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$1><Play_Control><Play_Mode><Repeat>GetParam</Repeat></Play_Mode></Play_Control></$1></YAMAHA_AV>", "statusRequest", "playRepeat", {options => {can_fail => 1}});
                                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$1><Play_Control><Play_Mode><Shuffle>GetParam</Shuffle></Play_Mode></Play_Control></$1></YAMAHA_AV>", "statusRequest", "playShuffle", {options => {can_fail => 1}});
                            }
                        }
                        else
                        {
                            Log3 $name, 4, "YAMAHA_AVR ($name) - skipping check for extended input informations on <$1>";
                        }
                    }
                    else
                    {
                        delete($hash->{helper}{CURRENT_INPUT_TAG}) if(exists($hash->{helper}{CURRENT_INPUT_TAG}));
                        delete($hash->{helper}{LAST_INPUT_TAG}) if(exists($hash->{helper}{LAST_INPUT_TAG}));
                        $hash->{helper}{SUPPORT_SHUFFLE_REPEAT} = 0;
                        readingsBulkUpdateIfChanged($hash, "currentAlbum", "");
                        readingsBulkUpdateIfChanged($hash, "currentTitle", "");
                        readingsBulkUpdateIfChanged($hash, "currentChannel", "");
                        readingsBulkUpdateIfChanged($hash, "currentStation", "");
                        readingsBulkUpdateIfChanged($hash, "currentStationFrequency","");
                        readingsBulkUpdateIfChanged($hash, "currentArtist", "");
                        readingsBulkUpdateIfChanged($hash, "playStatus", "stopped");
                    }
                }
                
                # input name as it is displayed on the receivers front display
                if($data =~ /<Input>.*?<Title>\s*(.+?)\s*<\/Title>.*?<\/Input>/)
                {
                    readingsBulkUpdate($hash, "inputName", $1);
                }
                elsif($data =~ /<Input>.*?<Input_Sel_Title>\s*(.+?)\s*<\/Input_Sel_Title>.*?<\/Input>/)
                {
                    readingsBulkUpdate($hash, "inputName", $1);
                }
                
                if($data =~ /<Surround>.*?<Current>.*?<Straight>(.+?)<\/Straight>.*?<\/Current>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "straight", lc($1));
                }
                elsif($data =~ /<Surr>.*?<Straight>(.+?)<\/Straight>.*?<\/Surr>/) # DSP-Z based models
                {
                    readingsBulkUpdate($hash, "straight", lc($1));
                }
                
                if($data =~ /<Surround>.*?<Current>.*?<Enhancer>(.+?)<\/Enhancer>.*?<\/Current>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "enhancer", lc($1));
                }
                
                if($data =~ /<Surround>.*?<Current>.*?<Sound_Program>(.+?)<\/Sound_Program>.*?<\/Current>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "dsp", YAMAHA_AVR_Param2Fhem($1, 0));
                }
                elsif($data =~ /<Surr>.*?<Pgm>(.+?)<\/Pgm>.*?<\/Surr>/) # DSP-Z based models
                {
                    readingsBulkUpdate($hash, "dsp", YAMAHA_AVR_Param2Fhem($1, 0));
                }
               
                if($data =~ /<Surround>.*?<_3D_Cinema_DSP>(.+?)<\/_3D_Cinema_DSP>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "3dCinemaDsp", lc($1));
                }
                
                if($data =~ /<Sound_Video>.*?<Adaptive_DRC>(.+?)<\/Adaptive_DRC>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "adaptiveDrc", lc($1));
                }
                
                if($data =~ /<Power_Control>.*?<Sleep>(.+?)<\/Sleep>.*?<\/Power_Control>/)
                {
                    readingsBulkUpdate($hash, "sleep", YAMAHA_AVR_Param2Fhem($1, 0));
                }
                
                if($data =~ /<Sound_Video>.*?<Direct>.*?<Mode>(.+?)<\/Mode>.*?<\/Direct>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "direct", lc($1));
                    $hash->{helper}{DIRECT_TAG} = "Direct"; 
                }
                elsif($data =~ /<Sound_Video>.*?<Pure_Direct>.*?<Mode>(.+?)<\/Mode>.*?<\/Pure_Direct>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "direct", lc($1));
                    $hash->{helper}{DIRECT_TAG} = "Pure_Direct";
                }
                else
                {
                    delete($hash->{helper}{DIRECT_TAG}) if(exists($hash->{helper}{DIRECT_TAG}));
                }
                
                if($data =~ /<Sound_Video>.*?<YPAO_Volume>(.+?)<\/YPAO_Volume>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "ypaoVolume", lc($1));
                    $hash->{helper}{SUPPORT_YPAO_VOLUME} = 1;
                }
                else
                {
                    $hash->{helper}{SUPPORT_YPAO_VOLUME} = 0;
                }

                if($data =~ /<Sound_Video>.*?<Extra_Bass>(.+?)<\/Extra_Bass>.*?<\/Sound_Video>/)
                {
                    $hash->{helper}{SUPPORT_EXTRA_BASS} = 1;
                    readingsBulkUpdate($hash, "extraBass", lc($1));
                }
                else
                {
                    $hash->{helper}{SUPPORT_EXTRA_BASS} = 0;
                }
            }
            elsif($arg eq "playInfo")
            {
                if($data =~ /<Meta_Info>.*?<Artist>(.+?)<\/Artist>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentArtist", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdateIfChanged($hash, "currentArtist", "");
                }

                if($data =~ /<Meta_Info>.*?<Station>(.+?)<\/Station>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentStation", YAMAHA_AVR_html2txt($1));
                }
                elsif($data =~ /<Meta_Info>.*?<Program_Service>(.+?)<\/Program_Service>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentStation", YAMAHA_AVR_html2txt($1));
                }
                elsif($data =~ /<Meta_Info>.*?<DAB>.*?<Service_Label>(.+?)<\/Service_Label>.*?<\/DAB>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentStation", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdateIfChanged($hash, "currentStation", "");
                }  
                
                if($data =~ /<Meta_Info>.*?<Channel>(.+?)<\/Channel>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentChannel", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdateIfChanged($hash, "currentChannel", "");
                }
                
                if($data =~ /<Meta_Info>.*?<Album>(.+?)<\/Album>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentAlbum", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdateIfChanged($hash, "currentAlbum", "");
                }
                
                if($data =~ /<Meta_Info>.*?<Song>(.+?)<\/Song>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1));
                }
                elsif($data =~ /<Meta_Info>.*?<Track>(.+?)<\/Track>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1));
                }
                elsif($data =~ /<Meta_Info>.*?<Radio_Text_A>(.+?)<\/Radio_Text_A>.*?<\/Meta_Info>/)    
                {        
                    my $tmp = $1;
                    
                    if($data =~ /<Meta_Info>.*?<Radio_Text_A>(.+?)<\/Radio_Text_A>.*?<Radio_Text_B>(.+?)<\/Radio_Text_B>.*?<\/Meta_Info>/)    
                    {                                                                   
                        readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt(trim($1)." ".trim($2)));        
                    }    
                    else
                    {
                        readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($tmp));        
                    }
                }    
                elsif($data =~ /<Meta_Info>.*?<Radio_Text_B>(.+?)<\/Radio_Text_B>.*?<\/Meta_Info>/)    
                {         
                    readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1));        
                }    
                elsif($data =~ /<DAB>.*?<DLS>(.+?)<\/DLS>.*?<\/DAB>/)
                {         
                    readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1));        
                } 
                else
                {
                    readingsBulkUpdateIfChanged($hash, "currentTitle", "");
                }

                if($data =~ /<Playback_Info>(.+?)<\/Playback_Info>/)
                {
                    readingsBulkUpdate($hash, "playStatus", "stopped") if($1 eq "Stop");
                    readingsBulkUpdate($hash, "playStatus", "playing") if($1 eq "Play");
                    readingsBulkUpdate($hash, "playStatus", "paused") if($1 eq "Pause");
                }
                elsif($options->{input_tag} eq "Tuner")
                {
                    readingsBulkUpdate($hash, "playStatus", "playing");
                }
                
                if($data =~ /<Tuning>.*?<Freq>(?:<Current>)?<Val>(\d+?)<\/Val><Exp>(\d+?)<\/Exp><Unit>(.*?)<\/Unit>(?:<\/Current>)?.*<\/Tuning>/ or (YAMAHA_AVR_isModel_DSP($hash) and $data =~ /<Tuning>.*?<Freq><Val>(\d+?)<\/Val><Exp>(\d+?)<\/Exp><Unit>(.*?)<\/Unit><\/Freq>.*?<\/Tuning>/))
                {
                    readingsBulkUpdate($hash, "currentStationFrequency", sprintf("%.$2f", ($1 / (10 ** $2)))." $3");
                    readingsBulkUpdate($hash, "tunerFrequency", sprintf("%.$2f", ($1 / (10 ** $2))));
                    
                    if($data =~ /<Tuning>.*?<Band>(.+?)<\/Band>.*?<\/Tuning>/)
                    {
                        readingsBulkUpdate($hash, "tunerFrequencyBand", uc($1));
                    }
                }
                elsif(ReadingsVal($name, "currentStationFrequency", "") ne "")
                {
                    readingsBulkUpdateIfChanged($hash, "currentStationFrequency","");
                }
            }
            elsif($arg eq "playShuffle")
            {
                if($data =~ /<Shuffle>(.+?)<\/Shuffle>/)
                {
                    $hash->{helper}{SUPPORT_SHUFFLE_REPEAT} = 1;
                    readingsBulkUpdate($hash, "shuffle", lc($1));
                }
            }
            elsif($arg eq "playRepeat")
            {
                if($data =~ /<Repeat>(.+?)<\/Repeat>/)
                {
                    $hash->{helper}{SUPPORT_SHUFFLE_REPEAT} = 1;
                    readingsBulkUpdate($hash, "repeat", lc($1));
                }
            }
            elsif($arg eq "fwUpdate")
            {
                if($data =~ /<Status>(.+?)<\/Status>/)
                {
                    readingsBulkUpdate($hash, "newFirmware", lc($1));
                }
            }
            elsif($arg eq "tunerFrequency")
            {
                if($data =~ /<Tuning>.*?<Band>(.+?)<\/Band>.*?<\/Tuning>/)
                {
                    readingsBulkUpdate($hash, "tunerFrequencyBand", uc($1));
                }
                
                if($data =~ /<Tuning>.*?<Freq><Current><Val>(\d+?)<\/Val><Exp>(\d+?)<\/Exp><Unit>(.*?)<\/Unit><\/Current>.*?<\/Tuning>/ or (YAMAHA_AVR_isModel_DSP($hash) and $data =~ /<Tuning>.*?<Freq><Val>(\d+?)<\/Val><Exp>(\d+?)<\/Exp><Unit>(.*?)<\/Unit><\/Freq>.*?<\/Tuning>/))
                {
                    readingsBulkUpdate($hash, "tunerFrequency", sprintf("%.$2f", ($1 / (10 ** $2))));
                }    
            }
            elsif($arg eq "surroundDecoder")
            {
                if($data =~ /<Decoder_Type>(.+?)<\/Decoder_Type>/)
                {
                    $hash->{helper}{SUPPORT_SURROUND_DECODER} = 1;
                    readingsBulkUpdate($hash, "surroundDecoder", YAMAHA_AVR_Param2Fhem($1, 0));
                    $hash->{helper}{SURROUND_DECODERS} = YAMAHA_AVR_generateSurroundDecoderList($hash) unless($hash->{helper}{SURROUND_DECODERS});
                }
                elsif($data =~ /RC="2"/) # is not supported by this specific model
                {
                    $hash->{helper}{SUPPORT_SURROUND_DECODER} = 0;
                }
            }
            elsif($arg eq "displayBrightness")
            {
                if($data =~ /<Dimmer>(.+?)<\/Dimmer>/ or (YAMAHA_AVR_isModel_DSP($hash) and $data =~ /<Val>(.+?)<\/Val>/))
                {
                    $hash->{helper}{SUPPORT_DISPLAY_BRIGHTNESS} = 1;
                    readingsBulkUpdate($hash, "displayBrightness", $1);
                }
                elsif($data =~ /RC="2"/) # is not supported by this specific model
                {
                    $hash->{helper}{SUPPORT_DISPLAY_BRIGHTNESS} = 0;
                }
            }
            elsif($arg eq "hdmiOut1")
            {
                if($data =~ /<OUT_1>(.+?)<\/OUT_1>/)
                {
                    readingsBulkUpdate($hash, "hdmiOut1", lc($1));
                }
                elsif($data =~ /RC="2"/) # is not supported by this specific model
                {
                    $hash->{helper}{SUPPORT_HDMI_OUT} = 0;
                }
            }
            elsif($arg eq "hdmiOut2")
            {
                if($data =~ /<OUT_2>(.+?)<\/OUT_2>/)
                {
                    readingsBulkUpdate($hash, "hdmiOut2", lc($1));
                }
                elsif($data =~ /RC="2"/) # is not supported by this specific model
                {
                    $hash->{helper}{SUPPORT_HDMI_OUT} = 0;
                }
            }
        }
        elsif($cmd eq "on")
        {
            if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
            {
                readingsBulkUpdate($hash, "power", "on");
                readingsBulkUpdate($hash, "state","on");
            }
        }
        elsif($cmd eq "off")
        {
            if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
            {
                readingsBulkUpdate($hash, "power", "off");
                readingsBulkUpdate($hash, "state","off");
            }
        }
        elsif($cmd eq "navigateListMenu")
        {
            my @list_cmds = split("/", $arg);
            
            if($data =~ /<Menu_Layer>(.+?)<\/Menu_Layer><Menu_Name>(.*?)<\/Menu_Name><Current_List>(.+?)<\/Current_List><Cursor_Position><Current_Line>(\d+)<\/Current_Line><Max_Line>(\d+)<\/Max_Line><\/Cursor_Position>/)
            {
               
                my $menu_layer = $1;
                my $menu_name = $2;
                my $current_list = $3;
                my $current_line = $4;
                my $max_line = $5;
                
                my $menu_status = "Ready"; # RX-Vx71's based series models does not provide <Menu_Status> so "Ready" must be assumed
                
                # but check, if <Menu_Status> is provided. Is that so, use the provided value
                if($data =~ /<Menu_Status>(.+?)<\/Menu_Status>/)
                {
                    $menu_status = $1;
                }
                
                my $last = ($options->{last_menu_item} or ($menu_layer == ($#list_cmds + 1)));

                if($menu_status eq "Ready")
                {               
                    # menu browsing finished
                    if(exists($options->{last_layer}) and $options->{last_layer} == $menu_layer and $last and $options->{item_selected})
                    {
                        Log3 $name, 5 ,"YAMAHA_AVR ($name) - menu browsing to $arg is finished. requesting basic status";
                        readingsEndUpdate($hash, 1);
                        YAMAHA_AVR_GetStatus($hash, 1);
                        return undef;
                    }
                    
                    # initialization sequence
                    if($options->{init} and $menu_layer > 1)
                    {
                        Log3 $name, 5 ,"YAMAHA_AVR ($name) - return to start of menu to begin menu browsing";
                        
                        # RX-Vx71's series models and older use a different command to return back to menu root                       
                        my $back_cmd = ((exists($hash->{MODEL}) and $hash->{MODEL} =~ /^(?:RX-A\d{1,2}10|RX-A\d{1,2}00|RX-V\d{1,2}(?:71|67|65))$/) ? "Back to Home" : "Return to Home");
                        
                        YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><List_Control><Cursor>$back_cmd</Cursor></List_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg);
                        YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"GET\"><[CURRENT_INPUT_TAG]><List_Info>GetParam</List_Info></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg,  {options => {init => 1}});

                        readingsEndUpdate($hash, 1);
                        YAMAHA_AVR_HandleCmdQueue($queue_hash);
                        return;
                    }
                    
                    if($menu_layer > @list_cmds)
                    {
                        # menu is still not browsed fully, but no more commands are left.
                        Log3 $name, 5 ,"YAMAHA_AVR ($name) - no more commands left to browse deeper into current menu.";
                    }
                    else # browse through the current item list
                    {
                        my $search = $list_cmds[($menu_layer - 1)];
                        
                        if($current_list =~ /<Line_(\d+)><Txt>([^<]*$search[^<]*)<\/Txt><Attribute>(.+?)<\/Attribute>/)
                        {
                            my $last = ($3 eq "Item");                       
                            my $absolute_line_number = $1 + int($current_line / 8) * 8;
                            
                            Log3 $name, 5 ,"YAMAHA_AVR ($name) - selecting menu item \"$2\" (line item: $1, absolute number: $absolute_line_number)";
                            
                            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><List_Control><Jump_Line>$absolute_line_number</Jump_Line></List_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg);
                            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><List_Control><Direct_Sel>Line_$1</Direct_Sel></List_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg);
                            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"GET\"><[CURRENT_INPUT_TAG]><List_Info>GetParam</List_Info></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg, {options => {last_layer => $menu_layer, item_selected => 1, last_menu_item => $last, not_before => gettimeofday()+1}});
                        }
                        else
                        {
                            if(($current_line + 8) < $max_line)
                            {
                                #request next page
                                Log3 $name, 5 ,"YAMAHA_AVR ($name) - request next page of menu (current line: $current_line, max lines: $max_line)";
                                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><[CURRENT_INPUT_TAG]><List_Control><Page>Down</Page></List_Control></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg);
                                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"GET\"><[CURRENT_INPUT_TAG]><List_Info>GetParam</List_Info></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg, {options => {not_before => gettimeofday()+1}});
                            }
                            else
                            {
                                Log3 $name, 3 ,"YAMAHA_AVR ($name) - no more pages left on menu to find item $search in $menu_name. aborting menu browsing";
                            }
                        }
                    }
                }
                else
                {
                    # list must be checked again in 1 second.
                    Log3 $name, 5 ,"YAMAHA_AVR ($name) - menu is busy. retrying in 1 second";
                    YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"GET\"><[CURRENT_INPUT_TAG]><List_Info>GetParam</List_Info></[CURRENT_INPUT_TAG]></YAMAHA_AV>", $cmd, $arg, {options => {not_before => (gettimeofday()+1), last_layer => $menu_layer, at_first => 1}});
                }
            }
        }
        elsif($cmd eq "input")
        {
            # schedule an immediate status request right before the next command to ensure the correct presence of $hash->{helper}{CURRENT_INPUT_TAG} for the next command
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus", {options => {priority => 1, at_first => 1}});
        }
        elsif($cmd eq "volume" and $data =~ /RC="0"/)
        {
            my $current_volume = $arg;
            my $target_volume = $options->{volume_target};
            my $diff = $options->{volume_diff};
            
            # DSP based models use "Vol" instead of "Volume"
            my $volume_cmd = (YAMAHA_AVR_isModel_DSP($hash) ? "Vol" : "Volume");
            
            my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});

            readingsBulkUpdate($hash, "volumeStraight", $current_volume);
            readingsBulkUpdate($hash, "volume", YAMAHA_AVR_volume_abs2rel($current_volume));
            
            if(not $current_volume == $target_volume)
            {
                if($diff == 0 or (abs($current_volume - $target_volume) < abs($diff)))
                {
                    Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB (target is $target_volume dB)";
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", $target_volume, {options => {volume_diff => $diff, at_first => 1, priority => 1, volume_target => $target_volume}});
                }
                else
                {
                    Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".($current_volume + $diff)." dB (target is $target_volume dB)";
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".(($current_volume + $diff)*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", ($current_volume + $diff), {options => {volume_diff => $diff, at_first => 1, priority => 1, volume_target => $target_volume}});
                }
            }
            else
            {
                # volume change finished, requesting overall status
                YAMAHA_AVR_GetStatus($hash, 1)
            }
        }
        elsif(($cmd eq "tunerFrequency"  or $cmd eq "tunerPreset") and $data =~ /RC="0"/)
        {
            # get new tunerFrequency status if current input != Tuner
            unless(exists($hash->{helper}{CURRENT_INPUT_TAG}) and $hash->{helper}{CURRENT_INPUT_TAG} eq "Tuner")
            {
                YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"GET\"><Tuner><Play_Info>GetParam</Play_Info></Tuner></YAMAHA_AV>", "statusRequest", "tunerFrequency");
            }
        }
       
        readingsEndUpdate($hash, 1);  
        
        YAMAHA_AVR_GetStatus($hash, 1) unless($cmd =~ /^statusRequest|navigateListMenu|volume|input|tuner.+$/);
    }
    
    YAMAHA_AVR_HandleCmdQueue($queue_hash);
}

#############################
# Converts all Values to FHEM usable command lists
sub YAMAHA_AVR_Param2Fhem($$)
{
    my ($param, $replace_pipes) = @_;

   
    $param =~ s/\s+//g;
    $param =~ s/,//g;
    $param =~ s/_//g;
    $param =~ s/\(/_/g;
    $param =~ s/\)//g;
    $param =~ s/\|/,/g if($replace_pipes == 1);

    return lc $param;
}

#############################
# Returns the Yamaha Parameter Name for the FHEM like aquivalents
sub YAMAHA_AVR_getParamName($$$)
{
    my ($hash, $name, $list) = @_;
    my $item;
   
    return undef if(not defined($list));
  
    my @commands = split("\\|",  $list);

    foreach $item (@commands)
    {
        if(YAMAHA_AVR_Param2Fhem($item, 0) eq $name)
        {
            return $item;
        }
    }
    
    return undef;
}

#############################
# queries the receiver model, system-id, version and all available zones
sub YAMAHA_AVR_getModel($)
{
    my ($hash) = @_;
   
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>", "statusRequest","systemConfig", {options => {at_first => 1, priority => 1}});
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Unit_Desc>GetParam</Unit_Desc></System></YAMAHA_AV>", "statusRequest","unitDescription", {options => {at_first => 1, priority => 1}});
}    
    
#############################
# parses the HTTP response for unit description XML file
sub
YAMAHA_AVR_ParseXML($$$)
{
    my ($param, $err, $data) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
   
    Log3 $name, 3, "YAMAHA_AVR ($name) - could not get unit description. Please turn on the device or check for correct hostaddress!" if($err ne "" and defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1);
    
    $hash->{helper}{RUNNING_REQUEST} = 0;
    delete($hash->{helper}{".HTTP_CONNECTION"}) unless($param->{keepalive});
    
    if($data eq "")
    {
        YAMAHA_AVR_HandleCmdQueue($hash);
        return undef
    }

    delete($hash->{helper}{ZONES}) if(exists($hash->{helper}{ZONES}));
    
    Log3 $name, 4, "YAMAHA_AVR ($name) - checking available zones"; 
    
    while($data =~ /<Menu Func="Subunit" Title_1="(.+?)" YNC_Tag="(.+?)">/gc)
    {
        if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
        {
            $hash->{helper}{ZONES} .= "|";
        }
        Log3 $name, 4, "YAMAHA_AVR ($name) - adding zone: $2";
        $hash->{helper}{ZONES} .= $2;
    }
    
    delete( $hash->{helper}{DSP_MODES}) if(exists($hash->{helper}{DSP_MODES}));
    
    if($data =~ /<Menu Func_Ex="Surround" Title_1="Surround">.*?<Get>(.+?)<\/Get>/)
    {
        my $modes = $1;
        
        Log3 $name, 4, "YAMAHA_AVR ($name) - found DSP modes in XML";
        
        while($modes =~ /<Direct.*?>(.+?)<\/Direct>/gc)
        {
            if(defined($hash->{helper}{DSP_MODES}) and length($hash->{helper}{DSP_MODES}) > 0)
            {
                $hash->{helper}{DSP_MODES} .= "|";
            }
            Log3 $name, 4, "YAMAHA_AVR ($name) - adding DSP mode $1";
            $hash->{helper}{DSP_MODES} .= $1;
        }
    }
    else
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - no DSP modes found in XML";
        # DSP-Z based series does not offer DSP modes in unit description
        if(YAMAHA_AVR_isModel_DSP($hash))
        {
            Log3 $name, 4, "YAMAHA_AVR ($name) - using static DSP mode list für DSP-Z based models";
            $hash->{helper}{DSP_MODES} =    "Hall in Munich|".
                                            "Hall in Vienna|".
                                            "Hall in Amsterdam|".
                                            "Church in Freiburg|".
                                            "Chamber|".
                                            "Village Vanguard|".
                                            "Warehouse Loft|".
                                            "Cellar Club|".
                                            "The Roxy Theatre|".
                                            "The Bottom Line|".
                                            "Sports|".
                                            "Action Game|".
                                            "Roleplaying Game|".
                                            "Music Video|".
                                            "Recital/Opera|".
                                            "Standard|".
                                            "Spectacle|".
                                            "Sci-Fi|".
                                            "Adventure|".
                                            "Drama|".
                                            "Mono Movie|".
                                            "2ch Stereo|".
                                            "7ch Stereo|".
                                            "Straight Enhancer|".
                                            "7ch Enhancer|".
                                            "Surround Decoder";
                                            
        } # RX-Vx67's based series does not offer DSP modes in unit description
        elsif($hash->{MODEL} =~ /^RX-(?:A\d{1,2}00|V\d{1,2}67)$/) 
        {
        
            Log3 $name, 4, "YAMAHA_AVR ($name) - using static DSP mode list for RX-Vx67-based models";
            $hash->{helper}{DSP_MODES} =    "Hall in Munich|".
                                            "Hall in Vienna|".
                                            "Hall in Amsterdam|".
                                            "Church in Freiburg|".
                                            "Church in Royaumont|".
                                            "Chamber|".
                                            "Village Vanguard|".
                                            "Warehouse Loft|".
                                            "Cellar Club|".
                                            "The Roxy Theatre|".
                                            "The Bottom Line|".
                                            "Sports|".
                                            "Action Game|".
                                            "Roleplaying Game|".
                                            "Music Video|".
                                            "Recital/Opera|".
                                            "Standard|".
                                            "Spectacle|".
                                            "Sci-Fi|".
                                            "Adventure|".
                                            "Drama|".
                                            "Mono Movie|".
                                            "2ch Stereo|".
                                            "7ch Stereo|".
                                            "Surround Decoder";
        }
    }
    

    # check for hdmi output command
    $hash->{helper}{SUPPORT_HDMI_OUT} = ($data =~ /<Menu Func_Ex="HDMI_Out" Title_1="HDMI OUT">/ ? 1 : 0);
    
    # uncomment line for zone detection testing
    #
    #$hash->{helper}{ZONES} .= "|Zone_2";
    
    $hash->{ZONES_AVAILABLE} = YAMAHA_AVR_Param2Fhem($hash->{helper}{ZONES}, 1);
   
    # if explicitly given in the define command, set the desired zone
    if(defined(YAMAHA_AVR_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES})))
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - using ".YAMAHA_AVR_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES})." as active zone";
        $hash->{ACTIVE_ZONE} = lc $hash->{helper}{SELECTED_ZONE};
    }
    else
    {
        Log3 $name, 2, "YAMAHA_AVR ($name) - selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available. Using Main Zone instead";
        $hash->{ACTIVE_ZONE} = "mainzone";
    }
    
    # create device pointer
    $modules{YAMAHA_AVR}{defptr}{$hash->{SYSTEM_ID}}{$hash->{ACTIVE_ZONE}} = $hash if(exists($hash->{SYSTEM_ID}) and exists($hash->{ACTIVE_ZONE}));
    
    YAMAHA_AVR_HandleCmdQueue($hash); 
}

#############################
# converts decibal volume in percentage volume (-80.5 .. 16.5dB => 0 .. 100%)
sub YAMAHA_AVR_volume_rel2abs($)
{
    my ($percentage) = @_;
    
    #  0 - 100% -equals 80.5 to 16.5 dB
    return int((($percentage / 100 * 97) - 80.5) / 0.5) * 0.5;
}

#############################
# converts percentage volume in decibel volume (0 .. 100% => -80.5 .. 16.5dB)
sub YAMAHA_AVR_volume_abs2rel($)
{
    my ($absolute) = @_;
    
    # -80.5 to 16.5 dB equals 0 - 100%
    return int(($absolute + 80.5) / 97 * 100);
}

#############################
# queries all available inputs and scenes
sub YAMAHA_AVR_getInputs($)
{
    my ($hash) = @_;  
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
   
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    return undef if(not defined($zone) or $zone eq "");
    
    # query all inputs
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Input><Input_Sel_Item>GetParam</Input_Sel_Item></Input></$zone></YAMAHA_AV>", "statusRequest","getInputs", {options => {at_first => 1, priority => 1}});

    # query all available scenes (only in mainzone available)
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Scene><Scene_Sel_Item>GetParam</Scene_Sel_Item></Scene></$zone></YAMAHA_AV>", "statusRequest","getScenes", {options => {can_fail => 1, at_first => 1, priority => 1}}) if($hash->{ACTIVE_ZONE} eq "mainzone");
}

#############################
# Restarts the internal status request timer according to the given interval or current receiver state
sub YAMAHA_AVR_ResetTimer($;$)
{
    my ($hash, $interval) = @_;
    my $name = $hash->{NAME};
    
    RemoveInternalTimer($hash, "YAMAHA_AVR_GetStatus");
    
    unless(IsDisabled($name))
    {
        if(defined($interval))
        {
            InternalTimer(gettimeofday()+$interval, "YAMAHA_AVR_GetStatus", $hash);
        }
        elsif(ReadingsVal($name, "presence", "absent") eq "present" and ReadingsVal($name, "power", "off") eq "on")
        {
            InternalTimer(gettimeofday()+$hash->{helper}{ON_INTERVAL}, "YAMAHA_AVR_GetStatus", $hash);
        }
        else
        {
            InternalTimer(gettimeofday()+$hash->{helper}{OFF_INTERVAL}, "YAMAHA_AVR_GetStatus", $hash);
        }
    }
    
    return undef;
}

#############################
# convert all HTML entities into UTF-8 aquivalents
sub YAMAHA_AVR_html2txt($)
{
    my ($string) = @_;

    $string =~ s/&amp;/&/g;
    $string =~ s/&amp;/&/g;
    $string =~ s/&nbsp;/ /g;
    $string =~ s/&apos;/'/g;
    
    $string = decode('UTF-8', $string); 
    
    $string =~ s/(\xe4|&auml;)/\xc3\xa4/g;
    $string =~ s/(\xc4|&Auml;)/\xc3\x84/g;
    $string =~ s/(\xf6|&ouml;)/\xc3\xb6/g;
    $string =~ s/(\xd6|&Ouml;)/\xc3\x96/g;
    $string =~ s/(\xfc|&uuml;)/\xc3\xbc/g;
    $string =~ s/(\xdc|&Uuml;)/\xc3\x9c/g;
    $string =~ s/(\xdf|&szlig;)/\xc3\x9f/g;
    
    $string =~ s/<[^>]+>//g;
    
    $string =~ s/&gt;/>/g;
    $string =~ s/&lt;/</g;
    
    $string =~ s/(^\s+|\s+$)//g;
   
    return $string;
}

sub YAMAHA_AVR_generateSurroundDecoderList($)
{
    my ($hash) = @_;
    
    if(defined($hash->{MODEL}))
    {
        if($hash->{MODEL} =~ /^(?:RX-V[67]79|RX-A750|RX-AS710D?)$/) # RX-V679, RX-V779, RX-A750, RX-AS710, RX-AS710D (from RX-Vx79/RX-Ax50 series)
        {
            $hash->{helper}{SURROUND_DECODERS} = "Dolby PLII Movie|Dolby PLII Music|Dolby PLII Game|Dolby PLIIx Movie|Dolby PLIIx Music|Dolby PLIIx Game|DTS NEO:6 Cinema|DTS NEO:6 Music";
        }
        elsif($hash->{MODEL} =~ /^(?:RX-A850|RX-A[123]050|CX-A5100)$/) # RX-A850, RX-A1050, RX-A2050, RX-A3050, CX-A5100 (from RX-Vx79/RX-Ax50 series)
        {
            $hash->{helper}{SURROUND_DECODERS} = "Dolby PLII Movie|Dolby PLII Music|Dolby PLII Game|Dolby PLIIx Movie|Dolby PLIIx Music|Dolby PLIIx Game|Dolby Surround|DTS Neural:X|DTS NEO:6 Cinema|DTS NEO:6 Music";
        }
        elsif($hash->{MODEL} =~ /^RX-(?:V\d{1,2}81|A\d{1,2}60)$/) # RX-Ax60/Vx81 series
        {
            $hash->{helper}{SURROUND_DECODERS} = "Dolby Surround|DTS Neural:X|DTS NEO:6 Cinema|DTS NEO:6 Music"
        }
        else # all other/older models
        {
            $hash->{helper}{SURROUND_DECODERS} = "Dolby PL|Dolby PLII Movie|Dolby PLII Music|Dolby PLII Game|Dolby PLIIx Movie|Dolby PLIIx Music|Dolby PLIIx Game|DTS NEO:6 Cinema|DTS NEO:6 Music";
        }
    }
}


#############################
# Check if amp is one of these models: DSP-Z7, DSP-Z9, DSP-Z11, RX-Z7, RX-Z9, RX-Z11, RX-V2065, RX-V3900, DSP-AX3900
# Tested models: DSP-Z7
sub YAMAHA_AVR_isModel_DSP($)
{
    my($hash) = @_;
    
    if(exists($hash->{MODEL}) && (($hash->{MODEL} =~ /DSP-Z/) || ($hash->{MODEL} =~ /RX-Z/) || ($hash->{MODEL} =~ /RX-V2065/) || ($hash->{MODEL} =~ /RX-V3900/) || ($hash->{MODEL} =~ /DSP-AX3900/)))
    {
        return 1;
    }
    return 0;
}



1;

=pod
=item device
=item summary    controls Yamaha AV receivers via LAN connection
=item summary_DE steuert Yamaha AV-Receiver &uuml;ber die LAN-Verbindung
=begin html

<a name="YAMAHA_AVR"></a>
<h3>YAMAHA_AVR</h3>
<ul>
  <a name="YAMAHA_AVR_define"></a>
  <b>Define</b>
  <ul>
    <code>
    define &lt;name&gt; YAMAHA_AVR &lt;ip-address&gt; [&lt;zone&gt;] [&lt;status_interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_AVR &lt;ip-address&gt; [&lt;zone&gt;] [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>
    This module controls AV receiver from Yamaha via network connection. You are able
    to power your AV reveiver on and off, query it's power state,
    select the input (HDMI, AV, AirPlay, internet radio, Tuner, ...), select the volume
    or mute/unmute the volume.<br><br>
    Defining a YAMAHA_AVR device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of the AV receiver (power state, selected
    input, volume and mute status) and triggers notify/filelog commands.
    <br><br>
    Different status update intervals depending on the power state can be given also. 
    If two intervals are given in the define statement, the first interval statement stands for the status update 
    interval in seconds in case the device is off, absent or any other non-normal state. The second 
    interval statement is used when the device is on.
   
    Example:<br><br>
    <ul><code>
       define AV_Receiver YAMAHA_AVR 192.168.0.10
       <br><br>
       # With custom status interval of 60 seconds<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60 
       <br><br>
       # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60 10
    </code></ul>
   
  </ul>
  <br><br>
  <b>Zone Selection</b><br>
  <ul>
    If your receiver supports zone selection (e.g. RX-V671, RX-V673,... and the AVANTAGE series) 
    you can select the zone which should be controlled. The RX-V3xx and RX-V4xx series for example 
    just have a "Main Zone" (which is the whole receiver itself). In general you have the following
    possibilities for the parameter &lt;zone&gt; (depending on your receiver model).<br><br>
    <ul>
    <li><b>mainzone</b> - this is the main zone (standard)</li>
    <li><b>zone2</b> - The second zone (Zone 2)</li>
    <li><b>zone3</b> - The third zone (Zone 3)</li>
    <li><b>zone4</b> - The fourth zone (Zone 4)</li>
    </ul>
    <br>
    Depending on your receiver model you have not all inputs available on these different zones.
    The module just offers the real available inputs.
    <br><br>
    Example:
    <br><br>
     <ul><code>
        define AV_Receiver YAMAHA_AVR 192.168.0.10 &nbsp;&nbsp;&nbsp; # If no zone is specified, the "Main Zone" will be used.<br>
        attr AV_Receiver YAMAHA_AVR room Livingroom<br>
        <br>
        # Define the second zone<br>
        define AV_Receiver_Zone2 YAMAHA_AVR 192.168.0.10 zone2<br>
        attr AV_Receiver_Zone2 room Bedroom
     </code></ul><br><br>
     For each Zone you will need an own YAMAHA_AVR device, which can be assigned to a different room.
     Each zone can be controlled separatly from all other available zones.
     <br><br>
  </ul>
  
  <a name="YAMAHA_AVR_set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined; the available inputs are depending on the used receiver.
    The module only offers the real available inputs and scenes. The following input commands are just an example and can differ.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; shuts down the device </li>
<li><b>input</b> hdm1,hdmX,... &nbsp;&nbsp;-&nbsp;&nbsp; selects the input channel (only the real available inputs were given)</li>
<li><b>scene</b> scene1,sceneX &nbsp;&nbsp;-&nbsp;&nbsp; select the scene</li>
<li><b>volume</b> 0...100 [direct] &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage. If you use "direct" as second argument, no volume smoothing is used (if activated) for this volume change. In this case, the volume will be set immediatly.</li>
<li><b>volumeStraight</b> -80...15 [direct] &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in decibel. If you use "direct" as second argument, no volume smoothing is used (if activated) for this volume change. In this case, the volume will be set immediatly.</li>
<li><b>volumeUp</b> [0-100] [direct] &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level by 5% or the value of attribute volumeSteps (optional the increasing level can be given as argument, which will be used instead). If you use "direct" as second argument, no volume smoothing is used (if activated) for this volume change. In this case, the volume will be set immediatly.</li>
<li><b>volumeDown</b> [0-100] [direct] &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level by 5% or the value of attribute volumeSteps (optional the decreasing level can be given as argument, which will be used instead). If you use "direct" as second argument, no volume smoothing is used (if activated) for this volume change. In this case, the volume will be set immediatly.</li>
<li><b>hdmiOut1</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the HDMI output 1</li>
<li><b>hdmiOut2</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the HDMI output 2</li>
<li><b>mute</b> on|off|toggle &nbsp;&nbsp;-&nbsp;&nbsp; activates volume mute</li>
<li><b>bass</b> [-6...6] step 0.5 (main zone), [-10...10] step 2 (other zones), [-10...10] step 1 (other zones, DSP models) &nbsp;&nbsp;-&nbsp;&nbsp; set bass tone level in decibel</li>
<li><b>treble</b> [-6...6] step 0.5 (main zone), [-10...10] step 2 (other zones), [-10...10] step 1 (other zones, DSP models) &nbsp;&nbsp;-&nbsp;&nbsp; set treble tone level in decibel</li>
<li><b>dsp</b> hallinmunich,hallinvienna,... &nbsp;&nbsp;-&nbsp;&nbsp; sets the DSP mode to the given preset</li>
<li><b>enhancer</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the internal sound enhancer</li>
<li><b>3dCinemaDsp</b> auto|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the CINEMA DSP 3D mode</li>
<li><b>adaptiveDrc</b> auto|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the Adaptive DRC</li>
<li><b>partyMode</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp;controls the party mode. In Main Zone the whole party mode is enabled/disabled system wide. In each zone executed, it enables/disables the current zone from party mode.</li>
<li><b>navigateListMenu</b> [item1]/[item2]/.../[itemN] &nbsp;&nbsp;-&nbsp;&nbsp; select a specific item within a menu structure. for menu-based inputs (e.g. Net Radio, USB, Server, ...) only. See chapter <a href="#YAMAHA_AVR_MenuNavigation">Automatic Menu Navigation</a> for further details and examples.</li>
<li><b>tunerFrequency</b> [frequency] [AM|FM] &nbsp;&nbsp;-&nbsp;&nbsp; sets the tuner frequency. The first argument is the frequency, second parameter is optional to set the tuner band (AM or FM, default: FM). Depending which tuner band you select, the frequency is given in kHz (AM band) or MHz (FM band). If the second parameter is not set, the FM band will be used. This command can be used even the current input is not "tuner", the new frequency is set and will be played, when the tuner gets active.</li>
<li><b>preset</b> 1...40 &nbsp;&nbsp;-&nbsp;&nbsp; selects a saved preset of the currently selected input.</li>
<li><b>presetUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; selects the next preset of the currently selected input.</li>
<li><b>presetDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; selects the previous preset of the currently selected input.</li>
<li><b>straight</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; bypasses the internal codec converter and plays the original sound codec</li>
<li><b>direct</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; bypasses all internal sound enhancement features and plays the sound straight directly</li> 
<li><b>sleep</b> off,30min,60min,...,last &nbsp;&nbsp;-&nbsp;&nbsp; activates the internal sleep timer</li>
<li><b>shuffle</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; activates the shuffle mode on the current input</li>
<li><b>surroundDecoder</b> dolbypl,... &nbsp;&nbsp;-&nbsp;&nbsp; set the surround decoder. Only the available decoders were given if the device supports the configuration of the surround decoder.</li>
<li><b>extraBass</b> off,auto &nbsp;&nbsp;-&nbsp;&nbsp; controls the extra bass. Only available if supported by the device.</li>
<li><b>ypaoVolume</b> off,auto &nbsp;&nbsp;-&nbsp;&nbsp; controls the YPAO volume. Only available if supported by the device.</li>
<li><b>displayBrightness</b> -4...0 &nbsp;&nbsp;-&nbsp;&nbsp; controls brightness reduction of the front display. Only available if supported by the device.</li>
<li><b>repeat</b> one,all,off &nbsp;&nbsp;-&nbsp;&nbsp; activates the repeat mode on the current input for one or all titles</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause playback on current input</li>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playback on current input</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop playback on current input</li>
<li><b>skip</b> reverse,forward &nbsp;&nbsp;-&nbsp;&nbsp; skip track on current input</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands as listed below</li>

</ul>
</ul><br><br>
<u>Remote control (not in all zones available, depending on your model)</u><br><br>
<ul>
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
    remoteControl setup<br>
    remoteControl option<br>
    remoteControl display<br>
    </code></ul><br><br>
    
    <u>Tuner Control:</u><br><br>
    <ul><code>
    remoteControl tunerPresetUp<br>
    remoteControl tunerPresetDown<br>
    </code></ul><br><br>

    The button names are the same as on your remote control.
  </ul>
  <br>
<a name="YAMAHA_AVR_MenuNavigation"></a>
<u>Automatic Menu Navigation (only for menu based inputs like Net Radio, Server, USB, ...)</u><br><br>
<ul>
For menu based inputs you have to select a specific item out of a complex menu structure to start playing music.
Mostly you want to start automatic playback for a specific internet radio (input: Net Radio) or similar, where you have to navigate through several menu and submenu items.
<br><br>
To automate such a complex menu navigation, you can use the set command "navigateListMenu". 
As Parameter you give a menu path of the desired item you want to select. 
YAMAHA_AVR will go through the menu and selects all menu items given as parameter from left to right. 
All menu items are separated by a forward slash (/).
<br><br>
So here are some examples:
    Receiver's current input is "netradio":<br><br>
    <ul>
    <code>
          set &lt;name&gt; navigateListMenu Countries/Australia/All Stations/1Radio.FM<br>
          set &lt;name&gt; navigateListMenu Bookmarks/Favorites/1LIVE</code>
    </ul><br>
    If you want to turn on your receiver and immediatly select a specific internet radio you may use:<br><br>
    <ul>
        <code>
          set &lt;name&gt; on ; set &lt;name&gt; volume 20 direct ; set &lt;name&gt; input netradio ; set &lt;name&gt; navigateListMenu Bookmarks/Favorites/1LIVE<br><br>
          # for regular execution to a specific time using the <a href="#at">at</a> module<br>
          define turn_on_Radio_morning at *08:00 set &lt;name&gt; on ; set &lt;name&gt; volume 20 direct ; set &lt;name&gt; input netradio ; set &lt;name&gt; navigateListMenu Countries/Australia/All Stations/1Radio.FM<br><br>
          define turn_on_Radio_evening at *17:00 set &lt;name&gt; on ; set &lt;name&gt; volume 20 direct ; set &lt;name&gt; input netradio ; set &lt;name&gt; navigateListMenu Bookmarks/Favorites/1LIVE</code>
    </ul>
    <br>
    Receiver's current input is "server" (network DLNA shares):<br><br> 
    <ul>
    <code>
          set &lt;name&gt; navigateListMenu NAS/Music/Sort By Artist/Alicia Keys/Songs in A Minor/Fallin
    </code>
    </ul>
    <br>
    The exact menu structure depends on your own configuration and network devices who provide content. 
    Each menu item name has not to be provided fully. Each item name will be treated as keyword search. That means, if any menu item contains the given item name, it will be selected, for example:
    <br><br>
    <ul>
    Your real menu path you want to select looks like this: <code> <i><b>Bookmarks</b></i> =&gt; <i><b>Favorites</b></i> =&gt; <i><b>foo:BAR 70's-90's [[HITS]]</b></i></code><br><br>
    The last item has many non-word characters, that can cause you trouble in some situations. But you don't have to use the full name to select this entry. 
    It's enough to use a specific part of the item name, that only exists in this one particular item. So to select this item you can use for instance the following set command:<br><br>
    <code>
          set &lt;name&gt; navigateListMenu Bookmarks/Favorites/foo:BAR
    </code>
    <br><br>
    This works, even without giving the full item name (<i><code>foo:BAR 70's-90's [[HITS]]</code></i>).
    </ul>
    <br>
    This also allows you to pare down long item names to shorter versions.
    The shorter version must be still unique enough to identify the right item.
    The first item in the list (from top to bottom), that contains the given keyword, will be selected.
    
<br><br>
</ul>
  <a name="YAMAHA_AVR_get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code>
    <br><br>
    Currently, the get command only returns the reading values. For a specific list of possible values, see section "Generated Readings/Events".
    <br><br>
  </ul>
  <a name="YAMAHA_AVR_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="YAMAHA_AVR_request-timeout">request-timeout</a></li>
    Optional attribute change the response timeout in seconds for all queries to the receiver.
    <br><br>
    Possible values: 1-5 seconds. Default value is 4 seconds.
    <br><br>
    <li><a name="YAMAHA_AVR_disable">disable</a></li>
    Optional attribute to disable the internal cyclic status update of the receiver. Manual status updates via statusRequest command is still possible.
    <br><br>
    Possible values: 0 => perform cyclic status update, 1 => don't perform cyclic status updates.
    <br><br>
    <li><a name="YAMAHA_AVR_volume-smooth-change">volume-smooth-change</a></li>
    Optional attribute to activate a smooth volume change.
    <br><br>
    Possible values: 0 => off , 1 => on
    <br><br>
    <li><a name="YAMAHA_AVR_volume-smooth-steps">volume-smooth-steps</a></li>
    Optional attribute to define the number of volume changes between the
    current and the desired volume. Default value is 5 steps
    <br><br>
    <li><a name="YAMAHA_AVR_volume-steps">volumeSteps</a></li>
    Optional attribute to define the default increasing and decreasing level for the volumeUp and volumeDown set command. Default value is 5%
    <br><br>
    <li><a name="YAMAHA_AVR_volume-max">volumeMax</a></li>
    Optional attribute to set an upper limit in percentage for volume changes.
    If the user tries to change the volume to a higher level than configured with this attribute, the volume will not exceed this limit.
    <br><br>
    Possible values: 0-100%. Default value is 100% (no limitation)<br><br>
  </ul>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>3dCinemaDsp</b> - The status of the CINEMA DSP 3D mode (can be "auto" or "off")</li>
  <li><b>adaptiveDrc</b> - The status of the Adaptive DRC (can be "auto" or "off")</li>
  <li><b>bass</b> Reports the current bass tone level of the receiver or zone in decibel values (between -6 and 6 dB (mainzone) and -10 and 10 dB (other zones)</li>
  <li><b>direct</b> - indicates if all sound enhancement features are bypassed or not ("on" =&gt; all features are bypassed, "off" =&gt; sound enhancement features are used).</li>
  <li><b>dsp</b> - The current selected DSP mode for sound output</li>
  <li><b>displayBrightness</b> - indicates the brightness reduction of the front display (-4 is the maximum reduction, 0 means no reduction; only available if supported by the device).</li>
  <li><b>enhancer</b> - The status of the internal sound enhancer (can be "on" or "off")</li>
  <li><b>extraBass</b> - The status of the extra bass (can be "auto" or "off", only available if supported by the device)</li>
  <li><b>input</b> - The selected input source according to the FHEM input commands</li>
  <li><b>inputName</b> - The input description as seen on the receiver display</li>
  <li><b>hdmiOut1</b> - The status of the HDMI output 1 (can be "on" or "off")</li>
  <li><b>hdmiOut2</b> - The status of the HDMI output 2 (can be "on" or "off")</li>
  <li><b>mute</b> - Reports the mute status of the receiver or zone (can be "on" or "off")</li>
  <li><b>newFirmware</b> - indicates if a firmware update is available (can be "available" or "unavailable"; only available for RX-Vx71, RX-Vx73, RX-Ax10 or RX-Ax20)</li>
  <li><b>power</b> - Reports the power status of the receiver or zone (can be "on" or "off")</li>
  <li><b>presence</b> - Reports the presence status of the receiver or zone (can be "absent" or "present"). In case of an absent device, it cannot be controlled via FHEM anymore.</li>
  <li><b>partyMode</b> - indicates if the party mode is enabled/disabled for the whole device (in main zone) or if the current zone is enabled for party mode (other zones than main zone)</li>
  <li><b>sleep</b> - indicates if the internal sleep timer is activated or not.</li>
  <li><b>straight</b> - indicates if the internal sound codec converter is bypassed or not (can be "on" or "off")</li>
  <li><b>state</b> - Reports the current power state and an absence of the device (can be "on", "off" or "absent")</li>
  <li><b>surroundDecoder</b> - Reports the selected surround decoder in case of "Surround Decoder" is used as active DSP</li>    
  <li><b>tunerFrequency</b> - the current tuner frequency in kHz (AM band) or MHz (FM band)</li>
  <li><b>tunerFrequencyBand</b> - the current tuner band (AM or FM)</li>
  <li><b>treble</b> Reports the current treble tone level of the receiver or zone in decibel values (between -6 and 6 dB (mainzone) and -10 and 10 dB (other zones)</li>
  <li><b>volume</b> - Reports the current volume level of the receiver or zone in percentage values (between 0 and 100 %)</li>
  <li><b>volumeStraight</b> - Reports the current volume level of the receiver or zone in decibel values (between -80.5 and +15.5 dB)</li>
  <li><b>ypaoVolume</b> - The status of the YPAO valume (can be "auto" or "off", only available if supported by the device)</li>
  <br><u>Input dependent Readings/Events:</u><br><br>
  <li><b>currentChannel</b> - Number of the input channel (SIRIUS only)</li>
  <li><b>currentStation</b> - Station name of the current radio station (available only on TUNER, HD RADIO, NET RADIO or PANDORA)</li>
  <li><b>currentStationFrequency</b> - The tuner frequency of the current station (only available on Tuner or HD Radio)</li>
  <li><b>currentAlbum</b> - Album name of the current song</li>
  <li><b>currentArtist</b> - Artist name of the current song</li>
  <li><b>currentTitle</b> - Title of the current song</li>
  <li><b>playStatus</b> - indicates if the input plays music or not</li>
  <li><b>shuffle</b> - indicates the shuffle status for the current input</li>
  <li><b>repeat</b> - indicates the repeat status for the current input</li>
  </ul>
<br>
  <b>Implementator's note</b><br>
  <ul>
    The module is only usable if you activate "Network Standby" on your receiver. Otherwise it is not possible to communicate with the receiver when it is turned off.
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="YAMAHA_AVR"></a>
<h3>YAMAHA_AVR</h3>
<ul>

  <a name="YAMAHA_AVR_define"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; YAMAHA_AVR &lt;IP-Addresse&gt; [&lt;Zone&gt;] [&lt;Status_Interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_AVR &lt;IP-Addresse&gt; [&lt;Zone&gt;] [&lt;Off_Interval&gt;] [&lt;On_Interval&gt;]
    </code>
    <br><br>

    Dieses Modul steuert AV-Receiver des Herstellers Yamaha &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit den Receiver an-/auszuschalten, den Eingangskanal zu w&auml;hlen,
    die Lautst&auml;rke zu &auml;ndern, den Receiver "Stumm" zu schalten, sowie den aktuellen Status abzufragen.
    <br><br>
    Bei der Definition eines YAMAHA_AVR-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter <code>&lt;Status_Interval&gt;</code>; falls nicht gesetzt ist der Standardwert 30 Sekunden)
    den Status des Receivers abfragt und entsprechende Notify-/FileLog-Ger&auml;te triggert.
    <br><br>
    Sofern 2 Interval-Argumente &uuml;bergeben werden, wird der erste Parameter <code>&lt;Off_Interval&gt;</code> genutzt
    sofern der Receiver ausgeschaltet oder nicht erreichbar ist. Der zweiter Parameter <code>&lt;On_Interval&gt;</code> 
    wird verwendet, sofern der Receiver eingeschaltet ist. 
    <br><br>
    Beispiel:<br><br>
    <ul><code>
       define AV_Receiver YAMAHA_AVR 192.168.0.10
       <br><br>
       # Mit modifiziertem Status Interval (60 Sekunden)<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60
       <br><br>
       # Mit gesetztem "Off"-Interval (60 Sekunden) und "On"-Interval (10 Sekunden)<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60 10
    </code></ul><br><br>
  </ul>
  <b>Zonenauswahl</b><br>
  <ul>
    Wenn der zu steuernde Receiver mehrere Zonen besitzt (z.B. RX-V671, RX-V673,... sowie die AVANTAGE Modellreihe) 
    kann die zu steuernde Zone explizit angegeben werden. Die Modellreihen RX-V3xx und RX-V4xx als Beispiel
    haben nur eine Zone (Main Zone). Je nach Receiver-Modell stehen folgende Zonen zur Verf&uuml;gung, welche mit
    dem optionalen Parameter &lt;Zone&gt; angegeben werden k&ouml;nnen.<br><br>
    <ul>
    <li><b>mainzone</b> - Das ist die Hauptzone (Standard)</li>
    <li><b>zone2</b> - Die zweite Zone (Zone 2)</li>
    <li><b>zone3</b> - Die dritte Zone (Zone 3)</li>
    <li><b>zone4</b> - Die vierte Zone (Zone 4)</li>
    </ul>
    <br>
    Je nach Receiver-Modell stehen in den verschiedenen Zonen nicht immer alle Eing&auml;nge zur Verf&uuml;gung. 
    Dieses Modul bietet nur die tats&auml;chlich verf&uuml;gbaren Eing&auml;nge an.
    <br><br>
    Beispiel:<br><br>
     <ul><code>
        define AV_Receiver YAMAHA_AVR 192.168.0.10 &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; # Wenn keine Zone angegeben ist, wird<br>
        attr AV_Receiver YAMAHA_AVR room Wohnzimmer &nbsp;&nbsp;&nbsp;&nbsp; # standardm&auml;&szlig;ig "mainzone" verwendet<br>
        <br>
        # Definition der zweiten Zone<br>
        define AV_Receiver_Zone2 YAMAHA_AVR 192.168.0.10 zone2<br>
        attr AV_Receiver_Zone2 room Schlafzimmer<br>
     </code></ul><br><br>
     F&uuml;r jede Zone muss eine eigene YAMAHA_AVR Definition erzeugt werden, welche dann unterschiedlichen R&auml;umen zugeordnet werden kann.
     Jede Zone kann unabh&auml;ngig von allen anderen Zonen (inkl. der Main Zone) gesteuert werden.
     <br><br>
  </ul>
  
  <a name="YAMAHA_AVR_set"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <br><br>
    Aktuell werden folgende Kommandos unterst&uuml;tzt. Die verf&uuml;gbaren Eing&auml;nge und Szenen k&ouml;nnen je nach Receiver-Modell variieren.
    Die folgenden Eing&auml;nge stehen beispielhaft an einem RX-V473 Receiver zur Verf&uuml;gung.
    Aktuell stehen folgende Kommandos zur Verf&uuml;gung.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet den Receiver ein</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet den Receiver aus</li>
<li><b>dsp</b> hallinmunich,hallinvienna,... &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert das entsprechende DSP Preset</li>
<li><b>enhancer</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den Sound Enhancer f&uuml;r einen verbesserten Raumklang</li>
<li><b>3dCinemaDsp</b> auto,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den CINEMA DSP 3D Modus</li>
<li><b>adaptiveDrc</b> auto,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert Adaptive DRC</li>
<li><b>extraBass</b> auto,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den Extra Bass</li>
<li><b>ypaoVolume</b> auto,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert YPAO Lautst&auml;rke</li>
<li><b>displayBrightness</b> -4...0 &nbsp;&nbsp;-&nbsp;&nbsp; Steuert die Helligkeitsreduzierung des Front-Displays</li>
<li><b>partyMode</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp;Aktiviert den Party Modus. In der Main Zone wird hierbei der Party Modus ger&auml;teweit aktiviert oder deaktiviert. In den anderen Zonen kann man damit die entsprechende Zone dem Party Modus zuschalten oder entziehen.</li>
<li><b>navigateListMenu</b> [Element 1]/[Element 2]/.../[Element N] &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt ein spezifisches Element aus einer Men&uuml;struktur aus. Nur verwendbar bei Men&uuml;-basierenden Eing&auml;ngen (z.B. Net Radio, USB, Server, etc.). Siehe nachfolgendes Kapitel "<a href="#YAMAHA_AVR_MenuNavigation">Automatische Men&uuml; Navigation</a>" f&uuml;r weitere Details und Beispiele.</li>
<li><b>tunerFrequency</b> [Frequenz] [AM|FM] &nbsp;&nbsp;-&nbsp;&nbsp; setzt die Radio-Frequenz. Das erste Argument ist die Frequenz, der zweite dient optional zu Angabe des Bandes (AM oder FM, standardm&auml;&szlig;ig FM). Abh&auml;ngig davon, welches Band man benutzt, wird die Frequenz in kHz (AM-Band) oder MHz (FM-Band) angegeben. Wenn im zweiten Argument kein Band angegeben ist, wird standardm&auml;&szlig;ig das FM-Band benutzt. Dieser Befehl kann auch benutzt werden, wenn der aktuelle Eingang nicht "tuner" ist. Die neue Frequenz wird dennoch gesetzt und bei der n&auml;chsten Benutzung abgespielt.</li>
<li><b>preset</b> 1...40 &nbsp;&nbsp;-&nbsp;&nbsp; w&auml;hlt ein gespeichertes Preset f&uuml;r den aktuellen Eingang aus.</li>
<li><b>presetUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; w&auml;hlt das n&auml;chste Preset f&uuml;r den aktuellen Eingang aus.</li>
<li><b>presetDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; w&auml;hlt das vorherige Preset f&uuml;r den aktuellen Eingang aus.</li>
<li><b>direct</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Umgeht alle internen soundverbessernden Ma&szlig;nahmen (Equalizer, Enhancer, Adaptive DRC,...) und gibt das Signal unverf&auml;lscht wieder</li>
<li><b>input</b> hdmi1,hdmiX,... &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt den Eingangskanal (es werden nur die tats&auml;chlich verf&uuml;gbaren Eing&auml;nge angeboten)</li>
<li><b>hdmiOut1</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert die Ausgabe via HDMI Ausgang 1</li>
<li><b>hdmiOut2</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert die Ausgabe via HDMI Ausgang 2</li>
<li><b>scene</b> scene1,sceneX &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt eine vorgefertigte Szene aus</li>
<li><b>surroundDecoder</b> dolbypl,... &nbsp;&nbsp;-&nbsp;&nbsp; Setzt den Surround Decoder, welcher genutzt werden soll sofern der DSP Modus "Surround Decoder" aktiv ist.</li>
<li><b>volume</b> 0...100  [direct] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Lautst&auml;rke in Prozent (0 bis 100%). Wenn als zweites Argument "direct" gesetzt ist, wird keine weiche Lautst&auml;rkenanpassung durchgef&uuml;hrt (sofern aktiviert). Die Lautst&auml;rke wird in diesem Fall sofort gesetzt.</li>
<li><b>volumeStraight</b> -87...15 [direct] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Lautst&auml;rke in Dezibel (-80.5 bis 15.5 dB) so wie sie am Receiver auch verwendet wird. Wenn als zweites Argument "direct" gesetzt ist, wird keine weiche Lautst&auml;rkenanpassung durchgef&uuml;hrt (sofern aktiviert). Die Lautst&auml;rke wird in diesem Fall sofort gesetzt.</li>
<li><b>volumeUp</b> [0...100] [direct] &nbsp;&nbsp;-&nbsp;&nbsp; Erh&ouml;ht die Lautst&auml;rke um 5% oder entsprechend dem Attribut volumeSteps (optional kann der Wert auch als Argument angehangen werden, dieser hat dann Vorang). Wenn als zweites Argument "direct" gesetzt ist, wird keine weiche Lautst&auml;rkenanpassung durchgef&uuml;hrt (sofern aktiviert). Die Lautst&auml;rke wird in diesem Fall sofort gesetzt.</li>
<li><b>volumeDown</b> [0...100] [direct] &nbsp;&nbsp;-&nbsp;&nbsp; Veringert die Lautst&auml;rke um 5% oder entsprechend dem Attribut volumeSteps (optional kann der Wert auch als Argument angehangen werden, dieser hat dann Vorang). Wenn als zweites Argument "direct" gesetzt ist, wird keine weiche Lautst&auml;rkenanpassung durchgef&uuml;hrt (sofern aktiviert). Die Lautst&auml;rke wird in diesem Fall sofort gesetzt.</li>
<li><b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet den Receiver stumm</li>
<li><b>bass</b> [-6...6] Schrittweite 0.5 (main zone), [-10...10] Schrittweite 2 (andere Zonen), [-10...10] Schrittweite 1 (andere Zonen, DSP Modelle) &nbsp;&nbsp;-&nbsp;&nbsp; Stellt die Tiefen in decibel ein</li>
<li><b>treble</b> [-6...6] Schrittweite 0.5 (main zone), [-10...10] Schrittweite 2 (andere Zonen), [-10...10] Schrittweite 1 (andere Zonen, DSP Modelle) &nbsp;&nbsp;-&nbsp;&nbsp; Stellt die H&ouml;hen in decibel ein</li>
<li><b>straight</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Umgeht die interne Codec-Umwandlung und gibt den Original-Codec wieder.</li>
<li><b>sleep</b> off,30min,60min,...,last &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den internen Sleep-Timer zum automatischen Abschalten</li>
<li><b>shuffle</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert die Zufallswiedergabe des aktuellen Eingangs (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>repeat</b> one,all,off &nbsp;&nbsp;-&nbsp;&nbsp; Wiederholt den aktuellen (one) oder alle (all) Titel des aktuellen Eingangs (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wiedergabe pausieren (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wiedergabe starten (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wiedergabe stoppen (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>skip</b> reverse,forward &nbsp;&nbsp;-&nbsp;&nbsp; Aktuellen Titel &uuml;berspringen (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; Fragt den aktuell Status des Receivers ab</li>

<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; Sendet Fernbedienungsbefehle wie im n&auml;chsten Abschnitt beschrieben</li>
</ul>
<br><br>
</ul>
<u>Fernbedienung (je nach Modell nicht in allen Zonen verf&uuml;gbar)</u><br><br>
<ul>
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
    remoteControl setup<br>
    remoteControl option<br>
    remoteControl display<br>
    </code></ul><br><br>
    
    <u>Radio Steuerung:</u><br><br>
    <ul><code>
    remoteControl tunerPresetUp<br>
    
    
    
    remoteControl tunerPresetDown<br>
    </code></ul><br>
  </ul>
<a name="YAMAHA_AVR_MenuNavigation"></a>
<u>Automatische Men&uuml; Navigation (nur f&uuml;r Men&uuml;-basierte Eing&auml;nge wie z.B. Net Radio, Server, USB, ...)</u><br><br>
<ul>
F&uuml;r Men&uuml;-basierte Eing&auml;nge muss man einen bestimmten Eintrag aus einer komplexen Struktur ausw&auml;hlen um die Wiedergabe zu starten.
Ein typischer Fall ist das Abspielen von Internet-Radios (Eingang: Net Radio) oder &auml;hnlichen, netzwerkbasierten Diensten. 
Erst durch das Navigieren durch mehrere Men&uuml;s und Untermen&uuml;s selektiert man das gew&uuml;nschte Element und die Wiedergabe beginnt.
<br><br>
Um diese Navigation durch verschiedene Men&uuml;strukturen zu automatisieren, gibt es das Set-Kommando "navigateListMenu".
Als Parameter &uuml;bergibt man den Pfad (ausgehend vom Beginn) zu dem gew&uuml;nschtem Men&uuml;eintrag
YAMAHA_AVR wird diese Liste von links nach rechts abarbeiten und sich so durch das Men&uuml; hangeln.
Alle angegebenen Men&uuml;elemente sind dabei durch einen Schr&auml;gstrich (/) getrennt.
<br><br>
Ein paar Beispiele:
    Aktueller Eingang ist "netradio":<br><br>
    <ul>
    <code>
          set &lt;name&gt; navigateListMenu L&auml;nder/Ozeanien/Australien/Alle Sender/1Radio.FM<br>
          set &lt;name&gt; navigateListMenu Lesezeichen/Favoriten/1LIVE</code>
    </ul><br>
    Wenn man den Receiver mit einem Befehl anschalten m&ouml;chte und einen bestimmten Internet-Radio Sender ausw&auml;hlen will:<br><br>
    <ul>
        <code>
          set &lt;name&gt; on ; set &lt;name&gt; volume 20 direct ; set &lt;name&gt; input netradio ; set &lt;name&gt; navigateListMenu Lesezeichen/Favoriten/1LIVE<br><br>
          # f&uuml;r t&auml;gliches einschalten eines Internet-Radios via <a href="#at">at-Modul</a><br>
          define 1Radio_am_Morgen at *08:00 set &lt;name&gt; on ; set &lt;name&gt; volume 20 direct ; set &lt;name&gt; input netradio ; set &lt;name&gt; navigateListMenu L&auml;nder/Ozeanien/Australien/Alle Sender/1Radio.FM<br><br>
          define 1LIVE_am_Abend at *17:00 set &lt;name&gt; on ; set &lt;name&gt; volume 20 direct ; set &lt;name&gt; input netradio ; set &lt;name&gt; navigateListMenu Lesezeichen/Favoriten/1LIVE</code>
    </ul>
    <br>
    Aktueller Eingang ist "server" (Netzwerk-Freigaben via UPnP/DLNA):<br><br> 
    <ul>
    <code>
          set &lt;name&gt; navigateListMenu NAS/Musik/Nach Interpret/Alicia Keys/Songs in A Minor/Fallin
    </code>
    </ul>
    <br>
    Die exakte Men&uuml;struktur h&auml;ngt von ihrer eigenen Receiver-Konfiguration, sowie den zur Verf&uuml;gung stehenden Freigaben in ihrem Netzwerk ab.
    Jeder einzelne Men&uuml;eintrag muss nicht vollst&auml;ndig als Pfadelement angegeben werden.
    Jedes Pfadelement wird als Stichwort verwendet um den richtigen Men&uuml;eintrag aus der aktuellen Listenebene zu finden, z.B:
    <br><br>
    <ul>
    Der tats&auml;chliche Men&uuml;pfad (wie im Display des Receiveres erkennbar) sieht beispielhaft folgenderma&szlig;en aus: <code> <i><b>Lesezeichen</b></i> =&gt; <i><b>Favoriten</b></i> =&gt; <i><b>foo:BAR 70'er-90'er [[HITS]]</b></i></code><br><br>
    Der letzte Men&uuml;eintrag hat in diesem Fall viele Sonderzeichen die einem in einer FHEM-Konfiguration durchaus Probleme bereiten k&ouml;nen.
    Man muss aber nicht die vollst&auml;ndige Bezeichnung in der Pfadangabe benutzen, sondern kann ein k&uuml;rzeres Stichwort benutzen, was in der vollst&auml;ndigen Bezeichnung jedoch vorkommen muss.
    So kann man beispielsweise folgendes Set-Kommando benutzen um diesen Eintrag auszuw&auml;hlen und die Wiedergabe damit zu starten:<br><br>
    <code>
          set &lt;name&gt; navigateListMenu Lesezeichen/Favoriten/foo:BAR
    </code>
    <br><br>
    Dieser Befehl funktioniert, obwohl man nicht die vollst&auml;ndige Bezeichnung angegeben hat (<i><code>foo:BAR 70's-90's [[HITS]]</code></i>).
    </ul>
    <br>
    Auf selbe Wei&szlig;e kann man somit lange Men&uuml;eintr&auml;ge abk&uuml;rzen, damit die Befehle nicht so lang werden.
    Solche gek&uuml;rzten Pfadangaben m&uuml;ssen aber trotzdem soweit eindeutig sein, damit sie nur auf das gew&uuml;nschte Element passen.
    Das erste Element aus einer Listenebene (von oben nach unten), was auf eine Pfadangabe passt, wird ausgew&auml;hlt.
<br><br>
</ul>
  <a name="YAMAHA_AVR_get"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Readingname&gt;</code>
    <br><br>
    Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".
  </ul>
  <br><br>
  <a name="YAMAHA_AVR_attr"></a>
  <b>Attribute</b>
  <ul>
  
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a name="YAMAHA_AVR_request-timeout">request-timeout</a></li>
    Optionales Attribut. Maximale Dauer einer Anfrage in Sekunden zum Receiver.
    <br><br>
    M&ouml;gliche Werte: 1-5 Sekunden. Standardwert ist 4 Sekunden<br><br>
    <li><a name="YAMAHA_AVR_disable">disable</a></li>
    Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
    <br><br>
    M&ouml;gliche Werte: 0 => zyklische Status-Updates, 1 => keine zyklischen Status-Updates.<br><br>
    <li><a name="YAMAHA_AVR_volume-smooth-change">volume-smooth-change</a></li>
    Optionales Attribut, welches einen weichen Lautst&auml;rke&uuml;bergang aktiviert..
    <br><br>
    M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br><br>
    <li><a name="YAMAHA_AVR_volume-smooth-steps">volume-smooth-steps</a></li>
    Optionales Attribut, welches angibt, wieviele Schritte zur weichen Lautst&auml;rkeanpassung
    durchgef&uuml;hrt werden sollen. Standardwert ist 5 Anpassungschritte<br><br>
    <li><a name="YAMAHA_AVR_volumeSteps">volumeSteps</a></li>
    Optionales Attribut, welches den Standardwert zur Lautst&auml;rkenerh&ouml;hung (volumeUp) und Lautst&auml;rkenveringerung (volumeDown) konfiguriert. Standardwert ist 5%
    <br><br>
    <li><a name="YAMAHA_AVR_volumeMax">volumeMax</a></li>
    Optionales Attribut, welches eine maximale Obergrenze in Prozent für die Lautst&auml;rke festlegt.
    Wird versucht die Lautst&auml;rke auf einen h&ouml;heren Wert zu setzen, so wird die Lautst&auml;rke dennoch die konfigurierte Obergrenze nicht &uuml;berschreiten.
    <br><br>
    M&ouml;gliche Werte: 0-100%. Standardwert ist 100% (keine Begrenzung)
    <br><br>
  </ul>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>3dCinemaDsp</b> - Der Status des CINEMA DSP 3D-Modus ("auto" =&gt; an, "off" =&gt; aus)</li>
  <li><b>adaptiveDrc</b> - Der Status des Adaptive DRC ("auto" =&gt; an, "off" =&gt; aus)</li>
  <li><b>bass</b> Der aktuelle Basspegel, zwischen -6 and 6 dB (main zone) and -10 and 10 dB (andere Zonen)</li>
  <li><b>direct</b> - Zeigt an, ob soundverbessernde Features umgangen werden oder nicht ("on" =&gt; soundverbessernde Features werden umgangen, "off" =&gt; soundverbessernde Features werden benutzt)</li>
  <li><b>displayBrightness</b> - Status der Helligkeitsreduzierung des Front-Displays (-4 =&gt; maximale Reduzierung, 0 =&gt; keine Reduzierung)</li>  
  <li><b>dsp</b> - Das aktuell aktive DSP Preset</li>
  <li><b>enhancer</b> - Der Status des Enhancers ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>extraBass</b> - Der Status des Extra Bass ("auto" =&gt; an, "off" =&gt; aus)</li>
  <li><b>input</b> - Der ausgew&auml;hlte Eingang entsprechend dem FHEM-Kommando</li>
  <li><b>inputName</b> - Die Eingangsbezeichnung, so wie sie am Receiver eingestellt wurde und auf dem Display erscheint</li>
  <li><b>hdmiOut1</b> - Der Status des HDMI Ausgang 1 ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>hdmiOut2</b> - Der Status des HDMI Ausgang 2 ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>mute</b> - Der aktuelle Stumm-Status ("on" =&gt; Stumm, "off" =&gt; Laut)</li>
  <li><b>newFirmware</b> - Zeigt an, ob eine neue Firmware zum installieren bereit liegt ("available" =&gt; neue Firmware verf&uuml;gbar, "unavailable" =&gt; keine neue Firmware verf&uuml;gbar; Event wird nur generiert f&uuml;r RX-Vx71, RX-Vx73, RX-Ax10 oder RX-Ax20)</li>
  <li><b>power</b> - Der aktuelle Betriebsstatus ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>presence</b> - Die aktuelle Empfangsbereitschaft ("present" =&gt; empfangsbereit, "absent" =&gt; nicht empfangsbereit, z.B. Stromausfall)</li>
  <li><b>partyMode</b> - Der Status des Party Modus ( "enabled" =&gt; aktiviert, "disabled" =&gt; deaktiviert). In der Main Zone stellt dies den ger&auml;teweiten Zustand des Party Modus dar. In den einzelnen Zonen zeigt es an, ob die jeweilige Zone f&uuml;r den Party Modus verwendet wird.</li>
  <li><b>straight</b> - Zeigt an, ob die interne Codec Umwandlung umgangen wird oder nicht ("on" =&gt; Codec Umwandlung wird umgangen, "off" =&gt; Codec Umwandlung wird benutzt)</li>
  <li><b>sleep</b> - Zeigt den Status des internen Sleep-Timers an</li>
  <li><b>surroundDecoder</b> - Zeigt den aktuellen Surround Decoder an</li>
  <li><b>state</b> - Der aktuelle Schaltzustand (power-Reading) oder die Abwesenheit des Ger&auml;tes (m&ouml;gliche Werte: "on", "off" oder "absent")</li>
  <li><b>tunerFrequency</b> - Die aktuelle Empfangsfrequenz f&uuml;r Radio-Empfang in kHz (AM-Band) oder MHz (FM-Band)</li>
  <li><b>tunerFrequencyBand</b> - Das aktuell genutzte Radio-Band ("AM" oder "FM")</li>
  <li><b>treble</b> Der aktuelle H&ouml;henpegel, zwischen -6 and 6 dB (main zone) and -10 and 10 dB (andere Zonen)</li>
  <li><b>volume</b> - Der aktuelle Lautst&auml;rkepegel in Prozent (zwischen 0 und 100 %)</li>
  <li><b>volumeStraight</b> - Der aktuelle Lautst&auml;rkepegel in Dezibel (zwischen -80.0 und +15 dB)</li>
  <li><b>ypaoVolume</b> - Der Status der YPAO Lautst&auml;rke ("auto" =&gt; an, "off" =&gt; aus)</li>
  <br><u>Eingangsabh&auml;ngige Readings/Events:</u><br><br>
  <li><b>currentChannel</b> - Nummer des Eingangskanals (nur bei SIRIUS)</li>
  <li><b>currentStation</b> - Name des Radiosenders (nur bei TUNER, HD RADIO, NET RADIO oder PANDORA)</li>
  <li><b>currentStationFrequency</b> - Die Sendefrequenz des aktuellen Radiosender (nur bei Tuner oder HD Radio)</li>  
  <li><b>currentAlbum</b> - Album es aktuell gespielten Titel</li>
  <li><b>currentArtist</b> - Interpret des aktuell gespielten Titel</li>
  <li><b>currentTitle</b> - Name des aktuell gespielten Titel</li>
  <li><b>playStatus</b> - Wiedergabestatus des Eingangs</li>
  <li><b>shuffle</b> - Status der Zufallswiedergabe des aktuellen Eingangs</li>
  <li><b>repeat</b> - Status der Titelwiederholung des aktuellen Eingangs</li>
  </ul>
<br>
  <b>Hinweise des Autors</b>
  <ul>
    Dieses Modul ist nur nutzbar, wenn die Option "Network Standby" am Receiver aktiviert ist. Ansonsten ist die Steuerung nur im eingeschalteten Zustand m&ouml;glich.
  </ul>
  <br>
</ul>
=end html_DE

=cut
