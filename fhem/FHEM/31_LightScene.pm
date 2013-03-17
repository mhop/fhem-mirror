
package main;

use strict;
use warnings;
use POSIX;
use JSON::XS;

sub LightScene_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "LightScene_Define";
  $hash->{NotifyFn} = "LightScene_Notify";
  $hash->{UndefFn}  = "LightScene_Undefine";
  $hash->{SetFn}    = "LightScene_Set";
  $hash->{GetFn}    = "LightScene_Get";
}

sub LightScene_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> LightScene <device>+"  if(@args < 3);

  my $name = shift(@args);
  my $tyoe = shift(@args);

  my %list;
  foreach my $a (@args) {
    foreach my $d (devspec2array($a)) {
      $list{$d} = 1;
    }
  }
  $hash->{CONTENT} = \%list;

  my %scenes;
  $hash->{SCENES} = \%scenes;

  LightScene_Load($hash);

  $hash->{STATE} = 'Initialized';

  return undef;
}

sub LightScene_Undefine($$)
{
  my ($hash,$arg) = @_;

  LightScene_Save();

  return undef;
}

sub
LightScene_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");

  if( grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}) ) {
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
    LightScene_Save();
  }

  return undef;
}

sub
myStatefileName()
{
  my $statefile = $attr{global}{statefile};
  $statefile = substr $statefile,0,rindex($statefile,'/')+1;
  return $statefile ."LightScenes.save";
}
my $LightScene_LastSaveTime="";
sub
LightScene_Save()
{
  my $time_now = TimeNow();
  return if( $time_now eq $LightScene_LastSaveTime);
  $LightScene_LastSaveTime = $time_now ;

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = myStatefileName();

  my $hash;
  for my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "LightScene");
    next if( !defined($defs{$d}{SCENES}) );

    $hash->{$d} = $defs{$d}{SCENES} if( keys(%{$defs{$d}{SCENES}}) );
  }

  if(open(FH, ">$statefile")) {
    my $t = localtime;
    print FH "#$t\n";

    print FH encode_json($hash) if( defined($hash) );

    close(FH);
  } else {

    my $msg = "LightScene_Save: Cannot open $statefile: $!";
    Log 1, $msg;
  }

  return undef;
}
sub
LightScene_Load($)
{
  my ($hash) = @_;

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = myStatefileName();

  if(open(FH, "<$statefile")) {
    my $json;
    while (my $line = <FH>) {
      chomp $line;
      next if($line =~ m/^#.*$/);
      $json .= $line;
    }

    close(FH);

    return if( !defined($json) );

    my $decoded = decode_json( $json );

    if( defined($decoded->{$hash->{NAME}}) ) {
      $hash->{SCENES} = $decoded->{$hash->{NAME}};
    }
  } else {
    my $msg = "LightScene_Load: Cannot open $statefile: $!";
    Log 1, $msg;
  }
  return undef;
}


sub
LightScene_Set($@)
{
  my ($hash, $name, $cmd, $value, @a) = @_;
  my $ret = "";

  if( !defined($cmd) ){ return "$name: set needs at least one parameter" };

  if( $cmd eq "?" ){ return "Unknown argument ?, choose one of save scene:".join(",", sort keys %{$hash->{SCENES}}) };

  if( $cmd eq "save" && !defined( $value ) ) { return "Usage: set save <scene_name>" };
  if( $cmd eq "scene" && !defined( $value ) ) { return "Usage: set scene <scene_name>" };
  if( $cmd eq "remove" && !defined( $value ) ) { return "Usage: set remove <scene_name>" };

  if( $cmd eq "remove" ) {
    delete( $hash->{SCENES}{$value} );
    return undef;
  };


  $hash->{INSET} = 1;

  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    next if(!$defs{$d});
    if($defs{$d}{INSET}) {
      Log 1, "ERROR: endless loop detected for $d in " . $hash->{NAME};
      next;
    }

    if( $cmd eq "save" ) {
      my $status = "";
      if( $defs{$d}{TYPE} eq 'CUL_HM' ) {
        my $subtype = AttrVal($d,"subType","");
        if( $subtype eq "switch" ) {
          $status = Value($d);
        } elsif( $subtype eq "dimmer" ) {
          $status = Value($d);
        }
      } elsif( $defs{$d}{TYPE} eq 'FS20' ) {
          $status = Value($d);
      } elsif( $defs{$d}{TYPE} eq 'HUEDevice' ) {
        my $subtype = AttrVal($d,"subType","");
        if( $subtype eq "switch" || Value($d) eq "off" ) {
          $status = Value($d);
        } elsif( $subtype eq "dimmer" ) {
          $status = "bri ". ReadingsVal($d,'bri',"0");
        } elsif( $subtype eq "colordimmer" ) {
          $status = "bri ". ReadingsVal($d,'bri',"0") ." : xy ". ReadingsVal($d,'xy',"");
        }
      } elsif( $defs{$d}{TYPE} eq 'IT' ) {
        my $subtype = AttrVal($d,"model","");
        if( $subtype eq "itswitch" ) {
          $status = Value($d);
        } elsif( $subtype eq "itdimmer" ) {
          $status = Value($d);
        }
      } elsif( $defs{$d}{TYPE} eq 'TRX_LIGHT' ) {
        $status = Value($d);
      } else {
        $status = Value($d);
      }

      $hash->{SCENES}{$value}{$d} = $status;
      $ret .= $d .": ". $status ."\n";

    } elsif ( $cmd eq "scene" ) {
      $hash->{STATE} = $value;
      $ret .= " ". CommandSet(undef,"$d $hash->{SCENES}{$value}{$d}");
    } else {
      $ret = "Unknown argument $cmd, choose one of save scene";
    }
  }

  delete($hash->{INSET});
  Log GetLogLevel($hash->{NAME},5), "SET: $ret" if($ret);

  return $ret;

  return undef;
}

sub
LightScene_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];
  if( $cmd eq "scene" && @a < 3 ) { return "Usage: get scene <scene_name>" };

  my $ret = "";
  if( $cmd eq "scenes" ) {
    foreach my $scene (sort keys %{ $hash->{SCENES} }) {
      $ret .= $scene ."\n";
    }
    return $ret;
  } elsif( $cmd eq "scene" ) {
    my $ret = "";
    my $scene = $a[2];
    if( defined($hash->{SCENES}{$scene}) ) {
      foreach my $device (sort keys %{ $hash->{SCENES}{$scene} }) {
        $ret .= $device .": ". $hash->{SCENES}{$scene}{$device} ."\n";
      }
    } else {
        $ret = "no scene <$scene> defined";
    }
    return $ret;
  }

  return "Unknown argument $cmd, choose one of scenes scene";
}

1;

=pod
=begin html

<a name="LightScene"></a>
<h3>LightScene</h3>
<ul>
  Allows to store the state of a group of lights and other devices and recall it later. Multiple states for one group can be stored.

  <br><br>
  <a name="LightScene_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LightScene [&lt;dev1&gt;] [&lt;dev2&gt;] [&lt;dev3&gt;] ... </code><br>
    <br>

    Examples:
    <ul>
      <code>define light_group LightScene Lampe1 Lampe2 Dimmer1</code><br>
    </ul>
  </ul><br>

  <a name="LightScene_Set"></a>
    <b>Set</b>
    <ul>
      <li>save &lt;scene_name&gt;<br>
      save current state for alle devices in this LightScene to &lt;scene_name&gt;</li>
      <li>scene &lt;scene_name&gt;<br>
      shows scene &lt;scene_name&gt; - all devices are switched to the previously saved state</li>
      <li>remove &lt;scene_name&gt;<br>
      remove &lt;scene_name&gt; from list of saved scenes</li>
    </ul><br>

  <a name="LightScene_Get"></a>
    <b>Get</b>
    <ul>
      <li>scenes</li>
      <li>scene &lt;scene_name&gt;</li>
    </ul><br>

</ul><br>

=end html
=cut
