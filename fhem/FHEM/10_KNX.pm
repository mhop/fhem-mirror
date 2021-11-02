##############################################
# $Id$  
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


package FHEM::KNX; ## no critic 'package'

use strict;
use warnings;
use Encode qw(encode decode);
use Time::HiRes qw(gettimeofday);
use Scalar::Util qw(looks_like_number);
#use SetExtensions; # not yet!
use GPUtils qw(GP_Import GP_Export); # Package Helper Fn

### perlcritic parameters
# these ones are NOT used! (constants,Policy::Modules::RequireFilenameMatchesPackage,Modules::RequireVersionVar,NamingConventions::Capitalization)
### the following percritic items will be ignored global ###
## no critic (ValuesAndExpressions::RequireNumberSeparators,ValuesAndExpressions::ProhibitMagicNumbers)
## no critic (RegularExpressions::RequireDotMatchAnything,RegularExpressions::RequireLineBoundaryMatching)
## no critic (ControlStructures::ProhibitPostfixControls)
### no critic (ControlStructures::ProhibitCascadingIfElse)
## no critic (Documentation::RequirePodSections)

### import FHEM functions / global vars
### run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate readingsBulkUpdate readingsBulkUpdateIfChanged readingsBeginUpdate readingsEndUpdate
          Log3
          AttrVal ReadingsVal ReadingsNum
          addToDevAttrList  
          AssignIoPort IOWrite
          CommandDefMod CommandModify CommandDelete
          defs modules attr
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

### export to main context (with different name)
GP_Export(qw(Initialize));

#string constants
my $MODELERR    = "MODEL_NOT_DEFINED"; # for autocreate

#my $ONFORTIMER  = "on-for-timer";
#my $OFFFORTIMER = "off-for-timer";
#my $ONUNTIL     = "on-until";
#my $OFFUNTIL    = "off-until";
my $BLINK       = "blink";
my $TOGGLE      = "toggle";
my $RAW         = "raw";
my $RGB         = "rgb";
my $STRING      = "string";
my $VALUE       = "value";

my $TULid       = 'C'; #identifier for TUL - extended adressing

#regex patterns
#pattern for group-adress
my $PAT_GAD = '(?:3[01]|([012])?[0-9])\/(?:1[0-5]|[0-9])\/(?:2[0-4][0-9]|25[0-5]|([01])?[0-9]{1,2})'; # 0-31/0-15/0-255
#pattern for group-adress in hex-format
my $PAT_GAD_HEX = '[01][0-9a-f]{4}'; # max is 1FFFF -> 31/15/255
#pattern for group-no
my $PAT_GNO = '[gG][1-9][0-9]?';
#pattern for GAD-Options
my $PAT_GAD_OPTIONS = 'get|set|listenonly'; 
#pattern for GAD-suffixes
my $PAT_GAD_SUFFIX = 'nosuffix';
#pattern for forbidden GAD-Names
my $PAT_GAD_NONAME = '^(on|off|value|raw|' . $PAT_GAD_OPTIONS . q{|} . $PAT_GAD_SUFFIX . ')';
#pattern for DPT
my $PAT_GAD_DPT = 'dpt\d*\.?\d*';
#pattern for dpt1 (standard)
my $PAT_DPT1_PAT = '(on)|(off)|(0?1)|(0?0)';
#pattern for date
my $PAT_DTSEP = qr/(?:_)/ix; # date/time separator
my $PAT_DATE = qr/(3[01]|[0-2]?[0-9])\.(1[0-2]|0?[0-9])\.((?:19|20)[0-9][0-9])/ix;
#pattern for time
my $PAT_TIME = qr/(2[0-4]|[0?1][0-9]):([0?1-5][0-9]):([0?1-5][0-9])/ix;
my $PAT_DPT16_CLR = qr/>CLR</ix;

#CODE is the identifier for the en- and decode algos. See encode and decode functions
#UNIT is appended to state for a better reading
#FACTOR and OFFSET are used to normalize a value. value = FACTOR * (RAW - OFFSET). Must be undef for non-numeric values.
#PATTERN is used to check an trim the input-values
#MIN and MAX are used to cast numeric values. Must be undef for non-numeric dpt. Special Usecase: DPT1 - MIN represents 00, MAX represents 01
#if supplied, setlist is passed directly to fhemweb in order to show comand-buttons in the details-view (e.g. "colorpicker" or "item1,item2,item3")
#if setlist is not supplied and min/max are given, a slider is shown for numeric values. Otherwise min/max value are shown in a list
my %dpttypes = (
	#Binary value
#	'dpt1'          => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ix, MIN=>'off', MAX=>'on', SETLIST=>'on,off,toggle'},
	'dpt1'          => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ix, MIN=>'off', MAX=>'on', SETLIST=>'on,off,toggle',
                            DEC=>\&dec_dpt1,ENC=>\&enc_dpt1,},
	'dpt1.000'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ix, MIN=>0, MAX=>1},
	'dpt1.001'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT)/ix, MIN=>'off', MAX=>'on', SETLIST=>'on,off,toggle'},
	'dpt1.002'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|true|false)/ix, MIN=>'false', MAX=>'true'},
	'dpt1.003'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|enable|disable)/ix, MIN=>'disable', MAX=>'enable'},
	'dpt1.004'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_ramp|ramp)/ix, MIN=>'no_ramp', MAX=>'ramp'},
	'dpt1.005'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_alarm|alarm)/ix, MIN=>'no_alarm', MAX=>'alarm'},
	'dpt1.006'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|low|high)/ix, MIN=>'low', MAX=>'high'},
	'dpt1.007'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|decrease|increase)/ix, MIN=>'decrease', MAX=>'increase'},
	'dpt1.008'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|up|down)/ix, MIN=>'up', MAX=>'down'},
	'dpt1.009'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|closed|open)/ix, MIN=>'open', MAX=>'closed'},
	'dpt1.010'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|start|stop)/ix, MIN=>'stop', MAX=>'start'},
	'dpt1.011'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|inactive|active)/ix, MIN=>'inactive', MAX=>'active'},
	'dpt1.012'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|not_inverted|inverted)/ix, MIN=>'not_inverted', MAX=>'inverted'},
	'dpt1.013'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|start_stop|cyclically)/ix, MIN=>'start_stop', MAX=>'cyclically'},
	'dpt1.014'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|fixed|calculated)/ix, MIN=>'fixed', MAX=>'calculated'},
	'dpt1.015'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_action|reset)/ix, MIN=>'no_action', MAX=>'reset'},
	'dpt1.016'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|no_action|acknowledge)/ix, MIN=>'no_action', MAX=>'acknowledge'},
	'dpt1.017'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|trigger_0|trigger_1)/ix, MIN=>'trigger_0', MAX=>'trigger_1', SETLIST=>'trigger_0,trigger_1',},
	'dpt1.018'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|not_occupied|occupied)/ix, MIN=>'not_occupied', MAX=>'occupied'},
	'dpt1.019'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|closed|open)/ix, MIN=>'closed', MAX=>'open'},
	'dpt1.021'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|logical_or|logical_and)/ix, MIN=>'logical_or', MAX=>'logical_and'},
	'dpt1.022'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|scene_A|scene_B)/ix, MIN=>'scene_A', MAX=>'scene_B'},
	'dpt1.023'      => {CODE=>'dpt1', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DPT1_PAT|move_(up_down|and_step_mode))/ix, MIN=>'move_up_down', MAX=>'move_and_step_mode'},

	#Step value (two-bit)
	'dpt2'          => {CODE=>'dpt2', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(on|off|forceon|forceoff)/ix, MIN=>undef, MAX=>undef, SETLIST=>'on,off,forceon,forceoff',
                            DEC=>\&dec_dpt2,ENC=>\&enc_dpt2,},
	'dpt2.000'      => {CODE=>'dpt2', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/(0?[0-3])/ix, MIN=>0, MAX=>3},

	#Step value (four-bit)
	'dpt3'          => {CODE=>'dpt3', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>-100, MAX=>100,
                            DEC=>\&dec_dpt3,ENC=>\&enc_dpt3,},
	'dpt3.007'      => {CODE=>'dpt3', UNIT=>q{%}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>-100, MAX=>100},

	# 1-Octet unsigned value
	'dpt5'          => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>255,
                            DEC=>\&dec_dpt5,ENC=>\&enc_dpt5,},
	'dpt5.001'      => {CODE=>'dpt5', UNIT=>q{%}, FACTOR=>100/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>100},  
	'dpt5.003'      => {CODE=>'dpt5', UNIT=>q{&deg;}, FACTOR=>360/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>360},
	'dpt5.004'      => {CODE=>'dpt5', UNIT=>q{%}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>255},

	# 1-Octet signed value
	'dpt6'          => {CODE=>'dpt6', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>-128, MAX=>127,
                            DEC=>\&dec_dpt6,ENC=>\&enc_dpt6,},
	'dpt6.001'      => {CODE=>'dpt6', UNIT=>q{%}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>100},
	'dpt6.010'      => {CODE=>'dpt6', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>-128, MAX=>127},

	# 2-Octet unsigned Value 
	'dpt7'          => {CODE=>'dpt7', UNIT=>q{},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535,
                            DEC=>\&dec_dpt7,ENC=>\&enc_dpt7,},
	'dpt7.001'      => {CODE=>'dpt7', UNIT=>q{},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535},
	'dpt7.005'      => {CODE=>'dpt7', UNIT=>q{s},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535},
	'dpt7.006'      => {CODE=>'dpt7', UNIT=>q{m},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535},
	'dpt7.007'      => {CODE=>'dpt7', UNIT=>q{h},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535},
	'dpt7.012'      => {CODE=>'dpt7', UNIT=>q{mA},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535},
	'dpt7.013'      => {CODE=>'dpt7', UNIT=>q{lux}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>0, MAX=>65535},
	'dpt7.600'      => {CODE=>'dpt7', UNIT=>q{K},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+]?\d{1,5}/ix,  MIN=>0, MAX=>12000},  # Farbtemperatur

	# 2-Octet signed Value 
	'dpt8'          => {CODE=>'dpt8', UNIT=>q{},      FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>-32768, MAX=>32767,
                            DEC=>\&dec_dpt8,ENC=>\&enc_dpt8,},
	'dpt8.005'      => {CODE=>'dpt8', UNIT=>q{s},     FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>-32768, MAX=>32767},
	'dpt8.010'      => {CODE=>'dpt8', UNIT=>q{%},     FACTOR=>0.01, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>-327.68, MAX=>327.67}, # min/max
	'dpt8.011'      => {CODE=>'dpt8', UNIT=>q{&deg;}, FACTOR=>1,    OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/ix, MIN=>-32768, MAX=>32767},

	# 2-Octet Float value
	'dpt9'          => {CODE=>'dpt9', UNIT=>q{},     FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760,
                            DEC=>\&dec_dpt9,ENC=>\&enc_dpt9,},
	'dpt9.001'      => {CODE=>'dpt9', UNIT=>q{&deg;C}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-274, MAX=>670760},
	'dpt9.002'      => {CODE=>'dpt9', UNIT=>q{K},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.003'      => {CODE=>'dpt9', UNIT=>q{K/h},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.004'      => {CODE=>'dpt9', UNIT=>q{lux},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.005'      => {CODE=>'dpt9', UNIT=>q{m/s},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.006'      => {CODE=>'dpt9', UNIT=>q{Pa},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.007'      => {CODE=>'dpt9', UNIT=>q{%},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.008'      => {CODE=>'dpt9', UNIT=>q{ppm},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.009'      => {CODE=>'dpt9', UNIT=>q{m&sup3;/h}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.010'      => {CODE=>'dpt9', UNIT=>q{s},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.011'      => {CODE=>'dpt9', UNIT=>q{ms},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.020'      => {CODE=>'dpt9', UNIT=>q{mV},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.021'      => {CODE=>'dpt9', UNIT=>q{mA},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.022'      => {CODE=>'dpt9', UNIT=>q{W/m&sup2;}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.023'      => {CODE=>'dpt9', UNIT=>q{K/%},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.024'      => {CODE=>'dpt9', UNIT=>q{kW},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.025'      => {CODE=>'dpt9', UNIT=>q{l/h},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.026'      => {CODE=>'dpt9', UNIT=>q{l/h},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.028'      => {CODE=>'dpt9', UNIT=>q{km/h}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760},
	'dpt9.029'      => {CODE=>'dpt9', UNIT=>q{g/m&sup3;}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760}, # Abs. Luftfeuchte
	'dpt9.030'      => {CODE=>'dpt9', UNIT=>q{&mu;g/m&sup3;}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/ix, MIN=>-670760, MAX=>670760}, # Dichte

	# Time of Day
	'dpt10'         => {CODE=>'dpt10', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_TIME|now)/ix, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt10,ENC=>\&enc_dpt10,},

	# Date  
	'dpt11'         => {CODE=>'dpt11', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DATE|now)/ix, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt11,ENC=>\&enc_dpt11,},

	# 4-Octet unsigned value (handled as dpt7)
	'dpt12'         => {CODE=>'dpt12', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ix, MIN=>0, MAX=>4294967295,
                            DEC=>\&dec_dpt12,ENC=>\&enc_dpt12,},

	# 4-Octet Signed Value
	'dpt13'         => {CODE=>'dpt13', UNIT=>q{},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ix, MIN=>-2147483648, MAX=>2147483647,
                            DEC=>\&dec_dpt13,ENC=>\&enc_dpt13,},
	'dpt13.010'     => {CODE=>'dpt13', UNIT=>q{Wh},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ix, MIN=>-2147483648, MAX=>2147483647},
	'dpt13.013'     => {CODE=>'dpt13', UNIT=>q{kWh}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/ix, MIN=>-2147483648, MAX=>2147483647},

	# 4-Octet single precision float
	'dpt14'         => {CODE=>'dpt14', UNIT=>q{},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt14,ENC=>\&enc_dpt14,},
	'dpt14.019'     => {CODE=>'dpt14', UNIT=>q{A},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},
	'dpt14.027'     => {CODE=>'dpt14', UNIT=>q{V},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},
	'dpt14.033'     => {CODE=>'dpt14', UNIT=>q{Hz}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},
	'dpt14.056'     => {CODE=>'dpt14', UNIT=>q{W},  FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},
	'dpt14.068'     => {CODE=>'dpt14', UNIT=>q{&deg;C},    FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},
	'dpt14.076'     => {CODE=>'dpt14', UNIT=>q{m&sup3;},   FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},
	'dpt14.057'     => {CODE=>'dpt14', UNIT=>q{cos &Phi;}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/ix, MIN=>undef, MAX=>undef},

	# 14-Octet String
	'dpt16'         => {CODE=>'dpt16', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/ix, MIN=>undef, MAX=>undef, SETLIST=>'multiple,>CLR<',
                            DEC=>\&dec_dpt16,ENC=>\&enc_dpt16,},
	'dpt16.000'     => {CODE=>'dpt16', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/ix, MIN=>undef, MAX=>undef, SETLIST=>'multiple,>CLR<'},
	'dpt16.001'     => {CODE=>'dpt16', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/ix, MIN=>undef, MAX=>undef, SETLIST=>'multiple,>CLR<'},

	# Scene, 0-63
	'dpt17'         => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>63,
                            DEC=>\&dec_dpt5,ENC=>\&enc_dpt5,},
	'dpt17.001'     => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>0, MAX=>63},

	# Scene, 1-64
	'dpt18'         => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>1, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>1, MAX=>64,
                            DEC=>\&dec_dpt5,ENC=>\&enc_dpt5,},
	'dpt18.001'     => {CODE=>'dpt5', UNIT=>q{}, FACTOR=>1, OFFSET=>1, PATTERN=>qr/[+-]?\d{1,3}/ix, MIN=>1, MAX=>64},
	
	#date and time
	'dpt19'         => {CODE=>'dpt19', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DATE$PAT_DTSEP$PAT_TIME|now)/ix, MIN=>undef, MAX=>undef,
                            DEC=>\&dec_dpt19,ENC=>\&enc_dpt19,},
	'dpt19.001'     => {CODE=>'dpt19', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/($PAT_DATE$PAT_DTSEP$PAT_TIME|now)/ix, MIN=>undef, MAX=>undef},

	# HVAC mode, 1Byte
	'dpt20'         => {CODE=>'dpt20', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/(auto|comfort|standby|(economy|night)|(protection|frost|heat))/ix, MIN=>undef, MAX=>undef, ## no critic (RegularExpressions::ProhibitComplexRegexes)
                            SETLIST=>'Auto,Comfort,Standby,Economy,Protection', DEC=>\&dec_dpt20,ENC=>\&enc_dpt20,},
	'dpt20.102'     => {CODE=>'dpt20', UNIT=>q{}, FACTOR=>1, OFFSET=>0, PATTERN=>qr/(auto|comfort|standby|(economy|night)|(protection|frost|heat))/ix, MIN=>undef, MAX=>undef, ## no critic (RegularExpressions::ProhibitComplexRegexes)
                            SETLIST=>'Auto,Comfort,Standby,Economy,Protection'},

	# Color-Code
	'dpt232'        => {CODE=>'dpt232', UNIT=>q{}, FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[0-9a-f]{6}/ix, MIN=>undef, MAX=>undef, SETLIST=>'colorpicker',
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
#	$hash->{NotifyFn}       = \&KNX_Notify; # not needed!
	$hash->{AttrFn}         = \&KNX_Attr;
	$hash->{DbLog_splitFn}  = \&KNX_DbLog_split;
#	$hash->{FingerprintFn}  = \&KNX_FingerPrint;

	$hash->{AttrList}       = "IODev " . #tells the module the IO-Device to communicate with. Optionally set within definition.
            "disable:1 " .                   #device disabled 
            "showtime:1,0 " .                #shows time instead of received value in state
            "answerReading:1,0 " .           #allows FHEM to answer a read telegram
            "stateRegex:textField-long " .   #modifies state value
            "stateCmd:textField-long " .     #modify state value
            "putCmd:textField-long " .       #called when the KNX bus asks for a -put reading
            "format " .                      #supplies post-string
            "KNX_toggle:textField " .        #toggle source <device>:<reading>
            "listenonly:1,0 " .              #DEPRECATED
            "readonly:1,0 " .                #DEPRECATED
            "slider " .                      #DEPRECATED
            "$readingFnAttributes ";         #standard attributes
	$hash->{noAutocreatedFilelog} = 1;   # autocreate devices create no FileLog
	$hash->{AutoCreate} = {"KNX_.*"  => { ATTR => "disable:1"} };  # autocreate devices are disabled by default

	return;
}

#Define this device
#Is called at every define
#############################
sub KNX_Define {
	my $hash = shift // return;
	my $def = shift;
	#enable newline within define with \
	my @a = split(/[ \t\n]+/x, $def);
	#device name
	my $name = $a[0];

	$hash->{NAME} = $name;

	Log3 ($name, 5, "KNX_define -enter: $name, attributes: " . join (", ", @a));
	
	#too less arguments
	return 'KNX_define: $name -wrong syntax "define <name> KNX <group:model[:GAD-name][:set|get|listenonly]> [<group:model[:GAD-name][:set|get|listenonly]>*]" ' if (int(@a) < 3);

	# check if the last arg matches any IO-Device - and assign it - else use the automatic mechanism
	if ( $a[int(@a) - 1] !~ m/^(?:$PAT_GAD|$PAT_GAD_HEX)/ix ) {
		my $iodevCandidate = pop(@a); 
		my @tulList = devspec2array('TYPE=(TUL|KNXTUL|KNXIO)',$hash);
		my $found = undef;
		foreach my $tuls (@tulList) {
			if ($tuls eq $iodevCandidate) {
				$found = 1;
				$attr{$name}{IODev} = $iodevCandidate;
				Log3 ($name, 3, "KNX_define ($name): specifying IODev $iodevCandidate is deprecated in define - see cmd-ref");
				last;
			}
		}
		Log3 ($name, 3, "KNX_define ($name): invalid IODev $iodevCandidate specified - ignored") if (! defined($found));
	}
	AssignIoPort($hash); # AssignIoPort will take device from $attr{$name}{IODev} if defined

	#reset
	$hash->{GADDETAILS} = {};
	$hash->{GADTABLE} = {};

	#delete all defptr entries for this device (defmod & copy problem) bug is still in SVN version! 09-02-2021
	KNX_delete_defptr($hash) if ($init_done); # verify with: {PrintHash($modules{KNX}{defptr},3) } on FHEM-cmdline
	
	#create groups and models, iterate through all possible args
	foreach my $i (2 .. $#a) { 
		my $gadCode = undef;
		my $gadOption = undef;
		my $gadNoSuffix = undef;

		Log3 ($name, 5, "KNX_define ($name):, argCtr $i, string: $a[$i]");

		#G-nr
		my $gadNo = $i - 1;
		my $gadName = 'g' . $gadNo; # old syntax

		my ($gad, $gadModel, @gadArgs) = split(/:/x, $a[$i]);
		$gadCode = $gad // return "GAD not defined for group-number $gadNo";
		return "KNX_define ($name): -wrong GA format in group-number $gadNo: specify as 0-31/0-15/0-255 or as hex-notation" if ($gad !~ m/^(?:$PAT_GAD|$PAT_GAD_HEX)$/ix);

		#new syntax for extended adressing
		$gad = KNX_hexToName ($gad) if ($gad =~ m/^$PAT_GAD_HEX$/ix);

		#convert it vice-versa, just to be sure
		$gadCode = KNX_nameToHex ($gad);

		if(! defined($gadModel)) { 
			return "KNX_define ($name): -no model defined for group-number $gadNo";
		}
		else {
			#within autocreate no model is supplied - throw warning
			if ($gadModel eq $MODELERR) {
				Log3 ($name, 3, "KNX_define ($name): -autocreate device will be disabled, correct def with valid dpt and enable device") if ($init_done);
			}
			elsif (!defined($dpttypes{$gadModel})) { #check model-type
				return "KNX_define ($name): -invalid model: $gadModel for group-number $gadNo. Please consult commanref - available DPT for correct model definition.";
			}
		}

		if ($gadModel ne $MODELERR && $gadNo == 1) { # for fheminfo statistic only
			($hash->{model} = lc($gadModel)) =~ s/^(dpt[\d]+)\..*/$1/x; # use first gad as mdl reference for fheminfo
			# $hash->{model} = lc($gadModel) # this is too much!
		}

		if (@gadArgs) {
			if ($gadArgs[0] =~ m/^($PAT_GAD_OPTIONS)$/ix) { # no gadname given
				unshift ( @gadArgs , 'dummy' ); # shift option up in array
			}
			elsif ($gadArgs[0] =~ m/^$PAT_GAD_NONAME$/ix) { # check for forbidden names forum #122582
				return  "KNX_define ($name): -forbidden gad-name: $gadArgs[0]";
			}
			else {
				$gadName = $gadArgs[0]; # new syntax
			}

			$gadOption = $gadArgs[1] if(defined($gadArgs[1]) && $gadArgs[1] =~ m/($PAT_GAD_OPTIONS)/ix);
			$gadNoSuffix = 'noSuffix' if (join(q{ },@gadArgs) =~ m/nosuffix/ix);

			return "KNX_define ($name): -invalid option for group-number $gadNo. Use one of: $PAT_GAD_OPTIONS" if (defined($gadOption) && ($gadOption !~ m/^(?:$PAT_GAD_OPTIONS)$/ix)); #PBP
			return "KNX_define ($name): -invalid suffix for group-number $gadNo. Use $PAT_GAD_SUFFIX" if (defined($gadNoSuffix) && ($gadNoSuffix !~ m/$PAT_GAD_SUFFIX/ix));
		}

		#save 1st gadName for later backwardCompatibility
		$hash->{FIRSTGADNAME} = $gadName if ($gadNo == 1);

		###GADTABLE
		#create a hash with gadCode and gadName for later mapping
		my $tableHashRef = $hash->{GADTABLE};
		#if not defined yet, define a new hash
		if (not(defined($tableHashRef))) {
			$tableHashRef={};
			$hash->{GADTABLE}=$tableHashRef;
		}
		###GADTABLE

		return "KNX_define ($name): -GAD $gad may be supplied only once per device." if (defined ($tableHashRef->{$gadCode}));

		#cache suffixes
		my $suffixGet = q{-get};
		my $suffixSet = q{-set};
		my $suffixPut = q{-put};
		if (defined ($gadNoSuffix)) {
			$suffixGet = q{};
			$suffixSet = q{};
			$suffixPut = q{};
		}
		# new syntax readingNames
		my $rdNameGet = $gadName . $suffixGet;
		my $rdNameSet = $gadName . $suffixSet;
		my $rdNamePut = $gadName . $suffixPut;

		if (($gadName =~ /^g$gadNo/ix) && (! defined($gadNoSuffix))) { # old syntax 
			$rdNameGet = "getG" . $gadNo;
			$rdNameSet = "setG" . $gadNo;
			$rdNamePut = "putG" . $gadNo;
		}

		my $log = "KNX_define ($name): -found GAD: $gad, NAME: $gadName NO: $gadNo, HEX: $gadCode, DPT: $gadModel";
		$log .= ", OPTION: $gadOption" if (defined ($gadOption));
		Log3 ($name, 5, "$log");

		#determint dpt-details
		my $dptDetails = $dpttypes{$gadModel};
		my $setlist;
		#case list is given, pass it through
		if (defined ($dptDetails->{SETLIST})) {
			$setlist = q{:} . $dptDetails->{SETLIST};
		}
		#case number - place slider
		elsif (defined ($dptDetails->{MIN}) and ($dptDetails->{MIN} =~ m/0|[+-]?\d*[(.|,)\d*]/x)) {
			my $min = $dptDetails->{MIN};
			my $max = $dptDetails->{MAX};
			my $interval = int(($max-$min)/100);
			$interval = 1 if ($interval == 0);
			$setlist = ':slider,' . $min . q{,} . $interval . q{,} . $max;
		}
		#on/off/...
		elsif (defined ($dptDetails->{MIN})) {
			my $min = $dptDetails->{MIN};
			my $max = $dptDetails->{MAX};
			$setlist = q{:} . $min . q{,} . $max;
		}
		#plain input field
		else {
			$setlist = q{};
		}

		Log3 ($name, 5, "KNX_define ($name): Estimated reading-names: $rdNameGet, $rdNameSet, $rdNamePut");
		Log3 ($name, 5, "KNX_define ($name): SetList: $setlist") if (defined ($setlist));
		
		#add details to hash
		$hash->{GADDETAILS}{$gadName} = {GROUP => $gad, CODE => $gadCode, MODEL => $gadModel, NO => $gadNo, OPTION => $gadOption, RDNAMEGET => $rdNameGet, RDNAMESET => $rdNameSet, RDNAMEPUT => $rdNamePut, SETLIST => $setlist};
		
		#add key and value to GADTABLE
		$tableHashRef->{$gadCode} = $gadName;

		###DEFPTR
		my @devList = ();
		#get list, if at least one GAD is installed
		@devList = @{$modules{KNX}{defptr}{$gadCode}} if (defined ($modules{KNX}{defptr}{$gadCode}));
		#push actual hash to list
		push (@devList, $hash);
		#restore list
		@{$modules{KNX}{defptr}{$gadCode}} = @devList;
		###DEFPTR

		#create setlist/getlist for setFn / getFn
		my $setString = q{};
		my $getString = q{};
		foreach my $key (keys %{$hash->{GADDETAILS}}) {
			#no set-command for listenonly or get / no get cmds for set
			my $option = $hash->{GADDETAILS}{$key}{OPTION};
			if (defined ($option)) {
				if ($option eq 'get') {
					$getString .= q{ } . $key . ':noArg';
				}
				elsif ($option eq 'set') {
					$setString .= ' on:noArg off:noArg' if (($hash->{GADDETAILS}{$key}{NO} == 1) && ($hash->{GADDETAILS}{$key}{MODEL} =~ /^(dpt1|dpt1.001)$/x)); 
					$setString .= q{ } . $key . $hash->{GADDETAILS}{$key}{SETLIST};
				}
				# must be listenonly, do nothing
			}
			else {  # no option def, select all
				$getString .= q{ } . $key . ':noArg';
				$setString .= ' on:noArg off:noArg' if (($hash->{GADDETAILS}{$key}{NO} == 1) && ($hash->{GADDETAILS}{$key}{MODEL} =~ /^(dpt1|dpt1.001)$/x));
				$setString .= q{ } . $key . $hash->{GADDETAILS}{$key}{SETLIST};
			}
		}
		$setString =~ s/^[\s?](.*)/$1/ix; # trim leading blank
		$getString =~ s/^[\s?](.*)/$1/ix;
		$hash->{SETSTRING} = $setString;
		$hash->{GETSTRING} = $getString;

		Log3 ($name, 5, "KNX_define ($name): -GETSTR= " . $hash->{GETSTRING} . ", SETSTR= " . $hash->{SETSTRING});
	}

	#backup name for a later rename
	$hash->{DEVNAME} = $name; # wer braucht das?

	Log3 ($name, 5, "KNX_define ($name): -exit");

	return;
}

#Release this device
#Is called at every delete / shutdown
#############################
sub KNX_Undef {
	my $hash = shift;
	my $name = shift;

	Log3 ($name, 5, "KNX_undef -enter: $name");
	
	#delete all defptr entries for this device. this bug is still in SVN version! 09-02-2021
	KNX_delete_defptr($hash); # verify with: {PrintHash($modules{KNX}{defptr},3) } on FHEM-cmdline

	Log3 ($name, 5, "KNX_undef -exit");
	return;
}

#Places a "read" Message on the KNX-Bus
#The answer is treated as regular telegram
#############################
sub KNX_Get {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};

	#FHEM asks with a ? at startup - no action, no log
	return "unknown argument $a[1] choose one of " . $hash->{GETSTRING} if(defined($a[1]) && ($a[1] =~ m/\?/x));
	return "KNX_Get device: $name is disabled" if (IsDisabled($name) == 1);

	Log3 ($name, 5, "KNX_Get -enter: $name, " . join(", ", @a));

	#no more than 1 argument allowed
	Log3 ($name, 2, "KNX_Get: too much arguments. Only one argument allowed (group-address). Other Arguments are discarded.") if (int(@a) > 2);

	#determine gadName to read - use first defined GAD if no argument is supplied
	my $gadName;
	if (defined ($a[1])) {
		$gadName = $a[1];
	}
	else {
		$gadName = $hash->{FIRSTGADNAME};
	}

	#get groupCode
	my $groupc = $hash->{GADDETAILS}{$gadName}{CODE};
	#get groupAddress
	my $group = $hash->{GADDETAILS}{$gadName}{GROUP};
	#get option		
	my $option = $hash->{GADDETAILS}{$gadName}{OPTION};

	#return, if unknown group
	return "KNX_Get: no valid address stored for gad: $gadName" if(!$groupc);

	#exit if get is prohibited
	return 'KNX_Get: did not request a value - "set" or "listenonly" option is defined.' if (defined ($option) and ($option =~ m/(set|listenonly)/ix));

	#send read-request to the bus
	Log3 ($name, 5, "KNX_Get-exit: $name request value for GAD: $group, GAD-NAME: $gadName");

	IOWrite($hash, $TULid, 'r' . $groupc);

	FW_directNotify("FILTER=" . $FW_detail, '#FHEMWEB:' . $FW_wname, 'FW_errmsg(" current value for ' . $name . ' - ' . $group . ' requested",5000)', qq{});

	return;
}

#Does something according the given cmd...
#############################
sub KNX_Set {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $ret = q{};
	my $na = scalar(@a);

	#identify this sub
	my @ca = caller(0);
	(my $thisSub = $ca[3]) =~ s/.+[:]+//gx;

	#FHEM asks with a "?" at startup or any reload of the device-detail-view
	#return string for enabling webfrontend to show boxes, ...
	return "unknown argument $a[1] choose one of " . $hash->{SETSTRING} if(defined($a[1]) && ($a[1] =~ m/\?/x));
	return "$thisSub: device $name is disabled" if (IsDisabled($name) == 1); 

	Log3 ($name, 5, "$thisSub -enter: $name, " . join(", ", @a[1 .. $na-1])) if (defined ($a[1]));

	#return, if no cmd specified
	return "$thisSub: no gadname specified for set cmd" if((!defined($a[1])) || ($a[1] eq q{}));
	#return, if no set value specified
	return "$thisSub: no value specified for set cmd" if($na < 2);

	#remove whitespaces
	(my $targetGadName = $a[1]) =~ s/^\s+|\s+$//gix; # gad-name or cmd (in old syntax)
	my @arg = @a[2 .. $na-1]; # copy cmd & arguments

	#contains gadNames to be executed
	my $cmd = undef;

	#check, if old or new syntax
	if (defined ($hash->{GADDETAILS}{$targetGadName})) { # #new syntax, if first arg is a valid gadName
		#shift backup args as with newsyntax $a[2] is cmd
		$cmd = shift(@arg);
	}
	else { #oldsyntax
		(my $err, $targetGadName, $cmd) = KNX_Set_oldsyntax($hash,$targetGadName,@arg); ## process old syntax targetGadName contains command!
		return $err if defined($err);
	}

	return "$thisSub: no target and cmd found" if((!defined($targetGadName)) && (!defined($cmd)));
	return "$thisSub: no cmd found" if(!defined($cmd));
	return "$thisSub: no target found" if(!defined($targetGadName));

	Log3 ($name, 5, "$thisSub: set $name: desired target is gad: $targetGadName, command: $cmd, args: " . join (q{ }, @arg));

	#get details
	my $groupCode = $hash->{GADDETAILS}{$targetGadName}{CODE};
	my $option    = $hash->{GADDETAILS}{$targetGadName}{OPTION};
	my $rdName    = $hash->{GADDETAILS}{$targetGadName}{RDNAMESET};
	my $model     = $hash->{GADDETAILS}{$targetGadName}{MODEL}; 

	return $thisSub . ': did not set a value - "get" or "listenonly" option is defined.' if (defined ($option) and ($option =~ m/(get|listenonly)/ix));

	##############################
	#process set command with $value as output
	my $value = $cmd;
	#Text neads special treatment - additional args may be blanked words
	$value .= q{ } . join (q{ }, @arg) if (($model =~ m/^dpt16/ix) and (scalar (@arg) > 0));

	#Special commands for dpt1 and dpt1.001
	if ($model =~ m/((dpt1)|(dpt1.001))$/ix) {
		(my $err, $value) = KNX_Set_dpt1($hash, $targetGadName, $cmd, @arg);
		return $err if defined($err);
	}

	##############################
	#check and cast value
	my $transval = KNX_checkAndClean($hash, $value, $targetGadName);

	#if cast not successful
	return "$thisSub: invalid value= $value" if (!defined($transval));

	#process set command
	my $transvale = KNX_encodeByDpt($hash, $transval, $targetGadName);
	IOWrite($hash, $TULid, 'w' . $groupCode . $transvale);
	
	Log3 ($name, 4, "$thisSub: $name, cmd= $cmd, value= $value, translated= $transvale");

	# decode again for values that have been changed in encode process
	if ($model =~ m/^(dpt3|dpt10|dpt11|dpt19)/ix) {
		$transval = KNX_decodeByDpt($hash, $transvale, $targetGadName);
	}
	else {
		my $unit = $dpttypes{$model}{UNIT};
		$transval .= q{ } . $unit if (defined($unit) && ($unit ne q{})); # append units during set cmd
	}
	#apply post processing for state and set all readings
	KNX_SetReadings($hash, $targetGadName, $transval, $rdName, undef); 

	Log3 ($name, 5, "$thisSub: -exit");
	return;
}

# Process set command for old syntax 
# calling param: $hash, $cmd, arg array
# returns ($err, targetgadname, $cmd)
sub KNX_Set_oldsyntax {
	my ($hash, $cmd, @a) = @_;
	my $name = $hash->{NAME};
	my $na = scalar(@a);

	#contains gadNames to be executed
	my $targetGadName = undef;

	#default
	my $groupnr = 1;
	#select another group, if the last arg starts with a g
	if($na >= 1 && $a[$na - 1] =~ m/$PAT_GNO/ix) {
		$groupnr = pop (@a);
		Log3 $name, 3, q{KNX_Set_syntax2: you are still using "old syntax", pls. change to "set } . "$name $groupnr $cmd " . join(q{ },@a) . q{"};
		$groupnr =~ s/^g//gix; #remove "g"
	}

	# if cmd contains g1: the check for valid gadnames failed !
	# this is NOT oldsyntax, but a user-error!
	if ($cmd =~ /^g[\d]/ix) { # an invalid Gadname was specified
		Log3 ($name,2,"KNX_Set_syntax2: an invalid gadName: $cmd was used in set-cmd");
		return ("KNX_Set_syntax2: an invalid gadName: $cmd was used in set-cmd",q{},q{});
	}

	foreach my $key (keys %{$hash->{GADDETAILS}}) {
		$targetGadName = $key if (int ($hash->{GADDETAILS}{$key}{NO}) == int ($groupnr));
	}
	return "KNX_Set_syntax2: gadName not found for $groupnr" if(!defined($targetGadName));

	# all of the following cmd's need at least 1 Argument (or more)
	return (undef, $targetGadName, $cmd) if (scalar(@a) <= 0);

	my $code = $hash->{GADDETAILS}{$targetGadName}{MODEL};
	my $value = $cmd;

	if ($cmd =~ m/$RAW/ix) {
		#check for 1-16 hex-digits
		return "KNX_Set_syntax2: $cmd $a[0] has wrong syntax. Use hex-format only." if ($a[0] !~ m/[0-9A-F]{1,16}/ix);
		$value = $a[0];

	}
	elsif ($cmd =~ m/$VALUE/ix) {
		return 'KNX_Set_syntax2: "value" not allowed for dpt1, dpt16 and dpt232' if ($code =~ m/(dpt1$)|(dpt16$)|(dpt232$)/ix);
		$value = $a[0];
		$value =~ s/,/\./gx;

	}
	#set string <val1 val2 valn>
	elsif ($cmd =~ m/$STRING/ix) {
		return 'KNX_Set_syntax2: "string" only allowed for dpt16' if ($code !~ m/dpt16/ix);
		$value = q{}; # will be joined in KNX_Set

	}
	#set RGB <RRGGBB>
	elsif ($cmd =~ m/$RGB/ix) {
		return 'KNX_Set_syntax2: "RGB" only allowed for dpt232' if ($code !~ m/dpt232$/ix);
		#check for 6 hex-digits
		return "KNX_Set_syntax2: $cmd $a[0] has wrong syntax. Use 6 hex-digits only." if ($a[0] !~ m/[0-9A-F]{6}/ix);
		$value = lc($a[0]);

	}

	return (undef, $targetGadName, $value);
}

# process special dpt1, dpt1.001 set
# calling: $hash, $targetGadName,  $cmd, @arg
# return: $err, $value
sub KNX_Set_dpt1 {
	my ($hash, $targetGadName, $cmd, @arg) = @_;
	my $name = $hash->{NAME};

	my $groupCode = $hash->{GADDETAILS}{$targetGadName}{CODE};

	#delete any running timers
	if ($hash->{".TIMER_$groupCode"}) {
		CommandDelete(undef, $name . "_TIMER_$groupCode");
		delete $hash->{".TIMER_$groupCode"};
	}

	my $value = 'off'; # default
	my $tvalue = 'on'; # default reversed value for timer ops
	if ($cmd =~ m/(^on|1)/ix) {
		$value = 'on';
		$tvalue = 'off';
	}

	return (undef,$value) if ($cmd =~ m/(?:on|off)$/ix); # shortcut

	#set on-for-timer / off-for-timer
	if ($cmd =~ m/(?:(on|off)-for-timer)$/ix) {
		#get duration
		my $duration = sprintf("%02d:%02d:%02d", $arg[0]/3600, ($arg[0]%3600)/60, $arg[0]%60);
		Log3 ($name, 5, "KNX_Set_dpt1 $name: \"on-for-timer\" for $duration");

		$hash->{".TIMER_$groupCode"} = $duration; #create local marker
		#place at-command for switching on / off
		CommandDefMod(undef, '-temporary ' .  $name . "_TIMER_$groupCode at +$duration set $name $targetGadName $tvalue");
	}

	#set on-until / off-until
	elsif ($cmd =~ m/(?:(on|off)-until)$/ix) {
		#get off-time
		my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($arg[0]); ## fhem.pl
		return "KNX_Set_dpt1: Error trying to parse timespec for $arg[0]: $err" if (defined($err));

		#do like (on|off)-until-overnight in at cmd !
		my $hms_til = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
		Log3 ($name, 5, "KNX_Set_dpt1 $name: \"$cmd $hms_til\" ");

		$hash->{".TIMER_$groupCode"} = $hms_til; #create local marker
		#place at-command for switching on / off
		CommandDefMod(undef, '-temporary ' . $name . "_TIMER_$groupCode at $hms_til set $name $targetGadName $tvalue");
	}

	#toggle
	elsif ($cmd =~ m/$TOGGLE/ix) {
		my $togglereading = 'dummy';
		my $toggleOldVal = 'dontknow';
		my $tDev = $name; # default

		if (defined($hash->{'.TOGGLESRC'})) { # prio1: use Attr. KNX_toggle: format: <device>:<reading>
			($tDev, $togglereading) = split(qr/:/x,$hash->{'.TOGGLESRC'});
			$toggleOldVal = ReadingsVal($tDev, $togglereading, 'dontknow');
		} 
		else {
			$togglereading = $hash->{GADDETAILS}{$targetGadName}{RDNAMEGET};
			$toggleOldVal = ReadingsVal($tDev, $togglereading, undef); #prio2: use get-reading
			if (! defined($toggleOldVal)) {
				$togglereading = $hash->{GADDETAILS}{$targetGadName}{RDNAMESET}; #prio3: use set-reading
				$toggleOldVal = ReadingsVal($tDev, $togglereading, 'dontknow');
			}
		}

		Log3 ($name, 3, 'KNX_Set_dpt1: initial value for "set ' . "$name $targetGadName" . ' TOGGLE is not "on" or "off" - ' . "$targetGadName will be switched off") if ($toggleOldVal !~ /^(?:on|off)/ix);
		$value = q{on} if ($toggleOldVal =~ m/^off/ix); # value off is default
	}

	#blink - implemented with timer & toggle
	elsif ($cmd =~ m/$BLINK/ix) {
		my $count = $arg[0] * 2 -1;
		$count = 1 if ($count < 1);
		my $duration = sprintf("%02d:%02d:%02d", $arg[0]/3600, ($arg[0]%3600)/60, $arg[0]%60);
		$hash->{".TIMERBLINK_$groupCode"} = $duration; #create local marker
		CommandDefMod(undef, '-temporary ' .  $name . "_TIMERBLINK_$groupCode at +*{" . $count ."}$duration set $name $targetGadName toggle");
		$value = 'on';
	}

#04.68	### setextensions trial...
#	else {
#		my ($ecmd,@earg) = split(/[\s]/ix,$cmd,2);
#		my $cmdlist = $hash->{SETSTRING} . ' blink intervals';
##		my @earg =  join(' ', @a[1 .. $na-1])) if (defined ($a[1]));
#		Log3($name, 1, "Setext cmd=$ecmd, arg=" . join(',',@earg));
#		my $extret = SetExtensions($hash, $cmdlist , $name, $ecmd, @earg); # use SetExtensions
#		Log3($name, 1, 'Setext returned: ' . $extret) if (defined($extret));
#	}
	return (undef,$value);
}

#In case setstate is executed, a readingsupdate is initiated
#############################
sub KNX_State {
	my ($hash, $time, $reading, $value) = @_;
	my $name = $hash->{NAME};

	return if (not (defined($value)));
	return if (not (defined($reading)));

	#remove whitespaces
	$value =~ s/^\s+|\s+$//gix;
	$reading =~ s/^\s+|\s+$//gix;

	#workaround for STATE in capitol letters (caused by unknown external function)
	$reading = "state" if ($reading eq 'STATE');
	
	Log3 ($name, 5, "KNX_State $name: update $reading with value: $value");

	#write value and update reading
	readingsSingleUpdate($hash, $reading, $value, 1);

	return;
}

#Get the chance to qualify attributes
#############################
sub KNX_Attr {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};

	my $value = undef;
	if ($cmd eq 'set') {
		Log3 ($name, 2, 'Attribut "listenonly" is deprecated. Please supply in definition - see commandref for details.') if ($aName =~ m/listenonly/ix);
		Log3 ($name, 2, 'Attribut "readonly" is deprecated. Please supply "get" in definition - see commandref for details.') if ($aName =~ m/readonly/ix);
		Log3 ($name, 2, 'Attribut "slider" is deprecated. Please use widgetOverride in Combination with WebCmd instead. See commandref for details.') if ($aName =~ m/slider/ix);
		Log3 ($name, 2, 'Attribut "useSetExtensions" is deprecated.') if ($aName =~ m/useSetExtensions/ix);

		if ($aName eq 'KNX_toggle') { # validate device/reading
			my ($srcDev,$srcReading) = split(qr/:/x,$aVal); # format: <device>:<reading>
			$srcDev = $name if ($srcDev eq '$self');
			return 'no valid device for attr: KNX_toggle' if (!IsDevice($srcDev));
			$value = ReadingsVal($srcDev,$srcReading,undef) if (defined($srcReading)); #test for value  
			return 'no valid device/reading value for attr: KNX_toggle' if (!defined($value) && $init_done); # maybe device/reading not defined during starrtup
			$hash->{'.TOGGLESRC'} = $srcDev . q{:} . $srcReading; # save for later processing
		}
		elsif (($aName eq 'disable') && (defined($aVal)) && ($aVal == 1)) {
			$hash->{SETSTRING} = q{}; # remove set & get options from UI
			$hash->{GETSTRING} = q{};
		}

		# check valid IODev
		elsif ($aName eq 'IODev' && $init_done) {
			my @IOList = devspec2array('TYPE=(TUL|KNXTUL|KNXIO)',$hash);
			foreach my $iodev (@IOList) {
				return if ($iodev eq $aVal); # ok
			}
			return $aVal . ' is not a valid IO-Device for this Device';
		}
	} # /set

	if ($cmd eq 'del') {
		if ($aName eq 'KNX_toggle') {
			delete $hash->{'.TOGGLESRC'};
#			CommandModify(undef, "$name $hash->{DEF}");
		}
		elsif ($aName eq 'disable') {
			my @defentries = split(/\s/ix,$hash->{DEF});
			foreach my $def (@defentries) { # check all entries
				next if ($def eq ReadingsVal($name,'IODev',undef)); # deprecated IOdev
				next if ($def =~ /:dpt\d+/ix); 

				Log3 ($name, 2, 'Attribut "disable" cannot be deleted for device ' . $name . ' until you specify a valid dpt!');
				return 'Attribut "disable" cannot be deleted for device ' . $name . ' until you specify a valid dpt!';
			}
#			CommandDefMod(undef, "-temporary $name KNX $hash->{DEF}"); # do a defmod ...
			CommandModify(undef, "$name $hash->{DEF}"); # do a defmod ...
		}
	}
	return;
}

#Split reading for DBLOG
#############################
sub KNX_DbLog_split {
	my ($event, $device) = @_;
	my ($reading, $value, $unit);

	Log3 $device, 5, "KNX_DbLog_split -enter: device= $device event= $event";

	#split input-string
	my @strings = split (q{ }, $event);
	return if (not defined ($strings[0]));

	#detect reading - real reading or state?
	if ($strings[0] =~ m/.*:$/x) { # real reading
		$reading = shift(@strings);
		$reading =~ s/:$//x;
	}
	else {
		$reading = 'state';
	}

	#per default join all single pieces
	$value = join(q{ }, @strings);

	#numeric value? and last value non numeric? - assume unit
	if (looks_like_number($strings[0]) && (! looks_like_number($strings[scalar(@strings)-1]))) {
		$value = join(q{ },@strings[0 .. (scalar(@strings)-2)]);
		$unit = $strings[scalar(@strings)-1];
	}
	$unit = q{} if (!defined($unit));

	Log3 $device, 5, "KNX_DbLog_split -exit: device= $device, reading= $reading, value= $value, unit= $unit";
	return ($reading, $value, $unit);
}

#Handle incoming messages
#############################
sub KNX_Parse {
	my $iohash = shift; # this is IO-Device hash !
	my $msg = shift;
	my $ioName = $iohash->{NAME};

	return q{} if ((IsDisabled($ioName) == 1) || IsDummy($ioName)); # IO - device is disabled or dummy

	#Msg format: 
	#C<src>[wrp]<group><value> i.e. Cw00000101
	#we will also take reply telegrams into account,
	#as they will be sent if the status is asked from bus

	#new syntax for extended adressing
	my ($src,$cmd,$gadCode,$val) = $msg =~ m/^$TULid([0-9a-f]{5})([prw])([0-9a-f]{5})(.*)$/ix; 

	my @foundMsgs;

	Log3 ($ioName, 5, "KNX_Parse -enter: IO-name: $ioName, dest: $gadCode, msg: $msg");

	#gad not defined yet, give feedback for autocreate
	if (not (exists $modules{KNX}{defptr}{$gadCode})) {
		#format gad
		my $gad = KNX_hexToName($gadCode);
		#create name
		my $newDevName = sprintf("KNX_%.2d%.2d%.3d",split (/\//x, $gad));
		return "UNDEFINED $newDevName KNX $gad:$MODELERR";
	}

	#get list from device-hashes using given gadCode (==destination)
	# check on cmd line with: {PrintHash($modules{KNX}{defptr},3) }
	my @deviceList = @{$modules{KNX}{defptr}{$gadCode}};

	#process message for all affected devices and gad's
	foreach my $deviceHash (@deviceList) {
		#get details
		my $deviceName = $deviceHash->{NAME};
		my $gadName = $deviceHash->{GADTABLE}{$gadCode};

		push(@foundMsgs, $deviceName); # save to list even if dev is disabled

		next if (IsDisabled($deviceName) == 1); # device is disabled 

		Log3 ($deviceName, 4, "KNX_Parse -process: IO-name: $ioName, device-name: $deviceName, rd-name: $gadName, gadCode: $gadCode, cmd: $cmd");

		#########################
		#process message
		#handle write and reply messages
		if ($cmd =~ /[w|p]/ix) {
			#decode message
			my $getName = $deviceHash->{GADDETAILS}{$gadName}{RDNAMEGET};
			my $transval = KNX_decodeByDpt ($deviceHash, $val, $gadName);
			#message invalid
			if (not defined($transval) or ($transval eq q{})) {
				Log3 ($deviceName, 2, "KNX_Parse (wp): $deviceName, READINGNAME: $getName, message $msg could not be decoded");
				next;
			}
			Log3 ($deviceName, 4, "KNX_Parse (wp): $deviceName, READINGNAME: $getName, VALUE: $transval, SENDER: $src");

			#apply post processing for state and set all readings
			KNX_SetReadings($deviceHash, $gadName, $transval, $getName, $src);
		}

		#handle read messages
		elsif ($cmd =~ /[r]/x) {
			my $putName = $deviceHash->{GADDETAILS}{$gadName}{RDNAMEPUT};
			Log3 ($deviceName, 5, "KNX_Parse (r): $deviceName, GET");
			my $transval = undef;

			#answer "old school"
			my $value = undef;
			if (AttrVal($deviceName, 'answerReading', 0) =~ m/1/x) {
				my $putVal = ReadingsVal($deviceName, $putName, undef);
				
				if ((defined($putVal)) && ($putVal ne q{})) {
					$value = $putVal; #medium priority, overwrite $value
				}
				else {
					$value = ReadingsVal($deviceName, 'state', undef); #lowest priority - use state
				}
			}

			#high priority - eval
			my $cmdAttr = AttrVal($deviceName, "putCmd", undef);
			if ((defined($cmdAttr)) && ($cmdAttr ne q{})) {
				$value = ReadingsVal($deviceName, 'state', undef); # get default value from state
				$value = KNX_eval ($deviceHash, $gadName, $value, $cmdAttr);
				if (defined($value) && ($value ne q{}) && ($value ne 'ERROR')) { # answer only, if eval was successful
					Log3 ($deviceName, 5, "KNX_Parse (r): $deviceName - put replaced via command $cmdAttr - value: $value");
					readingsSingleUpdate($deviceHash, $putName, $value,1);
				}
				else {
					Log3 ($deviceName, 2, "KNX_parse error (r): $deviceName - no reply sent!");
					$value = undef; # dont send !
				} 
			}

			#send transval
			if (defined($value)) {
				$transval = KNX_encodeByDpt($deviceHash, $value, $gadName);
				Log3 ($deviceName, 4, "KNX_Parse send answer (r): $deviceName, GET: $transval, READING: $gadName");
				IOWrite ($deviceHash, $TULid, "p" . $gadCode . $transval);
			}
		}
		#/process message
	}

	Log3 ($ioName, 5, "KNX_parse -exit");

	return @foundMsgs;
}

#Function is called at every notify
# not needed, will never be used
#############################
sub KNX_Notify {
	my $ownHash = shift;
	my $callHash = shift;
	#own name / hash
	my $ownName = $ownHash->{NAME};
	return if(IsDisabled($ownName) == 1); # Return without any further action if the module is disabled

	#Device that created the events
	my $callName = $callHash->{NAME}; 

	my $events = deviceEvents($callHash, 1);
	if($callName eq "global") {
		foreach my $ev (@{$events}) {
			if ($ev =~ /^INITIALIZED|REREADCFG$/x) {
				# X_FunctionWhoNeedsAttr($hash);
			}
		}
	}
	return;
}

# ignore duplicate messages (runs in TUL /KNXTUL context!)
#############################
sub KNX_FingerPrint {
	my $ioname = shift;
	my $buf  = shift;
	substr( $buf, 1, 5, '.....' ); # ignore src addr
	Log3 $ioname, 5, 'KNX_FingerPrint: ' . $buf;
#	return ( $ioname, $buf ); # ignore src addr only
	return ( q{}, $buf ); # ignore ioname & src addr
}

########## begin of private functions ##########

# KNX_SetReadings is called from KNX_Set and KNX_Parse
# calling param: $hash, $gadName, $transval, $rdName, caller (set/parse)
sub KNX_SetReadings {
	my ($hash, $gadName, $transval, $rdName, $src) = @_;
	my $name = $hash->{NAME};

	#append post-string, if supplied
	my $suffix = AttrVal($name, "format",undef);
	$transval .= q{ } . $suffix if (defined($suffix));
	#execute regex, if defined
	my $regAttr = AttrVal($name, "stateRegex", undef);
	my $state = KNX_replaceByRegex ($regAttr, $rdName, $transval);

	my $logstr = (defined($state))?$state:'UNDEFINED';
	Log3 ($name, 5, "KNX_SetReadings: $name - replaced $rdName value from: $transval to $logstr") if ($transval ne $logstr);

	my $lsvalue = 'fhem'; # called from set
	$lsvalue = KNX_hexToName2($src) if (defined($src) && ($src ne q{})); # called from parse

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'last-sender', $lsvalue);
	readingsBulkUpdate($hash, $rdName, $transval);

	if (defined($state)) {
		#execute state-command if defined
		#must be placed after first reading, because it may have a reference
		my $deviceName = $name; #hack for being backward compatible - serve $name and $devname
		my $cmdAttr = AttrVal($name, "stateCmd", undef);

		if ((defined($cmdAttr)) && ($cmdAttr ne q{})) {
			my $newstate = KNX_eval ($hash, $gadName, $state, $cmdAttr);
			if (defined($newstate) && ($newstate ne q{}) && ($newstate !~ m/ERROR/ix)) {
				$state = $newstate;
				Log3 ($name, 5, "KNX_SetReadings: $name - state replaced via stateCmd $cmdAttr - state: $state");
			}
			else {
				Log3 ($name, 3, "KNX_SetReadings: $name, gad: $gadName, error during stateCmd processing");
			}
		}

		readingsBulkUpdate($hash, "state", $state);
	}
	readingsEndUpdate($hash, 1);
	return;
}

# delete all defptr entries for this device
# used in undefine & define (avoid defmod problem) 09-02-2021
# calling param: $hash
# return param:  none
sub KNX_delete_defptr {
	my $hash = shift;
	my $name = $hash->{NAME};

	for my $gad (sort keys %{$modules{KNX}{defptr}}) { # get all gad for all KNX devices
		my @olddefList = ();
		@olddefList = @{$modules{KNX}{defptr}{$gad}} if (defined ($modules{KNX}{defptr}{$gad})); # get list of devices with this gad
		my @newdefList = ();
		foreach my $devHash (@olddefList) {
			push (@newdefList, $devHash) if ($devHash != $hash); # remove previous definition for this device, but keep them for other devices!
		}
		#restore list if we have at least one entry left, or delete key!
		if (scalar(@newdefList) == 0) {
			delete $modules{KNX}{defptr}{$gad};
		}
		else {
			@{$modules{KNX}{defptr}{$gad}} = @newdefList;
		}
	}
	return;
}

# convert GAD from hex to readable version
sub KNX_hexToName {
	my $v = shift;
	
	#new syntax - extended adressing
	my $p1 = hex(substr($v,0,2));
	my $p2 = hex(substr($v,2,1));
	my $p3 = hex(substr($v,3,2));

	return sprintf("%d/%d/%d", $p1,$p2,$p3);
}

# convert PHY from hex to readable version
sub KNX_hexToName2 {
	my $v = KNX_hexToName(shift);
	$v =~ s/\//\./gx;
	return $v;
}

# convert GAD from readable version to hex
sub KNX_nameToHex {
	my $v = shift;
	my $r = $v;

	if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/x) {
		#new syntax - extended adressing
		$r = sprintf("%02x%01x%02x",$1,$2,$3);
	}
	return $r;
}

# clean input string according DPT
sub KNX_checkAndClean {
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};
	my $orgValue = $value;

	Log3 ($name, 5, "KNX_checkAndClean -enter: value= $value, gadName= $gadName");

	my $model = $hash->{GADDETAILS}{$gadName}{MODEL};

	#return unchecked, if this is a autocreate-device
	return $value if ($model eq $MODELERR);

	my $pattern = $dpttypes{$model}{PATTERN};

	#trim whitespaces at the end
	$value =~ s/^\s+|\s+$//gix;
	$value .= ':00' if ($model eq 'dpt10' && $value =~ /^[\d]{2}:[\d]{2}$/gix); # compatibility with widgetoverride :time

#new code: match against model pattern -to be tested!!!
#	my $pattern = qr/^($dpttypes{$model}{PATTERN})$/;
#	($value) = ($value =~ m/$pattern/ix);
#	return if (!defined($value));

	my @tmp = ($value =~ m/$pattern/gix);
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

#E04.80	$value = KNX_limit ($hash, $value, $gadName, undef);

	Log3 ($name, 3, "KNX_checkAndClean: name= $name, gadName= $gadName, value= $orgValue was casted to $value") if ($orgValue ne $value); #E04.80 add dev-name
	Log3 ($name, 5, "KNX_checkAndClean -exit: value= $value, gadName= $gadName, model= $model, pattern= $pattern");

	return $value;
}

# replace state-values Attribute: stateRegex
sub KNX_replaceByRegex {
	my ($regAttr, $rdName, $input) = @_;

	return $input if (! defined($regAttr));

	my $retVal = $input;

	#execute regex, if defined
	#get array of given attributes
	my @reg = split(/\s\//x, $regAttr);

	my $tempVal = $rdName . q{:} . $input;

	#loop over all regex
	foreach my $regex (@reg) {
		#trim leading and trailing slashes
		$regex =~ s/^\/|\/$//gix;
		#get pairs
		my @regPair = split(/\//x, $regex);

		#skip if first part of regex not match readingName
		next if ((not defined($regPair[0])) || ($regPair[0] eq q{}) || ($regPair[0] !~ /^(?:$rdName)/ix));

		if (not defined ($regPair[1])) {
			#cut value
			$retVal = undef;
		}
		elsif ($regPair[0] eq $tempVal) { # complete match
			$retVal = $regPair[1];
		}
		elsif (($input !~ /$regPair[0]/x) && ($regPair[0] =~ /[:]/x)) { # value dont match!
			next; #E04.80
		}
		else {
			#replace value
			$tempVal =~ s/$regPair[0]/$regPair[1]/gix;
			($retVal = $tempVal) =~ s/[:]/ /x;
		}

		last;
	}
	return $retVal;
}

# limit numeric values. Valid directions: encode, decode
sub KNX_limit {
	my ($hash, $value, $model, $direction) = @_;
#E04.80	my ($hash, $value, $gadName, $direction) = @_;

	#continue only if numeric value
	return $value if (! looks_like_number ($value));
	return $value if (! defined($direction));

	my $name = $hash->{NAME};
#E04.80	my $model = $hash->{GADDETAILS}{$gadName}{MODEL};
	my $retVal = $value;

	#get correction details
	my $factor = $dpttypes{$model}{FACTOR};
	my $offset = $dpttypes{$model}{OFFSET};
	#get limits
	my $min = $dpttypes{$model}{MIN};
	my $max = $dpttypes{$model}{MAX};

	#determine direction of scaling, do only if defined
	if ($direction =~ m/^encode/ix) {
		#limitValue
		$retVal = $min if (defined ($min) and ($retVal < $min));
		$retVal = $max if (defined ($max) and ($retVal > $max));
		#correct value
		$retVal /= $factor if (defined ($factor));
		$retVal -= $offset if (defined ($offset));
	}
	elsif ($direction =~ m/^decode/ix) {
		#correct value
		$retVal += $offset if (defined ($offset));
		$retVal *= $factor if (defined ($factor));
		#limitValue
		$retVal = $min if (defined ($min) and ($retVal < $min));
		$retVal = $max if (defined ($max) and ($retVal > $max));
	}

	my $logString = "DIR: $direction";
	$logString   .= " FACTOR: $factor" if (defined ($factor));
	$logString   .= " OFFSET: $offset" if (defined ($offset));
	$logString   .= " MIN: $min" if (defined ($min));
	$logString   .= " MAX: $max" if (defined ($max));
#E04.80	Log3 ($name, 5, "KNX_limit: $gadName $logString");
#	Log3 ($name, 4, "KNX_limit: $gadName modified... Output: $retVal, Input: $value, Model: $model") if ($retVal != $value);
	Log3 ($name, 5, "KNX_limit: $logString");
#	Log3 ($name, 4, "KNX_limit: modified... Input: $value, Output: $retVal, Model: $model") if ($retVal != $value);

	return $retVal;
}

# process attributes stateCmd & putCmd
sub KNX_eval {
	my ($hash, $gadName, $state, $evalString) = @_;
	my $name = $hash->{NAME};
	my $retVal = undef;

	my $code = EvalSpecials($evalString,("%hash" => $hash, '%name' => $name, '%gadName' => $gadName, '%state' => $state)); # prepare vars for AnalyzePerlCommand
	$retVal =  AnalyzeCommandChain(undef, $code);
	$retVal = "ERROR" if (not defined ($retVal));

	if ($retVal =~ /(^Forbidden|error)/ix) { # eval error or forbidden by Authorize
		Log3 ($name, 2, "KNX_Eval-error: device= $name, gadName= $gadName, evalString= $evalString, result= $retVal");
		$retVal = 'ERROR';
	}
	return $retVal;
}

# encode KNX-Message according DPT
sub KNX_encodeByDpt {
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};

	my $model = $hash->{GADDETAILS}{$gadName}{MODEL}; 
	my $code = $dpttypes{$model}{CODE};

	#return unchecked, if this is a autocreate-device
	return if ($model eq $MODELERR);

#	#this one stores the translated value (readble)
#	my $numval = 0; # default
	#this one stores the translated hex-value
	my $hexval = undef;

	Log3 ($name, 5, "KNX_encodeByDpt -enter: $gadName model: $model, code: $code, value: $value");

	my $ivalue = $value; #E04.80 save for compare
	$value = KNX_limit ($hash, $value, $model, 'ENCODE'); #E04.80
#E04.80	$value = KNX_limit ($hash, $value, $gadName, 'ENCODE');
	Log3 ($name, 4, "KNX_limit: $gadName modified... Input: $ivalue, Output: $value, Model: $model") if ($ivalue ne $value); #E04.80

###rework begin
	if (ref($dpttypes{$code}->{ENC}) eq 'CODE') {
		$hexval = $dpttypes{$code}->{ENC}->($value, $model);
		Log3 ($name, 5, "KNX_encodeByDpt -exit: $gadName, model: $model, code: $code, value: $value, hexval: $hexval");
		return $hexval;
	}
	else {
		Log3 ($name, 2, "KNX_encodeByDpt: $gadName,  model: $model not valid");
	}
	return;
}
###rework end 

# decode KNX-Message according DPT
sub KNX_decodeByDpt {
	my ($hash, $value, $gadName) = @_;
	my $name = $hash->{NAME};

	#get model
	my $model = $hash->{GADDETAILS}{$gadName}{MODEL};
	my $code = $dpttypes{$model}{CODE};

	#return unchecked, if this is a autocreate-device
	return if ($model eq $MODELERR);

	#this one contains the return-value
	my $state = undef;

	Log3 ($name, 5, "KNX_decodeByDpt -enter: model: $model, code: $code, value: $value, length-value: " . length($value));

###rework begin 
	if (ref($dpttypes{$code}->{DEC}) eq 'CODE') {
		$state = $dpttypes{$code}->{DEC}->($value, $model);
		my $unit = $dpttypes{$model}{UNIT};
		$state = $state . q{ } . $unit if (defined ($unit) && ($unit ne q{})); #append unit, if supplied

		Log3 ($name, 5, "KNX_decodeByDpt -exit: model: $model, code: $code, value: $value, state: $state");
		return $state;
	}
	else {
		Log3 ($name, 2, "KNX_decodeByDpt: $model, no valid model defined");
	}
	return;
}
###rework end


############################
### encode sub functions ###
sub enc_dpt1 { #Binary value
	my $value = shift;
	my $model = shift;
	my $numval = 0; #default
	$numval = 1 if ($value =~ m/(1|on)$/ix);
	$numval = 1 if ($value eq $dpttypes{$model}{MAX}); # dpt1.011 problem
	return sprintf("%.2x",$numval);
}

sub enc_dpt2 { #Step value (two-bit)
	my $value = shift;
	my $dpt2list = {off => 0, on => 1, forceoff => 2, forceon =>3};
	my $numval = $dpt2list->{lc($value)};
	$numval = $value if ($value =~ m/^0?[0-3]$/ix); ## JoeALLb request
	return sprintf("%.2x",$numval);
}

sub enc_dpt3 { #Step value (four-bit)
	my $value = shift;
	my $numval = 0;
	my $sign = ($value >=0 )?1:0;
	$value = abs($value);
	my @values = qw( 75 50 25 12 6 3 1 );
#	my $i = 0;
	foreach my $key (@values) {
#		$i++;
		$numval++;
		if ($value >= $key) {
#			$numval = $i;
			last;
		}
	}
	$numval += 8 if ($sign == 1);
	return sprintf("%.2x",$numval);
}

sub enc_dpt5 { #1-Octet unsigned value
	return sprintf("00%.2x",shift);
}

sub enc_dpt6 { #1-Octet signed value
	#build 2-complement
	my $numval = unpack("C", pack("c", shift));
	return sprintf("00%.2x",$numval);
}

sub enc_dpt7 { #2-Octet unsigned Value
	return sprintf("00%.4x",shift);
}

sub enc_dpt8 { #2-Octet signed Value
	#build 2-complement
	my $numval = unpack("S", pack("s", shift));
	return sprintf("00%.4x",$numval);
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
	return sprintf("00%.4x",$numval);
}

sub enc_dpt10 { #Time of Day
	my $value = shift;
	my $numval = 0;
	if ($value =~ m/now/ix) {
		#get actual time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		#add offsets
		$year+=1900;
		$mon++;
		# calculate offset for weekday
		$wday = 7 if ($wday == 0);
		$hours += 32 * $wday;
	}
	else {
		my ($hh, $mm, $ss) = split(/:/x, $value);
		$numval = $ss + ($mm << 8) + ($hh << 16);
	}
	return sprintf("00%.6x",$numval);
}

sub enc_dpt11 { #Date
	my $value = shift;
	my $numval = 0;
	if ($value =~ m/now/ix) {
		#get actual time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		#add offsets
		$year+=1900;
		$mon++;
		# calculate offset for weekday
		$wday = 7 if ($wday == 0);
		$value = "$mday.$mon.$year";
		$numval = ($year - 2000) + ($mon << 8) + ($mday << 16);
	}
	else {
		my ($dd, $mm, $yyyy) = split (/\./x, $value);
		if ($yyyy >= 2000) {
			$yyyy -= 2000;
		}
		else {
			$yyyy -= 1900;
		}
		$numval = ($yyyy) + ($mm << 8) + ($dd << 16);
	}
	return sprintf("00%.6x",$numval);
}

sub enc_dpt12 { #4-Octet unsigned value
	return sprintf("00%.8x",shift);
}

sub enc_dpt13 {#4-Octet Signed Value
	#build 2-complement
	my $numval = unpack("L", pack("l", shift));
	return sprintf("00%.8x",$numval);
}

sub enc_dpt14 { #4-Octet single precision float
	my $numval = unpack("L",  pack("f", shift));
	return sprintf("00%.8x",$numval);
}

sub enc_dpt16 { #14-Octet String
	my $value = shift;
	#convert to latin-1
	my $numval = encode("iso-8859-1", decode("utf8", $value));
	#convert to hex-string
	my $dat = unpack "H*", $numval;
	$dat = '00' if ($value =~ /^$PAT_DPT16_CLR/ix); # send all zero string if "clear line string"
	#format for 14-byte-length and replace trailing blanks with zeros
	my $hexval = sprintf("00%-28s",$dat);
	$hexval =~ s/\s/0/gx;
	return $hexval;
}

sub enc_dpt19 { #DateTime
	my $value = shift;
	my $ts = time; # default or when "now" is given
	# if no match we assume now and use current date/time
	if ($value =~ m/^$PAT_DATE$PAT_DTSEP$PAT_TIME/x) {
		$ts = fhemTimeLocal($6, $5, $4, $1, $2-1, $3 - 1900); # if ($value =~ m/^$PAT_DATE$PAT_DTSEP$PAT_TIME/x);
	}
	my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($ts);
	$wday = 7 if ($wday eq "0"); # calculate offset for weekday
	$hours += ($wday << 5); # add day of week
	my $status1 = 0x20;  # Fault=0, WD = 0, NWD = 1 (WD Field valid), NY = 0, ND = 0, NDOW= 0,NT=0, SUTI = 0
	$status1 += 1 if ($isdst == 1);
	my $status0 = 0x00;  # CLQ=0
	$mon++;
	return sprintf("00%02x%02x%02x%02x%02x%02x%02x%02x",$year,$mon,$mday,$hours,$mins,$secs,$status1,$status0);
}

sub enc_dpt20 { # HVAC 1Byte
	my $value = shift;
	my $dpt20list = {auto => 0, comfort => 1, standby => 2, economy => 3, protection => 4,};
	my $numval = $dpt20list->{lc($value)};
	$numval = 5 if (! defined($numval));

	return sprintf("00%.2x",$numval);
}

sub enc_dpt232 { #RGB-Code
	return "00" . shift;
}

############################
### decode sub functions ###
sub dec_dpt1 { #Binary value
	my $value = shift;
	my $model = shift;
	my $numval = hex ($value);
	$numval = ($numval & 0x01);
	my $state = $dpttypes{"$model"}{MIN}; # default
	$state = $dpttypes{"$model"}{MAX} if ($numval == 1);
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
#	$numval = $numval & 0x0F;
	my $dir = ($numval & 0x08) >> 3;
	my $step = ($numval & 0x07);
	my $stepcode = 0;
	if ($step > 0) {
		$stepcode = int(100 / (2**($step-1)));
		$stepcode *= -1 if ($dir == 0);
	}
	return sprintf ("%d", $stepcode);
}

sub dec_dpt5 { #1-Octet unsigned value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%.0f", $state);
}

sub dec_dpt6 { #1-Octet signed value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = unpack("c",pack("C",$numval));
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%d", $state);
}

sub dec_dpt7 { #2-Octet unsigned Value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%.0f", $state);
}

sub dec_dpt8 { #2-Octet signed Value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = unpack("s",pack("S",$numval));
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%d", $state);
}

sub dec_dpt9 { #2-Octet Float value
	my $numval = hex(shift);
	my $model = shift;
	my $hash = shift;
	my $sign = 1;
	$sign = -1 if(($numval & 0x8000) > 0);
	my $exp = ($numval & 0x7800) >> 11;
	my $mant = ($numval & 0x07FF);
	$mant = -(~($mant-1) & 0x07FF) if($sign == -1);
	$numval = (1 << $exp) * 0.01 * $mant;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%.2f","$state");
}

sub dec_dpt10 { #Time of Day
	my $numval = hex(shift);
	my $hours = ($numval & 0x1F0000) >> 16;
	my $mins  = ($numval & 0x3F00) >> 8;
	my $secs  = ($numval & 0x3F);
	my $wday  = ($numval & 0xE00000) >> 21;
	my @wdays = (q{},'Monday, ','Tuesday, ','Wednesday, ','Thursday, ','Friday, ','Saturday, ','Sunday, ');
	# return sprintf("%s%02d:%02d:%02d",$wdays[$wday],$hours,$mins,$secs); # new option ?
	return sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
}

sub dec_dpt11 { #Date
	my $numval = hex(shift);
	my $day = ($numval & 0x1F0000) >> 16;
	my $month  = ($numval & 0x0F00) >> 8;
	my $year  = ($numval & 0x7F);
	#translate year (21st cent if <90 / else 20th century)
	$year += 1900 if($year >= 90);
	$year += 2000 if($year < 90);
	return sprintf("%02d.%02d.%04d",$day,$month,$year);
}

sub dec_dpt12 { #4-Octet unsigned value (handled as dpt7)
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%.0f", $state);
}

sub dec_dpt13 { #4-Octet Signed Value
	my $numval = hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = unpack("l",pack("L",$numval));
	my $state = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%d", $state);
}

sub dec_dpt14 { #4-Octet single precision float
	my $numval = unpack "f", pack "L", hex (shift);
	my $model = shift;
	my $hash = shift;
	$numval = KNX_limit ($hash, $numval, $model, 'DECODE');
	return sprintf ("%.3f","$numval");
}

sub dec_dpt16 { #14-Octet String
	my $value = shift;
	my $model = shift;
	my $numval = 0;
#	my $state  = q{};
	$value =~ s/\s*$//gx; # strip trailing blanks
	my $state = pack("H*",$value);
	#convert to latin-1
	$state = encode ("utf8", $state) if ($model =~ m/16.001/x);
	$state = q{} if ($state =~ m/^[\x00]/ix); # case all zeros received
	$state =~ s/[\x00-\x1F]+//gx; # remove non printable chars
	return $state;
}

sub dec_dpt19 { #DateTime
	my $numval = substr(shift,-16); # strip off 1st byte
	my $time = hex (substr ($numval, 6, 6));
	my $date = hex (substr ($numval, 0, 6));
	my $secs  = ($time & 0x3F) >> 0;
	my $mins  = ($time & 0x3F00) >> 8;
	my $hours = ($time & 0x1F0000) >> 16;
	my $day   = ($date & 0x1F) >> 0;
	my $month = ($date & 0x0F00) >> 8;
	my $year  = ($date & 0xFF0000) >> 16;
	#extras
	my $wday  = ($time & 0xE00000) >> 21; # 0 = anyday/not valid, 1= Monday,...
	$year += 1900;
	return sprintf("%02d.%02d.%04d_%02d:%02d:%02d", $day, $month, $year, $hours, $mins, $secs);
}

sub dec_dpt20 { #HVAC
	my $numval = hex (shift);
	$numval = ($numval & 0xff);
	my @dpt20_102txt = qw(Auto Comfort Standby Economy Protection reserved);
	$numval = 5 if ($numval > 4); # dpt20.102
	return $dpt20_102txt[$numval];
}

sub dec_dpt232 { #RGB-Code
	my $numval = hex (shift);
	return sprintf ("%.6x",$numval);
}


1;

=pod

=encoding utf8

=item [device]
=item summary Devices communicate via the IO-Device TUL/KNXTUL/KNXIO with KNX-bus
=item summary_DE Ger&auml;te kommunizieren &uuml;ber IO-Ger&auml;t TUL/KNXTUL/KNXIO mit KNX-Bus

=begin html

<style>
  .wrap {
    list-style-type: none;
    padding-left: 30px;
    width:100%;
    column-count:2;
    column-gap:20px;
    -moz-column-count:2;
    -moz-column-gap:20px;
    -webkit-column-count:2;
    -webkit-column-gap:20px;}
  .wrap.ul {
    float: left;
    margin: 3px;
    padding: 3px;
    width: 40%; }
  .wrap li { 
    white-space: pre; }
  .wrap.a {
    float: left;
    margin: 3px;
    padding: 3px;
    width: 40%; }
  /* For mobile phones: */
  @media only screen and (max-width: 800px) {
    .wrap {column-count:1; background-color: lightblue;}
  }
  .pad20l {padding-left: 20px;}
  .pad30l {padding-left: 30px;}
  .pad40l {padding-left: 40px;}
</style>
<a id="KNX"></a>
<h3>KNX</h3>
<ul>
<p>KNX is a standard for building automation / home automation. It is mainly based on a twisted pair wiring, but also other mediums (ip, wireless) are specified.</p>
<p>For getting started, please refer to this document: <a href="https://www.knx.org/knx-en/for-your-home/">KNX for your home</a> auf der knx.org WebSeite.</p>
<p>While the <a href="#TUL">TUL-module</a>, <a href="#KNXTUL">KNXTUL-module</a>, or <a href="#KNXIO">KNXIO-module</a> represent the connection to the KNX network, 
 the KNX module represent a individual KNX device. <br /> 
This module provides a basic set of operations (on, off, toggle, on-until, on-for-timer) to switch on/off KNX devices and to send values to the bus.&nbsp;</p>
<p>Sophisticated setups can be achieved by combining multiple KNX-groupaddresses:datapoints (GAD's:dpt's) in one KNX device instance.</p>
<p>KNX defines a series of Datapoint Type as standard data types used to allow general interpretation of values of devices manufactured by different companies.
 These datatypes are used to interpret the status of a device, so the state in FHEM will then show the correct value.</p>
<p>For each received telegram there will be a reading with containing the received value and the sender address.<br /> 
For every set, there will be a reading containing the sent value.<br /> 
The reading &lt;state&gt; will be updated with the last sent or received value.&nbsp;</p>
<p>A (german) wiki page is available here: <a href="http://www.fhemwiki.de/wiki/KNX">FHEM Wiki</a>

<a id="KNX-define"></a>
<p><strong>Define</strong></p>
<p><code>define &lt;name&gt; KNX &lt;group&gt;:&lt;dpt&gt;[:[gadName]:[set|get|listenonly]:[nosuffix]] [&lt;group&gt;:&lt;dpt&gt; ..] <del>[IODev]</del></code></p>
<p><strong>Important:&nbsp;a KNX device needs at least one&nbsp;concrete DPT.</strong> Please refer to <a href="#KNX-dpt">available DPT</a>. Otherwise the system cannot en- or decode the messages.<br />
<strong>Devices defined by autocreate have to be reworked with the suitable dpt and the disable attribute cleared. Otherwise they won't do anything.</strong></p>

<p>The &lt;group&gt; parameters are either a group name notation (0-31/0-15/0-255) or the hex representation of the value ([00-1f][0-f][00-ff]) (5 digits). 
 All of the defined groups can be used for bus-communication. 
 It is not allowed to have the same group more then once in one device. You can have multiple devices containing the same adresses.<br /> 
As described above the parameter &lt;DPT&gt; must contain the corresponding DPT.<br /> 
The optional parameteter [gadName] may contain an alias for the GAD. <del>The gadName <b>must not</b> begin with one of the following strings:</del> The following gadNames are <b>not allowed:</b> on, off, on-for-timer,
 on-until, off-for-timer, off-until, toggle, raw, rgb, string, value, set, get, listenonly, nosuffix -  because of conflict with cmds & parameters.<br />
Especially if attribute <code>answerReading</code> is set to 1, it might be useful to modifiy the behaviour of single GADs. If you want to restrict the GAD, you can raise the flags "get", "set", or "listenonly".
 The usage should be self-explanatory. It is not possible to combine the flags.<br /> 
<b>Specifying an IO-Device in define is now deprecated!</b> Use <a href="#KNX-attr-IODev">IODev Attribute</a> instead, but only if absolutely required!</p>
<p>The GAD's are per default named with "g&lt;number&gt;". The corresponding reading-names are getG&lt;number&gt;, setG&lt;number&gt; and putG&lt;number&gt;.<br /> 
If you supply &lt;gadName&gt; this name is used instead. The readings are &lt;gadName&gt;-get, &lt;gadName&gt;-set and &lt;gadName&gt;-put. 
We will use the synonyms &lt;getName&gt;, &lt;setName&gt; and &lt;putName&gt; in this documentation.
If you add the option "nosuffix", &lt;getName&gt;, &lt;setName&gt; and &lt;putName&gt; have the identical name - only &lt;gadName&gt;.</p>
<p>Per default, the first group is used for sending. If you want to send via a different group, you have to address it. E.g: <code>set &lt;name&gt; &lt;gadName&gt; &lt;value&gt; </code></p>
<p>Without further attributes, all incoming and outgoing messages are translated into reading &lt;state&gt;.</p>
<p>If enabled, the module <a href="#autocreate">autocreate</a> is creating a new definition for any unknown sender. The device itself will be disabled
 until you added a DPT to the definition and clear the disabled attribute. The name will be KNX_nnmmooo where nn is the line adress, mm the area and ooo the device.
 No FileLog or SVG definition is created for KNX-devices by autocreate. Use for example <code>define &lt;name&gt; FileLog &lt;filename&gt; KNX_.*</code> 
 to create a single FileLog-definition for all KNX-devices created by autocreate.<br />  
 Another option is to disable autocreate for KNX-devices in production environments (when no changes / additions are expected) by using&colon; <code>attr &lt;autocreate&gt; ignoreTypes KNX_.*</code></p>

<p>Examples:</p>
<ul>
<code>define lamp1 KNX 0/10/11:dpt1:listenonly</code><br/>
<code>attr lamp1 webCmd on:off</code><br/>
<code>attr lamp1 devStateIcon on::off off::on</code><br/>
<br/>
<code>define lamp2 KNX 0/10/12:dpt1:steuern 0/10/13:dpt1.001:status</code><br/>
<br/>
<code>define lamp3 KNX 00A0D:dpt1.003</code><br/>
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
<p>Examples:</p>
<ul>
<code>set lamp2 on # gadName omitted</code><br/>
<code>set lamp2 off # gadName omitted</code><br/>
<code>set lamp2 g1 on</code><br/>
<code>set lamp2 g1 off</code><br/>
<code>set lamp2 g1 on-for-timer 10</code><br/>
<code>set lamp2 g1 on-until 13:15:00</code><br/>
<code>set lamp3 steuern on-until 13:15:00</code><br/>
<code>set lamp3 steuern toogle    # lamp3 change state</code><br/>
<code>set lamp3 steuern blink 2 4 # lamp3 on for 4 seconds, off for 4 seconds, 2 repeats</code><br/>
<br/>
<code>set myThermoDev g1 23.44</code><br/>
<br/>
<code>set myMessageDev g1 Hallo Welt # dpt16 def</code><br/>
</ul>

<a id="KNX-get"></a>
<p><strong>Get</strong></p>
<p>If you execute "get" for a KNX-Element the status will be requested from the device. The device has to be able to respond to a read - this might not be supported by the target device.<br /> 
If the GAD is restricted in the definition with "set", the execution will be refused.<br /> 
The answer from the bus-device updates reading and state.</p>

<a id="KNX-attr"></a>
<p><strong>Common attributes</strong></p>
<ul>
<a href="#DbLogattr">DbLogInclude</a><br /> 
<a href="#DbLogattr">DbLogExclude</a><br />
<a href="#DbLogattr">DbLogValueFn</a><br />
<a href="#alias">alias</a><br /> 
<a href="#cmdIcon">cmdIcon</a><br />
<a href="#comment">comment</a><br /> 
<a href="#devStateIcon">devStateIcon</a><br /> 
<a href="#devStateStyle">devStateStyle</a><br /> 
<a href="#readingFnAttributes">event-aggregator</a><br /> 
<a href="#readingFnAttributes">event-min-interval</a><br /> 
<a href="#readingFnAttributes">event-on-change-reading</a><br /> 
<a href="#readingFnAttributes">event-on-update-reading</a><br /> 
<a href="#eventMap">eventMap</a><br />
<a href="#group">group</a><br /> 
<a href="#icon">icon</a><br /> 
<a href="#readingFnAttributes">oldreadings</a><br />
<a href="#room">room</a><br /> 
<a href="#showtime">showtime</a><br /> 
<a href="#sortby">sortby</a><br /> 
<a href="#readingFnAttributes">stateFormat</a><br />
<a href="#readingFnAttributes">timestamp-on-change-reading</a><br /> 
<a href="#readingFnAttributes">userReadings</a><br /> 
<a href="#userattr">userattr</a><br />
<a href="#verbose">verbose</a><br /> 
<a href="#webCmd">webCmd</a><br /> 
<a href="#webCmdLabel">webCmdLabel</a><br /> 
<a href="#widgetOverride">widgetOverride</a>
</ul>

<p><strong>Special attributes</strong></p>
<ul>
<a id="KNX-attr-answerReading"></a><li>answerReading<br/>
  If enabled, FHEM answers on read requests. The content of reading &lt;state&gt; is sent to the bus as answer. 
  If defined, the content of the reading &lt;putName&gt; is used as value for the answer.</li>
<br/>
<a id="KNX-attr-stateRegex"></a><li>stateRegex<br/>
  You can pass n pairs of regex-patterns and strings to replace, seperated by a space. A regex-pair is always in the format /&lt;readingName&gt;[:&lt;value&gt;]/[2nd part]/.
  The first part of the regex must exactly match the readingname, and optional the readingValue, separated by a colon. If first part match, the matching part will be replaced by the 2nd part of the regex.
  If the 2nd part is empty, the value will be ignored and state-reading is not updated.  
  The substitution is done every time, a reading is updated. You can use this function for converting, adding units, having more fun with icons, ...<br/>
  This function has only an impact on the content of reading state. It is executed directly after replacing the reading-names and setting the formats, but before stateCmd.</li>
<br/>
<a id="KNX-attr-stateCmd"></a><li>stateCmd<br/>
  You can supply a perl-command for modifying state. This command is executed directly before updating the reading - so after renaming, format and regex. 
  Please supply a valid perl command like using the attribute stateFormat.<br/>
  Unlike stateFormat the stateCmd modifies also the content of the reading, not only the hash-content for visualization.<br/>
  You can access the device-hash ("$hash") in the perl string (e.g: $hash{IODev} )in yr. perl-cmd. In addition the variables "$name", "$gadName" and "$state" are avavailable. 
  The return-value overrides "state".</li>
<br/>
<a id="KNX-attr-putCmd"></a> <li>putCmd<br/>
  Every time a KNX-value is requested from the bus to FHEM, the content of putCmd is evaluated before the answer is sent. You can supply a perl-command for modifying content. 
  If  putCmd is defined, the attr answerReading has no effect.
  This command is executed directly before sending the data. A copy is stored in the reading &lt;putName&gt;.<br/>
  Each device only knows one putCmd, so you have to take care about the different GAD's in the perl string.<br/>
  Like in stateCmd you can access the device hash ("$hash") in yr. perl-cmd. In addition the variables "$name", "$gadName" and "$state" are avavailable. 
  "$state" contains the prefilled return-value. The return-value overrides "state".</li>
<br/>
<a id="KNX-attr-format"></a><li>format<br/>
  The content of this attribute is appended to every received value, before copied to state.</li>
<br/>
<a id="KNX-attr-disable"></a><li>disable<br/>
  Disable the device if set to <b>1</b>. No send/receive from bus and no set/get possible. Delete this attr to enable device again.</li>
<br/>
<a id="KNX-attr-KNX_toggle"></a><li>KNX_toggle<br/>
  Lookup current value before issuing "set device &lt;gadName&gt; toggle" cmd.<br/> 
  FHEM has to retrieve a current value to make the toggle-cmd acting correctly. This attribute can be used to define the source of the current value.<br/>
  Format is: <b>&lt;devicename&gt;&colon;&lt;readingname&gt;</b>. If you want to use a reading from own device, you can use "$self" as devicename. Be aware that only <b>on</b> and <b>off</b> 
  are supported as valid values when defining device:readingname.<br/>
  If this attribute is not defined, the current value will be taken from owndevice:readingName-get or, if readingName-get is not defined, the value will be taken from readingName-set.</li>
<br/>
<a id="KNX-attr-IODev"></a><li>IODev<br/>
  Due to changes in IO-Device handling, (default IO-Device will be stored in <b>reading IODev</b>), setting this Attribute is no longer required,  
  except in cases where multiple IO-devices (of type TUL/KNXTUL/KNXIO) are defined. Defining more than one IO-device is <b>NOT recommended</b> 
  unless you take special care with yr. knxd or KNX-router definitions - to prevent multiple path from KNX-Bus to FHEM resulting in message loops.</li>   
<br/>
<!--<a id="KNX-attr-KNX_FIFO"></a><li>KNX_FIFO<br/> 
  Set this attr to 1 <b> in the IO-device ! </b>to enable a receive buffer for incoming messages. The KNX-messages will not processed faster,
  but the overall responsiveness and latency of FHEM benefit from this setting.</li>
<br/>
-->
<a id="KNX-attr-listenonly"></a><li>listenonly - This attr is deprecated - do not use - see cmdref device definition for alternatives</li> 
<a id="KNX-attr-readonly"></a><li>readonly - This attr is deprecated - do not use - see cmdref device definition for alternatives</li>
<a id="KNX-attr-slider"></a><li>slider - This attr is deprecated - do not use - see slider example in cmdref for alternatives</li>
<a id="KNX-attr-useSetExtensions"></a><li>useSetExtensions - This attr is deprecated - do not use</li>
</ul>

<a id="KNX-dpt"></a>
<p><strong>DPT - data-point-types</strong></p>
<p>The following dpt are implemented and have to be assigned within the device definition. 
   The values right to the dpt define the valid range of Set-command values and Get-command return values.</p>
<ul>
<li><b>dpt1     </b>     off, on, toggle</li>
<li><b>dpt1.000 </b>  0, 1</li>
<li><b>dpt1.001 </b>  off, on, toggle</li>
<li><b>dpt1.002 </b>  false, true</li>
<li><b>dpt1.003 </b>  disable, enable</li>
<li><b>dpt1.004 </b>  no ramp, ramp</li>
<li><b>dpt1.005 </b>  no alarm, alarm</li>
<li><b>dpt1.006 </b>  low, high</li>
<li><b>dpt1.007 </b>  decrease, increase</li>
<li><b>dpt1.008 </b>  up, down</li>
<li><b>dpt1.009 </b>  open, closed</li>
<li><b>dpt1.010 </b>  stop, start</li>
<li><b>dpt1.011 </b>  inactive, active</li>
<li><b>dpt1.012 </b>  not inverted, inverted</li>
<li><b>dpt1.013 </b>  start/stop, ciclically</li>
<li><b>dpt1.014 </b>  fixed, calculated</li>
<li><b>dpt1.015 </b>  no action, reset</li>
<li><b>dpt1.016 </b>  no action, acknowledge</li>
<li><b>dpt1.017 </b>  trigger_0, trigger_1</li>
<li><b>dpt1.018 </b>  not occupied, occupied</li>
<li><b>dpt1.019 </b>  closed, open</li>
<li><b>dpt1.021 </b>  logical or, logical and</li>
<li><b>dpt1.022 </b>  scene A, scene B</li>
<li><b>dpt1.023 </b>  move up/down, move and step mode</li>
<li><b>dpt2     </b>     off, on, forceOff, forceOn</li>
<li><b>dpt2.000 </b>  0,1,2,3</li>
<li><b>dpt3     </b>     -100..+100</li>
<li><b>dpt3.007 </b>  -100..+100 %</li>
<li><b>dpt5     </b>     0..255</li>
<li><b>dpt5.001 </b>  0..100 %</li>
<li><b>dpt5.003 </b>  0..360 &deg;</li>
<li><b>dpt5.004 </b>  0..255 %</li>
<li><b>dpt6     </b>     -128..+127</li>
<li><b>dpt6.001 </b>  -128 %..+127 %</li>
<li><b>dpt6.010 </b>  -128..+127</li>
<li><b>dpt7     </b>     0..65535</li>
<li><b>dpt7.001 </b>  0..65535 s</li>
<li><b>dpt7.005 </b>  0..65535 s</li>
<li><b>dpt7.006 </b>  0..65535 m</li>
<li><b>dpt7.007 </b>  0..65535 h</li>
<li><b>dpt7.012 </b>  0..65535 mA</li>
<li><b>dpt7.013 </b>  0..65535 lux</li>
<li><b>dpt7.600 </b>  0..12000 K</li>
<li><b>dpt8     </b>     -32768..32768</li>
<li><b>dpt8.005 </b>  -32768..32768 s</li>
<li><b>dpt8.010 </b>  -32768..32768 %</li>
<li><b>dpt8.011 </b>  -32768..32768 &deg;</li>
<li><b>dpt9     </b>     -670760.0..+670760.0</li>
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
<li><b>dpt9.028 </b>  -670760.0..+670760.0 km/h</li>
<li><b>dpt9.029 </b>  -670760.0..+670760.0 g/m&sup3;</li>
<li><b>dpt9.030 </b>  -670760.0..+670760.0 &mu;g/m&sup3;</li>
<li><b>dpt10    </b>     01:00:00 (Time: HH:MM:SS)</li>
<li><b>dpt11    </b>     01.01.2000 (Date: DD.MM.YYYY)</li>
<li><b>dpt12    </b>     0..+Inf</li>
<li><b>dpt13    </b>     -Inf..+Inf</li>
<li><b>dpt13.010</b>  -Inf..+Inf Wh</li>
<li><b>dpt13.013</b>  -Inf..+Inf kWh</li>
<li><b>dpt14    </b>     -Inf.0..+Inf.0</li>
<li><b>dpt14.019</b>  -Inf.0..+Inf.0 A</li>
<li><b>dpt14.027</b>  -Inf.0..+Inf.0 V</li>
<li><b>dpt14.033</b>  -Inf.0..+Inf.0 Hz</li>
<li><b>dpt14.056</b>  -Inf.0..+Inf.0 W</li>
<li><b>dpt14.057</b>  -Inf.0..+Inf.0 cos&Phi;</li>
<li><b>dpt14.068</b>  -Inf.0..+Inf.0 &deg;C</li>
<li><b>dpt14.076</b>  -Inf.0..+Inf.0 m&sup3;</li>
<li><b>dpt16    </b>     String</li>
<li><b>dpt16.000</b>  ASCII-String</li>
<li><b>dpt16.001</b>  ISO-8859-1-String (Latin1)</li>
<li><b>dpt17.001</b>  Scene number: 0..63</li>
<li><b>dpt18.001</b>  Scene number: 1..64. <br/>   Watch out - only "activation" works. <br/>   "Learning" will be limited to 64...</li>
<li><b>dpt19    </b>     01.12.2020_01:02:03 (Date&Time)</li>
<li><b>dpt19.001</b>  01.12.2020_01:02:03</li>
<li><b>dpt20.102</b>  HVAC mode</li>
<li><b>dpt22.101</b>  not yet implemented</li>
<li><b>dpt232   </b>     RGB-Value RRGGBB</li>
</ul>

<a id="KNX-examples"></a>
<p><strong>More complex examples </strong>can be found on the (german) <a href="http://www.fhemwiki.de/wiki/KNX_Device_Definition_-_Beispiele">Wiki</a></p> 
<br/>
</ul>

=end html

=cut
