##############################################
#
# This is open source software licensed unter the Apache License 2.0
# http://www.apache.org/licenses/LICENSE-2.0
#
##############################################

package VenetianBlinds::VenetianMasterController;
use v5.14;
use strict;
use warnings;
use experimental "smartmatch";
use VenetianBlinds::Shared;

# Map the condition codes from yahoo to cloudiness index, 
# makes it easier to implement thresholds as higher number indicates more clouds
# https://developer.yahoo.com/weather/documentation.html
# https://de.wikipedia.org/wiki/Bew%C3%B6lkung#Einteilung_des_Flugwetterdienstes

my $yahoo_code_map = {
	#TODO: add mapping for more codes	
	23 => 4, # blustery
	24 => 4, # windy
	26 => 5, # cloudy
    28 => 6, # mostly cloudy (day)
    30 => 3, # partly cloudy (day)
    32 => 1, # sunny 
    34 => 2, # fair (day)
    36 => 0, # hot
    38 => 5, #scattered thunderstorms
    39 => 5, #scattered thunderstorms
};

sub Define{
	my ($hash,$a,$h) = @_;

	if (!defined $h->{twilight}) {
		return "Mandatory argument 'twilight=<name>' is missing or undefined";
	}	
	$hash->{twilight} = $h->{twilight};

	if (!defined $h->{weather}) {
		return "Mandatory argument 'weather=<name>' is missing or undefined";
	}	
	$hash->{weather} = $h->{weather};

	if (!defined $h->{wind_speed_threshold}) {
		return "Mandatory argument 'wind_speed_threshold=<value>' is missing or undefined";
	}	
    $hash->{wind_speed_threshold} = $h->{wind_speed_threshold};

    $hash->{STATE} = "OK";
	return;
}

sub Set{
	my ($hash,$a,$h) = @_;
	my $cmd = $a->[1];
	if ($cmd eq "?"){
		return "trigger_update:noArg stop:noArg automatic:noArg";
	} elsif ($cmd eq "trigger_update") {
		trigger_update($hash);
	} elsif ($cmd eq "stop") {
    VenetianBlinds::Shared::send_to_all("stop");   
    } elsif ($cmd eq "automatic") {
    VenetianBlinds::Shared::send_to_all("automatic");   
	} else {
		return "unknown command $cmd";
	}
	return;
}


sub Notify{
	my ($hash, $devName, $events) = @_;
	if ($devName eq $hash->{twilight}) {
		update_twilight($hash);
	} elsif ($devName eq $hash->{weather}){
		update_weather($hash);
		check_wind_alarm($hash);
	}
	
	#foreach my $event (@{$events}) {
	#  	$event = "" if(!defined($event));
	#		main::Log(3,"Event on device $devName: $event");
	#}
	return;		
}

sub trigger_update {
	my ($hash) = @_;
	update_twilight($hash);
	update_calendar($hash);
	update_weather($hash);
	check_wind_alarm($hash);
	return
	
}

sub update_twilight{
	my ($hash) = @_;
	# TODO: reduce number of events: only trigger event if data has changed
	main::readingsBeginUpdate($hash);
	main::readingsBulkUpdate($hash, "sun_elevation",
		main::ReadingsVal($hash->{twilight}, "elevation", undef) );
	main::readingsBulkUpdate($hash, "sun_azimuth",
		main::ReadingsVal($hash->{twilight}, "azimuth", undef) );
	main::readingsEndUpdate($hash, 1);
	return;
}

sub update_calendar{
	my ($hash) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    # Note: months start at 0 = January
    $mon +=1;
    my $current = main::ReadingsVal($hash->{NAME}, "month", undef);    
	if ($mon != $current){
		main::readingsSingleUpdate($hash,"month",$mon,1);		
	}
	#TODO: do the update exactly at midnight
	main::InternalTimer(main::gettimeofday()+24*60*60, "VenetianMasterController::update_calendar", $hash, 1);        
	return ;
}

sub update_weather{
	my ($hash) = @_;
	my $condition_code = main::ReadingsVal($hash->{weather}, "code", undef);
	if (!defined $condition_code) {
        main::Log(1,"could not get Weather condition code from '$hash->{weather}'");
    }
    my $cloud_index = undef;
	$cloud_index = $yahoo_code_map->{$condition_code};
	if (!defined $cloud_index){
		$cloud_index = 9;
	};
    my $wind_speed = main::ReadingsVal($hash->{weather}, "wind_speed", undef);
    if (!defined $wind_speed) {
        main::Log(1,"could not get Weather wind_speed from '$hash->{weather}'");
    }
	
	# TODO: reduce number of events: only trigger event if data has changed
	main::readingsBeginUpdate($hash);	
	main::readingsBulkUpdate($hash, "wind_speed", $wind_speed);
	main::readingsBulkUpdate($hash, "cloud_index", $cloud_index);
	main::readingsEndUpdate($hash, 1);
	
	return;
}

sub check_wind_alarm{
	my ($hash) = @_;
	my $windspeed = main::ReadingsVal($hash->{NAME}, "wind_speed", undef);
	my $windalarm = main::ReadingsVal($hash->{NAME}, "wind_alarm", undef);
	given ($windalarm) {
		when (0) {
			if (($windspeed >= $hash->{wind_speed_threshold})){
				main::Log(3,"Wind alarm: $windspeed km/h");
				main::readingsSingleUpdate($hash,"wind_alarm",1,1);		
				VenetianBlinds::Shared::send_to_all("wind_alarm");	
				$hash->{STATE} = "wind alarm";		
			} 
		}

		when (1) {
			if (($windspeed >= $hash->{wind_speed_threshold})){
				main::readingsSingleUpdate($hash,"wind_alarm",1,1);		
			} else {
				if (main::ReadingsAge($hash->{NAME},"wind_speed",undef) > 600) {
					main::readingsSingleUpdate($hash,"wind_alarm",0,1);		
					main::Log(3,"Wind alarm ended.");
                    $hash->{STATE} = "normal";      
				}
			}						
		}
        when (undef) {
		    main::readingsSingleUpdate($hash,"wind_alarm",0,0);		
        }
	}
	return;
}


1;

