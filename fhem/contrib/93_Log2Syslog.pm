######################################################################################################################
# $Id: 93_Log2Syslog.pm 16688 2018-05-04 20:09:12Z DS_Starter $
######################################################################################################################
#       93_Log2Syslog.pm
#
#       (c) 2017-2018 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       The module is based on idea and input from betateilchen 92_rsyslog.pm
#
#       Implements the Syslog Protocol of RFC 5424  https://tools.ietf.org/html/rfc5424
#       and RFC 3164 https://tools.ietf.org/html/rfc3164 and
#       TLS Transport according to RFC5425 https://tools.ietf.org/pdf/rfc5425.pdf as well
#
######################################################################################################################
#  Versions History:
#
# 4.7.0      10.08.2018       Parser for TPLink
# 4.6.1      10.08.2018       some perl warnings, changed IETF Parser
# 4.6.0      08.08.2018       set sendTestMessage added, Attribute "contDelimiter", "sendSeverity"
# 4.5.1      07.08.2018       BSD Regex changed, setpayload of BSD changed 
# 4.5.0      06.08.2018       Regex capture groups used in parsePayload to set variables, parsing of BSD changed,
#                             Attribute "makeMsgEvent" added
# 4.4.0      04.08.2018       Attribute "outputFields" added
# 4.3.0      03.08.2018       Attribute "parseFn" added
# 4.2.0      03.08.2018       evaluate sender peer ip-address/hostname, use it as reading in event generation
# 4.1.0      02.08.2018       state event generation changed
# 4.0.0      30.07.2018       server mode (Collector)
# 3.2.1      04.05.2018       fix compatibility with newer IO::Socket::SSL on debian 9, attr ssldebug for
#                             debugging SSL messages
# 3.2.0      22.11.2017       add NOTIFYDEV if possible
# 3.1.0      28.08.2017       get-function added, commandref revised, $readingFnAttributes deleted
# 3.0.0      27.08.2017       change attr type to protocol, ready to check in
# 2.6.0      26.08.2017       more than one Log2Syslog device can be created
# 2.5.2      26.08.2018       fix in splitting timestamp, change Log2Syslog_trate using internaltimer with attr 
#                             rateCalcRerun, function Log2Syslog_closesock
# 2.5.1      24.08.2017       some fixes
# 2.5.0      23.08.2017       TLS encryption available, new readings, $readingFnAttributes
# 2.4.1      21.08.2017       changes in sub Log2Syslog_charfilter, change PROCID to $hash->{SEQNO}
#                             switch to non-blocking in subs event/Log2Syslog_fhemlog
# 2.4.0      20.08.2017       new sub Log2Syslog_Log3slog for entries in local fhemlog only -> verbose support
# 2.3.1      19.08.2017       commandref revised
# 2.3.0      18.08.2017       new parameter "ident" in DEF, sub setidex, Log2Syslog_charfilter
# 2.2.0      17.08.2017       set BSD data length, set only acceptable characters (USASCII) in payload
#                             commandref revised
# 2.1.0      17.08.2017       sub Log2Syslog_opensock created
# 2.0.0      16.08.2017       create syslog without SYS::SYSLOG
# 1.1.1      13.08.2017       registrate Log2Syslog_fhemlog to %loginform in case of sending fhem-log
#                             attribute timeout, commandref revised
# 1.1.0      26.07.2017       add regex search to sub Log2Syslog_fhemlog
# 1.0.0      25.07.2017       initial version

package main;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Encode qw(encode_utf8);
eval "use IO::Socket::INET;1" or my $MissModulSocket = "IO::Socket::INET";
eval "use Net::Domain qw(hostname hostfqdn hostdomain domainname);1"  or my $MissModulNDom = "Net::Domain";

###############################################################################
# Forward declarations
#
sub Log2Syslog_Log3slog($$$);

my $Log2SyslogVn = "4.7.0";

# Mappinghash BSD-Formatierung Monat
my %Log2Syslog_BSDMonth = (
  "01" => "Jan",
  "02" => "Feb",
  "03" => "Mar",
  "04" => "Apr",
  "05" => "May",
  "06" => "Jun",
  "07" => "Jul",
  "08" => "Aug",
  "09" => "Sep",
  "10" => "Oct",
  "11" => "Nov",
  "12" => "Dec",
  "Jan" => "01",
  "Feb" => "02",
  "Mar" => "03",
  "Apr" => "04",
  "May" => "05",
  "Jun" => "06",
  "Jul" => "07",
  "Aug" => "08",
  "Sep" => "09",
  "Oct" => "10",
  "Nov" => "11",
  "Dec" => "12"
);

# Mappinghash Severity
my %Log2Syslog_Severity = (
  "0" => "Emergency",
  "1" => "Alert",
  "2" => "Critical",
  "3" => "Error",
  "4" => "Warning",
  "5" => "Notice",
  "6" => "Informational",
  "7" => "Debug",
  "Emergency"     => "0",
  "Alert"         => "1",
  "Critical"      => "2",
  "Error"         => "3",
  "Warning"       => "4",
  "Notice"        => "5",
  "Informational" => "6",
  "Debug"         => "7"
);

# Mappinghash Facility
my %Log2Syslog_Facility = (
  "0"  => "kernel",
  "1"  => "user",
  "2"  => "mail",
  "3"  => "system",
  "4"  => "security",
  "5"  => "syslog",
  "6"  => "printer",
  "7"  => "network",
  "8"  => "UUCP",
  "9"  => "clock",
  "10" => "security",
  "11" => "FTP",
  "12" => "NTP",
  "13" => "log_audit",
  "14" => "log_alert",
  "15" => "clock",
  "16" => "local0",
  "17" => "local1",
  "18" => "local2",
  "19" => "local3",
  "20" => "local4",
  "21" => "local5",
  "22" => "local6",
  "23" => "local7"
  );

# Längenvorgaben nach RFC3164
my %RFC3164len = ("TAG"  => 32,           # max. Länge TAG-Feld
                  "DL"   => 1024          # max. Lange Message insgesamt
   			     );
				 
# Längenvorgaben nach RFC5425
my %RFC5425len = ("DL"  => 8192,          # max. Lange Message insgesamt mit TLS
                  "HST" => 255,           # max. Länge Hostname
                  "ID"  => 48,            # max. Länge APP-NAME bzw. Ident
                  "PID" => 128,           # max. Länge Proc-ID
                  "MID" => 32             # max. Länge MSGID
                  );

###############################################################################
sub Log2Syslog_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "Log2Syslog_Define";
  $hash->{UndefFn}  = "Log2Syslog_Undef";
  $hash->{DeleteFn} = "Log2Syslog_Delete";
  $hash->{SetFn}    = "Log2Syslog_Set";
  $hash->{GetFn}    = "Log2Syslog_Get";
  $hash->{AttrFn}   = "Log2Syslog_Attr";
  $hash->{NotifyFn} = "Log2Syslog_eventlog";
  $hash->{ReadFn}   = "Log2Syslog_Read";

  $hash->{AttrList} = "addStateEvent:1,0 ".
                      "disable:1,0,maintenance ".
                      "addTimestamp:0,1 ".
                      "contDelimiter ".
					  "logFormat:BSD,IETF ".
                      "makeMsgEvent:no,intern,reading ".
                      "outputFields:sortable-strict,PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT ".
                      "parseProfile:BSD,IETF,TPLink-SG2424,raw,ParseFn ".
                      "parseFn:textField-long ".
                      "sendSeverity:multiple-strict,Emergency,Alert,Critical,Error,Warning,Notice,Informational,Debug ".
                      "ssldebug:0,1,2,3 ".
					  "TLS:1,0 ".
					  "timeout ".
	                  "protocol:UDP,TCP ".
	                  "port ".
					  "rateCalcRerun ".
                      $readingFnAttributes
                      ;
return undef;   
}

###############################################################################
sub Log2Syslog_Define($@) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  
  return "Error: Perl module ".$MissModulSocket." is missing. Install it on Debian with: sudo apt-get install libio-socket-multicast-perl" if($MissModulSocket);
  return "Error: Perl module ".$MissModulNDom." is missing." if($MissModulNDom);
  
  # Example Sender:        define  splunklog Log2Syslog  splunk.myds.me ident:Prod  event:.* fhem:.*
  # Example Collector:     define  SyslogServer Log2Syslog
  
  delete($hash->{HELPER}{EVNTLOG});
  delete($hash->{HELPER}{FHEMLOG});
  delete($hash->{HELPER}{IDENT});
  
  $hash->{MYHOST} = hostfqdn();                            # FQDN eigener Host
  
  if(int(@a)-3 < 0){
      # Einrichtung Servermode (Collector)
      Log3 ($name, 3, "Log2Syslog $name - entering Syslog servermode ...");
      $hash->{MODEL} = "Collector";
      Log2Syslog_initServer("$name,global");
  } else {
      # Sendermode
      $hash->{MODEL} = "Sender";
      Log2Syslog_setidrex($hash,$a[3]) if($a[3]);
      Log2Syslog_setidrex($hash,$a[4]) if($a[4]);
      Log2Syslog_setidrex($hash,$a[5]) if($a[5]);
      
      eval { "Hallo" =~ m/^$hash->{HELPER}{EVNTLOG}$/ } if($hash->{HELPER}{EVNTLOG});
      return "Bad regexp: $@" if($@);
      eval { "Hallo" =~ m/^$hash->{HELPER}{FHEMLOG}$/ } if($hash->{HELPER}{FHEMLOG});
      return "Bad regexp: $@" if($@);
  
      return "Bad regexp: starting with *" 
         if((defined($hash->{HELPER}{EVNTLOG}) && $hash->{HELPER}{EVNTLOG} =~ m/^\*/) || (defined($hash->{HELPER}{FHEMLOG}) && $hash->{HELPER}{FHEMLOG} =~ m/^\*/));
  
      # nur Events dieser Devices an NotifyFn weiterleiten, NOTIFYDEV wird gesetzt wenn möglich
      notifyRegexpChanged($hash, $hash->{HELPER}{EVNTLOG}) if($hash->{HELPER}{EVNTLOG});
		
      $hash->{PEERHOST}         = $a[2];                    # Destination Host (Syslog Server)
  }

  $hash->{SEQNO}            = 1;                            # PROCID in IETF, wird kontinuierlich hochgezählt
  $hash->{VERSION}          = $Log2SyslogVn;
  $logInform{$hash->{NAME}} = "Log2Syslog_fhemlog";         # Funktion die in hash %loginform für $name eingetragen wird
  $hash->{HELPER}{SSLVER}   = "n.a.";                       # Initialisierung
  $hash->{HELPER}{SSLALGO}  = "n.a.";                       # Initialisierung
  $hash->{HELPER}{LTIME}    = time();                       # Init Timestmp f. Ratenbestimmung
  $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};               # Init Sequenznummer f. Ratenbestimmung
  $hash->{HELPER}{OLDSTATE} = "initialized";
  
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "SSL_Version", "n.a.");
  readingsBulkUpdate($hash, "SSL_Algorithm", "n.a.");
  readingsBulkUpdate($hash, "Transfered_logs_per_minute", 0);
  readingsBulkUpdate($hash, "state", "initialized") if($hash->{MODEL}=~/Sender/);
  readingsEndUpdate($hash,1);
  
  Log2Syslog_trate($hash);                                 # regelm. Berechnung Transfer Rate starten 
      
return undef;
}

#################################################################################################
#                       Syslog Collector (Server-Mode) initialisieren
#                       (im Collector Model)
#################################################################################################
sub Log2Syslog_initServer($) {
  my ($a) = @_;
  my ($name,$global) = split(",",$a);
  my $hash     = $defs{$name};

  RemoveInternalTimer($hash, "Log2Syslog_initServer");
  return if(IsDisabled($name));
  
  if($init_done != 1) {
      InternalTimer(gettimeofday()+5, "Log2Syslog_initServer", "$name,$global", 0);
	  return;
  }
  # Inititialisierung FHEM ist fertig -> Attribute geladen
  my $port     = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 1514);
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  my $lh = $global ? ($global eq "global"? undef : $global) : ($hash->{IPV6} ? "::1" : "127.0.0.1");
  
  Log3 $hash, 3, "Log2Syslog $name - Opening socket ...";
  
  $hash->{SERVERSOCKET} = IO::Socket::INET->new(
    Domain    => ($hash->{IPV6} ? AF_INET6() : AF_UNSPEC), # Linux bug
    LocalHost => $lh,
    Proto     => $protocol,
    LocalPort => $port, 
    ReuseAddr => 1
  ); 
  if(!$hash->{SERVERSOCKET}) {
      my $err = "Can't open Syslog Collector at $port: $!";
      Log3 ($hash, 1, "Log2Syslog $name - $err");
      readingsSingleUpdate ($hash, 'state', $err, 1);
      return;      
  }
  
  $hash->{FD}               = $hash->{SERVERSOCKET}->fileno();
  $hash->{PORT}             = $hash->{SERVERSOCKET}->sockport();
  $hash->{PROTOCOL}         = $protocol;
  $hash->{SEQNO}            = 1;                            # PROCID wird kontinuierlich pro empfangenen Datensatz hochgezählt
  $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};               # Init Sequenznummer f. Ratenbestimmung
  $hash->{INTERFACE}        = $lh?$lh:"global";
  
  Log3 ($hash, 3, "Log2Syslog $name - port $hash->{PORT}/$protocol opened for Syslog Collector on interface \"$hash->{INTERFACE}\"");
  readingsSingleUpdate ($hash, "state", "initialized", 1);
  delete($readyfnlist{"$name.$port"});
  $selectlist{"$name.$port"} = $hash;

return;
}

#################################################################################################
#                       Syslog Collector Daten empfangen
#                       (im Collector Model)
#################################################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub Log2Syslog_Read($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $socket = $hash->{SERVERSOCKET};
  my $st     = ReadingsVal($name,"state","active");
  my $pp     = AttrVal($name, "parseProfile", "IETF");
  my $mevt   = AttrVal($name, "makeMsgEvent", "intern");          # wie soll Reading/Eventerstellt werden
  my ($err,$data,$ts,$phost,$pl);
  
  return if(IsDisabled($name) || $hash->{MODEL} !~ /Collector/);

  if($pp =~ /BSD/) {
      # BSD-Format  
      unless($socket->recv($data, $RFC3164len{DL})) {
          # ungültige BSD-Payload
          return if(length($data) == 0);
          Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - received ".length($data)." bytes, but a BSD-message has to be 1024 bytes or less.");
          Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Seq \"$hash->{SEQNO}\" invalid data: $data"); 
          $st = "receive error - see logfile";          
      } else {
          # parse Payload  
          ($err,$phost,$ts,$pl) = Log2Syslog_parsePayload($hash,$data);      
          $hash->{SEQNO}++;
          if($err) {
              $st = "parse error - see logfile";
          } else {
              $st = "active";
              if($mevt =~ /intern/) {
                  # kein Reading, nur Event
                  $pl = "$phost: $pl";
                  Log2Syslog_Trigger($hash,$ts,$pl);
              } elsif ($mevt =~ /reading/) {
                  # Reading, Event abhängig von event-on-.*
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 1);
              } else {
                  # Reading ohne Event
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 0);
              }
          }
      }
  
  } elsif($pp =~ /IETF/) {
      # IETF-Format
      unless($socket->recv($data, $RFC5425len{DL})) {
          # ungültige IETF-Payload
          return if(length($data) == 0);
          Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - received ".length($data)." bytes, but a IETF-message has to be 8192 bytes or less.");
          Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Seq \"$hash->{SEQNO}\" invalid data: $data");
          $st = "receive error - see logfile";            
      } else {
          # parse Payload  
          ($err,$phost,$ts,$pl) = Log2Syslog_parsePayload($hash,$data);      
          $hash->{SEQNO}++;
          if($err) {
              $st = "parse error - see logfile";
          } else {
              $st = "active";
              if($mevt =~ /intern/) {
                  # kein Reading, nur Event
                  $pl = "$phost: $pl";
                  Log2Syslog_Trigger($hash,$ts,$pl);
              } elsif ($mevt =~ /reading/) {
                  # Reading, Event abhängig von event-on-.*
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 1);
              } else {
                  # Reading ohne Event
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 0);
              }
          }
      }  
  } else {
      # raw oder User eigenes Format
      $socket->recv($data, 8192);
      ($err,$phost,$ts,$pl) = Log2Syslog_parsePayload($hash,$data);      
      $hash->{SEQNO}++;
      if($err) {
          $st = "parse error - see logfile";
      } else {
          $st = "active";
              if($mevt =~ /intern/) {
                  # kein Reading, nur Event
                  $pl = "$phost: $pl";
                  Log2Syslog_Trigger($hash,$ts,$pl);
              } elsif ($mevt =~ /reading/) {
                  # Reading, Event abhängig von event-on-.*
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 1);
              } else {
                  # Reading ohne Event
                  readingsSingleUpdate($hash, "MSG_$phost", $pl, 0);
              }
      }      
  
  }
  # readingsSingleUpdate($hash, "state", $st, 1) if($st ne OldValue($name));  
  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st;  
  
return;
}

###############################################################################
#                Parsen Payload für Syslog-Server
#                (im Collector Model)
###############################################################################
sub Log2Syslog_parsePayload($$) { 
  my ($hash,$data) = @_;
  my $name         = $hash->{NAME};
  my $pp           = AttrVal($name, "parseProfile", "IETF");
  my $severity     = "";
  my $facility     = "";  
  my @evf          = split(",",AttrVal($name, "outputFields", "FAC,SEV,ID,CONT"));   # auszugebene Felder im Event/Reading
  my ($Mmm,$dd,$delimiter,$day,$ietf,$err,$pl,$tail);
  
  # Hash zur Umwandlung Felder in deren Variablen
  my ($prival,$ts,$host,$date,$time,$id,$pid,$mid,$sdfield,$cont);
  my $fac = "";
  my $sev = "";
  my %fh = (PRIVAL  => \$prival,
            FAC     => \$fac,
            SEV     => \$sev,
            TS      => \$ts,
            HOST    => \$host,
            DATE    => \$date,
            TIME    => \$time,
            ID      => \$id,
            PID     => \$pid,
            MID     => \$mid,
            SDFIELD => \$sdfield,
            CONT    => \$cont,
            DATA    => \$data
           );
    
  Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name - ###  new Syslog message Parsing ### ");
  
  # Sender Host / IP-Adresse ermitteln, $phost wird Reading im Event
  my ($phost,$paddr) = Log2Syslog_evalPeer($hash);
  $phost = $phost?$phost:$paddr;
  
  Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name - raw message -> $data");
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);       # Istzeit Ableitung
  $year = $year+1900;
  
  if ($pp =~ /raw/) {
      Log2Syslog_Log3slog($name, 4, "$name - $data");
      $ts = TimeNow();
      $pl = $data;
  
  } elsif ($pp eq "BSD") { 
      # BSD Protokollformat https://tools.ietf.org/html/rfc3164
      # Beispiel data "<$prival>$month $day $time $myhost $id: : $otp"
      $data =~ /^<(?<prival>\d{1,3})>(?<tail>.*)$/;
      $prival = $+{prival};        # must
      $tail   = $+{tail}; 
      $tail =~ /^((?<month>\w{3})\s+(?<day>\d{1,2})\s+(?<time>\d{2}:\d{2}:\d{2}))?\s+(?<tail>.*)$/;
      $Mmm       = $+{month};         # should
      $dd        = $+{day};           # should
      $time      = $+{time};          # should
      $tail      = $+{tail};  
      if( $Mmm && $dd && $time ) {
          my $month = $Log2Syslog_BSDMonth{$Mmm};
          $day      = (length($dd) == 1)?("0".$dd):$dd;
          $ts       = "$year-$month-$day $time";
      }      
      if($ts) {
          # Annahme: wenn Timestamp gesetzt, wird der Rest der Message ebenfalls dem Standard entsprechen
          $tail =~ /^(?<host>[^\s]*)?\s(?<tail>.*)$/;
          $host = $+{host};          # should 
          $tail = $+{tail};
          $tail =~ /^(?<id>\w{1,32}\W?)?:?(?<cont>.*)$/;      
          $id   = $+{id};            # should
          $cont = $+{cont};          # should
      } else {
          # andernfalls eher kein Standardaufbau
          $cont = $tail;
      }

      if(!$prival) {
          $err = 1;
          Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");  
      } else {
          
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");          
          }
          
		  no warnings 'uninitialized'; 
          Log2Syslog_Log3slog($name, 4, "$name - parsed message -> FAC: $fac, SEV: $sev, MM: $Mmm, Day: $dd, TIME: $time, TS: $ts, HOST: $host, ID: $id, CONT: $cont");
          $host = "" if($host eq "-");
		  use warnings;
		  $phost = $host?$host:$phost;
          
          # Payload zusammenstellen für Event/Reading
          $pl = "";
          my $i = 0;
          foreach my $f (@evf) {
              if(${$fh{$f}}) { 
		          $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }  	  
      }
      
  } elsif ($pp eq "IETF") {
	  # IETF Protokollformat https://tools.ietf.org/html/rfc5424 
      # Beispiel data "<$prival>1 $tim $host $id $pid $mid - : $otp";
#      $data =~ /^<(?<prival>\d{1,3})>(?<ietf>\d+)\s(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})\S*\s(?<host>\S*)\s(?<id>\S*)\s(?<pid>\S*)\s(?<mid>\S*)\s(?<sdfield>(\[.*?\]|-))\s(?<cont>.*)$/;
      $data =~ /^<(?<prival>\d{1,3})>(?<ietf>\d+)\s(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})\S*\s(?<host>\S*)\s(?<id>\S*)\s(?<pid>\S*)\s(?<mid>\S*)\s(?<sdfield>(\[.*?(?!\\\]).\]|-))\s(?<cont>.*)$/;
      $prival  = $+{prival};      # must
      $ietf    = $+{ietf};        # must 
      $date    = $+{date};        # must
      $time    = $+{time};        # must
      $host    = $+{host};        # should 
      $id      = $+{id};          # should
      $pid     = $+{pid};         # should
      $mid     = $+{mid};         # should 
      $sdfield = $+{sdfield};     # must
      $cont    = $+{cont};        # should
      
      if(!$prival || !$ietf || !$date || !$time) {
          $err = 1;
          Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");           
      } else {
          $ts      = "$date $time";
      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");          
          }
      
          # Längenbegrenzung nach RFC5424
          $id     = substr($id,0, ($RFC5425len{ID}-1));
          $pid    = substr($pid,0, ($RFC5425len{PID}-1));
          $mid    = substr($mid,0, ($RFC5425len{MID}-1));
          $host   = substr($host,0, ($RFC5425len{HST}-1));
      
	      no warnings 'uninitialized'; 
          Log2Syslog_Log3slog($name, 4, "$name - parsed message -> FAC: $fac, SEV: $sev, TS: $ts, HOST: $host, ID: $id, PID: $pid, MID: $mid, SDFIELD: $sdfield, CONT: $cont");
          $host = "" if($host eq "-");
		  use warnings;
	      $phost = $host?$host:$phost;
          
          # Payload zusammenstellen für Event/Reading
          $pl = "";
          my $i = 0;
          foreach my $f (@evf) {
              if(${$fh{$f}}) { 
		          $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }          
      }
  
  } elsif ($pp eq "TPLink-SG2424") {
	  # Parser für TPLink Router
      # Beispiel data "<131>2018-08-10 09:03:58 10.0.x.y 31890 Login the web by admin on web (10.0.x.y).";
      $data =~ /^<(?<prival>\d{1,3})>(?<date>\d{4}-\d{2}-\d{2})\s(?<time>\d{2}:\d{2}:\d{2})\s(?<host>\S*)\s(?<id>\S*)\s(?<cont>.*)$/;
      $prival  = $+{prival};      # must
      $date    = $+{date};        # must
      $time    = $+{time};        # must
      $host    = $+{host};        # should 
      $id      = $+{id};          # should
      $cont    = $+{cont};        # should
      
      if(!$prival || !$date || !$time) {
          $err = 1;
          Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");           
      } else {
          $ts      = "$date $time";
      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");          
          }
            
		  no warnings 'uninitialized'; 
          Log2Syslog_Log3slog($name, 4, "$name - parsed message -> FAC: $fac, SEV: $sev, TS: $ts, HOST: $host, ID: $id, CONT: $cont");
          $host = "" if($host eq "-");
		  use warnings;
	      $phost = $host?$host:$phost;
          
          # Payload zusammenstellen für Event/Reading
          $pl = "";
          my $i = 0;
          foreach my $f (@evf) {
              if(${$fh{$f}}) { 
		          $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }          
      }
  
  } elsif($pp eq "ParseFn") {
	  # user spezifisches Parsing
      my $parseFn = AttrVal( $name, "parseFn", "" );
      $ts = TimeNow();
      
      if( $parseFn =~ m/^\s*(\{.*\})\s*$/s ) {
          $parseFn = $1;
      } else {
          $parseFn = '';
      }
  
      if($parseFn ne '') {
          my $PRIVAL       = "";
          my $TS           = $ts;
          my $DATE         = "";
          my $TIME         = "";
 	      my $HOST         = "";
 	      my $ID           = "";
     	  my $PID          = "";
 	      my $MID          = "";
 	      my $CONT         = "";
 	      my $FAC          = "";
	      my $SEV          = "";
          my $DATA         = $data;
          my $SDFIELD      = "";

 	      eval $parseFn;
          if($@) {
	          Log3 $name, 1, "DbLog $name -> error parseFn: $@";
              $err = 1;
          }
		 
          $prival  = $PRIVAL if($PRIVAL =~ /\d{1,3}/);
          $date    = $DATE if($DATE =~ /^(\d{4})-(\d{2})-(\d{2})$/);
          $time    = $TIME if($TIME =~ /^(\d{2}):(\d{2}):(\d{2})$/);          
          $ts      = ($TS =~ /^(\d{4})-(\d{2})-(\d{2})\s(\d{2}):(\d{2}):(\d{2})$/)?$TS:($date && $time)?"$date $time":$ts;
 	      $host    = $HOST if(defined $HOST);
	      $id      = $ID if(defined $ID);
          $pid     = $PID if(defined $PID);
          $mid     = $MID if(defined $MID);
          $cont    = $CONT if(defined $CONT);
          $fac     = $FAC if(defined $FAC);
          $sev     = $SEV if(defined $SEV);
          $sdfield = $SDFIELD if(defined $SDFIELD);
          
          if($prival && looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - error parse msg -> $data");          
          }

          Log2Syslog_Log3slog($name, 4, "$name - parsed message -> FAC: $fac, SEV: $sev, TS: $ts, HOST: $host, ID: $id, PID: $pid, MID: $mid, CONT: $cont");
		  $phost = $host?$host:$phost;
          
          # auszugebene Felder im Event/Reading
          my $ef = "PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT"; 
          @evf = split(",",AttrVal($name, "outputFields", $ef));    
          
          # Payload zusammenstellen für Event/Reading
          $pl = "";
          my $i = 0;
          foreach my $f (@evf) {
              if(${$fh{$f}}) { 
		          $pl .= " || " if($i);
                  $pl .= "$f: ".${$fh{$f}};
                  $i++;
              }
          }           
      
      } else {
          $err = 1;
          Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - no parseFn defined."); 
      }
  }
  
  if(AttrVal($name, "TLS", 0)) {
      # wenn Transport Layer Security (TLS) -> Transport Mapping for Syslog https://tools.ietf.org/pdf/rfc5425.pdf
	  
  } 	

return ($err,$phost,$ts,$pl);
}

#################################################################################################
#                       Syslog Collector Events erzeugen
#                       (im Collector Model)
#################################################################################################
sub Log2Syslog_Trigger($$$) {
  my ($hash,$ts,$pl) = @_;
  my $name       = $hash->{NAME};
  my $no_replace = 1;                     # Ersetzung von Events durch das Attribut eventMap verhindern
  
  if($hash->{CHANGED}) {
      push @{$hash->{CHANGED}}, $pl;
  } else {
      $hash->{CHANGED}[0] = $pl;
  }
  
  if($hash->{CHANGETIME}) {
      push @{$hash->{CHANGETIME}}, $ts;
  } else {
      $hash->{CHANGETIME}[0] = $ts;
  }

  my $ret = DoTrigger($name, undef, $no_replace);
  
return;
}

###############################################################################
#               Undef Funktion
###############################################################################
sub Log2Syslog_Undef($$) {
  my ($hash, $name) = @_;
  
  RemoveInternalTimer($hash);
  
  if($hash->{MODEL} =~ /Collector/) {
      Log2Syslog_downServer($hash);
  }
  
return undef;
}

###############################################################################
#                         Collector-Socket schließen
###############################################################################
sub Log2Syslog_downServer($) {
  my ($hash)   = @_;
  my $name     = $hash->{NAME};
  my $port     = $hash->{PORT};
  my $protocol = $hash->{PROTOCOL};
  
  return if(!$hash->{SERVERSOCKET});
  
  Log3 $hash, 3, "Log2Syslog $name - Closing socket $protocol/$port ...";
  my $ret = $hash->{SERVERSOCKET}->close();
  Log3 $hash, 1, "Log2Syslog $name - Can't close Syslog Collector at port $port: $!" if(!$ret);
  delete($hash->{SERVERSOCKET});
  delete($selectlist{"$name.$port"});
  delete($readyfnlist{"$name.$port"});
  delete($hash->{FD});
  
return; 
}

###############################################################################
#               Delete Funktion
###############################################################################
sub Log2Syslog_Delete($$) {
  my ($hash, $arg) = @_;
  delete $logInform{$hash->{NAME}};
return undef;
}

###############################################################################
#              Set
###############################################################################
sub Log2Syslog_Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  
  my $setlist = "Unknown argument $opt, choose one of ".
                "sendTestMessage " 
                ;
  
  return if(AttrVal($name, "disable", "") eq "1" || $hash->{MODEL} !~ /Sender/);
  
  if($opt =~ /sendTestMessage/) {
      my $own;
      if ($prop) {
          shift @a;
          shift @a;
          $own = join(" ",@a);     
      }
	  Log2Syslog_sendTestMsg($hash,$own);
  
  } else {
      return "$setlist";
  }  
  
return undef;
}

###############################################################################
#              Get
###############################################################################
sub Log2Syslog_Get($@) {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  
  my $getlist = "Unknown argument $opt, choose one of ".
                "certinfo:noArg " 
                ;
  
  return if(AttrVal($name, "disable", "") eq "1");
  
  my($sock,$cert,@certs);
  if ($opt =~ /certinfo/) {
      if(ReadingsVal($name,"SSL_Version","n.a.") ne "n.a.") {
	      $sock = Log2Syslog_opensock($hash);
		  if(defined($sock)) {
		      $cert = $sock->dump_peer_certificate();
		      Log2Syslog_closesock($hash,$sock);
		  }
	  }
	  return $cert if($cert);
	  return "no SSL session has been created";
	  
  } else {
      return "$getlist";
  } 
  
return undef;
}

###############################################################################
sub Log2Syslog_Attr ($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my $do;
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

	if ($cmd eq "set" && $hash->{MODEL} !~ /Collector/ && $aName =~ /parseProfile|parseFn|outputFields|makeMsgEvent/) {
         return "\"$aName\" is only valid for model \"Collector\"";
	}
    
	if ($cmd eq "set" && $hash->{MODEL} =~ /Collector/ && $aName =~ /addTimestamp|contDelimiter|addStateEvent|protocol|logFormat|sendSeverity|timeout|TLS/) {
        return "\"$aName\" is only valid for model \"Sender\"";
	}
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            return "Mode \"$aVal\" is only valid for model \"Sender\"" if($aVal eq "maintenance" && $hash->{MODEL} !~ /Sender/);
            $do = $aVal?1:0;
        }
        $do = 0 if($cmd eq "del");
        my $val = ($do&&$aVal=~/maintenance/)?"maintenance":($do&&$aVal==1)?"disabled":"active";
		
        readingsSingleUpdate($hash, "state", $val, 1);
    }
	
    if ($aName eq "TLS") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if ($do == 0) {		
            $hash->{HELPER}{SSLVER}  = "n.a.";
            $hash->{HELPER}{SSLALGO} = "n.a.";
			readingsSingleUpdate($hash, "SSL_Version", "n.a.", 1);
            readingsSingleUpdate($hash, "SSL_Algorithm", "n.a.", 1);
		}
    }
    
    if ($aName =~ /rateCalcRerun/) {
        unless ($aVal =~ /^[0-9]+$/) { return "Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
        $_[3] = 60 if($aVal < 60);
        RemoveInternalTimer($hash, "Log2Syslog_trate");
        InternalTimer(gettimeofday()+5, "Log2Syslog_trate", $hash, 0);
    }
	
	if ($cmd eq "set" && $aName =~ /port|timeout/) {
        if($aVal !~ m/^\d+$/) { return " The Value of \"$aName\" is not valid. Use only figures !";}
        if($aName =~ /port/ && $hash->{MODEL} =~ /Collector/ && $init_done) {
            return "$aName \"$aVal\" is not valid because privileged ports are only usable by super users. Use a port grater than 1023."  if($aVal < 1024);
            Log2Syslog_downServer($hash);
            RemoveInternalTimer($hash, "Log2Syslog_initServer");
            InternalTimer(gettimeofday()+1.5, "Log2Syslog_initServer", "$name,global", 0);
        }
	}
    
	if ($cmd eq "set" && $aName =~ /parseFn/) {
         $_[3] = "{$aVal}" if($aVal !~ m/^\{.*\}$/s);
         $aVal = $_[3];
	      my %specials = (
             "%DATA"    => "1",
             "%PRIVAL"  => "1",
             "%TS"      => "1",
             "%DATE"    => "1",
             "%TIME"    => "1",
			 "%HOST"    => "1",
			 "%ID"      => "1",
             "%PID"     => "1",
             "%MID"     => "1",
             "%CONT"    => "1",
			 "%FAC"     => "1",
             "%SDFIELD" => "1",
             "%SEV"     => "1"
          );
          my $err = perlSyntaxCheck($aVal, %specials);
          return $err if($err);
	}
    
	if ($cmd eq "set" && $aName =~ /parseProfile/ && $aVal =~ /ParseFn/) {
          return "You have to define a parse-function via attribute \"parseFn\" first !" if(!AttrVal($name,"parseFn",""));
	}
    
    if ($cmd eq "del" && $aName =~ /parseFn/ && AttrVal($name,"parseProfile","") eq "ParseFn" ) {
          return "You use a parse-function via attribute \"parseProfile\". Please change/delete attribute \"parseProfile\" first !";
    }
    
    if ($aName =~ /makeMsgEvent/) {
        if($aVal =~ /intern/ || $cmd eq "del") {
            foreach my $reading (grep { /MSG_/ } keys %{$defs{$name}{READINGS}}) {
                readingsDelete($defs{$name}, $reading);
            }
        }
    }    
    
return;
}

#################################################################################
#                               Eventlogging
#################################################################################
sub Log2Syslog_eventlog($$) {
  # $hash is my entry, $dev is the entry of the changed device
  my ($hash,$dev) = @_;
  my $name    = $hash->{NAME};
  my $rex     = $hash->{HELPER}{EVNTLOG};
  my $st      = ReadingsVal($name,"state","active");
  my $sendsev = AttrVal($name, "sendSeverity", "");              # Nachrichten welcher Schweregrade sollen gesendet werden
  my ($prival,$sock,$data,$pid,$sevAstxt);
  
  return if(IsDisabled($name) || !$rex || $hash->{MODEL} !~ /Sender/);
  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  return if(!$events);

  my $n   = $dev->{NAME};
  my $max = int(@{$events});
  my $tn  = $dev->{NTFY_TRIGGERTIME};
  my $ct  = $dev->{CHANGETIME};
  
  $sock = Log2Syslog_opensock($hash);
  
  if(defined($sock)) { 
      for (my $i = 0; $i < $max; $i++) {
          my $txt = $events->[$i];
          $txt = "" if(!defined($txt));
          $txt = Log2Syslog_charfilter($hash,$txt);
	  
	      my $tim          = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
          my ($date,$time) = split(" ",$tim);
	  
	      if($n =~ m/^$rex$/ || "$n:$txt" =~ m/^$rex$/ || "$tim:$n:$txt" =~ m/^$rex$/) {				  
              my $otp             = "$n $txt";
              $otp                = "$tim $otp" if AttrVal($name,'addTimestamp',0);
	          ($prival,$sevAstxt) = Log2Syslog_setprival($txt);
              if($sendsev && $sendsev !~ m/$sevAstxt/) {
                  # nicht senden wenn Severity nicht in "sendSeverity" enthalten
                  Log2Syslog_Log3slog($name, 5, "$name - Warning - Payload NOT sent due to Message Severity not in attribute \"sendSeverity\"\n");
                  next;        
              }

	          ($data,$pid) = Log2Syslog_setpayload($hash,$prival,$date,$time,$otp,"event");	
              next if(!$data);			  
          
			  my $ret = syswrite $sock, $data."\n";
			  if($ret && $ret > 0) {      
				  Log2Syslog_Log3slog($name, 4, "$name - Payload sequence $pid sent\n");	
              } else {
                  my $err = $!;
				  Log2Syslog_Log3slog($name, 4, "$name - Warning - Payload sequence $pid NOT sent: $err\n");	
                  $st = "write error: $err";                 
			  }
          }
      } 
      Log2Syslog_closesock($hash,$sock);
  }

  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st; 
                  
return "";
}

#################################################################################
#                               FHEM system logging
#################################################################################
sub Log2Syslog_fhemlog($$) {
  my ($name,$raw) = @_;                              
  my $hash    = $defs{$name};
  my $rex     = $hash->{HELPER}{FHEMLOG};
  my $st      = ReadingsVal($name,"state","active");
  my $sendsev = AttrVal($name, "sendSeverity", "");              # Nachrichten welcher Schweregrade sollen gesendet werden
  my ($prival,$sock,$err,$ret,$data,$pid,$sevAstxt);
  
  return if(IsDisabled($name) || !$rex || $hash->{MODEL} !~ /Sender/);
	
  my ($date,$time,$vbose,undef,$txt) = split(" ",$raw,5);
  $txt = Log2Syslog_charfilter($hash,$txt);
  $date =~ s/\./-/g;
  my $tim = $date." ".$time;
  
  if($txt =~ m/^$rex$/ || "$vbose: $txt" =~ m/^$rex$/) {  	
      my $otp             = "$vbose: $txt";
      $otp                = "$tim $otp" if AttrVal($name,'addTimestamp',0);
	  ($prival,$sevAstxt) = Log2Syslog_setprival($txt,$vbose);
      if($sendsev && $sendsev !~ m/$sevAstxt/) {
          # nicht senden wenn Severity nicht in "sendSeverity" enthalten
          Log2Syslog_Log3slog($name, 5, "$name - Warning - Payload NOT sent due to Message Severity not in attribute \"sendSeverity\"\n");
          return;        
      }
	  
      ($data,$pid) = Log2Syslog_setpayload($hash,$prival,$date,$time,$otp,"fhem");	
	  return if(!$data);
	  
      $sock = Log2Syslog_opensock($hash);
	  
      if (defined($sock)) {
	      $ret = syswrite $sock, $data."\n" if($data);
		  if($ret && $ret > 0) {  
		      Log2Syslog_Log3slog($name, 4, "$name - Payload sequence $pid sent\n");	
          } else {
              my $err = $!;
			  Log2Syslog_Log3slog($name, 4, "$name - Warning - Payload sequence $pid NOT sent: $err\n");	
              $st = "write error: $err";             
	      }  
          Log2Syslog_closesock($hash,$sock);
	  }
  }
  
  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st; 

return;
}

#################################################################################
#                               Test Message senden
#################################################################################
sub Log2Syslog_sendTestMsg($$) {
  my ($hash,$own) = @_;                              
  my $name        = $hash->{NAME};
  my $st          = ReadingsVal($name,"state","active");
  my ($prival,$ts,$tim,$date,$time,$sock,$err,$ret,$data,$pid,$otp);
  
  if($own) {
      # eigene Testmessage ohne Formatanpassung raw senden
      $data = $own;
  
  } else {   
      $ts = TimeNow();
      ($date,$time) = split(" ",$ts);
      $date =~ s/\./-/g;
      $tim = $date." ".$time;
   	
      $otp    = "Test message from FHEM Syslog Client from ($hash->{MYHOST})";
      $otp    = "$tim $otp" if AttrVal($name,'addTimestamp',0);
	  $prival = "14";
	  
      ($data,$pid) = Log2Syslog_setpayload($hash,$prival,$date,$time,$otp,"fhem");	
	  return if(!$data);
  }  
      
  $sock = Log2Syslog_opensock($hash);
	  
  if (defined($sock)) {
	  $ret = syswrite $sock, $data."\n" if($data);
	  if($ret && $ret > 0) {  
	      Log2Syslog_Log3slog($name, 4, "$name - Payload sequence $pid sent\n");	
      } else {
          my $err = $!;
	      Log2Syslog_Log3slog($name, 4, "$name - Warning - Payload sequence $pid NOT sent: $err\n");	
          $st = "write error: $err";              
	  }  
      Log2Syslog_closesock($hash,$sock);
  }
  
  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st; 

return;
}

###############################################################################
#              Helper für ident & Regex setzen 
###############################################################################
sub Log2Syslog_setidrex ($$) { 
  my ($hash,$a) = @_;
     
  $hash->{HELPER}{EVNTLOG} = (split("event:",$a))[1] if(lc($a) =~ m/^event:.*/);
  $hash->{HELPER}{FHEMLOG} = (split("fhem:",$a))[1] if(lc($a) =~ m/^fhem:.*/);
  $hash->{HELPER}{IDENT}   = (split("ident:",$a))[1] if(lc($a) =~ m/^ident:.*/);
  
return;
}

###############################################################################
#              Zeichencodierung für Payload filtern 
###############################################################################
sub Log2Syslog_charfilter ($$) { 
  my ($hash,$txt) = @_;
  my $name   = $hash->{NAME};

  # nur erwünschte Zeichen in payload, ASCII %d32-126
  $txt =~ s/ß/ss/g;
  $txt =~ s/ä/ae/g;
  $txt =~ s/ö/oe/g;
  $txt =~ s/ü/ue/g;
  $txt =~ s/Ä/Ae/g;
  $txt =~ s/Ö/Oe/g;
  $txt =~ s/Ü/Ue/g;
  $txt =~ s/€/EUR/g;
  $txt =~ tr/ A-Za-z0-9!"#$%&'()*+,-.\/:;<=>?@[\]^_`{|}~//cd;      
  
return($txt);
}

###############################################################################
#                        erstelle Socket 
###############################################################################
sub Log2Syslog_opensock ($) { 
  my ($hash)   = @_;
  my $name     = $hash->{NAME};
  my $host     = $hash->{PEERHOST};
  my $port     = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 514);
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  my $st       = ReadingsVal($name,"state","active");
  my $timeout  = AttrVal($name, "timeout", 0.5);
  my $ssldbg   = AttrVal($name, "ssldebug", 0);
  my ($sock,$lo,$sslver,$sslalgo);
  
  return undef if($init_done != 1 || $hash->{MODEL} !~ /Sender/);
 
  if(AttrVal($name, "TLS", 0)) {
      # TLS gesicherte Verbindung
      # TLS Transport nach RFC5425 https://tools.ietf.org/pdf/rfc5425.pdf
	  $attr{$name}{protocol} = "TCP" if(AttrVal($name, "protocol", "UDP") ne "TCP");
	  $sslver  = "n.a.";
      $sslalgo = "n.a.";
	  eval "use IO::Socket::SSL";
	  if($@) {
          $st = "$@";
      } else {
	      $sock = IO::Socket::INET->new(PeerHost => $host, PeerPort => $port, Proto => 'tcp', Blocking => 0);
	      if (!$sock) {
		      $st = "unable open socket for $host, $protocol, $port: $!";
		  } else {
		      $sock->blocking(1);
              $IO::Socket::SSL::DEBUG = $ssldbg;
		      eval { IO::Socket::SSL->start_SSL($sock, 
						    			        SSL_verify_mode => 0,
		                                        SSL_version => "TLSv1_2:!TLSv1_1:!SSLv3:!SSLv23:!SSLv2",
								    	        SSL_hostname => $host,
									            SSL_veriycn_scheme => "rfc5425",
									            SSL_veriycn_publicsuffix => '',
												Timeout => $timeout
									            ) || undef $sock; };
              $IO::Socket::SSL::DEBUG = 0;
		      if($@) {
                  $st = "SSL error: $@";
                  undef $sock;
              } elsif (!$sock) {
		          $st = "SSL error: ".IO::Socket::SSL::errstr();
                  undef $sock;
		      } else  {
			      $sslver  = $sock->get_sslversion();
			      $sslalgo = $sock->get_fingerprint();
			      $sslalgo = (split("\\\$",$sslalgo))[0];
			      $lo      = "Socket opened for Host: $host, Protocol: $protocol, Port: $port, TLS: 0";
                  $st      = "active";
		      }
		  }
	  }     
  } else {
      # erstellt ungesicherte Socket Verbindung
	  $sslver  = "n.a.";
      $sslalgo = "n.a.";
      $sock    = new IO::Socket::INET (PeerHost => $host, PeerPort => $port, Proto => $protocol, Timeout => $timeout ); 

      if (!$sock) {
	      undef $sock;
          $st = "unable open socket for $host, $protocol, $port: $!";
      } else {
          $sock->blocking(0);
          $st = "active";
          # Logausgabe (nur in das fhem Logfile !)
          $lo = "Socket opened for Host: $host, Protocol: $protocol, Port: $port, TLS: 0";
      }
  }

  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
  readingsSingleUpdate($hash, "state", $st, $evt);
  $hash->{HELPER}{OLDSTATE} = $st;
  
  if($sslver ne $hash->{HELPER}{SSLVER}) {
      readingsSingleUpdate($hash, "SSL_Version", $sslver, 1);
	  $hash->{HELPER}{SSLVER} = $sslver;
  }
  
  if($sslalgo ne $hash->{HELPER}{SSLALGO}) {
      readingsSingleUpdate($hash, "SSL_Algorithm", $sslalgo, 1);
	  $hash->{HELPER}{SSLALGO} = $sslalgo;
  }
  
  Log2Syslog_Log3slog($name, 5, "$name - $lo") if($lo);
  
return($sock);
}

###############################################################################
#                          Socket schließen
###############################################################################
sub Log2Syslog_closesock($$) {
  my ($hash,$sock) = @_;
  
  shutdown($sock, 1);
  if(AttrVal($hash->{NAME}, "TLS", 0)) {
      $sock->close(SSL_no_shutdown => 1);
  } else {
      $sock->close();
  }
  
return; 
}

###############################################################################
#               set PRIVAL (severity & facility)
###############################################################################
sub Log2Syslog_setprival ($;$$) { 
  my ($txt,$vbose) = @_;
  my ($prival,$sevAstxt);
  
  # Priority = (facility * 8) + severity 
  # https://tools.ietf.org/pdf/rfc5424.pdf
  
  # determine facility
  my $fac = 5;                                     # facility by syslogd
  
  # calculate severity
  # mapping verbose level to severity
  # 0: Critical        -> 2
  # 1: Error           -> 3
  # 2: Warning         -> 4
  # 3: Notice          -> 5
  # 4: Informational   -> 6
  # 5: Debug           -> 7
  
  my $sv = 5;                                      # notice (default)
  
  if ($vbose) {
      # map verbose to severity 
	  $sv = 2 if ($vbose == 0);
	  $sv = 3 if ($vbose == 1);
	  $sv = 4 if ($vbose == 2);
	  $sv = 5 if ($vbose == 3);
	  $sv = 6 if ($vbose == 4);
      $sv = 7 if ($vbose == 5);
  }
                                         
  $sv = 3 if (lc($txt) =~ m/error/);              # error condition
  $sv = 4 if (lc($txt) =~ m/warning/);            # warning conditions
  
  $prival   = ($fac*8)+$sv;
  $sevAstxt = $Log2Syslog_Severity{$sv};
   
return($prival,$sevAstxt);
}

###############################################################################
#               erstellen Payload für Syslog
###############################################################################
sub Log2Syslog_setpayload ($$$$$$) { 
  my ($hash,$prival,$date,$time,$otp,$lt) = @_;
  my $name   = $hash->{NAME};
  my $ident  = ($hash->{HELPER}{IDENT}?$hash->{HELPER}{IDENT}:$name)."_".$lt;
  my $myhost = $hash->{MYHOST}?$hash->{MYHOST}:"0.0.0.0";
  my $lf     = AttrVal($name, "logFormat", "IETF");
  my $tag    = AttrVal($name, "contDelimiter", "");         # Trennzeichen vor Content (z.B. für Synology nötig)
  my $data;
  
  return undef,undef if(!$otp);
  my $pid = $hash->{SEQNO};                                 # PayloadID zur Nachverfolgung der Eventabfolge 
  $hash->{SEQNO}++;

  my ($year,$month,$day) = split("-",$date);
  
  if ($lf eq "BSD") {
      # BSD Protokollformat https://tools.ietf.org/html/rfc3164
      $time  = (split(/\./,$time))[0] if($time =~ m/\./);   # msec ist nicht erlaubt
	  $month = $Log2Syslog_BSDMonth{$month};                # Monatsmapping, z.B. 01 -> Jan
	  $day   =~ s/0/ / if($day =~ m/^0.*$/);                # in Tagen < 10 muss 0 durch Space ersetzt werden
	  $ident = substr($ident,0, $RFC3164len{TAG});          # Länge TAG Feld begrenzen
	  no warnings 'uninitialized'; 
      $data  = "<$prival>$month $day $time $myhost $ident $tag$otp";
	  use warnings;
	  $data = substr($data,0, ($RFC3164len{DL}-1));         # Länge Total begrenzen
  }
  
  if ($lf eq "IETF") {
      # IETF Protokollformat https://tools.ietf.org/html/rfc5424 
      
      my $IETFver = 1;                                      # Version von syslog Protokoll Spec RFC5424
	  my $mid     = "FHEM";                                 # message ID, identify protocol of message, e.g. for firewall filter
	  my $tim     = $date."T".$time; 
      my $sdfield = "[version\@Log2Syslog version=\"$hash->{VERSION}\"]";
      $otp        = Encode::encode_utf8($otp);
      
      # Längenbegrenzung nach RFC5424
      $ident  = substr($ident,0, ($RFC5425len{ID}-1));
      $pid    = substr($pid,0, ($RFC5425len{PID}-1));
      $mid    = substr($mid,0, ($RFC5425len{MID}-1));
      $myhost = substr($myhost,0, ($RFC5425len{HST}-1));
      
      no warnings 'uninitialized';
      if ($IETFver == 1) {
          $data = "<$prival>$IETFver $tim $myhost $ident $pid $mid $sdfield $tag$otp";
      }
	  use warnings;
  }
  
  if($data =~ /\s$/){$data =~ s/\s$//;}
  my $dl = length($data);                                   # Länge muss ! für TLS stimmen, sonst keine Ausgabe !
  
  # wenn Transport Layer Security (TLS) -> Transport Mapping for Syslog https://tools.ietf.org/pdf/rfc5425.pdf
  if(AttrVal($name, "TLS", 0)) {
	  $data = "$dl $data";
	  $data = substr($data,0, ($RFC5425len{DL}-1));         # Länge Total begrenzen 
	  Log2Syslog_Log3slog($name, 4, "$name - SSL-Payload created with length: ".(($dl>($RFC5425len{DL}-1))?($RFC5425len{DL}-1):$dl) ); 
  } 
  
  my $ldat = ($dl>130)?(substr($data,0, 130)." ..."):$data;
  Log2Syslog_Log3slog($name, 4, "$name - Payload sequence $pid created:\n$ldat");		
  
return($data,$pid);
}

###############################################################################
#               eigene Log3-Ableitung - Schleife vermeiden
###############################################################################
sub Log2Syslog_Log3slog($$$) {
  my ($dev, $loglevel, $text) = @_;
  our ($logopened,$currlogfile);
  
  $dev = $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");
     
  if(defined($dev) &&
     defined($attr{$dev}) &&
     defined (my $devlevel = $attr{$dev}{verbose})) {
    return if($loglevel > $devlevel);

  } else {
    return if($loglevel > $attr{global}{verbose});

  }

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards($attr{global}{logfile}, @t);
  OpenLogfile($nfile) if(!$currlogfile || $currlogfile ne $nfile);

  my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
  if($attr{global}{mseclog}) {
    $tim .= sprintf(".%03d", $microseconds/1000);
  }

  if($logopened) {
    print LOG "$tim $loglevel: $text\n";
  } else {
    print "$tim $loglevel: $text\n";
  }

return undef;
}

###############################################################################
#                          Bestimmung Übertragungsrate
###############################################################################
sub Log2Syslog_trate($) {
  my ($hash) = @_;
  my $name  = $hash->{NAME};
  my $rerun = AttrVal($name, "rateCalcRerun", 60);
  
  if ($hash->{HELPER}{LTIME}+60 <= time()) {
      my $div = (time()-$hash->{HELPER}{LTIME})/60;
      my $spm = sprintf "%.0f", ($hash->{SEQNO} - $hash->{HELPER}{OLDSEQNO})/$div;
      $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};
      $hash->{HELPER}{LTIME}    = time();
	  
	  my $ospm = ReadingsVal($name, "Transfered_logs_per_minute", 0);
	  if($spm != $ospm) {
          readingsSingleUpdate($hash, "Transfered_logs_per_minute", $spm, 1);
      } else {
          readingsSingleUpdate($hash, "Transfered_logs_per_minute", $spm, 0);	  
	  }
  }
  
RemoveInternalTimer($hash, "Log2Syslog_trate");
InternalTimer(gettimeofday()+$rerun, "Log2Syslog_trate", $hash, 0);

return; 
}

###############################################################################
#                  Peer IP-Adresse und Host ermitteln (Sender der Message)
###############################################################################
sub Log2Syslog_evalPeer($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  my $socket = $hash->{SERVERSOCKET};
  my ($phost,$paddr);
  
  my($pport, $pipaddr) = sockaddr_in($socket->peername);
  $phost = gethostbyaddr($pipaddr, AF_INET);
  $paddr = inet_ntoa($pipaddr);
  Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name - message peerhost: $phost,$paddr");

return ($phost,$paddr); 
}


1;

=pod
=item helper
=item summary    forwards FHEM system logs and/or events to a syslog server or act as an syslog server itself
=item summary_DE sendet FHEM Systemlogs und/oder Events an einen Syslog-Server bzw. agiert selbst als Syslog-Server

=begin html

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  Send FHEM system log entries and/or FHEM events to an external syslog server. <br>
  The syslog protocol has been implemented according the specifications of <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> and the TLS transport protocol according to 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>	
  <br>
  
  <b>Prerequisits</b>
  <ul>
    <br/>
    The additional perl module "IO::Socket::INET" must be installed on your system. <br>
	Install this package from cpan or by <br><br>
    
	<code>apt-get install libio-socket-multicast-perl (only on Debian based installations) </code><br>
  </ul>
  <br>
  
  <a name="Log2Syslogdefine"></a>
  <b>Define</b>
  <ul>
    <br>
    <code>define &lt;name&gt; Log2Syslog &lt;destination host&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;]</code><br>
    <br>
	
	&lt;destination host&gt; = host where the syslog server is running <br>
	[ident:&lt;ident&gt;] = optional program identifier. If not set the device name will be used as default <br>
	[event:&lt;regexp&gt;] = optional regex to filter events for logging  <br>
	[fhem:&lt;regexp&gt;] = optional regex to filter fhem system log for logging <br><br>
	
	After definition the new device sends all new appearing fhem systemlog entries and events to the destination host, 
	port=514/UDP format:IETF, immediately without further settings if the regex for fhem or event were set. <br>
	Without setting regex no fhem system log or event log will be forwarded. <br><br>
	
	The verbose level of FHEM system logs will convert into equivalent syslog severity level. <br>
	Thurthermore the message text will be scanned for signal terms "warning" and "error" (with case insensitivity). 
	Dependent off the severity will be set equivalent as well. If a severity is already set by verbose level, it wil be overwritten
    by the level according to the signal term found in the message text. <br><br>
	
	<b>Lookup table Verbose-Level to Syslog severity level: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=40%> <col width=60%> </colgroup>
	  <tr><td> <b>verbose-Level</b> </td><td> <b>Severity in Syslog</b> </td></tr>
      <tr><td> 0    </td><td> Critical </td></tr>
      <tr><td> 1    </td><td> Error </td></tr>
      <tr><td> 2    </td><td> Warning </td></tr>
      <tr><td> 3    </td><td> Notice </td></tr>
      <tr><td> 4    </td><td> Informational </td></tr>
      <tr><td> 5    </td><td> Debug </td></tr>
    </table>
    </ul>     
    <br>
    
	<br>
    Example to log anything: <br>
    <br/>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br>
    <br/>
    will produce output like this raw example of a splunk syslog server:<br/>
    <pre>Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM - : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM - : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM - : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM - : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM - : 4: CamTER - CAMID already set - ignore get camid
    </pre>
	
	The structure of the payload differs dependent of the used logFormat. <br><br>
	
	<b>logFormat IETF:</b> <br><br>
	"&lt;PRIVAL&gt;VERSION TIME MYHOST IDENT PID MID [SD-FIELD] :MESSAGE" <br><br> 
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> priority value (coded from "facility" and "severity") </td></tr>
      <tr><td> TIME     </td><td> timestamp according to RFC5424 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> ident-Tag from DEF if set, or else the own device name. The statement will be completed by "_fhem" (FHEM-Log) respectively "_event" (Event-Log). </td></tr>
      <tr><td> PID      </td><td> sequential Payload-ID </td></tr>
      <tr><td> MID      </td><td> fix value "FHEM" </td></tr>
      <tr><td> MESSAGE  </td><td> the dataset to transfer </td></tr>
    </table>
    </ul>     
    <br>	
	
	<b>logFormat BSD:</b> <br><br>
	"&lt;PRIVAL&gt;MONAT TAG TIME MYHOST IDENT: : MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> priority value (coded from "facility" and "severity") </td></tr>
      <tr><td> MONAT    </td><td> month according to RFC3164 </td></tr>
	  <tr><td> TAG      </td><td> day of month according to RFC3164 </td></tr>
	  <tr><td> TIME     </td><td> timestamp according to RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> ident-Tag from DEF if set, or else the own device name. The statement will be completed by "_fhem" (FHEM-Log) respectively "_event" (Event-Log). </td></tr>
      <tr><td> MESSAGE  </td><td> the dataset to transfer </td></tr>
    </table>
    </ul>     
    <br>
		
  </ul>
  <br>

  <a name="Log2SyslogGet"></a>
  <b>Get</b>
  <ul>
    <br> 
    
    <li><code>certinfo</code><br>
        <br>
        Show informations about the server certificate if a TLS-session was created (Reading "SSL_Version" isn't "n.a.").
    </li><br>
  </ul>
  <br>
  
  
  <a name="Log2Syslogattr"></a>
  <b>Attributes</b>
  <ul>
    <br/>
    <a name="addTimestamp"></a>
    <li><code>addTimestamp [0|1]</code><br>
        <br/>
        If set to 1, fhem timestamps will be logged too.<br/>
        Default behavior is to not log these timestamps, because syslog uses own timestamps.<br/>
        Maybe useful if mseclog is activated in fhem.<br/>
        <br/>
        Example output (raw) of a Splunk syslog server: <br>
        <pre>Aug 18 21:26:55 fhemtest.myds.me 1 2017-08-18T21:26:55 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:55 USV state: OL
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 Bezug state: done
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 recalc_Bezug state: Next: 21:31:59
        </pre>
    </li><br>

    <li><code>addStateEvent [0|1]</code><br>
        <br>
        If set to 1, events will be completed with "state" if a state-event appears.<br/>
		Default behavior is without getting "state".
    </li><br>
	
    <li><code>disable [0|1]</code><br>
        <br>
        disables the device.
    </li><br>
	
    <li><code>logFormat [BSD|IETF]</code><br>
        <br>
        Set the syslog protocol format. <br>
		Default value is "IETF" if not specified. 
		</li><br>
	
    <li><code>protocol [TCP|UDP]</code><br>
        <br>
        Sets the socket protocol which should be used. You can choose UDP or TCP. <br>
		Default value is "UDP" if not specified.
    </li><br>
	
    <li><code>port</code><br>
        <br>
        The used port. For a Sender the default-port is 514.
        A Collector (Syslog-Server) uses the port 1514 per default.
    </li><br>
	
    <li><code>rateCalcRerun</code><br>
        <br>
        Rerun cycle for calculation of log transfer rate (Reading "Transfered_logs_per_minute") in seconds. 
		Default is 60 seconds.
    </li><br>
    
    <li><code>ssldebug</code><br>
        <br>
        Debugging level of SSL messages. <br><br>
        <ul>
        <li> 0 - No debugging (default).  </li>
        <li> 1 - Print out errors from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and ciphers from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 2 - Print also information about call flow from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and progress information from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 3 - Print also some data dumps from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        </ul>
    </li><br>
	
    <li><code>TLS</code><br>
        <br>
        A secured connection to Syslog-server is used. The protocol will be switched to TCP automatically.
    </li><br>
    
    <li><code>timeout</code><br>
        <br>
        Timeout for connection to the destination syslog server (TCP). Only valid in Sender-mode. Default: 0.5 seconds.
    </li><br>
	
    <li><code>verbose</code><br>
        <br>
        To avoid loops, the output of verbose level of the Log2Syslog-Devices will only be reported into the local FHEM Logfile and
		no forwarded.
    </li><br>
	
	</ul>
    <br>
	
  <a name="Log2Syslogreadings"></a>
  <b>Readings</b>
  <ul>
  <br> 
    <table>  
    <colgroup> <col width=40%> <col width=60%> </colgroup>
	  <tr><td><b>SSL_Algorithm</b>                  </td><td> used SSL algorithm if SSL is enabled and active </td></tr>
      <tr><td><b>SSL_Version</b>                    </td><td> the used TLS-version if encryption is enabled and is active</td></tr>
	  <tr><td><b>Transfered_logs_per_minute</b>     </td><td> the average number of forwarded logs/events per minute </td></tr>
    </table>    
    <br>
  </ul>
  
</ul>

=end html
=begin html_DE

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  Sendet das Modul FHEM Systemlog Einträge und/oder Events an einen externen Syslog-Server weiter oder agiert als 
  Syslog-Server um Syslog-Meldungen anderer Geräte zu empfangen. <br>
  Die Implementierung des Syslog-Protokolls erfolgte entsprechend den Vorgaben von <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> sowie dem TLS Transport Protokoll nach 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>	
  <br>
  
  <b>Voraussetzungen</b>
  <ul>
    <br/>
    Es wird das Perl Modul "IO::Socket::INET" benötigt und muss installiert sein. <br>
    Das Modul kann über CPAN oder mit <br><br>
	
    <code>apt-get install libio-socket-multicast-perl (auf Debian Linux Systemen) </code><br><br>
	
	installiert werden.
  </ul>
  <br/>
  
  <a name="Log2Syslogdefine"></a>
  <b>Definition und Verwendung</b>
  <ul>
    <br>
    Je nach Verwendungszweck kann ein Syslog-Server (MODEL Collector) oder ein Syslog-Client (MODEL Sender) definiert 
    werden. <br>
    Der Collector empfängt Meldungen im Syslog-Format anderer Geräte und generiert daraus Events/Readings zur Weiterverarbeitung in 
    FHEM. Das Sender-Device leitet FHEM Systemlog Einträge und/oder Events an einen externen Syslog-Server weiter. <br>
  </ul>
    
  <br>
  <b><h4> Der Collector (Syslog-Server) </h4></b>

  <ul>    
    <b> Definition eines Collectors </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog </code><br>
    <br>
    </ul>
    
    Die Definition benötigt keine weiteren Parameter.
    In der Grundeinstellung wird der Syslog-Server mit dem Port=1514/UDP und dem Parsingprofil "IETF" initialisiert.
    Mit dem <a href="#Log2Syslogattr">Attribut</a> "parseProfile" können alternativ andere Formate (z.B. BSD) ausgewählt werden.
    Der Syslog-Server ist sofort betriebsbereit, parst die Syslog-Daten entsprechend der Richlinien nach RFC5424 und generiert aus den 
	eingehenden Syslog-Meldungen FHEM-Events. <br><br>
	
    <br>
    <b>Beispiel für einen Collector: </b><br>
    
    <ul>
    <br>
        <code>define SyslogServer Log2Syslog </code><br>
    <br>
    </ul>
    
    Im Eventmonitor können die generierten Events kontrolliert werden. <br>
    <br>

    Beispiel von generierten Events mit Attribut parseProfile=IETF: <br>
    <br>
    <code>
2018-07-31 17:07:24.382 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: USV state: OL <br>
2018-07-31 17:07:24.858 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: HMLAN2 loadLvl: low <br>
    </code> 
    <br>

    Zwischen den einzelnen Feldern wird der Trenner "||" verwendet. 
    Die Bedeutung der Felder in diesem Beispiel sind:   
    <br><br>
    
    <ul>  
    <table>  
    <colgroup> <col width=20%> <col width=80%> </colgroup>
	  <tr><td> <b>HOST</b>  </td><td> der Sender des Datensatzes </td></tr>
      <tr><td> <b>FAC</b>   </td><td> Facility (Kategorie) nach RFC5424 </td></tr>
      <tr><td> <b>SEV</b>   </td><td> Severity (Schweregrad) nach RFC5424 </td></tr>
      <tr><td> <b>ID</b>    </td><td> Ident-Tag </td></tr>
      <tr><td> <b>CONT</b>  </td><td> der Nachrichtenteil der empfangenen Meldung </td></tr>
    </table>
    </ul>
	<br>
	
	Der Timestamp der generierten Events wird aus den Syslogmeldungen geparst. Sollte diese Information nicht mitgeliefert 
    werden, wird der aktuelle Timestamp des Systems verwendet. <br>
	Der Name des Readings im generierten Event entspricht dem aus der Syslogmeldung geparsten Hostnamen.
	Ist der Hostname in der Meldung nicht enthalten, wird die IP-Adresse des Senders aus dem Netzwerk Interface abgerufen und 
    der Hostname ermittelt sofern möglich. 
    In diesem Fall wird der ermittelte Hostname bzw. die IP-Adresse als Reading im Event genutzt.
	<br>
	Nach der Definition des Collectors werden die Syslog-Meldungen im IETF-Format gemäß RFC5424 erwartet. Werden die Daten 
    nicht in diesem Format geliefert bzw. können nicht geparst werden, erscheint im Reading "state" die Meldung 
	<b>"parse error - see logfile"</b> und die empfangenen Syslog-Daten werden im Logfile im raw-Format ausgegeben. <br>
	
	In diesem Fall kann mit dem	<a href="#Log2Syslogattr">Attribut</a> "parseProfile" ein anderes vordefiniertes Parsing-Profil 
    eingestellt bzw. ein eigenes Profil definiert werden. <br><br>
    
    Zur Definition einer <b>eigenen Parsingfunktion</b> wird 
    "parseProfile = ParseFn" eingestellt und im <a href="#Log2Syslogattr">Attribut</a> "parseFn" eine spezifische 
    Parsingfunktion hinterlegt. <br>
    Die im Event verwendeten Felder und deren Reihenfolge können aus einem Wertevorrat mit dem 
    <a href="#Log2Syslogattr">Attribut</a> "outputFields" bestimmt werden. Je nach verwendeten Parsingprofil können alle oder
    nur eine Untermenge der verfügbaren Felder verwendet werden. Näheres dazu in der Beschreibung des Attributes "parseProfile". <br>
    <br>
    Das Verhalten der Eventgenerierung kann mit dem <a href="#Log2Syslogattr">Attribut</a> "makeMsgEvent" angepasst werden. <br>
  </ul>
    
  <br>
  <b><h4> Der Sender (Syslog-Client) </h4></b>

  <ul>    
    <b> Definition eines Senders </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog &lt;Zielhost&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;] </code><br>
    <br>
    </ul>
    
    <ul>  
    <table>  
    <colgroup> <col width=20%> <col width=80%> </colgroup>
	  <tr><td> <b>&lt;Zielhost&gt;</b>       </td><td> Host (Name oder IP-Adresse) auf dem der Syslog-Server läuft </td></tr>
      <tr><td> <b>[ident:&lt;ident&gt;]</b>  </td><td> optionaler Programm Identifier. Wenn nicht gesetzt wird per default der Devicename benutzt. </td></tr>
      <tr><td> <b>[event:&lt;regexp&gt;]</b> </td><td> optionaler regulärer Ausdruck zur Filterung von Events zur Weiterleitung </td></tr>
      <tr><td> <b>[fhem:&lt;regexp&gt;]</b>  </td><td> optionaler regulärer Ausdruck zur Filterung von FHEM Logs zur Weiterleitung </td></tr>
    </table>
    </ul> 
    
    <br><br>
	
	Direkt nach der Definition sendet das neue Device alle neu auftretenden FHEM Systemlog Einträge und Events ohne weitere 
	Einstellungen an den Zielhost, Port=514/UDP Format=IETF, wenn reguläre Ausdrücke für Events/FHEM angegeben wurden. <br>
	Wurde kein Regex gesetzt, erfolgt keine Weiterleitung von Events oder FHEM Systemlogs. <br><br>
	
	Die Verbose-Level der FHEM Systemlogs werden in entsprechende Schweregrade der Syslog-Messages umgewandelt. <br>
	Weiterhin wird der Meldungstext der FHEM Systemlogs und Events nach den Signalwörtern "warning" und "error" durchsucht 
	(Groß- /Kleinschreibung wird nicht beachtet). Davon abhängig wird der Schweregrad ebenfalls äquivalent gesetzt und übersteuert 
    einen eventuell bereits durch Verbose-Level gesetzten Schweregrad.	<br><br>
	
	<b>Umsetzungstabelle Verbose-Level in Syslog-Schweregrad Stufe: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=40%> <col width=60%> </colgroup>
	  <tr><td> <b>Verbose-Level</b> </td><td> <b>Schweregrad in Syslog</b> </td></tr>
      <tr><td> 0    </td><td> Critical </td></tr>
      <tr><td> 1    </td><td> Error </td></tr>
      <tr><td> 2    </td><td> Warning </td></tr>
      <tr><td> 3    </td><td> Notice </td></tr>
      <tr><td> 4    </td><td> Informational </td></tr>
      <tr><td> 5    </td><td> Debug </td></tr>
    </table>
    </ul>     
    <br>	
	<br>
    
    <b>Beispiel für einen Sender: </b><br>
    
    <ul>
    <br>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br/>
    <br>
    </ul>
    
    Es werden alle Events weitergeleitet wie deses Beispiel der raw-Ausgabe eines Splunk Syslog Servers zeigt:<br/>
    <pre>
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - CAMID already set - ignore get camid
    </pre>

	Der Aufbau der Payload unterscheidet sich je nach verwendeten logFormat. <br><br>
	
	<b>logFormat IETF:</b> <br><br>
	"&lt;PRIVAL&gt;VERSION TIME MYHOST IDENT PID MID [SD-FIELD] :MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL     </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> TIME       </td><td> Timestamp nach RFC5424 </td></tr>
      <tr><td> MYHOST     </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT      </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> PID        </td><td> fortlaufende Payload-ID </td></tr>
      <tr><td> MID        </td><td> fester Wert "FHEM" </td></tr>
	  <tr><td> [SD-FIELD] </td><td> Structured Data Feld. Enthält Informationen zur verwendeten Modulversion (die Klammern "[]" sind Bestandteil des Feldes)</td></tr>
      <tr><td> MESSAGE    </td><td> der zu übertragende Datensatz </td></tr>
    </table>
    </ul>     
    <br>	
	
	<b>logFormat BSD:</b> <br><br>
	"&lt;PRIVAL&gt;MONAT TAG TIME MYHOST IDENT: : MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> MONAT    </td><td> Monatsangabe nach RFC3164 </td></tr>
	  <tr><td> TAG      </td><td> Tag des Monats nach RFC3164 </td></tr>
	  <tr><td> TIME     </td><td> Zeitangabe nach RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> MESSAGE  </td><td> der zu übertragende Datensatz </td></tr>
    </table>
    </ul>     
    <br>
  
  </ul>
  <br><br>
  
  <a name="Log2SyslogSet"></a>
  <b>Set</b>
  <ul>
    <br> 
    
    <ul>
    <li><b>sendTestMessage [&lt;Message&gt;] </b><br>
        <br>
        Mit einem Devicetyp "Sender" kann abhängig vom Attribut "logFormat" eine Testnachricht im BSD- bzw. IETF-Format 
        gesendet werden. Wird eine optionale eigene &lt;Message&gt; angegeben, wird diese Nachricht im raw-Format ohne 
        Formatanpassung (BSD/IETF) gesendet. Das Attribut "disable = maintenance" legt fest, dass keine Daten ausser eine 
        Testnachricht an den Empfänger gesendet wird.
    </li>
    </ul>
    <br>

  </ul>
  <br>
  
  <a name="Log2SyslogGet"></a>
  <b>Get</b>
  <ul>
    <br> 
    
    <ul>
    <li><b>certinfo </b><br>
        <br>
        Zeigt Informationen zum Serverzertifikat wenn eine TLS-Session aufgebaut wurde (Reading "SSL_Version" ist nicht "n.a.").
    </li>
    </ul>
    <br>

  </ul>
  <br>

  
  <a name="Log2Syslogattr"></a>
  <b>Attribute</b>
  <ul>
    <br>
	
    <ul>
    <a name="addTimestamp"></a>
    <li><b>addTimestamp </b><br>
        <br/>
        Das Attribut ist nur für "Sender" verwendbar. Wenn gesetzt, werden FHEM Timestamps im Content-Feld der Syslog-Meldung
        mit übertragen.<br/>
        Per default werden die Timestamps nicht im Content-Feld hinzugefügt, da innerhalb der Syslog-Meldungen im IETF- bzw.
        BSD-Format bereits Zeitstempel gemäß RFC-Vorgabe erstellt werden.<br/>
        Die Einstellung kann hilfeich sein wenn mseclog in FHEM aktiviert ist.<br/>
        <br/>
		
        Beispielausgabe (raw) eines Splunk Syslog Servers:<br/>
        <pre>Aug 18 21:26:55 fhemtest.myds.me 1 2017-08-18T21:26:55 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:55 USV state: OL
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 Bezug state: done
Aug 18 21:26:54 fhemtest.myds.me 1 2017-08-18T21:26:54 fhemtest.myds.me Test_event 13339 FHEM - : 2017-08-18 21:26:54 recalc_Bezug state: Next: 21:31:59
        </pre>
    </li>
    </ul>
    <br>

    <ul>
    <li><b>addStateEvent </b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar. Wenn gesetzt, werden state-events mit dem Reading "state" ergänzt.<br/>
		Die Standardeinstellung ist ohne state-Ergänzung.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>contDelimiter </b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar. Es enthält ein zusätzliches Zeichen welches unmittelber vor das 
        Content-Feld eingefügt wird. <br>
        Diese Möglichkeit ist in manchen speziellen Fällen hilfreich (z.B. kann das Zeichen ':' eingefügt werden um eine 
        ordnungsgemäße Anzeige im Synology-Protokollcenter zu erhalten).
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>disable [1 | 0 | maintenance] </b><br>
        <br>
        Das Device wird aktiviert, deaktiviert bzw. in den Maintenance-Mode geschaltet. Im Maintenance-Mode kann mit dem 
        "Sender"-Device eine Testnachricht gesendet werden (siehe "set &lt;name&gt; sendTestMessage").
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>logFormat [ BSD | IETF ]</b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar.  Es stellt das Protokollformat ein. (default: "IETF") <br>
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>makeMsgEvent [ intern | no | reading ]</b><br>
        <br>
        Das Attribut ist nur für "Collector" verwendbar.  Mit dem Attribut wird das Verhalten der Event- bzw.
        Readinggenerierung festgelegt. 
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
	    <tr><td> <b>intern</b>   </td><td> es werden Events über die modulinterne Eventfunktion generiert </td></tr>
        <tr><td> <b>no</b>       </td><td> es werden nur Readings der Form "MSG_&lt;Hostname&gt;" ohne Eventfunktion erstellt </td></tr>
        <tr><td> <b>reading</b>  </td><td> es werden Readings der Form "MSG_&lt;Hostname&gt;" erstellt. Events werden in Abhängigkeit der "event-on-.*"-Attribute generiert </td></tr>
        </table>
        </ul> 
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>outputFields </b><br>
        <br>
        Über eine sortierbare Liste können die gewünschten Felder des generierten Events ausgewählt werden.
        Die abhängig vom Attribut <b>"parseProfil"</b> sinnvoll verwendbaren Felder und deren Bedeutung ist der Beschreibung 
        des Attributs "parseProfil" zu entnehmen.
        Ist "outputFields" nicht gesetzt, wird ein vordefinierter Satz Felder zur Eventgenerierung verwendet.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>parseFn {&lt;Parsefunktion&gt;} </b><br>
        <br>
        Das Attribut ist nur für Device-MODEL "Collector" verwendbar. Es wird die eingegebene Perl-Funktion auf die 
        empfangene Syslog-Meldung angewendet. Der Funktion werden folgende Variablen übergeben die zur Verarbeitung
        und zur Werterückgabe genutzt werden können. Leer übergebene Variablen sind als "" gekennzeichnet. <br>
        Das erwartete Rückgabeformat einer Variable wird in "()" angegeben sofern sie Restriktionen unterliegt.
        Ansonsten ist die Variable frei verfügbar.        
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> $PRIVAL  </td><td> "" (0 ... 191) </td></tr>
        <tr><td> $FAC     </td><td> "" (0 ... 23) </td></tr>
        <tr><td> $SEV     </td><td> "" (0 ... 7) </td></tr>
        <tr><td> $TS      </td><td> Zeitstempel (YYYY-MM-DD hh:mm:ss) </td></tr>
        <tr><td> $HOST    </td><td> "" </td></tr>
        <tr><td> $DATE    </td><td> "" (YYYY-MM-DD) </td></tr>
        <tr><td> $TIME    </td><td> "" (hh:mm:ss) </td></tr>
        <tr><td> $ID      </td><td> "" </td></tr>
        <tr><td> $PID     </td><td> "" </td></tr>
        <tr><td> $MID     </td><td> "" </td></tr>
        <tr><td> $SDFIELD </td><td> "" </td></tr>
        <tr><td> $CONT    </td><td> "" </td></tr>
        <tr><td> $DATA    </td><td> übergebene Rohdaten der Syslog-Mitteilung (keine Rückgabeauswertung!) </td></tr>
        </table>
        </ul>
	    <br>  

        Die Variablennamen korrespondieren mit den Feldnamen und deren ursprünglicher Bedeutung angegeben im Attribut 
        <b>"parseProfile"</b> (Erläuterung der Felddaten). <br><br>

        <ul>
        <b>Beispiel: </b> <br>
        # Quelltext: '<4> <;4>LAN IP and mask changed to 192.168.2.3 255.255.255.0' <br>
        # Die Zeichen '<;4>' sollen aus dem CONT-Feld entfernt werden
<pre>
{
($PRIVAL,$CONT) = ($DATA =~ /^<(\d{1,3})>\s(.*)$/);
$CONT = (split(">",$CONT))[1] if($CONT =~ /^<.*>.*$/);
} 
</pre>        
        </ul>         
              
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>parseProfile [ BSD | IETF | ParseFn | raw ] </b><br>
        <br>
        Auswahl eines Parsing-Profiles. Das Attribut ist nur für Device-MODEL "Collector" verwendbar.
        <br><br>
    
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> <b>BSD</b>     </td><td> Parsing der Meldungen im BSD-Format nach RFC3164 </td></tr>
        <tr><td> <b>IETF</b>    </td><td> Parsing der Meldungen im IETF-Format nach RFC5424 (default) </td></tr>
        <tr><td> <b>ParseFn</b> </td><td> Verwendung einer eigenen spezifischen Parsingfunktion im Attribut "parseFn". </td></tr>
        <tr><td> <b>raw</b>     </td><td> kein Parsing, die Meldungen werden wie empfangen in ein Event umgesetzt </td></tr>
        </table>
        </ul>
	    <br>

        Die geparsten Informationen werden in Feldern zur Verfügung gestellt. Die im Event erscheinenden Felder und deren 
        Reihenfolge können mit dem Attribut <b>"outputFields"</b> bestimmt werden. <br>
        Abhängig vom verwendeten "parseProfile" werden die folgenden Felder mit Werten gefüllt und es ist dementsprechend auch 
        nur sinnvoll die benannten Felder in Attribut "outputFields" zu verwenden. Im raw-Profil werden die empfangenen Daten
        ohne Parsing in ein Event umgewandelt.
        <br><br>
        
        Die sinnvoll im Attribut "outputFields" verwendbaren Felder des jeweilgen Profils sind: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
	    <tr><td> BSD     </td><td>-> PRIVAL,FAC,SEV,TS,HOST,ID,CONT  </td></tr>
        <tr><td> IETF    </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT  </td></tr>
        <tr><td> ParseFn </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT </td></tr>
        <tr><td> raw     </td><td>-> keine Auswahl sinnvoll, es wird immer die Originalmeldung in einen Event umgesetzt </td></tr>
        </table>
        </ul>
	    <br>   
        
        Erläuterung der Felddaten: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> PRIVAL  </td><td> kodierter Priority Wert (kodiert aus "facility" und "severity")  </td></tr>
        <tr><td> FAC     </td><td> Kategorie (Facility)  </td></tr>
        <tr><td> SEV     </td><td> Schweregrad der Meldung (Severity) </td></tr>
        <tr><td> TS      </td><td> Zeitstempel aus Datum und Zeit (YYYY-MM-DD hh:mm:ss) </td></tr>
        <tr><td> HOST    </td><td> Hostname / Ip-Adresse des Senders </td></tr>
        <tr><td> DATE    </td><td> Datum (YYYY-MM-DD) </td></tr>
        <tr><td> TIME    </td><td> Zeit (hh:mm:ss) </td></tr>
        <tr><td> ID      </td><td> Gerät oder Applikation welche die Meldung gesendet hat  </td></tr>
        <tr><td> PID     </td><td> Programm-ID, oft belegt durch Prozessname bzw. Prozess-ID </td></tr>
        <tr><td> MID     </td><td> Typ der Mitteilung (beliebiger String) </td></tr>
        <tr><td> SDFIELD </td><td> Metadaten über die empfangene Syslog-Mitteilung </td></tr>
        <tr><td> CONT    </td><td> Inhalt der Meldung </td></tr>
        <tr><td> DATA    </td><td> empfangene Rohdaten </td></tr>
        </table>
        </ul>
	    <br>   
              
    </li>
    </ul>
    <br>
	
    <ul>
    <li><b>protocol [ TCP | UDP ]</b><br>
        <br>
        Setzt den Protokolltyp der verwendet werden soll. Es kann UDP oder TCP gewählt werden (MODEL Sender). <br>
		Standard ist "UDP" wenn nichts spezifiziert ist.
        Ein Syslog-Server (MODEL Collector) verwendet UDP.
    </li>
    </ul>
    <br>
	
    <ul>
    <li><b>port &lt;Port&gt;</b><br>
        <br>
        Der verwendete Port. Für einen Sender ist der default-Port 514, für einen Collector (Syslog-Server) der Port 1514.
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>rateCalcRerun &lt;Zeit in Sekunden&gt; </b><br>
        <br>
        Wiederholungszyklus für die Bestimmung der Log-Transferrate (Reading "Transfered_logs_per_minute") in Sekunden (>=60).
        Eingegebene Werte <60 Sekunden werden automatisch auf 60 Sekunden korrigiert.        
		Default sind 60 Sekunden.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>sendSeverity </b><br>
        <br>
        Es werden nur Nachrichten übermittelt, deren Schweregrad im Attribut enthalten ist.
        Ist "sendSeverity" nicht gesetzt, werden Nachrichten aller Schwierigkeitsgrade gesendet.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>ssldebug</b><br>
        <br>
        Debugging Level von SSL Messages. <br><br>
        <ul>
        <li> 0 - Kein Debugging (default).  </li>
        <li> 1 - Ausgabe Errors von from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und ciphers von <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 2 - zusätzliche Ausgabe von Informationen über den Protokollfluss von <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und Fortschritinformationen von <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 3 - zusätzliche Ausgabe einiger Dumps von <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        </ul>
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>TLS</b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar.
        Es wird eine gesicherte Verbindung zum Syslog-Server aufgebaut. Das Protokoll schaltet automatisch
        auf TCP um.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>timeout</b><br>
        <br>
        Das Attribut ist nur für "Sender" verwendbar.
        Timeout für die Verbindung zum Syslog-Server (TCP). Default: 0.5s.
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>verbose</b><br>
        <br>
        Die Ausgaben der Verbose-Level von Log2Syslog-Devices werden ausschließlich im lokalen FHEM Logfile ausgegeben und
		nicht weitergeleitet um Schleifen zu vermeiden.
    </li>
    </ul>
    <br>
    <br>
	
  </ul>
  <br>
	
  <a name="Log2Syslogreadings"></a>
  <b>Readings</b>
  <ul>
  <br> 
    <table>  
    <colgroup> <col width=35%> <col width=65%> </colgroup>
      <tr><td><b>MSG_&lt;Host&gt;</b>               </td><td> die letzte erfolgreich geparste Syslog-Message von &lt;Host&gt; </td></tr>
	  <tr><td><b>SSL_Algorithm</b>                  </td><td> der verwendete SSL Algorithmus wenn SSL eingeschaltet und aktiv ist </td></tr>
      <tr><td><b>SSL_Version</b>                    </td><td> die verwendete TLS-Version wenn die Verschlüsselung aktiv ist</td></tr>
	  <tr><td><b>Transfered_logs_per_minute</b>     </td><td> die durchschnittliche Anzahl der übertragenen/empfangenen Logs/Events pro Minute </td></tr>
    </table>    
    <br>
  </ul>
  
</ul>
=end html_DE
=cut
