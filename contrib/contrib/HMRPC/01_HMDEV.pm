################################################
# HMRPC Device Handler
# Written by Oliver Wagner <owagner@vapor.com>
#
# V0.5
#
################################################
#
# This module handles individual devices via the
# HMRPC provider.
#
package main;

use strict;
use warnings;

sub
HMDEV_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^HMDEV .* .* .*";
  $hash->{DefFn}     = "HMDEV_Define";
  $hash->{ParseFn}   = "HMDEV_Parse";
  $hash->{SetFn}     = "HMDEV_Set";
  $hash->{GetFn}     = "HMDEV_Get";
  $hash->{AttrList}  = "IODev do_not_notify:0,1";
}

#############################
sub
HMDEV_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  return "wrong syntax: define <name> HMDEV deviceaddress" if int(@a)!=3;
  
  my $addr=$a[2];

  $hash->{hmaddr}=$addr;
  $modules{HMDEV}{defptr}{$addr} = $hash;
  AssignIoPort($hash);
  
  if($hash->{IODev}->{NAME})
  {
  	Log 5,"Assigned $name to $hash->{IODev}->{NAME}";
  }
 
  return undef;
}



#############################
sub
HMDEV_Parse($$)
{
  my ($hash, $msg) = @_;
  
  my @mp=split(" ",$msg);
  my $addr=$mp[1];
  my $attrid=$mp[2];
  
  $hash=$modules{HMDEV}{defptr}{$addr};
  
  if(!$hash)
  {
  	# If not explicitely defined, reroute this event to the main device
  	# with a suffixed attribute name
  	$addr=~s/:([0-9]{1,2})//;
  	my $subdev=$1;
  	if($subdev>0)
  	{
  		$attrid.="_$subdev";
  	}
  	$hash=$modules{HMDEV}{defptr}{$addr};
  }
  
  if(!$hash)
  {
  	  Log(2,"Received callback for unknown device $msg");
  	  return "UNDEFINED HMDEV_$addr HMDEV $addr";
  }
  
  # Let's see whether we can update our devinfo now
  if(!defined $hash->{devinfo})
  {
  	  $hash->{hmdevinfo}=$hash->{IODev}{devicespecs}{$addr};
	  $hash->{hmdevtype}=$hash->{hmdevinfo}{TYPE};	  
  }
  
  #
  # Ok update the relevant reading
  #
  my @changed;
  my $currentval=$hash->{READINGS}{$attrid}{VAL};
  $hash->{READINGS}{$attrid}{TIME}=TimeNow();
  # Note that we always trigger a change on PRESS_LONG/PRESS_SHORT events
  # (they are sent whenever a button is pressed, and there is no change back)
  # We also never trigger a change on the RSSI readings, for efficiency purposes
  if(!defined $currentval || ($currentval ne $mp[3]) || ($attrid =~ /^PRESS_/))
  {
  	if(defined $currentval && !($currentval =~ m/^RSSI_/))
  	{
		push @changed, "$attrid: $mp[3]";
	}
	$hash->{READINGS}{$attrid}{VAL}=$mp[3];
	# Also update the STATE
	my $state="";
	foreach my $key (sort(keys(%{$hash->{READINGS}})))
	{
		if(length($state))
		{
			$state.="  ";
		}
		$state.=$key.": ".$hash->{READINGS}{$key}{VAL};
	}
	$hash->{STATE}=$state;
  }
  $hash->{CHANGED}=\@changed;
  
  return $hash->{NAME};
}

################################
sub
HMDEV_Set($@)
{
	my ($hash, @a) = @_;

	return "invalid set call @a" if(@a != 3 && @a != 4);
	# We delegate this call to the HMRPC IODev, after having added the device address
	if(@a==4)
	{
		return HMRPC_Set($hash->{IODev},$hash->{IODev}->{NAME},$hash->{hmaddr},$a[1],$a[2],$a[3]);
	}
	else
	{
		return HMRPC_Set($hash->{IODev},$hash->{IODev}->{NAME},$hash->{hmaddr},$a[1],$a[2]);
	}
}

################################
sub
HMDEV_Get($@)
{
	my ($hash, @a) = @_;
	return "argument missing, usage is <attribute> @a" if(@a!=2);
	# Like set, we simply delegate to the HMPRC IODev here
	return HMRPC_Get($hash->{IODev},$hash->{IODev}->{NAME},$hash->{hmaddr},$a[1]);
}

1;
