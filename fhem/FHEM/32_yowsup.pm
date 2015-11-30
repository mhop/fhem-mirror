
# $Id$

package main;

use strict;
use warnings;

use Socket;
use IO::Handle;

sub
yowsup_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "yowsup_Read";

  $hash->{DefFn}    = "yowsup_Define";
  $hash->{NotifyFn} = "yowsup_Notify";
  $hash->{UndefFn}  = "yowsup_Undefine";
  $hash->{ShutdownFn}  = "yowsup_Shutdown";
  $hash->{SetFn}    = "yowsup_Set";
  #$hash->{GetFn}    = "yowsup_Get";
  $hash->{AttrFn}   = "yowsup_Attr";
  $hash->{AttrList} = "disable:1 ";
  $hash->{AttrList} .= "cmd home nickname ". $readingFnAttributes;
}

#####################################

sub
yowsup_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> yowsup"  if(@a < 2);

  my $name = $a[0];
  my $number = $a[2];

  if( !defined($number) ) {
    my $d = $modules{yowsup}{defptr}{yowsup};
    return "yowsup MASTER already defined as $d->{NAME}." if( defined($d) && $d->{NAME} ne $name );

    $modules{yowsup}{defptr}{yowsup} = $hash;

    addToDevAttrList( $name, "acceptFrom" );

  } else {
    return "no yowsup MASTER defined." if( !defined($modules{yowsup}{defptr}{yowsup}) );

    my $d = $modules{yowsup}{defptr}{$number};
    return "yowsup $number already defined as $d->{NAME}." if( defined($d) && $d->{NAME} ne $name );

    $modules{yowsup}{defptr}{$number} = $hash;

    addToDevAttrList( $name, "commandPrefix" );
    addToDevAttrList( $name, "allowedCommands" );

    addToDevAttrList( $name, "acceptFrom" ) if( $number =~ m/\./ );

    $hash->{NUMBER} = $number;
  }

  $hash->{NAME} = $name;

  $hash->{NOTIFYDEV} = "global";

  if( $init_done ) {
    yowsup_Disconnect($hash);
    yowsup_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  return undef;
}

sub
yowsup_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  yowsup_Disconnect($hash);
  yowsup_Connect($hash);
}

sub
yowsup_reConnect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "$name: reConnect";

  yowsup_Disconnect($hash);
  yowsup_Connect($hash);
}

sub
yowsup_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( $hash->{NUMBER} );

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  $hash->{PARTIAL} = "";

  my ($yowsup_child, $parent);
  if( socketpair($yowsup_child, $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ) {
    $yowsup_child->autoflush(1);
    $parent->autoflush(1);

    my $pid = fhemFork();

    if(!defined($pid)) {
      close $parent;
      close $yowsup_child;

      my $msg = "$name: Cannot fork: $!";
      Log 1, $msg;
      return $msg;
    }

    if( $pid ) {
      close $parent;

      $hash->{STATE} = "Connected";
      $hash->{CONNECTS}++;

      $hash->{FH} = $yowsup_child;
      $hash->{FD} = fileno($yowsup_child);
      $hash->{PID} = $pid;

      $hash->{WAITING_FOR_LOGIN} = 1;

      $selectlist{$name} = $hash;

    } else {
      close $yowsup_child;

      close STDIN;
      close STDOUT;

      my $fn = $parent->fileno();
      open(STDIN, "<&$fn") or die "can't redirect STDIN $!";
      open(STDOUT, ">&$fn") or die "can't redirect STDOUT $!";

      #select STDIN; $| = 1;
      #select STDOUT; $| = 1;

      #STDIN->autoflush(1);
      STDOUT->autoflush(1);

      close $parent;

      $ENV{PYTHONUNBUFFERED} = 1;

      if( my $home = AttrVal($name, "home", undef ) ) {
        $home = $ENV{'PWD'} if( $home eq 'PWD' );
        $ENV{'HOME'} = $home;
        Log3 $name, 2, "$name: setting \$HOME to $home";
      }

      my $cmd = AttrVal($name, "cmd", "/opt/local/bin/yowsup-cli demos -c /root/config.yowsup --yowsup" );
      Log3 $name, 2, "$name: starting yoswup-cli: $cmd";

      exec split( ' ', $cmd ) or Log3 $name, 1, "exec failed";

      Log3 $name, 1, "set the cmd attribut to: <path1>/yowsup-cli demos -c <path2>/config.yowsup --yowsup";

      POSIX::_exit(0);;
    }

  } else {
    #$hash->{STATE} = "Connected";
    Log3 $name, 3, "$name: socketpair failed";
    InternalTimer(gettimeofday()+20, "yowsup_Connect", $hash, 0);
  }
}

sub
yowsup_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  return undef if( $hash->{NUMBER} );

  RemoveInternalTimer($hash);

  return if( !$hash->{FD} );

  if( $hash->{PID} ) {
    yowsup_Write($hash, '/disconnect' );

    kill( 9, $hash->{PID} );
    waitpid($hash->{PID}, 0);
    delete $hash->{PID};
  }

  close($hash->{FH}) if($hash->{FH});
  delete($hash->{FH});
  delete($hash->{FD});
  delete($selectlist{$name});

  $hash->{STATE} = "Disconnected";
  Log3 $name, 3, "$name: Disconnected";
  $hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
}

sub
yowsup_Undefine($$)
{
  my ($hash, $arg) = @_;

  yowsup_Disconnect($hash);

  if( $hash->{NUMBER} ) {
    delete $modules{yowsup}{defptr}{$hash->{NUMBER}};
  } else {
    delete $modules{yowsup}{defptr}{yowsup};
  }

  return undef;
}
sub
yowsup_Shutdown($)
{
  my ($hash) = @_;

  yowsup_Disconnect($hash);

  return undef;
}


sub
yowsup_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  if( $hash->{NUMBER} ) {
    my $phash = $modules{yowsup}{defptr}{yowsup};
    $list .= "image send" if( $phash->{PID} );

    if( $cmd eq 'image' ) {
      return "MASTER not connected" if( !$phash->{PID} );

      readingsSingleUpdate( $hash, 'sent', 'image: '. join( ' ', @args ), 1 );

      my $number = $hash->{NUMBER};
      $number =~ s/\./-/;

      my $image = shift(@args);

      return yowsup_Write( $phash, "/image send $hash->{NUMBER} $args[0]" );

      return undef;
    } elsif( $cmd eq 'send' ) {
      return "MASTER not connected" if( !$phash->{PID} );

      readingsSingleUpdate( $hash, 'sent', join( ' ', @args ), 1 );

      my $number = $hash->{NUMBER};
      $number =~ s/\./-/;

      return yowsup_Write( $phash, "/message send $number '". join( ' ', @args ) ."'" );

      return undef;
    }

  } else {
    $list .= "image send raw disconnect:noArg " if( $hash->{PID} );
    $list .= "reconnect:noArg";

    if( $cmd eq 'raw' ) {
      return yowsup_Write( $hash, join( ' ', @args ) );

      return undef;

    } elsif( $cmd eq 'image' ) {
      readingsSingleUpdate( $hash, 'sent', 'image: '. join( ' ', @args ), 1 );

      my $number = shift(@args);
      $number =~ s/\./-/;

      my $image = shift(@args);

      return yowsup_Write( $hash, "/image send $number $image '". join( ' ', @args ) ."'" );

      return undef;

    } elsif( $cmd eq 'send' ) {
      readingsSingleUpdate( $hash, 'sent', join( ' ', @args ), 1 );

      my $number = shift(@args);
      $number =~ s/\./-/;

      if( $number =~ m/,/ ) {
        return yowsup_Write( $hash, "/message broadcast $number '". join( ' ', @args ) ."'" );
      } else {
        return yowsup_Write( $hash, "/message send $number '". join( ' ', @args ) ."'" );
      }

      return undef;

    } elsif( $cmd eq 'disconnect' ) {
      yowsup_Disconnect($hash);

      return undef;

    } elsif( $cmd eq 'reconnect' ) {
      yowsup_Disconnect($hash);
      yowsup_Connect($hash);

      return undef;
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}


sub
yowsup_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "devices:noArg";

  if( $cmd eq "devices" ) {
    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
yowsup_Parse($$)
{
  my ($hash,$data) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: parse: $data";

  $hash->{TIME} = TimeNow();
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+60*10, "yowsup_reConnect", $hash, 0);

  if( $data =~ m/\[offline\]:/ ) {
    readingsSingleUpdate( $hash, "state", 'offline', 1 ) if( ReadingsVal($name,'state','' ) ne 'offline' );

    if( $hash->{WAITING_FOR_LOGIN} ) {
      yowsup_Write( $hash, '/L' );
      yowsup_Write( $hash, '/presence available' );

      yowsup_Write( $hash, "/presence name '". AttrVal($name, 'nickname', "") ."'" ) if(defined(AttrVal($name, 'nickname', undef)));

      #yowsup_Write( $hash, '/ping' );

      delete $hash->{WAITING_FOR_LOGIN};
    }

  } elsif( $data =~ m/\[connected\]:/ ) {
    readingsSingleUpdate( $hash, "state", 'connected', 1 ) if( ReadingsVal($name,'state','' ) ne 'connected' );

  } elsif( $data =~ m/Auth: Logged in!/ ) {
    readingsSingleUpdate( $hash, "state", 'logged in', 1 ) if( ReadingsVal($name,'state','' ) ne 'logged in' );

  }

  if( $data =~ m/^CHATSTATE:.*State: (\S*).*From: ([\d-]*)/s ) {
    my $chatstate = $1;
    my $number = $2;
    $number =~ s/-/\./;

    if( my $chash = $modules{yowsup}{defptr}{$number} ) {
      readingsSingleUpdate( $chash, "chatstate", $chatstate, 1 );
    }

  #} elsif( $data =~ m/\[(.*)@.*\((.*)\)\]:\[(.*)\]\s*(.*)/s ) {
  } elsif( $data =~ m/\[(.*)@.*\((.*)\)\]:\[([^\]]*)\]\s*(.*)(\nMessage)/s
    || $data =~ m/\[(.*)@.*\((.*)\)\]:\[([^\]]*)\]\s*(.*)/s ) {

    my $number = $1;
    my $time = $2;
    my $id = $3;
    my $message = $4;
    my $last_sender;

    if( $number =~ m/(\d*)\/(\d*)-(\d*)/ ) {
      $number = "$2.$3";
      $last_sender = $1;
    }

    $message =~ s/\n$//;

    my $chash = $modules{yowsup}{defptr}{$number};
    if( !$chash ) {
      my $accept_from = AttrVal($name, "acceptFrom", undef );
      if( !$accept_from || ",$accept_from," =~/,$number,/ ) {
        my $define = "$number yowsup $number";
        my $cmdret = CommandDefine(undef,$define);
        if($cmdret) {
          Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for number '$number': $cmdret";
        } else {
          #$cmdret = CommandAttr(undef,"$number alias ".$result->{$id}{name});
          $cmdret = CommandAttr(undef,"$number room yowsup");
          #$cmdret = CommandAttr(undef,"$number IODev $name");
        }

        $chash = $modules{yowsup}{defptr}{$number};
      }
    }

    if( $chash ) {
      readingsBeginUpdate($chash);
      if( $last_sender ) {
        readingsBulkUpdate( $chash, "chatstate", "received from: $last_sender" );
      } else {
        readingsBulkUpdate( $chash, "chatstate", "received" );
      }
      readingsBulkUpdate( $chash, "message", $message );
      readingsEndUpdate($chash, 1);

      my $cname = $chash->{NAME};
      if( my $prefix = AttrVal($cname, "commandPrefix", undef ) ) {
        my $cmd;
        if( $prefix eq '0' ) {
        } elsif( $prefix eq '1' ) {
          $cmd = $message;
        } elsif( $message =~ m/^$prefix(.*)/ ) {
          $cmd = $1;
        }

        if( $cmd ) {
          my $accept_from = AttrVal($cname, "acceptFrom", undef );
          if( !$accept_from || $last_sender || ",$accept_from," =~/,$last_sender,/ ) {
            Log3 $name, 3, "$cname: received command: $cmd";

            my $allowed = AttrVal($cname, "allowedCommands", undef );
            my $ret = AnalyzeCommandChain( $hash, $cmd, $allowed );

            Log3 $name, 4, "$cname: command result: $ret";

            my $number = $chash->{NUMBER};
            $number =~ s/\./-/;

            yowsup_Write( $hash, "/message send $number '$ret'" ) if( $ret );

          } else {
            Log3 $cname, 3, "$cname: commands: ". $last_sender?$last_sender:$number ." not allowed";

          }
        }

      } else {
        Log3 $cname, 3, "$cname: commands not allowed";
      }

    } else {
      Log3 $name, 3, "$name: sender: $number not allowed";

    }

  }
}

sub
yowsup_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $ret = sysread($hash->{FH}, $buf, 65536 );

  if(!defined($ret) || $ret <= 0) {
    yowsup_Disconnect( $hash );

    Log3 $name, 3, "$name: read: error during sysread: $!" if(!defined($ret));
    Log3 $name, 3, "$name: read: end of file reached while sysread" if( $ret <= 0);

    InternalTimer(gettimeofday()+10, "yowsup_Connect", $hash, 0);
    return undef;
  }

  yowsup_Parse($hash,$buf);
  return undef;

  my $data = $hash->{PARTIAL};
  Log3 $name, 5, "yowsup/RAW: $data/$buf";
  $data .= $buf;

  $hash->{PARTIAL} = $data;
}

sub
yowsup_Write($$)
{
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  return "not connected" if( !$hash->{PID} );

  #my $ls = chr(226) . chr(128) . chr(168);
  #$data =~ s/\n/$ls/g;

  $data =~ s/\n/\r/g;

  Log3 $name, 3, "$name: sending $data";

  syswrite $hash->{FH}, $data ."\n";

  return undef;
}


sub
yowsup_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    yowsup_Disconnect($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
      $attrVal = 1;

    } else {
      $attr{$name}{$attrName} = 0;
      yowsup_Connect($hash);

    }
  } elsif( $attrName eq "cmd" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" ) {
      $attr{$name}{$attrName} = $attrVal;
    } else {
      delete $attr{$name}{$attrName};
    }

    yowsup_Disconnect($hash);
    yowsup_Connect($hash);
  }


  if( $cmd eq "set" ) {
    if( !defined($orig) || $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

1;

=pod
=begin html

<a name="yowsup"></a>
<h3>yowsup</h3>
<ul>
  Module to interface to the yowsup library to send and recive WhatsApp messages.<br><br>

  Notes:
  <ul>
    <li>Probably only works on linux/unix systems.</li>
  </ul><br>

  <a name="yowsup_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; yowsup</code><br>
    <br>

    Defines a yowsup device.<br><br>

    Examples:
    <ul>
      <code>define WhatsApp yowsup</code><br>
    </ul>
  </ul><br>

  <a name="yowsup_Set"></a>
  <b>Set</b>
  <ul>
    <li>image [&lt;number&gt;] &lt;path&gt; [&lt;text&gt;]<br>
      sends an image with optional text. &lt;number&gt; has to be given if sending via master device.</li>
    <li>send [&lt;numner&gt;] &lt;text&gt;<br>
      sends &lt;text&gt;. &lt;number&gt; has to be given if sending via master device.</li>
  </ul><br>

  <a name="yowsup_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>cmd<br>
      complette commandline to start the  yowsup cli client<br>
      eg: attr WhatsApp cmd /opt/local/bin/yowsup-cli demos -c /root/config.yowsup --yowsup</li>

    <li>home<br>
      set $HOME for the started yowsup process<br>
      PWD -> set to $PWD<br>
      anything else -> use as $HOME</li>

    <li>nickname<br>
      nickname that will be send as sender</li>

    <li>accept_from<br>
      comma separated list of contacts (numbers) from which messages will be accepted</li>

    <li>commandPrefix<br>
      not set -> don't accept commands<br>
      0 -> don't accept commands<br>
      1 -> allow commands, every message is interpreted as a fhem command<br>
      anything else -> if the message starts with this prefix then everything after the prefix is taken as the command</li>

    <li>allowedCommands<br>
      A comma separated list of commands that are allowed from this contact.<br>
      If set to an empty list <code>, (i.e. comma only)</code> no commands are accepted.<br>
      <b>Note: </b>allowedCommands should work as intended, but no guarantee
      can be given that there is no way to circumvent it.</li>
  </ul>
</ul>

=end html
=cut

