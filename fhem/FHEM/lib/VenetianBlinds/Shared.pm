##############################################
#
# This is open source software licensed unter the Apache License 2.0
# http://www.apache.org/licenses/LICENSE-2.0
#
##############################################

package VenetianBlinds::Shared;
use v5.14;
use strict;
use warnings;
use experimental "smartmatch";
use base 'Exporter';


# constants #############################################
use constant scenes => {
    "open" => {
        "blind" => 99,
        "slat" => 99,   
    },
    "closed" => {
        "blind" => 0,
        "slat" => 0,   
    },
    "see_through" => {
        "blind" => 0,
        "slat" => 50,   
    },
    "shaded" => {
        "blind" => 0,
        "slat" => 30,   
    },
    "adaptive" => {
        "blind" => 0,
        "slat" => "adaptive",   
    },    
};

our @EXPORT_OK = ('scenes');

# functions #############################################

sub send_to_all{
    my ($cmd) = @_;
    foreach my $device (find_devices()) {
        main::fhem("set $device $cmd");         
    }
}

sub find_devices_in_room {
    my ($my_room) = @_;
    my @result = ();
    my @devices = find_devices();
    foreach my $device (@devices){
    	my $rooms = main::AttrVal($device,"room",undef);
    	if (defined $rooms){
	        foreach my $room (split(/,/, $rooms)){
	            if ($my_room eq $room){
	                push(@result,$device);
	            }
	        }
    	} else {
    		main::Log(3,"Blinds '$device' not mapped to a room");
    	}
    }	
    return @result;
}


sub find_devices{
    my $devstr = main::fhem("list .* type");
    my @result = ();
    foreach my $device (split /\n/, $devstr) {
        $device =~ s/^\s+|\s+$//g; # trim white spaces
        if( length($device) > 0){ 
            $device =~ /^(\S+)\s+(\S+)$/;
            my $devname = $1;
            my $model = $2;
            if ($model eq "VenetianBlindController"){
                push(@result,$devname);
            }
        }
    }
    return @result;
}


1;