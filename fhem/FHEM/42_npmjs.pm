# $Id$

package main;
use strict;
use warnings;
use FHEM::Meta;

sub npmjs_Initialize($) {
    my ($modHash) = @_;

    $modHash->{SetFn}    = "FHEM::npmjs::Set";
    $modHash->{GetFn}    = "FHEM::npmjs::Get";
    $modHash->{DefFn}    = "FHEM::npmjs::Define";
    $modHash->{NotifyFn} = "FHEM::npmjs::Notify";
    $modHash->{UndefFn}  = "FHEM::npmjs::Undef";
    $modHash->{AttrFn}   = "FHEM::npmjs::Attr";
    $modHash->{AttrList} =
        "disable:1,0 "
      . "disabledForIntervals "
      . "updateListReading:1,0 "
      . "npmglobal:1,0 "
      . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $modHash );
}

# define package
package FHEM::npmjs;
use strict;
use warnings;
use POSIX;
use FHEM::Meta;

use GPUtils qw(GP_Import);
use Data::Dumper;

# Run before module compilation
BEGIN {

    # Import from main::
    GP_Import(
        qw(
          attr
          AttrVal
          CommandAttr
          Debug
          defs
          deviceEvents
          DoTrigger
          FW_webArgs
          gettimeofday
          init_done
          InternalTimer
          IsDisabled
          Log3
          modules
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

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
};
if ($@) {
    $@ = undef;

    # try to use JSON wrapper
    #   for chance of better performance
    eval {

        # JSON preference order
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

        require JSON;
        import JSON qw( decode_json encode_json );
        1;
    };

    if ($@) {
        $@ = undef;

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        };

        if ($@) {
            $@ = undef;

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            };

            if ($@) {
                $@ = undef;

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                require JSON::PP;
                import JSON::PP qw(decode_json encode_json);
                1;
            }
        }
    }
}

my %fhem_npm_modules = (
    'alexa-fhem'      => { fhem_module => 'alexa', },
    'gassistant-fhem' => { fhem_module => 'gassistant', },
    'homebridge-fhem' => { fhem_module => 'siri', },
    'tradfri-fhem'    => { fhem_module => 'tradfri', },
);

sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    # Initialize the module and the device
    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    my $name = $a[0];
    my $host = $a[2] ? $a[2] : 'localhost';

    Undef( $hash, undef ) if ( $hash->{OLDDEF} );    # modify

    $hash->{HOST}      = $host;
    $hash->{NOTIFYDEV} = "global,$name";

    return "Existing instance for host $hash->{HOST}: "
      . $modules{ $hash->{TYPE} }{defptr}{ $hash->{HOST} }{NAME}
      if ( defined( $modules{ $hash->{TYPE} }{defptr}{ $hash->{HOST} } ) );

    $modules{ $hash->{TYPE} }{defptr}{ $hash->{HOST} } = $hash;

    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {

        # presets for FHEMWEB
        $attr{$name}{alias} = 'Node.js Package Update Status';
        $attr{$name}{devStateIcon} =
'npm.updates.available:security@red:outdated npm.is.up.to.date:security@green:outdated .*npm.outdated.*in.progress:system_fhem_reboot@orange .*in.progress:system_fhem_update@orange warning.*:message_attention@orange error.*:message_attention@red';
        $attr{$name}{group} = 'Update';
        $attr{$name}{icon}  = 'npm-old';
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

    delete( $modules{npmjs}{defptr}{ $hash->{HOST} } );
    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);

            readingsSingleUpdate( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "npmjs ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "npmjs ($name) - enabled";
        }
    }

    elsif ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            return
"check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
              unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "npmjs ($name) - disabledForIntervals";
            readingsSingleUpdate( $hash, "state", "disabled", 1 );
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "npmjs ($name) - enabled";
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

    Log3 $name, 5, "npmjs ($name) - Notify: " . Dumper $events;

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

        # restore from packageList
        my $decode_json =
          eval { decode_json( ReadingsVal( $name, '.packageList', '' ) ) };
        unless ($@) {
            $hash->{".fhem"}{npm}{nodejsversions} = $decode_json->{versions}
              if ( defined( $decode_json->{versions} ) );
            $hash->{".fhem"}{npm}{listedpackages} = $decode_json->{listed}
              if ( defined( $decode_json->{listed} ) );
            $hash->{".fhem"}{npm}{outdatedpackages} = $decode_json->{outdated}
              if ( defined( $decode_json->{outdated} ) );
        }
        $decode_json = undef;

        # restore from installedList
        $decode_json =
          eval { decode_json( ReadingsVal( $name, '.installedList', '' ) ) };
        unless ($@) {
            $hash->{".fhem"}{npm}{installedpackages} = $decode_json;
        }
        $decode_json = undef;

        # restore from uninstalledList
        $decode_json =
          eval { decode_json( ReadingsVal( $name, '.uninstalledList', '' ) ) };
        unless ($@) {
            $hash->{".fhem"}{npm}{uninstalledpackages} = $decode_json;
        }
        $decode_json = undef;

        # restore from updatedList
        $decode_json =
          eval { decode_json( ReadingsVal( $name, '.updatedList', '' ) ) };
        unless ($@) {
            $hash->{".fhem"}{npm}{updatedpackages} = $decode_json;
        }
        $decode_json = undef;

        # Trigger update
        if ( ReadingsVal( $name, 'nodejsVersion', 'none' ) ne 'none' ) {
            ProcessUpdateTimer($hash);
        }
        else {
            $hash->{".fhem"}{npm}{cmd} = 'getNodeVersion';
            AsynchronousExecuteNpmCommand($hash);
        }
    }

    if (
        $devname eq $name
        and (  grep ( /^installed:.successful$/, @{$events} )
            or grep ( /^uninstalled:.successful$/, @{$events} )
            or grep ( /^updated:.successful$/,     @{$events} ) )
      )
    {
        $hash->{".fhem"}{npm}{cmd} = 'outdated';
        AsynchronousExecuteNpmCommand($hash);
    }

    return;
}

sub Set($$@) {

    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    my $npmglobal = ( AttrVal( $name, 'npmglobal', 1 ) eq '1' ? 1 : 0 );

    # outdated
    if ( $cmd eq 'outdated' ) {
        $hash->{".fhem"}{npm}{cmd} = $cmd;
    }

    # statusRequest
    elsif ( lc($cmd) eq 'statusrequest' ) {
        $hash->{".fhem"}{npm}{cmd} = 'getNodeVersion';
    }

    # update | upgrade
    elsif ( $cmd eq 'update' || $cmd eq 'upgrade' ) {
        return "Please run outdated check first"
          unless ( defined( $hash->{".fhem"}{npm}{outdatedpackages} ) );
        my $update;

        # generate explicit list for packages to update
        if (   @args == 0
            || lc( $args[0] ) eq 'all'
            || lc( $args[0] ) eq 'fhem-all' )
        {
            my $fhemall = @args > 0 && lc( $args[0] ) eq 'fhem-all' ? 1 : 0;
            undef @args;
            foreach ( keys %{ $hash->{".fhem"}{npm}{outdatedpackages} } ) {
                next
                  if ( $_ eq 'undefined'
                    || ( $fhemall && !defined( $fhem_npm_modules{$_} ) ) );
                push @args, $_;
            }
        }

        # use 'install' as default update method
        my $installcmd = 'install';

        foreach my $pkgfull (@args) {
            next
              unless ( $pkgfull =~
                /^(?:@([\w-]+)\/)?([\w-]+)(?:@([\d\.=<>]+|latest))?$/
                && defined( $hash->{".fhem"}{npm}{outdatedpackages}{$2} ) );

            my $pkg = $2;

            # if there is a non-FHEM package requested for update,
            #   enforce to use update method instead of install.
            #   See https://forum.fhem.de/index.php/topic,48558. \
            #     msg910786.html#msg910786
            #   Also see https://semver.org/
            $installcmd = 'update'
              unless ( defined( $fhem_npm_modules{$pkg} )
                || $cmd eq 'upgrade' );

            my $v =
              $3 ? $3
              : (
                  $installcmd eq 'install'
                ? $hash->{".fhem"}{npm}{outdatedpackages}{$pkg}{latest}
                : $hash->{".fhem"}{npm}{outdatedpackages}{$pkg}{wanted}
              );

            $update .= " " if ($update);
            $update .= $pkg . '@' . $v;
        }

        return "Everything is up-to-date already"
          unless ($update);

        $hash->{".fhem"}{npm}{cmd} = $installcmd . " " . $update;
    }

    # install
    elsif ( $cmd eq 'install' ) {
        return "usage: $cmd <package>" if ( @args < 1 );
        if ( defined( $args[0] )
            and ( lc( $args[0] ) eq "all" or lc( $args[0] ) eq "fhem-all" ) )
        {
            my $install;
            foreach ( keys %fhem_npm_modules ) {
                next
                  if (
                    defined(
                        $hash->{".fhem"}{npm}{listedpackages}{dependencies}{$_}
                    )
                  );
                $install .= " " if ($install);
                $install .= $_;
            }
            return "No FHEM specific NPM modules left to install"
              unless ($install);
            $hash->{".fhem"}{npm}{cmd} = $cmd . " " . $install;
        }
        else {
            $hash->{".fhem"}{npm}{cmd} = $cmd . " " . join( " ", @args );
        }
    }

    # uninstall
    elsif ( $cmd eq 'uninstall' ) {
        return "usage: $cmd <package>" if ( @args < 1 );
        if ( defined( $args[0] ) and lc( $args[0] ) eq "fhem-all" ) {
            my $uninstall;
            foreach ( keys %fhem_npm_modules ) {
                next
                  unless (
                    defined(
                        $hash->{".fhem"}{npm}{listedpackages}{dependencies}{$_}
                    )
                  );
                $uninstall .= " " if ($uninstall);
                $uninstall .= $_;
            }
            return "No FHEM specific NPM modules left to uninstall"
              unless ($uninstall);
            $hash->{".fhem"}{npm}{cmd} = $cmd . " " . $uninstall;
        }
        elsif ( defined( $args[0] ) and lc( $args[0] ) eq "all" ) {
            return "Please run outdated check first"
              unless ( defined( $hash->{".fhem"}{npm}{listedpackages} ) );

            my $uninstall;
            foreach (
                keys %{ $hash->{".fhem"}{npm}{listedpackages}{dependencies} } )
            {
                next if ( $_ eq "npm" );
                $uninstall .= " " if ($uninstall);
                $uninstall .= $_;
            }
            return "There is nothing to uninstall"
              unless ($uninstall);
            $hash->{".fhem"}{npm}{cmd} = $cmd . " " . $uninstall;
        }
        else {
            return "NPM cannot be uninstalled from here"
              if (
                grep ( m/^(?:@([\w-]+)\/)?(npm)(?:@([\d\.=<>]+|latest))?$/i,
                    @args ) );
            $hash->{".fhem"}{npm}{cmd} = $cmd . " " . join( " ", @args );
        }
    }

    # return Usage:
    else {
        my $list = '';

        if ( !defined( $hash->{".fhem"}{npm}{nodejsversions} ) ) {
            $list =
"install:nodejs-v12,nodejs-v10,nodejs-v8,nodejs-v6 statusRequest:noArg";
        }
        else {
            $list = "outdated:noArg";

            my $install;
            foreach ( keys %fhem_npm_modules ) {
                next
                  if (
                    defined( $hash->{".fhem"}{npm}{listedpackages} )
                    and defined(
                        $hash->{".fhem"}{npm}{listedpackages}{dependencies}
                    )
                    and defined(
                        $hash->{".fhem"}{npm}{listedpackages}{dependencies}{$_}
                    )
                  );
                $install .= "," if ($install);
                $install = "install:fhem-all," unless ($install);
                $install .= $_;
            }
            $install = "install" unless ($install);
            $list .= " $install";

            if (    defined( $hash->{".fhem"}{npm}{listedpackages} )
                and
                defined( $hash->{".fhem"}{npm}{listedpackages}{dependencies} )
                and scalar
                keys %{ $hash->{".fhem"}{npm}{listedpackages}{dependencies} } >
                0 )
            {
                my $uninstall;
                foreach (
                    sort
                    keys %{ $hash->{".fhem"}{npm}{listedpackages}{dependencies}
                    }
                  )
                {
                    next if ( $_ eq "npm" or $_ eq "undefined" );
                    $uninstall .= "," if ($uninstall);
                    $uninstall = "uninstall:all,fhem-all,"
                      unless ($uninstall);
                    $uninstall .= $_;
                }
                $list .= " $uninstall" if ($uninstall);
            }

            if ( defined( $hash->{".fhem"}{npm}{outdatedpackages} )
                and scalar
                keys %{ $hash->{".fhem"}{npm}{outdatedpackages} } > 0 )
            {
                my $update;
                my $upgrade;

                foreach (
                    sort
                    keys %{ $hash->{".fhem"}{npm}{outdatedpackages} }
                  )
                {
                    next
                      unless (
                        defined(
                            $hash->{".fhem"}{npm}{outdatedpackages}{$_}{current}
                        )
                        && defined(
                            $hash->{".fhem"}{npm}{outdatedpackages}{$_}{wanted}
                        )
                        && defined(
                            $hash->{".fhem"}{npm}{outdatedpackages}{$_}{latest}
                        )
                      );

                    if ( defined( $fhem_npm_modules{$_} )
                        || $hash->{".fhem"}{npm}{outdatedpackages}{$_}{wanted}
                        ne
                        $hash->{".fhem"}{npm}{outdatedpackages}{$_}{current} )
                    {
                        $update  .= "," if ($update);
                        $update  .= $_;
                        $upgrade .= "," if ($upgrade);
                        $upgrade .= $_;
                    }
                    else {
                        $upgrade .= "," if ($upgrade);
                        $upgrade .= $_;
                    }
                }
                if ($update) {
                    $update = "update:all,fhem-all,$update";
                    $list .= " $update";
                }
                if ($upgrade) {
                    $upgrade = "upgrade:all,fhem-all,$upgrade";
                    $list .= " $upgrade";
                }
            }
        }

        return "Unknown argument $cmd, choose one of $list";
    }

    AsynchronousExecuteNpmCommand($hash);

    return undef;
}

sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    if ( lc($cmd) eq 'showoutdatedlist' ) {
        return "usage: $cmd" if ( @args != 0 );

        my $ret = CreateOutdatedList( $hash, $cmd );
        return $ret;

    }
    elsif ( lc($cmd) eq 'showinstalledlist' ) {
        return "usage: $cmd" if ( @args != 0 );

        my $ret = CreateInstalledList( $hash, $cmd );
        return $ret;

    }

    # elsif ( $cmd eq 'showInstallResultList' ) {
    #     return "usage: $cmd" if ( @args != 0 );
    #
    #     my $ret = CreateInstallResultList( $hash, $cmd );
    #     return $ret;
    #
    # }
    # elsif ( $cmd eq 'showUninstallResultList' ) {
    #     return "usage: $cmd" if ( @args != 0 );
    #
    #     my $ret = CreateUninstallResultList( $hash, $cmd );
    #     return $ret;
    #
    # }
    # elsif ( $cmd eq 'showUpdateResultList' ) {
    #     return "usage: $cmd" if ( @args != 0 );
    #
    #     my $ret = CreateUpdateResultList( $hash, $cmd );
    #     return $ret;
    #
    # }
    # elsif ( $cmd eq 'showWarningList' ) {
    #     return "usage: $cmd" if ( @args != 0 );
    #
    #     my $ret = CreateWarningList($hash);
    #     return $ret;
    #
    # }
    elsif ( lc($cmd) eq 'showerrorlist' ) {
        return "usage: $cmd" if ( @args != 0 );

        my $ret = CreateErrorList($hash);
        return $ret;
    }
    else {
        my $list = '';
        $list .= " showOutdatedList:noArg"
          if ( defined( $hash->{".fhem"}{npm}{outdatedpackages} )
            and scalar keys %{ $hash->{".fhem"}{npm}{outdatedpackages} } > 0 );
        $list .= " showInstalledList:noArg"
          if (  defined( $hash->{".fhem"}{npm}{listedpackages} )
            and defined( $hash->{".fhem"}{npm}{listedpackages}{dependencies} )
            and scalar
            keys %{ $hash->{".fhem"}{npm}{listedpackages}{dependencies} } > 0 );

      # $list .= " showInstallResultList:noArg"
      #   if ( defined( $hash->{".fhem"}{npm}{installedpackages} )
      #     and scalar keys %{ $hash->{".fhem"}{npm}{installedpackages} } > 0 );
      # $list .= " showUninstallResultList:noArg"
      #   if ( defined( $hash->{".fhem"}{npm}{uninstalledpackages} )
      #     and scalar
      #     keys %{ $hash->{".fhem"}{npm}{uninstalledpackages} } > 0 );
      # $list .= " showUpdateResultList:noArg"
      #   if ( defined( $hash->{".fhem"}{npm}{updatedpackages} )
      #     and scalar keys %{ $hash->{".fhem"}{npm}{updatedpackages} } > 0 );
      # $list .= " showWarningList:noArg"
      #   if ( defined( $hash->{".fhem"}{npm}{'warnings'} )
      #     and scalar keys %{ $hash->{".fhem"}{npm}{'warnings'} } > 0 );

        $list .= " showErrorList:noArg"
          if ( defined( $hash->{".fhem"}{npm}{errors} )
            and scalar keys %{ $hash->{".fhem"}{npm}{errors} } > 0 );

        return "Unknown argument $cmd, choose one of $list";
    }
}

sub Event ($$) {
    my $hash  = shift;
    my $event = shift;
    my $name  = $hash->{NAME};

    return
      unless ( defined( $hash->{".fhem"}{npm}{cmd} )
        && $hash->{".fhem"}{npm}{cmd} =~
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
        "FHEM::npmjs::ProcessUpdateTimer",
        $hash, 0
    );
    Log3 $name, 4, "npmjs ($name) - stateRequestTimer: Call Request Timer";

    unless ( IsDisabled($name) ) {
        if ( exists( $hash->{".fhem"}{subprocess} ) ) {
            Log3 $name, 2,
              "npmjs ($name) - update in progress, process aborted.";
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
            $hash->{".fhem"}{npm}{cmd} = 'outdated';
            AsynchronousExecuteNpmCommand($hash);
        }
    }
}

sub CleanSubprocess($) {

    my $hash = shift;

    my $name = $hash->{NAME};

    delete( $hash->{".fhem"}{subprocess} );
    Log3 $name, 4, "npmjs ($name) - clean Subprocess";
}

use constant POLLINTERVAL => 1;

sub AsynchronousExecuteNpmCommand($) {

    require "SubProcess.pm";
    my ($hash) = shift;

    my $name = $hash->{NAME};

    my $subprocess = SubProcess->new( { onRun => \&OnRun } );
    $subprocess->{npm} = $hash->{".fhem"}{npm};
    $subprocess->{npm}{host} = $hash->{HOST};
    $subprocess->{npm}{debug} =
      ( AttrVal( $name, 'verbose', 0 ) > 3 ? 1 : 0 );
    $subprocess->{npm}{npmglobal} =
      ( AttrVal( $name, 'npmglobal', 1 ) eq '1' ? 1 : 0 );
    my $pid = $subprocess->run();

    readingsSingleUpdate( $hash, 'state',
        'command \'npm ' . $hash->{".fhem"}{npm}{cmd} . '\' in progress', 1 );

    if ( !defined($pid) ) {
        Log3 $name, 1, "npmjs ($name) - Cannot execute command asynchronously";

        CleanSubprocess($hash);
        readingsSingleUpdate( $hash, 'state',
            'Cannot execute command asynchronously', 1 );
        return undef;
    }

    Event( $hash, "BEGIN" );
    Log3 $name, 4, "npmjs ($name) - execute command asynchronously (PID= $pid)";

    $hash->{".fhem"}{subprocess} = $subprocess;

    InternalTimer( gettimeofday() + POLLINTERVAL,
        "FHEM::npmjs::PollChild", $hash, 0 );
    Log3 $hash, 4, "npmjs ($name) - control passed back to main loop.";
}

sub PollChild($) {

    my $hash = shift;

    my $name       = $hash->{NAME};
    my $subprocess = $hash->{".fhem"}{subprocess};
    my $json       = $subprocess->readFromChild();

    if ( !defined($json) ) {
        Log3 $name, 5,
          "npmjs ($name) - still waiting (" . $subprocess->{lasterror} . ").";
        InternalTimer( gettimeofday() + POLLINTERVAL,
            "FHEM::npmjs::PollChild", $hash, 0 );
        return;
    }
    else {
        Log3 $name, 4, "npmjs ($name) - got result from asynchronous parsing.";
        $subprocess->wait();
        Log3 $name, 4, "npmjs ($name) - asynchronous finished.";

        CleanSubprocess($hash);
        PreProcessing( $hash, $json );
    }
}

######################################
# Begin Childprocess
######################################

sub OnRun() {
    my $subprocess = shift;
    my $response   = ExecuteNpmCommand( $subprocess->{npm} );

    my $json = eval { encode_json($response) };
    if ($@) {
        Log3 'npmjs OnRun', 3, "npmjs - JSON error: $@";
        $json = "{\"jsonerror\":\"$@\"}";
    }

    $subprocess->writeToParent($json);
}

sub ExecuteNpmCommand($) {

    my $cmd = shift;

    my $npm = {};
    $npm->{debug} = $cmd->{debug};

    my $cmdPrefix = '';
    my $cmdSuffix = '';
    my $locale    = 'LC_ALL=C';

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
            'KEY=$('
          . $locale
          . ' ssh-keyscan -t ed25519 '
          . $2
          . ' 2>/dev/null); '
          . 'grep -q -E "^${KEY% *}" ${HOME}/.ssh/known_hosts || echo "${KEY}" >> ${HOME}/.ssh/known_hosts; ';
        $cmdPrefix .=
            'KEY=$('
          . $locale
          . ' ssh-keyscan -t rsa '
          . $2
          . ' 2>/dev/null); '
          . 'grep -q -E "^${KEY% *}" ${HOME}/.ssh/known_hosts || echo "${KEY}" >> ${HOME}/.ssh/known_hosts; ';

        # wrap SSH command
        $cmdPrefix .=
            $locale
          . ' ssh -oBatchMode=yes '
          . $port
          . ( $1 ? "$1@" : '' )
          . $2 . ' \'';
        $cmdSuffix = '\' 2>&1';
    }

    my $global = '-g ';
    my $sudo   = 'sudo -n ';

    if ( $cmd->{npmglobal} eq '0' ) {
        $global = '';
        $sudo   = '';
    }

    $npm->{nodejsversions} =
        $cmdPrefix
      . 'echo n | '
      . $locale
      . ' node -e "console.log(JSON.stringify(process.versions));" 2>&1'
      . $cmdSuffix;
    $npm->{npminstall} =
        $cmdPrefix
      . 'echo n | sh -c "'
      . $sudo
      . $locale
      . ' NODE_ENV=${NODE_ENV:-production} npm install '
      . $global
      . '--json --silent --unsafe-perm %PACKAGES%" 2>&1'
      . $cmdSuffix;
    $npm->{npmuninstall} =
        $cmdPrefix
      . 'echo n | sh -c "'
      . $sudo
      . $locale
      . ' NODE_ENV=${NODE_ENV:-production} npm uninstall '
      . $global
      . '--json --silent %PACKAGES%" 2>&1'
      . $cmdSuffix;
    $npm->{npmupdate} =
        $cmdPrefix
      . 'echo n | sh -c "'
      . $sudo
      . $locale
      . ' NODE_ENV=${NODE_ENV:-production} npm update '
      . $global
      . '--json --silent --unsafe-perm %PACKAGES%" 2>&1'
      . $cmdSuffix;
    $npm->{npmoutdated} =
        $cmdPrefix
      . 'echo n | '
      . 'echo "{' . "\n"
      . '\"versions\": "; '
      . $locale
      . ' node -e "console.log(JSON.stringify(process.versions));"; '
      . 'L1=$('
      . $locale
      . ' npm list '
      . $global
      . '--json --silent --depth=0 2>/dev/null); '
      . '[ "$L1" != "" ] && [ "$L1" != "\n" ] && echo ", \"listed\": $L1"; '
      . 'L2=$('
      . $locale
      . ' npm outdated '
      . $global
      . '--json --silent 2>&1); '
      . '[ "$L2" != "" ] && [ "$L2" != "\n" ] && echo ", \"outdated\": $L2"; '
      . 'echo "}"'
      . $cmdSuffix;

    my $response;

    if ( $cmd->{cmd} =~ /^install (.+)/ ) {
        if (   not defined( $cmd->{nodejsversions} )
            or not defined( $cmd->{nodejsversions}{node} ) )
        {
            if ( $1 =~ /^nodejs-v(\d+)/ ) {
                $npm->{npminstall} =
                    $cmdPrefix
                  . 'echo n | if [ -z "$(node --version 2>/dev/null)" ]; then'
                  . ' sh -c "( '
                  . $locale
                  . ' curl -fsSL https://deb.nodesource.com/setup_'
                  . $1
                  . '.x 2>/dev/null || '
                  . $locale
                  . ' wget -qO- https://deb.nodesource.com/setup_'
                  . $1
                  . '.x 2>/dev/null ) | '
                  . $locale
                  . ' DEBIAN_FRONTEND=noninteractive sudo -n bash - >/dev/null 2>&1" 2>&1 &&'
                  . ' sh -c "'
                  . $locale
                  . ' DEBIAN_FRONTEND=noninteractive sudo -n apt-get install -qqy nodejs >/dev/null 2>&1" 2>&1; '
                  . 'fi; '
                  . $locale
                  . ' node -e "console.log(JSON.stringify(process.versions));" 2>&1'
                  . $cmdSuffix;
            }
        }
        else {
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
            $npm->{npminstall} =~ s/%PACKAGES%/$pkglist/gi;
        }
        print qq($npm->{npminstall}\n) if ( $npm->{debug} == 1 );
        $response = NpmInstall($npm);
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
        $npm->{npmuninstall} =~ s/%PACKAGES%/$pkglist/gi;
        print qq($npm->{npmuninstall}\n) if ( $npm->{debug} == 1 );
        $response = NpmUninstall($npm);
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
        $npm->{npmupdate} =~ s/%PACKAGES%/$pkglist/gi;
        print qq($npm->{npmupdate}\n) if ( $npm->{debug} == 1 );
        $response = NpmUpdate($npm);
    }
    elsif ( $cmd->{cmd} eq 'outdated' ) {
        print qq($npm->{npmoutdated}\n) if ( $npm->{debug} == 1 );
        $response = NpmOutdated($npm);
    }
    elsif ( $cmd->{cmd} eq 'getNodeVersion' ) {
        print qq($npm->{nodejsversions}\n) if ( $npm->{debug} == 1 );
        $response = GetNodeVersion($npm);
    }

    return $response;
}

sub GetNodeVersion($) {
    my $cmd = shift;
    my $p   = `$cmd->{nodejsversions}`;
    my $ret = RetrieveNpmOutput( $cmd, $p );

    return { versions => $ret }
      if ( scalar keys %{$ret} > 0 && !defined( $ret->{error} ) );
    return $ret;
}

sub NpmUninstall($) {
    my $cmd = shift;
    my $p   = `$cmd->{npmuninstall}`;
    my $ret = RetrieveNpmOutput( $cmd, $p );

    return $ret;
}

sub NpmUpdate($) {
    my $cmd = shift;
    eval {
        umask 0022;
        1;
    };
    my $p   = `$cmd->{npmupdate}`;
    my $ret = RetrieveNpmOutput( $cmd, $p );

    return $ret;
}

sub NpmInstall($) {
    my $cmd = shift;
    eval {
        umask 0022;
        1;
    };
    my $p   = `$cmd->{npminstall}`;
    my $ret = RetrieveNpmOutput( $cmd, $p );

    # this will come back only after
    #  nodejs installation
    return { versions => $ret }
      if ( scalar keys %{$ret} > 0
        && defined( $ret->{node} ) );
    return $ret;
}

sub NpmOutdated($) {
    my $cmd = shift;
    my $p   = `$cmd->{npmoutdated}`;
    my $ret = RetrieveNpmOutput( $cmd, $p );

    return $ret;
}

sub RetrieveNpmOutput($$) {
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
                my $runningUser = getpwuid($<);
                if ( $o =~ m/Permission.denied.\(publickey\)\.?\r?\n?$/i ) {
                    $h->{error}{code} = "E403";
                    $h->{error}{summary} =
                        "Forbidden - None of the SSH keys from ~/.ssh/ "
                      . "were authorized to access remote host";
                    $h->{error}{detail} = "<pre>$o</pre>";
                }
                elsif ( $o =~ m/(sudo: .+)/i ) {
                    $h->{error}{code} = "E403";
                    $h->{error}{summary} =
                      "Forbidden - " . "passwordless sudo permissions required";
                    $h->{error}{detail} =
                        $1
                      . "<br /><br />"
                      . "You may add the following lines to /etc/sudoers.d/$runningUser:\n"
                      . "<pre>"
                      . "  $runningUser ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm update *\n"
                      . "  $runningUser ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm install *\n"
                      . "  $runningUser ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm uninstall *"
                      . "</pre>";
                }
                elsif ( $o =~
                    m/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?not.found$/i
                    or $o =~
m/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?No.such.file.or.directory$/i
                  )
                {
                    $h->{error}{code}    = "E404";
                    $h->{error}{summary} = "Not Found - $3 is not installed";
                    $h->{error}{detail}  = "<pre>$o</pre>";
                }
                else {
                    $h->{error}{code}    = "E501";
                    $h->{error}{summary} = "Parsing error - " . $@;
                    $h->{error}{detail}  = "<pre>$p</pre>";
                }
            }
            elsif ( $json =~
                m/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?not.found$/im
                or $json =~
m/(?:(\w+?): )?(?:(\w+? \d+): )?(\w+?): [^:]*?No.such.file.or.directory$/im
              )
            {
                $h->{error}{code}    = "E404";
                $h->{error}{summary} = "Not Found - $3 is not installed";
                $h->{error}{detail}  = "<pre>$o</pre>";
            }
            else {
                $h->{error}{code}    = "E500";
                $h->{error}{summary} = "Parsing error - " . $@;
                $h->{error}{detail}  = "<pre>$p</pre>";
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
        Log3 $name, 2, "npmjs ($name) - JSON error: $@";
        return;
    }

    Log3 $hash, 4, "npmjs ($name) - JSON: $json";

    if (   defined( $decode_json->{versions} )
        && defined( $decode_json->{versions}{node} ) )
    {
        $hash->{".fhem"}{npm}{nodejsversions} = $decode_json->{versions};
    }

    # safe result in hidden reading
    #   to restore module state after reboot
    if ( $hash->{".fhem"}{npm}{cmd} eq 'outdated' ) {
        delete $hash->{".fhem"}{npm}{outdatedpackages};
        $hash->{".fhem"}{npm}{outdatedpackages} = $decode_json->{outdated}
          if ( defined( $decode_json->{outdated} ) );
        delete $hash->{".fhem"}{npm}{listedpackages};
        $hash->{".fhem"}{npm}{listedpackages} = $decode_json->{listed}
          if ( defined( $decode_json->{listed} ) );
        readingsSingleUpdate( $hash, '.packageList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{npm}{cmd} =~ /^install/ ) {
        delete $hash->{".fhem"}{npm}{installedpackages};
        $hash->{".fhem"}{npm}{installedpackages} = $decode_json;
        readingsSingleUpdate( $hash, '.installedList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{npm}{cmd} =~ /^uninstall/ ) {
        delete $hash->{".fhem"}{npm}{uninstalledpackages};
        $hash->{".fhem"}{npm}{uninstalledpackages} = $decode_json;
        readingsSingleUpdate( $hash, '.uninstalledList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{npm}{cmd} =~ /^update/ ) {
        delete $hash->{".fhem"}{npm}{updatedpackages};
        $hash->{".fhem"}{npm}{updatedpackages} = $decode_json;
        readingsSingleUpdate( $hash, '.updatedList', $json, 0 );
    }

    if (   defined( $decode_json->{warning} )
        or defined( $decode_json->{error} ) )
    {
        $hash->{".fhem"}{npm}{'warnings'} = $decode_json->{warning}
          if ( defined( $decode_json->{warning} ) );
        $hash->{".fhem"}{npm}{errors} = $decode_json->{error}
          if ( defined( $decode_json->{error} ) );
    }
    else {
        delete $hash->{".fhem"}{npm}{'warnings'};
        delete $hash->{".fhem"}{npm}{errors};
    }

    WriteReadings( $hash, $decode_json );
}

sub WriteReadings($$) {

    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};

    Log3 $hash, 4, "npmjs ($name) - Write Readings";
    Log3 $hash, 5, "npmjs ($name) - " . Dumper $decode_json;

    readingsBeginUpdate($hash);

    if ( $hash->{".fhem"}{npm}{cmd} eq 'outdated' ) {
        readingsBulkUpdate(
            $hash,
            'outdated',
            (
                defined( $decode_json->{listed} )
                ? 'check completed'
                : 'check failed'
            )
        );
        delete $hash->{".fhem"}{npm}{nodejsversions}
          unless ( $decode_json->{versions} );
        $hash->{helper}{lastSync} = ToDay();
    }

    readingsBulkUpdateIfChanged( $hash, 'updatesAvailable',
        scalar keys %{ $decode_json->{outdated} } )
      if ( $hash->{".fhem"}{npm}{cmd} eq 'outdated' );
    readingsBulkUpdateIfChanged( $hash, 'updateListAsJSON',
        eval { encode_json( $hash->{".fhem"}{npm}{outdatedpackages} ) } )
      if ( AttrVal( $name, 'updateListReading', 'none' ) ne 'none' );

    my $result = 'successful';
    $result = 'error'   if ( defined( $hash->{".fhem"}{npm}{errors} ) );
    $result = 'warning' if ( defined( $hash->{".fhem"}{npm}{'warnings'} ) );

    readingsBulkUpdate( $hash, 'installed', $result )
      if ( $hash->{".fhem"}{npm}{cmd} =~ /^install/ );
    readingsBulkUpdate( $hash, 'uninstalled', $result )
      if ( $hash->{".fhem"}{npm}{cmd} =~ /^uninstall/ );
    readingsBulkUpdate( $hash, 'updated', $result )
      if ( $hash->{".fhem"}{npm}{cmd} =~ /^update/ );

    readingsBulkUpdateIfChanged( $hash, "nodejsVersion",
        $decode_json->{versions}{node} )
      if ( defined( $decode_json->{versions} )
        && defined( $decode_json->{versions}{node} ) );

    if ( defined( $decode_json->{error} ) ) {
        readingsBulkUpdate( $hash, 'state',
            'error \'' . $hash->{".fhem"}{npm}{cmd} . '\'' );
    }
    elsif ( defined( $decode_json->{warning} ) ) {
        readingsBulkUpdate( $hash, 'state',
            'warning \'' . $hash->{".fhem"}{npm}{cmd} . '\'' );
    }
    else {

        readingsBulkUpdate(
            $hash, 'state',
            (
                (
                         scalar keys %{ $decode_json->{outdated} } > 0
                      or scalar
                      keys %{ $hash->{".fhem"}{npm}{outdatedpackages} } > 0
                )
                ? 'npm updates available'
                : 'npm is up to date'
            )
        );
    }

    Event( $hash, "FINISH" );
    readingsEndUpdate( $hash, 1 );

    ProcessUpdateTimer($hash)
      if ( $hash->{".fhem"}{npm}{cmd} eq 'getNodeVersion'
        && !defined( $decode_json->{error} ) );
}

sub CreateWarningList($) {

    my $hash = shift;

    my $warnings = $hash->{".fhem"}{npm}{'warnings'};

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    my $ret = '<html><table><tr><td>';
    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even">';
    $ret .= "<td><b>Warning List</b></td>";
    $ret .= "<td></td>";
    $ret .= '</tr>';

    if ( ref($warnings) eq "ARRAY" ) {

        my $linecount = 1;
        foreach my $warning ( @{$warnings} ) {
            if ( $linecount % 2 == 0 ) {
                $ret .= '<tr class="even">';
            }
            else {
                $ret .= '<tr class="odd">';
            }

            $ret .= "<td>$warning->{message}</td>";

            $ret .= '</tr>';
            $linecount++;
        }
    }

    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;
}

sub CreateErrorList($) {
    my $hash  = shift;
    my $error = $hash->{".fhem"}{npm}{errors};

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    my $ret = '<html><table style="min-width: 450px;"><tr><td>';
    $ret .= '<table class="block wide">';

    if ( ref($error) eq "HASH" ) {
        $ret .= '<tr class="even">';
        $ret .= "<td><b>Error code $error->{code}</b></td>";
        $ret .= "<td></td>";
        $ret .= '</tr>';
        $ret .= '<tr class="odd">';
        $ret .= "<td><b>Summary:</b><br />$error->{summary}</td>";
        $ret .= '</tr>';
        $ret .= '<tr class="even">';
        $ret .= "<td><b>Detail:</b><br />$error->{detail}</td>";
        $ret .= '</tr>';
    }
    else {
        $ret .= '<tr class="even">';
        $ret .= "<td><b>Error List</b></td>";
        $ret .= "<td></td>";
        $ret .= '</tr>';
    }

    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;
}

sub CreateInstalledList($$) {
    my ( $hash, $getCmd ) = @_;
    my @ret;
    my $packages;
    my $html = defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : 0;
    $packages = $hash->{".fhem"}{npm}{listedpackages}{dependencies};

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    my $header = '';
    my $footer = '';
    if ($html) {
        $header = '<html><table class="block wide">';
        $footer = '</table></html>';
    }

    my $rowOpen         = '';
    my $rowOpenEven     = '';
    my $rowOpenOdd      = '';
    my $colOpen         = '';
    my $colOpenMinWidth = '';
    my $txtOpen         = '';
    my $txtClose        = '';
    my $colClose        = "\t\t\t";
    my $rowClose        = '';

    if ($html) {
        $rowOpen         = '<tr>';
        $rowOpenEven     = '<tr class="even">';
        $rowOpenOdd      = '<tr class="odd">';
        $colOpen         = '<td>';
        $colOpenMinWidth = '<td style="min-width: 12em;">';
        $txtOpen         = "<b>";
        $txtClose        = "</b>";
        $colClose        = '</td>';
        $rowClose        = '</tr>';
    }

    push @ret,
        $rowOpen
      . $colOpenMinWidth
      . $txtOpen
      . 'Package Name'
      . $txtClose
      . $colClose
      . $colOpenMinWidth
      . $txtOpen
      . 'Installed Version'
      . $txtClose
      . $colClose
      . $rowClose;

    if ( ref($packages) eq "HASH" ) {

        my $linecount = 1;
        foreach my $package ( sort { "\L$a" cmp "\L$b" } keys( %{$packages} ) )
        {
            next if ( $package eq "undefined" );

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;
            $l .= $colOpenMinWidth . $package . $colClose;
            $l .= $colOpenMinWidth
              . (
                defined( $packages->{$package}{version} )
                ? $packages->{$package}{version}
                : '?'
              ) . $colClose;
            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }

    return $header . join( "\n", @ret ) . $footer;
}

sub CreateOutdatedList($$) {
    my ( $hash, $getCmd ) = @_;
    my @ret;
    my $packages;
    my $html = defined( $hash->{CL} ) && $hash->{CL}{TYPE} eq "FHEMWEB" ? 1 : 0;
    $packages = $hash->{".fhem"}{npm}{outdatedpackages};
    my $npmglobal = ( AttrVal( $hash->{NAME}, 'npmglobal', 1 ) eq '1' ? 1 : 0 );

    # disable automatic links to FHEM devices
    delete $FW_webArgs{addLinks};

    my $header = '';
    my $footer = '';
    if ($html) {
        $header = '<html><table class="block wide">';
        $footer = '</table></html>';
    }

    my $rowOpen         = '';
    my $rowOpenEven     = '';
    my $rowOpenOdd      = '';
    my $colOpen         = '';
    my $colOpenMinWidth = '';
    my $txtOpen         = '';
    my $txtClose        = '';
    my $colClose        = "\t\t\t";
    my $rowClose        = '';

    if ($html) {
        $rowOpen         = '<tr>';
        $rowOpenEven     = '<tr class="even">';
        $rowOpenOdd      = '<tr class="odd">';
        $colOpen         = '<td>';
        $colOpenMinWidth = '<td style="min-width: 12em;">';
        $txtOpen         = "<b>";
        $txtClose        = "</b>";
        $colClose        = '</td>';
        $rowClose        = '</tr>';
    }

    push @ret,
        $rowOpen
      . $colOpenMinWidth
      . $txtOpen
      . 'Package Name'
      . $txtClose
      . $colClose
      . $colOpenMinWidth
      . $txtOpen
      . 'Installed Version'
      . $txtClose
      . $colClose
      . $colOpenMinWidth
      . $txtOpen
      . 'Update Version'
      . $txtClose
      . $colClose
      . $colOpenMinWidth
      . $txtOpen
      . 'Upgrade Version'
      . $txtClose
      . $colClose
      . $rowClose;

    if ( ref($packages) eq "HASH" ) {

        my $linecount = 1;
        foreach my $package ( sort { "\L$a" cmp "\L$b" } keys( %{$packages} ) )
        {
            next if ( $package eq "undefined" );
            my $fhemPkg = defined( $fhem_npm_modules{$package} ) ? 1 : 0;

            my $l = $linecount % 2 == 0 ? $rowOpenEven : $rowOpenOdd;
            $l .= $colOpenMinWidth . $package . $colClose;
            $l .= $colOpenMinWidth
              . (
                defined( $packages->{$package}{current} )
                ? $packages->{$package}{current}
                : '?'
              ) . $colClose;
            $l .= $colOpenMinWidth . (
                defined( $packages->{$package}{wanted} )
                ? (
                      $fhemPkg
                    ? $packages->{$package}{latest}
                    : (
                        defined( $packages->{$package}{current} )
                        ? (
                            $packages->{$package}{wanted} ne
                              $packages->{$package}{current}
                            ? $packages->{$package}{wanted}
                            : ''
                          )
                        : $packages->{$package}{wanted}
                      )

                  )
                : '?'
            ) . $colClose;
            $l .= $colOpenMinWidth
              . (
                defined( $packages->{$package}{latest} )
                ? $packages->{$package}{latest}
                : '?'
              ) . $colClose;
            $l .= $rowClose;

            push @ret, $l;
            $linecount++;
        }
    }

    return $header . join( "\n", @ret ) . $footer;
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
=item device
=item summary       Module to control Node.js package installation and update
=item summary_DE    Modul zur Bedienung der Node.js Paket Installation und Updates

=begin html

<a name="npmjs" id="npmjs"></a>
<h3>
  Node.js installation and update
</h3>
<ul>
  <u><b>npmjs - controls Node.js installation and updates</b></u><br>
  This module allows to install, uninstall and update outdated Node.js packages using NPM package manager.<br>
  Global installations will be controlled by default and running update/install/uninstall require sudo permissions like this:<br>
  <br>
  <code>
    fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm update *<br>
    fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm install *<br>
    fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm uninstall *
  </code><br>
  <br>
  This line may easily be added to a new file in /etc/sudoers.d/fhem and will automatically included to /etc/sudoers from there.<br>
  <br>
  <br>
  <a name="npmjsdefine" id="npmjsdefine"></a><b>Define</b><br>
  <ul>
    <code>define &lt;name&gt; npmjs [&lt;[user@]HOSTNAME[:port]&gt;]</code><br>
    <br>
    Example:<br>
    <ul>
      <code>define fhemServerNpm npmjs</code><br>
    </ul><br>
    This command creates an npmjs instance named 'fhemServerNpm' to run commands on the local host machine.
    Afterwards all information about installation and update state will be fetched. This will take a moment.<br>
    <br>
    If you would like to connect to a remote host, set the optional HOSTNAME to something different than 'localhost'.
    In that case, make sure that SSH keys between the FHEM running user and remote server are setup appropriately.
  </ul><br>
  <br>
  <a name="npmjsreadings" id="npmjsreadings"></a><b>Readings</b>
  <ul>
    <li>state - update status about the server
    </li>
    <li>nodejsVersion - installed Node.js version
    </li>
    <li>outdated - status about last update status sync
    </li>
    <li>updated - status about last update command
    </li>
    <li>installed - status about last install command
    </li>
    <li>uninstalled - status about last uninstall command
    </li>
    <li>updatesAvailable - number of available updates
    </li>
  </ul><br>
  <br>
  <a name="npmjsset" id="npmjsset"></a><b>Set</b>
  <ul>
    <li>statusRequest - Update Node.js installation status
    </li>
    <li>outdated - fetch information about update state
    </li>
    <li>update - trigger complete or selected update process (using 'npm update' command). FHEM related packages will always be upgraded to the latest major version (using 'npm install' instead of 'npm update'). Other packages will repsect <a href="https://semver.org/">semantic versioning</a> and major upgrades will not be performed.
    </li>
    <li>upgrade - trigger complete or selected upgrade process (using 'npm install' command). ATTENTION! Every package will be upgraded to the latest and greatest version (using 'npm install' command instead of 'npm update'), no matter if the package maintainer has defined some incompatiblities between the current installed and latest version. If in doubt, consider to only use the update set command instead.
    </li>
    <li>install - Install one or more NPM packages. If Node.js is not installed on the server, it will offer to
        initially install Node.js (APT compatible Linux distributions only). You may still install Node.js and
        NPM manually and trigger to re-detect the installation by using any of the provided options. Existing
        Node.js installations will never be overwritten and it will not be possible to upgrade Node.js using
        this FHEM module!
    </li>
    <li>uninstall - Uninstall one or more NPM packages
    </li>
  </ul><br>
  <br>
  <a name="npmjsget" id="npmjsget"></a><b>Get</b>
  <ul>
    <li>showOutdatedList - list about available updates
    </li>
    <li>showErrorList - list errors that occured for the last command
    </li>
  </ul><br>
  <br>
  <a name="npmjsattribut" id="npmjsattribut"></a><b>Attributes</b>
  <ul>
    <li>disable - disables the device
    </li>
    <li>updateListReading - add Update List Reading as JSON
    </li>
    <li>npmglobal - work on global or user installation. Defaults to 1=global
    </li>
    <li>disabledForIntervals - disable device for interval time (13:00-18:30 or 13:00-18:30 22:00-23:00)
    </li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="npmjs" id="npmjs"></a>
<h3>
  Node.js Installation und Update
</h3>
<ul>
  <u><b>npmjs - Bedienung der Node.js Installation und Updates</b></u><br>
  Das Modul erlaubt es Node.js Pakete &uuml;ber den NPM Paket Manager zu installieren, zu deinstallieren und zu aktualisieren.<br>
  Standardm&auml;&szlig;ig werden globale Installationen bedient und das Ausf&uuml;hren von update/install/uninstall erfordert sudo Berechtigungen wie diese:<br>
  <br>
  <code>
    fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm update *<br>
    fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm install *<br>
    fhem ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm uninstall *
  </code><br>
  <br>
  Diese Zeile kann einfach in einer neuen Datei unter /etc/sudoers.d/fhem hinzugef&uuml;gt werden und wird von dort automatisch in /etc/sudoers inkludiert.<br>
  <br>
  <br>
  <a name="npmjsdefine" id="npmjsdefine"></a><b>Define</b><br>
  <ul>
    <code>define &lt;name&gt; npmjs [&lt;[user@]HOSTNAME[:port]&gt;]</code><br>
    <br>
    Beispiel:<br>
    <ul>
      <code>define fhemServer npmjs</code><br>
    </ul><br>
    Der Befehl erstellt eine npmjs Instanz mit dem Namen 'fhemServerNpm', um Kommandos auf der lokalen Host Maschine auszuf&uuml;hren.
    Anschlie&szlig;end werden die alle Informationen &uuml;ber den Installations- und Update Status geholt. Dies kann einen Moment dauern.<br>
    <br>
    Wenn man sich zu einem entfernten Rechner verbinden m&ouml;chte, kann man den optionalen HOSTNAME Parameter zu etwas anderem als 'localhost' setzen.
    In diesem Fall muss auch sichergestellt sein, dass die SSH Schl&uuml;ssel zwischen dem laufenden FHEM Benutzer und dem entfernten Server entsprechend konfiguriert sind.
  </ul><br>
  <br>
  <a name="npmjsreadings" id="npmjsreadings"></a><b>Readings</b>
  <ul>
    <li>state - update Status des Servers
    </li>
    <li>nodejsVersion - installierte Node.js Version
    </li>
    <li>outdated - Status des letzten Update sync.
    </li>
    <li>updated - Status des letzten update Befehles
    </li>
    <li>installed - Status des letzten install Befehles
    </li>
    <li>uninstalled - Status des letzten uninstall Befehles
    </li>
    <li>updatesAvailable - Anzahl der verf&uuml;gbaren Paketupdates
    </li>
  </ul><br>
  <br>
  <a name="npmjsset" id="npmjsset"></a><b>Set</b>
  <ul>
    <li>statusRequest - Node.js Installationsstatus aktualisieren
    </li>
    <li>outdated - Holt aktuelle Informationen &uuml;ber den Updatestatus
    </li>
    <li>update - F&uuml;hrt ein komplettes oder selektives Update aus (nutzt 'npm update' Kommando). FHEM relevante Pakete werden immer auf die neuste Major Version upgegraded (nutzt 'npm install' Kommando anstatt von 'npm update'). <a href="https://semver.org/">Semantische Versionierung</a> wird bei anderen Paketen weiterhin respektiert und es werden keine Major Upgrades durchgef&uuml;hrt.
    </li>
    <li>upgrade - F&uuml;hrt ein komplettes oder selektives Upgrade aus (nutzt 'npm install' Kommando). ACHTUNG! Jedes Paket wird auf die neuste und gr&ouml;&szlig;te Version upgegraded (nutzt 'npm install' Kommando anstatt von 'npm update'), ganz egal ob der Paket Maintainer eine Inkompatibilit&auml;t zwischen der aktuell installierten und der neusten Version definiert hat. Im Zweifel sollte besser stattdessen das Update set Kommando benutzt werden.
    </li>
    <li>install - Installiert ein oder mehrere NPM Pakete. Wenn Node.js nicht installiert ist, wird die erstmalige
        Installation von Node.js angeboten (nur für APT kompatible Linux Distributionen). Node.js kann weiterhin
        manuell installiert werden. &Uuml;ber jede der angebotenen Optionen kann eine erneute Pr&uuml;fung veranlasst
        werden. Bestehende Node.js Installationen werden niemals &uuml;berschrieben und es ist nicht m&ouml;glich ein
        Upgrade von Node.js &uuml;ber dieses FHEM Modul durchzuf&uuml;hren!
    </li>
    <li>uninstall - deinstalliert ein oder mehrere NPM Pakete
    </li>
  </ul><br>
  <br>
  <a name="npmjsget" id="npmjsget"></a><b>Get</b>
  <ul>
    <li>showOutdatedList - Paketiste aller zur Verf&uuml;gung stehender Updates
    </li>
    <li>showErrorList - Liste aller aufgetretenden Fehler f&uuml;r das letzte Kommando
    </li>
  </ul><br>
  <br>
  <a name="npmjsattribut" id="npmjsattribut"></a><b>Attributes</b>
  <ul>
    <li>disable - Deaktiviert das Device
    </li>
    <li>updateListReading - f&uuml;gt die Update Liste als ein zus&auml;iches Reading im JSON Format ein.
    </li>
    <li>npmglobal - wechselt zwischen Global- und Benutzer-Installation. Standard ist 1=global
    </li>
    <li>disabledForIntervals - Deaktiviert das Device f&uuml;r eine bestimmte Zeit (13:00-18:30 or 13:00-18:30 22:00-23:00)
    </li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 42_npmjs.pm
{
  "abstract": "Module to control Node.js package installation and update",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Bedienung der Node.js Installation und Updates"
    }
  },
  "version": "v1.1.6",
  "release_status": "stable",
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
    "nodejs",
    "setup",
    "update"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "GPUtils": 0,
        "JSON::PP": 0,
        "Data::Dumper": 0,
        "SubProcess": 0
      },
      "recommends": {
        "JSON": 0
      },
      "suggests": {
        "Cpanel::JSON::XS": 0,
        "JSON::XS": 0
      }
    }
  },
  "x_prereqs_nodejs": {
    "runtime": {
      "requires": {
        "node": 8.0,
        "npm": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_binary_exec": {
    "runtime": {
      "requires": {
        "/usr/bin/node|/usr/local/bin/node": 0,
        "/usr/bin/npm|/usr/local/bin/npm": 0
      },
      "recommends": {
      },
      "suggests": {
        "/usr/bin/ssh|/usr/local/bin/ssh": 0
      }
    }
  },
  "x_prereqs_sudo": {
    "runtime": {
      "requires": {
      },
      "recommends": {
        "ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm update *": 0,
        "ALL=(ALL) NOPASSWD:SETENV: /usr/local/bin/npm update *": 0,
        "ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm install *": 0,
        "ALL=(ALL) NOPASSWD:SETENV: /usr/local/bin/npm install *": 0
      },
      "suggests": {
        "ALL=(ALL) NOPASSWD:SETENV: /usr/bin/npm uninstall *": 0,
        "ALL=(ALL) NOPASSWD:SETENV: /usr/local/bin/npm uninstall *": 0
      }
    }
  }
}
=end :application/json;q=META.json

=cut
