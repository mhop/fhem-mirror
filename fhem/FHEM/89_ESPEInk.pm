# $Id$

package main;
use strict;
use warnings;

use Time::HiRes qw( time );
use POSIX qw(strftime);
use Encode qw(decode encode);
use GD;
use Scalar::Util;
use File::Basename;
use File::Copy;
use File::Spec::Functions;
use File::Find;
use HttpUtils;

my $ESPEInk_has_SVG = 0;
eval {require Image::LibRSVG};
if ($@) {
	Log3 undef, 2, "ESPEInk: Error loading LibRSVG. Result of checking LibRSVG is: '$@'";
} else {
	$ESPEInk_has_SVG = 1;
	Image::LibRSVG->import();
}

#---------------------------------------------------------------------------------------------------
# define all needed palettes (i.e. arrays with rgb values fitting to each of the eInk color values)
# needed to map real color values in the picture to respective color values of the eInk display
my @ESPEInk_palettes = (
[2,[0,0,0],[255,255,255]],
[3,[0,0,0],[255,255,255],[127,0,0]],
[3,[0,0,0],[255,255,255],[127,127,127]],
[4,[0,0,0],[255,255,255],[127,127,127],[127,0,0]],
[2,[0,0,0],[255,255,255]],
[3,[0,0,0],[255,255,255],[220,180,0]]
);

#---------------------------------------------------------------------------------------------------
# define all possible device types and thier parameters (width, height, palette index and id)
my %ESPEInk_devices = (
#	"4.3inch_e-Paper_UART_Module"	=>	{width	=>	200,	height	=>	200,	pindex	=>	10,	id	=>	26},
#	"10.3inch_e-Paper_HAT_(D)"		=>	{width	=>	200,	height	=>	200,	pindex	=>	10,	id	=>	25},
#	"9.7inch_e-Paper_HAT"			=>	{width	=>	200,	height	=>	200,	pindex	=>	10,	id	=>	24},
#	"7.8inch_e-Paper_HAT"			=>	{width	=>	200,	height	=>	200,	pindex	=>	10,	id	=>	23},
#	"6inch_e-Paper_HAT"				=>	{width	=>	200,	height	=>	200,	pindex	=>	10,	id	=>	22},
#	"2.9inch_e-Paper_HAT_(D)"		=>	{width	=>	200,	height	=>	200,	pindex	=>	10,	id	=>	21},
	"7.5inch_e-Paper_HAT_V2_(B)"	=>	{width	=>	800,	height	=>	480,	pindex	=>	5,	id	=>	23},
	"7.5inch_e-Paper_HAT_V2"		=>	{width	=>	800,	height	=>	480,	pindex	=>	0,	id	=>	22},
	"7.5inch_e-Paper_HAT_(C)"		=>	{width	=>	640,	height	=>	384,	pindex	=>	5,	id	=>	21},
	"7.5inch_e-Paper_HAT_(B)"		=>	{width	=>	640,	height	=>	384,	pindex	=>	1,	id	=>	20},
	"7.5inch_e-Paper_HAT"			=>	{width	=>	640,	height	=>	384,	pindex	=>	0,	id	=>	19},
	"5.83inch_e-Paper_HAT_(C)"		=>	{width	=>	600,	height	=>	448,	pindex	=>	5,	id	=>	18},
	"5.83inch_e-Paper_HAT_(B)"		=>	{width	=>	600,	height	=>	448,	pindex	=>	1,	id	=>	17},
	"5.83inch_e-Paper_HAT"			=>	{width	=>	600,	height	=>	448,	pindex	=>	0,	id	=>	16},
	"4.2inch_e-Paper_Module_(C)"	=>	{width	=>	400,	height	=>	300,	pindex	=>	5,	id	=>	15},
	"4.2inch_e-Paper_Module_(B)"	=>	{width	=>	400,	height	=>	300,	pindex	=>	1,	id	=>	14},
	"4.2inch_e-Paper_Module"		=>	{width	=>	400,	height	=>	300,	pindex	=>	0,	id	=>	13},
	"2.9inch_e-Paper_Module_(D)"	=>	{width	=>	128,	height	=>	296,	pindex	=>	0,	id	=>	12},
	"2.9inch_e-Paper_Module_(C)"	=>	{width	=>	128,	height	=>	296,	pindex	=>	5,	id	=>	11},
	"2.9inch_e-Paper_Module_(B)"	=>	{width	=>	128,	height	=>	296,	pindex	=>	1,	id	=>	10},
	"2.9inch_e-Paper_Module"		=>	{width	=>	128,	height	=>	296,	pindex	=>	0,	id	=>	9},
	"2.7inch_e-Paper_HAT_(B)"		=>	{width	=>	176,	height	=>	264,	pindex	=>	1,	id	=>	8},
	"2.7inch_e-Paper_HAT"			=>	{width	=>	176,	height	=>	264,	pindex	=>	0,	id	=>	7},
	"2.13inch_e-Paper_HAT_(D)"		=>	{width	=>	104,	height	=>	212,	pindex	=>	0,	id	=>	6},
	"2.13inch_e-Paper_HAT_(C)"		=>	{width	=>	104,	height	=>	212,	pindex	=>	5,	id	=>	5},
	"2.13inch_e-Paper_HAT_(B)"		=>	{width	=>	104,	height	=>	212,	pindex	=>	1,	id	=>	4},
	"2.13inch_e-Paper_HAT"			=>	{width	=>	122,	height	=>	250,	pindex	=>	0,	id	=>	3},
	"1.54inch_e-Paper_Module_(C)"	=>	{width	=>	152,	height	=>	152,	pindex	=>	5,	id	=>	2},
	"1.54inch_e-Paper_Module_(B)"	=>	{width	=>	200,	height	=>	200,	pindex	=>	3,	id	=>	1},
	"1.54inch_e-Paper_Module"		=>	{width	=>	200,	height	=>	200,	pindex	=>	0,	id	=>	0}
);

#---------------------------------------------------------------------------------------------------
# Default values for upload control (e.g. number of maximum retries in case of communication problems)
my %ESPEInk_uploadcontrol = (
	"retries"		=> 0,
	"maxretries"	=> 3,
	"timeout"		=> 10,
	"srcindex"		=> 0,
	"stepindex"		=> 0
);

my %ESPEInk_sets = (
	"convert"		=> "noArg",				# run conversion of input picture and possible additional objects (text)
	"upload"		=> "noArg",				# perform upload of converted picture to EInk Display via WLAN
	"addtext"		=> "textFieldNL",		# add text to picture at given position (see set for details)
	"addicon"		=> "textFieldNL",		# add icon to picture at given position (see set for details)
	"iconreading"	=> "textFieldNL",		# add text to picture at given position (see set for details)
	"textreading"	=> "textFieldNL"		# add text to picture at given position (see set for details)
);

my %ESPEInk_gets = (
	"devices"		=> ":noArg"			# get list of all supported devices
);

my $ESPEInk_InitializationDone = 0;

#---------------------------------------------------------------------------------------------------
# Initialize Module
sub ESPEInk_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'ESPEInk_Define';
    $hash->{UndefFn}    = 'ESPEInk_Undef';
    $hash->{ShutdownFn} = 'ESPEInk_Shutdown';
    $hash->{SetFn}      = 'ESPEInk_Set';
    $hash->{GetFn}      = 'ESPEInk_Get';
    $hash->{AttrFn}     = 'ESPEInk_Attr';
    $hash->{NotifyFn}   = 'ESPEInk_Notify';
    $hash->{UploadFn}   = 'ESPEInk_Upload';
    $hash->{ConvertFn}  = 'ESPEInk_Convert';

	my $devs = "";
	for my $key ( sort keys %ESPEInk_devices ) { $devs .= $key.","; }
	$devs = substr($devs,0,length($devs)-1);
    $hash->{AttrList} =
        "picturefile "
        . "url "
        . "interval "
		. "devicetype:".$devs." "
		. "boardtype:ESP8266,ESP32 "
		. "convertmode:level,dithering "
		. "colormode:monochrome,color "
		. "width "
		. "height "
		. "x0 "
		. "y0 "
		. "placement:top-left,top-right,bottom-left,bottom-right "
		. "scale2fit:0,1 "
		. "coloroffset "
		. "maxretries "
		. "timeout "
		. "disable:0,1 "
		. "definition:textField-long "
		. "definitionFile "
        . $readingFnAttributes;

	$hash->{STATE} = "Initialized";
}

#---------------------------------------------------------------------------------------------------
# Define new device of type ESPEInk
sub ESPEInk_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    
    if(int(@param) < 3) {
        return "too few parameters: define <name> ESPEInk <picturefile> <subfolder> <url> <interval> <colormode> <convertmode>";
    }

	if (!open(IMAGE, $param[2])) {
		return "ESPEInk: Invalid filename $param[2]. Must point to a readable file.";
	} else {
		close IMAGE;
	}

    $hash->{NAME}  = $param[0];
    $hash->{PICTUREFILE} = $param[2];
    $hash->{SUBFOLDER} = "images";
	$hash->{INTERVAL} = 300;
	$hash->{COLORMODE} = "monochrome";
	$hash->{CONVERTMODE} = "level";
	$hash->{DEVICETYPE} = "1.54inch_e-Paper_Module";
	$hash->{BOARDTYPE} = "ESP8266";
	$hash->{URL} = "";

    if(int(@param) > 7) {
		$hash->{CONVERTMODE} = $param[7];
    } elsif (int(@param) > 6) {
		$hash->{COLORMODE} = $param[6];
    } elsif (int(@param) > 5) {
		$hash->{INTERVAL} = $param[5];
    } elsif (int(@param) > 4) {
		$hash->{URL} = $param[4];
    } elsif (int(@param) > 3) {
		$hash->{SUBFOLDER} = $param[3];
	}		

	my $rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
	mkdir $rootname."/".$hash->{SUBFOLDER}."/".$param[0];
	copy($param[2],$rootname."/".$hash->{SUBFOLDER}."/".$param[0]); # local copy of the file for usage in FHEMWEB (display)
	ESPEInk_MakePictureHTML($param[0],"source_picture",basename($param[2]));

	ESPEInk_ResetNotifies({hash=>$hash});
	InternalTimer(gettimeofday()+$hash->{INTERVAL}, "ESPEInk_FullUpdate", $hash, 0) if ($hash->{INTERVAL} > 0);
	$hash->{STATE} = "Added as new device";

    return undef;
}

#---------------------------------------------------------------------------------------------------
# shutdown device
sub ESPEInk_Shutdown($$) {
    my ($hash, $arg) = @_;
	
	# clean up directories and files created
    ESPEInk_Cleanup($hash);
	
	RemoveInternalTimer ($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    Log3 $hash, 5, "Prepared shutown for ".$hash->{NAME};
    return undef;
}

#---------------------------------------------------------------------------------------------------
# remove device
sub ESPEInk_Undef($$) {
    my ($hash, $arg) = @_;
	
	# clean up directories and files created
    ESPEInk_Cleanup($hash);

	RemoveInternalTimer ($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    Log3 $hash, 5, "Removed device for ".$hash->{NAME};
    return undef;
}

#---------------------------------------------------------------------------------------------------
# Get function, currently only display of supported devices is implemented
sub ESPEInk_Get($@) {
	my ($hash, @param) = @_;
	
	return '"get ESPEInk" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	if(!$ESPEInk_gets{$opt}) {
		return "Unknown argument $opt, choose one of " . join(" ", map{ "$_".$ESPEInk_gets{$_}} keys %ESPEInk_gets);
	}
	
	if ($opt eq 'devices') {
		my $result = "";
		$result .= "Name                            Width	Height\n";
		$result .= "----------------------------------------------\n";
		foreach my $name (sort keys %ESPEInk_devices) {
			my $fill = ' ' x (30-length($name));
			$result .= $name.$fill."	".$ESPEInk_devices{$name}{"width"}."	".$ESPEInk_devices{$name}{"height"}."\n";
		}
		return $result;
	}

	return $ESPEInk_gets{$opt};
}

#---------------------------------------------------------------------------------------------------
# Set function, convert/upload/addText if text is existing also removeText
sub ESPEInk_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set ESPEInk" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join(" ", @param);
	my $itext;

	if(!defined($ESPEInk_sets{$opt})) {
		return "Unknown argument $opt, choose one of " . join(" ", map{ "$_:".$ESPEInk_sets{$_}} keys %ESPEInk_sets);
	}
    
	if ($opt eq 'addtext' || $opt eq 'textreading' || $opt eq 'addicon' || $opt eq 'iconreading') {
		my ($text, $x, $y, $size, $angle, $color, $font, $linegap, $blockwidth) = split("#",$value);
		return "No text defined, use format: 'addtext text#x#y#size#angle#color#font'" if (!$text && ($opt eq 'addtext'));
		return "No reading defined, use format: 'textreading device:reading#x#y#size#angle#color#font'" if (!$text && ($opt eq 'textreading'));
		return "No icon defined, use format: 'addicon icon#x#y#size#angle#color'" if (!$text && ($opt eq 'addicon'));
		return "No reading defined, use format: 'iconreading device:reading#x#y#size#angle#color'" if (!$text && ($opt eq 'iconreading'));
		my($texts,$eval) = split("{",$text);
		my ($device,$reading) = split(':',$texts);
		$reading = "state" if (!$reading);

		readingsBeginUpdate($hash);
		$itext = ReadingsVal($name,"deftexts",0)+1;
		readingsBulkUpdate($hash,"deftexts",$itext);

		if ($opt eq 'textreading' or $opt eq 'iconreading') {
			readingsBulkUpdate($hash,$itext."-trigger",$text);
			$text = ReadingsVal($device,$reading,'');
			if ($eval) {
				$eval =~ s/\}//g;
				$text = sprintf($eval,$text);
			}
			readingsBulkUpdate($hash,$itext."-text",$text) if ($opt eq 'textreading');
			ESPEInk_ResetNotifies({hash=>$hash});
		}

		if ($opt eq 'iconreading' || $opt eq 'addicon') {
			readingsBulkUpdate($hash,$itext."-icon",$text) if ($opt eq 'iconreading');
			readingsBulkUpdate($hash,$itext."-isIcon",1);
		} elsif ($opt eq 'textreading' || $opt eq 'addtext') {
			readingsBulkUpdate($hash,$itext."-isIcon",0)
		}

		$x = 0 if (!$x || (($x !~ '-?\d+')&&($x !~ '(left|mid|right)')));
		$y = 0 if (!$y || (($y !~ '-?\d+')&&($y !~ '(top|mid|bottom)')));
		$size = 10 if (!$size || ($size !~ '\d+'));
		$angle = 0 if (!$angle || ($angle !~ '-?\d+'));

		$color = "000000" if (!$color || !ESPEInk_CheckColorString($color));

		$font = "medium" if (!ESPEInk_CheckFontString($font));
		$linegap = 0 if (!$linegap || ($linegap !~ '\d+'));
		$blockwidth = 0 if (!$blockwidth || ($blockwidth !~ '\d+'));

		readingsBulkUpdate($hash,$itext."-def",$opt."#".$value);
		readingsBulkUpdate($hash,$itext."-text",$text) if ($opt eq 'addtext');
		readingsBulkUpdate($hash,$itext."-icon",$text) if ($opt eq 'addicon');
		readingsBulkUpdate($hash,$itext."-x",$x);
		readingsBulkUpdate($hash,$itext."-y",$y);
		readingsBulkUpdate($hash,$itext."-size",$size);
		readingsBulkUpdate($hash,$itext."-angle",$angle);
		readingsBulkUpdate($hash,$itext."-color",$color);
		readingsBulkUpdate($hash,$itext."-font",$font) if ($opt eq 'addtext' || $opt eq 'textreading');
		readingsBulkUpdate($hash,$itext."-linegap",$linegap);
		readingsBulkUpdate($hash,$itext."-blockwidth",$blockwidth);

		ESPEInk_AddTextAttributes($name,$itext);

		delete $ESPEInk_sets{'removeobject'};
		my $list = "";
		for (my $i=1; $i<=ReadingsVal($name,"deftexts",0); $i++) {
			$list .= ",".$i;
		}
		$ESPEInk_sets{'removeobject'} = "multiple-strict".$list if ($list ne "");

		readingsEndUpdate($hash,1);
		$hash->{STATE} = "Added text $text at ($x,$y) for display";

		return undef;
	}

	if ($opt eq 'removeobject') {
		my @args = split(",",$value);

		foreach (reverse sort @args) {
			ESPEInk_RemoveTextReadings($hash,$_)
		}

		delete $ESPEInk_sets{'removeobject'};
		my $list = "";
		for (my $i=1; $i<=ReadingsVal($name,"deftexts",0); $i++) {
			$list .= ",".$i;
		}
		$ESPEInk_sets{'removeobject'} = "multiple-strict".$list if ($list ne "");;
		
		ESPEInk_ResetNotifies({hash=>$hash});
		$hash->{STATE} = "Removed ".@args." texts from display";
		return undef;
	}

	if ($opt eq 'upload') {
		$hash->{STATE} = ESPEInk_Upload($hash);
		return undef;
	}

	if ($opt eq 'convert') {
		$hash->{STATE} = ESPEInk_Convert($hash,0);
		return undef;
	}
}


#---------------------------------------------------------------------------------------------------
# Attr function, check attribute setting, conversion to readings and error handling
sub ESPEInk_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	my $err;
    my $hash = $defs{$name};

	if($cmd eq "set") {
        if($attr_name eq "interval") {
			if(!looks_like_number($attr_value)) {
			    $err = "Invalid argument $attr_value to $attr_name. Must be a number.";
			    return $err;
			}
			$hash->{INTERVAL} = $attr_value;
			RemoveInternalTimer ($hash);
			InternalTimer(gettimeofday()+$attr_value, "ESPEInk_FullUpdate", $hash, 0) if ($attr_value > 0);
		} elsif($attr_name eq "url") {
			$hash->{URL} = $attr_value;
		} elsif($attr_name eq "picturefile") {
			$err = ESPEInk_UpdatePicture($hash,$attr_value);
			return $err if (defined $err);
			$hash->{PICTUREFILE} = $attr_value;
		} elsif($attr_name eq "devicetype") {
			my $colormode = ESPEInk_GetSetting($name,"colormode");
			my $ipal = $ESPEInk_devices{$attr_value}{"pindex"};
			$hash->{DEVICETYPE} = $attr_value;
			if (($colormode eq "color") && (($ipal&1)==0) && $ESPEInk_InitializationDone) {
			    $err = "Inconsistent setting for device type $attr_value. Device does not support color mode, setting colormode attribute to monochrome.";
				fhem("attr $name colormode monochrome");
				fhem("attr $name devicetype $attr_value");
			    return $err;
			}
		} elsif($attr_name eq "boardtype") {
			$hash->{BOARDTYPE} = $attr_value;
		} elsif($attr_name eq "colormode") {
		    my $devtype = ESPEInk_GetSetting($name,"devicetype");
			my $ipal = $ESPEInk_devices{$devtype}{"pindex"};
			if (($attr_value eq "color") && (($ipal&1)==0) && $ESPEInk_InitializationDone) {
			    $err = "Invalid argument $attr_value to $attr_name. Device does not support color mode.";
			    return $err;
			}
			$hash->{COLORMODE} = $attr_value;
		} elsif($attr_name =~ '^\d+-.*') {
			if ($attr_name =~ '(x$|y$|size$)') {
				return "Invalid argument $attr_value to $attr_name must be an interger number" if ($attr_value !~ '-?\d+');
			} elsif ($attr_name =~ '(size)') {
				return "Invalid argument $attr_value to $attr_name must be a positive interger number"  if ($attr_value !~ '\d+');
			} elsif ($attr_name =~ '(angle)') {
				return "Invalid argument $attr_value to $attr_name must be an integer number between -180 and +180"  if ($attr_value !~ '-?\d+' || int($attr_value) < -180 || int($attr_value) > 180);
			} elsif ($attr_name =~ '(color)') {
				return "Invalid argument $attr_value to $attr_name must be a valid rgb hex string" if (!ESPEInk_CheckColorString($attr_value));
			} elsif ($attr_name =~ '(font)') {
				return "Invalid argument $attr_value to $attr_name either one of small/medium/large/giant or a path to a valid TTF file" if (!ESPEInk_CheckFontString($attr_value));
			} elsif ($attr_name =~ '(icon)') {
				my ($ret,$path) = ESPEInk_CheckIconString($attr_value);
				return "Invalid argument $attr_value to $attr_name must be a valid icon" if (!$ret);
			} elsif ($attr_name =~ '(trigger)') {
				readingsSingleUpdate( $hash,$attr_name,$attr_value,1);
				ESPEInk_ResetNotifies({hash=>$hash});
			}
			readingsSingleUpdate( $hash,$attr_name,$attr_value,1);
		} elsif($attr_name eq "convertmode") {
			$hash->{CONVERTMODE} = $attr_value;
		} elsif($attr_name eq "width") {
		} elsif($attr_name eq "height") {
		} elsif($attr_name eq "x0") {
		} elsif($attr_name eq "y0") {
		} elsif($attr_name eq "placement") {
		} elsif($attr_name eq "scale2fit") {
		} elsif($attr_name eq "coloroffset") {
		} elsif($attr_name eq "maxretries") {
		} elsif($attr_name eq "timeout") {
		} elsif($attr_name eq "definition") {
				ESPEInk_ResetNotifies({hash=>$hash,definition=>$attr_value});
		} elsif($attr_name eq "definitionFile") {
				ESPEInk_ResetNotifies({hash=>$hash,definitionfile=>$attr_value});
		} elsif(IsDisabled($name) && $attr_value eq "1") {
			Log3 $hash, 5, "$name: disable attribute set, stop timer";
			RemoveInternalTimer ($hash);
		} elsif(IsDisabled($name) && $attr_value eq "0") {
			Log3 $hash, 5, "$name: disable attribute unset, restart timer";
			RemoveInternalTimer ($hash);
			InternalTimer(gettimeofday()+ESPEInk_GetSetting($name,"interval"), "ESPEInk_FullUpdate", $hash, 0) if (ESPEInk_GetSetting($name,"interval") > 0);
		}
	}

	if($cmd eq "del") {
        if(IsDisabled($name)) {
			Log3 $hash, 5, "$name: disable attribute removed, restart timer";
			RemoveInternalTimer ($hash);
			InternalTimer(gettimeofday()+ESPEInk_GetSetting($name,"interval"), "ESPEInk_FullUpdate", $hash, 0) if (ESPEInk_GetSetting($name,"interval") > 0);
		} elsif($attr_name =~ '.*-trigger') {
			my ($ind,$cmd) = split("-",$attr_name);
			my ($type,$trigger) = split("#",ReadingsVal($name,$ind."-def",""));
			readingsDelete($hash,"$ind-trigger") if ($type eq 'addtext' || $type eq 'addicon');
			readingsSingleUpdate( $hash, "$ind-icon", $trigger, 1 ) if ($trigger && ReadingsVal($name,"$ind-isIcon",0));
			readingsSingleUpdate( $hash, "$ind-text", $trigger, 1 ) if ($trigger && !ReadingsVal($name,"$ind-isIcon",0));
			Log3 $hash, 5, "$name: deleted attribute $attr_name for triggering reset to initial definition";
		} elsif($attr_name =~ '^\d+-.*') {
			my ($ind,$cmd) = split("-",$attr_name);
			my ($type, $text, $x, $y, $size, $angle, $color, $font, $linegap, $blockwidth) = split("#",ReadingsVal($name,$ind."-def",""));

			Log3 $hash, 5, "$name: $ind, $cmd, $text, $x, $y, $size, $angle, $color, $font, $linegap, $blockwidth";

			if ($cmd =~ "text") {
				readingsSingleUpdate( $hash, "$ind-text", $text, 1 ) if ($text);
			} elsif ($cmd =~ "icon") {
				readingsSingleUpdate( $hash, "$ind-icon", $text, 1 ) if ($text);
			} elsif ($cmd =~ "x") {
				readingsSingleUpdate( $hash, "$ind-x", $x, 1 ) if ($x);
				readingsSingleUpdate( $hash, "$ind-x", 0, 1 ) if (!$x);
			} elsif ($cmd =~ "y") {
				readingsSingleUpdate( $hash, "$ind-y", $y, 1 ) if ($y);
				readingsSingleUpdate( $hash, "$ind-y", 0, 1 ) if (!$y);
			} elsif ($cmd =~ "size") {
				readingsSingleUpdate( $hash, "$ind-size", $size, 1 ) if ($size);
				readingsSingleUpdate( $hash, "$ind-size", 10, 1 ) if (!$size);
			} elsif ($cmd =~ "angle") {
				readingsSingleUpdate( $hash, "$ind-angle", $angle, 1 ) if ($angle);
				readingsSingleUpdate( $hash, "$ind-angle", 0, 1 ) if (!$angle);
			} elsif ($cmd =~ "color") {
				readingsSingleUpdate( $hash, "$ind-color", $color, 1 ) if ($color);
				readingsSingleUpdate( $hash, "$ind-color", "000000", 1 ) if (!$color);
			} elsif ($cmd =~ "font" && !ReadingsVal($name,"$ind-isIcon",0)) {
				readingsSingleUpdate( $hash, "$ind-font", $font, 1 ) if ($font);
				readingsSingleUpdate( $hash, "$ind-font", "medium", 1 ) if (!$font);
			} elsif ($cmd =~ "linegap" && !ReadingsVal($name,"$ind-isIcon",0)) {
				readingsSingleUpdate( $hash, "$ind-linegap", $linegap, 1 ) if ($linegap);
				readingsSingleUpdate( $hash, "$ind-linegap", 0, 1 ) if (!$linegap);
			} elsif ($cmd =~ "blockwidth" && !ReadingsVal($name,"$ind-isIcon",0)) {
				readingsSingleUpdate( $hash, "$ind-blockwidth", $blockwidth, 1 ) if ($blockwidth);
				readingsSingleUpdate( $hash, "$ind-blockwidth", 0, 1 ) if (!$blockwidth);
			}

			Log3 $hash, 5, "$name: deleted attribute $attr_name reset to default if in initial definition (set ".$name." ".$type.")";
		}
	}

	return undef;
}

#---------------------------------------------------------------------------------------------------
# Notify for INITIALIZED and check settings (e.g. when reload is called)
sub ESPEInk_Notify($$)
{
    my ($own, $source) = @_;

	my $name = $own->{NAME};
    my $hash = $defs{$name};
	my $sname = $source->{NAME};
	my $doupdate = 0;

	Log3 $own, 5, "$name: Event received from device $sname (events are: ".join("; ",@{deviceEvents($source, 1)}).")";

    if (grep(m/^INITIALIZED|REREADCFG$/, @{$source->{CHANGED}})) {
		Log3 $own, 5, "Making sure that settings are correct when initializing or rereading config";
		$ESPEInk_InitializationDone = 1;
		ESPEInk_ChecksWhenInitialized();
	}

    return if (IsDisabled($name));

    my $events = deviceEvents($source, 1);
    return if(!$events);

	my ($reading,$device,$sreading,$value);
	foreach my $event (@{$events}) {
		$event = "" if(!defined($event));
		($sreading,$value) = split(':',$event,2);

		my $definition = AttrVal($name,"definition",undef);
		my $definitionFile = AttrVal($name,"definitionFile",undef);
		
		if ($definitionFile) {
			my ($error, @content) = FileRead({FileName=>$definitionFile, ForceType=>"file"});
			
			if (!$error) {
				$definition .= "\n" . (join("\n", @content));
			} else {
				Log3 $own, 1, "Error ($error) reading definition from file $definitionFile";
			}
		}
		
		if ($definition) {	# work on all definitions if definition attribute is defined
			foreach my $line (split(/\n/,$definition)) { # go through the definition line by line
				next if ($line =~ /^\s*\#.*/); # check for comment lines
				my ($type, $text, $x, $y, $size, $ang, $col, $fnt) = split("#",$line);
				my $eval=0;
				($text,$eval) = split('{',$text);
				($device,$reading) = split(':',$text,2);
				$reading = "state" if (!$reading);
				if (($device) && ($device eq $sname) && ($reading eq $sreading))	{
					if (ESPEInk_GetSetting($name,"interval") == 0) {
						$doupdate = 1;	# there has been an update to one of the readings in the definition, do update if interval is 0
					}
				}
			}
		}

		for (my $i = 1; $i <= ReadingsVal($name,"deftexts",0); $i++) {
			my ($text,$eval) = split('{',ReadingsVal($name,$i."-trigger",""),2);
			($device,$reading) = split(':',$text,2);
			$reading = "state" if (!$reading);
			ESPEInk_ResetNotifies({hash=>$own}) if ($name eq $sname && $sreading =~ '.*trigger');	# make sure that changes in trigger setting are reflected in NOTIFYDEV
			if ($name eq $sname && $reading =~ 'interval') {								# take into account changes in interval settings
				
			}
			if (($device) && ($device eq $sname) && ($reading eq $sreading))	{
				if ($eval) {
					$eval =~ s/\}//g;
					$value = sprintf($eval,$value);
				}
				Log3 $own, 5, "Setting new text or icon to $value for device $name";
				readingsSingleUpdate( $hash,$i."-text",$value,1) if (!ReadingsVal($name,"$i-isIcon",0));
				if (ReadingsVal($name,"$i-isIcon",0)) {
					my $dsi = AttrVal($name,"devStateIcon",undef);
					if ($dsi) {
						my @list = split(" ", $dsi);
						foreach my $l (@list) {
						  my ($re, $iconName, $link) = split(":", $l, 3);
						  if(defined($re) && $sreading =~ m/^$re$/) {
							$value = $iconName;
						  }
						}						
					}
					readingsSingleUpdate( $hash,$i."-icon",$value,1);
				}
				if (ESPEInk_GetSetting($name,"interval") == 0) {
					$doupdate = 1;
				}
			}
		}
	}

	ESPEInk_FullUpdate($own) if ($doupdate);
    return;
}

#---------------------------------------------------------------------------------------------------
# function for doing a conversion and upload with the latest settings for the device (called when interval is > 0 or after trigger from external reading)
sub ESPEInk_FullUpdate($){
	my ($hash) = @_;
	my $name = $hash->{NAME};

	ESPEInk_Convert($hash, 1);
	
	RemoveInternalTimer ($hash);
	InternalTimer(gettimeofday()+ESPEInk_GetSetting($name,"interval"), "ESPEInk_FullUpdate", $hash, 0) if (ESPEInk_GetSetting($name,"interval") > 0);
}

#---------------------------------------------------------------------------------------------------
# Check color setting for validity
sub ESPEInk_ResetNotifies($) {
	my ($args) = @_;
	my $hash = $args->{hash};
	my $valdef = $args->{definition};
	my $valdeffile = $args->{definitionfile};
	my $name = $hash->{NAME};
	my ($device,$reading);
	my $notifies;
	
	$notifies = "";

	my $definition = (defined($valdef))?$valdef:AttrVal($name,"definition",undef);
	my $definitionFile = (defined($valdeffile))?$valdeffile:AttrVal($name,"definitionFile",undef);
	
	if ($definitionFile) {
		my ($error, @content) = FileRead({FileName=>$definitionFile, ForceType=>"file"});
		
		if (!$error) {
			$definition .= "\n" . (join("\n", @content));
		} else {
			Log3 $hash, 1, "Error ($error) reading definition from file $definitionFile";
		}
	}

	if ($definition) {	# work on all definitions if definition attribute is defined
		foreach my $line (split(/\n/,$definition)) { # go through the definition line by line
			next if ($line =~ /^\s*\#.*/); # check for comment lines
			my ($type, $text, $x, $y, $size, $ang, $col, $fnt) = split("#",$line);
			if ($type eq "iconreading" || $type eq "textreading") {
				my $eval;
				($text,$eval) = split("{",$text);
				($device,$reading) = split(':',$text);
				if ($device) {
					$reading = "state" if (!$reading);
					$notifies .= $device.":".$reading."|" if ($defs{$device});
					$reading = undef;
				}
			}
		}
	}

	for (my $i = 1; $i <= ReadingsVal($name,"deftexts",0); $i++) {
		my ($text,$eval) = split("{",ReadingsVal($name,$i."-trigger",""));
		($device,$reading) = split(':',$text);
		if ($device) {
			$reading = "state" if (!$reading);
			$notifies .= $device.":".$reading."|" if ($defs{$device});
			$reading = undef;
		}
	}
	
	$notifies .= $hash->{NAME}.":.*-trigger.*";										# make sure that changes in trigger are going to NotifyFn
	$notifies .= '|global';

	notifyRegexpChanged($hash, $notifies);
	Log3 $hash, 5, "Notify definition: ".($hash->{NOTIFYDEV}?$hash->{NOTIFYDEV}:"")." from $notifies";
}

#---------------------------------------------------------------------------------------------------
# cleanup
sub ESPEInk_Cleanup($) {
    my ($hash) = @_;
	
	# clean up directories and files created

	my $name = $hash->{NAME};
	my $fname = basename(ESPEInk_GetSetting($name,"picturefile"));

	my $rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
	unlink $rootname."/".$hash->{SUBFOLDER}."/".$name."/".$fname;		# remove local copy of input file in directory with device name
	unlink $rootname."/".$hash->{SUBFOLDER}."/".$name."/tmp_png.png";	# remove local copy of eventually existing temporary file in directory with device name
	unlink $rootname."/".$hash->{SUBFOLDER}."/".$name."/result.png";	# remove local copy of conversion result file in directory with device name
	rmdir $rootname."/".$hash->{SUBFOLDER}."/".$name;
}

#---------------------------------------------------------------------------------------------------
# Check color setting for validity
sub ESPEInk_CheckColorString($) {
	my ($color) = @_;
	return $color =~ '^(?:[0-9a-fA-F]{3}){1,2}$';
}

#---------------------------------------------------------------------------------------------------
# Get width and height of painted string
sub ESPEInk_GetStringPixelWidth($$$$$) {
	my ($name,$string,$font,$angle,$size) = @_;
	my $cw = 0;
	my $ch = 0;
	my $slength = length($string);
	my $wpixels = 0;
	my $hpixels = 0;
	
	($cw,$ch) = (6,12) if ($font eq 'small');
	($cw,$ch) = (7,13) if ($font eq 'medium');
	($cw,$ch) = (8,16) if ($font eq 'large');
	($cw,$ch) = (9,15) if ($font eq 'giant');
	
	if ($cw == 0) { # no standard font, use font from path
		my $dw = AttrVal($name,"width",$ESPEInk_devices{ESPEInk_GetSetting($name,"devicetype")}{"width"});
		my $dh = AttrVal($name,"height",$ESPEInk_devices{ESPEInk_GetSetting($name,"devicetype")}{"height"});
		my $image = GD::Image->new($dw,$dh,1);
		my @bounds = GD::Image->stringFT($image->colorAllocate(0,0,0),$font,$size,$angle/180*(4*atan2(1,1)),0,$size,$string);
		$wpixels = $bounds[4] - $bounds[0] - 1.5;
		$hpixels = $bounds[1] - $bounds[5];
	} else {
		$wpixels = $cw*$slength*cos($angle)+$ch*sin($angle);
		$hpixels = $ch*cos($angle)+$cw*$slength*sin($angle);
	}
	return ($wpixels,$hpixels);
}

#---------------------------------------------------------------------------------------------------
# Helper function to correct x and y according to setting (left/right/mid)
sub ESPEInk_CorrectXY($$$$$$$$$$) {
	my ($name,$type,$text,$font,$angle,$size,$w,$h,$xo,$yo) = @_;
	my ($wt,$ht);
	my ($x,$y);

	($wt,$ht) = ESPEInk_GetStringPixelWidth($name,$text,$font,$angle,$size) if ($type =~ 'text');
	($wt,$ht) = split("#",$text) if ($type =~ 'icon');
	my $xn = $xo;
	$xn =~ s/^(\<|\||\>)//g;
	$xn =~ s/^(left|mid|right)//g;
	$xn = 0 if (!$xn);
	my $yn = $yo;
	$yn =~ s/^(\<|\||\>)//g;
	$yn =~ s/^(top|mid|bottom)//g;
	$yn = 0 if (!$yn);

	$xn = 0 if (!$xn || ($xn !~ '-?\d+'));
	$yn = 0 if (!$yn || ($yn !~ '-?\d+'));

	$x = $xn;
	$x += ($w - $wt) if ($xo =~ 'right');
	$x += ($w/2 - $wt/2) - $xn if ($xo =~ 'mid');
	$x -= $wt if ($xo =~ '\>');
	$x -= $wt/2 if ($xo =~ '\|');

	$y = $yn;
	$y += ($h - $ht) if ($yo =~ 'bottom');
	$y += ($h/2 - $ht/2) if ($yo =~ 'mid');
	$y -= $ht if ($yo =~ '\>');
	$y -= $ht/2 if ($yo =~ '\|');

	return ($x,$y);
}

#---------------------------------------------------------------------------------------------------
# Check font setting for validity
sub ESPEInk_CheckFontString($) {
	my ($font) = @_;
	my $ret = 0;
	$ret = 1 if ($font && $font =~ '(small|medium|large|giant)');
	$ret = ($font && -e $font) if (!$ret);
	return $ret;
}

#---------------------------------------------------------------------------------------------------
# Check icon setting for validity
sub ESPEInk_CheckIconString($) {
	my ($icon) = @_;
	my $ret = 0;
	my $picdata = undef;

	if ($icon =~ /http(?:s)\:\/\//) { 	# Web link, check if it can be downloaded
		($ret, $picdata) = HttpUtils_BlockingGet({url=>$icon,timeout=>30});
		$ret = defined $picdata;
		return($ret,$icon) if ($ret);
	}

	my $modpath = AttrVal("global","modpath",".");
	my $iconpath = AttrVal("WEB","iconPath","default:fhemSVG:fontawesome:openautomation");
	my @iconpaths = split(":",$iconpath);

	no warnings 'File::Find';

	foreach my $path (@iconpaths) {
		#$path .= "/regular" if ($path eq "fontawesome" && -d $modpath."/"."www/images/".$path."/regular");
		foreach my $extension ("gif","jpg","png","svg") {
			my $foundfile = undef;
			my $search = ".*".$icon.".".$extension;
			find(sub {$foundfile = $File::Find::name if ($_ =~ /$search/);}, $modpath."/"."www/images/".$path);
			$ret = ($icon && defined $foundfile);
			return ($ret,$foundfile) if ($ret);
		}
	}

	return ($ret,"./www/images/default/fhemicon.png");	# nothing found return default fhem icon.
}

#---------------------------------------------------------------------------------------------------
# Add all new attributes (text, position, size, angle, color, font) for a text object 
sub ESPEInk_AddTextAttributes($$) {
	my ($name,$itext) = @_;
	addToDevAttrList($name, "$itext-text") if (!ReadingsVal($name,"$itext-isIcon",0));
	addToDevAttrList($name, "$itext-icon") if (ReadingsVal($name,"$itext-isIcon",0));
	addToDevAttrList($name, "$itext-trigger");
	addToDevAttrList($name, "$itext-x");
	addToDevAttrList($name, "$itext-y");
	addToDevAttrList($name, "$itext-size");
	addToDevAttrList($name, "$itext-angle");
	addToDevAttrList($name, "$itext-color:colorpicker,RGB");
	addToDevAttrList($name, "$itext-font") if (!ReadingsVal($name,"$itext-isIcon",0));
	addToDevAttrList($name, "$itext-linegap") if (!ReadingsVal($name,"$itext-isIcon",0));
	addToDevAttrList($name, "$itext-blockwidth") if (!ReadingsVal($name,"$itext-isIcon",0));
}

#---------------------------------------------------------------------------------------------------
# Check setting consistency if initialization is done
sub ESPEInk_ChecksWhenInitialized() {

	my @ESPEInkModules = devspec2array("TYPE=ESPEInk");
	foreach (@ESPEInkModules) {
		my ($hash) = $defs{$_};
		my $name = $hash->{NAME};
		my $tcount = 0;
		foreach my $reading ( keys %{$hash->{READINGS}}){
			if ($reading =~ '^\d+-text*' || $reading =~ '^\d+-icon*') { # there seems to be a text defined
				my $itext = $reading =~ /^\d+/g;
				ESPEInk_AddTextAttributes($name,$itext);
				$tcount++;
			};
			if ($reading =~ '^\d+-trigger*') { # there seems to be a triger for the text or icon defined
			};
		}
		Log3 $hash, 5, "found $tcount text/icon objects in module $name";
		readingsSingleUpdate( $hash,"deftexts",$tcount,1);
		if ($tcount > 0) {
			delete $ESPEInk_sets{'removeobject'};
			my $list = "";
			for (my $i=1; $i<=$tcount; $i++) {
				$list .= ",".$i;
			}
			$ESPEInk_sets{'removeobject'} = "multiple-strict".$list if ($list ne "");
		}
		ESPEInk_ResetNotifies({hash=>$hash});

		RemoveInternalTimer ($hash);
		InternalTimer(gettimeofday()+ESPEInk_GetSetting($name,"interval"), "ESPEInk_FullUpdate", $hash, 0) if (ESPEInk_GetSetting($name,"interval") > 0);
	}
}

#---------------------------------------------------------------------------------------------------
# allocate the colors defined for the selected EInk display to color table of destination image
sub ESPEInk_AllocateColors($$$){
	my ($hash,$image,$pi) = @_;
	my $length = $ESPEInk_palettes[$pi][0];
	my $index;
	Log3 $hash, 5, "Deallocate ".$image->colorsTotal." color entries";
    for (my $i=0;$i<$image->colorsTotal;$i++)	# remove all previously existing color entries of the image
    {
		$image->colorDeallocate($i)
    }

    for (my $i=1;$i<=$length;$i++)	# allocate new colors according to EInk display capabilities.
    {
		$index = $image->colorAllocate($ESPEInk_palettes[$pi][$i][0],$ESPEInk_palettes[$pi][$i][1],$ESPEInk_palettes[$pi][$i][2]);
		Log3 $hash, 5, "Allocating color values (".$ESPEInk_palettes[$pi][$i][0].",".$ESPEInk_palettes[$pi][$i][1].",".$ESPEInk_palettes[$pi][$i][2].") to index $index";
    }
}

#---------------------------------------------------------------------------------------------------
# Remove all readings related to a text object when removeobject setting is triggered
sub ESPEInk_RemoveTextReadings($$){
	my ($hash,$itext) = @_;
    my $name = $hash->{NAME};
	my $deftexts = ReadingsVal($name,"deftexts",0);
	if ($itext <= $deftexts) {
	
		my $isicon = ReadingsVal($name,"$itext-isIcon",0);

		readingsDelete($hash,$itext."-def");
		readingsDelete($hash,$itext."-text");
		readingsDelete($hash,$itext."-icon");
		readingsDelete($hash,$itext."-trigger");
		readingsDelete($hash,$itext."-x");
		readingsDelete($hash,$itext."-y");
		readingsDelete($hash,$itext."-size");
		readingsDelete($hash,$itext."-angle");
		readingsDelete($hash,$itext."-color");
		readingsDelete($hash,$itext."-font");
		readingsDelete($hash,$itext."-linegap");
		readingsDelete($hash,$itext."-blockwidth");
		readingsDelete($hash,$itext."-isIcon");
		readingsBeginUpdate($hash);

		for (my $i=$itext; $i<$deftexts; $i++) {
			$isicon = ReadingsVal($name,"$i-isIcon",0) if ($i > $itext);

			readingsBulkUpdate($hash,$i."-def",ReadingsVal($name,($i+1)."-def",""));
			readingsBulkUpdate($hash,$i."-text",ReadingsVal($name,($i+1)."-text","")) if (!ReadingsVal($name,($i+1)."-isIcon",0));
			readingsBulkUpdate($hash,$i."-icon",ReadingsVal($name,($i+1)."-icon","")) if (ReadingsVal($name,($i+1)."-isIcon",0));
			readingsBulkUpdate($hash,$i."-trigger",ReadingsVal($name,($i+1)."-trigger","")) if (ReadingsVal($name,($i+1)."-trigger",undef));
			readingsBulkUpdate($hash,$i."-x",ReadingsVal($name,($i+1)."-x",""));
			readingsBulkUpdate($hash,$i."-y",ReadingsVal($name,($i+1)."-y",""));
			readingsBulkUpdate($hash,$i."-size",ReadingsVal($name,($i+1)."-size",""));
			readingsBulkUpdate($hash,$i."-angle",ReadingsVal($name,($i+1)."-angle",""));
			readingsBulkUpdate($hash,$i."-color",ReadingsVal($name,($i+1)."-color",""));
			readingsBulkUpdate($hash,$i."-font",ReadingsVal($name,($i+1)."-font","")) if (ReadingsVal($name,($i+1)."-font",undef));
			readingsBulkUpdate($hash,$i."-linegap",ReadingsVal($name,($i+1)."-linegap","")) if (ReadingsVal($name,($i+1)."-linegap",undef));
			readingsBulkUpdate($hash,$i."-blockwidth",ReadingsVal($name,($i+1)."-blockwidth","")) if (ReadingsVal($name,($i+1)."-blockwidth",undef));

			addToDevAttrList($name, "$i-font") if ($isicon && !ReadingsVal($name,($i+1)."-isIcon",0));
			delFromDevAttrList($name, "$i-font") if (ReadingsVal($name,($i+1)."-isIcon",0));

			readingsBulkUpdate($hash,$i."-isIcon",ReadingsVal($name,($i+1)."-isIcon",""));

			if (defined(AttrVal($name,($i+1).'-text',undef))) {fhem("attr $name $i-text ".AttrVal($name,($i+1)."-text",""))} else {delFromDevAttrList($name, "$i-text")};
			if (defined(AttrVal($name,($i+1).'-icon',undef))) {fhem("attr $name $i-icon ".AttrVal($name,($i+1)."-icon",""))} else {delFromDevAttrList($name, "$i-icon")};
			if (defined(AttrVal($name,($i+1).'-trigger',undef))) {fhem("attr $name $i-trigger ".AttrVal($name,($i+1)."-trigger",""))} else {delFromDevAttrList($name, "$i-trigger")};
			if (defined(AttrVal($name,($i+1).'-x',undef))) {fhem("attr $name $i-x ".AttrVal($name,($i+1)."-x",0))} else {delFromDevAttrList($name, "$i-x")};
			if (defined(AttrVal($name,($i+1).'-y',undef))) {fhem("attr $name $i-y ".AttrVal($name,($i+1)."-y",0))} else {delFromDevAttrList($name, "$i-y")};
			if (defined(AttrVal($name,($i+1).'-size',undef))) {fhem("attr $name $i-size ".AttrVal($name,($i+1)."-size",10))} else {delFromDevAttrList($name, "$i-size")};
			if (defined(AttrVal($name,($i+1).'-angle',undef))) {fhem("attr $name $i-angle ".AttrVal($name,($i+1)."-angle",0))} else {delFromDevAttrList($name, "$i-angle")};
			if (defined(AttrVal($name,($i+1).'-color',undef))) {fhem("attr $name $i-color ".AttrVal($name,($i+1)."-color","000000"))} else {delFromDevAttrList($name, "$i-color")};
			if (defined(AttrVal($name,($i+1).'-font',undef))) {fhem("attr $name $i-font ".AttrVal($name,($i+1)."-font","medium"))} else {delFromDevAttrList($name, "$i-font")};
			if (defined(AttrVal($name,($i+1).'-linegap',undef))) {fhem("attr $name $i-linegap ".AttrVal($name,($i+1)."-linegap",0))} else {delFromDevAttrList($name, "$i-linegap")};
			if (defined(AttrVal($name,($i+1).'-blockwidth',undef))) {fhem("attr $name $i-blockwidth ".AttrVal($name,($i+1)."-blockwidth",0))} else {delFromDevAttrList($name, "$i-blockwidth")};
		}

		readingsBulkUpdate($hash,"deftexts",($deftexts-1));
		readingsEndUpdate($hash,1);

		readingsDelete($hash,"$deftexts-def");
		readingsDelete($hash,"$deftexts-text");
		readingsDelete($hash,"$deftexts-icon");
		readingsDelete($hash,"$deftexts-trigger");
		readingsDelete($hash,"$deftexts-x");
		readingsDelete($hash,"$deftexts-y");
		readingsDelete($hash,"$deftexts-size");
		readingsDelete($hash,"$deftexts-angle");
		readingsDelete($hash,"$deftexts-color");
		readingsDelete($hash,"$deftexts-font");
		readingsDelete($hash,"$deftexts-linegap");
		readingsDelete($hash,"$deftexts-blockwidth");
		readingsDelete($hash,"$deftexts-isIcon");

        delFromDevAttrList($name, "$deftexts-text");
        delFromDevAttrList($name, "$deftexts-icon");
        delFromDevAttrList($name, "$deftexts-trigger");
        delFromDevAttrList($name, "$deftexts-x");
        delFromDevAttrList($name, "$deftexts-y");
        delFromDevAttrList($name, "$deftexts-size");
        delFromDevAttrList($name, "$deftexts-angle");
        delFromDevAttrList($name, "$deftexts-color");
        delFromDevAttrList($name, "$deftexts-font");
        delFromDevAttrList($name, "$deftexts-linegap");
        delFromDevAttrList($name, "$deftexts-blockwidth");

		Log3 $hash, 5, "$name: Removed readings for ".(ReadingsVal($name,"$deftexts-isIcon",0)?"icon":"text");
	}
	
	
}

#---------------------------------------------------------------------------------------------------
# perform Floyd Steinberg dithering (if attribute dithering is set)
sub ESPEInk_Dither($$) {
	my ($image,$pi) = @_;
	my $length = $ESPEInk_palettes[$pi][0];
	my ($w,$h) = $image->getBounds;
	my $pixel;
	my $distance;
	my $indexOpt;
	my $newdist;
	my $error;
	my $thisline=0;
	my $nextline=1;
	my @dary;
	my @errors;

	for (my $ix=0; $ix<$w; $ix++) {$errors[$nextline][$ix][0]=0.0;$errors[$nextline][$ix][1]=0.0;$errors[$nextline][$ix][2]=0.0;}

	for (my $iy=0; $iy<$h; $iy++) {
		$thisline = ($thisline+1)%2;
		$nextline = ($nextline+1)%2;
		for (my $ix=0; $ix<$w; $ix++) {$errors[$nextline][$ix][0]=0.0;$errors[$nextline][$ix][1]=0.0;$errors[$nextline][$ix][2]=0.0;}

		for (my $ix=0; $ix<$w; $ix++) {
			my ($r, $g, $b) =  $image->rgb($image->getPixel($ix,$iy));

			$r += $errors[$thisline][$ix][0];
			$g += $errors[$thisline][$ix][1];
			$b += $errors[$thisline][$ix][2];
			$distance = (abs($r-$ESPEInk_palettes[$pi][1][0]) + abs($g-$ESPEInk_palettes[$pi][1][1]) + abs($b-$ESPEInk_palettes[$pi][1][2]))/3;
			$indexOpt = 1;
			for (my $i=2; $i<=$length; $i++) {
				$newdist = (abs($r-$ESPEInk_palettes[$pi][$i][0]) + abs($g-$ESPEInk_palettes[$pi][$i][1]) + abs($b-$ESPEInk_palettes[$pi][$i][2]))/3;
				if ($newdist < $distance) {
					$distance = $newdist;
					$indexOpt = $i;
				}
			}

			$image->setPixel($ix,$iy,$image->colorClosest($ESPEInk_palettes[$pi][$indexOpt][0],$ESPEInk_palettes[$pi][$indexOpt][1],$ESPEInk_palettes[$pi][$indexOpt][2]));

			$dary[0] = $r - $errors[$thisline][$ix][0] - $ESPEInk_palettes[$pi][$indexOpt][0];
			$dary[1] = $g - $errors[$thisline][$ix][1] - $ESPEInk_palettes[$pi][$indexOpt][1];
			$dary[2] = $b - $errors[$thisline][$ix][2] - $ESPEInk_palettes[$pi][$indexOpt][2];

			if ($ix == 0) {
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix][$i] = $errors[$nextline][$ix][$i] + ($dary[$i]*7.0)/16.0;}
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix+1][$i] = $errors[$nextline][$ix+1][$i] + ($dary[$i]*2.0)/16.0;}
				for (my $i=0; $i<3; $i++) {$errors[$thisline][$ix+1][$i] = $errors[$thisline][$ix+1][$i] + ($dary[$i]*7.0)/16.0;}
			} elsif ($ix == $w-1) {
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix-1][$i] = $errors[$nextline][$ix-1][$i] + ($dary[$i]*7.0)/16.0;}
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix][$i] = $errors[$nextline][$ix][$i] + ($dary[$i]*9.0)/16.0;}
			} else {
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix-1][$i] = $errors[$nextline][$ix-1][$i] + ($dary[$i]*3.0)/16.0;}
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix][$i] = $errors[$nextline][$ix][$i] + ($dary[$i]*5.0)/16.0;}
				for (my $i=0; $i<3; $i++) {$errors[$nextline][$ix+1][$i] = $errors[$nextline][$ix+1][$i] + ($dary[$i]*1.0)/16.0;}
				for (my $i=0; $i<3; $i++) {$errors[$thisline][$ix+1][$i] = $errors[$thisline][$ix+1][$i] + ($dary[$i]*7.0)/16.0;}
			}
		}
	}
}

#---------------------------------------------------------------------------------------------------
# update picture from file to have always the latest version on disk represented
sub ESPEInk_UpdatePicture($$) {
	my ($hash,$filename) = @_;
    my $name = $hash->{NAME};

	if (!open(IMAGE, $filename)) {
	    my $err = "Invalid filename $filename. Must be a readable file.";
	    return $err;
	} else {
		close IMAGE;
		my $rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
		unlink $rootname."/".$hash->{SUBFOLDER}."/".$name."/*.*";			# remove all existing files in directory with device name
		copy($filename,$rootname."/".$hash->{SUBFOLDER}."/".$name);			# local copy of the file for usage in FHEMWEB (display)
		ESPEInk_MakePictureHTML($name,"source_picture",basename($filename));
		return undef;
	}
}
#---------------------------------------------------------------------------------------------------
# generate html code to display picture as reading of device
sub ESPEInk_MakePictureHTML($$$) {
	my ($devname, $reading, $filename) = @_;
    my $hash = $defs{$devname};
	my $filedesc = $filename;
	$filedesc =~ s/\?.*$//g;
	readingsSingleUpdate( $hash,$reading,"<html><img src=/fhem/".$hash->{SUBFOLDER}."/".$devname."/".$filename."?dummy=".rand(1000000)."></img><div>/fhem/".$hash->{SUBFOLDER}."/".$devname."/".$filedesc."</div></html>",1);
}

sub ESPEInk_StoreFile($$$$) {
	my ($name, $fname, $extension, $image) = @_;
	my $rootname;
	my $outfilename;
	$rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
	$outfilename = catfile($rootname,$name,$extension.basename($fname));
	open(IMAGE,">",$outfilename);
	binmode IMAGE;
	print IMAGE $image->png;
	close IMAGE;
}

#---------------------------------------------------------------------------------------------------
# helper function to check attributes and internal values for consistent setting of parameters
sub ESPEInk_GetSetting($$) {
	my ($name, $setting) = @_;
	return defined(AttrVal($name,$setting,undef))?$attr{$name}{$setting}:InternalVal($name,uc $setting,undef);
}

#---------------------------------------------------------------------------------------------------
# Add a text object to the picture
sub ESPEInk_FormatBlockText($$$$$$$) {
	my ($name,$txt,$fnt,$angle,$size,$blockwidth,$th) = @_;
	my $text = $txt;

	if ($blockwidth) {		# insert additional \n if width of text reaches maximum width
		my @words;
		my $xoffset = 0;
		my ($wspc, $ww, $wh);
		my $newline = 1;
		($wspc, $wh) = ESPEInk_GetStringPixelWidth($name," ",$fnt,$angle,$size);
		@words = split(/[ ]/,$text);
		$text = "";
		foreach my $word (@words) {
			($ww, $wh) = ESPEInk_GetStringPixelWidth($name,$word,$fnt,$angle,$size);
			Log3 $defs{$name}, 5, "--->> Width (outer) of $word (lengt ".length($word).") is: $ww, Width of Space is: $wspc, Text offset is: $xoffset";
			if ($word =~ /.*\\n.*/) {
				my $ww2;
				foreach my $wd (split(/[\\n]/,$word)) {
					($ww2, $wh) = ESPEInk_GetStringPixelWidth($name,$wd,$fnt,$angle,$size);
					Log3 $defs{$name}, 5, "--->> Width (inner) of $wd (lengt ".length($wd).") is: $ww2, Width of Space is: $wspc, Text offset is: $xoffset";
					if (length($wd) > 0) {
						if (($xoffset+$ww2) <= $blockwidth) {
							$wd = (($xoffset==0)?"":" ") . $wd;
							$xoffset = $xoffset + $ww2 + $wspc;
							$newline = 0;
						} else {
							$wd = "\\n" . $wd . " " if (!$newline);
							$wd = $wd . "\\n" if ($newline);
							$xoffset = $ww2 + $wspc;
							$newline = 1;
						}
					}
					$xoffset = 0 if (length($wd) == 0);
					$wd = $wd . "\\n" if (length($wd) == 0);
					$text = $text . $wd;
				}
			} else {
				if (($xoffset+$ww) <= $blockwidth) {
					$word = (($newline)?"":" ") . $word;
					$xoffset = $xoffset + $ww + $wspc;
					$newline = 0;
				} else {
					$word = "\\n" . $word . " ";
					# $word = $word . "\\n" if ($newline);
					$xoffset = $ww + $wspc;
					$newline = 1;
				}
				$text = $text . $word;
			}
		}
		Log3 $defs{$name}, 5, "--->> Text is: $text";
	}

	return $text;
}

#---------------------------------------------------------------------------------------------------
# Add a text object to the picture
sub ESPEInk_AddObjects($$) {
	my ($name, $image) = @_;
	my ($r,$g,$b);
	my $color;
	my $font;
	my $deftexts = ReadingsVal($name,"deftexts",0);
	my $angle;
	my $icon_img = undef;
	my $rsvg = undef;
    my $hash = $defs{$name};
	my $rootname;
	my $outfile;

	my $definition = AttrVal($name,"definition",undef);
	my $definitionFile = AttrVal($name,"definitionFile",undef);
	
	if ($definitionFile) {
		my ($error, @content) = FileRead({FileName=>$definitionFile, ForceType=>"file"});
		
		if (!$error) {
			$definition .= "\n" . (join("\n", @content));
		} else {
			Log3 $hash, 1, "Error ($error) reading definition from file $definitionFile";
		}
	}
	
	if ($definition) {	# work on all definitions if definition attribute is defined
		foreach my $line (split(/\n/,$definition)) { # go through the definition line by line
			next if ($line =~ /^\s*\#.*/); # check for comment lines
			my ($type, $text, $x, $y, $size, $ang, $col, $fnt,$linegap,$blockwidth,$docolor);
			$type = undef;
			$text = undef;
			($type, $text, $x, $y, $size, $ang, $col, $fnt, $linegap, $blockwidth) = split("#",$line);
			$linegap = int($linegap) if ($linegap);
			$blockwidth = int($blockwidth) if ($blockwidth);

			$x = 0 if (!$x || (($x !~ '-?\d+')&&($x !~ '(left|mid|right)')));
			$y = 0 if (!$y || (($y !~ '-?\d+')&&($y !~ '(top|mid|bottom)')));
			$size = 10 if (!$size || ($size !~ '-?\d+'));
			$ang = 0 if (!$ang || ($ang !~ '-?\d+'));
			$docolor = $col?1:0;
			$col = "000000" if (!$col || !ESPEInk_CheckColorString($col));
			$fnt = "medium" if (!ESPEInk_CheckFontString($fnt));
			$angle = $ang/180*(4*atan2(1,1));
			$color = $col;

			next if (!defined $type);
			next if (!defined $text);

			if ($type eq "iconreading" || $type eq "textreading") {
				my $eval=0;
				($text,$eval) = split("{",$text);
				my ($device,$reading) = split(':',$text,2);
				$reading = "state" if (!$reading);
				$text = ReadingsVal($device,$reading,'');
				if ($eval) {
					$eval =~ s/\}//g;
					$text = sprintf($eval,ReadingsVal($device,$reading,""));
				}
			}

			if ($type eq "addicon") {
				my ($ret,$path) = ESPEInk_CheckIconString($text);
				next if (!$ret);
			}

			$r= hex(substr($col,0,2));
			$g= hex(substr($col,2,2));
			$b= hex(substr($col,4,2));
			$color = $image->colorResolve($r,$g,$b);

			if ($type eq "addicon" || $type eq "iconreading") {
				my ($ret,$path) = ESPEInk_CheckIconString($text);
				my ($ext) = $path =~ /(\.[^.]+)$/;
				Log3 $defs{$name}, 2, "$name: icon of type 'svg' specified but SVG support not available setting ignored" if ($ext eq '.svg' && !$ESPEInk_has_SVG);
				if ($path =~ /http(?:s)\:\/\//) {	# icon path seems to be a web path, lets download and use data content
					my $picdata = undef;
					($ret, $picdata) = HttpUtils_BlockingGet({url=>$path,timeout=>30});	# load the image data from file on web server with url
					if ($ext eq '.svg' && defined $picdata) {
						$rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root

						my $infile = catfile($rootname,$hash->{SUBFOLDER},$name,'tmp_svg.svg');
						if (!open(RESULT,">",$infile)) {
							Log3 $hash, 1, "File $infile cannot be written";
						} else {
							binmode RESULT;
							print RESULT $picdata;
							close RESULT;
						}

						$outfile = catfile($rootname,$hash->{SUBFOLDER},$name,'tmp_png.png');
						if ($ESPEInk_has_SVG) {
							$rsvg = new Image::LibRSVG();
							$rsvg->convert($infile, $outfile);
							unlink $infile;
						}
						if ($rsvg) {$icon_img = GD::Image->newFromPng($outfile,1);}
					} elsif ($ext eq '.png') {
						$icon_img = GD::Image->newFromPngData($picdata,1);
					} elsif ($ext eq '.gif') {
						$icon_img = GD::Image->newFromGifData($picdata);
					} elsif ($ext eq '.jpg') {
						$icon_img = GD::Image->newFromJpegData($picdata,1);
					}
				} else {	# plain file, just open from file system
					if ($ext eq '.svg') {
						$rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
						$outfile = catfile($rootname,$hash->{SUBFOLDER},$name,'tmp_png.png');
						if ($ESPEInk_has_SVG) {
							$rsvg = new Image::LibRSVG();
							$rsvg->convert($path, $outfile);
						}
						if ($rsvg) {$icon_img = GD::Image->newFromPng($outfile,1);}
					} elsif ($ext eq '.png') {
						$icon_img = GD::Image->newFromPng($path,1);
					} elsif ($ext eq '.gif') {
						$icon_img = GD::Image->newFromGif($path);
					} elsif ($ext eq '.jpg') {
						$icon_img = GD::Image->newFromJpeg($path,1);
					}
				}

				if ($icon_img) {
					my ($sw,$sh) = $icon_img->getBounds;
					my $usedcolors = $icon_img->colorsTotal();
					if ($docolor) {
						for (my $iy=0; $iy<$sh; $iy++) {
						for (my $ix=0; $ix<$sw; $ix++) {
							($r,$g,$b) = $icon_img->rgb($icon_img->getPixel($ix,$iy));	# get color values in source file
							#Log3 $hash, 1, "$r, $g, $b";
							$icon_img->setPixel($ix,$iy,$color) if ($r>0 && $g>0 && $b>0);	# set color to given color if original color is black
						}
						}
					}

					my $srw = abs($sw*cos($angle)+$sh*sin($angle));
					my $srh = abs($sh*cos($angle)+$sw*sin($angle));
					my $icon_img_rot = GD::Image->new($srw,$srh,1);
					$icon_img_rot->alphaBlending(0);
					$icon_img_rot->fill($srw/2,$srh/2,$icon_img_rot->colorAllocateAlpha(0,0,0,127));
					$icon_img_rot->copyRotated($icon_img,$srw/2,$srh/2,0,0,$sw,$sh,$ang);
					my $dh = $size;
					my $dw = $srw*$dh/$srh;
					my ($iw,$ih) = $image->getBounds;
					($x,$y) = ESPEInk_CorrectXY($name,$type,"$dw#$dh",$fnt,$ang,$size,$iw,$ih,$x,$y);
					$image->copyResized($icon_img_rot,$x,$y,0,0,$dw,$dh,$srw,$srh);
				}
			} else {
				$font = gdGiantFont if ($fnt eq "giant");
				$font = gdLargeFont if ($fnt eq "large");
				$font = gdMediumBoldFont if ($fnt eq "medium");
				$font = gdSmallFont if ($fnt eq "small");
				my ($dw,$dh) = $image->getBounds;
				my $ly = $y;
				my ($tw, $th) = ESPEInk_GetStringPixelWidth($name,$text,$fnt,$ang,$size);
				$th += $linegap if ($linegap);

				$text = ESPEInk_FormatBlockText($name,$text,$fnt,$ang,$size,$blockwidth,$th);
				
				foreach my $tline (split(/\\n/,$text)) {
					($x,$y) = ESPEInk_CorrectXY($name,$type,$tline,$fnt,$ang,$size,$dw,$dh,$x,$ly);
					if (!$font) {	#use TTF from file given
						my $font = $fnt;
						my @bounds = $image->stringFT($color,$font,$size,$angle,$x,$size+$y,$tline);
					} else {
						if (($ang < -45) || ($ang > 45)) {
							$image->stringUp($font,$x,$y,$tline,$color);
						} else {
							$image->string($font,$x,$y,$tline,$color);
						}
					}
					$ly += $th;
				}
			}
		}
	}

	for (my $itext=1; $itext<=$deftexts; $itext++) {
		my $docolor = (ReadingsVal($name,"$itext-color",0) ne 0) && (ReadingsVal($name,"$itext-color",0) ne '000000');
		$r= hex(substr(ReadingsVal($name,"$itext-color","000000"),0,2));
		$g= hex(substr(ReadingsVal($name,"$itext-color","000000"),2,2));
		$b= hex(substr(ReadingsVal($name,"$itext-color","000000"),4,2));
		$color = $image->colorResolve($r,$g,$b);
		$angle = ReadingsVal($name,"$itext-angle",0)/180*(4*atan2(1,1));
		if (ReadingsVal($name,"$itext-isIcon",0)) {
			my ($ret,$path) = ESPEInk_CheckIconString(ReadingsVal($name,"$itext-icon",""));
			my ($ext) = $path =~ /(\.[^.]+)$/;
			Log3 $defs{$name}, 2, "$name: icon of type 'svg' specified but SVG support not available setting ignored" if ($ext eq '.svg' && !$ESPEInk_has_SVG);

			if ($path =~ /http(?:s)\:\/\//) {	# icon path seems to be a web path, lets download and use data content
				my $picdata = undef;
				($ret, $picdata) = HttpUtils_BlockingGet({url=>$path,timeout=>30});	# load the image data from file on web server with url
				if ($ext eq '.svg' && defined $picdata) {
					$rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root

					my $infile = catfile($rootname,$hash->{SUBFOLDER},$name,'tmp_svg.svg');
					if (!open(RESULT,">",$infile)) {
						Log3 $hash, 1, "File $infile cannot be written";
					} else {
						binmode RESULT;
						print RESULT $picdata;
						close RESULT;
					}

					$outfile = catfile($rootname,$hash->{SUBFOLDER},$name,'tmp_png.png');
					if ($ESPEInk_has_SVG) {
						$rsvg = new Image::LibRSVG();
						$rsvg->convert($infile, $outfile);
						unlink $infile;
					}
					if ($rsvg) {$icon_img = GD::Image->newFromPng($outfile,1);}
				} elsif ($ext eq '.png') {
					$icon_img = GD::Image->newFromPngData($picdata,1);
				} elsif ($ext eq '.gif') {
					$icon_img = GD::Image->newFromGifData($picdata);
				} elsif ($ext eq '.jpg') {
					$icon_img = GD::Image->newFromJpegData($picdata,1);
				}
			} else {	# plain file, just open from file system
				if ($ext eq '.svg') {
					$rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
					$outfile = catfile($rootname,$hash->{SUBFOLDER},$name,'tmp_png.png');
					if ($ESPEInk_has_SVG) {
						$rsvg = new Image::LibRSVG();
						$rsvg->convert($path, $outfile);
					}
					if ($rsvg) {$icon_img = GD::Image->newFromPng($outfile,1);}
				} elsif ($ext eq '.png') {
					$icon_img = GD::Image->newFromPng($path,1);
				} elsif ($ext eq '.gif') {
					$icon_img = GD::Image->newFromGif($path);
				} elsif ($ext eq '.jpg') {
					$icon_img = GD::Image->newFromJpeg($path,1);
				}
			}

			if ($icon_img) {
				my ($sw,$sh) = $icon_img->getBounds;

				if ($docolor) {
					for (my $iy=0; $iy<$sh; $iy++) {
					for (my $ix=0; $ix<$sw; $ix++) {
						($r,$g,$b) = $icon_img->rgb($icon_img->getPixel($ix,$iy));	# get color values in source file
						$icon_img->setPixel($ix,$iy,$color) if ($r>0 && $g>0 && $b>0);	# set color to given color if original color is black
					}
					}
				}

				my $srw = abs($sw*cos($angle)+$sh*sin($angle));
				my $srh = abs($sh*cos($angle)+$sw*sin($angle));
				my $icon_img_rot = GD::Image->new($srw,$srh,1);
				$icon_img_rot->alphaBlending(0);
				$icon_img_rot->fill($srw/2,$srh/2,$icon_img_rot->colorAllocateAlpha(0,0,0,127));
				$icon_img_rot->copyRotated($icon_img,$srw/2,$srh/2,0,0,$sw,$sh,ReadingsVal($name,"$itext-angle",0));
				my $dh = ReadingsVal($name,"$itext-size",10);
				my $dw = $srw*$dh/$srh;
				my ($iw,$ih) = $image->getBounds;
				my ($x,$y) = ESPEInk_CorrectXY($name,"icon","$dw#$dh",ReadingsVal($name,"$itext-font",""),ReadingsVal($name,"$itext-angle",""),ReadingsVal($name,"$itext-size",""),$iw,$ih,ReadingsVal($name,"$itext-x",0),ReadingsVal($name,"$itext-y",0));
				$image->copyResized($icon_img_rot,$x,$y,0,0,$dw,$dh,$srw,$srh);
			}
		} else {
			$font = undef;
			$font = gdGiantFont if (ReadingsVal($name,"$itext-font","") eq "giant");
			$font = gdLargeFont if (ReadingsVal($name,"$itext-font","") eq "large");
			$font = gdMediumBoldFont if (ReadingsVal($name,"$itext-font","") eq "medium");
			$font = gdSmallFont if (ReadingsVal($name,"$itext-font","") eq "small");
			my ($dw,$dh) = $image->getBounds;
			my $ly = ReadingsVal($name,"$itext-y",0);
			my ($tw, $th) = ESPEInk_GetStringPixelWidth($name,ReadingsVal($name,"$itext-text",""),ReadingsVal($name,"$itext-font","small"),ReadingsVal($name,"$itext-angle",0),ReadingsVal($name,"$itext-size",10));
			$th += int(ReadingsVal($name,"$itext-linegap",0));

			my $text = ESPEInk_FormatBlockText($name,ReadingsVal($name,"$itext-text",""),ReadingsVal($name,"$itext-font","small"),ReadingsVal($name,"$itext-angle",0),ReadingsVal($name,"$itext-size",10),int(ReadingsVal($name,"$itext-blockwidth",0)),$th);
			foreach my $tline (split(/\\n/,$text)) {
				my ($x,$y) = ESPEInk_CorrectXY($name,"text",$tline,ReadingsVal($name,"$itext-font",""),ReadingsVal($name,"$itext-angle",""),ReadingsVal($name,"$itext-size",""),$dw,$dh,ReadingsVal($name,"$itext-x",0),$ly);

				if (!$font) {	#use TTF from file given
					my $fontfile = ReadingsVal($name,"$itext-font","");
					my @bounds = $image->stringFT($color,ReadingsVal($name,"$itext-font",""),ReadingsVal($name,"$itext-size",10),$angle,$x,ReadingsVal($name,"$itext-size",10)+$y,$tline);
				} else {
					if ((ReadingsVal($name,"$itext-angle",0) < -45) || (ReadingsVal($name,"$itext-angle",0) > 45)) {
						$image->stringUp($font,$x,$y,$tline,$color);
					} else {
						$image->string($font,$x,$y,$tline,$color);
					}
				}
				$ly += $th;
			}
		}
	}
}

#---------------------------------------------------------------------------------------------------
# convert the input picture into a picture taking into account capabilities of given eInk module
# if wanted, Floyd-Steinberg-Dithering is performed to better represent pictures with many colors
sub ESPEInk_ConvertDone(@) {
    my ($string) = @_;

    return unless ( defined($string) );

    my ( $name, $upload, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};

    Log3 $hash, 4, "Finished conversion in background".(($upload eq "1")?" doing automatic upload as requested":"");
    $hash->{STATE} = "Finished conversion in background";
    delete( $hash->{helper}{DO_UPLOAD} );
    delete( $hash->{helper}{RUNNING_PID} );
	ESPEInk_MakePictureHTML($name,"result_picture","result.png");
	ESPEInk_Upload($hash) if ($upload eq "1");
}

#---------------------------------------------------------------------------------------------------
# convert the input picture into a picture taking into account capabilities of given eInk module
# if wanted, Floyd-Steinberg-Dithering is performed to better represent pictures with many colors
sub ESPEInk_ConvertAborted(@) {
    my ($hash) = @_;
    delete( $hash->{helper}{DO_UPLOAD} );
    delete( $hash->{helper}{RUNNING_PID} );
    Log3 $hash, 4, "Forked process timed out";
}

#---------------------------------------------------------------------------------------------------
# convert the input picture into a picture taking into account capabilities of given eInk module
# if wanted, Floyd-Steinberg-Dithering is performed to better represent pictures with many colors
sub ESPEInk_Convert(@) {
    my ($hash,$upload) = @_;
    if (defined ($hash->{helper}{RUNNING_PID}))
    {
        BlockingKill($hash->{helper}{RUNNING_PID});
        delete( $hash->{helper}{DO_UPLOAD} );
        delete( $hash->{helper}{RUNNING_PID} );
        Log3 $hash, 4, "Killing old forked process";
    }

    unless (defined ($hash->{helper}{RUNNING_PID}))
    {
	   $hash->{helper}{DO_UPLOAD} = $upload;
       $hash->{helper}{RUNNING_PID} =
               BlockingCall(
               "ESPEInk_DoConvert",      # callback worker task
               $hash,                    # hash of the device and upload trigger
               "ESPEInk_ConvertDone",    # callback result method
               120,                      # timeout seconds
               "ESPEInk_ConvertAborted", # callback for abortion
               $hash );                  # parameter for abortion
       Log3 $hash, 4, "Start forked process to convert output picture";
       return "Starting conversion in background";
    }
    else
    {
       Log3 $hash, 1, "Could not start forked process, old process still running";
    }
}

#---------------------------------------------------------------------------------------------------
# convert the input picture into a picture taking into account capabilities of given eInk module
# if wanted, Floyd-Steinberg-Dithering is performed to better represent pictures with many colors
sub ESPEInk_DoConvert(@) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

	my $srcimage;
	my $srcimage_orig;
	my $dstimage;
	my $fname;
	my $colormode;
	my $convertmode;
	my $devtype;
	my ($r,$g,$b);

	my $w;
	my $h;
	my $dw;
	my $dh;
	my $dx;
	my $dy;
	my $y;
	my $x;
	my $index;
	my $pind;
	my $placement;
	my $scale2fit;
	my $rootname;
	my $outfilename;
	my $ext;
	my @coloroffset;
    my $upload = $hash->{helper}{DO_UPLOAD};

	$fname = ESPEInk_GetSetting($name,"picturefile");
	ESPEInk_UpdatePicture($hash,$fname);
	$colormode = ESPEInk_GetSetting($name,"colormode");
	$convertmode = ESPEInk_GetSetting($name,"convertmode");

    $devtype = ESPEInk_GetSetting($name,"devicetype");
	$dw = AttrVal($name,"width",$ESPEInk_devices{$devtype}{"width"});
	$dh = AttrVal($name,"height",$ESPEInk_devices{$devtype}{"height"});
	$placement = AttrVal($name,"placement","top-left");
	$scale2fit = AttrVal($name,"scale2fit",0);
	@coloroffset = split(";", AttrVal($name,"coloroffset","0;0;0"));

	if ($colormode eq 'monochrome') {
		$pind = 0; 	# use only two colors for output no matter of capabilities
	} else {
		$pind = $ESPEInk_devices{$devtype}{"pindex"};
	}

	if (!open(IMAGE, $fname)) {
		Log3 $hash, 1, "$name: File $fname cannot be opened";
		return "$name|$upload|ESPEInk - Convert: Error opening sourcefile";
	} else {
		close IMAGE;

		GD::Image->trueColor(1);
		($ext) = $fname =~ /(\.[^.]+)$/;
		if ($ext eq '.png') {
			$srcimage_orig = GD::Image->newFromPng($fname,1);
		} elsif ($ext eq '.jpg') {
			$srcimage_orig = GD::Image->newFromJpeg($fname,1);
		} elsif ($ext eq '.gif') {
			$srcimage_orig = GD::Image->newFromGif($fname,1);
		}
		if (!$srcimage_orig) {return "$name|$upload|ESPEInk - Convert: Error opening sourcefile";}

		ESPEInk_AddObjects($name,$srcimage_orig);

		($w,$h) = $srcimage_orig->getBounds;
		if (($w/$h<1) and ($dw/$dh>1) or ($w/$h>1) and ($dw/$dh<1)) { # rotate image 90 deg.
			$srcimage_orig = $srcimage_orig->copyRotate90();
		}

		if ($scale2fit) {
			$srcimage = GD::Image->new($dw,$dh,1);
			$srcimage->copyResized($srcimage_orig,0,0,0,0,$dw,$dh,$w,$h);
		} else {
			$srcimage = $srcimage_orig;
			#$srcimage->copyResized($srcimage_orig,0,0,0,0,$w,$h,$w,$h);
		}

		($w,$h) = $srcimage->getBounds;
		Log3 $hash, 4, "File $fname opened, sizes is $w x $h";

		if ($convertmode ne 'level') {
			ESPEInk_Dither($srcimage,$pind);
		}

		if ($placement eq 'top-left') {
			$dx = AttrVal($name,"x0",0);
			$dy = AttrVal($name,"y0",0);
		} elsif ($placement eq 'top-right') {
			$dx = AttrVal($name,"x0",$w-$dw);
			$dy = AttrVal($name,"y0",0);
		} elsif ($placement eq 'bottom-left') {
			$dx = AttrVal($name,"x0",0);
			$dy = AttrVal($name,"y0",$h-$dh);
		} elsif ($placement eq 'bottom-right') {
			$dx = AttrVal($name,"x0",$w-$dw);
			$dy = AttrVal($name,"y0",$h-$dh);
		}
		
		GD::Image->trueColor(0);
		$dstimage = GD::Image->new($dw,$dh,0);
		if (!$dstimage) {return "$name|$upload|ESPEInk - Convert: Error opening destinationfile";}
		ESPEInk_AllocateColors($hash,$dstimage,$pind);	# allocate colors according to capabilities of selected EInk display

		for (my $iy=0; $iy<$dh; $iy++) {
			$y = $iy + $dy;

			if (($y<0)||($y>=($h))){					# outside of source area, fill destination with alternating black and white in chess board kind
				for (my $i=0;$i<$dw;$i++) {$dstimage->setPixel($i,$iy,(($i+$iy)%2==0)?1:0);}
				next;
			}

			for (my $ix=0; $ix<$dw; $ix++) {
				$x = $ix + $dx;

				if (($x<0)||($x>=($w))){				# outside of source area, fill destination with alternating black and white in chess board kind
					$dstimage->setPixel($ix,$iy,(($ix+$iy)%2==0)?1:0);
					next;
				}
				
				($r,$g,$b) = $srcimage->rgb($srcimage->getPixel($x,$y));														# get color values in source file
				$dstimage->setPixel($ix,$iy,$dstimage->colorClosest($r+$coloroffset[0],$g+$coloroffset[1],$b+$coloroffset[2]));	# set destination color to closest fitting color of eInk display
			}
		}
		$rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
		$outfilename = catfile($rootname,$hash->{SUBFOLDER},$name,"result.png");
		if (!open(RESULT,">",$outfilename)) {
			Log3 $hash, 1, "File $outfilename cannot be written";
		} else {
			binmode RESULT;
			print RESULT $dstimage->png;
			close RESULT;
		}
	}

    return "$name|$upload";
}

#---------------------------------------------------------------------------------------------------
# helper function for coding picture pixels to EInk bit settings
sub ESPEInk_CodePixel2Bits($$$$$) {
	my ($indx,$bits,$comp,$imax,$array) = @_;
	my $v;
	my $x;
	my $str;
	
	if ($bits == 8) {
		if ($comp == -1) {
			$str = "";
			while (($indx < $imax)) {
				$x = 0;
				while ($x < 122) {
					$v = 0;
					for (my $i=0; $i<$bits&&$x<122; $i++,$x++) {
						if ((${$array}[$indx]!=0)) {
							$v|=(128>>$i);
						}
						$indx++;
					}
					$str .= ESPEInk_Byte2String($v);
				}
			}
			return ($indx, $str);
		} else {
			$v = 0;
			for (my $i=0; $i<$bits; $i++) {
				if (($indx<@{$array})&&(${$array}[$indx]!=$comp)) {
					$v|=(128>>$i);
				}
				$indx++;
			}
			return ($indx, ESPEInk_Byte2String($v));
		}
	} elsif ($bits == 16) {
		$v = 0;
		for (my $i=0; $i<$bits; $i+=2) {
			if ($indx<@{$array}) {
				$v|=(${$array}[$indx]<<$i);
			}
			$indx++;
		}
		return ($indx, ESPEInk_Word2String($v));
	}
}

#---------------------------------------------------------------------------------------------------
# helper function for converting a byte value to a string readable by EInk display
sub ESPEInk_Byte2String($) {
	my ($v) = @_;
	return chr(($v & 0xF) + 97).chr((($v >> 4) & 0xF) + 97);
}

#---------------------------------------------------------------------------------------------------
# helper function for converting a 2 byte value to a string readable by EInk display
sub ESPEInk_Word2String($) {
	my ($v) = @_;
	return ESPEInk_Byte2String($v&0xFF).ESPEInk_Byte2String(($v>>8)&0xFF);
}

#---------------------------------------------------------------------------------------------------
# helper function to encode the picture pixels to the right values for the EIknk display
sub ESPEInk_Encode4Upload($$$$) {
	my($param,$bits,$comp,$data) = @_;
	my $i = int($param->{control}{srcindex});
	my $ret = "";
	my $imax;

	if (($i+int($param->{maxulsize})*($bits==8?4:2)) > (@{$data}-1)) {
		$imax = @{$data}-1;
	} else {
		$imax = $i+int($param->{maxulsize})*($bits==8?4:2);
	}
	
	if ($param->{device} == 3) {
		$imax = $i+int($param->{maxulsize})*($bits==8?4:2)-(($param->{board} eq "ESP8266")?366:122);
	}

	my $postdata = "";
	while ($i < $imax) {
		($i, $ret) = ESPEInk_CodePixel2Bits($i,$bits,$comp,$imax,\@{$data});
		$postdata .= $ret;
	}
	return ($i,$postdata.ESPEInk_Word2String(length($postdata))."LOAD");
}

#---------------------------------------------------------------------------------------------------
# callback function for the http calls. Here all upload logic is happening
sub ESPEInk_HTTPCallbackA(@) {
	my ($inparam, $err, @dat) = @_;
	my $devname = $inparam->{devname};
	my $param = $inparam->{$devname};
	my $hash = $param->{hash};
    my $name = $hash->{NAME};
	my $imax;
	my $postdata;
	my $i;
	my $comp;
	my $bits;

	Log3 ($hash, 5, "$name: callback from command $param->{command}, URL $inparam->{url} status code $inparam->{code}");

	my $cparams = {
			url			=> 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command},
    		timeout		=> $param->{control}{timeout},
			method		=> $inparam->{method},
			header		=> $inparam->{header},
			callback	=> $inparam->{callback},
			devname		=> $name
	};

	if ($inparam->{code} != 200 && ($param->{board} eq "ESP8266")) {		# there seemed to be problem with the communication lets try again with the old data.
		$param->{control}{retries} += 1;
		if ($param->{control}{retries} > $param->{control}{maxretries}) {	# respect max retries
			Log3 ($hash, 1, "$name: problems with communication to device, max retries ($param->{control}{maxretries}) reached");
			$hash->{STATE} = "Error uploading image to device, max retries ($param->{control}{maxretries}) reached";
		} else {															# we still have retries, go on with same data
			Log3 ($hash, 3, "$name: problems with communication to device, trying once more ($param->{control}{retries} of $param->{control}{maxretries} done)");
			$cparams->{$name} = $param;
			HttpUtils_NonblockingGet($cparams);
		}
	} else {
		if ($param->{device} == 3) {										# special treatment for this device
			if ($param->{control}{stepindex} == 0) {						# we have different steps for uploading the different colors and closing the upload
				$comp = -1;
				$bits = 8;
				$param->{command} = "LOAD";									# start uploading black channel
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				($param->{control}{srcindex},$param->{data}) = ESPEInk_Encode4Upload($param,$bits,$comp,\@{$param->{outarray}});
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{data}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++ if ($param->{control}{srcindex} >= @{$param->{outarray}});	# complete array has been coded and sent, go to next step
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
				Log3 $hash, 5, "$name: $param->{control}{srcindex}, $param->{control}{stepindex}, ".$param->{data};
			} elsif ($param->{control}{stepindex} == 1) {
				$param->{command} = "SHOW";									# all data uploaded tell device to show uploaded data
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++;
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
			} elsif ($param->{control}{stepindex} == 2) {
				$hash->{STATE} = "Successfully uploaded image to device";
			}
		} elsif (($param->{device} == 0) ||
				 ($param->{device} == 3) ||
				 ($param->{device} == 6) ||
				 ($param->{device} == 7) ||
				 ($param->{device} == 9) ||
				 ($param->{device} == 12) ||
				 ($param->{device} == 16) ||
				 ($param->{device} == 19) ||
				 ($param->{device} == 22)) {								# black and white display
			if ($param->{control}{stepindex} == 0) {						# we have different steps for uploading the different colors and closing the upload
				$comp = 0;
				$bits = 8;
				$param->{command} = "LOAD";									# start uploading black channel
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				($param->{control}{srcindex},$param->{data}) = ESPEInk_Encode4Upload($param,$bits,$comp,\@{$param->{outarray}});
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{data}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++ if ($param->{control}{srcindex} >= @{$param->{outarray}});	# complete array has been coded and sent, go to next step
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
				Log3 $hash, 5, "$name: $param->{control}{srcindex}, $param->{control}{stepindex}, ".$param->{data};
			} elsif ($param->{control}{stepindex} == 1) {
				$param->{command} = "SHOW";								# all data uploaded tell device to show uploaded data
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++;
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
			} elsif ($param->{control}{stepindex} == 2) {
				$hash->{STATE} = "Successfully uploaded image to device";
			}
		} elsif (($param->{device} > 15) && ($param->{device} < 22)) {		# special treatment for bigger displays, upload is done in one step for all colors
			if ($param->{control}{stepindex} == 0) {						# we have different steps for uploading the different colors and closing the upload
				$comp = -1;
				$bits = 16;
				$param->{command} = "LOAD";									# start uploading black channel
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				($param->{control}{srcindex},$param->{data}) = ESPEInk_Encode4Upload($param,$bits,$comp,\@{$param->{outarray}});
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{data}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++ if ($param->{control}{srcindex} >= @{$param->{outarray}});	# complete array has been coded and sent, go to next step
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
				Log3 $hash, 5, "$name: $param->{control}{srcindex}, $param->{control}{stepindex}, ".$param->{data};
			} elsif ($param->{control}{stepindex} == 1) {
				$param->{command} = "SHOW";									# all data uploaded tell device to show uploaded data
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++;
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
			} elsif ($param->{control}{stepindex} == 2) {
				$hash->{STATE} = "Successfully uploaded image to device";
			}
		} else {															# treatment for all smaller color capable displays
			if ($param->{control}{stepindex} == 0) {						# we have different steps for uploading the different colors and closing the upload
				if ($param->{device} == 1 || $param->{device} == 12) {
					$comp = -1;
					$bits = 16;
				} elsif ($param->{device} == 23) {
					$comp = 0;
					$bits = 8;
				} else {
					$comp = 0;
					$bits = 8;
				}
				$param->{command} = "LOAD";									# start uploading black channel
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				($param->{control}{srcindex},$param->{data}) = ESPEInk_Encode4Upload($param,$bits,$comp,\@{$param->{outarray}});
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{data}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++ if ($param->{control}{srcindex} >= @{$param->{outarray}});	# complete array has been coded and sent, go to next step
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
				Log3 $hash, 5, "$name: $param->{control}{srcindex}, $param->{control}{stepindex}, ".$param->{data};
			} elsif ($param->{control}{stepindex} == 1) {
				$param->{control}{srcindex} = 0;							# black channel upload done, tell device that next step starts
				$param->{command} = "NEXT";
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++;
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
				Log3 $hash, 5, "$name: $param->{control}{srcindex}, $param->{control}{stepindex}, ".$param->{data};
			} elsif ($param->{control}{stepindex} == 2) {
				$comp = 3;
				$bits = 8;
				$param->{command} = "LOAD";								# start uploading black channel
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				($param->{control}{srcindex},$param->{data}) = ESPEInk_Encode4Upload($param,$bits,$comp,\@{$param->{outarray}});
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{data}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++ if ($param->{control}{srcindex} >= @{$param->{outarray}});	# complete array has been coded and sent, go to next step
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
				Log3 $hash, 5, "$name: $param->{control}{srcindex}, $param->{control}{stepindex}, ".$param->{data};
			} elsif ($param->{control}{stepindex} == 3) {
				$param->{command} = "SHOW";								# all data uploaded tell device to show uploaded data
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command};
				$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$param->{command}.'_' if ($param->{board} eq "ESP32");
				$param->{data} = '' if ($param->{board} eq "ESP32");
				$param->{control}{stepindex}++;
				$cparams->{$name} = $param;
				$cparams->{data} = $param->{data};
				HttpUtils_NonblockingGet($cparams);
			} elsif ($param->{control}{stepindex} == 4) {
				$hash->{STATE} = "Successfully uploaded image to device";
			}
		}
	}
}

#---------------------------------------------------------------------------------------------------
# initialization of upload and first http call (rest is cared for in the callback function)
sub ESPEInk_PostToDevice($$$$$) {
	my ($hash,$command,$devind,$control,@outarray) = @_;
    my $name = $hash->{NAME};

	my $params = {
			command		=> $command,
			device		=> $devind,
			outarray	=> @outarray,
			board		=> ($command eq "EPDx_")?"ESP32":"ESP8266",
    		hash		=> $hash,
			control		=> $control,
			maxulsize	=> ($command eq "EPDx_")?1000:1500
	};

	my $cparams = {
    		method		=> "POST",
    		header		=> "Content-Type: text/plain\r\nUser-Agent: fhem\r\nAccept: */*",
			data		=> ESPEInk_Byte2String($devind),
			callback	=> \&ESPEInk_HTTPCallbackA,
			devname		=> $name
  	};

	if ($params->{board} eq "ESP32") {
		if ($params->{device} == 3) {											# special treatment for this device
			$params->{command} =~ s/x_/d_/g;
		} else {																# treatment for all smaller color capable displays
			my $subst = chr($params->{device}+97)."_";
			$params->{command} =~ s/x_/$subst/g;
		}
	}

	$cparams->{url} = 'http://'.ESPEInk_GetSetting($name,"url").'/'.$params->{command};
	$cparams->{data} = '' if ($params->{board} eq "ESP32");
	$cparams->{$name} = $params;
	Log3 ($hash, 3, "$name: sending HTTP request to $cparams->{url} with data: $cparams->{data}");
	HttpUtils_NonblockingGet($cparams);
}

#---------------------------------------------------------------------------------------------------
# code converted picture and send it to eInk driver board (and thus to the connected eInk display)
sub ESPEInk_Upload(@) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
	
	my $url = ESPEInk_GetSetting($name,"url"); 
	if (!defined $url) {
		return "Error, missing url. Define url to device first";
	}
	
	if ($hash->{STATE} =~ /Uploading/) {
		Log3 ($hash, 2, "$name: Upload of image currently running, try again later");
		return $hash->{STATE};
	}

	$hash->{STATE} = "Uploading image to device";

	my @outarray;

	my $devtype = ESPEInk_GetSetting($name,"devicetype");
	my $boardtype = ESPEInk_GetSetting($name,"boardtype");
	my $devind = $ESPEInk_devices{$devtype}{"id"};

	my $rootname = $FW_dir; #File::Spec->rel2abs($FW_dir); # get Filename of FHEMWEB root
	my $filename = catfile($rootname,$hash->{SUBFOLDER},$name,"result.png");
	if (!open(RESULT,$filename)) {
		Log3 $hash, 1, "File $filename cannot be opened";
		return "Error opening image file $filename for upload";
	} else {
		close RESULT;
		my $image = GD::Image->newFromPng($filename);
		my ($w,$h) = $image->getBounds;
		my ($r,$g,$b);
		my $i = 0;

		for (my $iy=0; $iy<$h; $iy++) {
			for (my $ix=0; $ix<$w; $ix++) {
				($r,$g,$b) = $image->rgb($image->getPixel($ix,$iy));
				$outarray[$i] = ($r==0&&$g==0)?0:(($r==255&&$g==255)?1:(($r==127&&$g==127)?2:3));	#convert color values to values between 0 and 3
				$i++;
			}
		}
	}

	$ESPEInk_uploadcontrol{"retries"} = 0;									# actual number of retries
	$ESPEInk_uploadcontrol{"maxretries"} = AttrVal($name,"maxretries",3);	# maximum number of retries
	$ESPEInk_uploadcontrol{"timeout"} = AttrVal($name,"timeout",10);		# timout for HTTP calls
	$ESPEInk_uploadcontrol{"stepindex"} = 0;								# step currently performed (for multi color displays each color is transferred separately)
	$ESPEInk_uploadcontrol{"srcindex"} = 0;									# index of source array currently transferred (we might need to split due to the limit on arduino code in data transfer length via HTTP)
	ESPEInk_PostToDevice($hash,($boardtype eq "ESP32")?'EPDx_':'EPD',$devind,\%ESPEInk_uploadcontrol,\@outarray);	# convert data from conversion result in appropriate format and send it to the device via HTTP
	return $hash->{STATE};
}

1;

=pod
=item device
=item summary    Generate output pictures for EInk devices with ESP32 or ESP8266 driver.
=begin html

<a name="ESPEInk"></a>
<h3>ESPEInk</h3>
<ul>
    <i>ESPEInk</i> This module implements the possibility to send pictures generated in FHEM to an raw eInk paper connected to an ESP8266 or ESP32 eInk 
	WLAN driver board from waveshare (see details about the board at <a href="https://www.waveshare.com/wiki/E-Paper_ESP8266_Driver_Board">Wiki ESP8266 Waveshare Driver Board</a> and <a href="https://www.waveshare.com/wiki/E-Paper_ESP32_Driver_Board">Wiki ESP32 Waveshare Driver Board</a>).
	<br>
	The module consists of 2 parts. One is the preparation of the picture to be send to the board. Here a template picture can be defined and additional texts can be added. 
	Furthermore it can be specified how the conversion should be done (e.g. if size of template picture should be automatically fit to eInk size, dithering, color mode or monochrome)
	The second part converts the picture to the right format and sends it to the board and thus changes the display on the eInk paper.
    <br><br>
    <a name="ESPEInkdefine"></a>
    <b>Prerequisites</b>
    <ul>
        <br>
            This module requires an eInk paper raw module from Waveshare (exisiting in different sizes, number of colors and resolutions) 
			and a WLAN driver board (<a href="https://www.waveshare.com/wiki/E-Paper_ESP8266_Driver_Board">Wiki Waveshare Driver Board</a>).
			The driver board needs the installation of an adruino sketch as described in the Wiki (see link before). After this the module together with the 
			eInk display only needs power supply. The data exchange between FHEM and the display is done via WLAN.
			The module further needs installation of the GD library for perl (see installation instructions at <a href="https://metacpan.org/pod/GD">GD for Perl</a> and at <a href="https://metacpan.org/pod/Image::LibRSVG)">Image::LibRSVG for Perl</a>).
    </ul>
    <br>
    
    <a name="ESPEInkdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ESPEInk &lt;picturefile&gt; [url] [interval] [colormode] [convertmode]</code>
        <br><br>
        Example: <code>define myEInk ESPEInk /opt/fhem/www/images/test.png</code>
        <br><br>
        The <code>picturefile</code> parameter must be path to a readable file in the filesystem of FHEM.
		<br><code>[url]</code> is the url of the WLAN driver board (typically an IP address but could also be a Web-URL). This parameter is optional but needed as soon as you want to not 
		only generate the picture but also upload it to the eInk display. For upload it is also necessary to specify the correct device type (default is <code>1.54inch_e-Paper_Module</code> 
		see also attribute <code>devicetype</code>, for a list of all available device types use <code>get devices</code>).
		<br><code>[interval]</code> is a time interval for regular updates of the information to the eInk display. It automatically converts the inputs and uploads the result to the eInk display and 
		defaults to 300 seconds.
		<br><code>[colormode]</code> can be either <code>color</code> or <code>monochrome</code> and specifies if the inputs should be converted to a fitting color picture or if the conversion 
		should be done in monochrome format.
		<br><code>[convertmode]</code> can be either <code>level</code> or <code>dithering</code>. If <code>level</code> is specified, the conversion transforms the given colors to the ones to the 
		closest color the display is capable of (depending on the display type this can be black, red or yellow). When <code>dithering</code> is specified, the conversion performs a Floyd Steinberg 
		dithering to fit the input picture better to the capabilities of the eInk display.
    </ul>
    <br>
    
    <a name="ESPEInkset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; &lt;option&gt; &lt;value&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>addtext</i><br>
                  This option allows to specify a text that should be added to the template picture at any position.
				  <br>The value must be given in the form: <code>text#x#y#size#angle#color#font#linegap#blockwidth</code>
				  <br>where:
				  <br><code>text</code> is the text that should be added. This is the only mandatory part of the value.
				  <br><code>x</code> is the x-position of the lower left corner of the text relative to the lower left corner of the display area
				  <br><code>y</code> is the y-position of the lower left corner of the text relative to the lower left corner of the display area
				  <br><code>size</code> is the size of the text in pixels. This parameter is only used if a TTF font type is specified (see below)
				  <br><code>angle</code> is the rotation angle (counterclockwise) that should be used when drawing the text. In case of not using TTF fonts (see below), the resulting rotation can be only 0 or 90 degrees.
				  <br><code>color</code> is an RGB hex string that specifies the RGB values of the color respectively (e.g. 00FF00 for green)
				  <br><code>font</code> is either one of <code>small</code> <code>medium</code> <code>large</code> <code>giant</code> or a path to a valid TTF font file in the FHEM file system.
				  <br><code>linegap</code> The distance between consecutive lines if blocksetting is used (see blockwidth below) positive values increase the distance negative values reduce the distance.
				  <br><code>blockwidth</code> The width in pixels of the text block generated by the text string. If the string width on the display is higher than the given width in pixels, an automatic linebreak will be added.
				  <br>For each of the specified texts a list of readings and attributes is added to the device. The readings are holding the parameters finally taken for the generation of the output picture. 
				  The attributes allow an easy change of the readings (see details in the description below). Once at least one text is specified, the set option <code>removeobject</code> is added.
				  <br>
			  </li>
              <li><i>addicon</i><br>
                  This option allows to specify an icon that should be added to the template picture at any position.
				  <br>The value must be given in the form: <code>icon#x#y#size#angle#color</code>
				  <br>where:
				  <br><code>icon</code> is the name of the icon that should be added. This is the only mandatory part of the value. Icons can either be specified as fhem icon names (any installed fhem icons are supported), or as url links to web icons
				  <br><code>x</code> is the x-position of the lower left corner of the icon relative to the lower left corner of the display area
				  <br><code>y</code> is the y-position of the lower left corner of the icon relative to the lower left corner of the display area
				  <br><code>size</code> is the size of the icon in pixels. This parameter is only used if a TTF font type is specified (see below)
				  <br><code>angle</code> is the rotation angle (counterclockwise) that should be used when drawing the icon. In case of not using TTF fonts (see below), the resulting rotation can be only 0 or 90 degrees.
				  <br><code>color</code> is an RGB hex string that specifies the RGB values of the color respectively (e.g. 00FF00 for green)
				  <br>For each of the specified icons a list of readings and attributes is added to the device. The readings are holding the parameters finally taken for the generation of the output picture. 
				  The attributes allow an easy change of the readings (see details in the description below). Once at least one icon is specified, the set option <code>removeobject</code> is added.
				  <br>
			  </li>
              <li><i>textreading</i><br>
                  This option allows to specify a device:reading as trigger for adding texts to the template picture at any position.
				  <br>The value must be given in the form: <code>device:reading#x#y#size#angle#color#font#linegap#blockwidth</code>
				  <br>where:
				  <br><code>device:reading</code> specifies a device (and potentially a reading otherwise <code>state</code> will be taken as reading) that should contain the text. This is the only mandatory part of the value.
				  When the internal parameter INTERVAL ist set to 0 (at definition time or through the attribute interval) the change of the reading will directly trigger an update of the result picture and an upload to the device.
				  <br><code>x</code> is the x-position of the lower left corner of the text relative to the lower left corner of the display area
				  <br><code>y</code> is the y-position of the lower left corner of the text relative to the lower left corner of the display area
				  <br><code>size</code> is the size of the text in pixels. This parameter is only used if a TTF font type is specified (see below)
				  <br><code>angle</code> is the rotation angle (counterclockwise) that should be used when drawing the text. In case of not using TTF fonts (see below), the resulting rotation can be only 0 or 90 degrees.
				  <br><code>color</code> is an RGB hex string that specifies the RGB values of the color respectively (e.g. 00FF00 for green)
				  <br><code>font</code> is either one of <code>small</code> <code>medium</code> <code>large</code> <code>giant</code> or a path to a valid TTF font file in the FHEM file system.
				  <br><code>linegap</code> The distance between consecutive lines if blocksetting is used (see blockwidth below) positive values increase the distance negative values reduce the distance.
				  <br><code>blockwidth</code> The width in pixels of the text block generated by the text string. If the string width on the display is higher than the given width in pixels, an automatic linebreak will be added.
				  <br>For each of the specified texts a list of readings and attributes is added to the device. The readings are holding the parameters finally taken for the generation of the output picture. 
				  The attributes allow an easy change of the readings (see details in the description below). Once at least one text is specified, the set option <code>removeobject</code> is added.
			  </li>
              <li><i>iconreading</i><br>
                  This option allows to specify a device:reading as trigger for adding icons to the template picture at any position.
				  <br>The value must be given in the form: <code>device:reading#x#y#size#angle#color</code>
				  <br>where:
				  <br><code>device:reading</code> specifies a device (and potentially a reading otherwise <code>state</code> will be taken as reading) that should contain the icons names (see possible icon names at "addicon" option). This is the only mandatory part of the value.
				  When the internal parameter INTERVAL ist set to 0 (at definition time or through the attribute interval) the change of the reading will directly trigger an update of the result picture and an upload to the device.
				  <br><code>x</code> is the x-position of the lower left corner of the icon relative to the lower left corner of the display area
				  <br><code>y</code> is the y-position of the lower left corner of the icon relative to the lower left corner of the display area
				  <br><code>size</code> is the size of the icon in pixels. This parameter is only used if a TTF font type is specified (see below)
				  <br><code>angle</code> is the rotation angle (counterclockwise) that should be used when drawing the icon. In case of not using TTF fonts (see below), the resulting rotation can be only 0 or 90 degrees.
				  <br><code>color</code> is an RGB hex string that specifies the RGB values of the color respectively (e.g. 00FF00 for green)
				  <br><code>font</code> is either one of <code>small</code> <code>medium</code> <code>large</code> <code>giant</code> or a path to a valid TTF font file in the FHEM file system.
				  <br>For each of the specified icons a list of readings and attributes is added to the device. The readings are holding the parameters finally taken for the generation of the output picture. 
				  The attributes allow an easy change of the readings (see details in the description below). Once at least one icon is specified, the set option <code>removeobject</code> is added.
			  </li>
              <li><i>convert</i><br>
                  With this option the conversion can be triggered. Whenever a conversion is triggered, the resulting picture is added as reading result_picture to the device (or an existing reading is changed). Conversion is done "non-blocking" in the backround so that FHEM remains accessible.
			  </li>
              <li><i>removeobject</i><br>
                  With this option existing text definitions can be removed. The value for this option is a comma separated list of integer numbers refering to the index of the respective texts to be deleted. 
				  This option is only available if at least one text has been added to the device with <code>set addtext or set addicon</code>.
			  </li>
              <li><i>opload</i><br>
                  Uploads the current version of the result picture (result from most recent conversion step) to the eInk display device for display.
			  </li>
        </ul>
    </ul>
    <br>

    <a name="ESPEInkget"></a>
    <b>Get</b><br>
    <ul>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Currently the only supported get option is <code>get devices</code>. This will display a list of all available device types in a popup window.
        the get command.
    </ul>
    <br>
    
    <a name="ESPEInkreading"></a>
    <b>Readings</b>
    <ul>
        The following readings are generated by the module:
        <br><br>
        Readings:
        <ul>
            <li><i>source_picture</i><br>
                Displays the given picture template specified at the definition of a device or given by attribute <code>picturefile</code>.
            </li>
            <li><i>result_picture</i><br>
                Displays the result of the most recent conversion once set convert has been issued the first time.
            </li>
            <li><i>deftexts</i><br>
                The number of text attributes defined to be added to the template picture when doing the conversion.
            </li>
            <li><i>[0-n]-text</i><br>
                The text specified for a given text object. [0-n] is an integer number and refers to the index of the text.
            </li>
            <li><i>[0-n]-icon</i><br>
                The icon specified for a given icon object. [0-n] is an integer number and refers to the index of the icon.
            </li>
            <li><i>[0-n]-x</i><br>
                The x-position of the lower left corner of the text relative to the lower left corner of the display area.
            </li>
            <li><i>[0-n]-y</i><br>
                The y-position of the lower left corner of the text relative to the lower left corner of the display area.
            </li>
            <li><i>[0-n]-size</i><br>
                The size of the text in pixels. This parameter is only used if a TTF font type is specified (see below).
            </li>
            <li><i>[0-n]-angle</i><br>
                The rotation angle (degrees counterclockwise) that will be used when drawing the text. In case of not using TTF fonts (see below), the resulting rotation can be only 0 or 90 degrees.
            </li>
            <li><i>[0-n]-color</i><br>
                An RGB hex string that tells the respective RGB values of the  color used for displaying the text (e.g. 00FF00 for green).
            </li>
            <li><i>[0-n]-font</i><br>
                Either one of <code>small</code> <code>medium</code> <code>large</code> <code>giant</code> or a path to a valid TTF font file in the FHEM file system specifying the font to be used when displaying the text.
            </li>
            <li><i>[0-n]-linegap</i><br>
                The distance between consecutive lines if blocksetting is used (see blockwidth below) positive values increase the distance negative values reduce the distance
            </li>
            <li><i>[0-n]-blockwidth</i><br>
                The width in pixels of the text block generated by the text string. If the string width on the display is higher than the given width in pixels, an automatic linebreak will be added
            </li>
            <li><i>[0-n]-trigger</i><br>
                The triggering condition of the object if the object is related to areading (see set textreading and set iconreading).
            </li>
            <li><i>[0-n]-def</i><br>
                The initial definition of the object. This is used to reset to inital settings for color, font etc. when attributes are removed.
            </li>
            <li><i>[0-n]-isIcon</i><br>
                Internal setting for marking entry as icon or text.
            </li>
        </ul>
    </ul>
    <br>

    <a name="ESPEInkattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about 
        the attr command. In addition to the standard attributes the following device specific attributes are existing.
        <br><br>
        Attributes:
        <ul>
            <li><i>picturefile</i><br>
				Set the picture template. This parameter must be a path to a readable file in the filesystem of FHEM
            </li>
            <li><i>url</i><br>
				The url of the WLAN driver board the eInk display is connected to (typically an IP address but could also be a Web-URL)
            </li>
            <li><i>definition</i><br>
				This is an alternative to using the set addtext/addicon/textreadin/iconreading command. The attribute contains a list of defintions separated by newline.
				The syntax of the defintion is the same as in the reading <i>[0-n]-def</i>. It contains the command (addtext or addicon or textreading or iconreading) followed by '#' and then the same defintion values as statet in set (addtext ...) above.
				Lines starting with a <code>#</code> are ignored and treated as comment lines. Example: <code>addtext#Hello#10#10#12#0#000000#giant</code>
            </li>
            <li><i>definitionFile</i><br>
				This is another alternative to using the set addtext/addicon/textreadin/iconreading command. The attribute holdes the name of a text file containing a list of defintions separated by newline.
				The syntax of the defintion is the same as in the reading <i>[0-n]-def</i>. It contains the command (addtext or addicon or textreading or iconreading) followed by '#' and then the same defintion values as statet in set (addtext ...) above.
				Lines starting with a <code>#</code> are ignored and treated as comment lines. Example: <code>addtext#Hello#10#10#12#0#000000#giant</code>
            </li>
            <li><i>interval</i><br>
				The time interval for regular updates of the information to the eInk display. The device automatically converts the inputs and uploads the result to the eInk display in this interval.
				If this value is set to 0 there will be automatical updates in case a triggering device is specified (see set textreading). Otherwise 0 means no automatic updates.
            </li>
            <li><i>boardtype</i><br>
				The type of driver board to be used. Currently ESP8266 and ESP32 driver boards are supported.
            </li>
            <li><i>devicetype</i><br>
				The device type to be used. Refer to <code>get devices</code> for a list of available devices.
            </li>
            <li><i>colomode</i><br>
				Can be either <code>color</code> or <code>monochrome</code> and specifies if the inputs should be converted to a fitting color picture or 
				if the conversion should be done in monochrome format.
            </li>
            <li><i>convertmode</i><br>
				Can be either <code>level</code> or <code>dithering</code>. If <code>level</code> is specified, the conversion transforms the given colors to the ones to the 
				closest color the display is capable of (depending on the display type this can be black, red or yellow). When <code>dithering</code> is specified, the conversion performs a Floyd Steinberg 
				dithering to fit the input picture better to the capabilities of the eInk display.
            </li>
            <li><i>width</i><br>
				The width of the result picture. Is normally taken from the devicetype default settings. Should be only used for non predefined devices.
            </li>
            <li><i>height</i><br>
				The height of the result picture. Is normally taken from the devicetype default settings. Should be only used for non predefined devices.
            </li>
            <li><i>x0</i><br>
				An x-offset for the placement of the source picture into the result picture during conversion. Reference is the lower left corner of the result.
            </li>
            <li><i>y0</i><br>
				An y-offset for the placement of the source picture into the result picture during conversion. Reference is the lower left corner of the result.
            </li>
            <li><i>placement</i><br>
				Tells the conversion algorithm where to place the source picture in the result picture if there are different widths and heights. Can be one of 
				<code>top-left</code> <code>top-right</code> <code>bottom-left</code> <code>bottom-right</code>.
            </li>
            <li><i>scale2fit</i><br>
				If set to 1 the source picture is scaled to fit into the result picture in x and y directions.
            </li>
            <li><i>coloroffset</i><br>
				Provides a possibility for changing the mapping of source colors to result colors. Given in the form <code>r;g;b</code>.
            </li>
            <li><i>maxretries</i><br>
				Set the maximum number of retries for sending data to the WLAN display driver of the eInk display. Whenever the sending of a certain data package is not successful, sending is repeated until succes or number of maxretries is reached. Default is 3.
            </li>
			<br>The following attributes are only available for the defined text objects to be added to the result picture. There is one set of attributes for each defined texts starting with the respective text index before the -<br><br>
            <li><i>[0-n]-text</i><br>
                The text specified for a given text object. [0-n] is an integer number and refers to the index of the text.
            </li>
            <li><i>[0-n]-icon</i><br>
                The icon name or url specified for a given icon object. [0-n] is an integer number and refers to the index of the text.
            </li>
            <li><i>[0-n]-x</i><br>
                The x-position of the lower left corner of the text relative to the lower left corner of the display area.
            </li>
            <li><i>[0-n]-y</i><br>
                The y-position of the lower left corner of the text relative to the lower left corner of the display area.
            </li>
            <li><i>[0-n]-size</i><br>
                The size of the text in pixels. This parameter is only used if a TTF font type is specified (see below).
            </li>
            <li><i>[0-n]-angle</i><br>
                The rotation angle (degrees counterclockwise) that will be used when drawing the text. In case of not using TTF fonts (see below), the resulting rotation can be only 0 or 90 degrees.
            </li>
            <li><i>[0-n]-color</i><br>
                An RGB hex string that tells the respective RGB values of the  color used for displaying the text (e.g. 00FF00 for green).
            </li>
            <li><i>[0-n]-font</i><br>
                Either one of <code>small</code> <code>medium</code> <code>large</code> <code>giant</code> or a path to a valid TTF font file in the FHEM file system specifying the font to be used when displaying the text.
            </li>
            <li><i>[0-n]-linegap</i><br>
                The distance between consecutive lines if blocksetting is used (see blockwidth below) positive values increase the distance negative values reduce the distance
            </li>
            <li><i>[0-n]-blockwidth</i><br>
                The width in pixels of the text block generated by the text string. If the string width on the display is higher than the given width in pixels, an automatic linebreak will be added
            </li>
        </ul>
    </ul>
</ul>

=end html

=cut