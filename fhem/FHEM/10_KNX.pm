##############################################
# $Id$
# ABU 20160307 First release
# ABU 20160309 Fixed issue for sending group-indexed with dpt1. Added debug-information. Fixed issue for indexed get. Fixed regex-replace-issue.
# ABU 20160312 Fixed error while receiving numeric DPT with value 0. Added factor for dpt 08.010.
# ABU 20160312 Fixed Regex-Attributes. Syntax changed from space-seperated to " /".
# ABU 20160322 Fixed dpt1.008
# ABU 20160326 Added fix for stateFormat
# ABU 20160327 Removed readingRegex, writingRegex, created stateRegex, stateCmd, added reading-name support, fixed dblog-split
# ABU 20160403 Fixed various minor perl warnings
# ABU 20160413 Changed SplitFn
# ABU 20160414 Changed SplitFn again
# ABU 20160416 Changed SplitFn again
# ABU 20160422 Added dpt9.021 - mA
# ABU 20160529 Changed Doku
# ABU 20160605 Changed Doku, changed autocreate-naming, fixed dpt10-sending-now
# ABU 20160608 changed sprintf for int-dpt from %d to %.0f
# ABU 20160624 corrected Doku: till->until
# ABU 20161121 cleaned get/set options
# ABU 20161122 fixed set-handling
# ABU 20161126 added summary
# ABU 20161126 fixed doku
# ABU 20161127 adjusted dpt-16-sending, added dpt16.001
# ABU 20161129 fixed get-mechanism
# ABU 20170106 corrected doku for time, finetuned dpt9-regex, added dpt 7.001 7.012 9.007 9.008, , added mod for extended adressing (thx to its2bit)
# ABU 20170110 removed mod for extended adressing
# ABU 20100114 fixed dpt9-regex
# ABU 20100116 fixed dpt9-regex again
# ABU 20170427 reintegrated mechanism for extended adressing
# ABU 20170427 integrated setExtensions
# ABU 20170427 added dpt1.010 (start/stop)
# ABU 20170427 added dpt2
# ABU 20170503 corrected DPT1.010
# ABU 20170503 changed regex for all dpt9
# ABU 20170507 changed regex for all dpt9
# ABU 20170517 added useSetExtensions
# ABU 20170622 finetuned doku
# ABU 20171006 added sub-dpt1
# ABU 20171006 added dpt19

package main;

use strict;
use warnings;
use Encode;
use SetExtensions;

#set to 1 for debug
my $debug = 0;

#string constant for autocreate
my $modelErr = "MODEL_NOT_DEFINED";

my $OFF = "off";
my $ON = "on";
my $ONFORTIMER = "on-for-timer";
my $ONUNTIL = "on-until";
my $VALUE = "value";
my $STRING = "string";
my $RAW = "raw";
my $RGB = "rgb";

#valid set commands
my %sets = (
	#"off" => "noArg",
	#"on" => "noArg",
	$OFF => "",
	$ON => "",
	$ONFORTIMER => "",
	$ONUNTIL => "",
	$VALUE => "",
	$STRING => "",
	$RAW => "",
	$RGB => "colorpicker"
);

#identifier for TUL
my $id = 'C';

#regex patterns
my $PAT_GAD = qr/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/;
#old syntax
#my $PAT_GAD_HEX = qr/^[0-9a-f]{4}$/;
#new syntax for extended adressing
my $PAT_GAD_HEX = qr/^[0-9a-f]{5}$/;
my $PAT_GNO = qr/[gG][1-9][0-9]?/;

#CODE is the identifier for the en- and decode algos. See encode and decode functions
#UNIT is appended to state for a better reading
#FACTOR and OFFSET are used to normalize a value. value = FACTOR * (RAW - OFFSET). Must be undef for non-numeric values.
#PATTERN is used to check an trim the input-values
#MIN and MAX are used to cast numeric values. Must be undef for non-numeric dpt. Special Usecase: DPT1 - MIN represents 00, MAX represents 01
my %dpttypes = (
  #Binary value
	"dpt1" 			=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([oO][nN])|([oO][fF][fF])|(0?1)|(0?0)/, MIN=>"off", MAX=>"on"},  
	"dpt1.001" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([oO][nN])|([oO][fF][fF])|(0?1)|(0?0)/, MIN=>"off", MAX=>"on"},
	"dpt1.002" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([tT][rR][uU][eE])|([fF][aA][lL][sS][eE])|(0?1)|(0?0)/, MIN=>"false", MAX=>"true"},
	"dpt1.003" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(([eE][nN]|[dD][iI][sS])[aA][bB][lL][eE])|(0?1)|(0?0)/, MIN=>"disable", MAX=>"enable"},
	"dpt1.004"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"no ramp", MAX=>"ramp"},
	"dpt1.005"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"no alarm", MAX=>"alarm"},
	"dpt1.006"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"low", MAX=>"high"},
	"dpt1.007"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"decrease", MAX=>"increase"},
	"dpt1.008" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([uU][pP])|([dD][oO][wW][nN])|(0?1)|(0?0)/, MIN=>"up", MAX=>"down"},
	"dpt1.009" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([cC][lL][oO][sS][eE][dD])|([oO][pP][eE][nN])|(0?1)|(0?0)/, MIN=>"open", MAX=>"closed"},
	"dpt1.010" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([sS][tT][aA][rR][tT])|([sS][tT][oO][pP])|(0?1)|(0?0)/, MIN=>"stop", MAX=>"start"},
	"dpt1.011"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"inactive", MAX=>"active"},
	"dpt1.012"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"not inverted", MAX=>"inverted"},
	"dpt1.013"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"start/stop", MAX=>"cyclically"},
	"dpt1.014"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"fixed", MAX=>"calculated"},
	"dpt1.015"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"no action", MAX=>"reset"},
	"dpt1.016"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"no action", MAX=>"acknowledge"},
	"dpt1.017"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"trigger", MAX=>"trigger"},
	"dpt1.018"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"not occupied", MAX=>"occupied"},
	"dpt1.019" 		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([cC][lL][oO][sS][eE][dD])|([oO][pP][eE][nN])|(0?1)|(0?0)/, MIN=>"closed", MAX=>"open"},	
	"dpt1.021"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"logical or", MAX=>"logical and"},
	"dpt1.022"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"scene A", MAX=>"scene B"},
	"dpt1.023"		=> {CODE=>"dpt1", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(0?1)|(0?0)/, MIN=>"move up/down", MAX=>"move and step mode"},

	#Step value (two-bit)
	"dpt2" 			=> {CODE=>"dpt2", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/([oO][nN])|([oO][fF][fF])|([fF][oO][rR][cC][eE][oO][nN])|([fF][oO][rR][cC][eE][oO][fF][fF])/, MIN=>undef, MAX=>undef},
	  
	#Step value (four-bit)
	"dpt3" 			=> {CODE=>"dpt3", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>-100, MAX=>100},

	# 1-Octet unsigned value
	"dpt5" 			=> {CODE=>"dpt5", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>0, MAX=>255},
	"dpt5.001" 		=> {CODE=>"dpt5", UNIT=>"%", FACTOR=>100/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>0, MAX=>100},  
	"dpt5.003" 		=> {CODE=>"dpt5", UNIT=>"&deg;", FACTOR=>360/255, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>0, MAX=>360},
	"dpt5.004" 		=> {CODE=>"dpt5", UNIT=>"%", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>0, MAX=>255},
	
	# 1-Octet signed value
	"dpt6" 			=> {CODE=>"dpt6", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>-127, MAX=>127},
	"dpt6.001" 		=> {CODE=>"dpt6", UNIT=>"%", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,3}/, MIN=>0, MAX=>100},

	# 2-Octet unsigned Value 
	"dpt7" 			=> {CODE=>"dpt7", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>0, MAX=>65535},
	"dpt7.001" 			=> {CODE=>"dpt7", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>0, MAX=>65535},
	"dpt7.005" 		=> {CODE=>"dpt7", UNIT=>"s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>0, MAX=>65535},
	"dpt7.006" 		=> {CODE=>"dpt7", UNIT=>"m", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>0, MAX=>65535},
	"dpt7.012" 		=> {CODE=>"dpt7", UNIT=>"mA", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>0, MAX=>65535},	
	"dpt7.013" 		=> {CODE=>"dpt7", UNIT=>"lux", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>0, MAX=>65535},

	# 2-Octet signed Value 
	"dpt8" 			=> {CODE=>"dpt8", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>-32768, MAX=>32768},
	"dpt8.005" 		=> {CODE=>"dpt8", UNIT=>"s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>-32768, MAX=>32768},
	"dpt8.010" 		=> {CODE=>"dpt8", UNIT=>"%", FACTOR=>0.01, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>-32768, MAX=>32768},
	"dpt8.011" 		=> {CODE=>"dpt8", UNIT=>"&deg;", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,5}/, MIN=>-32768, MAX=>32768},

	# 2-Octet Float value
	"dpt9"	 		=> {CODE=>"dpt9", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},
	"dpt9.001"	 	=> {CODE=>"dpt9", UNIT=>"&deg;C", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.004"	 	=> {CODE=>"dpt9", UNIT=>"lux", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.006"	 	=> {CODE=>"dpt9", UNIT=>"Pa", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.005"	 	=> {CODE=>"dpt9", UNIT=>"m/s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.007"	 	=> {CODE=>"dpt9", UNIT=>"%", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.008"	 	=> {CODE=>"dpt9", UNIT=>"ppm", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.009"	 	=> {CODE=>"dpt9", UNIT=>"m&sup3/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.010"	 	=> {CODE=>"dpt9", UNIT=>"s", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.021"	 	=> {CODE=>"dpt9", UNIT=>"mA", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},		
	"dpt9.024"	 	=> {CODE=>"dpt9", UNIT=>"kW", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.025"	 	=> {CODE=>"dpt9", UNIT=>"l/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.026"	 	=> {CODE=>"dpt9", UNIT=>"l/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},	
	"dpt9.028"	 	=> {CODE=>"dpt9", UNIT=>"km/h", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[-+]?(?:\d*[\.\,])?\d+/, MIN=>-670760, MAX=>670760},		
  
	# Time of Day
	"dpt10"			=> {CODE=>"dpt10", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((2[0-4]|[0?1][0-9]):(60|[0?1-5]?[0-9]):(60|[0?1-5]?[0-9]))|([nN][oO][wW])/, MIN=>undef, MAX=>undef},
  
	# Date  
	"dpt11"			=> {CODE=>"dpt11", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/((3[01]|[0-2]?[0-9]).(1[0-2]|0?[0-9]).(19[0-9][0-9]|2[01][0-9][0-9]))|([nN][oO][wW])/, MIN=>undef, MAX=>undef},
  
	# 4-Octet unsigned value (handled as dpt7)
	"dpt12" 		=> {CODE=>"dpt12", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/, MIN=>0, MAX=>4294967295},
  
	# 4-Octet Signed Value
	"dpt13" 		=> {CODE=>"dpt13", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/, MIN=>-2147483647, MAX=>2147483647},
	"dpt13.010" 	=> {CODE=>"dpt13", UNIT=>"Wh", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/, MIN=>-2147483647, MAX=>2147483647},
	"dpt13.013" 	=> {CODE=>"dpt13", UNIT=>"kWh", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,10}/, MIN=>-2147483647, MAX=>2147483647},

	# 4-Octet single precision float
	"dpt14"			=> {CODE=>"dpt14", UNIT=>"", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/, MIN=>undef, MAX=>undef},
	"dpt14.019"		=> {CODE=>"dpt14", UNIT=>"A", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/, MIN=>undef, MAX=>undef},
	"dpt14.027"		=> {CODE=>"dpt14", UNIT=>"V", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/, MIN=>undef, MAX=>undef},    
	"dpt14.056"		=> {CODE=>"dpt14", UNIT=>"W", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/, MIN=>undef, MAX=>undef},
	"dpt14.068"		=> {CODE=>"dpt14", UNIT=>"&deg;C", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/, MIN=>undef, MAX=>undef},  
	"dpt14.076"		=> {CODE=>"dpt14", UNIT=>"m&sup3;", FACTOR=>1, OFFSET=>0, PATTERN=>qr/[+-]?\d{1,40}[.,]?\d{1,4}/, MIN=>undef, MAX=>undef},  
  
	# 14-Octet String
	"dpt16"         => {CODE=>"dpt16", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/, MIN=>undef, MAX=>undef},
	"dpt16.000"     => {CODE=>"dpt16", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/, MIN=>undef, MAX=>undef},
	"dpt16.001"     => {CODE=>"dpt16", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/.{1,14}/, MIN=>undef, MAX=>undef},

	"dpt19"			=> {CODE=>"dpt19", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/(((3[01]|[0-2]?[0-9]).(1[0-2]|0?[0-9]).(19[0-9][0-9]|2[01][0-9][0-9]))_((2[0-4]|[0?1][0-9]):(60|[0?1-5]?[0-9]):(60|[0?1-5]?[0-9])))|([nN][oO][wW])/, MIN=>undef, MAX=>undef},

	# Color-Code
	"dpt232"        => {CODE=>"dpt232", UNIT=>"", FACTOR=>undef, OFFSET=>undef, PATTERN=>qr/[0-9A-Fa-f]{6}/, MIN=>undef, MAX=>undef},
);

#Init this device
#This declares the interface to fhem
#############################
sub
KNX_Initialize($) {
	my ($hash) = @_;

	$hash->{Match}     		= "^$id.*";
	$hash->{GetFn}     		= "KNX_Get";
	$hash->{SetFn}     		= "KNX_Set";
	$hash->{StateFn}   		= "KNX_State";
	$hash->{DefFn}     		= "KNX_Define";
	$hash->{UndefFn}   		= "KNX_Undef";
	$hash->{ParseFn}   		= "KNX_Parse";
	$hash->{AttrFn}   		= "KNX_Attr";
	$hash->{NotifyFn}  		= "KNX_Notify";	
	$hash->{DbLog_splitFn}  = "KNX_DbLog_split";
	$hash->{AttrList}  		= 	"IODev " .					#tells the module the IO-Device to communicate with. Optionally set within definition.
								"do_not_notify:1,0 " . 		#supress any notification (including log)
								"listenonly:1,0 " . 		#device may not send any messages. answering is prohibited. get is prohibited.							
								"readonly:1,0 " .			#device may not send any messages. answering is prohibited. get is allowed.							
								"showtime:1,0 " . 			#shows time instead of received value in state
								"answerReading:1,0 " .		#allows FHEM to answer a read telegram
								"stateRegex " .				#modifies state value
								"stateCmd " .				#modify state value
								"stateCopy " .				#backup content of state in this reading (only for received telegrams)
								"format " .					#supplies post-string
								"slider " .					#creates slider. Syntax: min, step, max
								"$readingFnAttributes ";	#standard attributes
}

#Define this device
#Is called at every define
#############################
sub
KNX_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	#device name
	my $name = $a[0];
	
	#set verbose to 5, if debug enabled
	$attr{$name}{verbose} = 5 if ($debug eq 1);

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "define $name: enter $hash, attributes: $tempStr");
	
	#too less arguments
	return "wrong syntax - define <name> KNX <group:model[:reading-name]> [<group:model[:reading-name]>*] [<IODev>]" if (int(@a) < 3);
	
	#check for IODev
	#is last argument a group or a group:model pair?
	my $lastGroupDef = int(@a);
	#if (($a[int(@a) - 1] !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i) and ($a[int(@a) - 1] !~ m/^[0-9a-f]{4}$/i) and ($a[int(@a) - 1] !~ m/[0-9a-fA-F]:[dD][pP][tT]/i))
	if (($a[int(@a) - 1] !~ m/${PAT_GAD}/i) and ($a[int(@a) - 1] !~ m/${PAT_GAD_HEX}/i) and ($a[int(@a) - 1] !~ m/[0-9a-fA-F]:[dD][pP][tT]/i))
	{
		$attr{$name}{IODev} = $a[int(@a) - 1];
		$lastGroupDef--; 
	}
	
	#create groups and models, iterate through all possible args
	for (my $i = 2; $i < $lastGroupDef; $i++)
	{
		#backup actual GAD
		my $inp = lc($a[$i]); 
		my ($group, $model, $rdname) = split /:/, $inp;
		my $groupc;
		#G-nr
		my $gno = $i - 1;
		
		#GAD not defined
		return "GAD not defined for group-number $gno" if (!defined($group));
		
		#GAD wrong syntax
		#either 1/2/3 or 1203
		#return "wrong group name format: specify as 0-15/0-15/0-255 or as hex" if (($group !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i)  && (lc($group) !~ m/^[0-9a-f]{4}$/i));
		return "wrong group name format: specify as 0-15/0-15/0-255 or as hex" if (($group !~ m/${PAT_GAD}/i)  && (lc($group) !~ m/${PAT_GAD_HEX}/i));
		
		#check if model supplied
		return "no model defined" if (!defined($model));
		
		#within autocreate no model is supplied - throw warning
		if ($model eq $modelErr)
		{
			Log3 ($name, 2, "define $name: autocreate defines no model - only restricted functions are available");
		}
		else
		{
			#check model-type
			return "invalid model. Use " .join(",", keys %dpttypes) if (!defined($dpttypes{$model}));
		}
				
		#convert to string, if supplied in Hex
		#old syntax
		#$group = KNX_hexToName ($group) if ($group =~ m/^[0-9a-f]{4}$/i);
		#new syntax for extended adressing
		$group = KNX_hexToName ($group) if ($group =~ m/^[0-9a-f]{5}$/i);

		$groupc = KNX_nameToHex ($group);
		
		Log3 ($name, 5, "define $name: found GAD: $group, NO: $gno, HEX: $groupc, DPT: $model");
		Log3 ($name, 5, "define $name: found Readings-Name: $rdname") if (defined ($rdname));
		
		#add indexed group to hash. Index starts with one
		#readable GAD
		$hash->{GADDR}{$gno} = $group;
		#same as hex
		$hash->{GCODE}{$gno} = $groupc;
		#model
		$hash->{MODEL}{$gno} = $model;
		#backup readings-name
		$hash->{READINGSNAME}{$gno} = $rdname if (defined ($rdname) and !($rdname eq ""));
	}

	#common name
	$hash->{NAME} = $name;	
	#backup name for a later rename
	$hash->{DEVNAME} = $name;
	
	#finally create decice
	#defptr is needed to supress FHEM input
	$modules{KNX}{defptr}{$name} = $hash;
	
	#assign io-dev automatically, if not given via definition	
	AssignIoPort($hash);
	
	Log3 ($name, 5, "exit define");
	
	CommandDefine(undef, 'findMe');
	CommandDefine('myClass', 'findMe2');
	
	return undef;
}

#Release this device
#Is called at every delete / shutdown
#############################
sub
KNX_Undef($$) {
	my ($hash, $name) = @_;

	Log3 ($name, 5, "enter undef $name: hash: $hash name: $name");
	
	#remove all groups
	foreach my $group (keys %{$hash->{GCODE}}) 
	{
		Log3 ($name, 5, "undef $name: remove name: $hash->{NAME}, orig.-Name: $hash->{DEVNAME}, GAD: $group");
		delete $hash->{GADDR}{$group};		
		delete $hash->{GCODE}{$group};		
		delete $hash->{MODEL}{$group};
	}
	
	#remove module. Refer to DevName, because module may be renamed
	delete $modules{KNX}{defptr}{$hash->{DEVNAME}};

	#remove name
	delete $hash->{NAME};
	#remove backuped name
	delete $hash->{DEVNAME};
		
	Log3 ($name, 5, "exit undef");
	return undef;
}

#Places a "read" Message on the KNX-Bus
#The answer is treated as regular telegram
#############################
sub
KNX_Get($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $groupnr = 1;

	my $tempStr = join (", ", @a);
	Log3 ($name, 5, "enter get $name: hash: $hash, attributes: $tempStr");
	
	#FHEM asks with a ? at startup - no action, no log
	#do not use KNX_getCmdList because argument will be a group-adress
	return "Unknown argument ?, choose one of -" if(defined($a[1]) and ($a[1] =~ m/\?/));
	
	splice(@a, 1, 1) if (defined ($a[1]) and ($a[1] =~ m/-/));
	my $na = int(@a);
	
	#not more then 2 arguments allowed
	return "too much arguments. Only one argument allowed (group-address)." if($na>2);
	
	# the command can be send to any of the defined groups indexed starting by 1
	# optional last argument starting with g indicates the group
	if(defined ($a[1]))
	{
		#check syntax
		if ($a[1]=~ m/${PAT_GNO}/)
		{
			#assign group-no
			$groupnr = $a[1];
			$groupnr =~ s/^g//;
		} else
		{
			return "$a[1] is invalid. Second argument only may be a group g<no>";	
		}
	}

	#get group from hash (hex)
	my $groupc = $hash->{GCODE}{$groupnr};
	#get group from hash
	my $group = $hash->{GADDR}{$groupnr};
	
	#return, if unknown group
	return "groupnr: $groupnr not known" if(!$groupc);
	
	#exit, if reat is prohibited
	return "did not request a value - \"listenonly\" is set." if (AttrVal ($name, "listenonly", 0) =~ m/1/);
  	
	#send read-request to the bus
	Log3 ($name, 5, "get $name: request value for GAD $group");
	IOWrite($hash, $id, "r" . $groupc);
	
  	Log3 ($name, 5, "exit get");
	
	return "current value for $name ($group) requested";
}

#Does something according the given cmd...
#############################
sub
KNX_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $ret = "";
	my $na = int(@a);
	
	my $tempStr = join (", ", @a);
	#log only, if not called with cmd = ?
	Log3 ($name, 5, "enter set $name: hash: $hash, attributes: $tempStr") if ((defined ($a[1])) and (not ($a[1] eq "?")));

	#return, if no set value specified
	return "no set value specified" if($na < 2);

	#return, if this is a readonly-device
	return "this device is readonly" if(defined($hash->{readonly}));
	
	#backup values
	my $cmd = lc($a[1]);
	#remove whitespaces
	$cmd =~ s/^\s+|\s+$//g;

	#get slider definition
	my $slider = AttrVal ($name, "slider", undef);
	
	#hash has to be copied. Otherwise silder-operation affects all devices
	my %mySets = %sets;	
	#append slider-definition, if set...Necessary for FHEM
	$mySets{$VALUE} = $mySets{$VALUE} . "slider,$slider" if ((defined $slider) and !($mySets{$VALUE} =~ m/slider/));
	
	#create response, if cmd is wrong or gui asks
	my $cmdTemp = KNX_getCmdList ($hash, $cmd, %mySets);
	#return "Unknown argument $cmd, choose one of " . $cmdTemp if (defined ($cmdTemp)); 
	return SetExtensions($hash, $cmdTemp, $name, $cmd, @a) if (defined ($cmdTemp));
	
	#the command can be send to any of the defined groups indexed starting by 1
	#optional last argument starting with g indicates the group
	#default
  	my $groupnr = 1;
	my $lastArg = $na - 1;
	#select another group, if the last arg starts with a g
	if($na > 2 && $a[$lastArg]=~ m/${PAT_GNO}/)
	{	
		$groupnr = $a[$lastArg];
		#remove "g"
		$groupnr =~ s/^g//g;

		$lastArg--;
	}	

	#unknown groupnr
	return "group-no. not found" if(!defined($groupnr));
	
	#group
	my $group = $hash->{GADDR}{$groupnr};
	my $groupc = $hash->{GCODE}{$groupnr};

	#unknown groupnr
	return "group-no. $groupnr not known" if(!defined($group));

	#get model
	my $model = $hash->{MODEL}{$groupnr};
	my $code = $dpttypes{$model}{CODE};	
	
	Log3 ($name, 5, "set $name: model: $model, GAD: $group, GAD hex: $groupc, gno: $groupnr");
	
	#This contains the input
	my $value = "";
	
	#delete any running timers
	if ($hash->{"ON-FOR-TIMER_G$groupnr"})
	{
		CommandDelete(undef, $name . "_timer_$groupnr");
		delete $hash->{"ON-FOR-TIMER_G$groupnr"};
	}
	if($hash->{"ON-UNTIL_G$groupnr"}) 
	{
		CommandDelete(undef, $name . "_until_$groupnr");
		delete $hash->{"ON-UNTIL_G$groupnr"};
	}	

	#set on-for-timer
	if ($cmd =~ m/$ONFORTIMER/)
	{
		return "\"on-for-timer\" only allowed for dpt1" if (not($code eq "dpt1"));
		#get duration
		my $duration = sprintf("%02d:%02d:%02d", $a[2]/3600, ($a[2]%3600)/60, $a[2]%60);
		#$modules{KNX}{"on-for-timer"}{$name} = $duration;
		$hash->{"ON-FOR-TIMER_G$groupnr"} = $duration;
		Log3 ($name, 5, "set $name: \"on-for-timer\" for $duration");		
		#set to on
		$value = 1;
		#place at-command for switching off
		CommandDefine(undef, $name . "_timer_$groupnr at +$duration set $name off g$groupnr");
	} 
	#set on-till
	elsif ($cmd =~ m/$ONUNTIL/)
	{
		return "\"on\" only allowed for dpt1" if (not($code eq "dpt1"));
		#get off-time
		my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
		
		return "Error trying to parse timespec for $a[2]: $err" if (defined($err));
		
		#build of-time
		my @lt = localtime;
		my $hms_til = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
		my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
		
		return "Won't switch - now ($hms_now) is later than $hms_til" if($hms_now ge $hms_til);

		#$modules{KNX}{"on-until"}{$name} = $hms_til;
		$hash->{"ON-UNTIL_G$groupnr"} = $hms_til;
		Log3 ($name, 5, "set $name: \"on-until\" up to $hms_til");		
		#set to on
		$value = 1;
		#place at-command for switching off
		CommandDefine(undef, $name . "_until_$groupnr at $hms_til set $name off g$groupnr");
	} 	
	#set on
	elsif ($cmd =~ m/$ON/)
	{
		return "\"on\" only allowed for dpt1" if (not($code eq "dpt1"));
		$value = 1;
	} 
	#set off
	elsif ($cmd =~ m/$OFF/)
	{
		return "\"off\" only allowed for dpt1" if (not($code eq "dpt1"));
		$value = 0;
	} 
	#set raw <value>
	elsif ($cmd =~ m/$RAW/)
	{
		return "no data for cmd $cmd" if ($lastArg < 2);
		
		#check for 1-16 hex-digits
		if ($a[2] =~ m/[0-9a-fA-F]{1,16}/)
		{
			$value = lc($a[2]);
		} else
		{
			return "$a[2] has wrong syntax. Use hex-format only.";
		}
	} 
	#set value <value>	
	elsif ($cmd =~ m/$VALUE/)
	{
		return "\"value\" not allowed for dpt1, dpt16 and dpt232" if (($code eq "dpt1") or ($code eq "dpt16") or ($code eq "dpt232"));
		#return "\"value\" not allowed for dpt1 and dpt16" if ($code eq "dpt16");
		return "no data for cmd $cmd" if ($lastArg < 2);
		
		$value = $a[2];
		#replace , with .
		$value =~ s/,/\./g;
	} 
	#set string <val1 val2 valn>
	elsif ($cmd =~ m/$STRING/)
	{
		return "\"string\" only allowed for dpt16" if (not($code eq "dpt16"));
		return "no data for cmd $cmd" if ($lastArg < 2);
		
		#join string
		for (my $i=2; $i<=$lastArg; $i++)
		{
		  $value.= $a[$i]." ";		  
		}				
	} 	
	#set RGB <RRGGBB>
	elsif ($cmd =~ m/$RGB/)
	{
		return "\"RGB\" only allowed for dpt232" if (not($code eq "dpt232"));
		return "no data for cmd $cmd" if ($lastArg < 2);

		#check for 1-16 hex-digits
		if ($a[2] =~ m/[0-9A-Fa-f]{6}/)
		{
			$value = lc($a[2]);
		} else
		{
			return "$a[2] has wrong syntax. Use hex-format only.";
		}						
	} 	
	
	#check and cast value
	my $transval = KNX_checkAndClean($hash, $value, $groupnr);
	
	return "invalid value: $value" if (!defined($transval));
		
	#exit, if sending is prohibited
	return "did not send value - \"listenonly\" is set." if (AttrVal ($name, "listenonly", 0) =~ m/1/);
	return "did not send value - \"readonly\" is set." if (AttrVal ($name, "readonly", 0) =~ m/1/);
	
	#send value
	$transval = KNX_encodeByDpt($hash, $transval, $groupnr);
	IOWrite($hash, $id, "w" . $groupc . $transval);
	
	Log3 ($name, 5, "set $name: cmd: $cmd, value: $value, translated: $transval");

	#build readingsName
	my $rdName = $hash->{READINGSNAME}{$groupnr};					
	if (defined ($rdName) and !($rdName eq ""))
	{
		Log3 ($name, 5, "set name: $name, replaced \"getG\" with custom readingName \"$rdName\"");
		$rdName = $rdName . "-set";
	}
	else
	{
		$rdName = "setG" . $groupnr;
	}

	#re-read value, do not modify variable name due to usage in cmdAttr
	$transval = KNX_decodeByDpt($hash, $transval, $groupnr);	
	#append post-string, if supplied
	my $suffix = AttrVal($name, "format",undef);
	$transval = $transval . " " . $suffix if (defined($suffix));			
	#execute regex, if defined				
	my $regAttr = AttrVal($name, "stateRegex", undef);
	my $state = KNX_replaceByRegex ($regAttr, $rdName . ":", $transval);
	Log3 ($name, 5, "set name: $name - replaced $rdName:$transval to $state") if (not ($transval eq $state));					

	if (defined($state))
	{	
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, $rdName, $transval);

		#execute state-command if defined
		#must be placed after first reading, because it may have a reference
		my $cmdAttr = AttrVal($name, "stateCmd", undef);
		if (defined ($cmdAttr) and !($cmdAttr eq ""))
		{
			$state = eval $cmdAttr;
			Log3 ($name, 5, "set name: $name - state replaced via command, result: state:$state");					
		}
		
		readingsBulkUpdate($hash, "state", $state);		
		readingsEndUpdate($hash, 1);
	}							
	
	Log3 ($name, 5, "exit set");
	return undef;
}

#In case setstate is executed, a readingsupdate is initiated
#############################
sub
KNX_State($$$$) {
	my ($hash, $time, $reading, $value) = @_;
	my $name = $hash->{NAME};

	my $tempStr = join (", ", @_);
	Log3 ($name, 5, "enter state: hash: $hash name: $name, attributes: $tempStr");
	
	#in some cases state is submitted within value - if found, take only the stuff after state
	#my @strings = split("[sS][tT][aA][tT][eE]", $val);
	#$val = $strings[int(@strings) - 1];
	
	return undef if (not (defined($value)));
	return undef if (not (defined($reading)));
	
	#remove whitespaces
	$value =~ s/^\s+|\s+$//g;
	$reading =~ s/^\s+|\s+$//g;

	$reading = lc ($reading) if ($reading =~ m/[sS][tT][aA][tT][eE]/);
	
	Log3 ($name, 5, "state $name: update $reading with value: $value");
	
	#write value and update reading
	readingsSingleUpdate($hash, $reading, $value, 1);

	return undef;
}

#Get the chance to qualify attributes
#############################
sub
KNX_Attr(@) {
	my ($cmd,$name,$aName,$aVal) = @_;
	
	return undef;
}

#Split reading for DBLOG
#############################
sub KNX_DbLog_split($) {
	my ($event) = @_;
	my ($reading, $value, $unit);

	my $tempStr = join (", ", @_);
	Log (5, "splitFn - enter, attributes: $tempStr");
	
	#detect reading - real reading or state?
	my $isReading = "false"; 
	$isReading = "true" if ($event =~ m/: /);
	
	#split input-string
	my @strings = split (" ", $event);
	
	my $startIndex = undef;
	$unit = "";
	
	return undef if (not defined ($strings[0]));

	#real reading?
	if ($isReading =~ m/true/)
	{
		#first one is always reading
		$reading = $strings[0];
		$reading =~ s/:?$//;
		$startIndex = 1;
	}
	#plain state
	else
	{
		#for reading state nothing is supplied
		$reading = "state";
		$startIndex = 0;	
	}
	
	return undef if (not defined ($strings[$startIndex]));

	#per default join all single pieces
	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	
	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+$/)
	{
		$value = $strings[$startIndex];
		#single numeric value? Assume second par is unit...
		if ((defined ($strings[$startIndex + 1])) && !($strings[$startIndex+1] =~ /^[+-]?\d*[.,]?\d+/)) 
		{
			$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
		}
	}

	#numeric value?
	#if ($strings[$startIndex] =~ /^[+-]?\d*[.,]?\d+/)
	#{
	#	$value = $strings[$startIndex];
	#	$unit = $strings[$startIndex + 1] if (defined ($strings[$startIndex + 1]));
	#}
	#string or raw
	#else
	#{
	#	$value = join(" ", @strings[$startIndex..(int(@strings) - 1)]);
	#}
		
	Log (5, "splitFn - READING: $reading, VALUE: $value, UNIT: $unit");
	
	return ($reading, $value, $unit);
}

#Handle incoming messages
#############################
sub
KNX_Parse($$) {
	my ($hash, $msg) = @_;
	
	#Msg format: 
	#C(w/r/p)<group><value> i.e. Bw00000101
	#we will also take reply telegrams into account, 
	#as they will be sent if the status is asked from bus 	
	#split message into parts

	#old syntax
	#$msg =~ m/^$id(.{4})(.{1})(.{4})(.*)$/;
	#new syntax for extended adressing
	$msg =~ m/^$id(.{5})(.{1})(.{5})(.*)$/;
	my $src = $1;
	my $cmd = $2;
	my $dest = $3;
	my $val = $4;
	
	my @foundMsgs;
	
	Log3 ($hash->{NAME}, 5, "enter parse: hash: $hash name: $hash->{NAME}, msg: $msg");
	
	#check if the code is within the read groups
	foreach my $deviceName (keys %{$modules{KNX}{defptr}})
	{
		#fetch device
		my $deviceHash = $modules{KNX}{defptr}{$deviceName};
			
		#skip, if name not defined
		next if (!defined($deviceHash));

		#loop through all defined group-numbers
		foreach my $gno (keys %{$deviceHash->{GCODE}})
		{
			#fetch groupcode
			my $groupc = $deviceHash->{GCODE}{$gno};
		
			#GAD in message is matching GAD in device
			if (defined ($groupc) and ($groupc eq $dest))
			{
				#get details
				my $name = $deviceHash->{NAME};
				my $groupAddr = $deviceHash->{GADDR}{$gno};
				my $model = $deviceHash->{MODEL}{$gno};

				Log3 ($name, 5, "parse device hash: $deviceHash name: $name, GADDR: $groupAddr, GCODE: $groupc, MODEL: $model");
				
				#handle write and reply messages
				if ($cmd =~ /[w|p]/)
				{
					#decode message
					my $transval = KNX_decodeByDpt ($deviceHash, $val, $gno);
					#message invalid
					if (not defined($transval) or ($transval eq ""))
					{
						Log3 ($name, 2, "parse device hash: $deviceHash name: $name, message could not be decoded - see log for details");
						next;
					}

					Log3 ($name, 5, "received hash: $deviceHash name: $name, STATE: $transval, GNO: $gno, SENDER: $src");				

					#build readingsName
					my $rdName = $deviceHash->{READINGSNAME}{$gno};					
					if (defined ($rdName) and !($rdName eq ""))
					{
						Log3 ($name, 5, "parse device hash: $deviceHash name: $name, replaced \"getG\" with custom readingName \"$rdName\"");
						$rdName = $rdName . "-get";
					}
					else
					{
						$rdName = "getG" . $gno;
					}

					#append post-string, if supplied
					my $suffix = AttrVal($name, "format",undef);
					$transval = $transval . " " . $suffix if (defined($suffix));					
					#execute regex, if defined				
					my $regAttr = AttrVal($name, "stateRegex", undef);
					my $state = KNX_replaceByRegex ($regAttr, $rdName . ":", $transval);
					Log3 ($name, 5, "parse device hash: $deviceHash name: $name - replaced $rdName:$transval to $state") if (not ($transval eq $state));					

					if (defined($state))
					{
						readingsBeginUpdate($deviceHash);
						readingsBulkUpdate($deviceHash, $rdName, $transval);
						readingsBulkUpdate($deviceHash, "last-sender", KNX_hexToName($src));
						
						#execute state-command if defined
						#must be placed after first readings, because it may have a reference
						my $cmdAttr = AttrVal($name, "stateCmd", undef);
						if (defined ($cmdAttr) and !($cmdAttr eq ""))
						{
							$state = eval $cmdAttr;
							Log3 ($name, 5, "parse device hash: $deviceHash name: $name - state replaced via command - result: state:$state");					
						}					
						
						readingsBulkUpdate($deviceHash, "state", $state);						
						readingsEndUpdate($deviceHash, 1);
					}								
				}
				#handle read messages, if Attribute is set	
				elsif (($cmd =~ /[r]/) && (AttrVal($name, "answerReading",0) =~ m/1/))
				{
					Log3 ($name, 5, "received hash: $deviceHash name: $name, GET");				
					my $transval = KNX_encodeByDpt($deviceHash, $deviceHash->{STATE}, $gno);
					
					if (defined($transval))
					{
						Log3 ($name, 5, "received hash: $deviceHash name: $name, GET: $transval, GNO: $gno");				
						IOWrite ($deviceHash, "B", "p" . $groupc . $transval);
					}
				}
								
				#skip, if this is ignored
				next if (IsIgnored($name));
				#save to list
				push(@foundMsgs, $name);
			}
		}
	}	
	
	Log3 ($hash->{NAME}, 5, "exit parse");
	
	#return values
	if (int(@foundMsgs))
	{
		return @foundMsgs;
	} else
	{
		my $gad = KNX_hexToName($dest);
		#remove slashes
		#$name =~ s/\///g;
		#my $name = "KNX_" . $gad;
		my ($line, $area, $device) = split ("/", $gad);
		my $name = sprintf("KNX_%.2d%.2d%.3d", $line, $area, $device);
		
		my $ret = "KNX Unknown device $dest ($gad), Value $val, please define it";
		Log3 ($name, 3, "KNX Unknown device $dest ($gad), Value $val, please define it");
		
		#needed for autocreate
		return "UNDEFINED $name KNX $gad:$modelErr";	
	}
}

#Function is called at every notify
#############################
sub 
KNX_Notify($$)
{
	my ($ownHash, $callHash) = @_;
	#own name / hash
	my $ownName = $ownHash->{NAME};
	#Device that created the events
	my $callName = $callHash->{NAME}; 

	return undef;
}

#Private function to convert GAD from hex to readable version
#############################
sub
KNX_hexToName ($)
{
	my $v = shift;
	
	#old syntax
	#my $p1 = hex(substr($v,0,1));
	#my $p2 = hex(substr($v,1,1));
	#my $p3 = hex(substr($v,2,2));

	#new syntax for extended adressing
	my $p1 = hex(substr($v,0,2));
	my $p2 = hex(substr($v,2,1));
	my $p3 = hex(substr($v,3,2));
  
	my $r = sprintf("%d/%d/%d", $p1,$p2,$p3);
	
	return $r;
}

#Private function to convert GAD from readable version to hex
#############################
sub
KNX_nameToHex ($)
{
	my $v = shift;
	my $r = $v;

	if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/) 
	{
		#old syntax
		#$r = sprintf("%01x%01x%02x",$1,$2,$3);
		#new syntax for extended adressing
		$r = sprintf("%02x%01x%02x",$1,$2,$3);
	}
	#elsif($v =~ /^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,3})$/) 
	#{
	#	$r = sprintf("%01x%01x%02x",$1,$2,$3);
	#}  
    
	return $r;
}

#Private function to clean input string according DPT
#############################
sub
KNX_checkAndClean ($$$)
{
	my ($hash, $value, $gno) = @_;
	my $name = $hash->{NAME};
	my $orgValue = $value;
	
	Log3 ($name, 5, "check value: $value, gno: $gno");
	
	#get model
	my $model = $hash->{MODEL}{$gno};
	
	#return unchecked, if this is a autocreate-device
	return $value if ($model eq $modelErr);
	
	#get pattern
	my $pattern = $dpttypes{$model}{PATTERN};

	#trim whitespaces at the end
	$value =~ s/^\s+|\s+$//g;

	#match against model pattern
	my @tmp = ($value =~ m/$pattern/g);
	#loop through results
	my $found = 0;
	foreach my $str (@tmp) 
	{
		#assign first match and exit loop
		if (defined($str))
		{
			$found = 1;
			$value = $str;
			last;
		}
	}
	
	return undef if ($found == 0);

	#get min
	my $min = $dpttypes{"$model"}{MIN};
	#if min is numeric, cast to min
	$value = $min if (defined ($min) and ($min =~ /^[+-]?\d*[.,]?\d+/) and ($value < $min));

	#get max
	my $max = $dpttypes{"$model"}{MAX};
	#if max is numeric, cast to max
	$value = $max if (defined ($max) and ($max =~ /^[+-]?\d*[.,]?\d+/) and ($value > $max));

	Log3 ($name, 3, "check value: input-value $orgValue was casted to $value") if (not($orgValue eq $value));		
	Log3 ($name, 5, "check value: $value, gno: $gno, model: $model, pattern: $pattern");
	
	return $value;
}


#Private function to encode KNX-Message according DPT
#############################
sub
KNX_encodeByDpt ($$$) {
	my ($hash, $value, $gno) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "encode value: $value, gno: $gno");
	
	#get model
	my $model = $hash->{MODEL}{$gno};
	my $code = $dpttypes{$model}{CODE};
	
	#return unchecked, if this is a autocreate-device
	return $value if ($model eq $modelErr);

	#this one stores the translated value (readble)
	my $numval = undef;
	#this one stores the translated hex-value
	my $hexval = undef;
	
	Log3 ($name, 5, "encode model: $model, code: $code, value: $value");
		
	#get correction details
	my $factor = $dpttypes{$model}{FACTOR};
	my $offset = $dpttypes{$model}{OFFSET};
	
	#correct value
	$value /= $factor if (defined ($factor));
	$value -= $offset if (defined ($offset));
	
	Log3 ($name, 5, "encode normalized value: $value");
	
	#Binary value
	if ($code eq "dpt1")
	{
		$numval = "00" if ($value eq 0);
		$numval = "01" if ($value eq 1);
		$numval = "00" if ($value eq $dpttypes{$model}{MIN});
		$numval = "01" if ($value eq $dpttypes{$model}{MAX});
		
		$hexval = $numval;
	}
	#Step value (two-bit) 
	elsif ($code eq "dpt2")
	{
		$numval = "00" if ($value =~ m/[oO][fF][fF]/);
		$numval = "01" if ($value =~ m/[oO][nN]/);
		$numval = "02" if ($value =~ m/[fF][oO][rR][cC][eE][oO][fF][fF]/);		
		$numval = "03" if ($value =~ m/[fF][oO][rR][cC][eE][oO][nN]/);
		
		$hexval = $numval;
	}	
	#Step value (four-bit) 
	elsif ($code eq "dpt3")
	{
		$numval = 0;
		
		#get dim-direction
		my $sign = 0;
		$sign = 1 if ($value >= 0);

		#trim sign
		$value =~ s/^-//g;

		#get dim-value
		$numval = 7 if ($value >= 1);
		$numval = 6 if ($value >= 3);
		$numval = 5 if ($value >= 6);
		$numval = 4 if ($value >= 12);
		$numval = 3 if ($value >= 25);
		$numval = 2 if ($value >= 50);
		$numval = 1 if ($value >= 75);
		
		#assign dim direction
		$numval += 8 if ($sign == 1);
		
		#get hex representation
		$hexval = sprintf("%.2x",$numval);
	}
	#1-Octet unsigned value
	elsif ($code eq "dpt5")
	{
		$numval = $value;
		$hexval = sprintf("00%.2x",($numval));
	}
	#1-Octet signed value
	elsif ($code eq "dpt6")
	{
		#build 2-complement
		$numval = $value;
		$numval += 0x100 if ($numval < 0);
		$numval = 0x00 if ($numval < 0x00);
		$numval = 0xFF if ($numval > 0xFF);
		
		#get hex representation
		$hexval = sprintf("00%.2x",$numval);
	}
	#2-Octet unsigned Value
	elsif ($code eq "dpt7")
	{
		$numval = $value;
		$hexval = sprintf("00%.4x",($numval));	
	}
	#2-Octet signed Value 
	elsif ($code eq "dpt8")
	{
		#build 2-complement
		$numval = $value;
		$numval += 0x10000 if ($numval < 0);
		$numval = 0x00 if ($numval < 0x00);
		$numval = 0xFFFF if ($numval > 0xFFFF);
		
		#get hex representation
		$hexval = sprintf("00%.4x",$numval);	
	}
	#2-Octet Float value
	elsif ($code eq "dpt9")
	{
		my $sign = ($value <0 ? 0x8000 : 0);
		my $exp  = 0;
		my $mant = 0;

		$mant = int($value * 100.0);
		while (abs($mant) > 0x7FF) 
		{
			$mant /= 2;
			$exp++;
		}
		$numval = $sign | ($exp << 11) | ($mant & 0x07ff);
		
		#get hex representation
		$hexval = sprintf("00%.4x",$numval);
	}
	#Time of Day
	elsif ($code eq "dpt10")
	{
		if (lc($value) eq "now")
		{
			#get actual time
			my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			my $hoffset;
			
			#add offsets
			$year+=1900;
			$mon++;	
			# calculate offset for weekday
			$wday = 7 if ($wday eq "0");
			$hoffset = 32*$wday;
			$hours += $hoffset;
			
			$value = "$hours:$mins:$secs";
			$numval = $secs + ($mins<<8) + ($hours<<16);
		} else
		{
			my ($hh, $mm, $ss) = split (":", $value);
			$numval = $ss + ($mm<<8) + (($hh)<<16);
		}
			
		#get hex representation
		$hexval = sprintf("00%.6x",$numval);
	}
	#Date  
	elsif ($code eq "dpt11")
	{
		if (lc($value) eq "now")
		{	
			#get actual time
			my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			my $hoffset;
			
			#add offsets
			$year+=1900;
			$mon++;	
			# calculate offset for weekday
			$wday = 7 if ($wday eq "0");
			
			$value = "$mday.$mon.$year";			
			$numval = ($year - 2000) + ($mon<<8) + ($mday<<16);		
		} else
		{
			my ($dd, $mm, $yyyy) = split (/\./, $value);
			
			if ($yyyy >= 2000)
			{
				$yyyy -= 2000;
			} else
			{
				$yyyy -= 1900;
			}
			
			$numval = ($yyyy) + ($mm<<8) + ($dd<<16);
		}
			
		#get hex representation
		$hexval = sprintf("00%.6x",$numval);
	}
	#4-Octet unsigned value (handled as dpt7)
	elsif ($code eq "dpt12")
	{
		$numval = $value;
		$hexval = sprintf("00%.8x",($numval));	
	}	
	#4-Octet Signed Value
	elsif ($code eq "dpt13")
	{
		#build 2-complement
		$numval = $value;
		$numval += 4294967296 if ($numval < 0);
		$numval = 0x00 if ($numval < 0x00);
		$numval = 0xFFFFFFFF if ($numval > 0xFFFFFFFF);
		
		#get hex representation
		$hexval = sprintf("00%.8x",$numval);		
	}  
	#4-Octet single precision float
	elsif ($code eq "dpt14")
	{
		$numval = unpack("L",  pack("f", $value));
		
		#get hex representation
		$hexval = sprintf("00%.8x",$numval);	
	}	
	#14-Octet String
	elsif ($code eq "dpt16")
	{
		#convert to latin-1
		$value = encode("iso-8859-1", decode("utf8", $value));
		
		#convert to hex-string
		my $dat = unpack "H*", $value;
		#format for 14-byte-length
		$dat = sprintf("%-028s",$dat);
		#append leading zeros
		$dat = "00" . $dat;
		
		$numval = $value;
		$hexval = $dat;
	} 
	#DateTime
	elsif ($code eq "dpt19")
	{
		if (lc($value) eq "now")
		{
			#get actual time
			my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			my $hoffset;
			
			#add offsets
			$mon++;	
			# calculate offset for weekday
			$wday = 7 if ($wday eq "0");
			
			$hexval = 0;
			$hexval = sprintf ("00%.8x", (($secs<<16) + ($mins<<24) + ($hours<<32) + ($wday<<37) + ($mday<<40) + ($mon<<48) + ($year<<56)));
			
		} else
		{
			my ($date, $time) = split ('_', $value);
			my ($dd, $mm, $yyyy) = split (/\./, $date);
			my ($hh, $mi, $ss) = split (':', $time);

			#add offsets
			$yyyy -= 1900;  # year is based on 1900
			my $wday = 0;
			
			$hexval = 0;
			$hexval = sprintf ("00%.8x", (($ss<<16) + ($mi<<24) + ($hh<<32) + ($wday<<37) + ($dd<<40) + ($mm<<48) + ($yyyy<<56)));
		}
		$numval = 0;
	}	
	#RGB-Code
	elsif ($code eq "dpt232")
	{
		$hexval = "00" . $value;
		$numval = $value;
	}
	else
	{
		Log3 ($name, 2, "encode model: $model, no vaild model defined");
		return undef;	
	}
	
	Log3 ($name, 5, "encode model: $model, code: $code, value: $value, numval: $numval, hexval: $hexval");
	return $hexval;
}

#Private function to replace state-values
#############################
sub
KNX_replaceByRegex ($$$) {
	my ($regAttr, $prefix, $input) = @_;
	my $retVal = $input;

	#execute regex, if defined
	if (defined($regAttr))
	{
		#get array of given attributes
		my @reg = split(" /", $regAttr);
		
		my $tempVal = $prefix . $input;
		
		#loop over all regex
		foreach my $regex (@reg)
		{
			#trim leading and trailing slashes
			$regex =~ s/^\/|\/$//g;
			#get pairs
			my @regPair = split("\/", $regex);
						
			#skip if not at least 2 values supplied
			#next if (int(@regPair < 2));
			next if (not defined($regPair[0]));
			
			if (not defined ($regPair[1]))
			{
				#cut value
				$tempVal =~ s/$regPair[0]//g;
			}
			else
			{
				#replace value
				$tempVal =~ s/$regPair[0]/$regPair[1]/g;
			}
			
			#restore value
			$retVal = $tempVal;
		}
	}
	
	return $retVal;
}

#Private function to decode KNX-Message according DPT
#############################
sub
KNX_decodeByDpt ($$$) {
	my ($hash, $value, $gno) = @_;
	my $name = $hash->{NAME};
	
	Log3 ($name, 5, "decode value: $value, gno: $gno");
	
	#get model
	my $model = $hash->{MODEL}{$gno};
	my $code = $dpttypes{$model}{CODE};
	
	#return unchecked, if this is a autocreate-device
	return $value if ($model eq $modelErr);

	#this one stores the translated value (readble)
	my $numval = undef;
	#this one contains the return-value
	my $state = undef;
	
	Log3 ($name, 5, "decode model: $model, code: $code, value: $value");
		
	#get correction details
	my $factor = $dpttypes{$model}{FACTOR};
	my $offset = $dpttypes{$model}{OFFSET};
	
	#Binary value
	if ($code eq "dpt1")
	{
		my $min = $dpttypes{"$model"}{MIN};
		my $max = $dpttypes{"$model"}{MAX};
		
		$numval = $min if (lc($value) eq "00");
		$numval = $max if (lc($value) eq "01");
		$state = $numval;
	}
	#Step value (two-bit) 
	elsif ($code eq "dpt2")
	{
		#get numeric value
		$numval = hex ($value);

		$state = "off" if ($numval == 0);
		$state = "on" if ($numval == 1);
		$state = "forceOff" if ($numval == 2);
		$state = "forceOn" if ($numval == 3);
	}	
	#Step value (four-bit) 
	elsif ($code eq "dpt3")
	{
		#get numeric value
		$numval = hex ($value);

		$state = 1 if ($numval & 7);
		$state = 3 if ($numval & 6);
		$state = 6 if ($numval & 5);
		$state = 12 if ($numval & 4);
		$state = 25 if ($numval & 3);
		$state = 50 if ($numval & 2);
		$state = 100 if ($numval & 1);
				
		#get dim-direction
		$state = 0 - $state if (not ($numval & 8));
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);
	}
	#1-Octet unsigned value
	elsif ($code eq "dpt5")
	{
		$numval = hex ($value);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);
	}
	#1-Octet signed value
	elsif ($code eq "dpt6")
	{
		$numval = hex ($value);
		$numval -= 0x100 if ($numval >= 0x80);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}
	#2-Octet unsigned Value
	elsif ($code eq "dpt7")
	{
		$numval = hex ($value);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}
	#2-Octet signed Value 
	elsif ($code eq "dpt8")
	{
		$numval = hex ($value);
		$numval -= 0x10000 if ($numval >= 0x8000);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));
		
		$state = sprintf ("%.0f", $state);		
	}
	#2-Octet Float value
	elsif ($code eq "dpt9")
	{
		$numval = hex($value);
		my $sign = 1;
		$sign = -1 if(($numval & 0x8000) > 0);
		my $exp = ($numval & 0x7800) >> 11;
		my $mant = ($numval & 0x07FF);
		$mant = -(~($mant-1) & 0x07FF) if($sign == -1);
		$numval = (1 << $exp) * 0.01 * $mant;

		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));
		
		$state = sprintf ("%.2f","$numval");
	}
	#Time of Day
	elsif ($code eq "dpt10")
	{
		$numval = hex($value);
		my $hours = ($numval & 0x1F0000)>>16;
		my $mins  = ($numval & 0x3F00)>>8;
		my $secs  = ($numval & 0x3F);

		$state = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
	}
	#Date  
	elsif ($code eq "dpt11")
	{
		$numval = hex($value);
		my $day = ($numval & 0x1F0000) >> 16;
		my $month  = ($numval & 0x0F00) >> 8;
		my $year  = ($numval & 0x7F);
		#translate year (21st cent if <90 / else 20th century)
		$year += 1900 if($year >= 90);
		$year += 2000 if($year < 90);

		$state = sprintf("%02d.%02d.%04d",$day,$month,$year);
	}
	#4-Octet unsigned value (handled as dpt7)
	elsif ($code eq "dpt12")
	{
		$numval = hex ($value);
		$state = $numval;	
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}	
	#4-Octet Signed Value
	elsif ($code eq "dpt13")
	{
		$numval = hex ($value);
		$numval -= 4294967296 if ($numval >= 0x80000000);
		$state = $numval;
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));

		$state = sprintf ("%.0f", $state);		
	}  
	#4-Octet single precision float
	elsif ($code eq "dpt14")
	{
		$numval = unpack "f", pack "L", hex ($value);
		
		#correct value
		$state -= $offset if (defined ($offset));
		$state *= $factor if (defined ($factor));
		
		$state = sprintf ("%.3f","$numval");
	}	
	#14-Octet String
	elsif ($code eq "dpt16")
	{
		$numval = 0;
		$state  = "";
		
		for (my $i = 0; $i < 14; $i++) 
		{
			my $c = hex(substr($value, $i * 2, 2));
			
			#exit at string terminator, otherwise append current char
			if (($i != 0) and ($c eq 0))
			{
				$i = 14;
			} 
			else 
			{
				$state .=  sprintf("%c", $c);
			}
		}

		#convert to latin-1
		$state = encode ("utf8", $state) if ($model =~ m/16.001/);		
	}
	#DateTime
	elsif ($code eq "dpt19")
	{
		$numval = $value;
		my $time = hex (substr ($value, 6, 6));
		my $date = hex (substr ($value, 0, 6));
		my $secs  = ($time & 0x3F) >> 0;
		my $mins  = ($time & 0x3F00) >> 8;
		my $hours = ($time & 0x1F0000) >> 16;
		my $day   = ($date & 0x1F) >> 0;
		my $month = ($date & 0x0F00) >> 8;
		my $year  = ($date & 0xFFFF0000) >> 16;		
		
		$year += 1900;
		$state = sprintf("%02d.%02d.%04d_%02d:%02d:%02d", $day, $month, $year, $hours, $mins, $secs);	
	}
	#RGB-Code
	elsif ($code eq "dpt232")
	{
		$numval = hex ($value);
		$state = $numval;

		$state = sprintf ("%.6x", $state);
	} 
	else
	{
		Log3 ($name, 2, "decode model: $model, no valid model defined");
		return undef;	
	}
	
	#append unit, if supplied
	my $unit = $dpttypes{$model}{UNIT};	
	$state = $state . " " . $unit if (defined ($unit) and not($unit eq ""));
		
	Log3 ($name, 5, "decode model: $model, code: $code, value: $value, numval: $numval, state: $state");
	return $state;
}

#Private function to evaluate command-lists
#############################
sub KNX_getCmdList ($$$)
{
	my ($hash, $cmd, %cmdArray) = @_;
	
	my $name = $hash->{NAME};

	#return, if cmd is valid
	return undef if (defined ($cmd) and defined ($cmdArray{$cmd}));
	
	#response for gui or the user, if command is invalid
	my $retVal;
	foreach my $mySet (keys %cmdArray)
	{
		#append set-command
		$retVal = $retVal . " " if (defined ($retVal));
		$retVal = $retVal . $mySet;
		#get options
		my $myOpt = $cmdArray{$mySet};
		#append option, if valid
		$retVal = $retVal . ":" . $myOpt if (defined ($myOpt) and (length ($myOpt) > 0));
		$myOpt = "" if (!defined($myOpt));
		Log3 ($name, 5, "parse cmd-table - Set:$mySet, Option:$myOpt, RetVal:$retVal");
	}
	
	#if (!defined ($retVal))
	#{
	#	$retVal = "error while parsing set-table" ;
	#}
	#else
	#{
	#	$retVal = "Unknown argument $cmd, choose one of " . $retVal;	
	#}
	
		
	return $retVal;
}

1;

=pod
=begin html

<a name="KNX"></a> 
<h3>KNX</h3>
<ul>
<p>KNX is a standard for building automation / home automation.
  It is mainly based on a twisted pair wiring, but also other mediums (ip, wireless) are specified.</p>
  For getting started, please refer to this document: <a href="http://www.knx.org/media/docs/Flyers/KNX-Basics/KNX-Basics_de.pdf">KNX-Basics</a>

<p>While the module <a href="#TUL">TUL</a> represents the connection to the KNX network, the KNX modules represent individual KNX devices. This module provides a basic set of operations (on, off, on-until, on-for-timer)
  to switch on/off KNX devices. For numeric DPT you can use value (set &lt;devname&gt; value &lt;177.45&gt;). For string-DPT you can use string (set &lt;devname&gt; string &lt;Hello World&gt;). For other, non-defined 
  dpt you can send raw hex values to the network (set &lt;devname&gt; raw &lt;hexval&gt;).<br> 
  Sophisticated setups can be achieved by combining a number of KNX module instances. Therefore you can define a number of different GAD/DPT combinations per each device.</p>

<p>KNX defines a series of Datapoint Type as standard data types used to allow general interpretation of values of devices manufactured by different companies.
  These datatypes are used to interpret the status of a device, so the state in FHEM will then show the correct value. For each received telegram there will be a reading with state, getG&lt;group&gt; and the sender
  address. For every set, there will be a reading with state and setG&lt;group&gt;.</p>

  <p><a name="KNXdefine"></a> <b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; KNX &lt;group&gt;:&lt;DPT&gt;:&lt[;readingName]&gt; [&lt;group&gt;:&lt;DPT&gt; ..] [IODev]</code>
    
	<p>A KNX device need a concrete DPT. Please refer to <a href="#KNXdpt">Available DPT</a>. Otherwise the system cannot en- or decode the messages. Furthermore you can supply a IO-Device directly at startup. This can be done later on via attribute as well.</p>
	
    <p>Define an KNX device, connected via a <a href="#TUL">TUL</a>. The &lt;group&gt; parameters are either a group name notation (0-15/0-15/0-255) or the hex representation of the value (0-f0-f0-ff).
    All of the defined groups can be used for bus-communication. Without further attributes, all incoming messages are translated into state. Per default, the first group is used for sending. If you want to send
	via a different group, you have to index it (set &lt;devname&gt; value &lt;17.0&gt; &lt;g2&gt;).<br>
	If you use the readingName, readings are based on this name (e.g. hugo-set, hugo-get for name hugo).</p>

    <p>The module <a href="#autocreate">autocreate</a> is creating a new definition for any unknown sender. The device itself will be NOT fully available, until you added a DPT to the definition. The name will be
	KNX_nnmmooo where nn is the line adress, mm the area and ooo the device.</p>

    <p>Example:</p>
      <pre>
      define lamp1 KNX 0/10/12:dpt1
      define lamp1 KNX 0/10/12:dpt1:meinName 0/0/5:dpt1.001
      define lamp1 KNX 0A0C:dpt1.003 myTul
      </pre>

	One hint regarding dpt1 (binary): all the sub-types have to be used with keyword value. Received telegrams are already encoded to their representation. This mechanism does not work for send-telegrams.
	Here on/off has to be supplied.<br>
	Having the on/off button (for send values) without keyword value is an absolutely special use-case and only valid for dpt1 and its sub-types.<br>
	
    <p>Example:</p>
      <pre>
      define rollo KNX 0/10/12:dpt1.008
	  set rollo value off
	  set rollo value on
      </pre>
	
  </ul>
  
  <p><a name="KNXset"></a> <b>Set</b></p>
  <ul>
    <code>set &lt;name&gt; &lt;on, off&gt;</code> [g&lt;groupnr&gt;]
	<code>set &lt;name&gt; &lt;on-for-timer, on-until&gt; &lt;time&gt; [g&lt;groupnr&gt;]</code>
	<code>set &lt;name&gt; &lt;value&gt; [g&lt;groupnr&gt;]</code>
	<code>set &lt;name&gt; &lt;string&gt; [g&lt;groupnr&gt;]</code>
	<code>set &lt;name&gt; &lt;raw&gt; [g&lt;groupnr&gt;]</code>
	
    <p>Example:</p>
    <pre>
      set lamp1 on
      set lamp1 off
      set lamp1 on-for-timer 10
      set lamp1 on-until 13:15:00
      set foobar raw 234578
      set thermo value 23.44
	  set message value Hallo Welt
    </pre>

	<p>When as last argument a g&lt;groupnr&gt; is present, the command will be sent
	to the KNX group indexed by the groupnr (starting by 1, in the order as given in define).</p>
	<pre>
      define lamp1 KNX 0/10/01:dpt1 0/10/02:dpt1
      set lamp1 on g2 (will send "on" to 0/10/02)
	</pre>

	<p>A dimmer can be used with a slider as shown in following example:</p>
	<pre>
      define dim1 KNX 0/0/5:dpt5.001
      attr dim1 slider 0,1,100
      attr dim1 webCmd value
	</pre>
	
	<p>The current date and time can be sent to the bus by the following settings:</p>
	<pre>
      define timedev KNX 0/0/7:dpt10
      attr timedev webCmd value now
      
      define datedev KNX 0/0/8:dpt11
      attr datedev webCmd value now
      
      # send every midnight the new date
      define dateset at *00:00:00 set datedev value now
      
      # send every hour the current time
      define timeset at +*01:00:00 set timedev value now
	</pre>	
  </ul>
 
  <p><a name="KNXget"></a> <b>Get</b></p>
  <ul>  
  <p>If you execute get for a KNX-Element the status will be requested a state from the device. The device has to be able to respond to a read - this is not given for all devices.<br>
	The answer from the bus-device is not shown in the toolbox, but is treated like a regular telegram.</p>
  </ul>
  
  <p><a name="KNXattr"></a> <b>Attributes</b></p>
  <ul><br>
	Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	<a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="KNXformat"></a> <b>format</b></p>
  <ul> 
	The content of this attribute is added to every received value, before this is copied to state.
      <p>Example:</p>
      <pre>
      define myTemperature KNX 0/1/1:dpt5
      attr myTemperature format &degC;
      </pre>
  </ul> 

  <p><a name="KNXstateRegex"></a> <b>stateRegex</b></p>
  <ul> 
    You can pass n pairs of regex-pattern and string to replace, seperated by a slash. Internally the "new" state is always in the format getG&lt;group&gt;:&lt;state-value&gt;. The substitution is done every time, 
	a new object is received. You can use this function for converting, adding units, having more fun with icons, ... 
	This function has only an impact on the content of state - no other functions are disturbed. It is executed directly after replacing the reading-names and setting the formats, but before stateCmd
      <p>Example:</p>
      <pre>
      define myLamp KNX 0/1/1:dpt1 0/1/2:dpt1 0/1/2:dpt1
      attr myLamp stateRegex /getG1:/steuern:/ /getG2:/status:/ /getG3:/sperre:/ /setG[13]:/steuern:/ /setG[3]://
	  attr myLamp devStateIcon status.on:general_an status.off:general_aus sperre.on:lock steuern.*:hourglass
      </pre>    
  </ul>	

  <p><a name="KNXstateCmd"></a> <b>stateCmd</b></p>
  <ul>
	You can supply a perl-command for modifying state. This command is executed directly before updating the reading - so after renaming, format and regex. 
	Please supply a valid perl command like using the attribute stateFormat.
	Unlike stateFormat the stateCmd modifies also the content of the reading, not only the hash-conten for visualization.
      <p>Example:</p>
      <pre>
      define myLamp KNX 0/1/1:dpt1 0/1/2:dpt1 0/1/2:dpt1
      attr myLamp stateCmd {$state = sprintf("%s", ReadingsVal($name,"getG2","undef"))}
      </pre>    
  </ul>

  <p><a name="KNXanswerReading"></a> <b>answerReading</b></p>
  <ul> 
    If enabled, FHEM answers on read requests. The content of state is send to the bus as answer.
    <p>If set to 1, read-requests are answered</p>
  </ul>

  <p><a name="KNXlistenonly"></a> <b>listenonly</b></p>
  <ul> 
	If set to 1, the device may not send any messages. As well answering requests although get is prohibited.
  </ul>	 

  <p><a name="KNXreadonly"></a> <b>readonly</b></p>
  <ul> 
	If set to 1, the device may not send any messages. Answering requests are prohibited.Get is allowed.
  </ul>	 

  <p><a name="KNXslider"></a> <b>slider</b></p>
  <ul> 
	slider &lt;min&gt;,&lt;step&gt;,&lt;max&gt;<br>
	With this attribute you can add a slider to any device. 
      <p>Example:</p>
      <pre>
      define myDimmer KNX 0/1/1:dpt5
      attr myDimmer slider 0,1,100
	  attr myDimmer webCmd value
      </pre>
  </ul>  

  <p><a name="KNXdpt"></a> <b>DPT - datapoint-types</b></p>
  <ul>  
  <p>The following dpt are implemented and have to be assigned within the device definition.</p>					
	dpt1 on, off<br>
	dpt1.001 on, off<br>
	dpt1.002 true, false<br>
	dpt1.003 enable, disable<br>	
	dpt1.004 no ramp, ramp<br>
	dpt1.005 no alarm, alarm<br>
	dpt1.006 low, high<br>
	dpt1.007 decrease, increase<br>
	dpt1.008 up, down<br>
	dpt1.009 open, closed<br>	
	dpt1.010 start, stop<br>	
	dpt1.011 inactive, active<br>
	dpt1.012 not inverted, inverted<br>
	dpt1.013 start/stop, ciclically<br>
	dpt1.014 fixed, calculated<br>
	dpt1.015 no action, reset<br>
	dpt1.016 no action, acknowledge<br>
	dpt1.017 trigger, trigger<br>
	dpt1.018 not occupied, occupied<br>
	dpt1.019 closed, open<br>
	dpt1.020 logical or, logical and<br>
	dpt1.021 scene A, scene B<br>
	dpt1.022 move up/down, move and step mode<br>
	dpt2 value on, value off, value forceOn, value forceOff<br>
	dpt3 -100..+100<br>
	dpt5 0..255<br>
	dpt5.001 0..100	%<br>
	dpt5.003 0..360	&deg;<br>
	dpt5.004 0..255	%<br>
	dpt6 -127..+127<br>
	dpt6.001 0..100	%<br>
	dpt7 0..65535<br>
	dpt7.001 0..65535 s<br>
	dpt7.005 0..65535 s<br>
	dpt7.005 0..65535 m<br>	
	dpt7.012 0..65535 mA<br>	
	dpt7.013 0..65535 lux<br>
	dpt8 -32768..32768<br>
	dpt8.005 -32768..32768 s<br>
	dpt8.010 -32768..32768 %<br>
	dpt8.011 -32768..32768 &deg;<br>
	dpt9 -670760.0..+670760.0<br>
	dpt9.001 -670760.0..+670760.0 &deg;<br>
	dpt9.004 -670760.0..+670760.0 lux<br>
	dpt9.005 -670760.0..+670760.0 m/s<br>	
	dpt9.006 -670760.0..+670760.0 Pa<br>	
	dpt9.007 -670760.0..+670760.0 %<br>
	dpt9.008 -670760.0..+670760.0 ppm<br>	
	dpt9.009 -670760.0..+670760.0 m³/h<br>
	dpt9.010 -670760.0..+670760.0 s<br>
	dpt9.021 -670760.0..+670760.0 mA<br>	
	dpt9.024 -670760.0..+670760.0 kW<br>
	dpt9.025 -670760.0..+670760.0 l/h<br>
	dpt9.026 -670760.0..+670760.0 l/h<br>
	dpt9.028 -670760.0..+670760.0 km/h<br>
	dpt10 01:00:00<br>
	dpt11 01.01.2000<br>
	dpt12 0..+Inf<br>
	dpt13 -Inf..+Inf<br>	
	dpt13.010 -Inf..+Inf Wh<br>
	dpt13.013 -Inf..+Inf kWh<br>
	dpt14 -Inf.0..+Inf.0<br>
	dpt14.019 -Inf.0..+Inf.0 A<br>
	dpt14.027 -Inf.0..+Inf.0 V<br>
	dpt14.056 -Inf.0..+Inf.0 W<br>
	dpt14.068 -Inf.0..+Inf.0 &degC;<br>
	dpt14.076 -Inf.0..+Inf.0 m&sup3;<br>
	dpt16 String;<br>
	dpt16.000 ASCII-String;<br>
	dpt16.001 ISO-8859-1-String (Latin1);<br>
	dpt232 RGB-Value RRGGBB<br>
  </ul>		
</ul>
=end html
=device
=item summary Communicates to KNX via module TUL
=item summary_DE Kommuniziert mit dem KNX über das Modul TUL
=begin html_DE

<a name="KNX"></a> 
<h3>KNX</h3>
<ul>
<p>KNX ist ein Standard zur Haus- und Geb&auml;udeautomatisierung.
  Der Standard begr&uuml;ndet sich haupts&auml;chlich auf twisted pair, findet aber auch zunehmende Verbreitung auf andere Medien (Funk, Ethernet, ...)</p>
  F&uuml;r Anf&auml;nger sei folgende Lekt&uuml;re empfohlen: <a href="http://www.knx.org/media/docs/Flyers/KNX-Basics/KNX-Basics_de.pdf">KNX-Basics</a>

<p>Das Modul <a href="#TUL">TUL</a> stellt die Verbindung zum Bus her, Das KNX-Modul stellt die Verbindung zu den einzelnen KNX-/EIB-Ger&auml;ten her. Das Modul stellt Befehle (on, off, on-until, on-for-timer)
  zum ein- und Ausschalten von Ger&auml;ten zur Verf&uuml;gung. F&uuml;r numerische DPT nutzt bitte value (set &lt;devname&gt; value &lt;177.45&gt;). F&uuml;r string-DPT nutzt bitte string 
  (set &lt;devname&gt; string &lt;Hello World&gt;). F&uuml;r andere, undefinierte DPT k&ouml;nnt Ihr raw hex Werte ans Netzwerk senden (set &lt;devname&gt; raw &lt;hexval&gt;).<br> 
  Komplexe Konfigurationen k&ouml;nnen aufgebaut werden, indem mehrere Modulinstanzen in einem Ger&auml;t definiert werden. Daf&uuml;r werden mehrere Kombinationen aus GAD und DPT in einem Ger&auml;t definiert werden.</p>

<p>Der KNX-Standard stellt eine Reihe vordefinierter Datentypen zur Verf&uuml;gung. Dies sichert die Hersteller&uuml;bergreifende Kompatibilit&auml;t.
  Basierend auf diesen DPT wird der Status eines Ger&auml;tes interpretiert und in FHEM angezeigt. F&uuml;r jedes empfangene Telegramm wird ein reading mit state, getG&lt;group&gt; und der Absenderadresse angelegt.
  F&uuml;r jedes ser-command wird ein Reading mit state und setG&lt;group&gt; angelegt.</p>

  <p><a name="KNXdefine"></a> <b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; KNX &lt;group&gt;:&lt;DPT&gt;:&lt[;readingName]&gt; [&lt;group&gt;:&lt;DPT&gt; ..] [IODev]</code>
    
	<p>Ein KNX-device ben&ouml;tigt einen konkreten DPT. Bitte schaut die verf&uuml;gbaren DPT unter <a href="#KNXdpt">Available DPT</a> nach. Wird kein korrekter DPT angegeben, kann das system die Nachrichten nicht korrekt de- / codieren. 
	Weiterhin kann bei der Ger&auml;tedefinition eine IO-Schnittstelle angegeben werden. Dies kann sp&auml;ter ebenfalls per Attribut erfolgen.</p>
	
    <p>Jedes Device muss an eine <a href="#TUL">TUL</a> gebunden sein. Die &lt;group&gt; Parameter werden entweder als Gruppenadresse (0-15/0-15/0-255) oder als Hex-notation angegeben (0-f0-f0-ff).
    Alle definierten Gruppen k&ouml;nnen f&uuml;r die Buskommunikation verwendet werden. Ohne weitere Attribute, werden alle eingehenden Nachrichten in state &uuml;bersetzt. 
	Per default wird &uuml;ber die erste Gruppe gesendet.<br>
	Wenn Ihr einen readingNamen angebt, wird dieser als Basis für die Readings benutzt (z.B. hugo-set, hugo-get for name hugo).<br>
	Wollt Ihr &uuml;ber eine andere Gruppe senden. m&uuml;sst Ihr diese indizieren (set &lt;devname&gt; value &lt;17.0&gt; &lt;g2&gt;).</p>
	
    <p>Das Modul <a href="#autocreate">autocreate</a> generiert eine Instanz f&uuml;r jede unbekannte Gruppenadresse. Das Ger&auml;t selbst wird jedoch NICHT korrekt funktionieren, so lange noch kein korrekter 
	DPT angelegt ist. Der Name ist immer KNX_nnmmooo wobei nn die Linie ist, mm der Bereich und ooo die Geräteadresse.</p>

    <p>Example:</p>
      <pre>
      define lamp1 KNX 0/10/12:dpt1
      define lamp1 KNX 0/10/12:dpt1:meinName 0/0/5:dpt1.001
      define lamp1 KNX 0A0C:dpt1.003 myTul
      </pre>
	  
	Ein Hinweis bezüglich dem binären Datentyp dpt1: alle Untertypen müssen über das Schlüsselwort value gesetzt werden. Empfangene Telegramme werden entsprechend ihrer Definition automatisch
	umbenannt. Zu sendende Telegramme sind immer min on/off zu belegen!<br>
	Die zur Verfügung stehenden on/off Schaltflächen ohne den Schlüssel value sind ein absoluter Sonderfall und gelten für den dpt1 und alle Untertypen.
	
    <p>Example:</p>
      <pre>
      define rollo KNX 0/10/12:dpt1.008
	  set rollo value off
	  set rollo value on
      </pre>
	  
  </ul>
  
  <p><a name="KNXset"></a> <b>Set</b></p>
  <ul>
    <code>set &lt;name&gt; &lt;on, off&gt;</code> [g&lt;groupnr&gt;]
	<code>set &lt;name&gt; &lt;on-for-timer, on-until&gt; &lt;time&gt; [g&lt;groupnr&gt;]</code>
	<code>set &lt;name&gt; &lt;value&gt; [g&lt;groupnr&gt;]</code>
	<code>set &lt;name&gt; &lt;string&gt; [g&lt;groupnr&gt;]</code>
	<code>set &lt;name&gt; &lt;raw&gt; [g&lt;groupnr&gt;]</code>
	
    <p>Example:</p>
    <pre>
      set lamp1 on
      set lamp1 off
      set lamp1 on-for-timer 10
      set lamp1 on-until 13:15:00
      set foobar raw 234578
      set thermo value 23.44
	  set message value Hallo Welt
    </pre>

	<p>Wenn eine Gruppe angegeben wurde (g&lt;groupnr&gt;) wird das Telegramm an de indizierte Gruppe gesendet (start bei 1, wie in der Definition angegeben).</p>
	<pre>
      define lamp1 KNX 0/10/01:dpt1 0/10/02:dpt1
      set lamp1 on g2 (will send "on" to 0/10/02)
	</pre>

	<p>Ein Dimmer mit Slider:</p>
	<pre>
      define dim1 KNX 0/0/5:dpt5.001
      attr dim1 slider 0,1,100
      attr dim1 webCmd value
	</pre>
	
	<p>Aktuelle Uhrzeit / Datum k&ouml;nnen wie folgt auf den Bus gelegt werden:</p>
	<pre>
      define timedev KNX 0/0/7:dpt10
      attr timedev webCmd value now
      
      define datedev KNX 0/0/8:dpt11
      attr datedev webCmd value now
      
      # send every midnight the new date
      define dateset at *00:00:00 set datedev value now
      
      # send every hour the current time
      define timeset at +*01:00:00 set timedev value now
	</pre>	
  </ul>
 
  <p><a name="KNXget"></a> <b>Get</b></p>
  <ul>  
  <p>Bei jeder Ausf&uuml;hrung wird eine Leseanfrage an die entsprechende Gruppe geschickt. Die Gruppe muss in der Lage sein, auf diese Anfrage zu antworten (dies ist nicht immer der Fall).<br>
  Die Antwort der Gruppe wird nicht im FHEMWEB angezeigt. Das empfangene Telegramm wird (wie jedes andere) ausgewertet.</p>
  </ul>
  
  <p><a name="KNXattr"></a> <b>Attributes</b></p>
  <ul><br>
	Common attributes:<br>
    <a href="#DbLogInclude">DbLogInclude</a><br>
	<a href="#DbLogExclude">DbLogExclude</a><br>
    <a href="#IODev">IODev</a><br>
    <a href="#alias">alias</a><br>
    <a href="#comment">comment</a><br>
    <a href="#devStateIcon">devStateIcon</a><br>
    <a href="#devStateStyle">devStateStyle</a><br>
    <a href="#do_not_notify">do_not_notify</a><br>
    <a href="#readingFnAttributes">readingFnAttributes</a><br>
    <a href="#event-aggregator">event-aggregator</a><br>
    <a href="#event-min-interval">event-min-interval</a><br>
    <a href="#event-on-change-reading">event-on-change-reading</a><br>
    <a href="#event-on-update-reading">event-on-update-reading</a><br>
    <a href="#eventMap">eventMap</a><br>
    <a href="#group">group</a><br>
    <a href="#icon">icon</a><br>
    <a href="#room">room</a><br>
    <a href="#showtime">showtime</a><br>
    <a href="#sortby">sortby</a><br>
    <a href="#stateFormat">stateFormat</a><br>
    <a href="#userReadings">userReadings</a><br>
    <a href="#userattr">userattr</a><br>
    <a href="#verbose">verbose</a><br>
    <a href="#webCmd">webCmd</a><br>
    <a href="#widgetOverride">widgetOverride</a><br>
	<br>
  </ul>

  <p><a name="KNXformat"></a> <b>format</b></p>
  <ul> 
	Der Inhalt dieses Attributes wird bei jedem empfangenen Wert angehangen, bevor der Wert in state kopeiert wird.
      <p>Example:</p>
      <pre>
      define myTemperature KNX 0/1/1:dpt5
      attr myTemperature format &degC;
      </pre>
  </ul> 

  <p><a name="KNXstateRegex"></a> <b>stateRegex</b></p>
  <ul> 
	Es kann eine Reihe an Search/Replace Patterns &uuml;bergeben werden (getrennt durch einen Slash). Intern wird der neue Wert von state immer im Format getG&lt;group&gt;:&lt;state-value&gt;. abgebildet. 
	Die Ersetzungen werden bei bei jedem neuen Telegramm vorgenommen. Ihr k&ouml;nnt die Funktion f&uuml;r Konvertierungen nutzen, Einheiten hinzuf&uuml;gen, Spaß mit Icons haben, ...
	Diese Funktion wirkt nur auf den Inhalt von State - sonst wird nichts beeinflusst.
	Die Funktion wird direkt nach dem Ersetzen der Readings-Namen und dem ergänzen der Formate ausgeführt.
      <p>Example:</p>
      <pre>
      define myLamp KNX 0/1/1:dpt1 0/1/2:dpt1 0/1/2:dpt1
	  attr myLamp stateRegex /getG1:/steuern:/ /getG2:/status:/ /getG3:/sperre:/ /setG[13]:/steuern:/ /setG[3]://
	  attr myLamp devStateIcon status.on:general_an status.off:general_aus sperre.on:lock steuern.*:hourglass
      </pre>    
  </ul>	
 
  <p><a name="KNXstateCmd"></a> <b>stateCmd</b></p>
  <ul>
	Hier könnt Ihr ein perl-Kommando angeben, welches state beeinflusst. Die Funktion wird unmittelbar vor dem Update des Readings aufgerufen - also nach dem Umbennenen der Readings, format und regex.
	Es ist ein gültiges Perl-Kommando anzugeben (vgl. stateFormat). Im Gegensatz zu StateFormat wirkt sich dieses Attribut inhaltlich auf das Reading aus, und nicht "nur" auf die Anzeige im FHEMWEB.
      <p>Beispiel:</p>
      <pre>
      define myLamp KNX 0/1/1:dpt1 0/1/2:dpt1 0/1/2:dpt1
      attr myLamp stateCmd {$state = sprintf("%s", ReadingsVal($name,"getG2","undef"))}
      </pre>    
  </ul>

  <p><a name="KNXanswerReading"></a> <b>answerReading</b></p>
  <ul> 
	Wenn aktiviert, antwortet FHEM auf Leseanfragen. Der Inhalt von state wird auf den Bus gelegt.
    <p>Leseanfragen werden beantwortet, wenn der Wert auf 1 gesetzt ist.</p>
  </ul>

  <p><a name="KNXlistenonly"></a> <b>listenonly</b></p>
  <ul> 
	Wenn auf 1 gesetzt, kann das Ger&auml;t keine Nachrichten senden. Sowohl Leseanfragen als auch get sind verboten.
  </ul>	 

  <p><a name="KNXreadonly"></a> <b>readonly</b></p>
  <ul> 
	Wenn auf 1 gesetzt, kann das Ger&auml;t keine Nachrichten senden. Leseanfragen sind verboten. Get ist erlaubt.
  </ul>	 

  <p><a name="KNXslider"></a> <b>slider</b></p>
  <ul> 
	slider &lt;min&gt;,&lt;step&gt;,&lt;max&gt;<br>
	Mit diesem Attribut k&ouml;nnt Ihr jedem Ger&auml;t einen Slider verpassen.
      <p>Example:</p>
      <pre>
      define myDimmer KNX 0/1/1:dpt5
      attr myDimmer slider 0,1,100
	  attr myDimmer webCmd value
      </pre>
  </ul>  

  <p><a name="KNXdpt"></a> <b>DPT - datapoint-types</b></p>
  <ul>  
  <p>Die folgenden DPT sind implementiert und m&uuml;ssen in der Gruppendefinition angegeben werden.</p>					
	dpt1 on, off<br>
	dpt1.001 on, off<br>
	dpt1.002 true, false<br>
	dpt1.003 enable, disable<br>	
	dpt1.004 no ramp, ramp<br>
	dpt1.005 no alarm, alarm<br>
	dpt1.006 low, high<br>
	dpt1.007 decrease, increase<br>
	dpt1.008 up, down<br>
	dpt1.009 open, closed<br>	
	dpt1.010 start, stop<br>	
	dpt1.011 inactive, active<br>
	dpt1.012 not inverted, inverted<br>
	dpt1.013 start/stop, ciclically<br>
	dpt1.014 fixed, calculated<br>
	dpt1.015 no action, reset<br>
	dpt1.016 no action, acknowledge<br>
	dpt1.017 trigger, trigger<br>
	dpt1.018 not occupied, occupied<br>
	dpt1.019 closed, open<br>
	dpt1.020 logical or, logical and<br>
	dpt1.021 scene A, scene B<br>
	dpt1.022 move up/down, move and step mode<br>
	dpt2 value on, value off, value forceOn, value forceOff<br>
	dpt3 -100..+100<br>
	dpt5 0..255<br>
	dpt5.001 0..100	%<br>
	dpt5.003 0..360	&deg;<br>
	dpt5.004 0..255	%<br>
	dpt6 -127..+127<br>
	dpt6.001 0..100	%<br>
	dpt7 0..65535<br>
	dpt7.001 0..65535 s<br>
	dpt7.005 0..65535 s<br>
	dpt7.005 0..65535 m<br>	
	dpt7.012 0..65535 mA<br>	
	dpt7.013 0..65535 lux<br>
	dpt8 -32768..32768<br>
	dpt8.005 -32768..32768 s<br>
	dpt8.010 -32768..32768 %<br>
	dpt8.011 -32768..32768 &deg;<br>
	dpt9 -670760.0..+670760.0<br>
	dpt9.001 -670760.0..+670760.0 &deg;<br>
	dpt9.004 -670760.0..+670760.0 lux<br>
	dpt9.005 -670760.0..+670760.0 m/s<br>	
	dpt9.006 -670760.0..+670760.0 Pa<br>	
	dpt9.007 -670760.0..+670760.0 %<br>
	dpt9.008 -670760.0..+670760.0 ppm<br>	
	dpt9.009 -670760.0..+670760.0 m³/h<br>
	dpt9.010 -670760.0..+670760.0 s<br>
	dpt9.021 -670760.0..+670760.0 mA<br>	
	dpt9.024 -670760.0..+670760.0 kW<br>
	dpt9.025 -670760.0..+670760.0 l/h<br>
	dpt9.026 -670760.0..+670760.0 l/h<br>
	dpt9.028 -670760.0..+670760.0 km/h<br>
	dpt10 01:00:00<br>
	dpt11 01.01.2000<br>
	dpt12 0..+Inf<br>
	dpt13 -Inf..+Inf<br>	
	dpt13.010 -Inf..+Inf Wh<br>
	dpt13.013 -Inf..+Inf kWh<br>
	dpt14 -Inf.0..+Inf.0<br>
	dpt14.019 -Inf.0..+Inf.0 A<br>
	dpt14.027 -Inf.0..+Inf.0 V<br>
	dpt14.056 -Inf.0..+Inf.0 W<br>
	dpt14.068 -Inf.0..+Inf.0 &degC;<br>
	dpt14.076 -Inf.0..+Inf.0 m&sup3;<br>
	dpt16 String;<br>
	dpt16.000 ASCII-String;<br>
	dpt16.001 ISO-8859-1-String (Latin1);<br>
	dpt232 RGB-Value RRGGBB<br>
  </ul>
</ul>
=end html_DE

=cut
