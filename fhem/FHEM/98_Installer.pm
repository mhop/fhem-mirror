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
      . "installerMode:update,developer "
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
        qw(
          attr
          AttrVal
          cmds
          CommandAttr
          Debug
          defs
          deviceEvents
          devspec2array
          DoTrigger
          FW_webArgs
          gettimeofday
          init_done
          InternalTimer
          IsDisabled
          LoadModule
          Log
          Log3
          maxNum
          modules
          packages
          readingsBeginUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsEndUpdate
          readingsSingleUpdate
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          TimeNow
          Value
          )
    );
}

# Load dependent FHEM modules as packages,
#  no matter if user also defined FHEM devices or not.
#  We want to use their functions here :-)
#TODO let this make Meta.pm for me
#LoadModule('apt');
#LoadModule('pypip');
LoadModule('npmjs');

our %pkgStatus = ();

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

    delete( $modules{ $hash->{TYPE} }{defptr}{localhost} );
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
sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    if ( lc($cmd) eq 'checkprereqs' ) {
        my $ret = CreatePrereqsList( $hash, $cmd, @args );
        return $ret;
    }
    elsif ( lc($cmd) eq 'search' ) {
        my $ret = CreateSearchList( $hash, $cmd, @args );
        return $ret;
    }
    elsif ( lc($cmd) eq 'showmoduleinfo' ) {
        return "usage: $cmd MODULE" if ( @args != 1 );

        my $ret = CreateMetadataList( $hash, $cmd, $args[0] );
        return $ret;
    }
    elsif ( lc($cmd) eq 'showpackageinfo' ) {
        return "usage: $cmd PACKAGE" if ( @args != 1 );

        my $ret = CreateMetadataList( $hash, $cmd, $args[0] );
        return $ret;
    }
    elsif ( lc($cmd) eq 'zzgetmodulemeta.json' ) {
        return "usage: $cmd MODULE" if ( @args != 1 );

        my $ret = CreateRawMetaJson( $hash, $cmd, $args[0] );
        return $ret;
    }
    elsif ( lc($cmd) eq 'zzgetpackagemeta.json' ) {
        return "usage: $cmd PACKAGE" if ( @args != 1 );

        my $ret = CreateRawMetaJson( $hash, $cmd, $args[0] );
        return $ret;
    }
    else {
        my $installerMode = AttrVal( $name, 'installerMode', 'update' );
        my @fhemModules;
        foreach ( sort { "\L$a" cmp "\L$b" } keys %modules ) {
            next if ( $_ eq 'Global' );
            push @fhemModules, $_
              if ( $installerMode ne 'update'
                || defined( $modules{$_}{LOADED} ) );
        }

        my $list =
          'search' . ' showModuleInfo:FHEM,' . join( ',', @fhemModules );

        if ( $installerMode eq 'developer' ) {
            my @fhemPackages;
            foreach ( sort { "\L$a" cmp "\L$b" } keys %packages ) {
                push @fhemPackages, $_;
            }

            $list .=
                ' showPackageInfo:'
              . join( ',', @fhemPackages )
              . ' zzGetModuleMETA.json:FHEM,'
              . join( ',', @fhemModules )
              . ' zzGetPackageMETA.json:'
              . join( ',', @fhemPackages );
        }

        $list .= " checkPrereqs";
        if ( $installerMode eq 'install' ) {
            my $dh;
            my $dir = $attr{global}{modpath};
            if ( opendir( $dh, $dir ) ) {
                my $counter = 0;
                foreach my $fn (
                    grep { $_ ne "." && $_ ne ".." && !-d $_ && $_ =~ /\.cfg$/ }
                    readdir($dh)
                  )
                {
                    $list .= ':' unless ($counter);
                    $list .= ',' if ($counter);
                    $list .= $fn;
                    $counter++;
                }
                closedir($dh);
            }
        }
        elsif ( $installerMode eq 'update' ) {
            $list .= ':noArg';
        }

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

    my $cmd  = $1;
    my $pkgs = $2;

    my $list;

    foreach my $package ( split / /, $pkgs ) {
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
            __ToDay() ne (
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
        print qq($installer->{npmuninstall}\n)
          if ( $installer->{debug} == 1 );
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
        $hash->{helper}{lastSync} = __ToDay();
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

sub CreatePrereqsList {
    my $hash    = shift;
    my $getCmd  = shift;
    my $cfgfile = shift;
    my $mode =
      ( $cfgfile && $cfgfile eq '1' ? 'all' : ( $cfgfile ? 'file' : 'live' ) );
    $mode = 'list' if ( $cfgfile && defined( $modules{$cfgfile} ) );

    my @defined;
    if ( $mode eq 'live' || $mode eq 'all' ) {
        foreach ( keys %modules ) {
            next unless ( $mode eq 'all' || defined( $modules{$_}{LOADED} ) );
            push @defined, $_;
        }
    }
    elsif ( $mode eq 'file' ) {
        @defined = __GetDefinedModulesFromFile($cfgfile);
        return
            'File '
          . $cfgfile
          . ' does not seem to contain any FHEM device configuration'
          unless ( @defined > 0 );
    }
    elsif ( $mode eq 'list' ) {
        @defined = @_;
        unshift @defined, $cfgfile;
    }

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    my @ret;
    my $html =
      defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : 0;

    my $header = '';
    my $footer = '';
    if ($html) {
        $header = '<html>';
        $footer = '</html>';
    }

    my $blockOpen   = '';
    my $tTitleOpen  = '';
    my $tTitleClose = '';
    my $tOpen       = '';
    my $tCOpen      = '';
    my $tCClose     = '';
    my $tHOpen      = '';
    my $tHClose     = '';
    my $tBOpen      = '';
    my $tBClose     = '';
    my $tFOpen      = '';
    my $tFClose     = '';
    my $trOpen      = '';
    my $trOpenEven  = '';
    my $trOpenOdd   = '';
    my $thOpen      = '';
    my $thOpen2     = '';
    my $thOpen3     = '';
    my $tdOpen      = '';
    my $tdOpen2     = '';
    my $tdOpen3     = '';
    my $strongOpen  = '';
    my $strongClose = '';
    my $tdClose     = "\t\t\t";
    my $thClose     = "\t\t\t";
    my $trClose     = '';
    my $tClose      = '';
    my $blockClose  = '';
    my $colorRed    = '';
    my $colorGreen  = '';
    my $colorClose  = '';

    if ($html) {
        $blockOpen   = '<div class="makeTable wide internals">';
        $tTitleOpen  = '<span class="mkTitle">';
        $tTitleClose = '</span>';
        $tOpen       = '<table class="block wide internals wrapcolumns">';
        $tCOpen      = '<caption style="text-align: left; font-size: larger;">';
        $tCClose     = '</caption>';
        $tHOpen      = '<thead>';
        $tHClose     = '</thead>';
        $tBOpen      = '<tbody>';
        $tBClose     = '</tbody>';
        $tFOpen      = '<tfoot style="font-size: smaller;">';
        $tFClose     = '</tfoot>';
        $trOpen      = '<tr class="column">';
        $trOpenEven  = '<tr class="column even">';
        $trOpenOdd   = '<tr class="column odd">';
        $thOpen      = '<th style="text-align: left; vertical-align: top;">';
        $thOpen2 =
          '<th style="text-align: left; vertical-align: top;" colspan="2">';
        $thOpen3 =
          '<th style="text-align: left; vertical-align: top;" colspan="3">';
        $tdOpen      = '<td style="vertical-align: top;">';
        $tdOpen2     = '<td style="vertical-align: top;" colspan="2">';
        $tdOpen3     = '<td style="vertical-align: top;" colspan="3">';
        $strongOpen  = '<strong>';
        $strongClose = '</strong>';
        $tdClose     = '</td>';
        $thClose     = '</th>';
        $trClose     = '</tr>';
        $tClose      = '</table>';
        $blockClose  = '</div>';
        $colorRed    = '<span style="color: red">';
        $colorGreen  = '<span style="color: green">';
        $colorClose  = '</span>';
    }

    my $space = $html ? '&nbsp;' : ' ';
    my $lb    = $html ? '<br />' : "\n";
    my $lang  = lc(
        AttrVal(
            $hash->{NAME}, 'language',
            AttrVal( 'global', 'language', 'EN' )
        )
    );

    my $FW_CSRF = (
        defined( $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN} )
        ? '&fwcsrf=' . $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN}
        : ''
    );

    ########
    # Getting Perl prereqs
    LoadInstallStatusPerl( $defined[0] eq '1' ? 1 : \@defined );

    my $found                  = 0;
    my $foundRequired          = 0;
    my $foundRecommended       = 0;
    my $foundSuggested         = 0;
    my $foundRequiredPerl      = 0;
    my $foundRecommendedPerl   = 0;
    my $foundSuggestedPerl     = 0;
    my $foundRequiredNodejs    = 0;
    my $foundRecommendedNodejs = 0;
    my $foundSuggestedNodejs   = 0;
    my $foundRequiredPython    = 0;
    my $foundRecommendedPython = 0;
    my $foundSuggestedPython   = 0;

    # Display prereqs
    foreach my $mAttr (qw(required recommended suggested)) {
        foreach my $area (qw(Perl Node.js Python)) {
            next
              unless ( defined( $pkgStatus{$mAttr} )
                && defined( $pkgStatus{$mAttr}{$area} )
                && keys %{ $pkgStatus{$mAttr}{$area} } > 0 );

            my $linecount  = 1;
            my $importance = ucfirst($mAttr);

            foreach my $item (
                sort { "\L$a" cmp "\L$b" }
                keys %{ $pkgStatus{$mAttr}{$area} }
              )
            {
                my $linkmod = '';
                my $inScope = 0;
                foreach my $modName ( sort { "\L$a" cmp "\L$b" }
                    @{ $pkgStatus{$mAttr}{$area}{$item}{modules} } )
                {
                    # check if this package is used by any
                    #   module that is in install scope
                    if ( grep ( /^$modName$/, @defined ) ) {
                        $inScope = 1;
                    }

                    $linkmod .= ', ' unless ( $linkmod eq '' );
                    if ($html) {
                        $linkmod .=
                            '<a href="?cmd=get '
                          . $hash->{NAME}
                          . ' showModuleInfo '
                          . $modName
                          . $FW_CSRF . '">'
                          . ( $modName eq 'Global' ? 'FHEM' : $modName )
                          . '</a>';
                    }
                    else {
                        $linkmod .=
                          ( $modName eq 'Global' ? 'FHEM' : $modName );
                    }
                }
                next unless ($inScope);

                $found++;
                $foundRequired++    if ( $mAttr eq 'required' );
                $foundRecommended++ if ( $mAttr eq 'recommended' );
                $foundSuggested++   if ( $mAttr eq 'suggested' );
                $foundRequiredPerl++
                  if ( $area eq 'Perl' && $mAttr eq 'required' );
                $foundRecommendedPerl++
                  if ( $area eq 'Perl' && $mAttr eq 'recommended' );
                $foundSuggestedPerl++
                  if ( $area eq 'Perl' && $mAttr eq 'suggested' );
                $foundRequiredNodejs++
                  if ( $area eq 'Node.js' && $mAttr eq 'required' );
                $foundRecommendedNodejs++
                  if ( $area eq 'Node.js' && $mAttr eq 'recommended' );
                $foundSuggestedNodejs++
                  if ( $area eq 'Node.js' && $mAttr eq 'suggested' );
                $foundRequiredPython++
                  if ( $area eq 'Python' && $mAttr eq 'required' );
                $foundRecommendedPython++
                  if ( $area eq 'Python' && $mAttr eq 'recommended' );
                $foundSuggestedPython++
                  if ( $area eq 'Python' && $mAttr eq 'suggested' );

                my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

                my $linkitem = $item;
                $linkitem =
                    '<a href="https://metacpan.org/pod/'
                  . $item
                  . '" target="_blank">'
                  . $item . '</a>'
                  if ($html);

                $l .=
                    $tdOpen
                  . $linkitem
                  . (
                    $pkgStatus{$mAttr}{$area}{$item}{status} eq 'outdated'
                    ? ' (wanted version: '
                      . $pkgStatus{$mAttr}{$area}{$item}{version} . ')'
                    : ''
                  ) . $tdClose;
                $l .= $tdOpen . $area . $tdClose;
                $l .= $tdOpen . $linkmod . $tdClose;
                $l .= $trClose;

                if ( $linecount == 1 ) {
                    push @ret,
                        $trOpen
                      . $tdOpen
                      . (
                        $html
                        ? '<a name="prereqResult' . $importance . '"></a>'
                        : ''
                      )
                      . $blockOpen
                      . $tOpen
                      . $tCOpen
                      . $importance
                      . $tCClose;

                    push @ret, $tHOpen . $trOpen;
                    push @ret, $thOpen . 'Item' . $thClose;
                    push @ret, $thOpen . 'Type' . $thClose;
                    push @ret, $thOpen . 'Used by' . $thClose;
                    push @ret, $trClose . $tHClose . $tBOpen;
                }

                push @ret, $l;
                $linecount++;
            }

            push @ret, $tBClose;

            my $descr =
                'These dependencies '
              . $strongOpen . 'must'
              . $strongClose
              . ' be installed for the listed FHEM modules to work.';
            $descr =
                'These dependencies are '
              . $strongOpen
              . 'strongly encouraged'
              . $strongClose
              . ' and should be installed for full functionality of the listed FHEM modules, except in resource constrained environments.'
              if ( $importance eq 'Recommended' );
            $descr =
                'These dependencies are '
              . $strongOpen
              . 'optional'
              . $strongClose
              . ', but are suggested for enhanced operation of the listed FHEM modules.'
              if ( $importance eq 'Suggested' );

            push @ret, $tFOpen . $tdOpen3 . $descr . $tFClose;
            push @ret, $tClose . $blockClose . $tdClose . $trClose;
        }
    }

    if ($found) {
        push @ret, $tBClose;

        if ( defined( $pkgStatus{Perl}{analyzed} ) ) {
            push @ret,
                $tFOpen
              . $trOpen
              . $tdOpen
              . $strongOpen . 'Hint:'
              . $strongClose
              . ' Some of the FHEM modules in use do not provide Perl prerequisites from its metadata.'
              . $lb;

            if ( $pkgStatus{Perl}{analyzed} == 1 ) {
                push @ret,
'This check is based on automatic source code analysis and can be incorrect.'
                  . ' Suggested Perl items may still be required if the module author had decided to implement some own dependency and/or error handling like returning an informative message instead of the original Perl error message.';
            }
            elsif ( $pkgStatus{Perl}{analyzed} == 2 ) {
                push @ret,
'This check may be incomplete until you install Perl::PrereqScanner::NotQuiteLite for automatic source code analysis.';
            }

            push @ret, $tdClose . $trClose . $tFClose;
        }

        unshift @ret, $lb . $lb . $tdClose . $trClose;

        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#prereqResultSuggested">' : '' )
          . $foundSuggested
          . ' suggested '
          . ( $foundSuggested > 1 ? 'items' : 'item' )
          . ( $html               ? '</a>'  : '' )
          if ($foundSuggested);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#prereqResultRecommended">' : '' )
          . $foundRecommended
          . ' recommended '
          . ( $foundRecommended > 1 ? 'items' : 'item' )
          . ( $html                 ? '</a>'  : '' )
          if ($foundRecommended);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#prereqResultRequired">' : '' )
          . $foundRequired
          . ' required '
          . ( $foundRequired > 1 ? 'items' : 'item' )
          . ( $html              ? '</a>'  : '' )
          if ($foundRequired);
        unshift @ret,
            $found
          . ' total missing '
          . ( $found > 1 ? 'prerequisites:' : 'prerequisite:' );

        unshift @ret, $blockOpen . $blockClose;
        unshift @ret, $tBOpen . $trOpen . $tdOpen;
    }
    else {
        my @hooray = (
            'hooray', 'hurray', 'phew', 'woop woop',
            'woopee', 'wow',    'yay',  'yippie',
        );
        my $x = 0 + int( rand( scalar @hooray + 1 - 0 ) );
        unshift @ret,
            $tBOpen
          . $trOpen
          . $tdOpen
          . $lb
          . ucfirst( $hooray[$x] )
          . '! All prerequisites are met.'
          . ( $html ? ' 🥳' : '' )
          . $lb
          . $lb
          . $tdClose
          . $trClose
          . $tBClose;
    }

    push @ret, $tClose . $blockClose;

    unshift @ret,
        $blockOpen
      . $blockClose
      . ( $html ? '<a name="prereqResultTOP"></a>' : '' )
      . $blockOpen
      . $tTitleOpen
      . ( $mode eq 'live' ? 'Live ' : '' )
      . 'System Prerequisites Check'
      . $tTitleClose
      . $tOpen;

    return $header . join( "\n", @ret ) . $footer;
}

sub CreateSearchList ($$@) {
    my $hash   = shift;
    my $getCmd = shift;
    my $search = join( '\s*', @_ );
    $search = '.+' unless ($search);

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    my @ret;
    my $html =
      defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : 0;

    my $FW_CSRF = (
        defined( $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN} )
        ? '&fwcsrf=' . $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN}
        : ''
    );
    my $FW_CSRF_input =
      defined( $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN} )
      ? '<input type="hidden" name="fwcsrf" value="'
      . $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN} . '">'
      : '';

    my $header = '';
    my $footer = '';
    if ($html) {
        $header =
'<html><div class="detLink installerBack" style="float:right"><a href="?detail='
          . $hash->{NAME}
          . '">&larr; back to FHEM Installer</a></div>';
        $footer = '</html>';
    }

    my $blockOpen   = '';
    my $tTitleOpen  = '';
    my $tTitleClose = '';
    my $tOpen       = '';
    my $tCOpen      = '';
    my $tCClose     = '';
    my $tHOpen      = '';
    my $tHClose     = '';
    my $tBOpen      = '';
    my $tBClose     = '';
    my $tFOpen      = '';
    my $tFClose     = '';
    my $trOpen      = '';
    my $trOpenEven  = '';
    my $trOpenOdd   = '';
    my $thOpen      = '';
    my $thOpen2     = '';
    my $thOpen3     = '';
    my $tdOpen      = '';
    my $tdOpen2     = '';
    my $tdOpen3     = '';
    my $strongOpen  = '';
    my $strongClose = '';
    my $tdClose     = "\t\t\t";
    my $thClose     = "\t\t\t";
    my $trClose     = '';
    my $tClose      = '';
    my $blockClose  = '';
    my $colorRed    = '';
    my $colorGreen  = '';
    my $colorClose  = '';

    if ($html) {
        $blockOpen   = '<div class="makeTable wide internals">';
        $tTitleOpen  = '<span class="mkTitle">';
        $tTitleClose = '</span>';
        $tOpen       = '<table class="block wide internals wrapcolumns">';
        $tCOpen      = '<caption style="text-align: left; font-size: larger;">';
        $tCClose     = '</caption>';
        $tHOpen      = '<thead>';
        $tHClose     = '</thead>';
        $tBOpen      = '<tbody>';
        $tBClose     = '</tbody>';
        $tFOpen      = '<tfoot style="font-size: smaller;">';
        $tFClose     = '</tfoot>';
        $trOpen      = '<tr class="column">';
        $trOpenEven  = '<tr class="column even">';
        $trOpenOdd   = '<tr class="column odd">';
        $thOpen      = '<th style="text-align: left; vertical-align: top;">';
        $thOpen2 =
          '<th style="text-align: left; vertical-align: top;" colspan="2">';
        $thOpen3 =
          '<th style="text-align: left; vertical-align: top;" colspan="3">';
        $tdOpen      = '<td style="vertical-align: top;">';
        $tdOpen2     = '<td style="vertical-align: top;" colspan="2">';
        $tdOpen3     = '<td style="vertical-align: top;" colspan="3">';
        $strongOpen  = '<strong>';
        $strongClose = '</strong>';
        $tdClose     = '</td>';
        $thClose     = '</td>';
        $trClose     = '</tr>';
        $tClose      = '</table>';
        $blockClose  = '</div>';
        $colorRed    = '<span style="color: red">';
        $colorGreen  = '<span style="color: green">';
        $colorClose  = '</span>';
    }

    my $space = $html ? '&nbsp;' : ' ';
    my $lb    = $html ? '<br />' : "\n";
    my $lang  = lc(
        AttrVal(
            $hash->{NAME}, 'language',
            AttrVal( 'global', 'language', 'EN' )
        )
    );

    # Add search input
    $header .=
'<form id="fhemsearch" method="get" action="?" onsubmit="cmd.value = \'get '
      . $hash->{NAME}
      . ' search \'+ q.value">'
      . $FW_CSRF_input
      . '<input type="hidden" name="cmd" value="">'
      . '<label for="q" style="margin-right: 0.5em;">Search:</label>'
      . '<input type="text" name="q" id="q" value="'
      . $search
      . '" autocorrect="off" autocapitalize="off">'
      . '</form>';

    my $found = 0;

    # search for matching device
    my $foundDevices = 0;
    my $linecount    = 1;
    foreach my $device ( sort { "\L$a" cmp "\L$b" } keys %defs ) {
        next
          unless ( defined( $defs{$device}{TYPE} )
            && !defined( $defs{$device}{TEMPORARY} )
            && defined( $modules{ $defs{$device}{TYPE} } ) );

        if ( $device =~ m/^.*$search.*$/i ) {
            unless ($foundDevices) {
                push @ret,
                    ( $html ? '<a name="searchResultDevices"></a>' : '' )
                  . $blockOpen
                  . $tOpen
                  . $tCOpen
                  . 'Devices'
                  . $tCClose
                  . $tHOpen
                  . $trOpen;

                push @ret, $thOpen . 'Device Name' . $thClose;
                push @ret, $thOpen . 'Device Type' . $thClose;
                push @ret, $thOpen . 'Device State' . $thClose;
                push @ret, $trClose . $tHClose;
            }
            $found++;
            $foundDevices++;

            my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

            FHEM::Meta::Load( $defs{$device}{TYPE} );

            my $linkDev = $device;
            $linkDev =
                '<a href="?detail='
              . $device
              . $FW_CSRF . '">'
              . $device . '</a>'
              if ($html);

            my $linkMod = $defs{$device}{TYPE};
            $linkMod =
                '<a href="?cmd=get '
              . $hash->{NAME}
              . ' showModuleInfo '
              . $defs{$device}{TYPE}
              . $FW_CSRF . '">'
              . $defs{$device}{TYPE} . '</a>'
              if ($html);

            $l .= $tdOpen . $linkDev . $tdClose;
            $l .= $tdOpen . $linkMod . $tdClose;
            $l .= $tdOpen
              . (
                defined( $defs{$device}{STATE} )
                ? $defs{$device}{STATE}
                : ''
              ) . $tdClose;

            $l .= $trClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tClose . $blockClose if ($foundDevices);

    # search for matching module
    my $foundModules = 0;
    $linecount = 1;
    foreach my $module ( sort { "\L$a" cmp "\L$b" } keys %modules ) {
        if ( $module =~ m/^.*$search.*$/i ) {
            unless ($foundModules) {
                push @ret,
                    ( $html ? '<a name="searchResultModules"></a>' : '' )
                  . $blockOpen
                  . $tOpen
                  . $tCOpen
                  . 'Modules'
                  . $tCClose
                  . $tHOpen
                  . $trOpen;

                push @ret, $thOpen . 'Module Name' . $thClose;
                push @ret, $thOpen . 'Abstract' . $thClose;
                push @ret, $trClose . $tHClose;
            }
            $found++;
            $foundModules++;

            my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

            FHEM::Meta::Load($module);

            my $abstract = '';
            $abstract = $modules{$module}{META}{abstract}
              if ( defined( $modules{$module}{META} )
                && defined( $modules{$module}{META}{abstract} ) );

            my $link = $module;
            $link =
                '<a href="?cmd=get '
              . $hash->{NAME}
              . ' showModuleInfo '
              . $module
              . $FW_CSRF . '">'
              . $module . '</a>'
              if ($html);

            $l .= $tdOpen . $link . $tdClose;
            $l .= $tdOpen . ( $abstract eq 'n/a' ? '' : $abstract ) . $tdClose;

            $l .= $trClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tClose . $blockClose if ($foundModules);

    # search for matching module
    my $foundPackages = 0;
    $linecount = 1;
    foreach my $package ( sort { "\L$a" cmp "\L$b" } keys %packages ) {
        if ( $package =~ m/^.*$search.*$/i ) {
            unless ($foundPackages) {
                push @ret,
                    ( $html ? '<a name="searchResultPackages"></a>' : '' )
                  . $blockOpen
                  . $tOpen
                  . $tCOpen
                  . 'Packages'
                  . $tCClose
                  . $tHOpen
                  . $trOpen;

                push @ret, $thOpen . 'Package Name' . $thClose;
                push @ret, $thOpen . 'Abstract' . $thClose;
                push @ret, $trClose . $tHClose;
            }
            $found++;
            $foundPackages++;

            my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

            FHEM::Meta::Load($package);

            my $abstract = '';
            $abstract = $packages{$package}{META}{abstract}
              if ( defined( $packages{$package}{META} )
                && defined( $packages{$package}{META}{abstract} ) );

            my $link = $package;
            $link =
                '<a href="?cmd=get '
              . $hash->{NAME}
              . ' showPackageInfo '
              . $package
              . $FW_CSRF . '">'
              . $package . '</a>'
              if ($html);

            $l .= $tdOpen . $link . $tdClose;
            $l .= $tdOpen . ( $abstract eq 'n/a' ? '' : $abstract ) . $tdClose;

            $l .= $trClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tClose . $blockClose if ($foundPackages);

    # search for matching keyword
    my $foundKeywords = 0;
    $linecount = 1;
    foreach
      my $keyword ( sort { "\L$a" cmp "\L$b" } keys %FHEM::Meta::keywords )
    {
        if ( $keyword =~ m/^.*$search.*$/i ) {
            push @ret, '<a name="searchResultKeywords"></a>'
              unless ($foundKeywords);
            $found++;
            $foundKeywords++;

            my $descr = FHEM::Meta::GetKeywordDesc( $keyword, $lang );

            push @ret, $blockOpen . $tOpen;

            if ($html) {
                push @ret,
                    '<caption style="text-align: left; font-size: larger;"'
                  . ( $descr ne '' ? ' title="' . $descr . '"' : '' ) . '># '
                  . $keyword
                  . $tCClose;
            }
            else {
                push @ret, '# ' . $keyword;
            }

            my @mAttrs = qw(
              modules
              packages
            );

            push @ret, $tHOpen . $trOpen;

            push @ret, $thOpen . 'Name' . $thClose;

            push @ret, $thOpen . 'Type' . $thClose;

            push @ret, $thOpen . 'Abstract' . $thClose;

            push @ret, $trClose . $tHClose;

            foreach my $mAttr (@mAttrs) {
                next
                  unless ( defined( $FHEM::Meta::keywords{$keyword}{$mAttr} )
                    && @{ $FHEM::Meta::keywords{$keyword}{$mAttr} } > 0 );

                foreach my $item ( sort { "\L$a" cmp "\L$b" }
                    @{ $FHEM::Meta::keywords{$keyword}{$mAttr} } )
                {
                    my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

                    my $type = $mAttr;
                    $type = 'Module'  if ( $mAttr eq 'modules' );
                    $type = 'Package' if ( $mAttr eq 'packages' );

                    FHEM::Meta::Load($item);

                    my $abstract = '';
                    $abstract = $modules{$item}{META}{abstract}
                      if ( defined( $modules{$item} )
                        && defined( $modules{$item}{META} )
                        && defined( $modules{$item}{META}{abstract} ) );

                    my $link = $item;
                    $link =
                        '<a href="?cmd=get '
                      . $hash->{NAME}
                      . (
                        $type eq 'Module'
                        ? ' showModuleInfo '
                        : ' showPackageInfo '
                      )
                      . $item
                      . $FW_CSRF . '">'
                      . $item . '</a>'
                      if ($html);

                    $l .= $tdOpen . $link . $tdClose;
                    $l .= $tdOpen . $type . $tdClose;
                    $l .=
                        $tdOpen
                      . ( $abstract eq 'n/a' ? '' : $abstract )
                      . $tdClose;

                    $l .= $trClose;

                    push @ret, $l;
                    $linecount++;
                }
            }

            push @ret, $tClose . $blockClose;
        }
    }

    # search for matching maintainer
    my $foundMaintainers = 0;
    $linecount = 1;
    foreach my $maintainer (
        sort { "\L$a" cmp "\L$b" }
        keys %FHEM::Meta::maintainers
      )
    {
        if ( $maintainer =~ m/^.*$search.*$/i ) {
            unless ($foundMaintainers) {
                push @ret,
                    $blockOpen
                  . $tOpen
                  . $tCOpen
                  . ( $html ? '<a name="searchResultMaintainers"></a>' : '' )
                  . 'Authors & Maintainers'
                  . $tCClose
                  . $tHOpen
                  . $trOpen;

                push @ret, $thOpen . 'Name' . $thClose;
                push @ret, $thOpen . 'Modules' . $thClose;
                push @ret, $thOpen . 'Packages' . $thClose;
                push @ret, $trClose . $tHClose;
            }
            $found++;
            $foundMaintainers++;

            my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

            my $mods = '';
            if ( defined( $FHEM::Meta::maintainers{$maintainer}{modules} ) ) {
                my $counter = 0;
                foreach my $mod ( sort { "\L$a" cmp "\L$b" }
                    @{ $FHEM::Meta::maintainers{$maintainer}{modules} } )
                {
                    if ($html) {
                        $mods .= '<br />' if ($counter);
                        $mods .=
                            '<a href="?cmd=get '
                          . $hash->{NAME}
                          . ' showModuleInfo '
                          . $mod
                          . $FW_CSRF . '">'
                          . $mod . '</a>';
                    }
                    else {
                        $mods .= "\n" unless ($counter);
                        $mods .= $mod;
                    }
                    $counter++;
                }
            }
            my $pkgs = '';
            if ( defined( $FHEM::Meta::maintainers{$maintainer}{packages} ) ) {
                my $counter = 0;
                foreach my $pkg ( sort { "\L$a" cmp "\L$b" }
                    @{ $FHEM::Meta::maintainers{$maintainer}{packages} } )
                {
                    if ($html) {
                        $pkgs .= '<br />' if ($counter);
                        $pkgs .=
                            '<a href="?cmd=get '
                          . $hash->{NAME}
                          . ' showPackageInfo '
                          . $pkg
                          . $FW_CSRF . '">'
                          . $pkg . '</a>';
                    }
                    else {
                        $pkgs .= "\n" unless ($counter);
                        $pkgs .= $pkg;
                    }
                    $counter++;
                }
            }

            $l .= $tdOpen . $maintainer . $tdClose;
            $l .= $tdOpen . $mods . $tdClose;
            $l .= $tdOpen . $pkgs . $tdClose;

            $l .= $trClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tClose . $blockClose if ($foundMaintainers);

    # search for matching Perl package
    my $foundPerl = 0;
    $linecount = 1;
    foreach my $dependent (
        sort { "\L$a" cmp "\L$b" }
        keys %{ $FHEM::Meta::dependents{pkgs} }
      )
    {
        next if ( FHEM::Meta::ModuleIsPerlCore($dependent) );
        next if ( FHEM::Meta::ModuleIsPerlPragma($dependent) );
        next if ( FHEM::Meta::ModuleIsInternal($dependent) );

        if ( $dependent =~ m/^.*$search.*$/i ) {
            unless ($foundPerl) {
                push @ret,
                    $blockOpen
                  . $tOpen
                  . $tCOpen
                  . ( $html ? '<a name="searchResultPerl"></a>' : '' )
                  . 'Perl Packages'
                  . $tCClose
                  . $tHOpen
                  . $trOpen;

                push @ret, $thOpen . 'Name' . $thClose;
                push @ret, $thOpen . 'Referenced from' . $thClose;
                push @ret, $trClose . $tHClose;
            }
            $found++;
            $foundPerl++;

            my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

            my $references = '';
            my $counter    = 0;
            foreach my $pkgReq (qw(requires recommends suggests)) {
                next
                  unless (
                    defined(
                        $FHEM::Meta::dependents{pkgs}{$dependent}{$pkgReq}
                    )
                  );

                foreach my $mod ( sort { "\L$a" cmp "\L$b" }
                    @{ $FHEM::Meta::dependents{pkgs}{$dependent}{$pkgReq} } )
                {
                    if ($html) {
                        $references .= '<br />' if ($counter);
                        $references .=
                            '<a href="?cmd=get '
                          . $hash->{NAME}
                          . (
                            FHEM::Meta::ModuleIsInternal($mod) eq 'module'
                            ? ' showModuleInfo '
                            : ' showPackageInfo '
                          )
                          . $mod
                          . $FW_CSRF . '">'
                          . $mod . '</a>';
                    }
                    else {
                        $references .= "\n" unless ($counter);
                        $references .= $mod;
                    }
                    $counter++;
                }
            }

            $l .= $tdOpen . $dependent . $tdClose;
            $l .= $tdOpen . $references . $tdClose;

            $l .= $trClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tClose . $blockClose if ($foundPerl);

    #TODO works only if fhem.pl patch was accepted:
    #  https://forum.fhem.de/index.php/topic,98937.0.html
    if (   defined( $hash->{CL} )
        && defined( $hash->{CL}{'.iDefCmdMethod'} )
        && $hash->{CL}{'.iDefCmdMethod'} eq 'always' )
    {
        my $cmdO = $hash->{CL}{'.iDefCmdOrigin'};

        if (   defined( $cmds{$cmdO} )
            && defined( $hash->{CL}{'.iDefCmdOverwrite'} )
            && $hash->{CL}{'.iDefCmdOverwrite'} )
        {
            my $cmd = $search;
            $cmd =~ s/^$cmdO//;
            $cmd = $cmdO . '!' . ( $cmd && $cmd ne '' ? ' ' . $cmd : '' );

            unshift @ret,
                $lb
              . $lb
              . 'Did you mean to <a href="?cmd='
              . $cmd
              . $FW_CSRF
              . '">run command '
              . $cmdO
              . '</a> instead?';
        }

        delete $hash->{CL}{'.iDefCmdOrigin'};
        delete $hash->{CL}{'.iDefCmdMethod'};
        delete $hash->{CL}{'.iDefCmdOverwrite'};
    }

    if ($found) {
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#searchResultPerl">' : '' )
          . $foundPerl . ' '
          . ( $foundPerl > 1 ? 'Perl packages' : 'Perl package' )
          . ( $html          ? '</a>'          : '' )
          if ($foundPerl);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#searchResultMaintainers">' : '' )
          . $foundMaintainers . ' '
          . ( $foundMaintainers > 1 ? 'authors' : 'author' )
          . ( $html                 ? '</a>'    : '' )
          if ($foundMaintainers);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#searchResultKeywords">' : '' )
          . $foundKeywords . ' '
          . ( $foundKeywords > 1 ? 'keywords' : 'keyword' )
          . ( $html              ? '</a>'     : '' )
          if ($foundKeywords);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#searchResultPackages">' : '' )
          . $foundPackages . ' '
          . ( $foundPackages > 1 ? 'packages' : 'package' )
          . ( $html              ? '</a>'     : '' )
          if ($foundPackages);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#searchResultModules">' : '' )
          . $foundModules . ' '
          . ( $foundModules > 1 ? 'modules' : 'module' )
          . ( $html             ? '</a>'    : '' )
          if ($foundModules);
        unshift @ret,
            $lb
          . $space
          . $space
          . ( $html ? '<a href="#searchResultDevices">' : '' )
          . $foundDevices . ' '
          . ( $foundDevices > 1 ? 'devices' : 'device' )
          . ( $html             ? '</a>'    : '' )
          if ($foundDevices);
        unshift @ret,
          $found . ' total search ' . ( $found > 1 ? 'results:' : 'result:' );
    }
    else {
        unshift @ret,
            $tOpen
          . $trOpenOdd
          . $tdOpen
          . 'Nothing found'
          . $tdClose
          . $trClose
          . $tClose
          . $lb
          . $lb;
    }

    push @ret, $tdClose . $trClose . $tClose . $blockClose;

    unshift @ret,
        $blockOpen
      . $blockClose
      . ( $html ? '<a name="searchResultTOP"></a>' : '' )
      . $blockOpen
      . $tTitleOpen
      . 'Search Result'
      . $tTitleClose
      . $tOpen
      . $trOpen
      . $tdOpen
      . $blockOpen
      . $blockClose;

    return $header . join( "\n", @ret ) . $footer;
}

#TODO
# - show master/slave dependencies
# - show parent/child dependencies
# - show other dependant/related modules
# - fill empty keywords
# - Get Community Support URL from MAINTAINERS.txt
sub CreateMetadataList ($$$) {
    my ( $hash, $getCmd, $modName ) = @_;
    $modName = 'Global' if ( uc($modName) eq 'FHEM' );
    my $modType = lc($getCmd) eq 'showmoduleinfo' ? 'module' : 'package';

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    return 'Unknown module ' . $modName
      if ( $modType eq 'module' && !defined( $modules{$modName} ) );

    FHEM::Meta::Load($modName);

    return 'Unknown package ' . $modName
      if ( $modType eq 'package'
        && !defined( $packages{$modName} ) );

    return 'No metadata found about module '
      . $modName
      if (
        $modType eq 'module'
        && (  !defined( $modules{$modName}{META} )
            || scalar keys %{ $modules{$modName}{META} } == 0 )
      );

    return 'No metadata found about package '
      . $modName
      if (
        $modType eq 'package'
        && (  !defined( $packages{$modName}{META} )
            || scalar keys %{ $packages{$modName}{META} } == 0 )
      );

    my $modMeta =
        $modType eq 'module'
      ? $modules{$modName}{META}
      : $packages{$modName}{META};
    my @ret;
    my $html =
      defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : 0;

    my $header = '';
    my $footer = '';
    if ($html) {
        $header =
'<html><div class="detLink installerBack" style="float:right"><a href="?detail='
          . $hash->{NAME}
          . '">&larr; back to FHEM Installer</a></div>';
        $footer = '</html>';
    }

    my $blockOpen   = '';
    my $tTitleOpen  = '';
    my $tTitleClose = '';
    my $tOpen       = '';
    my $tCOpen      = '';
    my $tCClose     = '';
    my $tHOpen      = '';
    my $tHClose     = '';
    my $tBOpen      = '';
    my $tBClose     = '';
    my $tFOpen      = '';
    my $tFClose     = '';
    my $trOpen      = '';
    my $trOpenEven  = '';
    my $trOpenOdd   = '';
    my $thOpen      = '';
    my $thOpen2     = '';
    my $thOpen3     = '';
    my $tdOpen      = '';
    my $tdOpen2     = '';
    my $tdOpen3     = '';
    my $strongOpen  = '';
    my $strongClose = '';
    my $tdClose     = "\t\t\t";
    my $thClose     = "\t\t\t";
    my $trClose     = '';
    my $tClose      = '';
    my $blockClose  = '';
    my $colorRed    = '';
    my $colorGreen  = '';
    my $colorClose  = '';

    if ($html) {
        $blockOpen   = '<div class="makeTable wide internals">';
        $tTitleOpen  = '<span class="mkTitle">';
        $tTitleClose = '</span>';
        $tOpen       = '<table class="block wide internals wrapcolumns">';
        $tCOpen      = '<caption style="text-align: left; font-size: larger;">';
        $tCClose     = '</caption>';
        $tHOpen      = '<thead>';
        $tHClose     = '</thead>';
        $tBOpen      = '<tbody>';
        $tBClose     = '</tbody>';
        $tFOpen      = '<tfoot style="font-size: smaller;">';
        $tFClose     = '</tfoot>';
        $trOpen      = '<tr class="column">';
        $trOpenEven  = '<tr class="column even">';
        $trOpenOdd   = '<tr class="column odd">';
        $thOpen      = '<th style="text-align: left; vertical-align: top;">';
        $thOpen2 =
          '<th style="text-align: left; vertical-align: top;" colspan="2">';
        $thOpen3 =
          '<th style="text-align: left; vertical-align: top;" colspan="3">';
        $tdOpen      = '<td style="vertical-align: top;">';
        $tdOpen2     = '<td style="vertical-align: top;" colspan="2">';
        $tdOpen3     = '<td style="vertical-align: top;" colspan="3">';
        $strongOpen  = '<strong>';
        $strongClose = '</strong>';
        $tdClose     = '</td>';
        $thClose     = '</th>';
        $trClose     = '</tr>';
        $tClose      = '</table>';
        $blockClose  = '</div>';
        $colorRed    = '<span style="color: red">';
        $colorGreen  = '<span style="color: green">';
        $colorClose  = '</span>';
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
      homepage
      wiki
      command_reference
      community_support
      commercial_support
      bugtracker
      version_control
      license
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
    my $FW_CSRF = (
        defined( $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN} )
        ? '&fwcsrf=' . $defs{ $hash->{CL}{SNAME} }{CSRFTOKEN}
        : ''
    );

    push @ret,
        $blockOpen
      . $tTitleOpen
      . ucfirst($modType)
      . ' Information'
      . $tTitleClose
      . $tOpen;

    my $linecount = 1;
    foreach my $mAttr (@mAttrs) {
        next
          if (
            $mAttr eq 'release_status'
            && ( !defined( $modMeta->{release_status} )
                || $modMeta->{release_status} eq 'stable' )
          );
        next
          if ( $mAttr eq 'copyright'
            && !defined( $modMeta->{x_copyright} ) );
        next
          if (
            $mAttr eq 'abstract'
            && (   !defined( $modMeta->{abstract} )
                || $modMeta->{abstract} eq 'n/a'
                || $modMeta->{abstract} eq '' )
          );
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
        next
          if (
            $mAttr eq 'keywords'
            && (   !defined( $modMeta->{keywords} )
                || !@{ $modMeta->{keywords} } )
          );
        next
          if ( $mAttr eq 'version'
            && ( !defined( $modMeta->{version} ) ) );
        next
          if (
            $mAttr eq 'version_control'
            && (   !defined( $modMeta->{resources} )
                || !defined( $modMeta->{resources}{repository} ) )
          );
        next
          if ( $mAttr eq 'release_date'
            && ( !defined( $modMeta->{x_vcs} ) ) );
        next
          if ( $mAttr eq 'command_reference'
            && $modType eq 'package' );

        my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;
        my $mAttrName = $mAttr;
        $mAttrName =~ s/_/$space/g;
        $mAttrName =~ s/([\w'&]+)/\u\L$1/g;

        my $webname =
          AttrVal( $hash->{CL}{SNAME}, 'webname', 'fhem' );

        $l .= $thOpen . $mAttrName . $thClose;

        # these attributes do not exist under that name in META.json
        if ( !defined( $modMeta->{$mAttr} ) ) {
            $l .= $tdOpen;

            if ( $mAttr eq 'release_date' ) {
                if ( defined( $modMeta->{x_vcs} ) ) {
                    $l .= $modMeta->{x_vcs}[7];
                }
                else {
                    $l .= '-';
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

                if ( $html && $copyWeb ) {
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

            elsif ( $mAttr eq 'command_reference' ) {
                if (   defined( $hash->{CL} )
                    && defined( $hash->{CL}{TYPE} )
                    && $hash->{CL}{TYPE} eq 'FHEMWEB' )
                {
                    $l .=
                        '<a href="/'
                      . $webname
                      . '/docs/commandref.html#'
                      . ( $modName eq 'Global' ? 'global' : $modName )
                      . '" target="_blank">Offline version</a>';
                }

                if (   defined( $modMeta->{resources} )
                    && defined( $modMeta->{resources}{x_commandref} )
                    && defined( $modMeta->{resources}{x_commandref}{web} ) )
                {
                    my $title =
                      defined( $modMeta->{resources}{x_commandref}{title} )
                      ? $modMeta->{resources}{x_commandref}{title}
                      : 'Online version';

                    $l .=
                        ( $webname ? ' | ' : '' )
                      . '<a href="'
                      . $modMeta->{resources}{x_commandref}{web}
                      . '" target="_blank">'
                      . $title . '</a>';
                }
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

                $l .=
                    '<a href="'
                  . $modMeta->{resources}{x_wiki}{web}
                  . '" target="_blank">'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'community_support'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_support_community} )
                && defined( $modMeta->{resources}{x_support_community}{web} ) )
            {

                my $board = $modMeta->{resources}{x_support_community};
                $board =
                  $modMeta->{resources}{x_support_community}{subCommunity}
                  if (
                    defined(
                        $modMeta->{resources}{x_support_community}{subCommunity}
                    )
                  );

                my $title =
                  defined( $board->{title} ) ? $board->{title}
                  : (
                    $board->{web} =~ m/^(?:https?:\/\/)?forum\.fhem\.de/i
                    ? 'FHEM Forum'
                    : ''
                  );

                $title = 'FHEM Forum: ' . $title
                  if ( $title ne ''
                    && $title !~ m/^FHEM Forum/i
                    && $board->{web} =~ m/^(?:https?:\/\/)?forum\.fhem\.de/i );

                $l .= 'Limited - '
                  if ( defined( $modMeta->{x_support_status} )
                    && $modMeta->{x_support_status} eq 'limited' );

                $l .=
                    '<a href="'
                  . $board->{web}
                  . '" target="_blank"'
                  . (
                    defined( $board->{description} )
                    ? ' title="'
                      . $board->{description}
                      . '"'
                    : (
                        defined(
                            $modMeta->{resources}{x_support_community}
                              {description}
                          )
                        ? ' title="'
                          . $modMeta->{resources}{x_support_community}
                          {description} . '"'
                        : ''
                    )
                  )
                  . '>'
                  . $title . '</a>';
            }

            elsif ($mAttr eq 'commercial_support'
                && defined( $modMeta->{resources} )
                && defined( $modMeta->{resources}{x_support_commercial} )
                && defined( $modMeta->{resources}{x_support_commercial}{web} ) )
            {
                my $title =
                  defined( $modMeta->{resources}{x_support_commercial}{title} )
                  ? $modMeta->{resources}{x_support_commercial}{title}
                  : $modMeta->{resources}{x_support_commercial}{web};

                $l .= 'Limited - '
                  if ( $modMeta->{x_support_status} eq 'limited' );

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
                    : (
                        $modMeta->{resources}{bugtracker}{web} =~
                          m/^(?:https?:\/\/)?github\.com\/fhem/i
                        ? 'Github Issues: ' . $modMeta->{name}
                        : $modMeta->{resources}{bugtracker}{web}
                    )
                  );

                # add prefix if user defined title
                $title = 'FHEM Forum: ' . $title
                  if ( $title ne ''
                    && $title !~ m/^FHEM Forum/i
                    && $modMeta->{resources}{bugtracker}{web} =~
                    m/^(?:https?:\/\/)?forum\.fhem\.de/i );
                $title = 'Github Issues: ' . $title
                  if ( $title ne ''
                    && $title !~ m/^Github issues/i
                    && $modMeta->{resources}{bugtracker}{web} =~
                    m/^(?:https?:\/\/)?github\.com\/fhem/i );

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

                    # master link
                    my $url =
                      $modMeta->{resources}{repository}{web};

                    if (
                        defined( $modMeta->{resources}{repository}{x_branch} )
                        && defined( $modMeta->{resources}{repository}{x_dev} )
                        && defined(
                            $modMeta->{resources}{repository}{x_dev}{x_branch}
                        )
                        && $modMeta->{resources}{repository}{x_branch} ne
                        $modMeta->{resources}{repository}{x_dev}{x_branch}
                      )
                    {
                        # master entry
                        $l .=
                            'View online source code: <a href="'
                          . $url
                          . '" target="_blank">'
                          . $modMeta->{resources}{repository}{x_branch}
                          . '</a>';

                        # dev link
                        $url =
                          $modMeta->{resources}{repository}{x_dev}{web};

                        # dev entry
                        $l .=
                            ' | <a href="'
                          . $url
                          . '" target="_blank">'
                          . (
                            defined(
                                $modMeta->{resources}{repository}{x_dev}
                                  {x_branch}
                              )
                            ? $modMeta->{resources}{repository}{x_dev}{x_branch}
                            : 'dev'
                          ) . '</a>';
                    }

                    # master entry
                    else {
                        $l .=
                            '<a href="'
                          . $url
                          . '" target="_blank">View online source code</a>';
                    }

                    $l .= $lb;
                }

                # VCS link
                my $url =
                  $modMeta->{resources}{repository}{url};

                $l .=
                    uc( $modMeta->{resources}{repository}{type} )
                  . ' repository: '
                  . $modMeta->{resources}{repository}{url};

                if (
                    defined(
                        $modMeta->{resources}{repository}{x_branch_master}
                    )
                  )
                {
                    $l .=
                        $lb
                      . 'Main branch: '
                      . $modMeta->{resources}{repository}{x_branch_master};
                }

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
                    $l .=
                        $lb
                      . 'Dev branch: '
                      . $modMeta->{resources}{repository}{x_branch_dev};
                }
            }
            else {
                $l .= '-';
            }

            $l .= $tdClose;
        }

        # these text attributes can be shown directly
        elsif ( !ref( $modMeta->{$mAttr} ) ) {
            $l .= $tdOpen;

            my $mAttrVal =
                 defined( $modMeta->{x_lang} )
              && defined( $modMeta->{x_lang}{$lang} )
              && defined( $modMeta->{x_lang}{$lang}{$mAttr} )
              ? $modMeta->{x_lang}{$lang}{$mAttr}
              : $modMeta->{$mAttr};
            $mAttrVal =~ s/\\n/$lb/g;

            if ( $mAttr eq 'license' ) {
                if (   defined( $modMeta->{resources} )
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
            }
            elsif ( $mAttr eq 'version' ) {
                if ( $mAttrVal eq '0.000000001' ) {
                    $mAttrVal = '-';
                }
                elsif ( $modMeta->{x_file}[7] ne 'generated/vcs' ) {
                    $mAttrVal = version->parse($mAttrVal)->normal;

                    # only show maximum featurelevel for fhem.pl
                    $mAttrVal = $1
                      if ( $modName eq 'Global'
                        && $mAttrVal =~ m/^(v\d+\.\d+).*/ );

                    # Only add commit revision when it is not
                    #   part of the version already
                    $mAttrVal .= '-s' . $modMeta->{x_vcs}[5]
                      if ( defined( $modMeta->{x_vcs} )
                        && $modMeta->{x_vcs}[5] ne '' );
                }
            }

            # Add filename to module name
            $mAttrVal .= ' (' . $modMeta->{x_file}[2] . ')'
              if ( $modType eq 'module'
                && $mAttr eq 'name'
                && $modName ne 'Global' );

            $l .= $mAttrVal . $tdClose;
        }

        # this attribute is an array and needs further processing
        elsif (ref( $modMeta->{$mAttr} ) eq 'ARRAY'
            && @{ $modMeta->{$mAttr} } > 0
            && $modMeta->{$mAttr}[0] ne '' )
        {
            $l .= $tdOpen;

            if ( $mAttr eq 'author' ) {
                my $authorCount = scalar @{ $modMeta->{$mAttr} };
                my $counter     = 0;

                foreach ( @{ $modMeta->{$mAttr} } ) {
                    next if ( $_ eq '' );

                    my $authorName;
                    my $authorEditorOnly;
                    my $authorEmail;

                    if ( $_ =~
m/^([^<>\n\r]+?)(?:\s+(\(last release only\)))?(?:\s+(?:<(.*)>))?$/
                      )
                    {
                        $authorName       = $1;
                        $authorEditorOnly = $2 ? ' ' . $2 : '';
                        $authorEmail      = $3;
                    }

                    my $authorNameEmail = $authorName;

                    # add alias name if different
                    if (   defined( $modMeta->{x_fhem_maintainer} )
                        && ref( $modMeta->{x_fhem_maintainer} ) eq 'ARRAY'
                        && @{ $modMeta->{x_fhem_maintainer} } > 0
                        && $modMeta->{x_fhem_maintainer}[$counter] ne '' )
                    {

                        my $alias = $modMeta->{x_fhem_maintainer}[$counter];

                        if ( $alias eq $authorName ) {
                            $authorNameEmail =
                                '<a href="?cmd=get '
                              . $hash->{NAME}
                              . ' search '
                              . $alias
                              . $FW_CSRF . '">'
                              . $authorName . '</a>'
                              . $authorEditorOnly
                              if ($html);
                        }
                        else {
                            if ($html) {
                                $authorNameEmail =
                                    $authorName
                                  . ', alias <a href="?cmd=get '
                                  . $hash->{NAME}
                                  . ' search '
                                  . $alias
                                  . $FW_CSRF . '">'
                                  . $alias . '</a>'
                                  . $authorEditorOnly;
                            }
                            else {
                                $authorNameEmail =
                                    $authorName
                                  . $authorEditorOnly
                                  . ', alias '
                                  . $alias;
                            }
                        }
                    }

                    $l .= $lb if ($counter);
                    $l .= $lb . 'Co-' . $mAttrName . ':' . $lb
                      if ( $counter == 1 );
                    $l .=
                        $authorNameEmail
                      ? $authorNameEmail
                      : $authorName . $authorEditorOnly;

                    $counter++;
                }
            }
            elsif ( $mAttr eq 'keywords' ) {
                my $counter = 0;
                foreach my $keyword ( @{ $modMeta->{$mAttr} } ) {
                    $l .= ', ' if ($counter);
                    my $descr = FHEM::Meta::GetKeywordDesc( $keyword, $lang );

                    if ($html) {
                        $l .=
                            '<a href="?cmd=get '
                          . $hash->{NAME}
                          . ' search '
                          . $keyword
                          . $FW_CSRF . '"'
                          . (
                            $descr ne ''
                            ? ' title="' . $descr . '"'
                            : ''
                          )
                          . '>'
                          . $keyword . '</a>';
                    }
                    else {
                        $l .= $keyword;
                    }

                    $counter++;
                }
            }
            else {
                $l .= join ', ', @{ $modMeta->{$mAttr} };
            }

            $l .= $tdClose;
        }

        # woops, we don't know how to handle this attribute
        else {
            $l .= $tdOpen . '?' . $tdClose;
        }

        $l .= $trClose;

        push @ret, $l;
        $linecount++;
    }

    push @ret,
        $tFOpen
      . $trOpen
      . (
        $html
        ? '<td style="text-align:right;" colspan="2">'
        : ''
      )
      . 'Based on data generated by '
      . $lb
      . $modMeta->{generated_by}
      . $tdClose
      . $trClose
      . $tFClose;

    push @ret, $tClose . $blockClose;

    # show FHEM modules who use this package
    @mAttrs = qw(
      requires
      recommends
      suggests
    );

    $linecount = 1;
    foreach my $mAttr (@mAttrs) {
        next
          unless ( defined( $FHEM::Meta::dependents{pkgs}{$modName}{$mAttr} )
            && ref( $FHEM::Meta::dependents{pkgs}{$modName}{$mAttr} ) eq
            'ARRAY'
            && @{ $FHEM::Meta::dependents{pkgs}{$modName}{$mAttr} } > 0 );

        my $dependents = '';

        my $counter = 0;
        foreach my $dependant ( sort { "\L$a" cmp "\L$b" }
            @{ $FHEM::Meta::dependents{pkgs}{$modName}{$mAttr} } )
        {
            my $link = $dependant;
            $link =
                '<a href="?cmd=get '
              . $hash->{NAME}
              . (
                FHEM::Meta::ModuleIsInternal($dependant) eq 'module'
                ? ' showModuleInfo '
                : ' showPackageInfo '
              )
              . $dependant
              . $FW_CSRF . '">'
              . $dependant . '</a>'
              if ($html);

            $dependents .= ', ' if ($counter);
            $dependents .= $link;
            $counter++;
        }

        if ( $dependents ne '' ) {
            if ( $linecount == 1 ) {
                push @ret,
                    $blockOpen
                  . $tTitleOpen
                  . 'FHEM internal dependencies'
                  . $tTitleClose
                  . $tOpen;

                push @ret, $tHOpen . $trOpen;

                push @ret, $thOpen . 'Importance' . $thClose;

                push @ret, $thOpen . 'Dependent Modules' . $thClose;

                push @ret, $trClose . $tHClose;
            }

            my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

            my $importance = $mAttr;
            $importance = 'required'    if ( $mAttr eq 'requires' );
            $importance = 'recommended' if ( $mAttr eq 'recommends' );
            $importance = 'suggested'   if ( $mAttr eq 'suggests' );

            $l .= $tdOpen . $importance . $tdClose;
            $l .= $tdOpen . $dependents . $tdClose;

            $l .= $trClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret,
        $tFOpen
      . $trOpen
      . $tdOpen2
      . $strongOpen . 'Hint:'
      . $strongClose
      . ' Dependents can only be shown here if they were loaded into the metadata cache before.'
      . $tdClose
      . $trClose
      . $tFClose
      . $tClose
      . $blockClose
      if ( $linecount > 1 );

    if (
           $modType eq 'module'
        && $modName ne 'Global'
        && (   !defined( $modules{$modName}{META} )
            || !defined( $modules{$modName}{META}{keywords} )
            || !
            grep ( /^fhem-mod-command$/,
                @{ $modules{$modName}{META}{keywords} } ) )
      )
    {
        push @ret, $blockOpen . $tTitleOpen . 'Devices' . $tTitleClose . $tOpen;

        my $linecount = 1;

        if ( defined( $modules{$modName}{LOADED} )
            && $modules{$modName}{LOADED} )
        {
            my @instances = devspec2array( 'TYPE=' . $modName );
            if ( @instances > 0 ) {
                push @ret,
                    $tHOpen
                  . $trOpen
                  . $thOpen . 'Name'
                  . $thClose
                  . $thOpen . 'State'
                  . $thClose
                  . $trClose
                  . $tHClose
                  . $tBOpen;

                foreach my $instance ( sort { "\L$a" cmp "\L$b" } @instances ) {
                    next if ( defined( $defs{$instance}{TEMPORARY} ) );

                    my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

                    my $device = $instance;
                    $device =
                        '<a href="?detail='
                      . $instance . '">'
                      . $instance . '</a>'
                      if ($html);

                    $l .= $tdOpen . $device . $tdClose;
                    $l .= $tdOpen . $defs{$instance}{STATE} . $tdClose;

                    push @ret, $l;
                    $linecount++;
                }

                push @ret, $tBClose;
            }
            else {
                push @ret,
                    $tBOpen
                  . $trOpen
                  . $tdOpen
                  . 'The module was once loaded into memory, '
                  . 'but currently there is no device defined.'
                  . $tdClose
                  . $trClose
                  . $tBClose;
            }
        }
        else {
            push @ret,
                $tBOpen
              . $trOpen
              . $tdOpen
              . 'The module is currently not in use.'
              . $tdClose
              . $trClose
              . $tBClose;
        }

        push @ret, $tClose . $blockClose;
    }

    LoadInstallStatusPerl($modName);

    push @ret,
        $blockOpen
      . $tTitleOpen
      . 'System Prerequisites'
      . $tTitleClose
      . $tOpen
      . $trOpen
      . $tdOpen;

    push @ret, $blockOpen . $tOpen . $tCOpen . 'Perl Packages' . $tCClose;

    if (   defined( $modMeta->{prereqs} )
        && defined( $modMeta->{prereqs}{runtime} ) )
    {
        @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tHOpen . $trOpen;

        push @ret, $thOpen . 'Name' . $thClose;

        push @ret, $thOpen . 'Importance' . $thClose;

        push @ret, $thOpen . 'Status' . $thClose;

        push @ret, $trClose . $tHClose . $tBOpen;

        $linecount = 1;
        foreach my $mAttr (@mAttrs) {
            next
              unless ( defined( $modMeta->{prereqs}{runtime}{$mAttr} )
                && keys %{ $modMeta->{prereqs}{runtime}{$mAttr} } > 0 );

            foreach
              my $prereq ( sort keys %{ $modMeta->{prereqs}{runtime}{$mAttr} } )
            {
                my $isFhem    = FHEM::Meta::ModuleIsInternal($prereq);
                my $installed = $pkgStatus{Perl}{pkgs}{$prereq}{status};

                my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

                my $importance = $mAttr;
                $importance = 'required'    if ( $mAttr eq 'requires' );
                $importance = 'recommended' if ( $mAttr eq 'recommends' );
                $importance = 'suggested'   if ( $mAttr eq 'suggests' );

                my $version = $modMeta->{prereqs}{runtime}{$mAttr}{$prereq};
                $version = '' if ( !defined($version) || $version eq '0' );

                my $inherited = '';
                if (
                    defined( $modMeta->{prereqs}{runtime}{x_inherited} )
                    && defined(
                        $modMeta->{prereqs}{runtime}{x_inherited}{$prereq}
                    )
                  )
                {
                    $inherited = '[inherited]';
                    $inherited = '<span title="Inherited from '
                      . join(
                        ', ',
                        @{
                            $modMeta->{prereqs}{runtime}{x_inherited}{$prereq}
                        }
                      )
                      . '" style="color: grey;">'
                      . $inherited
                      . '</span>'
                      if ($html);
                }

                $prereq =
                    '<a href="https://metacpan.org/pod/'
                  . $prereq
                  . '" target="_blank">'
                  . $prereq . '</a>'
                  if ( $html
                    && $installed ne 'built-in'
                    && $installed ne 'included' );

                $prereq =
                    '<a href="?cmd=get '
                  . $hash->{NAME}
                  . (
                    $isFhem eq 'module'
                    ? ' showModuleInfo '
                    : ' showPackageInfo '
                  )
                  . $prereq
                  . $FW_CSRF . '">'
                  . $prereq . '</a>'
                  if ( $html
                    && $installed eq 'included' );

                if (
                    $mAttr ne 'requires'
                    && (   $installed eq 'missing'
                        || $installed eq 'outdated' )
                  )
                {
                    $installed = '';

                }
                elsif ($html) {
                    if ( $installed eq 'installed' ) {
                        $installed = $colorGreen . $installed . $colorClose;
                    }
                    elsif ($installed eq 'missing'
                        || $installed eq 'outdated' )
                    {
                        $installed =
                            $colorRed
                          . $strongOpen
                          . uc($installed)
                          . $strongClose
                          . $colorClose;
                    }
                }

                $l .=
                    $tdOpen
                  . $prereq
                  . ( $inherited ne '' ? " $inherited" : '' )
                  . ( $version ne ''   ? " ($version)" : '' )
                  . $tdClose;
                $l .= $tdOpen . $importance . $tdClose;
                $l .= $tdOpen . $installed . $tdClose;

                $l .= $trClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tBClose;

        push @ret,
            $tFOpen
          . $trOpenEven
          . $tdOpen3
          . $strongOpen . 'Hint:'
          . $strongClose
          . ' The module does not provide Perl prerequisites from its metadata.'
          . $lb
          . 'This result is based on automatic source code analysis '
          . 'and can be incorrect.'
          . $tdClose
          . $trClose
          . $tFClose
          if ( defined( $modMeta->{x_prereqs_src} )
            && $modMeta->{x_prereqs_src} ne 'META.json' );
    }
    elsif ( defined( $modMeta->{x_prereqs_src} ) ) {
        push @ret,
            $tBOpen
          . $trOpenOdd
          . $tdOpen
          . 'No known prerequisites.'
          . $tdClose
          . $trClose
          . $tBClose;
    }
    else {
        push @ret,
            $tBOpen
          . $trOpenOdd
          . $tdOpen
          . 'Module metadata do not contain any prerequisites.' . "\n"
          . 'For automatic source code analysis, please install Perl::PrereqScanner::NotQuiteLite first.'
          . $tdClose
          . $trClose
          . $tBClose;
    }
    push @ret, $tClose . $blockClose;

    if (   defined( $modMeta->{x_prereqs_nodejs} )
        && defined( $modMeta->{x_prereqs_nodejs}{runtime} ) )
    {
        push @ret,
            $blockOpen
          . $tTitleClose
          . $tOpen
          . $tCOpen
          . 'Node.js Packages'
          . $tCClose;

        my @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tHOpen . $trOpen;

        push @ret, $thOpen . 'Name' . $thClose;

        push @ret, $thOpen . 'Importance' . $thClose;

        push @ret, $thOpen . 'Status' . $thClose;

        push @ret, $trClose . $tHClose . $tBOpen;

        $linecount = 1;
        foreach my $mAttr (@mAttrs) {
            next
              unless ( defined( $modMeta->{x_prereqs_nodejs}{runtime}{$mAttr} )
                && keys %{ $modMeta->{x_prereqs_nodejs}{runtime}{$mAttr} } >
                0 );

            foreach my $prereq (
                sort
                keys %{ $modMeta->{x_prereqs_nodejs}{runtime}{$mAttr} }
              )
            {
                my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

                my $importance = $mAttr;
                $importance = 'required'    if ( $mAttr eq 'requires' );
                $importance = 'recommended' if ( $mAttr eq 'recommends' );
                $importance = 'suggested'   if ( $mAttr eq 'suggests' );

                my $version =
                  $modMeta->{x_prereqs_nodejs}{runtime}{$mAttr}{$prereq};
                $version = '' if ( !defined($version) || $version eq '0' );

                my $check     = __IsInstalledNodejs($prereq);
                my $installed = '';
                if ($check) {
                    if ( $check =~ m/^\d+\./ ) {
                        my $nverReq =
                            $version ne ''
                          ? $version
                          : 0;
                        my $nverInst = $check;

                        #TODO suport for version range:
                        #https://metacpan.org/pod/CPAN::Meta::Spec#Version-Range
                        if ( $nverReq > 0 && $nverInst < $nverReq ) {
                            $installed .=
                                $colorRed
                              . 'OUTDATED'
                              . $colorClose . ' ('
                              . $check . ')';
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

                $installed = $colorGreen . $installed . $colorClose;

                $prereq =
                    '<a href="https://www.npmjs.com/package/'
                  . $prereq
                  . '" target="_blank">'
                  . $prereq . '</a>'
                  if ($html);

                $l .=
                    $tdOpen
                  . $prereq
                  . ( $version ne '' ? " ($version)" : '' )
                  . $tdClose;
                $l .= $tdOpen . $importance . $tdClose;
                $l .= $tdOpen . $installed . $tdClose;

                $l .= $trClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tBClose . $tClose . $blockClose;
    }

    if (   defined( $modMeta->{x_prereqs_python} )
        && defined( $modMeta->{x_prereqs_python}{runtime} ) )
    {
        push @ret, $blockOpen . $tOpen . $tCOpen . 'Python Packages' . $tCClose;

        my @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tHOpen . $trOpen;

        push @ret, $thOpen . 'Name' . $thClose;

        push @ret, $thOpen . 'Importance' . $thClose;

        push @ret, $thOpen . 'Status' . $thClose;

        push @ret, $trClose . $tHClose . $tBOpen;

        $linecount = 1;
        foreach my $mAttr (@mAttrs) {
            next
              unless ( defined( $modMeta->{x_prereqs_python}{runtime}{$mAttr} )
                && keys %{ $modMeta->{x_prereqs_python}{runtime}{$mAttr} } >
                0 );

            foreach my $prereq (
                sort
                keys %{ $modMeta->{x_prereqs_python}{runtime}{$mAttr} }
              )
            {
                my $l = $linecount % 2 == 0 ? $trOpenEven : $trOpenOdd;

                my $importance = $mAttr;
                $importance = 'required'    if ( $mAttr eq 'requires' );
                $importance = 'recommended' if ( $mAttr eq 'recommends' );
                $importance = 'suggested'   if ( $mAttr eq 'suggests' );

                my $version =
                  $modMeta->{x_prereqs_python}{runtime}{$mAttr}{$prereq};
                $version = '' if ( !defined($version) || $version eq '0' );

                my $check     = __IsInstalledPython($prereq);
                my $installed = '';
                if ($check) {
                    if ( $check =~ m/^\d+\./ ) {
                        my $nverReq =
                            $version ne ''
                          ? $version
                          : 0;
                        my $nverInst = $check;

                        #TODO suport for version range:
                        #https://metacpan.org/pod/CPAN::Meta::Spec#Version-Range
                        if ( $nverReq > 0 && $nverInst < $nverReq ) {
                            $installed .=
                                $colorRed
                              . 'OUTDATED'
                              . $colorClose . ' ('
                              . $check . ')';
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

                my $isPerlPragma = FHEM::Meta::ModuleIsPerlPragma($prereq);
                my $isPerlCore =
                  $isPerlPragma ? 0 : FHEM::Meta::ModuleIsPerlCore($prereq);
                my $isFhem =
                  $isPerlPragma || $isPerlCore
                  ? 0
                  : FHEM::Meta::ModuleIsInternal($prereq);
                if ( $isPerlPragma || $isPerlCore || $prereq eq 'perl' ) {
                    $installed =
                      $installed ne 'installed'
                      ? "$installed (Perl built-in)"
                      : 'built-in';
                }
                elsif ($isFhem) {
                    $installed =
                      $installed ne 'installed'
                      ? "$installed (FHEM included)"
                      : 'included';
                }
                elsif ( $installed eq 'installed' ) {
                    $installed = $colorGreen . $installed . $colorClose;
                }

                $prereq =
                    '<a href="https://metacpan.org/pod/'
                  . $prereq
                  . '" target="_blank">'
                  . $prereq . '</a>'
                  if ( $html
                    && !$isFhem
                    && !$isPerlCore
                    && !$isPerlPragma
                    && $prereq ne 'perl' );

                $l .=
                    $tdOpen
                  . $prereq
                  . ( $version ne '' ? " ($version)" : '' )
                  . $tdClose;
                $l .= $tdOpen . $importance . $tdClose;
                $l .= $tdOpen . $installed . $tdClose;

                $l .= $trClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tBClose . $tClose . $blockClose;
    }

    push @ret, $tdClose . $trClose . $tClose . $blockClose;

    return $header . join( "\n", @ret ) . $footer;
}

sub CreateRawMetaJson ($$$) {
    my ( $hash, $getCmd, $modName ) = @_;
    $modName = 'Global' if ( uc($modName) eq 'FHEM' );
    my $modType = lc($getCmd) eq 'zzgetmodulemeta.json' ? 'module' : 'package';

    FHEM::Meta::Load($modName);

    return '{}'
      unless (
        (
               $modType eq 'module'
            && defined( $modules{$modName}{META} )
            && scalar keys %{ $modules{$modName}{META} } > 0
        )
        || (   $modType eq 'package'
            && defined( $packages{$modName}{META} )
            && scalar keys %{ $packages{$modName}{META} } > 0 )
      );

    my $j = JSON->new;
    $j->allow_nonref;
    $j->canonical;
    $j->pretty;
    if ( $modType eq 'module' ) {
        return $j->encode( $modules{$modName}{META} );

    }
    else {
        return $j->encode( $packages{$modName}{META} );
    }
}

sub __GetDefinedModulesFromFile($) {
    my ($filePath) = @_;
    my @modules;
    my $fh;

    if ( open( $fh, '<' . $filePath ) ) {
        while ( my $l = <$fh> ) {
            if ( $l =~ /^define\s+\S+\s+(\S+).*/ ) {
                my $modName = $1;
                push @modules, $modName
                  unless ( grep ( /^$modName$/, @modules ) );
            }
        }
        close($fh);
    }

    if (wantarray) {
        return @modules;
    }
    elsif ( @modules > 0 ) {
        return join( ',', @modules );
    }
}

sub LoadInstallStatusPerl(;$) {
    my ($modList) = @_;
    my $t = TimeNow();
    my @rets;

    my $unused = 0;
    my @lmodules;

    # if modList is undefined or is equal to '1'
    if ( !$modList || ( !ref($modList) && $modList eq '1' ) ) {
        $unused = 1 if ( $modList && $modList eq '1' );

        foreach ( keys %modules ) {

            # Only process loaded modules
            #   unless unused modules were
            #   explicitly requested
            push @lmodules,
              $_
              if (
                $unused
                || ( defined( $modules{$_}{LOADED} )
                    && $modules{$_}{LOADED} eq '1' )
              );
        }
    }

    # if a single module name was given
    elsif ( !ref($modList) ) {
        push @lmodules, $modList;
    }

    # if a list of module names was given
    elsif ( ref($modList) eq 'ARRAY' ) {
        foreach ( @{$modList} ) {
            push @lmodules, $_;
        }
    }

    # if a hash was given, assume every
    #   key is a module name
    elsif ( ref($modList) eq 'HASH' ) {
        foreach ( keys %{$modList} ) {
            push @lmodules, $_;
        }
    }

    # Wrong method use
    else {
        $@ =
          __PACKAGE__ . "LoadInstallStatusPerl: ERROR: Unknown parameter value";
        Log 1, $@;
        return "$@";
    }

    foreach my $modName (@lmodules) {
        $modName = 'Global' if ( uc($modName) eq 'FHEM' );
        my $type;

        if ( exists( $modules{$modName} ) && !exists( $packages{$modName} ) ) {
            $type = 'module';
        }
        elsif ( exists( $packages{$modName} ) && !exists( $modules{$modName} ) )
        {
            $type = 'package';
        }
        elsif ( exists( $packages{$modName} ) && exists( $modules{$modName} ) )
        {
            $type = 'module+package';
        }
        next unless ($type);

        foreach my $type ( split( '\+', $type ) ) {

            FHEM::Meta::Load($modName);

            next
              unless (
                ( $type eq 'module' && defined( $modules{$modName}{META} ) )
                || ( $type eq 'package'
                    && defined( $packages{$modName}{META} ) )
              );

            my $modMeta =
                $type eq 'module'
              ? $modules{$modName}{META}
              : $packages{$modName}{META};

            $pkgStatus{Perl}{analyzed} = 2
              unless ( defined( $modMeta->{x_prereqs_src} ) );

            # Perl
            if (   defined( $modMeta->{prereqs} )
                && defined( $modMeta->{prereqs}{runtime} ) )
            {
                my $modPreqs = $modMeta->{prereqs}{runtime};

                foreach my $mAttr (qw(requires recommends suggests)) {
                    next
                      unless ( defined( $modPreqs->{$mAttr} )
                        && keys %{ $modPreqs->{$mAttr} } > 0 );

                    foreach my $pkg ( keys %{ $modPreqs->{$mAttr} } ) {
                        push
                          @{ $pkgStatus{Perl}{pkgs}{$pkg}{ $type . 's' }{$mAttr}
                          },
                          $modName
                          unless (
                            grep ( /^$modName$/,
                                @{
                                    $pkgStatus{Perl}{pkgs}{$pkg}{ $type . 's' }
                                      {$mAttr}
                                } )
                          );

                        next
                          if (
                            defined( $pkgStatus{Perl}{pkgs}{$pkg}{status} ) );

                        my $fname = $pkg;
                        $fname =~
                          s/^.*://g;    # strip away any parent module names

                        my $isPerlPragma = FHEM::Meta::ModuleIsPerlPragma($pkg);
                        my $isPerlCore =
                          $isPerlPragma
                          ? 0
                          : FHEM::Meta::ModuleIsPerlCore($pkg);
                        my $isFhem =
                          $isPerlPragma || $isPerlCore
                          ? 0
                          : FHEM::Meta::ModuleIsInternal($pkg);

                        if ( $pkg eq 'perl' ) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'built-in';
                            $pkgStatus{Perl}{installed}{$pkg} =
                              version->parse($])->numify;
                        }
                        elsif ( $pkg eq 'FHEM' ) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'included';
                            $pkgStatus{Perl}{installed}{$pkg} =
                              $modules{'Global'}{META}{version};
                        }
                        elsif ( $pkg eq 'FHEM::Meta' || $pkg eq 'Meta' ) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'included';
                            $pkgStatus{Perl}{installed}{$pkg} =
                              FHEM::Meta->VERSION();
                        }
                        elsif ($isPerlPragma) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'built-in';
                            $pkgStatus{Perl}{installed}{$pkg} = 0;
                        }
                        elsif ($isPerlCore) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'built-in';
                            $pkgStatus{Perl}{installed}{$pkg} = 0;
                        }

                        # This is a FHEM package
                        elsif ( $isFhem && $isFhem eq 'package' ) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'included';
                            $pkgStatus{Perl}{installed}{$pkg} =
                              defined( $packages{$fname}{META} )
                              ? $packages{$fname}{META}{version}
                              : 0;
                        }

                        # This is a FHEM module being loaded as package
                        elsif ( $isFhem && $isFhem eq 'module' ) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'included';
                            $pkgStatus{Perl}{installed}{$pkg} =
                              defined( $modules{$fname}{META} )
                              ? $modules{$fname}{META}{version}
                              : 0;
                        }
                        elsif ( $pkg =~ /^Win32::/ && $^O ne 'MSWin32' ) {
                            $pkgStatus{Perl}{pkgs}{$pkg}{status} = 'n/a';
                        }
                        else {

                            my $pkgpath = $pkg . '.pm';
                            $pkgpath =~ s/::/\//g;

                            # remove any ealier tries to load
                            #  to get the original error message
                            foreach ( keys %INC ) {
                                delete $INC{$_}
                                  if ( !$INC{$_} );
                            }

                            #FIXME disable warnings does not work here...
                            no warnings;
                            my $verbose = AttrVal( 'global', 'verbose', 3 );
                            $attr{global}{verbose} = 0;
                            eval "no warnings; require $pkg;";
                            $attr{global}{verbose} = $verbose;
                            use warnings;

                            if ( $@ && $@ =~ m/^Can't locate (\S+)\.pm/i ) {
                                my $missing = $1;
                                $missing =~ s/\//::/g;
                                $pkgStatus{Perl}{pkgs}{$missing}{status} =
                                  'missing';
                                push @{ $pkgStatus{Perl}{missing}{$missing} },
                                  defined( $modPreqs->{$mAttr}{$missing} )
                                  ? $modPreqs->{$mAttr}{$missing}
                                  : 0;

                                $pkgStatus{Perl}{analyzed} = 1
                                  if ( $modMeta->{x_prereqs_src} ne 'META.json'
                                    && !$pkgStatus{Perl}{analyzed} );

                                # If the error message does contain a
                                #   different package name,
                                #   the actual package is installed and
                                #   misses another package by it's own
                                if ( $missing ne $pkg ) {
                                    my $v = eval "$pkg->VERSION()";
                                    $pkgStatus{Perl}{pkgs}{$pkg}{status} =
                                      'installed';
                                    $pkgStatus{Perl}{installed}{$pkg} =
                                      $v ? $v : 0;

                                    push @{ $pkgStatus{Perl}{pkgs}{$missing}
                                          { $type . 's' }{$mAttr} },
                                      $modName
                                      unless (
                                        grep ( /^$modName$/,
                                            @{
                                                $pkgStatus{Perl}{pkgs}{$missing}
                                                  { $type . 's' }{$mAttr}
                                            } )
                                      );

                                    # Lets also update the module meta data
                                    if ( $type eq 'module' ) {
                                        $modMeta->{prereqs}
                                          {runtime}{$mAttr}{$missing} = 0;
                                    }
                                    else {
                                        $packages{$modName}{META}{prereqs}
                                          {runtime}{$mAttr}{$missing} = 0;
                                    }
                                }
                            }
                            else {
                                $pkgStatus{Perl}{pkgs}{$pkg}{status} =
                                  'installed';
                                my $v = eval "$pkg->VERSION()";
                                $pkgStatus{Perl}{installed}{$pkg} = $v ? $v : 0;
                            }
                        }

                        # check for outdated version
                        if ( $pkgStatus{Perl}{pkgs}{$pkg}{status} eq 'installed'
                            || $pkg eq 'perl' )
                        {
                            my $reqV  = $modPreqs->{$mAttr}{$pkg};
                            my $instV = $pkgStatus{Perl}{installed}{$pkg};
                            if ( $reqV ne '0' && $instV ne '0' ) {
                                $reqV  = version->parse($reqV)->numify;
                                $instV = version->parse($instV)->numify;

                                #TODO suport for version range:
                                #  https://metacpan.org/pod/ \
                                #   CPAN::Meta::Spec#Version-Range
                                if ( $reqV > 0 && $instV < $reqV ) {

                                    $pkgStatus{Perl}{pkgs}{$pkg}{status} =
                                      'outdated';
                                    push @{ $pkgStatus{Perl}{outdated}{$pkg} },
                                      $reqV;

                                    $pkgStatus{Perl}{analyzed} = 1
                                      if (
                                        $modMeta->{x_prereqs_src} ne 'META.json'
                                        && !$pkgStatus{Perl}{analyzed} );
                                }
                            }
                        }

                        $pkgStatus{Perl}{pkgs}{$pkg}{timestamp} = $t;
                    }
                }
            }

            #TODO
            # nodejs
            # python
        }
    }

    # build installation hash
    foreach my $area ( keys %pkgStatus ) {
        foreach my $t (qw(missing outdated)) {
            if (   defined( $pkgStatus{$area}{$t} )
                && ref( $pkgStatus{$area}{$t} ) eq 'HASH'
                && %{ $pkgStatus{$area}{$t} } > 0 )
            {
                foreach my $pkg ( keys %{ $pkgStatus{$area}{$t} } ) {
                    next
                      unless ( ref( $pkgStatus{$area}{$t}{$pkg} ) eq 'ARRAY' );

                    # detect minimum required version
                    #   for missing and outdated packages
                    my $v = maxNum( 0, @{ $pkgStatus{$area}{$t}{$pkg} } );
                    $pkgStatus{$area}{$t}{$pkg} = $v;

                    if (
                        defined(
                            $pkgStatus{$area}{pkgs}{$pkg}{modules}{requires}
                        )
                        && @{ $pkgStatus{$area}{pkgs}{$pkg}{modules}{requires} }
                        > 0
                      )
                    {
                        $pkgStatus{counter}{total}++;
                        $pkgStatus{counter}{$t}++;
                        $pkgStatus{counter}{required}{total}++;
                        $pkgStatus{counter}{required}{$t}++;
                        $pkgStatus{counter}{required}{$area}{total}++;
                        $pkgStatus{counter}{required}{$area}{$t}++;
                        $pkgStatus{counter}{$area}{total}++;
                        $pkgStatus{counter}{$area}{$t}++;
                        $pkgStatus{counter}{$area}{required}{total}++;
                        $pkgStatus{counter}{$area}{required}{$t}++;

                        $pkgStatus{required}{$area}{$pkg}{status}  = $t;
                        $pkgStatus{required}{$area}{$pkg}{version} = $v;
                        $pkgStatus{required}{$area}{$pkg}{modules} =
                          $pkgStatus{$area}{pkgs}{$pkg}{modules}{requires};

                        # add other modules
                        if (
                            defined(
                                $pkgStatus{$area}{pkgs}{$pkg}{modules}
                                  {recommends}
                            )
                            && @{
                                $pkgStatus{$area}{pkgs}{$pkg}{modules}
                                  {recommends}
                            } > 0
                          )
                        {
                            foreach my $modName (
                                @{
                                    $pkgStatus{$area}{pkgs}{$pkg}{modules}
                                      {recommends}
                                }
                              )
                            {
                                push
                                  @{ $pkgStatus{required}{$area}{$pkg}{modules}
                                  },
                                  $modName
                                  unless (
                                    grep ( /^$modName$/,
                                        @{
                                            $pkgStatus{required}{$area}
                                              {$pkg}{modules}
                                        } )
                                  );
                            }
                        }

                        if (
                            defined(
                                $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests}
                            )
                            && @{
                                $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests}
                            } > 0
                          )
                        {
                            foreach my $modName (
                                @{
                                    $pkgStatus{$area}{pkgs}{$pkg}{modules}
                                      {suggests}
                                }
                              )
                            {
                                push
                                  @{ $pkgStatus{required}{$area}{$pkg}{modules}
                                  },
                                  $modName
                                  unless (
                                    grep ( /^$modName$/,
                                        @{
                                            $pkgStatus{required}{$area}
                                              {$pkg}{modules}
                                        } )
                                  );
                            }
                        }
                    }
                    elsif (
                        defined(
                            $pkgStatus{$area}{pkgs}{$pkg}{modules}{recommends}
                        )
                        && @{ $pkgStatus{$area}{pkgs}{$pkg}{modules}{recommends}
                        } > 0
                      )
                    {
                        $pkgStatus{counter}{total}++;
                        $pkgStatus{counter}{$t}++;
                        $pkgStatus{counter}{recommended}{total}++;
                        $pkgStatus{counter}{recommended}{$t}++;
                        $pkgStatus{counter}{recommended}{$area}{total}++;
                        $pkgStatus{counter}{recommended}{$area}{$t}++;
                        $pkgStatus{counter}{$area}{total}++;
                        $pkgStatus{counter}{$area}{$t}++;
                        $pkgStatus{counter}{$area}{recommended}{total}++;
                        $pkgStatus{counter}{$area}{recommended}{$t}++;

                        $pkgStatus{recommended}{$area}{$pkg}{status}  = $t;
                        $pkgStatus{recommended}{$area}{$pkg}{version} = $v;
                        $pkgStatus{recommended}{$area}{$pkg}{modules} =
                          $pkgStatus{$area}{pkgs}{$pkg}{modules}{recommends};

                        # add other modules
                        if (
                            defined(
                                $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests}
                            )
                            && @{
                                $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests}
                            } > 0
                          )
                        {
                            foreach my $modName (
                                @{
                                    $pkgStatus{$area}{pkgs}{$pkg}{modules}
                                      {suggests}
                                }
                              )
                            {
                                push @{ $pkgStatus{recommended}{$area}{$pkg}
                                      {modules} },
                                  $modName
                                  unless (
                                    grep ( /^$modName$/,
                                        @{
                                            $pkgStatus{recommended}{$area}
                                              {$pkg}{modules}
                                        } )
                                  );
                            }
                        }
                    }
                    elsif (
                        defined(
                            $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests}
                        )
                        && @{ $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests} }
                        > 0
                      )
                    {
                        $pkgStatus{counter}{total}++;
                        $pkgStatus{counter}{$t}++;
                        $pkgStatus{counter}{suggested}{total}++;
                        $pkgStatus{counter}{suggested}{$t}++;
                        $pkgStatus{counter}{suggested}{$area}{total}++;
                        $pkgStatus{counter}{suggested}{$area}{$t}++;
                        $pkgStatus{counter}{$area}{total}++;
                        $pkgStatus{counter}{$area}{$t}++;
                        $pkgStatus{counter}{$area}{suggested}{total}++;
                        $pkgStatus{counter}{$area}{suggested}{$t}++;

                        $pkgStatus{suggested}{$area}{$pkg}{status}  = $t;
                        $pkgStatus{suggested}{$area}{$pkg}{version} = $v;
                        $pkgStatus{suggested}{$area}{$pkg}{modules} =
                          $pkgStatus{$area}{pkgs}{$pkg}{modules}{suggests};
                    }
                }
            }
            else {
                $pkgStatus{counter}{$t}                     = 0;
                $pkgStatus{counter}{required}{$t}           = 0;
                $pkgStatus{counter}{required}{$area}{$t}    = 0;
                $pkgStatus{counter}{recommended}{$t}        = 0;
                $pkgStatus{counter}{recommended}{$area}{$t} = 0;
                $pkgStatus{counter}{suggested}{$t}          = 0;
                $pkgStatus{counter}{suggested}{$area}{$t}   = 0;
                $pkgStatus{counter}{$area}{$t}              = 0;
                $pkgStatus{counter}{$area}{required}{$t}    = 0;
                $pkgStatus{counter}{$area}{recommended}{$t} = 0;
                $pkgStatus{counter}{$area}{suggested}{$t}   = 0;
            }
        }
    }

    if (@rets) {
        $@ = join( "\n", @rets );
        return "$@";
    }

    return undef;
}

#TODO
# Checks whether a NodeJS package is installed in the system
sub __IsInstalledNodejs($) {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    return 0 unless (@_);
    my ($pkg) = @_;

    return 0;
}

#TODO
# Checks whether a Python package is installed in the system
sub __IsInstalledPython($) {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    return 0 unless (@_);
    my ($pkg) = @_;

    return 0;
}

sub __ToDay() {

    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst ) =
      localtime( gettimeofday() );

    $month++;
    $year += 1900;

    my $today = sprintf( '%04d-%02d-%02d', $year, $month, $mday );

    return $today;
}

sub __aUniq {
    my %seen;
    grep !$seen{$_}++, @_;
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
  <u><strong>Installer - Module to update FHEM, install 3rd-party FHEM modules and manage system prerequisites</strong></u><br>
  <br>
  <br>
  <a name="Installerdefine" id="Installerdefine"></a><strong>Define</strong><br>
  <ul>
    <code>define &lt;name&gt; Installer</code><br>
    <br>
    Example:<br>
    <ul>
      <code>define fhemInstaller Installer</code><br>
    </ul><br>
  </ul><br>
  <br>
  <a name="Installerget" id="Installerget"></a><strong>Get</strong>
  <ul>
    <li>checkPrereqs - list all missing prerequisites. If no parameter was given, the running live system will be inspected. If the parameter is a FHEM cfg file, inspection will be based on devices from this file. If the parameter is a list of module names, those will be used for inspection.
    </li>
    <li>search - search FHEM for device names, module names, package names, keywords, authors and Perl package names.
    </li>
    <li>showModuleInfo - list information about a specific FHEM module
    </li>
    <li>showPackageInfo - list information about a specific FHEM package
    </li>
    <li>zzGetModuleMETA.json - prints raw meta information of a FHEM module in JSON format
    </li>
    <li>zzGetPackageMETA.json - prints raw meta information of a FHEM package in JSON format
    </li>
  </ul><br>
  <br>
  <a name="Installerattribut" id="Installerattribut"></a><strong>Attributes</strong>
  <ul>
    <li>disable - disables the device
    </li>
    <li>disabledForIntervals - disable device for interval time (13:00-18:30 or 13:00-18:30 22:00-23:00)
    </li>
    <li>installerMode - sets the installation mode. May be update, developer or install with update being the default setting. Some get and/or set commands may be hidden or limited depending on this.
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
  "version": "v0.3.8",
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
  "keywords": [
    "Dependencies",
    "Prerequisites",
    "Setup"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "Data::Dumper": 0,
        "Encode": 0,
        "FHEM": 5.00918623,
        "FHEM::Meta": 0.001006,
        "FHEM::npmjs": 0,
        "File::stat": 0,
        "GPUtils": 0,
        "HttpUtils": 0,
        "IO::Socket::SSL": 0,
        "JSON": 0,
        "perl": 5.014,
        "version": 0
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
      "web": "https://github.com/fhem/Installer/issues"
    }
  }
}
=end :application/json;q=META.json

=cut
