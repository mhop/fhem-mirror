################################################################
#
#  $Id$
#
#  Maintainer: Sebatian Stuecker / FHEM Forum: unimatrix / Github: unimatrix27
#  
#  FHEM Forum : https://forum.fhem.de/index.php/topic,62389.0.html
#
#  Github: https://github.com/unimatrix27/fhemmodules/blob/master/96_Snapcast.pm
#
#  Feedback bitte nur ins FHEM Forum, Bugs oder Pull Request bitte direkt auf Github. 
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

# This module is used to control a Snapcast Server https://github.com/badaix/snapcast
# This version is tested against https://github.com/badaix/snapcast/tree/98be8a58d945f84af50e40ebcf8a774592dd6e7b
# Future developments beyond this revision are not necessarily supported. 
# The module uses DevIo for communication. There is no blocking communication whatsoever. 
# Communication to Snapcast goes through a TCP Socket, Writing and Reading are managed asynchronously.
# It is necessary to have  JSON module installed. If not, the module will detect this and put a message in the log file.

package main;
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

my %Snapcast_sets = (
    "update"   => 0,
    "volume"   => 2,
    "stream"   => 2,
    "name"     => 2,
    "mute"     => 2,
    "latency"  => 2,
    "group"    => 2,
);

my %Snapcast_client_sets = (
    "volume"   => 1,
    "stream"   => 1,
    "name"     => 1,
    "mute"     => 0,
    "latency"  => 1,
    "group"    => 1,
);

my %Snapcast_clientmethods = (
    "name"             => "Client.SetName",
    "volume"           => "Client.SetVolume",
    "mute"             => "Client.SetVolume",
    "stream"           => "Group.SetStream",
    "latency"          => "Client.SetLatency"
);


sub Snapcast_Initialize($) {
    my ($hash) = @_;
    use DevIo;
    $hash->{DefFn}      = 'Snapcast_Define';
    $hash->{UndefFn}    = 'Snapcast_Undef';
    $hash->{SetFn}      = 'Snapcast_Set';
    $hash->{GetFn}      = 'Snapcast_Get';
    $hash->{WriteFn}    = 'Snapcast_Write';
    $hash->{ReadyFn}    = 'Snapcast_Ready';
    $hash->{AttrFn}     = 'Snapcast_Attr';
    $hash->{ReadFn}     = 'Snapcast_Read';
    $hash->{AttrList} =
          "streamnext:all,playing constraintDummy constraints volumeStepSize volumeStepSizeSmall volumeStepSizeThreshold " . $readingFnAttributes;
}

sub Snapcast_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
    return "ERROR: perl module JSON is not installed" if (Snapcast_isPmInstalled($hash,"JSON"));
    my $name= $hash->{name}  = $a[0];
    if(defined($a[2]) && $a[2] eq "client"){
        return "Usage: define <name> Snapcast client <server> <id>" unless (defined($a[3]) && defined($a[4]));
        return "Server $a[3] not defined" unless defined ($defs{$a[3]});
        $hash->{MODE} = "client";
        $hash->{SERVER} = $a[3];
        $hash->{ID} = $a[4];
        readingsSingleUpdate($hash,"state","defined",1);
        RemoveInternalTimer($hash);
        DevIo_CloseDev($hash);
        $attr{$name}{volumeStepSize}          = '5' unless (exists($attr{$name}{volumeStepSize}));
        $attr{$name}{volumeStepSizeSmall}     = '1' unless (exists($attr{$name}{volumeStepSizeSmall}));
        $attr{$name}{volumeStepSizeThreshold} = '5' unless (exists($attr{$name}{volumeStepSizeThreshold}));
        return Snapcast_Client_Register_Server($hash);
    }
    $hash->{ip} = (defined($a[2])) ? $a[2] : "localhost"; 
    $hash->{port} = (defined($a[3])) ? $a[3] : "1705"; 
    $hash->{MODE} = "server";
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    $hash->{DeviceName} = $hash->{ip}.":".$hash->{port};
    $attr{$name}{volumeStepSize} = '5' unless (exists($attr{$name}{volumeStepSize}));
    delete($hash->{"IDLIST"});
    Snapcast_Connect($hash);
    return undef;
}

sub Snapcast_Connect($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if (!$init_done){
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+5,"Snapcast_Connect", $hash, 0);
      return "init not done";
  }else{
      return DevIo_OpenDev($hash,0,"Snapcast_onConnect",);
  }
}

sub Snapcast_Attr($$){
  my ($cmd, $name, $attr, $value) = @_;
  my $hash = $defs{$name};
  if ($cmd eq "set"){
    if($attr eq "streamnext"){  
      return "streamnext needs to be either all or playing" unless $value=~/(all)|(playing)/;
    }
    if($attr eq "volumeStepSize"){
      return "volumeStepSize needs to be a number between 1 and 100" unless $value>0 && $value <=100;
    }
    if($attr eq "volumeStepSizeSmall"){
      return "volumeStepSizeSmall needs to be a number between 1 and 100" unless $value>0 && $value <=100;
    }
    if($attr eq "volumeStepSizeThreshold"){
      return "volumeStepSizeThreshold needs to be a number between 0 and 100" unless $value>=0 && $value <=100;
    }
  }
  return undef;
}

sub Snapcast_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    if($hash->{MODE} eq "client"){
      Snapcast_Client_Unregister_Server($hash);
    }
    return undef;
}


sub Snapcast_Get($@) {
  return "get is not supported by this module";
}

sub Snapcast_Set($@) {
  my ($hash, @param) = @_;
  return '"set Snapcast" needs at least one argument' if (int(@param) < 2);
  my $name = shift @param;
  my $opt = shift @param;
  my $value = join(" ", @param);
#  my $clientmod;
  my %sets = ($hash->{MODE} eq "client") ? %Snapcast_client_sets : %Snapcast_sets;
  if(!defined($sets{$opt})) {
    my @cList = keys %sets;
    return "Unknown argument $opt, choose one of " . join(" ", @cList);
  }
  if(@param < $sets{$opt}){
    return "$opt requires at least ".$sets{$opt}." arguments";
  }
  if($opt eq "update"){
    Snapcast_getStatus($hash);
    return undef;
  }
  if(defined($Snapcast_clientmethods{$opt})){
    my $client;
    if($hash->{MODE} eq "client"){
      my $clientmod=$hash;
      $client=$hash->{NAME};
      $hash=$hash->{SERVER};
      $hash=$defs{$hash};
      $client = $clientmod->{ID};
      return "Cannot find Server hash" unless defined ($hash);
    }else{
      $client = shift @param;
    }
    $value = join(" ", @param);
    return "client not found, use unique name, IP, or MAC as client identifier" unless defined($client);
    if($client eq "all"){
      for(my $i=1;$i<=ReadingsVal($name,"clients",0);$i++){
        my $client = $hash->{STATUS}->{clients}->{"$i"}->{host}->{mac};
        $client=~s/\://g;
        my $res = Snapcast_setClient($hash,$client,$opt,$value);
        readingsSingleUpdate($hash,"lastError",$res,1) if defined ($res);
      }
      return undef;
    }
    my $res = Snapcast_setClient($hash,$client,$opt,$value);
    readingsSingleUpdate($hash,"lastError",$res,1) if defined ($res);
    return undef;
  }
  return "$opt not implemented";
}

sub Snapcast_Read($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf;
  $buf = DevIo_SimpleRead($hash);
    return "" if ( !defined($buf) );
  $buf = $hash->{PARTIAL} . $buf;
  $buf =~ s/\r//g;
  my $lastchr = substr( $buf, -1, 1 );
  if ( $lastchr ne "\n") {
      $hash->{PARTIAL} = $buf;
      Log3( $hash, 5, "snap: partial command received" );
      return;
  }else {
      $hash->{PARTIAL} = "";
  }
  
  ###############################
  # Log3 $name,2, "Buffer: $buf";
  ###############################

  my @lines = split( /\n/, $buf );
  foreach my $line (@lines) {
    # Hier die Results parsen
    my $decoded_json;
    eval {
      $decoded_json = decode_json($line);
      1;
    } or do {
    # Decode JSON died, probably because of incorrect JSON from Snapcast. 
      Log3 $name,2, "Invalid Response from Snapcast,ignoring result: $line";
      readingsSingleUpdate($hash,"lastError","Invalid JSON: $buf",1); 
      return undef;
    };
    my $update=$decoded_json;
    if(defined ($hash->{"IDLIST"}->{$update->{id}})){
      my $id=$update->{id};
      #Log3 $name,2, "id: $id ";
      if($hash->{"IDLIST"}->{$id}->{method} eq 'Server.GetStatus'){
        delete $hash->{"IDLIST"}->{$id};
        return Snapcast_parseStatus($hash,$update);
      }
      if($hash->{"IDLIST"}->{$id}->{method} eq 'Server.DeleteClient'){
        delete $hash->{"IDLIST"}->{$id};
        return undef;
      }
      while ( my ($key, $value) = each %Snapcast_clientmethods){ 
        if(($value eq $hash->{"IDLIST"}->{$id}->{method}) && $key ne "mute"){ #exclude mute here because muting is now integrated in SetVolume
          my $client = $hash->{"IDLIST"}->{$id}->{params}->{id};

          $client=~s/\://g;
          Log3 $name,2, "client: $client ";
          Log3 $name,2, "key: $key ";
          Log3 $name,2, "value: $value ";
          if($key eq "volume"){
            my $temp_percent = $update->{result}->{volume}->{percent};
            #Log3 $name,2, "percent: $temp_percent ";
            readingsBeginUpdate($hash); 
            readingsBulkUpdateIfChanged($hash,"clients_".$client."_muted",$update->{result}->{volume}->{muted} );
            readingsBulkUpdateIfChanged($hash,"clients_".$client."_volume",$update->{result}->{volume}->{percent} );
            readingsEndUpdate($hash,1);
            my $clientmodule = $hash->{$client};
            my $clienthash=$defs{$clientmodule};
            my $maxvol = Snapcast_getVolumeConstraint($clienthash);
            if (defined $clientmodule) {
              readingsBeginUpdate($clienthash); 
              readingsBulkUpdateIfChanged($clienthash,"muted",$update->{result}->{volume}->{muted} );
              readingsBulkUpdateIfChanged($clienthash,"volume",$update->{result}->{volume}->{percent} );
              readingsEndUpdate($clienthash,1);
            }
          }
          elsif($key eq "stream"){
            #Log3 $name,2, "key: $key ";
            my $group = $hash->{"IDLIST"}->{$id}->{params}->{id};
            #Log3 $name,2, "group: $group ";
            for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
              $client = $hash->{STATUS}->{clients}->{"$i"}->{id};
              my $client_group = ReadingsVal($hash->{NAME},"clients_".$client."_group","");
              #Log3 $name,2, "client_group: $client_group ";
              my $clientmodule = $hash->{$client};
              my $clienthash=$defs{$clientmodule};
              if ($group eq $client_group) {          
                readingsBeginUpdate($hash); 
                readingsBulkUpdateIfChanged($hash,"clients_".$client."_stream_id",$update->{result}->{stream_id} );
                readingsEndUpdate($hash,1);
                if (defined $clientmodule) {
                  readingsBeginUpdate($clienthash); 
                  readingsBulkUpdateIfChanged($clienthash,"stream_id",$update->{result}->{stream_id} );
                  readingsEndUpdate($clienthash,1);
                }
              }
            }
          }
          else{
            readingsBeginUpdate($hash); 
            readingsBulkUpdateIfChanged($hash,"clients_".$client."_".$key,$update->{result});
            readingsEndUpdate($hash,1);
            my $clientmodule = $hash->{$client};
            my $clienthash=$defs{$clientmodule};
            return undef unless defined ($clienthash);
            readingsBeginUpdate($clienthash);
            readingsBulkUpdateIfChanged($clienthash,$key,$update->{result} );
            readingsEndUpdate($clienthash,1);
          }
        }
      }
      delete $hash->{"IDLIST"}->{$id};
      return undef;
    }
    elsif($update->{method}=~/Client\.OnDelete/){
      my $s=$update->{params}->{data};
      fhem "deletereading $name clients.*";
      Snapcast_getStatus($hash);
      return undef;
    }
    elsif($update->{method}=~/Client\./){
      my $c=$update->{params}->{data};
      Snapcast_updateClient($hash,$c,0);
      return undef;
    }
    elsif($update->{method}=~/Stream\./){
      my $s=$update->{params}->{data};
      Snapcast_updateStream($hash,$s,0);
      return undef;
    }
    elsif($update->{method}=~/Group\./){
      my $s=$update->{params}->{data};
      Snapcast_updateStream($hash,$s,0);
      return undef;
    }
    Log3 $name,2,"unknown JSON, please ontact module maintainer: $buf";
    readingsSingleUpdate($hash,"lastError","unknown JSON, please ontact module maintainer: $buf",1);
    return "unknown JSON received"
  }
}


sub Snapcast_Ready($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if (AttrVal($hash->{NAME}, 'disable', 0)) {
    return;
  }
  if ( ReadingsVal( $name, "state", "disconnected" ) eq "disconnected" ) {
      fhem "deletereading ".$name." streams.*";
      fhem "deletereading ".$name." clients.*";
        DevIo_OpenDev($hash, 1,"Snapcast_onConnect");
        return;
    }
  return undef;
}

sub Snapcast_onConnect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
  $hash->{CONNECTS}++;
  $hash->{helper}{PARTIAL} = "";
  Snapcast_getStatus($hash);
  return undef;
 }

sub Snapcast_updateClient($$$){
  my ($hash,$c,$cnumber) = @_;
  my $name = $hash->{NAME};
  if($cnumber==0){
    $cnumber++;
    while(defined($hash->{STATUS}->{clients}->{"$cnumber"}) && $c->{host}->{mac} ne $hash->{STATUS}->{clients}->{"$cnumber"}->{host}->{mac}){$cnumber++}
    if (not defined ($hash->{STATUS}->{clients}->{"$cnumber"})) { 
      Snapcast_getStatus($hash);
      return undef;
    }
  }
  $hash->{STATUS}->{clients}->{"$cnumber"}=$c;
  my $id=$c->{id}? $c->{id} : $c->{host}->{mac};    # protocol version 2 has no id, but just the MAC, newer versions will have an ID. 
  my $orig_id = $id;
  $id =~ s/://g;
  $hash->{STATUS}->{clients}->{"$cnumber"}->{id}=$id;
  $hash->{STATUS}->{clients}->{"$cnumber"}->{origid}=$orig_id;

  my $clientmodule = $hash->{$id};
  my $clienthash=$defs{$clientmodule};
 
  readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_online",$c->{connected} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_latency",$c->{config}->{latency} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_stream_id",$c->{config}->{stream_id} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_volume",$c->{config}->{volume}->{percent} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_ip",$c->{host}->{ip} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_mac",$c->{host}->{mac}); 
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_id",$id); 
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_origid",$orig_id); 
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_nr",$cnumber); 
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_group",$c->{config}->{group_id}); 
  readingsEndUpdate($hash,1);

  return undef unless defined ($clienthash);

  readingsBeginUpdate($clienthash);
    readingsBulkUpdateIfChanged($clienthash,"online",$c->{connected} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($clienthash,"name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
    readingsBulkUpdateIfChanged($clienthash,"latency",$c->{config}->{latency} );
    readingsBulkUpdateIfChanged($clienthash,"stream_id",$c->{config}->{stream_id} );
    readingsBulkUpdateIfChanged($clienthash,"volume",$c->{config}->{volume}->{percent} );
    readingsBulkUpdateIfChanged($clienthash,"muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($clienthash,"ip",$c->{host}->{ip} );
    readingsBulkUpdateIfChanged($clienthash,"mac",$c->{host}->{mac}); 
    readingsBulkUpdateIfChanged($clienthash,"id",$id); 
    readingsBulkUpdateIfChanged($clienthash,"origid",$orig_id); 
    readingsBulkUpdateIfChanged($clienthash,"group",$c->{config}->{group_id}); 
  readingsEndUpdate($clienthash,1);
  my $maxvol = Snapcast_getVolumeConstraint($clienthash);
  if($c->{config}->{volume}->{percent} > $maxvol){
    Snapcast_setClient($hash,$clienthash->{ID},"volume",$maxvol);
  }
  return undef;
}

sub Snapcast_updateStream($$$){
  my ($hash,$s,$snumber) = @_;
  my $name = $hash->{NAME};
  if($snumber==0){
    $snumber++;
    while(defined($hash->{STATUS}->{streams}->{"$snumber"}) && $s->{id} ne $hash->{STATUS}->{streams}->{"$snumber"}->{id}){$snumber++}
    if (not defined ($hash->{STATUS}->{streams}->{"$snumber"})){ return undef;}
  }
  $hash->{STATUS}->{streams}->{"$snumber"}=$s;
  readingsBeginUpdate($hash); 
  readingsBulkUpdateIfChanged($hash,"streams_".$snumber."_id",$s->{id} );
  readingsBulkUpdateIfChanged($hash,"streams_".$snumber."_status",$s->{status} );
  readingsEndUpdate($hash,1);
}

sub Snapcast_Client_Register_Server($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef unless $hash->{MODE} eq "client";
  my $server = $hash->{SERVER};
  if (not defined ($defs{$server})){
    InternalTimer(gettimeofday() + 30, "Snapcast_Client_Register_Server", $hash, 1); # if server does not exists maybe it got deleted, recheck every 30 seconds if it reappears
    return undef;
  }
  my $id=$hash->{ID};
  $server = $defs{$server}; # get the server hash
  return undef unless defined($server);
  $server->{$id} = $name;
  Snapcast_getStatus($server);
  return undef;
}

sub Snapcast_Client_Unregister_Server($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef unless $hash->{MODE} eq "client";
  my $server = $hash->{SERVER};
  return undef if (not defined ($defs{$server}));
  my $id=$hash->{ID};
  $server = $defs{$server}; # get the server hash
  return undef unless defined($server);
  readingsSingleUpdate($server,"clients_".$id."_module",$name,1 );
  delete($server->{$id});
  return undef;
}

sub Snapcast_getStatus($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  return Snapcast_Do($hash,"Server.GetStatus",'');
}

sub Snapcast_parseStatus($$){
  my ($hash,$status) = @_;
  my $streams=$status->{result}->{server}->{streams};
  my $groups=$status->{result}->{server}->{groups};
  my $server=$status->{result}->{server}->{server};

  
  $hash->{STATUS}->{server}=$server;
  if(defined ($groups)){
    my @groups=@{$groups};
    my $gnumber=1;
    my $cnumber=1;
    foreach my $g(@groups){
      my $groupstream=$g->{stream_id};
      my $groupid = $g->{id};
      my $clients=$g->{clients};
      if(defined ($clients)){
        my @clients=@{$clients};
        foreach my $c(@clients){
          $c->{config}->{stream_id} = $groupstream; # insert "stream" field for every client
          $c->{config}->{group_id} = $groupid; # insert "group_id" field for every client
          Snapcast_updateClient($hash,$c,$cnumber);
          $cnumber++;
        }
        readingsBeginUpdate($hash); 
        readingsBulkUpdateIfChanged($hash,"clients",$cnumber-1 );
        readingsEndUpdate($hash,1);
      }
    }
  }
  if(defined ($streams)){
    my @streams=@{$streams} unless not defined ($streams);
    my $snumber=1;
    foreach my $s(@streams){
      Snapcast_updateStream($hash,$s,$snumber);
      $snumber++;
    }
    readingsBeginUpdate($hash); 
    readingsBulkUpdateIfChanged($hash,"streams",$snumber-1 );
    readingsEndUpdate($hash,1);
  }
    InternalTimer(gettimeofday() + 300, "Snapcast_getStatus", $hash, 1); # every 5 Minutes, get the full update, also to apply changed vol constraints. 
}

sub Snapcast_setClient($$$$){
  my ($hash,$id,$param,$value) = @_;
  my $name = $hash->{NAME};
  my $method;
  my $paramset;
  my $cnumber = ReadingsVal($name,"clients_".$id."_nr","");
  return undef unless defined($cnumber);
  $paramset->{id} = Snapcast_getId($hash,$id);
  return undef unless defined($Snapcast_clientmethods{$param});
  $method=$Snapcast_clientmethods{$param};
  if($param eq "volumeConstraint"){
    my @values=split(/ /,$value);
    my $match;
    return "not enough parameters for volumeConstraint" unless @values>=2;
    if(@values%2){ # there is a match argument given because number is uneven
      $match=pop(@values);
    } else {
      $match="_global_";
    }
    for(my $i=0;$i<@values;$i+=2){
      return "wrong timeformat 00:00 - 24:00 for time/volume pair" unless $values[$i]=~/^(([0-1]?[0-9]|2[0-3]):[0-5][0-9])|24:00$/;
      return "wrong volumeformat 0 - 100 for time/volume pair" unless $values[$i+1]=~/^(0?[0-9]?[0-9]|100)$/;
    }
    return undef;
  }
  if($param eq "stream"){
    $paramset->{id} = ReadingsVal($name,"clients_".$id."_group",""); # for setting stream we now use group id instead of client id in snapcast 0.11 JSON format
    $param="stream_id";
    if($value eq "next"){ # just switch to the next stream, if last stream, jump to first one. This way streams can be cycled with a button press
      my $totalstreams=ReadingsVal($name,"streams","");
      my $currentstream = ReadingsVal($name,"clients_".$id."_stream_id","");
      $currentstream = Snapcast_getStreamNumber($hash,$currentstream);
      my $newstream = $currentstream+1;
      $newstream=1 unless $newstream <= $totalstreams;
      $value=ReadingsVal($name,"streams_".$newstream."_id","");
    }
  }

  if($param eq "volume"){
    my $currentVol = ReadingsVal($name,"clients_".$id."_volume","");
    my $muteState = ReadingsVal($name,"clients_".$id."_muted","");
    return undef unless defined($currentVol);

    # check if volume was given as increment or decrement, then find out current volume and calculate new volume
    if($value=~/^([\+\-])(\d{1,2})$/){
      my $direction = $1;
      my $amount = $2;
      $value = eval($currentVol. $direction. $amount);
      $value = 100 if ($value >= 100);
      $value = 0 if ($value <0);
    }
    # if volume is given with up or down argument, then increase or decrease according to volumeStepSize
    if($value=~/^(up|down)$/){
      my $step = AttrVal($name,"volumeStepSizeThreshold",0) > $currentVol ? AttrVal($name,"volumeStepSizeSmall",3) : AttrVal($name,"volumeStepSize",7);
      if ($value eq "up"){$value = $currentVol + $step;}else{$value = $currentVol - $step;}
      $value = 100 if ($value >= 100);
      $value = 0 if ($value <0);
      $muteState = "false"  if $value > 0 && ($muteState eq "true" || $muteState == 1);
    }
    my $volumeobject->{muted} = $muteState;
    $volumeobject->{percent} = $value+0;
    $value = $volumeobject;
  }

  if($param eq "mute" ){
    my $currentVol = ReadingsVal($name,"clients_".$id."_volume","");
    my $volumeobject->{muted} = $value;
    $volumeobject->{percent} = $currentVol+0;
    $value = $volumeobject;
 
    if(not (defined($value->{muted})) || $value->{muted} eq ''){
      my $muteState = ReadingsVal($name,"clients_".$id."_muted","");
      my $currentVol = ReadingsVal($name,"clients_".$id."_volume","");
      $value = $muteState eq "true" || $muteState == 1 ? "false" : "true";
      my $volumeobject->{muted} = $value;
      $volumeobject->{percent} = $currentVol+0;
      $value = $volumeobject;
    }
    $param = "volume"; # change param to "volume" to match new format
  }

  if(looks_like_number($value)){
    $paramset->{"$param"} = $value+0;
  }else{
    $paramset->{"$param"} = $value
  }
   Snapcast_Do($hash,$method,$paramset);
  return undef;
}

sub Snapcast_Do($$$){
  my ($hash,$method,$param) = @_;
  my $name = $hash->{NAME};
  $param = '' unless defined($param);
  return DevIo_SimpleWrite($hash,Snapcast_Encode($hash,$method,$param),2);
} 

sub Snapcast_Encode($$$){
  my ($hash,$method,$param) = @_;
  my $name = $hash->{NAME};
  if(defined($hash->{helper}{REQID})){$hash->{helper}{REQID}++;}else{$hash->{helper}{REQID}=1;}
  $hash->{helper}{REQID} =1 if $hash->{helper}{REQID}>16383; # not sure if this is needed but we better dont let this grow forever
  my $request;
  my $json;
  $request->{jsonrpc}="2.0";
  $request->{method}=$method;
  $request->{id}=$hash->{helper}{REQID};
  $request->{params} = $param unless $param eq '';
  $hash->{"IDLIST"}->{$request->{id}} = $request;
  $request->{id}=$request->{id}+0;
  $json=encode_json($request)."\r\n";
  $json =~s/\"true\"/true/;     # Snapcast needs bool values without "" but encode_json does not do this
  $json =~s/\"false\"/false/;
  return $json;
}

sub Snapcast_getStreamNumber($$){
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};
  for(my $i=1;$i<=ReadingsVal($name,"streams",1);$i++){
    if ($id eq ReadingsVal($name,"streams_".$i."_id","")){
      return $i;
    }
  }
  return undef;
}

sub Snapcast_getId($$){
  my ($hash,$client) = @_;
  my $name = $hash->{NAME};
  if($client=~/^([0-9a-f]{12}(\#*\d*|$))$/i){ # client is  ID
    for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
      if ($client eq $hash->{STATUS}->{clients}->{"$i"}->{id}) {
        return $hash->{STATUS}->{clients}->{"$i"}->{origid};
      }
    }
  }
  return "unknown client";
}

sub Snapcast_getVolumeConstraint{
  my ($hash,$client) = @_;
  my $name = $hash->{NAME};
  my $value = 100;
  return $value if($hash->{MODE} ne "client");
  my @constraints=split(",",AttrVal($name,"constraints",""));
  return $value if @constraints<1;
  my $phase = ReadingsVal(AttrVal($name,"constraintDummy","undefined"),"state","standard");

  foreach my $c (@constraints){
    my ($cname,$list)= split(/\|/,$c);
    Log3 $name,3,"SNAP cname: $cname, list: $list";
    if($cname eq $phase){
      my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time+86400);
      my $tomorrow=sprintf("%04d",1900+$year)."-".sprintf("%02d",$mon+1)."-".sprintf("%02d",$mday)." ";
      $list =~ s/^\s+//; # get rid of whitespaces
      $list =~ s/\s+$//; 
      my @listelements=split(" ", $list);
      my $mindiff=time_str2num($tomorrow."23:59:00"); # eine Tageslänge
      for(my $i=0;$i<@listelements/2;$i++){
          my $diff=abstime2rel($listelements[$i*2].":00"); # wie lange sind wir weg von der SChaltzeit?
          if(time_str2num($tomorrow.$diff)<$mindiff){$mindiff=time_str2num($tomorrow.$diff);$value=$listelements[1+($i*2)];} # wir suchen die kleinste relative Zeit
      }
    }
   }
  readingsSingleUpdate($hash,"maxvol",$value,1);
  return $value; # der aktuelle Auto-Wert wird zurückgegeben
}

sub Snapcast_isPmInstalled($$)
{
  my ($hash,$pm) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  if (not eval "use $pm;1")
  {
    Log3 $name, 1, "$type $name: perl modul missing: $pm. Install it, please.";
    return "failed: $pm";
  }
  
  return undef;
}
1;

=pod
=item summary    control and monitor Snapcast Server
=begin html

<a name="Snapcast"></a>
<h3>Snapcast</h3>
<ul>
    <i>Snapcast</i> is a module to control a Snapcast Server. Snapcast is a little project to achieve multiroom audio and is a leightweight alternative to such solutions using Pulseaudio.
    Find all information about Snapcast, how to install and configure on the <a href="https://github.com/badaix/snapcast">Snapcast GIT</a>. To use this module, the minimum is to define a snapcast server module
    which defines the connection to the actual snapcast server. See the define section for how to do this. On top of that, it is possible to define virtual client modules, so that each snapcast client that is connected to 
    the Snapcast Server is represented by its own FHEM module. The purpose of that is to provide an interface to the user that enables to integrate Snapcast Clients into existing visualization solutions and to use 
    other FHEM capabilities around it, e.g. Notifies, etc. The server module includes all readings of all snapcast clients, and it allows to control all functions of all snapcast clients. 
    Each virtual client module just gets the reading for the specific client. The client modules is encouraged and also makes it possible to do per-client Attribute settings, e.g. volume step size and volume constraints. 
    <br><br>
    <a name="Snapcastdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> Snapcast [&lt;ip&gt; &lt;port&gt;]</code>
        <br><br>
        Example: <code>define MySnap Snapcast 127.0.0.1 1705</code>
        <br><br>
        This way a snapcast server module is defined. IP defaults to localhost, and Port to 1705, in case you run Snapcast in the default configuration on the same server as FHEM, you dont need to give those parameters.
        <br><br><br>
        <code>define <name> Snapcast client &lt;server&gt; &lt;clientid&gt;</code>
         <br><br>
        Example: <code>define MySnapClient Snapcast client MySnap aabbccddeeff</code>
        <br><br>
        This way a snapcast client module is defined. The keyword client does this. The next argument links the client module to the associated server module. The final argument is the client ID. In Snapcast each client gets a unique ID,
         which is normally made out of the MAC address. Once the server module is initialized it will have all the client IDs in the readings, so you want to use those for the definition of the client modules
    </ul>
    <br>
    <a name="Snapcastset"></a>
    <b>Set</b><br>
    <ul>
        For a Server module: <code>set &lt;name&gt; &lt;function&gt; &lt;client&gt; &lt;value&gt;</code>
        <br><br>
        For a Client module: <code>set &lt;name&gt; &lt;function&gt; &lt;value&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>update</i><br>
                  Perform a full update of the Snapcast Status including streams and servers. Only needed if something is not working. Server module only</li>
              <li><i>volume</i><br>
                  Set the volume of a client. For this and all the following 4 options, give client as second parameter (only for the server module), either as name, IP , or MAC and the desired value as third parameter. 
                  Client can be given as "all", in that case all clients are changed at once (only for server module)<br>
                  Volume can be given in 3 ways: Range betwee 0 and 100 to set volume directly. Increment or Decrement given between -100 and +100. Keywords <em>up</em> and <em>down</em> to increase or decrease with a predifined step size. 
                  The step size can be defined in the attribute <em>volumeStepSize</em><br>
                  The step size can be defined smaller for the lower volume range, so that finetuning is possible in this area.
                  See the description of the attributes <em>volumeStepSizeSmall</em> and <em>volumeStepThreshold</em>
                  Setting a volume bigger than 0 also unmutes the client, if muted.</li>
              <li><i>mute</i><br>
                  Mute or unmute by giving "true" or "false" as value. If no argument given,  toggle between muted and unmuted.</li>
              <li><i>latency</i><br>
                  Change the Latency Setting of the client</li>
              <li><i>name</i><br>
                  Change the Name of the client</li>
              <li><i>stream</i><br>
                  Change the stream that the client is listening to. Snapcast uses one or more streams which can be unterstood as virtual audio channels. Each client/room can subscribe to one of them. 
                  By using next as value, you can cycle through the avaialble streams</li>
        </ul>
</ul>
 <br><br>
  <a name="Snapcastattr"></a>
  <b>Attributes</b>
  <ul>
    All attributes can be set to the master module and the client modules. Using them for client modules enable the setting of different attribute values per client. 
    <li>streamnext<br>
    Can be set to <i>all</i> or <i>playing</i>. If set to <i>all</i>, the <i>next</i> function cycles through all streams, if set to <i>playing</i>, the next function cycles only through streams in the playing state.
    </li>
    <li>volumeStepSize<br>
      Default: 5. Set this to define, how far the volume is changed when using up/down volume commands. 
    </li>
    <li>volumeStepThreshold<br>
      Default: 7. When the volume is below this threshold, then the volumeStepSizeSmall setting is used for volume steps, rather than the normal volumeStepSize. 
    </li>
    <li>volumeStepSizeSmall<br>
      Default: 1. This typically smaller step size is used when using "volume up" or "volume down" and the current volume is smaller than the threshold. 
    </li>
        <li>constraintDummy<br>
    Links the Snapcast module to a dummy. The value of the dummy is then used as a selector for different sets of volumeConstraints. See the description of the volumeConstraint command. 
    </li>
    <li>constraints<br>Defines a set of volume Constraints for each client and, optionally, based on the value of the dummy as defined with constraintDummy. This way there can be different volume profiles for e.g. weekdays or weekends. volumeConstraints mean, that the maximum volume of snapcast clients can be limited or even set to 0 during certain times, e.g. at night for the childrens room, etc.
    the constraint argument is given in the folling format: <constraintSet>|hh:mm vol hh:mm vol ... [<constraintSet2>|hh:mm vol ... etc. The chain off <hh:mm> <volume> pairs defines a volume profile for 24 hours. It is equivalent to the temeratore setting of the homematic thermostates supported by FHEM.  
    <br>Example: standard|08:00 0 18:00 100 22:00 30 24:00 0,weekend|10:00 0 20:00 100 24:00 30</li>
    <br>In this example, there are two profiles defined. If the value of the associated dummy is "standard", then the standard profile is used. It mutes the client between midnight and 8 am, then allows full volume until 18:00, then limites the volume to 30 until 22:00 and then mutes the client for the rest of the day. The snapcast module does not increase the volume when a limited time is over, it only allows for increasing it manually again. 
  </ul>
</ul>

=end html

=currentstream
