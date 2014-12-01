##############################################
# $Id$
##############################################
package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "reset" => "noArg",
  "offset"=> "",
);

my %gets = (
  "position" => "noArg",
  "offset"   => "noArg",
  "value"    => "noArg",
);

sub
FRM_ROTENC_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_ROTENC_Set";
  $hash->{GetFn}     = "FRM_ROTENC_Get";
  $hash->{AttrFn}    = "FRM_ROTENC_Attr";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_ROTENC_Init";
  $hash->{UndefFn}   = "FRM_ROTENC_Undef";
  $hash->{StateFn}   = "FRM_ROTENC_State";

  $hash->{AttrList}  = "IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_ROTENC_Init($$)
{
	my ($hash,$args) = @_;

	my $u = "wrong syntax: define <name> FRM_ROTENC pinA pinB [id]";
  	return $u unless defined $args and int(@$args) > 1;
 	my $pinA = @$args[0];
 	my $pinB = @$args[1];
 	my $encoder = defined @$args[2] ? @$args[2] : 0;
 	my $name = $hash->{NAME};
 	
	$hash->{PINA} = $pinA;
	$hash->{PINB} = $pinB;
	
	$hash->{ENCODERNUM} = $encoder;
	
	eval {
		FRM_Client_AssignIOPort($hash);
		my $firmata = FRM_Client_FirmataDevice($hash);
		$firmata->encoder_attach($encoder,$pinA,$pinB);
		$firmata->observe_encoder($encoder, \&FRM_ROTENC_observer, $hash );
	};
	if ($@) {
		$@ =~ /^(.*)( at.*FHEM.*)$/;
		$hash->{STATE} = "error initializing: ".$1;
		return "error initializing '$name': $1";
	}

	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "position";
	}

  $hash->{offset} = ReadingsVal($name,"position",0);

	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_ROTENC_observer
{
	my ( $encoder, $value, $hash ) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,5,"onEncoderMessage for pins ".$hash->{PINA}.",".$hash->{PINB}." encoder: ".$encoder." position: ".$value."\n");
	main::readingsBeginUpdate($hash);
	main::readingsBulkUpdate($hash,"position",$value+$hash->{offset}, 1);
	main::readingsBulkUpdate($hash,"value",$value, 1);
	main::readingsEndUpdate($hash,1);
}

sub
FRM_ROTENC_Set
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  my $command = $a[1];
  my $value = $a[2];
  if(!defined($sets{$command})) {
  	my @commands = ();
    foreach my $key (sort keys %sets) {
      push @commands, $sets{$key} ? $key.":".join(",",$sets{$key}) : $key;
    }
    return "Unknown argument $a[1], choose one of " . join(" ", @commands);
  }
  COMMAND_HANDLER: {
    $command eq "reset" and do {
      eval {
        FRM_Client_FirmataDevice($hash)->encoder_reset_position($hash->{ENCODERNUM});
      };
      main::readingsBeginUpdate($hash);
      main::readingsBulkUpdate($hash,"position",$hash->{offset},1);
      main::readingsBulkUpdate($hash,"value",0,1);
      main::readingsEndUpdate($hash,1);
      last;
    };
    $command eq "offset" and do {
      $hash->{offset} = $value;
      readingsSingleUpdate($hash,"position",ReadingsVal($hash->{NAME},"value",0)+$value,1);
      last;
    };
  }
}

sub
FRM_ROTENC_Get($)
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  my $command = $a[1];
  my $value = $a[2];
  if(!defined($gets{$command})) {
  	my @commands = ();
    foreach my $key (sort keys %gets) {
      push @commands, $gets{$key} ? $key.":".join(",",$gets{$key}) : $key;
    }
    return "Unknown argument $a[1], choose one of " . join(" ", @commands);
  }
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "position" and do {
      return ReadingsVal($hash->{NAME},"position","0");
    };
    $cmd eq "offset" and do {
      return $hash->{offset};
    };
    $cmd eq "value" and do {
      return ReadingsVal($hash->{NAME},"value","0");
    };
  }
  return undef;
}

sub
FRM_ROTENC_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            FRM_Client_AssignIOPort($hash,$value);
            FRM_Init_Client($hash) if (defined ($hash->{IODev}));
          }
          last;
        };
      }
    }
  };
  if ($@) {
    $@ =~ /^(.*)( at.*FHEM.*)$/;
    $hash->{STATE} = "error setting $attribute to $value: ".$1;
    return "cannot $command attribute $attribute to $value for $name: ".$1;
  }
}

sub
FRM_ROTENC_Undef($$)
{
  my ($hash, $name) = @_;
  my $pinA = $hash->{PINA};
  my $pinB = $hash->{PINB};
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->encoder_detach($hash->{ENCODERNUM});
    $firmata->pin_mode($pinA,PIN_ANALOG);
    $firmata->pin_mode($pinB,PIN_ANALOG);
  };
  if ($@) {
    eval {
      my $firmata = FRM_Client_FirmataDevice($hash);
      $firmata->pin_mode($pinA,PIN_INPUT);
      $firmata->digital_write($pinA,0);
      $firmata->pin_mode($pinB,PIN_INPUT);
      $firmata->digital_write($pinB,0);
    };
  }
  return undef;
}

sub
FRM_ROTENC_State($$$$)
{
  my ($hash, $tim, $sname, $sval) = @_;
  if ($sname eq "position") {
    $hash->{offset} = $sval;
  }
  return undef;
}

1;

=pod
=begin html

<a name="FRM_ROTENC"></a>
<h3>FRM_ROTENC</h3>
<ul>
  represents a rotary-encoder attached to two pins of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a><br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_ROTENCdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_ROTENC &lt;pinA&gt; &lt;pinB&gt; [id]</code> <br>
  Defines the FRM_ROTENC device. &lt;pinA&gt> and &lt;pinA&gt> are the arduino-pins to use.<br>
  [id] is the instance-id of the encoder. Must be a unique number per FRM-device (rages from 0-4 depending on Firmata being used, optional if a single encoder is attached to the arduino).<br>
  </ul>
  
  <br>
  <a name="FRM_ROTENCset"></a>
  <b>Set</b><br>
    <li>reset<br>
    resets to value of 'position' to 0<br></li>
    <li>offset &lt;value&gt;<br>
    set offset value of 'position'<br></li>
  <a name="FRM_ROTENCget"></a>
  <b>Get</b>
  <ul>
    <li>position<br>
    returns the position of the rotary-encoder attached to pinA and pinB of the arduino<br>
    the 'position' is the sum of 'value' and 'offset'<br></li>
    <li>offset<br>
    returns the offset value<br>
    on shutdown of fhem the latest position-value is saved as new offset.<br></li>
    <li>value<br>
    returns the raw position value as it's reported by the rotary-encoder attached to pinA and pinB of the arduino<br>
    this value is reset to 0 whenever Arduino restarts or Firmata is reinitialized<br></li>
  </ul><br>
  <a name="FRM_ROTENCattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut
