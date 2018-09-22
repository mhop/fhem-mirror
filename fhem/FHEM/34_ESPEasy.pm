################################################################################
#
# $Id$
#
#  34_ESPEasy.pm is a FHEM Perl module to control ESP8266 /w ESPEasy
#
#  Copyright 2018 by dev0
#  FHEM forum: https://forum.fhem.de/index.php?action=profile;u=7465
#
#  This file is part of FHEM.
#
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

package main;

# ------------------------------------------------------------------------------
# required perl/fhem modules
# ------------------------------------------------------------------------------
use strict;
use warnings;
use Data::Dumper;
use MIME::Base64;
use TcpServerUtils;
use HttpUtils;
use Color;
use SetExtensions;

my $module_version      = "2.00";     # Version of this module

# ------------------------------------------------------------------------------
# modul version and required ESP Easy firmware / JSON lib version
# ------------------------------------------------------------------------------
my $minEEBuild          = 128;        # informational
my $minJsonVersion      = 1.02;       # checked in received data

# ------------------------------------------------------------------------------
# default values
# ------------------------------------------------------------------------------
my $d_Interval          = 300;        # interval
my $d_httpReqTimeout    = 10;         # timeout http req
my $d_colorpickerCTww   = 2000;       # color temp for ww (kelvin)
my $d_colorpickerCTcw   = 6000;       # color temp for cw (kelvin)
my $d_maxHttpSessions   = 3;          # concurrent connects to a single esp
my $d_maxQueueSize      = 250;        # max queue size,
my $d_resendFailedCmd   = 0;          # do no00t resend failed http requests
my $d_displayTextEncode = 1;          # urlEncode Text for Displays
my $d_displayTextWidth  = 0;          # display width, 0 => disable formating
my $d_bridgePort        = 8383;       # bridge port if none specified
my $d_disableLogin      = 0;          # Disable login if HTTP Code 302

# ------------------------------------------------------------------------------
# defaults for user defined cmds
# ------------------------------------------------------------------------------
my $d_args   = 0;                     # min number of required arguments
my $d_urlPlg = "/control?cmd=";       # plugin command URL
my $d_urlSys = "/?cmd=";              # system command URL
my $d_widget = "";                    # widget defaults
my $d_usage  = "";                    # usage defaults

# ------------------------------------------------------------------------------
# IP ranges that are allowed to connect to ESPEasy without attr allowedIPs set.
# defined as regexp beause it's quicker than check against IP ranges...
# ------------------------------------------------------------------------------
my $d_allowedIPs = "192.168.0.0/16,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,"
                 . "fe80::/10,fc00::/7,::1";

my $d_localIPs   = "^(127|192.168|172.(1[6-9]|2[0-9]|3[01])|10|169.254)\\.|"
                 . "^(f(e[89ab]|[cd])|::1)";


# ------------------------------------------------------------------------------
# some mappings
# ------------------------------------------------------------------------------
my %ee_map = (
  build => { # ESP Easy build versions
    1  => { type => "ESP Easy",      ver => "STD" },
    17 => { type => "ESP Easy Mega", ver => "STD" },
    33 => { type => "ESP Easy 32",   ver => "STD" },
    65 => { type => "ARDUINO Easy",  ver => "STD" },
    81 => { type => "NANO Easy",     ver => "STD" }
  },
  pins => {  # Arduino pin names, keys must be upper case here
    # ESP82xx / ESP32
    D0 => 16, D1 => 5,  D2 => 4, D3  => 0, D4 => 2, D5 => 14, D6 => 12,
    D7 => 13, D8 => 15, D9 => 3, D10 => 1, RX => 3, TX => 1,  SD2 => 9,  SD3 => 10,
    # ESP32
    TOUCH0 => 4,  TOUCH1 => 0,  TOUCH2 => 21, TOUCH3 => 15, TOUCH4 => 13,
    TOUCH5 => 12, TOUCH6 => 14, TOUCH7 => 27, TOUCH8 => 33, TOUCH9 => 32,
    # ESP32
    ADC1_0 => 36, ADC1_1 => 37, ADC1_2 => 38, ADC1_3 => 39, ADC1_4 => 32,
    ADC1_5 => 33, ADC1_6 => 34, ADC1_7 => 35, ADC2_0 => 4,  ADC2_1 => 0,
    ADC2_2 => 21, ADC2_3 => 15, ADC2_4 => 13, ADC2_5 => 12, ADC2_6 => 14,
    ADC2_7 => 27, ADC2_8 => 25, ADC2_9 => 26
  },
  rst => {                                  # readingSwitchText => {
    10 => {                                 #   vType => {
      1 => { 0 => "off", 1 => "on"  },      #     attr_rst => {org => new, ...},
      2 => { 0 => "on",  1 => "off" }       #     attr_rst => {org => new, ...}
    }                                       #   }
  },
  onOff => {                                # on/off mappings within setFn
    on  => 1,
    off => 0
  }
);

# ------------------------------------------------------------------------------
# get commands
# ------------------------------------------------------------------------------
my %ee_gets = (
  bridge  => {
     queuesize     => {widget => "noArg",  fn => ""},
     queuecontent  => {widget => "",       fn => ""},
     pinmap        => {widget => "noArg",  fn => ""},
     user          => {widget => "noArg",  fn => ""},
     pass          => {widget => "noArg",  fn => ""},
  },
  device  => {
     pinmap        => {widget => "noArg",  fn => ""},
     setcmds       => {widget => "noArg",  fn => ""},
     adminpassword => {widget => "noArg",  fn => ""}
  }
);

# ------------------------------------------------------------------------------
# attributes
# ------------------------------------------------------------------------------
my %ee_attr = (
  all => {
    disable                => { widget => "1,0" },
    disabledForIntervals   => { widget => "" },
    do_not_notify          => { widget => "0,1" },
  },
  bridge => {
    allowedIPs             => { widget => "" },
    authentication         => { widget => "1,0" },
    autocreate             => { widget => "1,0" },
    autosave               => { widget => "1,0" },
    combineDevices         => { widget => "" },
    deniedIPs              => { widget => "" },
    httpReqTimeout         => { widget => "" },
    maxQueueSize           => { widget => "10,25,50,100,250,500,1000,2500,5000,10000,25000,50000,100000" },
    maxHttpSessions        => { widget => "0,1,2,3,4,5,6,7,8,9" },
    resendFailedCmd        => { widget => "" },
  },
  device => {
    adjustValue            => { widget => "" },
    disableRiskyCmds       => { widget => "" },
    displayTextEncode      => { widget => "1,0" },
    displayTextWidth       => { widget => "" },
    IODev                  => { widget => "" },
    Interval               => { widget => "" },
    mapLightCmds           => { widget => "lights,nfx" },
    parseCmdResponse       => { widget => "" },
    pollGPIOs              => { widget => "" },
    presenceCheck          => { widget => "1,0" },
    readingPrefixGPIO      => { widget => "" },
    readingSuffixGPIOState => { widget => "" },
    readingSwitchText      => { widget => "1,0,2" },
    setState               => { widget => "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,25,50,100" },
    userSetCmds            => { widget => "textField-long" },
    useSetExtensions       => { widget => "0,1"},

    rgbGPIOs               => { widget => "" },
    wwcwGPIOs              => { widget => "" },
    colorpicker            => { widget => "RGB,HSV,HSVp" },
  },
#  attr_rgbGPIOs => {
#    colorpicker            => { widget => "RGB,HSV,HSVp" },
#  },
  attr_wwcwGPIOs => {
    colorpickerCTcw        => { widget => "" },
    colorpickerCTww        => { widget => "" },
    ctCW_reducedRange      => { widget => "" },
    ctWW_reducedRange      => { widget => "" },
    wwcwMaxBri             => { widget => "0,1" },
  }
);


# ------------------------------------------------------------------------------
# - get available set cmds based on attributes
# - available cmds can be found in $data{ESPEasy}{device}{sets}...
# - will be called from notifyFN() on INITIALIZED, REREADCFG and some attr changes
# ------------------------------------------------------------------------------
sub ESPEasy_initDevSets($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $subtype = $hash->{SUBTYPE};

  # define colorpickers for use below
  my $cp_pct = "colorpicker,BRI,0,1,100";
  my $cp_bri = "colorpicker,BRI,0,1,255";
  my $cp_ct  = "colorpicker,CT," . AttrVal($name,"ctWW_reducedRange",AttrVal($name,"colorpickerCTww",$d_colorpickerCTww)) . ",10," . AttrVal($name,"ctCW_reducedRange",AttrVal($name,"colorpickerCTcw",$d_colorpickerCTcw));
  my $cp_rgb = "colorpicker,".AttrVal($name,"colorpicker","HSVp");

  my %ee_sets = (
    bridge => { # bridge commands
      user             => { args => 0, url => "",        widget => "",      usage => "<username>" },
      pass             => { args => 0, url => "",        widget => "",      usage => "<password>" },
      clearqueue       => { args => 0, url => "",        widget => "noArg", usage => "" },
    },
    device => { # known ESP Easy plugin commands
      gpio             => { args => 2, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on>" },
      pwm              => { args => 2, url => $d_urlPlg, widget => "",      usage => "<pin> <level>" },
      pwmfade          => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <target> <duration>" },
      pulse            => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on> <duration>" },
      longpulse        => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on> <duration>" },
      longpulse_ms     => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on> <duration>" },
      servo            => { args => 3, url => $d_urlPlg, widget => "",      usage => "<servoNo> <pin> <position>" },
      lcd              => { args => 3, url => $d_urlPlg, widget => "",      usage => "<row> <col> <text>" },
      lcdcmd           => { args => 1, url => $d_urlPlg, widget => "",      usage => "<on|off|clear>" },
      mcpgpio          => { args => 2, url => $d_urlPlg, widget => "",      usage => "<port> <0|1|off|on>" },
      mcppulse         => { args => 3, url => $d_urlPlg, widget => "",      usage => "<port> <0|1|off|on> <duration>" },
      mcplongpulse     => { args => 3, url => $d_urlPlg, widget => "",      usage => "<port> <0|1|off|on> <duration>" },
      oled             => { args => 3, url => $d_urlPlg, widget => "",      usage => "<row> <col> <text>" },
      oledcmd          => { args => 1, url => $d_urlPlg, widget => "",      usage => "<on|off|clear>" },
      pcapwm           => { args => 2, url => $d_urlPlg, widget => "",      usage => "<pin> <Level>" },
      pcfgpio          => { args => 2, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on>" },
      pcfpulse         => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on> <duration>" },
      pcflongpulse     => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <0|1|off|on> <duration>" },
      irsend           => { args => 3, url => $d_urlPlg, widget => "",      usage => "<RAW> <B32 raw code> <frequenz> <pulse length> <blank length> | irsend <NEC|JVC|RC5|RC6|SAMSUNG|SONY|PANASONIC> <code> <bits>" }, #_P035_IRTX.ino
      status           => { args => 2, url => $d_urlPlg, widget => "",      usage => "<device> <pin>" },
      lights           => { args => 1, url => $d_urlPlg, widget => "",      usage => "<rgb|ct|pct|on|off|toggle> [color] [fading time] [pct]" },
      dots             => { args => 1, url => $d_urlPlg, widget => "",      usage => "<params>" },
      tone             => { args => 3, url => $d_urlPlg, widget => "",      usage => "<pin> <freq> <duration>" },
      rtttl            => { args => 1, url => $d_urlPlg, widget => "",      usage => "<RTTTL>" },
      dmx              => { args => 1, url => $d_urlPlg, widget => "",      usage => "<ON|OFF|LOG|value|channel=value[,value][...]>" },
      motorshieldcmd   => { args => 5, url => $d_urlPlg, widget => "",      usage => "<DCMotor|Stepper> <Motornumber> <Forward|Backward|Release> <Speed|Steps> <SINGLE|DOUBLE|INTERLEAVE|MICROSTEP>" },
      candle           => { args => 0, url => $d_urlPlg, widget => "",      usage => ":<FlameType>:<Color>:<Brightness>" },  # params are splited by ":" not " "
      neopixel         => { args => 4, url => $d_urlPlg, widget => "",      usage => "<led_nr> <red 0-255> <green 0-255> <blue 0-255>" },
      neopixelall      => { args => 3, url => $d_urlPlg, widget => "",      usage => "<red 0-255> <green 0-255> <blue 0-255>" },
      neopixelline     => { args => 5, url => $d_urlPlg, widget => "",      usage => "<start_led_nr> <end_led_nr> <red 0-255> <green 0-255> <blue 0-255>" },
      oledframedcmd    => { args => 1, url => $d_urlPlg, widget => "",      usage => "<on|off>" },
      serialsend       => { args => 1, url => $d_urlPlg, widget => "",      usage => "<string>" },  #_P020_Ser2Net.ino
      buzzer           => { args => 0, url => $d_urlPlg, widget => "",      usage => "" },
      inputswitchstate => { args => 0, url => $d_urlPlg, widget => "",      usage => "" },
      nfx              => { args => 1, url => $d_urlPlg, widget => "",      usage => "<off|on|dim|line|one|all|rgb|fade|colorfade|rainbow|kitt|comet|theatre|scan|dualscan|twinkle|twinklefade|sparkle|wipe|fire|stop> <parameter>" },
      event            => { args => 1, url => $d_urlPlg, widget => "",      usage => "<string>" },  #changed url to sys-url;
      # rules related commands
      deepsleep        => { args => 1, url => $d_urlSys, widget => "",      usage => "<duration in s>" },
      publish          => { args => 2, url => $d_urlSys, widget => "",      usage => "<topic> <value>" },
      notify           => { args => 0, url => $d_urlSys, widget => "",      usage => "<notify nr> <message>" },
      reboot           => { args => 0, url => $d_urlSys, widget => "noArg", usage => "" },
      rules            => { args => 1, url => $d_urlSys, widget => "",      usage => "<0|1|off|on>" }, #enable/disable use of rules
      sendto           => { args => 2, url => $d_urlSys, widget => "",      usage => "<unit nr> <command>" },
      sendtohttp       => { args => 3, url => $d_urlSys, widget => "",      usage => "<ip> <port> <url>" },
      sendtoudp        => { args => 3, url => $d_urlSys, widget => "",      usage => "<ip> <port> <url>" },
      taskvalueset     => { args => 3, url => $d_urlSys, widget => "",      usage => "<task/device nr> <value nr> <value/formula>" },
      taskvaluesetandrun => {args=> 3, url => $d_urlSys, widget => "",      usage => "<task/device nr> <value nr> <value/formula>" },
      taskrun          => { args => 1, url => $d_urlSys, widget => "",      usage => "<task/device nr>" },
      timerset         => { args => 2, url => $d_urlSys, widget => "",      usage => "<timer nr> <duration in s>" },
      # dummies
      raw              => { args => 1, url => $d_urlPlg, widget => "",      usage => "<esp_comannd> [args]" },
      rawsystem        => { args => 1, url => $d_urlSys, widget => "",      usage => "<esp_comannd> [args]" },
      # internal cmds
      statusrequest    => { args => 0, url => "",        widget => "noArg", usage => "" },
      adminpassword    => { args => 0, url => "",        widget => "",      usage => "<password>" },
      clearreadings    => { args => 0, url => "",        widget => "noArg", usage => "" },
    },
    system => { # system commands (another url)
      erase            => { args => 0, url => $d_urlSys, widget => "noArg", usage => "" },
      reset            => { args => 0, url => $d_urlSys, widget => "noArg", usage => "" },
      resetflashwritecounter => { args => 0, url => $d_urlSys, widget => "noArg", usage => "" },
    },
    attr_rgbGPIOs => {
      rgb              => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [fadetime] [delay +/-ms]" },
      pct              => { args => 1, url => $d_urlPlg, widget => $cp_pct, usage => "<pct> [fadetime]" },
      on               => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
      off              => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
      toggle           => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
    },
    attr_wwcwGPIOs => {
      pct              => { args => 1, url => $d_urlPlg, widget => $cp_pct, usage => "<pct> [fadetime]" },
      ct               => { args => 1, url => $d_urlPlg, widget => $cp_ct,  usage => "<ct> [fadetime] [pct bri]" },
      on               => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
      off              => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
      toggle           => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
    },
    attr_lights => { # Lights
      rgb              => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [fadetime] [delay +/-ms]" },
      pct              => { args => 1, url => $d_urlPlg, widget => $cp_pct, usage => "<pct> [fadetime]" },
      ct               => { args => 1, url => $d_urlPlg, widget => $cp_ct,  usage => "<ct> [fadetime] [pct bri]" },
      on               => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fadetime]" },
      off              => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fadetime]" },
      toggle           => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fadetime]" },
    },
    attr_nfx => { # nfx commands - Forum #73949
      rgb              => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [fadetime] [delay +/-ms]" },
      pct              => { args => 1, url => $d_urlPlg, widget => $cp_pct, usage => "<pct> [fadetime]" },
      ct               => { args => 1, url => $d_urlPlg, widget => $cp_ct,  usage => "<ct> [fadetime] [pct bri]" },
      on               => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fadetime] [delay +/-ms]" },
      off              => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fadetime] [delay +/-ms]" },
      toggle           => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fadetime]" },
      all              => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [fadetime] [delay +/-ms]" },
      bgcolor          => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb>" },
      colorfade        => { args => 2, url => $d_urlPlg, widget => "",      usage => "<rrggbb_start> <rrggbb_end> [startpixel] [endpixel]" },
      comet            => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [speed +/- 0-50]" },
      dim              => { args => 1, url => $d_urlPlg, widget => $cp_bri, usage => "<value 0-255>" },
      dualscan         => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [rrggbb background] [speed 0-50]" },
      fade             => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [fadetime ms] [delay +/-ms]" },
      fire             => { args => 0, url => $d_urlPlg, widget => "",      usage => "[fps] [brightness 0-255] [cooling 20-100] [sparking 50-200]" },
      kitt             => { args => 1, url => $d_urlPlg, widget => "",      usage => "<rrggbb> [speed 0-50]" },
      line             => { args => 3, url => $d_urlPlg, widget => "",      usage => "<startpixel> <endpixel> <rrggbb>" },
      one              => { args => 2, url => $d_urlPlg, widget => "",      usage => "<pixel> <rrggbb>" },
      scan             => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [rrggbb background] [speed 0-50]" },
      sparkle          => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [rrggbb background] [speed 0-50]" },
      stop             => { args => 0, url => $d_urlPlg, widget => "noArg", usage => "" },
      theatre          => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [rrggbb background] [speed +/- 0-50]" },
      twinkle          => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [rrggbb background] [speed 0-50]" },
      twinklefade      => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [number of pixels] [speed 0-50]" },
      wipe             => { args => 1, url => $d_urlPlg, widget => $cp_rgb, usage => "<rrggbb> [rrggbb dot] [speed +/- 0-50]" },
      faketv           => { args => 0, url => $d_urlPlg, widget => "",      usage => "[startpixel] [endpixel]" },
      simpleclock      => { args => 0, url => $d_urlPlg, widget => "",      usage => "[bigtickcolor] [smalltickcolor] [hourcolor] [minutecolor] [secondcolor]" },
      count            => { args => 1, url => $d_urlPlg, widget => "slider,1,1,50",        usage => "<value>" },
      fadedelay        => { args => 1, url => $d_urlPlg, widget => "slider,-5000,10,5000", usage => "<value in +/-ms>" },
      fadetime         => { args => 1, url => $d_urlPlg, widget => "slider,0,100,10000",   usage => "<value in ms>" },
      rainbow          => { args => 0, url => $d_urlPlg, widget => "slider,-10,1,10",      usage => "[speed +/- 0-50]" },
      speed            => { args => 1, url => $d_urlPlg, widget => "slider,-50,1,50",      usage => "<value 0-50>" },
    }
  ); # hash %ee_sets

  # gather required categories
  my @categories;
  my $mapLightsCmd = lc AttrVal($name,"mapLightCmds",0);
  push (@categories, $subtype);
  if ($subtype eq "device") {
    push (@categories, "system") if !AttrVal("$name","disableRiskyCmds",0);
    push (@categories, "attr_".$mapLightsCmd) if $mapLightsCmd && defined $ee_sets{"attr_$mapLightsCmd"};
    push (@categories, "attr_rgbGPIOs")  if AttrVal("$name","rgbGPIOs",0);
    push (@categories, "attr_wwcwGPIOs") if AttrVal("$name","wwcwGPIOs",0);
  }

  # build hash of avail commands
  # todo: with hashref copy, see https://perlmaven.com/how-to-insert-a-hash-in-another-hash ???
  my %activeSets;
  foreach my $cat (@categories) {
    foreach my $cmd (keys %{ $ee_sets{$cat} } ) {
      $activeSets{$cmd} = $ee_sets{$cat}{$cmd};
    }
  }


  # write all mapped subcms in $hash->{helper}{mapLightCmds}, will be used in SetFn;
  delete $hash->{helper}{mapLightCmds};
  if ($mapLightsCmd) {
    foreach (keys %{$ee_sets{"attr_$mapLightsCmd"}}) {
      $hash->{helper}{mapLightCmds}{$_} = $mapLightsCmd;
    }
  }

  # user cmds/maps
  my $userSetCmds = AttrVal($name,"userSetCmds",0);
  if ($userSetCmds) {
    my %ua = eval($userSetCmds);
    if ($@) {
      Log3 $name, 2, "An error occourred while building user defined cmds/maps: $@";
      return $@;
    }
    foreach my $plugin (keys %ua) {
      my $p = lc($plugin);
      # use reverse order to be sure plugin's url is set before subcmds.
      my @keys = reverse sort keys %{ $ua{$plugin} };
      foreach my $key (@keys) {
        # key is a mapped subcmd
        if ( ref($ua{$plugin}{$key}) eq "HASH" ) {
          foreach my $subcmd (keys %{ $ua{$plugin}{$key} }) {
            my $sc = lc($subcmd);
            $activeSets{$sc} = $ua{$plugin}{$key}{$subcmd};
            # write all mapped subcms in $hash->{helper}{mapLightCmds}, will be used in SetFn;
            $hash->{helper}{mapLightCmds}{$sc} = $p;
            # Set defaults for mapped cmds and be sure all keys are defined in following fns
            $activeSets{$sc}{args}   = $d_args   if !defined $activeSets{$sc}{args};
            $activeSets{$sc}{widget} = $d_widget if !defined $activeSets{$sc}{widget};
            $activeSets{$sc}{usage}  = $d_usage  if !defined $activeSets{$sc}{usage};
            # use plugin's url, if not defined use default
            $activeSets{$sc}{url} = defined $activeSets{$p}{url} ? $activeSets{$p}{url} : $d_urlPlg
              if !defined $activeSets{$sc}{url};
          }
        }
        # key is param for plugin cmd
        else {
          $activeSets{$p}{$key} = $ua{$plugin}{$key};
        }
      }
      # Set defaults for plugin cmds and be sure all keys are defined in following fns
      $activeSets{$p}{args}   = $d_args   if !defined $activeSets{$p}{args};
      $activeSets{$p}{url}    = $d_urlPlg    if !defined $activeSets{$p}{url};
      $activeSets{$p}{widget} = $d_widget if !defined $activeSets{$p}{widget};
      $activeSets{$p}{usage}  = $d_usage  if !defined $activeSets{$p}{usage};
    }
  }

  # add help command
  $activeSets{help} = { args => 1, widget => join(",",sort keys %activeSets), url => "", usage => "<".join(",",sort keys %activeSets).">" };

  # reference to all available cmds
  $data{ESPEasy}{$name}{sets} = \%activeSets;
  Log3 $name, 4, "ESPEasy $name: Available set cmds/maps (re)initialized.";

}


# ------------------------------------------------------------------------------
# enable colorpicker etc. only if attrs (rgb|wwcw)GPIOs|mapLightCmds are set
# called by NotifyFn
# ------------------------------------------------------------------------------
sub ESPEasy_initDevAttrs($) {
  my ($hash) = @_;
  my ($name, $subtype) = ($hash->{NAME}, $hash->{SUBTYPE});

  # add attr_.* categories if corresponding attr is in use
  my @cats = ($subtype, "all");
  foreach (keys %ee_attr) {
    if (m/^attr_(\w+)$/) {
      push(@cats, "attr_".$1) if defined AttrVal($name, $1, undef) || defined AttrVal($name,"mapLightCmds",undef);
    }
  }

  # push attributes from selected categories in array @attrs
  my @attrs;
  foreach my $cat (@cats) {
    foreach my $attr (sort keys %{ $ee_attr{$cat} }) {
      my $w = $ee_attr{$cat}{$attr}{widget};
      # push attrs with corresponding widget
      push(@attrs, $attr . ($w ne "" ? ":$w" : ""));
    }
  }
  push (@attrs, $readingFnAttributes);
  setDevAttrList($name, join(" ", sort @attrs));
  Log3 $name, 4, "ESPEasy $name: Available attributes (re)initialized.";
}


# ------------------------------------------------------------------------------
sub ESPEasy_Initialize($)
{
  my ($hash) = @_;
  #common
  $hash->{DefFn}      = "ESPEasy_Define";
  $hash->{GetFn}      = "ESPEasy_Get";
  $hash->{SetFn}      = "ESPEasy_Set";
  $hash->{AttrFn}     = "ESPEasy_Attr";
  $hash->{UndefFn}    = "ESPEasy_Undef";
  $hash->{ShutdownFn} = "ESPEasy_Shutdown";
  $hash->{DeleteFn}   = "ESPEasy_Delete";
  $hash->{RenameFn}   = "ESPEasy_Rename";
  $hash->{NotifyFn}   = "ESPEasy_Notify";

  #provider
  $hash->{ReadFn}     = "ESPEasy_Read";  # ESP http request will be parsed here
  $hash->{WriteFn}    = "ESPEasy_Write"; # called from logical module's IOWrite
  $hash->{Clients}    = ":ESPEasy:";     # used by dispatch,$hash->{TYPE} of receiver
  my %matchList       = ( "1:ESPEasy" => ".*" );
  $hash->{MatchList}  = \%matchList;

  #consumer
  $hash->{ParseFn}    = "ESPEasy_dispatchParse";
  $hash->{Match}      = ".+";

  # add all attributes to hash, unnecessary attributes will be removed in
  # ESPEasy_initDevAttrs called from NotifyFn
  my @attr;
  foreach my $subtype (keys %ee_attr) {
    foreach my $attr ( keys %{ $ee_attr{$subtype} } ) {
      push (
        @attr, $attr . (
          $ee_attr{$subtype}{$attr}{widget} ne ""
            ?  ":" . $ee_attr{$subtype}{$attr}{widget}
            : ""
          )  # ternary if
      ) # push
    } # foreach $attr
  } # foreach $subtype
  push (@attr, $readingFnAttributes);
  $hash->{AttrList}   = join(" ",sort @attr);

# for the next release...
# $hash->{AttrRenameMap} = { "ctCW_reducedRange" => "ctCWreducedRange",
#                            "ctWW_reducedRange" => "ctWWreducedRange",
#                            "colorpickerCTcw"   => "ctCWColorpicker"
#                            "colorpickerCTww"   => "ctWWcolorpicker"
#                            "wwcwMaxBri"        => "ctMaxBri"
#                          };
}


# ------------------------------------------------------------------------------
sub ESPEasy_Define($$)  # only called when defined, not on reload.
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $usage = "\nUse 'define <name> ESPEasy <bridge> <PORT>"
            . "\nUse 'define <name> ESPEasy <ip|fqdn> <PORT> <IODev> <IDENT>";
  return "Wrong syntax: $usage" if(int(@a) < 3);

  my $name  = $a[0];
  my $type  = $a[1];
  my $host  = $a[2];
  my $port;
  $port = $a[3] if defined $a[3];
  $port = 8383  if !defined $port && $host eq "bridge";
  my $iodev = $a[4] if defined $a[4];
  my $ident = $a[5] if defined $a[5];
  my $ipv = $port =~ m/^IPV6:/ ? 6 : 4;

  return "ERROR: only 1 ESPEasy bridge can be defined!"
    if($host eq "bridge" && $modules{ESPEasy}{defptr}{BRIDGE}{$ipv});
  return "ERROR: missing arguments for subtype device: $usage"
    if ($host ne "bridge" && !(defined $a[4]) && !(defined $a[5]));
  return "ERROR: too much arguments for a bridge: $usage"
    if ($host eq "bridge" && defined $a[4]);

  (ESPEasy_isIPv4($host) || ESPEasy_isFqdn($host) || $host eq "bridge")
    ? $hash->{HOST} = $host
    : return "ERROR: invalid IPv4 address, fqdn or keyword bridge: '$host'";

  # check fhem.pl version (req. setDevAttrList Forum # 85868, 86010)
  AttrVal('global','version','') =~ m/^fhem.pl:(\d+)\/.*$/;
  return "ERROR: fhem.pl is too old to use $type module. "
        ."Version 16453/2018-03-21 is required at least."
    if (not(defined $1) || $1 < 16453);

  $hash->{PORT}      = $port if defined $port;
  $hash->{IDENT}     = $ident if defined $ident;
  $hash->{VERSION}   = $module_version;
  $hash->{NOTIFYDEV} = "global";

  #--- BRIDGE -------------------------------------------------
  if ($hash->{HOST} eq "bridge") {
    $hash->{SUBTYPE} = "bridge";
    $hash->{IPV} = $ipv;
    $modules{ESPEasy}{defptr}{BRIDGE}{$ipv} = $hash;
    Log3 $hash->{NAME}, 2, "$type $name: Opening bridge v$module_version [TCP:".($ipv==4?"IPV4:":"")."$port]";
    ESPEasy_tcpServerOpen($hash);
    if ($init_done && !defined($hash->{OLDDEF})) {
      CommandAttr(undef,"$name room $type");
      CommandAttr(undef,"$name group $type Bridge");
      CommandAttr(undef,"$name authentication 0");
      CommandAttr(undef,"$name combineDevices 0");
    }
    $hash->{".bau"} = getKeyValue($type."_".$name."-user");
    $hash->{".bap"} = getKeyValue($type."_".$name."-pass");
    # only informational
    $hash->{MAX_HTTP_SESSIONS} = $d_maxHttpSessions;
    $hash->{MAX_QUEUE_SIZE}    = $d_maxQueueSize;

    # Check OS IPv6 support
    if ($ipv == 6) {
      use constant HAS_AF_INET6 => defined eval { Socket::AF_INET6() };
      Log3 $name, 2, "$type $name: WARNING: Your system seems to have no IPv6 support." if !HAS_AF_INET6;
    }
  }

  #--- DEVICE -------------------------------------------------
  else {
    $hash->{INTERVAL} = $d_Interval;
    $hash->{SUBTYPE} = "device";
    $hash->{sec}{admpwd} = getKeyValue($type."_".$name."-admpwd");
    AssignIoPort($hash,$iodev) if !defined $hash->{IODev};
    InternalTimer(gettimeofday()+5+rand(5), "ESPEasy_statusRequest", $hash);
    readingsSingleUpdate($hash, 'state', 'opened',1);
    my $io = (defined($hash->{IODev}{NAME})) ? $hash->{IODev}{NAME} : "none";
    Log3 $hash->{NAME}, 4, "$type $name: Opened for $ident $host:$port using bridge $io";
  }

  ESPEasy_initDevSets($hash);
  ESPEasy_loadRequiredModules($hash);
  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_Get(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  return "argument is missing" if !$cmd;
  my $subtype = $hash->{SUBTYPE};
  $cmd = lc $cmd;
  my $ret;

  if( !grep( m/^$cmd$/, keys %{ $ee_gets{$subtype} } ) || $cmd eq "?") {
    my @clist;
    foreach my $c ( sort keys %{ $ee_gets{$subtype} } ) {
      my $w = $ee_gets{$subtype}{$c}{widget} ? ":".$ee_gets{$subtype}{$c}{widget} : "";
      push(@clist, $c.$w);
    }
    return "Unknown argument $cmd, choose one of ". join(" ",@clist);
  }

  # lookup sub fn to be executed or use "ESPEasy_Get_$cmd"
  my $fn = $ee_gets{$subtype}{$cmd}{fn};
  $fn = $fn ne "" ? $fn : "ESPEasy_Get_$cmd";
  # exec $fn
  return &{\&{ $fn }}(@_);
}


# ------------------------------------------------------------------------------
# GetFn subs, called by reference to $cmd name or global $gets{$cmd}{fn}
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# get username or password that is being used
# ------------------------------------------------------------------------------
sub ESPEasy_Get_user(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  return defined $hash->{".bau"} ? $hash->{".bau"} : "username is not defined, yet.";
}

# ------------------------------------------------------------------------------
# get username or password that is being used
# ------------------------------------------------------------------------------
sub ESPEasy_Get_pass(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  return defined $hash->{".bap"} ? $hash->{".bap"} : "password is not defined, yet.";
}

# ------------------------------------------------------------------------------
# get arduino pin mappings that can be used
# ------------------------------------------------------------------------------
sub ESPEasy_Get_adminpassword(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  return defined $hash->{sec}{admpwd} ? $hash->{sec}{admpwd} : "password is not defined, yet.";
}

# ------------------------------------------------------------------------------
# get formated list of available commands
# ------------------------------------------------------------------------------
sub ESPEasy_Get_setcmds(@)
{
  my ($hash) = @_;
  my ($type, $name) = ($hash->{TYPE}, $hash->{NAME});

  my ($args, $url, $widget, $usage);
  my $line = "-" x 79 . "\n";
  $line .= "plugin / mapped cmd  |mapped to plugin |args|url           |widget            |\n";
  $line .= "-" x 79 . "\n";

  foreach my $cmd (sort keys %{ $data{$type}{$name}{sets} }) {
    next if $cmd =~ m/^(help|clearreadings|statusrequest)$/;
    my $plugin = defined $hash->{helper}{mapLightCmds}{$cmd} ? $hash->{helper}{mapLightCmds}{$cmd} : "-";
    $line .= substr( $cmd    . " " x (21 - length($cmd))    ,0,21 ) ."|";
    $line .= substr( $plugin . " " x (17 - length($plugin)) ,0,17 ) ."|";
    my $c = $data{$type}{$name}{sets}{$cmd}; # just a little bit shorter...
    $line .= substr( $c->{args}   . " " x(4  - length($c->{args}))   ,0,4  ) ."|";
    $line .= substr( $c->{url}    . " " x(14 - length($c->{url}))    ,0,14 ) ."|";
    $line .= substr( $c->{widget} . " " x(18 - length($c->{widget})) ,0,18 ) ."|\n";
  }

  # replace lace braces for FHEMWEB
  if ($hash->{CL}{TYPE} eq "FHEMWEB") {
    $line =~ s/</&lt;/g;
    $line =~ s/>/&gt;/g;
  }
    return $line;
}

# ------------------------------------------------------------------------------
# get arduino pin mappings that can be used
# ------------------------------------------------------------------------------
sub ESPEasy_Get_pinmap(@)
{
  my $ret .= "\nAlias   => GPIO\n";
  $ret .= "---------------\n";
  foreach (sort keys %{$ee_map{pins}}) {
    $ret .= $_." " x (8-length $_ ) ."=> $ee_map{pins}{$_}\n";
  }
  return $ret;
}

# ------------------------------------------------------------------------------
# simple get queue sizes
# ------------------------------------------------------------------------------
sub ESPEasy_Get_queuesize(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $ret;
  foreach (keys %{ $hash->{helper}{queue} }) {
    $ret .= "$_:".scalar @{$hash->{helper}{queue}{"$_"}}." ";
  }
  return $ret ? $ret : "No queues in use.";
}

# ------------------------------------------------------------------------------
# get queue content of all/selected queues
# ------------------------------------------------------------------------------
sub ESPEasy_Get_queuecontent(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $host = $args[0];
  my $ret; my $i = 0; my $j = 0;
  my $mseclog = AttrVal("global","mseclog",0);

  if (defined $hash->{helper}{queue}) {
    my $Xspace = " "x ($mseclog ? 20 : 16);                 # different spacer if attr/global/mseclog
    my $Xdash  = ("-"x80)."\n";                             # just a few dashes;
    foreach my $q (sort keys %{ $hash->{helper}{queue} }) {
      next if $host ne "" && $q !~ m/^$host$/;
      $ret .= "\nQueue for host $q:\n";
      $ret .= $Xdash."Time:".$Xspace."Cmd:\n".$Xdash;       # queue title
      $i = 0;
      foreach my $qe  (@{ $hash->{helper}{queue}{$q} }) {
        my ($s,$ms) = split(/\./,$qe->{ts});                # get secs + mSecs, see WriteFn
        my $ts = FmtDateTime($s);                           # format time string as FHEM does
        $ts .= sprintf(".%03d", $ms/1000) if $mseclog;      # add .msecs if attr/global/mseclog
        $ret .= $ts ."  " .$qe->{cmd} ." " .join(",",@{$qe->{cmdArgs}})."\n";
        $i++                                                # single queue counter
      }
      $ret .= "=> $i entries\n";                            # single queue counter
      $j += $i;                                             # add single counter to overall counter
    }
  }
  return $ret ? $ret."\n==> Number of all requested queue entries: $j entries"
              : "No specified queues active.";
}


# ------------------------------------------------------------------------------
sub ESPEasy_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;
  return if (IsDisabled $name);
  my $type = $hash->{TYPE};

  # case insensitive
  $cmd = lc($cmd) if $cmd;

  # get current cmd list if cmd is __unknown__
  my $clist = ESPEasy_isCmdAvailable($hash,$cmd);
  if (defined $clist) {
    if (AttrVal($name,"useSetExtensions",0)) {
      Log3 $name, 3, "$type $name: set $name $cmd ".join(" ",@params)." (use set extensions)"
        if $cmd =~ m/^(o(n|ff)-(for-timer|till(-overnight)?)|blink|intervals|toggle)$/ ;
      return SetExtensions($hash, $clist, $name, $cmd, @params);
    }
    my $err = "Unknown argument $cmd, choose one of $clist";
    return "Unknown argument $cmd, choose one of $clist";
  }

  SetExtensionsCancel($hash); # Forum #53137

  # Log set command
  Log3 $name, 3, "$type $name: set $name $cmd ".join(" ",@params) if $cmd !~  m/^(\?|user|pass|help)$/;

  # check if there are all required arguments
  my $set = $data{ESPEasy}{$name}{sets}{$cmd};
  if($set->{args} && scalar @params < $set->{args}) {
    Log3 $name, 2, "$type $name: Missing argument: 'set $name $cmd ".join(" ",@params)."'" if $cmd ne "help";
    return "Missing argument: $cmd needs at least $set->{args} argument" . ($set->{args} < 2 ? "" : "s")."\n"
         . "Usage: 'set $name $cmd $set->{usage}'";
  }

  if ($cmd eq "help") {
    my $usage = $data{ESPEasy}{$name}{sets}{$params[0]}{usage};
    return $usage ? "Usage: set $name $params[0] $usage"
                  : "Note: '$params[0]' is not registered as an ESPEasy command. "
                  . "See attribute userSetCmds to register your own or unsupported commands.";
  }

  # Internal cmds
  elsif ($cmd =~ m/^clearqueue$/i) {
    delete $hash->{helper}{queue};
    Log3 $name, 3, "$type $name: Queues erased.";
    return undef;
  }
  elsif ($cmd =~ m/^user|pass$/ ) {
    setKeyValue($hash->{TYPE}."_".$hash->{NAME}."-".$cmd,$params[0]);
    $cmd eq "user" ? $hash->{".bau"} = $params[0] : $hash->{".bap"} = $params[0];
  }
  return undef if $hash->{SUBTYPE} eq "bridge";

  # Device cmds
  if ($cmd eq "statusrequest") {
    ESPEasy_statusRequest($hash);
    return undef;
  }
  elsif ($cmd eq "clearreadings") {
    ESPEasy_clearReadings($hash);
    return undef;
  }
  elsif ($cmd =~ m/^adminpassword$/ ) {
    setKeyValue($hash->{TYPE}."_".$hash->{NAME}."-admpwd", $params[0]);
    $hash->{sec}{admpwd} = $params[0];
    return undef;
  }

  # urlEncode <text> parameter
  @params = ESPEasy_urlEncodeDisplayText($hash,$cmd,@params);

  # pin mapping (eg. D8 -> 15), <pin> parameter
  my $pp = ESPEasy_paramPos($hash,$cmd,'<pin>');
  if ($pp && $params[$pp-1] =~ m/^[a-zA-Z]/) {
    Log3 $name, 5, "$type $name: Pin mapping ". uc $params[$pp-1] .
                   " => ".$ee_map{pins}{uc $params[$pp-1]};
    $params[$pp-1] = $ee_map{pins}{uc $params[$pp-1]};
  }

  # onOff mapping (on/off -> 1/0), <0|1|off|on> parameter
  $pp = ESPEasy_paramPos($hash,$cmd,'<0|1|off|on>');
  if ($pp) {
    my $ooArg = lc($params[$pp-1]);
    my $ooVal = defined $ee_map{onOff}{$ooArg} ? $ee_map{onOff}{$ooArg} : undef;
    if (defined $ooVal) {
      Log3 $name, 5, "$type $name: onOff mapping ". $params[$pp-1]." => $ooVal";
      $params[$pp-1] = $ooVal;
    }
  }

  # re-map cmds if necessary
  if (defined $hash->{helper}{mapLightCmds} && defined $hash->{helper}{mapLightCmds}{$cmd}) {
    unshift @params, $cmd;
    $cmd = $hash->{helper}{mapLightCmds}{$cmd};
  }
  # special handling for attrs wwcwGPIOs & rgbGPIOs
  else {
    # enable ct|pct commands if attr wwcwGPIOs is set
    if (AttrVal($name,"wwcwGPIOs",0) && $cmd =~ m/^(ct|pct)$/i) {
      my $ret = ESPEasy_setCT($hash,$cmd,@params);
      return $ret if ($ret);
    }
    # enable rgb related commands if attr rgbGPIOs is set
    if (AttrVal($name,"rgbGPIOs",0) && $cmd =~ m/^(rgb|on|off|toggle)$/i) {
      my $ret = ESPEasy_setRGB($hash,$cmd,@params);
      return $ret if ($ret);
    }
  }

  # Log device set cmd with all mappings
  Log3 $name, 5, "$type $name: set $name $cmd ".join(" ",@params). " (mappings done)"
    if $cmd !~  m/^(\?|user|pass|help)$/;
  Log3 $name, 5, "$type $name: IOWrite ( \$defs{$name}, \$defs{$name}, $cmd, (\"".join("\",\"",@params)."\") )";
  Log3 $name, 2, "$type $name: Device seems to be in sleep mode, sending command nevertheless."
    if (defined $hash->{SLEEP} && $hash->{SLEEP} ne "0");

  # send cmd with required args to IO Device
  my $parseCmd = ESPEasy_isParseCmd($hash,$cmd); # should response be parsed and dispatched
  IOWrite($hash, $hash, $parseCmd, $cmd, @params);
  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_Read($) {

  my ($hash) = @_;                             #hash of temporary child instance
  my $name   = $hash->{NAME};
  my $ipv = $hash->{IPV} ? $hash->{IPV} : ($hash->{PEER} =~ m/:/ ? 6 : 4);
  my $bhash  = $modules{ESPEasy}{defptr}{BRIDGE}{$ipv}; #hash of original instance
  my $bname  = $bhash->{NAME};
  my $btype  = $bhash->{TYPE};

  # Levering new TcpServerUtils security feature.
  # $attr{$name}{allowfrom} = ".*" if !$attr{$name}{allowfrom};
  # Accept and create a child
  if( $hash->{SERVERSOCKET} ) {
    my $aRet = ESPEasy_TcpServer_Accept($hash,"ESPEasy");
    return;
  }

  # use received IP instead of configured one (NAT/PAT could have modified)
  my $peer = $hash->{PEER};

  # Read max 9000 bytes, return num of read bytes
  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 9000); # accept jumbo frames

  # Delete temporary device
  if( !defined($ret ) || $ret <= 0 ) {
    CommandDelete( undef, $hash->{NAME} );
    return;
  }

  return if (IsDisabled $bname);

  # Check allowed IPs
  if ( !( ESPEasy_isPeerAllowed($peer,AttrVal($bname,"allowedIPs", $d_allowedIPs)) &&
         !ESPEasy_isPeerAllowed($peer,AttrVal($bname,"deniedIPs",0)) ) ) {
    Log3 $bname, 2, "$btype $name: Peer address rejected";
    return;
  }
  Log3 $bname, 4, "$btype $name: Peer address $peer accepted";

  # check content-length header (Forum #87607)
  $hash->{PARTIAL} .= $buf;
  my @data = split( '\R\R', $hash->{PARTIAL} );
  (my $ldata = $hash->{PARTIAL}) =~ s/Authorization: Basic [\w=]+/Authorization: Basic *****/;
  if(scalar @data < 2) { #header not complete
    Log3 $bname, 5, "$btype $name: Incomplete or no header, awaiting more data: \n$ldata";
    #start timer
    return;
  }
  my $header = ESPEasy_header2Hash($data[0]);
  if(!defined $header->{"Content-Length"}) {
    Log3 $bname, 2, "$btype $name: Missing content-length header: \n$ldata";
    ESPEasy_sendHttpClose($hash,"400 Bad Request","");
    #delete temp bridge device
    return;
  }
  my $len = length($data[1]);
  if($header->{"Content-Length"} > $len) {
    Log3 $bname, 5, "$btype $name: Received content too small, awaiting more content: $header->{'Content-Length'}:$len \n$ldata";
    #start timer
    return;
  }
  elsif($header->{"Content-Length"} < $len) {
    Log3 $bname, 2, "$btype $name: Received content too large, skip processing data: $header->{'Content-Length'}:$len \n$ldata";
    ESPEasy_sendHttpClose($hash,"400 Bad Request","");
    #delete temp bridge device
    return;
  }
  Log3 $name, 4, "$btype $name: Received content length ok";

  # mask password in authorization header with ****
  my $logHeader = { %$header };

  # public IPs
  if (!defined $logHeader->{Authorization} && $peer !~ m/$d_localIPs/) {
    Log3 $bname, 2, "$btype $name: No basic auth set while using a public IP "
                  . "address. $peer rejected.";
    return;
  }

  $logHeader->{Authorization} =~ s/Basic\s.*\s/Basic ***** / if defined $logHeader->{Authorization};
  # Dump logHeader
  Log3 $bname, 5, "$btype $name: Received header: ".ESPEasy_dumpSingleLine($logHeader)
    if (defined $logHeader);
  # Dump content
  Log3 $bname, 5, "$btype $name: Received content: $data[1]" if defined $data[1];

  # check authorization
  if (!defined ESPEasy_isAuthenticated($hash,$header->{Authorization})) {
    ESPEasy_sendHttpClose($hash,"401 Unauthorized","");
    return;
  }

  # No error occurred, send http respose OK to ESP
  ESPEasy_sendHttpClose($hash,"200 OK",""); #if !grep(/"sleep":1/, $data[1]);

  # JSON received...
  my $json;
  if (defined $data[1] && $data[1] =~ m/"module":"ESPEasy"/) {

    # perl module JSON not installed
    if ( !$bhash->{helper}{pm}{JSON} ) {
      Log3 $bname, 2, "$btype $bname: Perl module 'JSON' is not installed. Can't process received data from $peer.";
      return;
    }

    # use encode_utf8 if available else replace any disturbing chars
    $bhash->{helper}{pm}{Encode}
      ? ( eval { $json = decode_json( encode_utf8($data[1]) ); 1; } )
      : ( eval { $json = decode_json( $data[1] =~ s/[^\x20-\x7E]/_/gr ); 1; } );
    if ($@) {
      Log3 $bname, 2, "$btype $name: WARNING: Invalid JSON received. "
                    . "Check your ESP configuration ($peer).\n$@";
      return;
    }

    # check that ESPEasy software is new enough
    return if ESPEasy_checkVersion($bhash,$peer,$json->{data}{ESP}{build},$json->{version});

    # should never happen, but who knows what some JSON module versions do...
    $json->{data}{ESP}{name} = "" if !defined $json->{data}{ESP}{name};
    $json->{data}{SENSOR}{0}{deviceName} = "" if !defined $json->{data}{SENSOR}{0}{deviceName};

    # remove illegal chars from ESP name for further processing and assign to new var
    (my $espName = $json->{data}{ESP}{name}) =~ s/[^A-Za-z\d_\.]/_/g;
    (my $espDevName = $json->{data}{SENSOR}{0}{deviceName}) =~ s/[^A-Za-z\d_\.]/_/g;

    # check that 'ESP name' or 'device name' is set
    if ($espName eq "" && $espDevName eq "") {
      Log3 $bname, 2, "$btype $name: WARNIING 'ESP name' and 'device name' "
                     ."missing ($peer). Check your ESP config. Skip processing data.";
      Log3 $bname, 2, "$btype $name: Data: $data[1]";
      return;
    }

    my $cd = ESPEasy_isCombineDevices($peer,$espName,AttrVal($bname,"combineDevices",0));
    my $ident = $cd
      ? $espName ne "" ? $espName : $peer
      : $espName.($espName ne "" && $espDevName ne "" ? "_" : "").$espDevName;

    my $d0;
    Log3 $bname, 4, "$btype $name: Src:'$json->{data}{ESP}{name}'/'"
                  . (!defined $json->{data}{SENSOR}{0}{deviceName} || $json->{data}{SENSOR}{0}{deviceName} eq ""
                    ? "<undefined>"
                    : $json->{data}{SENSOR}{0}{deviceName} )
                  ."' => ident:$ident dev:"
                  . ( ($d0=(devspec2array("i:IDENT=$ident:FILTER=i:TYPE=$btype"))[0])
                    ? $d0
                    : "<undefined>" )
                  . " combinedDevice:".$cd;

    # push internals in @values
    my @values;
    my @intVals = qw(unit sleep build build_git build_notes version node_type_id);
    foreach my $intVal (@intVals) {
      next if !defined $json->{data}{ESP}{$intVal} || $json->{data}{ESP}{$intVal} eq "";
      push(@values,"i||".$intVal."||".$json->{data}{ESP}{$intVal}."||0");
    }

    # push sensor value in @values
    foreach my $vKey (keys %{$json->{data}{SENSOR}}) {
      if(ref $json->{data}{SENSOR}{$vKey} eq ref {}
      && exists $json->{data}{SENSOR}{$vKey}{value}) {
        # remove illegal chars
        $json->{data}{SENSOR}{$vKey}{valueName} =~ s/[^A-Za-z\d_\.\-\/]/_/g;
        my $dmsg = "r||".$json->{data}{SENSOR}{$vKey}{valueName}
                   ."||".$json->{data}{SENSOR}{$vKey}{value}
                   ."||".$json->{data}{SENSOR}{$vKey}{type};
        if ($dmsg =~ m/(\|\|\|\|)|(\|\|$)/) { #detect an empty value
          Log3 $bname, 2, "$btype $name: WARNING: value name or value is "
                         ."missing ($peer). Skip processing this value.";
          Log3 $bname, 2, "$btype $name: Data: $data[1]";
          next; #skip further processing for this value only
        }
        push(@values,$dmsg);
      }
    }

    ESPEasy_dispatch($hash,$ident,$peer,@values);

  } #$data[1] =~ m/"module":"ESPEasy"/

  else {
    Log3 $bname, 2, "$btype $name: WARNING: Wrong controller configured or "
                   ."ESPEasy Version is too old.";
    Log3 $bname, 2, "$btype $name: WARNING: ESPEasy version R"
                   .$minEEBuild." or later required.";
  }

  # session will not be close immediately if ESP goes to sleep after http send
  # needs further investigation?
  if ($hash->{TEMPORARY} && $json->{data}{ESP}{sleep}) {
    CommandDelete(undef, $name);
  }
  return;
}


# ------------------------------------------------------------------------------
sub ESPEasy_Write($$$@) #called from logical's IOWrite (end of SetFn)
{
  my ($hash,$dhash,$parseCmd,$cmd,@params) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  my ($dname,$dtype) = ($dhash->{NAME},$dhash->{TYPE});

  if ($cmd eq "cleanup") {
    delete $hash->{helper}{received};
    return undef;
  }

  elsif ($cmd eq "statusrequest") {
    ESPEasy_statusRequest($hash);
    return undef;
  }
  my $retry = 0;

  # a hash is more easy to handle in the following subs...
  my $cmdHash = {
    name      => $dhash->{NAME},
    ident     => $dhash->{IDENT},
    port      => $dhash->{PORT},
    host      => $dhash->{HOST},
    parseCmd  => $parseCmd,
    retry     => 0,
    cmd       => $cmd,
    cmdArgs   => [ @params ],
    ts        => ESPEasy_timeStamp(),
    authRetry => 0,
    admpwd    => $dhash->{sec}{admpwd},
  };

  ESPEasy_httpReq($hash, $cmdHash);
}


# ------------------------------------------------------------------------------
# Global events only ( $hash->{NOTIFYDEV}=global )
# ------------------------------------------------------------------------------
sub ESPEasy_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  return if(!grep(m/^(DELETE)?ATTR $name |^INITIALIZED$|^REREADCFG$|^DEFINED/, @{$dev->{CHANGED}}));

  foreach (@{$dev->{CHANGED}}) {
   if (m/^(DELETE)?ATTR ($name) (\w+)\s?(.*)?$/s) {  # /s is important multiline attrs like userSetCmds, ...
      Log3 $name, 5, "$type $name: received event: $_";

      if ($3 eq "disable") {
        if (defined $1 || (defined $4 && $4 eq "0")) {
          Log3 $name, 4,"$type $name: Device enabled";
          ESPEasy_resetTimer($hash) if ($hash->{SUBTYPE} eq "device");
          readingsSingleUpdate($hash, 'state', 'opened',1);
        }
        else {
          Log3 $name, 3,"$type $name: Device disabled";
          ESPEasy_clearReadings($hash) if $hash->{SUBTYPE} eq "device";
          ESPEasy_resetTimer($hash,"stop");
          readingsSingleUpdate($hash, "state", "disabled",1)
        }
      }

      elsif ($3 eq "Interval") {
        if (defined $1) {
          $hash->{INTERVAL} = $d_Interval;
        }
        elsif (defined $4 && $4 eq "0") {
          $hash->{INTERVAL} = "disabled";
          ESPEasy_resetTimer($hash,"stop");
          CommandDeleteReading(undef, "$name presence")
            if defined $hash->{READINGS}{presence};
        }
        else { # Interval > 0
          $hash->{INTERVAL} = $4;
          ESPEasy_resetTimer($hash);
        }
      }

      elsif ($3 eq "setState") {
        if (defined $1 || (defined $4 && $4 > 0)) {
          ESPEasy_setState($hash);
        }
        else { #setState == 0
          CommandSetReading(undef,"$name state opened");
        }
      }

      elsif ($3 =~ /^(mapLightCmds)$/) {
        ESPEasy_initDevSets($hash);
        ESPEasy_initDevAttrs($hash);
      }

      elsif ($3 =~ /^(rgbGPIOs|wwcwGPIOs)$/) {
        ESPEasy_initDevAttrs($hash);
      }

      elsif ($3 =~ /^(mapLightCmds|colorpicker(CT[cw]w)?|ct[CW]W_reducedRange|disableRiskyCmds|userSetCmds|userSetMaps|userSets)$/) {
        ESPEasy_initDevSets($hash);
      }

      else {
        #Log 5, "$type $name: Attribute $3 not handeled by NotifyFn ";
      }

    } # if (m/^(DELETE)?ATTR ($name) (\w+)\s?(.*)?$/s)

    elsif (m/^(INITIALIZED|REREADCFG)$/) {
      ESPEasy_initDevSets($hash);
      ESPEasy_initDevAttrs($hash);
    }

    elsif (m/^DEFINED (.*)/ && $name eq $1) { # manual defined while runtime
      ESPEasy_initDevSets($hash);
      ESPEasy_initDevAttrs($hash);
    }

    else { #should never be reached
      #Log 5, "$type $name: WARNING: unexpected event received by NotifyFn: $_";
    }
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_Rename() {
  my ($new,$old) = @_;
  my $i = 0;
  my $type    = $defs{"$new"}->{TYPE};
  my $name    = $defs{"$new"}->{NAME};
  my $subtype = $defs{"$new"}->{SUBTYPE};
  my @am;

  # copy values from old to new device
  setKeyValue($type."_".$new."-user",getKeyValue($type."_".$old."-user"));
  setKeyValue($type."_".$new."-pass",getKeyValue($type."_".$old."-pass"));
  setKeyValue($type."_".$new."-admpwd",getKeyValue($type."_".$old."-admpwd"));
  # delete old entries
  setKeyValue($type."_".$old."-user",undef);
  setKeyValue($type."_".$old."-pass",undef);
  setKeyValue($type."_".$old."-firstrun",undef);
  setKeyValue($type."_".$old."-admpwd",undef);

  # sets/maps
  $data{$type}{$new} = $data{$type}{$old};
  delete $data{$type}{$old};

  # replace IDENT in devices if bridge name changed
  if ($subtype eq "bridge") {
    foreach my $ldev (devspec2array("TYPE=$type")) {
      my $dhash = $defs{$ldev};
      my $dsubtype = $dhash->{SUBTYPE};
      next if ($dsubtype eq "bridge");
      my $dname = $dhash->{NAME};
      my $ddef  = $dhash->{DEF};
      my $oddef = $dhash->{DEF};
      $ddef =~ s/ $old / $new /;
      if ($oddef ne $ddef){
        $i = $i+2;
        CommandModify(undef, "$dname $ddef");
        CommandAttr(undef,"$dname IODev $new");
        push (@am,$dname);
      }
    }
  }
  Log3 $name, 2, "$type $name: Device $old renamed to $new";
  Log3 $name, 2, "$type $name: Attribute IODev set to '$name' in these "
                ."devices: ".join(", ",@am) if $subtype eq "bridge";

  if (AttrVal($name,"autosave",AttrVal("global","autosave",1)) && $i>0) {
    CommandSave(undef,undef);
    Log3 $type, 2, "$type $name: $i structural changes saved "
                  ."(autosave is enabled)";
  }
  elsif ($i>0) {
    Log3 $type, 2, "$type $name: There are $i structural changes. "
                  ."Don't forget to save chages.";
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my ($type, $subtype) = ($hash->{TYPE}, $hash->{SUBTYPE});
  my $revSubType = $subtype eq "bridge" ? "device" : "bridge";
  my $ret;

  if ($cmd eq "set" && !defined $aVal) {
    Log3 $name, 2, "$type $name: attr $name $aName '': value must not be empty";
    return "$name: attr $aName: value must not be empty";
  }

  elsif ($aName eq "readingSwitchText") {
    $ret = "0,1,2" if ($cmd eq "set" && not $aVal =~ m/^(0|1|2)$/)
  }

  elsif ($aName eq "combineDevices") {
    $ret = "0 | 1 | ESPname | ip[/netmask][,ip[/netmask]][,...]"
      if $cmd eq "set" && !(ESPEasy_isAttrCombineDevices($aVal) || $aVal =~ m/^[01]$/ )
  }

  elsif ($aName =~ m/^(allowedIPs|deniedIPs)$/) {
    $ret = "[comma separated list of] ip[/netmask] or a regexp"
      if $cmd eq "set" && !ESPEasy_isIPv64Range($aVal,"regexp")
  }

  elsif ($aName =~ m/^(pollGPIOs|rgbGPIOs|wwcwGPIOs)$/) {
    $ret = "GPIO_No[,GPIO_No][...]"
      if $cmd eq "set" && $aVal !~ m/^[a-zA-Z]{0,2}[0-9]+(,[a-zA-Z]{0,2}[0-9]+)*$/
  }

  elsif ($aName eq "colorpicker") {
    $ret = "RGB | HSV | HSVp"
      if ($cmd eq "set" && not $aVal =~ m/^(RGB|HSV|HSVp)$/)
  }

  elsif ($aName =~ m/^(colorpickerCTww|colorpickerCTcw)$/) {
    $ret = "1000..10000"
      if $cmd eq "set" && ($aVal < 1000 || $aVal > 10000)
  }

  elsif ($aName eq "parseCmdResponse") {
    my $cmds = lc join("|",keys %{ $data{ESPEasy}{$name}{sets} });
    $ret = "cmd[,cmd][...] #cmd must be a registered ESPEasy cmd"
      if $init_done && $cmd eq "set" && lc($aVal) !~ m/^($cmds){1}(,($cmds))*$/
  }

  elsif ($aName eq "mapLightCmds") {
    my $cmds = lc join("|",keys %{ $data{ESPEasy}{$name}{sets} });
    $ret = "ESPEasy cmd"
      if $init_done && $cmd eq "set" && lc($aVal) !~ m/^($cmds){1}(,($cmds))*$/}

  elsif ($aName =~ m/^(setState|resendFailedCmd)$/) {
    $ret = "integer"
      if ($cmd eq "set" && not $aVal =~ m/^(\d+)$/)}

  elsif ($aName eq "displayTextWidth") {
    $ret = "number of charaters per line"
      if ($cmd eq "set" && not $aVal =~ m/^(\d+)$/)}

  elsif ($aName eq "readingPrefixGPIO") {
    $ret = "[a-zA-Z0-9._-/]+"
      if ($cmd eq "set" && $aVal !~ m/^[A-Za-z\d_\.\-\/]+$/)}

  elsif ($aName eq "readingSuffixGPIOState") {
    $ret = "[a-zA-Z0-9._-/]+"
      if ($cmd eq "set" && $aVal !~ m/^[A-Za-z\d_\.\-\/]+$/)}

  elsif ($aName eq "httpReqTimeout") {
    $ret = "3..60 (default: $d_httpReqTimeout)"
      if $cmd eq "set" && ($aVal < 3 || $aVal > 60)}

  elsif ($aName eq "maxHttpSessions") {
    ($cmd eq "set" && ($aVal !~ m/^[0-9]+$/))
    ? ($ret = ">= 0 (default: $d_maxHttpSessions, 0: disable queuing)")
    : ($hash->{MAX_HTTP_SESSIONS} = $aVal);
    if ($cmd eq "del") {$hash->{MAX_HTTP_SESSIONS} = $d_maxHttpSessions}
  }

  elsif ($aName eq "maxQueueSize") {
    ($cmd eq "set" && ($aVal !~ m/^[1-9][0-9]+$/))
    ? ($ret = ">=10 (default: $d_maxQueueSize)")
    : ($hash->{MAX_QUEUE_SIZE} = $aVal);
    if ($cmd eq "del") {$hash->{MAX_QUEUE_SIZE} = $d_maxQueueSize}
  }

  elsif ($aName eq "Interval") {
    ($cmd eq "set" && ($aVal !~ m/^(\d)+$/ || $aVal <10 && $aVal !=0))
      ? ($ret = "0 or >=10")
      : ($hash->{INTERVAL} = $aVal)
  }

  elsif ($aName eq "userSetCmds") {
    $ret = ESPEasy_Attr_userSetCmds($hash, $cmd, $aName, $aVal);
    $ret = "a perl hash. See command reference for details.\n\n"
         . "Error: ".chomp($ret)
         . "\n\nExample:\n"
         . "(\n"
         ." plugin_X => { cmd_1 => {}, cmd_2 => {} },\n"
         ." plugin_Y => {\n"
           ."  rgb => { args => 1, url => \"/myUrl\", widget => \"colorpicker,RGB\",              usage => \"<rrggbb> [fadetime]\" },\n"
           ."  ct  => { args => 1, url => \"/myUrl\", widget => \"colorpicker,CT,2000,100,4500\", usage => \"<colortemp>\" }\n"
        ." }\n"
        .")\n"
    if $ret;
  }

  if (!$init_done) {
    if ($aName =~ /^disable$/ && $aVal == 1) {
      readingsSingleUpdate($hash, "state", "disabled",1);
    }
  }

  if (defined $ret) {
    return "$name: Attribut '$aName' must be: $ret";
  }

  return undef;
}


# ------------------------------------------------------------------------------
# check attr userSetCmds | userSetMaps
# ------------------------------------------------------------------------------
sub ESPEasy_Attr_userSetCmds(@) {
  my ($hash, $cmd, $aName, $aVal) = @_;
  my %user;
  my $ret;

  if ($cmd eq "set") {

    my %ua = eval($aVal);
    return $@ if $@;

    foreach my $plugin (keys %ua) {
      foreach my $key ( keys %{ $ua{$plugin} } ) {
        return "Unknown key '$key' in $plugin => { $key => ... }" if ($key !~ m/^(args|url|widget|usage|cmds)$/);
        next if $key =~ m/^(args|url|widget|usage)$/ && !ref($ua{$plugin}{$key});
        if ($key eq "cmds") {
          if (ref($ua{$plugin}{$key}) eq "HASH") {
            foreach my $subcmd (keys %{ $ua{$plugin}{$key} }) {
              foreach my $subkey (keys %{ $ua{$plugin}{$key}{$subcmd} }) {
                my $where = "$plugin => { $key => { $subcmd => { $subkey => ... } } }";
                return "Unknown key '$subkey' in $where. Mistyped?" if ($subkey !~ m/^(args|url|widget|usage)$/);
                return "Value of '$subkey' in $where must be a string."  if ref($ua{$plugin}{$key}{$subcmd}{$subkey});
              }
            }
          }
          else {
            return "Value of key '$key' in $plugin => { $key => ... } must be a hash.";
          }
        } # key eq "cmds"
      } # foreach key
    } # foreach plugin
  } # set attr

  # Delete Attribute, afterwards notifyFn will build new cmdhash in $data{ESPEasy}{$name}{sets}...
  else {
    # do nothing
  }

  # eval() above accepts single string expressions...
  my $reHash = '\s*\w+\s*=>\s*\{.*}\s*,*\s*';
  return "Wrong Syntax: '$aVal'" if $aVal !~ m/^\s*\($reHash(,$reHash)*\)\s*$/s;

  return undef;
}


# ------------------------------------------------------------------------------
#UndefFn: called while deleting device (delete-command) or while rereadcfg
sub ESPEasy_Undef($$)
{
  my ($hash, $arg) = @_;
  my ($name,$type,$port) = ($hash->{NAME},$hash->{TYPE},$hash->{PORT});

  # close server and return if it is a child process for incoming http requests
  if (defined $hash->{TEMPORARY} && $hash->{TEMPORARY} == 1) {
    my $ipv = $hash->{PEER} =~ m/:/ ? 6 : 4;
    my $bhash = $modules{ESPEasy}{defptr}{BRIDGE}{$ipv};
    Log3 $bhash->{NAME}, 4, "$type $name: Closing tcp session.";
    TcpServer_Close($hash);
    return undef
  };

  HttpUtils_Close($hash);
  RemoveInternalTimer($hash);

  if($hash->{SUBTYPE} && $hash->{SUBTYPE} eq "bridge") {
    my $ipv = $hash->{IPV};
    delete $modules{ESPEasy}{defptr}{BRIDGE}{$ipv}
      if(defined($modules{ESPEasy}{defptr}{BRIDGE}{$ipv}));
    TcpServer_Close( $hash );
    Log3 $name, 2, "$type $name: Socket on port tcp/$port closed";
  }
  else {
    IOWrite($hash, $hash, undef, "cleanup", undef );
  }

  return undef;
}


# ------------------------------------------------------------------------------
#ShutdownFn: called before fhem's shutdown command
sub ESPEasy_Shutdown($)
{
  my ($hash) = @_;
  HttpUtils_Close($hash);
  Log3 $hash->{NAME}, 4, "$hash->{TYPE} $hash->{NAME}: Shutdown requested";
  return undef;
}


# ------------------------------------------------------------------------------
#DeleteFn: called while deleting device (delete-command) but after UndefFn
sub ESPEasy_Delete($$)
{
  my ($hash, $arg) = @_;
  my ($name, $type) = ($hash->{NAME}, $hash->{TYPE});

  # return if it is a child process for incoming http requests
  if (!defined $hash->{TEMPORARY}) {
    setKeyValue($type."_".$name."-user",undef);
    setKeyValue($type."_".$name."-pass",undef);
    setKeyValue($type."_".$name."-firstrun",undef);
    setKeyValue($type."_".$name."-admpwd",undef);
    delete $data{$type}{$name};

    Log3 $hash->{NAME}, 4, "$type $name: $hash->{NAME} deleted";
  }
  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_dispatch($$$@) #called by bridge -> send to logical devices
{
  my($hash,$ident,$host,@values) = @_;
  my $name = $hash->{NAME};
  return if (IsDisabled $name);

  my $type = $hash->{TYPE};
  my $ipv  = $host =~ m/:/ ? 6 : 4;
  my $bhash = $modules{ESPEasy}{defptr}{BRIDGE}{$ipv};
  my $bname = $bhash->{NAME};

  my $ui = 1; #can be removed later
  my $as = (AttrVal($bname,"autosave",AttrVal("global","autosave",1))) ? 1 : 0;
  my $ac = (AttrVal($bname,"autocreate",AttrVal("global","autoload_undefined_devices",1))) ? 1 : 0;
  my $msg = $ident."::".$host."::".$ac."::".$as."::".$ui."::".join("|||",@values);

#  Log3 $bname, 5, "$type $name: Dispatch: $msg";
  Dispatch($bhash, $msg, undef);

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_dispatchParse($$$) # called by logical device (defined by
{                              # $hash->{ParseFn})
  # we are called from dispatch() from the ESPEasy bridge device
  # we never come here if $msg does not match $hash->{MATCH} in the first place
  my ($IOhash, $msg) = @_;   # IOhash points to the ESPEasy bridge, not device
  my $IOname = $IOhash->{NAME};
  my $type   = $IOhash->{TYPE};

  # 1:ident 2:ip 3:autocreate 4:autosave 5:uniqIDs 6:value(s)
  my ($ident,$ip,$ac,$as,$ui,$v) = split("::",$msg);
  return "" if !$ident || $ident eq "";

  my $name;
  my @v = split("\\|\\|\\|",$v);

  # look in each $defs{$d}{IDENT} for $ident to get device name.
  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "ESPEasy");
    if (InternalVal($defs{$d}{NAME},"IDENT","") eq "$ident") {
      $name = $defs{$d}{NAME} ;
      last;
    }
  }

  # autocreate device if no device has $ident asigned.
  if (!($name) && $ac eq "1") {
    $name = ESPEasy_autocreate($IOhash,$ident,$ip,$as);
    # cleanup helper
    delete $IOhash->{helper}{autocreate}{$ident}
      if defined $IOhash->{helper}{autocreate}{$ident};
    delete $IOhash->{helper}{autocreate}
      if scalar keys %{$IOhash->{helper}{autocreate}} == 0;
  }
  # autocreate is disabled
  elsif (!($name) && $ac eq "0") {
    Log3 $IOname, 2, "$type $IOname: autocreate is disabled (ident: $ident)"
      if not defined $IOhash->{helper}{autocreate}{$ident};
    $IOhash->{helper}{autocreate}{$ident} = "disabled";
    return $ident;
  }

  return $name if (IsDisabled $name);
  my $hash = $defs{$name};

  Log3 $name, 5, "$type $name: Received: $msg";

  if (defined $hash && $hash->{TYPE} eq "ESPEasy" && $hash->{SUBTYPE} eq "device") {
    my @logInternals;
    foreach (@v) {
      my ($cmd,$reading,$value,$vType) = split("\\|\\|",$_);

      # reading prefix replacement (useful if we poll values)
      my $replace = '"'.AttrVal($name,"readingPrefixGPIO","GPIO").'"';
      $reading =~ s/^GPIO/$replace/ee;

      # --- setReading ----------------------------------------------
      if ($cmd eq "r") {
        # reading suffix replacement only for setreading
        $replace = '"'.AttrVal($name,"readingSuffixGPIOState","").'"';
        $reading =~ s/_state$/$replace/ee;

        # map value to on/off if device is a switch
        my $rst = AttrVal($name,"readingSwitchText",1);
        $value = $ee_map{rst}{$vType}{$rst}{$value}
          if defined $ee_map{rst}{$vType} && defined $ee_map{rst}{$vType}{$rst}
          && defined $ee_map{rst}{$vType}{$rst}{$value}
          && !AttrVal($name,"rgbGPIOs",0);  # special treatment if attr rgbGPIOs is set

        # delete ignored reading and helper
        if (defined ReadingsVal($name,".ignored_$reading",undef)) {
          delete $hash->{READINGS}{".ignored_$reading"};
          delete $hash->{helper}{received}{".ignored_$reading"};
        }

        # delete warning if there is any (send from httpRequestParse before)
        if (exists ($hash->{"WARNING"})) {
          if (defined $hash->{"WARNING"}) {
            Log3 $name, 2, "$type $name: RESOLVED: ".$hash->{"WARNING"};
          }
          delete $hash->{"WARNING"};
        }

        # attr adjustValue
        my $orgVal = $value;
        $value = ESPEasy_adjustValue($hash,$reading,$value);
        if (!defined $value) {
          Log3 $name, 4, "$type $name: $reading: $orgVal [ignored]";
          $reading = ".ignored_$reading";
          $value = $orgVal;
        }

        readingsSingleUpdate($hash, $reading, $value, 1);
        my $adj = ($orgVal ne $value) ? " [adjusted]" : "";
        Log3 $name, 4, "$type $name: $reading: $value".$adj
          if defined $value && $reading !~ m/^\./; #no leading dot

        # used for presence detection
        $hash->{helper}{received}{$reading} = time();

        # recalc RGB reading if a PWM channel has changed
        if (AttrVal($name,"rgbGPIOs",0) && $reading =~ m/\d$/i) {
          my ($r,$g,$b) = ESPEasy_gpio2RGB($hash);
          if (($r ne "" && uc ReadingsVal($name,"rgb","") ne uc $r.$g.$b)  ) {
            readingsSingleUpdate($hash, "rgb", $r.$g.$b, 1);
          }
        }

      }

      # --- Internals -----------------------------------------------
      elsif ($cmd eq "i") {
        # add human readable text to node_type_id
        $value .= defined $ee_map{build}{$value}{type}
          ? ": " . $ee_map{build}{$value}{type}
          : ": unknown node type id"
            if $reading eq "node_type_id";

        # no value given
        $value = "<undefined>" if !defined $value || $value eq "";

        # set internal
        $hash->{"ESP_".uc($reading)} = $value;

        # add to log
        push(@logInternals,"$reading:$value");
      }

      # --- Error ---------------------------------------------------
      elsif ($cmd eq "e") {
        if (!defined $hash->{"WARNING"} || $hash->{"WARNING"} ne $value) {
          Log3 $name, 2, "$type $name: WARNING: $value";
          $hash->{"WARNING"} = $value;
          # CommandTrigger(undef, "$name ....");
        }
        #readingsSingleUpdate($hash, $reading, $value, 1);
      }

      # --- Notice (just log) ---------------------------------------
      elsif ($cmd eq "n") {
        Log3 $name, $vType, "$type $name: $reading: $value";
      }

      # --- DeleteReading -------------------------------------------
      elsif ($cmd eq "dr") {
        CommandDeleteReading(undef, "$name $reading");
        Log3 $name, 4, "$type $name: Reading $reading deleted";
      }

      else {
        Log3 $name, 2, "$type $name: Unknown internal command code received via dispatch. Report to maintainer, please.";
      }
    } # foreach @v

    Log3 $name, 5, "$type $name: Internals: ".join(" ",@logInternals)
      if scalar @logInternals > 0;

    ESPEasy_checkPresence($hash) if ReadingsVal($name,"presence","") ne "present";
    ESPEasy_setState($hash);

  }

  else { #autocreate failed
    Log3 undef, 2, "ESPEasy: Device $name not defined";
  }

  return $name;  # must be != undef. else msg will processed further -> help me!
}


# ------------------------------------------------------------------------------
sub ESPEasy_autocreate($$$$)
{
  my ($IOhash,$ident,$ip,$autosave) = @_;
  my $IOname = $IOhash->{NAME};
  my $IOtype = $IOhash->{TYPE};

  my $devname = "ESPEasy_".$ident;
  my $define  = "$devname ESPEasy $ip 80 $IOhash->{NAME} $ident";
  Log3 undef, 2, "$IOtype $IOname: Autocreate $define";

  my $cmdret= CommandDefine(undef,$define);
  if(!$cmdret) {
    $cmdret= CommandAttr(undef, "$devname room $IOhash->{TYPE}");
    $cmdret= CommandAttr(undef, "$devname group $IOhash->{TYPE} Device");
    $cmdret= CommandAttr(undef, "$devname setState 3");
    $cmdret= CommandAttr(undef, "$devname Interval $d_Interval");
    $cmdret= CommandAttr(undef, "$devname presenceCheck 1");
    $cmdret= CommandAttr(undef, "$devname readingSwitchText 1");
    if (AttrVal($IOname,"autosave",AttrVal("global","autosave",1))) {
      CommandSave(undef,undef);
      Log3 undef, 2, "$IOtype $IOname: Structural changes saved.";
    }
    else {
      Log3 undef, 2, "$IOtype $IOname: Autosave is disabled: "
                    ."Do not forget to save changes.";
    }
  }
  else {
    Log3 undef, 1, "$IOtype $IOname: WARNING: an error occurred "
                  ."while creating device for $ident: $cmdret";
  }

  return $devname;
}


# ------------------------------------------------------------------------------
sub ESPEasy_httpReq(@)
{
  my ($hash, $cmdHash) = @_;
  my ($name, $type) = ($hash->{NAME},$hash->{TYPE});

  my ($host, $port, $ident, $dname) = ($cmdHash->{host}, $cmdHash->{port}, $cmdHash->{ident}, $cmdHash->{name});
  my ($cmd, @cmdArgs) = ($cmdHash->{cmd}, @{$cmdHash->{cmdArgs}}) ;
  my $url;

  # queue http requests or continue if there are no queued cmds
  return undef if ESPEasy_httpReqQueue($hash, $cmdHash);

  $cmdHash->{retry}++;

  $hash->{helper}{sessions}{$host}++;                  # increment http session counter
  my $path = $data{ESPEasy}{$dname}{sets}{$cmd}{url};  # build http url

  # raw/rawsystem is used for commands not implemented right now
  if ($cmd =~ m/^raw|rawsystem$/) {
    $cmd = $cmdArgs[0];
    splice(@cmdArgs,0,1);
  }

  if (defined $cmdHash->{dologin} && $cmdHash->{dologin} == 1) {
    $url = "http://$host:$port/login?password=$cmdHash->{admpwd}";
  }
  else {
    my $plist = join(",",@cmdArgs);    # join cmd params into a string to be used in http url
    $plist = ",".$plist if @cmdArgs;   # add leading comma if defined
    $url = "http://".$host.":".$port.$path.$cmd.$plist; # build full url
  }

  my $httpParams = {
    url             => $url,
    timeout         => AttrVal($name,"httpReqTimeout",$d_httpReqTimeout),
    keepalive       => 0,
    httpversion     => "1.0",
    hideurl         => ($url =~ m/password/ ? 1 : 0),
    method          => "GET",
    ignoreredirects => 1,
    callback        =>  \&ESPEasy_httpReqParse,
    hash            => $hash,    # pass throght to ESPEasy_httpReqParse()
    cmdHash         => $cmdHash  # pass throght to ESPEasy_httpReqParse()
  };
  (my $logUrl = $url) =~ s/password=.*/password=*****/;
  Log3 $name, 4, "$type $name: httpReq device:$dname ident:$ident timeout:$httpParams->{timeout} url:$logUrl" if ($cmd !~ m/^(status)/);

  HttpUtils_NonblockingGet($httpParams);
  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_httpReqParse($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});

  my $cmdHash = $param->{cmdHash};
  my ($host, $ident, $dname)   = ($cmdHash->{host},  $cmdHash->{ident},    $cmdHash->{name});
  my ($retry, $parseCmd, $cmd) = ($cmdHash->{retry}, $cmdHash->{parseCmd}, $cmdHash->{cmd});
  my ($port, $pass)            = ($cmdHash->{port},  $cmdHash->{admpwd});

  my @cmdArgs = @{ $cmdHash->{cmdArgs} };   # used for queueing
  my $plist   = join(",",@cmdArgs);         # used in Log entries
  my @values;

  # command queue
  $hash->{helper}{sessions}{$host}--;

  if ($err ne "") {
    push(@values, "e||_lastError||$err||0"); # dispatch $err to logical device
    $hash->{"WARNING_$host"} = $err;        # keep in helper for support reason

    #Log3 $name, 2, "$type $name: httpReq failed: $host $ident '$cmd $plist' ";
    #Log3 $name, 2, "$type $name: set $dname $cmd". ($plist ne "" ?" $plist": "")." failed: $err" ;
    Log3 $name, 2, "$type $name: $err [set $dname $cmd". ($plist ne ""?" $plist":"") ."]";

    # unshift command back to queue (resend) if retry not reached
    my $maxRetry = AttrVal($name,"resendFailedCmd",$d_resendFailedCmd);
    if ($retry <= $maxRetry && $hash->{MAX_HTTP_SESSIONS} ) {
      unshift @{$hash->{helper}{queue}{$host}}, $cmdHash;
      Log3 $name, 4, "$type $name: Requeuing: $host $ident '$cmd $plist' (".scalar @{$hash->{helper}{queue}{$host}}.")";
    }
  }

  # ESPEasy's firmware command is unknown
  elsif ($data =~ m/^(Unknown or restricted command)!/) {
    my $n = $1. ": '" .($cmd !~m/^raw(system)?/ ? $cmd : $cmdArgs[0]). "'";
    push(@values, "n||Warning||$n||3");
  }

  # Authorization not send or failed.
  elsif ($data =~ m/^(HTTP\/1.1 302)\s?\r\nLocation: \/login/s) {
    if (!defined $pass || $pass eq "") {
      my $n = "Command \'$cmd\' requires authentication but no adminpassword ist set.";
      push(@values, "n||Warning||$n||2");
    }
    else {
      # queue command, send credentials
      if ($cmdHash->{authRetry} == 0) {
        my $n = "Wrong URL or authorization required for \'$cmd $plist\'. Queueing command, sending credentials first.";
        push(@values, "n||Notice||$n||4");
        $cmdHash->{authRetry} = 1;
        unshift @{$hash->{helper}{queue}{$host}}, $cmdHash;
        my $loginHash = {
          name      => $dname, ident  => $ident, port    => $port,  host    => $host,
          parseCmd  => 1,      retry  => 0,      cmd     => $cmd,   cmdArgs => [ ],
          authRetry => 0,      admpwd => $pass,  dologin => 1,      ts      => ESPEasy_timeStamp()
        };
        unshift @{$hash->{helper}{queue}{$host}}, $loginHash;
      }
      # credentials send but still 302...
      else {
        my $n = "Authorization failed. Discarding command \'$cmd $plist\'.";
        push(@values, "n||Error||$n||2");
      }
    }
  }

  # check that response from cmd should be parsed (client attr parseCmdResponse)
  elsif ($data ne "" && !$parseCmd) {
    ESPEasy_httpReqDequeue($hash, $host);
    return undef;
  }

  elsif ($data ne "") { # no error occurred
    # command queue
    delete $hash->{"WARNING_$host"};

    (my $logData = $data) =~ s/\n//sg;
    Log3 $name, 5, "$type $name: http response for ident:$ident cmd:'$cmd,$plist' => '$logData'";

    # This json data are response from plugin. Lights and nfx plugin use it.
    # Also status command (polling) send infos that will be evaluate (deprecated)
    if ($data =~ m/^\{/) { #it could be json...
      my $res;

      # return here if PM JSON is not installed.
      if ( !$hash->{helper}{pm}{JSON} ) {
        Log3 $name, 2, "$type $name: Perl module JSON missing, can't process data.";
        return undef;
      }

      $hash->{helper}{pm}{Encode} # use encode_utf8 if available else replace any disturbing chars
        ? ( eval { $res = decode_json( encode_utf8($data) ); 1; } )
        : ( eval { $res = decode_json( $data =~ s/[^\x20-\x7E]/_/gr ); 1; } );

      # is there an json decode error?
      if ($@) {
        Log3 $name, 2, "$type $name: WARNING: deformed JSON data received from $host requested by $ident.";
        Log3 $name, 2, "$type $name: $@";
        push(@values, "n||Error||$@||2");
      }

      # json decode worked fine...
      else {
        # maps plugin type (answer for set state/gpio) to SENSOR_TYPE_SWITCH (vType:10)
        my $vType = (defined $res->{plugin} && $res->{plugin} eq "1") ? "10" : "0";

        # Plugins lights:123 nfx:124
        if (defined $res->{plugin} && $res->{plugin} =~ m/^(123|124)$/) {
          foreach my $key (keys %{ $res }) {
            push @values, "r||$key||".$res->{$key}."||".$vType
              if $res->{$key} ne "" && $key ne "plugin";
          }
        }

        # all other plugins...
        else {
          push @values, "r||GPIO".$res->{pin}."_mode||".$res->{mode}."||".$vType;
          push @values, "r||GPIO".$res->{pin}."_state||".$res->{state}."||".$vType;
          push @values, "r||_lastAction||".$res->{log}."||".$vType if $res->{log} ne "";
        }

      } # json decode worked fine...
    } #if ($data =~ m/^\{/)

    # no json returned => unknown state
    else {
      Log3 $name, 5, "$type $name: No json fmt: ident:$ident $cmd $plist => $data";
      if (defined $param->{cmd} && $param->{cmd} eq "status" && defined $param->{plist} && $param->{plist} =~ m/^gpio,(\d+)$/i) {
        # push values/cmds in @values
        if (defined $1) {
          push @values, "r||GPIO".$1."_mode||"."?"."||0";
          push @values, "r||GPIO".$1."_state||".$data."||0";
        }
      }
    }

  } # ($data ne "")

  else {
  }

  ESPEasy_dispatch($hash,$ident,$host,@values);
  ESPEasy_httpReqDequeue($hash, $host);
  return undef;
}


# ------------------------------------------------------------------------------
# Queue cmd if max_sessions reached and queueSize is not reached,
# else discard cmd
# ------------------------------------------------------------------------------
sub ESPEasy_httpReqQueue(@)
{
  my ($hash, $cmdHash) = @_;
  my ($name, $type) = ($hash->{NAME}, $hash->{TYPE});
  my $cmd = $cmdHash->{cmd};
  my @cmdArgs = @{ $cmdHash->{cmdArgs} };
  my $cmdArgs = join(",",@cmdArgs);
  my $host = $cmdHash->{host};
  my $queueSize =  defined $hash->{helper}{queue} && defined $hash->{helper}{queue}{$host}
                ? scalar @{$hash->{helper}{queue}{$host}} : 0;

  $hash->{helper}{sessions}{$host} = 0 if !defined $hash->{helper}{sessions}{$host};
  # is queueing enabled?
  if ($hash->{MAX_HTTP_SESSIONS}) {
    # do queueing if max sessions are already in use
    if ($hash->{helper}{sessions}{$host} >= $hash->{MAX_HTTP_SESSIONS} ) {
      # max queue size reached
      if ($queueSize < $hash->{MAX_QUEUE_SIZE}) {
        push(@{$hash->{helper}{queue}{$host}}, $cmdHash);
        Log3 $name, 4, "$type $name: Queuing: $host $cmdHash->{ident} '$cmd $cmdArgs' ($queueSize)";
        return 1;
      }
      else {
        Log3 $name, 2, "$type $name: set $cmd $cmdArgs (skipped due to queue size exceeded: $hash->{MAX_QUEUE_SIZE})";
        return 1;
      }
    }
  }

  return 0;
}


# ------------------------------------------------------------------------------
# De-Queue set cmds and delete $hash->{helper}{queue}.. if empty
# ------------------------------------------------------------------------------
sub ESPEasy_httpReqDequeue($$)
{
  my ($hash,$host) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});

  if ( defined $hash->{helper}{queue}
  &&   defined $hash->{helper}{queue}{$host}
  &&   scalar @{$hash->{helper}{queue}{$host}} ) {

    my $cmdHash = shift @{ $hash->{helper}{queue}{$host} };

    Log3 $name, 4, "$type $name: Dequeuing: $host $cmdHash->{ident} "
                 . "'$cmdHash->{cmd} " . join(",",@{$cmdHash->{cmdArgs}})."'"
                 . " (".scalar @{$hash->{helper}{queue}{$host}}.")";

    # delete queue if empty
    delete $hash->{helper}{queue}{$host} if defined $hash->{helper}{queue} && defined $hash->{helper}{queue}{$host} && scalar @{$hash->{helper}{queue}{$host}} == 0;
    delete $hash->{helper}{queue} if defined $hash->{helper}{queue} && scalar keys %{ $hash->{helper}{queue} } == 0;

    ESPEasy_httpReq($hash, $cmdHash);
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_statusRequest($) #called by device
{
  my ($hash) = @_;
  my ($name, $type) = ($hash->{NAME},$hash->{TYPE});

  unless (IsDisabled $name) {
    Log3 $name, 4, "$type $name: set statusRequest";
    ESPEasy_pollGPIOs($hash);
    ESPEasy_checkPresence($hash);
    ESPEasy_setState($hash);
  }
  ESPEasy_resetTimer($hash);
  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_pollGPIOs($) #called by device
{
  my ($hash) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  my $sleep = $hash->{SLEEP};
  my $a = AttrVal($name,'pollGPIOs',undef);

  if (!defined $a) {
    # do nothing, just return
  }
  elsif (defined $sleep && $sleep eq "1") {
    Log3 $name, 2, "$type $name: Polling of GPIOs is not possible as long as deep sleep mode is active.";
  }

  else {
    my @gpios = split(",",$a);
    foreach my $gpio (@gpios) {
      if ($gpio =~ m/^[a-zA-Z]/) { # pin mapping (eg. D8 -> 15)
        Log3 $name, 5, "$type $name: Pin mapping ".uc $gpio." => $ee_map{pins}{uc $gpio}";
        $gpio = $ee_map{pins}{uc $gpio};
      }
      Log3 $name, 5, "$type $name: IOWrite(\$defs{$name}, $hash, 1, status, gpio,".$gpio.")";
      IOWrite($hash, $hash, 1, "status", "gpio,".$gpio);
    }
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_resetTimer($;$)
{
  my ($hash,$sig) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  $sig = "" if !$sig;

  if ($init_done == 1) {
    RemoveInternalTimer($hash, "ESPEasy_statusRequest");
  }

  if ($sig eq "stop") {
    Log3 $name, 5, "$type $name: internalTimer stopped";
    return undef;
  }
  return undef if AttrVal($name,"Interval",$d_Interval) == 0;

  unless(IsDisabled($name)) {
    my $s  = AttrVal($name,"Interval",$d_Interval) + rand(5);
    my $ts = $s + gettimeofday();
    Log3 $name, 5, "$type $name: Start internalTimer +".int($s)." => ".FmtDateTime($ts);
    InternalTimer($ts, "ESPEasy_statusRequest", $hash);
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_tcpServerOpen($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $port = ($hash->{PORT}) ? $hash->{PORT} : 8383;

  my $ret = TcpServer_Open( $hash, $port, "global" );
  exit(1) if ($ret && !$init_done);
  readingsSingleUpdate($hash, "state", "initialized", 1 );

  return $ret;
}


# ------------------------------------------------------------------------------
# Duplicated sub from TcpServerUtils as a workaround for new security feature:
# https://forum.fhem.de/index.php/topic,72717.0.html
sub ESPEasy_TcpServer_Accept($$)
{
  my ($hash, $type) = @_;

  my $name = $hash->{NAME};
  my @clientinfo = $hash->{SERVERSOCKET}->accept();
  if(!@clientinfo) {
    Log3 $name, 1, "Accept failed ($name: $!)" if($! != EAGAIN);
    return undef;
  }
  $hash->{CONNECTS}++;

  my ($port, $iaddr) = $hash->{IPV6} ?
      sockaddr_in6($clientinfo[1]) :
      sockaddr_in($clientinfo[1]);
  my $caddr = $hash->{IPV6} ?
                inet_ntop(AF_INET6(), $iaddr) :
                inet_ntoa($iaddr);

# ------------------------------------------------------------------------------
# Removed from sub because we have our own access control system that works in
# a more readable and flexible way (network ranges with allow/deny and regexps).
# Our new allowed ranges default are also now:
# 127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fc00::/7,fe80::/10,::1
# ------------------------------------------------------------------------------
#
#  my $af = $attr{$name}{allowfrom};
#  if(!$af) {
#    my $re = "^(127|192.168|172.(1[6-9]|2[0-9]|3[01])|10|169.254)\\.|".
#             "^(fe[89ab]|::1)";
#    if($caddr !~ m/$re/) {
#      my %empty;
#      $hash->{SNAME} = $hash->{NAME};
#      my $auth = Authenticate($hash, \%empty);
#      delete $hash->{SNAME};
#      if($auth == 0) {
#        Log3 $name, 1,
#             "Connection refused from the non-local address $caddr:$port, ".
#             "as there is no working allowed instance defined for it";
#        close($clientinfo[0]);
#        return undef;
#      }
#    }
#  }
#
#  if($af) {
#    if($caddr !~ m/$af/) {
#      my $hostname = gethostbyaddr($iaddr, AF_INET);
#      if(!$hostname || $hostname !~ m/$af/) {
#        Log3 $name, 1, "Connection refused from $caddr:$port";
#        close($clientinfo[0]);
#        return undef;
#      }
#    }
#  }

  #$clientinfo[0]->blocking(0);  # Forum #24799

  if($hash->{SSL}) {
    # Forum #27565: SSLv23:!SSLv3:!SSLv2', #35004: TLSv12:!SSLv3
    my $sslVersion = AttrVal($hash->{NAME}, "sslVersion",
                     AttrVal("global", "sslVersion", "TLSv12:!SSLv3"));

    # Certs directory must be in the modpath, i.e. at the same level as the
    # FHEM directory
    my $mp = AttrVal("global", "modpath", ".");
    my $ret = IO::Socket::SSL->start_SSL($clientinfo[0], {
      SSL_server    => 1,
      SSL_key_file  => "$mp/certs/server-key.pem",
      SSL_cert_file => "$mp/certs/server-cert.pem",
      SSL_version => $sslVersion,
      SSL_cipher_list => 'HIGH:!RC4:!eNULL:!aNULL',
      Timeout       => 4,
      });
    my $err = $!;
    if( !$ret
      && $err != EWOULDBLOCK
      && $err ne "Socket is not connected") {
      $err = "" if(!$err);
      $err .= " ".($SSL_ERROR ? $SSL_ERROR : IO::Socket::SSL::errstr());
      Log3 $name, 1, "$type SSL/HTTPS error: $err"
        if($err !~ m/error:00000000:lib.0.:func.0.:reason.0./); #Forum 56364
      close($clientinfo[0]);
      return undef;
    }
  }

  my $cname = "${name}_${caddr}_${port}";
  my %nhash;
  $nhash{NR}    = $devcount++;
  $nhash{NAME}  = $cname;
  $nhash{PEER}  = $caddr;
  $nhash{PORT}  = $port;
  $nhash{FD}    = $clientinfo[0]->fileno();
  $nhash{CD}    = $clientinfo[0];     # sysread / close won't work on fileno
  $nhash{TYPE}  = $type;
  $nhash{SSL}   = $hash->{SSL};
  $nhash{STATE} = "Connected";
  $nhash{SNAME} = $name;
  $nhash{TEMPORARY} = 1;              # Don't want to save it
  $nhash{BUF}   = "";
  $attr{$cname}{room} = "hidden";
  $defs{$cname} = \%nhash;
  $selectlist{$nhash{NAME}} = \%nhash;

  my $ret = $clientinfo[0]->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1);

  Log3 $name, 4, "Connection accepted from $nhash{NAME}";
  return \%nhash;
}


# ------------------------------------------------------------------------------
sub ESPEasy_header2Hash($) {
  my ($string) = @_;
  my %header = ();

  foreach my $line (split("\r\n", $string)) {
    my ($key,$value) = split(": ", $line,2);
    next if !$value;

    $value =~ s/^ //;
    $header{$key} = $value;
  }

  return \%header;
}


# ------------------------------------------------------------------------------
sub ESPEasy_isCmdAvailable($$@)
{
  my ($hash,$cmd) = @_;
  my $name = $hash->{NAME};
  if (!defined $data{ESPEasy}{$name}{sets}{$cmd}) {
    my $clist;
    foreach my $c (sort keys %{ $data{ESPEasy}{$name}{sets} } ) {
      $clist .= $c . ($data{ESPEasy}{$name}{sets}{$c}{widget} eq ""
        ? " " : ":$data{ESPEasy}{$name}{sets}{$c}{widget} ");
    }

    return $clist;
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_isParseCmd($$) #called by device
{
  my ($hash,$cmd) = @_;
  my $name = $hash->{NAME};
  my $doParse = 0;

  my @cmds = split(",",AttrVal($name,"parseCmdResponse","status"));
  foreach (@cmds) {
    if (lc($_) eq lc($cmd)) {
      $doParse = 1;
      last;
    }
  }
  return $doParse;
}


# ------------------------------------------------------------------------------
sub ESPEasy_sendHttpClose($$$) {
  my ($hash,$code,$response) = @_;
  my ($name,$type,$con) = ($hash->{NAME},$hash->{TYPE},$hash->{CD});

  my $ipv = $hash->{PEER} =~ m/:/ ? 6 : 4;
  my $bhash = $modules{ESPEasy}{defptr}{BRIDGE}{$ipv};
  my $bname = $bhash->{NAME};

  print $con "HTTP/1.1 ".$code."\r\n",
         "Content-Type: text/plain\r\n",
         "Connection: close\r\n",
         "Content-Length: ".length($response)."\r\n\r\n",
         $response;
  Log3 $bname, 4, "$type $name: Send http close '$code'";
  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_paramPos($$$)
{
  my ($hash,$cmd,$search) = @_;
  my $name = $hash->{NAME};
  my @usage = split(" ",$data{ESPEasy}{$name}{sets}{$cmd}{usage});
  my $pos = 0;
  my $i = 0;

  foreach (@usage) {
    if ($_ eq $search) {
      $pos = $i+1;
      last;
    }
    $i++;
  }

  return $pos; # return 0 if no match, else position
}


# ------------------------------------------------------------------------------
sub ESPEasy_paramCount($)
{
  return () = $_[0] =~ m/\s/g  # count \s in a string
}


# ------------------------------------------------------------------------------
sub ESPEasy_clearReadings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my @dr;
  foreach (keys %{$hash->{READINGS}}) {
    CommandDeleteReading(undef, "$name $_");
    push(@dr,$_);
  }

  if (scalar @dr >= 1) {
    delete $hash->{helper}{received};
    delete $hash->{helper}{fpc};        # used in checkPresence
    Log3 $name, 3, "$type $name: Readings [".join(",",@dr)."] wiped out";
  }

  ESPEasy_setState($hash);
  return undef
}


# ------------------------------------------------------------------------------
sub ESPEasy_checkVersion($$$$)
{
  my ($hash,$dev,$ve,$vj) = @_;
  my ($type,$name) = ($hash->{TYPE},$hash->{NAME});
  my $ov = "_OUTDATED_ESP_VER_$dev";

  if ($vj < $minJsonVersion) {
    $hash->{$ov} = "R".$ve."/J".$vj;
    Log3 $name, 2, "$type $name: WARNING: no data processed. ESPEasy plugin "
                  ."'FHEM HTTP' is too old [$dev: R".$ve." J".$vj."]. ".
                   "Use ESPEasy R$minEEBuild at least.";
  return 1;
  }
  else{
    delete $hash->{$ov} if exists $hash->{$ov};
    return 0;
  }
}


# ------------------------------------------------------------------------------
sub ESPEasy_checkPresence($)
{
  my ($hash,$isPresent) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $interval = AttrVal($name,'Interval',$d_Interval);
  my $addTime = 10; # if there is extreme heavy system load

  return undef if AttrVal($name,'presenceCheck',1) == 0;
  return undef if $interval == 0;

  my $presence = "absent";
  # check each received reading
  foreach my $reading (keys %{$hash->{helper}{received}}) {
    if (ReadingsAge($name,$reading,0) < $interval+$addTime) {
      #dev is present if any reading is newer than INTERVAL+$addTime
      $presence = "present";
      last;
    }
  }

  # update presence only if FirstPrecenceCheck is $interval seconds ago.
  $hash->{helper}{fpc} = time() if (!defined $hash->{helper}{fpc});
  if ($presence eq "present" || (time() - $hash->{helper}{fpc}) > $interval) {
    readingsSingleUpdate($hash,"presence",$presence,1);
    Log3 $name, 4, "$type $name: presence: $presence";
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_setState($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  return undef if not AttrVal($name,"setState",1);

  if (AttrVal($name,"rgbGPIOs",0)) {
    my ($r,$g,$b) = ESPEasy_gpio2RGB($hash);
    if ($r ne "") {
      readingsSingleUpdate($hash,"state", "R: $r G: $g B: $b", 1)
    }
  }

  else {
    my $interval = AttrVal($name,"Interval",$d_Interval);
    my $addTime = 3;
    my @ret;
    foreach my $reading (sort keys %{$hash->{helper}{received}}) {
      next if $reading =~ m/^(\.ignored_.*|state|presence|_lastAction|_lastError|\w+_mode)$/;
      next if $interval && ReadingsAge($name,$reading,1) > $interval+$addTime;
      push(@ret, substr($reading,0,AttrVal($name,"setState",3))
                .": ".ReadingsVal($name,$reading,""));
    }

    my $oState = ReadingsVal($name, "state", "");
    my $presence = ReadingsVal($name, "presence", "opened");

    if ($presence eq "absent" && $oState ne "absent") {
      readingsSingleUpdate($hash,"state","absent", 1 );
      delete $hash->{helper}{received};
    }
    else {
      my $nState = (scalar @ret >= 1) ? join(" ",@ret) : $presence;
      readingsSingleUpdate($hash,"state",$nState, 1 ); # if ($oState ne $nState);
    }
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_setRGB($$@)
{
  my ($hash,$cmd,@p) = @_;
  my ($type,$name) = ($hash->{TYPE},$hash->{NAME});
  my ($rg,$gg,$bg) = split(",",AttrVal($name,"rgbGPIOs",""));
  my ($r,$g,$b);

  my $rgb = $p[0] if $cmd =~ m/^rgb$/i;
#  return undef if !defined $rgb;

  $rg = $ee_map{pins}{uc $rg} if defined $ee_map{pins}{uc $rg};
  $gg = $ee_map{pins}{uc $gg} if defined $ee_map{pins}{uc $gg};
  $bg = $ee_map{pins}{uc $bg} if defined $ee_map{pins}{uc $bg};

  if ($cmd =~ m/^(1|on)$/ || ($cmd =~ m/^rgb$/i && $rgb =~ m/^(1|on)$/)) {
    $rgb = "FFFFFF" }
  elsif ($cmd =~ m/^(0|off)$/ || ($cmd =~ m/^rgb$/i && $rgb =~ m/^(0|off)$/)) {
    $rgb = "000000" }
  elsif ($cmd =~ m/^toggle$/i || ($cmd =~ m/^rgb$/i && $rgb =~ m/^toggle$/i)) {
    $rgb = ReadingsVal($name,"rgb","000000") ne "000000" ? "000000" : "FFFFFF"
  }

  if ($rgb =~ m/^([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/) {
    ($r,$g,$b) = (hex($1), hex($2), hex($3));
  }
  else {
    Log3 $name, 2, "$type $name: set $name $cmd $rgb: "
          ."'$rgb' is not a valid RGB value.";
    return "'$rgb' is not a valid RGB value.";
  }
  ESPEasy_Set($hash, $name, "pwm", ("$rg", $r*4));
  ESPEasy_Set($hash, $name, "pwm", ("$gg", $g*4));
  ESPEasy_Set($hash, $name, "pwm", ("$bg", $b*4));
  readingsSingleUpdate($hash, "rgb", uc $rgb, 1);

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_setCT($$@)
{
  my ($hash,$cmd,@p) = @_;
  my ($type,$name) = ($hash->{TYPE},$hash->{NAME});
  my ($gww,$gcw) = split(",",AttrVal($name,"wwcwGPIOs",""));
  my ($ww,$cw);
  my ($pct,$ct);
  my $ctWW = AttrVal($name,"colorpickerCTww",$d_colorpickerCTww);
  my $ctCW = AttrVal($name,"colorpickerCTcw",$d_colorpickerCTcw);
  my $ctWW_lim = AttrVal($name,"ctWW_reducedRange",undef);
  my $ctCW_lim = AttrVal($name,"ctCW_reducedRange",undef);

  $gww = $ee_map{pins}{uc $gww} if defined $ee_map{pins}{uc $gww};
  $gcw = $ee_map{pins}{uc $gcw} if defined $ee_map{pins}{uc $gcw};

  readingsSingleUpdate($hash, $cmd, $p[0], 1);

  if ($cmd eq "ct") {
    $ct = $p[0];
    $pct = ReadingsVal($name,"pct",50);
  }
  elsif ($cmd eq "pct") {
    $pct = $p[0];
    $ct = ReadingsVal($name,"ct",3000);
  }

  # are we out of range?
  $pct = 100 if $pct > 100;
  $pct = 0 if $pct < 0;
  $ct = $ctWW if $ct < $ctWW;
  $ct = $ctCW if $ct > $ctCW;

  #Log 1, "pct:$pct  ct:$ct  ctWW:$ctWW  ctCW:$ctCW  ctWW_lim:$ctWW_lim  ctCW_lim:$ctCW_lim";

  my $wwcwMaxBri = AttrVal($name,"wwcwMaxBri",0);
  my ($fww,$fcw) = ESPEasy_ct2wwcw($ct, $ctWW, $ctCW, $wwcwMaxBri, $ctWW_lim, $ctCW_lim);

  ESPEasy_Set($hash, $name, "pwm", ($gww, int $pct*10.23*$fww));
  ESPEasy_Set($hash, $name, "pwm", ($gcw, int $pct*10.23*$fcw));

  return undef;
}


# ------------------------------------------------------------------------------
# ct2wwcw with constant brightness over temp range (or max bri if $maxBri == 1).
# "used range" can be set to reduce temp range to get a lighter leds with constant
# bri over reduced temp range.
# 1: temp to set 2:led-ww-temp 3:led-cw-temp 4:maxBri 5:used range ww 6:used range cw
sub ESPEasy_ct2wwcw($$$;$$$)
{
  my ($t,$tww,$tcw,$maxBri,$tww_ur,$tcw_ur) = @_;
  my $maxBriFactor;

  $tcw -= $tww;
  $t   -= $tww;
  my $fcw = $t / $tcw;
  my $fww = 1 - $fcw;

  if ($maxBri // $maxBri) {
    $maxBriFactor = ($fcw > $fww) ? 1/$fcw : 1/$fww;
    #Log 1, "maxBriFactor: $maxBriFactor (maxBri)";
  }
  else {
    $tww_ur = $tww if !(defined $tww_ur) || $tww_ur < $tww || $tww_ur >= $tcw;
    $tcw_ur = $tcw if !(defined $tcw_ur) || $tcw_ur > $tcw || $tcw_ur <= $tww;

    $tww_ur -= $tww;
    $tcw_ur -= $tww;
    my $t = ($tww_ur < $tcw - $tcw_ur) ? $tww_ur : $tcw - $tcw_ur;
    my $fcw = $t / $tcw;
    my $fww = 1 - $fcw;
    $maxBriFactor = ($fcw > $fww) ? 1/$fcw : 1/$fww;
    #Log 1, "maxBriFactor: $maxBriFactor (constBri)";
  }

  return ( $fww * $maxBriFactor, $fcw * $maxBriFactor );
}


# ------------------------------------------------------------------------------
sub ESPEasy_gpio2RGB($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($r,$g,$b,$rgb);
  my $a = AttrVal($name,"rgbGPIOs",undef);
  return undef if !defined $a;
  my ($gr,$gg,$gb) = split(",",AttrVal($name,"rgbGPIOs",""));

  $gr = $ee_map{pins}{uc $gr} if defined $ee_map{pins}{uc $gr};
  $gg = $ee_map{pins}{uc $gg} if defined $ee_map{pins}{uc $gg};
  $gb = $ee_map{pins}{uc $gb} if defined $ee_map{pins}{uc $gb};

  my $rr = AttrVal($name,"readingPrefixGPIO","GPIO").$gr;
  my $rg = AttrVal($name,"readingPrefixGPIO","GPIO").$gg;
  my $rb = AttrVal($name,"readingPrefixGPIO","GPIO").$gb;

  $r = ReadingsVal($name,$rr,undef);
  $g = ReadingsVal($name,$rg,undef);
  $b = ReadingsVal($name,$rb,undef);

  return ("","","") if !defined $r || !defined $g || !defined $b
                    || $r !~ m/^\d+$/ || $g !~ m/^\d+$/i || $b !~ m/^\d+$/i;
  return (sprintf("%2.2X",$r/4), sprintf("%2.2X",$g/4), sprintf("%2.2X",$b/4));
}


# ------------------------------------------------------------------------------
# attr <dev> devStateIcon { ESPEasy_devStateIcon($name) }
sub ESPEasy_devStateIcon($)
{
  my $ret = Color::devStateIcon($_[0],"rgb","rgb");
  $ret =~ m/^.*:on@#(..)(..)(..):toggle$/;
  return undef if !defined $1;
  my $symP = int((hex($1)+hex($2)+hex($3))/76.5)*10;
  $symP = "00" if $symP == 0;
  my $icon = "light_light_dim_".$symP;
  $ret =~ s/:on@#/:$icon@#/;

  return $ret;
}


# ------------------------------------------------------------------------------
sub ESPEasy_adjustValue($$$)
{
  my ($hash,$r,$v) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  my $a = AttrVal($name,"adjustValue",undef);
  return $v if !defined $a;

  my ($VALUE,$READING,$NAME) = ($v,$r,$name); #capital vars for use in attribute
  my @a = split(" ",$a);
  foreach (@a) {
    my ($regex,$formula) = split(":",$_);
    if ($r =~ m/^$regex$/) {
      no warnings;
      my $adjVal = $formula =~ m/\$VALUE/ ? eval($formula) : eval($v.$formula);
      use warnings;
      if ($@) {
        Log3 $name, 2, "$type $name: WARNING: attribute 'adjustValue': "
                      ."mad expression '$formula'";
        Log3 $name, 2, "$type $name: $@";
      }
      else {
        my $rText = (defined $adjVal) ? $adjVal : "'undef'";
        Log3 $name, 5, "$type $name: Adjusted reading $r: $v => $formula = $rText";
        return $adjVal;
      }
      #last; #disabled to be able to match multiple readings
    }
  }

  return $v;
}


# ------------------------------------------------------------------------------
sub ESPEasy_urlEncodeDisplayText($$@)
{
  my ($hash, $cmd, @params) = @_;
  my $name = $hash->{NAME};
  my $enc = AttrVal($name, "displayTextEncode", $d_displayTextEncode);
  my $pp = ESPEasy_paramPos($hash,$cmd,'<text>');

  if ($enc && $pp) {
    my (@p, @t);
    my $c = scalar @params;

    # leading parameters
    for (my $i=0; $i<$pp-1; $i++)  {
      push( @p, $params[$i] )
    }

    # collect all texts parameters
    for (my $i=$pp-1; $i<$c; $i++) {
      $params[$i] =~ s/,/./g;  # comma is ESPEasy parameter splitter, can't be used
      push @t, $params[$i];
    }
    my $text = join(" ", @t);

    # fill line with leading/trailing spaces
    my $width = AttrVal($name,"displayTextWidth", $d_displayTextWidth);
    if ($width) {
      $text = " " x ($p[1]-1) .$text. " " x ($width - length($text) - $p[1]+1);
      $text = substr($text, 0, $width);
      $p[1] = 1;
    }

    push(@p, urlEncode($text));
    return @p;
  }

  return @params;
}


# ------------------------------------------------------------------------------
sub ESPEasy_loadRequiredModules($)
{
  my ($hash) = @_;
  foreach ("JSON", "Encode") {
    eval "use $_; 1;";
    if (!$@) {
      $hash->{helper}{pm}{$_} = 1;
      }
    else {
      $hash->{helper}{pm}{$_} = 0;
      if ($init_done || $hash->{SUBTYPE} eq "bridge") {
        my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
        Log3 $name, 1, "$type $name: WARNING: Perl module $_ is not installed. "
                     . "Reduced functionality!";
        Log3 $name, 2, "$type $name: $@" if $init_done;
      }
    }
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_isAttrCombineDevices($)
{
  return 0 if !defined $_[0];
  my @ranges = split(/,| /,$_[0]);
  foreach (@ranges) {
    if (!($_ =~ m/^([A-Za-z0-9_\.]|[A-Za-z0-9_\.][A-Za-z0-9_\.]*[A-Za-z0-9\._])$/
       || ESPEasy_isIPv64Range($_)))
    {
      return 0
    }
  }

  return 1;
}


# ------------------------------------------------------------------------------
# check if $peer is covered by $allowed (eg. 10.1.2.3 is included in 10.0.0.0/8)
# 1:peer address 2:allowed range
# ------------------------------------------------------------------------------
sub ESPEasy_isCombineDevices($$$)
{
  my ($peer,$espName,$allowed) = @_;
  return $allowed if $allowed =~ m/^[01]$/;

  my @allowed = split(/,| /,$allowed);
  foreach (@allowed) { return 1 if $espName eq $_ }
  return 1 if ESPEasy_isPeerAllowed($peer,$allowed);
  return 0;
}


# ------------------------------------------------------------------------------
# check param to be a valid ip64 address or fqdn or hostname
# ------------------------------------------------------------------------------
sub ESPEasy_isAuthenticated($$)
{
  my ($hash,$ah) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});

  my $ipv = $hash->{PEER} =~ m/:/ ? 6 : 4;
  my $bhash = $modules{ESPEasy}{defptr}{BRIDGE}{$ipv};
  my ($bname,$btype) = ($bhash->{NAME},$bhash->{TYPE});

  my $u = $bhash->{".bau"};
  my $p = $bhash->{".bap"};
  my $attr = AttrVal($bname,"authentication",0);

  if (!defined $u || !defined $p || $attr == 0) {
    if (defined $ah){
      Log3 $bname, 2, "$type $name: No basic authentication active but ".
                     "credentials received";
    }
    else {
       Log3 $bname, 4, "$type $name: No basic authentication required";
    }
    return "not required";
  }

  elsif (defined $ah) {
    my ($a,$v) = split(" ",$ah);
    if ($a eq "Basic" && decode_base64($v) eq $u.":".$p) {
      Log3 $bname, 4, "$type $name: Basic authentication accepted";
      return "accepted";
    }
    else {
      Log3 $bname, 2, "$type $name: Basic authentication rejected";
    }
  }

  else {
    Log3 $bname, 2, "$type $name: Basic authentication active but ".
                   "no credentials received";
  }

return undef;
}


# ------------------------------------------------------------------------------
sub ESPEasy_isValidPeer($)
{
  my ($addr) = @_;
  return 0 if !defined $addr;
  my @ranges = split(/,| /,$addr);
  foreach (@ranges) {
    return 0 if !( ESPEasy_isIPv64Range($_)
                || ESPEasy_isFqdn($_) || ESPEasy_isHostname($_) );
  }

  return 1;
}


# ------------------------------------------------------------------------------
# check if given ip or ip range is guilty
# argument can be:
# - ipv4, ipv4/CIDR, ipv4/dotted, ipv6, ipv6/CIDR (or a regexp if opt. argument
#   $regexChk is set)
# - space or comma separated list of above.
# ------------------------------------------------------------------------------
sub ESPEasy_isIPv64Range($;$)
{
  my ($addr,$regexChk) = @_;
  return 0 if !defined $addr;
  my @ranges = split(/,| /,$addr);
  foreach (@ranges) {
    my ($ip,$nm) = split("/",$_);
    if (ESPEasy_isIPv4($ip)) {
      return 0 if defined $nm && !( ESPEasy_isNmDotted($nm)
                                 || ESPEasy_isNmCIDRv4($nm) );
    }
    elsif (ESPEasy_isIPv6($ip)) {
      return 0 if defined $nm && !ESPEasy_isNmCIDRv6($nm);
    }
    elsif (defined $regexChk && !defined $nm) {
      return 0 if $ip =~ m/^\*/ || $ip =~ m/^\d+\.\d+\.\d+\.\d+$/; # faulty regexp/ip
      eval { "Hallo" =~ m/^$ip$/ };
      return $@ ? 0 : 1;
    }
    else {
      return 0;
    }
  }

  return 1;
}


# ------------------------------------------------------------------------------
# check if $peer is covered by $allowed (eg. 10.1.2.3 is included in 10.0.0.0/8)
# 1:peer address 2:allowed range
# ------------------------------------------------------------------------------
sub ESPEasy_isPeerAllowed($$)
{
  my ($peer,$allowed) = @_;
  return $allowed if $allowed =~ m/^[01]$/;
  #return 1 if $allowed =~ /^0.0.0.0\/0(.0.0.0)?$/; # not necessary but faster
  my $binPeer = ESPEasy_ip2bin($peer);
  my @a = split(/,| /,$allowed);
  foreach (@a) {
    return 1 if $peer =~ m/^$_$/;                   # a regexp is been used
    next if !ESPEasy_isIPv64Range($_);              # needed for combinedDevices
    my ($addr,$ip,$mask) = ESPEasy_addrToCIDR($_);
    return 0 if !defined $ip || !defined $mask;   # return if ip or mask !guilty
    my $binAllowed = ESPEasy_ip2bin($addr);
    my $binPeerCut = substr($binPeer,0,$mask);
    return 1 if ($binAllowed eq $binPeerCut);
  }

  return 0;
}


# ------------------------------------------------------------------------------
# convert IPv64 address to binary format and return network part of binary, only
# ------------------------------------------------------------------------------
sub ESPEasy_ip2bin($)
{
  my ($addr) = @_;
  my ($ip,$mask) = split("/",$addr);
  my @bin;

  if (ESPEasy_isIPv4($ip)) {
    $mask = 32 if !defined $mask;
    @bin = map substr(unpack("B32",pack("N",$_)),-8), split(/\./,$ip);
  }
  elsif (ESPEasy_isIPv6($ip)) {
    $ip = ESPEasy_expandIPv6($ip);
    $mask = 128 if !defined $mask;
    @bin = map {unpack('B*',pack('H*',$_))} split(/:/, $ip);
  }
  else {
    return undef;
  }

  my $bin = join('', @bin);
  my $binMask = substr($bin, 0, $mask);

  return $binMask; # return network part of $bin
}


# ------------------------------------------------------------------------------
# expand IPv6 address to 8 full blocks
# Advantage of IO::Socket : already installed and it seems to be the fastest way
# http://stackoverflow.com/questions/4800691/perl-ipv6-address-expansion-parsing
# ------------------------------------------------------------------------------
sub ESPEasy_expandIPv6($)
{
  my ($ipv6) = @_;
  use Socket qw(inet_pton AF_INET6);
  return join(":", unpack("H4H4H4H4H4H4H4H4",inet_pton(AF_INET6, $ipv6)));
}


# ------------------------------------------------------------------------------
# convert IPv64 address or range into CIDR notion
# return undef if addreess or netmask is not valid
# ------------------------------------------------------------------------------
sub ESPEasy_addrToCIDR($)
{
  my ($addr) = @_;
  my ($ip,$mask) = split("/",$addr);
  # no nm specified
  return (ESPEasy_isIPv4($ip) ? ("$ip/32",$ip,32) : ("$ip/128",$ip,128)) if !defined $mask;
  # netmask is already in CIDR format and all values are valid
  return ("$ip/$mask",$ip,$mask)
    if (ESPEasy_isIPv4($ip) && ESPEasy_isNmCIDRv4($mask))
    || (ESPEasy_isIPv6($ip) && ESPEasy_isNmCIDRv6($mask));
  $mask = ESPEasy_dottedNmToCIDR($mask);
  return (undef,undef,undef) if !defined $mask;

  return ("$ip/$mask",$ip,$mask);
}


# ------------------------------------------------------------------------------
# convert dotted decimal netmask to CIDR format
# return undef if nm is not in dotted decimal format
# ------------------------------------------------------------------------------
sub ESPEasy_dottedNmToCIDR($)
{
  my ($mask) = @_;
  return undef if !ESPEasy_isNmDotted($mask);

  # dotted decimal to CIDR
  my ($byte1, $byte2, $byte3, $byte4) = split(/\./, $mask);
  my $num = ($byte1 * 16777216) + ($byte2 * 65536) + ($byte3 * 256) + $byte4;
  my $bin = unpack("B*", pack("N", $num));
  my $count = ($bin =~ tr/1/1/);

  return $count; # return number of netmask bits
}


# ------------------------------------------------------------------------------
sub ESPEasy_isIPv4($)
{
  return 0 if !defined $_[0];
  return 1 if($_[0]
    =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isIPv6($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0]
    =~ m/^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isIPv64($)
{
  return 0 if !defined $_[0];
  return 1 if ESPEasy_isIPv4($_[0]) || ESPEasy_isIPv6($_[0]);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isNmDotted($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0]
    =~ m/^(255|254|252|248|240|224|192|128|0)\.0\.0\.0|255\.(255|254|252|248|240|224|192|128|0)\.0\.0|255\.255\.(255|254|252|248|240|224|192|128|0)\.0|255\.255\.255\.(255|254|252|248|240|224|192|128|0)$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isNmCIDRv4($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0] =~ m/^([0-2]?[0-9]|3[0-2])$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isNmCIDRv6($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0] =~ m/^([0-9]?[0-9]|1([0-1][0-9]|2[0-8]))$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isFqdn($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0]
    =~ m/^(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)$/);
  return 0;
}

# ------------------------------------------------------------------------------
sub ESPEasy_isHostname($)
{
  return 0 if !defined $_[0];
  return 1 if ($_[0] =~ m/^([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/)
           && !(ESPEasy_isIPv4($_[0]) || ESPEasy_isIPv6($_[0]));
  return 0;
}

# ------------------------------------------------------------------------------
# get accurate time
# ------------------------------------------------------------------------------
sub ESPEasy_timeStamp() {
  my ($s,$ms) = gettimeofday();
  return "$s.$ms";
}

# ------------------------------------------------------------------------------
sub ESPEasy_dumpSingleLine($)
{
  my $saveIndent = $Data::Dumper::Indent; my $saveTerse = $Data::Dumper::Terse ;
  $Data::Dumper::Indent = 0; $Data::Dumper::Terse  = 1;
  my $ret = Dumper($_[0]);
  $Data::Dumper::Indent = $saveIndent; $Data::Dumper::Terse = $saveTerse;
  return $ret;
}


1;

=pod
=item device
=item summary Control and access to ESPEasy (Espressif ESP8266/ESP32 WLAN-SoC)
=item summary_DE Steuerung und Zugriff auf ESPEasy (Espressif ESP8266/ESP32 WLAN-SoC)
=begin html

<a name="ESPEasy"></a>
<h3>ESPEasy</h3>

<ul>
  <p>Provides access and control to Espressif ESP8266/ESP32 WLAN-SoC w/ ESPEasy</p>

  Notes:
  <ul>
    <li>You have to define a bridge device before any logical device can be
      (automatically) defined.
    </li>
    <li>You have to configure your ESP to use "FHEM HTTP" controller protocol.
      Furthermore ESP Easy controller IP must match FHEM's IP address. ESP controller
      port and the FHEM ESPEasy bridge port must be the same.
    </li>
    <li>
      Max. 2 ESPEasy bridges can be defined in the same FHEM instance: 1 for IPv4 and 1 for IPv6
    </li>
    <li>Further information about this module is available here:
      <a href="https://forum.fhem.de/index.php/topic,55728.0.html">Forum #55728</a>
      or in this <a href="https://wiki.fhem.de/wiki/ESPEasy">wiki article</a>.
    </li>
    <li>For security reasons: if one or more of your ESPEasy device uses a
      public IP address then you have to enable this explicitly or the device(s)
      will be ignored/rejected:
    </li>
    <ul>
      <li>
        Enable all ESPEasy device IP addresses/subnets/regexs with the help of
        bridge attributes
        <a href="#ESPEasy_bridge_attr_allowedips">allowedIPs</a> /
        <a href="#ESPEasy_bridge_attr_deniedips">deniedIPs</a>.
      </li>
      <li>
        Enable authentication: see attribute
        <a href="#ESPEasy_bridge_attr_authentication">authentication</a> and
        bridge set <a href="#ESPEasy_bridge_set_user">user</a>
                 / <a href="#ESPEasy_bridge_set_pass">pass</a> commands.
      </li>
    </ul>
    <br>
  </ul>

  Requirements:
  <ul>
    <li>
      ESPEasy build &gt;= <a href="https://github.com/ESP8266nu/ESPEasy"
      target="_new">R128</a> (self compiled) or an ESPEasy precompiled image
      &gt;= <a href="http://www.letscontrolit.com/wiki/index.php/ESPEasy#Loading_firmware" target="_new">R140_RC3</a><br>
    </li>
    <li>perl module JSON<br>
      Use "cpan install JSON" or operating system's package manager to install
      Perl JSON Modul. Depending on your os the required package is named:
      libjson-perl or perl-JSON.
    </li>
  </ul>

  <h4>ESPEasy Bridge</h4>

  <a name="ESPEasy_bridge_define"></a>
  <b>Define </b>(bridge)<br><br>

  <ul>
    <code>define &lt;name&gt; ESPEasy bridge &lt;[IPV6:]port&gt;</code><br><br>

    <li>
      <a name=""><code>&lt;name&gt;</code></a><br>
      Specifies a device name of your choise.<br>
      example: <code>ESPBridge</code>
    </li><br>

    <li>
      <a name=""><code>&lt;port&gt;</code></a><br>
      Specifies TCP port for incoming ESPEasy http requests. This port must
      <u>not</u> be used by any other application or daemon on your system and
      must be in the range 1024..65535 unless you run your FHEM installation
      with root permissions (not recommanded).<br>
      If you want to define an IPv4 and an IPv6 bridge on the same TCP port
      (recommanded) then it might be necessary on (some?) Linux
      distributions to activate IPV6_V6ONLY socket option. Use <code>"echo
      1>/proc/sys/net/ipv6/bindv6only"</code> or systemctl for that purpose.<br>
      eg. <code>8383</code><br>
      eg. <code>IPV6:8383</code><br>
      Example:<br>
      <code>define ESPBridge ESPEasy bridge 8383</code></li><br>
  </ul>

  <br><a name="ESPEasy_bridge_get"></a>
  <b>Get </b>(bridge)<br><br>

  <ul>
    <li><a name="ESPEasy_bridge_get_reading">&lt;reading&gt;</a><br>
      returns the value of the specified reading</li>
      <br>

    <li><a name="ESPEasy_bridge_get_queueSize">queueSize</a><br>
      returns number of entries for currently used queue.
      </li><br>

    <li><a name="ESPEasy_bridge_get_queueContent">queueContent</a><br>
      returns queues content.
      <ul>
        <li>arguments: <code>IP address</code> (can be a regex or omitted to display all queues)</li>
      </ul>
      </li><br>

    <li><a name="ESPEasy_bridge_get_user">user</a><br>
      returns username used by basic authentication for incoming requests.
      </li><br>

    <li><a name="ESPEasy_bridge_get_pass">pass</a><br>
      returns password used by basic authentication for incoming requests.
      </li><br>
  </ul>

  <br><a name="ESPEasy_bridge_set"></a>
  <b>Set </b>(bridge)<br><br>

  <ul>
    <li><a name="ESPEasy_bridge_set_help">help</a><br>
      Shows set command usage<br>
      required values: <code>help|pass|user|clearQueue</code></li><br>

    <li><a name="ESPEasy_bridge_set_clearqueue">clearQueue</a><br>
      Used to erase all command queues.<br>
      required value: <code>&lt;none&gt;</code><br>
      eg. : <code>set ESPBridge clearQueue</code></li><br>

    <li><a name="ESPEasy_bridge_set_pass">pass</a><br>
      Specifies password used by basic authentication for incoming requests.<br>
      Note that attribute <a href="#ESPEasy_bridge_attr_authentication">authentication</a>
      must be set to enable basic authentication, too.<br>
      required value: <code>&lt;password&gt;</code><br>
      eg. : <code>set ESPBridge pass secretpass</code></li><br>

    <li><a name="ESPEasy_bridge_set_user">user</a><br>
      Specifies username used by basic authentication for incoming requests.<br>
      Note that attribute <a href="#ESPEasy_bridge_attr_authentication">authentication</a>
      must be set to enable basic authentication, too.<br>
      required value: <code>&lt;username&gt;</code><br>
      eg. : <code>set ESPBridge user itsme</code></li><br>
  </ul>

  <br><a name="ESPEasy_bridge_attr"></a>
  <b>Attributes </b>(bridge)<br><br>

  <ul>
    <li><a name="ESPEasy_bridge_attr_allowedips">allowedIPs</a><br>
      Used to limit IPs or IP ranges of ESPs which are allowed to commit data.
      <br>
      Specify IP, IP/netmask, regexp or a comma separated list of these values.
      Netmask can be written as bitmask or dotted decimal. Domain names for dns
      lookups are not supported.<br>
      Possible values: IPv64 address, IPv64/netmask, regexp<br>
      Default: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
      fe80::/10, fc00::/7, ::1
      <br><br>
      Examles:<br>

      <table><tr><td>
      10.68.30.147
      </td><td>
        =&gt; IPv4 single address
      </td></tr><tr><td>
        10.68.30.0/25
      </td><td>
        =&gt; IPv4 CIDR network 192.168.30.0-127
      </td></tr><tr><td>
        10.68.30.8/255.255.248.0
      </td><td>
        =&gt; IPv4 CIDR network 192.168.30.8-15
      </td></tr><tr><td>
        192.168.30.1([0-4][0-9]|50)
      </td><td>
        =&gt; IPv4 range w/ regexp: 192.168.30.100-150
      </td></tr><tr><td>
        2001:1a59:50a9::aaaa
      </td><td>
        =&gt; IPv6 single address
      </td></tr><tr><td>
        2001:1a59:50a9::/48
      </td><td>
        =&gt; IPv6 network 2001:1a59:50a9::/48
      </td></tr><tr><td>
        2001:1a59:50a9::01[0-4][0-9]
      </td><td>
        =&gt; IPv6 range w/ regexp: 2001:1a59:50a9::0100-0149
      </tr></td>
      </table>
      <span style="font-size:small;">Note that short IPv6 notation (::) must be
      used in conjunction with regexps.</span>
      </li><br>

    <li><a name="ESPEasy_bridge_attr_authentication">authentication</a><br>
      Used to enable basic authentication for incoming requests.<br>
      Note that user, pass and authentication attribute must be set to activate
      basic authentication<br>
      Possible values: 0,1<br>
      Default: 0</li><br>

    <li><a name="ESPEasy_bridge_attr_autocreate">autocreate</a><br>
      Used to overwrite global autocreate setting.<br>
      Global autocreate setting will be detected by global attribut
      'autoload_undefined_devices'<br>
      Possible values: 0,1<br>
      Default: 0 (disabled)</li><br>

    <li><a name="ESPEasy_bridge_attr_autosave">autosave</a><br>
      Used to overwrite global autosave setting.<br>
      Global autosave setting will be detected by global attribut 'autosave'.
      <br>
      Possible values: 0,1<br>
      Default: 0 (disabled)</li><br>

    <li><a name="ESPEasy_bridge_attr_combinedevices">combineDevices</a><br>
      Used to gather all ESP devices of a single ESP into 1 FHEM device even if
      different ESP devices names are used.<br>
      Possible values: 0, 1, IPv64 address, IPv64/netmask, ESPname or a comma
      separated list consisting of these values.<br>
      Netmasks can be written as bitmask or dotted decimal. Domain names for dns
      lookups are not supported.<br>
      Default: 0 (disabled for all ESPs)<br>
      Eg. 1 (globally enabled)<br>
      Eg. ESP01,ESP02<br>
      Eg. 10.68.30.1,10.69.0.0/16,ESP01,2002:1a59:50a9::/48</li><br>

    <li><a name="ESPEasy_bridge_attr_deniedips">deniedIPs</a><br>
      Used to define IPs or IP ranges of ESPs which are denied to commit data.
      <br>
      Syntax see <a href="#ESPEasy_bridge_attr_allowedips">allowedIPs</a>.<br>
      This attribute will overwrite any IP or range defined by
      <a href="#ESPEasy_bridge_attr_allowedips">allowedIPs</a>.<br>
      Default: none (no IPs are denied)</li><br>

    <li><a name="ESPEasy_bridge_attr_disable">disable</a><br>
      Used to disable device.<br>
      Possible values: 0,1<br>
      Default: 0 (eanble)</li><br>

    <li><a name="ESPEasy_bridge_attr_httpreqtimeout">httpReqTimeout</a><br>
      Specifies seconds to wait for a http answer from ESP8266 device.<br>
      Possible values: 4..60<br>
      Default: 10 seconds</li><br>

    <li><a name="ESPEasy_bridge_attr_maxhttpsessions">maxHttpSessions</a><br>
      Limit maximal concurrent outgoing http sessions to a single ESP.<br>
      Set to 0 to disable this feature. At the moment (ESPEasy R147) it seems
      to be possible to send 5 "concurrent" requests if nothing else keeps the
      esp working.<br>
      Possible values: 0..9<br>
      Default: 3</li><br>

    <li><a name="ESPEasy_bridge_attr_maxqueuesize">maxQueueSize</a><br>
      Limit maximal queue size (number of commands in queue) for outgoing http
      requests.<br>
      If command queue size is reached (eg. ESP is offline) any further
      command will be ignored and discard.<br>
      Possible values: >10<br>
      Default: 250</li><br>

    <li><a name="ESPEasy_bridge_attr_resendfailedcmd">resendFailedCmd</a><br>
      Used to define number of command resends to the ESP if there is an error
      in transmission on network layer (eg. unreachable wifi device).<br>
      Possible values: a positive number<br>
      Default: 0 (disabled: no resending of commands)</li><br>

    <li><a name="ESPEasy_bridge_attr_uniqids">uniqIDs</a><br>
      This attribute has been removed.</li><br>

    <li><a href="#readingFnAttributes">readingFnAttributes</a>
      </li><br>
  </ul>

  <h4>ESPEasy Device</h4>

  <a name="ESPEasy_device_define"></a>
  <b>Define </b>(logical device)<br><br>

  <ul>
    Note 1: Logical devices will be created automatically if any values are
    received by the bridge device and autocreate is not disabled. If you
    configured your ESP in a way that no data is send independently then you
    have to define logical devices. At least wifi rssi value could be defined
    to use autocreate and presence detection.<br><br>

    <code>define &lt;name&gt; ESPEasy &lt;ip|fqdn&gt; &lt;port&gt; &lt;IODev&gt; &lt;identifier&gt;</code><br><br>

    <li>
      <a name=""><code>&lt;name&gt;</code></a><br>
      Specifies a device name of your choise.<br>
      example: <code>ESPxx</code>
    </li><br>

    <li>
      <a name=""><code>&lt;ip|fqdn&gt;</code></a><br>
      Specifies ESP IP address or hostname.<br>
      example: <code>172.16.4.100</code><br>
      example: <code>espxx.your.domain.net</code>
    </li><br>

    <li>
      <a name=""><code>&lt;port&gt;</code></a><br>
      Specifies http port to be used for outgoing request to your ESP. Should be 80<br>
      example: <code>80</code>
    </li><br>

    <li>
      <a name=""><code>&lt;IODev&gt;</code></a><br>
      Specifies your ESP bridge device. See above.<br>
      example: <code>ESPBridge</code>
    </li><br>

    <li>
      <a name=""><code>&lt;identifier&gt;</code></a><br>
      Specifies an identifier that will bind your ESP to this device.<br>
      This identifier must be specified in this form:<br>
      &lt;esp name&gt;_&lt;esp device name&gt;.<br>
      If bridge attribute <a href="#ESPEasy_bridge_attr_combinedevices">combineDevices</a> is used then &lt;esp name&gt; is used, only.<br>
      ESP name and device name can be found here:<br>
      &lt;esp name&gt;: =&gt; ESP GUI =&gt; Config =&gt; Main Settings =&gt; Name<br>
      &lt;esp device name&gt;: =&gt; ESP GUI =&gt; Devices =&gt; Edit =&gt; Task Settings =&gt; Name<br>
      example: <code>ESPxx_DHT22</code><br>
      example: <code>ESPxx</code>
    </li><br>

    <li>Example:<br>
      <code>define ESPxx ESPEasy 172.16.4.100 80 ESPBridge EspXX_SensorXX</code>
    </li><br>

  </ul>


  <br><a name="ESPEasy_device_get"></a>
  <b>Get </b>(logical device)<br><br>

  <ul>
    <li><a name="ESPEasy_device_get_adminpassword">adminPassword</a><br>
      returns the admin password. For details see
      <a href="#ESPEasy_device_set_adminpassword">set adminPassword</a>
    </li><br>

    <li><a name="ESPEasy_device_get_pinmap">pinMap</a><br>
      returns possible alternative pin names that can be used in commands
    </li><br>

    <li><a name="ESPEasy_device_get_setcmds">setCmds</a><br>
      returns formatted table of registered ESP commands/mappings.
    </li><br>

  </ul>


  <br><a name="ESPEasy_device_set"></a>
  <b>Set </b>(logical device)
  <br><br>

  <ul>
    Notes:<br>
    - Commands are case insensitive.<br>
    - Users of Wemos D1 mini or NodeMCU can use Arduino pin names instead of
    GPIO numbers.<br>
    &nbsp;&nbsp;D1 =&gt; GPIO5, D2 =&gt; GPIO4, ...,TX =&gt; GPIO1 (see: get
    <a href="#ESPEasy_bridge_get_pinmap">pinMap</a>)<br>
    - low/high state can be written as 0/1 or on/off
    <br><br>

    <b>ESPEasy module internal commands:</b><br><br>

    <li><a name="ESPEasy_device_set_adminpassword">adminPassword</a><br>
      The ESP Easy 'Admin Password" is used to protect some ESP Easy commands
      against unauthorized access. When this feature is enabled on your ESPs
      you should deposit this password. If an ESP Easy command will require this
      authorization the password will be sent to the ESP. Keep in mind that this
      feature works quite slow on your ESP Easy nodes.
    </li><br>

    <li><a name="ESPEasy_device_set_clearreadings">clearReadings</a><br>
      Delete all readings that are auto created by received sensor values
      since last FHEM restart.<br>
      <ul>
        <li>arguments: <code>none</code></li>
        <li>example: set &lt;esp&gt; clearReadings</li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_help">help</a><br>
      Shows set command usage.<br>
      <ul>
        <li>arguments: <code>&lt;a valid set command&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; help gpio</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_raw">raw</a><br>
      Can be used for own ESP plugins or new ESPEasy commands that are not
      considered by this module at the moment. Any argument will be sent
      directly to the ESP. Used URL is: "/control?cmd="
      <ul>
        <li>arguments: raw &lt;cmd&gt; [&lt;arg1&gt;] [&lt;arg2&gt;] [&lt;...&gt;]</li>
        <li>example: set &lt;esp&gt; raw myCommand p1 p2 p3</li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_rawsystem">rawsystem</a><br>
      The same as set command <a href="">raw</a> but this command uses the URL
      "/?cmd=" (command.ino) instead of "/control?cmd=" (ESPEasy plugins).
    </li><br>

    <li><a name="ESPEasy_device_set_statusrequest">statusRequest</a><br>
      Trigger a statusRequest for configured GPIOs (see attribut pollGPIOs)
      and do a presence check<br>
      <ul>
        <li>arguments: <code>n/a</code></li>
        <li>example: <code>set &lt;esp&gt; statusRequest</code></li>
      </ul><br>
    </li><br>

    <i><b>Note:</b> The following commands are built-in ESPEasy Software commands
    that are send directly to the ESP after passing a syntax check and more...
    A detailed description can be found here:
    <a href="http://www.letscontrolit.com/wiki/index.php/ESPEasy_Command_Reference"
    target="_NEW">ESPEasy Command Reference</a></i><br><br>

    <b>ESP Easy generic I/O commands:</b><br><br>

    <li><a name="ESPEasy_device_set_gpio">GPIO</a><br>
      Switch output pins to high/low<br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;0|1|off|on&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; gpio 14 on</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_pwm">PWM</a><br>
      Direct PWM control of output pins<br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;level&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; pwm 14 512</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_pwmfade">PWMFADE</a><br>
      Fade output pins to a pwm value<br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;target pwm&gt; &lt;duration 1-30s&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; pwmfade 14 1023 10</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_pulse">Pulse</a><br>
      Direct pulse control of output pins<br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; pulse 14 on 10</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_logpulse">LongPulse</a><br>
      Direct pulse control of output pins (duration in s)<br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; longpulse 14 on 10</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_logpulse_ms">LongPulse_ms</a><br>
      Direct pulse control of output pins (duration in ms)<br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; longpulse_ms 14 on 10000</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_pcfgpio">PCFGpio</a><br>
      Control PCF8574 (8-bit I/O expander for I2C-bus)<br>
      <ul>
        <li>arguments: <code>&lt;port&gt; &lt;0|1|off|on&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; PCFGpio 128 on</code></li>
      </ul>
      Port numbering see:
      <a href="https://www.letscontrolit.com/wiki/index.php/PCF8574#Input">
      ESPEasy Wiki PCF8574</a>
    </li><br>

    <li><a name="ESPEasy_device_set_pcfpulse">PCFPulse</a><br>
      Control PCF8574 (8-bit I/O expander for I2C-bus)
      <ul>
        <li>arguments: <code>&lt;port&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; PCFPulse 128 on 10</code></li>
      </ul>
      Port numbering see:
      <a href="https://www.letscontrolit.com/wiki/index.php/PCF8574#Input">
      ESPEasy Wiki PCF8574</a>
    </li><br>

    <li><a name="ESPEasy_device_set_pcflongpulse">PCFLongPulse</a><br>
      Control on PCF8574 (8-bit I/O expander for I2C-bus)
      <ul>
        <li>arguments: <code>&lt;port&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; PCFLongPulse 128 on 10</code></li>
      </ul>
      Port numbering see:
      <a href="https://www.letscontrolit.com/wiki/index.php/PCF8574#Input">
      ESPEasy Wiki PCF8574</a>
    </li><br>

    <li><a name="ESPEasy_device_set_mcpgpio">MCPGPIO</a><br>
      Control MCP23017 output pins (16-Bit I/O Expander with Serial Interface)<br>
      <ul>
        <li>arguments: <code>&lt;port&gt; &lt;0|1|off|on&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; MCPGPIO 48 on</code></li>
      </ul>
      Port numbering see:
      <a href="https://www.letscontrolit.com/wiki/index.php/MCP23017#Input">
      ESPEasy Wiki MCP23017</a>
    </li><br>

    <li><a name="ESPEasy_device_set_mcppulse">MCPPulse</a><br>
      Pulse control on MCP23017 output pins (duration in ms)<br>
      <ul>
        <li>arguments: <code>&lt;port&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; MCPPulse 48 on 100</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_mcplongpulse">MCPLongPulse</a><br>
      Longpulse control on MCP23017 output pins (duration in s)<br>
      <ul>
        <li>arguments: <code>&lt;port&gt; &lt;0|1|off|on&gt; &lt;duration&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; MCPLongPulse 48 on 2</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_pcapwm">pcapwm</a><br>
      Control PCA9685 (16-channel / 12-bit PWM I2C-bus controller)<br>
      <ul>
        <li>arguments: <code>&lt;pin 0-15&gt; &lt;level 0-4095&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; pcapwm 15 4095</code></li>
      </ul>
    </li><br>



    <b>ESP Easy motor control commands:</b><br><br>

    <li><a name="ESPEasy_device_set_servo">Servo</a><br>
      Direct control of servo motors<br>
      <ul>
        <li>arguments: <code>&lt;servoNo&gt; &lt;pin&gt; &lt;position&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; servo 1 14 100</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_motorshieldcmd">MotorShieldCMD</a><br>
      Control a DC motor or stepper<br>
      <ul>
        <li>
          arguments: <code>DCMotor &lt;motornumber&gt; &lt;forward|backward|release&gt; &lt;speed&gt;</code><br>
          arguments: <code>Stepper &lt;motornumber&gt; &lt;forward|backward|release&gt; &lt;steps&gt; &lt;single|double|interleave|microstep&gt;</code>
        </li>
        <li>
          example: <code>set &lt;esp&gt; MotorShieldCMD DCMotor 1 forward 10</code><br>
          example: <code>set &lt;esp&gt; MotorShieldCMD Stepper 1 backward 25 single</code>
        </li>
      </ul>
    </li><br>


    <b>ESP Easy display related commands:</b><br><br>

    <li><a name="ESPEasy_device_set_lcd">lcd</a><br>
      Write text messages to LCD screen<br>
      Pay attention to attributes
      <a href="#ESPEasy_device_attr_displaytextencode">displayTextEncode</a> and
      <a href="#ESPEasy_device_attr_displaytextwidth">displayTextWidth</a>.<br>
      <ul>
        <li>arguments: <code>&lt;row&gt; &lt;col&gt; &lt;text&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; lcd 1 1 Test a b c</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_lcdcmd">lcdcmd</a><br>
      Control LCD screen<br>
      <ul>
        <li>arguments: <code>&lt;on|off|clear&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; lcdcmd clear</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_oled">oled</a><br>
      Write text messages to OLED screen<br>
      Pay attention to attributes
      <a href="#ESPEasy_device_attr_displaytextencode">displayTextEncode</a> and
      <a href="#ESPEasy_device_attr_displaytextwidth">displayTextWidth</a>.<br>
      <ul>
        <li>arguments: <code>&lt;row&gt; &lt;col&gt; &lt;text&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; oled 1 1 Test a b c</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_oledcmd">oledcmd</a><br>
      Control OLED screen<br>
      <ul>
        <li>arguments: <code>&lt;on|off|clear&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; oledcmd clear</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_oledframedcmd">oledframedcmd</a><br>
      Switch oledframed on/off<br>
      <ul>
        <li>arguments: <code>&lt;on|off&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; oledframedcmd on</code></li>
      </ul>
    </li><br>


    <b>ESP Easy DMX related commands:</b><br><br>

    <li><a name="ESPEasy_device_set_dmx">dmx</a><br>
      Send DMX commands to a device<br>
      <ul>
        <li>arguments: <code>&lt;on|off|log|value|channel=value[,value][...]&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; dmx 1=255,2=127</code></li>
      </ul>
    </li><br>


    <b>ESP Easy LED/Lights related commands:</b><br><br>

    <li><a name="ESPEasy_device_set_lights">Lights</a> (plugin can be found <a
      href="https://github.com/ddtlabs/ESPEasy-Plugin-Lights target="_NEW">here</a>)<br>
      Control a rgb or ct light<br>
      <ul>
        <li>arguments: <code>&lt;rgb|ct|pct|on|off|toggle&gt; [&lt;hex-rgb|color-temp|pct-value&gt;] [&lt;fading time&gt;]</code></li>
        <li>examples:<br>
          <code>set &lt;esp&gt; lights rgb aa00aa</code><br>
          <code>set &lt;esp&gt; lights rgb aa00aa 10</code><br>
          <code>set &lt;esp&gt; lights ct 3200</code><br>
          <code>set &lt;esp&gt; lights ct 3200 10</code><br>
          <code>set &lt;esp&gt; lights pct 50</code><br>
          <code>set &lt;esp&gt; lights on</code><br>
          <code>set &lt;esp&gt; lights off</code><br>
          <code>set &lt;esp&gt; lights toggle</code><br>
        </li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_nfx">nfx</a> (plugin can be found
      <a target="_blank" href="https://github.com/djcysmic/NeopixelBusFX">here</a>)<br>
      Control nfx plugin. Note: To use FHEMWEB's colorpicker and slider widgets you have to set
      Attribut <a href="ESPEasy_device_attr_maplightscmds">mapLightCmds</a> to nfx.
      <ul>
        <li>arguments: <code>
        <table>
          <tr><td>all</td>         <td>&lt;rrggbb&gt; [fadetime] [delay +/-ms]</td></tr>
          <tr><td>bgcolor</td>     <td>&lt;rrggbb&gt;</td></tr>
          <tr><td>ct</td>          <td>&lt;ct&gt; [fadetime] [pct bri]</td></tr>
          <tr><td>colorfade</td>   <td>&lt;rrggbb_start&gt; &lt;rrggbb_end&gt; [startpixel] [endpixel]</td></tr>
          <tr><td>comet</td>       <td>&lt;rrggbb&gt; [speed +/- 0-50]</td></tr>
          <tr><td>count</td>       <td>&lt;value&gt;</td></tr>
          <tr><td>dim</td>         <td>&lt;value 0-255&gt;</td></tr>
          <tr><td>dualscan</td>    <td>&lt;rrggbb&gt; [rrggbb background] [speed 0-50]</td></tr>
          <tr><td>fade</td>        <td>&lt;rrggbb&gt; [fadetime ms] [delay +/-ms]</td></tr>
          <tr><td>fadedelay</td>   <td>&lt;value in +/-ms&gt;</td></tr>
          <tr><td>fadetime</td>    <td>&lt;value in ms&gt;</td></tr>
          <tr><td>faketv</td>      <td>[startpixel] [endpixel]</td></tr>
          <tr><td>fire</td>        <td>[fps] [brightness 0-255] [cooling 20-100] [sparking 50-200]</td></tr>
          <tr><td>kitt</td>        <td>&lt;rrggbb&gt; [speed 0-50]</td></tr>
          <tr><td>line</td>        <td>&lt;startpixel&gt; &lt;endpixel&gt; &lt;rrggbb&gt;</td></tr>
          <tr><td>off</td>         <td>[fadetime] [delay +/-ms]</td></tr>
          <tr><td>on</td>          <td>[fadetime] [delay +/-ms]</td></tr>
          <tr><td>one</td>         <td>&lt;pixel&gt; &lt;rrggbb&gt;</td></tr>
          <tr><td>pct</td>         <td>&lt;pct&gt; [fadetime]</td></tr>
          <tr><td>rainbow</td>     <td>[speed +/- 0-50]</td></tr>
          <tr><td>rgb</td>         <td>&lt;rrggbb&gt; [fadetime] [delay +/-ms]</td></tr>
          <tr><td>scan</td>        <td>&lt;rrggbb&gt; [rrggbb background] [speed 0-50]</td></tr>
          <tr><td>simpleclock</td> <td>[bigtickcolor] [smalltickcolor] [hourcolor] [minutecolor] [secondcolor]</td></tr>
          <tr><td>sparkle</td>     <td>&lt;rrggbb&gt; [rrggbb background] [speed 0-50]</td></tr>
          <tr><td>speed</td>       <td>&lt;value 0-50&gt;</td></tr>
          <tr><td>stop</td>        <td></td></tr>
          <tr><td>theatre</td>     <td>&lt;rrggbb&gt; [rrggbb background] [speed +/- 0-50]</td></tr>
          <tr><td>toggle</td>      <td>[fadetime]</td></tr>
          <tr><td>twinkle</td>     <td>&lt;rrggbb&gt; [rrggbb background] [speed 0-50]</td></tr>
          <tr><td>twinklefade</td> <td>&lt;rrggbb&gt; [number of pixels] [speed 0-50]</td></tr>
          <tr><td>wipe</td>        <td>&lt;rrggbb&gt; [rrggbb dot] [speed +/- 0-50]</td></tr>
        </table>
        </code></li>

        <li>examples:<br>
          <code>
          set &lt;esp&gt; nfx all 00ff00 100<br>
          set &lt;esp&gt; nfx rgb aa00ff 1000 10<br>
          set &lt;esp&gt; nfx line 0 100 f0f0f0c<br>
          </code>
        </li>
        <li>examples with attribut mapLightCmds set to nfx:<br>
          <code>
          set &lt;esp&gt; all 00ff00 100<br>
          set &lt;esp&gt; rgb aa00ff 1000 10<br>
          set &lt;esp&gt; line 0 100 f0f0f0c<br>
          </code>
        </li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_candle">candle</a><br>
      Control candle rgb plugin<br>
      <ul>
      <li>arguments:
        <code>CANDLE:&lt;FlameType&gt;:&lt;Color&gt;:&lt;Brightness&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; CANDLE:4:FF0000:200</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_neopixel">neopixel</a><br>
      Control neopixel plugin (single LED)<br>
      <ul>
        <li>arguments: <code>&lt;led nr&gt; &lt;red 0-255&gt; &lt;green 0-255&gt; &lt;blue 0-255&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; neopixel 1 255 255 255</code></li>
      </ul>
      </li><br>

    <li><a name="ESPEasy_device_set_neopixelall">neopixelall</a><br>
      Control neopixel plugin (all together)<br>
      <ul>
        <li>arguments: <code>&lt;red 0-255&gt; &lt;green 0-255&gt; &lt;blue 0-255&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; neopixelall 255 255 255</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_neopixelline">neopixelline</a><br>
      Control neopixel plugin (line)<br>
      <ul>
        <li>arguments: <code>&lt;start led no&gt; &lt;stop led no&gt; &lt;red 0-255&gt; &lt;green 0-255&gt; &lt;blue 0-255&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; neopixelline 1 5 0 127 255</code></li>
      </ul>
    </li><br>


    <b>ESP Easy sound related commands:</b><br><br>

    <li><a name="ESPEasy_device_set_tone">tone</a><br>
      Play a tone on a pin via a speaker or piezo element (ESPEasy &gt;=
      2.0.0-dev6)
      <br>
      <ul>
        <li>arguments: <code>&lt;pin&gt; &lt;freq Hz&gt; &lt;duration s&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; tone 14 4000 1</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_rtttl">rtttl</a><br>
      Play melodies via <a target="_NEW"
      href="https://en.wikipedia.org/wiki/Ring_Tone_Transfer_Language#Technical_specification">RTTTL</a>
      (ESPEasy &gt;= 2.0.0-dev6)
      <br>
      <ul>
        <li>arguments: &lt;rtttl&gt; &lt;pin&gt;:&lt;rtttl codes&gt;</li>
        <li>example: <code>set &lt;esp&gt; rtttl 14:d=10,o=6,b=180,c,e,g</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_buzzer">buzzer</a><br>
      Beep a short time<br>
      <ul>
        <li>arguments: <code>none</code></li>
        <li>example: <code>set &lt;esp&gt; buzzer</code></li>
      </ul>
    </li><br>


    <b>ESP Easy miscellaneous commands:</b><br><br>

    <li><a name="ESPEasy_device_set_irsend">irsend</a><br>
      Send ir codes via "Infrared Transmit" Plugin<br>
      Supported protocols are: NEC, JVC, RC5, RC6, SAMSUNG, SONY, PANASONIC at
      the moment. As long as official documentation is missing you can find
      some details here:
      <a href="http://www.letscontrolit.com/forum/viewtopic.php?f=5&amp;t=328" target="_NEW">
      IR Transmitter thread #1</a> and
      <a
      href="https://www.letscontrolit.com/forum/viewtopic.php?t=328&amp;start=61" target="_NEW">
      IR Transmitter thread #61</a>.<br>
      <ul>
        <li>
          arguments: <code>&lt;NEC|JVC|RC5|RC6|SAMSUNG|SONY|PANASONIC&gt; &lt;hex code&gt; &lt;bit length&gt;</code><br>
          arguments: <code>&lt;RAW&gt; &lt;B32 raw&gt; &lt;frequenz&gt; &lt;pulse length&gt; &lt;blank length&gt;</code>
        </li>
        <li>
          example: <code>set &lt;esp&gt; irsend NEC 7E81542B 32</code><br>
          example: <code>set &lt;esp&gt; irsend RAW 3U0GGL8AGGK588A22K58ALALALAGL1A22LAK45ALALALALALALALALAL1AK5 38 512 256</code>
        </li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_reboot">reboot</a><br>
      Used to reboot your ESP<br>
      <ul>
        <li>arguments: <code>none</code></li>
        <li>example: <code>set &lt;esp&gt; reboot</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_serialsend">serialsend</a><br>
      Used for ser2net plugin<br>
      <ul>
        <li>arguments: <code>&lt;string&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; serialsend test</code></li>
      </ul>
    </li><br>


    <b>ESP Easy administrative commands</b> (be careful !!!):<br><br>

    <li><a name="ESPEasy_device_set_erase">erase</a><br>
      Wipe out ESP flash memory<br>
      <ul>
        <li>arguments: <code>none</code></li>
        <li>example: <code>set &lt;esp&gt; erase</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_reset">reset</a><br>
      Do a factory reset on the ESP<br>
      <ul>
        <li>arguments: <code>none</code></li>
        <li>example: <code>set &lt;esp&gt; reset</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_resetflashwritecounter">resetflashwritecounter</a><br>
      Used to reset flash write counter<br>
      <ul>
        <li>arguments: <code>none</code></li>
        <li>example: <code>set &lt;esp&gt; resetflashwritecounter</code></li>
      </ul>
    </li><br>


  <b>ESP Easy rules related commands</b> (Note: These commands may be protected with the ESP Easy 'Admin Passsword'.
    See <a href="#ESPEasy_device_set_adminpassword">set adminpassword</a> for
    details.)<br><br>

    <li><a name="ESPEasy_device_set_deepsleep">deepsleep</a><br>
      Ask ESP to go into deepsleep mode.<br>
      <ul>
        <li>arguments: <code>&lt;duration in is&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_event">event</a><br>
      Trigger an ESP event. Such events can be used in ESP Easy rules.<br>
      <ul>
        <li>arguments: <code>&lt;string&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; event testevent</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_notify">notify</a><br>
      Send a notify message<br>
      <ul>
        <li>arguments: <code>&lt;notify nr&gt; &lt;message&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_publish">publish</a><br>
      Publish a value via MQTT<br>
      <ul>
        <li>arguments: <code>&lt;topic&gt; &lt;value&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_rules">rules</a><br>
      Enable/disable rule processing<br>
      <ul>
        <li>arguments: <code>&lt;0|1|off|on&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_sendto">sendto</a><br>
      Send a command to another ESP<br>
      <ul>
        <li>arguments: <code>&lt;unit nr&gt; &lt;command&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_sendtohttp">sendtohttp</a><br>
      Used to tigger a HTTP URL call<br>
      <ul>
        <li>arguments: <code>none</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_sendtoudp">sendtoudp</a><br>
      Used to tigger a UDP call<br>
      <ul>
        <li>arguments: <code>&lt;ip&gt; &lt;port&gt; &lt;url&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_taskrun">taskrun</a><br>
      Used trigger a taskrun command<br>
      <ul>
        <li>arguments: <code>&lt;task/device nr&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_taskvalueset">taskvalueset</a><br>
      Used to set taskvalueset<br>
      <ul>
        <li>arguments: <code>&lt;task/device nr&gt; &lt;value nr&gt; &lt;value/formula&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_taskvaluesetandrun">taskvaluesetandrun</a><br>
      Used to set taskvaluesetandrun<br>
      <ul>
        <li>arguments: <code>&lt;task/device nr&gt; &lt;value nr&gt; &lt;value/formula&gt;</code></li>
      </ul>
    </li><br>

    <li><a name="ESPEasy_device_set_timerset">timerset</a><br>
      Set an ESP Easy timer<br>
      <ul>
        <li>arguments: <code>&lt;timer nr&gt; &lt;duration in s&gt;</code></li>
      </ul>
    </li><br>


  <b>ESP Easy experimental commands:</b> (The following commands can be changed or removed at any time)<br><br>

    <li><a name="ESPEasy_device_set_rgb">rgb</a><br>
      Used to control a rgb light wo/ an ESPEasy plugin.<br>
      You have to set attribute <a href="#ESPEasy_device_attr_rgbgpios">rgbGPIOs</a> to
      enable this feature. Default colorpicker mode is HSVp but can be adjusted
      with help of attribute <a href="#ESPEasy_device_attr_colorpicker">colorpicker</a>
      to HSV or RGB. Set attribute <a href="#webCmd">webCmd</a> to rgb to
      display a colorpicker in FHEMWEB room view and on detail page.<br>
      <ul>
        <li>
          arguments: <code>&lt;rrggbb&gt;|on|off|toggle</code>
        </li>
        <li>
          examples:<br>
          <code>set &lt;esp&gt; rgb 00FF00</code><br>
          <code>set &lt;esp&gt; rgb on</code><br>
          <code>set &lt;esp&gt; rgb off</code><br>
          <code>set &lt;esp&gt; rgb toggle</code><br>
        </li>
        <li>Full featured example:<br>
          attr &lt;ESP&gt; colorpicker HSVp<br>
          attr &lt;ESP&gt; devStateIcon { ESPEasy_devStateIcon($name) }<br>
          attr &lt;ESP&gt; Interval 30<br>
          attr &lt;ESP&gt; parseCmdResponse status,pwm<br>
          attr &lt;ESP&gt; pollGPIOs D6,D7,D8<br>
          attr &lt;ESP&gt; rgbGPIOs D6,D7,D8<br>
          attr &lt;ESP&gt; webCmd rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:toggle:on:off
        </li>
      </ul>
    </li><br>


  <b>ESP Easy deprecated commands:</b> (will be removed in a later version)<br>
  <br>

    <li><a name="ESPEasy_device_set_status">status</a><br>
      Request esp device status (eg. gpio)<br>
      See attributes: parseCmdResponse, readingPrefixGPIO, readingSuffixGPIOState
      <ul>
        <li>arguments: <code>&lt;pin&gt;</code></li>
        <li>example: <code>set &lt;esp&gt; status 14</code></li>
      </ul>
    </li><br>


  </ul>
    <br><a name="ESPEasy_device_attr"></a>
    <b>Attributes</b> (logical device)<br><br>
  <ul>

    <li><a name="ESPEasy_device_attr_adjustvalue">adjustValue</a><br>
      Used to adjust sensor values<br>
      Must be a space separated list of &lt;reading&gt;:&lt;formula&gt;.
      Reading can be a regexp. Formula can be an arithmetic expression like
      'round(($VALUE-32)*5/9,2)'.
      If $VALUE is omitted in formula then it will be added to the beginning of
      the formula. So you can simple write 'temp:+20' or '.*:*4'<br>
      Modified or ignored values are marked in the system log (verbose 4). Use
      verbose 5 logging to see more details.<br>
      If the used sub function returns 'undef' then the value will be ignored.
      <br>
      The following variables can be used if necessary:
      <ul>
        <li>$VALUE contains the original value</li>
        <li>$READING contains the reading name</li>
        <li>$NAME contains the device name</li>
      </ul>
      Default: none<br>
      Eg. <code>attr ESPxx adjustValue humidity:+0.1
      temperature*:($VALUE-32)*5/9</code><br>
      Eg. <code>attr ESPxx adjustValue
      .*:my_OwnFunction($NAME,$READING,$VALUE)</code><br>
      <br>
      Sample function to ignore negative values:<br>
      <code>
        sub my_OwnFunction($$$) {<br>
          &nbsp;&nbsp;my ($name,$reading,$value) = @_;<br>
          &nbsp;&nbsp;return ($value < 0) ? undef : $value;<br>
        }<br>
      </code>
    </li><br>

    <li><a name="ESPEasy_device_attr_colorpicker">colorpicker</a><br>
      Used to select colorpicker mode<br>
      Possible values: RGB,HSV,HSVp<br>
      Default: HSVp
    </li><br>

    <li><a name="ESPEasy_device_attr_colorpickerctcw">colorpickerCTcw</a><br>
      Used to select ct colorpicker's cold white color temperature in Kelvin<br>
      Possible values: &gt; colorpickerCTww<br>
      Default: 6000
    </li><br>

    <li><a name="ESPEasy_device_attr_colorpickerctww">colorpickerCTww</a><br>
      Used to select ct colorpicker's warm white color temperature in Kelvin<br>
      Possible values: &lt; colorpickerCTcw<br>
      Default: 2000
    </li><br>

    <li><a name="ESPEasy_device_attr_disable">disable</a><br>
      Used to disable device<br>
      Possible values: 0,1<br>
      Default: 0
    </li><br>

    <li><a name="ESPEasy_device_attr_disableRiskyCmds">disableRiskyCmds</a><br>
      Used to disable supposed dangerous set cmds: erase, reset, resetflashwritecounter<br>
      Possible values: 0,1<br>
      Default: 0
    </li><br>

    <li><a name="ESPEasy_device_attr_displaytextencode">displayTextEncode</a><br>
      Used to disable url encoding for text that is send to oled/lcd displays.
      Useful if you want to encode the text by yourself.<br>
      Possible values: 0,1<br>
      Default: 1 (enabled)
    </li><br>

    <li><a name="ESPEasy_device_attr_displaytextwidth">displayTextWidth</a><br>
      Used to specify number of characters per display line.<br>
      If set then all characters before and after the text on the same line will
      be overwritten with spaces. Attribute
      <a href="#ESPEasy_device_attr_displaytextencode">displayTextEncode</a> must not be
      disabled to use this feature. A 128x64px display has 16 characters per
      line if you are using a 8px font.<br>
      Possible values: integer<br>
      Default: 0 (disabled)
    </li><br>

    <li><a name="ESPEasy_device_attr_interval">Interval</a><br>
      Used to set polling interval for presence check and GPIOs polling in
      seconds. 0 will disable this feature.<br>
      Possible values: secs &gt; 10.<br>
      Default: 300
    </li><br>

    <li><a href="#IODev">IODev</a><br>
      Used to select I/O device (ESPEasy Bridge).
    </li><br>

    <li><a name="ESPEasy_device_attr_maplightscmds">mapLightCmds</a><br>
      Enable the following commands and map them to the specified ESPEasy
      command: rgb, ct, pct, on, off, toggle, dim, line, one, all, fade,
      colorfade, rainbow, kitt, comet, theatre, scan, dualscan, twinkle,
      twinklefade, sparkle, wipe, fire, stop, fadetime, fadedelay, count, speed,
      bgcolor. Ask the ESPEasy maintainer to add more if required.<br>
      Needed to use FHEM's colorpicker or slider widgets to control a
      rgb/ct/effect/... plugin.<br>
      required values: <code>a valid set command</code><br>
      eg. <code>attr &lt;esp&gt; mapLightCmds Lights</code>
    </li><br>

    <li><a name="ESPEasy_device_attr_presencecheck">presenceCheck</a><br>
      Used to enable/disable presence check for ESPs<br>
      Presence check determines the presence of a device by readings age. If any
      reading of a device is newer than <a href="#ESPEasy_device_attr_interval">interval</a>
      seconds then it is marked as being present. This kind of check works for
      ESP devices in deep sleep too but require at least 1 reading that is
      updated regularly. Therefore the ESP must send the corresponding data
      regularly (ESP device option "delay").<br>
      Possible values: 0,1<br>
      Default: 1 (enabled)
    </li><br>

    <li>
      <a href="#readingFnAttributes">readingFnAttributes</a>
    </li><br>

    <li><a name="ESPEasy_device_attr_readingswitchtext">readingSwitchText</a><br>
      Map values for readings to on/off instead 0/1 if ESP device is a switch.<br>
      Possible values:<br>
      0: disable mapping.<br>
      1: enable mapping 0-&gt;off / 1-&gt;on<br>
      2: enable inverse mapping 0-&gt;on / 1-&gt;off<br>
      Default: 1
    </li><br>

    <li><a name="ESPEasy_device_attr_rgbgpios">rgbGPIOs</a><br>
      Use to define GPIOs your lamp is conneted to. Must be set to be able to
      use <a href="#ESPEasy_device_set_rgb">rgb</a> set command.<br>
      Possible values: Comma separated tripple of ESP pin numbers or arduino pin
      names<br>
      Eg: 12,13,15<br>
      Eg: D6,D7,D8<br>
      Default: none
    </li><br>

    <li><a name="ESPEasy_device_attr_setstate">setState</a><br>
      Summarize received values in state reading.<br>
      A positive number determines the number of characters used for abbreviated
      reading names. Only readings with an age less than
      <a href="#ESPEasy_device_attr_interval">interval</a> will be considered. If your are
      not satisfied with format or behavior of setState then disable this
      attribute (set to 0) and use global attributes userReadings and/or
      stateFormat to get what you want.<br>
      Possible values: integer &gt;=0<br>
      Default: 3 (enabled with 3 characters abbreviation)
    </li><br>

    <li><a name="ESPEasy_device_attr_userSetCmds">userSetCmds</a><br>
      Can be used to:
      <ul>
      <li>
        Define new, own or unconsidered ESP Easy commands. Note: alternatively
        the set commands <a href="#ESPEasy_device_set_raw">raw</a> or
        <a href="#ESPEasy_device_set_rawsystem">rawsystem</a> can also be used to it.<br>
      </li>
      <li>
        Mapping of secondary commands as primary ones to be able to use FHEM
        widgets or FHEM's <a href="#setExtensions">set extentions</a>.
      </li>
      <li>
        Redefine built-in commands.
      </li>
      </ul><br>

      Argument must be a <a href="https://perldoc.perl.org/perldsc.html#Declaration-of-a-HASH-OF-HASHES">perl hash</a>.
      The following hash keys can be used. An omitted key will be replaced with the appropriate default value.<br>
      <ul>
        <li><code>args:</code> minimum number of required arguments. Default: 0</li>
        <li><code>url:</code> ESPEasy URL to be called. Default: "/control?cmd="</li>
        <li><code>widget:</code> <a href="#widgetOverride">FHEM widget</a> to be
          used for this set command. Default: none
        </li>
        <li><code>cmds:</code> Sub command(s) of specified plugin that will be
          mapped as regular command(s). Must also be a perl hash. Default: none
        </li>
        <li><code>usage:</code> Possible command line arguments. Used in help command and
          syntax check. Required arguments should be enclosed in curly brackets,
          optional arguments in square brackets. Both should be separated by
          spaces. Default: none</li>
        The following usage strings have a special meaning and effect:
        <ul>
          <li>&lt;0|1|off|on&gt;: "on" or "off" will be replaced with "0" or "1"
           in commands send to the ESPEasy device. See attribute
           <a href="#ESPEasy_device_attr_readingswitchtext">readingSwitchText</a>
           for details.</li>
          <li>&lt;pin&gt;: GPIO pin numbers can also be written as
           Arduino/NodeMCU pin names. See get pinMap command.</li>
          <li>&lt;text&gt;: Text will be encoded for use with oled/lcd commands
           to be able to use special characters.</li>
        </ul>
      </ul><br>

      Define new commands:<br>
       <ul>
          <li><code>( myCmd1 =&gt; {} )</code></li>
          <li><code>( myCmd1 =&gt; {}, myCmd2 =&gt; {} )</code></li>
          <li><code>( myCmd3 =&gt; {args =&gt; 2, url =&gt; "/?cmd=", widget=&gt; "",
                    usage =&gt; "&lt;param1&gt; &lt;param2&gt;"} )</code></li>
       </ul>
      <br>

      Define new commands with mapped sub commands:<br>
      This example registers the new commands plugin_a and plugin_b. Both
      commands can be used like any other ESP Easy command (eg. set dev plugin_b on).
      Sub commands rgb, ct, on, off and bri can also be used as regular commands.
      The advantage is that FHEM's <a href="#widgetOverride">widgets</a> and/or
      <a href="#setExtensions">set extentions</a> can be used for these sub
      commands right now.

      <ul><li>
<pre>(
plugin_a =&gt; {
    args  =&gt; 2,
    url   =&gt; "/control?cmd=",
    usage =&gt; "&lt;rgb|ct&gt; <rrggbb|colortemp>",
    cmds  =&gt; {
       rgb =&gt; { args =&gt; 1, usage =&gt; "&lt;rrggbb&gt;", widget =&gt; "colorpicker,HSV" },
       ct  =&gt; { args =&gt; 1, usage =&gt; "&lt;colortemp&gt;", widget =&gt; "colorpicker,CT,2000,10,4000" }
    }
  },
plugin_b =&gt; {
    args  =&gt; 1,
    url   =&gt; "/foo?bar",
    usage =&gt; "&lt;on|off|bri&gt; [bri_value]",
    cmds  =&gt; {
       on  =&gt; { widget =&gt; "noArg" },
       off =&gt; { widget =&gt; "noArg" },
       bri =&gt; { widget =&gt; "knob,min:1,max:100,step:1,linecap:round", usage =&gt; "&lt;0..255&gt;", args =&gt; 1 }
    }
  }
)</pre>
        </li>
      </ul>
    </li>

    <li><a name="ESPEasy_device_attr_useSetExtensions">useSetExtensions</a><br>
      If set to 1 and on/off commands are available (use
      <a href="#ESPEasy_device_attr_userSetCmds">userSetCmds</a> or
      <a href="#eventMap">eventMap</a> if not) then the
      <a href="#setExtensions">set extensions</a> are supported.<br>
      Default: 0 (disabled)<br>
      Eg. attr ESPxx useSetExtensions 1
    </li><br>

  <b>Deprecated attributes:</b><br>
  <br>

    <li><a name="ESPEasy_device_attr_parsecmdresponse">parseCmdResponse</a> (deprecated, may be removed in later versions)<br>
      Used to parse response of commands like GPIO, PWM, STATUS, ...<br>
      Specify a module command or comma separated list of commands as argument.
      Commands are case insensitive.<br>
      Only necessary if ESPEasy software plugins do not send their data
      independently. Useful for commands like STATUS, PWM, ...<br>
      Possible values: &lt;set cmd&gt;[,&lt;set cmd&gt;][,...]<br>
      Default: status<br>
      Eg. <code>attr ESPxx parseCmdResponse status,pwm</code>
    </li><br>

    <li><a name="ESPEasy_device_attr_pollgpios">pollGPIOs</a> (deprecated, may be removed in later versions)<br>
      Used to enable polling for GPIOs status. This polling will do same as
      command 'set ESPxx status &lt;device&gt; &lt;pin&gt;'<br>
      Possible values: GPIO number or comma separated GPIO number list<br>
      Default: none<br>
      Eg. <code>attr ESPxx pollGPIOs 13,D7,D2</code>
    </li>

      <br>
      The following two attributes control naming of readings that are
      generated by help of parseCmdResponse and pollGPIOs (see above)
      <br><br>

    <li><a name="ESPEasy_device_attr_readingprefixgpio">readingPrefixGPIO</a> (deprecated, may be removed in later versions)<br>
      Specifies a prefix for readings based on GPIO numbers. For example:
      "set ESPxx pwm 13 512" will switch GPIO13 into pwm mode and set pwm to
      512. If attribute readingPrefixGPIO is set to PIN and attribut
      <a href="#ESPEasy_device_attr_parsecmdresponse">parseCmdResponse</a> contains pwm
      command then the reading name will be PIN13.<br>
      Possible Values: <code>string</code><br>
      Default: GPIO
    </li><br>

    <li><a name="ESPEasy_device_attr_readingsuffixgpiostate">readingSuffixGPIOState</a> (deprecated, may be removed in later versions)<br>
      Specifies a suffix for the state-reading of GPIOs (see Attribute
      <a href="#ESPEasy_device_attr_pollgpios">pollGPIOs</a>)<br>
      Possible Values: <code>string</code><br>
      Default: no suffix<br>
      Eg. attr ESPxx readingSuffixGPIOState _state
    </li><br>

  </ul>
</ul>

=end html
=cut
