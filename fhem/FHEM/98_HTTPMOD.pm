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
#	2014-12-22	Warnung in Set korrigiert
#
                    
package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    
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
    #$hash->{GetFn}   = "HTTPMOD_Get";
    $hash->{AttrFn}  = "HTTPMOD_Attr";
    $hash->{AttrList} =
      "reading[0-9]*Name " .    # new syntax for readings
      "reading[0-9]*Regex " .
      "reading[0-9]*Expr " .
      
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
      
      "do_not_notify:1,0 " . 
      "disable:0,1 " .
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
    my $url     = $a[2];
    my $inter   = 300;
    
    if(int(@a) == 4) { 
        $inter = $a[3]; 
        if ($inter < 5) {
            return "interval too small, please use something > 5, default is 300";
        }
    }

    $hash->{MainURL}    = $url;
    $hash->{Interval}   = $inter;
  
    # initial request after 2 secs, there the timer is set to interval for further updates
    InternalTimer(gettimeofday()+2, "HTTPMOD_GetUpdate", "update:$name", 0);
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
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    # simple attributes like requestHeader and requestData need no special treatment here
    # readingsExpr, readingsRegex.* or reAuthRegex need validation though.
    
    if ($cmd eq "set") {        
        if ($aName =~ "Regex") {    # catch all Regex like attributes
            eval { qr/$aVal/ };
            if ($@) {
                Log3 $name, 3, "$name: Invalid regex in attr $name $aName $aVal: $@";
                return "Invalid Regex $aVal";
            }
        } elsif ($aName =~ "Expr") { # validate all Expressions
            my $val = 1;
            eval $aVal;
            if ($@) {
                Log3 $name, 3, "$name: Invalid Expression in attr $name $aName $aVal: $@";
                return "Invalid Expression $aVal";
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
    Log3 $name, 4, "$name: start Auth with Steps: " . join (" ", sort keys %steps);

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
        HTTPMOD_AddToQueue($hash, $url, $header, $data, $type, $retrycount, $ignoreredirects);
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
    
    # ersetze $val in header, data und URL
    $header =~ s/\$val/$rawVal/g;
    $data   =~ s/\$val/$rawVal/g;
    $url    =~ s/\$val/$rawVal/g;
 
    $type = "Set$setNum";
    
    HTTPMOD_AddToQueue($hash, $url, $header, $data, $type); # leave RetryCount, IgnoreRedirects and Prio
    return undef;
}


#
# SET command
#########################################################################
sub HTTPMOD_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set HTTPMOD\" needs at least an argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, SetName, Rest of Set Line
    my ($name, $setName, $setVal) = @a;
    my (%rmap, $setNum, $setOpt, $setList, $rawVal);
	$setList = "";
    
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "");

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

    # Ist überhaupt ein Wert übergeben?
    if (!defined($setVal)) {
        Log3 $name, 3, "$name: no value given to set $setName";
        return "no value given to set $setName";
    }
    Log3 $name, 5, "$name: Set found option $setName in attribute set${setNum}Name";

    # Eingabevalidierung von Sets mit Definition per Attributen
    # 1. Schritt, falls definiert, per Umkehrung der Map umwandeln (z.B. Text in numerische Codes)
    if (AttrVal($name, "set${setNum}Map", undef)) {     # gibt es eine Map?
        my $rm = AttrVal($name, "set${setNum}Map", undef);
        $rm =~ s/([^ ,\$]+):([^ ,\$]+),? ?/$2 $1 /g;    # reverse map string erzeugen
        %rmap = split (' ', $rm);                       # reverse hash aus dem reverse string                   
        if (defined($rmap{$setVal})) {                  # Eintrag für den übergebenen Wert in der Map?
            $rawVal = $rmap{$setVal};                   # entsprechender Raw-Wert für das Gerät
            Log3 $name, 5, "$name: found $setVal in rmap and converted to $rawVal";
        } else {
            Log3 $name, 3, "$name: Set value $setVal did not match defined map";
            return "set value $setVal did not match defined map";
        }
    } else {
      # wenn keine map, dann wenigstens sicherstellen, dass Wert numerisch.
      if ($setVal !~ /^-?\d+\.?\d*$/) {
        Log3 $name, 3, "$name: set value $setVal is not numeric";
        return "set value $setVal is not numeric";
      }
      $rawVal = $setVal;
    }
    
    # 2. Schritt: falls definiert Min- und Max-Werte prüfen
    if (AttrVal($name, "set${setNum}Min", undef)) {
        my $min = AttrVal($name, "set${setNum}Min", undef);
        Log3 $name, 5, "$name: checking value $rawVal against min $min";
        return "set value $rawVal is smaller than Min ($min)"
            if ($rawVal < $min);
    }
    if (AttrVal($name, "set${setNum}Max", undef)) {
        my $max = AttrVal($name, "set${setNum}Max", undef);
        Log3 $name, 5, "$name: checking value $rawVal against max $max";
        return "set value $rawVal is bigger than Max ($max)"
            if ($rawVal > $max);
    }

    # 3. Schritt: Konvertiere mit setexpr falls definiert
    if (AttrVal($name, "set${setNum}Expr", undef)) {
        my $val = $rawVal;
        my $exp = AttrVal($name, "set${setNum}Expr", undef);
        $rawVal = eval($exp);
        Log3 $name, 5, "$name: converted value $val to $rawVal using expr $exp";
    }
    
    Log3 $name, 4, "$name: set will now set $setName -> $rawVal";
    my $result = HTTPMOD_DoSet($hash, $setNum, $rawVal);
    return "$setName -> $rawVal";
}


#
# GET command
# currently not used
#########################################################################
sub HTTPMOD_Get($@)
{
    return undef;
}



#
# request new data from device
###################################
sub HTTPMOD_GetUpdate($)
{
    my (undef,$name) = split(':', $_[0]);
    my $hash = $defs{$name};
    my ($url, $header, $data, $type, $count);
    
    RemoveInternalTimer ("update:$name");
    InternalTimer(gettimeofday()+$hash->{Interval}, "HTTPMOD_GetUpdate", "update:$name", 0);
    
    return if(AttrVal($name, "disable", undef));

    Log3 $name, 4, "$name: GetUpdate called";
    
    if ( $hash->{MainURL} eq "none" ) {
        return 0;
    }

    $url    = $hash->{MainURL};
    $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestHeader/, keys %{$attr{$name}})));
    $data   = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestData/, keys %{$attr{$name}})));
    $type   = "Update";
   
    HTTPMOD_AddToQueue($hash, $url, $header, $data, $type); # leave RetryCount, IgnoreRedirects and Prio
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
        Log3 $name, 3, "$name: read callback: request type was $type" . 
             ($header ? ",\r\nheader: $header" : ", no headers") . 
             ($buffer ? ",\r\nbuffer: $buffer" : ", buffer empty") . 
             ($err ? ", \r\nError $err" : "");
        return;
    }
    
    Log3 $name, 5, "$name: Read Callback: Request type was $type" .
             ($header ? ",\r\nheader: $header" : ", no headers") . 
             ($buffer ? ",\r\nbuffer: $buffer" : ", buffer empty");
    
    
    $buffer = $header . "\r\n\r\n" . $buffer if ($header);
    
    if ($type =~ "Auth(.*)") {
        my $step = $1;
        # sid extrahieren
        if (AttrVal($name, "sid${step}IDRegex", undef)) {
            if ($buffer =~ AttrVal($name, "sid1IDRegex", undef)) {
                $hash->{sid} = $1;
                Log3 $name, 5, "$name: set sid to $hash->{sid}";
            } else {
                Log3 $name, 5, "$name: buffer did not match IDRegex " .
                        AttrVal($name, "sid${step}IDRegex", undef);
            }
        }
    } elsif ($type =~ "Set(.*)") {
        my $setNum = $1;
        my $ReAuthRegex = AttrVal($name, "set${setNum}ReAuthRegex", AttrVal($name, "setReAuthRegex", undef));
        if ($ReAuthRegex) {
            Log3 $name, 5, "$name: checking response with ReAuthRegex $ReAuthRegex";
            if ($buffer =~ $ReAuthRegex) {
                Log3 $name, 4, "$name: New authentication required";
                if ($request->{retryCount} < 1) {
                    HTTPMOD_Auth $hash;
                    $request->{retryCount}++;
                    Log3 $name, 4, "$name: ReQueuing set with new retryCount $request->{retryCount} ...";
                    HTTPMOD_AddToQueue ($hash, $request->{url}, $request->{header}, 
                            $request->{data}, $request->{type}, $request->{retryCount}); 
                    return undef;
                } else {
                    Log3 $name, 4, "$name: no more retries left - did authentication not work?";
                }
            }
        }
    } elsif ($type eq "Update") {
        my $ReAuthRegex = AttrVal($name, "reAuthRegex", undef);
        if ($ReAuthRegex) {
            Log3 $name, 5, "$name: checking response with ReAuthRegex $ReAuthRegex";
            if ($buffer =~ $ReAuthRegex) {
                Log3 $name, 4, "$name: New authentication required";
                if ($request->{retryCount} < 1) {
                    HTTPMOD_Auth $hash;
                    $request->{retryCount}++;
                    Log3 $name, 4, "$name: ReQueueing GetUpdate with new retryCount $request->{retryCount} ...";
                    HTTPMOD_AddToQueue ($hash, $request->{url}, $request->{header}, 
                            $request->{data}, $request->{type}, $request->{retryCount});
                    return undef;
                } else {
                    Log3 $name, 4, "$name: no more retries left - did authentication not work?";
                }
            }
        }

        Log3 $name, 5, "$name: start extracting Readings from Response to GetUpdate";
        my $unmatched = "";
        readingsBeginUpdate($hash);
        foreach my $a (sort (grep (/readings?[0-9]*Name/, keys %{$attr{$name}}))) {
            $a =~ /readings?([0-9]*)Name(.*)/;
            my ($reading, $regex, $expr);
            if (($a =~ /readingsName(.*)/) && defined ($attr{$name}{'readingsName' . $1}) 
                  && defined ($attr{$name}{'readingsRegex' . $1})) {
                # old syntax
                $reading = $attr{$name}{'readingsName' . $1};
                $regex   = $attr{$name}{'readingsRegex' . $1};
                $expr    = "";
                if (defined ($attr{$name}{'readingsExpr' . $1})) {
                    $expr = $attr{$name}{'readingsExpr' . $1};
                }
            } elsif(($a =~ /reading([0-9]+)Name/) && defined ($attr{$name}{"reading${1}Name"}) 
                  && defined ($attr{$name}{"reading${1}Regex"})) {
                # new syntax
                $reading = $attr{$name}{"reading${1}Name"};
                $regex   = $attr{$name}{"reading${1}Regex"};
                $expr    = "";
                if (defined ($attr{$name}{"reading${1}Expr"})) {
                    $expr = $attr{$name}{"reading${1}Expr"};
                }
            } else {
                Log3 $name, 3, "$name: inconsistant attributes for $a";
                next;
            }
            Log3 $name, 5, "$name: Trying to extract Reading $reading with regex /$regex/...";
            if ($buffer =~ /$regex/) {
                my $val = $1;
                if ($expr) {
                    $val = eval $expr;
                    Log3 $name, 5, "$name: change value for Reading $reading with Expr $expr from $1 to $val";
                }
                Log3 $name, 5, "$name: Set Reading $reading to $val";
                readingsBulkUpdate( $hash, $reading, $val );
            } else {
                if ($unmatched) {
                    $unmatched .= ", $reading";
                } else {
                    $unmatched = "$reading";
                }
            }
        }
        readingsEndUpdate( $hash, 1 );
        if ($unmatched) {
            Log3 $name, 3, "$name: Response didn't match Reading(s) $unmatched";
            Log3 $name, 4, "$name: response was $buffer";
        }
        return undef;
    }
}



#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit $direct:$name
#todo: sobald letzter Request beantwortet ist (in Read) auch aufrufen.
sub
HTTPMOD_HandleSendQueue($)
{
  my (undef,$name) = split(':', $_[0]);
  my $hash  = $defs{$name};
  my $queue = $hash->{QUEUE};
  
  my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
  Log3 $name, 5, "$name: handle send queue called, qlen = $qlen";
  RemoveInternalTimer ("queue:$name");
  
  if(defined($queue) && @{$queue} > 0) {
  
    my $queueDelay  = AttrVal($name, "queueDelay", 1);  
    my $now = gettimeofday();
  
    if (!$init_done) {      # fhem not initialized, wait with IO
      InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
      Log3 $name, 3, "$name: init not done, delay sending from queue";
      return;
    }
    if ($hash->{BUSY}) {  # still waiting for reply to last request
      InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
      Log3 $name, 5, "$name: still waiting for reply to last request, delay sending from queue";
      return;
    }

    $hash->{REQUEST} = $queue->[0];

    if($hash->{REQUEST}{url} ne "") {    # if something to send - check min delay and send
        my $minSendDelay = AttrVal($hash->{NAME}, "minSendDelay", 0.2);

        if ($hash->{LASTSEND} && $now < $hash->{LASTSEND} + $minSendDelay) {
            InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
            Log3 $name, 5, "$name: HandleSendQueue minSendDelay not over, rescheduling";
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
            Log3 $name, 3, "$name: send queue too long, dropping request";
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
        <b>Advanced configuration to define a <code>set</code> and send data to a device</b>
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
        the optional attribute set01Hint will define a selection list for the Fhemweb GUI.
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
        doing the login procedure. If the Attribute ReAuthRegex is defined, it will then compare the HTTP Response to the set request with the regular expression from ReAuthRegex. If it matches, then a 
        login is performed. The ReAuthRegex is meant to match the error page a device returns if authentication or reauthentication is required e.g. because a session timeout has expired. <br><br>
        
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
    </ul>
    <br>
    <a name="HTTPMODget"></a>
    <b>Get-Commands</b><br>
    <ul>
        none so far
    </ul>
    <br>
    <a name="HTTPMODattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>requestHeader.*</b></li> 
            Define an additional HTTP Header to set in the HTTP request <br>
        <li><b>requestData</b></li>
            POST Data to be sent in the request. If not defined, it will be a GET request as defined in HttpUtils used by this module<br>
        <li><b>reading[0-9]*Name</b> or <b>readingsName.*</b></li>
            the name of a reading to extract with the corresponding readingRegex<br>
        <li><b>reading[0-9]*Regex</b> ro <b>readingsRegex.*</b></li>
            defines the regex to be used for extracting the reading. The value to extract should be in a sub expression e.g. ([\d\.]+) in the above example <br>
        <li><b>reading[0-9]*Expr</b> or <b>readingsExpr.*</b></li>
            defines an expression that is used in an eval to compute the readings value. The raw value will be in the variable $val.
        <li><b>noShutdown</b></li>
            pass the noshutdown flag to HTTPUtils for webservers that need it (some embedded webservers only deliver empty pages otherwise)
        <li><b>disable</b></li>
            stop doing HTTP requests while this attribute is set to 1
        <li><b>timeout</b></li>
            time in seconds to wait for an answer. Default value is 2
    </ul>
    <br>
    <b> advanced attributes </b>
    <br>
    <ul>
        <li><b>ReAuthRegex</b></li>
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
            Data to be sent to the device as POST data when the set is executed
        <li><b>set[0-9]*Header</b></li>
            HTTP Headers to be sent to the device when the set is executed
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
        <br>
        <br>
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
