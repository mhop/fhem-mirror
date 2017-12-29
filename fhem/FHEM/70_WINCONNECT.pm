# $Id$
############################################################################
# 2017-12-29, v0.0.27
#
# v0.0.27
# - BUFIX:      [WinWebGUI] - Crash nach ca. 40-60 Sekunden
# - CHANGE      [FEHMModul] - get www_files und www_files_reset
#
# v0.0.26
# - BUFIX:      [WinWebGUI] - Installation Windows Service
#
# v0.0.25
# - FEATURE:	[WinWebGUI] - Starten als Windows Dienst
#               [WinWebGUI] - Kamera Vollbild Beenden Button
#               [WinWebGUI] - TTSMSG - Auswahl Windows integrierte Sprachen
#               [WinWebGUI] - TTSMSG - Google TTS
#               [WinWebGUI] - TTSMSG - Amazon Polly TTS (3 Sprachen)
#               [WinWebGUI] - SetFocusToApp
#               [WinWebGUI] - sendKey https://msdn.microsoft.com/en-us/library/windows/desktop/dd375731.aspx
# - CHANGE      [WinWebGUI] - Logdatei wird in %TEMP% angelegt
#               [WinWebGUI] - Deletereading drive_X_* wenn Laufwerk entfernt wurde z.B. USB-Stick
# - BUFIX:      [FEHMModul] - Umlaute bei Messagebox und NotifyIcon
#               [FEHMModul] - Leerzeichen Support bei CheckProcess
#               [WinWebGUI] - Audio/Mikrofon Device
#               [WinWebGUI] - Software Kamera
#
# v0.0.23
# - BUFIX:      [FEHMModul] - Download gitlab GUI
# - CHANGE      [FEHMModul] - Download Timeout WinControl.exe = 30
# - FEATURE:	[WinWebGUI] - NotifyIcon - Kontextmenü
#
# v0.0.22
# - BUFIX:      [FEHMModul] - Überreste Attribut "http-noshutdown" entfernt
# - FEATURE:	[FEHMModul] - Attribut "autoupdatewincontrol:0,1" Standard = 1 / 0 = Hier kann das automatische GUI Update deaktiviert werden.
# - CHANGE      [WinWebGUI] - Autoupdate über Attribut steuerbar
#
# v0.0.21
# - BUFIX:      [WinWebGUI] - FHEM Server Connect / Reconnect
#               [WinWebGUI] - shutdown / standby / hibernate
#               [WinWebGUI] - accept trusted SSL certificat
#               [WinWebGUI] - battery_ChargeStatus 0 ersetzt in Middle
# - CHANGE      [WinWebGUI] - Autoupdate immer angeschalten
#               [WinWebGUI] - select SSL protocols ssl3, tls, tlsv11, tlsv12
# - FEATURE:	[WinWebGUI] - Icon FHEM Connect      = blau
#                             Icon FHEM Disconnect   = rot
#                             Icon FHEM Wrong Device = gelb
#               [WinWebGUI] - FQDN oder Netbios Name as FHEM Server
#               [WinWebGUI] - Support button / collect support informations
#               [WinWebGUI] - WMI Abfragen / WMI Wizard
#               [WinWebGUI] - Support Core Temp
#
# v0.0.20
# - BUFIX:      [FEHMModul] - $_ ersetzt durch $uResult
#               [FEHMModul] - reading "memory_available" und "memory_total" ohne Zusatz MB
#               [WinWebGUI] - Exit Messagebox entfernt
# - FEATURE:	[WinWebGUI] - Exit Menübutton
#
# v0.0.18
# - BUFIX:      [WinWebGUI] - Autoupdate
#               [WinWebGUI] - Shutdown Messagebox
#
# v0.0.17
# - BUFIX:      [FEHMModul] - Code Optimierungen
# - CHANGE      [WinWebGUI] - FHEM Devicename check auf Gültigkeit https://forum.fhem.de/index.php/topic,59251.msg667257.html#msg667257
# - FEATURE:	[WinWebGUI] - Fenster verstecken https://forum.fhem.de/index.php/topic,59251.msg665863.html#msg665863
#
# v0.0.16 erste SVN Version
# - BUFIX:      Refresh CSRFTOKEN nach einem reconnect
#				Readings zurücksetzen wenn Offline
#                os_RunTime_days,os_RunTime_hours und os_RunTime_minutes
#                printer_aktiv und printer_names
#               div. Optimierungen
# - FEATURE     Attribut "win_resetreadings:0,1" Standard = 1 / 1 = Readings zurücksetzen wenn Offline 
#               Attribut "autoupdategitlab:0,1"  Standard = 1 / 0 = Hier kann der automatische Download deaktiviert werden.
# - CHANGE      Attribut "http-noshutdown" Auf Standwardwert "0" gesetzt
#
# v0.0.15
# - BUFIX:      Start optimiert / Log sortiert
#
# v0.0.14
# - FEATURE:	Winconnect mit Windows starten
#            	Ausführen (minimiert/normales Fenster)
#            	checkprocess (prüft ob ein Prozess gestartet ist inkl. Anzahl)
#            	wincontrol.exe.config wird nicht mehr benötigt
#            	Windows Version (os_Version & os_ReleaseID ab Win10)
#            	Benutzer / Hostname (os_Username, os_Computername & os_Domainname)
#               Performance: CPU, Festplatte, Netzwerk, RAM, …
#            	Hardware Ausrüstung: Prozessor, BIOS & RAM (memory_*, bios_* und cpu_*)
#               VolumeDown, VolumeUp (mit attr volumeStep)
#               Laufzeiten in Tage/Stunden/Minuten (os_RunTime_minutes, os_RunTime_hours und os_RunTime_days)
# - BUFIX:      checkservice (im FHEM Reading wurde immer nur der erste Service eingetragen)
#
# v0.0.13
# - FEATURE:	Performance Optimierungen
#            	set powermode add(standby/hibernate)
#            	drive informations (Space in MB/change only > 10MB)
# - BUFIX:      div.
#               Programmabsturtz nach ca. 4-5 Tagen 
#
# v0.0.12
# - FEATURE:	CSRFToken
# - BUFIX:      Detect Audio Sound
#
# v0.0.11
# - FEATURE:	ttsmsg play sound
#            	messagebox play sound
#            	set camera (on/off)
#            	make picture (camera)
#            	motion detect (camera)
#            	Update Winconnect.exe (inkl. autoupdate)
#				microphone sound detection
#				Startscreen
# - BUFIX:      .NET Fehlermeldung
#				set screen on
#				set screen off
# - Readings:	audio_devicename
#				microphone_devicename
#
# v0.0.10
# - FEATURE:	send notifymsg (set notifymsg Ballon Tip)
#            	send messagebox (set messagebox)
#            	Verzeichnis überwachen
#            	set powermode (shutdown/restart)
#
# v0.0.9
# - FEATURE: 	FHEM SSL
#
# v0.0.8
# - FEATURE: 	FHEM Anmeldung (basicAuth)
#            	volume mute (on/off)
# - BUGFIX: 	statusrequest (firststart)
# - Readings:   speecherrormessage
#            	speecherrormessagequality
#            	speechmessagequality
#            	mute
#
# v0.0.7 - 20161107
# - BUGFIX:     Umlaute beim senden einer ttsmsg
# - FEATURE: 	set commandhide
#            	set user_aktividletime
#            	printer_aktiv
#            	Spracherkennung
#
# v0.0.6 - 20161025
# - BUFIX:      no audiodevice
# - FEATURE:	set brightness 0 - 100
#
# v0.0.5 - 20161024
# - BUGFIX
#
# v0.0.4 - 20161024
# - BUGFIX:     (Bereinigung wincontrol / FHEM readings)
# - FEATURE:	send ttsmsg (TextToSpeech)
# - Readings:	os_StartTime         = Startzeit Windows
#            	wincontrol_starttime = Startzeit WinControl
#            	wincontrol_user      = Benutzer der Wintrol gestartet hat
#            	battery_ChargeStatus
#            	battery_LifePercent
#            	battery_LifeRemainingsMin
#            	battery_PowerLineStatus
#
# v0.0.3 - 20161020
# - FEATURE:	set command
#            	set showfile
#            	set checkservice
#
# v0.0.0 - 20161018
# - FEATURE:	ON/OFF Windows Screen
#            	set volume
#            	detect playing audio
#
#     Copyright by Michael Winkler
#     e-mail: michael.winkler at online.de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it andor modify
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
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use Time::Piece;

sub WINCONNECT_Set($@);
sub WINCONNECT_Get($@);
sub WINCONNECT_GetStatus($;$);
sub WINCONNECT_Define($$);
sub WINCONNECT_Undefine($$);

# Autoupdateinformationen
my $DownloadGURL  = "https://gitlab.com/michael.winkler/winconnect/raw/master/WinControl_0.0.27.exe";
my $DownloadSURL  = "https://gitlab.com/michael.winkler/winconnect/raw/master/WinControlService_0.0.27.exe";
my $DownloadVer   = "0.0.27";
my $DownloadError = "";

###################################
sub WINCONNECT_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "WINCONNECT_Initialize: Entering";

    $hash->{SetFn}   = "WINCONNECT_Set";
	$hash->{GetFn}   = "WINCONNECT_Get";
    $hash->{DefFn}   = "WINCONNECT_Define";
    $hash->{UndefFn} = "WINCONNECT_Undefine";

	$hash->{AttrList} = "volumeStep win_resetreadings:0,1 disable:0,1 autoupdategitlab:0,1 autoupdatewincontrol:0,1 " . $readingFnAttributes;

    return;
}

#####################################
# Get Status
#####################################
sub WINCONNECT_GetStatus($;$) {
    my ($hash, $update ) = @_;
    my $name      = $hash->{NAME};
    my $interval  = $hash->{INTERVAL};
	my $filemtime = "-";
	
	if ($DownloadError eq "") {$DownloadError = ReadingsVal( $name, "wincontrol_error", "Start WinControl....." );}
	
    return if ( AttrVal( $name, "disable", 0 ) == 1 );
	
	InternalTimer( gettimeofday() + $interval, "WINCONNECT_GetStatus", $hash, 0 );
	
	my $filename    = '././www/winconnect/WinControl.exe';
	my $filenameSR  = '././www/winconnect/WinControlService.exe';
	my $filedir     = '././www/winconnect';
	
	if ((-e $filename)) {$filemtime = (stat $filename)[9];}
	
	Log3 $name, 5, "WINCONNECT $name: called function WINCONNECT_GetStatus()";
	Log3 $name, 5, "WINCONNECT $name: filename  = " . $filename . " filemtime = " . $filemtime;
	
	#Alte Readings bereinigen
	print (fhem( "deletereading $name wincontrol_gitlap" )) if ( ReadingsVal( $name, "wincontrol_gitlap", "0" ) ne "0" ) ;
	print (fhem( "deletereading $name wincontrol_gitlap_url" )) if ( ReadingsVal( $name, "wincontrol_gitlap_url", "0" ) ne "0" ) ;
	
	if ( !$update ) {
        WINCONNECT_SendCommand( $hash, "powerstate" );
    }
    else {
		WINCONNECT_SendCommand( $hash, "statusrequest" );
	}
	
	if (ReadingsVal( $name, "wincontrol_type", ".." ) eq "GUI with own device") {
		print (fhem( "deletereading $name wincontrol_update" ))     if ( ReadingsVal( $name, "wincontrol_update", "0" ) ne "0" ) ;
		print (fhem( "deletereading $name wincontrol_gitlab_url" )) if ( ReadingsVal( $name, "wincontrol_gitlab_url", "0" ) ne "0" ) ;
		print (fhem( "deletereading $name wincontrol_gitlab" ))     if ( ReadingsVal( $name, "wincontrol_gitlab", "0" ) ne "0" ) ;
		print (fhem( "deletereading $name wincontrol_error" ))      if ( ReadingsVal( $name, "wincontrol_error", "0" ) ne "0" ) ;
		return;
	}
	
	readingsBeginUpdate($hash);
	
	#WinControl Versionsinformationen
	readingsBulkUpdateIfChanged( $hash, "wincontrol_gitlab", $DownloadVer );
	readingsBulkUpdateIfChanged( $hash, "wincontrol_gitlab_url", $DownloadGURL);
	readingsBulkUpdateIfChanged( $hash, "wincontrol_gitlab_serviceurl", $DownloadSURL);
		
	#WinControl Update Info eintragen
	if ($filemtime eq "-") {$filemtime = 0;}
	readingsBulkUpdateIfChanged( $hash, "wincontrol_update", $filemtime );
	if (ReadingsVal( $name, "os_Name", "unbekannt" ) ne "unbekannt") {readingsBulkUpdateIfChanged( $hash, "model", ReadingsVal( $name, "os_Name", "unbekannt" ));}
	
	#WinControl Last Error
	readingsBulkUpdateIfChanged( $hash, "wincontrol_error", $DownloadError);
	
	readingsEndUpdate( $hash, 1 );
	
	#Autoupdatefile von Gitlab herunterladen
	if ($DownloadGURL ne '' && !(-e $filename . "_" .$DownloadVer) && AttrVal( $name, "autoupdategitlab", "1" ) ) {
	
		#Verzeichnis anlegen
		mkdir($filedir, 0777) unless(-d $filedir );

		if(!open (FILE, ">". $filename . "_" .$DownloadVer)) {
			$DownloadError = "WINCONNECT [NEW] Download ERROR Can't write = " .$filename . "_" .$DownloadVer . " Error=" .$!;
			Log3 $name, 5, $DownloadError;
		}else {
			
			print FILE $name;
			close (FILE);
			
			#Delete old version
			if ((-e $filename))   {unlink $filename}
			if ((-e $filenameSR)) {unlink $filenameSR}
				
			HttpUtils_NonblockingGet({url=>$DownloadGURL, timeout=>30, hash=>$hash, service=>"autoupdate", callback=>\&WINCONNECT_GetNewGUIVersion});		
			HttpUtils_NonblockingGet({url=>$DownloadSURL, timeout=>30, hash=>$hash, service=>"autoupdate", callback=>\&WINCONNECT_GetNewServiceVersion});
		}
	}
	
    return;
}

sub WINCONNECT_GetNewGUIVersion($$$) {
	my ($hash, $err, $data) = @_;
	my $filename  = '././www/winconnect/WinControl.exe';
	my $name      = $hash->{NAME};
   	my $CheckFile = $filename . "_" .$DownloadVer;
    
	# Download neue Datei
	if(!open(FH, ">$filename")) {
		$DownloadError = "Download ERROR Can't write = " .$filename . " Error=" .$!;
		Log3 $name, 5, "WINCONNECT [NEW] " .$DownloadError;

		#Delete Version Flag
		if ((-e $CheckFile)) {unlink $CheckFile}
	}else{
		print FH $data;
		close(FH);
		
		my $filesize = -s $filename;

		# Prüfen ob die Dateigröße passt!
		if ($filesize < 600000) {
			$DownloadError = "Download ERROR file to small. Filesize = " . $filesize;
			Log3 $name, 5, "WINCONNECT [NEW] " .$DownloadError;
			#Download fehlgeschlagen! / Flag wieder löschen
			if ((-e $CheckFile)) {unlink $CheckFile}
		}else{
			Log3 $name, 0, "WINCONNECT [NEW] Download new version URL = $DownloadGURL";
			Log3 $name, 0, "WINCONNECT [NEW] Download new version OK";
			$DownloadError = "Download new version = $DownloadVer";
		}
	}
}

sub WINCONNECT_GetNewServiceVersion($$$) {
	my ($hash, $err, $data) = @_;
	my $filename  = '././www/winconnect/WinControlService.exe';
	my $name      = $hash->{NAME};
   	my $CheckFile = $filename . "_" .$DownloadVer;
    
	# Download neue Datei
	if(!open(FH, ">$filename")) {
		$DownloadError = "Download ERROR Can't write = " .$filename . " Error=" .$!;
		Log3 $name, 5, "WINCONNECT [NEW] " .$DownloadError;

		#Delete Version Flag
		if ((-e $CheckFile)) {unlink $CheckFile}
	}else{
		print FH $data;
		close(FH);
		
		my $filesize = -s $filename;

		# Prüfen ob die Dateigröße passt!
		if ($filesize < 50000) {
			$DownloadError = "Download ERROR file to small. Filesize = " . $filesize;
			Log3 $name, 5, "WINCONNECT [NEW] " .$DownloadError;
			#Download fehlgeschlagen! / Flag wieder löschen
			if ((-e $CheckFile)) {unlink $CheckFile}
		}else{
			Log3 $name, 0, "WINCONNECT [NEW] Download new version URL = $DownloadSURL";
			Log3 $name, 0, "WINCONNECT [NEW] Download new version OK";
			$DownloadError = "Download new version = $DownloadVer";
		}
	}
}

###################################
sub WINCONNECT_SendCommand($$;$$) {
    my ( $hash, $service, $cmd ) = @_;
    my $name            = $hash->{NAME};
    my $address         = $hash->{helper}{ADDRESS};
	my $serviceurl		= "";
	my $PWRState 		= ReadingsVal( $name, "state", "" );
	my $Winconnect      = ReadingsVal( $name, "wincontrol", "statusrequest" );
	my $WinconnectUPD   = ReadingsVal( $name, "wincontrol_update", "0" );
	my $GUIPort         = ReadingsVal( $name, "wincontrol_user_port", "8183" );
	my $URL;

    Log3 $name, 5, "WINCONNECT $name: called function WINCONNECT_SendCommand()";

    # Check Service and change serviceurl
	if ($service eq "statusrequest") {
		$serviceurl = "statusrequest";
	}
	elsif ($service eq "volume") {
		$serviceurl = "volume";
	}
	elsif ($service eq "file_dir") {
		$serviceurl = "file_dir";
	}
	elsif ($service eq "picture_dir") {
		$serviceurl = "picture_dir";
	}
	elsif ($service eq "camera") {
		$serviceurl = "camera";
	}
	elsif ($service eq "file_order") {
		$serviceurl = "file_order";
	}
	elsif ($service eq "file_filter") {
		$serviceurl = "file_filter";
	}
	elsif ($service eq "mute") {
		$serviceurl = "volumemute";
	}
	elsif ($service eq "speechcommands") {
		$serviceurl = "speechcommands";
	}
	elsif ($service eq "speechquality") {
		$serviceurl = "speechquality";
	}
	elsif ($service eq "brightness") {
		$serviceurl = "brightness";
	}
	elsif ($service eq "user_aktividletime") {
		$serviceurl = "user_aktividletime";
	}
	elsif ($service eq "powerstate") {
		if ( AttrVal( $name, "autoupdatewincontrol", 1 ) == 1 ) {$serviceurl = "powerstate" . "=" . $PWRState . ";" . $Winconnect . ";" . $WinconnectUPD;}
		else {$serviceurl = "powerstate" . "=" . $PWRState . ";" . $Winconnect . ";0";}
	}
	elsif ($service eq "command") {
		$serviceurl = "command";
	}
	elsif ($service eq "commandhide") {
		$serviceurl = "commandhide";
	}
	elsif ($service eq "update") {
		$serviceurl = "update";
	}
	elsif ($service eq "checkservice") {
		$serviceurl = "checkservice";
	}
	elsif ($service eq "checkperformance") {
		$serviceurl = "checkperformance";
	}	
	elsif ($service eq "checkperformance_interval") {
		$serviceurl = "checkperformance_interval";
	}
	elsif ($service eq "checkprocess") {
		$serviceurl = "checkprocess";
	}
	elsif ($service eq "checkprocess_type") {
		$serviceurl = "serviceconfigwrite";
	}
	elsif ($service eq "showfile") {
		$serviceurl = "showfile";
	}
	elsif ($service eq "setfocustoapp") {
		$serviceurl = "setfocustoapp";
	}
	elsif ($service eq "ttsmsg") {
		$serviceurl = "ttsmsg";
	}
	elsif ($service eq "powermode") {
		$serviceurl = "powermode";
	}
	elsif ($service eq "messagebox") {
		$serviceurl = "messagebox";
	}
	elsif ($service eq "notifymsg") {
		$serviceurl = "notifymsg";
	}
	elsif ($service eq "screenon") {
		$serviceurl = "screen=on";
	}
	elsif ($service eq "picture_make") {
		$serviceurl = "picture_make";
	}
	elsif ($service eq "screenoff") {
		$serviceurl = "screen=off";
	}
	elsif ($service eq "sendkey") {
		$serviceurl = "sendkey";
	}		
	else{
		$serviceurl = $service;
	}
	
	# URL zusammenbauen
	$cmd = ( defined($cmd) ) ? $cmd : "";
    $URL =  "http://" . $address . ":" . $GUIPort . "/fhem/" . $serviceurl . $cmd ;
	$URL =~ tr/\r\n/|/;
	
    Log3 $name, 5, "WINCONNECT $name: GET " . urlDecode($URL);

     HttpUtils_NonblockingGet(
            {
                url        => $URL,
                timeout    => 10,
                noshutdown => 0,
                #data       => undef, 2017.07.20 - enfernt
                hash       => $hash,
                service    => $service,
                cmd        => $cmd,
                #type       => $type, 2017.07.20 - enfernt
				callback   => \&WINCONNECT_ReceiveCommand
            }
        );

    return;
}

###################################
sub WINCONNECT_Set($@) {
    my ( $hash, @a ) = @_;
    my $name       = $hash->{NAME};
    my $state      = ReadingsVal( $name, "state", "absent" );
   	my $cmd        = "";
	my $Value	   = "";
	my $Count      = 0;
	my $SetValue   = 0;
	my $GUIType    = ReadingsVal( $name, "wincontrol_type", "GUI without service" );
	my $usage      = "";
    Log3 $name, 5, "WINCONNECT $name: called function WINCONNECT_Set()";
	
	# Set´s anzeigen je nach WinControl Typ!
	if ($GUIType eq "GUI with own device") {
		# GUI mit eigenem Device und einem Windows Service
		$usage = "choose one of camera:on,off picture_make:noArg speechquality:slider,0,1,100 statusRequest:noArg screenOn:noArg screenOff:noArg command commandhide sendkey showfile picture_dir checkprocess notifymsg messagebox file_dir file_filter file_order:ascending,descending ttsmsg user_aktividletime speechcommands setfocustoapp ";	
	}
	elsif($GUIType eq "GUI without service") {
		# Standard GUI ohne einen Service
		$usage = "choose one of brightness:slider,0,1,100 camera:on,off checkperformance:textField-long checkperformance_interval checkprocess checkservice command commandhide file_dir file_filter file_order:ascending,descending messagebox mute:on,off notifymsg picture_dir picture_make:noArg powermode:shutdown,restart,standby,hibernate screenOn:noArg screenOff:noArg sendkey setfocustoapp showfile speechcommands speechquality:slider,0,1,100 statusRequest:noArg ttsmsg update:noArg user_aktividletime volume:slider,0,1,100 volumeDown:noArg volumeUp:noArg ";	
	}
	else {
		# Windows Service betrieb / GUI ohne eigenes Device aber mit einem Windows Service
		$usage = "choose one of brightness:slider,0,1,100 camera:on,off checkperformance:textField-long checkperformance_interval checkprocess checkprocess_type:service,gui checkservice command commandhide command_type:service,gui file_dir file_filter file_order:ascending,descending file_type:service,gui messagebox mute:on,off notifymsg picture_dir picture_make:noArg powermode:shutdown,restart,standby,hibernate screenOn:noArg screenOff:noArg sendkey setfocustoapp showfile speechcommands speechquality:slider,0,1,100 statusRequest:noArg ttsmsg update:noArg user_aktividletime volume:slider,0,1,100 volumeDown:noArg volumeUp:noArg ";
	}
	
	return "No Argument given" if ( !defined( $a[1] ) );

    # statusRequest
    if ( lc( $a[1] ) eq "statusrequest" ) {
        Log3 $name, 3, "WINCONNECT set $name " . $a[1];
		WINCONNECT_SendCommand( $hash, "statusrequest" );
    }
	
	# on
    elsif ( lc( $a[1] ) eq "on" ) {
        readingsSingleUpdate( $hash, "state", "on",1 );
    }

	# powerstate
    elsif ( lc( $a[1] ) eq "powerstate" ) {
        Log3 $name, 3, "WINCONNECT set $name " . $a[1];
		WINCONNECT_SendCommand( $hash, "powerstate" );
    }

	# update
    elsif ( lc( $a[1] ) eq "update" ) {
        Log3 $name, 3, "WINCONNECT set $name " . $a[1];
		WINCONNECT_SendCommand( $hash, "update" );
    }
	
    # off
    elsif ( lc( $a[1] ) eq "off" ) {
        readingsSingleUpdate( $hash, "state", "off",1 );
    }
	
	# screenOn
	elsif ( lc( $a[1] ) eq "screenon" ) {
        Log3 $name, 3, "WINCONNECT set $name " . $a[1];
		if ( $state eq "on" ) {WINCONNECT_SendCommand( $hash, "screenon" );}else {return "Device needs to be ON to adjust screenon.";}
    }
	
	#screenOff
	elsif ( lc( $a[1] ) eq "screenoff" ) {
        Log3 $name, 3, "WINCONNECT set $name " . $a[1];
		if ( $state eq "on" ) {WINCONNECT_SendCommand( $hash, "screenoff" );}else {return "Device needs to be ON to adjust screenoff.";}
    }
	
	# volume
    elsif ( lc( $a[1] ) eq "volume" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			$SetValue  = $a[2];
            if ($SetValue >= 0 && $SetValue <= 100 ) {
                $cmd = $a[2];
            }
            else {
                return "Argument $SetValue does not seem to be a valid integer between 0 and 100";
            }
			WINCONNECT_SendCommand( $hash, "volume" , "=" . $cmd  );
			readingsSingleUpdate( $hash, "volume", $cmd,1 ); 
        }
        else {return "Device needs to be ON to adjust volume.";}
    }
		
	# volumeUp
	elsif ( lc( $a[1] ) eq "volumeup" ) {
		my $volumeStep = int(AttrVal($name, "volumeStep", 5));
		my $volumenow  = ReadingsVal( $name, "volume", 0);
		my $volumeNew  = $volumenow + $volumeStep;
				
		if ($volumeNew > 100) {$volumeNew  = 100;}
		
        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $volumeNew;
		if ( $state eq "on" ) {WINCONNECT_SendCommand( $hash, "volume" , "=" . $volumeNew  );readingsSingleUpdate( $hash, "volume", $volumeNew,1 );}else {return "Device needs to be ON to adjust volume.";}
    }
	
	# volumeDown
	elsif ( lc( $a[1] ) eq "volumedown" ) {
		my $volumeStep = int(AttrVal($name, "volumeStep", 5));
		my $volumenow  = ReadingsVal( $name, "volume", 0);
		my $volumeNew  = $volumenow - $volumeStep;
		
		if ($volumeNew < 0) {$volumeNew  = 0;}
		
        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $volumeNew;
		if ( $state eq "on" ) {WINCONNECT_SendCommand( $hash, "volume" , "=" . $volumeNew  );readingsSingleUpdate( $hash, "volume", $volumeNew,1 );}else {return "Device needs to be ON to adjust volume.";}
    }
	
	# mute
    elsif ( lc( $a[1] ) eq "mute" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
           	WINCONNECT_SendCommand( $hash, "volumemute" , "=" . $a[2]  );
			readingsSingleUpdate( $hash, "mute", $a[2],0 ); 
        }
        else {return "Device needs to be ON to adjust volume mute.";}
    }

	# powermode
    elsif ( lc( $a[1] ) eq "powermode" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
           	WINCONNECT_SendCommand( $hash, "powermode" , "=" . $a[2]  );
        }
        else {return "Device needs to be ON to adjust powermode.";}
    }
	
	# user_aktividletime
    elsif ( lc( $a[1] ) eq "user_aktividletime" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			$SetValue  = $a[2];
            if ($SetValue >= 0 && $SetValue <= 10000 ) {
                $cmd = $a[2];
            }
            else {
                return "Argument does not seem to be a valid integer between 0 and 10000";
            }
			WINCONNECT_SendCommand( $hash, "user_aktividletime" , "=" . $cmd  );
			readingsSingleUpdate( $hash, "user_aktividletime", $cmd,1 ); 
        }
        else {return "Device needs to be ON to adjust user_aktividletime.";}
    }
	
	# brightness
    elsif ( lc( $a[1] ) eq "brightness" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			$SetValue  = $a[2];
            if ($SetValue >= 0 && $SetValue <= 100 ) {
                $cmd = $a[2];
            }
            else {
                return "Argument does not seem to be a valid integer between 0 and 100";
            }
			WINCONNECT_SendCommand( $hash, "brightness" , "=" . $cmd  );
			readingsSingleUpdate( $hash, "brightness", $cmd,1 ); 
        }
        else {return "Device needs to be ON to adjust brightness.";}
    }
	
	# speechquality
    elsif ( lc( $a[1] ) eq "speechquality" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			$SetValue  = $a[2];
            if ($SetValue >= 0 && $SetValue <= 100 ) {
                $cmd = $a[2];
            }
            else {
                return "Argument does not seem to be a valid integer between 0 and 100";
            }
			WINCONNECT_SendCommand( $hash, "speechquality" , "=" . $cmd  );
			readingsSingleUpdate( $hash, "speechquality", $cmd,1 ); 
        }
        else {return "Device needs to be ON to adjust speechquality.";}
    }
	
	# command
    elsif ( lc( $a[1] ) eq "command" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "command" , "=" . $cmd );
		}
		else {return "Device needs to be ON to execute command.";}
    }
	
	# commandhide
	elsif ( lc( $a[1] ) eq "commandhide" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "commandhide" , "=" . $cmd );
		}
		else {return "Device needs to be ON to execute commandhide.";}
    }

	# command_type
    elsif ( lc( $a[1] ) eq "command_type" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			readingsSingleUpdate( $hash, "command_type", $a[2],1 ); 
           	WINCONNECT_SendCommand( $hash, "SERVICECONFIGWRITE" , "%20type_service_command%20" . $a[2]  );
        }
        else {return "Device needs to be ON to adjust command_type.";}
    }
	
	# showfile
    elsif ( lc( $a[1] ) eq "showfile" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "showfile" , "=" . $cmd );
		}
		else {return "Device needs to be ON to showfile.";}
    }

	# sendkey
    elsif ( lc( $a[1] ) eq "sendkey" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "sendkey" , "=" . $cmd );
		}
		else {return "Device needs to be ON to sendkey.";}
    }
	
	# setfocustoapp
    elsif ( lc( $a[1] ) eq "setfocustoapp" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "setfocustoapp" , "=" . $cmd );
		}
		else {return "Device needs to be ON to setfocustoapp.";}
    }
	
	# ttsmsg
    elsif ( lc( $a[1] ) eq "ttsmsg" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "ttsmsg" , "=" . $cmd );
			readingsSingleUpdate( $hash, "ttsmsg", $Value,1 );
		}
		else {return "Device needs to be ON to send ttsmsg.";}
    }   

	# messagebox
    elsif ( lc( $a[1] ) eq "messagebox" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "messagebox" , "=" . $cmd );
			readingsSingleUpdate( $hash, "messagebox", $Value,1 );
		}
		else {return "Device needs to be ON to send messagebox.";}
    } 
	
	# notifymsg
    elsif ( lc( $a[1] ) eq "notifymsg" ) {
        return "No argument given" if ( !defined( $a[2] ) );
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "notifymsg" , "=" . $cmd );
			readingsSingleUpdate( $hash, "notifymsg", $Value,1 );
		}
		else {return "Device needs to be ON to send notifymsg.";}
    } 
	
	# checkservice
    elsif ( lc( $a[1] ) eq "checkservice" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			readingsSingleUpdate( $hash, "checkservice", $Value,1 );
			WINCONNECT_SendCommand( $hash, "checkservice" , "=" . $cmd );
		}
		else {return "Device needs to be ON to checkservice.";}
    }

	# checkperformance
    elsif ( lc( $a[1] ) eq "checkperformance" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			readingsSingleUpdate( $hash, "checkperformance", $Value,1 );
			WINCONNECT_SendCommand( $hash, "checkperformance" , "=" . $cmd );
		}
		else {return "Device needs to be ON to checkperformance.";}
    }

	# checkperformance_interval
    elsif ( lc( $a[1] ) eq "checkperformance_interval" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			$SetValue  = $a[2];
            if ($SetValue >= 10 && $SetValue <= 10000 ) {
                $cmd = $a[2];
            }
            else {
                return "Argument does not seem to be a valid integer between 10 and 10000";
            }
			WINCONNECT_SendCommand( $hash, "checkperformance_interval" , "=" . $cmd  );
			readingsSingleUpdate( $hash, "checkperformance_interval", $cmd,0 ); 
        }
        else {return "Device needs to be ON to adjust checkperformance_interval.";}
    }
	
	# checkprocess
    elsif ( lc( $a[1] ) eq "checkprocess" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			readingsSingleUpdate( $hash, "checkprocess", $Value,1 );
			WINCONNECT_SendCommand( $hash, "checkprocess" , "=" . $cmd );
		}
		else {return "Device needs to be ON to checkprocess.";}
    }

	# checkprocess_type
    elsif ( lc( $a[1] ) eq "checkprocess_type" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			readingsSingleUpdate( $hash, "checkprocess_type", $a[2],1 ); 
           	WINCONNECT_SendCommand( $hash, "SERVICECONFIGWRITE" , "%20type_service_checkprocess%20" . $a[2]  );
        }
        else {return "Device needs to be ON to adjust checkprocess_type.";}
    }
	
	# speechcommands
    elsif ( lc( $a[1] ) eq "speechcommands" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "speechcommands" , "=" . $cmd );
			readingsSingleUpdate( $hash, "speechcommands", $Value,1 );
		}
		else {return "Device needs to be ON to speechcommands.";}
    }

	# file_dir
    elsif ( lc( $a[1] ) eq "file_dir" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "file_dir" , "=" . $cmd );
			readingsSingleUpdate( $hash, "file_dir", $Value,1 );
		}
		else {return "Device needs to be ON to file_dir.";}
    }
	
	# file_filter
    elsif ( lc( $a[1] ) eq "file_filter" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "file_filter" , "=" . $cmd );
			readingsSingleUpdate( $hash, "file_filter", $Value,0 );
		}
		else {return "Device needs to be ON to file_filter.";}
    }

	# file_order
    elsif ( lc( $a[1] ) eq "file_order" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
           	WINCONNECT_SendCommand( $hash, "file_order" , "=" . $a[2]  );
			readingsSingleUpdate( $hash, "file_order", $a[2],1 ); 
        }
        else {return "Device needs to be ON to adjust file_order.";}
    }

	# file_type
    elsif ( lc( $a[1] ) eq "file_type" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
			readingsSingleUpdate( $hash, "file_type", $a[2],1 ); 
           	WINCONNECT_SendCommand( $hash, "SERVICECONFIGWRITE" , "%20type_service_file%20" . $a[2]  );
        }
        else {return "Device needs to be ON to adjust file_type.";}
    }
	
	# picture_dir
    elsif ( lc( $a[1] ) eq "picture_dir" ) {
        if ( $state eq "on" ) {
		
			foreach (@a) {
				if ($cmd eq "") {$cmd = $_ ;} else {$cmd = $cmd . "%20" . $_ ;}
				$Count = $Count + 1;
				if ($Count >= 3 ) {if ($Value eq "") {$Value = $_ ;} else {$Value = $Value . " " . $_ ;}}
			}
			Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $cmd;
			WINCONNECT_SendCommand( $hash, "picture_dir" , "=" . $cmd );
			readingsSingleUpdate( $hash, "picture_dir", $Value,1 );
		}
		else {return "Device needs to be ON to picture_dir.";}
    }

	# picture_make
	elsif ( lc( $a[1] ) eq "picture_make" ) {
        Log3 $name, 3, "WINCONNECT set $name " . $a[1];
		if ( $state eq "on" ) {WINCONNECT_SendCommand( $hash, "picture_make" );}else {return "Device needs to be ON to adjust picture_make.";}
    }

	# camera
    elsif ( lc( $a[1] ) eq "camera" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "WINCONNECT set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
           	WINCONNECT_SendCommand( $hash, "camera" , "=" . $a[2]  );
        }
        else {return "Device needs to be ON to adjust camera.";}
    }
	
    # return usage hint
    else {return $usage;}

    return;
}

sub WINCONNECT_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $what;
	my $files;

    return "argument is missing" if ( int(@a) < 2 );
	$what = $a[1];

	#2017.07.21 - Log nur schreiben wenn get nicht initialisiert wird
	if ($what ne '?') {
		Log3 $name, 5, "WINCONNECT $name [WINCONNECT_Get] [$what] called function";
	}

    if ( $what =~ /^(www_files|www_files_reset)$/)
    {
		if ( $what eq "www_files" ) {
		
			my $directory = '././www/winconnect';
			opendir (DIR, $directory) or die $!;
			while (my $file = readdir(DIR)) {
				if ($file ne "." && $file ne "..") {
				$files = $files . "$file\n";				
				}
			}
			closedir(DIR);
            return $files ;
        }

		elsif ( $what eq "www_files_reset" ) {
		
			my $directory = '././www/winconnect';
			opendir (DIR, $directory) or die $!;
			while (my $file = readdir(DIR)) {
				if ($file ne "." && $file ne "..") {
				Log3 $name, 0, "WINCONNECT [WINCONNECT_Get] [www_files_reset] ././www/winconnect/$file delete!";
				unlink "././www/winconnect/$file";
				$files = $files . "DELETE $file\n";				
				}
			}
			closedir(DIR);
            return $files ;
        }
		
        else {
            return "no such reading: $what";
        }

	}
    
    else {
        return "Unknown argument $what, choose one of www_files:noArg www_files_reset:noArg ";
    }
}

###################################
sub WINCONNECT_Define($$) {
    my ( $hash, $def ) = @_;
    my @a 		   = split( "[ \t][ \t]*", $def );
    my $name 	   = $hash->{NAME};
	
    Log3 $name, 5, "WINCONNECT $name: called function WINCONNECT_Define()";

    if ( int(@a) < 2 ) {
        my $msg = "Wrong syntax: define <name> WINCONNECT <ip-or-hostname> [<poll-interval>] ";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "WINCONNECT";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

	# use interval of 45sec if not defined
    my $interval = $a[3] || 45;
    $hash->{INTERVAL} = $interval;
	
    # set default settings on first define
    if ($init_done) {
        $attr{$name}{icon} = 'it_server';
    }
	
	# start the status update timer
    #RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "WINCONNECT_GetStatus", $hash, 1);
	
    return;
}

sub WINCONNECT_ReceiveCommand($) {

	my ($param, $err, $data) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
	my $VerWin   = substr(ReadingsVal( $name, "wincontrol", "0.0.0.0" ),4);
	my $VerGit   = substr(ReadingsVal( $name, "wincontrol_gitlab", "0.0.0.0" ),4);
	my $service  = $param->{service};

	readingsBeginUpdate($hash);
 
	# Versionsnachricht
	my $Message = $name . "%20NOTIFYMSG%20Neue%20WinConnect%20Version%20verfügbar!%20Downloadlink%20=%20" . $DownloadGURL;
	
    if($err ne "")    {
		Log3 $name, 5, "WINCONNECT $name: error while requesting ".$param->{url}." - $err"; 
        readingsBulkUpdateIfChanged( $hash, "state", "off" );
		
		if (ReadingsVal( $name, "wincontrol_user_port", "8183" ) eq "8183" && AttrVal($name, "win_resetreadings", 1) eq '1') {
			readingsBulkUpdateIfChanged( $hash, "user_aktiv", "false" ); 
			readingsBulkUpdateIfChanged( $hash, "audio", "off");
			readingsBulkUpdateIfChanged( $hash, "user_aktiv", "false" ); 
			readingsBulkUpdateIfChanged( $hash, "os_RunTime_days", "0" ); 
			readingsBulkUpdateIfChanged( $hash, "os_RunTime_hours", "0" ); 
			readingsBulkUpdateIfChanged( $hash, "os_RunTime_minutes", "0" ); 
			readingsBulkUpdateIfChanged( $hash, "printer_aktiv", "false" );
			readingsBulkUpdateIfChanged( $hash, "printer_names", "no_prining" );
		}
    }
 
    elsif($data ne "")
    {
		readingsBulkUpdateIfChanged( $hash, "state", "on" );
        Log3 $name, 5, "WINCONNECT $name: url ".$param->{url}." returned: $data";
		
		if(!defined($hash->{helper}{SENDVERSION})) {$hash->{helper}{SENDVERSION}='';}
		
		# 2017.07.26 - Check update
		if ( AttrVal( $name, "autoupdatewincontrol", 1 ) == 1 ) {
			if ($VerWin < $VerGit && $hash->{helper}{SENDVERSION} eq  '2' && $service ne 'notifymsg') {
				# Neue Version vorhanden
				$hash->{helper}{SENDVERSION} = '1';
				WINCONNECT_SendCommand( $hash, "notifymsg" , "=" . $Message);
			} else{
				delete($hash->{helper}{SENDVERSION})
			}
		}
    }

	readingsEndUpdate( $hash, 1 );

}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub WINCONNECT_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "WINCONNECT $name: called function WINCONNECT_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

1;
=pod
=item device
=item summary control for Windows based systems via network connection
=item summary_DE Steuerung von Windows basierte Systemen &uuml;ber das Netzwerk
=begin html

<a name="WINCONNECT"></a>
<h3>WINCONNECT</h3>
<ul>
  This module controls a Windows PC.
  <br><br>
  
    <ul>
      <a name="WINCONNECTdefine" id="WINCONNECTdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; WINCONNECT &lt;ip-address-or-hostname&gt; [&lt;poll-interval&gt;]</code><br>
        <br>
        Defining an WINCONNECT device will schedule an internal task (interval can be set with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 45 seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br>
        <br>
        Example:<br>
        <ul>
          <code>define Buero.PC WINCONNECT 192.168.0.10<br>
          <br>
          # With custom interval of 60 seconds<br>
          define Buero.PC WINCONNECT 192.168.0.10 60<br></code>
		</ul>
	  </ul>
	</ul>
	
  <br><br>
    More information on <a target="_blank" href="https://wiki.fhem.de/wiki/WINCONNECT">FHEM Wiki</a>.<br/>
  <br>
</ul>

=end html
=begin html_DE

<a name="WINCONNECT"></a>
<h3>WINCONNECT</h3>
<ul>
  Dieses Module dient zur Steuerung eines Windows PCs 
  <br><br>
  
    <ul>
      <a name="WINCONNECTdefine" id="WINCONNECTdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; WINCONNECT &lt;ip-address-or-hostname&gt; [&lt;poll-interval&gt;]</code><br>
        <br>
        F&uuml;r definierte WINCONNECT Ger&auml;te wird ein interner Task angelegt, welcher periodisch die Readings aktualisiert. Der Standartpollintervall ist 45 Sekunden.<br>
        <br>
        Example:<br>
        <ul>
          <code>define Buero.PC WINCONNECT 192.168.0.10<br>
          <br>
          # Alternativer poll intervall von 60 seconds<br>
          define Buero.PC WINCONNECT 192.168.0.10 60<br></code>
      </ul>
    </ul>
	</ul>
  <br><br>
    Mehr Information im <a target="_blank" href="https://wiki.fhem.de/wiki/WINCONNECT">FHEM Wiki</a>.<br/>
  <br>
</ul>

=end html_DE
=cut
