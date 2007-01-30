##############################################
# Switching the FHTs with e.g. a Button
##############################################

# This is only an example.

# After pressing e.g. a button it will change the values 
# of desired-temp against the value of windowopen-temp

# With small changes it is possible to change e.g. all FHTs to
# 2 degrees less if you are leaving the house and activating 
# the alarm system.

# Don't change the values very often within a time because the FHT seems 
# to hang if there are too much values within a time.
# 
# Add something like the following lines to the configuration file :
#       notifyon NameOfButton {MyFHTswitch("NameOfFHT")}
# and put this file in the <modpath>/FHZ1000 directory.


# Martin Haas 
##############################################


package main;
use strict;
use warnings;
 


sub
FHTswitch_Initialize($)
{
#  my ($hash) = @_; ## for fhz1000 >3.0
#  $hash->{Category} = "none";  ## for fhz1000 >3.0

 my ($hash, $init) = @_; ## for fhz1000 <=3.0
  $hash->{Type} = "none"; ## for fhz1000 <=3.0
}



###### ok, let's learn perl ;-)...
sub
MyFHTswitch($)
{
    my $str;
    my $fhtorder;
    my @a = @_;
    my $fht=$a[0];
    my @windowopentemp;
    my @desiredtemp;

    no strict "refs";
    $str = &{$devmods{$defs{$a[0]}{TYPE}}{ListFn}}($defs{$a[0]});
    my @lines = split("\n", $str);
    use strict "refs";

  foreach my $l (@lines) {
        my ($date, $time, $attr, $val) = split(" ", $l, 4);
	if($attr eq "desired-temp")
	{
		Log 3, "old $attr  of $a[0]: $val";
		@desiredtemp = split(" ", $val);
	}
	if($attr eq "windowopen-temp")
	{
		Log 3, "old $attr of $a[0]:  $val";
		@windowopentemp = split(" ", $val);
	}
  }
	$fhtorder="set $fht desired-temp $windowopentemp[0] ";
	fhz "$fhtorder";
	$fhtorder="set $fht windowopen-temp $desiredtemp[0] ";
	fhz "$fhtorder";
	fhz "set $fht refreshvalues";
}

1;
