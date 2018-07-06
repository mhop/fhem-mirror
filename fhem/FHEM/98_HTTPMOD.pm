#########################################################################
# $Id$
# fhem Modul für Geräte mit Web-Oberfläche / Webservices
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
#   2015-09-14  implemented parseFunction1 and 2, modified to not return a value if successful
#   2015-10-10  major restructuring, new xpath, xpath-strict and json parsing implementation
#   2015-11-08  fixed bug which caused a recursion when reading from file:// urls
#               fixed xpath handling (so far ...)
#   2015-11-19  MaxAge, aligned type and context for some functions
#   2015-11-23  fixed map handling to allow spaces in names and convert them for fhemweb 
#   2015-12-03  Max age finalized
#   2015-12-05  fixed error when loading Libs inside eval{} (should have been eval"") and added documentation for showError
#   2015-12-07  fixed syntax to work with Perl older than 5.14 in a few places
#               added RecombineExpr and a few performance optimisations
#   2015-12-10  fixed a bug in JSON parsing and corrected extractAllJSON to start with lower case 
#   2015-12-22  fixed missing error handling for JSON parser call 
#   2015-12-28  added SetParseResponse
#   2016-01-01  fixed bug where httpheader was not handled, added cookie handling
#   2016-01-09  fixed a bug which caused only one replacement per string to happen
#   2016-01-10  fixed a bug where only the first word of text passed to set is used,
#               added sid extraction and reAuth detection with JSON and XPath 
#   2016-01-11  modified automatic $val replacement for set values to pass the value through the request queue and 
#               do the actual replacement just before sending just like user definable replacements
#               so they can be done by replacement attributes with other placeholders instead
#   2016-01-16  added TextArg to get and optimized creating the hint list for get / set ?
#   2016-01-21  added documentation
#               added RegOpt (still needs more testing), Replacement mode delete
#   2016-01-23  changed MATCHED_READINGS to contain automatically created subreadings (-num)
#               added AutoNumLen for automatic sub-reading names (multiple matches) 
#               so the number has leading zeros and a fixed length
#               added new attribute upgrading mechanism (e.g. for sidIDRegex to sidIdRegex)
#   2016-01-25  modified the way attributes are added to userattr - now includes :hints for fhemweb
#               and old entries are replaced
#   2016-02-02  added more checks to JsonFlatter (if defined ...), fixed auth to be added in the front of the queue, 
#               added clearSIdBeforeAuth, authRetries
#   2016-02-04  added a feature to name a reading "unnamed-XX" if Name attribute is missing 
#               instead of ignoring everything related
#   2016-02-05  fixed a warning caused by missing initialisation of .setList internal
#   2016-02-07  allowed more regular expression modifiers in RegOpt, added IMap / OMap / IExpr / OExpr
#   2016-02-13  enable sslVersion attribute für HttpUtils and httpVersion
#   2016-02-14  add sslArgs attribute - e.g. as attr myDevice sslArgs SSL_verify_mode,SSL_VERIFY_NONE
#               Log old attrs and offer set upgradeAttributes
#   2016-02-15  added replacement type key and set storeKeyValue
#   2016-02-20  set $XML::XPath::SafeMode = 1 to avoid memory leak in XML parser lib
#   2016-03-25  started fixing array handling in json flatter
#   2016-03-28  during extractAllJSON reading definitions will not be used to format readings. 
#               Instead after the ExtractAllJSION loop 
#               individual readings will be extracted (checkAll) and recombined if necessary
#               Fixed cookie handling to add cookies in HandleSendQueue instead of PrepareRequest
#   2016-04-08  fixed usage of "keys" on reference in 1555 and 1557
#   2016-04-10  added readings UNMATCHED_READINGS and LAST_REQUEST if showMatched is set.
#               added AlwaysNum to force names anding with a number even if just one value is found
#   2016-04-16  fixed typos in logging
#   2016-04-24  Implemented DeleteOnError and DeleteIfUnmatched, 
#               fixed an error in the cookie handling
#   2016-05-08  Implemented alignTime, more MaxAgeReplacementMode varieties
#               fixed bug in Timer handling if Main URL was not specified in define
#   2016-05-20  3.2.2 UpdateRequestHash for DeleteIf / DeleteOn / MaxAge
#               foreach / grep usage optimized in Replace, UpdateHintList, UpdateRequesthash, UpdateReadingList, GetUpdate
#               Poll handling fixed (poll = 0) in GetUpdate
#               Optimized keylist in json handling in ExtractReading
#               Regexes optimized (^$)
#               Module Version internal
#               Fixed attr regex for poll, pollDelay, replacements, 
#               typos in Auth, UpdateHintList after define,
#               details im ExtractReading for requestReading hash
#               LAST_REQUEST bei Error in Read
#               fixed call to CheckAuth - pass buffer instead of body
#               restructured _Read
#               modified CheckAuth to do auth also for json / xpath matches
#               Map, Format, Expr as well as Encode and Decode attributes will
#                   be applied to ExtractAllJSON as well (e.g. getXXEncode or readingEncode)
#   2016-06-02  switched from "each" to foreach in JsonFlatter when used on an array to support older Perl
#               fixed a warning in Getupdate when calculating with pollDelay
#               fixed double LAST_REQUEST
#               allow control_sets if disabled
#               fixed a bug in updateRequestHash (wrong request setting)
#   2016-06-05  added code to recover if HttpUtils does not call back _read in timeout
#   2016-06-28  added remark about dnsServer to documentation
#   2016-07-03  fixed typos
#   2016-07-18  make $now and $timeDiff available to OExpr
#   2016-08-31  only fixed typos
#   2016-09-20  fixed bugs where extractAllJSON filled requestReadings hash with wrong key and 
#               requestReadings structure was filled with wrong data in updateRequestHash
#               optimized deletion of readings with their metadata, check $buffer before jsonflatter
#   2016-10-02  changed logging in _Read: shorter log on level 3 if $err and details only on level 4
#   2016-10-06  little modification to help debugging a strange syntax error
#   2017-02-08  fix bug in xpath handling reported in https://forum.fhem.de/index.php/topic,45176.315.html
#               catch warnings in evals - to be finished (drop subroutine and add inline)
#   2017-03-16  Log line removed in JsonFlatter (creates warning if $value is not defined and it is not needed anyways)
#   2017-03-23  new attribute removeBuf
#   2017-05-07  fixed typo in documentation
#   2017-05-08  optimized warning signal handling
#   2017-05-09  fixed character encoding of source file for documentation
#               fixed a bug where updateRequestHash was not called after restart and for MaxAge
#               fixed a warning when alwaysNum without NumLen is specified
#   2017-09-06  new attribute reAuthAlways to do the defined authentication steps 
#               before each get / set / getupdate regardless of any reAuthRegex setting or similar.
#   2018-01-18  added preProcessRegex e.g. to fix broken JSON data in a response
#   2018-02-10  modify handling of attribute removeBuf since httpUtils doesn't expose its buffer anymore, 
#               Instead new attribute showBody to explicitely show a formatted version of the http response body (header is already shown)
#   2018-05-01  new attribute enforceGoodReadingNames
#   2018-05-05  experimental support for named groups in regexes (won't support individual MaxAge / deleteIf attributes)
#               see ExtractReading function
#   2018-07-01  own redirect handling, support for cookies with different paths / options
#               new attributes dontRequeueAfterAuth, handleRedirects
#
#

#
#   Todo:       
#               get after set um readings zu aktualisieren
#               definierbarer prefix oder Suffix für Readingsnamen wenn sie von unterschiedlichen gets über readingXY erzeugt werden
#
#				set clearCookies
#				
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
#               extend httpmod to support simple tcp connections over devio instead of HttpUtils?
#
#
# Merkliste fürs nächste Fhem Release
#   - enforceGoodReadingNames 1 als Default
#
#
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
sub HTTPMOD_AddToQueue($$$$$;$$$$);
sub HTTPMOD_JsonFlatter($$;$);
sub HTTPMOD_ExtractReading($$$$$);

my $HTTPMOD_Version = '3.5.1 - 5.7.2018';

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
      "(reading|get|set)[0-9]+(-[0-9]+)?Name " . 
      
      "(reading|get|set)[0-9]*(-[0-9]+)?Expr " .
      "(reading|get|set)[0-9]*(-[0-9]+)?Map " . 
      "(reading|get|set)[0-9]*(-[0-9]+)?OExpr " .
      "(reading|get|set)[0-9]*(-[0-9]+)?OMap " .
      "(get|set)[0-9]*(-[0-9]+)?IExpr " .
      "(get|set)[0-9]*(-[0-9]+)?IMap " . 

      "(reading|get|set)[0-9]*(-[0-9]+)?Format " . 
      "(reading|get|set)[0-9]*(-[0-9]+)?Decode " . 
      "(reading|get|set)[0-9]*(-[0-9]+)?Encode " . 

      "(reading|get)[0-9]*(-[0-9]+)?MaxAge " . 
      "(reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacementMode:text,reading,internal,expression,delete " . 
      "(reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacement " . 
      
      "(reading|get|set)[0-9]+Regex " .
      "(reading|get|set)[0-9]+RegOpt " .        # see http://perldoc.perl.org/perlre.html#Modifiers
      "(reading|get|set)[0-9]+XPath " . 
      "(reading|get|set)[0-9]+XPath-Strict " . 
      "(reading|get|set)[0-9]+JSON " . 
      "(reading|get|set)[0-9]*RecombineExpr " .
      "(reading|get|set)[0-9]*AutoNumLen " .
      "(reading|get|set)[0-9]*AlwaysNum " .
      "(reading|get|set)[0-9]*DeleteIfUnmatched " .
      "(reading|get|set)[0-9]*DeleteOnError " .
      "extractAllJSON " .
      
      "readingsName.* " .               # old 
      "readingsRegex.* " .              # old 
      "readingsExpr.* " .               # old 
     
      "requestHeader.* " .  
      "requestData.* " .
      "noShutdown:0,1 " .    
      "httpVersion " .
      "sslVersion " .
      "sslArgs " .
      "timeout " .
      "queueDelay " .
      "queueMax " .
      "alignTime " .
      "minSendDelay " .

      "showMatched:0,1 " .
      "showError:0,1 " .
      "showBody " .                     # expose the http response body as internal
      #"removeBuf:0,1 " .               # httpUtils doesn't expose buf anymore
      "preProcessRegex " .
      
      "parseFunction1 " .
      "parseFunction2 " .

      "[gs]et[0-9]*URL " .
      "[gs]et[0-9]*Data.* " .
      "[gs]et[0-9]*NoData.* " .         # make sure it is an HTTP GET without data - even if a more generic data is defined
      "[gs]et[0-9]*Header.* " .
      "[gs]et[0-9]*CheckAllReadings:0,1 " .
      "[gs]et[0-9]*ExtractAllJSON:0,1 " .
      
      "[gs]et[0-9]*URLExpr " .          # old
      "[gs]et[0-9]*DatExpr " .          # old
      "[gs]et[0-9]*HdrExpr " .          # old

      "get[0-9]*Poll:0,1 " . 
      "get[0-9]*PollDelay " .
      
      "get[0-9]*PullToFile " .
      "get[0-9]*PullIterate " .

      "set[0-9]+Min " .                 # todo: min, max und hint auch für get, Schreibweise der Liste auf (get|set) vereinheitlichen
      "set[0-9]+Max " .
      "set[0-9]+Hint " .                # Direkte Fhem-spezifische Syntax für's GUI, z.B. "6,10,14" bzw. slider etc.
      "set[0-9]*NoArg:0,1 " .           # don't expect a value - for set on / off and similar. (default for get)
      "[gs]et[0-9]*TextArg:0,1 " .      # just pass on a raw text value without validation / further conversion
      "set[0-9]*ParseResponse:0,1 " .   # parse response to set as if it was a get
      
      "reAuthRegex " .
      "reAuthAlways:0,1 " .
      "reAuthJSON " .
      "reAuthXPath " .
      "reAuthXPath-Strict " .
      "[gs]et[0-9]*ReAuthRegex " .
      "[gs]et[0-9]*ReAuthJSON " .
      "[gs]et[0-9]*ReAuthXPath " .
      "[gs]et[0-9]*ReAuthXPath-Strict " .
      
      "idRegex " .
      "idJSON " .
      "idXPath " .
      "idXPath-Strict " .
      "(get|set|sid)[0-9]*IDRegex " .           # old
      "(get|set|sid)[0-9]*IdRegex " .
      "(get|set|sid)[0-9]*IdJSON " .
      "(get|set|sid)[0-9]*IdXPath " .
      "(get|set|sid)[0-9]*IdXPath-Strict " .
        
      "sid[0-9]*URL " .
      "sid[0-9]*Header.* " .
      "sid[0-9]*Data.* " .
      "sid[0-9]*IgnoreRedirects:0,1 " .      
      "sid[0-9]*ParseResponse:0,1 " .           # parse response as if it was a get
      "clearSIdBeforeAuth:0,1 " .
      "authRetries " .
      
      "replacement[0-9]+Regex " .
      "replacement[0-9]+Mode:reading,internal,text,expression,key " .   # defaults to text
      "replacement[0-9]+Value " .                                   # device:reading, device:internal, text, replacement expression
      "[gs]et[0-9]*Replacement[0-9]+Value " .                       # can overwrite a global replacement value - todo: auch für auth?
      
      "do_not_notify:1,0 " . 
      "disable:0,1 " .
      "enableControlSet:0,1 " .
      "enableCookies:0,1 " .
      "handleRedirects:0,1 " .                  # own redirect handling outside HttpUtils
      "enableXPath:0,1 " .                      # old 
      "enableXPath-Strict:0,1 " .               # old
      "enforceGoodReadingNames " .
      "dontRequeueAfterAuth " .
      $readingFnAttributes;  
}



#
# 
#########################################################################
sub HTTPMOD_SetTimer($;$)
{
    my ($hash, $start) = @_;
    my $nextTrigger;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    $start   = 0 if (!$start);

    if ($hash->{Interval}) {
        if ($hash->{TimeAlign}) {
            my $count = int(($now - $hash->{TimeAlign} + $start) / $hash->{Interval});
            my $curCycle = $hash->{TimeAlign} + $count * $hash->{Interval};
            $nextTrigger = $curCycle + $hash->{Interval};
        } else {
            $nextTrigger = $now + ($start ? $start : $hash->{Interval});
        }
        
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        RemoveInternalTimer("update:$name");
        InternalTimer($nextTrigger, "HTTPMOD_GetUpdate", "update:$name", 0);
        Log3 $name, 4, "$name: update timer modified: will call GetUpdate in " . 
            sprintf ("%.1f", $nextTrigger - $now) . " seconds at $hash->{TRIGGERTIME_FMT}";
    } else {
       $hash->{TRIGGERTIME}     = 0;
       $hash->{TRIGGERTIME_FMT} = "";
    }
}


#
# Define command
# init internal values,
# set internal timer get Updates
#########################################################################
sub HTTPMOD_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split( "[ \t]+", $def );

    return "wrong syntax: define <name> HTTPMOD URL interval"
      if ( @a < 3 );
    my $name    = $a[0];

    if ($a[2] eq "none") {
        Log3 $name, 3, "$name: URL is none, periodic updates will be limited to explicit GetXXPoll attribues (if defined)";
        $hash->{MainURL}    = "";
    } else {
        $hash->{MainURL}    = $a[2];
    }

    if(int(@a) > 3) { 
        # interval specified
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
        # default if no interval specified
        $hash->{Interval} = 300;
    }

    Log3 $name, 3, "$name: Defined " .
        ($hash->{MainURL}  ? "with URL $hash->{MainURL}" : "without URL") .
        ($hash->{Interval} ? " and interval $hash->{Interval}" : "");

    HTTPMOD_SetTimer($hash, 2);     # first Update in 2 seconds or aligned
    
    $hash->{ModuleVersion} = $HTTPMOD_Version;
    $hash->{".getList"}    = "";
    $hash->{".setList"}    = "";
    $hash->{".updateHintList"}    = 1;
    $hash->{".updateReadingList"} = 1;
    $hash->{".updateRequestHash"} = 1;

    return undef;
}


#
# undefine command when device is deleted
#########################################################################
sub HTTPMOD_Undef($$)
{                     
    my ($hash, $arg) = @_;       
    my $name = $hash->{NAME};
    RemoveInternalTimer ("timeout:$name");
    RemoveInternalTimer ("queue:$name"); 
    RemoveInternalTimer ("update:$name"); 
    return undef;                  
}    


#########################################################################
sub HTTPMOD_LogOldAttr($$;$)
{                     
    my ($hash, $old, $new) = @_;       
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: the attribute $old should no longer be used." . ($new ? " Please use $new instead" : "");
    Log3 $name, 3, "$name: For most old attributes you can specify enableControlSet and then set device upgradeAttributes to automatically modify the configuration";
}


#
# Attr command 
#########################################################################
sub HTTPMOD_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash    = $defs{$name};
    my $modHash = $modules{$hash->{TYPE}};
    my ($sid, $old);                # might be needed inside a URLExpr
    
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are attribute name and attribute value

    # simple attributes like requestHeader and requestData need no special treatment here
    # readingsExpr, readingsRegex.* or reAuthRegex need validation though.
    # if validation fails, return something so CommandAttr in fhem.pl doesn't assign a value to $attr
    
    if ($cmd eq "set") {        
        if ($aName =~ /Regex/) {    # catch all Regex like attributes
            my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
            $SIG{__WARN__} = sub { Log3 $name, 3, "$name: set attr $aName $aVal created warning: @_"; };
            eval {qr/$aVal/};
            $SIG{__WARN__} = $oldSig;
            if ($@) {
                Log3 $name, 3, "$name: Attr with invalid regex in attr $name $aName $aVal: $@";
                return "Invalid Regex $aVal";
            }
            if ($aName =~ /([gs]et[0-9]*)?[Rr]eplacement[0-9]*Regex$/) {
                $hash->{ReplacementEnabled} = 1;
            }

            # conversions for legacy things
            if ($aName =~ /(.+)IDRegex$/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}IdRegex");
            }
            if ($aName =~ /readingsRegex.*/) {
                HTTPMOD_LogOldAttr($hash, $aName, "reading01Regex syntax");
            }
        } elsif ($aName =~ /readingsName.*/) {    
                HTTPMOD_LogOldAttr($hash, $aName, "reading01Name syntax");
        } elsif ($aName =~ /RegOpt$/) {    
            if ($aVal !~ /^[msxdualsig]*$/) {
                Log3 $name, 3, "$name: illegal RegOpt in attr $name $aName $aVal";
                return "$name: illegal RegOpt in attr $name $aName $aVal";
            }
        } elsif ($aName =~ /Expr/) { # validate all Expressions
            my $val = 0; my $old = 0;
            my $timeDiff = 0;               # to be available in Exprs
            my @matchlist = ();
            no warnings qw(uninitialized);
            my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
            $SIG{__WARN__} = sub { Log3 $name, 3, "$name: set attr $aName $aVal created warning: @_"; };
            eval $aVal;
            $SIG{__WARN__} = $oldSig;
            if ($@) {
                Log3 $name, 3, "$name: Attr with invalid Expression in attr $name $aName $aVal: $@";
                return "Invalid Expression $aVal";
            }
            if ($aName =~ /readingsExpr.*/) {
                HTTPMOD_LogOldAttr($hash, $aName, "reading01Expr syntax");
            } elsif ($aName =~ /^(get[0-9]*)Expr/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}OExpr");
            } elsif ($aName =~ /^(reading[0-9]*)Expr/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}OExpr");
            } elsif ($aName =~ /^(set[0-9]*)Expr/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}IExpr");
            }

        } elsif ($aName =~ /Map$/) {
            if ($aName =~ /^(get[0-9]*)Map/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}OMap");
            } elsif ($aName =~ /^(reading[0-9]*)Map/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}OMap");
            } elsif ($aName =~ /^(set[0-9]*)Map/) {
                HTTPMOD_LogOldAttr($hash, $aName, "${1}IMap");
            }           
            
        } elsif ($aName =~ /replacement[0-9]*Mode/) {
            if ($aVal !~ /^(reading|internal|text|expression|key)$/) {
                Log3 $name, 3, "$name: illegal mode in attr $name $aName $aVal";
                return "$name: illegal mode in attr $name $aName $aVal";
            }
            
        } elsif ($aName =~ /([gs]et[0-9]*)?[Rr]eplacement([0-9]*)Value/) {
            Log3 $name, 5, "$name: validating attr $name $aName $aVal";
            if (AttrVal($name, "replacement${2}Mode", "text") eq "expression") {
                no warnings qw(uninitialized);
                my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
                $SIG{__WARN__} = sub { Log3 $name, 3, "$name: set attr $aName $aVal created warning: @_"; };
                eval $aVal;
                $SIG{__WARN__} = $oldSig;
                if ($@) {
                    Log3 $name, 3, "$name: Attr with invalid Expression (mode is expression) in attr $name $aName $aVal: $@";
                    return "Attr with invalid Expression (mode is expression) in attr $name $aName $aVal: $@";
                }
            }
            
        } elsif ($aName =~ /(get|reading)[0-9]*JSON$/ 
                || $aName =~ /[Ee]xtractAllJSON$/ 
                || $aName =~ /[Rr]eAuthJSON$/
                || $aName =~ /[Ii]dJSON$/) {
            eval "use JSON";
            if($@) {
                return "Please install JSON Library to use JSON (apt-get install libjson-perl) - error was $@";
            }
            $hash->{JSONEnabled} = 1;
        } elsif ($aName eq "enableCookies") {
            if ($aVal eq "0") {
                delete $hash->{HTTPCookieHash};
            }
        } elsif ($aName eq "enableXPath" 
                || $aName =~ /(get|reading)[0-9]+XPath$/
                || $aName =~ /[Rr]eAuthXPath$/
                || $aName =~ /[Ii]dXPath$/) {
            eval "use HTML::TreeBuilder::XPath";
            if($@) {
                return "Please install HTML::TreeBuilder::XPath to use the xpath-Option (apt-get install libxml-TreeBuilder-perl libhtml-treebuilder-xpath-perl) - error was $@";
            }
            $hash->{XPathEnabled} = ($aVal ? 1 : 0);
            
        } elsif ($aName eq "enableXPath-Strict" 
                || $aName =~ /(get|reading)[0-9]+XPath-Strict$/
                || $aName =~ /[Rr]eAuthXPath-Strict$/
                || $aName =~ /[Ii]dXPath-Strict$/) {
            eval "use XML::XPath;use XML::XPath::XMLParser";
            if($@) {
                return "Please install XML::XPath and XML::XPath::XMLParser to use the xpath-strict-Option (apt-get install libxml-parser-perl libxml-xpath-perl) - error was $@";
            }
            $XML::XPath::SafeMode = 1;
            $hash->{XPathStrictEnabled} = ($aVal ? 1 : 0);
            
        } elsif ($aName =~ /^(reading|get)[0-9]*(-[0-9]+)?MaxAge$/) {
            if ($aVal !~ '([0-9]+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";    
            }
            $hash->{MaxAgeEnabled} = 1;

        } elsif ($aName =~ /^(reading|get)[0-9]*(-[0-9]+)?MaxAgeReplacementMode$/) {
            if ($aVal !~ /^(text|reading|internal|expression|delete)$/) {
                Log3 $name, 3, "$name: illegal mode in attr $name $aName $aVal";
                return "$name: illegal mode in attr $name $aName $aVal, choose on of text, expression";
            }

        } elsif ($aName =~ /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteOnError$/) {
            if ($aVal !~ '([0-9]+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";    
            }
            $hash->{DeleteOnError} = ($aVal ? 1 : 0);

        } elsif ($aName =~ /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteIfUnmatched$/) {
            if ($aVal !~ '([0-9]+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";    
            }
            $hash->{DeleteIfUnmatched} = ($aVal ? 1 : 0);
            
        } elsif ($aName eq 'alignTime') {
            my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($aVal);
            return "Invalid Format $aVal in $aName : $alErr" if ($alErr);
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
            $hash->{TimeAlign}    = fhemTimeLocal($alSec, $alMin, $alHr, $mday, $mon, $year);
            $hash->{TimeAlignFmt} = FmtDateTime($hash->{TimeAlign});
            HTTPMOD_SetTimer($hash, 2);     # change timer for alignment but at least 2 secs from now 

        } elsif ($aName =~ /^(reading|get)([0-9]+)(-[0-9]+)?Name$/) {
            # todo: validate good reading name if enforceGoodReadingNames is set to 1 / by default in next fhem version
            $hash->{".updateRequestHash"} = 1;
        }
        
        # handle wild card attributes -> Add to userattr to allow modification in fhemweb
        #Log3 $name, 3, "$name: attribute $aName checking ";
        if (" $modHash->{AttrList} " !~ m/ ${aName}[ :;]/) {
            # nicht direkt in der Liste -> evt. wildcard attr in AttrList
            foreach my $la (split " ", $modHash->{AttrList}) {
                $la =~ /([^:;]+)(:?.*)/;
                my $vgl = $1;           # attribute name in list - probably a regex
                my $opt = $2;           # attribute hint in list
                if ($aName =~ $vgl) {   # yes - the name in the list now matches as regex
                    # $aName ist eine Ausprägung eines wildcard attrs
                    addToDevAttrList($name, "$aName" . $opt);    # create userattr with hint to allow changing by click in fhemweb
                    if ($opt) {
                        # remove old entries without hint
                        my $ualist = $attr{$name}{userattr};
                        $ualist = "" if(!$ualist);  
                        my %uahash;
                        foreach my $a (split(" ", $ualist)) {
                            if ($a !~ /^${aName}$/) {    # entry in userattr list is attribute without hint
                                $uahash{$a} = 1;
                            } else {
                                Log3 $name, 3, "$name: added hint $opt to attr $a in userattr list";
                            }
                        }
                        $attr{$name}{userattr} = join(" ", sort keys %uahash);
                    }
                }
            }
        } else {
            # exakt in Liste enthalten -> sicherstellen, dass keine +* etc. drin sind.
            if ($aName =~ /\|\*\+\[/) {
                Log3 $name, 3, "$name: Atribute $aName is not valid. It still contains wildcard symbols";
                return "$name: Atribute $aName is not valid. It still contains wildcard symbols";
            }
        }
            
    # Deletion of Attributes
    } elsif ($cmd eq "del") {    
        #Log3 $name, 5, "$name: del attribute $aName";
        if ($aName =~ /(reading|get)[0-9]*JSON$/ 
                || $aName =~ /[Ee]xtractAllJSON$/
                || $aName =~ /[Rr]eAuthJSON$/
                || $aName =~ /[Ii]dJSON$/) {
            if (!(grep !/$aName/, grep (/((reading|get)[0-9]*JSON$)|[Ee]xtractAllJSON$|[Rr]eAuthJSON$|[Ii]dJSON$/, 
                    keys %{$attr{$name}}))) {
                delete $hash->{JSONEnabled};
            }
        } elsif ($aName eq "enableXPath" 
                || $aName =~ /(get|reading)[0-9]+XPath$/
                || $aName =~ /[Rr]eAuthXPath$/
                || $aName =~ /[Ii]dXPath$/) {
            if (!(grep !/$aName/, grep (/(get|reading)[0-9]+XPath$|enableXPath|[Rr]eAuthXPath$|[Ii]dXPath$/, 
                    keys %{$attr{$name}}))) {
                delete $hash->{XPathEnabled};
            }
        } elsif ($aName eq "enableXPath-Strict" 
                || $aName =~ /(get|reading)[0-9]+XPath-Strict$/
                || $aName =~ /[Rr]eAuthXPath-Strict$/
                || $aName =~ /[Ii]dXPath-Strict$/) {
                
            if (!(grep !/$aName/, grep (/(get|reading)[0-9]+XPath-Strict$|enableXPath-Strict|[Rr]eAuthXPath-Strict$|[Ii]dXPath-Strict$/, 
                    keys %{$attr{$name}}))) {
                delete $hash->{XPathStrictEnabled};
            }
        } elsif ($aName eq "enableCookies") {
            delete $hash->{HTTPCookieHash};

        } elsif ($aName =~ /(reading|get)[0-9]*(-[0-9]+)?MaxAge$/) {
            if (!(grep !/$aName/, grep (/(reading|get)[0-9]*(-[0-9]+)?MaxAge$/, keys %{$attr{$name}}))) {
                delete $hash->{MaxAgeEnabled};
            }
        } elsif ($aName =~ /([gs]et[0-9]*)?[Rr]eplacement[0-9]*Regex/) {
            if (!(grep !/$aName/, grep (/([gs]et[0-9]*)?[Rr]eplacement[0-9]*Regex/, keys %{$attr{$name}}))) {
                delete $hash->{ReplacementEnabled};
            }

        } elsif ($aName =~ /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteOnError$/) {
            if (!(grep !/$aName/, grep (/^(reading|get|set)[0-9]*(-[0-9]+)?DeleteOnError$/, keys %{$attr{$name}}))) {
                delete $hash->{DeleteOnError};              
            }

        } elsif ($aName =~ /^(reading|get|set)[0-9]*(-[0-9]+)?DeleteIfUnmatched$/) {
            if (!(grep !/$aName/, grep (/^(reading|get|set)[0-9]*(-[0-9]+)?DeleteIfUnmatched$/, keys %{$attr{$name}}))) {
                delete $hash->{DeleteIfUnmatched};              
            }

        } elsif ($aName eq 'alignTime') {
            delete $hash->{TimeAlign};
            delete $hash->{TimeAlignFmt};
        }
    }
    if ($aName =~ /^[gs]et/ || $aName eq "enableControlSet") {
        $hash->{".updateHintList"} = 1;
    }
    if ($aName =~ /^(get|reading)/) {
        $hash->{".updateReadingList"} = 1;
    }  
    return undef;
}




# Upgrade attribute names from older versions
##############################################
sub HTTPMOD_UpgradeAttributes($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
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
        } elsif ($aName =~ /(.+)Regex$/) {
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
        } elsif ($aName eq "enableXPath" || $aName eq "enableXPath-Strict" ) {
            CommandDeleteAttr(undef, "$name $aName");
            Log3 $name, 3, "$name: removed attribute name $aName";
            
        } elsif ($aName =~ /(set[0-9]*)Expr$/) {
            my $new = $1 . "IExpr";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } elsif ($aName =~ /(get[0-9]*)Expr$/) {
            my $new = $1 . "OExpr";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } elsif ($aName =~ /(reading[0-9]*)Expr$/) {
            my $new = $1 . "OExpr";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";

        } elsif ($aName =~ /(set[0-9]*)Map$/) {
            my $new = $1 . "IMap";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } elsif ($aName =~ /(get[0-9]*)Map$/) {
            my $new = $1 . "OMap";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } elsif ($aName =~ /(reading[0-9]*)Map$/) {
            my $new = $1 . "OMap";
            my $val = $attr{$name}{$aName};
            CommandAttr(undef, "$name $new $val"); 
            CommandDeleteAttr(undef, "$name $aName");
            $dHash{$aName} = 1;
            Log3 $name, 3, "$name: upgraded attribute name $aName to new sytax $new";
        } elsif ($aName =~ /^readings(Name|Expr|Regex)(.*)$/) {
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
    
    my $ualist = $attr{$name}{userattr};
    $ualist = "" if(!$ualist);  
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
}


# get attribute based specification
# for format, map or similar
# with generic and absolute default (empty variable num part)
# if num is like 1-1 then check for 1 if 1-1 not found 
#############################################################
sub HTTPMOD_GetFAttr($$$$;$)
{
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


###################################################
# checks and stores obfuscated keys like passwords 
# based on / copied from FRITZBOX_storePassword
sub HTTPMOD_StoreKeyValue($$$)
{
    my ($hash, $kName, $value) = @_;
     
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;    
    my $enc   = "";
    
    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $value)
    {
        my $encode=chop($key);
        $enc.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = setKeyValue($index, $enc);
    return "error while saving the value - $err" if(defined($err));
    return undef;
} 
   
   
#####################################################
# reads obfuscated value 
sub HTTPMOD_ReadKeyValue($$)
{
   my ($hash, $kName) = @_;
   my $name = $hash->{NAME};

   my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
   my $key = getUniqueId().$index;

   my ($value, $err);

   Log3 $name, 5, "$name: ReadKeyValue tries to read value for $kName from file";
   ($err, $value) = getKeyValue($index);

   if ( defined($err) ) {
      Log3 $name, 4, "$name: ReadKeyValue is unable to read value from file: $err";
      return undef;
   }  
    
   if ( defined($value) ) {
      if ( eval "use Digest::MD5;1" ) {
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
   } else {
      Log3 $name, 4, "$name: ReadKeyValue could not find key $kName in file";
      return undef;
   }
   return;
} 


# replace strings as defined in Attributes for URL, Header and Data
# type is request type and can be set01, get03, auth01, update
# corresponding context is set, get (or reading, but here we use '' instead)
#########################################################################
sub HTTPMOD_Replace($$$)
{
    my ($hash, $type, $string) = @_;
    my $name    = $hash->{NAME};
    my $context = "";
    my $input   = $string;
    
    if ($type =~ /(auth|set|get)(.*)/) {
        $context = $1;                      # context is type without num
        # for type update there is no num so no individual replacement - only one for the whole update request
    }

    #Log3 $name, 4, "$name: Replace called for request type $type";
    # Loop through all Replacement Regex attributes
    foreach my $rr (sort keys %{$attr{$name}}) {
        next if ($rr !~ /^replacement([0-9]*)Regex$/);
        my $rNum  = $1;
        #Log3 $name, 5, "$name: Replace: rr=$rr, rNum $rNum, look for ${type}Replacement${rNum}Value";
        my $regex = AttrVal($name, "replacement${rNum}Regex", "");
        my $mode  = AttrVal($name, "replacement${rNum}Mode", "text");
        next if (!$regex);
        
        # value can be specific for a get / set / auth step 
        my $value = "";
        if ($context && defined ($attr{$name}{"${type}Replacement${rNum}Value"})) {
            # get / set / auth mit individuellem Replacement für z.B. get01
            $value = $attr{$name}{"${type}Replacement${rNum}Value"};
        } elsif ($context && defined ($attr{$name}{"${context}Replacement${rNum}Value"})) {
            # get / set / auth mit generischem Replacement für alle gets / sets
            $value = $attr{$name}{"${context}Replacement${rNum}Value"};
        } elsif (defined ($attr{$name}{"replacement${rNum}Value"})) {
            # ganz generisches Replacement
            $value = $attr{$name}{"replacement${rNum}Value"};
        }
        Log3 $name, 5, "$name: Replace called for type $type, regex $regex, mode $mode, " .
            ($value ? "value $value" : "empty value") . " input: $string";
        
        my $match = 0;
        if ($mode eq 'text') {
            $match = ($string =~ s/$regex/$value/g);
        } elsif ($mode eq 'reading') {
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
        } elsif ($mode eq 'internal') {
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
        } elsif ($mode eq 'expression') {
            my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
            $SIG{__WARN__} = sub { Log3 $name, 3, "$name: Replacement $rNum with expression $value created warning: @_"; };
            $match = eval {$string =~ s/$regex/$value/gee};
            $SIG{__WARN__} = $oldSig;     
            if ($@) {
                Log3 $name, 3, "$name: Replace: invalid regex / expression: /$regex/$value/gee - $@";
            }
        } elsif ($mode eq 'key') {
            my $rvalue = HTTPMOD_ReadKeyValue($hash, $value);
            if ($string =~ s/$regex/$rvalue/g) {
                Log3 $name, 5, "$name: Replace: key $value value is $rvalue";   
                $match = 1;
            }
        }
        Log3 $name, 4, "$name: Replace: match for type $type, regex $regex, mode $mode, " .
            ($value ? "value $value," : "empty value,") . " input: $input, result is $string" if ($match);
    }
    return $string;
}


# 
#########################################################################
sub HTTPMOD_ModifyWithExpr($$$$$)
{
    my ($name, $context, $num, $attr, $text) = @_;
    my $exp = AttrVal($name, "${context}${num}${attr}", undef);
    if ($exp) {
        my $old = $text;      
        my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');     
        $SIG{__WARN__} = sub { Log3 $name, 3, "$name: ModifyWithExpr ${context}${num}${attr} created warning: @_"; };
        $text = eval($exp);
        $SIG{__WARN__} = $oldSig;     
        if ($@) {
            Log3 $name, 3, "$name: error in $attr for $context $num: $@";
        }
        Log3 $name, 5, "$name: $context $num used $attr to convert\n$old\nto\n$text\nusing expr $exp";
    }   
    return $text;
}



# 
#########################################################################
sub HTTPMOD_PrepareRequest($$;$)
{
    my ($hash, $context, $num) = @_;
    my $name = $hash->{NAME};
    my ($url, $header, $data, $exp);
    $num = 0 if (!$num);    # num is not passed wehn called for update request

    if ($context eq "reading") {
        # called from GetUpdate - not Get / Set / Auth
        $url    = $hash->{MainURL};
        $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestHeader/, keys %{$attr{$name}})));
        $data   = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestData/, keys %{$attr{$name}})));
    } else {
        # called for Get / Set / Auth
        # hole alle Header bzw. generischen Header ohne Nummer 
        $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/${context}${num}Header/, keys %{$attr{$name}})));
        if (length $header == 0) {
            $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/${context}Header/, keys %{$attr{$name}})));
        }
        if (! HTTPMOD_GetFAttr($name, $context, $num, "NoData")) {
            # hole Bestandteile der Post data 
            $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/${context}${num}Data/, keys %{$attr{$name}})));
            if (length $data == 0) {
                $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/${context}Data/, keys %{$attr{$name}})));
            }
        }
        # hole URL
        $url = HTTPMOD_GetFAttr($name, $context, $num, "URL");
        if (!$url) {
            $url = $hash->{MainURL};
        }
    }
    
    $header = HTTPMOD_ModifyWithExpr($name, $context, $num, "HdrExpr", $header);
    $data   = HTTPMOD_ModifyWithExpr($name, $context, $num, "DatExpr", $data);
    $url    = HTTPMOD_ModifyWithExpr($name, $context, $num, "URLExpr", $url);
    
    return ($url, $header, $data);
}


# create a new authenticated session
#########################################################################
sub HTTPMOD_Auth($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my ($url, $header, $data);
    
    # get all steps
    my %steps;
    foreach my $attr (keys %{$attr{$name}}) {
        if ($attr =~ /^sid([0-9]+).+/) {
            $steps{$1} = 1;
        }
    }
    Log3 $name, 4, "$name: Auth called with Steps: " . join (" ", sort keys %steps);
  
    $hash->{sid} = "" if AttrVal($name, "clearSIdBeforeAuth", 0);
    foreach my $step (sort {$b cmp $a} keys %steps) {   # reverse sort
        ($url, $header, $data) = HTTPMOD_PrepareRequest($hash, "sid", $step);
        if ($url) {
            my $ignRedir = AttrVal($name, "sid${step}IgnoreRedirects", 0);
            # add to front of queue (prio)
            HTTPMOD_AddToQueue($hash, $url, $header, $data, "auth$step", undef, 0, $ignRedir, 1);
        } else {
            Log3 $name, 3, "$name: no URL for Auth $step";
        }
    }
    $hash->{LastAuthTry} = FmtDateTime(gettimeofday());
    HTTPMOD_HandleSendQueue("direct:".$name);   # AddToQueue with prio did not call this.
    return;
}


# create hint list for set / get ?
########################################
sub HTTPMOD_UpdateHintList($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "$name: UpdateHintList called";
    $hash->{".getList"} = "";
    if (AttrVal($name, "enableControlSet", undef)) {        # spezielle Sets freigeschaltet?
        #$hash->{".setList"} = "interval reread:noArg stop:noArg start:noArg ";
        $hash->{".setList"} = "interval reread:noArg stop:noArg start:noArg upgradeAttributes:noArg storeKeyValue ";
    } else {
        $hash->{".setList"} = "";
    }
    
    foreach my $aName (keys %{$attr{$name}}) {
        next if ($aName !~ /^([gs]et)([0-9]+)Name$/);
        my $context = $1;
        my $num     = $2;                     
        my $oName   = $attr{$name}{$aName};
        my $opt;
                 
        if ($context eq "set") {
            my $map = "";
            $map = AttrVal($name, "${context}${num}Map", "") if ($context ne "get"); # old Map for set is now IMap (Input)
            $map = AttrVal($name, "${context}${num}IMap", $map);                     # new syntax ovverides old one
            if ($map) {                                                         
                my $hint = $map;                                                # create hint from map
                $hint =~ s/([^,\$]+):([^,\$]+)(,?) */$2$3/g;                    # allow spaces in names
                $hint =~ s/\s/&nbsp;/g;                                         # convert spaces for fhemweb
                $opt  = $oName . ":$hint";                                      # opt is Name:Hint (from Map)
            } elsif (AttrVal($name, "${context}${num}NoArg", undef)) {          # NoArg explicitely specified for a set?
                $opt = $oName . ":noArg";                            
            } else {
                $opt = $oName;                                                  # nur den Namen für opt verwenden.
            }
        } elsif ($context eq "get") {
            if (AttrVal($name, "${context}${num}TextArg", undef)) {             # TextArg explicitely specified for a get?
                $opt = $oName;                                                  # nur den Namen für opt verwenden.
            } else {
                $opt = $oName . ":noArg";                                       # sonst noArg bei get
            }           
        }
        if (AttrVal($name, "${context}${num}Hint", undef)) {                    # gibt es einen expliziten Hint?
            $opt = $oName . ":" . AttrVal($name, "${context}${num}Hint", undef);
        }
        $hash->{".${context}List"} .= $opt . " ";                               # save new hint list
    }
    delete $hash->{".updateHintList"};
    Log3 $name, 5, "$name: UpdateHintList: setlist = " . $hash->{".setList"};
    Log3 $name, 5, "$name: UpdateHintList: getlist = " . $hash->{".getList"};
    return;
}



# update hashes to point back from reading name 
# to attr defining its name and properties
# called after Fhem restart or attribute changes
# to handle existing readings 
########################################################

sub HTTPMOD_UpdateRequestHash($)
{
    my ($hash)   = @_;
    return if (!$hash->{READINGS});
    my $name        = $hash->{NAME};
    my @readingList = sort keys %{$hash->{READINGS}};
    my @attrList    = sort keys %{$attr{$name}};
    
    Log3 $name, 5, "$name: UpdateRequestHash called";
    
    foreach my $aName (@attrList) {
        next if ($aName !~ /^(reading|get|set)([0-9]+)(-[0-9]+)?Name$/);
        my $context = $1;
        my $num     = $2;
        my $nSubNum = ($3 ? $3 : "");       # named SubReading?    
        my $reqType = ($context eq 'reading' ? 'update' : $context . $num);
        
        my $baseReading = $attr{$name}{$aName};   # base reading Name or explicitely named subreading
        
        if ($defs{$name}{READINGS}{$baseReading}) {
            # reading exists
            Log3 $name, 5, "$name: UpdateRequestHash looks at $baseReading, request $reqType, context $context, num $num, nSubNum $nSubNum";
            
            $hash->{defptr}{readingBase}{$baseReading}   = $context;
            $hash->{defptr}{readingNum}{$baseReading}    = $num;
            $hash->{defptr}{readingSubNum}{$baseReading} = $nSubNum if ($nSubNum);
            $hash->{defptr}{requestReadings}{$reqType}{$baseReading} = "$context ${num}" .
                ($nSubNum ? "-$nSubNum" : "");
        }
        # go through the potential subreadings derived from this ..Name attribute with added -Num
        if (!$nSubNum) {
            foreach my $reading (@readingList) {
                next if ($reading !~ /^${baseReading}(-[0-9]+)$/);
                my $subNum = $1;
                Log3 $name, 5, "$name: UpdateRequestHash looks at $reading - subNum $subNum";
                $hash->{defptr}{readingBase}{$reading}   = $context;
                $hash->{defptr}{readingNum}{$reading}    = $num;
                $hash->{defptr}{readingSubNum}{$reading} = $subNum;
                $hash->{defptr}{requestReadings}{$reqType}{$reading} = "$context ${num}${subNum}";
                # deleteOn ... will later check for e.g. reading02-001DeleteOnError but also for reading02-DeleteOnError (without subNum)
            }
        }
        # special Handling for get / set with CheckAllReadings
        if ($aName =~ /^(get|set)([0-9]+)Name$/ && 
           HTTPMOD_GetFAttr($name, $context, $num, 'CheckAllReadings')) {
            foreach my $raName (@attrList) {
                next if ($aName !~ /^(reading)([0-9]+)(-[0-9]+)?Name$/);
                my $rbaseReading = $attr{$name}{$raName};   # common base reading Name   
                my $rNum     = $2;
                my $rnSubNum = ($3 ? $3 : "");              # named SubReading?    
                
                if ($defs{$name}{READINGS}{$rbaseReading}) {
                    # reading exists
                    #$hash->{defptr}{requestReadings}{$reqType}{$rbaseReading} = "$context ${num}" .
                    #    ($rnSubNum ? "-$rnSubNum" : "");
                    # point from reqType get/set and reading Name like "Temp" to the definition in readingXX
                    $hash->{defptr}{requestReadings}{$reqType}{$rbaseReading} = "reading $rNum" .
                        ($rnSubNum ? "-$rnSubNum" : "");
                }
                
                # go through the potential subreadings - the Name attribute was for a base Reading without explicit subNum
                if (!$rnSubNum) {
                    foreach my $reading (@readingList) {
                        next if ($reading !~ /^${rbaseReading}(-[0-9]+)$/);
                        #$hash->{defptr}{requestReadings}{$reqType}{$reading} = "$context ${num}$1";
                        # point from reqType get/set and reading Name like "Temp-001" to the definition in readingXX or even potential readingXX-YYDeleteOnError
                        $hash->{defptr}{requestReadings}{$reqType}{$reading} = "reading ${rNum}$1";
                    }
                }
            }
        }
    }
    delete $hash->{".updateRequestHash"};
    return;
}


#
# SET command - handle predifined control sets
################################################
sub HTTPMOD_ControlSet($$$)
{
    my ($hash, $setName, $setVal) = @_;
    my $name = $hash->{NAME};
    
    if ($setName eq 'interval') {
        if (!$setVal) {
            Log3 $name, 3, "$name: no interval (sec) specified in set, continuing with $hash->{Interval} (sec)";
            return "No Interval specified";
        } else {
            if (int $setVal > 5) {
                $hash->{Interval} = $setVal;
                Log3 $name, 3, "$name: timer interval changed to $hash->{Interval} seconds";
                HTTPMOD_SetTimer($hash);
                return "0";
            } elsif (int $setVal <= 5) {
                Log3 $name, 3, "$name: interval $setVal (sec) to small (must be >5), continuing with $hash->{Interval} (sec)";
                return "interval too small";
            }
        }
    } elsif ($setName eq 'reread') {
        HTTPMOD_GetUpdate("reread:$name");
        return "0";
    } elsif ($setName eq 'stop') {
        RemoveInternalTimer("update:$name");    
        $hash->{TRIGGERTIME}     = 0;
        $hash->{TRIGGERTIME_FMT} = "";
        Log3 $name, 3, "$name: internal interval timer stopped";
        return "0";
    } elsif ($setName eq 'start') {
        HTTPMOD_SetTimer($hash);
        return "0";
    } elsif ($setName eq 'upgradeAttributes') {
        HTTPMOD_UpgradeAttributes($hash);
        return "0";
    } elsif ($setName eq 'storeKeyValue') {
        my $key;
        if ($setVal =~ /([^ ]+) +(.*)/) {
            $key = $1;
            my $err = HTTPMOD_StoreKeyValue($hash, $key, $2);
            return $err if ($err);
        } else {
            return "Please give a key and a value to storeKeyValue";
        }
        return "0";
    }
    return undef;   # no control set identified - continue with other sets
}


#
# SET command
#########################################################################
sub HTTPMOD_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set HTTPMOD\" needs at least an argument" if (@a < 2);
    
    # @a is an array with the command line: DeviceName, setName. Rest is setVal (splitted in fhem.pl by space and tab)
    my ($name, $setName, @setValArr) = @a;
    my $setVal = (@setValArr ? join(' ', @setValArr) : "");
    my (%rmap, $setNum, $setOpt, $rawVal);
   
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "")
        if ($setName ne "?");

    if (AttrVal($name, "enableControlSet", undef)) {        # spezielle Sets freigeschaltet?
        my $error = HTTPMOD_ControlSet($hash, $setName, $setVal);
        return undef if (defined($error) && $error eq "0");    # control set found and done.
        return $error if ($error);          # error
        # continue if function returned undef
    }

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 4, "$name: set called with $setName but device is disabled"
            if ($setName ne "?");
        return undef;
    }   
  
    # Vorbereitung:
    # suche den übergebenen setName in den Attributen und setze setNum
    
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ /^set([0-9]+)Name$/) {            # ist das Attribut ein "setXName" ?
            if ($setName eq $attr{$name}{$aName}) {     # ist es der im konkreten Set verwendete setName?
                $setNum = $1;                           # gefunden -> merke Nummer X im Attribut
            }            
        }
    }
    
    # gültiger set Aufruf? ($setNum oben schon gesetzt?)
    if(!defined ($setNum)) {
        HTTPMOD_UpdateHintList($hash) if ($hash->{".updateHintList"});
        return "Unknown argument $setName, choose one of " . $hash->{".setList"};
    } 
    Log3 $name, 5, "$name: set found option $setName in attribute set${setNum}Name";

    if (!AttrVal($name, "set${setNum}NoArg", undef)) {      # soll überhaupt ein Wert übergeben werden?
        if (!defined($setVal)) {                            # Ist ein Wert übergeben?
            Log3 $name, 3, "$name: set without value given for $setName";
            return "no value given to set $setName";
        }

        # Eingabevalidierung von Sets mit Definition per Attributen
        # 1. Schritt, falls definiert, per Umkehrung der Map umwandeln (z.B. Text in numerische Codes)
        
        
        my $map = AttrVal($name, "set${setNum}Map", "");                # old Map for set is now IMap (Input)
        $map    = AttrVal($name, "set${setNum}IMap", $map);             # new syntax ovverides old one
        if ($map) {                                                         
            my $rm = $map;
            $rm =~ s/([^, ][^,\$]*):([^,][^,\$]*),? */$2:$1, /g;    # reverse map string erzeugen
            $setVal = decode ('UTF-8', $setVal);                    # convert nbsp from fhemweb
            $setVal =~ s/\s|&nbsp;/ /g;                             # back to normal spaces

            %rmap = split (/, *|:/, $rm);                           # reverse hash aus dem reverse string                   

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

        # kein TextArg?
        if (!AttrVal($name, "set${setNum}TextArg", undef)) {     
            # prüfe Min
            if (AttrVal($name, "set${setNum}Min", undef)) {
                my $min = AttrVal($name, "set${setNum}Min", undef);
                Log3 $name, 5, "$name: is checking value $rawVal against min $min";
                return "set value $rawVal is smaller than Min ($min)"
                    if ($rawVal < $min);
            }
            # Prüfe Max
            if (AttrVal($name, "set${setNum}Max", undef)) {
                my $max = AttrVal($name, "set${setNum}Max", undef);
                Log3 $name, 5, "$name: set is checking value $rawVal against max $max";
                return "set value $rawVal is bigger than Max ($max)"
                    if ($rawVal > $max);
            }
        }

        # Konvertiere input mit IExpr falls definiert
        my $exp = AttrVal($name, "set${setNum}Expr", "");       # old syntax for input in set
        $exp    = AttrVal($name, "set${setNum}IExpr", "");      # new syntax overrides old one
        if ($exp) {
            my $val = $rawVal;
            my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');         
            $SIG{__WARN__} = sub { Log3 $name, 3, "$name: Set IExpr $exp created warning: @_"; };
            $rawVal = eval($exp);
            $SIG{__WARN__} = $oldSig;     
            if ($@) {
                Log3 $name, 3, "$name: Set error in setExpr $exp: $@";
            } else {
                Log3 $name, 5, "$name: set converted value $val to $rawVal using expr $exp";
            }
        }        
        Log3 $name, 4, "$name: set will now set $setName -> $rawVal";
    } else {
        # NoArg
        $rawVal = 0;
        Log3 $name, 4, "$name: set will now set $setName";
    }

    my ($url, $header, $data) = HTTPMOD_PrepareRequest($hash, "set", $setNum);
    if ($url) {
        HTTPMOD_Auth $hash if (AttrVal($name, "reAuthAlways", 0));
        HTTPMOD_AddToQueue($hash, $url, $header, $data, "set$setNum", $rawVal); 
    } else {
        Log3 $name, 3, "$name: no URL for set $setNum";
    }
    
    return undef;
}


#
# GET command
#########################################################################
sub HTTPMOD_Get($@)
{
    my ($hash, @a) = @_;
    return "\"get HTTPMOD\" needs at least an argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, getName, options
    my ($name, $getName, @getValArr) = @a;
    my $getVal = (@getValArr ? join(' ', @getValArr) : ""); # optional value after get name - might be used in HTTP request
    my $getNum;

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: get called with $getName but device is disabled"
            if ($getName ne "?");
        return undef;
    }
    Log3 $name, 5, "$name: get called with $getName " if ($getName ne "?");

    # Vorbereitung:
    # suche den übergebenen getName in den Attributen, setze getNum falls gefunden
    foreach my $aName (keys %{$attr{$name}}) {
        if ($aName =~ /^get([0-9]+)Name$/) {              # ist das Attribut ein "getXName" ?
            if ($getName eq $attr{$name}{$aName}) {     # ist es der im konkreten get verwendete getName?
                $getNum = $1;                           # gefunden -> merke Nummer X im Attribut
            }
        }
    }

    # gültiger get Aufruf? ($getNum oben schon gesetzt?)
    if(!defined ($getNum)) {
        HTTPMOD_UpdateHintList($hash) if ($hash->{".updateHintList"});
        return "Unknown argument $getName, choose one of " . $hash->{".getList"};
    } 
    Log3 $name, 5, "$name: get found option $getName in attribute get${getNum}Name";
    Log3 $name, 4, "$name: get will now request $getName" .
        ($getVal ? ", value = $getVal" : ", no optional value");

    my ($url, $header, $data) = HTTPMOD_PrepareRequest($hash, "get", $getNum);
    if ($url) {
        HTTPMOD_Auth $hash if (AttrVal($name, "reAuthAlways", 0));
        HTTPMOD_AddToQueue($hash, $url, $header, $data, "get$getNum", $getVal); 
    } else {
        Log3 $name, 3, "$name: no URL for Get $getNum";
    }

    return "$getName requested, watch readings";
}


#
# request new data from device
# calltype can be update and reread
###################################
sub HTTPMOD_GetUpdate($)
{
    my ($calltype, $name) = split(':', $_[0]);
    my $hash = $defs{$name};
    my ($url, $header, $data, $count);
    my $now = gettimeofday();
    
    Log3 $name, 4, "$name: GetUpdate called ($calltype)";

    if ($calltype eq "update") {
        HTTPMOD_SetTimer($hash);
    }
    
    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: GetUpdate called but device is disabled";
        return undef;
    }
    
    if ($hash->{MainURL}) {
        # queue main get request 
        ($url, $header, $data) = HTTPMOD_PrepareRequest($hash, "reading");          # context "reading" is used for other attrs relevant for GetUpdate
        if ($url) {
            HTTPMOD_Auth $hash if (AttrVal($name, "reAuthAlways", 0));
            HTTPMOD_AddToQueue($hash, $url, $header, $data, "update");              # use request type "update"
        } else {
            Log3 $name, 3, "$name: GetUpdate: no Main URL specified";
        }
    }

    # check if additional readings with individual URLs need to be requested
    foreach my $getAttr (sort keys %{$attr{$name}}) {
        next if ($getAttr !~ /^get([0-9]+)Name$/);
        my $getNum  = $1;
        my $getName = AttrVal($name, $getAttr, ""); 
        next if (!HTTPMOD_GetFAttr($name, 'get', $getNum, "Poll"));
     
        Log3 $name, 5, "$name: GetUpdate checks if poll required for $getName ($getNum)";
        my $lastPoll = 0;
        $lastPoll = $hash->{lastpoll}{$getName} 
            if ($hash->{lastpoll} && $hash->{lastpoll}{$getName});
        my $dueTime = $lastPoll + HTTPMOD_GetFAttr($name, 'get', $getNum, "PollDelay",0);
        if ($now >= $dueTime) {
            Log3 $name, 4, "$name: GetUpdate will request $getName";
            $hash->{lastpoll}{$getName} = $now;
            
            ($url, $header, $data) = HTTPMOD_PrepareRequest($hash, "get", $getNum);
            if ($url) {
                HTTPMOD_Auth $hash if (AttrVal($name, "reAuthAlways", 0));
                HTTPMOD_AddToQueue($hash, $url, $header, $data, "get$getNum"); 
            } else {
                Log3 $name, 3, "$name: no URL for Get $getNum";
            }               
        } else {
            Log3 $name, 5, "$name: GetUpdate will skip $getName, delay not over";
        }
    }
}


# Try to call a parse function if defined
#########################################
sub HTTPMOD_TryCall($$$$)
{
    my ($hash, $buffer, $fName, $type) = @_;
    my $name = $hash->{NAME};
    if (AttrVal($name, $fName, undef)) {
        Log3 $name, 5, "$name: Read is calling $fName for HTTP Response to $type";
        my $func = AttrVal($name, 'parseFunction1', undef);
        no strict "refs";     
        eval { &{$func}($hash,$buffer) };
        if( $@ ) {         
            Log3 $name, 3, "$name: error calling $func: $@";
        }                   
        use strict "refs";
    }
}


# recoursive main part for 
# HTTPMOD_FlattenJSON($$)
###################################
sub HTTPMOD_JsonFlatter($$;$)
{
    my ($hash,$ref,$prefix) = @_;
    my $name = $hash->{NAME};
    
    $prefix = "" if( !$prefix );                                                   

    Log3 $name, 5, "$name: JSON Flatter called : prefix $prefix, ref is $ref";
    if (ref($ref) eq "ARRAY" ) { 
        my $key = 0;
        foreach my $value (@{$ref}) {
            #Log3 $name, 5, "$name: JSON Flatter in array while, key = $key, value = $value"; 
            if(ref($value) eq "HASH" or ref($value) eq "ARRAY") {                                                        
                Log3 $name, 5, "$name: JSON Flatter doing recursion because value is a " . ref($value);
                HTTPMOD_JsonFlatter($hash, $value, $prefix.sprintf("%02i",$key+1)."_"); 
            } else { 
                if (defined ($value)) {             
                    Log3 $name, 5, "$name: JSON Flatter sets $prefix$key to $value";
                    $hash->{ParserData}{JSON}{$prefix.$key} = $value; 
                }
            }
            $key++;         
        }                                                                            
    } elsif (ref($ref) eq "HASH" ) {
        while( my ($key,$value) = each %{$ref}) {                                       
            #Log3 $name, 5, "$name: JSON Flatter in hash while, key = $key, value = $value";
            if(ref($value) eq "HASH" or ref($value) eq "ARRAY") {                                                        
                Log3 $name, 5, "$name: JSON Flatter doing recursion because value is a " . ref($value);
                HTTPMOD_JsonFlatter($hash, $value, $prefix.$key."_");
            } else { 
                if (defined ($value)) {             
                    Log3 $name, 5, "$name: JSON Flatter sets $prefix$key to $value";
                    $hash->{ParserData}{JSON}{$prefix.$key} = $value; 
                }
            }                                                                          
        }                                                                            
    }                                                                              
}                       

# entry to create a flat hash
# out of a pares JSON hash hierarchy
####################################
sub HTTPMOD_FlattenJSON($$)
{
    my ($hash, $buffer) = @_;                                                   
    my $name = $hash->{NAME};

    my $decoded = eval 'decode_json($buffer)'; 
    if ($@) {
        Log3 $name, 3, "$name: error while parsing JSON data: $@";
    } else {
        HTTPMOD_JsonFlatter($hash, $decoded);
        Log3 $name, 4, "$name: extracted JSON values to internal";
    }
}


# format a reading value
###################################
sub HTTPMOD_FormatReading($$$$$)
{
    my ($hash, $context, $num, $val, $reading) = @_;                                                
    my $name = $hash->{NAME};
    my ($format, $decode, $encode);
    my $expr = "";
    my $map  = "";

    if ($context eq "reading") {        
        $expr = AttrVal($name, 'readingsExpr'  . $num, "") if ($context ne "set");   # very old syntax, not for set!
    }

    $decode  = HTTPMOD_GetFAttr($name, $context, $num, "Decode");
    $encode  = HTTPMOD_GetFAttr($name, $context, $num, "Encode");
    $map     = HTTPMOD_GetFAttr($name, $context, $num, "Map") if ($context ne "set");           # not for set!
    $map     = HTTPMOD_GetFAttr($name, $context, $num, "OMap", $map);                           # new syntax
    $format  = HTTPMOD_GetFAttr($name, $context, $num, "Format");
    $expr    = HTTPMOD_GetFAttr($name, $context, $num, "Expr", $expr) if ($context ne "set");   # not for set!
    $expr    = HTTPMOD_GetFAttr($name, $context, $num, "OExpr", $expr);                         # new syntax

    $val = decode($decode, $val) if ($decode);
    $val = encode($encode, $val) if ($encode);
    
    if ($expr) {
        my $old = $val;     # save for later logging
        my $now = ($hash->{".updateTime"} ? $hash->{".updateTime"} : gettimeofday());
        my $timeDiff = 0;       # to be available in Exprs

        my $timeStr = ReadingsTimestamp($name, $reading, 0);
        $timeDiff = ($now - time_str2num($timeStr)) if ($timeStr);  

        my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');        
        $SIG{__WARN__} = sub { Log3 $name, 3, "$name: FormatReadig OExpr $expr created warning: @_"; };
        $val = eval $expr;
        $SIG{__WARN__} = $oldSig;     
        if ($@) {
            Log3 $name, 3, "$name: FormatReading error, context $context, expression $expr: $@";
        }
        
        Log3 $name, 5, "$name: FormatReading changed value with Expr $expr from $old to $val";
    }
    
    if ($map) {                                 # gibt es eine Map?
        my %map = split (/, +|:/, $map);        # hash aus dem map string                   
        if (defined($map{$val})) {              # Eintrag für den gelesenen Wert in der Map?
            my $nVal = $map{$val};              # entsprechender sprechender Wert für den rohen Wert aus dem Gerät
            Log3 $name, 5, "$name: FormatReading found $val in map and converted to $nVal";
            $val = $nVal;
        } else {
            Log3 $name, 3, "$name: FormatReading could not match $val to defined map";
        }
    }
    
    if ($format) {
        Log3 $name, 5, "$name: FormatReading does sprintf with format " . $format .
            " value is $val";
        $val = sprintf($format, $val);
        Log3 $name, 5, "$name: FormatReading sprintf result is $val";
    }
    return $val;
}


# extract reading for a buffer
###################################
sub HTTPMOD_ExtractReading($$$$$)
{
    my ($hash, $buffer, $context, $num, $reqType) = @_;
    # for get / set which use reading.* definitions for parsing reqType might be "get01" and context might be "reading"
    my $name = $hash->{NAME};
    my ($reading, $regex) = ("", "", "");
    my ($json, $xpath, $xpathst, $recomb, $regopt, $sublen, $alwaysn);
    my @subrlist  = ();
    my @matchlist = ();
    my $try = 1;            # was there any applicable parsing definition?
    
    $json    = HTTPMOD_GetFAttr($name, $context, $num, "JSON");
    $xpath   = HTTPMOD_GetFAttr($name, $context, $num, "XPath");
    $xpathst = HTTPMOD_GetFAttr($name, $context, $num, "XPath-Strict");
    $regopt  = HTTPMOD_GetFAttr($name, $context, $num, "RegOpt");
    $recomb  = HTTPMOD_GetFAttr($name, $context, $num, "RecombineExpr");
    $sublen  = HTTPMOD_GetFAttr($name, $context, $num, "AutoNumLen", 0);
    $alwaysn = HTTPMOD_GetFAttr($name, $context, $num, "AlwaysNum");
    
    # support for old syntax
    if ($context eq "reading") {        
        $reading = AttrVal($name, 'readingsName'.$num, ($json ? $json : "reading$num"));
        $regex   = AttrVal($name, 'readingsRegex'.$num, "");
    }
    # new syntax overrides reading and regex
    $reading = HTTPMOD_GetFAttr($name, $context, $num, "Name", $reading);
    $regex   = HTTPMOD_GetFAttr($name, $context, $num, "Regex", $regex);

    my %namedRegexGroups;

    if ($regex) {
        # old syntax for xpath and xpath-strict as prefix in regex - one result joined 
        if (AttrVal($name, "enableXPath", undef) && $regex =~ /^xpath:(.*)/) {
            $xpath = $1;
            Log3 $name, 5, "$name: ExtractReading $reading with old XPath syntax in regex /$regex/, xpath = $xpath";
            eval {@matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath)};
            Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
            @matchlist = (join ",", @matchlist);    # old syntax returns only one value
        } elsif (AttrVal($name, "enableXPath-Strict", undef) && $regex =~ /^xpath-strict:(.*)/) {
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
        } else {
            # normal regex
            if ($regopt) {
                Log3 $name, 5, "$name: ExtractReading $reading with regex /$regex/$regopt ...";
                eval '@matchlist = ($buffer =~ /' . "$regex/$regopt" . ')';
                Log3 $name, 3, "$name: error in regex matching with regex option: $@" if ($@);
                %namedRegexGroups = %+ if (%+);
            } else {
                Log3 $name, 5, "$name: ExtractReading $reading with regex /$regex/...";
                @matchlist = ($buffer =~ /$regex/);
                %namedRegexGroups = %+ if (%+);
            }
            Log3 $name, 5, "$name: " . @matchlist . " capture group(s), " .
                (%namedRegexGroups ? "named capture groups, " : "") .
                "matchlist = " . join ",", @matchlist if (@matchlist);
        }
    } elsif ($json) {
        Log3 $name, 5, "$name: ExtractReading $reading with json $json ...";
        if (defined($hash->{ParserData}{JSON}) && 
            defined($hash->{ParserData}{JSON}{$json})) {
                @matchlist = ($hash->{ParserData}{JSON}{$json});
        } elsif (defined ($hash->{ParserData}{JSON})) {
            Log3 $name, 5, "$name: ExtractReading $reading with json $json did not match a key directly - trying regex match to create a list";
            my @keylist = sort grep /^$json/, keys (%{$hash->{ParserData}{JSON}});
            Log3 $name, 5, "$name: ExtractReading $reading with json /^$json/ got keylist @keylist";
            @matchlist = map ($hash->{ParserData}{JSON}{$_}, @keylist);
        }
    } elsif ($xpath) {
        Log3 $name, 5, "$name: ExtractReading $reading with XPath $xpath";
        eval {@matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath)};
        Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
    } elsif ($xpathst) {
        Log3 $name, 5, "$name: ExtractReading $reading with XPath-Strict $xpathst";
        my $nodeset;
        eval {$nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst)};
        if ($@) {
            Log3 $name, 3, "$name: error in find for XPathStrictNodeset: $@";
        } else {
        
            # bug in xpath handling reported in https://forum.fhem.de/index.php/topic,45176.315.html
            #foreach my $node ($nodeset->get_nodelist) {
            #    push @matchlist, XML::XPath::XMLParser::as_string($node);
            #}
            
            if ($nodeset->isa('XML::XPath::NodeSet')) {
                foreach my $node ($nodeset->get_nodelist) {
                    push @matchlist, XML::XPath::XMLParser::as_string($node);
                }
            } else {
                push @matchlist, $nodeset;
            }
            
        }
    } else {
        $try   = 0; # neither regex, xpath nor json attribute found ...
        Log3 $name, 5, "$name: ExtractReading for context $context, num $num - no individual parse definition";
    }

    my $match = @matchlist;
    if ($match) {
        if ($recomb) {
            Log3 $name, 5, "$name: ExtractReading is recombining $match matches with expression $recomb";
            my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
            $SIG{__WARN__} = sub { Log3 $name, 3, "$name: RecombineExpr $recomb created warning: @_"; };
            my $val = (eval $recomb);
            $SIG{__WARN__} = $oldSig;     
            if ($@) {
                Log3 $name, 3, "$name: ExtractReading error in RecombineExpr: $@";
            }
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
                $val  = HTTPMOD_FormatReading($hash, $context, $eNum, $val, $subReading);
                            
                Log3 $name, 4, "$name: ExtractReading for $context$num sets reading for named capture group $subReading to $val";
                readingsBulkUpdate( $hash, $subReading, $val );
                # point from reading name back to the parsing definition as reading01 or get02 ...
                $hash->{defptr}{readingBase}{$subReading} = $context;                   # used to find maxAge attr
                $hash->{defptr}{readingNum}{$subReading}  = $num;                       # used to find maxAge attr
                $hash->{defptr}{requestReadings}{$reqType}{$subReading} = "$context $eNum"; # used by deleteOnError / deleteIfUnmatched
                delete $hash->{defptr}{readingOutdated}{$subReading};                   # used by MaxAge as well
            }
        } else {
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
                $val = HTTPMOD_FormatReading($hash, $context, $eNum, $val, $subReading);
                            
                Log3 $name, 4, "$name: ExtractReading for $context$num-$group sets $subReading to $val";
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
    } else {
        Log3 $name, 5, "$name: ExtractReading $reading did not match" if ($try);
    }
    return ($try, $match, $reading, @subrlist);
}



# pull log lines to a file
###################################
sub HTTPMOD_PullToFile($$$$)
{
    my ($hash, $buffer, $num, $file) = @_;
    my $name = $hash->{NAME};

    my $reading   = HTTPMOD_GetFAttr($name, "get", $num, "Name");
    my $regex     = HTTPMOD_GetFAttr($name, "get", $num, "Regex");
    my $iterate   = HTTPMOD_GetFAttr($name, "get", $num, "PullIterate");
    my $recombine = HTTPMOD_GetFAttr($name, "get", $num, "RecombineExpr");
    $recombine    = '$1' if not ($recombine);
    my $matches   = 0;
    $hash->{GetSeq} = 0 if (!$hash->{GetSeq});

    Log3 $name, 5, "$name: Read is pulling to file, sequence is $hash->{GetSeq}";
    while ($buffer =~ /$regex/g) {
        $matches++;                 
        no warnings qw(uninitialized);
        my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
        $SIG{__WARN__} = sub { Log3 $name, 3, "$name: RecombineExpr $recombine created warning: @_"; };
        my $val = eval($recombine);
        $SIG{__WARN__} = $oldSig;     
        if ($@) {
            Log3 $name, 3, "$name: PullToFile error in RecombineExpr $recombine: $@";
        } else {
            Log3 $name, 3, "$name: Read pulled line $val";
        }
    }
    Log3 $name, 3, "$name: Read pulled $matches lines";
    if ($matches) {
        if ($iterate && $hash->{GetSeq} < $iterate) {
            $hash->{GetSeq}++;                  
            Log3 $name, 5, "$name: Read is iterating pull until $iterate, next is $hash->{GetSeq}";
            my ($url, $header, $data) = HTTPMOD_PrepareRequest($hash, "get", $num);
            HTTPMOD_AddToQueue($hash, $url, $header, $data, "get$num"); 
        } else {
            Log3 $name, 5, "$name: Read is done with pull after $hash->{GetSeq}.";
        }
    } else {
        Log3 $name, 5, "$name: Read is done with pull, no more lines matched";
    }
    return (1, 1, $reading);
}



# delete a reading and its metadata
###################################
sub HTTPMOD_DeleteReading($$)
{
    my ($hash, $reading) = @_;
    my $name = $hash->{NAME};
    delete($defs{$name}{READINGS}{$reading});
    delete $hash->{defptr}{readingOutdated}{$reading};
    delete $hash->{defptr}{readingBase}{$reading};
    delete $hash->{defptr}{readingNum}{$reading};
    delete $hash->{defptr}{readingSubNum}{$reading};
    
    foreach my $rt (keys %{$hash->{defptr}{requestReadings}}) {
        delete $hash->{defptr}{requestReadings}{$rt}{$reading};
    }
    
}


# check max age of all readings
###################################
sub HTTPMOD_DoMaxAge($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my ($base, $num, $sub, $max, $rep, $mode, $time, $now);
    my $readings = $hash->{READINGS};
    return if (!$readings); 
    $now = gettimeofday();

    HTTPMOD_UpdateRequestHash($hash) if ($hash->{".updateRequestHash"});
    
    foreach my $reading (sort keys %{$readings}) {
        my $key = $reading;     # in most cases the reading name can be looked up in the readingBase hash
        Log3 $name, 5, "$name: MaxAge: check reading $reading";
        if ($hash->{defptr}{readingOutdated}{$reading}) {
            Log3 $name, 5, "$name: MaxAge: reading $reading was outdated before - skipping";
            next;
        }
        
        # get base name of definig attribute like "reading" or "get" 
        $base = $hash->{defptr}{readingBase}{$reading};
        if (!$base && $reading =~ /(.*)(-[0-9]+)$/) {
            # reading name endet auf -Zahl und ist nicht selbst per attr Name definiert 
            # -> suche nach attr Name mit Wert ohne -Zahl
            $key  = $1;
            $base = $hash->{defptr}{readingBase}{$key};
            Log3 $name, 5, "$name: MaxAge: no defptr for this name - reading name seems automatically created with $2 from $key and not updated recently";
        }
        if (!$base) {
            Log3 $name, 5, "$name: MaxAge: reading $reading doesn't come from a -Name attr -> skipping";
            next;
        }
        
        $num = $hash->{defptr}{readingNum}{$key};
        if ($hash->{defptr}{readingSubNum}{$key}) {
            $sub = $hash->{defptr}{readingSubNum}{$key};
        } else {
            $sub = "";
        }

        Log3 $name, 5, "$name: MaxAge: reading definition comes from $base, $num" . ($sub ? ", $sub" : "");
        $max = HTTPMOD_GetFAttr($name, $base, $num . $sub, "MaxAge");
        if ($max) {
            $rep  = HTTPMOD_GetFAttr($name, $base, $num . $sub, "MaxAgeReplacement", "");
            $mode = HTTPMOD_GetFAttr($name, $base, $num . $sub, "MaxAgeReplacementMode", "text");
            $time = ReadingsTimestamp($name, $reading, 0);
            Log3 $name, 5, "$name: MaxAge: max = $max, mode = $mode, rep = $rep";
            if ($now - time_str2num($time) > $max) {
                if ($mode eq "expression") {
                    Log3 $name, 4, "$name: MaxAge: reading $reading too old - using Perl expression as MaxAge replacement: $rep";
                    my $val = ReadingsVal($name, $reading, "");
                    my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');                 
                    $SIG{__WARN__} = sub { Log3 $name, 3, "$name: MaxAge replacement expr $rep created warning: @_"; };
                    $rep = eval($rep);
                    $SIG{__WARN__} = $oldSig;     
                    if($@) {         
                        Log3 $name, 3, "$name: MaxAge: error in replacement expression $1: $@";
                        $rep = "error in replacement expression";
                    } else {
                        Log3 $name, 4, "$name: MaxAge: result is $rep";
                    }
                    readingsBulkUpdate($hash, $reading, $rep);
                    
                } elsif ($mode eq "text") {
                    Log3 $name, 4, "$name: MaxAge: reading $reading too old - using $rep instead";
                    readingsBulkUpdate($hash, $reading, $rep);
                                        
                } elsif ($mode eq 'reading') {
                    my $device  = $name;
                    my $rname = $rep;
                    if ($rep =~ /^([^\:]+):(.+)$/) {
                        $device  = $1;
                        $rname = $2;
                    }
                    my $rvalue = ReadingsVal($device, $rname, "");
                    Log3 $name, 4, "$name: MaxAge: reading $reading too old - using reading $rname with value $rvalue instead";
                    readingsBulkUpdate($hash, $reading, $rvalue);

                } elsif ($mode eq 'internal') {
                    my $device   = $name;
                    my $internal = $rep;
                    if ($rep =~ /^([^\:]+):(.+)$/) {
                        $device   = $1;
                        $internal = $2;
                    }
                    my $rvalue = InternalVal($device, $internal, "");
                    Log3 $name, 4, "$name: MaxAge: reading $reading too old - using internal $internal with value $rvalue instead";
                    readingsBulkUpdate($hash, $reading, $rvalue);
                    
                } elsif ($mode eq "delete") {
                    Log3 $name, 4, "$name: MaxAge: reading $reading too old - delete it";
                    HTTPMOD_DeleteReading($hash, $reading);
                }
                $hash->{defptr}{readingOutdated}{$reading} = 1 if ($mode ne "delete");
            }
        } else {
            Log3 $name, 5, "$name: MaxAge: No MaxAge attr for $base, $num, $sub";
        }
    }
}




# check delete option on error
# for readings that were created in the last reqType
# e.g. get04 but maybe defined in reading02Regex
######################################################
sub HTTPMOD_DoDeleteOnError($$)
{
    my ($hash, $reqType) = @_;
    my $name = $hash->{NAME};
    
    return if (!$hash->{READINGS}); 
    HTTPMOD_UpdateRequestHash($hash) if ($hash->{".updateRequestHash"});
    
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
        if (HTTPMOD_GetFAttr($name, $context, $eNum, "DeleteOnError")) {
            Log3 $name, 4, "$name: DoDeleteOnError: delete reading $reading created by $reqType ($context, $eNum)";
            HTTPMOD_DeleteReading($hash, $reading);
        }
    }
}


# check delete option if unmatched
###################################
sub HTTPMOD_DoDeleteIfUnmatched($$@)
{
    my ($hash, $reqType, @matched) = @_;
    my $name = $hash->{NAME};
    
    Log3 $name, 5, "$name: DoDeleteIfUnmatched called with request $reqType";
    return if (!$hash->{READINGS}); 
    HTTPMOD_UpdateRequestHash($hash) if ($hash->{".updateRequestHash"});
    
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
    foreach my $reading (@rList) {
        
        Log3 $name, 5, "$name: DoDeleteIfUnmatched: check reading $reading" 
            . ($matched{$reading} ? " (matched)" : " (no match)");
        next if ($matched{$reading});
        
        my ($context, $eNum) = split (" ", $reqReadings->{$reading});
        Log3 $name, 5, "$name: DoDeleteIfUnmatched: check attr for reading $reading ($context, $eNum)";
        if (HTTPMOD_GetFAttr($name, $context, $eNum, "DeleteIfUnmatched")) {
            Log3 $name, 4, "$name: DoDeleteIfUnmatched: delete reading $reading created by $reqType ($context, $eNum)";
            HTTPMOD_DeleteReading($hash, $reading);
        } else {
            Log3 $name, 5, "$name: DoDeleteIfUnmatched: no DeleteIfUnmatched for reading $reading ($context, $eNum)";
        }
    }
}


#
# extract cookies from HTTP Response Header
# called from _Read
###########################################
sub HTTPMOD_GetCookies($$)
{
    my ($hash, $header) = @_;
    my $name = $hash->{NAME};
    #Log3 $name, 5, "$name: looking for Cookies in $header";
    Log3 $name, 5, "$name: GetCookies is looking for Cookies";
    foreach my $cookie ($header =~ m/set-cookie: ?(.*)/gi) {
        #Log3 $name, 5, "$name: GetCookies found Set-Cookie: $cookie";
        $cookie =~ /([^,; ]+)=([^,; ]+)[;, ]*([^\v]*)/;
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
}


# initialize Parsers
# called from _Read
###################################
sub HTTPMOD_InitParsers($$)
{
    my ($hash, $body) = @_;
    my $name = $hash->{NAME};

    # initialize parsers
    if ($hash->{JSONEnabled} && $body) {
        HTTPMOD_FlattenJSON($hash, $body);
    }
    if ($hash->{XPathEnabled} && $body) {
        $hash->{ParserData}{XPathTree} = HTML::TreeBuilder::XPath->new;
        eval {$hash->{ParserData}{XPathTree}->parse($body)};
        Log3 $name, ($@ ? 3 : 5), "$name: InitParsers: XPath parsing " . ($@ ? "error: $@" : "done.");
    }
    if ($hash->{XPathStrictEnabled} && $body) {
        eval {$hash->{ParserData}{XPathStrictNodeset} = XML::XPath->new(xml => $body)};
        Log3 $name, ($@ ? 3 : 5), "$name: InitParsers: XPath-Strict parsing " . ($@ ? "error: $@" : "done.");
    }
}


# cleanup Parsers
# called from _Read
###################################
sub HTTPMOD_CleanupParsers($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ($hash->{XPathEnabled}) {
        if ($hash->{ParserData}{XPathTree}) {
            eval {$hash->{ParserData}{XPathTree}->delete()};
            Log3 $name, 3, "$name: error deleting XPathTree: $@" if ($@);
        }
    }
    if ($hash->{XPathStrictEnabled}) {
        if ($hash->{ParserData}{XPathStrictNodeset}) {
            eval {$hash->{ParserData}{XPathStrictNodeset}->cleanup()};
            Log3 $name, 3, "$name: error deleting XPathStrict nodeset: $@" if ($@);
        }
    }
    delete $hash->{ParserData};
}


# Extract SID
# called from _Read
###################################
sub HTTPMOD_ExtractSid($$$$)
{
    my ($hash, $buffer, $context, $num) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "$name: ExtractSid called, context $context, num $num";
    my $regex   = AttrVal($name, "idRegex", "");
    my $json    = AttrVal($name, "idJSON", "");
    my $xpath   = AttrVal($name, "idXPath", "");
    my $xpathst = AttrVal($name, "idXPath-Strict", ""); 
    
    $regex   = HTTPMOD_GetFAttr($name, $context, $num, "IDRegex", $regex);
    $regex   = HTTPMOD_GetFAttr($name, $context, $num, "IdRegex", $regex);
    $json    = HTTPMOD_GetFAttr($name, $context, $num, "IdJSON", $json);
    $xpath   = HTTPMOD_GetFAttr($name, $context, $num, "IdXPath", $xpath);
    $xpathst = HTTPMOD_GetFAttr($name, $context, $num, "IdXPath-Strict", $xpathst);

    my @matchlist;
    if ($json) {
        Log3 $name, 5, "$name: Checking SID with JSON $json";
        if (defined($hash->{ParserData}{JSON}) && 
            defined($hash->{ParserData}{JSON}{$json})) {
                @matchlist = ($hash->{ParserData}{JSON}{$json});
        }
    } elsif ($xpath) {
        Log3 $name, 5, "$name: Checking SID with XPath $xpath";
        eval {@matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath)};
        Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
    } elsif ($xpathst) {
        Log3 $name, 5, "$name: Checking SID with XPath-Strict $xpathst";
        my $nodeset;
        eval {$nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst)};
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
        } else {
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
        } else {
            Log3 $name, 5, "$name: ExtractSid could not match buffer to IdRegex $regex";
        }
    }
}


# Check if Auth is necessary
# called from _Read
###################################
sub HTTPMOD_CheckAuth($$$$$)
{
    my ($hash, $buffer, $request, $context, $num) = @_;
    my $name = $hash->{NAME};
    my $doAuth;

    my $regex   = AttrVal($name, "reAuthRegex", "");
    my $json    = AttrVal($name, "reAuthJSON", "");
    my $xpath   = AttrVal($name, "reAuthXPath", "");
    my $xpathst = AttrVal($name, "reAuthXPath-Strict", "");

    if ($context =~ /([gs])et/) {
        $regex   = HTTPMOD_GetFAttr($name, $context, $num, "ReAuthRegex", $regex);
        $json    = HTTPMOD_GetFAttr($name, $context, $num, "ReAuthJSON", $json);
        $xpath   = HTTPMOD_GetFAttr($name, $context, $num, "ReAuthXPath", $xpath);
        $xpathst = HTTPMOD_GetFAttr($name, $context, $num, "ReAuthXPath-Strict", $xpathst);
    }
    
    my @matchlist;
    if ($json) {
        Log3 $name, 5, "$name: Checking Auth with JSON $json";
        if (defined($hash->{ParserData}{JSON}) && 
            defined($hash->{ParserData}{JSON}{$json})) {
                @matchlist = ($hash->{ParserData}{JSON}{$json});
        }
    } elsif ($xpath) {
        Log3 $name, 5, "$name: Checking Auth with XPath $xpath";
        eval {@matchlist = $hash->{ParserData}{XPathTree}->findnodes_as_strings($xpath)};
        Log3 $name, 3, "$name: error in findvalues for XPathTree: $@" if ($@);
    } elsif ($xpathst) {
        Log3 $name, 5, "$name: Checking Auth with XPath-Strict $xpathst";
        my $nodeset;
        eval {$nodeset = $hash->{ParserData}{XPathStrictNodeset}->find($xpathst)};
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
            HTTPMOD_Auth $hash;
            if (!AttrVal($name, "dontRequeueAfterAuth", 0)) {
                HTTPMOD_AddToQueue ($hash, $request->{url}, $request->{header}, 
                    $request->{data}, $request->{type}, $request->{value}, $request->{retryCount}+1); 
                Log3 $name, 4, "$name: CheckAuth requeued request $request->{type} after auth, retryCount $request->{retryCount} ...";
            }
            return 1;
        } else {
            Log3 $name, 4, "$name: Authentication still required but no retries left - did last authentication fail?";
        }
    } else {
        Log3 $name, 4, "$name: CheckAuth decided no authentication required";    
    }
    return 0;
}


# update List of Readings to parse
# during GetUpdate cycle
###################################
sub HTTPMOD_UpdateReadingList($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};

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
}


sub HTTPMOD_CheckRedirects($$)
{
    my ($hash, $header) = @_;
    my $name    = $hash->{NAME};
    my $request = $hash->{REQUEST};
    my $type    = $request->{type};
    my $url     = $request->{url};
    
    my @header= split("\r\n", $hash->{httpheader});
    my @header0= split(" ", shift @header);
    my $code= $header0[1];
    Log3 $name, 4, "$name: checking for redirects, code=$code, ignore=$request->{ignoreredirects}";
    if ($code==301 || $code==302 || $code==303) {       # redirect ?
        $hash->{HTTPMOD_Redirects} = 0 if (!$hash->{HTTPMOD_Redirects});
        if(++$hash->{HTTPMOD_Redirects} > 5) {
            Log3 $name, 3, "$name: Too many redirects processing response to $url";
            return;
        } else {
            my $ra;
            map { $ra=$1 if($_ =~ m/Location:\s*(\S+)$/) } @header;
            $ra = "/$ra" if($ra !~ m/^http/ && $ra !~ m/^\//);
            my $rurl = ($ra =~ m/^http/) ? $ra: $hash->{addr}.$ra;
            if ($request->{ignoreredirects}) {
                Log3 $name, 4, "$name: ignoring redirect to $rurl";
                return;
            }
            Log3 $name, 4, "$name: $url: Redirect ($hash->{HTTPMOD_Redirects}) to $rurl";
            # add new url with prio to queue, old header, no data todo: redirect with post possible / supported??
            HTTPMOD_AddToQueue($hash, $rurl, $request->{header}, "", $type, undef, $request->{retryCount}, 0, 1);   
            HTTPMOD_HandleSendQueue("direct:".$name);   # AddToQueue with prio did not call this.
            return 1;
        }
    } else {
        Log3 $name, 4, "$name: no redirects to handle";
    }
}

#
# read / parse new data from device
# - callback for non blocking HTTP 
###################################
sub HTTPMOD_Read($$$)
{
    my ($hash, $err, $body) = @_;
    my $name    = $hash->{NAME};
    my $request = $hash->{REQUEST};
    my $header  = ($hash->{httpheader} ? $hash->{httpheader} : "");
    my $type    = $request->{type};
    my ($buffer, $num, $context, $authQueued);
    my @subrlist = ();
        
    # set attribute prefix and num for parsing and formatting depending on request type
    if ($type =~ /(set|get)(.*)/) {
        $context = $1;      $num = $2;
    } elsif ($type =~ /(auth)(.*)/) {
        $context = "sid";   $num = $2;
    } else {   
        $context = "reading"; $num = "";
    }
    
    if (!$name || $hash->{TYPE} ne "HTTPMOD") {
        $name = "HTTPMOD";
        Log3 $name, 3, "HTTPMOD _Read callback was called with illegal hash - this should never happen - problem in HttpUtils?";
        return undef;
    }
    
    $hash->{BUSY} = 0;
    Log3 $name, 3, "$name: Read callback: Error: $err" if ($err);
    Log3 $name, 4, "$name: Read callback: request type was $type" . 
        " retry $request->{retryCount}" .
         #($header ? ",\r\nHeader: $header" : ", no headers") . 
         ($body ? ",\r\nBody: $body" : ", body empty");
    
    $body = "" if (!$body);
    
    my $ppr = AttrVal($name, "preProcessRegex", "");
    if ($ppr) {
            my $pprexp = '$body=~' . $ppr; 
            my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
            $SIG{__WARN__} = sub { Log3 $name, 3, "$name: read applying preProcessRegex created warning: @_"; };
            eval $pprexp;
            $SIG{__WARN__} = $oldSig;
    
        $body =~ $ppr;
        Log3 $name, 5, "$name: Read - body after preProcessRegex: $ppr is $body";
    }
    
    $buffer = ($header ? $header . "\r\n\r\n" . $body : $body);      # for matching sid / reauth
    $buffer = $buffer . "\r\n\r\n" . $err if ($err);                 # for matching reauth
    
    #delete $hash->{buf} if (AttrVal($name, "removeBuf", 0));
    if (AttrVal($name, "showBody", 0)) {
        $hash->{httpbody} = $body;
    }
    
    HTTPMOD_InitParsers($hash, $body);   
    HTTPMOD_GetCookies($hash, $header) if (AttrVal($name, "enableCookies", 0));   
    HTTPMOD_ExtractSid($hash, $buffer, $context, $num); 
    
    return if (AttrVal($name, "handleRedirects", 0) && HTTPMOD_CheckRedirects($hash, $header));
    delete $hash->{HTTPMOD_Redirects};
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate ($hash, "LAST_ERROR", $err)      if ($err && AttrVal($name, "showError", 0));
    readingsBulkUpdate($hash, "LAST_REQUEST", $type)    if (AttrVal($name, "showMatched", undef));
    
    HTTPMOD_DoMaxAge($hash) if ($hash->{MaxAgeEnabled});
    
    $authQueued = HTTPMOD_CheckAuth($hash, $buffer, $request, $context, $num) if ($context ne "sid");
    
    if ($err || $authQueued || 
        ($context =~ "set|sid" && !HTTPMOD_GetFAttr($name, $context, $num, "ParseResponse"))) {
        readingsEndUpdate($hash, 1);
        HTTPMOD_DoDeleteOnError($hash, $type)   if ($hash->{DeleteOnError}); 
        HTTPMOD_CleanupParsers($hash);
        return undef;   # don't continue parsing response  
    }
      
    my ($checkAll, $tried, $match, $reading); 
    my @unmatched = (); my @matched   = ();
    
    my $file = HTTPMOD_GetFAttr($name, $context, $num, "PullToFile");
    if ($context eq "get" && $file) {
        ($tried, $match, $reading) = HTTPMOD_PullToFile($hash, $buffer, $num, $file);
        return undef;
    }

    if ($context =~ "get|set") {
        ($tried, $match, $reading, @subrlist) = HTTPMOD_ExtractReading($hash, $buffer, $context, $num, $type);
        if ($tried) {
            if($match) {
                push @matched, @subrlist;
            } else {
                push @unmatched, $reading;
            }
        }
        $checkAll = HTTPMOD_GetFAttr($name, $context, $num, 'CheckAllReadings', !$tried);
        # if ExtractReading2 could not find any parsing instruction (e.g. regex) then check all Readings
    } else {
        $checkAll = 1;
    }
    
    if (AttrVal($name, "extractAllJSON", "") || HTTPMOD_GetFAttr($name, $context, $num, "ExtractAllJSON")) {
        # create a reading for each JSON object and use formatting options if a correspondig reading name / formatting is defined 
        if (ref $hash->{ParserData}{JSON} eq "HASH") {
            foreach my $object (keys %{$hash->{ParserData}{JSON}}) {
                # todo: create good reading name with makeReadingName instead of using the potentially illegal object name
                my $rName = $object;                
                $rName = makeReadingName($object) if (AttrVal($name, "enforceGoodReadingNames", 0));    # todo: should become default with next fhem version
                my $value = $hash->{ParserData}{JSON}{$object};
                Log3 $name, 5, "$name: Read set JSON $object as reading $rName to value " . $value;
                $value = HTTPMOD_FormatReading($hash, $context, $num, $value, $rName);
                readingsBulkUpdate($hash, $rName, $value);
                push @matched, $rName;     # unmatched is not filled for "ExtractAllJSON"
                delete $hash->{defptr}{readingOutdated}{$rName};
                
                $hash->{defptr}{readingBase}{$rName} = $context;
                $hash->{defptr}{readingNum}{$rName}  = $num;
                $hash->{defptr}{requestReadings}{$type}{$rName} = "$context $num";
            }
        } else {
            Log3 $name, 3, "$name: no parsed JSON structure available";
        }
    } 
    
    HTTPMOD_UpdateReadingList($hash) if ($hash->{".updateReadingList"});   
    if ($checkAll && defined($hash->{".readingParseList"})) {
        # check all defined readings and try to extract them
               
        Log3 $name, 5, "$name: Read starts parsing response to $type with defined readings: " . 
                join (",", @{$hash->{".readingParseList"}});
        foreach $num (@{$hash->{".readingParseList"}}) {
            # try to parse readings defined in reading.* attributes
            # pass request $type so we know for later delete
            (undef, $match, $reading, @subrlist) = HTTPMOD_ExtractReading($hash, $buffer, 'reading', $num, $type);
            if($match) {
                push @matched, @subrlist;
            } else {
                push @unmatched, $reading;
            }
        }
    }
    if (AttrVal($name, "showMatched", undef)) {
        readingsBulkUpdate($hash, "MATCHED_READINGS", join ' ', @matched);
        readingsBulkUpdate($hash, "UNMATCHED_READINGS", join ' ', @unmatched);
    }

    if (!@matched) {
        Log3 $name, 3, "$name: Read response to $type didn't match any Reading";
    } else {
        Log3 $name, 4, "$name: Read response to $type matched Reading(s) " . join ' ', @matched;
        Log3 $name, 4, "$name: Read response to $type did not match "      . join ' ', @unmatched if (@unmatched);
    }
    
    HTTPMOD_TryCall($hash, $buffer, 'parseFunction1', $type);
    readingsEndUpdate($hash, 1);
    HTTPMOD_TryCall($hash, $buffer, 'parseFunction2', $type);
    
    HTTPMOD_DoDeleteIfUnmatched($hash, $type, @matched) 
        if ($hash->{DeleteIfUnmatched});
        
    HTTPMOD_HandleSendQueue("direct:".$name);  
    HTTPMOD_CleanupParsers($hash);
   
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
        if ($hash->{LASTSEND} && $now > $hash->{LASTSEND} + (AttrVal($name, "timeout", 2)*2)
                              && $now > $hash->{LASTSEND} + 15) {
            Log3 $name, 5, "$name: HandleSendQueue - still waiting for reply, timeout is over twice - this should never happen";
            Log3 $name, 5, "$name: HandleSendQueue - stop waiting";
            $hash->{BUSY} = 0;
        } else {
            if ($hash->{LASTSEND} && $now > $hash->{LASTSEND} + ($queueDelay * 2)) {
                $queueDelay *= 2;
            }
            InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
            Log3 $name, 5, "$name: HandleSendQueue - still waiting for reply to last request, delay sending from queue";
            return;
        }
    }

    $hash->{REQUEST} = $queue->[0];

    if($hash->{REQUEST}{url} ne "") {    # if something to send - check min delay and send
        my $minSendDelay = AttrVal($hash->{NAME}, "minSendDelay", 0.2);

        if ($hash->{LASTSEND} && $now < $hash->{LASTSEND} + $minSendDelay) {
            InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
            Log3 $name, 5, "$name: HandleSendQueue - minSendDelay not over, rescheduling";
            return;
        }   
        
        # set parameters for HttpUtils from request into hash
        $hash->{BUSY}            = 1;           # HTTPMOD queue is busy until response is received
        $hash->{LASTSEND}        = $now;        # remember when last sent
        $hash->{redirects}       = 0;           # for HttpUtils
        $hash->{callback}        = \&HTTPMOD_Read;
        $hash->{url}             = $hash->{REQUEST}{url};
        $hash->{header}          = $hash->{REQUEST}{header};
        $hash->{data}            = $hash->{REQUEST}{data}; 
        $hash->{value}           = $hash->{REQUEST}{value}; 
        $hash->{timeout}         = AttrVal($name, "timeout", 2);
        $hash->{httpversion}     = AttrVal($name, "httpVersion", "1.0");
        if (AttrVal($name, "handleRedirects", 0)) {
            $hash->{ignoreredirects} = 1;           # HttpUtils should not follow redirects if we do it in HTTPMOD
        } else {
            $hash->{ignoreredirects} = $hash->{REQUEST}{ignoreredirects};   # as defined in queue / set when adding to queue
        }
        
        my $sslArgList = AttrVal($name, "sslArgs", undef);
        if ($sslArgList) {
            Log3 $name, 5, "$name: sslArgs is set to $sslArgList";
            my %sslArgs = split (',', $sslArgList);
            Log3 $name, 5, "$name: sslArgs hash keys:   " . join(",", keys %sslArgs);
            Log3 $name, 5, "$name: sslArgs hash values: " . join(",", values %sslArgs);
            $hash->{sslargs}     = \%sslArgs;
        }
      
        if (AttrVal($name, "noShutdown", undef)) {
            $hash->{noshutdown} = 1;
        } else {
            delete $hash->{noshutdown};
        };
    
        # do user defined replacements first
        if ($hash->{ReplacementEnabled}) {
            $hash->{header} = HTTPMOD_Replace($hash, $hash->{REQUEST}{type}, $hash->{header});
            $hash->{data}   = HTTPMOD_Replace($hash, $hash->{REQUEST}{type}, $hash->{data});
            $hash->{url}    = HTTPMOD_Replace($hash, $hash->{REQUEST}{type}, $hash->{url});
        }
        
        # then replace $val in header, data and URL with value from request (setVal) if it is still there
        $hash->{header} =~ s/\$val/$hash->{value}/g;
        $hash->{data}   =~ s/\$val/$hash->{value}/g;
        $hash->{url}    =~ s/\$val/$hash->{value}/g;
                
        # sid replacement is also done here - just before sending so changes in session while request was queued will be reflected
        if ($hash->{sid}) {
            $hash->{header} =~ s/\$sid/$hash->{sid}/g;
            $hash->{data}   =~ s/\$sid/$hash->{sid}/g;
            $hash->{url}    =~ s/\$sid/$hash->{sid}/g;
        }
        
                
        if (AttrVal($name, "enableCookies", 0)) {       
            my $uriPath = "";
            if($hash->{url} =~ /
                ^(http|https):\/\/                # $1: proto
                (([^:\/]+):([^:\/]+)@)?          # $2: auth, $3:user, $4:password
                ([^:\/]+|\[[0-9a-f:]+\])         # $5: host or IPv6 address
                (:\d+)?                          # $6: port
                (\/.*)$                          # $7: path
                /xi) {
                $uriPath = $7;
            }
            my $cookies = "";
            if ($hash->{HTTPCookieHash}) {
                foreach my $cookie (sort keys %{$hash->{HTTPCookieHash}}) {
                    my $cPath = $hash->{HTTPCookieHash}{$cookie}{Path};
                    my $idx = index ($uriPath, $cPath);
                    #Log3 $name, 5, "$name: HandleSendQueue checking cookie $hash->{HTTPCookieHash}{$cookie}{Name} path $cPath";
                    #Log3 $name, 5, "$name: HandleSendQueue cookie path $cPath";
                    #Log3 $name, 5, "$name: HandleSendQueue URL path $uriPath";
                    #Log3 $name, 5, "$name: HandleSendQueue no cookie path" if (!$cPath);
                    #Log3 $name, 5, "$name: HandleSendQueue URL path" if (!$uriPath);
                    #Log3 $name, 5, "$name: HandleSendQueue cookie path match idx = $idx";
                    if (!$uriPath || !$cPath || $idx == 0) {
                        Log3 $name, 5, "$name: HandleSendQueue is using Cookie $hash->{HTTPCookieHash}{$cookie}{Name} " .
                            "with path $hash->{HTTPCookieHash}{$cookie}{Path} and Value " .
                            "$hash->{HTTPCookieHash}{$cookie}{Value} (key $cookie, destination path is $uriPath)";
                        $cookies .= "; " if ($cookies); 
                        $cookies .= $hash->{HTTPCookieHash}{$cookie}{Name} . "=" . $hash->{HTTPCookieHash}{$cookie}{Value};
                    } else {
                        #Log3 $name, 5, "$name: HandleSendQueue no cookie path match";
                        Log3 $name, 5, "$name: HandleSendQueue is ignoring Cookie $hash->{HTTPCookieHash}{$cookie}{Name} ";
                        Log3 $name, 5, "$name: " . unpack ('H*', $cPath);
                        Log3 $name, 5, "$name: " . unpack ('H*', $uriPath);
                    }
                }
            }
            if ($cookies) {
                Log3 $name, 5, "$name: HandleSendQueue is adding Cookie header: $cookies";
                $hash->{header} .= "\r\n" if ($hash->{header});
                $hash->{header} .= "Cookie: " . $cookies;
            }
        }
                
        Log3 $name, 4, "$name: HandleSendQueue sends request type $hash->{REQUEST}{type} to " .
                        "URL $hash->{url}, " . 
                        ($hash->{data} ? "\r\ndata: $hash->{data}, " : "No Data, ") .
                        ($hash->{header} ? "\r\nheader: $hash->{header}" : "No Header") .
                        "\r\ntimeout $hash->{timeout}";
                        
        shift(@{$queue});       # remove first element from queue
        HttpUtils_NonblockingGet($hash);
    } else {
        shift(@{$queue});       # remove invalid first element from queue
    }

    if(@{$queue} > 0) {         # more items in queue -> schedule next handle 
        InternalTimer($now+$queueDelay, "HTTPMOD_HandleSendQueue", "queue:$name", 0);
    }
  }
}



#####################################
sub
HTTPMOD_AddToQueue($$$$$;$$$$){
    my ($hash, $url, $header, $data, $type, $value, $count, $ignoreredirects, $prio) = @_;
    my $name = $hash->{NAME};

    $value           = 0 if (!$value);
    $count           = 0 if (!$count);
    $ignoreredirects = 0 if (! defined($ignoreredirects));
    
    my %request;
    $request{url}             = $url;
    $request{header}          = $header;
    $request{data}            = $data;
    $request{type}            = $type;
    $request{value}           = $value;
    $request{retryCount}      = $count;
    $request{ignoreredirects} = $ignoreredirects;
    
    my $qlen = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
    Log3 $name, 4, "$name: AddToQueue adds $request{type}, initial queue len: $qlen" . ($prio ? ", prio" : "");
    Log3 $name, 5, "$name: AddToQueue " . ($prio ? "prepends " : "adds ") . 
            "type $request{type} to " .
            "URL $request{url}, " .
            ($request{data} ? "data $request{data}, " : "no data, ") .
            ($request{header} ? "header $request{header}, " : "no headers, ") .
            ($request{ignoreredirects} ? "ignore redirects, " : "") .
            "retry $count";
    if(!$qlen) {
        $hash->{QUEUE} = [ \%request ];
    } else {
        if ($qlen > AttrVal($name, "queueMax", 20)) {
            Log3 $name, 3, "$name: AddToQueue - send queue too long ($qlen), dropping request ($type), BUSY = $hash->{BUSY}";
        } else {
            if ($prio) {
                unshift (@{$hash->{QUEUE}}, \%request); # an den Anfang
            } else {
                push(@{$hash->{QUEUE}}, \%request);     # ans Ende
            }
        }
    }
    HTTPMOD_HandleSendQueue("direct:".$name) if (!$prio);   # if prio is set, wait until all steps are added to the front - Auth will call HandleSendQueue then.
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
        and <code>attr readingXRegex</code> should be preferred.
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
            attr PM reading03Name3TEMP<br>
            attr PM reading03Regex 34.4033.value":[ \t]+"([\d\.]+)"<br>
            <br>
            attr PM requestData {"get" :["34.4001.value" ,"34.4008.value" ,"34.4033.value", "14.16601.value", "14.16602.value"]}<br>
            attr PM requestHeader1 Content-Type: application/json<br>
            attr PM requestHeader2 Accept: */*<br>
            <br>
            attr PM stateFormat {sprintf("%.1f Grad, PH %.1f, %.1f mg/l Chlor", ReadingsVal($name,"TEMP",0), ReadingsVal($name,"PH",0), ReadingsVal($name,"CL",0))}<br>
        </code></ul>
        <br>
        The regular expressions used will take the value that matches a capture group. This is the part of the regular expression inside ().
        In the above example "([\d\.]+)" refers to numerical digits or points between double quotation marks. Only the string consiting of digits and points 
        will match inside (). This piece is assigned to the reading.
        
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
            attr test2 extractAllJSON
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
            attr test2 get01ExtractAllJSON
        </ul></code>
        which would only apply to all data read as response to the get command defined as get01.        

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
        HTTPMOD has two built in replacements: one for values passed to a set or get command and the other one for the session id.<br>
        Before a request is sent, the placeholder $val is replaced with the value that is passed in a set command or an optional value that can be passed in a get command (see getXTextArg). This value is internally stored in the internal "value" so it can also be used in a user defined replacement as explaind in this section.<br>
        The other built in replacement is for the session id. If a session id is extracted via a regex, JSON or XPath the it is stored in the internal "sid" and the placeholder $sid in a URL, header or post data is replaced by the content of thus internal.
        
        User defined replacement can exted this functionality and this might be needed to pass further variables to a server, a current date or other things. <br>
        To support this HTTPMOD offers user defined replacements that are as well applied to a request before it is sent to the server.
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
        The mode <code>key</code> will use a value from a key / value pair that is stored in an obfuscated form in the file system with the set storeKeyValue command. This might be useful for storing passwords.<br>
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
        reading values should be replaced. MaxAgeReplacementMode can be <code>text</code>, <code>expression</code> or <code>delete</code>. <br>
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
            the name of a reading to extract with the corresponding readingRegex, readingJSON, readingXPath or readingXPath-Strict<br>
            Please note that the old syntax <b>readingsName.*</b> does not work with all features of HTTPMOD and should be avoided. It might go away in a future version of HTTPMOD.
        <li><b>(get|set)[0-9]+Name</b></li>
            Name of a get or set command to be defined. If the HTTP response that is received after the command is parsed with an individual parse option then this name is also used as a reading name. Please note that no individual parsing needs to be defined for a get or set. If no regex, XPath or JSON is specified for the command, then HTTPMOD will try to parse the response using all the defined readingRegex, reading XPath or readingJSON attributes.
            
        <li><b>(get|set|reading)[0-9]+Regex</b></li>
            If this attribute is specified, the Regex defined here is used to extract the value from the HTTP Response 
            and assign it to a Reading with the name defined in the (get|set|reading)[0-9]+Name attribute.<br>
            If this attribute is not specified for an individual Reading or get or set but without the numbers in the middle, e.g. as getRegex or readingRegex, then it applies to all the other readings / get / set commands where no specific Regex is defined.<br>
            The value to extract should be in a capture group / sub expression e.g. ([\d\.]+) in the above example. 
            Multiple capture groups will create multiple readings (see explanation above)<br>
            Using this attribute for a set command (setXXRegex) only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
            Please note that the old syntax <b>readingsRegex.*</b> does not work with all features of HTTPMOD and should be avoided. It might go away in a future version of HTTPMOD.
            If for get or set commands neither a generic Regex attribute without numbers nor a specific (get|set)[0-9]+Regex attribute is specified and also no XPath or JSON parsing specification is given for the get or set command, then HTTPMOD tries to use the parsing definitions for general readings defined in reading[0-9]+Name, reading[0-9]+Regex or XPath or JSON attributes and assigns the Readings that match here.
        <li><b>(get|set|reading)[0-9]+RegOpt</b></li>
            Lets the user specify regular expression modifiers. For example if the same regular expression should be matched as often as possible in the HTTP response, 
            then you can specify RegOpt g which will case the matching to be done as /regex/g<br>
            The results will be trated the same way as multiple capture groups so the reading name will be extended with -number. 
            For other possible regular expression modifiers see http://perldoc.perl.org/perlre.html#Modifiers
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
            defines an encoding to be used in a call to the perl function encode to convert the raw data string read from the device to a reading. 
            This can be used if the device delivers strings in an encoding like cp850 and after decoding it you want to reencode it to e.g. utf8.
            If your reading values contain Umlauts and they are shown as strange looking icons then you probably need to use this feature.
            Using this attribute for a set command only makes sense if you want to parse the HTTP response to the HTTP request that the set command sent by defining the attribute setXXParseResponse.<br>
        <br>
            
        <li><b>(get|set)[0-9]*URL</b></li>
            URL to be requested for the get or set command. 
            If this option is missing, the URL specified during define will be used.
        <li><b>(get|set)[0-9]*Data</b></li>
            optional data to be sent to the device as POST data when the get oer set command is executed. 
            if this attribute is specified, an HTTP POST method will be sent instead of an HTTP GET
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
        <br>

        <li><b>(get|set)[0-9]*URLExpr</b></li>
            Defines a Perl expression to specify the HTTP Headers for this request. This overwrites any other header specification and should be used carefully only if needed. The original Header is availabe as $old. Typically this feature is not needed and it might go away in future versions of HTTPMOD. Please use the "replacement" attributes if you want to pass additional variable data to a web service. 
        <li><b>(get|set)[0-9]*DatExpr</b></li>
            Defines a Perl expression to specify the HTTP Post data for this request. This overwrites any other post data specification and should be used carefully only if needed. The original Data is availabe as $old. Typically this feature is not needed and it might go away in future versions of HTTPMOD. Please use the "replacement" attributes if you want to pass additional variable data to a web service. 
        <li><b>(get|set)[0-9]*HdrExpr</b></li>
            Defines a Perl expression to specify the URL for this request. This overwrites any other URL specification and should be used carefully only if needed. The original URL is availabe as $old. Typically this feature is not needed and it might go away in future versions of HTTPMOD. Please use the "replacement" attributes if you want to pass additional variable data to a web service.           
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
            If set to 1 this attribute causes certain readings to be deleted when the parsing of the website does not match the specified reading. Internally HTTPMOD remembers which kind of operation created a reading (update, Get01, Get02 and so on). Specified readings will only be deleted if the same operation does not parse this reading again. This is especially useful for parsing that creates several matches / readings and this number of matches can vary from request to request. For example if reading01Regex creates 4 readings in one update cycle and in the next cycle it only matches two times then the readings containing the remaining values from the last round will be deleted.<br>
            Please note that this mechanism will not work in all cases after a restart. Especially when a get definition does not contain its own parsing definition but ExtractAllJSON or relies on HTTPMOD to use all defined reading.* attributes to parse the responsee to a get command, old readings might not be deleted after a restart of fhem.
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
            enables the built in set commands interval, stop, start, reread, upgradeAttributes, storeKeyValue.
        <li><b>enableCookies</b></li>
            enables the built cookie handling if set to 1. With cookie handling each HTTPMOD device will remember cookies that the server sets and send them back to the server in the following requests. 
            This simplifies session magamenet in cases where the server uses a session ID in a cookie. In such cases enabling Cookies should be sufficient and no sidRegex and no manual definition of a Cookie Header should be necessary.
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
            
        <li><b>handleRedirects</b></li>
            enables redirect handling inside HTTPMOD. This makes complex session establishment where the HTTP responses contain a series of redirects much easier. If enableCookies is set as well, cookies will be tracked during the redirects.
            
        <li><b>dontRequeueAfterAuth</b></li>
            prevents the original HTTP request to be added to the send queue again after the authentication steps. This might be necessary if the authentication steps will automatically get redirects to the URL originally requested. This option will likely need to be combined with sidXXParseResponse.
            
        <li><b>parseFunction1</b> and <b>parseFunction2</b></li>
            These functions allow an experienced Perl / Fhem developer to plug in his own parsing functions.<br>
            Please look into the module source to see how it works and don't use them if you are not sure what you are doing.
        <li><b>preProcessRegex</b></li>
            can be used to fix a broken HTTP response before parsing. The regex should be a replacement regex like s/match/replacement/g and will be applied to the buffer.

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
