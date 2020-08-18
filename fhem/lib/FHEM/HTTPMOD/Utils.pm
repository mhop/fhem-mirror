#########################################################################
# $Id$
# Utility functions of HTTPMOD that can be uses by other Fhem modules
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
                    
package FHEM::HTTPMOD::Utils;

use strict;
use warnings;

use GPUtils         qw(:all);
use Time::HiRes     qw(gettimeofday);    
use Encode          qw(decode encode);
use DevIo;

use Exporter ('import');
our @EXPORT_OK = qw(UpdateTimer FhemCaller 
                    ValidRegex ValidExpr
                    EvalExpr
                    MapConvert MapToHint
                    ReadKeyValue StoreKeyValue
                    ManageUserAttr
                    MemReading
                    FlattenJSON
                    BodyDecode
                    IsOpen
                    FmtTime
                    );

our %EXPORT_TAGS = (all => [@EXPORT_OK]);

BEGIN {
    GP_Import( qw(
        Log3
        RemoveInternalTimer
        InternalTimer
        gettimeofday

        FmtDateTime
        addToDevAttrList
        modules
        attr
        ReadingsVal
        ReadingsTimestamp
        AttrVal
        InternalVal

        readingsSingleUpdate
        readingsBeginUpdate
        readingsBulkUpdate
        readingsEndUpdate
        makeReadingName

        EvalSpecials
        AnalyzePerlCommand
        PerlSyntaxCheck
        rtrim

        featurelevel
        
        DevIo_OpenDev
        DevIo_SimpleWrite
        DevIo_SimpleRead
        DevIo_CloseDev
        DevIo_IsOpen
        
    ));
};


####################################################################################################
# set internal Timer to call GetUpdate if necessary
# at next interval. Time can be aligned (attribute TimeAlign)
# called from attr (disable, alignTime), set (interval, start), openCB, 
# notify (INITIALIZED|REREADCFG|MODIFIED|DEFINED) and getUpdate
# call e.g.:
# UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'next');         # set update timer for next round (now + interval)
# UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'stop');
# UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'start');        # first call: call asap

sub UpdateTimer {
    my $hash   = shift;
    my $updFn  = shift;
    my $cmd    = shift // 'next';
    my $name   = $hash->{NAME};
    my $now    = gettimeofday();
    my $intvl  = $hash->{Interval} // 0;                    # make sure module doesn't use other spelling / caps
    
    if ($cmd eq 'stop' || !$intvl) {                        # stop timer
        RemoveInternalTimer("update:$name");
        if ($hash->{TRIGGERTIME}) {
            Log3 $name, 4, "$name: UpdateTimer called from " . FhemCaller() . " with cmd $cmd and interval $intvl stops timer";
            delete $hash->{TRIGGERTIME};
            delete $hash->{TRIGGERTIME_FMT};
            delete $hash->{lastUpdate};
        }
        return;
    }
    if ($cmd eq 'next') {
        $hash->{lastUpdate} = $now;                         # start timer from now, ignore potential last update time
    } 
    my $nextUpdate;
    if ($hash->{TimeAlign}) {                               # TimeAlign: do as if interval started at time w/o drift ...
        my $count   = int(($now - $hash->{TimeAlign}) / $intvl);    # $intvl <> 0,has been checked above
        $nextUpdate = $count * $intvl + $hash->{TimeAlign}; # next aligned time >= now, lastUpdate doesn't matter with alignment
        $nextUpdate += $intvl if ($nextUpdate <= $now);     # works for initial alignment as welas for next round
    } 
    else {                                                  # no align time -> just add the interval to now
        if ($hash->{lastUpdate}) {
            $nextUpdate = $hash->{lastUpdate} + $intvl;     
        } 
        else {
            $nextUpdate = $now;                             # first call -> don't wait for interval to pass
        }
    }
    $hash->{TRIGGERTIME}     = $nextUpdate;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextUpdate);

    my $delay = sprintf ("%.1f", $nextUpdate - $now);
    Log3 $name, 4, "$name: UpdateTimer called from " . FhemCaller() . " with cmd $cmd" .
        " sets timer to call update function in $delay sec at $hash->{TRIGGERTIME_FMT}, interval $intvl";
    RemoveInternalTimer("update:$name");
    InternalTimer($nextUpdate, $updFn, "update:$name", 0);  # now set the timer   
    return;
}



#########################################################################
# check if a regex is valid
sub ValidRegex {
    my $hash   = shift;
    my $action = shift;
    my $regex  = shift;
    my $name   = $hash->{NAME};

    # check if Regex is valid 
    local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: $action with regex $regex created warning: @_"; };
    eval {qr/$regex/};                  ## no critic
    if ($@) {
        Log3 $name, 3, "$name: $action with regex $regex created error: $@";
        return 0;
    }
    return 1;
}


##################################################################################
# evaluate perl expression and make variables available for the expression
# call like $new = EvalExpr($hash, $exp, $rawVal, {'%setValArr' => \@setValArr});
#
# Problem: can not pass $val and @val at the same time because evalSpecials 
# expects %val for both.
# also $hash can not be passed but will become %hash. Same reason.
#
sub EvalExprWithFhemFunctions {
    my $hash    = shift;                    # the current device hash
    my $exp     = shift;                    # the expression to be used
    my $text    = shift;                    # the original value to be avaliable as val / old / rawVal
    my $val_ref = shift;                    # the values to be passed via EvalSpecials into eval
    my $name    = $hash->{NAME};
    my %vHash;

    $val_ref = \%vHash if (!$val_ref);      # if no value hash is passed create one
    $val_ref->{'%hash'}         = $hash;
    $val_ref->{'%name'}         = $name;
    $val_ref->{'%val'}          = $text if (!exists $val_ref->{'%val'});
    $val_ref->{'%old'}          = $text if (!exists $val_ref->{'%old'});
    $val_ref->{'%rawVal'}       = $text if (!exists $val_ref->{'%rawVal'});
    $val_ref->{'%inCheckEval'}  = 1     if (!exists $val_ref->{'%inCheckEval'});

    if ($exp) {
        $exp  = EvalSpecials($exp, %{$val_ref});
        $text = AnalyzePerlCommand(undef, $exp);
        #Log3 $name, 5, "$name: eval $exp resulted in $text";
    }   
    return $text;
}


###################################################################
# new combined function for evaluating perl expressions
# pass values via hash reference similar to fhem EvalSpecials
# together with AnalyzePerlCommands but more flexible:
#
# var names can not only start with % but also @ and $
# when a hash is passed and the target variable name starts with $
# then it is assigned the hash reference not a new copy of the hash
# same for arrays.
#
# special keys:
# checkOnly : only do sytax check and return 1 if valid
# action    : describe context for logging
#
# some variables are set by default to make use in HTTPMOD and Modbus 
# easier: $val, $old, $text, $rawVal, $inCheckEval, @val
#
sub EvalExpr {
    my $hash   = shift;                     # the current device hash
    my $exp    = shift;                     # the expression to be used
    my $vRef   = shift;                     # optional setValArr as reference for use in expressions
    
    my $name   = $hash->{NAME};
    my $val    = 0;
    my @val    = ($val);
    my %vHash;
    
    my $r = ref $vRef;
    if (ref $vRef eq '') {
        $val  = $vRef;
        $vRef = shift;
        #Log3 $name, 5, "$name: old syntax used, ref is $r, val is $val";
    } else {
        $val  = $vRef->{'val'} // '';      # need input value already now as potential return value
        #Log3 $name, 5, "$name: new syntax used, ref is $r, val is $val";
    }
    $vRef = \%vHash if (ref ($vRef) ne 'HASH');                     # create hash if not passed (rare case)
    my $action    = $vRef->{'action'} // 'perl expression eval';    # context for logging
    my $checkOnly = $vRef->{'checkOnly'} // 0;                      # only syntax check
    return $val if (!$exp);
    
    my $old         = $val;                 # predefined variables, can be overwritten in %vHash
    my $rawVal      = $val;
    my $text        = $val;
    my $inCheckEval = ($checkOnly ? 0 : 1);

    my $assign = '';
    foreach my $key (keys %{$vRef}) {
        my $type   = ref $vRef->{$key};
        my $vName  = substr($key,1);
        my $vType  = substr($key,0,1);
        
        if ($type eq 'SCALAR') {
            $assign .= "my \$$vName = \${\$vRef->{'$key'}};";   # assign ref to scalar as scalar
        } 
        elsif ($type eq 'ARRAY' && $vType eq '$') {
            $assign .= "my \$$vName = \$vRef->{'$key'};";       # assign array ref as array ref
        } 
        elsif ($type eq 'ARRAY') {
            $assign .= "my \@$vName = \@{\$vRef->{'$key'}};";   # assign array ref as array
        } 
        elsif ($type eq 'HASH' && $vType eq '$') {
            $assign .= "my \$$vName = \$vRef->{'$key'};";       # assign hash ref as hash ref
        } 
        elsif ($type eq 'HASH') {
            $assign .= "my \%$vName = \%{\$vRef->{'$key'}};";   # assign hash ref as hash
        } 
        elsif ($type eq '' && $vType eq '$') {
            $assign .= "my \$$vName = \$vRef->{'$key'};";       # assign scalar as scalar
        }
    }
    $exp = $assign . ($checkOnly ? 'return undef;' : '') . $exp;
    
    local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: $action with expresion $exp created warning: @_"; };
    my $result = eval $exp;                  ## no critic
    if ($@) {
        Log3 $name, 3, "$name: $action with expression $exp on $val created error: $@";
        return 0 if ($checkOnly);
    } else {
        return 1 if ($checkOnly);
        Log3 $name, 5, "$name: $action evaluated $exp to $result";
    }
    return $result;
}



###########################################################
# return the name of the caling function for debug output
sub FhemCaller {
    my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller 2;
    return $1 if ($subroutine =~ /main::HTTPMOD_(.*)/);
    return $1 if ($subroutine =~ /main::(.*)/);
    return 'Fhem internal timer' if ($subroutine =~ /main::HandleTimeout/);
    return "$subroutine";
}


#########################################
# Try to convert a value with a map 
# called from Set and FormatReading
sub MapConvert {
    my $hash    = shift;
    my $map     = shift;
    my $val     = shift;
    my $reverse = shift;
    my $name    = $hash->{NAME};
    
    $map =~ s/\s+/ /g;                                          # substitute all \t \n etc. by one space only       
    if ($reverse) {
        $map =~ s/([^, ][^,\$]*):([^,][^,\$]*),? */$2:$1, /g;   # reverse map
    }
    # spaces in words allowed, separator is ',' or ':'
    $val = decode ('UTF-8', $val);                              # convert nbsp from fhemweb
    $val =~ s/\s|&nbsp;/ /g;                                    # back to normal spaces in case it came from FhemWeb with coded Blank

    my %mapHash = split (/, *|:/, $map);                        # reverse hash aus dem reverse string                   

    if (defined($mapHash{$val})) {                              # Eintrag für den übergebenen Wert in der Map?
        my $newVal = $mapHash{$val};                            # entsprechender Raw-Wert für das Gerät
        Log3 $name, 5, "$name: MapConvert called from " . FhemCaller() . " converted $val to $newVal with" .
        ($reverse ? " reversed" : "") . " map $map";
        return $newVal;
    } 
    else {
        Log3 $name, 3, "$name: MapConvert called from " . FhemCaller() . " did not find $val in" . 
        ($reverse ? " reversed" : "") . " map $map";
        return;
    }
}


#########################################
# called from UpdateHintList
sub MapToHint {
    my $hint = shift;                                               # create hint from map
    $hint =~ s/([^,\$]+):([^,\$]+)(,?) */$2$3/g;                    # allow spaces in names
    $hint =~ s/\s/&nbsp;/g;                                         # convert spaces for fhemweb
    return $hint;
}


#########################################################################
# set userAttr-Attribute for Regex-Attrs
# pass device hash and new attr based on a regex attr
sub ManageUserAttr {                     
    my $hash    = shift;
    my $aName   = shift;
    my $name    = $hash->{NAME};
    my $modHash = $modules{$hash->{TYPE}};

    if ($modHash->{AttrList} =~ m{  (?:\A|\s)                       # Beginning or space
                                    $aName                          # the name of the new attribute
                                    (?: \s | \: | \z)               # space, : or the end 
                                }xms) {                             # does AttrList contain the passed attribute (potentially with an added hint) -> no regex attr?
        my $retVal;
        if ($aName =~ m{ \| \* \+ \[}xms) {                         # contained in list -> make sure nobody tries to set it as regex attr
            $retVal = "$name: Atribute $aName is not valid. It still contains wildcard symbols";
            Log3 $name, 3, $retVal;
        }
        return $retVal;
    }
    # go through all possible attrs and check if the passed attr matches one of the regex attrs
    foreach my $listAttr (split " ", $modHash->{AttrList}) {
        my ($listAttrName, $listAttrHint) 
            = $listAttr =~ m{ \A ([^:]+) (:?.*) }xms;               # split list entry in name and optional hint
        if ($aName =~ m{\A$listAttrName\z}xms) {                    # yes - the passed attribute name now matches the entry in the list as regex
            addToDevAttrList($name, $aName . $listAttrHint);        # create userattr with hint to allow change in fhemweb
            #Log3 $name, 5, "$name: ManageUserAttr added attr $aName to userattr list";

            if ($listAttrHint) {                                    # in case an earlier version added the attribute without the hint, remove old entry
                my $uaList = $attr{$name}{userattr} // '';
                my %uaHash;
                foreach my $userAttr (split(" ", $uaList)) {
                    if ($userAttr !~ m{\A $aName \z}xms) {          # no match -> existing entry in userattr list is attribute without hint
                        $uaHash{$userAttr} = 1;                     # put $userAttr as key into the hash so it is kept in userattr
                    } 
                    else {                                          # match -> in list without attr -> remove
                        #Log3 $name, 5, "$name: ManageUserAttr removes attr $userAttr without hint $listAttrHint from userattr list";
                    }
                }
                $attr{$name}{userattr} = join(" ", sort keys %uaHash);
            }
        }
    }
    return;
}


###################################################
# checks and stores obfuscated keys like passwords 
# based on / copied from FRITZBOX_storePassword
sub StoreKeyValue {
    my $hash  = shift;
    my $kName = shift;
    my $value = shift;
     
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;    
    my $enc   = "";
    
    if(eval { use Digest::MD5; 1 }) {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    for my $char (split //, $value) {
        my $encode=chop($key);
        $enc.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = setKeyValue($index, $enc);
    return "error while saving the value - $err" if(defined($err));
    return;
} 
   
   
#####################################################
# reads obfuscated value 
sub ReadKeyValue {
    my $hash  = shift;
    my $kName = shift;
    my $name  = $hash->{NAME};
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;
    my ($value, $err);

    Log3 $name, 5, "$name: ReadKeyValue tries to read value for $kName from file";
    ($err, $value) = getKeyValue($index);
    if ( defined($err) ) {
        Log3 $name, 4, "$name: ReadKeyValue is unable to read value from file: $err";
        return;
    }  
    
    if ( !defined($value) ) {
        Log3 $name, 4, "$name: ReadKeyValue could not find key $kName in file";
        return;
    }
    if (eval { use Digest::MD5; 1 }) {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    my $dec = '';
    for my $char (map { pack('C', hex($_)) } ($value =~ /(..)/g)) {
        my $decode=chop($key);
        $dec.=chr(ord($char)^ord($decode));
        $key=$decode.$key;
    }   
    return $dec;
} 



###################################################
# recoursive main part for HTTPMOD_FlattenJSON($$)
# consumes a hash passed as parameter
# and creates $hash->{ParserData}{JSON}{$prefix.$key}
sub JsonFlatter {
    my $hash   = shift;             # reference to Fhem device hash
    my $ref    = shift;             # starting point in JSON-Structure hash
    my $prefix = shift // '';       # prefix string for resulting key
    my $name   = $hash->{NAME};     # Fhem device name

    #Log3 $name, 5, "$name: JSON Flatter called : prefix $prefix, ref is $ref";
    if (ref($ref) eq "ARRAY" ) { 
        my $key = 0;
        foreach my $value (@{$ref}) {
            #Log3 $name, 5, "$name: JSON Flatter in array while, key = $key, value = $value"; 
            if(ref($value) eq "HASH" or ref($value) eq "ARRAY") {                                                        
                #Log3 $name, 5, "$name: JSON Flatter doing recursion because value is a " . ref($value);
                JsonFlatter($hash, $value, $prefix.sprintf("%02i",$key+1)."_"); 
            } 
            else { 
                if (defined ($value)) {             
                    #Log3 $name, 5, "$name: JSON Flatter sets $prefix$key to $value";
                    $hash->{ParserData}{JSON}{$prefix.$key} = $value; 
                }
            }
            $key++;         
        }                                                                            
    } 
    elsif (ref($ref) eq "HASH" ) {
        while( my ($key,$value) = each %{$ref}) {                                       
            #Log3 $name, 5, "$name: JSON Flatter in hash while, key = $key, value = $value";
            if(ref($value) eq "HASH" or ref($value) eq "ARRAY") {                                                        
                #Log3 $name, 5, "$name: JSON Flatter doing recursion because value is a " . ref($value);
                JsonFlatter($hash, $value, $prefix.$key."_");
            } 
            else { 
                if (defined ($value)) {             
                    #Log3 $name, 5, "$name: JSON Flatter sets $prefix$key to $value";
                    $hash->{ParserData}{JSON}{$prefix.$key} = $value; 
                }
            }                                                                          
        }                                                                            
    }     
    return;                                                                         
}                       


####################################
# entry to create a flat hash
# out of a pares JSON hash hierarchy
sub FlattenJSON {
    my $hash    = shift;                # reference to Fhem device hash
    my $buffer  = shift;                # buffer containing JSON data       
    my $name    = $hash->{NAME};        # Fhem device name

    eval { use JSON };                  
    return if($@);

    my $decoded = eval { decode_json($buffer) }; 
    if ($@) {
        Log3 $name, 3, "$name: error while parsing JSON data: $@";
    } 
    else {
        JsonFlatter($hash, $decoded);
        Log3 $name, 4, "$name: extracted JSON values to internal";
    }
    return;
}


#################################################################
# create memory Reading Fhem_Mem
sub MemReading {
    my $hash = shift;
    my $name = $hash->{NAME};        # Fhem device name
    my $v    = `awk '/VmSize/{print \$2}' /proc/$$/status`;
    $v = sprintf("%.2f",(rtrim($v)/1024));
    readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, "Fhem_Mem", $v);
    readingsBulkUpdate ($hash, "Fhem_BufCounter", $hash->{BufCounter}) if defined($hash->{BufCounter});
    readingsEndUpdate($hash, 1);
    Log3 $name, 5, "$name: Read checked virtual Fhem memory: " . $v . "MB" .
        (defined($hash->{BufCounter}) ? ", BufCounter = $hash->{BufCounter}" : "");
    return;
}


##########################################
# decode charset in a http response
sub BodyDecode {    
    my $hash       = shift;
    my $body       = shift;
    my $header     = shift // '';
    my $name       = $hash->{NAME};        # Fhem device name
    my $fDefault   = ($featurelevel > 5.9 ? 'auto' : '');
    my $bodyDecode = AttrVal($name, 'bodyDecode', $fDefault);

    if ($bodyDecode eq 'auto' or $bodyDecode eq 'Auto') {
        if ($header =~/Content-Type:.*charset=([\w\-\.]+)/i) {
            $bodyDecode = $1;
            Log3 $name, 4, "$name: Read found charset header and set decoding to $bodyDecode (bodyDecode was set to auto)";
        } 
        else {
            $bodyDecode = "";
            Log3 $name, 4, "$name: Read found no charset header (bodyDecode was set to auto)";
        }
    }
    if ($bodyDecode) {
        if ($bodyDecode =~ m{\A [Nn]one \z}xms) {
            Log3 $name, 4, "$name: Read is not decoding the response body (set to none)";
        } 
        else {
            $body = decode($bodyDecode, $body);
            Log3 $name, 4, "$name: Read is decoding the response body as $bodyDecode ";
        }
        #Log3 $name, 5, "$name: Read callback " . ($body ? "new body as utf-8 is: \n" . encode ('utf-8', $body) : "body empty");
    }
    return $body;
}


########################################
# check if a device is open
# not only for devio devices but also 
# tcpserver
sub IsOpen {
    my $hash = shift;
    return 1 if ($hash->{DeviceName} eq 'none');
    return 1 if ($hash->{TCPServer} && $hash->{FD});
    return 1 if ($hash->{TCPChild}  && defined($hash->{CD}));
    return DevIo_IsOpen($hash);
}


####################################################
# format time as string with msecs as fhem.pl does
sub FmtTime($)
{
    my $time = shift // 0;
    my $seconds;
    my $mseconds;
    if ($time =~ /([^\.]+)(\.(.*))?/) {
        $seconds  = $1;
        $mseconds = $3;
    } 
    else {
        $seconds  = $time;
        $mseconds = 0;
    }
    #my $seconds  = int ($time);
    #my $mseconds = $time - $seconds;
    #Log3 undef, 1, "Test: ms = $mseconds";
    
    my @t = localtime($seconds);
    my $tim = sprintf("%02d:%02d:%02d", $t[2],$t[1],$t[0]);
    $tim .= sprintf(".%03d", $mseconds);
    return $tim;
}




1;
