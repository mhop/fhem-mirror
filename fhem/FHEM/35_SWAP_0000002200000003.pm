
# $Id$
package main;

use strict;
use warnings;

use Color;

use constant  CMD_REG => '0F';

use constant  { CMD_NOOP       => '00',
                RET_OK         => '05',
                RET_ERR        => '06',
                CMD_On         => '10',
                CMD_Off        => '11',
                CMD_DimUp      => '12',
                CMD_DimDown    => '13',
                CMD_OnForTimer => '14',
                CMD_Toggle     => '20',
                CMD_GetIR      => '30',
                CMD_SetIR      => '31',
                CMD_LearnIR    => '32',
                CMD_GetFade    => '40',
                CMD_SetFade    => '41',
                CMD_StartFade  => '42',
                CMD_RESET      => 'FF',  };

my %dim_values = (
   0 => "dim06%",
   1 => "dim12%",
   2 => "dim18%",
   3 => "dim25%",
   4 => "dim31%",
   5 => "dim37%",
   6 => "dim43%",
   7 => "dim50%",
   8 => "dim56%",
   9 => "dim62%",
  10 => "dim68%",
  11 => "dim75%",
  12 => "dim81%",
  13 => "dim87%",
  14 => "dim93%",
);


sub
SWAP_0000002200000003_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/34_SWAP.pm";
  require "$attr{global}{modpath}/FHEM/31_HUEDevice.pm";

  $hash->{SWAP_SetFn}     = "SWAP_0000002200000003_Set";
  $hash->{SWAP_SetList}   = { off => 0, on => 0, "on-for-timer" => 1, fadeTo => 2,
                              "rgb:colorpicker,RGB" => 1,
                              toggle => 0,
                              dimUp => 0, dimDown => 0,
                              getIR => 1, setIR => 2, learnIR => 1, storeIR => 3,
                              getFade => 1, setFade => 3, startFade => 2,
                              reset => 0 };
  $hash->{SWAP_GetFn}     = "SWAP_0000002200000003_Get";
  $hash->{SWAP_GetList}   = { devStateIcon => 0, rgb => 0, RGB => 0, pct => 0,
                              listIR => 0,
                              listFade => 0 };
  $hash->{SWAP_ParseFn}   = "SWAP_0000002200000003_Parse";

  my $ret = SWAP_Initialize($hash);

  $hash->{AttrList} .= " color-icons:1,2";

  #$hash->{FW_summaryFn} = "SWAP_0000002200000003_summaryFn";

  $data{webCmdFn}{colorpicker} = "FHEM_colorpickerFn";
  $data{FWEXT}{"/"}{SCRIPT} = "/jscolor/jscolor.js";

  return $ret;
}

sub
SWAP_0000002200000003_devStateIcon($@)
{
  my($hash,$state) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $name = $hash->{NAME};
  my $rgb = CommandGet("","$name rgb");
  $rgb = $state if( $state );
  $state = ReadingsVal($name,"state","unknown") if( !$state );

  return undef if( !defined($attr{$name}{ProductCode}) );
  return undef if( $attr{$name}{ProductCode} ne '0000002200000003' );

  return ".*:light_question" if( $state eq "unknown" || $state =~m/^set/ );

  return undef if( $state eq "off" );

  my ($pct,$RGB) = SWAP_0000002200000003_rgbToPct($rgb);
  my $s = $dim_values{int($pct/7)};

  return ".*:$s@#".$RGB.":toggle" if( $pct < 100 && AttrVal($name, "color-icons", 2) == 2 );
  return ".*:on@#".$rgb.":toggle" if( AttrVal($name, "color-icons", 2) != 0 );

  return ".*:on@#".$rgb.":toggle";

  return '<div style="width:32px;height:19px;'.
         'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';"></div>';
}

sub
SWAP_0000002200000003_summaryFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $name = $hash->{NAME};

  return SWAP_0000002200000003_devStateIcon( $hash );
}

sub
SWAP_0000002200000003_Watchdog($)
{
  my ($hash) = @_;
  readingsSingleUpdate($hash, "state", "unknown", 1);
}

sub
SWAP_0000002200000003_Parse($$$$)
{
  my ($hash, $reg, $func, $data) = @_;
  my $name = $hash->{NAME};

  if( $reg == 0x00 ) {
    my $productcode = $data;
    $attr{$name}{devStateIcon} = '{(SWAP_0000002200000003_devStateIcon($name),"toggle")}' if( $productcode eq '0000002200000003'&& !defined( $attr{$name}{devStateIcon} ) );
    $attr{$name}{webCmd} = 'rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:toggle:on:off' if( $productcode eq '0000002200000003'&& !defined( $attr{$name}{webCmd} ) );
  } elsif( $reg == hex(CMD_REG) ) {
    if( defined($hash->{waiting_for_ir_cmd}) ) {
      my $ir_reg = $hash->{ir_reg}->[$hash->{waiting_for_ir_cmd}];
      $ir_reg->{command} = $data;
      delete($hash->{waiting_for_ir_cmd});
    } else {
      my $cmd = substr( $data, 0, 2 );
      if( $cmd eq "30" ) {
        my $reg = substr( $data, 2, 2 );
        my $ir_value = substr( $data, 4, 8 );
        my %ir_reg;
        $ir_reg{ir_value} = $ir_value;
        $hash->{ir_reg}->[hex($reg)] = \%ir_reg;
        $hash->{waiting_for_ir_cmd} = hex($reg);
      }
      elsif( $cmd eq CMD_GetFade || $cmd eq CMD_SetFade ) {
        my $reg = substr( $data, 2, 2 );
        my $fade_rgb = substr( $data, 4, 6 );
        my $fade_time = substr( $data, 10, 2 );
        my %fade_reg;
        $fade_reg{fade_rgb} = $fade_rgb;
        $fade_reg{fade_time} = $fade_time;
        $hash->{fade_reg}->[hex($reg)] = \%fade_reg;
      }
    }
  } elsif( $reg == 0x0B ) {
    CommandTrigger( "", "$name RGB: $data" );
  }

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+hex($hash->{'SWAP_0A-PeriodicTxInterval'})+10, "SWAP_0000002200000003_Watchdog", $hash, 1) if( defined $hash->{'SWAP_0A-PeriodicTxInterval'} );
}

sub
SWAP_0000002200000003_Set($@)
{
  my ($hash, $name, $cmd, $arg, $arg2, $arg3) = @_;

  InternalTimer(gettimeofday()+10, "SWAP_0000002200000003_Watchdog", $hash, 1);

  #$cmd = (ReadingsVal( $name, "0B-RGBlevel", "FFFFFF" ) eq "000000" ? "on" :"off") if( $cmd eq "toggle" );

  if( $cmd eq "on" ) {
    return( "regSet", CMD_REG, CMD_On."FFFFFF0000" );
  } elsif( $cmd eq "on-for-timer" ) {
    return( "regSet", CMD_REG, CMD_OnForTimer. sprintf( "%04X",$arg ) ."000000" ) if( $arg =~ /^\d{1,4}$/ );
    return (undef, "$arg not a valid time" );
  } elsif( $cmd eq "off" ) {
    return( "regSet", CMD_REG, CMD_Off."0000000000" );
  } elsif( $cmd eq "toggle" ) {
    return( "regSet", CMD_REG, CMD_Toggle."0000000000" );
  } elsif( $cmd eq "rgb" ) {
    return( "regSet", CMD_REG, CMD_On.$arg."0000" ) if( $arg =~ /^[\da-f]{6}$/i );
    return (undef, "$arg is not a valid rgb color" );
  } elsif( $cmd eq "fadeTo" ) {
    return (undef, "$arg2 not a valid time" ) if( $arg2 !~ /^\d{1,2}$/ );
    return( "regSet", CMD_REG, CMD_On.$arg.sprintf( "%02X",$arg2 )."00" ) if( $arg =~ /^[\da-f]{6}$/i );
    return (undef, "$arg is not a valid rgb color" );
  } elsif( $cmd eq "dimUp" ) {
    return( "regSet", CMD_REG, CMD_DimUp."0000000000" );
  } elsif( $cmd eq "dimDown" ) {
    return( "regSet", CMD_REG, CMD_DimDown."0000000000" );
  } elsif( $cmd eq "getIR" ) {
    if( $arg eq "all" ) {
      for( my $reg = 0; $reg <= 0xF; ++$reg) {
        SWAP_Send($hash, $hash->{addr}, "02", CMD_REG, CMD_GetIR."0".sprintf("%1X",$reg)."00000000" );
      }
      return undef;
    }
    return( "regSet", CMD_REG, CMD_GetIR."0".sprintf("%1X",$arg)."00000000" ) if( $arg =~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg is not a valid ir register number" );
  } elsif( $cmd eq "setIR" ) {
    return (undef, "$arg2 not a valid ir value" )if( $arg2 !~ /^[\da-f]{8}$/i );
    return( "regSet", CMD_REG, CMD_SetIR."0".sprintf("%1X",$arg).$arg2 ) if( $arg =~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg is not a valid ir register" );
  } elsif( $cmd eq "learnIR" ) {
    return( "regSet", CMD_REG, CMD_LearnIR."0".sprintf("%1X",$arg)."00000000" ) if( $arg =~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg is not a valid ir register number" );
  } elsif( $cmd eq "storeIR" ) {
    return (undef, "$arg is not a valid ir register number" ) if( $arg !~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg2 not a valid ir value" )if( $arg2 !~ /^[\da-f]{8}$/i );
    return (undef, "$arg3 not a valid command" ) if( $arg3 !~ /^[\da-f]{12}$/i );
    SWAP_Send($hash, $hash->{addr}, "02", CMD_REG, CMD_SetIR."0".sprintf("%1X",$arg).$arg2 );
    SWAP_Send($hash, $hash->{addr}, "02", CMD_REG, $arg3 );
    return( "regSet", CMD_REG, CMD_GetIR."0".sprintf("%1X",$arg)."00000000" );
  } elsif( $cmd eq "getFade" ) {
    if( $arg eq "all" ) {
      for( my $reg = 0; $reg <= 0xF; ++$reg) {
        SWAP_Send($hash, $hash->{addr}, "02", CMD_REG, CMD_GetFade."0".sprintf("%1X",$reg)."00000000" );
      }
      return undef;
    }
    return( "regSet", CMD_REG, CMD_GetFade."0".sprintf("%1X",$arg)."00000000" ) if( $arg =~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg is not a valid fade register number" );
  } elsif( $cmd eq "setFade" ) {
    return (undef, "$arg2 not a valid rgb value" ) if( $arg2 !~ /^[\da-f]{6}$/i );
    return (undef, "$arg3 not a valid time value" ) if( $arg3 !~ /^[\da-f]{1,3}$/i );
    return( "regSet", CMD_REG, CMD_SetFade."0".sprintf("%1X",$arg).$arg2.sprintf( "%02X",$arg3 ) ) if( $arg =~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg not a valid fade register" );
  } elsif( $cmd eq "startFade" ) {
    return (undef, "$arg is not a valid fade register number" ) if( $arg !~ /^(\d|0\d|1[0-5])$/ );
    return( "regSet", CMD_REG, CMD_StartFade."0".sprintf("%1X",$arg)."0".sprintf( "%1X",$arg2 )."000000" ) if( $arg2 =~ /^(\d|0\d|1[0-5])$/ );
    return (undef, "$arg2 not a valid fade register number" );
  } elsif( $cmd eq "reset" ) {
    return( "regSet", CMD_REG, CMD_RESET."0000000000" );
  }

  return undef;
}

sub
SWAP_0000002200000003_max($@)
{
  my ($max, @vars) = @_;
  for (@vars) {
    $max = $_ if $_ > $max;
  }
  return $max;
}

sub
SWAP_0000002200000003_rgbToPct($)
{
  my ($rgb) = @_;

  $rgb = "000000" if( $rgb eq "off" );
  $rgb = "FFFFFF" if( $rgb eq "on" );

  if( $rgb =~ m/([\da-f]{2})([\da-f]{2})([\da-f]{2})/i ) {
    my( $r, $g, $b ) = (hex($1), hex($2), hex($3));
    my $f  = SWAP_0000002200000003_max($r,$g,$b);
    my $p = $f / 2.55;
    $f = 255.0 / $f if( $f > 0 );
    return (int($p), sprintf( "%02x%02x%02x", $f*$r, $f*$g, $f*$b ));
  }

 return (0,undef) ;
}
sub
SWAP_0000002200000003_Get($@)
{
  my ($hash, $name, $cmd, @a) = @_;

  if( $cmd eq 'rgb' ) {
    return ReadingsVal( $name, "0B-RGBlevel", undef );
  } elsif( $cmd eq 'RGB' ) {
     my ($pct,$RGB) = SWAP_0000002200000003_rgbToPct(ReadingsVal( $name, "0B-RGBlevel", undef));
    return $RGB;
  } elsif( $cmd eq 'pct' ) {
     my ($pct,$RGB) = SWAP_0000002200000003_rgbToPct(ReadingsVal( $name, "0B-RGBlevel", undef));
     return $pct + " ";
  } elsif( $cmd eq 'devStateIcon' ) {
    return SWAP_0000002200000003_devStateIcon( $hash );
  } elsif( $cmd eq 'listIR' ) {
    my $ret = "no ir registers known";

    if( defined($hash->{ir_reg}) ) {
      $ret = "known ir registers:\n";
      $ret .= sprintf( "%s\t%s\t%s\n", "reg", "ir_value", "command" );

      for( my $reg = 0; $reg <= 0xF; ++$reg) {
        if( defined($hash->{ir_reg}->[$reg]) ) {
          $ret .= sprintf( "%02i\t%8s\t%s\n", $reg, $hash->{ir_reg}->[$reg]->{ir_value}, $hash->{ir_reg}->[$reg]->{command} );
        }
      }
    }

    return $ret;
  } elsif( $cmd eq 'listFade' ) {
    my $ret = "no fade registers known";

    if( defined($hash->{fade_reg}) ) {
      $ret = "known fade registers:\n";
      $ret .= sprintf( "%s\t%s\t%s\n", "reg", "rgb", "time" );

      for( my $reg = 0; $reg <= 0xF; ++$reg) {
        if( defined($hash->{fade_reg}->[$reg]) ) {
          $ret .= sprintf( "%02i\t%6s\t%4s\n", $reg, $hash->{fade_reg}->[$reg]->{fade_rgb}, $hash->{fade_reg}->[$reg]->{fade_time} );
        }
      }
    }

    return $ret;
  }

  return undef;
}

1;

=pod
=begin html

<a name="SWAP_0000002200000003"></a>
<h3>SWAP_0000002200000003</h3>
<ul>

  <tr><td>
  Module for the justme version of the panstamp rgb driver board with ir (sketch product code 0000002200000003).

  <br><br>
  to learn an ir command the simplest way ist to use 'learnIR #'. the on board led will start to blink indicating ir learning mode. after an ir command is received the blinking will switch to slow and the boards waits for a fhem command (on/off/...) and will link the ir command to the fhem command.
  <br><br>
  received ir commands that will not trigger one of the 16 possible learned commands will be send as SWAP register 0C to fhem and can be used in notifys.
  <br><br>
  SWAP register 0E will configure the power on state of the board: off, configured color, last color before power down.
  <br><br>

  <a name="SWAP_0000002200000003_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SWAP_0000002200000003 &lt;ID&gt; 0000002200000003</code> <br>
    <br>
  </ul>
  <br>

  <a name="SWAP_0000002200000003_Set"></a>
  <b>Set </b>
  all SWAP set commands and:
  <ul>
    <li>on<br>
        </li>
    <li>on-for-timer &lt;time&gt;<br>
        </li>
    <li>off<br>
        </li>
    <li>toggle<br>
        </li><br>

    <li>rgb &lt;RRGGBB&gt;<br>
        set the led color
        </li><br>

    <li>dimUP<br>
        </li>
    <li>dimDown<br>
        </li><br>

    <li>setIR # &lt;code&gt;<br>
        </li>
    <li>learnIR #<br>
        </li>
    <li>storeIR # &lt;code&gt; &lt;command&gt;<br>
        </li><br>

    <li>getIR # | all<br>
        read content of IR regisgter # or all IR registers
        </li><br>

    <li>setFade &lt;RRGGBB&gt; &lt;time&gt;<br>
      stores color and time in fede register #
        </li><br>

    <li>startFade &lt;#1&gt; &lt;#2&gt;<br>
        starts an endless fading loop over all fading registers [#1..#2]
        </li><br>

    <li>getFade # | all<br>
        read content of fade regisgter # or all fade regisgters
        </li><br>

    <li><a href="#setExtensions"> set extensions</a> are supported.</li>
  </ul><br>

  <a name="SWAP_0000002200000003_Get"></a>
  <b>Get</b>
  all SWAP get commands and:
  <ul>
    <li>rgb<br>
        returns the current led color
        </li><br>
    <li>listIR<br>
        list all IR registers of this device. use getIR first.
        </li><br>
    <li>listFade<br>
        list all fade registers. use getFade first.
        </li><br>
  </ul><br>

  <a name="SWAP_0000002200000003_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>color-icon<br>
      1 -> use lamp color as icon color and 100% shape as icon shape<br>
      2 -> use lamp color scaled to full brightness as icon color and dim state as icon shape</li>
    <li>ProductCode<br>
      must be 0000002200000003</li><br>
  </ul><br>
</ul>

=end html
=cut
