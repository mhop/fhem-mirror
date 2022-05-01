# $Id$
####################################################################################################
#
#	12_OilFox.pm
#
#	Copyright: Stephan Eisler
#	Email: stephan@eisler.de 
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package FHEM::OilFox;

use strict;
use warnings;
use Time::Local;
use JSON;
use HttpUtils;
use Blocking;
use Data::Dumper;
use GPUtils qw(GP_Import);

use constant API => "https://api.oilfox.io/";

BEGIN {
    GP_Import(
        qw(
          readingFnAttributes
          readingsSingleUpdate
          readingsBeginUpdate
          readingsEndUpdate
          readingsBulkUpdate
          deviceEvents
          defs
          HttpUtils_NonblockingGet
          modules
          attr
          AttrVal
          InternalTimer
          RemoveInternalTimer
          Log3
          strftime)
    );
}

sub _Export {
    no strict qw/refs/;
    my $pkg  = caller(0);
    my $main = $pkg;
    $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
    foreach (@_) {
        *{ $main . $_ } = *{ $pkg . '::' . $_ };
    }
}

_Export(
    qw(
      Initialize
      )
);



sub Initialize($) {
    my ($hash) = @_;
    
    $hash->{SetFn}      = "FHEM::OilFox::Set";
    $hash->{DefFn}      = "FHEM::OilFox::Define";
    $hash->{UndefFn}    = "FHEM::OilFox::Undef";
    $hash->{NotifyFn} 	= "FHEM::OilFox::Notify";
    $hash->{AttrFn}     = "FHEM::OilFox::Attr";
    $hash->{AttrList}   = "email " .
                          "password " .
                          "oilfox " .
                          "interval " .
                          $readingFnAttributes;
}

sub Define($$){
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );
    my $name = $a[0];

    return "too few parameters: define <NAME> OilFox" if( @a < 1 ) ;

    %$hash = (%$hash,
        NOTIFYDEV => "global,$name",
        OilFox => { 
            CONNECTED				            => 0,
            oilfox                              => 0,
            oilfox_id                           => '',
            token					            => '',
            oilfox_name				            => '',
            oilfox_hwid				            => '',
            oilfox_tankVolume 		            => 0,
            oilfox_metering_value               => 0,
            oilfox_metering_fillingPercentage   => 0,
            oilfox_metering_liters              => 0,
            oilfox_metering_currentOilHeight    => 0,
            oilfox_metering_battery             => 0,
            oilfox_currentMeteringAt            => '',
            oilfox_nextMeteringAt               => '',
            oilfox_daysReach                    => 0,
            oilfox_quantityUnit                 => '',
            email 				                => '',
            password 				            => '',
            interval    			            => 300,
            access_token_expires 				=> time(),
            validationError                     => '',
        },
    );
    
    $attr{$name}{room} = "OilFox" if( !defined( $attr{$name}{room} ) );
    
    CONNECTED($hash,'initialized');

    DoUpdate($hash);

    return undef;

}

sub Set($@) {
    my ($hash,@a) = @_;
    return "\"set $hash->{NAME}\" needs at least an argument" if ( @a < 2 );
    my ($name,$setName,$setVal,$setVal2,$setVal3) = @a;

    Log3 $name, 3, "$name: set called with $setName " . ($setVal ? $setVal : "") if ($setName ne "?");

    if (CONNECTED($hash) eq 'disabled' && $setName !~ /clear/) {
        return "Unknown argument $setName, choose one of clear:all,readings";
        Log3 $name, 3, "$name: set called with $setName but device is disabled!" if ($setName ne "?");
        return undef;
    }
    
    if ($setName !~ /update/) {
        return "Unknown argument $setName, choose one of update";
    } else {
        Log3 $name, 3, "$name: set $setName";
    }

    if ($setName eq 'update') {
        RemoveInternalTimer($hash);
        DoUpdate($hash);
    }
    
    return undef;
}

sub Notify($$) {
    
    my ($hash,$dev) = @_;
    my ($name) = ($hash->{NAME});
    
    if (AttrVal($name, "disable", 0)) {
        Log3 $name, 5, "Device '$name' is disabled, do nothing...";
        CONNECTED($hash,'disabled');
        return undef;
    }

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);
    
    Log3 $name, 5, "OilFox ($name) - Notify: " . Dumper $events;

    $hash->{OilFox}->{updateStartTime} = time();    
    
    if ( $devtype eq 'Global') {
        if (
            grep /^INITIALIZED$/,@{$events}
            or grep /^REREADCFG$/,@{$events}
            or grep /^DEFINED.$name$/,@{$events}
            or grep /^MODIFIED.$name$/,@{$events}
        ) {
            APIAuth($hash);
        }
    } 
    
    if ( $devtype eq 'OilFox') {
        if ( grep(/^state:.authenticated$/, @{$events}) ) {
            get($hash);
        }
        
        if ( grep(/^state:.disconnected$/, @{$events}) ) {
            Log3 $name, 3, "Reconnecting...";
            APIAuth($hash);
        }
        
        if ( grep(/^state:.connected$/, @{$events}) ) {
            DoUpdate($hash);
        }
    }
            
    return undef;
}

sub Attr(@) {
    
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
        
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disable", 1 );
            Log3 $name, 3, "$name - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "$name - enabled";
        }
    }
    
    elsif( $attrName eq "email" ) {
        if( $cmd eq "set" ) {
            $hash->{OilFox}->{email} = $attrVal;
            Log3 $name, 3, "$name - email set to " . $hash->{OilFox}->{email};
        }
    }

    elsif( $attrName eq "password" ) {
        if( $cmd eq "set" ) {
            $hash->{OilFox}->{password} = $attrVal;
            Log3 $name, 3, "$name - password set to " . $hash->{OilFox}->{password};	
        }
    }
    
    elsif( $attrName eq "oilfox" ) {
        if( $cmd eq "set" ) {
            $hash->{OilFox}->{oilfox} = $attrVal;
            Log3 $name, 3, "$name - oilfox set to " . $hash->{OilFox}->{oilfox};	
        }
        elsif( $cmd eq "del" ) {
            $hash->{OilFox}->{oilfox} = 0;
            Log3 $name, 3, "$name - deleted oilfox and set to default: 0";
        }
    }

    elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            return "Interval must be greater than 0"
            unless($attrVal > 0);
            $hash->{OilFox}->{interval} = $attrVal;
            RemoveInternalTimer($hash);
            InternalTimer( time() + $hash->{OilFox}->{interval}, "FHEM::OilFox::DoUpdate", $hash);
            Log3 $name, 3, "$name - set interval: $attrVal";
        }

        elsif( $cmd eq "del" ) {
            $hash->{OilFox}->{interval} = 300;
            RemoveInternalTimer($hash);
            InternalTimer( time() + $hash->{OilFox}->{interval}, "FHEM::OilFox::DoUpdate", $hash);
            Log3 $name, 3, "$name - deleted interval and set to default: 300";
        }
    }

    return undef;
}


sub Undef($$){
    my ( $hash, $arg )  = @_;
    my $name            = $hash->{NAME};
    my $deviceId        = $hash->{DEVICEID};
    delete $modules{OilFox}{defptr}{$deviceId};
    RemoveInternalTimer($hash);
    return undef;
}


sub APIAuth($) {
    my ($hash, $def) = @_;
    my $name = $hash->{NAME};
    
    my $email = $hash->{OilFox}->{email};
    my $password = $hash->{OilFox}->{password};
    
    my $header = "Content-Type: application/json\r\nAccept: application/json";
    my $json = '{
                    "email" : "' . $email. '",
                    "password" : "' . $password. '"
                }';

    HttpUtils_NonblockingGet({
        url        	=> API . "customer-api/v1/login",
        timeout    	=> 5,
        hash       	=> $hash,
        method     	=> "POST",
        header     	=> $header,  
        data 		=> $json,
        callback   	=> \&APIAuthResponse,
    });  
    
}

sub APIAuthResponse($) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        CONNECTED($hash,'error');
        Log3 $name, 2, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
   
        my $result = eval { decode_json($data) };
        if ($@) {
            Log3( $name, 2, " - JSON error while request: $@");
            return;
        }
            
        if ($result->{errors}) {
            CONNECTED($hash,'error');
            Log3 $name, 2, "Error: " . $result->{errors}[0]->{detail};
            
        } else {
            Log3 $name, 2, "$data"; 

            $hash->{OilFox}->{token} = $result->{access_token};
            $hash->{OilFox}->{expires} = time() + 300; # TODO Read exp from JWT
            
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,'token',$hash->{OilFox}->{token} );
            
            my $expire_date = strftime("%Y-%m-%d %H:%M:%S", localtime($hash->{OilFox}->{expires}));
            readingsBulkUpdate($hash,'access_token_expires',$expire_date );
            readingsEndUpdate($hash, 1);
            
            CONNECTED($hash,'authenticated');

        }
        
    }

}

sub CONNECTED($@) {
    my ($hash,$set) = @_;
    if ($set) {
       $hash->{OilFox}->{CONNECTED} = $set;
       %{$hash->{updateDispatch}} = ();
       if (!defined($hash->{READINGS}->{state}->{VAL}) || $hash->{READINGS}->{state}->{VAL} ne $set) {
               readingsSingleUpdate($hash,"state",$set,1);
       }
       return undef;
    } else {
        if ($hash->{OilFox}->{CONNECTED} eq 'disabled') {
            return 'disabled';
        }
        elsif ($hash->{OilFox}->{CONNECTED} eq 'connected') {
            return 1;
        } else {
            return 0;
        }
    }
}

sub DoUpdate($) {
    my ($hash) = @_;
    my ($name) = $hash->{NAME};

    Log3 $name, 5, "doUpdate() called.";

    if (CONNECTED($hash) eq "disabled") {
        Log3 $name, 3, "$name - Device is disabled.";
        return undef;
    }

    if (time() >= $hash->{OilFox}->{expires} ) {
        Log3 $name, 2, "LOGIN TOKEN MISSING OR EXPIRED";
        CONNECTED($hash,'disconnected');

    }
    elsif ($hash->{OilFox}->{CONNECTED} eq 'connected') {
        Log3 $name, 4, "Update with device: " . $hash->{OilFox}->{oilfox_hwid} . " Interval:". $hash->{OilFox}->{interval};
        get($hash);
        InternalTimer( time() + $hash->{OilFox}->{interval}, "FHEM::OilFox::DoUpdate", $hash);
    } 

}

sub get($) {
    my ($hash) = @_;
    my ($name) = $hash->{NAME};

    my $token = $hash->{OilFox}->{token};
    my $header = "Content-Type: application/json\r\nAccept: application/json\r\nAuthorization: Bearer " . $token;

    HttpUtils_NonblockingGet({
        url        	=> API .  "customer-api/v1/device",
        timeout    	=> 5,
        hash       	=> $hash,
        method     	=> "GET",
        header     	=> $header,  
        callback   	=> \&getResponse,
    });  
    
    return undef;
}

sub getResponse($) {
    
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        Log3 $name, 2, "error while requesting ".$param->{url}." - $err";     
                                           
    } elsif($data ne "") {
        
        if ($data eq '{"errorCode":401}') {
            Log3 $name, 2, "Please register OilFox first";
            $hash->{OilFox}->{oilfox_hwid} = "none";

            CONNECTED($hash,'connected');

        } else {

            Log3 $name, 5, "OilFox(s) found"; 			
            Log3 $name, 5, $data; 
            
            my $result = eval { decode_json($data) };
            if ($@) {
                Log3( $name, 2, " - JSON error while request: $@");
                return;
            }	
                    
            my $oilfox = $hash->{OilFox}->{oilfox};
            Log3 $name, 5, $result->{'items'}->[$oilfox]->{'hwid'};
            
            my $myoilfox = $result->{'items'}->[$oilfox];
            $hash->{OilFox}->{oilfox_hwid} = $myoilfox->{'hwid'};
            $hash->{OilFox}->{oilfox_currentMeteringAt} = $myoilfox->{'currentMeteringAt'};
            $hash->{OilFox}->{oilfox_nextMeteringAt} = $myoilfox->{'nextMeteringAt'};
            $hash->{OilFox}->{oilfox_daysReach} = $myoilfox->{'daysReach'};
            $hash->{OilFox}->{oilfox_metering_fillingPercentage} = $myoilfox->{'fillLevelPercent'};
            $hash->{OilFox}->{oilfox_metering_liters} = $myoilfox->{'fillLevelQuantity'};
            $hash->{OilFox}->{oilfox_metering_battery} = $myoilfox->{'batteryLevel'};
            $hash->{OilFox}->{oilfox_quantityUnit} = $myoilfox->{'quantityUnit'};
            $hash->{OilFox}->{validationError} = $myoilfox->{'validationError'};
       
            CONNECTED($hash,'connected');

        }
        
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "oilfox_hwid", $hash->{OilFox}->{oilfox_hwid});
        readingsBulkUpdate($hash, "oilfox_currentMeteringAt", $hash->{OilFox}->{oilfox_currentMeteringAt});
        readingsBulkUpdate($hash, "oilfox_nextMeteringAt", $hash->{OilFox}->{oilfox_nextMeteringAt});
        readingsBulkUpdate($hash, "oilfox_daysReach", $hash->{OilFox}->{oilfox_daysReach});
        readingsBulkUpdate($hash, "oilfox_metering_fillingPercentage", $hash->{OilFox}->{oilfox_metering_fillingPercentage});
        readingsBulkUpdate($hash, "oilfox_metering_liters", $hash->{OilFox}->{oilfox_metering_liters});
        readingsBulkUpdate($hash, "oilfox_metering_battery", $hash->{OilFox}->{oilfox_metering_battery});
        readingsBulkUpdate($hash, "oilfox_quantityUnit", $hash->{OilFox}->{oilfox_quantityUnit});
        readingsBulkUpdate($hash, "validationError", $hash->{OilFox}->{validationError});
        readingsEndUpdate($hash, 1);
         
    }	
    
    return undef;

}

1;

=pod
=item device
=item summary    support for OilFox
=begin html

<a name="OilFox"></a>
<h3>OilFox</h3>
<ul>
	<u><b>Requirements</b></u>
  	<br><br>
	<ul>
		<li>This module allows the communication between the Oilfox Cloud and FHEM.</li>
  	</ul>
	<br>
	
	<a name="OilFoxDefine"></a>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; OilFox</code>
		<br><br>
		Example:
		<ul><br>
			<code>define myOilFox OilFox<br>
			attr myOilFox email YOUR_EMAIL<br>
			attr myOilFox password YOUR_PASSWORD
			</code><br>
		</ul>
		<br><br>
		You must set both attributes <b>email</b> and <b>password</b>. These are the same that you use to login via the OilFox App.
	</ul>
	<br>
	

	<a name="OilFoxAttributes"></a>
	<b>Attributes</b>
	<ul>
		<li>username - Email that is used in OilFox App</li>
		<li>password - Password that is used in OilFox App</li>
	</ul>
	<br>
	
	<b>Optional attributes</b>
	<ul>
		<li>oilfox - ID of OilFox, if more that one is registered. Default: 0</li>
		<li>interval - Time in seconds that is used to get new data from OilFox Cloud. Default: 300</li>
	</ul>
	<br>
	
	<a name="OilFoxReadings"></a>
	<b>Readings</b>
	<ul>
		<li>access_token_expires - date when session of OilFox Cloud expires</li>
		<li>oilfox_hwid - Id of the OilFox</li>
        <li>oilfox_name - Name of the OilFox</li>
        <li>oilfox_daysReach - Estimated days until the storage runs empty</li>
        <li>oilfox_tankVolume - Tank Volume in liters</li>
		<li>oilfox_metering_battery - enum of the battery level</li>
            <ul>
            <li>FULL - Full battery level</li>
            <li>GOOD - Good battery level</li>
            <li>MEDIUM - Medium battery level</li>
            <li>WARNING - Low battery level</li>
            <li>CRITICAL - Critical battery level</li>
            </ul>
		<li>oilfox_metering_value - Tank Value</li>
		<li>oilfox_metering_fillingPercentage - Tank filling Percentage</li>
		<li>oilfox_metering_liters - Tank filling liters</li>
        <li>oilfox_metering_currentOilHeight - Tank current Oil Height</li>
        <li>oilfox_currentMeteringAt - Timestamp of measurement</li>
        <li>oilfox_nextMeteringAt - Timestamp of next measurement</li>
        <li>validationError - enum with errors regarding the measurement</li>
            <ul>
            <li>NO_METERING - No measurement yet</li>
            <li>EMPTY_METERING - Incorrect Measurement</li>
            <li>NO_EXTRACTED_VALUE - No fill level detected</li>
            <li>SENSOR_CONFIG - Faulty measurement</li>
            <li>MISSING_STORAGE_CONFIG - Storage configuration missing</li>
            <li>INVALID_STORAGE_CONFIG - Incorrect storage configuration</li>
            <li>DISTANCE_TOO_SHORT - Measured distance too small</li>
            <li>ABOVE_STORAGE_MAX - Storage full</li>
            <li>BELOW_STORAGE_MIN - Calculated filling level implausible</li>
            </ul>
	</ul>
</ul>

=end html
