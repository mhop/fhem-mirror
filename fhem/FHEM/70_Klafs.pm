# $Id$
##############################################################################
#
#     70_Klafs.pm
#     A FHEM Perl module to control a Klafs sauna.
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
#     along with fhem. If not, see <http://www.gnu.org/licenses/>.
#     Forum: https://forum.fhem.de/index.php?topic=127701
#
##############################################################################
package main;

use strict;
use warnings;
use Carp qw(carp);
use Scalar::Util    qw(looks_like_number);
use Time::HiRes     qw(gettimeofday);
use JSON            qw(decode_json encode_json);
#use Encode          qw(encode_utf8 decode_utf8);
use Time::Piece;
use Time::Local;
#use Data::Dumper;
use HttpUtils;
use FHEM::Core::Authentication::Passwords qw(:ALL);

my %sets = (
    off                 => 'noArg',
    password            => '',
    on                  => '',
    ResetLoginFailures  => '',
    update              => 'noArg',
);

my %gets = (
        help          => 'noArg',
        SaunaID       => 'noArg',
        );

###################################
sub KLAFS_Initialize {
    my $hash = shift;

    Log3 ($hash, 5, 'KLAFS_Initialize: Entering');
    $hash->{DefFn}    = \&Klafs_Define;
    $hash->{UndefFn}  = \&Klafs_Undef;
    $hash->{SetFn}    = \&Klafs_Set;
    $hash->{AttrFn}   = \&Klafs_Attr;
    $hash->{GetFn}    = \&Klafs_Get;
    $hash->{RenameFn} = \&Klafs_Rename;
    $hash->{AttrList} = 'username saunaid pin interval disable:1,0 ' . $main::readingFnAttributes;
    return;
}

sub Klafs_Attr
{
  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};

        if( $attrName eq 'disable' ) {
          RemoveInternalTimer($hash) if $cmd ne 'del';
          InternalTimer(gettimeofday(), \&Klafs_DoUpdate, $hash, 0) if $cmd eq 'del' || !$attrVal && $init_done;
        }elsif( $attrName eq 'username' ) {
                if( $cmd eq 'set' ) {
                    $hash->{Klafs}->{username} = $attrVal;
                    Log3 ($name, 3, "$name - username set to " . $hash->{Klafs}->{username});
                }
        }elsif( $attrName eq 'saunaid' ) {
                if( $cmd eq 'set' ) {
                    $hash->{Klafs}->{saunaid} = $attrVal;
                    Log3 ($name, 3, "$name - saunaid set to " . $hash->{Klafs}->{saunaid});
                }
        }elsif( $attrName eq 'pin' ) {
                if( $cmd eq 'set' ) {
                    return 'Pin is not a number!'  if !looks_like_number($attrVal);
                    $hash->{Klafs}->{pin} = $attrVal;
                    Log3 ($name, 3, "$name - pin set to " . $hash->{Klafs}->{pin});
                }
        }elsif( $attrName eq 'interval' ) {
          if( $cmd eq 'set' ) {
            return 'Interval must be greater than 0' if !$attrVal;
            $hash->{Klafs}->{interval} = $attrVal;
            InternalTimer( time() + $hash->{Klafs}->{interval}, \&Klafs_DoUpdate, $hash, 0 );
            Log3 ($name, 3, "$name - set interval: $attrVal");
          }elsif( $cmd eq 'del' ) {
            $hash->{Klafs}->{interval} = 60;
            InternalTimer( time() + $hash->{Klafs}->{interval}, \&Klafs_DoUpdate, $hash, 0 );
            Log3 ($name, 3, "$name - deleted interval and set to default: 60");
          }
        }
    return;
}

###################################
sub Klafs_Define {
    my $hash = shift;
    my $def  = shift;

    return $@ if !FHEM::Meta::SetInternals($hash);
    my @args = split m{\s+}, $def;
    my $usage = qq (syntax: define <name> KLAFS);
    return $usage if ( @args != 2 );
    my ( $name, $type ) = @args;

    Log3 ($name, 5, "KLAFS $name: called function KLAFS_Define()");

    $hash->{NAME} = $name;
    $hash->{helper}->{passObj} = FHEM::Core::Authentication::Passwords->new($hash->{TYPE});

    readingsSingleUpdate( $hash, "last_errormsg", "0", 0 );
    Klafs_CONNECTED($hash,'initialized',1);
    $hash->{Klafs}->{interval}      = 60;
    InternalTimer( time() + $hash->{Klafs}->{interval}, \&Klafs_DoUpdate, $hash, 0 );
    $hash->{Klafs}->{reconnect}     = 0;
    $hash->{Klafs}->{expire}        = time();

    InternalTimer(gettimeofday() + AttrVal($name,'interval',$hash->{Klafs}->{interval}), 'Klafs_DoUpdate', $hash, 0) if !$init_done;
    notifyRegexpChanged($hash, 'global',1);
    Klafs_DoUpdate($hash) if $init_done && !AttrVal($name,'disable',0);

    return;
}

###################################
sub Klafs_Undef {
    my $hash = shift // return;
    my $name = $hash->{NAME};
    Log3 ($name, 5, "KLAFS  $name: called function KLAFS_Undefine()");

    # De-Authenticate
    Klafs_CONNECTED( $hash, 'deauthenticate',1 );

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

sub Klafs_Rename
{
        my $name_new = shift // return;
        my $name_old = shift // return;

        my $passObj = $main::defs{$name_new}->{helper}->{passObj};

        my $password = $passObj->getReadPassword($name_old) // return;

        $passObj->setStorePassword($name_new, $password);
        $passObj->setDeletePassword($name_old);

        return;
}

sub Klafs_CONNECTED {
    my $hash = shift // return;
    my $set  = shift;
    my $notUseBulk = shift;

    if ($set) {
      $hash->{Klafs}->{CONNECTED} = $set;

      if ( $notUseBulk ) {
        readingsSingleUpdate($hash,'state',$set,1) if $set ne ReadingsVal($hash->{NAME},'state','');
      } else {
        readingsBulkUpdate($hash,'state',$set) if $set ne ReadingsVal($hash->{NAME},'state','');
      }
      return;
    }
    return 'disabled' if $hash->{Klafs}->{CONNECTED} eq 'disabled';
    return 1 if $hash->{Klafs}->{CONNECTED} eq 'connected';
        return 0;
}

##############################################################
#
# API AUTHENTICATION
#
##############################################################
sub Klafs_Auth{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    # $hash->{Klafs}->{reconnect}: Sperre bei Reconnect. Zwischen Connects müssen 300 Sekunden liegen.
    # $hash->{Klafs}->{LoginFailures}: Anzahl fehlerhafte Logins. Muss 0 sein, sonst kein connect. Bei drei Fehlversuchen sperrt Klafs den Benutzer

    $hash->{Klafs}->{reconnect} = 0 if(!defined $hash->{Klafs}->{reconnect});
    my $LoginFailures = ReadingsVal( $name, "LoginFailures", "0" );
    
    $hash->{Klafs}->{LoginFailures} //= '';
    if($hash->{Klafs}->{LoginFailures} eq ""){
       $hash->{Klafs}->{LoginFailures} = 0;
    }

    if (time() >= $hash->{Klafs}->{reconnect}){
      Log3 ($name, 4, "Reconnect");


      my $username = $hash->{Klafs}->{username} // carp q[No username found!]  && return;
      my $password = $hash->{helper}->{passObj}->getReadPassword($name) // q{} && carp q[No password found!]  && return;;

      
      #Reading auslesen und definieren um das Reading unten zu schreiben. Intern wird $hash->{Klafs}->{LoginFailures}, weil Readings ggf. nicht schnell genug zur Verfuegung stehen.
      my $LoginFailures = ReadingsVal( $name, "LoginFailures", "0" );

      return if $hash->{Klafs}->{LoginFailures} > 0;
      Log3 ($name, 4, "Anzahl Loginfailures: $hash->{Klafs}->{LoginFailures}");
      
      if ( $hash->{Klafs}->{username} eq "") {
            my $msg = "Missing attribute: attr $name username <username>";
               Log3 ($name, 4, $msg);
               return $msg;
      }elsif ( $password eq "") {
            my $msg = "Missing password: set $name password <password>";
               Log3 ($name, 4, $msg);
               return $msg;
      }else{
        # Reconnects nicht unter 300 Sekunden durchführen
        my $reconnect = time() + 300;
        $hash->{Klafs}->{reconnect} = $reconnect;
        my $header = "Content-Type: application/x-www-form-urlencoded\r\n".
                     "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36";
        my $datauser   = "UserName=$username&Password=$password";

        if ($hash->{Klafs}->{LoginFailures} eq "0"){

          HttpUtils_NonblockingGet({
              url                          => "https://sauna-app.klafs.com/Account/Login",
              ignoreredirects        => 1,
              timeout                      => 5,
              hash                        => $hash,
              method                      => "POST",
              header                      => $header,  
              data                        => $datauser,
              callback              => \&Klafs_AuthResponse,
          });  
        }
      }
    }
    return;
}

# Antwortheader aus dem Login auslesen fuer das Cookie
sub Klafs_AuthResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $header = $param->{httpheader};
  Log3 ($name, 5, "header: $header");
  Log3 ($name, 5, "Data: $data");
  Log3 ($name, 5, "Error: $err");
  readingsBeginUpdate($hash);
   if($data=~/<div class="validation-summary-errors" data-valmsg-summary="true"><ul><li>/) {
     for my $err ($data =~ m /<div class="validation-summary-errors" data-valmsg-summary="true"><ul><li> ?(.*)<\/li>/) {
       my %umlaute = ("&#228;" => "ae", "&#252;" => "ue", "&#196;" => "Ae", "&#214;" => "Oe", "&#246;" => "oe", "&#220;" => "Ue", "&#223;" => "ss");
       my $umlautkeys = join ("|", keys(%umlaute));
       $err=~ s/($umlautkeys)/$umlaute{$1}/g;
       Log3 ($name, 1, "KLAFS $name: $err");
       $hash->{Klafs}->{LoginFailures} = $hash->{Klafs}->{LoginFailures}+1;
       readingsBulkUpdate( $hash, 'last_errormsg', $err );
       readingsBulkUpdate( $hash, 'LoginFailures', $hash->{Klafs}->{LoginFailures});
       }
       Klafs_CONNECTED($hash,'error');
   }else{
     readingsBulkUpdate( $hash, 'LoginFailures', 0, 0);
     $hash->{Klafs}->{LoginFailures} =0;
     for my $cookie ($header =~ m/set-cookie: ?(.*)/gi) {
         $cookie =~ /([^,; ]+)=([^,;\s\v]+)[;,\s\v]*([^\v]*)/;
         my $aspxauth  = $1 . "=" .$2 .";";
         $hash->{Klafs}->{cookie}    = $aspxauth;
         Log3 ($name, 4, "$name: GetCookies parsed Cookie: $aspxauth");
         
         # Cookie soll nach 2 Tagen neu erzeugt werden
         my $expire = time() + 172800;
         $hash->{Klafs}->{expire}    = $expire;
         my $expire_date = strftime("%Y-%m-%d %H:%M:%S", localtime($expire));
         readingsBulkUpdate( $hash, 'cookieExpire', $expire_date, 0 );
         
         Klafs_CONNECTED($hash,'authenticated');
     }
  }
  readingsEndUpdate($hash,1);
  return;
}
##############################################################
#
# Cookie pruefen und Readings erneuern
#
##############################################################

sub klafs_getStatus{
    my ($hash, $def) = @_;
    my $name  = $hash->{NAME};

    my $LoginFailures = ReadingsVal( $name, "LoginFailures", "0" );
    if(!defined $hash->{Klafs}->{LoginFailures}){
       $hash->{Klafs}->{LoginFailures} = $LoginFailures;
    }

    # SaunaIDs für GET zur Verfügung stellen
    Klafs_GetSaunaIDs_Send($hash);


    if ( $hash->{Klafs}->{saunaid} eq "") {
      my $msg = "Missing attribute: attr $name saunaid <saunaid> -> Use <get $name SaunaID> to receive your SaunaID";
         Log3 ($name, 1, $msg);
         return $msg;
    }
    
    my $aspxauth = $hash->{Klafs}->{cookie};
    my $saunaid  = $hash->{Klafs}->{saunaid};

      my $header_gs = "Content-Type: application/json\r\n".
                      "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                      "Cookie: $aspxauth";
      my $datauser_gs = '{"saunaId":"'.$saunaid.'"}';

      HttpUtils_NonblockingGet({
          url                => "https://sauna-app.klafs.com/Control/GetSaunaStatus",
          timeout            => 5,
          hash               => $hash,
          method             => "POST",
          header             => $header_gs,  
          data                 => $datauser_gs,
          callback           => \&klafs_getStatusResponse,
      });
      
      #Name Vorname Mail Benutzername
      #GET Anfrage mit ASPXAUTH
      my $header_user = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                        "Cookie: $aspxauth";

      HttpUtils_NonblockingGet({
          url                => "https://sauna-app.klafs.com/Account/ChangeProfile",
          timeout            => 5,
          hash               => $hash,
          method             => "GET",
          header             => $header_user,
          callback           => \&Klafs_GETProfile,
      });
      
      my $header_set = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                       "Cookie: $aspxauth";

      HttpUtils_NonblockingGet({
          url                => "https://sauna-app.klafs.com/Control/ChangeSettings",
          timeout            => 5,
          hash               => $hash,
          method             => "GET",
          header             => $header_set,
          callback           => \&Klafs_GETSettings,
      });
      return;
}

sub klafs_getStatusResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $header = $param->{httpheader};
  
  Log3 ($name, 5, "Status header: $header");
  Log3 ($name, 5, "Status Data: $data");
  Log3 ($name, 5, "Status Error: $err");
  
  if($data !~/Account\/Login/) {
    # Wenn in $data eine Anmeldung verlangt wird und kein json kommt, darf es nicht weitergehen.
    # Connect darf es hier nicht geben. Das darf nur an einer Stelle kommen. Sonst macht perl mehrere connects gleichzeitig- bei 3 Fehlversuchen wäre der Account gesperrt
     
     #my $return = decode_json( "$data" );
     my $entries;
     if ( !eval { $entries = decode_json($data) ; 1 } ) {
       #sonstige Fehlerbehandlungsroutinen hierher, dann ;
       return Log3($name, 1, "JSON decoding error: $@");
     }

     # boolsche Werte in true/false uebernehmen
     for my $key (qw( saunaSelected sanariumSelected irSelected isConnected isPoweredOn isReadyForUse showBathingHour)) {
      $entries->{$key} = $entries->{$key} ?  q{true} : q{false} ;
     }
     my $power = $entries->{isPoweredOn} eq q{true}  ? 'on' 
               : $entries->{isPoweredOn} eq q{false} ? 'off'
               : 0;
     $entries->{power} = $power;

     $entries->{statusMessage} //= '';
     $entries->{currentTemperature} = '0' if $entries->{currentTemperature} eq '141';
     $entries->{RemainTime} = sprintf("%2.2d:%2.2d" , $entries->{bathingHours}, $entries->{bathingMinutes});
     my $modus = $entries->{saunaSelected} eq q{true}     ? 'Sauna' 
                : $entries->{sanariumSelected} eq q{true} ? 'Sanarium'
                : $entries->{irSelected} eq q{true}       ? 'Infrared'
                : 0;
    $entries->{Mode} = $modus;

    # Loop ueber $entries und ggf. reading schreiben
    my $old;
    readingsBeginUpdate ($hash);
    for my $record ($entries) {
      for my $key (keys(%$record)) {
        my $new = $record->{$key};
        # Alter Wert Readings auslesen
        $old = ReadingsVal( $name, $key, "" );
        next if $old eq $new;
        # Readings schreiben, wenn es einen anderen Wert hat
        readingsBulkUpdate($hash, $key, $new);
      }
    }
    
    Klafs_CONNECTED($hash,'connected');
    readingsEndUpdate($hash, 1);
  }else{
   # Wenn Account/Login zurück kommt, dann benötigt es einen reconnect
   Klafs_CONNECTED($hash,'disconnected', 1);
  }
  return;
}

sub Klafs_GETProfile {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $header = $param->{httpheader};
  Log3 ($name, 5, "Profile header: $header");
  Log3 ($name, 5, "Profile Data: $data");
  Log3 ($name, 5, "Profile Error: $err");
  
  if($data !~/Account\/Login/) {
    # Wenn in $data eine Anmeldung verlangt wird und kein json kommt, darf es nicht weitergehen.
    # Connect darf es hier nicht geben. Das darf nur an einer Stelle kommen. Sonst macht perl mehrere connects gleichzeitig- bei 3 Fehlversuchen wäre der Account gesperrt
     readingsBeginUpdate ($hash);
     if($data=~/<input class="ksa-iw-hidden" id="UserName" name="UserName" type="text" value=\"/) {
       for my $output ($data =~ m /<input class="ksa-iw-hidden" id="UserName" name="UserName" type="text" value=\"?(.*)\"/) {
         my $usercloud    = ReadingsVal( $name, "username", "" );
         if($usercloud eq "" || $usercloud ne $1){
           readingsBulkUpdate( $hash, "username", "$1", 0 );
         }
       }
     }
     
     if($data=~/<input class="ksa-iw-change-profile-input-text" id="Email" name="Email" type="text" value=\"/) {
       for my $output ($data =~ m /<input class="ksa-iw-change-profile-input-text" id="Email" name="Email" type="text" value=\"?(.*)\"/) {
         my $mailcloud    = ReadingsVal( $name, "mail", "" );
         if($mailcloud eq "" || $mailcloud ne $1){
           readingsBulkUpdate( $hash, "mail", "$1", 0 );
         }
       }
     }
     
     if($data=~/<input class="ksa-iw-change-profile-input-text" id="FirstName" name="FirstName" type="text" value=\"/) {
       for my $output ($data =~ m /<input class="ksa-iw-change-profile-input-text" id="FirstName" name="FirstName" type="text" value=\"?(.*)\"/) {
         my $fnamecloud    = ReadingsVal( $name, "firstname", "" );
         if($fnamecloud eq "" || $fnamecloud ne $1){
           readingsBulkUpdate( $hash, "firstname", "$1", 0 );
         }
       }
     }
     
     if($data=~/<input class="ksa-iw-change-profile-input-text" id="LastName" name="LastName" type="text" value=\"/) {
       for my $output ($data =~ m /<input class="ksa-iw-change-profile-input-text" id="LastName" name="LastName" type="text" value=\"?(.*)\"/) {
         my $lnamecloud    = ReadingsVal( $name, "lastname", "" );
         if($lnamecloud eq "" || $lnamecloud ne $1){
           readingsBulkUpdate( $hash, "lastname", "$1", 0 );
         }
       }
     }
     readingsEndUpdate($hash, 1);
  }else{
   # Wenn Account/Login zurück kommt, dann benötigt es einen reconnect
   Klafs_CONNECTED($hash,'disconnected', 1);
  }
  return;
}

sub Klafs_GETSettings {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $header = $param->{httpheader};
  Log3 ($name, 5, "Settings header: $header");
  Log3 ($name, 5, "Settings Data: $data");
  Log3 ($name, 5, "Settings Error: $err");
  
  if($data !~/Account\/Login/) {
    # Wenn in $data eine Anmeldung verlangt wird und kein json kommt, darf es nicht weitergehen.
    # Connect darf es hier nicht geben. Das darf nur an einer Stelle kommen. Sonst macht perl mehrere connects gleichzeitig- bei 3 Fehlversuchen wäre der Account gesperrt
    if($data=~/StandByTime: parseInt\(\'/) {
       readingsBeginUpdate ($hash);
       for my $output ($data =~ m /StandByTime: parseInt\(\'?(.*)'/) {
        my $sbtime = $1 eq q{24}   ? '1 Tag' 
                   : $1 eq q{72}   ? '3 Tage'
                   : $1 eq q{168}  ? '1 Woche'
                   : $1 eq q{672}  ? '4 Wochen'
                   : $1 eq q{1344} ? '8 Wochen'
                   : 'Internal error';
        my $sbcloud    = ReadingsVal( $name, 'standbytime', '' );
        if($sbcloud eq '' || $sbcloud ne $sbtime){
          readingsBulkUpdate( $hash, 'standbytime', $sbtime, 1 );
        }
       }
       readingsEndUpdate($hash, 1);
     }

     if($data=~/Language: \'/) {
       readingsBeginUpdate ($hash);
       for my $output ($data =~ m /Language: \'?(.*)'/) {
         my $language = $1 eq q{de} ? 'Deutsch' 
                      : $1 eq q{en} ? 'Englisch'
                      : $1 eq q{fr} ? 'Franzoesisch'
                      : $1 eq q{es} ? 'Spanisch'
                      : $1 eq q{ru} ? 'Russisch'
                      : $1 eq q{pl} ? 'Polnisch'
                      : 'Internal error';
         my $langcloud    = ReadingsVal( $name, 'langcloud', '' );
         if($langcloud eq '' || $langcloud ne $language){
           readingsBulkUpdate( $hash, 'langcloud', $language, 1 );
         }
       }
       readingsEndUpdate($hash, 1);
     }
  }else{
   # Wenn Account/Login zurück kommt, dann benötigt es einen reconnect
   Klafs_CONNECTED($hash,'disconnected', 1);
  }
  return;
}

###################################
sub Klafs_Get {
    my ( $hash, @a ) = @_;

    my $name = $hash->{NAME};
    my $what;
    Log3 ($name, 5, "KLAFS $name: called function KLAFS_Get()");

    return "argument is missing" if ( @a < 2 );

    $what = $a[1];


    return _KLAFS_help($hash) if ( $what =~ /^(help)$/ );
    return _KLAFS_saunaid($hash) if ( $what =~ /^(SaunaID)$/ );
    return "$name get with unknown argument $what, choose one of " . join(" ", sort keys %gets); 
}

sub _KLAFS_help {
    return << 'EOT';
------------------------------------------------------------------------------------------------------------------------------------------------------------
| Set Parameter                                                                                                                                            |
------------------------------------------------------------------------------------------------------------------------------------------------------------
|on                 | ohne Parameter -> Default Sauna 90 Grad                                                                                              |
|                   | set "name" on Sauna 90 - 3 Parameter: Sauna mit Temperatur [10-100]; Optional Uhrzeit [19:30]                                        |
|                   | set "name" on Saunarium 65 5 - 4 Parameter: Sanarium mit Temperatur [40-75]; Optional HumidtyLevel [0-10] und Uhrzeit [19:30]        |
|                   | set "name" on Infrared 30 5 - 4 Parameter: Infrarot mit Temperatur [20-40] und IR Level [0-10]; Optional Uhrzeit [19:30]             |
|                   | Infrarot ist nicht supported, da keine Testumgebung verfuegbar.                                                                      |
------------------------------------------------------------------------------------------------------------------------------------------------------------
|off                | Schaltet die Sauna|Sanarium|Infrarot aus - ohne Parameter.                                                                           |
------------------------------------------------------------------------------------------------------------------------------------------------------------
|ResetLoginFailures | Bei fehlerhaftem Login wird das Reading LoginFailures auf 1 gesetzt. Damit ist der automatische Login vom diesem Modul gesperrt.     |
|                   | Klafs sperrt den Account nach 3 Fehlversuchen. Damit nicht automatisch 3 falsche Logins hintereinander gemacht werden.               |
|                   | ResetLoginFailures setzt das Reading wieder auf 0. Davor sollte man sich erfolgreich an der App bzw. unter sauna-app.klafs.com       |
|                   | angemeldet bzw. das Passwort zurueckgesetzt haben. Erfolgreicher Login resetet die Anzahl der Fehlversuche in der Klafs-Cloud.       |
------------------------------------------------------------------------------------------------------------------------------------------------------------
|update             | Refresht die Readings und fuehrt ggf. ein Login durch.                                                                               |
------------------------------------------------------------------------------------------------------------------------------------------------------------
| Get Parameter                                                                                                                                            |
------------------------------------------------------------------------------------------------------------------------------------------------------------
|SaunaID            | Liest die verfuegbaren SaunaIDs aus.                                                                                                 |
------------------------------------------------------------------------------------------------------------------------------------------------------------
|help               | Diese Hilfe                                                                                                                          |
------------------------------------------------------------------------------------------------------------------------------------------------------------
EOT
}

sub Klafs_GetSaunaIDs_Send{
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Klafs_Whoami());
    my $aspxauth = $hash->{Klafs}->{cookie};
    return if $hash->{Klafs}->{LoginFailures} > 0;
    Log3 ($name, 5, "$name ($self) - executed.");
    
    my $header = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                   "Cookie: $aspxauth";
      HttpUtils_NonblockingGet({
          url                => "http://sauna-app.klafs.com/Control",
          timeout            => 5,
          hash               => $hash,
          method             => "GET",
          header             => $header,
          callback           => \&Klafs_GetSaunaIDs_Receive,
      });
    return;
}

sub Klafs_GetSaunaIDs_Receive {
    my ($param, $err, $data) = @_;
    my ($name,$self,$hash) = ($param->{hash}->{NAME},Klafs_Whoami(),$param->{hash});
    my $returnwerte;

    Log3 ($name, 5, "$name ($self) - executed.");
    
    if ($err ne "") {
        Log3 ($name, 4, "$name ($self) - error.");
    }
    elsif ($data ne "") {
        if ($param->{code} == 200 || $param->{code} == 400  || $param->{code} == 401) {
        if($data !~/Account\/Login/) {
          # Wenn in $data eine Anmeldung verlangt wird und keine Daten, darf es nicht weitergehen.
          # Connect darf es hier nicht geben. Das darf nur an einer Stelle kommen. Sonst macht perl mehrere connects gleichzeitig - bei 3 Fehlversuchen wäre der Account gesperrt
           $returnwerte = "";       
           if($data=~/<tr class="ksa-iw-sauna-webgrid-row-style">/) {
             for my $output ($data =~ m /<tr class="ksa-iw-sauna-webgrid-row-style">(.*?)<\/tr>/gis) {
               $output=~ m/<span id="lbldeviceName">(.*?)<\/span>/g;
               $returnwerte .= $1.": ";
               $output=~ m/<div class="ksa-iw-sauna-status" id=\"(.*?)\"/g;
               $returnwerte .= $1."\n";
             }
             $hash->{Klafs}->{GetSaunaIDs} = $returnwerte;
           }
        }
        }
    }
    return;
}

sub _KLAFS_saunaid {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    
      return "======================================== FOUND SAUNA-IDs ========================================\n"
           . $hash->{Klafs}->{GetSaunaIDs} .
             "=================================================================================================";
      
}


###################################
sub Klafs_Set {
    my ( $hash, $name, $cmd, @args ) = @_;
    return if $hash->{Klafs}->{LoginFailures} > 0 and !$cmd;


    if (Klafs_CONNECTED($hash) eq 'disabled' && $cmd !~ /clear/) {
        Log3 ($name, 3, "$name: set called with $cmd but device is disabled!") if ($cmd ne "?");
        return "Unknown argument $cmd, choose one of clear:all,readings";
    }
    
    my $temperature;
    my $level;
    my $power = ReadingsVal( $name, "power", "off" );
    
    
    # Klafs rundet bei der Startzeit immer auf volle 10 Minuten auf. Das ist der Zeitpunkt, wann die Sauna fertig aufgeheizt sein soll. Naechste 10 Minuten heisst also sofort aufheizen
    my $FIFTEEN_MINS = (15 * 60);
    my $now = time;
    if (my $diff = $now % $FIFTEEN_MINS) {
     $now += $FIFTEEN_MINS - $diff;
    }
    my $next = scalar localtime $now;
    my @Zeit = split(/ /,$next);
    my @Uhrzeit = split(/:/,$Zeit[3]);
    my $std = $Uhrzeit[0];
    my $min = $Uhrzeit[1];
    
    if($std < 10){
      if(substr($std,0,1) eq "0"){
        $std = substr($std,1,1);
      }
    }
    if($min < 10){
      if(substr($min,0,1) eq "0"){
        $min = substr($min,1,1);
      }
    }
    

    # on ()
    if ( $cmd eq "on" ) {
       Log3 ($name, 2, "KLAFS set $name " . $cmd);
        
       klafs_getStatus($hash);
       my $mode        = shift @args;
       my $aspxauth    = $hash->{Klafs}->{cookie};
       
       my $pin         = $hash->{Klafs}->{pin};
       my $saunaid     = $hash->{Klafs}->{saunaid};
       my $selectedSaunaTemperature = ReadingsVal( $name, "selectedSaunaTemperature", "90" );
       my $selectedSanariumTemperature = ReadingsVal( $name, "selectedSanariumTemperature", "65" );
       my $selectedIrTemperature = ReadingsVal( $name, "selectedIrTemperature", "0" );
       my $selectedHumLevel = ReadingsVal( $name, "selectedHumLevel", "5" );
       my $selectedIrLevel = ReadingsVal( $name, "selectedIrLevel", "0" );
       my $isConnected = ReadingsVal( $name, "isConnected", "true" );
       my $isPoweredOn = ReadingsVal( $name, "isPoweredOn", "false" );
       my $isReadyForUse = ReadingsVal( $name, "isReadyForUse", "false" );
       my $currentTemperature = ReadingsVal( $name, "currentTemperature", "141" );
       if($currentTemperature eq "0"){
         $currentTemperature = "141";
       }
       my $currentHumidity = ReadingsVal( $name, "currentHumidity", "0" );
       my $statusCode = ReadingsVal( $name, "statusCode", "0" );
       my $statusMessage = ReadingsVal( $name, "statusMessage", "" );
       if($statusMessage eq ""){
         $statusMessage = 'null';
       }
       my $showBathingHour = ReadingsVal( $name, "showBathingHour", "false" );
       my $bathingHours = ReadingsVal( $name, "bathingHours", "0" );
       my $bathingMinutes = ReadingsVal( $name, "bathingMinutes", "0" );
       my $currentHumidityStatus = ReadingsVal( $name, "currentHumidityStatus", "0" );
       my $currentTemperatureStatus = ReadingsVal( $name, "currentTemperatureStatus", "0" );

       if ( $pin eq "") {
            my $msg = "Missing attribute: attr $name pin <pin>";
               Log3 ($name, 1, $msg);
               return $msg;
       }elsif ( $saunaid eq "") {
            my $msg = "Missing attribute: attr $name $saunaid <saunaid>";
               Log3 ($name, 1, $msg);
               return $msg;
       }else{
         my $datauser_cv = "";
         if ( $mode eq "Sauna"){
           # Sauna hat 1 Parameter: Temperatur
           #return "Zu wenig Argumente: Temperatur fehlt" if ( @args < 1 );
           my $temperature = shift @args;
           if(!looks_like_number($temperature)){
            return "Geben Sie einen nummerischen Wert  fuer <temperatur> ein";
           }
           if ($temperature >= 10 && $temperature <=100 && $temperature ne ""){
             # Wenn Temperatur zwischen 10 und 100 Grad angegeben wurde: Werte aus der App entnommen
             $temperature = $temperature;
           }else{
             # Keine Temperatur oder ausser Range, letzter Wert auslesen ggf. auf 90 Grad setzen
             $temperature    = ReadingsVal( $name, "selectedSaunaTemperature", "" );
             if ($temperature eq "" || $temperature eq 0){
               $temperature = 90;
             }
           }
           my $Time;
           $Time  = shift @args;
           
           if(!defined($Time)){
            $Time ="$Uhrzeit[0]:$Uhrzeit[1]";
           }

           if($Time =~ /:/){
               my @Timer = split(/:/,$Time);
               $std = $Timer[0];
               $min = $Timer[1];
               if($std < 10){
                 if(substr($std,0,1) eq "0"){
                   $std = substr($std,1,1);
                 }
               }
               if($min < 10){

                 if(substr($min,0,1) eq "0"){
                   $min = substr($min,1,1);
                 }
               }
           }
           if ($std <0 || $std >23 || $min <0 || $min >59){
           return "Checken Sie das Zeitformat $std:$min\n";
           }
           $datauser_cv = '{"changedData":{"saunaId":"'.$saunaid.'","saunaSelected":true,"sanariumSelected":false,"irSelected":false,"selectedSaunaTemperature":'.$temperature.',"selectedSanariumTemperature":'.$selectedSanariumTemperature.',"selectedIrTemperature":'.$selectedIrTemperature.',"selectedHumLevel":'.$selectedHumLevel.',"selectedIrLevel":'.$selectedIrLevel.',"selectedHour":'.$std.',"selectedMinute":'.$min.',"isConnected":'.$isConnected.',"isPoweredOn":'.$isPoweredOn.',"isReadyForUse":'.$isReadyForUse.',"currentTemperature":'.$currentTemperature.',"currentHumidity":'.$currentHumidity.',"statusCode":'.$statusCode.',"statusMessage":'.$statusMessage.',"showBathingHour":'.$showBathingHour.',"bathingHours":'.$bathingHours.',"bathingMinutes":'.$bathingMinutes.',"currentHumidityStatus":'.$currentHumidityStatus.',"currentTemperatureStatus":'.$currentTemperatureStatus.'}}';
         }elsif ( $mode eq "Sanarium" ) {
           my $temperature = shift @args;
           

           if(!looks_like_number($temperature)){
            return "Geben Sie einen nummerischen Wert  fuer <temperatur> ein";
           }
           if ($temperature >= 40 && $temperature <=75 && $temperature ne ""){
             $temperature = $temperature;
           }else{
            # Letzer Wert oder Standardtemperatur
             $temperature    = ReadingsVal( $name, "selectedSanariumTemperature", "" );
             if ($temperature eq "" || $temperature eq 0){
               $temperature = 65;
             }
             
           }
           my $Time;
           my $level;
           $level = shift @args;
           $Time  = shift @args;
           
           if(!defined($Time)){
            $Time ="$Uhrzeit[0]:$Uhrzeit[1]";
           }

           # Parameter level ist optional. Wird in der ersten Variable eine anstelle des Levels eine Uhrzeit gefunden, dann level auf "" setzen und $std,$min setzen
           if($level =~ /:/ || $Time =~ /:/){
             if($level =~ /:/){
               my @Timer = split(/:/,$level);
               $std = $Timer[0];
               $min = $Timer[1];
               if($std < 10){
                 if(substr($std,0,1) eq "0"){
                   $std = substr($std,1,1);
                 }
               }
               if($min < 10){
                 if(substr($min,0,1) eq "0"){
                   $min = substr($min,1,1);
                 }
               }
               $level = "";
             }else{
               my @Timer = split(/:/,$Time);
               $std = $Timer[0];
               $min = $Timer[1];
               if($std < 10){
                 if(substr($std,0,1) eq "0"){
                   $std = substr($std,1,1);
                 }
               }
               if($min < 10){
                 if(substr($min,0,1) eq "0"){
                   $min = substr($min,1,1);
                 }
               }
             }
           }
           if ($std <0 || $std >23 || $min <0 || $min >59){
           return "Checken Sie das Zeitformat $std:$min\n";
           }
           
           # Auf volle 10 Minuten runden
           #if( substr($min,-1,1) > 0){
           # my $min1 = substr($min,0,1)+1;
           # $min = $min1."0";
           #  if($min eq 60){
           #  $min = "00";
           #  $std = $std+1;
           #   if($std eq 24){
           #      $std = "00";
           #    }
           #  }
           #}
           
           if ($level >= 0 && $level <=10 && $level ne ""){
             $level = $level;
           }else{
             # Letzer Wert oder Standardlevel
             $level    = ReadingsVal( $name, "selectedHumLevel", "" );
             if ($level eq ""){
               $level = 5;
             }
             
           }
           $datauser_cv = '{"changedData":{"saunaId":"'.$saunaid.'","saunaSelected":false,"sanariumSelected":true,"irSelected":false,"selectedSaunaTemperature":'.$selectedSaunaTemperature.',"selectedSanariumTemperature":'.$temperature.',"selectedIrTemperature":'.$selectedIrTemperature.',"selectedHumLevel":'.$level.',"selectedIrLevel":'.$selectedIrLevel.',"selectedHour":'.$std.',"selectedMinute":'.$min.',"isConnected":'.$isConnected.',"isPoweredOn":'.$isPoweredOn.',"isReadyForUse":'.$isReadyForUse.',"currentTemperature":'.$currentTemperature.',"currentHumidity":'.$currentHumidity.',"statusCode":'.$statusCode.',"statusMessage":'.$statusMessage.',"showBathingHour":'.$showBathingHour.',"bathingHours":'.$bathingHours.',"bathingMinutes":'.$bathingMinutes.',"currentHumidityStatus":'.$currentHumidityStatus.',"currentTemperatureStatus":'.$currentTemperatureStatus.'}}';
         }elsif ( $mode eq "Infrared" ) {
           my $temperature = shift @args;
           if(!looks_like_number($temperature)){
            return "Geben Sie einen nummerischen Wert  fuer <temperatur> ein";
           }
           if ($temperature >= 20 && $temperature <=40 && $temperature ne ""){
             $temperature = $temperature;
           }else{
            # Letzer Wert oder Standardtemperatur
             $temperature    = ReadingsVal( $name, "selectedIrTemperature", "" );
             if ($temperature eq "" || $temperature eq 0){
               $temperature = 35;
             }
           }
           my $Time;
           my $level;
           $level = shift @args;
           $Time  = shift @args;
           
           if(!defined($Time)){
            $Time ="$Uhrzeit[0]:$Uhrzeit[1]";
           }

           # Parameter level ist optional. Wird in der ersten Variable eine anstelle des Levels eine Uhrzeit gefunden, dann level auf "" setzen und $std,$min setzen
           if($level =~ /:/ || $Time =~ /:/){
             if($level =~ /:/){
               my @Timer = split(/:/,$level);
               $std = $Timer[0];
               $min = $Timer[1];
               if($std < 10){
                 if(substr($std,0,1) eq "0"){
                   $std = substr($std,1,1);
                 }
               }
               if($min < 10){
                 if(substr($min,0,1) eq "0"){
                   $min = substr($min,1,1);
                 }
               }
               $level = "";
             }else{
               my @Timer = split(/:/,$Time);
               $std = $Timer[0];
               $min = $Timer[1];
               if($std < 10){
                 if(substr($std,0,1) eq "0"){
                   $std = substr($std,1,1);
                 }
               }
               if($min < 10){
                 if(substr($min,0,1) eq "0"){
                   $min = substr($min,1,1);
                 }
               }
             }
           }
           if ($std <0 || $std >23 || $min <0 || $min >59){
           return "Checken Sie das Zeitformat $std:$min\n";
           }
           
           if ($level >= 0 && $level <=10 && $level ne "" ){
             $level = $level;
           }else{
             # Letzer Wert oder Standardlevel
             $level    = ReadingsVal( $name, "selectedIrLevel", "" );
             if ($level eq ""){
               $level = 5;
             }
           }
           $datauser_cv = '{"changedData":{"saunaId":"'.$saunaid.'","saunaSelected":false,"sanariumSelected":false,"irSelected":true,"selectedSaunaTemperature":'.$selectedSaunaTemperature.',"selectedSanariumTemperature":'.$selectedSanariumTemperature.',"selectedIrTemperature":'.$temperature.',"selectedHumLevel":'.$selectedHumLevel.',"selectedIrLevel":'.$level.',"selectedHour":'.$std.',"selectedMinute":'.$min.',"isConnected":'.$isConnected.',"isPoweredOn":'.$isPoweredOn.',"isReadyForUse":'.$isReadyForUse.',"currentTemperature":'.$currentTemperature.',"currentHumidity":'.$currentHumidity.',"statusCode":'.$statusCode.',"statusMessage":'.$statusMessage.',"showBathingHour":'.$showBathingHour.',"bathingHours":'.$bathingHours.',"bathingMinutes":'.$bathingMinutes.',"currentHumidityStatus":'.$currentHumidityStatus.',"currentTemperatureStatus":'.$currentTemperatureStatus.'}}';
           
         }else{
           $datauser_cv = '{"changedData":{"saunaId":"'.$saunaid.'","saunaSelected":true,"sanariumSelected":false,"irSelected":false,"selectedSaunaTemperature":90,"selectedSanariumTemperature":'.$selectedSanariumTemperature.',"selectedIrTemperature":'.$selectedIrTemperature.',"selectedHumLevel":'.$selectedHumLevel.',"selectedIrLevel":'.$selectedIrLevel.',"selectedHour":'.$std.',"selectedMinute":'.$min.',"isConnected":'.$isConnected.',"isPoweredOn":'.$isPoweredOn.',"isReadyForUse":'.$isReadyForUse.',"currentTemperature":'.$currentTemperature.',"currentHumidity":'.$currentHumidity.',"statusCode":'.$statusCode.',"statusMessage":'.$statusMessage.',"showBathingHour":'.$showBathingHour.',"bathingHours":'.$bathingHours.',"bathingMinutes":'.$bathingMinutes.',"currentHumidityStatus":'.$currentHumidityStatus.',"currentTemperatureStatus":'.$currentTemperatureStatus.'}}';
         }
 
         Log3 ($name, 4, "$name - JSON ON: $datauser_cv");
                                                  # 1) Werte aendern
                                                  #print "Mode: ". $mode . " Temperature: ". $temperature . " Level: " .$level ."\n$datauser_cv\n\n";
                                                  my $header_cv = "Content-Type: application/json\r\n".
                                                                  "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                                                                  "Cookie: $aspxauth";
                                                  HttpUtils_BlockingGet({
                                                      url       => "https://sauna-app.klafs.com//Control/PostConfigChange",
                                                      timeout   => 5,
                                                      hash      => $hash,
                                                      method    => "POST",
                                                      header    => $header_cv,  
                                                      data         => $datauser_cv,
                                                  });
         
         
         my $state_onoff = ReadingsVal( $name, "isPoweredOn", "false" );
         
         # Einschalten, wenn Sauna aus ist.
         if($state_onoff eq "false"){
         my $header_af = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                         "Cookie: $aspxauth";
         my $datauser_af = "s=$saunaid";
         # 2 Steps: 2) Antiforgery erzeugen; 3) Einschalten
         HttpUtils_NonblockingGet({
                             url                => "https://sauna-app.klafs.com/Control/EnterPin",
                             timeout            => 5,
                             hash               => $hash,
                             method             => "POST",
                             header             => $header_af,  
                             data                 => $datauser_af,
                             callback=>sub($$$){
                                                  my ($param, $err, $data) = @_;
                                                  my $hash = $param->{hash};
                                                  my $name = $hash->{NAME};
                                                  my $header = $param->{httpheader};
                                                  Log3 ($name, 5, "header: $header");
                                                  Log3 ($name, 5, "Data: $data");
                                                  Log3 ($name, 5, "Error: $err");
                                                  readingsBeginUpdate ($hash);
                                                  for my $cookie ($header =~ m/set-cookie: ?(.*)/gi) {
                                                      $cookie =~ /([^,; ]+)=([^,;\s\v]+)[;,\s\v]*([^\v]*)/;
                                                      my $antiforgery  = $1 . "=" .$2 .";";
                                                      my $antiforgery_date = strftime("%Y-%m-%d %H:%M:%S", localtime(time()));
                                                      readingsBulkUpdate( $hash, "antiforgery_date", "$antiforgery_date", 1 );
                                                      Log3 ($name, 5, "$name: Antiforgery found: $antiforgery");
                                                      $hash->{Klafs}->{antiforgery}    = $antiforgery;
                                                  }
                                                  readingsEndUpdate($hash, 1);

                                                  # 2) Einschalten
                                                  my $headeron = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                                                                 "Cookie: $aspxauth";
                                                  my $antiforgery = $hash->{Klafs}->{antiforgery};
                                                  my $datauseron = "$antiforgery&Pin=$pin&saunaId=$saunaid";
                                                  HttpUtils_NonblockingGet({
                                                       url        => "https://sauna-app.klafs.com/Control/EnterPin",
                                                       timeout  => 5,
                                                       hash     => $hash,
                                                       method   => "POST",
                                                       header   => $headeron,
                                                       data        => $datauseron,
                                                       callback        => sub($$$){
                                                                             my ($param, $err, $data) = @_;
                                                                             my $hash = $param->{hash};
                                                                             my $name = $hash->{NAME};
                                                                             Log3 ($name, 5, "header: $header");
                                                                             Log3 ($name, 5, "Data: $data");
                                                                             Log3 ($name, 5, "Error: $err");
                                                                             if($data=~/<div class="validation-summary-errors" data-valmsg-summary="true"><ul><li>/) {
                                                                               readingsBeginUpdate ($hash);
                                                                               for my $err ($data =~ m /<div class="validation-summary-errors" data-valmsg-summary="true"><ul><li> ?(.*)<\/li>/) {
                                                                                 my %umlaute = ("&#228;" => "ae", "&#252;" => "ue", "&#196;" => "Ae", "&#214;" => "Oe", "&#246;" => "oe", "&#220;" => "Ue", "&#223;" => "ss");
                                                                                 my $umlautkeys = join ("|", keys(%umlaute));
                                                                                 $err=~ s/($umlautkeys)/$umlaute{$1}/g;
                                                                                 Log3 ($name, 1, "KLAFS $name: $err");
                                                                                 readingsBulkUpdate( $hash, "last_errormsg", "$err", 1 );
                                                                               }
                                                                               readingsEndUpdate($hash, 1);
                                                                              }else{
                                                                               $power    = "on";
                                                                               Log3 ($name, 3, "Sauna on");
                                                                               readingsBeginUpdate ($hash);
                                                                               readingsBulkUpdate( $hash, "power", $power, 1 );
                                                                               readingsBulkUpdate( $hash, "last_errormsg", "0", 1 );
                                                                               readingsEndUpdate($hash, 1);
                                                                               klafs_getStatus($hash);
                                                                             }                                                   
                                                                           }
                                                                          }); 
                                               }
                                 });
         }
       }
    
    # sauna off
    }elsif ( $cmd eq "off" ) {
       Log3 ($name, 2, "KLAFS set $name " . $cmd);
       klafs_getStatus($hash);

       my $aspxauth = $hash->{Klafs}->{cookie};
       
       my $saunaid     = $hash->{Klafs}->{saunaid};
       my $saunaSelected = ReadingsVal( $name, "saunaSelected", "true" );
       my $sanariumSelected = ReadingsVal( $name, "sanariumSelected", "false" );
       my $irSelected = ReadingsVal( $name, "irSelected", "false" );
       
       my $selectedSaunaTemperature = ReadingsVal( $name, "selectedSaunaTemperature", "90" );
       my $selectedSanariumTemperature = ReadingsVal( $name, "selectedSanariumTemperature", "65" );
       my $selectedIrTemperature = ReadingsVal( $name, "selectedIrTemperature", "0" );
       my $selectedHumLevel = ReadingsVal( $name, "selectedHumLevel", "5" );
       my $selectedIrLevel = ReadingsVal( $name, "selectedIrLevel", "0" );
       my $selectedHour = ReadingsVal( $name, "selectedHour", "0" );
       my $selectedMinute = ReadingsVal( $name, "selectedMinute", "0" );
       
       my $isConnected = ReadingsVal( $name, "isConnected", "true" );
       my $isPoweredOn = ReadingsVal( $name, "isPoweredOn", "false" );
       my $isReadyForUse = ReadingsVal( $name, "isReadyForUse", "false" );
       my $currentTemperature = ReadingsVal( $name, "currentTemperature", "141" );
       if($currentTemperature eq "0"){
         $currentTemperature = "141";
       }
       my $currentHumidity = ReadingsVal( $name, "currentHumidity", "0" );
       my $statusCode = ReadingsVal( $name, "statusCode", "0" );
       my $statusMessage = ReadingsVal( $name, "statusMessage", "" );
       if($statusMessage eq ""){
         $statusMessage = 'null';
       }
       my $showBathingHour = ReadingsVal( $name, "showBathingHour", "false" );
       my $bathingHours = ReadingsVal( $name, "bathingHours", "0" );
       my $bathingMinutes = ReadingsVal( $name, "bathingMinutes", "0" );
       my $currentHumidityStatus = ReadingsVal( $name, "currentHumidityStatus", "0" );
       my $currentTemperatureStatus = ReadingsVal( $name, "currentTemperatureStatus", "0" );
       
       if ($saunaid eq ""){
         my $msg = "Missing attribute: attr $name saunaid <saunaid>";
         Log3 ($name, 1, $msg);
         return $msg;
       }else{

         my $header = "Content-Type: application/json\r\n".
                      "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.71 Safari/537.36\r\n".
                      "Cookie: $aspxauth";

         my $datauser_end = '{"changedData":{"saunaId":"'.$saunaid.'","saunaSelected":'.$saunaSelected.',"sanariumSelected":'.$sanariumSelected.',"irSelected":'.$irSelected.',"selectedSaunaTemperature":'.$selectedSaunaTemperature.',"selectedSanariumTemperature":'.$selectedSanariumTemperature.',"selectedIrTemperature":'.$selectedIrTemperature.',"selectedHumLevel":'.$selectedHumLevel.',"selectedIrLevel":'.$selectedIrLevel.',"selectedHour":'.$selectedHour.',"selectedMinute":'.$selectedMinute.',"isConnected":'.$isConnected.',"isPoweredOn":'.$isPoweredOn.',"isReadyForUse":'.$isReadyForUse.',"currentTemperature":'.$currentTemperature.',"currentHumidity":'.$currentHumidity.',"statusCode":'.$statusCode.',"statusMessage":'.$statusMessage.',"showBathingHour":'.$showBathingHour.',"bathingHours":'.$bathingHours.',"bathingMinutes":'.$bathingMinutes.',"currentHumidityStatus":'.$currentHumidityStatus.',"currentTemperatureStatus":'.$currentTemperatureStatus.'}}';
         Log3 ($name, 4, "$name - JSON_OFF: $datauser_end");

         HttpUtils_BlockingGet({
             url                => "https://sauna-app.klafs.com/Control/PostPowerOff",
             timeout            => 5,
             hash               => $hash,
             method             => "POST",
             header             => $header,  
             data         => $datauser_end,
         });
         
         HttpUtils_BlockingGet({
             url       => "https://sauna-app.klafs.com//Control/PostConfigChange",
             timeout   => 5,
             hash      => $hash,
             method    => "POST",
             header    => $header,  
             data         => $datauser_end,
         });
         $power    = "off";
         readingsBeginUpdate ($hash);
         readingsBulkUpdate( $hash, "power", $power, 1 );
         readingsEndUpdate($hash, 1);
         Log3 ($name, 3, "Sauna off");
       }
    }elsif ( $cmd eq "update" ) {
        Klafs_DoUpdate($hash);
    }elsif ( $cmd eq "ResetLoginFailures" ) {
       readingsBeginUpdate ($hash);
       readingsBulkUpdate( $hash, "LoginFailures", "0", 1 );
       readingsEndUpdate($hash, 1);
       $hash->{Klafs}->{LoginFailures} =0;
    }elsif($cmd eq 'password'){

      my $password        = shift @args;
      print "$name - Passwort1: ".$password."\n";
      my ($res, $error) = defined $password ? $hash->{helper}->{passObj}->setStorePassword($name, $password) : $hash->{helper}->{passObj}->setDeletePassword($name);
   
      if(defined $error && !defined $res)
      {
        Log3($name, 1, "$name - could not update password");
        return "Error while updating the password - $error";
      }else{
        Log3($name, 1, "$name - password successfully saved");
      }
      return;
    }else{
        return "Unknown argument $cmd, choose one of "
        . join( " ",
        map { "$_" . ( $sets{$_} ? ":$sets{$_}" : "" ) } keys %sets );
    }
    return;
}

##############################################################
#
# UPDATE FUNCTIONS
#
##############################################################

sub Klafs_Whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }
sub Klafs_Whowasi() { return (split('::',(caller(2))[3]))[1] || ''; }

sub Klafs_DoUpdate {
    my ($hash) = @_;
    my ($name,$self) = ($hash->{NAME},Klafs_Whoami());
    Log3 ($name, 5, "$name doUpdate() called.");
    
  RemoveInternalTimer($hash);
  if (Klafs_CONNECTED($hash) eq 'disabled') {
    Log3 ($name, 3, "$name - Device is disabled.");
    return;
  }
  
  

  InternalTimer( time() + $hash->{Klafs}->{interval}, $self, $hash, 0 );
        if (time() >= $hash->{Klafs}->{expire} && $hash->{Klafs}->{CONNECTED} ne "disconnected" && $hash->{Klafs}->{CONNECTED} ne "initialized") {
                Log3 ($name, 2, "$name - LOGIN TOKEN MISSING OR EXPIRED - DoUpdate");
                Klafs_CONNECTED($hash,'disconnected',1);

        } elsif ($hash->{Klafs}->{CONNECTED} eq 'connected') {
                Log3 ($name, 4, "$name - Update with device: " . $hash->{Klafs}->{saunaid});
                klafs_getStatus($hash);
        } elsif ($hash->{Klafs}->{CONNECTED} eq 'disconnected' || $hash->{Klafs}->{CONNECTED} eq "initialized") {
          # Das übernimmt eigentlich das notify unten. Hier wird es gebraucht, wenn innerhalb 5 Minuten nach den letzten Reconnect die Verbindung abbricht, dann muss der Login das DoUpdate übernehmen
          # Login wird 5 Minuten nach den letzten Login verhindert vom Modul.
          Log3 ($name, 4, "$name - Reconnect within 5 Minutes");
                Klafs_Auth($hash);
        } elsif ($hash->{Klafs}->{CONNECTED} eq 'authenticated') {
                Log3 ($name, 4, "$name - Update with device: " . $hash->{Klafs}->{saunaid});
                klafs_getStatus($hash);
        }
return;
}

1;

__END__

=pod

=encoding utf8
=item device
=item summary Klafs Sauna control
=item summary_DE Klafs Saunasteuerung
=begin html

<a name="Klafs"></a>
<h3>Klafs Sauna control</h3>
<ul>
   The module receives data and sends commands to the Klafs app.<br>
   In the current version, the sauna can be turned on and off, and the parameters can be set.
   <br>
   <br>
   <b>Requirements</b>
   <ul>
      <br/>
      The SaunaID must be known. This can be found in the URL directly after logging in to the app (http://sauna-app.klafs.com).<br>
      The ID is there with the parameter ?s=xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxxxxxx.<br>
      In addition, the user name and password must be known, as well as the PIN that was defined on the sauna module.
   </ul>
   <br/>
   <a name="Klafsdefine"></a>
   <b>Definition and use</b>
   <ul>
      <br>
      The module is defined without mandatory parameters.<br>
      User name, password, refresh interval, saunaID and pin defined on the sauna module are set as attributes.<br>
   </ul>
   <ul>
      <b>Definition of the module</b>
      <br>
   </ul>
   <ul>
      <br>
      <code>define &lt;name&gt; KLAFS &lt;Intervall&gt;</code><br>
      <code>attr &lt;name&gt; &lt;saunaid&gt; &lt;xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx&gt;</code><br>
      <code>attr &lt;name&gt; &lt;username&gt; &lt;xxxxxx&gt;</code><br>
      <code>attr &lt;name&gt; &lt;pin&gt; &lt;1234&gt;</code><br>
      <code>attr &lt;name&gt; &lt;interval&gt; &lt;60&gt;</code><br>
      <br>
      <code>set &lt;name&gt; &lt;password&gt; &lt;secret&gt;</code><br>
   </ul>
</ul>
<ul>
   <b>Example of a module definition:</b><br>
   <ul>
      <br>
      <code>define mySauna KLAFS</code><br>
      <code>attr mySauna saunaid ab0c123d-ef4g-5h67-8ij9-k0l12mn34op5</code><br>
      <code>attr mySauna username user01</code><br>
      <code>attr mySauna pin 1234</code><br>
      <code>attr mySauna interval 60</code><br>
      <br>
      <code>set mySauna password secret</code><br>
   </ul>
   <a name="KlafsSet"></a>
   <b>Set</b>
   <br>
   <ul>
      <table>
         <colgroup>
            <col width=20%>
            <col width=80%>
         </colgroup>
         <tr>
            <td><b>ResetLoginFailures</b></td>
            <td>If the login fails, the Reading LoginFailures is set to 1. This locks the automatic login from this module.<br>
                Klafs locks the account after 3 failed attempts. So that not automatically 3 wrong logins are made in a row.<br>
                ResetLoginFailures resets the reading to 0. Before this, you should have successfully logged in to the app or sauna-app.klafs.com<br>
                or reset the password. Successful login resets the number of failed attempts in the Klafs cloud.
            </td>
         </tr>
         <tr>
            <td><b>off</b></td>
            <td>Turns off the sauna|sanarium|infrared - without parameters.</td>
         </tr>
         <tr>
            <td><b>on</b></td>
            <td>
            <code>set &lt;name&gt; on</code> without parameters - default sauna 90 degrees<br>
            <code>set &lt;name&gt; on Sauna 90</code> -  3 parameters possible: "Sauna" with temperature [10-100]; Optional time [19:30].<br>
            <code>set &lt;name&gt; on Saunarium 65 5</code> - 4 parameters possible: "Sanarium" with temperature [40-75]; Optional HumidtyLevel [0-10] and time [19:30].<br>
            <code>set &lt;name&gt; on Infrared 30 5</code> - 4 parameters possible: "Infrared" with temperature [20-40] and IR Level [0-10]; Optional time [19:30].<br>
            Infrared works, but is not supported because no test environment is available.
            </td>
         </tr>
         <tr>
            <td><b>Update</b></td>
            <td>Refreshes the readings and performs a login if necessary.</td>
         </tr>
      </table>
   </ul>
   <br>
   <b>Get</b>
   <br>
   <ul>
      <table>
         <colgroup>
            <col width=20%>
            <col width=80%>
         </colgroup>
         <tr>
            <td><b>SaunaID</b></td>
            <td>Reads out the available SaunaIDs.</td>
         </tr>
         <tr>
            <td><b>help</b></td>
            <td>Displays the help for the SET commands.</td>
         </tr>

      </table>
   </ul>
   <br>
   <a name="Klafsreadings"></a>
   <b>Readings</b>
   <ul>
      <br>
      <table>
         <colgroup>
            <col width=35%>
            <col width=65%>
         </colgroup>
         <tr>
            <td><b>Mode</b></td>
            <td> Sauna, Sanarium or Infrared</td>
         </tr>
         <tr>
            <td><b>LoginFailures</b></td>
            <td>Failed login attempts to the app. If the value is set to 1, no login attempts are made by the module. See <code> set &lt;name&gt; ResetLoginFailures</code></td>
         </tr>
         <tr>
            <td><b>Restzeit</b></td>
            <td>Remaining bathing time. Value from bathingHours and bathingMinutes</td>
         </tr>
         <tr>
            <td><b>antiforgery_date</b>        </td>
            <td>Date of the antiforgery cookie. This is generated when the program is switched on.</td>
         </tr>
         <tr>
            <td><b>bathingHours</b>        </td>
            <td>Hour of remaining bath time</td>
         </tr>
         <tr>
            <td><b>bathingMinutes</b></td>
            <td>Minute of remaining bath time</td>
         </tr>
         <tr>
            <td><b>cookieExpire</b></td>
            <td>Logincookie runtime. 2 days</td>
         </tr>
         <tr>
            <td><b>currentHumidity</b></td>
            <td>In sanarium mode. Percentage humidity</td>
         </tr>
         <tr>
            <td><b>currentHumidityStatus</b></td>
            <td>undefined reading</td>
         </tr>
         <tr>
            <td><b>currentTemperature</b></td>
            <td>Temperature in the sauna. 0 When the sauna is off</td>
         </tr>
         <tr>
            <td><b>currentTemperatureStatus</b></td>
            <td>undefined reading</td>
         </tr>
         <tr>
            <td><b>firstname</b></td>
            <td>Defined first name in the app</td>
         </tr>
         <tr>
            <td><b>irSelected</b></td>
            <td>true/false - Currently set operating mode Infrared</td>
         </tr>
         <tr>
            <td><b>isConnected</b></td>
            <td>true/false - Sauna connected to the app</td>
         </tr>
         <tr>
            <td><b>isPoweredOn</b></td>
            <td>true/false - Sauna is on/off</td>
         </tr>
         <tr>
            <td><b>langcloud</b></td>
            <td>Language set in the app</td>
         </tr>
         <tr>
            <td><b>last_errormsg</b></td>
            <td>Last error message. Often that the safety check door contact was not performed.<br>
            Safety check must be performed with the reed contact on the door
            </td>
         </tr>
         <tr>
            <td><b>lastname</b></td>
            <td>Defined last name in the app</td>
         </tr>
         <tr>
            <td><b>mail</b></td>
            <td>Defined mail address in the app</td>
         </tr>
         <tr>
            <td><b>sanariumSelected</b></td>
            <td>true/false - Currently set operating mode Sanarium</td>
         </tr>
         <tr>
            <td><b>saunaId</b></td>
            <td>SaunaID defined as an attribute</td>
         </tr>
         <tr>
            <td><b>saunaSelected</b></td>
            <td>true/false - Currently set operating mode Sauna</td>
         </tr>
         <tr>
            <td><b>selectedHour</b></td>
            <td>Defined switch-on time. Here hour</td>
         </tr>
         <tr>
            <td><b>selectedHumLevel</b></td>
            <td>Defined humidity levels in sanarium operation</td>
         </tr>
         <tr>
            <td><b>selectedIrLevel</b></td>
            <td>Defined intensity in infrared mode</td>
         </tr>
         <tr>
            <td><b>selectedIrTemperature</b></td>
            <td>Defined infrotemperature</td>
         </tr>
         <tr>
            <td><b>selectedMinute</b></td>
            <td>Defined switch-on time. Here minute</td>
         </tr>
         <tr>
            <td><b>selectedSanariumTemperature</b></td>
            <td>Defined sanarium temperature</td>
         </tr>
         <tr>
            <td><b>selectedSaunaTemperature</b></td>
            <td>Defined sauna temperature</td>
         </tr>
         <tr>
            <td><b>showBathingHour</b></td>
            <td>true/false - not further defined. true, if sauna is on.</td>
         </tr>
         <tr>
            <td><b>standbytime</b></td>
            <td>Defined standby time in the app.</td>
         </tr>
         <tr>
            <td><b>power</b></td>
            <td>on/off</td>
         </tr>
         <tr>
            <td><b>statusCode</b></td>
            <td>undefined reading</td>
         </tr>
         <tr>
            <td><b>statusMessage</b></td>
            <td>undefined reading</td>
         </tr>
         <tr>
            <td><b>username</b></td>
            <td>Username defined as an attribute</td>
         </tr>
      </table>
      <br>
   </ul>
</ul>
=end html

=begin html_DE

<a name="Klafs"></a>
<h3>Klafs Saunasteuerung</h3>
<ul>
   Das Modul empf&auml;ngt Daten und sendet Befehle an die Klafs App.<br>
   In der aktuellen Version kann die Sauna an- bzw. ausgeschaltet werden und dabei die Parameter mitgegeben werden.
   <br>
   <br>
   <b>Voraussetzungen</b>
   <ul>
      <br/>
      Die SaunaID muss bekannt sein. Diese findet sich in der URL direkt nach dem Login an der App (http://sauna-app.klafs.com).<br>
      Dort steht die ID mit dem Parameter ?s=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx<br>
      Dar&uuml;berhinaus m&uuml;ssen Benutzername und Passwort bekannt sein sowie die PIN, die am Saunamodul definiert wurde.
   </ul>
   <br/>
   <a name="Klafsdefine"></a>
   <b>Definition und Verwendung</b>
   <ul>
      <br>
      Das Modul wird ohne Pflichtparameter definiert.<br>
      Benutzername, Passwort, Refresh-Intervall, SaunaID, und am Saunamodul definierte Pin werden als Attribute gesetzt.<br>
   </ul>
   <ul>
      <b>Definition des Moduls</b>
      <br>
   </ul>
   <ul>
      <br>
      <code>define &lt;name&gt; KLAFS &lt;Intervall&gt;</code><br>
      <code>attr &lt;name&gt; &lt;saunaid&gt; &lt;xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx&gt;</code><br>
      <code>attr &lt;name&gt; &lt;username&gt; &lt;xxxxxx&gt;</code><br>
      <code>attr &lt;name&gt; &lt;pin&gt; &lt;1234&gt;</code><br>
      <code>attr &lt;name&gt; &lt;interval&gt; &lt;60&gt;</code><br>
      <br>
      <code>set &lt;name&gt; &lt;password&gt; &lt;xxxxxx&gt;</code><br>
   </ul>
</ul>
<ul>
   <b>Beispiel f&uuml;r eine Moduldefinition:</b><br>
   <ul>
      <br>
      <code>define mySauna KLAFS</code><br>
      <code>attr mySauna saunaid ab0c123d-ef4g-5h67-8ij9-k0l12mn34op5</code><br>
      <code>attr mySauna username user01</code><br>
      <code>attr mySauna pin 1234</code><br>
      <code>attr mySauna interval 60</code><br>
      <br>
      <code>set mySauna password geheim</code><br>
   </ul>
   <a name="KlafsSet"></a>
   <b>Set</b>
   <br>
   <ul>
      <table>
         <colgroup>
            <col width=20%>
            <col width=80%>
         </colgroup>
         <tr>
            <td><b>ResetLoginFailures</b></td>
            <td>Bei fehlerhaftem Login wird das Reading LoginFailures auf 1 gesetzt. Damit ist der automatische Login vom diesem Modul gesperrt.<br>
                Klafs sperrt den Account nach 3 Fehlversuchen. Damit nicht automatisch 3 falsche Logins hintereinander gemacht werden.<br>
                ResetLoginFailures setzt das Reading wieder auf 0. Davor sollte man sich erfolgreich an der App bzw. unter sauna-app.klafs.com<br>
                angemeldet bzw. das Passwort zur&uuml;ckgesetzt haben. Erfolgreicher Login resetet die Anzahl der Fehlversuche in der Klafs-Cloud.
            </td>
         </tr>
         <tr>
            <td><b>off</b></td>
            <td>Schaltet die Sauna|Sanarium|Infrared aus - ohne Parameter.</td>
         </tr>
         <tr>
            <td><b>on</b></td>
            <td>
            <code>set &lt;name&gt; on</code> ohne Parameter - Default Sauna 90 Grad<br>
            <code>set &lt;name&gt; on Sauna 90</code> - 3 Parameter m&ouml;glich: "Sauna" mit Temperatur [10-100]; Optional Uhrzeit [19:30]<br>
            <code>set &lt;name&gt; on Saunarium 65 5</code> - 4 Parameter m&ouml;glich: "Sanarium" mit Temperatur [40-75]; Optional HumidtyLevel [0-10] und Uhrzeit [19:30]<br>
            <code>set &lt;name&gt; on Infrared 30 5</code> - 4 Parameter m&ouml;glich: "Infrarot" mit Temperatur [20-40] und IR Level [0-10]; Optional Uhrzeit [19:30]<br>
            Infrarot funktioniert, ist aber nicht supported, da keine Testumgebung verf&uuml;gbar.
            </td>
         </tr>
         <tr>
            <td><b>Update</b></td>
            <td>Refresht die Readings und f&uuml;hrt ggf. ein Login durch.</td>
         </tr>
      </table>
   </ul>
   <br>
   <b>Get</b>
   <br>
   <ul>
      <table>
         <colgroup>
            <col width=20%>
            <col width=80%>
         </colgroup>
         <tr>
            <td><b>SaunaID</b></td>
            <td>Liest die verf&uuml;gbaren SaunaIDs aus.</td>
         </tr>
         <tr>
            <td><b>help</b></td>
            <td>Zeigt die Hilfe f&uuml;r die SET Befehle an.</td>
         </tr>

      </table>
   </ul>
   <br>
   <a name="Klafsreadings"></a>
   <b>Readings</b>
   <ul>
      <br>
      <table>
         <colgroup>
            <col width=35%>
            <col width=65%>
         </colgroup>
         <tr>
            <td><b>Mode</b></td>
            <td> Sauna, Sanarium oder Infrared</td>
         </tr>
         <tr>
            <td><b>LoginFailures</b></td>
            <td>Fehlerhafte Loginversuche an der App. Steht der Wert auf 1, werden vom Modul keine Loginversuche unternommen. Siehe <code> set &lt;name&gt; ResetLoginFailures</code></td>
         </tr>
         <tr>
            <td><b>Restzeit</b></td>
            <td>Restliche Badezeit. Wert aus bathingHours und bathingMinutes</td>
         </tr>
         <tr>
            <td><b>antiforgery_date</b>        </td>
            <td>Datum des Antiforgery Cookies. Dieses wird beim Einschalten erzeugt.</td>
         </tr>
         <tr>
            <td><b>bathingHours</b>        </td>
            <td>Stunde der Restbadezeit</td>
         </tr>
         <tr>
            <td><b>bathingMinutes</b></td>
            <td>Minute der Restbadezeit</td>
         </tr>
         <tr>
            <td><b>cookieExpire</b></td>
            <td>Laufzeit des Logincookies. 2 Tage</td>
         </tr>
         <tr>
            <td><b>currentHumidity</b></td>
            <td>Im Sanariumbetrieb. Prozentuale Luftfeuchtigkeit</td>
         </tr>
         <tr>
            <td><b>currentHumidityStatus</b></td>
            <td>nicht definiertes Reading</td>
         </tr>
         <tr>
            <td><b>currentTemperature</b></td>
            <td>Temperatur in der Sauna. 0 wenn die Sauna aus ist</td>
         </tr>
         <tr>
            <td><b>currentTemperatureStatus</b></td>
            <td>nicht definiertes Reading</td>
         </tr>
         <tr>
            <td><b>firstname</b></td>
            <td>Definierter Vorname in der App</td>
         </tr>
         <tr>
            <td><b>irSelected</b></td>
            <td>true/false - Aktuell eingestellter Betriebsmodus Infrarot</td>
         </tr>
         <tr>
            <td><b>isConnected</b></td>
            <td>true/false - Sauna mit der App verbunden</td>
         </tr>
         <tr>
            <td><b>isPoweredOn</b></td>
            <td>true/false - Sauna ist an/aus</td>
         </tr>
         <tr>
            <td><b>langcloud</b></td>
            <td>Eingestellte Sprache in der App</td>
         </tr>
         <tr>
            <td><b>last_errormsg</b></td>
            <td>Letzte Fehlermeldung. H&auml;ufig, dass die Sicherheits&uuml;berpr&uuml;fung T&uuml;rkontakt nicht durchgef&uuml;hrt wurde.<br>
             Sicherheits&uuml;berpr&uuml;fung muss durchgef&uuml;hrt werden mit dem Reedkontakt an der T&uuml;r.
            </td>
         </tr>
         <tr>
            <td><b>lastname</b></td>
            <td>Definierter Nachname in der App</td>
         </tr>
         <tr>
            <td><b>mail</b></td>
            <td>Definierte Mailadresse in der App</td>
         </tr>
         <tr>
            <td><b>sanariumSelected</b></td>
            <td>true/false - Aktuell eingestellter Betriebsmodus Sanarium</td>
         </tr>
         <tr>
            <td><b>saunaId</b></td>
            <td>SaunaID, die als Attribut definiert wurde</td>
         </tr>
         <tr>
            <td><b>saunaSelected</b></td>
            <td>true/false - Aktuell eingestellter Betriebsmodus Sauna</td>
         </tr>
         <tr>
            <td><b>selectedHour</b></td>
            <td>Definierte Einschaltzeit. Hier Stunde</td>
         </tr>
         <tr>
            <td><b>selectedHumLevel</b></td>
            <td>Definierte Luftfeuchtigkeitslevel im Sanariumbetrieb</td>
         </tr>
         <tr>
            <td><b>selectedIrLevel</b></td>
            <td>Definierte Intensivit&auml;t im Infrarotbetrieb</td>
         </tr>
         <tr>
            <td><b>selectedIrTemperature</b></td>
            <td>Definierte Infrottemperatur</td>
         </tr>
         <tr>
            <td><b>selectedMinute</b></td>
            <td>Definierte Einschaltzeit. Hier Minute</td>
         </tr>
         <tr>
            <td><b>selectedSanariumTemperature</b></td>
            <td>Definierte Sanariumtemperatur</td>
         </tr>
         <tr>
            <td><b>selectedSaunaTemperature</b></td>
            <td>Definierte Saunatemperatur</td>
         </tr>
         <tr>
            <td><b>showBathingHour</b></td>
            <td>true/false - nicht n&auml;her definiert. true, wenn Sauna an ist.</td>
         </tr>
         <tr>
            <td><b>standbytime</b></td>
            <td>Definierte Standbyzeit in der App.</td>
         </tr>
         <tr>
            <td><b>power</b></td>
            <td>on/off</td>
         </tr>
         <tr>
            <td><b>statusCode</b></td>
            <td>nicht definiertes Reading</td>
         </tr>
         <tr>
            <td><b>statusMessage</b></td>
            <td>nicht definiertes Reading</td>
         </tr>
         <tr>
            <td><b>username</b></td>
            <td>Benutzername, der als Attribut definiert wurde</td>
         </tr>
      </table>
      <br>
   </ul>
</ul>
=end html_DE
=cut
