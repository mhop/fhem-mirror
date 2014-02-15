#########################################################################
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
#	Changelog:
#
#	2013-12-25	initial version
#	2013-12-29	modified to use non blocking HTTP
#	2014-1-1	modified to use attr instead of set to define internal parameters
#	2014-1-6	extended error handling and added documentation	
#	2014-1-15	added readingsExpr to allow some computation on raw values before put in readings
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

#
# lists of Set and Get Options for this module
# so far this is not used 

my %HTTPMOD_sets = (  
);

my %HTTPMOD_gets = (  
);


#
# FHEM module intitialisation
# defines the functions to be called from FHEM
#########################################################################
sub HTTPMOD_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}   = "HTTPMOD_Define";
	$hash->{UndefFn} = "HTTPMOD_Undef";
	#$hash->{SetFn}   = "HTTPMOD_Set";
	#$hash->{GetFn}   = "HTTPMOD_Get";
	$hash->{AttrFn}  = "HTTPMOD_Attr";
	$hash->{AttrList} =
	  "do_not_notify:1,0 " . 
	  "readingsName.* " .
	  "readingsRegex.* " .
	  "readingsExpr.* " .
	  "requestHeader.* " .
	  "requestData.* " .
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

	my $name 	= $a[0];
	my $url 	= $a[2];
	my $inter	= 300;
	
	if(int(@a) == 4) { 
		$inter = $a[3]; 
		if ($inter < 5) {
			return "interval too small, please use something > 5, default is 300";
		}
	}

	$hash->{url} 		= $url;
	$hash->{Interval}	= $inter;
	
	# for non blocking HTTP Get
	$hash->{callback} = \&HTTPMOD_Read;
	$hash->{timeout}  = 2;
	#$hash->{loglevel} = 3;
	
	# initial request after 2 secs, there timer is set to interval for further update
	InternalTimer(gettimeofday()+2, "HTTPMOD_GetUpdate", $hash, 0);	

	return undef;
}

#
# undefine command when device is deleted
#########################################################################
sub HTTPMOD_Undef($$)
{                     
	my ( $hash, $arg ) = @_;       
	DevIo_CloseDev($hash);         
	RemoveInternalTimer($hash);    
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

	# Attributes are readingsRegexp.*, requestHeader.* and requestData.*

	# requestHeader and requestData need no special treatment here
	# however they have to be added to $hash later so HttpUtils 
	# an pick them up. Maybe later versions of HttpUtils could 
	# also pick up attributes?

	# readingsRegex.* needs validation though.
	# ... to be implemented later here ...
	# each readingsRegexX defines a pair of Reading and Regex
	
	if ($cmd eq "set") {
		if ($aName =~ "readingsRegex") {
			eval { qr/$aVal/ };
			if ($@) {
				Log3 $name, 3, "HTTPOD: Invalid regex in attr $name $aName $aVal: $@";
				return "Invalid Regex $aVal";
			}
		} elsif ($aName =~ "readingsExpr") {
			my $val = 1;
			eval $aVal;
			if ($@) {
				Log3 $name, 3, "HTTPOD: Invalid Expression in attr $name $aName $aVal: $@";
				return "Invalid Expression $aVal";
			}
		}
	}
	
	return undef;
}



#
# SET command
# currently not used
#########################################################################
sub HTTPMOD_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set HTTPMOD\" needs at least an argument" if ( @a < 2 );
	
	# @a is an array with DeviceName, SetName, Rest of Set Line
	my $name = shift @a;
	my $attr = shift @a;
	my $arg = join("", @a);
	
	if(!defined($HTTPMOD_sets{$attr})) {
		my @cList = keys %HTTPMOD_sets;
		return "Unknown argument $attr, choose one of " . join(" ", @cList);
	} 

	return undef;
}

#
# GET command
# currently not used
#########################################################################
sub HTTPMOD_Get($@)
{
	my ( $hash, @a ) = @_;
	return "\"get HTTPMOD\" needs at least an argument" if ( @a < 2 );

	# @a is an array with DeviceName and GetName
	my $name = shift @a;
	my $attr = shift @a;
	
	if(!defined($HTTPMOD_gets{$attr})) {
		my @cList = keys %HTTPMOD_gets;
		return "Unknown argument $attr, choose one of " . join(" ", @cList);
	}
	
	return undef;
}



#
# request new data from device
###################################
sub HTTPMOD_GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	InternalTimer(gettimeofday()+$hash->{Interval}, "HTTPMOD_GetUpdate", $hash, 1);
	Log3 $name, 4, "HTTPMOD: GetUpdate called, hash = $hash, name = $name";
	
	if ( $hash->{url} eq "none" ) {
		return 0;
	}

	my $header = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestHeader/, keys %{$attr{$name}})));
	if (length $header > 0) {
		$hash->{header} = $header;
	} else {
		delete $hash->{header};
	}

	my $data = join ("\r\n", map ($attr{$name}{$_}, sort grep (/requestData/, keys %{$attr{$name}})));
	if (length $data > 0) {
		$hash->{data} = $data;
	} else {
		delete $hash->{data};
	}
	
	HttpUtils_NonblockingGet($hash);
}

#
# read / parse new data from device
# - callback for non blocking HTTP 
###################################
sub HTTPMOD_Read($$$)
{
	my ($hash, $err, $buffer) = @_;
	my $name = $hash->{NAME};
	
	if ($err) {
		Log3 $name, 3, "HTTPMOD got error in callback: $err";
		return;
	}
	Log3 $name, 5, "HTTPMOD: Callback called: Hash: $hash, Name: $name, buffer: $buffer\r\n";

	my $msg = "";
	readingsBeginUpdate($hash);
	foreach my $a (sort (grep (/readingsName/, keys %{$attr{$name}}))) {
		$a =~ /readingsName(.*)/;
		if (defined ($attr{$name}{'readingsName' . $1}) && 
		    defined ($attr{$name}{'readingsRegex' . $1})) {
			my $reading = $attr{$name}{'readingsName' . $1};
			my $regex   = $attr{$name}{'readingsRegex' . $1};
			my $expr	= "";
			if (defined ($attr{$name}{'readingsExpr' . $1})) {
				$expr = $attr{$name}{'readingsExpr' . $1};
			}
			Log3 $name, 5, "HTTPMOD: Trying to extract Reading $reading with regex /$regex/...";
			if ($buffer =~ /$regex/) {
				my $val = $1;
				if ($expr) {
					$val = eval $expr;
					Log3 $name, 5, "HTTPMOD: change value for Reading $reading with Expr $expr from $1 to $val";
				}
				Log3 $name, 5, "HTTPMOD: Set Reading $reading to $val";
				readingsBulkUpdate( $hash, $reading, $val );
			} else {
				if ($msg) {
					$msg .= ", $reading";
				} else {
					$msg = "$reading";
				}
			}
		} else {
			Log3 $name, 3, "HTTPMOD: inconsitant attributes for $a";
		}
	}
	readingsEndUpdate( $hash, 1 );
	if ($msg) {
		Log3 $name, 3, "HTTPMOD: Response didn't match Reading(s) $msg";
		Log3 $name, 4, "HTTPMOD: response was $buffer";
	}
	return;
	
}


1;


=pod
=begin html

<a name="HTTPMOD"></a>
<h3>HTTPMOD</h3>

<ul>
	This module provides a generic way to retrieve information from devices with an HTTP Interface and store them in Readings. 
	It queries a given URL with Headers and data defined by attributes. 
	From the HTTP Response it extracts Readings named in attributes using Regexes also defined by attributes.
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
		pairs of <code>attr readingNameX</code> and <code>attr readingRegexX</code> to define which readings you want to extract from the HTTP
		response and how to extract them.
		<br><br>
		Example for a PoolManager 5:<br><br>
		<ul><code>
			define PM HTTPMOD http://MyPoolManager/cgi-bin/webgui.fcgi 60<br>
			attr PM readingsName1 PH<br>
			attr PM readingsName2 CL<br>
			attr PM readingsName3 TEMP<br>
			attr PM readingsRegex1 34.4001.value":[ \t]+"([\d\.]+)"<br>
			attr PM readingsRegex2 34.4008.value":[ \t]+"([\d\.]+)"<br>
			attr PM readingsRegex3 34.4033.value":[ \t]+"([\d\.]+)"<br>
			attr PM requestData {"get" :["34.4001.value" ,"34.4008.value" ,"34.4033.value", "14.16601.value", "14.16602.value"]}<br>
			attr PM requestHeader1 Content-Type: application/json<br>
			attr PM requestHeader2 Accept: */*<br>
			attr PM stateFormat {sprintf("%.1f Grad, PH %.1f, %.1f mg/l Chlor", ReadingsVal($name,"TEMP",0), ReadingsVal($name,"PH",0), ReadingsVal($name,"CL",0))}<br>
		</code></ul>
		If you need to do some calculation on a raw value before it is used as a reading you can define the attribute <code>readingsExprX</code> 
		which can use the raw value from the variable $val
		<br><br>
		Example:<br><br>
		<ul><code>
			attr PM readingsExpr3 $val * 10<br>
		</code></ul>
	</ul>
	<br>

	<a name="HTTPMODset"></a>
	<b>Set-Commands</b><br>
	<ul>
		none
	</ul>
	<br>
	<a name="HTTPMODget"></a>
	<b>Get-Commands</b><br>
	<ul>
		none
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
		<li><b>readingsName.*</b></li>
			the name of a reading to extract with the corresponding readingRegex<br>
		<li><b>readingsRegex.*</b></li>
			defines the regex to be used for extracting the reading. The value to extract should be in a sub expression e.g. ([\d\.]+) in the above example <br>
		<li><b>readingsExpr.*</b></li>
			defines an expression that is used in an eval to compute the readings value. The raw value will be in the variable $val.
			
	</ul>
	<br>
	<b>Author's notes</b><br><br>
	<ul>
		<li>If you don't know which URLs, headers or POST data your web GUI uses, you might try a local proxy like <a href=http://portswigger.net/burp/>BurpSuite</a> to track requests and responses </li>
	</ul>
</ul>

=end html
=cut
