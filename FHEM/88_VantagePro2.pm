################################################################
#
#  Copyright notice
#
#  (c) 2010 Sacha Gloor (sacha@imp.ch)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

package main;

use strict;
use warnings;
use Data::Dumper;
use Net::Telnet;

sub Log($$);
#####################################

sub
VantagePro2_Initialize($)
{
  my ($hash) = @_;
  # Consumer
  $hash->{DefFn}   = "VantagePro2_Define";
  $hash->{AttrList}= "model:VantagePro2 delay loglevel:0,1,2,3,4,5,6";
}

#####################################

sub
VantagePro2_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);
  Log 5, "VantagePro2 Define: $a[0] $a[1] $a[2] $a[3]";
  return "Define the host as a parameter i.e. VantagePro2"  if(@a < 3);

  my $host = $a[2];
  my $port=$a[3];
  my $delay=$a[4];
  $attr{$name}{delay}=$delay if $delay;
  Log 1, "VantagePro2 device is none, commands will be echoed only" if($host eq "none");
  
  $hash->{Host} = $host;
  $hash->{Port} = $port;
  $hash->{STATE} = "Initialized";

  InternalTimer(gettimeofday()+$delay, "VantagePro2_GetStatus", $hash, 0);
  return undef;

}

#####################################

sub
VantagePro2_GetStatus($)
{
  my ($hash) = @_;
  
  my $buf;

  Log 5, "VantagePro2_GetStatus";
  my $name = $hash->{NAME};
  my $host = $hash->{Host};
  my $port = $hash->{Port};
  my $text='';
  my $err_log='';
  my $answer;
  my $sensor;
  
  my $delay=$attr{$name}{delay}||300;
  InternalTimer(gettimeofday()+$delay, "VantagePro2_GetStatus", $hash, 0);

  my $tel=new Net::Telnet(Host => $host, Port => $port,Timeout => 3, Binmode => 1, Telnetmode => 0, Errmode => "return");

  if(!defined($tel))
  {
  	Log 4,"$name: Error connecting to $host:$port";
  }
  else
  {
	  $tel->print("");
	  $answer=$tel->get();
	  $tel->print("TEST");
	  $answer=$tel->get();
	  $tel->print("LOOP 1");
	  $answer=$tel->get();
	  $tel->close();  


	  my $offset=1;
	  my $t;
	  my $btrend="";

	  $t=substr($answer,$offset+3,1);
	  my ($bartrend)=unpack("c1",$t);

	  $t=substr($answer,$offset+7,2);
	  my ($barometer)=unpack("s2",$t);

          $barometer=sprintf("%.02f",$barometer/1000*2.54);

	  $t=substr($answer,$offset+9,2);
	  my ($itemp)=unpack("s2",$t);

	  $t=substr($answer,$offset+11,1);
	  my ($ihum)=unpack("c1",$t);

	  $t=substr($answer,$offset+12,2);
	  my ($otemp)=unpack("s2",$t);

	  $t=substr($answer,$offset+33,1);
	  my ($ohum)=unpack("c1",$t);

	  $t=substr($answer,$offset+14,1);
	  my ($windspeed)=unpack("c1",$t);

	  $t=substr($answer,$offset+15,1);
	  my ($avgwindspeed)=unpack("c1",$t);

	  $t=substr($answer,$offset+16,2);
	  my ($winddir)=unpack("s1",$t);

	  $t=substr($answer,$offset+41,2);
	  my ($rainrate)=unpack("s2",$t);

	  $t=substr($answer,$offset+43,1);
	  my ($uv)=unpack("c1",$t);

	  $t=substr($answer,$offset+44,2);
	  my ($solar)=unpack("s2",$t);

	  $t=substr($answer,$offset+50,2);
	  my ($drain)=unpack("s2",$t);

	  $t=substr($answer,$offset+52,2);
	  my ($mrain)=unpack("s2",$t);

	  $t=substr($answer,$offset+54,2);
	  my ($yrain)=unpack("s2",$t);

	  $itemp=sprintf("%.02f",(($itemp/10)-32)*5/9);
	  $otemp=sprintf("%.02f",(($otemp/10)-32)*5/9);
	  $rainrate=sprintf("%.02f",$rainrate/5);
	  $windspeed=sprintf("%.02f",$windspeed*1.609);
	  $avgwindspeed=sprintf("%.02f",$avgwindspeed*1.609);
	  $uv=$uv/10;
	  if($bartrend==0) { $btrend="Steady"; }
	  elsif($bartrend==20) { $btrend="Rising Slowly"; }
	  elsif($bartrend==60) { $btrend="Rising Rapidly"; }
	  elsif($bartrend==-20) { $btrend="Falling Slowly"; }
	  elsif($bartrend==-60) { $btrend="Falling Rapidly"; }

	  $text="T-OUT: ".$otemp." T-IN: ".$itemp." H-OUT: ".$ohum." H-IN: ".$ihum." W: ".$windspeed." W-AV: ".$avgwindspeed." WD: ".$winddir." R: ".$rainrate." S: ".$solar." UV: ".$uv." RD: ".$drain." RM: ".$mrain. " RY: ".$yrain." BM: ".$barometer." BT: ".$btrend;
	  my $n=0;

	  Log 4,"$name: $text";
	  if (!$hash->{local}){
	       $sensor="temperature-outside";
	       $hash->{CHANGED}[$n++] = "Temperature Outside: ".$otemp;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $otemp." (Celsius)";;

               $sensor="temperature-inside";
	       $hash->{CHANGED}[$n++] = "Temperature Inside: ".$itemp;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $itemp." (Celsius)";;

		$sensor="humidity outside";
	       $hash->{CHANGED}[$n++] = "Humidity Outside: ".$ohum;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $ohum." (%)";;

		$sensor="humidity inside";
	       $hash->{CHANGED}[$n++] = "Humidity Inside: ".$ihum;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $ihum." (%)";;

		$sensor="windspeed";
	       $hash->{CHANGED}[$n++] = "Wind: ".$windspeed;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $windspeed." (km/h)";;

		$sensor="10 min. average windspeed";
	       $hash->{CHANGED}[$n++] = "10 Min. Wind: ".$avgwindspeed;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $avgwindspeed." (km/h)";;

		$sensor="wind direction";
	       $hash->{CHANGED}[$n++] = "Wind Direction: ".$winddir;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $winddir." (Degrees)";;

		$sensor="solar";
	       $hash->{CHANGED}[$n++] = "Solar: ".$solar;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $solar." (Watt/m^2)";;

		$sensor="UV";
	       $hash->{CHANGED}[$n++] = "UV: ".$uv;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $uv." (UV/Index)";;

		$sensor="rainrate";
	       $hash->{CHANGED}[$n++] = "Rainrate: ".$rainrate;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $rainrate." (mm/h)";;

		$sensor="day rain";
	       $hash->{CHANGED}[$n++] = "Dayrain: ".$drain;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $drain." (mm/day)";;

		$sensor="month rain";
	       $hash->{CHANGED}[$n++] = "Monthrain: ".$mrain;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $mrain." (mm/month)";;

		$sensor="year rain";
	       $hash->{CHANGED}[$n++] = "Yearrain: ".$yrain;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $yrain." (mm/year)";;

		$sensor="barometer";
	       $hash->{CHANGED}[$n++] = "Barometer: ".$barometer;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $barometer." (Millimeters)";;

		$sensor="barometer trend";
	       $hash->{CHANGED}[$n++] = "Barometer Trend: ".$btrend;
	       $hash->{READINGS}{$sensor}{TIME} = TimeNow();
	       $hash->{READINGS}{$sensor}{VAL} = $btrend;

	       DoTrigger($name, undef) if($init_done);    
	  }
	  $hash->{STATE} = $text;
  }
  return($text);
}


1;

