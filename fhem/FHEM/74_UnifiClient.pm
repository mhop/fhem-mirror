##############################################################################
# $Id$
# 74_UnifiClient.pm

# CHANGED
##############################################################################
# V 0.0.1 BETA
#  - feature: 74_UnifiClient: initial version
# V 0.0.2 BETA
#  - fixed: 74_UnifiClient: fixed Loglevel and disconnected state
# V 0.0.3 BETA
#  - fixed: 74_UnifiClient: fixed use of timelocal()-Funktion

package main;
my $version="0.0.3 BETA";
my $thresholdBytesPerMinuteDefault=75000;
my $maxOnlineMinutesPerDayDefault=2000;# deutlich mehr als 1440=24h
# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use strict;
use warnings;
use POSIX;
use JSON qw(decode_json);

###  Forward declarations ####################################################{
sub UnifiClient_Initialize($$);
sub UnifiClient_Define($$);
sub UnifiClient_Undef($$);
sub UnifiClient_Attr(@);
sub UnifiClient_Notify($$);
sub UnifiClient_Set($@);
sub UnifiClient_Get($@);
sub UnifiClient_Parse($$);
sub UnifiClient_DailyReset($);
sub UnifiClient_Whoami();
sub UnifiClient_Whowasi();


sub UnifiClient_Initialize($$) {
  my ($hash) = @_; 
  $hash->{DefFn}         = "UnifiClient_Define";
  $hash->{UndefFn}       = "UnifiClient_Undef";
  $hash->{ParseFn}       = "UnifiClient_Parse";
  $hash->{AttrFn}        = "UnifiClient_Attr";
  $hash->{SetFn}         = "UnifiClient_Set";
  $hash->{GetFn}         = "UnifiClient_Get";
  $hash->{AttrList}      = "maxOnlineMinutesPerDay "
						   ."thresholdBytesPerMinute "
						   ."blockingUsergroup "
						   .$readingFnAttributes;
  $hash->{Match}     = "^UnifiClient";
}

sub UnifiClient_Define($$) {
    my ( $hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $name = $a[0];
    Log3 $name, 3, "UnifiClient_Define - executed. 0 ";
    return "Wrong syntax: use define <name> UnifiClient <clientName>" if(int(@a) < 2);
	# zweites Argument ist die eindeutige Geräteadresse
	my $address = $a[2];
    
    if(defined($modules{UnifiClient}{defptr}{$address})){
        return "Client with name $address already defined in ".($modules{UnifiClient}{defptr}{$address}{NAME});
    }
	$hash->{CODE}=$address;
	$hash->{VERSION}=$version;
	$hash->{NOTIFYDEV} = "global";
	# Adresse rückwärts dem Hash zuordnen (für ParseFn)
	$modules{UnifiClient}{defptr}{$address} = $hash;
	
    
    Log3 $name, 5, "UnifiClient_Define - Adress: ".$address;
    AssignIoPort($hash);
    
	
	# TODO: Ab hier nach notify verschieben
	$hash->{timeControl}->{clientblocked}=0;# TODO: Ändern in $hash->{unifiClient}->{usedOnlineTime} ??? oder anders speichern? 
	# clientBlocked und usedOnlineTime gehen verloren bei einem Neustart von fhem. 
	# im code mit TODO? markiert
		
    #$hash->{timeControl}->{usedOnlineTime}=0; # wird in DailyReset gesetzt -> Damit beim einem Neustart auf 0! TODO!!!
	$hash->{timeControl}->{maxOnlineMinutesPerDay}=$maxOnlineMinutesPerDayDefault if ! defined $hash->{timeControl}->{maxOnlineMinutesPerDay};
    $hash->{timeControl}->{thresholdBytesPerMinute} = $thresholdBytesPerMinuteDefault if ! defined $hash->{timeControl}->{thresholdBytesPerMinute};
    UnifiClient_DailyReset($hash);
}

sub UnifiClient_Undef($$){
	my ($hash, $name) = @_;
	Log3 $name, 3, "$name (UnifiClient_Undef) - executed.".$hash->{CODE};
	if(defined($hash->{CODE}) && defined($modules{UnifiClient}{defptr}{$hash->{CODE}})){
		delete($modules{UnifiClient}{defptr}{$hash->{CODE}});
	}
  
	RemoveInternalTimer($hash);
	return undef;
}

sub UnifiClient_Notify($$)
{
    my ($hash,$dev) = @_;
    my ($name,$self) = ($hash->{NAME},Unifi_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";

    return if($dev->{NAME} ne "global");
	
    return if(!grep(m/^DEFINED $name|MODIFIED $name|INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

    UnifiClient_DailyReset($hash);
    #Todo: $hash->{timeControl}->{blockingUsergroupID} = $usergroupID;

    return undef;
}
sub UnifiClient_Attr(@){
    my ($cmd,$name,$attr_name,$attr_value) = @_;
    my $hash = $defs{$name};
    
    if($cmd eq "set") {
        if($attr_name eq "disable") {
            if($attr_value == 1) {
				RemoveInternalTimer($hash);
            }
            else{
				# TODO: ggf. weitere Werte neu setzen?
				UnifiClient_DailyReset($hash);
            }
        }
        if($attr_name eq "maxOnlineMinutesPerDay") {
            $hash->{timeControl}->{maxOnlineMinutesPerDay} = $attr_value;
        }elsif($attr_name eq "thresholdBytesPerMinute") {
            $hash->{timeControl}->{thresholdBytesPerMinute} = $attr_value;
        }elsif($attr_name eq "blockingUsergroup") {
		
			#doppelter Code siehe UnifiClient_Set()
			my $usergroupID="";
			if (defined $defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups} && $attr_value ne "Default"){
				for my $ugID (keys %{$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}}) {
					$usergroupID=$ugID;
					last if $attr_value eq $defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}->{$usergroupID}->{name};	
				}
			}
            $hash->{timeControl}->{blockingUsergroupID} = $usergroupID;
        }
    }
    elsif($cmd eq "del") {
		if($attr_name eq "maxOnlineMinutesPerDay") {
            $hash->{timeControl}->{maxOnlineMinutesPerDay} = $maxOnlineMinutesPerDayDefault;
        }elsif($attr_name eq "thresholdBytesPerMinute") {
            $hash->{timeControl}->{thresholdBytesPerMinute} = $thresholdBytesPerMinuteDefault;
        }elsif($attr_name eq "blockingUsergroup") {
            delete $hash->{timeControl}->{blockingUsergroupID};
        }
    }
    return undef;
}


sub UnifiClient_Set($@){
	my ($hash,@a) = @_;
	my ($name,$setName,$setVal,$setVal2) = @a;
	Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "")." ". ($setVal2 ? $setVal2 : "") if ($setName ne "?");
  
	my $usergroups="";
	my $clientUsergroupID="";
	$clientUsergroupID=$hash->{unifiClient}->{usergroup_id} if defined $hash->{unifiClient}->{usergroup_id};
	if (defined $defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}){
		for my $usergroupID (keys %{$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}}) {
			if($usergroupID ne $clientUsergroupID){ # die schon vorhandene Gruppe braucht nicht erneut gesetzt zu werden
				$usergroups .=$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}->{$usergroupID}->{name}.",";	
			}
		}
	}
	$usergroups =~ s/.$//;
	if($setName !~ /clear|blockClient|unblockClient|usergroup|update/) {
		return "Unknown argument $setName, choose one of "
			."clear:readings,usedOnlineTime "
			.(($hash->{unifiClient}->{blocked} eq JSON::false) ? "blockClient:noArg " : "")
			.(($hash->{unifiClient}->{blocked} eq JSON::true) ? "unblockClient:noArg " : "")
			.(($usergroups ne "") ? "usergroup:$usergroups" : "")
			.((defined $hash->{unifiClient}->{mac}) ? " update:noArg" :"");
	} elsif ($setName eq 'clear') {
		if ($setVal eq 'readings') {
			for (keys %{$hash->{READINGS}}) {
				delete $hash->{READINGS}->{$_} if($_ ne 'state');
			}
		}elsif ($setVal eq 'usedOnlineTime') {
			$hash->{timeControl}->{usedOnlineTime}=0;
		}
	} elsif ($setName eq 'blockClient') {      
		IOWrite($hash, "Unifi_BlockClient_Send", $hash->{unifiClient}->{mac});
		$hash->{unifiClient}->{blocked}=JSON::true;
	} elsif ($setName eq 'unblockClient') {
		IOWrite($hash, "Unifi_UnblockClient_Send", $hash->{unifiClient}->{mac});
		$hash->{unifiClient}->{blocked}=JSON::false;
	} elsif ($setName eq 'usergroup') {
		my $usergroupID="";
		if (defined $defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}){
			for my $ugID (keys %{$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}}) {
				$usergroupID=$ugID;
				last if $setVal eq $defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}->{$usergroupID}->{name};	
			}
		}
		my $clientnameUC = "?";
		if (defined $hash->{unifiClient}->{name}){
			$clientnameUC = $hash->{unifiClient}->{name};
		}elsif (defined $hash->{unifiClient}->{hostname}){
			$clientnameUC = $hash->{unifiClient}->{hostname};
		}
		IOWrite($hash, "Unifi_UserRestJson_Send", $hash->{unifiClient}->{_id},"{\"usergroup_id\":\"".$usergroupID."\",\"name\":\"".$clientnameUC."\"}");
	} elsif ($setName eq 'update') {
		IOWrite($hash, "Unifi_UpdateClient_Send", $hash->{unifiClient}->{mac});
	}
	return undef;
}


sub UnifiClient_Get($@){
    my ($hash,@a) = @_;
	return "\"get $hash->{NAME}\" needs at least one argument" if ( @a < 2 );
    my ($name,$getName,$getVal) = @a;
	
    if (defined $getVal){
        Log3 $name, 5, "$name: get called with $getName $getVal." ;
    }else{
        Log3 $name, 5, "$name: get called with $getName.";
    }
	
    if($getName !~ /usergroups/) {
        return "Unknown argument $getName, choose one of usergroups:noArg";
    }
    elsif ($getName eq 'usergroups') {
        my $usergroups="";
		if (defined $defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}){
			for my $usergroupID (keys %{$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}}) {
				$usergroups .="name: ".$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}->{$usergroupID}->{name}."\n";
				$usergroups .="max_down: ".$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}->{$usergroupID}->{qos_rate_max_down}."\n";
				$usergroups .="max_up: ".$defs{$hash->{IODev}->{NAME}}->{unifi}->{usergroups}->{$usergroupID}->{qos_rate_max_up}."\n";
				$usergroups .= "====================================================\n";				
			}
		}
        $usergroups = "====================================================\n". $usergroups;
        $usergroups .= "====================================================\n";
        return $usergroups;
    }
  return undef;
}

sub UnifiClient_Parse($$) {
    my ($io_hash, $message) = @_;
    my ($name,$self) = ($io_hash->{NAME},UnifiClient_Whoami());
    my $i1=index($message,"_")+1;
    my $i2=index($message,"{")-$i1;
    my $address = substr($message, $i1, $i2); 
    Log3 $name, 5, "$name ($self) - executed. UnifiClient: Adress: ".$address;
    my $message_json=substr($message,$i1+$i2);
    Log3 $name, 5, "$name ($self) - executed. UnifiClient: message_json: ".$message_json;
	

	# wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
    if(my $hash = $modules{UnifiClient}{defptr}{$address}){
        # Nachricht für $hash verarbeiten
        my $clientRef = decode_json($message_json);
        $hash->{unifiClient} = $clientRef;
		$hash->{STATE} = $clientRef->{fhem_state};
		$hash->{MODEL}=$clientRef->{oui};
        
        my $old_tx=ReadingsVal($hash->{NAME},"tx_bytes",undef);
        my $seconds=ReadingsAge($hash->{NAME},"tx_bytes",1);
		$seconds=0.1 if ($seconds eq 0 || ! defined $seconds);  
        my $tx_used=0;
        if (defined $old_tx && defined $clientRef->{tx_bytes}){
            $tx_used=($clientRef->{tx_bytes})-($old_tx);
            $clientRef->{_f_diff_tx_bytes}=$tx_used;
        }        
		my $usedPerMinute=60*$tx_used/$seconds;
		if ($usedPerMinute > $hash->{timeControl}->{thresholdBytesPerMinute}){
			$hash->{timeControl}->{usedOnlineTime}=$hash->{timeControl}->{usedOnlineTime}+$seconds;# TODO?
		}
        $clientRef->{fhem_usedOnlineTime}=floor(($hash->{timeControl}->{usedOnlineTime})/60)." Minuten";# TODO?
		
		my $blockingUsergroupID=$hash->{timeControl}->{blockingUsergroupID};# TODO?
		#doppelter Code siehe UnifiClient_Set()
		my $clientnameUC = "?";
		if (defined $hash->{unifiClient}->{name}){
			$clientnameUC = $hash->{unifiClient}->{name};
		}elsif (defined $hash->{unifiClient}->{hostname}){
			$clientnameUC = $hash->{unifiClient}->{hostname};
		}
        if($hash->{timeControl}->{usedOnlineTime} > (60*$hash->{timeControl}->{maxOnlineMinutesPerDay})){ # mit 60 multiplizieren, da usedOnlineTime in Sekunden gespeichert wird.# TODO: Ändern in $hash->{unifiClient}->{usedOnlineTime}
			if(! $hash->{timeControl}->{clientblocked}){# TODO?
				if (defined $blockingUsergroupID){
					my $origUsergroup=""; # = Default
					$origUsergroup=$clientRef->{usergroup_id} if defined $clientRef->{usergroup_id};
					$hash->{timeControl}->{origUsergroup}=$origUsergroup;# TODO: Überlebt das einen Neustart von fhem? Oder besser ein neues Reading?
					
					IOWrite($hash, "Unifi_UserRestJson_Send", $clientRef->{_id},"{\"usergroup_id\":\"".$blockingUsergroupID."\",\"name\":\"".$clientnameUC."\"}");
					$clientRef->{usergroup_id}=$blockingUsergroupID;# ggf. auch _f_usergroupName setzen
				} else{
					IOWrite($hash, "Unifi_BlockClient_Send", $clientRef->{mac});
					$clientRef->{blocked}=JSON::true;
				}
			}
			$hash->{timeControl}->{clientblocked}=1;# TODO?
		}elsif($hash->{timeControl}->{clientblocked}){# TODO?
			if (defined $blockingUsergroupID){
				IOWrite($hash, "Unifi_UserRestJson_Send", $clientRef->{_id},"{\"usergroup_id\":\"".$hash->{timeControl}->{origUsergroup}."\",\"name\":\"".$clientnameUC."\"}");
				$clientRef->{usergroup_id}=$hash->{timeControl}->{origUsergroup}; # ggf. auch _f_usergroupName setzen
			} else{
				IOWrite($hash, "Unifi_UnblockClient_Send", $clientRef->{mac});
				$clientRef->{blocked}=JSON::false;
			}
			$hash->{timeControl}->{clientblocked}=0;# TODO?
		}
        
		readingsBeginUpdate($hash);
		for my $key (keys %{$clientRef}) {
			readingsBulkUpdate($hash,$key,$clientRef->{$key});
		}
		readingsEndUpdate($hash,1);
        
        
        Log3 $name, 5, "$name ($self) - return: ".$hash->{NAME};
		return $hash->{NAME}; # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.
	}
	else{
		# Keine Gerätedefinition verfügbar
		# Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
        Log3 $name, 4, "$name ($self) - return: UNDEFINED UnifiClient_".$address." UnifiClient $address";
		#return "UNDEFINED ".$address." UnifiClient $address";
		return $io_hash->{NAME}; # kein autocreate
		#return undef;
	}
}

###############################################################################
sub UnifiClient_DailyReset($){
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},UnifiClient_Whoami());
    Log3 $name, 5, "$name ($self) - executed.";
	RemoveInternalTimer($hash, 'UnifiClient_DailyReset');
    $hash->{timeControl}->{usedOnlineTime}=0; # TODO?

    my @l = localtime();
    $l[0] = 0;
    $l[1] = 0;
    $l[2] = 0;
    my $localmidnighttime = mktime(@l)+(60*60*24);
	#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)= gmtime($localmidnighttime);
    #Log3 $name, 1, "$name ($self) - next reset at: $wday $mday.$mon.$year - $hour:$min:$sec";
	#my ($sec2,$min2,$hour2,$mday2,$mon2,$year2,$wday2,$yday2,$isdst2)= gmtime(time());
    #Log3 $name, 1, "$name ($self) - now: $wday2 $mday2.$mon2.$year2 - $hour2:$min2:$sec2";
    InternalTimer($localmidnighttime, 'UnifiClient_DailyReset', $hash, 0);
}

###############################################################################

sub UnifiClient_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
sub UnifiClient_Whowasi() { return (split('::',(caller(2))[3]))[1] || ''; }

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item device
=item summary Show info and control a UnifiClient (Unifi-Device required).
=item summary_DE Zeigt Infos zu einem UnifiClient an und steuert diesen.

=begin html

<a name="UnifiClient"></a>
<h3>UnifiClient</h3>
<ul>

UnifiClient is the FHEM module for the Ubiquiti Networks (UBNT) Client.<br>
<br>
You can use the readings or set features to control your clients.
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
    <code>define &lt;name&gt; UnifiClient &lt;clientName&gt;</code>
	<br>
    &lt;name&gt;:
    <ul>
    <code>The FHEM device name for the device.</code><br>
    </ul>
    &lt;clientName&gt;:
    <ul>
    <code>The name of the client in unifi-module.</code><br>
    </ul>
</ul>

<h4>Set</h4>
<ul>
    <li><code>set &lt;name&gt; clear &lt;readings|usedOnlineTime&gt;</code><br>
    Clears the readings or set the usedOnlimeTime=0. </li>
	<br>
    <li><code>set &lt;name&gt; blockClient &lt;</code><br>
    Blocks the client. </li>
	<br>
    <li><code>set &lt;name&gt; unblockClient &lt;</code><br>
    Unblocks the client. </li>
	<br>
    <li><code>set &lt;name&gt; usergroup &lt;</code><br>
    Set the usergroup for the client. </li>
	<br>
    <li><code>set &lt;name&gt; update &lt;</code><br>
    Updates the client data. </li>
	<br>
</ul>

<h4>Get</h4>
<ul>
    <li><code>get &lt;usergroups&gt; todo</code><br>
    Show information about the configuered usergroups in UnifiController.</li>
    <br>

</ul>

<h4>Attributes</h4>
<ul>
    <li>attr maxOnlineMinutesPerDay &lt;number&gt;<br>
    Defines the maximum minutes this client is allowed to use the unifi-network. The client will be blocked when the reading fhem_usedOnlineTime is above this attribute.<br></li>
    <br>
    <li>attr thresholdBytesPerMinute &lt;number&gt;<br>
    Clients often use the network without user interaction. Define a threshold thats allowed per Minute without counting to usedOnlineTime.<br>
	Default: 75000<br></li>
    <br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
</ul>

<h4>Readings</h4>
<ul>
    Note: All readings generate events. You can control this with <a href="#readingFnAttributes">these global attributes</a>.
    <li>todo
        <ul>todo.</ul>
    </li>
</ul>
<br>

</ul>

=end html

# Ende der Commandref
=cut