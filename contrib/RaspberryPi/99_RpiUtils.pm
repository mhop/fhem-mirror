##############################################
# $Id: 99_RpiUtils.pm $
#
# Module by Jörg Wiemann
# Corrections by Prof. Dr. Peter A. Henning
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

	my @RamValues = RpiRamSwap("I");
	my %RpiValues =
	(
		"1. CPUTemperature" => RpiTemp("I").' Grad',
		"2. CPUSpeed" => RpiCPUSpeed().' MHz',
		"3. UpTime" => RpiUpTime(),
		"4. RAM" => $RamValues[0],
		"5. Swap" => $RamValues[1],
		"6. FileSystem" => RpiFileSystem("I"),
		"7. Ethernet" => RpiNetwork("I"),
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
	$htmlcode .= "</table></div><br>";
	$htmlcode .= "--------------------------------------------------------------------------";

	
	return $htmlcode;
}

sub
RpiUpTime ()
{

	my @uptime = split(/ /, qx(cat /proc/uptime));
	my $seconds = $uptime[0];
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
	
	return $string;
}

sub
RpiNetwork
{

	my $Para = shift;
	my $network;

	my $dataThroughput = qx(ifconfig eth0 | grep RX\\ bytes);
	$dataThroughput =~ s/RX bytes://;
	$dataThroughput =~ s/TX bytes://;
	$dataThroughput = trim($dataThroughput);

	my @dataThroughput = split(/ /, $dataThroughput);
    
	my $rxRaw = $dataThroughput[0] / 1024 / 1024;
	my $txRaw = $dataThroughput[4] / 1024 / 1024;
	my $rx = sprintf ("%.2f", $rxRaw, 2);
	my $tx = sprintf ("%.2f", $txRaw, 2);
	my $totalRxTx = $rx + $tx;

	if($Para eq "I") {
		$network = "Received: " . $rx . " MB" . "<br>" . "Sent: " . $tx . " MB" . "<br>" . "Total: " . $totalRxTx . " MB";
	} else {
		$network = "R: " . $rx . " S: " . $tx . " T: " . $totalRxTx;
	}
	
	return $network;
}

sub
RpiRamSwap
{
	my $Para = shift;
	my $ram;
	my $swap;
	my $percentage;
	my @retvalues;
	my @speicher = qx(free);
	shift @speicher;

	my ($fs_desc, $total, $used, $free, $shared, $buffers, $cached) = split(/\s+/, trim($speicher[0]));

	shift @speicher;
	my ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim($speicher[0]));

	if($fs_desc2 ne "Swap:"){
	   shift @speicher;
	   ($fs_desc2, $total2, $used2, $free2, $shared2, $buffers2, $cached2) = split(/\s+/, trim($speicher[0]));
	}

	$used = sprintf ("%.2f", $used / 1000);
	$buffers = sprintf ("%.2f", $buffers / 1000);
	$cached = sprintf ("%.2f", $cached / 1000);
	$total = sprintf ("%.2f", $total / 1000);
	$free = sprintf ("%.2f", $free / 1000);

	$used2 = sprintf ("%.2f", $used2 / 1000);
	$total2 = sprintf ("%.2f", $total2 / 1000);
	$free2 = sprintf ("%.2f", $free2 / 1000);

	if($Para eq "I") {
	   $percentage = sprintf ("%.2f", (($used - $buffers - $cached) / $total * 100), 0);
	   $ram = "RAM: " . $percentage . "%" . "<br>" . "Free: " . ($free + $buffers + $cached) . " MB" . "<br>" . "Used: " . ($used - $buffers - $cached) . " MB" . "<br>" . "Total: " . $total . " MB";
	   push (@retvalues, $ram);
	
	   $percentage = sprintf ("%.2f", ($used2 / $total2 * 100), 0);
	   $swap = "Swap: " . $percentage . "%" . "<br>" . "Free: " . $free2 . " MB" . "<br>" . "Used: " . $used2 . " MB" . "<br>" . "Total: " . $total2 . " MB";
	   push (@retvalues, $swap);
	   
	   return @retvalues;

	} elsif($Para eq "R") {
	      $percentage = sprintf ("%.2f", (($used - $buffers - $cached) / $total * 100), 0);
	      $ram = "R: " . $percentage . " F: " . ($free + $buffers + $cached) . " U: " . ($used - $buffers - $cached) . " T: " . $total;
	      return $ram;

	} elsif($Para eq "S") {
	      $percentage = sprintf ("%.2f", ($used2 / $total2 * 100), 0);
	      $swap = "S: " . $percentage . " F: " . $free2 . " U: " . $used2 . " T: " . $total2 . " MB";
	      return $swap;
	} else {
	   return "Fehler";
	}
	return "Fehler";
}

sub
RpiFileSystem
{

	my $Para = shift;
	my $out;
	my @filesystems = qx(df /dev/root);

	shift @filesystems;
	my ($fs_desc, $all, $used, $avail, $fused) = split(/\s+/, $filesystems[0]);

	if($Para eq "I") {
	   $out = "Groesse: ".sprintf ("%.2f", (($all)/1024))." MB <br>"."Benutzt: ".sprintf ("%.2f", (($used)/1024))." MB <br>"."Verfuegbar: ".sprintf ("%.2f", (($avail)/1024))." MB";
	} else {
	   $out = "G: ".sprintf ("%.2f", (($all)/1024))." B: ".sprintf ("%.2f", (($used)/1024))." V: ".sprintf ("%.2f", (($avail)/1024));
	}

	return $out;
}

sub
RpiCPUSpeed
{
	
	my $CPUSpeed = qx(cat /proc/cpuinfo | grep "BogoMIPS" | sed 's/[^0-9\.]//g');
	
	return $CPUSpeed;

}

sub
RpiTemp
{

	my $Para = shift;
	my $Temperatur;

	if($Para eq "I") {
	   $Temperatur = sprintf ("%.2f", qx(cat /sys/class/thermal/thermal_zone0/temp) / 1000);
	} else {
	   $Temperatur = "T: ".sprintf ("%.2f", qx(cat /sys/class/thermal/thermal_zone0/temp) / 1000);
	}
	
	return $Temperatur;
}

1;
