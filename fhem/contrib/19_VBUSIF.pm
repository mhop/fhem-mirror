# 19_VBUSIF.pm
# VBUS LAN Adapter Device
#
# (c) 2014 Arno Willig <akw@bytefeed.de>
# (c) 2015 Frank Wurdinger <frank@wurdinger.de>
# (c) 2015 Adrian Freihofer <adrian.freihofer gmail com>

package main;

use strict;
use warnings;
use POSIX;
use Data::Dumper;
use Device::SerialPort;

sub VBUSIF_Read($@);
sub VBUSIF_Write($$$);
sub VBUSIF_Ready($);

sub VBUSIF_getDevList($$);


sub VBUSIF_Initialize($)
{
	my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
	$hash->{ReadFn}     = "VBUSIF_Read";
	$hash->{WriteFn}    = "VBUSIF_Write";
	$hash->{ReadyFn}    = "VBUSIF_Ready";
	$hash->{UndefFn}    = "VBUSIF_Undef";
	$hash->{ShutdownFn} = "VBUSIF_Undef";

# Normal devices
	$hash->{DefFn}      = "VBUSIF_Define";
	$hash->{AttrList}   = "dummy:1,0";
}


sub VBUSIF_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t]+", $def);

	if(@a != 3) {
		return "wrong syntax: define <name> VBUSIF [<hostname:7053> or <dev>]";
	}

	my $name = $a[0];
	my $dev = $a[2];
	$hash->{Clients} = ":VBUSDEV:";
	my %matchList = ( "1:VBUSDEV" => ".*" );
	$hash->{MatchList} = \%matchList;

	DevIo_CloseDev($hash);
	$hash->{DeviceName} = $dev;
	my @dev_name = split('@', $dev);
	if ( -c ${dev_name}[0]) {
		$hash->{DeviceType} = "Serial";
	} else {
		$hash->{DeviceType} = "Net";
	}

	my $ret = DevIo_OpenDev($hash, 0, "VBUSIF_DoInit");
	return $ret;
}

sub VBUSIF_DoInit($)
{
	my $hash = shift;
	if ($hash->{DeviceType} eq "Net" ) {
		my $name = $hash->{NAME};
		delete $hash->{HANDLE}; # else reregister fails / RELEASE is deadly

		my $conn = $hash->{TCPDev};
		$conn->autoflush(1);
		$conn->getline();
		$conn->write("PASS vbus\n");
#		$conn->write("PASS !Cs536939$\n");
		$conn->getline();
		$conn->write("DATA\n");
		$conn->getline();
	}
	return undef;
}

sub VBUSIF_Undef($@)
{
	my ($hash, $arg) = @_;
	if ($hash->{DeviceType} eq "Net" ) {
		VBUSIF_Write($hash, "QUIT\n", "");  # RELEASE
	}
	DevIo_CloseDev($hash);
	return undef;
}

sub VBUSIF_Write($$$)
{
	my ($hash,$fn,$msg) = @_;
	DevIo_SimpleWrite($hash, $msg, 1);
}


sub VBUSIF_Read($@)
{
	my ($hash, $local, $regexp) = @_;
	my $buf = ($local ? $local : DevIo_SimpleRead($hash));
	return "" if(!defined($buf));
	my $name = $hash->{NAME};
	$buf = unpack('H*', $buf);
	my $data = ($hash->{PARTIAL} ? $hash->{PARTIAL} : "");

	Log3 $hash->{NAME}, 5, ,"received buffer: $buf";

	$data .= $buf;

	my $msg;
	my $idx;
	$idx = index($data,"aa");
	if ($idx>=0) {
		
		$data = substr($data,$idx); # Cut off beginning

		$idx = index($data,"aa",2); # Find next message

		if ($idx>0) {

			$idx +=1 if (substr($data,$idx,3) eq "aaa"); # Message endet mit a

			$msg = substr($data,0,$idx);  # vollstaendiges Payload
			$data = substr($data,$idx); # erster Teil des naechsten Payloads 
			Log3 $hash->{NAME}, 4, ,"completed Message: $msg";

			my $protoVersion = substr($msg,10,2);

			if ($protoVersion == "10" && length($msg)>=20) {
				my $frameCount = hex(substr($msg,16,2));
				my $headerCRC  = hex(substr($msg,18,2));

				my $crc = 0;
				for (my $j = 1; $j<=8;$j++) {
					$crc += hex(substr($msg,$j*2,2));
				}
				$crc = ($crc ^ 0xff) & 0x7f;
				if ($headerCRC != $crc) {
					Log 3,"$name: Wrong checksum: $crc != $headerCRC";
				} 
				else {
					my $len = 20+12*$frameCount; # 20 Byte Header + 12 Byte per frame
					if ($len != length($msg) && length($msg) != 223) {
 					   Log 4,"$name: Wrong message length: $len != ".length($msg);
					} else {
						if(length($msg) == 223) {
							$msg = $msg."a";
						}
						my $payload = VBUSIF_DecodePayload($hash,$msg);
						if (defined $payload) {
							$msg = substr($msg,0,20).$payload;

							$hash->{"${name}_MSGCNT"}++;
							$hash->{"${name}_TIME"} = TimeNow();
							$hash->{RAWMSG} = $msg;
							my %addvals = (RAWMSG => $msg);
							Log3 $hash->{NAME}, 4, ,"Payload ready to dispatch: $msg";
							Dispatch($hash, $msg, \%addvals) if($init_done);
  						}
					}
				}

			}
			if ($protoVersion == "20") {
#				my $command    = substr($msg,14,2).substr($msg,12,2);
#				my $dataPntId  = substr($msg,16,4);
#				my $dataPntVal = substr($msg,20,8);
#				my $septet     = substr($msg,28,2);
#				my $checksum   = substr($msg,30,2);
#				TODO use septet
#				TODO validate checksum
#				TODO Understand protocol
			}
		}
	}

	$hash->{PARTIAL} = $data;
#	return $msg if(defined($local));
	return undef;
}

sub VBUSIF_Ready($)
{
	my ($hash) = @_;
	return DevIo_OpenDev($hash, 1, "VBUSIF_DoInit") if($hash->{STATE} eq "disconnected");
	return 0;
}


sub VBUSIF_DecodePayload($@)
{
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};

	my $frameCount = hex(substr($msg,16,2));
	my $payload = "";
	for (my $i = 0; $i < $frameCount; $i++) {
		my $septet   = hex(substr($msg,28+$i*12,2));
		my $frameCRC = hex(substr($msg,30+$i*12,2));

		my $crc = (0x7f - $septet) & 0x7f;
		for (my $j = 0; $j<4;$j++) {
			my $ch = hex(substr($msg,20+$i*12+$j*2,2));
			$ch |= 0x80 if ($septet & (1 << $j));
			$crc = ($crc - $ch) & 0x7f;
			$payload .= chr($ch);
		}

		if ($crc != $frameCRC) {
		   Log 3,"$name: Wrong checksum: $crc != $frameCRC";
			return undef;
		}
	}
	return unpack('H*', $payload);
}

1;

=pod
=item device
=begin html

<a name="VBUSIF"></a>
<h3>VBUSIF</h3>
<ul>
  This module connects to the RESOL VBUS LAN or Serial Port adapter.
  It serves as the "physical" counterpart to the <a href="#VBUSDevice">VBUSDevice</a>
  devices.
  <br /><br />
  <a name="VBUSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; VBUS &lt;device&gt;</code>
  <br />
  <br />
  &lt;device&gt; is a &lt;host&gt;:&lt;port&gt; combination, where
  &lt;host&gt; is the address of the RESOL LAN Adapter and &lt;port&gt; 7053.
  <br /><br />
  Examples:
  <ul>
    <code>define vbus VBUSLAN 192.168.1.69:7053</code>
     <br /><br />
	<code>define vbus VBUSIF /dev/ttyS0</code>
  </ul>
  </ul>
  <br />
</ul>

=end html

=cut
