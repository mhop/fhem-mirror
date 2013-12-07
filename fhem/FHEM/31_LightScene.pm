
# $Id$

package main;

use strict;
use warnings;
use POSIX;
#use JSON;
use Data::Dumper;

use vars qw(%FW_webArgs); # all arguments specified in the GET

my $LightScene_hasJSON = 1;

sub LightScene_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "LightScene_Define";
  $hash->{NotifyFn} = "LightScene_Notify";
  $hash->{UndefFn}  = "LightScene_Undefine";
  $hash->{SetFn}    = "LightScene_Set";
  $hash->{GetFn}    = "LightScene_Get";

  $hash->{FW_detailFn}  = "LightScene_detailFn";

  addToAttrList("lightSceneParamsToSave");

  eval "use JSON";
  $LightScene_hasJSON = 0 if($@);
}

sub LightScene_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> LightScene <device>+"  if(@args < 3);

  my $name = shift(@args);
  my $type = shift(@args);

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
LightScene_2html($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $name = $hash->{NAME};
  my $room = $FW_webArgs{room};

  my $show_heading = 1;

  my $row = 1;
  my $ret = "";
  $ret .= "<table>";
  $ret .= "<tr><td><div class=\"devType\"><a href=\"$FW_ME?detail=$name\">".AttrVal($name, "alias", $name)."</a></div></td></tr>" if( $show_heading );
  $ret .= "<tr><td><table class=\"block wide\">";

  $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
  $row++;
  $ret .= "<td><div></div></td>";
  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    $ret .= "<td><div class=\"col2\"><a href=\"$FW_ME?detail=$d\">". AttrVal($d, "alias", $d) ."</a></div></td>";
  }

  if( defined($FW_webArgs{detail}) ) {
    $room = "&detail=$FW_webArgs{detail}";

    $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
    $row++;
    $ret .= "<td><div></div></td>";
    foreach my $d (sort keys %{ $hash->{CONTENT} }) {
      my %extPage = ();
      my ($allSets, $cmdlist, $txt) = FW_devState($d, $room, \%extPage);
      $ret .= "<td informId=\"$d\">$txt</td>";
    }
  }

  foreach my $scene (sort keys %{ $hash->{SCENES} }) {
    $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
    $row++;

    my $srf = $room ? "&room=$room" : "";
    $srf = $room if( $room && $room =~ m/^&/ );
    my $link = "cmd=set $name scene $scene";
    my $txt = $scene;
    if( 1 ) {
      my ($icon, $link, $isHtml) = FW_dev2image($name, $scene);
      $txt = ($isHtml ? $icon : FW_makeImage($icon, $scene)) if( $icon );
    }
    if( AttrVal($FW_wname, "longpoll", 1)) {
      $txt = "<a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$link')\">$txt</a>";
    } else {
      $txt = "<a href=\"$FW_ME$FW_subdir?$link$srf\">$txt</a>";
    }
    $ret .= "<td><div>$txt</div></td>";

    foreach my $d (sort keys %{ $hash->{CONTENT} }) {
      if( !defined($hash->{SCENES}{$scene}{$d} ) ) {
        $ret .= "<td><div></div></td>";
        next;
      }

      my $icon;
      my $state = $hash->{SCENES}{$scene}{$d};
      $icon = $state->{icon} if( ref($state) eq 'HASH' );
      $state = $state->{state} if( ref($state) eq 'HASH' );

      my ($isHtml);
      $isHtml = 0;

      if( !$icon ) {
        my ($link);
        ($icon, $link, $isHtml) = FW_dev2image($d, $state);
      }
      $icon = FW_iconName($state) if( !$icon );

      if( $icon ) {
        $ret .= "<td><div class=\"col2\">". ($isHtml ? $icon : FW_makeImage($icon, $state)) ."</div></td>";
      } else {
        $ret .= "<td><div>". $state ."</div></td>";
      }
    }
  }

  $ret .= "</table></td></tr>";
  $ret .= "</table>";
  $ret .= "</br>";

  return $ret;
}
sub
LightScene_detailFn()
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return LightScene_2html($d);
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

  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if($s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      my ($old, $new) = ($1, $2);
      if( defined($hash->{CONTENT}{$old}) ) {

        $hash->{DEF} =~ s/(\s*)$old(\s*)/$1$new$2/;

        foreach my $scene (keys %{ $hash->{SCENES} }) {
          $hash->{SCENES}{$scene}{$new} = $hash->{SCENES}{$scene}{$old} if( defined($hash->{SCENES}{$scene}{$old}) );
          delete( $hash->{SCENES}{$scene}{$old} );
        }

        delete( $hash->{CONTENT}{$old} );
        $hash->{CONTENT}{$new} = 1;
      }
    } elsif($s =~ m/^DELETED ([^ ]*)$/) {
      my ($name) = ($1);

      if( defined($hash->{CONTENT}{$name}) ) {

        $hash->{DEF} =~ s/(\s*)$name(\s*)/ /;
        $hash->{DEF} =~ s/^ //;
        $hash->{DEF} =~ s/ $//;

        foreach my $scene (keys %{ $hash->{SCENES} }) {
          delete( $hash->{SCENES}{$scene}{$name} );
        }

        delete( $hash->{CONTENT}{$name} );
      }
    }
  }

  return undef;
}

sub
myStatefileName()
{
  my $statefile = $attr{global}{statefile};
  $statefile = substr $statefile,0,rindex($statefile,'/')+1;
  return $statefile ."LightScenes.save" if( $LightScene_hasJSON );
  return $statefile ."LightScenes.dd.save";
}
my $LightScene_LastSaveTime="";
sub
LightScene_Save()
{
  my $time_now = TimeNow();
  return if( $time_now eq $LightScene_LastSaveTime);
  $LightScene_LastSaveTime = $time_now;

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

    if( $LightScene_hasJSON ) {
      print FH encode_json($hash) if( defined($hash) );
    } else {
      my $dumper = Data::Dumper->new([]);
      $dumper->Terse(1);

      $dumper->Values([$hash]);
      print FH $dumper->Dump;
    }

    close(FH);
  } else {

    my $msg = "LightScene_Save: Cannot open $statefile: $!";
    Log3 undef, 1, $msg;
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
    my $encoded;
    while (my $line = <FH>) {
      chomp $line;
      next if($line =~ m/^#.*$/);
      $encoded .= $line;
    }
    close(FH);

    return if( !defined($encoded) );

    my $decoded;
    if( $LightScene_hasJSON ) {
      $decoded = decode_json( $encoded );
    } else {
      $decoded = eval $encoded;
    }
    $hash->{SCENES} = $decoded->{$hash->{NAME}} if( defined($decoded->{$hash->{NAME}}) );
  } else {
    my $msg = "LightScene_Load: Cannot open $statefile: $!";
    Log3 undef, 1, $msg;
  }
  return undef;
}


sub
LightScene_Set($@)
{
  my ($hash, $name, $cmd, $scene, @a) = @_;
  my $ret = "";

  if( !defined($cmd) ){ return "$name: set needs at least one parameter" };

  if( $cmd eq "?" ){ return "Unknown argument ?, choose one of remove:".join(",", sort keys %{$hash->{SCENES}}) ." save set scene:".join(",", sort keys %{$hash->{SCENES}})};

  if( $cmd eq "save" && !defined( $scene ) ) { return "Usage: set $name save <scene_name>" };
  if( $cmd eq "scene" && !defined( $scene ) ) { return "Usage: set $name scene <scene_name>" };
  if( $cmd eq "remove" && !defined( $scene ) ) { return "Usage: set $name remove <scene_name>" };

  if( $cmd eq "remove" ) {
    delete( $hash->{SCENES}{$scene} );
    return undef;
  } elsif( $cmd eq "set" ) {
    my ($d, @args) = @a;

    if( !defined( $scene ) || !defined( $d ) || !@args ) { return "Usage: set $name set <scene_name> <device> <cmd>" };
    return "no stored scene >$scene<" if( !defined($hash->{SCENES}{$scene} ) );
    return "device >$d< is not a member of scene >$scene<" if( !defined($hash->{CONTENT}{$d} ) );

    $hash->{SCENES}{$scene}{$d} = join(" ", @args);
    return undef;
  }


  $hash->{INSET} = 1;

  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    next if(!$defs{$d});
    if($defs{$d}{INSET}) {
      Log3 $name, 1, "ERROR: endless loop detected for $d in " . $hash->{NAME};
      next;
    }

    if( $cmd eq "save" ) {
      my $state = "";
      my $icon = undef;
      my $type = $defs{$d}->{TYPE};
      $type = "" if( !defined($type) );

      if( my $toSave = AttrVal($d,"lightSceneParamsToSave","") ) {
        $icon = Value($d);
        if( $toSave =~ m/^{.*}$/) {
          my $DEVICE = $d;
          $toSave = eval $toSave;
          $toSave = "state" if( $@ );
        }
        my @sets = split(',', $toSave);
        foreach my $set (@sets) {
          my $saved = "";
          my @params = split(':', $set);
          foreach my $param (@params) {
            $saved .= " : " if( $saved );

            my $use_get = 0;
            my $get = $param;
            my $regex;
            my $set = $param;

            if( $param =~ /(get\s+)?(\S*)(\s*->\s*(set\s+)?)?(\S*)?/ ) {
              $use_get = 1 if( $1 );
              $get = $2 if( $2 );
              $set = $5 if( $5 );
            }
            ($get,$regex) = split('#', $get, 2);
            $set = "state" if( $set eq "STATE" );

            $saved .= "$set " if( $set ne "state" );

            my $value;
            if( $use_get ) {
              $value = CommandGet( "", "$d $get" );
            } elsif( $get eq "STATE" ) {
              $value = Value($d);
            } else {
              $value = ReadingsVal($d,$get,undef);
            }
            $value = eval $regex if( $regex );
            Log3 $hash, 2, "$name: $@" if($@);
            $saved .= $value;
          }

          if( !$state ) {
            $state = $saved;
          } else {
            $state = [$state] if( ref($state) ne 'ARRAY' );
            push( @{$state}, $saved );
          }
        }
      } elsif( $type eq 'CUL_HM' ) {
        #my $subtype = AttrVal($d,"subType","");
        my $subtype = CUL_HM_Get($defs{$d},$d,"param","subType");
        if( $subtype eq "switch" ) {
          $state = Value($d);
        } elsif( $subtype eq "dimmer" ) {
          $state = Value($d);
          if ( $state =~ m/^(\d+)/ ) {
            $icon = $state;
            $state = $1 if ( $state =~ m/^(\d+)/ );
          }
        } else {
          $state = Value($d);
        }
      } elsif( $type eq 'FS20' ) {
          $state = Value($d);
      } elsif( $type eq 'SWAP_0000002200000003' ) {
          $state = Value($d);
          $state = "rgb ". $state if( $state ne "off" );
      } elsif( $type eq 'HUEDevice' ) {
        my $subtype = AttrVal($d,"subType","");
        if( $subtype eq "switch" || Value($d) eq "off" ) {
          $state = Value($d);
        } elsif( $subtype eq "dimmer" ) {
          $state = "bri ". ReadingsVal($d,'bri',"0");
        } elsif( $subtype eq "colordimmer" ) {
          if( ReadingsVal($d,"colormode","") eq "ct" ) {
            ReadingsVal($d,"ct","") =~ m/(\d+) .*/;
            $state = "bri ". ReadingsVal($d,'bri',"0") ." : ct ". $1;
          } else {
            $state = "bri ". ReadingsVal($d,'bri',"0") ." : xy ". ReadingsVal($d,'xy',"");
          }
        }
      } elsif( $type eq 'IT' ) {
        my $subtype = AttrVal($d,"model","");
        if( $subtype eq "itswitch" ) {
          $state = Value($d);
        } elsif( $subtype eq "itdimmer" ) {
          $state = Value($d);
        } else {
          $state = Value($d);
        }
      } elsif( $type eq 'TRX_LIGHT' ) {
        $state = Value($d);
      } else {
        $state = Value($d);
      }

      if( $icon || ref($state) eq 'ARRAY' || $type eq "SWAP_0000002200000003" || $type eq "HUEDevice"  ) {
        my %desc;
        $desc{state} = $state;
        my ($icon, $link, $isHtml) = FW_dev2image($d);
        $desc{icon} = $icon;
        $hash->{SCENES}{$scene}{$d} = \%desc;
      } else {
        $hash->{SCENES}{$scene}{$d} = $state;
      }

      $ret .= $d .": ". $state ."\n" if( defined($FW_webArgs{room}) && $FW_webArgs{room} eq "all" ); #only if telnet

    } elsif ( $cmd eq "scene" ) {
      $hash->{STATE} = $scene;
      next if( !defined($hash->{SCENES}{$scene}{$d}));

      my $state = $hash->{SCENES}{$scene}{$d};
      $state = $state->{state} if( ref($state) eq 'HASH' );

      if( ref($state) eq 'ARRAY' ) {
        my $r = "";
        foreach my $entry (@{$state}) {
          $r .= "," if( $ret );
          $r .= CommandSet(undef,"$d $entry");
        }
        $ret .= " " if( $ret );
        $ret .= $r;
      } else {
        $ret .= " " if( $ret );
        $ret .= CommandSet(undef,"$d $state");
      }
    } else {
      $ret = "Unknown argument $cmd, choose one of save scene";
    }
  }

  delete($hash->{INSET});
  Log3 $hash, 5, "SET: $ret" if($ret);

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
  if( $cmd eq "html" ) {
    return LightScene_2html($hash);
  } elsif( $cmd eq "scenes" ) {
    foreach my $scene (sort keys %{ $hash->{SCENES} }) {
      $ret .= $scene ."\n";
    }
    return $ret;
  } elsif( $cmd eq "scene" ) {
    my $ret = "";
    my $scene = $a[2];
    if( defined($hash->{SCENES}{$scene}) ) {
      foreach my $d (sort keys %{ $hash->{SCENES}{$scene} }) {
        next if( !defined($hash->{SCENES}{$scene}{$d}));

        my $state = $hash->{SCENES}{$scene}{$d};
        $state = $state->{state} if( ref($state) eq 'HASH' );

        if( ref($state) eq 'ARRAY' ) {
          my $r = "";
          foreach my $entry (@{$state}) {
            $r .= ',' if( $r );
            $r .= $entry;
          }
          $ret .= $d .": $r\n";
        } else {
          $ret .= $d .": $state\n";
        }
      }
    } else {
        $ret = "no scene <$scene> defined";
    }
    return $ret;
  }

  return "Unknown argument $cmd, choose one of html:noArg scenes:noArg scene:".join(",", sort keys %{$hash->{SCENES}});
}

1;

=pod
=begin html

<a name="LightScene"></a>
<h3>LightScene</h3>
<ul>
  Allows to store the state of a group of lights and other devices and recall it later.
  Multiple states for one group can be stored.

  <br><br>
  <a name="LightScene_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LightScene [&lt;dev1&gt;] [&lt;dev2&gt;] [&lt;dev3&gt;] ... </code><br>
    <br>

    Examples:
    <ul>
      <code>define light_group LightScene Lampe1 Lampe2 Dimmer1</code><br>
      <code>define kino_group LightScene LampeDecke LampeFernseher Fernseher Verstaerker</code><br>
      <code>define Wohnzimmer LightScene Leinwand Beamer TV Leselampe Deckenlampe</code><br>
    </ul>
  </ul><br>

  The device detail view will show an html overview of the current state of all included devices and all
  configured scenes with the device states for each. The column heading with the device names is clickable
  to go to detail view of this device. The first row that displays the current device state is clickable
  and should react like a click on the device icon in a room overview would. this can be used to interactively
  configure a new scene and save it with the command menu of the detail view. The first column of the table with
  the scene names ic clickable to activate the scene.<br><br>

  A weblink with a scene overview that can be included in any room or a floorplan can be created with:
   <ul><code>define wlScene weblink htmlCode {LightScene_2html("Scene")}</code></ul>

  <a name="LightScene_Set"></a>
    <b>Set</b>
    <ul>
      <li>save &lt;scene_name&gt;<br>
      save current state for alle devices in this LightScene to &lt;scene_name&gt;</li>
      <li>scene &lt;scene_name&gt;<br>
      shows scene &lt;scene_name&gt; - all devices are switched to the previously saved state</li>
      <li>set &lt;scene_name&gt; &lt;device&gt; &lt;cmd&gt;<br>
      set the saved state of &lt;device&gt; in &lt;scene_name&gt; to &lt;cmd&gt;</li>
      <li>remove &lt;scene_name&gt;<br>
      remove &lt;scene_name&gt; from list of saved scenes</li>
    </ul><br>

  <a name="LightScene_Get"></a>
    <b>Get</b>
    <ul>
      <li>scenes</li>
      <li>scene &lt;scene_name&gt;</li>
    </ul><br>

  <a name="LightScene_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>lightSceneParamsToSave<br>
      this attribute can be set on the devices to be included in a scene. it is set to a comma separated list of readings
      that will be saved. multiple readings separated by : are collated in to a single set command (this has to be supported
      by the device). each reading can have a perl expression appended with '#' that will be used to alter the $value used for
      the set command. this can for example be used to strip a trailing % from a dimmer state.
      in addition to reading names the list can also contain expressions of the form <code>abc -> xyz</code>
      or <code>get cba -> set uvw</code> to map reading abc to set xyz or get cba to set uvw. the list can be given as a
      string or as a perl expression enclosed in {} that returns this string.<br>
      <code>attr myReceiver lightSceneParamsToSave volume,channel</code></br>
      <code>attr myHueDevice lightSceneParamsToSave {(Value($DEVICE) eq "off")?"state":"bri : xy"}</code></li>
      <code>attr myDimmer lightSceneParamsToSave state#{if($value=~m/(\d+)/){$1}else{$value}}</code></br>
    </ul><br>
</ul>

=end html
=cut
