##############################################
#
# This is open source software licensed unter the Apache License 2.0
# http://www.apache.org/licenses/LICENSE-2.0
#
##############################################

# $Id$

use v5.10.1;
use strict;
use warnings;
use POSIX;
use experimental "smartmatch";


#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use VenetianBlinds::VenetianMasterController;
use VenetianBlinds::VenetianRoomController;
use VenetianBlinds::VenetianBlindController;

my %valid_types = (
	"master" =>"VenetianMasterController",
	"room" => "VenetianRoomController",
	"blind" => "VenetianBlindController",
	);

sub Venetian_Initialize {
    my ($hash) = @_;
    $hash->{DefFn}      = 'Venetian_Define';
    #$hash->{UndefFn}    = 'Venetian_Undef';
    $hash->{SetFn}      = 'Venetian_Set';
    #$hash->{GetFn}      = 'Venetian_Get';
    #$hash->{AttrFn}     = 'Venetian_Attr';
    #$hash->{ReadFn}     = 'Venetian_Read';    
    $hash->{NotifyFn}     = 'Venetian_Notify';
    $hash->{parseParams} = 1;
    return;
}

sub Venetian_Define {
    my ($hash, $a, $h) = @_;	
	$hash->{type} = $valid_types{$h->{type}};
	if (!defined $hash->{type}) {
		return "Type $h->{type} is not supported!";
	}
	return vbc_call("Define",$hash, $a, $h);
}

sub Venetian_Set {	
	my ( $hash, $a,$h ) = @_;
	my $result = undef;
	return vbc_call("Set",$hash, $a, $h);
}


sub Venetian_Notify {	
    my ($own_hash, $dev_hash) = @_;
    my $ownName = $own_hash->{NAME}; # own name / hash	
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
	
    my $devName = $dev_hash->{NAME}; # Device that created the events
    my $events = main::deviceEvents($dev_hash,1);
    return if( !$events );
    
	return vbc_call("Notify",$own_hash, $devName, $events);
}

sub vbc_call{
	my ($func,$hash,$a,$h) = @_;
	$func = "VenetianBlinds::$hash->{type}::$func";
	my $result;
	{
		## no critic (ProhibitNoStrict)
		no strict 'refs';
		$result = &$func($hash, $a, $h);
		## use critic
	}
	return $result;	
}
1;

=pod
=item summary automates venetian blinds depending on sun and weather
=begin html

<a name="Venetian"></a>
<h3>Venetian</h3>
<ul>
	<i>Venetian</i> implements a fully automated solution to control venetian blinds. 
	It will consinder lots of input data to set the blinds as a human being would do.
	It use the sun position (from Twilight) the weather (from Weather) and orientation of the blinds.
	The blinds are opened automatically if the wind speed exceeds a user defined threshold.
	<br/><br/>
	<b>Note:</b> Venetian only works with Fibaro FGM-222 controllers!
	<br/><br/>
	A minimal set up consists of two devices: one <i>Master</i> and one <i>Blind</i>. 
	The <i>Master</i> will collect global data from your installation while the <i>Blind</i> will control the actual device.
	For each physical device a <i>Blind</i> device must be defined.
	<br/><br/>
	You can add an optional device <i>Room</i> to control all <i>Blinds</i> in one room with one click.
	For this to work your <i>Blinds</i> must be mapped to rooms with the standard attribute "room".
	<br/><br/>
	<a name="Venetian_Define"></a>
	<b>Define</b>
	<ul>
		Master:<br/> 
		<code>define  &lt;name&gt; Venetian type=master twilight=&lt;name&gt; weather=&lt;name&gt; wind_speed_threshold=&lt;value&gt;</code>
		<br/><br/>
		
		Room: <br/>
		<code>define  &lt;name&gt; Venetian type=room	&#91;rooms=&lt;name&gt;,&lt;name&gt;,...	&#93;</code> 
		<br/><br/>
		
		Blind: <br/>
		<code>define  &lt;name&gt; Venetian type=blind master=&lt;name&gt; device=&lt;name&gt; could_index_threshold=&lt;number&gt; azimuth=&lt;start&gt;-&lt;end&gt; elevation=&lt;start&gt;-&lt;end&gt; months=&lt;start&gt;-&lt;end&gt;</code>
		<br/><br/>
		
		<b>Parameters (common)</b>
		<ul>
			<li/>type<br/>
				is one of the values "master", "room" or "blind".
		</ul>
		<b>Parameters (Master)</b>
		<ul>
			<li/>twilight<br/>
				Name of the <a href="#Twilight">Twilight</a> device. 
				This is used to get the current position of the sun.
			<li/>weather<br/>
				Name of the <a href="#Weather">Weather</a> device.
				This is used to get the weather reports
			<li/>wind_speed_threshold<br/>
				Maximum wind speed in km/h the venetian blinds are designed for.
				If the measured wind speed exceed this threshold, the blinds are opened automatically to prevent damages.
		</ul>
		<b>Parameters (Blind)</b>
		<ul>
			<li/>master</br>
				name of the Venetian "Master" device.
			<li/>device</br>
				name of the blind controller (Fibaro FGM-222) to be controlled.
			<li/>could_index_threshold</br>
				Threshold for the cloudiness, as defined in <a href="https://de.wikipedia.org/wiki/Bew%C3%B6lkung">Wikipedia</a>.
				The scale is 0 (clear sky) to 8 (overcast), where 9 is unknown.
				The blinds are lowered only the the current cloud index is <i>below</i> this number.
				<br/>
				Example: <code>could_index_threshold=5</code> means broken 
			<li/>azimuth</br>
				The range of the azimuth of the sun, in which the blinds shall be closed.
				This is measured in degrees.
				This is defined by the pyhiscal orientation of your window.
				You can use a compass to measure this for every window.
				<br/>
				Example: <code>azimuth=90-120</code> means from 90° to 120° 
			<li/>elevation</br>
				The range of the elevation of the sun, in which the blinds shall be closed.
				This is measured in degrees.
				You can guess this from the pyhsical localtion of your window and obstacles around your building.
				<br/>
				Example: <code>azimuth=10-90</code> means from 10° to 90°
			<li/>months</br>
				The range of months in which the blinds shall be closed, e.g. summer.
				<br/>
				Example: <code>azimuth=5-10</code> means from May to October
		</ul>
		<b>Parameters (Room)</b>
		<ul>
			<li/>rooms (optional)</br>
				Comma separated list of rooms in which this device shall control the blinds.
				If this is not defined, the rooms from the Attribute of this device are used. 
				<br/>
				Example: <code>rooms=Kitchen,Living</code> means that all blinds in the rooms named "Kitchen" and "Living" are controlled.
		</ul>
	</ul>
    <a name="Venetian_Set"></a>
    <b>Set</b>
    <ul>
        <b>Blind:</b>
        <ul>
            <li/><code>set automatic</code></br>
                Set blinds to automatic mode. This is the normal mode, if blinds should be set accoring to the sun position.
            <li/><code>set stop</code></br>
                Stop the blind movement
            <li/><code>set windalarm</code></br>
                Trigger the wind alarm. This will cause the blinds to be opened, regardless of the current state.
            <li/><code>set &lt;scene&gt;</code></br>
                Disable the automatic and set a scene manually. The currently available scenes are:
                <ul>
                    <li/><code>open</code><br/> 
                        Fully open the binds.
                    <li/><code>closed</code> <br/>
                        Fully close the blinds and slats.
                    <li/><code>see_through</code> <br/>
                        Fully close the blinds and set the slats horizontally, so that you can still <i>see through</i>.
                    <li/><code>shaded</code><br/> 
                        Close the blinds and slightly close the slats. This is the scene when the automatic closes the blinds.
                    <li/><code>adaptive</code><br/>
                        <b>Experimental!</b> Tries to set the slats so that they are just closed enough so that the sun does not get in. 
                        This takes the elevation of the sun and geometry of the slats into consideration. 
                </ul>
        </ul>
        <b>Room:</b>
        <ul>
            <li/><code>set automatic</code></br>
                Set all blinds in this room to automatic mode. 
            <li/><code>set stop</code></br>
                Stop all blinds in this room.
            <li/><code>set &lt;scene&gt;</code></br>
                Set all blinds in this room to a certain scene.
        </ul>
        <b>Master:</b>
        <ul>
            <li/><code>set automatic</code></br>
                Set all blinds to automatic mode. 
            <li/><code>set stop</code></br>
                Stop all blinds.
            <li/><code>set trigger_update</code></br>
                Trigger all blinds in automatic mode to update their scenes to the current sun position. 
                This should not be neccesary in normal operation but is useful when trying our different parameters.
        </ul>
    </ul>

<!-- there are get operations at the moment     
    <a name="Venetian_Get"></a>
    <b>Get</b>
    <ul>
        TODO
    </ul>
-->

<!-- there are not attributes at the moment     
    <a name="Venetian_Attributes"></a>
    <b>Set</b>
    <ul>
        TODO
    </ul>
-->

</ul>

=end html
=cut

