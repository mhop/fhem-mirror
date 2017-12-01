# $Id$
##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


my %gets = (

	#  "libnodaveversion"   => ""
);

#####################################
sub S7_DRead_Initialize($) {
	my $hash = shift @_;

	# Provider

	# Consumer
	$hash->{Match} = "^DR";

	$hash->{DefFn}   = "S7_DRead_Define";
	$hash->{UndefFn} = "S7_DRead_Undef";

	$hash->{ParseFn} = "S7_DRead_Parse";

	$hash->{AttrFn}   = "S7_DRead_Attr";
	$hash->{AttrList} = "IODev " . $readingFnAttributes;

	main::LoadModule("S7");
}

#####################################
sub S7_DRead_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my ( $name, $area, $DB, $start, $position );

	$name = $a[0];

	AssignIoPort($hash);    # logisches modul an physikalisches binden !!!
	my $sname = $hash->{IODev}{NAME};

	my $byte;
	my $bit;

	if ( uc $a[2] =~ m/^[QIMN](\d*)/ ) {
		my $Offset;
		$area = "db";
		$DB   = 0;
		my $startposition;

		if ( uc $a[2] =~ m/^Q(\d*)/ ) {
			$startposition = 1;
			
			if ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO7" ) {
				$Offset = 942;
			}
			elsif ( defined($hash->{IODev}{S7TYPE}) && $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1064;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

				Log3 undef, 2, $msg;
				return $msg;
			}

		}
		elsif ( uc $a[2] =~ m/^I(\d*)/ ) {
			$startposition = 1;
			if ( $hash->{IODev}{S7TYPE} eq "LOGO7" ) {
				$Offset = 923;
			}
			elsif ( $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1024;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		elsif ( uc $a[2] =~ m/^NI(\d*)/ ) {
			$startposition = 2;
			if ( $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1246;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		elsif ( uc $a[2] =~ m/^NQ(\d*)/ ) {
			$startposition = 2;
			if ( $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1390;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		elsif ( uc $a[2] =~ m/^M(\d*)/ ) {
			$startposition = 1;
			if ( $hash->{IODev}{S7TYPE} eq "LOGO7" ) {
				$Offset = 948;
			}
			elsif ( $hash->{IODev}{S7TYPE} eq "LOGO8" ) {
				$Offset = 1104;
			}
			else {
				my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

				Log3 undef, 2, $msg;
				return $msg;
			}
		}
		else {
			my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

			Log3 undef, 2, $msg;
			return $msg;
		}

		$position =
		  ( $Offset * 8 ) + int( substr( $a[2], $startposition ) ) - 1;
		$byte = int( $position / 8 );
		$bit  = ( $position % 8 );

	}
	else {

		$area     = lc $a[2];
		$DB       = $a[3];
		$position = $a[4];

		if (   $area ne "inputs"
			&& $area ne "outputs"
			&& $area ne "flags"
			&& $area ne "db" )
		{
			my $msg =
"wrong syntax : define <name> S7_DRead {inputs|outputs|flags|db} <DB> <address> \n Only for Logo7 or Logo8:\n define <name> S7_DRead {I|Q|M|NI|NQ}1..24";

			Log3 undef, 2, $msg;
			return $msg;
		}

		my @address = split( /\./, $position );
		if ( int(@address) == 2 ) {
			$byte = $address[0];
			$bit  = $address[1];
		}
		else {

			$byte = int( $address[0] / 8 );
			$bit  = ( $address[0] % 8 );
		}
	}

	$hash->{AREA}     = $area;
	$hash->{DB}       = $DB;
	$hash->{POSITION} = ( $byte * 8 ) + $bit;
	$hash->{ADDRESS}  = "$byte.$bit";
	$hash->{LENGTH}   = 1;

	my $ID = "$area $DB";

	if ( !defined( $modules{S7_DRead}{defptr}{$ID} ) ) {
		my @b = ();
		push( @b, $hash );
		$modules{S7_DRead}{defptr}{$ID} = \@b;

	}
	else {
		push( @{ $modules{S7_DRead}{defptr}{$ID} }, $hash );
	}

	$hash->{IODev}{dirty} = 1;

	Log3 $name, 4, "S7_DRead ($sname): define $name Adress:$byte.$bit";
	return undef;
}

#####################################
sub S7_DRead_Undef($$) {
	my ( $hash, $name ) = @_;

	Log3 $name, 4,
	    "S7_DRead ("
	  . $hash->{IODev}{NAME}
	  . "): undef "
	  . $hash->{NAME}
	  . " Adress:"
	  . $hash->{ADDRESS};

	delete( $modules{S7_DRead}{defptr} );

	return undef;
}

#####################################

sub S7_DRead_Parse_new($$) {
	my ( $hash, $rmsg ) = @_;
	my $name;

	if ( defined( $hash->{NAME} ) ) {
		$name = $hash->{NAME};
	}
	else {
		Log3 undef, 2, "S7_DRead: Error ...";
		return undef;
	}

	my @a = split( "[ \t][ \t]*", $rmsg );

	my @list;

	my ( $area, $DB, $start, $length, $datatype, $s7name, $hexbuffer );

	$area      = lc $a[1];
	$DB        = $a[2];
	$start     = $a[3];
	$length    = $a[4];
	$s7name    = $a[5];
	$hexbuffer = $a[6];
	my $ID = "$area $DB";

	Log3 $name, 6, "$name S7_DRead_Parse $rmsg";

	my @Writebuffer =
	  unpack( "C" x $length, pack( "H2" x $length, split( ",", $hexbuffer ) ) );

	#	my $b = pack( "C" x $length, @Writebuffer );

	my $clientArray = $hash->{"Clients"};
	foreach my $h ( @{$clientArray} ) {
		if (   $start <= int( $h->{POSITION} / 8 )
			&& $start + $length >= int( $h->{POSITION} / 8 ) )
		{

			#die Nachricht ist für den client

			my $n = $h->{NAME};    #damit die werte im client gesetzt werden!
			push( @list, $n );

			#aktualisierung des wertes

			my $s = int( $h->{POSITION} / 8 ) - $start;
			my $myI = $hash->{S7PLCClient}->ByteAt( \@Writebuffer, $s );

			Log3 $name, 6, "$name S7_DRead_Parse update $n ";
			
			my $valueText = "";
			
			if ( ( int($myI) & ( 1 << ( $h->{POSITION} % 8 ) ) ) > 0 ) {				
				$valueText = "on";
			}
			else {
				$valueText = "off";
			}

			
			if (ReadingsVal($h->{NAME},"state","") ne $valueText) {				
				main::readingsSingleUpdate( $h, "state", $valueText, 1 );
			} else {
				my $reading="state";
				#value not changed check event-min-interval attribute
				my $attrminint = AttrVal($name, "event-min-interval", undef);
				if($attrminint) {
						my @a = split(/,/,$attrminint);
				}			
				my @v = grep { my $l = $_;
							   $l =~ s/:.*//;
							   ($reading=~ m/^$l$/) ? $_ : undef} @a;
				if(@v) {
				  my (undef, $minInt) = split(":", $v[0]);
				  
				  my $now = gettimeofday();
				  my $le = $hash->{".lastTime$reading"};

				  if($le && $now-$le >= $minInt) {
						main::readingsSingleUpdate( $h, $reading, $valueText, 1 );
				  }
				} 
			
			}
		}
	}

	if ( int(@list) == 0 ) {
		Log3 $name, 6, "S7_DRead: Parse no client found ($name) ...";
		push( @list, "" );
	}

	return @list;

}

#####################################

sub S7_DRead_Parse($$) {
	my ( $hash, $rmsg ) = @_;
	my $name;

	if ( defined( $hash->{NAME} ) ) {
		$name = $hash->{NAME};
	}
	else {
		Log3 undef, 2, "S7_DRead: Error ...";
		return undef;
	}

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

	Log3 $name, 5, "$name S7_DRead_Parse $rmsg";

	# 	         main::readingsBeginUpdate($h);
	#			main::readingsBulkUpdate($h,"reading",$res,1);
	#			main::readingsEndUpdate($h, 1);

	my @clientList = split( ",", $clientNames );

	if ( int(@clientList) > 0 ) {

		my @Writebuffer = unpack( "C" x $length,
			pack( "H2" x $length, split( ",", $hexbuffer ) ) );

		my $now = gettimeofday();
		foreach my $clientName (@clientList) {

			my $h = $defs{$clientName};

			#			if ( defined( $main::attr{ $h->{NAME} }{IODev} )
			#				&& $main::attr{ $h->{NAME} }{IODev} eq $name )
			#			{

			if (   $h->{TYPE} eq "S7_DRead"
				&& $start <= int( $h->{POSITION} / 8 )
				&& $start + $length >= int( $h->{POSITION} / 8 ) )
			{
				push( @list, $clientName )
				  ;    #damit die werte im client gesetzt werden!

				#aktualisierung des wertes
				my $s = int( $h->{POSITION} / 8 ) - $start;

				my $myI = $hash->{S7PLCClient}->ByteAt( \@Writebuffer, $s );

				Log3 $name, 6, "$name S7_DRead_Parse update $clientName ";

#				if ( ( int($myI) & ( 1 << ( $h->{POSITION} % 8 ) ) ) > 0 ) {
#					main::readingsSingleUpdate( $h, "state", "on", 1 );
#				}
#				else {
#					main::readingsSingleUpdate( $h, "state", "off", 1 );
#				}
				
				my $valueText = "";
				my $reading="state";
				
				if ( ( int($myI) & ( 1 << ( $h->{POSITION} % 8 ) ) ) > 0 ) {				
					$valueText = "on";
				}
				else {
					$valueText = "off";
				}

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

				  if($valueText =~ m/([\d\.\-eE]+)/ && looks_like_number($1)) { #41083, #62190
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
					  || ($eocr && ($valueText ne ReadingsVal($h->{NAME},$reading,"")));				
								

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
					if(!$eocr || ($eocr && $valueText eq ReadingsVal($h->{NAME},$reading,""))){
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
					main::readingsSingleUpdate( $h, $reading, $valueText, 1 );
				}
				
				
			}

			#			}
		}
	}
	else {
		Log3 $name, 3, "$name S7_DRead_Parse going the save way ";

		if ( defined( $modules{S7_DRead}{defptr}{$ID} ) ) {

			foreach my $h ( @{ $modules{S7_DRead}{defptr}{$ID} } ) {

				if ( defined( $main::attr{ $h->{NAME} }{IODev} )
					&& $main::attr{ $h->{NAME} }{IODev} eq $name )
				{
					if (   $start <= int( $h->{POSITION} / 8 )
						&& $start + $length >= int( $h->{POSITION} / 8 ) )
					{

						my $n =
						  $h->{NAME}; #damit die werte im client gesetzt werden!
						push( @list, $n );

						#aktualisierung des wertes
						my @Writebuffer = unpack( "C" x $length,
							pack( "H2" x $length, split( ",", $hexbuffer ) ) );
						my $s = int( $h->{POSITION} / 8 ) - $start;

						#my $b = pack( "C" x $length, @Writebuffer );

						my $myI =
						  $hash->{S7PLCClient}->ByteAt( \@Writebuffer, $s );

						Log3 $name, 6, "$name S7_DRead_Parse update $n ";

						if ( ( int($myI) & ( 1 << ( $h->{POSITION} % 8 ) ) ) >
							0 )
						{

							main::readingsSingleUpdate( $h, "state", "on", 1 );

						}
						else {
							main::readingsSingleUpdate( $h, "state", "off", 1 );

						}
					}
				}

			}
		}
	}

	if ( int(@list) == 0 ) {
		Log3 $name, 6, "S7_DRead: Parse no client found ($name) ...";
		push( @list, "" );
	}

	return @list;

}

#####################################
sub S7_DRead_Attr(@) {
	my ( $cmd, $name, $aName, $aVal ) = @_;

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value

	my $hash = $defs{$name};

	if ( $cmd eq "set" ) {

		if ( $aName eq "IODev" ) {
			if ( defined( $hash->{IODev} ) ) { #set old master device dirty
				$hash->{IODev}{dirty} = 1;
			}
			if ( defined( $defs{$aVal} ) ) { #set new master device dirty
				$defs{$aVal}{dirty} = 1;
			}

			Log3 $name, 4, "S7_DRead: IODev for $name is $aVal";
		}

	}
	return undef;
}

#####################################
1;

=pod
=item summary logical device for a digital reading from a S7/S5
=item summary_DE logisches Device für einen binären Nur Lese Datenpunkt von einer S5 / S7
=begin html

<a name="S7_DRead"></a>
<h3>S7_DRead</h3>
<ul>
This module is a logical module of the physical module S7. <br>
This module provides digital data (ON/OFF).<br>
Note: you have to configure a PLC reading at the physical modul (S7) first.<br>
<br><br>
<b>Define</b>
<ul>
<code>define &lt;name&gt; S7_DRead {inputs|outputs|flags|db} &lt;DB&gt; &lt;address&gt;</code>

<ul>
<li>inputs|outputs|flags|db … defines where to read.</li>
<li>DB … Number of the DB</li>
<li>address … address you want to read. bit number to read. Example: 10.3</li>
</ul>
Note: the required memory area need to be with in the configured PLC reading of the physical module.
</ul>

</ul>
=end html

=begin html_DE

<a name="S7_DRead"></a>
<h3>S7_DRead</h3>
<ul>

This module is a logical module of the physical module S7. <br>
This module provides digital data (ON/OFF).<br>
Note: you have to configure a PLC reading at the physical modul (S7) first.<br>
<br><br>
<b>Define</b>
<ul>
<code>define &lt;name&gt; S7_DRead {inputs|outputs|flags|db} &lt;DB&gt; &lt;address&gt;</code>

<ul>
<li>inputs|outputs|flags|db … defines where to read.</li>
<li>DB … Number of the DB</li>
<li>address … address you want to read. bit number to read. Example: 10.3</li>
</ul>
Note: the required memory area need to be with in the configured PLC reading of the physical module.
</ul>
</ul>
=end html_DE

=cut
