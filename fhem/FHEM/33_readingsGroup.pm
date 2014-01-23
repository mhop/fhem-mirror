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
  $hash->{AttrFn}   = "readingsGroup_Attr";
  $hash->{AttrList} = "disable:1,2,3 nameIcon valueIcon mapping separator style nameStyle valueColumns valueStyle valueFormat commands timestampStyle noheading:1 nolinks:1 notime:1 nostate:1 alwaysTrigger:1";

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

    while ($param && $param =~ m/^</ && $param !~ m/>$/ ) {
      my $next = shift(@params);
      last if( !defined($next) );
      $param .= " ". $next;
    }

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
      } elsif($device[0] =~ m/(.*)&(.*)/) {
        my ($lattr,$re) = ($1, $2);
        foreach my $d (sort keys %attr) {
          next if( IsIgnored($d) );
          next if( !defined($attr{$d}{$lattr}) );
          next if( $attr{$d}{$lattr} !~ m/^$re$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
        }
      } elsif($device[0] =~ m/^<.*>$/) {
        push @devices, [$device[0]];
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
  }

  $hash->{CONTENT} = \%list;
  $hash->{DEVICES} = \@devices;

  $hash->{fhem}->{last_update} = gettimeofday();
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

sub
lookup($$$$$$$$)
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
lookup2($$$$)
{
  my($lookup,$name,$reading,$value) = @_;

  return $lookup if( !$lookup );

  if( ref($lookup) eq 'HASH' ) {
    my $vf = "";
    $vf = $lookup->{$reading} if( exists($lookup->{$reading}) );
    $vf = $lookup->{$name.".".$reading} if( exists($lookup->{$name.".".$reading}) );
    $vf = $lookup->{$reading.".".$value} if( defined($value) && exists($lookup->{$reading.".".$value}) );
    $lookup = $vf;
  } elsif($lookup =~ m/^{.*}$/) {
    my $DEVICE = $name;
    my $READING = $reading;
    my $VALUE = $value;
    $lookup = eval $lookup;
    $lookup = "" if( $@ );
  }

  $lookup =~ s/\%DEVICE/$name/g;
  $lookup =~ s/\%READING/$reading/g;
  $lookup =~ s/\%VALUE/$value/g;

  $lookup =~ s/\$DEVICE/$name/g;
  $lookup =~ s/\$READING/$reading/g;
  $lookup =~ s/\$VALUE/$value/g;

  return $lookup;
}
sub
readingsGroup_makeLink($$$)
{
  my($v,$devStateIcon,$cmd) = @_;

  if( $cmd ) {
    my $txt = $v;
    $txt = $devStateIcon if( $devStateIcon );
    my $link = "cmd=$cmd";
    if( AttrVal($FW_wname, "longpoll", 1)) {
      $txt = "<a style=\"cursor:pointer\" onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$link')\">$txt</a>";
    } else {
      my $room = $FW_webArgs{room};
      $room = "&detail=$FW_webArgs{detail}";
      my $srf = $room ? "&room=$room" : "";
      $srf = $room if( $room && $room =~ m/^&/ );
      $txt = "<a href=\"$FW_ME$FW_subdir?$link$srf\">$txt</a>";
    }
    if( !$devStateIcon ) {
      $v = $txt;
    } else {
      $devStateIcon = $txt;
    }
  }

  return ($v, $devStateIcon);
}

sub
readingsGroup_2html($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  if( $hash->{DEF} =~ m/=/ ) {
    if( !$hash->{fhem}->{last_update}
        || gettimeofday() - $hash->{fhem}->{last_update} > 600 ) {
      readingsGroup_updateDevices($hash);
    }
  }

  my $d = $hash->{NAME};

  my $show_heading = !AttrVal( $d, "noheading", "0" );
  my $show_links = !AttrVal( $d, "nolinks", "0" );

  my $disable = AttrVal($d,"disable", 0);
  if( AttrVal($d,"disable", 0) > 2 ) {
    return undef;
  } elsif( AttrVal($d,"disable", 0) > 1 ) {
    my $ret;
    $ret .= "<table>";
    my $txt = AttrVal($d, "alias", $d);
    $txt = "<a href=\"/fhem?detail=$d\">$txt</a>" if( $show_links );
    $ret .= "<tr><td><div class=\"devType\">$txt</a></div></td></tr>" if( $show_heading );
    $ret .= "<tr><td><table class=\"block wide\">";
    #$ret .= "<div class=\"devType\"><a style=\"color:#ff8888\" href=\"/fhem?detail=$d\">readingsGroup $txt is disabled.</a></div>";
    $ret .= "<td><div style=\"color:#ff8888;text-align:center\">disabled</div></td>";
    $ret .= "</table></td></tr>";
    $ret .= "</table>";
    return $ret;
  }

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

  my $value_columns = AttrVal( $d, "valueColumns", "" );
  if( $value_columns =~ m/^{.*}$/ ) {
    my $vc = eval $value_columns;
    $value_columns = $vc if( $vc );
  }

  my $mapping = AttrVal( $d, "mapping", "");
  $mapping = eval $mapping if( $mapping =~ m/^{.*}$/ );
  #$mapping = undef if( ref($mapping) ne 'HASH' );

  my $nameIcon = AttrVal( $d, "nameIcon", "");
  $nameIcon = eval $nameIcon if( $nameIcon =~ m/^{.*}$/ );
  #$nameIcon = undef if( ref($nameIcon) ne 'HASH' );

  my $valueIcon = AttrVal( $d, "valueIcon", "");
  $valueIcon = eval $valueIcon if( $valueIcon =~ m/^{.*}$/ );
  #$valueIcon = undef if( ref($valueIcon) ne 'HASH' );

  my $commands = AttrVal( $d, "commands", "" );
  $commands = eval $commands if( $commands =~ m/^{.*}$/ );

  my $devices = $hash->{DEVICES};

  my $row = 1;
  my $ret;
  $ret .= "<table>";
  my $txt = AttrVal($d, "alias", $d);
  $txt = "<a href=\"/fhem?detail=$d\">$txt</a>" if( $show_links );
  $ret .= "<tr><td><div class=\"devType\">$txt</a></div></td></tr>" if( $show_heading );
  $ret .= "<tr><td><table $style class=\"block wide\">";
  $ret .= "<tr><td colspan=\"99\"><div style=\"color:#ff8888;text-align:center\">updates disabled</div></tr>" if( $disable > 0 );
  foreach my $device (@{$devices}) {
    my $item = 0;
    my $h = $defs{$device->[0]};
    my $regex = $device->[1];
    if( !$h && $device->[0] =~ m/^<.*>$/ ) {
      $h = $hash if( !$h );
      $regex = $device->[0];
    }
    my $name = $h->{NAME};
    next if( !$h );

    my @list = (undef);
    @list = split(",",$regex) if( $regex );
    my $first = 1;
    my $multi = @list;
    #foreach my $regex (@list) {
    for( my $i = 0; $i <= $#list; ++$i ) {
      my $regex = $list[$i];
      while ($regex && $regex =~ m/^</ && $regex !~ m/>$/ && $list[++$i] ) {
        $regex .= ",". $list[$i];
      }
      my $h = $h;
      if( $regex && $regex =~ m/^<(.*)>$/ ) {
        my $txt = $1;
        my $readings;
        $item++;
        if( $txt =~ m/^{(.*)}(@[\w\-|.*]+)?$/ ) {
          $txt = "{$1}";
          $readings = $2;

          my $new_line = $first;
          my $DEVICE = $name;
          ($txt,$new_line) = eval $txt;
          $first = $new_line if( defined($new_line) );
          if( $@ ) {
            $txt = "<ERROR>";
            Log3 $d, 3, $d .": ". $regex .": ". $@;
          }
          next if( !defined($txt) );
        }

        my $name_style = lookup2($name_style,$name,$1,undef);

        if( $txt eq 'br' ) {
          $ret .= sprintf("<tr class=\"%s\">", ($row-1&1)?"odd":"even");
          $ret .= "<td><div $name_style class=\"dname\"></div></td>";
          $first = 0;
          next;
        } elsif( $txt && $txt =~ m/^%([^%]*)(%(.*))?/ ) {
          my $icon = $1;
          my $cmd = $3;
          $txt = FW_makeImage( $icon, $icon, "icon" );

          $cmd = lookup2($commands,$name,$d,$icon) if( !defined($cmd) );
          ($txt,undef) = readingsGroup_makeLink($txt,undef,$cmd);

        } elsif( $first || $multi == 1 ) {
          $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
          $row++;

          if( $h != $hash ) {
            my $a = AttrVal($name, "alias", $name);
            my $m = "$a$separator";
            $m = $a if( $multi != 1 );
            my $room = AttrVal($name, "room", "");
            my $group = AttrVal($name, "group", "");
            my $txt = lookup($mapping,$name,$a,"","",$room,$group,$m);

            $ret .= "<td><div $name_style class=\"dname\">$txt</div></td>";
          }
        }
        my $inform_id = "";
        $inform_id = "informId=\"$d-i$item.item\"" if( $readings );
        $ret .= "<td><div $name_style $inform_id>$txt</div></td>";
        $first = 0;
        next;
      } elsif( $regex && $regex =~ m/^\+(.*)/ ) {
        $regex = $1;
      } elsif( $regex && $regex =~ m/^\?(.*)/ ) {
        $regex = $1;
        $h = $attr{$name};
      } else {
        $h = $h->{READINGS};
      }

      foreach my $n (sort keys %{$h}) {
        next if( $n =~ m/^\./);
        next if( $n eq "state" && !$show_state && (!defined($regex) || $regex ne "state") );
        if( defined($regex) ) {
          eval { $n =~ m/^$regex$/ };
          if( $@ ) {
            Log3 $name, 3, $name .": ". $regex .": ". $@;
            last;
          }
        next if( $n !~ m/^$regex$/);
        }
        my $val = $h->{$n};

        my ($v, $t);
        if(ref($val)) {
          next if( ref($val) ne "HASH" || !defined($val->{VAL}) );
          ($v, $t) = ($val->{VAL}, $val->{TIME});
          $v = FW_htmlEscape($v);
          $t = "" if(!$t);
          $t = "" if( $multi != 1 );
        } else {
          $v = FW_htmlEscape($val);
        }

        my $name_style = lookup2($name_style,$name,$n,$v);
        my $value_style = lookup2($value_style,$name,$n,$v);

        my $value_format = lookup2($value_format,$name,$n,$v);
        next if( !defined($value_format) );
        if(  $value_format =~ m/%/ ) {
          $v = sprintf( $value_format, $v );
        } elsif( $value_format ) {
          $v = $value_format;
        }

        my $value_columns = lookup2($value_columns,$name,$n,$v);

        my $a = AttrVal($name, "alias", $name);
        my $m = "$a$separator$n";
        $m = $a if( $multi != 1 );
        my $room = AttrVal($name, "room", "");
        my $group = AttrVal($name, "group", "");
        my $txt = lookup($mapping,$name,$a,$n,$v,$room,$group,$m);

        if( $nameIcon ) {
          if( my $icon = lookup($nameIcon,$name,$a,$n,$v,$room,$group,"") ) {
            $txt = FW_makeImage( $icon, $txt, "icon" );
          }
        }

        my $cmd;
        my $devStateIcon;
        if( $valueIcon ) {
          if( my $icon = lookup($valueIcon,$name,$a,$n,$v,$room,$group,"") ) {
            if( $icon =~ m/^[\%\$]devStateIcon$/ ) {
              my %extPage = ();
              my ($allSets, $cmdlist, $txt) = FW_devState($name, $room, \%extPage);
              $devStateIcon = $txt;
            } else {
              $devStateIcon = FW_makeImage( $icon, $v, "icon" );
              $cmd = lookup2($commands,$name,$n,$icon);
              $cmd = lookup2($commands,$name,$n,$v) if( !$cmd );
            }
          }
        }

        $cmd = lookup2($commands,$name,$n,$v) if( !$devStateIcon );
        ($v,$devStateIcon) = readingsGroup_makeLink($v,$devStateIcon,$cmd);

        if( $first || $multi == 1 ) {
          $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
          $row++;
        }

        $txt = "<a href=\"/fhem?detail=$name\">$txt</a>" if( $show_links );
        $v = "<div $value_style>$v</div>" if( $value_style && !$devStateIcon );

        $ret .= "<td><div $name_style class=\"dname\">$txt</div></td>" if( $first || $multi == 1 );
        $ret .= "<td informId=\"$d-$name.$n\">$devStateIcon</td>" if( $devStateIcon );
        $ret .= "<td $value_columns><div informId=\"$d-$name.$n\">$v</div></td>" if( !$devStateIcon );
        $ret .= "<td><div $timestamp_style informId=\"$d-$name.$n-ts\">$t</div></td>" if( $show_time && $t );

        $first = 0;
      }
    }
  }
  $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
  $ret .= "<td colspan=\"99\"><div style=\"color:#ff8888;text-align:center\">updates disabled</div></td></tr>" if( $disable > 0 );
  $ret .= "</table></td></tr>";
  $ret .= "</table>";

  return $ret;
}
sub
readingsGroup_detailFn()
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $hash = $defs{$d};

  if( 1 || $hash->{alwaysTrigger} ) {
    delete( $hash->{helper}->{myDisplay} );
  } else {
    Log3 $hash->{NAME}, 5, "opened: $FW_cname";
    $hash->{helper}->{myDisplay}->{$FW_cname} = 1;
  }

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

  return if( AttrVal($name,"disable", 0) > 0 );

  if( 1 || $hash->{alwaysTrigger} ) {
  } elsif( !defined($hash->{helper}{myDisplay})
      || !%{$hash->{helper}{myDisplay}} ) {
    Log3 $name, 5, "$name: not on any display, ignoring notify";
    return undef;
  } else {
    foreach my $display ( keys %{$hash->{helper}{myDisplay}} ) {
      if( defined($defs{$display}) ) {
        my $filter = $defs{$display}->{inform};
        return undef if( !defined($filter) );
        my $rn = AttrVal($name, "room", "");
        if($filter eq "all" || $rn =~ m/\b$filter\b/) {
          Log3 $name, 5, "$name: do update";
        } else {
          Log3 $name, 5, "$name: $display is not my room, ignoring notify";
          delete( $hash->{helper}{myDisplay}{$display} );
          return undef;
        }
      } else {
        Log3 $name, 5, "$name: $display is closed, ignoring notify";
        delete( $hash->{helper}{myDisplay}{$display} );
        return undef;
      }
    }
  }

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
      my $show_state = 1;
      if( $value eq "" ) {
        $show_state = !AttrVal( $name, "nostate", "0" );
        #next if( !$show_state );

        $reading = "state";
        $value = $s;
      }

      my $value_style = AttrVal( $name, "valueStyle", "" );

      my $value_format = AttrVal( $name, "valueFormat", "" );
      if( $value_format =~ m/^{.*}$/ ) {
        my $vf = eval $value_format;
        $value_format = $vf if( $vf );
      }

      my $valueIcon = AttrVal( $name, "valueIcon", "");
      $valueIcon = eval $valueIcon if( $valueIcon =~ m/^{.*}$/ );

      my $commands = AttrVal( $name, "commands", "" );
      $commands = eval $commands if( $commands =~ m/^{.*}$/ );


      foreach my $device (@{$devices}) {
        my $item = 0;
        my $h = $defs{@{$device}[0]};
        next if( !$h );
        next if( $dev->{NAME} ne $h->{NAME} );
        my $regex = @{$device}[1];
        my @list = (undef);
        @list = split(",",$regex) if( $regex );
        #foreach my $regex (@list) {
        for( my $i = 0; $i <= $#list; ++$i ) {
        my $regex = $list[$i];
          while ($regex && $regex =~ m/^</ && $regex !~ m/>$/ && $list[++$i] ) {
            $regex .= ",". $list[$i];
          }
          next if( $reading eq "state" && !$show_state && (!defined($regex) || $regex ne "state") );
          next if( $regex && $regex =~ m/^\+/ );
          next if( $regex && $regex =~ m/^\?/ );
          if( $regex && $regex =~ m/^<(.*)>$/ ) {
            my $txt = $1;
            my $readings;
            $item++;
            if( $txt =~ m/^{(.*)}(@([\w\-|.*]+))?$/ ) {
              $txt = "{$1}";
              $readings = $3;

              next if( !$readings );
              next if( $reading !~ m/^$readings$/);

              my $new_line;
              my $DEVICE = $dev->{NAME};
              ($txt,$new_line) = eval $txt;
              if( $@ ) {
                $txt = "<ERROR>";
                Log3 $name, 3, $name .": ". $regex .": ". $@;
              }
              $txt = "" if( !defined($txt) );

              if( $txt && $txt =~ m/^%([^%]*)(%(.*))?/ ) {
                my $icon = $1;
                my $cmd = $3;

                $cmd = lookup2($commands,$name,$h->{NAME},$icon) if( !defined($cmd) );
                $txt = FW_makeImage( $icon, $icon, "icon" );
                ($txt,undef) = readingsGroup_makeLink($txt,undef,$cmd);
              }

              CommandTrigger( "", "$name i$item.item: $txt" );
            }

            next;
          }

          next if( defined($regex) && $reading !~ m/^$regex$/);

          my $value_style = lookup2($value_style,$dev->{NAME},$reading,$value);

          my $value = $value;
          if( $value_format ) {
            my $value_format = lookup2($value_format,$dev->{NAME},$reading,$value);

            if( !defined($value_format) ) {
              $value = "";
            } elsif( $value_format =~ m/%/ ) {
              $value = sprintf( $value_format, $value );
            } elsif( $value_format ) {
              $value = $value_format;
            }
          }

          my $cmd;
          my $devStateIcon;
          if( $valueIcon ) {
            my $n = $h->{NAME};
            my $a = AttrVal($n, "alias", $n);
            my $room = AttrVal($n, "room", "");
            my $group = AttrVal($n, "group", "");
            if( my $icon = lookup($valueIcon,$n,$a,$reading,$value,$room,$group,"") ) {
              if( $icon eq "%devStateIcon" ) {
                my %extPage = ();
                my ($allSets, $cmdlist, $txt) = FW_devState($n, $room, \%extPage);
                $devStateIcon = $txt;
              } else {
                $devStateIcon = FW_makeImage( $icon, $value, "icon" );
                $cmd = lookup2($commands,$n,$reading,$icon);
                $cmd = lookup2($commands,$n,$reading,$value) if( !$cmd );
              }
            }

            if( $devStateIcon ) {
              (undef,$devStateIcon) = readingsGroup_makeLink(undef,$devStateIcon,$cmd);

              CommandTrigger( "", "$name $n.$reading: $devStateIcon" );
              next;
            }
          }

          $cmd = lookup2($commands,$dev->{NAME},$reading,$value);
          ($value,undef) = readingsGroup_makeLink($value,undef,$cmd);

          $value = "<div $value_style>$value</div>" if( $value_style );

          CommandTrigger( "", "$name $dev->{NAME}.$reading: $value" );
        }
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

sub
readingsGroup_Attr($$$)
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
      <li>&lt;device&gt; can be of the form &lt;STRING&gt; or &lt;{perl}&gt; where STRING or the string returned by perl is
          inserted as a line in the readings list. skipped if STRING is undef.</li>
      <li>If regex is a comma separatet list the reading values will be shown on a single line.</li>
      <li>If regex starts with a '+' it will be matched against the internal values of the device instead of the readings.</li>
      <li>If regex starts with a '?' it will be matched against the attributes of the device instead of the readings.</li>
      <li>regex can be of the form &lt;STRING&gt; or &lt;{perl}[@readings]&gt; where STRING or the string returned by perl is
          inserted as a reading or:
          <ul><li>the item will be skipped if STRING is undef</li>
              <li>if STRING is br a new line will be started</li>
              <li>if STRING is of the form %ICON[%CMD] ICON will be used as the name of an icon instead of a text and CMD
                  as the command to be executed if the icon is clicked. also see the commands attribute.</li></ul>
          if readings is given the perl expression will be reevaluated during longpoll updates.</li>
      <li>For internal values and attributes longpoll update is not possible. Refresh the page to update the values.</li>
      <li>the &lt;{perl}&gt; expression is limited to expressions without a space. it is best just to call a small sub
          in 99_myUtils.pm instead of having a compex expression in the define.</li>
    </ul><br>

    Examples:
    <ul>
      <code>
        define batteries readingsGroup .*:battery</code><br>
      <br>
        <code>define temperatures readingsGroup s300th.*:temperature</code><br>
        <code>define temperatures readingsGroup TYPE=CUL_WS:temperature</code><br>
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
        attr systemStatus mapping {'load' => 'Systemauslastung', 'temperature' => 'Systemtemperatur in &amp;deg;C'}<br>
      <br>
        define Verbrauch readingsGroup TYPE=PCA301:state,power,consumption<br>
        attr Verbrauch mapping %ALIAS<br>
        attr Verbrauch nameStyle style="font-weight:bold"<br>
        attr Verbrauch style style="font-size:20px"<br>
        attr Verbrauch valueFormat {power => "%.1f W", consumption => "%.2f kWh"}<br>
        attr Verbrauch valueIcon { state => '%devStateIcon' }<br>
        attr Verbrauch valueStyle {($READING eq "power" && $VALUE > 150)?'style="color:red"':'style="color:green"'}<br>
      <br>
        define rg_battery readingsGroup TYPE=LaCrosse:[Bb]attery<br>
        attr rg_battery alias Batteriestatus<br>
        attr rg_battery commands { "battery.low" => "set %DEVICE replaceBatteryForSec 60" }<br>
        attr rg_battery valueIcon {'battery.ok' => 'batterie', 'battery.low' => 'batterie\@red'}<br>
      <br>
        define rgMediaPlayer readingsGroup myMediaPlayer:currentTitle,<>,totaltime,<br>,currentAlbum,<>,currentArtist,<br>,volume,<{if(ReadingsVal($DEVICE,"playStatus","")eq"paused"){"%rc_PLAY%set+$DEVICE+play"}else{"%rc_PAUSE%set+$DEVICE+pause"}}@playStatus>,playStatus<br>
        attr rgMediaPlayer commands { "playStatus.paused" => "set %DEVICE play", "playStatus.playing" => "set %DEVICE pause" }<br>
        attr rgMediaPlayer mapping &nbsp;<br>
        attr rgMediaPlayer notime 1<br>
        attr rgMediaPlayer valueFormat { "volume" => "Volume: %i" }<br>
        #attr rgMediaPlayer valueIcon { "playStatus.paused" => "rc_PLAY", "playStatus.playing" => "rc_PAUSE" }<br>
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
      <li>valueColumns<br>
        Specify an HTML colspan for the reading values, e.g.:<br>
          <code>attr wzReceiverRG valueColumns { eventdescription => 'colspan="4"' }</code></li>
      <li>valueFormat<br>
        Specify an sprintf style format string used to display the reading values. If the format string is undef
        this reading will be skipped. Can be given as a string, a perl expression returning a hash or a perl
        expression returning a string, e.g.:<br>
          <code>attr temperatures valueFormat %.1f &deg;C</code></br>
          <code>attr temperatures valueFormat { temperature => "%.1f &deg;C", humidity => "%.1f %" }</code></br>
          <code>attr temperatures valueFormat { ($READING eq 'temperature')?"%.1f &deg;C":undef }</code></li>
      <li>nameIcon<br>
        Specify the icon to be used instead of the reading name. Can be a simple string or a perl expression enclosed
        in {} that returns a hash that maps reading names to the icon name. e.g.:<br>
          <code>attr devices nameIcon $DEVICE</code></li>
      <li>valueIcon<br>
        Specify an icon to be used instead of the reading value. Can be a simple string or a perl expression enclosed
        in {} that returns a hash that maps reading value to the icon name. e.g.:<br>
          <code>attr devices valueIcon $VALUE</code></br>
          <code>attr devices valueIcon {state => '%VALUE'}</code></br>
          <code>attr devices valueIcon {state => '%devStateIcon'}</code>
          <code>attr rgMediaPlayer valueIcon { "playStatus.paused" => "rc_PLAY", "playStatus.playing" => "rc_PAUSE" }</code></li>
      <li>commands<br>
        Makes a reading or icon clickable and specifies the command that should be executed. eg.:<br>
        <code>attr rgMediaPlayer commands { "playStatus.paused" => "set %DEVICE play", "playStatus.playing" => "set %DEVICE pause" }</code></li>
    </ul><br>

      The nameStyle and valueStyle attributes can also contain a perl expression enclosed in {} that returns the style
      string to use. The perl code can use $DEVICE,$READING and $VALUE, e.g.:<br>
    <ul>
          <code>attr batteries valueStyle {($VALUE ne "ok")?'style="color:red"':'style="color:green"'}</code><br>
          <code>attr temperatures valueStyle {($DEVICE =~ m/aussen/)?'style="color:green"':'style="color:red"'}</code>
    </ul>
      Note: Only valueStyle, valueFomat, valueIcon and <{...}@reading> are evaluated during longpoll updates
      and valueStyle has to return a non empty style for every possible value. All other perl expressions are
      evaluated only once during html creation and will not reflect value updates with longpoll.
      Refresh the page to update the dynamic style. For nameStyle the color attribut is not working at the moment,
      the font-... and background attributes do work.
</ul>

=end html
=cut
