# $Id$
##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

#use Switch;
require "44_S7_Client.pm";

my %gets = (

	#  "libnodaveversion"   => ""
);

sub _isfloat {
	my $val = shift;

	#  return $val =~ m/^\d+.\d+$/;
	return $val =~ m/^[-+]?\d*\.?\d*$/;

	#[-+]?[0-9]*\.?[0-9]*
}

#####################################
sub S7_ARead_Initialize($) {
	my $hash = shift @_;

	# Provider

	# Consumer
	$hash->{Match} = "^AR";

	$hash->{DefFn}   = "S7_ARead_Define";
	$hash->{UndefFn} = "S7_ARead_Undef";
	$hash->{ParseFn} = "S7_ARead_Parse";

	$hash->{AttrFn} = "S7_ARead_Attr";

	$hash->{AttrList} = "IODev offset multiplicator " . $readingFnAttributes;

	main::LoadModule("S7");
}

#####################################
sub S7_ARead_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my ( $name, $area, $DB, $start, $datatype );

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
"wrong syntax : define <name> S7_ARead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

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
"wrong syntax : define <name> S7_ARead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

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
"wrong syntax : define <name> S7_ARead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

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
"wrong syntax : define <name> S7_ARead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

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
"wrong syntax : define <name> S7_ARead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		else {
			my $msg =
"wrong syntax : define <name> S7_ARead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

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

		if (   $area ne "inputs"
			&& $area ne "outputs"
			&& $area ne "flags"
			&& $area ne "db" )
		{
			my $msg =
"wrong syntax: define <name> S7_ARead {inputs|outputs|flags|db} <DB> <start> {u8|s8|u16|s16|u32|s32|float} \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

			Log3 undef, 2, $msg;
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
"wrong syntax: define <name> S7_ARead {inputs|outputs|flags|db} <DB> <start> {u8|s8|u16|s16|u32|s32|float} \n Only for Logo7 or Logo8:\n define <name> S7_ARead {AI|AM|AQ|NAI|NAQ}";

			Log3 undef, 2, $msg;
			return $msg;
		}
	}

	$hash->{AREA}     = $area;
	$hash->{DB}       = $DB;
	$hash->{ADDRESS}  = $start;
	$hash->{DATATYPE} = $datatype;

	if ( $datatype eq "u16" || $datatype eq "s16" ) {
		$hash->{LENGTH} = 2;
	}
	elsif ( $datatype eq "u32" || $datatype eq "s32" || $datatype eq "float" ) {
		$hash->{LENGTH} = 4;
	}
	else {
		$hash->{LENGTH} = 1;
	}

	my $ID = "$area $DB";

	if ( !defined( $modules{S7_ARead}{defptr}{$ID} ) ) {
		my @b = ();
		push( @b, $hash );
		$modules{S7_ARead}{defptr}{$ID} = \@b;

	}
	else {
		push( @{ $modules{S7_ARead}{defptr}{$ID} }, $hash );
	}

	$hash->{IODev}{dirty} = 1;
	Log3 $name, 4,
	  "S7_ARead (" . $hash->{IODev}{NAME} . "): define $name Adress:$start";

	return undef;
}
#####################################
sub S7_ARead_Undef($$) {
	my ( $hash, $name ) = @_;

	Log3 $name, 4,
	    "S7_ARead ("
	  . $hash->{IODev}{NAME}
	  . "): undef "
	  . $hash->{NAME}
	  . " Adress:"
	  . $hash->{ADDRESS};
	delete( $modules{S7_ARead}{defptr} );

	return undef;
}

#####################################
sub S7_ARead_Parse($$) {
	my ( $hash, $rmsg ) = @_;
	my $name = $hash->{NAME};

	my @a = split( "[ \t][ \t]*", $rmsg );
	my @list;

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

	Log3 $name, 5, "$name S7_ARead_Parse $rmsg";

	my @clientList = split( ",", $clientNames );

	if ( int(@clientList) > 0 ) {
		my @Writebuffer = unpack( "C" x $length,
			pack( "H2" x $length, split( ",", $hexbuffer ) ) );

		#my $b = pack( "C" x $length, @Writebuffer );
		my $now = gettimeofday();
		foreach my $clientName (@clientList) {

			my $h = $defs{$clientName};

			if (   $h->{TYPE} eq "S7_ARead"
				&& $start <= $h->{ADDRESS}
				&& $start + $length >= $h->{ADDRESS} + $h->{LENGTH} )
			{

				my $n = $h->{NAME};   #damit die werte im client gesetzt werden!
				push( @list, $n );

				#aktualisierung des wertes
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
					Log3 $name, 3,
					  "$n S7_ARead: Parse unknown type : ("
					  . $h->{DATATYPE} . ")";
				}

 #now we need to correct the analog value by the parameters attribute and offset
				my $offset = 0;
				if ( defined( $main::attr{$n}{offset} ) ) {
					$offset = $main::attr{$n}{offset};
				}

				my $multi = 1;
				if ( defined( $main::attr{$n}{multiplicator} ) ) {
					$multi = $main::attr{$n}{multiplicator};
				}

				$myI = $myI * $multi + $offset;

				my $reading="state";

#				main::readingsSingleUpdate( $h, $reading, $myI, 1 );

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

		Log3 $name, 3, "$name S7_ARead_Parse going the save way ";
		if ( defined( $modules{S7_ARead}{defptr}{$ID} ) ) {

			foreach my $h ( @{ $modules{S7_ARead}{defptr}{$ID} } ) {
				if ( defined( $main::attr{ $h->{NAME} }{IODev} )
					&& $main::attr{ $h->{NAME} }{IODev} eq $name )
				{
					if (   $start <= $h->{ADDRESS}
						&& $start + $length >= $h->{ADDRESS} + $h->{LENGTH} )
					{

						my $n =
						  $h->{NAME}; #damit die werte im client gesetzt werden!
						push( @list, $n );

						#aktualisierung des wertes

						my @Writebuffer = unpack( "C" x $length,
							pack( "H2" x $length, split( ",", $hexbuffer ) ) );
						my $s = $h->{ADDRESS} - $start;

						#my $b = pack( "C" x $length, @Writebuffer );
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
							  "$name S7_ARead: Parse unknown type : ("
							  . $h->{DATATYPE} . ")";
						}

 #now we need to correct the analog value by the parameters attribute and offset
						my $offset = 0;
						if ( defined( $main::attr{$n}{offset} ) ) {
							$offset = $main::attr{$n}{offset};
						}

						my $multi = 1;
						if ( defined( $main::attr{$n}{multiplicator} ) ) {
							$multi = $main::attr{$n}{multiplicator};
						}

						$myI = $myI * $multi + $offset;

						#my $myResult;

						main::readingsSingleUpdate( $h, "state", $myI, 1 );

						#			main::readingsSingleUpdate($h,"value",$myResult, 1);
					}
				}
			}
		}

	}

	if ( int(@list) == 0 ) {
		Log3 $name, 6, "S7_ARead: Parse no client found ($name) ...";
		push( @list, "" );
	}

	return @list;

}

#####################################

sub S7_ARead_Attr(@) {
	my ( $cmd, $name, $aName, $aVal ) = @_;

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	my $hash = $defs{$name};
	if ( $cmd eq "set" ) {
		if ( $aName eq "offset" || $aName eq "multiplicator" ) {

			if ( !_isfloat($aVal) ) {

				Log3 $name, 3,
"S7_ARead: Invalid $aName in attr $name $aName $aVal ($aVal is not a number): $@";
				return "Invalid $aName $aVal: $aVal is not a number";
			}

		}
		elsif ( $aName eq "IODev" ) {
			if ( defined( $hash->{IODev} ) ) {    #set old master device dirty
				$hash->{IODev}{dirty} = 1;
			}
			if ( defined( $defs{$aVal} ) ) {      #set new master device dirty
				$defs{$aVal}{dirty} = 1;
			}
			Log3 $name, 4, "S7_ARead: IODev for $name is $aVal";

		}

	}
	return undef;
}

1;

=pod
=item summary logical device for a analog reading from a S7/S5
=item summary_DE logisches Device für einen analogen Nur Lese Datenpunkt von einer S5 / S7
=begin html

<a name="S7_ARead"></a>
<h3>S7_ARead</h3>
<ul>

This module is a logical module of the physical module S7. <br>
This module provides analog data (signed / unsigned integer Values).<br>
Note: you have to configure a PLC reading at the physical module (S7) first.<br>
<br><br>
<b>Define</b><br>
<code>define &lt;name&gt; S7_ARead {inputs|outputs|flags|db} &lt;DB&gt; &lt;start&gt; {u8|s8|u16|s16|u32|s32}</code>
<br><br>
<ul>
<li>inputs|outputs|flags|db … defines where to read.</li>
<li>DB … Number of the DB</li>
<li>start … start byte of the reading</li>
<li>{u8|s8|u16|s16|u32|s32} … defines the datatype: </li>
<ul>
	<li>u8 …. unsigned 8 Bit integer</li>
	<li>s8 …. signed 8 Bit integer</li>
	<li>u16 …. unsigned 16 Bit integer</li>
	<li>s16 …. signed 16 Bit integer</li>
	<li>u32 …. unsigned 32 Bit integer</li>
	<li>s32 …. signed 32 Bit integer</li>
</ul>
Note: the required memory area  (start – start + datatypelength) need to be with in the configured PLC reading of the physical module.
</ul>
<br>
<b>Attr</b><br>
The following parameters are used to scale every reading<br>
<ul>
<li>multiplicator</li>
<li>offset</li>
</ul>

newValue = &lt;multiplicator&gt; * Value + &lt;offset&gt;
</ul>
=end html

=begin html_DE

<a name="S7_ARead"></a>
<h3>S7_ARead</h3>
<ul>

This module is a logical module of the physical module S7. <br>
This module provides analog data (signed / unsigned integer Values).<br>
Note: you have to configure a PLC reading at the physical module (S7) first.<br>
<br><br>
<b>Define</b><br>
<code>define &lt;name&gt; S7_ARead {inputs|outputs|flags|db} &lt;DB&gt; &lt;start&gt; {u8|s8|u16|s16|u32|s32}</code>
<br><br>
<ul>
<li>inputs|outputs|flags|db … defines where to read.</li>
<li>DB … Number of the DB</li>
<li>start … start byte of the reading</li>
<li>{u8|s8|u16|s16|u32|s32} … defines the datatype: </li>
<ul>
	<li>u8 …. unsigned 8 Bit integer</li>
	<li>s8 …. signed 8 Bit integer</li>
	<li>u16 …. unsigned 16 Bit integer</li>
	<li>s16 …. signed 16 Bit integer</li>
	<li>u32 …. unsigned 32 Bit integer</li>
	<li>s32 …. signed 32 Bit integer</li>
	<li>float …. 4 byte float </li>
</ul>
Note: the required memory area  (start – start + datatypelength) need to be with in the configured PLC reading of the physical module.
</ul>
<b>Attr</b>
The following parameters are used to scale every reading
<ul>
<li>multiplicator</li>
<li>offset</li>
</ul>
newValue = &lt;multiplicator&gt; * Value + &lt;offset&gt;
</ul>
=end html_DE

=cut
