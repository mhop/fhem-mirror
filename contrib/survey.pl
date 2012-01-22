#!/usr/bin/perl

use strict;
use warnings;
use CGI;

sub collectSubmitted($$@);
sub printChapter($$@);

my @hw = qw(
  CM11 CUL FHZ HMLAN KM271 LIRC TCM TUL BS CUL_FHTTK USF1000 CUL_HM EIB EnOcean
  FS20 FHT FHT8V HMS KS300 CUL_TX CUL_WS CUL_EM CUL_RFR SIS_PMS CUL_HOERMANN
  OWFS X10 OWTEMP ALL3076 ALL4027 WEBIO WEBIO_12DIGITAL WEBTHERM RFXCOM OREGON
  RFXMETER RFXX10REC RFXELSE WS300 Weather EM EMWZ EMEM EMGZ ESA2000 ECMD
  ECMDDevice SCIVT SISPM USBWX WS3600 M232 xxLG7000 M232Counter LGTV
  M232Voltage WS2000 ALL4000T IPWE VantagePro2
  );
my @help = qw(
  at notify sequence watchdog FileLog FHEM2FHEM PachLog holiday PID autocreate
  dummy structure SUNRISE_EL Utils XmlList updatefhem
  );
my @fe = (
  "FHEMRENDERER", "fheME", "iPhone: dhs-computertechnik", "iPhone: fhemgw",
  "iPhone: fhemobile", "iPhone: phyfhem", "myHCE", "pgm2/FHEMWEB with SVG",
  "pgm2/FHEMWEB with gnuplot", "pgm3", "pgm5", "HomeMini",
  );
my @platform = (
  "PC: Linux", "OSX", "PC: Windows", "PC: BSD", "Fritz!Box 7390", "Fritz!Box 7270",
  "Fritz!Box 7170", "Synology", "NSLU2", "TuxRadio", "Plug Computer",
  );


my $title = "Used FHEM Modules & Components";

my $TIMES_HOME = "/opt/times/TIMES.rko";
#my $TIMES_HOME = "/home/ipqmbe/times/TIMES";

my $q = new CGI;
print $q->header,
      $q->start_html( -title  => $title, -style=>{-src=>"style.css"}), "\n";

print '<div id="left">', "\n",
      '<img src="fhem.png" alt="fhem-logo"/>', "\n",
      '  <h3>FHEM survey</h3>', "\n",
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
