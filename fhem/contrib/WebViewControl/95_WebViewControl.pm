################################################################################
# 95_webViewControl.pm
# Modul for FHEM
#
# Modul for communication between WebViewControl Android App and FHEM
#
# contributed by Dirk Hoffmann 01/2013
# $Id:
#
################################################################################

package main;

use Data::Dumper;    # for debugging only

use strict;
use warnings;
use URI::Escape;

use vars qw {%data %attr %defs %modules $FW_RET}; #supress errors in Eclipse EPIC

use constant {
	webViewControl_Version => '0.5.1_beta',
};

#########################
# Forward declaration
sub webViewControl_Initialize($);		# Initialize
sub webViewControl_Define($$);			# define <name> WEBVIEWCONTROL
sub webViewControl_Undef($$);			# delete
sub webViewControl_modifyJsInclude($);	# include js parts
sub webViewControl_Set($@);				# set
sub webViewControl_Get($@);				# get
sub webViewControl_Cgi();				# analyze and parse URL
sub webViewControl_Attr(@);

#########################
# Global variables
my $fhemUrl = '/webviewcontrol' ;

my %sets = (
	'screenBrightness'	=> 'screenBrightness', # slider,1,1,100',
	'volume'			=> 'volume', # slider,1,1,100',	
	'keepScreenOn'		=> 'keepScreenOn',
	'toastMessage'		=> 'toastMessage',
	'reload'			=> 'reload',
	'audioPlay'			=> 'audioPlay',
	'audioStop'			=> 'audioStop',
	'ttsSay'			=> 'ttsSay',
	'voiceRec'			=> 'voiceRec',
	'newUrl'			=> 'newUrl',	
	'reload'			=> 'reload',	
);
	
my %gets = (
	'powerLevel'				=> 1,
	'powerPlugged'				=> 1,
	'voiceRecognitionLastError'	=> 1,
	'voiceRecognitionLastResult'=> 1,
);

my $FW_encoding="UTF-8";		 # like in FHEMWEB: encoding hardcoded

################################################################################
# Implements Initialize function
#
# @param	hash	$hash	hash of device addressed
#
################################################################################
sub webViewControl_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'webViewControl_Define';
	$hash->{UndefFn}  = 'webViewControl_Undef';
	$hash->{SetFn}    = 'webViewControl_Set';
	$hash->{GetFn}    = 'webViewControl_Get';
	$hash->{AttrFn}   = "webViewControl_Attr";

	$hash->{AttrList} = 'loglevel:0,1,2,3,4,5,6 model userJsFile userCssFile '
	                  . $readingFnAttributes;

	# CGI
	$data{FWEXT}{$fhemUrl}{FUNC} = 'webViewControl_Cgi';
}

################################################################################
# Implements DefFn function
#
# @param	hash	$hash	hash of device addressed
# @param	string	$def	definition string
#
# @return	string
#
################################################################################
sub webViewControl_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	my $name = $hash->{NAME};
	return "wrong syntax: define <name> WEBVIEWCONTROL APP-ID" if int(@a)!=3;

	$hash->{appID} = $a[2];
	$modules{webViewControl}{defptr}{$name} = $hash;									  

	webViewControl_modifyJsInclude($hash);

	$hash->{VERSION} = webViewControl_Version;

	return undef;
}

#############################
sub webViewControl_Undef($$) {
	my ($hash, $name) = @_;
  
	delete($modules{webViewControl}{defptr}{$name});
	webViewControl_modifyJsInclude($hash);

  return undef;
}

sub webViewControl_Attr (@) {
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	if ($attr eq 'userJsFile' || $attr eq 'userCssFile') {
		$attr{$name}{$attr} = $val;
		webViewControl_modifyJsInclude($hash);
	}

	return undef;
}

sub webViewControl_modifyJsInclude($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my @appsArray;
	foreach my $appName (keys %{ $modules{webViewControl}{defptr} } ) {
		push(@appsArray, '\'' . $modules{webViewControl}{defptr}{$appName}->{appID} . '\': \'' . $appName . '\'');
	}

	my $vars = 'var wvcDevices = {' . join(', ', @appsArray) . '}';
	my $userJs = AttrVal($name, 'userJsFile', '');
	$userJs = $userJs ? '<script type="text/javascript" src="/fhem/pgm2/' . $userJs . '"></script>' : '';

	my $userCss = AttrVal($name, 'userCssFile', '');
	if ($userCss) {
		$vars.= '; var wvcUserCssFile="' . $userCss . '"';  
	}

	$data{FWEXT}{$fhemUrl}{SCRIPT} = 'cordova-2.3.0.js"></script>' .
									 '<script type="text/javascript" src="/fhem/pgm2/webviewcontrol.js"></script>' .
									 $userJs .
									 '<script type="text/javascript">' . $vars . '</script>' .
									 '<script type="text/javascript" charset="UTF-8';
}

###################################
sub webViewControl_Set($@) {
	my ($hash, @a) = @_;
	my $setArgs = join(' ', sort values %sets);
 	my $name = shift @a;

	if (int(@a) == 1 && $a[0] eq '?') {
		my %localSets = %sets;
		$localSets{screenBrightness}.=':slider,1,1,255';
		$localSets{volume}.=':slider,0,1,15';
		my $setArgs = join(' ', sort values %localSets);
		return $setArgs;	
	}

	if ((int(@a) < 1) || (!defined $sets{$a[0]}) ) {
		return 'Please specify one of following set value: ' . $setArgs;
	}

	my $cmd = $a[0];

	if (! (($sets{$cmd} eq 'reload') || ($sets{$cmd} eq 'audioStop')) ) {
		if ($sets{$cmd} eq 'toastMessage' && (int(@a)) < 2) {
			return 'Please input a text for toastMessage';

		} elsif ($sets{$cmd} eq 'keepScreenOn') {
			if ($a[1] ne 'on' && $a[1] ne 'off') {
				return 'keepScreenOn needs on of off';
			} else {
				$a[1] = ($a[1] eq 'on') ? 'true' : 'false'; 
			}
			
		} elsif ($sets{$cmd} eq 'screenBrightness' && (int($a[1]) < 1 || int($a[1]) > 255)) {
			return 'screenBrightness needs value from 1 to 255';

		} elsif ($sets{$cmd} eq 'volume' && (int($a[1]) < 0 || int($a[1]) > 15)) {
			return 'volume needs value from 0 to 15';

		} elsif ($sets{$cmd} eq 'audioPlay' && (int(@a)) < 2 ) {
			return 'Please input a url where Audio to play.';

		} elsif ($sets{$cmd} eq 'ttsSay' && (int(@a)) < 2 ) {
			return 'Please input a text to say.';

		} elsif ($sets{$cmd} eq 'voiceRec' && ($a[1] ne 'start' && $a[1] ne 'stop')) {
			return 'voiceRec must set to start or stop';

		} elsif ($sets{$cmd} eq 'newUrl') {
			if ((int(@a)) < 2 ) {
				return 'Please input a url.';
			} else {
				shift(@a);
				my $v = uri_escape(join(' ', @a));
				@a = ($cmd, $v);
			}
		}
	}
	
	my $v = join(' ', @a);
	$hash->{CHANGED}[0] = $v;
	$hash->{STATE} = $v;
	$hash->{lastCmd} = $v;
	$hash->{READINGS}{state}{TIME} = TimeNow();
	$hash->{READINGS}{state}{VAL} = $v;

	return undef;
}

sub webViewControl_Get($@) {
	my ($hash, @a) = @_;

	return ('argument missing, usage is <attribute>') if(@a!=2);

	if(!$gets{$a[1]}) {
		return $a[1] . 'Not supported by get. Supported attributes: ' . join(' ', keys %gets) ;
	}

	my $retVal;
	if ($hash->{READINGS}{$a[1]}{VAL}) {
		$retVal = $hash->{READINGS}{$a[1]}{VAL};
	} else {
		$retVal = $a[1] . ' not yet set';
	}
	
	return $retVal;
}

##################
# Answer requests for webviewcontrol url for set some readings
sub webViewControl_Cgi() {
	my ($htmlarg) = @_;         #URL

	$htmlarg =~ s/^\///;

	my @htmlpart = ();
	@htmlpart = split("\\?", $htmlarg) if ($htmlarg);  #split URL by ? 

	if ($htmlpart[1]) {
		$htmlpart[1] =~ s,^[?/],,;
		
		my @states = ();
		my $name = undef;
		my %readings = ();
		my $timeNow		= TimeNow();

		foreach my $pv (split("&", $htmlpart[1])) {		#per each URL-section devided by &
			$pv =~ s/\+/ /g;
			$pv =~ s/%(..)/chr(hex($1))/ge;
			my ($p,$v) = split("=",$pv, 2);				#$p = parameter, $v = value
			$p =~ s/[\r]\n/\\\n/g;
			$v =~ s/[\r]\n/\\\n/g;
			
			if ($p eq 'id') {
				$name = $v;
			} else {
				$readings{$p} = $v;
				push(@states, $p . '=' . $v);
			}
		}

		if ($modules{webViewControl}{defptr}{$name}) {
			my $state = join(', ', @states);
			my $hash = $modules{webViewControl}{defptr}{$name};

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "state", $state);

			foreach my $reading (keys %readings) {
				readingsBulkUpdate($hash, $reading, $readings{$reading});
			}

			readingsEndUpdate($hash, 1);
		}
	}

	return ("text/html; charset=$FW_encoding", $FW_RET);	# $FW_RET composed by FW_pO, FP_pH etc
}

1;

=pod
=begin html

<a name="WebViewControl"></a>
<h3>WebViewControl</h3>
<ul>
	WebViewCountrol ist the interface for the android APP WebviewControl
  <br><br>

</ul>

=end html
=cut
