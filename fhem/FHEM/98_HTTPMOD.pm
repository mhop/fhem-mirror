#########################################################################
# $Id$
# fhem Modul für Geräte mit Web-Oberfläche 
# wie z.B. Poolmanager Pro von Bayrol (PM5)
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
#   2013-12-25  initial version
#   2013-12-29  modified to use non blocking HTTP
#   2014-1-1    modified to use attr instead of set to define internal parameters
#   2014-1-6    extended error handling and added documentation 
#   2014-1-15   added readingsExpr to allow some computation on raw values before put in readings
#   2014-3-13   added noShutdown and disable attributes
#   2014-4-8    fixed noShutdown check
#   2014-4-9    added Attribute timeout as suggested by Frank
#   2014-10-22  added generic set function, alternative naming of old attributes, ...
#   2014-11-17  added queueing for requests, fixed timeout
#   2014-11-30  fixed race condition, added ignoreRedirects
#               an neues HttpUtils angepasst
#   2014-12-05  definierte Attribute werden zu userattr der Instanz hinzugefügt
#               use $hash->{HTTPHEADER} or $hash->{httpheader}
#   2014-12-22  Warnung in Set korrigiert
#   2015-02-11  added attributes for a generic get feature, new get function, attributes "map" for readings,
#               modified the map attributes handling so it works with strings containing blanks
#               and splits at ", " or ":"
#   2015-02-15  attribute to select readings per get
#   2015-02-17  new attributes getXXRegex, Map, Format, Expr, new semantics for default values of these attributes
#               restructured HTTPMOD_Read
#   2015-04-27  Integrated modification of jowiemann partially
#               settings: interval, reread, stop, start
#               DEVSTATE was not implemented because "disabled" is visible as attribute
#               and stopped / started is visible as TRIGGERTIME.
#               also the attribute disabled will not touch the internal timer.
#   2015-05-10  Integrated xpath extension as suggested in the forum
#   2015-06-22  added set[0-9]*NoArg and get[0-9]*URLExpr, get[0-9]*HeaderExpr and get[0-9]*DataExpr
#   2015-07-30  added set[0-9]*TextArg, Encode and Decode
#   2015-08-03  added get[0-9]*PullToFile (not fully implemented yet and not yet documented)
#   2015-08-24  corrected bug when handling sidIdRegex for step <> 1
#
#   Todo:       
#               multi page log extraction
#               generic cookie handling?
#
#
                    
package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    
use Encode qw(decode encode);
use HttpUtils;

sub HTTPMOD_Initialize($);
sub HTTPMOD_Define($$);
sub HTTPMOD_Undef($$);
sub HTTPMOD_Set($@);
sub HTTPMOD_Get($@);
sub HTTPMOD_Attr(@);
sub HTTPMOD_GetUpdate($);
sub HTTPMOD_Read($$$);
sub HTTPMOD_AddToQueue($$$$$;$$$);

#
# FHEM module intitialisation
# defines the functions to be called from FHEM
#########################################################################
sub HTTPMOD_Initialize($)
{
    my ($hash) = @_;

    $hash->{DefFn}   = "HTTPMOD_Define";
    $hash->{UndefFn} = "HTTPMOD_Undef";
    $hash->{SetFn}   = "HTTPMOD_Set";
    $hash->{GetFn}   = "HTTPMOD_Get";
    $hash->{AttrFn}  = "HTTPMOD_Attr";
    $hash->{AttrList} =
      "reading[0-9]+Name " .    # new syntax for readings
      "reading[0-9]+Regex " .
      "reading[0-9]*Expr " .
      "reading[0-9]*Map " .     # new feature
      "reading[0-9]*Format " .  # new feature
      "reading[0-9]*Decode " .  # new feature
      "reading[0-9]*Encode " .  # new feature
      
      "readingsName.* " .       # old syntax
      "readingsRegex.* " .
      "readingsExpr.* " .
     
      "requestHeader.* " .  
      "requestData.* " .
      "reAuthRegex " .
      "noShutdown:0,1 " .
      
      "timeout " .
      "queueDelay " .
      "queueMax " .
      "minSendDelay " .
      "showMatched:0,1 " .

      "sid[0-9]*URL " .
      "sid[0-9]*IDRegex " .
      "sid[0-9]*Data.* " .
      "sid[0-9]*Header.* " .
      "sid[0-9]*IgnoreRedirects " .
      
      "set[0-9]+Name " .
      "set[0-9]*URL " .
      "set[0-9]*Data.* " .
      "set[0-9]*Header.* " .
      "set[0-9]+Min " .
      "set[0-9]+Max " .
      "set[0-9]+Map " .         # Umwandlung von Codes für das Gerät zu sprechenden Namen, z.B. "0:mittig, 1:oberhalb, 2:unterhalb"
      "set[0-9]+Hint " .        # Direkte Fhem-spezifische Syntax für's GUI, z.B. "6,10,14" bzw. slider etc.
      "set[0-9]+Expr " .
      "set[0-9]*ReAuthRegex " .
      "set[0-9]*NoArg " .       # don't expect a value - for set on / off and similar.
      "set[0-9]*TextArg " .     # just pass on a raw text value without validation / further conversion
      
      "get[0-9]+Name " .
      "get[0-9]*URL " .
      "get[0-9]*Data.* " .
      "get[0-9]*Header.* " .

      "get[0-9]*URLExpr " .
      "get[0-9]*DatExpr " .
      "get[0-9]*HdrExpr " .

      "get[0-9]+Poll " .        # Todo: warum geht bei wildcards kein :0,1 Anhang ? -> in fhem.pl nachsehen
      "get[0-9]+PollDelay " .
      "get[0-9]*Regex " .
      "get[0-9]*Expr " .
      "get[0-9]*Map " .
      "get[0-9]*Format " .
      "get[0-9]*Decode " .
      "get[0-9]*Encode " .
      "get[0-9]*CheckAllReadings " .
      
      "get[0-9]*PullToFile " .
      "get[0-9]*PullIterate " .
      "get[0-9]*RecombineExpr " .
      
      "do_not_notify:1,0 " . 
      "disable:0,1 " .
      "enableControlSet:0,1 " .
      "enableXPath:0,1 " .
      "enableXPath-Strict:0,1 " .
      $readingFnAttributes;  
}

#
# Define command
# init internal values,
# set internal timer get Updates
#########################################################################
sub HTTPMOD_Define($$)
{
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "wrong syntax: define <name> HTTPMOD URL interval"
      if ( @a < 3 );
    my $name    = $a[0];

    if ($a[2] eq "none") {
        Log3 $name, 3, "$name: URL is none, no periodic updates will be limited to explicit GetXXPoll attribues (if defined)";
        $hash->{MainURL}    = "";
    } else {
        $hash->{MainURL}    = $a[2];
    }

    if(int(@a) > 3) { 
        if ($a[3] > 0) {
            if ($a[3] >= 5) {
                $hash->{Interval} = $a[3];
            } else {
                return "interval too small, please use something > 5, default is 300";
            }
        } else {
            Log3 $name, 3, "$name: interval is 0, no periodic updates will done.";
            $hash->{Interval} = 0;
        }
    } else {
        $hash->{Interval} = 300;
    }

    Log3 $name, 3, "$name: Defined with URL $hash->{MainURL} and interval $hash->{Interval}";

    # Initial request after 2 secs, for further updates the timer will be set according to interval.
    # but only if URL is specified and interval > 0
    if ($hash->{MainURL} && $hash->{Interval}) {
        my $firstTrigger = gettimeofday() + 2;
        $hash->{TRIGGERTIME}     = $firstTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);
        RemoveInternalTimer("update:$name");
        InternalTimer($firstTrigger, "HTTPMOD_GetUpdate", "update:$name", 0);
        Log3 $name, 5, "$name: InternalTimer set to call GetUpdate in 2 seconds for the first time";
    } else {
       $hash->{TRIGGERTIME} = 0;
       $hash->{TRIGGERTIME_FMT} = "";
    }
    return undef;
}

#
# undefine command when device is deleted
#########################################################################
sub HTTPMOD_Undef($$)
{                     
    my ( $hash, $arg ) = @_;       
    my $name = $hash->{NAME};
    RemoveInternalTimer ("timeout:$name");
    RemoveInternalTimer ("queue:$name"); 
    RemoveInternalTimer ("update:$name"); 
    return undef;                  
}    


#
# Attr command 
#########################################################################
sub
HTTPMOD_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};        # might be needed inside a URLExpr
    my ($sid, $old);                # might be needed inside a URLExpr
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    # simple attributes like requestHeader and requestData need no special treatment here
    # readingsExpr, readingsRegex.* or reAuthRegex need validation though.
    
    if ($cmd eq "set") {        
        if ($aName =~ "Regex") {    # catch all Regex like attributes
            eval { qr/$aVal/ };
            if ($@) {
                Log3 $name, 3, "$name: Attr with invalid regex in attr $name $aName $aVal: $@";
                return "Invalid Regex $aVal";
            }
        } elsif ($aName =~ "Expr") { # validate all Expressions
            my $val = 1;
            no warnings qw(uninitialized);
            eval $aVal;
            if ($@) {
                Log3 $name, 3, "$name: Attr with invalid Expression in attr $name $aName $aVal: $@";
                return "Invalid Expression $aVal";
            }
        } elsif ($aName eq "enableXPath") {
            if(!eval("use HTML::TreeBuilder::XPath;1")) {
                Log3 $name, 3, "$name: Please install HTML::TreeBuilder::XPath to use the xpath-Option";
                return "Please install HTML::TreeBuilder::XPath to use the xpath-Option";
            }
        } elsif ($aName eq "enableXPath-Strict") {
            if(!eval("use XML::XPath;use XML::XPath::XMLParser;1")) {
                Log3 $name, 3, "$name: Please install XML::XPath and XML::XPath::XMLParser to use the xpath-strict-Option";
                return "Please install XML::XPath and XML::XPath::XMLParser to use the xpath-strict-Option";
            }
        }
        addToDevAttrList($name, $aName);
    }
    return undef;
}


# create a new authenticated session
#########################################################################
sub HTTPMOD_Auth($@)
{
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};

    # get all steps
    my %steps;
    foreach my $attr (keys %{$attr{$name}}) {
        if ($attr =~ "sid([0-9]+).+") {
            $steps{$1} = 1;
        }
    }
    Log3 $name, 4, "$name: Auth called with Steps: " . join (" ", sort keys %steps);

    $hash->{sid} = "";
    foreach my $step (sort keys %steps) {
    
        my ($url, $header, $data, $type, $retrycount, $ignoreredirects);
        # hole alle Header bzw. generischen Header ohne Nummer 
        $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/sid${step}Header/, keys %{$attr{$name}})));
        if (length $header == 0) {
            $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/sidHeader/, keys %{$attr{$name}})));
        }
        # hole Bestandteile der Post Data
        $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/sid${step}Data/, keys %{$attr{$name}})));
        if (length $data == 0) {
            $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/sidData/, keys %{$attr{$name}})));
        }
        # hole URL
        $url = AttrVal($name, "sid${step}URL", undef);
        if (!$url) {
            $url = AttrVal($name, "sidURL", undef);
        }
        $ignoreredirects = AttrVal($name, "sid${step}IgnoreRedirects", undef);
        $retrycount      = 0;
        $type            = "Auth$step";
        if ($url) {
            HTTPMOD_AddToQueue($hash, $url, $header, $data, $type, $retrycount, $ignoreredirects);
        } else {
            Log3 $name, 3, "$name: no URL for $type";
        }
    }
    return undef;
}


# put URL, Header, Data etc. in hash for HTTPUtils Get
# for set with index $setNum
#########################################################################
sub HTTPMOD_DoSet($$$)
{
    my ($hash, $setNum, $rawVal) = @_;
    my $name = $hash->{NAME};
    my ($url, $header, $data, $type, $count);
    
    # hole alle Header bzw. generischen Header ohne Nummer 
    $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/set${setNum}Header/, keys %{$attr{$name}})));
    if (length $header == 0) {
        $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/setHeader/, keys %{$attr{$name}})));
    }
    # hole Bestandteile der Post data 
    $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/set${setNum}Data/, keys %{$attr{$name}})));
    if (length $data == 0) {
        $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/setData/, keys %{$attr{$name}})));
    }
    # hole URL
    $url = AttrVal($name, "set${setNum}URL", undef);
    if (!$url) {
        $url = AttrVal($name, "setURL", undef);
    }
    if (!$url) {
        $url = $hash->{MainURL};
    }
    
    # ersetze $val in header, data und URL
    $header =~ s/\$val/$rawVal/g;
    $data   =~ s/\$val/$rawVal/g;
    $url    =~ s/\$val/$rawVal/g;
 
    $type = "Set$setNum";

    if ($url) {
        HTTPMOD_AddToQueue($hash, $url, $header, $data, $type); 
    } else {
        Log3 $name, 3, "$name: no URL for $type";
    }
    
    return undef;
}


#
# SET command
#########################################################################
sub HTTPMOD_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set HTTPMOD\" needs at least an argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, setName and setVal
    my ($name, $setName, $setVal) = @a;
    my (%rmap, $setNum, $setOpt, $setList, $rawVal);
    $setList = "";

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: set called with $setName but device is disabled"
            if ($setName ne "?");
        return undef;
    }
    
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "")
        if ($setName ne "?");

    if (AttrVal($name, "enableControlSet", undef)) {        # spezielle Sets freigeschaltet?
        $setList = "interval reread:noArg stop:noArg start:noArg ";
        if ($setName eq 'interval') {
            if (int $setVal > 5) {
                $hash->{Interval} = $setVal;
                my $nextTrigger = gettimeofday() + $hash->{Interval};
                RemoveInternalTimer("update:$name");    
                $hash->{TRIGGERTIME} = $nextTrigger;
                $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
                InternalTimer($nextTrigger, "HTTPMOD_GetUpdate", "update:$name", 0);
                Log3 $name, 3, "$name: timer interval changed to $hash->{Interval} seconds";
                return undef;
            } elsif (int $setVal <= 5) {
                Log3 $name, 3, "$name: interval $setVal (sec) to small (must be >5), continuing with $hash->{Interval} (sec)";
            } else {
                Log3 $name, 3, "$name: no interval (sec) specified in set, continuing with $hash->{Interval} (sec)";
            }
        } elsif ($setName eq 'reread') {
            HTTPMOD_GetUpdate("reread:$name");
            return undef;
        } elsif ($setName eq 'stop') {
            RemoveInternalTimer("update:$name");    
            $hash->{TRIGGERTIME} = 0;
            $hash->{TRIGGERTIME_FMT} = "";
            Log3 $name, 3, "$name: internal interval timer stopped";
            return undef;
        } elsif ($setName eq 'start') {
            my $nextTrigger = gettimeofday() + $hash->{Interval};
            $hash->{TRIGGERTIME} = $nextTrigger;
            $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
            RemoveInternalTimer("update:$name");
            InternalTimer($nextTrigger, "HTTPMOD_GetUpdate", "update:$name", 0);
            Log3 $name, 5, "$name: internal interval timer set to call GetUpdate in " . int($hash->{Interval}). " seconds";
            return undef;
        } 
    }
        
    # verarbeite Attribute "set[0-9]*Name  set[0-9]*URL  set[0-9]*Data.*  set[0-9]*Header.* 
    # set[0-9]*Min  set[0-9]*Max  set[0-9]*Map  set[0-9]*Expr   set[0-9]*Hint
    
    # Vorbereitung:
    # suche den übergebenen setName in den Attributen, setze setNum und erzeuge rmap falls gefunden
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ "set([0-9]+)Name") {      # ist das Attribut ein "setXName" ?
            my $setI  = $1;                     # merke die Nummer im Namen
            my $iName = $attr{$name}{$aName};   # Name der Set-Option diser Schleifen-Iteration
            
            if ($setName eq $iName) {           # ist es der im konkreten Set verwendete setName?
                $setNum = $setI;                # gefunden -> merke Nummer X im Attribut
            }
            
            # erzeuge setOpt für die Rückgabe bei set X ?
            if (AttrVal($name, "set${setI}Map", undef)) {               # nochmal: gibt es eine Map (für Hint)
                my $hint = AttrVal($name, "set${setI}Map", undef);      # create hint from map
                $hint =~ s/([^ ,\$]+):([^ ,\$]+,?) ?/$2/g;
                $setOpt = $iName . ":$hint";                            # setOpt ist Name:Hint (aus Map)
            } else {
                $setOpt = $iName;                                       # nur den Namen für setopt verwenden.
            }
            if (AttrVal($name, "set${setI}Hint", undef)) {              # gibt es einen expliziten Hint?
                $setOpt = $iName . ":" . 
                AttrVal($name, "set${setI}Hint", undef);
            }
            $setList .= $setOpt . " ";      # speichere Liste mit allen Sets inkl. der Hints nach ":" für Rückgabe bei Set ?
        }
    }
    
    # gültiger set Aufruf? ($setNum oben schon gesetzt?)
    if(!defined ($setNum)) {
        return "Unknown argument $setName, choose one of $setList";
    } 
    Log3 $name, 5, "$name: set found option $setName in attribute set${setNum}Name";

    if (!AttrVal($name, "set${setNum}NoArg", undef)) {      # soll überhaupt ein Wert übergeben werden?
        if (!defined($setVal)) {                            # Ist ein Wert übergeben?
            Log3 $name, 3, "$name: set without value given for $setName";
            return "no value given to set $setName";
        }

        # Eingabevalidierung von Sets mit Definition per Attributen
        # 1. Schritt, falls definiert, per Umkehrung der Map umwandeln (z.B. Text in numerische Codes)
        if (AttrVal($name, "set${setNum}Map", undef)) {     # gibt es eine Map?
            my $rm = AttrVal($name, "set${setNum}Map", undef);
            #$rm =~ s/([^ ,\$]+):([^ ,\$]+),? ?/$2 $1 /g;           # reverse map string erzeugen
            $rm =~ s/([^, ][^,\$]*):([^, ][^,\$]*),? ?/$2:$1, /g;   # reverse map string erzeugen
            %rmap = split (/, +|:/, $rm);                           # reverse hash aus dem reverse string                   
            if (defined($rmap{$setVal})) {                  # Eintrag für den übergebenen Wert in der Map?
                $rawVal = $rmap{$setVal};                   # entsprechender Raw-Wert für das Gerät
                Log3 $name, 5, "$name: set found $setVal in rmap and converted to $rawVal";
            } else {
                Log3 $name, 3, "$name: set value $setVal did not match defined map";
                return "set value $setVal did not match defined map";
            }
        } else {
            # wenn keine map, dann wenigstens sicherstellen, dass Wert numerisch - falls nicht TextArg.
            if (!AttrVal($name, "set${setNum}TextArg", undef)) {     
                if ($setVal !~ /^-?\d+\.?\d*$/) {
                    Log3 $name, 3, "$name: set - value $setVal is not numeric";
                    return "set value $setVal is not numeric";
                }
            }
            $rawVal = $setVal;
        }
        
        if (!AttrVal($name, "set${setNum}TextArg", undef)) {     
            # 2. Schritt: falls definiert Min- und Max-Werte prüfen - falls kein TextArg
            if (AttrVal($name, "set${setNum}Min", undef)) {
                my $min = AttrVal($name, "set${setNum}Min", undef);
                Log3 $name, 5, "$name: is checking value $rawVal against min $min";
                return "set value $rawVal is smaller than Min ($min)"
                    if ($rawVal < $min);
            }
            if (AttrVal($name, "set${setNum}Max", undef)) {
                my $max = AttrVal($name, "set${setNum}Max", undef);
                Log3 $name, 5, "$name: set is checking value $rawVal against max $max";
                return "set value $rawVal is bigger than Max ($max)"
                    if ($rawVal > $max);
            }
        }

        # 3. Schritt: Konvertiere mit setexpr falls definiert
        if (AttrVal($name, "set${setNum}Expr", undef)) {
            my $val = $rawVal;
            my $exp = AttrVal($name, "set${setNum}Expr", undef);
            $rawVal = eval($exp);
            Log3 $name, 5, "$name: set converted value $val to $rawVal using expr $exp";
        }
        
        Log3 $name, 4, "$name: set will now set $setName -> $rawVal";
        my $result = HTTPMOD_DoSet($hash, $setNum, $rawVal);
        return "$setName -> $rawVal";
    } else {
        Log3 $name, 4, "$name: set will now set $setName";
        HTTPMOD_DoSet($hash, $setNum, 0);
        return $setName;
    }
    
}



# put URL, Header, Data etc. in hash for HTTPUtils Get
# for get with index $getNum
#########################################################################
sub HTTPMOD_DoGet($$)
{
    my ($hash, $getNum) = @_;
    my $name = $hash->{NAME};
    my ($url, $header, $data, $type, $count);
    my $seq = $hash->{GetSeq};
    
    # hole alle Header bzw. generischen Header ohne Nummer 
    $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/get${getNum}Header/, keys %{$attr{$name}})));
    if (length $header == 0) {
        $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/getHeader/, keys %{$attr{$name}})));
    }
    if (AttrVal($name, "get${getNum}HdrExpr", undef)) {
        my $exp = AttrVal($name, "get${getNum}HdrExpr", undef);
        my $old = $header;
        $header = eval($exp);
        Log3 $name, 5, "$name: get converted the header $old\n to $header\n using expr $exp";
    }   
    
    # hole Bestandteile der Post data 
    $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/get${getNum}Data/, keys %{$attr{$name}})));
    if (length $data == 0) {
        $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/getData/, keys %{$attr{$name}})));
    }
    if (AttrVal($name, "get${getNum}DatExpr", undef)) {
        my $exp = AttrVal($name, "get${getNum}DatExpr", undef);
        my $old = $data;
        $data = eval($exp);
        Log3 $name, 5, "$name: get converted the post data $old\n to $data\n using expr $exp";
    }   

    # hole URL
    $url = AttrVal($name, "get${getNum}URL", undef);
    if (!$url) {
        $url = AttrVal($name, "getURL", undef);
    }
    if (AttrVal($name, "get${getNum}URLExpr", undef)) {
        my $exp = AttrVal($name, "get${getNum}URLExpr", undef);
        my $old = $url;
        $url = eval($exp);
        Log3 $name, 5, "$name: get converted the url $old to $url using expr $exp";
    }   
    if (!$url) {
        $url = $hash->{MainURL};
    }
    
    $type = "Get$getNum";

    if ($url) {
        HTTPMOD_AddToQueue($hash, $url, $header, $data, $type); 
    } else {
        Log3 $name, 3, "$name: no URL for $type";
    }
    
    return undef;
}


#
# GET command
#########################################################################
sub HTTPMOD_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"get HTTPMOD\" needs at least an argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, getName
    my ($name, $getName) = @a;
    my ($getNum, $getList);
    $hash->{GetSeq} = 0;
    $getList = "";

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: get called with $getName but device is disabled"
            if ($getName ne "?");
        return undef;
    }
    
    Log3 $name, 5, "$name: get called with $getName "
        if ($getName ne "?");

    # verarbeite Attribute "get[0-9]*Name  get[0-9]*URL  get[0-9]*Data.*  get[0-9]*Header.* 
    
    # Vorbereitung:
    # suche den übergebenen getName in den Attributen, setze getNum falls gefunden
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ "get([0-9]+)Name") {      # ist das Attribut ein "getXName" ?
            my $getI  = $1;                     # merke die Nummer im Namen
            my $iName = $attr{$name}{$aName};   # Name der get-Option diser Schleifen-Iteration
            
            if ($getName eq $iName) {           # ist es der im konkreten get verwendete getName?
                $getNum = $getI;                # gefunden -> merke Nummer X im Attribut
            }
            $getList .= $iName . " ";           # speichere Liste mit allen gets für Rückgabe bei get ?
        }
    }
    
    # gültiger get Aufruf? ($getNum oben schon gesetzt?)
    if(!defined ($getNum)) {
        return "Unknown argument $getName, choose one of $getList";
    } 
    Log3 $name, 5, "$name: get found option $getName in attribute get${getNum}Name";
    Log3 $name, 4, "$name: get will now request $getName";

    my $result = HTTPMOD_DoGet($hash, $getNum);
    return "$getName requested, watch readings";
}



#
# request new data from device
###################################
sub HTTPMOD_GetUpdate($)
{
    my ($calltype,$name) = split(':', $_[0]);
    my $hash = $defs{$name};
    my ($url, $header, $data, $type, $count);
    my $now = gettimeofday();
    
    Log3 $name, 4, "$name: GetUpdate called ($calltype)";
    
    if ($calltype eq "update" && $hash->{Interval}) {
        RemoveInternalTimer ("update:$name");
        my $nt = gettimeofday() + $hash->{Interval};
        $hash->{TRIGGERTIME}     = $nt;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nt);
        InternalTimer($nt, "HTTPMOD_GetUpdate", "update:$name", 0);
        Log3 $name, 5, "$name: internal interval timer set to call GetUpdate again in " . int($hash->{Interval}). " seconds";
    }
    
    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: GetUpdate called but device is disabled";
        return undef;
    }
    
    if ( $hash->{MainURL} ne "none" ) {
        $url    = $hash->{MainURL};
        $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestHeader/, keys %{$attr{$name}})));
        $data   = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestData/, keys %{$attr{$name}})));
        $type   = "Update";
        
        # queue main get request 
        if ($url) {
            HTTPMOD_AddToQueue($hash, $url, $header, $data, $type); 
        } else {
            Log3 $name, 3, "$name: no URL for $type";
        }
    }

    # check if additional readings with individual URLs need to be requested
    foreach my $poll (sort grep (/^get[0-9]+Poll$/, keys %{$attr{$name}})) {
        $poll =~ /^get([0-9]+)Poll$/;
        next if (!$1);
        my $getNum  = $1;
        my $getName = AttrVal($name, "get".$getNum."Name", ""); 
        if ($getName) {
            Log3 $name, 5, "$name: GetUpdate checks if poll required for $getName ($getNum)";
            my $lastPoll = 0;
            $lastPoll = $hash->{lastpoll}{$getName} 
                if ($hash->{lastpoll} && $hash->{lastpoll}{$getName});
            my $dueTime = $lastPoll + AttrVal($name, "get".$getNum."PollDelay", 0);
            if ($now >= $dueTime) {
                Log3 $name, 5, "$name: GetUpdate will request $getName";
                $hash->{lastpoll}{$getName} = $now;
                
                # hole alle Header bzw. generischen Header ohne Nummer 
                $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/get${getNum}Header/, keys %{$attr{$name}})));
                if (length $header == 0) {
                    $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/getHeader/, keys %{$attr{$name}})));
                }
                # hole Bestandteile der Post data 
                $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/get${getNum}Data/, keys %{$attr{$name}})));
                if (length $data == 0) {
                    $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/getData/, keys %{$attr{$name}})));
                }
                # hole URL
                $url = AttrVal($name, "get${getNum}URL", undef);
                if (!$url) {
                    $url = AttrVal($name, "getURL", undef);
                }
                if (!$url) {
                    $url = $hash->{MainURL} if ( $hash->{MainURL} ne "none" );
                }

                $type    = "Get$getNum";
                if ($url) {
                    HTTPMOD_AddToQueue($hash, $url, $header, $data, $type); 
                } else {
                    Log3 $name, 3, "$name: no URL to get $type";
                }
            } else {
                Log3 $name, 5, "$name: GetUpdate will skip $getName, delay not over";
            }
        }
    }
}


# extract one reading for a buffer
# and apply Expr, Map and Format
###################################
sub HTTPMOD_ExtractReading($$$$$$$$$)
{
    my ($hash, $buffer, $reading, $regex, $expr, $map, $format, $decode, $encode) = @_;
    my $name = $hash->{NAME};
    my $val  = "";
    my $match;

    if (AttrVal($name, "enableXPath", undef) && $regex =~ /^xpath:(.*)/) {
        Log3 $name, 5, "$name: ExtractReading $reading with xpath $1 ...";
        my $xpath = $1;
        my $tree  = HTML::TreeBuilder::XPath->new;
        my $html  = $buffer;
        $html =~ s/.*?(\r\n){2}//s; # remove HTTP-header
            
        # if the xpath isn't syntactically correct, fhem would crash
        # the use of eval prevents this from happening
        $val = eval('
            $tree->parse($html);
            $val = join ",", $tree->findvalues($xpath);
            $tree->delete();
            $val;
        ');
        $match = $val;
    } elsif (AttrVal($name, "enableXPath-Strict", undef) && $regex =~ /^xpath-strict:(.*)/) {
        Log3 $name, 5, "$name: ExtractReading $reading with strict xpath $1 ...";
        my $xpath = $1;
        my $xml= $buffer;
        $xml =~ s/.*?(\r\n){2}//s; # remove HTTP-header
        
        # if the xml isn't wellformed, fhem would crash
        # the use of eval prevents this from happening
        $val = eval('
            my $xp = XML::XPath->new(xml => $xml);
            my $nodeset = $xp->find($xpath);
            my @vals;
            foreach my $node ($nodeset->get_nodelist) {
                push @vals, XML::XPath::XMLParser::as_string($node);
            }
            $val = join ",", @vals;
            $xp->cleanup();
            $val;
        ');
        $match = $val;
    } else {
        Log3 $name, 5, "$name: ExtractReading $reading with regex /$regex/...";
        $match = ($buffer =~ /$regex/);
        $val = $1 if ($match);
    }
    
    if ($match) {

        $val = decode($decode, $val) if ($decode);
        $val = encode($encode, $val) if ($encode);
        
        if ($expr) {
            $val = eval $expr;
            Log3 $name, 5, "$name: ExtractReading changed $reading with Expr $expr from $1 to $val";
        }
        
        if ($map) {                                 # gibt es eine Map?
            my %map = split (/, +|:/, $map);        # hash aus dem map string                   
            if (defined($map{$val})) {              # Eintrag für den gelesenen Wert in der Map?
                my $nVal = $map{$val};              # entsprechender sprechender Wert für den rohen Wert aus dem Gerät
                Log3 $name, 5, "$name: ExtractReading found $val in map and converted to $nVal";
                $val = $nVal;
            } else {
                Log3 $name, 3, "$name: ExtractReading cound not match $val to defined map";
            }
        }
        
        if ($format) {
            Log3 $name, 5, "$name: ExtractReading for $reading does sprintf with format " . $format .
                " value is $val";
            $val = sprintf($format, $val);
            Log3 $name, 5, "$name: ExtractReading for $reading sprintf result is $val";
        }
        
        Log3 $name, 5, "$name: ExtractReading sets $reading to $val";
        readingsBulkUpdate( $hash, $reading, $val );
        return 1;
    } else {
        Log3 $name, 5, "$name: ExtractReading $reading did not match (val is >$val<)";
        return 0;
    }
}


# get attribute based specification
# for format, map or similar
# with generic default (empty variable part)
#############################################
sub HTTPMOD_GetFAttr($$$$)
{
    my ($name, $prefix, $num, $type) = @_;
    my $val = "";
    if (defined ($attr{$name}{$prefix . $num . $type})) {
          $val = $attr{$name}{$prefix . $num . $type};
    } elsif 
       (defined ($attr{$name}{$prefix . $type})) {
          $val = $attr{$name}{$prefix . $type};
    }
    return $val;
}



#
# read / parse new data from device
# - callback for non blocking HTTP 
###################################
sub HTTPMOD_Read($$$)
{
    my ($hash, $err, $buffer) = @_;
    my $name    = $hash->{NAME};
    my $request = $hash->{REQUEST};
    my $type    = $request->{type};
    
    $hash->{BUSY} = 0;
    RemoveInternalTimer ($hash); # Remove remaining timeouts of HttpUtils (should be done in HttpUtils)
    
    $hash->{HTTPHEADER} = "" if (!$hash->{HTTPHEADER});
    $hash->{httpheader} = "" if (!$hash->{httpheader});
    my $header = $hash->{HTTPHEADER} . $hash->{httpheader};
    
    if ($err) {
        Log3 $name, 3, "$name: Read callback: request type was $type" . 
             ($header ? ",\r\nheader: $header" : ", no headers") . 
             ($buffer ? ",\r\nbuffer: $buffer" : ", buffer empty") . 
             ($err ? ", \r\nError $err" : "");
        return;
    }
    
    Log3 $name, 5, "$name: Read Callback: Request type was $type" .
             ($header ? ",\r\nheader: $header" : ", no headers") . 
             ($buffer ? ",\r\nbuffer: $buffer" : ", buffer empty");
    
    
    $buffer = $header . "\r\n\r\n" . $buffer if ($header);
    
    $type =~ "(Auth|Set|Get)(.*)";
    my $num = $2;
    
    if ($type =~ "Auth") {
        # Doing Authentication step -> extract sid
        my $idRegex = HTTPMOD_GetFAttr($name, "sid", $num, "IDRegex");
        if ($idRegex) {
            if ($buffer =~ $idRegex) {
                $hash->{sid} = $1;
                Log3 $name, 5, "$name: Read set sid to $hash->{sid}";
            } else {
                Log3 $name, 5, "$name: Read could not match buffer to IDRegex $idRegex";
            }
        }
        return undef;
    } else {
        # not in Auth, so check if Auth is necessary
        my $ReAuthRegex;
        if ($type =~ "Set") {
            $ReAuthRegex = AttrVal($name, "set${num}ReAuthRegex", AttrVal($name, "setReAuthRegex", undef));
        } else {
            $ReAuthRegex = AttrVal($name, "reAuthRegex", undef);
        }
        if ($ReAuthRegex) {
            Log3 $name, 5, "$name: Read is checking response with ReAuthRegex $ReAuthRegex";
            if ($buffer =~ $ReAuthRegex) {
                Log3 $name, 4, "$name: Read decided new authentication required";
                if ($request->{retryCount} < 1) {
                    HTTPMOD_Auth $hash;
                    $request->{retryCount}++;
                    Log3 $name, 4, "$name: Read is requeuing request $type after Auth, retryCount $request->{retryCount} ...";
                    HTTPMOD_AddToQueue ($hash, $request->{url}, $request->{header}, 
                            $request->{data}, $request->{type}, $request->{retryCount}); 
                    return undef;
                } else {
                    Log3 $name, 4, "$name: Read has no more retries left - did authentication fail?";
                }
            }
        }
    }
    
    return undef if ($type =~ "Set");
    
    my $checkAll  = 0;  
    my $unmatched = "";
    my $matched   = "";
    my ($reading, $regex, $expr, $map, $format, $encode, $decode, $pull);
    readingsBeginUpdate($hash);
    
    if ($type =~ "Get") {
        $checkAll = AttrVal($name, "get" . $num . "CheckAllReadings", 0);
        $reading  = $attr{$name}{"get" . $num . "Name"};
        $regex    = HTTPMOD_GetFAttr($name, "get", $num, "Regex");
        #Log3 $name, 5, "$name: Read is extracting Reading with $regex from HTTP Response to $type";
        if (!$regex) {
            $checkAll = 1;
        } else {
            $expr    = HTTPMOD_GetFAttr($name, "get", $num, "Expr");
            $map     = HTTPMOD_GetFAttr($name, "get", $num, "Map");
            $format  = HTTPMOD_GetFAttr($name, "get", $num, "Format");
            $decode  = HTTPMOD_GetFAttr($name, "get", $num, "Decode");
            $encode  = HTTPMOD_GetFAttr($name, "get", $num, "Encode");
            $pull    = HTTPMOD_GetFAttr($name, "get", $num, "PullToFile");

            if ($pull) {
                Log3 $name, 5, "$name: Read is pulling to file, sequence is $hash->{GetSeq}";
                my $iterate   = HTTPMOD_GetFAttr($name, "get", $num, "PullIterate");
                my $matches = 0;
                while ($buffer =~ /$regex/g) {
                    my $recombine = HTTPMOD_GetFAttr($name, "get", $num, "RecombineExpr");
                    no warnings qw(uninitialized);
                    $recombine = '$1' if not ($recombine);
                    my $val = eval($recombine);
                    Log3 $name, 3, "$name: Read pulled line $val";
                    $matched = $reading;
                    $matches++;                 
                }
                Log3 $name, 3, "$name: Read pulled $matches lines";
                if ($matches) {
                    if ($iterate && $hash->{GetSeq} < $iterate) {
                        $hash->{GetSeq}++;                  
                        Log3 $name, 5, "$name: Read is iterating pull until $iterate, next is $hash->{GetSeq}";
                        HTTPMOD_DoGet($hash, $num);
                    } else {
                        Log3 $name, 5, "$name: Read is done with pull after $hash->{GetSeq}.";
                    }
                } else {
                    Log3 $name, 5, "$name: Read is done with pull, no more lines matched";
                }
            } elsif (HTTPMOD_ExtractReading($hash, $buffer, $reading, $regex, $expr, $map, $format, $decode, $encode)) {
                $matched = ($matched ? "$matched $reading" : "$reading");
            } else {
                $unmatched = ($unmatched ? "$unmatched $reading" : "$reading");
            }
        }
    }
    
    if (($type eq "Update") || ($checkAll)) {
        Log3 $name, 5, "$name: Read starts extracting all Readings from HTTP Response to $type";
        foreach my $a (sort (grep (/readings?[0-9]*Name/, keys %{$attr{$name}}))) {
            if (($a =~ /readingsName(.*)/) && defined ($attr{$name}{'readingsName' . $1}) 
                  && defined ($attr{$name}{'readingsRegex' . $1})) {
                # old syntax
                $reading = AttrVal($name, 'readingsName'  . $1, "");
                $regex   = AttrVal($name, 'readingsRegex' . $1, "");
                $expr    = AttrVal($name, 'readingsExpr'  . $1, "");
            } elsif(($a =~ /reading([0-9]+)Name/) && defined ($attr{$name}{"reading${1}Name"}) 
                  && defined ($attr{$name}{"reading${1}Regex"})) {
                # new syntax
                $reading = AttrVal($name, "reading${1}Name", "");
                $regex   = AttrVal($name, "reading${1}Regex", "");
                $expr    = HTTPMOD_GetFAttr($name, "reading", $1, "Expr");
                $map     = HTTPMOD_GetFAttr($name, "reading", $1, "Map");
                $format  = HTTPMOD_GetFAttr($name, "reading", $1, "Format");
                $decode  = HTTPMOD_GetFAttr($name, "reading", $1, "Decode");
                $encode  = HTTPMOD_GetFAttr($name, "reading", $1, "Encode");
            } else {
                Log3 $name, 3, "$name: Read found inconsistant attributes for $a";
                next;
            }
            if (HTTPMOD_ExtractReading($hash, $buffer, $reading, $regex, $expr, $map, $format, $decode, $encode)) {
                $matched = ($matched ne "" ? "$matched $reading" : "$reading");
            } else {
                $unmatched = ($unmatched ne "" ? "$unmatched $reading" : "$reading");
            }
        }
    }
    if ($type =~ "(Update|Get)") {
        if (!$matched) {
            readingsBulkUpdate( $hash, "MATCHED_READINGS", "")
                if (AttrVal($name, "showMatched", undef));
            Log3 $name, 3, "$name: Read response to $type didn't match any Reading(s)";
        } else {
            readingsBulkUpdate( $hash, "MATCHED_READINGS", $matched)
                if (AttrVal($name, "showMatched", undef));
            Log3 $name, 4, "$name: Read response to $type matched Reading(s) $matched";
            Log3 $name, 4, "$name: Read response to $type did not match $unmatched" if ($unmatched);
        }
    }
    readingsEndUpdate( $hash, 1 );
    HTTPMOD_HandleSendQueue("direct:".$name);
    return undef;
}



#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit $direct:$name
sub
HTTPMOD_HandleSendQueue($)
{
  my (undef,$name) = split(':', $_[0]);
  my $hash  = $defs{$name};
  my $queue = $hash->{QUEUE};
  
  my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
  Log3 $name, 5, "$name: HandleSendQueue called, qlen = $qlen";
  RemoveInternalTimer ("queue:$name");
  
  if(defined($queue) && @{$queue} > 0) {
  
    my $queueDelay  = AttrVal($name, "queueDelay", 1);  
    my $now = gettimeofday();
  
    if (!$init_done) {      # fhem not initialized, wait with IO
      InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
      Log3 $name, 3, "$name: HandleSendQueue - init not done, delay sending from queue";
      return;
    }
    if ($hash->{BUSY}) {  # still waiting for reply to last request
      InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
      Log3 $name, 5, "$name: HandleSendQueue - still waiting for reply to last request, delay sending from queue";
      return;
    }

    $hash->{REQUEST} = $queue->[0];

    if($hash->{REQUEST}{url} ne "") {    # if something to send - check min delay and send
        my $minSendDelay = AttrVal($hash->{NAME}, "minSendDelay", 0.2);

        if ($hash->{LASTSEND} && $now < $hash->{LASTSEND} + $minSendDelay) {
            InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
            Log3 $name, 5, "$name: HandleSendQueue - minSendDelay not over, rescheduling";
            return;
        }   
        
        $hash->{BUSY}      = 1;         # HTTPMOD queue is busy until response is received
        $hash->{LASTSEND}  = $now;      # remember when last sent
        $hash->{redirects} = 0;
        $hash->{callback}  = \&HTTPMOD_Read;
        $hash->{url}       = $hash->{REQUEST}{url};
        $hash->{header}    = $hash->{REQUEST}{header};
        $hash->{data}      = $hash->{REQUEST}{data};     
        $hash->{timeout}   = AttrVal($name, "timeout", 2);
        $hash->{ignoreredirects} = $hash->{REQUEST}{ignoreredirects};
      
        if (AttrVal($name, "noShutdown", undef)) {
            $hash->{noshutdown} = 1;
        } else {
            delete $hash->{noshutdown};
        };

        if ($hash->{sid}) {
            $hash->{header} =~ s/\$sid/$hash->{sid}/g;
            $hash->{data}   =~ s/\$sid/$hash->{sid}/g;
            $hash->{url}    =~ s/\$sid/$hash->{sid}/g;
        }
        
        Log3 $name, 4, "$name: HandleSendQueue sends request type $hash->{REQUEST}{type} to " .
                        "URL $hash->{url}, data $hash->{data}, header $hash->{header}, timeout $hash->{timeout}";
        HttpUtils_NonblockingGet($hash);
    }
    shift(@{$queue});           # remove first element from queue
    if(@{$queue} > 0) {         # more items in queue -> schedule next handle 
        InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
    }
  }
}



#####################################
sub
HTTPMOD_AddToQueue($$$$$;$$$){
    my ($hash, $url, $header, $data, $type, $count, $ignoreredirects, $prio) = @_;
    my $name = $hash->{NAME};

    $count           = 0 if (!$count);
    $ignoreredirects = 0 if (!$ignoreredirects);
    
    my %request;
    $request{url}             = $url;
    $request{header}          = $header;
    $request{data}            = $data;
    $request{type}            = $type;
    $request{retryCount}      = $count;
    $request{ignoreredirects} = $ignoreredirects;
    
    my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
    Log3 $name, 5, "$name: AddToQueue called, initial send queue length : $qlen";
    Log3 $name, 5, "$name: AddToQueue adds type $request{type} to " .
            "URL $request{url}, data $request{data}, header $request{header}";
    if(!$qlen) {
        $hash->{QUEUE} = [ \%request ];
    } else {
        if ($qlen > AttrVal($name, "queueMax", 20)) {
            Log3 $name, 3, "$name: AddToQueue - send queue too long, dropping request";
        } else {
            if ($prio) {
                unshift (@{$hash->{QUEUE}}, \%request); # an den Anfang
            } else {
                push(@{$hash->{QUEUE}}, \%request);     # ans Ende
            }
        }
    }
    HTTPMOD_HandleSendQueue("direct:".$name);
}


1;

=pod
=begin html

<a name="HTTPMOD"></a>
<h3>HTTPMOD</h3>

<ul>
    This module provides a generic way to retrieve information from devices with an HTTP Interface and store them in Readings. 
    It queries a given URL with Headers and data defined by attributes. 
    From the HTTP Response it extracts Readings named in attributes using Regexes also defined by attributes. <br>
    In an advanced configuration the module can also send information to devices. To do this a generic set option can be configured using attributes.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This Module uses the non blocking HTTP function HttpUtils_NonblockingGet provided by FHEM's HttpUtils in a new Version published in December 2013.<br>
            If not already installed in your environment, please update FHEM or install it manually using appropriate commands from your environment.<br>
        </li>
        
    </ul>
    <br>

    <a name="HTTPMODdefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; HTTPMOD &lt;URL&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the given URL every Interval seconds, sends optional headers and data and then parses the response<br>
        <br>
        Example:<br>
        <br>
        <ul><code>define PM HTTPMOD http://MyPoolManager/cgi-bin/webgui.fcgi 60</code></ul>
    </ul>
    <br>

    <a name="HTTPMODconfiguration"></a>
    <b>Configuration of HTTP Devices</b><br><br>
    <ul>
        Specify optional headers as <code>attr requestHeader1</code> to <code>attr requestHeaderX</code>, <br>
        optional POST data as <code>attr requestData</code> and then <br>
        pairs of <code>attr readingXName</code> and <code>attr readingXRegex</code> to define which readings you want to extract from the HTTP
        response and how to extract them. (The old syntax <code>attr readingsNameX</code> and <code>attr readingsRegexX</code> is still supported 
        but the new one with <code>attr readingXName</code> and <code>attr readingXRegex</code> should be preferred.
        <br><br>
        Example for a PoolManager 5:<br><br>
        <ul><code>
            define PM HTTPMOD http://MyPoolManager/cgi-bin/webgui.fcgi 60<br>
            attr PM reading01Name PH<br>
            attr PM reading01Regex 34.4001.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM reading02Name CL<br>
            attr PM reading02Regex 34.4008.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM reading03Name3TEMP<br>
            attr PM reading03Regex 34.4033.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM requestData {"get" :["34.4001.value" ,"34.4008.value" ,"34.4033.value", "14.16601.value", "14.16602.value"]}<br>
            attr PM requestHeader1 Content-Type: application/json<br>
            attr PM requestHeader2 Accept: */*<br>
            attr PM stateFormat {sprintf("%.1f Grad, PH %.1f, %.1f mg/l Chlor", ReadingsVal($name,"TEMP",0), ReadingsVal($name,"PH",0), ReadingsVal($name,"CL",0))}<br>
        </code></ul>
        <br>
        If you need to do some calculation on a raw value before it is used as a reading, you can define the attribute <code>readingXExpr</code> 
        which can use the raw value from the variable $val
        <br><br>
        Example:<br><br>
        <ul><code>
            attr PM reading03Expr $val * 10<br>
        </code></ul>


        <br><br>
        <b>Advanced configuration to define a <code>set</code> or <code>get</code> and send data to a device</b>
        <br><br>
        
        When a set option is defined by attributes, the module will use the value given to the set command and translate it into an HTTP-Request that sends the value to the device. <br><br>
        Extension to the above example for a PoolManager 5:<br><br>
        <ul><code>
            attr PM set01Name HeizungSoll <br>
            attr PM set01URL http://MyPoolManager/cgi-bin/webgui.fcgi?sid=$sid <br>
            attr PM set01Hint 6,10,20,30 <br>
            attr PM set01Min 6 <br>
            attr PM set01Max 30 <br>
            attr PM setHeader1 Content-Type: application/json <br>
            attr PM set01Data {"set" :{"34.3118.value" :"$val" }} <br>
        </code></ul>
        <br>
        This example defines a set option with the name HeizungSoll. <br>
        By issuing <code>set PM HeizungSoll 10</code> in FHEM, the value 10 will be sent in the defined HTTP
        Post to URL <code>http://MyPoolManager/cgi-bin/webgui.fcgi</code> in the Post Data as <br>
        <code>{"set" :{"34.3118.value" :"10" }}</code><br>
        The optional attributes set01Min and set01Max define input validations that will be checked in the set function.<br>
        the optional attribute set01Hint will define a selection list for the Fhemweb GUI.<br><br>

        When a get option is defined by attributes, the module allows querying additional values from the device that require 
        individual HTTP-Requests or special parameters to be sent<br><br>
        Extension to the above example:<br><br>
        <ul><code>
            attr PM get01Name MyGetValue <br>
            attr PM get01URL http://MyPoolManager/cgi-bin/directory/webgui.fcgi?special=1?sid=$sid <br>
            attr PM getHeader1 Content-Type: application/json <br>
            attr PM get01Data {"get" :{"30.1234.value"}} <br>
        </code></ul>
        <br>
        This example defines a get option with the name MyGetValue. <br>
        By issuing <code>get PM MyGetValue</code> in FHEM, the defined HTTP request is sent to the device.<br>
        The HTTP response is then parsed using the same readingXXName and readingXXRegex attributes as above so
        additional pairs will probably be needed there for additional values.<br><br>
        
        If the new get parameter should also be queried regularly, you can define the following optional attributes:<br>
        <ul><code>
            attr PM get01Poll 1<br>
            attr PM get01PollDelay 300<br>
        </code></ul>
        <br>

        The first attribute includes this reading in the automatic update cycle and the second defines an
        alternative lower update frequency. When the interval defined initially is over and the normal readings
        are read from the device, the update function will check for additional get parameters that should be included
        in the update cycle.
        If a PollDelay is specified for a get parameter, the update function also checks if the time passed since it has last read this value 
        is more than the given PollDelay. If not, this reading is skipped and it will be rechecked in the next cycle when 
        interval is over again. So the effective PollDelay will always be a multiple of the interval specified in the initial define.
        
        <br><br>
        <b>Advanced configuration to create a valid session id that might be necessary in set options</b>
        <br><br>
        when sending data to an HTTP-Device in a set, HTTPMOD will replace any <code>$sid</code> in the URL, Headers and Post data with the internal <code>$hash->{sid}</code>. To authenticate towards the device and give this internal a value, you can use an optional multi step login procedure defined by the following attributes: <br>
        <ul>
        <li>sid[0-9]*URL</li>
        <li>sid[0-9]*IDRegex</li>
        <li>sid[0-9]*Data.*</li>
        <li>sid[0-9]*Header.*</li>
        </ul><br>
        Each step can have a URL, Headers, Post Data pieces and a Regex to extract a resulting Session ID into <code>$hash->{sid}</code>.<br>
        HTTPMOD will create a sorted list of steps (the numbers between sid and URL / Data / Header) and the loop through these steps and send the corresponding requests to the device. For each step a $sid in a Header or Post Data will be replaced with the current content of <code>$hash->{sid}</code>. <br>
        Using this feature, HTTPMOD can perform a forms based authentication and send user name, password or other necessary data to the device and save the session id for further requests. <br><br>
        
        To determine when this login procedure is necessary, HTTPMOD will first try to do a set without 
        doing the login procedure. If the Attribute reAuthRegex is defined, it will then compare the HTTP Response to the set request with the regular expression from reAuthRegex. If it matches, then a 
        login is performed. The reAuthRegex is meant to match the error page a device returns if authentication or reauthentication is required e.g. because a session timeout has expired. <br><br>
        
        If for one step not all of the URL, Data or Header Attributes are set, then HTTPMOD tries to use a 
        <code>sidURL</code>, <code>sidData.*</code> or <code>sidHeader.*</code> Attribue (without the step number after sid). This way parts that are the same for all steps don't need to be defined redundantly. <br><br>
        
        Example for a multi step login procedure: 
        <br><br>
        
        <ul><code>
            attr PM sidURL http://192.168.70.90/cgi-bin/webgui.fcgi?sid=$sid<br>
            attr PM sidHeader1 Content-Type: application/json<br>
            attr PM sid1IDRegex wui.init\('([^']+)'<br>
            attr PM sid2Data {"set" :{"9.17401.user" :"fhem" ,"9.17401.pass" :"password" }}<br>
            attr PM sid3Data {"set" :{"35.5062.value" :"128" }}<br>
            attr PM sid4Data {"set" :{"42.8026.code" :"pincode" }}<br>
        </ul></code>
        
    </ul>
    <br>

    <a name="HTTPMODset"></a>
    <b>Set-Commands</b><br>
    <ul>
        as defined by the attributes set.*Name
        If you set the attribute enableControlSet to 1, the following additional built in set commands are available:<br>
        <ul>
            <li><b>interval</b></li>
                set new interval time in seconds and restart the timer<br>
            <li><b>reread</b></li>
                request the defined URL and try to parse it just like the automatic update would do it every Interval seconds without modifying the running timer. <br>
            <li><b>stop</b></li>
                stop interval timer.<br>
            <li><b>start</b></li>
                restart interval timer to call GetUpdate after interval seconds<br>
        </ul>
        <br>
    </ul>
    <br>
    <a name="HTTPMODget"></a>
    <b>Get-Commands</b><br>
    <ul>
        as defined by the attributes get.*Name
    </ul>
    <br>
    <a name="HTTPMODattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>requestHeader.*</b></li> 
            Define an optional additional HTTP Header to set in the HTTP request <br>
        <li><b>requestData</b></li>
            optional POST Data to be sent in the request. If not defined, it will be a GET request as defined in HttpUtils used by this module<br>
        <li><b>reading[0-9]+Name</b> or <b>readingsName.*</b></li>
            the name of a reading to extract with the corresponding readingRegex<br>
        <li><b>reading[0-9]+Regex</b> ro <b>readingsRegex.*</b></li>
            defines the regex to be used for extracting the reading. The value to extract should be in a sub expression e.g. ([\d\.]+) in the above example <br>
        <li><b>reading[0-9]*Expr</b> or <b>readingsExpr.*</b></li>
            defines an expression that is used in an eval to compute the readings value. <br>
            The raw value will be in the variable $val.<br>
            If specified as readingExpr then the attribute value is a default for all other readings that don't specify 
            an explicit reading[0-9]*Expr.
        <li><b>reading[0-9]*Map</b></li>
            Map that defines a mapping from raw to visible values like "0:mittig, 1:oberhalb, 2:unterhalb". <br>
            If specified as readingMap then the attribute value is a default for all other readings that don't specify 
            an explicit reading[0-9]*Map.
        <li><b>reading[0-9]*Format</b></li>
            Defines a format string that will be used in sprintf to format a reading value.<br>
            If specified as readingFormat then the attribute value is a default for all other readings that don't specify 
            an explicit reading[0-9]*Format.

        <li><b>reading[0-9]*Decode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw data string read from the device to a reading. This can be used if the device delivers strings in an encoding like cp850 instead of utf8.
        <li><b>reading[0-9]*Encode</b></li> 
            defines an encoding to be used in a call to the perl function encode to convert the raw data string read from the device to a reading. This can be used if the device delivers strings in an encoding like cp850 and after decoding it you want to reencode it to e.g. utf8.

        <li><b>noShutdown</b></li>
            pass the noshutdown flag to HTTPUtils for webservers that need it (some embedded webservers only deliver empty pages otherwise)
        <li><b>disable</b></li>
            stop doing automatic HTTP requests while this attribute is set to 1
        <li><b>timeout</b></li>
            time in seconds to wait for an answer. Default value is 2
        <li><b>enableControlSet</b></li>
            enables the built in set commands interval, stop, start, reread.
        <li><b>enableXPath</b></li>
            enables the use of "xpath:" instead of a regular expression to parse the HTTP response
        <li><b>enableXPath-Strict</b></li>
            enables the use of "xpath-strict:" instead of a regular expression to parse the HTTP response
    </ul>
    <br>
    <b> advanced attributes </b>
    <br>
    <ul>
        <li><b>reAuthRegex</b></li>
            regular Expression to match an error page indicating that a session has expired and a new authentication for read access needs to be done. This attribute only makes sense if you need a forms based authentication for reading data and if you specify a multi step login procedure based on the sid.. attributes.
        <br><br>
        <li><b>sid[0-9]*URL</b></li>
            different URLs or one common URL to be used for each step of an optional login procedure. 
        <li><b>sid[0-9]*IDRegex</b></li>
            different Regexes per login procedure step or one common Regex for all steps to extract the session ID from the HTTP response
        <li><b>sid[0-9]*Data.*</b></li>
            data part for each step to be sent as POST data to the corresponding URL
        <li><b>sid[0-9]*Header.*</b></li>
            HTTP Headers to be sent to the URL for the corresponding step
        <li><b>sid[0-9]*IgnoreRedirects</b></li>
            tell HttpUtils to not follow redirects for this authentication request
        <br>
        <br>
        <li><b>set[0-9]+Name</b></li>
            Name of a set option
        <li><b>set[0-9]*URL</b></li>
            URL to be requested for the set option
        <li><b>set[0-9]*Data</b></li>
            optional Data to be sent to the device as POST data when the set is executed. if this atribute is not specified, an HTTP GET method 
            will be used instead of an HTTP POST
        <li><b>set[0-9]*Header</b></li>
            optional HTTP Headers to be sent to the device when the set is executed
        <li><b>set[0-9]+Min</b></li>
            Minimum value for input validation. 
        <li><b>set[0-9]+Max</b></li>
            Maximum value for input validation. 
        <li><b>set[0-9]+Expr</b></li>
            Perl Expression to compute the raw value to be sent to the device from the input value passed to the set.
        <li><b>set[0-9]+Map</b></li>
            Map that defines a mapping from raw to visible values like "0:mittig, 1:oberhalb, 2:unterhalb". This attribute atomatically creates a hint for FhemWEB so the user can choose one of the visible values.
        <li><b>set[0-9]+Hint</b></li>
            Explicit hint for fhemWEB that will be returned when set ? is seen.
        <li><b>set[0-9]*ReAuthRegex</b></li>
            Regex that will detect when a session has expired an a new login needs to be performed.         
        <li><b>set[0-9]*NoArg</b></li>
            Defines that this set option doesn't require arguments. It allows sets like "on" or "off" without further values.
        <li><b>set[0-9]*TextArg</b></li>
            Defines that this set option doesn't require any validation / conversion. 
            The raw value is passed on as text to the device.
        <br>
        <br>
        <li><b>get[0-9]+Name</b></li>
            Name of a get option and Reading to be retrieved / extracted
        <li><b>get[0-9]*URL</b></li>
            URL to be requested for the get option. If this option is missing, the URL specified during define will be used.
        <li><b>get[0-9]*Data</b></li>
            optional data to be sent to the device as POST data when the get is executed. if this attribute is not specified, an HTTP GET method 
            will be used instead of an HTTP POST
        <li><b>get[0-9]*Header</b></li>
            optional HTTP Headers to be sent to the device when the get is executed
            
        <li><b>get[0-9]*URLExpr</b></li>
            optional Perl expression that allows modification of the URL at runtime. The origial value is available as $old.
        <li><b>get[0-9]*DatExpr</b></li>
            optional Perl expression that allows modification of the Post data at runtime. The origial value is available as $old.
        <li><b>get[0-9]*HdrExpr</b></li>
            optional Perl expression that allows modification of the Headers at runtime. The origial value is available as $old.
            
        <li><b>get[0-9]+Poll</b></li>
            if set to 1 the get is executed automatically during the normal update cycle (after the interval provided in the define command has elapsed)
        <li><b>get[0-9]+PollDelay</b></li>
            if the value should not be read in each iteration (after the interval given to the define command), then a
            minimum delay can be specified with this attribute. This has only an effect if the above Poll attribute has
            also been set. Every time the update function is called, it checks if since this get has been read the last time, the defined delay has elapsed. If not, then it is skipped this time.<br>
            PollDelay can be specified as seconds or as x[0-9]+ which means a multiple of the interval in the define command.
        <li><b>get[0-9]*Regex</b></li>
            If this attribute is specified, the Regex defined here is used to extract the value from the HTTP Response 
            and assign it to a Reading with the name defined in the get[0-9]+Name attribute.<br>
            if this attribute is not specified for an individual Reading but as getRegex, then it applies to all get options
            where no specific Regex is defined.<br>
            If neither a generic getRegex attribute nor a specific get[0-9]+Regex attribute is specified, then HTTPMOD
            tries all Regex / Reading pairs defined in Reading[0-9]+Name and Reading[0-9]+Regex attributes and assigns the 
            Readings that match.
        <li><b>get[0-9]*Expr</b></li>
            this attribute behaves just like Reading[0-9]*Expr but is applied to a get value. 
        <li><b>get[0-9]*Map</b></li>
            this attribute behaves just like Reading[0-9]*Map but is applied to a get value.
        <li><b>get[0-9]*Format</b></li>
            this attribute behaves just like Reading[0-9]*Format but is applied to a get value.
            
        <li><b>get[0-9]*Decode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw data string read from the device to a reading. This can be used if the device delivers strings in an encoding like cp850 instead of utf8.
        <li><b>get[0-9]*Encode</b></li> 
            defines an encoding to be used in a call to the perl function encode to convert the raw data string read from the device to a reading. This can be used if the device delivers strings in an encoding like cp850 and after decoding it you want to reencode it to e.g. utf8.

            <li><b>get[0-9]*CheckAllReadings</b></li>
            this attribute modifies the behavior of HTTPMOD when the HTTP Response of a get command is parsed. <br>
            If this attribute is set to 1, then additionally to any matching of get specific regexes (get[0-9]*Regex), 
            also all the Regex / Reading pairs defined in Reading[0-9]+Name and Reading[0-9]+Regex attributes are checked and if they match, the coresponding Readings are assigned as well.
        <br>
        <li><b>get[0-9]*URLExpr</b></li>
            Defines a Perl expression to specify the HTTP Headers for this request. This overwrites any other header specification and should be used carefully only if needed e.g. to pass additional variable data to a web service. The original Header is availabe as $old.
        <li><b>get[0-9]*DatExpr</b></li>
            Defines a Perl expression to specify the HTTP Post data for this request. This overwrites any other post data specification and should be used carefully only if needed e.g. to pass additional variable data to a web service.
            The original Data is availabe as $old.
        <li><b>get[0-9]*HdrExpr</b></li>
            Defines a Perl expression to specify the URL for this request. This overwrites any other URL specification and should be used carefully only if needed e.g. to pass additional variable data to a web service.
            The original URL is availabe as $old.
        <br>
        <br>
        <li><b>showMatched</b></li>
            if set to 1 then HTTPMOD will create a reading that contains the names of all readings that could be matched in the last request.
        <li><b>queueDelay</b></li>
            HTTP Requests will be sent from a queue in order to avoid blocking when several Requests have to be sent in sequence. This attribute defines the delay between calls to the function that handles the send queue. It defaults to one second.
        <li><b>queueMax</b></li>
            Defines the maximum size of the send queue. If it is reached then further HTTP Requests will be dropped and not be added to the queue
        <li><b>minSendDelay</b></li>
            Defines the minimum time between two HTTP Requests.
    </ul>
    <br>
    <b>Author's notes</b><br><br>
    <ul>
        <li>If you don't know which URLs, headers or POST data your web GUI uses, you might try a local proxy like <a href=http://portswigger.net/burp/>BurpSuite</a> to track requests and responses </li>
    </ul>
</ul>

=end html
=cut
