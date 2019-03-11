# $Id$

package main;
use strict;
use warnings;
use FHEM::Meta;

sub Installer_Initialize($) {
    my ($modHash) = @_;

    # $modHash->{SetFn}    = "FHEM::Installer::Set";
    $modHash->{GetFn}    = "FHEM::Installer::Get";
    $modHash->{DefFn}    = "FHEM::Installer::Define";
    $modHash->{NotifyFn} = "FHEM::Installer::Notify";
    $modHash->{UndefFn}  = "FHEM::Installer::Undef";
    $modHash->{AttrFn}   = "FHEM::Installer::Attr";
    $modHash->{AttrList} =
        "disable:1,0 "
      . "disabledForIntervals "
      . "updateListReading:1,0 "
      . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $modHash );
}

# define package
package FHEM::Installer;
use strict;
use warnings;
use POSIX;
use FHEM::Meta;

use GPUtils qw(GP_Import);
use JSON;
use Data::Dumper;

# Run before module compilation
BEGIN {
    # Import from main::
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsTimestamp
          defs
          modules
          Log
          Log3
          Debug
          DoTrigger
          CommandAttr
          attr
          AttrVal
          ReadingsVal
          Value
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          RemoveInternalTimer)
    );
}

sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    # Initialize the module and the device
    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    my $name = $a[0];
    my $host = $a[2] ? $a[2] : 'localhost';

    Undef( $hash, undef ) if ( $hash->{OLDDEF} );    # modify

    $hash->{NOTIFYDEV} = "global,$name";

    return "Existing instance: "
      . $modules{ $hash->{TYPE} }{defptr}{localhost}{NAME}
      if ( defined( $modules{ $hash->{TYPE} }{defptr}{localhost} ) );

    $modules{ $hash->{TYPE} }{defptr}{localhost} = $hash;

    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {

        # presets for FHEMWEB
        $attr{$name}{alias} = 'FHEM Installer Status';
        $attr{$name}{devStateIcon} =
'fhem.updates.available:security@red:outdated fhem.is.up.to.date:security@green:outdated .*fhem.outdated.*in.progress:system_fhem_reboot@orange .*in.progress:system_fhem_update@orange warning.*:message_attention@orange error.*:message_attention@red';
        $attr{$name}{group} = 'Update';
        $attr{$name}{icon}  = 'system_fhem';
        $attr{$name}{room}  = 'System';
    }

    # __GetUpdatedata() unless ( defined($coreUpdate) );

    readingsSingleUpdate( $hash, "state", "initialized", 1 )
      if ( ReadingsVal( $name, 'state', 'none' ) ne 'none' );

    return undef;
}

sub Undef($$) {

    my ( $hash, $arg ) = @_;

    my $name = $hash->{NAME};

    if ( exists( $hash->{".fhem"}{subprocess} ) ) {
        my $subprocess = $hash->{".fhem"}{subprocess};
        $subprocess->terminate();
        $subprocess->wait();
    }

    RemoveInternalTimer($hash);

    delete( $modules{installer}{defptr}{ $hash->{HOST} } );
    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);

            readingsSingleUpdate( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "Installer ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "Installer ($name) - enabled";
        }
    }

    elsif ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            return
"check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
              unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "Installer ($name) - disabledForIntervals";
            readingsSingleUpdate( $hash, "state", "disabled", 1 );
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "Installer ($name) - enabled";
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }

    return undef;
}

sub Notify($$) {

    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};
    return if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    Log3 $name, 5, "Installer ($name) - Notify: " . Dumper $events;

    if (
        (
            (
                   grep ( /^DEFINED.$name$/, @{$events} )
                or grep ( /^DELETEATTR.$name.disable$/, @{$events} )
                or grep ( /^ATTR.$name.disable.0$/,     @{$events} )
            )
            and $devname eq 'global'
            and $init_done
        )
        or (
            (
                   grep ( /^INITIALIZED$/, @{$events} )
                or grep ( /^REREADCFG$/,      @{$events} )
                or grep ( /^MODIFIED.$name$/, @{$events} )
            )
            and $devname eq 'global'
        )
      )
    {
        # Load metadata for all modules that are in use
        FHEM::Meta::Load();
    }

    if (
        $devname eq $name
        and (  grep ( /^installed:.successful$/, @{$events} )
            or grep ( /^uninstalled:.successful$/, @{$events} )
            or grep ( /^updated:.successful$/,     @{$events} ) )
      )
    {
        $hash->{".fhem"}{installer}{cmd} = 'outdated';
        AsynchronousExecuteFhemCommand($hash);
    }

    return;
}

#TODO
# - filter out FHEM command modules from FHEMWEB view (+attribute) -> difficult as not pre-loaded
# - disable FHEM automatic link to device instances in output
sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    if ( lc($cmd) eq 'showmoduleinfo' ) {
        return "usage: $cmd MODULE" if ( @args != 1 );

        my $ret = CreateMetadataList( $hash, $cmd, $args[0] );
        return $ret;
    }
    else {
        my $fhemModules;

        foreach ( sort { "\L$a" cmp "\L$b" } keys %modules ) {
            next if ( $_ eq 'Global' );
            $fhemModules .= ',' if ($fhemModules);
            $fhemModules .= $_;
        }

        my $list = "showModuleInfo:FHEM,$fhemModules";

        return "Unknown argument $cmd, choose one of $list";
    }
}

sub Event ($$) {
    my $hash  = shift;
    my $event = shift;
    my $name  = $hash->{NAME};

    return
      unless ( defined( $hash->{".fhem"}{installer}{cmd} )
        && $hash->{".fhem"}{installer}{cmd} =~
        m/^(install|uninstall|update)(?: (.+))/i );

    my $cmd      = $1;
    my $packages = $2;

    my $list;

    foreach my $package ( split / /, $packages ) {
        next
          unless (
            $package =~ /^(?:@([\w-]+)\/)?([\w-]+)(?:@([\d\.=<>]+|latest))?$/ );
        $list .= " " if ($list);
        $list .= $2;
    }

    DoModuleTrigger( $hash, uc($event) . uc($cmd) . " $name $list" );
}

sub DoModuleTrigger($$@) {
    my ( $hash, $eventString, $noreplace, $TYPE ) = @_;
    $hash      = $defs{$hash}  unless ( ref($hash) );
    $noreplace = 1             unless ( defined($noreplace) );
    $TYPE      = $hash->{TYPE} unless ( defined($TYPE) );

    return ''
      unless ( defined($TYPE)
        && defined( $modules{$TYPE} )
        && defined($eventString)
        && $eventString =~
        m/^([A-Za-z\d._]+)(?:\s+([A-Za-z\d._]+)(?:\s+(.+))?)?$/ );

    my $event = $1;
    my $dev   = $2;

    return "DoModuleTrigger() can only handle module related events"
      if ( ( $hash->{NAME} && $hash->{NAME} eq "global" )
        || $dev eq "global" );

    # This is a global event on module level
    return DoTrigger( "global", "$TYPE:$eventString", $noreplace )
      unless ( $event =~
/^INITIALIZED|INITIALIZING|MODIFIED|DELETED|BEGIN(?:UPDATE|INSTALL|UNINSTALL)|END(?:UPDATE|INSTALL|UNINSTALL)$/
      );

    # This is a global event on module level and in device context
    return "$event: missing device name"
      if ( !defined($dev) || $dev eq '' );

    return DoTrigger( "global", "$TYPE:$eventString", $noreplace );
}

###################################
sub ProcessUpdateTimer($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    InternalTimer(
        gettimeofday() + 14400,
        "FHEM::Installer::ProcessUpdateTimer",
        $hash, 0
    );
    Log3 $name, 4, "Installer ($name) - stateRequestTimer: Call Request Timer";

    unless ( IsDisabled($name) ) {
        if ( exists( $hash->{".fhem"}{subprocess} ) ) {
            Log3 $name, 2,
              "Installer ($name) - update in progress, process aborted.";
            return 0;
        }

        readingsSingleUpdate( $hash, "state", "ready", 1 )
          if ( ReadingsVal( $name, 'state', 'none' ) eq 'none'
            or ReadingsVal( $name, 'state', 'none' ) eq 'initialized' );

        if (
            ToDay() ne (
                split(
                    ' ', ReadingsTimestamp( $name, 'outdated', '1970-01-01' )
                )
            )[0]
            or ReadingsVal( $name, 'state', '' ) eq 'disabled'
          )
        {
            $hash->{".fhem"}{installer}{cmd} = 'outdated';
            AsynchronousExecuteFhemCommand($hash);
        }
    }
}

sub CleanSubprocess($) {

    my $hash = shift;

    my $name = $hash->{NAME};

    delete( $hash->{".fhem"}{subprocess} );
    Log3 $name, 4, "Installer ($name) - clean Subprocess";
}

use constant POLLINTERVAL => 1;

sub AsynchronousExecuteFhemCommand($) {

    require "SubProcess.pm";
    my ($hash) = shift;

    my $name = $hash->{NAME};

    my $subprocess = SubProcess->new( { onRun => \&OnRun } );
    $subprocess->{installer} = $hash->{".fhem"}{installer};
    $subprocess->{installer}{host} = $hash->{HOST};
    $subprocess->{installer}{debug} =
      ( AttrVal( $name, 'verbose', 0 ) > 3 ? 1 : 0 );
    my $pid = $subprocess->run();

    readingsSingleUpdate(
        $hash,
        'state',
        'command \'fhem ' . $hash->{".fhem"}{installer}{cmd} . '\' in progress',
        1
    );

    if ( !defined($pid) ) {
        Log3 $name, 1,
          "Installer ($name) - Cannot execute command asynchronously";

        CleanSubprocess($hash);
        readingsSingleUpdate( $hash, 'state',
            'Cannot execute command asynchronously', 1 );
        return undef;
    }

    Event( $hash, "BEGIN" );
    Log3 $name, 4,
      "Installer ($name) - execute command asynchronously (PID= $pid)";

    $hash->{".fhem"}{subprocess} = $subprocess;

    InternalTimer( gettimeofday() + POLLINTERVAL,
        "FHEM::Installer::PollChild", $hash, 0 );
    Log3 $hash, 4, "Installer ($name) - control passed back to main loop.";
}

sub PollChild($) {

    my $hash = shift;

    my $name       = $hash->{NAME};
    my $subprocess = $hash->{".fhem"}{subprocess};
    my $json       = $subprocess->readFromChild();

    if ( !defined($json) ) {
        Log3 $name, 5,
          "Installer ($name) - still waiting ("
          . $subprocess->{lasterror} . ").";
        InternalTimer( gettimeofday() + POLLINTERVAL,
            "FHEM::Installer::PollChild", $hash, 0 );
        return;
    }
    else {
        Log3 $name, 4,
          "Installer ($name) - got result from asynchronous parsing.";
        $subprocess->wait();
        Log3 $name, 4, "Installer ($name) - asynchronous finished.";

        CleanSubprocess($hash);
        PreProcessing( $hash, $json );
    }
}

######################################
# Begin Childprocess
######################################

sub OnRun() {
    my $subprocess = shift;
    my $response   = ExecuteFhemCommand( $subprocess->{installer} );

    my $json = eval { encode_json($response) };
    if ($@) {
        Log3 'Installer OnRun', 3, "Installer - JSON error: $@";
        $json = "{\"jsonerror\":\"$@\"}";
    }

    $subprocess->writeToParent($json);
}

sub ExecuteFhemCommand($) {

    my $cmd = shift;

    my $installer = {};
    $installer->{debug} = $cmd->{debug};

    my $cmdPrefix = '';
    my $cmdSuffix = '';

    if ( $cmd->{host} =~ /^(?:(.*)@)?([^:]+)(?::(\d+))?$/
        && lc($2) ne "localhost" )
    {
        my $port = '';
        if ($3) {
            $port = "-p $3 ";
        }

        # One-time action to add remote hosts key.
        # If key changes, user will need to intervene
        #   and cleanup known_hosts file manually for security reasons
        $cmdPrefix =
            'KEY=$(ssh-keyscan -t ed25519 '
          . $2
          . ' 2>/dev/null); '
          . 'grep -q -E "^${KEY% *}" ${HOME}/.ssh/known_hosts || echo "${KEY}" >> ${HOME}/.ssh/known_hosts; ';
        $cmdPrefix .=
            'KEY=$(ssh-keyscan -t rsa '
          . $2
          . ' 2>/dev/null); '
          . 'grep -q -E "^${KEY% *}" ${HOME}/.ssh/known_hosts || echo "${KEY}" >> ${HOME}/.ssh/known_hosts; ';

        # wrap SSH command
        $cmdPrefix .=
          'ssh -oBatchMode=yes ' . $port . ( $1 ? "$1@" : '' ) . $2 . ' \'';
        $cmdSuffix = '\' 2>&1';
    }

    my $global = '-g ';
    my $sudo   = 'sudo -n ';

    if ( $cmd->{npmglobal} eq '0' ) {
        $global = '';
        $sudo   = '';
    }

    $installer->{npminstall} =
        $cmdPrefix
      . 'echo n | sh -c "'
      . $sudo
      . 'NODE_ENV=${NODE_ENV:-production} npm install '
      . $global
      . '--json --silent --unsafe-perm %PACKAGES%" 2>&1'
      . $cmdSuffix;
    $installer->{npmuninstall} =
        $cmdPrefix
      . 'echo n | sh -c "'
      . $sudo
      . 'NODE_ENV=${NODE_ENV:-production} npm uninstall '
      . $global
      . '--json --silent %PACKAGES%" 2>&1'
      . $cmdSuffix;
    $installer->{npmupdate} =
        $cmdPrefix
      . 'echo n | sh -c "'
      . $sudo
      . 'NODE_ENV=${NODE_ENV:-production} npm update '
      . $global
      . '--json --silent --unsafe-perm %PACKAGES%" 2>&1'
      . $cmdSuffix;
    $installer->{npmoutdated} =
        $cmdPrefix
      . 'echo n | '
      . 'echo "{' . "\n"
      . '\"versions\": "; '
      . 'node -e "console.log(JSON.stringify(process.versions));"; '
      . 'L1=$(npm list '
      . $global
      . '--json --silent --depth=0 2>/dev/null); '
      . '[ "$L1" != "" ] && [ "$L1" != "\n" ] && echo ", \"listed\": $L1"; '
      . 'L2=$(npm outdated '
      . $global
      . '--json --silent 2>&1); '
      . '[ "$L2" != "" ] && [ "$L2" != "\n" ] && echo ", \"outdated\": $L2"; '
      . 'echo "}"'
      . $cmdSuffix;

    my $response;

    if ( $cmd->{cmd} =~ /^install (.+)/ ) {
        my @packages = '';
        foreach my $package ( split / /, $1 ) {
            next
              unless ( $package =~
                /^(?:@([\w-]+)\/)?([\w-]+)(?:@([\d\.=<>]+|latest))?$/ );

            push @packages,
              "homebridge"
              if (
                $package =~ m/^homebridge-/i
                && (
                        defined( $cmd->{listedpackages} )
                    and defined( $cmd->{listedpackages}{dependencies} )
                    and !defined(
                        $cmd->{listedpackages}{dependencies}{homebridge}
                    )
                )
              );

            push @packages, $package;
        }
        my $pkglist = join( ' ', @packages );
        return unless ( $pkglist ne '' );
        $installer->{npminstall} =~ s/%PACKAGES%/$pkglist/gi;

        print qq($installer->{npminstall}\n) if ( $installer->{debug} == 1 );
        $response = InstallerInstall($installer);
    }
    elsif ( $cmd->{cmd} =~ /^uninstall (.+)/ ) {
        my @packages = '';
        foreach my $package ( split / /, $1 ) {
            next
              unless ( $package =~
                /^(?:@([\w-]+)\/)?([\w-]+)(?:@([\d\.=<>]+|latest))?$/ );
            push @packages, $package;
        }
        my $pkglist = join( ' ', @packages );
        return unless ( $pkglist ne '' );
        $installer->{npmuninstall} =~ s/%PACKAGES%/$pkglist/gi;
        print qq($installer->{npmuninstall}\n) if ( $installer->{debug} == 1 );
        $response = InstallerUninstall($installer);
    }
    elsif ( $cmd->{cmd} =~ /^update(?: (.+))?/ ) {
        my $pkglist = '';
        if ( defined($1) ) {
            my @packages;
            foreach my $package ( split / /, $1 ) {
                next
                  unless ( $package =~
                    /^(?:@([\w-]+)\/)?([\w-]+)(?:@([\d\.=<>]+|latest))?$/ );
                push @packages, $package;
            }
            $pkglist = join( ' ', @packages );
        }
        $installer->{npmupdate} =~ s/%PACKAGES%/$pkglist/gi;
        print qq($installer->{npmupdate}\n) if ( $installer->{debug} == 1 );
        $response = InstallerUpdate($installer);
    }
    elsif ( $cmd->{cmd} eq 'outdated' ) {
        print qq($installer->{npmoutdated}\n) if ( $installer->{debug} == 1 );
        $response = InstallerOutdated($installer);
    }

    return $response;
}

sub InstallerUpdate($) {
    my $cmd = shift;
    my $p   = `$cmd->{npmupdate}`;
    my $ret = RetrieveInstallerOutput( $cmd, $p );

    return $ret;
}

sub InstallerOutdated($) {
    my $cmd = shift;
    my $p   = `$cmd->{npmoutdated}`;
    my $ret = RetrieveInstallerOutput( $cmd, $p );

    return $ret;
}

sub RetrieveInstallerOutput($$) {
    my $cmd = shift;
    my $p   = shift;
    my $h   = {};

    return $h unless ( defined($p) && $p ne '' );

    # first try to interprete text as JSON directly
    my $decode_json = eval { decode_json($p) };
    if ( not $@ ) {
        $h = $decode_json;
    }

    # if this was not successful,
    #   we'll disassamble the text
    else {
        my $o;
        my $json;
        my $skip = 0;

        foreach my $line ( split /\n/, $p ) {
            chomp($line);
            print qq($line\n) if ( $cmd->{debug} == 1 );

            # JSON output
            if ($skip) {
                $json .= $line;
            }

            # reached JSON
            elsif ( $line =~ /^\{$/ ) {
                $json = $line;
                $skip = 1;
            }

            # other output before JSON
            else {
                $o .= $line;
            }
        }

        $decode_json = eval { decode_json($json) };

        # Found valid JSON output
        if ( not $@ ) {
            $h = $decode_json;
        }

        # Final parsing error
        else {
            if ($o) {
                if ( $o =~ m/Permission.denied.\(publickey\)\.?\r?\n?$/i ) {
                    $h->{error}{code} = "E403";
                    $h->{error}{summary} =
                        "Forbidden - None of the SSH keys from ~/.ssh/ "
                      . "were authorized to access remote host";
                    $h->{error}{detail} = $o;
                }
                elsif ( $o =~
                    m/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?not.found$/i
                    or $o =~
m/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?No.such.file.or.directory$/i
                  )
                {
                    $h->{error}{code}    = "E404";
                    $h->{error}{summary} = "Not Found - $3 is not installed";
                    $h->{error}{detail}  = $o;
                }
                else {
                    $h->{error}{code}    = "E501";
                    $h->{error}{summary} = "Parsing error - " . $@;
                    $h->{error}{detail}  = $p;
                }
            }
            else {
                $h->{error}{code}    = "E500";
                $h->{error}{summary} = "Parsing error - " . $@;
                $h->{error}{detail}  = $p;
            }
        }
    }

    return $h;
}

####################################################
# End Childprocess
####################################################

sub PreProcessing($$) {

    my ( $hash, $json ) = @_;

    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3 $name, 2, "Installer ($name) - JSON error: $@";
        return;
    }

    Log3 $hash, 4, "Installer ($name) - JSON: $json";

    # safe result in hidden reading
    #   to restore module state after reboot
    if ( $hash->{".fhem"}{installer}{cmd} eq 'outdated' ) {
        delete $hash->{".fhem"}{installer}{outdatedpackages};
        $hash->{".fhem"}{installer}{outdatedpackages} = $decode_json->{outdated}
          if ( defined( $decode_json->{outdated} ) );
        delete $hash->{".fhem"}{installer}{listedpackages};
        $hash->{".fhem"}{installer}{listedpackages} = $decode_json->{listed}
          if ( defined( $decode_json->{listed} ) );
        readingsSingleUpdate( $hash, '.packageList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{installer}{cmd} =~ /^install/ ) {
        delete $hash->{".fhem"}{installer}{installedpackages};
        $hash->{".fhem"}{installer}{installedpackages} = $decode_json;
        readingsSingleUpdate( $hash, '.installedList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{installer}{cmd} =~ /^uninstall/ ) {
        delete $hash->{".fhem"}{installer}{uninstalledpackages};
        $hash->{".fhem"}{installer}{uninstalledpackages} = $decode_json;
        readingsSingleUpdate( $hash, '.uninstalledList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{installer}{cmd} =~ /^update/ ) {
        delete $hash->{".fhem"}{installer}{updatedpackages};
        $hash->{".fhem"}{installer}{updatedpackages} = $decode_json;
        readingsSingleUpdate( $hash, '.updatedList', $json, 0 );
    }

    if (   defined( $decode_json->{warning} )
        or defined( $decode_json->{error} ) )
    {
        $hash->{".fhem"}{installer}{'warnings'} = $decode_json->{warning}
          if ( defined( $decode_json->{warning} ) );
        $hash->{".fhem"}{installer}{errors} = $decode_json->{error}
          if ( defined( $decode_json->{error} ) );
    }
    else {
        delete $hash->{".fhem"}{installer}{'warnings'};
        delete $hash->{".fhem"}{installer}{errors};
    }

    WriteReadings( $hash, $decode_json );
}

sub WriteReadings($$) {

    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};

    Log3 $hash, 4, "Installer ($name) - Write Readings";
    Log3 $hash, 5, "Installer ($name) - " . Dumper $decode_json;

    readingsBeginUpdate($hash);

    if ( $hash->{".fhem"}{installer}{cmd} eq 'outdated' ) {
        readingsBulkUpdate(
            $hash,
            'outdated',
            (
                defined( $decode_json->{listed} )
                ? 'check completed'
                : 'check failed'
            )
        );
        $hash->{helper}{lastSync} = ToDay();
    }

    readingsBulkUpdateIfChanged( $hash, 'updatesAvailable',
        scalar keys %{ $decode_json->{outdated} } )
      if ( $hash->{".fhem"}{installer}{cmd} eq 'outdated' );
    readingsBulkUpdateIfChanged( $hash, 'updateListAsJSON',
        eval { encode_json( $hash->{".fhem"}{installer}{outdatedpackages} ) } )
      if ( AttrVal( $name, 'updateListReading', 'none' ) ne 'none' );

    my $result = 'successful';
    $result = 'error' if ( defined( $hash->{".fhem"}{installer}{errors} ) );
    $result = 'warning'
      if ( defined( $hash->{".fhem"}{installer}{'warnings'} ) );

    readingsBulkUpdate( $hash, 'installed', $result )
      if ( $hash->{".fhem"}{installer}{cmd} =~ /^install/ );
    readingsBulkUpdate( $hash, 'uninstalled', $result )
      if ( $hash->{".fhem"}{installer}{cmd} =~ /^uninstall/ );
    readingsBulkUpdate( $hash, 'updated', $result )
      if ( $hash->{".fhem"}{installer}{cmd} =~ /^update/ );

    readingsBulkUpdateIfChanged( $hash, "nodejsVersion",
        $decode_json->{versions}{node} )
      if ( defined( $decode_json->{versions} )
        && defined( $decode_json->{versions}{node} ) );

    if ( defined( $decode_json->{error} ) ) {
        readingsBulkUpdate( $hash, 'state',
            'error \'' . $hash->{".fhem"}{installer}{cmd} . '\'' );
    }
    elsif ( defined( $decode_json->{warning} ) ) {
        readingsBulkUpdate( $hash, 'state',
            'warning \'' . $hash->{".fhem"}{installer}{cmd} . '\'' );
    }
    else {

        readingsBulkUpdate(
            $hash, 'state',
            (
                (
                         scalar keys %{ $decode_json->{outdated} } > 0
                      or scalar
                      keys %{ $hash->{".fhem"}{installer}{outdatedpackages} } >
                      0
                )
                ? 'npm updates available'
                : 'npm is up to date'
            )
        );
    }

    Event( $hash, "FINISH" );
    readingsEndUpdate( $hash, 1 );

    ProcessUpdateTimer($hash)
      if ( $hash->{".fhem"}{installer}{cmd} eq 'getFhemVersion'
        && !defined( $decode_json->{error} ) );
}

#TODO
# - show master/slave dependencies
# - show parent/child dependencies
# - show other dependant/related modules
# - show community and commercial support
#    - aligned with bugtracker
# - fill empty keywords
# - Get Community Support URL from MAINTAINERS.txt
sub CreateMetadataList ($$$) {
    my ( $hash, $getCmd, $modName ) = @_;
    $modName = 'Global' if ( uc($modName) eq 'FHEM' );

    return 'Unknown module ' . $modName
      unless ( defined( $modules{$modName} ) );

    FHEM::Meta::Load($modName);

    return 'No metadata found about module ' . $modName
      unless ( defined( $modules{$modName}{META} )
        && scalar keys %{ $modules{$modName}{META} } > 0 );

    my $modMeta = $modules{$modName}{META};
    my @ret;
    my $html = defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : 0;

    my $header = '';
    my $footer = '';
    if ($html) {
        $header = '<html>';
        $footer = '</html>';
    }

    my $tableOpen       = '';
    my $rowOpen         = '';
    my $rowOpenEven     = '';
    my $rowOpenOdd      = '';
    my $colOpen         = '';
    my $colOpenMinWidth = '';
    my $txtOpen         = '';
    my $txtClose        = '';
    my $colClose        = "\t\t\t";
    my $rowClose        = '';
    my $tableClose      = '';
    my $colorRed        = '';
    my $colorGreen      = '';
    my $colorClose      = '';

    if ($html) {
        $tableOpen       = '<table class="block wide">';
        $rowOpen         = '<tr>';
        $rowOpenEven     = '<tr class="even">';
        $rowOpenOdd      = '<tr class="odd">';
        $colOpen         = '<td>';
        $colOpenMinWidth = '<td style="min-width: 12em;">';
        $txtOpen         = "<b>";
        $txtClose        = "</b>";
        $colClose        = '</td>';
        $rowClose        = '</tr>';
        $tableClose      = '</table>';
        $colorRed        = '<span style="color:red">';
        $colorGreen      = '<span style="color:green">';
        $colorClose      = '</span>';
    }

    my @mAttrs = qw(
      name
      abstract
      keywords
      version
      release_date
      release_status
      author
      copyright
      privacy
      license
      homepage
      wiki
      command_reference
      community_support
      commercial_support
      bugtracker
      version_control
      description
    );

    my $space = $html ? '&nbsp;' : ' ';
    my $lb    = $html ? '<br />' : "\n";
    my $lang  = lc(
        AttrVal(
            $hash->{NAME}, 'language',
            AttrVal( 'global', 'language', 'EN' )
        )
    );

    push @ret, $tableOpen;

    my $linecount = 1;
    foreach my $mAttr (@mAttrs) {
        next
          if ( $mAttr eq 'copyright' && !defined( $modMeta->{x_copyright} ) );
        next
          if (
            $mAttr eq 'description'
            && (   !defined( $modMeta->{description} )
                || $modMeta->{description} eq 'n/a'
                || $modMeta->{description} eq '' )
          );
        next
          if (
            $mAttr eq 'bugtracker'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{bugtracker} ) )
          );
        next
          if (
            $mAttr eq 'homepage'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{homepage} ) )
          );
        next
          if (
            $mAttr eq 'wiki'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{x_wiki} ) )
          );
        next
          if (
            $mAttr eq 'command_reference'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{x_commandref} ) )
          );
        next
          if (
            $mAttr eq 'community_support'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{x_support_community} ) )
          );
        next
          if (
            $mAttr eq 'commercial_support'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{x_support_commercial} ) )
          );
        next
          if (
            $mAttr eq 'privacy'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{x_privacy} ) )
          );

        my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;
        my $mAttrName = $mAttr;
        $mAttrName =~ s/_/$space/g;
        $mAttrName =~ s/([\w'&]+)/\u\L$1/g;

        $l .= $colOpenMinWidth . $txtOpen . $mAttrName . $txtClose . $colClose;

        if ( !defined( $modMeta->{$mAttr} ) ) {
            $l .= $colOpen;

            if ( $mAttr eq 'release_date' ) {
                if ( defined( $modMeta->{x_vcs} ) ) {
                    $l .= $modMeta->{x_vcs}[7];
                }
                else {
                    $l .= $modMeta->{x_file}[6][8][2] . ' (last modify date)';
                }
            }

            elsif ( $mAttr eq 'copyright' ) {
                my $copyName;
                my $copyEmail;
                my $copyWeb;
                my $copyNameContact;

                if ( $modMeta->{x_copyright} =~
                    m/^([^<>\n\r]+)(?:\s+(?:<(.*)>))?$/ )
                {
                    if ( defined( $modMeta->{x_vcs} ) ) {
                        $copyName = '© ' . $modMeta->{x_vcs}[8] . ' ' . $1;
                    }
                    else {
                        $copyName = '© ' . $1;
                    }
                    $copyEmail = $2;
                }
                if (   defined( $modMeta->{resources} )
                    && defined( $modMeta->{resources}{x_copyright} )
                    && defined( $modMeta->{resources}{x_copyright}{web} ) )
                {
                    $copyWeb = $modMeta->{resources}{x_copyright}{web};
                }

                if ( $html && $copyEmail ) {
                    $copyNameContact =
                        '<a href="'
                      . $copyWeb
                      . '" target="_blank">'
                      . $copyName . '</a>';
                }
                elsif ( $html && $copyEmail ) {
                    $copyNameContact =
                        '<a href="mailto:'
                      . $copyEmail . '">'
                      . $copyName . '</a>';
                }

                $l .= $copyNameContact ? $copyNameContact : $copyName;
            }

            elsif ( $mAttr eq 'privacy' ) {
                my $title =
                  defined( $modMeta->{resources}{x_privacy}{title} )
                  ? $modMeta->{resources}{x_privacy}{title}
                  : $modMeta->{resources}{x_privacy}{web};

                $l .=
                    '<a href="'
                  . $modMeta->{resources}{x_privacy}{web}
                  . '" target="_blank">'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'homepage'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{homepage} ) )
            {
                my $title =
                  defined( $modMeta->{resources}{x_homepage_title} )
                  ? $modMeta->{resources}{x_homepage_title}
                  : (
                      $modMeta->{resources}{homepage} =~ m/^.+:\/\/([^\/]+).*/
                    ? $1
                    : $modMeta->{resources}{homepage}
                  );

                $l .=
                    '<a href="'
                  . $modMeta->{resources}{homepage}
                  . '" target="_blank">'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'command_reference'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_commandref} )
                && defined( $modMeta->{resources}{x_commandref}{web} ) )
            {
                my $title =
                  defined( $modMeta->{resources}{x_commandref}{title} )
                  ? $modMeta->{resources}{x_commandref}{title}
                  : (
                    $modMeta->{resources}{x_commandref}{web} =~
                      m/^(?:https?:\/\/)?fhem\.de/i ? 'Public'
                    : ''
                  );

                my $url =
                  $modMeta->{resources}{x_commandref}{web};

                if ( defined( $modMeta->{resources}{x_commandref}{modpath} ) ) {
                    $url .=
                      $modMeta->{resources}{x_commandref}{modpath};
                    $url .= $modName eq 'Global' ? 'global' : $modName;
                }

                $l .=
                  '<a href="' . $url . '" target="_blank">' . $title . '</a>';
            }

            elsif ($mAttr eq 'wiki'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_wiki} )
                && defined( $modMeta->{resources}{x_wiki}{web} ) )
            {
                my $title =
                  defined( $modMeta->{resources}{x_wiki}{title} )
                  ? $modMeta->{resources}{x_wiki}{title}
                  : (
                    $modMeta->{resources}{x_wiki}{web} =~
                      m/^(?:https?:\/\/)?wiki\.fhem\.de/i ? 'FHEM Wiki'
                    : ''
                  );

                $title = 'FHEM Wiki: ' . $title
                  if ( $title ne ''
                    && $title !~ m/^FHEM Wiki/i
                    && $modMeta->{resources}{x_wiki}{web} =~
                    m/^(?:https?:\/\/)?wiki\.fhem\.de/i );

                my $url =
                  $modMeta->{resources}{x_wiki}{web};
                $url .= '/' unless ( $url =~ m/\/$/ );

                if ( defined( $modMeta->{resources}{x_wiki}{modpath} ) ) {
                    $url .= '/' unless ( $url =~ m/\/$/ );
                    $url .=
                      $modMeta->{resources}{x_wiki}{modpath};
                    $url .= '/' unless ( $url =~ m/\/$/ );
                    $url .= $modName eq 'Global' ? 'global' : $modName;
                }

                $l .=
                  '<a href="' . $url . '" target="_blank">' . $title . '</a>';
            }

            elsif ($mAttr eq 'community_support'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_support_community} )
                && defined( $modMeta->{resources}{x_support_community}{web} ) )
            {
                my $title =
                  defined(
                    $modMeta->{resources}{x_support_community}{x_web_title} )
                  ? $modMeta->{resources}{x_support_community}{x_web_title}
                  : (
                    $modMeta->{resources}{x_support_community}{web} =~
                      m/^(?:https?:\/\/)?forum\.fhem\.de/i ? 'FHEM Forum'
                    : ''
                  );

                $title = 'FHEM Forum: ' . $title
                  if ( $title ne ''
                    && $title !~ m/^FHEM Forum/i
                    && $modMeta->{resources}{x_support_community}{web} =~
                    m/^(?:https?:\/\/)?forum\.fhem\.de/i );

                $l .=
                    '<a href="'
                  . $modMeta->{resources}{x_support_community}{web}
                  . '" target="_blank">'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'commercial_support'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_support_commercial} )
                && defined( $modMeta->{resources}{x_support_commercial}{web} ) )
            {
                my $title =
                  defined(
                    $modMeta->{resources}{x_support_commercial}{x_web_title} )
                  ? $modMeta->{resources}{x_support_commercial}{x_web_title}
                  : $modMeta->{resources}{x_support_commercial}{web};

                $l .=
                    '<a href="'
                  . $modMeta->{resources}{x_support_commercial}{web}
                  . '" target="_blank">'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'bugtracker'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{bugtracker} )
                && defined( $modMeta->{resources}{bugtracker}{web} ) )
            {
                my $title =
                  defined( $modMeta->{resources}{bugtracker}{x_web_title} )
                  ? $modMeta->{resources}{bugtracker}{x_web_title}
                  : (
                    $modMeta->{resources}{bugtracker}{web} =~
                      m/^(?:https?:\/\/)?forum\.fhem\.de/i ? 'FHEM Forum'
                    : ''
                  );

                $title = 'FHEM Forum: ' . $title
                  if ( $title ne ''
                    && $title !~ m/^FHEM Forum/i
                    && $modMeta->{resources}{bugtracker}{web} =~
                    m/^(?:https?:\/\/)?forum\.fhem\.de/i );

                $l .=
                    '<a href="'
                  . $modMeta->{resources}{bugtracker}{web}
                  . '" target="_blank">'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'version_control'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{repository} )
                && defined( $modMeta->{resources}{repository}{type} )
                && defined( $modMeta->{resources}{repository}{url} ) )
            {
                # Web link
                if ( defined( $modMeta->{resources}{repository}{web} ) ) {
                    my $url =
                      $modMeta->{resources}{repository}{web};
                    $url .= '/' unless ( $url =~ m/\/$/ );
                    $url .= $modMeta->{resources}{repository}{x_branch_master}
                      if (
                        defined(
                            $modMeta->{resources}{repository}{x_branch_master}
                        )
                      );

                    if (
                        defined(
                            $modMeta->{resources}{repository}{x_filepath}
                        )
                      )
                    {
                        $url .= '/' unless ( $url =~ m/\/$/ );
                        $url .=
                          $modMeta->{resources}{repository}{x_filepath};
                        $url .= '/' unless ( $url =~ m/\/$/ );
                        $url .= $modMeta->{x_file}[2];

                    }

                    $l .=
                        'Web: <a href="'
                      . $url
                      . '" target="_blank">'
                      . (
                        defined(
                            $modMeta->{resources}{repository}{x_web_title}
                          )
                        ? $modMeta->{resources}{repository}{x_web_title}
                        : $url
                      ) . '</a>';

                    if (
                        defined(
                            $modMeta->{resources}{repository}{x_branch_master}
                        )
                        && defined(
                            $modMeta->{resources}{repository}{x_branch_dev}
                        )
                        && $modMeta->{resources}{repository}{x_branch_master}
                        ne $modMeta->{resources}{repository}{x_branch_dev}
                      )
                    {
                        my $url =
                          $modMeta->{resources}{repository}{web};
                        $url .= '/' unless ( $url =~ m/\/$/ );
                        $url .= $modMeta->{resources}{repository}{x_branch_dev};

                        $l .=
                            ' Development branch: <a href="'
                          . $url
                          . '" target="_blank">'
                          . $modMeta->{resources}{repository}{x_branch_dev}
                          . '</a>';
                    }

                    $l .= $lb;
                }

                # VCS link
                my $url =
                  $modMeta->{resources}{repository}{url};
                $url .= '/' unless ( $url =~ m/\/$/ );
                $url .= $modMeta->{resources}{repository}{x_branch_master}
                  if (
                    defined(
                        $modMeta->{resources}{repository}{x_branch_master}
                    )
                  );

                if ( defined( $modMeta->{resources}{repository}{x_filepath} ) )
                {
                    $url .= '/' unless ( $url =~ m/\/$/ );
                    $url .=
                      $modMeta->{resources}{repository}{x_filepath};
                    $url .= '/' unless ( $url =~ m/\/$/ );
                    $url .= $modMeta->{x_file}[2];

                }

                $l .=
                    $modMeta->{resources}{repository}{type}
                  . ': <a href="'
                  . $url
                  . '" target="_blank">'
                  . $url . '</a>';

                if (
                    defined(
                        $modMeta->{resources}{repository}{x_branch_master}
                    )
                    && defined(
                        $modMeta->{resources}{repository}{x_branch_dev} )
                    && $modMeta->{resources}{repository}{x_branch_master} ne
                    $modMeta->{resources}{repository}{x_branch_dev}
                  )
                {
                    my $url =
                      $modMeta->{resources}{repository}{url};
                    $url .= '/' unless ( $url =~ m/\/$/ );
                    $url .= $modMeta->{resources}{repository}{x_branch_dev};

                    $l .=
                        ' Development branch: <a href="'
                      . $url
                      . '" target="_blank">'
                      . $modMeta->{resources}{repository}{x_branch_dev}
                      . '</a>';
                }
            }
            else {
                $l .= '-';
            }

            $l .= $colClose;
        }
        elsif ( !ref( $modMeta->{$mAttr} ) ) {
            $l .= $colOpen;

            my $mAttrVal =
                 defined( $modMeta->{x_lang} )
              && defined( $modMeta->{x_lang}{$lang} )
              && defined( $modMeta->{x_lang}{$lang}{$mAttr} )
              ? $modMeta->{x_lang}{$lang}{$mAttr}
              : $modMeta->{$mAttr};
            $mAttrVal =~ s/\\n/$lb/g;

            if (   $mAttr eq 'license'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{license} )
                && ref( $modMeta->{resources}{license} ) eq 'ARRAY'
                && @{ $modMeta->{resources}{license} } > 0
                && $modMeta->{resources}{license}[0] ne '' )
            {
                $mAttrVal =
                    '<a href="'
                  . $modMeta->{resources}{license}[0]
                  . '" target="_blank">'
                  . $mAttrVal . '</a>';
            }
            elsif ( $mAttr eq 'version' && $modName ne 'Global' ) {
                if (   $modMeta->{x_file}[7] ne 'generated/vcs'
                    && defined( $modMeta->{x_vcs} )
                    && $modMeta->{x_vcs}[5] ne '' )
                {
                    $mAttrVal .= '-s' . $modMeta->{x_vcs}[5];
                }
            }

            $mAttrVal .= ' (' . $modMeta->{x_file}[2] . ')'
              if ( $mAttr eq 'name' && $modName ne 'Global' );

            $l .= $mAttrVal . $colClose;
        }
        elsif (ref( $modMeta->{$mAttr} ) eq 'ARRAY'
            && @{ $modMeta->{$mAttr} } > 0
            && $modMeta->{$mAttr}[0] ne '' )
        {
            $l .= $colOpen;

            if ( $mAttr eq 'author' ) {
                my $authorCount = scalar @{ $modMeta->{$mAttr} };
                my $counter     = 0;

                foreach ( @{ $modMeta->{$mAttr} } ) {
                    next if ( $_ eq '' );

                    my $authorName;
                    my $authorEmail;
                    my $authorNameEmail;

                    if ( $_ =~ m/^([^<>\n\r]+)(?:\s+(?:<(.*)>))?$/ ) {
                        $authorName  = $1;
                        $authorEmail = $2;
                    }

                    $authorNameEmail =
                        '<a href="mailto:'
                      . $authorEmail . '">'
                      . $authorName . '</a>'
                      if ( $html && $authorEmail );

                    if (   defined( $modMeta->{x_fhem_maintainer} )
                        && ref( $modMeta->{x_fhem_maintainer} ) eq 'ARRAY'
                        && @{ $modMeta->{x_fhem_maintainer} } > 0
                        && $modMeta->{x_fhem_maintainer}[$counter] ne '' )
                    {
                        $authorNameEmail = (
                              $authorNameEmail
                            ? $authorNameEmail
                            : $authorName
                          )
                          . ', alias '
                          . $modMeta->{x_fhem_maintainer}[$counter]
                          if ( $modMeta->{x_fhem_maintainer}[$counter] ne
                            $authorName );
                    }

                    $l .= $lb if ($counter);
                    $l .= $lb . 'Co-' . $mAttrName . ':' . $lb
                      if ( $counter == 1 );
                    $l .= $authorNameEmail ? $authorNameEmail : $authorName;

                    $counter++;
                }
            }
            else {
                $l .= join ', ', @{ $modMeta->{$mAttr} };
            }

            $l .= $colClose;
        }
        else {
            $l .= $colOpen . '?' . $colClose;
        }

        $l .= $rowClose;

        push @ret, $l;
        $linecount++;
    }

    push @ret, $tableClose;

    push @ret, '<h3>System Prerequisites</h3>';

    my $moduleUsage =
      defined( $modules{$modName}{LOADED} )
      ? $colorGreen . 'IN USE' . $colorClose
      : $txtOpen . 'not' . $txtClose . ' in use';

    push @ret, 'This FHEM module is currently ' . $moduleUsage . '.'
      unless ( $modName eq 'Global' );

    push @ret, '<h4>Perl Modules</h4>';
    if (   defined( $modMeta->{prereqs} )
        && defined( $modMeta->{prereqs}{runtime} ) )
    {

        push @ret,
            $txtOpen . 'HINT:'
          . $txtClose . "\n"
          . 'This module does not provide prerequisites from its metadata.'
          . "\n"
          . 'The following result is based on automatic source code analysis'
          . "\n"
          . 'and can be incorrect.'
          . $lb
          if ( defined( $modMeta->{x_prereqs_src} )
            && $modMeta->{x_prereqs_src} ne 'META.json' );

        my @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tableOpen;

        push @ret, $colOpenMinWidth . $txtOpen . 'Name' . $txtClose . $colClose;

        push @ret,
          $colOpenMinWidth . $txtOpen . 'Importance' . $txtClose . $colClose;

        push @ret,
          $colOpenMinWidth . $txtOpen . 'Status' . $txtClose . $colClose;

        my $linecount = 1;
        foreach my $mAttr (@mAttrs) {
            next
              unless ( defined( $modMeta->{prereqs}{runtime}{$mAttr} )
                && keys %{ $modMeta->{prereqs}{runtime}{$mAttr} } > 0 );

            foreach
              my $prereq ( sort keys %{ $modMeta->{prereqs}{runtime}{$mAttr} } )
            {
                my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

                my $importance = $mAttr;
                $importance = 'required'    if ( $mAttr eq 'requires' );
                $importance = 'recommended' if ( $mAttr eq 'recommends' );
                $importance = 'suggested'   if ( $mAttr eq 'suggests' );

                my $version = $modMeta->{prereqs}{runtime}{$mAttr}{$prereq};
                $version = '' if ( !defined($version) || $version eq '0' );
                $version = version->parse($version)->normal
                  if ( $version ne '' );

                my $check     = __IsInstalledPerl($prereq);
                my $installed = '';
                if ($check) {
                    if ( $check =~ m/^v/ ) {
                        my $nverReq =
                          $version ne ''
                          ? version->parse($version)->numify
                          : 0;
                        my $nverInst = version->parse($check)->numify;

                        if ( $nverReq > 0 && $nverInst < $nverReq ) {
                            $installed .= 'OUTDATED (' . $check . ')';
                        }
                        else {
                            $installed = 'installed';
                        }
                    }
                    else {
                        $installed = 'installed';
                    }
                }
                else {
                    $installed = $colorRed . 'MISSING' . $colorClose
                      if ( $importance eq 'required' );
                }

                $prereq =
                    '<a href="https://metacpan.org/pod/'
                  . $prereq
                  . '" target="_blank">'
                  . $prereq . '</a>'
                  if ($html);

                $l .=
                    $colOpenMinWidth
                  . $prereq
                  . ( $version ne '' ? " ($version)" : '' )
                  . $colClose;
                $l .= $colOpenMinWidth . $importance . $colClose;
                $l .= $colOpenMinWidth . $installed . $colClose;

                $l .= $rowClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tableClose;
    }
    elsif ( defined( $modMeta->{x_prereqs_src} ) ) {
        push @ret, 'No known prerequisites.' . $lb . $lb;
    }
    else {
        push @ret,
            'Module metadata do not contain any prerequisites.' . "\n"
          . 'For automatic source code analysis, please install Perl::PrereqScanner::NotQuiteLite .'
          . $lb
          . $lb;
    }

    push @ret, 'Based on data generated by ' . $modMeta->{generated_by};

    return $header . join( "\n", @ret ) . $footer;

}

sub __IsInstalledPerl($) {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    return 0 unless (@_);
    my ($pkg) = @_;
    return version->parse($])->normal if ( $pkg eq 'perl' );
    return version->parse( $modules{'Global'}{META}{version} )->normal
      if ( $pkg eq 'FHEM' );

    eval "require $pkg;";

    return 0
      if ($@);

    my $v = eval "$pkg->VERSION()";

    if ($v) {
        return version->parse($v)->normal;
    }
    else {
        return 1;
    }
}

#### my little helper
sub ToDay() {

    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst ) =
      localtime( gettimeofday() );

    $month++;
    $year += 1900;

    my $today = sprintf( '%04d-%02d-%02d', $year, $month, $mday );

    return $today;
}

1;

=pod
=encoding utf8
=item helper
=item summary       Module to help with FHEM installations
=item summary_DE    Modul zur Unterstuetzung bei FHEM Installationen

=begin html

<a name="Installer" id="Installer"></a>
<h3>
  Installer
</h3>
<ul>
  <u><b>Installer - Module to update FHEM, install 3rd-party FHEM modules and manage system prerequisites</b></u><br>
  <br>
  <br>
  <a name="Installerdefine" id="Installerdefine"></a><b>Define</b><br>
  <ul>
    <code>define &lt;name&gt; Installer</code><br>
    <br>
    Example:<br>
    <ul>
      <code>define fhemInstaller Installer</code><br>
    </ul><br>
  </ul><br>
  <br>
  <a name="Installerget" id="Installerget"></a><b>Get</b>
  <ul>
    <li>showModuleInfo - list information about a specific FHEM module
    </li>
  </ul><br>
  <br>
  <a name="Installerattribut" id="Installerattribut"></a><b>Attributes</b>
  <ul>
    <li>disable - disables the device
    </li>
    <li>disabledForIntervals - disable device for interval time (13:00-18:30 or 13:00-18:30 22:00-23:00)
    </li>
  </ul>
</ul>

=end html

=begin html_DE

    <p>
      <a name="Installer" id="Installer"></a>
    </p>
    <h3>
      Installer
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#Installer'>Installer</a>
    </ul>

=end html_DE

=for :application/json;q=META.json 98_Installer.pm
{
  "abstract": "Module to update FHEM, install 3rd-party FHEM modules and manage system prerequisites",
  "x_lang": {
    "de": {
      "abstract": "Modul zum Update von FHEM, zur Installation von Drittanbieter FHEM Modulen und der Verwaltung von Systemvoraussetzungen"
    }
  },
  "keywords": [
    "fhem-core",
    "fhem-mod",
    "fhem-mod-helper",
    "fhem-3rdparty"
  ],
  "version": "v0.0.1",
  "release_status": "testing",
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918623,
        "perl": 5.014,
        "GPUtils": 0,
        "JSON": 0,
        "FHEM::Meta": 0,
        "Data::Dumper": 0,
        "IO::Socket::SSL": 0,
        "HttpUtils": 0,
        "File::stat": 0,
        "Encode": 0
      },
      "recommends": {
        "Perl::PrereqScanner::NotQuiteLite": 0,
        "Time::Local": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "bugtracker": {
      "web": "https://forum.fhem.de/index.php/board,44.0.html",
      "x_web_title": "FHEM Forum: Unterstützende Dienste"
    }
  }
}
=end :application/json;q=META.json

=cut
