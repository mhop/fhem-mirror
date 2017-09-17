# $Id$

##############################################################################
#
#     83_IOhomecontrol.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
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
use HttpUtils;
use JSON;
use Data::Dumper;

#####################################
sub IOhomecontrol_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}        = "IOhomecontrol_Define";
  $hash->{UndefFn}      = "IOhomecontrol_Undef";
  $hash->{GetFn}        = "IOhomecontrol_Get";
  $hash->{SetFn}        = "IOhomecontrol_Set";
  $hash->{parseParams}  = 1;
  #$hash->{AttrFn}  = "IOhomecontrol_Attr";
  $hash->{AttrList}     = "setCmds " . $readingFnAttributes;
}

#####################################
sub IOhomecontrol_Define($$) {

  # define <name> IOhomecontrol <model> <host> <pwfile>
  my ($hash, $argref, undef) = @_;
 
  my @def= @{$argref};
  if($#def != 4) {
    my $msg = "wrong syntax: define <name> IOhomecontrol <model> <host> <pwfile>";
    Log 2, $msg;
    return $msg;
  }
  
  my $name = $def[0];
  my $unused = $def[2];
  my $host = $def[3];
  my $pwfile = $def[4];
 
  $hash->{"host"}= $host;
  $hash->{"pwfile"}= $pwfile;
  $hash->{fhem}{".token"}= undef;
  $hash->{fhem}{".scenes"}= undef;
  
  $hash->{STATE} = "Initialized";
  
  return undef;
}


#####################################
sub IOhomecontrol_Undef($$) {
  return undef;
}

#####################################
# Internals
#####################################

sub IOhomecontrol_Exec($$$$) {

  my ($hash, $api, $action, $params) = @_;
  my $name = $hash->{NAME};
  my $host = $hash->{"host"};
  my $token = $hash->{fhem}{".token"};
    
  # build header
  my $header = {
    "Accept" => "application/json",
    "Content-Type" => "application/json;charset=utf-8",
  };
  if(defined($token)) {
    $header->{"Authorization"} = "Bearer $token";
  };

  # build payload
  my $payload = {
    "action" => $action,
    "params" => $params,
  };
  my $json = encode_json $payload;
  #Debug "IOhomecontrol $name: sending $json";
  
  # build HTTP request
  my $httpParams = {
    url         =>  "http://$host/api/v1/$api",
    timeout     => 2,
    method      => "POST",
    noshutdown  => 1,
    keepalive   => 0,
    httpversion => "1.1",
    header      => $header,
    data        => $json,
  };
  
  my ($err, $data)= HttpUtils_BlockingGet($httpParams);
  
  if(defined($err) && $err) {
    Log3 $hash, 2, "IOhomecontrol $name returned error: $err";
    return undef;
  } else {
    if(defined($data) && $data) {
      # strip junk from the beginning
      $data =~ s/^\)\]\}\',//;
      #Debug "IOhomecontrol $name: data $data";
      my $result = decode_json $data;
      #Debug Dumper $result;
      my $errorsref= $result->{errors};
      my @errors= @{$errorsref};
      $err= "";
      if(@errors) {
        $err= join(" ", @errors);
        Log3 $hash, 2, "IOhomecontrol $name: API $api, action $action returned errors ($err).";
      };
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "deviceStatus", $result->{deviceStatus});
      readingsBulkUpdate($hash, "errors", $err);
      readingsEndUpdate($hash, 1);
      return undef if(@errors);
      return $result; # this is a hash reference
    } else {
      Log3 $hash, 2, "IOhomecontrol $name returned no data.";
      return undef;
    }
  }

}

#####################################

sub IOhomecontrol_getPassword($) {
  my $hash = shift;
  
  my $pwfile= $hash->{"pwfile"};
  if(open(PWFILE, $pwfile)) {
    my @contents= <PWFILE>;
    close(PWFILE);
    return undef unless @contents;
    my $password = $contents[0];
    chomp $password;
    return $password;
  } else {
    return undef;
  }

}

sub IOhomecontrol_Login($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  Log3 $hash, 4, "IOhomecontrol $name: Logging in...";
  my $password = IOhomecontrol_getPassword($hash);
  if(!defined($password)) {
    Log3 $hash, 2, "IOhomecontrol $name: No password.";
    return 0;
  }
  my $params = { "password" => $password };
  my $result= IOhomecontrol_Exec($hash, "auth", "login", $params);
  if(defined($result)) {
    my $token= $result->{token};
    Log3 $hash, 4, "IOhomecontrol $name got token: $token";
    $hash->{fhem}{".token"}= $token;
    return 1;
  } 
  return 0;
}

sub IOhomecontrol_Logout($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  Log3 $hash, 4, "IOhomecontrol $name: Logging out...";
  my $params = { };
  my $result= IOhomecontrol_Exec($hash, "auth", "logout", $params);
  if(defined($result)) {
    Log3 $hash, 4, "IOhomecontrol $name logged out.";
    $hash->{fhem}{".token"}= undef;
  } 
  return undef;
}

sub IOhomecontrol_Action($$$$) {
  my ($hash, $api, $action, $params) = @_;
  my $name = $hash->{NAME};
  
  Log3 $hash, 4, "IOhomecontrol $name: API $api, action $action";
  if(IOhomecontrol_Login($hash)) {
    my $result= IOhomecontrol_Exec($hash, $api, $action, $params);
    IOhomecontrol_Logout($hash);
    return $result;
  } 
  return undef;
}


#####################################
sub IOhomecontrol_makeScenes($) {
  my $hash= shift;
  
  my $scenes= $hash->{fhem}{".scenes"};
  if(!defined($scenes)) {
    $scenes= IOhomecontrol_getScenes($hash);
    $hash->{fhem}{".scenes"} = $scenes;
  } 
  my $sc= {};
  if(defined($scenes)) {
    my $data= $scenes->{data};
    #Debug "data: " . Dumper $data;
    foreach my $item (@{$data}) {
      #Debug "data item: " . Dumper $item;
      my $name= $item->{name};
      my $id= $item->{id};
      #Debug "$id: $name";
      $sc->{$id}= $name;
    }
    my $sns= "";
    foreach my $id (sort keys %{$sc}) {
      $sns.="," if($sns);
      $sns.= sprintf("%d: %s", $id, $sc->{$id});
    }
    readingsSingleUpdate($hash, "scenes", $sns, 1);
  }
  return $sc; # a hash id => name
}

sub IOhomecontrol_getScenes($) {
  my $hash= shift;
  my $scenes= IOhomecontrol_Action($hash, "scenes", "get", {}); 
  #Debug Dumper $scenes;
  return $scenes;
}  

sub IOhomecontrol_runSceneById($$$) {
  my ($hash, $id, $name)= @_;
  IOhomecontrol_Action($hash, "scenes", "run", { id => $id }); 
  readingsSingleUpdate($hash, "lastScene", $name, 1);
}  

#####################################
sub IOhomecontrol_Get($@) {
  my ($hash, $argsref, undef) = @_;

  my @a= @{$argsref};
  return "get needs at least one parameter" if(@a < 2);

  my $name = $a[0];
  my $cmd= $a[1];
  my $arg = ($a[2] ? $a[2] : "");
  my @args= @a; shift @args; shift @args;

  my $answer= "";
  if($cmd eq "scenes") {
        $hash->{fhem}{".scenes"}= undef; # forget scenes forces get from device
        my $sc= IOhomecontrol_makeScenes($hash);
        foreach my $id (sort keys %{$sc}) {
          $answer.="\n" if($answer);
          $answer.= sprintf("%2d: %s", $id, $sc->{$id});
        }
  }  else {
        return "Unknown argument $cmd, choose one of scenes:noArg";
  }

  return $answer;
}


#####################################

# sub IOhomecontrol_Attr($@) {
# 
#   my @a = @_;
#   my $hash= $defs{$a[1]};
#   my $name= $hash->{NAME};
# 
#   if($a[0] eq "set") {
#     if($a[2] eq "") {
#     }
#   }
# 
#   return undef;
# }


#####################################
sub IOhomecontrol_getSetCmds($) {
  my $hash= shift;
  my $name= $hash->{NAME};
  
  my $attr= AttrVal($name, "setCmds", "");
  my (undef, $setCmds)= parseParams($attr,",");
  return $setCmds;
}


sub IOhomecontrol_Set($$$) {
  my ($hash, $argsref, undef) = @_;

  my @a= @{$argsref};
  return "set needs at least one parameter" if(@a < 2);
  
  my $name = shift @a;
  my $cmd= shift @a;

  my $setCmds= IOhomecontrol_getSetCmds($hash);
  my $usage= "Unknown argument $cmd, choose one of scene " . 
    join(" ", (keys %{$setCmds}));
  if(exists($setCmds->{$cmd})) {
    readingsSingleUpdate($hash, "state", $cmd, 1);
    my $subst= $setCmds->{$cmd};
    Log3 $hash, 4, "IOhomecontrol $name: substitute set command $cmd by $subst";
    ($argsref, undef)= parseParams($subst);
    @a= @{$argsref};
    $cmd= shift @a;
  }
    
  if($cmd eq "scene") {
    if($#a) {
      Debug Dumper @a;
      return "Command scene needs exactly one argument.";
    } else {
      my $sc= IOhomecontrol_makeScenes($hash);
      my $id= $a[0];
      if($id !~ /^\d+$/) {
        #Debug "IOhomecontrol $name: looking up scene $id by name...";
        my %cs= reverse %{$sc};
        $id= $cs{$id};
      }
      my $sn= $sc->{$id};
      if(defined($sn)) {
        Log3 $hash, 4, "IOhomecontrol $name: running scene id $id, name $sn";
        IOhomecontrol_runSceneById($hash, $id, $sn);
      } else {
        return "No such scene $id";
      }
    }
  } else {
    return $usage
  }
  
  return undef;
        
}

#####################################

1;

=pod
=item device
=item summary control IOhomecontrol devices via REST API
=item summary_DE IOhomecontrol-Ger&auml;te mittels REST-API steuern
=begin html

<a name="IOhomecontrol"></a>
<h3>IOhomecontrol</h3>
<ul>

  <a name="IOhomecontroldefine"></a>
  <b>Define</b><br><br>
  <ul>
    <code>define &lt;name&gt; IOhomecontrol &lt;model&gt; &lt;host&gt; &lt;pwfile&gt; </code><br><br>

    Defines a IOhomecontrol device. <code>&lt;model&gt;</code> is a placeholder for future amendments. <code>&lt;host&gt;</code> is the IP address or hostname of the IOhomecontrol device. <code>&lt;pwfile&gt;</code> is a file that contains the password to log into the device.<br><br>

    Example:
    <ul>
      <code>define velux IOhomecontrol KLF200 192.168.0.91 /opt/fhem/etc/veluxpw.txt</code><br>
    </ul>
    <br><br>
  </ul>

  <a name="IOhomecontrolset"></a>
  <b>Set</b><br><br>
  <ul>
    <code>set &lt;name&gt; scene &lt;id&gt;</code>
    <br><br>
    Runs the scene identified by <code>&lt;id&gt;</code> which can be either the numeric id of the scene or the scene's name.
    <br><br>
    Examples:
    <ul>
      <code>set velux scene 1</code><br>
      <code>set velux scene "all shutters down"</code><br>
    </ul>
    <br>
    Scene names with blanks must be enclosed in double quotes.
    <br><br>
  </ul>


  <a name="IOhomecontrolget"></a>
  <b>Get</b><br><br>
  <ul>
    <code>get &lt;name&gt; scenes</code>
    <br><br>
    Retrieves the ids and names of the scenes from the device. 
    <br><br>
    Example: 
    <ul>
      <code>get velux scenes</code><br>
    </ul>
  </ul>
  <br><br>
  
  
  <a name="IOhomecontrolattr"></a>
  <b>Attributes</b>
  <ul>
    <li>setCmds: a comma-separated list of set command definitions.
    Every definition is of the form <code>&lt;shorthand&gt;=&lt;command&gt;</code>. This defines a new single-word command <code>&lt;shorthand&gt</code> as a substitute for <code>&lt;command&gt;</code>.<br>
    Example: <code>attr velux setCmds up=scene "3.dz.roll2 100%",down=scene "3.dz.roll2 0%"</code><br>
    Substituted commands (and only these) are shown in the state reading. This is useful in conjunction with the <code>devStateIcon</code> attribute, e.g. <code>attr velux devStateIcon down:shutter_closed up:shutter_open</code>.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>


</ul>

=end html
=cut
