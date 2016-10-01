##############################################
#
# This is open source software licensed unter the Apache License 2.0
# http://www.apache.org/licenses/LICENSE-2.0
#
##############################################

package VenetianBlinds::VenetianRoomController;

use v5.10.1;
use strict;
use warnings;
use experimental "smartmatch";
use VenetianBlinds::Shared;


# fhem interface #############################################
sub Define{
    my ($hash,$a,$h) = @_;
    $hash->{STATE} = "OK";
    if (defined $h->{rooms}) {
        $hash->{rooms} = $h->{rooms};
    }
    return;
}

sub Notify {
    my ($hash, $devName, $events) = @_;
    return;
}

sub Set{
    my ($hash,$a,$h) = @_;
    my $cmd = $a->[1];
    my @scene_list = keys %{&VenetianBlinds::Shared::scenes};
    given ($cmd) {
    	when ("?") {
	        my $result = "automatic:noArg stop:noArg automatic:noArg"; 
	        foreach my $scene (@scene_list){
	            $result .= " $scene:noArg";
		        }
	        return $result;
        }
        when ("automatic") {
        	send_to_all_in_my_rooms($hash, "automatic");
        }
        when ("stop"){
            send_to_all_in_my_rooms($hash, "stop");
        }
        when (@scene_list){
            send_to_all_in_my_rooms($hash, $cmd);
        }
        default {
        	return "Unkown command $cmd";
        }
    }
    return;
}

# room logic #############################################

sub send_to_all_in_my_rooms{
    my ($hash, $cmd) = @_;
    foreach my $room ( get_my_rooms($hash) ){
        foreach my $device (VenetianBlinds::Shared::find_devices_in_room($room)) {
             main::fhem("set $device $cmd");         
        }
    }
}

sub send_to_all_in_room{
    my ($cmd,$room) = @_;
    foreach my $device (find_devices_in_room($room)) {
        main::fhem("set $device $cmd");         
    }
}

sub get_my_rooms{
    my ($hash) = @_;
    
    my $rooms = undef;  
    if (defined $hash->{rooms}){
        $rooms = $hash->{rooms};        
    } else {
        $rooms = main::AttrVal($hash->{NAME},"room",undef);
    }
    if (!defined $rooms) {
    	main::Log(1,"Error reading rooms for VenetianRoomController '$hash->{NAME}'");
    	return;
    }
    return split(/,/,$rooms);
}

1;
