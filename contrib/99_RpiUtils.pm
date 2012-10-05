##############################################
# $Id: 99_RpiUtils.pm $
package main;

use strict;
use warnings;
use POSIX;

sub
RpiUtils_Initialize($$)
{
  my ($hash) = @_;
}

sub
ShowRpiValues ()
{

my @uptime = split(/ /, qx(cat /proc/uptime));
my $seconds = @uptime[0];
my $y = floor($seconds / 60/60/24/365);
my $d = floor($seconds/60/60/24) % 365;
my $h = floor(($seconds / 3600) % 24);
my $m = floor(($seconds / 60) % 60);
my $s = $seconds % 60;

my $string = '';

if($y > 0)
{
   my $yw = $y > 1 ? ' Jahre ' : ' Jahr ';
   $string .= $y . $yw . '<br>';
}

if($d > 0)
{
  my $dw = $d > 1 ? ' Tage ' : ' Tag ';
  $string .= $d . $dw . '<br>';
}

if($h > 0)
{
  my $hw = $h > 1 ? ' Stunden ' : ' Stunde ';
  $string .= $h . $hw. '<br>';
}

if($m > 0)
{
  my $mw = $m > 1 ? ' Minuten ' : ' Minute ';
  $string .= $m . $mw . '<br>';
}

if($s > 0)
{
  my $sw = $s > 1 ? ' Sekunden ' : ' Sekunde ';
  $string .= $s . $sw . '<br>';
}

# my $uptime = "Uptime:\n" . preg_replace('/\s+/',' ',$string);

my $dataThroughput = qx(ifconfig eth0 | grep RX\\ bytes);
$dataThroughput =~ s/RX bytes://;
$dataThroughput =~ s/TX bytes://;
$dataThroughput = trim($dataThroughput);

my @dataThroughput = split(/ /, $dataThroughput);
    
my $rxRaw = $dataThroughput[0] / 1024 / 1024;
my $txRaw = $dataThroughput[4] / 1024 / 1024;
my $rx = sprintf ("%.2f", $rxRaw, 2)." ";
my $tx = sprintf ("%.2f", $txRaw, 2);
my $totalRxTx = $rx + $tx;

my $network = "Received: " . $rx . " MB" . "<br>" . "Sent: " . $tx . " MB" . "<br>" . "Total: " . $totalRxTx . " MB";

my @speicher = qx(free);
shift @speicher;
my ($fs_desc, $total, $used, $free, $shared, $buffers, $cached) = split(/\s+/, trim(@speicher[0]));

shift @speicher;
my ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim(@speicher[0]));
if($fs_desc2 ne "Swap:"){
   shift @speicher;
   ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim(@speicher[0]));
}

$used = $used / 1000;
$buffers = $buffers / 1000;
$cached = $cached / 1000;
$total = $total / 1000;
$free = $free / 1000;

$used2 = $used2 / 1000;
$total2 = $total2 / 1000;
$free2 = $free2 / 1000;

my $percentage = sprintf ("%.2f", (($used - $buffers - $cached) / $total * 100), 0);
my $ram = "RAM: " . $percentage . "%" . "<br>" . "Free: " . ($free + $buffers + $cached) . " MB" . "<br>" . "Used: " . ($used - $buffers - $cached) . " MB" . "<br>" . "Total: " . $total . " MB";
 
$percentage = sprintf ("%.2f", ($used2 / $total2 * 100), 0);
my $swap = "Swap: " . $percentage . "%" . "<br>" . "Free: " . $free2 . " MB" . "<br>" . "Used: " . $used2 . " MB" . "<br>" . "Total: " . $total2 . " MB";

my $Temperatur=sprintf ("%.2f", qx(cat /sys/class/thermal/thermal_zone0/temp) / 1000);

my @filesystems = qx(df /dev/root);
shift @filesystems;
my ($fs_desc, $all, $used, $avail, $fused) = split(/\s+/, @filesystems[0]);
my $out = "Groesse: ".sprintf ("%.2f", (($all)/1024))." MB <br>"."Benutzt: ".sprintf ("%.2f", (($used)/1024))." MB <br>"."Verfuegbar: ".sprintf ("%.2f", (($avail)/1024))." MB";
#sprintf("%0.2f%%",$df_free);

my %RpiValues =
(
   "1. RpiCPUTemperature" => $Temperatur.' Grad',
   "2. RpiCPUSpeed" => substr(qx(cat /proc/cpuinfo | grep BogoMIPS),11).' MHz',
   "3. RpiUpTime" => $string,
   "4. RpiRAM" => $ram,
   "5. RpiSwap" => $swap,
   "6. RpiSD-Card" => $out,
   "7. RpiEthernet" => $network,
);

my $tag;
my $value;
my $div_class="";

my $htmlcode = '<div  class="'.$div_class."\"><table>\n";

foreach $tag (sort keys %RpiValues)
{
 $htmlcode .= "<tr><td valign='top'>$tag : </td><td>$RpiValues{$tag}</td></tr>\n";
}

$htmlcode .= "<tr><td></td></tr>\n";
$htmlcode .= "</table></div>";
return $htmlcode;
}

1;
