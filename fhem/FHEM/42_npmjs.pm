###############################################################################
# $Id$
#
# Based on 42_AptToDate.pm by CoolTux

package main;

use strict;
use warnings;

sub npmjs_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}    = "npmjs::Set";
    $hash->{GetFn}    = "npmjs::Get";
    $hash->{DefFn}    = "npmjs::Define";
    $hash->{NotifyFn} = "npmjs::Notify";
    $hash->{UndefFn}  = "npmjs::Undef";
    $hash->{AttrFn}   = "npmjs::Attr";
    $hash->{AttrList} =
        "disable:1,0 "
      . "disabledForIntervals "
      . "upgradeListReading:1,0 "
      . "npmglobal:1,0 "
      . $readingFnAttributes;

    # update INTERNAL after module reload
    foreach my $d ( devspec2array("TYPE=npmjs") ) {
        $defs{$d}{VERSION} = $npmjs::VERSION;
    }
}

# define package
package npmjs;

use strict;
use warnings;
use POSIX;

# our @EXPORT  = qw(get_time_suffix);
our $VERSION = "0.9.3";

# wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use GPUtils qw(GP_Import);

use Data::Dumper;    #only for Debugging

my $missingModule = "";
eval "use JSON;1" or $missingModule .= "JSON ";

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsTimestamp
          defs
          modules
          Log3
          Debug
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

my @fhem_modules = ( "alexa-fhem", "tradfri-fhem" );

sub Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return
      "Cannot define npmjs device. Perl module ${missingModule} is missing."
      if ($missingModule);

    my $name = $a[0];
    my $host = $a[2] ? $a[2] : 'localhost';

    $hash->{VERSION}   = $VERSION;
    $hash->{HOST}      = $host;
    $hash->{NOTIFYDEV} = "global,$name";

    return "Existing instance for host $hash->{HOST}: "
      . $modules{ $hash->{TYPE} }{defptr}{ $hash->{HOST} }{NAME}
      if ( defined( $modules{ $hash->{TYPE} }{defptr}{ $hash->{HOST} } ) );

    $modules{ $hash->{TYPE} }{defptr}{ $hash->{HOST} } = $hash;

    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {

        # presets for FHEMWEB
        $attr{$name}{alias} = 'Node.js Update Status';
        $attr{$name}{devStateIcon} =
'npm.updates.available:security@red:outdated npm.is.up.to.date:security@green:outdated .*in.progress:system_fhem_reboot@orange errors:message_attention@red';
        $attr{$name}{group} = 'System';
        $attr{$name}{icon}  = 'nodejs';
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
    Log3 $name, 3, "Sub npmjs ($name) - delete device $name";
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

    Log3 $name, 5, "npmjs ($name) - Notify: " . Dumper $events;    # mit Dumper

    if (
        (
            (
                grep /^DEFINED.$name$/,
                @{$events}
                or grep /^DELETEATTR.$name.disable$/,
                @{$events}
                or grep /^ATTR.$name.disable.0$/,
                @{$events}
            )
            and $devname eq 'global'
            and $init_done
        )
        or (
            (
                grep /^INITIALIZED$/,
                @{$events}
                or grep /^REREADCFG$/,
                @{$events}
                or grep /^MODIFIED.$name$/,
                @{$events}
            )
            and $devname eq 'global'
        )
      )
    {

        if (
            ref(
                eval { decode_json( ReadingsVal( $name, '.upgradeList', '' ) ) }
            ) eq "HASH"
          )
        {
            $hash->{".fhem"}{npm}{packages} =
              eval { decode_json( ReadingsVal( $name, '.upgradeList', '' ) ) }
              ->{packages};
        }
        elsif (
            ref(
                eval { decode_json( ReadingsVal( $name, '.updatedList', '' ) ) }
            ) eq "HASH"
          )
        {
            $hash->{".fhem"}{npm}{updatedpackages} =
              eval { decode_json( ReadingsVal( $name, '.updatedList', '' ) ) }
              ->{packages};
        }

        if ( ReadingsVal( $name, 'nodejsVersion', 'none' ) ne 'none' ) {
            ProcessUpdateTimer($hash);
        }
        else {
            $hash->{".fhem"}{npm}{cmd} = 'getNodeVersion';
            AsynchronousExecuteNpmCommand($hash);
        }
    }

    if ( $devname eq $name and grep /^update:.successful$/, @{$events} ) {
        $hash->{".fhem"}{npm}{cmd} = 'outdated';
        AsynchronousExecuteNpmCommand($hash);
    }

    return;
}

sub Set($$@) {

    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    if ( $cmd eq 'outdated' ) {

        # return "usage: $cmd" if ( @args != 0 );

        $hash->{".fhem"}{npm}{cmd} = $cmd;

    }
    elsif ( $cmd eq 'update' ) {

        # return "usage: $cmd" if ( @args != 0 );

        $hash->{".fhem"}{npm}{cmd} = $cmd;

    }
    else {
        my $list = "outdated:noArg";
        $list .= " update:noArg"
          if ( defined( $hash->{".fhem"}{npm}{packages} )
            and scalar keys %{ $hash->{".fhem"}{npm}{packages} } > 0 );

        return "Unknown argument $cmd, choose one of $list";
    }

    AsynchronousExecuteNpmCommand($hash);

    return undef;
}

sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    if ( $cmd eq 'showUpgradeList' ) {
        return "usage: $cmd" if ( @args != 0 );

        my $ret = CreateUpgradeList( $hash, $cmd );
        return $ret;

    }
    elsif ( $cmd eq 'showUpdatedList' ) {
        return "usage: $cmd" if ( @args != 0 );

        my $ret = CreateUpgradeList( $hash, $cmd );
        return $ret;

    }
    elsif ( $cmd eq 'nodejsVersion' ) {
        return "usage: $cmd" if ( @args != 0 );

        $hash->{".fhem"}{npm}{cmd} = 'getNodeVersion';
        AsynchronousExecuteNpmCommand($hash);
    }
    else {
        my $list = "";
        $list .= " showUpgradeList:noArg"
          if ( defined( $hash->{".fhem"}{npm}{packages} )
            and scalar keys %{ $hash->{".fhem"}{npm}{packages} } > 0 );
        $list .= " showUpdatedList:noArg"
          if ( defined( $hash->{".fhem"}{npm}{updatedpackages} )
            and scalar keys %{ $hash->{".fhem"}{npm}{updatedpackages} } > 0 );

        return "Unknown argument $cmd, choose one of $list";
    }
}

###################################
sub ProcessUpdateTimer($) {

    my $hash = shift;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 14400,
        "npmjs::ProcessUpdateTimer", $hash, 0 );
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
      ( AttrVal( $name, 'npmglobal', 1 ) == 1 ? 1 : 0 );
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

    Log3 $name, 4, "npmjs ($name) - execute command asynchronously (PID= $pid)";

    $hash->{".fhem"}{subprocess} = $subprocess;

    InternalTimer( gettimeofday() + POLLINTERVAL,
        "npmjs::PollChild", $hash, 0 );
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
            "npmjs::PollChild", $hash, 0 );
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

    my $response = ExecuteNpmCommand( $subprocess->{npm} );

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

    my $cmdPrefix = "";
    my $cmdSuffix = "";

    if ( $cmd->{host} ne 'localhost' ) {
        $cmdPrefix = 'ssh ' . $cmd->{host} . ' \'';
        $cmdSuffix = '\'';
    }

    $npm->{nodejsversion} = $cmdPrefix . 'echo n | node --version' . $cmdSuffix;
    if ( $cmd->{npmglobal} == 0 ) {
        $npm->{npmupdate} =
          $cmdPrefix . 'echo n | npm update --unsafe-perm' . $cmdSuffix;
        $npm->{npmoutdated} =
            $cmdPrefix
          . 'echo n | node --version; npm outdated --parseable'
          . $cmdSuffix;
    }
    else {
        $npm->{npmupdate} =
          $cmdPrefix . 'echo n | sudo npm update -g --unsafe-perm' . $cmdSuffix;
        $npm->{npmoutdated} =
            $cmdPrefix
          . 'echo n | node --version; sudo npm outdated -g --parseable'
          . $cmdSuffix;
    }

    my $response;

    if ( $cmd->{cmd} eq 'outdated' ) {
        $response = NpmOutdated($npm);
    }
    elsif ( $cmd->{cmd} eq 'getNodeVersion' ) {
        $response = GetNodeVersion($npm);
    }
    elsif ( $cmd->{cmd} eq 'update' ) {
        $response = NpmUpdate($npm);
    }

    return $response;
}

sub GetNodeVersion($) {

    my $cmd = shift;

    my $update = {};
    my $v      = `$cmd->{nodejsversion} 2>/dev/null`;

    if ( defined($v) and $v =~ /^v(\d+\.\d+\.\d+)/ ) {
        $update->{nodejsversion} = $1;
    }
    else {
        $update->{error} = 'Node.js not installed';
    }

    return $update;
}

sub NpmUpdate($) {

    my $cmd = shift;

    my $update = {};
    my $p      = `$cmd->{npmupdate}`;

    $update->{'state'} = 'done';
    return $update;
}

sub NpmOutdated($) {

    my $cmd = shift;

    my $updates = {};
    my $p       = `$cmd->{npmoutdated}`;

    foreach my $line ( split /\n/, $p ) {
        chomp($line);
        print qq($line\n) if ( $cmd->{debug} == 1 );

        if ( $line =~ m/^.*:((.*)@(.*)):((.*)@(.*)):((.*)@(.*))$/ ) {
            my $update  = {};
            my $package = $2;
            $update->{current}               = $6;
            $update->{new}                   = $9;
            $updates->{packages}->{$package} = $update;
        }
        elsif ( $line =~ m/^v(\d+\.\d+\.\d+)$/ ) {
            $updates->{nodejsversion} = $1;
        }
    }

    $updates->{'state'} = 'done';
    return $updates;
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

    if ( $hash->{".fhem"}{npm}{cmd} eq 'outdated' ) {
        $hash->{".fhem"}{npm}{packages} = $decode_json->{packages};
        readingsSingleUpdate( $hash, '.upgradeList', $json, 0 );
    }
    elsif ( $hash->{".fhem"}{npm}{cmd} eq 'update' ) {
        $hash->{".fhem"}{npm}{updatedpackages} = $decode_json->{packages};
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
    Log3 $hash, 5,
      "npmjs ($name) - Packages: " . scalar keys %{ $decode_json->{packages} };

    readingsBeginUpdate($hash);

    if ( $hash->{".fhem"}{npm}{cmd} eq 'outdated' ) {
        readingsBulkUpdate(
            $hash,
            'outdated',
            (
                defined( $decode_json->{'state'} )
                ? 'fetched ' . $decode_json->{'state'}
                : 'fetched error'
            )
        );
        $hash->{helper}{lastSync} = ToDay();
    }

    readingsBulkUpdateIfChanged( $hash, 'updatesAvailable',
        scalar keys %{ $decode_json->{packages} } )
      if ( $hash->{".fhem"}{npm}{cmd} eq 'outdated' );
    readingsBulkUpdateIfChanged( $hash, 'upgradeListAsJSON',
        eval { encode_json( $hash->{".fhem"}{npm}{packages} ) } )
      if ( AttrVal( $name, 'upgradeListReading', 'none' ) ne 'none' );
    readingsBulkUpdate( $hash, 'update', 'successful' )
      if (  $hash->{".fhem"}{npm}{cmd} eq 'update'
        and not defined( $hash->{".fhem"}{npm}{'errors'} )
        and not defined( $hash->{".fhem"}{npm}{'warnings'} ) );
    readingsBulkUpdateIfChanged( $hash, "nodejsVersion",
        $decode_json->{'nodejsversion'} )
      if ( defined( $decode_json->{'nodejsversion'} ) );

    if ( defined( $decode_json->{error} ) ) {
        readingsBulkUpdate( $hash, 'state',
            $hash->{".fhem"}{npm}{cmd} . ' Errors (get showErrorList)' );
        readingsBulkUpdate( $hash, 'state', 'errors' );
    }
    elsif ( defined( $decode_json->{warning} ) ) {
        readingsBulkUpdate( $hash, 'state',
            $hash->{".fhem"}{npm}{cmd} . ' Warnings (get showWarningList)' );
        readingsBulkUpdate( $hash, 'state', 'warnings' );
    }
    else {

        readingsBulkUpdate(
            $hash, 'state',
            (
                (
                         scalar keys %{ $decode_json->{packages} } > 0
                      or scalar keys %{ $hash->{".fhem"}{npm}{packages} } > 0
                )
                ? 'npm updates available'
                : 'npm is up to date'
            )
        );
    }

    readingsEndUpdate( $hash, 1 );

    ProcessUpdateTimer($hash)
      if ( $hash->{".fhem"}{npm}{cmd} eq 'getNodeVersion' );
}

sub CreateUpgradeList($$) {

    my ( $hash, $getCmd ) = @_;

    my $packages;
    $packages = $hash->{".fhem"}{npm}{packages}
      if ( $getCmd eq 'showUpgradeList' );
    $packages = $hash->{".fhem"}{npm}{updatedpackages}
      if ( $getCmd eq 'showUpdatedList' );

    my $ret = '<html><table><tr><td>';
    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even">';
    $ret .= "<td><b>Packagename</b></td>";
    $ret .= "<td><b>Current Version</b></td>"
      if ( $getCmd eq 'showUpgradeList' );
    $ret .= "<td><b>Over Version</b></td>" if ( $getCmd eq 'showUpdatedList' );
    $ret .= "<td><b>New Version</b></td>";
    $ret .= "<td></td>";
    $ret .= '</tr>';

    if ( ref($packages) eq "HASH" ) {

        my $linecount = 1;
        foreach my $package ( sort keys( %{$packages} ) ) {
            if ( $linecount % 2 == 0 ) {
                $ret .= '<tr class="even">';
            }
            else {
                $ret .= '<tr class="odd">';
            }

            $ret .= "<td>$package</td>";
            $ret .= "<td>$packages->{$package}{current}</td>";
            $ret .= "<td>$packages->{$package}{new}</td>";

            $ret .= '</tr>';
            $linecount++;
        }
    }

    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;
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
=item device
=item summary       Module to control Node.js installation and update
=item summary_DE    Modul zur Bedienung der Node.js Installation und Updates

=begin html

<a name="npmjs" id="npmjs"></a>
<h3>
  Node.js installation and update
</h3>
<ul>
  <u><b>npmjs - controls Node.js installation and updates</b></u><br>
  This module informs about outdated Node.js packages using NPM package manager.<br>
  Global installations will be controlled by default and require sudo permissions like this:<br>
  <li>fhem ALL=NOPASSWD: /usr/bin/npm
  </li><br>
  <a name="npmjsdefine" id="npmjsdefine"></a><b>Define</b>
  <ul>
    <br>
    <code>define &lt;name&gt; npmjs &lt;HOST&gt;</code><br>
    <br>
    Example:
    <ul>
      <br>
      <code>define fhemServerNpm npmjs localhost</code><br>
    </ul><br>
    This command creates an npmjs instance named 'fhemServerNpm' to run commands on host 'localhost'.<br>
    Afterwards all information about installation and update state will be fetched. This will take a moment.
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
    <li>update - status about last upgrade
    </li>
    <li>updatesAvailable - number of available updates
    </li>
  </ul><br>
  <br>
  <a name="npmjsset" id="npmjsset"></a><b>Set</b>
  <ul>
    <li>outdated - fetch information about update state
    </li>
    <li>update - trigger update process. this will take a moment
    </li><br>
  </ul><br>
  <br>
  <a name="npmjsget" id="npmjsget"></a><b>Get</b>
  <ul>
    <li>showUpgradeList - list about available updates
    </li>
    <li>getNodeVersion - fetch Node.js version information
    </li><br>
  </ul><br>
  <br>
  <a name="npmjsattribut" id="npmjsattribut"></a><b>Attributes</b>
  <ul>
    <li>disable - disables the device
    </li>
    <li>upgradeListReading - add Upgrade List Reading as JSON
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
  Das Modul prüft die zu aktualisierenden Node.js Pakete über den NPM Paket Manager.<br>
  Standardmäßig werden globale Installationen bedient und erfordern sudo Berechtigungen wie diese:<br>
  <li>fhem ALL=NOPASSWD: /usr/bin/npm update
  </li><br>
  <a name="npmjsdefine" id="npmjsdefine"></a><b>Define</b>
  <ul>
    <br>
    <code>define &lt;name&gt; npmjs &lt;HOST&gt;</code><br>
    <br>
    Beispiel:
    <ul>
      <br>
      <code>define fhemServer npmjs localhost</code><br>
    </ul><br>
    Der Befehl erstellt eine npmjs Instanz mit dem Namen 'fhemServerNpm', um Kommandos auf dem Host 'localhost' auszuf&uuml;hren.<br>
    Anschließend werden die alle Informationen über den Installations- und Update Status geholt. Dies kann einen Moment dauern.
  </ul><br>
  <br>
  <a name="npmjsreadings" id="npmjsreadings"></a><b>Readings</b>
  <ul>
    <li>state - update Status des Servers, liegen neue Updates an oder nicht
    </li>
    <li>nodejsVersion - installierte Node.js Version
    </li>
    <li>outdated - status des letzten update sync.
    </li>
    <li>update - status des letzten update Befehles
    </li>
    <li>updatesAvailable - Anzahl der verfügbaren Paketupdates
    </li>
  </ul><br>
  <br>
  <a name="npmjsset" id="npmjsset"></a><b>Set</b>
  <ul>
    <li>outdated - holt aktuelle Informationen über den Updatestatus
    </li>
    <li>update - führt den upgrade Prozess aus
    </li><br>
  </ul><br>
  <br>
  <a name="npmjsget" id="npmjsget"></a><b>Get</b>
  <ul>
    <li>showUpgradeList - Paketiste aller zur Verfügung stehender Updates
    </li>
    <li>getNodeVersion - Hole die NodeJS Versions-Information
    </li><br>
  </ul><br>
  <br>
  <a name="npmjsattribut" id="npmjsattribut"></a><b>Attributes</b>
  <ul>
    <li>disable - Deaktiviert das Device
    </li>
    <li>upgradeListReading - fügt die Upgrade Liste als ein zusäiches Reading im JSON Format ein.
    </li>
    <li>npmglobal - wechselt zwischen Global- und Benutzer-Installation. Standard ist 1=global
    </li>
    <li>disabledForIntervals - Deaktiviert das Device für eine bestimmte Zeit (13:00-18:30 or 13:00-18:30 22:00-23:00)
    </li>
  </ul>
</ul>

=end html_DE

=cut
