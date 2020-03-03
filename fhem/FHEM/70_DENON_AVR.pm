###############################################################################
# 70_DENON_AVR
#
#     This file is part of Fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with Fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################
#
# DENON_AVR maintained by Martin Gutenbrunner
# original credits to raman and the community (see Forum thread)
#
# This module enables FHEM to interact with Denon and Marantz audio devices.
#
# Discussed in FHEM Forum: https://forum.fhem.de/index.php/topic,58452.300.html
#
# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use HttpUtils;

sub DENON_AVR_Get($@);
sub DENON_AVR_Set($@);
sub DENON_AVR_Define($$);
sub DENON_AVR_Undefine($$);
sub DENON_AVR_Notify($$);


# Database and call-functions
######################################################################
my $DENON_db = {
	'SSLEV' => {
		'FL'	=> 'Front-Left',
		'FR'	=> 'Front-Right',
		'C'	=> 'Center',
		'SW'	=> 'Subwoofer',
		'SW2'	=> 'Subwoofer2',
		'SL'	=> 'Surround-Left',
		'SR'	=> 'Surround-Right',
		'SBL'	=> 'Surround-Back-Left',
		'SBR'	=> 'Surround-Back-Right',
		'SB'	=> 'Surround-Back',
		'FHL'	=> 'Front-Height-Left',
		'FHR'	=> 'Front-Height-Right',
		'FWL'	=> 'Front-Wide-Left',
		'FWR'	=> 'Front-Wide-Right',
		'TFL'	=> 'Top-Front-Left',
		'TFR'	=> 'Top-Front-Right',
		'TML'	=> 'Top-Middle-Left',
		'TMR'	=> 'Top-Middle-Right',	
		'TRL'	=> 'Top-Rear-Left',
		'TRR'	=> 'Top-Rear-Right',
		'RHL'	=> 'Rear-Height-Left',
		'RHR'	=> 'Rear-Height-Right',
		'FDL'	=> 'Front-Dolby-Left',
		'FDR'	=> 'Front-Dolby-Right',
		'SDL'	=> 'Surround-Dolby-Left',
		'SDR'	=> 'Surround,Dolby-Right',
		'BDL'	=> 'Back-Dolby-Left',
		'BDR'	=> 'Back-Dolby-Right',
		'SHL'	=> 'Surround-Height-Left',
		'SHR'	=> 'Surround-Hight-Right',
		'TS'	=> 'Top-Surround',
	},
		'CV' => {
		'FL'	=> 'FrontLeft',
		'FR'	=> 'FrontRight',
		'C'		=> 'Center',
		'SW'	=> 'Subwoofer',
		'SW2'	=> 'Subwoofer2',
		'SL'	=> 'SourroundLeft',
		'SR'	=> 'SourroundRight',
		'SBL'	=> 'SourroundBackLeft',
		'SBR'	=> 'SourroundBackRight',
		'SB'	=> 'SourroundBack',
		'FHL'	=> 'FrontHeightLeft',
		'FHR'	=> 'FrontHeightRight',
		'FWL'	=> 'FrontWideLeft',
		'FWR'	=> 'FrontWideRight',
		'TFL'	=> 'TopFrontLeft',
		'TFR'	=> 'TopFrontRight',
		'TML'	=> 'TopMiddleLeft',
		'TMR'	=> 'TopMiddleRight',	
		'TRL'	=> 'TopRearLeft',
		'TRR'   => 'TopRearRight',
		'RHL'   => 'RearHeightLeft',
		'RHR'   => 'RearHeightRight',
		'FDL'   => 'FrontDolbyLeft',
		'FDR'   => 'FrontDolbyRight',
		'SDL'   => 'SurroundDolbyLeft',
		'SDR'   => 'SurroundDolbRight',
		'BDL'   => 'BackDolbyLeft',
		'BDR'   => 'BackDolbyRight',
		'SHL'   => 'SurroundHeightLeft',
		'SHR'   => 'SurroundHightRight',
		'TS'    => 'TopSurround',
	},
	'SSALSSET' => {                     #AutoLipSync
		'on'     => 'ON',
		'off'    => 'OFF',
	},
	'SSVCTZMADIS' =>  {           #Lautstärkeanzeige
		'relativ'     => 'REL',
		'absolute'    => 'ABS',
        },
	'SSVCTZMAMLV' =>  {           #MutingLevel
		'mute' => 'MUT',
		'-40db' => '040',
		'-20db' => '060',
		},  
	'DC' => {
		'AUTO'		=> 'auto',
		'PCM' 		=> 'PCM',
		'DTS' 		=> 'DTS',
	},
	'DIM' => {                     #Dim-States
		'bright' => 'BRI',
		'dim' 	 => 'DIM',
		'dark'   => 'DAR',
		'off'    => 'OFF',
		'toggle' => 'SEL',
	},
	'ECO' => {                     #ECO-Mode
		'on'     => 'ON',
		'auto'   => 'AUTO',
		'off'    => 'OFF',
	},
	'MN' => {      			#System-Remote:
		'up' => 'CUP',
		'down' => 'CDN',
		'left' => 'CLT',
		'right' => 'CRT',
		'enter' => 'ENT',
		'return' => 'RTN',
		'option' => 'OPT',
		'info' => 'INF',
		'channelLevelAdjust' => 'CHL',
		'info' => 'INF',
		'allZoneStereo' => 'ZST',
		'info' => 'INF',
	},
	'MS' => {                    #Surround-Mode
		'Movie' 						=> 'MOVIE',
		'Music' 						=> 'MUSIC',
		'Game' 						=> 'GAME',
		'Direct' 						=> 'DIRECT',
		'Pure_Direct' 				=> 'PURE DIRECT',
		'Stereo' 					=> 'STEREO',
		'Auto' 						=> 'AUTO',
		'Dolby_Digital' 				=> 'DOLBY DIGITAL',
		'DTS_Surround' 			=> 'DTS SURROUND',
		'Auro3D' 					=> 'AURO3D',
		'Auro2D_Surround' 			=> 'AURO2DSURR',
		'Multichannel_Stereo' 		=> 'MCH STEREO',
		'Wide_Screen' 				=> 'WIDE SCREEN',
		'Super_Stadium' 			=> 'SUPER STADIUM',
		'Rock_Arena' 				=> 'ROCK ARENA',
		'Jazz_Club' 					=> 'JAZZ CLUB',
		'Classic_Concert' 			=> 'CLASSIC CONCERT',
		'Mono_Movie' 				=> 'MONO MOVIE',
		'Matrix' 					=> 'MATRIX',
		'Video_Game' 				=> 'VIDEO GAME',
		'Dolby_Audio_Surround'	=> 'DOLBY AUDIO-DSUR',
		'Dolby_Audio_Digital'		=> 'DOLBY AUDIO-DD',
		'Dolby_Audio_Digital-Surround'		=> 'DOLBY AUDIO-DD+DSUR',
		'Dolby_Audio_Digital-Neural:X'		=> 'DOLBY AUDIO-DD+NEURAL:X',
		'Neural:X'					=> 'NEURAL:X',
		'Virtual' 					=> 'VIRTUAL',
		'Left' 						=> 'LEFT',
		'Right' 						=> 'RIGHT',
		'Quick1' 					=> 'QUICK1',
		'Quick2' 					=> 'QUICK2',
		'Quick3' 					=> 'QUICK3',
		'Quick4' 					=> 'QUICK4',
		'Quick5' 					=> 'QUICK5',
		'Smart1' 					=> 'SMART1',
		'Smart2' 					=> 'SMART2',
		'Smart3' 					=> 'SMART3',
		'Smart4' 					=> 'SMART4',
		'Smart5' 					=> 'SMART5',
	},
		'MS-set_sound_out' => {                    #to set sound_out
		'Pure_Direct' 				=> 'PURE DIRECT',
		'Stereo' 					=> 'STEREO',
		'Auto' 						=> 'AUTO',
		'Dolby_Digital' 				=> 'DOLBY DIGITAL',
		'DTS_Surround' 			=> 'DTS SURROUND',
		'Auro3D' 					=> 'AURO3D',
		'Auro2D_Surround' 			=> 'AURO2DSURR',
		'Multichannel_Stereo' 		=> 'MCH STEREO',
		'Wide_Screen' 				=> 'WIDE SCREEN',
		'Super_Stadium' 			=> 'SUPER STADIUM',
		'Rock_Arena' 				=> 'ROCK ARENA',
		'Jazz_Club' 					=> 'JAZZ CLUB',
		'Classic_Concert' 			=> 'CLASSIC CONCERT',
		'Mono_Movie' 				=> 'MONO MOVIE',
		'Matrix' 					=> 'MATRIX',
		'Video_Game' 				=> 'VIDEO GAME',
		'Dolby_Audio_Surround'	=> 'DOLBY AUDIO-DSUR',
		'Dolby_Audio_Digital'		=> 'DOLBY AUDIO-DD',
		'Dolby_Audio_Digital-Surround'		=> 'DOLBY AUDIO-DD+DSUR',
		'Dolby_Audio_Digital-Neural:X'		=> 'DOLBY AUDIO-DD+NEURAL:X',
		'Neural:X'					=> 'NEURAL:X',
		'Virtual' 					=> 'VIRTUAL',
	},
	 'MS-set_surroundMode' => {                    #to set surroundMode
		'Movie' 						=> 'MOVIE',
		'Music' 						=> 'MUSIC',
		'Game' 						=> 'GAME',
		'Direct' 						=> 'DIRECT',
	},
	'MU' => {
		'on' 		=> 'ON',
		'off' 		=> 'OFF',
		'status' 	=> '?',
	},
	'NS' => {  
		#System-Info:
		'FRN' => 'Network-Name', # device-type
		#Remote:
		'up' => '90',
		'down' => '91',
		'left' => '92',
		'right' => '93',
		'enter' => '94',
		'play' => '9A',
		'pause' => '9B',
		'stop' => '9C',
		'skipPlus' => '9D',
		'skipMinus' => '9E',
		'manualSearchPlus' => '9F',
		'manualSearchMinus' => '9G',
		'repeatOne' => '9H',
		'repeatAll' => '9I',
		'repeatOff' => '9J',
		'randomOn' => '9K',
		'randomOff' => '9M',
		'toggleSwitch' => '9W',
		'pageNext' => '9X',
		'pagePrevious' => '9Y',
		'manualSearchStop' => '9Z',
		'toggleRepeat' => 'RPT',
		'toggleRandom' => 'RND',
		'addFavoritesFolder' => 'FV MEM',
	},
	'NSE' => {                     #Info-Display - for example:
		'0' => 'currentMedia',     # Now Playing iRadio 
        '1' => 'currentTitle',     # Dua Lipa: Hotter than hell 
		'2a' => 'currentArtist',   # Bayern 3 Live oder currentArtist
		'2s' => 'currentStation',  # Bayern 3 Live
		'3' => 'currentBitrate',   # 44.1kHz 
		'4' => 'currentAlbum',
		'5' => 'currentPlaytime',  # 0:38 100% 
		'6' => 'ignore',
		'7' => 'ignore',
		'8' => 'ignore',
    },
	'PS' => {                     #Sound-Parameter
		'TONE CTRL' => 'toneControl',
		'DRC'       => 'dynamicCompression',
		'LFC'       => 'audysseyLFC',
		'LFE'       => 'lowFrequencyEffects',
		'BAS'       => 'bass',
		'TRE'       => 'treble',
		'DIL'       => 'dialogLevelAdjust',
		'SWL'       => 'subwooferLevelAdjust',
		'CINEMA EQ'  => 'cinemaEQ',
		'LOM' 		=> 'loudness',
		'PHG' 		=> { 
			'PHG' => 'PLIIheightGain',
			'LOW' => 'low',
			'MID' => 'mid',
			'HI' => 'high',
		},	
		'MULTEQ' => { 
			'MULTEQ' => 'multEQ',
			'AUDYSSEY' => 'reference',
			'BYP.LR' => 'bypassL/R',
			'FLAT' => 'flat',
			'MANUAL' => 'manual',
			'OFF' => 'off',
		},
		'DYNEQ' 	=> 'dynamicEQ',
		'DYNVOL' 	=> {
			'DYNVOL' 	=> 'dynamicVolume',
			'HEV' 		=> 'heavy',
			'MED' 		=> 'medium',
			'LIT' 		=> 'light',
			'OFF' 		=> 'off',
		},
		'GEQ' 		=> 'graphicEQ',
		'PAN' 		=> 'panorama',
		'CES' 		=> 'centerSpread',
		'BAL' 		=> 'balance',
		'SDB' 		=> 'sdb',
		'SDI' 		=> 'sourceDirect',
		
	},
	'PV' => {
		'OFF' 		=> 'Off',
		'STD' 		=> 'Standard',
		'MOV' 		=> 'Movie',
		'VVD' 		=> 'Vivid',
		'STM' 		=> 'Stream',
		'CTM' 		=> 'Custom',
		'DAY' 		=> 'ISF_Day',
		'NGT' 		=> 'ISF_Night',
	},
	'PW' => {
		'on' 		=> 'ON',
		'off' 		=> 'STANDBY',
		'standby' 	=> 'STANDBY',
		'status' 	=> '?',
	},
	'R' => {				  #default names:
		'1' => 'MAIN ZONE',   # MAIN ZONE
		'2' => 'ZONE2',       # ZONE2
		'3' => 'ZONE3',       # ZONE3
		'4' => 'ZONE4',       # ZONE4
		'Z' => 'ZONE',		  # ZONE
	},
	'REMOTE' => {      			 #Remote - all commands:
		'up' => 'CUP',
		'down' => 'CDN',
		'left' => 'CLT',
		'right' => 'CRT',
		'enter' => 'ENT',
		'return' => 'RTN',
		'option' => 'OPT',
		'info' => 'INF',
		'channelLevelAdjust' => 'CHL',
		'info' => 'INF',
		'setup' => '',
		'eco' => '',
		'play' => '9A',
		'pause' => '9B',
		'stop' => '9C',
		'skipPlus' => '9D',
		'skipMinus' => '9E',
		'manualSearchPlus' => '9F',
		'manualSearchMinus' => '9G',
		'repeatOne' => '9H',
		'repeatAll' => '9I',
		'repeatOff' => '9J',
		'randomOn' => '9K',
		'randomOff' => '9M',
		'toggleSwitch' => '9W',
		'pageNext' => '9X',
		'pagePrevious' => '9Y',
		'manualSearchStop' => '9Z',
		'toggleRepeat' => 'RPT',
		'toggleRandom' => 'RND',
		'addFavoritesFolder' => 'FV MEM',
	},
	'SI' => {								#Inputs
			'Phono' 					=> 'PHONO', 
			'CD' 						=> 'CD', 
			'Tuner' 					=> 'TUNER', 
			'Dock' 						=> 'DOCK',
			'DVD' 						=> 'DVD',
			'DVR' 						=> 'DVR',
			'Blu-Ray'					=> 'BD',
			'TV' 						=> 'TV',
			'Sat/Cbl' 					=> 'SAT/CBL',
			'Sat' 						=> 'SAT', 			
			'Mediaplayer' 				=> 'MPLAY', 
			'Game' 						=> 'GAME', 
			'HDRadio'					=> 'HDRADIO',
			'OnlineMusic' 				=> 'NET', 
			'Spotify' 					=> 'SPOTIFY', 
			'LastFM' 					=> 'LASTFM', 
			'Flickr' 					=> 'FLICKR', 
			'iRadio' 					=> 'IRADIO', 
			'Server' 					=> 'SERVER', 
			'Favorites' 				=> 'FAVORITES',
			'Pandora'					=> 'PANDORA',
			'SiriusXM'					=> 'SIRIUSXM',
			'Aux1' 						=> 'AUX1', 
			'Aux2' 						=> 'AUX2', 
			'Aux3' 						=> 'AUX3', 
			'Aux4' 						=> 'AUX4', 
			'Aux5' 						=> 'AUX5', 
			'Aux6' 						=> 'AUX6', 
			'Aux7' 						=> 'AUX7', 
			'AuxA' 						=> 'AUXA', 
			'AuxB' 						=> 'AUXB', 
			'AuxC' 						=> 'AUXC', 
			'AuxD' 						=> 'AUXD', 
			'V.Aux' 					=> 'V.AUX', 
			'Bluetooth' 				=> 'BT', 
			'Net/Usb' 					=> 'NET/USB', 
			'Usb/iPod' 					=> 'USB/IPOD', 
			'Usb_play' 					=> 'USB', 
			'iPod_play' 				=> 'IPD', 
			'iRadio_play' 				=> 'IRP', 
			'Favorites_play' 			=> 'FVP', 
			'Source'                   => 'SOURCE',
	},
	'SS' => {                 #System-Info:
		'FUN' => {			  # default names:
			'DVD' => '',      # DVD
			'DVR'  => '', 
			'DOCK' => '',
			'BD' => '',       # Blu-ray
			'TV' => '',       # TV Audio
			'SAT/CBL' => '',  # SAT/CBL
			'SAT' => '',	  # SAT - some old Marantz models
			'MPLAY' => '',    # Media Player
			'BT' => '',       # Bluetooth
			'GAME' => '',     # Game
			'AUX1' => '',	  # AUX1-7
			'AUX2' => '',
			'AUX3' => '',
			'AUX4' => '',
			'AUX5' => '',
			'AUX6' => '',
			'AUX7' => '',
			'AUXA' => '',
			'AUXB' => '',
			'AUXC' => '',
			'AUX' => '',
            'V.AUX' => '',		
			'CD' => '',       # CD
			'PHONO' => '',    # Phono
			'HDRADIO' => '',
			'TUNER' => '',
			'FAVORITES' => '',
			'IRADIO' => '',
			'SIRIUSXM' => '',
			'PANDORA' => '',
			'SERVER' => '',
			'FLICKR' => '',
			'NET' => '',
			'LASTFM' => '',
			'NET/USB'=> '',
			'USB/IPOD' => '',
			'USB' => '',
			'IPD' => '',
			'IRP' => '',
			'FVP' => '',
			'SOURCE' => '',
		},
		'LAN' => 'lan',      # DEU
		'LOC' => 'lock',      # off/on
		'PAA' => {
			'MOD' => {
				'FRB' => '5.1-Channel+FrontB',			
				'BIA' => '5.1-Channel (Bi-Amp)',	
				'ZO2' => '5.1-Channel+Zone2',
				'ZO3' => '5.1-Channel+Zone3',
				'ZOM' => '5.1-Channel+Zone2/3-Mono',
				'NOR' => '7.1-Kanal',
				'2CH' => '7.1/2-Channel-Front',
				'91C' => '9.1-Channel',
				'DAT' => 'Dolby Atmos',
			},
		},
		'INF' => { 			 #Informations
			'MO1' => {
				'INT'   => 'interface',
				'SUP00' => 'resolution0',
				'SUP01' => 'resolution1',
				'SUP02' => 'resolution2',
				'SUP03' => 'resolution3',
				'SUP04' => 'resolution4',
				'SUP05' => 'resolution5',
			},
			'MO2' => {
				'INT'   => 'interface',
				'SUP00' => 'resolution0',
				'SUP01' => 'resolution1',
				'SUP02' => 'resolution2',
				'SUP03' => 'resolution3',
				'SUP04' => 'resolution4',
			},
			'FRMAVR' => 'firmware_AVR',
			'FRMDTS' => 'firmware_DTS',
			'AIS' => {
				'FSV' => 'samplingRate',
				'FOR' => 'audioFormat',
				'SIG' => {
					'00' => 'na 00',
					'01' => 'Analog',
					'02' => 'PCM',
					'03' => 'Dolby Audio DD',
					'04' => 'Dolby TrueHD',
					'05' => 'Dolby Atmos',
					'06' => 'DTS',
					'07' => 'na 07',
					'08' => 'DTS-HD Hi Res',
					'09' => 'DTS-HD Mstr',
					'10' => 'na 10',
					'11' => 'na 11',
					'12' => 'Dolby Digital',
					'13' => 'PCM Zero',
					'14' => 'na 14',
					'15' => 'na 15',
					'16' => 'na 16',
					'17' => 'na 17',
					'18' => 'na 18',
					'19' => 'na 19',
					'20' => 'na 20',
				},
			},
		},
		'SMG' => { 			 #Sound-Mode - status only
			'MUS' => 'Music',
			'MOV' => 'Movie',
			'GAM' => 'Game',
			'PUR' => 'Pure_Direct',
		},
		'SOD' => {            # used inputs: USE = aviable / DEL = not aviable
			'DVD' => 'USE', 
			'DVR'  => 'DEL', 
			'DOCK' => 'DEL', 
			'BD' => 'USE',       
			'TV' => 'USE',       
			'SAT/CBL' => 'USE',
			'SAT' => 'DEL',			
			'MPLAY' => 'USE',    
			'BT' => 'USE',       
			'GAME' => 'USE',
			'HDRADIO' => 'DEL',		
			'AUX1' => 'USE',
			'AUX2' => 'USE',
 			'AUX3' => 'DEL',
			'AUX4' => 'DEL',
			'AUX5' => 'DEL',
			'AUX6' => 'DEL',
			'AUX7' => 'DEL',
			'AUXA' => 'DEL',
			'AUXB' => 'DEL',
			'AUXC' => 'DEL',
			'AUXD' => 'DEL',
			'V.AUX' => 'DEL',				
			'CD' => 'USE',          
			'PHONO' => 'USE',
			'TUNER' => 'USE',
			'FAVORITES' => 'USE',
			'IRADIO' => 'USE',
			'SIRIUSXM' => 'DEL',
			'PANDORA' => 'DEL',
			'SERVER' => 'USE',
			'FLICKR' => 'USE',
			'NET' => 'USE',
			'NET/USB'=> 'DEL',
			'LASTFM' => 'DEL',
			'USB/IPOD' => 'USE',
			'USB' => 'USE',
			'IPD' => 'USE',
			'IRP' => 'USE',
			'FVP' => 'USE',
			'SOURCE' => 'DEL',
		},	
	},
	'SLP' => {                  #sleep-Mode
		'10min'     => '010',
		'15min'     => '015',
		'30min'     => '030',
		'40min'     => '040',
		'50min'     => '050',
		'60min'     => '060',
		'70min'     => '070',
		'80min'     => '080',
		'90min'     => '090',
		'100min'    => '100',
		'110min'    => '110',
		'120min'    => '120',
		'off'    	=> 'OFF',
	},
	'STBY' => {                  #autoStandby-Mode
		'15min'     => '15M',
		'30min'     => '30M',
		'60min'     => '60M',
		'off'    	=> 'OFF',
	},
	'SV' => {  					#Video-Select
		'DVD'		=> 'DVD',
		'BD'		=> 'Blu-Ray',
		'TV'		=> 'TV',
		'SAT/CBL'	=> 'Sat/Cbl',
		'DVR' 		=> 'DVR',
		'DOCK' 		=> 'Dock',
		'MPLAY'		=> 'Mediaplayer',
		'GAME'		=> 'Game',
		'AUX1'		=> 'Aux1',
		'AUX2'		=> 'Aux2',
		'AUX3'		=> 'Aux3',
		'AUX4'		=> 'Aux4',
		'AUX5'		=> 'Aux5',
		'AUX6'		=> 'Aux6',
		'AUX7'		=> 'Aux7',
		'V.AUX'		=> 'V.Aux',
		'CD'		=> 'CD',
		'SOURCE'	=> 'Source',
		'ON'		=> 'on',
		'OFF'		=> 'off',
	},
	'SD' => {  			#DigitalSound-Select
		'AUTO'		=> 'auto',
		'HDMI'		=> 'hdmi',
		'DIGITAL'	=> 'digital',
		'ANALOG'	=> 'analog',
		'EXT.IN'	=> 'externalInput',
		'7.1IN'		=> '7.1input',
		'ARC'		=> 'ARCplaying',
		'NO'		=> 'noInput',
	},
	'SWITCH' => {
		"on"      => "off",
		"off"     => "on",
		"standby" => "on",
	},
	'SY' => { 					#System-Info
		'MO' => 'model',      	# AVR-X4100WEUR
		'MODTUN' => 'tuner',  	# EUR
	},
	'SIGNAL' => {
		'STEREO'      				=> 'PCM',
		'DOLBY'    					=> 'Dolby Digital',
		'DOLBY DIGITAL'    			=> 'Dolby Digital',
		'DOLBY D EX'    			=> 'Dolby Digital EX',
		'DOLBY HD'    				=> 'Dolby TrueHD',
		'DOLBY D+'    				=> 'Dolby Digital Plus',
		'DSD'      					=> 'DSD',
		'MULTI CH IN'      			=> 'PCM Multi',
		'DTS'      					=> 'DTS',
		'DTS HD'      				=> 'DTS-HD',
		'DTS EXPRESS'      			=> 'DTS Express',
		'DTS ES DSCRT6.1'      		=> 'DTS Dscrt 6.1',
		'DTS ES MTRX6.1'      		=> 'DTS Mtrx 6.1',
		'DOLBY ATMOS'    			=> 'Dolby Atmos',
		'AURO3D'    				=> 'Auro-3D',
		'AURO2DSURR'				=> 'Auro-2D',
	},
	'SOUND' => {
		'STEREO' => 'Stereo',
		'DIRECT' => 'Direct',
		'DSD DIRECT' => 'DSD Direct',
		'PURE DIRECT' => 'Pure Direct',
		'DSD PURE DIRECT' => 'DSD Pure Direct',
		'PURE DIRECT EXT' => 'Pure Direct Ext',
		'MCH STEREO' => 'Multichannel Stereo',
		'ALL ZONE STEREO' => 'All Zone Stereo',
		'AUDYSSEY DSX' => 'Audyssey DSX',
		'PL DSX' => 'PL DSX',
		'PL2 C DSX' => 'PL2 C DSX',
		'PL2 M DSX' => 'PL2 M DSX',
		'PL2 G DSX' => 'PL2 G DSX',
		'PL2X C DSX' => 'PL2X C DSX',
		'PL2X M DSX' => 'PL2X M DSX',
		'PL2X G DSX' => 'PL2X G DSX',
		'DOLBY AUDIO-DSUR' => 'Dolby_Audio_Surround',
		'DOLBY PL2 C' => 'Dolby PL2 C',
		'DOLBY PL2 M' => 'Dolby PL2 M',
		'DOLBY PL2 G' => 'Dolby PL2 G',
		'DOLBY PRO LOGIC' => 'Dolby Pro Logic',
		'DOLBY SURROUND' => 'Dolby Surround',
		'DOLBY ATMOS' => 'Dolby Atmos',
		'DOLBY AUDIO-DD' => 'Dolby_Audio_Dolby-Digital',
		'DOLBY AUDIO-DD+DSUR' => 'Dolby_Audio_Digital-Surround',
		'DOLBY AUDIO-DD+NEURAL:X' => 'Dolby_Audio_Digital-Neural:X',
		'DOLBY DIGITAL' => 'Dolby Digital',
		'DOLBY PL2 C' => 'Dolby PL2 C',
		'DOLBY PL2 M' => 'Dolby PL2 M',
		'DOLBY PL2 G' => 'Dolby PL2 G',
		'DOLBY PL2X C' => 'Dolby PL2X C',
		'DOLBY PL2X M' => 'Dolby PL2X M',
		'DOLBY PL2X G' => 'Dolby PL2X G',
		'DOLBY PL2Z H' => 'Dolby PL2Z H',
		'DOLBY D EX' => 'Dolby Digital EX',
		'DOLBY D+PL2X C' => 'Dolby Digital+PL2X C',
		'DOLBY D+PL2X M' => 'Dolby Digital+PL2X M',
		'DOLBY D+PL2Z H' => 'Dolby Digital+PL2Z H',
		'DOLBY D+DS' => 'Dolby Digital+DS',
		'DOLBY D+NEO:X C' => 'Dolby Digital+Neo:X C',
		'DOLBY D+NEO:X M' => 'Dolby Digital+Neo:X M',
		'DOLBY D+NEO:X G' => 'Dolby Digital+Neo:X G',
		'DOLBY D+' => 'Dolby Digital Plus',
		'DOLBY D+ +EX' => 'Dolby Digital Plus+PL2X C',
		'DOLBY D+ +PL2X C' => 'Dolby Digital Plus+PL2X C',
		'DOLBY D+ +PL2X M' => 'Dolby Digital Plus+PL2X M',
		'DOLBY D+ +PL2Z H' => 'Dolby Digital Plus+PL2Z H',
		'DOLBY D+ +PLZ H' => 'Dolby Digital Plus+PLZ H',
		'DOLBY D+ +DS' => 'Dolby Digital+ +DS',
		'DOLBY D+ +NEO:X C' => 'Dolby Digital Plus+Neo:X C',
		'DOLBY D+ +NEO:X M' => 'Dolby Digital Plus+Neo:X M',
		'DOLBY D+ +NEO:X G' => 'Dolby Digital Plus+Neo:X G',
		'DOLBY HD' => 'Dolby HD',
		'DOLBY HD+EX' => 'Dolby HD+EX',
		'DOLBY HD+PL2X C' => 'Dolby HD+PL2X C',
		'DOLBY HD+PL2X M' => 'Dolby HD+PL2X M',
		'DOLBY HD+PL2Z H' => 'Dolby HD+PL2Z H',
		'DOLBY HD+DS' => 'Dolby HD+DS',
		'DOLBY HD+NEO:X C' => 'Dolby HD+Neo:X C',
		'DOLBY HD+NEO:X M' => 'Dolby HD+Neo:X M',
		'DOLBY HD+NEO:X G' => 'Dolby HD+Neo:X G',
		'DTS SURROUND' => 'DTS Surround',
		'DTS ES DSCRT6.1' => 'DTS ES Dscrt 6.1',
		'DTS ES MTRX6.1' => 'DTS ES Mtrx 6.1',
		'DTS+PL2X C' => 'DTS+PL2X C',
		'DTS+PL2X M' => 'DTS+PL2X M',
		'DTS+PL2Z H' => 'DTS+PL2Z H',
		'DTS+DS' => 'DTS+DS',
		'DTS96/24' => 'DTS 96/24',
		'DTS96 ES MTRX' => 'DTS 96 ES MTRX',		
		'DTS+NEO:6' => 'DTS+Neo:6',		
		'DTS NEO:6 C' => 'DTS Neo:6 C',
		'DTS NEO:X C' => 'DTS Neo:X C',
		'DTS+NEO:X C' => 'DTS+Neo:X C',
		'DTS NEO:6 M' => 'DTS Neo:6 M',		
		'DTS NEO:X M' => 'DTS Neo:X M',
		'DTS+NEO:X M' => 'DTS+Neo:X M',		
		'DTS+NEO:X G' => 'DTS+Neo:X G',
		'DTS+NEO:X G' => 'DTS+Neo:X G',		
		'DTS HD' => 'DTS-HD',
		'DTS HD TR' => 'DTS-HD TR',
		'DTS HD MSTR' => 'DTS-HD Mstr',
		'DTS HD+PL2X C' => 'DTS-HD+PL2X C',
		'DTS HD+PL2X M' => 'DTS-HD+PL2X M',
		'DTS HD+PL2Z H' => 'DTS-HD+PL2Z H',
		'DTS HD+NEO:6' => 'DTS-HD+Neo:6',
		'DTS HD+DS' => 'DTS-HD+DS',
		'DTS HD+NEO:X C' => 'DTS-HD+Neo:X C',
		'DTS HD+NEO:X M' => 'DTS-HD+Neo:X M',
		'DTS HD+NEO:X G' => 'DTS-HD+Neo:X G',
		'DTS EXPRESS' => 'DTS Express',
		'DTS ES 8CH DSCRT' => 'DTS ES 8Ch Dscrt',
		'AURO3D' => 'Auro-3D',
		'AURO2DSURR' => 'Auro-2D Surround',
		'MPEG2 AAC' => 'MPEG2 AAC',
		'AAC+DOLBY EX' => 'AAC+Dolby EX',
		'AAC+PL2X C' => 'AAC+PL2X C',
		'AAC+PL2X M' => 'AAC+PL2X M',
		'AAC+PL2Z H' => 'AAC++PL2Z H',
		'AAC+DS' => 'AAC+DS',
		'AAC+NEO:X C' => 'AAC+Neo:X C',
		'AAC+NEO:X M' => 'AAC+Neo:X M',
		'AAC+NEO:X G' => 'AAC+Neo:X G',
		'MULTI CH IN' => 'Multi Ch In',
		'M CH IN+DOLBY EX' => 'Multi Ch In',
		'M CH IN+PL2X C' => 'Multi Ch In+PL2X C',
		'M CH IN+PL2X M' => 'Multi Ch In+PL2X M',
		'M CH IN+PL2Z H' => 'Multi Ch In+PL2Z H',
		'M CH IN+DS' => 'Multi Ch In+DS',
		'MULTI CH IN 7.1' => 'Multi Ch In 7.1',
		'M CH IN+NEO:X C' => 'Multi Ch In+Neo:X C',
		'M CH IN+NEO:X M' => 'Multi Ch In+Neo:X M',
		'M CH IN+NEO:X G' => 'Multi Ch In+Neo:X G',
		'NEURAL:X'	=> 'Neural:X',
		'NEO:6 C DSX' => 'Neo:6 C DSX',
		'NEO:6 M DSX' => 'Neo:6 M DSX',
		'7.1IN' => 'Multi Ch In 7.1',
		'VIRTUAL' => 'Virtual',
	},
	'TF' => {
		'AN' => {
			'up' => 'UP',
			'down' => 'DOWN',
			'status' => '?',
			'RDS' => 'NAME?',
		},
		'HD' => {
			'up' => 'UP',
			'down' => 'DOWN',
			'status' => '?',
		},
	},
	'TP' => {
		'AN' => {
			'up' => 'UP',
			'down' => 'DOWN',
			'status' => '?',
			'memory' => 'MEM',
		},
		'HD' => {
			'up' => 'UP',
			'down' => 'DOWN',
			'status' => '?',
			'memory' => 'MEM',
		},
	},
	'TM' => {
		'AN' => {
			'AM' => 'AM',
			'FM' => 'FM',
			'auto' => 'AUTO',
			'manual' => 'MANUAL',
		},
		'HD' => {
			'AM' => 'AM',
			'FM' => 'FM',
			'status' => '?',
			'autoHD' => 'AUTOHD',
			'auto' => 'AUTO',
			'manual' => 'MANUAL',
			'analogAuto' => 'ANAAUTO',
			'analogManual' => 'ANMANUAL',
		},
	},
	'TOGGLE' => {
		"on"      => "auto",
		"off"     => "on",
		"auto" => "off",
	},
	'VS' => {
		'ASP' => {
			'ASP' => 'aspectRatio',
			'NRM' => '4:3',
			'FUL' => '16:9',
		},
		'MONI' => {
			'MONI' => 'monitorOut',
			'AUTO' => 'auto',
			'1' => '1',
			'2' => '2',
		},
		'SC' => {
			'SC' => 'resolution',
			'AUTO' => 'auto',
			'48P' => '480p/576p',
			'10I' => '1080i',
			'48P' => '480p/576p',
			'72P' => '720p',
			'10P' => '1080p',
			'10P24' => '1080p:24Hz',
			'4K' => '4K',
			'4KF' => '4K(60/50)',
		},
		'SCH' => {
			'SCH' => 'resolutionHDMI',
			'AUTO' => 'auto',
			'48P' => '480p/576p',
			'10I' => '1080i',
			'48P' => '480p/576p',
			'72P' => '720p',
			'10P' => '1080p',
			'10P24' => '1080p:24Hz',
			'4K' => '4K',
			'4KF' => '4K(60/50)',
		},
		'AUDIO' => { # HDMI AUDIO Output
			'AUDIO' => 'audioOutHDMI',
			'AMP' => 'amplifier',
			'TV' => 'tv',
		},
		'VPM' => { #Video Processing  Mode
			'VPM' => 'videoProcessingMode',
			'AUTO' => 'auto',
			'GAME' => 'Game',
			'MOVI' => 'Movie',
		},
		'VST' => 'verticalStretch',
	},
};

my $DENON_db_ceol = {
	'MN' => {      			#System-Remote:
		'up' => 'CUP',
		'down' => 'CDN',
		'left' => 'CLT',
		'right' => 'CRT',
		'enter' => 'ENT',
		'favorite_on' => 'FAV ON',
		'favorite_off' => 'FAV OFF',
	},
};

sub
DENON_GetValue($$;$;$;$) {	
	my ( $status, $command, $inf1, $inf2, $inf3) = @_;
	my $name = "Denon";
	
	my $info1 = (defined($inf1) ? $inf1 : "na");
	my $info2 = (defined($inf2) ? $inf2 : "na");
	my $info3 = (defined($inf3) ? $inf3 : "na");

    if (  $info1 eq "na" && $info2 eq "na" && $info3 eq "na"
        && defined( $DENON_db->{$status}{$command} ) )
    {
        my $value = eval { $DENON_db->{$status}{$command} };
		$value = $@ ? "unknown" : $value;
		return $value; 
    }
    elsif ( defined($DENON_db->{$status}{$command}{$info1} ) && $info2 eq "na" && $info3 eq "na" ) {
        my $value =  eval { $DENON_db->{$status}{$command}{$info1} };
		$value = $@ ? "unknown" : $value;
		return $value;
    }
	elsif ( defined($DENON_db->{$status}{$command}{$info1}{$info2}) && $info3 eq "na" ) {
        my $value = eval { $DENON_db->{$status}{$command}{$info1}{$info2} };
		$value = $@ ? "unknown" : $value;
		return $value;
    }
	elsif ( defined($DENON_db->{$status}{$command}{$info1}{$info2}{$info3}) ) {
        my $value = eval { $DENON_db->{$status}{$command}{$info1}{$info2}{$info3} };
		$value = $@ ? "unknown" : $value;
		return $value;
    }
    else {
        return "unknown";
    }
}

sub
DENON_SetValue($$$;$;$;$) {
	my ( $value, $status, $command, $inf1, $inf2, $inf3) = @_;
	
	my $info1 = (defined($inf1) ? $inf1 : "na");
	my $info2 = (defined($inf2) ? $inf2 : "na");
	my $info3 = (defined($inf3) ? $inf3 : "na");
	
	if (  $info1 eq "na" && $info2 eq "na" && $info3 eq "na"
        && defined( $DENON_db->{$status}{$command} ) )
    {
        $DENON_db->{$status}{$command} = $value;
    }
    elsif ( defined($DENON_db->{$status}{$command}{$info1} ) && $info2 eq "na" && $info3 eq "na"  ) {
        $DENON_db->{$status}{$command}{$info1} = $value;
    }
	elsif ( defined($DENON_db->{$status}{$command}{$info1}{$info2}) && $info3 eq "na" ) {
        $DENON_db->{$status}{$command}{$info1}{$info2} = $value;
    }
	elsif ( defined($DENON_db->{$status}{$command}{$info1}{$info2}{$info3}) ) {
       $DENON_db->{$status}{$command}{$info1}{$info2}{$info3} = $value;
    }
 
    return undef;	
}

sub
DENON_GetKey($$;$) {
	my ( $status, $command, $info) = @_;

	if ( defined($status) && defined($command) && !defined($info))
    {
		my @keys = keys %{$DENON_db->{$status}};
        my @values = values %{$DENON_db->{$status}};
        while (@keys) {
            my $fhemCommand = pop(@keys);   
			my $denonCommand = pop(@values);
			if ($command eq $denonCommand)
			{
				return $fhemCommand;
			}
        }
	}
	if ( defined($status) && defined($command) && defined($info))
    {
		my @keys = keys %{$DENON_db->{$status}{$command}};
        my @values = values %{$DENON_db->{$status}{$command}};
        while (@keys) {
            my $fhemCommand = pop(@keys);   
			my $denonCommand = pop(@values);
			if ($info eq $denonCommand)
			{
				return $fhemCommand;
			}
        }
	}
	else {
        return undef;
    }
}

sub DENON_AVR_RequestDeviceinfo {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $url = "http://$hash->{IP}/goform/Deviceinfo.xml";
    Log3 $name, 4, "DENON_AVR ($name) - requesting $url";
    my $param = {
                    url        => "$url",
                    timeout    => 5,
                    hash       => $hash,
                    method     => "GET",
                    header     => "User-Agent: FHEM\r\nAccept: application/xml",
                    callback   => \&DENON_AVR_ParseDeviceinfoResponse
                };

    HttpUtils_NonblockingGet($param);
}

sub DENON_AVR_ParseDeviceinfoResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $return;

  if($err ne "") {
      Log3 $name, 0, "DENON_AVR ($name) - Error while requesting ".$param->{url}." - $err";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, 'httpState', 'ERROR', 0);
      readingsBulkUpdate($hash, 'httpError', $err, 0);
      readingsEndUpdate($hash, 0);

      DENON_AVR_RequestProductTypeName($hash);
  } elsif($data ne "") {
      readingsDelete($hash, 'httpState');
      readingsDelete($hash, 'httpError');

      Log3 $name, 5, "DENON_AVR ($name) - Deviceinfo.xml\n$data";
      my $ref = XMLin($data, KeyAttr => { }, ForceArray => [ ]);

      my $codes = {
        '0' => 'Denon',
        '1' => 'Marantz'
      };
      my $brandCode = $ref->{BrandCode};

      $hash->{model} = $codes->{$brandCode} . ' ' . $ref->{ModelName};
  }
}

sub DENON_AVR_RequestProductTypeName {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $url = "http://$hash->{IP}/ajax/get_config?type=25";
    Log3 $name, 4, "DENON_AVR ($name) - requesting $url";
    my $param = {
                    url        => "$url",
                    timeout    => 5,
                    hash       => $hash,
                    method     => "GET",
                    header     => "User-Agent: FHEM\r\nAccept: application/xml",
                    callback   => \&DENON_AVR_ParseProductTypeName
                };

    HttpUtils_NonblockingGet($param);
}

sub DENON_AVR_ParseProductTypeName {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $return;

  if($err ne "") {
      Log3 $name, 0, "DENON_AVR ($name) - Error while requesting ".$param->{url}." - $err";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, 'httpState', 'ERROR', 0);
      readingsBulkUpdate($hash, 'httpError', $err, 0);
      readingsEndUpdate($hash, 0);
  } elsif($data ne "") {
      readingsDelete($hash, 'httpState');
      readingsDelete($hash, 'httpError');

      my $productTypeName = $data =~ s/<productTypeName>|<\/productTypeName>//rg;
      Log3 $name, 4, "DENON_AVR ($name) - productTypeName: $productTypeName";

      $hash->{model} = $productTypeName;
  }
}

###################################
sub
DENON_AVR_Initialize($)
{
	my ($hash) = @_;

	Log 5, "DENON_AVR_Initialize: Entering";
		
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	
# Provider
	$hash->{ReadFn}	    = "DENON_AVR_Read";
	$hash->{WriteFn}    = "DENON_AVR_Write";
	$hash->{ReadyFn}    = "DENON_AVR_Ready";
	
# Device	
	$hash->{DefFn}		= "DENON_AVR_Define";
	$hash->{UndefFn}	= "DENON_AVR_Undefine";
	$hash->{GetFn}		= "DENON_AVR_Get";
	$hash->{SetFn}		= "DENON_AVR_Set";
	$hash->{NotifyFn}   = "DENON_AVR_Notify";
	$hash->{ShutdownFn} = "DENON_AVR_Shutdown";
	
	$hash->{AttrList}  = "brand:Denon,Marantz disable:0,1 do_not_notify:1,0 connectionCheck:off,30,45,60,75,90,105,120,240,300 dlnaName favorites maxFavorites maxPreset inputs playTime:off,1,2,3,4,5,10,15,20,30,40,50,60 sleep timeout:1,2,3,4,5 presetMode:numeric,alphanumeric type:AVR,Ceol unit:off,on ".$readingFnAttributes;
	
	$data{RC_makenotify}{DENON_AVR} = "DENON_AVR_RCmakenotify";
	$data{RC_layout}{DENON_AVR_RC}  = "DENON_AVR_RClayout";
}

###################################
sub
DENON_AVR_Define($$)
{
	my ($hash, $def) = @_;
	
	Log 5, "DENON_AVR_Define($def) called.";

	my @a = split("[ \t][ \t]*", $def);
	
	if (@a != 3)
	{
		my $msg = "wrong syntax: define <name> DENON_AVR <ip-or-hostname>";
		Log 2, $msg;

		return $msg;
	}
	
        RemoveInternalTimer($hash);
	DevIo_CloseDev($hash);
	
	my $name = $a[0]; 
	
	$hash->{Clients} = ":DENON_AVR_ZONE:";
	$hash->{TIMEOUT} = AttrVal( $name, "timeout", "3" );
	$hash->{DeviceName} = $a[2];
	
	$hash->{helper}{isPlaying} = 0;
	$hash->{helper}{isPause} = 0;
	$hash->{helper}{playTimeCheck} = 0;
		
	$modules{DENON_AVR_ZONE}{defptr}{$name}{1} = $hash;
	
	InternalTimer(gettimeofday() + 5, "DENON_AVR_UpdateConfig", $hash, 0);
	
	unless (exists($attr{$name}{webCmd})){
		$attr{$name}{webCmd} = 'volume:muteT:input:surroundMode';
	}
	unless (exists($attr{$name}{suppressReading})){
		$attr{$name}{suppressReading} = 'HASH.*';
	}
	unless ( exists( $attr{$name}{cmdIcon} ) ) {
		$attr{$name}{cmdIcon} = 'muteT:rc_MUTE';
	}
	unless ( exists( $attr{$name}{devStateIcon} ) ) {
		$attr{$name}{devStateIcon} = 'on:rc_GREEN:main_off main_off:rc_YELLOW:main_on off:rc_STOP:main_on absent:rc_RED:main_on muted:rc_MUTE@green:muteT playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play disconnected:rc_RED';
	}
	unless (exists($attr{$name}{stateFormat})){
		$attr{$name}{stateFormat} = 'stateAV';
	}
	
		
	# connect using serial connection (old blocking style)
	if ($hash->{DeviceName} =~ /^([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}) (.+@.+)/)
	{
		my $ret = DevIo_OpenDev($hash, 0, "DENON_AVR_DoInit");
		return $ret;
	}
	# connect using TCP connection (non-blocking style)
	else
	{
                $hash->{IP} = $a[2];
                use XML::Simple qw(:strict);
                DENON_AVR_RequestDeviceinfo($hash);

		$hash->{DeviceName} = $hash->{DeviceName} . ":23"
			if ( $hash->{DeviceName} !~ m/^(.+):([0-9]+)$/ );
		  
		DevIo_OpenDev(
           $hash, 0,
           "DENON_AVR_DoInit",
           sub() {
                my ( $hash, $err ) = @_;
               Log3 $name, 4, "DENON_AVR $name: $err." if ($err);
           }
       );
	}
	
}

#####################################
sub
DENON_AVR_DoInit($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
  	
	if ( lc( ReadingsVal( $name, "state", "?" ) ) eq "opened" ) {
        DoTrigger( $name, "CONNECTED" );
		Log3 $name, 5, "DENON_AVR_DoInit $name: CONNECTED";
    }
    else {
        DoTrigger( $name, "DISCONNECTED" );
		Log3 $name, 5, "DENON_AVR_DoInit $name: DISCONNECTED";
    }
}

sub
DENON_AVR_Notify($$) {
    my ( $hash, $dev ) = @_;
	my $name         = $hash->{NAME};
    my $devName      = $dev->{NAME};
	
	if ( $devName eq "global" ) {
		foreach my $change ( @{ $dev->{CHANGED} } ) {
			if ($change =~ /^(.+) (.+) (.+) (.+)/) {
				if ($1 eq "ATTR")
				{
					if ($2 eq $name)
					{
						if ($3 eq "connectionCheck")
						{
							if ($4 ne "off")
							{
								RemoveInternalTimer($hash, "DENON_AVR_ConnectionCheck");
								InternalTimer(gettimeofday() + $4, "DENON_AVR_ConnectionCheck", $hash, 0);	
								Log3 $name, 5, "DENON_AVR $name: changing attribut connectionCheck to <$4> seconds.";
							}
							else
							{
								RemoveInternalTimer($hash, "DENON_AVR_ConnectionCheck");
								Log3 $name, 5, "DENON_AVR $name: changing attribut connectionCheck to off.";
							}
						}
						elsif ($3 eq "brand")
						{
							Log3 $name, 5, "DENON_AVR $name: changing attribut brand to <$4>.";
						}
						elsif ($3 eq "disable")
						{	
							if ($4 eq "1")
							{
								RemoveInternalTimer($hash);
								DevIo_CloseDev($hash);
								
								readingsBeginUpdate($hash);
								readingsBulkUpdate($hash, "power", "off");
								readingsBulkUpdate($hash, "presence", "absent");
								readingsBulkUpdate($hash, "state", "disconnected");
								readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
								readingsEndUpdate($hash, 1);
			
								if ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{2}) || defined($modules{DENON_AVR_ZONE}{defptr}{$name}{3}))
								{
									Log3 $name, 5, "DENON_AVR $name: Dispatching state change to slaves";
									Dispatch( $hash, "presence absent", undef);
									Dispatch( $hash, "power off", undef);
									Dispatch( $hash, "state disconnected", undef);
									Dispatch( $hash, "stateAV ".DENON_AVR_GetStateAV($hash), undef);
								}
							}
							else
							{
								DevIo_OpenDev($hash, 0, "DENON_AVR_DoInit");
							}
							Log3 $name, 5, "DENON_AVR $name: changing attribut disable to <$4>.";
						}
						elsif ($3 eq "playTime")
						{
							RemoveInternalTimer($hash, "DENON_AVR_PlaytimeCheck");	
							if ($4 ne "off")
							{
								RemoveInternalTimer($hash, "DENON_AVR_PlaytimeCheck");	
								InternalTimer(gettimeofday() + $4, "DENON_AVR_PlaytimeCheck", $hash, 0);
							}
							Log3 $name, 5, "DENON_AVR $name: changing attribut playTime to <$4>.";
						}
						elsif ($3 eq "maxFavorites")
						{	
							Log3 $name, 5, "DENON_AVR $name: changing attribut maxFavorites to <$4>.";
						}
						elsif ($3 eq "maxPreset")
						{	
							Log3 $name, 5, "DENON_AVR $name: changing attribut maxPreset to <$4>.";
						}
						elsif ($3 eq "presetMode")
						{	
							Log3 $name, 5, "DENON_AVR $name: changing attribut presetMode to <$4>.";
						}
						elsif ($3 eq "timeout")
						{	
							$hash->{TIMEOUT} = $4;
							Log3 $name, 5, "DENON_AVR $name: changing attribut timeout to <$4>.";
						}
						elsif ($3 eq "type")
						{	
							if ($4 eq "AVR")
							{
								$attr{$name}{devStateIcon} = 'on:rc_GREEN:main_off main_off:rc_YELLOW:main_on off:rc_STOP:main_on absent:rc_RED:main_on muted:rc_MUTE@green:muteT playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play disconnected:rc_RED';
							}
							elsif ($4 eq "Ceol")
							{
								$attr{$name}{devStateIcon} = 'on:rc_GREEN:off off:rc_YELLOW:on off:rc_STOP:on absent:rc_RED:on muted:rc_MUTE@green:muteT playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play disconnected:rc_RED';
							}
							
							Log3 $name, 5, "DENON_AVR $name: changing attribut type to <$4>.";
						}
					}
				}
			}
			elsif ($change =~ /^(.+) (.+) (.+)/)
			{
				if ($1 eq "DELETEATTR")
				{
					if ($2 eq $name)
					{
						if ($3 eq "connectionCheck")
						{
							RemoveInternalTimer($hash, "DENON_AVR_ConnectionCheck");
							InternalTimer(gettimeofday() + 60, "DENON_AVR_ConnectionCheck", $hash, 0);	
							Log3 $name, 5, "DENON_AVR $name: changing attribut connectionCheck to <60> seconds.";
						}
						elsif ($3 eq "brand")
						{
							Log3 $name, 5, "DENON_AVR $name: changing attribut brand to <Denon>.";
						}
						elsif ($3 eq "disable")
						{
							InternalTimer(gettimeofday() + 5, "DENON_AVR_UpdateConfig", $hash, 0);
						}
						elsif ($3 eq "timeout")
						{	
							$hash->{TIMEOUT} = 3;
							Log3 $name, 5, "DENON_AVR $name: deleting attribut timeout.";
						}
						elsif ($3 eq "dlnaName")
						{	
							Log3 $name, 5, "DENON_AVR $name: deleting attribut dlnaName.";
						}
						elsif ($3 eq "type")
						{
							$attr{$name}{devStateIcon} = 'on:rc_GREEN:main_off main_off:rc_YELLOW:main_on off:rc_STOP:main_on absent:rc_RED:main_on muted:rc_MUTE@green:muteT playing:rc_PLAY@green:pause paused:rc_PAUSE@green:play disconnected:rc_RED';
							Log3 $name, 5, "DENON_AVR $name: deleting attribut type.";
						}
					}
				}
			}
		}
	}
	elsif ( $devName ne $name ) {
        return;
    }
	
	foreach my $change ( @{ $dev->{CHANGED} } ) {
		
		readingsBeginUpdate($hash);
		
		if ($change eq "CONNECTED")
		{
			Log3 $hash, 5, "DENON_AVR " . $name . ": processing change $change";
			InternalTimer(gettimeofday() + 5, "DENON_AVR_UpdateConfig", $hash, 0);
		}
		elsif ($change eq "DISCONNECTED")
		{
			RemoveInternalTimer($hash);
			
			readingsBulkUpdate($hash, "power", "off");
			readingsBulkUpdate($hash, "presence", "absent");
			readingsBulkUpdate($hash, "state", "disconnected");
			readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
			
			if ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{2}) || defined($modules{DENON_AVR_ZONE}{defptr}{$name}{3}))
			{
				Log3 $name, 5, "DENON_AVR $name: Dispatching state change to slaves";
				Dispatch( $hash, "presence absent", undef);
				Dispatch( $hash, "power off", undef);
				Dispatch( $hash, "state disconnected", undef);
				Dispatch( $hash, "stateAV ".DENON_AVR_GetStateAV($hash), undef);
			}
		}
		elsif ($change =~ /^(.+): (.+)/) {
		
			if ($1 eq "currentMedia")
			{
				my $status = defined($hash->{helper}{playTimeCheck}) ? $hash->{helper}{playTimeCheck} : 0;
				if($status == 0)
				{
					readingsBulkUpdate($hash, "playStatus", "stopped");
				}
			}
			if ($1 eq "currentPlaytime")
			{
				my $status = ReadingsVal($name, "playStatus", "stopped");
				if ($2 eq "-")
				{
					readingsBulkUpdate($hash, "playStatus", "stopped") if($status ne "stopped");
					my $cover = "http://" . $hash->{helper}{deviceIP} . "/img/album%20art_S.png" . "?" . DENON_AVR_GetTimeStamp(gettimeofday());
					readingsBulkUpdate($hash, "currentCover", $cover);
				}
				elsif ($hash->{helper}{isPause} == 1)
				{
					readingsBulkUpdate($hash, "playStatus", "paused") if($status ne "paused");
				}
				else
				{
					readingsBulkUpdate($hash, "playStatus", "playing") if($status ne "playing");
				}
			}
			elsif ($1 eq "mute")
			{
				readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
			}
			elsif ($1 eq "playStatus")
			{
				if ($2 eq "playing")
				{
					$hash->{helper}{isPlaying} = 1;
					$hash->{helper}{isPause} = 0;
					$hash->{helper}{playTimeCheck} = 1;				
				}
				elsif ($1 eq "paused")
				{
					$hash->{helper}{isPlaying} = 1;
					$hash->{helper}{isPause} = 1;
					$hash->{helper}{playTimeCheck} = 1;
				}
				elsif ($1 eq "stopped")
				{
					$hash->{helper}{isPlaying} = 0;
					$hash->{helper}{isPause} = 0;
					$hash->{helper}{playTimeCheck} = 0;
				}
						
				readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
			}
			elsif ($1 eq "power")
			{
				readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
			}
			elsif ($1 eq "state")
			{
				readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
			}
		}
	}
	readingsEndUpdate($hash, 1);
	
	return;
}

#####################################
sub
DENON_AVR_Ready($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
	
    if ( lc(ReadingsVal( $name, "state", "disconnected" )) eq "disconnected" ) {
		
		DevIo_OpenDev(
            $hash, 1, undef,
            sub() {
               my ( $hash, $err ) = @_;
                Log3 $name, 4, "DENON_AVR $name: $err." if ($err);
            }	
        );
        return;	
    }

    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags );
    if ($po) {
        ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
    }
    return ( $InBytes && $InBytes > 0 );
}

###################################
sub
DENON_AVR_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $state = ReadingsVal( $name, "power", "off" );
	my $buf = '';
	my $zone = 0;
	my $return;
	
	if(defined($hash->{helper}{PARTIAL}) && $hash->{helper}{PARTIAL}) {
	$buf = $hash->{helper}{PARTIAL} . DevIo_SimpleRead($hash);
	}	else {
		$buf = DevIo_SimpleRead($hash);
	}
	return if(!defined($buf));
	
	my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
	RemoveInternalTimer($hash, "DENON_AVR_ConnectionCheck");
	if ($checkInterval ne "off" ) {
		my $next = gettimeofday() + $checkInterval;
		$hash->{helper}{nextConnectionCheck} = $next;
		InternalTimer($next, "DENON_AVR_ConnectionCheck", $hash, 0);
	}
	
	Log3 $name, 5, "DENON_AVR $name: read.";
	
	readingsBeginUpdate($hash);
	while ($buf =~ m/\r/) 
	{
		my $rmsg;
		($rmsg, $buf) = split("\r", $buf, 2);
		$rmsg =~ s/^\s+|\s+$//g;
		$rmsg =~ s/\s+/ /g;
		
		if ($rmsg =~ /^Z2|Z3|Z4/) {
			if ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{2}) && $rmsg =~ /^Z2/ )
			{
				Log3 $hash, 4, "DENON_AVR $name dispatch: this is for zone 2 <$rmsg>";
				Dispatch( $hash, $rmsg, undef );
			}
			elsif ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{3}) && $rmsg =~ /^Z3/ )
			{
				Log3 $hash, 4, "DENON_AVR $name dispatch: this is for zone 3 <$rmsg>";
				Dispatch( $hash, $rmsg, undef );
			}
			elsif ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{4}) && $rmsg =~ /^Z4/ )
			{
				Log3 $hash, 4, "DENON_AVR $name dispatch: this is for zone 4 <$rmsg>";
				Dispatch( $hash, $rmsg, undef );
			}
			
			if ($rmsg =~ /(Z[2-4])(ON$|OFF$)/) {
			
				$return = DENON_AVR_Parse($hash, $rmsg) if($rmsg);
				
				Log3 $hash, 4, "DENON_AVR zone $1: parsing <$rmsg> to <$return>.";
			}
			readingsEndUpdate($hash, 1);
			return;
		}
		
		$return = DENON_AVR_Parse($hash, $rmsg) if($rmsg);
		Log3 $name, 4, "DENON_AVR $name: parsing <$rmsg> to <$return>." if($rmsg);
	}
	
	readingsEndUpdate($hash, 1);
	$hash->{helper}{PARTIAL} = $buf;
}

####################################
sub
DENON_AVR_Write($$;$)
{
	my ($hash, $msg, $event) = @_;	
	my $name = $hash->{NAME};
	
	Log3 $name, 4, "DENON_AVR $name: SimpleWrite $msg <$event>.";
	
	$msg = $msg."\r";
	
	DevIo_SimpleWrite($hash, $msg, 0);
			
	# do connection check latest after TIMEOUT
    my $next = gettimeofday() + $hash->{TIMEOUT};
    if ( !defined( $hash->{helper}{nextConnectionCheck} )
        || $hash->{helper}{nextConnectionCheck} > $next )
    {
        $hash->{helper}{nextConnectionCheck} = $next;
        RemoveInternalTimer($hash, "DENON_AVR_ConnectionCheck");
        InternalTimer( $next, "DENON_AVR_ConnectionCheck", $hash, 0 );
    }
}

###################################
sub
DENON_AVR_Parse(@)
{
	my ($hash, $msg) = @_;
	my $name = $hash->{NAME};
	my $deviceIP = $hash->{DeviceName};
	$deviceIP =~ /^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|[a-zA-Z0-9_-]+\.local):\d+$/;
	$hash->{helper}{deviceIP} = $1;
	my $percent = AttrVal($name, "unit", "off") eq "on" ? " %" : "";
	my $dezibel = AttrVal($name, "unit", "off") eq "on" ? " dB" : "";
	my $return = "unknown";

	#Power
	if ($msg =~ /^PW(.+)/)
	{
		my $power = lc($1);
		if ($power eq "standby")
		{
			$power = "off";
		}
		readingsBulkUpdate($hash, "power", $power);
		readingsBulkUpdate($hash, "state", $power);
		DENON_AVR_GetStateAV($hash);

		$return = $power;
	}
	#Channel-Level
	elsif ($msg =~ /^SSLEV([A-Z2]+) (.+)/){
		my $channel = DENON_GetValue('SSLEV', $1);
		my $volume = $2;
		if (length($volume) == 2)
		{
			$volume = $volume."0";
		}
		readingsBulkUpdate($hash, "Level-".$channel, ($volume / 10 - 50).$dezibel) if($channel ne "unknown");
		$return = "level".$channel." ".($volume / 10 - 50);
	}
	#digitalInput
	elsif ($msg =~ /^DC(.+)/)
	{
		my $digitalInput = DENON_GetValue('DC', $1);
		readingsBulkUpdate($hash, "digitalInput", $digitalInput) if($digitalInput ne "unknown");
		$return = "digitalInput ".$digitalInput;
	}
	#favorite (only older models)
	elsif ($msg =~ /^ZMFAVORITE(.+)/)
	{
		readingsBulkUpdate($hash, "favorite", $1);
		$return = "favorite ".$1;
	}
	#Mute
	elsif ($msg =~ /^MU(.+)/)
	{
		readingsBulkUpdate($hash, "mute", lc($1));
		$return = lc($1);
	}
  	#Maximal Volume
    	elsif ($msg =~ /^MVMAX(.+)/)
	{
		readingsBulkUpdate($hash, "volumeMax", $1.$percent);
		$return = "volumeMax ".$1;
	}
	elsif ($msg =~ /^SSVCTZMALIM (.+)([0-9]{2})/)          #/^0*([0-9]*)/;     ^([A-Z]{3}) (.+)/
	{
		readingsBulkUpdate($hash, "Volume-Max", $2.$percent);
		$return = "Volume-Max".$2;
	}
		#Einschaltlautstärke
	elsif ($msg =~ /^SSVCTZMAPON (.+)/)
	{
				
				my $mutelevel = $1;
					
				if($1 eq 'LAS')
				{
					readingsBulkUpdate($hash, "Volume-Startup", "last") if($mutelevel ne "unknown");
					$return = "Volume-Startup"."$1";
			
				}
				elsif($1 eq 'MUT')
				{
					readingsBulkUpdate($hash, "Volume-Startup", "mute") if($mutelevel ne "unknown");
					$return = "Volume-Startup"."$1";
			
				}
				else
				{
					if (length($mutelevel) == 2)
					{
						$mutelevel = $mutelevel."";
						
				readingsBulkUpdate($hash, "Volume-Startup", $mutelevel) if($mutelevel ne "unknown");
				$return = "Volume-Startup".$mutelevel;
			}
			} 
			}
	#Volume
	elsif ($msg =~ /^MV(.+)/)
	{
		my $volume = $1;
		if (length($volume) == 2)
		{
			$volume = $volume."0";
		}
		readingsBulkUpdate($hash, "volumeStraight", ($volume / 10 - 80).$percent);
		readingsBulkUpdate($hash, "volume", ($volume / 10).$dezibel);
		$return = "volume/volumeStraight ".($volume / 10)."/".($volume / 10 - 80);
		$hash->{helper}{volume} = $volume / 10;
	}
	#Sound Parameter
	elsif ($msg =~ /^PS(.+)/)
	{
		my $parameter = $1;
		if($parameter =~ /^(TONE CTRL) (.+)/)
		{	
			my $status = DENON_GetValue('PS', $1);
			readingsBulkUpdate($hash, $status, lc($2)) if($status ne "unknown");
			$return = $status." ".lc($2);
		}
		elsif($parameter =~ /^([A-Z]{3}) (.+)/)
		{
			if($2 eq 'ON' || $2 eq 'OFF')
			{
				my $status = DENON_GetValue('PS', $1);
				readingsBulkUpdate($hash, $status, lc($2)) if($status ne "unknown");
				$return = $status." ".lc($2);
			}
			elsif($1 eq "PHG")
			{
				my $status = DENON_GetValue('PS', $1, $1);
				my $value = DENON_GetValue('PS', $1, $2);
				readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
				$return = $status." ".$value;
			}
			elsif($1 eq "BAL")
			{
				my $status = DENON_GetValue('PS', $1);
				my $volume = $2 - 50;
				readingsBulkUpdate($hash, $status, $volume) if($status ne "unknown");
				$return = $status." ".$volume;				
			}
			else
			{
				my $status = DENON_GetValue('PS', $1);
				my $volume = $2;
					
				if($1 eq 'LFE')
				{
					$volume = ($volume * -1).$dezibel;
				}
				elsif($1 eq 'EFF')
				{
					$volume = $volume.$dezibel;
				}
				elsif($1 eq 'DEL')
				{
					$volume = $volume." ms";
				}
				else
				{
					if (length($volume) == 2)
					{
						$volume = $volume."0";
					}
					$volume = ($volume / 10 - 50).$dezibel;
				}
				readingsBulkUpdate($hash, $status, $volume) if($status ne "unknown");
				$return = $status." ".$volume;
			}
		}
		elsif($parameter =~ /^(CINEMA EQ).(.+)/)
		{
			my $name = DENON_GetValue('PS', $1);
			readingsBulkUpdate($hash, $name, lc($2)) if($name ne "unknown");
			$return = $name." ".lc($2);
		}
		elsif($parameter =~ /^(MULTEQ):(.+)/)
		{
			my $name = DENON_GetValue('PS', $1, $1);
			my $status = DENON_GetValue('PS', $1, $2);
			readingsBulkUpdate($hash, $name, $status) if($name ne "unknown" || $status ne "unknown");
			$return = $name." ".$status;
		}
		elsif($parameter =~ /^(DYNEQ) (.+)/)
		{
			my $name = DENON_GetValue('PS', $1);
			readingsBulkUpdate($hash, $name, lc($2)) if($name ne "unknown");
			$return = $name." ".lc($2);
		}
		elsif($parameter =~ /^(DYNVOL) (.+)/)
		{
			my $name = DENON_GetValue('PS', $1, $1);
			my $status = DENON_GetValue('PS', $1, $2);
			readingsBulkUpdate($hash, $name, $status) if($name ne "unknown" || $status ne "unknown");
			$return = $name." ".$status;
		}
	}
	#Input select
	elsif ($msg =~ /^SI(.+)/)
	{
		my $status = DENON_GetKey('SI', $1);
		readingsBulkUpdate($hash, "input", $status) if($status ne "unknown");
		readingsBulkUpdate($hash, "currentStream", "-") if($status ne "Server");
		readingsBulkUpdate($hash, "sound_signal_in", "-") if($status ne "CD|DOCK|DVR|DVD|BD|TV|SAT\/CBL|SAT|GAME|MPLAY|SAT|AUX1|AUX2|AUX3|AUX4|AUX5|AUX6|AUX7"); #	sets sound_signal_out to "-" if Input <-
		$hash->{helper}{INPUT} = $1;
		$return = $status;
		
		if ($1 =~ /^(TUNER|DVD|BD|TV|SAT\/CBL|GAME|SAT|AUX1|AUX2|AUX3|AUX4|AUX5|AUX6|AUX7|FLICKR)$/)
		{
			for(my $i = 0; $i < 9; $i++) {
				my $cur = "";
				my $status = 'ignore';
				if ($i == 2)
				{
					$cur = "s";
					$status = DENON_GetValue('NSE', $i.$cur);
					if($status ne 'ignore'){
						readingsBulkUpdate($hash, $status, '-');
					}
					$cur = "a";
				}
				$status = DENON_GetValue('NSE', $i.$cur);
				if($status ne 'ignore'){
					readingsBulkUpdate($hash, $status, '-');
				}
			}
		}
	}
	#Video-Select
	elsif ($msg =~ /^SV(.+)/)
	{
		my $status = DENON_GetValue('SV', $1);
		readingsBulkUpdate($hash, "videoSelect", $status) if($status ne "unknown");
		$return = "videoSelect ".$status;
	}
	#Video-Select
	elsif ($msg =~ /^PV(.+)/)
	{
		my $status = DENON_GetValue('PV', $1);
		readingsBulkUpdate($hash, "pictureMode", $status) if($status ne "unknown");
		$return = "pictureMode ".$status;
	}
	#Setup-Menu
	elsif ($msg =~ /^MNMEN ([A-Z]+)/)
	{
		readingsBulkUpdate($hash, "setup", lc($1));
		$return = "setup ".lc($1);
	}
	elsif ($msg =~ /^MNZST ([A-Z]+)/)
	{
		readingsBulkUpdate($hash, "allZoneStereo", lc($1));
		$return = "setup ".lc($1);
	}
	#quickselect
	elsif ($msg =~ /^MSQUICK(.+)/)
	{
		my $quick = DENON_GetValue("MS", "QUICK".$1);
		if ($1 =~ /^(1|2|3|4)/) {
			readingsBulkUpdate($hash, "quickselect", $quick) if($quick ne "unknown");
			$return = "quickselect ".$quick;
		}
	}
	#smartselect (Marantz)
	elsif ($msg =~ /^MSSMART(.+)/)
	{
		my $quick = DENON_GetValue("MS", "SMART".$1);
		if ($1 =~ /^(1|2|3|4)/) {
			readingsBulkUpdate($hash, "smartselect", $quick) if($quick ne "unknown");
			$return = "smartselect ".$quick;
		}
	}		
		#Sound
	elsif ($msg =~ /^MS(.+)/)
	{
		my $sound = DENON_GetValue('SOUND', $1);
		# get Surround-Mode from MS
		if($sound eq "unknown")
		{
			$sound = DENON_GetKey('MS', $1);
		}
		if ($sound ne "unknown")
		{
			readingsBulkUpdate($hash, "sound_out", $sound);
			$return = "sound_out ".$sound;	
		}
	}
	#tuner band
	elsif ($msg =~ /^TMAN(.+)/)
	{
		my $tuner = DENON_GetKey('TM', 'AN', $1);
		if($tuner =~ /^(AM|FM)$/)
		{
			readingsBulkUpdate($hash, "tunerBand", $tuner) if($tuner ne "unknown");
			$return = "tunerBand ".$tuner;
		}
		else
		{
			readingsBulkUpdate($hash, "tunerMode", $tuner) if($tuner ne "unknown");
			$return = "tunerMode ".$tuner;
		}
	}
	#tuner preset
	elsif ($msg =~ /^TPAN([0-9]+)/)
	{
		readingsBulkUpdate($hash, "tunerPreset", ($1 / 1));
		$return = "tunerPreset ".$1;

	}
	elsif ($msg =~ /^TPAN(OFF|ON)/)
	{
		readingsBulkUpdate($hash, "tunerTrafficProgramme", lc($1));
		$return = "tunerTrafficProgramme ".lc($1);

	}
	#tuner preset memory
	elsif ($msg =~ /^TPANMEM([A-Z0-9]+)/)
	{
		readingsBulkUpdate($hash, "tunerPresetMemory", $1);
		$return = "tunerPresetMemory ".$1;

	}	
	#tuner frequency
	elsif ($msg =~ /^TFAN([0-9]{6})/)
	{	
		my $frq = $1 / 100;
		if ($frq > 500)
		{
			readingsBulkUpdate($hash, "tunerFrequency", $frq." kHz");
			$return = "tunerFrequency ".$frq." kHz";
		}
		else
		{
			readingsBulkUpdate($hash, "tunerFrequency", $frq." MHz");
			$return = "tunerFrequency ".$frq." MHz";
		}

	}
	elsif ($msg =~ /^TFANNAME(.+)/) #TFANNAMEBayern 2
	{	
		readingsBulkUpdate($hash, "tunerStationName", $1);
		$return = "tunerStationName ".$1;
	}
	#elsif ($msg =~ /^NSFRN(.+)/) #Netwerk-Name
	#{	
	#	readingsBulkUpdate($hash, "Netzwerk-Name", $1);
	#	$return = "Netzwerk-Name ".$1;
	#}
	
	#Auto-LipSync
	elsif ($msg =~ /^SSALSSET ([A-Z]+)/)
	{
		my $status = DENON_GetKey('SSALSSET', $1);
		readingsBulkUpdate($hash, "Auto-Lip-Sync", $status) if($status ne "unknown");
		$return = "Auto-Lip-Sync ".$status;
	} 
	#Lautstärkeanzeige
	elsif ($msg =~ /^SSVCTZMADIS.([A-Z]+)/)
	{
		my $status = DENON_GetKey('SSVCTZMADIS', $1);
		readingsBulkUpdate($hash, "Volume-Display", $status) if($status ne "unknown");
		$return = "Volume-Display ".$status;
	}
  	#Muting-Pegel
	elsif ($msg =~ /^SSVCTZMAMLV ([A-Z0-9]+)/)
	{
		my $status = DENON_GetKey('SSVCTZMAMLV', $1);
		readingsBulkUpdate($hash, "Muting-Level", $status) if($status ne "unknown");
		$return = "Muting-Level".$status;
	}
	#ECO-Mode
	elsif ($msg =~ /^ECO([A-Z]+)/)
	{
		readingsBulkUpdate($hash, "eco", lc($1));
		$return = "eco ".lc($1);
	}
	#Dim-Mode Display
	elsif ($msg =~ /^DIM.([A-Z]+)/)
	{
		my $status = DENON_GetKey('DIM', $1);
		readingsBulkUpdate($hash, "display", $status) if($status ne "unknown");
		$return = "display ".$status;
	}
	#autoStandby
	elsif ($msg =~ /^STBY(.+)/)
	{
		my $status = DENON_GetKey('STBY', $1);
		readingsBulkUpdate($hash, "autoStandby", $status) if($status ne "unknown");
		$return = "autoStandby ".$status;
	}
	#sleep
	elsif ($msg =~ /^SLP(.+)/)
	{
		my $status = lc($1);
		if ($status ne "off")
		{
			$status = ($1 / 1)."min";
		}
		readingsBulkUpdate($hash, "sleep", $status) if($status ne "unknown");
		$return = "sleep ".$status;
	}
	#trigger on/off
	elsif ($msg =~ /^TR([0-9]) (.+)/)
	{
		readingsBulkUpdate($hash, "trigger".$1, lc($2));
		$return = "trigger".$1." ".lc($2);
	}
	#mainzone on/off
	elsif ($msg =~ /^ZM(.+)/)
	{
		readingsBulkUpdate($hash, "zoneMain", lc($1)) if(lc($1) ne ReadingsVal( $name, "zoneMain", "off"));
		readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
		DENON_AVR_GetStateAV($hash);
		$return = "zoneMain ". lc($1);
	}
	# other zones
	elsif ($msg =~ /^Z([2-4])(.+)/)
	{
		if($2 eq "ON"|| $2 eq "OFF")
		{
			Log3 $hash, 5, "DENON_AVR $name zone$1: $msg";
			readingsBulkUpdate($hash, "zone".$1, lc($2));
			$return = "zone".$1 . " " . lc($2);
		}
	}
	#current Media
	elsif ($msg =~ /^NSE0/ && length($msg) > 5){	
		my $text = substr($msg,4);
		if ($text =~ /^Now Playing/) {
			if(ReadingsVal( $name, "input", "" ) =~ /^(iRadio|Mediaplayer|HDRadio|OnlineMusic|Spotify|LastFM|Server|Favorites|SiriusXM|Bluetooth|Usb\/iPod|Usb_play|iPod_play|iRadio_play|Favorites_play|Pandora)$/)
			{
				$text =~ /Now Playing (.+)/;
				my $status = DENON_GetValue('NSE', '0');
				readingsBulkUpdate($hash, $status, $1) if ($1 ne ReadingsVal( $name, "currentMedia", "-"));
				if(ReadingsVal( $name, "currentPlaytime", "-") eq "-")
				{
					readingsBulkUpdate($hash, "playStatus", "playing");
					readingsBulkUpdate($hash, "currentPlaytime", "0:00");
					DENON_AVR_PlaytimeCheck ($hash);
					$hash->{helper}{playTimeCheck} = 1;
					$hash->{helper}{isPlaying} = 1;
				}
				$return = $status." ".$1;
			}
			else
			{
				my $cover = "http://" . $hash->{helper}{deviceIP} . "/img/album%20art_S.png" . "?" . DENON_AVR_GetTimeStamp(gettimeofday());
				readingsBulkUpdate($hash, "currentCover", $cover);
	
				$return = "reading ignored";
			}
		}
		else
		{
			foreach my $key (sort(keys %{$DENON_db->{'NSE'}})) {
				my $status = DENON_GetValue('NSE', $key);
				if ($status ne "ignore" || $status ne "unknown") {
					readingsBulkUpdate($hash, $status, "-");
				}
			}
			
			$return = "set readings to '-'";
		}
	}
	#Media Informations
	elsif ($msg =~ /^NSE/ && length($msg) > 5){
	    my $flag = ord(substr($msg,4,1));

		if(substr($msg,3,1) eq "4" && $flag == 0 && ord(substr($msg,5,1)) > 31)
		{
			#return "reading ignored";
		}
		elsif(substr($msg,3,1) eq "1" && $flag == 1 && ord(substr($msg,5,1)) > 31)
		{
			#return "reading ignored";
		}
		elsif(substr($msg,3,1) ne "5" && (ord(substr($msg,5,1)) == 32 || $flag == 0))
		{
			return "reading ignored: flag: " . $flag;
		}

		my $text = $flag < 32 ? substr($msg,5) : substr($msg,4);
		my $cur = "";
		my $status = "";
		
		if(ReadingsVal( $name, "input", "" ) =~ /^(iRadio|Mediaplayer|HDRadio|OnlineMusic|Spotify|LastFM|Server|Favorites|SiriusXM|Bluetooth|Usb\/iPod|Usb_play|iPod_play|iRadio_play|Favorites_play|Pandora)$/)
		{
			if (substr($msg,3,1) eq '2')
			{
				if(ReadingsVal( $name, "currentMedia", "" ) eq "iRadio" || ReadingsVal( $name, "input", "" ) eq "iRadio")
				{
					$cur = "s";
					$status = DENON_GetValue('NSE', substr($msg,3,1)."a");
					readingsBulkUpdate($hash, $status, "-") if ("-" ne ReadingsVal( $name, "currentArtist", "-"));
					$status = DENON_GetValue('NSE', "4");
					readingsBulkUpdate($hash, $status, "-") if ("-" ne ReadingsVal( $name, "currentAlbum", "-"));
				}
				else
				{
					$cur = "a";
					$status = DENON_GetValue('NSE', substr($msg,3,1)."s");
					readingsBulkUpdate($hash, $status, "-") if ("-" ne ReadingsVal( $name, "currentStation", "-"));
				}
			}
			
			$status = DENON_GetValue('NSE', substr($msg,3,1).$cur);
		
			if (substr($msg,3,1) ne '0')
			{
				if ((substr($msg,3,1) eq '5' && $text =~ /([0-9]{1,2}:[0-9]{2}:[0-9]{2}) .+/) || (substr($msg,3,1) eq '5' && $text =~ /([0-9]{1,2}:[0-9]{2}) .+/)) #Playtime
				{
					if ($flag eq "0")  # 0 = NUL (time)  or  2 = STX (text)
					{					
						if ($hash->{helper}{playTimeCheck} == 1)
						{	
							DENON_AVR_PlaystatusCheck($hash);
							readingsBulkUpdate($hash, $status, $1) if ($1 ne ReadingsVal( $name, "currentPlaytime", "-"));
							$return = $status." ".$1." flag: ".$flag;
						}
						else
						{
							readingsBulkUpdate($hash, $status, $1) if ($1 ne ReadingsVal( $name, "currentPlaytime", "-"));
							$return = $status." ".$1." flag: ".$flag;
						}					
					}
				}
				elsif($status ne 'ignore'){
					my $cover = "http://" . $hash->{helper}{deviceIP} . "/NetAudio/art.asp-jpg" . "?" . DENON_AVR_GetTimeStamp(gettimeofday());
					if (substr($msg,3,1) eq '1' && $flag eq "1" && $hash->{helper}{isPlaying} == 1)  #Title
					{
						if ($text ne ReadingsVal( $name, "currentTitle", "-")) {
							readingsBulkUpdate($hash, $status, $text);
							readingsBulkUpdate($hash, "currentCover", $cover);
						}
					}
					if (substr($msg,3,1) eq '2' && $flag eq "1" && $hash->{helper}{isPlaying} == 1) #Artist or station					
					{
						if($cur eq "a" && $text ne ReadingsVal( $name, "currentArtist", "-"))
						{
							readingsBulkUpdate($hash, $status, $text);
							readingsBulkUpdate($hash, "currentCover", $cover);
						}
						if($cur eq "s" && $text ne ReadingsVal( $name, "currentStation", "-"))
						{
							readingsBulkUpdate($hash, $status, $text);
							readingsBulkUpdate($hash, "currentCover", $cover);
						}
					}
					if (substr($msg,3,1) eq '3' && $flag eq "1" && $text =~ /kHz/ && $hash->{helper}{isPlaying} == 1) #Bitrate
					{
						readingsBulkUpdate($hash, $status, $text) if ($text ne ReadingsVal( $name, "currentBitrate", "-"));
					}
					if (substr($msg,3,1) eq '4' && $flag eq "0" && $hash->{helper}{isPlaying} == 1) # Album
					{
						readingsBulkUpdate($hash, $status, $text) if ($text ne ReadingsVal( $name, "currentAlbum", "-"));
					}
					$return = $status." ".$text." flag: ".$flag;
				}
				else
				{
					$return = "reading ignored: flag: " . $flag;
				}
			}
		}
	}
	#system information
	elsif ($msg =~ /^SS(.+)/){
		my $parameter = $1;
		if($parameter =~ /^([A-Z]{3}) (.+)/)
		{
			if($1 eq 'LOC') #SSLOC OFF
			{
				my $status = DENON_GetValue('SS', $1);
				readingsBulkUpdate($hash, $status, lc($2)) if($status ne "unknown");
				$return = $status." ".lc($2);			
			}
			#Surround Mode
			elsif($1 eq 'SMG') #SSSMG MOV
			{
				my $status = DENON_GetValue('SS', $1, $2);
				readingsBulkUpdate($hash, "surroundMode", $status) if($status ne "unknown");
				$return = "surroundMode ".$status;
			}
		}
		elsif($parameter =~ /^([A-Z]{3})(.+) (.+)/)
		{
			if ($1 eq 'FUN') # SSFUNCD CD , SSFUNMPLAY Media Player
			{
				my $function = $3;
				$function =~ s/ //g;
				#DENON_SetValue($function, 'SS', $1, $2);
				$return = "name ".$2." changed to ".$function;
			}
			elsif ($1 eq 'SOD') # SSSODTUNER USE
			{
				#DENON_SetValue($3, 'SS', $1, $2);			
				$return = lc($3)." ".$2;			
			}
#			elsif ($1 eq 'PAA') # SSPAA
#			{
#				my $status = DENON_GetValue('SS', $1, $2, $3);	
#				readingsBulkUpdate($hash, "ampAssign", $status) if($status ne "unknown");
#				$return = "ampAssign ".$status;
#			}
			elsif ($1 eq 'INF') # SSINFFRM 0000-0000-0000-00
			{		
				#Firmware_AVR
				if ($2 eq "FRMAVR") { # SSINFFRMAVR 0000-0000-0000-00
					my $status = DENON_GetValue('SS', $1, $2);
					readingsBulkUpdate($hash, $status, $3) if($status ne "unknown");
					$return = $status." ".$3;
				}
				if ($2 eq "FRMDTS") { # SSINFFRMDTS 0.00.00.00
					my $status = DENON_GetValue('SS', $1, $2);
					readingsBulkUpdate($hash, $status, $3) if($status ne "unknown");
					$return = $status." ".$3;
				}
				else # SSINFAISSIG 02
				{
					my $cmd1  = $1; #INF
					my $cmd2  = $2;
					my $value = $3;						#  $1  $2
					$cmd2 =~ /^([A-Z]{3})([A-Z]{3})/;   # AIS SIG
					
					if ($1 eq 'AIS') 
					{	
									#input signal
						if ($2 eq 'SIG')
						{
							my $signal = DENON_GetValue('SS', $cmd1, $1, $2, $value);
							readingsBulkUpdate($hash, "sound_signal_in", $signal) if($signal ne "unknown");
							$return = "sound_signal_in ".$signal;
							if($signal =~ /^na (.+)/)
							{
								my $sound = ReadingsVal( $name, "sound_out", "?" );
								Log3 $name, 2, "DENON_AVR $name: unknown input signal <$1>, sound_out <$sound>.";
							}
						}						
						# samplingRate, audioFormat
						elsif ($2 eq 'FSV' || $2 eq 'FOR')
						{
							my $status = DENON_GetValue('SS', $cmd1, $1, $2);
							$value = "-" if($value eq "NON");
							if($status eq "samplingRate" && $value ne "-")
							{
								if ($value =~ /^([0-9]{3})/)
								{
									$value = ($1 / 10)." khz";
								}
								elsif ($value =~ /^([0-9]{2})/)
								{
									$value = $1." khz";
								}
							}
							readingsBulkUpdate($hash, $status, $value) if($status ne "unknown");
							$return = $status." ".$value;	
						}
					}
				}
			}		
		}
	}	
	#Model
	elsif ($msg =~ /^NS([A-Z]{3}) (.+)/){
		my $status = DENON_GetValue('NS', $1);
		readingsBulkUpdate($hash, $status, $2) if($status ne "unknown");
			$return = $status." ".$2;
	}
	
	
	elsif ($msg =~ /^VS(.+)/){
		my $cmd  = $1;
		if($cmd =~ /^(ASP)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1, $1);
			my $value = DENON_GetValue('VS', $1, $2);
			readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
			$return = $status." ".$value;
		}
		elsif($cmd =~ /^(MONI)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1, $1);
			my $value = DENON_GetValue('VS', $1, $2);
			readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
			$return = $status." ".$value;
		}
		elsif($cmd =~ /^(SCH)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1, $1);
			my $value = DENON_GetValue('VS', $1, $2);
			readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
			$return = $status." ".$value;
		}
		elsif($cmd =~ /^(SC)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1, $1);
			my $value = DENON_GetValue('VS', $1, $2);
			readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
			$return = $status." ".$value;
		}
		elsif($cmd =~ /^(AUDIO)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1, $1);
			my $value = DENON_GetValue('VS', $1, $2);
			readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
			$return = $status." ".$value;
		}
		elsif($cmd =~ /^(VPM)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1, $1);
			my $value = DENON_GetValue('VS', $1, $2);
			readingsBulkUpdate($hash, $status, $value) if($status ne "unknown" || $value ne "unknown");
			$return = $status." ".$value;
		}
		elsif($cmd =~ /^(VST)(.+)/)
		{
			my $status = DENON_GetValue('VS', $1);
			readingsBulkUpdate($hash, $status, lc($2)) if($status ne "unknown");
			$return = $status." ".lc($2);
		}
	}
	#DigitalSound-Select input
	elsif ($msg =~ /^SD(.+)/){
		my $status = DENON_GetValue('SD', $1);
		readingsBulkUpdate($hash, "inputSound" ,$status) if($status ne "unknown");
		$return = "inputSound ".$status;
	}
	#Favorite list - only ceol
	elsif ($msg =~ /^FV(.+)/){
		$return = $1;
	}
	else 
	{
		if($msg eq "CV END")
		{
			$return = "ignored";	
		}
		else
		{
			$return = "unknown message - $msg";	
		}
	}
	return $return;
}

#############################
sub
DENON_AVR_Undefine($$)
{
	my($hash, $name) = @_;
	
	Log3 $name, 5, "DENON_AVR $name: called Undefine.";
	
	delete $modules{DENON_AVR_ZONE}{defptr}{$name}{1}
		if ( defined( $modules{DENON_AVR_ZONE}{defptr}{$name}{1} ) );

	RemoveInternalTimer($hash);
	DevIo_CloseDev($hash);
	
	DENON_AVR_RCdelete($name);
	DENON_AVR_Delete_Zone($name."_Zone_2", "2");
	DENON_AVR_Delete_Zone($name."_Zone_3", "3");
	
	return undef;
}

#############################
sub
DENON_AVR_Get($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	return "argument is missing" if (int(@a) < 2 && int(@a) > 3);

	if ($a[1] =~ /^(power|volumeStraight|volume|mute|eco|display|input|disconnect|reconnect|remotecontrol|autoStandby|sound_out|statusRequest|mediaInfo|surroundMode|zone)$/)
	{
		if ($a[1] eq "statusRequest")
		{
			# Force update of status
			return DENON_AVR_Command_StatusRequest($hash);
		}
		if ($a[1] eq "mediaInfo")
		{
			DENON_AVR_Write($hash, "NSE", "query");
			return undef;
		}
		elsif ($a[1] eq "remotecontrol")
		{
			return DENON_AVR_RCmake($name);
		}
		elsif ($a[1] eq "reconnect")
		{
			my $status = ReadingsVal( $name, "state", "opened" );
			if($status ne "opened")
			{
				DevIo_OpenDev($hash, 0, "DENON_AVR_DoInit");
				return "Try to initialize device!";			
			}
			else 
			{
				return "Disconnect device first!";
			}
		}
		elsif ($a[1] eq "zone")
		{			
			my $return = DENON_AVR_Make_Zone($name."_Zone_".$a[2], $a[2]);
			DENON_AVR_Command_StatusRequest($hash);
			return $return;
		}
		elsif ($a[1] eq "disconnect")
		{
			RemoveInternalTimer($hash);
			DevIo_CloseDev($hash);
			$hash->{STATE} = "disconnected";
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "presence", "absent");
			readingsBulkUpdate($hash, "state", "disconnected");
			readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
			readingsEndUpdate($hash, 1);
			Log3 $name, 5, "$name: closed.";
			
			return "Disconnected device!";
		}
		elsif(defined(ReadingsVal( $name, $a[1], "" )))
		{		
			return ReadingsVal( $name, $a[1], "" );
		}
		else
		{
			return "No such reading: $a[1]";
		}
	}
	else
	{
		my @inputs = ();
		foreach my $key (sort(keys %{$DENON_db->{'SI'}})) {
			my $device = $DENON_db->{'SI'}{$key};
			if ( defined($DENON_db->{'SS'}{'SOD'}{$device}) && $DENON_db->{'SS'}{'SOD'}{$device} eq 'USE' )
			{
				push(@inputs, $key);
			}
		}
		return "Unknown argument $a[1], choose one of power volumeStraight volume mute eco display input disconnect reconnect remotecontrol autoStandby sound_out statusRequest mediaInfo surroundMode zone:2,3,4";
	}
}

###################################
sub
DENON_AVR_Set($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	
	my @channel = ();
	my $favorites = AttrVal( $name, "favorites", 4 );
	my @favorite = (1..$favorites);
	my $maxFavorites = AttrVal( $name, "maxFavorites", 20 );
	my @favoriteList = (1..$maxFavorites);
	my @preset = (01..56);
	my $maxPreset = AttrVal( $name, "maxPreset", 35 );
	my $presetMode = AttrVal( $name, "presetMode", "numeric" );
	my @presetCall = (00..$maxPreset);
	my @presetCallAn = ("A1","A2","A3","A4","A5","A6","A7","A8","B1","B2","B3","B4","B5","B6","B7","B8","C1","C2","C3","C4","C5","C6","C7","C8","D1","D2","D3","D4","D5","D6","D7","D8","E1","E2","E3","E4","E5","E6","E7","E8","F1","F2","F3","F4","F5","F6","F7","F8","G1","G2","G3","G4","G5","G6","G7","G8");
	my @inputs = ();
	my @inputSound = ();
	my @pictureMode = ();
	my @usedInputs = ();
	my @remoteControl = ();
	my @resolution = ();
	my @resolutionHDMI = ();
	my @tuner = ();
	my @multiEQ = ();
	my @dynvol = ();
	my $select = "quick";
	my $sliderSraight = "-80,0.5,18,1 ";
	my $slider = "0,0.5,98,1 ";
	my $streams = "";
	my $dezibel = AttrVal($name, "unit", "off") eq "on" ? " dB" : "";

	
	foreach my $key (sort(keys %{$DENON_db->{'CV'}})) {
		push(@channel, $DENON_db->{'CV'}{$key}."_up");
		push(@channel, $DENON_db->{'CV'}{$key}."_down");		
	}
	
	foreach my $key (sort(keys %{$DENON_db->{'REMOTE'}})) {
		push(@remoteControl, $key);	
	}
	
	foreach my $key (sort(keys %{$DENON_db->{'VS'}{'SC'}})) {
		push(@resolution, $DENON_db->{'VS'}{'SCH'}{$key}) if ($key ne "SC");	
	}
	
	foreach my $key (sort(keys %{$DENON_db->{'VS'}{'SCH'}})) {
		push(@resolutionHDMI, $DENON_db->{'VS'}{'SCH'}{$key}) if ($key ne "SCH");	
	}
	
	if ( exists( $attr{$name}{inputs} ) ) {
		@usedInputs = split(/,/,$attr{$name}{inputs});
		
		foreach(@usedInputs) {
			if ( defined($DENON_db->{'SI'}{$_})) {
				push(@inputs, $_);
			}
		}
	}
	else
	{
		foreach my $key (sort(keys %{$DENON_db->{'SI'}})) {
			my $device = $DENON_db->{'SI'}{$key};
				
			if ( defined($DENON_db->{'SS'}{'SOD'}{$device}))
			{
				if ($DENON_db->{'SS'}{'SOD'}{$device} eq 'USE')
				{
					push(@inputs, $key);
				}		
				push(@usedInputs, $key);
			}
		}
	}
			
	foreach my $key (sort(keys %{$DENON_db->{'SD'}})) {
		push(@inputSound, $DENON_db->{'SD'}{$key});	
	}
	
	
	foreach my $key (sort(keys %{$DENON_db->{'PV'}})) {
		push(@pictureMode, $DENON_db->{'PV'}{$key});	
	}
	
	foreach my $key (sort(keys %{$DENON_db->{'TM'}{'AN'}})) {
		push(@tuner, $key);	
	}
	
	foreach my $key (sort(keys %{$DENON_db->{'PS'}{'MULTEQ'}})) {
		my $value = $DENON_db->{'PS'}{'MULTEQ'}{$key};
		push(@multiEQ, $value) if ($key ne "MULTEQ");	
	}
	
	foreach my $key (sort(keys %{$DENON_db->{'PS'}{'DYNVOL'}})) {
		my $value = $DENON_db->{'PS'}{'DYNVOL'}{$key};
		push(@dynvol, $value) if ($key ne "DYNVOL");	
	}
	
	if(AttrVal($name, "brand", "Denon") eq "Marantz")
	{
		$select = "smart";
	}
	
	my $ceolEntry = "";
	if(AttrVal($name, "type", "AVR") eq "Ceol")
	{
		$sliderSraight = "-80,1,-20,1 ";
		$slider = "0,1,60,1 ";
		$ceolEntry = "clock" . " " .
		             "favorite_Memory:" . join(",", @favorite) . " " .
					 "favorite_Delete:" . join(",", @favorite) . " " .
					 "balance:slider,-6,1,6"  . " " .
					 "sdb:on,off"  . " " .
					 "sourceDirect:on,off"  . " ";
	}
	else 
	{
		$ceolEntry = "favoriteList:" . join(",", @favoriteList) . " ";
	}

	my $usage = "Unknown argument $a[1], choose one of on off toggle volumeDown volumeUp mute:on,off,toggle muteT eco:on,auto,off allZoneStereo:on,off display:off,bright,dim,dark,toggle setup:on,off autoStandby:off,15min,30min,60min sleep:off,10min,15min,20min,30min,40min,50min,60min,70min,80min,90min,100min,110min,120min trigger1:on,off trigger2:on,off audysseyLFC:on,off cinemaEQ:on,off dynamicEQ:on,off loudness:on,off aspectRatio:4:3,16:9 monitorOut:auto,1,2 audioOutHDMI:amplifier,tv videoProcessingMode:auto,Game,Movie verticalStretch:on,off zoneMain:on,off " .
			"volumeStraight:slider," . $sliderSraight .
			"volume:slider," . $slider .
			$select . "select:1,2,3,4,5 " .
			"resolution:" . join(",", @resolution) . " " .
			"resolutionHDMI:" . join(",", @resolutionHDMI) . " " .
			"multiEQ:" . join(",", @multiEQ) . " " .
			"dynamicVolume:" . join(",", @dynvol) . " " .
			"lowFrequencyEffects:slider,-10,1,0 " .
	        "bass:slider,-6,1,6 treble:slider,-6,1,6 " .
		    "channelVolume:" . join(",", @channel) . ",FactoryDefaults" . " " . 
			"tuner:" . join(",", @tuner) . " " .
			"tunerPreset:" . join(",", @preset) . " " .
			"tunerPresetMemory:" . join(",", @preset) . " " .
			"preset:1,2,3" . " " .
			"presetCall:" . join(",", @presetCall) . " " .
			"presetMemory:" . join(",", ($presetMode eq "alphanumeric" ? @presetCallAn : @presetCall)) . " " .
			"favorite:" . join(",", @favorite) . " " .
			$ceolEntry  .
			"input:" . join(",", @inputs) . " " .
			"inputSound:" . join(",", @inputSound) . " " .
			"pictureMode:" . join(",", @pictureMode) . " " .
			"usedInputs:multiple-strict,"  . join(",", @usedInputs) . " " .
			"remoteControl:" . join(",", @remoteControl) . " " .
			"sound_out:" . join(",", sort keys %{$DENON_db->{'MS-set_sound_out'}}) . " " .
			"surroundMode:" . join(",", sort keys %{$DENON_db->{'MS-set_surroundMode'}}) . " " .
		 	"rawCommand"; 	
		
	if(AttrVal($name, "dlnaName", "") ne "")
	{
		$streams = DENON_AVR_GetStream("", "list");
		if ($streams ne "")
		{
			$usage .= " stream:" . $streams;
		}
	}
	
	if ($a[1] eq "?")
	{
		return $usage;
	}
	
	readingsBeginUpdate($hash);
	
	if ($a[1] =~ /^(on|off)$/)
	{
		return DENON_AVR_Command_SetPower($hash, $a[1]);
	}
	elsif ($a[1] =~ "zoneMain")
	{
		DENON_AVR_Write($hash, "ZM".uc($a[2]), "zoneMain");
		readingsBulkUpdate($hash, "zoneMain", $a[2]);
		readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
	}
	elsif ($a[1] eq "quickselect")
	{
		DENON_AVR_Write($hash, "MSQUICK".$a[2], "quickselect");
		readingsBulkUpdate($hash, "quickselect", $a[2]);
	}
	elsif ($a[1] eq "smartselect")
	{
		DENON_AVR_Write($hash, "MSSMART".$a[2], "smartselect");
		readingsBulkUpdate($hash, "smartselect", $a[2]);
	}
	elsif ($a[1] eq "tuner")
	{
		my $tuner = DENON_GetValue('TM', 'AN', $a[2]);
		DENON_AVR_Write($hash, "TMAN".$tuner, "tuner");
	}
	elsif ($a[1] eq "tunerPreset")
	{
		my $preset = sprintf("%.2d", $a[2]);	
		DENON_AVR_Write($hash, "TPAN".$preset, "preset");
	}
	elsif ($a[1] eq "tunerPresetMemory")
	{
		my $preset = sprintf("%.2d", $a[2]);	
		DENON_AVR_Write($hash, "TPANMEM".$preset, "tunerPresetMemory");
	}
	elsif ($a[1] eq "preset")
	{
		my $preset = $a[2];
		DENON_AVR_Write($hash, "NSP".$preset, "tunerPreset");
	}
	elsif ($a[1] eq "presetCall")
	{
		my $preset = sprintf("%.2d", $a[2]);
		
		DENON_AVR_Write($hash, "NSB".$preset, "presetCall");
	}
	elsif ($a[1] eq "presetMemory")
	{
		if ($a[2] =~ /^[ABCDEFG][0-8]$/){	
			DENON_AVR_Write($hash, "NSC".$a[2], "presetMemory");
		}
		else {
			my $preset = sprintf("%.2d", $a[2]);	
			DENON_AVR_Write($hash, "NSC".$preset, "presetMemory");
		}
	}
	elsif ($a[1] eq "favorite")
	{
		my $favorite = $a[2];
		if(AttrVal($name, "type", "AVR") eq "Ceol")
		{
			$favorite = sprintf ('%02d', $favorite);
			DENON_AVR_Write($hash, "FV ".$favorite, "favorite");
		}
		else
		{
			DENON_AVR_Write($hash, "ZMFAVORITE".$favorite, "favorite");
		}
		readingsBulkUpdate($hash, "favorite", $favorite);
	}
	elsif ($a[1] eq "favorite_Memory")
	{
		my $favorite = $a[2];
		$favorite = sprintf ('%02d', $favorite);
		DENON_AVR_Write($hash, "FVMEM ".$favorite, "favorite_Memory");
	}
	elsif ($a[1] eq "favorite_Delete")
	{
		my $favorite = $a[2];
		$favorite = sprintf ('%02d', $favorite);
		DENON_AVR_Write($hash, "FVDEL ".$favorite, "favorite_Delete");
	}
	elsif ($a[1] eq "favoriteList")
	{
		my $fav = $a[2];
		DENON_AVR_SetFavorite($name, $fav);
	}
	elsif ($a[1] eq "toggle")
	{
		my $newPowerState = DENON_GetValue('SWITCH', ReadingsVal( $name, "state", "on"));		
		return DENON_AVR_Command_SetPower($hash, $newPowerState);
	}
	elsif ($a[1] eq "mute" || $a[1] eq "muteT")
	{	
		my $mute = defined($a[2]) ? $a[2] : "?";
		if ($mute eq "toggle" || $a[1] eq "muteT")
		{
		    $a[1] = "mute";
			my $newMuteState = DENON_GetValue('SWITCH', ReadingsVal( $name, $a[1], "off"));
			return DENON_AVR_Command_SetMute($hash, $newMuteState);
		}
		else
		{
			return DENON_AVR_Command_SetMute($hash, $mute);
		}
	}
	elsif ($a[1] eq "input")
	{
		my $input = DENON_GetValue('SI', $a[2]);
		return DENON_AVR_Command_SetInput($hash, $input, $a[2]);
	}	
	elsif ($a[1] eq "remoteControl")
	{
		if($a[2] =~ /^(up|down|left|right|enter)$/)
		{
			if(ReadingsVal( $name,"input", "" ) =~ /^(iRadio|Mediaplayer|OnlineMusic|Spotify|LastFM|Server|Favorites|SiriusXM|Bluetooth|Usb\/iPod|Usb_play|iPod_play|iRadio_play|Favorites_play|Pandora)$/)
			{
				if(ReadingsVal( $name, "setup", "off" ) eq "on")
				{
					my $remote = DENON_GetValue('MN', $a[2]);	
					DENON_AVR_Write($hash, "MN".$remote, "remoteControl");
				}
				my $remote = DENON_GetValue('NS', $a[2]);	
				DENON_AVR_Write($hash, "NS".$remote, "remoteControl");
			}
			elsif(ReadingsVal( $name,"input", "" ) =~ /^(Tuner)$/)
			{
				if(ReadingsVal( $name, "setup", "off" ) eq "on")
				{
					my $remote = DENON_GetValue('MN', $a[2]);	
					DENON_AVR_Write($hash, "MN".$remote, "remoteControl");
				}
				
				if(ReadingsVal( $name, "tunerBand", "?" ) =~ /^(AM|FM)$/)
				{
					if($a[2] eq "up")
					{
						DENON_AVR_Write($hash, "TPANUP", "remoteControl");
					}
					elsif($a[2] eq "down")
					{
						DENON_AVR_Write($hash, "TPANDOWN", "remoteControl");
					}
					elsif($a[2] eq "left")
					{
						DENON_AVR_Write($hash, "TFANDOWN", "remoteControl");
					}
					elsif($a[2] eq "right")
					{
						DENON_AVR_Write($hash, "TFANUP", "remoteControl");
					}
				}	
			}
			else
			{
				my $remote = DENON_GetValue('MN', $a[2]);	
				DENON_AVR_Write($hash, "MN".$remote, "remoteControl");
			}
		}
		else
		{
			if($a[2] eq "eco")
			{			        
				my $state = ReadingsVal( $name, "eco", "off" );
				my $cmd = DENON_GetValue('TOGGLE', $state);
								
				DENON_AVR_Write($hash, 'ECO'.uc($cmd), "remoteControl");
				readingsBulkUpdate($hash, "eco", $cmd);
			}
			elsif($a[2] eq "setup")
			{
				my $state =  DENON_GetValue('SWITCH', ReadingsVal( $name, "setup", "on" ));
				DENON_AVR_Write($hash, 'MNMEN '.uc($state), "remoteControl");
				readingsBulkUpdate($hash, "setup", $state);
			}
			elsif($a[2] eq "allZoneStereo")
			{
				my $state =  DENON_GetValue('SWITCH', ReadingsVal( $name, "allZoneStereo", "on" ));
				DENON_AVR_Write($hash, 'MNZST '.uc($state), "remoteControl");
				readingsBulkUpdate($hash, "allZoneStereo", $state);
			}	
			elsif ($a[2] eq "clock")
			{
				DENON_AVR_Write($hash, 'CLK', "clock");
				return undef;
			}
			elsif ($a[1] eq "sdb")
			{
				my $state = ReadingsVal( $name, "sdb", "off" );
				DENON_AVR_Write($hash, "SDB ".uc($state), "remoteControl");
				readingsBulkUpdate($hash, "sdb", $state);
			}
			elsif ($a[1] eq "sourceDirect")
			{
				my $state = ReadingsVal( $name, "sourceDirect", "off" );
				DENON_AVR_Write($hash, "SDI ".uc($state), "remoteControl");
				readingsBulkUpdate($hash, "sourceDirect", $state);
			}	
			elsif($a[2] =~ /^in_(.+)/) #inputs
			{
				my $remote = DENON_GetValue('SI', $1);
				DENON_AVR_Command_SetInput($hash, $remote, $1);
			}
			elsif($a[2] =~ /^sm_(.+)/) #sound-mode
			{
				my $remote = DENON_GetValue('MS', $1);
				DENON_AVR_Write($hash, "MS".$remote, "remoteControl");
			}
			elsif($a[2] =~ /^pc_(.+)/) #preset call 00-55 or 00-35 (AVR > 2014)
			{
				my $preset = sprintf("%.2d", $1);	
				DENON_AVR_Write($hash, "NSB".$preset, "presetCall");
			}
			elsif($a[2] =~ /^pm_(.+)/) #preset memory call 00-55, 00-35 (AVR > 2014) or A1-G8
			{
				if ($a[2] =~ /^[ABCDEFG][0-8]$/){	
					DENON_AVR_Write($hash, "NSC".$a[2], "presetMemory");
				}
				else {
						my $preset = sprintf("%.2d", $a[2]);	
					DENON_AVR_Write($hash, "NSC".$preset, "presetMemory");
				}
			}			
			elsif($a[2] =~ /^main_(on|off)/) #main zone
			{
				fhem("set $name zoneMain $1");
			}
			else
			{				
				if(exists $DENON_db->{'MN'}{$a[2]}) #system remote
				{
					my $remote = DENON_GetValue('MN', $a[2]);	
					DENON_AVR_Write($hash, "MN".$remote, "remoteControl");	
				}
				elsif(exists $DENON_db->{'NS'}{$a[2]}) #media remote
				{
					my $remote = DENON_GetValue('NS', $a[2]);	
					DENON_AVR_Write($hash, "NS".$remote, "remoteControl");
					readingsBulkUpdate($hash, "playStatus", 'paused') if($a[1] eq "pause");
					readingsBulkUpdate($hash, "playStatus", 'playing') if($a[1] eq "play");
					readingsBulkUpdate($hash, "playStatus", 'stopped') if($a[1] eq "stop");
				}
				else
				{
					fhem("set $name $a[2]");
				}
			}
		}
		readingsEndUpdate($hash, 1);
		return undef;
	}		
	elsif ($a[1] eq "sound_out")
	{	
		my $sound = $a[2];		
		my $cmd = DENON_GetValue('MS', $a[2]);
		DENON_AVR_Write($hash, "MS".$cmd, "sound_out");
		
		readingsBulkUpdate($hash, "sound_out", $sound);	
		readingsEndUpdate($hash, 1);
		return undef;	
	}
	elsif ($a[1] eq "surroundMode")
	{	
		my $sound = $a[2];		
		my $cmd = DENON_GetValue('MS', $a[2]);
		DENON_AVR_Write($hash, "MS".$cmd, "surroundMode");
		
		readingsBulkUpdate($hash, "surroundMode", $sound);	
		readingsEndUpdate($hash, 1);
		return undef;	
		}
	elsif ($a[1] eq "volumeStraight")
	{
		my $volume = $a[2];
		return DENON_AVR_Command_SetVolume($hash, $volume + 80);
	}
	elsif ($a[1] eq "volume")
	{
		my $volume = $a[2];
		return DENON_AVR_Command_SetVolume($hash, $volume);
	}
	elsif ($a[1] eq "volumeDown")
	{
		my $cmd = "MVDOWN";
		my $volume = $a[2];
		if($a[2])
		{
			$volume = $hash->{helper}{volume} - $volume;
			return DENON_AVR_Command_SetVolume($hash, $volume);
		}
		else
		{
			DENON_AVR_Write($hash, $cmd, "volumeDown");
		}
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "volumeUp")
	{
		my $cmd = "MVUP";
		my $volume = $a[2];
		if($a[2])
		{
			$volume = $hash->{helper}{volume} + $volume;
			return DENON_AVR_Command_SetVolume($hash, $volume);
		}
		else
		{
			DENON_AVR_Write($hash, $cmd, "volumeUp");
		}
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "channelVolume")
	{
		my $channel = "";
		my $command = $a[2];
		my $volume = "";
		if($command =~ /^(.+)_(up|down)/)
		{
			$channel = DENON_GetKey("CV", $1);
			$channel = $channel." ".uc($2);
			$volume = uc($2);
		}
		elsif($command =~ /^FactoryDefaults/)
		{
			$channel = 'ZRL';
			$volume = "reset";
		}
		else
		{
		
		
		
		
		
		
		

			$channel = DENON_GetKey("CV", $command);
			$volume = $a[3] + 50;
			if ($volume % 1 == 0)
			{
				$volume = 38 if($volume < 38);
				$volume = 62 if($volume > 62);
				$volume = sprintf ('%02d', $volume);
				$channel = $channel." ".$volume;
			}
			elsif ($volume % 1 == 0.5)
			{
				$volume = 38.5 if($volume < 38.5);
				$volume = 61.5 if($volume > 61.5);
				$volume = sprintf ('%03d', ($volume * 10));
				$channel = $channel." ".$volume;
			}
			else
			{
				return undef;
			}
		}						
		DENON_AVR_Write($hash, "CV".$channel, $volume);
		readingsEndUpdate($hash, 1);
		DENON_AVR_Write($hash, "CV?", "query"); 
		return undef;
	}
	elsif ($a[1] eq "bass")
	{
		my $volume = $a[2] + 50;	
		DENON_AVR_Write($hash, "PSBAS ".$volume, "bass");
		readingsBulkUpdate($hash, "bass", $a[2].$dezibel);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "treble")
	{
		my $volume = $a[2] + 50;					
		DENON_AVR_Write($hash, "PSTRE ".$volume, "treble");
		readingsBulkUpdate($hash, "treble", $a[2].$dezibel);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "balance")
	{
		my $volume = $a[2] + 50;					
		DENON_AVR_Write($hash, "PSBAL ".$volume, "balance");
		readingsBulkUpdate($hash, "balance", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "eco")
	{
		my $cmd = DENON_GetValue("ECO", $a[2]);
		DENON_AVR_Write($hash, "ECO".$cmd, "eco");
		readingsBulkUpdate($hash, "eco", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "setup")
	{
		DENON_AVR_Write($hash, 'MNMEN '.uc($a[2]), "setup");
		readingsBulkUpdate($hash, "setup", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "allZoneStereo")
	{
		DENON_AVR_Write($hash, 'MNZST '.uc($a[2]), "allZoneStereo");
		readingsBulkUpdate($hash, "allZoneStereo", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "cinemaEQ")
	{
		DENON_AVR_Write($hash, 'PSCINEMA EQ.'.uc($a[2]), "cinemaEQ");
		readingsBulkUpdate($hash, "cinemaEQ", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "multiEQ")
	{	
		my $cmd = DENON_GetKey("PS", "MULTEQ", $a[2]);
		DENON_AVR_Write($hash, 'PSMULTEQ:'.$cmd, "multiEQ");
		readingsBulkUpdate($hash, "multiEQ", $cmd);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "dynamicEQ")
	{
		DENON_AVR_Write($hash, 'PSDYNEQ '.uc($a[2]), "dynamicEQ");
		readingsBulkUpdate($hash, "dynamicEQ", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "dynamicVolume")
	{
		my $cmd = DENON_GetKey("PS", "DYNVOL", $a[2]);
		DENON_AVR_Write($hash, "PSDYNVOL ".$cmd, "dynamicVolume");
		readingsBulkUpdate($hash, "dynamicVolume", $cmd);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "audysseyLFC")
	{
		DENON_AVR_Write($hash, 'PSLFC '.uc($a[2]), "audysseyLFC");
		readingsBulkUpdate($hash, "audysseyLFC", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "lowFrequencyEffects")
	{
		my $volume = sprintf ('%02d', $a[2]);
		DENON_AVR_Write($hash, "PSLFE ".$volume, "lowFrequencyEffects");
		readingsBulkUpdate($hash, "lowFrequencyEffects", ($volume * -1).$dezibel);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] eq "loudness")
	{
		DENON_AVR_Write($hash, "PSLOM ".uc($a[2]), "loudness");
		readingsBulkUpdate($hash, "loudness", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "clock")
	{
		DENON_AVR_Write($hash, 'CLK', "clock");
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "sdb")
	{
		DENON_AVR_Write($hash, "SDB ".uc($a[2]), "sdb");
		readingsBulkUpdate($hash, "sdb", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "sourceDirect")
	{
		DENON_AVR_Write($hash, "SDI ".uc($a[2]), "sdi");
		readingsBulkUpdate($hash, "sourceDirect", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "display")
	{
		my $cmd = DENON_GetValue('DIM', $a[2]);
		DENON_AVR_Write($hash, 'DIM '.$cmd, "display");
		readingsBulkUpdate($hash, "display", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "autoStandby")
	{
		my $cmd = DENON_GetValue('STBY', $a[2]);
		DENON_AVR_Write($hash, 'STBY'.$cmd, "autoStandby");
		readingsBulkUpdate($hash, "autoStandby", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "sleep")
	{
		my $cmd = DENON_GetValue('SLP', $a[2]);
		DENON_AVR_Write($hash, 'SLP'.$cmd, "sleep");
		readingsBulkUpdate($hash, "sleep", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif($a[1] =~ /^(trigger1|trigger2)$/)
	{
		my $trigger = $a[1];
		$trigger =~ /^trigger([0-9])/;
		DENON_AVR_Write($hash, 'TR'.$1." ".uc($a[2]), "trigger");
		readingsBulkUpdate($hash, "trigger".$1, $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "usedInputs")
	{
		DENON_AVR_SetUsedInputs($hash, $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "inputSound")
	{
		my $cmd = DENON_GetKey("SD", $a[2]);
		DENON_AVR_Write($hash, "SD".$cmd, "inputSound");
		readingsBulkUpdate($hash, "inputSound", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "pictureMode")
	{
		my $cmd = DENON_GetKey("PV", $a[2]);
		DENON_AVR_Write($hash, "PV".$cmd, "pictureMode");
		readingsBulkUpdate($hash, "pictureMode", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "aspectRatio")
	{
		my $cmd = DENON_GetKey("VS", "ASP", $a[2]);
		DENON_AVR_Write($hash, "VSASP".$cmd, "aspectRatio");
		readingsBulkUpdate($hash, "aspectRatio", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "monitorOut")
	{
		my $cmd = DENON_GetKey("VS", "MONI", $a[2]);
		DENON_AVR_Write($hash, "VSMONI".$cmd, "monitorOut");
		readingsBulkUpdate($hash, "monitorOut", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "resolution")
	{
		my $cmd = DENON_GetKey("VS", "SC", $a[2]);
		DENON_AVR_Write($hash, "VSSC".$cmd, "resolution");
		readingsBulkUpdate($hash, "resolution", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "resolutionHDMI")
	{
		my $cmd = DENON_GetKey("VS", "SCH", $a[2]);
		DENON_AVR_Write($hash, "VSSCH".$cmd, "resolutionHDMI");
		readingsBulkUpdate($hash, "resolutionHDMI", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "audioOutHDMI")
	{
		my $cmd = DENON_GetKey("VS", "AUDIO", $a[2]);
		DENON_AVR_Write($hash, "VSAUDIO".$cmd, "audioOutHDMI");
		readingsBulkUpdate($hash, "audioOutHDMI", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "videoProcessingMode")
	{
		my $cmd = DENON_GetKey("VS", "VPM", $a[2]);
		DENON_AVR_Write($hash, "VSVPM".$cmd, "videoProcessingMode");
		readingsBulkUpdate($hash, "videoProcessingMode", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}
	elsif ($a[1] eq "verticalStretch")
	{
		DENON_AVR_Write($hash, "VSVST ".uc($a[2]), "verticalStretch");
		readingsBulkUpdate($hash, "verticalStretch", $a[2]);
		readingsEndUpdate($hash, 1);
		return undef;
	}		
	elsif ($a[1] eq "rawCommand")
	{
		my $cmd = $a[2];
		$cmd = $a[2]." ".$a[3] if defined $a[3];
		$cmd = $cmd." ".$a[4] if defined $a[4];
		DENON_AVR_Write($hash, $cmd, "rawCommand");
		readingsEndUpdate($hash, 1);
		return undef;		
	}
	elsif ($a[1] eq "stream")
	{
		my $cmd = $a[2];
		my $dlnaDevice = AttrVal( $name, "dlnaName", "" );
		my $dlnaStream = DENON_AVR_GetStream($cmd, "url");
		if($dlnaDevice ne "" && $dlnaStream ne "")
		{
			fhem("set $dlnaDevice stream $dlnaStream");
			readingsBulkUpdate($hash, "currentStream", $cmd);
			readingsEndUpdate($hash, 1);
		}
		return undef;		
	}
	else
	{
		if(exists $DENON_db->{'MN'}{$a[1]}) #system remote
		{
			my $remote = DENON_GetValue('MN', $a[1]);	
			DENON_AVR_Write($hash, "MN".$remote, "remoteControl");	
			readingsEndUpdate($hash, 1);
			return undef;
		}
		elsif(exists $DENON_db->{'NS'}{$a[1]}) #media remote
		{
			my $remote = DENON_GetValue('NS', $a[1]);	
			DENON_AVR_Write($hash, "NS".$remote, "remoteControl");
			readingsBulkUpdate($hash, "playStatus", 'paused') if($a[1] eq "pause");
			readingsBulkUpdate($hash, "playStatus", 'playing') if($a[1] eq "play");
			readingsBulkUpdate($hash, "playStatus", 'stopped') if($a[1] eq "stop");
			readingsEndUpdate($hash, 1);
			return undef;
		}
		elsif($a[1] =~ /^main_(on|off)$/)
		{
			fhem("set $name zoneMain $1");
		}
		else
		{
			readingsEndUpdate($hash, 1);
			return $usage;
		}
	}
}

#####################################
sub
DENON_AVR_Shutdown($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "DENON_AVR $name: called Shutdown.";
}

#####################################
sub 
DENON_AVR_UpdateConfig($)
{
	# this routine is called 5 sec after the last define of a restart
	# this gives FHEM sufficient time to fill in attributes
	# it will also be called after each manual definition
	# Purpose is to parse attributes and read config
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	if (AttrVal($name, "webCmd", "na") eq "na")
	{
		$attr{$name}{webCmd} = "volume:mute:input:surroundMode";
	}
	
	DENON_AVR_Command_StatusRequest($hash);
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "presence", "present");
	
	if ( defined($modules{DENON_AVR_ZONE}{defptr}{$name}{2}) || defined($modules{DENON_AVR_ZONE}{defptr}{$name}{3}) || defined($modules{DENON_AVR_ZONE}{defptr}{$name}{4}))
	{
		Log3 $name, 5, "DENON_AVR $name: Dispatching state change to slaves";
		Dispatch( $hash, "presence present", undef);
	}
	
	if (ReadingsVal($name, "surroundMode", "na") eq "na")
	{
		readingsBulkUpdate($hash, "surroundMode", "Auto");
	}
	if (ReadingsVal($name, "setup", "na") eq "na")
	{
		readingsBulkUpdate($hash, "setup", "off");
	}
	if (ReadingsVal($name, "input", "na") eq "na")
	{
		$hash->{helper}{INPUT} = "Cbl/Sat";
	}
		
	my $deviceIP = $hash->{DeviceName}; 
	$deviceIP =~ /^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|[a-zA-Z0-9_-]+\.local):\d+$/;
	$hash->{helper}{deviceIP} = $1;
	
	readingsBulkUpdate($hash, "playStatus", 'stopped');
	readingsEndUpdate($hash, 1);
		
	my $connectionCheck = AttrVal($name, "connectionCheck", "60");	
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday() + $connectionCheck, "DENON_AVR_ConnectionCheck", $hash, 0);
	
	Log3 $name, 5, "DENON_AVR $name: called UpdateConfig.";
}

#####################################
sub 
DENON_AVR_ConnectionCheck($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	 
	Log3 $name, 5, "DENON_AVR $name: called ConnectionCheck.";
	my $connectionCheck = AttrVal($name, "connectionCheck", "60");
	
	if ($connectionCheck ne "off") {
	
		$hash->{STATE} = "opened";
	
		RemoveInternalTimer($hash, "DENON_AVR_ConnectionCheck");
	
		my $connState = DevIo_Expect( $hash, "PW?\r", $hash->{TIMEOUT} );
		  	
		if ( defined($connState) ) {
			# reset connectionCheck timer
			my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
			if ( $checkInterval ne "off" ) {
				my $next = gettimeofday() + $checkInterval;
				$hash->{helper}{nextConnectionCheck} = $next;
				InternalTimer( $next, "DENON_AVR_ConnectionCheck", $hash, 0 );
				
				my $avState = DENON_AVR_GetStateAV($hash);
				
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "stateAV", $avState) if(ReadingsVal( $name, "stateAV", "off") ne $avState);
				readingsEndUpdate($hash, 1);
			
				Log3 $name, 5, "DENON_AVR_ConnectionCheck $name: reset internal timer.";
			}
		}
	}
}

#####################################
sub
DENON_AVR_Command_SetPower($$)
{
	my ($hash, $power) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "DENON_AVR_Command $name: called SetPower";

	my $status = DENON_GetValue('PW', lc($power));

	DENON_AVR_Write($hash, 'PW'.$status, "power");
		
	readingsBulkUpdate($hash, "power", lc($power));
	readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
	readingsEndUpdate($hash, 1);
	
	if($status eq "ON")
	{
		DENON_AVR_Write($hash, "ZM?", "query");
	}
	
	return undef;
}

#####################################
sub
DENON_AVR_Command_SetMute($$)
{
	my ($hash, $mute) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "DENON_AVR  $name: called SetMute.";
	
	return "mute can only used when device is powered on" if (ReadingsVal( $name, "state", "off") eq "off");

	my $status = DENON_GetValue('MU', lc($mute));
	
	DENON_AVR_Write($hash, 'MU'.$status, "mute");
			
	readingsBulkUpdate($hash, "stateAV", DENON_AVR_GetStateAV($hash));
	readingsEndUpdate($hash, 1);

	return undef;
}

#####################################
sub
DENON_AVR_Command_SetInput($$$)
{
	my ($hash, $input, $friendlyName) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "DENON_AVR $name: called SetInput.";

	DENON_AVR_Write($hash, "SI".$input, "input");	
	readingsBulkUpdate($hash, "input", $friendlyName);
	$hash->{helper}{INPUT} = $input;
	
	if ($input =~ /^(TUNER|DVD|BD|TV|SAT\/CBL|GAME|AUX1|AUX2|AUX3|AUX4|AUX5|AUX6|AUX7)$/)
	{
		for(my $i = 0; $i < 9; $i++) {
			my $cur = "";
			if ($i == 2)
			{
				$cur = "s";
				my $status = DENON_GetValue('NSE', $i.$cur);
				if($status ne 'ignore'){
					readingsBulkUpdate($hash, $status, '-');
				}
				$cur = "a";
			}
			my $status = DENON_GetValue('NSE', $i.$cur);
			if($status ne 'ignore'){
				readingsBulkUpdate($hash, $status, '-');
			}
		}
	}
	readingsEndUpdate($hash, 1);
	return undef;
}


#####################################
sub
DENON_AVR_Command_SetVolume($$)
{
	my ($hash, $volume) = @_;
	my $name = $hash->{NAME};
		
	Log3 $name, 5, "DENON_AVR $name: called SetVolume.";
	
	if(ReadingsVal( $name, "state", "off") eq "off")
	{
		return "Volume can only set when device is powered on!";
	}
	else
	{		
		$hash->{helper}{volume} = $volume;
		if (($volume * 10) % 10 > 0)
		{
			$volume = sprintf ('%03d', ($volume * 10));
		}
		else
		{
			$volume = sprintf ('%02d', $volume);
		}
		DENON_AVR_Write($hash, "MV".$volume, "volume");
	}
	readingsEndUpdate($hash, 1);
	return undef;
}

#####################################
sub
DENON_AVR_Command_StatusRequest($)
{
 	my ($hash) = @_;
	
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "DENON_AVR $name: called StatusRequest.";
	
	DENON_AVR_Write($hash, "PW?", "query"); 				#power 
	DENON_AVR_Write($hash, "MU?", "query"); 				#mute
	DENON_AVR_Write($hash, "MV?", "query"); 				#mastervolume
	DENON_AVR_Write($hash, "SI?", "query"); 				#input select
	DENON_AVR_Write($hash, "MS?", "query"); 				#surround mode
	DENON_AVR_Write($hash, "NSP", "query"); 				#presetP - older models(<=2013)
	DENON_AVR_Write($hash, "ZM?", "query"); 				#main-zone
	DENON_AVR_Write($hash, "Z2?", "query"); 				#zone2
	DENON_AVR_Write($hash, "Z3?", "query"); 				#zone3
	if(defined($modules{DENON_AVR_ZONE}{defptr}{$name}{4}))
	{
		DENON_AVR_Write($hash, "Z4?", "query"); 
	}	
	DENON_AVR_Write($hash, "SLP?", "query"); 				#sleep main-zone
	DENON_AVR_Write($hash, "DIM ?", "query"); 				#dim display
	DENON_AVR_Write($hash, "ECO?", "query"); 				#eco-mode
	DENON_AVR_Write($hash, "STBY?", "query"); 				#standby
	
	DENON_AVR_Write($hash, "MSQUICK ?", "query"); 			#Quick select
	DENON_AVR_Write($hash, "MSSMART ?", "query"); 			#Smart select (Marantz)
	if(AttrVal($name, "type", "AVR") eq "Ceol")
	{
		DENON_AVR_Write($hash, "FV ?", "query");            #Favorite list (Ceol)
	}
	DENON_AVR_Write($hash, "MONI ?", "query");				#Monitor
	DENON_AVR_Write($hash, "MNMEN?", "query");				#menu
	DENON_AVR_Write($hash, "MNZST?", "query");				#All Zone Stereo
	DENON_AVR_Write($hash, "NSE", "query"); 				#Onscreen Display Information List
	DENON_AVR_Write($hash, "CV ?", "query"); 				#channel volume
	DENON_AVR_Write($hash, "SSINFFRM ?", "query"); 				#Firmware-Infos
#	DENON_AVR_Write($hash, "SR?", "query"); 				#record select - older models
  DENON_AVR_Write($hash, "SSVCTZMA ?", "query"); 				#channel volume new
	DENON_AVR_Write($hash, "SD?", "query"); 				#sound input mode
	DENON_AVR_Write($hash, "DC?", "query"); 				#digital input
	DENON_AVR_Write($hash, "SV?", "query"); 				#video select mode
	DENON_AVR_Write($hash, "TMAN?", "query");				#tuner
	DENON_AVR_Write($hash, "TR?", "query");					#Trigger Control
	DENON_AVR_Write($hash, "VSASP ?", "query"); 			#Aspect Ratio
	DENON_AVR_Write($hash, "VSSC ?", "query"); 				#Resolution
	DENON_AVR_Write($hash, "VSSCH ?", "query"); 			#Resolution (HDMI)
	DENON_AVR_Write($hash, "VSVPM ?", "query"); 			#Video Processing  Mode
	DENON_AVR_Write($hash, "VSVST ?", "query");				#Vertical Stretch
	DENON_AVR_Write($hash, "PSCINEMA EQ. ?", "query");	    #CINEMA EQ
	DENON_AVR_Write($hash, "PSLOM ?", "query");				#Loudness Management
	DENON_AVR_Write($hash, "PSMULTEQ: ?", "query");			#MULT EQ
	DENON_AVR_Write($hash, "PSDYNEQ ?", "query");			#DYNAMIC EQ
	DENON_AVR_Write($hash, "PSDYNVOL ?", "query");			#Dynamic Volume
	DENON_AVR_Write($hash, "PSLFC ?", "query");				#Audyssey LFC Status
	
	return "StatusRequest finished!";
}

#####################################
sub
DENON_AVR_GetStateAV($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, "presence", "absent" ) eq "absent" ) {
        return "absent";
    }
    elsif ( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        return "off";
    }
    elsif ( ReadingsVal( $name, "mute", "off" ) eq "on" ) {
        return "muted";
    }
	elsif (ReadingsVal( $name, "playStatus", "stopped" ) ne "stopped")
    {
        return ReadingsVal( $name, "playStatus", "stopped" );
    }
	elsif ( ReadingsVal( $name, "zoneMain", "off" ) eq "off" && ReadingsVal( $name, "power", "off" ) eq "on" ) {
        return "mainOff";
    }
    else {
        return ReadingsVal( $name, "power", "off" );
    }
}

sub
DENON_AVR_GetTimeStamp($)
{
	my ( $time ) = @_;	
	$time =  $time * 1000;
	return sprintf("%.0f", $time);
}

sub
DENON_AVR_GetSpanPlaytime($$) {
	my ( $time1, $time2 ) = @_;	
	my ($Ha, $Ma, $Sa, $Hb, $Mb, $Sb) = 0;
	
	if ($time1 =~ /^([0-9]{1,2}):([0-9]{2}):([0-9]{2})/)
	{
		$Ha = $1;
		$Ma = $2;
		$Sa = $3;
	}
	elsif ($time1 =~ /^([0-9]{1,2}):([0-9]{2})/)
	{
		$Ma = $1;
		$Sa = $2;
	}
	
	if ($time2 =~ /^([0-9]{1,2}):([0-9]{2}):([0-9]{2})/)
	{
		$Hb = $1;
		$Mb = $2;
		$Sb = $3;
	}
	elsif ($time2 =~ /^([0-9]{1,2}):([0-9]{2})/)
	{
		$Mb = $1;
		$Sb = $2;
	}
	
	my $timespan = (($Ha*3600) + ($Ma*60) + $Sa) - (($Hb*3600) + ($Mb*60) + $Sb);
	
	return $timespan;
}

#####################################
sub
DENON_AVR_PlaytimeCheck ($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
	my $playTime = AttrVal($name, "playTime", "off");
		
	RemoveInternalTimer($hash, "DENON_AVR_PlaytimeCheck");
	
	if ($playTime ne "off" && ReadingsVal($name, "playStatus", "stopped") ne "stopped")
	{
		InternalTimer(gettimeofday() + $playTime, "DENON_AVR_PlaytimeCheck", $hash, 0);
		DENON_AVR_Write($hash, "NSE", "query");		
		Log3 $name, 5, "DENON_AVR $name: called PlaytimeCheck";
	}
	else	
	{
		$hash->{helper}{isPause} = 0;
		fhem("sleep 8;get $name mediaInfo");
		Log3 $name, 5, "DENON_AVR $name: called PlaytimeCheck mediaInfo";
	}
}

#####################################
sub
DENON_AVR_PlaystatusCheck ($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
	my $time = ReadingsVal( $name, "currentPlaytime", "na");
	my $oldtime = defined($hash->{helper}{playTime}) ? $hash->{helper}{playTime} : "00:00:00";
	my $status = ReadingsVal($name, "playStatus", "stopped");
	
	my $timespan = 0;
	if ($time ne  "-")
	{
		$timespan = DENON_AVR_GetSpanPlaytime($time, $oldtime);
	}

	
	
	if (ReadingsVal($name, "playStatus", "stopped") ne "stopped")
	{			
		if ($timespan == 0)
		{
			readingsBulkUpdate($hash, "playStatus", "paused") if($status ne "paused");
		}
		else
		{
			readingsBulkUpdate($hash, "playStatus", "playing") if($status ne "playing");
		}
		
		if ($time eq  "-")
		{
			readingsBulkUpdate($hash, "playStatus", "stopped");
		}
	}
	else
	{
		if ($hash->{helper}{playTimeCheck} == 0)
		{
			readingsBulkUpdate($hash, "playStatus", 'stopped') if($status ne "stopped");
		}
		else
		{
			readingsBulkUpdate($hash, "playStatus", 'playing')  if($status ne "playing");
			readingsBulkUpdate($hash, "currentPlaytime", '0:00');
		}
	}
	
	if ($hash->{helper}{playTimeCheck} == 1)
	{
		$hash->{helper}{playTime} = $time if ($time ne "-");
	}
}

#####################################
sub 
DENON_AVR_GetStream($$) {
	my ( $name, $mode ) = @_;

	my $file = "./FHEM/Denon.streams";
	my $return = "";
	open( my $handle, "<", $file ) || return $return;
	while(<$handle>){
		$_ =~ /^(.+)<>(.+)/;
		if ($mode eq "url")
		{
			if($1 eq $name)
			{
				$return = $2;
				last;  
			}
		}
		elsif ($mode eq "list")
		{
			$return .= $1 . ",";
		}
	}
	close( $handle );
	
	if ($mode eq "list")
	{
		chop($return);
	}
	Log3 $name, 5, "DENON_AVR $name GetStream: $return";
    return $return;
}

#####################################
sub 
DENON_AVR_SetFavorite($$) {
	my ( $name, $fav ) = @_;

		fhem("set $name input Favorites");

		my $sleep = AttrVal($name, "sleep", 5);
		my $command = "sleep $sleep;";
		
		if ($fav > 1)
		{
			for(my $i = 1; $i < $fav; $i++) {
				$command .= "set $name remoteControl down;sleep 0.5;";
			}
		}
		$command .= "set $name remoteControl play";
		
		fhem("$command");
		
		Log3 $name, 5, "DENON_AVR $name SetFavorite: $command";
		
    return;
}

#####################################
sub 
DENON_AVR_SetUsedInputs($$) {
	my ($hash, $usedInputs) = @_;
	my $name = $hash->{NAME};
	my @inputs = split(/,/,$usedInputs);
	my @denonInputs = ();
	
	foreach (@inputs)
	{
		if(exists $DENON_db->{'SI'}{$_})
		{
			push(@denonInputs, $_);			
		}
	}
	$attr{$name}{inputs} = join(",", @denonInputs);
}

#####################################
sub 
DENON_AVR_Make_Zone($$) {
	my ( $name, $zone ) = @_;
	if(!defined($defs{$name}))
	{
		fhem("define $name Denon_AVR_ZONE $zone");
	}
		
    Log3 $name, 3, "DENON_AVR $name: create Denon_AVR_ZONE $zone.";
    return "Denon_AVR_ZONE $name created by DENON_AVR";
}

#####################################
sub 
DENON_AVR_Delete_Zone($$) {
	my ( $name, $zone ) = @_;
	if(defined($defs{$name}))
	{
		fhem("delete $name");
	}
	
    Log3 $name, 3, "DENON_AVR $name: delete Denon_AVR_ZONE $zone.";
    return "Denon_AVR_ZONE $name deleted by DENON_AVR";
}

#####################################
sub 
DENON_AVR_RCmakenotify($$) {
    my ( $name, $ndev ) = @_;
    my $nname = "notify_$name";

    fhem( "define $nname notify $name set $ndev remoteControl " . '$EVENT', 1 );
    Log3 $name, 3, "DENON_AVR $name: create notify for remoteControl.";
    return "Notify created by DENON_AVR $nname";
}

#####################################
sub 
DENON_AVR_RCmake($) {
	my ( $name ) = @_;
	if(!defined($defs{"Denon_AVR_RC_" . $name}))
	{
		fhem("define Denon_AVR_RC_$name remotecontrol");
		fhem("sleep 1;set Denon_AVR_RC_$name layout DENON_AVR_RC");
		
		if(!defined($defs{"notify_Denon_AVR_RC_" . $name}))
		{
			fhem("sleep 1;set Denon_AVR_RC_$name makenotify $name");
		}
	}
	
    Log3 $name, 3, "DENON_AVR $name: create remoteControl.";
    return "Remotecontrol created by DENON_AVR $name";
}

#####################################
sub 
DENON_AVR_RCdelete($) {
	my ( $name ) = @_;
	if(defined($defs{"Denon_AVR_RC_" . $name}))
	{
		fhem("delete Denon_AVR_RC_" . $name);
		
		if(defined($defs{"notify_Denon_AVR_RC_" . $name}))
		{
			fhem("sleep 1;delete notify_Denon_AVR_RC_$name");
		}
	}
	
    Log3 undef, 3, "DENON_AVR $name: delete remoteControl.";
    return "Remotecontrol deleted by DENON_AVR: $name";
}

#####################################
sub DENON_AVR_RClayout() {
    my @row;
	
	$row[0] = "info:INFO,:blank,up:CHUP,:blank,option:OPTION,:blank,volumeUp:VOLUP,:blank,sm_Movie:MOVIE,sm_Music:MUSIC,sm_Game:GAME,sm_Pure:PURE,:blank,play:PLAY,:blank,toggle:POWEROFF3";
	$row[1] = ":blank,left:LEFT,enter:ENTER3,right:RIGHT,:blank,:blank,muteT:MUTE,:blank,in_Cbl/Sat:CBLSAT,in_Blu-Ray:BR,in_DVD:DVD,in_CD:CD,:blank,pause:PAUSE";
	$row[2] = "return:RETURN,:blank,down:CHDOWN,:blank,setup:SETUP,:blank,volumeDown:VOLDOWN,:blank,in_Mediaplayer:MEDIAPLAYER,in_iRadio:IRADIO,in_OnlineMusic:ONLINEMUSIC,in_Usb/iPod:IPODUSB,:blank,stop:STOP,:blank,eco:ECO";
	$row[3] = "attr rc_iconpath icons/remotecontrol";
	$row[4] = "attr rc_iconprefix black_btn_";
	
    return @row;
}
 
1;


=pod
=item device
=item summary control for DENON (Marantz) AV receivers via network or serial connection
=item summary_DE Steuerung von DENON (Marantz) AV Receivern per LAN oder RS-232
=begin html


	<p>
		<a name="DENON_AVR" id="DENON_AVR"></a>
	</p>
	<h3>
		DENON_AVR
	</h3>
	<ul>
		<a name="DENON_AVRdefine" id="DENON_AVRdefine"></a> <b>Define</b>
		<ul>
			<code>define &lt;name&gt; DENON_AVR &lt;ip-address-or-hostname[:PORT]&gt;</code><br>
			<code>define &lt;name&gt; DENON_AVR &lt;devicename[@baudrate]&gt;</code><br>
			<br>
			This module controls DENON (Marantz) A/V receivers in real-time via network connection.<br>
			<br>
			Instead of IP address or hostname you may set a serial connection format for direct connectivity.<br>
			<br>
			Example:<br>
			<br>
			<ul>
				<code>
					define avr DENON_AVR 192.168.0.10<br>
					<br>
					# With explicit port<br>
					define avr DENON_AVR 192.168.0.10:23<br>
					<br>
					# With serial connection<br>
					define avr DENON_AVR /dev/ttyUSB0@9600
				</code>
			</ul>
		</ul><br>
		<br>
		<a name="DENON_AVRset" id="DENON_AVRset"></a> <b>Set</b>
		<ul>
			<code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
			<br>
			Currently, the following commands are defined:<br>
			<ul>
				<li>
					<b>allZoneStereo</b> &nbsp;&nbsp;-&nbsp;&nbsp; set allZoneStereo on/off
				</li>
				<li>
					<b>audysseyLFC</b> &nbsp;&nbsp;-&nbsp;&nbsp; set audysseyLFC on/off
				</li>
				<li>
					<b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; set auto standby (off, 15,30,60 min)
				</li>
				<li>
					<b>bass</b> &nbsp;&nbsp;-&nbsp;&nbsp; adjust bass level
				</li>
				<li>
					<b>channelVolume</b> &nbsp;&nbsp;-&nbsp;&nbsp; adjust channel volume level for active speakers (up/down),<br>
					&nbsp;to reset all channel level use FactoryDefaults<br>
					&nbsp;Example to adjust volume level via command line: <b>set avr channelVolume FrontLeft -1</b><br>
					&nbsp;(possible values -12 to 12)
				</li>
				<li>
					<b>cinemaEQ</b> &nbsp;&nbsp;-&nbsp;&nbsp; set cinemaEQ on/off
				</li>
				<li>
					<b>display</b> &nbsp;&nbsp;-&nbsp;&nbsp; controls display dim state
				</li>
				<li>
					<b>dynamicEQ</b> &nbsp;&nbsp;-&nbsp;&nbsp; set dynamicEQ on/off
				</li>
				<li>
					<b>dynamicVolume</b> &nbsp;&nbsp;-&nbsp;&nbsp; set dynamicEQ off/light/medium/heavy
				</li>
				<li>
					<b>eco</b> &nbsp;&nbsp;-&nbsp;&nbsp; controls eco state
				</li>
				<li>
					<b>favorite</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between favorite (only older models)
				</li>
				<li>
					<b>favoriteList</b> &nbsp;&nbsp;-&nbsp;&nbsp; select entries in favorite list (workaround for new models >= 2014),<br>
					&nbsp;it is recommended to use set stream in combination with module 98_DLNARenderer!
				</li>
				<li>
					<b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between inputs
				</li>
				<li>
					<b>loudness</b> &nbsp;&nbsp;-&nbsp;&nbsp; set loudness on/off
				</li>
				<li>
					<b>lowFrequencyEffect</b> &nbsp;&nbsp;-&nbsp;&nbsp; adjust LFE level (-10 to 0)
				</li>
				<li>
					<b>multiEQ</b> &nbsp;&nbsp;-&nbsp;&nbsp; set multiEQ off/reference/bypassLR...
				</li>
				<li>
					<b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute
				</li>
				<li>
					<b>muteT</b> &nbsp;&nbsp;-&nbsp;&nbsp; toggle mute state
				</li>
				<li>
					<b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
				</li>
				<li>
					<b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device
				</li>
				<li>
					<b>preset</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between presets (1-3, only older models)
				</li>
				<li>
					<b>presetCall</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between presets (00-35, 00-55 older models)
				</li>
				<li>
					<b>presetMemory</b> &nbsp;&nbsp;-&nbsp;&nbsp; save presets (00-35, 00-55 older models, for alphanumeric mode A1-G8 set attribute "presetMode" to "alphanumeric")
				</li>
				<li>
					<b>quickselect</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between quick select modes (1-5, only new models)
				</li>
				<li>
					<b>rawCommand</b> &nbsp;&nbsp;-&nbsp;&nbsp;  send raw command to AV receiver
				</li>
				<li>
					<b>reconnect</b> &nbsp;&nbsp;-&nbsp;&nbsp;  reconnect AV receiver
				</li>
				<li>
					<b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp;  remote commands (play, stop, pause,...)
				</li>
				<li>
					<b>setup</b> &nbsp;&nbsp;-&nbsp;&nbsp; onscreen setup on/off
				</li>
				<li>
					<b>sleep</b> &nbsp;&nbsp;-&nbsp;&nbsp; set sleep timer (off/10 to 120 min)
				</li>
				<li>
					<b>smartselect</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between smart select modes (1-5, only Marantz, to activate set attribute brand to Marantz)
				</li>
				<li>
					<b>stream</b> &nbsp;&nbsp;-&nbsp;&nbsp; send stream adress via module 98_DLNARenderer to reciever; the user has to create a file "Denon.streams" in folder "fhem/FHEM"<br>
					<br>list format:<br>
					<code>
						Rockantenne<>http://mp3channels.webradio.antenne.de/rockantenne<br>
						Bayern3<>http://streams.br.de/bayern3_2.m3u<br>
						JamFM<>http://www.jam.fm/streams/jam-nmr-mp3.m3u<br>
					</code>
					<br>The attribut "dlnaName" must be set to the name of the reciever in DLNARenderer module.<br>
				</li>
				<li>
					<b>surroundMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; set surround mode
				</li>
				<li>
					<b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off
				</li>
				<li>
					<b>treble</b> &nbsp;&nbsp;-&nbsp;&nbsp; adjust treble level
				</li>
				<li>
					<b>trigger1</b> &nbsp;&nbsp;-&nbsp;&nbsp; set trigger1 on/off
				</li>
				<li>
					<b>trigger2</b> &nbsp;&nbsp;-&nbsp;&nbsp; set trigger2 on/off
				</li>
				<li>
					<b>tuner</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between AM and FM
				</li>
				<li>
					<b>tunerPreset</b> &nbsp;&nbsp;-&nbsp;&nbsp; switches between tuner presets (1-56)
				</li>
				<li>
					<b>tunerPresetMemory</b> &nbsp;&nbsp;-&nbsp;&nbsp; save tuner presets (1-56)
				</li>
				<li>
					<b>usedInputs</b> &nbsp;&nbsp;-&nbsp;&nbsp; set used inputs manually if needed (e.g. us model)
				</li>
				<li>
					<b>volume</b> 0...98 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage
				</li>
				<li>
					<b>volumeStraight</b> -80...18 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in dB
				</li>
				<li>
					<b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level
				</li>
				<li>
					<b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level
				</li>
			</ul>
		</ul><br>
		<br>
		<a name="DENON_AVRget" id="DENON_AVRget"></a> <b>Get</b>
		<ul>
			<code>get &lt;name&gt; &lt;what&gt;</code><br>
			<br>
			Currently, the following commands are defined:<br>
			<ul>
				<li>
					<b>disconnect</b> &nbsp;&nbsp;-&nbsp;&nbsp; disconnect AV receiver
				</li>
				<li>
					<b>mediaInfo</b> &nbsp;&nbsp;-&nbsp;&nbsp; refresh current media infos
				</li>
				<li>
					<b>reconnect</b> &nbsp;&nbsp;-&nbsp;&nbsp; reconnect AV receiver
				</li>
				<li>
					<b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; autocreate remote ccontrol
				</li>
				<li>
					<b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; refresh status
				</li>
				<li>
					<b>some readings</b> &nbsp;&nbsp;-&nbsp;&nbsp; see list below
				</li>
				<li>
					<b>zone</b> &nbsp;&nbsp;-&nbsp;&nbsp; autocreate zones
				</li>
			</ul>
			<br>
			<b>Generated Readings/Events:</b><br>
			<br>
			The AV reciever sends some readings only if settings (e.g. ampAssign) have changed<br> 
			or the reciever has been disconnected (power supply) for more than 5 min and connected again.<br>
			<br>
			<ul>
				<li>
					<b>ampAssign</b> &nbsp;&nbsp;-&nbsp;&nbsp; amplifier settings for AV receiver (5.1, 7.1, 9.1,...)
				</li>
				<li>
					<b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; auto standby state
				</li>
				<li>
					<b>bass</b> &nbsp;&nbsp;-&nbsp;&nbsp; bass level in dB
				</li>
				<li>
					<b>currentAlbum</b> &nbsp;&nbsp;-&nbsp;&nbsp; current album (mediaplayer, online music,...)
				</li>
				<li>
					<b>currentArtist</b> &nbsp;&nbsp;-&nbsp;&nbsp; current artist (mediaplayer, online music,...)
				</li>
				<li>
					<b>currentBitrate</b> &nbsp;&nbsp;-&nbsp;&nbsp; current bitrate (mediaplayer, online music,...)
				</li>
				<li>
					<b>currentMedia</b> &nbsp;&nbsp;-&nbsp;&nbsp; current media (mediaplayer, online music,...)
				</li>
				<li>
					<b>currentStation</b> &nbsp;&nbsp;-&nbsp;&nbsp; current station (online radio)
				</li>
				<li>
					<b>currentTitle</b> &nbsp;&nbsp;-&nbsp;&nbsp; current title (mediaplayer, online music,...)
				</li>
				<li>
					<b>display</b> &nbsp;&nbsp;-&nbsp;&nbsp; dim state of display
				</li>
				<li>
					<b>dynamicCompression</b> &nbsp;&nbsp;-&nbsp;&nbsp; dynamic compression state
				</li>
				<li>
					<b>eco</b> &nbsp;&nbsp;-&nbsp;&nbsp; eco state
				</li>
				<li>
					<b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; selected input
				</li>
				<li>
					<b>level[speaker]</b> &nbsp;&nbsp;-&nbsp;&nbsp; [speaker] level in dB (e.g. levelFrontRight)
				</li>
				<li>
					<b>lowFrequencyEffects</b> &nbsp;&nbsp;-&nbsp;&nbsp;  low frequency effects (LFE) state
				</li>
				<li>
					<b>mute</b> &nbsp;&nbsp;-&nbsp;&nbsp; mute state
				</li>
				<li>
					<b>playStatus</b> &nbsp;&nbsp;-&nbsp;&nbsp; current playStatus (playing/paused/stopped)
				</li>
				<li>
					<b>power</b> &nbsp;&nbsp;-&nbsp;&nbsp; power state
				</li>
				<li>
					<b>samplingRate</b> &nbsp;&nbsp;-&nbsp;&nbsp; sampling rate
				</li>
				<li>
					<b>signal</b> &nbsp;&nbsp;-&nbsp;&nbsp; input signal sound
				</li>
				<li>
					<b>sound</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual sound type
				</li>
				<li>
					<b>state</b> &nbsp;&nbsp;-&nbsp;&nbsp; state of AV reciever (on,off,disconnected)
				</li>
				<li>
					<b>stateAV</b> &nbsp;&nbsp;-&nbsp;&nbsp; state of AV reciever (on,off,absent,mute)
				</li>
				<li>
					<b>surroundMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual surround mode (Auto, Stereo, Music,...)
				</li>
				<li>
					<b>toneControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; tone control state
				</li>
				<li>
					<b>treble</b> &nbsp;&nbsp;-&nbsp;&nbsp; treble level in dB
				</li>
				<li>
					<b>tuner[Information]</b> &nbsp;&nbsp;-&nbsp;&nbsp; tuner settings [Band, Frequency, Mode, Preset]
				</li>
				<li>
					<b>videoSelect</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual video select mode
				</li>
				<li>
					<b>volume</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual volume
				</li>
				<li>
					<b>volumeMax</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual maximum volume
				</li>
				<li>
					<b>volumeStraight</b> &nbsp;&nbsp;-&nbsp;&nbsp; actual volume straight
				</li>
				<li>
					<b>zone</b> &nbsp;&nbsp;-&nbsp;&nbsp; state of aviable zones (on/off)
				</li>
			</ul>
			<br>
			<b>Attributes</b><br>
			<br>
			<ul>
				<li>
					<b>brand</b> &nbsp;&nbsp;-&nbsp;&nbsp; brand of  AV receiver (Denon/Marantz) - to activate smartselect set attribute brand to Marantz
				</li>
				<li>
					<b>connectionCheck</b> &nbsp;&nbsp;-&nbsp;&nbsp; time to next connection check
				</li>
				<li>
					<b>disable</b> &nbsp;&nbsp;-&nbsp;&nbsp;  defined device on/off
				</li>
				<li>
					<b>dlnaName</b> &nbsp;&nbsp;-&nbsp;&nbsp; name of Reciever in DLNARenderer module
				</li>
				<li>
					<b>favorites</b> &nbsp;&nbsp;-&nbsp;&nbsp; max entries for favorites
				</li>	
				<li>
					<b>maxFavorites</b> &nbsp;&nbsp;-&nbsp;&nbsp; max entries in favorite list for "set favoriteList"
				</li>
				<li>
					<b>maxPreset</b> &nbsp;&nbsp;-&nbsp;&nbsp; max entries in preset list
				</li>					
				<li>
					<b>playTime</b> &nbsp;&nbsp;-&nbsp;&nbsp; timespan to next playtime check (off, 1-60 sec)
				</li>
				<li>
					<b>presetMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; preset list mode (numeric [00-55] or alphanumeric [A1-G8])
				</li>
				<li>
					<b>sleep</b> &nbsp;&nbsp;-&nbsp;&nbsp; break between commands for use with "set favoriteList"
				</li>
				<li>
					<b>timeout</b> &nbsp;&nbsp;-&nbsp;&nbsp; number of connection attempts
				</li>
				<li>
					<b>type</b> &nbsp;&nbsp;-&nbsp;&nbsp; reciever type (AVR oder Ceol), steps for volumeslider (0.5 or 1)
				</li>
				<li>
					<b>unit</b> &nbsp;&nbsp;-&nbsp;&nbsp; de-/activate units for readings (on or off)
				</li>
			</ul>
		</ul>
	</ul>	

=end html


=begin html_DE


	<p>
		<a name="DENON_AVR" id="DENON_AVR"></a>
	</p>
	<h3>
		DENON_AVR
	</h3>
	<ul>
		<a name="DENON_AVRdefine" id="DENON_AVRdefine"></a> <b>Define</b>
		<ul>
			<code>define &lt;name&gt; DENON_AVR &lt;ip-address-or-hostname[:PORT]&gt;</code><br>
			<code>define &lt;name&gt; DENON_AVR &lt;devicename[@baudrate]&gt;</code><br>
			<br>
			Dieses Modul steuert DENON (Marantz) A/V-Receiver &uuml;ber das Netzwerk.<br>
			<br>
			 Anstatt der IP-Addresse oder dem Hostnamen kann eine serielle Schnittstelle angegeben werden.<br>
			<br>
			Beispiele:<br>
			<br>
			<ul>
				<code>
					define avr DENON_AVR 192.168.0.10<br>
					<br>
					# Unter Angabe eines bestimmten Ports<br>
					define avr DENON_AVR 192.168.0.10:23<br>
					<br>
					# Mit serieller Schnittstelle<br>
					define avr DENON_AVR /dev/ttyUSB0@9600
				</code>
			</ul>
		</ul><br>
		<br>
		<a name="DENON_AVRset" id="DENON_AVRset"></a> <b>Set</b>
		<ul>
			<code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
			<br>
			Momentan sind folgende Befehle verf&uuml;gbar:<br>
			<ul>
			
				<li>
					<b>allZoneStereo</b> &nbsp;&nbsp;-&nbsp;&nbsp; allZoneStereo an/aus
				</li>
				<li>
					<b>audysseyLFC</b> &nbsp;&nbsp;-&nbsp;&nbsp; audysseyLFC an/aus
				</li>			
				<li>
					<b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; Zeit f&uuml;r den Auto-Standby setzen
				</li>
				<li>
					<b>bass</b> &nbsp;&nbsp;-&nbsp;&nbsp; Bass-Pegel einstellen
				</li>
				<li>
					<b>channelVolume</b> &nbsp;&nbsp;-&nbsp;&nbsp; Lautst&auml;rkepegel der aktiven Lautsprecher schrittweise setzen (up/down)<br>
					&nbsp;Um alle Einstellungen zur&uuml;ckzusetzen, kann <b>FactoryDefaults</b> verwendet werden.<br>
					&nbsp;Beispiel, wie der Lautst&auml;rkepegel direkt &uuml;ber die Kommandozeile gesetzt wird: <b>set avr channelVolume FrontLeft -1</b><br>
					&nbsp;(m&ouml;gliche Werte sind -12 bis 12)
				</li>				
				<li>
					<b>cinemaEQ</b> &nbsp;&nbsp;-&nbsp;&nbsp; cinemaEQ an/aus
				</li>
				<li>
					<b>display</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der &quot;Dim-Modi&quot; des Displays
				</li>
				<li>
					<b>dynamicEQ</b> &nbsp;&nbsp;-&nbsp;&nbsp; dynamicEQ an/aus
				</li>
				<li>
					<b>dynamicVolume</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wert f&uuml;r dynamicEQ setzen (off/light/medium/heavy)
				</li>
				<li>
					<b>eco</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl des Eco-Modus
				</li>				
				<li>
					<b>favorite</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Favoriten (nur alte Modelle)
				</li>	
				<li>
					<b>favoriteList</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Favoriten aus der Listenansicht (Workaround f&uuml;r Modelle >= 2014)<br>
					&nbsp;Es wird emfohlen den Set-Befehl stream in Kombination mit dem Modul 98_DLNARenderer zu verwenden!
				</li>				
				<li>
					<b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Eing&auml;nge
				</li>
				<li>
					<b>loudness</b> &nbsp;&nbsp;-&nbsp;&nbsp; Loudness an/aus
				</li>				
				<li>
					<b>lowFrequencyEffect</b> &nbsp;&nbsp;-&nbsp;&nbsp; LFE-Pegel einstellen (-10 to 0)
				</li>
				<li>
					<b>multiEQ</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wert f&uuml;r multiEQ setzen (off/reference/bypassLR...)
				</li>
				<li>
					<b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; AV-Receiver laut/stumm schalten
				</li>
				<li>
					<b>muteT</b> &nbsp;&nbsp;-&nbsp;&nbsp; zwischen laut und stumm wechseln
				</li>
				<li>
					<b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; Standby AV-Receiver
				</li>
				<li>
					<b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; AV-Receiver anschalten
				</li>
				<li>
					<b>preset</b> &nbsp;&nbsp;-&nbsp;&nbsp; zwischen Voreinstellungen (1-3, nur alte Modelle) wechseln
				</li>
				<li>
					<b>presetCall</b> &nbsp;&nbsp;-&nbsp;&nbsp; zwischen Voreinstellungen (00-35, 00-55 alte Modelle) wechseln
				</li>
				<li>
					<b>presetMemory</b> &nbsp;&nbsp;-&nbsp;&nbsp; Voreinstellungen speichern (00-35, 00-55 alte Modelle, f&uuml;r Aktivierung der alphanumerschen Liste A1-G8 das Attribut presetMode auf alphanumeric setzen)
				</li>
				<li>
					<b>quickselect</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der &quot;Quick-Select&quot; Modi (1-5, nur neue Modelle)
				</li>
				<li>
					<b>rawCommand</b> &nbsp;&nbsp;-&nbsp;&nbsp; schickt ein &quot;raw command&quot; zum AV-Receiver
				</li>
				<li>
					<b>reconnect</b> &nbsp;&nbsp;-&nbsp;&nbsp; stellt die Verbindung zum AV-Receivers wieder her
				</li>
				<li>
					<b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; Fernbedienungsbefehle (play, stop, pause,...)
				</li>
				<li>
					<b>setup</b> &nbsp;&nbsp;-&nbsp;&nbsp; Anzeige Onscreen-Setup an/aus
				</li>
				<li>
					<b>sleep</b> &nbsp;&nbsp;-&nbsp;&nbsp; Sleep-Timer (aus/10 bis 120 min)
				</li>
				<li>
					<b>smartselect</b> &nbsp;&nbsp;-&nbsp;&nbsp; Smart-Select Modus w&auml;hlen (1-5, nur Marantz, f&uuml;r Aktivierung das Attribut brand auf Marantz setzen)
				</li>
				<li>
					<b>stream</b> &nbsp;&nbsp;-&nbsp;&nbsp; Aufruf von Streams &uuml;ber Modul 98_DLNARenderer; eine Datei "Denon.streams" mit einer Liste von Streams muss im Ordner "fhem/FHEM" selbst angelegt werden.<br>
					<br>Format der Liste:<br>
					<code>
						Rockantenne<>http://mp3channels.webradio.antenne.de/rockantenne<br>
						Bayern3<>http://streams.br.de/bayern3_2.m3u<br>
						JamFM<>http://www.jam.fm/streams/jam-nmr-mp3.m3u<br>
					</code>
					<br>Der Name des Recievers aus dem DLNARenderer-Modul muss als Attribut "dlnaName" im Denon-Modul gesetzt werden.<br>
				</li>				
				<li>
					<b>surroundMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur Auswahl der Surround-Modi
				</li>
				<li>
					<b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; AV-Receiver an/aus
				</li>
				<li>
					<b>treble</b> &nbsp;&nbsp;-&nbsp;&nbsp; H&ouml;hen-Pegel einstellen
				</li>
				<li>
					<b>trigger1</b> &nbsp;&nbsp;-&nbsp;&nbsp; trigger1 an/aus
				</li>
				<li>
					<b>trigger2</b> &nbsp;&nbsp;-&nbsp;&nbsp; trigger2 an/aus
				</li>
				<li>
					<b>tuner</b> &nbsp;&nbsp;-&nbsp;&nbsp; zwischen AM und FM wechseln
				</li>
				<li>
					<b>tunerPreset</b> &nbsp;&nbsp;-&nbsp;&nbsp; zwischen Radio Voreinstellungen (1-56) wechseln
				</li>
				<li>
					<b>tunerPresetMemory</b> &nbsp;&nbsp;-&nbsp;&nbsp; Radio Voreinstellungen (1-56) speichern
				</li>
				<li>
					<b>usedInputs</b> &nbsp;&nbsp;-&nbsp;&nbsp; zur manuellen Auswahl der genutzten Eing&auml;nge (z.B. AUX-Ausg&auml;nge hinzuf&uuml;gen/enfernen)
				</li>
				<li>
					<b>volume</b> 0...98 &nbsp;&nbsp;-&nbsp;&nbsp; Lautst&auml;rke in Prozent
				</li>
				<li>
					<b>volumeStraight</b> -80...18 &nbsp;&nbsp;-&nbsp;&nbsp; absolute Lautst&auml;rke in dB
				</li>
				<li>
					<b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; erh&ouml;ht Lautst&auml;rke
				</li>
				<li>
					<b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; verringert Lautst&auml;rke
				</li>
			</ul>
		</ul><br>
		<br>
		<a name="DENON_AVRget" id="DENON_AVRget"></a> <b>Get</b>
		<ul>
			<code>get &lt;name&gt; &lt;what&gt;</code><br>
			<br>
			Momentan sind folgende Befehle verf&uuml;gbar:<br>
			<ul>
				<li>
					<b>disconnect</b> &nbsp;&nbsp;-&nbsp;&nbsp; Verbindung zum AV receiver trennen
				</li>
				<li>
					<b>mediaInfo</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle Medieninformationen abrufen
				</li>
				<li>
					<b>reconnect</b> &nbsp;&nbsp;-&nbsp;&nbsp; Verbindung zum AV receiver wiederherstellen
				</li>
				<li>
					<b>remoteControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; Fernbedienung automatisch erzeugen lassen
				</li>
				<li>
					<b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status neu laden
				</li>
				<li>
					<b>diverse Readings</b> &nbsp;&nbsp;-&nbsp;&nbsp; siehe Liste unten
				</li>
				<li>
					<b>zone</b> &nbsp;&nbsp;-&nbsp;&nbsp; Zonen automatisch erzeugen lassen
				</li>
			</ul>
			<br>
			<b>Erzeugte Readings/Events:</b><br>
			<br>
			Einige Statusmeldungen werden vom AV-Reciever nur gesendet, wenn die entsprechende<br> 
			Einstellung (z.B. ampAssign) ge&auml;ndert wird oder der Reciever wieder ans Stromnetz<br>
			angeschlossen wird (muss ca. 5 min vom Strom getrennt sein!).<br>
			<br>
			<ul>
				<li>
					<b>ampAssign</b> &nbsp;&nbsp;-&nbsp;&nbsp; Endstufenzuweisung des AV-Receiver (5.1, 7.1, 9.1,...)
				</li>
				<li>
					<b>autoStandby</b> &nbsp;&nbsp;-&nbsp;&nbsp; Standbyzustand des AV-Recievers
				</li>
				<li>
					<b>bass</b> &nbsp;&nbsp;-&nbsp;&nbsp; Bass-Level in dB
				</li>
				<li>
					<b>currentAlbum</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelles Album (Mediaplayer, Online Music,...)
				</li>
				<li>
					<b>currentArtist</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktueller K&uuml;nstler (Mediaplayer, Online Music,...)
				</li>
				<li>
					<b>currentBitrate</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle Bitrate (Mediaplayer, Online Music,...)
				</li>
				<li>
					<b>currentMedia</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle Quelle (Mediaplayer, Online Music,...)
				</li>
				<li>
					<b>currentStation</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktueller Sender (Online Radio)
				</li>
				<li>
					<b>currentTitle</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktueller Titel (Mediaplayer, Online Music,...)
				</li>
				<li>
					<b>display</b> &nbsp;&nbsp;-&nbsp;&nbsp; Dim-Status des Displays
				</li>
				<li>
					<b>dynamicCompression</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status der dynamischen Kompression
				</li>
				<li>
					<b>eco</b> &nbsp;&nbsp;-&nbsp;&nbsp; Eco-Status
				</li>
				<li>
					<b>input</b> &nbsp;&nbsp;-&nbsp;&nbsp; gew&auml;hlte Eingangsquelle
				</li>
				<li>
					<b>levelFrontLeft</b> &nbsp;&nbsp;-&nbsp;&nbsp; Pegel des linken Frontlautsprechers in dB 
				</li>
				<li>
					<b>levelFrontRight</b> &nbsp;&nbsp;-&nbsp;&nbsp; Pegel des rechten Frontlautsprechers in dB 
				</li>
				<li>
					<b>lowFrequencyEffects</b> &nbsp;&nbsp;-&nbsp;&nbsp;  LFE-Status (low frequency effect)
				</li>
				<li>
					<b>mute</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status der Stummschaltung
				</li>
				<li>
					<b>power</b> &nbsp;&nbsp;-&nbsp;&nbsp; Einschaltzustand des AV-Recievers
				</li>
				<li>
					<b>samplingRate</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle Sampling-Rate
				</li>
				<li>
					<b>signal</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuell anliegendes Eingangssignal
				</li>
				<li>
					<b>sound</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktueller Sound-Modus
				</li>
				<li>
					<b>state</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status des AV-Recievers (on,off,disconnected)
				</li>
				<li>
					<b>stateAV</b> &nbsp;&nbsp;-&nbsp;&nbsp; stateAV-Status des AV-Recievers (on,off,mute,absent)
				</li>
				<li>
					<b>surroundMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; gew&auml;hlter Surround-Modus (Auto, Stereo, Music,...)
				</li>
				<li>
					<b>toneControl</b> &nbsp;&nbsp;-&nbsp;&nbsp; Status der Klangkontrolle
				</li>
				<li>
					<b>treble</b> &nbsp;&nbsp;-&nbsp;&nbsp; H&ouml;hen-Level in dB
				</li>
				<li>
					<b>videoSelect</b> &nbsp;&nbsp;-&nbsp;&nbsp; gew&auml;hlter Videoselect-Modus
				</li>
				<li>
					<b>volume</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle Lautst&auml;rke in Prozent
				</li>
				<li>
					<b>volumeMax</b> &nbsp;&nbsp;-&nbsp;&nbsp; maximale Lautst&auml;rke in Prozent
				</li>
				<li>
					<b>volumeStraight</b> &nbsp;&nbsp;-&nbsp;&nbsp; aktuelle absolute Lautst&auml;rke in dB
				</li>
			</ul>
			<br>
			<b>Attribute</b><br>
			<br>
			<ul>
				<li>
					<b>brand</b> &nbsp;&nbsp;-&nbsp;&nbsp; Marke des Recievers (Denon oder Marantz) - um smartselect zu aktivieren Attribut brand auf Marantz setzen 
				</li>
				<li>
					<b>connectionCheck</b> &nbsp;&nbsp;-&nbsp;&nbsp; Zeitintervall f&uuml;r die &Uuml;bepr&uuml;fung der Verbindung
				</li>
				<li>
					<b>disable</b> &nbsp;&nbsp;-&nbsp;&nbsp; definiertes Gerät vorübergehend deaktivieren
				</li>
				<li>
					<b>dlnaName</b> &nbsp;&nbsp;-&nbsp;&nbsp; Name des Recievers im DLNARenderer-Modul
				</li>
				<li>
					<b>favorites</b> &nbsp;&nbsp;-&nbsp;&nbsp; maximale Anzahl der Favoriten
				</li>
				<li>
					<b>maxFavorites</b> &nbsp;&nbsp;-&nbsp;&nbsp; maximale Anzahl der Eintr&auml;ge in der Favoritenliste f&uuml;r die Verwendung mit "set favoriteList"
				</li>
				<li>
					<b>maxPreset</b> &nbsp;&nbsp;-&nbsp;&nbsp; maximale Anzahl der Eintr&auml;ge in der Liste f&uuml;r die Voreinstellungen
				</li>
				<li>
					<b>playTime</b> &nbsp;&nbsp;-&nbsp;&nbsp; Zeitintervall f&uuml;r die Abfrage der Spielzeit bei Online-Medien (off, 1-60 sec)
				</li>
				<li>
					<b>presetMode</b> &nbsp;&nbsp;-&nbsp;&nbsp; Verhalten der Liste f&uuml;r die Voreinstellungen (numerisch [00-55] oder alphanumerisch [A1-G8])
				</li>
				<li>
					<b>sleep</b> &nbsp;&nbsp;-&nbsp;&nbsp; Pause zwischen den Befehlen zum Aufruf der Favoritenliste mit "set favoriteList"
				</li>
				<li>
					<b>timeout</b> &nbsp;&nbsp;-&nbsp;&nbsp; Anzahl der Versuch f&uuml;r den Verbindungsaufbau
				</li>
				<li>
					<b>type</b> &nbsp;&nbsp;-&nbsp;&nbsp; Verstärkertyp (AVR oder Ceol), legt Schrittweite der Lautstärkeslider fest (0.5 oder 1)
				</li>
				<li>
					<b>unit</b> &nbsp;&nbsp;-&nbsp;&nbsp; Einheiten f&uuml;r Readings de-/aktivieren (on oder off)
				</li>
			</ul>
		</ul>
	</ul>
	

=end html_DE

=cut
	
