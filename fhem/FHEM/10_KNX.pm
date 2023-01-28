## no critic (Modules::RequireVersionVar) ######################################
# $Id$  
################################################################################
### changelog:
# ABU 20180218 restructuring, removed older documentation
# MH  20210908 deleted part of change history
# ABU 20181007 fixed dpt19
# HAUSWART 20201112 implemented DPT20.102 #91462, KNX_parse set & get #115122, corrected dpt1 / dpt1.001 #112538
# HAUSWART 20201113 fixed dpt19 #91650, KNX_hexToName2
# MH  20201122 reworked most of dpt1, added dpt6.010, reworked dpt19, fixed (hopefully) putCmd, corrcetions to docu
# MH  20201202 dpt10 compatibility with widgetoverride :time, docu formatting
# MH  20201207 improve code (PerlBestPractices) changes marked with #PBP, added x-flag to most of regex, fixed dpt16 
# MH  20201210 add docu example for dpt16, fix docu indent.
# MH  20201223 add Evolution-version string, add dpt2.000 (JoeALLb), correction to "unknow argument..."  
#              new attr disable, simplify set-cmd logic, removed 'use SetExtensions', rework DbLogsplit logic 
# MH  20210110 E04.20 rework / simplify set and define subs. No functional changes, i hope...
#              PBP /perlcritic: now down to 12 Lines (from original 425) on package main Level 3,
#              most of them 'cascading if-elsif chain' or 'high complexity score's. 
#              Still one severity 5, don't know how to fix that one.
# MH  20210210 E04.40 reworked dpt3 en- de-code, added disable also for KNX_parse,
#              reworked set & parse -> new sub KNX_SetReading 
#              fix dpt16 empty string / full string length
#              autocreate: new devices will be default disabled during autocreate! - see cmdref
#              the Log msg "Unknown code xxxxx please help me" cannot be suppressed, would require a change in TUL/KNXTUL Module
#              "set xxx (on|off)-until hh:mm"  now works like "at xxx on-till-overnight hh:mm" 
#              fixed toggle (current value)
#              additional PBP/perlcritic fixes
#              fixed ugly bug when doing defmod or copy (defptr not cleared!)
# MH  20210211 E04.41 quick fix readingnames (gammatwin)
# MH  20210218 E04.42 cleanup, change dpts: 6,8,13 en-/de-code, fixed $PAT_DATE,
#              readings: a write from bus updates always the "get" reading, indepedend of option set !!!
#              add KNX_toggle Attr  & docu 
# MH  20210225 E04.43 fix autocreate- unknown code..., defptr
#              cmdref: changed <a name= to <a id=
# MH  20210515 E04.60 fix IsDisabled when state = inactive
#              cleanup, replaced ok-dialog on get-cmd by "err-msg"
#              docu correction
#              fixed KNX_replaceByRegex
#              replace eval by AnalyzePerlCommand 
#              added FingerPrintFn, fix DbLog_split  
# MH  20210521 E04.62 DbLog_split replace regex by looks_like_number
#              fix readingsnames "gx:...:nosuffix"
# MH  202105xx E04.65 own Package FHEM:KNX
# MH  20210803 E04.66 remove FingerPrintFn
#              new dpt7.600, dpt9.029,dpt9.030  
# MH  20210818 E04.67 1st checkin SVN version
#              docu correction
# MH  20210829 fix crash when using Attr KNX_toogle & on-until (related to package)
# MH  20211002 E04.68 IODev specification on define is now deprecated 
#              check for valid IO-Module during IODev-Attr definition 
#              changed policy on forbidden GADNames e.g.: onConnect is now allowed
#              removed "private" eversion 
#              removed unnecessary "return $UNDEF"
#              removed sub KNX_Notify - not needed!  
#              fixed "old syntax" dpt16 set Forum #122779
#              modified examples in cmdref - added wiki link
#              prevent deletion of Attr disable until a valid dpt is defined
#              changed AnalyzePerlCommand to AnalyzeCommandChain to allow multiple fhem cmds in eval's
#              code cleanup
# MH 20211013  E04.72 fix dpt1.004, .011, .012, .018 encoding
#              remove 'return undef' from initialize & defineFn 
#              fix stateregex (KNX_replacebyregex)		
#              fix off-for-timer
#              add wiki links
#              add blink cmd for dpt1, dpt1.001
# MH 20211017  E04.80 rework decode- encode- ByDpt (cascading if/else != performance)
#              fix stateregex once more
#              removed examples from cmdref -> wiki
# MH 20211118  E04.90 fix dpt10 now, fix dpt19 workingdays
#              fix dpt3 encode
# MH 20220107  E05.00 feature: add support for FHEM2FHEM as IO-Device
#              E05.01 feature: utitity KNX_scan
#              corrections cmd-ref
#              optimize replaceByRegex
# MH 20220108  fix KNX_scan sub (export-problem)
# MH 202201xx  E05.02 fix dpt14 "0"
#              avoid undefined event when autocreate ignoreTypes is set
# MH 20220313  fix dpt20_decode
#              new dpt22.101 receive only
#              changed unit encoding to UTF8 eg: dpt9.030 from: &mu;g/m&sup3; to: µg/m³
# MH 20220403  allow 'nosuffix' as only option in define 
#              minor corrections to cmdref
# MH 20220429  minor additions to cmdref & some cleanup
# MH 20221019  cleanup, replace doubleqoutes in Log3, sprintf,pack,....
#              add devicename to every Log msg 
#              rework doKNXscan, stateregex
#              add dpt4, dpt15, added sub-dpts for dpts 3,5,8,9,14; corrected min/max/pattern values in dpts
#              fix dpt19, dpt11 parsing
#              unify Log-Msg's
#              prevent setting deprecated (since 2018!) Attr: readonly,listenonly,slider - with errormsg
#              prevent setting IODev in define...
#              .... both will be completly removed with next version
#              new: Internal "RAWMSG" shows msg from Bus while device is disabled (debugging)
#              bugfix: allowed group-format corrected: was 0-31/0-15/0-255 -> now: 0-31/0-7/0-255 lt.KNX-spec
# MH 202210xx  changed package name FHEM::KNX -> KNX
#              changed svnid format 
#              fix dpt4,dpt16 encode/decode (ascii vs. ISO-8859-1)
#              fix dpt14.057 unit 'dpt14.057' { cos&phi; vs. cosφ ) =>need UTF8 in DbLog spec !
#              new dpt217 - for EBUSD KNX implementation
#              no default slider in FHEMWEB-set/get for dpt7,8,9,12,13 - use widgetoverride slider !
# MH 20221113  cleanup, cmdref formatting  
# MH 202212xx  fix dpt217 range/fomatting, cmd-ref links,
#              remove support for IODev in define
#              modify disabled logic
# MH 20221226  device define after init_complete
#              remove $hash->{DEVNAME}
#              modify autocreate, get/set logic
#              changed not user relevant internals to {.XXXX}
#              changed DbLog_split function
#              disabled StateFn
# MH 20230104  change pattern matching for dpt1 and dptxxx
#              fix DbLogSplitFn
# MH 20230124  simplify DbLogSplitFn
#              modify parsing of gadargs in define
#              modify KNX_parse - reply msg code
#              modify KNX_set
#              add pulldown menu for attr IODev with vaild IO-devs
#              KNX_scan now avail also from cmd-line
# MH 20220129  PBP changes /ms flag
#              syntax check on attr stateCmd & putCmd
#              fix define parsing


package KNX; ## no critic 'package'

use strict;
use warnings;
use Encode qw(encode decode);
use Time::HiRes qw(gettimeofday);
use Scalar::Util qw(looks_like_number);
use GPUtils qw(GP_Import GP_Export); # Package Helper Fn

### perlcritic parameters
# these ones are NOT used! (constants,Policy::Modules::RequireFilenameMatchesPackage,NamingConventions::Capitalization)
# these ones are NOT used! (ControlStructures::ProhibitCascadingIfElse)
# these ones are NOT used! (RegularExpressions::RequireDotMatchAnything,RegularExpressions::RequireLineBoundaryMatching)
### the following percritic items will be ignored global ###
## no critic (ValuesAndExpressions::RequireNumberSeparators,ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (ControlStructures::ProhibitPostfixControls)
## no critic (Documentation::RequirePodSections)

### import FHEM functions / global vars
### run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate readingsBulkUpdate readingsBulkUpdateIfChanged
          readingsBeginUpdate readingsEndUpdate
          Log3
          AttrVal InternalVal ReadingsVal ReadingsNum
          addToDevAttrList
          AssignIoPort IOWrite
          CommandDefMod CommandModify CommandDelete
          defs modules attr cmds
          perlSyntaxCheck
          FW_detail FW_wname FW_directNotify
          readingFnAttributes
          InternalTimer RemoveInternalTimer
          GetTimeSpec
          init_done
          IsDisabled IsDummy IsDevice
          deviceEvents devspec2array
          AnalyzePerlCommand AnalyzeCommandChain EvalSpecials
          fhemTimeLocal)
    );
}
# export to main context
GP_Export( qw(Initialize) );

#string constants
my $MODELERR    = 'MODEL_NOT_DEFINED'; # for autocreate

my $BLINK       = 'blink';
my $TOGGLE      = 'toggle';
my $RAW         = 'raw';
my $RGB         = 'rgb';
my $STRING      = 'string';
my $VALUE       = 'value';

my $TULid       = 'C'; #identifier for KNX - extended adressing
my $svnid       = '$Id$';

#regex patterns
#pattern for group-adress
my $PAT_GAD = '(?:3[01]|([012])?[0-9])\/(?:[0-7])\/(?:2[0-4][0-9]|25[0-5]|([01])?[0-9]{1,2})'; # 0-31/0-7/0-255
#pattern for group-adress in hex-format
my $PAT_GAD_HEX = '[01][0-9a-f][0-7][0-9a-f]{2}'; # max is 1F7FF -> 31/7/255 5 digits
#pattern for group-no
my $PAT_GNO = '[gG][1-9][0-9]?';
#pattern for GAD-Options
my $PAT_GAD_OPTIONS = 'get|set|listenonly'; 
#pattern for GAD-suffixes
my $PAT_GAD_SUFFIX = 'nosuffix';
#pattern for forbidden GAD-Names
my $PAT_GAD_NONAME = '^(on|off|value|raw|' . $PAT_GAD_OPTIONS . q{|} . $PAT_GAD_SUFFIX . ')';
#pattern for DPT
my $PAT_GAD_DPT = 'dpt\d+\.?\d*';
#pattern for dpt1 (standard)
my $PAT_DPT1_PAT = 'on|off|[01]$';
#pattern for date
my $PAT_DTSEP  = qr/(?:_)/ixms; # date/time separator
my $PAT_DATEdm = qr/^(3[01]|[1-2][0-9]|0?[1-9])\.(1[0-2]|0?[1-9])/ixms; # day/month
my $PAT_DATE   = qr/$PAT_DATEdm\.((?:19|20|21)[0-9]{2})/ixms; # dpt19 year range: 1900-2155 ! 
my $PAT_DATE2  = qr/$PAT_DATEdm\.(199[0-9]|20[0-8][0-9])/ixms; # dpt11 year range: 1990-2089 !
#pattern for time
my $PAT_TIME = qr/(2[0-4]|[01]{0,1}[0-9]):([0-5]{0,1}[0-9]):([0-5]{0,1}[0-9])/ixms;
my $PAT_DPT16_CLR = qr/>CLR</ixms;

#CODE is the identifier for the en- and decode algos. See encode and decode functions
#UNIT is appended to state for a better reading
#FACTOR and OFFSET are used to normalize a value. value = FACTOR * (RAW - OFFSET). Must be undef for non-numeric values.
#PATTERN is used to check an trim the input-values
#MIN and MAX are used to cast numeric values. Must be undef for non-numeric dpt. Special Usecase: DPT1 - MIN represents 00, MAX represents 01
#if supplied, setlist is passed directly to fhemweb in order to show comand-buttons in the details-view (e.g. "colorpicker" or "item1,item2,item3")
#if setlist is not supplied and min/max are given, a slider is shown for numeric values. Otherwise min/max value are shown in a list
my %dpttypes = (
	#Binary value
	'dpt1'          => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ixms, MIN=>'off', MAX=>'on', SETLIST=>'on,off,toggle',
                            DEC=>\&dec_dpt1,ENC=>\&enc_dpt1,},
	'dpt1.000'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ixms, MIN=>0, MAX=>1, SETLIST=>'0,1'},
	'dpt1.001'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ixms, MIN=>'off', MAX=>'on', SETLIST=>'on,off,toggle'},
	'dpt1.002'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|true|false)/ixms, MIN=>'false', MAX=>'true'},
	'dpt1.003'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|enable|disable)/ixms, MIN=>'disable', MAX=>'enable'},
	'dpt1.004'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_ramp|ramp)/ixms, MIN=>'no_ramp', MAX=>'ramp'},
	'dpt1.005'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_alarm|alarm)/ixms, MIN=>'no_alarm', MAX=>'alarm'},
	'dpt1.006'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|low|high)/ixms, MIN=>'low', MAX=>'high'},
	'dpt1.007'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|decrease|increase)/ixms, MIN=>'decrease', MAX=>'increase'},
	'dpt1.008'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|up|down)/ixms, MIN=>'up', MAX=>'down'},
	'dpt1.009'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|closed|open)/ixms, MIN=>'open', MAX=>'closed'},
	'dpt1.010'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|start|stop)/ixms, MIN=>'stop', MAX=>'start'},
	'dpt1.011'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|inactive|active)/ixms, MIN=>'inactive', MAX=>'active'},
	'dpt1.012'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|not_inverted|inverted)/ixms, MIN=>'not_inverted', MAX=>'inverted'},
	'dpt1.013'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|start_stop|cyclically)/ixms, MIN=>'start_stop', MAX=>'cyclically'},
	'dpt1.014'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|fixed|calculated)/ixms, MIN=>'fixed', MAX=>'calculated'},
	'dpt1.015'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_action|reset)/ixms, MIN=>'no_action', MAX=>'reset'},
	'dpt1.016'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_action|acknowledge)/ixms, MIN=>'no_action', MAX=>'acknowledge'},
	'dpt1.017'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|trigger_0|trigger_1)/ixms, MIN=>'trigger_0', MAX=>'trigger_1', SETLIST=>'trigger_0,trigger_1',},
	'dpt1.018'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|not_occupied|occupied)/ixms, MIN=>'not_occupied', MAX=>'occupied'},
	'dpt1.019'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|closed|open)/ixms, MIN=>'closed', MAX=>'open'},
	'dpt1.021'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|logical_or|logical_and)/ixms, MIN=>'logical_or', MAX=>'logical_and'},
	'dpt1.022'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|scene_A|scene_B)/ixms, MIN=>'scene_A', MAX=>'scene_B'},
	'dpt1.023'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|move_(up_down|and_step_mode))/ixms, MIN=>'move_up_down', MAX=>'move_and_step_mode'},

	#Step value (two-bit)
	'dpt2'          => {CODE=>'dpt2', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(on|off|forceon|forceoff)/ixms, MIN=>undef, MAX=>undef, SETLIST=>'on,off,forceon,forceoff',
                            DEC=>\&dec_dpt2,ENC=>\&enc_dpt2,},
	'dpt2.000'      => {CODE=>'dpt2', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/(0?[0-3])/ixms, MIN=>0, MAX=>3, SETLIST=>'0,1,2,3'},

	#Step value (four-bit)
	'dpt3'          => {CODE=>'dpt3', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>-100, MAX=>100,
                            DEC=>\&dec_dpt3,ENC=>\&enc_dpt3,},
	'dpt3.007'      => {CODE=>'dpt3', UNIT=>q{%}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>-100, MAX=>100},
	'dpt3.008'      => {CODE=>'dpt3', UNIT=>q{%}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>-100, MAX=>100},

	#single ascii/iso-8859-1 char
	'dpt4'          => {CODE=>'dpt4', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[[:ascii:]]/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt16,ENC=>\&enc_dpt4,},
	'dpt4.001'      => {CODE=>'dpt4', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[[:ascii:]]/ixms, MIN=>undef, MAX=>undef}, # ascii
	'dpt4.002'      => {CODE=>'dpt4', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[\x20-\xFF].*/ixms, MIN=>undef, MAX=>undef}, # iso-8859-1

	# 1-Octet unsigned value
	'dpt5'          => {CODE=>'dpt5', UNIT=>q{},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>255,
                            DEC=>\&dec_dpt5,ENC=>\&enc_dpt5,},
	'dpt5.001'      => {CODE=>'dpt5', UNIT=>q{%}, FACTOR=>100/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>100},  
	'dpt5.003'      => {CODE=>'dpt5', UNIT=>q{°}, FACTOR=>360/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>360},
	'dpt5.004'      => {CODE=>'dpt5', UNIT=>q{%}, FACTOR=>1,       OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>255},
	'dpt5.010'      => {CODE=>'dpt5', UNIT=>q{p}, FACTOR=>1,       OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>255}, # counter pulses

	# 1-Octet signed value
	'dpt6'          => {CODE=>'dpt6', UNIT=>q{},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>-128, MAX=>127,
                            DEC=>\&dec_dpt6,ENC=>\&enc_dpt6,},
	'dpt6.001'      => {CODE=>'dpt6', UNIT=>q{%}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>100},
	'dpt6.010'      => {CODE=>'dpt6', UNIT=>q{},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>-128, MAX=>127},

	# 2-Octet unsigned Value 
	'dpt7'          => {CODE=>'dpt7', UNIT=>q{},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535,
                            DEC=>\&dec_dpt7,ENC=>\&enc_dpt7,},
	'dpt7.001'      => {CODE=>'dpt7', UNIT=>q{},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535},
	'dpt7.005'      => {CODE=>'dpt7', UNIT=>q{s},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535},
	'dpt7.006'      => {CODE=>'dpt7', UNIT=>q{m},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535},
	'dpt7.007'      => {CODE=>'dpt7', UNIT=>q{h},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535},
	'dpt7.012'      => {CODE=>'dpt7', UNIT=>q{mA},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535},
	'dpt7.013'      => {CODE=>'dpt7', UNIT=>q{lux}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>0, MAX=>65535},
	'dpt7.600'      => {CODE=>'dpt7', UNIT=>q{K},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+]?\d{1,5}/ixms,  MIN=>0, MAX=>12000},  # Farbtemperatur

	# 2-Octet signed Value 
	'dpt8'          => {CODE=>'dpt8', UNIT=>q{},      FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-32768, MAX=>32767,
                            DEC=>\&dec_dpt8,ENC=>\&enc_dpt8,},
	'dpt8.001'      => {CODE=>'dpt8', UNIT=>q{p},     FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-32768, MAX=>32767},
	'dpt8.003'      => {CODE=>'dpt8', UNIT=>q{s},     FACTOR=>0.01, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-327.68, MAX=>327.67},
	'dpt8.004'      => {CODE=>'dpt8', UNIT=>q{s},     FACTOR=>0.1,  OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-3276.8, MAX=>3276.7},
	'dpt8.005'      => {CODE=>'dpt8', UNIT=>q{s},     FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-32768, MAX=>32767},
	'dpt8.006'      => {CODE=>'dpt8', UNIT=>q{min},   FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-32768, MAX=>32767},
	'dpt8.007'      => {CODE=>'dpt8', UNIT=>q{h},     FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-32768, MAX=>32767},
	'dpt8.010'      => {CODE=>'dpt8', UNIT=>q{%},     FACTOR=>0.01, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-327.68, MAX=>327.67}, # min/max
	'dpt8.011'      => {CODE=>'dpt8', UNIT=>q{°},     FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ixms, MIN=>-32768, MAX=>32767},

	# 2-Octet Float value
	'dpt9'          => {CODE=>'dpt9', UNIT=>q{},     FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760,
                            DEC=>\&dec_dpt9,ENC=>\&enc_dpt9,},
	'dpt9.001'      => {CODE=>'dpt9', UNIT=>q{°C},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-274, MAX=>670760},
	'dpt9.002'      => {CODE=>'dpt9', UNIT=>q{K},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.003'      => {CODE=>'dpt9', UNIT=>q{K/h},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.004'      => {CODE=>'dpt9', UNIT=>q{lux},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>0, MAX=>670760},
	'dpt9.005'      => {CODE=>'dpt9', UNIT=>q{m/s},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>0, MAX=>670760},
	'dpt9.006'      => {CODE=>'dpt9', UNIT=>q{Pa},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>0, MAX=>670760},
	'dpt9.007'      => {CODE=>'dpt9', UNIT=>q{%},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>0, MAX=>670760},
	'dpt9.008'      => {CODE=>'dpt9', UNIT=>q{ppm},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>0, MAX=>670760},
	'dpt9.009'      => {CODE=>'dpt9', UNIT=>q{m³/h}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.010'      => {CODE=>'dpt9', UNIT=>q{s},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.011'      => {CODE=>'dpt9', UNIT=>q{ms},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.020'      => {CODE=>'dpt9', UNIT=>q{mV},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.021'      => {CODE=>'dpt9', UNIT=>q{mA},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.022'      => {CODE=>'dpt9', UNIT=>q{W/m²}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.023'      => {CODE=>'dpt9', UNIT=>q{K/%},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.024'      => {CODE=>'dpt9', UNIT=>q{kW},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.025'      => {CODE=>'dpt9', UNIT=>q{l/h},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.026'      => {CODE=>'dpt9', UNIT=>q{l/h},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760},
	'dpt9.027'      => {CODE=>'dpt9', UNIT=>q{°F},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-459.6, MAX=>670760},
	'dpt9.028'      => {CODE=>'dpt9', UNIT=>q{km/h}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>0, MAX=>670760},
	'dpt9.029'      => {CODE=>'dpt9', UNIT=>q{g/m³}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760}, # Abs. Luftfeuchte
	'dpt9.030'      => {CODE=>'dpt9', UNIT=>q{µg/m³}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>-670760, MAX=>670760}, # Dichte

	# Time of Day
	'dpt10'         => {CODE=>'dpt10', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_TIME|now)/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt10,ENC=>\&enc_dpt10,},

	# Date  
	'dpt11'         => {CODE=>'dpt11', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DATE2|now)/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt11,ENC=>\&enc_dpt11,}, # year range 1990-2089 !

	# 4-Octet unsigned value (handled as dpt7)
	'dpt12'         => {CODE=>'dpt12', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ixms, MIN=>0, MAX=>4294967295,
                            DEC=>\&dec_dpt12,ENC=>\&enc_dpt12,},

	# 4-Octet Signed Value
	'dpt13'         => {CODE=>'dpt13', UNIT=>q{},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ixms, MIN=>-2147483648, MAX=>2147483647,
                            DEC=>\&dec_dpt13,ENC=>\&enc_dpt13,},
	'dpt13.010'     => {CODE=>'dpt13', UNIT=>q{Wh},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ixms, MIN=>-2147483648, MAX=>2147483647},
	'dpt13.013'     => {CODE=>'dpt13', UNIT=>q{kWh}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ixms, MIN=>-2147483648, MAX=>2147483647},

	# 4-Octet single precision float
	'dpt14'         => {CODE=>'dpt14', UNIT=>q{},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt14,ENC=>\&enc_dpt14,},
	'dpt14.007'     => {CODE=>'dpt14', UNIT=>q{p},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef}, # counter pulses
	'dpt14.019'     => {CODE=>'dpt14', UNIT=>q{A},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.027'     => {CODE=>'dpt14', UNIT=>q{V},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.033'     => {CODE=>'dpt14', UNIT=>q{Hz}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.039'     => {CODE=>'dpt14', UNIT=>q{m},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.056'     => {CODE=>'dpt14', UNIT=>q{W},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.068'     => {CODE=>'dpt14', UNIT=>q{°C}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.076'     => {CODE=>'dpt14', UNIT=>q{m³}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
	'dpt14.057'     => {CODE=>'dpt14', UNIT=>q{cosφ}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},
#	'dpt14.057'     => {CODE=>'dpt14', UNIT=>q{cos&phi;}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ixms, MIN=>undef, MAX=>undef},

	# Access data - receive only
	'dpt15'         => {CODE=>'dpt15', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/noset/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt15,},
	'dpt15.000'     => {CODE=>'dpt15', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/noset/ixms, MIN=>undef, MAX=>undef},

	# 14-Octet String
	'dpt16'         => {CODE=>'dpt16', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/ixms, MIN=>undef, MAX=>undef, SETLIST=>'multiple,>CLR<',
                            DEC=>\&dec_dpt16,ENC=>\&enc_dpt16,},
	'dpt16.000'     => {CODE=>'dpt16', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/ixms, MIN=>undef, MAX=>undef, SETLIST=>'multiple,>CLR<'},
	'dpt16.001'     => {CODE=>'dpt16', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/ixms, MIN=>undef, MAX=>undef, SETLIST=>'multiple,>CLR<'},

	# Scene, 0-63
	'dpt17'         => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>63,
                            DEC=>\&dec_dpt5,ENC=>\&enc_dpt5,},
	'dpt17.001'     => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>0, MAX=>63},

	# Scene, 1-64
	'dpt18'         => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>1, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>1, MAX=>64,
                            DEC=>\&dec_dpt5,ENC=>\&enc_dpt5,},
	'dpt18.001'     => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>1, PATTERN=>qr/[+-]?\d{1,3}/ixms, MIN=>1, MAX=>64},
	
	#date and time
	'dpt19'         => {CODE=>'dpt19', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DATE$PAT_DTSEP$PAT_TIME|now)/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt19,ENC=>\&enc_dpt19,},
	'dpt19.001'     => {CODE=>'dpt19', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DATE$PAT_DTSEP$PAT_TIME|now)/ixms, MIN=>undef, MAX=>undef},

	# HVAC mode, 1Byte
	'dpt20'         => {CODE=>'dpt20', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/(auto|comfort|standby|(economy|night)|(protection|frost|heat))/ixms, MIN=>undef, MAX=>undef, ## no critic (RegularExpressions::ProhibitComplexRegexes)
                            SETLIST=>'Auto,Comfort,Standby,Economy,Protection', DEC=>\&dec_dpt20,ENC=>\&enc_dpt20,},
	'dpt20.102'     => {CODE=>'dpt20', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/(auto|comfort|standby|(economy|night)|(protection|frost|heat))/ixms, MIN=>undef, MAX=>undef, ## no critic (RegularExpressions::ProhibitComplexRegexes)
                            SETLIST=>'Auto,Comfort,Standby,Economy,Protection'},

	# HVAC mode RHCC Status, 2Byte - receive only!!!
	'dpt22'         => {CODE=>'dpt22', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/noset/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt22,},
	'dpt22.101'     => {CODE=>'dpt22', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/noset/ixms, MIN=>undef, MAX=>undef},

	# Version Info - receive only!!! for EBUSD KNX implementation
	'dpt217'        => {CODE=>'dpt217', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/\d+\.\d+\.\d+/ixms, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt217,},
	'dpt217.001'    => {CODE=>'dpt217', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/\d+\.\d+\.\d+/ixms, MIN=>undef, MAX=>undef},

	# Color-Code
	'dpt232'        => {CODE=>'dpt232', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[0-9a-f]{6}/ixms, MIN=>undef, MAX=>undef, SETLIST=>'colorpicker',
                            DEC=>\&dec_dpt232,ENC=>\&enc_dpt232,}
);

#Init this device
#This declares the interface to fhem
#############################
sub Initialize {
	my $hash = shift // return;

	$hash->{Match}          = "^$TULid.*";
	$hash->{DefFn}          = \&KNX_Define;
	$hash->{UndefFn}        = \&KNX_Undef;
	$hash->{SetFn}          = \&KNX_Set;
	$hash->{GetFn}          = \&KNX_Get;
	$hash->{StateFn}        = \&KNX_State;
	$hash->{ParseFn}        = \&KNX_Parse;
	$hash->{AttrFn}         = \&KNX_Attr;
	$hash->{DbLog_splitFn}  = \&KNX_DbLog_split;

	$hash->{AttrList} = 'IODev ' .    #define IO-Device to communicate with. Deprecated at definition line.
           'disable:1 ' .                 #device disabled 
           'showtime:1,0 ' .              #shows time instead of received value in state
           'answerReading:1,0 ' .         #allows FHEM to answer a read telegram
           'stateRegex:textField-long ' . #modifies state value
           'stateCmd:textField-long ' .   #modify state value
           'putCmd:textField-long ' .     #called when the KNX bus asks for a -put reading
           'format ' .                    #supplies post-string
           'KNX_toggle:textField ' .      #toggle source <device>:<reading>
           'listenonly:1,0 ' .            #DEPRECATED
           'readonly:1,0 ' .              #DEPRECATED
           'slider ' .                    #DEPRECATED
           "$readingFnAttributes ";       #standard attributes
	$hash->{noAutocreatedFilelog} = 1; # autocreate devices create no FileLog
	$hash->{AutoCreate} = {'KNX_.*'  => { ATTR => 'disable:1'} }; #autocreate devices are disabled by default

	# register KNX_scan cmd (use from cmd-line)
	$cmds{KNX_scan} = { Fn  => "KNX_scancmd", Hlp => ' <devspec>, get values from KNX-devices',};

	return;
}

#Define this device
#############################
sub KNX_Define {
	my $hash = shift // return;
	my $def = shift;

	my @a = split(/[ \t\n]+/xms, $def); #enable newline within define with \
	my $name = $a[0];
	$hash->{NAME} = $name;

	$svnid =~ s/.*\.pm\s(.+)Z.*/$1/ixms;
	$hash->{'.SVN'} = $svnid; # store svn info in dev hash

	my $logtxt = qq{KNX_define ($name): }; # leading txt

	Log3 ($name, 5, $logtxt . join (q{ }, @a));

	#too less arguments or no valid 1st gad
	return ($logtxt . q{wrong syntax or wrong group-format (0-31/0-7/0-255)} . 
               qq{\n} . q{  "define <name> KNX <group:model[:GAD-name][:set|get|listenonly][:nosuffix]> } .
               q{[<group:model[:GAD-name][:set|get|listenonly][:nosuffix]>]"}) if (int(@a) < 3 || $a[2] !~ m/^(?:$PAT_GAD|$PAT_GAD_HEX)/ixms);

	# check if the last arg matches any IO-Device - and discard it !
	if ( $a[int(@a) - 1] !~ m/^(?:$PAT_GAD|$PAT_GAD_HEX)/ixms ) {
		my $iodevCandidate = pop(@a); # remove from array, but do nothing with it!
		my $logtxtIO = qq{$logtxt specifying IODev $iodevCandidate is deprecated in define } .
                               qq{- use "attr $name IODev $iodevCandidate"};
		Log3 ($name, 2, $logtxtIO);
		return $logtxtIO if ($init_done); # allow durin start
	}

	$hash->{'.DEFLINE'} = join(q{ },@a); # temp store defs for define2...
	return InternalTimer(gettimeofday() + 5.0,\&KNX_Define2,$hash) if (! $init_done);
	return KNX_Define2($hash);
}

### continue define 5 sec after init complete!
sub KNX_Define2 {
	my $hash = shift // return;

	my $name = $hash->{NAME};
	my $def  = $hash->{'.DEFLINE'};
	delete $hash->{'.DEFLINE'}; 
	my @a = split(/\s+/xms, $def);
	RemoveInternalTimer($hash);

	my $logtxt = qq{KNX_define2 ($name): }; # leading txt

	# Add pulldown for attr IODev
	my $attrList = $modules{KNX}->{AttrList}; #get Attrlist from Module def
	my $IODevs = KNX_chkIODev($hash); # get list of valid IO's
	$attrList =~ s/\bIODev\b([:]select[^\s]*)?/IODev:select,$IODevs/xms;
	$modules{KNX}->{AttrList} = $attrList;

	AssignIoPort($hash); # AssignIoPort will take device from $attr{$name}{IODev} if defined

	#reset
	$hash->{GADDETAILS} = {};
	$hash->{GADTABLE} = {};

	#delete all defptr entries for this device (defmod & copy problem)
	KNX_delete_defptr($hash); # verify with: {PrintHash($modules{KNX}->{defptr},3) }

	#create groups and models, iterate through all possible args
	foreach my $i (2 .. $#a) { 
		my $gadCode = undef;
		my $gadOption = undef;
		my $gadNoSuffix = undef;

		my $gadNo = $i - 1;
		my $gadName = 'g' . $gadNo; # old syntax

		Log3 ($name, 5, $logtxt . qq{gadNr= $gadNo def-string= $a[$i]});

		my ($gad, $gadModel, @gadArgs) = split(/:/xms, $a[$i]);
		$gadCode = $gad // return $logtxt . qq{GAD not defined for group-number $gadNo};
		return ($logtxt . qq{wrong GA format in group-number $gadNo} . 
                       ': specify as 0-31/0-7/0-255 or as hex-notation') if ($gad !~ m/^(?:$PAT_GAD|$PAT_GAD_HEX)$/ixms);

		$gad = KNX_hexToName ($gad) if ($gad =~ m/^$PAT_GAD_HEX$/ixms);
		$gadCode = KNX_nameToHex ($gad); #convert it vice-versa, just to be sure

		return ($logtxt . qq{no model defined for group-number $gadNo}) if(! defined($gadModel));

		if ($gadModel eq $MODELERR) { #within autocreate no model is supplied - throw warning
			Log3 ($name, 3, $logtxt . 'autocreate device will be disabled, correct def with valid dpt and enable device');
			$attr{$name}->{disable} = 1 if (AttrVal($name,'disable',0) != 1);
		}
		elsif (!defined($dpttypes{$gadModel})) { #check model-type
			return $logtxt . qq{invalid model: $gadModel for group-number $gadNo} . 
                               '. Please consult commandref - avaliable DPT for correct model definition.';
		}
		elsif ($gadNo == 1) { # gadModel ok
			$hash->{model} = lc($gadModel) =~ s/^(dpt[\d]+)\..*/$1/rxms; # use first gad as mdl reference for fheminfo
		}

		if (scalar(@gadArgs)) {
			$gadNoSuffix = pop(@gadArgs) if ($gadArgs[-1] =~ /$PAT_GAD_SUFFIX/ixms);
			$gadOption   = pop(@gadArgs) if (@gadArgs && $gadArgs[-1] =~ /^($PAT_GAD_OPTIONS)$/ixms);
			$gadName     = pop(@gadArgs) if (@gadArgs);

			return $logtxt . qq{forbidden gad-name: $gadName} if ($gadName =~ /$PAT_GAD_NONAME$/ixms);
			return ($logtxt . qq{invalid option for group-number $gadNo. Use one of: $PAT_GAD_OPTIONS}) if (defined($gadOption) && ($gadOption !~ m/^(?:$PAT_GAD_OPTIONS)$/ixms));
			return ($logtxt . qq{invalid suffix for group-number $gadNo. Use $PAT_GAD_SUFFIX}) if (defined($gadNoSuffix) && ($gadNoSuffix !~ m/$PAT_GAD_SUFFIX/ixms));
		}

		###GADTABLE
		#create a hash with gadCode and gadName for later mapping
		my $tableHashRef = $hash->{GADTABLE};
		#if not defined yet, define a new hash
		if (not(defined($tableHashRef))) {
			$tableHashRef={};
			$hash->{GADTABLE} = $tableHashRef;
		}

		return ($logtxt . qq{GAD $gad may be supplied only once per device.}) if (defined($hash->{GADTABLE}->{$gadCode}));

		$hash->{GADTABLE}->{$gadCode} = $gadName; #add key and value to GADTABLE

		#cache suffixes
		my ($suffixGet, $suffixSet, $suffixPut) = qw(-get -set -put);
		($suffixGet, $suffixSet, $suffixPut) = (q{},q{},q{}) if (defined($gadNoSuffix));

		# new syntax readingNames
		my $rdNameGet = $gadName . $suffixGet;
		my $rdNameSet = $gadName . $suffixSet;
		my $rdNamePut = $gadName . $suffixPut;
		if (($gadName eq 'g' . $gadNo) && (! defined($gadNoSuffix))) { # old syntax
			$rdNameGet = 'getG' . $gadNo;
			$rdNameSet = 'setG' . $gadNo;
			$rdNamePut = 'putG' . $gadNo;
		}

		my $log = $logtxt . qq{found GAD: $gad NAME: $gadName NO: $gadNo HEX: $gadCode DPT: $gadModel};
		$log .= qq{ OPTION: $gadOption} if (defined ($gadOption));
		Log3 ($name, 5, $log);

		#determine dpt-details
		my $dptDetails = $dpttypes{$gadModel};
		my $setlist = q{}; #default - #plain input field
		if (defined ($dptDetails->{SETLIST})) { # list is given, pass it through
			$setlist = q{:} . $dptDetails->{SETLIST};
		}
		elsif (defined ($dptDetails->{MIN}) && looks_like_number($dptDetails->{MIN})) { #number? - place slider
			my $min = $dptDetails->{MIN};
			my $max = $dptDetails->{MAX};
			my $interval = int(($max-$min)/100);
			$interval = 1 if ($interval == 0);
			$setlist = ':slider,' . $min . q{,} . $interval . q{,} . $max if ($interval < 50); # nonsense for dpt7,8,9,12,13
		}
		elsif (defined ($dptDetails->{MIN})) { #on/off/...
			my $min = $dptDetails->{MIN};
			my $max = $dptDetails->{MAX};
			$setlist = q{:} . $min . q{,} . $max;
		}

		Log3 ($name, 5, $logtxt . qq{Estimated reading-names: $rdNameSet , $rdNameGet , $rdNamePut});
		Log3 ($name, 5, $logtxt . qq{SetList: $setlist}) if (defined ($setlist));
		
		#add details to hash
		$hash->{GADDETAILS}->{$gadName} = {GROUP => $gad, CODE => $gadCode, MODEL => $gadModel, NO => $gadNo, OPTION => $gadOption, 
                                                  RDNAMEGET => $rdNameGet, RDNAMESET => $rdNameSet, RDNAMEPUT => $rdNamePut, SETLIST => $setlist};

		# add gadcode to module DEFPTR - used to find devicename during parse
		my @devList = ();
		#get list, if at least one GAD is installed
		@devList = @{$modules{KNX}->{defptr}->{$gadCode}} if (defined ($modules{KNX}->{defptr}->{$gadCode}));
		#push actual hash to list
		push (@devList, $hash);
		#restore list
		@{$modules{KNX}->{defptr}->{$gadCode}} = @devList;

		#create setlist for setFn / getlist will be created during get-cmd!
		my $setString = q{};
		foreach my $key (keys %{$hash->{GADDETAILS}}) {
			#no set-command for get or listenonly
			my $option = $hash->{GADDETAILS}->{$key}->{OPTION};
			if ((defined($option) && $option eq 'set') || (! defined($option))) {
					$setString .= 'on:noArg off:noArg ' if (($hash->{GADDETAILS}->{$key}->{NO} == 1) && ($hash->{GADDETAILS}->{$key}->{MODEL} =~ /^(dpt1|dpt1.001)$/xms));
					$setString .= $key . $hash->{GADDETAILS}->{$key}->{SETLIST} . q{ };
			}
		}
		$hash->{'.SETSTRING'} = $setString;

		Log3 ($name, 5, qq{$logtxt setstring= $hash->{'.SETSTRING'}});
	}

	Log3 ($name, 5, $logtxt . 'define complete');
	return;
}

#Release this device
#Is called at every delete / shutdown
#############################
sub KNX_Undef {
	my $hash = shift;
	my $name = shift;

	Log3 ($name, 5, qq{KNX_undef ($name): enter});

	#delete all defptr entries for this device
	KNX_delete_defptr($hash); # verify with: {PrintHash($modules{KNX}->{defptr},3) } on FHEM-cmdline
	return;
}

#Places a "read" Message on the KNX-Bus
#The answer is treated as regular telegram
#############################
sub KNX_Get {
	my $hash = shift;
	my $name = shift;
	my $gadName = shift // KNX_gadNameByNO($hash,1); # use first defined GAD if no argument is supplied
	
	return qq{KNX_Get ($name): gadName not defined} if (! defined($gadName));
	Log3 ($name, 3, qq{KNX_Get ($name): too much arguments. Only one argument allowed (gadName). Other Arguments are discarded.}) if (defined(shift));

	#FHEM asks with a ? at startup - no action, no log - if dev is disabled: no SET/GET pulldown !
	if ($gadName  =~ m/\?/xms) {
		my $getter = q{};
		foreach my $key (keys %{$hash->{GADDETAILS}}) {
			last if (! defined($key));
			my $option = $hash->{GADDETAILS}->{$key}->{OPTION};
			next if (defined($option) && $option =~ /(?:set|listenonly)/ixms);
			$getter .= q{ } . $key . ':noArg';
		}
		$getter =~ s/^\s+//gixms; #trim leading blank
		$getter = q{} if (IsDisabled($name) == 1);

		return qq{unknown argument $gadName choose one of $getter};
	}
	return qq{KNX_Get ($name): is disabled} if (IsDisabled($name) == 1);

	Log3 ($name, 5, qq{KNX_Get ($name): -enter: CMD= $gadName});

	#return, if unknown group
	return qq{KNX_Get ($name): invalid gadName: $gadName} if(! exists($hash->{GADDETAILS}->{$gadName}));
	#get groupCode, groupAddress, option
	my $groupc = $hash->{GADDETAILS}->{$gadName}->{CODE};
	my $group  = $hash->{GADDETAILS}->{$gadName}->{GROUP};
	my $option = $hash->{GADDETAILS}->{$gadName}->{OPTION};

	#exit if get is prohibited
	return qq{KNX_Get ($name): did not request a value - "set" or "listenonly" option is defined.} if (defined ($option) and ($option =~ m/(set|listenonly)/ixms));

	Log3 ($name, 5, qq{KNX_Get ($name): request value for GAD: $group GAD-NAME: $gadName});

	IOWrite($hash, $TULid, 'r' . $groupc); #send read-request to the bus

	FW_directNotify('#FHEMWEB:' . $FW_wname, 'FW_errmsg(" value for ' . $name . ' - ' . $group . ' requested",5000)', qq{}) if (defined($FW_wname));

	return;
}

#Does something according the given cmd...
#############################
sub KNX_Set {
	my ($hash, $name, $targetGadName, @arg) = @_;

	my @ca = caller(0); #identify this sub
	my $thisSub = $ca[3] =~ s/.+[:]+//grxms;
	$thisSub .= qq{ ($name): };

	#FHEM asks with a "?" at startup or any reload of the device-detail-view - if dev is disabled: no SET/GET pulldown !
	if(defined($targetGadName) && ($targetGadName =~ m/\?/xms)) {
		my $setter = exists($hash->{'.SETSTRING'})?$hash->{'.SETSTRING'}:q{};
		$setter = q{} if (IsDisabled($name) == 1);
		return qq{unknown argument $targetGadName choose one of $setter};
	}

	return $thisSub . 'is disabled' if (IsDisabled($name) == 1);
	return $thisSub . 'no parameter(s) specified for set cmd' if((!defined($targetGadName)) || ($targetGadName eq q{})); #return, if no cmd specified

	Log3 ($name, 5, $thisSub . qq{-enter: $targetGadName } . join(q{ }, @arg));

	$targetGadName =~ s/^\s+|\s+$//gxms; # gad-name or cmd (in old syntax)
	my $cmd = undef;

	if (defined ($hash->{GADDETAILS}->{$targetGadName})) { # #new syntax, if first arg is a valid gadName
		$cmd = shift(@arg); #shift args as with newsyntax $arg[0] is cmd
		return $thisSub . 'no cmd found' if(!defined($cmd));
	}
	else {
		(my $err, $targetGadName, $cmd) = KNX_Set_oldsyntax($hash,$targetGadName,@arg); # process old syntax targetGadName contains command!
		return $thisSub . $err if defined($err);
	}

	Log3 ($name, 5, $thisSub . qq{desired target is gad: $targetGadName , command: $cmd , args: } . join (q{ }, @arg));

	#get details
	my $groupCode = $hash->{GADDETAILS}->{$targetGadName}->{CODE};
	my $option    = $hash->{GADDETAILS}->{$targetGadName}->{OPTION};
	my $rdName    = $hash->{GADDETAILS}->{$targetGadName}->{RDNAMESET};
	my $model     = $hash->{GADDETAILS}->{$targetGadName}->{MODEL}; 

	return $thisSub . q{did not set a value - "get" or "listenonly" option is defined.} if (defined ($option) and ($option =~ m/(?:get|listenonly)/ixms));

	my $value = $cmd; #process set command with $value as output
	#Text neads special treatment - additional args may be blanked words
	$value .= q{ } . join (q{ }, @arg) if (($model =~ m/^dpt16/ixms) && (scalar (@arg) > 0));

	#Special commands for dpt1 and dpt1.001
	if ($model =~ m/^(?:dpt1|dpt1.001)$/ixms) {
		(my $err, $value) = KNX_Set_dpt1($hash, $targetGadName, $cmd, @arg);
		return $err if defined($err);
	}

	my $transval = KNX_checkAndClean($hash, $value, $targetGadName); #check and cast value
	return $thisSub . qq{invalid value= $value} if (!defined($transval)); #if cast not successful

	my $transvale = KNX_encodeByDpt($hash, $transval, $targetGadName); #process set command
	return $thisSub . 'failed - no set cmd allowed for this dpt' if (!defined($transvale)); # encodeByDpt failed

	IOWrite($hash, $TULid, 'w' . $groupCode . $transvale);

	Log3 ($name, 4, $thisSub . qq{cmd= $cmd , value= $value , translated= $transvale});

	# decode again for values that have been changed in encode process
	$transval = KNX_decodeByDpt($hash, $transvale, $targetGadName) if ($model =~ m/^(?:dpt3|dpt10|dpt11|dpt19)/ixms);

	#apply post processing for state and set all readings
	KNX_SetReadings($hash, $targetGadName, $transval, $rdName, undef); 

	Log3 ($name, 5, $thisSub . '-exit');
	return;
}

# Process set command for old syntax 
# calling param: $hash, $cmd, arg array
# returns ($err, targetgadname, $cmd)
sub KNX_Set_oldsyntax {
	my ($hash, $cmd, @arg) = @_;

	my $name = $hash->{NAME};
	my $na = scalar(@arg);
	my $targetGadName = undef; #contains gadNames to process
	my $groupnr = 1; #default group

	#select another group, if the last arg starts with a g
	if($na >= 1 && $arg[$na - 1] =~ m/$PAT_GNO/ixms) {
		$groupnr = pop (@arg);
		Log3 ($name, 3, qq{KNX_Set_syntax2 ($name): you are still using old syntax, pls. change to "set $name $groupnr $cmd } . join(q{ },@arg) . q{"});
		$groupnr =~ s/^g//gixms; #remove "g"
	}

	# if cmd contains g1: the check for valid gadnames failed !
	# this is NOT oldsyntax, but a user-error!
	if ($cmd =~ /^g[\d]/ixms) {
		Log3 ($name, 2, qq{KNX_Set_syntax2 ($name): an invalid gadName: $cmd was used in set-cmd});
		return qq{an invalid gadName: $cmd was used in set-cmd};
	}

	$targetGadName = KNX_gadNameByNO($hash, $groupnr);
	return qq{gadName not found for $groupnr} if(!defined($targetGadName));

	# all of the following cmd's need at least 1 Argument (or more)
	return (undef, $targetGadName, $cmd) if (scalar(@arg) <= 0);

	my $code = $hash->{GADDETAILS}->{$targetGadName}->{MODEL};
	my $value = $cmd;

	if ($cmd =~ m/$RAW/ixms) {
		#check for 1-16 hex-digits
		return q{"raw" } . $arg[0] . ' has wrong syntax. Use hex-format only.' if ($arg[0] !~ m/[0-9A-F]{1,16}/ixms);
		$value = $arg[0];
	}
	elsif ($cmd =~ m/$VALUE/ixms) {
		return q{"value" not allowed for dpt1, dpt16 and dpt232} if ($code =~ m/(dpt1$)|(dpt16$)|(dpt232$)/ixms);
		$value = $arg[0];
		$value =~ s/,/\./gxms;
	}
	#set string <val1 val2 valn>
	elsif ($cmd =~ m/$STRING/ixms) {
		return q{"string" only allowed for dpt16} if ($code !~ m/dpt16/ixms);
		$value = q{}; # will be joined in KNX_Set
	}
	#set RGB <RRGGBB>
	elsif ($cmd =~ m/$RGB/ixms) {
		return q{"rgb" only allowed for dpt232} if ($code !~ m/dpt232$/ixms);
		#check for 6 hex-digits
		return q{"rgb" } . $arg[0] . q{ has wrong syntax. Use 6 hex-digits only.} if ($arg[0] !~ m/[0-9A-F]{6}/ixms);
		$value = lc($arg[0]);
	}

	return (undef, $targetGadName, $value);
}

# process special dpt1, dpt1.001 set
# calling: $hash, $targetGadName,  $cmd, @arg
# return: $err, $value
sub KNX_Set_dpt1 {
	my ($hash, $targetGadName, $cmd, @arg) = @_;

	my $name = $hash->{NAME};
	my $groupCode = $hash->{GADDETAILS}->{$targetGadName}->{CODE};

	#delete any running timers
	if ($hash->{".TIMER_$groupCode"}) {
		CommandDelete(undef, $name . "_TIMER_$groupCode");
		delete $hash->{".TIMER_$groupCode"};
	}

	my $value = 'off'; # default
	my $tvalue = 'on'; # default reversed value for timer ops
	if ($cmd =~ m/(^on|1)/ixms) {
		$value = 'on';
		$tvalue = 'off';
	}

	return (undef,$value) if ($cmd =~ m/(?:on|off)$/ixms); # shortcut

	#set on-for-timer / off-for-timer
	if ($cmd =~ m/(?:(on|off)-for-timer)$/ixms) {
		#get duration
		my $duration = sprintf('%02d:%02d:%02d', $arg[0]/3600, ($arg[0]%3600)/60, $arg[0]%60);
		Log3 ($name, 5, qq{KNX_Set_dpt1 ($name): $cmd $duration});

		$hash->{".TIMER_$groupCode"} = $duration; #create local marker
		#place at-command for switching on / off
		CommandDefMod(undef, '-temporary ' .  $name . qq{_TIMER_$groupCode at +$duration set $name $targetGadName $tvalue});
	}
	#set on-until / off-until
	elsif ($cmd =~ m/(?:(on|off)-until)$/ixms) {
		#get off-time
		my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($arg[0]); # fhem.pl
		return qq{KNX_Set_dpt1 ($name): Error trying to parse timespec for $arg[0] : $err} if (defined($err));

		#do like (on|off)-until-overnight in at cmd !
		my $hms_til = sprintf('%02d:%02d:%02d', $hr, $min, $sec);
		Log3 ($name, 5, qq{KNX_Set_dpt1 ($name): $cmd  $hms_til});

		$hash->{".TIMER_$groupCode"} = $hms_til; #create local marker
		#place at-command for switching on / off
		CommandDefMod(undef, '-temporary ' . $name . qq{_TIMER_$groupCode at $hms_til set $name $targetGadName $tvalue});
	}
	#toggle
	elsif ($cmd =~ m/$TOGGLE/ixms) {
		my $toggleOldVal = 'dontknow';

		my ($tDev, $togglereading) = split(qr/:/xms,AttrVal($name,'KNX_toggle',$name));
		if (defined($togglereading)) { # prio1: use Attr. KNX_toggle: format: <device>:<reading>
			$tDev = $name if ($tDev eq '$self');
			$toggleOldVal = ReadingsVal($tDev, $togglereading, 'dontknow'); # switch off in case of non existent reading
		}
		else {
			$togglereading = $hash->{GADDETAILS}->{$targetGadName}->{RDNAMEGET}; #prio2: use get-reading
			$toggleOldVal = ReadingsVal($name, $togglereading, undef);
			if (! defined($toggleOldVal)) {
				$togglereading = $hash->{GADDETAILS}->{$targetGadName}->{RDNAMESET}; #prio3: use set-reading
				$toggleOldVal = ReadingsVal($name, $togglereading, 'dontknow');
			}
		}

		Log3 ($name, 3, qq{KNX_Set_dpt1 ($name): current value for "set $name $targetGadName TOGGLE" is not "on" or "off" - } . 
                                qq{$targetGadName will be switched off}) if ($toggleOldVal !~ /^(?:on|off)/ixms);
		$value = q{on} if ($toggleOldVal =~ m/^off/ixms); # value off is default
	}
	#blink - implemented with timer & toggle
	elsif ($cmd =~ m/$BLINK/ixms) {
		my $count = ($arg[0])?$arg[0] * 2 -1:1;
		$count = 1 if ($count < 1);
		my $dur = ($arg[1])?$arg[1]:1;
		$dur = 1 if ($dur < 1);

		my $duration = sprintf('%02d:%02d:%02d', $dur/3600, ($dur%3600)/60, $dur%60);
		CommandDefMod(undef, '-temporary ' .  $name . "_TIMERBLINK_$groupCode at +*{" . $count ."}$duration set $name $targetGadName toggle");
		$value = 'on';
	}

	return (undef,$value);
}

#############################
sub KNX_State {
	return;
}

#Get the chance to qualify attributes
#############################
sub KNX_Attr {
	my ($cmd,$name,$aName,$aVal) = @_;

	my $hash = $defs{$name};
	my $value = undef;

	if ($cmd eq 'set') {
		return qq{KNX_Attr ($name): Attribute "$aName" is not supported/have no function at all, pls. check cmdref for equivalent function.} if ($aName =~ m/(listenonly|readonly|slider)/ixms);

		if ($aName eq 'KNX_toggle') { # validate device/reading
			my ($srcDev,$srcReading) = split(qr/:/xms,$aVal); # format: <device>:<reading>
			$srcDev = $name if ($srcDev eq '$self');
			return 'no valid device for attr: KNX_toggle' if (!IsDevice($srcDev));
			$value = ReadingsVal($srcDev,$srcReading,undef) if (defined($srcReading)); #test for value  
			return 'no valid device/reading value for attr: KNX_toggle' if (!defined($value) && $init_done); # maybe device/reading not defined during start
		}

		# check valid IODev
		elsif ($aName eq 'IODev' && $init_done) {
			return KNX_chkIODev($hash,$aVal);
		}

		elsif ($aName =~ /(?:stateCmd|putCmd)/xms ) { # test for syntax errors
			my %specials = ( '%hash' => $hash, '%name' => $name, '%gadName' => $name, '%state' => $name, );
			my $err = perlSyntaxCheck($aVal, %specials);
			return qq{syntax check failed for $aName: \n $err} if($err);
		}
=pod
		elsif ($aName eq 'stateRegex') { # test for syntax errors
			my $err = eval { "HALLO" =~ m/$aVal/xms };
			return qq{syntax check failed for $aName: \n $@} if ($@); ## no critic (Variables::ProhibitPunctuationVars)
		}
=cut
	} # /set

	if ($cmd eq 'del') {
		if ($aName eq 'disable') {
			my @defentries = split(/\s/ixms,$hash->{DEF});
			foreach my $def (@defentries) { # check all entries
				next if ($def eq ReadingsVal($name,'IODev',undef)); # deprecated IOdev
				next if ($def =~ /:dpt\d+/ixms); 

				Log3 ($name, 2, qq{KNX_Attr ($name): Attribut "disable" cannot be deleted for this device until you specify a valid dpt!});
				return qq{Attribut "disable" cannot be deleted for device $name until you specify a valid dpt!};
			}
			delete $hash->{RAWMSG}; # debug internal
		}
	}
	return;
}

#Split reading for DBLOG
#############################
sub KNX_DbLog_split {
	my $event  = shift;
	my $device = shift;

	my $reading = 'state'; # default
	my $unit    = q{}; # default

	# split event into pieces
	$event =~ s/^\s?//xms; # remove leading blank if any
	my @strings = split (/[\s]+/xms, $event);
	if ($strings[0] =~ /.+[:]$/xms) {
		$reading = shift(@strings);
		$reading =~ s/[:]$//xms;
	}
	$strings[0] = q{} if (! defined($strings[0]));
	
	#numeric value? and last value non numeric? - assume unit
	if (looks_like_number($strings[0]) && (! looks_like_number($strings[scalar(@strings)-1]))) {
		$unit = pop(@strings);
	}
	my $value = join(q{ },@strings);
	$unit = q{} if (!defined($unit));

	Log3 ($device, 5, qq{KNX_DbLog_Split ($device): EVENT= $event READING= $reading VALUE= $value UNIT= $unit});
	return ($reading, $value, $unit);
}

#Handle incoming messages
#############################
sub KNX_Parse {
	my $iohash = shift; # this is IO-Device hash !
	my $msg = shift;

	my $ioName = $iohash->{NAME};
	return q{} if ((IsDisabled($ioName) == 1) || IsDummy($ioName)); # IO - device is disabled or dummy

	#Msg format: C<src>[wrp]<group><value> i.e. Cw00000101
	my ($src,$cmd,$gadCode,$val) = $msg =~ m/^$TULid([0-9a-f]{5})([prw])([0-9a-f]{5})(.*)$/ixms; 
	my @foundMsgs;

	Log3 ($ioName, 4, qq{KNX_Parse -enter: IO-name=$ioName src=} . KNX_hexToName2($src) . q{ dest=} . KNX_hexToName($gadCode) . qq{ msg=$msg});

	#gad not defined yet, give feedback for autocreate
	return KNX_autoCreate($iohash,$gadCode) if (! (exists $modules{KNX}->{defptr}->{$gadCode}));

	#get list from device-hashes using given gadCode (==destination)
	# check on cmd line with: {PrintHash($modules{KNX}->{defptr},3) }
	my @deviceList = @{$modules{KNX}->{defptr}->{$gadCode}};

	#process message for all affected devices and gad's
	foreach my $deviceHash (@deviceList) {
		#get details
		my $deviceName = $deviceHash->{NAME};
		my $gadName = $deviceHash->{GADTABLE}->{$gadCode};

		push(@foundMsgs, $deviceName); # save to list even if dev is disabled

		if (IsDisabled($deviceName) == 1) {
			$deviceHash->{RAWMSG} = qq{gadName=$gadName cmd=$cmd, hexvalue=$val}; # for debugging
			next;
		}

		Log3 ($deviceName, 4, qq{KNX_Parse ($deviceName): -process gadName=$gadName cmd= $cmd});

		#handle write and reply messages
		if ($cmd =~ /[w|p]/ixms) {
			#decode message
			my $getName = $deviceHash->{GADDETAILS}->{$gadName}->{RDNAMEGET};
			my $transval = KNX_decodeByDpt ($deviceHash, $val, $gadName);
			#message invalid
			if (! defined($transval) || ($transval eq q{})) {
				Log3 ($deviceName, 2, qq{KNX_Parse_wp ($deviceName): readingName=$getName message=$msg} . 
                                                      ' could not be decoded');
				next;
			}
			Log3 ($deviceName, 4, qq{KNX_Parse_wp ($deviceName): readingName=$getName value=$transval});

			#apply post processing for state and set all readings
			KNX_SetReadings($deviceHash, $gadName, $transval, $getName, $src);
		}

		#handle read messages
		elsif ($cmd =~ /[r]/ixms) {
			my $putName = $deviceHash->{GADDETAILS}->{$gadName}->{RDNAMEPUT};
			Log3 ($deviceName, 5, qq{KNX_Parse_r ($deviceName): GET});

			my $value = undef;
			#high priority - eval
			my $cmdAttr = AttrVal($deviceName, 'putCmd', undef);
			if ((defined($cmdAttr)) && ($cmdAttr ne q{})) {
				$value = KNX_eval ($deviceHash, $gadName, $value, $cmdAttr);
				if (defined($value) && ($value ne q{}) && ($value ne 'ERROR')) { # answer only, if eval was successful
					Log3 ($deviceName, 5, qq{KNX_Parse_r ($deviceName): replaced by Attr putCmd=$cmdAttr VALUE=$value});
					readingsSingleUpdate($deviceHash, $putName, $value,0);
				}
				else {
					Log3 ($deviceName, 5, qq{KNX_Parse_r ($deviceName): gadName=$gadName - no reply sent!});
					$value = undef; # dont send !
				} 
			}
			# medium / low priority
			elsif (AttrVal($deviceName, 'answerReading', 0) != 0) {
				my $putVal = ReadingsVal($deviceName, $putName, undef);
				if (defined($putVal) && ($putVal ne q{})) {
					$value = $putVal; #medium priority, overwrite $value
				}
				else {
					$value = ReadingsVal($deviceName, 'state', undef); #lowest priority - use state!
				}
			}

			#send transval
			if (defined($value)) {
				my $transval = KNX_encodeByDpt($deviceHash, $value, $gadName);
				Log3 ($deviceName, 4, qq{KNX_Parse_r ($deviceName): send answer: reading=$gadName VALUE=$transval});
				IOWrite ($deviceHash, $TULid, 'p' . $gadCode . $transval);
			}
		}
		#/process message
	}
	return @foundMsgs;
}

########## begin of private functions ##########

### KNX_autoCreate 
# check wether we must do autocreate...
# on entry: $iohash, $gadcode
# on exit: return string for autocreate
sub KNX_autoCreate {
	my $iohash  = shift;
	my $gadCode = shift;

	my $gad = KNX_hexToName($gadCode); #format gad
	my $newDevName = sprintf('KNX_%.2d%.2d%.3d',split (/\//xms, $gad)); #create name

	# check if any autocreate device has ignoretype "KNX..." set
	my @acList = devspec2array('TYPE=autocreate');
	foreach my $acdev (@acList) {
		next unless $acdev;
		next if (! $defs{$acdev});
		my $igntypes = AttrVal($acdev,'ignoreTypes',q{});
		return q{} if($newDevName =~ /$igntypes/xms);
	}
	return qq{UNDEFINED $newDevName KNX $gad} . q{:} . $MODELERR;
} 

### KNX_SetReadings is called from KNX_Set and KNX_Parse
# calling param: $hash, $gadName, $transval, $rdName, caller (set/parse)
sub KNX_SetReadings {
	my ($hash, $gadName, $transval, $rdName, $src) = @_;
	my $name = $hash->{NAME};

	#append post-string, if supplied: format attr overrides supplied unit!
	my $model = $hash->{GADDETAILS}->{$gadName}->{MODEL};
	my $unit = $dpttypes{$model}->{UNIT};
	my $suffix = AttrVal($name, 'format', undef);
	if (defined($suffix) && ($suffix ne q{})) {
		$transval .= q{ } . $suffix;
	} elsif (defined ($unit) && ($unit ne q{})) {
		$transval .= q{ } . $unit;
	}

	#execute stateRegex
	my $state = KNX_replaceByRegex ($hash, $rdName, $transval);

	my $lsvalue = 'fhem'; # called from set
	$lsvalue = KNX_hexToName2($src) if (defined($src) && ($src ne q{})); # called from parse

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'last-sender', $lsvalue);
	readingsBulkUpdate($hash, $rdName, $transval);

	if (defined($state)) {
		#execute state-command if defined
		#must be placed after first reading, because it may have a reference
		my $deviceName = $name; #hack for being backward compatible - serve $name and $devname
		my $cmdAttr = AttrVal($name, 'stateCmd', undef);

		if ((defined($cmdAttr)) && ($cmdAttr ne q{})) {
			my $newstate = KNX_eval ($hash, $gadName, $state, $cmdAttr);
			if (defined($newstate) && ($newstate ne q{}) && ($newstate !~ m/ERROR/ixms)) {
				$state = $newstate;
				Log3 ($name, 5, qq{KNX_SetReadings ($name): state replaced via stateCmd $cmdAttr - state: $state});
			}
			else {
				Log3 ($name, 3, qq{KNX_SetReadings ($name): GAD $gadName , error during stateCmd processing});
			}
		}
		readingsBulkUpdate($hash, 'state', $state);
	}
	readingsEndUpdate($hash, 1);
	return;
}

### check for valid IODev
# called from define & Attr
# returns undef on success , error msg on failure
# returns list of IODevs if $iocandidate is undef on entry
sub KNX_chkIODev {
	my $hash = shift;
	my $iocandidate = shift // 'undefined';

	my $name = $hash->{NAME};

	my @IOList = devspec2array('TYPE=(TUL|KNXTUL|KNXIO|FHEM2FHEM)');
	my @IOList2 = (); # holds all non disabled io-devs
	foreach my $iodev (@IOList) {
		next unless $iodev;
		next if ((IsDisabled($iodev) == 1) || IsDummy($iodev)); # IO - device is disabled or dummy
		my $iohash = $defs{$iodev};
		next if ($iohash->{TYPE} eq 'KNXIO' && exists($iohash->{model}) && $iohash->{model} eq 'X'); # exclude dummy dev
		push(@IOList2,$iodev);
		next if ($iodev ne $iocandidate);
		return if ($iohash->{TYPE} ne 'FHEM2FHEM'); # ok for std io-dev

		# add support for fhem2fhem as io-dev
		my $rawdef = $iohash->{rawDevice}; #name of fake local IO-dev or remote IO-dev
		if (defined($rawdef)) {
			return if (exists($defs{$rawdef}) && $defs{$rawdef}->{TYPE} eq 'KNXIO' && $defs{$rawdef}->{model} eq 'X'); # only if model of fake device eq 'X'
			return if (exists($iohash->{'.RTYPE'}) && $iohash->{'.RTYPE'} eq 'KNXIO'); # remote TYPE is KNXIO ( need patched FHEM2FHEM module)
		}
	}
	return join(q{,}, @IOList2) if ($iocandidate eq 'undefined');
	return $iocandidate . ' is not a valid IO-device or disabled/dummy for ' . qq{$name \n} .
               'Valid IO-devices are: ' . join(q{, }, @IOList2);
}

### delete all defptr entries for this device
# used in undefine & define (avoid defmod problem) 09-02-2021
# calling param: $hash
# return param:  none
sub KNX_delete_defptr {
	my $hash = shift;
	my $name = $hash->{NAME};

	for my $gad (sort keys %{$modules{KNX}->{defptr}}) { # get all gad for all KNX devices
		my @olddefList = ();
		@olddefList = @{$modules{KNX}->{defptr}->{$gad}} if (defined ($modules{KNX}->{defptr}->{$gad})); # get list of devices with this gad
		my @newdefList = ();
		foreach my $devHash (@olddefList) {
			push (@newdefList, $devHash) if ($devHash != $hash); # remove previous definition for this device, but keep them for other devices!
		}
		#restore list if we have at least one entry left, or delete key!
		if (scalar(@newdefList) == 0) {
			delete $modules{KNX}->{defptr}->{$gad};
		}
		else {
			@{$modules{KNX}->{defptr}->{$gad}} = @newdefList;
		}
	}
	return;
}

### convert GAD from hex to readable version
sub KNX_hexToName {
	my $v = shift;
	
	my $p1 = hex(substr($v,0,2));
	my $p2 = hex(substr($v,2,1));
	my $p3 = hex(substr($v,3,2));

	return sprintf('%d/%d/%d', $p1,$p2,$p3);
}

### convert PHY from hex to readable version
sub KNX_hexToName2 {
	my $v = KNX_hexToName(shift);
	$v =~ s/\//\./gxms;
	return $v;
}

### convert GAD from readable version to hex
sub KNX_nameToHex {
	my $v = shift;
	my $r = $v;

	if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/xms) {
		$r = sprintf('%02x%01x%02x',$1,$2,$3);
	}
	return $r;
}

### clean input string according DPT
# return undef on error
sub KNX_checkAndClean {
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};
	my $orgValue = $value;

	my $model = $hash->{GADDETAILS}->{$gadName}->{MODEL};

	#return unchecked, if this is a autocreate-device
	return $value if ($model eq $MODELERR);

	my $pattern = $dpttypes{$model}->{PATTERN};

	#trim whitespaces at the end
	$value =~ s/^\s+|\s+$//gixms;
	$value .= ':00' if ($model eq 'dpt10' && $value =~ /^[\d]{2}:[\d]{2}$/gixms); # compatibility with widgetoverride :time

#new code: match against model pattern -to be tested!!!
#	my $pattern = $dpttypes{$model}->{PATTERN});
#	return if ($value !~ m/$pattern/ix);

	my @tmp = ($value =~ m/$pattern/gixms);
	#loop through results
	my $found = 0;
	foreach my $str (@tmp) {
		#assign first match and exit loop
		if (defined($str)) {
			$found = 1;
			$value = $str;
			last;
		}
	}
	return if ($found == 0);

	Log3 ($name, 3, qq{KNX_checkAndClean ($name): gadName= $gadName value= $orgValue was casted to $value}) if ($orgValue ne $value);
	Log3 ($name, 5, qq{KNX_checkAndClean ($name): gadName= $gadName value= $value model= $model pattern= $pattern});

	return $value;
}

### replace state-values by Attr stateRegex
sub KNX_replaceByRegex {
	my ($hash, $rdName, $input) = @_;
	my $name = $hash->{NAME};

	my $regAttr = AttrVal($name, 'stateRegex', undef);
	return $input if (! defined($regAttr));

	my $retVal = $input;

	#execute regex, if defined
	#get array of given attributes
	my @reg = split(/\s\//xms, $regAttr);

	my $tempVal = $rdName . q{:} . $input;

	#loop over all regex
	foreach my $regex (@reg) {
		#trim leading and trailing slashes
		$regex =~ s/^\/|\/$//gixms;
		#get pairs
		my @regPair = split(/\//xms, $regex);
		next if ((not defined($regPair[0])) || ($regPair[0] eq q{}));

		#skip if first part of regex not match readingName
		my $regName = $regPair[0] =~ s/^([^:]+).*/$1/irxms; # extract rd-name
		next if ($rdName ne $regName); # must match completely!

		if (not defined ($regPair[1])) { # cut value
			$retVal = 'undefined';
		}
		elsif ($regPair[0] eq $tempVal) { # complete match
			$retVal = $regPair[1];
		}
		elsif (($input !~ /$regPair[0]/xms) && ($regPair[0] =~ /[:]/xms)) { # value dont match!
			next;
		}
		else { #replace value
			$tempVal =~ s/$regPair[0]/$regPair[1]/gixms;
			($retVal = $tempVal) =~ s/[:]/ /xms;
		}
		last;
	}
	Log3 ($name, 5, qq{KNX_replaceByRegex ($name): replaced $rdName value from: $input to $retVal}) if ($input ne $retVal);
	return ($retVal eq 'undefined')?undef:$retVal;
}

### limit numeric values. Valid directions: encode, decode
# called from: _encodeByDpt, _decodeByDpt
# returns: limited value
sub KNX_limit {
	my ($hash, $value, $model, $direction) = @_;

	#continue only if numeric value
	return $value if (! looks_like_number ($value));
	return $value if (! defined($direction));

	my $name = $hash->{NAME};
	my $retVal = $value;

	#get correction details
	my $factor = $dpttypes{$model}->{FACTOR};
	my $offset = $dpttypes{$model}->{OFFSET};
	#get limits
	my $min = $dpttypes{$model}->{MIN};
	my $max = $dpttypes{$model}->{MAX};

	#determine direction of scaling, do only if defined
	if ($direction =~ m/^encode/ixms) {
		#limitValue
		$retVal = $min if (defined ($min) && ($value < $min));
		$retVal = $max if (defined ($max) && ($value > $max));
		#correct value
		$retVal /= $factor if (defined ($factor));
		$retVal -= $offset if (defined ($offset));
	}
	elsif ($direction =~ m/^decode/ixms) {
		#correct value
		$retVal += $offset if (defined ($offset));
		$retVal *= $factor if (defined ($factor));
		#limitValue
		$retVal = $min if (defined ($min) && ($retVal < $min));
		$retVal = $max if (defined ($max) && ($retVal > $max));
	}

	Log3 ($name, 5, qq{KNX_limit ($name): DIR= $direction INPUT= $value OUTPUT= $retVal});

	return $retVal;
}

### process attributes stateCmd & putCmd
sub KNX_eval {
	my ($hash, $gadName, $state, $evalString) = @_;
	my $name = $hash->{NAME};
	my $retVal = undef;

	my $code = EvalSpecials($evalString,('%hash' => $hash, '%name' => $name, '%gadName' => $gadName, '%state' => $state)); # prepare vars for AnalyzePerlCommand
	$retVal =  AnalyzeCommandChain(undef, $code);
	$retVal = 'ERROR' if (not defined ($retVal));

	if ($retVal =~ /(^Forbidden|error)/ixms) { # eval error or forbidden by Authorize
		Log3 ($name, 2, qq{KNX_Eval-error ($name): gadName= $gadName evalString= $evalString result= $retVal});
		$retVal = 'ERROR';
	}
	return $retVal;
}

### encode KNX-Message according DPT
# on return: hex string to be sent to bus / undef on error
sub KNX_encodeByDpt {
	my $hash    = shift;
	my $value   = shift;
	my $gadName = shift;

	my $name = $hash->{NAME};
	my $model = $hash->{GADDETAILS}->{$gadName}->{MODEL}; 
	my $code = $dpttypes{$model}->{CODE};

	return if ($model eq $MODELERR); #return unchecked, if this is a autocreate-device

	my $lvalue = KNX_limit ($hash, $value, $model, 'ENCODE');
	Log3 ($name, 4, qq{KNX_limit ($name): gadName= $gadName modified... Input= $value Output= $lvalue Model= $model}) if ($value ne $lvalue);

	if (ref($dpttypes{$code}->{ENC}) eq 'CODE') {
		my $hexval = $dpttypes{$code}->{ENC}->($lvalue, $model);
		Log3 ($name, 5, qq{KNX_encodeByDpt ($name): gadName= $gadName model= $model code= $code } . 
                                qq{in-Value= $value out-value= $lvalue out-hexval= $hexval});
		return $hexval;
	}
	else {
		Log3 ($name, 2, qq{KNX_encodeByDpt ($name): gadName= $gadName model= $model not valid});
	}
	return;
}

### decode KNX-Message according DPT
# on return: decoded value from bus / on error: undef
sub KNX_decodeByDpt {
	my $hash    = shift;
	my $value   = shift;
	my $gadName = shift;

	my $name = $hash->{NAME};
	my $model = $hash->{GADDETAILS}->{$gadName}->{MODEL};
	my $code = $dpttypes{$model}->{CODE};

	return if ($model eq $MODELERR); #return unchecked, if this is a autocreate-device

	if (ref($dpttypes{$code}->{DEC}) eq 'CODE') {
		my $state = $dpttypes{$code}->{DEC}->($value, $model, $hash);
		Log3 ($name, 5, qq{KNX_decodeByDpt ($name): gadName= $gadName model= $model code= $code value= $value length-value= } . 
                                length($value) . qq{ state= $state});
		return $state;
	}
	else {
		Log3 ($name, 2, qq{KNX_decodeByDpt ($name): gadName= $gadName model= $model not valid});
	}
	return;
}

############################
### encode sub functions ###
sub enc_dpt1 { #Binary value
	my $value = shift;
	my $model = shift;
	my $numval = 0; #default
	$numval = 1 if ($value =~ m/(1|on)$/ixms);
	$numval = 1 if ($value eq $dpttypes{$model}->{MAX}); # dpt1.011 problem
	return sprintf('%.2x',$numval);
}

sub enc_dpt2 { #Step value (two-bit)
	my $value = shift;
	my $dpt2list = {off => 0, on => 1, forceoff => 2, forceon =>3};
	my $numval = $dpt2list->{lc($value)};
	$numval = $value if ($value =~ m/^0?[0-3]$/ixms); # JoeALLb request
	return sprintf('%.2x',$numval);
}

sub enc_dpt3 { #Step value (four-bit)
	my $value = shift;
	my $numval = 0;
	my $sign = ($value >= 0 )?1:0;
	$value = abs($value);
	my @values = qw( 100 50 25 12 6 3 1 0);
	foreach my $key (@values) {
		$numval++;
		last if ($value >= $key);
	}
	$numval = ($numval | 0x08) if ($sign == 1); # positive
	return sprintf('%.2x',$numval);
}

sub enc_dpt4 { #single ascii or iso-8859-1 char
	my $value = shift;
	my $model = shift;
	my $numval = encode('iso-8859-1', decode('utf8', $value)); #always convert to latin-1
	$numval =~ s/[\x80-\xff]/?/gxms if ($model eq 'dpt4.001'); #replace values >= 0x80 if ascii
	#convert to hex-string
	my $dat = unpack('H*', $numval);
	return sprintf('00%s',$dat);
}

sub enc_dpt5 { #1-Octet unsigned value
	return sprintf('00%.2x',shift);
}

sub enc_dpt6 { #1-Octet signed value
	#build 2-complement
	my $numval = unpack('C', pack('c', shift));
	return sprintf('00%.2x',$numval);
}

sub enc_dpt7 { #2-Octet unsigned Value
	return sprintf('00%.4x',shift);
}

sub enc_dpt8 { #2-Octet signed Value
	#build 2-complement
	my $numval = unpack('S', pack('s', shift));
	return sprintf('00%.4x',$numval);
}

sub enc_dpt9 { #2-Octet Float value
	my $value = shift;
	my $sign = ($value <0 ? 0x8000 : 0);
	my $exp  = 0;
	my $mant = $value * 100;
	while (abs($mant) > 0x07FF) {
		$mant /= 2;
		$exp++;
	}
	my $numval = $sign | ($exp << 11) | ($mant & 0x07FF);
	return sprintf('00%.4x',$numval);
}

sub enc_dpt10 { #Time of Day
	my $value = shift;
	my $numval = 0;
	my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time); # default now
	if ($value =~ /$PAT_TIME/ixms) {
		($hours,$mins,$secs) = split(/[:]/ixms,$value);
		my $ts = fhemTimeLocal($secs, $mins, $hours, $mday, $mon, $year);
		($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
	}
	#add offsets
	$year += 1900;
	$mon++;
	# calculate offset for weekday
	$wday = 7 if ($wday == 0);
	$hours += 32 * $wday;
	$numval = $secs + ($mins << 8) + ($hours << 16);

	return sprintf('00%.6x',$numval);
}

sub enc_dpt11 { #Date year range is 1990-2089 {0 => 2000 , 89 => 2089, 90 => 1990}
	my $value = shift;
	my $numval = 0;
	if ($value =~ m/now/ixms) {
		#get actual time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		#add offsets
		$year+=1900;
		$mon++;
		# calculate offset for weekday
		$wday = 7 if ($wday == 0);
		$numval = ($year - 2000) + ($mon << 8) + ($mday << 16);
	}
	else {
		my ($dd, $mm, $yyyy) = split (/\./xms, $value);
		$yyyy -= 2000;
		$yyyy += 100 if ($yyyy < 0);
		$numval = ($yyyy) + ($mm << 8) + ($dd << 16);
	}
	return sprintf('00%.6x',$numval);
}

sub enc_dpt12 { #4-Octet unsigned value
	return sprintf('00%.8x',shift);
}

sub enc_dpt13 {#4-Octet Signed Value
	#build 2-complement
	my $numval = unpack('L', pack('l', shift));
	return sprintf('00%.8x',$numval);
}

sub enc_dpt14 { #4-Octet single precision float
	my $numval = unpack('L',  pack('f', shift));
	return sprintf('00%.8x',$numval);
}

sub enc_dpt16 { #14-Octet String
	my $value = shift;
	my $model = shift;
	my $numval = encode('iso-8859-1', decode('utf8', $value)); #always convert to latin-1
	$numval =~ s/[\x80-\xff]/?/gxms if ($model =~ /dpt16\.000/ixms); #replace values >= 0x80 if ascii 
	#convert to hex-string
	my $dat = unpack('H*', $numval);
	$dat = '00' if ($value =~ /^$PAT_DPT16_CLR/ixms); # send all zero string if "clear line string"
	#format for 14-byte-length and replace trailing blanks with zeros
	my $hexval = sprintf('00%-28s',$dat);
	$hexval =~ s/\s/0/gxms;
	return $hexval;
}

sub enc_dpt19 { #DateTime
	my $value = shift;
	my $ts = time; # default or when "now" is given
	# if no match we assume now and use current date/time
	if ($value =~ m/^$PAT_DATE$PAT_DTSEP$PAT_TIME/xms) {
		$ts = fhemTimeLocal($6, $5, $4, $1, $2-1, $3 - 1900);
	}
	my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
	$wday = 7 if ($wday == 0); # calculate offset for weekday
	$hours += ($wday << 5); # add day of week
	my $status1 = 0x40;  # Fault=0, WD = 1, NWD = 0 (WD Field valid), NY = 0, ND = 0, NDOW= 0,NT=0, SUTI = 0
	$status1 = $status1 & 0xBF if ($wday >= 6); # Saturday & Sunday is non working day
	$status1 += 1 if ($isdst == 1);
	my $status0 = 0x00;  # CLQ=0
	$mon++;
	return sprintf('00%02x%02x%02x%02x%02x%02x%02x%02x',$year,$mon,$mday,$hours,$mins,$secs,$status1,$status0);
}

sub enc_dpt20 { # HVAC 1Byte
	my $value = shift;
	my $dpt20list = {auto => 0, comfort => 1, standby => 2, economy => 3, protection => 4,};
	my $numval = $dpt20list->{lc($value)};
	$numval = 5 if (! defined($numval));
	return sprintf('00%.2x',$numval);
}

#sub enc_dpt22 { # HVAC dpt22.101 only no encoding - receive only!!!
#	my $value = shift;
#}

sub enc_dpt232 { #RGB-Code
	return '00' . shift;
}

############################
### decode sub functions ###
sub dec_dpt1 { #Binary value
	my $numval = hex (shift);
	my $model = shift;
	$numval = ($numval & 0x01);
	my $state = $dpttypes{$model}->{MIN}; # default
	$state = $dpttypes{$model}->{MAX} if ($numval == 1);
	return $state;
}

sub dec_dpt2 { #Step value (two-bit)
	my $numval = hex (shift);
	my $model = shift;
	my $state = ($numval & 0x03);
	my @dpt2txt = qw(off on forceOff forceOn);
	$state = $dpt2txt[$state] if ($model ne 'dpt2.000');  # JoeALLb request;
	return $state;
}

sub dec_dpt3 { #Step value (four-bit)
	my $numval = hex (shift);
	my $dir = ($numval & 0x08) >> 3;
	my $step = ($numval & 0x07);
	my $stepcode = 0;
	if ($step > 0) {
		$stepcode = int(100 / (2**($step-1)));
		$stepcode *= -1 if ($dir == 0);
	}
	return sprintf ('%d', $stepcode);
}

sub dec_dpt5 { #1-Octet unsigned value / also used for dpt17, dpt18
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = ($numval & 0x3F) if ($model =~ /^(dpt17|dpt18)/ixms);
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%.0f', $state);
}

sub dec_dpt6 { #1-Octet signed value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = unpack('c',pack('C',$numval));
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%d', $state);
}

sub dec_dpt7 { #2-Octet unsigned Value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%.0f', $state);
}

sub dec_dpt8 { #2-Octet signed Value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = unpack('s',pack('S',$numval));
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%d', $state);
}

sub dec_dpt9 { #2-Octet Float value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	my $sign = 1;
	$sign = -1 if(($numval & 0x8000) > 0);
	my $exp = ($numval & 0x7800) >> 11;
	my $mant = ($numval & 0x07FF);
	$mant = -(~($mant-1) & 0x07FF) if($sign == -1);
	$numval = (1 << $exp) * 0.01 * $mant;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%.2f', $state);
}

sub dec_dpt10 { #Time of Day
	my $numval = hex (shift);
	my $hours = ($numval & 0x1F0000) >> 16;
	my $mins  = ($numval & 0x3F00) >> 8;
	my $secs  = ($numval & 0x3F);
	my $wday  = ($numval & 0xE00000) >> 21;
	# my @wdays = qw{q{} Monday Tuesday Wednesday Thursday Friday Saturday Sunday};
	# return sprintf('%s, %02d:%02d:%02d',$wdays[$wday],$hours,$mins,$secs); # new option ?
	return sprintf('%02d:%02d:%02d',$hours,$mins,$secs);
}

sub dec_dpt11 { #Date
	my $numval = hex (shift);
	my $day = ($numval & 0x1F0000) >> 16;
	my $month  = ($numval & 0x0F00) >> 8;
	my $year  = ($numval & 0x7F);
	#translate year (21st cent if <90 / else 20th century)
	$year += 1900 if($year >= 90);
	$year += 2000 if($year < 90);
	return sprintf('%02d.%02d.%04d',$day,$month,$year);
}

sub dec_dpt12 { #4-Octet unsigned value (handled as dpt7)
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%.0f', $state);
}

sub dec_dpt13 { #4-Octet Signed Value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = unpack('l',pack('L',$numval));
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%d', $state);
}

sub dec_dpt14 { #4-Octet single precision float
	my $numval = unpack 'f', pack 'L', hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ('%.3f', $numval);
}

sub dec_dpt15 { #4-Octet Access data receive only
	my $numval = shift;
	my $model = shift;
	my $hash = shift;
	my $aindex = hex(substr($numval,-2));
	return 'error' if (($aindex & 0x80) != 0);
	return 'no_permission' if (($aindex & 0x40) != 0);
	$aindex = $aindex & 0x0F; # Access index
	$numval = substr($numval,0,length($numval)-2);
	return sprintf ('%02d-%s',$aindex,$numval); # <index>-<acc-Code>
}

sub dec_dpt16 { #14-Octet String or dpt4: single Char string
	my $value = shift;
	my $model = shift;
	my $numval = 0;
	$value =~ s/\s*$//gxms; # strip trailing blanks
	my $state = pack('H*',$value);
	#convert from latin-1
	$state = encode ('utf8', decode('iso-8859-1',$state)) if ($model !~ m/^dpt(?:16.000|4.001)$/xms);
	$state = q{} if ($state =~ m/^[\x00]/ixms); # case all zeros received
	$state =~ s/[\x00-\x1F]+//gxms; # remove non printable chars
	return $state;
}

sub dec_dpt19 { #DateTime
	my $numval = substr(shift,-16); # strip off 1st byte
	my $time = hex (substr ($numval, 6, 6));
	my $date = hex (substr ($numval, 0, 6));
	my $secs  = ($time & 0x3F);
	my $mins  = ($time & 0x3F00) >> 8;
	my $hours = ($time & 0x1F0000) >> 16;
	my $day   = ($date & 0x1F);
	my $month = ($date & 0x0F00) >> 8;
	my $year  = ($date & 0xFF0000) >> 16;
	#extras
	my $wday  = ($time & 0xE00000) >> 21; # 0 = anyday/not valid, 1= Monday,...
	$year += 1900;
	return sprintf('%02d.%02d.%04d_%02d:%02d:%02d', $day, $month, $year, $hours, $mins, $secs);
}

sub dec_dpt20 { #HVAC
	my $numval = hex (shift);
	$numval = ($numval & 0x07); # mask any non-std bits!
	my @dpt20_102txt = qw(Auto Comfort Standby Economy Protection reserved);
	$numval = 5 if ($numval > 4); # dpt20.102
	return $dpt20_102txt[$numval];
}

sub dec_dpt22 { #HVAC dpt22.101 only
	my $numval = hex (shift);
	return 'error' if (($numval & 0x01) == 1);
	my $state = (($numval & 0x0100) == 0)?'heating':'cooling';
	$state .= '_Frostalarm' if (($numval & 0x2000) != 0);
	$state .= '_Overtempalarm' if (($numval & 0x4000) != 0);
	return $state;
}

sub dec_dpt217 { #version
	my $numval = hex (shift);
	my $maj = $numval >> 11;
	my $mid = ($numval >> 6) & 0x001F;
	my $min = $numval & 0x003F;
	return sprintf('V %d.%d.%d',$maj,$mid,$min);
}

sub dec_dpt232 { #RGB-Code
	my $numval = hex (shift);
	return sprintf ('%.6x',$numval);
}

### lookup gadname by gadnumber
# called from: KNX_Get, KNX_setOldsyntax
# entry: $hash, desired gadNO
# return: undef on error / gadName
sub KNX_gadNameByNO {
	my $hash = shift;
	my $groupnr  = shift // 1; # default: search for g1

	my $targetGadName = undef;
	foreach my $key (keys %{$hash->{GADDETAILS}}) {
		if ($hash->{GADDETAILS}->{$key}->{NO} == $groupnr) {
			$targetGadName = $key;
			last;
		}
	}
	return $targetGadName;
}

########## public utility functions ##########
# when called from FHEM cmd-line
sub main::KNX_scancmd {
	my $cl = shift;
	my $devs = shift;
	$devs = undef if ($devs eq q{});
	return main::KNX_scan($devs);
}

### get state of devices from KNX_Hardware
# called with devspec as argument
# e.g : KNX_scan() / KNX_scan('device1') / KNX_scan('device1, dev2,dev3,...' / KNX_scan('room=Kueche'), ...
# returns number of "gets" executed
sub main::KNX_scan {
	my $devs = shift // 'TYPE=KNX'; # select all if nothing defined

	if (! $init_done) { # avoid scan before init complete
		Log3 (undef, 2,'KNX_scan command rejected during FHEM-startup!');
		return 0;
	}

	my @devlist = devspec2array($devs);

	my $i = 0; #counter devices
	my $j = 0; #counter devices with get
	my $k = 0; #counter total get's
	my $getsarr = q{};

	foreach my $knxdef (@devlist) {
		next unless $knxdef;
		next if($knxdef eq $devs && !$defs{$knxdef});
		my $devhash = $defs{$knxdef};
		next if ((! defined($devhash)) || ($devhash->{TYPE} ne 'KNX') || $devhash->{DEF} =~ /$MODELERR/ixms);

		#check if IO-device is ready
		my $iodev = $devhash->{IODev}->{NAME};
		next if (! defined($iodev));
		my $iostate = ReadingsVal($iodev,'state',q{});
		next if ($iostate ne 'connected');
 
		$i++;
		my $k0 = $k; #save previous number of get's
		foreach my $key (keys %{$devhash->{GADDETAILS}}) {
			last if (! defined($key));
			my $option = $devhash->{GADDETAILS}->{$key}->{OPTION};
			next if (defined($option) && $option =~ /(?:set|listenonly)/ixms);
			$k++;
			$getsarr .= $knxdef . q{ } . $key . q{,};
		}
		$j++ if ($k > $k0);
	}
	Log3 (undef, 3, qq{KNX_scan: $i devices selected (regex= $devs) / $j devices with get / $k "gets" executing...});
	doKNX_scan($getsarr) if ($k > 0);
	return $k;
}

### issue all get cmd's - each one delayed by InternalTimer
sub doKNX_scan {
	my ($devgad, $arr) = split(/,/xms,shift,2);
	main::fhem("get $devgad");
	return if (! defined($arr) || $arr eq q{});
	return InternalTimer(gettimeofday() + 0.2,\&doKNX_scan,$arr); # does not support array-> use string...
}


1;

=pod

=encoding utf8

=item [device]
=item summary Devices communicate via the IO-Device TUL/KNXTUL/KNXIO with KNX-bus
=item summary_DE Ger&auml;te kommunizieren &uuml;ber IO-Ger&auml;t TUL/KNXTUL/KNXIO mit KNX-Bus

=begin html

<style>
  #KNX-dpt_ul {
    list-style-type: none;
    padding-left: 10px;
    width:95%;
    column-count:2;
    column-gap:10px;
    -moz-column-count:2;
    -moz-column-gap:20px;
    -webkit-column-count:2;
    -webkit-column-gap:20px;
  }
  #KNX-dpt_ul li {
    padding-left: 1em; white-space: pre; overflow: clip;
  }
  #KNX-dpt_ul li b { 
    display: inline-block;
    width: 6em;
    overflow: clip;
  }
  #KNX-attr_ul {
    list-style-type: none;
    padding-left: 30px;
    width:95%;
    column-count:2;
    column-gap:10px;
    -moz-column-count:2;
    -moz-column-gap:20px;
    -webkit-column-count:2;
    -webkit-column-gap:20px;
  }
  #KNX-attr_ul a {
    padding-left: 1em; width: 100%;
  }
  /* For mobile phones: */
  @media only screen and (max-width: 1070px) {
    #KNX-dpt_ul {column-count:1; -moz-column-count:1; -webkit-column-count:1;}
    #KNX-attr_ul {column-count:1; -moz-column-count:1; -webkit-column-count:1;}
  }
</style>
<a id="KNX"></a>
<h3>KNX</h3>
<ul>
<p>KNX is a standard for building automation / home automation. It is mainly based on a twisted pair wiring, but also other mediums (ip, wireless) are specified.</p>
<p>For getting started, please refer to this document: <a href="https://www.knx.org/knx-en/for-your-home/">KNX for your home</a> -  knx.org web-site.</p>
<p>While the <a href="#TUL">TUL-module</a>, <a href="#KNXTUL">KNXTUL-module</a>, or <a href="#KNXIO">KNXIO-module</a> represent the connection to the KNX network, 
 the KNX module represent a individual KNX device. <br /> 
This module provides a basic set of operations (on, off, toggle, on-until, on-for-timer) to switch on/off KNX devices and to send values to the bus.&nbsp;</p>
<p>Sophisticated setups can be achieved by combining multiple KNX-groupaddresses:datapoints (GAD's:dpt's) in one KNX device instance.</p>
<p>KNX defines a series of Datapoint Type as standard data types used to allow general interpretation of values of devices manufactured by different vendors.
 These datatypes are used to interpret the status of a device, so the readings in FHEM will show the correct value and optional unit.</p>
<p>For each received telegram there will be a reading containing the received value and the sender address.<br /> 
For every set, there will be a reading containing the sent value.<br /> 
The reading &lt;state&gt; will be updated with the last sent or received value.&nbsp;</p>
<p>A (german) wiki page is avaliable here: <a href="http://www.fhemwiki.de/wiki/KNX">FHEM Wiki</a>

<a id="KNX-define"></a>
<p><strong>Define</strong></p>
<p><code>define &lt;name&gt; KNX &lt;group&gt;:&lt;dpt&gt;[:[gadName]:[set|get|listenonly]:[nosuffix]] [&lt;group&gt;:&lt;dpt&gt; ..] <del>[IODev]</del></code></p>
<p><strong>Important:&nbsp;a KNX device needs at least one&nbsp;valid DPT.</strong> Please refer to <a href="#KNX-dpt">avaliable DPT</a>.
 Otherwise the system cannot en- or decode messages.<br />
<strong>Devices defined by autocreate have to be reworked with the suitable dpt and the disable attribute cleared. Otherwise they won't do anything.</strong></p>

<p>The &lt;group&gt; parameter is either a group name notation (0-31/0-7/0-255) or the hex representation of it ([00-1f][0-7][00-ff]) (5 digits). 
 All of the defined groups can be used for bus-communication. 
 It is not allowed to have the same group-address more then once in one device. You can have multiple devices containing the same group-adresses.<br /> 
As described above the parameter &lt;DPT&gt; must contain the corresponding DPT - matching the dpt-spec of the KNX-Hardware..<br /> 
The optional parameteter [gadName] may contain an alias for the GAD. The following gadNames are <b>not allowed:</b> on, off, on-for-timer,
 on-until, off-for-timer, off-until, toggle, raw, rgb, string, value, set, get, listenonly, nosuffix -  because of conflict with cmds &amp; parameters.<br />
Especially if attribute <a href="#KNX-attr-answerReading">answerReading</a> is set to 1, it might be useful to modifiy the behaviour of single GADs. If you want to restrict the GAD,
 you can raise the flags "get", "set", or "listenonly".  The usage should be self-explanatory. It is not possible to combine the flags.<br /> 
<b>Specifying an IO-Device in define is now deprecated!</b> Use attribute <a href="#KNX-attr-IODev">IODev</a> instead, but only if absolutely required!</p>
<p>The GAD's are per default named with "g&lt;number&gt;". The corresponding reading-names are getG&lt;number&gt;, setG&lt;number&gt; and putG&lt;number&gt;.<br /> 
If you supply &lt;gadName&gt; this name is used instead. The readings are &lt;gadName&gt;-get, &lt;gadName&gt;-set and &lt;gadName&gt;-put. 
The synonyms &lt;getName&gt;, &lt;setName&gt; and &lt;putName&gt; are used in this documentation.
If you add the option "nosuffix", &lt;getName&gt;, &lt;setName&gt; and &lt;putName&gt; have the identical name - only &lt;gadName&gt;.</p>
<p>The first group is used for sending by default. If you want to send to a different group, you have to address it. E.g: <code>set &lt;name&gt; &lt;gadName&gt; &lt;value&gt; </code></p>
<p>Without additional attributes, all incoming and outgoing messages are in addition copied into reading &lt;state&gt;.</p>
<p>If enabled, the module <a href="#autocreate">autocreate</a> is creating a new definition for any unknown group-address. However, the new device will be disabled
 until you added a DPT to the definition and clear the disabled attribute. The name will be KNX_nnmmooo where nn is the line adress, mm the area and ooo the device.
 No FileLog or SVG definition is created for KNX-devices by autocreate. Use for example <code>define &lt;name&gt; FileLog &lt;filename&gt; KNX_.*</code> 
 to create a single FileLog-definition for all KNX-devices created by autocreate.<br />  
 Another option is to disable autocreate for KNX-devices in production environments (when no changes / additions are expected) by using&colon;
 <code>attr &lt;autocreate&gt; ignoreTypes KNX_.*</code></p>

<p>Examples:</p>
<ul>
<code>define lamp1 KNX 0/10/11:dpt1</code><br/>
<code>attr lamp1 webCmd on:off</code><br/>
<code>attr lamp1 devStateIcon on:li_wht_on:off off:li_wht_off:on</code><br/>
<br/>
<code>define lamp2 KNX 0/10/12:dpt1:steuern:set 0/10/13:dpt1.001:status:listenonly</code><br/>
<br/>
<code>define lamp3 KNX 00A0D:dpt1.001</code><br/>
</ul>

<a id="KNX-set"></a>
<p><strong>Set</strong></p>
<p><code>set &lt;deviceName&gt; [gadName] &lt;on|off|toggle&gt;<br />
  set &lt;deviceName&gt; [gadName] &lt;on-for-timer|on-until|off-for-timer|off-until&gt; &lt;timespec&gt;<br />
  set &lt;deviceName&gt; [gadName] &lt;value&gt;<br /></code></p>
<p>Set sends the given value to the bus.<br /> If &lt;gadName&gt; is omitted, the first listed GAD of the device is used. 
 If the GAD is restricted in the definition with "get" or "listenonly", the set-command will be refused.<br /> 
 For dpt1 and dpt1.001 valid values are on, off, toggle and blink. Also the timer-functions can be used. 
 For all other binary DPT (dpt1.xxx) the min- and max-values can be used for en- and decoding alternatively to on/off.<br/> 
 After successful sending the value, it is stored in the readings &lt;setName&gt;.</p>

<a id="KNX-examples"></a>
<p>Examples:</p>
<ul>
<code>set lamp2 on # gadName omitted</code><br/>
<code>set lamp2 off # gadName omitted</code><br/>
<code>set lamp2 steuern on</code><br/>
<code>set lamp2 steuern off</code><br/>
<code>set lamp2 steuern on-for-timer 10</code><br/>
<code>set lamp2 steuern on-until 13:15:00</code><br/>
<code>set lamp3 g1 on-until 13:15:00</code><br/>
<code>set lamp3 g1 toogle    # lamp3 change state</code><br/>
<code>set lamp3 g1 blink 2 4 # lamp3 on for 4 seconds, off for 4 seconds, 2 repeats</code><br/>
<br/>
<code>set myThermoDev g1 23.44</code><br/>
<br/>
<code>set myMessageDev g1 Hello World! # dpt16 def</code><br/>
<p><b>More complex examples </b>can be found on the (german) <a href="http://www.fhemwiki.de/wiki/KNX_Device_Definition_-_Beispiele">Wiki</a></p>
</ul>

<a id="KNX-get"></a>
<p><strong>Get</strong></p>
<p>If you execute "get" for a KNX-Element the status will be requested from the device. The device has to be able to respond to a read -
 this might not be supported by the target device.<br /> 
If the GAD is restricted in the definition with "set", the execution will be refused.<br /> 
The answer from the bus-device updates the readings &lt;getName&gt; and state.</p>

<a id="KNX-attr"></a>
<p><strong>Common attributes</strong></p>
<ol id="KNX-attr_ul"> <!-- use ol as block element -->
<a href="#DbLogattr">DbLogInclude</a><br /> 
<a href="#DbLogattr">DbLogExclude</a><br />
<a href="#DbLogattr">DbLogValueFn</a><br />
<a href="#alias">alias</a><br /> 
<a href="#FHEMWEB-attr-cmdIcon">cmdIcon</a><br />
<a href="#comment">comment</a><br /> 
<a href="#FHEMWEB-attr-devStateIcon">devStateIcon</a><br /> 
<a href="#FHEMWEB-attr-devStateStyle">devStateStyle</a><br /> 
<a href="#readingFnAttributes">event-aggregator</a><br /> 
<a href="#readingFnAttributes">event-min-interval</a><br /> 
<a href="#readingFnAttributes">event-on-change-reading</a><br /> 
<a href="#readingFnAttributes">event-on-update-reading</a><br /> 
<a href="#eventMap">eventMap</a><br />
<a href="#group">group</a><br /> 
<a href="#FHEMWEB-attr-icon">icon</a><br /> 
<a href="#readingFnAttributes">oldreadings</a><br />
<a href="#room">room</a><br /> 
<a href="#showtime">showtime</a><br /> 
<a href="#FHEMWEB-attr-sortby">sortby</a><br /> 
<a href="#readingFnAttributes">stateFormat</a><br />
<a href="#readingFnAttributes">timestamp-on-change-reading</a><br /> 
<a href="#readingFnAttributes">userReadings</a><br /> 
<a href="#userattr">userattr</a><br />
<a href="#verbose">verbose</a><br /> 
<a href="#FHEMWEB-attr-webCmd">webCmd</a><br /> 
<a href="#FHEMWEB-attr-webCmdLabel">webCmdLabel</a><br /> 
<a href="#KNX-attr-widgetOverride">widgetOverride</a>
</ol>

<p><strong>Special attributes</strong></p>
<ul>
<a id="KNX-attr-answerReading"></a><li>answerReading<br/>
  If enabled, FHEM answers on read requests. The content of reading &lt;state&gt; is sent to the bus as answer. 
  If defined, the content of the reading &lt;putName&gt; is used as value for the answer.</li>
<br/>
<a id="KNX-attr-stateRegex"></a><li>stateRegex<br/>
  You can pass n pairs of regex-patterns and strings to replace, seperated by a space. A regex-pair is always in the format /&lt;readingName&gt;[:&lt;value&gt;]/[2nd part]/.
  The first part of the regex must exactly match the readingname, and optional (separated by a colon) the readingValue. If first part match, the matching part will be replaced by the 2nd part of the regex.
  If the 2nd part is empty, the value will be ignored and state-reading is not updated.  
  The substitution is done every time, a reading is updated. You can use this function for converting, adding units, having more fun with icons, ...<br/>
  This function has only an impact on the content of reading state. It is executed directly after replacing the reading-names and processing "format" Attr, but before stateCmd.</li>
<br/>
<a id="KNX-attr-stateCmd"></a><li>stateCmd<br/>
  You can supply a perl-command for modifying state. This command is executed directly before updating the reading - so after renaming, format and regex. 
  Please supply a valid perl command like using the attribute stateFormat.<br/>
  Unlike stateFormat the stateCmd modifies also the content of the reading <b>state</b>, not only the hash-content for visualization.<br/>
  You can access the device-hash ( e.g: $hash{IODev} ) in yr. perl-cmd. In addition the variables "$name", "$gadName" and "$state" are avaliable. 
  A return value must be set and overrides reading "state".</li>
<br/>
<a id="KNX-attr-putCmd"></a> <li>putCmd<br/>
  Every time a KNX-value is requested from the bus to FHEM, the content of putCmd is evaluated before the answer is sent. You can use a perl-command for modifying content. 
  If putCmd is defined, the attr "answerReading" has no effect.
  This command is executed directly before sending the data. A copy is stored in the reading &lt;putName&gt;.<br/>
  Each device only knows one putCmd, so you have to take care about the different GAD's in the perl string.<br/>
  Like in stateCmd you can access the device hash ("$hash") in yr. perl-cmd. In addition the variables "$name", "$gadName" and "$state" are avaliable. 
  "$state" contains the prefilled return-value. The return-value overrides reading "state".</li>
<br/>
<a id="KNX-attr-format"></a><li>format<br/>
  The content of this attribute is appended to every sent/received value before readings are set, it replaces the default unit-value! 
  "format" will be appied to ALL readings, it is better to use the (more complex) "stateCmd" or "stateRegex" Attributes if you have more than one GAD in your device.</li>
<br/>
<a id="KNX-attr-disable"></a><li>disable<br/>
  Disable the device if set to <b>1</b>. No send/receive from bus and no set/get possible. Delete this attr to enable device again. 
  As an aid for debugging, an additional INTERNAL: &lt;RAWMSG&gt; will show any message received from bus while the device is disabled.</li>
<br/>
<a id="KNX-attr-KNX_toggle"></a><li>KNX_toggle<br/>
  Lookup current value before issuing "set device &lt;gadName&gt; toggle" cmd.<br/> 
  FHEM has to retrieve a current value to make the toggle-cmd acting correctly. This attribute can be used to define the source of the current value.<br/>
  Format is: <b>&lt;devicename&gt;&colon;&lt;readingname&gt;</b>. If you want to use a reading from own device, you can use "$self" as devicename.
  Be aware that only <b>on</b> and <b>off</b> are supported as valid values when defining device:readingname.<br/>
  If this attribute is not defined, the current value will be taken from owndevice:readingName-get or, if readingName-get is not defined, 
  the value will be taken from readingName-set.</li>
<br/>
<a id="KNX-attr-IODev"></a><li>IODev<br/>
  Due to changes in IO-Device handling, (default IO-Device will be stored in <b>reading IODev</b>), setting this Attribute is no longer required,  
  except in cases where multiple IO-devices (of type TUL/KNXTUL/KNXIO) exist in your config. Defining more than one IO-device is <b>NOT recommended</b> 
  unless you take special care with yr. knxd or KNX-router definitions - to prevent multiple path from KNX-Bus to FHEM resulting in message loops.</li>   
<br/>
<a id="KNX-attr-widgetOverride"></a><li>widgetOverride<br/>
  This is a standard FHEMWEB-attribute, the recommendation for use in KNX-module is to specify the following form:
  <b>&lt;gadName&gt;@set&colon;&lt;widgetName,parameter&gt;</b> This avoids overwriting the GET pulldown in FHEMWEB detail page.
  For details, pls see <a href="#FHEMWEB-attr-widgetOverride">FHEMWEB-attribute</a>.</li>
<br/>
<a id="KNX-attr-listenonly"></a><li>listenonly - This attr is deprecated - use "listenonly" option in device definition</li> 
<a id="KNX-attr-readonly"></a><li>readonly - This attr is deprecated - use "get" option in device definition</li>
<a id="KNX-attr-slider"></a><li>slider - This attr is deprecated - use attribute widgetOverride &lt;gadName&gt;:slider,&lt;start-&gt;,&lt;step-&gt;,&lt;end-range&gt; instead</li>
</ul>

<a id="KNX-dpt"></a>
<p><strong>DPT - data-point-types</strong></p>
<p>The following dpt are implemented and have to be assigned within the device definition. 
   The values right to the dpt define the valid range of Set-command values and Get-command return values and units.</p>
<ol id="KNX-dpt_ul">
<li><b>dpt1     </b>  off, on, toggle</li>
<li><b>dpt1.000 </b>  0, 1</li>
<li><b>dpt1.001 </b>  off, on, toggle</li>
<li><b>dpt1.002 </b>  false, true</li>
<li><b>dpt1.003 </b>  disable, enable</li>
<li><b>dpt1.004 </b>  no_ramp, ramp</li>
<li><b>dpt1.005 </b>  no_alarm, alarm</li>
<li><b>dpt1.006 </b>  low, high</li>
<li><b>dpt1.007 </b>  decrease, increase</li>
<li><b>dpt1.008 </b>  up, down</li>
<li><b>dpt1.009 </b>  open, closed</li>
<li><b>dpt1.010 </b>  stop, start</li>
<li><b>dpt1.011 </b>  inactive, active</li>
<li><b>dpt1.012 </b>  not_inverted, inverted</li>
<li><b>dpt1.013 </b>  start/stop, ciclically</li>
<li><b>dpt1.014 </b>  fixed, calculated</li>
<li><b>dpt1.015 </b>  no_action, reset</li>
<li><b>dpt1.016 </b>  no_action, acknowledge</li>
<li><b>dpt1.017 </b>  trigger_0, trigger_1</li>
<li><b>dpt1.018 </b>  not_occupied, occupied</li>
<li><b>dpt1.019 </b>  closed, open</li>
<li><b>dpt1.021 </b>  logical_or, logical_and</li>
<li><b>dpt1.022 </b>  scene_A, scene_B</li>
<li><b>dpt1.023 </b>  move_up/down, move_and_step_mode</li>
<li><b>dpt2     </b>  off, on, forceOff, forceOn</li>
<li><b>dpt2.000 </b>  0,1,2,3</li>
<li><b>dpt3     </b>  -100..+100</li>
<li><b>dpt3.007 </b>  -100..+100 %</li>
<li><b>dpt3.008 </b>  -100..+100 %</li>
<li><b>dpt4     </b>  single char</li>
<li><b>dpt4.001 </b>  ascii char</li>
<li><b>dpt4.002 </b>  ISO-8859-1 char</li>
<li><b>dpt5     </b>  0..255</li>
<li><b>dpt5.001 </b>  0..100 %</li>
<li><b>dpt5.003 </b>  0..360 &deg;</li>
<li><b>dpt5.004 </b>  0..255 %</li>
<li><b>dpt5.010 </b>  0..255 p</li>
<li><b>dpt6     </b>  -128..+127</li>
<li><b>dpt6.001 </b>  -128 %..+127 %</li>
<li><b>dpt6.010 </b>  -128..+127</li>
<li><b>dpt7     </b>  0..65535</li>
<li><b>dpt7.001 </b>  0..65535 s</li>
<li><b>dpt7.005 </b>  0..65535 s</li>
<li><b>dpt7.006 </b>  0..65535 m</li>
<li><b>dpt7.007 </b>  0..65535 h</li>
<li><b>dpt7.012 </b>  0..65535 mA</li>
<li><b>dpt7.013 </b>  0..65535 lux</li>
<li><b>dpt7.600 </b>  0..12000 K</li>
<li><b>dpt8     </b>  -32768..32767</li>
<li><b>dpt8.001 </b>  -32768..32767 pulsecount</li>
<li><b>dpt8.003 </b>  -327.68..327.67 s</li>
<li><b>dpt8.004 </b>  -3276.8..3276.7 s</li>
<li><b>dpt8.005 </b>  -32768..32767 s</li>
<li><b>dpt8.006 </b>  -32768..32767 min</li>
<li><b>dpt8.007 </b>  -32768..32767 h</li>
<li><b>dpt8.010 </b>  -32768..32767 %</li>
<li><b>dpt8.011 </b>  -32768..32767 &deg;</li>
<li><b>dpt9     </b>  -670760.0..+670760.0</li>
<li><b>dpt9.001 </b>  -274.0..+670760.0 &deg;C</li>
<li><b>dpt9.002 </b>  -670760.0..+670760.0 K</li>
<li><b>dpt9.003 </b>  -670760.0..+670760.0 K/h</li>
<li><b>dpt9.004 </b>  -670760.0..+670760.0 lux</li>
<li><b>dpt9.005 </b>  -670760.0..+670760.0 m/s</li>
<li><b>dpt9.006 </b>  -670760.0..+670760.0 Pa</li>
<li><b>dpt9.007 </b>  -670760.0..+670760.0 %</li>
<li><b>dpt9.008 </b>  -670760.0..+670760.0 ppm</li>
<li><b>dpt9.009 </b>  -670760.0..+670760.0 m&sup3;/h</li>
<li><b>dpt9.010 </b>  -670760.0..+670760.0 s</li>
<li><b>dpt9.011 </b>  -670760.0..+670760.0 ms</li>
<li><b>dpt9.020 </b>  -670760.0..+670760.0 mV</li>
<li><b>dpt9.021 </b>  -670760.0..+670760.0 mA</li>
<li><b>dpt9.022 </b>  -670760.0..+670760.0 W/m&sup2;</li>
<li><b>dpt9.023 </b>  -670760.0..+670760.0 K/%</li>
<li><b>dpt9.024 </b>  -670760.0..+670760.0 kW</li>
<li><b>dpt9.025 </b>  -670760.0..+670760.0 l/h</li>
<li><b>dpt9.026 </b>  -670760.0..+670760.0 l/h</li>
<li><b>dpt9.027 </b>  -459.6..+670760.0 &deg;F</li>
<li><b>dpt9.028 </b>  -670760.0..+670760.0 km/h</li>
<li><b>dpt9.029 </b>  -670760.0..+670760.0 g/m&sup3;</li>
<li><b>dpt9.030 </b>  -670760.0..+670760.0 &mu;g/m&sup3;</li>
<li><b>dpt10    </b>  01:00:00 (Time: HH:MM:SS)</li>
<li><b>dpt11    </b>  01.01.2000 (Date: DD.MM.YYYY)</li>
<li><b>dpt12    </b>  0..+Inf</li>
<li><b>dpt13    </b>  -Inf..+Inf</li>
<li><b>dpt13.010</b>  -Inf..+Inf Wh</li>
<li><b>dpt13.013</b>  -Inf..+Inf kWh</li>
<li><b>dpt14    </b>  -Inf.0..+Inf.0</li>
<li><b>dpt14.007</b>  -Inf.0..+Inf.0 &deg;</li>
<li><b>dpt14.019</b>  -Inf.0..+Inf.0 A</li>
<li><b>dpt14.027</b>  -Inf.0..+Inf.0 V</li>
<li><b>dpt14.033</b>  -Inf.0..+Inf.0 Hz</li>
<li><b>dpt14.039</b>  -Inf.0..+Inf.0 m</li>
<li><b>dpt14.056</b>  -Inf.0..+Inf.0 W</li>
<li><b>dpt14.057</b>  -Inf.0..+Inf.0 cos&phi;</li>
<li><b>dpt14.068</b>  -Inf.0..+Inf.0 &deg;C</li>
<li><b>dpt14.076</b>  -Inf.0..+Inf.0 m&sup3;</li>
<li><b>dpt15.000</b>  Access-code - receive only!</li>
<li><b>dpt16    </b>  14 char string</li>
<li><b>dpt16.000</b>  ASCII string</li>
<li><b>dpt16.001</b>  ISO-8859-1 string (Latin1)</li>
<li><b>dpt17.001</b>  Scene Nr: 0..63</li>
<li><b>dpt18.001</b>  Scene Nr: 1..64. - only "activation" works..</li>
<li><b>dpt19    </b>  01.12.2020_01:02:03 (Date&amp;Time)</li>
<li><b>dpt19.001</b>  01.12.2020_01:02:03</li>
<li><b>dpt20.102</b>  HVAC mode</li>
<li><b>dpt22.101</b>  HVAC RHCC Status (readonly)</li>
<li><b>dpt217.001</b>  dpt version (readonly)</li>
<li><b>dpt232    </b>  RGB-Value RRGGBB</li>
</ol>

<a id="KNX-utilities"></a>
<p><strong>KNX Utility Functions</strong></p>
<ul>
<li><b>KNX_scan</b> Function to be called from scripts or FHEM cmdline. 
<br/>Selects all KNX-definitions (specified by the argument) that support a "get" from the device. 
Issues a "get" cmd to each selected device/GAD. 
The result of the "get" cmd  will be stored in the respective readings - same as a <code>get &lt;device&gt; &lt;gadName&gt;</code> from cmd-line. 
<br/>Useful after a fhem-start to syncronize the readings with the status of the KNX-device.
<br/>The "get" cmds are scheduled asynchronous, with a delay of 200ms between each get. (avoid overloading KNX-bus) 
Returns number of "get's" issued.<br/>
<br/>Examples:
<pre>
<code>syntax when used as perl-function (eg. in at, notify,...)</code>
<code>   KNX_scan()                    - scan all possible devices</code>
<code>   KNX_scan('dev-A')             - scan device-A only</code>
<code>   KNX_scan('dev-A,dev-B,dev-C') - scan device-A, device-B, device-C</code>
<code>   KNX_scan('room=Kueche')       - scan all KNX-devices in room Kueche</code>
<code>   KNX_scan('EG_.*')             - scan all KNX-devices where device-names begin with EG_</code> 
<code>syntax when used from FHEM-cmdline</code>
<code>   KNX_scan                      - scan all possible devices</code>
<code>   KNX_scan dev-A                - scan device-A only</code>
<code>   KNX_scan dev-A,dev-B,dev-C    - scan device-A, device-B, device-C</code>
<code>   KNX_scan room=Kueche          - scan all KNX-devices in room Kueche</code>
<code>   KNX_scan EG_.*                - scan all KNX-devices where device-names begin with EG_</code>
</pre>
When using KNX_scan or any 'set or get &lt;device&gt; ...' in a global:INITIALIZED notify, pls. ensure to have some delay in processing the cmd's by using <b>fhem sleep</b>.
<br/>Example:<br/>
<code>defmod initialized_nf notify global:INITIALIZED sleep 10 quiet;; set KNX_date now;; set KNX_time now;; KNX_scan;;</code>
<br/>This avoids sending requests while the KNX-Gateway has not finished its initial handshake-procedure with FHEM (the KNX-IO-device).  
<!--
<br/><br/>If you want to use this function as a FHEM cmd, define a cmdalias-device, e.g:<br/>
<code>defmod cmd_KNXscan cmdalias knxscan .* AS { my $res = KNX_scan($EVTPART0);; return 'Number of GAs scanned: '. $res;; }</code>
-->
<br/>
</li>
</ul>
</ul>
<br/>

=end html

=cut
