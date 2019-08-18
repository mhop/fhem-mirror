##############################################################################
# $Id$
# 74_UnifiSwitch.pm

# CHANGED
##############################################################################
# V 0.1
#  - feature: 74_UnifiSwitch: initial version
# V 0.11
#  - feature: 74_UnifiSwitch: state des USW wird gesetzt
#                             Port-Nummern < 9 mit führender 0
#                             Model als Internal
#                             port-state als reading hinzugefügt
# V 0.90
# - feature: 74_UnifiSwitch: setter for poe-Mode
#                             added commandref
# V 0.91
# - fixed:   74_Unififwitch: fixed wording in commandref
#                             added new state-mappings
# V 0.92
# - fixed:   74_UnifiSwitch: fixed possible log-error in eq in line 135
# V 0.93
# - bugfix:  74_UnifiSwitch: fixed poe restart
# V 0.0.94
# - feature: 74_UnifiSwitch: supports new module UnifiClient
# V 0.0.95
# - feature: 74_UnifiSwitch: supports disablePort
# V 0.0.96
# - fixed:   74_UnifiSwitch: Log-Messages
# 
# TODOs:
# - state des USW für weiter state-Numbers korrekt in Worte übersetzen 

package main;
my $version="0.0.96";
# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use strict;
use warnings;
use POSIX;
use JSON qw(decode_json);
use JSON qw(encode_json);

###  Forward declarations ####################################################{
sub UnifiSwitch_Initialize($$);
sub UnifiSwitch_Define($$);
sub UnifiSwitch_Undef($$);
sub UnifiSwitch_Attr(@);
sub UnifiSwitch_Set($@);
sub UnifiSwitch_Get($@);
sub UnifiSwitch_Parse($$);
sub UnifiSwitch_Whoami();
sub UnifiSwitch_Whowasi();


sub UnifiSwitch_Initialize($$) {
  my ($hash) = @_; 
  $hash->{DefFn}         = "UnifiSwitch_Define";
  $hash->{UndefFn}       = "UnifiSwitch_Undef";
  $hash->{ParseFn}       = "UnifiSwitch_Parse";
  $hash->{AttrFn}        = "UnifiSwitch_Attr";
  $hash->{SetFn}         = "UnifiSwitch_Set";
  $hash->{GetFn}         = "UnifiSwitch_Get";
  $hash->{AttrList}      = "portProfileDisableID ".
							$readingFnAttributes;
  # TODO: notwendig?
  $hash->{Match}     = "^UnifiSwitch";
  # TODO ATTR wird nicht übernommen
  $hash->{AutoCreate}={"UnifiSwitch.*" => { ATTR => "event-on-change-reading:.* event-min-interval:.*:300",
                                             FILTER => "%NAME", 
                                             autocreateThreshold => "1:1"} };
}

sub UnifiSwitch_Define($$) {
    my ( $hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $name = $a[0];
    Log3 $name, 5, "UnifiSwitch_Define - executed. 0 ";
	# zweites Argument ist die eindeutige Geräteadresse
	my $address = $a[2];
    
    if(defined($modules{UnifiSwitch}{defptr}{$address})){
        return "Switch with name $address already defined in ".($modules{UnifiSwitch}{defptr}{$address}{NAME});
    }
	$hash->{CODE}=$address;
	$hash->{VERSION}=$version;
	# Adresse rückwärts dem Hash zuordnen (für ParseFn)
	$modules{UnifiSwitch}{defptr}{$address} = $hash;
  
    Log3 $name, 3, "UnifiSwitch_Define - Adress: ".$address;
    AssignIoPort($hash);
}

sub UnifiSwitch_Undef($$){
  my ($hash, $name) = @_;
  Log3 $name, 3, "$name (UnifiSwitch_Undef) - executed.".$hash->{CODE};
  if(defined($hash->{CODE}) && defined($modules{UnifiSwitch}{defptr}{$hash->{CODE}})){
    delete($modules{UnifiSwitch}{defptr}{$hash->{CODE}});
  }
  return undef;
}

sub UnifiSwitch_Attr(@){

    my ($cmd,$name,$attr_name,$attr_value) = @_;
    my $hash = $defs{$name};
    
    #if($cmd eq "set") {
    #    if($attr_name eq "portProfileDisableID") {
    #    }
    #}
    #elsif($cmd eq "del") {
    #    if($attr_name eq "portProfileDisableID") {
    #    }
    #}
    return undef;
}


sub UnifiSwitch_Set($@){
  my ($hash,@a) = @_;
  my ($name,$setName,$setVal,$setVal2) = @a;
  Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "")." ". ($setVal2 ? $setVal2 : "") if ($setName ne "?");
  
  # TODO: ggf. auf disabled des Unifi-devices prüfen?! Wie bekomme ich den io_hash?
  #if(Unifi_CONNECTED($hash) eq 'disabled' && $setName !~ /clear/) {
  #  return "Unknown argument $setName, choose one of clear:all,readings";
  #  Log3 $name, 5, "$name: set called with $setName but device is disabled!" if($setName ne "?");
  #  return undef;
  #}
	my $portProfileDisableID=AttrVal($name,"portProfileDisableID",undef);
	my $isPortprofileID = "";
	$isPortprofileID ="disablePort" if (defined $portProfileDisableID);
    if($setName !~ /clear|poeMode|disablePort/) {
		return "Unknown argument $setName, choose one of "
           ."clear:all,readings poeMode ".$isPortprofileID; #TODO: PortNamen sowie die Modes als Auswahl anhängen 
    } else {
		Log3 $name, 4, "$name: set $setName";
		my $apRef = $hash->{usw};
		if( $setVal !~ m/\d+/ ) { #falls der Portname angegeben wurde, diesen in eine ID umwandeln.
			for my $port (@{$apRef->{port_table}}) {
				next if( $port->{name} !~ $setVal );
				$setVal = $port->{port_idx};
				last;
			}
		}
		my $port_overrides = $apRef->{port_overrides};
		my $idx;
		my $i = 0;
		for my $entry (@{$port_overrides}) {
			if( defined $entry->{port_idx}){
				if($entry->{port_idx} eq $setVal) {
					$idx = $i;
					#last;
				}
			}
			else{
				splice(@{$port_overrides},$i,1); #manchmal kommen Einträge ohne ID hinzu. Dies führt bei vielen Overrides zu einem Fehler, da mehr Overrides als Ports vorhanden sein können. Hier wird aufgeräumt.
			}				
			++$i;
		}
		if( !defined($idx) ) {
			push @{$port_overrides}, {port_idx => $setVal+0};
			$idx = scalar @{$port_overrides};
		}
		return "port-ID musst be numeric" if( $setVal !~ m/\d+/ );
		return "switch has no ports!" if( !$apRef->{port_table} );
		return "port musst be in [1..". scalar @{$apRef->{port_table}} ."] " if( $setVal < 1 || $setVal > scalar @{$apRef->{port_table}} );
		return "switch '$apRef->{name}' has no port $setVal" if( !defined(@{$apRef->{port_table}}[$setVal-1] ) );
		
		if( $setName eq 'disablePort' ) {
			$port_overrides->[$idx]{portconf_id} = $portProfileDisableID;
			IOWrite($hash, "Unifi_DeviceRestJson_Send", $apRef->{device_id}, $port_overrides);
		}elsif ($setName eq 'poeMode') {
			return "usage: $setName  <port> <off|auto|passive|passthrough|restart>" if( !$setVal );		  
			return "port $setVal of switch '$apRef->{name}' is not poe capable" if( !@{$apRef->{port_table}}[$setVal-1]->{port_poe} );


			if( $setVal2 eq 'off' ) {
				$port_overrides->[$idx]{poe_mode} = "off";
				IOWrite($hash, "Unifi_DeviceRestJson_Send", $apRef->{device_id}, $port_overrides);

			} elsif( $setVal2 eq 'auto' || $setVal2 eq 'poe+' ) {
				#return "port $setVal not auto poe capable" if( @{$apRef->{port_table}}[$setVal-1]->{poe_caps} & 0x03 ) ;
				$port_overrides->[$idx]{poe_mode} = "auto";
				IOWrite($hash, "Unifi_DeviceRestJson_Send", $apRef->{device_id}, $port_overrides );

			} elsif( $setVal2 eq 'passive' ) {
				#return "port $setVal not passive poe capable" if( @{$apRef->{port_table}}[$setVal-1]->{poe_caps} & 0x04 ) ;
				$port_overrides->[$idx]{poe_mode} = "pasv24";
				IOWrite($hash, "Unifi_DeviceRestJson_Send", $apRef->{device_id}, $port_overrides);

			} elsif( $setVal2 eq 'passthrough' ) {
				#return "port $setVal not passthrough poe capable" if( @{$apRef->{port_table}}[$setVal-1]->{poe_caps} & 0x08 ) ;
				$port_overrides->[$idx]{poe_mode} = "passthrough";
				IOWrite($hash, "Unifi_DeviceRestJson_Send", $apRef->{device_id}, $port_overrides);

			} elsif( $setVal2 eq 'restart' ) {#TODO: Was wir hier gemacht? Funktioniert das noch?
				IOWrite($hash, "Unifi_ApJson_Send", $apRef->{device_id}, {cmd => 'power-cycle', mac => $apRef->{mac}, port_idx => $setVal});

			}else {
				return "unknwon poe mode $setVal2";
			}
		}elsif ($setName eq 'clear') {
		  if ($setVal eq 'readings' || $setVal eq 'all') {
			  for (keys %{$hash->{READINGS}}) {
				  delete $hash->{READINGS}->{$_} if($_ ne 'state');
			  }
		  }
		}
	}
	return undef;
}


sub UnifiSwitch_Get($@){
    my ($hash,@a) = @_;
	return "\"get $hash->{NAME}\" needs at least one argument" if ( @a < 2 );
    my ($name,$getName,$getVal) = @a;
	
    if (defined $getVal){
        Log3 $name, 5, "$name: get called with $getName $getVal." ;
    }else{
        Log3 $name, 5, "$name: get called with $getName.";
    }
	
    if($getName !~ /poeState|portOverrides/) {
        return "Unknown argument $getName, choose one of poeState:noArg portOverrides:noArg";
    }
    elsif ($getName eq 'poeState') {
        my $poeState;
        my $apRef = $hash->{usw};
        next if( $apRef->{type} ne 'usw' );
        next if( !$apRef->{port_table} );
        next if( $getVal && $getVal ne $apRef->{mac} && $getVal ne $apRef->{device_id} && $apRef->{name} !~ $getVal );
        $poeState .= "\n" if( $poeState );
        $poeState .= sprintf( "%-20s (mac:%-17s, id:%s)\n", $apRef->{name}, $apRef->{mac}, $apRef->{device_id} );
        $poeState .= sprintf( "  %2s  %-15s", "id", "name" );
        $poeState .= sprintf( " %s %-6s %-4s %s %-10s", " ", "on", "mode", " ", "class" );
        $poeState .= "\n";
        for my $port (@{$apRef->{port_table}}) {
          #next if( !$port->{port_poe} );
          $poeState .= sprintf( "  %2i  %-15s", $port->{port_idx}, $port->{name} );
          $poeState .= sprintf( " %s %-6s %-4s %s %-10s", $port->{poe_caps}, $port->{poe_enable}, $port->{poe_mode}, defined($port->{poe_good})?($port->{poe_good}?"good":""):"", defined($port->{poe_class})?$port->{poe_class}:"" ) if( $port->{port_poe} );
          $poeState .= sprintf( " %5.2fW %5.2fV %5.2fmA", $port->{poe_power}?$port->{poe_power}:0, $port->{poe_voltage}, $port->{poe_current}?$port->{poe_current}:0 ) if( $port->{port_poe} );
          $poeState .= "\n";
        }
        
        $poeState = "====================================================\n". $poeState;
        $poeState .= "====================================================\n";
        return $poeState;
    }
    elsif ($getName eq 'portOverrides') {
        my $portOverrides;
        my $apRef = $hash->{usw};
        next if( $apRef->{type} ne 'usw' );
        next if( !$apRef->{port_table} );
        next if( $getVal && $getVal ne $apRef->{mac} && $getVal ne $apRef->{device_id} && $apRef->{name} !~ $getVal );		
        $portOverrides .= "\n" if( $portOverrides );
        $portOverrides .= sprintf( "%-20s (mac:%-17s, id:%s)\n", $apRef->{name}, $apRef->{mac}, $apRef->{device_id} );
        $portOverrides .= sprintf( "  %2s  %-15s", "id", "name" );
        $portOverrides .= sprintf( " %-10s %-25s", "poe_mode", "PortConfigID" );
        $portOverrides .= "\n";
        for my $port (@{$apRef->{port_overrides}}) {
			if(defined $port->{port_idx}){
				$portOverrides .= sprintf( "  %2i  %-15s", $port->{port_idx}, $port->{name}?$port->{name}:"" );
				$portOverrides .= sprintf( " %-10s %-25s", $port->{poe_mode}?$port->{poe_mode}:"", $port->{portconf_id}?$port->{portconf_id}:"");
				$portOverrides .= "\n";
			}
        }
        
        $portOverrides = "====================================================\n". $portOverrides;
        $portOverrides .= "====================================================\n";
        return $portOverrides;
    }
  return undef;
}

sub UnifiSwitch_Parse($$) {
    my ($io_hash, $message) = @_;
    my ($name,$self) = ($io_hash->{NAME},UnifiSwitch_Whoami());
    my $i1=index($message,"_")+1;
    my $i2=index($message,"{")-$i1;
    my $address = substr($message, $i1, $i2); 
    Log3 $name, 5, "$name ($self) - executed. UnifiSwitch: Adress: ".$address;
    my $message_json=substr($message,$i1+$i2);
    Log3 $name, 5, "$name ($self) - executed. UnifiSwitch: message_json: ".$message_json;

	# wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
    if(my $hash = $modules{UnifiSwitch}{defptr}{$address}){
        # Nachricht für $hash verarbeiten
        my $apRef = decode_json($message_json);
        $hash->{usw} = $apRef;
        if( $apRef->{type} eq 'usw' ){
          if ($apRef->{state} eq "1"){
            $hash->{STATE} = "connected";
          }elsif($apRef->{state} eq "2"){
            $hash->{STATE} = "managed by other";
          }elsif($apRef->{state} eq "4"){
            $hash->{STATE} = "upgrading";
          }elsif($apRef->{state} eq "5"){
            $hash->{STATE} = "provisioning";
          }else{
            $hash->{STATE} = "unknown: ".$apRef->{state}; # TODO: Weitere states setzen wenn state-id bekannt
          }
          $hash->{MODEL}=$apRef->{model};
          readingsBeginUpdate($hash);
          if( $apRef->{port_table} ){
            for my $port (@{$apRef->{port_table}}) {
              my $port_id=$port->{port_idx} > 9 ? "port_".$port->{port_idx} : "port_0".$port->{port_idx};
              readingsBulkUpdate($hash,$port_id."_name",$port->{name});
              if(defined $port->{speed} && looks_like_number($port->{speed})){
                readingsBulkUpdate($hash,$port_id."_state",$port->{speed} > 0 ? $port->{speed}." Mbps" : "disconnected");
              }else{
                readingsBulkUpdate($hash,$port_id."_state","unknown");
              }
              if( $port->{port_poe} ){
                readingsBulkUpdate($hash,$port_id."_poe_mode",$port->{poe_mode});
                readingsBulkUpdate($hash,$port_id."_poe_power",$port->{poe_power});
                readingsBulkUpdate($hash,$port_id."_poe_voltage",$port->{poe_voltage});
                readingsBulkUpdate($hash,$port_id."_poe_current",$port->{poe_current});
              }
            }
          }
		  
		  
		  
          readingsEndUpdate($hash,1);
        }
        Log3 $name, 5, "$name ($self) - return: ".$hash->{NAME};
		return $hash->{NAME}; # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.
	}
	else{
		# Keine Gerätedefinition verfügbar
		# Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
        Log3 $name, 4, "$name ($self) - return: UNDEFINED UnifiSwitch_".$address." UnifiSwitch $address";
		return "UNDEFINED ".$address." UnifiSwitch $address";
	}
}

###############################################################################

sub UnifiSwitch_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
sub UnifiSwitch_Whowasi() { return (split('::',(caller(2))[3]))[1] || ''; }

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item device
=item summary Show info and control UnifiSwitch  (USW) (Unifi-Device required)
=item summary_DE Zeigt Infos zum UnifiSwitch (USW) an und steuert diesen.

=begin html

<a name="UnifiSwitch"></a>
<h3>UnifiSwitch</h3>
<ul>

UnifiSwitch is the FHEM module for the Ubiquiti Networks (UBNT) Switch - USW.<br>
<br>
You can use the readings or set features to control your unifi-switch.
<br>
<h4>Prerequisites</h4>
  <ul>
    <li>
      A connected Unifi-Device as IODev.
    </li>
    <li>
      The Perl module JSON is required. <br>
      On Debian/Raspbian: <code>apt-get install libjson-perl </code><br>
      Via CPAN: <code>cpan install JSON</code>
    </li>
  </ul>

<h4>Define</h4>
<ul>
    <code>define &lt;name&gt; UnifiSwitch &lt;ip&gt; &lt;nameOfSwitch&gt;</code>
    <br>Normaly this device will be autocreated!<br>
	<br>
    &lt;name&gt;:
    <ul>
    <code>The FHEM device name for the device.</code><br>
    </ul>
    &lt;nameOfSwitch&gt;:
    <ul>
    <code>The name of the switch in unifi-controller.</code><br>
    </ul>
</ul>

<h4>Set</h4>
<ul>
    <li><code>set &lt;name&gt; clear &lt;readings|all&gt;</code><br>
    Clears the readings or all. </li>
    <br>
    <li><code>set &lt;name&gt; poeMode &lt;port&gt; &lt;off|auto|passive|passthrough|restart&gt;</code><br>
    Set PoE mode for &lt;port&gt;. </li>
    <br>
    <li><code>set &lt;name&gt; disablePort &lt;port&gt;</code><br>
	Only visible when Attr portProfileDisableID is set.<br>
    Set the PortProfile from Attr portProfileDisableID for &lt;port&gt;. </li>
</ul>

<h4>Get</h4>
<ul>
    <li><code>get &lt;name&gt; poeState</code><br>
    Show more details about the ports of the switch.</li>
    <br>
    <li><code>get &lt;name&gt; portOverrides</code><br>
    Show more details about the portOverrides of the switch.</li>
    <br>

</ul>



<h4>Attributes</h4>
<ul>
    <li>attr portProfileDisableID<br>
    Quick Workaround for special purposes: Must contain the ID off the disable-PortConfig. Then set disablePort can be used.<br>
	The ID can be found with get portOverrides.<br>
	To enable the port the UnifiController-Software must be used.</li>
    <br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
</ul>

<h4>Readings</h4>
<ul>
    Note: All readings generate events. You can control this with <a href="#readingFnAttributes">these global attributes</a>.
    <li>Each port has the readings name and state. POE-ports have more readings.</li>
    <li>name
        <ul>The name of the port as defined in UnifiController.</ul>
    </li>
    <li>state
        <ul>The connection state of the port. Can be disconnected or in Mbps/Gbps.</ul>
    </li>
    <li>poe_current
        <ul>The current of the port.</ul>
    </li>
    <li>poe_mode
        <ul>The poe-mode of the port.</ul>
    </li>
    <li>poe_power
        <ul>The power of the port.</ul>
    </li>
    <li>poe_voltage
        <ul>The voltage of the port.</ul>
    </li>
</ul>
<br>

</ul>

=end html

# Ende der Commandref
=cut