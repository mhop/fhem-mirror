################################################################################
# 99 TXT
# Feedback: http://groups.google.com/group/fhem-users
# TXT WEBINTERFACE
#
# Feedback: http://groups.google.com/group/fhem-users
# Autor: Axel Rieger fhem[bei]anax.info
# Stand: 05.07.2012
# Version: 1.0
#
################################################################################
# Usage:
# Values seperated by Semikolon
# FHEM-BASE-URL: http://<MyFHEM-IP>/FHEM/
# # Info returns FHEM&FHEMTXT Version -> /TXT/INFO
# 
# /TXT -> Lists alle Devices with <DeviceName>;<DEVCIE-TYPE>;<ROOM>;<STATE>
#
# Devices By Type
# /TXT/TYPE/<DeviceType> -> <DeviceName>;<STATE>
#
# Devices By ROOM
# /TXT/ROOM -> Lists All Rooms <ROOM-NAME>
# /TXT/ROOM/<ROOM-NAME> -> <DeviceName>;<DEVCIE-TYPE>;<ROOM>;<STATE>
#
# Devices ALL / By Name
# /TXT/DEFS -> List alls Devices <DEVICE-NAME>;<STATE>
# /TXT/DEFS/<DEVICE-NAME> ->
#   READ = READINGS -> READ;<READINGS-NAME>;<VALUE>;<TIMESTAMP>
#   ATTR = Attributes -> ATTR;<ATTR-NAME>;<VALUE>
#   INT = Internals -> INT;<NAME>;<VALUE>
# /TXT/DEFS/<DEVICE-NAME>/READINGS -> READINGS <READINGS-NAME>;<VALUE>;<TIMESTAMP>
# /TXT/DEFS/<DEVICE-NAME>/ATTR -> Attributes <ATTR-NAME>;<VALUE>
# /TXT/DEFS/<DEVICE-NAME>/INT -> Internals <NAME>;VALUE>
#
# FHEM-Commands
# /TXT/CMD/<command>;<parameters>
# Values seperated by Semikolon
# Returns OK if Command has no Output
# Otherwise Command-Output
# TXT-Commands
# Test returns 1 -> /TXT/CMD/TEST 
# List all FHEM CMDs -> /TXT/CMD/ALL
# State for DeviceList -> /TXT/CMD/LIST_STATE
#   DeviceList: <Device01>;<Device01>;<Device03>... -> Returns: <STATE01>;<STATE02>;<STATE03>;...
################################################################################
package main;
use strict;
use warnings;
use vars qw(%data);
#-------------------------------------------------------------------------------
sub TXT_Initialize($)
{
  my ($hash) = @_;
  # CGI
  my ($name,$fhem_url);
  $name = "TXT";
  $fhem_url = "/" . $name ;
  $data{FWEXT}{$fhem_url}{FUNC} = "TXT_CGI";
  $data{FWEXT}{$fhem_url}{LINK} = $name;
  $data{FWEXT}{$fhem_url}{NAME} = $name;
  # Lookup URI -> CallBack-Funktion
  $data{T9X9T}{DEFS}{FUNC} = "txt_uri_defs";
  $data{T9X9T}{TYPE}{FUNC} = "txt_uri_type";
  $data{T9X9T}{ROOM}{FUNC} = "txt_uri_room";
  $data{T9X9T}{CMD}{FUNC} = "txt_uri_cmd";
  $data{T9X9T}{INFO}{FUNC} = "txt_uri_info";

  # Eigene Commands
  $data{T9X9T}{CMD}{EXEC}{ALL} = "exec_all";
  $data{T9X9T}{CMD}{EXEC}{TEST} = "exec_test";
  $data{T9X9T}{CMD}{EXEC}{LIST_STATE} = "exec_list_state";
  return undef;
}
#-------------------------------------------------------------------------------
sub TXT_CGI() {
  my ($htmlarg) = @_;
  Log 5, "TXT HTMLARG $htmlarg";
  my ($ret_html,$uri,$callback);
  # Remove trailing slash
  $htmlarg =~ s/\/$//;
  # $ret_html = "TXT HTMLARG $htmlarg";
  my @params = split(/\//,$htmlarg);
  $uri = undef;
  if($params[2]) {
    $uri = $params[2];
    if (defined($data{T9X9T}{$uri}{FUNC})) {
      $callback = $data{T9X9T}{$uri}{FUNC};
        $htmlarg =~ s/TXT\///;
        no strict "refs";
        # Call Function
        Log 5,"TXT URI-DISPATCHER -> $uri";
        $ret_html = &$callback($htmlarg);
        use strict "refs";
        }
    else {$ret_html = "ERROR;URI_NOT_FOUND;" . $uri;}
   }
   else {
    # Lists alle Devices with <DeviceName>;<DEVCIE-TYPE>;<ROOM>;<STATE>
    foreach my $d (sort keys %defs) {
    $ret_html .= $d . ";" ;
    $ret_html .= $defs{$d}{TYPE} . ";" ;
    if(defined($attr{$d}{ROOM})) {$ret_html .= $attr{$d}{ROOM} . ";" ;}
    else {$ret_html .= ";";}
    $ret_html .= $defs{$d}{STATE} . "\n" ;
    }
   }
  return ("text/plain; charset=ISO-8859-1", $ret_html);
}
#-------------------------------------------------------------------------------
sub txt_uri_defs() {
  my ($params) = @_;
  my $ret;
  my @args = split(/\//,$params);
  # $ret .= "ARG-COUNT: " . @args . "\n";
  # $ret .= "ARG-VALUE: " . join(";",@args) . "\n";
  my $def_name = "xxx";
  if(int(@args) > 2) {
    $def_name = $args[2];
    if(!defined($defs{$def_name})) {
      $ret .= "ERROR;DEVICE_NOT_FOUND;$def_name\n";
      return $ret;
    }
  }
  # Show All Devices with STATE
  if($params =~ m/^\/DEFS$/) {
    # List alle Device Names
    foreach my $d (sort keys %defs) {
    $ret .= "$d;" . $defs{$d}{STATE} . "\n";
    }
  }
  # List alle READINGS
  elsif($params =~ m/^\/DEFS.*\/READ/) {
    $ret .= &txt_uri_defs_readings($def_name);
  }
  # List alle ATTRIBUTES
  elsif($params =~ m/^\/DEFS.*\/ATTR/) {
  $ret .= &txt_uri_defs_attributes($def_name);
  }
  elsif($params =~ m/^\/DEFS.*\/INT/) {
    $ret .= &txt_uri_defs_internals($def_name);
    }
  else {
    $ret .= "###READINGS\n";
    $ret .= &txt_uri_defs_readings($def_name);
    $ret .= "###ATTR\n";
    $ret .= &txt_uri_defs_attributes($def_name);
    $ret .= "###INT\n";
    $ret .= &txt_uri_defs_internals($def_name);
    }
  return $ret;
}
#-------------------------------------------------------------------------------
sub txt_uri_defs_readings() {
  my ($d) = @_;
  my $ret;
  foreach my $r (sort keys %{$defs{$d}{READINGS}}) {
  $ret .= $r . ";" . $defs{$d}{READINGS}{$r}{VAL} . ";" . $defs{$d}{READINGS}{$r}{TIME} . "\n";
  }
  return $ret;
  }
#-------------------------------------------------------------------------------
sub txt_uri_defs_attributes() {
  my ($d) = @_;
  my $ret;
  foreach my $a (sort keys %{$attr{$d}}) {
    $ret .= $a . ";" . $attr{$d}{$a} . "\n";
    }
  return $ret;
  }
#-------------------------------------------------------------------------------
sub txt_uri_defs_internals() {
  my ($d) = @_;
  my $ret;
  foreach my $i (sort keys %{$defs{$d}}) {
    next if($i eq "READINGS");
    $ret .= $i . ";" . $defs{$d}{$i} . "\n";
    }
  return $ret;
  }
#-------------------------------------------------------------------------------
sub txt_uri_type() {
  my ($params) = @_;
  my @args = split(/\//,$params);
  my ($type,$d,$ret);
  if(int(@args) > 2) {
    $type = $args[2];
      foreach $d (sort keys %defs ) {
      next if(IsIgnored($d));
      next if($defs{$d}{TYPE} ne $type);
      $ret .= $d . ";" . $defs{$d}{STATE} . "\n";
    }
    return $ret;
  }
  # List all Types
  my %types;
  foreach $d (sort keys %defs ) {
    next if(IsIgnored($d));
    $types{$defs{$d}{TYPE}}{$d} = 1;
  }
  foreach my $k (sort keys %types) {
    $ret .= $k . "\n";
  }
  return $ret;
}
#-------------------------------------------------------------------------------
sub txt_uri_room() {
  my ($params) = @_;
  my @args = split(/\//,$params);
  my ($ret,$room,$d,$r);
  # Get All Rooms
  my (%rooms,$dev_room);
  foreach my $d (keys %defs ) {
    next if(IsIgnored($d));
    if (!$attr{$d}{room}) {
        $dev_room = "Default";
    }
    else {
         $dev_room = $attr{$d}{room};
    }
    Log 5,"TXT ROOM: $d:" . $dev_room;
    foreach my $r (split(",", $dev_room)) {
      $rooms{$r}{$d} = 1;
    }
  }
  # List Devices in ROOM yxz with STATE
  if(int(@args) > 2) {
    $room = $args[2];
    if(defined($rooms{$room})){
      foreach $d (sort keys %{$rooms{$room}}) {
        $ret .= $d . ";" . $defs{$d}{STATE} . "\n";
        }
      return $ret;
      }
    else {return "ERROR;ROOM_NOT_FOUND;" . $room;}
  }
  # List alle Rooms
  foreach $r (sort keys %rooms) {
    $ret .= $r . "\n";
  }
  return $ret;
}
#-------------------------------------------------------------------------------
sub txt_uri_cmd() {
    my ($params) = @_;
    my @args = split(/\//,$params);
    my ($ret,$cmd,$cmd_ret);
    $cmd = $args[2];
    if ($cmd =~ m/\%20/) { $cmd =~ s/\%20/ /g}
    if ($cmd =~ m/;/) { $cmd =~ s/;/ /g}
    if ($cmd =~ m/\%25/) { $cmd =~ s/\%25/\%/g}
    Log 5,"TXT CMD " . $cmd;
    if(defined $data{T9X9T}{CMD}{EXEC}{$cmd}) {
        Log 5,"TXT EXEC " . $params;
        my $callback = $data{T9X9T}{CMD}{EXEC}{$cmd};
        no strict "refs";
        # Call Function
        $ret = &$callback($params);
        use strict "refs";
        return $ret;
    }
    # Excute FHEM-Command
    $cmd_ret = fhem "$cmd";
    if (!$cmd_ret) {
        $ret = "OK" ;
    } else {
        $ret = "$cmd_ret"
    }
    $ret .= "\n";
    return $ret;
}
#-------------------------------------------------------------------------------
sub exec_all() {
    # List all FHEM CMDs
    my $ret = "";
    foreach my $c (sort keys %{cmds}) {
        $ret .= $c . "\n";
    }
    return $ret;

}
#-------------------------------------------------------------------------------
sub exec_list_state() {
  # List State for Device Array
  my ($params) = @_;
  # STATE/CMD/LIST_STATE/def1;def2
  my ($ret,@args,@defs,$d);
  @args = split(/\//,$params);
  @defs = split(/;/,$args[$#args]);
  Log 5,"TXT EXEC LIST STATE: " . int(@defs);
  if(int(@defs) gt 0 ) {
    foreach(@defs) {
      if(defined($defs{$_})) {
        $ret .= $defs{$_}{STATE} . "\n";
      }
      else { $ret.= "ERROR" . "\n";
      }
    }
  }
  return $ret;
}
#-------------------------------------------------------------------------------
sub exec_test() {
    return "1" . "\n";
}
#-------------------------------------------------------------------------------
sub txt_uri_info() {
    my ($params) = @_;
    # my @args = split(/\//,$params);
    my($ret,$TXTVersion,$FHEMVersion);
    # Version
    $TXTVersion = "FHTMTXT:01.07.2012\n";
    # FHEM Version
    # =VERS= from =DATE= ($Id: fhem.pl 1204 2012-01-22 12:21:05Z rudolfkoenig $)
    my @a = split(/\$/,$attr{global}{version});
    my @b = split(/\s+/,$a[1]);
    $FHEMVersion = "FHEM: " . $b[2] . " " . $b[3];
    $ret = $FHEMVersion . "\n";
    $ret .= $TXTVersion;
}
#-------------------------------------------------------------------------------
1;
