# $Id$
##############################################
#
#     31_MilightDevice.pm (Based on 32_WifiLight.pm by hermannj)
#     FHEM module for MILIGHT lightbulbs.  Supports RGB (untested), RGBW and White models.
#     Author: Matthew Wire (mattwire)
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

use IO::Handle;
use IO::Socket;
use IO::Select;
use Time::HiRes;
#use Math::Round ();

use Color;
use SetExtensions;

my %dim_values = (
   0 => "dim_00",
   1 => "dim_10",
   2 => "dim_20",
   3 => "dim_30",
   4 => "dim_40",
   5 => "dim_50",
   6 => "dim_60",
   7 => "dim_70",
   8 => "dim_80",
   9 => "dim_90",
  10 => "dim_100",
);

# RGBW 3 byte commands.  3rd byte not required Bridge V3+
my @RGBWCmdsOn  = ("\x45", "\x47", "\x49", "\x4B", "\x42"); # Byte 1 for setting On
my @RGBWCmdsOff = ("\x46", "\x48", "\x4A", "\x4C", "\x41"); # Byte 1 for setting Off
my @RGBWCmdsWT  = ("\xC5", "\xC7", "\xC9", "\xCB", "\xC2"); # Byte 1 for setting WhiteMode
my @RGBWCmdsNt  = ("\xC6", "\xC8", "\xCA", "\xCC", "\xC1"); # Byte 1 for setting NightMode
my $RGBWCmdBri = "\x4E"; # Byte 1 for setting brightness (Byte 2 specifies level (0x02-0x1B 25 steps)
my $RGBWCmdCol = "\x40"; # Byte 1 for setting color (Byte 2 specifies color value (0x00-0xFF (255 steps))
my $RGBWCmdDiscoUp = "\x4D"; # Byte 1 for setting discoMode Up
my $RGBWCmdDiscoInc = "\x44"; # Byte 1 for setting discoMode speed +
my $RGBWCmdDiscoDec = "\x43"; # Byte 1 for setting discoMode speed -
my $RGBWCmdEnd = "\x55"; # Byte 3

# White 3 byte commands.
my @WhiteCmdsOn = ("\x38", "\x3D", "\x37", "\x32", "\x35"); # Byte 1 for setting On
my @WhiteCmdsOff = ("\x3B", "\x33", "\x3A", "\x36", "\x39"); # Byte 1 for setting Off
my @WhiteCmdsOnFull = ("\xB8", "\xBD", "\xB7", "\xB2", "\xB5"); # Byte 1 for setting full brightness
my @WhiteCmdsNt  = ("\xBB", "\xB3", "\xBA", "\xB6", "\xB9"); # Byte 1 for setting NightMode
my @WhiteCmdBriDn = ("\x34", "\x34", "\x34", "\x34", "\xB4"); # Byte 1 for setting Brightness down (11 steps, no direct setting)
my @WhiteCmdBriUp = ("\x3C", "\x3C", "\x3C", "\x3C", "\xBC"); # Byte 1 for setting Brightness up (11 steps, no direct setting)
my @WhiteCmdColDn = ("\x3F", "\x3F", "\x3F", "\x3F", "\xBF"); # Byte 1 for setting colour temp down
my @WhiteCmdColUp = ("\x3E", "\x3E", "\x3E", "\x3E", "\xBE"); # Byte 1 for setting colour temp up
my $WhiteCmdEnd = "\x55"; # Byte 3


sub MilightDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "MilightDevice_Define";
  $hash->{UndefFn} = "MilightDevice_Undef";
  $hash->{ShutdownFn} = "MilightDevice_Undef";
  $hash->{SetFn} = "MilightDevice_Set";
  $hash->{GetFn} = "MilightDevice_Get";
  $hash->{AttrFn} = "MilightDevice_Attr";
  $hash->{NotifyFn} = "MilightDevice_Notify";
  $hash->{AttrList} = "IODev dimStep defaultBrightness defaultRampOn " .
                      "defaultRampOff presets dimOffWhite:1,0 updateGroupDevices:1,0 " .
                      "restoreAtStart:1,0 colorCast gamma lightSceneParamsToSave " . 
                      $readingFnAttributes;
  FHEM_colorpickerInit();
    
}

#####################################
# Device State Icon for FHEMWEB: Shows a colour changing icon with dim level
sub MilightDevice_devStateIcon($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if(ref($hash) ne 'HASH');

  return undef if(!$hash);
  return undef if($hash->{helper}->{group});

  my $name = $hash->{NAME};

  my $percent = ReadingsVal($name,"brightness","100");
  my $s = $dim_values{MilightDevice_roundfunc($percent/10)};

  # Return SVG coloured icon with toggle as default action
  return ".*:light_light_$s@#".ReadingsVal($name, "rgb", "FFFFFF").":toggle"
            if (($hash->{LEDTYPE} eq 'RGBW') || ($hash->{LEDTYPE} eq 'RGB'));
  # Return SVG icon with toggle as default action (for White bulbs)
  return ".*:light_light_$s:toggle";
}

#####################################
# Define Milight device
sub MilightDevice_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);
  my ($name, $type, $ledtype, $iodev, $slot) = @args;
  
  $hash->{INIT} = 0; # Set to 1 when lamp initialised (MilightDevice_Restore)
  $hash->{LEDTYPE} = $ledtype;
  $hash->{SLOT} = $slot;
  $hash->{SLOTID} = $slot;
  if($slot eq 'A') {
    $hash->{SLOTID} = 9 if ($hash->{LEDTYPE} eq 'RGBW');
    $hash->{SLOTID} = 5 if ($hash->{LEDTYPE} eq 'White');
    $hash->{SLOTID} = 0 if ($hash->{LEDTYPE} eq 'RGB');
  }

  # Validate parameters
  return "wrong syntax: define <name> MilightDevice <devType(RGB|RGBW|White)> <IODev> <slot>" if(@args < 5);
  return "unknown LED type ($hash->{LEDTYPE}): choose one of RGB, RGBW, White" if ($hash->{LEDTYPE} !~ /RGBW|White|RGB/);
  return "Invalid slot: Select one of 1..4 / A for White" if (($hash->{SLOTID} !~ /^\d*$/) || (($hash->{SLOT} ne 'A') && (($hash->{SLOT} < 1) || ($hash->{SLOT} > 4))) && ($hash->{LEDTYPE} eq 'White'));
  return "Invalid slot: Select one of 5..8 / A for RGBW" if (($hash->{SLOTID} !~ /^\d*$/) || (($hash->{SLOT} ne 'A') && (($hash->{SLOT} < 5) || ($hash->{SLOT} > 8))) && ($hash->{LEDTYPE} eq 'RGBW'));
  return "Invalid slot: Select 0 for RGB" if (($hash->{SLOTID} !~ /^\d*$/) || ($hash->{SLOTID} != 0 && $hash->{LEDTYPE} eq 'RGB'));
  Log3 ($hash, 4, $name."_Define: $name $type $hash->{LEDTYPE} $iodev $hash->{SLOT}");

  # Verify IODev is valid
  AssignIoPort($hash, $iodev);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 4, $name."_Define: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, $name."_Define: no I/O device";
  }

  # Look for already defined device on IODev
  if ($hash->{SLOT} ne 'A' && defined($hash->{IODev}->{$hash->{SLOT}}->{NAME}))
  {
    # If defined slot does not match current device name don't allow new definition.  Redefining the same device is ok though.
    #return "Slot $hash->{SLOT} already defined as $hash->{IODev}->{$hash->{SLOT}}->{NAME}" if ($hash->{IODev}->{$hash->{SLOT}}->{NAME} ne $name);
  }
  # Define device on IODev
  if ($hash->{SLOT} ne 'A')
  {
    $hash->{IODev}->{$hash->{SLOT}}->{NAME} = $name;
    #$hash->{IODev}->{$hash->{SLOT}}->{DEVNAME} = $name;
  }

  # Define Command Queue
  my @cmdQueue = [];
  $hash->{helper}->{cmdQueue} = \@cmdQueue;
  
  my $baseCmds = "on off toggle dimup dimdown";

  my $sharedCmds = "pair unpair restorePreviousState:noArg saveState:noArg restoreState:noArg";
  my $rgbCmds = "hsv rgb:colorpicker,RGB hue:colorpicker,HUE,0,1,360 saturation:slider,0,100,100 preset";
  $hash->{helper}->{COMMANDSET} = "$baseCmds discoModeUp:noArg discoSpeedUp:noArg discoSpeedDown:noArg night:noArg white:noArg toggleWhite:noArg $sharedCmds $rgbCmds"
        if ($hash->{LEDTYPE} eq 'RGBW');
  $hash->{helper}->{COMMANDSET} = "$baseCmds discoModeUp:noArg discoModeDown:noArg discoSpeedUp:noArg discoSpeedDown:noArg $sharedCmds $rgbCmds"
        if ($hash->{LEDTYPE} eq 'RGB');
        
  $hash->{helper}->{COMMANDSET} = "$baseCmds hsv ct:colorpicker,CT,3000,350,6500 night:noArg $sharedCmds"
        if ($hash->{LEDTYPE} eq 'White');
  
  my $defaultcommandset = $hash->{helper}->{COMMANDSET};
  $hash->{helper}->{COMMANDSET} .= " dim:slider,0,".MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)).",100 brightness:slider,0,".MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)).",100";

  # webCmds
  if (!defined($attr{$name}{webCmd}))
  {
    $attr{$name}{webCmd} = 'on:off:dim:hue:night:rgb ffffff:rgb ff0000:rgb 00ff00:rgb 0000ff:rgb ffff00' if ($hash->{LEDTYPE} eq 'RGBW');
    $attr{$name}{webCmd} = 'on:off:dim:hue:rgb ffffff:rgb ff0000:rgb 00ff00:rgb 0000ff:rgb ffff00' if ($hash->{LEDTYPE} eq 'RGB');
    $attr{$name}{webCmd} = 'on:off:dim:ct:night' if ($hash->{LEDTYPE} eq 'White');
  }

  $hash->{helper}->{GAMMAMAP} = MilightDevice_CreateGammaMapping($hash, 1.0);
  $hash->{helper}->{COLORMAP} = MilightDevice_ColorConverter($hash, split(',', "0,0,0,0,0,0"));

    
  # Define devStateIcon
  $attr{$name}{devStateIcon} = '{(MilightDevice_devStateIcon($name),"toggle")}' if(!defined($attr{$name}{devStateIcon}));
  
  # Event on change reading
  $attr{$name}{"event-on-change-reading"} = "state,transitionInProgress" if (!defined($attr{$name}{"event-on-change-reading"}));

  # lightScene
  if(!defined($attr{$name}{"lightSceneParamsToSave"}))
  {
    $attr{$name}{"lightSceneParamsToSave"} = "hsv" if (($hash->{LEDTYPE} eq 'RGBW')|| ($hash->{LEDTYPE} eq 'RGB'));
    $attr{$name}{"lightSceneParamsToSave"} = "brightness" if ($hash->{LEDTYPE} eq 'White');
  }

  # IODev
  $attr{$name}{IODev} = $hash->{IODev} if (!defined($attr{$name}{IODev}));

  # restoreAtStart
  if($slot eq 'A') {
    $attr{$name}{"restoreAtStart"} = 0 if (!defined($attr{$name}{"restoreAtStart"}));
  } else {
    $attr{$name}{"restoreAtStart"} = 1 if (!defined($attr{$name}{"restoreAtStart"}));
  }
  
  return undef;
}

sub MilightDevice_Init($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( AttrVal($hash->{NAME}, "gamma", "1.0") eq "1.0")
  {
    Log3 ($name, 5, $name." dimstep ".MilightDevice_roundfunc(100 / MilightDevice_DimSteps($hash))." / gamma 1.0");
  } else {
    $hash->{helper}->{COMMANDSET} =~ s/dim:slider,0,.*,100/dim:slider,0,1,100/g;
    $hash->{helper}->{COMMANDSET} =~ s/brightness:slider,0,.*,100/brightness:slider,0,1,100/g;
    Log3 $name, 5, $name." dimstep 1 / gamma ".AttrVal($hash->{NAME}, "gamma", "1.0");
    $hash->{helper}->{GAMMAMAP} = MilightDevice_CreateGammaMapping($hash, AttrVal($hash->{NAME}, "gamma", "1.0"));
  }

  # Colormap / Commandsets
  if (($hash->{LEDTYPE} eq 'RGBW') || ($hash->{LEDTYPE} eq 'RGB'))
  {
    my @a = split(',', "0,0,0,0,0,0");
    if ( defined( $attr{$name}{colorCast} ) )
    {
      @a = split(',', AttrVal($hash->{NAME}, "colorCast", "0,0,0,0,0,0"));
      @a = split(',', "0,0,0,0,0,0") unless (@a == 6);  
      foreach my $tc (@a)
      {
        @a = split(',', "0,0,0,0,0,0") unless ($tc =~ m/^\s*[\-]{0,1}[0-9]+[\.]{0,1}[0-9]*\s*$/g);
        @a = split(',', "0,0,0,0,0,0") if (abs($tc) >= 30);
      }
    }
    $hash->{helper}->{COLORMAP} = MilightDevice_ColorConverter($hash, @a);
  }

  return undef;
}


#####################################
# Undefine device
sub MilightDevice_Undef(@)
{
  my ($hash,$args) = @_;

  RemoveInternalTimer($hash);
  # Remove slot on bridge
  delete ($hash->{IODev}->{$hash->{SLOT}}->{NAME}) if ($hash->{SLOT} ne 'A');

  return undef;
}

#####################################
# Set functions
sub MilightDevice_Set(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;
  my $ramp = 0;
  my $flags = "";
  my $event = undef;
  my $usage = "set $name ...";

  if ($hash->{IODev}->{STATE} ne "ok" && $hash->{IODev}->{STATE} ne "Initialized") {
    readingsSingleUpdate($hash, "state", "error", 1);
    $flags = "q";
    $args[2] = "" if(!defined($args[2]));
    $args[2] .= "q" if ($args[2] !~ m/.*[qQ].*/);
    # return SetExtensions($hash, $hash->{helper}->{COMMANDSET}, $name, $cmd, @args);
    # IO error, we need to keep our current state settings!
  }
  # Commands that map to other commands
  if ($cmd eq "toggle")
  {
    $cmd = ReadingsVal($name,"state","on") ne "off" ? "off" :"on";
  }
  elsif ($cmd eq "white")
  {
    $cmd = "saturation";
    $args[0] = 0;
  }
  elsif ($cmd eq "toggleWhite")
  {
    $cmd = "saturation";
    $args[0] = (ReadingsVal($name,"saturation",100) > 0) ? 0 : 100;
  }

  # Commands
  if ($cmd eq 'on')
  {
    if (defined($args[0]))
    {
      return "Usage: set $name on [seconds(0..X)]" if ($args[0] !~ /^\d+$/);
      $ramp = $args[0];
    }
    elsif (defined($attr{$name}{defaultRampOn}))
    {
      $ramp = $attr{$name}{defaultRampOn};
    }
    return MilightDevice_RGBW_On($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_DimOn($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White' && AttrVal($hash->{NAME}, "dimOffWhite", 0) == 1);
    return MilightDevice_White_On($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_On($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGB');
  }

  elsif ($cmd eq 'off')
  {
    if (defined($args[0]))
    {
      return "Usage: set $name off [seconds(0..X)]" if ($args[0] !~ /^\d+$/);
      $ramp = $args[0];
    }
    elsif (defined($attr{$name}{defaultRampOff}))
    {
      $ramp = $attr{$name}{defaultRampOff};
    }
    return MilightDevice_RGBW_Off($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_DimOff($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White' && AttrVal($hash->{NAME}, "dimOffWhite", 0) == 1);
    return MilightDevice_White_Off($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_Off($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGB');
  }

  # Set HSV value
  elsif ($cmd eq 'hsv')
  {
    $usage = "Usage: set $name hsv <h(0..360)>,<s(0..100)>,<v(0..100)> [seconds(0..x)] [flags(l=long path|q=don't clear queue)]";
    $usage = "Usage: set $name hsv <h(3000=Warm..6500=Cool)>,<s(-)>,<v(0..100)> [seconds(0..x)] [flags(q=don't clear queue)]" if ($hash->{LEDTYPE} eq 'White');
    return $usage if ($args[0] !~ /^(\d{1,4}),(\d{1,3}),(\d{1,3})$/);
    my ($h, $s, $v) = ($1, $2, $3);
    return "Invalid hue ($h): valid range 0..360" if (!(($h >= 0) && ($h <= 360)) && ($hash->{LEDTYPE} ne 'White'));
    return "Invalid color temperature ($h): valid range 3000..6500" if (!(($h >= 3000) && ($h <= 6500)) && ($hash->{LEDTYPE} eq 'White'));
    return "Invalid saturation ($s): valid range 0..100" if (!(($s >= 0) && ($s <= 100)) && ($hash->{LEDTYPE} ne 'White'));
    return "Invalid brightness ($v): valid range 0..100" if !(($v >= 0) && ($v <= 100));
    if (defined($args[1]))
    {
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] > 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return $usage if ($args[2] !~ m/.*[lLqQ].*/); # Flags l=Long way round for transition, q=don't clear queue (add to end)
      $flags = $args[2];
    }
    return MilightDevice_White_Transition($hash, $h, 0, $v, $ramp, $flags) if($hash->{LEDTYPE} eq 'White');
    return MilightDevice_HSV_Transition($hash, $h, $s, $v, $ramp, $flags);
  }

  # Dim to a fixed percentage with transition if requested
  elsif ($cmd eq 'dim' || $cmd eq 'brightness')
  {
    $usage = "Usage: set $name dim <percent(0..100)> [seconds(0..x)] [flags(l=long path|q=don't clear queue)]";
    return $usage if (($args[0] !~ /^\d+$/) || ($args[0] < 0) || ($args[0] > 100)); # Decimal value for percent between 0..100
    if (defined($args[1]))
    {
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] > 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return $usage if ($args[2] !~ m/.*[lLqQ].*/); # Flags l=Long way round for transition, q=don't clear queue (add to end)
      $flags = $args[2];
    }
    return MilightDevice_RGBW_Dim($hash, $args[0], $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_Dim($hash, $args[0], $ramp, $flags) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_Dim($hash, $args[0], $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGB');
  }

  # Set night mode
  elsif ($cmd eq 'night')
  {
    if (defined($args[0]))
    {
      return "Usage: set $name night";
    }
    return MilightDevice_RGBW_Night($hash) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_Night($hash) if ($hash->{LEDTYPE} eq 'White');
  }

  # Set hue
  elsif ($cmd eq 'hue')
  {
    $usage = "Usage: set $name hue <h(0..360)> [seconds(0..x)] [flags(l=long path|q=don't clear queue)]";
    return $usage if (($args[0] !~ /^(\d+)$/) || ($args[0] < 0) || ($args[0] > 360));
    if (defined($args[1]))
    {
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] > 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return $usage if ($args[2] !~ m/.*[lLqQ].*/); # Flags l=Long way round for transition, q=don't clear queue (add to end)
      $flags = $args[2];
    }
    my $sat = ReadingsVal($hash->{NAME}, "saturation", 100);
    $sat = 100 if(ReadingsVal($hash->{NAME}, "saturation", 0) == 0);
    return MilightDevice_HSV_Transition($hash, $args[0], $sat, ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36)), $ramp, $flags);
  }
  
  # Set color temperature
  elsif ($cmd eq 'ct')
  {
    if (defined($args[0]))
    {
      return "Usage: set $name ct <3000=Warm..6500=Cool>" if (($args[0] !~ /^\d+$/) || ($args[0] < 2500 || $args[0] > 7000));
    }
    if (defined($args[1]))
    {
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] > 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return $usage if ($args[2] !~ m/.*[lLqQ].*/); # Flags l=Long way round for transition, q=don't clear queue (add to end)
      $flags = $args[2];
    }
    return MilightDevice_White_SetColourTemp($hash, $args[0], $ramp, $flags);
  }
  
  # Set RGB value
  elsif( $cmd eq "rgb")
  {
    $usage = "Usage: set $name rgb RRGGBB [seconds(0..x)] [flags(l=long path|q=don't clear queue)]";
    return $usage if ($args[0] !~ /^([0-9A-Fa-f]{1,2})([0-9A-Fa-f]{1,2})([0-9A-Fa-f]{1,2})$/);
    my( $r, $g, $b ) = (hex($1), hex($2), hex($3)); #change to color.pm?
    my( $h, $s, $v ) = Color::rgb2hsv($r/255.0,$g/255.0,$b/255.0);
    $h = MilightDevice_roundfunc($h * 360);
    $s = MilightDevice_roundfunc($s * 100);
    $v = MilightDevice_roundfunc($v * 100);
    if (defined($args[1]))
    {
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] > 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return $usage if ($args[2] !~ m/.*[lLqQ].*/); # Flags l=Long way round for transition, q=don't clear queue (add to end)
      $flags = $args[2];
    }
    return MilightDevice_HSV_Transition($hash, $h, $s, $v, $ramp, $flags);
  }

  # Dim up by 1 "dimStep" or by a percentage with transition if requested
  elsif ($cmd eq 'dimup')
  {
    $usage = "Usage: set $name dimup [percent change(0..100)] [seconds(0..x)]";
    my $percentChange = MilightDevice_roundfunc(100 / MilightDevice_DimSteps($hash)); # Default one dimStep
    if (defined($args[0]))
    { # Percent change (0..100%)
      return $usage if (($args[0] !~ /^\d+$/) || ($args[0] < 0) || ($args[0] > 100)); # Decimal value for percent between 0..100
      $percentChange = $args[0]; # Percentage to change, will be converted in dev specific function
    }
    if (defined($args[1]))
    { # Seconds for transition (0..x)
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] >= 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
      # Special case, if percent=100 adjust the ramp so it matches the actual amount required.
      # Eg. start: 80%. ramp 5seconds. Amount change: 100-80=20. Ramp time req: 20/100*5 = 1second.
      if ($percentChange == 100)
      {
        my $difference = $percentChange - ReadingsVal($hash->{NAME}, "brightness", 0);
        $ramp = ($difference/100) * $ramp;
        Log3 ($hash, 5, "$hash->{NAME}_Set: dimdown. Adjusted ramp to $ramp");
      }
    }
    
    my $newBrightness = ReadingsVal($hash->{NAME}, "brightness", 0) + $percentChange;
    $newBrightness = 100 if $newBrightness > 100;
    return MilightDevice_RGBW_Dim($hash, $newBrightness, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_Dim($hash, $newBrightness, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_Dim($hash, $newBrightness, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGB');
  }

  # Dim down by 1 "dimStep" or by a percentage with transition if requested
  elsif ($cmd eq 'dimdown')
  { 
    $usage = "Usage: set $name dimdown [percent change(0..100)] [seconds(0..x)]";
    my $percentChange = MilightDevice_roundfunc(100 / MilightDevice_DimSteps($hash)); # Default one dimStep
    if (defined($args[0]))
    { # Percent change (0..100%)
      return $usage if (($args[0] !~ /^\d+$/) || ($args[0] < 0) || ($args[0] > 100)); # Decimal value for percent between 0..100
      $percentChange = $args[0]; # Percentage to change, will be converted in dev specific function
    }
    if (defined($args[1]))
    { # Seconds for transition (0..x)
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] >= 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
      # Special case, if percent=100 adjust the ramp so it matches the actual amount required.
      # Eg. start: 80%. ramp 5seconds. Amount change: 80. Ramp time req: 80/100*5 = 4second.
      if ($percentChange == 100)
      {
        my $difference = ReadingsVal($hash->{NAME}, "brightness", 0);
        $ramp = ($difference/100) * $ramp;
        Log3 ($hash, 5, "$hash->{NAME}_Set: dimdown. Adjusted ramp to $ramp");
      }
    }
    
    my $newBrightness = ReadingsVal($hash->{NAME}, "brightness", 0) - $percentChange;
    $newBrightness = 0 if $newBrightness < 0;
    return MilightDevice_RGBW_Dim($hash, $newBrightness, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_Dim($hash, $newBrightness, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_Dim($hash, $newBrightness, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGB');
  }

  elsif ($cmd eq 'saturation')
  {
    $usage = "Usage: set $name saturation <h(0..100)> [seconds(0..x)] [flags(q=don't clear queue)]";
    return $usage if (($args[0] !~ /^\d+$/) || ($args[0] < 0) || ($args[0] > 100));
    if (defined($args[1]))
    {
      return $usage if (($args[1] !~ /^\d+$/) && ($args[1] > 0)); # Decimal value for ramp > 0
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return $usage if ($args[2] !~ m/.*[qQ].*/); # Flags q=don't clear queue (add to end)
      $flags = $args[2];
    }
    return MilightDevice_HSV_Transition($hash, ReadingsVal($hash->{NAME}, "hue", 0), $args[0], ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36)), $ramp, $flags);
  }
  
  elsif ($cmd eq 'discoModeUp')
  {
    return MilightDevice_RGBW_DiscoModeStep($hash, 1);
  }

  elsif ($cmd eq 'discoModeDown')
  {
    return MilightDevice_RGBW_DiscoModeStep($hash, 0);
  }
    
  elsif ($cmd eq 'discoSpeedUp')
  {
    return MilightDevice_RGBW_DiscoModeSpeed($hash, 1);
  }

  elsif ($cmd eq 'discoSpeedDown')
  {
    return MilightDevice_RGBW_DiscoModeSpeed($hash, 0);
  }
    
  elsif ($cmd eq 'restorePreviousState')
  {
    # Restore the previous state (as store in previous* readings)
    my ($h, $s, $v) = MilightDevice_HSVFromStr($hash, ReadingsVal($hash->{NAME}, "previousState", MilightDevice_HSVToStr($hash, 0, 0, 0)));
    if($v eq 0)
    {
      if (defined($attr{$name}{defaultRampOff}))
      {
        $ramp = $attr{$name}{defaultRampOff};
      }
      return MilightDevice_RGBW_Off($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGBW');
      return MilightDevice_White_DimOff($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White' && AttrVal($hash->{NAME}, "dimOffWhite", 0) == 1);
      return MilightDevice_White_Off($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'White');
      return MilightDevice_RGB_Off($hash, $ramp, $flags) if ($hash->{LEDTYPE} eq 'RGB');
    }
    MilightDevice_HSV_Transition($hash, $h, $s, $v, 0, '');
    return undef;
  }
  
  elsif ($cmd eq 'saveState')
  {
    # Save the hsv state as a string
    readingsSingleUpdate($hash, "savedState", MilightDevice_HSVToStr($hash, ReadingsVal($hash->{NAME}, "hue", 0), ReadingsVal($hash->{NAME}, "saturation", 0), ReadingsVal($hash->{NAME}, "brightness", 0)), 1);
    return undef;
  }
  elsif ($cmd eq 'restoreState')
  {
    my ($h, $s, $v) = MilightDevice_HSVFromStr($hash, ReadingsVal($hash->{NAME}, "savedState", MilightDevice_HSVToStr($hash, 0, 0, 0)));
    return MilightDevice_HSV_Transition($hash, $h, $s, $v, 0, '');
  }

  elsif ($cmd eq 'preset')
  {
    my $preset = "+";
    # Default to "preset +" if no args defined
    if (defined($args[0]))
    {
      return "Usage: set $name preset <0..X|+>" if ($args[0] !~ /^(\d+|\+)$/);
      $preset = $args[0];
    }
       
    # Get presets, if not defined default to 1 preset 0,0,100.
    my @presets = split(/ /, AttrVal($hash->{NAME}, "presets", MilightDevice_HSVToStr($hash, 0, 0, 100)));

    # Load the next preset (and loop back to the first) if "+" specified.
    if ("$preset" eq "+")
    {
      $preset = (ReadingsVal($hash->{NAME}, "lastPreset", -1) + 1);
      if ($#presets < $preset) { $preset = 0; }
    }
    return "No preset defined at index $preset" if ($#presets < $preset);

    # Update reading and load preset
    readingsSingleUpdate($hash, "lastPreset", $preset, 1);
    my ($h, $s, $v) = MilightDevice_HSVFromStr($hash, $presets[$preset]);
    return MilightDevice_HSV_Transition($hash, $h, $s, $v, 0, '');
  }

  elsif ($cmd eq 'pair')
  {
    if (defined($args[0]))
    {
      return "Usage: set $name pair [seconds(0..X)(default 3)]" if ($args[0] !~ /^\d+$/);
      $ramp = $args[0];
    }
    else { $ramp = 3; } # Default pair for 3 seconds

    MilightDevice_CmdQueue_Clear($hash);
    return MilightDevice_RGBW_Pair($hash, $ramp) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_Pair($hash, $ramp) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_Pair($hash, $ramp) if ($hash->{LEDTYPE} eq 'RGB');
  }

  elsif ($cmd eq 'unpair')
  {
    if (defined($args[0]))
    {
      return "Usage: set $name unpair [seconds(0..X)(default 3)]" if ($args[0] !~ /^\d+$/);
      $ramp = $args[0];
    }
    else { $ramp = 3; } # Default unpair for 3 seconds
    
    MilightDevice_CmdQueue_Clear($hash);
    return MilightDevice_RGBW_UnPair($hash, $ramp) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_UnPair($hash, $ramp) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_UnPair($hash, $ramp) if ($hash->{LEDTYPE} eq 'RGB');
  }

  return SetExtensions($hash, $hash->{helper}->{COMMANDSET}, $name, $cmd, @args);
}

#####################################
# Get functions
sub MilightDevice_Get(@)
{
  my ($hash, @args) = @_;

  my $name = $args[0];
  return "$name: get needs at least one parameter" if(@args < 2);

  my $cmd= $args[1];

  if($cmd eq "rgb" || $cmd eq "RGB") {
    return ReadingsVal($name, "rgb", "FFFFFF");
  }
  elsif($cmd eq "hsv") {
    return MilightDevice_HSVToStr($hash, ReadingsVal($hash->{NAME}, "ct", 3000), 0, ReadingsVal($hash->{NAME}, "brightness", 0)) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_HSVToStr($hash, ReadingsVal($hash->{NAME}, "hue", 0), ReadingsVal($hash->{NAME}, "saturation", 0), ReadingsVal($hash->{NAME}, "brightness", 0));
  }
  
  return "Unknown argument $cmd, choose one of rgb:noArg hsv:noArg";
}

#####################################
# Attribute functions
sub MilightDevice_Attr(@)
{
  my ($cmd, $device, $attribName, $attribVal) = @_;
  my $hash = $defs{$device};

  $attribVal = "" if (!defined($attribVal));

  Log3 ($hash, 4, "$hash->{NAME}_Attr: Cmd: $cmd; Attribute: $attribName; Value: $attribVal");

  if ($cmd eq 'set' && $attribName eq 'gamma')
  {
    return "gamma is required as numerical value with one decimal (eg. 0.5 or 2.2)" if ($attribVal !~ /^\d*\.\d*$/);
    $hash->{helper}->{GAMMAMAP} = MilightDevice_CreateGammaMapping($hash, $attribVal);
    if($attribVal ne "1.0")
    {
      $hash->{helper}->{COMMANDSET} =~ s/dim:slider,0,.*,100/dim:slider,0,1,100/g;
      $hash->{helper}->{COMMANDSET} =~ s/brightness:slider,0,.*,100/brightness:slider,0,1,100/g;
    }
  }
  # Allows you to modify the default number of dimSteps for a device
  elsif ($cmd eq 'set' && $attribName eq 'dimStep')
  {
    return "dimStep is required as numerical value [1..100]" if ($attribVal !~ /^\d*$/) || (($attribVal < 1) || ($attribVal > 100));
  }
  # Allows you to set a default transition time for on/off
  elsif ($cmd eq 'set' && (($attribName eq 'defaultRampOn') || ($attribName eq 'defaultRampOff')))
  {
    return "defaultRampOn/Off is required as numerical value [0..100]" if ($attribVal !~ /^[0-9]*\.?[0-9]*$/) || (($attribVal < 0) || ($attribVal > 100));
  }
  # List of presets in hsv separated by space.  Loaded by set command preset X
  elsif ($cmd eq 'set' && ($attribName eq 'presets'))
  {
    return "presets is required as space separated list of hsv(h,s,v) (eg. 0,0,100, 0,100,50)" if ($attribVal !~ /^[(\d{1,3}),(\d{1,3}),(\d{1,3})(?:$|\s)]*$/);
  }
  elsif ($cmd eq 'set' && $attribName eq 'colorCast')
  {
    return "colorCast: only works with RGB(W) devices" if ($hash->{LEDTYPE} eq 'White');
    my @a = split(',', $attribVal);
    my $msg =  "colorCast: correction requires red, yellow, green ,cyan, blue, magenta (each in a range of -29 .. 29)";
    return $msg unless (@a == 6);  
    foreach my $tc (@a)
    {
      return $msg unless ($tc =~ m/^\s*[\-]{0,1}[0-9]+[\.]{0,1}[0-9]*\s*$/g);
      return $msg if (abs($tc) >= 30);
    }
    $hash->{helper}->{COLORMAP} = MilightDevice_ColorConverter($hash, @a);

    #MilightDevice_RGB_ColorConverter($hash, @a);
    if ($init_done && !(@{$hash->{helper}->{cmdQueue}} > 0))
    {
      my $hue = $hash->{READINGS}->{hue}->{VAL};
      my $sat = $hash->{READINGS}->{saturation}->{VAL};
      my $val = $hash->{READINGS}->{brightness}->{VAL};
      return MilightDevice_RGBW_SetHSV($hash, $hue, $sat, $val, 1) if ($hash->{LEDTYPE} eq 'RGBW');
      return MilightDevice_RGB_SetHSV($hash, $hue, $sat, $val, 1) if ($hash->{LEDTYPE} eq 'RGB');
    }
  }
  elsif ($cmd eq 'set' && $attribName eq 'defaultBrightness')
  {
    return "defaultBrighness: has to be between ".MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash))." and 100" if ($attribVal < MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)) || $attribVal > 100);
  }

  return undef;
}

#####################################
# Notify functions
sub MilightDevice_Notify(@)
{
  my ($hash,$dev) = @_;
  return MilightDevice_Restore($hash);
}

#####################################
# Restore HSV settings from readings.
# Called after initialization to synchronise lamp state with fhem.
sub MilightDevice_Restore(@)
{
  my ($hash) = @_;

  return if ($hash->{INIT});
  if ($init_done)
  {
    return if (AttrVal($hash->{NAME}, "restoreAtStart", 0) == 0);
    Log3 ($hash, 4, "$hash->{NAME}_Restore: Restoring saved HSV values");
    $hash->{INIT} = 1;
    # Initialize device
    MilightDevice_Init($hash);
    # Clear inProgress flag: MJW Do we still need to do this?
    readingsSingleUpdate($hash, "transitionInProgress", 0, 1);
    # Default to OFF if not defined
    my ($hue, $sat, $val);
    $hue = ReadingsVal($hash->{NAME}, "hue", 0);
    $sat = ReadingsVal($hash->{NAME}, "saturation", 0);
    $val = ReadingsVal($hash->{NAME}, "brightness", 0);

    # Restore state
    return MilightDevice_RGBW_SetHSV($hash, $hue, $sat, $val, 1) if ($hash->{LEDTYPE} eq 'RGBW');
    return MilightDevice_White_SetHSV($hash, $hue, $sat, $val, 1) if ($hash->{LEDTYPE} eq 'White');
    return MilightDevice_RGB_SetHSV($hash, $hue, $sat, $val, 1) if ($hash->{LEDTYPE} eq 'RGB');
  }
}

###############################################################################
# device specific controller functions RGB
# LED Strip or bulb, no white, controller V2+. No longer manufactured Jan2014
###############################################################################
sub MilightDevice_RGB_Pair(@)
{
  my ($hash, $numSeconds) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);
  Log3 ($hash, 4, "$hash->{NAME}_RGB_Pair: RGB LED slot $hash->{SLOT} pair $numSeconds s"); 
  # DISCO SPEED FASTER 0x25 (SYNC/PAIR RGB Bulb within 2 seconds of Wall Switch Power being turned ON)
  my $ctrl = "\x25\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 1000, undef);
  }
  return undef;
}

#####################################
sub MilightDevice_RGB_UnPair(@)
{
  my ($hash) = @_;
  my $numSeconds = 8;
  Log3 ($hash, 4, "$hash->{NAME}_RGB_UnPair: RGB LED slot $hash->{SLOT} unpair $numSeconds s"); 
  # DISCO SPEED FASTER 0x25 (SYNC/PAIR RGB Bulb within 2 seconds of Wall Switch Power being turned ON)
  my $ctrl = "\x25\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
  }
  return undef;
}

#####################################
sub MilightDevice_RGB_On(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  my $v = AttrVal($hash->{NAME}, "defaultBrightness", 36);
  Log3 ($hash, 4, "$hash->{NAME}_RGB_On: RGB slot $hash->{SLOT} set on $ramp");
  # Switch on with same brightness it was switched off with, or max if undefined.
  if (ReadingsVal($hash->{NAME}, "state", "off") eq "off")
  {
    $v = ReadingsVal($hash->{NAME}, "brightness_on", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  else
  {
    $v = ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }

  # When turning on, make sure we request at least minimum dim step.
  if ($v < MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)))
  {
    $v = MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash));
  }

  return MilightDevice_RGB_Dim($hash, $v, $ramp, $flags); 
}

#####################################
sub MilightDevice_RGB_Off(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_RGB_Off: RGB slot $hash->{SLOT} set off $ramp");
  # Store value of brightness before turning off
  # "on" will be of the form "on 50" where 50 is current dimlevel
  if (ReadingsVal($hash->{NAME}, "state", "off") ne "off")
  {
    readingsSingleUpdate($hash, "brightness_on", ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36)), 1);
    MilightDevice_BridgeDevices_Update($hash, "brightness_on") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1);   

    # Dim down to min brightness then send off command (avoid flicker on turn on)
    MilightDevice_RGB_Dim($hash, MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)), $ramp, $flags);
    return MilightDevice_RGB_Dim($hash, 0, 0, 'qP');
  }
  else
  {
    # If we are already off just send the off command again
    return MilightDevice_RGB_Dim($hash, 0, 0, 'P');
  }
}

#####################################
sub MilightDevice_RGB_Dim(@)
{
  my ($hash, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($hash->{NAME}, "hue", 0);
  my $s = ReadingsVal($hash->{NAME}, "saturation", 0);
  Log3 ($hash, 4, "$hash->{NAME}_RGB_Dim: RGB slot $hash->{SLOT} dim $level $ramp $flags"); 
  return MilightDevice_HSV_Transition($hash, $h, $s, $level, $ramp, $flags);
}

#####################################
sub MilightDevice_RGB_SetHSV(@)
{
  my ($hash, $hue, $sat, $val, $repeat) = @_;
  Log3 ($hash, 4, "$hash->{NAME}_RGB_setHSV: RGB slot $hash->{SLOT} set h:$hue, s:$sat, v:$val");
  $sat = 100;
  MilightDevice_SetHSV_Readings($hash, $hue, $sat, $val);

  # apply gamma correction
  my $gammaVal = $hash->{helper}->{GAMMAMAP}[$val];

  # convert to device specs
  my ($cv, $cl, $wl) = MilightDevice_RGB_ColorConverter($hash, $hue, $sat, $gammaVal);
  Log3 ($hash, 4, "$hash->{NAME}_RGB_setHSV: RGB slot $hash->{SLOT} set levels: $cv, $cl, $wl");
  
  $repeat = 1 if (!defined($repeat));
  
  # On first load, colorLevel won't be defined, define it.
  $hash->{helper}->{colorLevel} = $cl if (!defined($hash->{helper}->{colorLevel}));

  # NOTE: All commands sent twice for reliability (it's udp with no feedback)
  
  if (($wl < 1) && ($cl < 1)) # off
  {
    # if no white or colour switch off
    IOWrite($hash, "\x21\x00\x55"); # switch off
    $hash->{helper}->{colorLevel} = 0;  
  }
  else # on
  {
    if (($wl > 0) || ($cl > 0)) # Colour/White on
    {
      IOWrite($hash, "\x22\x00\x55"); # switch on
      IOWrite($hash, "\x20".chr($cv)."\x55"); # set color
      if ($repeat eq 1) {
        IOWrite($hash, "\x22\x00\x55"); # switch on
        IOWrite($hash, "\x20".chr($cv)."\x55"); # set color
      }
      
      # cl decrease
      if ($hash->{helper}->{colorLevel} > $cl)
      {
        for (my $i=$hash->{helper}->{colorLevel}; $i > $cl; $i--) 
        {
          IOWrite($hash, "\x24\x00\x55"); # brightness down
          $hash->{helper}->{colorLevel} = $i - 1;
        }
      }
      # cl increase
      if ($hash->{helper}->{colorLevel} < $cl)
      {
        for (my $i=$hash->{helper}->{colorLevel}; $i < $cl; $i++)
        {
          IOWrite($hash, "\x23\x00\x55"); # brightness up
          $hash->{helper}->{colorLevel} = $i + 1;
        }
      }
    }
  }

  return undef;
}

#####################################
sub MilightDevice_RGB_ColorConverter(@)
{
  my ($hash, $h, $s, $v) = @_;

  my $color = $hash->{helper}->{COLORMAP}[$h % 360];
  
  # there are 0..9 dim level, setup correction
  my $valueSpread = MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash));
  my $totalVal = MilightDevice_roundfunc($v / $valueSpread);
  # saturation 100..50: color full, white increase. 50..0 white full, color decrease
  my $colorVal = ($s >= 50) ? $totalVal : int(($s / 50 * $totalVal) +0.5);
  my $whiteVal = ($s >= 50) ? int(((100-$s) / 50 * $totalVal) +0.5) : $totalVal;
  return ($color, $colorVal, $whiteVal);
}

###############################################################################
# RGBW device specific: Bridge V3+ only. 
# Available as GU10, E14, E27, B22, led strip controller...
###############################################################################
sub MilightDevice_RGBW_Pair(@)
{
  my ($hash, $numSeconds) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);
  Log3 ($hash, 4, "$hash->{NAME}_RGBW_Pair: $hash->{LEDTYPE} at $hash->{CONNECTION}, slot $hash->{SLOT}: pair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd;
  # Send on command once a second
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 1000, undef);
  }
  return undef;
}

#####################################
sub MilightDevice_RGBW_UnPair(@)
{
  my ($hash, $numSeconds, $releaseFromSlot) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);
  Log3 ($hash, 4, "$hash->{NAME}_RGBW_UnPair: $hash->{LEDTYPE} at $hash->{CONNECTION}, slot $hash->{SLOT}: unpair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd;

  # Send on command every 200ms
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
  }
  return undef;
}

#####################################
sub MilightDevice_RGBW_On(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  my $v = AttrVal($hash->{NAME}, "defaultBrightness", 36);
  Log3 ($hash, 4, "$hash->{NAME}_RGBW_On: Set ON; Ramp: $ramp");
  # Switch on with same brightness it was switched off with, or max if undefined.
  if (ReadingsVal($hash->{NAME}, "state", "off") eq "off" || ReadingsVal($hash->{NAME}, "state", "off") eq "night")
  {
    $v = ReadingsVal($hash->{NAME}, "brightness_on", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  else
  {
    $v = ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  # When turning on, make sure we request at least minimum dim step.
  if ($v < MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)))
  {
    $v = MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash));
  }

  return MilightDevice_RGBW_Dim($hash, $v, $ramp, $flags); 
}

#####################################
sub MilightDevice_RGBW_Off(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_RGBW_Off: Set OFF; Ramp: $ramp");
  # Store value of brightness before turning off
  # "on" will be of the form "on 50" where 50 is current dimlevel
  if (ReadingsVal($hash->{NAME}, "state", "off") ne "off" && ReadingsVal($hash->{NAME}, "state", "off") ne "night")
  {
    readingsSingleUpdate($hash, "brightness_on", ReadingsVal($hash->{NAME}, "brightness", 0), 1);
    MilightDevice_BridgeDevices_Update($hash, "brightness_on") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1);  
 
    # Dim down to min brightness then send off command (avoid flicker on turn on)
    MilightDevice_RGBW_Dim($hash, MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)), $ramp, $flags);
    return MilightDevice_RGBW_Dim($hash, 0, 0, 'qP');
  }
  else
  {
    # If we are already off just send the off command again
    return MilightDevice_RGBW_Dim($hash, 0, 0, 'P');
  }
}

#####################################
sub MilightDevice_RGBW_Night(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_RGBW_Night: Set NIGHTMODE");
  if(ReadingsVal($hash->{NAME}, "state", "off") ne "night") {
    if (ReadingsVal($hash->{NAME}, "brightness", 0) > 0)
    {
      readingsSingleUpdate($hash, "brightness_on", ReadingsVal($hash->{NAME}, "brightness", 4), 1);
      MilightDevice_BridgeDevices_Update($hash, "brightness_on") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
    }  
    IOWrite($hash, @RGBWCmdsOff[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd); # off
  }
  IOWrite($hash, @RGBWCmdsNt[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd); # night
  readingsSingleUpdate($hash, "state", "night", 1);
  MilightDevice_BridgeDevices_Update($hash, "state") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
  return undef;
}

#####################################
sub MilightDevice_RGBW_Dim(@)
{
  my ($hash, $v, $ramp, $flags) = @_;
  my $h = ReadingsVal($hash->{NAME}, "hue", 0);
  my $s = ReadingsVal($hash->{NAME}, "saturation", 0);
  Log3 ($hash, 4, "$hash->{NAME}_RGBW_Dim: Brightness: $v; Ramp: $ramp; Flags: ". $flags || ''); 
  return MilightDevice_HSV_Transition($hash, $h, $s, $v, $ramp, $flags);
}

#####################################
sub MilightDevice_RGBW_SetHSV(@)
{
  my ($hash, $hue, $sat, $val, $repeat) = @_;
  my ($cl, $wl);
  
  $repeat = 1 if (!defined($repeat));

  my $cv = $hash->{helper}->{COLORMAP}[$hue % 360];

  #check dim levels to decide wether to change color or brightness first
  my $dimup = 0;
  $dimup = 1 if($val > ReadingsVal($hash->{NAME}, "brightness", 100));

  # apply gamma correction
  my $gammaVal = $hash->{helper}->{GAMMAMAP}[$val];

  # brightness 2..27 (x02..x1b) | 25 dim levels
  
  my $cf = MilightDevice_roundfunc((($gammaVal / 100) * MilightDevice_DimSteps($hash)) + 1);
  if ($sat < 20) 
  {
    $wl = $cf;
    $cl = 0;
    $sat = 0;
  }
  else
  {
    $cl = $cf;
    $wl = 0;
    $sat = 100;
  }
  
  Log3 ($hash, 5, "MilightDevice_RGBW_SetHSV:  h:$hue s:$sat v:$val / cv:$cv wl:$wl cl:$cl ");
  # Set readings in FHEM
  MilightDevice_SetHSV_Readings($hash, $hue, $sat, $val);

  # NOTE: All commands sent twice for reliability (it's udp with no feedback)

  # Off is shifted to "2" above so check for < 2
  if (($wl < 2) && ($cl < 2)) # off
  {
    IOWrite($hash, @RGBWCmdsOff[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd); # group off
    IOWrite($hash, @RGBWCmdsOff[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if ($repeat eq 1); # group off
    $hash->{helper}->{whiteLevel} = 0;
    $hash->{helper}->{colorLevel} = 0;
  }
  else # on
  {
    if ($wl > 0) # white
    {
      IOWrite($hash, @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if (($wl > 0) || ($cl > 0)); # group on
      IOWrite($hash, @RGBWCmdsWT[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd); # white
      IOWrite($hash, $RGBWCmdBri.chr($wl).$RGBWCmdEnd); # brightness
      if ($repeat eq 1) {
        IOWrite($hash, @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if (($wl > 0) || ($cl > 0)); # group on
        IOWrite($hash, @RGBWCmdsWT[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd); # white
        IOWrite($hash, $RGBWCmdBri.chr($wl).$RGBWCmdEnd); # brightness
      }
    }
    elsif ($cl > 0) # color
    {
      IOWrite($hash, @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if (($wl > 0) || ($cl > 0)); # group on
      if($dimup)
      {
      IOWrite($hash, $RGBWCmdCol.chr($cv).$RGBWCmdEnd); # color
      IOWrite($hash, $RGBWCmdBri.chr($cl).$RGBWCmdEnd); # brightness
      } else {
        IOWrite($hash, $RGBWCmdBri.chr($cl).$RGBWCmdEnd); # brightness
        IOWrite($hash, $RGBWCmdCol.chr($cv).$RGBWCmdEnd); # color
      }
      if ($repeat eq 1) {
        IOWrite($hash, @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if (($wl > 0) || ($cl > 0)); # group on
        if($dimup)
        {
        IOWrite($hash, $RGBWCmdCol.chr($cv).$RGBWCmdEnd); # color
        IOWrite($hash, $RGBWCmdBri.chr($cl).$RGBWCmdEnd); # brightness
        } else {
          IOWrite($hash, $RGBWCmdBri.chr($cl).$RGBWCmdEnd); # brightness
          IOWrite($hash, $RGBWCmdCol.chr($cv).$RGBWCmdEnd); # color
        }
      }
    }

    $hash->{helper}->{colorValue} = $cv;
    $hash->{helper}->{colorLevel} = $cl;
    $hash->{helper}->{whiteLevel} = $wl;
  }
  
  return undef;
}

####################################
# RGB and RGBW types
sub MilightDevice_RGBW_DiscoModeStep(@)
{
  my ($hash, $step) = @_;
  
  MilightDevice_CmdQueue_Clear($hash);
  
  $step = 0 if ($step < 0);
  $step = 1 if ($step > 1);
  
  # Set readings in FHEM
  MilightDevice_SetDisco_Readings($hash, $step, ReadingsVal($hash->{NAME}, 'discoSpeed', 5));

  # NOTE: Only sending commands once, because it makes changes on each successive command
  IOWrite($hash, @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if (($hash->{LEDTYPE} eq 'RGBW')); # group on
  IOWrite($hash, "\x22\x00\x55") if (($hash->{LEDTYPE} eq 'RGB')); # switch on

  if ($step == 1)
  {
    IOWrite($hash, $RGBWCmdDiscoUp."\x00".$RGBWCmdEnd) if (($hash->{LEDTYPE} eq 'RGBW')); # discoMode step up
    IOWrite($hash, "\x27\x00\x55") if (($hash->{LEDTYPE} eq 'RGB')); # discoMode step up
  }
  elsif ($step == 0)
  {
    IOWrite($hash, "\x28\x00\x55") if (($hash->{LEDTYPE} eq 'RGB')); # discoMode step down
    # There is no discoMode step down for RGBW
  }
  
  return undef;
}

#####################################
# RGB and RGBW types
sub MilightDevice_RGBW_DiscoModeSpeed(@)
{
  my ($hash, $speed) = @_;

  MilightDevice_CmdQueue_Clear($hash);
  
  $speed = 0 if ($speed < 0);
  $speed = 1 if ($speed > 1);
  
  # Set readings in FHEM
  MilightDevice_SetDisco_Readings($hash, ReadingsVal($hash->{NAME}, 'discoMode', 1), $speed);

  # NOTE: Only sending commands once, because it makes changes on each successive command
  IOWrite($hash, @RGBWCmdsOn[$hash->{SLOTID} -5]."\x00".$RGBWCmdEnd) if (($hash->{LEDTYPE} eq 'RGBW')); # group on
  IOWrite($hash, "\x22\x00\x55") if (($hash->{LEDTYPE} eq 'RGB')); # switch on

  if ($speed == 1)
  {
    IOWrite($hash, $RGBWCmdDiscoInc."\x00".$RGBWCmdEnd) if ($hash->{LEDTYPE} eq 'RGBW'); # discoMode speed up
    IOWrite($hash, "\x25\x00\x55") if ($hash->{LEDTYPE} eq 'RGB'); # discoMode speed up
  }
  elsif ($speed == 0)
  {
    IOWrite($hash, $RGBWCmdDiscoDec."\x00".$RGBWCmdEnd) if ($hash->{LEDTYPE} eq 'RGBW'); # discoMode speed down
    IOWrite($hash, "\x26\x00\x55") if ($hash->{LEDTYPE} eq 'RGB'); # discoMode speed down
  }
  
  return undef;
}

###############################################################################
# White device specific: Warm/Cold White with Dim - Bridge V2+
###############################################################################
sub MilightDevice_White_Pair(@)
{
  my ($hash, $numSeconds) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);

  Log3 ($hash, 4, "$hash->{NAME}_White_Pair: $hash->{LEDTYPE} at $hash->{CONNECTION}, slot $hash->{SLOT}: pair $numSeconds");
  # find my slot and get my group-all-on cmd
  my $ctrl = @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd;
  
  # Send on command once a second
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 1000, undef);
  }
  return undef;
}

#####################################
sub MilightDevice_White_UnPair(@)
{
  my ($hash, $numSeconds, $releaseFromSlot) = @_;
    $numSeconds = 3 if (($numSeconds || 0) == 0);
    
  Log3 ($hash, 4, "$hash->{NAME}_White_UnPair: $hash->{LEDTYPE} at $hash->{CONNECTION}, slot $hash->{SLOT}: unpair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd;
  
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
    MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
  }
  return undef;
}

#####################################
sub MilightDevice_White_On(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  my $v = AttrVal($hash->{NAME}, "defaultBrightness", 36);
  Log3 ($hash, 4, "$hash->{NAME}_White_On: Set ON: Ramp: $ramp"); 
  # Switch on with same brightness it was switched off with, or max if undefined.
  if (ReadingsVal($hash->{NAME}, "state", "off") eq "off" || ReadingsVal($hash->{NAME}, "state", "off") eq "night")
  {
    $v = ReadingsVal($hash->{NAME}, "brightness_on", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  else
  {
    $v = ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  # When turning on, make sure we request at least minimum dim step.
  if ($v < MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)))
  {
    $v = MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash));
  }
  return MilightDevice_White_Dim($hash, $v, $ramp, $flags); 
}

#####################################
sub MilightDevice_White_Off(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_White_Off: Set OFF; Ramp: $ramp"); 
  # Store value of brightness before turning off
  # "on" will be of the form "on 50" where 50 is current dimlevel
  if (ReadingsVal($hash->{NAME}, "state", "off") ne "off" && ReadingsVal($hash->{NAME}, "state", "off") ne "night")
  {
    if (ReadingsVal($hash->{NAME}, "brightness", 0) > 0)
    {
      readingsSingleUpdate($hash, "brightness_on", ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36)), 1);
      MilightDevice_BridgeDevices_Update($hash, "brightness_on") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
    }
    # Dim down to min brightness then send off command (avoid flicker on turn on)
    MilightDevice_White_Dim($hash, MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)), $ramp, $flags);
    return MilightDevice_White_Dim($hash, 0, 0, 'q');
  }
  else
  {
    # If we are already off just send the off command again
    return MilightDevice_White_Dim($hash, 0, 0, 'P');
  }
}

#####################################
sub MilightDevice_White_DimOff(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_White_DimOff: Set OFF; Ramp: $ramp"); 

  if (ReadingsVal($hash->{NAME}, "brightness", 0) > 0)
  {
    readingsSingleUpdate($hash, "brightness_on", ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36)), 1);
    MilightDevice_BridgeDevices_Update($hash, "brightness_on") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
  }

  for (my $i = 0; $i < 12; $i++)
  { 
    IOWrite($hash, @WhiteCmdBriDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
  }
  IOWrite($hash, @WhiteCmdsOff[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
  return MilightDevice_White_Dim($hash, 0, 0, 'q');
}


#####################################
sub MilightDevice_White_DimOn(@)
{
  my ($hash, $ramp, $flags) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_White_DimOn: Set ON; Ramp: $ramp"); 
  my $v = AttrVal($hash->{NAME}, "defaultBrightness", 36);

  if (ReadingsVal($hash->{NAME}, "state", "off") eq "off" || ReadingsVal($hash->{NAME}, "state", "off") eq "night")
  {
    $v = ReadingsVal($hash->{NAME}, "brightness_on", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  else
  {
    $v = ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36));
  }
  # When turning on, make sure we request at least minimum dim step.
  if ($v < MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)))
  {
    $v = MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash));
  }

  MilightDevice_White_Dim($hash, $v, $ramp, $flags);
  for (my $i = 0; $i < ($v/(100/MilightDevice_DimSteps($hash))); $i++)
  { 
    #IOWrite($hash, @WhiteCmdBriUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
  }
  #$ctrl = @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd;
  #MilightDevice_CmdQueue_Add($hash, undef, undef, undef, $ctrl, 200, undef);
  #return MilightDevice_White_Dim($hash, 0, 0, 'q');
}

#####################################
sub MilightDevice_White_Night(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "$hash->{NAME}_White_NIGHT: Set NIGHTMODE"); 
  if(ReadingsVal($hash->{NAME}, "state", "off") ne "night") 
  {
    if (ReadingsVal($hash->{NAME}, "brightness", 0) > 0)
    {
      readingsSingleUpdate($hash, "brightness_on", ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36)), 1);
      MilightDevice_BridgeDevices_Update($hash, "brightness_on") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
    }
    IOWrite($hash, @WhiteCmdsOff[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # off
  }
  IOWrite($hash, @WhiteCmdsNt[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # night
  readingsSingleUpdate($hash, "state", "night", 1);
  MilightDevice_BridgeDevices_Update($hash, "state") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
  return undef;
}

#####################################
sub MilightDevice_White_Dim(@)
{
  my ($hash, $level, $ramp, $flags) = @_;
  Log3 ($hash, 4, "$hash->{NAME}_White_Dim: Brightness: $level; Ramp: $ramp; Flags: $flags"); 
  return MilightDevice_HSV_Transition($hash, ReadingsVal($hash->{NAME}, "ct", 3000), 0, $level, $ramp, $flags);
}

#####################################
# $hue is colourTemperature, $val is brightness
sub MilightDevice_White_SetHSV(@)
{
  my ($hash, $hue, $sat, $val, $repeat) = @_;
  my $name = $hash->{NAME};
  
  $repeat = 1 if (!defined($repeat));

    
  # Validate brightness
  $val = 100 if ($val > 100);
  $val = 0 if ($val < 0);
  # Validate colour temperature
  $hue = 6500 if ($hue > 6500);
  $hue = 3000 if ($hue < 3000);
  my $oldHueStep = MilightDevice_White_ct_hwValue($hash, ReadingsVal($hash->{NAME}, "ct", 6500));
  my $newHueStep = MilightDevice_White_ct_hwValue($hash, $hue);
  $hue = MilightDevice_White_ct_hwValue($hash, $newHueStep);
  # Set colour temperature
  if ($oldHueStep != $newHueStep)
  {
    IOWrite($hash, @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on
    if ($oldHueStep > $newHueStep)
    {
      Log3 ($hash, 4, "$hash->{NAME}_setColourTemp: Decrease from $oldHueStep to $newHueStep");
      for (my $i=$oldHueStep; $i > $newHueStep; $i--)
      {
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # Cooler (colourtemp up)
      }
    }
    elsif ($oldHueStep < $newHueStep)
    {
      Log3 ($hash, 4, "$hash->{NAME}_setColourTemp: Increase from $oldHueStep to $newHueStep");
      for (my $i=$oldHueStep; $i < $newHueStep; $i++)
      {
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # Warmer (colourtemp down)
      }
    }
    if(AttrVal($hash->{NAME}, "dimOffWhite", 0) == 1)
    {
      if($newHueStep == 1)
      {
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      }
      elsif($newHueStep == 11)
      {
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      }
    }
  }


  # apply gamma correction
  my $gammaVal = $hash->{helper}->{GAMMAMAP}[$val];
  
  # Calculate brightness hardware value (10 steps / 11 positions for white)
  my $maxWl = (100 / MilightDevice_DimSteps($hash));
  my $wl = MilightDevice_roundfunc($gammaVal / $maxWl);

  # On first load, whiteLevel won't be defined, define it.
  $hash->{helper}->{whiteLevel} = $wl if (!defined($hash->{helper}->{whiteLevel}));

  if (ReadingsVal($hash, "brightness", 0) > 0)
  {
    # We are transitioning from on to off so store new value of wl and stop brightness up/down being triggered below
    $hash->{helper}->{whiteLevel} = $wl;
  }

  # Store new values for colourTemperature and Brightness
  MilightDevice_SetHSV_Readings($hash, $hue, 0, $val);

  # Make sure we actually send off command if we should be off
  if ($wl == 0)
  {
    IOWrite($hash, @WhiteCmdsOff[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group off
    IOWrite($hash, @WhiteCmdsOff[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd) if ($repeat eq 1); # group off
    Log3 ($hash, 4, "$hash->{NAME}_White_setHSV: OFF");
  }
  elsif ($wl == $maxWl)
  {
    IOWrite($hash, @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on
    IOWrite($hash, @WhiteCmdsOnFull[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on full
    if ($repeat eq 1) {
      IOWrite($hash, @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on
      IOWrite($hash, @WhiteCmdsOnFull[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on full
    }
    Log3 ($hash, 4, "$hash->{NAME}_White_setHSV: Full Brightness");
  }
  else
  {
    # Not off or MAX brightness, so make sure we are on
    IOWrite($hash, @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on
    IOWrite($hash, @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd) if ($repeat eq 1); # group on

    if ($hash->{helper}->{whiteLevel} > $wl)
    {
      # Brightness level should be decreased
      Log3 ($hash, 4, "$hash->{NAME}_White_setHSV: Brightness decrease from $hash->{helper}->{whiteLevel} to $wl");
      for (my $i=$hash->{helper}->{whiteLevel}; $i > $wl; $i--) 
      {
        IOWrite($hash, @WhiteCmdBriDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # brightness down
        $hash->{helper}->{whiteLevel} = $i - 1;
      }
    }
    elsif ($hash->{helper}->{whiteLevel} < $wl)
    {
      # Brightness level should be increased
      $hash->{helper}->{whiteLevel} = 1 if ($hash->{helper}->{whiteLevel} == 0);
      Log3 ($hash, 4, "$hash->{NAME}_White_setHSV: Brightness increase from $hash->{helper}->{whiteLevel} to $wl");
      for (my $i=$hash->{helper}->{whiteLevel}; $i < $wl; $i++) 
      {
        IOWrite($hash, @WhiteCmdBriUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # brightness up
        $hash->{helper}->{whiteLevel} = $i + 1;
      }
    }
    else
    {
      Log3 ($hash, 4, "$hash->{NAME}_White_setHSV: ON");
    }
  }

  $hash->{helper}->{whiteLevel} = $wl;
    
  return undef;
}

#####################################
sub MilightDevice_White_SetColourTemp(@)
{
  # $hue is colourTemperature (1-11), $val is brightness (0-100%)
  my ($hash, $hue) = @_;
  my $name = $hash->{NAME};
  
  MilightDevice_CmdQueue_Clear($hash);

  # Save old value of ct
  my $oldHue = MilightDevice_White_ct_hwValue($hash, ReadingsVal($hash->{NAME}, "ct", 6500));
  # Store new values for colourTemperature and Brightness
  MilightDevice_SetHSV_Readings($hash, $hue, 0, ReadingsVal($hash->{NAME}, "brightness", AttrVal($hash->{NAME}, "defaultBrightness", 36) ) ); 
  # Validate colourTemperature (11 steps)
  # 3000-6500 (350 per step) Warm-White to Cool White
  # Maps backwards 1=6500 11=3000
  $hue = MilightDevice_White_ct_hwValue($hash, $hue);
  
  Log3 ($hash, 4, "$hash->{NAME}_setColourTemp: $oldHue to $hue");
  
  # Set colour temperature
  if ($oldHue != $hue)
  {
    IOWrite($hash, @WhiteCmdsOn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # group on
    if ($oldHue > $hue)
    {
      Log3 ($hash, 4, "$hash->{NAME}_setColourTemp: Decrease from $oldHue to $hue");
      for (my $i=$oldHue; $i > $hue; $i--)
      {
        IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # Cooler (colourtemp up)
      }
    }
    elsif ($oldHue < $hue)
    {
      Log3 ($hash, 4, "$hash->{NAME}_setColourTemp: Increase from $oldHue to $hue");
      for (my $i=$oldHue; $i < $hue; $i++)
      {
        IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd); # Warmer (colourtemp down)
      }
    }
  }

  if(AttrVal($hash->{NAME}, "dimOffWhite", 0) == 1)
  {
    if($hue == 1) 
    {
      IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColDn[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
    }
    elsif($hue == 11) 
    {
      IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
      IOWrite($hash, @WhiteCmdColUp[$hash->{SLOTID} -1]."\x00".$WhiteCmdEnd);
    }
  }
  return undef;
}

# Convert from 3000-6500 colourtemperature to hardware value
sub MilightDevice_White_ct_hwValue(@)
{
  my ($hash, $ct) = @_;
  
  # Couldn't get switch statement to work so using if
  if ($ct == 11) { return 3000; }
  elsif ($ct == 10) { return 3350; }
  elsif ($ct == 9) { return 3700; }
  elsif ($ct == 8) { return 4050; }
  elsif ($ct == 7) { return 4400; }
  elsif ($ct == 6) { return 4750; }
  elsif ($ct == 5) { return 5100; }
  elsif ($ct == 4) { return 5450; }
  elsif ($ct == 3) { return 5800; }
  elsif ($ct == 2) { return 6150; }
  elsif ($ct == 1) { return 6500; }
  
  elsif ($ct < 3350) { return 11; }
  elsif ($ct < 3700) { return 10; }
  elsif ($ct < 4050) { return 9; }
  elsif ($ct < 4400) { return 8; }
  elsif ($ct < 4750) { return 7; }
  elsif ($ct < 5100) { return 6; }
  elsif ($ct < 5450) { return 5; }
  elsif ($ct < 5800) { return 4; }
  elsif ($ct < 6150) { return 3; }
  elsif ($ct < 6500) { return 2; }
  return 1;
}

###############################################################################
# Device independent routines
###############################################################################
sub MilightDevice_HSVFromStr(@)
{
  # Convert HSV values from string in format "h,s,v"
  my ($hash, @args) = @_;
  
  if ((!defined($args[0])) || ($args[0] !~ /^(\d{1,4}),(\d{1,3}),(\d{1,3})$/))
  {
    Log3 ($hash, 3, "MilightDevice_HSVFromStr: Could not parse h,s,v values from $args[0]");
    return (0, 0, 0);
  }
  Log3 ($hash, 5, "MilightDevice_HSVFromStr: Parsed hsv string: h:$1,s:$2,v:$3");
  return ($1, $2, $3);
}

#####################################
sub MilightDevice_HSVToStr(@)
{
  # Convert HSV values to string in format "h,s,v"
  my ($hash, $h, $s, $v) = @_;
  
  $h=0 if (!defined($h));
  $s=0 if (!defined($s));
  $v=0 if (!defined($v));
  
  Log3 ($hash, 5, "MilightDevice_HSVToStr: h:$h,s:$s,v:$v");
  return "$h,$s,$v";
}

#####################################
sub MilightDevice_ValidateHSV(@)
{
  # Validate and return valid values for HSV
  my ($hash, $h, $s, $v) = @_;
  $h = 0 if ($h < 0);
  $h = 360 if ($h > 360 && $hash->{LEDTYPE} ne 'White');
  $h = 3000 if ($h < 3000 && $hash->{LEDTYPE} eq 'White');
  $h = 6500 if ($h > 6500);
  $s = 0 if ($s < 0);
  $s = 100 if ($s > 100);
  $v = 0 if ($v < 0);
  $v = 100 if ($v > 100);
  
  return ($h, $s, $v);
}

#####################################
# Return number of steps for each type of bulb
#  White: 11 steps (step = 9.1)
#  RGB: 9 steps (step = 11)
#  RGBW: 25 steps (step = 4)
sub MilightDevice_DimSteps(@)
{
  my ($hash) = @_;
  return AttrVal($hash->{NAME}, "dimStep", 25) if ($hash->{LEDTYPE} eq 'RGBW');
  return AttrVal($hash->{NAME}, "dimStep", 11) if ($hash->{LEDTYPE} eq 'White');
  return AttrVal($hash->{NAME}, "dimStep", 9) if ($hash->{LEDTYPE} eq 'RGB');
}

#####################################
# Return number of colour steps for each type of bulb
#  White: 11 steps (this is colour temperature)
#  RGB: 255 steps (not mentioned in API?)
#  RGBW: 255 steps
sub MilightDevice_ColourSteps(@)
{
  my ($hash) = @_;
  return 255 if ($hash->{LEDTYPE} eq 'RGBW');
  return 11 if ($hash->{LEDTYPE} eq 'White');
  return 255 if ($hash->{LEDTYPE} eq 'RGB');    
}

#####################################
# dispatcher
sub MilightDevice_SetHSV(@)
{
  my ($hash, $hue, $sat, $val, $repeat) = @_;
  MilightDevice_RGBW_SetHSV($hash, $hue, $sat, $val, $repeat) if ($hash->{LEDTYPE} eq 'RGBW');
  MilightDevice_White_SetHSV($hash, $hue, $sat, $val, $repeat) if ($hash->{LEDTYPE} eq 'White');
  MilightDevice_RGB_SetHSV($hash, $hue, $sat, $val, $repeat) if ($hash->{LEDTYPE} eq 'RGB');
  return undef;
}

#####################################
sub MilightDevice_HSV_Transition(@)
{
  my ($hash, $hue, $sat, $val, $ramp, $flags) = @_;
  my ($hueFrom, $satFrom, $valFrom, $timeFrom)=0;
  
  # Clear command queue if flag "q" not specified
  MilightDevice_CmdQueue_Clear($hash) if ($flags !~ m/.*[qQ].*/);
  
  # if queue in progress set start vals to last cached hsv target, else set start to actual hsv
  if (@{$hash->{helper}->{cmdQueue}} > 0)
  {
    $hueFrom = $hash->{helper}->{targetHue};
    $satFrom = $hash->{helper}->{targetSat};
    $valFrom = $hash->{helper}->{targetVal};
    $timeFrom = $hash->{helper}->{targetTime};
    $hueFrom = 0 if(!defined($hueFrom));
    $satFrom = 100 if(!defined($satFrom));
    $valFrom = 0 if(!defined($valFrom));
    $timeFrom = 0 if(!defined($timeFrom));
    Log3 ($hash, 5, "$hash->{NAME}_HSV_Transition: Prepare Start (cached): $hueFrom,$satFrom,$valFrom@".$timeFrom);
  }
  else
  {
    $hueFrom = ReadingsVal($hash->{NAME}, "hue", 0);
    $satFrom = ReadingsVal($hash->{NAME}, "saturation", 0);
    $valFrom = ReadingsVal($hash->{NAME}, "brightness", 0);
    $timeFrom = gettimeofday();
    Log3 ($hash, 5, "$hash->{NAME}_HSV_Transition: Prepare Start (actual): $hueFrom,$satFrom,$valFrom@".$timeFrom);


    if ($flags !~ m/.*[pP].*/ and ($hash->{LEDTYPE} eq 'RGB') || ($hash->{LEDTYPE} eq 'RGBW'))
    {
      # Store previous state if different to requested state
      if (($hueFrom != $hue) || ($satFrom != $sat) || ($valFrom != $val))
      {
        readingsSingleUpdate($hash, "previousState", MilightDevice_HSVToStr($hash, $hueFrom, $satFrom, $valFrom),1);
      }
    }
  }

  Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Current: $hueFrom,$satFrom,$valFrom");
  Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Set: $hue,$sat,$val; Ramp: $ramp; Flags: ". $flags);

  # Store target vales
  $hash->{helper}->{targetHue} = $hue;
  $hash->{helper}->{targetSat} = $sat;
  $hash->{helper}->{targetVal} = $val;
  
  # if there is no ramp we don't need transition
  if (($ramp || 0) == 0)
  {
    Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Set: $hue,$sat,$val; No Ramp");
    $hash->{helper}->{targetTime} = $timeFrom;
    return MilightDevice_CmdQueue_Add($hash, $hue, $sat, $val, undef, 0, undef);
  }

  # calculate the left and right turn length based
  # startAngle +360 -endAngle % 360 = counter clock
  # endAngle +360 -startAngle % 360 = clockwise
  my $hueTo = ($hue == 0) ? 1 : ($hue == 360) ? 359 : $hue;
  my $fadeLeft = ($hueFrom + 360 - $hue) % 360;
  my $fadeRight = ($hue + 360 - $hueFrom) % 360;
  my $direction = ($fadeLeft <=> $fadeRight); # -1 = counterclock, +1 = clockwise
  $direction = ($direction == 0)?1:$direction; # in dupt cw
  Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Colour rotation: cc(-1): $fadeLeft, cw(+1): $fadeRight; Shortest: $direction;"); 
  $direction *= -1 if ($flags =~ m/.*[lL].*/); # reverse if long path desired (flag l or L is set)

  my $rotation = ($direction == 1)?$fadeRight:$fadeLeft; # angle of hue rotation in based on flags
  my $sFade = abs($sat - $satFrom);
  my $vFade = abs($val - $valFrom);

  # No transition, so set immediately and ignore ramp setting
  if ($rotation == 0 && $sFade == 0 && $vFade == 0)
  {
    Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Unchanged. Set: $hue,$sat,$val; Ignoring Ramp");
    
    $hash->{helper}->{targetTime} = $timeFrom;
    return MilightDevice_CmdQueue_Add($hash, $hue, $sat, $val, undef, 0, undef);
  }
  
  my ($stepWidth, $steps, $maxSteps, $hueToSet, $hueStep, $satToSet, $satStep, $valToSet, $valStep);

  # Calculate stepWidth
  if ($rotation >= ($sFade || $vFade))
  { 
    # Transition based on Hue, so max steps = colourSteps
    $stepWidth = ($ramp * 1000 / $rotation); # how long is one step (set hsv) in ms based on hue
    $maxSteps = MilightDevice_ColourSteps($hash);
  }
  elsif ($sFade  >= ($rotation || $vFade))
  { 
    # Transition based on Saturation, so max steps = 2 (devices don't support sat, so set to 0 or 100 mostly)
    $stepWidth = ($ramp * 1000 / $sFade); # how long is one step (set hsv) in ms based on sat
    $maxSteps = 2;
  }
  else
  {
    # Transition based on Brightness, so max steps = dimSteps
    $stepWidth = ($ramp * 1000 / $vFade); # how long is one step (set hsv) in ms based on val
    $maxSteps = MilightDevice_DimSteps($hash);
  }
  
  # Calculate number of steps, limit to max number (no point running more if they are the same)
  $steps = int($ramp * 1000 / $stepWidth);
  if ($steps > $maxSteps)
  {
    $stepWidth *= ($steps/$maxSteps);
    $steps = $maxSteps;
  }

  # Calculate number of steps, limit to max number (no point running more if they are the same)
  $steps = int($ramp * 1000 / $stepWidth);
  if ($steps > $maxSteps)
  {
    $stepWidth *= ($steps/$maxSteps);
    $steps = $maxSteps;
  }

  # Calculate minimum stepWidth
  # Min bridge delay as specified by Bridge * 3 (eg. 100*3=300ms).
  # On average min 3 commands need to be sent per step (eg. Group On; Mode; Brightness;) so this gets it approximately right
  my $minStepWidth = $hash->{IODev}->{INTERVAL} * 3;
  $stepWidth = $minStepWidth if ($stepWidth < $minStepWidth); # Make sure we have min stepWidth
  
  Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Steps: $steps; Step Interval(ms): $stepWidth");  
  
  # Calculate hue step  
  $hueToSet = $hueFrom; # Start at current hue
  $hueStep = $rotation / $steps * $direction;
  
  # Calculate saturation step
  $satToSet = $satFrom; # Start at current saturation
  $satStep = ($sat - $satFrom) / $steps;
  
  # Calculate brightness step
  $valToSet = $valFrom;  # Start at current brightness
  $valStep = ($val - $valFrom) / $steps;

  for (my $i=1; $i <= $steps; $i++)
  {
    $hueToSet += $hueStep; # Increment new hue by step (negative step decrements)
    $hueToSet -= 360 if ($hueToSet > 360); #handle turn over zero
    $hueToSet += 360 if ($hueToSet < 0);
    $satToSet += $satStep; # Increment new saturation by step (negative step decrements)
    $valToSet += $valStep; # Increment new brightness by step (negative step decrements)
    Log3 ($hash, 4, "$hash->{NAME}_HSV_Transition: Add to Queue: h:".($hueToSet).", s:".($satToSet).", v:".($valToSet)." ($i/$steps)");  
    MilightDevice_CmdQueue_Add($hash, MilightDevice_roundfunc($hueToSet), MilightDevice_roundfunc($satToSet), MilightDevice_roundfunc($valToSet), undef, $stepWidth, $timeFrom + (($i-1) * $stepWidth / 1000) );
  }
  # Set target time for completion of sequence. 
  # This may be slightly higher than what was requested since $stepWidth > minDelay (($steps * $stepWidth) > $ramp)
  $hash->{helper}->{targetTime} = $timeFrom + ($steps * $stepWidth / 1000);
  Log3 ($hash, 5, "$hash->{NAME}_HSV_Transition: TargetTime: $hash->{helper}->{targetTime}");
  return undef;
}

#####################################
sub MilightDevice_White_Transition(@)
{
  my ($hash, $ct, $sat, $val, $ramp, $flags) = @_;
  my ($ctFrom, $valFrom, $timeFrom)=0;

  # Clear command queue if flag "q" not specified
  MilightDevice_CmdQueue_Clear($hash) if ($flags !~ m/.*[qQ].*/);

  # if queue in progress set start vals to last cached hsv target, else set start to actual hsv
  if (@{$hash->{helper}->{cmdQueue}} > 0)
  {
    $ctFrom = $hash->{helper}->{targetCt};
    $valFrom = $hash->{helper}->{targetVal};
    $timeFrom = $hash->{helper}->{targetTime};
    $ctFrom = 3000 if(!defined($ctFrom));
    $valFrom = 0 if(!defined($valFrom));
    $timeFrom = 0 if(!defined($timeFrom));
    Log3 ($hash, 5, "$hash->{NAME}_White_Transition: Prepare Start (cached): $ctFrom,$valFrom@".$timeFrom);
  }
  else
  {
    $ctFrom = ReadingsVal($hash->{NAME}, "ct", 3000);
    $valFrom = ReadingsVal($hash->{NAME}, "brightness", 0);
    $timeFrom = gettimeofday();
    Log3 ($hash, 5, "$hash->{NAME}_White_Transition: Prepare Start (actual): $ctFrom,$valFrom@".$timeFrom);


    if ($flags !~ m/.*[pP].*/)
    {
      # Store previous state if different to requested state
      if (($ctFrom != $ct) || ($valFrom != $val))
      {
        readingsSingleUpdate($hash, "previousState", MilightDevice_HSVToStr($hash, $ctFrom, 0, $valFrom),1);
      }
    }
  }

  Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Current: $ctFrom,$valFrom");
  Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Set: $ct,$val; Ramp: $ramp; Flags: ". $flags);

  # Store target vales
  $hash->{helper}->{targetCt} = $ct;
  $hash->{helper}->{targetVal} = $val;

  # if there is no ramp we don't need transition
  if (($ramp || 0) == 0)
  {
    Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Set: $ct,$val; No Ramp");
    $hash->{helper}->{targetTime} = $timeFrom;
    return MilightDevice_CmdQueue_Add($hash, $ct, 0, $val, undef, 0, undef);
  }

  my $vFade = abs($val - $valFrom);
  my $ctFade = abs($ct - $ctFrom);
  Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Colour temp: $ctFade, Brightness: $vFade;");

  # No transition, so set immediately and ignore ramp setting
  if ($ctFade == 0 && $vFade == 0)
  {
    Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Unchanged. Set: $ct,0,$val; Ignoring Ramp");

    $hash->{helper}->{targetTime} = $timeFrom;
    return MilightDevice_CmdQueue_Add($hash, $ct, 0, $val, undef, 0, undef);
  }

  my ($stepWidth, $steps, $maxSteps, $ctToSet, $ctStep, $valToSet, $valStep);

  # Calculate stepWidth
  if ($ctFade >= $vFade)
  {
    # Transition based on ct, so max steps = colourSteps
    $stepWidth = ($ramp * 1000 / $ctFade /100); # how long is one step (set hsv) in ms based on ct
    $maxSteps = MilightDevice_ColourSteps($hash);
  }
  else
  {
    # Transition based on Brightness, so max steps = dimSteps
    $stepWidth = ($ramp * 1000 / $vFade); # how long is one step (set hsv) in ms based on val
    $maxSteps = MilightDevice_DimSteps($hash);
  }

  # Calculate number of steps, limit to max number (no point running more if they are the same)
  $steps = int($ramp * 1000 / $stepWidth);
  if ($steps > $maxSteps)
  {
    $stepWidth *= ($steps/$maxSteps);
    $steps = $maxSteps;
  }

  # Calculate number of steps, limit to max number (no point running more if they are the same)
  $steps = int($ramp * 1000 / $stepWidth);
  if ($steps > $maxSteps)
  {
    $stepWidth *= ($steps/$maxSteps);
    $steps = $maxSteps;
  }

  # Calculate minimum stepWidth
  # Min bridge delay as specified by Bridge * 3 (eg. 100*3=300ms).
  # On average min 3 commands need to be sent per step (eg. Group On; Mode; Brightness;) so this gets it approximately right
  my $minStepWidth = $hash->{IODev}->{INTERVAL} * 3;
  $stepWidth = $minStepWidth if ($stepWidth < $minStepWidth); # Make sure we have min stepWidth

  Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Steps: $steps; Step Interval(ms): $stepWidth");

  # Calculate hue step
  $ctToSet = $ctFrom; # Start at current hue
  $ctStep = ($ct - $ctFrom) / $steps;

  # Calculate brightness step
  $valToSet = $valFrom;  # Start at current brightness
  $valStep = ($val - $valFrom) / $steps;

  for (my $i=1; $i <= $steps; $i++)
  {
    $ctToSet += $ctStep; # Increment new hue by step (negative step decrements)
    $valToSet += $valStep; # Increment new brightness by step (negative step decrements)
    Log3 ($hash, 4, "$hash->{NAME}_White_Transition: Add to Queue: ct:".(int($ctToSet)).", s:0, v:".(int($valToSet))." ($i/$steps)");
    MilightDevice_CmdQueue_Add($hash, MilightDevice_roundfunc($ctToSet), 0, MilightDevice_roundfunc($valToSet), undef, $stepWidth, $timeFrom + (($i-1) * $stepWidth / 1000) );
  }
  # Set target time for completion of sequence.
  # This may be slightly higher than what was requested since $stepWidth > minDelay (($steps * $stepWidth) > $ramp)
  $hash->{helper}->{targetTime} = $timeFrom + ($steps * $stepWidth / 1000);
  Log3 ($hash, 5, "$hash->{NAME}_White_Transition: TargetTime: $hash->{helper}->{targetTime}");
  return undef;
}

#####################################
sub MilightDevice_SetHSV_Readings(@)
{
  my ($hash, $hue, $sat, $val, $val_on) = @_;
  my $name = $hash->{NAME};
  
  readingsBeginUpdate($hash); # Start update readings
  
  # Store requested values
  readingsBulkUpdate($hash, "brightness", $val);
  # Store on brightness so we can turn on at a set brightness
  readingsBulkUpdate($hash, "brightness_on", $val_on);
  if (($hash->{LEDTYPE} eq 'RGB') || ($hash->{LEDTYPE} eq 'RGBW'))
  {
    # Store previous state if different to requested state
    my $prevHue = ReadingsVal($hash->{NAME}, "hue", 0);
    my $prevSat = ReadingsVal($hash->{NAME}, "saturation", 0);
    my $prevVal = ReadingsVal($hash->{NAME}, "brightness", 0);
    if (($prevHue != $hue) || ($prevSat != $sat) || ($prevVal != $val))
    {
      readingsBulkUpdate($hash, "previousState", MilightDevice_HSVToStr($hash, $prevHue, $prevSat, $prevVal)) if ReadingsVal($hash->{NAME}, "transitionInProgress", 1) eq 0;
    }

    readingsBulkUpdate($hash, "saturation", $sat);
    readingsBulkUpdate($hash, "hue", $hue);
    readingsBulkUpdate($hash, "hsv", MilightDevice_HSVToStr($hash, $hue,$sat,$val));
  	
    # Calc RGB values from HSV
    my ($r,$g,$b) = Color::hsv2rgb($hue/360.0,$sat/100.0,$val/100.0);
    $r *=255; $g *=255; $b*=255;
    # Store values
    readingsBulkUpdate($hash, "rgb", sprintf("%02X%02X%02X",$r,$g,$b)); # Int to Hex convert
    readingsBulkUpdate($hash, "discoMode", 0);
    readingsBulkUpdate($hash, "discoSpeed", 0);
  }
  elsif ($hash->{LEDTYPE} eq 'White')
  {
    readingsBulkUpdate($hash, "ct", $hue); 
    readingsBulkUpdate($hash, "hsv", MilightDevice_HSVToStr($hash, $hue,0,$val));
  }
  readingsBulkUpdate($hash, "state", "on $val") if ($val > 1);
  readingsBulkUpdate($hash, "state", "off") if ($val < 2);
  readingsEndUpdate($hash, 1);
  MilightDevice_BridgeDevices_Update($hash, "bulk") if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1); 
}

#####################################
sub MilightDevice_SetDisco_Readings(@)
{
  # Step/Speed can be "1" or "0" when active
  my ($hash, $step, $speed) = @_;
  my $name = $hash->{NAME};
  
  if (($hash->{LEDTYPE} eq 'RGBW') || ($hash->{LEDTYPE} eq 'RGB'))
  {
    my $discoMode = ReadingsVal($hash->{NAME}, "discoMode", 0);
    $discoMode = "on";
    
    my $discoSpeed = ReadingsVal($hash->{NAME}, "discoSpeed", 5);
    $discoSpeed = "-" if ($speed == 0);
    $discoSpeed = "+" if ($speed == 1);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "discoMode", $step);
    readingsBulkUpdate($hash, "discoSpeed", $speed);
    readingsEndUpdate($hash, 1);
    if ($hash->{SLOT} eq 'A' && AttrVal($hash->{NAME}, "updateGroupDevices", 0) == 1)
    {
      MilightDevice_BridgeDevices_Update($hash, "discoMode"); 
      MilightDevice_BridgeDevices_Update($hash, "discoSpeed");
    } 
  }
  
}

#####################################
sub MilightDevice_ColorConverter(@)
{
  my ($hash, $cr, $cy, $cg, $cc, $cb, $cm) = @_;

  my @colorMap;

  my $adjRed = 0 + $cr;
  my $adjYellow = 60 + $cy;
  my $adjGreen = 120 + $cg;
  my $adjCyan = 180 + $cc;
  my $adjBlue = 240 + $cb;
  my $adjLilac = 300 + $cm;

  my $devRed = 176; # (0xB0)
  #my $devYellow = 128; # (0x80)
  my $devYellow = 144;
  my $devGreen = 96; # (0x60)
  #my $devCyan = 48; # (0x30)
  my $devCyan = 56;
  my $devBlue = 16; # (0x10)
  my $devLilac = 224; # (0xE0)

  my $i= 360;

  # red to yellow
  $adjRed += 360 if ($adjRed < 0); # in case of negative adjustment
  $devRed += 256 if ($devRed < $devYellow);
  $adjYellow += 360 if ($adjYellow < $adjRed);
  for ($i = $adjRed; $i <= $adjYellow; $i++)
  {
    $colorMap[$i % 360] = ($devRed - int((($devRed - $devYellow) / ($adjYellow - $adjRed)  * ($i - $adjRed)) +0.5)) % 255;
    Log3 ($hash, 5, "$hash->{NAME}_ColorConverter: create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #yellow to green
  $devYellow += 256 if ($devYellow < $devGreen);
  $adjGreen += 360 if ($adjGreen < $adjYellow);
  for ($i = $adjYellow; $i <= $adjGreen; $i++)
  {
    $colorMap[$i % 360] = ($devYellow - int((($devYellow - $devGreen) / ($adjGreen - $adjYellow)  * ($i - $adjYellow)) +0.5)) % 255;
    Log3 ($hash, 5, "$hash->{NAME}_ColorConverter: create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #green to cyan
  $devGreen += 256 if ($devGreen < $devCyan);
  $adjCyan += 360 if ($adjCyan < $adjGreen);
  for ($i = $adjGreen; $i <= $adjCyan; $i++)
  {
    $colorMap[$i % 360] = ($devGreen - int((($devGreen - $devCyan) / ($adjCyan - $adjGreen)  * ($i - $adjGreen)) +0.5)) % 255;
    Log3 ($hash, 5, "$hash->{NAME}_ColorConverter: create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #cyan to blue
  $devCyan += 256 if ($devCyan < $devCyan);
  $adjBlue += 360 if ($adjBlue < $adjCyan);
  for ($i = $adjCyan; $i <= $adjBlue; $i++)
  {
    $colorMap[$i % 360] = ($devCyan - int((($devCyan - $devBlue) / ($adjBlue - $adjCyan)  * ($i - $adjCyan)) +0.5)) % 255;
    Log3 ($hash, 5, "$hash->{NAME}_ColorConverter: create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #blue to lilac
  $devBlue += 256 if ($devBlue < $devLilac);
  $adjLilac += 360 if ($adjLilac < $adjBlue);
  for ($i = $adjBlue; $i <= $adjLilac; $i++)
  {
    $colorMap[$i % 360] = ($devBlue - int((($devBlue - $devLilac) / ($adjLilac - $adjBlue)  * ($i- $adjBlue)) +0.5)) % 255;
    Log3 ($hash, 5, "$hash->{NAME}_ColorConverter: create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #lilac to red
  $devLilac += 256 if ($devLilac < $devRed);
  $adjRed += 360 if ($adjRed < $adjLilac);
  for ($i = $adjLilac; $i <= $adjRed; $i++)
  {
    $colorMap[$i % 360] = ($devLilac - int((($devLilac - $devRed) / ($adjRed - $adjLilac)  * ($i - $adjLilac)) +0.5)) % 255;
    Log3 ($hash, 5, "$hash->{NAME}_ColorConverter: create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }

  return \@colorMap;
}


#####################################
sub MilightDevice_CreateGammaMapping(@)
{
  my ($hash, $gamma) = @_;

  #original wifilight gamma was inverted
  $gamma = 1/$gamma;

  my @gammaMap;

  $gammaMap[0] = 0;
  for (my $i = 1; $i <= 100; $i += 1)
  {
    my $correction = ($i / 100) ** (1 / $gamma); 
    $gammaMap[$i] = $correction * 100;
    $gammaMap[$i] = MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)) if($gammaMap[$i] < MilightDevice_roundfunc(100/MilightDevice_DimSteps($hash)));
    Log3 ($hash, 5, "$hash->{NAME} create gammamap v-in: ".$i.", v-out: $gammaMap[$i]");
  } 

  return \@gammaMap;
}


###############################################################################
# Device Command Queue
# Triggers commands for long running transitions for a device
###############################################################################
sub MilightDevice_CmdQueue_Add(@)
{
  my ($hash, $hue, $sat, $val, $ctrl, $delay, $targetTime) = @_;
  my $cmd;
  
  # Validate input
  ($hue, $sat, $val) = MilightDevice_ValidateHSV($hash, $hue, $sat, $val);

  $cmd->{hue} = $hue;
  $cmd->{sat} = $sat;
  $cmd->{val} = $val;
  $cmd->{ctrl} = $ctrl;
  $cmd->{delay} = $delay;
  $cmd->{targetTime} = $targetTime;
  $cmd->{inProgess} = 0;

  push @{$hash->{helper}->{cmdQueue}}, $cmd;

  my $hexStr = defined($cmd->{ctrl})? unpack("H*", $cmd->{ctrl} || '') : "";
  Log3 ($hash, 4, "$hash->{NAME}_CmdQueue_Add: h: ".(defined($cmd->{hue})? $cmd->{hue}: "")."; s: ".(defined($cmd->{sat})? $cmd->{sat}: "")."; v: ".(defined($cmd->{val})? $cmd->{val}: "")."; Ctrl $hexStr; TargetTime: ".(defined($cmd->{targetTime})? $cmd->{targetTime}: "")."; QLen: ".@{$hash->{helper}->{cmdQueue}});

  my $actualCmd = @{$hash->{helper}->{cmdQueue}}[0];

  # sender busy ?
  if(defined($actualCmd))
  {
    return undef if (ref($actualCmd) ne 'HASH');
    return undef if (!defined($actualCmd->{inProgess}));
    return undef if (($actualCmd->{inProgess} || 0) == 1);
  }
  return MilightDevice_CmdQueue_Exec($hash);
}

#####################################
sub MilightDevice_CmdQueue_Exec(@)
{
  my ($hash) = @_; 
  RemoveInternalTimer($hash);
  #if ($hash->{IODev}->{STATE} ne "ok" && $hash->{IODev}->{STATE} ne "Initialized") {
  #  InternalTimer(gettimeofday() + 60, "MilightDevice_CmdQueue_Exec", $hash, 0);
  #  return undef;    
  #}
  

  my $actualCmd = @{$hash->{helper}->{cmdQueue}}[0];

  # transmission complete, remove
  shift @{$hash->{helper}->{cmdQueue}} if ($actualCmd->{inProgess});

  # next in queue
  $actualCmd = @{$hash->{helper}->{cmdQueue}}[0];
  my $nextCmd = @{$hash->{helper}->{cmdQueue}}[1];

  # return if no more elements in queue
  if (!defined($actualCmd->{inProgess}))
  {
    readingsSingleUpdate($hash, "transitionInProgress", 0, 1); # Clear transitionInProgress flag
    return undef;
  }
  
  readingsSingleUpdate($hash, "transitionInProgress", 1, 1); # Set transitionInProgress flag

  # drop frames if next frame is already scheduled for given time. do not drop if it is the last frame or if it is a control command  
  while (defined($nextCmd->{targetTime}) && ($nextCmd->{targetTime} < gettimeofday()) && !$actualCmd->{ctrl})
  {
    shift @{$hash->{helper}->{cmdQueue}};
    $actualCmd = @{$hash->{helper}->{cmdQueue}}[0];
    $nextCmd = @{$hash->{helper}->{cmdQueue}}[1];
    Log3 ($hash, 4, "$hash->{NAME}_CmdQueue_Exec: Drop Frame. Queue Length: ".@{$hash->{helper}->{cmdQueue}});
  }
  Log3 ($hash, 5, "$hash->{NAME}_CmdQueue_Exec: Dropper Delay: ".($actualCmd->{targetTime} - gettimeofday())) if (defined($actualCmd->{targetTime}));

  # set hsv or if a device ctrl command is scheduled: send it and ignore hsv
  if ($actualCmd->{ctrl})
  {
    my $dbgStr = unpack("H*", $actualCmd->{ctrl});
    Log3 ($hash, 4, "$hash->{NAME}_CmdQueue_Exec: Send ctrl: $dbgStr; Queue Length: ".@{$hash->{helper}->{cmdQueue}});
    IOWrite($hash, $actualCmd->{ctrl});
  }
  else
  {
    # Send an HSV Command.
    my $repeat = 0;
    # If queue length < 2 (ie. 1) we are last command so repeat sending (takes twice as long...)
    $repeat = 1 if (@{$hash->{helper}->{cmdQueue}} < 2);
    MilightDevice_SetHSV($hash, $actualCmd->{hue}, $actualCmd->{sat}, $actualCmd->{val}, $repeat);
  }
  $actualCmd->{inProgess} = 1;
  my $next = defined($nextCmd->{targetTime})?$nextCmd->{targetTime}:gettimeofday() + ($actualCmd->{delay} / 1000);
  
  Log3 ($hash, 5, "$hash->{NAME}_CmdQueue_Exec: Next Exec: $next");
  InternalTimer($next, "MilightDevice_CmdQueue_Exec", $hash, 0);
  return undef;
}

#####################################
sub MilightDevice_CmdQueue_Clear(@)
{
  my ($hash) = @_;
  Log3 ($hash, 4, "$hash->{NAME}_CmdQueue_Clear");
  RemoveInternalTimer($hash);
  #if ($hash->{IODev}->{STATE} ne "ok" && $hash->{IODev}->{STATE} ne "Initialized") {
  #  InternalTimer(gettimeofday() + 60, "MilightDevice_CmdQueue_Exec", $hash, 0);
  #  return undef;    
  #}

  readingsSingleUpdate($hash, "transitionInProgress", 0, 1); # Clear inProgress flag
  
  #foreach my $args (keys %intAt) 
  #{
  #  if (($intAt{$args}{ARG} eq $hash) && ($intAt{$args}{FN} eq 'MilightDevice_CmdQueue_Exec'))
  #  {
  #    Log3 ($hash, 5, "$hash->{NAME}_CmdQueue_Clear: Remove timer at: ".$intAt{$args}{TRIGGERTIME});
  #    delete($intAt{$args});
  #  }
  #}

  $hash->{helper}->{cmdQueue} = [];

  return undef;
}

#####################################
sub MilightDevice_BridgeDevices_Update(@)
{
  my ($hash, $attr) = @_;

  my @rdlist = ($attr);
 
  if($attr eq 'bulk')
  {
    @rdlist = ("state","brightness","brightness_on","hue", "saturation", "hsv", "rgb", "discoMode", "discoSpeed")if ($hash->{LEDTYPE} eq 'RGBW');
    @rdlist = ("state","brightness","brightness_on","ct")if ($hash->{LEDTYPE} eq 'White');
  }

  my $sl = 5;
  $sl = 1 if ($hash->{LEDTYPE} eq 'White');

  for (my $i = 0; $i < 4; $i++)
  {

    my $devname = $hash->{IODev}->{$sl+$i}->{NAME};
    next if (!defined($defs{$devname}));
    my $device = $defs{$devname};
    $devname = "?" if(!defined($devname));
    readingsSingleUpdate($device, "transitionInProgress", 1, 1);

    
    readingsBeginUpdate($device);
  
    foreach my $rdname (@rdlist) 
    {
      if (exists ($device->{READINGS}{$rdname}))
      {
        readingsBulkUpdate($device, $rdname, $hash->{READINGS}{$rdname}{VAL}, 1);
        Log3 ($hash, 4, $rdname.": ".$device->{READINGS}{$rdname}{VAL}." for ".$devname);
      }
    }
    readingsEndUpdate($device, 1);
    readingsSingleUpdate($device, "transitionInProgress", 0, 1);
  }

  return undef;
}

sub MilightDevice_roundfunc($) {
  my ($number) = @_;
  return sprintf("%.0f", $number);
  #return Math::Round::round($number);
}


1;

=pod
=item device
=item summary This module represents a Milight LED Bulb or LED strip controller
=begin html

<a name="MilightDevice"></a>
<h3>MilightDevice</h3>
<ul>
  <p>This module represents a Milight LED Bulb or LED strip controller.  It is controlled by a <a href="#MilightBridge">MilightBridge</a>.</p>
  <p>The Milight system is sold under various brands around the world including "LimitlessLED, EasyBulb, AppLamp"</p>
  <p>The API documentation is available here: <a href="http://www.limitlessled.com/dev/">http://www.limitlessled.com/dev/</a></p>
  <p>Requires perl module Math::Round</p>

  <a name="MilightDevice_define"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MilightDevice &lt;devType(RGB|RGBW|White)&gt; &lt;IODev&gt; &lt;slot&gt;</code></p>
    <p>Specifies the Milight device.<br/>
       &lt;devType&gt; One of RGB, RGBW, White depending on your device.<br/>
       &lt;IODev&gt; The <a href="#MilightBridge">MilightBridge</a> which the device is paired with.<br/>
       &lt;slot&gt; The slot on the <a href="#MilightBridge">MilightBridge</a> that the device is paired with or 'A' to group all slots.</p>
  </ul>
  <a name="MilightDevice_readings"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <b>state</b><br/>
         [on xxx|off|night]: Current state of the device / night mode (xxx = 0-100%).
    </li>
    <li>
      <b>brightness</b><br/>
         [0-100]: Current brightness level in %.
    </li>
    <li>
      <b>brightness_on</b><br/>
         [0-100]: The brightness level before the off command was sent.  This allows the light to turn back on to the last brightness level.
    </li>
    <li>
      <b>rgb</b><br/>
         [FFFFFF]: HEX value for RGB.
    </li>
    <li>
      <b>previousState</b><br/>
         [hsv]: hsv value before last change.  Can be used with <b>restorePreviousState</b> set command.
    </li>
    <li>
      <b>savedState</b><br/>
         [hsv]: hsv value that was saved using <b>saveState</b> set function
    </li>
    <li>
      <b>hue</b><br/>
         [0-360]: Current hue value.
    </li>
    <li>
      <b>saturation</b><br/>
         [0-100]: Current saturation value.
    </li>
    <li>
      <b>transitionInProgress</b><br/>
         [0|1]: Set to 1 if a transition is currently in progress for this device (eg. fade).
    </li>
    <li>
      <b>discoMode</b><br/>
         [0|1]: 1 if discoMode is enabled, 0 otherwise.
    </li>
    <li>
      <b>discoSpeed</b><br/>
         [0|1]: 1 if discoSpeed is increased, 0 if decreased.  Does not mean much for RGBW
    </li>
    <li>
      <b>lastPreset</b><br/>
         [0..X]: Last selected preset.
    </li>
    <li>
      <b>ct</b><br/>
         [1-10]: Current colour temperature (3000=Warm,6500=Cold) for White devices.
    </li>
  </ul>

  <a name="MilightDevice_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <b>on &lt;ramp_time (seconds)></b>
    </li>
    <li>
      <b>off &lt;ramp_time (seconds)></b>
    </li>
    <li>
      <b>toggle</b>     
    </li>
    <li>
      <b>night</b>     
    </li>
    <li>
      <b>dim &lt;percent(0..100)&gt; [seconds(0..x)] [flags(l=long path|q=don't clear queue)]</b><br/>
      Will be replaced by <i>brightness</i> at some point
    </li>
    <li>
      <b>dimup &lt;percent change(0..100)&gt; [seconds(0..x)]</b><br/>
         Special case: If percent change=100, seconds will be adjusted for actual change to go from current brightness.
    </li>
    <li>
      <b>dimdown &lt;percent change(0..100)&gt; [seconds(0..x)]</b><br/>
         Special case: If percent change=100, seconds will be adjusted for actual change to go from current brightness.
    </li>
    <li>
      <b>pair</b><br/>
         May not work properly. Sometimes it is necessary to use a remote to clear pairing first.
    </li>
    <li>
      <b>unpair</b><br/>
         May not work properly. Sometimes it is necessary to use a remote to clear pairing first.
    </li>
    <li>
      <b>restorePreviousState</b><br/>
         Set device to previous hsv state as stored in <b>previousState</b> reading.
    </li>
    <li>
      <b>saveState</b><br/>
         Save current hsv state to <b>savedState</b> reading.
    </li>
    <li>
      <b>restoreState</b><br/>
         Set device to saved hsv state as stored in <b>savedState</b> reading.
    </li>
    <li>
      <b>preset (0..X|+)</b><br/>
         Load preset (+ for next preset).
    </li>
    <li>
      <b>hsv &lt;h(0..360)&gt;,&lt;s(0..100)&gt;,&lt;v(0..100)&gt; [seconds(0..x)] [flags(l=long path|q=don't clear queue)]</b><br/>
         Set hsv value directly
    </li>
    <li>
      <b>rgb RRGGBB [seconds(0..x)] [flags(l=long path|q=don't clear queue)]</b><br/>
         Set rgb value directly or using colorpicker.
    </li>
    <li>
      <b>hue &lt;(0..360)&gt; [seconds(0..x)] [flags(l=long path|q=don't clear queue)]</b><br/>
         Set hue value.
    </li>
    <li>
      <b>saturation &lt;s(0..100)&gt; [seconds(0..x)] [flags(q=don't clear queue)]</b><br/>
         Set saturation value directly
    </li>
    <li>
      <b>discoModeUp</b><br/>
         Next disco Mode setting (for RGB and RGBW).
    </li>
    <li>
      <b>discoModeDown</b><br/>
         Previous disco Mode setting (for RGB).
    </li>
    <li>
      <b>discoSpeedUp</b><br/>
         Increase speed of disco mode (for RGB and RGBW).
    </li>
    <li>
      <b>discoSpeedDown</b><br/>
         Decrease speed of disco mode (for RGB and RGBW).
    </li>
    <li>
      <b>ct &lt;3000-6500&gt;</b><br/>
         Colour temperature 3000=Warm White,6500=Cold White (10 steps) (for White devices only).
    </li>
    <li>
      <a href="#setExtensions"> set extensions</a> are supported.
    </li>
  </ul>

  <a name="MilightDevice_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <b>rgb</b>
    </li>
    <li>
      <b>hsv</b>
    </li>
  </ul>
  
  <a name="MilightDevice_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <b>dimStep</b><br/>
         Allows you to modify the default dimStep if required.
    </li>
    <li>
      <b>defaultRampOn</b><br/>
         Set the default ramp time if not specified for on command.
    </li>
    <li>
      <b>defaultRampOff</b><br/>
         Set the default ramp time if not specified for off command.
    </li>
    <li>
      <b>presets</b><br/>
         List of hsv presets separated by spaces (eg 0,0,100 9,0,50).
    </li>
    <li>
      <b>colorCast</b><br/>
         Color shift values for red,yellow,green,cyan,blue,magenta (-29..29) for HSV color correction (eg 0,5,10,-5,0,0)
    </li>
    <li>
      <b>gamma</b><br/>
         Set gamma correction value for device (eg 0.8)
    </li>
    <li>
      <b>dimOffWhite</b><br/>
         Use a different switching logic for White bulbs to better handle packet loss.
    </li>
    <li>
      <b>updateGroupDevices</b><br/>
         Update the state of single devices switched with slot 'A'.
    </li>
    <li>
      <b>restoreAtStart</b><br/>
         Restore the state of devices at startup. Default 0 for slot 'A', 1 otherwise.
    </li>
    <li>
      <b>defaultBrightness</b><br/>
         Set the default brightness if not known. (Default: 36)
    </li>
  </ul>
</ul>

=end html
=cut
