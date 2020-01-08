#######################################################################################################################################################
# $Id$
# 
# Original von Wzut https://forum.fhem.de/index.php?topic=77678.0
# modifiziert von Bismosa
#
# Dieses Modul erweitert die Heizkörpersteuerung MAX um eine genauere Einstellmöglichkeit. 
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#######################################################################################################################################################
#
# Mögliche Kombinationen:
#	HT/WT	|	<auto|manual>	|	<temp|eco|comfort|boost|off|on>	|	<until> (auto nzw. mannual wird ignoriert. Es wird in den Urlaubsmodus gesetzt)
#######################################################################################################################################################
#	
#TODO:
#- 
#- 
#
#######################################################################################################################################################

package main;

use strict;
use warnings;
use Date::Parse;

#####################################
sub MAX_Temperature_Initialize($)
{
    my ($hash) = @_;
    $hash->{DefFn}		= "MAX_Temperature_Define";
    $hash->{UndefFn}	= "MAX_Temperature_Undef";
    $hash->{AttrFn}		= "MAX_Temperature_Attr";  
    $hash->{SetFn}		= "MAX_Temperature_Set";
    #$hash->{GetFn}		= "MAX_Temperature_Get";		#Derzeit kein Get-Befehl
    #$hash->{ParseFn}	= "MAX_Temperature_Parse";
    $hash->{AttrList}	= "maxDay:1,2,3,4,5,6,7,14,21,28,35 "
			."maxHour:6,12,18,24 "
			."createAT:0,1 " 
			."autoAT_room " 
			."ignoreDevices "
			."addDevices "
			."addDevicesFirst:0,1 " 
			."addGroups " 
			."addGroupsFirst:0,1 "	
			."DevicesAlias "
			."ShowMSg:0,1 "
			."SendButton "
			."ResetButton "
			."Layout:textField-long "
			.$readingFnAttributes;
    
    $hash->{NotifyFn}	= "MAX_Temperature_Notify";
    $hash->{FW_summaryFn}	= "MAX_Temperature_summaryFn";         	# displays html instead of status icon in fhemweb room-view
    
    #$hash->{FW_hideDisplayName} = 1;                  			# Forum 88667 
    #$hash->{FW_detailFn}	= "MAX_Temperature_summaryFn";         	# displays html instead of status icon in fhemweb room-view
    #$data{webCmdFn}{MAX_Temperature} = "MAX_Temperature_webCmdFn";	# displays rc instead of device-commands on the calling device
    #$hash->{FW_atPageEnd} = 1; 					# wenn 1 -> kein Longpoll ohne informid in HTML-Tag
}

###################################
sub MAX_Temperature_Define($$){
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    my @a = split("[ \t][ \t]*", $def);
    
    Log3 $name, 4, "$name: Anzahl Argumente = ".int(@a);
    Log3 $name, 4, "$name: Argument0 = ".$a[0] if(int(@a) > 0);
    Log3 $name, 4, "$name: Argument1 = ".$a[1] if(int(@a) > 1);
    Log3 $name, 4, "$name: Argument2 = ".$a[2] if(int(@a) > 2);
    Log3 $name, 4, "$name: Argument3 = ".$a[3] if(int(@a) > 3);
    
    if ($init_done == 1){
	#nur beim ersten define setzen:
	$attr{$name}{icon} = "sani_heating" if( not defined( $attr{$name}{icon} ) );
	$attr{$name}{ShowMSg} = "1" if( not defined( $attr{$name}{ShowMSg} ) );
	$attr{$name}{room} = "MAX" if( not defined( $attr{$name}{room} ) );
	$attr{$name}{SendButton} = "audio_play" if( not defined( $attr{$name}{SendButton} ) );
	$attr{$name}{ResetButton} = "control_x" if( not defined( $attr{$name}{ResetButton} ) );
	$attr{$name}{Layout} = "[DEVICE][MODE][TEMP][SEND][DATE][CLOCK][SEND]<br>[STATE]" if( not defined( $attr{$name}{Layout} ) );
    } else {
	#Log3 $name, 1, "$name: already defined";
    }
    
    $hash->{STATE} = "Defined";
    
    my $ok;
    if (!defined($a[2])){
	$a[2] = "T";
	$ok=1;
    } else {
	if (($a[2] eq "T") || ($a[2] eq "HT") || ($a[2] eq "WT")){
	    $ok=1;
	}
	if ($a[2] =~ m/^[A-F0-9]{6}$/i){
	    $ok=1;
	}
    }
    return "Wrong syntax: use define <name> MAX_Temperature <Optional:T|HT|WT|addr>" if (!$ok);
    
    #T = Alle Max-Devices
    #HT = nur Thermostate
    #WT = nur Wandthermostate
    #addr = nur ein Device
    Log3 $name, 1, "$name: $a[2]";
    $hash->{MAXDEVICE} = $a[2];
    
    #Rücksetzen des Devices
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"Selected_Device","---");
    readingsBulkUpdate($hash,"Selected_MaxDevice","---");
    readingsEndUpdate($hash,1);
    #Auf keine Events von außerhalb reagieren
    $hash->{NOTIFYDEV} = 'global';
    
    #Standards setzen, die unbedingt vorhanden sein sollten
    $attr{$name}{maxHour}= '12'            unless (exists($attr{$name}{maxHour}));
    $attr{$name}{maxDay}= '14'            unless (exists($attr{$name}{maxDay}));
    
    return undef;
}

#####################################
sub MAX_Temperature_Undef($$) {
    my ($hash, $name) = @_;
    delete($modules{MAX_Temperature}{defptr}{$hash->{DEF}}) if(defined($hash->{DEF}) && defined($modules{MAX_Temperature}{defptr}{$hash->{DEF}}));
    return undef;
}

#####################################
sub MAX_Temperature_Attr(@) {
    my ($cmd, $name, $attrName, $attrValue) = @_;
    my $hash = $defs{$name};
    
    if ($init_done == 1) {
    
    
	if ($cmd eq "set") {
	
	}
	##disabled?
	if ($attrName eq "disable"){
	
	}
    
    if ($attrName eq "disable"){
      
    }
	
	Log3 $name, 4, "$name: $cmd attr $attrName to $attrValue" if (defined $attrValue);
	Log3 $name, 4, "$name: $cmd attr $attrName" if (not defined $attrValue);
    }
    
    

    return undef;
}

#####################################
sub MAX_Temperature_Set($@){
    my ($hash, @a) = @_;
    my $name = shift @a;
    #return undef if(IsDisabled($name) || !$init_done);
    #return "no set value specified" if(int(@a) < 1);

    my $cmd = shift @a;
    my $val = shift @a;
    
    if ($cmd eq "reset"){
	#Zuletzt gewähltes Device verwenden!
	$val = ReadingsVal("$name", "Selected_Device", "---");
	MAX_Temperature_SetDevice($hash, $val);
	#MAX_Temperature_Reset($hash);
	return "ok";
    }
    if ($cmd eq "start"){
	my $retValue = MAX_Temperature_Execute($hash);
	#Nicht zurücksetzen, wenn ERROR!
	if ($retValue =~ /^ERROR/){
	    return $retValue;
	}
	$val = ReadingsVal("$name", "Selected_Device", "---");
	MAX_Temperature_SetDevice($hash, $val);
	readingsSingleUpdate($hash,"state","OK",1);
	return $retValue;
	
    }
    if ($cmd eq "device"){
	MAX_Temperature_SetDevice($hash, $val);
	return;
    }
    
    
  
    return;
}

#####################################
sub MAX_Temperature_Execute($) {
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $device = ReadingsVal($name,"Selected_MaxDevice","---");
    return "ERROR: please set Device first !" if ($device  eq "---");
    
    my $mode = ReadingsVal($name,"Selected_Mode","");
    my $temp = ReadingsVal($name,"Selected_Temperatur","---");
    return "ERROR: please set mode first !" if ($mode eq "");
    return "ERROR: please set Temperature or mode first !" if ($temp eq "---") and ($mode eq "---");
    
    $mode = "" if ($mode eq "---");
    
    my $time_s = ReadingsVal($name,"Selected_Uhrzeit","---");
    return "ERROR: please set Temperature first!" if ($temp eq "---") and ($time_s ne "---");
    
    
    my $timeDay = ReadingsVal($name,"Selected_Datum","---");
    return "ERROR: please set Date first!" if ($timeDay eq "---") and ($time_s ne "---");
    
    #Zeit zusammensetzen
    if ($time_s eq "---"){
	$time_s = "";
    } else {
	$time_s = $timeDay.".".$time_s;
    }
    
    #CreateAT
    my $stxt;
    my $ATtxt;
    my $error;
    my @ar;
    my $Sekunden = 10; 	
    if ($time_s && int(AttrVal($name,"createAT",0))){
	@ar = split("\\.",$time_s.":".sprintf("%02d",$Sekunden));
	my $time_at = $ar[2]."-".$ar[1]."-".$ar[0]."T".$ar[3];
	
    my $autoAT = "autoAT_".$device;
	#Illegale Zeichen entfernen/ersetzen
    $autoAT =~ s/[^A-Za-z0-9]/_/g; # Replace all non-alphanumericals with "_"
    
    $ATtxt = $autoAT." at ".$time_at." set $device desiredTemperature auto";
	$error = CommandDefine(undef, $ATtxt);
	if (($defs{$autoAT}) && !$error && (AttrVal($name,"autoAT_room","MAX") ne "Unsorted")){
	    $attr{$autoAT}{room} = AttrVal($name,"autoAT_room","MAX");
	}
	Log3 $name,3,"$name, error -> ".$error if($error);
	Log3 $name,4,"$name, define -> $ATtxt";
    }
    
    if ($time_s){
	my @ar = split("\\.",$time_s);
	$time_s = $ar[0].".".$ar[1].".".$ar[2]." ".$ar[3];
	#<mode> ist hier nicht erforderlich!
	$stxt = "$device desiredTemperature $temp until ".$time_s;
    } else {
    # keine Zeitangabe
    #Es muss eine Temperatur übermittelt werden. 
    #Wird ein --- übertragen kommt es zu einem Log-Eintrag der Modus wird aber umgeschaltet
    #Wird die Temperatur "0" übergeben, kommt keine Fehlermeldung
	if ("$temp" eq "---"){
	    $temp = 0;
	}
	$stxt = "$device desiredTemperature $mode $temp";
    }
    
    Log3 $name,4,"$name, set -> ".$stxt;
    $error = CommandSet(undef, $stxt);

    if($error){ 
	Log3 $name,3,"$name, error -> ".$error; 
	return "ERROR: $error";
    } else {
	my $showMsg = AttrVal($name,"ShowMsg",1);
	if ($showMsg eq 1){
      if (defined ($ATtxt)){
        return "OK: set ".$ATtxt."<br>".$stxt;
      } else {
        return "OK: set ".$stxt;
      }
	} else {
	    if (defined ($ATtxt)){
        return $ATtxt."<br>".$stxt;
      } else {
        return $stxt;
      }
	}
    }
}

#####################################
sub MAX_Temperature_SetDevice($$){
    my $hash = shift;
    my $name = $hash->{NAME};
    my $device = shift;
  
    #Zuerst alle Werte löschen!
    MAX_Temperature_Reset($hash);
  
    #Standardwerte setzen
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"Selected_Device",$device);
  
    my $MaxDevice = MAX_Temperature_GetDeviceFromName($hash,$device);
    readingsBulkUpdate($hash,"Selected_MaxDevice",$MaxDevice);
  
    my $Temperatur = ReadingsVal("$MaxDevice", "desiredTemperature", "---");
    readingsBulkUpdate($hash,"Selected_Temperatur","$Temperatur");
  
    my $mode = ReadingsVal("$MaxDevice", "mode", "---");
    readingsBulkUpdate($hash,"Selected_Mode","$mode");
  
    readingsBulkUpdate($hash,"Selected_Datum","---");
    readingsBulkUpdate($hash,"Selected_Uhrzeit","---");
    readingsEndUpdate($hash,1);
    
    return; 
}

#####################################
sub MAX_Temperature_Reset($){
    my $hash = shift;
    my $name = $hash->{NAME};
  
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"Selected_Device","---");
    readingsBulkUpdate($hash,"Selected_Temperatur","---");
    readingsBulkUpdate($hash,"Selected_Mode","---");
    readingsBulkUpdate($hash,"Selected_Datum","---");
    readingsBulkUpdate($hash,"Selected_Uhrzeit","---");
    readingsEndUpdate($hash,1);
    return;
}

#####################################
sub MAX_Temperature_Notify($$){
    # $hash is my hash, $dev_hash is the hash of the changed device
    my ($hash, $dev_hash) = @_;
    my $events = deviceEvents($dev_hash,0);
    my $name   = $hash->{NAME};
    my $device = $dev_hash->{NAME};

    #Log3 $name,3,"$name, event from $device -> $events";
    
    my @MaxDevices = split(/,/, ReadingsVal($name,"Selected_MaxDevice",""));
    my $IsMyDevice = 0;
    
    for my $MaxDev(@MaxDevices){
	if ($MaxDev eq $device){
	    $IsMyDevice = 1;
	}
    }
    
    #Wenn Structure
    if ($IsMyDevice == 0){
	my @StrucDevices = MAX_Temperature_GetStructureDevices($hash, ReadingsVal($name,"Selected_MaxDevice",""));
	#Log3 $name,3,"$name, $device scalar:".scalar @StrucDevices;
	if (scalar @StrucDevices == 0){
	    #keine structure
	} else {
	    #Log3 $name,3,"$name, $device Structure!";
	    for my $MaxDev(@StrucDevices){
		if ($MaxDev eq $device){
		    $IsMyDevice = 1;
		}
	    }
	}
    }
    
    #Log3 $name,3,"$name, $device IsmyDevice -> $IsMyDevice";
    
    return undef if ($IsMyDevice eq 0);
    
    my $state = MAX_Temperature_GetDevState($hash);
    return undef;
}

#####################################
sub MAX_Temperature_summaryFn($$$$){
    my ($FW_wname, $d, $room, $pageHash) = @_;										# pageHash is set fosummaryFn.
    my $hash   = $defs{$d};
    my $name = $hash->{NAME};
    my $stateFormat = AttrVal($name, "stateFormat", undef);
  
    if (defined($stateFormat)){
	return ;
    }
  
    my $html;
    #$html = "<div><table class=\"block wide\"><tr>"; 
    
    $html=MAX_Temperature_HTML($hash);
    #Log3 $name,1,"$name, $html";
    return $html;
    
}

#####################################
#HTML
sub MAX_Temperature_HTML($){
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $Layout = AttrVal($name, "Layout", "[DEVICE][MODE][TEMP][SEND][DATE][CLOCK][SEND]<br>[STATE]");
	
    #Log3 $name,1,"$name, $Layout";
    
    my $htmlState = MAX_Temperature_GetDevState($hash);
    
    my $htmlDev = MAX_Temperature_GetHTMLSelectMaxDevice($hash);
    my $htmlMode = MAX_Temperature_GetHTMLSelectMode($hash);
    my $htmlTemp = MAX_Temperature_GetHTMLSelectTemperaturen($hash);
    my $htmlDatum = MAX_Temperature_GetHTMLSelectDatum($hash);
    my $htmlUhrzeit = MAX_Temperature_GetHTMLSelectUhrzeit($hash);
    my $htmlSend = MAX_Temperature_GetHTMLSend($hash);
    my $htmlReset = MAX_Temperature_GetHTMLReset($hash);
    
    my $html=$Layout;
    
    #Perl ausdrücke auswerten:
    #ACHTUNG! VOR SEND! Sonst fehlen die geschweiften klammern!
    if ($html =~ "{(.*)}") {
	my @list = ($html =~ m/{(.*?)}/g);
	foreach my $perlv(@list){
	    my $val = eval($perlv);
	    $html =~ s/\Q{$perlv}\E/$val/g;
	}
    }
    
    $html =~ s/\[STATE\]/$htmlState/g;
    $html =~ s/\[DEVICE\]/$htmlDev/g;
    $html =~ s/\[MODE\]/$htmlMode/g;
    $html =~ s/\[TEMP\]/$htmlTemp/g;
    $html =~ s/\[DATE\]/$htmlDatum/g;
    $html =~ s/\[CLOCK\]/$htmlUhrzeit/g;
    $html =~ s/\[SEND\]/$htmlSend/g;
    $html =~ s/\[RESET\]/$htmlReset/g;
  
    return $html;
}

#####################################
#Devices der Structure
sub MAX_Temperature_GetStructureDevices($$){
    my $hash = shift;
    my $name = $hash->{NAME};
    my $structureName = shift;
    
    my @StrucDevices;
    
    #Prüfen, ob es eine structure ist:
    my $Devhash = $defs{$structureName};
    if (defined($Devhash->{TYPE})){
	if ($Devhash->{TYPE} eq "structure"){
	    @StrucDevices = split(/ /, $Devhash->{DEF});
	    splice @StrucDevices, 0, 1;
	    return @StrucDevices;
	}
    }
    
    return @StrucDevices;
}

#####################################
#Stauts: mode / keepAuto / temperature / desiredTemperature
sub MAX_Temperature_GetDevState($){
    my $hash = shift;
    my $name = $hash->{NAME};
    my $maxdev = ReadingsVal($name,"Selected_MaxDevice","???");
    my $state = "";
    
    my @MaxDevices;
    
    my $AddDeviceName = 0;
    
    #Prüfen, ob es eine structure ist:
    my @StrucDevices = MAX_Temperature_GetStructureDevices($hash, $maxdev);
    if (scalar @StrucDevices == 0){
	#Keine structure - Normal weiter
	@MaxDevices=split(/,/, $maxdev);
	if (scalar(@MaxDevices) > 1){
	    $AddDeviceName = 1;
	}
    } else {
	#structure
	@MaxDevices = @StrucDevices;
	$AddDeviceName = 1;
    }
    
    for my $maxdev(@MaxDevices){
	if ($state ne ""){
	    $state .= "<br>";
	}
	$state .= "Mode:".ReadingsVal($maxdev,"mode","???")." keepAuto:".AttrVal($maxdev,"keepAuto","?");
	$state .= " Temp:".ReadingsVal($maxdev,"temperature","???")."°C desiredTemp:".ReadingsVal($maxdev,"desiredTemperature","???")."°C";
	if ($AddDeviceName){
      my $DeviceAlias = AttrVal($maxdev,"alias","?");
      if ("$DeviceAlias" eq "?"){
        $state .= " ($maxdev)";
      } else {
        $state .= " ($DeviceAlias)";
      }
	    
	}
    }
    readingsSingleUpdate($hash,"state",$state,1);
    
    #Anzahl der zu verarbeitenden Events beggrenzen
    #TODO! Das ist nur, wenn Device Aufgerufen! Nicht nach neustarrt!!!
    $hash->{NOTIFYDEV} = join(",",@MaxDevices);
  
    return $state;
}

#####################################
#HTML Select Max-Device
sub MAX_Temperature_GetHTMLSelectMaxDevice($){
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my @Devices=MAX_Temperature_GetDevices($hash);
    
    my $Reading = "Selected_Device";
    my $DDSelected = ReadingsVal($name, $Reading, "");
    $DDSelected =~ s/ /&nbsp;/g;
    $DDSelected =~ s/\xC2\xA0/&nbsp;/g; #non-page-breaking-space
    my $html="";
    
    
    if (scalar @Devices > 1){
	#Select
	my $changecmd = "cmd.$name=set $name device ";
	$html.= "<select id=\"$name$Reading\" name=\"val.$name\" onchange=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$changecmd ' + this.options[this.selectedIndex].value.replace(' ','&nbsp;'))\">";
	#Log3 $name,1,"DDESELECTED $DDSelected";
    if ("$DDSelected" eq "---"){
      $html.= "<option selected value=\"---\">---</option>";
    }
    foreach my $Device(@Devices) {
	    if ("$DDSelected" eq "$Device"){
		
		$html.= "<option selected value=\"".($Device)."\">".($Device)."</option>";
	    } else {
		$html.= "<option value=\"".($Device)."\">".($Device)."</option>";
	    }
	}
	$html.="</select>";
    } else {
	#Nur Device-Name
	if (scalar @Devices eq 1){
	    $html.=$Devices[0];
	    #Setzen des richtigen Namens, wenn erforderlich
	    if (ReadingsVal($name, "Selected_Device", "---") eq "---"){
		MAX_Temperature_SetDevice($hash, $Devices[0]);
	    }
	} else {
	    $html.="not defined";
	}
    }
    
    return $html;
}

#####################################
#Eine Liste der Devices bekommen
#Namen mit leerzeichen -> Immer mit &nbsp;
sub MAX_Temperature_GetDevices($){
    my $hash = shift;
    my $name = $hash->{NAME};
    my $def = $hash->{DEF};
    
    my @ar;
    
    my $type    = "?";
    
    #Ignored Devices
    my $ignoreDevices = AttrVal($name,"ignoreDevices","");
    my @ignoreDevicesList = split(/,/, $ignoreDevices);
    
    #Add Devices/Alias
    my $addDevices = AttrVal($name,"addDevices","");
    my @addDevicesList = split(/,/, $addDevices);
    my $addDevicesFirst = AttrVal($name,"addDevicesFirst",0);
  
    if (($hash->{MAXDEVICE} eq "T") || ($hash->{MAXDEVICE} eq "HT") || ($hash->{MAXDEVICE} eq "WT")){
	$type = ".*Thermostat"          if ($hash->{MAXDEVICE} eq "T");
	$type = "HeatingThermostat"     if ($hash->{MAXDEVICE} eq "HT");
	$type = "WallMountedThermostat" if ($hash->{MAXDEVICE} eq "WT");
	@ar = devspec2array("DEF=".$type.".*");
    }else {
	@ar = devspec2array("DEF=.*Thermostat ".$hash->{MAXDEVICE});
    }
    
    #Filtern der ignoreDevices
    my %h;
    @h{@ignoreDevicesList} = undef;
    @ar = grep {not exists $h{$_}} @ar;
    
    #hinzufügen manueller Devices
    if ($addDevicesFirst){
	my @arNEU = @addDevicesList;
	push(@arNEU, @ar);
	@ar = @arNEU;
    }else{
	push(@ar, @addDevicesList);
    }
    
    #hinzufügen von Gruppen
    #Grp1:dev1,dev2 Grp2:dev3,dev4
    my $AddGroup = AttrVal($name,"addGroups","");
    my @AddGroups = split(/ /, $AddGroup);
    my $addGroupsFirst = AttrVal($name,"addGroupsFirst",0);
    #Liste erstellen
    my @Groups;
    for my $Grp(@AddGroups){
	my @split=split(/:/, $Grp);
	my $GrpName=$split[0];
	#my @GrpDevices=split(/,/, $split[1]);
	push (@Groups,$GrpName);
    }
      
    if ($addGroupsFirst){
	my @arNEU = @Groups;
	push(@arNEU, @ar);
	@ar = @arNEU;
    }else{
	push(@ar, @Groups);
    }
    
    #Umbenennen von den Devices
    #<Device>:<Alias>,<Device2>:Alias mit leerzeichen,<Device3>:<Alias3>
    #Max_HT_Buero:
    my @aliase = split(/,/, AttrVal($name,"DevicesAlias",""));
    
    for my $dev(@ar){
	for my $alias(@aliase){
	    my @list=split(/:/,$alias);
	    my $AliasDevice=$list[0];
	    my $AliasDeviceName=$list[1];
	    #Log3 $name,1,"$name $dev $AliasDeviceName";
	    if ($AliasDevice eq $dev){
		$dev=$AliasDeviceName;
		#Log3 $name,1,"$name $dev $AliasDeviceName";
	    }
	}
    }
    
    #Leerzeichen mit &nbsp; ersetzen
    for my $dev(@ar){
	$dev =~ s/ /&nbsp;/g;
    }
    return @ar;
  
}

#####################################
#Das Max-Device (ggf. Kommaliste) zurückbekommen
sub MAX_Temperature_GetDeviceFromName($$){
    my $hash = shift;
    my $caption = shift;
    my $name = $hash->{NAME};
    
    my $MaxDevice = $caption; #ggf. bereits das Device
    $caption =~ s/ /&nbsp;/g;
    $caption =~ s/\xC2\xA0/&nbsp;/g; #non-page-breaking-space
    #Gruppe?
    my $AddGroup = AttrVal($name,"addGroups","");
    my @AddGroups = split(/ /, $AddGroup);
    my @Groups;
    for my $Grp(@AddGroups){
	my @split=split(/:/, $Grp);
	my $GrpName=$split[0];
	$GrpName =~ s/ /&nbsp;/g;
        $GrpName =~ s/\xC2\xA0/&nbsp;/g; #non-page-breaking-space
	#my @GrpDevices=split(/,/, $split[1]);
	#Log3 $name,1,"$name $caption $GrpName";
	if ($caption eq $GrpName){
	    $MaxDevice = $split[1];
	}
    }
    
    #Alias?
    my @aliase = split(/,/, AttrVal($name,"DevicesAlias",""));
    for my $alias(@aliase){
	my @list=split(/:/,$alias);
	my $AliasDevice=$list[0];
	my $AliasDeviceName=$list[1];
	$AliasDeviceName =~ s/ /&nbsp;/g;
        $AliasDeviceName =~ s/\xC2\xA0/&nbsp;/g; #non-page-breaking-space
	#Log3 $name,1,"$name $dev $AliasDeviceName";
	if ($caption eq $AliasDeviceName){
	    $MaxDevice = $AliasDevice;
	}
    }
    
    return $MaxDevice;
}

#####################################
#HTML Select Mode
sub MAX_Temperature_GetHTMLSelectMode($){
    my $hash = shift;
    my $name = $hash->{NAME};
    
    #Log3 $name,1,"$name, event MAX_Temperature_GetHTMLSelectMode";
    
    my $mode	= "---,auto,manual";
    my $html	= MAX_Temperature_GetHTMLSelectListe($hash, $mode,"Selected_Mode");
    
    return $html;
}

#####################################
#HTML Select Temperaturen
sub MAX_Temperature_GetHTMLSelectTemperaturen($){
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $temp    = "---,off,eco,comfort,boost,";
    my $i;
    for ($i=0;$i<52;$i++) { $temp .= sprintf("%.1f",5+(0.5*$i)).","; }
    $temp .="on";
    
    my $html	= MAX_Temperature_GetHTMLSelectListe($hash, $temp,"Selected_Temperatur");
    return $html;
}

#####################################
#HTML Select Datum
sub MAX_Temperature_GetHTMLSelectDatum($){
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $maxDay = int(AttrVal($name,"maxDay",7));
    
    my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, undef, undef, undef) = localtime(time);
    my $Heute = sprintf("%02d.%02d.%02d",$Monatstag,$Monat+1,$Jahr+1900);
    
    my $d = "---,";
    for (my $i=0;$i<$maxDay;$i++)
    {
	(undef, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, undef, undef, undef) = localtime(time+($i*24*60*60));
	$d .= sprintf("%02d.%02d.%02d",$Monatstag,$Monat+1,$Jahr+1900).",";
    }
    chop($d);
    
    my $html	= MAX_Temperature_GetHTMLSelectListe($hash, $d,"Selected_Datum");
    return $html;
    
}

#####################################
#HTML Select Uhrzeit
sub MAX_Temperature_GetHTMLSelectUhrzeit($){
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $maxHour = int(AttrVal($name,"maxHour",12));
    my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, undef, undef, undef) = localtime(time);
    my $m = (int($Minuten) < 30) ? 30-int($Minuten) : 60-int($Minuten);
    my $t = "---,";
  for (my $i=0;$i<$maxHour*2;$i++)
    {
	(undef, $Minuten, $Stunden, $Monatstag, $Monat, $Jahr, undef, undef, undef) = localtime(time+($i*1800)+($m*60)-$Sekunden);
	$t .= sprintf("%02d\:%02d",$Stunden,$Minuten).",";
    }
    chop($t);
    
    my $html	= MAX_Temperature_GetHTMLSelectListe($hash, $t,"Selected_Uhrzeit");
    return $html;
}

#####################################
#HTML Select nach Liste
sub MAX_Temperature_GetHTMLSelectListe($$$){
    my $hash = shift;
    my $Names = shift;
    my $ReadingName = shift;
    my $name = $hash->{NAME};
    
    my @modes = split(/,/, $Names);
    my $html	= "";
    my $DDSelected = ReadingsVal($name, $ReadingName, "");
    
    my $changecmd = "cmd.$name=setreading $name $ReadingName ";
    $html.= "<select name=\"val.$name\" onchange=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$changecmd ' + this.options[this.selectedIndex].value)\">";
    
    foreach my $mode (@modes) {
	if ($DDSelected eq "$mode"){
	    $html.= "<option selected value=".($mode).">".($mode)."</option>";
	} else {
	    $html.= "<option value=".($mode).">".($mode)."</option>";
	}
    }
    $html.="</select>";
    return $html; 
}

#####################################
#HTML Send Bild oder Text
sub MAX_Temperature_GetHTMLSend($){
    #entweder Button oder Text
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $Icon = AttrVal($name, "SendButton", "audio_play");
    my $html;
    my $img = FW_makeImage("$Icon");
    #Log3 $name,1,"$name, $img";
    my $cmd = "cmd.$name=set $name start";
    
    my $showMsg = AttrVal($name,"ShowMsg",1);
    if ($showMsg eq 0){
	$html.="<a style=\"cursor: pointer;\" onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a>";
    } else {
	$html.="<a style=\"cursor: pointer;\" onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd',function(data){FW_okDialog(data)})\">$img</a>";
    }
    
#		$html.=<<'EOF';
#				<script type="text/javascript">
#				function myFunction(data){alert(data)}
#				</script>
#EOF
#Make sure "EOF" is on a line by itself with no preceeding or trailing spaces, tabs, etc.	
    #FW_cmd(FW_root+'?cmd={FW_makeImage("fts_shutter_10")}&XHR=1', function(data){FW_okDialog(data)});
    #Log3 $name,1,"$name, $html";
    return $html;
}

#####################################
#HTML Reset Bild oder Text
sub MAX_Temperature_GetHTMLReset($){
    #entweder Button oder Text
    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $Icon = AttrVal($name, "ResetButton", "control_x");
    my $html;
    my $img = FW_makeImage("$Icon");
    #Log3 $name,1,"$name, $img";
    my $cmd = "cmd.$name=set $name reset";
    $html.="<a style=\"cursor: pointer;\" onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a>";
    return $html;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper]
=item summary Set MAX-Heating Devices
=item summary_DE MAX-Heizkörperthermostate setzen
=begin html

<a name="MAX_Temperature"></a>
<h3>MAX_Temperature</h3>
<div>
    <ul>
	<p>This module extends the MAX radiator control by additional setting options.<br>
	Possibilities:<br>
	- Set the temperature for one or more radiator thermostats. <br>
	- Set the temperature and time (vacation mode). <br>
	- Groups can be defined for this module. <br>
	- Individual devices can be added or excluded. <br>
	- The layout for the selection fields can be adjusted as required. <br>
	</p>
	<h4>Examples:</h4>
	<p>
	    <code>define MaxTemp MAX_Temperature</code><br>
	    <code>define MaxTemp MAX_Temperature T</code><br>
	    <code>define MaxTemp MAX_Temperature HT</code><br>
	    <code>define MaxTemp MAX_Temperature WT</code><br>
	    <code>define MaxTemp MAX_Temperature 123456</code><br>
	</p>
      
	<a name="MAX_Temperature_Define"></a>
        <h4>Define</h4>
	<p><code>define &lt;NAME&gt; MAX_Temperature</code><br>
	    Definition of a temperature module for all radiator thermostats and wall thermostats.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature T</code><br>
	    Definition of a temperature module for all radiator thermostats and wall thermostats.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature HT</code><br>
	    Definition of a temperature module only for radiator thermostats.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature WT</code><br>
	    Definition of a temperature module only for wall thermostats.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature 123456</code><br>
	    Definition of a temperature module for a specific thermostat.<br>
	</p>
    </ul>

  <h4>Attributes</h4>
  <ul><a name="MAX_Temperature_Attr"></a>
    <li><a name="Layout">Layout</a><br>
	    <code>attr &lt;NAME&gt; Layout &lt;HTML&gt;</code><br>
            Possibility of layout of the advertisement. <br> <br>
             It is possible to define the layout yourself. HTML code is possible. Examples: <br>
             Standard: <br>
            [DEVICE][MODE][TEMP][SEND][DATE][CLOCK][SEND]&lt;br&gt;\n[STATE]<br><br>
            
            Structure as a table:<br>
            [STATE]&lt;br&gt;&lt;table class=\"block wide\"&gt;&lt;tr&gt;&lt;td&gt;[DEVICE]&lt;/td&gt;&lt;td&gt;[MODE]&lt;/td&gt;&lt;td&gt;[DATE]&lt;/td&gt;&lt;td&gt;[CLOCK]&lt;/td&gt;&lt;td&gt;[SEND]&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;
            <br><br>
            
            Without setting the Holiday mode:<br>
            [STATE]&lt;br&gt; [DEVICE][MODE][TEMP][SEND]<br><br>
            
            Holiday mode setting only:<br>
            [STATE]&lt;br&gt; [DEVICE][TEMP][DATE][CLOCK][SEND]<br><br>
            
            All entries one below the other:<br>
            [STATE]&lt;br&gt;<br>
            [DEVICE]&lt;br&gt;<br>
            [MODE]&lt;br&gt;<br>
            [TEMP]&lt;br&gt;<br>
            [DATE]&lt;br&gt;<br>
            [CLOCK]&lt;br&gt;<br>
            [SEND]&lt;br&gt;<br><br>
            
            It is also possible to add Perl code (in curly brackets)<br>
            {ReadingsVal("myDevice","MyReading","Default_Value")}[STATE][DEVICE][MODE][TEMP][SEND][DATE][CLOCK][SEND]<br><br>
            
            <b>Special entries:</b><br>
            <table>
             <colgroup> <col width="120"></colgroup>
              <tr>
                <td>[STATE]</td>
                <td>Status<br>
                    Display of readings of the selected MAX device. <br>
                     Standard: Mode: (auto | manual | temporary) keepAuto: (0 | 1) Temp: (current temperature) desiredTemperature: (set temperature) <br>
                     If a group is selected, the name of the group is displayed here.
                </td>
              </tr>
              <tr>
                <td>[DEVICE]</td>
                <td>Selection box or name of the selected MAX device.</td>
              </tr>
              <tr>
                <td>[MODE]</td>
                <td>Selection box for the mode (auto | manual).</td>
              </tr>
              <tr>
                <td>[TEMP]</td>
                <td>Selection box for the desired temperature.</td>
              </tr>
              <tr>
                <td>[DATE]</td>
                <td>Selection box for the date.</td>
              </tr>
              <tr>
                <td>[CLOCK]</td>
                <td>Selection box for the time.</td>
              </tr>
              <tr>
                <td>[SEND]</td>
                <td>Button to send the new settings.</td>
              </tr>
              <tr>
                <td>[RESET]</td>
                <td>Button to reset the settings made.</td>
              </tr>
            </table>
    </li>
    <li><a name="maxDay">maxDay</a><br>
	    <code>attr &lt;NAME&gt; maxDay (1,2,3,4,5,6,7,14,21,28,35)</code><br>
            Setting how many days are entered in the selection field for the date.<br>
    </li>
    <li><a name="maxHour">maxHour</a><br>
	    <code>attr &lt;NAME&gt; maxHour (6,12,18,24)</code><br>
            Setting how many hours are entered in the selection field for the time.<br>
    </li>
    <li><a name="ignoreDevices">ignoreDevices</a><br>
	    <code>attr &lt;NAME&gt; ignoreDevices &lt;listing&gt;</code><br>
            List of devices to be ignored by the module. <br>
             Comma as separator. <br>
             Example: <br>
            MyMax_Wohnzimmer,MyMax_Schlafzimmer<br>
    </li>
    <li><a name="addDevices">addDevices</a><br>
	    <code>attr &lt;NAME&gt; addDevices &lt;listing&gt;</code><br>
            List of devices to be added to the selection list. <br>
	    This means that e.g. Add "structure". <br>
            Comma as separator. <br>
            Example: <br>
            Struc_heating1,Struc_heating2<br>
    </li>
    <li><a name="addDevicesFirst">addDevicesFirst</a><br>
	    <code>attr &lt;NAME&gt; addDevicesFirst (0|1)</code><br>
            Show the manually added devices first in the list.<br>
    </li>
    <li><a name="addGroups">addGroups</a><br>
	    <code>attr &lt;NAME&gt; addGroups (Text)</code><br>
            Create groups. <br>
             Examples: <br>
            <code>Basement:Max_Device1,Max_Device2,Max_Device3 Upstairs:Max_Device4,Max_Device5</code><br>
	    <code>Group&amp;nbsp;1:Max_Device1,Max_Device2,Max_Device3 Group&amp;nbsp;2:Max_Device4,Max_Device5</code><br>
            To insert a space in the group name, can be entered <code>&amp;nbsp;</code>. Example:<br>
            <code>My&amp;nbsp;Group:Device1,Device2</code>
    </li>
    <li><a name="addGroupsFirst">addGroupsFirst</a><br>
	    <code>attr &lt;NAME&gt; addGroupsFirst (0|1)</code><br>
            Show the groups first in the list.<br>
    </li>
    <li><a name="DevicesAlias">DevicesAlias</a><br>
	    <code>attr &lt;NAME&gt; addDevicesAlias &lt;listing&gt;</code><br>
            Assign an alias for the MAX devices. <br>
             Comma as separator. <br>
             Examples: <br>
            Struc_Radiator1:Radiator below,Struc_Radiator2:Radiator above<br>
	    Max-Device1:Radiator bathroom,Max-Device2:Radiator kitchen<br>
    </li>
    <li><a name="ShowMSg">ShowMSg</a><br>
	    <code>attr &lt;NAME&gt; ShowMSg (0|1)</code><br>
            After sending settings, display a success notification in a dialog.<br>
    </li>
    <li><a name="SendButton">SendButton</a><br>
	    <code>attr &lt;NAME&gt; SendButton (Text)</code><br>
            Either the name of a symbol or a text. Standard: <br>
            audio_play<br>
    </li>
    <li><a name="ResetButton">ResetButton</a><br>
	    <code>attr &lt;NAME&gt; ResetButton (Text)</code><br>
            Either the name of a symbol or a text. Standard: <br>
            control_x<br>
    </li>
    <li><a name="createAT">createAT</a><br>
	    <code>attr &lt;NAME&gt; createAT (0|1)</code><br>
            Automatically creates a temporary AT to the device after the time has expired <br>
	    to switch back to automatic mode. <br>
	    This is usually not necessary<br>
    </li>
    <li><a name="autoAT_room">autoAT_room</a><br>
	    <code>attr &lt;NAME&gt; autoAT_room MAX</code><br>
	    The room in which the temporary AT should be created. Default:<br>
            MAX<br>
    </li>
    
  </ul>
  
  <h4>Readings</h4>
  <ul><a name="MAX_Temperature_Readings"></a>
	<li><a name="Selected_*">Selected_*</a><br>
	    The currently selected values of the selection boxes.<br>
    </li>
  </ul>
    
</div>


=end html

=begin html_DE

<a name="MAX_Temperature"></a>
<h3>MAX_Temperature</h3>
<div>
    <ul>
	<p>Dieses Modul erweitert die Heizkörpersteuerung MAX um weitere Einstellmöglichkeiten.<br>
	Möglichkeiten:<br>
	- Setzen der Temperatur für ein oder mehrere Heizkörperthermostate.<br>
	- Setzen der Temperatur und der Zeit (Urlaubsmodus).<br>
	- Gruppen können für dieses Modul festgelegt werden.<br>
	- Es können einzelne Devices hinzugefügt oder auch ausgeschlossen werden.<br>
	- Das Layout für die Auswahlfelder kann beliebig angepasst werden.<br>
	</p>
	<h4>Beispiele:</h4>
	<p>
	    <code>define MaxTemp MAX_Temperature</code><br>
	    <code>define MaxTemp MAX_Temperature T</code><br>
	    <code>define MaxTemp MAX_Temperature HT</code><br>
	    <code>define MaxTemp MAX_Temperature WT</code><br>
	    <code>define MaxTemp MAX_Temperature 123456</code><br>
	</p>
      
	<a name="MAX_Temperature_Define"></a>
        <h4>Define</h4>
	<p><code>define &lt;NAME&gt; MAX_Temperature</code><br>
	    Definition eines Temperatur-Moduls für alle Heizkörperthermostate und Wandthermostate.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature T</code><br>
	    Definition eines Temperatur-Moduls für alle Heizkörperthermostate und Wandthermostate.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature HT</code><br>
	    Definition eines Temperatur-Moduls nur für Heizkörperthermostate.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature WT</code><br>
	    Definition eines Temperatur-Moduls nur für Wandthermostate.<br>
	</p>
    <p><code>define &lt;NAME&gt; MAX_Temperature 123456</code><br>
	    Definition eines Temperatur-Moduls für einen bestimmten Thermostaten.<br>
	</p>
    </ul>

  <h4>Attributes</h4>
  <ul><a name="MAX_Temperature_Attr"></a>
    <li><a name="Layout">Layout</a><br>
	    <code>attr &lt;NAME&gt; Layout &lt;HTML&gt;</code><br>
            Layoutmöglichkeit der Anzeige.<br><br>
            Es ist möglich das Layout selbst zu definieren. HTML-Code ist möglich. Beispiele:<br>
            Standard:<br>
            [DEVICE][MODE][TEMP][SEND][DATE][CLOCK][SEND]&lt;br&gt;\n[STATE]<br><br>
            
            Aufbau als Tabelle:<br>
            [STATE]&lt;br&gt;&lt;table class=\"block wide\"&gt;&lt;tr&gt;&lt;td&gt;[DEVICE]&lt;/td&gt;&lt;td&gt;[MODE]&lt;/td&gt;&lt;td&gt;[DATE]&lt;/td&gt;&lt;td&gt;[CLOCK]&lt;/td&gt;&lt;td&gt;[SEND]&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;
            <br><br>
            
            Ohne Einstellung des Urluabsmodus:<br>
            [STATE]&lt;br&gt; [DEVICE][MODE][TEMP][SEND]<br><br>
            
            Nur Einstellung des Urlaubsmodus:<br>
            [STATE]&lt;br&gt; [DEVICE][TEMP][DATE][CLOCK][SEND]<br><br>
            
            Alle Einträge untereinander:
            [STATE]&lt;br&gt;<br>
            [DEVICE]&lt;br&gt;<br>
            [MODE]&lt;br&gt;<br>
            [TEMP]&lt;br&gt;<br>
            [DATE]&lt;br&gt;<br>
            [CLOCK]&lt;br&gt;<br>
            [SEND]&lt;br&gt;<br><br>
            
            Es ist auch möglich Perl-Code hinzuzufügen (in geschweiften Klammern)<br>
            {ReadingsVal("meinDevice","MeinReading","Standardwert")}[STATE][DEVICE][MODE][TEMP][SEND][DATE][CLOCK][SEND]<br><br>
            
            <b>Spezielle Einträge:</b><br>
            <table>
             <colgroup> <col width="120"></colgroup>
              <tr>
                <td>[STATE]</td>
                <td>Status<br>
                    Anzeige von Readings des gewählten MAX-Gerätes.<br>
                    Standard: Mode: (auto|manual|temporary) keepAuto: (0|1) Temp: (aktuelle Temperatur) desiredTemperature: (eingestellte Temperatur)<br>
                    Wird eine Gruppe ausgewählt, wird hier der Name der Gruppe angezeigt.
                </td>
              </tr>
              <tr>
                <td>[DEVICE]</td>
                <td>Auswahlbox oder Name des gewählten MAX-Gerätes.</td>
              </tr>
              <tr>
                <td>[MODE]</td>
                <td>Auswahlbox für den Modus (auto|manual).</td>
              </tr>
              <tr>
                <td>[TEMP]</td>
                <td>Auswahlbox für die gewünschte Temperatur.</td>
              </tr>
              <tr>
                <td>[DATE]</td>
                <td>Auswahlbox für das Datum.</td>
              </tr>
              <tr>
                <td>[CLOCK]</td>
                <td>Auswahlbox für die Uhrzeit.</td>
              </tr>
              <tr>
                <td>[SEND]</td>
                <td>Button zum senden der neuen Einstellungen.</td>
              </tr>
              <tr>
                <td>[RESET]</td>
                <td>Button zum zurücksetzen der gemachten Einstellungen.</td>
              </tr>
            </table>
    </li>
    <li><a name="maxDay">maxDay</a><br>
	    <code>attr &lt;NAME&gt; maxDay (1,2,3,4,5,6,7,14,21,28,35)</code><br>
            Einstellung, wie viele Tage im Auswahlfeld für das Datum eingetragen werden.<br>
    </li>
    <li><a name="maxHour">maxHour</a><br>
	    <code>attr &lt;NAME&gt; maxHour (6,12,18,24)</code><br>
            Einstellung, wie viele Stunden im Auswahlfeld für das Zeit eingetragen werden.<br>
    </li>
    <li><a name="ignoreDevices">ignoreDevices</a><br>
	    <code>attr &lt;NAME&gt; ignoreDevices &lt;Auflistung&gt;</code><br>
            Auflistung von Geräten, die von dem Modul ignoriert werden sollen.<br>
            Komma als Trenner.<br>
            Beispiel:<br>
            MyMax_Wohnzimmer,MyMax_Schlafzimmer<br>
    </li>
    <li><a name="addDevices">addDevices</a><br>
	    <code>attr &lt;NAME&gt; addDevices &lt;Auflistung&gt;</code><br>
            Auflistung von Geräten, die zur Auswahlliste hinzugefügt werden sollen.<br>
	    Somit lassen sich dann auch z.B. "structure" hinzufügen.<br>
            Komma als Trenner.<br>
            Beispiel:<br>
            Struc_HeizungenUnten,Struc_HeizungenOben<br>
    </li>
    <li><a name="addDevicesFirst">addDevicesFirst</a><br>
	    <code>attr &lt;NAME&gt; addDevicesFirst (0|1)</code><br>
            Die manuell hinzugefügten Geräte als erstes in der Liste anzeigen.<br>
    </li>
    <li><a name="addGroups">addGroups</a><br>
	    <code>attr &lt;NAME&gt; addGroups (Text)</code><br>
            Gruppen erstellen.<br>
            Beispiele:<br>
            <code>Untergeschoss:Max_Device1,Max_Device2,Max_Device3 Obergeschoss:Max_Device4,Max_Device5</code><br>
	    <code>Gruppe&amp;nbsp;1:Max_Device1,Max_Device2,Max_Device3 Gruppe&amp;nbsp;2:Max_Device4,Max_Device5</code><br>
            Um ein leerzeichen in den Namen der Gruppe einzufügen, kann <code>&amp;nbsp;</code> eingegeben werden. Beispiel:<br>
            <code>Meine&amp;nbsp;Gruppe:Device1,Device2</code>
    </li>
    <li><a name="addGroupsFirst">addGroupsFirst</a><br>
	    <code>attr &lt;NAME&gt; addGroupsFirst (0|1)</code><br>
            Die Gruppen als erstes in der Liste anzeigen.<br>
    </li>
    <li><a name="DevicesAlias">DevicesAlias</a><br>
	    <code>attr &lt;NAME&gt; addDevicesAlias &lt;Auflistung&gt;</code><br>
            Ein Aliasnamen für die MAX-Geräte vergeben.<br>
            Komma als Trenner.<br>
            Beispiele:<br>
            Struc_HeizungenUnten:Heizkörper unten,Struc_HeizungenOben:Heizkörper oben<br>
	    Max-Device1:Heizkörper Bad,Max-Device2:Heizkörper Küche<br>
    </li>
    <li><a name="ShowMSg">ShowMSg</a><br>
	    <code>attr &lt;NAME&gt; ShowMSg (0|1)</code><br>
            Nach dem Senden von Einstellungen eine Erfolgsbenachrichtigung in einem Dialog anzeigen.<br>
    </li>
    <li><a name="SendButton">SendButton</a><br>
	    <code>attr &lt;NAME&gt; SendButton (Text)</code><br>
            Entweder der Name eines Symbols oder ein Text. Standard:<br>
            audio_play<br>
    </li>
    <li><a name="ResetButton">ResetButton</a><br>
	    <code>attr &lt;NAME&gt; ResetButton (Text)</code><br>
            Entweder der Name eines Symbols oder ein Text. Standard:<br>
            control_x<br>
    </li>
    <li><a name="createAT">createAT</a><br>
	    <code>attr &lt;NAME&gt; createAT (0|1)</code><br>
            Legt automatisch ein temporäres AT an, um das Gerät nach Ablauf der Zeit<br>
	    wieder in den Automatik Modus zu schalten.<br>
	    Dies ist normalerweise nicht notwendig.<br>
    </li>
    <li><a name="autoAT_room">autoAT_room</a><br>
	    <code>attr &lt;NAME&gt; autoAT_room MAX</code><br>
	    Der Raum in dem das temporäre AT erstellt werden soll. Standard:<br>
            MAX<br>
    </li>
    
  </ul>
  
  <h4>Readings</h4>
  <ul><a name="MAX_Temperature_Readings"></a>
	<li><a name="Selected_*">Selected_*</a><br>
	    Die derzeit ausgewählten Werte der Auswahlboxen.<br>
    </li>
  </ul>
    
</div>

=end html_DE

=cut
