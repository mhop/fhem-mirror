###############################################################################
# $Id: 70_VolumeLink.pm 2015-08-20 09:00 - rapster - rapster at x0e dot de $ 

package main;
use strict;
use warnings;
use POSIX;
use HttpUtils;
use Time::HiRes qw(gettimeofday time);
use Scalar::Util;
###############################################################################

sub VolumeLink_Initialize($$) { 
    my ($hash) = @_; 
    $hash->{DefFn}    = "VolumeLink_Define";
    $hash->{UndefFn}  = "VolumeLink_Undef";
    $hash->{SetFn}    = "VolumeLink_Set";
    $hash->{AttrFn}   = 'VolumeLink_Attr';
    $hash->{AttrList} = "disable:1,0 "
                        ."ampInputReading "
                        ."ampInputReadingVal "
                        ."ampVolumeReading "
                        ."ampVolumeCommand "
                        ."ampMuteReading "
                        ."ampMuteReadingOnVal "
                        ."ampMuteReadingOffVal "
                        ."ampMuteCommand "
                        ."volumeRegexPattern "
                        ."muteRegexPattern "
                        ."httpNoShutdown:1,0 "
                        .$readingFnAttributes;
}
###############################################################################

sub VolumeLink_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    return "Wrong syntax: use define <name> VolumeLink <interval> <url> <ampDevice> [<timeout> [<httpErrorLoglevel> [<httpLoglevel>]]]" if(int(@a) < 5);
    return "Wrong syntax: <interval> is not a number!"                    if(!looks_like_number($a[2]));
    return "Wrong syntax: <interval> too small, must be at least 0.01"    if($a[2] < 0.01);
    return "Wrong syntax: <timeout> is not a number!"                     if($a[5] && !looks_like_number($a[5]));
    return "Wrong syntax: <timeout> too small, must be at least 0.01"     if($a[5] && $a[5] < 0.01);
    return "Wrong syntax: <ampDevice> not defined! Define '$a[4]' first." if(!defined$defs{$a[4]});
    
    my $name = $a[0];

    %$hash = (                  %$hash,
        STARTED                 => $hash->{STARTED} || 0,
        interval                => $a[2],
        url                     => $a[3],
        ampDevice               => $a[4],
        timeout                 => $a[5] || 0.5,
        httpErrorLoglevel       => $a[6] || 4,
        httpLoglevel            => $a[7] || 5,
        httpNoShutdown          => ( defined($attr{$name}->{httpNoShutdown}) ) ? $attr{$name}->{httpNoShutdown} : 1,
        volumeRegexPattern      => $attr{$name}->{volumeRegexPattern} || 'current":\s*(\d+)',
        muteRegexPattern        => $attr{$name}->{muteRegexPattern} || 'muted":\s*(\w+|\d+)',
        ampInputReading         => ( defined($attr{$name}->{ampInputReading}) ) ? $attr{$name}->{ampInputReading} : 'currentTitle',
        ampInputReadingVal      => ( defined($attr{$name}->{ampInputReadingVal}) ) ? $attr{$name}->{ampInputReadingVal} : 'SPDIF-Wiedergabe|^$',
        ampVolumeReading        => $attr{$name}->{ampVolumeReading} || 'Volume',
        ampVolumeCommand        => $attr{$name}->{ampVolumeCommand} || 'Volume',
        ampMuteReading          => $attr{$name}->{ampMuteReading} || 'Mute',
        ampMuteReadingOnVal     => ( defined($attr{$name}->{ampMuteReadingOnVal}) ) ? $attr{$name}->{ampMuteReadingOnVal} : 1,
        ampMuteReadingOffVal    => ( defined($attr{$name}->{ampMuteReadingOffVal}) ) ? $attr{$name}->{ampMuteReadingOffVal} : 0,
        ampMuteCommand          => $attr{$name}->{ampMuteCommand} || 'Mute'
    );
    $hash->{httpParams} = {
        HTTP_ERROR_COUNT  => 0,
        fastRetryInterval => 0.1,
        hash              => $hash,
        url               => $hash->{url},
        timeout           => $hash->{timeout},
        noshutdown        => $hash->{httpNoShutdown},
        loglevel          => $hash->{httpLoglevel},
        errorLoglevel     => $hash->{httpErrorLoglevel},
        method            => 'GET',
        callback          => \&VolumeLink_ReceiveCommand
    };
    
    readingsSingleUpdate($hash,'state','off',1) if($hash->{STARTED} == 0 && ReadingsVal($name,'state','') ne 'off');
    
    Log3 $name, 3, "$name: Defined with interval:$hash->{interval}, url:$hash->{url}, timeout:$hash->{timeout}, ampDevice:$hash->{ampDevice}";	

    return undef;
}
###############################################################################

sub VolumeLink_Undef($$) {
    my ($hash,$arg) = @_;
    
    $hash->{STARTED} = 0;
    RemoveInternalTimer ($hash);
    
    Log3 $hash->{NAME}, 3, "$hash->{NAME}: STOPPED";
    
    return undef;
}
###############################################################################

sub VolumeLink_Set($@) {
    my ($hash,@a) = @_;
    return "\"set $hash->{NAME}\" needs at least an argument" if ( @a < 2 );

    my ($name,$setName,$setVal) = @a;

    if (AttrVal($name, "disable", 0)) {
        Log3 $name, 5, "$name: set called with $setName but device is disabled" if ($setName ne "?");
        return undef;
    }
    Log3 $name, 5, "$name: set called with $setName " . ($setVal ? $setVal : "") if ($setName ne "?");

    if($setName !~ /on|off/) {
        return "Unknown argument $setName, choose one of on:noArg off:noArg";
    } else {
        Log3 $name, 4, "VolumeLink: set $name $setName";
        
        if ($setName eq 'on') {
            if($hash->{STARTED} == 0) {
            
                $hash->{STARTED} = 1;
                
                Log3 $name, 3, "$name: STARTED";
                readingsSingleUpdate($hash,"state",$setName,1);
                
				VolumeLink_SendCommand($hash);
            }
        } 
        elsif ($setName eq 'off') {
            if($hash->{STARTED} == 1) {
            
                $hash->{STARTED} = 0;
                RemoveInternalTimer($hash);
                
                Log3 $name, 3, "$name: STOPPED";
				readingsSingleUpdate($hash,"state",$setName,1);
            }
        }
    }
    return undef;
}
###############################################################################

sub VolumeLink_Attr(@) {
    my ($cmd,$name,$attr_name,$attr_value) = @_;
    
    if($cmd eq "set") {
        if($attr_name eq "disable" && $attr_value == 1) {
            CommandSet(undef, $name.' off');
        }
        $defs{$name}->{ampInputReading}      = $attr_value      if($attr_name eq 'ampInputReading');
        $defs{$name}->{ampInputReadingVal} 	 = $attr_value      if($attr_name eq 'ampInputReadingVal');
        $defs{$name}->{ampVolumeReading}     = $attr_value      if($attr_name eq 'ampVolumeReading');
        $defs{$name}->{ampVolumeCommand}     = $attr_value      if($attr_name eq 'ampVolumeCommand');
        $defs{$name}->{ampMuteReading}       = $attr_value      if($attr_name eq 'ampMuteReading');
        $defs{$name}->{ampMuteReadingOnVal}  = $attr_value      if($attr_name eq 'ampMuteReadingOnVal');
        $defs{$name}->{ampMuteReadingOffVal} = $attr_value      if($attr_name eq 'ampMuteReadingOffVal');
        $defs{$name}->{ampMuteCommand}       = $attr_value      if($attr_name eq 'ampMuteCommand');
        $defs{$name}->{volumeRegexPattern}   = $attr_value      if($attr_name eq 'volumeRegexPattern');
        $defs{$name}->{muteRegexPattern}     = $attr_value      if($attr_name eq 'muteRegexPattern');
        $defs{$name}->{httpNoShutdown}       = $attr_value      if($attr_name eq 'httpNoShutdown');
        if($attr_name eq 'httpNoShutdown') {
            $defs{$name}->{httpNoShutdown} = $attr_value;
            $defs{$name}->{httpParams}->{noshutdown} = $defs{$name}->{httpNoShutdown};
        }
    }
    elsif($cmd eq "del") {
        $defs{$name}->{ampInputReading}      = 'currentTitle'          if($attr_name eq 'ampInputReading');
        $defs{$name}->{ampInputReadingVal}   = 'SPDIF-Wiedergabe|^$'   if($attr_name eq 'ampInputReadingVal');
        $defs{$name}->{ampVolumeReading}     = 'Volume'                if($attr_name eq 'ampVolumeReading');
        $defs{$name}->{ampVolumeCommand}     = 'Volume'                if($attr_name eq 'ampVolumeCommand');
        $defs{$name}->{ampMuteReading}       = 'Mute'                  if($attr_name eq 'ampMuteReading');
        $defs{$name}->{ampMuteReadingOnVal}  = 1                       if($attr_name eq 'ampMuteReadingOnVal');
        $defs{$name}->{ampMuteReadingOffVal} = 0                       if($attr_name eq 'ampMuteReadingOffVal');
        $defs{$name}->{ampMuteCommand}       = 'Mute'                  if($attr_name eq 'ampMuteCommand');
        $defs{$name}->{volumeRegexPattern}   = 'current":\s*(\d+)'     if($attr_name eq 'volumeRegexPattern');
        $defs{$name}->{muteRegexPattern}     = 'muted":\s*(\w+|\d+)'   if($attr_name eq 'muteRegexPattern');
        if($attr_name eq 'httpNoShutdown') {
            $defs{$name}->{httpNoShutdown} = 1;
            $defs{$name}->{httpParams}->{noshutdown} = $defs{$name}->{httpNoShutdown};
        }
    }
    return undef;
}
###############################################################################

sub VolumeLink_SendCommand($) {
    my ($hash) = @_;
    
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: SendCommand - executed with params: $hash->{httpParams}->{noshutdown}";
    
    HttpUtils_NonblockingGet($hash->{httpParams});
    
    return undef;
}
###############################################################################

sub VolumeLink_ReceiveCommand($) {
    my ($param, $err, $data) = @_;
    my $name = $param->{hash}->{NAME};
    my $interval = $param->{hash}->{interval};
    
    Log3 $name, 5, "$name: ReceiveCommand - executed";
    
    if($err ne "") {        
        if($interval > $param->{fastRetryInterval} && $err =~ /timed.out/ && $param->{HTTP_ERROR_COUNT} < 3) {
        	$interval = $param->{fastRetryInterval};
        	$param->{HTTP_ERROR_COUNT}++;
            
            readingsSingleUpdate($param->{hash},'lastHttpError',"$err #$param->{HTTP_ERROR_COUNT} of 3, do fast-retry in $interval sec.",0);
            Log3 $name, $param->{errorLoglevel}, "$name: Error while requesting ".$param->{url}." - $err - Fast-retry #$param->{HTTP_ERROR_COUNT} of 3 in $interval seconds.";
        }
        else {
            readingsSingleUpdate($param->{hash},'lastHttpError',"$err, retry in $interval sec.",0);
            Log3 $name, $param->{errorLoglevel}, "$name: Error while requesting ".$param->{url}." - $err - Retry in $interval seconds.";
        }
    }
    elsif($data ne "") {
        Log3 $name, $param->{loglevel}, "$name: url ".$param->{url}." returned: $data";
        
        $param->{HTTP_ERROR_COUNT} = 0;
        
        my ($vol) = $data =~ /$param->{hash}->{volumeRegexPattern}/si;
        my ($mute) = $data =~ /$param->{hash}->{muteRegexPattern}/si;
        if (!defined($vol)) {$vol = '';}
        if (!defined($mute)) {$mute = '';}
        
        Log3 $name, 5, "$name - volumeRegexPattern: m/$param->{hash}->{volumeRegexPattern}/si - returned:'$vol'";
        Log3 $name, 5, "$name - muteRegexPattern: m/$param->{hash}->{muteRegexPattern}/si - returned:'$mute'";
        
        if(looks_like_number($vol)) {
            if($mute =~ /true|false|0|1/i) {
                $vol = int($vol);
                Log3 $name, 5, "$name: Values O.K. - currentVolume:'$vol' - muted:'$mute' - Set it now...";
                readingsBeginUpdate($param->{hash});
                readingsBulkUpdate($param->{hash}, 'volume', $vol );
                readingsBulkUpdate($param->{hash}, 'mute', $mute );
                readingsEndUpdate($param->{hash}, 0);
                
                if( !defined($defs{$param->{hash}->{ampDevice}}) ) {
                    Log3 $name, 1, "$name: FAILURE, configured <ampDevice> '$param->{hash}->{ampDevice}' is not defined. End now...";
                    CommandSet(undef, $name.' off');
                    return;
                }
                
                my $ampMute = ReadingsVal($param->{hash}->{ampDevice},$param->{hash}->{ampMuteReading},'N/A');
                my $ampVol = ReadingsVal($param->{hash}->{ampDevice},$param->{hash}->{ampVolumeReading},'N/A');
                my $ampTitle = ( $param->{hash}->{ampInputReading} ) ? ReadingsVal($param->{hash}->{ampDevice},$param->{hash}->{ampInputReading},'N/A') : 0;
                Log3 $name, 5, "$name: Fetched amp-readings - ampMute:'$ampMute' - ampVol:'$ampVol' - ampInput:'$ampTitle'";
                
                if($ampMute eq 'N/A' || $ampVol eq 'N/A' || $ampTitle eq 'N/A') {
                    Log3 $name, 1, "$name: FAILURE, can not fetch an amp-reading! End now... - ampMute:'$ampMute' - ampVol:'$ampVol' - ampInput:'$ampTitle' ";
                    CommandSet(undef, $name.' off');
                    return;
                }
                
                if($ampTitle =~ /$param->{hash}->{ampInputReadingVal}/i || $param->{hash}->{ampInputReading} == 0) {
                    if($vol ne $ampVol) {
                        Log3 $name, 5, "$name: Set Volume on ampDevice '$param->{hash}->{ampDevice}' - newVolume:'$vol' - oldVolume:'$ampVol'.";
                        CommandSet(undef, $param->{hash}->{ampDevice}.' '.$param->{hash}->{ampVolumeCommand}.' '.$vol);
                    }
                    if($mute =~ /true|1/i && $ampMute eq $param->{hash}->{ampMuteReadingOffVal}) {
                        Log3 $name, 5, "$name: Set MuteOn on ampDevice '$param->{hash}->{ampDevice}'.";
                        CommandSet(undef, $param->{hash}->{ampDevice}.' '.$param->{hash}->{ampMuteCommand}.' '.$param->{hash}->{ampMuteReadingOnVal});
                    }
                    if($mute =~ /false|0/i && $ampMute eq $param->{hash}->{ampMuteReadingOnVal}) {
                        Log3 $name, 5, "$name: Set MuteOff on ampDevice '$param->{hash}->{ampDevice}'.";
                        CommandSet(undef, $param->{hash}->{ampDevice}.' '.$param->{hash}->{ampMuteCommand}.' '.$param->{hash}->{ampMuteReadingOffVal});
                    }
                }else {
                    Log3 $name, 5, "$name: current amp-input: '$ampTitle' not match configured input.' - Skip setting volume in this turn...";
                }
            }
            else {
                Log3 $name, 1, "$name: FAILURE, muteRegexPattern 'm/$param->{hash}->{muteRegexPattern}/si' delivers bad mute-state! Must be 0, 1, true, or false. End now... - returned:'$mute'";
                CommandSet(undef, $name.' off');
                return;
            }
        }
        else {
            Log3 $name, 1, "$name: FAILURE, volumeRegexPattern 'm/$param->{hash}->{volumeRegexPattern}/si' delivers bad volume-level (Not a number)! End now... - returned:'$vol'";
            CommandSet(undef, $name.' off');
            return;
        }
    }
    
    if($param->{hash}->{STARTED} == 1) {
        InternalTimer(time()+$interval, 'VolumeLink_SendCommand', $param->{hash}, 0);
    }
    return undef;
}
###############################################################################


1;

=pod
=begin html

<a name="VolumeLink"></a>
<h3>VolumeLink</h3>
<ul>

VolumeLink links the volume-level &amp; mute-state from a physical device (e.g. a Philips-TV) with the volume &amp; mute control of a fhem device (e.g. a SONOS-Playbar, Onkyo, Yamaha or Denon Receiver, etc.).
<br><br>

<h4>Define</h4>
<ul>
    <code>define &lt;name&gt; VolumeLink &lt;interval&gt; &lt;url&gt; &lt;ampDevice&gt; [&lt;timeout&gt; [&lt;httpErrorLoglevel&gt; [&lt;httpLoglevel&gt;]]]</code>
    <br><br>
	<br>
    &lt;interval&gt;:
    <ul>
    <code>interval to fetch current volume &amp; mute level from physical-device.</code><br>
    </ul>
    &lt;url&gt;:
    <ul>
    <code>url to fetch volume &amp; mute level, see Example below. (Example applies to many Philips TV's)</code><br>
    </ul>
    &lt;ampDevice&gt;:
    <ul>
    <code>the target fhem-device.</code><br>
    </ul>
    [&lt;timeout&gt;]:
    <ul>
    <code>optional: timeout of a http-get. default: 0.5 seconds</code><br>
    </ul>
    [&lt;httpErrorLoglevel&gt;]:
    <ul>
    <code>optional: loglevel of http-errors. default: 4</code><br>
    </ul>
    [&lt;httpLoglevel&gt;]:
    <ul>
    <code>optional: loglevel of http-messages. default: 5</code><br>
    </ul>
</ul>
<br>

<h4>Example</h4>
<ul>
    <code>define tvVolume_LivingRoom VolumeLink 0.2 http://192.168.1.156:1925/5/audio/volume Sonos_LivingRoom</code><br>
    <code>set tvVolume_LivingRoom on</code><br>
    <br>
	Note:<br>
    - This example will work out of the box with many Philips TV's and a SONOS-Playbar as fhem-device.<br>
    - Pre 2014 Philips TV's use another protocoll, which can be accessed on http://&lt;ip&gt;/1/audio/volume
    </ul>
<br>

<h4>Set</h4>
<ul>
    <code>set &lt;name&gt; &lt;on|off&gt</code><br>
    <br>
    Set on or off, to start or to stop.
</ul>
<br>

<h4>Get</h4> <ul>N/A</ul><br>


<h4>Attributes</h4>
<ul>
	Note:<br>
    - All Attributes takes effect immediately.<br>
    - The default value of volumeRegexPattern &amp; muteRegexPattern applies to many Philips-TV's, otherwise it must be configured.<br>
    - The default values of amp* applies to a SONOS-Playbar, otherwise it must be configured.<br>
    - If you don't receive a result from url, or the lastHttpErrorMessage shows every time 'timed out', try setting attribute 'httpNoShutdown' to 0.<br>
    <br>
    <li>disable &lt;1|0&gt;<br>
    With this attribute you can disable the whole module. <br>
    If set to 1 the module will be stopped and no volume will be fetched from physical-device or transfer to the amplifier-device. <br>
    If set to 0 you can start the module again with: set &lt;name&gt; on.</li>
    <li>httpNoShutdown &lt;1|0&gt;<br>
    If set to 0 the module will tell the http-server to explicit close the connection.<br>
    <i>Default: 1</i>
    </li>
    <li>ampInputReading &lt;value&gt;<br>
    Name of the Input-Reading on amplifier-device<br>
    To disable the InputCheck if your amplifier-device does not support this, set this attribute to 0.<br>
    <i>Default (which applies to SONOS-Player's): currentTitle</i></li>
    <li>ampInputReadingVal &lt;RegEx&gt;<br>
    RegEx for the Reading value of the corresponding Input-Channel on amplifier-device<br>
    <i>Default (which applies to a SONOS-Playbar's SPDIF-Input and if no Input is selected): SPDIF-Wiedergabe|^$</i></li>
    <li>ampVolumeReading &lt;value&gt;<br>
    Name of the Volume-Reading on amplifier-device<br>
    <i>Default: Volume</i></li>
    <li>ampVolumeCommand &lt;value&gt;<br>
    Command to set the volume on amplifier device<br>
    <i>Default: Volume</i></li>
    <li>ampMuteReading &lt;value&gt;<br>
    Name of the Mute-Reading on amplifier-device<br>
    <i>Default: Mute</i></li>
    <li>ampMuteReadingOnVal &lt;value&gt;<br>
    Reading value if muted<br>
    <i>Default: 1</i></li>
    <li>ampMuteReadingOffVal &lt;value&gt;<br>
    Reading value if not muted<br>
    <i>Default: 0</i></li>
    <li>ampMuteCommand &lt;value&gt;<br>
    Command to mute the amplifier device<br>
    <i>Default: Mute</i></li>
    <li>volumeRegexPattern &lt;RegEx&gt;<br>
    RegEx which is applied to url return data. Must return a number for volume-level. <br>
    <i>Default (which applies to many Phlips-TV's): current&quot;:&#92;s*(&#92;d+)</i></li>
    <li>muteRegexPattern &lt;RegEx&gt;<br>
    RegEx which is applied to url return data. Must return true, false, 1 or 0 as mute-state. <br>
    <i>Default (which applies to many Phlips-TV's): muted&quot;:&#92;s*(&#92;w+|&#92;d+)</i></li>
</ul><br>

<h4>Readings</h4>
<ul>
    Note: All VolumeLink Readings except of 'state' does not generate events!<br>
    <br>
    <li>lastHttpError<br>
    The last HTTP-Error will be recorded in this reading.<br>
    Define httpErrorLoglevel, httpLoglevel or attribute <a href="#verbose">verbose</a> for more information.<br>
    Note: Attr <a href="#verbose">verbose</a> will not output all HTTP-Messages, define httpLoglevel for this.</li>
    <li>mute<br>
    The current mute-state fetched from physical device.</li>
    <li>volume<br>
    The current volume-level fetched from physical device.</li>
    <li>state<br>
    on if VolumeLink is running, off if VolumeLink is stopped.</li>
</ul>
<br>

</ul>

=end html
=cut
