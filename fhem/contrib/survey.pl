#!/usr/bin/perl

use strict;
use warnings;
use CGI;

sub collectSubmitted($$@);
sub printChapter($$@);

my @hw = qw(
  ALL3076
  ALL4000T
  ALL4027
  BS
  CM11
  CUL
  CUL_EM
  CUL_FHTTK
  CUL_HM
  CUL_HOERMANN
  CUL_IR
  CUL_MAX
  CUL_RFR
  CUL_TX
  CUL_WS
  ECMD
  ECMDDevice
  EIB
  EM
  EMEM
  EMGZ
  EMWZ
  ESA2000
  EnOcean
  FBAHA
  FBDECT
  FHT
  FHT8V
  FHZ
  FRM
  FRM_AD
  FRM_I2C
  FRM_IN
  FRM_OUT
  FRM_PWM
  FRM_SERVO
  FS20
  HMLAN
  HMS
  HTTPSRV
  HUEBridge
  HUEDevice
  IPCAM
  IPWE
  IT
  Itach_Relay
  KM271
  KS300
  LGTV
  LINDY_HDMI_SWITCH
  LIRC
  LUXTRONIK2
  M232
  M232Counter
  M232Voltage
  MAX
  MAXLAN
  NetIO230B
  OREGON
  OWAD
  OWCOUNT
  OWDevice
  OWFS
  OWID
  OWLCD
  OWMULTI
  OWSWITCH
  OWServer
  OWTEMP
  OWTHERM
  OWX
  POKEYS
  RFXCOM
  RFXMETER
  RFXX10REC
  RSS
  SCIVT
  SISPM
  SIS_PMS
  SML
  STV
  TCM
  TRX
  TRX_ELSE
  TRX_LIGHT
  TRX_SECURITY
  TRX_WEATHER
  TUL
  TellStick
  UNIRoll
  USBWX
  USF1000
  VantagePro2
  WEBCOUNT
  WEBIO
  WEBIO_12DIGITAL
  WEBTHERM
  WS2000
  WS300
  WS3600
  Weather
  X10
  YAMAHA_AVR
  ZWDongle
  ZWave
  xxLG7000

);

my @help = qw(
  CULflash
  Calendar
  DbLog
  FB_CALLMONITOR
  FHEM2FHEM
  FileLog
  HCS
  Heating_Control
  JsonList
  MSG
  MSGFile
  MSGMail
  PID
  PRESENCE
  PachLog
  SUNRISE_EL
  SYSSTAT
  Twilight
  WOL
  XmlList
  at
  autocreate
  average
  backup
  createlog
  dewpoint
  dummy
  fheminfo
  holiday
  notice
  notify
  sequence
  structure
  telnet
  update
  usb
  watchdog
  weblink

);

my @fe = (
  "FHEMRENDERER",
  "HomeMini",
  "android: andFHEM",
  "fheME",
  "iPhone: dhs-computertechnik",
  "iPhone: fhemgw",
  "iPhone: fhemobile",
  "iPhone: phyfhem",
  "myHCE",
  "pgm2/FHEMWEB with SVG",
  "pgm2/FHEMWEB with gnuplot",
  "pgm3",
  "pgm5",

);

my @platform = (
  "Fritz!Box 7170",
  "Fritz!Box 7270",
  "Fritz!Box 7390",
  "NSLU2",
  "OSX",
  "PC: BSD",
  "PC: Linux",
  "PC: Windows",
  "Plug Computer",
  "Raspberry PI",
  "Synology",
  "TuxRadio",

);


my $title = "Used FHEM Modules & Components";

my $q = new CGI;
print $q->header,
      $q->start_html( -title => $title, 
                      -style => {-src=>"../www/pgm2/style.css"}), "\n";

print '<div id="left">', "\n",
  '<div id="menuScrollArea">',"\n",
    '<div id="logo"></div>',"\n",
    '<div id="menu">',"\n",
      '<h3>FHEM survey</h3>', "\n",
     '</div>', "\n",
  '</div>', "\n";

print '<div id="right">',"\n",
      $q->h3("$title"), "\n";


if($q->param('Submit')) {
  my $ret = "";
  $ret .= collectSubmitted("1. User",     0, ("user"));
  $ret .= collectSubmitted("2. Hardware", 1, @hw);
  $ret .= collectSubmitted("3. Helper",   1, @help);
  $ret .= collectSubmitted("4. Frontends",1, @fe);
  $ret .= collectSubmitted("5. Platform", 1, @platform);
  $ret .= collectSubmitted("6. Other",    0, ("other"));


  if(0) {
    $ret =~ s/\n/<br>\n/g;
    print $ret;

  } else {
    require Mail::Send;
    my $msg = Mail::Send->new;
    $msg->to('info-r@koeniglich.de');
    $msg->subject('Formulardaten');
    my $fh = $msg->open;
    print $fh $ret;
    if(!$fh->close) {
      print "Couldn't send message: $!\n";
    } else {
      print "Collected data is forwarded for half-automated evaluation.\n";
    }
  }

  print "</div>\n";
  print $q->end_html;
  exit(0);
}


print "This is a survey to get a feeling which fhem modules are used.<br>";
print "<br>";
print $q->start_form;

##############################################
print $q->h4("User (optional):");
print $q->textfield(-name=>'user', -size=>18, -maxsize=>36);

##############################################
sub
printChapter($$@)
{
  my @arr = @_;
  my $name = shift @arr;
  my $cols = shift @arr;
  @arr = sort(@arr);
  print $q->h4("$name:");
  print "<div id=\"block\">";
  print "<table><tr>";
  foreach(my $i=0; $i < @arr; $i++) {
    print "<td>",$q->checkbox(-name=>"$arr[$i]",-label=>"$arr[$i]"),"</td>";
    print "</tr><tr>\n" if($i % $cols == ($cols-1));
  }
  print "</tr></table>";
  print "</div>";
}

sub
collectSubmitted($$@)
{
  my ($name, $flags, @arr) = @_;
  my $ret = "";
  my @set;
  foreach my $f (@arr) {
    #print "Testing $f ", ($q->param($f) ? $q->param($f) : "UNDEF"), "<br>\n";
    push @set, $f if($q->param($f) && $flags);
    push @set, $q->param($f) if($q->param($f) && !$flags);
  }
  $ret .= join(", '   '", @set) if(@set);
  return "$name\n   '$ret'\n";
}

printChapter("Hardware devices", 4, @hw);
printChapter("Helper modules", 6, @help);
printChapter("Frontends", 3, @fe);
printChapter("Platform", 5, @platform);


##############################################
print $q->h4("Other modules:");
print $q->textfield(-name=>'other', -size=>80, -maxsize=>80);
print "<br><br><br>\n";

print $q->submit('Submit');
print "<br><br><br>\n";

print $q->end_form;
print "</div>\n";
print $q->end_html;
