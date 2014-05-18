# $Id$
##############################################################################
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;

use POSIX qw(strftime);

use vars qw($FW_ME);
use vars qw($FW_wname);
use vars qw($FW_subdir);
use vars qw(%FW_hiddenroom);
use vars qw(%FW_visibleDeviceHash);
use vars qw(%FW_webArgs); # all arguments specified in the GET

my $readingsHistory_hasJSON = 0;
my $readingsHistory_hasDataDumper = 1;

sub readingsHistory_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "readingsHistory_Define";
  $hash->{NotifyFn} = "readingsHistory_Notify";
  $hash->{NotifyOrderPrefix}= "51-";
  $hash->{UndefFn}  = "readingsHistory_Undefine";
  $hash->{SetFn}    = "readingsHistory_Set";
  $hash->{GetFn}    = "readingsHistory_Get";
  $hash->{AttrFn}   = "readingsHistory_Attr";
  $hash->{AttrList} = "disable:1,2,3 mapping style timestampFormat valueFormat noheading:1 nolinks:1 notime:1 nostate:1 alwaysTrigger:1 rows";

  $hash->{FW_detailFn}  = "readingsHistory_detailFn";
  $hash->{FW_summaryFn}  = "readingsHistory_detailFn";

  $hash->{FW_atPageEnd} = 1;

  eval "use Data::Dumper";
  $readingsHistory_hasDataDumper = 0 if($@);

}

sub
readingsHistory_updateDevices($)
{
  my ($hash) = @_;

  my %list;
  my @devices;

  my $def = $hash->{DEF};
  $def = "" if( !$def );
  my @params = split(" ", $def);
  while (@params) {
    my $param = shift(@params);

    my @device = split(":", $param);

    if($device[0] =~ m/(.*)=(.*)/) {
      my ($lattr,$re) = ($1, $2);
      foreach my $d (sort keys %defs) {
        next if( IsIgnored($d) );
        next if( !defined($defs{$d}{$lattr}) );
        next if( $defs{$d}{$lattr} !~ m/^$re$/);
        $list{$d} = 1;
        push @devices, [$d,$device[1]];
      }
    } elsif($device[0] =~ m/(.*)&(.*)/) {
        my ($lattr,$re) = ($1, $2);
        foreach my $d (sort keys %attr) {
          next if( IsIgnored($d) );
          next if( !defined($attr{$d}{$lattr}) );
          next if( $attr{$d}{$lattr} !~ m/^$re$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
      }
    } elsif( defined($defs{$device[0]}) ) {
      $list{$device[0]} = 1;
      push @devices, [@device];
    } else {
      foreach my $d (sort keys %defs) {
        next if( IsIgnored($d) );
        eval { $d =~ m/^$device[0]$/ };
        if( $@ ) {
          Log3 $hash->{NAME}, 3, $hash->{NAME} .": ". $device[0] .": ". $@;
          push @devices, ["<<ERROR>>"];
          last;
        }
        next if( $d !~ m/^$device[0]$/);
        $list{$d} = 1;
        push @devices, [$d,$device[1]];
      }
    }
  }

  $hash->{CONTENT} = \%list;
  $hash->{DEVICES} = \@devices;

  delete( $hash->{NOTIFYDEV} );
  if( scalar keys %list == 0 ) {
    $hash->{NOTIFYDEV} = "global";
  }

  $hash->{fhem}->{last_update} = gettimeofday();
}

sub
readingsHistory_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> readingsHistory [<device>[:<readings>]]+"  if(@args < 2);

  my $name = shift(@args);
  my $type = shift(@args);

  $hash->{HAS_DataDumper} = $readingsHistory_hasDataDumper;

  $hash->{fhem}{lines} = [] if( !defined($hash->{fhem}{lines}) );

  readingsHistory_updateDevices($hash);

  $hash->{STATE} = 'Initialized';

  return undef;
}

sub
readingsHistory_lookup($$$$$$$$)
{
  my($mapping,$name,$alias,$reading,$value,$room,$group,$default) = @_;

  if( $mapping ) {
    if( ref($mapping) eq 'HASH' ) {
      $default = $mapping->{$name} if( defined($mapping->{$name}) );
      $default = $mapping->{$reading} if( defined($mapping->{$reading}) );
      $default = $mapping->{$name.".".$reading} if( defined($mapping->{$name.".".$reading}) );
      $default = $mapping->{$reading.".".$value} if( defined($mapping->{$reading.".".$value}) );
    #} elsif( $mapping =~ m/^{.*}$/) {
    #  my $DEVICE = $name;
    #  my $READING = $reading;
    #  my $VALUE = $value;
    #  $mapping = eval $mapping;
    #  $default = $mapping if( $mapping );
    } else {
      $default = $mapping;
    }

    return $default if( !defined($default) );

    $default =~ s/\%ALIAS/$alias/g;
    $default =~ s/\%DEVICE/$name/g;
    $default =~ s/\%READING/$reading/g;
    $default =~ s/\%VALUE/$value/g;
    $default =~ s/\%ROOM/$room/g;
    $default =~ s/\%GROUP/$group/g;

    $default =~ s/\$ALIAS/$alias/g;
    $default =~ s/\$DEVICE/$name/g;
    $default =~ s/\$READING/$reading/g;
    $default =~ s/\$VALUE/$value/g;
    $default =~ s/\$ROOM/$room/g;
    $default =~ s/\$GROUP/$group/g;
  }

  return $default;
}
sub
readingsHistory_lookup2($$$$)
{
  my($lookup,$name,$reading,$value) = @_;

  return $lookup if( !$lookup );

  if( ref($lookup) eq 'HASH' ) {
    my $vf = "";
    $vf = $lookup->{$reading} if( exists($lookup->{$reading}) );
    $vf = $lookup->{$name.".".$reading} if( exists($lookup->{$name.".".$reading}) );
    $vf = $lookup->{$reading.".".$value} if( defined($value) && exists($lookup->{$reading.".".$value}) );
    $lookup = $vf;
  }

  if( !ref($lookup) && $lookup =~ m/^{.*}$/) {
    my $DEVICE = $name;
    my $READING = $reading;
    my $VALUE = $value;
    $lookup = eval $lookup;
    $lookup = "" if( $@ );
  }

  return $lookup if( !defined($lookup) );

  $lookup =~ s/\%DEVICE/$name/g;
  $lookup =~ s/\%READING/$reading/g;
  $lookup =~ s/\%VALUE/$value/g;

  $lookup =~ s/\$DEVICE/$name/g;
  $lookup =~ s/\$READING/$reading/g;
  $lookup =~ s/\$VALUE/$value/g;

  return $lookup;
}


sub readingsHistory_Undefine($$)
{
  my ($hash,$arg) = @_;

  return undef;
}

sub
readingsHistory_2html($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  if( $hash->{DEF} =~ m/=/ ) {
    if( !$hash->{fhem}->{last_update}
        || gettimeofday() - $hash->{fhem}->{last_update} > 600 ) {
      readingsHistory_updateDevices($hash);
    }
  }

  my $d = $hash->{NAME};

  my $show_heading = !AttrVal( $d, "noheading", "0" );
  my $show_links = !AttrVal( $d, "nolinks", "0" );
  $show_links = 0 if($FW_hiddenroom{detail});

  my $disable = AttrVal($d,"disable", 0);
  if( AttrVal($d,"disable", 0) > 2 ) {
    return undef;
  } elsif( AttrVal($d,"disable", 0) > 1 ) {
    my $ret;
    $ret .= "<table>";
    my $txt = AttrVal($d, "alias", $d);
    $txt = "<a href=\"$FW_ME$FW_subdir?detail=$d\">$txt</a>" if( $show_links );
    $ret .= "<tr><td><div class=\"devType\">$txt</a></div></td></tr>" if( $show_heading );
    $ret .= "<tr><td><table class=\"block wide\">";
    #$ret .= "<div class=\"devType\"><a style=\"color:#ff8888\" href=\"$FW_ME$FW_subdir?detail=$d\">readingsHistory $txt is disabled.</a></div>";
    $ret .= "<td><div style=\"color:#ff8888;text-align:center\">disabled</div></td>";
    $ret .= "</table></td></tr>";
    $ret .= "</table>";
    return $ret;
  }

  my $show_time = !AttrVal( $d, "notime", "0" );

  my $style = AttrVal( $d, "style", "" );

  my $devices = $hash->{DEVICES};

  my $row = 1;
  my $ret;
  $ret .= "<table>";
  my $txt = AttrVal($d, "alias", $d);
  $txt = "<a href=\"$FW_ME$FW_subdir?detail=$d\">$txt</a>" if( $show_links );
  $ret .= "<tr><td><div class=\"devType\">$txt</a></div></td></tr>" if( $show_heading );
  $ret .= "<tr><td><table $style class=\"block wide\">";
  $ret .= "<tr><td colspan=\"99\"><div style=\"color:#ff8888;text-align:center\">updates disabled</div></tr>" if( $disable > 0 );

  my $rows = AttrVal($d,"rows", 5 );
  $rows = 1 if( $rows < 1 );

  my $lines = "";
  for (my $i = 0; $i < $rows; $i++) {
    $lines .= @{$hash->{fhem}{lines}}[$i] if( @{$hash->{fhem}{lines}}[$i] );
    $lines .= "<br>";
  }

  $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
  $row++;
  $ret .= "<td><div id=\"$d-history\" rows=\"$rows\">$lines</div></td>";

  $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
  $ret .= "<td colspan=\"99\"><div style=\"color:#ff8888;text-align:center\">updates disabled</div></td></tr>" if( $disable > 0 );
  $ret .= "</table></td></tr>";
  $ret .= "</table>";

  return $ret;
}
sub
readingsHistory_detailFn()
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $hash = $defs{$d};

  $hash->{mayBeVisible} = 1;

  return readingsHistory_2html($d);
}

sub
readingsHistory_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};

  if( grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}) ) {
    readingsHistory_updateDevices($hash);
    readingsHistory_Load($hash);
    return undef;
  } elsif( grep(m/^REREADCFG$/, @{$dev->{CHANGED}}) ) {
    readingsHistory_updateDevices($hash);
    readingsHistory_Load($hash);
    return undef;
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
    readingsHistory_Save();
  }

  return if( AttrVal($name,"disable", 0) > 0 );

  return if($dev->{TYPE} eq $hash->{TYPE});
  #return if($dev->{NAME} eq $name);

  my $devices = $hash->{DEVICES};

  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if( $dev->{NAME} eq "global" && $s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      my ($old, $new) = ($1, $2);
      if( defined($hash->{CONTENT}{$old}) ) {

        $hash->{DEF} =~ s/(\s*)$old((:\S+)?\s*)/$1$new$2/g;
      }
      readingsHistory_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      my ($name) = ($1);

      if( defined($hash->{CONTENT}{$name}) ) {

        $hash->{DEF} =~ s/(\s*)$name((:\S+)?\s*)/ /g;
        $hash->{DEF} =~ s/^ //;
        $hash->{DEF} =~ s/ $//;
      }
      readingsHistory_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      readingsHistory_updateDevices($hash);
    } else {
      next if(AttrVal($name,"disable", undef));

      next if (!$hash->{CONTENT}->{$dev->{NAME}});

      if( $hash->{alwaysTrigger} ) {
        $hash->{mayBeVisible} = 1;
      } elsif( !defined($hash->{mayBeVisible}) ) {
        Log3 $name, 5, "$name: not on any display, don't trigger";
      } else {
        if( defined($FW_visibleDeviceHash{$name}) ) {
        } else {
          Log3 $name, 5, "$name: no longer visible, don't trigger";
          delete( $hash->{mayBeVisible} );
        }
      }

      my @parts = split(/: /,$s);
      my $reading = shift @parts;
      my $value   = join(": ", @parts);

      $reading = "" if( !defined($reading) );
      next if( $reading =~ m/^\./);
      $value = "" if( !defined($value) );
      my $show_state = 1;
      if( $value eq "" ) {
        next if AttrVal( $name, "nostate", "0" );

        $reading = "state";
        $value = $s;
      }

      my $mapping = AttrVal( $name, "mapping", "");
      $mapping = eval $mapping if( $mapping =~ m/^{.*}$/ );
      #$mapping = undef if( ref($mapping) ne 'HASH' );

      my $timestampFormat = AttrVal( $name, "timestampFormat", undef);

      my $value_format = AttrVal( $name, "valueFormat", "" );
      if( $value_format =~ m/^{.*}$/ ) {
        my $vf = eval $value_format;
        $value_format = $vf if( $vf );
      }

      foreach my $device (@{$devices}) {
        my $item = 0;
        my $h = $defs{@{$device}[0]};
        next if( !$h );
        next if( $dev->{NAME} ne $h->{NAME} );
        my $n = $h->{NAME};
        my $regex = @{$device}[1];
        my @list = (undef);
        @list = split(",",$regex) if( $regex );
        foreach my $regex (@list) {
          next if( $reading eq "state" && !$show_state && (!defined($regex) || $regex ne "state") );

          next if( defined($regex) && $reading !~ m/^$regex$/);

          my $value_format = readingsHistory_lookup2($value_format,$n,$reading,$value);
          next if( !defined($value_format) );
          if( $value_format =~ m/%/ ) {
            $s = sprintf( $value_format, $value );
          } elsif( $value_format ) {
            $s = $value_format;
          }

          my @t = localtime;
          my $tm;
          if( $timestampFormat ) {
            $tm = strftime( $timestampFormat, @t );
          } else {
            $tm = sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0] );
          }

          my $show_links = !AttrVal( $name, "nolinks", "0" );
          $show_links = 0 if($FW_hiddenroom{detail});
          $show_links = 0 if(!defined($FW_ME));
          #$show_links = 0 if(!defined($FW_subdir));

          my $a = AttrVal($n, "alias", $n);
          my $m = $a;
          if( $mapping ) {
            my $room = AttrVal($n, "room", "");
            my $group = AttrVal($n, "group", "");
            $m = readingsHistory_lookup($mapping,$n,$a,$reading,$value,$room,$group,$m);
          }

          my $line = "$tm&nbsp;&nbsp;$m $s";
          $line = "$tm&nbsp;&nbsp;<a href=\"$FW_ME$FW_subdir?detail=$n\">$m</a> $s" if( $show_links );

          while( @{$hash->{fhem}{lines}} >= AttrVal($name,"rows", 5 ) ) {
            pop @{$hash->{fhem}{lines}};
          }
          unshift( @{$hash->{fhem}{lines}}, $line );

          DoTrigger( "$name", "history: $line" ) if( $hash->{mayBeVisible} );
        }
      }
    }
  }

  return undef;
}

sub
readingsHistory_StatefileName()
{
  my $statefile = $attr{global}{statefile};
  $statefile = substr $statefile,0,rindex($statefile,'/')+1;
  #return $statefile ."readingsHistorys.save" if( $readingsHistory_hasJSON );
  return $statefile ."readingsHistorys.dd.save" if( $readingsHistory_hasDataDumper );
}
my $readingsHistory_LastSaveTime="";
sub
readingsHistory_Save()
{
  my $time_now = TimeNow();
  return if( $time_now eq $readingsHistory_LastSaveTime);
  $readingsHistory_LastSaveTime = $time_now;

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = readingsHistory_StatefileName();

  my $hash;
  for my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "readingsHistory");
    next if( !defined($defs{$d}{fhem}{lines}) );

    $hash->{$d} = $defs{$d}{fhem}{lines};
  }

  if(open(FH, ">$statefile")) {
    my $t = localtime;
    print FH "#$t\n";

    if( $readingsHistory_hasJSON ) {
      print FH encode_json($hash) if( defined($hash) );
    } elsif( $readingsHistory_hasDataDumper ) {
      my $dumper = Data::Dumper->new([]);
      $dumper->Terse(1);

      $dumper->Values([$hash]);
      print FH $dumper->Dump;
    }

    close(FH);
  } else {

    my $msg = "readingsHistory_Save: Cannot open $statefile: $!";
    Log3 undef, 1, $msg;
  }

  return undef;
}
sub
readingsHistory_Load($)
{
  my ($hash) = @_;

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = readingsHistory_StatefileName();

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
    if( $readingsHistory_hasJSON ) {
      $decoded = decode_json( $encoded );
    } elsif( $readingsHistory_hasDataDumper ) {
      $decoded = eval $encoded;
    }
    $hash->{fhem}{lines} = $decoded->{$hash->{NAME}} if( defined($decoded->{$hash->{NAME}}) );
  } else {
    my $msg = "readingsHistory_Load: Cannot open $statefile: $!";
    Log3 undef, 1, $msg;
  }
  return undef;
}

sub
readingsHistory_Set($@)
{
  my ($hash, $name, $cmd, $param, @a) = @_;

  my $list = "clear:noArgs add";

  if( $cmd eq "clear" ) {
    $hash->{fhem}{lines} = [];

    my @t = localtime;
    my $tm = sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0] );
    my $line = "$tm&nbsp;&nbsp;--clear--";

    unshift( @{$hash->{fhem}{lines}}, $line );

    DoTrigger( "$name", "clear: $line" ) if( $hash->{mayBeVisible} );

    return undef;
  } elsif ( $cmd eq "add" ) {
    my @t = localtime;
    my $tm = sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0] );
    my $line = "$tm&nbsp;&nbsp;$param ". join( " ", @a );

    while( @{$hash->{fhem}{lines}} >= AttrVal($name,"rows", 5 ) ) {
      pop @{$hash->{fhem}{lines}};
    }
    unshift( @{$hash->{fhem}{lines}}, $line );

    DoTrigger( "$name", "history: $line" ) if( $hash->{mayBeVisible} );
    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
readingsHistory_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  my $ret = "";
  if( $cmd eq "html" ) {
    return readingsHistory_2html($hash);
  }

  return undef;
  return "Unknown argument $cmd, choose one of html:noArg";
}

sub
readingsHistory_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $orig = $attrVal;

  if( $attrName eq "alwaysTrigger" ) {
    my $hash = $defs{$name};
    $attrVal = 1 if($attrVal);

    if( $cmd eq "set" ) {
      $hash->{alwaysTrigger} = $attrVal;
      delete( $hash->{helper}->{myDisplay} ) if( $hash->{alwaysTrigger} );
    } else {
      delete $hash->{alwaysTrigger};
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

1;

=pod
=begin html

<a name="readingsHistory"></a>
<h3>readingsHistory</h3>
<ul>
  Displays a history of readings from on or more devices.

  <br><br>
  <a name="readingsHistory_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsHistory [&lt;device&gt;[:regex] [&lt;device-2&gt;[:regex-2] ... [&lt;device-n&gt;[:regex-n]]]]</code><br>
    <br>

    Notes:
    <ul>
      <li>&lt;device&gt; can be of the form INTERNAL=VALUE where INTERNAL is the name of an internal value and VALUE is a regex.</li>
      <li>If regex is a comma separatet list it will be used as an enumeration of allowed readings.</li>
      <li>if no device/reading argument is given only lines with 'set <device> add ...' are displayed.</li>
    </ul><br>

    Examples:
    <ul>
    </ul>
  </ul><br>

  <a name="readingsHistory_Set"></a>
    <b>Set</b>
    <ul>
      <li>add ...<br>
        directly add text as new line to history.</br>
      <li>clear<br>
        clear the history.</br>
    </ul><br>

  <a name="readingsHistory_Get"></a>
    <b>Get</b>
    <ul>
    </ul><br>

  <a name="readingsHistory_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>alwaysTrigger<br>
        1 -> alwaysTrigger update events. even if not visible.</li>
      <li>disable<br>
        1 -> disable notify processing and longpoll updates. Notice: this also disables rename and delete handling.<br>
        2 -> also disable html table creation<br>
        3 -> also disable html creation completely</li>
      <li>noheading<br>
        If set to 1 the readings table will have no heading.</li>
      <li>nolinks<br>
        Disables the html links from the heading and the reading names.</li>
      <li>notime<br>
        If set to 1 the reading timestamp is not displayed.</li>
      <li>mapping<br>
        Can be a simple string or a perl expression enclosed in {} that returns a hash that maps device names
        to the displayed name.  The keys can be either the name of the reading or &lt;device&gt;.&lt;reading&gt;.
        %DEVICE, %ALIAS, %ROOM and %GROUP are replaced by the device name, device alias, room attribute and
        group attribute respectively. You can also prefix these keywords with $ instead of %.
        </li>
      <li>style<br>
        Specify an HTML style for the readings table, e.g.:<br>
          <code>attr history style style="font-size:20px"</code></li>
      <li>timestampFormat<br>
        POSIX strftime compatible string for used as the timestamp for each line.
        </li>
      <li>valueFormat<br>
        Specify an sprintf style format string used to display the reading values. If the format string is undef
        this reading will be skipped. Can be given as a string, a perl expression returning a hash or a perl
        expression returning a string, e.g.:<br>
          <code>attr history valueFormat %.1f &deg;C</code></br>
          <code>attr history valueFormat { temperature => "%.1f &deg;C", humidity => "%.1f %" }</code></br>
          <code>attr history valueFormat { ($READING eq 'temperature')?"%.1f &deg;C":undef }</code></li>
      <li>rows<br>
        Number of history rows to show.</li>
    </ul>
</ul>

=end html
=cut
