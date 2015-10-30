##############################################################################
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or rename
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
#
#     $Id$
#
##############################################################################

package main;

use strict;
use warnings;
use Data::Dumper;
use utf8;
use Encode qw( encode_utf8 );
use HttpUtils;
use JSON;

#use diagnostics;

sub Pushbullet_Initialize($) {
	my ($hash) = @_;

	$hash->{GetFn}     = "Pushbullet_Get";
	$hash->{SetFn}     = "Pushbullet_Set";
	$hash->{AttrFn}    = "Pushbullet_Attr";
	$hash->{DefFn}     = "Pushbullet_Define";
	$hash->{UndefFn}   = "Pushbullet_Undefine";
	#$hash->{NotifyFn  = "Pushbullet_Notify";
	$hash->{AttrList}  = "disable:0,1".
	                     " defaultTitle".
	                     " defaultDevice".
                       " ".$readingFnAttributes;
}

sub Pushbullet_Define($$) {
	my ( $hash, $def ) = @_;
	
	my @a = split( "[ \t][ \t]*", $def );
	return "Usage: define <name> Pushbullet <accessToken>"
		if ( @a != 3 );

	$hash->{NAME}         = $a[0];
	$hash->{helper}{key}  = $a[2];
	my $name              = $hash->{NAME};
	
	# accessToken Check
	my $url           = 'https://' . $hash->{helper}{key} . ':%20@api.pushbullet.com/v2/users/me';
  my $decoded       = Pushbullet_httpCall($hash,$url,undef,"GET");
  return $decoded->{error}{message} if( $decoded->{error} );
 
	Pushbullet_clear($hash);
 
  return undef;
}

sub Pushbullet_Undefine($) {		
	return undef;
}

sub Pushbullet_Set($@) {	
  my ($hash, @a)    = @_;
  my $name          = $hash->{NAME};
  
  # Disabled
  return undef if( IsDisabled($name) );
  
  # Zu wenig argumente
  return "no set argument specified" if(int(@a) < 2);
  
  # Variablen
  my $cmd  = "";
  $cmd     = $a[1] if( $a[1] );
  my @setValues;
  my $i    = 0;
  my $list = undef;
  my %url;
  my $urlNew;
  my ($err,$data);
  my $jsonHash;    
  my $json;
  my $value = "";
  
  # Set Liste
  $list = "clear:noArg contactAdd deviceDelete deviceRename message link list";
  
  # Eingaben einlesen
  $i = 0;
  foreach my $set ( @a ){
    $i++;
    next if( $i <= 2 );
     
    $value .= Pushbullet_trim($set) . " ";
  }
  
  # setValues einlesen
  my @split = split( /\s*\|\s*/, $value );
  foreach my $sv ( @split ){
    $sv = Pushbullet_trim($sv);
    push(@setValues, $sv);
    Log3 $hash, 4, $sv;
  }
  
  %url = ( "push"       => 'https://' . $hash->{helper}{key} . ': @api.pushbullet.com/v2/pushes',
           "device"     => 'https://' . $hash->{helper}{key} . ': @api.pushbullet.com/v2/devices/',
           "contact"    => 'https://' . $hash->{helper}{key} . ': @api.pushbullet.com/v2/contacts/', 
           "contactAdd" => 'https://' . $hash->{helper}{key} . ': @api.pushbullet.com/v2/contacts' );
  
  # clear
  if( $cmd eq "clear" ){
    Pushbullet_clear($hash);
  }
  
  # Message senden
  elsif( $cmd eq "message" ){
    return 'Message needet. Correct sytax: set ' . $name . ' message a message[|a title|deviceName]' if( @a < 3 );
    
    # Variablen
    my ($msg, $title, $deviceNick, $deviceIden, $deviceEmail) = "";
    my $decoded;
    
    # Argumente überprüfen und auswerten
    ($msg, $title, $deviceNick, $deviceIden, $deviceEmail) = Pushbullet_checkArgs($hash, $cmd, @setValues);
    
    # Push geht an Device
    $jsonHash       = { 'device_iden' => $deviceIden, 'type' => 'note', 'title' => $title, 'body' => $msg };
    
    # Push geht an Kontakt
    $jsonHash       = { 'email' => $deviceEmail, 'type' => 'note', 'title' => $title, 'body' => $msg } if( $deviceEmail );
    
    # Push senden
    $decoded        = Pushbullet_httpCall($hash,$url{push},$jsonHash,"POST");
    return $decoded->{error}{message} if( $decoded->{error} );
    
    # Last Push Date
    my ($seconds) = gettimeofday();
    $hash->{LAST_PUSH} = FmtDateTime( $seconds );
  }
  
  # Link senden
  elsif( $cmd eq "link" ){
    return 'Message needet. Correct sytax: set ' . $name . ' link http://www.google.com [| Title | Device]' if( @a < 3 );
    
    # Variablen
    my ($link, $title, $deviceNick, $deviceIden, $deviceEmail) = "";
    my $decoded;
    
    # Argumente überprüfen und auswerten
    ($link, $title, $deviceNick, $deviceIden, $deviceEmail) = Pushbullet_checkArgs($hash, $cmd, @setValues);
    
    # Link check
    return "URL is not valid. Correct sytax: set " . $name . " link http://www.google.com [| Title | Device] " 
      if( $link !~ /^(http|https):\/\/.*/ && $link !~ /^skype:.*/ );
    
    # Push geht an Device
    $jsonHash       = {'type' => 'link', 'device_iden' => $deviceIden, 'title' => $title, 'url' => $link};
    
    # Push geht an Kontakt
    $jsonHash       = {'type' => 'link', 'email' => $deviceEmail, 'title' => $title, 'url' => $link} if( $deviceEmail );
    
    # Push senden
    $decoded        = Pushbullet_httpCall($hash,$url{push},$jsonHash,"POST");
    return $decoded->{error}{message} if( $decoded->{error} );
    
    # Last Push Date
    my ($seconds) = gettimeofday();
    $hash->{LAST_PUSH} = FmtDateTime( $seconds );
  }
  
  # Liste senden
  elsif( $cmd eq "list" ){
    return 'Message needet. Correct sytax: set ' . $name . ' list item1[, item2, item3, ... | Titel | Device]' if( @a < 2 );
    
    my @items       = split( m/,/, $setValues[0] );
    
    for( my $i=0; $i<=int(@items); $i++){
      next if(Pushbullet_trim($items[$i]) eq "");
      Log3 $hash, 4, $name . ": $i:" . Pushbullet_trim($items[$i]);
      $items[$i] = Pushbullet_trim($items[$i]) 
    }
        
    # Variablen
    my ($title, $deviceNick, $deviceIden, $deviceEmail) = "";
    my $decoded;
    
    # Argumente überprüfen und auswerten
    (undef, $title, $deviceNick, $deviceIden, $deviceEmail) = Pushbullet_checkArgs($hash, $cmd, @setValues);
    
    # Push geht an Device
    $jsonHash       = {'type' => 'list', 'device_iden' => $deviceIden, 'title' => $title, 'items' => [@items]};
    
    # Push geht an Kontakt
    $jsonHash       = {'type' => 'list', 'email' => $deviceEmail, 'title' => $title, 'items' => [@items]} if( $deviceEmail );
    
    # Push senden
    $decoded        = Pushbullet_httpCall($hash,$url{push},$jsonHash,"POST");
    return $decoded->{error}{message} if( $decoded->{error} );
    
    # Last Push Date
    my ($seconds) = gettimeofday();
    $hash->{LAST_PUSH} = FmtDateTime( $seconds );
  }
  
  # Device umbenennen
  elsif( $cmd eq "deviceRename" ){
    return '2 parameter needet. Correct sytax: set ' . $name . ' renameDeviceName oldName | newName' if( @setValues < 2  );
    
    my ($deviceNick, $deviceNickNew, $deviceIden, $deviceEmail) = "";
    my $decoded;
    
    # Argumente überprüfen und auswerten
    ($deviceNick, $deviceNickNew, undef, $deviceIden, $deviceEmail) = Pushbullet_checkArgs($hash, $cmd, @setValues);
    
    # Device = Device
    $jsonHash  = {'nickname' => $deviceNickNew};
    $urlNew    = $url{device} . $deviceIden;
    
    # Device = Kontakt
    $jsonHash  = {'name' => $deviceNickNew}  if( $deviceEmail );
    $urlNew    = $url{contact} . $deviceIden if( $deviceEmail );
    
    # Device umbenennen
    $decoded        = Pushbullet_httpCall($hash,$urlNew,$jsonHash,"POST");
    return $decoded->{error}{message} if( $decoded->{error});
    
    Pushbullet_clear($hash);
    Pushbullet_getDevices($hash);
    Pushbullet_getContacts($hash);
  }
  
  # Device löschen
  elsif( $cmd eq "deviceDelete" ){ 
    $value = $setValues[0];
    return '1 parameter needet. Correct sytax: set ' . $name . ' deleteDevice deviceName'                      if( !$value );
    
    my ($deviceNick, $deviceIden, $deviceEmail) = "";
    my $decoded;
    
    # Argumente überprüfen und auswerten
    ($deviceNick, undef, undef, $deviceIden, $deviceEmail) = Pushbullet_checkArgs($hash, $cmd, $value);
    
    # Device = Device      
    $urlNew    = $url{device} . $deviceIden;
    
    # Device = Kontakt
    $urlNew    = $url{contact} . $deviceIden if( $deviceEmail );
    
    # Device löschen
    $decoded   = Pushbullet_httpCall($hash,$urlNew,undef,"DELETE");
    return $decoded->{error}{message} if( $decoded->{error} );
    
    Pushbullet_clear($hash);
    Pushbullet_getDevices($hash);
    Pushbullet_getContacts($hash);
  }
  
  # Kontakt hinzufügen
  elsif( $cmd eq "contactAdd" ){                                                        
    return '2 parameter needet. Correct sytax: set ' . $name . ' contactAdd name | email' if( @a < 3 || @setValues == 1 || @setValues > 2 );
    
    my ($contactName,$contactEmail)  = "";
    my $decoded;
    
    # Argumente überprüfen und auswerten
    ($contactName, $contactEmail, undef, undef, undef) = Pushbullet_checkArgs($hash, $cmd, @setValues);
    
    # Log
    Log3 $hash, 4, $name . ": add contact - contact:" . @setValues . " name:" . $contactName . " email:" . $contactEmail;
    
    # Email validation
    return "<" .$contactEmail . "> is no valid email." if( $contactEmail !~ /.+\@.+\..+/ );
    
    $jsonHash       = {'name', => $contactName, 'email' => $contactEmail};
    
    # Kontakt hinzufügen
    $decoded        = Pushbullet_httpCall($hash,$url{contactAdd},$jsonHash,"POST");
    return $decoded->{error}{message} if( $decoded->{error} );
    
    Pushbullet_clear($hash);
    Pushbullet_getDevices($hash);
    Pushbullet_getContacts($hash); 
  }
  else {
    return "Unknown argument $cmd, choose one of $list";
  }
  return;
}

sub Pushbullet_Get($@) {
  my ($hash, @a)    = @_;
  my $name          = $hash->{NAME}; 
  
  # Disabled
  return undef if( IsDisabled($name) );

  return "Need a parameter for get" if(@a < 2);
  
  my $cmd           = $a[1];
  my $value         = $a[2];
  my $list          = undef;
  
  $list            .= " devices:noArg";
  
  if( $cmd eq "devices" ){
    Pushbullet_clear($hash);
    Pushbullet_getDevices($hash);
    Pushbullet_getContacts($hash); 
  }
  else{
    return "Unknown argument $cmd, choose one of $list";
  }
}

sub Pushbullet_Attr(@) {	
	return undef;
}

sub Pushbullet_getDevices($){
  my ($hash)        = @_;
  my $name          = $hash->{NAME};
  
  my $url;
  my $decoded;
  my $i             = 0;
  
  $url              = 'https://' . $hash->{helper}{key} . ':%20@api.pushbullet.com/v2/devices';
  $decoded          = Pushbullet_httpCall($hash,$url,undef,"GET");
   
  return $decoded->{error}{message} if( $decoded->{error} );
  
  # Last Poll Date
  my ($seconds) = gettimeofday();
  $hash->{LAST_POLL} = FmtDateTime( $seconds );
    
  for my $d( @{ $decoded->{devices}} ){
    next if( !$d->{active} );
    
    if( $d->{nickname} =~ /'|"/ ){
      Log3 $hash, 3, "$name: Forbidden character. Please check your device name on pushbullet.com";
      next;
    }
      
      # Readings updaten
      readingsBeginUpdate($hash);
       readingsBulkUpdate($hash, $d->{iden} . "_name", $d->{nickname} );
      readingsEndUpdate($hash, 1);
      $i++;
  };
  
  Log3 $hash, 4, "$name: Es wurden $i Endgeraete neu eingelesen.";
  
  return;
}

sub Pushbullet_getContacts($){
  my ($hash)        = @_;
  my $name          = $hash->{NAME};
  
  my $url;
  my $decoded;
  my $i             = 0;
  
  $url              = 'https://' . $hash->{helper}{key} . ':%20@api.pushbullet.com/v2/contacts';
  $decoded          = Pushbullet_httpCall($hash,$url,undef,"GET");
  
  return $decoded->{error}{message} if( $decoded->{error} );
  
  for my $c( @{ $decoded->{contacts}} ){
    next if( !$c->{active} || !$c->{name} );
    
    if( $c->{name} =~ /'|"/ ){
      Log3 $hash, 3, "$name: Forbidden character. Please check your device name on pushbullet.com";
      next;
    }
      
      # Readings updaten
      readingsBeginUpdate($hash);
       readingsBulkUpdate($hash, $c->{iden} . "_name", $c->{name} );
       readingsBulkUpdate($hash, $c->{iden} . "_email", $c->{email} );
      readingsEndUpdate($hash, 1);
      
      $i++;
  };
  
  Log3 $hash, 4, "$name: Es wurden $i Kontakte neu eingelesen.";
  
  return;
}

sub Pushbullet_clear($){
  my ($hash)        = @_;
  my $name          = $hash->{NAME};
  
  delete $hash->{READINGS};
  readingsSingleUpdate($hash, "state", "Initialized", 1);
  
  return undef;
}

sub Pushbullet_getDeviceIden($$){
  my ($hash, $deviceNick) = @_;
  my $name = $hash->{NAME};
  
  my $deviceIden    = undef; 
  my @deviceIdenSplit;
  my ($nkey, $nvalue, $rkey, $rvalue); 
  
  $deviceNick = Pushbullet_trim($deviceNick);   
  
  return if( !$hash->{READINGS} );
  
  while( ($nkey, $nvalue) = each%{$hash->{READINGS}} ){
    while( ($rkey, $rvalue) = each%{$hash->{READINGS}{$nkey}} ){
       Log3 $hash, 5, $name . ": nkey:" . $nkey . " nvalue:" . $nvalue . " rkey:" . $rkey . " rvalue:" . $rvalue if( $rvalue eq $deviceNick );
       $deviceIden = $nkey if( $rvalue eq $deviceNick );
    } 
  }
  
  if( !$deviceIden ){
    Log3 $hash, 3, "$name: Can not read deviceIden from $deviceNick.";
    return;
  }
    
  @deviceIdenSplit = split( /_name/, $deviceIden );
  $deviceIden      = $deviceIdenSplit[0];
  
  Log3 $hash, 5, $name . ": deviceIden:".$deviceIden; 
    
  return $deviceIden;
}

sub Pushbullet_httpCall($$$$){
  my ($hash,$url,$jsonHash,$method) = @_;
  my ($json,$err,$data,$decoded);
  my $name = $hash->{NAME};
  
  $json = JSON->new->latin1->encode($jsonHash) if( $jsonHash ); 
   
  ($err,$data)    = HttpUtils_BlockingGet({
    url           => $url,
    method        => $method,
    header        => "Content-Type: application/json",
    data          => $json
  });
  
  $json = "" if( !$json );
  $data = "" if( !$data );
  
  Log3 $hash, 4, "FHEM -> Pushbullet.com: " . $json; 
  Log3 $hash, 4, "Pushbullet.com -> FHEM: " . $data;
  
  Log3 $hash, 5, '$err: ' . $err;
  Log3 $hash, 5, '$method: ' . $method;
  
  Log3 $hash, 3, "Something gone wrong" if( $data =~ "<!DOCTYPE html>" );
  $err = 1 if( $data =~ "<!DOCTYPE html>" );
  
  $decoded  = decode_json($data) if( !$err ); 
   
  return($decoded);
}

sub Pushbullet_trim($)
{
	my $string = shift;
	$string    = "" if( !defined($string) );
		
	#$string    =~ s/Â//;
  $string    =~ s/^\\u00a0//g;
	
	# BUGFIX: Â Zeichen umwandeln. Tritt auf wenn Safari Formular automatisch ausfüllt
	#$string    =~ s/\s*\|\W/\s\|\s/;
	
	# Leerzeichen am Anfang und am Ende entfernen
	$string    =~ s/^\s+//;# if( $string =~ m/^\s+/ );
	$string    =~ s/\s+$//;# if( $string =~ m/\s+$/ );
	
	return $string;
}

sub Pushbullet_checkArgs($$@){
  my ($hash, $cmd, @args) = @_;
  my $name = $hash->{NAME};
  
  my $argsCount = int(@args);
  
  my ($msg, $title, $deviceNick, $defaultNick, $deviceIden, $deviceEmail) = "";
  
  # Nachricht (cmd = message)
  # Link      (cmd = link)
  # Liste     (cmd = list)
  # AlterNick (cmd = deviceRename)
  # Nick      (cmd = devicedDelete || contactAdd)
  
  # Titel     (cmd = message || link)
  # NeuerNick (cmd = deviceRename)
  # undef     (cmd = devicedDelete)
  # Email     (cmd = contactAdd)
  $args[1]        = "FHEM"                                 if( ( $cmd eq "message" || $cmd eq "link" || $cmd eq "list" ) && $argsCount == 1 );
  $args[1]        = AttrVal($name, "defaultTitle", undef)  if( ( $cmd eq "message" || $cmd eq "link" || $cmd eq "list" ) && $argsCount == 1 && AttrVal($name, "defaultTitle", undef) );
  
  # Default Nick (cmd = message || link)
  $defaultNick    = AttrVal($name, "defaultDevice", undef) if( ( $cmd eq "message" || $cmd eq "link" || $cmd eq "list" ) && $argsCount < 2 && AttrVal($name, "defaultDevice", undef) );
  
  # Device Nick
  $deviceNick     = $defaultNick          if( ( $cmd eq "message" || $cmd eq "link" || $cmd eq "list" ) && $argsCount < 2 && AttrVal($name, "defaultDevice", undef) );
  $deviceNick     = $args[2]              if( $argsCount > 2);
  $deviceNick     = $args[0]              if( $cmd eq "deviceRename" || $cmd eq "deviceDelete" );

  # Device Iden
  $deviceIden     = Pushbullet_getDeviceIden($hash,$deviceNick) if( defined($deviceNick) );
  $deviceIden     = "" if( !defined($deviceIden) );

  # Device Email
  $deviceEmail    = ReadingsVal($name, $deviceIden . "_email", undef) if( defined($deviceNick) );
  
  # Warnungen ausblenden
  $deviceNick     = "" if( !defined($deviceNick) );
  $deviceIden     = "" if( !defined($deviceIden) );
  $deviceEmail    = "" if( !defined($deviceEmail) );
  $args[1]        = "" if( !defined($args[1]) );
  
  # Log
  Log3 $hash, 4, $name . "_checkArgs: cmd:" . $cmd . " Args:" . $argsCount . " arg0:" . $args[0] . " arg1:" . $args[1] . " deviceNick:" . $deviceNick . " deviceIden:" . $deviceIden . " email:" . $deviceEmail;
  
  return($args[0], $args[1], $deviceNick, $deviceIden, $deviceEmail);
}
1;

=pod
=begin html

<a name="Pushbullet"></a>
<h3>Pushbullet</h3>
<ul>
  Pushbullet is a service to send instant push notifications to different devices. There are
  apps for iPhone, Android, Windows (Beta), Mac OS X and plugins for Chrome Firefox and Safari.<br>
  For further information about the service see <a target="_blank" href="https://pushbullet.com">pushbullet.com</a>.<br>
  <br>
  Discuss the module <a target="_blank" href="http://forum.fhem.de/index.php/topic,29796.0.html">here</a>.<br>  <br><br>
  <a name="Pushbullet_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushbullet &lt;accessToken&gt;</code><br>
    <br>

    Note:<br>
    <ul>
      <li>JSON has to be installed on the FHEM host.</li>
      <li>Register on pushbullet.com to get your accessToken.</li>
    </ul>
  </ul><br>

  <a name="Pushbullet_Set"></a>
    <b>Set</b>
    <ul>
      <li>clear<br>
        clear device readings</li>
      <li>contactAdd name | email<br>
        adds a contact. Spaces in name are allowed</li>
      <li>deviceDelete deviceName<br>
        deletes a device</li>
      <li>deviceRename deviceName | newDeviceName<br>
        renames a device</li>
      <li>link [| title | device]<br>
        sends a link with optional title and device. If no device is given, push goes to all your devices.</li>
      <li>list item1[, item2, item3, ... | title | device]<br>
      sends a list with one or more items, optional title and device. If no device is given, push goes to all your devices.</li>
      <li>message [| title | device]<br>
        sends a push notification with optional title and device. If no device is given, push goes to all your devices.</li>
      <br>
      Examples:<br>
      <ul>
        <code>set Pushbullet message This is a message.</code><br>
        sends a push notification with message "This is a message" without a title to all <b>your</b> devices.<br><br>
        <code>set Pushbullet message This is a message | A title</code><br>
        sends a push notification with message "This is a message" and title "A title" to all <b>your</b> devices.<br><br>
        <code>set Pushbullet message This is a message | A title | iPhone</code><br>
        sends a push notification with message "This is a message" and title "A title" to Device iPhone.<br><br>
        <code>set Pushbullet message This is a message | A title | Max Mustermann</code><br>
        sends a push notification with message "This is a message" and title "A title" to your contact Max Mustermann.<br>
      </ul>
      <br>
      Note:<br>
      Spaces before and after | are not needed.
    </ul><br>
    
   <a name="Pushbullet_Get"></a>
    <b>Get</b>
    <ul>
      <li>devices<br>
        reads your device list (devices + contacts) and set device readings</li>
    </ul><br>  

  <a name="Pushbullet_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>defaultDevice<br>
        default device for pushmessages</li>
      <li>defaultTitle<br>
        default title for pushmessages. If it is undefined the defaultTitle will be FHEM</li>
    </ul>
</ul>

=end html

=begin html_DE

<a name="Pushbullet"></a>
<h3>Pushbullet</h3>
<ul>
  Pushbullet ist ein Dienst, um Benachrichtigungen an unterschiedliche Endgeräte zu senden. Pushbullet
  bietet Apps für iPhone, Android, Windows (Beta) und Mac OS X sowie Plugins für Chrome, Firefox und Safari an.<br>
  Für weitere Informationen über den Dienst besuche <a target="_blank" href="https://pushbullet.com">pushbullet.com</a>.<br>
  <br>
  Diskutiere das Modul <a target="_blank" href="http://forum.fhem.de/index.php/topic,29796.0.html">hier</a>.<br>
  <br><br>
  <a name="Pushbullet_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Pushbullet &lt;accessToken&gt;</code><br>
    <br>

    Notiz:<br>
    JSON muss auf dem FHEM Host installiert sein.<br><br>
    Registriere dich auf pushbullet.com um deine accessToken zu bekommen.<br>
  </ul><br>

  <a name="Pushbullet_Set"></a>
    <b>Set</b>
    <ul>
      <li>clear<br>
        Löscht alle Device Readings</li>
      <li>contactAdd name | email<br>
        Fügt einen neuen Kontakt hinzu. Leerzeichen im Namen sind erlaubt.</li>
      <li>deviceDelete deviceName<br>
        Löscht das Device.</li>
      <li>deviceRename deviceName | neuerDeviceName<br>
        Benennt das Device um.</li>
      <li>link [| Titel | Device]<br>
        Sendet einen Link mit optionalen Titel und Device. Wenn kein Device angegeben ist, geht der Push an alle deine Devices.</li>
      <li>list Item1[, Item2, Item3, ... | Titel | Device]<br>
        Sendet eine Liste mit einem oder mehreren Items, optionalen Titel und Device. Wenn kein Device angegeben ist, geht der Push an alle deine Devices.</li>
      <li>message [| Titel | Device]<br>
        Sendet eine Nachricht mit optionalen Titel und Device. Wenn kein Device angegeben ist, geht der Push an alle deine Devices.</li>
      <br>
      Beispiele:<br>
      <ul>
        <code>set Pushbullet message Das ist eine Nachricht</code><br>
        Sendet eine Push Benachrichtigung mit der Nachricht "Das ist eine Nachricht" ohne vorbestimmten Titel an alle <b>deine</b> Devices.<br><br>
        <code>set Pushbullet message Das ist eine Nachricht | Ein Titel</code><br>
        Sendet eine Push Benachrichtigung mit der Nachricht "Das ist eine Nachricht" mit dem Titel "Ein Titel" an alle <b>deine</b> Devices.<br><br>
        <code>set Pushbullet message This is a message | Ein Titel | iPhone</code><br>
        Sendet eine Push Benachrichtigung mit der Nachricht "Das ist eine Nachricht" mit dem Titel "Ein Titel" an deinen Device iPhone.<br><br>
        <code>set Pushbullet message This is a message | Ein Titel | Max Mustermann</code><br>
        Sendet eine Push Benachrichtigung mit der Nachricht "Das ist eine Nachricht" mit dem Titel "Ein Titel" an deinen Kontakt Max Mustermann.<br><br>
      </ul>
      <br>
      Notiz:<br>
      Leerstellen vor und nach dem Trenner | werden nicht benötigt.
    </ul><br>
    
  <a name="Pushbullet_Get"></a>
    <b>Get</b>
    <ul>
      <li>devices<br>
        Liest alle Geräte und Kontakte ein und setzt die entsprechenden Readings.</li>
    </ul><br> 

  <a name="Pushbullet_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>defaultDevice<br>
        Standart Device für Pushnachrichten.</li>
      <li>defaultTitle<br>
        Standart Titel für Pushnachrichten. Wenn nicht gesetzt ist der Standart Titel FHEM</li>
    </ul>
</ul>

=end html_DE

=cut