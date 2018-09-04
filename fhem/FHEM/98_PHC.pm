##############################################
# $Id$
# fhem Modul für PHC
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
#   2017-02-11  started initial PoC version
#   2017-08-08  optimized logging, silentReconnect, singleLastCommand
#   2017-08-18  ping command, reset / config, sendRaw
#
#
# Todo / Ideas:
# =============
#
#   command 01 (Ping), configure commands ...
#
#   input validation for attrs (allowed EMD address)
#   EMD Resend falls kein ACK
#   Bei kaputten Frames nächstes Frame im Buffer suchen
#
#   attr zum Steuern der Readings-Erzeugung
#       setze alle Modul-Ausgänge in Readings mit Moduladr als Namen
#       nur angegebenen Liste von Modulen in Readings setzen
#       Namen für Readings überschreben mit eigenem attr (stärker als desc falls gesetzt)
#       -Desc Readings erzeugen
#
#   Parsen der ACK / Feedback Channelbits als Option? (Bei Umschalten wäre es aber nötig)
#   Per Default auf eindeutige Befehle Readings setzen - Wert aus Command Hash (bei Ein / Aus, nicht bei Umschalten)
#   Dim Feedback codes (ein / aus)
#
#   Timer im STM von Fhem aus ändern?
#
# What does not work:
# ===================
#   AMD direkt ansprechen
#       Problem: keine Unterscheidung im Protokoll zwischen Befehlen vom STM und solchen von Modulen. Erst ACK ist Unterscheid
#       bei direktem Befehl meint STM dass es ein Feedback-Befeh ist. Die Acks überschneiden sich.
#       -> direktes Ansprechen von AMDs scheint nicht sinnvoll.
#       also Fhem als virtuelles EMD, STM soll dann AMDs ansprechen.
#   AMD in Fhem simulieren?
#       Fhem auf RPI viel zu langsam - erster Empfang enthält bereits 8 Resends vom STM bis Fhem überhaupt Befehl verarbeitet
#       insgesamt kommen 63 Resends ...
#


package main;

use strict;
use warnings;
use Time::HiRes qw( gettimeofday tv_interval time );
use Encode qw(decode encode);

sub PHC_Initialize($);
sub PHC_Define($$);
sub PHC_Undef($$);
sub PHC_Set($@);
sub PHC_Get($@);
sub PHC_Read($);
sub PHC_Ready($);
sub PHC_ReadAnswer($$$);
sub PHC_ParseFrames($);
sub PHC_HandleSendQueue($);
sub PHC_TimeoutSend($);

my $PHC_Version = '0.42 - 31.8.2018';
    

my %PHC_AdrType = (
    0x00 => ['EMD'],            # Class 0 starts at 0x00      (EMD, ...)
    0x20 => ['MCC', 'UIM'],     # Class 1 starts at 0x20 / 32 (UIM, MCC, ...)
    0x40 => ['AMD', 'JRM'],     # Class 2 starts at 0x40 / 64 (AMD, JRM)
    0x60 => ['MFM'],            # Class 3 starts at 0x60 / 96 (MFM, ...) FUI = MFM
    0x80 => [],                 # Class 4 starts at 0x80 / 128 (?)
    0xA0 => ['DIM'],            # Class 5 starts at 0xA0 / 160 (DIM, ...)
    0xC0 => [],                 # ?
    0xE0 => ['CLK']             #
);


# shr bits for channel, &-Mask for function
my %PHC_CodeSplit = (
    'EMD' => [4, 0x0F], 
    'MCC' => [4, 0x0F], 
    'UIM' => [4, 0x0F], 
    'AMD' => [5, 0x1F], 
    'JRM' => [5, 0x1F], 
    'MFM' => [4, 0x0F], 
    'DIM' => [5, 0x1F], 
    'CLK' => [4, 0x0F]
);


#
# Options:
#   cbm Channel bits in Message
#   cba Channel bits in Ack
#   o   use name for output channel
#   i   use name for input channel
#   t1  time in data bytes 1+2
#   t2  time in data bytes 2+3, 4+5 and 6+7 if present
#   p   priority information in data byte 1
#

# format: 'Type Function Len Acklen' => ['Function Name', Options]
#           len=1 means just one byte for function/channel 
#                   e.g. a Frame with Adr, 81/01, Fkt/Chan CRC

my %PHC_functions = (
    'EMD02+01' => ['Ein > 0', 'i'],
    'EMD03+01' => ['Aus < 1', 'i'],
    'EMD04+01' => ['Ein > 1', 'i'],
    'EMD05+01' => ['Aus > 1', 'i'],
    'EMD06+01' => ['Ein > 2', 'i'],
    'EMD07+01' => ['Aus', 'i'],
    
    'EMD020103' => ['LED_Ein', 'o'],
    'EMD030103' => ['LED_Aus', 'o'],
    
    'AMD010102' => ['Ping', 'cba'],
    'AMD020102' => ['Ein', 'cba'],
    'AMD030102' => ['Aus', 'cba'],
    'AMD040102' => ['An Lock', 'cba'],
    'AMD050102' => ['Aus Lock', 'cba'],
    'AMD060102' => ['Umschalten', 'cba'],
    'AMD070102' => ['Unlock', 'cba'],
    'AMD080302' => ['An verzögert', 'cba', 't1'],
    'AMD090302' => ['Aus verzögert', 'cba', 't1'],
    'AMD100302' => ['An mit Timer', 'cba', 't1'],
    'AMD110302' => ['Aus mit Timer', 'cba', 't1'],
    'AMD120302' => ['Umschalten verzögert', 'cba', 't1'],
    'AMD130302' => ['Umschalten mit Timer', 'cba', 't1'],
    'AMD140102' => ['Lock', 'cba'],
    'AMD150102' => ['Lock for time running', 'cba'],
    'AMD160302' => ['Timer Addieren', 'cba', 't1'],
    'AMD170302' => ['Timer setzen', 'cba', 't1'],
    'AMD180102' => ['Timer cancel', 'cba'],

    'AMD020201' => ['FB_Ein', 'cbm'],
    'AMD030201' => ['FB_Aus', 'cbm'],
    'AMD290201' => ['FB_Timer_Aus', 'cbm'],     # kommt nach F10 wenn Zeit abgelaufen ist todo: check aus mit timer feedback?
    

    'JRM020202' => ['Stop'],
    'JRM030402' => ['Umschalten heben stop', 'p', 't2'],
    'JRM040402' => ['Umschalten senken stop', 'p', 't2'],
    'JRM050402' => ['Heben', 'p', 't2'],
    'JRM060402' => ['Senken', 'p', 't2'],
    'JRM070402' => ['Flip auf', 'p', 't2'],
    'JRM080402' => ['Flip ab', 'p', 't2'],

    'JRM030201' => ['FB_Senken_Ein', 'cbm'],
    'JRM040201' => ['FB_Heben_Aus', 'cbm'],
    'JRM050201' => ['FB_Senken_Aus', 'cbm'],

    'JRM060201' => ['FB_Timer_Ein', 'cbm'],
    'JRM060301' => ['FB_Timer_Ein', 'cbm'],
    
    'JRM070201' => ['FB_Timer_Cancel', 'cbm'],
    'JRM080201' => ['FB_Timer_Aus', 'cbm'],
    
    'JRM090202' => ['Prio lock', 'p'],
    'JRM100202' => ['Prio unlock', 'p'],
    'JRM11'     => ['Lernen an'],           # uses different communication
    'JRM12'     => ['Lernen aus'],
    'JRM130202' => ['Prio setzen', 'p'],
    'JRM140202' => ['Prio löschen', 'p'],
    'JRM150602' => ['Sensor heben', 'p', 't2'],
    'JRM160802' => ['Sensor heben flip', 'p', 't2'],
    'JRM170602' => ['Sensor senken', 'p', 't2'],
    'JRM180802' => ['Sensor senken flip', 'p', 't2'],
    'JRM190302' => ['Zeitmessung verzögert an', 't1'],
    'JRM200302' => ['Zeitmessung verzögert aus', 't1'],
    'JRM210302' => ['Zeitmessung an mit Timer', 't1'],
    'JRM220102' => ['Zeitmessung cancel'],
    
    'DIM020102' => ['Ein Max mit Memory', 'cba'],
    'DIM030102' => ['Ein Max ohne Memory', 'cba'],
    'DIM040102' => ['Aus', 'cba'],
    'DIM050102' => ['Umschalten Max mit Memory', 'cba'],
    'DIM060102' => ['Umschalten Max ohne Memory', 'cba'],
    'DIM070302' => ['Dimmen Gegenrichtung', 'cba'],
    'DIM080302' => ['Heller Dimmen', 'cba'],
    'DIM090302' => ['Dunkler Dimmen', 'cba'],
    'DIM100102' => ['Speichern Memory', 'cba'],
    'DIM110102' => ['Umschalten Memory', 'cba'],
    'DIM120102' => ['Ein Memory', 'cba'],
    'DIM130102' => ['Speichern DIA1', 'cba'],
    'DIM140102' => ['Umschalten DIA1', 'cba'],
    'DIM150102' => ['Ein DIA1', 'cba'],
    'DIM160102' => ['Speichern DIA2', 'cba'],
    'DIM170102' => ['Umschalten DIA2', 'cba'],
    'DIM180102' => ['Ein DIA2', 'cba'],
    'DIM190102' => ['Speichern DIA3', 'cba'],
    'DIM200102' => ['Umschalten DIA3', 'cba'],
    'DIM210102' => ['Ein DIA3', 'cba'],
    'DIM220302' => ['Dimmwert und Zeit setzen', 'cba'],
    
    'DIM020201' => ['FB_Ein', 'cba'],
    'DIM030201' => ['FB_Aus', 'cba'],
    
    'MFM020103' => ['Ein', 'o'],
    'MFM030103' => ['Aus', 'o'],
    'MFM040103' => ['Umschalten', 'o'],
    'MFM050103' => ['Ein verzögert', 'o'],
    'MFM060103' => ['Aus verzögert', 'o'],
    'MFM070103' => ['Ein mit Timer', 'o'],
    'MFM080103' => ['Aus mit Timer', 'o'],
    'MFM090103' => ['Dimmen in Gegenrichtung', 'o'],
    'MFM100103' => ['Heller Dimmen', 'o'],
    'MFM110103' => ['Dunkler Dimmen', 'o'],
    'MFM120103' => ['Dimmwert und Zeit setzen', 'o'],
    'MFM130103' => ['Rollade heben', 'o'],
    'MFM140103' => ['Rollade senken', 'o'],
    'MFM150103' => ['Aktion abbrechen', 'o'],

    'MFM020101' => ['Taste O Ein > 0', 'i'],
    'MFM030101' => ['Taste I Ein > 0', 'i'],
    'MFM040101' => ['Taste O Aus', 'i'],
    'MFM050101' => ['Taste I Aus', 'i'],
    'MFM060101' => ['unknown'],
    'MFM070101' => ['unknown'],
    'MFM080101' => ['unknown'],
    'MFM090101' => ['unknown'],
    'MFM100101' => ['unknown'],
    'MFM110101' => ['unknown'],
    
    'UIM020101' => ['On/Off Ein', 'i'],
    'UIM040101' => ['Auf Ein', 'i'],
    'UIM060101' => ['Ab Ein', 'i'],

    'MCC020101' => ['Ein > 0', 'i'],
    'MCC020103' => ['LED Ein', 'o', 'cba'],
    'MCC030103' => ['LED Aus', 'o', 'cba'],
    'MCC090103' => ['LED Blink'],

    'CLK03'     => ['Clock Request']

);


    
#####################################
sub PHC_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{ReadFn}  = "PHC_Read";
    $hash->{ReadyFn} = "PHC_Ready";
    $hash->{DefFn}   = "PHC_Define";
    $hash->{UndefFn} = "PHC_Undef";
    $hash->{SetFn}   = "PHC_Set";
    $hash->{GetFn}   = "PHC_Get";
    $hash->{AttrFn}  = "PHC_Attr";
          
    $hash->{AttrList}= "do_not_notify:1,0 " . 
        "queueDelay " .
        "timeout " .
        "queueMax " . 
        "silentReconnect " .
        "singleLastCommandReading " .
        "sendEcho:1,0 " .
        "module[0-9]+description " .
        "module[0-9]+type " .
        "channel(EMD|AMD|JRM|DIM|UIM|MCC|MFM)[0-9]+[io]?[0-9]+description " .
        "virtEMD[0-9]+C[0-9]+Name " .       # virtual emd channel for set
        $readingFnAttributes;
}


#####################################
sub PHC_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my ($name, $PHC, $dev) = @a;
    return "wrong syntax: define <name> PHC [devicename]"
        if(@a < 3);
        
    eval "use Digest::CRC qw(crc crc32 crc16 crcccitt)";
    if($@) {
        return "Please install the Perl Digest Library (apt-get install libdigest-crc-perl) - error was $@";
    }       
        
    $hash->{BUSY}   = 0;    
    $hash->{EXPECT} = "";
    $hash->{ModuleVersion} = $PHC_Version;
    
    if ($dev !~ /.+@([0-9]+)/) {
        $dev .= '@19200,8,N,2';
    } else {
        Log3 $name, 3, "$name: Warning: connection speed $1 is probably wrong for the PHC bus. Default is 19200,8,N,2"
            if ($1 != 19200);
    }

    $hash->{DeviceName} = $dev;
    $hash->{devioLoglevel}  = (AttrVal($name, "silentReconnect", 0) ? 4 : 3);
    DevIo_CloseDev($hash);
    my $ret = DevIo_OpenDev($hash, 0, 0);

    return $ret;
}


#####################################
sub PHC_Undef($$)
{
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    DevIo_CloseDev($hash); 
    return undef;
}


# Attr command 
#########################################################################
sub PHC_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    my $hash    = $defs{$name};

    Log3 $name, 5, "$name: Attr called with @_";
    if ($cmd eq "set") {
        if ($aName =~ 'virtEMD([0-9]+)C([0-9]+)Name(.*)') {
            my $modAdr = $1;
            my $cnlAdr = $2;
            if ($modAdr >= 32) {
                return "illegal EMD module address $modAdr - address needs to be < 32 and it must not be used on the bus";
            }
            if ($cnlAdr >= 15) {
                return "illegal EMD channel address $cnlAdr - address needs to be < 16";
            }
            
            my @virtEMDList = grep (/virtEMD[0-9]+C[0-9]+Name/, keys %{$attr{$name}});
            my $emdAdr     = "";
            my $emdChannel = "";
            foreach my $attrName (@virtEMDList) {
                if ($aVal eq $attr{$name}{$attrName}) {     # ist es der im konkreten Attr verwendete Name?
                    if ($attrName =~ /virtEMD([0-9]+)C([0-9]+)Name/) {
                        return "Name $aVal is already used for virtual EMD $modAdr channel $cnlAdr";
                    }
                }            
            }            
        }
    }
}


#####################################
sub PHC_Get($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $getName = $a[1];

    return "\"get $name\" needs at least one argument" if(@a < 2);

    return undef;
}


#####################################
sub PHC_DoEMD($$$$)
{
    my ($hash, $modAdr, $channel, $fName) = @_;
    my $name = $hash->{NAME};
    my $function = 0;
    Log3 $name, 3, "$name: DoEMD called for module $modAdr, channel $channel, function $fName";
    foreach my $hkey (grep (/EMD/, keys %PHC_functions)) {
        #Log3 $name, 5, "$name: hkey $hkey";
        my $fn = lc $PHC_functions{$hkey}[0];
        #Log3 $name, 5, "$name: fn $fn";
        $fn =~ s/ //g;
        if ($fn =~ /(.*),.*/) {
            $fn = $1;
        }
        #Log3 $name, 5, "$name: compare to $fn";
        if ($fn eq $fName) {
            if ($hkey =~ /EMD0([0-9]).*/) {
                $function = $1;
                last;
            }
        }
    }
    return "function $fName not found" if (!$function);
    Log3 $name, 5, "$name: found function $function";
            
    if ($hash->{Toggle}{$modAdr} && $hash->{Toggle}{$modAdr} eq 's') {
        $hash->{Toggle}{$modAdr} = 'c';
        Log3 $name, 3, "$name: toggle for module $modAdr was set and will now be cleared";
    } elsif ($hash->{Toggle}{$modAdr} && $hash->{Toggle}{$modAdr} eq 'c') {
        $hash->{Toggle}{$modAdr} = 's';
        Log3 $name, 5, "$name: toggle for module $modAdr was cleared and will now be set";
    } else {
        $hash->{Toggle}{$modAdr} = 'c';
        Log3 $name, 3, "$name: toggle for module $modAdr was unknown and will now be cleared";      
    }
    my $len  = 1 | (($hash->{Toggle}{$modAdr} eq 's' ? 1 : 0) << 7);
            
    #Log3 $name, 3, "$name: len is $len";
    my $code = ($function + ($channel << 4));

    my $frame = pack ('CCC', $modAdr, $len, $code);
    my $crc   = pack ('v', crc($frame, 16, 0xffff, 0xffff, 1, 0x1021, 1, 0));   
       $frame = $frame . $crc;

    my $hFrame = unpack ('H*', $frame);
    Log3 $name, 3, "$name: sends $hFrame";
    
    if (!AttrVal($name, "sendEcho", 0)) {
        my $now  = gettimeofday();
        $hash->{helper}{buffer} .= $frame;
        $hash->{helper}{lastRead} = $now;       
    }
    
    DevIo_SimpleWrite($hash, $frame, 0);
}


#####################################
sub PHC_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set $a[0]\" needs at least an argument" if(@a < 2);

    my ($name, $setName, @setValArr) = @a;
    my $setVal = (@setValArr ? join(' ', @setValArr) : "");
    
    if ($setName eq 'importChannelList') {
        if ($setVal) {
            my $iFile;
            if (!open($iFile, "<", $setVal)) {
                Log3 $name, 3, "$name: Cannot open template file $setVal";
                return;
            };
            my $mType = 'unknown';
            my $mAdr  = 'unknown';
            my $aAdr  = 'unknown';
            my $mName = 'unknown';
            my $mDisp = 'unknown';
            my $cType = 'i';
            my ($key, $cAdr, $cName);
            while (<$iFile>) {
                Log3 $name, 5, "$name: import read line $_";
                if ($_ =~ /<MOD adr="([0-9]+)" name="([^"]+)" display="([^"]+)"/) {
                    $aAdr  = sprintf('%03d', $1);
                    $mAdr  = sprintf('%02d', $1 & 0x1f);
                    $mName = $2;
                    $mDisp = encode ('UTF-8', $3);
                    $mType = substr($mName, 0, 3);
                    CommandAttr(undef, "$name module${aAdr}description $mDisp");
                    CommandAttr(undef, "$name module${aAdr}type $mType");
                } elsif ($_ =~ /<OUT>/) {
                    $cType = 'o';
                } elsif ($_ =~ /<IN>/) {
                    $cType = 'i';
                } elsif ($_ =~ /<CHA adr="([0-9]+)" name="([^"]+)" visu="([^"]+)"\/>/) {
                    my $rAdr = $1 & 0x1f;
                    $cAdr  = sprintf('%02d', $rAdr);
                    $cName = encode ('UTF-8', $2);
                    $key  = $mType . $mAdr . $cType . $cAdr; 
                    CommandAttr(undef, "$name channel${key}description $cName");
                }
            }
        } else {
            return "please specify a filename";
        }
    } elsif ($setName eq "emd") {
        my @arg = @setValArr;
        shift @arg; shift @arg;
        my $fName = lc join('', @arg);
        return PHC_DoEMD($hash, $setValArr[0], $setValArr[1], $fName);
               
    } elsif ($setName eq "sendRaw") {

        my $modAdr = $setValArr[0];
        my $hexCmd = $setValArr[1];
        
        if ($hash->{Toggle}{$modAdr} && $hash->{Toggle}{$modAdr} eq 's') {
            $hash->{Toggle}{$modAdr} = 'c';
            Log3 $name, 3, "$name: toggle for module $modAdr was set and will now be cleared";
        } elsif ($hash->{Toggle}{$modAdr} && $hash->{Toggle}{$modAdr} eq 'c') {
            $hash->{Toggle}{$modAdr} = 's';
            Log3 $name, 5, "$name: toggle for module $modAdr was cleared and will now be set";
        } else {
            $hash->{Toggle}{$modAdr} = 'c';
            Log3 $name, 3, "$name: toggle for module $modAdr was unknown and will now be cleared";      
        }
        
        my $len  = (length ($hexCmd) / 2) | (($hash->{Toggle}{$modAdr} eq 's' ? 1 : 0) << 7);
        #Log3 $name, 3, "$name: len is $len";

        my $frame = pack ('H2CH*', $modAdr, $len, $hexCmd);
        my $crc   = pack ('v', crc($frame, 16, 0xffff, 0xffff, 1, 0x1021, 1, 0));   
           $frame = $frame . $crc;

        my $hFrame = unpack ('H*', $frame);
        Log3 $name, 3, "$name: sends $hFrame";
                
        if (!AttrVal($name, "sendEcho", 0)) {
            my $now  = gettimeofday();
            $hash->{helper}{buffer} .= $frame;
            $hash->{helper}{lastRead} = $now;       
        }
        DevIo_SimpleWrite($hash, $frame, 0);
               
    } else {    
        my @virtEMDList = grep (/virtEMD[0-9]+C[0-9]+Name/, keys %{$attr{$name}});
        my $emdAdr     = "";
        my $emdChannel = "";
        foreach my $aName (@virtEMDList) {
            if ($setName eq $attr{$name}{$aName}) {     # ist es der im konkreten Set verwendete setName?
                if ($aName =~ /virtEMD([0-9]+)C([0-9]+)Name/) {
                    $emdAdr     = $1;                           # gefunden -> merke Nummer X im Attribut
                    $emdChannel = $2;
                }
            }            
        }
        if ($emdAdr eq "") {
            # todo: map to values, add hints
            my $hints = ":ein>0,ein>1,ein>2,aus,aus<1,aus>1";
            return "Unknown argument $setName, choose one of importChannelList sendRaw " . join (' ', map ($attr{$name}{$_} . $hints, @virtEMDList));
        }
        return PHC_DoEMD($hash, $emdAdr, $emdChannel, $setVal);
    }
    return undef;
}




#####################################
# Called from ParseCommands
sub PHC_ParseCode($$)
{
    my ($hash, $command) = @_;
    my $name = $hash->{NAME};
    
    my $fAdr = sprintf('%03d', $command->{ADR});                        # formatted abs adr for attr lookup (mod type)
    my @typeArr = split (',', AttrVal($name, "module${fAdr}type", "")); # potential types from attr
    my $typeAttrLen = @typeArr;                                         # number of potential types in attr
    @typeArr = @{$PHC_AdrType{$command->{ADR} & 0xE0}} if (!@typeArr);  # fallback to types from AdrType hash
    my $mType = $typeArr[0];                                            # first option for split (same for all options)
    
    Log3 $name, 5, "$name: ParseCode called, fAdr $fAdr, typeArr = @typeArr, code " . sprintf ('x%02X', $command->{CODE});
    #Log3 $name, 5, "$name: ParseCode data = @{$command->{DATA}}";
    #Log3 $name, 5, "$name: ParseCode ackdata = @{$command->{ACKDATA}}";
    
    return PHC_LogCommand($hash, $command, "unknown module type", 3) if (!$mType);
    $command->{MTYPE} = $mType;                             # first idea unless we find a fit later
    
    # splitting and therefore channel and function are the same within one address class
    # so they are ok to calculate here regardless of the exact module type identified later
    my ($channel, $function) = PHC_SplitCode($hash, $mType, $command->{CODE});
    $command->{CHANNEL} = $channel;
    $command->{FUNCTION} = $function;
    
    my $key1 = sprintf('%02d', $function);
    my $key2 = sprintf('%02d', $command->{LEN});
    my $key3 = sprintf('%02d', $command->{ACKLEN});
    my $wldk = '+';
    my @keys = ("$mType$key1$key2$key3", "$mType$key1$wldk$key3", "$mType$key1$key2", "$mType$key1");
    
    Log3 $name, 5, "$name: ParseCode checks typelist @typeArr against" . 
            " F=" . sprintf ('x%02X', $function) . " C=" . sprintf ('x%02X', $channel) . "Len=$command->{LEN}, ackLen=$command->{ACKLEN}";
    my $bestFit = 0;                                        # any fit of key 3, 2 or 1 is better than 0
    foreach my $mTypePot (@typeArr) {
        #Log3 $name, 5, "$name: ParseCode checks if type of module at $fAdr can be $mTypePot";
        my $idx = 4;    # fourlevels of abstraction in the PHC_functions hash
        
        # does this module type match better than a previously tested type?
        foreach my $key (@keys) {
            if ($PHC_functions{$key}) {
                #Log3 $name, 5, "$name: match: $key";
                if ($idx > $bestFit) {                      # longer = better matching type found
                    $bestFit = $idx;
                    my @parseOpts = @{$PHC_functions{$key}};
                    $command->{MTYPE} = $mTypePot;
                    $command->{FNAME} = shift @parseOpts;
                    foreach (@parseOpts) {$command->{PARSEOPTS}{$_} = 1};
                    Log3 $name, 5, "$name: ParseCode match $key / $command->{FNAME} " . join (',', @parseOpts);
                }
                last;                                       # first match is the best for this potential type
            } else {
                if (!$idx) {    # this was the last try for this type with $idx=0, $key=$mTypePot$key1
                    @typeArr = grep {!/$mTypePot/} @typeArr;    # module type is not an option any more
                    Log3 $name, 5, "$name: ParseCode could not match to $mTypePot, delete this option";
                }
            }
            $idx--;
        }   
    }
    Log3 $name, 4, "$name: ParseCode typelist after matching is @typeArr" if (@typeArr > 1);

    return PHC_LogCommand($hash, $command, "no parse info", 3) if (!$command->{FNAME});
    
    $command->{CTYPE} = ($command->{PARSEOPTS}{'i'} ? 'i' : 'o');
    
    if (!$typeAttrLen || (scalar(@typeArr) >= 1 && scalar(@typeArr) < $typeAttrLen)) {
        # no moduleType attr so far or we could eliminate an option -> set more specific new attr
        CommandAttr(undef, "$name module${fAdr}type " . join (',', @typeArr));
        Log3 $name, 4, "$name: set attr $name module${fAdr}type " . join (',', @typeArr); 
    }
    return 1;
}


#####################################
# Called from ParseCommands
sub PHC_ParseOptions($$)
{
    my ($hash, $command) = @_;
    my $name = $hash->{NAME};
    my $dLen = @{$command->{DATA}};
    
    if ($command->{PARSEOPTS}{'p'}) {
        $command->{PRIO} = unpack ('b6', pack ('C', $command->{DATA}[1] & 0x3F));
        $command->{PSET} = $command->{DATA}[1] & 0x40;
    }
    
    if ($command->{PARSEOPTS}{'t1'}) {
        $command->{TIME1} = $command->{DATA}[1] + ($command->{DATA}[2] << 8) if ($dLen > 2);
    }
    
    if ($command->{PARSEOPTS}{'t2'}) {      
        $command->{TIME1} = $command->{DATA}[2] + ($command->{DATA}[3] << 8) if ($dLen > 3);
        $command->{TIME2} = $command->{DATA}[4] + ($command->{DATA}[5] << 8) if ($dLen > 5);
        $command->{TIME3} = $command->{DATA}[6] + ($command->{DATA}[7] << 8) if ($dLen > 7);
    }
}


# todo: zumindest bei emds können mehrere codes (channel/function) nacheinender in einer message kommen
# wenn zwei tasten gleichzeitig gedrückt werden...

#####################################
# Called from ParseFrames
sub PHC_ParseCommands($$)
{
    my ($hash, $command) = @_;
    my $name = $hash->{NAME};
    
    return if (!PHC_ParseCode($hash, $command));
    PHC_ParseOptions($hash, $command);
    PHC_LogCommand($hash, $command, "", ($command->{MTYPE} eq "CLK" ? 5:4));

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'LastCommand', PHC_CmdText($hash, $command));
    
    DoTrigger($name, PHC_ChannelText($hash, $command, $command->{CHANNEL}) . ": " . $command->{FNAME});

    # channel bits aus Feedback / Ack verarbeiten
    if ($command->{PARSEOPTS}{'cbm'} || $command->{PARSEOPTS}{'cba'}) {
        my $bin = unpack ("B8", pack ("C", ($command->{PARSEOPTS}{'cbm'} ? $command->{DATA}[1] : $command->{ACKDATA}[1])));
        Log3 $name, 5, "$name: ParseCommand channel map = $bin";
        my $channelBit = 7;
        foreach my $c (split //, $bin) {
            my $bitName = PHC_ChannelDesc($hash, $command, $channelBit);
            Log3 $name, 5, "$name: ParseCommand Reading for channel $channelBit is $c ($bitName)";
            readingsBulkUpdate($hash, $bitName, $c) if ($bitName);
            $channelBit --;
        }
    }
    
    my @data = @{$command->{DATA}};
    if ($command->{PARSEOPTS}{'i'} && @data > 1) {
        my $codeIdx = 1;    # second code
        while ($codeIdx < @data) {
            Log3 $name, 5, "$name: ParseCommand now handles additional code at Index $codeIdx";
            $command->{CODE} = $data[$codeIdx];
            PHC_ParseCode($hash, $command);
            PHC_LogCommand($hash, $command, "", 4);
            DoTrigger($name, PHC_ChannelText($hash, $command, $command->{CHANNEL}) . ": " . $command->{FNAME});
            $codeIdx++;
        }
        Log3 $name, 5, "$name: ParseCommand done";
    }
    
    readingsEndUpdate($hash, 1);
}


#####################################
# Called from the read functions
sub PHC_ParseFrames($)
{
    my $hash  = shift;
    my $name  = $hash->{NAME};
    my $frame;
    my $hFrame;
    my ($adr, $xAdr, $len, $tog, $rest, $pld, $crc, $crc1);
    my $rLen;
    my @data;
    
    #Log3 $name, 5, "$name: Parseframes called";    
    use bytes;
    if (!$hash->{skipReason}) {
        $hash->{skipBytes}   = "";
        $hash->{skipReason}  = "";
    };
    
    while ($hash->{helper}{buffer}) {
    
        $hash->{RAWBUFFER} = unpack ('H*', $hash->{helper}{buffer});
        Log3 $name, 5, "$name: Parseframes: loop with raw buffer: $hash->{RAWBUFFER}" if (!$hash->{skipReason});
        
        $rLen = length($hash->{helper}{buffer});
        return if ($rLen < 4);

        ($adr, $len, $rest) = unpack ('CCa*', $hash->{helper}{buffer});
        $xAdr = unpack('H2', $hash->{helper}{buffer});
        $tog = $len >> 7;
        $len = $len & 0x7F;

        if ($len > 30) {
            Log3 $name, 5, "$name: Parseframes: len > 30, skip first byte of buffer $hash->{RAWBUFFER}";
            $hash->{skipBytes} .= substr ($hash->{helper}{buffer},0,1);
            $hash->{skipReason} = "Len > 30" if (!$hash->{skipReason});
            $hash->{helper}{buffer} = substr ($hash->{helper}{buffer}, 1);
            next;
        }

        if (($rLen < 20) && ($rLen < $len + 4)) {
            Log3 $name, 5, "$name: Parseframes: len is $len so frame shoud be " . ($len + 4) . " but only $rLen read. wait for more";
            return;
        }        
        $frame  = substr($hash->{helper}{buffer},0,$len+2);     # the frame (adr, tog/len, cmd/data) without crc
        $hFrame = unpack ('H*', $frame);
        
        ($pld, $crc, $rest) = unpack ("a[$len]va*", $rest);     # v = little endian unsigned short, n would be big endian
        @data  = unpack ('C*', $pld);
        $crc1  = crc($frame, 16, 0xffff, 0xffff, 1, 0x1021, 1, 0);
        my $fcrc  = unpack ("H*", pack ("v", $crc));
        my $fcrc1 = unpack ("H*", pack ("v", $crc1));

        if ($crc != $crc1) {
            #my $skip = $len + 4;
            my $skip = 1;
            Log3 $name, 5, "$name: Parseframes: CRC error for $hFrame $fcrc, calc $fcrc1) - skip $skip bytes of buffer $hash->{RAWBUFFER}";
            $hash->{skipBytes} .= substr ($hash->{helper}{buffer},0,$skip);
            $hash->{skipReason} = "CRC error" if (!$hash->{skipReason});
            $hash->{helper}{buffer} = substr ($hash->{helper}{buffer}, $skip);
            next;
        }

        Log3 $name, 4, "$name: Parseframes: skipped " . 
            unpack ("H*", $hash->{skipBytes}) . " reason: $hash->{skipReason}"
            if $hash->{skipReason};
            
        $hash->{skipBytes}   = "";
        $hash->{skipReason}  = "";
        $hash->{helper}{buffer} = $rest;
        Log3 $name, 5, "$name: Parseframes: Adr $adr/x$xAdr Len $len T$tog Data " . unpack ('H*', $pld) . " (Frame $hFrame $fcrc) Rest " . unpack ('H*', $rest)
            if ($adr != 224);   # todo: remove this filter later (hide noisy stuff)
        
        $hash->{Toggle}{$adr} = ($tog ? 's' : 'c');     # save toggle for potential own sending of data

        if ($hash->{COMMAND} && $hFrame eq $hash->{COMMAND}{FRAME}) {
            Log3 $name, 4, "$name: Parseframes: Resend of $hFrame $fcrc detected";
            next;
        }   
        
        my $cmd = $data[0];
        
        if ($cmd == 1) {
            # Ping / Ping response
            if (!$hash->{COMMAND}) {
                Log3 $name, 5, "$name: Parseframes: Ping request received";
                # fall through until $hash->{COMMAND} is set                
            } else {
                if ($hash->{COMMAND}{CODE} == 1 && $hash->{COMMAND}{ADR} == $adr) {
                    # this must be the response
                    Log3 $name, 5, "$name: Parseframes: Ping response received";
                    $hash->{COMMAND}{ACKDATA} = \@data;
                    $hash->{COMMAND}{ACKLEN} = $len;
                    PHC_ParseCommands($hash, $hash->{COMMAND});
                    next;
                } else {
                    # no reply to last command - ping or something else - now we seem to have a new ping request    
                    Log3 $name, 4, "$name: Parseframes: new Frame $hFrame $fcrc but no ACK for valid last Frame $hash->{COMMAND}{FRAME} - dropping last one";
                    delete $hash->{COMMAND};   # done with this command
                    # fall through until $hash->{COMMAND} is set                
                }
            }
        } elsif ($cmd == 254) {
            # reset
            # todo: get module name / type and show real type / adr in Log, add to comand reading or go through parsecommand with simulated acl len 0 ...
            
            # parse payload in parsecommand
            # por byte, many channel/ function bytes
            
            Log3 $name, 4, "$name: Parseframes: configuration request for adr $adr received - frame is $hFrame $fcrc";
            delete $hash->{COMMAND};   # done with this command
            next;

        } elsif ($cmd == 255) {
            # reset
            Log3 $name, 4, "$name: Parseframes: reset for adr $adr received - frame is $hFrame $fcrc";
            delete $hash->{COMMAND};   # done with this command
            next;
            
        } elsif ($cmd == 0) {
            # ACK received
            Log3 $name, 5, "$name: Parseframes: Ack received";
            if ($hash->{COMMAND}) {
                if ($hash->{COMMAND}{ADR} != $adr) {
                    Log3 $name, 4, "$name: Parseframes: ACK frame $hFrame $fcrc does not match adr of last Frame $hash->{COMMAND}{FRAME}";
                } elsif ($hash->{COMMAND}{TOGGLE} != $tog) {
                    Log3 $name, 4, "$name: Parseframes: ACK frame $hFrame $fcrc does not match toggle of last Frame $hash->{COMMAND}{FRAME}";
                } else {  # this ack is fine
                    $hash->{COMMAND}{ACKDATA} = \@data;
                    $hash->{COMMAND}{ACKLEN} = $len;
                    PHC_ParseCommands($hash, $hash->{COMMAND});
                }
                delete $hash->{COMMAND};   # done with this command
                next;
            } else {
                Log3 $name, 4, "$name: Parseframes: ACK frame $hFrame $fcrc without a preceeding request - dropping";
                next;
            }
        } else {
            # normal command - no ack, ping etc.
            if ($hash->{COMMAND}) {
                Log3 $name, 4, "$name: Parseframes: new Frame $hFrame $fcrc but no ACK for valid last Frame $hash->{COMMAND}{FRAME} - dropping last one";
            } 
            Log3 $name, 5, "$name: Parseframes: $hFrame $fcrc is not an Ack frame, wait for ack to follow";
            # todo: set timeout timer if not ACK received 
        }
        my @oldData = @data;
        $hash->{COMMAND}{ADR} = $adr;
        $hash->{COMMAND}{LEN} = $len;
        $hash->{COMMAND}{TOGGLE} = $tog;
        $hash->{COMMAND}{DATA} = \@oldData;
        $hash->{COMMAND}{CODE} = $oldData[0];
        $hash->{COMMAND}{FRAME} = $hFrame;
    }
}


#####################################
# Called from the global loop, when the select for hash->{FD} reports data
sub PHC_Read($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    
    # throw away old stuff
    if ($hash->{helper}{lastRead} && ($now - $hash->{helper}{lastRead}) > 1) {
        if ($hash->{helper}{buffer}) {
            Log3 $name, 5, "throw away " . unpack ('H*', $hash->{helper}{buffer}); 
        }
        $hash->{helper}{buffer} = "";
    }
    $hash->{helper}{lastRead} = $now;
    
    my $buf = DevIo_SimpleRead($hash);
    return if(!defined($buf));
    
    $hash->{helper}{buffer} .= $buf;  
    
    PHC_ParseFrames($hash);
}


#####################################
# Called from get / set to get a direct answer
sub PHC_ReadAnswer($$$)
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
                return("PHC_ReadAnswer $arg: $err", undef);
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

        $framedata = PHC_ParseFrames($hash);
    }
}


#####################################
sub PHC_Ready($)
{
    my ($hash) = @_;
    return DevIo_OpenDev($hash, 1, undef)
        if($hash->{STATE} eq "disconnected");

    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  
    return ($InBytes>0);
}


#######################################
sub PHC_TimeoutSend($)
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



###############################################################
# split code into channel and function depending on module type
sub PHC_SplitCode($$$)
{
    my ($hash, $mType, $code) = @_;
    #Log3 $hash->{NAME}, 5, "$hash->{NAME}: PHC_SplitCode called with code $code and type $mType";
    my @splitArr = @{$PHC_CodeSplit{$mType}};
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: SplitCode splits code " .
        sprintf ('%02d', $code) . " for type $mType into " .
        " channel " . ($code >> $splitArr[0]) . " / function " . ($code & $splitArr[1]);
    return ($code >> $splitArr[0], $code & $splitArr[1]);   # channel, function
}




###############################################################
# log message with command parse data
sub PHC_LogCommand($$$$)
{
    my ($hash, $command, $msg, $level) = @_;
    Log3 $hash->{NAME}, $level, "$hash->{NAME}: " . PHC_Caller() . ' ' . PHC_CmdText($hash, $command) . $msg;
}


###############################################################
# get Text like EMD12i01
sub PHC_ChannelText($$$)
{
    my ($hash, $command, $channel) = @_;
    my $fmAdr = sprintf('%02d', ($command->{ADR} & 0x1F));      # relative module address formatted with two digits
    my $mType = $command->{MTYPE};

    return  ($mType ? $mType . $fmAdr : 'Module' . sprintf ("x%02X", $command->{ADR})) .
            ($command->{CTYPE} ? $command->{CTYPE} : "") .
            (defined($channel) ? sprintf('%02d', $channel) : "");
}


###############################################################
# full detail of a command for logging
sub PHC_CmdText($$)
{
    my ($hash, $command) = @_;

    my $adr     = $command->{ADR};
    my $mAdr    = $adr & 0x1F;             # relative module address
    my $fmAdr   = sprintf('%02d', $mAdr);
    my $mType   = $command->{MTYPE};
    my $channel = $command->{CHANNEL};
    my $cDesc   = PHC_ChannelDesc($hash, $command, $channel);
    my $start   = PHC_ChannelText($hash, $command, $channel);
    return  ($start ? $start : "") . 
            ($command->{FUNCTION} ? " F$command->{FUNCTION}" : "") .
            ($command->{FNAME} ? " $command->{FNAME}" : "") .
            (defined($command->{PRIO}) ? " P$command->{PRIO}" : "") .
            (defined($command->{PRIO}) ? ($command->{PSET} ? " (Set)" : " (no Set)") : "") .
            (defined($command->{TIME1}) ? " Time1 $command->{TIME1}" : "") .
            (defined($command->{TIME2}) ? " Time2 $command->{TIME2}" : "") .
            (defined($command->{TIME3}) ? " Time3 $command->{TIME3}" : "") .
            " data " . join (",", map ({sprintf ("x%02X", $_)} @{$command->{DATA}})) .
            " ack " . join (",", map ({sprintf ("x%02X", $_)} @{$command->{ACKDATA}})) .
            " tg " . $command->{TOGGLE} . 
            ($cDesc ? " $cDesc" : "");
}


###############################################################
# channel description or internal mod/chan text
sub PHC_ChannelDesc($$$)
{
    my ($hash, $command, $channel) = @_;
    my $name    = $hash->{NAME};
    my $mAdr    = $command->{ADR} & 0x1F;             # relative module address
    my $fmAdr   = sprintf('%02d', $mAdr);
    my $mType   = $command->{MTYPE};

    my $aName   = "channel" . PHC_ChannelText($hash, $command, $channel) . "description";
    my $bName   = PHC_ChannelText($hash, $command, $channel);    
    my $bitName = PHC_SanitizeReadingName(AttrVal($name, $aName, $bName));
    return $bitName;
}


###############################################################
# convert description into a usable reading name
sub PHC_SanitizeReadingName($) 
{
    my ($bitName) = @_;
    $bitName =~ s/ä/ae/g;
    $bitName =~ s/ö/oe/g;
    $bitName =~ s/ü/ue/g;
    $bitName =~ s/Ä/Ae/g;
    $bitName =~ s/Ö/Oe/g;
    $bitName =~ s/Ü/Ue/g;
    $bitName =~ s/ß/ss/g;
    $bitName =~ s/  / /g;
    $bitName =~ s/ -/-/g;
    $bitName =~ s/- /-/g;
    $bitName =~ s/ /_/g;
    $bitName =~ s/[^A-Za-z0-9\-]/_/g;
    $bitName =~ s/__/_/g;
    $bitName =~ s/__/_/g;
    return $bitName;
}


###########################################################
# return the name of the caling function for debug output
# todo: remove main from caller function
sub PHC_Caller() 
{
    my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller 2;
    return $1 if ($subroutine =~ /main::PHC_(.*)/);
    return $1 if ($subroutine =~ /main::(.*)/);
    return "$subroutine";
}


1;

=pod
=item device
=item summary retrieves events / readings from PHC bus and simulates input modules
=item summary_DE hört den PHC-Bus ab, erzeugt Events / Readings und simuliert EMDs
=begin html

<a name="PHC"></a>
<h3>PHC</h3>
<ul>
    PHC provides a way to communicate with the PHC bus from Peha. It listens to the communication on the PHC bus, tracks the state of output modules in readings and can send events to the bus / "Steuermodul" by simulating PHC input modules.<br>
    It can import the channel list file that is exportable from the Peha "Systemsoftware" to get names of existing modules and channels.<br>
    This module can not replace a Peha "Steuermodul". It is also not possible to directly send commands to output modules on the PHC bus. If you want to
    interact with output modules then you have to define the action on the Peha "Steuermodul" and send the input event to it through a virtual input module. <br>
    If you define a virtual input module then it needs to be given a unique address in the allowed range for input modules and this address must not be used by existing input modules.
    <br><br>
    
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
          This module requires the Perl modules Device::SerialPort or Win32::SerialPort and Digest::CRC.<br>
          To connect to the PHC bus it requires an RS485 adapter that connects directly to the PHC bus with GND, +data and -data.
        </li>
    </ul>
    <br>
    
    <a name="PHCDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; PHC &lt;Device&gt;</code><br>
        The module connects to the PHC bus with the specified device (RS485 adapter)<br>
        <br>
        Examples:<br>
        <br>
        <ul><code>define MyPHC PHC /dev/ttyRS485</code></ul><br>
    </ul>
    <br>

    <a name="PHCConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        The module doesn't need configuration to listen to the bus and create readings. <br>
        Only if you want to send input to the bus, you need to define a virtual input module with an address that is not used by real modules.<br>
        Virtual input modules and their channels are defined using attributes.<br>
        
        Example:<br>
        <pre>
        attr MyPHC virtEMD25C2Name VirtLightSwitch
        </pre>
        
        Defines a virtual light switch as channel 2 on the virtual input nodule with address 25. This light switch can then be used with set comands like 
        <pre>
        set MyPHC VirtualLightSwitch ein>0
        </pre>
        The set options offered here are the event types that PHC knows for input modules. They are ein>0, ein>1, ein>2, aus, aus<1. 
        To react on such events in the PHC system you need to add a reaction to the programming of your PHC control module.
    </ul>
    <br>
    
    <a name="PHCSet"></a>
    <b>Set-Commands</b><br>
    
    <ul>
        <li><b>importChannelList</b></li> 
            reads an xml file that is exportable by the Peha "Systemsoftware" that contains addresses and names of existing modules and channels on the PHC bus.<br>
            The path to the filename to import is relative to the Fhem base directory.<br>
            Example:<br>
            <pre>
            set MyPHC importChannelList Kanalliste.xml
            </pre>
            If Kanalliste.xml is located in /opt/fhem.<br>
        <br><br>
        more set options are created based on the attributes defining virtual input modules / channels<br>
        Every input channel for which an attribute like <code>virtEMDxyCcName</code> is defined will create a valid set option with name specified in the attribute.<br>
    </ul>
    <br>
    <a name="PHCGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        none so far
    </ul>
    <br>
    <a name="PHCattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>virtEMDxyCcName</b></li>
            Defines a virtual input module with a given address and a name for a channel of that input module.<br>
            For example:<br>
            <pre>
            attr MyPHC virtEMD25C1Name LivingRoomLightSwitch
            attr MyPHC virtEMD25C2Name KitchenLightSwitch
            </pre>
        <li><b>module[0-9]+description</b></li>
            this attribute is typically created when you import a channel list with <code>set MyPHCDevice importChannelList</code>.<br>
            It gives a name to a module. This name is used for better readability when logging at verbose level 4 or 5.
        <li><b>module[0-9]+type</b></li>
            this attribute is typically created when you import a channel list with <code>set MyPHCDevice importChannelList</code>.<br>
            It defines the type of a module. This information is needed since some module types (e.g. EMD and JRM) use the same address space but a different 
            protocol interpretation so parsing is only correct if the module type is known.
        <li><b>channel(EMD|AMD|JRM|DIM|UIM|MCC|MFN)[0-9]+[io]?[0-9]+description</b></li>
            this attribute is typically created when you import a channel list with <code>set MyPHCDevice importChannelList</code>.<br>
            It defines names for channels of modules. 
            These names are used for better readability when logging at verbose level 4 or 5.
            They also define the names of readings that are automatically created when the module listens to the PHC bus.
        <br>
    </ul>
	<br>
</ul>

=end html
=cut

