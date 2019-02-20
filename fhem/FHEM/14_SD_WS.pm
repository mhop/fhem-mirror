##############################################
# $Id$
#
# The purpose of this module is to support serval
# weather sensors which use various protocol
# Sidey79 & Ralf9  2016 - 2017
# Joerg 2017
# 17.04.2017 WH2 (TFA 30.3157 nur Temp, Hum = 255),es wird das Perlmodul Digest:CRC benoetigt fuer CRC-Pruefung benoetigt
# 29.05.2017 Test ob Digest::CRC installiert
# 22.07.2017 WH2 angepasst
# 21.08.2017 WH2 Abbruch wenn kein "FF" am Anfang
# 18.08.2018 Protokoll 51 - prematch auf genau 10 Nibbles angepasst, Protokoll 33 - prematch auf genau 11 Nibbles angepasst
# 21.08.2018 Modelauswahl hinzugefuegt, da 3 versch. Typen SD_WS_33 --> Batterie-Bit Positionen unterschiedlich (34,35,36)
# 11.09.2018 Plotanlegung korrigiert | doc | temp check war falsch positioniert
# 16.09.2018 neues Protokoll 84: Funk Wetterstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D
# 31.09.2018 neues Protokoll 85: Kombisensor TFA 30.3222.02 fuer Wetterstation TFA 35.1140.01
# 09.12.2018 neues Protokoll 89: Temperatur-/Feuchtesensor TFA 30.3221.02 fuer Wetterstation TFA 35.1140.01
# 06.01.2019 Protokoll 33: Temperatur-/Feuchtesensor TX-EZ6 fuer Wetterstation TZS First Austria hinzugefuegt

package main;


use strict;
use warnings;
# use Digest::CRC qw(crc);
# use Data::Dumper;


sub SD_WS_Initialize($)
{
	my ($hash) = @_;

	$hash->{Match}		= '^W\d+x{0,1}#.*';
	$hash->{DefFn}		= "SD_WS_Define";
	$hash->{UndefFn}	= "SD_WS_Undef";
	$hash->{ParseFn}	= "SD_WS_Parse";
	$hash->{AttrFn}		= "SD_WS_Attr";
	$hash->{AttrList}	= "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
											"model:E0001PA,S522,TX-EZ6,other " .
                      "max-deviation-temp:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
                      "max-deviation-hum:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
											"$readingFnAttributes ";
	$hash->{AutoCreate} =
	{ 
		"SD_WS37_TH.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"},
		"SD_WS50_SM.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,",  autocreateThreshold => "2:180"},
		"BresserTemeo.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
		"SD_WS_51_TH.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
		"SD_WS_58_TH.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:90"},
		"SD_WH2.*"			=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:90"},
		"SD_WS71_T.*"		=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "2:180"},
		"SD_WS_33_T_.*"	=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.* model:other", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "2:180"},
		"SD_WS_33_TH_.*"	=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.* model:other", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
		"SD_WS_84_TH_.*"	=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:120"},
		"SD_WS_85_THW_.*"	=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "4:120"},
		"SD_WS_89_TH.*"	=> { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "3:180"},
	};

}

#############################
sub SD_WS_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	return "wrong syntax: define <name> SD_WS <code> ".int(@a) if(int(@a) < 3 );

	$hash->{CODE} = $a[2];
	$hash->{lastMSG} =  "";
	$hash->{bitMSG} =  "";

	$modules{SD_WS}{defptr}{$a[2]} = $hash;
	$hash->{STATE} = "Defined";

	my $name= $hash->{NAME};
	return undef;
}

#####################################
sub SD_WS_Undef($$)
{
	my ($hash, $name) = @_;
	delete($modules{SD_WS}{defptr}{$hash->{CODE}})
	if(defined($hash->{CODE}) && defined($modules{SD_WS}{defptr}{$hash->{CODE}}));
	return undef;
}


###################################
sub SD_WS_Parse($$)
{
	my ($iohash, $msg) = @_;
	#my $rawData = substr($msg, 2);
	my $name = $iohash->{NAME};
	my $ioname = $iohash->{NAME};
	my ($protocol,$rawData) = split("#",$msg);
	$protocol=~ s/^[WP](\d+)/$1/; # extract protocol
	my $dummyreturnvalue= "Unknown, please report";
	my $hlen = length($rawData);
	my $blen = $hlen * 4;
	my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	my $bitData2;
	my $model;	# wenn im elsif Abschnitt definiert, dann wird der Sensor per AutoCreate angelegt
	my $SensorTyp;
	my $id;
	my $bat;
	my $sendmode;
	my $channel;
	my $rawTemp;
	my $temp;
	my $hum;
	my $windspeed;
	my $trend;
	my $trendTemp;
	my $trendHum;
	
	my %decodingSubs  = (
    50    => # Protocol 50
     # FF550545FF9E
     # FF550541FF9A 
	 # AABCDDEEFFGG
 	 # A = Preamble, always FF
 	 # B = TX type, always 5
 	 # C = Address (5/6/7) > low 2 bits = 1/2/3
 	 # D = Soil moisture 05% 
 	 # E = temperature 
 	 # F = security code, always F
 	 # G = Checksum 55+05+45+FF=19E CRC value = 9E
        {   # subs to decode this
        	sensortype => 'XT300',
        	model => 'SD_WS_50_SM',
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^FF5[0-9A-F]{5}FF[0-9A-F]{2}/); }, 		# prematch
			crcok => sub {my $msg = shift; return 1 if ((hex(substr($msg,2,2))+hex(substr($msg,4,2))+hex(substr($msg,6,2))+hex(substr($msg,8,2))&0xFF) == (hex(substr($msg,10,2))) );  }, 	# crc
			id => sub {my $msg = shift; return (hex(substr($msg,2,2)) &0x03 ); },   							#id
			temp => sub {my $msg = shift; return  ((hex(substr($msg,6,2)))-40)  },								#temp
			hum => sub {my $msg = shift; return hex(substr($msg,4,2));  }, 										#hum
			channel => sub {my (undef,$bitData) = @_; return ( SD_WS_binaryToNumber($bitData,12,15)&0x03 );  }, #channel
			bat 	=> sub { return "";},
        },	
     71 =>	
	# 5C2A909F792F
	# 589A829FDFF4
	# PiiTTTK?CCCC
	# P = Preamble (immer 5 ?)
	# i = ID
	# T = Temperatur
	# K = Kanal (B/A/9)
	# ? = immer F ?
	# C = Checksum ?
		  {
     		sensortype => 'PV-8644',
        	model =>	'SD_WS71_T',
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^5[A-F0-9]{6}F[A-F0-9]{2}/); }, 			# prematch
			crcok => 	sub {return 1; }, 										# crc is unknown
			id => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,4,11); },   		# id
			temp => 	sub {my (undef,$bitData) = @_; return ((SD_WS_binaryToNumber($bitData,12,23) - 2448) / 10); },	#temp
			channel => 	sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,26,27); },			#channel
			hum => 		sub {return undef;},
			bat => 		sub {return undef;},
    	 	 },
     33 =>
   	 	 {
			# Protokollbeschreibung: Conrad Temperatursensor S522 fuer Funk-Thermometer S521B
			# ------------------------------------------------------------------------
			# 0    4    | 8    12   | 16   20   | 24   28   | 32   36   40
			# 1111 1100 | 0001 0110 | 0001 0000 | 0011 0111 | 0100 1001 01
			# iiii iiii | iixx cctt | tttt tttt | tthh hhhh | hhxx bgxx xx
			# i: 10 bit random id (changes on power-loss) - Bit 0 + 1 every 0 ???
			# b: battery indicator (0=>OK, 1=>LOW)
			# g: battery changed (1=>changed) - muss noch genauer getestet werden! ????
			# c: Channel (MSB-first, valid channels are 0x00-0x02 -> 1-3)
			# t: Temperature (MSB-first, BCD, 12 bit unsigned fahrenheit offset by 90 and scaled by 10)
			# h: always 0
			# x: unknown

			# Protokollbeschreibung: renkforce Temperatursensor E0001PA fuer Funk-Wetterstation E0303H2TPR (Conrad)
			# ------------------------------------------------------------------------
			# 0    4    | 8    12   | 16   20   | 24   28   | 32   36   40
			# iiii iiii | iixx cctt | tttt tttt | tthh hhhh | hhsb xxxx xx
			# h: Humidity (MSB-first, BCD, 8 bit relative humidity percentage)
			# s: sendmode (1=>Test push, send manual 0=>automatic send)
			# i: | c: | t: | h: | b: | x: same like S522

			# Protokollbeschreibung: Temperatur-/Fechtesensor TX-EZ6 fuer Wetterstation TZS First Austria
			# ------------------------------------------------------------------------
			# 0    4    | 8    12   | 16   20   | 24   28   | 32   36   40
			# iiii iiii | iiHH cctt | tttt tttt | tthh hhhh | hhsb TTxx xx
			# H: Humidity trend, 00 = equal, 01 = up, 10 = down
			# T: Temperature trend, 00 = equal, 01 = up, 10 = down
			# i: | c: | t: | h: | s: | b: | x: same like E0001PA

			sensortype => 's014/TFA 30.3200/TCM/S522/E0001PA/TX-EZ6',
			model =>	'SD_WS_33_T',
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{11}$/); }, 							# prematch
			crcok => 	sub {return 1;}, 									# crc currently not calculated
			id => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,0,9); },   				# id
			temp => 	sub {my (undef,$bitData) = @_; return round(((SD_WS_binaryToNumber($bitData,22,25)*256 +  SD_WS_binaryToNumber($bitData,18,21)*16 + SD_WS_binaryToNumber($bitData,14,17)) - 1220) * 5 / 90.0 , 1); },	#temp
			hum => 		sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,30,33)*16 + SD_WS_binaryToNumber($bitData,26,29));  }, 					#hum
			channel => 	sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,12,13)+1 );  }, 		#channel
			bat => 		sub {my (undef,$bitData) = @_; return substr($bitData,34,1) eq "0" ? "ok" : "low";},	# other or modul orginal
   	 	 } ,       
     51 =>
   	 	 {
     		sensortype => 'Auriol IAN 275901 / IAN 114324',
        	model =>	'SD_WS_51_TH', 
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{10}$/); }, 							# prematch
			crcok => 	sub {return 1;  }, 																			# crc is unknown
			id => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,0,12); },   				# random id?
	#		sendmode =>	sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,10,11) eq "1" ? "manual" : "auto";  }
			temp => 	sub {my (undef,$bitData) = @_; return round(((SD_WS_binaryToNumber($bitData,16,27)) -1220) *5 /90.0,1); },	#temp
			hum => 		sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,28,31)*10) + (SD_WS_binaryToNumber($bitData,32,35));  }, 		#hum
			channel => 	sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,36,39) );  }, 		#channel
     		bat => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,13) eq "1" ? "low" : "ok";},
      		trend => 	sub {my (undef,$bitData) = @_; return ('neutral', 'rising', 'falling', 'what?')[SD_WS_binaryToNumber($bitData,14,15)];}, 
     # 		sync => 	sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,35,35) eq "1" ? "true" : "false");},
   	 	 }   ,  
       58 => 
   	 	 {
     		sensortype => 'TFA 30.3208.0',
        	model =>	'SD_WS_58_TH', 
			prematch => sub {my $msg = shift; return 1 if ($msg =~ /^45[0-9A-F]{11}/); }, 							# prematch
			crcok => 	sub {   my $msg = shift;
							    my @buff = split(//,substr($msg,index($msg,"45"),10));
							    my $crc_check = substr($msg,index($msg,"45")+10,2);
							    my $mask = 0x7C;
							    my $checksum = 0x64;
							    my $data;
							    my $nibbleCount;
							    for ( $nibbleCount=0; $nibbleCount < scalar @buff; $nibbleCount+=2)
							    {
							        my $bitCnt;
							        if ($nibbleCount+1 <scalar @buff)
							        {
							        	$data = hex($buff[$nibbleCount].$buff[$nibbleCount+1]);
							        } else  {
							        	$data = hex($buff[$nibbleCount]);	
							        }
							        for ( my $bitCnt= 7; $bitCnt >= 0 ; $bitCnt-- )
							        {
							            my $bit;
							            # Rotate mask right
							            $bit = $mask & 1;
							            $mask = ($mask >> 1 ) | ($mask << 7) & 0xFF;
							            if ( $bit )
							            {
							                $mask ^= 0x18 & 0xFF;
							            }
							            # XOR mask into checksum if data bit is 1
							            if ( $data & 0x80 )
							            {
							                $checksum ^= $mask & 0xFF;
							            }
							            $data <<= 1 & 0xFF;
							        }
							    }
							    if ($checksum == hex($crc_check)) {
								    return 1;
							    } else {
							    	return 0;
							    }
							}, 																			
			id => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,8,15); },   							   # random id
			bat => 		sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,16) eq "1" ? "low" : "ok";},  	   # bat?
			channel => 	sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,17,19)+1 );  },						   # channel
			temp => 	sub {my (undef,$bitData) = @_; return round((SD_WS_binaryToNumber($bitData,20,31)-720)*0.0556,1); }, 		   # temp
			hum => 		sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,32,39));  }, 							   # hum
   	 	 }   ,     
		84 =>
			{
				# Protokollbeschreibung: Funk Wetterstation Auriol IAN 283582 (Lidl)
				# ------------------------------------------------------------------------
				# 0    4    | 8    12   | 16   20   | 24   28   | 32   36  
				# 1111 1100 | 0001 0110 | 0001 0000 | 0011 0111 | 0100 1001
				# iiii iiii | hhhh hhhh | bscc tttt | tttt tttt | ???? ????
				# i: 8 bit id (?) - no change after battery change, i have seen two IDs: 0x03 and 0xfe
				# h: 8 bit relative humidity percentage
				# b: 1 bit battery indicator (0=>OK, 1=>LOW)
				# s: 1 bit sendmode 1=manual (button pressed) 0=auto
				# c: 2 bit channel valid channels are 0-2 (1-3)
				# t: 12 bit signed temperature scaled by 10
				# ?: unknown
				# Sensor sends approximately every 30 seconds
				sensortype => 'Auriol IAN 283582',
				model => 'SD_WS_84_TH',
				prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{4}[01245689ACDE]{1}[0-9A-F]{5}$/); },		# valid channel only 0-2
				id =>	sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,0,7); },
				hum => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,8,15); },
				bat => 		sub {my (undef,$bitData) = @_; return substr($bitData,16,1) eq "0" ? "ok" : "low";},
				sendmode =>	sub {my (undef,$bitData) = @_; return substr($bitData,17,1) eq "1" ? "manual" : "auto"; },
				channel => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,18,19)+1 ); },
				temp => sub {	my (undef,$bitData) = @_;
											my $tempraw = SD_WS_binaryToNumber($bitData,20,31);
											$tempraw -= 4096 if ($tempraw > 1023);		# negative
											$tempraw /= 10.0;
											return $tempraw;
										},
				crcok      => sub {return 1;},		# crc test method is so far unknown
   	 	} ,       
		85 =>
			{
				# Protokollbeschreibung: Kombisensor TFA 30.3222.02 fuer Wetterstation TFA 35.1140.01
				# -----------------------------------------------------------------------------------
				# 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40   44   | 48   52   | 56   60   | 64
				# 0000 1001 | 0001 0110 | 0001 0000 | 0000 0111 | 0100 1001 | 0100 0000 | 0100 1001 | 0100 1001 | 1
				# ???? iiii | iiii iiii | iiii iiii | b??? ??yy | tttt tttt | tttt ???? | hhhh hhhh | ???? ???? | ?   message 1
				# ???? iiii | iiii iiii | iiii iiii | b?cc ??yy | wwww wwww | wwww ???? | 0000 0000 | ???? ???? | ?   message 2
				# i: 20 bit random id (changes on power-loss)
				# b:  1 bit battery indicator (0=>OK, 1=>LOW)
				# c:  2 bit channel valid channels are (always 00 stands for channel 1)
				# y:  2 bit typ, 01 - thermo/hygro (message 1), 10 - wind (message 2)
				# t: 12 bit unsigned temperature, offset 500, scaled by 10 - if message 1
				# h:  8 bit relative humidity percentage - if message 1
				# w: 12 bit unsigned windspeed, scaled by 10 - if message 2
				# ?: unknown
				# The sensor sends at intervals of about 30 seconds
				sensortype => 'TFA 30.3222.02',
				model      => 'SD_WS_85_THW',
				prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{16}/); },		# min 16 nibbles
				crcok      => sub {return 1;},		# crc test method is so far unknown
				id         =>	sub {my (undef,$bitData) = @_; return substr($rawData,1,5); },		# 0952CF012B1021DF0
				bat        => sub {my (undef,$bitData) = @_; return substr($bitData,24,1) eq "0" ? "ok" : "low";},
				channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,26,27) + 1 ); },		# unknown
				temp       => sub {my (undef,$bitData) = @_;
														if (substr($bitData,30,2) eq "01") {		# message 1 thermo/hygro
															return ((SD_WS_binaryToNumber($bitData,32,43) - 500) / 10.0);
														} else {
															return undef;
														}
													},
				hum        => sub {my (undef,$bitData) = @_;
														if (substr($bitData,30,2) eq "01") {		# message 1 thermo/hygro
															return SD_WS_binaryToNumber($bitData,48,55);
														} else {
															return undef;
														}
													},
				windspeed  => sub {my (undef,$bitData) = @_;
														if (substr($bitData,30,2) eq "10") {		# message 2 windspeed
															return (SD_WS_binaryToNumber($bitData,32,43) / 10.0);
														} else {
															return undef;
														}
													},
			} ,
		89 =>
			{
				# Protokollbeschreibung: Temperatur-/Feuchtesensor TFA 30.3221.02 fuer Wetterstation TFA 35.1140.01
				# -------------------------------------------------------------------------------------------------
				# 0    4    | 8    12   | 16   20   | 24   28   | 32   36  
				# 0000 1001 | 0001 0110 | 0001 0000 | 0000 0111 | 0100 1001
				# iiii iiii | bscc tttt | tttt tttt | hhhh hhhh | ???? ????
				# i:  8 bit random id (changes on power-loss)
				# b:  1 bit battery indicator (0=>OK, 1=>LOW)
				# s:  1 bit sendmode (0=>auto, 1=>manual)
				# c:  2 bit channel valid channels are 0-2 (1-3)
				# t: 12 bit unsigned temperature, offset 500, scaled by 10
				# h:  8 bit relative humidity percentage
				# ?:  8 bit unknown
				# The sensor sends 3 repetitions at intervals of about 60 seconds
				sensortype => 'TFA 30.3221.02',
				model      => 'SD_WS_89_TH',
				prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{2}[01245689ACDE]{1}[0-9A-F]{7}$/); },		# valid channel only 0-2
				id         =>	sub {my (undef,$bitData) = @_; return substr($rawData,0,2); },
				bat        => sub {my (undef,$bitData) = @_; return substr($bitData,8,1) eq "0" ? "ok" : "low";},
				sendmode   => sub {my (undef,$bitData) = @_; return substr($bitData,9,1) eq "1" ? "manual" : "auto"; },
				channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,10,11) + 1); },
				temp       => sub {my (undef,$bitData) = @_; return ((SD_WS_binaryToNumber($bitData,12,23) - 500) / 10.0); },
				hum        => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,24,31); },
				crcok      => sub {return 1;},		# crc test method is so far unknown
			} ,
    );
    
    	
	Log3 $name, 4, "$name: SD_WS_Parse Protocol: $protocol, rawData: $rawData";
	
	if ($protocol eq "37") {		# Bresser 7009994
		# Protokollbeschreibung:
		# https://github.com/merbanan/rtl_433_tests/tree/master/tests/bresser_3ch
		# The data is grouped in 5 bytes / 10 nibbles
		# ------------------------------------------------------------------------
		# 0         | 8    12   | 16        | 24        | 32
		# 1111 1100 | 0001 0110 | 0001 0000 | 0011 0111 | 0101 1001 0  65.1 F 55 %
		# iiii iiii | bscc tttt | tttt tttt | hhhh hhhh | xxxx xxxx
		# i: 8 bit random id (changes on power-loss)
		# b: battery indicator (0=>OK, 1=>LOW)
		# s: Test/Sync (0=>Normal, 1=>Test-Button pressed / Sync)
		# c: Channel (MSB-first, valid channels are 1-3)
		# t: Temperature (MSB-first, Big-endian)
		#    12 bit unsigned fahrenheit offset by 90 and scaled by 10
		# h: Humidity (MSB-first) 8 bit relative humidity percentage
		# x: checksum (byte1 + byte2 + byte3 + byte4) % 256
		#    Check with e.g. (byte1 + byte2 + byte3 + byte4 - byte5) % 256) = 0
		$model = "SD_WS37_TH";
		$SensorTyp = "Bresser 7009994";
		my $checksum = (SD_WS_binaryToNumber($bitData,0,7) + SD_WS_binaryToNumber($bitData,8,15) + SD_WS_binaryToNumber($bitData,16,23) + SD_WS_binaryToNumber($bitData,24,31)) & 0xFF;
		if ($checksum != SD_WS_binaryToNumber($bitData,32,39)) {
			Log3 $name, 4, "$name: SD_WS37 ERROR - checksum $checksum != ".SD_WS_binaryToNumber($bitData,32,39);
			return "";
		} else {
			Log3 $name, 4, "$name: SD_WS37 checksum ok $checksum = ".SD_WS_binaryToNumber($bitData,32,39);
			$id = SD_WS_binaryToNumber($bitData,0,7);
			$id = sprintf('%02X', $id);           # wandeln nach hex
			$bat = int(substr($bitData,8,1)) eq "0" ? "ok" : "low";		# Batterie-Bit konnte nicht geprueft werden
			$channel = SD_WS_binaryToNumber($bitData,10,11);
			$rawTemp = 	SD_WS_binaryToNumber($bitData,12,23);
			$hum = SD_WS_binaryToNumber($bitData,24,31);
			my $tempFh = $rawTemp / 10 - 90;							# Grad Fahrenheit
			$temp = (($tempFh - 32) * 5 / 9);							# Grad Celsius
 			$temp = sprintf("%.1f", $temp + 0.05);						# round
			Log3 $name, 4, "$name: SD_WS37 tempraw = $rawTemp, temp = $tempFh F, temp = $temp C, Hum = $hum";
			Log3 $name, 4, "$name: SD_WS37 decoded protocol = $protocol ($SensorTyp), sensor id = $id, channel = $channel";
		}
	}
	elsif  ($protocol eq "44" || $protocol eq "44x")	# BresserTemeo
	{
		# 0    4    8    12       20   24   28   32   36   40   44       52   56   60
		# 0101 0111 1001 00010101 0010 0100 0001 1010 1000 0110 11101010 1101 1011 1110 110110010
		# hhhh hhhh ?bcc viiiiiii sttt tttt tttt xxxx xxxx ?BCC VIIIIIII Syyy yyyy yyyy

		# - h humidity / -x checksum
		# - t temp     / -y checksum
		# - c Channel  / -C checksum
		# - V sign     / -V checksum
		# - i 7 bit random id (aendert sich beim Batterie- und Kanalwechsel)  / - I checksum
		# - b battery indicator (0=>OK, 1=>LOW)               / - B checksum
		# - s Test/Sync (0=>Normal, 1=>Test-Button pressed)   / - S checksum
	
		$model= "BresserTemeo";
		$SensorTyp = "BresserTemeo";
		
		#my $binvalue = unpack("B*" ,pack("H*", $rawData));
		my $binvalue = $bitData;
 
		if (length($binvalue) != 72) {
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo length error (72 bits expected)!!!";
			return "";
		}

		# Check what Humidity Prefix (*sigh* Bresser!!!) 
		if ($protocol eq "44")
		{
			$binvalue = "0".$binvalue;
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Humidity <= 79  Flag";
		}
		else
		{
			$binvalue = "1".$binvalue;
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Humidity > 79  Flag";
		}
		
		Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo new bin $binvalue";
	
		my $checksumOkay = 1;
		
		my $hum1Dec = SD_WS_binaryToNumber($binvalue, 0, 3);
		my $hum2Dec = SD_WS_binaryToNumber($binvalue, 4, 7);
		my $checkHum1 = SD_WS_binaryToNumber($binvalue, 32, 35) ^ 0b1111;
		my $checkHum2 = SD_WS_binaryToNumber($binvalue, 36, 39) ^ 0b1111;

		if ($checkHum1 != $hum1Dec || $checkHum2 != $hum2Dec)
		{
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Humidity";
		}
		else
		{
			$hum = $hum1Dec.$hum2Dec;
			if ($hum < 1 || $hum > 100)
			{
				Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Humidity Error. Humidity=$hum";
				return "";
			}
		}

		my $temp1Dec = SD_WS_binaryToNumber($binvalue, 21, 23);
		my $temp2Dec = SD_WS_binaryToNumber($binvalue, 24, 27);
		my $temp3Dec = SD_WS_binaryToNumber($binvalue, 28, 31);
		my $checkTemp1 = SD_WS_binaryToNumber($binvalue, 53, 55) ^ 0b111;
		my $checkTemp2 = SD_WS_binaryToNumber($binvalue, 56, 59) ^ 0b1111;
		my $checkTemp3 = SD_WS_binaryToNumber($binvalue, 60, 63) ^ 0b1111;
		$temp = $temp1Dec.$temp2Dec.".".$temp3Dec;
		$temp +=0; # remove leading zeros
		if ($checkTemp1 != $temp1Dec || $checkTemp2 != $temp2Dec || $checkTemp3 != $temp3Dec)
		{
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Temperature";
			$checksumOkay = 0;
		}
		if ($temp > 60)
		{
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Temperature Error. temp=$temp";
			return "";
		}
		
		my $sign = substr($binvalue,12,1);
		my $checkSign = substr($binvalue,44,1) ^ 0b1;
		
		if ($sign != $checkSign) 
		{
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Sign";
			$checksumOkay = 0;
		}
		else
		{
			if ($sign)
			{
				$temp = 0 - $temp
			}
		}
		
		$bat = substr($binvalue,9,1);
		my $checkBat = substr($binvalue,41,1) ^ 0b1;
		
		if ($bat != $checkBat)
		{
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Bat";
			$bat = undef;
		}
		else
		{
			$bat = ($bat == 0) ? "ok" : "low";
		}
		
		$channel = SD_WS_binaryToNumber($binvalue, 10, 11);
		my $checkChannel = SD_WS_binaryToNumber($binvalue, 42, 43) ^ 0b11;
		$id = SD_WS_binaryToNumber($binvalue, 13, 19);
		my $checkId = SD_WS_binaryToNumber($binvalue, 45, 51) ^ 0b1111111;
		
		if ($channel != $checkChannel || $id != $checkId)
		{
			Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Channel or Id";
			$checksumOkay = 0;
		}
		
		if ($checksumOkay == 0)
		{
			Log3 $iohash, 4, "$name:SD_WS_Parse BresserTemeo checksum error!!! These Values seem incorrect: temp=$temp, channel=$channel, id=$id";
			return "";
		}
		
		$id = sprintf('%02X', $id);           # wandeln nach hex
		Log3 $iohash, 4, "$name: SD_WS_Parse model=$model, temp=$temp, hum=$hum, channel=$channel, id=$id, bat=$bat";
		
	}   elsif  ($protocol eq "64")	# WH2
  {
	  #* Fine Offset Electronics WH2 Temperature/Humidity sensor protocol
	 #* aka Agimex Rosenborg 66796 (sold in Denmark)
	 #* aka ClimeMET CM9088 (Sold in UK)
	 #* aka TFA Dostmann/Wertheim 30.3157 (Temperature only!) (sold in Germany)
	 #* aka ...
	 #*
	 #* The sensor sends two identical packages of 48 bits each ~48s. The bits are PWM modulated with On Off Keying
	 # * The data is grouped in 6 bytes / 12 nibbles
	 #* [pre] [pre] [type] [id] [id] [temp] [temp] [temp] [humi] [humi] [crc] [crc]
	 #*
	 #* pre is always 0xFF
	 #* type is always 0x4 (may be different for different sensor type?)
	 #* id is a random id that is generated when the sensor starts
	 #* temp is 12 bit signed magnitude scaled by 10 celcius
	 #* humi is 8 bit relative humidity percentage
	 #* Based on reverse engineering with gnu-radio and the nice article here:
	 #*  http://lucsmall.com/2012/04/29/weather-station-hacking-part-2/
	 # 0x4A/74 0x70/112 0xEF/239 0xFF/255 0x97/151 | Sensor ID: 0x4A7 | 255% | 239 | OK
	 #{ Dispatch($defs{sduino}, "W64#FF48D0C9FFBA", undef) }
	
	        #* Message Format:
	       #* .- [0] -. .- [1] -. .- [2] -. .- [3] -. .- [4] -.
	       #* |       | |       | |       | |       | |       |
	       #* SSSS.DDDD DDN_.TTTT TTTT.TTTT WHHH.HHHH CCCC.CCCC
	       #* |  | |     ||  |  | |  | |  | ||      | |       |
	       #* |  | |     ||  |  | |  | |  | ||      | `--------- CRC
	       #* |  | |     ||  |  | |  | |  | |`-------- Humidity
	       #* |  | |     ||  |  | |  | |  | |
	       #* |  | |     ||  |  | |  | |  | `---- weak battery
	       #* |  | |     ||  |  | |  | |  |
	       #* |  | |     ||  |  | |  | `----- Temperature T * 0.1
	       #* |  | |     ||  |  | |  |
	       #* |  | |     ||  |  | `---------- Temperature T * 1
	       #* |  | |     ||  |  |
	       #* |  | |     ||  `--------------- Temperature T * 10
	       #* |  | |     | `--- new battery
	       #* |  | `---------- ID
	       #* `---- START = 9
	       #*
	       #*/ 
	      $msg =  substr($msg,0,16);
	      my (undef ,$rawData) = split("#",$msg);
	      my $hlen = length($rawData);
	      my $blen = $hlen * 4;
	      my $msg_vor ="W64#";
	      my $bitData20;
	      my $sign = 0;
	      my $rr2;
	      my $vorpre = -1; 
	      my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	     
	      my $temptyp = substr($bitData,0,8);
	      if( $temptyp == "11111110" ) {
	          $rawData = SD_WS_WH2SHIFT($rawData);
	          $msg = $msg_vor.$rawData;
	          $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	          Log3 $iohash, 4, "$name: SD_WS_WH2_1 msg=$msg length:".length($bitData) ;
	          Log3 $iohash, 4, "$name: SD_WS_WH2_1 bitdata: $bitData" ;
	        } else{
	        if ( $temptyp == "11111101" ) {
	          $rawData = SD_WS_WH2SHIFT($rawData);
	          $rawData = SD_WS_WH2SHIFT($rawData);
	          $msg = $msg_vor.$rawData;
	          $bitData = unpack("B$blen", pack("H$hlen", $rawData));
	          Log3 $iohash, 4, "$name: SD_WS_WH2_2 msg=$msg length:".length($bitData) ;
	          Log3 $iohash, 4, "$name: SD_WS_WH2_2 bitdata: $bitData" ;
	          }
	      }
	
	      if( $temptyp == "11111111" ) {
	            $vorpre = 8;
	          }else{
	            Log3 $iohash, 4, "$name: SD_WS_WH2_4 Error kein WH2: Typ: $temptyp" ;
	            return "";
	          }
	
	     my $rc = eval
	     {
	      require Digest::CRC;
	      Digest::CRC->import();
	      1;
	     };
	
	    if($rc)
	    {
	    # Digest::CRC loaded and imported successfully
	     Log3 $iohash, 4, "$name: SD_WS_WH2_1 msg: $msg raw: $rawData " ;
	    $rr2 = SD_WS_WH2CRCCHECK($rawData);
	     if ($rr2 == 0 ){
	            # 1.CRC OK 
	            Log3 $iohash, 4, "$name: SD_WS_WH2_1 CRC_OK   : CRC=$rr2 msg: $msg check:".$rawData ;
	          }else{
	             Log3 $iohash, 4, "$name: SD_WS_WH2_4 CRC_Error: CRC=$rr2 msg: $msg check:".$rawData ;
	            return "";
	          }
	   }else {
	      Log3 $iohash, 1, "$name: SD_WS_WH2_3 CRC_not_load: Modul Digest::CRC fehlt" ;
	      return "";
	   }  
	   
	    $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 
	   	Log3 $iohash, 4, "$name: converted to bits WH2 " . $bitData;    
	    $model = "SD_WS_WH2";
		$SensorTyp = "WH2";
		$id = 	SD_WS_bin2dec(substr($bitData,$vorpre + 4,6));
	    $id = sprintf('%03X', $id); 
		$channel = 	0;
	    $bat = SD_WS_binaryToNumber($bitData,$vorpre + 20) eq "1" ? "low" : "ok";
	     
	    $sign = SD_WS_bin2dec(substr($bitData,$vorpre + 12,1)); 
	    
	    if ($sign == 0) {
	    # Temp positiv
	      	$temp = (SD_WS_bin2dec(substr($bitData,$vorpre + 13,11))) / 10;
	    }else{
	    # Temp negativ
	     	$temp = -(SD_WS_bin2dec(substr($bitData,$vorpre + 13,11))) / 10;
	    }
	    Log3 $iohash, 4, "$name: decoded protocolid $protocol ($SensorTyp) sensor id=$id, Data:".substr($bitData,$vorpre + 12,12)." temp=$temp";
	    $hum =  SD_WS_bin2dec(substr($bitData,$vorpre + 24,8));   # TFA 30.3157 nur Temp, Hum = 255
	    Log3 $iohash, 4, "$name: SD_WS_WH2_8 $protocol ($SensorTyp) sensor id=$id, Data:".substr($bitData,$vorpre + 24,8)." hum=$hum";
	    Log3 $iohash, 4, "$name: SD_WS_WH2_9 $protocol ($SensorTyp) sensor id=$id, channel=$channel, temp=$temp, hum=$hum";
		
 	}
   
	elsif (defined($decodingSubs{$protocol}))		# durch den hash decodieren
	{
	 	   	$SensorTyp=$decodingSubs{$protocol}{sensortype};
		    if (!$decodingSubs{$protocol}{prematch}->( $rawData ))
		    { 
		   		Log3 $iohash, 4, "$name: SD_WS_Parse $rawData protocolid $protocol ($SensorTyp) prematch error" ;
		    	return "";  
	    	}
		    my $retcrc=$decodingSubs{$protocol}{crcok}->( $rawData );
		    if (!$retcrc)		    { 
		    	Log3 $iohash, 4, "$name: SD_WS_Parse $rawData protocolid $protocol ($SensorTyp) crc error: $retcrc";
		    	return "";  
	    	}
	    	$id=$decodingSubs{$protocol}{id}->( $rawData,$bitData );
	    	#my $temphex=$decodingSubs{$protocol}{temphex}->( $rawData,$bitData );
	    	$temp=$decodingSubs{$protocol}{temp}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{temp}));
	    	$hum=$decodingSubs{$protocol}{hum}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{hum}));
	    	$windspeed=$decodingSubs{$protocol}{windspeed}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{windspeed}));
	    	$channel=$decodingSubs{$protocol}{channel}->( $rawData,$bitData );
	    	$model = $decodingSubs{$protocol}{model};
				$bat = $decodingSubs{$protocol}{bat}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{bat}));
				if ($model eq "SD_WS_33_T") {			# for SD_WS_33 discrimination T - TH
					$model = $decodingSubs{$protocol}{model}."H" if $hum != 0;				# for models with Humidity
				} 
	    	$sendmode = $decodingSubs{$protocol}{sendmode}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{sendmode}));
	    	$trend = $decodingSubs{$protocol}{trend}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{trend}));
				#Use of uninitialized value $temp 
	    	#Log3 $iohash, 4, "$name: decoded protocolid $protocol ($SensorTyp) sensor id=$id, channel=$channel, temp=$temp, hum=$hum, bat=$bat";
	    	Log3 $iohash, 4, "$name: decoded protocolid $protocol ($SensorTyp) sensor id=$id";
	} 
	else {
		Log3 $iohash, 2, "$name: SD_WS_Parse unknown message, please report. converted to bits: $bitData";
		return undef;
	}

	if (!defined($model)) {
		return undef;
	}
	
	my $deviceCode;
	
	my $longids = AttrVal($ioname,'longids',0);
	if (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
	{
		$deviceCode = $model . '_' . $id . $channel;						# old form of longid
		if (!defined($modules{SD_WS}{defptr}{$deviceCode})) {
			$deviceCode = $model . '_' . $id . '_' . $channel;		# new form of longid
		}
		Log3 $iohash,4, "$name: using longid for $longids device $deviceCode";
	} else {
		$deviceCode = $model . "_" . $channel;
	}
	
	#print Dumper($modules{SD_WS}{defptr});
	
	my $def = $modules{SD_WS}{defptr}{$ioname . "." . $deviceCode};
	$def = $modules{SD_WS}{defptr}{$deviceCode} if(!$def);

	if(!$def) {
		Log3 $iohash, 1, "$name: SD_WS_Parse UNDEFINED sensor $model detected, code $deviceCode";
		return "UNDEFINED $deviceCode SD_WS $deviceCode";
	}
		
	my $hash = $def;
	$name = $hash->{NAME};
	return "" if(IsIgnored($name));

	if (defined $temp) {
		if ($temp < -30 || $temp > 70) {
			Log3 $iohash, 3, "$ioname: SD_WS_Parse $deviceCode - ERROR temperature $temp";
			return "";  
		}
	}
	if (defined $hum) {
		if ($hum > 100) {
			Log3 $iohash, 3, "$ioname: SD_WS_Parse $deviceCode - ERROR humidity $hum";
			return "";  
		}
	}
	
	# Sanity checks
  if($def) {
		my $timeSinceLastUpdate = abs(ReadingsAge($name, "state", 0));
		# temperature
		if (defined($temp) && defined(ReadingsVal($name, "temperature", undef))) {
			my $diffTemp = 0;
			my $oldTemp = ReadingsVal($name, "temperature", undef);
			my $maxdeviation = AttrVal($name, "max-deviation-temp", 1);				# default 1 K
			if ($temp > $oldTemp) {
				$diffTemp = ($temp - $oldTemp);
			} else {
				$diffTemp = ($oldTemp - $temp);
			}
			$diffTemp = sprintf("%.1f", $diffTemp);				
			Log3 $name, 4, "$ioname: $name old temp $oldTemp, age $timeSinceLastUpdate, new temp $temp, diff temp $diffTemp";
			my $maxDiffTemp = $timeSinceLastUpdate / 60 + $maxdeviation; 			# maxdeviation + 1.0 Kelvin/Minute
			$maxDiffTemp = sprintf("%.1f", $maxDiffTemp + 0.05);						# round 0.1
			Log3 $name, 4, "$ioname: $name max difference temperature $maxDiffTemp K";
			if ($diffTemp > $maxDiffTemp) {
				Log3 $name, 3, "$ioname: $name ERROR - Temp diff too large (old $oldTemp, new $temp, diff $diffTemp)";
				return "";
			}
		}
		# humidity
		if (defined($hum) && defined(ReadingsVal($name, "humidity", undef))) {
			my $diffHum = 0;
			my $oldHum = ReadingsVal($name, "humidity", undef);
			my $maxdeviation = AttrVal($name, "max-deviation-hum", 1);				# default 1 %
			if ($hum > $oldHum) {
				$diffHum = ($hum - $oldHum);
			} else {
				$diffHum = ($oldHum - $hum);
			}
			$diffHum = sprintf("%.1f", $diffHum);				
			Log3 $name, 4, "$ioname: $name old hum $oldHum, age $timeSinceLastUpdate, new hum $hum, diff hum $diffHum";
			my $maxDiffHum = $timeSinceLastUpdate / 60 + $maxdeviation; 			# $maxdeviation + 1.0 %/Minute
			$maxDiffHum = sprintf("%1.f", $maxDiffHum + 0.5);							# round 1
			Log3 $name, 4, "$ioname: $name max difference humidity $maxDiffHum %";
			if ($diffHum > $maxDiffHum) {
				Log3 $name, 3, "$ioname: $name ERROR - Hum diff too large (old $oldHum, new $hum, diff $diffHum)";
				return "";
			}
		}
  }
	
	Log3 $name, 4, "$ioname: SD_WS_Parse $name ($rawData)";  

	$hash->{lastReceive} = time();
	$hash->{lastMSG} = $rawData;
	if (defined($bitData2)) {
		$hash->{bitMSG} = $bitData2;
	} else {
		$hash->{bitMSG} = $bitData;
	}
  
	#my $state = (($temp > -60 && $temp < 70) ? "T: $temp":"T: xx") . (($hum > 0 && $hum < 100) ? " H: $hum":"");
	my $state = "";
	if (defined($temp)) {
		$state .= "T: $temp"
	}
	if (defined($hum) && ($hum > 0 && $hum < 100)) {
		$state .= " H: $hum"
	}
	if (defined($windspeed)) {
		$state .= " " if (length($state) > 0);
		$state .= "W: $windspeed"
	}
	
	### protocol 33 has different bits per sensor type
	if ($protocol eq "33") {
		if (AttrVal($name,'model',0) eq "S522") {									# Conrad S522
			$bat = substr($bitData,36,1) eq "0" ? "ok" : "low";
		} elsif (AttrVal($name,'model',0) eq "E0001PA") {					# renkforce E0001PA
			$bat = substr($bitData,35,1) eq "0" ? "ok" : "low";	
			$sendmode = substr($bitData,34,1) eq "1" ? "manual" : "auto";
		} elsif (AttrVal($name,'model',0) eq "TX-EZ6") {					# TZS First Austria TX-EZ6
			$bat = substr($bitData,35,1) eq "0" ? "ok" : "low";	
			$sendmode = substr($bitData,34,1) eq "1" ? "manual" : "auto";
			$trendTemp = ('consistent', 'rising', 'falling', 'unknown')[SD_WS_binaryToNumber($bitData,10,11)];
			$trendHum = ('consistent', 'rising', 'falling', 'unknown')[SD_WS_binaryToNumber($bitData,36,37)];
		}
	}

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $state);
	readingsBulkUpdate($hash, "temperature", $temp)  if (defined($temp) && ($temp > -60 && $temp < 70 ));
	readingsBulkUpdate($hash, "humidity", $hum)  if (defined($hum) && ($hum > 0 && $hum < 100 )) ;
	readingsBulkUpdate($hash, "windspeed", $windspeed)  if (defined($windspeed)) ;
	readingsBulkUpdate($hash, "batteryState", $bat) if (defined($bat) && length($bat) > 0) ;
	readingsBulkUpdate($hash, "batteryState", $bat) if (defined($bat) && length($bat) > 0) ;
	readingsBulkUpdate($hash, "channel", $channel) if (defined($channel)&& length($channel) > 0);
	readingsBulkUpdate($hash, "trend", $trend) if (defined($trend) && length($trend) > 0);
	readingsBulkUpdate($hash, "temperatureTrend", $trendTemp) if (defined($trendTemp) && length($trendTemp) > 0);
	readingsBulkUpdate($hash, "humidityTrend", $trendHum) if (defined($trendHum) && length($trendHum) > 0);
	readingsBulkUpdate($hash, "sendmode", $sendmode) if (defined($sendmode) && length($sendmode) > 0);
	readingsEndUpdate($hash, 1); # Notify is done by Dispatch
	
	return $name;

}

sub SD_WS_Attr(@)
{
	my @a = @_;
	
	# Make possible to use the same code for different logical devices when they
	# are received through different physical devices.
	return  if($a[0] ne "set" || $a[2] ne "IODev");
	my $hash = $defs{$a[1]};
	my $iohash = $defs{$a[3]};
	my $cde = $hash->{CODE};
	delete($modules{SD_WS}{defptr}{$cde});
	$modules{SD_WS}{defptr}{$iohash->{NAME} . "." . $cde} = $hash;
	return undef;
}

sub SD_WS_bin2dec($)
    {
      my $h = shift;
      my $int = unpack("N", pack("B32",substr("0" x 32 . $h, -32))); 
      return sprintf("%d", $int); 
    }


sub SD_WS_binaryToNumber
{
	my $binstr=shift;
	my $fbit=shift;
	my $lbit=$fbit;
	$lbit=shift if @_;
	return oct("0b".substr($binstr,$fbit,($lbit-$fbit)+1));
}

 sub SD_WS_WH2CRCCHECK($) {
       my $rawData = shift;
       my $datacheck1 = pack( 'H*', substr($rawData,2,length($rawData)-2) );
       my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
       my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
       $rr3 = sprintf("%d", hex($rr3));
       Log3 "SD_WS_CRCCHECK", 4, "SD_WS_WH2CRCCHECK :  raw:$rawData CRC=$rr3 " ;
       return $rr3 ;
    }
sub SD_WS_WH2SHIFT($){
         my $rawData = shift;
         my $hlen = length($rawData);
         my $blen = $hlen * 4;
         my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
    	   my $bitData2 = '1'.unpack("B$blen", pack("H$hlen", $rawData));
         my $bitData20 = substr($bitData2,0,length($bitData2)-1);
          $blen = length($bitData20);
          $hlen = $blen / 4;
          $rawData = uc(unpack("H$hlen", pack("B$blen", $bitData20)));
          $bitData = $bitData20;
          Log3 "SD_WS_WH2SHIFT", 4, "SD_WS_WH2SHIFT_0  raw: $rawData length:".length($bitData) ;
          Log3 "SD_WS_WH2SHIFT", 4, "SD_WS_WH2SHIFT_1  bitdata: $bitData" ;
        return $rawData;  
    }

1;

=pod
=item summary    Supports various weather stations
=item summary_DE Unterst&uumltzt verschiedene Funk Wetterstationen
=begin html

<a name="SD_WS"></a>
<h3>Weather Sensors various protocols</h3>
<ul>
  The SD_WS module processes the messages from various environmental sensors received from an IO device (CUL, CUN, SIGNALDuino, SignalESP etc.).<br><br>
  <b>Known models:</b>
  <ul>
    <li>Bresser 7009994</li>
    <li>BresserTemeo</li>
    <li>Conrad S522</li>
		<li>Opus XT300</li>
    <li>PV-8644 infactory Poolthermometer</li>
    <li>Renkforce E0001PA</li>
		<li>TX-EZ6 for Weatherstation TZS First Austria</li>
		<li>WH2 (TFA Dostmann/Wertheim 30.3157 (sold in Germany), Agimex Rosenborg 66796 (sold in Denmark),ClimeMET CM9088 (Sold in UK)</li>
		<li>Weatherstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D</li>
		<li>Weatherstation TFA 35.1140.01 with temperature / humidity sensor TFA 30.3221.02 and temperature / humidity / windspeed sensor TFA 30.3222.02</li>
  </ul><br><br>

  <a name="SD_WS_Define"></a>
  <b>Define</b><br><br>
  <ul>
		Newly received sensors are usually automatically created in FHEM via autocreate.<br>
		It is also possible to set up the devices manually with the following command:<br><br>
    <code>define &lt;name&gt; SD_WS &lt;code&gt; </code> <br><br>
    &lt;code&gt; is the channel or individual identifier used to identify the sensor.<br>
  </ul><br><br>

  <a name="SD_WS Events"></a>
  <b>Generated readings:</b><br><br>
  <ul>
		Some devices may not support all readings, so they will not be presented<br>
	</ul>
  <ul>
    <li>batteryState (low or ok)</li>
    <li>channel (number of channel</li>
		<li>humidity (humidity (1-100 % only if available)</li>
		<li>humidityTrend (consistent, rising, falling)</li>
		<li>sendmode (automatic or manual)</li>
		<li>state (T: H: W:)</li>
    <li>temperature (&deg;C)</li>
		<li>temperatureTrend (consistent, rising, falling)</li>
  </ul><br><br>

  <a name="SD_WS Attribute"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li>max-deviation-hum<br>
			(Default: 1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
			<a name="max-deviation-hum"></a>
			Maximum permissible deviation of the measured humidity from the previous value in percent.<br>
			Since many of the sensors handled in the module do not have checksums, etc. send, it can easily come to the reception of implausible values. 
			To intercept these, a maximum deviation from the last correctly received value can be set. 
			Greater deviations are then ignored and result in an error message in the log file, such as an error message like this:<br>
			<code>SD_WS_TH_84 ERROR - Hum diff too large (old 60, new 68, diff 8)</code><br>
			In addition to the set value, a value dependent on the difference of the reception times is added. 
			This is 1.0% relative humidity per minute. 
			This means e.g. if a difference of 8 is set and the time interval of receipt of the messages is 3 minutes, the maximum allowable difference is 11.<br>
			Instead of the <code>max-deviation-hum</code> and <code>max-deviation-temp</code> attributes, 
			the <code>doubleMsgCheck_IDs</code> attribute of the SIGNALduino can also be used if the sensor is well received. 
			An update of the readings is only executed if the same values ??have been received at least twice.
			<a name="end_max-deviation-hum"></a>
    </li><br>
    <li>max-deviation-temp<br>
			(Default: 1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
			<a name="max-deviation-temp"></a>
			Maximum permissible deviation of the measured temperature from the previous value in Kelvin.<br>
			Explanation see attribute "max-deviation-hum".
			<a name="end_max-deviation-temp"></a>
    </li><br>
    <li>model<br>
			(Default: other, currently supported sensors: E0001PA, S522)<br>
			<a name="model"></a>
			The sensors of the "SD_WS_33 series" use different positions for the battery bit and different readings. 
			If the battery bit is detected incorrectly (low instead of ok), then you can possibly adjust with the model selection of the sensor.<br>
			So far, 3 variants are known. All sensors are created by Autocreate as model "other". 
			If you receive a Conrad S522, Renkforce E0001PA or TX-EZ6, then set the appropriate model for the proper processing of readings.
			<a name="end_model"></a>
		</li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
		<li><a href="#showtime">showtime</a></li><br>
  </ul><br>
  <b>Set</b>
	<ul>N/A</ul><br>
</ul>

=end html

=begin html_DE

<a name="SD_WS"></a>
<h3>SD_WS</h3>
<ul>
  Das Modul SD_WS verarbeitet die von einem IO-Ger&aumlt (CUL, CUN, SIGNALDuino, SignalESP etc.) empfangenen Nachrichten verschiedener Umwelt-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b><br><br>
  <ul>
    <li>Bresser 7009994</li>
    <li>BresserTemeo</li>
    <li>Conrad S522</li>
		<li>Opus XT300</li>
    <li>PV-8644 infactory Poolthermometer</li>
    <li>Renkforce E0001PA</li>
		<li>TX-EZ6 fuer Wetterstation TZS First Austria</li>
		<li>WH2 (TFA Dostmann/Wertheim 30.3157 (Deutschland), Agimex Rosenborg 66796 (Denmark), ClimeMET CM9088 (UK)</li>
		<li>Wetterstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D</li>
		<li>Wetterstation TFA 35.1140.01 mit Temperatur-/Feuchtesensor TFA 30.3221.02 und Temperatur-/Feuchte- und Windsensor TFA 30.3222.02</li>
		</ul>
  <br><br>

  <a name="SD_WS_Define"></a>
  <b>Define</b><br><br>
  <ul>
		Neu empfangene Sensoren werden in FHEM normalerweise per autocreate automatisch angelegt.<br>
		Es ist auch m&ouml;glich, die Ger&auml;te manuell mit folgendem Befehl einzurichten:<br><br>
    <code>define &lt;name&gt; SD_WS &lt;code&gt; </code> <br><br>
    &lt;code&gt; ist der Kanal oder eine individuelle Ident, mit dem der Sensor identifiziert wird.<br>
  </ul>
  <br><br>

  <a name="SD_WS Events"></a>
  <b>Generierte Readings:</b><br><br>
  <ul>(verschieden, je nach Typ des Sensors)</ul>
  <ul>
  	<li>batteryState (low oder ok)</li>
    <li>channel (Sensor-Kanal)</li>
    <li>humidity (Luftfeuchte (1-100 %)</li>
		<li>humidityTrend (gleichbleibend, steigend, fallend)</li>
		<li>state (T: H: W:)</li>
    <li>temperature (&deg;C)</li>
		<li>temperatureTrend (gleichbleibend, steigend, fallend)</li>
    <li>sendmode (Der Sendemodus, automatic oder manuell mittels Taster am Sender)</li>
  </ul>
  <br><br>

  <a name="SD_WS Attribute"></a>
  <b>Attribute</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li>max-deviation-hum<br>
			(Standard: 1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
			<a name="max-deviation-hum"></a>
			Maximal erlaubte Abweichung der gemessenen Feuchte zum vorhergehenden Wert in Prozent.
			<br>Da viele der in dem Modul behandelten Sensoren keine Checksummen o.&auml;. senden, kann es leicht zum Empfang von unplausiblen Werten kommen. 
			Um diese abzufangen, kann eine maximale Abweichung zum letzten korrekt empfangenen Wert festgelegt werden.
			Gr&ouml&szlig;ere Abweichungen werden dann ignoriert und f&uuml;hren zu einer Fehlermeldung im Logfile, wie z.B. dieser:<br>
			<code>SD_WS_TH_84 ERROR - Hum diff too large (old 60, new 68, diff 8)</code><br>
			Zus&auml;tzlich zum eingestellten Wert wird ein von der Differenz der Empfangszeiten abh&auml;ngiger Wert addiert.
			Dieser betr&auml;gt 1.0 % relative Feuchte pro Minute. Das bedeutet z.B. wenn eine Differenz von 8 eingestellt ist
			und der zeitliche Abstand des Empfangs der Nachrichten betr&auml;gt 3 Minuten, ist die maximal erlaubte Differenz 11.
			<br>Anstelle der Attribute <code>max-deviation-hum</code> und <code>max-deviation-temp</code> kann bei gutem Empfang des Sensors 
			auch das Attribut <code>doubleMsgCheck_IDs</code> des SIGNALduino verwendet werden. Dabei wird ein Update der Readings erst 
			ausgef&uuml;hrt, wenn mindestens zweimal die gleichen Werte empfangen wurden.
			<a name="end_max-deviation-hum"></a>
    </li><br>
    <li>max-deviation-temp<br>
			(Standard: 1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
			<a name="max-deviation-temp"></a>
			Maximal erlaubte Abweichung der gemessenen Temperatur zum vorhergehenden Wert in Kelvin.<br>
			Erkl&auml;rung siehe Attribut "max-deviation-hum".
			<a name="end_max-deviation-temp"></a>
    </li><br>
    <li>model<br>
			<a name="model"></a>
			(Standard: other, zur Zeit unterst&uuml;tzte Sensoren: E0001PA, S522, TX-EZ6)<br>
			Die Sensoren der "SD_WS_33 - Reihe" verwenden unterschiedliche Positionen f&uuml;r das Batterie-Bit und unterst&uuml;tzen verschiedene Readings. 
			Sollte das Batterie-Bit falsch erkannt werden (low statt ok), so kann man mit der Modelauswahl des Sensors das evtl. anpassen.<br>
			Bisher sind 3 Varianten bekannt. Alle Sensoren werden durch Autocreate als Model "other" angelegt. 
			Empfangen Sie einen Sensor vom Typ Conrad S522, Renkforce E0001PA oder TX-EZ6, so stellen Sie das jeweilige Modell f&uuml;r die richtige Verarbeitung der Readings ein.
			<a name="end_model"></a>
		</li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
		<li><a href="#showtime">showtime</a></li><br>
  </ul>
	<br>

  <b>Set</b> <ul>N/A</ul><br>
</ul>

=end html_DE
=cut
