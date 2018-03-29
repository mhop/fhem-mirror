##############################################
# $Id$
#
# v3.3.2 (stable release 3.3)
# The module is inspired by the FHEMduino project and modified in serval ways for processing the incomming messages
# see http://www.fhemwiki.de/wiki/SIGNALDuino
# It was modified also to provide support for raw message handling which can be send from the SIGNALduino
# The purpos is to use it as addition to the SIGNALduino which runs on an arduno nano or arduino uno.
# It routes Messages serval Modules which are already integrated in FHEM. But there are also modules which comes with it.
# N. Butzek, S. Butzek, 2014-2015
# S.Butzek,Ralf9 2016-2018

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Data::Dumper qw(Dumper);
use Scalar::Util qw(looks_like_number);
no warnings 'portable';

#$| = 1;		#Puffern abschalten, Hilfreich für PEARL WARNINGS Search
#use POSIX qw( floor);  # can be removed
#use Math::Round qw();


use constant {
	SDUINO_VERSION            => "v3.3.2",
	SDUINO_INIT_WAIT_XQ       => 1.5,       # wait disable device
	SDUINO_INIT_WAIT          => 2,
	SDUINO_INIT_MAXRETRY      => 3,
	SDUINO_CMD_TIMEOUT        => 10,
	SDUINO_KEEPALIVE_TIMEOUT  => 60,
	SDUINO_KEEPALIVE_MAXRETRY => 3,
	SDUINO_WRITEQUEUE_NEXT    => 0.3,
	SDUINO_WRITEQUEUE_TIMEOUT => 2,
	
	SDUINO_DISPATCH_VERBOSE   => 5,       # default 5
};


sub SIGNALduino_Attr(@);
#sub SIGNALduino_Clear($);           # wird nicht mehr benoetigt
sub SIGNALduino_HandleWriteQueue($);
sub SIGNALduino_Parse($$$$@);
sub SIGNALduino_Read($);
#sub SIGNALduino_ReadAnswer($$$$);  # wird nicht mehr benoetigt
sub SIGNALduino_Ready($);
sub SIGNALduino_Write($$$);
sub SIGNALduino_SimpleWrite(@);

#my $debug=0;

my %gets = (    # Name, Data to send to the SIGNALduino, Regexp for the answer
  "version"  => ["V", 'V\s.*SIGNAL(duino|ESP).*'],
  "freeram"  => ["R", '^[0-9]+'],
  "raw"      => ["", '.*'],
  "uptime"   => ["t", '^[0-9]+' ],
  "cmds"     => ["?", '.*Use one of[ 0-9A-Za-z]+[\r\n]*$' ],
# "ITParms"  => ["ip",'.*'],
  "ping"     => ["P",'^OK$'],
  "config"   => ["CG",'^MS.*MU.*MC.*'],
  "protocolIDs"   => ["none",'none'],
  "ccconf"   => ["C0DnF", 'C0Dn11.*'],
  "ccreg"    => ["C", '^C.* = .*'],
  "ccpatable" => ["C3E", '^C3E = .*'],
#  "ITClock"  => ["ic", '\d+'],
#  "FAParms"  => ["fp", '.*' ],
#  "TCParms"  => ["dp", '.*' ],
#  "HXParms"  => ["hp", '.*' ]
);


my %sets = (
  "raw"       => '',
  "flash"     => '',
  "reset"     => 'noArg',
  "close"     => 'noArg',
  #"disablereceiver"     => "",
  #"ITClock"  => 'slider,100,20,700',
  "enableMessagetype" => 'syncedMS,unsyncedMU,manchesterMC',
  "disableMessagetype" => 'syncedMS,unsyncedMU,manchesterMC',
  "sendMsg"		=> "",
  "cc1101_freq"    => '',
  "cc1101_bWidth"  => '',
  "cc1101_rAmpl"   => '',
  "cc1101_sens"    => '',
  "cc1101_patable_433" => '-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm',
  "cc1101_patable_868" => '-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm',
);

my %patable = (
  "433" =>
  {
    "-10_dBm"  => '34',
    "-5_dBm"   => '68',
    "0_dBm"    => '60',
    "5_dBm"    => '84',
    "7_dBm"    => 'C8',
    "10_dBm"   => 'C0',
  },
  "868" =>
  {
    "-10_dBm"  => '27',
    "-5_dBm"   => '67',
    "0_dBm"    => '50',
    "5_dBm"    => '81',
    "7_dBm"    => 'CB',
    "10_dBm"   => 'C2',
  },
);


my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42); # rAmpl(dB)

## Supported Clients per default
my $clientsSIGNALduino = ":IT:"
						."CUL_TCM97001:"
						."SD_RSL:"
						."OREGON:"
						."CUL_TX:"
						."SD_AS:"
						."Hideki:"
						."SD_WS07:"
						."SD_WS09:"
						." :"		# Zeilenumbruch
						."SD_WS:"
						."RFXX10REC:"
						."Dooya:"
						."SOMFY:"
						."SD_UT:"	## BELL 201.2 TXA
			        	."SD_WS_Maverick:"
			        	."FLAMINGO:"
			        	."CUL_WS:"
			        	."Revolt:"
					." :"		# Zeilenumbruch
			        	."FS10:"
			        	."CUL_FHTTK:"
			        	."Siro:"
						."FHT:"
						."FS20:"
			      		."SIGNALduino_un:"
					; 

## default regex match List for dispatching message to logical modules, can be updated during runtime because it is referenced
my %matchListSIGNALduino = (
     "1:IT"            			=> "^i......",	  				  # Intertechno Format
     "2:CUL_TCM97001"      		=> "^s[A-Fa-f0-9]+",			  # Any hex string		beginning with s
     "3:SD_RSL"					=> "^P1#[A-Fa-f0-9]{8}",
     "5:CUL_TX"               	=> "^TX..........",         	  # Need TX to avoid FHTTK
     "6:SD_AS"       			=> "^P2#[A-Fa-f0-9]{7,8}", 		  # Arduino based Sensors, should not be default
     "4:OREGON"            		=> "^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*",		
     "7:Hideki"					=> "^P12#75[A-F0-9]+",
     "9:CUL_FHTTK"			=> "^T[A-F0-9]{8}",
     "10:SD_WS07"				=> "^P7#[A-Fa-f0-9]{6}F[A-Fa-f0-9]{2}(#R[A-F0-9][A-F0-9]){0,1}\$",
     "11:SD_WS09"				=> "^P9#F[A-Fa-f0-9]+",
     "12:SD_WS"					=> '^W\d+x{0,1}#.*',
     "13:RFXX10REC" 			=> '^(20|29)[A-Fa-f0-9]+',
     "14:Dooya"					=> '^P16#[A-Fa-f0-9]+',
     "15:SOMFY"					=> '^Ys[0-9A-F]+',
     "16:SD_WS_Maverick"		=> '^P47#[A-Fa-f0-9]+',
     "17:SD_UT"            		=> '^u30#.*',						## BELL 201.2 TXA
     "18:FLAMINGO"            	=> '^P13#[A-Fa-f0-9]+',						## Flamingo Smoke
     "19:CUL_WS"				=> '^K[A-Fa-f0-9]{5,}',
     "20:Revolt"				=> '^r[A-Fa-f0-9]{22}',
     "21:FS10"				=> '^P61#[A-F0-9]+',
     "22:Siro"					=> '^P72#[A-Fa-f0-9]+',
     "23:FHT"       => "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
     "24:FS20"      => "^81..(04|0c)..0101a001", 
     "X:SIGNALduino_un"			=> '^[u]\d+#.*',
);


my %ProtocolListSIGNALduino  = (
    "0"    => 
        {
            name			=> 'weather1',		# Logilink, NC, WS, TCM97001 etc.
			comment		=> 'Logilink, NC, WS, TCM97001 etc',
			id          	=> '0',
			one				=> [1,-8],
			zero			=> [1,-4],
			sync			=> [1,-18],		
			clockabs   		=> '500',		# not used now
			format     		=> 'twostate',  # not used now
			preamble		=> 's',			# prepend to converted message	 	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'CUL_TCM97001',   # not used now
			#modulematch     => '^s[A-Fa-f0-9]+', # not used now
			length_min      => '24',
			length_max      => '46',
			paddingbits     => '8',				 # pad up to 8 bits, default is 4
        },
    "1"    => 
        {
            name			=> 'ConradRSL',			# 
			id          	=> '1',
			one				=> [2,-1],
			zero			=> [1,-2],
			sync			=> [1,-11],		
			clockabs   		=> '560',				# not used now
			format     		=> 'twostate',  		# not used now
			preamble		=> 'P1#',					# prepend to converted message	 	
			postamble		=> '',					# Append to converted message	 	
			clientmodule    => 'SD_RSL',   # not used now
			modulematch     => '^P1#[A-Fa-f0-9]{8}', 	# not used now
			length_min 		=> '20',   # 23
			length_max 		=> '40',   # 24

        },


    "2"    => 
        {
			name			=> 'AS, Self build arduino sensor',
			comment         => 'developModule. SD_AS module is only in github available',
			developId 		=> 'm',
			id          	=> '2',
			one				=> [1,-2],
			zero			=> [1,-1],
			sync			=> [1,-20],
			clockabs     	=> '500',		# not used now
			format 			=> 'twostate',	
			preamble		=> 'P2#',		# prepend to converted message		
			clientmodule    => 'SD_AS',   # not used now
			modulematch     => '^P2#.{7,8}',
			length_min      => '32',
			length_max      => '34',		# Don't know maximal lenth of a valid message
			paddingbits     => '8',		    # pad up to 8 bits, default is 4
	
        },
    "3"    => 
        {
            name			=> 'itv1',	
			id          	=> '3',
			one				=> [3,-1],
			zero			=> [1,-3],
			#float			=> [-1,3],		# not full supported now later use
			sync			=> [1,-31],
			clockabs     	=> -1,	# -1=auto	
			format 			=> 'twostate',	# not used now
			preamble		=> 'i',			
			clientmodule    => 'IT',   # not used now
			modulematch     => '^i......', # not used now
			length_min      => '24',
			#length_max      => '800',		# Don't know maximal lenth of a valid message

			},
    "3.1"    => 
        {
            name			=> 'itv1_sync40',	
			comment		=> 'IT remote Control PAR 1000',
			id          	=> '3',
			one				=> [3,-1],
			zero			=> [1,-3],
			#float			=> [-1,3],		# not full supported now later use
			sync			=> [1,-40],
			clockabs     	=> -1,	# -1=auto	
			format 			=> 'twostate',	# not used now
			preamble		=> 'i',			
			clientmodule    => 'IT',   # not used now
			modulematch     => '^i......', # not used now
			length_min      => '24',
			#length_max      => '800',		# Don't know maximal lenth of a valid message

			},
    "4"    => 
        {
            name			=> 'arctech2',	
			id          	=> '4',
			#one			=> [1,-5,1,-1],  
			#zero			=> [1,-1,1,-5],  
			one				=> [1,-5],  
			zero			=> [1,-1],  
			#float			=> [-1,3],		# not full supported now, for later use
			sync			=> [1,-14],
			clockabs     	=> -1,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'i',			# Append to converted message	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'IT',   		# not used now
			modulematch     => '^i......',  # not used now
			length_min      => '32',
			#length_max      => '76',		# Don't know maximal lenth of a valid message
		},
    "5"    => 			## Similar protocol as intertechno, but without sync
        {
            name			=> 'unitec6899',	
			id          	=> '5',
			one				=> [3,-1],
			zero			=> [1,-3],
			clockabs     	=> 500,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'p5#',			# Append to converted message	
			clientmodule    => 'IT',   		# not used now
			modulematch     => '^i......',  # not used now
			length_min      => '24',

		},    
	
	"6"    => 			## Eurochron Protocol
        {
            name			=> 'weatherID6',	
			id          	=> '6',
			one				=> [1,-10],
			zero			=> [1,-5],
			sync			=> [1,-36],		# This special device has no sync
			clockabs     	=> 220,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'u6#',			# Append to converted message	
			#clientmodule    => '',   	# not used now
			#modulematch     => '^u......',  # not used now
			length_min      => '24',

		},
	"7"    => 			## weather sensors like EAS800z
        {
            name			=> 'weatherID7',	
			comment		=> 'EAS800z, FreeTec NC-7344',
			id          	=> '7',
			one				=> [1,-4],
			zero			=> [1,-2],
			sync			=> [1,-8],		 
			clockabs     	=> 484,			
			format 			=> 'twostate',	
			preamble		=> 'P7#',		# prepend to converted message	
			clientmodule    => 'SD_WS07',   	# not used now
			modulematch     => '^P7#.{6}F.{2}', # not used now
			length_min      => '35',
			length_max      => '40',

		}, 
	"8"    => 			## TX3 (ITTX) Protocol
        {
            name			=> 'TX3 Protocol',	
			id          	=> '8',
			one				=> [1,-2],
			zero			=> [2,-2],
			#sync			=> [1,-8],		# 
			clockabs     	=> 470,			# 
			format 			=> 'pwm',	    # 
			preamble		=> 'TX',		# prepend to converted message	
			clientmodule    => 'CUL_TX',   	# not used now
			modulematch     => '^TX......', # not used now
			length_min      => '43',
			length_max      => '44',
			remove_zero     => 1,           # Removes leading zeros from output

		}, 	
	"9"    => 			## Funk Wetterstation CTW600
			{
      name			=> 'CTW 600',	
			comment		=> 'FunkWS WH1080/WH3080/CTW600',
			id          	=> '9',
			zero			=> [3,-2],
			one				=> [1,-2],
			#float			=> [-1,3],		# not full supported now, for later use
			#sync			=> [1,-8],		# 
			clockabs     	=> 480,			# -1 = auto undef=noclock
			format 			=> 'pwm',	    # tristate can't be migrated from bin into hex!
			preamble		=> 'P9#',		# prepend to converted message	
			clientmodule    => 'SD_WS09',   	# not used now
			#modulematch     => '^u9#.....',  # not used now
			length_min      => '60',
			length_max      => '120',

		}, 	
	"10"    => 			## Oregon Scientific 2
		{
            name			=> 'OSV2o3',	
			id          	=> '10',
			clockrange     	=> [300,520],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			clientmodule    => 'OREGON',
			modulematch     => '^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*',
			length_min      => '64',
			length_max      => '220',
			method          => \&SIGNALduino_OSV2, # Call to process this message
			polarity        => 'invert',			
		}, 	
	"11"    => 			## Arduino Sensor
		{
            name			=> 'AS',	
			id          	=> '11',
			clockrange     	=> [380,425],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			preamble		=> 'P2#',		# prepend to converted message	
			clientmodule    => 'SD_AS',   	# not used now
			modulematch     => '^P2#.{7,8}',
			length_min      => '52',
			length_max      => '56',
			method          => \&SIGNALduino_AS # Call to process this message
		}, 
	"12"    => 			## Hideki
		{
            name			=> 'Hideki protocol',	
			comment         => 'Hideki messages are sometimes received as inverted (check in sub)',
			id          	=> '12',
			clockrange     	=> [420,510],                   # min, max better for Bresser Sensors, OK for hideki/Hideki/TFA too     
			format 			=> 'manchester',	
			preamble		=> 'P12#',						# prepend to converted message	
			clientmodule    => 'hideki',   				# not used now
			modulematch     => '^P12#75.+',  						# not used now
			length_min      => '71',
			length_max      => '128',
			method          => \&SIGNALduino_Hideki,	# Call to process this message
			#polarity        => 'invert',			
			
		}, 	
	"13"    => 			## FLAMINGO  FA 21
		{
            name			=> 'FLAMINGO FA21',	
			id          	=> '13',
			one				=> [1,-2],
			zero			=> [1,-4],
			sync			=> [1,-20,10,-1],		
			clockabs		=> 800,
			format 			=> 'twostate',	  		
			preamble		=> 'P13#',				# prepend to converted message	
			clientmodule    => 'FLAMINGO',   				# not used now
			#modulematch     => 'P13#.*',  				# not used now
			length_min      => '24',
			length_max      => '26',
		}, 		
	"13.1"    => 			## FLAMINGO FA20 
		{
            name			=> 'FLAMINGO FA21 b',	
			id          	=> '13',
			one				=> [1,-2],
			zero			=> [1,-4],
			start			=> [20,-1],		
			clockabs		=> 800,
			format 			=> 'twostate',	  		
			preamble		=> 'P13#',				# prepend to converted message	
			clientmodule    => 'FLAMINGO',   				# not used now
			#modulematch     => 'P13#.*',  				# not used now
			length_min      => '24',
			length_max      => '24',
		}, 		
	
	"14"    => 			## Heidemann HX
		{
            name			=> 'Heidemann HX',	
			id          	=> '14',
			one				=> [1,-2],
			zero			=> [1,-1],
			#float			=> [-1,3],				# not full supported now, for later use
			sync			=> [1,-14],				# 
			clockabs		=> 350,
			format 			=> 'twostate',	  		
			preamble		=> 'u14#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '10',
			length_max      => '20',
		}, 			
	"15"    => 			## TCM234759
			{
            name			=> 'TCM Bell',	
			id          	=> '15',
			one				=> [1,-1],
			zero			=> [1,-2],
			sync			=> [1,-45],				# 
			clockabs		=> 700,
			format 			=> 'twostate',	  		
			preamble		=> 'u15#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '10',
			length_max      => '20',
			#method          => \&SIGNALduino_Cresta	# Call to process this message
		}, 	
	"16" => # Rohrmotor24 und andere Funk Rolladen / Markisen Motoren
		{
            name			=> 'Dooya shutter',	
			id          	=> '16',
			one				=> [2,-1],
			zero			=> [1,-3],
			start           => [17,-5],
			clockabs		=> 280,
			format 			=> 'twostate',	  		
			preamble		=> 'P16#',				# prepend to converted message	
			clientmodule    => 'Dooya',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '39',
			length_max      => '40',
		}, 	
    "17"    => 
        {
            name			=> 'arctech',	
			id          	=> '17',
			one				=> [1,-5,1,-1],  
			zero			=> [1,-1,1,-5],  
			#one			=> [1,-5],  
			#zero			=> [1,-1],  
			sync			=> [1,-10],
			float			=> [1,-1,1,-1],
			clockabs     	=> -1,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'i',			# Append to converted message	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'IT',   		# not used now
			modulematch     => '^i......',  # not used now
			length_min      => '32',
			#length_max     => '76',		# Don't know maximal lenth of a valid message
			postDemodulation => \&SIGNALduino_bit2Arctec,
		},
	
	"18"    => 			## Oregon Scientific v1
		{
            name			=> 'OSV1',	
			id          	=> '18',
			clockrange     	=> [1400,1500],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			preamble		=> '',					
			clientmodule    => 'OREGON',
			modulematch     => '^[0-9A-F].*',
			length_min      => '31',
			length_max      => '32',
			polarity        => 'invert',		    # invert bits
			method          => \&SIGNALduino_OSV1   # Call to process this message
		},
	#"19" => # nothing knowing about this 2015-09-28 01:25:40-MS;P0=-8916;P1=-19904;P2=390;P3=-535;P4=-1020;P5=12846;P6=1371;D=2120232323232324242423232323232323232320239;CP=2;SP=1;
	#
	#	{
    #       name			=> 'unknown19',	
	#		id          	=> '19',
	#		one				=> [1,-2],
	#		zero			=> [1,-1],
	#		sync			=> [1,-50,1,-22],				
	#		clockabs		=> 395,
	#		format 			=> 'twostate',	  		
	#		preamble		=> 'u19#',				# prepend to converted message	
	#		#clientmodule    => '',   				# not used now
	#		#modulematch     => '',  				# not used now
	#		length_min      => '16',
	#		length_max      => '32',
	#	}, 	 	
	"20" => #Livolo	
		{
            name			=> 'livolo',	
			id          	=> '20',
			one				=> [3],
			zero			=> [1],
			start			=> [5],				
			clockabs		=> 110,                  #can be 90-140
			format 			=> 'twostate',	  		
			preamble		=> 'u20#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '16',
			filterfunc      => 'SIGNALduino_filterSign',
		},
	"21" => #Einhell Garagentor	
		{
            name			=> 'einhell garagedoor',	
			id          	=> '21',
			one				=> [-3,1],
			zero			=> [-1,3],
			#sync			=> [-50,1],	
			start  			=> [-50,1],	
			clockabs		=> 400,                  #ca 400us
			format 			=> 'twostate',	  		
			preamble		=> 'u21#',				# prepend to converted message	
			#clientmodule   => '',   				# not used now
			#modulematch    => '',  				# not used now
			length_min      => '32',
			length_max      => '32',				
			paddingbits     => '1',					# This will disable padding 
		},
	"22" => #TX-EZ6 / Meteo	
		{
            name			=> 'TX-EZ6',	
			id          	=> '22',
			one				=> [1,-8],
			zero			=> [1,-3],
			sync			=> [1,16],				
			clockabs		=> 500,                  #ca 400us
			format 			=> 'twostate',	  		
			preamble		=> 'u22#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '40',
			#length_max      => '',				    # must be tested

		},
	"23" => # Pearl Sensor
		{
            name			=> 'perl unknown',	
			id          	=> '23',
			one				=> [1,-6],
			zero			=> [1,-1],
			sync			=> [1,-50],				
			clockabs		=> 200,                  #ca 200us
			format 			=> 'twostate',	  		
			preamble		=> 'u23#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '36',
			length_max      => '44',				

		},
	"24" => # visivon
		{
            name			=> 'visivon remote',	
			id          	=> '24',
			one			    => [3,-2],
			zero			=> [1,-5],
			#one			=> [3,-2],
			#zero			=> [1,-1],
			start           => [30,-5],
			clockabs		=> 150,                  #ca 150us
			format 			=> 'twostate',	  		
			preamble		=> 'u24#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '54',
			length_max      => '58',				

		},
		
	"25" => # LES remote for led lamp
		{
            name			=> 'les led remote',	
			id          	=> '25',
			one				=> [-2,1],
			zero			=> [-1,2],
			sync			=> [-46,1],				# this is a end marker, but we use this as a start marker
			clockabs		=> 350,                 #ca 350us
			format 			=> 'twostate',	  		
			preamble		=> 'u25#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '50',				# message has only 24 bit, but we get more than one message, calculation has to be corrected
		},
	"26" => # some remote code send by flamingo style remote controls
		{
            name			=> 'remote26',	
			id          	=> '26',
			one				=> [1,-3],
			zero			=> [3,-1],
#			sync			=> [1,-6],				# Message is not provided as MS, due to small fact
			start 			=> [1,-6],				# Message is not provided as MS, due to small fact
			clockabs		=> 380,                 #ca 380
			format 			=> 'twostate',	  		
			preamble		=> 'u26#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				# message has only 24 bit, but we get more than one message, calculation has to be corrected
		},
	"27" => # some remote code, send by flamingo style remote controls
		{
            name			=> 'remote27',	
			id          	=> '27',
			one				=> [1,-2],
			zero			=> [2,-1],
			start			=> [6,-15],				# Message is not provided as MS, worakround is start
			clockabs		=> 480,                 #ca 480
			format 			=> 'twostate',	  		
			preamble		=> 'u27#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				
		},
	"28" => # some remote code, send by aldi IC Ledspots
		{
	        name			=> 'IC Ledspot',	
			id          	=> '28',
			one				=> [1,-1],
			zero			=> [1,-2],
			start			=> [4,-5],				
			clockabs		=> 600,                 #ca 600
			format 			=> 'twostate',	  		
			preamble		=> 'u28#',				# prepend to converted message
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '8',
			length_max      => '8',				
		},
	"29" => # 
		{
            name			=> 'HT12e remote',	
			id          	=> '29',
			one				=> [-2,1],
			zero			=> [-1,2],
			#float          => [1,-1],	
			start			=> [-38,1],				# Message is not provided as MS, worakround is start
			clockabs		=> 220,                 #ca 220
			format 			=> 'tristate',	  		# there is a pause puls between words
			preamble		=> 'u29#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '10',
			length_max      => '12',				# message has only 10 bit but is paddet to 12
		},
	"30" => # a unitec remote door reed switch
		{
            name			=> 'unitec47031',	
			comment         => 'developModule. SD_UT module is only in github available',
			id          	=> '30',
			developId       => 'm',
			one				=> [-1,2],
			zero			=> [-2,1],
			start			=> [-33,1],				# Message is not provided as MS, worakround is start
			clockabs		=> 300,                 # ca 300 us
			format 			=> 'twostate',	  		# there is a pause puls between words
			preamble		=> 'u30#',				# prepend to converted message	
			clientmodule    => 'SD_UT',   			# not used now
			modulematch     => '^u30',  			# not used now
			length_min      => '12',
			length_max      => '12',				# message has only 10 bit but is paddet to 12
		},
	"31" => # Pollin Isotronic
		{
            name			=> 'pollin isotronic',	
			id          	=> '31',
			one				=> [-1,2],
			zero			=> [-2,1],
			start			=> [1],				
			clockabs		=> 600,                  
			format 			=> 'twostate',	  		
			preamble		=> 'u31#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '20',
			length_max      => '20',				

		},
	"32" => #FreeTec PE-6946 -> http://www.free-tec.de/Funkklingel-mit-Voic-PE-6946-919.shtml
    	{   
            name			=> 'freetec 6946',	
			id          	=> '32',
			one				=> [4,-2],
			zero			=> [1,-5],
			sync			=> [1,-49],				
			clockabs		=> 140,                 #ca 140us
			format 			=> 'twostate',	  		
			preamble		=> 'u32#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				
    	},
    "33" => #Thermo-/Hygrosensor S014
    	{   
       		name			=> 'weather33',		#
			id          	=> '33',
			one				=> [1,-8],
			zero			=> [1,-4],
			sync			=> [1,-15],
			clockabs   		=> '500',				# not used now
			format     		=> 'twostate',  		# not used now
			preamble		=> 'W33#',				# prepend to converted message	
			postamble		=> '',					# Append to converted message	 	
			clientmodule    => 'SD_WS',      			# not used now
			#modulematch     => '',     			# not used now
			length_min      => '42',
			length_max      => '44',
    	},
#    "34" =>   # replaced by 37
#     	 {   
#       		name			=> 'unknown34',		
#       		id          	=> '34',
#			one				=> [2,-1],
#			zero			=> [1,-2],
#			start			=> [3,-3,3,-3,3,-3,3,-3],
#			clockabs   		=> '240',		
#			format     		=> 'twostate',  		# not used now
#			preamble		=> 'u34#',				# prepend to converted message	
#			postamble		=> '',					# Append to converted message	 	
#			#clientmodule    => '',      			# not used now
#			#modulematch     => '',     			# not used now
#			length_min      => '40',
#			length_max      => '40',
 #   	},
     "35" =>
     	 {   
       		name			=> 'socket35',		
       		id          	=> '35',
			one				=> [1,-4],
			zero			=> [4,-1],
			sync			=> [1,-19],
			clockabs   		=> '280',		
			format     		=> 'twostate',  		# not used now
			preamble		=> 'u35#',				# prepend to converted message	
			postamble		=> '',					# Append to converted message	 	
			#clientmodule    => '',      			# not used now
			#modulematch     => '',     			# not used now
			length_min      => '28',
			length_max      => '32',
    	},
     "36" =>
     	 {   
       		name			=> 'socket36',		
       		id          	=> '36',
			one				=> [1,-3],
			zero			=> [1,-1],
			start		 	=> [20,-20],
			clockabs   		=> '500',		
			format     		=> 'twostate',  		# not used now
			preamble		=> 'u36#',				# prepend to converted message	
			postamble		=> '',					# Append to converted message	 	
			#clientmodule    => '',      			# not used now
			#modulematch     => '',     			# not used now
			length_min      => '24',
			length_max      => '24',
    	},
    "37" =>	## Bresser 7009994
			# MU;P0=729;P1=-736;P2=483;P3=-251;P4=238;P5=-491;D=010101012323452323454523454545234523234545234523232345454545232345454545452323232345232340;CP=4;
			# MU;P0=-790;P1=-255;P2=474;P4=226;P6=722;P7=-510;D=721060606060474747472121212147472121472147212121214747212147474721214747212147214721212147214060606060474747472121212140;CP=4;R=216;
			# short pulse of 250 us followed by a 500 us gap is a 0 bit
			# long pulse of 500 us followed by a 250 us gap is a 1 bit
			# sync preamble of pulse, gap, 750 us each, repeated 4 times
     	 {   
       		name			=> 'Bresser 7009994',		
       		id          	=> '37',
			one				=> [2,-1],
			zero			=> [1,-2],
			start		 	=> [3,-3,3,-3],
			clockabs   		=> '250',		
			format     		=> 'twostate',  		# not used now
			preamble		=> 'W37#',				# prepend to converted message	
			clientmodule    => 'SD_WS', 
			length_min      => '40',
			length_max      => '41',
    	},
    "38" =>
      	 {   
       		name			=> 'weather38',		
       		id          	=> '38',
			one				=> [1,-10],
			zero			=> [1,-5],
			sync 			=> [1,-25],
			clockabs   		=> '360',		# not used now
			format     		=> 'twostate',  # not used now
			preamble		=> 's',			# prepend to converted message	 	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'CUL_TCM97001',   # not used now
			#modulematch     => '^s[A-Fa-f0-9]+', # not used now
			length_min      => '32',
			length_max      => '32',
			paddingbits     => '8',			
    	},   
	"39" => ## X10 Protocol
		{
			name => 'X10 Protocol',
			id => '39',
			one => [1,-3],
			zero => [1,-1],
			start => [17,-7],
			clockabs => 560, 
			format => 'twostate', 
			preamble => '', # prepend to converted message
			clientmodule => 'RFXX10REC', # not used now
			#modulematch => '^TX......', # not used now
			length_min => '32',
			length_max => '44',
			paddingbits     => '8',		
			postDemodulation => \&SIGNALduino_lengtnPrefix,			
			filterfunc      => 'SIGNALduino_compPattern',
			
			
		},    
	"40" => ## Romotec
		{
			name => 'romotec',
			id => '40',
			one => [3,-2],
			zero => [1,-3],
			start => [1,-2],
			clockabs => 250, 
			preamble => 'u40#', # prepend to converted message
			#clientmodule => '', # not used now
			#modulematch => '', # not used now
			length_min => '10',
			length_min => '12',
			
		},    
	"41" => ## Elro (Smartwares) Doorbell DB200
		{
			name => 'elro doorbell',
			comment => 'Elro (Smartwares) Doorbell DB200',
			id => '41',
			zero => [1,-3],
			one => [3,-1],
			sync => [1,-15],
			clockabs => 450, 
			preamble => 'u41#', # prepend to converted message
			#clientmodule => '', # not used now
			#modulematch => '', # not used now
			length_min => '20',
		},     
	#"42" => ## MKT Multi Kon Trade  // Sollte eigentlich als MS ITv1 erkannt werden
	#	{
	#		name => 'MKT motionsensor',
	#		id => '42',
	#		zero => [1,-3],
	#		one => [3,-1],
	#		sync => [-28],
	#		clockabs => 550, 
	#		preamble => 'u42#', # prepend to converted message
	#		#clientmodule => '', # not used now
	#		#modulematch => '', 
	#		length_min => '24',
	#	},
	"43" => ## Somfy RTS
		{
			name 			=> 'Somfy RTS',
			id 				=> '43',
			clockrange  	=> [610,680],			# min , max
			format			=> 'manchester', 
			preamble 		=> 'Ys',
			clientmodule	=> 'SOMFY', # not used now
			modulematch 	=> '^Ys[0-9A-F]{14}',
			length_min 		=> '56',
			length_max 		=> '57',
			method          => \&SIGNALduino_SomfyRTS, # Call to process this message
			msgIntro		=> 'SR;P0=-2560;P1=2560;P3=-640;D=10101010101010113;',
			#msgOutro		=> 'SR;P0=-30415;D=0;',
			frequency		=> '10AB85550A',
		},
	"44" => ## Bresser Temeo Trend
		{
            		name 			=> 'BresserTemeo',
            		id 			=> '44',
            		clockabs		=> 500,
            		zero 			=> [4,-4],
            		one				=> [4,-8],
            		start	 		=> [8,-8],
            		preamble 		=> 'W44#',
            		clientmodule		=> 'SD_WS',
            		modulematch		=> '^W44#[A-F0-9]{18}',
            		length_min 		=> '64',
            		length_max 		=> '72',
		},
	"44.1" => ## Bresser Temeo Trend
		{
            		name 			=> 'BresserTemeo',
            		id 			=> '44',
            		clockabs		=> 500,
            		zero 			=> [4,-4],
            		one				=> [4,-8],
            		start 			=> [8,-12],
            		preamble 		=> 'W44x#',
            		clientmodule		=> 'SD_WS',
            		modulematch		=> '^W44x#[A-F0-9]{18}',
            		length_min 		=> '64',
            		length_max 		=> '72',
		},

    "45"  => #  Revolt 
			 #	MU;P0=-8320;P1=9972;P2=-376;P3=117;P4=-251;P5=232;D=012345434345434345454545434345454545454543454343434343434343434343434543434345434343434545434345434343434343454343454545454345434343454345434343434343434345454543434343434345434345454543454343434543454345434545;CP=3;R=2
		{
			name         => 'Revolt',
			id           => '45',
			one          => [2,-2],
			zero         => [1,-2],
			start        => [83,-3], 
			clockabs     => 120, 
			preamble     => 'r', # prepend to converted message
			clientmodule => 'Revolt', 
			modulematch  => '^r[A-Fa-f0-9]{22}', 
			length_min   => '84',
			length_max   => '120',	
			postDemodulation => sub {	my ($name, @bit_msg) = @_;	my @new_bitmsg = splice @bit_msg, 0,88;	return 1,@new_bitmsg; },
		},    
    "46"    => 
        {
            name			=> 'EKX1BE',	
			id          	=> '46',
			one				=> [1,-8],
			zero			=> [8,-1],
			clockabs     	=> 250,	# -1=auto	
			format 			=> 'twostate',	# not used now
			preamble		=> 'u46#',			
			#clientmodule    => '',   # not used now
			#modulematch     => '', # not used now
			length_min      => '16',
			length_max 		=> '18',
			
			},
   	"47"    => 			## maverick
		{
            name			=> 'Maverick protocol',	
			id          	=> '47',
			clockrange     	=> [180,260],                   
			format 			=> 'manchester',	
			preamble		=> 'P47#',						# prepend to converted message	
			clientmodule    => 'SD_WS_Maverick',   					
			modulematch     => '^P47#[569A]{12}.*',  					
			length_min      => '100',
			length_max      => '108',
			method          => \&SIGNALduino_Maverick,		# Call to process this message
			#polarity		=> 'invert'
		}, 			
     "48"    => 			## Joker Dostmann TFA
		{
            name			=> 'TFA Dostmann',	
			id          	=> '48',
			clockabs     	=> 250, 						# In real it is 500 but this leads to unprceise demodulation 
			one				=> [-4,6],
			zero			=> [-4,2],
			start			=> [-6,2],
			format 			=> 'twostate',	
			preamble		=> 'U48#',						# prepend to converted message	
			#clientmodule    => '',   						# not used now
			modulematch     => '^U48#.*',  					# not used now
			length_min      => '47',
			length_max      => '48',
		}, 			
	"49"    => 			## quigg / Aldi gt_9000
		{
            name			=> 'quigg_gt9000',	
			id          	=> '49',
			clockabs     	=> 400, 						
			one				=> [2,-1],
			zero			=> [1,-3],
			start			=> [-15,2,-1],
			format 			=> 'twostate',	
			preamble		=> 'U49#',						# prepend to converted message	
			#clientmodule    => '',   						# not used now
			modulematch     => '^U49#.*',  					# not used now
			length_min      => '22',
			length_max      => '28',
		}, 
	"50"    => 			## Opus XT300
		{
      name			=> 'optus_XT300',	
			id          	=> '50',
			clockabs     	=> 500, 						
			zero			=> [3,-2],
			one				=> [1,-2],
		#	start			=> [1,-25],						# Wenn das startsignal empfangen wird, fehlt das 1 bit
			format 			=> 'twostate',	
			preamble		=> 'W50#',						# prepend to converted message	
			clientmodule    => 'SD_WS',   					# not used now
			modulematch     => '^W50#.*',  					# not used now
			length_min      => '47',
			length_max      => '48',
		},
	 "51"    => 
        {  # MS;P0=-16046;P1=552;P2=-1039;P3=983;P5=-7907;P6=-1841;P7=-4129;D=15161716171616161717171716161616161617161717171717171617171617161716161616161616171032323232;CP=1;SP=5;O;
            name			=> 'weather51',		# Logilink, NC, WS, TCM97001 etc.
			comment			=> 'IAN 275901 Wetterstation Lidl',
			id          	=> '51',
			one				=> [1,-8],
			zero			=> [1,-4],
			sync			=> [1,-13],		
			clockabs   		=> '560',		# not used now
			format     		=> 'twostate',  # not used now
			preamble		=> 'W51#',		# prepend to converted message	 	
			postamble		=> '',			# Append to converted message	 	
			clientmodule    => 'SD_WS',   
			modulematch     => '^W51#.*',
			length_min      => '40',
			length_max      => '45',
        },
    "52"    => 			## Oregon PIR Protocol
		{
            name			=> 'OS_PIR',	
			id          	=> '52',
			clockrange     	=> [470,640],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			clientmodule    => 'OREGON',
			modulematch     => '^u52#F{3}|0{3}.*',
			preamble		=> 'u52#',
			length_min      => '30',
			length_max      => '30',
			method          => \&SIGNALduino_OSPIR, # Call to process this message
			polarity        => 'invert',			
		}, 	
    
	"55"  => ##quigg gt1000
		{
            name			=> 'quigg_gt1000',	
			id          	=> '55',
			clockabs     	=> 300, 						
			zero			=> [1,-4],
			one				=> [4,-2],
			sync			=> [1,-8],						
			format 			=> 'twostate',	
			preamble		=> 'i',						# prepend to converted message	
			clientmodule    => 'IT',   					# not used now
			modulematch     => '^i.*',  					# not used now
			length_min      => '24',
			length_max      => '24',
		},	
	"56" => ##  Celexon
		{
			name			=> 'Celexon',	
			id          	=> '56',
			clockabs     	=> 200, 						
			zero			=> [1,-3],
			one				=> [3,-1],
			start			=> [25,-3],						
			format 			=> 'twostate',	
			preamble		=> 'u56#',						# prepend to converted message	
			#clientmodule    => ''	,   					# not used now
			modulematch     => '',  						# not used now
			length_min      => '56',
			length_max      => '68',
		},		
 		"57"    => 			## m-e doorbell
		{
            name			=> 'm-e',	
			id          	=> '57',
			clockrange     	=> [300,360],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			clientmodule    => '',
			modulematch     => '^u57*',
			preamble		=> 'u57#',
			length_min      => '21',
			length_max      => '24',
			method          => \&SIGNALduino_MCRAW, # Call to process this message
			polarity        => 'invert',			
		}, 	 
  		"58"    => 			## tfa 30.3208.0 
		{
            name			=> 'tfa 30.3208.0 ',	
			id          	=> '58',
			clockrange     	=> [460,520],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			clientmodule    => '',
			modulematch     => '^W58*',
			preamble		=> 'W58#',
			length_min      => '54',
			length_max      => '136',
			method          => \&SIGNALduino_MCTFA, # Call to process this message
			polarity        => 'invert',			
		}, 	 
		"59" => ##  AK-HD-4 remote
		{
			name			=> 'AK-HD-4',	
			id          	=> '59',
			clockabs     	=> 230, 						
			zero			=> [-4,1],
			one				=> [-1,4],
			start			=> [-1,37],						
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'u59#',			# Append to converted message	
			postamble		=> '',		# Append to converted message	 	
			#clientmodule    => '',   		# not used now
			modulematch     => '',  # not used now
			length_min      => '24',
			length_max      => '24',
		},			
  "60" =>	## ELV, LA CROSSE (WS2000/WS7000)
  {
     	# MU;P0=32001;P1=-381;P2=835;P3=354;P4=-857;D=01212121212121212121343421212134342121213434342121343421212134213421213421212121342121212134212121213421212121343421343430;CP=2;R=53;			# tested sensors:  	WS-7000-20, AS2000, ASH2000, S2000, S2000I, S2001A, S2001IA,
     	#                    ASH2200, S300IA, S2001I, S2000ID, S2001ID, S2500H 
     	# not tested:        AS3, S2000W, S2000R, WS7000-15, WS7000-16, WS2500-19, S300TH, S555TH
     	# das letzte Bit 1 und 1 x 0 Preambel fehlt meistens
	    #  ___        _
	    # |   |_     | |___
	    #  Bit 0      Bit 1
	    # kurz 366 µSek / lang 854 µSek / gesamt 1220 µSek - Sollzeiten 
	  		name                 => 'WS2000',
     		id                   => '60',
     		one                  => [3,-7],	
     		zero                 => [7,-3],
	     	clockabs             => 122,
     		preamble      	 	   => 'K',        # prepend to converted message
     		postamble     	 	   => '',         # Append to converted message
     		clientmodule         => 'CUL_WS',   
     		length_min           => '44',	      # eigentlich 46
     		length_max           => '82',	      # eigentlich 81
			postDemodulation     => \&SIGNALduino_postDemo_WS2000,
	}, 

	"61" =>	## ELV FS10
		# tested transmitter:   FS10-S8, FS10-S4, FS10-ZE
		# tested receiver:      FS10-ST, FS10-MS, WS3000-TV, PC-Wettersensor-Empfaenger
		# das letzte Bit 1 und 1 x 0 Preambel fehlt immer
		{
			name   		=> 'FS10',
			id		=> '61',
			one		=> [1,-2],
			zero		=> [1,-1],
			clockabs	=> 400,
			format 		=> 'twostate',
			preamble	=> 'P61#',      # prepend to converted message
			postamble	=> '',         # Append to converted message
			clientmodule	=> 'FS10',
			#modulematch	=> '',
			length_min	=> '38',	# eigentlich 41 oder 46 (Pruefsumme nicht bei allen)
			length_max      => '48',	# eigentlich 46
			
		}, 
	"62" => ## Clarus_Switch  
		{    #MU;P0=-5893;P4=-634;P5=498;P6=-257;P7=116;D=45656567474747474745656707456747474747456745674567456565674747474747456567074567474747474567456745674565656747474747474565670745674747474745674567456745656567474747474745656707456747474747456745674567456565674747474747456567074567474747474567456745674567;CP=7;O;
			name         => 'Clarus_Switch',
			id           => '62',
			one          => [3,-1],
			zero         => [1,-3],
			start        => [1,-35], # ca 30-40
			clockabs     => 189, 
			preamble     => 'i', # prepend to converted message
			clientmodule => 'IT', 
			#modulematch => '', 
			length_min   => '24',
			length_max   => '24',		
		},
	"63" => ## Warema MU
		{    #MU;P0=-2988;P1=1762;P2=-1781;P3=-902;P4=871;P5=6762;P6=5012;D=0121342434343434352434313434243521342134343436;
			name         => 'Warema',
			comment      => 'developId, is still experimental',
			id           => '63',
			developId    => 'y',
			one          => [1],
			zero         => [0],
			clockabs     => 800, 
			syncabs		 => '6700',# Special field for filterMC function
			preamble     => 'u63', # prepend to converted message
			#clientmodule => '', 
			#modulematch => '', 
			length_min   => '24',
			filterfunc   => 'SIGNALduino_filterMC',
		},
	"64" => ##  WH2 #############################################################################
		{
    # MU;P0=-32001;P1=457;P2=-1064;P3=1438;D=0123232323212121232123232321212121212121212323212121232321;CP=1;R=63;
    # MU;P0=-32001;P1=473;P2=-1058;P3=1454;D=0123232323212121232123232121212121212121212121232321212321;CP=1;R=51;
    #MU;P0=134;P1=-113;P3=412;P4=-1062;P5=1379;D=01010101013434343434343454345454345454545454345454545454343434545434345454345454545454543454543454345454545434545454345;CP=3;

			name         => 'WH2',
			id           => '64',
      one          => [1,-2],   
      zero			   => [3,-2], 
      clockabs     => 490,
      clientmodule    => 'SD_WS',  
			modulematch  => '^W64*',
			preamble     => 'W64#',       # prepend to converted message
			postamble    => '',           # Append to converted message       
			#clientmodule => '',
			length_min   => '48',
			length_max   => '54',
		},
	"65" => ## Homeeasy
		{
			name         => 'Homeeasy',
			id           => '65',
			one          => [1,-5],
			zero         => [1,-1],
			start        => [1,-40],
			clockabs     => 250,
			format       => 'twostate',  # not used now
			preamble     => 'U65#',
			length_min   => '50',
			#msgOutro     => 'SR;P0=275;P1=-7150;D=01;',
			postDemodulation => \&SIGNALduino_HE,
		},
	"66" => ## TX2 Protocol (Remote Temp Transmitter & Remote Thermo Model 7035)
	# MU;P0=13312;P1=-2785;P2=4985;P3=1124;P4=-6442;P5=3181;P6=-31980;D=0121345434545454545434545454543454545434343454543434545434545454545454343434545434343434545621213454345454545454345454545434545454343434545434345454345454545454543434345454343434345456212134543454545454543454545454345454543434345454343454543454545454545;CP=3;R=73;O;
		{
			name         => 'WS7035',
			id           => '66',
			one          => [10,-52],
			zero         => [27,-52],
			start        => [-21,42,-21],
			clockabs     => 122,
			format       => 'pwm',  # not used now
			preamble     => 'TX',
			clientmodule => 'CUL_TX',
			modulematch  => '^TX......',
			length_min   => '43',
			length_max   => '44',
			postDemodulation => \&SIGNALduino_postDemo_WS7035,
		},
 	"67" => ## TX2 Protocol (Remote Datalink & Remote Thermo Model 7053)
            # MU;P0=3381;P1=-672;P2=-4628;P3=1142;P4=-30768;D=0102320232020202020232020232020202320232323202323202020202020202020401023202320202020202320202320202023202323232023232020202020202020200;CP=0;R=45;
            # MU;P0=1148;P1=3421;P6=-664;P7=-4631;D=16170717071717171717071717071717171717070707170717171717070717171710;CP=1;R=29;
            # MU;P0=3389;P3=2560;P4=-720;P5=1149;P7=-4616;D=345407570757070707070757070757070707070757570707075707070707570757575;CP=5;R=253;
            #           __               ____
            #  ________|  |     ________|    |
            #      Bit 1             Bit 0
            #    4630  1220       4630   3420   µSek - mit Oszi gemessene Zeiten
      {
			name           => 'WS7053',	
			id             => '67',
         	one            => [-38,10],
         	zero           => [-38,28],      
         	clockabs       => 122,
         	preamble	      => 'TX', 	      # prepend to converted message
         	clientmodule   => 'CUL_TX',
         	modulematch    => '^TX......',
         	length_min     => '32',
         	length_max     => '34',
         	postDemodulation => \&SIGNALduino_postDemo_WS7053,
      },
  "68" => ##  PFR-130 ###########################################################################
		{
    # MS;P0=-3890;P1=386;P2=-2191;P3=-8184;D=1312121212121012121212121012121212101012101010121012121210121210101210101012;CP=1;SP=3;R=20;O;
    # MS;P0=-2189;P1=371;P2=-3901;P3=-8158;D=1310101010101210101010101210101010121210121212101210101012101012121012121210;CP=1;SP=3;R=20;O;
			name         => 'PFR-130',
			id           => '68',
      		one				=> [1,-10],
			zero			=> [1,-5],
      		sync			=> [1,-21],	
			clockabs   		=> 380,		# not used now
      		preamble		=> 's',			# prepend to converted message	 	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'CUL_TCM97001',   # not used now
     		length_min      => '24',
			length_max      => '42',
			paddingbits     => '8',				 # pad up to 8 bits, default is 4
		}, 	
	"69"    => ## Hoermann
	# MU;P0=-508;P1=1029;P2=503;P3=-1023;P4=12388;D=01010232323232310104010101010101010102323231010232310231023232323231023101023101010231010101010232323232310104010101010101010102323231010232310231023232323231023101023101010231010101010232323232310104010101010101010102323231010232310231023232323231023101;CP=2;R=37;O;
		{
			name            => 'Hoermann',
			id              => '69',
			zero            => [2,-1],
			one             => [1,-2],
			start           => [24,-1],
			clockabs        => 510,
			format          => 'twostate',  # not used now
			#clientmodule    => '',
			#modulematch     => '^U69*',
			preamble        => 'U69#',
			length_min      => '40',
			#length_max      => '90',
			postDemodulation => \&SIGNALduino_postDemo_Hoermann,	# Call to process this message
		},
	"70" => ## FHT80TF (Funk-Tuer-Fenster-Melder FHT 80TF und FHT 80TF-2)
	# closed MU;P0=-24396;P1=417;P2=-376;P3=610;P4=-582;D=012121212121212121212121234123434121234341212343434121234123434343412343434121234341212121212341212341234341234123434;CP=1;R=35;
	# open   MU;P0=-21652;P1=429;P2=-367;P4=634;P5=-555;D=012121212121212121212121245124545121245451212454545121245124545454512454545121245451212121212124512451245451245121212;CP=1;R=38;
		{
			name         	=> 'FHT80TF',
			comment		   => 'Door/Window switch (868Mhz)',
			id           	=> '70',
			one         	=> [1.5,-1.5],	# 600
			zero         	=> [1,-1],	# 400
			clockabs     	=> 400,
			format          => 'twostate',  # not used now
			clientmodule    => 'CUL_FHTTK',
			preamble     	=> 'T',
			length_min     => '50',
			length_max     => '58',
			postDemodulation => \&SIGNALduino_postDemo_FHT80TF,
		},
	"71" => ## PV-8644 infactory Poolthermometer
		# MU;P0=1735;P1=-1160;P2=591;P3=-876;D=0123012323010101230101232301230123010101010123012301012323232323232301232323232323232323012301012;CP=2;R=97;
		{
			name		=> 'PV-8644',
			comment		=> 'infactory Poolthermometer',
			id         	=> '71',
			clockabs	=> 580,
			zero		=> [3,-2],
			one		=> [1,-1.5],
			format		=> 'twostate',	
			preamble	=> 'W71#',		# prepend to converted message	
			clientmodule    => 'SD_WS',
			#modulematch     => '^W71#.*'
			length_min      => '48',
			length_max      => '48',
		},
	# MU;P0=-760;P1=334;P2=693;P3=-399;P4=-8942;P5=4796;P6=-1540;D=01010102310232310101010102310232323101010102310101010101023102323102323102323102310101010102310232323101010102310101010101023102310231023102456102310232310232310231010101010231023232310101010231010101010102310231023102310245610231023231023231023101010101;CP=1;R=45;O;
    # MU;P0=-8848;P1=4804;P2=-1512;P3=336;P4=-757;P5=695;P6=-402;D=0123456345656345656345634343434345634565656343434345634343434343456345634563456345;CP=3;R=49;
    		
	"72" => # Siro blinds MU    @Dr. Smag
		{
			name			=> 'Siro shutter',
			comment         => 'developModule. Siro is not in github or SVN available',
			id				=> '72',
			developId		=> 'm',
			dispatchequals  =>  'true',
			one				=> [2,-1.2],    # 680, -400
			zero			=> [1,-2.2],    # 340, -750
			start			=> [14,-4.4],   # 4800,-1520
			clockabs		=> 340,
			format 			=> 'twostate',	  		
			preamble		=> 'P72#',		# prepend to converted message	
			clientmodule	=> 'Siro',
			#modulematch 	=> '',  			
			length_min   	=> '39',
			length_max   	=> '40',
			msgOutro		=> 'SR;P0=-8500;D=0;',
		},
 	
 	# MS;P0=4803;P1=-1522;P2=333;P3=-769;P4=699;P5=-393;P6=-9190;D=2601234523454523454523452323232323452345454523232323452323232323234523232345454545;CP=2;SP=6;R=61;
 	"72.1" => # Siro blinds MS     @Dr. Smag
		{
			name			=> 'Siro shutter',
			comment     	=> 'developModule. Siro is not in github or SVN available',
			id				=> '72',
			developId		=> 'm',
			dispatchequals  =>  'true',
			one				=> [2,-1.2],    # 680, -400
			zero			=> [1,-2.2],    # 340, -750
			sync			=> [14,-4.4],   # 4800,-1520
			clockabs		=> 340,
			format 			=> 'twostate',	  		
			preamble		=> 'P72#',		# prepend to converted message	
			clientmodule	=> 'Siro',
			#modulematch 	=> '',  			
			length_min   	=> '39',
			length_max   	=> '40',
			#msgOutro	=> 'SR;P0=-8500;D=0;',
		},
	"73" => ## FHT80 - Raumthermostat (868Mhz),  @HomeAutoUser
		{
			name		=> 'FHT80',
			comment 	=> 'Roomthermostat (868Mhz only receive)',
			id		=> '73',
			developId	=> 'y',
			one		=> [1.5,-1.5], # 600
			zero		=> [1,-1], # 400
			clockabs	=> 400,
			format		=> 'twostate', # not used now
			clientmodule	=> 'FHT',
			preamble	=> '810c04xx0909a001',
			length_min	=> '59',
			length_max	=> '67',
			postDemodulation => \&SIGNALduino_postDemo_FHT80,
		},
	"74" => ## FS20 - 'Remote Control (868Mhz),  @HomeAutoUser
		{
			name			=> 'FS20',
			comment			=> 'Remote Control (868Mhz only receive)',
			id			=> '74',
			developId		=> 'y',
			one			=> [1.5,-1.5], # 600
			zero			=> [1,-1], # 400
			clockabs		=> 400,
			format			=> 'twostate', # not used now
			clientmodule		=> 'FS20',
			preamble		=> '810b04f70101a001',
			length_min		=> '50',
			length_max		=> '67',
			postDemodulation => \&SIGNALduino_postDemo_FS20,
		},
	"75" => ## ConradRSL2 @litronics https://github.com/RFD-FHEM/SIGNALDuino/issues/69
		# MU;P0=-1365;P1=477;P2=1145;P3=-734;P4=-6332;D=01023202310102323102423102323102323101023232323101010232323231023102323102310102323102423102323102323101023232323101010232323231023102323102310102323102;CP=1;R=12;
		{
			name			=> 'ConradRSL2', 
			id			=> '75',
			one			=> [3,-1],
			zero			=> [1,-3],
			clockabs		=> 500, 
			format			=> 'twostate', 
			clientmodule		=> 'SD_RSL',
			preamble		=> 'P1#',  
			modulematch		=> '^P1#[A-Fa-f0-9]{8}', 
			length_min		=> '32',
			length_max 		=> '40',
		},
	"76" => ##  Kabellose LED-Weihnachtskerzen XM21-0
		{
			name			=> 'xm21',
			comment			=> 'reserviert, LED Lichtrekette on',
			id				=> '76',
			developId		=> 'p',
			one				=> [1.2,-2], # 120,-200
			zero			=> [],   # existiert nicht
			start           => [4.5,-2], # 450,-200 Starsequenz
			clockabs		=> 100,
			format			=> 'twostate', # not used now
			clientmodule	=> '',
			preamble		=> 'P76',
			length_min		=> 64,
			length_max		=> 64,
		},
	"76.1" => ##  Kabellose LED-Weihnachtskerzen XM21-0
		{
			name			=> 'xm21',
			comment			=> 'reserviert, LED Lichtrekette off',
			id				=> '76.1',
			developId		=> 'p', 
			one				=> [1.2,-2], # 120,-200
			zero			=> [],   # existiert nicht
			start           => [4.5,-2], # 450,-200 Starsequenz
			clockabs		=> 100,
			format			=> 'twostate', # not used now
			clientmodule	=> '',
			preamble		=> 'P76',
			length_min		=> 58,
			length_max		=> 58,
		},

);





sub
SIGNALduino_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "SIGNALduino_Read";
  $hash->{WriteFn} = "SIGNALduino_Write";
  $hash->{ReadyFn} = "SIGNALduino_Ready";

# Normal devices
  $hash->{DefFn}  		 	= "SIGNALduino_Define";
  $hash->{FingerprintFn} 	= "SIGNALduino_FingerprintFn";
  $hash->{UndefFn} 		 	= "SIGNALduino_Undef";
  $hash->{GetFn}   			= "SIGNALduino_Get";
  $hash->{SetFn}   			= "SIGNALduino_Set";
  $hash->{AttrFn}  			= "SIGNALduino_Attr";
  $hash->{AttrList}			= 
                       "Clients MatchList do_not_notify:1,0 dummy:1,0"
					  ." hexFile"
                      ." initCommands"
                      ." flashCommand"
  					  ." hardware:nano328,uno,promini328,nanoCC1101"
					  ." debug:0,1"
					  ." longids"
					  ." minsecs"
					  ." whitelist_IDs"
					  ." blacklist_IDs"
					  ." WS09_CRCAUS:0,1,2"
					  ." addvaltrigger"
					  ." rawmsgEvent:1,0"
					  ." cc1101_frequency"
					  ." doubleMsgCheck_IDs"
					  ." suppressDeviceRawmsg:1,0"
					  ." development"
					  ." noMsgVerbose:0,1,2,3,4,5"
		              ." $readingFnAttributes";

  $hash->{ShutdownFn} = "SIGNALduino_Shutdown";
  
  $hash->{msIdList} = ();
  $hash->{muIdList} = ();
  $hash->{mcIdList} = ();
  
}

sub
SIGNALduino_FingerprintFn($$)
{
  my ($name, $msg) = @_;

  # Store only the "relevant" part, as the Signalduino won't compute the checksum
  #$msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);

  return ($name, $msg);
}

#####################################
sub
SIGNALduino_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> SIGNALduino {none | devicename[\@baudrate] | devicename\@directio | hostname:port}";
    Log3 undef, 2, $msg;
    return $msg;
  }
  
  DevIo_CloseDev($hash);
  my $name = $a[0];

  
  if (!exists &round)
  {
      Log3 $name, 1, "$name: Signalduino can't be activated (sub round not found). Please update Fhem via update command";
	  return undef;
  }
  
  my $dev = $a[2];
  #Debug "dev: $dev" if ($debug);
  #my $hardware=AttrVal($name,"hardware","nano328");
  #Debug "hardware: $hardware" if ($debug);
 
 
  if($dev eq "none") {
    Log3 $name, 1, "$name: device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    #return undef;
  }
  

  if ($dev ne "none" && $dev =~ m/[a-zA-Z]/ && $dev !~ m/\@/) {    # bei einer IP wird kein \@57600 angehaengt
	$dev .= "\@57600";
  }	
  
  #$hash->{CMDS} = "";
  $hash->{Clients} = $clientsSIGNALduino;
  $hash->{MatchList} = \%matchListSIGNALduino;
  

  #if( !defined( $attr{$name}{hardware} ) ) {
  #  $attr{$name}{hardware} = "nano328";
  #}


  if( !defined( $attr{$name}{flashCommand} ) ) {
#    $attr{$name}{flashCommand} = "avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]"
     $attr{$name}{flashCommand} = "avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]"; 
    
  }
  $hash->{DeviceName} = $dev;
  
  my $ret=undef;
  
  InternalTimer(gettimeofday(), 'SIGNALduino_IdList',"sduino_IdList:$name",0);       # verzoegern bis alle Attribute eingelesen sind
  
  if($dev ne "none") {
    $ret = DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
  } else {
		$hash->{DevState} = 'initialized';
  		readingsSingleUpdate($hash, "state", "opened", 1);
  }
  
  $hash->{DMSG}="nothing";
  $hash->{LASTDMSG} = "nothing";
  $hash->{TIME}=time();
  

  
  Log3 $name, 3, "$name: Firmwareversion: ".$hash->{READINGS}{version}{VAL}  if ($hash->{READINGS}{version}{VAL});

  return $ret;
}

###############################
sub SIGNALduino_Connect($$)
{
	my ($hash, $err) = @_;

	# damit wird die err-msg nur einmal ausgegeben
	if (!defined($hash->{disConnFlag}) && $err) {
		SIGNALduino_Log3($hash, 3, "SIGNALduino $hash->{NAME}: ${err}");
		Log3($hash, 3, "SIGNALduino $hash->{NAME}: ${err}");
		$hash->{disConnFlag} = 1;
	}
}

#####################################
sub
SIGNALduino_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  
 

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "$name: deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  SIGNALduino_Shutdown($hash);
  
  DevIo_CloseDev($hash); 
  RemoveInternalTimer($hash);    
  return undef;
}

#####################################
sub
SIGNALduino_Shutdown($)
{
  my ($hash) = @_;
  #DevIo_SimpleWrite($hash, "XQ\n",2);
  SIGNALduino_SimpleWrite($hash, "XQ");  # Switch reception off, it may hang up the SIGNALduino
  return undef;
}

#####################################
#$hash,$name,"sendmsg","P17;R6#".substr($arg,2)

sub
SIGNALduino_Set($@)
{
  my ($hash, @a) = @_;
  
  return "\"set SIGNALduino\" needs at least one parameter" if(@a < 2);

  #Log3 $hash, 3, "SIGNALduino_Set called with params @a";


  my $hasCC1101 = 0;
  my $CC1101Frequency;
  if ($hash->{version} && $hash->{version} =~ m/cc1101/) {
    $hasCC1101 = 1;
    if (!defined($hash->{cc1101_frequency})) {
       $CC1101Frequency = "433";
    } else {
       $CC1101Frequency = $hash->{cc1101_frequency};
    }
  }
  if (!defined($sets{$a[1]})) {
    my $arguments = ' ';
    foreach my $arg (sort keys %sets) {
      next if ($arg =~ m/cc1101/ && $hasCC1101 == 0);
      if ($arg =~ m/patable/) {
        next if (substr($arg, -3) ne $CC1101Frequency);
      }
      $arguments.= $arg . ($sets{$arg} ? (':' . $sets{$arg}) : '') . ' ';
    }
    #Log3 $hash, 3, "set arg = $arguments";
    return "Unknown argument $a[1], choose one of " . $arguments;
  }

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);
  
  if ($cmd =~ m/cc1101/ && $hasCC1101 == 0) {
    return "This command is only available with a cc1101 receiver";
  }
  
  return "$name is not active, may firmware is not suppoted, please flash or reset" if ($cmd ne 'reset' && $cmd ne 'flash' && exists($hash->{DevState}) && $hash->{DevState} ne 'initialized');

  if ($cmd =~ m/^cc1101_/) {
     $cmd = substr($cmd,7);
  }
  
  if($cmd eq "raw") {
    Log3 $name, 4, "set $name $cmd $arg";
    #SIGNALduino_SimpleWrite($hash, $arg);
    SIGNALduino_AddSendQueue($hash,$arg);
  } elsif( $cmd eq "flash" ) {
    my @args = split(' ', $arg);
    my $log = "";
    my $hexFile = "";
    my @deviceName = split('@', $hash->{DeviceName});
    my $port = $deviceName[0];
	my $hardware=AttrVal($name,"hardware","nano328");
	my $baudrate=$hardware eq "uno" ? 115200 : 57600;
    my $defaultHexFile = "./FHEM/firmware/$hash->{TYPE}_$hardware.hex";
    my $logFile = AttrVal("global", "logdir", "./log/") . "$hash->{TYPE}-Flash.log";

    if(!$arg || $args[0] !~ m/^(\w|\/|.)+$/) {
      $hexFile = AttrVal($name, "hexFile", "");
      if ($hexFile eq "") {
        $hexFile = $defaultHexFile;
      }
    }
    elsif ($args[0] =~ m/^https?:\/\// ) {
		my $http_param = {
		                    url        => $args[0],
		                    timeout    => 5,
		                    hash       => $hash,                                  # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
		                    method     => "GET",                                  # Lesen von Inhalten
		                    callback   =>  \&SIGNALduino_ParseHttpResponse,        # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
		                    command    => 'flash',
		                };
		
		HttpUtils_NonblockingGet($http_param);       
		return;  	
    } else {
      $hexFile = $args[0];
    }
	Log3 $name, 3, "$name: filename $hexFile provided, trying to flash";
 
    return "Usage: set $name flash [filename]\n\nor use the hexFile attribute" if($hexFile !~ m/^(\w|\/|.)+$/);

    $log .= "flashing Arduino $name\n";
    $log .= "hex file: $hexFile\n";
    $log .= "port: $port\n";
    $log .= "log file: $logFile\n";

    my $flashCommand = AttrVal($name, "flashCommand", "");

    if($flashCommand ne "") {
      if (-e $logFile) {
        unlink $logFile;
      }

      DevIo_CloseDev($hash);
      $hash->{STATE} = "disconnected";
      $log .= "$name closed\n";

      my $avrdude = $flashCommand;
      $avrdude =~ s/\Q[PORT]\E/$port/g;
      $avrdude =~ s/\Q[BAUDRATE]\E/$baudrate/g;
      $avrdude =~ s/\Q[HEXFILE]\E/$hexFile/g;
      $avrdude =~ s/\Q[LOGFILE]\E/$logFile/g;

      $log .= "command: $avrdude\n\n";
      `$avrdude`;

      local $/=undef;
      if (-e $logFile) {
        open FILE, $logFile;
        my $logText = <FILE>;
        close FILE;
        $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
        $log .= $logText;
        $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
      }
      else {
        $log .= "WARNING: avrdude created no log file\n\n";
      }

    }
    else {
      $log .= "\n\nNo flashCommand found. Please define this attribute.\n\n";
    }

    DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
    $log .= "$name opened\n";

    return $log;

  } elsif ($cmd =~ m/reset/i) {
	delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
	return SIGNALduino_ResetDevice($hash);
  } elsif( $cmd eq "close" ) {
	$hash->{DevState} = 'closed';
	return SIGNALduino_CloseDevice($hash);
  } elsif( $cmd eq "disableMessagetype" ) {
	my $argm = 'CD' . substr($arg,-1,1);
	#SIGNALduino_SimpleWrite($hash, $argm);
	SIGNALduino_AddSendQueue($hash,$argm);
	Log3 $name, 4, "set $name $cmd $arg $argm";;
  } elsif( $cmd eq "enableMessagetype" ) {
	my $argm = 'CE' . substr($arg,-1,1);
	#SIGNALduino_SimpleWrite($hash, $argm);
	SIGNALduino_AddSendQueue($hash,$argm);
	Log3 $name, 4, "set $name $cmd $arg $argm";
  } elsif( $cmd eq "freq" ) {
	if ($arg eq "") {
		$arg = AttrVal($name,"cc1101_frequency", 433.92);
	}
	my $f = $arg/26*65536;
	my $f2 = sprintf("%02x", $f / 65536);
	my $f1 = sprintf("%02x", int($f % 65536) / 256);
	my $f0 = sprintf("%02x", $f % 256);
	$arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
	Log3 $name, 3, "$name: Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
	SIGNALduino_AddSendQueue($hash,"W0F$f2");
	SIGNALduino_AddSendQueue($hash,"W10$f1");
	SIGNALduino_AddSendQueue($hash,"W11$f0");
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "bWidth" ) {
	SIGNALduino_AddSendQueue($hash,"C10");
	$hash->{getcmd}->{cmd} = "bWidth";
	$hash->{getcmd}->{arg} = $arg;
  } elsif( $cmd eq "rAmpl" ) {
	return "a numerical value between 24 and 42 is expected" if($arg !~ m/^\d+$/ || $arg < 24 || $arg > 42);
	my ($v, $w);
	for($v = 0; $v < @ampllist; $v++) {
		last if($ampllist[$v] > $arg);
	}
	$v = sprintf("%02d", $v-1);
	$w = $ampllist[$v];
	Log3 $name, 3, "$name: Setting AGCCTRL2 (1B) to $v / $w dB";
	SIGNALduino_AddSendQueue($hash,"W1D$v");
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "sens" ) {
	return "a numerical value between 4 and 16 is expected" if($arg !~ m/^\d+$/ || $arg < 4 || $arg > 16);
	my $w = int($arg/4)*4;
	my $v = sprintf("9%d",$arg/4-1);
	Log3 $name, 3, "$name: Setting AGCCTRL0 (1D) to $v / $w dB";
	SIGNALduino_AddSendQueue($hash,"W1F$v");
	SIGNALduino_WriteInit($hash);
  } elsif( substr($cmd,0,7) eq "patable" ) {
	my $paFreq = substr($cmd,8);
	my $pa = "x" . $patable{$paFreq}{$arg};
	Log3 $name, 3, "$name: Setting patable $paFreq $arg $pa";
	SIGNALduino_AddSendQueue($hash,$pa);
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "sendMsg" ) {
	Log3 $name, 5, "$name: sendmsg msg=$arg";
	my ($protocol,$data,$repeats,$clock,$frequency) = split("#",$arg);
	$protocol=~ s/[Pp](\d+)/$1/; # extract protocol num
	$repeats=~ s/[rR](\d+)/$1/; # extract repeat num
	$repeats=1 if (!defined($repeats));
	if (defined($clock) && substr($clock,0,1) eq "F") {   # wenn es kein clock gibt, pruefen ob im clock eine frequency ist
		$clock=~ s/[F]([0-9a-fA-F]+$)/$1/;
		$frequency = $clock;
		$clock = undef;
	} else {
		$clock=~ s/[Cc](\d+)/$1/ if (defined($clock)); # extract ITClock num
		$frequency=~ s/[Ff]([0-9a-fA-F]+$)/$1/ if (defined($frequency));
	}
	if (exists($ProtocolListSIGNALduino{$protocol}{frequency}) && $hasCC1101 && !defined($frequency)) {
		$frequency = $ProtocolListSIGNALduino{$protocol}{frequency};
	}
	if (defined($frequency) && $hasCC1101) {
		$frequency="F=$frequency;";
	} else {
		$frequency="";
	}
	
	return "$name: sendmsg, unknown protocol: $protocol" if (!exists($ProtocolListSIGNALduino{$protocol}));
	
	#print ("data = $data \n");
	#print ("protocol = $protocol \n");
    #print ("repeats = $repeats \n");
    
	my %signalHash;
	my %patternHash;
	my $pattern="";
	my $cnt=0;
	
	my $sendData;
	if  ($ProtocolListSIGNALduino{$protocol}{format} eq 'manchester')
	{
		#$clock = (map { $clock += $_ } @{$ProtocolListSIGNALduino{$protocol}{clockrange}}) /  2 if (!defined($clock));
		
		$clock += $_ for(@{$ProtocolListSIGNALduino{$protocol}{clockrange}});
		$clock = round($clock/2,0);
		if ($protocol == 43) {
			#$data =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
		}
		
		my $intro = "";
		my $outro = "";
		
		$intro = $ProtocolListSIGNALduino{$protocol}{msgIntro} if ($ProtocolListSIGNALduino{$protocol}{msgIntro});
		$outro = $ProtocolListSIGNALduino{$protocol}{msgOutro}.";" if ($ProtocolListSIGNALduino{$protocol}{msgOutro});

		if ($intro ne "" || $outro ne "")
		{
			$intro = "SC;R=$repeats;" . $intro;
			$repeats = 0;
		}

		$sendData = $intro . "SM;" . ($repeats > 0 ? "R=$repeats;" : "") . "C=$clock;D=$data;" . $outro . $frequency; #	SM;R=2;C=400;D=AFAFAF;
		Log3 $name, 5, "$name: sendmsg Preparing manchester protocol=$protocol, repeats=$repeats, clock=$clock data=$data";
	} else {
		if ($protocol == 3 || substr($data,0,2) eq "is") {
			if (substr($data,0,2) eq "is") {
				$data = substr($data,2);   # is am Anfang entfernen
			}
			$data = SIGNALduino_ITV1_tristateToBit($data);
			Log3 $name, 5, "$name: sendmsg IT V1 convertet tristate to bits=$data";
		}
		if (!defined($clock)) {
			$hash->{ITClock} = 250 if (!defined($hash->{ITClock}));   # Todo: Klaeren wo ITClock verwendet wird und ob wir diesen Teil nicht auf Protokoll 3,4 und 17 minimieren
			$clock=$ProtocolListSIGNALduino{$protocol}{clockabs} > 1 ?$ProtocolListSIGNALduino{$protocol}{clockabs}:$hash->{ITClock};
		}

		Log3 $name, 5, "$name: sendmsg Preparing rawsend command for protocol=$protocol, repeats=$repeats, clock=$clock bits=$data";
		
		foreach my $item (qw(sync start one zero float))
		{
		    #print ("item= $item \n");
		    next if (!exists($ProtocolListSIGNALduino{$protocol}{$item}));
		    
			foreach my $p (@{$ProtocolListSIGNALduino{$protocol}{$item}})
			{
			    #print (" p = $p \n");
			    
			    if (!exists($patternHash{$p}))
				{
					$patternHash{$p}=$cnt;
					$pattern.="P".$patternHash{$p}."=".$p*$clock.";";
					$cnt++;
				}
		    	$signalHash{$item}.=$patternHash{$p};
			   	#print (" signalHash{$item} = $signalHash{$item} \n");
			}
		}
		my @bits = split("", $data);
	
		my %bitconv = (1=>"one", 0=>"zero", 'D'=> "float");
		my $SignalData="D=";
		
		$SignalData.=$signalHash{sync} if (exists($signalHash{sync}));
		$SignalData.=$signalHash{start} if (exists($signalHash{start}));
		foreach my $bit (@bits)
		{
			next if (!exists($bitconv{$bit}));
			#Log3 $name, 5, "encoding $bit";
			$SignalData.=$signalHash{$bitconv{$bit}}; ## Add the signal to our data string
		}
		$sendData = "SR;R=$repeats;$pattern$SignalData;$frequency";
	}

	
	#SIGNALduino_SimpleWrite($hash, $sendData);
	SIGNALduino_AddSendQueue($hash,$sendData);
	Log3 $name, 4, "$name/set: sending via SendMsg: $sendData";
	
  } else {
  	Log3 $name, 5, "$name/set: set $name $cmd $arg";
	#SIGNALduino_SimpleWrite($hash, $arg);
	return "Unknown argument $cmd, choose one of ". ReadingsVal($name,'cmd',' help me');
  }

  return undef;
}

#####################################
sub
SIGNALduino_Get($@)
{
  my ($hash, @a) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  return "$name is not active, may firmware is not suppoted, please flash or reset" if (exists($hash->{DevState}) && $hash->{DevState} ne 'initialized');
  #my $name = $a[0];
  
  Log3 $name, 5, "\"get $type\" needs at least one parameter" if(@a < 2);
  return "\"get $type\" needs at least one parameter" if(@a < 2);
  if(!defined($gets{$a[1]})) {
    my @cList = map { $_ =~ m/^(file|raw|ccreg)$/ ? $_ : "$_:noArg" } sort keys %gets;
    return "Unknown argument $a[1], choose one of " . join(" ", @cList);
  }

  my $arg = ($a[2] ? $a[2] : "");
  return "no command to send, get aborted." if (length($gets{$a[1]}[0]) == 0 && length($arg) == 0);
  
  if (($a[1] eq "ccconf" || $a[1] eq "ccreg" || $a[1] eq "ccpatable") && $hash->{version} && $hash->{version} !~ m/cc1101/) {
    return "This command is only available with a cc1101 receiver";
  }
  
  my ($msg, $err);

  if (IsDummy($name))
  {
  	if ($arg =~ /^M[CSU];.*/)
  	{
		$arg="\002$arg\003";  	## Add start end end marker if not already there
		Log3 $name, 5, "$name/msg adding start and endmarker to message";
	
	}
	if ($arg =~ /\002M.;.*;\003$/)
	{
		Log3 $name, 4, "$name/msg get raw: $arg";
		return SIGNALduino_Parse($hash, $hash, $hash->{NAME}, $arg);
  	}
  	else {
		my $arg2 = "";
		if ($arg =~ m/^version=/) {           # set version
			$arg2 = substr($arg,8);
			$hash->{version} = "V " . $arg2;
		}
		elsif ($arg =~ m/^regexp=/) {         # set fileRegexp for get raw messages from file
			$arg2 = substr($arg,7);
			$hash->{fileRegexp} = $arg2;
			delete($hash->{fileRegexp}) if (!$arg2);
		}
		elsif ($arg =~ m/^file=/) {
			$arg2 = substr($arg,5);
			my $n = 0;
			if (open(my $fh, '<', $arg2)) {
				my $fileRegexp = $hash->{fileRegexp};
				while (my $row = <$fh>) {
					if ($row =~ /.*\002M.;.*;\003$/) {
						chomp $row;
						$row =~ s/.*\002(M.;.*;)\003/$1/;
						if (!defined($fileRegexp) || $row =~ m/$fileRegexp/) {
							$n += 1;
							$row="\002$row\003";
							Log3 $name, 4, "$name/msg fileGetRaw: $row";
							SIGNALduino_Parse($hash, $hash, $hash->{NAME}, $row);
						}
					}
				}
				return $n . " raw Nachrichten eingelesen";
			} else {
				return "Could not open file $arg2";
			}
		}
		elsif ($arg eq '?') {
			my $ret;
			
			$ret = "dummy get raw\n\n";
			$ret .= "raw message       e.g. MS;P0=-392;P1=...\n";
			$ret .= "dispatch message  e.g. P7#6290DCF37\n";
			$ret .= "version=x.x.x     sets version. e.g. (version=3.2.0) to get old MC messages\n";
			$ret .= "regexp=           set fileRegexp for get raw messages from file. e.g. regexp=^MC\n";
			$ret .= "file=             gets raw messages from file in the fhem directory\n";
			return $ret;
		}
		else {
			Log3 $name, 4, "$name/msg get dispatch: $arg";
			Dispatch($hash, $arg, undef);
		}
		return "";
  	}
  }
  return "No $a[1] for dummies" if(IsDummy($name));

  Log3 $name, 5, "$name: command for gets: " . $gets{$a[1]}[0] . " " . $arg;

  if ($a[1] eq "raw")
  {
  	# Dirty hack to check and modify direct communication from logical modules with hardware
  	if ($arg =~ /^is.*/ && length($arg) == 34)
  	{
  		# Arctec protocol
  		Log3 $name, 5, "$name: calling set :sendmsg P17;R6#".substr($arg,2);
  		
  		SIGNALduino_Set($hash,$name,"sendMsg","P17#",substr($arg,2),"#R6");
  	    return "$a[0] $a[1] => $arg";
  	}
  	
  }
  elsif ($a[1] eq "protocolIDs")
  {
	my $id;
	my $ret;
	my $s;
	my $moduleId;
	my @IdList = ();
	
	foreach $id (keys %ProtocolListSIGNALduino)
	{
		next if ($id eq 'id');
		push (@IdList, $id);
	}
	@IdList = sort { $a <=> $b } @IdList;
	
	$ret = " ID    modulname       protocolname # comment\n\n";
	
	foreach $id (@IdList)
	{
		$ret .= sprintf("%3s",$id) . " ";
		
		if (exists ($ProtocolListSIGNALduino{$id}{format}) && $ProtocolListSIGNALduino{$id}{format} eq "manchester")
		{
			$ret .= "MC";
		}
		elsif (exists $ProtocolListSIGNALduino{$id}{sync})
		{
			$ret .= "MS";
		}
		elsif (exists ($ProtocolListSIGNALduino{$id}{clockabs}))
		{
			$ret .= "MU";
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{clientmodule}))
		{
			$moduleId .= "$id,";
			$s = $ProtocolListSIGNALduino{$id}{clientmodule};
			if (length($s) < 15)
			{
				$s .= substr("               ",length($s) - 15);
			}
			$ret .= " $s";
		}
		else
		{
			$ret .= "                ";
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{name}))
		{
			$ret .= " $ProtocolListSIGNALduino{$id}{name}";
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{comment}))
		{
			$ret .= " # $ProtocolListSIGNALduino{$id}{comment}";
		}
		
		$ret .= "\n";
	}
	#$moduleId =~ s/,$//;
	
	return "$a[1]: \n\n$ret\n";
	#return "$a[1]: \n\n$ret\nIds with modules: $moduleId";
  }
  
  #SIGNALduino_SimpleWrite($hash, $gets{$a[1]}[0] . $arg);
  SIGNALduino_AddSendQueue($hash, $gets{$a[1]}[0] . $arg);
  $hash->{getcmd}->{cmd}=$a[1];
  $hash->{getcmd}->{asyncOut}=$hash->{CL};
  $hash->{getcmd}->{timenow}=time();
  
  return undef; # We will exit here, and give an output only, if asny output is supported. If this is not supported, only the readings are updated
}

sub SIGNALduino_parseResponse($$$)
{
	my $hash = shift;
	my $cmd = shift;
	my $msg = shift;

	my $name=$hash->{NAME};
	
  	$msg =~ s/[\r\n]//g;

	if($cmd eq "cmds") 
	{       # nice it up
	    $msg =~ s/$name cmds =>//g;
   		$msg =~ s/.*Use one of//g;
 	} 
 	elsif($cmd eq "uptime") 
 	{   # decode it
   		#$msg = hex($msg);              # /125; only for col or coc
    	$msg = sprintf("%d %02d:%02d:%02d", $msg/86400, ($msg%86400)/3600, ($msg%3600)/60, $msg%60);
  	}
  	elsif($cmd eq "ccregAll")
  	{
		$msg =~ s/  /\n/g;
		$msg = "\n\n" . $msg
  	}
  	elsif($cmd eq "ccconf")
  	{
		my (undef,$str) = split('=', $msg);
		my $var;
		my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"11"=>1,"1B"=>1,"1D"=>1 );
		$msg = "";
		foreach my $a (sort keys %r) {
			$var = substr($str,(hex($a)-13)*2, 2);
			$r{$a} = hex($var);
		}
		$msg = sprintf("freq:%.3fMHz bWidth:%dKHz rAmpl:%ddB sens:%ddB  (DataRate:%.2fBaud)",
		26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
		26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
		$ampllist[$r{"1B"}&7],                                          #rAmpl
		4+4*($r{"1D"}&3),                                               #Sens
		((256+$r{"11"})*(2**($r{"10"} & 15 )))*26000000/(2**28)         #DataRate
		);
	}
	elsif($cmd eq "bWidth") {
		my $val = hex(substr($msg,6));
		my $arg = $hash->{getcmd}->{arg};
		my $ob = $val & 0x0f;
		
		my ($bits, $bw) = (0,0);
		OUTERLOOP:
		for (my $e = 0; $e < 4; $e++) {
			for (my $m = 0; $m < 4; $m++) {
				$bits = ($e<<6)+($m<<4);
				$bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
				last OUTERLOOP if($arg >= $bw);
			}
		}

		$ob = sprintf("%02x", $ob+$bits);
		$msg = "Setting MDMCFG4 (10) to $ob = $bw KHz";
		Log3 $name, 3, "$name/msg parseResponse bWidth: Setting MDMCFG4 (10) to $ob = $bw KHz";
		delete($hash->{getcmd});
		SIGNALduino_AddSendQueue($hash,"W12$ob");
		SIGNALduino_WriteInit($hash);
	}
	elsif($cmd eq "ccpatable") {
		my $CC1101Frequency = "433";
		if (defined($hash->{cc1101_frequency})) {
			$CC1101Frequency = $hash->{cc1101_frequency};
		}
		my $dBn = substr($msg,9,2);
		Log3 $name, 3, "$name/msg parseResponse patable: $dBn";
		foreach my $dB (keys %{ $patable{$CC1101Frequency} }) {
			if ($dBn eq $patable{$CC1101Frequency}{$dB}) {
				Log3 $name, 5, "$name/msg parseResponse patable: $dB";
				$msg .= " => $dB";
				last;
			}
		}
	#	$msg .=  "\n\n$CC1101Frequency MHz\n\n";
	#	foreach my $dB (keys $patable{$CC1101Frequency})
	#	{
	#		$msg .= "$patable{$CC1101Frequency}{$dB}  $dB\n";
	#	}
	}
	
  	return $msg;
}


#####################################
sub
SIGNALduino_ResetDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $hash, 3, "$name reset"; 
  DevIo_CloseDev($hash);
  my $ret = DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');

  return $ret;
}

#####################################
sub
SIGNALduino_CloseDevice($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $hash, 2, "$name closed"; 
	RemoveInternalTimer($hash);
	DevIo_CloseDev($hash);
	readingsSingleUpdate($hash, "state", "closed", 1);
	
	return undef;
}

#####################################
sub
SIGNALduino_DoInit($)
{
	my $hash = shift;
	my $name = $hash->{NAME};
	my $err;
	my $msg = undef;

	my ($ver, $try) = ("", 0);
	#Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing
  	Log3 $hash, 1, "$name/define: ".$hash->{DEF};
  
	delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});
	
	RemoveInternalTimer("HandleWriteQueue:$name");
    @{$hash->{QUEUE}} = ();
    $hash->{sendworking} = 0;
    
 # 	if (($hash->{DEF} !~ m/\@DirectIO/) and ($hash->{DEF} !~ m/none/) )
 if (($hash->{DEF} !~ m/\@directio/) and ($hash->{DEF} !~ m/none/) )
	{
		Log3 $hash, 1, "$name/init: ".$hash->{DEF};
		$hash->{initretry} = 0;
		RemoveInternalTimer($hash);
		
		#SIGNALduino_SimpleWrite($hash, "XQ"); # Disable receiver
		InternalTimer(gettimeofday() + SDUINO_INIT_WAIT_XQ, "SIGNALduino_SimpleWrite_XQ", $hash, 0);
		
		InternalTimer(gettimeofday() + SDUINO_INIT_WAIT, "SIGNALduino_StartInit", $hash, 0);
	}
	# Reset the counter
	delete($hash->{XMIT_TIME});
	delete($hash->{NR_CMD_LAST_H});
	return;
	return undef;
}

# Disable receiver
sub SIGNALduino_SimpleWrite_XQ($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 $hash, 3, "$name/init: disable receiver (XQ)";
	SIGNALduino_SimpleWrite($hash, "XQ");
	#DevIo_SimpleWrite($hash, "XQ\n",2);
}


sub SIGNALduino_StartInit($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	$hash->{version} = undef;
	
	Log3 $name,3 , "$name/init: get version, retry = " . $hash->{initretry};
	if ($hash->{initretry} >= SDUINO_INIT_MAXRETRY) {
		$hash->{DevState} = 'INACTIVE';
		# einmaliger reset, wenn danach immer noch 'init retry count reached', dann SIGNALduino_CloseDevice()
		if (!defined($hash->{initResetFlag})) {
			Log3 $name,2 , "$name/init retry count reached. Reset";
			$hash->{initResetFlag} = 1;
			SIGNALduino_ResetDevice($hash);
		} else {
			Log3 $name,2 , "$name/init retry count reached. Closed";
			SIGNALduino_CloseDevice($hash);
		}
		return;
	}
	else {
		$hash->{getcmd}->{cmd} = "version";
		SIGNALduino_SimpleWrite($hash, "V");
		#DevIo_SimpleWrite($hash, "V\n",2);
		$hash->{DevState} = 'waitInit';
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday() + SDUINO_CMD_TIMEOUT, "SIGNALduino_CheckCmdResp", $hash, 0);
	}
}


####################
sub SIGNALduino_CheckCmdResp($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $msg = undef;
	my $ver;
	
	if ($hash->{version}) {
		$ver = $hash->{version};
		if ($ver !~ m/SIGNAL(duino|ESP)/) {
			$msg = "$name: Not an SIGNALduino device, setting attribute dummy=1 got for V:  $ver";
			Log3 $hash, 1, $msg;
			readingsSingleUpdate($hash, "state", "no SIGNALduino found", 1);
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_CloseDevice($hash);
		}
		elsif($ver =~ m/^V 3\.1\./) {
			$msg = "$name: Version of your arduino is not compatible, pleas flash new firmware. (device closed) Got for V:  $ver";
			readingsSingleUpdate($hash, "state", "unsupported firmware found", 1);
			Log3 $hash, 1, $msg;
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_CloseDevice($hash);
		}
		else {
			readingsSingleUpdate($hash, "state", "opened", 1);
			Log3 $name, 2, "$name: initialized. " . SDUINO_VERSION;
			$hash->{DevState} = 'initialized';
			delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
			SIGNALduino_SimpleWrite($hash, "XE"); # Enable receiver
			#DevIo_SimpleWrite($hash, "XE\n",2);
			Log3 $hash, 3, "$name/init: enable receiver (XE)";
			delete($hash->{initretry});
			# initialize keepalive
			$hash->{keepalive}{ok}    = 0;
			$hash->{keepalive}{retry} = 0;
			InternalTimer(gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, "SIGNALduino_KeepAlive", $hash, 0);
		}
	}
	else {
		delete($hash->{getcmd});
		$hash->{initretry} ++;
		#InternalTimer(gettimeofday()+1, "SIGNALduino_StartInit", $hash, 0);
		SIGNALduino_StartInit($hash);
	}
}


#####################################
# Check if the 1% limit is reached and trigger notifies
sub
SIGNALduino_XmitLimitCheck($$)
{
  my ($hash,$fn) = @_;
 
 
  return if ($fn !~ m/^(is|SR).*/);

  my $now = time();


  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $name = $hash->{NAME};
    Log3 $name, 2, "SIGNALduino TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
## API to logical modules: Provide as Hash of IO Device, type of function ; command to call ; message to send
sub
SIGNALduino_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};

  $fn="RAW" if $fn eq "";

  Log3 $name, 5, "$name/write: adding to queue $fn $msg";

  #SIGNALduino_SimpleWrite($hash, $bstring);
  
  SIGNALduino_Set($hash,$name,$fn,$msg);
  #SIGNALduino_AddSendQueue($hash,$bstring);
 
}


sub SIGNALduino_AddSendQueue($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  push(@{$hash->{QUEUE}}, $msg);
  
  #Log3 $hash , 5, Dumper($hash->{QUEUE});
  
  Log3 $hash, 5,"AddSendQueue: " . $hash->{NAME} . ": $msg (" . @{$hash->{QUEUE}} . ")";
  InternalTimer(gettimeofday() + 0.1, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name") if (@{$hash->{QUEUE}} == 1 && $hash->{sendworking} == 0);
}


sub
SIGNALduino_SendFromQueue($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  if($msg ne "") {
	SIGNALduino_XmitLimitCheck($hash,$msg);
    #DevIo_SimpleWrite($hash, $msg . "\n", 2);
    $hash->{sendworking} = 1;
    SIGNALduino_SimpleWrite($hash,$msg);
    if ($msg =~ m/^S(R|C|M);/) {
       $hash->{getcmd}->{cmd} = 'sendraw';
       Log3 $hash, 4, "$name SendrawFromQueue: msg=$msg"; # zu testen der Queue, kann wenn es funktioniert auskommentiert werden
    } 
    elsif ($msg eq "C99") {
       $hash->{getcmd}->{cmd} = 'ccregAll';
    }
  }

  ##############
  # Write the next buffer not earlier than 0.23 seconds
  # else it will be sent too early by the SIGNALduino, resulting in a collision, or may the last command is not finished
  
  if (defined($hash->{getcmd}->{cmd}) && $hash->{getcmd}->{cmd} eq 'sendraw') {
     InternalTimer(gettimeofday() + SDUINO_WRITEQUEUE_TIMEOUT, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name");
  } else {
     InternalTimer(gettimeofday() + SDUINO_WRITEQUEUE_NEXT, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name");
  }
}

####################################
sub
SIGNALduino_HandleWriteQueue($)
{
  my($param) = @_;
  my(undef,$name) = split(':', $param);
  my $hash = $defs{$name};
  
  #my @arr = @{$hash->{QUEUE}};
  
  $hash->{sendworking} = 0;       # es wurde gesendet
  
  if (defined($hash->{getcmd}->{cmd}) && $hash->{getcmd}->{cmd} eq 'sendraw') {
    Log3 $name, 4, "$name/HandleWriteQueue: sendraw no answer (timeout)";
    delete($hash->{getcmd});
  }
	  
  if(@{$hash->{QUEUE}}) {
    my $msg= shift(@{$hash->{QUEUE}});

    if($msg eq "") {
      SIGNALduino_HandleWriteQueue("x:$name");
    } else {
      SIGNALduino_SendFromQueue($hash, $msg);
    }
  } else {
  	 Log3 $name, 4, "$name/HandleWriteQueue: nothing to send, stopping timer";
  	 RemoveInternalTimer("HandleWriteQueue:$name");
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
SIGNALduino_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  my $debug = AttrVal($name,"debug",0);

  my $SIGNALduinodata = $hash->{PARTIAL};
  Log3 $name, 5, "$name/RAW READ: $SIGNALduinodata/$buf" if ($debug); 
  $SIGNALduinodata .= $buf;

  while($SIGNALduinodata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$SIGNALduinodata) = split("\n", $SIGNALduinodata, 2);
    $rmsg =~ s/\r//;
    
    	if ($rmsg =~ m/^\002(M(s|u);.*;)\003/) {
		$rmsg =~ s/^\002//;                # \002 am Anfang entfernen
		my @msg_parts = split(";",$rmsg);
		my $m0;
		my $mnr0;
		my $m1;
		my $mL;
		my $mH;
		my $part = "";
		my $partD;
		
		foreach my $msgPart (@msg_parts) {
			$m0 = substr($msgPart,0,1);
			$mnr0 = ord($m0);
			$m1 = substr($msgPart,1);
			if ($m0 eq "M") {
				$part .= "M" . uc($m1) . ";";
			}
			elsif ($mnr0 > 127) {
				$part .= "P" . sprintf("%u", ($mnr0 & 7)) . "=";
				if (length($m1) == 2) {
					$mL = ord(substr($m1,0,1)) & 127;        # Pattern low
					$mH = ord(substr($m1,1,1)) & 127;        # Pattern high
					if (($mnr0 & 0b00100000) != 0) {           # Vorzeichen  0b00100000 = 32
						$part .= "-";
					}
					if ($mnr0 & 0b00010000) {                # Bit 7 von Pattern low
						$mL += 128;
					}
					$part .= ($mH * 256) + $mL;
				}
				$part .= ";";
			}
			elsif (($m0 eq "D" || $m0 eq "d") && length($m1) > 0) {
				my @arrayD = split(//, $m1);
				$part .= "D=";
				$partD = "";
				foreach my $D (@arrayD) {
					$mH = ord($D) >> 4;
					$mL = ord($D) & 7;
					$partD .= "$mH$mL";
				}
				#Log3 $name, 3, "$name/msg READredu1$m0: $partD";
				if ($m0 eq "d") {
					$partD =~ s/.$//;	   # letzte Ziffer entfernen wenn Anzahl der Ziffern ungerade
				}
				$partD =~ s/^8//;	           # 8 am Anfang entfernen
				#Log3 $name, 3, "$name/msg READredu2$m0: $partD";
				$part = $part . $partD . ';';
			}
			elsif (($m0 eq "C" || $m0 eq "S") && length($m1) == 1) {
				$part .= "$m0" . "P=$m1;";
			}
			elsif ($m1 =~ m/^[0-9A-Z]{1,2}$/) {        # bei 1 oder 2 Hex Ziffern nach Dez wandeln 
				$part .= "$m0=" . hex($m1) . ";";
			}
			elsif ($m0 =~m/[0-9a-zA-Z]/) {
				$part .= "$m0";
				if ($m1 ne "") {
					$part .= "=$m1";
				}
				$part .= ";";
			}
		}
		Log3 $name, 4, "$name/msg READredu: $part";
		$rmsg = "\002$part\003";
	}
	else {
		Log3 $name, 4, "$name/msg READ: $rmsg";
	}

	if ( $rmsg && !SIGNALduino_Parse($hash, $hash, $name, $rmsg) && defined($hash->{getcmd}) && defined($hash->{getcmd}->{cmd}))
	{
		my $regexp;
		if ($hash->{getcmd}->{cmd} eq 'sendraw') {
			$regexp = '^S(R|C|M);';
		}
		elsif ($hash->{getcmd}->{cmd} eq 'ccregAll') {
			$regexp = '^ccreg 00:';
		}
		elsif ($hash->{getcmd}->{cmd} eq 'bWidth') {
			$regexp = '^C.* = .*';
		}
		else {
			$regexp = $gets{$hash->{getcmd}->{cmd}}[1];
		}
		if(!defined($regexp) || $rmsg =~ m/$regexp/) {
			if (defined($hash->{keepalive})) {
				$hash->{keepalive}{ok}    = 1;
				$hash->{keepalive}{retry} = 0;
			}
			Log3 $name, 5, "$name/msg READ: regexp=$regexp cmd=$hash->{getcmd}->{cmd} msg=$rmsg";
			
			if ($hash->{getcmd}->{cmd} eq 'version') {
				my $msg_start = index($rmsg, 'V 3.');
				if ($msg_start > 0) {
					$rmsg = substr($rmsg, $msg_start);
					Log3 $name, 4, "$name/read: cut chars at begin. msgstart = $msg_start msg = $rmsg";
				}
				$hash->{version} = $rmsg;
				if (defined($hash->{DevState}) && $hash->{DevState} eq 'waitInit') {
					RemoveInternalTimer($hash);
					SIGNALduino_CheckCmdResp($hash);
				}
			}
			if ($hash->{getcmd}->{cmd} eq 'sendraw') {
				# zu testen der sendeQueue, kann wenn es funktioniert auf verbose 5
				Log3 $name, 4, "$name/read sendraw answer: $rmsg";
				delete($hash->{getcmd});
				RemoveInternalTimer("HandleWriteQueue:$name");
				SIGNALduino_HandleWriteQueue("x:$name");
			}
			else {
				$rmsg = SIGNALduino_parseResponse($hash,$hash->{getcmd}->{cmd},$rmsg);
				if (defined($hash->{getcmd}) && $hash->{getcmd}->{cmd} ne 'ccregAll') {
					readingsSingleUpdate($hash, $hash->{getcmd}->{cmd}, $rmsg, 0);
				}
				if (defined($hash->{getcmd}->{asyncOut})) {
					#Log3 $name, 4, "$name/msg READ: asyncOutput";
					my $ao = asyncOutput( $hash->{getcmd}->{asyncOut}, $hash->{getcmd}->{cmd}.": " . $rmsg );
				}
				delete($hash->{getcmd});
			}
		} else {
			Log3 $name, 4, "$name/msg READ: Received answer ($rmsg) for ". $hash->{getcmd}->{cmd}." does not match $regexp"; 
		}
	}
  }
  $hash->{PARTIAL} = $SIGNALduinodata;
}



sub SIGNALduino_KeepAlive($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	return if ($hash->{DevState} eq 'disconnected');
	
	#Log3 $name,4 , "$name/KeepAliveOk: " . $hash->{keepalive}{ok};
	if (!$hash->{keepalive}{ok}) {
		delete($hash->{getcmd});
		if ($hash->{keepalive}{retry} >= SDUINO_KEEPALIVE_MAXRETRY) {
			Log3 $name,3 , "$name/keepalive not ok, retry count reached. Reset";
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_ResetDevice($hash);
			return;
		}
		else {
			my $logLevel = 3;
			$hash->{keepalive}{retry} ++;
			if ($hash->{keepalive}{retry} == 1) {
				$logLevel = 4;
			}
			Log3 $name, $logLevel, "$name/KeepAlive not ok, retry = " . $hash->{keepalive}{retry} . " -> get ping";
			$hash->{getcmd}->{cmd} = "ping";
			SIGNALduino_AddSendQueue($hash, "P");
			#SIGNALduino_SimpleWrite($hash, "P");
		}
	}
	else {
		Log3 $name,4 , "$name/keepalive ok, retry = " . $hash->{keepalive}{retry};
	}
	$hash->{keepalive}{ok} = 0;
	
	InternalTimer(gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, "SIGNALduino_KeepAlive", $hash);
}


### Helper Subs >>>


## Parses a HTTP Response for example for flash via http download
sub SIGNALduino_ParseHttpResponse
{
	
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "")               											 		# wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";    		# Eintrag fürs Log
    }
    elsif($param->{code} eq "200" && $data ne "")                                                       		# wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    {
    	
        Log3 $name, 3, "url ".$param->{url}." returned: ".length($data)." bytes Data";  # Eintrag fürs Log
		    	
    	if ($param->{command} eq "flash")
    	{
	    	my $filename;
	    	
	    	if ($param->{httpheader} =~ /Content-Disposition: attachment;.?filename=\"?([-+.\w]+)?\"?/)
			{ 
				$filename = $1;
			} else {  # Filename via path if not specifyied via Content-Disposition
	    		($filename = $param->{path}) =~s/.*\///;
			}
			
	    	Log3 $name, 3, "$name: Downloaded $filename firmware from ".$param->{host};
	    	Log3 $name, 5, "$name: Header = ".$param->{httpheader};
	
			
		   	$filename = "FHEM/firmware/" . $filename;
			open(my $file, ">", $filename) or die $!;
			print $file $data;
			close $file;
	
			# Den Flash Befehl mit der soebene heruntergeladenen Datei ausführen
			#Log3 $name, 3, "calling set ".$param->{command}." $filename";    		# Eintrag fürs Log

			SIGNALduino_Set($hash,$name,$param->{command},$filename); # $hash->{SetFn}
			
    	}
    } else {
    	Log3 $name, 3, "undefined error while requesting ".$param->{url}." - $err - code=".$param->{code};    		# Eintrag fürs Log
    }
}

sub SIGNALduino_splitMsg
{
  my $txt = shift;
  my $delim = shift;
  my @msg_parts = split(/$delim/,$txt);
  
  return @msg_parts;
}
# $value  - $set <= $tolerance
sub SIGNALduino_inTol($$$)
{
	#Debug "sduino abs \($_[0] - $_[1]\) <= $_[2] ";
	return (abs($_[0]-$_[1])<=$_[2]);
}


 # - - - - - - - - - - - -
 #=item SIGNALduino_PatternExists()
 #This functons, needs reference to $hash, @array of values to search and %patternList where to find the matches.
# 
# Will return -1 if pattern is not found or a string, containing the indexes which are in tolerance and have the smallest gap to what we searched
# =cut


# 01232323242423       while ($message =~ /$pstr/g) { $count++ }


sub SIGNALduino_PatternExists
{
	my ($hash,$search,$patternList,$data) = @_;
	#my %patternList=$arg3;
	#Debug "plist: ".Dumper($patternList) if($debug); 
	#Debug "searchlist: ".Dumper($search) if($debug);


	
	my $searchpattern;
	my $valid=1;  
	my @pstr;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	my $i=0;
	
	my $maxcol=0;
	
	foreach $searchpattern (@{$search}) # z.B. [1, -4] 
	{
		#my $patt_id;
		# Calculate tolernace for search
		#my $tol=abs(abs($searchpattern)>=2 ?$searchpattern*0.3:$searchpattern*1.5);
		my $tol=abs(abs($searchpattern)>3 ? abs($searchpattern)>16 ? $searchpattern*0.18 : $searchpattern*0.3 : 1);  #tol is minimum 1 or higer, depending on our searched pulselengh
		

		Debug "tol: looking for ($searchpattern +- $tol)" if($debug);		
		
		my %pattern_gap ; #= {};
		# Find and store the gap of every pattern, which is in tolerance
		%pattern_gap = map { $_ => abs($patternList->{$_}-$searchpattern) } grep { abs($patternList->{$_}-$searchpattern) <= $tol} (keys %$patternList);
		if (scalar keys %pattern_gap > 0) 
		{
			Debug "index => gap in tol (+- $tol) of pulse ($searchpattern) : ".Dumper(\%pattern_gap) if($debug);
			# Extract fist pattern, which is nearst to our searched value
			my @closestidx = (sort {$pattern_gap{$a} <=> $pattern_gap{$b}} keys %pattern_gap);
			
			my $idxstr="";
			my $r=0;
			
			while (my ($item) = splice(@closestidx, 0, 1)) 
			{
				$pstr[$i][$r]=$item; 
				$r++;
				Debug "closest pattern has index: $item" if($debug);
			}
			$valid=1;
		} else {
			# search is not found, return -1
			return -1;
			last;	
		}
		$i++;
		#return ($valid ? $pstr : -1);  # return $pstr if $valid or -1

		
		#foreach $patt_id (keys %$patternList) {
			#Debug "$patt_id. chk ->intol $patternList->{$patt_id} $searchpattern $tol"; 
			#$valid =  SIGNALduino_inTol($patternList->{$patt_id}, $searchpattern, $tol);
			#if ( $valid) #one pulse found in tolerance, search next one
			#{
			#	$pstr="$pstr$patt_id";
			#	# provide this index for further lookup table -> {$patt_id =  $searchpattern}
			#	Debug "pulse found";
			#	last ; ## Exit foreach loop if searched pattern matches pattern in list
			#}
		#}
		#last if (!$valid);  ## Exit loop if a complete iteration has not found anything
	}
	my @results = ('');
	
	foreach my $subarray (@pstr)
	{
	    @results = map {my $res = $_; map $res.$_, @$subarray } @results;
	}
			
	foreach my $search (@results)
	{
		Debug "looking for substr $search" if($debug);
			
		return $search if (index( ${$data}, $search) >= 0);
	}
	
	return -1;
	
	#return ($valid ? @results : -1);  # return @pstr if $valid or -1
}

#SIGNALduino_MatchSignalPattern{$hash,@array, %hash, @array, $scalar}; not used >v3.1.3
sub SIGNALduino_MatchSignalPattern($\@\%\@$){

	my ( $hash, $signalpattern,  $patternList,  $data_array, $idx) = @_;
    my $name = $hash->{NAME};
	#print Dumper($patternList);		
	#print Dumper($idx);		
	#Debug Dumper($signalpattern) if ($debug);		
	my $tol="0.2";   # Tolerance factor
	my $found=0;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	foreach ( @{$signalpattern} )
	{
			#Debug " $idx check: ".$patternList->{$data_array->[$idx]}." == ".$_;		
			Debug "$name: idx: $idx check: abs(". $patternList->{$data_array->[$idx]}." - ".$_.") > ". ceil(abs($patternList->{$data_array->[$idx]}*$tol)) if ($debug);		
			  
			#print "\n";;
			#if ($patternList->{$data_array->[$idx]} ne $_ ) 
			### Nachkommastelle von ceil!!!
			if (!defined( $patternList->{$data_array->[$idx]})){
				Debug "$name: Error index ($idx) does not exist!!" if ($debug);

				return -1;
			}
			if (abs($patternList->{$data_array->[$idx]} - $_)  > ceil(abs($patternList->{$data_array->[$idx]}*$tol)))
			{
				return -1;		## Pattern does not match, return -1 = not matched
			}
			$found=1;
			$idx++;
	}
	if ($found)
	{
		return $idx;			## Return new Index Position
	}
	
}




sub SIGNALduino_b2h {
    my $num   = shift;
    my $WIDTH = 4;
    my $index = length($num) - $WIDTH;
    my $hex = '';
    do {
        my $width = $WIDTH;
        if ($index < 0) {
            $width += $index;
            $index = 0;
        }
        my $cut_string = substr($num, $index, $width);
        $hex = sprintf('%X', oct("0b$cut_string")) . $hex;
        $index -= $WIDTH;
    } while ($index > (-1 * $WIDTH));
    return $hex;
}

sub SIGNALduino_Split_Message($$)
{
	my $rmsg = shift;
	my $name = shift;
	my %patternList;
	my $clockidx;
	my $syncidx;
	my $rawData;
	my $clockabs;
	my $mcbitnum;
	my $rssi;
	
	my @msg_parts = SIGNALduino_splitMsg($rmsg,';');			## Split message parts by ";"
	my %ret;
	my $debug = AttrVal($name,"debug",0);
	
	foreach (@msg_parts)
	{
		#Debug "$name: checking msg part:( $_ )" if ($debug);

		if ($_ =~ m/^MS/ or $_ =~ m/^MC/ or $_ =~ m/^MU/) 		#### Synced Message start
		{
			$ret{messagetype} = $_;
		}
		elsif ($_ =~ m/^P\d=-?\d{2,}/ or $_ =~ m/^[SL][LH]=-?\d{2,}/) 		#### Extract Pattern List from array
		{
		   $_ =~ s/^P+//;  
		   $_ =~ s/^P\d//;  
		   my @pattern = split(/=/,$_);
		   
		   $patternList{$pattern[0]} = $pattern[1];
		   Debug "$name: extracted  pattern @pattern \n" if ($debug);
		}
		elsif($_ =~ m/D=\d+/ or $_ =~ m/^D=[A-F0-9]+/) 		#### Message from array

		{
			$_ =~ s/D=//;  
			$rawData = $_ ;
			Debug "$name: extracted  data $rawData\n" if ($debug);
			$ret{rawData} = $rawData;

		}
		elsif($_ =~ m/^SP=\d{1}/) 		#### Sync Pulse Index
		{
			(undef, $syncidx) = split(/=/,$_);
			Debug "$name: extracted  syncidx $syncidx\n" if ($debug);
			#return undef if (!defined($patternList{$syncidx}));
			$ret{syncidx} = $syncidx;

		}
		elsif($_ =~ m/^CP=\d{1}/) 		#### Clock Pulse Index
		{
			(undef, $clockidx) = split(/=/,$_);
			Debug "$name: extracted  clockidx $clockidx\n" if ($debug);;
			#return undef if (!defined($patternList{$clockidx}));
			$ret{clockidx} = $clockidx;
		}
		elsif($_ =~ m/^L=\d/) 		#### MC bit length
		{
			(undef, $mcbitnum) = split(/=/,$_);
			Debug "$name: extracted  number of $mcbitnum bits\n" if ($debug);;
			$ret{mcbitnum} = $mcbitnum;
		}
		
		elsif($_ =~ m/^C=\d+/) 		#### Message from array
		{
			$_ =~ s/C=//;  
			$clockabs = $_ ;
			Debug "$name: extracted absolute clock $clockabs \n" if ($debug);
			$ret{clockabs} = $clockabs;
		}
		elsif($_ =~ m/^R=\d+/)		### RSSI ###
		{
			$_ =~ s/R=//;
			$rssi = $_ ;
			Debug "$name: extracted RSSI $rssi \n" if ($debug);
			$ret{rssi} = $rssi;
		}  else {
			Debug "$name: unknown Message part $_" if ($debug);;
		}
		#print "$_\n";
	}
	$ret{pattern} = {%patternList}; 
	return %ret;
}



# Function which dispatches a message if needed.
sub SIGNALduno_Dispatch($$$$$)
{
	my ($hash, $rmsg, $dmsg, $rssi, $id) = @_;
	my $name = $hash->{NAME};
	
	if (!defined($dmsg))
	{
		Log3 $name, 5, "$name Dispatch: dmsg is undef. Skipping dispatch call";
		return;
	}
	
	#Log3 $name, 5, "$name: Dispatch DMSG: $dmsg";
	
	my $DMSGgleich = 1;
	if ($dmsg eq $hash->{LASTDMSG}) {
		Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, test gleich";
	} else {
		if (defined($hash->{DoubleMsgIDs}{$id})) {
			$DMSGgleich = 0;
			Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, test ungleich";
		}
		else {
			Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, test ungleich: disabled";
		}
		$hash->{LASTDMSG} = $dmsg;
	}

   if ($DMSGgleich) {
	#Dispatch if dispatchequals is provided in protocol definition or only if $dmsg is different from last $dmsg, or if 2 seconds are between transmits
	if ( (SIGNALduino_getProtoProp($id,'dispatchequals',0) eq 'true') || ($hash->{DMSG} ne $dmsg) || ($hash->{TIME}+2 < time() ) )   { 
		$hash->{MSGCNT}++;
		$hash->{TIME} = time();
		$hash->{DMSG} = $dmsg;
		#my $event = 0;
		if (substr(ucfirst($dmsg),0,1) eq 'U') {
			#$event = 1;
			DoTrigger($name, "DMSG " . $dmsg);
		}
		#readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, $event);
		
		$hash->{RAWMSG} = $rmsg;
		my %addvals = (DMSG => $dmsg);
		if (AttrVal($name,"suppressDeviceRawmsg",0) == 0) {
			$addvals{RAWMSG} = $rmsg
		}
		if(defined($rssi)) {
			$hash->{RSSI} = $rssi;
			$addvals{RSSI} = $rssi;
			$rssi .= " dB,"
		}
		else {
			$rssi = "";
		}
		Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, $rssi dispatch";
		Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules 
		
	}	else {
		Log3 $name, 4, "$name Dispatch: $dmsg, Dropped due to short time or equal msg";
	}
   }
}

sub
SIGNALduino_Parse_MS($$$$%)
{
	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;

	my $protocolid;
	my $syncidx=$msg_parts{syncidx};			
	my $clockidx=$msg_parts{clockidx};				
	my $rawRssi=$msg_parts{rssi};
	my $protocol=undef;
	my $rawData=$msg_parts{rawData};
	my %patternList;
	my $rssi;
	if (defined($rawRssi)) {
		$rssi = ($rawRssi>=128 ? (($rawRssi-256)/2-74) : ($rawRssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
    #$patternList{$_} = $msg_parts{rawData}{$_] for keys %msg_parts{rawData};

	#$patternList = \%msg_parts{pattern};

	#Debug "Message splitted:";
	#Debug Dumper(\@msg_parts);

	my $debug = AttrVal($iohash->{NAME},"debug",0);

	
	if (defined($clockidx) and defined($syncidx))
	{
		
		## Make a lookup table for our pattern index ids
		#Debug "List of pattern:";
		my $clockabs= $msg_parts{pattern}{$msg_parts{clockidx}};
		return undef if ($clockabs == 0); 
		$patternList{$_} = round($msg_parts{pattern}{$_}/$clockabs,1) for keys %{$msg_parts{pattern}};
	
		
 		#Debug Dumper(\%patternList);		

		#my $syncfact = $patternList{$syncidx}/$patternList{$clockidx};
		#$syncfact=$patternList{$syncidx};
		#Debug "SF=$syncfact";
		#### Convert rawData in Message
		my $signal_length = length($rawData);        # Length of data array

		## Iterate over the data_array and find zero, one, float and sync bits with the signalpattern
		## Find matching protocols
		my $id;
		my $message_dispatched=0;
		foreach $id (@{$hash->{msIdList}}) {
			
			my $valid=1;
			#$debug=1;
			Debug "Testing against Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($debug);

			# Check Clock if is it in range
			$valid=SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},$clockabs,$clockabs*0.30) if ($ProtocolListSIGNALduino{$id}{clockabs} > 0);
			Debug "validclock = $valid"  if ($debug);
			
			next if (!$valid) ;

			my $bit_length = ($signal_length-(scalar @{$ProtocolListSIGNALduino{$id}{sync}}))/((scalar @{$ProtocolListSIGNALduino{$id}{one}} + scalar @{$ProtocolListSIGNALduino{$id}{zero}})/2);

			#Check calculated min length
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_min} <= $bit_length if (exists $ProtocolListSIGNALduino{$id}{length_min}); 
			#Check calculated max length
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_max} >= $bit_length if (exists $ProtocolListSIGNALduino{$id}{length_max});

			Debug "expecting $bit_length bits in signal" if ($debug);
			next if (!$valid) ;

			#Debug Dumper(@{$ProtocolListSIGNALduino{$id}{sync}});
			Debug "Searching in patternList: ".Dumper(\%patternList) if($debug);

			Debug "searching sync: @{$ProtocolListSIGNALduino{$id}{sync}}[0] @{$ProtocolListSIGNALduino{$id}{sync}}[1]" if($debug); # z.B. [1, -18] 
			#$valid = $valid && SIGNALduino_inTol($patternList{$clockidx}, @{$ProtocolListSIGNALduino{$id}{sync}}[0], 3); #sync in tolerance
			#$valid = $valid && SIGNALduino_inTol($patternList{$syncidx}, @{$ProtocolListSIGNALduino{$id}{sync}}[1], 3); #sync in tolerance
			
			my $pstr;
			my %patternLookupHash=();

			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{sync}},\%patternList,\$rawData)) >=0;
			Debug "Found matched sync with indexes: ($pstr)" if ($debug && $valid);
			$patternLookupHash{$pstr}="" if ($valid); ## Append Sync to our lookuptable
			my $syncstr=$pstr; # Store for later start search

			Debug "sync not found " if (!$valid && $debug); # z.B. [1, -18] 

			next if (!$valid) ;

			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList,\$rawData)) >=0;
			Debug "Found matched one with indexes: ($pstr)" if ($debug && $valid);
			$patternLookupHash{$pstr}="1" if ($valid); ## Append Sync to our lookuptable
			#Debug "added $pstr " if ($debug && $valid);
			Debug "one pattern not found" if ($debug && !$valid);


			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList,\$rawData)) >=0;
			Debug "Found matched zero with indexes: ($pstr)" if ($debug && $valid);
			$patternLookupHash{$pstr}="0" if ($valid); ## Append Sync to our lookuptable
			Debug "zero pattern not found" if ($debug && !$valid);

			#Debug "added $pstr " if ($debug && $valid);

			next if (!$valid) ;
			#Debug "Pattern Lookup Table".Dumper(%patternLookupHash);
			## Check somethin else

		
			#Anything seems to be valid, we can start decoding this.			

			Log3 $name, 4, "$name: Matched MS Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($valid);
			my $signal_width= @{$ProtocolListSIGNALduino{$id}{one}};
			#Debug $signal_width;
			
			
			my @bit_msg;							# array to store decoded signal bits

			#for (my $i=index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{sync}}))+$signal_width;$i<length($rawData);$i+=$signal_width)
			#for (my $i=scalar@{$ProtocolListSIGNALduino{$id}{sync}};$i<length($rawData);$i+=$signal_width)
			my $message_start =index($rawData,$syncstr)+length($syncstr);
			Log3 $name, 5, "$name: Starting demodulation at Position $message_start";
			
			for (my $i=$message_start;$i<length($rawData);$i+=$signal_width)
			{
				my $sig_str= substr($rawData,$i,$signal_width);
				#Log3 $name, 5, "demodulating $sig_str";
				#Debug $patternLookupHash{substr($rawData,$i,$signal_width)}; ## Get $signal_width number of chars from raw data string
				if (exists $patternLookupHash{$sig_str}) { ## Add the bits to our bit array
					push(@bit_msg,$patternLookupHash{$sig_str})
				} else {
					Log3 $name, 5, "$name: Found wrong signalpattern, catched ".scalar @bit_msg." bits, aborting demodulation";
					last;
				}
			}
	
			
			Debug "$name: decoded message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);;
			
			my ($rcode,@retvalue) = SIGNALduino_callsub('postDemodulation',$ProtocolListSIGNALduino{$id}{postDemodulation},$name,@bit_msg);
			next if ($rcode < 1 );
			#Log3 $name, 5, "$name: postdemodulation value @retvalue";
			
			@bit_msg = @retvalue;
			undef(@retvalue); undef($rcode);

			my $padwith = defined($ProtocolListSIGNALduino{$id}{paddingbits}) ? $ProtocolListSIGNALduino{$id}{paddingbits} : 4;
			
			my $i=0;
			while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
			{
				push(@bit_msg,'0');
				$i++;
			}
			Debug "$name padded $i bits to bit_msg array" if ($debug);
				
			#my $logmsg = SIGNALduino_padbits(@bit_msg,$padwith);
			
			#Check converted message against lengths
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_min} <= scalar @bit_msg  if (defined($ProtocolListSIGNALduino{$id}{length_min})); 
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_max} >= scalar @bit_msg  if (defined($ProtocolListSIGNALduino{$id}{length_max}));
			next if (!$valid);  
			
			#my $dmsg = sprintf "%02x", oct "0b" . join "", @bit_msg;			## Array -> String -> bin -> hex
			my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
			my $postamble = $ProtocolListSIGNALduino{$id}{postamble};
			#if (defined($rawRssi)) {
				#if (defined($ProtocolListSIGNALduino{$id}{preamble}) && $ProtocolListSIGNALduino{$id}{preamble} eq "s") {
				#	$postamble = sprintf("%02X", $rawRssi);
				#} elsif ($id eq "7") {
				#        $postamble = "#R" . sprintf("%02X", $rawRssi);
				#}
			#}
			$dmsg = "$dmsg".$postamble if (defined($postamble));
			$dmsg = "$ProtocolListSIGNALduino{$id}{preamble}"."$dmsg" if (defined($ProtocolListSIGNALduino{$id}{preamble}));
			
			if (defined($rssi)) {
				Log3 $name, 4, "$name: Decoded MS Protocol id $id dmsg $dmsg length " . scalar @bit_msg . " RSSI = $rssi";
			} else {
				Log3 $name, 4, "$name: Decoded MS Protocol id $id dmsg $dmsg length " . scalar @bit_msg;
			}
			
			#my ($rcode,@retvalue) = SIGNALduino_callsub('preDispatchfunc',$ProtocolListSIGNALduino{$id}{preDispatchfunc},$name,$dmsg);
			#next if (!$rcode);
			#$dmsg = @retvalue;
			#undef(@retvalue); undef($rcode);
			
			my $modulematch = undef;
			if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
				$modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
			}
			if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
				Debug "$name: dispatching now msg: $dmsg" if ($debug);
				if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
					my $devid = "m$id";
					my $develop = lc(AttrVal($name,"development",""));
					if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
						Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
						next;
					}
				}
				SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
				$message_dispatched=1;
			}
		}
		
		return 0 if (!$message_dispatched);
		
		return 1;
		

	}
}



## //Todo: check list as reference
sub SIGNALduino_padbits(\@$)
{
	my $i=@{$_[0]} % $_[1];
	while (@{$_[0]} % $_[1] > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
	{
		push(@{$_[0]},'0');
	}
	return " padded $i bits to bit_msg array";
}

# - - - - - - - - - - - -
#=item SIGNALduino_getProtoProp()
#This functons, will return a value from the Protocolist and check if it is defined optional you can specify a optional default value that will be reurned
# 
# returns "" if the var is not defined
# =cut
#  $id, $propertyname,

sub SIGNALduino_getProtoProp
{
	my ($id,$propNameLst,$default) = @_;
	
	#my $id = shift;
	#my $propNameLst = shift;
	return $ProtocolListSIGNALduino{$id}{$propNameLst} if defined($ProtocolListSIGNALduino{$id}{$propNameLst});
	return $default; # Will return undef if $default is not provided
	#return undef;
}

sub SIGNALduino_Parse_MU($$$$@)
{
	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;

	my $protocolid;
	my $clockidx=$msg_parts{clockidx};
	my $rssi=$msg_parts{rssi};
	my $protocol=undef;
	my $rawData;
	my %patternListRaw;
	my $message_dispatched=0;
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
	
    Debug "$name: processing unsynced message\n" if ($debug);

	my $clockabs = 1;  #Clock will be fetched from Protocol if possible
	#$patternListRaw{$_} = floor($msg_parts{pattern}{$_}/$clockabs) for keys $msg_parts{pattern};
	$patternListRaw{$_} = $msg_parts{pattern}{$_} for keys %{$msg_parts{pattern}};

	
	if (defined($clockidx))
	{
		
		## Make a lookup table for our pattern index ids
		#Debug "List of pattern:"; 		#Debug Dumper(\%patternList);		

		## Find matching protocols
		my $id;
		foreach $id (@{$hash->{muIdList}}) {
			
			my $valid=1;
			$clockabs= $ProtocolListSIGNALduino{$id}{clockabs};
			my %patternList;
			$rawData=$msg_parts{rawData};
			if (exists($ProtocolListSIGNALduino{$id}{filterfunc}))
			{
				my $method = $ProtocolListSIGNALduino{$id}{filterfunc};
		   		if (!exists &$method)
				{
					Log3 $name, 5, "$name: Error: Unknown filtermethod=$method. Please define it in file $0";
					next;
				} else {					
					Log3 $name, 5, "$name: applying filterfunc $method";

				    no strict "refs";
					(my $count_changes,$rawData,my %patternListRaw_tmp) = $method->($name,$id,$rawData,%patternListRaw);				
				    use strict "refs";

					%patternList = map { $_ => round($patternListRaw_tmp{$_}/$clockabs,1) } keys %patternListRaw_tmp; 
				}
			} else {
				%patternList = map { $_ => round($patternListRaw{$_}/$clockabs,1) } keys %patternListRaw; 
			}
			
			my $signal_length = length($rawData);        # Length of data array
			
			my @keys = sort { $patternList{$a} <=> $patternList{$b} } keys %patternList;

			#Debug Dumper(\%patternList);	
			#Debug Dumper(@keys);	
			#$debug=1;
					
			Debug "Testing against Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($debug);
	
#			$valid=SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},$clockabs,$clockabs*0.30) if ($ProtocolListSIGNALduino{$id}{clockabs} > 0);

			next if (!$valid) ;
			
			my $bit_length = ($signal_length/((scalar @{$ProtocolListSIGNALduino{$id}{one}} + scalar @{$ProtocolListSIGNALduino{$id}{zero}})/2));
			Debug "Expect $bit_length bits in message"  if ($valid && $debug);

			#Check calculated min length
			#$valid = $valid && $ProtocolListSIGNALduino{$id}{length_min} <= $bit_length if (exists $ProtocolListSIGNALduino{$id}{length_min}); 
			#Check calculated max length
			#$valid = $valid && $ProtocolListSIGNALduino{$id}{length_max} >= $bit_length if (exists $ProtocolListSIGNALduino{$id}{length_max});

			#next if (!$valid) ;
			#Debug "expecting $bit_length bits in signal" if ($debug && $valid);

			Debug "Searching in patternList: ".Dumper(\%patternList) if($debug);
			next if (!$valid) ;

	
			my %patternLookupHash=();

			#Debug "phash:".Dumper(%patternLookupHash);
			my $pstr="";
			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList,\$rawData)) >=0;
			Debug "Found matched one" if ($debug && $valid);
			my $oneStr=$pstr if ($valid);
			$patternLookupHash{$pstr}="1" if ($valid); ## Append one to our lookuptable
			Debug "added $pstr " if ($debug && $valid);

			my $zeroStr ="";
			if (scalar @{$ProtocolListSIGNALduino{$id}{zero}} >0) {
				$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList,\$rawData)) >=0;
				Debug "Found matched zero" if ($debug && $valid);
				$zeroStr=$pstr if ($valid);
				$patternLookupHash{$pstr}="0" if ($valid); ## Append zero to our lookuptable
				Debug "added $pstr " if ($debug && $valid);
			}

			if (defined($ProtocolListSIGNALduino{$id}{float}))
			{
				$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{float}},\%patternList,\$rawData)) >=0;
				Debug "Found matched float" if ($debug && $valid);
				$patternLookupHash{$pstr}="F" if ($valid); ## Append float to our lookuptable
				Debug "added $pstr " if ($debug && $valid);
			}

			next if (!$valid) ;
			#Debug "Pattern Lookup Table".Dumper(%patternLookupHash);
			## Check somethin else

		
			#Anything seems to be valid, we can start decoding this.			

			Log3 $name, 4, "$name: Fingerprint for MU Protocol id $id -> $ProtocolListSIGNALduino{$id}{name} matches, trying to demodulate"  if ($valid);
			my $signal_width= @{$ProtocolListSIGNALduino{$id}{one}};
			#Debug $signal_width;
			
			my @bit_msg=();							# array to store decoded signal bits
			
			my $message_start=0 ;
			my @msgStartLst;
			my $startStr="";
			my $start_regex;
			#my $oneStr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList,\$rawData);
			#my $zeroStr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList,\$rawData);

			if (@msgStartLst = SIGNALduino_getProtoProp($id,"start"))
			{
				Debug "msgStartLst: ".Dumper(@msgStartLst)  if ($debug);
			
				if ( ($startStr=SIGNALduino_PatternExists($hash,@msgStartLst,\%patternList,\$rawData)) eq -1)
				{
					Log3 $name, 5, "$name: start pattern for MU Protocol id $id -> $ProtocolListSIGNALduino{$id}{name} mismatches, aborting"  ;
					$valid=0;
					next;
				};
			} 
			
			
			if (length ($zeroStr) > 0 ){  $start_regex = "$startStr\($oneStr\|$zeroStr\)";}
			else {$start_regex  = $startStr.$oneStr; }
			
			Debug "Regex is: $start_regex" if ($debug);

			$rawData =~ /$start_regex/;
			if (defined($-[0] && $-[0] > 0)) {
				$message_start=$-[0]+ length($startStr);
			} else {
				undef($message_start);				
			}
			undef @msgStartLst;
			
			#for (my $i=index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{sync}}))+$signal_width;$i<length($rawData);$i+=$signal_width)
			Debug "Message starts at $message_start - length of data is ".length($rawData) if ($debug);
			next if (!defined($message_start));
			Log3 $name, 5, "$name: Starting demodulation at Position $message_start";
			#my $onepos= index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList));
			#my $zeropos=index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList));
			#Log3 $name, 3, "op=$onepos zp=$zeropos";
			#Debug "phash:".Dumper(%patternLookupHash);
			
			my $padwith = defined($ProtocolListSIGNALduino{$id}{paddingbits}) ? $ProtocolListSIGNALduino{$id}{paddingbits} : 4;
			
			for (my $i=$message_start;$i<=length($rawData)-$signal_width;$i+=$signal_width)
			{
				
				my $sig_str= substr($rawData,$i,$signal_width);
				Debug "$name: i=$i  search=$sig_str" if ($debug);

				$valid=1; # Set valid to 1 for every loop
				#Debug $patternLookupHash{substr($rawData,$i,$signal_width)}; ## Get $signal_width number of chars from raw data string
				if (exists $patternLookupHash{$sig_str}) 
				{
					my $bit = $patternLookupHash{$sig_str};
					
					push(@bit_msg,$bit) if (looks_like_number($bit)) ; ## Add the bits to our bit array
				}
				if (!exists $patternLookupHash{$sig_str} || $i+$signal_width>length($rawData)-$signal_width)  ## Dispatch if last signal or unknown data
				{
					Debug "$name: demodulated message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);
					#Check converted message against lengths 
					$valid = $valid && $ProtocolListSIGNALduino{$id}{length_max} >= scalar @bit_msg  if (defined($ProtocolListSIGNALduino{$id}{length_max}));					
					$valid = $valid && $ProtocolListSIGNALduino{$id}{length_min} <= scalar @bit_msg  if (defined($ProtocolListSIGNALduino{$id}{length_min})); 

					
					#next if (!$valid);  ## Last chance to try next protocol if there is somethin invalid
					if ($valid) {
			
						my ($rcode,@retvalue) = SIGNALduino_callsub('postDemodulation',$ProtocolListSIGNALduino{$id}{postDemodulation},$name,@bit_msg);
						next if ($rcode < 1 );

						#Log3 $name, 5, "$name: postdemodulation value @retvalue";
			
						@bit_msg = @retvalue;
						undef(@retvalue); undef($rcode);
			
			
						while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
						{
							push(@bit_msg,'0');
							Debug "$name: padding 0 bit to bit_msg array" if ($debug);
						}
			
						Log3 $name, 5, "$name: dispatching bits: @bit_msg";
						my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
						$dmsg =~ s/^0+//	 if (defined($ProtocolListSIGNALduino{$id}{remove_zero})); 
						$dmsg = "$dmsg"."$ProtocolListSIGNALduino{$id}{postamble}" if (defined($ProtocolListSIGNALduino{$id}{postamble}));
						$dmsg = "$ProtocolListSIGNALduino{$id}{preamble}"."$dmsg" if (defined($ProtocolListSIGNALduino{$id}{preamble}));
						
						if (defined($rssi)) {
							Log3 $name, 4, "$name: decoded matched MU Protocol id $id dmsg $dmsg length " . scalar @bit_msg . " RSSI = $rssi";
						} else {
							Log3 $name, 4, "$name: decoded matched MU Protocol id $id dmsg $dmsg length " . scalar @bit_msg;
						}
						
						my $modulematch;
						if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
							$modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
						}
						if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
							Debug "$name: dispatching now msg: $dmsg" if ($debug);
							if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
								my $devid = "m$id";
								my $develop = lc(AttrVal($name,"development",""));
								if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
									Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
									next;
								}
							}
	
							SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
							$message_dispatched=1;
						}
					} else {
						if ($debug)
						{
							my $debugstr;
							$debugstr.=$ProtocolListSIGNALduino{$id}{length_min} if defined($ProtocolListSIGNALduino{$id}{length_min});
							$debugstr.="/";
							$debugstr.=$ProtocolListSIGNALduino{$id}{length_max} if defined($ProtocolListSIGNALduino{$id}{length_max});
							
							Debug "$name: length ($debugstr) does not match (@bit_msg), ".@bit_msg." bits\n";
						}	
						
					}
					@bit_msg=(); # clear bit_msg array
					
					#Find next position of valid signal (skip invalid pieces)
					my $regex=".{$i}".$start_regex;
					Debug "$name: searching new start with ($regex)\n" if ($debug);
					
					$rawData =~ /$regex/;
					if (defined($-[0]) && ($-[0] > 0)) {
						#$i=$-[0]+ $i+ length($startStr);
						$i=$-[0]+ $i;
						$i=$i-$signal_width if ($i>0 && length($startStr) == 0); #Todo:
						Debug "$name: found restart at Position $i ($regex)\n" if ($debug);
					} else {
						last;
					}
					
					#if ($startStr)
					#{
				#		$i= index($rawData,$startStr,$i);	
				#	} else {
				#		$i = (index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList),$i+$signal_width) < index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList),$i+$signal_width) ? index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList),$i+$signal_width) : index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList),$i+$signal_width));
				#		$i-=$signal_width if ($i<length($rawData)-$signal_width) ;
				#		
				#	}
				#	last if ($i <=-1);	
					Log3 $name, 5, "$name: restarting demodulation at Position $i+$signal_width" if ($debug);
				
				}
			}
					
			#my $dmsg = sprintf "%02x", oct "0b" . join "", @bit_msg;			## Array -> String -> bin -> hex
		}
		return 0 if (!$message_dispatched);
		
		return 1;
	}
}


sub
SIGNALduino_Parse_MC($$$$@)
{

	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;
	my $clock=$msg_parts{clockabs};	     ## absolute clock
	my $rawData=$msg_parts{rawData};
	my $rssi=$msg_parts{rssi};
	my $mcbitnum=$msg_parts{mcbitnum};
	my $bitData;
	my $dmsg;
	my $message_dispatched=0;
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
	
	return undef if (!$clock);
	#my $protocol=undef;
	#my %patternListRaw = %msg_parts{patternList};
	
	Debug "$name: processing manchester messag len:".length($rawData) if ($debug);
	
	my $hlen = length($rawData);
	my $blen;
	#if (defined($mcbitnum)) {
	#	$blen = $mcbitnum;
	#} else {
		$blen = $hlen * 4;
	#}
	my $id;
	
	my $rawDataInverted;
	($rawDataInverted = $rawData) =~ tr/0123456789ABCDEF/FEDCBA9876543210/;   # Some Manchester Data is inverted
	
	foreach $id (@{$hash->{mcIdList}}) {

		#next if ($blen < $ProtocolListSIGNALduino{$id}{length_min} || $blen > $ProtocolListSIGNALduino{$id}{length_max});
		#if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1]);
		if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1] and length($rawData)*4 >= $ProtocolListSIGNALduino{$id}{length_min} )
		{
			Debug "clock and min length matched"  if ($debug);

			if (defined($rssi)) {
				Log3 $name, 4, "$name: Found manchester Protocol id $id clock $clock RSSI $rssi -> $ProtocolListSIGNALduino{$id}{name}";
			} else {
				Log3 $name, 4, "$name: Found manchester Protocol id $id clock $clock -> $ProtocolListSIGNALduino{$id}{name}";
			}
			
			if (exists($ProtocolListSIGNALduino{$id}{polarity}) && ($ProtocolListSIGNALduino{$id}{polarity} eq 'invert') && (!defined($hash->{version}) || substr($hash->{version},0,6) ne 'V 3.2.'))
			# todo  && substr($hash->{version},0,6) ne 'V 3.2.')   # bei version V 3.2. nicht invertieren 
			{
		   		$bitData= unpack("B$blen", pack("H$hlen", $rawDataInverted)); 
			} else {
		   		$bitData= unpack("B$blen", pack("H$hlen", $rawData)); 
			}
			Debug "$name: extracted data $bitData (bin)\n" if ($debug); ## Convert Message from hex to bits
		   	Log3 $name, 5, "$name: extracted data $bitData (bin)";
		   	
		   	my $method = $ProtocolListSIGNALduino{$id}{method};
		    if (!exists &$method)
			{
				Log3 $name, 5, "$name: Error: Unknown function=$method. Please define it in file $0";
			} else {
				my ($rcode,$res) = $method->($name,$bitData,$id,$mcbitnum);
				if ($rcode != -1) {
					$dmsg = $res;
					$dmsg=$ProtocolListSIGNALduino{$id}{preamble}.$dmsg if (defined($ProtocolListSIGNALduino{$id}{preamble})); 
					my $modulematch;
					if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
		                $modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
					}
					if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
						if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
							my $devid = "m$id";
							my $develop = lc(AttrVal($name,"development",""));
							if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
								Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
								next;
							}
						}
						SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
						$message_dispatched=1;
					}
				} else {
					$res="undef" if (!defined($res));
					Log3 $name, 5, "$name: protocol does not match return from method: ($res)" ; 

				}
			}
		}
			
	}
	return 0 if (!$message_dispatched);
	return 1;
}


sub
SIGNALduino_Parse($$$$@)
{
  my ($hash, $iohash, $name, $rmsg, $initstr) = @_;

	#print Dumper(\%ProtocolListSIGNALduino);
	
    	
	if (!($rmsg=~ s/^\002(M.;.*;)\003/$1/)) 			# Check if a Data Message arrived and if it's complete  (start & end control char are received)
	{							# cut off start end end character from message for further processing they are not needed
		Log3 $name, AttrVal($name,"noMsgVerbose",5), "$name/noMsg Parse: $rmsg";
		return undef;
	}

	if (defined($hash->{keepalive})) {
		$hash->{keepalive}{ok}    = 1;
		$hash->{keepalive}{retry} = 0;
	}
	
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	
	
	Debug "$name: incomming message: ($rmsg)\n" if ($debug);
	
	if (AttrVal($name, "rawmsgEvent", 0)) {
		DoTrigger($name, "RAWMSG " . $rmsg);
	}
	
	my %signal_parts=SIGNALduino_Split_Message($rmsg,$name);   ## Split message and save anything in an hash %signal_parts
	#Debug "raw data ". $signal_parts{rawData};
	
	
	my $dispatched;
	# Message Synced type   -> M#

	if (@{$hash->{msIdList}} && $rmsg=~ m/^MS;(P\d=-?\d+;){3,8}D=\d+;CP=\d;SP=\d;/) 
	{
		$dispatched= SIGNALduino_Parse_MS($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	# Message unsynced type   -> MU
  	elsif (@{$hash->{muIdList}} && $rmsg=~ m/^MU;(P\d=-?\d+;){3,8}D=\d+;CP=\d;/)
	{
		$dispatched=  SIGNALduino_Parse_MU($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	# Manchester encoded Data   -> MC
  	elsif (@{$hash->{mcIdList}} && $rmsg=~ m/^MC;.*;/) 
	{
		$dispatched=  SIGNALduino_Parse_MC($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	else {
		Debug "$name: unknown Messageformat, aborting\n" if ($debug);
		return undef;
	}
	
	if ( AttrVal($hash->{NAME},"verbose","0") > 4 && !$dispatched)
	{
   	    my $notdisplist;
   	    my @lines;
   	    if (defined($hash->{unknownmessages}))
   	    {
   	    	$notdisplist=$hash->{unknownmessages};	      				
			@lines = split ('#', $notdisplist);   # or whatever
   	    }
		push(@lines,FmtDateTime(time())."-".$rmsg);
		shift(@lines)if (scalar @lines >25);
		$notdisplist = join('#',@lines);

		$hash->{unknownmessages}=$notdisplist;
		return undef;
		#Todo  compare Sync/Clock fact and length of D= if equal, then it's the same protocol!
	}


}


#####################################
sub
SIGNALduino_Ready($)
{
  my ($hash) = @_;

  if ($hash->{STATE} eq 'disconnected') {
    $hash->{DevState} = 'disconnected';
    return DevIo_OpenDev($hash, 1, "SIGNALduino_DoInit", 'SIGNALduino_Connect')
  }
  
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}


sub
SIGNALduino_WriteInit($)
{
  my ($hash) = @_;
  
  # todo: ist dies so ausreichend, damit die Aenderungen uebernommen werden?
  SIGNALduino_AddSendQueue($hash,"WS36");   # SIDLE, Exit RX / TX, turn off frequency synthesizer 
  SIGNALduino_AddSendQueue($hash,"WS34");   # SRX, Enable RX. Perform calibration first if coming from IDLE and MCSM0.FS_AUTOCAL=1.
}

########################
sub
SIGNALduino_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
  if($hash->{TYPE} eq "SIGNALduino_RFR") {
    # Prefix $msg with RRBBU and return the corresponding SIGNALduino hash.
    ($hash, $msg) = SIGNALduino_RFR_AddPrefix($hash, $msg); 
  }

  my $name = $hash->{NAME};
  Log3 $name, 5, "$name SW: $msg";

  $msg .= "\n" unless($nonl);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

sub
SIGNALduino_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	my $debug = AttrVal($name,"debug",0);
	
	$aVal= "" if (!defined($aVal));
	Log3 $name, 4, "$name: Calling Getting Attr sub with args: $cmd $aName = $aVal";
		
	if( $aName eq "Clients" ) {		## Change clientList
		$hash->{Clients} = $aVal;
		$hash->{Clients} = $clientsSIGNALduino if( !$hash->{Clients}) ;				## Set defaults
		return "Setting defaults";
	} elsif( $aName eq "MatchList" ) {	## Change matchList
		my $match_list;
		if( $cmd eq "set" ) {
			$match_list = eval $aVal;
			if( $@ ) {
				Log3 $name, 2, $name .": $aVal: ". $@;
			}
		}
		
		if( ref($match_list) eq 'HASH' ) {
		  $hash->{MatchList} = $match_list;
		} else {
		  $hash->{MatchList} = \%matchListSIGNALduino;								## Set defaults
		  Log3 $name, 2, $name .": $aVal: not a HASH using defaults" if( $aVal );
		}
	}
	elsif ($aName eq "verbose")
	{
		Log3 $name, 3, "$name: setting Verbose to: " . $aVal;
		$hash->{unknownmessages}="" if $aVal <4;
		
	}
	elsif ($aName eq "debug")
	{
		$debug = $aVal;
		Log3 $name, 3, "$name: setting debug to: " . $debug;
	}
	elsif ($aName eq "whitelist_IDs")
	{
		Log3 $name, 3, "$name Attr: whitelist_IDs";
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",$aVal);
		}
	}
	elsif ($aName eq "blacklist_IDs")
	{
		Log3 $name, 3, "$name Attr: blacklist_IDs";
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",undef,$aVal);
		}
	}
	elsif ($aName eq "development")
	{
		Log3 $name, 3, "$name Attr: development";
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",undef,undef,$aVal);
		}
	}
	elsif ($aName eq "doubleMsgCheck_IDs")
	{
		if (defined($aVal)) {
			if (length($aVal)>0) {
				if (substr($aVal,0 ,1) eq '#') {
					Log3 $name, 3, "$name Attr: doubleMsgCheck_IDs disabled: $aVal";
					delete $hash->{DoubleMsgIDs};
				}
				else {
					Log3 $name, 3, "$name Attr: doubleMsgCheck_IDs enabled: $aVal";
					my %DoubleMsgiD = map { $_ => 1 } split(",", $aVal);
					$hash->{DoubleMsgIDs} = \%DoubleMsgiD;
					#print Dumper $hash->{DoubleMsgIDs};
				}
			}
			else {
				Log3 $name, 3, "$name delete Attr: doubleMsgCheck_IDs";
				delete $hash->{DoubleMsgIDs};
			}
		}
	}
	elsif ($aName eq "cc1101_frequency")
	{
		if ($aVal eq "" || $aVal < 800) {
			Log3 $name, 3, "$name: delete cc1101_frequeny";
			delete ($hash->{cc1101_frequency}) if (defined($hash->{cc1101_frequency}));
		} else {
			Log3 $name, 3, "$name: setting cc1101_frequency to 868";
			$hash->{cc1101_frequency} = 868;
		}
	}
	
  	return undef;
}


sub SIGNALduino_IdList($@)
{
	my ($param, $aVal, $blacklist, $develop) = @_;
	my (undef,$name) = split(':', $param);
	my $hash = $defs{$name};

	my @msIdList = ();
	my @muIdList = ();
	my @mcIdList = ();

	if (!defined($aVal)) {
		$aVal = AttrVal($name,"whitelist_IDs","");
	}
	Log3 $name, 3, "$name sduinoIdList: whitelistIds=$aVal";
	
	if (!defined($blacklist)) {
		$blacklist = AttrVal($name,"blacklist_IDs","");
	}
	Log3 $name, 3, "$name sduinoIdList: blacklistIds=$blacklist";
	
	if (!defined($develop)) {
		$develop = AttrVal($name,"development","");
	}
	$develop = lc($develop);
	Log3 $name, 3, "$name sduinoIdList: development=$develop";

	my %WhitelistIDs;
	my %BlacklistIDs;
	my $wflag = 0;		# whitelist flag, 0=disabled
	my $bflag = 0;		# blacklist flag, 0=disabled
	if (defined($aVal) && length($aVal)>0)
	{
		if (substr($aVal,0 ,1) eq '#') {
			Log3 $name, 3, "$name Attr whitelist disabled: $aVal";
		}
		else {
			%WhitelistIDs = map { $_ => 1 } split(",", $aVal);
			#my $w = join ', ' => map "$_" => keys %WhitelistIDs;
			#Log3 $name, 3, "Attr whitelist $w";
			$wflag = 1;
		}
	}
	if ($wflag == 0) {		# whitelist disabled
		if (defined($blacklist) && length($blacklist)>0) {
			%BlacklistIDs = map { $_ => 1 } split(",", $blacklist);
			my $w = join ', ' => map "$_" => keys %BlacklistIDs;
			Log3 $name, 3, "$name Attr blacklist $w";
			$bflag = 1;
		}
	}
	
	my $id;
	foreach $id (keys %ProtocolListSIGNALduino)
	{
		next if ($id eq 'id');
		if ($wflag == 1 && !defined($WhitelistIDs{$id}))
		{
			#Log3 $name, 3, "skip ID $id";
			next;
		}
		if ($bflag == 1 && defined($BlacklistIDs{$id}))
		{
			Log3 $name, 3, "$name skip Blacklist ID $id";
			next;
		}
		
		if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "p") {
			my $devid = "p$id";
			if ($develop !~ m/$devid/) {		# skip wenn die Id nicht im Attribut development steht
				Log3 $name, 3, "$name: ID=$devid skiped (developId=p)";
				next;
			}
		}
		
		if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "y") {
			if ($develop !~ m/y/) {			# skip wenn y nicht im Attribut development steht
				Log3 $name, 3, "$name: ID=$id skiped (developId=y)";
				next;
			}
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{format}) && $ProtocolListSIGNALduino{$id}{format} eq "manchester")
		{
			push (@mcIdList, $id);
		} 
		elsif (exists $ProtocolListSIGNALduino{$id}{sync})
		{
			push (@msIdList, $id);
		}
		elsif (exists ($ProtocolListSIGNALduino{$id}{clockabs}))
		{
			push (@muIdList, $id);
		}
	}

	@msIdList = sort @msIdList;
	@muIdList = sort @muIdList;
	@mcIdList = sort @mcIdList;

	Log3 $name, 3, "$name: IDlist MS @msIdList";
	Log3 $name, 3, "$name: IDlist MU @muIdList";
    Log3 $name, 3, "$name: IDlist MC @mcIdList";
	
	$hash->{msIdList} = \@msIdList;
    $hash->{muIdList} = \@muIdList;
    $hash->{mcIdList} = \@mcIdList;
}


sub SIGNALduino_callsub
{
	my $funcname =shift;
	my $method = shift;
	my $name = shift;
	my @args = @_;
	
	
	if ( defined $method && defined &$method )   
	{
		#my $subname = @{[eval {&$method}, $@ =~ /.*/]};
		Log3 $name, 5, "$name: applying $funcname"; # method $subname";
		#Log3 $name, 5, "$name: value bevore $funcname: @args";
		
		my ($rcode, @returnvalues) = $method->($name, @args) ;	
			
	    Log3 $name, 5, "$name: modified value after $funcname: @returnvalues";
	    return ($rcode, @returnvalues);
	} elsif (defined $method ) {					
		Log3 $name, 5, "$name: Error: Unknown method $funcname Please check definition";
		return (0,undef);
	}	
	return (1,@args);			
}


# calculates the hex (in bits) and adds it at the beginning of the message
# input = @list
# output = @list
sub SIGNALduino_lengtnPrefix
{
	my ($name, @bit_msg) = @_;
	
	my $msg = join("",@bit_msg);	

	#$msg = unpack("B8", pack("N", length($msg))).$msg;
	$msg=sprintf('%08b', length($msg)).$msg;
	
	return (1,split("",$msg));
}


sub SIGNALduino_bit2Arctec
{
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);	
	# Convert 0 -> 01   1 -> 10 to be compatible with IT Module
	$msg =~ s/0/z/g;
	$msg =~ s/1/10/g;
	$msg =~ s/z/01/g;
	return (1,split("",$msg)); 
}


sub SIGNALduino_ITV1_tristateToBit($)
{
	my ($msg) = @_;
	# Convert 0 -> 00   1 -> 11 F => 01 to be compatible with IT Module
	$msg =~ s/0/00/g;
	$msg =~ s/1/11/g;
	$msg =~ s/F/01/g;
	$msg =~ s/D/10/g;
		
	return (1,$msg);
}

sub SIGNALduino_HE($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	
	#Log3 $name, 4, "$name HE: $msg";
	Log3 $name, 4, "$name HE: " . substr($msg,0,11) ." ". substr($msg,11,32) ." ". substr($msg,43,4) ." ". substr($msg,47,2) ." ". substr($msg,49,2) ." ". substr($msg,51);
	
	return (1,split("",$msg));
}

sub SIGNALduino_postDemo_Hoermann($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	
	if (substr($msg,0,9) ne "000000001") {		# check ident
		Log3 $name, 4, "$name: Hoermann ERROR - Ident not 000000001";
		return 0, undef;
	} else {
		Log3 $name, 5, "$name: Hoermann $msg";
		$msg = substr($msg,9);
		return (1,split("",$msg));
	}
}

sub SIGNALduino_postDemo_FS20($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 0;
	my $b = 0;
	my $i = 0;
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		Log3 $name, 3, "$name: FS20 - ERROR message all bit are zeros";
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
         
   if ($protolength == 45) {                       		      ### FS20 length 45 or 54
      for(my $b = 0; $b < 36; $b += 9) {	                             # build sum over first 4 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[36 .. 43]));          # Checksum Byte 5
      if (((($sum + 6) & 0xFF) - $checksum) == 0) {				## FHT80TF Tuer-/Fensterkontakt
			for(my $b = 0; $b < 45; $b += 9) {	                              # check parity over 5 byte
				my $parity = 0;					                                 # Parity even
				for(my $i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
					$parity += $bit_msg[$i];
				}
				if ($parity % 2 != 0) {
					Log3 $name, 3, "$name: FS20 ERROR - Parity not even";
					return 0, undef;
				}
			}																						# parity ok
			for(my $b = 44; $b > 0; $b -= 9) {	                               # delete 5 parity bits
				splice(@bit_msg, $b, 1);
			}
			splice(@bit_msg, 32, 8);                                         	# delete checksum
         splice(@bit_msg, 24, 0, (0,0,0,0,0,0,0,0));                    # insert Byte 3
         Log3 $name, 4, "$name: FS20 - remote control protolength $protolength";
			return (1, @bit_msg);											## FHT80TF ok
      } 
   } 

   if ($protolength == 54) {                       		### FS20 length 45 or 54
      for($b = 0; $b < 45; $b += 9) {	                             # build sum over first 5 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[45 .. 52]));          # Checksum Byte 6
      if (((($sum + 6) & 0xFF) - $checksum) == 0) {				## FHT80 Raumthermostat
         for($b = 0; $b < 55; $b += 9) {	                              # check parity over 6 byte
            my $parity = 0;					                              # Parity even
            for($i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
               $parity += $bit_msg[$i];
            }
            if ($parity % 2 != 0) {
               Log3 $name, 3, "$name: FHT80 ERROR - Parity not even";
               return 0, undef;
            }
         }																					# parity ok
         for($b = 53; $b > 0; $b -= 9) {	                              # delete 6 parity bits
            splice(@bit_msg, $b, 1);
         }
         splice(@bit_msg, 40, 8);                                       # delete checksum
         Log3 $name, 4, "$name: FS20 - remote control protolength $protolength";
         return (1, @bit_msg);											## FHT80 ok
      }
   }
   return 0, undef;
}

sub SIGNALduino_postDemo_FHT80($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 0;
	my $b = 0;
	my $i = 0;
   # if ($protolength < 66) {                                        	# min 6 bytes + 6 bits
		# Log3 $name, 3, "$name: FHT80 - ERROR lenght of message < 66";
		# return 0, undef;
   # }
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		Log3 $name, 3, "$name: FHT80 - ERROR message all bit are zeros";
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   if ($protolength == 54) {                       		### FHT80 fixed length
      for($b = 0; $b < 45; $b += 9) {	                             # build sum over first 5 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[45 .. 52]));          # Checksum Byte 6
      if (((($sum + 12) & 0xFF) - $checksum) == 0) {				## FHT80 Raumthermostat
         for($b = 0; $b < 55; $b += 9) {	                              # check parity over 6 byte
            my $parity = 0;					                              # Parity even
            for($i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
               $parity += $bit_msg[$i];
            }
            if ($parity % 2 != 0) {
               Log3 $name, 3, "$name: FHT80 ERROR - Parity not even";
               return 0, undef;
            }
         }																					# parity ok
         for($b = 53; $b > 0; $b -= 9) {	                              # delete 6 parity bits
            splice(@bit_msg, $b, 1);
         }
         if ($bit_msg[26] != 1) {                                       # Bit 5 Byte 3 must 1
            Log3 $name, 3, "$name: FHT80 ERROR - byte 3 bit 5 not 1";
            return 0, undef;
         }
         splice(@bit_msg, 40, 8);                                       # delete checksum
         splice(@bit_msg, 24, 0, (0,0,0,0,0,0,0,0));                    # insert Byte 3
         Log3 $name, 4, "$name: FHT80 - roomthermostat protolength $protolength";
         return (1, @bit_msg);											## FHT80 ok
      }
   }
   return 0, undef;
}

sub SIGNALduino_postDemo_FHT80TF($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 0;			
	my $b = 0;
   if ($protolength < 46) {                                        	# min 5 bytes + 6 bits
		Log3 $name, 4, "$name: FHT80TF or FS20 - ERROR lenght of message < 46";
		return 0, undef;
   }
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		Log3 $name, 3, "$name: FHTTF or FS20 - ERROR message all bit are zeros";
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   if ($protolength == 45) {                       		      ### FHT80TF fixed length
      for(my $b = 0; $b < 36; $b += 9) {	                             # build sum over first 4 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[36 .. 43]));          # Checksum Byte 5
      if (((($sum + 12) & 0xFF) - $checksum) == 0) {				## FHT80TF Tuer-/Fensterkontakt
			for(my $b = 0; $b < 45; $b += 9) {	                              # check parity over 5 byte
				my $parity = 0;					                                 # Parity even
				for(my $i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
					$parity += $bit_msg[$i];
				}
				if ($parity % 2 != 0) {
					Log3 $name, 4, "$name: FHT80TF ERROR - Parity not even";
					return 0, undef;
				}
			}																						# parity ok
			for(my $b = 44; $b > 0; $b -= 9) {	                               # delete 5 parity bits
				splice(@bit_msg, $b, 1);
			}
         if ($bit_msg[26] != 0) {                                       # Bit 5 Byte 3 must 0
            Log3 $name, 3, "$name: FHT80 ERROR - byte 3 bit 5 not 0";
            return 0, undef;
         }
			splice(@bit_msg, 32, 8);                                         	# delete checksum
      Log3 $name, 4, "$name: FHT80TF - door/window switch protolength $protolength";
			return (1, @bit_msg);											## FHT80TF ok
      } 
   } 
   return 0, undef;
}

sub SIGNALduino_postDemo_WS7035($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $parity = 0;					# Parity even

	Log3 $name, 4, "$name: WS7035 $msg";
	if (substr($msg,0,8) ne "10100000") {		# check ident
		Log3 $name, 3, "$name: WS7035 ERROR - Ident not 1010 0000";
		return 0, undef;
	} else {
		for(my $i = 15; $i < 28; $i++) {			# Parity over bit 15 and 12 bit temperature
	      $parity += substr($msg, $i, 1);
		}
		if ($parity % 2 != 0) {
			Log3 $name, 3, "$name: WS7035 ERROR - Parity not even";
			return 0, undef;
		} else {
			Log3 $name, 4, "$name: WS7035 " . substr($msg,0,4) ." ". substr($msg,4,4) ." ". substr($msg,8,4) ." ". substr($msg,12,4) ." ". substr($msg,16,4) ." ". substr($msg,20,4) ." ". substr($msg,24,4) ." ". substr($msg,28,4) ." ". substr($msg,32,4) ." ". substr($msg,36,4) ." ". substr($msg,40);
			substr($msg, 27, 4, '');			# delete nibble 8
			return (1,split("",$msg));
		}
	}
}

sub SIGNALduino_postDemo_WS2000($@) {
	my ($name, @bit_msg) = @_;
	my $debug = AttrVal($name,"debug",0);
	my @new_bit_msg = "";
	my $protolength = scalar @bit_msg;
	my @datalenghtws = (35,50,35,50,70,40,40,85);
	my $datastart = 0;
	my $datalength = 0;
	my $datalength1 = 0;
	my $index = 0;
	my $data = 0;
	my $dataindex = 0;
	my $error = 0;
	my $check = 0;
	my $sum = 5;
	my $typ = 0;
	my $adr = 0;
	my @sensors = (
		"Thermo",
		"Thermo/Hygro",
		"Rain",
		"Wind",
		"Thermo/Hygro/Baro",
		"Brightness",
		"Pyrano",
		"Kombi"
		);

	for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
		last if $bit_msg[$datastart] eq "1";
	}
	if ($datastart == $protolength) {                                 # all bits are 0
		Log3 $name, 3, "$name: WS2000 - ERROR message all bit are zeros";
		return 0, undef;
	}
	$datalength = $protolength - $datastart;
	$datalength1 = $datalength - ($datalength % 5);  		# modulo 5
	Log3 $name, 5, "$name: WS2000 protolength: $protolength, datastart: $datastart, datalength $datalength";
	$typ = oct( "0b".(join "", reverse @bit_msg[$datastart + 1.. $datastart + 4]));		# Sensortyp
	if ($typ > 7) {
		Log3 $name, 4, "$name: WS2000 Sensortyp $typ - ERROR typ to big";
		return 0, undef;
	}
	if ($typ == 1 && ($datalength == 45 || $datalength == 46)) {$datalength1 += 5;}		# Typ 1 ohne Summe
	if ($datalenghtws[$typ] != $datalength1) {												# check lenght of message
		Log3 $name, 4, "$name: WS2000 Sensortyp $typ - ERROR lenght of message $datalength1 ($datalenghtws[$typ])";
		return 0, undef;
	} elsif ($datastart > 10) {									# max 10 Bit preamble
		Log3 $name, 4, "$name: WS2000 ERROR preamble > 10 ($datastart)";
		return 0, undef;
	} else {
		do {
			$error += !$bit_msg[$index + $datastart];			# jedes 5. Bit muss 1 sein
			$dataindex = $index + $datastart + 1;				 
			$data = oct( "0b".(join "", reverse @bit_msg[$dataindex .. $dataindex + 3]));
			if ($index == 5) {$adr = ($data & 0x07)}			# Sensoradresse
			if ($datalength == 45 || $datalength == 46) { 	# Typ 1 ohne Summe
				if ($index <= $datalength - 5) {
					$check = $check ^ $data;		# Check - Typ XOR Adresse XOR  bis XOR Check muss 0 ergeben
				}
			} else {
				if ($index <= $datalength - 10) {
					$check = $check ^ $data;		# Check - Typ XOR Adresse XOR  bis XOR Check muss 0 ergeben
					$sum += $data;
				}
			}
			$index += 5;
		} until ($index >= $datalength);
	}
	if ($error != 0) {
		Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR examination bit";
		return (0, undef);
	} elsif ($check != 0) {
		Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR check XOR";
		return (0, undef);
	} else {
		if ($datalength < 45 || $datalength > 46) { 			# Summe prüfen, außer Typ 1 ohne Summe
			$data = oct( "0b".(join "", reverse @bit_msg[$dataindex .. $dataindex + 3]));
			if ($data != ($sum & 0x0F)) {
				Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR sum";
				return (0, undef);
			}
		}
		Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - $sensors[$typ]";
		$datastart += 1;																							# [x] - 14_CUL_WS
		@new_bit_msg[4 .. 7] = reverse @bit_msg[$datastart .. $datastart+3];						# [2]  Sensortyp
		@new_bit_msg[0 .. 3] = reverse @bit_msg[$datastart+5 .. $datastart+8];					# [1]  Sensoradresse
		@new_bit_msg[12 .. 15] = reverse @bit_msg[$datastart+10 .. $datastart+13];				# [4]  T 0.1, R LSN, Wi 0.1, B   1, Py   1
		@new_bit_msg[8 .. 11] = reverse @bit_msg[$datastart+15 .. $datastart+18];				# [3]  T   1, R MID, Wi   1, B  10, Py  10
		if ($typ == 0 || $typ == 2) {		# Thermo (AS3), Rain (S2000R, WS7000-16)
			@new_bit_msg[16 .. 19] = reverse @bit_msg[$datastart+20 .. $datastart+23];			# [5]  T  10, R MSN
		} else {
			@new_bit_msg[20 .. 23] = reverse @bit_msg[$datastart+20 .. $datastart+23];			# [6]  T  10, 			Wi  10, B 100, Py 100
			@new_bit_msg[16 .. 19] = reverse @bit_msg[$datastart+25 .. $datastart+28];			# [5]  H 0.1, 			Wr   1, B Fak, Py Fak
			if ($typ == 1 || $typ == 3 || $typ == 4 || $typ == 7) {	# Thermo/Hygro, Wind, Thermo/Hygro/Baro, Kombi
				@new_bit_msg[28 .. 31] = reverse @bit_msg[$datastart+30 .. $datastart+33];		# [8]  H   1,			Wr  10
				@new_bit_msg[24 .. 27] = reverse @bit_msg[$datastart+35 .. $datastart+38];		# [7]  H  10,			Wr 100
				if ($typ == 4) {	# Thermo/Hygro/Baro (S2001I, S2001ID)
					@new_bit_msg[36 .. 39] = reverse @bit_msg[$datastart+40 .. $datastart+43];	# [10] P    1
					@new_bit_msg[32 .. 35] = reverse @bit_msg[$datastart+45 .. $datastart+48];	# [9]  P   10
					@new_bit_msg[44 .. 47] = reverse @bit_msg[$datastart+50 .. $datastart+53];	# [12] P  100
					@new_bit_msg[40 .. 43] = reverse @bit_msg[$datastart+55 .. $datastart+58];	# [11] P Null
				}
			}
		}
		return (1, @new_bit_msg);
	}

}


sub SIGNALduino_postDemo_WS7053($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $new_msg ="";
	my $parity = 0;									# Parity even
   if (length($msg) > 32) {                  # start not correct
      $msg = substr($msg,1)
   }
	Log3 $name, 4, "$name: WS7053 MSG = $msg";
	if (substr($msg,0,8) ne "10100000") {		# check ident
		Log3 $name, 3, "$name: WS7053 ERROR - Ident not 1010 0000 - " . substr($msg,0,8);
		return 0, undef;
	} else {
		for(my $i = 15; $i < 28; $i++) {			# Parity over bit 15 and 12 bit temperature
	      $parity += substr($msg, $i, 1);
		}
		if ($parity % 2 != 0) {
			Log3 $name, 3, "$name: WS7053 ERROR - Parity not even";
			return 0, undef;
		} else {
			Log3 $name, 5, "$name: WS7053 before: " . substr($msg,0,4) ." ". substr($msg,4,4) ." ". substr($msg,8,4) ." ". substr($msg,12,4) ." ". substr($msg,16,4) ." ". substr($msg,20,4) ." ". substr($msg,24,4) ." ". substr($msg,28,4);
         # Format from 7053:  Bit 0-7 Ident, Bit 8-15 Rolling Code/Parity, Bit 16-27 Temperature (12.3), Bit 28-31 Zero
			$new_msg = substr($msg,0,28) . substr($msg,16,8) . substr($msg,28,4);
         # Format for CUL_TX: Bit 0-7 Ident, Bit 8-15 Rolling Code/Parity, Bit 16-27 Temperature (12.3), Bit 28 - 35 Temperature (12), Bit 36-39 Zero
			Log3 $name, 5, "$name: WS7053 after:  " . substr($new_msg,0,4) ." ". substr($new_msg,4,4) ." ". substr($new_msg,8,4) ." ". substr($new_msg,12,4) ." ". substr($new_msg,16,4) ." ". substr($new_msg,20,4) ." ". substr($new_msg,24,4) ." ". substr($new_msg,28,4) ." ". substr($new_msg,32,4) ." ". substr($new_msg,36,4);
			return (1,split("",$new_msg));
		}
	}
}


# manchester method

sub SIGNALduino_MCTFA
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	my $preamble_pos;
	my $message_end;
	my $message_length;
		
	#if ($bitData =~ m/^.?(1){16,24}0101/)  {  
	if ($bitData =~ m/(1{10}101)/ )
	{ 
		$preamble_pos=$+[1];
		Log3 $name, 4, "$name: TFA 30.3208.0 preamble_pos = $preamble_pos";
		return return (-1," sync not found") if ($preamble_pos <=0);
		my @messages;
		
		do 
		{
			$message_end = index($bitData,"1111111111101",$preamble_pos); 
			if ($message_end < $preamble_pos)
			{
				$message_end=length($bitData);
			} 
			$message_length = ($message_end - $preamble_pos);			
			
			my $part_str=substr($bitData,$preamble_pos,$message_length);
			$part_str = substr($part_str,0,52) if (length($part_str)) > 52;

			Log3 $name, 4, "$name: TFA message start=$preamble_pos end=$message_end with length".$message_length;
			Log3 $name, 5, "$name: part $part_str";
			my $hex=SIGNALduino_b2h($part_str);
			push (@messages,$hex);
			Log3 $name, 4, "$name: ".$hex;
			$preamble_pos=index($bitData,"1101",$message_end)+4;
		}  while ( $message_end < length($bitData) );
		
		my %seen;
		my @dupmessages = map { 1==$seen{$_}++ ? $_ : () } @messages;
	
		if (scalar(@dupmessages) > 0 ) {
			Log3 $name, 4, "$name: repeated hex ".$dupmessages[0]." found ".$seen{$dupmessages[0]}." times";
			return  (1,$dupmessages[0]);
		} else {  
			return (-1," no duplicate found");
		}
	}
	return (-1,undef);
	
}


sub SIGNALduino_OSV2()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	my $preamble_pos;
	my $message_end;
	my $message_length;
	
	#$bitData =~ tr/10/01/;
	if ($bitData =~ m/^.?(01){12,17}.?10011001/) 
	{  # Valid OSV2 detected!	
		#$preamble_pos=index($bitData,"10011001",24);
		$preamble_pos=$+[1];
		
		Log3 $name, 4, "$name: OSV2 protocol detected: preamble_pos = $preamble_pos";
		return return (-1," sync not found") if ($preamble_pos <=24);
		
		$message_end=$-[1] if ($bitData =~ m/^.{44,}(01){16,17}.?10011001/); #Todo regex .{44,} 44 should be calculated from $preamble_pos+ min message lengh (44)
		if (!defined($message_end) || $message_end < $preamble_pos) {
			$message_end = length($bitData);
		} else {
			$message_end += 16;
			Log3 $name, 4, "$name: OSV2 message end pattern found at pos $message_end  lengthBitData=".length($bitData);
		}
		$message_length = ($message_end - $preamble_pos)/2;

		return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );
		
		my $idx=0;
		my $osv2bits="";
		my $osv2hex ="";
		
		for ($idx=$preamble_pos;$idx<$message_end;$idx=$idx+16)
		{
			if ($message_end-$idx < 8 )
			{
			  last;
			}
			my $osv2byte = "";
			$osv2byte=NULL;
			$osv2byte=substr($bitData,$idx,16);

			my $rvosv2byte="";
			
			for (my $p=0;$p<length($osv2byte);$p=$p+2)
			{
				$rvosv2byte = substr($osv2byte,$p,1).$rvosv2byte;
			}
			$rvosv2byte =~ tr/10/01/;
			
			if (length($rvosv2byte) eq 8) {
				$osv2hex=$osv2hex.sprintf('%02X', oct("0b$rvosv2byte"))  ;
			} else {
				$osv2hex=$osv2hex.sprintf('%X', oct("0b$rvosv2byte"))  ;
			}
			$osv2bits = $osv2bits.$rvosv2byte;
		}
		$osv2hex = sprintf("%02X", length($osv2hex)*4).$osv2hex;
		Log3 $name, 4, "$name: OSV2 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits";
		#$found=1;
		#$dmsg=$osv2hex;
		return (1,$osv2hex);
	}
	elsif ($bitData =~ m/^.?(1){16,24}0101/)  {  # Valid OSV3 detected!	
		$preamble_pos = index($bitData, '0101', 16);
		$message_end = length($bitData);
		$message_length = $message_end - ($preamble_pos+4);
		Log3 $name, 4, "$name: OSV3 protocol detected: preamble_pos = $preamble_pos, message_length = $message_length";
		
		my $idx=0;
		#my $osv3bits="";
		my $osv3hex ="";
		
		for ($idx=$preamble_pos+4;$idx<length($bitData);$idx=$idx+4)
		{
			if (length($bitData)-$idx  < 4 )
			{
			  last;
			}
			my $osv3nibble = "";
			$osv3nibble=NULL;
			$osv3nibble=substr($bitData,$idx,4);

			my $rvosv3nibble="";
			
			for (my $p=0;$p<length($osv3nibble);$p++)
			{
				$rvosv3nibble = substr($osv3nibble,$p,1).$rvosv3nibble;
			}
			$osv3hex=$osv3hex.sprintf('%X', oct("0b$rvosv3nibble"));
			#$osv3bits = $osv3bits.$rvosv3nibble;
		}
		Log3 $name, 4, "$name: OSV3 protocol =                     $osv3hex";
		my $korr = 10;
		# Check if nibble 1 is A
		if (substr($osv3hex,1,1) ne 'A')
		{
			my $n1=substr($osv3hex,1,1);
			$korr = hex(substr($osv3hex,3,1));
			substr($osv3hex,1,1,'A');  # nibble 1 = A
			substr($osv3hex,3,1,$n1); # nibble 3 = nibble1
		}
		# Korrektur nibble
		my $insKorr = sprintf('%X', $korr);
		# Check for ending 00
		if (substr($osv3hex,-2,2) eq '00')
		{
			#substr($osv3hex,1,-2);  # remove 00 at end
			$osv3hex = substr($osv3hex, 0, length($osv3hex)-2);
		}
		my $osv3len = length($osv3hex);
		$osv3hex .= '0';
		my $turn0 = substr($osv3hex,5, $osv3len-4);
		my $turn = '';
		for ($idx=0; $idx<$osv3len-5; $idx=$idx+2) {
			$turn = $turn . substr($turn0,$idx+1,1) . substr($turn0,$idx,1);
		}
		$osv3hex = substr($osv3hex,0,5) . $insKorr . $turn;
		$osv3hex = substr($osv3hex,0,$osv3len+1);
		$osv3hex = sprintf("%02X", length($osv3hex)*4).$osv3hex;
		Log3 $name, 4, "$name: OSV3 protocol converted to hex: ($osv3hex) with length (".((length($osv3hex)-2)*4).") bits";
		#$found=1;
		#$dmsg=$osv2hex;
		return (1,$osv3hex);
		
	}
	return (-1,undef);
}

sub SIGNALduino_OSV1()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $mcbitnum < $ProtocolListSIGNALduino{$id}{length_min} );
	return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $mcbitnum > $ProtocolListSIGNALduino{$id}{length_max} );
	
	
	my $calcsum = oct( "0b" . reverse substr($bitData,0,8));
	$calcsum += oct( "0b" . reverse substr($bitData,8,8));
	$calcsum += oct( "0b" . reverse substr($bitData,16,8));
	$calcsum = ($calcsum & 0xFF) + ($calcsum >> 8);
	my $checksum = oct( "0b" . reverse substr($bitData,24,8));
	if ($calcsum != $checksum) {	# Checksum
		return (-1,"OSV1 - ERROR checksum not equal: $calcsum != $checksum");
	} else {
		Log3 $name, 4, "$name: OSV1 input data: $bitData";
		my $newBitData = "00001010";                       # Byte 0:   Id1 = 0x0A
        $newBitData .= "01001101";                         # Byte 1:   Id2 = 0x4D
		# Todo: Sensortyp automtisch erkennen und Premable damit setzen.
		
		# preamble	=> '50B208',	# THR128 ohne Checksumme
		# 50 - Length
		# B2 - Byte 0: Id1
		# 08 - Byte 1: Id2
		my $channel = substr($bitData,6,2); # Byte 2 h: Channel
		if ($channel == "00") { # in 0 LSB first
		$newBitData .= "0001"; # out 1 MSB first
	} elsif ($channel == "10") { # in 4 LSB first
		$newBitData .= "0010"; # out 2 MSB first
	} else { # in 8 LSB first
		$newBitData .= "0100"; # out 4 MSB first
	}
	$newBitData .= "0000"; # Byte 2 l: ????
	$newBitData .= "0000"; # Byte 3 h: address
	$newBitData .= reverse substr($bitData,0,4); # Byte 3 l: address (Rolling Code)
	$newBitData .= reverse substr($bitData,8,4); # Byte 4 h: T 0,1
	$newBitData .= "0" . substr($bitData,23,1) . "00"; # Byte 4 l: Bit 2 - Batterie 0=ok, 1=low (< 2,5 Volt)
	$newBitData .= reverse substr($bitData,16,4); # Byte 5 h: T 10
	$newBitData .= reverse substr($bitData,12,4); # Byte 5 l: T 1
	$newBitData .= "0000"; # Byte 6 h: immer 0000
	$newBitData .= substr($bitData,21,1) . "000"; # Byte 6 l: Bit 3 - Temperatur 0=pos | 1=neg, Rest 0
	$newBitData .= "00000000"; # Byte 7: immer 0000 0000
	# calculate new checksum over first 16 nibbles
    $checksum = 0;       
    for (my $i = 0; $i < 64; $i = $i + 4) {
    	$checksum += oct( "0b" . substr($newBitData, $i, 4));
    }
    $checksum = ($checksum - 0xa) & 0xff;
	$newBitData .= sprintf("%08b",$checksum);          # Byte 8:   new Checksum 
    $newBitData .= "00000000";                         # Byte 9:   immer 0000 0000

	my $osv1hex = "50" . SIGNALduino_b2h($newBitData); # output with length before  #todo: Länge berechnen
	Log3 $name, 4, "$name: OSV1 protocol id ($id) translated to RFXSensor format";
	Log3 $name, 4, "$name: converted to hex: ($osv1hex)";
	return (1,$osv1hex);
}
}

sub	SIGNALduino_AS()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	if(index($bitData,"1100",16) >= 0) # $rawData =~ m/^A{2,3}/)
	{  # Valid AS detected!	
		my $message_start = index($bitData,"1100",16);
		Debug "$name: AS protocol detected \n" if ($debug);
		
		my $message_end=index($bitData,"1100",$message_start+16);
		$message_end = length($bitData) if ($message_end == -1);
		my $message_length = $message_end - $message_start;
		
		return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );
		
		
		my $msgbits =substr($bitData,$message_start);
		
		my $ashex=sprintf('%02X', oct("0b$msgbits"));
		Log3 $name, 5, "$name: AS protocol converted to hex: ($ashex) with length ($message_length) bits \n";

		return (1,$bitData);
	}
	return (-1,undef);
}

sub	SIGNALduino_Hideki()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);
	
    Debug "$name: search in $bitData \n" if ($debug);
	my $message_start = index($bitData,"10101110");
	my $invert = 0;
	
	if ($message_start < 0) {
	$bitData =~ tr/01/10/;									# invert message
	$message_start = index($bitData,"10101110");			# 0x75 but in reverse order
	$invert = 1;
	}

	if ($message_start >= 0 )   # 0x75 but in reverse order
	{
		Debug "$name: Hideki protocol (invert=$invert) detected \n" if ($debug);

		# Todo: Mindest Laenge fuer startpunkt vorspringen 
		# Todo: Wiederholung auch an das Modul weitergeben, damit es dort geprueft werden kann
		my $message_end = index($bitData,"10101110",$message_start+71); # pruefen auf ein zweites 0x75,  mindestens 72 bit nach 1. 0x75, da der Regensensor minimum 8 Byte besitzt je byte haben wir 9 bit
        $message_end = length($bitData) if ($message_end == -1);
        my $message_length = $message_end - $message_start;
		
		return (-1,"message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1,"message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );

		
		my $hidekihex;
		my $idx;
		
		for ($idx=$message_start; $idx<$message_end; $idx=$idx+9)
		{
			my $byte = "";
			$byte= substr($bitData,$idx,8); ## Ignore every 9th bit
			Debug "$name: byte in order $byte " if ($debug);
			$byte = scalar reverse $byte;
			Debug "$name: byte reversed $byte , as hex: ".sprintf('%X', oct("0b$byte"))."\n" if ($debug);

			$hidekihex=$hidekihex.sprintf('%02X', oct("0b$byte"));
		}
		
		if ($invert == 0) {
			SIGNALduino_Log3 $name, 4, "$name: receive Hideki protocol not inverted";
		} else {
			SIGNALduino_Log3 $name, 4, "$name: receive Hideki protocol inverted";
		}
		SIGNALduino_Log3 $name, 4, "$name: Hideki protocol converted to hex: $hidekihex with " .$message_length ." bits, messagestart $message_start";

		return  (1,$hidekihex); ## Return only the original bits, include length
	}
	SIGNALduino_Log3 $name, 4, "$name: hideki start pattern (10101110) not found";
	return (-1,"Start pattern (10101110) not found");
}


sub SIGNALduino_Maverick()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	if ($bitData =~ m/^.*(101010101001100110010101).*/) 
	{  # Valid Maverick header detected	
		my $header_pos=$+[1];
		
		Log3 $name, 4, "$name: Maverick protocol detected: header_pos = $header_pos";

		my $hex=SIGNALduino_b2h(substr($bitData,$header_pos,26*4));
	
		return  (1,$hex); ## Return the bits unchanged in hex
	} else {
		return return (-1," header not found");
	}	
}

sub SIGNALduino_OSPIR()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	if ($bitData =~ m/^.*(1{14}|0{14}).*/) 
	{  # Valid Oregon PIR detected	
		my $header_pos=$+[1];
		
		Log3 $name, 4, "$name: Oregon PIR protocol detected: header_pos = $header_pos";

		my $hex=SIGNALduino_b2h($bitData);
	
		return  (1,$hex); ## Return the bits unchanged in hex
	} else {
		return return (-1," header not found");
	}	
}
sub SIGNALduino_MCRAW()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	my $hex=SIGNALduino_b2h($bitData);
	return  (1,$hex); ## Return the bits unchanged in hex
}



sub SIGNALduino_SomfyRTS()
{
	my ($name, $bitData,$id,$mcbitnum) = @_;
	
    #(my $negBits = $bitData) =~ tr/10/01/;   # Todo: eventuell auf pack umstellen

	if (defined($mcbitnum)) {
		Log3 $name, 4, "$name: Somfy bitdata: $bitData ($mcbitnum)";
		if ($mcbitnum == 57) {
			$bitData = substr($bitData, 1, 56);
			Log3 $name, 4, "$name: Somfy bitdata: _$bitData (" . length($bitData) . "). Bit am Anfang entfernt";
		}
	}
	my $encData = SIGNALduino_b2h($bitData);

	#Log3 $name, 4, "$name: Somfy RTS protocol enc: $encData";
	return (1, $encData);
}

# - - - - - - - - - - - -
#=item SIGNALduino_filterMC()
#This functons, will act as a filter function. It will decode MU data via Manchester encoding
# 
# Will return  $count of ???,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_filterMC($$$%)
{
	
	## Warema Implementierung : Todo variabel gestalten
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	my ($ht, $hasbit, $value) = 0;
	$value=1 if (!$debug);
	my @bitData;
	my @sigData = split "",$rawData;

	foreach my $pulse (@sigData)
	{
	  next if (!defined($patternListRaw{$pulse})); 
	  #Log3 $name, 4, "$name: pulese: ".$patternListRaw{$pulse};
		
	  if (SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5))
	  {
		# Short	
		$hasbit=$ht;
		$ht = $ht ^ 0b00000001;
		$value='S' if($debug);
		#Log3 $name, 4, "$name: filter S ";
	  } elsif ( SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs}*2,abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5)) {
	  	# Long
	  	$hasbit=1;
		$ht=1;
		$value='L' if($debug);
		#Log3 $name, 4, "$name: filter L ";	
	  } elsif ( SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{syncabs}+(2*$ProtocolListSIGNALduino{$id}{clockabs}),abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5))  {
	  	$hasbit=1;
		$ht=1;
		$value='L' if($debug);
	  	#Log3 $name, 4, "$name: sync L ";
	
	  } else {
	  	# No Manchester Data
	  	$ht=0;
	  	$hasbit=0;
	  	#Log3 $name, 4, "$name: filter n ";
	  }
	  
	  if ($hasbit && $value) {
	  	$value = lc($value) if($debug && $patternListRaw{$pulse} < 0);
	  	my $bit=$patternListRaw{$pulse} > 0 ? 1 : 0;
	  	#Log3 $name, 5, "$name: adding value: ".$bit;
	  	
	  	push @bitData, $bit ;
	  }
	}

	my %patternListRawFilter;
	
	$patternListRawFilter{0} = 0;
	$patternListRawFilter{1} = $ProtocolListSIGNALduino{$id}{clockabs};
	
	#Log3 $name, 5, "$name: filterbits: ".@bitData;
	$rawData = join "", @bitData;
	return (undef ,$rawData, %patternListRawFilter);
	
}

# - - - - - - - - - - - -
#=item SIGNALduino_filterSign()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
# 
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_filterSign($$$%)
{
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);


	my %buckets;
	# Remove Sign
    %patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sign from all
    
    my $intol=0;
    my $cnt=0;

    # compress pattern hash
    foreach my $key (keys %patternListRaw) {
			
		#print "chk:".$patternListRaw{$key};
    	#print "\n";

        $intol=0;
		foreach my $b_key (keys %buckets){
			#print "with:".$buckets{$b_key};
			#print "\n";
			
			# $value  - $set <= $tolerance
			if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.25))
			{
		    	#print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
				$cnt++;
				eval "\$rawData =~ tr/$key/$b_key/";

				#if ($key == $msg_parts{clockidx})
				#{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}
			#	elsif ($key == $msg_parts{syncidx})
			#	{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}			
				
				$buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
				#print"\t recalc to ". $buckets{$b_key}."\n";

				delete ($patternListRaw{$key});  # deletes the compressed entry
				$intol=1;
				last;
			}
		}	
		if ($intol == 0) {
			$buckets{$key}=abs($patternListRaw{$key});
		}
	}

	return ($cnt,$rawData, %patternListRaw);
	#print "rdata: ".$msg_parts{rawData}."\n";

	#print Dumper (%buckets);
	#print Dumper (%msg_parts);

	#modify msg_parts pattern hash
	#$patternListRaw = \%buckets;
}


# - - - - - - - - - - - -
#=item SIGNALduino_compPattern()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
# 
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_compPattern($$$%)
{
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);


	my %buckets;
	# Remove Sign
    #%patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sing from all
    
    my $intol=0;
    my $cnt=0;

    # compress pattern hash
    foreach my $key (keys %patternListRaw) {
			
		#print "chk:".$patternListRaw{$key};
    	#print "\n";

        $intol=0;
		foreach my $b_key (keys %buckets){
			#print "with:".$buckets{$b_key};
			#print "\n";
			
			# $value  - $set <= $tolerance
			if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.4))
			{
		    	#print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
				$cnt++;
				eval "\$rawData =~ tr/$key/$b_key/";

				#if ($key == $msg_parts{clockidx})
				#{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}
			#	elsif ($key == $msg_parts{syncidx})
			#	{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}			
				
				$buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
				#print"\t recalc to ". $buckets{$b_key}."\n";

				delete ($patternListRaw{$key});  # deletes the compressed entry
				$intol=1;
				last;
			}
		}	
		if ($intol == 0) {
			$buckets{$key}=$patternListRaw{$key};
		}
	}

	return ($cnt,$rawData, %patternListRaw);
	#print "rdata: ".$msg_parts{rawData}."\n";

	#print Dumper (%buckets);
	#print Dumper (%msg_parts);

	#modify msg_parts pattern hash
	#$patternListRaw = \%buckets;
}

#print Dumper (%msg_parts);
#print "\n";
#SIGNALduino_filterSign(%msg_parts);
#print Dumper (%msg_parts);
#print "\n";

1;

=pod
=item summary    supports the same low-cost receiver for digital signals
=item summary_DE Unterst&uumltzt den gleichnamigen Low-Cost Empf&aumlnger fuer digitale Signale
=begin html

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

	<table>
	<tr><td>
	The SIGNALduino ia based on an idea from mdorenka published at <a
	href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>.

	With the opensource firmware (see this <a
	href="https://github.com/RFD-FHEM/SIGNALduino">link</a>) it is capable
	to receive and send different protocols over different medias. Currently are 433Mhz protocols implemented.
	<br><br>

	The following device support is currently available:
	<br><br>


	Wireless switches  <br>
	ITv1 & ITv3/Elro and other brands using pt2263 or arctech protocol--> uses IT.pm<br><br>

	In the ITv1 protocol is used to sent a default ITclock from 250 and it may be necessary in the IT-Modul to define the attribute ITclock<br>
	<br><br>
	Temperatur / humidity senso
	<ul>
	<li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 and many more -> 14_CUL_TCM97001 </li>
	<li>Oregon Scientific v2 and v3 Sensors  -> 41_OREGON.pm</li>
	<li>Temperatur / humidity sensors suppored -> 14_SD_WS07</li>
    <li>technoline WS 6750 and TX70DTH -> 14_SD_WS07</li>
    <li>Eurochon EAS 800z -> 14_SD_WS07</li>
    <li>CTW600, WH1080	-> 14_SD_WS09 </li>
    <li>Hama TS33C, Bresser Thermo/Hygro Sensor -> 14_Hideki</li>
    <li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07</li>
	</ul>
	<br><br>

	It is possible to attach more than one device in order to get better
	reception, fhem will filter out duplicate messages.<br><br>

	Note: this module require the Device::SerialPort or Win32::SerialPort
	module. It can currently only attatched via USB.

	</td>
	</tr>
	</table>
	<br>
	<a name="SIGNALduinodefine"></a>
	<b>Define</b><br>
	<code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code> <br>
	<br>
	USB-connected devices (SIGNALduino):<br>
	<ul><li>
		&lt;device&gt; specifies the serial port to communicate with the SIGNALduino.
		The name of the serial-device depends on your distribution, under
		linux the cdc_acm kernel module is responsible, and usually a
		/dev/ttyACM0 or /dev/ttyUSB0 device will be created. If your distribution does not have a
		cdc_acm module, you can force usbserial to handle the SIGNALduino by the
		following command:
		<ul>
		modprobe usbserial 
		vendor=0x03eb
		product=0x204b
		</ul>In this case the device is most probably
		/dev/ttyUSB0.<br><br>

		You can also specify a baudrate if the device name contains the @
		character, e.g.: /dev/ttyACM0@57600<br><br>This is also the default baudrate

		It is recommended to specify the device via a name which does not change:
		e.g. via by-id devicename: /dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600

		If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
		perl module Device::SerialPort is not needed, and fhem opens the device
		with simple file io. This might work if the operating system uses sane
		defaults for the serial parameters, e.g. some Linux distributions and
		OSX.  <br><br>
		</li>

	</ul>

	<a name="SIGNALduinoattr"></a>
	<b>Attributes</b>
	<ul>
	<li><a name="addvaltrigger">addvaltrigger</a><br>
        Create triggers for additional device values. Right now these are RSSI, RAWMSG and DMSG.
        </li>
        <li>blacklist_IDs<br>
        The blacklist works only if a whitelist not exist.
        </li>
        <li>cc1101_frequency<br>
        Since the PA table values ​​are frequency-dependent, is at 868 MHz a value greater 800 required.
        </li>
	<li><a href="#do_not_notify">do_not_notify</a></li>
	<li><a href="#attrdummy">dummy</a></li>
	<li>debug<br>
	This will bring the module in a very verbose debug output. Usefull to find new signals and verify if the demodulation works correctly.
	</li>
	<li>development<br>
	With development you can enable protocol decoding for protocolls witch are still in development and may not be very accurate implemented. 
	This can result in crashes or throw high amount of log entrys in your logfile, so be careful to use this. <br><br>
	
	Protocols flagged with a developID flag are not loaded unless specified to do so.<br>
	
	If the flag developId => 'y' is set in the protocol defintion then the protocol is still in development. You can enable it with the attribute:<br>
	Specify "y" followed with the protocol id to enable it.<br><br>
    If the protocoll is developed well, but the logical module is not ready, developId => 'm' is set.<br> 
    You can enable it with the attribute:<br>
	Specify "m" followed with the protocol id to enable it.<br>
	</li>
	<li>doubleMsgCheck_IDs<br>
	This attribute allows it, to specify protocols which must be received two equal messages to call dispatch to the modules.<br>
	You can specify multiple IDs wih a colon : 0,3,7,12<br>
	</li>
	<li>flashCommand<br>
    	This is the command, that is executed to performa the firmware flash. Do not edit, if you don't know what you are doing.<br>
    	The default is: avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]<br>
		It contains some place-holders that automatically get filled with the according values:<br>
		<ul>
			<li>[PORT]<br>
			is the port the Signalduino is connectd to (e.g. /dev/ttyUSB0) and will be used from the defenition</li>
			<li>[HEXFILE]<br>
			is the .hex file that shall get flashed. There are three options (applied in this order):<br>
			- passed in set flash as first argument<br>
			- taken from the hexFile attribute<br>
			- the default value defined in the module<br>
			</li>
			<li>[LOGFILE]<br>
			The logfile that collects information about the flash process. It gets displayed in FHEM after finishing the flash process</li>
		</ul>
    
    </li>
    <li>hardware<br>
    When using the flash command, you should specify what hardware you have connected to the usbport. Doing not, can cause failures of the device.
    </li>
    <li>minsecs<br>
    This is a very special attribute. It is provided to other modules. minsecs should act like a threshold. All logic must be done in the logical module. 
    If specified, then supported modules will discard new messages if minsecs isn't past.
    </li>
    
    <li>noMsgVerbose<br>
    With this attribute you can control the logging of debug messages from the io device.
    If set to 3, this messages are logged if global verbose is set to 3 or higher.
    </li>
    <li>longids<br>
        Comma separated list of device-types for SIGNALduino that should be handled using long IDs. This additional ID allows it to differentiate some weather sensors, if they are sending on the same channel. Therfor a random generated id is added. If you choose to use longids, then you'll have to define a different device after battery change.<br>
		Default is to not to use long IDs for all devices.
      <br><br>
      Examples:<PRE>
# Do not use any long IDs for any devices:
attr sduino longids 0
# Use any long IDs for all devices (this is default):
attr sduino longids 1
# Use longids for BTHR918N devices.
# Will generate devices names like BTHR918N_f3.
attr sduino longids BTHR918N
</PRE></li>
<li>rawmsgEvent<br>
When set to "1" received raw messages triggers events
</li>
<li>suppressDeviceRawmsg<br>
When set to 1, the internal "RAWMSG" will not be updated with the received messages
</li>
<li>whitelistIDs<br>
This attribute allows it, to specify whichs protocos are considured from this module.
Protocols which are not considured, will not generate logmessages or events. They are then completly ignored. 
This makes it possible to lower ressource usage and give some better clearnes in the logs.
You can specify multiple whitelistIDs wih a colon : 0,3,7,12<br>
With a # at the beginnging whitelistIDs can be deactivated.
</li><br>
   <li>WS09_CRCAUS<br>
       <br>0: CRC-Check WH1080 CRC = 0  on, default   
       <br>2: CRC = 49 (x031) WH1080, set OK
    </li>
   </ul>
   
   
    
	<a name="SIGNALduinoget"></a>
	<b>Get</b>
	<ul>
		<li>version<br>
		return the SIGNALduino firmware version
		</li><br>
		<li>raw<br>
		Issue a SIGNALduino firmware command, and wait for one line of data returned by
		the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
		commands. With this line, you can send almost any signal via a transmitter connected
		</li><br>
		<li>cmds<br>
		Depending on the firmware installed, SIGNALduinos have a different set of
		possible commands. Please refer to the sourcecode of the firmware of your
		SIGNALduino to interpret the response of this command. See also the raw-
		command.
		</li><br>
		<li>protocolIDs<br>
		display a list of the protocol IDs
		</li><br>
		<li>ccconf<br>
		Only with cc1101 receiver.
		Read some CUL radio-chip (cc1101) registers (frequency, bandwidth, etc.),
		and display them in human readable form.
		</li><br>
		<li>ccpatable<br>
		read cc1101 PA table (power amplification for RF sending)
		</li><br>
		<li>ccreg<br>
		read cc1101 registers (99 reads all cc1101 registers)
		</li><br>
	</ul>
	<a name="SIGNALduinoset"></a>
	<b>SET</b>
	<ul>
		<li>raw<br>
		Issue a SIGNALduino firmware command, without waiting data returned by
		the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
		commands. With this line, you can send almost any signal via a transmitter connected

        To send some raw data look at these examples:
		P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional) 
		<br>Example 1: set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030  sends the data in raw mode 3 times repeated
        <br>Example 2: set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE  sends the data manchester encoded with a clock of 250uS
        <br>Example 3: set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE  sends a combined message of raw and manchester encoded repeated 3 times

		<br>;
		</p>


		</li><br>
		<li>reset<br>
		This will do a reset of the usb port and normaly causes to reset the uC connected.
		</li><br>
		<li>close<br>
		Closes the connection to the device.
		</li><br>
		<li>flash [hexFile|url]<br>
			The SIGNALduino needs the right firmware to be able to receive and deliver the sensor data to fhem. In addition to the way using the
			arduino IDE to flash the firmware into the SIGNALduino this provides a way to flash it directly from FHEM.
			You can specify a file on your fhem server or specify a url from which the firmware is downloaded

			There are some requirements:
			<ul>
				<li>avrdude must be installed on the host<br>
					On a Raspberry PI this can be done with: sudo apt-get install avrdude</li>
				<li>the hardware attribute must be set if using any other hardware as an Arduino nano<br>
					This attribute defines the command, that gets sent to avrdude to flash the uC.<br></li>
		     	<br>
	
			</ul>
		</li>
		<li>sendMsg<br>
		This command will create the needed instructions for sending raw data via the signalduino. Insteaf of specifying the signaldata by your own you specify 
		a protocol and the bits you want to send. The command will generate the needed command, that the signalduino will send this.
		<br><br>
		Please note, that this command will work only for MU or MS protocols. You can't transmit manchester data this way.
		<br><br>
		Input args are:
		<p>
		P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional) 
		<br>Example: P0#0101#R3#C500
		<br>Will generate the raw send command for the message 0101 with protocol 0 and instruct the arduino to send this three times and the clock is 500.
		<br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;
		</p>

		
		</li><br>
		<li>enableMessagetype<br>
			Allows you to enable the message processing for 
			<ul>
				<li>messages with sync (syncedMS),</li>
				<li>messages without a sync pulse (unsyncedMU) </li>
				<li>manchester encoded messages (manchesterMC) </li>
			</ul>
			The new state will be saved into the eeprom of your arduino.
		</li><br>
		<li>disableMessagetype<br>
			Allows you to disable the message processing for 
			<ul>
				<li>messages with sync (syncedMS),</li>
				<li>messages without a sync pulse (unsyncedMU)</li> 
				<li>manchester encoded messages (manchesterMC) </li>
			</ul>
			The new state will be saved into the eeprom of your arduino.
		</li><br><br>
		
		<li>freq / bWidth / patable / rAmpl / sens<br>
		Only with CC1101 receiver.<br>
		Set the sduino frequency / bandwidth / PA table / receiver-amplitude / sensitivity<br>
		
		Use it with care, it may destroy your hardware and it even may be
		illegal to do so. Note: The parameters used for RFR transmission are
		not affected.<br>
		<ul>
		<li>freq sets both the reception and transmission frequency. Note:
		    Although the CC1101 can be set to frequencies between 315 and 915
		    MHz, the antenna interface and the antenna of the CUL is tuned for
		    exactly one frequency. Default is 868.3 MHz (or 433 MHz)</li>
		<li>bWidth can be set to values between 58 kHz and 812 kHz. Large values
		    are susceptible to interference, but make possible to receive
		    inaccurately calibrated transmitters. It affects tranmission too.
		    Default is 325 kHz.</li>
		<li>patable change the PA table (power amplification for RF sending) 
		</li>
		<li>rAmpl is receiver amplification, with values between 24 and 42 dB.
		    Bigger values allow reception of weak signals. Default is 42.
		</li>
		<li>sens is the decision boundary between the on and off values, and it
		    is 4, 8, 12 or 16 dB.  Smaller values allow reception of less clear
		    signals. Default is 4 dB.</li>
		</ul>
		</li><br>
		
	</ul>




=end html
=cut
