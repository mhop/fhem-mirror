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

=for comment

The interaction with the interface has three layers:
- a FHEM get or set command enqueues a job consisting of one or several
  API calls combined with a callback to be executed on the result
- the queues takes care of logging in, running the API calls and executing the
  callbacks, and logging out again
- the core communication handles the REST API calls to the interface

Commands
========

A get or set command enqueues an API call with callback and then runs the queue.
When the queue has executed the API call, the callback is executed and
handles the reply from the API call according to the specific get or set
command.

Queue
=====

Processing the queue logs into the interface,executes the single API calls
from the get or set commands in the queue, and then logs out from the
interface. A function to reenter queue processing is added to the callback list
for each call.

Communication
=============

The communication with the KLF200 interface is effected through the
IOhomecontrol_Call and IOhomecontrol_Callback functions.

IOhomecontrol_Call makes a REST API call to the interface. In the non-blocking
mode, the call is asynchronous. On completion, IOhomecontrol_Callback is called.
The blocking mode is not used.

Among others, IOhomecontrol_Call is called with the parameters api, action and
params. These can take the following values:

api       action     params       description
------------------------------------------------------------------------------
auth      login                   log into the interface, return token
auth      logout                  log out from the interface
scenes    get                     get the scenes
scenes    run        id           run the scene given by id
settings  getLog

The callbacks parameter of IOhomecontrol_Call is an array of function
references that are called in order with the following parameters:

hash:         the hash reference to the FHEM device
httpParams:   the hash reference used for making the API call
err:          the error message from the call, if any, else undefined
result:       the JSON decoded to a hash reference, undefined in case of error

Note: err is undefined if the call succeeded and a result has been returned
      even if that result contains error messages.

Aforementioned evaluation and execution of callback function references is
done in IOhomecontrol_Callback.



=cut

package main;

use strict;
use warnings;
use HttpUtils;
use JSON;

#use Data::Dumper;

use constant MESSAGES => <<'JSON';
{
	"e401": "Falsches Passwort",
	"e402": "Unbekannter Fehler, Anmeldung fehlgeschlagen",
	"e403": "KLF 200 wird von einem anderen Benutzer konfiguriert. Bitte versuchen Sie die Anmeldung später.",
	"e404": "Fehler bei der Abmeldung!",
	"e405": "Sitzung abgelaufen!",
	"e406": "Ungültiges Zeichen!",
	"e407": "Passwort entspricht nicht den Erfordernissen!",
	"e408": "Login not possible, while reset to factory settings!",
	"e999": "Unbekannter Fehler",
	"e998": "Das Gerät ist ausgelastet!",
	"e997": "Das Gerät befindet sich im Fehlerzustand!",
	"e996": "Ein kritischer Fehler ist aufgetreten. Das Gerät kann nicht mehr im normalen Modus betrieben werden!",
	"e995": "Abrufen der gelöschten Programmliste fehlgeschlagen",
	"e994": "Abrufen der gelöschten Eingangsliste fehlgeschlagen",
	"e993": "Programm \"{{name}}\" wurde aufgrund gelöschter Produkte gelöscht",
	"e992": "Die Verbindung \"{{name}}\" wurde aufgrund gelöschter Produkte oder Programme gelöscht",
	"e991": "Ein GW_ERROR_NTF wurde empfangen.",
	"e449": "Nicht unterstützter Modus",
	"e450": "Wechsel in den Interface-Modus fehlgeschlagen",
	"e451": "Wechsel in den Repeater-Modus fehlgeschlagen",
	"e452": "Wechsel in die Werkseinstellungen fehlgeschlagen",
	"e485": "Modus-Wechsel fehlgeschlagen - allgemeiner Fehler",
	"e101": "Produktempfang fehlgeschlagen",
	"e102": "Produktlöschung fehlgeschlagen",
	"e103": "Empfangvorgang von Produkt(en) fehlgeschlagen",
	"e104": "Kurze Bewegungen/Aufleuchten fehlgeschlagen",
	"e105": "Kopiervorgang von Produkt(en) fehlgeschlagen",
	"e106": "Suchvorgang von Produkt(en) fehlgeschlagen",
	"e107": "Produktumbenennung fehlgeschlagen",
	"e108": "Länge des Namens darf 32 Zeichen nicht überschreiten",
	"e109": "Dieser Name wird bereits verwendet. Bitte wählen Sie einen anderen Namen",
	"e110": "Stornieren des Kopierens von Produkten fehlgeschlagen",
	"e111": "Das Datenfeld darf nicht leer sein",
	"e112": "Kopieren von Produkt(en) fehlgeschlagen!",
	"e113": "Produktsuche fehlgeschlagen!",
	"e114": "Unbekannter Fehler!",
	"e115": "Das Auffinden einer anderen Bedienung im Konfigurationsempfangmodus fehlgeschlagen.",
	"e116": "DTS nicht bereit",
	"e117": "DTS-Fehler. Werkseinstellungen müssen aufgrund eines Systemfehlers der Bedienung hergestellt werden.",
	"e118": "Konfiguration nicht bereit.",
	"e119": "Die Datenübertragung zu oder von der Bedienung unterbrochen.",
	"e120": "Konfigurationsempfang wurde in der Bedienung abgebrochen.",
	"e121": "Unterbrechung.",
	"e201": "Programmumbenennung fehlgeschlagen",
	"e202": "Wechsel in den Flüstermodus fehlgeschlagen",
	"e203": "Programmlöschen fehlgeschlagen",
	"e204": "Programmempfang fehlgeschlagen",
	"e205": "Länge des Namens darf 32 Zeichen nicht überschreiten",
	"e206": "Dieser Name wird bereits verwendet. Bitte wählen Sie einen anderen Namen",
	"e207": "Programmausführung fehlgeschlagen",
	"e208": "Start der Programmerstellung fehlgeschlagen",
	"e209": "Stornieren der Programmerstellung fehlgeschlagen",
	"e210": "Programmerstellung fehlgeschlagen. Versuchen Sie es noch einmal",
	"e211": "Das Datenfeld darf nicht leer sein",
	"e212": "Unbekannte Rückmeldung",
	"e213": "Keine Kommunikation zum Netzknoten",
	"e214": "Manuell betätigt durch einen Benutzer",
	"e215": "Netzknoten durch ein Objekt blockiert",
	"e216": "Netzknoten enthält einen falschen Systemschlüssel",
	"e217": "Netzknoten auf dieser Prioritätsstufe gesperrt",
	"e218": "Netzknoten in einer anderen Position gestoppt als erwartet",
	"e219": "Während der Ausführung des Befehls ist ein Fehler aufgetreten",
	"e220": "Keine Bewegung des Netzknoten-Parameters",
	"e221": "Netzknoten kalibriert die Parameter",
	"e222": "Netzknoten-Energieverbrauch ist zu hoch",
	"e223": "Netzknoten-Energieverbrauch ist zu niedrig",
	"e224": "Türschloss-Fehler. Türverriegelung fehlgeschlagen.",
	"e225": "Zielposition nicht rechtzeitig erreicht",
	"e226": "Netzknoten ist in den Temperaturschutzmodus gegangen",
	"e227": "Netzknoten ohne Funktion",
	"e228": "Filter muss gewartet werden",
	"e229": "Batteriestand ist niedrig",
	"e230": "Netzknoten hat den Zielwert des Befehls modifiziert",
	"e231": "Netzknoten unterstützt nicht den empfangenen Modus",
	"e232": "Netzknoten ist nicht in der Lage, die richtige Richtung durchzuführen",
	"e233": "Verriegelung ist während des Entriegelungbefehls manuell gesperrt",
	"e234": "Verriegelungsfehler",
	"e235": "Netzknoten ist in den automatischen Zyklus-Modus gegangen",
	"e236": "Falsche Last am Netzknoten",
	"e237": "Netzknoten ist nicht in der Lage, den empfangenen Farbcode zu erreichen",
	"e238": "Netzknoten ist nicht in der Lage, die empfangene Zielposition zu erreichen",
	"e239": "io-Protokoll hat einen ungültigen Index empfangen",
	"e240": "Befehl durch einen neuen Befehl außer Kraft gesetzt",
	"e241": "Netzknoten wartet auf Energierückmeldung",
	"e242": "Es können keine weiteren Programme gespeichert werden",
	"e243": "Programmerstellung nicht gestartet",
	"e244": "Keine io-homecontrol® Produkte wurden aktiviert",
	"e301": "Verbindung konnte nicht hinzugefügt werden",
	"e304": "Empfang von Verbindungen fehlgeschlagen",
	"e305": "Speichern von Ausgang fehlgeschlagen",
	"e306": "Löschen von Ausgang fehlgeschlagen",
	"e308": "Löschen von Eingang fehlgeschlagen",
	"e486": "Erstellung eines neuen Systemschlüssels fehlgeschlagen. Versuchen Sie es später noch einmal.",
	"e498": "Nicht alle Netzknoten in der Tabelle haben ihrem Systemschlüssel geändert. Die Schlüssel in diesen Knoten reparieren oder sie aus der Tabelle löschen.",
	"e499": "Nicht alle Produkte wurden gelöscht",
	"e500": "Schlüsselerstellung wird in der Werkseinstellungs- oder Repeater-Modus nicht unterstützt",
	"e501": "Die Verbindung mit einigen Netzknoten in der Tabelle ging verloren. Die Verbindung reparieren oder diese Knoten aus der Tabelle entfernen.           ",
	"log.100": "KLF 200 application started",
	"log.101": "EFM chip start",
	"log.102": "EFM library start",
	"log.103": "Initial web content unpacking",
	"log.104": "STM restore to factory settings request",
	"log.105": "Firmware image - uploading started",
	"log.106": "Firmware image - creating file",
	"log.107": "Firmware image - receiving data",
	"log.108": "Firmware image - validating data",
	"log.109": "Firmware image - uploading finished",
	"log.110": "Reset to factory settings",
	"log.200": "WiFi module initialized",
	"log.201": "WiFi is running as access point ",
	"log.202": "WiFi is running as a client",
	"log.203": "WiFi access point stopped",
	"log.204": "WiFi client stopped",
	"log.205": "Reading WiFi settings",
	"log.206": "Setting WiFi SSID value",
	"log.300": "LAN module initialized",
	"log.301": "LAN module stopped",
	"log.400": "51200 port server started over LAN",
	"log.401": "51200 port server started over WiFi",
	"log.402": "51200 port server over LAN stopped",
	"log.403": "51200 port server over WiFi stopped",
	"log.500": "HTTP server started",
	"log.501": "HTTP server stopped",
	"log.600": "EFM GW_ERROR_NTF error",
	"log.601": "EFM GW_CS_DISCOVER_NODES_NTF error",
	"log.602": "EFM GW_CS_CONTROLLER_COPY_CFM in TCM mode error",
	"log.603": "EFM GW_CS_CONTROLLER_COPY_CFM in RCM mode error",
	"log.604": "EFM GW_INITIALIZE_SCENE_NTF error",
	"log.605": "EFM GW_RECORD_SCENE_NTF error",
	"log.606": "EFM GW_ACTIVATE_SCENE_NTF error",
	"log.607": "EFM GW_CS_KEY_CHANGE_CFM error",
	"log.608": "EFM GW_CS_GENERATE_NEW_KEY_NTF error",
	"log.609": "EFM GW_CS_REPAIR_KEY_NTF error",
	"log.620": "EFM is not responding",
	"log.650": "EFM was externally rebooted",
	"log.651": "EFM was externally reset to factory settings",
	"log.652": "EFM restore to factory settings request",
	"log.700": "FW update start phase",
	"log.701": "FW update validate binary image phase",
	"log.702": "FW update set version phase",
	"log.703": "FW update unpack binary phase",
	"log.704": "FW update move EFM chain phase",
	"log.705": "FW update update EFM phase",
	"log.706": "FW update move STM chain phase",
	"log.707": "FW update schedule STM update phase",
	"log.708": "FW update finished phase",
	"log.709": "FW update unknown phase",
	"log.710": "FW update web content update phase",
	"log.711": "FW update schedule KLF update phase",
	"log.712": "FW update move STM chain back phase",
	"log.713": "FW update webcontent rollback phase",
	"log.714": "FW update move EFM chain back phase",
	"log.715": "FW update EFM rollback phase",
	"log.800": "Token generation failed during login",
	"log.801": "Too many attempts to login with incorrect password",
	"log.802": "Error during logout",
	"log.803": "Unknown request received to login endpoint",
	"e460": "Validierung fehlgeschlagen.",
	"e461": "Die Installation der neuen Softwareversion ist fehlgeschlagen.",
	"e462": "Entpacken fehlgeschlagen.",
	"e463": "Verschiebung der EFM-Datei fehlgeschlagen",
	"e464": "EFM Aktualisierung fehlgeschlagen.",
	"e465": "Verschiebung der STM-Datei fehlgeschlagen.",
	"e466": "STM Aktualisierung fehlgeschlagen.",
	"e467": "Zeitpunkt für die Aktualisierung des KLF 200 fehlgeschlagen.",
	"e468": "WEB Aktualisierung fehlgeschlagen.",
	"e469": "Unbekannter Fehler beim Aktualisieren.",
	"e473": "Passwort muss aus mindestens 8 Zeichen mit Buchstaben und Zahlen bestehen",
	"e474": "Passwortwiederholung falsch",
	"e475": "Veraltete Software",
	"e476": "Keine KLF 200 Software",
	"e477": "Fehler beim Abrufen",
	"e481": "Fehler beim Ermitteln der Softwareversion",
	"e482": "Die Datei ist zu groß. Unbekannt Software",
	"e483": "Aktualisierungs-Start fehlgeschlagen",
	"e488": "Falsches Passwort",
	"e489": "Änderung des Passworts fehlgeschlagen",
	"e490": "Wi-Fi-Datenempfang fehlgeschlagen",
	"e491": "Empfang der Energieverwaltungseinstellungen fehlgeschlagen",
	"e494": "Ungültige Energiekonfiguration ",
	"e492": "Änderung der Energieverwaltungseinstellungen fehlgeschlagen",
	"e493": "Empfang der Systemprotokollmeldungen fehlgeschlagen",
	"e495": "Löschen des Systemprotokolls fehlgeschlagen",
	"e496": "Übertragung fehlgeschlagen",
	"e497": "Das Gerät führt die Formatierung des Flash-Speichers durch. Versuchen Sie es in 10 Minuten erneut.",
	"e430": "Empfang der LAN-Einstellungen fehlgeschlagen",
	"e431": "Aktualisierung der LAN-Einstellung fehlgeschlagen",
	"e432": "Falsche LAN-Einstellungen",
	"e433": "Ungültige IP-Adresse",
	"e434": "Ungültige Subnetzmaske",
	"e436": "Ungültiges Gateway",
	"e435": "LAN-Konfiguration ist nicht übereinstimmend: IP-Adresse und Gateway gehören nicht zum gleichen, durch die Netzwerk-Subnetzmaske definierten Netzwerk ",
	"e437": "IP-Adresse und Standard-Gateway-Adresse müssen unterschiedlich sein",
	"e438": "IP-Adresse und Standard-Gateway können mit der ersten, durch die Netzwerk-Subnetzmaske definierten Netzwerk Adresse nicht identisch sein",
	"e439": "IP-Adresse und Standard-Gateway-Adresse können mit der ersten, durch die Netzwerk-Subnetzmaske definierten Netzwerk Adresse nicht identisch sein",
	"e440": "IP-Adresse ist nicht im gültigen IP-Bereich",
	"e441": "Standard-Gateway ist nicht im gültigen IP-Bereich"
}
JSON
our $messages = decode_json(MESSAGES);

# https://github.com/MiSchroe/klf-200-api/tree/master/src

#####################################
# Initialize, Define, Undefine
#####################################

sub IOhomecontrol_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}       = "IOhomecontrol_Define";
    $hash->{UndefFn}     = "IOhomecontrol_Undef";
    $hash->{GetFn}       = "IOhomecontrol_Get";
    $hash->{SetFn}       = "IOhomecontrol_Set";
    $hash->{NotifyFn}    = "IOhomecontrol_Notify";
    $hash->{parseParams} = 1;

    #$hash->{AttrFn}  = "IOhomecontrol_Attr";
    $hash->{AttrList} = "setCmds logTraffic " . $readingFnAttributes;
}

#####################################

sub IOhomecontrol_getPassword($) {
    my $hash = shift;

    my $pwfile = $hash->{"pwfile"};
    if ( open( my $fh, "<", $pwfile ) ) {
        my @contents = <$fh>;
        close($fh);
        return unless @contents;
        my $password = $contents[0];
        chomp $password;
        return $password;
    }
    else {
        return;
    }
}

sub IOhomecontrol_Define($$) {

    # define <name> IOhomecontrol <model> <host> <pwfile>
    my ( $hash, $argref, undef ) = @_;

    my @def = @{$argref};
    if ( $#def != 4 ) {
        my $msg =
          "wrong syntax: define <name> IOhomecontrol <model> <host> <pwfile>";
        Log 2, $msg;
        return $msg;
    }

    my $name   = $def[0];
    my $model  = $def[2];
    my $host   = $def[3];
    my $pwfile = $def[4];

    if ( $model ne "KLF200" ) {
        my $msg = "unsupported model $model, allowed models: KLF200";
        Log 2, $msg;
        return $msg;
    }

    $hash->{NOTIFYDEV} = "global";

    $hash->{"host"}            = $host;
    $hash->{"pwfile"}          = $pwfile;
    $hash->{fhem}{".password"} = IOhomecontrol_getPassword($hash);
    $hash->{fhem}{".token"}    = undef;
    $hash->{fhem}{".scenes"}   = undef;
    $hash->{fhem}{".running"}  = 0;
    $hash->{fhem}{".log"}      = [];
    IOhomecontrol_updateStateReadings( $hash, "Initialized" );

    return;
}

###################################
sub IOhomecontrol_Notify($$) {

    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};
    my $type = $hash->{TYPE};

    return if ( $dev->{NAME} ne "global" );
    return if ( !grep( m/^INITIALIZED|REREADCFG$/, @{ $dev->{CHANGED} } ) );

    return if ( $attr{$name} && $attr{$name}{disable} );

    Log3 $hash, 5,
"IOhomecontrol $name: FHEM initialization or rereadcfg triggered getting scenes";

    # update readings
    IOhomecontrol_updateLoggedInReadings($hash);
    IOhomecontrol_clearQueue($hash);
    IOhomecontrol_getScenes($hash);

    return undef;
}

#####################################
sub IOhomecontrol_Undef($$) {

    my ( $hash, $arg ) = @_;

    # we should call HttpUtils_Close here
    # for all pending non blocking gets
    # todo!
    return;
}

#####################################
# Core communication with interface
# Knows nothing about business logic
#####################################

sub IOhomecontrol_setDeviceResult($$) {
    my ( $hash, $result ) = @_;

    my $name      = $hash->{NAME};
    my $errorsref = $result->{errors};
    my @errors    = @{$errorsref};
    my $err       = "";
    if (@errors) {
        $err = join( " ", @errors );
        Log3 $hash, 2, "IOhomecontrol $name: device has errors ($err).";
    }
    else {
        $err = "";
    }
    my $r = $result->{result};
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "deviceStatus", $result->{deviceStatus} );
    readingsBulkUpdate( $hash, "deviceErrors", $err );
    readingsBulkUpdate( $hash, "deviceResult", $r );
    readingsEndUpdate( $hash, 1 );

}

sub IOhomecontrol_Call($$$$$) {

    my ( $hash, $api, $action, $params, $callbacks ) = @_;
    my $name  = $hash->{NAME};
    my $host  = $hash->{"host"};
    my $token = $hash->{fhem}{".token"};

    # build url
    my $url = "http://$host/api/v1/$api";

    # build header
    my $header = {
        "Accept"       => "application/json",
        "Content-Type" => "application/json;charset=utf-8",
    };
    if ( defined($token) ) {
        $header->{"Authorization"} = "Bearer $token";
    }

    # build payload
    my $payload = {
        "action" => $action,
        "params" => $params,
    };
    my $json = encode_json $payload;

    # https://wiki.fhem.de/wiki/HttpUtils

    # build HTTP request
    my $httpParams = {
        url         => $url,
        timeout     => 120,       # it takes long to close the shutters
        method      => "POST",
        noshutdown  => 1,
        keepalive   => 0,
        httpversion => "1.1",
        header      => $header,
        data        => $json,
        callback => \&IOhomecontrol_Callback,

        # additional data
        hash      => $hash,
        api       => $api,
        action    => $action,
        params    => $params,
        callbacks => $callbacks,

    };

    Log3 $hash, 5, "IOhomecontrol $name: $url, calling";
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "callState", "calling" );
    readingsBulkUpdate( $hash, "callURL",   $url );
    if ( AttrVal( $name, "logTraffic", 0 ) ) {
        Log3 $hash, 5, "IOhomecontrol $name: request $json";
        readingsBulkUpdate( $hash, "callRequest", $json );
    }
    readingsBulkUpdate( $hash, "callResult", "pending" );
    readingsEndUpdate( $hash, 1 );
    HttpUtils_NonblockingGet($httpParams);
}

sub IOhomecontrol_Callback($$$) {

    my ( $httpParams, $err, $data ) = @_;

    my $hash      = $httpParams->{hash};
    my $name      = $hash->{NAME};
    my $url       = $httpParams->{url};
    my $api       = $httpParams->{api};
    my $json      = $httpParams->{data};
    my $action    = $httpParams->{action};
    my $callbacks = $httpParams->{callbacks};

    $err  = undef if ( $err eq "" );
    $data = undef if ( $data eq "" );
    my $result = undef;

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "callState", "completed" );

    # process error
    if ( defined($err) ) {

        Log3 $hash, 5, "IOhomecontrol $name: $url, call failed";
        readingsBulkUpdate( $hash, "callResult", "error ($err)" );
        if ( AttrVal( $name, "logTraffic", 0 ) ) {
            readingsBulkUpdate( $hash, "callReply", "" );
        }

    }

    # decode data
    if ( defined($data) ) {

        # strip junk from the beginning
        $data =~ s/^\)\]\}\',\n*//;

        if ( AttrVal( $name, "logTraffic", 0 ) ) {
            Log3 $hash, 5, "IOhomecontrol $name: reply $data";
            readingsBulkUpdate( $hash, "callReply", $data );
        }

        eval { $result = decode_json $data };
        if ($@) {
            $err  = "malformed JSON string";
            $data = undef;
            Log3 $hash, 5,
              "IOhomecontrol $name: $url, call returned malformed JSON";
            readingsBulkUpdate( $hash, "callResult", "error ($err)" );
        }
        else {
            Log3 $hash, 5, "IOhomecontrol $name: $url, call succeeded";
            readingsBulkUpdate( $hash, "callResult", "success" );
            IOhomecontrol_setDeviceResult( $hash, $result );
        }
    }

    readingsEndUpdate( $hash, 1 );

    # callbacks
    foreach my $callback ( @{$callbacks} ) {
        $callback->( ( $hash, $httpParams, $err, $result ) );
    }
}

#####################################
# Command Queue
#####################################

sub IOhomecontrol_queueLength($) {
    my ($hash) = @_;
    return scalar @{ $hash->{fhem}{".queue"} };
}

sub IOhomecontrol_loggedIn($) {
    my ($hash) = @_;
    return defined( $hash->{fhem}{".token"} );
}

sub IOhomecontrol_updateStateReadings($$) {
    my ( $hash, $msg ) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", $msg );
    readingsEndUpdate( $hash, 1 );
}

sub IOhomecontrol_updateQueueReadings($) {
    my ($hash) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "queueLength",
        IOhomecontrol_queueLength($hash) );
    readingsEndUpdate( $hash, 1 );
}

sub IOhomecontrol_updateLoggedInReadings($) {
    my ($hash) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "loggedIn",
        IOhomecontrol_loggedIn($hash) ? "yes" : "no" );
    readingsEndUpdate( $hash, 1 );
}

sub IOhomecontrol_enqueue($$$$$) {
    my ( $hash, $api, $action, $params, $callbacks ) = @_;

    # if a single function reference is passed, put it in an array
    # this is for the developer's convenience
    if ( ref($callbacks) ne 'ARRAY' ) {
        my @callbacks = ($callbacks);
        $callbacks = \@callbacks;
    }
    my $name = $hash->{NAME};
    my %job  = (
        api       => $api,
        action    => $action,
        params    => $params,
        callbacks => $callbacks
    );
    push @{ $hash->{fhem}{".queue"} }, \%job;
    Log3 $hash, 5,
      "IOhomecontrol $name: job enqueued, API $api, action $action";
    IOhomecontrol_updateQueueReadings($hash);
}

sub IOhomecontrol_dequeue($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $jobref = shift @{ $hash->{fhem}{".queue"} };
    my $api    = $jobref->{api};
    my $action = $jobref->{action};
    Log3 $hash, 5,
      "IOhomecontrol $name: job dequeued, API $api, action $action";
    IOhomecontrol_updateQueueReadings($hash);
    return $jobref;
}

sub IOhomecontrol_clearQueue($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my @queue  = ();
    $hash->{fhem}{".queue"} = \@queue;
    Log3 $hash, 5, "IOhomecontrol $name: queue cleared";
    IOhomecontrol_updateQueueReadings($hash);
}

sub IOhomecontrol_runJob($$$) {
    my ( $hash, $jobref, $callback ) = @_;
    my $name      = $hash->{NAME};
    my $callbacks = $jobref->{callbacks};
    push @{$callbacks}, $callback;
    IOhomecontrol_Call( $hash, $jobref->{api}, $jobref->{action},
        $jobref->{params}, $callbacks );
}

sub IOhomecontrol_Login($$) {
    my ( $hash, $callback ) = @_;
    my $name = $hash->{NAME};
    Log3 $hash, 5, "IOhomecontrol $name: Logging in...";
    my $password  = $hash->{fhem}{".password"};
    my $params    = { "password" => $password };
    my @callbacks = ( \&IOhomecontrol_LoginCallback, $callback );
    IOhomecontrol_Call( $hash, "auth", "login", $params, \@callbacks );
}

sub IOhomecontrol_LoginCallback($$$$) {
    my ( $hash, $httpParams, $err, $result ) = @_;
    my $name = $hash->{NAME};
    if ( defined($err) ) {
        Log3 $hash, 2, "IOhomecontrol $name: Login failed ($err)";
    }
    else {
        my $token = $result->{token};
        if ( defined($token) ) {
            Log3 $hash, 5, "IOhomecontrol $name: Login successful";
            $hash->{fhem}{".token"} = $token;
        }
        else {
            Log3 $hash, 2,
              "IOhomecontrol $name: Login failed (no token received)";
            IOhomecontrol_clearQueue($hash);    # forget
            Log3 $hash, 2, "IOhomecontrol $name: pending commands cancelled";
        }
    }
    IOhomecontrol_updateLoggedInReadings($hash);
}

sub IOhomecontrol_Logout($$) {
    my ( $hash, $callback ) = @_;
    my $name = $hash->{NAME};
    Log3 $hash, 5, "IOhomecontrol $name: Logging out...";
    my $params = {};
    my @callbacks = ( \&IOhomecontrol_LogoutCallback, $callback );
    IOhomecontrol_Call( $hash, "auth", "logout", $params, \@callbacks );
}

sub IOhomecontrol_LogoutCallback($$$$) {
    my ( $hash, $httpParams, $err, $result ) = @_;
    my $name = $hash->{NAME};
    if ( defined($err) ) {
        Log3 $hash, 2, "IOhomecontrol $name: Logout failed ($err)";
    }
    else {
        $hash->{fhem}{".token"} = undef;
    }
    IOhomecontrol_updateLoggedInReadings($hash);
}

sub IOhomecontrol_runQueue($) {
    my ($hash) = @_;
    return if ( $hash->{fhem}{".running"} );
    $hash->{fhem}{".running"} = 1;
    IOhomecontrol_updateStateReadings( $hash, "running" );
    IOhomecontrol_processQueue($hash);
}

sub IOhomecontrol_processQueue($) {
    my ($hash) = @_;

    if ( IOhomecontrol_queueLength($hash) > 0 ) {
        if ( IOhomecontrol_loggedIn($hash) ) {

            # already logged in => run jon
            IOhomecontrol_runJob(
                $hash,
                IOhomecontrol_dequeue($hash),
                \&IOhomecontrol_processQueue
            );
        }
        else {
            # not yet logged on => login
            IOhomecontrol_Login( $hash, \&IOhomecontrol_processQueue );
        }
    }
    else {
        # queue empty

        if ( IOhomecontrol_loggedIn($hash) ) {

            # still logged in => logout
            IOhomecontrol_Logout( $hash, \&IOhomecontrol_processQueue );
        }
        else {
            # processing ended => idle
            $hash->{fhem}{".running"} = 0;
            IOhomecontrol_updateStateReadings( $hash, "idle" );
        }

    }
}

#####################################
# Get, Set
#####################################

### scenes

sub IOhomecontrol_makeScenes($$) {
    my ( $hash, $data ) = @_;
    my $sc = {};
    if ( defined($data) ) {

        #Debug "data: " . Dumper $data;
        foreach my $item ( @{$data} ) {

            #Debug "data item: " . Dumper $item;
            my $name = $item->{name};
            my $id   = $item->{id};

            #Debug "$id: $name";
            $sc->{$id} = $name;
        }
        my $sns = "";
        foreach my $id ( sort keys %{$sc} ) {
            $sns .= "," if ($sns);
            $sns .= sprintf( "%d: %s", $id, $sc->{$id} );
        }
        readingsSingleUpdate( $hash, "scenes", $sns, 1 );
    }
    $hash->{fhem}{".scenes"} = $sc;
    return $sc;    # a hash reference to id => name
}

sub IOhomecontrol_getScenes($) {
    my $hash = shift;
    IOhomecontrol_enqueue( $hash, "scenes", "get", {},
        \&IOhomecontrol_getScenesCallback );
    IOhomecontrol_runQueue($hash);
}

sub IOhomecontrol_getScenesCallback($$$$) {
    my ( $hash, $httpParams, $err, $result ) = @_;
    my $name = $hash->{NAME};
    if ( defined($err) ) {
        Log3 $hash, 2, "IOhomecontrol $name: getting scenes failed ($err)";
    }
    else {
        $hash->{fhem}{".scenes"} =
          IOhomecontrol_makeScenes( $hash, $result->{data} );
    }
}

sub IOhomecontrol_runSceneById($$$;$) {
    my ( $hash, $id, $sn, $callback ) = @_;
    my $name = $hash->{NAME};
    Log3 $hash, 5, "IOhomecontrol $name: running scene id $id, name $sn";
    my @callbacks= (\&IOhomecontrol_runSceneByIdCallback);
    push @callbacks, $callback if(defined($callback));
    IOhomecontrol_enqueue(
        $hash, "scenes", "run",
        { id => $id },
        \@callbacks
    );
    IOhomecontrol_runQueue($hash);
}

sub IOhomecontrol_runSceneByIdCallback($$$$) {
    my ( $hash, $httpParams, $err, $result ) = @_;
    my $name = $hash->{NAME};
    my $id= $httpParams->{params}{id};
    my $sn= $hash->{fhem}{".scenes"}->{$id};
    if ( defined($err) ) {
        Log3 $hash, 2, "IOhomecontrol $name: running scene id $id, name $sn, failed ($err)";
    }
    else {
        Log3 $hash, 5, "IOhomecontrol $name: running scene id $id, name $sn, completed";
        my $id= $httpParams->{params}{id};
        readingsSingleUpdate( $hash, "lastScene", $id, 1 );
    }
}

### log

sub IOhomecontrol_logLength($) {
    my ($hash) = @_;
    return scalar @{ $hash->{fhem}{".log"} };
}

sub IOhomecontrol_updateLogReadings($) {
    my ($hash) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "logLength", IOhomecontrol_logLength($hash) );
    readingsEndUpdate( $hash, 1 );
}

sub IOhomecontrol_getLog($) {
    my $hash = shift;
    IOhomecontrol_enqueue( $hash, "settings", "getLog", {},
        \&IOhomecontrol_getLogCallback );
    IOhomecontrol_runQueue($hash);
}

sub IOhomecontrol_logEntry($) {
    my ($e) = @_;    # log entry as hash reference
    return sprintf( "%s: %s, %s %s",
        $e->{time}, $e->{type}, $messages->{ $e->{text} },
        $e->{opt} );
}

sub IOhomecontrol_getLogCallback($$$$) {
    my ( $hash, $httpParams, $err, $result ) = @_;
    my $name = $hash->{NAME};
    if ( defined($err) ) {
        Log3 $hash, 2, "IOhomecontrol $name: getting log failed ($err)";
    }
    else {
        $hash->{fhem}{".log"} = $result->{data};
    }
}

#####################################
sub IOhomecontrol_Get($@) {
    my ( $hash, $argsref, undef ) = @_;

    my @a = @{$argsref};
    return "get needs at least one parameter" if ( @a < 2 );

    my $name = $a[0];
    my $cmd  = $a[1];
    my $arg  = ( $a[2] ? $a[2] : "" );
    my @args = @a;
    shift @args;
    shift @args;

    my $answer = "";

    if ( $cmd eq "sceneList" ) {
        my $sc = $hash->{fhem}{".scenes"};
        if ( defined($sc) ) {
            foreach my $id ( sort keys %{$sc} ) {
                $answer .= "\n" if ($answer);
                $answer .= sprintf( "%2d: %s", $id, $sc->{$id} );
            }
        }
    }
    elsif ( $cmd eq "scenes" ) {
        IOhomecontrol_getScenes($hash);
    }
    elsif ( $cmd eq "log" ) {
        IOhomecontrol_getLog($hash);
    }
    elsif ( $cmd eq "showLog" ) {
        my @log = @{ $hash->{fhem}{".log"} };
        my $log = join( "\n", map( IOhomecontrol_logEntry($_), @log ) );
        return $log;
    }
    elsif ( $cmd eq "password" ) {
        $hash->{fhem}{".password"} = IOhomecontrol_getPassword($hash);
        return "password read from file " . $hash->{fhem}{".pwfile"};
    }
    else {
        return
"Unknown argument $cmd, choose one of scenes:noArg sceneList:noArg log:noArg showLog:noArg password:noArg";
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
    my $hash = shift;
    my $name = $hash->{NAME};

    my $attr = AttrVal( $name, "setCmds", "" );
    my ( undef, $setCmds ) = parseParams( $attr, "," );
    return $setCmds;
}

sub IOhomecontrol_setScene($$;$) {

    my ( $hash, $id, $callback ) = @_;

    my $sc = $hash->{fhem}{".scenes"};
    return "No scenes available." unless ( defined($sc) );
    if ( $id !~ /^\d+$/ ) {
        my %cs = reverse %{$sc};
        $id = $cs{$id};
    }
    my $sn = $sc->{$id};
    if ( defined($sn) ) {
        IOhomecontrol_runSceneById( $hash, $id, $sn, $callback );
    }
    else {
        return "No such scene $id";
    }
}

sub IOhomecontrol_Set($$$) {
    my ( $hash, $argsref, undef ) = @_;

    my @a = @{$argsref};
    return "set needs at least one parameter" if ( @a < 2 );

    my $name = shift @a;
    my $cmd  = shift @a;

    my $setCmds = IOhomecontrol_getSetCmds($hash);
    my $usage   = "Unknown argument $cmd, choose one of scene "
      . join( " ", ( keys %{$setCmds} ) );
    if ( exists( $setCmds->{$cmd} ) ) {
        readingsSingleUpdate( $hash, "state", $cmd, 1 );
        my $subst = $setCmds->{$cmd};
        Log3 $hash, 5,
          "IOhomecontrol $name: substitute set command $cmd by $subst";
        ( $argsref, undef ) = parseParams($subst);
        @a   = @{$argsref};
        $cmd = shift @a;
    }

    if ( $cmd eq "scene" ) {
        if ($#a) {
            return "Command scene needs exactly one argument.";
        }
        else {
            my $id = $a[0];
            IOhomecontrol_setScene( $hash, $id );
        }
    }
    else {
        return $usage;
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

    Defines an IOhomecontrol interface device (gateway) to communicate with
    IOhomecontrol devices.
    <code>&lt;model&gt;</code> is a placeholder for future amendments.
    Currently only the Velux Integra KLF200 Interface model <code>KLF200</code> is supported
    as a gateway.
    <code>&lt;host&gt;</code> is the IP address or hostname of the IOhomecontrol
    interface device (gateway).
    <code>&lt;pwfile&gt;</code> is a file that contains the password to log into the device.<br><br>

    Example:
    <ul>
      <code>define myKLF200 IOhomecontrol KLF200 192.168.0.91 /opt/fhem/etc/veluxpw.txt</code><br>
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
    Retrieves the ids and names of the scenes from the device. This is done
    automatically after FHEM is initialized. So you should need this only
    if you have altered scenes in the interface device.
    <br><br>
    Example:
    <ul>
      <code>get myKLF200 scenes</code><br>
    </ul>
    <br><br>
    <code>get &lt;name&gt; sceneList</code>
    <br><br>
    Displays the scenes.
    <br><br>
    <code>get &lt;name&gt; log</code>
    <br><br>
    Retrieves the event log from the device.
    <br><br>
    <code>get &lt;name&gt; showLog</code>
    <br><br>
    Displays the event log.
    <br><br>
    <code>get &lt;name&gt; password</code>
    <br><br>
    Reads the password from the password file &lt;pwfile&gt;. This is done
    automatically after FHEM is initialized. So you should need this only
    if you have altered the password in the file.
  </ul>
  <br><br>


  <a name="IOhomecontrolattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>setCmds: a comma-separated list of set command definitions.
    Every definition is of the form <code>&lt;shorthand&gt;=&lt;command&gt;</code>.
    This defines a new single-word command <code>&lt;shorthand&gt</code> as a substitute for <code>&lt;command&gt;</code>.<br>
    Example: <code>attr velux setCmds evening=scene "close all",morning=scene "open all"</code><br>
    <br></li>
    <li>logTraffic: if set to a nonzero value, request and reply JSON strings
    are logged with log level 5 and stored in the <code>callRequest</code> and
    <code>callReply</code> readings. Use with caution because the password is
    transmitted in plain text in the authentication request.
    <br><br></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>


</ul>

=end html
=cut
