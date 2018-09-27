##########################################################################################################################
# $Id: 93_Log2Syslog.pm 17197 2018-08-24 13:45:51Z DS_Starter $
##########################################################################################################################
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
##########################################################################################################################
#  Versions History:
#
# 5.0.1      27.09.2018       Log2Syslog_closesock if write error:.* , delete readings code changed 
# 5.0.0      26.09.2018       TCP-Server in Collector-mode, HIPCACHE added, PROFILE as Internal, Parse_Err_No as reading,
#                             octetCount attribute, TCP-SSL-support, set "reopen" command, code fixes
# 4.8.5      20.08.2018       BSD/parseFn parsing changed, BSD setpayload changed, new variable $IGNORE in parseFn
# 4.8.4      15.08.2018       BSD parsing changed
# 4.8.3      14.08.2018       BSD setpayload changed, BSD parsing changed, Internal MYFQDN 
# 4.8.2      13.08.2018       rename makeMsgEvent to makeEvent
# 4.8.1      12.08.2018       IETF-Syslog without VERSION changed, Log verbose 1 to 2 changed in parsePayload
# 4.8.0      12.08.2018       enhanced IETF Parser to match logs without version 
# 4.7.0      10.08.2018       Parser for TPLink
# 4.6.1      10.08.2018       some perl warnings, changed IETF Parser
# 4.6.0      08.08.2018       set sendTestMessage added, Attribute "contDelimiter", "respectSeverity"
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
use TcpServerUtils;
use Scalar::Util qw(looks_like_number);
use Encode qw(encode_utf8);
# use Net::Domain qw(hostname hostfqdn hostdomain);
eval "use IO::Socket::INET;1" or my $MissModulSocket = "IO::Socket::INET";
eval "use Net::Domain qw(hostname hostfqdn hostdomain domainname);1"  or my $MissModulNDom = "Net::Domain";

###############################################################################
# Forward declarations
#
sub Log2Syslog_Log3slog($$$);

my $Log2SyslogVn = "5.0.1";

# Mappinghash BSD-Formatierung Monat
our %Log2Syslog_BSDMonth = (
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
                      "makeEvent:no,intern,reading ".
                      "outputFields:sortable-strict,PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT ".
                      "parseProfile:BSD,IETF,TPLink-Switch,raw,ParseFn ".
                      "parseFn:textField-long ".
                      "respectSeverity:multiple-strict,Emergency,Alert,Critical,Error,Warning,Notice,Informational,Debug ".
                      "octetCount:1,0 ".
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
  
  $hash->{MYFQDN} = hostfqdn();                            # MYFQDN eigener Host (f. IETF)
  $hash->{MYHOST} = hostname();                            # eigener Host (lt. RFC nur Hostname f. BSD)
  
  if(int(@a)-3 < 0){
      # Einrichtung Servermode (Collector)
      Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - entering Syslog servermode ..."); 
      $hash->{MODEL}        = "Collector";
      $hash->{PROFILE}      = "IETF";                          
      readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);  # Fehlerzähler für Parse-Errors auf 0
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
		
      $hash->{PEERHOST} = $a[2];                            # Destination Host (Syslog Server)
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
  my $hash           = $defs{$name};
  my $err;

  RemoveInternalTimer($hash, "Log2Syslog_initServer");
  return if(IsDisabled($name) || $hash->{SERVERSOCKET});
  
  if($init_done != 1 || Log2Syslog_IsMemLock($hash)) {
      InternalTimer(gettimeofday()+1, "Log2Syslog_initServer", "$name,$global", 0);
	  return;
  }
  # Inititialisierung FHEM ist fertig -> Attribute geladen
  my $port     = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 1514);
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  my $lh = ($global ? ($global eq "global" ? undef : $global) : ($hash->{IPV6} ? "::1" : "127.0.0.1"));
  
  Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Opening socket on interface \"$global\" ...");
  
  if($protocol =~ /udp/) {
      $hash->{SERVERSOCKET} = IO::Socket::INET->new(
        Domain    => ($hash->{IPV6} ? AF_INET6() : AF_UNSPEC), # Linux bug
        LocalHost => $lh,
        Proto     => $protocol,
        LocalPort => $port, 
        ReuseAddr => 1
      ); 
      if(!$hash->{SERVERSOCKET}) {
          $err = "Can't open Syslog Collector at $port: $!";
          Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - $err");
          readingsSingleUpdate ($hash, 'state', $err, 1);
          return;      
      }
      $hash->{FD}   = $hash->{SERVERSOCKET}->fileno();
      $hash->{PORT} = $hash->{SERVERSOCKET}->sockport();           
  } else {
      $lh = "global" if(!$lh);
      my $ret = TcpServer_Open($hash,$port,$lh);
      if($ret) {        
          $err = "Can't open Syslog TCP Collector at $port: $ret";
          Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - $err");
          readingsSingleUpdate ($hash, 'state', $err, 1);
          return; 
      }
  }
  
  $hash->{PROTOCOL}         = $protocol;
  $hash->{SEQNO}            = 1;                            # PROCID wird kontinuierlich pro empfangenen Datensatz hochgezählt
  $hash->{HELPER}{OLDSEQNO} = $hash->{SEQNO};               # Init Sequenznummer f. Ratenbestimmung
  $hash->{INTERFACE}        = $lh?$lh:"global";
  
  Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - port $hash->{PORT}/$protocol opened for Syslog Collector on interface \"$hash->{INTERFACE}\"");
  readingsSingleUpdate ($hash, "state", "initialized", 1);
  delete($readyfnlist{"$name.$port"});
  $selectlist{"$name.$port"} = $hash;

return;
}

########################################################################################################
#                        Syslog Collector Daten empfangen (im Collector-Mode)
#  
#                                        !!!!! Achtung !!!!!
#  Kontextswitch des $hash beachten:  initialer TCP-Server <-> temporärer TCP-Server ohne SERVERSOCKET
#
########################################################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub Log2Syslog_Read($@) {
  my ($hash,$reread) = @_;
  my $socket         = $hash->{SERVERSOCKET};
  my ($err,$sev,$data,$ts,$phost,$pl,$ignore,$st,$len,$evt,$pen);  
  
  return if($init_done != 1);
  
  my $mlen = 8192;                                               # maximale Länge des Syslog-Frames als Begrenzung falls kein EOF
                                                                 # vom Sender initiiert wird (Endlosschleife vermeiden)
  if($hash->{TEMPORARY}) {
      # temporäre Instanz angelegt durch TcpServer_Accept
      $len = 8192;
      ($st,$data,$hash) = Log2Syslog_getifdata($hash,$len,$mlen,$reread);
  }
  
  my $name     = $hash->{NAME};
  return if(IsDisabled($name) || Log2Syslog_IsMemLock($hash));
  my $pp       = AttrVal($name, "parseProfile", "IETF");
  my $mevt     = AttrVal($name, "makeEvent", "intern");          # wie soll Reading/Event erstellt werden
  my $sevevt   = AttrVal($name, "respectSeverity", "");          # welcher Schweregrad soll berücksichtigt werden (default: alle)
    
  if($pp =~ /BSD/) {
      # BSD-Format
          $len = $RFC3164len{DL};
  
  } elsif ($pp =~ /IETF/) {
      # IETF-Format   
          $len = $RFC5425len{DL};     
      
  } else {
      # raw oder User eigenes Format
          $len = 8192;        
  } 
  
  if($socket) {
      ($st,$data,$hash) = Log2Syslog_getifdata($hash,$len,$mlen,$reread);
  }
  
  if($data) {
      # parse Payload 
      my (@load,$mlen,$msg,$tail);
      if($data =~ /^(?<mlen>(\d+))\s(?<tail>.*)/s) {
          # Syslog Sätze mit Octet Count -> Transmission of Syslog Messages over TCP https://tools.ietf.org/html/rfc6587
          my $i = 0;
          $mlen = $+{mlen};
	      $tail = $+{tail};	      
          $msg  = substr($tail,0,$mlen);
          chomp $msg;
          push @load, $msg;
          $tail = substr($tail,$mlen);          
          Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name -> LEN$i: $mlen, MSG$i: $msg, TAIL$i: $tail"); 
          
          while($tail && $tail =~ /^(?<mlen>(\d+))\s(?<tail>.*)/s) {
              $i++;
              $mlen = $+{mlen};
              $tail = $+{tail};	      
              $msg  = substr($tail,0,$mlen);
              chomp $msg;
              push @load, $msg;
              $tail = substr($tail,$mlen);           
              Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name -> LEN$i: $mlen, MSG$i: $msg, TAIL$i: $tail");             
          }   
      } else {
          @load = split("[\r\n]",$data);
      }
 
      foreach my $line (@load) {          
          ($err,$ignore,$sev,$phost,$ts,$pl) = Log2Syslog_parsePayload($hash,$line);       
          $hash->{SEQNO}++;
          if($err) {
              $pen = ReadingsVal($name, "Parse_Err_No", 0);
              $pen++;
              readingsSingleUpdate($hash, 'Parse_Err_No', $pen, 1);
              $st = "parse error - see logfile";
          } elsif ($ignore) {
              Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name -> dataset was ignored by parseFn");
          } else {
              return if($sevevt && $sevevt !~ m/$sev/);            # Message nicht berücksichtigen
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
          $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
          readingsSingleUpdate($hash, "state", $st, $evt);
          $hash->{HELPER}{OLDSTATE} = $st; 
      }
  }
      
return;
}

###############################################################################
#                  Daten vom Interface holen 
#
# Die einzige Aufgabe der Instanz mit SERVERSOCKET ist TcpServer_Accept 
# durchzufuehren (und evtl. noch Statistiken). Durch den Accept wird eine 
# weitere Instanz des gleichen Typs angelegt die eine Verbindung repraesentiert 
# und im ReadFn die eigentliche Arbeit macht:
#
# - ohne SERVERSOCKET dafuer mit CD/FD, PEER und PORT. CD/FD enthaelt den 
#   neuen Filedeskriptor.
# - mit TEMPORARY (damit es nicht gespeichert wird)
# - SNAME verweist auf die "richtige" Instanz, damit man die Attribute 
#   abfragen kann.
# - TcpServer_Accept traegt den neuen Filedeskriptor in die globale %selectlist 
#   ein. Damit wird ReadFn von fhem.pl/select mit dem temporaeren Instanzhash 
#   aufgerufen, wenn Daten genau bei dieser Verbindung anstehen.
#   (sSiehe auch "list TYPE=FHEMWEB", bzw. "man -s2 accept")
# 
###############################################################################
sub Log2Syslog_getifdata($$@) {
  my ($hash,$len,$mlen,$reread)   = @_;
  my $name     = $hash->{NAME};
  my $socket   = $hash->{SERVERSOCKET};
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  if($hash->{TEMPORARY}) {
      # temporäre Instanz abgelegt durch TcpServer_Accept
      $protocol = "tcp";
  }
  my $st = ReadingsVal($name,"state","active");
  my ($data,$ret);
  
  if($socket && $protocol =~ /udp/) { 
      # UDP Datagramm empfangen
      Log2Syslog_Log3slog ($hash, 4, "Log2Syslog $name - ####################################################### ");
      Log2Syslog_Log3slog ($hash, 4, "Log2Syslog $name - #########        new Syslog UDP Parsing       ######### ");
      Log2Syslog_Log3slog ($hash, 4, "Log2Syslog $name - ####################################################### ");      
      unless($socket->recv($data, $len)) {
          Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Seq \"$hash->{SEQNO}\" invalid data: $data"); 
          $data = '' if(length($data) == 0);
          $st = "receive error - see logfile";
      }              
  } elsif ($protocol =~ /tcp/) {
      if($hash->{SERVERSOCKET}) {   # Accept and create a child
          my $nhash = TcpServer_Accept($hash, "Log2Syslog");
          return ($st,$data,$hash) if(!$nhash);
          $nhash->{CD}->blocking(0);
		  if($nhash->{SSL}) {
		      my $sslver  = $nhash->{CD}->get_sslversion();
		      my $sslalgo = $nhash->{CD}->get_fingerprint(); 
			  readingsSingleUpdate($hash, "SSL_Version", $sslver, 1);
			  readingsSingleUpdate($hash, "SSL_Algorithm", $sslalgo, 1);	  
		  }
		  return ($st,$data,$hash);
      }

      my $sname = $hash->{SNAME};
      my $cname = $hash->{NAME};
      my $shash = $defs{$sname};    # Hash des Log2Syslog-Devices bei temporärer TCP-Serverinstanz
      
      Log2Syslog_Log3slog ($shash, 4, "Log2Syslog $sname - ####################################################### ");
      Log2Syslog_Log3slog ($shash, 4, "Log2Syslog $sname - #########        new Syslog TCP Parsing       ######### ");
      Log2Syslog_Log3slog ($shash, 4, "Log2Syslog $sname - ####################################################### ");
      Log2Syslog_Log3slog ($shash, 4, "Log2Syslog $sname - childname: $cname");
      $st       = ReadingsVal($sname,"state","active");
      my $c = $hash->{CD};
      if($c) {
          $shash->{HELPER}{TCPPADDR} = $hash->{PEER};
          if(!$reread) {
              my $buf;  	  		  
              my $off = 0;
              $ret = sysread($c, $buf, $len);  # returns undef on error, 0 at end of file and Integer, number of bytes read on success.                
              
              if(!defined($ret) && $! == EWOULDBLOCK ){
			      # error
                  $hash->{wantWrite} = 1 if(TcpServer_WantWrite($hash));
                  $hash = $shash;
                  return ($st,undef,$hash); 

              } elsif (!$ret) {
			      # end of file
                  CommandDelete(undef, $cname); 
                  $hash = $shash;
                  Log2Syslog_Log3slog ($shash, 4, "Log2Syslog $sname - Connection closed for $cname: ".(defined($ret) ? 'EOF' : $!));
                  return ($st,undef,$hash); 
              
              }
              $hash->{BUF} .= $buf;
              
              if($hash->{SSL} && $c->can('pending')) {
                  while($c->pending()) {
                      sysread($c, $buf, 1024);
                      $hash->{BUF} .= $buf;
                  }
              }
              
              $data = $hash->{BUF};
              delete $hash->{BUF};
              $hash = $shash;
              Log2Syslog_Log3slog ($shash, 5, "Log2Syslog $sname - Buffer content:\n$data");         
          }
      }
      
  } else {
      $st = "error - no socket opened";
      $data = '';
  }

return ($st,$data,$hash); 
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
  my $ignore       = 0;
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
  
  # Sender Host / IP-Adresse ermitteln, $phost wird Reading im Event
  my ($phost) = Log2Syslog_evalPeer($hash);
  
  Log2Syslog_Log3slog ($hash, 4, "Log2Syslog $name - raw message -> $data");
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);       # Istzeit Ableitung
  $year = $year+1900;
  
  if ($pp =~ /raw/) {
      Log2Syslog_Log3slog($name, 4, "$name - $data");
      $ts = TimeNow();
      $pl = $data;
  
  } elsif ($pp eq "BSD") { 
      # BSD Protokollformat https://tools.ietf.org/html/rfc3164
      # Beispiel data "<$prival>$month $day $time $myhost $id: $otp"
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
          $tail =~ /^(?<id>(\w*))?(?<cont>(\[\w*\]:|:\s).*)$/; 
          $id   = $+{id};            # should
          if($id) {
              $id   = substr($id,0, ($RFC3164len{TAG}-1));           # Länge TAG-Feld nach RFC begrenzen
              $cont = $+{cont};      # should
          } else {
              $cont = $tail;
          }
      } else {
          # andernfalls eher kein Standardaufbau
          $cont = $tail;
      }

      if(!$prival) {
          $err = 1;
          Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name - error parse msg -> $data");  
      } else {
          $cont =~ s/^(:\s*)(.*)$/$2/;
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
      # Beispiel data "<14>1 2018-08-09T21:45:08+02:00 SDS1 Connection - - [synolog@6574 synotype="Connection" luser="apiuser" event="User [apiuser\] logged in from [192.168.2.45\] via [DSM\]."][meta sequenceId="1"] ﻿apiuser: User [apiuser] logged in from [192.168.2.45] via [DSM].";
      # $data =~ /^<(?<prival>\d{1,3})>(?<ietf>\d+)\s(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})\S*\s(?<host>\S*)\s(?<id>\S*)\s(?<pid>\S*)\s(?<mid>\S*)\s(?<sdfield>(\[.*?(?!\\\]).\]|-))\s(?<cont>.*)$/;
      $data =~ /^<(?<prival>\d{1,3})>(?<ietf>\d{0,2})\s(?<cont>.*)$/;
      $prival  = $+{prival};      # must
      $ietf    = $+{ietf};        # should      
      
      if($prival && $ietf) {
          # Standard IETF-Syslog incl. VERSION
          if($ietf == 1) {
              $data =~ /^<(?<prival>\d{1,3})>(?<ietf>\d{0,2})\s?(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})\S*\s(?<host>\S*)\s(?<id>\S*)\s?(?<pid>\S*)\s?(?<mid>\S*)\s?(?<sdfield>(\[.*?(?!\\\]).\]|-))\s(?<cont>.*)$/;      
              $prival  = $+{prival};      # must
              $ietf    = $+{ietf};        # should
              $date    = $+{date};        # must
              $time    = $+{time};        # must
              $host    = $+{host};        # should 
              $id      = $+{id};          # should
              $pid     = $+{pid};         # should
              $mid     = $+{mid};         # should 
              $sdfield = $+{sdfield};     # must
              $cont    = $+{cont};        # should
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - new IETF version detected, inform Log2Syslog Maintainer");          
          }
      } else {
          # IETF-Syslog ohne VERSION
          $data =~ /^<(?<prival>\d{1,3})>(?<date>\d{4}-\d{2}-\d{2})T(?<time>\d{2}:\d{2}:\d{2})\S*\s(?<host>\S*)\s(?<id>\S*)\s?(?<pid>\S*)\s?(?<mid>\S*)\s?(?<sdfield>(\[.*?(?!\\\]).\]|-))?\s(?<cont>.*)$/;
          $prival  = $+{prival};      # must
          $date    = $+{date};        # must
          $time    = $+{time};        # must
          $host    = $+{host};        # should 
          $id      = $+{id};          # should
          $pid     = $+{pid};         # should
          $mid     = $+{mid};         # should 
          $sdfield = $+{sdfield};     # should
          $cont    = $+{cont};        # should                        
      }      
      
      if(!$prival || !$date || !$time) {
          $err = 1;
          Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name - error parse msg -> $data");  
	      no warnings 'uninitialized'; 
          Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name - parsed fields -> PRI: $prival, IETF: $ietf, DATE: $date, TIME: $time, HOST: $host, ID: $id, PID: $pid, MID: $mid, SDFIELD: $sdfield, CONT: $cont");
		  use warnings;          
      } else {
          $ts = "$date $time";
      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name - error parse msg -> $data");          
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
  
  } elsif ($pp eq "TPLink-Switch") {
	  # Parser für TPLink Switch
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
          Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name - error parse msg -> $data");           
      } else {
          $ts      = "$date $time";
      
          if(looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name - error parse msg -> $data");          
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
  
  } elsif ($pp eq "ParseFn") {
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
          my $IGNORE       = 0;

 	      eval $parseFn;
          if($@) {
              Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name -> error parseFn: $@"); 
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
          $ignore  = $IGNORE if($IGNORE =~ /\d/);
          
          if($prival && looks_like_number($prival)) {
              $facility = int($prival/8) if($prival >= 0 && $prival <= 191);
              $severity = $prival-($facility*8);
     	      $fac = $Log2Syslog_Facility{$facility};
              $sev = $Log2Syslog_Severity{$severity};
          } else {
              $err = 1;
              Log2Syslog_Log3slog ($hash, 2, "Log2Syslog $name - error parse msg -> $data");          
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

return ($err,$ignore,$sev,$phost,$ts,$pl);
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
  
  Log2Syslog_closesock($hash,1);    # Clientsocket schließen 
  Log2Syslog_downServer($hash,1);   # Serversocket schließen, kill children

return undef;
}

###############################################################################
#                         Collector-Socket schließen
###############################################################################
sub Log2Syslog_downServer($;$) {
  my ($hash,$delchildren)   = @_;
  my $name     = $hash->{NAME};
  my $port     = $hash->{PORT};
  my $protocol = $hash->{PROTOCOL};
  my $ret;
  
  return if(!$hash->{SERVERSOCKET} || $hash->{MODEL} !~ /Collector/);
  Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Closing server socket $protocol/$port ...");
  
  if($protocol =~ /tcp/) {
      TcpServer_Close($hash);
      delete($hash->{CONNECTS});
      delete($hash->{SERVERSOCKET});
      
      if($delchildren) {
          my @children = devspec2array($name."_.*");
          foreach (@children) {
              my $child = $_;
              if($child ne $name."_.*") {
                  CommandDelete(undef, $child); 
                  Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - child instance $child deleted."); 
              }
          }
		  delete($hash->{HELPER}{SSLALGO});
	      delete($hash->{HELPER}{SSLVER});
		  readingsSingleUpdate($hash, "SSL_Version", "n.a.", 1);
	      readingsSingleUpdate($hash, "SSL_Algorithm", "n.a.", 1);
      }
      return;
  }
  
  $ret = $hash->{SERVERSOCKET}->close();  
  
  Log2Syslog_Log3slog ($hash, 1, "Log2Syslog $name - Can't close Syslog Collector at port $port: $!") if(!$ret);
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
                "reopen:noArg ".	
                (($hash->{MODEL} =~ /Sender/)?"sendTestMessage ":"")
                ;
  
  return if(AttrVal($name, "disable", "") eq "1");
  
  if($opt =~ /sendTestMessage/) {
      my $own;
      if ($prop) {
          shift @a;
          shift @a;
          $own = join(" ",@a);     
      }
	  Log2Syslog_sendTestMsg($hash,$own);
  
  } elsif($opt =~ /reopen/) {
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "Log2Syslog_deleteMemLock", $hash, 0);     
        
        Log2Syslog_closesock($hash,1);                                                         # Clientsocket schließen
        Log2Syslog_downServer($hash,1);                                                        # Serversocket schließen     
        if($hash->{MODEL} =~ /Collector/) {                                                    # Serversocket öffnen
            InternalTimer(gettimeofday()+0.5, "Log2Syslog_initServer", "$name,global", 0);  
            readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0			
        }
		
  } else {
      return "$setlist";
  }  
  
return undef;
}

###############################################################################
#                                    Get
###############################################################################
sub Log2Syslog_Get($@) {
  my ($hash, @a) = @_;
  return "\"get X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $st;
  my $getlist = "Unknown argument $opt, choose one of ".
                "certinfo:noArg " 
                ;
  
  return if(AttrVal($name, "disable", "") eq "1" || $hash->{MODEL} =~ /Collector/);
  
  my($sock,$cert,@certs);
  if ($opt =~ /certinfo/) {
      if(ReadingsVal($name,"SSL_Version","n.a.") ne "n.a.") {
          ($sock,$st) = Log2Syslog_opensock($hash,0);
		  if($sock) {
		      $cert = $sock->dump_peer_certificate();
		      # Log2Syslog_closesock($hash);
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
    my ($do,$st);
      
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

	if ($cmd eq "set" && $hash->{MODEL} !~ /Collector/ && $aName =~ /parseProfile|parseFn|outputFields|makeEvent/) {
         return "\"$aName\" is only valid for model \"Collector\"";
	}
    
	if ($cmd eq "set" && $hash->{MODEL} =~ /Collector/ && $aName =~ /addTimestamp|contDelimiter|addStateEvent|logFormat|octetCount|ssldebug|timeout/) {
        return "\"$aName\" is only valid for model \"Sender\"";
	}
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            return "Mode \"$aVal\" is only valid for model \"Sender\"" if($aVal eq "maintenance" && $hash->{MODEL} !~ /Sender/);
            $do = $aVal?1:0;
        }
        $do = 0 if($cmd eq "del");
        $st = ($do&&$aVal=~/maintenance/)?"maintenance":($do&&$aVal==1)?"disabled":"initialized";
		
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "Log2Syslog_deleteMemLock", $hash, 0);
		
        if($do==0 || $aVal=~/maintenance/) {
		    if($hash->{MODEL} =~ /Collector/) {
                Log2Syslog_downServer($hash,1);     # Serversocket schließen und wieder öffnen
                InternalTimer(gettimeofday()+0.5, "Log2Syslog_initServer", "$name,global", 0);                 
			} 
		} else {
		    Log2Syslog_closesock($hash,1);          # Clientsocket schließen 
            Log2Syslog_downServer($hash);           # Serversocket schließen
		}         
    }
	
    if ($aName eq "TLS") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do = 0 if($cmd eq "del");
        if ($do == 0) {		
            delete $hash->{SSL};
		} else {
            if($hash->{MODEL} =~ /Collector/) {
                $attr{$name}{protocol} = "TCP" if(AttrVal($name, "protocol", "UDP") ne "TCP");
                TcpServer_SetSSL($hash);
            }
        }
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "Log2Syslog_deleteMemLock", $hash, 0);     
        
        Log2Syslog_closesock($hash,1);                                                         # Clientsocket schließen
        Log2Syslog_downServer($hash,1);                                                        # Serversocket schließen     
        if($hash->{MODEL} =~ /Collector/) {
            InternalTimer(gettimeofday()+0.5, "Log2Syslog_initServer", "$name,global", 0);     # Serversocket öffnen
            readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0			
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
        
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "Log2Syslog_deleteMemLock", $hash, 0);
        
        if($aName =~ /port/ && $hash->{MODEL} =~ /Collector/ && $init_done) {
            return "$aName \"$aVal\" is not valid because privileged ports are only usable by super users. Use a port grater than 1023."  if($aVal < 1024);
            Log2Syslog_downServer($hash,1);                                                      # Serversocket schließen
            InternalTimer(gettimeofday()+0.5, "Log2Syslog_initServer", "$name,global", 0);
            readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0			
        } elsif ($aName =~ /port/ && $hash->{MODEL} !~ /Collector/) {
            Log2Syslog_closesock($hash,1);                                                     # Clientsocket schließen               
        }
	}
    
	if ($aName =~ /protocol/) {
        if($aVal =~ /UDP/) {
            $attr{$name}{TLS} = 0 if(AttrVal($name, "TLS", 0));        
        }
        $hash->{HELPER}{MEMLOCK} = 1;
        InternalTimer(gettimeofday()+2, "Log2Syslog_deleteMemLock", $hash, 0);
        
        if($hash->{MODEL} eq "Collector") {
            Log2Syslog_downServer($hash,1);                                                      # Serversocket schließen
            InternalTimer(gettimeofday()+0.5, "Log2Syslog_initServer", "$name,global", 0);
			readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);                                # Fehlerzähler für Parse-Errors auf 0
        } else {
            Log2Syslog_closesock($hash,1);                                                     # Clientsocket schließen  
        }
	}
    
	if ($cmd eq "set" && $aName =~ /parseFn/) {
         $_[3] = "{$aVal}" if($aVal !~ m/^\{.*\}$/s);
         $aVal = $_[3];
	      my %specials = (
             "%IGNORE"  => "0",
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
    
	if ($aName =~ /parseProfile/) {
          if ($cmd eq "set" && $aVal =~ /ParseFn/) {
              return "You have to define a parse-function via attribute \"parseFn\" first !" if(!AttrVal($name,"parseFn",""));
	      }
          if ($cmd eq "set") {
              $hash->{PROFILE} = $aVal;
          } else {
              $hash->{PROFILE} = "IETF";
          }
          readingsSingleUpdate ($hash, 'Parse_Err_No', 0, 1);  # Fehlerzähler für Parse-Errors auf 0
    }
    
    if ($cmd eq "del" && $aName =~ /parseFn/ && AttrVal($name,"parseProfile","") eq "ParseFn" ) {
          return "You use a parse-function via attribute \"parseProfile\". Please change/delete attribute \"parseProfile\" first !";
    }
    
    if ($aName =~ /makeEvent/) {
        foreach my $key(keys%{$defs{$name}{READINGS}}) {
            delete($defs{$name}{READINGS}{$key}) if($key !~ /state|Transfered_logs_per_minute|SSL_.*|Parse_Err_No/);
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
  my $sendsev = AttrVal($name, "respectSeverity", "");              # Nachrichten welcher Schweregrade sollen gesendet werden
  my ($prival,$data,$sock,$pid,$sevAstxt);
  
  if(IsDisabled($name)) {
      $st = AttrVal($name, "disable", "0"); 
	  $st = ($st =~ /maintenance/)?$st:"disabled";
	  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
	  readingsSingleUpdate($hash, "state", $st, $evt);
	  $hash->{HELPER}{OLDSTATE} = $st;
      return;
  }
  
  if($init_done != 1 || !$rex || $hash->{MODEL} !~ /Sender/ || Log2Syslog_IsMemLock($hash)) {
      return;
  }
  
  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  return if(!$events);

  my $n   = $dev->{NAME};
  my $max = int(@{$events});
  my $tn  = $dev->{NTFY_TRIGGERTIME};
  my $ct  = $dev->{CHANGETIME};
  
  ($sock,$st) = Log2Syslog_opensock($hash,0);
	
  if($sock) { 
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
                  # nicht senden wenn Severity nicht in "respectSeverity" enthalten
                  Log2Syslog_Log3slog($name, 5, "Log2Syslog $name - Warning - Payload NOT sent due to Message Severity not in attribute \"respectSeverity\"\n");
                  next;        
              }

	          ($data,$pid) = Log2Syslog_setpayload($hash,$prival,$date,$time,$otp,"event");	
              next if(!$data);			  
          
			  my $ret = syswrite ($sock,$data);
			  if($ret && $ret > 0) {      
				  Log2Syslog_Log3slog($name, 4, "Log2Syslog $name - Payload sequence $pid sent\n");	
              } else {
                  my $err = $!;
				  Log2Syslog_Log3slog($name, 3, "Log2Syslog $name - Warning - Payload sequence $pid NOT sent: $err\n");	
                  $st = "write error: $err";                 
			  }
          }
      } 
   
      Log2Syslog_closesock($hash) if($st =~ /^write error:.*/);
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
  my $sendsev = AttrVal($name, "respectSeverity", "");              # Nachrichten welcher Schweregrade sollen gesendet werden
  my ($prival,$sock,$err,$ret,$data,$pid,$sevAstxt);
  
  if(IsDisabled($name)) {
      $st = AttrVal($name, "disable", "1"); 
	  $st = ($st =~ /maintenance/)?$st:"disabled";
	  my $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
	  readingsSingleUpdate($hash, "state", $st, $evt);
	  $hash->{HELPER}{OLDSTATE} = $st;
      return;
  }
  
  if($init_done != 1 || !$rex || $hash->{MODEL} !~ /Sender/ || Log2Syslog_IsMemLock($hash)) {
      return;
  }
	
  my ($date,$time,$vbose,undef,$txt) = split(" ",$raw,5);
  $txt = Log2Syslog_charfilter($hash,$txt);
  $date =~ s/\./-/g;
  my $tim = $date." ".$time;
  
  if($txt =~ m/^$rex$/ || "$vbose: $txt" =~ m/^$rex$/) {  	
      my $otp             = "$vbose: $txt";
      $otp                = "$tim $otp" if AttrVal($name,'addTimestamp',0);
	  ($prival,$sevAstxt) = Log2Syslog_setprival($txt,$vbose);
      if($sendsev && $sendsev !~ m/$sevAstxt/) {
          # nicht senden wenn Severity nicht in "respectSeverity" enthalten
          Log2Syslog_Log3slog($name, 5, "Log2Syslog $name - Warning - Payload NOT sent due to Message Severity not in attribute \"respectSeverity\"\n");
          return;        
      }
	  
      ($data,$pid) = Log2Syslog_setpayload($hash,$prival,$date,$time,$otp,"fhem");	
	  return if(!$data);
      
      ($sock,$st) = Log2Syslog_opensock($hash,0);
	  
      if ($sock) {
	      $ret = syswrite($sock,$data) if($data);
		  if($ret && $ret > 0) {  
		      Log2Syslog_Log3slog($name, 4, "Log2Syslog $name - Payload sequence $pid sent\n");	
          } else {
              my $err = $!;
			  Log2Syslog_Log3slog($name, 3, "Log2Syslog $name - Warning - Payload sequence $pid NOT sent: $err\n");	
              $st = "write error: $err";             
	      }  
          
          Log2Syslog_closesock($hash) if($st =~ /^write error:.*/);
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
  my ($prival,$ts,$sock,$tim,$date,$time,$err,$ret,$data,$pid,$otp);
  
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
    
  ($sock,$st) = Log2Syslog_opensock($hash,0);
	  
  if ($sock) {
	  $ret = syswrite $sock, $data."\n" if($data);
	  if($ret && $ret > 0) {  
	      Log2Syslog_Log3slog($name, 4, "$name - Payload sequence $pid sent\n");
          $st = "maintenance";          
      } else {
          my $err = $!;
	      Log2Syslog_Log3slog($name, 3, "$name - Warning - Payload sequence $pid NOT sent: $err\n");	
          $st = "write error: $err";              
	  }  
      
      Log2Syslog_closesock($hash) if($st =~ /^write error:.*/);
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
sub Log2Syslog_opensock ($;$$) { 
  my ($hash,$supresslog)   = @_;
  my $name     = $hash->{NAME};
  my $host     = $hash->{PEERHOST};
  my $port     = AttrVal($name, "TLS", 0)?AttrVal($name, "port", 6514):AttrVal($name, "port", 514);
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  my $st       = ReadingsVal($name,"state","active");
  my $timeout  = AttrVal($name, "timeout", 0.5);
  my $ssldbg   = AttrVal($name, "ssldebug", 0);
  my ($sock,$lo,$lof,$sslver,$sslalgo);
  
  return undef if($init_done != 1 || $hash->{MODEL} !~ /Sender/);
  
  if($hash->{CLIENTSOCKET}) {
      return($hash->{CLIENTSOCKET},$st);
  }
  
  Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Opening client socket on port \"$port\" ...") if(!$supresslog);
 
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
			      $lof     = "Socket opened for Host: $host, Protocol: $protocol, Port: $port, TLS: 1";
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
          $lo = "Socket not opened: $!";
      } else {
          $sock->blocking(0);
          $st = "active";
          # Logausgabe (nur in das fhem Logfile !)
          $lof = "Socket opened for Host: $host, Protocol: $protocol, Port: $port, TLS: 0";
      }
  }
  
  if($sslver ne $hash->{HELPER}{SSLVER}) {
      readingsSingleUpdate($hash, "SSL_Version", $sslver, 1);
	  $hash->{HELPER}{SSLVER} = $sslver;
  }
  
  if($sslalgo ne $hash->{HELPER}{SSLALGO}) {
      readingsSingleUpdate($hash, "SSL_Algorithm", $sslalgo, 1);
	  $hash->{HELPER}{SSLALGO} = $sslalgo;
  }
  
  Log2Syslog_Log3slog($name, 3, "Log2Syslog $name - $lo") if($lo);
  Log2Syslog_Log3slog($name, 3, "Log2Syslog $name - $lof") if($lof && !$supresslog && !$hash->{CLIENTSOCKET});
  
  $hash->{CLIENTSOCKET} = $sock if($sock);
    
return($sock,$st);
}

###############################################################################
#                          Socket schließen
###############################################################################
sub Log2Syslog_closesock($;$$) {
  my ($hash,$dolog) = @_;
  my $name = $hash->{NAME};
  my $st   = "closed";
  my $evt;

  my $sock = $hash->{CLIENTSOCKET};
  if($sock) {
      Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Closing client socket ...") if($dolog);
      shutdown($sock, 1);
      if(AttrVal($hash->{NAME}, "TLS", 0) && ReadingsVal($name,"SSL_Algorithm", "n.a.") ne "n.a.") {
          $sock->close(SSL_no_shutdown => 1);
          $hash->{HELPER}{SSLVER}  = "n.a.";
          $hash->{HELPER}{SSLALGO} = "n.a.";
          readingsSingleUpdate($hash, "SSL_Version", "n.a.", 1);
          readingsSingleUpdate($hash, "SSL_Algorithm", "n.a.", 1);
      } else {
          $sock->close();
      }
      Log2Syslog_Log3slog ($hash, 3, "Log2Syslog $name - Client socket closed ...") if($dolog);

      delete($hash->{CLIENTSOCKET});
      
      if($dolog) {
          $evt = ($st eq $hash->{HELPER}{OLDSTATE})?0:1;
          readingsSingleUpdate($hash, "state", $st, $evt);
          $hash->{HELPER}{OLDSTATE} = $st;
      }
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
  my $myfqdn = $hash->{MYFQDN}?$hash->{MYFQDN}:"0.0.0.0";
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
      $ident = $ident.$tag."[$pid]:";
      $data  = "<$prival>$month $day $time $myhost $ident$otp";
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
      $myfqdn = substr($myfqdn,0, ($RFC5425len{HST}-1));
      
      no warnings 'uninitialized';
      if ($IETFver == 1) {
          $data = "<$prival>$IETFver $tim $myfqdn $ident $pid $mid $sdfield $tag$otp";
      }
	  use warnings;
  }
  
  if($data =~ /\s$/) {$data =~ s/\s$//;}
  $data = $data."\n";
  my $dl = length($data);                               # Länge muss ! für TLS stimmen, sonst keine Ausgabe !
  
  # wenn Transport Layer Security (TLS) -> Transport Mapping for Syslog https://tools.ietf.org/pdf/rfc5425.pdf
  # oder Octet counting -> Transmission of Syslog Messages over TCP https://tools.ietf.org/html/rfc6587
  if(AttrVal($name, "TLS", 0) || AttrVal($name, "octetCount", 0)) { 
      $data = "$dl $data";
	  Log2Syslog_Log3slog($name, 4, "$name - Payload created with octet count length: ".$dl); 
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
  my ($hash)   = @_;
  my $name     = $hash->{NAME};
  my $socket   = $hash->{SERVERSOCKET};
  my $protocol = lc(AttrVal($name, "protocol", "udp"));
  if($hash->{TEMPORARY}) {
      # temporäre Instanz abgelegt durch TcpServer_Accept
      $protocol = "tcp";
  } 
  my ($phost,$paddr,$pport, $pipaddr);
  
  no warnings 'uninitialized';
  if($protocol =~ /tcp/) {
      $pipaddr = $hash->{HELPER}{TCPPADDR};    # gespeicherte IP-Adresse 
      $phost = $hash->{HIPCACHE}{$pipaddr};    # zuerst IP/Host-Kombination aus Cache nehmen falls vorhanden     
      if(!$phost) {
          $paddr = inet_aton($pipaddr);      
          $phost = gethostbyaddr($paddr, AF_INET);
          $hash->{HIPCACHE}{$pipaddr} = $phost if($phost);
      }
  } elsif ($protocol =~ /udp/ && $socket) {
      # Protokoll UDP
      ($pport, $paddr) = sockaddr_in($socket->peername) if($socket->peername);
      $pipaddr = inet_ntoa($paddr) if($paddr);
      $phost = $hash->{HIPCACHE}{$pipaddr};    # zuerst IP/Host-Kombination aus Cache nehmen falls vorhanden   
      if(!$phost) {  
          $phost = gethostbyaddr($paddr, AF_INET);
          $hash->{HIPCACHE}{$pipaddr} = $phost if($phost);
      }
  }
  Log2Syslog_Log3slog ($hash, 5, "Log2Syslog $name - message peer: $phost,$pipaddr");
  use warnings;
  $phost = $phost?$phost:$pipaddr?$pipaddr:"unknown";

return ($phost); 
}

###############################################################################
#                    Memory-Lock
# - solange gesetzt erfolgt keine Socketöffnung
# - löschen Sperre über Internaltimer
###############################################################################
sub Log2Syslog_IsMemLock($) {
  my ($hash) = @_;
  my $ret    = 0;
 
  $ret = 1 if($hash->{HELPER}{MEMLOCK});

return ($ret); 
}

sub Log2Syslog_deleteMemLock($) {
  my ($hash) = @_;
  
  RemoveInternalTimer($hash, "Log2Syslog_deleteMemLock");
  delete($hash->{HELPER}{MEMLOCK});

return; 
}

1;

=pod
=item helper
=item summary    forward FHEM system logs/events to a syslog server/act as an syslog server
=item summary_DE sendet FHEM Logs/Events an Syslog-Server / agiert als Syslog-Server

=begin html

<a name="Log2Syslog"></a>
<h3>Log2Syslog</h3>
<ul>
  The module sends FHEM systemlog entries and/or FHEM events to an external syslog server or act itself as an Syslog-Server 
  to receive Syslog-messages of other Devices which are able to send Syslog. <br>
  The syslog protocol has been implemented according the specifications of <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> and the TLS transport protocol according to 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>	
  <br>
  
  <b>Prerequisits</b>
  <ul>
    <br/>
    The additional perl modules "IO::Socket::INET" and "IO::Socket::SSL" (if SSL is used) must be installed on your system. <br>
	Install this package from cpan or by <br><br>
    
	<code>apt-get install libio-socket-multicast-perl (only on Debian based installations) </code><br>
  </ul>
  <br>
  
  <a name="Log2Syslogdefine"></a>
  <b>Definition and usage</b>
  <ul>
    <br>
    Depending of the intended purpose a Syslog-Server (MODEL Collector) or a Syslog-Client (MODEL Sender) can be  
    defined. <br>
    The Collector receives messages in Syslog-format of other Devices and hence generates Events/Readings for further 
    processing. The Sender-Device forwards FHEM Systemlog entries and/or Events to an external Syslog-Server. <br>
  </ul>
    
  <br>
  <b><h4> The Collector (Syslog-Server) </h4></b>

  <ul>    
    <b> Definition of a Collector </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog </code><br>
    <br>
    </ul>
    
    The Definition don't need any further parameter.
    In basic setup the Syslog-Server is initialized with Port=1514/UDP and the Parsingprofil "IETF".
    By the <a href="#Log2Syslogattr">attribute</a> "parseProfile" another formats (e.g. BSD) can be selected.
    The Syslog-Server is immediately ready for use, is parsing the Syslog-data accordingly the rules of RFC5424 and 
    generates FHEM-Events from received Syslog-messages (pls. see Eventmonitor for parsed data). <br><br>
	
    <br>
    <b>Example of a Collector: </b><br>
    
    <ul>
    <br>
        <code>define SyslogServer Log2Syslog </code><br>
    <br>
    </ul>
    
    The generated events are visible in the FHEM-Eventmonitor. <br>
    <br>

    Example of generated Events with attribute parseProfile=IETF: <br>
    <br>
    <code>
2018-07-31 17:07:24.382 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: USV state: OL <br>
2018-07-31 17:07:24.858 Log2Syslog SyslogServer HOST: fhem.myds.me || FAC: syslog || SEV: Notice || ID: Prod_event || CONT: HMLAN2 loadLvl: low <br>
    </code> 
    <br>

    To separate fields the string "||" is used. 
    The meaning of the fields in the example is:   
    <br><br>
    
    <ul>  
    <table>  
    <colgroup> <col width=20%> <col width=80%> </colgroup>
	  <tr><td> <b>HOST</b>  </td><td> the Sender of the dataset </td></tr>
      <tr><td> <b>FAC</b>   </td><td> Facility corresponding to RFC5424 </td></tr>
      <tr><td> <b>SEV</b>   </td><td> Severity corresponding to RFC5424 </td></tr>
      <tr><td> <b>ID</b>    </td><td> Ident-Tag </td></tr>
      <tr><td> <b>CONT</b>  </td><td> the message part of the received message </td></tr>
    </table>
    </ul>
	<br>
	
	The timestamp of generated events is parsed from the Syslog-message. If this information isn't delivered, the current
    timestamp of the operating system is used. <br>
	The reading name in the generated event match the parsed hostname from Syslog-message.
	If the message don't contain a hostname, the IP-address of the sender is retrieved from the network interface and 
    the hostname is determined if possible. 
    In this case the determined hostname respectively the IP-address is used as Reading in the generated event.
	<br>
	After definition of a Collectors Syslog-messages in IETF-format according to RFC5424 are expected. If the data are not
    delivered in this record format and can't be parsed, the Reading "state" will contain the message 
	<b>"parse error - see logfile"</b> and the received Syslog-data are printed into the FHEM Logfile in raw-format. The
    reading "Parse_Err_No" contains the number of parse-errors since module start.<br>
	
	By the <a href="#Log2Syslogattr">attribute</a> "parseProfile" you can try to use another predefined parse-profile  
    or you can create an own parse-profile as well. <br><br>
    
    To define an <b>own parse function</b> the 
    "parseProfile = ParseFn" has to be set and with <a href="#Log2Syslogattr">attribute</a> "parseFn" a specific 
    parse function has to be provided. <br>
    The fields used by the event and their sequential arrangement can be selected from a range with 
    <a href="#Log2Syslogattr">attribute</a> "outputFields". Depending from the used parse-profil all or a subset of 
    the available fields can be selected. Further information about it you can find in description of attribute 
    "parseProfile". <br>
    <br>
    The behavior of the event generation can be adapted by <a href="#Log2Syslogattr">attribute</a> "makeEvent". <br>
  </ul>
    
  <br>
  <b><h4> The Sender (Syslog-Client) </h4></b>

  <ul>    
    <b> Definition of a Sender </b>
    <br>
    
    <ul>
    <br>
        <code>define &lt;name&gt; Log2Syslog &lt;destination host&gt; [ident:&lt;ident&gt;] [event:&lt;regexp&gt;] [fhem:&lt;regexp&gt;]</code><br>
    <br>
    </ul>
    
    <ul>  
    <table>  
    <colgroup> <col width=25%> <col width=75%> </colgroup>
	  <tr><td> <b>&lt;destination host&gt;</b> </td><td> host (name or IP-address) where the syslog server is running </td></tr>
      <tr><td> <b>[ident:&lt;ident&gt;]</b>    </td><td> optional program identifier. If not set the device name will be used as default. </td></tr>
      <tr><td> <b>[event:&lt;regexp&gt;]</b>   </td><td> optional regex to filter events for logging </td></tr>
      <tr><td> <b>[fhem:&lt;regexp&gt;]</b>    </td><td> optional regex to filter fhem system log for logging </td></tr>
    </table>
    </ul> 
    
    <br><br>
	    
	After definition the new device sends all new appearing fhem systemlog entries and events to the destination host, 
	port=514/UDP format:IETF, immediately without further settings if the regex for fhem or event is set. <br>
	Without setting a regex, no fhem system log or event log will be forwarded. <br><br>

	The verbose level of FHEM system logs are converted into equivalent syslog severity level. <br>
	Thurthermore the message text will be scanned for signal terms "warning" and "error" (with case insensitivity). 
	Dependent of it the severity will be set equivalent as well. If a severity is already set by verbose level, it will be 
    overwritten by the level according to the signal term found in the message text. <br><br>
	
	<b>Lookup table Verbose-Level to Syslog severity level: </b><br><br>
    <ul>  
    <table>  
    <colgroup> <col width=50%> <col width=50%> </colgroup>
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
   
    <b>Example of a Sender: </b><br>
    
    <ul>
    <br>
    <code>define splunklog Log2Syslog fhemtest 192.168.2.49 ident:Test event:.* fhem:.* </code><br/>
    <br>
    </ul>
    
    All events are forwarded like this exmple of a raw-print of a Splunk Syslog Servers shows:<br/>
    <pre>
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB sql_processing_time: 0.2306
Aug 18 21:06:46 fhemtest.myds.me 1 2017-08-18T21:06:46 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB background_processing_time: 0.2397
Aug 18 21:06:45 fhemtest.myds.me 1 2017-08-18T21:06:45 fhemtest.myds.me Test_event 13339 FHEM [version@Log2Syslog version="4.2.0"] : LogDB CacheUsage: 21
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.760 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - Informations of camera Terrasse retrieved
Aug 18 21:08:27 fhemtest.myds.me 1 2017-08-18T21:08:27.095 fhemtest.myds.me Test_fhem 13339 FHEM [version@Log2Syslog version="4.2.0"] : 4: CamTER - CAMID already set - ignore get camid
    </pre>
    
	The structure of the payload differs dependent of the used logFormat. <br><br>
	
	<b>logFormat IETF:</b> <br><br>
	"&lt;PRIVAL&gt;IETFVERS TIME MYHOST IDENT PID MID [SD-FIELD] :MESSAGE" <br><br> 
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> priority value (coded from "facility" and "severity") </td></tr>
      <tr><td> IETFVERS </td><td> used version of RFC5424 specification </td></tr>
      <tr><td> TIME     </td><td> timestamp according to RFC5424 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> ident-Tag from DEF if set, or else the own device name. The statement will be completed by "_fhem" (FHEM-Log) respectively "_event" (Event-Log). </td></tr>
      <tr><td> PID      </td><td> sequential Payload-ID </td></tr>
      <tr><td> MID      </td><td> fix value "FHEM" </td></tr>
      <tr><td> SD-FIELD </td><td> contains additional iformation about used module version </td></tr>
      <tr><td> MESSAGE  </td><td> the dataset to transfer </td></tr>
    </table>
    </ul>     
    <br>	
	
	<b>logFormat BSD:</b> <br><br>
	"&lt;PRIVAL&gt;MONTH DAY TIME MYHOST IDENT[PID]:MESSAGE" <br><br>
    
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> priority value (coded from "facility" and "severity") </td></tr>
      <tr><td> MONTH    </td><td> month according to RFC3164 </td></tr>
	  <tr><td> DAY      </td><td> day of month according to RFC3164 </td></tr>
	  <tr><td> TIME     </td><td> timestamp according to RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> ident-Tag from DEF if set, or else the own device name. The statement will be completed by "_fhem" (FHEM-Log) respectively "_event" (Event-Log). </td></tr>
      <tr><td> PID      </td><td> the message-id (sequence number) </td></tr>
      <tr><td> MESSAGE  </td><td> the dataset to transfer </td></tr>
    </table>
    </ul>     
    <br>
		
  </ul>
  <br>

  <a name="Log2SyslogSet"></a>
  <b>Set</b>
  <ul>
    <br> 
	
    <ul>
    <li><b>reopen </b><br>
        <br>
        Closes an existing Client/Server-connection and open it again. 
		This command can be helpful in case of e.g. "broken pipe"-errors.
    </li>
    </ul>
    <br>
    
    <ul>
    <li><b>sendTestMessage [&lt;Message&gt;] </b><br>
        <br>
        With device type "Sender" a testmessage can be transfered. The format of the message depends on attribute "logFormat" 
        and contains data in BSD- or IETF-format. 
        Alternatively an own &lt;Message&gt; can be set. This message will be sent in im raw-format without  
        any conversion. The attribute "disable = maintenance" determines, that no data except test messages are sent 
        to the receiver.
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
        Show informations about the server certificate if a TLS-session was created (Reading "SSL_Version" isn't "n.a.").
    </li>
    </ul>
    <br>

  </ul>
  <br>  
  
  <a name="Log2Syslogattr"></a>
  <b>Attributes</b>
  <ul>
    <br>
	
    <ul>
    <a name="addTimestamp"></a>
    <li><b>addTimestamp </b><br>
        <br/>
        The attribute is only usable for device type "Sender".         
        If set, FHEM timestamps will be logged too.<br>
        Default behavior is not log these timestamps, because syslog uses own timestamps.<br>
        Maybe useful if mseclog is activated in FHEM.<br>
        <br>
		
        Example output (raw) of a Splunk syslog server: <br>
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
        The attribute is only usable for device type "Sender".         
        If set, events will be completed with "state" if a state-event appears. <br>
		Default behavior is without getting "state".
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>contDelimiter </b><br>
        <br>
        The attribute is only usable for device type "Sender". 
        You can set an additional character which is straight inserted before the content-field. <br>
        This possibility is useful in some special cases if the receiver need it (e.g. the Synology-Protokollcenter needs the 
        character ":" for proper function).
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>disable [1 | 0 | maintenance] </b><br>
        <br>
        This device will be activated, deactivated respectSeverity set into the maintenance-mode. 
        In maintenance-mode a test message can be sent by the "Sender"-device (pls. see also command "set &lt;name&gt; 
        sendTestMessage").
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>logFormat [ BSD | IETF ]</b><br>
        <br>
        This attribute is only usable for device type "Sender".  
        Set the syslog protocol format. <br>
		Default value is "IETF" if not specified. 
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>makeEvent [ intern | no | reading ]</b><br>
        <br>
        The attribute is only usable for device type "Collector". 
        With this attribute the behavior of the event- and reading generation is  defined. 
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
	    <tr><td> <b>intern</b>   </td><td> events are generated by module intern mechanism and only visible in FHEM eventmonitor. Readings are not created. </td></tr>
        <tr><td> <b>no</b>       </td><td> only readings like "MSG_&lt;hostname&gt;" without event generation are created </td></tr>
        <tr><td> <b>reading</b>  </td><td> readings like "MSG_&lt;hostname&gt;" are created. Events are created dependent of the "event-on-.*"-attributes </td></tr>
        </table>
        </ul> 
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>octetCount </b><br>
        <br>
        The attribute is only usable for device type "Sender". <br>
        If set, the Syslog Framing is changed from Non-Transparent-Framing (default) to Octet-Framing.
        The Syslog-Reciver must support Octet-Framing !
        For further informations see RFC6587 <a href="https://tools.ietf.org/html/rfc6587">"Transmission of Syslog Messages 
        over TCP"</a>. 
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>outputFields </b><br>
        <br>
        The attribute is only usable for device type "Collector".
        By a sortable list the desired fields of generated events can be selected.
        The meaningful usable fields are depending on the attribute <b>"parseProfil"</b>. Their meaning can be found in 
        the description of attribute "parseProfil".
        Is "outputFields" not defined, a predefined set of fields for event generation is used.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>parseFn {&lt;Parsefunktion&gt;} </b><br>
        <br>
        The attribute is only usable for device type "Collector".
        The provided perl function (has to be set into "{}") will be applied to the received Syslog-message. 
        The following variables are commited to the function. They can be used for programming, processing and for 
        value return. Variables which are provided as blank, are marked as "". <br>
        In case of restrictions the expected format of variables return is specified in "()".
        Otherwise the variable is usable for free.        
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> $PRIVAL  </td><td> "" (0 ... 191) </td></tr>
        <tr><td> $FAC     </td><td> "" (0 ... 23) </td></tr>
        <tr><td> $SEV     </td><td> "" (0 ... 7) </td></tr>
        <tr><td> $TS      </td><td> Timestamp (YYYY-MM-DD hh:mm:ss) </td></tr>
        <tr><td> $HOST    </td><td> "" </td></tr>
        <tr><td> $DATE    </td><td> "" (YYYY-MM-DD) </td></tr>
        <tr><td> $TIME    </td><td> "" (hh:mm:ss) </td></tr>
        <tr><td> $ID      </td><td> "" </td></tr>
        <tr><td> $PID     </td><td> "" </td></tr>
        <tr><td> $MID     </td><td> "" </td></tr>
        <tr><td> $SDFIELD </td><td> "" </td></tr>
        <tr><td> $CONT    </td><td> "" </td></tr>
        <tr><td> $DATA    </td><td> provided raw-data of received Syslog-message (no evaluation of value return!) </td></tr>
        <tr><td> $IGNORE  </td><td> 0 (0|1), if $IGNORE==1 the Syslog-dataset is ignored </td></tr>
        </table>
        </ul>
	    <br>  

        The names of the variables corresponding to the field names and their primary meaning  denoted in attribute 
        <b>"parseProfile"</b> (explanation of the field data). <br><br>

        <ul>
        <b>Example: </b> <br>
        # Source text: '<4> <;4>LAN IP and mask changed to 192.168.2.3 255.255.255.0' <br>
        # Task: The characters '<;4>' are to removed from the CONT-field
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
    <li><b>parseProfile [ BSD | IETF | ... | ParseFn | raw ] </b><br>
        <br>
        Selection of a parse profile. The attribute is only usable for device type "Collector".
        <br><br>
    
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> <b>BSD</b>     </td><td> Parsing of messages in BSD-format according to RFC3164 </td></tr>
        <tr><td> <b>IETF</b>    </td><td> Parsing of messages in IETF-format according to RFC5424 (default) </td></tr>
		<tr><td> <b>...</b>     </td><td> further specific parse profiles for selective device are provided </td></tr>
        <tr><td> <b>ParseFn</b> </td><td> Usage of an own specific parse function provided by attribute "parseFn" </td></tr>
        <tr><td> <b>raw</b>     </td><td> no parsing, events are created from the messages as received without conversion </td></tr>
        </table>
        </ul>
	    <br>

        The parsed data are provided in fields. The fields to use for events and their sequence can be defined by  
        attribute <b>"outputFields"</b>. <br>
        Dependent from used "parseProfile" the following fields are filled with values and therefor it is meaningful 
        to use only the namend fields by attribute "outputFields". By the "raw"-profil the received data are not converted 
        and the event is created directly.
        <br><br>
        
        The meaningful usable fields in attribute "outputFields" depending of the particular profil: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
	    <tr><td> BSD     </td><td>-> PRIVAL,FAC,SEV,TS,HOST,ID,CONT  </td></tr>
        <tr><td> IETF    </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT  </td></tr>
        <tr><td> ParseFn </td><td>-> PRIVAL,FAC,SEV,TS,HOST,DATE,TIME,ID,PID,MID,SDFIELD,CONT </td></tr>
        <tr><td> raw     </td><td>-> no selection is meaningful, the original message is used for event creation </td></tr>
        </table>
        </ul>
	    <br>   
        
        Explanation of field data: 
        <br>
        <br>
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> PRIVAL  </td><td> coded Priority value (coded from "facility" and "severity")  </td></tr>
        <tr><td> FAC     </td><td> decoded Facility  </td></tr>
        <tr><td> SEV     </td><td> decoded Severity of message </td></tr>
        <tr><td> TS      </td><td> Timestamp containing date and time (YYYY-MM-DD hh:mm:ss) </td></tr>
        <tr><td> HOST    </td><td> Hostname / Ip-address of the Sender </td></tr>
        <tr><td> DATE    </td><td> Date (YYYY-MM-DD) </td></tr>
        <tr><td> TIME    </td><td> Time (hh:mm:ss) </td></tr>
        <tr><td> ID      </td><td> Device or application what was sending the Syslog-message  </td></tr>
        <tr><td> PID     </td><td> Programm-ID, offen reserved by process name or prozess-ID </td></tr>
        <tr><td> MID     </td><td> Type of message (arbitrary string) </td></tr>
        <tr><td> SDFIELD </td><td> Metadaten about the received Syslog-message </td></tr>
        <tr><td> CONT    </td><td> Content of the message </td></tr>
        <tr><td> DATA    </td><td> received raw-data </td></tr>
        </table>
        </ul>
	    <br>   
              
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>port &lt;Port&gt;</b><br>
        <br>
        The used port. For a Sender the default-port is 514.
        A Collector (Syslog-Server) uses the port 1514 per default.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>protocol [ TCP | UDP ]</b><br>
        <br>
        Sets the socket protocol which should be used. You can choose UDP or TCP. <br>
		Default value is "UDP" if not specified.
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>rateCalcRerun &lt;Zeit in Sekunden&gt; </b><br>
        <br>
        Rerun cycle for calculation of log transfer rate (Reading "Transfered_logs_per_minute") in seconds (>=60).  
        Values less than 60 seconds are corrected to 60 seconds automatically.        
		Default is 60 seconds.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>respectSeverity </b><br>
        <br>
        Messages are only forwarded (Sender) respectively the receipt considered (Collector), whose severity is included 
        by this attribute.
        If "respectSeverity" isn't set, messages of all severity is processed.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>ssldebug</b><br>
        <br>
        Debugging level of SSL messages. The attribute is only usable for device type "Sender". <br><br>
        <ul>
        <li> 0 - No debugging (default).  </li>
        <li> 1 - Print out errors from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and ciphers from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 2 - Print also information about call flow from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and progress information from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 3 - Print also some data dumps from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> and from <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        </ul>
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>TLS</b><br>
        <br>
        A client (Sender) establish a secured connection to a Syslog-Server. 
		A Syslog-Server (Collector) provide to establish a secured connection. 
		The protocol will be switched to TCP automatically.
		<br<br>
		
		Thereby a Collector device can use TLS, a certificate has to be created or available.
		With following steps a certicate can be created: <br><br>
		
		1. in the FHEM basis directory create the directory "certs": <br>
    <pre>
    sudo mkdir /opt/fhem/certs
    </pre>
		
		2. create the SSL certicate: <br>
    <pre>
    cd /opt/fhem/certs
    sudo openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout server-key.pem
	</pre>		
	
		3. set file/directory permissions: <br>
    <pre>
    sudo chown -R fhem:dialout /opt/fhem/certs
    sudo chmod 644 /opt/fhem/certs/*.pem
    sudo chmod 711 /opt/fhem/certs
	</pre>
	
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>timeout</b><br>
        <br>
        This attribute is only usable for device type "Sender".  
        Timeout für die Verbindung zum Syslog-Server (TCP). Default: 0.5s.
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>verbose</b><br>
        <br>
        Please see global <a href="#attributes">attribute</a> "verbose".
        To avoid loops, the output of verbose level of the Log2Syslog-Devices will only be reported into the local FHEM 
        Logfile and not forwarded.
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
      <tr><td><b>MSG_&lt;Host&gt;</b>               </td><td> the last successful parsed Syslog-message from &lt;Host&gt; </td></tr>
	  <tr><td><b>Parse_Err_No</b>                   </td><td> the number of parse errors since start </td></tr>
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
  Das Modul sendet FHEM Systemlog-Einträge und/oder Events an einen externen Syslog-Server weiter oder agiert als 
  Syslog-Server um Syslog-Meldungen anderer Geräte zu empfangen. <br>
  Die Implementierung des Syslog-Protokolls erfolgte entsprechend den Vorgaben von <a href="https://tools.ietf.org/html/rfc5424"> RFC5424 (IETF)</a>,
  <a href="https://tools.ietf.org/html/rfc3164"> RFC3164 (BSD)</a> sowie dem TLS Transport Protokoll nach 
  <a href="https://tools.ietf.org/pdf/rfc5425.pdf"> RFC5425</a>. <br>	
  <br>
  
  <b>Voraussetzungen</b>
  <ul>
    <br/>
    Es werden die Perl Module "IO::Socket::INET" und "IO::Socket::SSL" (wenn SSL benutzt) benötigt und müssen installiert sein. <br>
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
    Der Syslog-Server ist sofort betriebsbereit, parst die Syslog-Daten entsprechend der Richtlinien nach RFC5424 und generiert 
    aus den eingehenden Syslog-Meldungen FHEM-Events (Daten sind im Eventmonitor sichtbar). <br><br>
	
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
	<b>"parse error - see logfile"</b> und die empfangenen Syslog-Daten werden im Logfile im raw-Format ausgegeben. Das Reading
    "Parse_Err_No" enthält die Anzahl der Parse-Fehler seit Modulstart. <br>
	
	In diesem Fall kann mit dem	<a href="#Log2Syslogattr">Attribut</a> "parseProfile" ein anderes vordefiniertes Parse-Profil 
    eingestellt bzw. ein eigenes Profil definiert werden. <br><br>
    
    Zur Definition einer <b>eigenen Parse-Funktion</b> wird 
    "parseProfile = ParseFn" eingestellt und im <a href="#Log2Syslogattr">Attribut</a> "parseFn" eine spezifische 
    Parse-Funktion hinterlegt. <br>
    Die im Event verwendeten Felder und deren Reihenfolge können aus einem Wertevorrat mit dem 
    <a href="#Log2Syslogattr">Attribut</a> "outputFields" bestimmt werden. Je nach verwendeten Parse-Funktion können alle oder
    nur eine Untermenge der verfügbaren Felder verwendet werden. Näheres dazu in der Beschreibung des Attributes "parseProfile". <br>
    <br>
    Das Verhalten der Eventgenerierung kann mit dem <a href="#Log2Syslogattr">Attribut</a> "makeEvent" angepasst werden. <br>
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
	"&lt;PRIVAL&gt;IETFVERS TIME MYHOST IDENT PID MID [SD-FIELD] :MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL     </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> IETFVERS   </td><td> Version der benutzten RFC5424 Spezifikation </td></tr>
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
	"&lt;PRIVAL&gt;MONTH DAY TIME MYHOST IDENT[PID]:MESSAGE" <br><br>
		
    <ul>  
    <table>  
    <colgroup> <col width=10%> <col width=90%> </colgroup>
	  <tr><td> PRIVAL   </td><td> Priority Wert (kodiert aus "facility" und "severity") </td></tr>
      <tr><td> MONTH    </td><td> Monatsangabe nach RFC3164 </td></tr>
	  <tr><td> DAY      </td><td> Tag des Monats nach RFC3164 </td></tr>
	  <tr><td> TIME     </td><td> Zeitangabe nach RFC3164 </td></tr>
      <tr><td> MYHOST   </td><td> Internal MYHOST </td></tr>
      <tr><td> IDENT    </td><td> Ident-Tag aus DEF wenn angegeben, sonst der eigene Devicename. Die Angabe wird mit "_fhem" (FHEM-Log) bzw. "_event" (Event-Log) ergänzt. </td></tr>
      <tr><td> PID      </td><td> Die ID der Mitteilung (= Sequenznummer) </td></tr>
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
    <li><b>reopen </b><br>
        <br>
        Schließt eine bestehende Client/Server-Verbindung und öffnet sie erneut. 
		Der Befehl kann z.B. bei "broken pipe"-Fehlern hilfreich sein.
    </li>
    </ul>
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
        mit übertragen.<br>
        Per default werden die Timestamps nicht im Content-Feld hinzugefügt, da innerhalb der Syslog-Meldungen im IETF- bzw.
        BSD-Format bereits Zeitstempel gemäß RFC-Vorgabe erstellt werden.<br>
        Die Einstellung kann hilfeich sein wenn mseclog in FHEM aktiviert ist.<br>
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
        Das Attribut ist nur für "Sender" verwendbar. Wenn gesetzt, werden state-events mit dem Reading "state" ergänzt.<br>
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
    <li><b>makeEvent [ intern | no | reading ]</b><br>
        <br>
        Das Attribut ist nur für "Collector" verwendbar.  Mit dem Attribut wird das Verhalten der Event- bzw.
        Readinggenerierung festgelegt. 
        <br><br>
        
        <ul>  
        <table>  
        <colgroup> <col width=10%> <col width=90%> </colgroup>
	    <tr><td> <b>intern</b>   </td><td> Events werden modulintern generiert und sind nur im Eventmonitor sichtbar. Readings werden nicht erstellt. </td></tr>
        <tr><td> <b>no</b>       </td><td> es werden nur Readings der Form "MSG_&lt;Hostname&gt;" ohne Eventfunktion erstellt </td></tr>
        <tr><td> <b>reading</b>  </td><td> es werden Readings der Form "MSG_&lt;Hostname&gt;" erstellt. Events werden in Abhängigkeit der "event-on-.*"-Attribute generiert </td></tr>
        </table>
        </ul> 
        
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>octetCount </b><br>
        <br>
        Das Attribut ist nur für "Sender" verfügbar. <br>
        Wenn gesetzt, wird das Syslog Framing von Non-Transparent-Framing (default) in Octet-Framing geändert.
        Der Syslog-Empfänger muss Octet-Framing unterstützen !
        Für weitere Informationen siehe RFC6587 <a href="https://tools.ietf.org/html/rfc6587">"Transmission of Syslog Messages 
        over TCP"</a>. 
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>outputFields </b><br>
        <br>
        Das Attribut ist nur für "Collector" verwendbar.
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
        <tr><td> $IGNORE  </td><td> 0 (0|1), wenn $IGNORE==1 wird der Syslog-Datensatz ignoriert </td></tr>
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
    <li><b>parseProfile [ BSD | IETF | ... | ParseFn | raw ] </b><br>
        <br>
        Auswahl eines Parsing-Profiles. Das Attribut ist nur für Device-MODEL "Collector" verwendbar.
        <br><br>
    
        <ul>  
        <table>  
        <colgroup> <col width=20%> <col width=80%> </colgroup>
	    <tr><td> <b>BSD</b>     </td><td> Parsing der Meldungen im BSD-Format nach RFC3164 </td></tr>
        <tr><td> <b>IETF</b>    </td><td> Parsing der Meldungen im IETF-Format nach RFC5424 (default) </td></tr>
		<tr><td> <b>...</b>     </td><td> Es werden weitere angepasste Parsingprofile für ausgewählte Geräte angeboten </td></tr>
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
    <li><b>protocol [ TCP | UDP ]</b><br>
        <br>
        Setzt den Protokolltyp der verwendet werden soll. Es kann UDP oder TCP gewählt werden. <br>
		Standard ist "UDP" wenn nichts spezifiziert ist.
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
    <li><b>respectSeverity </b><br>
        <br>
        Es werden nur Nachrichten übermittelt (Sender) bzw. beim Empfang berücksichtigt (Collector), deren Schweregrad im 
        Attribut enthalten ist.
        Ist "respectSeverity" nicht gesetzt, werden Nachrichten aller Schweregrade verarbeitet.
    </li>
    </ul>
    <br>
    <br>
    
    <ul>
    <li><b>ssldebug</b><br>
        <br>
        Debugging Level von SSL Messages. Das Attribut ist nur für Device-MODEL "Sender" verwendbar. <br><br>
        <ul>
        <li> 0 - Kein Debugging (default).  </li>
        <li> 1 - Ausgabe Errors von from <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und ciphers von <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 2 - zusätzliche Ausgabe von Informationen über den Protokollfluss von <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und Fortschrittinformationen von <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        <li> 3 - zusätzliche Ausgabe einiger Dumps von <a href="http://search.cpan.org/~sullr/IO-Socket-SSL-2.056/lib/IO/Socket/SSL.pod">IO::Socket::SSL</a> und <a href="http://search.cpan.org/~mikem/Net-SSLeay-1.85/lib/Net/SSLeay.pod">Net::SSLeay</a>. </li>
        </ul>
    </li>
    </ul>
    <br>
    <br>
	
    <ul>
    <li><b>TLS</b><br>
        <br>
        Ein Client (Sender) baut eine gesicherte Verbindung zum Syslog-Server auf. 
		Ein Syslog-Server (Collector) stellt eine gesicherte Verbindung zur Verfügung. 
		Das Protokoll schaltet automatisch auf TCP um.
		<br<br>
		
		Damit ein Collector TLS verwenden kann, muss ein Zertifikat erstellt werden bzw. vorhanden sein.
		Mit folgenden Schritten kann ein Zertifikat erzeugt werden: <br><br>
		
		1. im FHEM-Basisordner das Verzeichnis "certs" anlegen: <br>
    <pre>
    sudo mkdir /opt/fhem/certs
    </pre>
		
		2. SSL Zertifikat erstellen: <br>
    <pre>
    cd /opt/fhem/certs
    sudo openssl req -new -x509 -nodes -out server-cert.pem -days 3650 -keyout server-key.pem
	</pre>		
	
		3. Datei/Verzeichnis-Rechte setzen: <br>
    <pre>
    sudo chown -R fhem:dialout /opt/fhem/certs
    sudo chmod 644 /opt/fhem/certs/*.pem
    sudo chmod 711 /opt/fhem/certs
	</pre>	
		
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
        Verbose-Level entsprechend dem globalen <a href="#attributes">Attribut</a> "verbose".
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
	  <tr><td><b>Parse_Err_No</b>                   </td><td> die Anzahl der Parse-Fehler seit Start </td></tr>
      <tr><td><b>SSL_Algorithm</b>                  </td><td> der verwendete SSL Algorithmus wenn SSL eingeschaltet und aktiv ist </td></tr>
      <tr><td><b>SSL_Version</b>                    </td><td> die verwendete TLS-Version wenn die Verschlüsselung aktiv ist</td></tr>
	  <tr><td><b>Transfered_logs_per_minute</b>     </td><td> die durchschnittliche Anzahl der übertragenen/empfangenen Logs/Events pro Minute </td></tr>
    </table>    
    <br>
  </ul>
  
</ul>
=end html_DE
=cut
