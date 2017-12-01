# $Id$
##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

require "44_S7_Client.pm";

my %gets = (
	"reading" => "",
	"STATE"   => ""
);

#####################################
sub S7_AWrite_Initialize($) {
	my $hash = shift @_;

	# Consumer
	$hash->{Match} = "^AW";

	$hash->{DefFn}   = "S7_AWrite_Define";
	$hash->{UndefFn} = "S7_AWrite_Undef";

	#	$hash->{GetFn} = "S7_AWrite_Get";
	$hash->{SetFn}   = "S7_AWrite_Set";
	$hash->{ParseFn} = "S7_AWrite_Parse";

	$hash->{AttrFn}   = "S7_AWrite_Attr";
	$hash->{AttrList} = "IODev " . $readingFnAttributes;

	main::LoadModule("S7");
}

#####################################
sub S7_AWrite_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my ( $name, $area, $DB, $start, $datatype, $length );

	$name     = $a[0];

        AssignIoPort($hash);
	
	if ( uc $a[2] =~ m/^[NA](\d*)/ ) {
		my $Offset;
		$area = "db";
		$DB   = 0;
		my $startposition;

		if ( uc $a[2] =~ m/^AI(\d*)/ ) {
			$startposition = 2;
			
			if ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO7" ) {
				$Offset = 926;
			}
			elsif ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1032;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

				Log3 undef, 2, $msg;
				return $msg;
			}

		}
		elsif ( uc $a[2] =~ m/^AQ(\d*)/ ) {
			$startposition = 2;
			
			if ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO7" ) {
				$Offset = 944;
			}
			elsif ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1072;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

				Log3 undef, 2, $msg;
				return $msg;
			}

		}
		elsif ( uc $a[2] =~ m/^AM(\d*)/ ) {
			$startposition = 2;
			
			if ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO7" ) {
				$Offset = 952;
			}
			elsif ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1118;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}

		elsif ( uc $a[2] =~ m/^NAI(\d*)/ ) {
			$startposition = 3;
			if ( $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1262;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		elsif ( uc $a[2] =~ m/^NAQ(\d*)/ ) {
			$startposition = 3;
			if ( $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1406;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		else {
			my $msg =
"wrong syntax : define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

			Log3 undef, 2, $msg;
			return $msg;
		}

		$start = $Offset  + ((int( substr( $a[2], $startposition ) ) - 1)*2);
		$datatype = "u16";

	}
	else {		
	
		$area     = lc $a[2];
		$DB       = $a[3];
		$start    = $a[4];
		$datatype = lc $a[5];

		Log3 $name, 5, "$name S7_AWrite_Define called";

		if (   $area ne "inputs"
			&& $area ne "outputs"
			&& $area ne "flags"
			&& $area ne "db" )
		{
			my $msg =
"$name wrong syntax: define <name> S7_AWrite {inputs|outputs|flags|db} <DB> <start> {u8|s8|u16|s16|u32|s32|float}  \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

			Log3 $name, 2, $msg;
			return $msg;
		}

		if (   $datatype ne "u8"
			&& $datatype ne "s8"
			&& $datatype ne "u16"
			&& $datatype ne "s16"
			&& $datatype ne "u32"
			&& $datatype ne "s32"
			&& $datatype ne "float" )
		{
			my $msg =
"$name wrong syntax: define <name> S7_AWrite {inputs|outputs|flags|db} <DB>  <start> {u8|s8|u16|s16|u32|s32|float}  \n Only for Logo7 or Logo8:\n define <name> S7_AWrite {AI|AM|AQ|NAI|NAQ}";

			Log3 $name, 2, $msg;
			return $msg;
		}


		my $sname = $hash->{IODev}{NAME};

		if ( $datatype eq "u16" || $datatype eq "s16" ) {
			$length = 2;
		}
		elsif ( $datatype eq "u32" || $datatype eq "s32" || $datatype eq "float" ) {
			$length = 4;
		}
		else {
			$length = 1;
		}
	}

	$hash->{AREA}     = $area;
	$hash->{DB}       = $DB;
	$hash->{ADDRESS}  = $start;
	$hash->{DATATYPE} = $datatype;
	$hash->{LENGTH}   = $length;

	my $ID = "$area $DB";

	if ( !defined( $modules{S7_AWrite}{defptr}{$ID} ) ) {
		my @b = ();
		push( @b, $hash );
		$modules{S7_AWrite}{defptr}{$ID} = \@b;

	}
	else {
		push( @{ $modules{S7_AWrite}{defptr}{$ID} }, $hash );
	}

	Log3 $name, 4,
	  "S7_AWrite (" . $hash->{IODev}{NAME} . "): define $name Adress:$start";

	$hash->{IODev}{dirty} = 1;
	return undef;
}

#####################################

sub S7_AWrite_Undef($$) {
	my ( $hash, $name ) = @_;

	Log3 $name, 4,
	    "S7_AWrite ("
	  . $hash->{IODev}{NAME}
	  . "): undef "
	  . $hash->{NAME}
	  . " Adress:"
	  . $hash->{ADDRESS};
	delete( $modules{S7_AWrite}{defptr} );

	return undef;
}

#####################################

sub S7_AWrite_Set($@) {
	my ( $hash, @a ) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 5, "$name S7_AWrite_Set";

	my $minValue;
	my $maxValue;

	my $datatype = $hash->{DATATYPE};

#note I have used a SIEMENS Logo for testing here just the following range was supported.
#  $minValue = 0;
#  $maxValue = 32767;

	if ( $datatype eq "u16" ) {
		$minValue = 0;
		$maxValue = 65535;
	}
	elsif ( $datatype eq "s16" ) {
		$minValue = -32768;
		$maxValue = 32767;
	}
	elsif ( $datatype eq "u32" ) {
		$minValue = 0;
		$maxValue = 4294967295;
	}
	elsif ( $datatype eq "s32" ) {
		$minValue = -2147483648;
		$maxValue = 2147483647;
	}
	elsif ( $datatype eq "float" ) {
		$minValue = -3.402823e38;
		$maxValue = 3.402823e38;
	}
	elsif ( $datatype eq "u8" ) {
		$minValue = 0;
		$maxValue = 255;
	}
	elsif ( $datatype eq "s8" ) {
		$minValue = -128;
		$maxValue = 127;
	}
	else {    #should never happen
		$minValue = -1;
		$maxValue = 0;
	}

	return "$name Need at least one parameter" if ( int(@a) < 2 );
	return " : " if ( $a[1] eq "?" );

	if ( $a[1] ne int( $a[1] ) && $datatype ne "float" ) {
		return "$name You have to enter a numeric value: $minValue - $maxValue";
	}

	my $newValue;
	if ( $datatype ne "float" ) {
		$newValue = int( $a[1] );
	}
	else {
		$newValue = $a[1];
	}

	if ( $newValue < $minValue || $newValue > $maxValue ) {
		return "$name Out of range: $minValue - $maxValue";
	}

	my $sname = $hash->{IODev}{NAME};

	#find the rigth config
	my $area = $hash->{AREA};

	my $length = $hash->{LENGTH};
	my $start  = $hash->{ADDRESS};
	my $dbNR   = $hash->{DB};
	my $shash  = $defs{$sname};

	if ( !defined( $shash->{S7PLCClient} ) ) {
		my $err = "$name S7_AWrite_Set: not connected to PLC ";
		Log3 $name, 3, $err;
		return $err;
	}

	if ( $shash->{STATE} ne "connected to PLC" ) {
		my $err = "$name S7_AWrite_Set: not connected to PLC";
		Log3 $name, 3, $err;
		return $err;
	}

	my $b;

	my $WordLen;

	if ( $datatype eq "u8" ) {
		$b = $shash->{S7PLCClient}->setByteAt( "X", 0, $newValue );
		$WordLen = &S7Client::S7WLByte;
	}
	elsif ( $datatype eq "s8" ) {
		$b = $shash->{S7PLCClient}->setShortAt( "X", 0, $newValue );
		$WordLen = &S7Client::S7WLByte;
	}
	elsif ( $datatype eq "u16" ) {
		$b = $shash->{S7PLCClient}->setWordAt( "XX", 0, $newValue );
		$WordLen = &S7Client::S7WLInt;

		#		$WordLen = &S7Client::S7WLWord;
	}
	elsif ( $datatype eq "s16" ) {
		$b = $shash->{S7PLCClient}->setIntegerAt( "XX", 0, $newValue );
		$WordLen = &S7Client::S7WLInt;

		#		$WordLen = &S7Client::S7WLWord;
	}
	elsif ( $datatype eq "u32" ) {
		$b = $shash->{S7PLCClient}->setDWordAt( "XXXX", 0, $newValue );
		$WordLen = &S7Client::S7WLDInt;

		#		$WordLen = &S7Client::S7WLDWord;
	}
	elsif ( $datatype eq "s32" ) {
		$b = $shash->{S7PLCClient}->setDintAt( "XXXX", 0, $newValue );
		$WordLen = &S7Client::S7WLDInt;

		#		$WordLen = &S7Client::S7WLDWord;
	}
	elsif ( $datatype eq "float" ) {
		$b = $shash->{S7PLCClient}->setFloatAt( "XXXX", 0, $newValue );
		$WordLen = &S7Client::S7WLReal;
	}
	else {
		my $err = "$name S7_AWrite: Parse unknown type : (" . $datatype . ")";
		Log3 $name, 3, $err;
		return $err;
	}

	my $bss = join( ", ", unpack( "H2" x $length, $b ) );
	Log3 $name, 5, "$name S7_AWrite_Set: Write Bytes to PLC: $bss";

	my $writeAreaIndex = S7_getAreaIndex4AreaName($area);
	return $writeAreaIndex if ( $writeAreaIndex ne int($writeAreaIndex) );

	#	my $res = S7_WriteBlockToPLC($shash,$writeAreaIndex,$dbNR,$start,$b);

	my $res =
	  S7_WriteToPLC( $shash, $writeAreaIndex, $dbNR, $start, $WordLen, $b );

	if ( $res == 0 ) {
		main::readingsSingleUpdate( $hash, "state", $newValue, 1 );

	}
	else {
		main::readingsSingleUpdate( $hash, "state", "", 1 );

	}

	return undef;

}

#####################################
sub S7_AWrite_Parse($$) {
	my ( $hash, $rmsg ) = @_;
	my $name = $hash->{NAME};
	my @list;
	my @a = split( "[ \t][ \t]*", $rmsg );

	my ( $area, $DB, $start, $length, $datatype, $s7name, $hexbuffer,
		$clientNames );

	$area        = lc $a[1];
	$DB          = $a[2];
	$start       = $a[3];
	$length      = $a[4];
	$s7name      = $a[5];
	$hexbuffer   = $a[6];
	$clientNames = $a[7];

	my $ID = "$area $DB";

	Log3 $name, 5, "$name S7_AWrite_Parse $rmsg";
	my @clientList = split( ",", $clientNames );

	if ( int(@clientList) > 0 ) {
		my @Writebuffer = unpack( "C" x $length,
			pack( "H2" x $length, split( ",", $hexbuffer ) ) );

		#my $b = pack( "C" x $length, @Writebuffer );
		my $now = gettimeofday();
		foreach my $clientName (@clientList) {

			my $h = $defs{$clientName};

			if (   $h->{TYPE} eq "S7_AWrite"
				&& $start <= $h->{ADDRESS}
				&& $start + $length >= $h->{ADDRESS} + $h->{LENGTH} )
			{

				my $n = $h->{NAME};   #damit die werte im client gesetzt werden!
				push( @list, $n );

				#Aktualisierung des wertes

				my $s = $h->{ADDRESS} - $start;
				my $myI;

				if ( $h->{DATATYPE} eq "u8" ) {
					$myI = $hash->{S7PLCClient}->ByteAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "s8" ) {
					$myI = $hash->{S7PLCClient}->ShortAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "u16" ) {
					$myI = $hash->{S7PLCClient}->WordAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "s16" ) {
					$myI = $hash->{S7PLCClient}->IntegerAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "u32" ) {
					$myI = $hash->{S7PLCClient}->DWordAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "s32" ) {
					$myI = $hash->{S7PLCClient}->DintAt( \@Writebuffer, $s );
				}
				elsif ( $h->{DATATYPE} eq "float" ) {
					$myI = $hash->{S7PLCClient}->FloatAt( \@Writebuffer, $s );
				}
				else {
					Log3 $name, 3, "$name S7_AWrite: Parse unknown type : ("
					  . $h->{DATATYPE} . ")";
				}

				#main::readingsSingleUpdate( $h, "state", $myI, 1 );
				my $reading="state";
				#check event-onchange-reading
				#code wurde der datei fhem.pl funktion readingsBulkUpdate entnommen und adaptiert
				my $attreocr= AttrVal($h->{NAME}, "event-on-change-reading", undef);
				my @a;
				if($attreocr) {
					@a = split(/,/,$attreocr);
					$h->{".attreocr"} = \@a;
				}
				# determine whether the reading is listed in any of the attributes
				my @eocrv;
				my $eocr = $attreocr &&
					( @eocrv = grep { my $l = $_; $l =~ s/:.*//;
										($reading=~ m/^$l$/) ? $_ : undef} @a);
			

			  # check if threshold is given
				my $eocrExists = $eocr;
				if( $eocr
					&& $eocrv[0] =~ m/.*:(.*)/ ) {
				  my $threshold = $1;

				  if($myI =~ m/([\d\.\-eE]+)/ && looks_like_number($1)) { #41083, #62190
					my $mv = $1;
					my $last_value = $h->{".attreocr-threshold$reading"};
					if( !defined($last_value) ) {
					 # $h->{".attreocr-threshold$reading"} = $mv;
					} elsif( abs($mv - $last_value) < $threshold ) {
					  $eocr = 0;
					} else {
					 # $h->{".attreocr-threshold$reading"} = $mv;
					}
				  }
				}
				
				my $changed = !($attreocr)
					  || ($eocr && ($myI ne ReadingsVal($h->{NAME},$reading,"")));				
								

				my $attrminint = AttrVal($h->{NAME}, "event-min-interval", undef);
				my @aa;
				if($attrminint) {
						@aa = split(/,/,$attrminint);
				}								
					
				my @v = grep { my $l = $_;
							   $l =~ s/:.*//;
							   ($reading=~ m/^$l$/) ? $_ : undef
							  } @aa;
				if(@v) {
				  my (undef, $minInt) = split(":", $v[0]);
				  my $le = $h->{".lastTime$reading"};
				  if($le && $now-$le < $minInt) {
					if(!$eocr || ($eocr && $myI eq ReadingsVal($h->{NAME},$reading,""))){
					  $changed = 0;
					#} else {
					#  $hash->{".lastTime$reading"} = $now;
					}
				  } else {
					#$hash->{".lastTime$reading"} = $now;
					$changed = 1 if($eocrExists);
				  }
				}				

				if ($changed == 1) {				
					main::readingsSingleUpdate( $h, $reading, $myI, 1 );
				}
								
			}
		}
	}
	else {

		Log3 $name, 3, "$name S7_AWrite_Parse going the save way ";
		if ( defined( $modules{S7_AWrite}{defptr}{$ID} ) ) {

			foreach my $h ( @{ $modules{S7_AWrite}{defptr}{$ID} } ) {
				if ( defined( $main::attr{ $h->{NAME} }{IODev} )
					&& $main::attr{ $h->{NAME} }{IODev} eq $name )
				{
					if (   $start <= $h->{ADDRESS}
						&& $start + $length >= $h->{ADDRESS} + $h->{LENGTH} )
					{

						my $n =
						  $h->{NAME}; #damit die werte im client gesetzt werden!
						push( @list, $n );

						#Aktualisierung des wertes

						my @Writebuffer = unpack( "C" x $length,
							pack( "H2" x $length, split( ",", $hexbuffer ) ) );
						my $s = $h->{ADDRESS} - $start;

						#	my $b = pack( "C" x $length, @Writebuffer );
						my $myI;

						if ( $h->{DATATYPE} eq "u8" ) {
							$myI =
							  $hash->{S7PLCClient}->ByteAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "s8" ) {
							$myI =
							  $hash->{S7PLCClient}
							  ->ShortAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "u16" ) {
							$myI =
							  $hash->{S7PLCClient}->WordAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "s16" ) {
							$myI =
							  $hash->{S7PLCClient}
							  ->IntegerAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "u32" ) {
							$myI =
							  $hash->{S7PLCClient}
							  ->DWordAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "s32" ) {
							$myI =
							  $hash->{S7PLCClient}->DintAt( \@Writebuffer, $s );
						}
						elsif ( $h->{DATATYPE} eq "float" ) {
							$myI =
							  $hash->{S7PLCClient}
							  ->FloatAt( \@Writebuffer, $s );
						}
						else {
							Log3 $name, 3,
							  "$name S7_AWrite: Parse unknown type : ("
							  . $h->{DATATYPE} . ")";
						}

						main::readingsSingleUpdate( $h, "state", $myI, 1 );
					}
				}

			}
		}
	}
	if ( int(@list) == 0 ) {
		Log3 $name, 5, "S7_AWrite: Parse no client found ($name) ...";
		push( @list, "" );

		#		return undef;
	}

	return @list;

}

#####################################
	sub S7_AWrite_Attr(@) {
		my ( $cmd, $name, $aName, $aVal ) = @_;

		# $cmd can be "del" or "set"
		# $name is device name
		# aName and aVal are Attribute name and value
		my $hash = $defs{$name};
		if ( $cmd eq "set" ) {

			if ( $aName eq "IODev" ) {
				if ( defined( $hash->{IODev} ) ) {  #set old master device dirty
					$hash->{IODev}{dirty} = 1;
				}
				if ( defined( $defs{$aVal} ) ) {    #set new master device dirty
					$defs{$aVal}{dirty} = 1;
				}
				Log3 $name, 4, "S7_AWrite: IODev for $name is $aVal";
			}

		}
		return undef;
	}

	1;

=pod
=item summary logical device for a analog writing to a S7/S5
=item summary_DE logisches Device für einen analogen Lese/Schreib Datenpunkt zu einer S5 / S7

=begin html

<p><a name="S7_AWrite"></a></p>
<h3>S7_AWrite</h3>
<ul>
<ul>This module is a logical module of the physical module S7.</ul>
</ul>
<ul>
<ul>This module provides sending analog data (unsigned integer Values) to the PLC.</ul>
</ul>
<ul>
<ul>Note: you have to configure a PLC writing at the physical modul (S7) first.</ul>
</ul>
<p><br /><br /><strong>Define</strong><br /><code>define &lt;name&gt; S7_AWrite {inputs|outputs|flags|db} &lt;DB&gt; &lt;start&gt; {u8|s8|u16|s16|u32|s32|float}</code><br /><br /></p>
<ul>
<ul>
<ul>
<ul>
<li>db &hellip; defines where to read. Note currently only writing in to DB are supported.</li>
<li>DB &hellip; Number of the DB</li>
<li>start &hellip; start byte of the reading</li>
<li>{u8|s8|u16|s16|u32|s32} &hellip; defines the datatype:</li>
<ul>
<li>u8 &hellip;. unsigned 8 Bit integer</li>
<li>s8 &hellip;. signed 8 Bit integer</li>
<li>u16 &hellip;. unsigned 16 Bit integer</li>
<li>s16 &hellip;. signed 16 Bit integer</li>
<li>u32 &hellip;. unsigned 32 Bit integer</li>
<li>s32 &hellip;. signed 32 Bit integer</li>
<li>float &hellip;. 4 byte float</li>
</ul>
</ul>
Note: the required memory area (start &ndash; start + datatypelength) need to be with in the configured PLC writing of the physical module.</ul>
</ul>
</ul>
<p>Logo 7 / Logo 8</p>
<p style="padding-left: 60px;">For Logo7 / Logo 8 also a short notation is supportet:</p>
<p><code>define &lt;name&gt; S7_AWrite {AI|AM|AQ|NAI|NAQ}X</code></p>
<p><strong>Set</strong><br /><br /><code>set &lt;name&gt; S7_AWrite &lt;value&gt;</code></p>
<ul>
<ul>
<ul>
<li>value &hellip; an numeric value</li>
</ul>
</ul>
</ul>
=end html

=begin html_DE

<p><a name="S7_AWrite"></a></p>
<h3>S7_AWrite</h3>
<ul>
<ul>This module is a logical module of the physical module S7.</ul>
</ul>
<ul>
<ul>This module provides sending analog data (unsigned integer Values) to the PLC.</ul>
</ul>
<ul>
<ul>Note: you have to configure a PLC writing at the physical modul (S7) first.</ul>
</ul>
<p><br /><br /><strong>Define</strong><br /><code>define &lt;name&gt; S7_AWrite {inputs|outputs|flags|db} &lt;DB&gt; &lt;start&gt; {u8|s8|u16|s16|u32|s32|float}</code><br /><br /></p>
<ul>
<ul>
<ul>
<ul>
<li>db &hellip; defines where to read. Note currently only writing in to DB are supported.</li>
<li>DB &hellip; Number of the DB</li>
<li>start &hellip; start byte of the reading</li>
<li>{u8|s8|u16|s16|u32|s32} &hellip; defines the datatype:</li>
<ul>
<li>u8 &hellip;. unsigned 8 Bit integer</li>
<li>s8 &hellip;. signed 8 Bit integer</li>
<li>u16 &hellip;. unsigned 16 Bit integer</li>
<li>s16 &hellip;. signed 16 Bit integer</li>
<li>u32 &hellip;. unsigned 32 Bit integer</li>
<li>s32 &hellip;. signed 32 Bit integer</li>
<li>float &hellip;. 4 byte float</li>
</ul>
</ul>
Note: the required memory area (start &ndash; start + datatypelength) need to be with in the configured PLC writing of the physical module.</ul>
</ul>
</ul>
<p>Logo 7 / Logo 8</p>
<p style="padding-left: 60px;">For Logo7 / Logo 8 also a short notation is supportet:</p>
<p><code>define &lt;name&gt; S7_AWrite {AI|AM|AQ|NAI|NAQ}X</code></p>
<p><strong>Set</strong><br /><br /><code>set &lt;name&gt; S7_AWrite &lt;value&gt;</code></p>
<ul>
<ul>
<ul>
<li>value &hellip; an numeric value</li>
</ul>
</ul>
</ul>=end html_DE

=cut
