#########################################################################
# $Id$
# fhem Modul für Geräte mit Web-Oberfläche / Webservices
#   
#     This file is part of fhem.
# 
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option)  any later version.
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
#   First version: 25.12.2013
#
#   Todo:       
#               setXYHintExpression zum dynamischen Ändern / Erweitern der Hints
#               extractAllReadings mit Filter / Prefix
#               definierbarer prefix oder Suffix für Readingsnamen wenn sie von unterschiedlichen gets über readingXY erzeugt werden
#               reading mit Status je get (error, no match, ...) oder reading zum nachverfolgen der schritte, fehler, auth etc.
#
#               In _Attr bei Prüfungen auf get auch set berücksichtigen wo nötig, ebenso in der Attr Liste (oft fehlt set)
#               featureAttrs aus hash verarbeiten
#
#               Implement IMap und IExpr for get
#
#               replacement scope attribute?
#               make extracting the sid after a get / update an attribute / option?
#               multi page log extraction?
#               Profiling von Modbus übernehmen?
#

# verwendung von defptr:
# $hash->{defptr}{readingBase}{$reading} gibt zu einem Reading-Namen den Ursprung an, z.B. get oder reading
#                 readingNum                                die zugehörige Nummer, z.B. 01
#                 readingSubNum                             ggf. eine Unternummer (bei reading01-001)
#   wird von MaxAge verwendet um schnell zu einem Reading die zugehörige MaxAge Definition finden zu können
#
# $hash->{defptr}{requestReadings}{$reqType}{$baseReading}
#   wird von DeleteOnError und DeleteIfUnmatched verwendet. 
#       $reqType ist update, get01, set01 etc.
#       $baseReading ist der Reading Basisname wie im Attribute ...Name definiert, 
#       aber ohne eventuelle Extension bei mehreren Matches.
#   Liefert "$context $num", also z.B. get 1 - dort wird nach DeleteOn.. gesucht
#   wichtig um z.B. von reqType "get01" baseReading "Temperatur" auf reading 02 zu kommen 
#       falls get01 keine eigenen parsing definitions enthält
#   DeleteOn... wird dann beim reading 02 etc. spezifiziert.
#
                   
package HTTPMOD;

use strict;
use warnings;

use GPUtils         qw(:all);
use Time::HiRes     qw(gettimeofday);    
use Encode          qw(decode encode);
use SetExtensions   qw(:all);
use HttpUtils;
use FHEM::HTTPMOD::Utils  qw(:all);
use POSIX;
use Data::Dumper;

use Exporter ('import');
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (all => [@EXPORT_OK]);


BEGIN {
    GP_Import( qw(
        fhem
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

        Log3
        RemoveInternalTimer
        InternalTimer
        deviceEvents
        EvalSpecials
        AnalyzePerlCommand
        CheckRegexp
        IsDisabled

        gettimeofday
        FmtDateTime
        GetTimeSpec
        fhemTimeLocal
        time_str2num
        min
        max
        minNum
        maxNum
        abstime2rel
        defInfo
        trim
        ltrim
        rtrim
        UntoggleDirect
        UntoggleIndirect
        IsInt
        fhemNc
        round
        sortTopicNum
        Svn_GetFile
        WriteFile

        DevIo_OpenDev
        DevIo_SimpleWrite
        DevIo_SimpleRead
        DevIo_CloseDev
        SetExtensions
        HttpUtils_NonblockingGet

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

my $Module_Version = '4.1.08 - 1.4.2021';

my $AttrList = join (' ', 
      '(reading|get|set)[0-9]+(-[0-9]+)?Name', 
      '(reading|get|set)[0-9]*(-[0-9]+)?Expr:textField-long',
      '(reading|get|set)[0-9]*(-[0-9]+)?Map', 
      '(reading|get|set)[0-9]*(-[0-9]+)?OExpr:textField-long',
      '(reading|get|set)[0-9]*(-[0-9]+)?OMap:textField-long',
      '(get|set)[0-9]*(-[0-9]+)?IExpr:textField-long',
      '(get|set)[0-9]*(-[0-9]+)?IMap:textField-long', 
      '(reading|get|set)[0-9]*(-[0-9]+)?Format', 
      '(reading|get|set)[0-9]*(-[0-9]+)?Decode', 
      '(reading|get|set)[0-9]*(-[0-9]+)?Encode', 
      '(reading|get)[0-9]*(-[0-9]+)?MaxAge', 
      '(reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacementMode:text,reading,internal,expression,delete', 
      '(reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacement', 
      '(reading|get|set)[0-9]+Regex',
      '(reading|get|set)[0-9]*RegOpt',        # see http://perldoc.perl.org/perlre.html#Modifiers
      '(reading|get|set)[0-9]+XPath', 
      '(reading|get|set)[0-9]+XPath-Strict', 
      '(reading|get|set)[0-9]+JSON', 
      '(reading|get|set)[0-9]*RecombineExpr:textField-long',
      '(reading|get|set)[0-9]*AutoNumLen',
      '(reading|get|set)[0-9]*AlwaysNum',
      '(reading|get|set)[0-9]*DeleteIfUnmatched',
      '(reading|get|set)[0-9]*DeleteOnError',
      'extractAllJSON:0,1,2',
      'extractAllJSONFilter',
      'readingsName.*',               # old 
      'readingsRegex.*',              # old 
      'readingsExpr.*',               # old 
      'requestHeader.*',  
      'requestData.*:textField-long',
      'noShutdown:0,1',    
      'httpVersion',
      'sslVersion',
      'sslArgs',
      'timeout',
      'queueDelay',
      'queueMax',
      'alignTime',
      'minSendDelay',
      'showMatched:0,1',
      'showError:0,1',
      'showBody:0,1',                 # expose the http response body as internal
      'preProcessRegex',
      'parseFunction1',
      'parseFunction2',
      'set[0-9]+Local',               # don't create a request and just set a reading
      '[gs]et[0-9]*URL',
      '[gs]et[0-9]*Data.*:textField-long',
      '[gs]et[0-9]*NoData.*',         # make sure it is an HTTP GET without data - even if a more generic data is defined
      '[gs]et[0-9]*Header.*:textField-long',
      '[gs]et[0-9]*CheckAllReadings:0,1',
      '[gs]et[0-9]*ExtractAllJSON:0,1,2',
      
      '[gs]et[0-9]*URLExpr:textField-long',          # old
      '[gs]et[0-9]*DatExpr:textField-long',          # old
      '[gs]et[0-9]*HdrExpr:textField-long',          # old

      'get[0-9]*Poll:0,1', 
      'get[0-9]*PollDelay',
      
      'set[0-9]+Min',                 # todo: min, max und hint auch für get, Schreibweise der Liste auf (get|set) vereinheitlichen
      'set[0-9]+Max',
      'set[0-9]+Hint',                # Direkte Fhem-spezifische Syntax für's GUI, z.B. '6,10,14' bzw. slider etc.
      'set[0-9]*NoArg:0,1',           # don't expect a value - for set on / off and similar. (default for get)
      '[gs]et[0-9]*TextArg:0,1',      # just pass on a raw text value without validation / further conversion
      'set[0-9]*ParseResponse:0,1',   # parse response to set as if it was a get
      'set[0-9]*Method:GET,POST,PUT', # select HTTP method for the set
      '[gs]et[0-9]*FollowGet',        # do a get after the set/get to update readings / create chains
      'maxGetChain',                  # max length of chains
      
      'reAuthRegex',
      'reAuthAlways:0,1',
      'reAuthJSON',
      'reAuthXPath',
      'reAuthXPath-Strict',
      '[gs]et[0-9]*ReAuthRegex',
      '[gs]et[0-9]*ReAuthJSON',
      '[gs]et[0-9]*ReAuthXPath',
      '[gs]et[0-9]*ReAuthXPath-Strict',
      
      'idRegex',
      'idJSON',
      'idXPath',
      'idXPath-Strict',
      '(get|set|sid)[0-9]*IDRegex',           # old
      '(get|set|sid)[0-9]*IdRegex',
      '(get|set|sid)[0-9]*IdJSON',
      '(get|set|sid)[0-9]*IdXPath',
      '(get|set|sid)[0-9]*IdXPath-Strict',
        
      'sid[0-9]*URL',
      'sid[0-9]*Header.*',
      'sid[0-9]*Data.*:textField-long',
      'sid[0-9]*IgnoreRedirects:0,1',      
      'sid[0-9]*ParseResponse:0,1',           # parse response as if it was a get
      'clearSIdBeforeAuth:0,1',
      'authRetries',
      
      'errLogLevelRegex',
      'errLogLevel',
      
      'replacement[0-9]+Regex',
      'replacement[0-9]+Mode:reading,internal,text,expression,key',   # defaults to text
      'replacement[0-9]+Value',                                   # device:reading, device:internal, text, replacement expression
      '[gs]et[0-9]*Replacement[0-9]+Value',                       # can overwrite a global replacement value - todo: auch für auth?
      
      'do_not_notify:1,0', 
      'disable:0,1',
      'enableControlSet:0,1',
      'enableCookies:0,1',
      'useSetExtensions:1,0 '.
      'handleRedirects:0,1',                  # own redirect handling outside HttpUtils
      'enableXPath:0,1',                      # old 
      'enableXPath-Strict:0,1',               # old
      'enforceGoodReadingNames',
      'dontRequeueAfterAuth',
      'dumpBuffers',                          # debug -> write buffers to files
      'fileHeaderSplit',                      # debug -> read file including header

      'memReading',                           # debuf -> create a reading for the virtual Memory of the Fhem process together with BufCounter if it is used
      'model',                                # for attr templates
      'regexDecode',
      'bodyDecode', 
      'regexCompile') .
      $main::readingFnAttributes;  


#########################################################################
# FHEM module intitialisation - defines functions to be called from FHEM
# GP_Export automatically exports this as Package_Initialize so  is not necessary
sub Initialize {
    my $hash = shift;
    $hash->{DefFn}    = \&HTTPMOD::DefineFn;
    $hash->{UndefFn}  = \&HTTPMOD::UndefFn;
    $hash->{SetFn}    = \&HTTPMOD::SetFn;
    $hash->{GetFn}    = \&HTTPMOD::GetFn;
    $hash->{AttrFn}   = \&HTTPMOD::AttrFn;
    $hash->{NotifyFn} = \&HTTPMOD::NotifyFn;
    $hash->{AttrList} = $AttrList;
    return;
}


#########################################################################
# Define command
# init internal values,
# set internal timer get Updates
sub DefineFn {
    my $hash = shift;                           # reference to the Fhem device hash 
    my $def  = shift;                           # definition string
    my @a    = split( /[ \t]+/, $def );         # the above string split at space or tab
    my $name = $a[0];                           # first item in the definition is the name of the new Fhem device

    return 'wrong syntax: define <name> HTTPMOD URL interval' if ( @a < 3 );

    if ($a[2] eq 'none') {
        Log3 $name, 3, "$name: URL is none, periodic updates will be limited to explicit GetXXPoll attribues (if defined)";
        $hash->{MainURL} = "";
    } else {
        $hash->{MainURL} = $a[2];
    }
    if(int(@a) > 3) {       # numeric interval specified
        if ($a[3] > 0) {
            return 'interval too small, please use something > 5, default is 300' if ($a[3] < 5);
            $hash->{Interval} = $a[3];
        } else {
            Log3 $name, 3, "$name: interval is 0, no periodic updates will done.";
            $hash->{Interval} = 0;
        }
    } else {                # default if no interval specified
        Log3 $name, 3, "$name: no valid interval specified, use default 300 seconds";
        $hash->{Interval} = 300;
    }

    Log3 $name, 3, "$name: Defined " .
        ($hash->{MainURL}  ? "with URL $hash->{MainURL}" : "without URL") .
        ($hash->{Interval} ? " and interval $hash->{Interval}" : "") .
        " featurelevel $featurelevel";

    UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'start');
    
    $hash->{NOTIFYDEV}            = "global";           # NotifyFn nur aufrufen wenn global events (INITIALIZED)
    $hash->{ModuleVersion}        = $Module_Version;
    $hash->{'.getList'}           = '';
    $hash->{'.setList'}           = '';
    $hash->{'.updateHintList'}    = 1;
    $hash->{'.updateReadingList'} = 1;
    $hash->{'.updateRequestHash'} = 1;
    return;
}


#########################################################################
# undefine command when device is deleted
sub UndefFn {                     
    my $hash = shift;                       # reference to the Fhem device hash 
    my $name = shift;                       # name of the Fhem device
    RemoveInternalTimer ("timeout:$name");
    StopQueueTimer($hash, {silent => 1});     
    UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'stop');
    return;                  
}    


##############################################################
# Notify Funktion - reagiert auf Änderung des Featurelevel
sub NotifyFn {
    my $hash   = shift;                         # reference to the HTTPMOD Fhem device hash 
    my $source = shift;                         # reference to the Fhem device hash that created the event
    my $name   = $hash->{NAME};                 # device name of the HTTPMOD Fhem device

    return if($source->{NAME} ne 'global');     # only interested in global events
    my $events = deviceEvents($source, 1);
    return if(!$events);                        # no events

    #Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";  
    foreach my $event (@{$events}) {
        #Log3 $name, 5, "$name: event $event";
        if ($event =~ /ATTR global featurelevel/) {     # update hint list in case featurelevel change implies new defaults
            $hash->{'.updateHintList'} = 1;
        }
    }  
    #return if (!grep(m/^INITIALIZED|REREADCFG|(MODIFIED $name)|(DEFINED $name)$/, @{$source->{CHANGED}}));
    # DEFINED is not triggered if init is not done.
    return;
}


#########################################################################
sub LogOldAttr {                     
    my $hash = shift;               # reference to the HTTPMOD Fhem device hash 
    my $old  = shift;               # old attr name
    my $new  = shift;               # new attr name
    my $name = $hash->{NAME};       # name of the Fhem device
    Log3 $name, 3, "$name: the attribute $old should no longer be used." . ($new ? " Please use $new instead" : "");
    Log3 $name, 3, "$name: For most old attributes you can specify enableControlSet and then set device upgradeAttributes to automatically modify the configuration";
    return;
}


###################################
# precompile regex attr value
sub PrecompileRegexAttr {
    my $hash   = shift;             # reference to the HTTPMOD Fhem device hash 
    my $aName  = shift;             # name of the object that contains the regex (e.g. attr name)          
    my $aVal   = shift;             # the regex
    my $name   = $hash->{NAME};     # Fhem device name
    my $regopt = '';
    
    my $regDecode = AttrVal($name, 'regexDecode', "");
    if ($regDecode && $regDecode !~ /^[Nn]one$/) {
        $aVal = decode($regDecode, $aVal);
        Log3 $name, 5, "$name: PrecompileRegexAttr is decoding regex $aName as $regDecode";
    }
    
    if ($aName =~ /^(reading|get|set)([0-9]+).*Regex$/) {           # get context and num so we can look for corespondig regOpt attribute
        my $context = $1;
        my $num     = $2;
        $regopt = GetFAttr($name, $context, $num, "RegOpt", "");
        $regopt =~ s/[gceor]//g;                                    # remove gceor options - they will be added when using the regex
        # see https://www.perlmonks.org/?node_id=368332
    }
    
    local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: PrecompileRegexAttr for $aName $aVal created warning: @_"; };
    if ($regopt) {
        eval "\$hash->{CompiledRegexes}{\$aName} = qr/$aVal/$regopt";   ## no critic - some options need to be compiled in - special syntax needed -> better formulate options as part of regex ...
    } else {
        eval {$hash->{CompiledRegexes}{$aName} = qr/$aVal/};            # no options - use easy way.
    }
    if (!$@) {
        if ($aVal =~ /^xpath:(.*)/ || $aVal =~ /^xpath-strict:(.*)/) {
            Log3 $name, 3, "$name: PrecompileRegexAttr cannot store precompiled regex because outdated xpath syntax is used in attr $aName $aVal. Please upgrade attributes";
            delete $hash->{CompiledRegexes}{$aName};
        } else {
            #Log3 $name, 5, "$name: PrecompileRegexAttr precompiled $aName /$aVal/$regopt to $hash->{CompiledRegexes}{$aName}";
        }
    }
    return;
}

    
#########################################################################
# Attr command 
# simple attributes like requestHeader and requestData need no special treatment here
# readingsExpr, readingsRegex.* or reAuthRegex need validation though.
# if validation fails, return something so CommandAttr in fhem.pl doesn't assign a value to $attr
sub AttrFn {
    my $cmd   = shift;                  # 'set' or 'del'
    my $name  = shift;                  # the Fhem device name
    my $aName = shift;                  # attribute name
    my $aVal  = shift // '';            # attribute value
    my $hash  = $defs{$name};           # reference to the Fhem device hash
    
    Log3 $name, 5, "$name: attr $name $aName $aVal";
    if ($cmd eq 'set') {        
        if ($aName =~ /^regexDecode$/) {
            delete $hash->{CompiledRegexes};        # recompile everything with the right decoding
            #Log3 $name, 4, "$name: Attr got DecodeRegexAttr -> delete all potentially precompiled regexs";
        }
        if ($aName =~ /Regex/) {                    # catch all Regex like attributes
            delete $hash->{CompiledRegexes}{$aName};
            #Log3 $name, 4, "$name: Attr got regex attr -> delete potentially precompiled regex for $aName";
            
            my $regexErr = CheckRegexp($aVal, "attr $aName");       # check if Regex is valid
            return "$name: $aName Regex: $regexErr" if ($regexErr);
            
            if ($aName =~ /([gs]et[0-9]*)?[Rr]eplacement[0-9]*Regex$/) {
                $hash->{'.ReplacementEnabled'} = 1;
            }
            if ($aName =~ /(.+)IDRegex$/) {         # conversions for legacy things
                LogOldAttr($hash, $aName, "${1}IdRegex");
            }
            if ($aName =~ /readingsRegex.*/) {
                LogOldAttr($hash, $aName, "reading01Regex syntax");
            }
        } 
        elsif ($aName =~ /readingsName.*/) {    
                LogOldAttr($hash, $aName, "reading01Name syntax");
        } 
        elsif ($aName =~ /RegOpt$/) {    
            if ($aVal !~ /^[msxdualsig]*$/) {
                Log3 $name, 3, "$name: illegal RegOpt in attr $name $aName $aVal";
                return "$name: illegal RegOpt in attr $name $aName $aVal";
            }
        } 
        elsif ($aName =~ /Expr/) { 
            my $timeDiff = 0;       # only for expressions using it
            my @matchlist;
            return "Invalid Expression $aVal" 
                if (!EvalExpr($hash, {expr => $aVal, '$timeDiff' => $timeDiff, '@matchlist' => \@matchlist,
                            checkOnly => 1, action => "attr $aName"} ));
            if ($aName =~ /readingsExpr.*/) {
                LogOldAttr($hash, $aName, "reading01Expr syntax");
            } elsif ($aName =~ /^(get[0-9]*)Expr/) {
                LogOldAttr($hash, $aName, "${1}OExpr");
            } elsif ($aName =~ /^(reading[0-9]*)Expr/) {
                LogOldAttr($hash, $aName, "${1}OExpr");
            } elsif ($aName =~ /^(set[0-9]*)Expr/) {
                LogOldAttr($hash, $aName, "${1}IExpr");
            }
        } 
        elsif ($aName =~ /Map$/) {
            if ($aName =~ /^(get[0-9]*)Map/) {
                LogOldAttr($hash, $aName, "${1}OMap");
            } elsif ($aName =~ /^(reading[0-9]*)Map/) {
                LogOldAttr($hash, $aName, "${1}OMap");
            } elsif ($aName =~ /^(set[0-9]*)Map/) {
                LogOldAttr($hash, $aName, "${1}IMap");
            }           
        } 
        elsif ($aName =~ /replacement[0-9]*Mode/) {
            if ($aVal !~ /^(reading|internal|text|expression|key)$/) {
                Log3 $name, 3, "$name: illegal mode in attr $name $aName $aVal";
                return "$name: illegal mode in attr $name $aName $aVal";
            }    
        } 
        elsif ($aName =~ /([gs]et[0-9]*)?[Rr]eplacement([0-9]*)Value/) {
            Log3 $name, 5, "$name: validating attr $name $aName $aVal";
            if (AttrVal($name, "replacement${2}Mode", "text") eq "expression") {
                return "Invalid Expression $aVal" if (!EvalExpr($hash, 
                            {expr => $aVal, action => "attr $aName", checkOnly => 1}));
            }
        } 
        elsif ($aName =~ /(get|reading)[0-9]*JSON$/ 
                || $aName =~ /[Ee]xtractAllJSON$/ 
                || $aName =~ /[Rr]eAuthJSON$/
                || $aName =~ /[Ii]dJSON$/) {
            eval "use JSON";                        ## no critic - need this at runtime!
            if($@) {
                return "Please install JSON Library to use JSON (apt-get install libjson-perl) - error was $@";
            }
            $hash->{'.JSONEnabled'} = 1;
        } 
        elsif ($aName eq "enableCookies") {
            if ($aVal eq "0") {
                delete $hash->{HTTPCookieHash};
            }
        } 
        elsif ($aName eq "showBody") {
            if ($aVal eq "0") {
                delete $hash->{httpbody};
            }
        } 
        elsif ($aName eq "enableXPath" 
                || $aName =~ /(get|reading)[0-9]+XPath$/
                || $aName =~ /[Rr]eAuthXPath$/
                || $aName =~ /[Ii]dXPath$/) {
            eval "use HTML::TreeBuilder::XPath";                    ## no critic - need this at runtime!
            if($@) {
                return "Please install HTML::TreeBuilder::XPath to use the xpath-Option (apt-get install libxml-TreeBuilder-perl libhtml-treebuilder-xpath-perl) - error was $@";
            }
            $hash->{'.XPathEnabled'} = ($aVal ? 1 : 0);    
        } 
        elsif ($aName eq "enableXPath-Strict" 
                || $aName =~ /(get|reading)[0-9]+XPath-Strict$/
                || $aName =~ /[Rr]eAuthXPath-Strict$/
                || $aName =~ /[Ii]dXPath-Strict$/) {
            eval "use XML::XPath;use XML::XPath::XMLParser";        ## no critic - need this at runtime!
            if($@) {
                return "Please install XML::XPath and XML::XPath::XMLParser to use the xpath-strict-Option (apt-get install libxml-parser-perl libxml-xpath-perl) - error was $@";
            }
            $XML::XPath::SafeMode = 1;
            $hash->{'.XPathStrictEnabled'} = ($aVal ? 1 : 0);    
        } 
        elsif ($aName =~ /^(reading|get)[0-9]*(-[0-9]+)?MaxAge$/) {
            if ($aVal !~ '([0-9]+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";    
            }
            $hash->{'.MaxAgeEnabled'} = 1;
        } 
        elsif ($aName =~ /^(reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacementMode$/) {
            if ($aVal !~ /^(text|reading|internal|expression|delete)$/) {
                Log3 $name, 3, "$name: illegal mode in attr $name $aName $aVal";
                return "$name: illegal mode in attr $name $aName $aVal, choose on of text, expression";
            }
        } 
        elsif ($aName =~ /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteOnError$/) {
            if ($aVal !~ '([0-9]+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";    
            }
            $hash->{DeleteOnError} = ($aVal ? 1 : 0);
        } 
        elsif ($aName =~ /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteIfUnmatched$/) {
            if ($aVal !~ '([0-9]+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";    
            }
            $hash->{DeleteIfUnmatched} = ($aVal ? 1 : 0);
        } 
        elsif ($aName eq 'alignTime') {
            my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($aVal);
            return "Invalid Format $aVal in $aName : $alErr" if ($alErr);
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
            $hash->{'.TimeAlign'} = fhemTimeLocal($alSec, $alMin, $alHr, $mday, $mon, $year);
            #$hash->{TimeAlignFmt} = FmtDateTime($hash->{'.TimeAlign'});
            UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'start');      # change timer for alignment
        } 
        elsif ($aName =~ /^(reading|get)([0-9]+)(-[0-9]+)?Name$/) {
            $hash->{".updateRequestHash"} = 1;
        }
        my $err = ManageUserAttr($hash, $aName);        # todo: handle deletion as well
        return $err if ($err);    
    } 
    elsif ($cmd eq 'del') {                             # Deletion of Attributes
        #Log3 $name, 5, "$name: del attribute $aName";
        if ($aName =~                    /((reading|get)[0-9]*JSON$) | [Ee]xtractAllJSON$ | [Rr]eAuthJSON$ | [Ii]dJSON$/xms) {
            if (!(grep {!/$aName/} grep {/((reading|get)[0-9]*JSON$) | [Ee]xtractAllJSON$ | [Rr]eAuthJSON$ | [Ii]dJSON$/xms} keys %{$attr{$name}} )) {
                delete $hash->{'.JSONEnabled'};
            }
        } 
        elsif ($aName =~                 /(get|reading)[0-9]+XPath$ | enableXPath | [Rr]eAuthXPath$ | [Ii]dXPath$/xms) {
            if (!(grep {!/$aName/} grep {/(get|reading)[0-9]+XPath$ | enableXPath | [Rr]eAuthXPath$ | [Ii]dXPath$/xms} keys %{$attr{$name}})) {
                delete $hash->{'.XPathEnabled'};
            }
        } 
        elsif ($aName =~                 /(get|reading)[0-9]+XPath-Strict$ | enableXPath-Strict | [Rr]eAuthXPath-Strict$ | [Ii]dXPath-Strict$/xms) {                
            if (!(grep {!/$aName/} grep {/(get|reading)[0-9]+XPath-Strict$ | enableXPath-Strict | [Rr]eAuthXPath-Strict$ | [Ii]dXPath-Strict$/xms} 
                    keys %{$attr{$name}})) {
                delete $hash->{'.XPathStrictEnabled'};
            }
        } 
        elsif ($aName eq 'enableCookies') {
            delete $hash->{HTTPCookieHash};
        } 
        elsif ($aName eq 'showBody') {
            delete $hash->{httpbody};
        } 
        elsif ($aName =~                 /(reading|get)[0-9]*(-[0-9]+)?MaxAge$/) {
            if (!(grep {!/$aName/} grep {/(reading|get)[0-9]*(-[0-9]+)?MaxAge$/} keys %{$attr{$name}})) {
                delete $hash->{'.MaxAgeEnabled'};
            }
        } 
        elsif ($aName =~                 /([gs]et[0-9]*)?[Rr]eplacement[0-9]*Regex/) {
            if (!(grep {!/$aName/} grep {/([gs]et[0-9]*)?[Rr]eplacement[0-9]*Regex/} keys %{$attr{$name}})) {
                delete $hash->{'.ReplacementEnabled'};
            }
        } 
        elsif ($aName =~                 /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteOnError$/) {
            if (!(grep {!/$aName/} grep {/^(reading|get|set)[0-9]*(-[0-9]+)?DeleteOnError$/} keys %{$attr{$name}})) {
                delete $hash->{DeleteOnError};              
            }
        } 
        elsif ($aName =~                 /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteIfUnmatched$/) {
            if (!(grep {!/$aName/} grep {/^(reading|get|set)[0-9]*(-[0-9]+)?DeleteIfUnmatched$/} keys %{$attr{$name}})) {
                delete $hash->{DeleteIfUnmatched};              
            }
        } 
        elsif ($aName eq 'alignTime') {
            delete $hash->{'.TimeAlign'};
            #delete $hash->{TimeAlignFmt};    
        }
    }
    if ($aName =~ /^[gs]et/ || $aName eq "enableControlSet") {
        $hash->{".updateHintList"} = 1;
    }
    if ($aName =~ /^(get|reading)/) {
        $hash->{".updateReadingList"} = 1;
    }  
    return;
}



##############################################
# Upgrade attribute names from older versions
sub UpgradeAttributes {
    my $hash = shift;
    my $name = $hash->{NAME};
    my %dHash;
    my %numHash;
    
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ /(.+)IDRegex$/) {
            my $new = $1 . "IdRegex";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val");          # also adds new attr to userattr list through _Attr function
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } 
        elsif ($aName =~ /(.+)Regex$/) {
            my $ctx = $1;
            my $val = $attr{$name}{$aName};
            #Log3 $name, 3, "$name: upgradeAttributes check attr $aName, val $val";
            if ($val =~ /^xpath:(.*)/) {
                $val      = $1;
                my $new   = $ctx . "XPath";
                CommandAttr(undef, "$name $new $val");
                CommandAttr(undef, "$name $ctx" . "RecombineExpr join(\",\", \@matchlist)");
                CommandDeleteAttr(undef, "$name $aName");
                $dHash{$aName} = 1;
                Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
            }
            if ($val =~ /^xpath-strict:(.*)/) {
                $val      = $1;
                my $new   = $ctx . "XPath-Strict";
                CommandAttr(undef, "$name $new $val");
                CommandAttr(undef, "$name $ctx" . "RecombineExpr join(\",\", \@matchlist)");
                CommandDeleteAttr(undef, "$name $aName");
                $dHash{$aName} = 1;
                Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
            }
        } 
        elsif ($aName eq "enableXPath" || $aName eq "enableXPath-Strict" ) {
            CommandDeleteAttr(undef, "$name $aName");
            Log3 $name, 3, "$name: removed attribute name $aName";    
        } 
        elsif ($aName =~ /(set[0-9]*)Expr$/) {
            my $new = $1 . "IExpr";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } 
        elsif ($aName =~ /(get[0-9]*)Expr$/) {
            my $new = $1 . "OExpr";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } 
        elsif ($aName =~ /(reading[0-9]*)Expr$/) {
            my $new = $1 . "OExpr";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";

        } 
        elsif ($aName =~ /(set[0-9]*)Map$/) {
            my $new = $1 . "IMap";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } 
        elsif ($aName =~ /(get[0-9]*)Map$/) {
            my $new = $1 . "OMap";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } 
        elsif ($aName =~ /(reading[0-9]*)Map$/) {
            my $new = $1 . "OMap";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } 
        elsif ($aName =~ /^readings(Name|Expr|Regex)(.*)$/) {
            my $typ = $1;
            my $sfx = $2;
            my $num;
            if (defined($numHash{$sfx})) {
                $num = $numHash{$sfx};
            } else {
                my $max = 0;
                foreach my $a (keys %{$attr{$name}}) {
                    if ($a =~ /^reading([0-9]+)\D+$/) {
                        $max = $1 if ($1 > $max);
                    }
                }
                $num = sprintf("%02d", $max + 1);
                $numHash{$sfx} = $num;
            }
            my $new = "reading${num}${typ}";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        }
    }
    $dHash{"enableXpath"} = 1;
    $dHash{"enableXpath-Strict"} = 1;
    
    my $ualist = $attr{$name}{userattr} // '';
    my %uahash;
    foreach my $a (split(" ", $ualist)) {
        if (!$dHash{$a}) {
            $uahash{$a} = 1;
        } else {
            Log3 $name, 3, "$name: dropping $a from userattr list";
        }
    }
    $attr{$name}{userattr} = join(" ", sort keys %uahash);    
    #Log3 $name, 3, "$name: UpgradeAttribute done, userattr list is $attr{$name}{userattr}";
    return;
}


#############################################################
# get attribute based specification
# for format, map or similar
# with generic and absolute default (empty variable num part)
# if num is like 1-1 then check for 1 if 1-1 not found 
sub GetFAttr {
    my ($name, $prefix, $num, $type, $val) = @_;
    # first look for attribute with the full num in it
    if (defined ($attr{$name}{$prefix . $num . $type})) {
          $val = $attr{$name}{$prefix . $num . $type};
    # if not found then check if num contains a subnum 
    # (for regexes with multiple capture groups etc) and look for attribute without this subnum
    } elsif (($num =~ /^([0-9]+)-[0-9]+$/) && defined ($attr{$name}{$prefix .$1 . $type})) {
          $val = $attr{$name}{$prefix . $1 . $type};
    # if again not found then look for generic attribute without num
    } elsif (defined ($attr{$name}{$prefix . $type})) {
          $val = $attr{$name}{$prefix . $type};
    }
    return $val;
}


#########################################################################
# replace strings as defined in Attributes for URL, Header and Data
# type is request type and can be set01, get03, auth01, update
# corresponding context is set, get (or reading, but here we use '' instead)
sub DoReplacement {
    my $hash    = shift;                    # reference to the Fhem device hash
    my $type    = shift;                    # type of replacement (get / set / auth with number)
    my $string  = shift;                    # source string
    my $name    = $hash->{NAME};            # name of the fhem device
    my $context = '';                       # context of replacement (type without the number)
    my $input   = $string;                  # save for logging at the end
    
    if ($type =~ /(auth|set|get)(.*)/) {
        $context = $1;                      # context is type without num
        # for type update there is no num so no individual replacement - only one for the whole update request
    }

    #Log3 $name, 4, "$name: Replace called for request type $type";
    # Loop through all Replacement Regex attributes
    foreach my $rr (sort keys %{$attr{$name}}) {
        next if ($rr !~ /^replacement([0-9]*)Regex$/);
        my $rNum  = $1;
        my $regex = GetRegex($name, "replacement", $rNum, "Regex", "");
        my $mode  = AttrVal($name, "replacement${rNum}Mode", "text");
        #Log3 $name, 5, "$name: Replace: rr=$rr, rNum $rNum, look for ${type}Replacement${rNum}Value";
        next if (!$regex);

        my $value = "";         # value can be specific for a get / set / auth step (with a number in $type)

        #Log3 $name, 5, "$name: Replace: check value as ${type}Replacement${rNum}Value";
        if ($context && defined ($attr{$name}{"${type}Replacement${rNum}Value"})) {
            # get / set / auth mit individuellem Replacement für z.B. get01
            $value = $attr{$name}{"${type}Replacement${rNum}Value"};
        } else {
            #Log3 $name, 5, "$name: Replace: check value as ${context}Replacement${rNum}Value";
            if ($context && defined ($attr{$name}{"${context}Replacement${rNum}Value"})) {
                # get / set / auth mit generischem Replacement für alle gets / sets (without the number)
                $value = $attr{$name}{"${context}Replacement${rNum}Value"};
            } else {
                #Log3 $name, 5, "$name: Replace: check value as replacement${rNum}Value";
                if (defined ($attr{$name}{"replacement${rNum}Value"})) {
                    # ganz generisches Replacement
                    $value = $attr{$name}{"replacement${rNum}Value"};
                } else {
                    #Log3 $name, 5, "$name: Replace: no matching value attribute found";
                }
            }
        }
        Log3 $name, 5, "$name: Replace called for type $type, regex $regex, mode $mode, " .
            ($value ? "value $value" : "empty value") . " input: $string";
        
        my $match = 0;
        if ($mode eq 'text') {
            $match = ($string =~ s/$regex/$value/g);
        } 
        elsif ($mode eq 'reading') {
            my $device  = $name;
            my $reading = $value;
            if ($value =~ /^([^\:]+):(.+)$/) {
                $device  = $1;
                $reading = $2;
            }
            my $rvalue = ReadingsVal($device, $reading, "");
            if ($string =~ s/$regex/$rvalue/g) {
                Log3 $name, 5, "$name: Replace: reading value is $rvalue";
                $match = 1;
            }
        } 
        elsif ($mode eq 'internal') {
            my $device   = $name;
            my $internal = $value;
            if ($value =~ /^([^\:]+):(.+)$/) {
                $device   = $1;
                $internal = $2;
            }
            my $rvalue = InternalVal($device, $internal, "");
            if ($string =~ s/$regex/$rvalue/g) {
                Log3 $name, 5, "$name: Replace: internal value is $rvalue";
                $match = 1;
            }
        } 
        elsif ($mode eq 'expression') {
            $value = 'package main; ' . ($value // '');
            local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: Replacement $rNum with expression $value and regex $regex created warning: @_"; };
            # if expression calls other fhem functions, creates readings or other, then the warning handler will create misleading messages!
            $match = eval { $string =~ s/$regex/$value/gee };
            if ($@) {
                Log3 $name, 3, "$name: Replace: invalid regex / expression: /$regex/$value/gee - $@";
            }
        } 
        elsif ($mode eq 'key') {
            my $rvalue = ReadKeyValue($hash, $value);
            if ($string =~ s/$regex/$rvalue/g) {
                Log3 $name, 5, "$name: Replace: key $value value is $rvalue";   
                $match = 1;
            }
        }
        Log3 $name, 5, "$name: Replace: match for type $type, regex $regex, mode $mode, " .
            ($value ? "value $value," : "empty value,") . " input: $input, result is $string" if ($match);
    }
    return $string;
}


#########################################################################
sub PrepareRequest {
    my $hash    = shift;                # reference to Fhem device hash
    my $context = shift;                # get / set / reading
    my $num     = shift // 0;           # number of get / set / ...
    my $name    = $hash->{NAME};        # Fhem device name
    my ($url, $header, $data, $exp);

    if ($context eq 'reading') {        # if called from GetUpdate - not get / set / auth
        $url    = $hash->{MainURL};
        $header = join ("\r\n", map {$attr{$name}{$_}} sort grep {/requestHeader/} keys %{$attr{$name}});
        $data   = join ("\r\n", map {$attr{$name}{$_}} sort grep {/requestData/} keys %{$attr{$name}});
    } 
    else {                              # called for get / set / auth
        # hole alle Header bzw. generischen Header ohne Nummer 
        $header = join ("\r\n", map {$attr{$name}{$_}} sort grep {/${context}${num}Header/} keys %{$attr{$name}});
        if (length $header == 0) {
            $header = join ("\r\n", map {$attr{$name}{$_}} sort grep {/${context}Header/} keys %{$attr{$name}});
        }
        if (! GetFAttr($name, $context, $num, "NoData")) {
            # hole Bestandteile der Post data 
            $data = join ("\r\n", map {$attr{$name}{$_}} sort grep {/${context}${num}Data/} keys %{$attr{$name}});
            if (length $data == 0) {
                $data = join ("\r\n", map {$attr{$name}{$_}} sort grep {/${context}Data/} keys %{$attr{$name}});
            }
        }
        # hole URL
        $url = GetFAttr($name, $context, $num, "URL");
        $url = $hash->{MainURL} if (!$url);
    }
    #Log3 $name, 5, "$name: PrepareRequest got url $url, header $header and data $data";
    $header = EvalExpr($hash, {expr => GetFAttr($name, $context, $num, "HdrExpr"), val => $header, action => 'HdrExpr'});
    $data   = EvalExpr($hash, {expr => GetFAttr($name, $context, $num, "DatExpr"), val => $data,   action => 'DatExpr'});
    $url    = EvalExpr($hash, {expr => GetFAttr($name, $context, $num, "URLExpr"), val => $url,    action => 'URLExpr'});

    my $type;
    if ($context eq 'reading') {
        $type = "update";
    } elsif ($context eq 'sid') {
        $type = "auth$num";
    } else {
        $type = "$context$num";
    }
    return {'url' => $url, 'header' => $header, 'data' => $data, 'type' => $type, 'context' => $context, 'num' => $num};
}


#########################################################################
# create a new authenticated session by queueing the sid stuff
sub DoAuth {
    my $hash = shift;               # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $name = $hash->{NAME};       # fhem device name
    
    # get all authentication steps
    my %steps;
    foreach my $attr (keys %{$attr{$name}}) {
        if ($attr =~ /^sid([0-9]+).+/) {
            $steps{$1} = 1;
        }
    }
    Log3 $name, 4, "$name: DoAuth called with Steps: " . join (" ", sort keys %steps);
  
    $hash->{sid} = '' if AttrVal($name, "clearSIdBeforeAuth", 0);
    foreach my $step (sort {$b cmp $a} keys %steps) {   # reverse sort because requests are prepended
        my $request = PrepareRequest($hash, "sid", $step);
        if ($request->{'url'}) {
            $request->{'ignoreRedirects'} = AttrVal($name, "sid${step}IgnoreRedirects", 0);
            $request->{'priority'} = 1;                 # prepend at front of queue
            AddToSendQueue($hash, $request);
            # todo: http method for sid steps?
        } else {
            Log3 $name, 3, "$name: no URL for Auth $step";
        }
    }
    $hash->{LastAuthTry} = FmtDateTime(gettimeofday());
    HandleSendQueue("direct:".$name);       # AddToQueue with priority did not call this.
    return;
}


########################################
# create hint list for set / get ?
sub UpdateHintList {
    my $hash = shift;               # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $name = $hash->{NAME};       # fhem device name

    Log3 $name, 5, "$name: UpdateHintList called";
    $hash->{'.getList'} = '';
    my $fDefault = ($featurelevel > 5.9 ? 1 : 0);
    if (AttrVal($name, 'enableControlSet', $fDefault)) {                        # spezielle Sets freigeschaltet?
        $hash->{".setList"} = "interval reread:noArg stop:noArg start:noArg clearCookies:noArg upgradeAttributes:noArg storeKeyValue ";
        #Log3 $name, 5, "$name: UpdateHintList added control sets";
    } else {
        #Log3 $name, 5, "$name: UpdateHintList ignored control sets ($featurelevel, $fDefault)";
        $hash->{'.setList'} = '';
    }
    foreach my $aName (keys %{$attr{$name}}) {
        next if ($aName !~ /^([gs]et)([0-9]+)Name$/);
        my $context = $1;
        my $num     = $2;                     
        my $oName   = $attr{$name}{$aName};
        my $opt;
                 
        if ($context eq 'set') {
            my $map = '';
            $map = AttrVal($name, "${context}${num}Map", "") if ($context ne "get"); # old Map for set is now IMap (Input)
            $map = AttrVal($name, "${context}${num}IMap", $map);                     # new syntax ovverides old one
            if ($map) {                                                         
                my $hint = MapToHint($map);                                     # create hint from map
                $opt  = $oName . ":$hint";                                      # opt is Name:Hint (from Map)
            } elsif (AttrVal($name, "${context}${num}NoArg", undef)) {          # NoArg explicitely specified for a set?
                $opt = $oName . ':noArg';                            
            } else {
                $opt = $oName;                                                  # nur den Namen für opt verwenden.
            }
        } 
        elsif ($context eq 'get') {
            if (AttrVal($name, "${context}${num}TextArg", undef)) {             # TextArg explicitely specified for a get?
                $opt = $oName;                                                  # nur den Namen für opt verwenden.
            } else {
                $opt = $oName . ':noArg';                                       # sonst noArg bei get
            }           
        }
        if (AttrVal($name, "${context}${num}Hint", undef)) {                    # gibt es einen expliziten Hint?
            $opt = $oName . ":" . AttrVal($name, "${context}${num}Hint", undef);
        }
        $hash->{".${context}List"} .= $opt . ' ';                               # save new hint list
    }
    delete $hash->{'.updateHintList'};
    Log3 $name, 5, "$name: UpdateHintList: setlist = " . $hash->{'.setList'};
    Log3 $name, 5, "$name: UpdateHintList: getlist = " . $hash->{'.getList'};
    return;
}


########################################################################################
# update hashes to point back from reading name to attr defining its name and properties
# called after Fhem restart or attribute changes to handle existing readings 
sub UpdateRequestHash {
    my $hash = shift;                       # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $name = $hash->{NAME};               # fhem device name

    Log3 $name, 5, "$name: UpdateRequestHash called";
    return if (!$hash->{READINGS});

    my @readingList = sort keys %{$hash->{READINGS}};
    my @attrList    = sort keys %{$attr{$name}};    
    ATTRLOOP:                                       # go through all attributes like reading|get|set...Name
    foreach my $aName (@attrList) {                 # need reregx match inside loop to get capture groups!
        next ATTRLOOP if ($aName !~ m{\A (reading|get|set) ([0-9]+) (-[0-9]+)? Name \z}xms);
        my $context = $1;                           # split attr name in reading/get/set, a num and potentially -subnum
        my $num     = $2;
        my $nSubNum = $3 // '';                     # named SubReading?    
        my $reqType = ($context eq 'reading' ? 'update' : $context . $num);
        
        my $baseReading = $attr{$name}{$aName};     # ...Name attribute: base reading Name or explicitely named subreading
        
        if ($defs{$name}{READINGS}{$baseReading}) { # reading with name from attr exists
            Log3 $name, 5, "$name: UpdateRequestHash for direct reading $baseReading from attr $aName $baseReading";
            
            $hash->{defptr}{readingBase}{$baseReading}   = $context;
            $hash->{defptr}{readingNum}{$baseReading}    = $num;
            $hash->{defptr}{readingSubNum}{$baseReading} = $nSubNum if ($nSubNum);
            $hash->{defptr}{requestReadings}{$reqType}{$baseReading} = "$context ${num}" . ($nSubNum ? "-$nSubNum" : '');
        }
        if (!$nSubNum) {                            # if given "Name"-attribute doesn't have a subNum
            READINGLOOP:                            # go through the potential subreadings derived from the above ..Name attribute with added -Num
            foreach my $reading (@readingList) {    
                next READINGLOOP if ($reading !~ m{\A ${baseReading} (-[0-9]+) \z}xms); 
                my $subNum = $1;
                Log3 $name, 5, "$name: UpdateRequestHash for reading $reading from attr $aName $baseReading with automatic subNum $subNum";
                $hash->{defptr}{readingBase}{$reading}   = $context;
                $hash->{defptr}{readingNum}{$reading}    = $num;
                $hash->{defptr}{readingSubNum}{$reading} = $subNum;
                $hash->{defptr}{requestReadings}{$reqType}{$reading} = "$context ${num}${subNum}";
                # deleteOn ... will later check for e.g. reading02-001DeleteOnError but also for reading02-DeleteOnError (without subNum)
            }
        }
        if ($aName =~ m{\A (get|set) ([0-9]+) Name \z}xms &&                      # special Handling for get / set with CheckAllReadings
                GetFAttr($name, $context, $num, 'CheckAllReadings')) {
            ATTRLOOP2:
            foreach my $raName (@attrList) {
                next ATTRLOOP2 if ($aName !~ m{\A (reading) ([0-9]+) (-[0-9]+)? Name \z}xms);
                my $rbaseReading = $attr{$name}{$raName};               # common base reading Name   
                my $rNum     = $2;
                my $rnSubNum = ($3 ? $3 : "");                          # named SubReading?    
                
                if ($defs{$name}{READINGS}{$rbaseReading}) {
                    $hash->{defptr}{requestReadings}{$reqType}{$rbaseReading} = "reading $rNum" .
                        ($rnSubNum ? "-$rnSubNum" : "");
                }
                if (!$rnSubNum) {                                       # go through the potential subreadings - the Name attribute was for a base Reading without explicit subNum
                    foreach my $reading (@readingList) {
                        next if ($reading !~ m{\A ${rbaseReading} (-[0-9]+) \z}xms);
                        # point from reqType get/set and reading Name like "Temp-001" to the definition in readingXX or even potential readingXX-YYDeleteOnError
                        $hash->{defptr}{requestReadings}{$reqType}{$reading} = "reading ${rNum}$1";
                    }
                }
            }
        }
    }
    delete $hash->{'.updateRequestHash'};
    return;
}


################################################
# SET command - handle predefined control sets
sub ControlSet {
    my $hash    = shift;            # hash reference passed to HttpUtils_NonblockingGet (our device hash)         
    my $setName = shift;            # name of set option
    my $setVal  = shift;            # value to set
    my $name    = $hash->{NAME};    # fhem device name
    
    if ($setName eq 'interval') {
        if (!$setVal || $setVal !~ /^[0-9\.]+/) {
            Log3 $name, 3, "$name: no interval (sec) specified in set, continuing with $hash->{Interval} (sec)";
            return "No Interval specified";
        } 
        if (int $setVal <= 5) {
            Log3 $name, 3, "$name: interval $setVal (sec) to small (must be >5), continuing with $hash->{Interval} (sec)";
            return "interval too small";
        }
        $hash->{Interval} = $setVal;
        Log3 $name, 3, "$name: timer interval changed to $hash->{Interval} seconds";
        UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'start');      # set timer for new interval
        return "0";
    } 
    if ($setName eq 'reread') {
        GetUpdate("reread:$name");
        return "0";
    } 
    if ($setName eq 'stop') {
        UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'stop');
        return "0";     
    } 
    if ($setName eq 'start') {
        UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'start');      # set timer for new interval
        return "0";
    } 
    if ($setName eq 'clearCookies') {
        delete $hash->{HTTPCookieHash};
        return "0";
    } 
    if ($setName eq 'upgradeAttributes') {
        UpgradeAttributes($hash);
        return "0";
    } 
    if ($setName eq 'storeKeyValue') {
        my $key;
        if ($setVal !~ /([^ ]+) +(.*)/) {
            return "Please give a key and a value to storeKeyValue";
        }
        $key = $1;
        my $err = StoreKeyValue($hash, $key, $2);
        return $err if ($err);
        return "0";
    }
    return;   # no control set identified - continue with other sets
}


#########################################################################
# SET command
sub SetFn {
    my @setValArr = @_;                     # remainder is set values 
    my $hash      = shift @setValArr;       # reference to Fhem device hash
    my $name      = shift @setValArr;       # Fhem device name
    my $setName   = shift @setValArr;       # name of the set option
    my $setVal    = join(' ', @setValArr);  # set values as one string
    my (%rmap, $setNum, $setOpt, $rawVal);
    return "\"set $name\" needs at least an argument" if (!$setName);
   
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "")
        if ($setName ne "?");
    my $fDefault = ($featurelevel > 5.9 ? 1 : 0);
    if (AttrVal($name, "enableControlSet", $fDefault)) {    # spezielle Sets freigeschaltet?
        my $error = ControlSet($hash, $setName, $setVal);
        if (defined ($error)) {
            return if ($error eq "0");          # control set found and done.
            return $error if ($error);          # error        
        }                                       # continue if function returned undef
    }
    # Vorbereitung: suche den übergebenen setName in den Attributen und setze setNum
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ /^set([0-9]+)Name$/) {                # ist das Attribut ein "setXName" ?
            if ($setName eq $attr{$name}{$aName}) {         # ist es der im konkreten Set verwendete setName?
                $setNum = $1;                               # gefunden -> merke Nummer X im Attribut
            }            
        }
    }
    if(!defined ($setNum)) {                                # gültiger set Aufruf? ($setNum oben schon gesetzt?)
        UpdateHintList($hash) if ($hash->{".updateHintList"});
        if (AttrVal($name, "useSetExtensions", 1)) {
            #Log3 $name, 5, "$name: set is passing to setExtensions";
            return SetExtensions($hash, $hash->{".setList"}, $name, $setName, @setValArr);
        } else {
            return "Unknown argument $setName, choose one of " . $hash->{".setList"};
        }
    } 
    Log3 $name, 5, "$name: set found option $setName in attribute set${setNum}Name";

    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: set called with $setName but device is disabled" if ($setName ne "?");
        return;
    }
     
    if (!AttrVal($name, "set${setNum}NoArg", undef)) {      # soll überhaupt ein Wert übergeben werden?
        if (!defined($setVal)) {                            # Ist ein Wert übergeben?
            Log3 $name, 3, "$name: set without value given for $setName";
            return "no value given to set $setName";
        }
        $rawVal = $setVal;                                  # now work with $rawVal

        # Eingabevalidierung von Sets mit Definition per Attributen
        # 1. Schritt, falls definiert, per Umkehrung der Map umwandeln (z.B. Text in numerische Codes)
        my $map = AttrVal($name, "set${setNum}Map", "");                # old Map for set is now IMap (Input)
        $map    = AttrVal($name, "set${setNum}IMap", $map);             # new syntax ovverides old one
        $rawVal = MapConvert ($hash, {map => $map, val => $rawVal, reverse => 1, undefIfNoMatch => 1});
        return "set value $setVal did not match defined map" if (!defined($rawVal));

        # make sure $rawVal is numeric unless textArg is specified
        if (!$map && !AttrVal($name, "set${setNum}TextArg", undef) && $rawVal !~ /^-?\d+\.?\d*$/) {
            Log3 $name, 3, "$name: set - value $rawVal is not numeric";
            return "set value $rawVal is not numeric";
        }

        if (!AttrVal($name, "set${setNum}TextArg", undef) 
                && !CheckRange($hash, {val => $rawVal, 
                                        min => AttrVal($name, "set${setNum}Min", undef), 
                                        max => AttrVal($name, "set${setNum}Max", undef)} ) ) {
            return "set value $rawVal is not within defined range";
        }

        # Konvertiere input mit IExpr falls definiert
        my $exp = AttrVal($name, "set${setNum}Expr", "");           # old syntax for input in set
        $exp    = AttrVal($name, "set${setNum}IExpr", $exp);        # new syntax overrides old one
        $rawVal = EvalExpr($hash, {expr => $exp, val => $rawVal, '@setValArr' => \@setValArr, action => "set${setNum}IExpr"});
        Log3 $name, 4, "$name: set will now set $setName -> $rawVal";
    } 
    else {                  # NoArg
        $rawVal = 0;
        Log3 $name, 4, "$name: set will now set $setName";
    }
    if (!AttrVal($name, "set${setNum}Local", undef)) {              # soll überhaupt ein Request erzeugt werden?
        my $request = PrepareRequest($hash, "set", $setNum);
        if ($request->{'url'}) {
            DoAuth $hash if (AttrVal($name, "reAuthAlways", 0));
            $request->{'value'}  = $rawVal;
            $request->{'method'} = AttrVal($name, "set${setNum}Method", '');
            AddToSendQueue($hash, $request );
        } else {
            Log3 $name, 3, "$name: no URL for set $setNum";
        }
    } else {
        readingsSingleUpdate($hash, makeReadingName($setName), $rawVal, 1);
    }
    ChainGet($hash, 'set', $setNum);
    return;
}


#########################################################################
# GET command
sub GetFn {
    my @getValArr = @_;                     # rest is optional values
    my $hash      = shift @getValArr;       # reference to device hash
    my $name      = shift @getValArr;       # device name
    my $getName   = shift @getValArr;       # get option name
    my $getVal    = join(' ', @getValArr);  # optional value after get name - might be used in HTTP request
    my $getNum;
    return "\"get $name\" needs at least one argument" if (!$getName);

    if (IsDisabled($name)) {
        Log3 $name, 5, "$name: get called with $getName but device is disabled"
            if ($getName ne "?");
        return;
    }
    Log3 $name, 5, "$name: get called with $getName " if ($getName ne "?");

    # Vorbereitung:
    # suche den übergebenen getName in den Attributen, setze getNum falls gefunden
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ /^get([0-9]+)Name$/) {            # ist das Attribut ein "getXName" ?
            if ($getName eq $attr{$name}{$aName}) {     # ist es der im konkreten get verwendete getName?
                $getNum = $1;                           # gefunden -> merke Nummer X im Attribut
            }
        }
    }

    # gültiger get Aufruf? ($getNum oben schon gesetzt?)
    if(!defined ($getNum)) {
        UpdateHintList($hash) if ($hash->{".updateHintList"});
        return "Unknown argument $getName, choose one of " . $hash->{".getList"};
    } 
    Log3 $name, 5, "$name: get found option $getName in attribute get${getNum}Name";
    Log3 $name, 4, "$name: get will now request $getName" .
        ($getVal ? ", value = $getVal" : ", no optional value");

    my $request = PrepareRequest($hash, "get", $getNum);
    if ($request->{'url'}) {
        DoAuth $hash if (AttrVal($name, "reAuthAlways", 0));
        $request->{'value'}  = $getVal;
        AddToSendQueue($hash, $request);        
    } else {
        Log3 $name, 3, "$name: no URL for Get $getNum";
    }
    ChainGet($hash, 'get', $getNum);
    return "$getName requested, watch readings";
}


##########################################
# chain a get after a set or another get
# if specified by attr
sub ChainGet {
    my $hash = shift;
    my $type = shift;
    my $num  = shift;
    my $name = $hash->{NAME};
    my $get  = AttrVal($name, "${type}${num}FollowGet", '');
    if (!$get) {
        delete $hash->{GetChainLength};
        return;
    }
    $hash->{GetChainLength} = ($hash->{GetChainLength} // 0) + 1;
    if ($hash->{GetChainLength} > AttrVal($name, "maxGetChain", 10)) {
        Log3 $name, 4, "$name: chaining to get $get due to attr ${type}${num}FollowGet suppressed because chain would get longer than maxGetChain";
        return;
    }
    Log3 $name, 4, "$name: chaining to get $get due to attr ${type}${num}FollowGet, Level $hash->{GetChainLength}";
    GetFn($hash, $name, $get);
    return;
}


###################################
# request new data from device
# calltype can be update and reread
sub GetUpdate {
    my $arg  = shift;                               # called with a string type:$name
    my ($calltype, $name) = split(':', $arg);
    my $hash = $defs{$name};
    my $now  = gettimeofday();
    my ($url, $header, $data, $count);
    
    Log3 $name, 4, "$name: GetUpdate called ($calltype)";

    $hash->{'.LastUpdate'} = $now;                  # note the we were called - even when not as 'update' and UpdateTimer is not called afterwards
    UpdateTimer($hash, \&HTTPMOD::GetUpdate, 'next') if ($calltype eq 'update');    # set update timer for next round

    if (IsDisabled($name)) {
        Log3 $name, 5, "$name: GetUpdate called but device is disabled";
        return;
    }
    
    if ($hash->{MainURL}) {
        DoAuth($hash) if (AttrVal($name, 'reAuthAlways', 0));
        my $request = PrepareRequest($hash, 'reading');
        AddToSendQueue($hash, $request);                                # no need to copy the request - the hash has been created in prepare above
    }

    LOOP:
    foreach my $getAttr (sort keys %{$attr{$name}}) {                   # check if additional readings with individual URLs need to be requested
        next LOOP if ($getAttr !~ /^get([0-9]+)Name$/);
        my $getNum  = $1;
        my $getName = AttrVal($name, $getAttr, ''); 
        next LOOP if (!GetFAttr($name, 'get', $getNum, "Poll"));
     
        Log3 $name, 5, "$name: GetUpdate checks if poll required for $getName ($getNum)";
        my $lastPoll = 0;
        $lastPoll = $hash->{lastpoll}{$getName} if ($hash->{lastpoll} && $hash->{lastpoll}{$getName});
        my $dueTime = $lastPoll + GetFAttr($name, 'get', $getNum, "PollDelay",0);
        if ($now < $dueTime) {
            Log3 $name, 5, "$name: GetUpdate will skip $getName, delay not over";            
            next LOOP;
        }
        Log3 $name, 4, "$name: GetUpdate will request $getName";
        $hash->{lastpoll}{$getName} = $now;
        my $request = PrepareRequest($hash, "get", $getNum);
        if (!$request->{url}) {
            Log3 $name, 3, "$name: no URL for Get $getNum";
            next LOOP;
        }
        DoAuth $hash if (AttrVal($name, "reAuthAlways", 0));
        AddToSendQueue($hash, $request); 
    }
    return;
}


#########################################
# Try to call a parse function if defined
sub EvalFunctionCall {
    my ($hash, $buffer, $fName, $type) = @_;
    my $name = $hash->{NAME};
    if (AttrVal($name, $fName, undef)) {
        Log3 $name, 5, "$name: Read is calling $fName for HTTP Response to $type";
        my $func = AttrVal($name, 'parseFunction1', undef);
        no strict "refs";               ## no critic - function name needs to be string becase it comes from an attribute
        eval { &{$func}($hash, $buffer) };
        Log3 $name, 3, "$name: error calling $func: $@" if($@);
        use strict "refs";
    }
    return;
}


################################################
# get a regex from attr and compile if not done
sub GetRegex {
    my ($name, $context, $num, $type, $default) = @_; 
    my $hash = $defs{$name};
    my $val;
    my $regDecode  = AttrVal($name, 'regexDecode', "");                 # implement this even when not compiled
    my $regCompile = AttrVal($name, 'regexCompile', 1);

    #Log3 $name, 5, "$name: Look for Regex $context$num$type";
    # first look for attribute with the full num in it
    if ($num && defined ($attr{$name}{$context . $num . $type})) {      # specific regex attr exists
        return $attr{$name}{$context . $num . $type} if (!$regCompile); # regex string from attr if no compilation wanted
        if ($hash->{CompiledRegexes}{$context . $num . $type}) {        # compiled specific regex esists
            $val = $hash->{CompiledRegexes}{$context . $num . $type};
            #Log3 $name, 5, "$name: GetRegex found precompiled $type for $context$num as $val";
        } else {                                                        # not compiled (yet)
            $val = $attr{$name}{$context . $num . $type};
            PrecompileRegexAttr($hash, $context . $num . $type, $val);
            $val = $hash->{CompiledRegexes}{$context . $num . $type};
        }
    # if not found then look for generic attribute without num
    } elsif (defined ($attr{$name}{$context . $type})) {                # generic regex attr exists
        return $attr{$name}{$context . $type} if (!$regCompile);        # regex string from attr if no compilation wanted
        if ($hash->{CompiledRegexes}{$context . $type}) {
            $val = $hash->{CompiledRegexes}{$context . $type};
            #Log3 $name, 5, "$name: GetRegex found precompiled $type for $context as $val";
        } else {
            $val = $attr{$name}{$context . $type};                      # not compiled (yet)
            PrecompileRegexAttr($hash, $context . $type, $val);
            $val = $hash->{CompiledRegexes}{$context . $type};
        }    
    } 
    else {                      # no attribute defined
        $val = $default;
        return if (!$val)       # default is not compiled - should only be "" or similar
    }
    return $val;
}


###################################
# format a reading value
sub FormatReading {
    my ($hash, $context, $num, $val, $reading) = @_;                                                
    my $name = $hash->{NAME};
    my ($format, $decode, $encode);
    my $expr = "";
    my $map  = "";

    if ($context eq "reading") {        
        $expr = AttrVal($name, 'readingsExpr'  . $num, "") if ($context ne "set");   # very old syntax, not for set!
    }
    $decode  = GetFAttr($name, $context, $num, "Decode");
    $encode  = GetFAttr($name, $context, $num, "Encode");
    $map     = GetFAttr($name, $context, $num, "Map") if ($context ne "set");           # not for set!
    $map     = GetFAttr($name, $context, $num, "OMap", $map);                           # new syntax
    $format  = GetFAttr($name, $context, $num, "Format");
    $expr    = GetFAttr($name, $context, $num, "Expr", $expr) if ($context ne "set");   # not for set!
    $expr    = GetFAttr($name, $context, $num, "OExpr", $expr);                         # new syntax
    
    # encode as utf8 by default if no encode is specified and body was decoded or no charset was seen in the header 
    if (!$encode && (!$hash->{'.bodyCharset'} || $hash->{'.bodyCharset'} eq 'internal' )) {   # body was decoded and encode not sepcified
        $encode = 'utf8';
        Log3 $name, 5, "$name: FormatReading is encoding the reading value as utf-8 because no encoding was specified and the response body charset was unknown or decoded";
    }

    $val = decode($decode, $val) if ($decode && $decode ne 'none');
    $val = encode($encode, $val) if ($encode && $encode ne 'none');
    
    if ($expr) {
        # variables to be available in Exprs
        my $timeStr  = ReadingsTimestamp($name, $reading, 0);
        my $timeDiff = $timeStr ? ($hash->{".updateTime"} ? $hash->{".updateTime"} : gettimeofday()) - time_str2num($timeStr) : 0;
        $val = EvalExpr($hash, {expr => $expr, val => $val, '$timeDiff' => $timeDiff});
    }    
    $val = MapConvert ($hash, {map => $map, val => $val, undefIfNoMatch => 0});            # keep $val if no map or no match
    $val = FormatVal  ($hash, {val => $val, format => $format});
    return $val;
}


###################################
# extract reading for a buffer
sub ExtractReading {
    my ($hash, $buffer, $context, $num, $reqType) = @_;         
    # can't just use $request because update might extract additional gets as update
    # for get / set which use reading.* definitions for parsing reqType might be "get01" and context might be "reading"
    my $name = $hash->{NAME};
    my ($reading, $regex) = ("", "");
    my ($json, $xpath, $xpathst, $recomb, $regopt, $sublen, $alwaysn);
    my @subrlist  = ();
    my @matchlist = ();
    my $try = 1;            # was there any applicable parsing definition?
    my $regCompile = AttrVal($name, 'regexCompile', 1);
    my %namedRegexGroups;
    
    $json    = GetFAttr($name, $context, $num, "JSON");
    $xpath   = GetFAttr($name, $context, $num, "XPath");
    $xpathst = GetFAttr($name, $context, $num, "XPath-Strict");
    $regopt  = GetFAttr($name, $context, $num, "RegOpt");
    $recomb  = GetFAttr($name, $context, $num, "RecombineExpr");
    $sublen  = GetFAttr($name, $context, $num, "AutoNumLen", 0);
    $alwaysn = GetFAttr($name, $context, $num, "AlwaysNum");
    
    # support for old syntax
    if ($context eq "reading") {        
        $reading = AttrVal($name, 'readingsName'.$num, ($json ? $json : "reading$num"));
        $regex   = AttrVal($name, 'readingsRegex'.$num, "");
    }
    # new syntax overrides reading and regex
    $reading = GetFAttr($name, $context, $num, "Name", $reading);
    $regex   = GetRegex($name, $context, $num, "Regex", $regex);

    if ($regex) {    
        # old syntax for xpath and xpath-strict as prefix in regex - one result joined 
        if (AttrVal($name, "enableXPath", undef) && $regex =~ /^xpath:(.*)/) {
            $xpath = $1;
            Log3 $name, 5, "$name: ExtractReading $reading with old XPath syntax in regex /$regex/, xpath = $xpath";
            eval {@matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath)};
            Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
            @matchlist = (join ",", @matchlist);    # old syntax returns only one value
        } 
        elsif (AttrVal($name, "enableXPath-Strict", undef) && $regex =~ /^xpath-strict:(.*)/) {
            $xpathst = $1;
            Log3 $name, 5, "$name: ExtractReading $reading with old XPath-strict syntax in regex /$regex/...";
            my $nodeset;
            eval {$nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst)};
            if ($@) {
                Log3 $name, 3, "$name: error in find for XPathStrictNodeset: $@";
            } else {
                foreach my $node ($nodeset->get_nodelist) {
                    push @matchlist, XML::XPath::XMLParser::as_string($node);
                }
            }
            @matchlist = (join ",", @matchlist);    # old syntax returns only one value    
        } 
        else {                                      # normal regex  
            if ($regopt) {
                Log3 $name, 5, "$name: ExtractReading $reading with regex $regex and options $regopt ...";
                eval "\@matchlist = (\$buffer =~ m/\$regex/$regopt)";    ## no critic - see no other way to pass options to regex 
                Log3 $name, 3, "$name: error in regex matching (with regex option $regopt): $@" if ($@);
                %namedRegexGroups = %+ if (%+);
            } else {                                # simple case without regex options
                Log3 $name, 5, "$name: ExtractReading $reading with regex /$regex/...";
                @matchlist = ($buffer =~ /$regex/);
                %namedRegexGroups = %+ if (%+);
            }
            #Log3 $name, 5, "$name: " . @matchlist . " matches, " .
            #   (%namedRegexGroups ? "named capture groups, " : "") .
            #   "matchlist = " . join ",", @matchlist if (@matchlist);
        }
    } 
    elsif ($json) {
        Log3 $name, 5, "$name: ExtractReading $reading with json $json ...";
        if (defined($hash->{ParserData}{JSON}) && 
            defined($hash->{ParserData}{JSON}{$json})) {
                @matchlist = ($hash->{ParserData}{JSON}{$json});
        } elsif (defined ($hash->{ParserData}{JSON})) {
            Log3 $name, 5, "$name: ExtractReading $reading with json $json did not match a key directly - trying regex match to create a list";
            my @keylist = sort grep {/^$json/} keys (%{$hash->{ParserData}{JSON}});
            Log3 $name, 5, "$name: ExtractReading $reading with json /^$json/ got keylist @keylist";
            @matchlist = map {$hash->{ParserData}{JSON}{$_}} @keylist;
        }
    } 
    elsif ($xpath) {
        Log3 $name, 5, "$name: ExtractReading $reading with XPath $xpath";
        eval { @matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath) };
        Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
    } 
    elsif ($xpathst) {
        Log3 $name, 5, "$name: ExtractReading $reading with XPath-Strict $xpathst";
        my $nodeset;
        eval { $nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst) };
        if ($@) {
            Log3 $name, 3, "$name: error in find for XPathStrictNodeset: $@";
        } else {        
            if ($nodeset->isa('XML::XPath::NodeSet')) {
                foreach my $node ($nodeset->get_nodelist) {
                    push @matchlist, XML::XPath::XMLParser::as_string($node);
                }
            } else {
                push @matchlist, $nodeset;
            }        
        }
    } 
    else {      # neither regex, xpath nor json attribute found ...
        $try = 0;           
        Log3 $name, 5, "$name: ExtractReading for context $context, num $num - no individual parse definition";
    }

    my $match = @matchlist;
    if (!$match) {
        Log3 $name, 5, "$name: ExtractReading $reading did not match" if ($try);
        return ($try, $match, $reading, @subrlist);
    }
    
    if ($recomb) {
        Log3 $name, 5, "$name: ExtractReading is recombining $match matches with expression $recomb";
        my $val = EvalExpr($hash, {expr => $recomb, '@matchlist' => \@matchlist});
        Log3 $name, 5, "$name: ExtractReading recombined matchlist to $val";
        @matchlist = ($val);
        $match = 1;
    }
    if (%namedRegexGroups) {
        Log3 $name, 5, "$name: experimental named regex group handling";
        foreach my $subReading (keys %namedRegexGroups) {
            my $val = $namedRegexGroups{$subReading};
            push @subrlist, $subReading;
            # search for group in -Name attrs (-group is sub number) ...
            my $group = 0;
            foreach my $aName (sort keys %{$attr{$name}}) {
                if ($aName =~ /^$context$num-([\d]+)Name$/) {
                    if ($attr{$name}{$context.$num."-".$1."Name"} eq $subReading) {
                        $group = $1;
                        Log3 $name, 5, "$name: ExtractReading uses $context$num-$group attrs for named capture group $subReading";
                    }
                }
            }
            my $eNum = $num . ($group ? "-".$group : "");
            $val  = FormatReading($hash, $context, $eNum, $val, $subReading);
                        
            Log3 $name, 5, "$name: ExtractReading for $context$num sets reading for named capture group $subReading to $val";
            readingsBulkUpdate( $hash, $subReading, $val );
            # point from reading name back to the parsing definition as reading01 or get02 ...
            $hash->{defptr}{readingBase}{$subReading} = $context;                   # used to find maxAge attr
            $hash->{defptr}{readingNum}{$subReading}  = $num;                       # used to find maxAge attr
            $hash->{defptr}{requestReadings}{$reqType}{$subReading} = "$context $eNum"; # used by deleteOnError / deleteIfUnmatched
            delete $hash->{defptr}{readingOutdated}{$subReading};                   # used by MaxAge as well
        }
    } 
    else {                # now assign readings from matchlist  
        my $group = 1;
        foreach my $val (@matchlist) {
            my ($subNum, $eNum, $subReading);
            if ($match == 1) {
                # only one match
                $eNum = $num;
                $subReading = ($alwaysn ? "${reading}-" . ($sublen ? sprintf ("%0${sublen}d", 1) : "1") : $reading);
            } else {
                # multiple matches -> check for special name of readings
                $eNum = $num ."-".$group;
                # don't use GetFAttr here because we don't want to get the value of the generic attribute "Name"
                # but this name with -group number added as default
                if (defined ($attr{$name}{$context . $eNum . "Name"})) {
                    $subReading = $attr{$name}{$context . $eNum . "Name"};
                } else {
                    if ($sublen) {
                        $subReading = "${reading}-" . sprintf ("%0${sublen}d", $group);
                    } else {
                        $subReading = "${reading}-$group";
                    }
                    $subNum = "-$group";
                }
            }
            push @subrlist, $subReading;
            $val = FormatReading($hash, $context, $eNum, $val, $subReading);
                        
            Log3 $name, 5, "$name: ExtractReading for $context$num-$group sets $subReading to $val";
            Log3 $name, 5, "$name: ExtractReading value as hex is " . unpack ('H*', $val);
            readingsBulkUpdate( $hash, $subReading, $val );
            # point from reading name back to the parsing definition as reading01 or get02 ...
            $hash->{defptr}{readingBase}{$subReading}   = $context;                 # used to find maxAge attr
            $hash->{defptr}{readingNum}{$subReading}    = $num;                     # used to find maxAge attr
            $hash->{defptr}{readingSubNum}{$subReading} = $subNum if ($subNum);     # used to find maxAge attr
            $hash->{defptr}{requestReadings}{$reqType}{$subReading} = "$context $eNum";     # used by deleteOnError / deleteIfUnmathced
            # might be                       get01      Temp-02         reading  5 (where its parsing / naming was defined)
            delete $hash->{defptr}{readingOutdated}{$subReading};                   # used by MaxAge as well
            $group++;
        }
    }
    return ($try, $match, $reading, @subrlist);
}


###################################
# delete a reading and its metadata
sub DeleteReading {
    my $hash    = shift;                    # reference to Fhem device hash
    my $reading = shift;                    # name of reading to delete
    my $name    = $hash->{NAME};            # fhem device name
    delete($defs{$name}{READINGS}{$reading});
    delete $hash->{defptr}{readingOutdated}{$reading};
    delete $hash->{defptr}{readingBase}{$reading};
    delete $hash->{defptr}{readingNum}{$reading};
    delete $hash->{defptr}{readingSubNum}{$reading};
    
    foreach my $rt (keys %{$hash->{defptr}{requestReadings}}) {
        delete $hash->{defptr}{requestReadings}{$rt}{$reading};
    }
    return;
}


###################################
# check max age of all readings
sub DoMaxAge {
    my $hash = shift;                   # reference to Fhem device hash
    my $name = $hash->{NAME};           # Fhem device name
    my ($base, $num, $sub, $max, $rep, $mode, $time, $now);
    my $readings = $hash->{READINGS};
    return if (!$readings); 
    $now = gettimeofday();
    UpdateRequestHash($hash) if ($hash->{".updateRequestHash"});

    LOOP:                               # go through alle readings of this device
    foreach my $reading (sort keys %{$readings}) {
        my $key = $reading;                                     # start by checking full reading name as key in readingBase hash
        Log3 $name, 5, "$name: MaxAge: check reading $reading";
        if ($hash->{defptr}{readingOutdated}{$reading}) {
            Log3 $name, 5, "$name: MaxAge: reading $reading was outdated before - skipping";
            next LOOP;
        }        
        $base = $hash->{defptr}{readingBase}{$reading};         # get base name of definig attribute like "reading" or "get" 
        if (!$base && $reading =~ m{(.*) (-[0-9]+) \z}xms) {    # reading name endet auf -Zahl und ist nicht selbst per attr Name definiert 
            $key  = $1;                                         # -> suche nach attr Name mit Wert ohne -Zahl
            $base = $hash->{defptr}{readingBase}{$key};
            Log3 $name, 5, "$name: MaxAge: no defptr for this name - reading name seems automatically created with $2 from $key and not updated recently";
        }
        if (!$base) {
            Log3 $name, 5, "$name: MaxAge: reading $reading doesn't come from a -Name attr -> skipping";
            next LOOP;
        }
        
        $num = $hash->{defptr}{readingNum}{$key};
        if ($hash->{defptr}{readingSubNum}{$key}) {
            $sub = $hash->{defptr}{readingSubNum}{$key};
        } else {
            $sub = "";
        }

        Log3 $name, 5, "$name: MaxAge: reading definition comes from $base, $num" . ($sub ? ", $sub" : "");
        $max = GetFAttr($name, $base, $num . $sub, "MaxAge");
        if (!$max) {
            Log3 $name, 5, "$name: MaxAge: No MaxAge attr for $base, $num, $sub";
            next LOOP;
        }

        $rep  = GetFAttr($name, $base, $num . $sub, "MaxAgeReplacement", "");
        $mode = GetFAttr($name, $base, $num . $sub, "MaxAgeReplacementMode", "text");
        $time = ReadingsTimestamp($name, $reading, 0);
        Log3 $name, 5, "$name: MaxAge: max = $max, mode = $mode, rep = $rep";
        if ($now - time_str2num($time) <= $max) {
            next LOOP;
        }

        if ($mode eq "expression") {
            my $val = ReadingsVal($name, $reading, "");
            my $new = EvalExpr($hash, {expr => $rep, val => $val, '$reading' => $reading});
            Log3 $name, 4, "$name: MaxAge: reading $reading too old - using Value $new from Perl expression as MaxAge replacement: $rep";
            readingsBulkUpdate($hash, $reading, $new);    
        } 
        elsif ($mode eq "text") {
            Log3 $name, 4, "$name: MaxAge: reading $reading too old - using $rep instead";
            readingsBulkUpdate($hash, $reading, $rep);
        } 
        elsif ($mode eq 'reading') {
            my $device  = $name;
            my $rname = $rep;
            if ($rep =~ /^([^\:]+):(.+)$/) {
                $device  = $1;
                $rname = $2;
            }
            my $rvalue = ReadingsVal($device, $rname, "");
            Log3 $name, 4, "$name: MaxAge: reading $reading too old - using reading $rname with value $rvalue instead";
            readingsBulkUpdate($hash, $reading, $rvalue);
        } 
        elsif ($mode eq 'internal') {
            my $device   = $name;
            my $internal = $rep;
            if ($rep =~ /^([^\:]+):(.+)$/) {
                $device   = $1;
                $internal = $2;
            }
            my $rvalue = InternalVal($device, $internal, "");
            Log3 $name, 4, "$name: MaxAge: reading $reading too old - using internal $internal with value $rvalue instead";
            readingsBulkUpdate($hash, $reading, $rvalue);    
        } 
        elsif ($mode eq "delete") {
            Log3 $name, 4, "$name: MaxAge: reading $reading too old - delete it";
            DeleteReading($hash, $reading);
        }
        $hash->{defptr}{readingOutdated}{$reading} = 1 if ($mode ne "delete");
    }
    return;
}




######################################################
# check delete option on error
# for readings that were created in the last reqType
# e.g. get04 but maybe defined in reading02Regex
sub DoDeleteOnError {
    my $hash    = shift;
    my $reqType = shift;
    my $name    = $hash->{NAME};
    
    return if (!$hash->{READINGS}); 
    UpdateRequestHash($hash) if ($hash->{".updateRequestHash"});
    
    if (!$hash->{defptr}{requestReadings} || !$hash->{defptr}{requestReadings}{$reqType}) {
        Log3 $name, 5, "$name: DoDeleteOnError: no defptr pointing from request to readings - returning";
        return;
    }
    # readings that were created during last request type reqType (e.g. get03)
    my $reqReadings = $hash->{defptr}{requestReadings}{$reqType};
    foreach my $reading (sort keys %{$reqReadings}) {
        Log3 $name, 5, "$name: DoDeleteOnError: check reading $reading";
        # get parsing / handling definition of this reading (e.g. reading02... or Get04...)            
        my ($context, $eNum) = split (" ", $reqReadings->{$reading});
        if (GetFAttr($name, $context, $eNum, "DeleteOnError")) {
            Log3 $name, 4, "$name: DoDeleteOnError: delete reading $reading created by $reqType ($context, $eNum)";
            DeleteReading($hash, $reading);
        }
    }
    return;
}


###################################
# check delete option if unmatched
sub DoDeleteIfUnmatched {
    my ($hash, $reqType, @matched) = @_;
    my $name = $hash->{NAME};
    
    Log3 $name, 5, "$name: DoDeleteIfUnmatched called with request $reqType";
    return if (!$hash->{READINGS}); 
    UpdateRequestHash($hash) if ($hash->{".updateRequestHash"});
    
    if (!$hash->{defptr}{requestReadings}) {
        Log3 $name, 5, "$name: DoDeleteIfUnmatched: no defptr pointing from request to readings - returning";
        return;
    }
    my %matched;
    foreach my $m (@matched) {
        $matched{$m} = 1;
    }                 
    my $reqReadings = $hash->{defptr}{requestReadings}{$reqType};  
    my @rList = sort keys %{$reqReadings};
    Log3 $name, 5, "$name: DoDeleteIfUnmatched: List from requestReadings is @rList";
    RLOOP:
    foreach my $reading (@rList) {
        Log3 $name, 5, "$name: DoDeleteIfUnmatched: check reading $reading" 
            . ($matched{$reading} ? " (matched)" : " (no match)");
        next RLOOP if ($matched{$reading});
        
        my ($context, $eNum) = split (" ", $reqReadings->{$reading});
        Log3 $name, 5, "$name: DoDeleteIfUnmatched: check attr for reading $reading ($context, $eNum)";
        if (GetFAttr($name, $context, $eNum, "DeleteIfUnmatched")) {
            Log3 $name, 4, "$name: DoDeleteIfUnmatched: delete reading $reading created by $reqType ($context, $eNum)";
            DeleteReading($hash, $reading);
        } 
        else {
            Log3 $name, 5, "$name: DoDeleteIfUnmatched: no DeleteIfUnmatched for reading $reading ($context, $eNum)";
        }
    }
    return;
}


###########################################
# extract cookies from HTTP Response Header
# called from ReadCallback
sub GetCookies {
    my $hash   = shift;             # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $header = shift;             # http header read
    my $name   = $hash->{NAME};     # fhem device name
    #Log3 $name, 5, "$name: looking for Cookies in $header";
    Log3 $name, 5, "$name: GetCookies is looking for Cookies";
    foreach my $cookie ($header =~ m/set-cookie: ?(.*)/gi) {
        #Log3 $name, 5, "$name: GetCookies found Set-Cookie: $cookie";
        $cookie =~ /([^,; ]+)=([^,;\s\v]+)[;,\s\v]*([^\v]*)/;
        Log3 $name, 4, "$name: GetCookies parsed Cookie: $1 Wert $2 Rest $3";
        my $name  = $1;
        my $value = $2;
        my $rest  = ($3 ? $3 : "");
        my $path  = "";
        if ($rest =~ /path=([^;,]+)/) {
            $path = $1; 
        }
        my $key = $name . ';' . $path;
        $hash->{HTTPCookieHash}{$key}{Name}    = $name;
        $hash->{HTTPCookieHash}{$key}{Value}   = $value;
        $hash->{HTTPCookieHash}{$key}{Options} = $rest;
        $hash->{HTTPCookieHash}{$key}{Path}    = $path;     
    }
    return;
}


###################################
# initialize Parsers
# called from _Read
sub InitParsers {
    my $hash = shift;               # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $body = shift;               # http body read
    my $name = $hash->{NAME};       # fhem device name

    # initialize parsers
    if ($hash->{'.JSONEnabled'} && $body) {
        FlattenJSON($hash, $body);
    }
    if ($hash->{'.XPathEnabled'} && $body) {
        $hash->{ParserData}{XPathTree} = HTML::TreeBuilder::XPath->new;
        eval { $hash->{ParserData}{XPathTree}->parse($body) };
        Log3 $name, ($@ ? 3 : 5), "$name: InitParsers: XPath parsing " . ($@ ? "error: $@" : "done.");
    }
    if ($hash->{'.XPathStrictEnabled'} && $body) {
        eval { $hash->{ParserData}{XPathStrictNodeset} = XML::XPath->new(xml => $body) };
        Log3 $name, ($@ ? 3 : 5), "$name: InitParsers: XPath-Strict parsing " . ($@ ? "error: $@" : "done.");
    }
    return;
}


###################################
# cleanup Parsers
# called from _Read
sub CleanupParsers {
    my $hash = shift;               # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $name = $hash->{NAME};       # fhem device name

    if ($hash->{'.XPathEnabled'}) {
        if ($hash->{ParserData}{XPathTree}) {
            eval { $hash->{ParserData}{XPathTree}->delete() };
            Log3 $name, 3, "$name: error deleting XPathTree: $@" if ($@);
        }
    }
    if ($hash->{'.XPathStrictEnabled'}) {
        if ($hash->{ParserData}{XPathStrictNodeset}) {
            eval {$hash->{ ParserData}{XPathStrictNodeset}->cleanup()} ;
            Log3 $name, 3, "$name: error deleting XPathStrict nodeset: $@" if ($@);
        }
    }
    delete $hash->{ParserData};
    return;
}


###################################
# Extract SID
# called from _Read
sub ExtractSid {
    my $hash    = shift;                        # hash reference passed to HttpUtils_NonblockingGet (our device)
    my $buffer  = shift;                        # whole http response buffer read
    my $request = $hash->{REQUEST};             # hash ref to the request that was sent        
    my $context = $request->{'context'};        # attribute context (reading, get, set, sid)
    my $num     = $request->{'num'};
    my $name    = $hash->{NAME};
    my $regex   = GetRegex($name, "", "", "idRegex", "");
    my $json    = AttrVal($name, "idJSON", "");
    my $xpath   = AttrVal($name, "idXPath", "");
    my $xpathst = AttrVal($name, "idXPath-Strict", ""); 

    Log3 $name, 5, "$name: ExtractSid called, context $context, num $num";
    
    $regex   = GetRegex($name, $context, $num, "IdRegex", $regex);
    $regex   = GetRegex($name, $context, $num, "IDRegex", $regex);
    $json    = GetFAttr($name, $context, $num, "IdJSON", $json);
    $xpath   = GetFAttr($name, $context, $num, "IdXPath", $xpath);
    $xpathst = GetFAttr($name, $context, $num, "IdXPath-Strict", $xpathst);

    my @matchlist;
    if ($json) {
        Log3 $name, 5, "$name: Checking SID with JSON $json";
        if (defined($hash->{ParserData}{JSON}) && 
            defined($hash->{ParserData}{JSON}{$json})) {
                @matchlist = ($hash->{ParserData}{JSON}{$json});
        }
    } 
    elsif ($xpath) {
        Log3 $name, 5, "$name: Checking SID with XPath $xpath";
        eval { @matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath) };
        Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
    } 
    elsif ($xpathst) {
        Log3 $name, 5, "$name: Checking SID with XPath-Strict $xpathst";
        my $nodeset;
        eval { $nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst) };
        if ($@) {
            Log3 $name, 3, "$name: error in find for XPathStrictNodeset: $@";
        } else {
            foreach my $node ($nodeset->get_nodelist) {
                push @matchlist, XML::XPath::XMLParser::as_string($node);
            }
        }
    }
    if (@matchlist) {
        $buffer = join (' ', @matchlist);
        if ($regex) {
            Log3 $name, 5, "$name: ExtractSid is replacing buffer to check with match: $buffer";
        } 
        else {
            $hash->{sid} = $buffer;
            Log3 $name, 4, "$name: ExtractSid set sid to $hash->{sid}";
            return 1;
        }
    }
    if ($regex) {
        if ($buffer =~ $regex) {
            $hash->{sid} = $1;
            Log3 $name, 4, "$name: ExtractSid set sid to $hash->{sid}";
            return 1;
        } 
        else {
            Log3 $name, 5, "$name: ExtractSid could not match buffer to IdRegex $regex";
        }
    }
    return;
}


###############################################################
# Check if Auth is necessary and queue auth steps if needed
# called from _Read
sub CheckAuth {
    my $hash    = shift;                        # hash reference passed to HttpUtils_NonblockingGet (our device)
    my $buffer  = shift;                        # whole http response read
    my $request = $hash->{REQUEST};             # hash ref to the request that was sent
    my $context = $request->{'context'};        # attribute context (reading, get, set, sid)
    my $num     = $request->{'num'};
    my $name    = $hash->{NAME};
    my $doAuth;

    my $regex   = GetRegex($name, "", "", "reAuthRegex", "");
    my $json    = AttrVal($name, "reAuthJSON", "");
    my $xpath   = AttrVal($name, "reAuthXPath", "");
    my $xpathst = AttrVal($name, "reAuthXPath-Strict", "");

    if ($context =~ /([gs])et/) {
        $regex   = GetRegex($name, $context, $num, "ReAuthRegex", $regex);
        $json    = GetFAttr($name, $context, $num, "ReAuthJSON", $json);
        $xpath   = GetFAttr($name, $context, $num, "ReAuthXPath", $xpath);
        $xpathst = GetFAttr($name, $context, $num, "ReAuthXPath-Strict", $xpathst);
    }
    
    my @matchlist;
    if ($json) {
        Log3 $name, 5, "$name: Checking Auth with JSON $json";
        if (defined($hash->{ParserData}{JSON}) && 
            defined($hash->{ParserData}{JSON}{$json})) {
                @matchlist = ($hash->{ParserData}{JSON}{$json});
        }
    } 
    elsif ($xpath) {
        Log3 $name, 5, "$name: Checking Auth with XPath $xpath";
        eval { @matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath) };
        Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
    } 
    elsif ($xpathst) {
        Log3 $name, 5, "$name: Checking Auth with XPath-Strict $xpathst";
        my $nodeset;
        eval { $nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst) };
        if ($@) {
            Log3 $name, 3, "$name: error in find for XPathStrictNodeset: $@";
        } else {
            foreach my $node ($nodeset->get_nodelist) {
                push @matchlist, XML::XPath::XMLParser::as_string($node);
            }
        }
    }
    if (@matchlist) {
        if ($regex) {
            $buffer = join (' ', @matchlist);
            Log3 $name, 5, "$name: CheckAuth is replacing buffer to check with match: $buffer";
        } else {
            Log3 $name, 5, "$name: CheckAuth matched: $buffer";
            $doAuth = 1;
        }
    }
    if ($regex) {
        Log3 $name, 5, "$name: CheckAuth is checking buffer with ReAuthRegex $regex";
        $doAuth = 1 if ($buffer =~ $regex);
    }
    if ($doAuth) {
        Log3 $name, 4, "$name: CheckAuth decided new authentication required";
        if ($request->{retryCount} < AttrVal($name, "authRetries", 1)) {
            if (!AttrVal($name, "dontRequeueAfterAuth", 0)) {
                AddToSendQueue ($hash, { %{$request}, 'priority' => 1, 'retryCount' => $request->{retryCount}+1, 'value' => $request->{value} } ); 
                Log3 $name, 4, "$name: CheckAuth prepended request $request->{type} again before auth, retryCount $request->{retryCount} ...";
            }
            DoAuth $hash;
            return 1;
        } else {
            Log3 $name, 4, "$name: Authentication still required but no retries left - did last authentication fail?";
        }
    } 
    else {
        Log3 $name, 5, "$name: CheckAuth decided no authentication required";    
    }
    return 0;
}


###################################
# update List of Readings to parse
# during GetUpdate cycle
sub UpdateReadingList {
    my $hash   = shift;                 # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $name   = $hash->{NAME};         # Fhem device name

    my %khash;
    foreach my $a (sort keys %{$attr{$name}}) {
        if (($a =~ /^readingsName(.*)/) && defined ($attr{$name}{'readingsName' . $1})) { 
            $khash{$1} = 1;      # old syntax
        } elsif ($a =~ /^reading([0-9]+).*/) { 
            $khash{$1} = 1;      # new syntax
        }
    }
    my @list = sort keys %khash;
    $hash->{".readingParseList"} = \@list;
    Log3 $name, 5, "$name: UpdateReadingList created list of reading.* nums to parse during getUpdate as @list";
    delete $hash->{".updateReadingList"};
    return;
}


###################################
# Check for redirect headers
sub CheckRedirects {
    my $hash    = shift;                    # hash reference passed to HttpUtils_NonblockingGet (our device hash)
    my $header  = shift;                    # HTTP header read
    my $addr    = shift;
    my $name    = $hash->{NAME};            # fhem device name
    my $request = $hash->{REQUEST};         # reference to request hash
    my $type    = $request->{type};         
    my $url     = $request->{url};
    
    if (!$header) {
        Log3 $name, 4, "$name: no header to look for redirects";
        return;
    }
    my @header  = split("\r\n", $header);
    my @header0 = split(" ", shift @header);
    my $code    = $header0[1];
    Log3 $name, 4, "$name: checking for redirects, code=$code, ignore=$request->{ignoreredirects}";

    if ($code !~ m{ \A 301 | 302 | 303 \z }xms) {
        Log3 $name, 4, "$name: no redirects to handle";
        return;
    }

    $hash->{RedirCount} = 0 if (!$hash->{RedirCount});
    if(++$hash->{RedirCount} > 5) {
        Log3 $name, 3, "$name: Too many redirects processing response to $url";
        return;
    } 

    my $redirAdr;
    map { $redirAdr = $1 if ( $_ =~ m{ [Ll]ocation: \s* (\S+) $ }xms ) } @header;
    if (!$redirAdr) {
        Log3 $name, 3, "$name: Error: got Redirect but no Location-Header from server";
    }
    $redirAdr = "/$redirAdr" if($redirAdr !~ m/^http/ && $redirAdr !~ m/^\//);
    my $rurl = ($redirAdr =~ m/^http/) ? $redirAdr : $addr.$redirAdr;
    if ($request->{ignoreredirects}) {
        Log3 $name, 4, "$name: ignoring redirect to $rurl";
        return;
    }
    Log3 $name, 4, "$name: $url: Redirect ($hash->{RedirCount}) to $rurl";
    # todo: redirect with post possible / supported??    
    # prepend redirected request, copy from old request and overwrite some keys:
    AddToSendQueue($hash, { %{$request}, 'url' => $rurl, 'priority' => 1 } );   
    HandleSendQueue("direct:".$name);   # AddToQueue with prio did not call this.
    return 1;
}


###########################################
# create automatic readings from JSON
sub ExtractAllJSON {
    my $hash    = shift;                        # hash reference passed to HttpUtils_NonblockingGet (our device)
    my $body    = shift;                        # buffer read
    my $request = $hash->{REQUEST};             # hash ref to the request that was sent        
    my $context = $request->{'context'};        # attribute context (reading, get, set, sid)
    my $num     = $request->{'num'};            # attribute num
    my $type    = $request->{'type'};           # type of request that was sent (like get01, update or auth01)
    my $name    = $hash->{NAME};

    # create a reading for each JSON object and use formatting options if a correspondig reading name / formatting is defined 
    if ((AttrVal($name, "extractAllJSON", 0) == 2 || GetFAttr($name, $context, $num, "ExtractAllJSON", 0) == 2) 
        && ($context =~/get|set/) && (AttrVal($name, "${context}${num}CheckAllReadings", "u") eq "u")) {
        # ExtractAllJSON mode 2 will create attributes, also CheckAllReadings to 1 for get/set unless already defined as 0
        CommandAttr(undef, "$name ${context}${num}CheckAllReadings 1");  
    }
    my $fDefault = ($featurelevel > 5.9 ? 1 : '');
    my $rNum     = 100;                     # start value for extractAllJSON mode 2
    my @matched;
    my $filter = AttrVal($name, "extractAllJSONFilter", "");
    if (ref $hash->{ParserData}{JSON} ne "HASH") {
        Log3 $name, 3, "$name: no parsed JSON structure available";
        return;
    }
    foreach my $object (keys %{$hash->{ParserData}{JSON}}) {
        next if ($filter && $object !~ $filter);
        my $rName = $object;
        $rName = makeReadingName($object) if (AttrVal($name, "enforceGoodReadingNames", $fDefault));
        if (AttrVal($name, "extractAllJSON", 0) == 2 || 
            (GetFAttr($name, $context, $num, "ExtractAllJSON") &&
            GetFAttr($name, $context, $num, "ExtractAllJSON") == 2)) {
            # mode 2: create attributes with the readings to make renaming easier

            $rName = makeReadingName($object);  # at least for this mode!
            my $existing = 0;       # check if there already is an attribute reading[0-9]+JSON $object
            foreach my $a (grep { /reading[0-9]+JSON/ } keys %{$attr{$name}} ) {
                if ($attr{$name}{$a} eq $object) {
                    $existing = $a;
                }
            }
            if ($existing) {        
                Log3 $name, 5, "$name: Read with extractAllJSON mode 2 doesn't set a new attr for $object because $existing already exists with $object";
            } 
            else {                # find free reading num 
                while (AttrVal($name, "reading${rNum}Name", "u") ne "u" 
                    || AttrVal($name, "reading${rNum}JSON", "u") ne "u") {
                    $rNum++;        # skip until a number is unused
                }
                Log3 $name, 5, "$name: Read with extractAllJSON mode 2 is defining attribute reading${rNum}Name and reading${rNum}JSON for object $object";
                CommandAttr(undef, "$name reading${rNum}Name $rName");
                CommandAttr(undef, "$name reading${rNum}JSON $object");
            }
        } 
        else {                      # normal mode without attribute creation  
            my $value = FormatReading($hash, $context, $num, $hash->{ParserData}{JSON}{$object}, $rName);
            Log3 $name, 5, "$name: Read sets reading $rName to value $value of JSON $object";
            readingsBulkUpdate($hash, $rName, $value);
            push @matched, $rName;      # unmatched is not filled for "ExtractAllJSON"
            delete $hash->{defptr}{readingOutdated}{$rName};
            
            $hash->{defptr}{readingBase}{$rName} = $context;
            $hash->{defptr}{readingNum}{$rName}  = $num;
            $hash->{defptr}{requestReadings}{$type}{$rName} = "$context $num";
        }
    }
    if ((AttrVal($name, "extractAllJSON", 0) == 2) && $context eq "reading") {
        Log3 $name, 3, "$name: Read is done with JSON extractAllJSON mode 2 and now removes this attribute";
        CommandDeleteAttr(undef, "$name extractAllJSON");
    } 
    elsif ((GetFAttr($name, $context, $num, "ExtractAllJSON") && 
                GetFAttr($name, $context, $num, "ExtractAllJSON") == 2) && $context =~/get|set/) {
        Log3 $name, 3, "$name: Read is done with JSON ${context}${num}ExtractAllJSON mode 2 and now removes this attribute";
        CommandDeleteAttr(undef, "$name ${context}${num}ExtractAllJSON");
    }
    return @matched;
}


################################################
# dump buffer and header to file for debugging
sub DumpBuffer {
    my $hash   = shift;
    my $body   = shift;
    my $header = shift;
    my $name   = $hash->{NAME};    
    my $fh;
    $hash->{BufCounter} = 0 if (!$hash->{BufCounter});
    $hash->{BufCounter} ++;
    my $path = AttrVal($name, "dumpBuffers", '.');
    Log3 $name, 3, "$name: dump buffer to $path/buffer$hash->{BufCounter}.txt";
    open($fh, '>', "$path/buffer$hash->{BufCounter}.txt");      ## no critic 
    if ($header) {
        print $fh $header;
        print $fh "\r\n\r\n";
    }
    print $fh $body;
    close $fh;
    return;
}
    

###################################
# read / parse new data from device
# - callback for non blocking HTTP 
sub ReadCallback {
    my $huHash  = shift;                        # hash reference passed to HttpUtils_NonblockingGet
    my $err     = shift;                        # error message from HttpUtils_NonblockingGet
    my $body    = shift // '';                  # HTTP body received
    my $hash    = $huHash->{DEVHASH};           # our device hash
    my $name    = $hash->{NAME};                # our device name
    my $request = $hash->{REQUEST};             # hash ref to the request that was sent        
    my $context = $request->{'context'};        # attribute context (reading, get, set, sid)
    my $num     = $request->{'num'};
    my $type    = $request->{'type'};           # type of request that was sent (like get01, update or auth01)
    my $header  = $huHash->{httpheader} // '';  # HTTP headers received
    delete $huHash->{DEVHASH};
    $hash->{HttpUtils} = $huHash;               # make the httpUtils hash available in case anyone wants to use variables
    $hash->{BUSY}      = 0;

    Log3 $name, 5, "$name: ReadCallback called from " . FhemCaller();
    if (!$name || $hash->{TYPE} ne "HTTPMOD") {
        Log3 'HTTPMOD', 3, "HTTPMOD ReadCallback was called with illegal hash - this should never happen - problem in HttpUtils?";
        return;
    }
    
    my $headerSplit = AttrVal($name, 'fileHeaderSplit', '');        # to allow testing header features
    if ($headerSplit && !$header && $body =~ m{ (.*) $headerSplit (.*) }xms ) {
        $header = $1;
        $body   = $2 // '';
        Log3 $name, 5, "$name: HTTPMOD ReadCallback split file body / header at $headerSplit";
    }
    if ($err) {
        my $lvlRegex = GetRegex($name, '', '', 'errLogLevelRegex', '');
        my $errLvl   = AttrVal($name, 'errLogLevel', 3);
        Log3 $name, 5, "$name: Read callback Error LogLvl set to $errLvl, regex " . ($lvlRegex // '');
        $errLvl      = 3 if ($lvlRegex && $err !~ $lvlRegex);
        Log3 $name, $errLvl, "$name: Read callback: Error: $err";
    }
    
    Log3 $name, 4, "$name: Read callback: request type was $type" . 
        " retry $request->{retryCount}" .
        ($header ? ",\r\nheader: $header" : ", no headers") . 
        ($body ? ", body length " . length($body) : ", no body");
    Log3 $name, 5, "$name: Read callback: " . ($body ? "body\r\n$body" : "body empty");
        
    MemReading($hash) if (AttrVal($name, "memReading", 0));
    DumpBuffer($hash, $body, $header) if (AttrVal($name, "dumpBuffers", 0));

    $body = BodyDecode($hash, $body, $header);                  # decode body according to attribute bodyDecode and content-type header

    my $ppr = AttrVal($name, "preProcessRegex", "");
    # can't precompile a whole substitution so the GetRegex way doesn't work here.
    # we would need to split the regex into match/replace part and only compile the matching part ...
    # if a user s affected by Perl's memory he leak he might just add option a to his regex attr
    #Log3 $name, 5, "$name: Read preProcessRegex is $ppr";
    if ($ppr) {
        my $pprexp = '$body=~' . $ppr; 
        local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: Read preProcessRegex created warning: @_"; };
        eval $pprexp;                   ## no critic - user defined substitution needs evaluation as string
        Log3 $name, 5, "$name: Read - body after preProcessRegex: $ppr is $body";
    }
    $hash->{httpbody} = $body if (AttrVal($name, "showBody", 0));
    
    my $buffer;
    $buffer = ($header ? $header . "\r\n\r\n" . $body : $body);      # for matching sid / reauth
    $buffer = $buffer . "\r\n\r\n" . $err if ($err);                 # for matching reauth
            
    my $fDefault = ($featurelevel > 5.9 ? 1 : 0);
    InitParsers($hash, $body);
    GetCookies($hash, $header) if (AttrVal($name, "enableCookies", $fDefault));   
    ExtractSid($hash, $buffer); 
    return if (AttrVal($name, "handleRedirects", $fDefault) && CheckRedirects($hash, $header, $huHash->{addr}));
    delete $hash->{RedirCount};
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "LAST_ERROR", $err)      if (AttrVal($name, "showError", 0) && $err);
    readingsBulkUpdate($hash, "LAST_REQUEST", $type)   if (AttrVal($name, "showMatched", 0));
    Log3 $name, 5, "$name: Read callback sets LAST_REQUEST to $type";
    
    DoMaxAge($hash) if ($hash->{'.MaxAgeEnabled'});
    
    my $authQueued;
    $authQueued = CheckAuth($hash, $buffer) if ($context ne "sid");
    
    if ($err || $authQueued || ($context =~ "set|sid" && !GetFAttr($name, $context, $num, "ParseResponse"))) {
        readingsEndUpdate($hash, 1);
        DoDeleteOnError($hash, $type)   if ($hash->{DeleteOnError}); 
        CleanupParsers($hash);
        return;   # don't continue parsing response  
    }
      
    my ($tried, $match, $reading); 
    my @unmatched = (); 
    my @matched   = ();
    my @subrlist  = ();
    my $checkAll  = 1;
    
    if ($context =~ "get|set") {
        ($tried, $match, $reading, @subrlist) = ExtractReading($hash, $buffer, $context, $num, $type);
        push @matched,   @subrlist if ($tried && $match);
        push @unmatched, $reading  if ($tried && !$match);
        $checkAll = GetFAttr($name, $context, $num, 'CheckAllReadings', !$tried);
        # if ExtractReading2 could not find any parsing instruction (e.g. regex) then check all Readings
    }
    
    if (AttrVal($name, "extractAllJSON", "") || GetFAttr($name, $context, $num, "ExtractAllJSON")) {
        push @matched, ExtractAllJSON($hash, $body);
    } 
    
    UpdateReadingList($hash) if ($hash->{".updateReadingList"});   
    if ($checkAll && defined($hash->{".readingParseList"})) {
        # check all defined readings and try to extract them               
        Log3 $name, 5, "$name: Read starts parsing response to $type with defined readings: " . 
                join (",", @{$hash->{".readingParseList"}});
        foreach my $iNum (@{$hash->{".readingParseList"}}) {
            # try to parse readings defined in reading.* attributes
            # pass request $type so we know for later delete
            (undef, $match, $reading, @subrlist) = ExtractReading($hash, $buffer, 'reading', $iNum, $type);
            push @matched,   @subrlist if ($match);
            push @unmatched, $reading  if (!$match);
        }
    }
    if (AttrVal($name, "showMatched", undef)) {
        readingsBulkUpdate($hash, "MATCHED_READINGS", join ' ', @matched);
        readingsBulkUpdate($hash, "UNMATCHED_READINGS", join ' ', @unmatched);
    }

    if (!@matched) {
        Log3 $name, 4, "$name: Read response to $type didn't match any Reading";
    } else {
        Log3 $name, 4, "$name: Read response matched " . scalar(@matched) .", unmatch " . scalar(@unmatched) . " Reading(s)";
        Log3 $name, 5, "$name: Read response to $type matched " . join ' ', @matched;
        Log3 $name, 5, "$name: Read response to $type did not match " . join ' ', @unmatched if (@unmatched);
    }
    
    EvalFunctionCall($hash, $buffer, 'parseFunction1', $type);
    readingsEndUpdate($hash, 1);
    EvalFunctionCall($hash, $buffer, 'parseFunction2', $type);
    DoDeleteIfUnmatched($hash, $type, @matched) if ($hash->{DeleteIfUnmatched});
    HandleSendQueue("direct:".$name);  
    CleanupParsers($hash);
    return;
}


###################################
# add cookies to header
sub PrepareCookies {
    my $hash    = shift;
    my $url     = shift;
    my $name    = $hash->{NAME};
    my $uriPath = '';
    my $cookies = '';
    
    if ($url =~ /
    ^(http|https):\/\/               # $1: proto
    (([^:\/]+):([^:\/]+)@)?          # $2: auth, $3:user, $4:password
    ([^:\/]+|\[[0-9a-f:]+\])         # $5: host or IPv6 address
    (:\d+)?                          # $6: port
    (\/.*)$                          # $7: path
    /xi ) {
        $uriPath = $7;
    }
    #Log3 $name, 5, "$name: DoCookies called, path=$uriPath";
    return if (!$hash->{HTTPCookieHash});
    
    foreach my $cookie ( sort keys %{ $hash->{HTTPCookieHash} } ) {
        my $cPath = $hash->{HTTPCookieHash}{$cookie}{Path};
        my $idx   = index( $uriPath, $cPath );      # Beginn des neuen URL-Pfads in einem Cooke-Pfad
        #Log3 $name, 5, "$name: DoCookies checking cookie $hash->{HTTPCookieHash}{$cookie}{Name} path $cPath";
        if ( !$uriPath || !$cPath || $idx == 0 ) {
            Log3 $name, 5,
                  "$name: HandleSendQueue is using Cookie $hash->{HTTPCookieHash}{$cookie}{Name} "
                . "with path $hash->{HTTPCookieHash}{$cookie}{Path} and Value "
                . "$hash->{HTTPCookieHash}{$cookie}{Value} (key $cookie, destination path is $uriPath)";
            $cookies .= "; " if ($cookies);
            $cookies .= $hash->{HTTPCookieHash}{$cookie}{Name} . "=" . $hash->{HTTPCookieHash}{$cookie}{Value};
        }
        else {
            Log3 $name, 5, "$name: DoCookies no cookie path match for $uriPath";
            Log3 $name, 5, "$name: DoCookies is ignoring Cookie $hash->{HTTPCookieHash}{$cookie}{Name} ";
            Log3 $name, 5, "$name: " . unpack( 'H*', $cPath );
            Log3 $name, 5, "$name: " . unpack( 'H*', $uriPath );
        }
    }
    Log3 $name, 5, "$name: DoCookies is adding Cookie header: $cookies" if ($cookies);
    return $cookies;
}


#################################################################
# set parameters for HttpUtils from request into hash
sub FillHttpUtilsHash {
    my $hash     = shift;
    my $name     = $hash->{NAME};
    my $request  = $hash->{REQUEST};
    my $huHash   = {};
    my $fDefault = ($featurelevel > 5.9 ? 1 : 0);
    
    $huHash->{redirects}       = 0;
    $huHash->{loglevel}        = 4;
    $huHash->{callback}        = \&ReadCallback;
    $huHash->{url}             = $request->{url};
    $huHash->{header}          = $request->{header};
    $huHash->{data}            = $request->{data} // '';
    $huHash->{timeout}         = AttrVal( $name, "timeout", 2 );
    $huHash->{httpversion}     = AttrVal( $name, "httpVersion", "1.0" );
    $huHash->{ignoreredirects} = (AttrVal($name, "handleRedirects", $fDefault) ? 1 : $request->{ignoreredirects});
    $huHash->{noshutdown}      = 1 if (AttrVal($name, "noShutdown", 0));
    $huHash->{method}          = $request->{method} if ($request->{method});
    $huHash->{DEVHASH}         = $hash;
    Log3 $name, 5, "$name: HandleSendQueue - call with HTTP METHOD: $huHash->{method}" if ($request->{method});
    
    my $sslArgList = AttrVal( $name, "sslArgs", undef );
    if ($sslArgList) {
        Log3 $name, 5, "$name: sslArgs is set to $sslArgList";
        my %sslArgs = split( ',', $sslArgList );
        Log3 $name, 5, "$name: sslArgs huHash keys:   " . join( ",", keys %sslArgs );
        Log3 $name, 5, "$name: sslArgs huHash values: " . join( ",", values %sslArgs );
        $huHash->{sslargs} = \%sslArgs;
    }

    # do user defined replacements first
    if ( $hash->{'.ReplacementEnabled'} ) {
        $huHash->{header} = DoReplacement($hash, $request->{type}, $huHash->{header} ) if ($huHash->{header});
        $huHash->{data}   = DoReplacement($hash, $request->{type}, $huHash->{data} )   if ($huHash->{data});
        $huHash->{url}    = DoReplacement($hash, $request->{type}, $huHash->{url} );
    }

    # then replace $val in header, data and URL with value from request (setVal) if it is still there
    my $value = $request->{value} // '';
    $huHash->{header} =~ s/\$val/$value/g if ($huHash->{header});
    $huHash->{data}   =~ s/\$val/$value/g if ($huHash->{data});;
    $huHash->{url}    =~ s/\$val/$value/g;

    # sid replacement is also done here - just before sending so changes in session while request was queued will be reflected
    if ( $hash->{sid} ) {
        $huHash->{header} =~ s/\$sid/$hash->{sid}/g if ($huHash->{header});
        $huHash->{data}   =~ s/\$sid/$hash->{sid}/g if ($huHash->{data});
        $huHash->{url}    =~ s/\$sid/$hash->{sid}/g;
    }

    if (AttrVal($name, "enableCookies", $fDefault)) {
        my $cookies = PrepareCookies($hash, $huHash->{url});
        if ($cookies) {
            $huHash->{header} .= "\r\n" if ( $huHash->{header} );
            $huHash->{header} .= "Cookie: " . $cookies;
        }
    }
    return $huHash;
}


##################################################
# can we send another request or is it too early?
sub ReadyForSending {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my $now    = gettimeofday();
    my $last   = $hash->{'.LASTSEND'} // 0;

    if (!$init_done) {              # fhem not initialized, wait with IO
        StartQueueTimer($hash, \&HTTPMOD::HandleSendQueue, {log => 'init not done, delay sending from queue'});
        return;
    }
    if ($hash->{BUSY}) {            # still waiting for reply to last request
        if ($now > $last + max(15, AttrVal($name, "timeout", 2) *2)) {
            Log3 $name, 5, "$name: HandleSendQueue - still waiting for reply, timeout is over twice - this should never happen. Stop waiting";
            $hash->{BUSY} = 0;      # waited long enough, clear busy flag and continue
        }
        else {
            my $qDelay = AttrVal( $name, "queueDelay", 1 );
            $qDelay *= 2 if ($now > $last + ($qDelay *2));
            StartQueueTimer($hash, \&HTTPMOD::HandleSendQueue, {delay => $qDelay, log => 'still waiting for reply to last request'});
            return;
        }
    }
    my $minSendDelay = AttrVal($name, "minSendDelay", 0.2);
    if ($now < $last + $minSendDelay) {
        StartQueueTimer($hash, \&HTTPMOD::HandleSendQueue, {log => "minSendDelay $minSendDelay not over"});
        return;
    }
    return 1;
}


#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit $direct:$name
sub HandleSendQueue {
    my $arg    = shift;
    my ($calltype, $name) = split(':', $arg);
    my $hash   = $defs{$name};
    my $queue  = $hash->{QUEUE};
    my $qlen   = ($hash->{QUEUE} ? scalar(@{ $hash->{QUEUE} }) : 0 );
    my $now    = gettimeofday();
    my $qDelay = AttrVal( $name, "queueDelay", 1 );
    my $request;
    
    Log3 $name, 5, "$name: HandleSendQueue called from " . FhemCaller() . ", qlen = $qlen";
    StopQueueTimer($hash, {silent => 1});

    CLEANLOOP: {                                                # get first usable entry or return
        if(!$queue || !scalar(@{$queue})) {                     # nothing in queue -> return
            Log3 $name, 5, "$name: HandleSendQueue found no usable entry in queue";
            return;
        }                       
        $request = $queue->[0];                                 # get top element from Queue
        #Log3 $name, 5, "$name: HandleSendQueue - next request is " . Dumper $request;
        next CLEANLOOP if (!$request || !$request->{url});      # skip invalid entry (should not happen)
        last CLEANLOOP;
    } continue {
        shift(@{$queue});                                       # remove unusable first element and iterate
    }
    return if (!ReadyForSending($hash));                        # check busy and delays

    shift( @{$queue} );                                         # first element is good and will be used now, remove it from queue (after delays are ok)
    $hash->{BUSY}        = 1;                                   # queue is busy until response is received
    $hash->{'.LASTSEND'} = $now;                                # remember when last sent
    $hash->{REQUEST}     = $request;
    $hash->{value}       = $request->{value};                   # make value accessible for user defined replacements / expressions
    
    my $huHash = FillHttpUtilsHash($hash);

    Log3 $name, 4,
          "$name: HandleSendQueue sends $request->{type} with timeout $huHash->{timeout} to "
        . "$huHash->{url}, "
        . ( $huHash->{data}   ? "\r\ndata: $huHash->{data}, "   : "No Data, " )
        . ( $huHash->{header} ? "\r\nheader: $huHash->{header}" : "No Header" );

    HttpUtils_NonblockingGet($huHash);
    StartQueueTimer($hash, \&HTTPMOD::HandleSendQueue);
    return;
}




######################################################################################################
# queue requests
sub AddToSendQueue {
    my $hash    = shift;
    my $request = shift;
    my $name    = $hash->{NAME};

    $request->{retryCount}      = 0 if (!$request->{retryCount});
    $request->{ignoreredirects} = 0 if (!$request->{ignoreredirects});
    $request->{context}         = 'unknown' if (!$request->{context});
    $request->{type}            = 'unknown' if (!$request->{type});
    $request->{num}             = 'unknown' if (!$request->{num});
    
    my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
    #Log3 $name, 4, "$name: AddToQueue adds $request->{type}, initial queue len: $qlen" . ($request->{'priority'} ? ", priority" : "");
    Log3 $name, 5, "$name: AddToQueue " . ($request->{'priority'} ? "prepends " : "adds ") . 
            "type $request->{type} to " .
            "URL $request->{url}, " .
            ($request->{data} ? "data $request->{data}, " : "no data, ") .
            ($request->{header} ? "header $request->{header}, " : "no headers, ") .
            ($request->{ignoreredirects} ? "ignore redirects, " : "") .
            "retry " . ($request->{'retryCount'} // 0) .
            ", initial queue len: $qlen";
    if(!$qlen) {
        $hash->{QUEUE} = [ $request ];
    } 
    else {
        if ($qlen > AttrVal($name, "queueMax", 20)) {
            Log3 $name, 3, "$name: AddToQueue - send queue too long ($qlen), dropping request ($request->{'type'}), BUSY = $hash->{BUSY}";
        } else {
            if ($request->{'priority'}) {
                unshift (@{$hash->{QUEUE}}, $request); # an den Anfang
            } else {
                push(@{$hash->{QUEUE}}, $request);     # ans Ende
            }
        }
    }
    HandleSendQueue("direct:".$name) if (!$request->{'priority'});   # if prio is set, wait until all steps are added to the front - Auth will call HandleSendQueue then.
    return;
}


1;
=pod
=item device
=item summary retrieves readings from devices with an HTTP Interface
=item summary_DE fragt Readings von Geräten mit HTTP-Interface ab
=begin html

<a name="HTTPMOD"></a>
<h3>HTTPMOD</h3>

<ul>
    This module provides a generic way to retrieve information from devices with an HTTP Interface and store them in Readings or send information to such devices. 
    It queries a given URL with Headers and data defined by attributes. <br>
    From the HTTP Response it extracts Readings named in attributes using Regexes, JSON or XPath also defined by attributes. <br>
    To send information to a device, set commands can be configured using attributes.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This Module uses the non blocking HTTP function HttpUtils_NonblockingGet provided by FHEM's HttpUtils in a new Version published in December 2013.<br>
            If not already installed in your environment, please update FHEM or install it manually using appropriate commands from your environment.<br>
            Please also note that Fhem HttpUtils need the global attribute dnsServer to be set in order to work really non blocking even when dns requests can not be answered.
        </li>
        
    </ul>
    <br>

    <a name="HTTPMODdefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; HTTPMOD &lt;URL&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the given URL every Interval seconds, sends optional headers 
        and data and then parses the response.<br>
        URL can be "none" and Interval can be 0 if you prefer to only query data manually with a get command and not automatically in a defined interval.<br>
        <br>
        Example:<br>
        <br>
        <ul><code>define PM HTTPMOD http://MyPoolManager/cgi-bin/webgui.fcgi 60</code></ul>
    </ul>
    <br>

    <a name="HTTPMODconfiguration"></a>
    <b>Simple configuration of HTTP Devices</b><br><br>
    <ul>
        In a simple configuration you don't need to define get or set commands. One common HTTP request is automatically sent in the 
        interval specified in the define command and to the URL specified in the define command.<br>
        Optional HTTP headers can be specified as <code>attr requestHeader1</code> to <code>attr requestHeaderX</code>, <br>
        optional POST data as <code>attr requestData</code> and then 
        pairs of <code>attr readingXName</code> and <code>attr readingXRegex</code>, 
        <code>attr readingXXPath</code>, <code>attr readingXXPath-Strict</code> or <code>attr readingXJSON</code>
        to define how values are parsed from the HTTP response and in which readings they are stored. <br>
        (The old syntax <code>attr readingsNameX</code> and <code>attr readingsRegexX</code> is still supported 
        but it can go away in a future version of HTTPMOD so the new one with <code>attr readingXName</code> 
        and <code>attr readingXRegex</code> should be preferred)
        <br><br>
        Example for a PoolManager 5:<br><br>
        <ul><code>
            define PM HTTPMOD http://MyPoolManager/cgi-bin/webgui.fcgi 60<br>
            <br>
            attr PM enableControlSet 1<br>
            attr PM enableCookies 1<br>
            attr PM enforceGoodReadingNames 1<br>
            attr PM handleRedirects 1<br>
            <br>
            attr PM reading01Name PH<br>
            attr PM reading01Regex 34.4001.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM reading02Name CL<br>
            attr PM reading02Regex 34.4008.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM reading03Name TEMP<br>
            attr PM reading03Regex 34.4033.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM requestData {"get" :["34.4001.value" ,"34.4008.value" ,"34.4033.value", "14.16601.value", "14.16602.value"]}<br>
            attr PM requestHeader1 Content-Type: application/json<br>
            attr PM requestHeader2 Accept: */*<br>
            <br>
            attr PM stateFormat {sprintf("%.1f Grad, PH %.1f, %.1f mg/l Chlor", ReadingsVal($name,"TEMP",0), ReadingsVal($name,"PH",0), ReadingsVal($name,"CL",0))}<br>
        </code></ul>
        <br>
        This example uses regular expressions to parse the HTTP response. A regular expression describes what text is around the value that is supposed to be assigned to a reading. The value itself has to match the so called capture group of the regular expression. That is the part of the regular expression inside ().
        In the above example "([\d\.]+)" refers to numerical digits or points between double quotation marks. Only the string consisting of digits and points will match inside (). This piece is assigned to the reading.
        
        You can also use regular expressions that have several capture groups which might be helpful when parsing tables. In this case an attribute like 
        <code><ul>
            reading02Regex something[ \t]+([\d\.]+)[ \t]+([\d\.]+)
        </code></ul>
        could match two numbers. When you specify only one reading02Name like 
        <code><ul>
            reading02Name Temp
        </code></ul>
        the name Temp will be used with the extension -1 and -2 thus giving a reading Temp-1 for the first number and Temp-2 for the second.
        You can also specify individual names for several readings that get parsed from one regular expression with several capture groups by 
        defining attributes 
        <code><ul>
            reading02-1Name<br>
            reading02-2Name
            ...
        </code></ul>
        The same notation can be used for formatting attributes like readingXOMap, readingXFormat and so on.<br>
        <br>
        The usual way to define readings is however to have an individual regular expression with just one capture group per reading as shown in the above example.
        <br>
    </ul>
    <br>

    <a name="HTTPMODformat"></a>
    <b>formating and manipulating values / readings</b><br><br>
    <ul>
        Values that are parsed from an HTTP response can be further treated or formatted with the following attributes:<br>
        <ul><code>
          (reading|get)[0-9]*(-[0-9]+)?OExpr<br>
          (reading|get)[0-9]*(-[0-9]+)?OMap<br>
          (reading|get)[0-9]*(-[0-9]+)?Format<br>
          (reading|get)[0-9]*(-[0-9]+)?Decode<br>
          (reading|get)[0-9]*(-[0-9]+)?Encode
        </code></ul>

        They can all be specified for an individual reading, for all readings in one match (e.g. if a regular expression has several capture groups)
        or for all readings in a get command (defined by getXX) or for all readings in the main reading list (defined by readingXX):
        <ul><code>
          reading01Format %.1f
        </code></ul>
        will format the reading with the name specified by the attribute reading01Name to be numerical with one digit after the decimal point. <br>
        If the attribute reading01Regex is used and contains several capture groups then the format will be applied to all readings thet are parsed 
        by this regex unless these readings have their own format specified by reading01-1Format, reading01-2Format and so on.
        <br>
        <ul><code>
          reading01-2Format %.1f
        </code></ul>
        Can be used in cases where a regular expression specified as reading1regex contains several capture groups or an xpath specified 
        as reading01XPath creates several readings. 
        In this case reading01-2Format specifies the format to be applied to the second match.
        <br>
        <ul><code>
          readingFormat %.1f
        </code></ul>
        applies to all readings defined by a reading-Attribute that have no more specific format.
        <br>
        <br>
        If you need to do some calculation on a raw value before it is used as a reading, you can define the attribute <code>readingOExpr</code>.<br> 
        It defines a Perl expression that is used in an eval to compute the readings value. The raw value will be in the variable $val.<br>
        Example:<br>
        <ul><code>
            attr PM reading03OExpr $val * 10<br>
        </code></ul>
        Just like in the above example of the readingFormat attributes, readingOExpr and the other following attributes 
        can be applied on several levels.
        <br>
        <br>
        To map a raw numerical value to a name, you can use the readingOMap attribute. 
        It defines a mapping from raw values read from the device to visible values like "0:mittig, 1:oberhalb, 2:unterhalb". <br>
        Example:<br>
        <ul><code>
            attr PM reading02-3OMap 0:kalt, 1:warm, 2:sehr warm
        </code></ul>
        <br>
        If the value read from a http response is 1, the above map will transalte it to the string warm and the reading value will be set to warm.<br>
        
        To convert character sets, the module can first decode a string read from the device and then encode it again. For example:
        <ul><code>
            attr PM getDecode UTF-8
        </code></ul>
        This applies to all readings defined for Get-Commands.
        
    </ul>
    <br>

    <a name="HTTPMODsetconfiguration"></a>
    <b>Configuration to define a <code>set</code> command and send data to a device</b><br><br>
    <ul>
        When a set option is defined by attributes, the module will use the value given to the set command 
        and translate it into an HTTP-Request that sends the value to the device. <br>
        HTTPMOD has a built in replacement that replaces $val in URLs, headers or Post data with the value passed in the set command.<br>
        This value is internally stored in the internal "value" ($hash->{value}) so it can also be used in a user defined replacement.
        <br>
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
        Post to URL <code>http://MyPoolManager/cgi-bin/webgui.fcgi</code> and with Post Data as <br>
        <code>{"set" :{"34.3118.value" :"10" }}</code><br>
        The optional attributes set01Min and set01Max define input validations that will be checked in the set function.<br>
        the optional attribute set01Hint will define the way the Fhemweb GUI shows the input. This might be a slider or a selection list for example.<br>
        <br>
        The HTTP response to such a request will be ignored unless you specify the attribute <code>setParseResponse</code> 
        for all set commands or <code>set01ParseResponse</code> for the set command with number 01.<br>
        If the HTTP response to a set command is parsed then this is done like the parsing of responses to get commands and you can use the attributes ending e.g. on 
        Format, Encode, Decode, OMap and OExpr to manipulate / format the values read.
        <br>
        If a parameter to a set command is not numeric but should be passed on to the device as text, then you can specify the attribute setTextArg. For example: 
        <ul><code>
            attr PM set01TextArg
        </code></ul>
        If a set command should not require a parameter at all, then you can specify the attribute NoArg. For example: 
        <ul><code>
            attr PM set03Name On
            attr PM set03NoArg
        </code></ul>
        <br>
        
    </ul>
    <br>

    <a name="HTTPMODgetconfiguration"></a>
    <b>Configuration to define a <code>get</code> command</b><br><br>
    <ul>        
        
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
        alternative lower update frequency. When the interval defined initially in the define is over and the normal readings
        are read from the device, the update function will check for additional get parameters that should be included
        in the update cycle.
        If a PollDelay is specified for a get parameter, the update function also checks if the time passed since it has last read this value 
        is more than the given PollDelay. If not, this reading is skipped and it will be rechecked in the next cycle when 
        interval is over again. So the effective PollDelay will always be a multiple of the interval specified in the initial define.<br>
        <br>
        Please note that each defined get command that is included in the regular update cycle will create its own HTTP request. So if you want to extract several values from the same request, it is much more efficient to do this by defining readingXXName and readingXXRegex, XPath or JSON attributes and to specify an interval and a URL in the define of the HTTPMOD device. 
        
    </ul>
    <br>

    <a name="HTTPMODsessionconfiguration"></a>
    <b>Handling sessions and logging in</b><br><br>
    <ul>
        In simple cases logging in works with basic authentication. In the case HTTPMOD accepts a username and password as part of the URL
        in the form http://User:Password@192.168.1.18/something<br>
        However basic auth is seldom used. If you need to fill in a username and password in a HTML form and the session is then managed by a session id, 
        here is how to configure this:
        
        when sending data to an HTTP-Device in a set, HTTPMOD will replace any <code>$sid</code> in the URL, Headers and Post data 
        with the internal <code>$hash->{sid}</code>. 
        To authenticate towards the device and give this internal a value, you can use an optional multi step login procedure 
        defined by the following attributes: <br>
        <ul>
        <li>sid[0-9]*URL</li>
        <li>sid[0-9]*Data.*</li>
        <li>sid[0-9]*Header.*</li>
        <li>idRegex</li>
        <li>idJSON</li>
        <li>idXPath</li>
        <li>idXPath-Strict</li>
        <li>(get|set|sid)[0-9]*IdRegex</li>
        <li>(get|set|sid)[0-9]*IdJSON</li>
        <li>(get|set|sid)[0-9]*IdXPath</li>
        <li>(get|set|sid)[0-9]*IdXPath-Strict</li>
        </ul><br>
        Each step can have a URL, Headers and Post Data. To extract the actual session Id, you can use regular expressions, JSON or XPath just like for the parsing of readings but with the attributes (get|set|sid)[0-9]*IdRegex, (get|set|sid)[0-9]*IdJSON, (get|set|sid)[0-9]*IdXPath or (get|set|sid)[0-9]*IdXPath-Strict.<br>
        An extracted session Id will be stored in the internal <code>$hash->{sid}</code>.<br>
        HTTPMOD will create a sorted list of steps (the numbers between sid and URL / Data / Header) 
        and the loop through these steps and send the corresponding requests to the device. 
        For each step a $sid in a Header or Post Data will be replaced with the current content of <code>$hash->{sid}</code>. <br>
        Using this feature, HTTPMOD can perform a forms based authentication and send user name, password or other necessary data to the device and save the session id for further requests.<br>
        If for one step not all of the URL, Data or Header Attributes are set, then HTTPMOD tries to use a 
        <code>sidURL</code>, <code>sidData.*</code> or <code>sidHeader.*</code> Attribue (without the step number after sid). 
        This way parts that are the same for all steps don't need to be defined redundantly. <br>
        <br>
        To determine when this login procedure is necessary, HTTPMOD will first try to send a request without 
        doing the login procedure. If the result contains an error that authentication is necessary, then a login is performed. 
        To detect such an error in the HTTP response, you can again use a regular expression, JSON or XPath, this time with the attributes 
        <ul>
        <li>reAuthRegex</li>
        <li>reAuthJSON</li>
        <li>reAuthXPath</li>
        <li>reAuthXPath-Strict</li>
        <li>[gs]et[0-9]*ReAuthRegex</li>
        <li>[gs]et[0-9]*ReAuthJSON</li>
        <li>[gs]et[0-9]*ReAuthXPath</li>
        <li>[gs]et[0-9]*ReAuthXPath-Strict</li>
        </ul>
        <br>
        reAuthJSON or reAuthXPath typically only extract one piece of data from a response. 
        If the existance of the specified piece of data is sufficent to start a login procedure, then nothing more needs to be defined to detect this situation. 
        If however the indicator is a status code that contains different values depending on a successful request and a failed request if a new authentication is needed, 
        then you can combine things like reAuthJSON with reAuthRegex. In this case the regex is only matched to the data extracted by JSON (or XPath). 
        This way you can easily extract the status code using JSON parsing and then specify the code that means "authentication needed" as a regular expression. <br>
        <br>
        Example for a multi step login procedure: 
        <br><br>        
        <ul><code>
            attr PM reAuthRegex /html/dummy_login.htm 
            attr PM sidURL http://192.168.70.90/cgi-bin/webgui.fcgi?sid=$sid<br>
            attr PM sidHeader1 Content-Type: application/json<br>
            attr PM sid1IdRegex wui.init\('([^']+)'<br>
            attr PM sid2Data {"set" :{"9.17401.user" :"fhem" ,"9.17401.pass" :"password" }}<br>
            attr PM sid3Data {"set" :{"35.5062.value" :"128" }}<br>
            attr PM sid4Data {"set" :{"42.8026.code" :"pincode" }}<br>
        </ul></code>

        In this case HTTPMOD detects that a login is necessary by looking for the pattern /html/dummy_login.htm in the HTTP response. 
        If it matches, it starts a login sequence. In the above example all steps request the same URL. In step 1 only the defined header
        is sent in an HTTP get request. The response will contain a session id that is extraced with the regex wui.init\('([^']+)'.
        In the next step this session id is sent in a post request to the same URL where tha post data contains a username and password.
        The a third and a fourth request follow that set a value and a code. The result will be a valid and authorized session id that can be used in other requests where $sid is part of a URL, header or post data and will be replaced with the session id extracted above.<br>
        <br>
        In the special case where a session id is set as a HTTP-Cookie (with the header Set-cookie: in the HTTP response) HTTPMOD offers an even simpler way. With the attribute enableCookies a basic cookie handling mechanism is activated that stores all cookies that the server sends to the HTTPMOD device and puts them back as cookie headers in the following requests. <br>
        For such cases no sidIdRegex and no $sid in a user defined header is necessary.<br>
        
    </ul>
    <br>

    <a name="HTTPMODjsonconfiguration"></a>
    <b>Parsing JSON</b><br><br>
    <ul>
        If a webservice delivers data in JSON format, HTTPMOD can directly parse JSON which might be easier in this case than definig regular expressions.<br>
        The next example shows the data that can be requested from a Poolmanager with the following partial configuration:

        <ul><code>
        define test2 HTTPMOD none 0<br>
        <br>
        attr PM enableControlSet 1<br>
        attr PM enableCookies 1<br>
        attr PM enforceGoodReadingNames 1<br>
        attr PM handleRedirects 1<br>
        <br>
        attr test2 get01Name Chlor<br>
        attr test2 getURL http://192.168.70.90/cgi-bin/webgui.fcgi<br>
        attr test2 getHeader1 Content-Type: application/json<br>
        attr test2 getHeader2 Accept: */*<br>
        attr test2 getData {"get" :["34.4008.value"]}<br>
        </ul></code>

        The data in the HTTP response looks like this:
        
        <ul><pre>
        {
            "data": {
                    "34.4008.value": "0.25"
            },
            "status":       {
                    "code": 0
            },
            "event":        {
                    "type": 1,
                    "data": "48.30000.0"
            }
        }
        </ul></pre>

        the classic way to extract the value 0.25 into a reading with the name Chlor with a regex would have been
        <ul><code>
            attr test2 get01Regex 34.4008.value":[ \t]+"([\d\.]+)"
        </ul></code>
        
        with JSON you can write 
        <ul><code>
            attr test2 get01JSON data_34.4008.value 
        </code></ul>

        If you define an explicit json reading with the get01JSON or reading01JSON syntax and there is no full match, HTTPMOD will try to do a regex match using the defined string. If for example the json data contains an array like 

        <ul><code>
         "modes":["Off","SimpleColor","RainbowChase","BobblySquares","Blobs","CuriousCat","Adalight","UDP","DMX"],
        </code></ul>

        a Configuration could be 

        <ul><code>
            attr test2 get01Name ModesList
            attr test2 get01JSON modes 
        </code></ul>
        
        The result will be treated as a list just like a list of XPath matches or Regex matches. 
        So it will create readings ModlesList-1 ModesList-2 and so on as described above (simple Comfiguration).<br>
        You can also define a recombineExpr to recombine the match list into one reading e.g. as 
        <ul><code>
            attr test2 reading01RecombineExpr join ",", @matchlist
        </code></ul>
        
        If you don't care about the naming of your readings, you can simply extract all JSON data with 
        <ul><code>
            attr test2 extractAllJSON 1
        </ul></code>
        which would apply to all data read from this device and create the following readings out of the HTTP response shown above:<br>
        
        <ul><code>
            data_34.4008.value 0.25 <br>
            event_data 48.30000.0 <br>
            event_type 1 <br>
            status_code 0 <br>
        </ul></code>
        
        or you can specify
        <ul><code>
            attr test2 get01ExtractAllJSON 1
        </ul></code>
        which would only apply to all data read as response to the get command defined as get01.        
        <br>
        Another option is setting extractAllJSON or get01ExtractAllJSON to 2. In this case the module analyzes the JSON data when it is first read, creates readingXXName and readingXXJSON attributes for you and then removes the extractAllJSON attribute.
    </ul>
    <br>

    <a name="HTTPMODxpathconfiguration"></a>
    <b>Parsing http / XML using xpath</b><br><br>
    <ul>
        
        Another alternative to regex parsing is the use of XPath to extract values from HTTP responses.<br>
        The following example shows how XML data can be parsed with XPath-Strict or HTML Data can be parsed with XPath. <br>
        Both work similar and the example uses XML Data parsed with the XPath-Strict option:

        If The XML data in the HTTP response looks like this:
        
        <ul><code>
        &lt;root xmlns:foo=&quot;http://www.foo.org/&quot; xmlns:bar=&quot;http://www.bar.org&quot;&gt;<br>
        &lt;actors&gt;<br>
        &lt;actor id=&quot;1&quot;&gt;Peter X&lt;/actor&gt;<br>
        &lt;actor id=&quot;2&quot;&gt;Charles Y&lt;/actor&gt;<br>
        &lt;actor id=&quot;3&quot;&gt;John Doe&lt;/actor&gt;<br>
        &lt;/actors&gt;<br>
        &lt;/root&gt;
        </ul></code>
       
        with XPath you can write        
        <ul><code>
            attr htest reading01Name Actor<br>
            attr htest reading01XPath-Strict //actor[2]/text()
        </ul></code>
        This will create a reading with the Name "Actor" and the value "Charles Y".<br>
        <br>
        Since XPath specifications can define several values / matches, HTTPMOD can also interpret these and store them in 
        multiple readings:
        <ul><code>
            attr htest reading01Name Actor<br>
            attr htest reading01XPath-Strict //actor/text()
        </ul></code>
        will create the readings 
        <ul><code>
            Actor-1 Peter X<br>
            Actor-2 Charles Y<br>
            Actor-3 John Doe
        </ul></code>        

    </ul>
    <br>

    <a name="HTTPMODnamedGroupsconfiguration"></a>
    <b>Parsing with named regex groups</b><br><br>
    <ul>
        If you are an expert with regular expressions you can also use named capture groups in regexes for parsing and HTTPMOD will use the group names as reading names. This feature is only meant for experts who know exactly what they are doing and it is not necessary for normal users.
        For formatting such readings the name of a capture group can be matched with a readingXYName attribute and then the correspondug formatting attributes will be used here.
    </ul>
    <br>
    
    <a name="HTTPMODreplacements"></a>
    <b>Further replacements of URL, header or post data</b><br><br>
    <ul>
        sometimes it is helpful to dynamically change parts of a URL, HTTP header or post data depending on existing readings, internals or perl expressions at runtime. <br>
        HTTPMOD has two built in replacements: one for values passed to a set or get command and the other one for a session id.<br>
        Before a request is sent, the placeholder $val is replaced with the value that is passed in a set command or an optional value that can be passed in a get command (see getXTextArg). This value is internally stored in the internal "value" so it can also be used in a user defined replacement as explaind in this section.<br>
        The other built in replacement is for the session id. If a session id is extracted via a regex, JSON or XPath the it is stored in the internal "sid" and the placeholder $sid in a URL, header or post data is replaced by the content of this internal.
        
        User defined replacements can exted this functionality and this might be needed to pass further variables to a server, a current date, a CSRF-token or other things. <br>
        To support this, HTTPMOD offers user defined replacements that are as well applied to a request before it is sent to the server.
        A replacement can be defined with the attributes 
        <ul><code>
          "replacement[0-9]*Regex "<br>
          "replacement[0-9]*Mode "<br>
          "replacement[0-9]*Value "<br>
          "[gs]et[0-9]*Replacement[0-9]*Value "
        </ul></code>        
        <br>
        A replacement always replaces a match of a regular expression. 
        The way the replacement value is defined can be specified with the replacement mode. If the mode is <code>reading</code>, 
        then the value is interpreted as the name of a reading of the same device or as device:reading to refer to another device.
        If the mode is <code>internal</code>, then the value is interpreted as the name of an internal of the same device or as device:internal to refer to another device.<br>
        The mode <code>text</code> will use the value as a static text and the mode <code>expression</code> will evaluate the value as a perl expression to compute the replacement. Inside such a replacement expression it is possible to refer to capture groups of the replacement regex.<br>
        The mode <code>key</code> will use a value from a key / value pair that is stored in an obfuscated form in the file system with the set storeKeyValue command. This can be useful for storing passwords.<br>
        <br>
        Example:
        <ul><code>
            attr mydevice getData {"get" :["%%value%%.value"]} <br>
            attr mydevice replacement01Mode text <br>
            attr mydevice replacement01Regex %%value%% <br>
            <br>
            attr mydevice get01Name Chlor <br>
            attr mydevice get01Replacement01Value 34.4008 <br>
            <br>
            attr mydevice get02Name Something<br>
            attr mydevice get02Replacement01Value 31.4024 <br>
            <br>
            attr mydevice get05Name profile <br>
            attr mydevice get05URL http://www.mydevice.local/getprofile?password=%%password%% <br>
            attr mydevice replacement02Mode key <br>
            attr mydevice replacement02Regex %%password%% <br>
            attr mydevice get05Replacement02Value password <br>         
        </ul></code>        
        defines that %%value%% will be replaced by a static text.<br>
        All Get commands will be HTTP post requests of a similar form. Only the %%value%% will be different from get to get.<br>
        The first get will set the reading named Chlor and for the request it will take the generic getData and replace %%value%% with 34.4008.<br>
        A second get will look the same except a different name and replacement value. <br>
        With the command <code>set storeKeyValue password geheim</code> you can store the password geheim in an obfuscated form in the file system. To use this password and send it in a request you can use the above replacement with mode key. The value password will then refer to the ofuscated string stored with the key password.<br>
        <br>
        HTTPMOD has two built in replacements: One for session Ids and another one for the input value in a set command.
        The placeholder $sid is always replaced with the internal <code>$hash->{sid}</code> which contains the session id after it is extracted from a previous HTTP response. If you don't like to use the placeholder $sid the you can define your own replacement for example like:
        <ul><code>
            attr mydevice replacement01Mode internal<br>
            attr mydevice replacement01Regex %session% <br>
            attr mydevice replacement01Value sid<br>
        </ul></code>        
        Now the internal <code>$hash->{sid}</code> will be used as a replacement for the placeholder %session%.<br>
        <br>
        In the same way a value that is passed to a set-command can be put into a request with a user defined replacement. In this case the internal <code>$hash->{value}</code> will contain the value passed to the set command. It might even be a string containing several values that could be put into several different positions in a request by using user defined replacements.
        <br>
        The mode expression allows you to define your own replacement syntax:
        <ul><code>          
            attr mydevice replacement01Mode expression <br>
            attr mydevice replacement01Regex {{([^}]+)}}<br>
            attr mydevice replacement01Value ReadingsVal("mydevice", $1, "")<br>
            attr mydevice getData {"get" :["{{temp}}.value"]} 
        </ul></code>        
        In this example any {{name}} in a URL, header or post data will be passed on to the perl function ReadingsVal 
        which uses the string between {{}} as second parameter. This way one defined replacement can be used for many different
        readings.
                
    </ul>
    <br>

    <a name="HTTPMODaging"></a>
    <b>replacing reading values when they have not been updated / the device did not respond</b><br><br>
    <ul>
        If a device does not respond then the values stored in readings will keep the same and only their timestamp shows that they are outdated. 
        If you want to modify reading values that have not been updated for a number of seconds, you can use the attributes
        <ul><code>
          (reading|get)[0-9]*(-[0-9]+)?MaxAge<br>
          (reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacementMode<br>
          (reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacement<br>
        </ul></code>        
        Every time the module tries to read from a device, it will also check if readings have not been updated 
        for longer than the MaxAge attributes allow. If readings are outdated, the MaxAgeReplacementMode defines how the affected
        reading values should be replaced. MaxAgeReplacementMode can be <code>text</code>, <code>reading</code>, <code>internal</code>, <code>expression</code> or <code>delete</code>. <br>
        MaxAge specifies the number of seconds that a reading should remain untouched before it is replaced. <br>
        MaxAgeReplacement contains either a static text that is used as replacement value or a Perl expression that is evaluated to 
        give the replacement value. This can be used for example to replace a temperature that has not bee updated for more than 5 minutes 
        with the string "outdated - was 12":        
        <ul><code>
            attr PM readingMaxAge 300<br>
            attr PM readingMaxAgeReplacement "outdated - was " . $val <br>
            attr PM readingMaxAgeReplacementMode expression 
        </ul></code>        
        The variable $val contains the value of the reading before it became outdated.<br>
        If the mode is delete then the reading will be deleted if it has not been updated for the defined time.<br>
        If you want to replace or delete a reading immediatley if a device doid not respond, simply set the maximum time to a number smaller than the update interval. Since the max age is checked after a HTTP request was either successful or it failed, the reading will always contain the read value or the replacement after a failed update.
    </ul>
    <br>
    
    <a name="HTTPMODset"></a>
    <b>Set-Commands</b><br>
    <ul>
        As defined by the attributes set.*Name<br>
        HTTPMOD also supports setExtensions so if you define sets named on and off, setExtensions will provide their usual sets like on-for-timer.<br>
        Since setExtensions include AttrTemplate, HTTPMOD also supports these templates.<br>
        If you set the attribute enableControlSet to 1, the following additional built in set commands are available:<br>
        <ul>
            <li><b>interval</b></li>
                set new interval time in seconds and restart the timer<br>
            <li><b>reread</b></li>
                request the defined URL and try to parse it just like the automatic update would do it every Interval seconds 
                without modifying the running timer. <br>
            <li><b>stop</b></li>
                stop interval timer.<br>
            <li><b>start</b></li>
                restart interval timer to call GetUpdate after interval seconds<br>
            <li><b>clearCookies</b></li>
                delete all saved cookies<br>
            <li><b>upgradeAttributes</b></li>
                convert the attributes for this device from the old syntax to the new one.<br>
                atributes with the description "this attribute should not be used anymore" or similar will be translated to the new syntax, e.g. readingsName1 to reading01Name.
            <li><b>storeKeyValue</b></li>
                stores a key value pair in an obfuscated form in the file system. Such values can then be used in replacements where
                the mode is "key" e.g. to avoid storing passwords in the configuration in clear text<br>
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
        
        <li><b>reading[0-9]+Name</b></li>
            specifies the name of a reading to extract with the corresponding readingRegex, readingJSON, readingXPath or readingXPath-Strict<br>
            Example:
            <code>
            attr myWebDevice reading01Name temperature
            attr myWebDevice reading02Name humidity
            </code>
            Please note that the old syntax <b>readingsName.*</b> does not work with all features of HTTPMOD and should be avoided. It might go away in a future version of HTTPMOD.
            
        <li><b>(get|set)[0-9]+Name</b></li>
            Name of a get or set command to be defined. If the HTTP response that is received after the command is parsed with an individual parse option then this name is also used as a reading name. Please note that no individual parsing needs to be defined for a get or set. If no regex, XPath or JSON is specified for the command, then HTTPMOD will try to parse the response using all the defined readingRegex, readingXPath or readingJSON attributes.
            Example:
            <code>
            attr myWebDevice get01Name temperature
            attr myWebDevice set01Name tempSoll
            </code>
            
        <li><b>(get|set|reading)[0-9]+Regex</b></li>
            If this attribute is specified, the Regex defined here is used to extract the value from the HTTP Response 
            and assign it to a Reading with the name defined in the (get|set|reading)[0-9]+Name attribute.<br>
            If this attribute is not specified for an individual Reading or get or set but without the numbers in the middle, e.g. as getRegex or readingRegex, then it applies to all the other readings / get / set commands where no specific Regex is defined.<br>
            The value to extract should be in a capture group / sub expression e.g. ([\d\.]+) in the above example. 
            Multiple capture groups will create multiple readings (see explanation above)<br>
            Using this attribute for a set command (setXXRegex) only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
            Please note that the old syntax <b>readingsRegex.*</b> does not work with all features of HTTPMOD and should be avoided. It might go away in a future version of HTTPMOD.
            If for get or set commands neither a generic Regex attribute without numbers nor a specific (get|set)[0-9]+Regex attribute is specified and also no XPath or JSON parsing specification is given for the get or set command, then HTTPMOD tries to use the parsing definitions for general readings defined in reading[0-9]+Name, reading[0-9]+Regex or XPath or JSON attributes and assigns the Readings that match here.
            Example:
            <code>
            attr myWebDevice get01Regex temperature:.([0-9]+)
            attr myWebDevice reading102Regex 34.4001.value":[ \t]+"([\d\.]+)"
            </code>
            
        <li><b>(get|set|reading)[0-9]+RegOpt</b></li>
            Lets the user specify regular expression modifiers. For example if the same regular expression should be matched as often as possible in the HTTP response, 
            then you can specify RegOpt g which will case the matching to be done as /regex/g<br>
            The results will be trated the same way as multiple capture groups so the reading name will be extended with -number. 
            For other possible regular expression modifiers see http://perldoc.perl.org/perlre.html#Modifiers
            Example:
            <code>
            attr myWebDevice reading0088Regex temperature:.([0-9]+)
            attr myWebDevice reading0088RegOpt g
            </code>
            
        <li><b>(get|set|reading)[0-9]+XPath</b></li>
            defines an xpath to one or more values when parsing HTML data (see examples above)<br>
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>          
        <li><b>get|set|reading[0-9]+XPath-Strict</b></li>
            defines an xpath to one or more values when parsing XML data (see examples above)<br>
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <li><b>(get|set|reading)[0-9]+AutoNumLen</b></li>
            In cases where a regular expression or an XPath results in multiple results and these results are stored in a common reading name with extension -number, then 
            you can modify the format of this number to have a fixed length with leading zeros. AutoNumLen 3 for example will lead to reading names ending with -001 -002 and so on.
        <li><b>(reading|get|set)[0-9]*AlwaysNum</b></li>
            if set to 1 this attributes forces reading names to end with a -1, -01 (depending on the above described AutoNumLen) even if just one value is parsed.
        <li><b>get|set|reading[0-9]+JSON</b></li>
            defines a path to the JSON object wanted by concatenating the object names. See the above example.<br>
            If you don't know the paths, then start by using extractAllJSON and the use the names of the readings as values for the JSON attribute.<br>
            Please don't forget to also specify a name for a reading, get or set. 
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <li><b>get|set[0-9]+ExtractAllJSON or extractAllJSON</b></li>
            if set to 1 it will create a reading for every JSON object. The reading names will be deducted from the JSON strings hierarchically concatenated by "_".<br>
            if set to 2 it will create attributes for naming and parsing the JSON objects to make it easier to rename or remove some of them.
        <li><b>extractAllJSONFilter</b></li>    
            is an optional regular expression that filters the readings to be created with extractAllJSON.
        <li><b>(get|set|reading)[0-9]*RecombineExpr</b></li> 
            defines an expression that is used in an eval to compute one reading value out of the list of matches. <br>
            This is supposed to be used for regexes or xpath specifications that produce multiple results if only one result that combines them is wanted. The list of matches will be in the variable @matchlist.<br>
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <li><b>get[0-9]*CheckAllReadings</b></li>
            this attribute modifies the behavior of HTTPMOD when the HTTP Response of a get command is parsed. <br>
            If this attribute is set to 1, then additionally to the matching of get specific regexe (get[0-9]*Regex), XPath or JSON
            also all the reading names and parse definitions defined in Reading[0-9]+Name and Reading[0-9]+Regex, XPath or JSON attributes are checked and if they match, the coresponding Readings are assigned as well.<br>
            This is automatically done if a get or set command is defined without its own parse attributes.
        <br>
          
        <li><b>(get|reading)[0-9]*OExpr</b></li>
            defines an optional expression that is used in an eval to compute / format a readings value after parsing an HTTP response<br>
            The raw value from the parsing will be in the variable $val.<br>
            If specified as readingOExpr then the attribute value is a default for all other readings that don't specify an explicit reading[0-9]*Expr.<br>
            Please note that the old syntax <b>readingsExpr.*</b> does not work with all features of HTTPMOD and should be avoided. It might go away in a future version of HTTPMOD.
        <li><b>(get|reading)[0-9]*Expr</b></li>
            This is the old syntax for (get|reading)[0-9]*OExpr. It should be replaced by (get|reading)[0-9]*OExpr. The set command upgradeAttributes which becomes visible when the attribute enableControlSet is set to 1, can do this renaming automatically.
        <li><b>(get|reading)[0-9]*OMap</b></li>
            Map that defines a mapping from raw value parsed to visible values like "0:mittig, 1:oberhalb, 2:unterhalb". <br>
            If specified as readingOMap then the attribute value is a default for all other readings that don't specify 
            an explicit reading[0-9]*Map.<br>
            The individual options in a map are separated by a komma and an optional space. Spaces are allowed to appear in a visible value however kommas are not possible.
        <li><b>(get|reading)[0-9]*Map</b></li>
            This is the old syntax for (get|reading)[0-9]*OMap. It should be replaced by (get|reading)[0-9]*OMap. The set command upgradeAttributes which becomes visible when the attribute enableControlSet is set to 1, can do this renaming automatically.
        <li><b>(get|set|reading)[0-9]*Format</b></li>
            Defines a format string that will be used in sprintf to format a reading value.<br>
            If specified without the numbers in the middle e.g. as readingFormat then the attribute value is a default for all other readings that don't specify an explicit reading[0-9]*Format.
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <li><b>(get|set|reading)[0-9]*Decode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw data string read from the device to a reading. 
            This can be used if the device delivers strings in an encoding like cp850 instead of utf8.<br>
            If your reading values contain Umlauts and they are shown as strange looking icons then you probably need to use this feature.
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <li><b>(get|set|reading)[0-9]*Encode</b></li> 
            defines an encoding to be used in a call to the perl function encode to convert the data string read from the device to a reading. 
            This can be used if the device delivers strings in an encoding like cp850 and after decoding it you want to reencode it to e.g. utf8.<br>
            When the attribute bodyDecode is not set to 'none' then this encoding attribute defaults to utf8.
            If your reading values contain Umlauts and they are shown as strange looking icons then you probably need to modidify this attribute.
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <li><b>bodyDecode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw http response body data string 
            read from the device before further processing / matching<br>
            If you have trouble matching special characters or if your reading values contain Umlauts 
            and they are shown as strange looking icons then you might need to use this feature.<br>
            If this attribute is set to 'auto' then HTTPMOD automatically looks for a charset header and decodes the body acordingly. 
            If no charset header is found, the body will remain undecoded.
            <br>
        <li><b>regexDecode</b></li> 
            defines an encoding to be used in a call to the perl function decode to convert the raw data string from regex attributes before further processing / matching<br>
            If you have trouble matching special characters or if you need to get around a memory leak in Perl regex processing this might help
            <br>
        <li><b>regexCompile</b></li> 
            defines that regular expressions will be precompiled when they are used for the first time and then stored internally so that subsequent uses of the same 
            regular expression will be faster. This option is turned on by default but setting this attribute to 0 will disable it.
            <br>
        <br>
            
        <li><b>(get|set)[0-9]*URL</b></li>
            URL to be requested for the get or set command. 
            If this option is missing, the URL specified during define will be used.
        <li><b>(get|set)[0-9]*Data</b></li>
            optional data to be sent to the device as POST data when the get oer set command is executed. 
            if this attribute is specified, an HTTP POST method will be sent instead of an HTTP GET
        <li><b>set[0-9]*Method</b></li>
             HTTP Method (GET, POST or PUT) which shall be used for the set.
        <li><b>(get|set)[0-9]*NoData</b></li>
            can be used to override a more generic attribute that specifies POST data for all get commands. 
            With NoData no data is sent and therefor the request will be an HTTP GET.
        <li><b>(get|set)[0-9]*Header.*</b></li>
            optional HTTP Headers to be sent to the device when the get or set command is executed
        <li><b>requestHeader.*</b></li> 
            Define an optional additional HTTP Header to set in the HTTP request <br>
        <li><b>requestData</b></li>
            optional POST Data to be sent in the request. If not defined, it will be a GET request as defined in HttpUtils used by this module<br>
        <br>

        <li><b>get[0-9]+Poll</b></li>
            if set to 1 the get is executed automatically during the normal update cycle (after the interval provided in the define command has elapsed)
        <li><b>get[0-9]+PollDelay</b></li>
            if the value should not be read in each iteration (after the interval given to the define command), then a
            minimum delay can be specified with this attribute. This has only an effect if the above Poll attribute has
            also been set. Every time the update function is called, it checks if since this get has been read the last time, the defined delay has elapsed. If not, then it is skipped this time.<br>
            PollDelay can be specified as seconds or as x[0-9]+ which means a multiple of the interval in the define command.
        <br>
        <li><b>(get|set)[0-9]*FollowGet</b></li>
            allows to chain a get command after another set or get command. <br>
            If for example you want to set a new required temerature with a set 'TargetTemp' command and this set command changes the temperature with a series 
            of HTTP requests in your heating system, then you can automaticaly do a get 'TargetTemp' to read out the new value from your heating.<br>
            The value of this attribute must match a defined get command name.
        
        <li><b>(get|set)[0-9]*TextArg</b></li>
            For a get command this defines that the command accepts a text value after the option name. 
            By default a get command doesn't accept optional values after the command name. 
            If TextArg is specified and a value is passed after the get name then this value can then be used in a request URL, header or data 
            as replacement for $val or in a user defined replacement that uses the internal "value" ($hash->{value}).<br>
            If used for a set command then it defines that the value to be set doesn't require any validation / conversion. 
            The raw value is passed on as text to the device. By default a set command expects a numerical value or a text value that is converted to a numeric value using a map.

        <li><b>set[0-9]+Min</b></li>
            Minimum value for input validation. 
        <li><b>set[0-9]+Max</b></li>
            Maximum value for input validation. 
        <li><b>set[0-9]+IExpr</b></li>
            Perl Expression to compute the raw value to be sent to the device from the input value passed to the set.
        <li><b>set[0-9]+Expr</b></li>
            This is the old syntax for (get|reading)[0-9]*IExpr. It should be replaced by (get|reading)[0-9]*IExpr. The set command upgradeAttributes which becomes visible when the attribute enableControlSet is set to 1, can do this renaming automatically.
            
        <li><b>set[0-9]+IMap</b></li>
            Map that defines a mapping from raw to visible values like "0:mittig, 1:oberhalb, 2:unterhalb". This attribute atomatically creates a hint for FhemWEB so the user can choose one of the visible values and HTTPMOD sends the raw value to the device.
        <li><b>set[0-9]+Map</b></li>
            This is the old syntax for (get|reading)[0-9]*IMap. It should be replaced by (get|reading)[0-9]*IMap. The set command upgradeAttributes which becomes visible when the attribute enableControlSet is set to 1, can do this renaming automatically.
        <li><b>set[0-9]+Hint</b></li>
            Explicit hint for fhemWEB that will be returned when set ? is seen.
        <li><b>set[0-9]*NoArg</b></li>
            Defines that this set option doesn't require arguments. It allows sets like "on" or "off" without further values.
        <li><b>set[0-9]*ParseResponse</b></li>
            defines that the HTTP response to the set will be parsed as if it was the response to a get command.
        <li><b>set[0-9]*Local</b></li>
            defines that no HTTP request will be sent. Instead the value is directly set as a reading value.
        <br>

        <li><b>(get|set)[0-9]*HdrExpr</b></li>
            Defines a Perl expression to specify the HTTP Headers for this request. This overwrites any other header specification 
            and should be used carefully only if needed. The original headers are availabe as $old and separated by newlines. 
            Typically this feature is not needed and it might go away in future versions of HTTPMOD. 
            Please use the "replacement" attributes if you want to pass additional variable data to a web service. 
        <li><b>(get|set)[0-9]*DatExpr</b></li>
            Defines a Perl expression to specify the HTTP Post data for this request. This overwrites any other post data specification 
            and should be used carefully only if needed. The original Data is availabe as $old. 
            Typically this feature is not needed and it might go away in future versions of HTTPMOD. 
            Please use the "replacement" attributes if you want to pass additional variable data to a web service. 
        <li><b>(get|set)[0-9]*URLExpr</b></li>
            Defines a Perl expression to specify the URL for this request. This overwrites any other URL specification 
            and should be used carefully only if needed. The original URL is availabe as $old. 
            Typically this feature is not needed and it might go away in future versions of HTTPMOD. 
            Please use the "replacement" attributes if you want to pass additional variable data to a web service.           
        <br>

        
        <li><b>set[0-9]*ReAuthRegex</b></li>
            Regex that will detect when a session has expired during a set operation and a new login needs to be performed.
            It works like the global reAuthRegex but is used for set operations.
    
        <li><b>reAuthRegex</b></li>
            regular Expression to match an error page indicating that a session has expired and a new authentication for read access needs to be done. 
            This attribute only makes sense if you need a forms based authentication for reading data and if you specify a multi step login procedure based on the sid.. attributes.<br>
            This attribute is used for all requests. For set operations you can however specify individual reAuthRegexes with the set[0-9]*ReAuthRegex attributes.
        <li><b>reAuthAlways</b></li>
            if set to 1 will force authentication requests defined in the sid-attributes to be sent before each getupdate, get or set.
        <br><br>
        <li><b>sid[0-9]*URL</b></li>
            different URLs or one common URL to be used for each step of an optional login procedure. 
        <li><b>sid[0-9]*IdRegex</b></li>
            different Regexes per login procedure step or one common Regex for all steps to extract the session ID from the HTTP response
        <li><b>sid[0-9]*Data.*</b></li>
            data part for each step to be sent as POST data to the corresponding URL
        <li><b>sid[0-9]*Header.*</b></li>
            HTTP Headers to be sent to the URL for the corresponding step
        <li><b>sid[0-9]*IgnoreRedirects</b></li>
            tell HttpUtils to not follow redirects for this authentication request
        <li><b>clearSIdBeforeAuth</b></li>
            will set the session id to "" before doing the authentication steps
        <li><b>authRetries</b></li>
            number of retries for authentication procedure - defaults to 1
        <br>

        <li><b>replacement[0-9]*Regex</b></li>
            Defines a replacement to be applied to an HTTP request header, data or URL before it is sent. This allows any part of the request to be modified based on a reading, an internal or an expression.
            The regex defines which part of a header, data or URL should be replaced. The replacement is defined with the following attributes:
        <li><b>replacement[0-9]*Mode</b></li>
            Defines how the replacement should be done and what replacementValue means. Valid options are text, reading, internal and expression.
        <li><b>replacement[0-9]*Value</b></li>
            Defines the replacement. If the corresponding replacementMode is <code>text</code>, then value is a static text that is used as the replacement.<br>
            If replacementMode is <code>reading</code> then Value can be the name of a reading of this device or it can be a reading of a different device referred to by devicename:reading.<br>
            If replacementMode is <code>internal</code> the Value can be the name of an internal of this device or it can be an internal of a different device referred to by devicename:internal.<br>
            If replacementMode is <code>expression</code> the the Value is treated as a Perl expression that computes the replacement value. The expression can use $1, $2 and so on to refer to capture groups of the corresponding regex that is matched against the original URL, header or post data.<br>
            If replacementMode is <code>key</code> then the module will use a value from a key / value pair that is stored in an obfuscated form in the file system with the set storeKeyValue command. This might be useful for storing passwords.

        <li><b>[gs]et[0-9]*Replacement[0-9]*Value</b></li>
            This attribute can be used to override the replacement value for a specific get or set.
        <br>

        <li><b>get|reading[0-9]*MaxAge</b></li>
            Defines how long a reading is valid before it is automatically overwritten with a replacement when the read function is called the next time.
        <li><b>get|reading[0-9]*MaxAgeReplacement</b></li>
            specifies the replacement for MaxAge - either as a static text, the name of a reading / internal or as a perl expression.<br>
            If MaxAgeReplacementMode is <code>reading</code> then the value of MaxAgeReplacement can be the name of a reading of this device or it can be a reading of a different device referred to by devicename:reading.<br>
            If MaxAgeReplacementMode is <code>internal</code> the value of MaxAgeReplacement can be the name of an internal of this device or it can be an internal of a different device referred to by devicename:internal.
            
        <li><b>get|reading[0-9]*MaxAgeReplacementMode</b></li>
            specifies how the replacement is interpreted: can be text, reading, internal, expression and delete.
        <br>

        <li><b>get|reading[0-9]*DeleteIfUnmatched</b></li>
            If set to 1 this attribute causes certain readings to be deleted when the parsing of the website does not match the specified reading. 
            Internally HTTPMOD remembers which kind of operation created a reading (update, Get01, Get02 and so on). 
            Specified readings will only be deleted if the same operation does not parse this reading again. 
            This is especially useful for parsing that creates several matches / readings and this number of matches can vary from request to request. 
            For example if reading01Regex creates 4 readings in one update cycle and in the next cycle it only matches two times then the readings containing the 
            remaining values from the last round will be deleted.<br>
            Please note that this mechanism will not work in all cases after a restart. Especially when a get definition does not contain its own parsing definition 
            but ExtractAllJSON or relies on HTTPMOD to use all defined reading.* attributes to parse the responsee to a get command, 
            old readings might not be deleted after a restart of fhem.
        <li><b>get|reading[0-9]*DeleteOnError</b></li>
            If set to 1 this attribute causes certain readings to be deleted when the website can not be reached and the HTTP request returns an error. Internally HTTPMOD remembers which kind of operation created a reading (update, Get01, Get02 and so on). Specified readings will only be deleted if the same operation returns an error. <br>
            The same restrictions as for DeleteIfUnmatched apply regarding a fhem restart.
        <br>        

        <li><b>httpVersion</b></li>
            defines the HTTP-Version to be sent to the server. This defaults to 1.0.
        <li><b>sslVersion</b></li>
            defines the SSL Version for the negotiation with the server. The attribute is evaluated by HttpUtils. If it is not specified, HttpUtils assumes SSLv23:!SSLv3:!SSLv2
        <li><b>sslArgs</b></li>
            defines a list that is converted to a key / value hash and gets passed to HttpUtils. To avoid certificate validation for broken servers you can for example specify 
            <code>attr myDevice sslArgs SSL_verify_mode,SSL_VERIFY_NONE</code>
        <li><b>noShutdown</b></li>
            pass the noshutdown flag to HTTPUtils for webservers that need it (some embedded webservers only deliver empty pages otherwise)
            
        <li><b>disable</b></li>
            stop communication with the Web_Server with HTTP requests while this attribute is set to 1
        <li><b>enableControlSet</b></li>
            enables the built in set commands like interval, stop, start, reread, upgradeAttributes, storeKeyValue.
            <br>
            starting with featurelevel > 5.9 HTTPMOD uses this feature by default. So you don't need to set it to 1, but you can disable it by setting it to 0.
            
        <li><b>enableCookies</b></li>
            enables the built cookie handling if set to 1. With cookie handling each HTTPMOD device will remember cookies that the server sets and send them back to the server in the following requests. 
            This simplifies session magamenet in cases where the server uses a session ID in a cookie. In such cases enabling Cookies should be sufficient and no sidRegex and no manual definition of a Cookie Header should be necessary.
            <br>
            starting with featurelevel > 5.9 HTTPMOD uses this feature by default. So you don't need to set it to 1, but you can disable it by setting it to 0.

        <li><b>showMatched</b></li>
            if set to 1 then HTTPMOD will create a reading with the name MATCHED_READINGS 
            that contains the names of all readings that could be matched in the last request.
        <li><b>showError</b></li>
            if set to 1 then HTTPMOD will create a reading and event with the Name LAST_ERROR 
            that contains the error message of the last error returned from HttpUtils. 
        <li><b>removeBuf</b></li>
            This attribute has been removed. If set to 1 then HTTPMOD used to removes the internal named buf when a HTTP-response had been
            received. $hash->{buf} is used internally be Fhem httpUtils and used to be visible. This behavior of httpUtils has changed so removeBuf has become obsolete.
        <li><b>showBody</b></li>
            if set to 1 then the body of http responses will be visible as internal httpbody.
            
        <li><b>timeout</b></li>
            time in seconds to wait for an answer. Default value is 2
        <li><b>queueDelay</b></li>
            HTTP Requests will be sent from a queue in order to avoid blocking when several Requests have to be sent in sequence. This attribute defines the delay between calls to the function that handles the send queue. It defaults to one second.
        <li><b>queueMax</b></li>
            Defines the maximum size of the send queue. If it is reached then further HTTP Requests will be dropped and not be added to the queue
        <li><b>minSendDelay</b></li>
            Defines the minimum time between two HTTP Requests.
        <br>
        <li><b>alignTime</b></li>
            Aligns each periodic read request for the defined interval to this base time. This is typcally something like 00:00 (see the Fhem at command)
        <br>

        <li><b>enableXPath</b></li>
            This attribute should no longer be used. Please specify an HTTP XPath in the dedicated attributes shown above.
        <li><b>enableXPath-Strict</b></li>
            This attribute should no longer be used. Please specify an XML XPath in the dedicated attributes shown above.
            
        <li><b>enforceGoodReadingNames</b></li>
            makes sure that reading names are valid and especially that extractAllJSON creates valid reading names.
            <br>
            starting with featurelevel > 5.9 HTTPMOD uses this feature by default. So you don't need to set it to 1, but you can disable it by setting it to 0.
            
        <li><b>handleRedirects</b></li>
            enables redirect handling inside HTTPMOD. This makes complex session establishment where the HTTP responses contain a series of redirects much easier. If enableCookies is set as well, cookies will be tracked during the redirects.
            <br>
            starting with featurelevel > 5.9 HTTPMOD uses this feature by default. So you don't need to set it to 1, but you can disable it by setting it to 0.
            
        <li><b>useSetExtensions</b></li>
            enables or disables the integration of setExtensions in HTTPMOD. By default this is enabled, but setting this attribute to 0 will disable setExtensions in HTTPMOD.
            
        <li><b>dontRequeueAfterAuth</b></li>
            prevents the original HTTP request to be added to the send queue again after the authentication steps. This might be necessary if the authentication steps will automatically get redirects to the URL originally requested. This option will likely need to be combined with sidXXParseResponse.
            
        <li><b>parseFunction1</b> and <b>parseFunction2</b></li>
            These functions allow an experienced Perl / Fhem developer to plug in his own parsing functions.<br>
            Please look into the module source to see how it works and don't use them if you are not sure what you are doing.
        <li><b>preProcessRegex</b></li>
            can be used to fix a broken HTTP response before parsing. The regex should be a replacement regex like s/match/replacement/g and will be applied to the buffer.
            
        <li><b>errorLogLevel</b></li>
            allows to modify the loglevel used to log errors from HttpUtils. by default level 3 is used.
        <li><b>errorLogLevelRegex</b></li>
            restricts the effect of errorLogLevel to such error messages that match this regex.

        <li><b>Remarks regarding the automatically created userattr entries</b></li>
            Fhemweb allows attributes to be edited by clicking on them. However this does not work for attributes that match to a wildcard attribute. To circumvent this restriction HTTPMOD automatically adds an entry for each instance of a defined wildcard attribute to the device userattr list. E.g. if you define a reading[0-9]Name attribute as reading01Name, HTTPMOD will add reading01Name to the device userattr list. These entries only have the purpose of making editing in Fhemweb easier.
    </ul>
    <br>
    <b>Author's notes</b><br><br>
    <ul>
        <li>If you don't know which URLs, headers or POST data your web GUI uses, you might try a local proxy like <a href=http://portswigger.net/burp/>BurpSuite</a> to track requests and responses </li>
    </ul>
</ul>

=end html
=cut
