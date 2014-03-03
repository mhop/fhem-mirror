# 30_ENECSYSGW.pm
# ENECSYS Gateway Device
#
# (c) 2014 Arno Willig <akw@bytefeed.de>
#
# $Id$

package main;

use strict;
use warnings;
use POSIX;
use MIME::Base64;
use XML::Simple;

sub ENECSYSGW_Initialize($)
{
	my ($hash) = @_;

	# Provider
	$hash->{ReadFn}		= "ENECSYSGW_Read";
	$hash->{WriteFn}	= "ENECSYSGW_Read";
	$hash->{Clients}	= ":ENECSYSDevice:";

	# Consumer
	$hash->{DefFn}		= "ENECSYSGW_Define";
	$hash->{NOTIFYDEV}	= "global";
	$hash->{NotifyFn}	= "ENECSYSGW_Notify";
	$hash->{UndefFn}	= "ENECSYSGW_Undefine";
	$hash->{AttrList}	= "disable:1";
}

sub ENECSYSGW_Read($@)
{
	my ($hash,$name,$id,$obj)= @_;
	return ENECSYSGW_Call($hash);
}

sub ENECSYSGW_Define($$)
{
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	return "Usage: define <name> ENECSYSGW <host> [interval]"  if(@args < 3);

	my ($name, $type, $host, $interval) = @args;

	$interval = 10 unless defined($interval);
	if ($interval < 5) { $interval = 5; }

	$hash->{STATE} = 'Initialized';
	$hash->{Host} = $host;
	$hash->{INTERVAL} = $interval;
	
	$hash->{Clients} = ":ENECSYSINV:";
	my %matchList = ( "1:ENECSYSINV" => ".*" );
	$hash->{MatchList} = \%matchList;

	if( $init_done ) {
		ENECSYSGW_OpenDev( $hash ) if( !AttrVal($name, "disable", 0) );
	}
	return undef;
}

sub ENECSYSGW_Notify($$)
{
	my ($hash,$dev) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};

	return if($dev->{NAME} ne "global");
	return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
	return undef if( AttrVal($name, "disable", 0) );
	
	ENECSYSGW_OpenDev($hash);
	return undef;
}

sub ENECSYSGW_Undefine($$)
{
	my ($hash,$arg) = @_;
	RemoveInternalTimer($hash);
	return undef;
}

sub ENECSYSGW_OpenDev($)
{
	my ($hash) = @_;
	$hash->{STATE} = 'Connected';
	ENECSYSGW_GetUpdate($hash);
	return undef;
}

sub ENECSYSGW_GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if(!$hash->{LOCAL}) {
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday()+$hash->{INTERVAL}, "ENECSYSGW_GetUpdate", $hash, 0);
	}
	ENECSYSGW_Call($hash);
}

sub ENECSYSGW_Call($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	return undef if($attr{$name} && $attr{$name}{disable});
	my $URL = "http://" . $hash->{Host} . "/ajax.xml";
	my $ret = GetFileFromURL($URL, 5, undef, 1 );
  
	if( !defined($ret) ) {
		return undef;
	} elsif($ret eq '') {
		return undef;
	} elsif($ret =~ /^error:(\d){3}$/) {
		return "HTTP Error Code " . $1;
	}
	my $parser = new XML::Simple;
	my $data = $parser->XMLin($ret,SuppressEmpty => 1);
	my $rmsg = $data->{zigbeeData};
	my $ConnectionStatus = $data->{connectionStatus};
	my $ConnectionUptime = $data->{connectionUptime};
	my $devicesInNetwork = $data->{devicesInNetwork};
	my $timeSinceReset   = $data->{timeSinceReset};
  
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,"ConnectionStatus",$ConnectionStatus);
	readingsBulkUpdate($hash,"ConnectionUptime",$ConnectionUptime);
	readingsBulkUpdate($hash,"devicesInNetwork",$devicesInNetwork);
	readingsBulkUpdate($hash,"timeSinceReset",$timeSinceReset);
	readingsEndUpdate($hash, 1);
	
	# Testing $rmsg = "WS=F4_3BQCaxjQAABMIIQEAAAIrFDADiAAAEAANAywyAOUOApsBJAAAB8";
	
	return undef unless defined $rmsg;

	$rmsg =~ s/\r//g;
	$rmsg =~ s/\n//g;
	$rmsg =~ s/_/\//g;
	$rmsg =~ s/-/+/g;

	readingsSingleUpdate($hash,"rawReading",$rmsg,1);

	if ($rmsg =~ /^WS/  && length($rmsg)==57) {
		$rmsg = unpack('H*', decode_base64(substr($rmsg,3,54))).'A';

		Log3 $name, 4, "$name: Zigbee raw: $rmsg";
	
		my $serial = hex(unpack("H*", pack("V*", unpack("N*", pack("H*", substr($rmsg,0,8))))));
		
		my $dmsg = $rmsg;
		Log3 $name, 4, "$name: $dmsg";
		$hash->{"${name}_MSGCNT"}++;
		$hash->{"${name}_TIME"} = TimeNow();
		$hash->{RAWMSG} = $rmsg;
		my %addvals = (RAWMSG => $rmsg);
		Dispatch($hash, $dmsg, \%addvals);
	}

	if ($rmsg =~ /^WS/  && length($rmsg)!=57) { # other inverter strings (startup?)
		Log3 $name, 4, "$name: Zigbee unknown data";
	}

	if ($rmsg =~ /^WZ/) { # gateway data
		Log3 $name, 4, "$name: Zigbee gateway data";
	}
	return undef;
}

1;

=pod
=begin html

<a name="ENECSYSGW"></a>
<h3>ENECSYSGW</h3>
<ul>
  Module to access the ENECSYS gateway (http://www.ENECSYS.com/products/gateway/).<br /><br />

  The actual micro-inverter devices are defined as <a href="#ENECSYSINV">ENECSYSINV</a> devices.

  <br /><br />
  All newly found inverter devices are autocreated and added to the room ENECSYSINV.


  <br /><br />
  <a name="ENECSYSGW_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ENECSYSGW [&lt;host&gt;] [&lt;interval&gt;]</code><br />
    <br />

    Defines an ENECSYSGW device with address &lt;host&gt;.<br /><br />

    The gateway will be polled every &lt;interval&gt; seconds. The default is 10 and minimum is 5.<br /><br />

    Examples:
    <ul>
      <code>define gateway ENECSYSGW 10.0.1.1</code><br />
    </ul>
  </ul><br />
 </ul><br />

=end html
=cut
