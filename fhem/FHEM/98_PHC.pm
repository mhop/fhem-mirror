##############################################################################
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
#   First version: 2017-02-11
#
# Todo / Ideas:
# =============
#
#   
#   Timer im STM von Fhem aus ändern?
#   Dimer setzen - zuerst DimProz in Byte 1, dann Zeit in Byte 2 wie bei heller / dunkler dimmen kodiert (Max 160)
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
# What does not work:
# ===================
#   AMD über Bus direkt ansprechen
#       Problem: keine Unterscheidung im Protokoll zwischen Befehlen vom STM und solchen von Modulen. Erst ACK ist Unterscheid
#       bei direktem Befehl meint STM dass es ein Feedback-Befeh ist. Die Acks überschneiden sich.
#       -> direktes Ansprechen von AMDs scheint nicht sinnvoll.
#       also Fhem als virtuelles EMD, STM soll dann AMDs ansprechen.
#   AMD in Fhem simulieren?
#       Fhem auf RPI viel zu langsam - erster Empfang enthält bereits 8 Resends vom STM bis Fhem überhaupt Befehl verarbeitet
#       insgesamt kommen 63 Resends ...
#

package PHC;

use strict;
use warnings;

use GPUtils         qw(:all);
use Time::HiRes     qw(gettimeofday);    
use Encode          qw(decode encode);
use SetExtensions   qw(:all);
use DevIo;
use FHEM::HTTPMOD::Utils qw(:all);

use Exporter ('import');
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (all => [@EXPORT_OK]);


BEGIN {
    GP_Import( qw(
        LoadModule
        parseParams
        CommandAttr
        CommandDeleteAttr
        addToDevAttrList
        AttrVal
        ReadingsVal
        ReadingsTimestamp
        readingsSingleUpdate
        readingsBeginUpdate
        readingsBulkUpdate
        readingsEndUpdate
        InternalVal
        makeReadingName
        DoTrigger

        Log3
        RemoveInternalTimer
        InternalTimer
        deviceEvents
        EvalSpecials
        AnalyzePerlCommand
        CheckRegexp

        gettimeofday
        FmtDateTime
        GetTimeSpec
        fhemTimeLocal
        time_str2num
        rtrim

        DevIo_OpenDev
        DevIo_SimpleWrite
        DevIo_SimpleRead
        DevIo_CloseDev
        SetExtensions

        featurelevel
        defs
        modules
        attr
        init_done
    ));

    GP_Export( qw(
        Initialize
    ));
};


my $Version = '0.70 - 8.3.2022';
    

my %AdrType = (
    0x00 => ['EMD'],            # Class 0 starts at 0x00      (EMD, ...)
    0x20 => ['MCC', 'UIM'],     # Class 1 starts at 0x20 / 32 (UIM, MCC, ...)
    0x40 => ['AMD', 'JRM'],     # Class 2 starts at 0x40 / 64 (AMD, JRM)
    0x60 => ['MFM'],            # Class 3 starts at 0x60 / 96 (MFM, ...) FUI = MFM
    0x80 => [],                 # Class 4 starts at 0x80 / 128 (?)
    0xA0 => ['DIM'],            # Class 5 starts at 0xA0 / 160 (DIM, ...)
    0xC0 => [],                 # ?
    0xE0 => ['CLK']             #
);


# number of bits to shift right for channel, &-Mask for function
my %CodeSplit = (
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
#   cbm Channel bits in command message
#   cba Channel bits in ack
#   cb2 2 Channel buts at the end of command message 
#   o   use name for output channel
#   i   use name for input channel
#   t1  time in data bytes 1+2
#   t2  time in data bytes 2+3, 4+5 and 6+7 if present
#   dt1 dim time in data byte 1 (coded) and data byte 2 is zero
#   dt2 dim time in data byte 2 (coded) and dim value (0-255) in data byte 1
#   p   priority information in data byte 1
#

# format: 'Type Function Len Acklen' => ['Function Name', Options]
#           Len=1 means just one byte for function/channel 
#                   e.g. a Frame with Adr, 81/01, Fkt/Chan CRC

my %functions = (
    'EMD02+01' => ['Ein > 0', 'i'],         # EMD, Function 2, Len flexible, AckLen 1
    'EMD03+01' => ['Aus < 1', 'i'],
    'EMD04+01' => ['Ein > 1', 'i'],
    'EMD05+01' => ['Aus > 1', 'i'],
    'EMD06+01' => ['Ein > 2', 'i'],
    'EMD07+01' => ['Aus', 'i'],
    
    'EMD020103' => ['LED_Ein', 'o'],
    'EMD030103' => ['LED_Aus', 'o'],
    
    'AMD010102' => ['Ping', 'cba'],
    'AMD020102' => ['Ein', 'cba', 'o'],
    'AMD030102' => ['Aus', 'cba', 'o'],
    'AMD040102' => ['An Lock', 'cba', 'o'],
    'AMD050102' => ['Aus Lock', 'cba', 'o'],
    'AMD060102' => ['Umschalten', 'cba', 'o'],
    'AMD070102' => ['Unlock', 'cba', 'o'],
    'AMD080302' => ['An verzögert', 'cba', 't1', 'o'],
    'AMD090302' => ['Aus verzögert', 'cba', 't1', 'o'],
    'AMD100302' => ['An mit Timer', 'cba', 't1', 'o'],
    'AMD110302' => ['Aus mit Timer', 'cba', 't1', 'o'],
    'AMD120302' => ['Umschalten verzögert', 'cba', 't1', 'o'],
    'AMD130302' => ['Umschalten mit Timer', 'cba', 't1', 'o'],
    'AMD140102' => ['Lock', 'cba', 'o'],
    'AMD150102' => ['Lock for time running', 'cba', 'o'],
    'AMD160302' => ['Timer Addieren', 'cba', 't1', 'o'],
    'AMD170302' => ['Timer setzen', 'cba', 't1', 'o'],
    'AMD180102' => ['Timer cancel', 'cba', 'o'],

    'AMD020201' => ['FB_Ein', 'cbm'],
    'AMD030201' => ['FB_Aus', 'cbm'],
    'AMD290201' => ['FB_Timer_Aus', 'cbm'],     # kommt nach F10 wenn Zeit abgelaufen ist todo: check aus mit timer feedback?
    
    'JRM020202' => ['Stop', 'o'],
    'JRM030402' => ['Umschalten heben stop', 'p', 't2', 'o'],
    'JRM040402' => ['Umschalten senken stop', 'p', 't2', 'o'],
    'JRM050402' => ['Heben', 'p', 't2', 'o'],
    'JRM060402' => ['Senken', 'p', 't2', 'o'],
    'JRM070402' => ['Flip auf', 'p', 't2', 'o'],
    'JRM080402' => ['Flip ab', 'p', 't2', 'o'],

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
    'JRM150602' => ['Sensor heben', 'p', 't2', 'o'],
    'JRM160802' => ['Sensor heben flip', 'p', 't2', 'o'],
    'JRM170602' => ['Sensor senken', 'p', 't2', 'o'],
    'JRM180802' => ['Sensor senken flip', 'p', 't2', 'o'],
    'JRM190302' => ['Zeitmessung verzögert an', 't1', 'o'],
    'JRM200302' => ['Zeitmessung verzögert aus', 't1', 'o'],
    'JRM210302' => ['Zeitmessung an mit Timer', 't1', 'o'],
    'JRM220102' => ['Zeitmessung cancel', 'o'],
    
    'DIM020102' => ['Ein Max mit Memory', 'cb2', 'o'],
    'DIM030102' => ['Ein Max ohne Memory', 'cb2', 'o'],
    'DIM040102' => ['Aus', 'cb2', 'o'],
    'DIM050102' => ['Umschalten Max mit Memory', 'cb2', 'o'],
    'DIM060102' => ['Umschalten Max ohne Memory', 'cb2', 'o'],
    'DIM070302' => ['Dimmen Gegenrichtung', 'cb2', 'dt1', 'o'],
    'DIM080302' => ['Heller Dimmen', 'cb2', 'dt1', 'o'],
    'DIM090302' => ['Dunkler Dimmen', 'cb2', 'dt1', 'o'],
    'DIM100102' => ['Speichern Memory', 'cb2', 'o'],
    'DIM110102' => ['Umschalten Memory', 'cb2', 'o'],
    'DIM120102' => ['Ein Memory', 'cb2', 'o'],
    'DIM130102' => ['Speichern DIA1', 'cb2'],
    'DIM140102' => ['Umschalten DIA1', 'cb2'],
    'DIM150102' => ['Ein DIA1', 'cb2'],
    'DIM160102' => ['Speichern DIA2', 'cb2'],
    'DIM170102' => ['Umschalten DIA2', 'cb2'],
    'DIM170302' => ['Umschalten DIA2', 'cb2'],      # mcp reported that both variants can be observed
    'DIM180102' => ['Ein DIA2', 'cb2'],
    'DIM190102' => ['Speichern DIA3', 'cb2'],
    'DIM200102' => ['Umschalten DIA3', 'cb2'],
    'DIM210102' => ['Ein DIA3', 'cb2'],
    'DIM220302' => ['Dimmwert und Zeit setzen', 'cb2', 'dt2'],
    
    'DIM020201' => ['FB_Ein'],
    'DIM030201' => ['FB_Aus'],
    
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
    'MFM060101' => ['unknown06'],
    'MFM070101' => ['unknown07'],
    'MFM080101' => ['unknown08'],
    'MFM090101' => ['unknown09'],
    'MFM100101' => ['Taste O Ein > 1', 'i'],
    'MFM110101' => ['Taste I Ein > 1', 'i'],
    'MFM130301' => ['unknown13-3-1'],
    
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
# called when module is loaded
sub Initialize {
    my $hash = shift;

    $hash->{ReadFn}  = \&ReadFn;
    $hash->{ReadyFn} = \&ReadyFn;
    $hash->{DefFn}   = \&DefineFn;
    $hash->{UndefFn} = \&UndefFn;
    $hash->{SetFn}   = \&SetFn;
    $hash->{GetFn}   = \&GetFn;
    $hash->{AttrFn}  = \&AttrFn;
          
    $hash->{AttrList}= "do_not_notify:1,0 " . 
        #"timeout " .
        "silentReconnect " .
        "sendEcho:1,0 " .
        "module[0-9]+description " .
        "module[0-9]+type " .
        "channel(EMD|AMD|JRM|DIM|UIM|MCC|MFM)[0-9]+[io]?[0-9]+description " .
        "channel(EMD|AMD|JRM|DIM|UIM|MCC|MFM)[0-9]+[o]?[0-9]+set " .
        "virtEMD[0-9]+C[0-9]+Name " .       # virtual emd channel for set
        "EMDReadings " .
        'HTTPMOD ' .
        'STM_ADR ' .
        "BusEvents:none,simple,long " .
        $main::readingFnAttributes;

    LoadModule "HTTPMOD";
    return;
}


############################################
# called by Fhem to define a device as PHC
sub DefineFn {
    my $hash = shift;                       # reference to device hash
    my $def  = shift;                       # definition string
    my @a    = split("[ \t]+", $def);       # split definition string
    my ($name, $PHC, $dev) = @a;            # device name, "PHC", RS485 interface path

    return "wrong syntax: define <name> PHC [devicename]" if(@a < 3);
        
    eval {use Digest::CRC qw(crc crc32 crc16 crcccitt)};
    if($@) {
        return "Please install the Perl Digest Library (apt-get install libdigest-crc-perl) - error was $@";
    }       
        
    $hash->{BUSY}          = 0;    
    $hash->{EXPECT}        = '';
    $hash->{ModuleVersion} = $Version;
    
    return if ($dev eq 'none');

    if ($dev !~ /.+@([0-9]+)/) {
        $dev .= '@19200,8,N,2';         # default baud rate
    } else {
        Log3 $name, 3, "$name: Warning: connection speed $1 is probably wrong for the PHC bus. Default is 19200,8,N,2"
            if ($1 != 19200);
    }

    $hash->{DeviceName}     = $dev;
    $hash->{devioLoglevel}  = (AttrVal($name, "silentReconnect", 0) ? 4 : 3);

    DevIo_CloseDev($hash);
    my $ret = DevIo_OpenDev($hash, 0, 0);
    return $ret;
}


#####################################
# called hen Fhem deletes a device
sub UndefFn {
    my $hash = shift;
    my $arg  = shift;
    my $name = $hash->{NAME};
    DevIo_CloseDev($hash); 
    return;
}


#####################################
# Attr command 
sub AttrFn {
    my $cmd   = shift;          # 'set' or 'del'
    my $name  = shift;          # device name
    my $aName = shift;          # attribute name
    my $aVal  = shift;          # attribute value
    my $hash  = $defs{$name};   # reference to the device hash

    Log3 $name, 5, "$name: Attr called with $cmd $name $aName $aVal";
    if ($cmd eq 'set') {
        if ($aName =~ m{\A virtEMD ([0-9]+) C ([0-9]+) Name \z}xms) {
            my $modAdr = $1;
            my $cnlAdr = $2;
            if ($modAdr >= 32) {
                return "illegal EMD module address $modAdr - address needs to be < 32 and it must not be used on the bus";
            }
            if ($cnlAdr >= 16) {
                return "illegal EMD channel address $cnlAdr - address needs to be < 16";
            }
            my @virtEMDList = grep { m{\A virtEMD [0-9]+ C [0-9]+ Name \z}xms} keys %{$attr{$name}};
            foreach my $attrName (@virtEMDList) {
                if ($aVal eq $attr{$name}{$attrName}) {     # ist es der im konkreten Attr verwendete Name?
                    if ($attrName ne $aName) {
                        return "Name $aVal is already used for virtual EMD $attrName";
                    }
                }            
            }            
        }
    }
    return;
}


#####################################
# get command
sub GetFn {
    my @getValArr = @_;                     # rest is optional values
    my $hash      = shift @getValArr;       # reference to device hash
    my $name      = shift @getValArr;       # device name
    my $getName   = shift @getValArr;       # get option name
    my $getVal    = join(' ', @getValArr);  # optional value after get name

    return "\"get $name\" needs at least one argument" if (!$getName);
    return;
}


#####################################
# switch toggle
sub DoToggle {
    my $hash   = shift;             # reference to Fhem device hash
    my $modAdr = shift;             # PHC module address
    my $name   = $hash->{NAME};     # Fhem device name    

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
    return;
}


#####################################################
# send PHC command
sub SendFrame {
    my $hash     = shift;           # reference to Fhem device hash
    my $modAdr   = shift;           # PHC module address
    my $hexCmd   = shift;           # combined function and channel as hex string
    my $name     = $hash->{NAME};   # Fhem device name

    Log3 $name, 5, "$name: SendFrame called with hexCmd $hexCmd for module $modAdr";
    DoToggle($hash, $modAdr);
            
    my $lUTog = (length ($hexCmd) / 2) | (($hash->{Toggle}{$modAdr} eq 's' ? 1 : 0) << 7);            
    my $frame = pack ('CCH*', $modAdr, $lUTog, $hexCmd);
    my $crc   = pack ('v', crc($frame, 16, 0xffff, 0xffff, 1, 0x1021, 1, 0));   
    $frame    = $frame . $crc;

    Log3 $name, 5, "$name: sends " . unpack ('H*', $frame);
    
    if (!AttrVal($name, "sendEcho", 0)) {
        my $now  = gettimeofday();
        $hash->{helper}{buffer} .= $frame;
        $hash->{helper}{lastRead} = $now;       
    }
    DevIo_SimpleWrite($hash, $frame, 0);
    return;
}


########################################################
# find PHC function in function hash
# to be called from DoEMD and setFn (new XMLRPC stuff)
sub FindFunction {
    my $hash     = shift;           # reference to Fhem device hash
    my $fName    = shift;           # input function name 
    my $mType    = shift // 'EMD';
    my $name     = $hash->{NAME};   # Fhem device name
    my $function = 0;
    $fName = '^' . lc($fName) . '$';            # input function name to be compared as regex
    $fName =~ s/(\s|_|&nbsp;|(\\xc2\\xa0))+/_*/g;  # function name with spaces as \s*
    
    FuncLOOP:                                   # look for entry in PHC functions parse information hash (ModuleFuncLenAcklen => Name, Options)
    foreach my $hkey (grep {m/^$mType/i} keys %functions) { 
        #Log3 $name, 5, "$name: FindFunction hkey $hkey";
        my $fn = lc $functions{$hkey}[0];       # function name in hash
        #Log3 $name, 5, "$name: FindFunction fn >$fn<";
        $fn =~ s/ //g;                          # function name without spaces
        $fn = $1 if ($fn =~ /(.*),.*/);         # strip anything in the name after a komma ... todo: is this necessary?
        Log3 $name, 5, "$name: FindFunction regex compare >$fn< to >$fName< ";
        if ($fn =~ $fName) {                    # is this the function name passed?
            Log3 $name, 4, "$name: FindFunction found function $fn as $hkey";
            return $hkey;
        }
    }
    Log3 $name, 4, "$name: FindFunction did not find function for $fName on $mType" if (!$function);
    return;
}


########################################################
# find possible PHC output functions per module type 
sub FindOutFunctions {
    my $hash     = shift;           # reference to Fhem device hash
    my $mType    = shift;
    my $name     = $hash->{NAME};   # Fhem device name
    my %fList;

    foreach my $hkey (grep {m/^$mType/i} keys %functions) { 
        my @opts = @{$functions{$hkey}};
        #Log3 $name, 5, "$name: FindOutFunctions: hkey $hkey, opts " . join (' ', @opts);
        my $fn = lc $functions{$hkey}[0];           # function name in hash
        $fn =~ s/\s/&nbsp;/g;                       # convert spaces for fhemweb
        #$fn =~ s/ /_/g;                            # function name without spaces
        if (grep {/^o$/} @opts) {
            $fList{$fn} = 1;
            #Log3 $name, 5, "$name: FindOutFunctions: match fn >$fn<";
        }
    }
    my @functions = keys %fList;
    Log3 $name, 5, "$name: FindOutFunctions: did find functions " . join (' ', @functions);
    return @functions;
}


#####################################################
# EMD aktion (mod, channel, function) simulieren 
# aufgerufen von set
sub DoEMD {
    my $hash     = shift;           # reference to Fhem device hash
    my $modAdr   = shift;           # PHC module address
    my $channel  = shift;           # channel number in module
    my $fName    = shift;           # input function name 
    my $name     = $hash->{NAME};   # Fhem device name

    Log3 $name, 3, "$name: DoEMD called for module $modAdr, channel $channel, function $fName";
    my $hKey = FindFunction($hash, $fName, 'EMD');
    return "function $fName not found" if (!$hKey);

    if ($hKey !~ /EMD([0-9][0-9]).*/i) {
        return "can not get function number for $hKey";
    }
    my $function = $1;
    my $code     = ($function + ($channel << 4));       # EMD commands are code without aditional data, len is always 1
    my $hexCmd   = unpack ('H2', pack ('C', $code));
    Log3 $name, 5, "$name: DoCmd: channel $channel, function $function => $code / $hexCmd";

    SendFrame($hash, $modAdr, $hexCmd);
    return;
}


#####################################################
# import PHC channel descriptions
sub DoImport {
    my $hash   = shift;
    my $setVal = shift;
    my $name   = $hash->{NAME};   # Fhem device name

    my $iFile;
    if (!open($iFile, "<", $setVal)) {
        Log3 $name, 3, "$name: Cannot open template file $setVal";
        return "Cannot open template file $setVal";
    };
    my $mType = 'unknown';
    my $mAdr  = 'unknown';
    my $aAdr  = 'unknown';
    my $mName = 'unknown';
    my $mDisp = 'unknown';
    my $cType = 'i';
    my $encoding = '';
    my ($key, $cAdr, $cName);
    while (<$iFile>) {
        my $line = $_;
        Log3 $name, 5, "$name: import read line $line";
        if ($line =~ /xml version.* encoding="([^\"]+)"/) {
            $encoding = $1;
            Log3 $name, 5, "$name: import encoding is $encoding";
            next;
        }
        $line = decode($encoding, $line) if ($encoding);

        if ($line =~ /^\s*<MOD\s/) {
            if ($line =~ /\sadr="([0-9]+)"\s/) {
                $aAdr  = sprintf('%03d', $1);
                $mAdr  = sprintf('%02d', $1 & 0x1f);
            }
            if ($line =~ /\sname="([^"]+)"/) {                        
                $mName = $1;
                $mType = substr($mName, 0, 3);
            }
            if ($line =~ /\sdisplay="([^"]+)"/) {
                $mDisp = encode ('UTF-8', $1);
            }
            CommandAttr(undef, "$name module${aAdr}description $mDisp");
            CommandAttr(undef, "$name module${aAdr}type $mType");
        } elsif ($line =~ /<OUT>/) {
            $cType = 'o';
        } elsif ($line =~ /<IN>/) {
            $cType = 'i';
        } elsif ($line =~ /^\s*<CHA\s/) {
            if ($line =~ /\sadr="([0-9]+)"/) {
                my $rAdr = $1 & 0x1f;
                $cAdr  = sprintf('%02d', $rAdr);
            }
            if ($line =~ /\sname="([^"]+)"/) {
                $cName = encode ('UTF-8', $1);
            }
            $key  = $mType . $mAdr . $cType . $cAdr; 
            CommandAttr(undef, "$name channel${key}description $cName");
        }
    }
    close $iFile;
    return;
}    


###################################################################
# call XML-RPC service via HTTPMOD
sub XMLRPC {
    my @args    = @_;
    my $hash    = shift @args;
    my $service = shift @args;
    my $name    = $hash->{NAME};
    my $hName   = AttrVal($name, 'HTTPMOD', '');    # which HTTPMOD to use? (url defined there)
    my $data    = "<methodCall> <methodName>$service</methodName> <params>";
    foreach my $arg (@args) {
        $data .= "<param><value><int>$arg</int></value></param>";       # for now only a list of ints
    }
    $data .= "</params> </methodCall>";
    Log3 $name, 4, "$name: XMLRPC called with $service and " . join (',', map {sprintf("0x%02X", $_)} @args);    
    Log3 $name, 5, "$name: XMLRPC data = $data";    
    if ($hName && $defs{$hName} && $defs{$hName}{TYPE} && $defs{$hName}{TYPE} eq "HTTPMOD") {
        HTTPMOD::AddToSendQueue($defs{$hName}, {'url' => $defs{$hName}{MainURL}, 'data' => $data, 'type' => 'external'});
    } else {
        Log3 $name, 3, "$name: XMLRPC does not have valid HTTPMOD device. Please set attr HTTPMOD to a device configured to your STM with port 6680";
    }
    return;
}


#################################################
# set an output via xmlrpc 
sub DoChannelSet {
    my $hash         = shift;
    my $modType      = shift;
    my $modAdr       = shift;
    my $modChannel   = shift;
    my $setVal       = shift;
    my $name         = $hash->{NAME};

    my $adrOffset    = 0;
    my $stmAdr       = AttrVal($name, 'STM_ADR', 0);
    my($args, $keys) = parseParams(lc($setVal));
    my $fName        = join ' ', @{$args};

    OFFLOOP:
    foreach my $off (keys %AdrType) {
        if (grep {/^$modType$/i} @{$AdrType{$off}}) {
            $adrOffset = $off;
            last OFFLOOP
        }
    }
    $modAdr += $adrOffset;                      # absolute address

    Log3 $name, 5, "$name: DoChannelSet called for direct output on $modType (offset $adrOffset), adr $modAdr, ch $modChannel, $fName";
    my $hKey = FindFunction($hash, $fName, $modType);
    return "function $fName not found" if (!$hKey);

    if ($hKey !~ /$modType([0-9][0-9]).*/i) {
        return "can not get function number for $hKey";
    }
    my $function = $1;

    my $split = $CodeSplit{uc($modType)};       # get number of bits to combine channel and function
    return "unknown module type $modType - can not use splitCode" if (!$split);
    my $cmdByte = ($modChannel << $split->[0]) + $function;

    my @parseOpts = @{$functions{$hKey}};
    Log3 $name, 5, "$name: function def = " . join ",", @parseOpts;

    shift @parseOpts;
    my %opts;
    foreach (@parseOpts) {$opts{$_} = 1};
    my @cmdOpts;

    if ($opts{'p'}) {
        my $prio = $keys->{prio} // 3;          # default prio 3
        return "illegal prio $prio" if ($prio > 7);
        $prio |= 0x40 if ($keys->{set});        # set priority?
        push @cmdOpts, $prio;       
    }        
    if ($opts{'t1'}||$opts{'t2'}) {
        my $time = $keys->{time} // 600;       # 60 secs as default
        return "illegal time $time" if ($time > 3000);
        my $t1 = int($time / 256);
        my $t2 = int($time) % 256;
        push @cmdOpts, $t2;                     # low byte
        push @cmdOpts, $t1;                     # high byte
    }
    if ($opts{'dt1'}) {
        my $time = $keys->{time} // 5;          # 5 secs as default
        return "illegal time $time" if ($time > 160);
        my $t1 = int($time * 25 / 16);
        push @cmdOpts, $t1;                     
        push @cmdOpts, 0;                     
    }
    if ($opts{'dt2'}) {
        my $value = $keys->{value} // 128;      # 128 as default (50%)
        my $time = $keys->{time} // 5;          # 5 secs as default
        return "illegal time $time" if ($time > 160);
        my $t1 = int($time * 25 / 16);
        push @cmdOpts, $value;
        push @cmdOpts, $t1;                     
    }

    XMLRPC($hash, 'service.stm.sendTelegram', $stmAdr, $modAdr, $cmdByte, @cmdOpts);
    return;
}


#####################################
# set comand
sub SetFn {
    my @setValArr = @_;                     # remainder is set values 
    my $hash      = shift @setValArr;       # reference to Fhem device hash
    my $name      = shift @setValArr;       # Fhem device name
    my $setName   = shift @setValArr;       # name of the set option
    my $setVal    = join(' ', @setValArr);  # set values as one string

    Log3 $name, 5, "$name: SetFn called from " . FhemCaller() . " with $setName and $setVal";

    return "\"set $name\" needs at least one argument" if(!$setName);
    
    if ($setName eq 'importChannelList') {
        if (!$setVal) {
            return 'please specify a filename';
        }
        return DoImport($hash, $setVal);
    } 
    elsif ($setName eq 'emd') {
        my @arg = @setValArr;
        shift @arg; 
        shift @arg;
        my $fName = lc join(' ', @arg);
        return DoEMD($hash, $setValArr[0], $setValArr[1], $fName);           
    } 
    elsif ($setName eq "sendRaw") {
        my $modAdr = unpack ('H2', $setValArr[0]);
        my $hexCmd = $setValArr[1];
        SendFrame($hash, $modAdr, $hexCmd);
    } 
    elsif ($setName =~ m{ (EMD|MCC|UIM|AMD|JRM|MFM|DIM) ([\d]+) o ([\d]+) }xmsi) {
        my $modType      = $1;
        my $modAdr       = $2;
        my $modChannel   = $3;
        return DoChannelSet($hash, $1, $2, $3, $setVal);     
    }
    else {    
        my @ChannelSetList = grep { m{channel (EMD|AMD|JRM|DIM|UIM|MCC|MFM) [0-9]+ [o]? [0-9]+ set}xms } keys %{$attr{$name}};
        my @setModHintList;
        Log3 $name, 5, "$name: check setName $setName against attrs " . join ",", @ChannelSetList if ($setName ne '?');
        foreach my $setAttr (@ChannelSetList) {
            if ($setAttr =~ m{channel (EMD|AMD|JRM|DIM|UIM|MCC|MFM) ([0-9]+) ([o]?) ([0-9]+) set}xms) {
                my $modType = $1;
                my $modAdr  = $2;
                my $o       = $3;
                my $chAdr   = $4;
                my $aName   = "channel$modType$modAdr$o$chAdr" . 'description';
                my $aVal    = SanitizeReadingName(lc($attr{$name}{$aName}));
                my $nameCmp = SanitizeReadingName(lc($setName));
                $nameCmp =~ s/ //g;                              # channel name without spaces
                Log3 $name, 5, "$name: compare $nameCmp with $aVal" if ($setName ne '?');
                if ($nameCmp eq $aVal) {                        
                    return DoChannelSet($hash, $modType, $modAdr, $chAdr, $setVal);     
                }
                push @setModHintList, $aVal . ':' . join (',', FindOutFunctions($hash, $modType));
            }            
        }
        my @virtEMDList = grep { m{virtEMD [0-9]+ C [0-9]+ Name}xms } keys %{$attr{$name}};
        foreach my $aName (@virtEMDList) {
            if (lc($setName) eq lc($attr{$name}{$aName})) {     # ist es der im konkreten Set verwendete setName?
                if ($aName =~ m{virtEMD ([0-9]+) C ([0-9]+) Name}xms) {
                    return DoEMD($hash, $1, $2, $setVal);     
                }
            }            
        }
        # todo: also take input functions from functions hash
        my $hints = "Unknown argument $setName, choose one of importChannelList sendRaw amd.*:ein,aus,umschalten" . 
            ' ' . join (' ', map { $attr{$name}{$_} . ':ein>0,ein>1,ein>2,aus,aus<1,aus>1' } @virtEMDList ) .
            ' ' . join (' ', @setModHintList);
        return $hints;
    }
    return;
}


###############################################################################
# Called from ParseCommands
# find out type of module at $command->{ADR}
# then split the code field into channel and function
# then search in functions hash for matching function and details / options
# set keys in command hash: MTYPE, CHANNEL, FUNCTION, FNAME, PARSEOPTS, CTYPE
#   
sub ParsePHCCode {
    my $hash    = shift;                # reference to Fhem device hash
    my $command = shift;                # reference to command hash containing ADR and CMD
    my $name    = $hash->{NAME};        # Fhem device name
    
    my $fAdr    = sprintf('%03d', $command->{ADR});                     # formatted abs module adr for attr lookup (mod type)
    my @typeArr = split (',', AttrVal($name, "module${fAdr}type", "")); # potential types from attr
    my $typeAttrLen = @typeArr;                                         # number of potential types in attr
    @typeArr    = @{$AdrType{$command->{ADR} & 0xE0}} if (!@typeArr);   # fallback to types from AdrType hash
    my $mType   = $typeArr[0];                                          # first option for split (same for all options)
    
    #Log3 $name, 5, "$name: ParseCode called, Adr $fAdr, typeArr = @typeArr, code " . sprintf ('x%02X', $command->{CODE});
    #Log3 $name, 5, "$name: ParseCode data = @{$command->{DATA}}";
    #Log3 $name, 5, "$name: ParseCode ackdata = @{$command->{ACKDATA}}";
    
    return 'unknown module type' if (!$mType);
    $command->{MTYPE} = $mType;                             # first idea unless we find a fit later
    
    # splitting and therefore channel and function are the same within one address class
    # so they are ok to calculate here regardless of the exact module type identified later
    my ($channel, $function) = SplitPHCCode($hash, $mType, $command->{CODE});
    $command->{CHANNEL} = $channel;
    $command->{FUNCTION} = $function;
    
    my $key1 = sprintf('%02d', $function);              # formatted function number
    my $key2 = sprintf('%02d', $command->{LEN});        # formatted LEN
    my $key3 = sprintf('%02d', $command->{ACKLEN});     # formatted ACKLEN
    my $wldk = '+';
    my @keys = ("$mType$key1$key2$key3", "$mType$key1$wldk$key3", "$mType$key1$key2", "$mType$key1");
    
    Log3 $name, 5, "$name: ParseCode for Adr $fAdr checks typelist @typeArr against" . 
            " Fkt=" . sprintf ('x%02X', $function) . " Ch=" . sprintf ('x%02X', $channel) . 
            " Len=$command->{LEN}, ackLen=$command->{ACKLEN}";

    my $bestFit = 0;                                        # any fit of key 3, 2 or 1 is better than 0
    TYPELOOP:
    foreach my $mTypePot (@typeArr) {
        #Log3 $name, 5, "$name: ParseCode checks if type of module at $fAdr can be $mTypePot";
        
        # does this module type match better than a previously tested type?
        my $idx = 4;                                        # four levels of abstraction in the functions hash
        FUNCLOOP:
        foreach my $key (@keys) {                           # four keys, one for each abstraction
            if ($functions{$key}) {
                #Log3 $name, 5, "$name: match: $key";
                if ($idx > $bestFit) {                      # longer = better matching type found
                    $bestFit = $idx;                        # save for next type
                    my @parseOpts = @{$functions{$key}};
                    $command->{MTYPE} = $mTypePot;
                    $command->{FNAME} = shift @parseOpts;
                    foreach (@parseOpts) {$command->{PARSEOPTS}{$_} = 1};
                    Log3 $name, 5, "$name: ParseCode match $key / $command->{FNAME} " . join (',', @parseOpts);
                }
                last FUNCLOOP;                               # first match is the best for this potential type
            } 
            if (!$idx) {    # this was the last try for this type with $idx=0, $key=$mTypePot$key1
                @typeArr = grep {!/$mTypePot/} @typeArr;    # module type is not an option any more
                Log3 $name, 5, "$name: ParseCode could not match to $mTypePot, delete this option";
                last FUNCLOOP;                              # not really necessary because at idx=0 FUNCLOOP is through anyway -> next TYPELOOP
            }
            $idx--;
        }   
    }
    Log3 $name, 4, "$name: ParseCode typelist after matching is @typeArr" if (@typeArr > 1);

    return 'no parse info' if (!$command->{FNAME});
    
    $command->{CTYPE} = ($command->{PARSEOPTS}{'i'} ? 'i' : 'o');
    
    if (!$typeAttrLen || (scalar(@typeArr) >= 1 && scalar(@typeArr) < $typeAttrLen)) {
        # no moduleType attr so far or we could eliminate an option -> set more specific new attr
        CommandAttr(undef, "$name module${fAdr}type " . join (',', @typeArr));
        #Log3 $name, 4, "$name: set attr $name module${fAdr}type " . join (',', @typeArr); 
    }
    return;
}


#####################################
# Called from ParseCommands
sub ParseOptions {
    my $hash    = shift;                # reference to Fhem device hash
    my $command = shift;                # reference to command hash containing ADR and CMD
    my $name    = $hash->{NAME};        # Fhem device name 
    my $dLen    = @{$command->{DATA}};  # length of Data
    
    if ($command->{PARSEOPTS}{'p'}) {   # priority in data[1]
        $command->{PRIO} = unpack ('b6', pack ('C', $command->{DATA}[1] & 0x3F));
        $command->{PSET} = $command->{DATA}[1] & 0x40;
    }
    
    if ($command->{PARSEOPTS}{'t1'}) {  # time in data[1] / data[2] (JRM)
        $command->{TIME1} = $command->{DATA}[1] + ($command->{DATA}[2] << 8) if ($dLen > 2);
    }
    
    if ($command->{PARSEOPTS}{'t2'}) {  # times in data[2/3] and data[4/5] ... if existant (JRM)
        $command->{TIME1} = $command->{DATA}[2] + ($command->{DATA}[3] << 8) if ($dLen > 3);
        $command->{TIME2} = $command->{DATA}[4] + ($command->{DATA}[5] << 8) if ($dLen > 5);
        $command->{TIME3} = $command->{DATA}[6] + ($command->{DATA}[7] << 8) if ($dLen > 7);
    }

    if ($command->{PARSEOPTS}{'dt1'}) {  # time in data[1], data[2]=0 (DIM)
        $command->{TIME1} = sprintf ('%.0f', $command->{DATA}[1]*16/25 + 0.1) if ($dLen > 2);
    }
    if ($command->{PARSEOPTS}{'dt2'}) {  # time in data[1], data[2]=0 (DIM)
        $command->{VALUE} = sprintf ('%.0f', $command->{DATA}[1]) if ($dLen > 2);
        $command->{TIME1} = sprintf ('%.0f', $command->{DATA}[2]*16/25 + 0.1) if ($dLen > 2);
    }

    return;
}


# todo: zumindest bei emds können mehrere codes (channel/function) nacheinender in einer message kommen
# wenn zwei tasten gleichzeitig gedrückt werden...

##########################################################################################
# Called from ParseFrames when a valid command frame and its ACK have been received
# all data is in $hash->{COMMAND}
# call ParsePHCCode to split code into channel / function, find function name and options
# call ParseOptions and then set readings / create events
sub ParseCommands {
    my $hash    = shift;                # reference to Fhem device hash
    my $command = shift;                # reference to command hash containing ADR and CMD
    my $name    = $hash->{NAME};        # Fhem device name
    
    my $err = ParsePHCCode($hash, $command) // '';
    ParseOptions($hash, $command) if (!$err);
    my $lvl = ($err ? 3 : ($command->{MTYPE} eq "CLK" ? 5:4));
    LogCommand($hash, $command, $err, $lvl);

    # todo: new mode to set on/off depending on command instead of bits in ack message 
    # to avoid multiple events when a group of outputs on the same module is switched
    # and every output creates a redundant event in every command 
    
    return if ($command->{MTYPE} eq "CLK");     # don't handle this noisy message

    my $busEvents   = AttrVal($name, "BusEvents", 'short');     # can be short, long or none
    my $longChName  = ChannelLongName($hash, $command, $command->{CHANNEL});
    my $shortChName = ChannelShortName($hash, $command, $command->{CHANNEL});
    my $cmd         = $command->{FNAME};
    my $event;
    if ($busEvents eq 'long') {
        $event = $longChName;
    } 
    elsif ($busEvents eq 'short') {
        $event = $shortChName;
    }   # if attr was set to none then $event stays undef
    if ($event) {
        $event .= ': ' . $cmd if ($cmd);
        DoTrigger($name, $event);
        Log3 $name, 5, "$name: ParseCommands create Event $event";
    }
    if (AttrVal($name, "EMDReadings", 0) && $command->{MTYPE} eq "EMD") {
        readingsSingleUpdate($hash, $longChName, $cmd, 0);                          # descriptive reading of EMD command using the long name of the input channel but don't trigger event here
        Log3 $name, 5, "$name: ParseCommands sets EMD reading $longChName to $cmd without event";
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'LastCommand', CmdDetailText($hash, $command));       # reading with full Log-Details of command

    # channel bits aus Feedback / Ack verarbeiten
    if ($command->{PARSEOPTS}{'cbm'} || $command->{PARSEOPTS}{'cba'}) {     # 8 channel bits in command message or in ACK
        my $bin = unpack ("B8", pack ("C", ($command->{PARSEOPTS}{'cbm'} ? $command->{DATA}[1] : $command->{ACKDATA}[1])));
        Log3 $name, 5, "$name: ParseCommands channel map = $bin";
        my $channelBit = 7;
        foreach my $c (split //, $bin) {
            my $bitName = ChannelLongName($hash, $command, $channelBit);
            Log3 $name, 5, "$name: ParseCommands sets reading $bitName for channel $channelBit to $c";
            readingsBulkUpdate($hash, $bitName, $c) if ($bitName);
            $channelBit --;
        }
    } 
    elsif ($command->{PARSEOPTS}{'cb2'}) {                                  # 2 channel bits in ACKData (last two) 
        my $bin = substr (unpack ("B8", pack ("C", $command->{ACKDATA}[1])), -2);
        Log3 $name, 5, "$name: ParseCommands channel map = $bin";
        my $channelBit = 1;
        foreach my $c (split //, $bin) {
            my $bitName = ChannelLongName($hash, $command, $channelBit);
            Log3 $name, 5, "$name: ParseCommands sets reading $bitName for channel $channelBit to $c";
            readingsBulkUpdate($hash, $bitName, $c) if ($bitName);
            $channelBit --;
        }
    }
    
    my @data = @{$command->{DATA}};
    if ($command->{PARSEOPTS}{'i'} && @data > 1) {                          # input with more data -> more commands
        my $codeIdx = 1;    # second code
        while ($codeIdx < @data) {
            Log3 $name, 5, "$name: ParseCommands now handles additional code at Index $codeIdx";
            $command->{CODE} = $data[$codeIdx];
            my $err = ParsePHCCode($hash, $command) // '';
            my $lvl = ($err ? 3 : 4);
            LogCommand($hash, $command, $err, $lvl);
            DoTrigger($name, ChannelShortName($hash, $command, $command->{CHANNEL}) . ": " . $command->{FNAME});
            $codeIdx++;
        }
        Log3 $name, 5, "$name: ParseCommands done";
    }
    
    readingsEndUpdate($hash, 1);
    return;
}


#####################################
# Called from the read functions
sub ParseFrames {
    my $hash  = shift;
    my $name  = $hash->{NAME};

    #Log3 $name, 5, "$name: Parseframes called";    
    use bytes;
    if (!$hash->{skipReason}) {
        $hash->{skipBytes}   = '';
        $hash->{skipReason}  = '';
    };
    
    BUFLOOP:
    while ($hash->{helper}{buffer}) {
    
        $hash->{RAWBUFFER} = unpack ('H*', $hash->{helper}{buffer});
        Log3 $name, 5, "$name: Parseframes: loop with raw buffer: $hash->{RAWBUFFER}" if (!$hash->{skipReason});
        
        my $rLen = length($hash->{helper}{buffer});
        return if ($rLen < 4);

        my ($adr, $lUTog, $rest) = unpack ('CCa*', $hash->{helper}{buffer});
        my $xAdr = unpack('H2', $hash->{helper}{buffer});
        my $tog  = $lUTog >> 7;         # toggle bit
        my $len  = $lUTog & 0x7F;       # length

        if ($len > 30) {
            #Log3 $name, 5, "$name: Parseframes: len > 30, skip first byte of buffer $hash->{RAWBUFFER}";
            $hash->{skipBytes}  .= substr ($hash->{helper}{buffer}, 0, 1);          # add, will be logged later
            $hash->{skipReason} .= ($hash->{skipReason} ? ', ' : '') . 'Len > 30';
            $hash->{helper}{buffer} = substr ($hash->{helper}{buffer}, 1);
            next BUFLOOP;
        }

        if (($rLen < 20) && ($rLen < $len + 4)) {
            Log3 $name, 5, "$name: Parseframes: len is $len so frame shoud be " . ($len + 4) . " but only $rLen read. wait for more";
            return;
        }        
        my $frame  = substr($hash->{helper}{buffer}, 0, $len + 2);  # the frame (adr, tog/len, cmd/data) without crc
        my $hFrame = unpack ('H*', $frame);
        
        # extract real pdu
        my ($pld, $crc, $rest2) = unpack ("a[$len]va*", $rest);     # v = little endian unsigned short, n would be big endian
        my @data  = unpack ('C*', $pld);
        $crc      = 0 if (!$crc);

        # calculate CRC
        my $crc1  = crc($frame, 16, 0xffff, 0xffff, 1, 0x1021, 1, 0);
        my $fcrc  = unpack ("H*", pack ("v", $crc));                # formatted crc as received
        my $fcrc1 = unpack ("H*", pack ("v", $crc1));               # formatted crc as calculated

        # check CRC
        if ($crc != $crc1) {
            my $skip = 1;
            #Log3 $name, 5, "$name: Parseframes: CRC error for $hFrame $fcrc, calc $fcrc1) - skip $skip bytes of buffer $hash->{RAWBUFFER}";
            $hash->{skipBytes}  .= substr ($hash->{helper}{buffer}, 0, $skip);
            $hash->{skipReason} .= ($hash->{skipReason} ? ', ' : '') . 'CRC Error';
            $hash->{helper}{buffer} = substr ($hash->{helper}{buffer}, $skip);
            next BUFLOOP;
        }
        Log3 $name, 4, "$name: Parseframes: skipped " . 
                unpack ("H*", $hash->{skipBytes}) . " reason: $hash->{skipReason}"
            if $hash->{skipReason};
            
        $hash->{skipBytes}   = '';
        $hash->{skipReason}  = '';
        $hash->{helper}{buffer} = $rest2;
        #Log3 $name, 5, "$name: Parseframes: Adr $adr/x$xAdr Len $len T$tog Data " . unpack ('H*', $pld) . " (Frame $hFrame $fcrc) Rest " . unpack ('H*', $rest2)
        Log3 $name, 5, "$name: Parseframes: Adr $adr/x$xAdr Len $len T$tog Data " . unpack ('H*', $pld) . " (Frame $hFrame $fcrc)"
            if ($adr != 224);   # todo: remove this filter later (hide noisy stuff)
        
        $hash->{Toggle}{$adr} = ($tog ? 's' : 'c');     # save toggle for potential own sending of data

        if ($hash->{COMMAND} && $hFrame eq $hash->{COMMAND}{FRAME}) {
            Log3 $name, 4, "$name: Parseframes: Resend of $hFrame $fcrc detected";
            next BUFLOOP;
        }   
        
        my $cmd = $data[0];
        
        if ($cmd == 1) {    # Ping / Ping response
            if ($hash->{COMMAND} && $hash->{COMMAND}{CODE} == 1 
                    && $hash->{COMMAND}{ADR} == $adr) {     # ping response
                # response to a previous ping
                Log3 $name, 5, "$name: Parseframes: Ping response received";
                $hash->{COMMAND}{ACKDATA} = \@data;
                $hash->{COMMAND}{ACKLEN} = $len;
                ParseCommands($hash, $hash->{COMMAND});
                delete $hash->{COMMAND};                    # done with this command
                next BUFLOOP;
            } 
            if (!$hash->{COMMAND}) {                        # new ping request
                Log3 $name, 5, "$name: Parseframes: Ping request received";
            } 
            else {
                Log3 $name, 4, "$name: Parseframes: new Frame $hFrame $fcrc but no ACK for valid last Frame $hash->{COMMAND}{FRAME} - dropping last one";
                delete $hash->{COMMAND};                    # done with this command
            }
            my @oldData = @data;    # save data in a new array that can be referenced by the command hash
            $hash->{COMMAND} = {CODE => $data[0], ADR => $adr, LEN => $len, TOGGLE => $tog, DATA => \@oldData, FRAME => $hFrame};
            next BUFLOOP;
        } 
        elsif ($cmd == 254) {                               # reset
            # todo: get module name / type and show real type / adr in Log, add to comand reading or go through ParseCommands with simulated acl len 0 ...
            # parse payload in parsecommand
            # por byte, many channel/ function bytes
            Log3 $name, 4, "$name: Parseframes: configuration request for adr $adr received - frame is $hFrame $fcrc";
            delete $hash->{COMMAND};   # done with this command
            next BUFLOOP;
        } 
        elsif ($cmd == 255) {                               # reset
            Log3 $name, 4, "$name: Parseframes: reset for adr $adr received - frame is $hFrame $fcrc";
            delete $hash->{COMMAND};   # done with this command
            next BUFLOOP;  
        } 
        elsif ($cmd == 0) {                                 # ACK received
            Log3 $name, 5, "$name: Parseframes: Ack received";
            if ($hash->{COMMAND}) {
                if ($hash->{COMMAND}{ADR} != $adr) {
                    Log3 $name, 4, "$name: Parseframes: ACK frame $hFrame $fcrc does not match adr of last Frame $hash->{COMMAND}{FRAME}";
                } 
                elsif ($hash->{COMMAND}{TOGGLE} != $tog) {
                    Log3 $name, 4, "$name: Parseframes: ACK frame $hFrame $fcrc does not match toggle of last Frame $hash->{COMMAND}{FRAME}";
                } 
                else {  # this ack is fine
                    $hash->{COMMAND}{ACKDATA} = \@data;
                    $hash->{COMMAND}{ACKLEN} = $len;
                    ParseCommands($hash, $hash->{COMMAND});
                }
                delete $hash->{COMMAND};                    # done with this command
            } 
            else {
                Log3 $name, 4, "$name: Parseframes: ACK frame $hFrame $fcrc without a preceeding request - dropping";
            }
            next BUFLOOP;
        } 
        else {                                              # normal command - no ack, ping etc.
            if ($hash->{COMMAND}) {
                Log3 $name, 4, "$name: Parseframes: new Frame $hFrame $fcrc but no ACK for valid last Frame $hash->{COMMAND}{FRAME} - dropping last one";
            } 
            Log3 $name, 5, "$name: Parseframes: $hFrame $fcrc is not an Ack frame, wait for ack to follow";
            my @oldData = @data;    # save data in a new array that can be referenced by the command hash
            $hash->{COMMAND} = {CODE => $data[0], ADR => $adr, LEN => $len, TOGGLE => $tog, DATA => \@oldData, FRAME => $hFrame};
            # todo: set timeout timer if not ACK received 
        }
    } # BUFLOOP
    return;
}


#####################################
# Called from the global loop, when the select for hash->{FD} reports data
sub ReadFn {
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
    
    ParseFrames($hash);
    return;
}


#####################################
sub ReadyFn {
    my $hash = shift;
    if ($hash->{STATE} eq "disconnected") {
        $hash->{devioLoglevel} = (AttrVal($hash->{NAME}, "silentReconnect", 0) ? 4 : 3);
        return DevIo_OpenDev($hash, 1, undef);
    }
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    return ($InBytes>0);
}


###############################################################
# split code into channel and function depending on module type
sub SplitPHCCode {
    my $hash  = shift;          # phc device hash ref
    my $mType = shift;          # module type (AMD, EMD, ...)
    my $code  = shift;          # code byte in protocol to be split into channel and function
    
    #Log3 $hash->{NAME}, 5, "$hash->{NAME}: SplitPHCCode called with code $code and type $mType";
    my @splitArr = @{$CodeSplit{$mType}};
    #Log3 $hash->{NAME}, 5, "$hash->{NAME}: SplitCode splits code " .
    #    sprintf ('%02d', $code) . " for type $mType into " .
    #    " channel " . ($code >> $splitArr[0]) . " / function " . ($code & $splitArr[1]);
    return ($code >> $splitArr[0], $code & $splitArr[1]);   # channel, function
}


###############################################################
# log message with command parse data
sub LogCommand {
    my ($hash, $command, $msg, $level) = @_;
    Log3 $hash->{NAME}, $level, "$hash->{NAME}: " . FhemCaller() . ' ' . CmdDetailText($hash, $command) . " $msg";
    return;
}


###############################################################
# get Text like EMD12i01
sub ChannelShortName {
    my $hash    = shift;        # device hash
    my $command = shift;        # reference to command hash with ADR, MTYPE, CTYPE
    my $channel = shift;        # channel number

    my $fmAdr = sprintf('%02d', ($command->{ADR} & 0x1F));      # relative module address formatted with two digits
    my $mType = $command->{MTYPE};

    my $cText = ($mType ? $mType . $fmAdr : 'Module' . sprintf ("x%02X", $command->{ADR})) .
            ($command->{CTYPE} ? $command->{CTYPE} : "?") .
            (defined($channel) ? sprintf('%02d', $channel) : "");
    #Log3 $hash->{NAME}, 5, "$hash->{NAME}: ChannelText is $cText";
    return $cText;
}


###############################################################
# channel description if attr is defined 
# or internal mod/chan text like EMD12i01
sub ChannelLongName {
    my $hash    = shift;                    # device hash
    my $command = shift;                    # reference to command hash with ADR, MTYPE, CTYPE
    my $channel = shift;                    # channel number
    my $name    = $hash->{NAME};            # Fhem device name 
    my $cName   = ChannelShortName($hash, $command, $channel);
    my $descr   = AttrVal($name, "channel${cName}description", '');
    my $bitName = SanitizeReadingName( $descr ? $descr : $cName);
    #Log3 $hash->{NAME}, 5, "$hash->{NAME}: ChannelDesc is looking for $aName or $cName, Result name is $bitName";
    return $bitName;
}


###############################################################
# full detail of a command for logging
sub CmdDetailText {
    my $hash    = shift;                    # device hash
    my $command = shift;                    # reference to command hash with ADR, MTYPE, CTYPE
    my $channel = $command->{CHANNEL};      # channel on PHC module
    my $cDesc   = ChannelLongName($hash, $command, $channel);   
    my $start   = ChannelShortName($hash, $command, $channel);
    return  ($start ? $start : "") . 
            (defined($command->{CHANNEL})  ? " Ch$command->{CHANNEL}" : "") .
            (defined($command->{FUNCTION}) ? " F$command->{FUNCTION}" : "") .
            ($command->{FNAME} ? " $command->{FNAME}" : "") .
            (defined($command->{PRIO}) ? " P$command->{PRIO}" : "") .
            (defined($command->{PRIO}) ? ($command->{PSET} ? " (Set)" : " (no Set)") : "") .
            (defined($command->{VALUE}) ? " Value $command->{VALUE}" : "") .
            (defined($command->{TIME1}) ? " Time1 $command->{TIME1}" : "") .
            (defined($command->{TIME2}) ? " Time2 $command->{TIME2}" : "") .
            (defined($command->{TIME3}) ? " Time3 $command->{TIME3}" : "") .
            " data " . join (",", map ({sprintf ("x%02X", $_)} @{$command->{DATA}})) .
            " ack " . join (",", map ({sprintf ("x%02X", $_)} @{$command->{ACKDATA}})) .
            " tg " . $command->{TOGGLE} . 
            ($cDesc ? " $cDesc" : "");
}


###############################################################
# convert description into a usable reading name
sub SanitizeReadingName {
    my $bitName = shift;
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


1;

=pod
=item device
=item summary retrieves events / readings from PHC bus and simulates input modules
=item summary_DE hört den PHC-Bus ab, erzeugt Events / Readings und simuliert EMDs
=begin html

<a id="PHC"></a>
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
    
    <a id="PHC-define"></a>
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

    <a id="PHC-configuration"></a>
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
    
    <a id="PHC-set"></a>
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
    <a id="PHC-get"></a>
    <b>Get-Commands</b><br>
    <ul>
        none so far
    </ul>
    <br>
    <a id="PHC-attr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        
        <li><a id="PHC-attr-BusEvents">BusEvents</a><br>
            this attribute controls what kind of events are generated when messages are received from the PHC bus regardless of any readings that might be created.
            If set to simple (which is the default) then short events like EMD12i01: Ein > 0 will be generated.
            If set to long then instead of EMD12i01 the module will use a name specified with a channel description attribue (see above).
            If set to none then no events will be created except the ones that result from readings that are created when output modules send their channel state.
        </li>
        <li><a id="PHC-attr-HTTPMOD">HTTPMOD</a><br>
            Name of an HTTPMOD-device which is defined as http://your-stm-ip:6680/ 0
        </li>
        <li><a id="STM_ADR">STM_ADR</a><br>
            Address of the control module (typically 0) to be used in the XMLRPC communication to directly set an output (STM Version 3 with ethernet connection only)
        </li>
        <li><a id="PHC-attr-EMDReadings">EMDReadings</a><br>
            if this attribute is set to 1 then the module will create readings for each input channel. 
            These readings will contain the last command received from an input, e.g. ein>0<br>
            These readings will not create events because by default any input message on the bus will create an event anyway (see BusEvents).
        </li>
        <li><a id="PHC-attr-sendEcho">sendEcho</a><br>
            controls if bus commands sent should be fed back to the read function.
        </li>
        <li><a id="PHC-attr-virtEMD[0-9]+C[0-9]+Name" data-pattern="virtEMD.*">virtEMD[0-9]+C[0-9]+Name</a>
            Defines a virtual input module with a given address and a name for a channel of that input module.<br>
            For example:<br>
            <pre>
            attr MyPHC virtEMD25C1Name LivingRoomLightSwitch
            attr MyPHC virtEMD25C2Name KitchenLightSwitch
            </pre>
        </li>
        <li><a id="PHC-attr-module[0-9]+description" data-pattern="module.*description">module[0-9]+description</a><br>
            this attribute is typically created when you import a channel list with <code>set MyPHCDevice importChannelList</code>.<br>
            It gives a name to a module. This name is used for better readability when logging at verbose level 4 or 5.
        </li>
        <li><a id="PHC-attr-module[0-9]+type" data-pattern="module.*type">module[0-9]+type</a><br>
            this attribute is typically created when you import a channel list with <code>set MyPHCDevice importChannelList</code>.<br>
            It defines the type of a module. This information is needed since some module types (e.g. EMD and JRM) use the same address space but a different 
            protocol interpretation so parsing is only correct if the module type is known.
        </li>
        <li><a id="PHC-attr-channel(EMD|AMD|JRM|DIM|UIM|MCC|MFN)[0-9]+[io]?[0-9]+description" 
            data-pattern="channel.*description">channel(EMD|AMD|JRM|DIM|UIM|MCC|MFN)[0-9]+[io]?[0-9]+description</a><br>
            this attribute is typically created when you import a channel list with <code>set MyPHCDevice importChannelList</code>.<br>
            It defines names for channels of modules. 
            These names are used for better readability when logging at verbose level 4 or 5.
            They also define the names of readings that are automatically created when the module listens to the PHC bus.
        </li>
        <li><a id="PHC-attr-channel(EMD|AMD|JRM|DIM|UIM|MCC|MFN)[0-9]+[io]?[0-9]+set" 
            data-pattern="channel.*set">channel(EMD|AMD|JRM|DIM|UIM|MCC|MFN)[0-9]+[io]?[0-9]+set</a><br>
            Only for STM version 3! This allows sending commands to output modules (so far tested with AMD, JRM or DIM) through the XML-RPC interface of a version 3 STM.
            To work this feature needs an HTTPMOD device which is defined as http://your-stm-ip:6680/ 0<br>
            The name of this HTTPMOD device then needs to be linked here via an attr named HTTPMOD.
        </li>
        <li><a id="PHC-attr-silentReconnect">silentReconnect</a><br>
            this attribute controls at what loglevel reconnect messages from devIO will be logged. Without this attribute they will be logged at level 3.
            If this attribute is set to 1 then such messages will be logged at level 4.
        </li>
        <br>
    </ul>
    <br>
</ul>

=end html
=cut


