###############################################################################
# 
# Developed with Kate
#
#  (c) 2016 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################


package main;

use strict;
use warnings;
use JSON;
#use Time::HiRes qw(gettimeofday);
use HttpUtils;

my $version = "0.2.1";
my $bridgeAPI = "1.0.2";



my %lockActions = (
    'unlock'                => 1,
    'lock'                  => 2,
    'unlatch'               => 3,
    'locknGo'               => 4,
    'locknGoWithUnlatch'    => 5
);


sub NUKIBridge_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     = "NUKIBridge_Read";
    $hash->{WriteFn}    = "NUKIBridge_Read";
    $hash->{Clients}    = ":NUKIDevice:";

    # Consumer
    $hash->{SetFn}      = "NUKIBridge_Set";
    $hash->{DefFn}	= "NUKIBridge_Define";
    $hash->{UndefFn}	= "NUKIBridge_Undef";
    $hash->{AttrFn}	= "NUKIBridge_Attr";
    $hash->{AttrList} 	= "interval ".
                          "disable:1 ".
                          $readingFnAttributes;


    foreach my $d(sort keys %{$modules{NUKIBridge}{defptr}}) {
	my $hash = $modules{NUKIBridge}{defptr}{$d};
	$hash->{VERSION} 	= $version;
    }
}

sub NUKIBridge_Read($@) {

  my ($hash,$chash,$name,$path,$lockAction,$nukiId)= @_;
  NUKIBridge_Call($hash,$chash,$path,$lockAction,$nukiId );
  
}

sub NUKIBridge_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    

    return "too few parameters: define <name> NUKIBridge <HOST> <TOKEN>" if( @a != 4 );
    


    my $name    	= $a[0];
    my $host    	= $a[2];
    my $token           = $a[3];
    my $port		= 8080;
    my $interval  	= 60;

    $hash->{HOST} 	= $host;
    $hash->{PORT} 	= $port;
    $hash->{TOKEN} 	= $token;
    $hash->{INTERVAL} 	= $interval;
    $hash->{VERSION} 	= $version;
    


    Log3 $name, 3, "NUKIBridge ($name) - defined with host $host on port $port, Token $token";

    $attr{$name}{room} = "NUKI" if( !defined( $attr{$name}{room} ) );
    readingsSingleUpdate($hash, 'state', 'Initialized', 1 );
    
    RemoveInternalTimer($hash);
    
    if( $init_done ) {
        NUKIBridge_Get($hash) if( ($hash->{HOST}) and ($hash->{TOKEN}) );
        #NUKIBridge_GetCheckBridgeAlive($hash) if( ($hash->{HOST}) and ($hash->{TOKEN}) );
    } else {
        InternalTimer( gettimeofday()+15, "NUKIBridge_Get", $hash, 0 ) if( ($hash->{HOST}) and ($hash->{TOKEN}) );
    }

    $modules{NUKIBridge}{defptr}{$hash->{HOST}} = $hash;
    
    return undef;
}

sub NUKIBridge_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    RemoveInternalTimer( $hash );
    
    delete $modules{NUKIBridge}{defptr}{$hash->{HOST}};
    
    return undef;
}

sub NUKIBridge_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    if( $attrName eq "disable" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal eq "0" ) {
		RemoveInternalTimer( $hash );
		InternalTimer( gettimeofday()+2, "NUKIBridge_GetCheckBridgeAlive", $hash, 0 );
		readingsSingleUpdate($hash, 'state', 'Initialized', 1 );
		Log3 $name, 3, "NUKIBridge ($name) - enabled";
	    } else {
		RemoveInternalTimer( $hash );
		readingsSingleUpdate($hash, 'state', 'disabled', 1 );
		Log3 $name, 3, "NUKIBridge ($name) - disabled";
            }
            
        } else {
	    RemoveInternalTimer( $hash );
	    InternalTimer( gettimeofday()+2, "NUKIBridge_GetCheckBridgeAlive", $hash, 0 );
	    readingsSingleUpdate($hash, 'state', 'Initialized', 1 );
	    Log3 $name, 3, "NUKIBridge ($name) - enabled";
        }
    }
    
    if( $attrName eq "interval" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal < 30 ) {
		Log3 $name, 3, "NUKIBridge ($name) - interval too small, please use something > 30 (sec), default is 60 (sec)";
		return "interval too small, please use something > 30 (sec), default is 60 (sec)";
	    } else {
		$hash->{INTERVAL} = $attrVal;
		Log3 $name, 3, "NUKIBridge ($name) - set interval to $attrVal";
	    }
	}
	elsif( $cmd eq "del" ) {
	    $hash->{INTERVAL} = 60;
	    Log3 $name, 3, "NUKIBridge ($name) - set interval to default";
	
	} else {
	    if( $cmd eq "set" ) {
		$attr{$name}{$attrName} = $attrVal;
		Log3 $name, 3, "NUKIBridge ($name) - $attrName : $attrVal";
	    }
	}
    }
    
    return undef;
}

sub NUKIBridge_Set($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;

    
    if($cmd eq 'autocreate') {
        return "usage: autocreate" if( @args != 0 );

        NUKIBridge_Get($hash);

        return undef;

    } elsif($cmd eq 'statusRequest') {
    
        NUKIBridge_GetCheckBridgeAlive($hash);
        
        return undef;
        
    } elsif($cmd eq 'other2') {

    } else {
        my $list = "statusRequest:noArg autocreate:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

}

sub NUKIBridge_Get($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    RemoveInternalTimer($hash);
    
    NUKIBridge_Call($hash,$hash,"list",undef,undef) if( !IsDisabled($name) );
    NUKIBridge_GetCheckBridgeAlive($hash);
    
    Log3 $name, 4, "NUKIBridge ($name) - Call NUKIBridge_Get" if( !IsDisabled($name) );

    return 1;
}

sub NUKIBridge_GetCheckBridgeAlive($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    RemoveInternalTimer($hash);
    
    if( !IsDisabled($name) ) {

        NUKIBridge_Call($hash,$hash,"list",undef,undef,1);
    
        InternalTimer( gettimeofday()+$hash->{INTERVAL}, "NUKIBridge_GetCheckBridgeAlive", $hash, 1 );
        Log3 $name, 4, "NUKIBridge ($name) - Call InternalTimer for NUKIBridge_GetCheckBridgeAlive";
    }
    
    return 1;
}

sub NUKIBridge_Call($$$$$;$) {

    my ($hash,$chash,$path,$lockAction,$nukiId,$alive) = @_;
    
    my $name    =   $hash->{NAME};
    my $host    =   $hash->{HOST};
    my $port    =   $hash->{PORT};
    my $token   =   $hash->{TOKEN};
    
    $alive = 0 if( !defined($alive) );
    
    
    my $uri = "http://" . $hash->{HOST} . ":" . $port;
    $uri .= "/" . $path if( defined $path);
    $uri .= "?token=" . $token if( defined($token) );
    $uri .= "&action=" . $lockActions{$lockAction} if( defined($lockAction) );
    $uri .= "&nukiId=" . $nukiId if( defined($nukiId) );


    HttpUtils_NonblockingGet(
	{
	    url        => $uri,
	    timeout    => 10,
	    hash       => $hash,
	    chash      => $chash,
	    endpoint   => $path,
	    alive      => $alive,
	    method     => "GET",
	    doTrigger  => 1,
	    noshutdown => 1,
	    callback   => \&NUKIBridge_Dispatch,
	}
    );
    
    Log3 $name, 4, "NUKIBridge ($name) - Send HTTP POST with URL $uri";

    #return undef;      # beim Aufruf aus dem logischen Modul kam immer erst ein Fehler, deshalb auskommentiert
}

sub NUKIBridge_Dispatch($$$) {

    my ( $param, $err, $json ) = @_;
    my $hash = $param->{hash};
    my $doTrigger = $param->{doTrigger};
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    

    readingsBeginUpdate($hash);
    
    if( defined( $err ) ) {

	if( $err ne "" and $param->{endpoint} eq "list" and $param->{alive} eq 1 ) {
            
            readingsBulkUpdate( $hash, "state", "not connected");
            readingsBulkUpdate( $hash, "lastError", $err );
            
            Log3 $name, 4, "NUKIBridge ($name) - Bridge ist offline";
            readingsEndUpdate( $hash, 1 );
            return;
	} 
	
	elsif ( $err ne "" ) {
	
            readingsBulkUpdate( $hash, "lastError", $err );
            Log3 $name, 4, "NUKIBridge ($name) - error while requesting: $err";
            readingsEndUpdate( $hash, 1 );
            return $err;
	}
    }

    if( $json eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
    
        readingsBulkUpdate( $hash, "lastError", "Internal error, " .$param->{code} );
	Log3 $name, 4, "NUKIBridge ($name) - received http code " .$param->{code}." without any data after requesting";

	readingsEndUpdate( $hash, 1 );
	return "received http code ".$param->{code}." without any data after requesting";
    }

    if( ( $json =~ /Error/i ) and exists( $param->{code} ) ) {    
        
        readingsBulkUpdate( $hash, "lastError", "invalid API token" ) if( $param->{code} eq 401 );
        readingsBulkUpdate( $hash, "lastError", "action is undefined" ) if( $param->{code} eq 400 and $hash == $param->{chash} );
        
        
        ###### Fehler bei Antwort auf Anfrage eines logischen Devices ######
        NUKIDevice_Parse($param->{chash},$param->{code}) if( $param->{code} eq 404 );
        NUKIDevice_Parse($param->{chash},$param->{code}) if( $param->{code} eq 400 and $hash != $param->{chash} );       
        
        
	Log3 $name, 4, "NUKIBridge ($name) - invalid API token" if( $param->{code} eq 401 );
	Log3 $name, 4, "NUKIBridge ($name) - nukiId is not known" if( $param->{code} eq 404 );
	Log3 $name, 4, "NUKIBridge ($name) - action is undefined" if( $param->{code} eq 400 and $hash == $param->{chash} );
	
	
	######### Zum testen da ich kein Nuki Smartlock habe ############
	#if ( $param->{code} eq 404 ) {
        #    if( defined($param->{chash}->{helper}{lockAction}) ) {
        #        Log3 $name, 3, "NUKIBridge ($name) - Test JSON String for lockAction";
        #        $json = '{"success": true, "batteryCritical": false}';
        #    } else {
        #        Log3 $name, 3, "NUKIBridge ($name) - Test JSON String for lockState";
        #        $json = '{"state": 1, "stateName": "locked", "batteryCritical": false, "success": "true"}';
        #    }
        #    NUKIDevice_Parse($param->{chash},$json);
        #}
        
        
        readingsEndUpdate( $hash, 1 );
	return $param->{code};
    }
    
    if( $param->{code} eq 200 and $param->{endpoint} eq "list" and $param->{alive} eq 1 ) {
    
        readingsBulkUpdate( $hash, "state", "connected" );
        Log3 $name, 5, "NUKIBridge ($name) - Bridge ist online";
            
        readingsEndUpdate( $hash, 1 );
        return;
    }
    
    
    if( $hash == $param->{chash} ) {
    
        #$json = '[{"nukiId": 1, "name": "Home"}, {"nukiId": 2, "name": "Grandma"}]';        # zum testen da ich kein Nuki Smartlock habe
        
        NUKIBridge_ResponseProcessing($hash,$json);
        
    } else {
    
        NUKIDevice_Parse($param->{chash},$json);
    }
    
    readingsEndUpdate( $hash, 1 );
    return undef;
}

sub NUKIBridge_ResponseProcessing($$) {

    my ( $hash, $json ) = @_;
    my $name = $hash->{NAME};
    my $decode_json;
    
    
    $decode_json = decode_json($json);
    
    if( ref($decode_json) eq "ARRAY" and scalar(@{$decode_json}) > 0 ) {

        NUKIBridge_Autocreate($hash,$decode_json);
    
    } else {
        return $json;
    }
    
    return undef;
}

sub NUKIBridge_Autocreate($$;$) {

    my ($hash,$decode_json,$force)= @_;
    my $name = $hash->{NAME};

    if( !$force ) {
        foreach my $d (keys %defs) {
            next if($defs{$d}{TYPE} ne "autocreate");
            return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
        }
    }

    my $autocreated = 0;
    my $nukiSmartlock;
    my $nukiId;
    my $nukiName;
    
    readingsBeginUpdate($hash);
    
    foreach $nukiSmartlock (@{$decode_json}) {
        
        $nukiId     = $nukiSmartlock->{nukiId};
        $nukiName   = $nukiSmartlock->{name};
        
        
        my $code = $name ."-".$nukiId;
        if( defined($modules{NUKIDevice}{defptr}{$code}) ) {
            Log3 $name, 5, "$name: NukiId '$nukiId' already defined as '$modules{NUKIDevice}{defptr}{$code}->{NAME}'";
            next;
        }
        
        my $devname = "NUKIDevice" . $nukiId;
        my $define= "$devname NUKIDevice $nukiId IODev=$name";
        Log3 $name, 5, "$name: create new device '$devname' for address '$nukiId'";

        my $cmdret= CommandDefine(undef,$define);
        if($cmdret) {
            Log3 $name, 1, "($name) Autocreate: An error occurred while creating device for nukiId '$nukiId': $cmdret";
        } else {
            $cmdret= CommandAttr(undef,"$devname alias $nukiName");
            $cmdret= CommandAttr(undef,"$devname room NUKI");
            $cmdret= CommandAttr(undef,"$devname IODev $name");
        }

        $defs{$devname}{helper}{fromAutocreate} = 1 ;
        
        readingsBulkUpdate( $hash, "${autocreated}_nukiId", $nukiId );
        readingsBulkUpdate( $hash, "${autocreated}_name", $nukiName );
        
        $autocreated++;
        
        readingsBulkUpdate( $hash, "smartlockCount", $autocreated );
    }
    
    readingsBulkUpdate( $hash, "bridgeAPI", $bridgeAPI );
    readingsEndUpdate( $hash, 1 );
    
    
    if( $autocreated ) {
        Log3 $name, 2, "$name: autocreated $autocreated devices";
        CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    return "created $autocreated devices";
}

1;




=pod
=item device
=item summary    
=item summary_DE Modul zur Steuerung des Nuki Smartlock über die Nuki Bridge.

=begin html

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - controls the Nuki Smartlock over the Nuki Bridge</b></u>
  <br>
  The Nuki Bridge module connects FHEM to the Nuki Bridge and then reads all the smartlocks available on the bridge. Furthermore, the detected Smartlocks are automatically created as independent devices.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    This statement creates a NUKIBridge device with the name NBridge1 and the IP 192.168.0.23 as well as the token F34HK6.<br>
    After the bridge device is created, all available Smartlocks are automatically placed in FHEM.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>0_nukiId - ID of the first found Nuki Smartlock</li>
    <li>0_name - Name of the first found Nuki Smartlock</li>
    <li>smartlockCount - number of all found Smartlocks</li>
    <li>bridgeAPI - API Version of bridge</li>
    <br>
    The preceding number is continuous, starts with 0 und returns the properties of <b>one</b> Smartlock.
   </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>autocreate - Prompts to re-read all Smartlocks from the bridge and if not already present in FHEM, create the autimatic.</li>
    <li>statusRequest - starts a checkAlive of the bridge, it is determined whether the bridge is still online</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki Bridge</li>
    <li>interval - changes the interval for the CheckAlive</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - Steuert das Nuki Smartlock über die Nuki Bridge</b></u>
  <br>
  Das Nuki Bridge Modul verbindet FHEM mit der Nuki Bridge und liest dann alle auf der Bridge verfügbaren Smartlocks ein. Desweiteren werden automatisch die erkannten Smartlocks als eigenst&auml;ndige Devices an gelegt.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIBridge Device mit Namen NBridge1 und der IP 192.168.0.23 sowie dem Token F34HK6.<br>
    Nach dem anlegen des Bridge Devices werden alle zur verf&uuml;gung stehende Smartlock automatisch in FHEM an gelegt.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>0_nukiId - ID des ersten gefundenen Nuki Smartlocks</li>
    <li>0_name - Name des ersten gefunden Nuki Smartlocks</li>
    <li>smartlockCount - Anzahl aller gefundenen Smartlock</li>
    <li>bridgeAPI - API Version der Bridge</li>
    <br>
    Die vorangestellte Zahl ist forlaufend und gibt beginnend bei 0 die Eigenschaften <b>Eines</b> Smartlocks wieder.
  </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>autocreate - Veranlasst ein erneutes Einlesen aller Smartlocks von der Bridge und falls noch nicht in FHEM vorhanden das autimatische anlegen.</li>
    <li>statusRequest - startet einen checkAlive der Bridge, es wird festgestellt ob die Bridge noch online ist</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert die Nuki Bridge</li>
    <li>interval - verändert den Interval für den CheckAlive</li>
    <br>
  </ul>
</ul>

=end html_DE
=cut