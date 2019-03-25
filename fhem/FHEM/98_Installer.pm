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
    my $mode    = $cfgfile ? 'file' : 'live';
    $mode = 'list' if ( $cfgfile && defined( $modules{$cfgfile} ) );

    my @defined;
    if ( $mode eq 'file' ) {
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
    Debug Dumper \@defined;

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

    my $tableOpen   = '';
    my $rowOpen     = '';
    my $rowOpenEven = '';
    my $rowOpenOdd  = '';
    my $colOpen     = '';
    my $txtOpen     = '';
    my $txtClose    = '';
    my $colClose    = "\t\t\t";
    my $rowClose    = '';
    my $tableClose  = '';
    my $colorRed    = '';
    my $colorGreen  = '';
    my $colorClose  = '';

    if ($html) {
        $tableOpen   = '<table class="block wide">';
        $rowOpen     = '<tr class="column">';
        $rowOpenEven = '<tr class="column even">';
        $rowOpenOdd  = '<tr class="column odd">';
        $colOpen     = '<td>';
        $txtOpen     = '<b>';
        $txtClose    = '</b>';
        $colClose    = '</td>';
        $rowClose    = '</tr>';
        $tableClose  = '</table>';
        $colorRed    = '<span style="color:red">';
        $colorGreen  = '<span style="color:green">';
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
    my $perlAnalyzed = 0;
    my %prereqs;

    foreach my $modName ( keys %modules ) {
        next
          if ( $mode eq 'live'
            && !defined( $modules{$modName}{LOADED} )
            && $modName ne 'Installer' );
        next
          if ( $mode ne 'live'
            && @defined > 0
            && !grep ( /^$modName$/, @defined ) );

        FHEM::Meta::Load($modName);

        next
          unless ( defined( $modules{$modName}{META} ) );

        if ( !defined( $modules{$modName}{META}{x_prereqs_src} ) ) {
            $perlAnalyzed = 2;
            next;
        }

        next
          unless ( defined( $modules{$modName}{META}{prereqs} )
            && defined( $modules{$modName}{META}{prereqs}{runtime} ) );
        my $modPreqs = $modules{$modName}{META}{prereqs}{runtime};

        foreach my $mAttr (qw(requires recommends suggests)) {
            next
              unless ( defined( $modPreqs->{$mAttr} )
                && keys %{ $modPreqs->{$mAttr} } > 0 );

            foreach my $prereq ( keys %{ $modPreqs->{$mAttr} } ) {
                next
                  if ( FHEM::Meta::ModuleIsPerlPragma($prereq)
                    || FHEM::Meta::ModuleIsPerlCore($prereq)
                    || FHEM::Meta::ModuleIsInternal($prereq) );

                my $version = $modPreqs->{$mAttr}{$prereq};
                $version = '' if ( !defined($version) || $version eq '0' );

                my $check     = __IsInstalledPerl($prereq);
                my $installed = '';
                if ($check) {
                    if ( $check ne '1' ) {
                        my $nverReq =
                          $version ne ''
                          ? version->parse($version)->numify
                          : 0;
                        my $nverInst = $check;

                        #TODO suport for version range:
                        #https://metacpan.org/pod/CPAN::Meta::Spec#Version-Range
                        if ( $nverReq > 0 && $nverInst < $nverReq ) {
                            push @{ $prereqs{$prereq}{$mAttr}{by} },
                              $modName
                              unless (
                                grep ( /^$modName$/,
                                    @{ $prereqs{$prereq}{$mAttr}{by} } )
                              );
                            push @{ $prereqs{$prereq}{$mAttr}{version} },
                              $nverReq;

                            $perlAnalyzed = 1
                              if ( $modules{$modName}{META}{x_prereqs_src} ne
                                'META.json' && !$perlAnalyzed );
                        }
                    }
                }
                else {
                    push @{ $prereqs{$prereq}{$mAttr}{by} }, $modName
                      unless (
                        grep ( /^$modName$/,
                            @{ $prereqs{$prereq}{$mAttr}{by} } ) );

                    $perlAnalyzed = 1
                      if (
                        $modules{$modName}{META}{x_prereqs_src} ne 'META.json'
                        && !$perlAnalyzed );
                }
            }
        }
    }

    my %pending;
    my $found                = 0;
    my $foundRequired        = 0;
    my $foundRecommended     = 0;
    my $foundSuggested       = 0;
    my $foundRequiredPerl    = 0;
    my $foundRecommendedPerl = 0;
    my $foundSuggestedPerl   = 0;

    # Consolidating prereqs
    foreach ( keys %prereqs ) {
        $found++;
        if ( defined( $prereqs{$_}{requires} ) ) {
            $foundRequired++;
            $foundRequiredPerl++;
            $pending{requires}{Perl}{$_} =
              $prereqs{$_}{requires}{by};

            if ( defined( $prereqs{$_}{recommends} ) ) {
                foreach my $i ( @{ $prereqs{$_}{recommends}{by} } ) {
                    push @{ $pending{requires}{Perl}{$_} }, $i
                      unless (
                        grep ( /^$i$/, @{ $pending{requires}{Perl}{$_} } ) );
                }
            }
            if ( defined( $prereqs{$_}{suggestes} ) ) {
                foreach my $i ( @{ $prereqs{$_}{suggestes}{by} } ) {
                    push @{ $pending{suggestes}{Perl}{$_} }, $i
                      unless (
                        grep ( /^$i$/, @{ $pending{suggestes}{Perl}{$_} } ) );
                }
            }
        }
        elsif ( defined( $prereqs{$_}{recommends} ) ) {
            $foundRecommended++;
            $foundRecommendedPerl++;
            $pending{recommends}{Perl}{$_} =
              $prereqs{$_}{recommends}{by};

            if ( defined( $prereqs{$_}{suggestes} ) ) {
                foreach my $i ( @{ $prereqs{$_}{suggestes}{by} } ) {
                    push @{ $pending{suggestes}{Perl}{$_} }, $i
                      unless (
                        grep ( /^$i$/, @{ $pending{suggestes}{Perl}{$_} } ) );
                }
            }
        }
        else {
            $foundSuggested++;
            $foundSuggestedPerl++;
            $pending{suggests}{Perl}{$_} =
              $prereqs{$_}{suggests}{by};
        }
    }

    # Display prereqs
    if ($found) {

        foreach my $mAttr (qw(requires recommends suggests)) {
            next
              unless ( defined( $pending{$mAttr} )
                && keys %{ $pending{$mAttr} } > 0 );

            my $linecount  = 1;
            my $importance = $mAttr;
            $importance = 'Required'    if ( $mAttr eq 'requires' );
            $importance = 'Recommended' if ( $mAttr eq 'recommends' );
            $importance = 'Suggested'   if ( $mAttr eq 'suggests' );

            if ( $linecount == 1 ) {
                push @ret,
                    '<a name="prereqResult'
                  . $importance
                  . '"></a><h3>'
                  . $importance . '</h3>'
                  . $lb;
                push @ret, $tableOpen . $rowOpen;
                push @ret, $colOpen . $txtOpen . 'Item' . $txtClose . $colClose;
                push @ret, $colOpen . $txtOpen . 'Type' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Used by' . $txtClose . $colClose;
                push @ret, $rowClose;
            }

            foreach my $area (qw(Perl)) {
                next
                  unless ( defined( $pending{$mAttr}{$area} )
                    && keys %{ $pending{$mAttr}{$area} } > 0 );

                foreach my $item (
                    sort { "\L$a" cmp "\L$b" }
                    keys %{ $pending{$mAttr}{$area} }
                  )
                {
                    my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

                    my $linkitem = $item;
                    $linkitem =
                        '<a href="https://metacpan.org/pod/'
                      . $item
                      . '" target="_blank">'
                      . $item . '</a>'
                      if ($html);

                    my $linkmod = '';
                    foreach ( sort { "\L$a" cmp "\L$b" }
                        @{ $pending{$mAttr}{$area}{$item} } )
                    {
                        $linkmod .= ', ' unless ( $linkmod eq '' );
                        if ($html) {
                            $linkmod .=
                                '<a href="?cmd=get '
                              . $hash->{NAME}
                              . ' showModuleInfo '
                              . $_
                              . $FW_CSRF . '">'
                              . ( $_ eq 'Global' ? 'FHEM' : $_ ) . '</a>';
                        }
                        else {
                            $linkmod .= ( $_ eq 'Global' ? 'FHEM' : $_ );
                        }
                    }

                    $l .= $colOpen . $linkitem . $colClose;
                    $l .= $colOpen . $area . $colClose;
                    $l .= $colOpen . $linkmod . $colClose;
                    $l .= $rowClose;

                    push @ret, $l;
                    $linecount++;
                }
            }

            push @ret, $tableClose;
        }

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
    }
    else {
        unshift @ret, 'Hooray! All prerequisites are met. 🥳';
    }

    unshift @ret,
        '<a name="prereqResultTOP"></a><h2>'
      . ( $mode eq 'live' ? 'Live ' : '' )
      . 'System Prerequisites Check</h2>';

    if ($perlAnalyzed) {
        push @ret,
            $lb
          . $txtOpen . 'Hint:'
          . $txtClose
          . ' Some of the used FHEM modules do not provide Perl prerequisites from its metadata.'
          . $lb;

        if ( $perlAnalyzed == 1 ) {
            push @ret,
'This check is based on automatic source code analysis and can be incorrect.';
        }
        elsif ( $perlAnalyzed == 2 ) {
            push @ret,
'This check may be incomplete until you install Perl::PrereqScanner::NotQuiteLite.';
        }
    }

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

    my $header = '';
    my $footer = '';
    if ($html) {
        $header =
            '<html><a href="?detail='
          . $hash->{NAME}
          . '" style="position: absolute; top: 1em; right: 1em; text-align:right; font-size:.85em;">&larr; back to FHEM Installer</a>';
        $footer = '</html>';
    }

    my $tableOpen   = '';
    my $rowOpen     = '';
    my $rowOpenEven = '';
    my $rowOpenOdd  = '';
    my $colOpen     = '';
    my $txtOpen     = '';
    my $txtClose    = '';
    my $colClose    = "\t\t\t";
    my $rowClose    = '';
    my $tableClose  = '';
    my $colorRed    = '';
    my $colorGreen  = '';
    my $colorClose  = '';

    if ($html) {
        $tableOpen   = '<table class="block wide">';
        $rowOpen     = '<tr class="column">';
        $rowOpenEven = '<tr class="column even">';
        $rowOpenOdd  = '<tr class="column odd">';
        $colOpen     = '<td>';
        $txtOpen     = '<b>';
        $txtClose    = '</b>';
        $colClose    = '</td>';
        $rowClose    = '</tr>';
        $tableClose  = '</table>';
        $colorRed    = '<span style="color:red">';
        $colorGreen  = '<span style="color:green">';
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

    my $found = 0;

    # search for matching device
    my $foundDevices = 0;
    my $linecount    = 1;
    foreach my $device ( sort { "\L$a" cmp "\L$b" } keys %defs ) {
        next
          unless ( defined( $defs{$device}{TYPE} )
            && defined( $modules{ $defs{$device}{TYPE} } ) );

        if ( $device =~ m/^.*$search.*$/i ) {
            unless ($foundDevices) {
                push @ret,
                  '<a name="searchResultDevices"></a><h3>Devices</h3>' . $lb;
                push @ret, $tableOpen . $rowOpen;
                push @ret,
                  $colOpen . $txtOpen . 'Device Name' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Device Type' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Device State' . $txtClose . $colClose;
                push @ret, $rowClose;
            }
            $found++;
            $foundDevices++;

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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

            $l .= $colOpen . $linkDev . $colClose;
            $l .= $colOpen . $linkMod . $colClose;
            $l .= $colOpen
              . (
                defined( $defs{$device}{STATE} )
                ? $defs{$device}{STATE}
                : ''
              ) . $colClose;

            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tableClose if ($foundDevices);

    # search for matching module
    my $foundModules = 0;
    $linecount = 1;
    foreach my $module ( sort { "\L$a" cmp "\L$b" } keys %modules ) {
        if ( $module =~ m/^.*$search.*$/i ) {
            unless ($foundModules) {
                push @ret,
                  '<a name="searchResultModules"></a><h3>Modules</h3>' . $lb;
                push @ret, $tableOpen . $rowOpen;
                push @ret,
                  $colOpen . $txtOpen . 'Module Name' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Abstract' . $txtClose . $colClose;
                push @ret, $rowClose;
            }
            $found++;
            $foundModules++;

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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

            $l .= $colOpen . $link . $colClose;
            $l .=
              $colOpen . ( $abstract eq 'n/a' ? '' : $abstract ) . $colClose;

            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tableClose if ($foundModules);

    # search for matching module
    my $foundPackages = 0;
    $linecount = 1;
    foreach my $package ( sort { "\L$a" cmp "\L$b" } keys %packages ) {
        if ( $package =~ m/^.*$search.*$/i ) {
            unless ($foundPackages) {
                push @ret,
                  '<a name="searchResultPackages"></a><h3>Packages</h3>' . $lb;
                push @ret, $tableOpen . $rowOpen;
                push @ret,
                  $colOpen . $txtOpen . 'Package Name' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Abstract' . $txtClose . $colClose;
                push @ret, $rowClose;
            }
            $found++;
            $foundPackages++;

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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

            $l .= $colOpen . $link . $colClose;
            $l .=
              $colOpen . ( $abstract eq 'n/a' ? '' : $abstract ) . $colClose;

            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tableClose if ($foundPackages);

    # search for matching keyword
    my $foundKeywords = 0;
    $linecount = 1;
    foreach
      my $keyword ( sort { "\L$a" cmp "\L$b" } keys %FHEM::Meta::keywords )
    {
        if ( $keyword =~ m/^.*$search.*$/i ) {
            push @ret, '<a name="searchResultKeywords"></a><h3>Keywords</h3>'
              unless ($foundKeywords);
            $found++;
            $foundKeywords++;

            my $descr = FHEM::Meta::GetKeywordDesc( $keyword, $lang );
            push @ret,
                '<h4'
              . ( $descr ne '' ? ' title="' . $descr . '"' : '' ) . '># '
              . $keyword . '</h4>';

            my @mAttrs = qw(
              modules
              packages
            );

            push @ret, $tableOpen . $rowOpen;

            push @ret, $colOpen . $txtOpen . 'Name' . $txtClose . $colClose;

            push @ret, $colOpen . $txtOpen . 'Type' . $txtClose . $colClose;

            push @ret, $colOpen . $txtOpen . 'Abstract' . $txtClose . $colClose;

            push @ret, $rowClose;

            foreach my $mAttr (@mAttrs) {
                next
                  unless ( defined( $FHEM::Meta::keywords{$keyword}{$mAttr} )
                    && @{ $FHEM::Meta::keywords{$keyword}{$mAttr} } > 0 );

                foreach my $item ( sort { "\L$a" cmp "\L$b" }
                    @{ $FHEM::Meta::keywords{$keyword}{$mAttr} } )
                {
                    my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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

                    $l .= $colOpen . $link . $colClose;
                    $l .= $colOpen . $type . $colClose;
                    $l .=
                        $colOpen
                      . ( $abstract eq 'n/a' ? '' : $abstract )
                      . $colClose;

                    $l .= $rowClose;

                    push @ret, $l;
                    $linecount++;
                }
            }

            push @ret, $tableClose;
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
'<a name="searchResultMaintainers"></a><h3>Authors & Maintainers</h3>'
                  . $lb;
                push @ret, $tableOpen . $rowOpen;
                push @ret, $colOpen . $txtOpen . 'Name' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Modules' . $txtClose . $colClose;
                push @ret,
                  $colOpen . $txtOpen . 'Packages' . $txtClose . $colClose;
                push @ret, $rowClose;
            }
            $found++;
            $foundMaintainers++;

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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

            $l .= $colOpen . $maintainer . $colClose;
            $l .= $colOpen . $mods . $colClose;
            $l .= $colOpen . $pkgs . $colClose;

            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tableClose if ($foundMaintainers);

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
                  '<a name="searchResultPerl"></a><h3>Perl packages</h3>' . $lb;
                push @ret, $tableOpen . $rowOpen;
                push @ret, $colOpen . $txtOpen . 'Name' . $txtClose . $colClose;
                push @ret,
                    $colOpen
                  . $txtOpen
                  . 'Referenced from'
                  . $txtClose
                  . $colClose;
                push @ret, $rowClose;
            }
            $found++;
            $foundPerl++;

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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

            $l .= $colOpen . $dependent . $colClose;
            $l .= $colOpen . $references . $colClose;

            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }
    push @ret, $tableClose if ($foundPerl);

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
        unshift @ret, 'Nothing found';
    }

    $search =~ s/\\s\*/ /g;
    unshift @ret,
      '<a name="searchResultTOP"></a><h2>Search result: ' . $search . '</h2>';

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
            '<html><a href="?detail='
          . $hash->{NAME}
          . '" style="top: 1em; right: 1em; text-align:right; font-size:.85em;">&larr; back to FHEM Installer</a>';
        $footer = '</html>';
    }

    my $tableOpen   = '';
    my $rowOpen     = '';
    my $rowOpenEven = '';
    my $rowOpenOdd  = '';
    my $colOpen     = '';
    my $txtOpen     = '';
    my $txtClose    = '';
    my $colClose    = "\t\t\t";
    my $rowClose    = '';
    my $tableClose  = '';
    my $colorRed    = '';
    my $colorGreen  = '';
    my $colorClose  = '';

    if ($html) {
        $tableOpen   = '<table class="block wide">';
        $rowOpen     = '<tr class="column">';
        $rowOpenEven = '<tr class="column even">';
        $rowOpenOdd  = '<tr class="column odd">';
        $colOpen     = '<td>';
        $txtOpen     = '<b>';
        $txtClose    = '</b>';
        $colClose    = '</td>';
        $rowClose    = '</tr>';
        $tableClose  = '</table>';
        $colorRed    = '<span style="color:red">';
        $colorGreen  = '<span style="color:green">';
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

    push @ret, $tableOpen;

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

        my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;
        my $mAttrName = $mAttr;
        $mAttrName =~ s/_/$space/g;
        $mAttrName =~ s/([\w'&]+)/\u\L$1/g;

        my $webname =
          AttrVal( $hash->{CL}{SNAME}, 'webname', 'fhem' );

        $l .= $colOpen . $txtOpen . $mAttrName . $txtClose . $colClose;

        # these attributes do not exist under that name in META.json
        if ( !defined( $modMeta->{$mAttr} ) ) {
            $l .= $colOpen;

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

            $l .= $colClose;
        }

        # these text attributes can be shown directly
        elsif ( !ref( $modMeta->{$mAttr} ) ) {
            $l .= $colOpen;

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

            $l .= $mAttrVal . $colClose;
        }

        # this attribute is an array and needs further processing
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

            $l .= $colClose;
        }

        # woops, we don't know how to handle this attribute
        else {
            $l .= $colOpen . '?' . $colClose;
        }

        $l .= $rowClose;

        push @ret, $l;
        $linecount++;
    }

    push @ret, $tableClose;

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
                push @ret, '<h4>FHEM internal dependencies</h4>';

                push @ret,
                    $txtOpen . 'Hint:'
                  . $txtClose
                  . $lb
                  . 'Dependents can only be shown here if they were loaded into the metadata cache before.'
                  . $lb
                  . $lb;

                push @ret, $tableOpen . $rowOpen;

                push @ret,
                  $colOpen . $txtOpen . 'Importance' . $txtClose . $colClose;

                push @ret,
                    $colOpen
                  . $txtOpen
                  . 'Dependent Modules'
                  . $txtClose
                  . $colClose;

                push @ret, $rowClose;
            }

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

            my $importance = $mAttr;
            $importance = 'required'    if ( $mAttr eq 'requires' );
            $importance = 'recommended' if ( $mAttr eq 'recommends' );
            $importance = 'suggested'   if ( $mAttr eq 'suggests' );

            $l .= $colOpen . $importance . $colClose;
            $l .= $colOpen . $dependents . $colClose;

            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }

    push @ret, $tableClose . $lb if ( $linecount > 1 );

    if ( $modType eq 'module' && $modName ne 'Global' ) {
        push @ret, '<h3>Devices</h3>';

        if ( defined( $modules{$modName}{LOADED} ) ) {
            my @instances = devspec2array( 'TYPE=' . $modName );
            if ( @instances > 0 ) {
                push @ret, $lb, $tableOpen . $rowOpen;

                my $devices = '';
                foreach my $instance ( sort { "\L$a" cmp "\L$b" } @instances ) {
                    next if ( defined( $defs{$instance}{TEMPORARY} ) );
                    $devices .= ', ' unless ( $devices eq '' );
                    if ($html) {
                        $devices .=
                            '<a href="?detail='
                          . $instance . '">'
                          . $instance . '</a>';
                    }
                    else {
                        $devices .= $instance;
                    }
                }

                push @ret, $colOpen . $devices . $colClose;

                push @ret, $rowClose . $tableClose;
            }
            else {
                push @ret,
                    $lb
                  . 'This module was once loaded into memory, '
                  . 'but currently there is no device defined anymore.';
            }
        }
        else {
            push @ret, $lb . 'This module is currently not in use.';
        }
    }

    push @ret, '<h3>System Prerequisites</h3>';

    push @ret, '<h4>Perl Packages</h4>';
    if (   defined( $modMeta->{prereqs} )
        && defined( $modMeta->{prereqs}{runtime} ) )
    {

        push @ret,
            $txtOpen . 'Hint:'
          . $txtClose
          . $lb
          . 'This module does not provide Perl prerequisites from its metadata.'
          . $lb
          . 'The following result is based on automatic source code analysis '
          . 'and can be incorrect.'
          . $lb
          . $lb
          if ( defined( $modMeta->{x_prereqs_src} )
            && $modMeta->{x_prereqs_src} ne 'META.json' );

        @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tableOpen . $rowOpen;

        push @ret, $colOpen . $txtOpen . 'Name' . $txtClose . $colClose;

        push @ret, $colOpen . $txtOpen . 'Importance' . $txtClose . $colClose;

        push @ret, $colOpen . $txtOpen . 'Status' . $txtClose . $colClose;

        push @ret, $rowClose;

        $linecount = 1;
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

                my $check     = __IsInstalledPerl($prereq);
                my $installed = '';
                if ($check) {
                    if ( $check ne '1' ) {
                        my $nverReq =
                          $version ne ''
                          ? version->parse($version)->numify
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
                    && $isFhem );

                $l .=
                    $colOpen
                  . $prereq
                  . ( $version ne '' ? " ($version)" : '' )
                  . $colClose;
                $l .= $colOpen . $importance . $colClose;
                $l .= $colOpen . $installed . $colClose;

                $l .= $rowClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tableClose;
    }
    elsif ( defined( $modMeta->{x_prereqs_src} ) ) {
        push @ret, $lb . 'No known prerequisites.' . $lb . $lb;
    }
    else {
        push @ret,
            $lb
          . 'Module metadata do not contain any prerequisites.' . "\n"
          . 'For automatic source code analysis, please install Perl::PrereqScanner::NotQuiteLite .'
          . $lb
          . $lb;
    }

    if (   defined( $modMeta->{x_prereqs_nodejs} )
        && defined( $modMeta->{x_prereqs_nodejs}{runtime} ) )
    {
        push @ret, '<h4>Node.js Packages</h4>';

        my @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tableOpen . $rowOpen;

        push @ret, $colOpen . $txtOpen . 'Name' . $txtClose . $colClose;

        push @ret, $colOpen . $txtOpen . 'Importance' . $txtClose . $colClose;

        push @ret, $colOpen . $txtOpen . 'Status' . $txtClose . $colClose;

        push @ret, $rowClose;

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
                my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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
                    $colOpen
                  . $prereq
                  . ( $version ne '' ? " ($version)" : '' )
                  . $colClose;
                $l .= $colOpen . $importance . $colClose;
                $l .= $colOpen . $installed . $colClose;

                $l .= $rowClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tableClose;

    }

    if (   defined( $modMeta->{x_prereqs_python} )
        && defined( $modMeta->{x_prereqs_python}{runtime} ) )
    {
        push @ret, '<h4>Python Packages</h4>';

        my @mAttrs = qw(
          requires
          recommends
          suggests
        );

        push @ret, $tableOpen . $rowOpen;

        push @ret, $colOpen . $txtOpen . 'Name' . $txtClose . $colClose;

        push @ret, $colOpen . $txtOpen . 'Importance' . $txtClose . $colClose;

        push @ret, $colOpen . $txtOpen . 'Status' . $txtClose . $colClose;

        push @ret, $rowClose;

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
                my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;

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
                    $colOpen
                  . $prereq
                  . ( $version ne '' ? " ($version)" : '' )
                  . $colClose;
                $l .= $colOpen . $importance . $colClose;
                $l .= $colOpen . $installed . $colClose;

                $l .= $rowClose;

                push @ret, $l;
                $linecount++;
            }
        }

        push @ret, $tableClose;

    }

    push @ret,
      $lb . $lb . 'Based on data generated by ' . $modMeta->{generated_by};

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

# Checks whether a perl package is installed in the system
sub __IsInstalledPerl($) {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    return 0 unless (@_);
    my ($pkg) = @_;
    return version->parse($])->numify if ( $pkg eq 'perl' );
    return $modules{'Global'}{META}{version}
      if ( $pkg eq 'FHEM' );
    return FHEM::Meta->VERSION()
      if ( $pkg eq 'FHEM::Meta' || $pkg eq 'Meta' );

    my $fname = $pkg;
    $fname =~ s/^.*://g;    # strip away any parent module names

    # This is an internal Perl package
    if ( defined( $packages{$fname} ) ) {
        return $packages{$fname}{META}{version}
          if ( defined( $packages{$fname}{META} ) );
        return 1;
    }

    # This is an internal Perl package
    if ( defined( $modules{$fname} ) ) {
        return $modules{$fname}{META}{version}
          if ( defined( $modules{$fname}{META} ) );
        return 1;
    }

    eval "require $pkg;";

    return 0
      if ($@);

    my $v = eval "$pkg->VERSION()";

    if ($v) {
        return $v;
    }
    else {
        return 1;
    }
}

# Checks whether a NodeJS package is installed in the system
sub __IsInstalledNodejs($) {
    return 0 unless ( __PACKAGE__ eq caller(0) );
    return 0 unless (@_);
    my ($pkg) = @_;

    return 0;
}

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
  <a name="Installerattribut" id="Installerattribut"></a><b>Attributes</b>
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
  "version": "v0.3.0",
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
        "FHEM": 5.00918623,
        "perl": 5.014,
        "GPUtils": 0,
        "JSON": 0,
        "FHEM::Meta": 0.001006,
        "Data::Dumper": 0,
        "IO::Socket::SSL": 0,
        "HttpUtils": 0,
        "File::stat": 0,
        "Encode": 0,
        "version": 0,
        "FHEM::npmjs": 0
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
