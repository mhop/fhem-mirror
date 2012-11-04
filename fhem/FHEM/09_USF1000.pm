#
#
# 09_USF1000.pm
# written by Dr. Boris Neubert 2009-06-20
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;

my $PI= 3.141592653589793238;

my $dev= "a5ce aa";

#############################
sub
USF1000_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^81..(04|0c)..0101a001a5ceaa00....";
  $hash->{DefFn}     = "USF1000_Define";
  $hash->{UndefFn}   = "USF1000_Undef";
  $hash->{ParseFn}   = "USF1000_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:0,1 " .
                        "model:usf1000s loglevel:0,1,2,3,4,5,6";

}


#############################
sub
USF1000_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u= "wrong syntax: define <name> USF1000 geometry";
  my $g= "wrong geometry for USF1000";

  # geometry (units: meter)
  #	 cub	length width height offset	cuboid			3+4
  #	 cylv	diameter height offset		vertical cylinder	3+3
  # the offset is measured from the TOP of the box!

  return $u if(int(@a)< 6);

  my $name	= $a[0];
  my $geometry	= $a[2];

  if($geometry eq "cub") {
  	# cuboid
  	return $g if(int(@a)< 7);
  	$hash->{GEOMETRY}= $geometry;
  	$hash->{LENGTH}=   $a[3];
  	$hash->{WIDTH}=    $a[4];
  	$hash->{HEIGHT}=   $a[5];
  	$hash->{OFFSET}=   $a[6];
  	$hash->{CAPACITY}= int($hash->{LENGTH}*$hash->{WIDTH}*$hash->{HEIGHT}*100.0+0.5)*10.0;
  } elsif($geometry eq "cylv") {
  	# vertical cylinder
  	return $g if(int(@a)< 6);
  	$hash->{GEOMETRY}= $geometry;
  	$hash->{DIAMETER}= $a[3];
  	$hash->{HEIGHT}=   $a[4];
  	$hash->{OFFSET}=   $a[5];
  	$hash->{CAPACITY}= int($PI*$hash->{DIAMETER}*$hash->{DIAMETER}/4.0*$hash->{HEIGHT}*100.0+0.5)*10.0;
  } else {
  	 return $g;
  }

  $modules{USF1000}{defptr}{$dev} = $hash;
  AssignIoPort($hash);
}

#############################
sub
USF1000_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{USF1000}{defptr}{$dev});
  return undef;
}

#############################
sub
USF1000_Parse($$)
{
  my ($hash, $msg) = @_;	# hash points to the FHZ, not to the USF1000

  if(!defined($modules{USF1000}{defptr}{$dev})) {
    Log 3, "USF1000 Unknown device, please define it";
    return "UNDEFINED USF1000 USF1000 cylv 1 1 0.5";
  }

  my $def= $modules{USF1000}{defptr}{$dev};
  my $name= $def->{NAME};

  return "" if(IsIgnored($name));

  my $t= TimeNow();

  # Msg format:
  # 01 23 45 67 8901 2345 6789 01 23 45 67
  # 81 0c 04 .. 0101 a001 a5ce aa 00 cc xx

  my $cc= substr($msg, 24, 2);
  my $xx= substr($msg, 26, 2);


  my $lowbattery= (hex($cc) & 0x40 ? 1 : 0);
  my $testmode=   (hex($cc) & 0x80 ? 1 : 0);
  my $distance=   hex($xx)/100.0; # in meters
  my $valid= (($distance>0.00) && ($distance<2.55));


  if($valid) {
  	my $wlevel  =   $def->{HEIGHT}-($distance-$def->{OFFSET}); # water level

	my $geometry= $def->{GEOMETRY};
  	my $capacity= $def->{CAPACITY}; # capacity of tank (for distance= offset) in liters
  	my $volume;   # current volume in tank in liters
  	my $flevel;	# fill level in percent

  	if($geometry eq "cub") {
  		# cuboid
  		$volume  = $def->{LENGTH}*$def->{WIDTH}*$wlevel*1000.0;
  	} elsif($geometry eq "cylv") {
  		# vertical cylinder
  		$volume  = $PI*$def->{DIAMETER}*$def->{DIAMETER}/4.0*$wlevel*1000.0;
  	} else {
  		return 0;
  	}

  	$flevel  = int($volume/$capacity*100.0+0.5);
  	$volume= int($volume/10.0+0.5)*10.0;

  	if($flevel>-5) {
		# reflections may lead to false reading (distance too large)
		# the meaningless results are suppressed

		my $state= sprintf("v: %d  V: %d", $flevel, $volume);

		$def->{CHANGED}[0] = $state;
		$def->{STATE} = $state;
		$def->{READINGS}{state}{TIME} = $t;
		$def->{READINGS}{state}{VAL} = $state;
		Log GetLogLevel($name, 4), "USF1000 $name: $state";

		$def->{READINGS}{distance}{TIME} = $t;
		$def->{READINGS}{distance}{VAL} = $distance;
		$def->{READINGS}{level}{TIME} = $t;
		$def->{READINGS}{level}{VAL} = $flevel;
		$def->{READINGS}{volume}{TIME} = $t;
		$def->{READINGS}{volume}{VAL} = $volume;
	}
  }

  my $warnings= ($lowbattery ? "Battery low" : "");
  if($testmode) {
  	$warnings.= "; " if($warnings);
  	$warnings.= "Test mode";
  }
  $warnings= $warnings ? $warnings : "none";

  $def->{READINGS}{"warnings"}{TIME} = $t;
  $def->{READINGS}{"warnings"}{VAL} = $warnings;

  return $name;

}

#############################

1;

=pod
=begin html

<a name="USF1000"></a>
<h3>USF1000</h3>
<ul>
  Fhem can receive your tank's fill level from the USF1000S device
  through a <a href="#FHZ">FHZ</a> device, so one must be defined first.
  The state contains the fill level in % (lower case v in the device state)
  and the current volume in liters (upper case V in the device state).
  Measured distance to the liquid's surface, fill level, volume and warnings
  (Test mode, Battery low) are available. Due to the design of the USF1000S
  protocol, you can have only one USF1000S in range of your FHZ as these
  devices cannot be distinguished.<br>
  <br>

  <a name="USF1000Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; USF1000 &lt;geometry&gt;</code>
    <br><br>

    <code>&lt;geometry&gt;</code> determines the form of the tank and the
    position of the sensor. The following geometries are currently
    supported:<br><br>
    <ul>
        <li><code>cub &lt;length&gt; &lt;width&gt; &lt;height&gt; &lt;offset&gt;</code></li>
        <li><code>cylv &lt;diameter&gt; &lt;height&gt; &lt;offset&gt;</code></li>
    </ul>
    <br>
    <code>cub</code> stands for a cuboid whose base is &lt;length&gt; &times; &lt;width&gt;.
    <code>cylv</code> stands for a vertical cylinder whose diameter is &lt;diameter&gt;.
    &lt;height&gt; is the distance of the surface of the liquid from the ground
    if the tank is full. &lt;offset&gt; is the distance of the sensor relative to
    the surface of the liquid. All quantities are expressed in meters.<br>
    <br>

    Example:<br>
    <ul>
      <code>define MyTank USF1000 cylv 2 1 0.3</code>: a cylindrical water tank with
      2 meters diameter. The water stands 1 meter high if the tank is full. The
      sensor is fixed 1,3 meters above ground.<br>
    </ul>
  </ul>
  <br>

  <a name="USF1000set"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="USF1000get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="USF1000attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a> (usf1000s)</li>
    <li><a href="#ignore">ignore</a></li>
  </ul>
  <br>

</ul>
=end html
=cut
