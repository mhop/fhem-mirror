# 30_ENECSYSINV.pm
# ENECSYS Inverter Device
#
# (c) 2014 Arno Willig <akw@bytefeed.de>
#
# $Id$

package main;

use strict;
use warnings;
use POSIX;
use SetExtensions;

sub ENECSYSINV_Initialize($)
{
	my ($hash) = @_;
	# Provider

	# Consumer
	$hash->{Match}		= ".*";
	$hash->{DefFn}		= "ENECSYSINV_Define";
	$hash->{UndefFn}	= "ENECSYSINV_Undefine";
	$hash->{ParseFn}	= "ENECSYSINV_Parse";
	$hash->{AttrList}	= "IODev ".$readingFnAttributes;
                      
	$hash->{AutoCreate}	= { 
			"ENECSYSINV.*" => { 
             		GPLOT  => "power4:Power,",
             		FILTER => "%NAME:dcpower:.*"
             		#ATTR => "event-min-interval:dcpower:120" 
            	} 
        	};
}


sub ENECSYSINV_Define($$)
{
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	my $iodev;
	my $i = 0;
	foreach my $param ( @args ) {
		if ($param =~ m/IODev=(.*)/) {
			$iodev = $1;
    		splice( @args, $i, 1 );
    		last;
		}
		$i++;
	}
	return "Usage: define <name> ENECSYSINV <serial>"  if(@args < 3);

	my ($name, $type, $code, $interval) = @args;

	$hash->{STATE} = 'Initialized';
	$hash->{CODE} = $code;

	AssignIoPort($hash,$iodev) if (!$hash->{IODev});
	if(defined($hash->{IODev}->{NAME})) {
		Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
	} else {
		Log3 $name, 1, "$name: no I/O device";
	}
	$modules{ENECSYSINV}{defptr}{$code} = $hash;
	return undef;
}

sub ENECSYSINV_Undefine($$)
{
	my ($hash,$arg) = @_;
	my $code = $hash->{ID};
	$code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
	delete($modules{ENECSYSINV}{defptr}{$code});
	return undef;
}

sub ENECSYSINV_Parse($$)
{
	my ($iodev, $msg, $local) = @_;
	my $ioName = $iodev->{NAME};

	my $serial = hex(unpack("H*", pack("V*", unpack("N*", pack("H*", substr($msg,0,8))))));


	my $hash = $modules{ENECSYSINV}{defptr}{$serial};
	if(!$hash) {
		my $ret = "UNDEFINED ENECSYSINV_$serial ENECSYSINV $serial";
		Log3 $ioName, 3, "$ret, please define it";
		DoTrigger("global", $ret);
		return "";
	}


  	foreach my $mod (keys %{$modules{ENECSYSINV}{defptr}}) {
   		my $hash = $modules{ENECSYSINV}{defptr}{"$mod"};
	   	if ($hash && $hash->{CODE} == $serial) {
			my $time1 		= hex(substr($msg,18,4));
			my $time2	 	= hex(substr($msg,30,6));
			my $dcCurrent 	= 0.025*hex(substr($msg,46,4)); #25 mA units?
			my $dcPower 	= hex(substr($msg,50,4));
			my $efficiency 	= 0.001*hex(substr($msg,54,4));
			my $acFreq 		= hex(substr($msg,58,2));
			my $acVolt 		= hex(substr($msg,60,4));
			my $temperature = hex(substr($msg,64,2));
			my $lifekWh 	= (0.001*hex(substr($msg,66,4)))+hex(substr($msg,70,4));
			my $acPower 	= $dcPower * $efficiency;
			my $dcVolt 		= sprintf("%0.2f",$dcPower / $dcCurrent);
				
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,"dccurrent",$dcCurrent);
			readingsBulkUpdate($hash,"dcpower",$dcPower);
			readingsBulkUpdate($hash,"dcvolt",$dcVolt);
			readingsBulkUpdate($hash,"acfrequency",$acFreq);
			readingsBulkUpdate($hash,"acvolt",$acVolt);
			readingsBulkUpdate($hash,"acpower",$acPower);
			readingsBulkUpdate($hash,"lifetime",$lifekWh);
			readingsBulkUpdate($hash,"efficiency",$efficiency);
			readingsBulkUpdate($hash,"temperature",$temperature);
			readingsBulkUpdate($hash,"state",$dcPower);
			readingsEndUpdate($hash, 1);
			
			return $hash->{NAME};

		}
	}
}
1;

=pod
=begin html

<a name="ENECSYSINV"></a>
<h3>ENECSYSINV</h3>
<ul>
  <br />
  <a name="ENECSYSINV_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ENECSYSINV &lt;id&gt; [&lt;interval&gt;]</code><br />
    <br />

    Defines an micro-inverter device connected to an <a href="#ENECSYSGW">ENECSYSGW</a>.<br /><br />

    Examples:
    <ul>
      <code>define SolarPanel1 ENECSYSINV 100123456</code><br />
    </ul>
  </ul><br />

  <a name="ENECSYSINV_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>acfrequency<br />
    the alternating current frequency reported from the device. Should be around 50 Hz in Europe.</li>
    <li>acpower<br />
    the alternating current power</li>
    <li>acvolt<br />
    the alternating current voltage</li>
    <li>dccurrent<br />
    the direct current</li>
    <li>dcpower<br />
    the direct current power</li>
    <li>dcvolt<br />
    the direct current voltage</li>
    <li>efficiency<br />
    the efficiency of the inverter</li>
    <li>lifetime<br />
    the sum of collected energy of the inverter</li>
    <li>temperature<br />
    the temperature of the inverter</li>
    <li>state<br />
    the current state (equal to dcpower) </li>
  </ul><br />


</ul><br />

=end html
=cut
