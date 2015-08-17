###############################################################################
# $Id: 70_VolumeLink.pm 2015-08-17 08:00 - rapster - rapster at x0e.de $

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
                        .$readingFnAttributes;
}
###############################################################################

sub VolumeLink_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    return "Wrong syntax: use define <name> VolumeLink <interval> <url> <ampDevice> [<timeout> [<httpErrorLoglevel> [<httpLoglevel>]]]" if(int(@a) < 5);
    
    my $name = $a[0];

    %$hash = (                  %$hash,
        STARTED                 => $hash->{STARTED} || 0,
        interval                => $a[2],
        url                     => $a[3],
        ampDevice               => $a[4],
        timeout                 => $a[5] || 1,
        httpErrorLoglevel       => $a[6] || 4,
        httpLoglevel            => $a[7] || 5,
        volumeRegexPattern      => $attr{$name}{volumeRegexPattern} || qr/current":(\d+).*muted":(\w+|\d+)/,
        ampInputReading         => $attr{$name}{ampInputReading} || 'currentTitle',
        ampInputReadingVal      => $attr{$name}{ampInputReadingVal} || qr/SPDIF-Wiedergabe|^$/,
        ampVolumeReading        => $attr{$name}{ampVolumeReading} || 'Volume',
        ampVolumeCommand        => $attr{$name}{ampVolumeCommand} || 'Volume',
        ampMuteReading          => $attr{$name}{ampMuteReading} || 'Mute',
        ampMuteReadingOnVal     => $attr{$name}{ampMuteReadingOnVal} || 1,
        ampMuteReadingOffVal    => $attr{$name}{ampMuteReadingOffVal} || 0,
        ampMuteCommand          => $attr{$name}{ampMuteCommand} || 'Mute'
    );
    $hash->{httpParams} = {
        HTTP_ERROR_COUNT  => 0,
        fastRetryInterval => 0.1,
        hash              => $hash,
        url               => $hash->{url},
        timeout           => $hash->{timeout},
        noshutdown        => 1,
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
        $defs{$name}{ampInputReading} 		= $attr_value      if($attr_name eq 'ampInputReading');
        $defs{$name}{ampInputReadingVal} 	= qr/$attr_value/  if($attr_name eq 'ampInputReadingVal');
        $defs{$name}{ampVolumeReading} 		= $attr_value      if($attr_name eq 'ampVolumeReading');
        $defs{$name}{ampVolumeCommand} 		= $attr_value      if($attr_name eq 'ampVolumeCommand');
        $defs{$name}{ampMuteReading} 		= $attr_value      if($attr_name eq 'ampMuteReading');
        $defs{$name}{ampMuteReadingOnVal} 	= $attr_value      if($attr_name eq 'ampMuteReadingOnVal');
        $defs{$name}{ampMuteReadingOffVal}	= $attr_value      if($attr_name eq 'ampMuteReadingOffVal');
        $defs{$name}{ampMuteCommand} 		= $attr_value      if($attr_name eq 'ampMuteCommand');
        $defs{$name}{volumeRegexPattern} 	= qr/$attr_value/  if($attr_name eq 'volumeRegexPattern');
    }
    elsif($cmd eq "del") {
        $defs{$name}{ampInputReading} 	    = 'currentTitle'          if($attr_name eq 'ampInputReading');
        $defs{$name}{ampInputReadingVal}    = qr/SPDIF-Wiedergabe|^$/ if($attr_name eq 'ampInputReadingVal');
        $defs{$name}{ampVolumeReading} 	    = 'Volume'                if($attr_name eq 'ampVolumeReading');
        $defs{$name}{ampVolumeCommand} 	    = 'Volume'                if($attr_name eq 'ampVolumeCommand');
        $defs{$name}{ampMuteReading} 	    = 'Mute'                  if($attr_name eq 'ampMuteReading');
        $defs{$name}{ampMuteReadingOnVal}   = '1'                     if($attr_name eq 'ampMuteReadingOnVal');
        $defs{$name}{ampMuteReadingOffVal}  = '0'                     if($attr_name eq 'ampMuteReadingOffVal');
        $defs{$name}{ampMuteCommand} 	    = 'Mute'                  if($attr_name eq 'ampMuteCommand');
        $defs{$name}{volumeRegexPattern}    = qr/current":(\d+).*muted":(\w+|\d+)/	if($attr_name eq 'volumeRegexPattern');
    }
    return undef;
}
###############################################################################

sub VolumeLink_SendCommand($) {
    my ($hash) = @_;
    
    Log3 $hash->{NAME}, 5, "$hash->{NAME}: SendCommand - executed";
    
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
        
        my($vol,$mute) = $data =~ /$param->{hash}->{volumeRegexPattern}/m;
        $vol = int($vol);
        
        if(looks_like_number($vol) && $mute =~ /true|false|0|1/i) {
            Log3 $name, 5, "$name: currentVolume: '$vol' - muted: '$mute' - Set it now...";
            readingsBeginUpdate($param->{hash});
            readingsBulkUpdate($param->{hash}, 'volume', $vol );
            readingsBulkUpdate($param->{hash}, 'mute', $mute );
            readingsEndUpdate($param->{hash}, 0);
            
            my $ampMute = ReadingsVal($param->{hash}->{ampDevice},$param->{hash}->{ampMuteReading},'N/A');
            my $ampVol = ReadingsVal($param->{hash}->{ampDevice},$param->{hash}->{ampVolumeReading},'N/A');
            my $ampTitle = ReadingsVal($param->{hash}->{ampDevice},$param->{hash}->{ampInputReading},'N/A');
            
            if($ampMute eq 'N/A' || $ampVol eq 'N/A' || $ampTitle eq 'N/A') {
                Log3 $name, 1, "$name: FAILURE, can not fetch an amp-reading! End now... - ampMute:'$ampMute' - ampVol:'$ampVol' - ampInput:'$ampTitle' ";
                CommandSet(undef, $name.' off');
                return;
            }
            
            if($ampTitle =~ /$param->{hash}->{ampInputReadingVal}/i) {
                if($vol ne $ampVol) {
                    CommandSet(undef, $param->{hash}->{ampDevice}.' '.$param->{hash}->{ampVolumeCommand}.' '.$vol);
                }
                if($mute =~ /true|1/i && $ampMute eq $param->{hash}->{ampMuteReadingOffVal}) {
                    CommandSet(undef, $param->{hash}->{ampDevice}.' '.$param->{hash}->{ampMuteCommand}.' '.$param->{hash}->{ampMuteReadingOnVal});
                }
                if($mute =~ /false|0/i && $ampMute eq $param->{hash}->{ampMuteReadingOnVal}) {
                    CommandSet(undef, $param->{hash}->{ampDevice}.' '.$param->{hash}->{ampMuteCommand}.' '.$param->{hash}->{ampMuteReadingOffVal});
                }
            }else {
                Log3 $name, 5, "$name: current amp-input: '$ampTitle' not match configured input.' - Skip setting volume in this turn...";
            }
        }
        else {
            Log3 $name, 1, "$name: FAILURE, volumeRegexPattern delivers bad volume or mute state! End now... - volume/\$1:'$vol' - mute/\$2:'$mute'";
            
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

VolumeLink links the volume &amp; mute from a physical device (e.g. a Philips-TV) with the volume &amp; mute control of a fhem device (e.g. a SONOS-Playbar, Onkyo, Yamaha or Denon Receiver, etc.).
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
    <code>the amplifier fhem-device.</code><br>
    </ul>
    [&lt;timeout&gt;]:
    <ul>
    <code>optional: timeout of a http-get. default: 1 second</code><br>
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
	Note: This example will work out of the box with many Philips TV's and a SONOS-Playbar as fhem-device.<br><br>
    <code>define tvVolume_LivingRoom VolumeLink 0.2 http://192.168.1.156:1925/5/audio/volume Sonos_LivingRoom</code><br>
    <code>set tvVolume_LivingRoom on</code><br>
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
    - The default value of volumeRegexPattern applies to many Philips-TV's, otherwise it must be configured.<br>
    - The default values of amp* applies to a SONOS-Playbar, otherwise it must be configured.<br>
    <br>
    <li>disable &lt;1|0&gt;<br>
    With this attribute you can disable the whole module. <br>
    If set to 1 the module will be stopped and no volume will be fetched from physical-device or transfer to the amplifier-device. <br>
    If set to 0 you can start the module again with: set &lt;name&gt; on.</li>
    <li>ampInputReading &lt;value&gt;<br>
    Name of the Input-Reading on amplifier-device<br>
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
    RegEx which is applied to url return data.<br>
    Must return a number in $1 for volume-level and true, false, 1 or 0 as mute-state in $2. <br>
    <i>Default (which applies to many Phlips-TV's): current&quot;:(&#92;d+).*muted&quot;:(&#92;w+|&#92;d+)</i></li>
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
