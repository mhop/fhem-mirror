##############################################
# $Id$

# TODO

# versions
# 00 POC
# ..
# 50 Stable
# 51 new milight color converter
# 52 timing for transitions: drop frames if required
# 53 transition names and events
# 54 drop frames ll add-on / lock ll queue
# 55 add ll queue lock count
# 56 RGB in
# 57 bridge v2
# 58 gamma correction 
# 59 fix "off" with ramp
# 60 add dimup/dimdown
# 61 introduce dimSteps
# 62 introduce defaultColor
# 63 LW12 define if lw12 is unavailable at startup
# 64 transition with ramp 0 fixed
# 65 some typos with impact to RGBW1 and RGBW2
# 66 readings: lower camelCase and limited trigger
# 67 restore state after startup
# 68 LW12 reconnect after timeout
# 69 RGBW1 timing improved
# 70 colorpicker
# 71 default ramp attrib
# 72 add LD316
# 73 add LD382
# 74 add color calibration (hue intersections) for RGB type controller
# 75 add white point adjustment for RGB type controller
# 76 add LW12 HX001
# 77 milight RGBW2: critical cmds sendout repeatly
# 78 add attrib for color managment (rgb types)
# 79 add LD382 RGB ony mode
# 80 HSV2fourChannel bug fixed (thnx to lexorius)
# 81 LW12FC added 
# 82 LD382A (FW 1.0.6)
# 83 fixed ramp handling (thnx to henryk)
# 84 sengled boost added (thnx to scooty)
# 85 milight white, improved reliability
# 86 milight white, improved reliability / mark II
# 87 milight rgbw2, dim bug
# 88 readingFnAttributes
# 89 add LD316A
# 90 Sunricher poc
# 91 milight colorcast fixed, more robust tcp re-connect

# verbose level
# 0: quit
# 1: error
# 2: warning
# 3: user command
# 4: 1st technical level (detailed internal reporting)
# 5: 2nd technical level (full internal reporting)

package main;

use strict;
use warnings;

use IO::Handle;
use IO::Socket;
use IO::Select;
use Time::HiRes;
use Data::Dumper;

use Color;

sub
WifiLight_Initialize(@)
{

  my ($hash) = @_;

  FHEM_colorpickerInit();

  $hash->{DefFn}        = "WifiLight_Define";
  $hash->{UndefFn}      = "WifiLight_Undef";
  $hash->{ShutdownFn}   = "WifiLight_Undef";
  $hash->{SetFn}        = "WifiLight_Set";
  $hash->{GetFn}        = "WifiLight_Get";
  $hash->{AttrFn}       = "WifiLight_Attr";
  $hash->{NotifyFn}     = "WifiLight_Notify";
  $hash->{AttrList}     = "gamma dimStep defaultColor defaultRamp colorCast whitePoint"
                          ." $readingFnAttributes";
      

  return undef;
}

sub
WifiLight_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def); 
  my $name = $a[0];
  my $key;

  return "wrong syntax: define <name> WifiLight <type> <connection>" if(@a != 4);
  # return "unknown LED type ($a[2]): choose one of RGB, RGBW, RGBW1, RGBW2, White" unless (grep /$a[2]/, ('RGB', 'RGBW', 'RGBW1', 'RGBW2', 'White')); 
  
  $hash->{LEDTYPE} = $a[2];
  my $otherLights;

  if ($a[3] =~ m/(bridge-V2):([^:]+):*(\d+)*/g)
  {
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:50000;
    $hash->{PROTO} = 0;
    #my @hlCmdQueue = [];
    @{$hash->{helper}->{hlCmdQueue}} = (); #\@hlCmdQueue;
    # $hash->{SERVICE} = 48899; unkown for v2
    # search if this bridge is already defined 
    # if so, we need a shared buffer (llCmdQueue), shared socket and we need to check if the requied slot is free
    foreach $key (keys %defs) 
    {
      if (($defs{$key}{TYPE} eq 'WifiLight') && ($defs{$key}{IP} eq $hash->{IP}) && ($key ne $name))
      {
        #bridge is in use
        Log3 (undef, 3, "WifiLight: requested bridge $hash->{CONNECTION} at $hash->{IP} already in use by $key, copy llCmdQueue");
        $hash->{helper}->{llCmdQueue} = $defs{$key}{helper}{llCmdQueue};
        $hash->{helper}->{llLock} = 0;
        $hash->{helper}->{SOCKET} = $defs{$key}{helper}{SOCKET};
        $hash->{helper}->{SELECT} = $defs{$key}{helper}{SELECT};
        my $slotInUse = $defs{$key}{SLOT};
        $otherLights->{$slotInUse} = $defs{$key};
      }
    } 
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => 48899,
        Blocking => 0,
        Proto => 'udp',
        Broadcast => 1) or return "can't bind: $@";
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = {};
      $hash->{helper}->{llLock} = 0;
    }
  }

  if ($a[3] =~ m/(bridge-V3):([^:]+):*(\d+)*/g)
  {
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:8899;
    $hash->{PROTO} = 0;
    #my @hlCmdQueue = [];
    @{$hash->{helper}->{hlCmdQueue}} = (); #\@hlCmdQueue;
    # $hash->{SERVICE} = 48899;
    # search if this bridge is already defined 
    # if so, we need a shared buffer (llCmdQueue), shared socket and we need to check if the requied slot is free
    foreach $key (keys %defs) 
    {
      if (($defs{$key}{TYPE} eq 'WifiLight') && ($defs{$key}{IP} eq $hash->{IP}) && ($defs{$key}{PORT} eq $hash->{PORT}) && ($key ne $name))
      {
        #bridge is in use
        Log3 (undef, 3, "WifiLight: requested bridge $hash->{CONNECTION} at $hash->{IP} already in use by $key, copy llCmdQueue");
        $hash->{helper}->{llCmdQueue} = $defs{$key}{helper}{llCmdQueue};
        $hash->{helper}->{llLock} = 0;
        $hash->{helper}->{SOCKET} = $defs{$key}{helper}{SOCKET};
        $hash->{helper}->{SELECT} = $defs{$key}{helper}{SELECT};
        my $slotInUse = $defs{$key}{SLOT};
        $otherLights->{$slotInUse} = $defs{$key};
      }
    } 
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => 48899,
        Blocking => 0,
        Proto => 'udp',
        Broadcast => 1) or return "can't bind: $@";
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }
  
  if ($a[3] =~ m/(LW12):([^:]+):*(\d+)*/g)
  {
    return "only RGB supported by LW12" if ($a[2] ne "RGB"); 
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5577;
    $hash->{PROTO} = 1;
    #$hash->{SERVICE} = 48899;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }

  if ($a[3] =~ m/(LW12HX):([^:]+):*(\d+)*/g)
  {
    return "only RGB supported by LW12HX" if ($a[2] ne "RGB"); 
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5000;
    $hash->{PROTO} = 1;
    #$hash->{SERVICE} = 48899;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }

  if ($a[3] =~ m/(LW12FC):([^:]+):*(\d+)*/g)
  {
    return "only RGB supported by LW12FC" if ($a[2] ne "RGB"); 
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5000;
    #$hash->{PROTO} = 1;
    #$hash->{SERVICE} = 48899;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Blocking => 0,
        Proto => 'udp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }

  if ($a[3] =~ m/(LD316):([^:]+):*(\d+)*/g)
  {
    return "only RGBW supported by LD316" if ($a[2] ne "RGBW"); 
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5577;
    $hash->{PROTO} = 1;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }
  
  if ($a[3] =~ m/(LD316A):([^:]+):*(\d+)*/g)
  {
    return "only RGBW supported by LD316A" if ($a[2] ne "RGBW"); 
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5577;
    $hash->{PROTO} = 1;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }

  if ($a[3] =~ m/(LD382):([^:]+):*(\d+)*/g)
  {
    return "only RGB and RGBW supported by LD382" if (($a[2] ne "RGB") && ($a[2] ne "RGBW"));
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5577;
    $hash->{PROTO} = 1;
    #$hash->{SERVICE} = 48899;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }

  if ($a[3] =~ m/(LD382A):([^:]+):*(\d+)*/g)
  {
    return "only RGB and RGBW supported by LD382A" if (($a[2] ne "RGB") && ($a[2] ne "RGBW"));
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:5577;
    $hash->{PROTO} = 1;
    #$hash->{SERVICE} = 48899;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }
  
  if ($a[3] =~ m/(SENGLED):([^:]+):*(\d+)*/g)
  {
    return "only White supported by SENGLED" if ($a[2] ne "White"); 
    $hash->{CONNECTION} = $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:9060;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Blocking => 0,
        Proto => 'udp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }
  
  if ($a[3] =~ m/(SUNRICHER):([^:]+):*(\d+)*/gi)
  {
    # return "only White, DualWhite, RGB, RGBW supported by Sunricher" if ($a[2] ne 'RGBW');
    $hash->{CONNECTION} = uc $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:8899;
    $hash->{PROTO} = 1;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    @{$hash->{helper}->{llCmdQueue}} = ();
    $hash->{helper}->{llLock} = 0;
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
    }
  }

  if ($a[3] =~ m/(SUNRICHERA):([^:]+):*(\d+)*/gi)
  {
    # return "only White, DualWhite, RGB, RGBW supported by Sunricher" if ($a[2] ne 'RGBW');
    $hash->{CONNECTION} = uc $1;
    $hash->{IP} = $2;
    $hash->{PORT} = $3?$3:8899;
    $hash->{PROTO} = 1;
    $hash->{SLOT} = 0;
    @{$hash->{helper}->{hlCmdQueue}} = ();
    if (!defined($hash->{helper}->{SOCKET}))
    {
      my $sock = IO::Socket::INET-> new (
        PeerPort => $hash->{PORT},
        PeerAddr => $hash->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
      my $select = IO::Select->new($sock);
      $hash->{helper}->{SOCKET} = $sock;
      $hash->{helper}->{SELECT} = $select;
      @{$hash->{helper}->{llCmdQueue}} = ();
      $hash->{helper}->{llLock} = 0;
    }
  }
  
  return "unknown connection type, see documentation" if !(defined($hash->{CONNECTION})); 

  Log3 ($hash, 4, "define $a[0] $a[1] $a[2] $a[3]");

  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} =~ 'LW12'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 0.75, 0.25';
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} =~ 'LW12HX'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 0.75, 0.25';   
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} =~ 'LW12FC'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.85);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 0.85, 0.55';   
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGBW') && ($hash->{CONNECTION} =~ 'LD316'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -25, -15, -25, 0, -20';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1.0, 0.6, 0.065';
    return undef;
  }
  
  if (($hash->{LEDTYPE} eq 'RGBW') && ($hash->{CONNECTION} =~ 'LD316A'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -25, -15, -25, 0, -20';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1.0, 0.6, 0.065';
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGBW') && ($hash->{CONNECTION} =~ 'LD382'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 1, 1';
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} =~ 'LD382'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 0.75, 0.25';
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGBW') && ($hash->{CONNECTION} =~ 'LD382A'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 1, 1';
    return undef;
  }

  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} =~ 'LD382A'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10';
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 0.75, 0.25';
    return undef;
  }

  if ((($hash->{LEDTYPE} eq 'RGB') || ($hash->{LEDTYPE} eq 'RGBW1')) && ($hash->{CONNECTION} =~ 'bridge-V[2|3]'))
  {
    return "no free slot at $hash->{CONNECTION} ($hash->{IP}) for $hash->{LEDTYPE}" if (defined($otherLights->{0}));
    $hash->{SLOT} = 0;
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 1);
    $hash->{helper}->{COLORMAP} = WifiLight_Milight_ColorConverter($hash);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB sync pair unpair";
    #if we are allready paired: sync to get a defined state
    return WifiLight_RGB_Sync($hash) if ($hash->{LEDTYPE} eq 'RGB');
    return WifiLight_RGBW1_Sync($hash) if ($hash->{LEDTYPE} eq 'RGBW1');
  }
  elsif (($hash->{LEDTYPE} eq 'RGBW2')  && ($hash->{CONNECTION} =~ 'bridge-V3'))
  {
    # find a free slot
    my $i = 5;
    while (defined($otherLights->{$i}))
    {
      $i++;
    }
    if ( grep { $i == $_ } 5..8 )
    { 
      $hash->{SLOT} = $i;
      $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.73);
      $hash->{helper}->{COLORMAP} = WifiLight_Milight_ColorConverter($hash);
      $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB sync pair unpair";
      return WifiLight_RGBW2_Sync($hash);
    }
    else
    {
      return "no free slot at $hash->{CONNECTION} ($hash->{IP}) for $hash->{LEDTYPE}";
    }
  }
  elsif (($hash->{LEDTYPE} eq 'White')  && ($hash->{CONNECTION} =~ 'bridge-V[2|3]'))
  {
    # find a free slot
    my $i = 1;
    while (defined($otherLights->{$i}))
    {
      $i++;
    }
    if ( grep { $i == $_ } 1..4 )
    { 
      $hash->{SLOT} = $i;
      $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.8);
      $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown sync pair unpair";
      return WifiLight_White_Sync($hash);
    }
    else
    {
      return "no free slot at $hash->{CONNECTION} ($hash->{IP}) for $hash->{LEDTYPE}";
    }
  }
  
  if (($hash->{LEDTYPE} eq 'White') && ($hash->{CONNECTION} =~ 'SENGLED'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 1);
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown";
    return undef;
  }
  
  if (($hash->{LEDTYPE} eq 'DualWhite') && ($hash->{CONNECTION} eq 'SUNRICHER'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65); # TODO CHECK VALUES
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown";
    $hash->{helper}->{wLevel} = 0;
    # color cast defaults in r,y, g, c, b, m: +/-30°
    # my $cc = '0, -20, -20, -25, 0, -10'; # TODO CHECK VALUES
    # $attr{$name}{"colorCast"} = $cc;
    # WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    # $attr{$name}{"whitePoint"} = '1, 1, 1';
    return undef;
  }
  
  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} eq 'SUNRICHER'))
  {
    $hash->{helper}->{COMMANDSET} = 'on off dim dimup dimdown HSV HSVK CT RGB';
    # init helper
    $hash->{helper}->{rLevel} = 0;
    $hash->{helper}->{gLevel} = 0;
    $hash->{helper}->{bLevel} = 0;
    # init converter
    $hash->{helper}->{cmd_pwr} = 'RGBSunricher_setPWR';
    $hash->{helper}->{cmd_hsv} = 'RGBSunricher_setHSV';
    # defaults
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65); # TODO CHECK VALUES
    # color cast defaults
    my $cc = '0, -20, -20, -25, 0, -10'; # TODO CHECK VALUES
    $attr{$name}{"colorCast"} = '0, -20, -20, -25, 0, -10';
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 1, 1';
    # TODO init readings
    return undef;
  }
  
  if (($hash->{LEDTYPE} eq 'RGB') && ($hash->{CONNECTION} eq 'SUNRICHERA'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65); # TODO CHECK VALUES
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    $hash->{helper}->{rLevel} = 0;
    $hash->{helper}->{gLevel} = 0;
    $hash->{helper}->{bLevel} = 0;
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10'; # TODO CHECK VALUES
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 1, 1';
    return undef;
  }
  
  if (($hash->{LEDTYPE} eq 'RGBW') && ($hash->{CONNECTION} eq 'SUNRICHER'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65); # TODO CHECK VALUES
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    $hash->{helper}->{rLevel} = 0;
    $hash->{helper}->{gLevel} = 0;
    $hash->{helper}->{bLevel} = 0;
    $hash->{helper}->{wLevel} = 0;
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10'; # TODO CHECK VALUES
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 1, 1';
    return undef;
  }
  
  if (($hash->{LEDTYPE} eq 'RGBW') && ($hash->{CONNECTION} eq 'SUNRICHERA'))
  {
    $hash->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($hash, 0.65); # TODO CHECK VALUES
    $hash->{helper}->{COMMANDSET} = "on off dim dimup dimdown HSV RGB";
    $hash->{helper}->{rLevel} = 0;
    $hash->{helper}->{gLevel} = 0;
    $hash->{helper}->{bLevel} = 0;
    $hash->{helper}->{wLevel} = 0;
    # color cast defaults in r,y, g, c, b, m: +/-30°
    my $cc = '0, -20, -20, -25, 0, -10'; # TODO CHECK VALUES
    $attr{$name}{"colorCast"} = $cc;
    WifiLight_RGB_ColorConverter($hash, split(',', $cc));
    # white point defaults in r,g,b
    $attr{$name}{"whitePoint"} = '1, 1, 1';
    return undef;
  }
  
  return "$hash->{LEDTYPE} is not supported at $hash->{CONNECTION} ($hash->{IP})";
}

sub
WifiLight_Undef(@)
{
  return undef;
}

sub
WifiLight_Set(@)
{
  my ($ledDevice, $name, $cmd, @args) = @_;
  my $descriptor = '';
  
  # remove descriptor from @args
  for (my $i = $#args; $i >= 0; --$i )
  {
    if ($args[$i] =~ /\/d\:(.*)/)
    {
      $descriptor = $1;
      splice (@args, $i, 1);
    }
  }
  
  my $cnt = @args;
  my $ramp = 0;
  my $flags = "";
  my $event = undef;

  my $cmdSet = $ledDevice->{helper}->{COMMANDSET}; 
  return "unknown command ($cmd): choose one of ".join(", ", $cmdSet) if ($cmd eq "?"); 
  return "unknown command ($cmd): choose one of ".$ledDevice->{helper}->{COMMANDSET} if ($cmd ne 'RGB') and not ( grep { $cmd eq $_ } split(" ", $ledDevice->{helper}->{COMMANDSET} ));

  if ($cmd eq 'pair')
  {
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    if (defined($args[0]))
    {
      return "usage: set $name pair [seconds]" if ($args[0] !~ /^\d+$/);
      $ramp = $args[0];
    }
    return WifiLight_RGB_Pair($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_Pair($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_Pair($ledDevice, $ramp) if ($ledDevice->{LEDTYPE} eq 'RGBW2');
    return WifiLight_White_Pair($ledDevice, $ramp) if ($ledDevice->{LEDTYPE} eq 'White');
  }

  if ($cmd eq 'unpair')
  {
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    if (defined($args[0]))
    {
      return "usage: set $name unpair [seconds]" if ($args[0] !~ /^\d+$/);
      $ramp = $args[0];
    }
    return WifiLight_RGB_UnPair($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_UnPair($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_UnPair($ledDevice, $ramp) if ($ledDevice->{LEDTYPE} eq 'RGBW2');
    return WifiLight_White_UnPair($ledDevice, $ramp) if ($ledDevice->{LEDTYPE} eq 'White');
  }

  if ($cmd eq 'sync')
  {
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    return WifiLight_RGB_Sync($ledDevice) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_Sync($ledDevice) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_Sync($ledDevice) if ($ledDevice->{LEDTYPE} eq 'RGBW2');
    return WifiLight_White_Sync($ledDevice) if ($ledDevice->{LEDTYPE} eq 'White');
  }
  
  if (($cmd eq 'HSV') || ($cmd eq 'RGB') || ($cmd eq 'dim'))
  {
    $args[1] = AttrVal($ledDevice->{NAME}, "defaultRamp", 0) if !defined($args[1]);
  }
  else
  {
    $args[0] = AttrVal($ledDevice->{NAME}, "defaultRamp", 0) if !defined($args[0]);
  }

  if ($cmd eq 'on')
  {
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    if (defined($args[0]))
    {
      return "usage: set $name on [seconds]" if ($args[0] !~ /^\d?.?\d+$/);
      $ramp = $args[0];
    }
    return WifiLight_RGBWLD316_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316'));
    return WifiLight_RGBWLD316A_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316A'));
    return WifiLight_RGBWLD382_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBLD382_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBWLD382A_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLD382A_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLW12_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12'));
    return WifiLight_RGBLW12HX_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12HX'));
    return WifiLight_RGBLW12FC_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12FC'));
    return WifiLight_WhiteSENGLED_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'));
    return WifiLight_RGB_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} eq 'bridge-V3'));
    return WifiLight_White_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_DualWhiteSunricher_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'DualWhite') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
    return WifiLight_RGBSunricher_On($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
  }

  if ($cmd eq 'off')
  {
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    if (defined($args[0]))
    {
      return "usage: set $name off [seconds]" if ($args[0] !~ /^\d?.?\d+$/);
      $ramp = $args[0];
    }
    return WifiLight_RGBWLD316_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316'));
    return WifiLight_RGBWLD316A_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316A'));
    return WifiLight_RGBWLD382_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBLD382_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBWLD382A_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLD382A_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLW12_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12'));
    return WifiLight_RGBLW12HX_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12HX'));
    return WifiLight_RGBLW12FC_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12FC'));
    return WifiLight_WhiteSENGLED_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'));
    return WifiLight_RGB_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} eq 'bridge-V3'));
    return WifiLight_White_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_DualWhiteSunricher_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} eq 'DualWhite') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
    return WifiLight_RGBSunricher_Off($ledDevice, $ramp) if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
  }

  if ($cmd eq 'dimup')
  {
    return "usage: set $name dimup" if (defined($args[1]));
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    my $v = ReadingsVal($ledDevice->{NAME}, "brightness", 0) + AttrVal($ledDevice->{NAME}, "dimStep", 7);
    $v = 100 if $v > 100;
    return WifiLight_RGBWLD316_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316'));
    return WifiLight_RGBWLD316A_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316A'));
    return WifiLight_RGBWLD382_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBLD382_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBWLD382A_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLD382A_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLW12_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12'));
    return WifiLight_RGBLW12HX_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12HX'));
    return WifiLight_RGBLW12FC_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12FC'));
    return WifiLight_WhiteSENGLED_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'));
    return WifiLight_RGB_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} eq 'bridge-V3'));
    return WifiLight_White_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_DualWhiteSunricher_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'DualWhite') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
    return WifiLight_RGBSunricher_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
  }

  if ($cmd eq 'dimdown')
  {
    return "usage: set $name dimdown" if (defined($args[1]));
    WifiLight_HighLevelCmdQueue_Clear($ledDevice);
    my $v = ReadingsVal($ledDevice->{NAME}, "brightness", 0) - AttrVal($ledDevice->{NAME}, "dimStep", 7);
    $v = 0 if $v < 0;
    return WifiLight_RGBWLD316_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316'));
    return WifiLight_RGBWLD316A_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316A'));
    return WifiLight_RGBWLD382_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBLD382_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBWLD382A_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLD382A_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLW12_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12'));
    return WifiLight_RGBLW12HX_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12HX'));
    return WifiLight_RGBLW12FC_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12FC'));
    return WifiLight_WhiteSENGLED_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'));
    return WifiLight_RGB_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} eq 'bridge-V3'));
    return WifiLight_White_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_DualWhiteSunricher_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} eq 'DualWhite') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
    return WifiLight_RGBSunricher_Dim($ledDevice, $v, 0, '') if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
  }

  if ($cmd eq 'dim')
  {
    return "usage: set $name dim level [seconds]" if ($args[0] !~ /^\d+$/);
    return "usage: set $name dim level [seconds]" if (($args[0] < 0) || ($args[0] > 100));
    if (defined($args[1]))
    {
      return "usage: set $name dim level [seconds] [q]" if ($args[1] !~ /^\d?.?\d+$/);
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return "usage: set $name dim level seconds [q]" if ($args[2] !~ m/.*[qQ].*/);
      $flags = $args[2];
    }
    WifiLight_HighLevelCmdQueue_Clear($ledDevice) if ($flags !~ m/.*[qQ].*/);
    return WifiLight_RGBWLD316_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316'));
    return WifiLight_RGBWLD316A_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316A'));
    return WifiLight_RGBWLD382_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBLD382_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382'));
    return WifiLight_RGBWLD382A_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLD382A_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382A'));
    return WifiLight_RGBLW12_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12'));
    return WifiLight_RGBLW12HX_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12HX'));
    return WifiLight_RGBLW12FC_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LW12FC'));
    return WifiLight_WhiteSENGLED_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'));
    return WifiLight_RGB_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW1_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_RGBW2_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} eq 'bridge-V3'));
    return WifiLight_White_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    return WifiLight_DualWhiteSunricher_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} eq 'DualWhite') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
    return WifiLight_RGBSunricher_Dim($ledDevice, $args[0], $ramp, $flags) if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
  }

  if (($cmd eq 'HSV') || ($cmd eq 'RGB'))
  {
    my ($hue, $sat, $val);
    
    if ($cmd eq 'HSV')
    {
      return "HSV is required as h,s,v" if (defined($args[0]) && $args[0] !~ /^\d{1,3},\d{1,3},\d{1,3}$/);
      ($hue, $sat, $val) = split(',', $args[0]);
      return "wrong hue ($hue): valid range 0..360" if !(($hue >= 0) && ($hue <= 360));
      return "wrong saturation ($sat): valid range 0..100" if !(($sat >= 0) && ($sat <= 100));
      return "wrong brightness ($val): valid range 0..100" if !(($val >= 0) && ($val <= 100));
    }
    elsif ($cmd eq 'RGB')
    {
      return "RGB is required hex RRGGBB" if (defined($args[0]) && $args[0] !~ /^[0-9A-Fa-f]{6}$/);
      ($hue, $sat, $val) = WifiLight_RGB2HSV($ledDevice, $args[0]);
    }
    
    if (defined($args[1]))
    {
      return "usage: set $name HSV H,S,V seconds flags programm" if ($args[1] !~ /^\d?.?\d+$/);
      $ramp = $args[1];
    }
    if (defined($args[2]))
    {   
      return "usage: set $name HSV H,S,V seconds [slq] programm" if ($args[2] !~ m/.*[sSlLqQ].*/);
      $flags = $args[2];
    }
    if (defined($args[3]))
    {   
      return "usage: set $name HSV H,S,V seconds flags programm=[A-Za-z_0-9]" if ($args[3] !~ m/[A-Za-z_0-9]*/);
      $event = $args[3];
    }
    WifiLight_HighLevelCmdQueue_Clear($ledDevice) if ($flags !~ m/.*[qQ].*/);
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LD316');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LD316A');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LD382');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LD382A');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LW12');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LW12HX');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if ($ledDevice->{CONNECTION} eq 'LW12FC');
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 500, $event) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 1000, $event) if (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 200, $event) if (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
    WifiLight_HSV_Transition($ledDevice, $hue, $sat, $val, $ramp, $flags, 100, $event) if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
    return WifiLight_SetHSV_Target($ledDevice, $hue, $sat, $val);
  }
}

sub
WifiLight_Get(@)
{
  my ($ledDevice, $name, $cmd, @args) = @_;
  my $cnt = @args;
  
  return undef;
}

sub
WifiLight_Attr(@)
{
  my ($cmd, $device, $attribName, $attribVal) = @_;
  my $ledDevice = $defs{$device};

  if ($cmd eq 'set' && $attribName eq 'gamma')
  {
    return "gamma is required as numerical value (eg. 0.5 or 2.2)" if ($attribVal !~ /^\d*\.\d*$/);
    $ledDevice->{helper}->{GAMMAMAP} = WifiLight_CreateGammaMapping($ledDevice, $attribVal);
  }
  if ($cmd eq 'set' && $attribName eq 'dimStep')
  {
    return "dimStep is required as numerical value [1..100]" if ($attribVal !~ /^\d*$/) || (($attribVal < 1) || ($attribVal > 100));
  }
  if ($cmd eq 'set' && $attribName eq 'defaultColor')
  {
    return "defaultColor is required as HSV" if ($attribVal !~ /^\d{1,3},\d{1,3},\d{1,3}$/);
    my ($hue, $sat, $val) = split(',', $attribVal);
    return "defaultColor: wrong hue ($hue): valid range 0..360" if !(($hue >= 0) && ($hue <= 360));
    return "defaultColor: wrong saturation ($sat): valid range 0..100" if !(($sat >= 0) && ($sat <= 100));
    return "defaultColor: wrong brightness ($val): valid range 0..100" if !(($val >= 0) && ($val <= 100));
  }
  my @a = ();
  if ($cmd eq 'set' && $attribName eq 'colorCast')
  {
    @a = split(',', $attribVal);
    my $msg =  "colorCast: correction require red, yellow, green ,cyan, blue, magenta (each in a range of -29 .. 29)";
    return $msg unless (@a == 6);  
    foreach my $tc (@a)
    {
      return $msg unless ($tc =~ m/^\s*[\-]{0,1}[0-9]+[\.]{0,1}[0-9]*\s*$/g);
      return $msg if (abs($tc) >= 30);
    }
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LD316');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LD316A');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LD382');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LD382A');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LW12');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LW12HX');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} eq 'LW12FC');
    WifiLight_Milight_ColorConverter($ledDevice, @a) if ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]');
    WifiLight_RGB_ColorConverter($ledDevice, @a) if (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/));
    if ($init_done && !(@{$ledDevice->{helper}->{hlCmdQueue}}))
    {
      my $hue = $ledDevice->{READINGS}->{hue}->{VAL};
      my $sat = $ledDevice->{READINGS}->{saturation}->{VAL};
      my $val = $ledDevice->{READINGS}->{brightness}->{VAL};
      WifiLight_setHSV($ledDevice, $hue, $sat, $val, 1);
    }
  }
  if ($cmd eq 'set' && $attribName eq 'whitePoint')
  {
    @a = split(',', $attribVal);
    my $msg =  "whitePoint: correction require red, green, blue (each in a range of 0.0 ..1.0)";
    return $msg unless (@a == 3);  
    foreach my $tc (@a)
    {
      return $msg unless ($tc =~ m/^\s*[0-9]+?[\.]{0,1}[0-9]*\s*$/g);
      return $msg if (($tc < 0) || ($tc > 1));
    }
    if ($init_done && !(@{$ledDevice->{helper}->{hlCmdQueue}}))
    {
      $attr{$device}{"whitePoint"} = $attribVal;
      my $hue = $ledDevice->{READINGS}->{hue}->{VAL};
      my $sat = $ledDevice->{READINGS}->{saturation}->{VAL};
      my $val = $ledDevice->{READINGS}->{brightness}->{VAL};
      WifiLight_setHSV($ledDevice, $hue, $sat, $val, 1);
    }
  }

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} attrib $attribName $cmd $attribVal") if $attribVal; 
  return undef;
}

# restore previous settings (as set statefile)
sub
WifiLight_Notify(@)
{
  my ($ledDevice, $eventSrc) = @_;
  my $events = deviceEvents($eventSrc, 1);
  my ($hue, $sat, $val);

  # wait for global: INITIALIZED after start up
  if ($eventSrc->{NAME} eq 'global' && @{$events}[0] eq 'INITIALIZED')
  {
    #######################################################
    # TODO remove in a few weeks. its here for convenience
    delete($ledDevice->{READINGS}->{HUE});
    delete($ledDevice->{READINGS}->{SATURATION});
    delete($ledDevice->{READINGS}->{BRIGHTNESS});
    #######################################################
    if ($ledDevice->{CONNECTION} eq 'LW12') 
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBLW12_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif ($ledDevice->{CONNECTION} eq 'LW12HX') 
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBLW12HX_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif ($ledDevice->{CONNECTION} eq 'LW12FC') 
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBLW12FC_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif ($ledDevice->{CONNECTION} eq 'LD316')
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBWLD316_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif ($ledDevice->{CONNECTION} eq 'LD316A')
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBWLD316A_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif ($ledDevice->{CONNECTION} eq 'LD382')
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBWLD382_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif ($ledDevice->{CONNECTION} eq 'LD382A')
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBWLD382A_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'))
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:60;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:100;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:100;
      return WifiLight_RGB_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif (($ledDevice->{LEDTYPE} eq 'RGBW1') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'))
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:50;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:100;
      return WifiLight_RGBW1_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif (($ledDevice->{LEDTYPE} eq 'RGBW2') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'))
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:0;
      return WifiLight_RGBW2_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'))
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:100;
      return WifiLight_White_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'))
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:100;
      return WifiLight_WhiteSENGLED_setHSV($ledDevice, $hue, $sat, $val);
    }
    elsif (($ledDevice->{LEDTYPE} =~ /^RGB.?$/) && ($ledDevice->{CONNECTION} =~ /^SUNRICHER.?$/))
    {
      $hue = defined($ledDevice->{READINGS}->{hue}->{VAL})?$ledDevice->{READINGS}->{hue}->{VAL}:0;
      $sat = defined($ledDevice->{READINGS}->{saturation}->{VAL})?$ledDevice->{READINGS}->{saturation}->{VAL}:0;
      $val = defined($ledDevice->{READINGS}->{brightness}->{VAL})?$ledDevice->{READINGS}->{brightness}->{VAL}:100;
      return WifiLight_RGBSunricher_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
      return WifiLight_RGBSunricherA_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'SUNRICHERA'));
      return WifiLight_RGBWSunricher_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
      return WifiLight_RGBWSunricherA_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'SUNRICHERA'));
    }
    # 
    else
    {
    }
    return 
  }
}

###############################################################################
#
# generic device types
# RGB device
#
#
###############################################################################


sub
WifiLight_RGBDevice_On(@)
{
  my ($ledDevice, $ramp) = @_;
  
  my $delay = 50;
  my $on = pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x02, 0x12, 0xAB, 0x00, 0xAA, 0xAA );
  my $receiver;
  
  $on = WifiLight_Sunricher_Checksum($ledDevice, $on);
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  
  # TODO device specific on
  
  my ($h, $s, $v, $k) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100, 3200"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} $ledDevice->{LEDTYPE} $ledDevice->{CONNECTION} set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBDevice_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} $ledDevice->{LEDTYPE} $ledDevice->{CONNECTION} set off $ramp");
  return WifiLight_RGBDevice_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBDevice_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} $ledDevice->{LEDTYPE} $ledDevice->{CONNECTION} dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}



###############################################################################
#
# device specific controller functions DualWhite SUNRICHER
# 
#
#
###############################################################################


sub
WifiLight_DualWhiteSunricher_On(@)
{
  my ($ledDevice, $ramp) = @_;
  
  my $delay = 50;
  my $on = pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x02, 0x12, 0xAB, 0x00, 0xAA, 0xAA );
  my $receiver;
  
  $on = WifiLight_Sunricher_Checksum($ledDevice, $on);
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} DualWhite Sunricher set on ($v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_DualWhiteSunricher_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} DualWhite Sunricher set off $ramp");
  return WifiLight_DualWhiteSunricher_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_DualWhiteSunricher_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} DualWhite Sunricher dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_DualWhiteSunricher_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val, $ct) = @_;
  my $receiver; # = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 0;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} DualWhite Sunricher set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];
  
  my $wt = int($gammaVal * 0x40 / 100);
  
  my $msg;
  # Me$msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x36, 0x10, 0x00, 0xAA, 0xAA));
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x33, $wt, 0x00, 0xAA, 0xAA));
  
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions RGBW SUNRICHER
# device range 0x00 0xff
#
#
###############################################################################


sub
WifiLight_RGBSunricher_On(@)
{
  my ($ledDevice, $ramp) = @_;
  
  my $delay = 50;
  my $on = pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x02, 0x12, 0xAB, 0x00, 0xAA, 0xAA );
  my $receiver;
  
  $on = WifiLight_Sunricher_Checksum($ledDevice, $on);
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} $ledDevice->{LEDTYPE} $ledDevice->{CONNECTION} set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBSunricher_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} $ledDevice->{LEDTYPE} $ledDevice->{CONNECTION} set off $ramp");
  return WifiLight_RGBWLD382_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBSunricher_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} $ledDevice->{LEDTYPE} $ledDevice->{CONNECTION} dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

###############################################################################
#
#  SUNRICHER Color conversation functions
# 
#
#
###############################################################################

sub
WifiLight_RGBSunricher_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver; # = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 0;
  my $msg = '';

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW Sunricher set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 
  
  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  
  $rr = int( $rr * 0x80 / 0xFF );
  $rg = int( $rg * 0x80 / 0xFF );
  $rb = int( $rb * 0x80 / 0xFF );
  $white = int( $white * 0x80 / 0xFF );
  
  # TODO CT and white point correction
  $rr += $white;
  $rg += $white;
  $rb += $white;
  
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x18, $rr, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{rLevel} != $rr);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x19, $rg, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{gLevel} != $rg);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x20, $rb, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{bLevel} != $rb);
  
  $ledDevice->{helper}->{rLevel} = $rr;
  $ledDevice->{helper}->{rLevel} = $rg;
  $ledDevice->{helper}->{rLevel} = $rb;
  
  # leave here if nothing to tell
  return unless $msg;
  
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}
sub
WifiLight_RGBSunricherA_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver; # = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 0;
  my $msg = '';

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW Sunricher set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 
  
  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  
  # TODO CT and white point correction
  $rr += $white;
  $rg += $white;
  $rb += $white;
  
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x18, $rr, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{rLevel} != $rr);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x19, $rg, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{gLevel} != $rg);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x20, $rb, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{bLevel} != $rb);
  
  $ledDevice->{helper}->{rLevel} = $rr;
  $ledDevice->{helper}->{rLevel} = $rg;
  $ledDevice->{helper}->{rLevel} = $rb;
  
  # leave here if nothing to tell
  return unless $msg;
  
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

sub
WifiLight_RGBWSunricher_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver; # = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 0;
  my $msg = '';

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW Sunricher set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 
  
  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  
  $rr = int( $rr * 0x80 / 0xFF );
  $rg = int( $rg * 0x80 / 0xFF );
  $rb = int( $rb * 0x80 / 0xFF );
  $white = int( $white * 0x80 / 0xFF );
  
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x18, $rr, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{rLevel} != $rr);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x19, $rg, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{gLevel} != $rg);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x20, $rb, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{bLevel} != $rb);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x21, $white, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{wLevel} != $white);
  
  $ledDevice->{helper}->{rLevel} = $rr;
  $ledDevice->{helper}->{rLevel} = $rg;
  $ledDevice->{helper}->{rLevel} = $rb;
  $ledDevice->{helper}->{rLevel} = $white;
  
  # leave here if nothing to tell
  return unless $msg;
  
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

sub
WifiLight_RGBWSunricherA_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver; # = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 0;
  my $msg = '';

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW Sunricher set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 
  
  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  
  $rr *= 0x80 / 0xFF;
  
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x18, $rr, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{rLevel} != $rr);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x19, $rg, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{gLevel} != $rg);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x20, $rb, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{bLevel} != $rb);
  $msg .= WifiLight_Sunricher_Checksum($ledDevice, pack('C*', 0x55, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x08, 0x21, $white, 0x00, 0xAA, 0xAA)) if ($ledDevice->{helper}->{wLevel} != $white);
  
  $ledDevice->{helper}->{rLevel} = $rr;
  $ledDevice->{helper}->{rLevel} = $rg;
  $ledDevice->{helper}->{rLevel} = $rb;
  $ledDevice->{helper}->{rLevel} = $white;
  
  # leave here if nothing to tell
  return unless $msg;
  
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
#  SUNRICHER helper functions
# 
#
###############################################################################

sub
WifiLight_Sunricher_Checksum(@)
{
  my ($ledDevice, $msg) = @_;
  
  my @byteStream = unpack('C*', $msg);
  my $l = @byteStream;
  my $c = 0;
  
  for (my $i=4; $i<($l-3); $i++) {
    $c += $byteStream[$i];
  }
  $c %= 0x100;
  $byteStream[$l -3]  = $c;
  $msg = pack('C*', @byteStream);
  return $msg;
}

###############################################################################
#
# device specific controller functions RGBW LD316
# aka XScource 
#
#
###############################################################################

sub
WifiLight_RGBWLD316_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c", 0xCC, 0x23, 0x33);
  my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD316 set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBWLD316_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD316 set off $ramp");
  return WifiLight_RGBWLD316_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBWLD316_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD316 dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBWLD316_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val, $k) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW LD316 set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction, may be doing it after wb more ok
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  ##########################################
  # sat is spread by 10% so there is room
  # for a smoth switch to white and adapt to 
  # higher brightness of white led
  ##########################################  

  $sat = ($sat * 1.1) -10;
  my $wl = ($sat<0)?$sat * -1:0;
  $sat = ($sat<0)?0:$sat;

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my $msg;

  ##########################################
  # experimental white temp adjustment
  # G - 50%
  # B - 04%
  # sat is spread by 10% so there is room
  # for a smoth switch to white and adapt to 
  # higher brightness of whte led
  ##########################################

  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  # rgb mode
  if (($val > 0) && ($wl == 0)) 
  {
    #replace the removed part of white light and apply white balance
    $rr += int(($white * $wr) + 0.5);
    $rg += int(($white * $wg) + 0.5);
    $rb += int(($white * $wb) + 0.5);

    #new proto 0x56, r, g, b, white level, f0 (color) || 0f (white), 0xaa (terminator)
    $msg = sprintf("%c%c%c%c%c%c%c", 0x56, $rr, $rg, $rb, 0x00, 0xF0, 0xAA);
  }
  elsif ($wl > 0)
  {
    #smoth brightness adaption of white led
    my $wo = $gammaVal - ($gammaVal * (10-$wl) * 0.08); #0.07
    $wo = int(0.5 + ($wo * 2.55));
    $msg = sprintf("%c%c%c%c%c%c%c", 0x56, 0, 0, 0, $wo, 0x0F, 0xAA);
  }
  else
  {
    $msg = sprintf("%c%c%c%c%c%c%c", 0x56, 0, 0, 0, 0x00, 0xF0, 0xAA);
  }
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions RGBW LD316A - new fw. 
# thnx raspklaus
#
###############################################################################

sub
WifiLight_RGBWLD316A_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c%c", 0x71, 0x23, 0x0F, 0xA3);
  my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD316A set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBWLD316A_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD316A set off $ramp");
  return WifiLight_RGBWLD316_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBWLD316A_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD316A dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBWLD316A_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW LD316A set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction, may be doing it after wb more ok
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  ##########################################
  # sat is spread by 10% so there is room
  # for a smoth switch to white and adapt to 
  # higher brightness of white led
  ##########################################  

  $sat = ($sat * 1.1) -10;
  my $wl = ($sat<0)?$sat * -1:0;
  $sat = ($sat<0)?0:$sat;

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my $msg;

  ##########################################
  # experimental white temp adjustment
  # G - 50%
  # B - 04%
  # sat is spread by 10% so there is room
  # for a smoth switch to white and adapt to 
  # higher brightness of whte led
  ##########################################

  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  # rgb mode
  if (($val > 0) && ($wl == 0)) 
  {
    #replace the removed part of white light and apply white balance
    $rr += int(($white * $wr) + 0.5);
    $rg += int(($white * $wg) + 0.5);
    $rb += int(($white * $wb) + 0.5);

    #new proto 0x56, r, g, b, white level, f0 (color) || 0f (white), 0xaa (terminator)
    $msg = sprintf("%c%c%c%c%c%c%c", 0x31, $rr, $rg, $rb, 0x00, 0xF0, 0x0F);
  }
  elsif ($wl > 0)
  {
    #smoth brightness adaption of white led
    my $wo = $gammaVal - ($gammaVal * (10-$wl) * 0.08); #0.07
    $wo = int(0.5 + ($wo * 2.55));
    $msg = sprintf("%c%c%c%c%c%c%c", 0x31, 0, 0, 0, $wo, 0x0F, 0x0F);
  }
  else
  {
    $msg = sprintf("%c%c%c%c%c%c%c", 0x31, 0, 0, 0, 0x00, 0xF0, 0x0F);
  }
  #add checksum
  $msg = WifiLight_RGBWLD382_Checksum($ledDevice, $msg);
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions LD382 aka Magic UFO
# with RGBW stripe (RGB and white)
#
#
###############################################################################

sub
WifiLight_RGBWLD382_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c", 0x71, 0x23, 0x94);
  my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD382 set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBWLD382_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD382 set off $ramp");
  return WifiLight_RGBWLD382_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBWLD382_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD382 dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBWLD382_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW LD382 set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my $msg = sprintf("%c%c%c%c%c%c%c", 0x31, $rr, $rg, $rb, $white, 0x00, 0x00);
  #add checksum
  $msg = WifiLight_RGBWLD382_Checksum($ledDevice, $msg);
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

sub
WifiLight_RGBWLD382_Checksum(@)
{
  my ($ledDevice, $msg) = @_;
  my $c = 0;
  foreach my $w (split //, $msg)
  {
    $c += ord($w);
  }
  $c %= 0x100;
  $msg .= sprintf("%c", $c);
  return $msg;
}

###############################################################################
#
# device specific controller functions LD382 aka Magic UFO
# with RGB stripe (mixed white)
#
#
###############################################################################

sub
WifiLight_RGBLD382_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c", 0x71, 0x23, 0x94);
  my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LD382 set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBLD382_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LD382 set off $ramp");
  return WifiLight_RGBLD382_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBLD382_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LD382 dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBLD382_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB LD382 set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  #replace the removed part of white light and apply white balance
  $rr += int(($white * $wr) + 0.5);
  $rg += int(($white * $wg) + 0.5);
  $rb += int(($white * $wb) + 0.5);

  my $msg = sprintf("%c%c%c%c%c%c%c", 0x31, $rr, $rg, $rb, 0x00, 0x00, 0x00);
  #add checksum
  $msg = WifiLight_RGBWLD382_Checksum($ledDevice, $msg);
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions LD382A aka Magic UFO
# with RGBW stripe (RGB and white)
# LD382A is a LD382 with fw 1.0.6
#
###############################################################################

sub
WifiLight_RGBWLD382A_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c%c", 0x71, 0x23, 0x0F, 0xA3);
  # my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD382A set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBWLD382A_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD382A set off $ramp");
  return WifiLight_RGBWLD382A_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBWLD382A_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW LD382A dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBWLD382A_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW LD382A set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my $msg = sprintf("%c%c%c%c%c%c%c", 0x31, $rr, $rg, $rb, $white, 0x00, 0x0F);
  #add checksum
  $msg = WifiLight_RGBWLD382_Checksum($ledDevice, $msg);
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions LD382A aka Magic UFO
# with RGB stripe (mixed white)
# LD382A is a LD382 with fw 1.0.6
#
###############################################################################

sub
WifiLight_RGBLD382A_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c%c", 0x71, 0x23, 0x0F, 0xA3);
  # my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LD382A set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBLD382A_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LD382A set off $ramp");
  return WifiLight_RGBLD382A_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBLD382A_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LD382A dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBLD382A_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB LD382A set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # convert to device 4 channels (remaining r,g,b after substract white, white, rgb)
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  #replace the removed part of white light and apply white balance
  $rr += int(($white * $wr) + 0.5);
  $rg += int(($white * $wg) + 0.5);
  $rb += int(($white * $wb) + 0.5);

  my $msg = sprintf("%c%c%c%c%c%c%c", 0x31, $rr, $rg, $rb, 0x00, 0x00, 0x0F);
  #add checksum
  $msg = WifiLight_RGBWLD382_Checksum($ledDevice, $msg);
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions RGB LW12
# LED Stripe controller LW12
#
#
###############################################################################

sub
WifiLight_RGBLW12_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c", 0xCC, 0x23, 0x33);
  my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  my $receiver;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  # WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12 set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

#TODO set physical off: my $off = sprintf("%c%c%c", 0xCC, 0x24, 0x33);
sub
WifiLight_RGBLW12_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12 set off $ramp");
  return WifiLight_RGBLW12_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBLW12_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12 dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBLW12_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB LW12 set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];
  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  #new style converter with white point correction
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  #replace the removed part of white light and apply white balance
  $rr += int(($white * $wr) + 0.5);
  $rg += int(($white * $wg) + 0.5);
  $rb += int(($white * $wb) + 0.5);
  my $msg = sprintf("%c%c%c%c%c", 0x56, $rr, $rg, $rb, 0xAA);

  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions RGB LW12 HX001 Version
# LED Stripe controller LW12
#
#
###############################################################################

sub
WifiLight_RGBLW12HX_On(@)
{
  my ($ledDevice, $ramp) = @_;
  # my $delay = 50;
  # my $on = sprintf("%c%c%c", 0xCC, 0x23, 0x33);
  # my $msg = sprintf("%c%c%c%c%c", 0x56, 0, 0, 0, 0xAA);
  # my $receiver;
  # WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  # WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12HX set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBLW12HX_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12HX set off $ramp");
  return WifiLight_RGBLW12HX_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBLW12HX_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBHX LW12 dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBLW12HX_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB LW12 set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);

  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];
  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  #new style converter with white point correction
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  #replace the removed part of white light and apply white balance
  $rr += int(($white * $wr) + 0.5);
  $rg += int(($white * $wg) + 0.5);
  $rb += int(($white * $wb) + 0.5);

  my $on = ($gammaVal > 0)?1:0;
  my $dim = 100;

  # supported by ichichich
  my @sendData = (0x9D, 0x62, 0x00, 0x01, 0x01, $on, $dim, $rr, $rg, $rb, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
  my $chkSum = 0xFF;
  $chkSum += $_ for @sendData[3, 5..9];
  unless ($chkSum == 0)
  {
    $chkSum %= 0xFF;
    $chkSum = 0xFF if ($chkSum == 0);
  }
  push (@sendData, $chkSum);
  for (my $i=2; $i<11; $i++)
  {
    my $h = ($sendData[$i] & 0xF0) + ($sendData[21-$i] >> 4);
    my $l = (($sendData[$i] & 0x0F) << 4) + ($sendData[21-$i] & 0x0F);

    $sendData[$i] = $h;
    $sendData[21-$i] = $l;
  } 
  my $msg = pack('C*', @sendData);
  # $dbgStr = unpack("H*", $msg);
  # print "lw12HX $dbgStr \n";

  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;  
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions RGB LW12 FC Version
# LED Stripe controller LW12
#
#
###############################################################################

sub
WifiLight_RGBLW12FC_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my $delay = 50;
  my $on = sprintf("%c%c%c%c%c%c%c%c%c", 0x7E, 0x04, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0x00, 0xEF);
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12FC set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_RGBLW12FC_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12FC set off $ramp");
  return WifiLight_RGBLW12FC_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBLW12FC_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LW12FC dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_RGBLW12FC_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB LW12FC set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);

  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];
  # color cast correction
  my $h = $ledDevice->{helper}->{COLORMAP}[$hue]; 

  # new style converter with white point correction
  my ($rr, $rg, $rb, $white) = WifiLight_HSV2fourChannel($h, $sat, $gammaVal);
  my ($wr, $wg, $wb) = split(',', AttrVal($ledDevice->{NAME}, 'whitePoint', '1, 1, 1'));
  # replace the removed part of white light and apply white balance
  $rr += int(($white * $wr) + 0.5);
  $rg += int(($white * $wg) + 0.5);
  $rb += int(($white * $wb) + 0.5);

  my $on = ($gammaVal > 0)?1:0;
  my $dim = 100;

  my $msg = sprintf("%c%c%c%c%c%c%c%c%c", 0x7E, 0x07, 0x05, 0x03, $rr, $rg, $rb, 0x00, 0xEF);
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable
  $ledDevice->{helper}->{llLock} += 1;
  WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
  # unlock ll queue
  return WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
}

###############################################################################
#
# device specific controller functions White SENGLED
# E27 LED Bulb with 
#
#
###############################################################################

sub
WifiLight_WhiteSENGLED_On(@)
{
  my ($ledDevice, $ramp) = @_;
  # my $delay = 50;
  # my $on = sprintf("%c%c%c%c%c%c%c%c%c", 0x7E, 0x04, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0x00, 0xEF);
  # my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  # WifiLight_LowLevelCmdQueue_Add($ledDevice, $on, $receiver, $delay);
  
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} White SENGLED set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 100, undef);
}

sub
WifiLight_WhiteSENGLED_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} White SENGLED set off $ramp");
  return WifiLight_WhiteSENGLED_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_WhiteSENGLED_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  # my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  # my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} White SENGLED dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, 0, 0, $level, $ramp, $flags, 100, undef);
}

sub
WifiLight_WhiteSENGLED_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val, $isLast) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 50;

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} White SENGLED set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);

  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];
  
  my @remote = split(/\./, $ledDevice->{helper}->{SOCKET}->peerhost());

  # intro
  my $msg = sprintf("%c%c%c%c%c", 0x0d, 0x00, 0x02, 0x00, 0x01);
  # sender, lazy 0x00
  $msg .= sprintf("%c%c%c%c", 0x00, 0x00, 0x00, 0x00);
  # destinations
  $msg .= sprintf("%c%c%c%c", $remote[0], $remote[1], $remote[2], $remote[3] );
  # sender, lazy 0x00
  $msg .= sprintf("%c%c%c%c", 0x00, 0x00, 0x00, 0x00);
  # destinations
  $msg .= sprintf("%c%c%c%c", $remote[0], $remote[1], $remote[2], $remote[3] );
  # intro 2
  $msg .= sprintf("%c%c%c%c%c%c", 0x01, 0x00, 0x01, 0x00, 0x00, 0x00);
  # cmd level
  $msg .= sprintf("%c%c", $gammaVal, 0x64);
  
  # for safety of tranmission (udp): repeat cmd if its stand-alone or first or last in transition
  my $repeat = ($isLast)?3:1;
  for (my $i=0; $i<$repeat; $i++)
  {
    # lock ll queue to prevent a bottleneck within llqueue
    # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
    # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
    $ledDevice->{helper}->{llLock} += 1;
    WifiLight_LowLevelCmdQueue_Add($ledDevice, $msg, $receiver, $delay);
    # unlock ll queue after complete cmd is send
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
  }
  
  return undef;
}

###############################################################################
#
# device specific controller functions RGB
# LED Stripe or bulb, no white, controller V2
#
###############################################################################

sub
WifiLight_RGB_Pair(@)
{
  my ($ledDevice, $numSeconds) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LED slot $ledDevice->{SLOT} pair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = "\x25\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
  }
  return undef;
}

sub
WifiLight_RGB_UnPair(@)
{
  my ($ledDevice) = @_;
  my $numSeconds = 8;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB LED slot $ledDevice->{SLOT} unpair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = "\x25\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
  }
  return undef;
}

sub
WifiLight_RGB_Sync(@)
{
  my ($ledDevice) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 100;

  $ledDevice->{helper}->{whiteLevel} =9; 
  $ledDevice->{helper}->{colorLevel} =9;
  $ledDevice->{helper}->{colorValue} =127; 
  $ledDevice->{helper}->{mode} =2; # mode 0: off, 1: mixed "white", 2: color
 
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x22\x00\x55", $receiver, 500); # on
  for (my $i = 0; $i < 22; $i++) {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode up (to "pure white" ;-) 
  }
  for (my $i = 0; $i < 10; $i++) {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up (to "pure white" ;-) 
  }
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20\x7F\x55", $receiver, $delay); # color yellow (auto jump to mode 2)
  for (my $i = 0; $i < 10; $i++) {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up (yellow max brightness) 
  }

  WifiLight_setHSV_Readings($ledDevice, 60, 100, 100) if $init_done;

  return undef;
}

sub
WifiLight_RGB_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "40,100,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB slot $ledDevice->{SLOT} set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 500, undef);
}

sub
WifiLight_RGB_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB slot $ledDevice->{SLOT} set off $ramp");
  return WifiLight_RGB_Dim($ledDevice, 0, $ramp, '');
  #TODO remove if tested
  #return WifiLight_HSV_Transition($ledDevice, 0, 100, 0, $ramp, undef, 500, undef);
}

sub
WifiLight_RGB_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGB slot $ledDevice->{SLOT} dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 500, undef);
}

sub
WifiLight_RGB_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB slot $ledDevice->{SLOT} set h:$hue, s:$sat, v:$val"); 
  $sat = 100;
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # convert to device specs
  my ($cv, $cl, $wl) = WifiLight_RGBW1_ColorConverter($ledDevice, $hue, $sat, $val);
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGB slot $ledDevice->{SLOT} set levels: $cv, $cl, $wl");
  return WifiLight_RGB_setLevels($ledDevice, $cv, $cl, $wl);
}

sub
WifiLight_RGB_setLevels(@)
{
  my ($ledDevice, $cv, $cl, $wl) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 100;
  my $lock = 0;

  # mode 0: off, 1: mixed "white", 2: color
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  if ((($ledDevice->{helper}->{colorValue} != $cv) && ($cl > 0)) || ($ledDevice->{helper}->{colorLevel} != $cl) || ($ledDevice->{helper}->{whiteLevel} != $wl))
  {
    $ledDevice->{helper}->{llLock} += 1;
    $lock = 1;
  }
  # need to touch color value (only if visible) or color level ?
  if ((($ledDevice->{helper}->{colorValue} != $cv) && ($cl > 0)) || $ledDevice->{helper}->{colorLevel} != $cl)
  {
    # if color all off switch on
    if ($ledDevice->{helper}->{mode} == 0)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x22\x00\x55", $receiver, $delay); # switch on
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20".chr($cv)."\x55", $receiver, $delay); # set color
      $ledDevice->{helper}->{colorValue} = $cv;
      $ledDevice->{helper}->{colorLevel} = 1;
      $ledDevice->{helper}->{mode} = 2;
    }
    elsif ($ledDevice->{helper}->{mode} == 1)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20".chr($cv)."\x55", $receiver, $delay); # set color
      $ledDevice->{helper}->{colorValue} = $cv;
      $ledDevice->{helper}->{mode} = 2;
    }
    else
    {
      $ledDevice->{helper}->{colorValue} = $cv;
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20".chr($cv)."\x55", $receiver, $delay); # set color
    }
    # cl decrease
    if ($ledDevice->{helper}->{colorLevel} > $cl)
    {
      for (my $i=$ledDevice->{helper}->{colorLevel}; $i > $cl; $i--) 
      {
        WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x24\x00\x55", $receiver, $delay); # brightness down
        $ledDevice->{helper}->{colorLevel} = $i - 1;
      }
      if ($cl == 0)
      {
        # need to switch off color
        # if no white is required and no white is active we can must entirely switch off
        WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x21\x00\x55", $receiver, $delay); # switch off
        $ledDevice->{helper}->{colorLevel} = 0;
        $ledDevice->{helper}->{mode} = 0;
      }
    }
    # cl inrease
    if ($ledDevice->{helper}->{colorLevel} < $cl)
    {
      for (my $i=$ledDevice->{helper}->{colorLevel}; $i < $cl; $i++)
      {
        WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # brightness up
        $ledDevice->{helper}->{colorLevel} = $i + 1;
      }
    }
  }
  # unlock ll queue
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1) if $lock;
  return undef;
}

###############################################################################
#
# device specific controller functions RGBW1 
# LED Stripe with extra white led, controller V2, bridge V2|bridge V3
#
#
###############################################################################

sub
WifiLight_RGBW1_Pair(@)
{
  my ($ledDevice, $numSeconds) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW1 LED slot $ledDevice->{SLOT} pair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = "\x25\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
  }
  return undef;
}

sub
WifiLight_RGBW1_UnPair(@)
{
  my ($ledDevice) = @_;
  my $numSeconds = 8;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW1 LED slot $ledDevice->{SLOT} unpair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = "\x25\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
  }
  return undef;
}

sub
WifiLight_RGBW1_Sync(@)
{
  my ($ledDevice) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 250;

  $ledDevice->{helper}->{whiteLevel} =9; 
  $ledDevice->{helper}->{colorLevel} =9;
  $ledDevice->{helper}->{colorValue} =170; 
  $ledDevice->{helper}->{mode} =3; # mode 0: c:off, w:off; 1: c:on, w:off; 2: c:off, w:on; 3: c:on, w:on

  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x22\x00\x55", $receiver, 500); # on
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x22\x00\x55", $receiver, $delay); # on
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20\xAA\x55", $receiver, $delay); # color red (auto jump to mode 1 except we are mode 3)
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down 
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down (now we are for sure in mode 1)
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #1
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #2
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #3
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #4
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #5
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #6
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #7
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #8 
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #9 (highest dim-level color red)
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay); # mode up (pure white) 
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #1
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #2
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #3
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #4
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #5
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #6
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #7
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #8
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # dim up #9 (highest dim-level white)
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay); # mode up (white and red at highest level: bright warm light) 

  WifiLight_setHSV_Readings($ledDevice, 0, 50, 100) if $init_done;

  return undef;
}

sub
WifiLight_RGBW1_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW1 slot $ledDevice->{SLOT} set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 1000, undef);
}

sub
WifiLight_RGBW1_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW1 slot $ledDevice->{SLOT} set off $ramp");
  return WifiLight_RGBW1_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_RGBW1_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW1 slot $ledDevice->{SLOT} dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 1000, undef);
}

sub
WifiLight_RGBW1_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW1 slot $ledDevice->{SLOT} set h:$hue, s:$sat, v:$val"); 
  WifiLight_setHSV_Readings($ledDevice, $hue, $sat, $val);
  # convert to device specs
  my ($cv, $cl, $wl) = WifiLight_RGBW1_ColorConverter($ledDevice, $hue, $sat, $val);
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW1 slot $ledDevice->{SLOT} set levels: $cv, $cl, $wl");
  return WifiLight_RGBW1_setLevels($ledDevice, $cv, $cl, $wl);
}

sub
WifiLight_RGBW1_setLevels(@)
{
  my ($ledDevice, $cv, $cl, $wl) = @_;
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 250;
  my $lock = 0;

  # need to touch color value or color level?
  # yes
  # is color visible ? (we are in mode 1 or 3)
  #   yes: adjust color!, requ level = 1 if cl = 0; new level 0 ? yes: mode 0 if wl == 0 else Mode = 1 (if coming from 0 or 1 then wl =1)
  #   no:
  #     will we need color ?
  #       yes: go into mode #1, (cl jumps to 1)

  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  if ((($ledDevice->{helper}->{colorValue} != $cv) && ($cl > 0)) || ($ledDevice->{helper}->{colorLevel} != $cl) || ($ledDevice->{helper}->{whiteLevel} != $wl))
  {
    $ledDevice->{helper}->{llLock} += 1;
    $lock = 1;
  }

  # need to touch color value (only if visible) or color level ?
  if ((($ledDevice->{helper}->{colorValue} != $cv) && ($cl > 0)) || $ledDevice->{helper}->{colorLevel} != $cl)
  {
    # if color all off switch on
    if ($ledDevice->{helper}->{mode} == 0)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x22\x00\x55", $receiver, $delay); # switch on
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down: 3 > 2 || 2 > 1
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down: 2 > 1 || 1 > 1
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20".chr($cv)."\x55", $receiver, $delay); # set color
      $ledDevice->{helper}->{colorValue} = $cv;
      $ledDevice->{helper}->{colorLevel} = 1;
      $ledDevice->{helper}->{mode} = 1;
    }
    elsif ($ledDevice->{helper}->{mode} == 2)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay); # mode up: 2 > 3
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20".chr($cv)."\x55", $receiver, $delay); # set color
      $ledDevice->{helper}->{colorValue} = $cv;
      $ledDevice->{helper}->{colorLevel} = 1;
      $ledDevice->{helper}->{mode} = 3;
    }
    else
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x20".chr($cv)."\x55", $receiver, $delay); # set color
      $ledDevice->{helper}->{colorValue} = $cv;
    }

    # color level decrease
    if ($ledDevice->{helper}->{colorLevel} > $cl)
    {
      for (my $i=$ledDevice->{helper}->{colorLevel}; $i > $cl; $i--) 
      {
        WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x24\x00\x55", $receiver, $delay); # brightness down
        $ledDevice->{helper}->{colorLevel} = $i - 1;
      }
      if ($cl == 0)
      {
        # need to switch off color
        # if no white is required and no white is active switch off
        if (($wl == 0) && ($ledDevice->{helper}->{mode} == 1))
        {
          WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x21\x00\x55", $receiver, $delay); # switch off
          $ledDevice->{helper}->{colorLevel} = 0;
          $ledDevice->{helper}->{mode} = 0;
        }
        # if white is required, goto mode 2: pure white
        if (($wl > 0) || ($ledDevice->{helper}->{mode} == 2) ||  ($ledDevice->{helper}->{mode} == 3))
        {
          WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay) if ($ledDevice->{helper}->{mode} == 1) ; # mode up
          WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay) if ($ledDevice->{helper}->{mode} == 3) ; # mode down
          $ledDevice->{helper}->{colorLevel} = 0;
          $ledDevice->{helper}->{whiteLevel} = 1 if ($ledDevice->{helper}->{mode} == 1);
          $ledDevice->{helper}->{mode} = 2;
        }
      }
    }
    if ($ledDevice->{helper}->{colorLevel} < $cl)
    {
      for (my $i=$ledDevice->{helper}->{colorLevel}; $i < $cl; $i++)
      {
        WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # brightness up
        $ledDevice->{helper}->{colorLevel} = $i + 1;
      }
    }
  }
  # need to adjust white level ?
  if ($ledDevice->{helper}->{whiteLevel} != $wl)
  {
    # white off but need adjustment ? set it on..
    # color processing is finished, so if we are in mode 0, no color required. go to mode 2: pure white
    if ($ledDevice->{helper}->{mode} == 0)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x22\x00\x55", $receiver, $delay); # switch on
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down (3 -> 2 || 2 -> 1)
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down (2 -> 1 || 1 -> 1)
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay); # mode up (1 -> 2)
      $ledDevice->{helper}->{whiteLevel} = 1;
      $ledDevice->{helper}->{mode} = 2;
    }
    # color processing is finished, so if we are at mode 1 color is required. go to mode 2
    if ($ledDevice->{helper}->{mode} == 1)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay); # mode up (1 -> 2)
      $ledDevice->{helper}->{whiteLevel} = 1;
      $ledDevice->{helper}->{mode} = 2; 
    }
    # temporary go to mode 2 while maintain white level
    if ($ledDevice->{helper}->{mode} == 3)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down (3 -> 2)
      $ledDevice->{helper}->{mode} = 2; 
    }
    # white level inrease
    for (my $i=$ledDevice->{helper}->{whiteLevel}; $i < $wl; $i++)
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x23\x00\x55", $receiver, $delay); # brightness up
      $ledDevice->{helper}->{whiteLevel} = $i + 1;
    }
    # white level decrease
    if ($ledDevice->{helper}->{whiteLevel} > $wl)
    {
      for (my $i=$ledDevice->{helper}->{whiteLevel}; $i > $wl; $i--) 
      {
        WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x24\x00\x55", $receiver, $delay); # brightness down
        $ledDevice->{helper}->{whiteLevel} = $i - 1;
      }
    }

    # assume we are at mode 2, finishing to correct mode
    if (($wl == 0) && ($cl == 0))
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x21\x00\x55", $receiver, $delay); # switch off
      $ledDevice->{helper}->{whiteLevel} = 0;
      $ledDevice->{helper}->{mode} = 0;
    }
    if (($wl == 0) && ($cl > 0))
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x28\x00\x55", $receiver, $delay); # mode down (2 -> 1)
      $ledDevice->{helper}->{whiteLevel} = 0;
      $ledDevice->{helper}->{mode} = 1; 
    }
    if (($wl > 0) && ($cl > 0))
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x27\x00\x55", $receiver, $delay); # mode up (2 -> 3)
      $ledDevice->{helper}->{mode} = 3; 
    }
  }
  # unlock ll queue
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1) if $lock;
  return undef;
}

sub
WifiLight_RGBW1_ColorConverter(@)
{
  my ($ledDevice, $h, $s, $v) = @_;
  my $color = $ledDevice->{helper}->{COLORMAP}[$h % 360];
  
  # there are 0..9 dim level, setup correction
  my $valueSpread = 100/9;
  my $totalVal = int(($v / $valueSpread) +0.5);
  # saturation 100..50: color full, white increase. 50..0 white full, color decrease
  my $colorVal = ($s >= 50) ? $totalVal : int(($s / 50 * $totalVal) +0.5);
  my $whiteVal = ($s >= 50) ? int(((100-$s) / 50 * $totalVal) +0.5) : $totalVal;
  return ($color, $colorVal, $whiteVal);
}

###############################################################################
#
# device specific functions RGBW2 bulb 
# RGB white, only bridge V3
#
#
###############################################################################

sub
WifiLight_RGBW2_Pair(@)
{
  my ($ledDevice, $numSeconds) = @_;
  $numSeconds = 3 if (($numSeconds || 0) == 0);
  my @bulbCmdsOn = ("\x45", "\x47", "\x49", "\x4B");
  Log3 ($ledDevice, 3, "$ledDevice->{NAME}, $ledDevice->{LEDTYPE} at $ledDevice->{CONNECTION}, slot $ledDevice->{SLOT}: pair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
  }
  return undef;
}

sub
WifiLight_RGBW2_UnPair(@)
{
  my ($ledDevice, $numSeconds, $releaseFromSlot) = @_;
  $numSeconds = 5;
  my @bulbCmdsOn = ("\x45", "\x47", "\x49", "\x4B");
  Log3 ($ledDevice, 3, "$ledDevice->{NAME}, $ledDevice->{LEDTYPE} at $ledDevice->{CONNECTION}, slot $ledDevice->{SLOT}: unpair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
  }
  return undef;
}

sub
WifiLight_RGBW2_Sync(@)
{
  my ($ledDevice) = @_;
  # force new settings
  $ledDevice->{helper}->{mode} = -1; 
  $ledDevice->{helper}->{colorValue} = -1; 
  $ledDevice->{helper}->{colorLevel} = -1;
  $ledDevice->{helper}->{whiteLevel} = -1;
  return undef;
}

sub
WifiLight_RGBW2_On(@)
{
  my ($ledDevice, $ramp) = @_;
  my ($h, $s, $v) = split(',', AttrVal($ledDevice->{NAME}, "defaultColor", "0,0,100"));
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW2 slot $ledDevice->{SLOT} set on ($h, $s, $v) $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $v, $ramp, '', 200, undef);
}

sub
WifiLight_RGBW2_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW2 slot $ledDevice->{SLOT} set off $ramp");
  return WifiLight_RGBW2_Dim($ledDevice, 0, $ramp, '');
  #TODO remove if tested
  #return WifiLight_HSV_Transition($ledDevice, 0, 0, 0, $ramp, undef, 500, undef);
}

sub
WifiLight_RGBW2_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} RGBW2 slot $ledDevice->{SLOT} dim $level $ramp ". $flags || ''); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 200, undef);
}

sub
WifiLight_RGBW2_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val, $isLast) = @_;
  my ($cl, $wl);

  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 100;
  my $cv = $ledDevice->{helper}->{COLORMAP}[$hue % 360];

  # apply gamma correction
  my $gammaVal = $ledDevice->{helper}->{GAMMAMAP}[$val];

  # mode 0 = off, 1 = color, 2 = white
  # brightness 2..27 (x02..x1b) | 25 
  my $cf = 100 / 26;
  my $cb = int(($gammaVal / $cf) + 0.5);
  $cb += ($cb > 0)?1:0;

  if ($sat < 20) 
  {
    $wl = $cb;
    $cl = 0;
    WifiLight_setHSV_Readings($ledDevice, $hue, 0, $val);
  }
  else
  {
    $cl = $cb;
    $wl = 0;
    WifiLight_setHSV_Readings($ledDevice, $hue, 100, $val);
  }

  return WifiLight_RGBW2_setLevelsFast($ledDevice, $receiver, $cv, $cl, $wl) unless ($isLast);
  return WifiLight_RGBW2_setLevelsSafe($ledDevice, $receiver, $cv, $cl, $wl);
}

# repeatly send out a full size cmd 
# the last cmd in a transition or if it is stand alone
sub
WifiLight_RGBW2_setLevelsSafe(@)
{
  my ($ledDevice, $receiver, $cv, $cl, $wl) = @_;
  my $delay = 100;

  my @bulbCmdsOn = ("\x45", "\x47", "\x49", "\x4B");
  my @bulbCmdsOff = ("\x46", "\x48", "\x4A", "\x4C");
  my @bulbCmdsWT = ("\xC5", "\xC7", "\xC9", "\xCB");

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} RGBW2 slot $ledDevice->{SLOT} set safe levels");
  Log3 ($ledDevice, 5, "$ledDevice->{NAME} RGBW2 slot $ledDevice->{SLOT} lock queue ".$ledDevice->{helper}->{llLock});

  my @cmd = ();
  
  # about switching off. dim to prevent a flash if switched on again
  
  if (($wl == 0) && ($cl == 0) && ($ledDevice->{helper}->{mode} != 0))
  {
    $ledDevice->{helper}->{llLock} += 1; # lock ...
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55", $receiver, $delay); # group on
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x4E\x02\x55", $receiver, $delay); # brightness
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1); # ... unlock
  }

  if (($wl == 0) && ($cl == 0))
  {
    push (@cmd, @bulbCmdsOff[$ledDevice->{SLOT} -5]."\x00\x55");
    $ledDevice->{helper}->{whiteLevel} = 0;
    $ledDevice->{helper}->{colorLevel} = 0;
    $ledDevice->{helper}->{mode} = 0; # group off
  }
  elsif ($wl > 0)
  {
    push (@cmd, @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55");
    push (@cmd, @bulbCmdsWT[$ledDevice->{SLOT} -5]."\x00\x55");
    push (@cmd, "\x4E".chr($wl)."\x55");
    $ledDevice->{helper}->{whiteLevel} = $wl;
    $ledDevice->{helper}->{colorLevel} = 0;
    $ledDevice->{helper}->{mode} = 2; # white
  }
  elsif ($cl > 0)
  {
    push (@cmd, @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55");
    push (@cmd, "\x40".chr($cv)."\x55"); # color
    push (@cmd, "\x4E".chr($cl)."\x55"); # brightness
    $ledDevice->{helper}->{whiteLevel} = 0;
    $ledDevice->{helper}->{colorLevel} = $cl;
    $ledDevice->{helper}->{colorValue} = $cv;
    $ledDevice->{helper}->{mode} = 1; # color
  }

  # repeat it three times
  for (my $i=0; $i<3; $i++)
  {
    # lock ll queue to prevent a bottleneck within llqueue
    # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
    # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
    $ledDevice->{helper}->{llLock} += 1;
    WifiLight_LowLevelCmdQueue_Add($ledDevice, $_, $receiver, $delay) foreach (@cmd);
    # unlock ll queue after complete cmd is send
    WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
  }

  return undef;
}

# classic optimized version, used by fast color transitions
sub
WifiLight_RGBW2_setLevelsFast(@)
{
  my ($ledDevice, $receiver, $cv, $cl, $wl) = @_;
  my $delay = 100;

  my @bulbCmdsOn = ("\x45", "\x47", "\x49", "\x4B");
  my @bulbCmdsOff = ("\x46", "\x48", "\x4A", "\x4C");
  my @bulbCmdsWT = ("\xC5", "\xC7", "\xC9", "\xCB");

  return if (($ledDevice->{helper}->{colorValue} == $cv) && ($ledDevice->{helper}->{colorLevel} == $cl) && ($ledDevice->{helper}->{whiteLevel} == $wl));
  # lock ll queue to prevent a bottleneck within llqueue
  # in cases where the high level queue fills the low level queue (which should not be interrupted) faster then it is processed (send out)
  # this lock will cause the hlexec intentionally drop frames which can safely be done because there are further frames for processing avialable  
  $ledDevice->{helper}->{llLock} += 1;
  Log3 ($ledDevice, 5, "$ledDevice->{NAME} RGBW2 slot $ledDevice->{SLOT} lock queue ".$ledDevice->{helper}->{llLock});

  if (($wl == 0) && ($cl == 0) && ($ledDevice->{helper}->{mode} != 0))
  {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOff[$ledDevice->{SLOT} -5]."\x00\x55", $receiver, $delay);
    $ledDevice->{helper}->{whiteLevel} = 0;
    $ledDevice->{helper}->{colorLevel} = 0;
    $ledDevice->{helper}->{mode} = 0; # group off
  }
  else
  {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55", $receiver, $delay); # group on
    # WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -5]."\x00\x55", $receiver, $delay) if (($wl > 0) || ($cl > 0)); # group on
    if (($wl > 0) && ($ledDevice->{helper}->{mode} == 2)) # already white
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x4E".chr($wl)."\x55", $receiver, $delay) if ($ledDevice->{helper}->{whiteLevel} != $wl); # brightness
    }
    elsif (($wl > 0) && ($ledDevice->{helper}->{mode} != 2)) # not white
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsWT[$ledDevice->{SLOT} -5]."\x00\x55", $receiver, $delay); # white
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x4E".chr($wl)."\x55", $receiver, $delay); # brightness
      $ledDevice->{helper}->{mode} = 2; # white
    }
    elsif (($cl > 0) && ($ledDevice->{helper}->{mode} == 1)) # already color
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x4E".chr($cl)."\x55", $receiver, $delay) if ($ledDevice->{helper}->{colorLevel} != $cl); # brightness
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x40".chr($cv)."\x55", $receiver, $delay) if ($ledDevice->{helper}->{colorValue} != $cv); # color
    }
    elsif (($cl > 0) && ($ledDevice->{helper}->{mode} != 1)) # not color
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x40".chr($cv)."\x55", $receiver, $delay); # color
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x4E".chr($cl)."\x55", $receiver, $delay); # brightness
      $ledDevice->{helper}->{mode} = 1; # color
    }
    $ledDevice->{helper}->{colorValue} = $cv;
    $ledDevice->{helper}->{colorLevel} = $cl;
    $ledDevice->{helper}->{whiteLevel} = $wl;
  }
  # unlock ll queue after complete cmd is send
  WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x00", $receiver, 0, 1);
  return undef;
}

###############################################################################
#
# device specific functions white bulb 
# warm white / cold white with dim, bridge V2|bridge V3
#
#
###############################################################################

sub
WifiLight_White_Pair(@)
{
  my ($ledDevice, $numSeconds) = @_;
  $numSeconds = 1 if !(defined($numSeconds));
  my @bulbCmdsOn = ("\x38", "\x3D", "\x37", "\x32");
  Log3 ($ledDevice, 3, "$ledDevice->{NAME}, $ledDevice->{LEDTYPE} at $ledDevice->{CONNECTION}, slot $ledDevice->{SLOT}: pair $numSeconds");
  # find my slot and get my group-all-on cmd
  my $ctrl = @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 500, undef, undef);
  }
  return undef;
}

sub
WifiLight_White_UnPair(@)
{
  my ($ledDevice, $numSeconds, $releaseFromSlot) = @_;
  $numSeconds = 5;
  my @bulbCmdsOn = ("\x38", "\x3D", "\x37", "\x32");
  Log3 ($ledDevice, 3, "$ledDevice->{NAME}, $ledDevice->{LEDTYPE} at $ledDevice->{CONNECTION}, slot $ledDevice->{SLOT}: unpair $numSeconds"); 
  # find my slot and get my group-all-on cmd
  my $ctrl = @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55";
  for (my $i = 0; $i < $numSeconds; $i++)
  { 
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
    WifiLight_HighLevelCmdQueue_Add($ledDevice, undef, undef, undef, $ctrl, 250, undef, undef);
  }
  return undef;
}

sub
WifiLight_White_Sync(@)
{
  my ($ledDevice) = @_;
  my @bulbCmdsOn = ("\x38", "\x3D", "\x37", "\x32");
  my @bulbCmdsFB = ("\xB8", "\xBD", "\xB7", "\xB2");
  
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 100;

  $ledDevice->{helper}->{whiteLevel} =11; 

  Log3 ($ledDevice, 3, "$ledDevice->{NAME}, $ledDevice->{LEDTYPE} at $ledDevice->{CONNECTION}, slot $ledDevice->{SLOT}: sync"); 

  WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay); # group on
  WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsFB[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay); # full brightness

  WifiLight_setHSV_Readings($ledDevice, 0, 0, 100) if $init_done;

  return undef;
}

sub
WifiLight_White_On(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} white slot $ledDevice->{SLOT} set on $ramp"); 
  return WifiLight_HSV_Transition($ledDevice, 0, 0, 100, $ramp, '', 500, undef);
}

sub
WifiLight_White_Off(@)
{
  my ($ledDevice, $ramp) = @_;
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} white slot $ledDevice->{SLOT} set off $ramp"); 
  return WifiLight_RGBW2_Dim($ledDevice, 0, $ramp, '');
}

sub
WifiLight_White_Dim(@)
{
  my ($ledDevice, $level, $ramp, $flags) = @_;
  my $h = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  my $s = ReadingsVal($ledDevice->{NAME}, "saturation", 0);
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} white slot $ledDevice->{SLOT} dim $level $ramp $flags"); 
  return WifiLight_HSV_Transition($ledDevice, $h, $s, $level, $ramp, $flags, 300, undef);
}

# only val supported, 
# TODO hue will become colortemp
sub
WifiLight_White_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my $wlStep = (100 / 11);
  WifiLight_setHSV_Readings($ledDevice, 0, 0, $val);
  $val = int(($val / $wlStep) +0.5);
  WifiLight_White_setLevels($ledDevice, undef, $val);
  
  return undef;
}

sub
WifiLight_White_setLevels(@)
{
  my ($ledDevice, $cv, $wl) = @_;
  my @bulbCmdsOn = ("\x38", "\x3D", "\x37", "\x32");
  my @bulbCmdsOff = ("\x3B", "\x33", "\x3A", "\x36");
  my @bulbCmdsFull = ("\xB8", "\xBD", "\xB7", "\xB2");
  my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
  my $delay = 80;

  # alert that dump receiver, give it a extra wake up call 
  if ($ledDevice->{helper}->{whiteLevel} != $wl) 
  {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay);
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay);
  }
  
  if ($ledDevice->{helper}->{whiteLevel} > $wl)
  {
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay); # group on
    for (my $i=$ledDevice->{helper}->{whiteLevel}; $i > $wl; $i--) 
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x34\x00\x55", $receiver, $delay); # brightness down
      $ledDevice->{helper}->{whiteLevel} = $i - 1;
    }
    if ($wl == 0)
    {
      # special precaution, giving extra downsteps to do a sync each time you switch off
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x34\x00\x55", $receiver, $delay); # brightness down
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x34\x00\x55", $receiver, $delay); # brightness down
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x34\x00\x55", $receiver, $delay); # brightness down
      WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOff[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay); # group off
      #WifiLight_LowLevelCmdqueue_Add($ledDevice, @bulbCmdsOff[$ledDevice->{SLOT}-1]."\x00\x55", $receiver, $delay);
    }
  }
   
  if ($ledDevice->{helper}->{whiteLevel} < $wl)
  {
    $ledDevice->{helper}->{whiteLevel} = 1 if ($ledDevice->{helper}->{whiteLevel} == 0);
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsOn[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay); # group on
    for (my $i=$ledDevice->{helper}->{whiteLevel}; $i < $wl; $i++) 
    {
      WifiLight_LowLevelCmdQueue_Add($ledDevice, "\x3C\x00\x55", $receiver, $delay); # brightness up
      $ledDevice->{helper}->{whiteLevel} = $i + 1;
    }
    WifiLight_LowLevelCmdQueue_Add($ledDevice, @bulbCmdsFull[$ledDevice->{SLOT} -1]."\x00\x55", $receiver, $delay) if ($ledDevice->{helper}->{whiteLevel} == 11);
  }
  return undef;
}


###############################################################################
#
# device indepenent routines
#
###############################################################################

# dispatcher 
sub
WifiLight_setHSV(@)
{
  my ($ledDevice, $hue, $sat, $val, $isLast) = @_;
  return WifiLight_RGBWLD316_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316'));
  return WifiLight_RGBWLD316A_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD316A'));
  return WifiLight_RGBWLD382_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382'));
  return WifiLight_RGBLD382_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382'));
  return WifiLight_RGBWLD382A_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'LD382A'));
  return WifiLight_RGBLD382A_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'LD382A'));
  return WifiLight_RGBLW12_setHSV($ledDevice, $hue, $sat, $val) if ($ledDevice->{CONNECTION} eq 'LW12');
  return WifiLight_RGBLW12HX_setHSV($ledDevice, $hue, $sat, $val) if ($ledDevice->{CONNECTION} eq 'LW12HX');
  return WifiLight_RGBLW12FC_setHSV($ledDevice, $hue, $sat, $val) if ($ledDevice->{CONNECTION} eq 'LW12FC');
  return WifiLight_WhiteSENGLED_setHSV($ledDevice, $hue, $sat, $val, $isLast) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} eq 'SENGLED'));
  return WifiLight_RGB_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
  return WifiLight_RGBW1_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq "RGBW1") && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
  return WifiLight_RGBW2_setHSV($ledDevice, $hue, $sat, $val, $isLast) if ($ledDevice->{LEDTYPE} eq "RGBW2");
  return WifiLight_White_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'White') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'));
  return WifiLight_DualWhiteSunricher_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'DualWhite') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
  return WifiLight_RGBSunricher_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
  return WifiLight_RGBSunricherA_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} eq 'SUNRICHERA'));
  return WifiLight_RGBWSunricher_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'SUNRICHER'));
  return WifiLight_RGBWSunricherA_setHSV($ledDevice, $hue, $sat, $val) if (($ledDevice->{LEDTYPE} eq 'RGBW') && ($ledDevice->{CONNECTION} eq 'SUNRICHERA'));
  return undef;
}

# dispatcher
sub
WifiLight_processEvent(@)
{
  my ($ledDevice, $event, $progress) = @_;
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} processEvent: $event, progress: $progress") if defined($event);
  DoTrigger($ledDevice->{NAME}, "programm: $event $progress",0) if defined($event);
  return undef;
}

sub
WifiLight_HSV_Transition(@)
{
  my ($ledDevice, $hue, $sat, $val, $ramp, $flags, $delay, $event) = @_;
  my ($hueFrom, $satFrom, $valFrom, $timeFrom);
  
  # minimum stepwide
  my $defaultDelay = $delay;

  # if queue in progess set start vals to last cached hsv target, else set start to actual hsv
  if (@{$ledDevice->{helper}->{hlCmdQueue}} > 0)
  {
    $hueFrom = $ledDevice->{helper}->{targetHue};
    $satFrom = $ledDevice->{helper}->{targetSat};
    $valFrom = $ledDevice->{helper}->{targetVal};
    $timeFrom = $ledDevice->{helper}->{targetTime};
    Log3 ($ledDevice, 5, "$ledDevice->{NAME} prepare start hsv transition (is cached) hsv $hueFrom, $satFrom, $valFrom, $timeFrom");
  }
  else
  {
    $hueFrom = $ledDevice->{READINGS}->{hue}->{VAL} || 0;
    $satFrom = $ledDevice->{READINGS}->{saturation}->{VAL} || 0;
    $valFrom = $ledDevice->{READINGS}->{brightness}->{VAL} || 0;
    $timeFrom = gettimeofday();
    Log3 ($ledDevice, 5, "$ledDevice->{NAME} prepare start hsv transition (is actual) hsv $hueFrom, $satFrom, $valFrom, $timeFrom");
  }

  Log3 ($ledDevice, 4, "$ledDevice->{NAME} current HSV $hueFrom, $satFrom, $valFrom");
  Log3 ($ledDevice, 3, "$ledDevice->{NAME} set HSV $hue, $sat, $val with ramp: $ramp, flags: ". $flags);

  # if there is no ramp we dont need transition
  if (($ramp || 0) == 0)
  {
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} hsv transition without ramp routed to direct settings, hsv $hue, $sat, $val");
    $ledDevice->{helper}->{targetTime} = $timeFrom;
    return WifiLight_HighLevelCmdQueue_Add($ledDevice, $hue, $sat, $val, undef, $delay, 100, $event, $timeFrom);
  }

  # calculate the left and right turn length based
  # startAngle +360 -endAngle % 360 = counter clock
  # endAngle +360 -startAngle % 360 = clockwise
  my $fadeLeft = ($hueFrom + 360 - $hue) % 360;
  my $fadeRight = ($hue + 360 - $hueFrom) % 360;
  my $direction = ($fadeLeft <=> $fadeRight); # -1 = counterclock, +1 = clockwise
  $direction = ($direction == 0)?1:$direction; # in dupt cw
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} color rotation dev cc:$fadeLeft, cw:$fadeRight, shortest:$direction"); 
  $direction *= -1 if ($flags =~ m/.*[lL].*/); # reverse if long path desired (flag l or L is set)

  my $rotation = ($direction == 1)?$fadeRight:$fadeLeft; # angle of hue rotation in based on flags
  my $sFade = abs($sat - $satFrom);
  my $vFade = abs($val - $valFrom);
        
  my ($stepWide, $steps, $hueToSet, $hueStep, $satToSet, $satStep, $valToSet, $valStep);
  
  # fix if there is in fact no transition, blocks queue for given ramp time with actual hsv values
  if ($rotation == 0 && $sFade == 0 && $vFade == 0)
  {
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} hsv transition with unchaned settings, hsv $hue, $sat, $val, ramp $ramp"); 
    #TODO remove if tested 
    #WifiLight_HighLevelCmdQueue_Add($ledDevice, $hue, $sat, $val, undef, $ramp * 1000, 0, $event, $timeFrom);
    
    $ledDevice->{helper}->{targetTime} = $timeFrom + $ramp;
    return WifiLight_HighLevelCmdQueue_Add($ledDevice, $hue, $sat, $val, undef, $delay, 100, $event, $timeFrom + $ramp);
  }

  if (($rotation >= $sFade) && ($rotation >= $vFade))
  {
    $stepWide = ($ramp * 1000 / $rotation); # how long is one step (set hsv) in ms based on hue
    $stepWide = $defaultDelay if ($stepWide < $defaultDelay);
    $steps = int($ramp * 1000 / $stepWide); # how many steps will we need ?
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} transit (H>S||V) steps: $steps stepwide: $stepWide");  
  }
  elsif (($sFade  >= $rotation) && ($sFade  >= $vFade))
  {
    $stepWide = ($ramp * 1000 / $sFade); # how long is one step (set hsv) in ms based on sat
    $stepWide = $defaultDelay if ($stepWide < $defaultDelay);
    $steps = int($ramp * 1000 / $stepWide); # how many steps will we need ?
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} transit (S>H||V) steps: $steps stepwide: $stepWide");  
  }
  else
  {
    $stepWide = ($ramp * 1000 / $vFade); # how long is one step (set hsv) in ms based on val
    $stepWide = $defaultDelay if ($stepWide < $defaultDelay);
    $steps = int($ramp * 1000 / $stepWide); # how many steps will we need ?
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} transit (V>H||S) steps: $steps stepwide: $stepWide");  
  }
        
  $hueToSet = $hueFrom; # prepare tmp working hue
  $hueStep = $rotation / $steps * $direction; # how big is one hue step base on timing choosen
          
  $satToSet = $satFrom; # prepare workin sat
  $satStep = ($sat - $satFrom) / $steps;
          
  $valToSet = $valFrom;
  $valStep = ($val - $valFrom) / $steps;

  #TODO do something more flexible
  #TODO remove if tested
  # $timeFrom += 1;

  for (my $i=1; $i <= $steps; $i++)
  {
    $hueToSet += $hueStep;
    $hueToSet -= 360 if ($hueToSet > 360); #handle turn over zero
    $hueToSet += 360 if ($hueToSet < 0);
    $satToSet += $satStep;
    $valToSet += $valStep;
    my $progress = 100 / $steps * $i;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} add to hl queue h:".($hueToSet).", s:".($satToSet).", v:".($valToSet)." ($i/$steps)");  
    WifiLight_HighLevelCmdQueue_Add($ledDevice, int($hueToSet +0.5), int($satToSet +0.5), int($valToSet +0.5), undef, $stepWide, int($progress +0.5), $event, $timeFrom + (($i-1) * $stepWide / 1000) );
  }
  $ledDevice->{helper}->{targetTime} = $timeFrom + $ramp;
  return undef;
}

sub
WifiLight_SetHSV_Target(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  $ledDevice->{helper}->{targetHue} = $hue;
  $ledDevice->{helper}->{targetSat} = $sat;
  $ledDevice->{helper}->{targetVal} = $val;
  return undef;
}

sub
WifiLight_setHSV_Readings(@)
{
  my ($ledDevice, $hue, $sat, $val) = @_;
  my ($r, $g, $b) = WifiLight_HSV2RGB($hue, $sat, $val);
  readingsBeginUpdate($ledDevice);
  readingsBulkUpdate($ledDevice, "hue", $hue % 360);
  readingsBulkUpdate($ledDevice, "saturation", $sat);
  readingsBulkUpdate($ledDevice, "brightness", $val);
  readingsBulkUpdate($ledDevice, "RGB", sprintf("%02X%02X%02X",$r,$g,$b));
  readingsBulkUpdate($ledDevice, "state", "on") if ($val > 0);
  readingsBulkUpdate($ledDevice, "state", "off") if ($val == 0);
  readingsEndUpdate($ledDevice, 1);
}

sub
WifiLight_HSV2RGB(@)
{
  my ($hue, $sat, $val) = @_;

  if ($sat == 0) 
  {
    return int(($val * 2.55) +0.5), int(($val * 2.55) +0.5), int(($val * 2.55) +0.5);
  }
  $hue %= 360;
  $hue /= 60;
  $sat /= 100;
  $val /= 100;

  my $i = int($hue);

  my $f = $hue - $i;
  my $p = $val * (1 - $sat);
  my $q = $val * (1 - $sat * $f);
  my $t = $val * (1 - $sat * (1 - $f));

  my ($r, $g, $b);

  if ( $i == 0 )
  {
    ($r, $g, $b) = ($val, $t, $p);
  }
  elsif ( $i == 1 )
  {
    ($r, $g, $b) = ($q, $val, $p);
  }
  elsif ( $i == 2 ) 
  {
    ($r, $g, $b) = ($p, $val, $t);
  }
  elsif ( $i == 3 ) 
  {
    ($r, $g, $b) = ($p, $q, $val);
  }
  elsif ( $i == 4 )
  {
    ($r, $g, $b) = ($t, $p, $val);
  }
  else
  {
    ($r, $g, $b) = ($val, $p, $q);
  }
  return (int(($r * 255) +0.5), int(($g * 255) +0.5), int(($b * 255) + 0.5));
}

sub
WifiLight_RGB2HSV(@)
{
  my ($ledDevice, $in) = @_;
  my $r = hex substr($in, 0, 2);
  my $g = hex substr($in, 2, 2);
  my $b = hex substr($in, 4, 2);
  my ($max, $min, $delta);
  my ($h, $s, $v);

  $max = $r if (($r >= $g) && ($r >= $b));
  $max = $g if (($g >= $r) && ($g >= $b));
  $max = $b if (($b >= $r) && ($b >= $g));
  $min = $r if (($r <= $g) && ($r <= $b));
  $min = $g if (($g <= $r) && ($g <= $b));
  $min = $b if (($b <= $r) && ($b <= $g));

  $v = int(($max / 2.55) + 0.5);  
  $delta = $max - $min;

  my $currentHue = ReadingsVal($ledDevice->{NAME}, "hue", 0);
  return ($currentHue, 0, $v) if (($max == 0) || ($delta == 0));

  $s = int((($delta / $max) *100) + 0.5);
  $h = ($g - $b) / $delta if ($r == $max);
  $h = 2 + ($b - $r) / $delta if ($g == $max);
  $h = 4 + ($r - $g) / $delta if ($b == $max);
  $h = int(($h * 60) + 0.5);
  $h += 360 if ($h < 0);
  return $h, $s, $v;
}

sub
WifiLight_HSV2fourChannel(@)
{
  my ($h, $s, $v) = @_;
  my ($r, $g, $b) = WifiLight_HSV2RGB($h, $s, $v);
  #white part, base 255
  my $white = 255;
  foreach ($r, $g, $b) { $white = $_ if ($_ < $white); }
  #remaining color part 
  my ($rr, $rg, $rb);
  $rr = $r - $white;
  $rg = $g - $white;
  $rb = $b - $white;
  return ($rr, $rg, $rb, $white);
}

sub
WifiLight_Milight_ColorConverter(@)
{
  my ($ledDevice, $cr, $cy, $cg, $cc, $cb, $cm) = @_;
  #my ($ledDevice) = @_;

  my @colorMap;
  
  #my $hueRed = 0;
  my $adjRed = 0 - ($cr || 0);
  #my $hueYellow = 60;
  my $adjYellow = 60 - ($cy || 0);
  #my $hueGreen = 120;
  my $adjGreen = 120 - ($cg || 0);
  #my $hueCyan = 180;
  my $adjCyan = 180 - ($cc || 0);
  #my $hueBlue = 240;
  my $adjBlue = 240 - ($cb || 0);
  #my $hueLilac = 300;
  my $adjLilac = 300 - ($cm || 0);

  #st34
  my $devRed = 168;
  #my $devRed = 176;
  my $devYellow = 134;
  #my $devYellow = 144;
  my $devGreen = 88;
  #my $devCyan = 48;
  my $devCyan = 56;
  my $devBlue = 8;
  my $devLilac = 208; #224

  my $i= 360;

  # red to yellow
  $adjRed += 360 if ($adjRed < 0); # in case of negative adjustment
  $devRed += 256 if ($devRed < $devYellow);
  $adjYellow += 360 if ($adjYellow < $adjRed);
  for ($i = $adjRed; $i <= $adjYellow; $i++)
  {
    $colorMap[$i % 360] = ($devRed - int((($devRed - $devYellow) / ($adjYellow - $adjRed)  * ($i - $adjRed)) +0.5)) % 255;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #yellow to green
  $devYellow += 256 if ($devYellow < $devGreen);
  $adjGreen += 360 if ($adjGreen < $adjYellow);
  for ($i = $adjYellow; $i <= $adjGreen; $i++)
  {
    $colorMap[$i % 360] = ($devYellow - int((($devYellow - $devGreen) / ($adjGreen - $adjYellow)  * ($i - $adjYellow)) +0.5)) % 255;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #green to cyan
  $devGreen += 256 if ($devGreen < $devCyan);
  $adjCyan += 360 if ($adjCyan < $adjGreen);
  for ($i = $adjGreen; $i <= $adjCyan; $i++)
  {
    $colorMap[$i % 360] = ($devGreen - int((($devGreen - $devCyan) / ($adjCyan - $adjGreen)  * ($i - $adjGreen)) +0.5)) % 255;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #cyan to blue
  $devCyan += 256 if ($devCyan < $devCyan);
  $adjBlue += 360 if ($adjBlue < $adjCyan);
  for ($i = $adjCyan; $i <= $adjBlue; $i++)
  {
    $colorMap[$i % 360] = ($devCyan - int((($devCyan - $devBlue) / ($adjBlue - $adjCyan)  * ($i - $adjCyan)) +0.5)) % 255;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #blue to lilac
  $devBlue += 256 if ($devBlue < $devLilac);
  $adjLilac += 360 if ($adjLilac < $adjBlue);
  for ($i = $adjBlue; $i <= $adjLilac; $i++)
  {
    $colorMap[$i % 360] = ($devBlue - int((($devBlue - $devLilac) / ($adjLilac - $adjBlue)  * ($i- $adjBlue)) +0.5)) % 255;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  #lilac to red
  $devLilac += 256 if ($devLilac < $devRed);
  $adjRed += 360 if ($adjRed < $adjLilac);
  for ($i = $adjLilac; $i <= $adjRed; $i++)
  {
    $colorMap[$i % 360] = ($devLilac - int((($devLilac - $devRed) / ($adjRed - $adjLilac)  * ($i - $adjLilac)) +0.5)) % 255;
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} create colormap h: ".($i % 360)." d: ".$colorMap[$i % 360]); 
  }
  @{$ledDevice->{helper}->{COLORMAP}} = @colorMap;
  return \@colorMap;
}

sub
WifiLight_RGB_ColorConverter(@)
{
  # default correction +/- 29° 
  my ($ledDevice, $cr, $cy, $cg, $cc, $cb, $cm) = @_;
  #my ($cr, $cy, $cg, $cc, $cb, $cm) = (0, -30, -10, -30, 0, -10);

  my @colorMap;

  for (my $i = 0; $i <= 360; $i++)
  {
    my $toR = WifiLight_HueDistance(0, $i);
    my $toY = WifiLight_HueDistance(60, $i);
    my $toG = WifiLight_HueDistance(120, $i);
    my $toC = WifiLight_HueDistance(180, $i);
    my $toB = WifiLight_HueDistance(240, $i);
    my $toM = WifiLight_HueDistance(300, $i);
    
    my $c = 0; # $i;
    $c += $cr - ($cr * $toR / 60) if (abs($toR) <= 60);
    $c += $cy - ($cy * $toY / 60) if (abs($toY) <= 60);
    $c += $cg - ($cg * $toG / 60) if (abs($toG) <= 60);
    $c += $cc - ($cc * $toC / 60) if (abs($toC) <= 60);
    $c += $cb - ($cb * $toB / 60) if (abs($toB) <= 60);
    $c += $cm - ($cm * $toM / 60) if (abs($toM) <= 60);

    $colorMap[$i] = int($i + $c + 0.5) % 360;

    #$colorMap[$i] = (int($colorMap[$i] + ($cr - ($cr * $toR / 45)) + 0.5) + 360) % 360 if (abs($toR) <= 45);
    #$colorMap[$i] = (int($colorMap[$i] + ($cy - ($cy * $toY / 45)) + 0.5) + 360) % 360 if (abs($toY) <= 45);
    #$colorMap[$i] = (int($colorMap[$i] + ($cg - ($cg * $toG / 45)) + 0.5) + 360) % 360 if (abs($toG) <= 45);
  }
  @{$ledDevice->{helper}->{COLORMAP}} = @colorMap;
  return \@colorMap;
}

# calculate the distance of two given hue
sub
WifiLight_HueDistance(@)
{
  my ($hue, $testHue) = @_;
  my $a = (360 + $hue - $testHue) % 360;
  my $b = (360 + $testHue - $hue) % 360;
  return ($a, $b)[$a > $b];
}

# helper for easying access to attrib
sub
WifiLight_ccAttribVal(@)
{
  my ($ledDevice, $dr, $dy, $dg, $dc, $db, $dm) = @_;
  my $a = AttrVal($ledDevice->{NAME}, 'colorCast', undef);
  if ($a)
  {
    my ($cr, $cy, $cg, $cc, $cb, $cm) = split (',', $a);
  }
  else
  {
    my ($cr, $cy, $cg, $cc, $cb, $cm) = ($dr, $dy, $dg, $dc, $db, $dm);
  }
  return ($dr, $dy, $dg, $dc, $db, $dm);
}


sub
WifiLight_CreateGammaMapping(@)
{
  my ($ledDevice, $gamma) = @_;

  my @gammaMap;

  for (my $i = 0; $i <= 100; $i += 1)
  {
    my $correction = ($i / 100) ** (1 / $gamma); 
    $gammaMap[$i] = $correction * 100;
    Log3 ($ledDevice, 5, "$ledDevice->{NAME} create gammamap v-in: ".$i.", v-out: $gammaMap[$i]");
  } 

  return \@gammaMap;
}

###############################################################################
#
# high level queue, long running color transitions
#
###############################################################################

sub
WifiLight_HighLevelCmdQueue_Add(@)
{
  my ($ledDevice, $hue, $sat, $val, $ctrl, $delay, $progress, $event, $targetTime) = @_;
  my $cmd;

  $cmd->{hue} = $hue;
  $cmd->{sat} = $sat;
  $cmd->{val} = $val;
  # $cmd->{k} = $k;
  $cmd->{ctrl} = $ctrl;
  $cmd->{delay} = $delay;
  $cmd->{progress} = $progress;
  $cmd->{event} = $event;
  $cmd->{targetTime} = $targetTime;
  $cmd->{inProgess} = 0;

  push @{$ledDevice->{helper}->{hlCmdQueue}}, $cmd;

  my $dbgStr = unpack("H*", $cmd->{ctrl} || '');
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} high level cmd queue add hsv/ctrl $cmd->{hue}, $cmd->{sat}, $cmd->{val}, ctrl $dbgStr, targetTime $cmd->{targetTime}, qlen ".@{$ledDevice->{helper}->{hlCmdQueue}});

  my $actualCmd = @{$ledDevice->{helper}->{hlCmdQueue}}[0];

  # sender busy ?
  return undef if (($actualCmd->{inProgess} || 0) == 1);
  return WifiLight_HighLevelCmdQueue_Exec($ledDevice);
}

sub
WifiLight_HighLevelCmdQueue_Exec(@)
{
  my ($ledDevice) = @_; 
  my $actualCmd = @{$ledDevice->{helper}->{hlCmdQueue}}[0];

  # transmission complete, remove
  shift @{$ledDevice->{helper}->{hlCmdQueue}} if ($actualCmd->{inProgess});

  # next in queue
  $actualCmd = @{$ledDevice->{helper}->{hlCmdQueue}}[0];
  my $nextCmd = @{$ledDevice->{helper}->{hlCmdQueue}}[1];

  # return if no more elements in queue
  return undef if (!defined($actualCmd->{inProgess}));

  # drop frames if next frame is already sceduled for given time. do not drop if it is the last frame or if it is a command  
  while (defined($nextCmd->{targetTime}) && ($nextCmd->{targetTime} < gettimeofday()) && !$actualCmd->{ctrl})
  {
    shift @{$ledDevice->{helper}->{hlCmdQueue}};
    $actualCmd = @{$ledDevice->{helper}->{hlCmdQueue}}[0];
    $nextCmd = @{$ledDevice->{helper}->{hlCmdQueue}}[1];
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} high level cmd queue exec drop frame at hlQueue level. hl qlen: ".@{$ledDevice->{helper}->{hlCmdQueue}});
  }
  Log3 ($ledDevice, 5, "$ledDevice->{NAME} high level cmd queue exec dropper delay: ".($actualCmd->{targetTime} - gettimeofday()) );

  # set hsv or if a device ctrl command is sceduled: send it and ignore hsv
  if ($actualCmd->{ctrl})
  {
    my $dbgStr = unpack("H*", $actualCmd->{ctrl});
    Log3 ($ledDevice, 4, "$ledDevice->{NAME} high level cmd queue exec ctrl $dbgStr, qlen ".@{$ledDevice->{helper}->{hlCmdQueue}}); 
    WifiLight_sendCtrl($ledDevice, $actualCmd->{ctrl});
  }
  else
  {
    my $isLast = (@{$ledDevice->{helper}->{hlCmdQueue}} == 1)?1:undef;
    if (($ledDevice->{helper}->{llLock} == 0) || $isLast)
    {
      Log3 ($ledDevice, 4, "$ledDevice->{NAME} high level cmd queue exec hsv $actualCmd->{hue}, $actualCmd->{sat}, $actualCmd->{val}, delay $actualCmd->{delay}, hl qlen ".@{$ledDevice->{helper}->{hlCmdQueue}}.", ll qlen ".@{$ledDevice->{helper}->{llCmdQueue}}.", lock ".$ledDevice->{helper}->{llLock});
      WifiLight_setHSV($ledDevice, $actualCmd->{hue}, $actualCmd->{sat}, $actualCmd->{val}, $isLast);
    }
    else
    {
      Log3 ($ledDevice, 5, "$ledDevice->{NAME} high level cmd queue exec drop frame at llQueue level. ll qlen: ".@{$ledDevice->{helper}->{llCmdQueue}}.", lock ".$ledDevice->{helper}->{llLock});
    }
  }
  $actualCmd->{inProgess} = 1;
  my $next = defined($nextCmd->{targetTime})?$nextCmd->{targetTime}:gettimeofday() + ($actualCmd->{delay} / 1000);
  Log3 ($ledDevice, 4, "$ledDevice->{NAME} high level cmd queue ask next $next");
  InternalTimer($next, "WifiLight_HighLevelCmdQueue_Exec", $ledDevice, 0);
  WifiLight_processEvent($ledDevice, $actualCmd->{event}, $actualCmd->{progress});
  return undef;
}

sub
WifiLight_HighLevelCmdQueue_Clear(@)
{
  my ($ledDevice) = @_;
  foreach my $a (keys %intAt) 
  {
    if (($intAt{$a}{ARG} eq $ledDevice) && ($intAt{$a}{FN} eq 'WifiLight_HighLevelCmdQueue_Exec'))
    {

      Log3 ($ledDevice, 4, "$ledDevice->{NAME} high level cmd queue clear, remove timer at ".$intAt{$a}{TRIGGERTIME} );
      delete($intAt{$a}) ;
    }
  }
  $ledDevice->{helper}->{hlCmdQueue} = [];
}

# dispatcher for ctrl cmd
sub
WifiLight_sendCtrl(@)
{
  my ($ledDevice, $ctrl) = @_;
  # TODO adjust for all bridge types
  if  (($ledDevice->{LEDTYPE} eq 'RGB') && ($ledDevice->{CONNECTION} =~ 'bridge-V[2|3]'))
  {
    my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
    my $delay = 100;
    WifiLight_LowLevelCmdQueue_Add($ledDevice, $ctrl, $receiver, $delay);
  }
  if ($ledDevice->{LEDTYPE} eq 'RGBW1')
  {
    my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
    my $delay = 100;
    WifiLight_LowLevelCmdQueue_Add($ledDevice, $ctrl, $receiver, $delay);
  }
  if ($ledDevice->{LEDTYPE} eq 'RGBW2')
  {
    my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
    my $delay = 100;
    WifiLight_LowLevelCmdQueue_Add($ledDevice, $ctrl, $receiver, $delay);
  }
  if ($ledDevice->{LEDTYPE} eq 'White')
  {
    my $receiver = sockaddr_in($ledDevice->{PORT}, inet_aton($ledDevice->{IP}));
    my $delay = 10;
    WifiLight_LowLevelCmdQueue_Add($ledDevice, $ctrl, $receiver, $delay);
  }
}

###############################################################################
#
# atomic low level udp communication to device
# required because there are timing requirements, mostly limitaions in processing speed of the bridge
# the commands should never be interrupted or canceled because some fhem readings are set in advance
#
###############################################################################

sub
WifiLight_LowLevelCmdQueue_Add(@)
{
  my ($ledDevice, $command, $receiver, $delay, $unlock) = @_;
  my $cmd;

  $cmd->{command} = $command;
  $cmd->{sender} = $ledDevice;
  $cmd->{receiver} = $receiver;
  $cmd->{delay} = $delay;
  $cmd->{unlock} = $unlock;
  $cmd->{inProgess} = 0;

  # push cmd into queue
  push @{$ledDevice->{helper}->{llCmdQueue}}, $cmd;

  my $dbgStr = unpack("H*", $cmd->{command});
  Log3 ($ledDevice, 5, "$ledDevice->{NAME} low level cmd queue add $dbgStr, qlen ".@{$ledDevice->{helper}->{llCmdQueue}}); 

  my $actualCmd = @{$ledDevice->{helper}->{llCmdQueue}}[0];
 
  # sender busy ?
  return undef if ($actualCmd->{inProgess});
  return WifiLight_LowLevelCmdQueue_Send($ledDevice);
}

sub
WifiLight_LowLevelCmdQueue_Send(@)
{
  my ($ledDevice) = @_; 
  my $actualCmd = @{$ledDevice->{helper}->{llCmdQueue}}[0];

  # transmission complete, remove
  shift @{$ledDevice->{helper}->{llCmdQueue}} if ($actualCmd->{inProgess});

  # next in queue
  $actualCmd = @{$ledDevice->{helper}->{llCmdQueue}}[0];
  
  # remove a low level queue lock if present and get next 
  while (($actualCmd->{unlock} || 0) == 1) 
  { 
    $actualCmd->{sender}->{helper}->{llLock} -= 1;
    Log3 ($ledDevice, 5, "$ledDevice->{NAME} | $actualCmd->{sender}->{NAME} unlock queue ".$actualCmd->{sender}->{helper}->{llLock});
    shift @{$ledDevice->{helper}->{llCmdQueue}}; 
    $actualCmd = @{$ledDevice->{helper}->{llCmdQueue}}[0];
  }

  # return if no more elements in queue
  return undef if (!defined($actualCmd->{command}));

  my $dbgStr = unpack("H*", $actualCmd->{command});
  Log3 ($ledDevice, 5, "$ledDevice->{NAME} low level cmd queue qlen ".@{$ledDevice->{helper}->{llCmdQueue}}.", send $dbgStr");

  # TCP
  if ($ledDevice->{PROTO})
  {
    if (!$ledDevice->{helper}->{SOCKET} || ($ledDevice->{helper}->{SELECT}->can_read(0) && !$ledDevice->{helper}->{SOCKET}->recv(my $data, 512)))
    {
      Log3 ($ledDevice, 4, "$ledDevice->{NAME} low level cmd queue send $dbgStr, qlen ".@{$ledDevice->{helper}->{llCmdQueue}}." connection refused: trying to reconnect");

      if ($ledDevice->{helper}->{SOCKET}) {
        $ledDevice->{helper}->{SOCKET}->shutdown(2);
        $ledDevice->{helper}->{SOCKET}->close();
      }

      $ledDevice->{helper}->{SOCKET} = IO::Socket::INET-> new (
        PeerPort => $ledDevice->{PORT},
        PeerAddr => $ledDevice->{IP},
        Timeout => 1,
        Blocking => 0,
        Proto => 'tcp') or Log3 ($ledDevice, 3, "$ledDevice->{NAME} low level cmd queue send ERROR $dbgStr, qlen ".@{$ledDevice->{helper}->{llCmdQueue}}." (reconnect giving up)");
      $ledDevice->{helper}->{SELECT} = IO::Select->new($ledDevice->{helper}->{SOCKET}) if $ledDevice->{helper}->{SOCKET};
    }
    $ledDevice->{helper}->{SOCKET}->send($actualCmd->{command}) if $ledDevice->{helper}->{SOCKET};
  }
  else
  {
    # print "send: $ledDevice->{NAME} $dbgStr \n";
    send($ledDevice->{helper}->{SOCKET}, $actualCmd->{command}, 0, $actualCmd->{receiver}) or Log3 ($ledDevice, 1, "$ledDevice->{NAME} low level cmd queue send ERROR $@ $dbgStr, qlen ".@{$ledDevice->{helper}->{llCmdQueue}});
  }

  $actualCmd->{inProgess} = 1;
  my $msec = $actualCmd->{delay} / 1000;
  InternalTimer(gettimeofday()+$msec, "WifiLight_LowLevelCmdQueue_Send", $ledDevice, 0);
  return undef;
}

1;

=pod
=item device
=item summary controls a large number of different LED types
=item summary_DE steuert eine gro&szlig;e Anzahl unterschiedlicher LED Typen
=begin html

<a name="WifiLight"></a>
<h3>WifiLight</h3>
<ul>
  <p>The module controls a large number of different "no name" LED types and provide a consistent interface.</p>
  <p>Following types will be supported:</p> 

  <!-- <table rules="all" cellpadding="6" style="border:solid 1px;"> -->
  <table>
	  <thead align="left">
		  <tr>
			  <th>
			  type / bridge
			  </th>
			  <th>
			  type
			  </th>
			  <th>
			  note
			  </th>
			  <th>
			  define signature
			  </th>
		  </tr>
	  </thead>
	  <tbody>
		  <tr>
			  <td>
			  Milight RGB first generation
			  </td>
			  <td>
			  E27, stripe controller
			  </td>
			  <td>
			  *(1,2,a,C)
			  </td>
			  <td>
			  RGB bridge-V2|3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  Milight RGBW1 first generation
			  </td>
			  <td>
			  RGBW stripe controller
			  </td>
			  <td>
			  *(1,2,a)
			  </td>
			  <td>
			  RGBW1 bridge-V2|3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  Milight Dual White
			  </td>
			  <td>
			  E14, E27, GU10, stripe controller, Downlight
			  </td>
			  <td>
			  *(1,2,b,W,nK)
			  </td>
			  <td>
			  White bridge-V2|3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  Milight RGBW2 second generation
			  </td>
			  <td>
			  E14, E27, GU10, stripe controller, Downlight
			  </td>
			  <td>
			  *(2,b,CW,S20)
			  </td>
			  <td>
			  RGBW2 bridge-V3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LW12 first generation (SSID LEDNet...)
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LW12
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LW12HX (SSID HX...)
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LW12HX
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LW12FC (SSID FC...)
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LW12FC
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD316 in RGB mode
			  </td>
			  <td>
			  E27
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LD316
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD316 in RGBW mode
			  </td>
			  <td>
			  E27
			  </td>
			  <td>
			  *(S20)
			  </td>
			  <td>
			  RGBW LD316
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD316A in RGBW mode
			  </td>
			  <td>
			  E27
			  </td>
			  <td>
			  *(S20)
			  </td>
			  <td>
			  RGBW LD316A
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382 in RGB mode
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382 in RGBW mode
			  </td>
			  <td>
			  RGBW stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGBW LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382A (FW 1.0.6+) in RGB mode
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382A (FW 1.0.6+) in RGBW mode
			  </td>
			  <td>
			  RGBW stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGBW LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  SENGLED
			  </td>
			  <td>
			  E27 bulb with build-in WLAN repeater
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  White Sengled
			  </td>
		  </tr>
		  <tr>
			  <td>
			  SUNRICHER with RGBW
			  </td>
			  <td>
			  Controller
			  </td>
			  <td>
			  *(!!!)
			  </td>
			  <td>
			  RGBW Sunricher
			  </td>
		  </tr>
	  </tbody>
  </table>

  <p>
  <small>
  (1) milght brigbe V2, V3, V4<br />
  (2) milight bridge V3, V4<br />
  (a) one group per bridge<br />
  (b) four independent group per bridge<br />
  (nK) no color temp support (Kelvin)<br />
  (C) pure color<br />
  (W) pure white<br />
  (CW) pure Color or pure white<br />
  (S20) Saturation &lt;20: switch to pure white channel<br />
  (!!!) EXPERIMENTAL<br />
  </p>
  </small>
  <p>
  <table>
    <tr>
      <td>
        <p><b>Color</b></p>
        <p>Colors can be specified in RGB or HSV color space.</p>
        <p>Color in <a name="WifiLight_Farbraum_HSV"><b>color space "HSV"</b></a> are completely and generally more intuitive than RGB.</p> 
        <p><b>H</b> (HUE: 0..360) are the basic color in a color wheel.
          <ul>
            <li>Red is at 0 °</li>
            <li>Green at 120 °</li>
            <li> Blue at 240 °</li>
          </ul>
        </p> 
        <p><b>S</b> (Saturation: 0..100) stands for the saturation of the color. A saturation of 100 means the color is "pure" or completely saturated. Blue, for example, with 100% saturation corresponds to RGB # 0000FF.</p>
        <p><b>V</b> (Value: 0..100) indicates the brightness. A value of 50 states that "half brightness".</p>
      </td>
      <td>
        <a name="WifiLight_Farbkreis">
          <svg style="width:450px; height:320px;"  viewBox="-100 -30 500 320">
            <linearGradient id="linearColors1" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#FF0000"></stop>
              <stop offset="100%" stop-color="#FFFF00"></stop>
            </linearGradient>
            <linearGradient id="linearColors2" x1="0.5" y1="0" x2="0.5" y2="1">
               <stop offset="0%" stop-color="#FFFF00"></stop>
               <stop offset="100%" stop-color="#00FF00"></stop>
            </linearGradient>
            <linearGradient id="linearColors3" x1="1" y1="0" x2="0" y2="1">
               <stop offset="0%" stop-color="#00FF00"></stop>
               <stop offset="100%" stop-color="#00FFFF"></stop>
            </linearGradient>
            <linearGradient id="linearColors4" x1="1" y1="1" x2="0" y2="0">
               <stop offset="0%" stop-color="#00FFFF"></stop>
               <stop offset="100%" stop-color="#0000FF"></stop>
            </linearGradient>
            <linearGradient id="linearColors5" x1="0.5" y1="1" x2="0.5" y2="0">
               <stop offset="0%" stop-color="#0000FF"></stop>
               <stop offset="100%" stop-color="#FF00FF"></stop>
            </linearGradient>
            <linearGradient id="linearColors6" x1="0" y1="1" x2="1" y2="0">
               <stop offset="0%" stop-color="#FF00FF"></stop>
               <stop offset="100%" stop-color="#FF0000"></stop>
            </linearGradient>
            <linearGradient id="linearColors7" x1="152" y1="130" x2="152" y2="35" gradientUnits="userSpaceOnUse">
               <stop offset="0.2" stop-color="#FFFFFF"></stop>
               <stop offset="1" stop-color="#FF0000"></stop>
            </linearGradient>
            <linearGradient id="linearColors8" x1="152" y1="130" x2="230" y2="190" gradientUnits="userSpaceOnUse">
               <stop offset="0.2" stop-color="#FFFFFF"></stop>
               <stop offset="1" stop-color="#00FF00"></stop>
            </linearGradient>
            <linearGradient id="linearColors9" x1="152" y1="130" x2="70" y2="190" gradientUnits="userSpaceOnUse">
               <stop offset="0.2" stop-color="#FFFFFF"></stop>
               <stop offset="1" stop-color="#0000FF"></stop>
            </linearGradient>
            <marker id="markerArrow" markerWidth="13" markerHeight="13" refX="2" refY="6" orient="auto">
              <path d="M2,2 L2,11 L10,6 L2,2" style="fill:grey;" />
            </marker>
            <path d="M150 10 a120 120 0 0 1 103.9230 60" fill="none" stroke="url(#linearColors1)" stroke-width="20" />
            <path d="M253.9230 70 a120 120 0 0 1 0 120" fill="none" stroke="url(#linearColors2)" stroke-width="20" />
            <path d="M253.9230 190 a120 120 0 0 1 -103.9230 60" fill="none" stroke="url(#linearColors3)" stroke-width="20" />
            <path d="M150 250 a120 120 0 0 1 -103.9230 -60" fill="none" stroke="url(#linearColors4)" stroke-width="20" />
            <path d="M46.077 190 a120 120 0 0 1 0 -120" fill="none" stroke="url(#linearColors5)" stroke-width="20" />
            <path d="M46.077 70 a120 120 0 0 1 103.9230 -60" fill="none" stroke="url(#linearColors6)" stroke-width="20" />
            <path d="M150,50 C250,50 250,180 180,200" fill="none" stroke="grey" stroke-width="2"  marker-end="url(#markerArrow)" />
            <text class="Label" x="126" y="208">HUE</text>
            <line x1="152" y1="130" x2="152" y2="35" stroke="url(#linearColors7)" stroke-width="4" />
            <line x1="136" y1="120" x2="136" y2="45" stroke="grey" stroke-width="2" marker-end="url(#markerArrow)" />
            <text class="Label" x="96" y="96">SAT</text>
            <line x1="152" y1="130" x2="230" y2="190" stroke="url(#linearColors8)" stroke-width="4" />
            <line x1="152" y1="130" x2="70" y2="190" stroke="url(#linearColors9)" stroke-width="4" />
            <text x="120" y="-10">0° (Red)</text>
            <text x="270" y="60">60° (Yellow)</text>
            <text x="270" y="220">120° (Green)</text>
            <text x="110" y="285">180° (Cyan)</text>
            <text x="-60" y="220">240° (Blue)</text>
            <text x="-90" y="60">300° (Magenta)</text>
          </svg>
        </a>
      </td>
    </tr>
  </table>
  </p>
  <p>
  <b>Color: HSV compared to RGB</b>
  <p>
    Normally, a color may be expressed in the HSV color space as well as in RGB color space.
  <p>
    Colors in the HSV color space usually seem more understandable. 
    To move a Green in the HSV color space a little more toward CYAN, simply increase the HUE value (angle) slightly. 
    In RGB color space, the same task is less intuitive to achieve by increasing blue.
  <p>
    Differences become clear in Transitions however.
    In order to dim BLUE up the HSV Transitions 240,100,0 -> 240,100,100 would be used. 
    To slowly dim RED (brightness 0) to BLUE the Transition in the HSV color space is 0,100,0 -> 240,100,100.
    In RGB color space (# 000000 -> # 0000FF) can not distinguish between the two versions.
    Here (correctly, but probably differently than intended) would appear in both cases, a white (brightness 0) as an initial value.
  </p>

  <p><b>Define</b></p>
  <ul>
    <li>
      <p><code>define &lt;name&gt; WifiLight &lt;LED type&gt; &lt;bridgetype&gt;:&lt;IP|FQDN&gt;</code></p>
      <p>
      <i><u>example</u></i>
      <ul>
        <p>
        <i>defines a milight RGBW2 (bulb or LED stripe controller) on a milight bridge version 3 or 4.
        The LED is allocated to a maximum of 4 groups available per bridge in order of definition:</i>
        <br/>
        <code>define wz.licht.decke WifiLight RGBW2 bridge-V3:192.168.178.142</code>
      </ul>
      <ul>
        <p>
        <i>defines a LD382A Controller with RGBW stripe:</i>
        <br/>
        <code>define wz.licht.decke WifiLight RGBW LD382A:192.168.178.142</code>
      </ul>    
      <ul>
        <p>
        <i>defines a LD382A Controller with RGB stripe:</i>
        <br/>
        <code>define wz.licht.decke WifiLight RGB LD382A:192.168.178.142</code>
      </ul>
      <p>WifiLight has a <a href="#WifiLight_Farbkalibrierung">"color calibration"</a>. Ideally, a calibration should be performed every time after a lamp change or after definition.</p>
    </ul>
  </li>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; <b>on</b> [ramp]</code></p>
      <p>Turns on the device. It is either chosen 100% White or the color defined by the attribute "default color".
      <p>Advanced options:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>off</b> [ramp]</code></p>
      <p>Turns of the device.
      <p>Advanced options:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>dimup</b></code></p>
      <p>Increases the brightness by a fixed amount. The attribute "dimStep" or the default "7" is applied.<br />
      This command is useful to increase particularly the brightness by a wall switch or a remote control.
      <p>Advanced options:
        <ul>
          <li>none</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>dimdown</b></code></p>
      <p>Decreases the brightness by a fixed amount. The attribute "dimStep" or the default "7" is applied.<br />
      This command is useful to reduce particularly the brightness by a wall switch or a remote control.
      <p>Advanced options:
        <ul>
          <li>none</li>
        </ul>
      </p>
    </li>
    <li>  
      <p><code>set &lt;name&gt; <b>dim</b> level [ramp] [q]</code></p>
      <p>Sets the brightness to the specified level (0..100).
      This command also maintains the preset color even with "dim 0" (off) and then "dim xx" (turned on) at. 
      Therefore, it represents an alternative form to "off" / "on". The latter would always choose the "default color".
      <p>Advanced options:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
      <p>Flags:
        <ul>
          <li>q</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>HSV</b> H,S,V [ramp] [s|l|q] [event]</code></p>
      <p>Sets the color in the <a href="#WifiLight_Farbraum_HSV">HSV color space</a>. If the ramp is specified (as a time in seconds), the module calculates a soft color transition from the current color to the newly set.
      <ul><i>For example, sets a saturated blue with half brightness:</i><br /><code>set wz.licht.decke HSV 240,100,50</code></ul>
      <p>Advanced options:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
      <p>Flags:
        <ul>
          <li>s l q event</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>RGB</b> RRGGBB [ramp] [l|s|q] [event]</code></p>
      <p>Sets the color in the RGB color space.
      <p>Advanced options:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
      <p>Flags:
        <ul>
          <li>s l q event</li>
        </ul>
      </p>
    </ul>
  </li>
  <p><b>Meaning of Flags</b></p>
  Certain commands (set) can be marked with special flags.
  <p>
  <ul>
    <li>ramp: 
      <ul>
        Time in seconds for a soft color or brightness transition. The soft transition starts at the currently visible color and is calculated for the specified.
      </ul>
    </li>
    <li>s: 
      <ul>
        (short, default). A smooth transition to another color is carried out in the <a href="#WifiLight_Farbkreis">"color wheel"</a> on the shortest path. 
        A transition from red to green lead by the shortest route through yellow.
      </ul>
    </li>
    <li>l: 
      <ul>
        (long). A smooth transition to another color is carried out in the <a href="#WifiLight_Farbkreis">"color wheel"</a> on the "long" way.
        A transition from red to green then leads across magenta, blue, and cyan.
      </ul>
    </li>
    <li>q: 
      <ul>
        (queue). Commands with this flag are cached in an internal queue and will not run before the currently running soft transitions have been processed. 
        Commands without the flag will be processed immediately. In this case all running transitions are stopped immediately and the queue will be cleared.
      </ul>
    </li>
    <li>event: 
      <ul>
        designator ([A-Za-z_0-9])
        <p>
          WifiLight creates, when using this flag, during transitions to another color messages (events) in the form:
        <p>
        <code>WifiLight &ltNAME&gt programm: &ltEVENT&gt &ltXX&gt</code>.
        <p>
        &ltEVENT&gt is the designator as specified in the flag.<br/>
        &ltXX&gt is the progress (percentage) of the transition.<br/>
        <p>
        Depending on the total duration of the transition, the values from 0 to 100 will not completely go through but for 0% and 100% is guaranteed always a event. 
        To these events can then be reacted within a notify or DOIF to (for example):
        <ul>
          <li>increase the volume of a radio when a lamp is turned on in the morning slowly</li>
          <li>A color transition can be restarted in a notify if it is complete (loop it, even complex transitions)</li>
          <li>Other light sources can be synchronized by individually created color transitions.</li>
        </ul>
      </ul>
    </li>
  </ul>
  <p><b><a name="WifiLight_Farbkalibrierung"></a>color calibration</b></p>
  WifiLight supports two different types of color calibrations:
  <ul>
    <p>
    <b>Correction of saturated colors</b>
    <p>
    background:
    <p>
      YELLOW, for example, is defined as a mixture of red and green light in equal parts.
      Depending on the LED and control used the green channel may be much more luminous.
      If the red and green LEDs are each fully driven, GREEN predominates in this mixture and the desired YELLOW would get a distinct green tint.
      In this example, no yellow would be generated (corresponding to 60 ° in the <a href="#WifiLight_Farbkreis">"color wheel"</a>) for HSV 60,100,100. 
      Instead GREEN would be generated with yellow tinge, perhaps corresponding to an estimated color angle of 80 °. 
      The required correction for yellow would therefore minus 20° (60° target - 80° result = -20° correction). 
      YELLOW may have to be corrected as to -20 °. Possible values per correction point are +/- 29 °.
    <p>
    procedure:
    <p>
      The correction of the full color is controlled by the attribute "color cast". 
      Here 6 (comma separated) values are specified in the range from -29 to 29. 
      These values are in accordance with the angle correction for red (0 °), yellow (60 °), green (120 °), cyan (180 °), blue (240 °) and magenta (300 °). 
      First, the deviation of the mixed colors (60 ° / 180 ° / 300 °) should be determined as in the above example, and stored in the attribute. 
      Following the primary colors (0 ° / 120 ° / 240 °) should be corrected so that the smooth transitions between adjacent pure colors appear as linear as possible. 
      This process may need to be repeated iteratively multiple times until the result is harmonious.
    <p>
    <b>White Balance</b>
    <p>
    background:
    <p>
    Some bulbs produce white light by mixing the RGB channels (for example, LW12). 
    Depending on the light intensity of the RGB channels of the LED strips used, the result is different. 
    One or two colors dominate. 
    In addition, there are various types of white light. 
    Cold light has a higher proportion of blue. 
    In Central Europe mostly warm white light is used for light sources. 
    This has a high red and low blue component.
    <p>
    WifiLight offers the possibility for mixed RGB white to adapt the composition. 
    The adjustment is carried out via the attribute "white point". 
    The attribute expects a value between 0 and 1 (decimal point with) and the three colors are separated by a comma for each of the three RGB channels.
    <p>
    procedure:
    <p>
    A value of "1,1,1" sets all the three channels to 100% each. 
    Assuming that the blue component of the white light should be reduced, a value of "1,1,0.5" sets the third channel (BLUE) in white on 0.5 according to 50%. 
    Before doing a white balance correction the adjusment of the saturated color should be completed.
  </ul>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <code>attr &ltname&gt <b>colorCast</b> &ltR,Y,G,C,B,M&gt</code>
      <p>   
      <a href="#WifiLight_Farbkalibrierung">color calibration</a> of saturated colors.
      R(ed), Y(ellow), G(reen), C(yan), B(lue), M(agenta) in the range of +/- 29 (degrees)
    </li>
    <li>
      <code>attr &ltname&gt <b>defaultColor</b> &ltH,S,V&gt</code>
      <p>   
      Specify the light color in HSV which is selected at "on". Default is white.
    </li>
    <li>
      <code>attr &ltname&gt <b>defaultRamp</b> &lt0 bis X&gt</code>
      <p>   
      Time in seconds. If this attribute is set, a smooth transition is always implicitly generated if no ramp in the set is indicated.
    </li>
    <li>
      <code>attr &ltname&gt <b>dimStep</b> &lt0 bis 100&gt</code>
      <p>   
      Value by which the brightness at dim up and dim-down is changed. Default is "7"
    </li>
    <li>
      <code>attr &ltname&gt <b>gamma</b> &ltX.X&gt</code>
      <p>   
        The human eye perceives brightness changes very differently to (logarithmic). 
        At low output brightness even a small change in brightness is perceived as very strong and on the other side strong changes are needed at high luminance. 
        Therefore, a logarithmic correction of brightness increase of lamps is necessary so that the increase is found to be uniform. 
        Some controllers perform this correction internally. 
        In other cases it is necessary to store this correction in the module. 
        A gamma value of 1.0 (default) results in a linear output values. 
        Values less than 1.0 lead to a logarithmic correction.
    </li>
    <li>
      <code>attr &ltname&gt <b>whitePoint</b> &ltR,G,B&gt</code>
      <p>   
      <a href="#WifiLight_Farbkalibrierung">color calibration</a> for mixed RGB white light.
    </li>
    <li>
      <code>attr &ltname&gt <b><a href="#readingFnAttributes">readingFnAttributes</a></b></code>
    </li>
  </ul>
  <p><b>Colored device-icon for FhemWeb</b>
  <ul>
    <p>
    To activate a colored icon for <a href="#FHEMWEB">FhemWeb</a> the following attribute must be set:
    <p>
    <li>
      <code>attr &ltname&gt <b>devStateIcon</b> {Color_devStateIcon(ReadingsVal($name,"RGB","000000"))}</code>
    </li>
  </ul>
  <p><b>Colorpicker for FhemWeb</b>
  <ul>
    <p>
    In order for the Color Picker can be used in <a href="#FHEMWEB">FhemWeb</a> following attributes need to be set:
    <p>
    <li>
      <code>attr &ltname&gt <b>webCmd</b> RGB</code>
    </li>
    <li>
      <code>attr &ltname&gt <b>widgetOverride</b> RGB:colorpicker,RGB</code>
    </li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="WifiLight"></a>
<h3>WifiLight</h3>
<ul>
  <p>Das Modul steuert eine gro&szlig;e Anzahl unterschiedlicher &quot;no name&quot; LED Typen und stellt Ihnen einheitliches Interface zur Verf&uuml;gung.</p>
  <p>Folgende Typen werden unterstützt:</p> 

  <!-- <table rules="all" cellpadding="6" style="border:solid 1px;"> -->
  <table>
	  <thead align="left">
		  <tr>
			  <th>
			  Leuchtmitteltyp / bridge
			  </th>
			  <th>
			  Type
			  </th>
			  <th>
			  Notiz
			  </th>
			  <th>
			  Signatur im define
			  </th>
		  </tr>
	  </thead>
	  <tbody>
		  <tr>
			  <td>
			  Milight RGB erste Generation
			  </td>
			  <td>
			  E27, stripe controller
			  </td>
			  <td>
			  *(1,2,a,C)
			  </td>
			  <td>
			  RGB bridge-V2|3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  Milight RGBW1 erste Generation
			  </td>
			  <td>
			  RGBW stripe controller
			  </td>
			  <td>
			  *(1,2,a)
			  </td>
			  <td>
			  RGBW1 bridge-V2|3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  Milight White
			  </td>
			  <td>
			  E14, E27, GU10, stripe controller, Downlight
			  </td>
			  <td>
			  *(1,2,b,W,nK)
			  </td>
			  <td>
			  White bridge-V2|3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  Milight RGBW2 zweite Generation
			  </td>
			  <td>
			  E14, E27, GU10, stripe controller, Downlight
			  </td>
			  <td>
			  *(2,b,CW,S20)
			  </td>
			  <td>
			  RGBW2 bridge-V3
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LW12 erste Generation (SSID LEDNet...)
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LW12
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LW12HX (SSID HX...)
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LW12HX
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LW12FC (SSID FC...)
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LW12FC
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD316 im RGB mode
			  </td>
			  <td>
			  E27
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LD316
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD316 im RGBW mode
			  </td>
			  <td>
			  E27
			  </td>
			  <td>
			  *(S20)
			  </td>
			  <td>
			  RGBW LD316
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD316A im RGBW mode
			  </td>
			  <td>
			  E27
			  </td>
			  <td>
			  *(S20)
			  </td>
			  <td>
			  RGBW LD316A
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382 im RGB mode
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382 im RGBW mode
			  </td>
			  <td>
			  RGBW stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGBW LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382A (FW 1.0.6) im RGB mode
			  </td>
			  <td>
			  RGB stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGB LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  LD382A (FW 1.0.6) im RGBW mode
			  </td>
			  <td>
			  RGBW stripe controller
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  RGBW LD382
			  </td>
		  </tr>
		  <tr>
			  <td>
			  SENGLED
			  </td>
			  <td>
			  E27 mit WLAN repeater
			  </td>
			  <td>
			  &nbsp;
			  </td>
			  <td>
			  White Sengled
			  </td>
		  </tr>
		  <tr>
			  <td>
			  SUNRICHER mit RGBW
			  </td>
			  <td>
			  Controller
			  </td>
			  <td>
			  *(!!!)
			  </td>
			  <td>
			  RGBW Sunricher
			  </td>
		  </tr>
	  </tbody>
  </table>

  <p>
  <small>
  (1) milght brigbe V2, V3, V4<br />
  (2) milight bridge V3, V4<br />
  (a) eine Gruppe pro bridge<br />
  (b) vier unabh&auml;ngige Gruppen pro bridge<br />
  (nK) kein Temperatursupport, Kelvin<br />
  (C) rein Color<br />
  (W) rein White<br />
  (CW) rein Color oder White<br />
  (S20) Saturation &lt;20: umschalten white Channel<br />
  (!!!) EXPERIMENTAL<br />
  </p>
  </small>
  <p>
  <table>
    <tr>
      <td>
        <p><b>Farbangaben</b></p>
        <p>Farben können im RGB oder im HSV Farbraum angegeben werden.</p>
        <p>Farbangaben im <a name="WifiLight_Farbraum_HSV"><b>Farbraum "HSV"</b></a> sind vollständig und in der Regel intuitiver als RGB.</p> 
        <p><b>H</b> (HUE: 0..360) gibt die Grundfarbe in einem Farbkreis an. 
          <ul>
            <li>Rot liegt bei 0°</li>
            <li>Grün bei 120°</li>
            <li>Blau bei 240°</li>
          </ul>
        </p> 
        <p><b>S</b> (Saturation/Sättigung: 0..100) steht für die Sättigung der Farbe. Eine Sättigung von 100 bedeutet die Farbe ist "rein" oder komplett gesättigt. Blau zum Beispiel mit 100% Sättigung entspricht RGB #0000FF.</p>
        <p><b>V</b> (Value: 0..100) gibt die Helligkeit an. Ein V von 50 heißt: "halbe Helligkeit".</p>
      </td>
      <td>
        <a name="WifiLight_Farbkreis">
          <svg style="width:450px; height:320px;"  viewBox="-100 -30 500 320">
            <linearGradient id="linearColors1" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#FF0000"></stop>
              <stop offset="100%" stop-color="#FFFF00"></stop>
            </linearGradient>
            <linearGradient id="linearColors2" x1="0.5" y1="0" x2="0.5" y2="1">
               <stop offset="0%" stop-color="#FFFF00"></stop>
               <stop offset="100%" stop-color="#00FF00"></stop>
            </linearGradient>
            <linearGradient id="linearColors3" x1="1" y1="0" x2="0" y2="1">
               <stop offset="0%" stop-color="#00FF00"></stop>
               <stop offset="100%" stop-color="#00FFFF"></stop>
            </linearGradient>
            <linearGradient id="linearColors4" x1="1" y1="1" x2="0" y2="0">
               <stop offset="0%" stop-color="#00FFFF"></stop>
               <stop offset="100%" stop-color="#0000FF"></stop>
            </linearGradient>
            <linearGradient id="linearColors5" x1="0.5" y1="1" x2="0.5" y2="0">
               <stop offset="0%" stop-color="#0000FF"></stop>
               <stop offset="100%" stop-color="#FF00FF"></stop>
            </linearGradient>
            <linearGradient id="linearColors6" x1="0" y1="1" x2="1" y2="0">
               <stop offset="0%" stop-color="#FF00FF"></stop>
               <stop offset="100%" stop-color="#FF0000"></stop>
            </linearGradient>
            <linearGradient id="linearColors7" x1="152" y1="130" x2="152" y2="35" gradientUnits="userSpaceOnUse">
               <stop offset="0.2" stop-color="#FFFFFF"></stop>
               <stop offset="1" stop-color="#FF0000"></stop>
            </linearGradient>
            <linearGradient id="linearColors8" x1="152" y1="130" x2="230" y2="190" gradientUnits="userSpaceOnUse">
               <stop offset="0.2" stop-color="#FFFFFF"></stop>
               <stop offset="1" stop-color="#00FF00"></stop>
            </linearGradient>
            <linearGradient id="linearColors9" x1="152" y1="130" x2="70" y2="190" gradientUnits="userSpaceOnUse">
               <stop offset="0.2" stop-color="#FFFFFF"></stop>
               <stop offset="1" stop-color="#0000FF"></stop>
            </linearGradient>
            <marker id="markerArrow" markerWidth="13" markerHeight="13" refX="2" refY="6" orient="auto">
              <path d="M2,2 L2,11 L10,6 L2,2" style="fill:grey;" />
            </marker>
            <path d="M150 10 a120 120 0 0 1 103.9230 60" fill="none" stroke="url(#linearColors1)" stroke-width="20" />
            <path d="M253.9230 70 a120 120 0 0 1 0 120" fill="none" stroke="url(#linearColors2)" stroke-width="20" />
            <path d="M253.9230 190 a120 120 0 0 1 -103.9230 60" fill="none" stroke="url(#linearColors3)" stroke-width="20" />
            <path d="M150 250 a120 120 0 0 1 -103.9230 -60" fill="none" stroke="url(#linearColors4)" stroke-width="20" />
            <path d="M46.077 190 a120 120 0 0 1 0 -120" fill="none" stroke="url(#linearColors5)" stroke-width="20" />
            <path d="M46.077 70 a120 120 0 0 1 103.9230 -60" fill="none" stroke="url(#linearColors6)" stroke-width="20" />
            <path d="M150,50 C250,50 250,180 180,200" fill="none" stroke="grey" stroke-width="2"  marker-end="url(#markerArrow)" />
            <text class="Label" x="126" y="208">HUE</text>
            <line x1="152" y1="130" x2="152" y2="35" stroke="url(#linearColors7)" stroke-width="4" />
            <line x1="136" y1="120" x2="136" y2="45" stroke="grey" stroke-width="2" marker-end="url(#markerArrow)" />
            <text class="Label" x="96" y="96">SAT</text>
            <line x1="152" y1="130" x2="230" y2="190" stroke="url(#linearColors8)" stroke-width="4" />
            <line x1="152" y1="130" x2="70" y2="190" stroke="url(#linearColors9)" stroke-width="4" />
            <text x="120" y="-10">0° (Rot)</text>
            <text x="270" y="60">60° (Gelb)</text>
            <text x="270" y="220">120° (Grün)</text>
            <text x="110" y="285">180° (Cyan)</text>
            <text x="-60" y="220">240° (Blau)</text>
            <text x="-90" y="60">300° (Magenta)</text>
          </svg>
        </a>
      </td>
    </tr>
  </table>
  </p>
  <p><b>Farbangaben: HSV gegenüber RGB</b><p>
        <p>
        Im Normalfall kann eine Farbe im HSV Farbraum genauso wie im RGB Farbraum dargestellt werden.
        <p>
        Farben im HSV Farbraum wirken meist verständlicher. 
        Um ein Grün im HSV Farbraum etwas mehr in Richtung CYAN zu bewegen wird einfach der HUE Wert (Winkel) etwas erhöht. 
        Im RGB Farbraum ist die gleiche Aufgabe weniger intuitiv durch eine Erhöhung von BLAU zu erreichen. 
        <p>
        Unterschiede werden jedoch bei Transitions deutlich. 
        Um BLAU langsam auf zu dimmen lauten die HSV Transitions 240,100,0 -> 240,100,100. 
        Um von ROT (Helligkeit 0) langsam auf BLAU zu dimmen wird im HSV Farbraum 0,100,0 -> 240,100,100 verwendet. 
        Im RGB Farbraum (#000000 -> #0000FF) kann nicht zwischen den beiden Varianten unterschieden werden. 
        Hier würde (richtiger weise, vermutlich jedoch anders als beabsichtigt) in beiden Fällen ein Weiß (Helligkeit 0) als Startwert erscheinen.
  </p>

  <p><b>Define</b></p>
  <ul>
    <li>
      <p><code>define &lt;name&gt; WifiLight &lt;Leuchtmitteltyp&gt; &lt;bridgetyp&gt;:&lt;IP|FQDN&gt;</code></p>
      <p>
      <i><u>Beispiele</u></i>
      <ul>
        <p>
        <i>definiert einen milight RGBW2 Leuchtmittel (Bulb oder LED stripe controller) an einer milight bridge Version 3 oder 4. 
        Die LED wird den maximal 4 verf&uuml;gbaren Gruppen pro bridge in der Reihenfolge der Definition zugeordnet:</i>
        <br/>
        <code>define wz.licht.decke WifiLight RGBW2 bridge-V3:192.168.178.142</code>
      </ul>
      <ul>
        <p>
        <i>definiert einen LD382A Controller mit RGBW Stripe:</i>
        <br/>
        <code>define wz.licht.decke WifiLight RGBW LD382A:192.168.178.142</code>
      </ul>    
      <ul>
        <p>
        <i>definiert einen LD382A Controller mit RGB Stripe:</i>
        <br/>
        <code>define wz.licht.decke WifiLight RGB LD382A:192.168.178.142</code>
      </ul>    
      <p>WifiLight verfügt über eine <a href="#WifiLight_Farbkalibrierung">"Farbkalibrierung"</a>. Sinnvollerweise sollte nach einem Leuchtmitteltausch oder einem define eine Kalibrierung vorgenommen werden.</p>
    </ul>
  </li>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; <b>on</b> [ramp]</code></p>
      <p>Schaltet das device ein. Dabei wird entweder 100% Weiß oder die im Attribut "defaultColor" definierte Farbe gewählt.
      <p>Erweiterte Parameter:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>off</b> [ramp]</code></p>
      <p>Schaltet das device aus.
      <p>Erweiterte Parameter:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>dimup</b></code></p>
      <p>Erhöht die Helligkeit um einen festen Betrag. Dabei wird der im Attribut "dimStep" definierte Wert oder der Default "7" angewendet.<br>Dieser Befehl eignet sich besonders um die Helligkeit über einen Wandschalter oder eine Fernbedienung zu erhöhen.
      <p>Erweiterte Parameter:
        <ul>
          <li>keine</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>dimdown</b></code></p>
      <p>Verringert die Helligkeit um einen festen Betrag. Dabei wird der im Attribut "dimStep" definierte Wert oder der Default "7" angewendet.<br>Dieser Befehl eignet sich besonders um die Helligkeit über einen Wandschalter oder eine Fernbedienung zu verringern
      <p>Erweiterte Parameter:
        <ul>
          <li>keine</li>
        </ul>
      </p>
    </li>
    <li>  
      <p><code>set &lt;name&gt; <b>dim</b> level [ramp] [q]</code></p>
      <p>Setzt die Helligkeit auf den angegebenen level (0..100).<br>Dieser Befehl behält außerdem die eingestellte Farbe auch bei "dim 0" (ausgeschaltet) und nachfolgendem "dim xx" (eingeschaltet) bei. Daher stellt er eine alternative Form zu "off" / "on" dar. Letzteres würde immer die "defaultColor" wählen.  
      <p>Erweiterte Parameter:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
      <p>Flags:
        <ul>
          <li>q</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>HSV</b> H,S,V [ramp] [s|l|q] [event]</code></p>
      <p>Setzt die Farbe im <a href="#WifiLight_Farbraum_HSV">HSV Farbraum</a>. Wenn die ramp (als Zeit in Sekunden) angegeben ist, berechnet das modul einen weichen Farbübergang von der aktuellen Farbe zur neu gesetzten.
      <ul><i>Beispiel, setzt ein gesättigtes Blau mit halber Helligkeit:</i><br /><code>set wz.licht.decke HSV 240,100,50</code></ul>
      <p>Erweiterte Parameter:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
      <p>Flags:
        <ul>
          <li>s l q event</li>
        </ul>
      </p>
    </li>
    <li>
      <p><code>set &lt;name&gt; <b>RGB</b> RRGGBB [ramp] [l|s|q] [event]</code></p>
      <p>Setzt die Farbe im RGB Farbraum. 
      <p>Erweiterte Parameter:
        <ul>
          <li>ramp</li>
        </ul>
      </p>
      <p>Flags:
        <ul>
          <li>s l q event</li>
        </ul>
      </p>
    </ul>
  </li>
  <p><b>Bedeutung der Flags</b></p>
  Bestimmte Befehle (set) können mit speziellen Flags versehen werden.
  <p>
  <ul>
    <li>ramp: 
      <ul>
        Zeit in Sekunden für einen weichen Farb- oder Helligkeitsübergang. Der weiche Übergang startet bei der aktuell sichtbaren Farbe und wird zur angegeben berechnet. 
      </ul>
    </li>
    <li>s: 
      <ul>
        (short, default). Ein weicher Übergang zu einer anderen Farbe wird im <a href="#WifiLight_Farbkreis">"Farbkreis"</a> auf dem kürzesten Weg durchgeführt.</br>
        Eine Transition von ROT nach GRÜN führt auf dem kürzesten Weg über GELB.
      </ul>
    </li>
    <li>l: 
      <ul>
        (long). Ein weicher Übergang zu einer anderen Farbe wird im <a href="#WifiLight_Farbkreis">"Farbkreis"</a> auf dem "langen" Weg durchgeführt.</br>
        Eine Transition von ROT nach GRÜN führt dann über MAGENTA, BLAU, und CYAN.
      </ul>
    </li>
    <li>q: 
      <ul>
        (queue). Kommandos mit diesem Flag werden in einer internen Warteschlange zwischengespeichert und erst ausgeführt nachdem die aktuell laufenden weichen Übergänge
        abgearbeitet wurden. Kommandos ohne das Flag werden sofort abgearbeitet. Dabei werden alle laufenden Übergänge sofort abgebrochen und die Warteschlange wird gelöscht.
      </ul>
    </li>
    <li>event: 
      <ul>
        Beliebige Bezeichnung ([A-Za-z_0-9])
        <p>
        WifiLight erzeugt bei Verwendung dieses Flags im Verlauf weicher Übergange zu einer anderen Farbe Nachrichten (events) in der Form:
        <p>
        <code>WifiLight &ltNAME&gt programm: &ltEVENT&gt &ltXX&gt</code>.
        <p>
        &ltEVENT&gt entspricht dem Namen so wie im Flag angegeben.<br/>
        &ltXX&gt ist der prozentuale Fortschritt des Übergangs.<br/>
        <p>
        Je nach Gesamtdauer des Übergangs werden die Werte von 0 bis 100 nicht komplett durchlaufen wobei jedoch für 0% und 100% immer ein event garantiert ist. Auf diese events kann dann innerhalb von notify oder DOIF reagiert werden um zum Beispiel:
        <ul>
          <li>die Lautstärke eines Radios anzupassen wenn eine LED morgens langsam hochgedimmt wird</li>
          <li>ein Farbübergang kann in einem notify neu gestartet werden wenn er komplett ist (loop)</li>
          <li>andere Leuchtmittel können mit erstellten Farbübergängen synchronisiert werden</li>
        </ul>
      </ul>
    </li>
  </ul>
  <p><b><a name="WifiLight_Farbkalibrierung"></a>Farbkalibrierung</b></p>
  WifiLight unterstützt zwei unterschiedliche Formen der Farbkalibrierungen:
  <ul>
    <p>
    <b>Korrektur gesättigter Farben</b>
    <p>
    Hintergrund:
    <p>
    GELB, zum Beispiel, ist definiert als Mischung aus ROTEM und GRÜNEM Licht zu gleichen Teilen. 
    Je nach verwendeter LED und Ansteuerung ist der GRÜNE Kanal nun möglicherweise viel leuchtstärker.
    Wenn jetzt also die ROTE und GRÜNE LED jeweils voll angesteuert werden überwiegt GRÜN in dieser Mischung und das gewünschte GELB bekäme einen deutlichen Grünstich.
    In diesem Beispiel würde jetzt für HSV 60,100,100 kein Gelb (entsprechend 60° im <a href="#WifiLight_Farbkreis">"Farbkreis"</a>) erzeugt. 
    Stattdessen würde GRÜN mit GELBSTICH erzeugt das vielleicht einem geschätzten Farbwinkel von 80° entspricht.
    Die erforderliche Korrektur für GELB würde also minus 20° betragen (60° SOLL - 80° IST = -20° Korrektur). 
    GELB müsste als um -20° korrigiert werden. Mögliche Werte pro Korrektur-Punkt sind +/- 29°.
    <p>
    Vorgehen:
    <p>
    Die Korrektur der Vollfarben wird über das Attribut "colorCast" gesteuert. Dabei werden 6 (Komma getrennte) Werte im Bereich -29 bis 29 angegeben.
    Diese Werte stehen entsprechen der Winkelkorrektur für ROT (0°), GELB (60°), GRÜN (120°), CYAN (180°), BLAU (240°) und MAGENTA (300°).
    Zuerst sollte die Abweichung für 60°/180°/300° (die Mischfarben) so wie in obigem Beispiel ermittelt und im Attribut hinterlegt werden.
    Im Anschluss sollten die Primärfarben (0°/120°/240°) so korrigiert werden das die weichen Übergänge zwischen benachbarten reinen Farben möglichst linear erscheinen.
    Dieser Vorgang muss eventuell iterativ mehrfach wiederholt werden bis das Ergebniss stimmig ist. 
    <p>
    <b>Weißabgleich</b>
    <p>
    Hintergrund:
    <p>
    Einige Leuchtmittel erzeugen weißes Licht durch Mischung der RGB Kanäle (zum Beispiel LW12). 
    Je nach Leuchtstärke der RGB Kanäle der verwendeten LED Streifen unterscheidet sich das Ergebnis und eine oder zwei Farben dominieren. 
    Zusätzlich gibt es verschiedene Formen weißen Lichtes. Kaltes Licht hat einen höheren Blauanteil. 
    Dagegen wird in Mitteleuropa für Leuchtmittel meist warm-weiß verwendet welches einen hohen ROT- und geringen BLAU Anteil hat.
    <p>
    WifiLight bietet die Möglichkeit bei RGB gemischtem Weiß die Zusammensetzung anzupassen. Die Anpassung erfolgt über das Attribut "whitePoint".
    Dieses erwartet für jeden der drei RGB Kanäle einen Wert zwischen 0 und 1 (ein Komma wird als Punkt angegeben). Die drei Werte werden mit einem normalen Komma getrennt.
    <p>
    Vorgehen:
    <p>
    Eine Angabe von "1,1,1" setzt alle die drei Kanäle auf jeweils 100%. Angenommen der BLAU Anteil des weißen Lichtes soll nun verringert werden. 
    Ein Wert von "1,1,0.5" setzt den dritten Kanal (BLAU) bei Weiß auf 0.5 entsprechend 50%. Vor einem Weißabgleich sollte die Korrektur der Vollfarben abgeschlossen sein.  
  </ul>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <code>attr &ltname&gt <b>colorCast</b> &ltR,Y,G,C,B,M&gt</code>
      <p>   
      <a href="#WifiLight_Farbkalibrierung">Farbkalibrierung</a> der voll gesättigten Farben.
      R(ed), Y(ellow), G(reen), C(yan), B(lue), M(agenta) im Bereich +/- 29
    </li>
    <li>
      <code>attr &ltname&gt <b>defaultColor</b> &ltH,S,V&gt</code>
      <p>   
      HSV Angabe der Lichtfarbe die bei "on" gewählt wird. Default ist Weiß.
    </li>
    <li>
      <code>attr &ltname&gt <b>defaultRamp</b> &lt0 bis X&gt</code>
      <p>   
      Zeit in Sekunden. Wenn dieses Attribut gesetzt ist wird implizit immer ein weicher Übergang erzeugt wenn keine Ramp im set angegeben ist. 
    </li>
    <li>
      <code>attr &ltname&gt <b>dimStep</b> &lt0 bis 100&gt</code>
      <p>   
      Wert um den die Helligkeit bei dimUp und dimDown verändert wird. Default 7.
    </li>
    <li>
      <code>attr &ltname&gt <b>gamma</b> &ltX.X&gt</code>
      <p>   
      Das menschliche Auge nimmt Helligkeitsänderungen sehr unterschiedlich wahr (logarithmisch). 
      Bei geringer Ausgangshelligkeit wird schon eine kleine Helligkeitsänderung als sehr stark empfunden und auf der anderen Seite sind bei großer Helligkeit starke Änderungen notwendig.
      Daher ist eine logarithmische Korrektur des Helligkeitsanstiegs der Leuchtmittel erforderlich damit der Anstieg als gleichmäßig empfunden wird.
      Einige controller führen diese Korrektur intern durch. In anderen Fällen ist es notwendig diese Korrektur im Modul zu hinterlegen.
      Ein gamma Wert von 1.0 (default) führt zu einer linearen Ausgabe der Werte. Werte kleiner als 1.0 führen zu einer logarithmischem Korrektur.
    </li>
    <li>
      <code>attr &ltname&gt <b>whitePoint</b> &ltR,G,B&gt</code>
      <p>   
      <a href="#WifiLight_Farbkalibrierung">Farbkalibrierung</a> für RGB gemischtes weißes Licht.
    </li>
    <li>
      <code>attr &ltname&gt <b><a href="#readingFnAttributes">readingFnAttributes</a></b></code>
    </li>
  </ul>
  <p><b>Farbiges Icon für FhemWeb</b>
  <ul>
    <p>
    Um ein farbiges Icon für <a href="#FHEMWEB">FhemWeb</a> zu aktivieren muss das folgende Attribut gesetzt sein:
    <p>
    <li>
      <code>attr &ltname&gt <b>devStateIcon</b> {Color_devStateIcon(ReadingsVal($name,"RGB","000000"))}</code>
    </li>
  </ul>
  <p><b>Colorpicker für FhemWeb</b>
  <ul>
    <p>
    Um den Color-Picker für <a href="#FHEMWEB">FhemWeb</a> zu aktivieren müssen folgende Attribute gesetzt werden:
    <p>
    <li>
      <code>attr &ltname&gt <b>webCmd</b> RGB</code>
    </li>
    <li>
      <code>attr &ltname&gt <b>widgetOverride</b> RGB:colorpicker,RGB</code>
    </li>
  </ul>
</ul>

=end html_DE
