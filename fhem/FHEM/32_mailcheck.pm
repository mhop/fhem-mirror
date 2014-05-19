
# $Id$

# basic idea from https://github.com/justinribeiro/idlemailcheck

package main;

use strict;
use warnings;

use Mail::IMAPClient;
use IO::Socket::SSL;
use IO::Socket::INET;
use IO::File;
use IO::Handle;
use Data::Dumper;

my $mailcheck_hasGPG = 1;
my $mailcheck_hasMIME = 1;

sub
mailcheck_Initialize($)
{
  my ($hash) = @_;


  eval "use MIME::Parser";
  $mailcheck_hasMIME = 0 if($@);

  eval "use Mail::GnuPG";
  $mailcheck_hasGPG = 0 if($@);
  $hash->{ReadFn}   = "mailcheck_Read";

  $hash->{DefFn}    = "mailcheck_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "mailcheck_Notify";
  $hash->{UndefFn}  = "mailcheck_Undefine";
  #$hash->{SetFn}    = "mailcheck_Set";
  $hash->{GetFn}    = "mailcheck_Get";
  $hash->{AttrFn}   = "mailcheck_Attr";
  $hash->{AttrList} = "debug:1 ".
                      "delete_message:1 ".
                      "disable:1 ".
                      "interval ".
                      "logfile ".
                      "nossl:1 ";
  $hash->{AttrList} .= "accept_from " if( $mailcheck_hasMIME && $mailcheck_hasGPG );
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub
mailcheck_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> mailcheck host user password [folder]"  if(@a < 5);

  my $name = $a[0];

  my $host = $a[2];
  my $user = $a[3];
  my $password = $a[4];
  my $folder = $a[5];

  $hash->{tag} = undef;

  $hash->{NAME} = $name;

  $hash->{Host} = $host;
  $hash->{User} = $user;
  $hash->{helper}{PASS} = $password;

  $hash->{Folder} = "INBOX";
  $hash->{Folder} = $folder if( $folder );

  $hash->{HAS_GPG} = $mailcheck_hasGPG;
  $hash->{HAS_MIME} = $mailcheck_hasMIME;

  if( $init_done ) {
    mailcheck_Disconnect($hash);
    mailcheck_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  return undef;
}

sub
mailcheck_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  mailcheck_Connect($hash);
}

sub
mailcheck_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  my $socket;
  if( AttrVal($name, "nossl", 0) ) {
    $socket = IO::Socket::INET->new( PeerAddr => $hash->{Host},
                                     PeerPort => 143, #AttrVal($name, "port", 143)
                                   );
  } else {
    $socket = IO::Socket::SSL->new( PeerAddr => $hash->{Host},
                                    PeerPort => 993, #AttrVal($name, "port", 993)
                                  );
  }

  if($socket) {
    $hash->{STATE} = "Connected";
    $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );

    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;
    Log3 $name, 3, "$name: connected to $hash->{Host}";

    my $client = Mail::IMAPClient->new(
       Socket   => $socket,
       KeepAlive => 'true',
       User     => $hash->{User},
       Password => $hash->{helper}{PASS},
     );

    $client->Debug(AttrVal($name, "debug", 0)) if( $client );
    $client->Debug_fh($hash->{FH}) if( $client && defined($hash->{FH}) );

    if( $client && $client->IsConnected && $client->IsAuthenticated ) {
      $hash->{STATE} = "Logged in";
      $hash->{LAST_LOGIN} = FmtDateTime( gettimeofday() );

      $hash->{CLIENT} = $client;
      Log3 $name, 3, "$name: logged in to $hash->{User}";

      $hash->{HAS_IDLE} = $client->has_capability("IDLE");

      my $interval = AttrVal($name, "interval", 0);
      $interval = $hash->{HAS_IDLE}?60*10:60*1 if( !$interval );
      $hash->{INTERVAL} = $interval;

      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "mailcheck_poll", $hash, 0);

      #if( !$client->has_capability("IDLE") ) {
        #mailcheck_Disconnect($hash);
        #$hash->{STATE} = "IDLE not supported";
        #return undef;
      #}

      $client->Uid(0);
      $client->select($hash->{Folder});

      $hash->{tag} = $client->idle;

    } else {
      mailcheck_Disconnect($hash);
    }
  } else {
    #$hash->{STATE} = "Connected";
    Log3 $name, 3, "$name: failed to connect to $hash->{Host}";
  }
}
sub
mailcheck_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);

  return if( !$hash->{CD} );

  my $client = $hash->{CLIENT};
  $client->done if($client && $client->IsAuthenticated );
  $client->logout if($client && $client->IsConnected);
  delete $hash->{CLIENT};
  $hash->{tag} = undef;
  Log3 $name, 3, "$name: logged out";

  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});
  $hash->{STATE} = "Disconnected";
  Log3 $name, 3, "$name: Disconnected";
  $hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
}

sub
mailcheck_Undefine($$)
{
  my ($hash, $arg) = @_;

  mailcheck_Disconnect($hash);

  return undef;
}

sub
mailcheck_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";
  return "Unknown argument $cmd, choose one of $list";
}

sub
mailcheck_poll($)
{
  my ($hash) = @_;

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "mailcheck_poll", $hash, 0);

  my $client = $hash->{CLIENT};
  if( $client && $client->IsConnected && $client->IsAuthenticated ) {
    $client->done;
    $client->select($hash->{Folder});
    $hash->{tag} = $client->idle;
    $hash->{LAST_POLL} = FmtDateTime( gettimeofday() );
  }
}


sub
mailcheck_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "folders:noArg update:noArg";

  my $client = $hash->{CLIENT};
  if( $cmd eq "folders" ) {
    if( $client && $client->IsConnected && $client->IsAuthenticated ) {
      $client->done;
      my @folders = $client->folders;
      $hash->{tag} = $client->idle;
      return join( "\n", @folders );
    }
    return "not connected";
  } elsif( $cmd eq "update" ) {
      mailcheck_poll($hash);
      return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
mailcheck_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60 if($attrName eq "interval" && $attrVal < 60 && $attrVal != 0);

  if( $attrName eq "debug" ) {
    $attrVal = 1 if($attrVal);

    my $hash = $defs{$name};
    my $client = $hash->{CLIENT};
    $client->Debug($attrVal) if( $client );
  } elsif( $attrName eq "logfile" ) {
    my $hash = $defs{$name};

    close( $hash->{FH} );
    delete $hash->{FH};
    delete $hash->{currentlogfile};

    if( $cmd eq "set" ) {
        my @t = localtime;
        my $f = ResolveDateWildcards($attrVal, @t);
        my $fh = new IO::File ">>$f";
        if( defined($fh) ) {
          Log3 $name, 3, "$name: logging to $f";

          $fh->autoflush(1);

          $hash->{FH} = $fh;
          $hash->{currentlogfile} = $f;

          my $client = $hash->{CLIENT};
          $client->Debug_fh($fh) if( $client );
        } else {
          Log3 $name, 3, "$name: can't open log file $f";

          my $client = $hash->{CLIENT};
          $client->Debug_fh(*STDERR) if( $client );
        }
    }
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      mailcheck_Disconnect($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      mailcheck_Disconnect($hash);
      mailcheck_Connect($hash);
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

sub
mailcheck_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $client = $hash->{CLIENT};

  my $ret = $client->idle_data();

  if( !defined($ret) || !$ret ) {
    $hash->{tag} = undef;
    $ret = $client->done;
  }

  foreach my $resp (@$ret) {
    $resp =~ s/\015?\012$//;
    if ( $resp =~ /^\*\s+(\d+)\s+(EXISTS)\b/ ) {
      $resp =~ s/\D//g;

      $client->done;

      my $msg_count = $client->unseen_count||0;
      if ($msg_count > 0) {
        my $from = $client->get_header($resp, "From");
        $from =~ s/<[^>]*>//g; #strip the email, only display the sender's name
        Log3 $name, 4, "from: $from";

        my $subject = $client->get_header($resp, "Subject");
        Log3 $name, 4, "subject: $subject";

        my $do_notify = 1;
        if( $hash->{HAS_MIME} ) {
          my $message = $client->message_string($resp);
          Log3 $name, 5, "message: $message";
          my $parser = new MIME::Parser;
          $parser->tmp_to_core(1);
          $parser->output_to_core(1);
          my $entity = $parser->parse_data($message);
          #Log3 $name, 5, "mime: $entity";

          if( my $accept_from = AttrVal($name, "accept_from", "" ) ) {
            $do_notify = 0;
            if( $hash->{HAS_GPG} ) {
              my $gpg = new Mail::GnuPG();
              if( $gpg->is_signed($entity) ) {
                my ($result,$keyid,$email) = $gpg->verify( $entity );
                if( $result == 0 ) {
                  if( !$keyid && !$email) {
                    Log3 $name, 4, "signature valid";
                    my $result = join "", @{$gpg->{last_message}};
                    ($keyid)  = $result =~ /mittels \S+ ID (.+)$/m;
                    ($email) = $result =~ /Korrekte Signatur von "(.+)"$/m;
                    #($email) = $result =~ /(Korrekte|FALSCHE) Signatur von "(.+)"$/m;
                  }
                  if( !$keyid || !$email ) {
                    Log3 $name, 3, "can't parse gpg result. please fix regex in module.";
                    Log3 $name, 3, Dumper $gpg->{last_message};
                  }

                  $do_notify = 1 if( ",$accept_from," =~/,$keyid,/i );
                  Log3 $name, 3, "sender $keyid not allowed" if( !$do_notify );
                } else {
                  Log3 $name, 3, "invalid signature";
                  Log3 $name, 4, Dumper $gpg->{last_message};
                }
              } else {
                Log3 $name, 3, "message not signed";
              }
            } elsif( $hash->{HAS_SMIME} ) {
            } else {
              Log3 $name, 2, "accept_from is set but Mail::GnuPG and/or S/MIME is not available";
            }
          }

          $entity->head->decode();
          $subject = $entity->head->get('Subject');
          chomp( $subject );
          Log3 $name, 4, "subject decoded: $subject";

        } elsif( my $accept_from = AttrVal($name, "accept_from", "" ) ) {
          Log3 $name, 2, "accept_from is set but MIME::Parser is not available";
        }

        readingsSingleUpdate($hash, "Subject", $subject, 1 ) if( $do_notify );

        $client->delete_message( $resp ) if( AttrVal($name, "delete_message", 0) == 1 );
      }

      $client->idle;

    } elsif ( $resp =~ /^\*\s+(BYE)/ ) {
      mailcheck_Disconnect($hash);
      mailcheck_Connect($hash);

      return undef;
    }
  }

  $hash->{tag} ||= $client->idle;

  unless ( $client->IsConnected ) {
    mailcheck_Disconnect($hash);
    mailcheck_Connect($hash);
  }
}


1;

=pod
=begin html

<a name="mailcheck"></a>
<h3>mailcheck</h3>
<ul>
  Watches a mailbox with imap idle and for each new mail triggers an event with the subject of this mail.<br><br>
  This can be used to send mails *to* FHEM and react to them from a notify. Application scenarios are for example
  a geofencing apps on mobile phones, networked devices that inform about warning or failure conditions by e-mail or
  (with a little logic in FHEM) the absence of regular status messages from such devices and so on.<br><br>

  Notes:
  <ul>
    <li>Mail::IMAPClient and IO::Socket::SSL and IO::Socket::INET hast to be installed on the FHEM host.</li>
    <li>Probably only works reliably if no other mail programm is marking messages as read at the same time.</li>
    <li>If you experience a hanging system caused by regular forced disconnects of your internet provider you
        can disable and enable the mailcheck instance with an <a href="#at">at</a>.</li>
    <li>If MIME::Parser is installed non ascii subjects will be docoded to utf-8</li>
    <li>If MIME::Parser and Mail::GnuPG are installed gpg signatures can be checked and mails from unknown senders can be ignored.</li>
  </ul><br>

  <a name="mailcheck_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; mailcheck &lt;host&gt; &lt;user&gt; &lt;password&gt; [&lt;folder&gt;]</code><br>
    <br>

    Defines a mailcheck device.<br><br>

    Examples:
    <ul>
      <code>define mailcheck mailcheck imap.mail.me.com x.y@me.com</code><br>
    </ul>
  </ul><br>

  <a name="mailcheck_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>Subject<br>
      the subject of the last mail received</li>
  </ul><br>

  <a name="mailcheck_Get"></a>
  <b>Get</b>
  <ul>
    <li>update<br>
      trigger an update</li>
    <li>folders<br>
      list available folders</li>
  </ul><br>

  <a name="mailcheck_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>delete_message<br>
      1 -> delete message after Subject reading is created</li>
    <li>interval<br>
      the interval in seconds used to trigger an update on the connection.
      if idle is supported the defailt is 600, without idle support the default is 60. the minimum is 60.</li>
    <li>nossl<br>
      1 -> don't use ssl.</li><br>
    <li>disable<br>
      1 -> disconnect and stop polling</li>
    <li>debug<br>
      1 -> enables debug output. default target is stdout.</li>
    <li>logfile<br>
      set the target for debug messages if debug is enabled.</li>
    <li>accept_from<br>
      comma separated list of gpg keys that will be accepted for signed messages. Mail::GnuPG and MIME::Parser have to be installed</li>
  </ul>
</ul>

=end html
=cut
