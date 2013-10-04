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

use vars qw(%FW_webArgs); # all arguments specified in the GET

sub readingsGroup_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "readingsGroup_Define";
  $hash->{NotifyFn} = "readingsGroup_Notify";
  $hash->{UndefFn}  = "readingsGroup_Undefine";
  #$hash->{SetFn}    = "readingsGroup_Set";
  $hash->{GetFn}    = "readingsGroup_Get";
  $hash->{AttrList} = "nameIcons mapping separator style nameStyle valueStyle valueFormat timestampStyle noheading:1 nolinks:1 notime:1 nostate:1";

  $hash->{FW_detailFn}  = "readingsGroup_detailFn";
  $hash->{FW_summaryFn}  = "readingsGroup_detailFn";

  $hash->{FW_atPageEnd} = 1;
}

sub
readingsGroup_updateDevices($)
{
  my ($hash) = @_;

  my %list;
  my @devices;

  my @params = split(" ", $hash->{DEF});
  while (@params) {
    my $param = shift(@params);

    # for backwards compatibility with weblink readings
    if( $param eq '*noheading' ) {
      $attr{$hash->{NAME}}{noheading} = 1;
      $hash->{DEF} =~ s/(\s*)\\$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param eq '*notime' ) {
      $attr{$hash->{NAME}}{notime} = 1;
      $hash->{DEF} =~ s/(\s*)\\$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param eq '*nostate' ) {
      $attr{$hash->{NAME}}{nostate} = 1;
      $hash->{DEF} =~ s/(\s*)\\$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param =~ m/^{/) {
      $attr{$hash->{NAME}}{mapping} = $param ." ". join( " ", @params );
      $hash->{DEF} =~ s/\s*[{].*$//g;
      last;
    } else {
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
      }
      elsif( defined($defs{$device[0]}) ) {
        $list{$device[0]} = 1;
        push @devices, [@device];
      } else {
        foreach my $d (sort keys %defs) {
          next if( IsIgnored($d) );
          next if( $d !~ m/^$device[0]$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
        }
      }
    }
  }

  $hash->{CONTENT} = \%list;
  $hash->{DEVICES} = \@devices;
}

sub readingsGroup_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> readingsGroup <device>+"  if(@args < 3);

  my $name = shift(@args);
  my $type = shift(@args);

  readingsGroup_updateDevices($hash);

  $hash->{STATE} = 'Initialized';

  return undef;
}

sub readingsGroup_Undefine($$)
{
  my ($hash,$arg) = @_;

  return undef;
}

sub lookup($$$$$$$)
{
  my($mapping,$name,$alias,$reading,$room,$group,$default) = @_;

  if( $mapping ) {
    if( ref($mapping) eq 'HASH' ) {
      $default = $mapping->{$name} if( defined($mapping) && defined($mapping->{$name}) );
      $default = $mapping->{$reading} if( defined($mapping) && defined($mapping->{$reading}) );
      $default = $mapping->{$name.".".$reading} if( defined($mapping) && defined($mapping->{$name.".".$reading}) );
    } else {
      $default = $mapping;
    }

    $default =~ s/\%ALIAS/$alias/g;
    $default =~ s/\%DEVICE/$name/g;
    $default =~ s/\%READING/$reading/g;
    $default =~ s/\%ROOM/$room/g;
    $default =~ s/\%GROUP/$group/g;

    $default =~ s/\$ALIAS/$alias/g;
    $default =~ s/\$DEVICE/$name/g;
    $default =~ s/\$READING/$reading/g;
    $default =~ s/\$ROOM/$room/g;
    $default =~ s/\$GROUP/$group/g;
  }

  return $default;
}
sub
readingsGroup_2html($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $d = $hash->{NAME};

  my $show_heading = !AttrVal( $d, "noheading", "0" );
  my $show_links = !AttrVal( $d, "nolinks", "0" );
  my $show_state = !AttrVal( $d, "nostate", "0" );
  my $show_time = !AttrVal( $d, "notime", "0" );

  my $separator = AttrVal( $d, "separator", ":" );
  my $style = AttrVal( $d, "style", "" );
  my $name_style = AttrVal( $d, "nameStyle", "" );
  my $value_style = AttrVal( $d, "valueStyle", "" );
  my $timestamp_style = AttrVal( $d, "timestampStyle", "" );

  my $value_format = AttrVal( $d, "valueFormat", "" );
  if( $value_format =~ m/^{.*}$/ ) {
    my $vf = eval $value_format;
    $value_format = $vf if( $vf );
  }

  my $mapping = AttrVal( $d, "mapping", "");
  $mapping = eval $mapping if( $mapping =~ m/^{.*}$/ );
  #$mapping = undef if( ref($mapping) ne 'HASH' );

  my $nameIcons = AttrVal( $d, "nameIcons", "");
  $nameIcons = eval $nameIcons if( $nameIcons =~ m/^{.*}$/ );
  #$nameIcons = undef if( ref($nameIcons) ne 'HASH' );


  my $devices = $hash->{DEVICES};

  my $ret;

  my $row = 1;
  $ret .= "<table>";
  my $txt = AttrVal($d, "alias", $d);
  $txt = "<a href=\"/fhem?detail=$d\">$txt</a>" if( $show_links );
  $ret .= "<tr><td><div class=\"devType\">$txt</a></div></td></tr>" if( $show_heading );
  $ret .= "<tr><td><table $style class=\"block wide\">";
  foreach my $device (@{$devices}) {
    my $h = $defs{@{$device}[0]};
    my $regex = @{$device}[1];
    my $name = $h->{NAME};
    next if( !$h );

    if( $regex && $regex =~ m/\+(.*)/ ) {
      $regex = $1;

      my $now = gettimeofday();
      my $fmtDateTime = FmtDateTime($now);

      foreach my $n (sort keys %{$h}) {
        next if( $n =~ m/^\./);
        next if( defined($regex) &&  $n !~ m/^$regex$/);
        my $val = $h->{$n};

        my $r = ref($val);
        next if($r && ($r ne "HASH" || !defined($hash->{$n}{VAL})));

        my $v = FW_htmlEscape($val);

        my $name_style = $name_style;
        if(defined($name_style) && $name_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $name_style = eval $name_style;
          $name_style = "" if( !$name_style );
        }
        my $value_style = $value_style;
        if(defined($value_style) && $value_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $value_style = eval $value_style;
          $value_style = "" if( !$value_style );
        }

        if( $value_format ) {
          my $value_format = $value_format;
          if( ref($value_format) eq 'HASH' ) {
            my $vf ="";
            $vf = $value_format->{$n} if( defined($value_format->{$n}) );
            $vf = $value_format->{$name.".".$n} if( defined($value_format->{$name.".".$n}) );
            $value_format = $vf;
          } elsif( $value_format =~ m/^{.*}$/) {
            my $DEVICE = $name;
            my $READING = $n;
            my $VALUE = $v;
            $value_format = eval $value_format;
          }

          next if( !defined($value_format) );

          $v = sprintf( $value_format, $v ) if( $value_format );
        }

        my $a = AttrVal($name, "alias", $name);
        my $m = "$a$separator$n";
        my $room = AttrVal($name, "room", "");
        my $group = AttrVal($name, "group", "");
        my $txt = lookup($mapping,$name,$a,$n,$room,$group,$m);

        if( $nameIcons ) {
          if( my $icon = lookup($nameIcons,$name,$a,$n,$room,$group,"") ) {
            $txt = FW_makeImage( $icon, $txt, "icon" );
          }
        }

        $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
        $row++;

        $txt = "<a href=\"/fhem?detail=$name\">$txt</a>" if( $show_links );
        $ret .= "<td><div $name_style class=\"dname\">$txt</div></td>";
        $ret .= "<td><div $value_style\">$v</div></td>";
        $ret .= "<td><div></div>$fmtDateTime</td>" if( $show_time );
      }
    } else {
    foreach my $n (sort keys %{$h->{READINGS}}) {
      next if( $n =~ m/^\./);
      next if( $n eq "state" && !$show_state );
      next if( defined($regex) &&  $n !~ m/^$regex$/);
      my $val = $h->{READINGS}->{$n};

      if(ref($val)) {
        my ($v, $t) = ($val->{VAL}, $val->{TIME});
        $v = FW_htmlEscape($v);
        $t = "" if(!$t);

        my $name_style = $name_style;
        if(defined($name_style) && $name_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $name_style = eval $name_style;
          $name_style = "" if( !$name_style );
        }
        my $value_style = $value_style;
        if(defined($value_style) && $value_style =~ m/^{.*}$/) {
          my $DEVICE = $name;
          my $READING = $n;
          my $VALUE = $v;
          $value_style = eval $value_style;
          $value_style = "" if( !$value_style );
        }

        if( $value_format ) {
          my $value_format = $value_format;
          if( ref($value_format) eq 'HASH' ) {
            my $vf ="";
            $vf = $value_format->{$n} if( defined($value_format->{$n}) );
            $vf = $value_format->{$name.".".$n} if( defined($value_format->{$name.".".$n}) );
            $value_format = $vf;
          } elsif( $value_format =~ m/^{.*}$/) {
            my $DEVICE = $name;
            my $READING = $n;
            my $VALUE = $v;
            $value_format = eval $value_format;
          }

          next if( !defined($value_format) );

          $v = sprintf( $value_format, $v ) if( $value_format );
        }

        my $a = AttrVal($name, "alias", $name);
        my $m = "$a$separator$n";
        my $room = AttrVal($name, "room", "");
        my $group = AttrVal($name, "group", "");
        my $txt = lookup($mapping,$name,$a,$n,$room,$group,$m);

        if( $nameIcons ) {
          if( my $icon = lookup($nameIcons,$name,$a,$n,$room,$group,"") ) {
            $txt = FW_makeImage( $icon, $txt, "icon" );
          }
        }

        $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
        $row++;

        $txt = "<a href=\"/fhem?detail=$name\">$txt</a>" if( $show_links );
        $ret .= "<td><div $name_style class=\"dname\">$txt</div></td>";
        $ret .= "<td><div $value_style informId=\"$d-$name.$n\">$v</div></td>";
        $ret .= "<td><div $timestamp_style informId=\"$d-$name.$n-ts\">$t</div></td>" if( $show_time );
      }
    }
    }
  }
  $ret .= "</table></td></tr>";
  $ret .= "</table>";
  #$ret .= "</br>";

  return $ret;
}
sub
readingsGroup_detailFn()
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  return readingsGroup_2html($d);
}

sub
readingsGroup_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};

  if( grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}) ) {
    readingsGroup_updateDevices($hash);
    return undef;
  }
  elsif( grep(m/^REREADCFG$/, @{$dev->{CHANGED}}) ) {
    readingsGroup_updateDevices($hash);
    return undef;
  }

  return if($dev->{NAME} eq $name);

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
      readingsGroup_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      my ($name) = ($1);

      if( defined($hash->{CONTENT}{$name}) ) {

        $hash->{DEF} =~ s/(\s*)$name((:\S+)?\s*)/ /g;
        $hash->{DEF} =~ s/^ //;
        $hash->{DEF} =~ s/ $//;
      }
      readingsGroup_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      readingsGroup_updateDevices($hash);
    } else {
      next if(AttrVal($name,"disable", undef));

      next if (!$hash->{CONTENT}->{$dev->{NAME}});

      my @parts = split(/: /,$s);
      my $reading = shift @parts;
      my $value   = join(": ", @parts);

      $reading = "" if( !defined($reading) );
      next if( $reading =~ m/^\./);
      $value = "" if( !defined($value) );
      if( $value eq "" ) {
        next if( AttrVal( $name, "nostate", "0" ) );

        $reading = "state";
        $value = $s;
      }

      my $value_format = AttrVal( $name, "valueFormat", "" );
      if( $value_format =~ m/^{.*}$/ ) {
        my $vf = eval $value_format;
        $value_format = $vf if( $vf );
      }

      foreach my $device (@{$devices}) {
        my $h = $defs{@{$device}[0]};
        next if( !$h );
        next if( $dev->{NAME} ne $h->{NAME} );
        my $regex = @{$device}[1];
        next if( defined($regex) && $reading !~ m/^$regex$/);

        if( $value_format ) {
          my $value_format = $value_format;
          if( ref($value_format) eq 'HASH' ) {
            my $vf = "";
            $vf = $value_format->{$reading} if( defined($value_format->{$reading}) );
            $vf = $value_format->{$dev->{NAME}.".".$reading} if( defined($value_format->{$dev->{NAME}.".".$reading}) );
            $value_format = $vf;
            } elsif( $value_format =~ m/^{.*}$/) {
            my $DEVICE = $dev->{NAME};
            my $READING = $reading;
            my $VALUE = $value;
            $value_format = eval $value_format;
          }
          $value = sprintf( $value_format, $value ) if( $value_format );
        }

        CommandTrigger( "", "$name $dev->{NAME}.$reading: $value" );
      }
    }
  }

  return undef;
}

sub
readingsGroup_Set($@)
{
  my ($hash, $name, $cmd, $param, @a) = @_;

  my $list = "refresh:noArgs";

  if( $cmd eq "refresh" ) {
    readingsGroup_updateDevices($hash);
    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
readingsGroup_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  my $ret = "";
  if( $cmd eq "html" ) {
    return readingsGroup_2html($hash);
  }

  return undef;
  return "Unknown argument $cmd, choose one of html:noArg";
}

1;

=pod
=begin html

<a name="readingsGroup"></a>
<h3>readingsGroup</h3>
<ul>
  Displays a collection of readings from on or more devices.

  <br><br>
  <a name="readingsGroup_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsGroup &lt;device&gt;[:regex] [&lt;device-2&gt;[:regex-2]] ... [&lt;device-n&gt;[:regex-n]]</code><br>
    <br>

    Notes:
    <ul>
      <li>&lt;device&gt; can be of the form INTERNAL=VALUE where INTERNAL is the name of an internal value and VALUE is a regex.</li>
      <li>If regex starts with a + it will be matched against the internal values of the device instead of the readings.</li>
      <li>For internal values no longpoll update is possible. Refresh the page to update the values.</li>
    </ul><br>

    Examples:
    <ul>
      <code>
        define batteries readingsGroup .*:battery</code><br>
      <br>
        <code>define temperatures readingsGroup s300th.*:temperature</code><br>
        <code>define temperatures readingsGroup TYPE=CUL_WS.*:temperature</code><br>
      <br>
        <code>define culRSSI readingsGroup cul_RSSI=.*:+cul_RSSI</code><br>
      <br>
        <code>define heizung readingsGroup t1:temperature t2:temperature t3:temperature<br>
        attr heizung notime 1<br>
        attr heizung mapping {'t1.temperature' => 'Vorlauf', 't2.temperature' => 'R&amp;uuml;cklauf', 't3.temperature' => 'Zirkulation'}</br>
        attr heizung style style="font-size:20px"<br>
      <br>
        define systemStatus readingsGroup sysstat<br>
        attr systemStatus notime 1<br>
        attr systemStatus nostate 1<br>
        attr systemStatus mapping { 'load' => 'Systemauslastung', 'temperature' => 'Systemtemperatur in &amp;deg;C'}<br>
      </code><br>
    </ul>
  </ul><br>

  <a name="readingsGroup_Set"></a>
    <b>Set</b>
    <ul>
    </ul><br>

  <a name="readingsGroup_Get"></a>
    <b>Get</b>
    <ul>
    </ul><br>

  <a name="readingsGroup_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>noheading<br>
        If set to 1 the readings table will have no heading.</li>
      <li>nolinks<br>
        Disables the html links from the heading and the reading names.</li>
      <li>nostate<br>
        If set to 1 the state reading is excluded.</li>
      <li>notime<br>
        If set to 1 the reading timestamp is not displayed.</li>
      <li>mapping<br>
        Can be a simple string or a perl expression enclosed in {} that returns a hash that maps reading names to the displayed name.
        The keys can be either the name of the reading or &lt;device&gt;.&lt;reading&gt;.
        %DEVICE, %ALIAS, %ROOM, %GROUP and %READING are replaced by the device name, device alias, room attribute, group attribute and reading name respectively. You can
        also prefix these keywords with $ instead of %. Examples:<br>
          <code>attr temperatures mapping $DEVICE-$READING</code><br>
          <code>attr temperatures mapping {temperature => "%DEVICE Temperatur"}</code>
        </li>
      <li>separator<br>
        The separator to use between the device alias and the reading name if no mapping is given. Defaults to ':'
        a space can be enteread as <code>&amp;nbsp;</code></li>
      <li>style<br>
        Specify an HTML style for the readings table, e.g.:<br>
          <code>attr temperatures style style="font-size:20px"</code></li>
      <li>nameStyle<br>
        Specify an HTML style for the reading names, e.g.:<br>
          <code>attr temperatures nameStyle style="font-weight:bold"</code></li>
      <li>valueStyle<br>
        Specify an HTML style for the reading values, e.g.:<br>
          <code>attr temperatures valueStyle style="text-align:right"</code></li>
      <li>valueFormat<br>
        Specify an sprintf style format string used to display the reading values. If the format string is undef
        this reading will be skipped. Can be given as a string,
        a perl expression returninga hash or a perl expression returning a string, e.g.:<br>
          <code>attr temperatures valueFormat %.1f &deg;C</code></br>
          <code>attr temperatures valueFormat { temperature => "%.1f &deg;C", humidity => "%.1f %" }</code></br>
          <code>attr temperatures valueFormat { ($READING eq 'temperature')?"%.1f &deg;C":undef }</code></li>
      <li>nameIcon<br>
        Specify an icon to be used instead of the reading name. Can be a simple string or a perl expression enclosed
        in {} that returns a hash that maps reading names to the icon name. e.g.:<br>
          <code>attr devices nameIcon $DEVICE</code></li>
    </ul><br>

      The nameStyle and valueStyle attributes can also contain a perl expression enclosed in {} that returns the style string to use. The perl code can use $DEVICE,$READING and $VALUE, e.g.:<br>
    <ul>
          <code>attr batteries valueStyle {($VALUE ne "ok")?'style="color:red"':'style="color:green"'}</code><br>
          <code>attr temperatures valueStyle {($DEVICE =~ m/aussen/)?'style="color:green"':'style="color:red"'}</code>
    </ul>
      Note: The perl expressions are evaluated only once during html creation and will not reflect value updates with longpoll.
      Refresh the page to update the dynamic style. For nameStyle the collor attribut is not working at the moment,
      font-... and background do work.

</ul>

=end html
=cut
