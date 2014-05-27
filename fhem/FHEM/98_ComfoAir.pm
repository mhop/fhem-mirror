##############################################
# $Id: 98_ComfoAir.pm 
#
# fhem Modul für ComfoAir Lüftungsanlagen von Zehnder mit 
# serieller Schnittstelle (RS232) sowie dazu kompatible Anlagen wie 
# Storkair WHR 930, Storkair 950
# Paul Santos 370 DC, Paul Santos 570 DC
# Wernig G90-380, Wernig G90-550
#
# Dieses Modul basiert auf der Protokollanalyse von SeeSolutions:
# http://www.see-solutions.de/sonstiges/Protokollbeschreibung_ComfoAir.pdf
# sowie auf den bereits existierenden Modulen von Joachim und danhauck
# http://forum.fhem.de/index.php/topic,14697.0.html
#   
#     This file is part of fhem.
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
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#   Changelog:
#
#   2014-04-18  initial version
#   2014-05-17  added more protocol commands, changed logging settings
#	2014-05-25	added hide- attributes

package main;

use strict;
use warnings;
use Time::HiRes qw( time );

sub ComfoAir_Initialize($);
sub ComfoAir_Define($$);
sub ComfoAir_Undef($$);
sub ComfoAir_Set($@);
sub ComfoAir_Get($@);
sub ComfoAir_Read($);
sub ComfoAir_Ready($);
sub ComfoAir_ReadAnswer($$$);
sub ComfoAir_GetUpdate($$);
sub ComfoAir_Send($$$;$$);
sub ComfoAir_ParseFrames($);
sub ComfoAir_InterpretFrame($$);
sub ComfoAir_HandleSendQueue($);
sub ComfoAir_SendAck($);
sub ComfoAir_TimeoutSend($);


# %parseInfo:
# replyCode => msgHashRef
# msgHash => unpack, name, request, readings (array of readingHashes)
# readingHash => name, map, set, setmin, setmax, hint, expr

# jeder readingHash in parseMap wird in der Initialize-Funktion ergänzt um 
# - rmap aus map
# - setopt aus map 
# - msgHash - Rückverweis auf msgHash

my %parseInfo = (
    "000c"  =>  { unpack   => "CCS>S>",
                  name     => "Ventilation-Status",     # PC Befehl
                  request  => "000b", 
                  readings => [ { name => "Proz_Zuluft"},
                                { name => "Proz_Abluft"},
                                { name => "UPM_Zuluft",  expr => 'int(1875000/$val)'},
                                { name => "UPM_Abluft",  expr => 'int(1875000/$val)'}]},
    
    "0068"  =>  { unpack   => "CCCA*",
                  name     => "Bootloader-Version",     # PC Befehl
                  request  => "0067", 
                  readings => [ { name => "Bootloader_Version_Major"},
                                { name => "Bootloader_Version_Minor"},
                                { name => "Bootloader_Version_Beta"},
                                { name => "Bootloader_Version_Name"}]},

    "006a"  =>  { unpack   => "CCCA*",                  # PC Befehl
                  name     => "Firmware-Version",
                  request  => "0069",
                  readings => [ { name => "Firmware_Version_Major"},
                                { name => "Firmware_Version_Minor"},
                                { name => "Firmware_Version_Beta"},
                                { name => "Firmware_Version_Name"}]},
                    
    "0098"  =>  { unpack   => "CCCCCCxCCCCCCCCCC",
                  name     => "Sensordaten",
                  request  => "0097",
                  readings => [ { name => "Temp_Enthalpie",  expr => '$val / 2 - 20'},
                                { name => "Feucht_Enthalpie"},
                                { name => "Analog1_Proz"},
                                { name => "Analog2_Proz"},
                                { name => "Koeff_Enthalpie"},
                                { name => "Timer_Enthalpie", expr => '$val * 12'},
                                { name => "Analog1_Zu_Wunsch"},
                                { name => "Analog1_Ab_Wunsch"},
                                { name => "Analog2_Zu_Wunsch"},
                                { name => "Analog2_Ab_Wunsch"},
                                { name => "Analog3_Proz"},
                                { name => "Analog4_Proz"},
                                { name => "Analog3_Zu_Wunsch"},
                                { name => "Analog3_Ab_Wunsch"},
                                { name => "Analog4_Zu_Wunsch"},
                                { name => "Analog4_Ab_Wunsch"}]},

    "009c"  =>  { unpack   => "C",                      # PC Befehl
                  name     => "RS232-Modus",            # eigener Request existiert nicht sondern set mit 9b erzeugt Antwort 9c
                  readings => [ { name => "RS232-Modus",
                                  map => "0:Ende, 1:nur-PC, 2:nur-CC-Ease, 3:PC-Master, 4:PC-Log",
                                  set => "009b:%02x", }]},

    "00a2"  =>  { unpack   => "CCA10CC",                # PC Befehl
                  name     => "KonPlatine-Version",
                  request  => "00a1",
                  readings => [ { name => "KonPlatine_Version_Major"},
                                { name => "KonPlatine_Version_Minor"},
                                { name => "KonPlatine_Version_Name"},
                                { name => "CC-Ease_Version"},
                                { name => "CC-Luxe_Version"}]},

    "00ca"  =>  { unpack   => "CCCCCCCC",
                  name     => "Verzoegerungen",
                  request  => "00c9",
                  readings => [ { name => "Verz_Bad_Einschalt"},
                                { name => "Verz_Bad_Ausschalt"},
                                { name => "Verz_L1_Ausschalt"},
                                { name => "Verz_Stosslüftung"},
                                { name => "Verz_Filter_Wochen"},
                                { name => "Verz_RF_Hoch_Kurz"},
                                { name => "Verz_RF_Hoch_Lang"},
                                { name => "Verz_Küchenhaube_Ausschalt"}]},

    "00ce"  =>  { unpack   => "CCCCCCCCCCCC",
                  name     => "Ventilation-Levels",
                  request  => "00cd", defaultpoll => 1,
                  readings => [ { name => "Proz_Abluft_abwesend"},
                                { name => "Proz_Abluft_niedrig"},
                                { name => "Proz_Abluft_mittel"},
                                { name => "Proz_Zuluft_abwesend"},
                                { name => "Proz_Zuluft_niedrig"},
                                { name => "Proz_Zuluft_mittel"},
                                { name => "Proz_Abluft_aktuell"},
                                { name => "Proz_Zuluft_aktuell"},
                                { name => "Stufe", 
                                  showget => 1,
                                  map => "0:auto, 1:abwesend, 2:niedrig, 3:mittel, 4:hoch",
                                  set => "0099:%02x"},
                                { name => "Zuluft_aktiv"},
                                { name => "Proz_Abluft_hoch"},
                                { name => "Proz_Zuluft_hoch"}]},

    "00d2"  =>  { unpack   => "CCCCCxC",
                  name     => "Temperaturen",
                  request  => "00d1", defaultpoll => 1,
                  readings => [ { name => "Temp_Komfort",  expr => '$val / 2 - 20',
                                  set  => "00D3:%02x", setexpr => '($val + 20) *2',
                                  setmin => 12, setmax => 28, hint => "slider,12,1,28"},
                                { name => "Temp_Aussen" ,  
                                  showget => 1, expr => '$val / 2 - 20'},
                                { name => "Temp_Zuluft" ,  expr => '$val / 2 - 20'},
                                { name => "Temp_Abluft" ,  expr => '$val / 2 - 20'},
                                { name => "Temp_Fortluft", expr => '$val / 2 - 20'},
                                { name => "Temp_EWT",      expr => '$val / 2 - 20'}]},
                                
    "00de"  =>  { unpack   => "H6H6H6S>S>S>S>H6",
                  name     => "Betriebsstunden",
                  request  => "00dd",
                  readings => [ { name => "Betriebsstunden_Abwesend", expr => 'hex($val)'},
                                { name => "Betriebsstunden_Niedrig",  expr => 'hex($val)'},
                                { name => "Betriebsstunden_Mittel",   expr => 'hex($val)'},
                                { name => "Betriebsstunden_Frostschutz"},
                                { name => "Betriebsstunden_Vorheizung"},
                                { name => "Betriebsstunden_Bypass"},
                                { name => "Betriebsstunden_Filter"},
                                { name => "Betriebsstunden_Hoch",    expr => 'hex($val)'}]},
                                
    "00e0"  =>  { unpack   => "xxCCCxC",
                  name     => "Status-Bypass",
                  request  => "00df", defaultpoll => 1,
                  readings => [ { name => "Bypass_Faktor"},
                                { name => "Bypass_Stufe"},
                                { name => "Bypass_Korrektur"},
                                { name => "Bypass_Sommermodus", map => "0:nein, 1:ja"}]},

    "00e2"  =>  { unpack   => "CCCS>C",
                  name     => "Status-Vorheizung",
                  request  => "00e1",
                  readings => [ { name => "Status_Klappe",      map => "0:geschlossen, 1:offen, 2:unbekannt"},
                                { name => "Status_Frostschutz", map => "0:inaktiv, 1:aktiv"},
                                { name => "Status_Vorheizung",  map => "0:inaktiv, 1:aktiv"},
                                { name => "Frostminuten"}, # S> is 2 bytes as high low 
                                { name => "Status_Frostsicherheit", map => "1:extra, 4:sicher"}]},
                                
);

my @setList;        # helper to return valid set options if set is called with "?"
my @getList;        # helper to return valid get options if get is called with "?"
my %setHash;        # helper to reference the readings array in the above parseInfo for each set option
my %getHash;        # helper to reference the msgHash in parseInfo for each name / get option
my %requestHash;    # helper to reference each msgHash for each request Set
my %cmdHash;        # helper to map from send cmd code to msgHash of Reply
    
my %ComfoAir_AddSets = (
  "SendRawData"     => ""
);
    

#####################################
sub
ComfoAir_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{ReadFn}  = "ComfoAir_Read";
    $hash->{ReadyFn} = "ComfoAir_Ready";
    $hash->{DefFn}   = "ComfoAir_Define";
    $hash->{UndefFn} = "ComfoAir_Undef";
    $hash->{SetFn}   = "ComfoAir_Set";
    $hash->{GetFn}   = "ComfoAir_Get";
  
    @setList  = ();
    @getList  = ();
    my @pollList = (); # ergänzt später $hash->{AttrList}
    
    # gehe durch alle Nachrichtentypen in parseInfo und erzeuge Hilfsdaten für set, get und die Attribute:
    # berechne reverse map aus der map zum Wandeln der gesetzten Werte
    # und berechnet setList für den "choose one of" Rückgabewert in det Set-Funktion
    # setHash enthält dann für jede gültige Set-Option eine Referenz auf den readingHash
    # requestHash: für jeden Request den Verweis auf msgHash innerhalb parseInfo
    
    while (my ($replyCode, $msgHashRef) = each (%parseInfo)) {
        my $msgName = $msgHashRef->{name};
        # baue pollList und requestHash auf, setze Requests in @setList.
        if (defined ($msgHashRef->{request})) {                     # Nachricht kann abgefragt werden
            my $requestName = "request-" . $msgName;                # für eine Set-Option
            my $attrName    = "poll-"    . $msgName;                # für das Attribut zur Steuerung welche Blöcke abgefragt werden
			my $attr2Name   = "hide-"    . $msgName;                # für das Attribut zum Verstecken von Blöcken
            $requestHash{$requestName} = $msgHashRef;               # erzeuge requestHash für Verweis von requestName auf msgHash
            $requestHash{$requestName}->{replyCode} = $replyCode;   # ergänze Replycode im msgHash
            $cmdHash{$msgHashRef->{request}} = $msgHashRef;         # erzeuge %cmdHash für Verweis von RequestCode auf msgHash (für Debug Log)
            push @setList, $requestName;
            push @pollList, "$attrName:0,1";
			push @pollList, "$attr2Name:0,1";
        }
        # gehe durch alle Readings im Nachrichtentyp und erzeuge getHash, setHash und setList, rmap, setopt
        foreach my $readingHashRef (@{$msgHashRef->{readings}}) {
            my $reading = $readingHashRef->{name};                  # Name des Readings

            # getHash erzeugen
            $getHash{$reading} = $readingHashRef;                   # erzeuge getHash mit Verweis von Reading-Name auf msgHash
            push @getList, $reading 
                if ($readingHashRef->{showget});                    # sichtbares get (alle Readings können per Get aktiv abgefragt werden)
            
            # Rückwärtsverweis auf msgHash erzeugen
            $readingHashRef->{msgHash} = $msgHashRef;               # ergänze Rückwärtsverweis
            
            # gibt es für das Reading ein SET?
            if (defined($readingHashRef->{set})) {
                # ist eine Map definiert, aus der eine Reverse-Map und auch Hints abgeleitet werden können?
                if (defined($readingHashRef->{map})){
                    my $rm = $readingHashRef->{map};
                    $rm =~ s/([^ ,\$]+):([^ ,\$]+),? ?/$2 $1 /g;    # reverse map string erzeugen
                    my %rmap = split (' ', $rm);                    # reverse hash aus dem reverse string                   
                    $readingHashRef->{rmap} = \%rmap;               # reverse map im readingHash sichern
                    
                    my $hl = $readingHashRef->{map};                # create hint list from map
                    $hl =~ s/([^ ,\$]+):([^ ,\$]+,?) ?/$2/g;
                    $readingHashRef->{setopt} = $reading . ":$hl";
                } else {
                    $readingHashRef->{setopt} = $reading;           # keine besonderen Optionen, nur den Namen für setopt verwenden.
                }
                if (defined($readingHashRef->{hint})){              # hints explizit definiert? (überschreibt evt. schon abgeleitete hints)
                    $readingHashRef->{setopt} = $reading . 
                        ":" . $readingHashRef->{hint};
                }
                $setHash{$reading} = $readingHashRef;               # erzeuge Hash mit Verweis auf readingHashRef für jedes Reading mit Set
                push @setList, $readingHashRef->{setopt};           # speichere Liste mit allen Sets inkl. der Hints nach ":" für Rückgabe bei Set ?
            }
        }
    }
    $hash->{AttrList}= "do_not_notify:1,0 " . 
        "queueDelay " .
        "timeout " .
        #"minSendDelay " .
        join (" ", @pollList) . " " .                               # Def der zyklisch abzufragenden Nachrichten
        $readingFnAttributes;
}


#####################################
sub
ComfoAir_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my ($name, $ComfoAir, $dev, $interval) = @a;
    return "wrong syntax: define <name> ComfoAir [devicename|none] [interval]"
        if(@a < 3);
        
    $hash->{BUSY}   = 0;    
    $hash->{EXPECT} = "";

    if (!defined($interval)) {
        $hash->{INTERVAL} = 0; 
        Log 1, "$name: interval is 0 or not defined - not sending requests - just listening!";
    } else {
        $hash->{INTERVAL} = $interval;
    }
    DevIo_CloseDev($hash);

    if($dev eq "none") {
        Log 1, "$name: device is none, commands will be echoed only";
        return undef;
    }
    $hash->{DeviceName} = $dev;
    my $ret = DevIo_OpenDev($hash, 0, 0);

    InternalTimer(gettimeofday()+1, "ComfoAir_GetUpdate", $hash, 0)       # erste Abfrage von Werten nach 1 Sekunde (zumindest in Queue stellen)
        if ($hash->{INTERVAL});
    return $ret;
}


#####################################
sub
ComfoAir_Undef($$)
{
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    DevIo_CloseDev($hash); 
    RemoveInternalTimer ("timeout:".$name);
    RemoveInternalTimer ("queue:".$name); 
    RemoveInternalTimer ($hash);
    return undef;
}


#####################################
sub
ComfoAir_Get($@)
{
    my ($hash, @a) = @_;
    return "\"get ComfoAir\" needs at least one argument" if(@a < 2);

    my $name = $hash->{NAME};
    my $getName = $a[1];
    
    if (defined($getHash{$getName})) {
        # get Option für Reading aus parseInfo -> generische Verarbeitung
        my $msgHash = $getHash{$getName}{msgHash};  # Hash für die Nachricht aus parseInfo
        Log3 $name, 3, "$name: Request found in getHash created from parseInfo data";
        if ($msgHash->{request}) {
            ComfoAir_Send($hash, $msgHash->{request}, "", $msgHash->{replyCode}, 1);
            my $result = ComfoAir_ReadAnswer($hash, $getName, $msgHash->{replyCode});
            return $result;
        } else {
            return "Protocol doesn't provide a command to get $getName";
        }
    } else {
        # undefiniertes Get
        Log3 $name, 5, "$name: Get $getName not found, return list @getList ";
        return "Unknown argument $a[1], choose one of @getList ";
    }

    return undef;
}



#####################################
sub
ComfoAir_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set ComfoAir\" needs at least an argument" if(@a < 2);

    my $name = $hash->{NAME};
    my ($cmd,$fmt,$data);

    my $setName = $a[1];
    my $setVal  = $a[2];
    my $rawVal  = "";

    if (defined($requestHash{$setName})) {
        # set Option ist Daten-Abfrage-Request aus parseInfo
        Log3 $name, 5, "$name: Request found in requestHash created from parseInfo data";
        ComfoAir_Send($hash, $requestHash{$setName}{request}, "", $requestHash{$setName}{replyCode});
        return "";
    }
    if (defined($setHash{$setName})) {
        # set Option für einen einzelnen Wert, in parseInfo definiert -> generische Verarbeitung
        if (!defined($setVal)) {
            Log3 $name, 3, "$name: No Value given to set $setName";
            return "No Value given to set $setName";
        }
        Log3 $name, 5, "$name: Set found option $setName in setHash created from parseInfo data";
        ($cmd, $fmt) = split(":", $setHash{$setName}{set});
        
        # 1. Schritt, falls definiert per Umkehrung der Map umwandeln (z.B. Text in numerische Codes)
        if (defined($setHash{$setName}{rmap})) {
          if (defined($setHash{$setName}{rmap}{$setVal})) {
            # reverse map für das Reading und den Wert definiert
            $rawVal = $setHash{$setName}{rmap}{$setVal};
            Log3 $name, 5, "$name: found $setVal in setHash rmap and converted to $rawVal";
          } else {
            Log3 $name, 3, "$name: Set Value $setVal did not match defined map";
            return "Set Value $setVal did not match defined map";
          }
        } else {
          # wenn keine map, dann wenigstens sicherstellen, dass numerisch.
          if ($setVal !~ /^-?\d+\.?\d*$/) {
            Log3 $name, 3, "$name: Set Value $setVal is not numeric";
            return "Set Value $setVal is not numeric";
          }
          $rawVal = $setVal;
        }
        # 2. Schritt: falls definiert Min- und Max-Werte prüfen
        if (defined($setHash{$setName}{setmin})) {
            Log3 $name, 5, "$name: checking Value $rawVal against Min $setHash{$setName}{setmin}";
            return "Set Value $rawVal is smaller than Min ($setHash{$setName}{setmin})"
                if ($rawVal < $setHash{$setName}{setmin});
        }
        if (defined($setHash{$setName}{setmax})) {
            Log3 $name, 5, "$name: checking Value $rawVal against Max $setHash{$setName}{setmax}";
            return "Set Value $rawVal is bigger than Max ($setHash{$setName}{setmax})"
                if ($rawVal > $setHash{$setName}{setmax});
        }
        # 3. Schritt: Konvertiere mit setexpr falls definiert
        if (defined($setHash{$setName}{setexpr})) {
            my $val = $rawVal;
            $rawVal = eval($setHash{$setName}{setexpr});
            Log3 $name, 5, "$name: converted Value $val to $rawVal using expr $setHash{$setName}{setexpr}";
        }
        # 4. Schritt: mit sprintf umwandeln und senden.
        $data = sprintf($fmt, $rawVal); # in parseInfo angegebenes Format bei set=> - meist Konvert in Hex
        ComfoAir_Send($hash, $cmd, $data, 0);
        # Nach dem Set gleich den passenden Datenblock nochmals anfordern, damit die Readings de neuen Wert haben
        if ($setHash{$setName}{msgHash}{request}) {
            ComfoAir_Send($hash, $setHash{$setName}{msgHash}{request}, "", 
                        $setHash{$setName}{msgHash}{replyCode},1);
            # falls ein minDelay bei Send implementiert wäre, müsste ReadAnswer optiniert werden, sonst wird der 2. send ggf nicht vor einem Timeout gesendet ...
            my $result = ComfoAir_ReadAnswer($hash, $setName, $setHash{$setName}{msgHash}{replyCode});
            return "$setName -> $result";
        }
        return undef;
        
    } elsif (defined($ComfoAir_AddSets{$setName})) {
        # Additional set option not defined in parseInfo but ComfoAir_AddSets
        if($setName eq "SendRawData") {
            return "please specify data as cmd or cmd -> data in hex" 
                if (!defined($setVal));
            ($cmd, $data) = split("->",$setVal); # eingegebener Wert ist HexCmd -> HexData
            $data="" if(!defined($data));
        }
        ComfoAir_Send($hash, $cmd, $data, 0);
    } else {
        # undefiniertes Set
        Log3 $name, 5, "$name: Set $setName not found, return list @setList " . join (" ", keys %ComfoAir_AddSets);
        return "Unknown argument $a[1], choose one of @setList " . join (" ", keys %ComfoAir_AddSets);
    }
    return undef;
}


#####################################
# Called from the read functions
sub
ComfoAir_ParseFrames($)
{
    my $hash  = shift;
    my $name  = $hash->{NAME};
    my $frame = $hash->{helper}{buffer};
    
    $hash->{RAWBUFFER} = unpack ('H*', $frame);
    Log3 $name, 5, "$name: raw buffer: $hash->{RAWBUFFER}";

    # check for full frame in buffer 
    if ($frame =~ /\x07\xf0(.{3}(?:[^\x07]|(?:\x07\x07))*)\x07\x0f(.*)/s) {
        # got full frame (and maybe Ack before but that's ok)
        my $framedata = $1;
        $hash->{helper}{buffer} = $2;           # only keep the rest after the frame
        $framedata =~ s/\x07\x07/\x07/g;        # remove double x07
        $hash->{LASTFRAMEDATA} = unpack ('H*', $framedata);
        Log3 $name, 5, "$name: ParseFrames got frame: $hash->{RAWBUFFER}" .
            " data $hash->{LASTFRAMEDATA} Rest " . unpack ('H*', $hash->{helper}{buffer});
        return $framedata;
    } elsif ($frame =~ /\x07\xf3(.*)/s) {
        my $level = ($hash->{INTERVAL} ? 4 : 5);
        Log3 $name, $level, "$name: read got Ack";
        $hash->{helper}{buffer} = $1;           # only keep the rest after the frame
        if (!$hash->{EXPECT}) {
            $hash->{BUSY} = 0;
            # es wird keine weitere Antwort erwartet -> gleich weiter Send Queue abarbeiten und nicht auf alten Timer warten
            RemoveInternalTimer ("timeout:".$name);
            RemoveInternalTimer ("queue:".$name); 
            ComfoAir_HandleSendQueue ("direct:".$name); # don't wait for next regular handle queue slot
        }
        return undef;                           
    } else {
        return undef;                           # continue reading, probably frame not fully received yet
    }
}


#####################################
# Called from the read functions
sub 
ComfoAir_InterpretFrame($$)
{
    my $hash      = shift;
    my $framedata = shift;
    my $name      = $hash->{NAME};
    
    my ($cmd, $hexcmd, $hexdata, $len, $data, $chk);
    if (defined($framedata)) {
        if ($framedata =~ /(.{2})(.)(.*)(.)/s) {
            $cmd     = $1;
            $len     = $2;
            $data    = $3;
            $chk     = unpack ('C', $4);
            $hexcmd  = unpack ('H*', $cmd);
            $hexdata = unpack ('H*', $data);
            Log3 $name, 5, "$name: read split frame into cmd $hexcmd, len " . unpack ('C', $len) . 
                ", data $hexdata chk $chk";
        } else {
            Log3 $name, 3, "$name: read: error splitting frame into fields: $hash->{LASTFRAMEDATA}";
            return;
        }
    }
  
    # Länge prüfen
    if (unpack ('C', $len) != length($data)) {
        Log3 $name, 4, "$name: read: wrong length: " . length($data) . 
            " (calculated) != " . unpack ('C', $len) . " (header)" .
            " cmd=$hexcmd, data=$hexdata, chk=$chk";
        #return;
    }
    
    # Checksum prüfen
    my $csum = unpack ('%8C*', $cmd . $len . $data . "\xad"); # berechne csum
    if($csum != $chk) {
        Log3 $name, 4, "$name: read: wrong checksum: $csum (calculated) != $chk (frame) cmd $hexcmd, data $hexdata";
        return;
    };
    
    # Parse Data
    if ($parseInfo{$hexcmd}) {
		if (!AttrVal($name, "hide-$parseInfo{$hexcmd}{name}", 0)) {
			# Definition für diesen Nachrichten-Typ gefunden
			my %p = %{$parseInfo{$hexcmd}};
			Log3 $name, 4, "$name: read got " . $p{"name"} . " (reply code $hexcmd) with data $hexdata";
			readingsBeginUpdate($hash);
			# Definition der einzelnen Felder abarbeiten
			my @fields = unpack($p{"unpack"}, $data);
			for (my $i = 0; $i < scalar(@fields); $i++) {
				# einzelne Felder verarbeiten
				my $reading = $p{"readings"}[$i]{"name"};
				my $val     = $fields[$i];
				# Exp zur Nachbearbeitung der Werte?
				if ($p{"readings"}[$i]{"expr"}) {
					Log3 $name, 5, "$name: read evaluate $val with expr " . $p{"readings"}[$i]{"expr"};
					$val = eval($p{"readings"}[$i]{"expr"});
				}
				# Map zur Nachbereitung der Werte?
				if ($p{"readings"}[$i]{"map"}) {
					my %map = split (/[,: ]+/, $p{"readings"}[$i]{"map"});
					Log3 $name, 5, "$name: read maps value $val with " . $p{"readings"}[$i]{"map"};
					$val = $map{$val} if ($map{$val});
				}
				Log3 $name, 5, "$name: read assign $reading with $val";
				readingsBulkUpdate($hash, $reading, $val);
			}
			readingsEndUpdate($hash, 1);
		}
    } else {
        my $level = ($hash->{INTERVAL} ? 4 : 5);
        Log3 $name, $level, "$name: read: unknown cmd $hexcmd, len " . unpack ('C', $len) . 
            ", data $hexdata, chk $chk";
    }
    if ($hash->{EXPECT}) {
        # der letzte Request erwartet eine Antwort -> ist sie das?
        if ($hexcmd eq $hash->{EXPECT}) {
            $hash->{BUSY}   = 0;    
            $hash->{EXPECT} = "";
            Log3 $name, 5, "$name: read got expected reply ($hexcmd), setting BUSY=0";
        } else {
            Log3 $name, 3, "$name: read did not get expected reply (" . $hash->{EXPECT} . ") but $hexcmd";
        }
    }
    ComfoAir_SendAck($hash) if ($hash->{INTERVAL});

    if (!$hash->{EXPECT}) {
        # es wird keine Antwort mehr erwartet -> gleich weiter Send Queue abarbeiten und nicht auf Timer warten
        $hash->{BUSY}   = 0;    # zur Sicherheit falls ein Ack versäumt wurde
        RemoveInternalTimer ("timeout:".$name);
        RemoveInternalTimer ("queue:".$name);       
        ComfoAir_HandleSendQueue ("direct:".$name); # don't wait for next regular handle queue slot
    }
}


#####################################
# Called from the global loop, when the select for hash->{FD} reports data
sub
ComfoAir_Read($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf = DevIo_SimpleRead($hash);
    return if(!defined($buf));
    
    $hash->{helper}{buffer} .= $buf;  
    
    for (my $i = 0;$i < 2;$i++) {
        my $framedata = ComfoAir_ParseFrames($hash);
        return if (!$framedata);
        ComfoAir_InterpretFrame($hash, $framedata);
    }
}


#####################################
# Called from get / set to get a direct answer
sub
ComfoAir_ReadAnswer($$$)
{
    my ($hash, $arg, $expectReply) = @_;
    my $name  = $hash->{NAME};

    return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

    my ($buf, $framedata, $cmd);
    my $rin = '';
    my $to  = AttrVal($name, "timeout", 2);   # default is 2 seconds timeout
  
    Log3 $name, 5, "$name: ReadAnswer called for get $arg";
    for(;;) {

        if($^O =~ m/Win/ && $hash->{USBDev}) {
            $hash->{USBDev}->read_const_time($to*1000);   # set timeout (ms)
            $buf = $hash->{USBDev}->read(999);
			if(length($buf) == 0) {
				Log3 $name, 3, "$name: Timeout in ReadAnswer for get $arg";
				return ("Timeout reading answer for $arg", undef);
			}
        } else {
            if(!$hash->{FD}) {
                Log3 $name, 3, "$name: Device lost in ReadAnswer for get $arg";
                return ("Device lost when reading answer for get $arg", undef);
            }

            vec($rin, $hash->{FD}, 1) = 1;    # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $to);
            if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                DevIo_Disconnected($hash);
                Log3 $name, 3, "$name: ReadAnswer $arg: error $err";
                return("ComfoAir_ReadAnswer $arg: $err", undef);
            }
            if($nfound == 0) {
                Log3 $name, 3, "$name: Timeout2 in ReadAnswer for $arg";
                return ("Timeout reading answer for $arg", undef);
            }
        
            $buf = DevIo_SimpleRead($hash);
            if(!defined($buf)) {
                Log3 $name, 3, "$name: ReadAnswer for $arg got no data";
                return ("No data", undef);
            }
        }

        if($buf) {
            $hash->{helper}{buffer} .= $buf;
            Log3 $name, 5, "$name: ReadAnswer got: " . unpack ("H*", $hash->{helper}{buffer});
        }

        $framedata = ComfoAir_ParseFrames($hash);
        if ($framedata) {
            ComfoAir_InterpretFrame($hash, $framedata);
            $cmd = unpack ('H4x*', $framedata);
            if ($cmd eq $expectReply) {
                # das war's worauf wir gewartet haben
                Log3 $name, 5, "$name: ReadAnswer done with success";
                return ReadingsVal($name, $arg, "");
            }
        }
        ComfoAir_HandleSendQueue("direct:".$name);
    }
}


#####################################
sub
ComfoAir_Ready($)
{
    my ($hash) = @_;
    return DevIo_OpenDev($hash, 1, undef)
        if($hash->{STATE} eq "disconnected");

    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  
    return ($InBytes>0);
}


#####################################
sub
ComfoAir_GetUpdate($$) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "ComfoAir_GetUpdate", $hash, 1)
        if ($hash->{INTERVAL});
    
    foreach my $msgHashRef (values %parseInfo) {
        if (defined($msgHashRef->{request})) {
            my $default = ($msgHashRef->{defaultpoll} ? 1 : 0); # verwende als Defaultwert für Attribut, falls gesetzt in %parseInfo
            if (AttrVal($name, "poll-$msgHashRef->{name}", $default)) {
                Log3 $name, 5, "$name: GetUpdate requests $msgHashRef->{name}, default is $default";
                ComfoAir_Send($hash, $msgHashRef->{request}, "", $msgHashRef->{replyCode});
            }
        }
    }
}


#####################################
sub
ComfoAir_Send($$$;$$){
    my ($hash, $hexcmd, $hexdata, $expectReply, $first) = @_;
    my $name = $hash->{NAME};
    
    my $cmd   = pack ('H*', $hexcmd);
    my $data  = pack ('H*', $hexdata);
    my $len   = pack ('C', length ($data));
    my $csum  = pack ('C', unpack ('%8C*', $cmd . $len . $data. "\xad"));
    
    my $framedata = $data.$csum;
    $framedata =~ s/\x07/\x07\x07/g;        # double 07 in contents of frame including Checksum!
    my $frame = "\x07\xF0".$cmd.$len.$framedata."\x07\x0F";
    my $hexframe = unpack ('H*', $frame);

    $expectReply = "" if (!$expectReply);
    Log3 $name, 4, "$name: send adds frame to queue with cmd $hexcmd" .
        ($cmdHash{$hexcmd} ? " (get " . $cmdHash{$hexcmd}{name} . ")" : "") . 
        " / frame " . $hexframe;

    my %entry;
    $entry{DATA}   = $frame;
    $entry{EXPECT} = $expectReply;
  
    if(!$hash->{QUEUE} || 0 == scalar(@{$hash->{QUEUE}})) {
        $hash->{QUEUE} = [ \%entry ];
    } else {
        if ($first) {
            unshift (@{$hash->{QUEUE}}, \%entry);
        } else {
            push(@{$hash->{QUEUE}}, \%entry);
        }
    }
    ComfoAir_HandleSendQueue("direct:".$name);
}


#######################################
sub
ComfoAir_TimeoutSend($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
  
    Log3 $name, 3, "$name: timeout waiting for reply" .
        ($hash->{EXPECT} ? " expecting " . $hash->{EXPECT} : "") .
        " Request was " . $hash->{LASTREQUEST};
    $hash->{BUSY}   = 0;
    $hash->{EXPECT} = "";  
};


#######################################
sub
ComfoAir_HandleSendQueue($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    my $arr  = $hash->{QUEUE};
    my $now  = gettimeofday();
    my $queueDelay = AttrVal($name, "queueDelay", 1);
    Log3 $name, 5, "$name: handle send queue";
    if(defined($arr) && @{$arr} > 0) {
        if (!$init_done) {      # fhem not initialized, wait with IO
            RemoveInternalTimer ("queue:".$name);
            InternalTimer($now+$queueDelay, "ComfoAir_HandleSendQueue", "queue:".$name, 0);
            Log3 $name, 3, "$name: init not done, delay writing from queue";
            return;
        }
        if ($hash->{BUSY}) {  # still waiting for reply to last request
            RemoveInternalTimer ("queue:".$name);
            InternalTimer($now+$queueDelay, "ComfoAir_HandleSendQueue", "queue:".$name, 0);
            Log3 $name, 5, "$name: send busy, delay writing from queue";
            return;
        }
    
        my $entry   = $arr->[0];
        my $bstring = $entry->{DATA};
        my $hexcmd  = unpack ('xxH4x*', $bstring);
    
        if($bstring ne "") {    # if something to send - do so 
            $hash->{LASTREQUEST} = unpack ('H*', $bstring);
            $hash->{BUSY}        = 1;     # at least wait for ACK
            Log3 $name, 4, "$name: handle queue sends" .
                ($cmdHash{$hexcmd} ? " get " . $cmdHash{$hexcmd}{name} : "") . 
                " code: $hexcmd" .
                " frame: " . $hash->{LASTREQUEST} . 
                ($entry->{EXPECT} ? " and wait for " . $entry->{EXPECT} : "");
        
            DevIo_SimpleWrite($hash, $bstring, 0);
      
            if ($entry->{EXPECT}) {
                # we expect a reply
                $hash->{EXPECT} = $entry->{EXPECT};
            }
            my $to = AttrVal($name, "timeout", 2);    # default is 2 seconds timeout
            RemoveInternalTimer ("timeout:".$name);
            InternalTimer($now+$to, "ComfoAir_TimeoutSend", "timeout:".$name, 0);
        }
        shift(@{$arr});
        if(@{$arr} == 0) {      # last item was sent -> delete queue
            delete($hash->{QUEUE});
        } else {                # more items in queue -> schedule next handle invocation
            RemoveInternalTimer ("queue:".$name);
            InternalTimer($now+$queueDelay, "ComfoAir_HandleSendQueue", "queue:".$name, 0);
        }
    }
}


#######################################
sub
ComfoAir_SendAck($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
    Log3 $name, 4, "$name: sending Ack";
    DevIo_SimpleWrite($hash, "\x07\xf3", 0);
}



1;

=pod
=begin html

<a name="ComfoAir"></a>
<h3>ComfoAir</h3>
<ul>
    ComfoAir provides a way to communicate with ComfoAir ventilation systems from Zehnder, especially the ComfoAir 350 (CA350).
    It seems that many other ventilation systems use the same communication device and protocol, 
    e.g. WHR930 from StorkAir, G90-380 from Wernig and Santos 370 DC from Paul.
    They are connected via serial line to the fhem computer. 
    This module is based on the protocol description at http://www.see-solutions.de/sonstiges/Protokollbeschreibung_ComfoAir.pdf
    and copies some ideas from earlier modules for the same devices that were posted in the fhem forum from danhauck(Santos) and Joachim (WHR962).
    <br>
    The module can be used in two ways depending on how fhem and / or a vendor supplied remote control device 
    like CC Ease or CC Luxe are connected to the system. If a remote control device is connected it is strongly advised that 
    fhem does not send data to the ventilation system as well and only listens to the communication betweem the vendor equipment. 
    The RS232 interface used is not made to support more than two parties communicating and connecting fhem in parallel to a CC Ease or similar device can lead to 
    collisions when sending data which can corrupt the ventilation system.
    If connected in parallel fhem should only passively listen and &lt;Interval&gt; is to be set to 0. <br>
    If no remote control device is connected to the ventilation systems then fhem has to take control and actively request data 
    in the interval to be defined. Otherwiese fhem will not see any data. In this case fhem can also send commands to modify settings.
    <br><br>
    
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
          This module requires the Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ComfoAirDefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; ComfoAir &lt;device&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the ventialation system through the given Device and either passively listens to data that is communicated 
        between the ventialation system and its remote control device (e.g. CC Luxe) or it actively requests data from the 
        ventilation system every &lt;Interval&gt; seconds <br>
        <br>
        Example:<br>
        <br>
        <ul><code>define ZL ComfoAir /dev/ttyUSB1@9600 60</code></ul>
    </ul>
    <br>

    <a name="ComfoAirConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        apart from the serial connection and the interval which both are specified in the define command there are several attributes that 
        can optionally be used to modify the behavior of the module. <br><br>
        The module internally gives names to all the protocol messages that are defined in the module and these names can be used 
        in attributes to define which requests are periodically sent to the ventilation device. The same nams can also be used with 
        set commands to manually send a request. Since all messages and readings are generically defined in a data structure in the module, it should be 
        quite easy to add more protocol details if needed without programming.
        
        <br>
        The names currently defined are:
        
        <pre>
        Bootloader-Version
        Firmware-Version
        RS232-Modus
		Sensordaten
        KonPlatine-Version
        Verzoegerungen
        Ventilation-Levels
        Temperaturen
        Betriebsstunden
        Status-Bypass
        Status-Vorheizung
        </pre>
        
        The attributes that control which messages are sent / which data is requested every &lt;Interval&gt; seconds are:
        
        <pre>
        poll-Bootloader-Version
        poll-Firmware-Version
        poll-RS232-Modus
		poll-Sensordaten
        poll-KonPlatine-Version
        poll-Verzoegerungen
        poll-Ventilation-Levels
        poll-Temperaturen
        poll-Betriebsstunden
        poll-Status-Bypass
        poll-Status-Vorheizung
        </pre>
        
        if the attribute is set to 1, the corresponding data is requested every &lt;Interval&gt; seconds. If it is set to 0, then the data is not requested.
        by default Ventilation-Levels, Temperaturen and Status-Bypass are requested if no attributes are set.
        <br><br>
        Example:<br><br>
        <pre>
        define ZL ComfoAir /dev/ttyUSB1@9600 60
        attr ZL poll-Status-Bypass 0
        define FileLog_Lueftung FileLog ./log/Lueftung-%Y.log ZL
        </pre>
    </ul>

    <a name="ComfoAirSet"></a>
    <b>Set-Commands</b><br>
    <ul>
        like with the attributes mentioned above, set commands can be used to send a request for data manually. The following set options are available for this:
        <pre>
        request-Status-Bypass 
        request-Bootloader-Version 
		request-Sensordaten
        request-Temperaturen 
        request-Firmware-Version 
        request-KonPlatine-Version 
        request-Ventilation-Levels 
        request-Verzoegerungen 
        request-Betriebsstunden 
        request-Status-Vorheizung 
        </pre>
        additionally important fields can be set:
        <pre>
        Temp_Komfort (target temperature for comfort)
        Stufe (ventilation level)
        </pre>
    </ul>
    <a name="ComfoAirGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings that are derived from the responses to protocol requests are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. To avoid huge option lists in FHEMWEB, only the most important Get options
        are visible in FHEMWEB. However this can easily be changed since all the readings and protocol messages are internally defined in the modue in a data structure 
        and to make a Reading visible as Get option only a little option (e.g. <code>showget => 1</code> has to be added to this data structure
    </ul>
    <a name="ComfoAirattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>poll-Bootloader-Version</b></li> 
        <li><b>poll-Firmware-Version</b></li> 
        <li><b>poll-RS232-Modus</b></li> 
		<li><b>poll-Sensordaten</b></li> 
        <li><b>poll-KonPlatine-Version</b></li> 
        <li><b>poll-Verzoegerungen</b></li> 
        <li><b>poll-Ventilation-Levels</b></li> 
        <li><b>poll-Temperaturen</b></li> 
        <li><b>poll-Betriebsstunden</b></li> 
        <li><b>poll-Status-Bypass</b></li> 
        <li><b>poll-Status-Vorheizung</b></li> 
            include a request for the data belonging to the named group when sending requests every interval seconds <br>
        <li><b>hide-Bootloader-Version</b></li> 
        <li><b>hide-Firmware-Version</b></li> 
        <li><b>hide-RS232-Modus</b></li> 
		<li><b>hide-Sensordaten</b></li> 
        <li><b>hide-KonPlatine-Version</b></li> 
        <li><b>hide-Verzoegerungen</b></li> 
        <li><b>hide-Ventilation-Levels</b></li> 
        <li><b>hide-Temperaturen</b></li> 
        <li><b>hide-Betriebsstunden</b></li> 
        <li><b>hide-Status-Bypass</b></li> 
        <li><b>hide-Status-Vorheizung</b></li> 
			prevent readings of the named group from being created even if used passively without polling and an external remote control requests this data.
			please note that this attribute doesn't delete already existing readings.<br>
        <li><b>queueDelay</b></li> 
            modify the delay used when sending requests to the device from the internal queue, defaults to 1 second <br>
        <li><b>timeout</b></li> 
            set the timeout for reads, defaults to 2 seconds <br>
    </ul>
    <br>
</ul>

=end html
=cut

