# $Id$
# 93_InfluxDBLogger.pm
#
package main;

use strict;
use warnings;
use HttpUtils;

my $total_writes_name = "total_writes";
my $succeeded_writes_name = "succeeded_writes";
my $failed_writes_name = "failed_writes";
my $dropped_writes_name = "dropped_writes";
my $droppeed_writes_last_message_name = "dropped_writes_last_message";
my $failed_writes_last_error_name = "failed_writes_last_error";

# FHEM Modulfunktionen

sub InfluxDBLogger_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}    = "InfluxDBLogger_Define";
    $hash->{NotifyFn} = "InfluxDBLogger_Notify";
    $hash->{SetFn} = "InfluxDBLogger_Set";
    $hash->{RenameFn} = "InfluxDBLogger_Rename";
    $hash->{AttrList} = "disable:1,0 security:basic_auth,none,token username readingInclude readingExclude conversions deviceTagName measurement tags fields";
    Log3 undef, 2, "InfluxDBLogger: Initialized new";
}

sub InfluxDBLogger_Define($$) {
    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};

    my @a = split("[ \t][ \t]*", $def);

    return "Usage: define devname InfluxDBLogger [http|https]://IP_or_Hostname:port dbname devspec" if (scalar(@a) < 4);

    $hash->{URL} = $a[2];
    $hash->{DATABASE} = $a[3];
    $hash->{NOTIFYDEV} = $a[4];

    if ( "THIS_WONT_USUALY_MATCH" =~ /$hash->{NOTIFYDEV}/ && $init_done) {
        $attr{$name}{disable} = "1";
        Log3 $name, 2, "InfluxDBLogger: [$name] You specified a very loose device spec. To avoid a lot of events in your influx database this module is disabled on default. You might want to use the readingRegEx-attribute and enable the device afterwards.";
    }

    Log3 $name, 3, "InfluxDBLogger: [$name] defined with server ".$hash->{URL}." database ".$hash->{DATABASE}." notifydev ".$hash->{NOTIFYDEV};
}

sub InfluxDBLogger_Notify($$)
{
	my ($own_hash, $dev_hash) = @_;
	my $name = $own_hash->{NAME}; # own name / hash

	return "" if(IsDisabled($name)); # Return without any further action if the module is disabled
    return "" if(!$init_done);

	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash, 1);

    return "" if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}));
    return "" if($own_hash->{TYPE} eq $dev_hash->{TYPE}); # avoid endless loops from logger to logger

    Log3 $name, 4, "InfluxDBLogger: [$name] notified from device $devName";
    my %map = InfluxDBLogger_BuildMap($own_hash, $dev_hash, $events);
    my @incompatible = ();
    my ($data,$rows) = InfluxDBLogger_BuildData($own_hash,$dev_hash,\%map,\@incompatible);

    InfluxDBLogger_Send($own_hash,$data,$rows);

    if (scalar(@incompatible) > 0 ) {
        InfluxDBLogger_DroppedIncompatibleValues($own_hash,$name,@incompatible);
    }
}

sub InfluxDBLogger_Send($$$)
{
    my ($own_hash, $data, $rows) = @_;
    my $name = $own_hash->{NAME};

    if ( $data ne "" ) {
        my $total_writes = ReadingsVal($name,$total_writes_name,0);
        $total_writes+=$rows;
        my $rv = readingsSingleUpdate($own_hash, $total_writes_name, $total_writes, 1);
        InfluxDBLogger_UpdateState($own_hash,$name);

        my $reqpar = {
                    url => InfluxDBLogger_BuildUrl($own_hash),
                    method => "POST",
                    data => $data,
                    hideurl => 1,
                    hash => $own_hash,
                    callback => \&InfluxDBLogger_HttpCallback
        };
        InfluxDBLogger_AddSecurity($own_hash,$name,$reqpar);

        Log3 $name, 4, "InfluxDBLogger: [$name] Sending data ".$reqpar->{data}." to ".$reqpar->{url};
        HttpUtils_NonblockingGet($reqpar);
    }
}

sub InfluxDBLogger_AddSecurity($$$)
{
    my ($own_hash, $name, $reqpar) = @_;

    my $security = AttrVal($name, "security", "");
    if ( $security eq "basic_auth" )
    {
        my $user = AttrVal($name, "username", undef);
        $reqpar->{user} =  $user;
        $reqpar->{pwd} = InfluxDBLogger_GetPassword($own_hash,$name);
    }
    elsif ( $security eq "token")
    {
        my $token = InfluxDBLogger_ReadSecret($own_hash,$name,"token");
        $reqpar->{header} = { "Authorization" => "Token " . $token};
    }
}

sub InfluxDBLogger_BuildMap($$$)
{
    my ($own_hash, $dev_hash, $events) = @_;
    my $name = $own_hash->{NAME};
    my $devName = $dev_hash->{NAME};
    my %map = ();

    foreach my $event (@{$events}) {
        $event = "" if(!defined($event));
        my $readingInclude = AttrVal($name, "readingInclude", undef);
        my $readingExclude = AttrVal($name, "readingExclude", undef);
        if ( (!defined($readingInclude) || $event =~ /$readingInclude/) && (!defined($readingExclude) || !($event =~ /$readingExclude/)) ) {
            Log3 $name, 4, "InfluxDBLogger: [$name] notified from device $devName about $event";
            InfluxDBLogger_Map($own_hash, $dev_hash, $event, \%map);
        }
    }

    return %map;
}

sub InfluxDBLogger_BuildData($$$$)
{
    my ($own_hash, $dev_hash, $map, $incompatible) = @_;
    my $name = $own_hash->{NAME};
    my $data = "";

    my $rows = 0;
    my %m = %{$map};
    my %measuremnts = ();
    foreach my $device (keys %m) {
        my $readings = $m{$device};
        my %r = %{$readings};
        foreach my $reading (keys %r) {
            my $value_map = $r{$reading};
            my $value = $value_map->{"value"};
            my $numeric = $value_map->{"numeric"};
            if ($numeric) {
                my ($measurementAndTagSet,$fieldset) = InfluxDBLogger_BuildDataDynamic($own_hash, $dev_hash, $device, $reading, $value);
                if (defined $measuremnts{$measurementAndTagSet}) {
                  $measuremnts{$measurementAndTagSet} .= "," . $fieldset;
                } else {
                  $measuremnts{$measurementAndTagSet} = $fieldset;
                }
                $rows++;
            }
            else {
                push(@{$incompatible}, $device ." ". $reading . " " . $value);
            }
        }
    }
    foreach my $measurementAndTagSet ( keys %measuremnts ) {
        $data .= $measurementAndTagSet . " " . $measuremnts{$measurementAndTagSet} . "\n";
    }

    return $data, $rows;
}

sub InfluxDBLogger_BuildDataDynamic($$$$$)
{
    my ($hash, $dev_hash, $device, $reading, $value) = @_;
    my $name = $hash->{NAME};

    my $measurement =  InfluxDBLogger_GetMeasurement($hash, $dev_hash, $device, $reading, $value);
    my $tag_set = InfluxDBLogger_GetTagSet($hash, $dev_hash, $device, $reading, $value);
    my $field_set = InfluxDBLogger_GetFieldSet($hash, $dev_hash, $device, $reading, $value);

    my $measurementAndTagSet = defined $tag_set ? $measurement . "," . $tag_set : $measurement;
    return ($measurementAndTagSet,$field_set);
}

sub InfluxDBLogger_GetMeasurement($$$)
{
    my ($hash, $dev_hash, $device, $reading, $value) = @_;
    my $name = $hash->{NAME};

    my $measurement =  AttrVal($name, "measurement", $reading);
    $measurement =~ s/\$DEVICE/$device/ei;
    $measurement =~ s/\$READINGNAME/$reading/ei;

    return $measurement;
}

sub InfluxDBLogger_GetTagSet($$$)
{
    my ($hash, $dev_hash, $device, $reading, $value) = @_;
    my $name = $hash->{NAME};
    my $tags_set = AttrVal($name, "tags", undef);
    if (defined $tags_set) {
        if ( $tags_set eq "-" ) {
            $tags_set = undef;
        } else {
            $tags_set =~ s/\{(.*)\}/eval($1) /ei;
            $tags_set =~ s/\$DEVICE/$device /ei;
        }
    } else {
      $tags_set = AttrVal($name, "deviceTagName", "site_name")."=".$device;
    }

    return $tags_set;
}

sub InfluxDBLogger_GetFieldSet($$$)
{
    my ($hash, $dev_hash, $device, $reading, $value) = @_;
    my $name = $hash->{NAME};

    my $field_set =  AttrVal($name, "fields", "value=\$READINGVALUE");
    $field_set =~ s/\$READINGNAME/$reading/ei;
    $field_set =~ s/\$READINGVALUE/$value/ei;

    return $field_set;
}

sub InfluxDBLogger_BuildDataClassic($$$)
{
    my ($hash, $dev_hash, $device, $reading, $value) = @_;
    my $name = $hash->{NAME};

    my $measurement = $reading;
    my $tag_set = AttrVal($name, "deviceTagName", "site_name")."=".$device;
    my $field_set = "value=".$value;

    return "$measurement,$tag_set $field_set";
}

sub InfluxDBLogger_BuildUrl($)
{
    my ($hash) = @_;
    return $hash->{URL}."/write?db=".urlEncode($hash->{DATABASE});
}

sub InfluxDBLogger_Map($$$$)
{
    my ($hash, $dev_hash, $event, $map) = @_;
    my $name = $hash->{NAME};
    my $deviceName = $dev_hash->{NAME};
    my @readingAndValue = split(":[ \t]*", $event);
    my $readingName = $readingAndValue[0];
    my $readingValue = $readingAndValue[1];

    my $conversions = AttrVal($name, "conversions", undef);
    if ( defined($conversions)) {
        my @conversions = split(",", $conversions);
        foreach ( @conversions ) {
            my @ab = split("=", $_);
            $readingValue =~ s/$ab[0]/eval($ab[1])/ei;
        }
    }

    $map->{$deviceName}->{$readingName}->{"value"} = $readingValue;
    $map->{$deviceName}->{$readingName}->{"numeric"} = $readingValue =~ /^[0-9,.E-]+$/;
}
sub InfluxDBLogger_HttpCallback($$$)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "") {
        InfluxDBLogger_HttpCallback_Error($hash,$name,$err);
    }
    else {
        my $header = $param->{httpheader};
        my $influx_db_error = undef;
        my $http_error = undef;
        while ($header =~ /X-Influxdb-Error:\s*(.*+)/g) {
            $influx_db_error = $1;
        }
        while ($header =~ /HTTP\/1\.0\s*([4|5]\d\d\s*.*+)/g) {
            $http_error = $1;
        }
        if ( defined($influx_db_error) )
        {
            InfluxDBLogger_HttpCallback_Error($hash,$name,$influx_db_error);
        }
        elsif ( defined($http_error) )
        {
            InfluxDBLogger_HttpCallback_Error($hash,$name,$http_error);
        }
        else
        {
            my $succeeded_writes = ReadingsVal($name,$succeeded_writes_name,0);
            $succeeded_writes++;
            my $rv = readingsSingleUpdate($hash, $succeeded_writes_name, $succeeded_writes, 1);
            Log3 $name, 4, "InfluxDBLogger: [$name] HTTP Succeeded ".$rv;
        }
    }
    InfluxDBLogger_UpdateState($hash,$name);
}
sub InfluxDBLogger_UpdateState($$)
{
    my ($hash, $name) = @_;
    my $new_state = "Statistics: t=".ReadingsVal($name,$total_writes_name,0)." s=".ReadingsVal($name,$succeeded_writes_name,0)." f=".ReadingsVal($name,$failed_writes_name,0);
    readingsSingleUpdate($hash,"state",$new_state,1);
}


sub InfluxDBLogger_HttpCallback_Error($$$)
{
    my ($hash, $name, $err) = @_;


    Log3 $name, 1,"InfluxDBLogger: [$name] Error = $err";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, $failed_writes_last_error_name, $err);

    my $failed_writes = ReadingsVal($name,$failed_writes_name,0);
    $failed_writes++;
    readingsBulkUpdate($hash, $failed_writes_name, $failed_writes);

    readingsEndUpdate($hash, 1);
}

sub InfluxDBLogger_DroppedIncompatibleValues($$@)
{
    my ($hash, $name, @warnings) = @_;

    readingsBeginUpdate($hash);
    my $dropped_writes = ReadingsVal($name,$dropped_writes_name,0);
    my $warn = "";
    foreach (@warnings) {
        $warn = $_;
        Log3 $name, 4, "InfluxDBLogger: [$name] Warning, incompatible non numeric value: $warn";
    }
    readingsBulkUpdate($hash, $droppeed_writes_last_message_name, $warn);

    $dropped_writes+=scalar(@warnings);
    readingsBulkUpdate($hash, $dropped_writes_name, $dropped_writes);

    readingsEndUpdate($hash, 1);
}

sub InfluxDBLogger_Set($$@)
{
    my ( $hash, $name, $cmd, @args ) = @_;
    Log3 $name, 5, "InfluxDBLogger: [$name] set $cmd";

    if ( lc $cmd eq 'password' ) {
        my $pwd = $args[0];
        InfluxDBLogger_StoreSecret($hash, $name,"passwd", $pwd);
        return (undef,1);
    }
    elsif ( lc $cmd eq 'token' ) {
        my $token = $args[0];
        InfluxDBLogger_StoreSecret($hash, $name,"token", $token);
        return (undef,1);
    }
    elsif ( lc $cmd eq 'resetstatistics' ) {
        InfluxDBLogger_ResetStatistics($hash, $name);
        return (undef,1);
    }
    else {
        return "Unknown argument $cmd, choose one of resetStatistics:noArg password token";
    }
}

sub InfluxDBLogger_ResetStatistics($)
{
    my ( $hash, $name ) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, $total_writes_name, 0);
    readingsBulkUpdate($hash, $succeeded_writes_name, 0);
    readingsBulkUpdate($hash, $failed_writes_name, 0);
    readingsBulkUpdate($hash, $dropped_writes_name, 0);
    readingsBulkUpdate($hash, $droppeed_writes_last_message_name, "<none>");
    readingsBulkUpdate($hash, $failed_writes_last_error_name, "<none>");
    readingsEndUpdate($hash, 1);

    InfluxDBLogger_UpdateState($hash, $name);
}

sub InfluxDBLogger_IsBasicAuth($)
{
    my $name = shift;
    return AttrVal($name, "security", "") eq "basic_auth";
}

sub InfluxDBLogger_GetPassword()
{
    my $hash = shift;
    my $name = shift;

    if( InfluxDBLogger_IsBasicAuth($name) )
    {
        return InfluxDBLogger_ReadSecret($hash,$name,"passwd");
    }
    else
    {
        return undef;
    }
}

sub InfluxDBLogger_StoreSecret {
    my $hash     = shift;
    my $name     = shift;
    my $ref      = shift;
    my $password = shift;

    my $index   = $hash->{TYPE} . "_" . $name . "_" . $ref;
    my $key     = getUniqueId() . $index;
    my $enc_pwd = "";

    $hash->{$ref} = undef;

    if ( eval "use Digest::MD5;1" ) {
        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
    }

    for my $char ( split //, $password ) {
        my $encode = chop($key);
        $enc_pwd .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }
    Log3 $name, 5, "InfluxDBLogger: [$name] storing new $ref";
    my $err = setKeyValue( $index, $enc_pwd );
    return "error while saving the $ref - $err" if ( defined($err) );

    $hash->{$ref} = "saved";

    return "$ref successfully saved";
}

sub InfluxDBLogger_ReadSecret {
    my $hash = shift;
    my $name = shift;
    my $ref  = shift;

    my $index   = $hash->{TYPE} . "_" . $name . "_" . $ref;
    my $key   = getUniqueId() . $index;
    my ( $password, $err );

    Log3 $name, 4, "InfluxDBLogger [$name] - Read $ref from file";

    ( $err, $password ) = getKeyValue($index);

    if ( defined($err) ) {

        Log3 $name, 3, "InfluxDBLogger [$name] - unable to read $ref from file: $err";
        return undef;

    }

    if ( defined($password) ) {
        if ( eval "use Digest::MD5;1" ) {

            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = '';

        for my $char ( map { pack( 'C', hex($_) ) } ( $password =~ /(..)/g ) ) {

            my $decode = chop($key);
            $dec_pwd .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }

        return $dec_pwd;

    }
    else {

        Log3 $name, 3, "InfluxDBLogger [$name] - No $ref in file";
        return undef;
    }

    return;
}

sub InfluxDBLogger_Rename($$) {
   my ( $new_name, $old_name) = @_;

    my $hash = $defs{$new_name};

    InfluxDBLogger_StorePassword( $hash, $new_name, InfluxDBLogger_ReadPassword( $hash, $old_name ) );
    setKeyValue( $hash->{TYPE} . "_" . $old_name . "_passwd", undef );

    return;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item helper
=item summary Logs numeric readings into InfluxDB time-series databases
=item summary_DE Schreibt numerische Readings in eine InfluxDB Zeitreihendatenbank

=begin html

<a name="InfluxDBLogger"></a>
<h3>InfluxDBLogger</h3>
<ul>
   Module for logging to InfluxDB time-series databases.
   According to the <i>InfluxDB terminology</i>, here is the default mapping, which can be changed via attributes:
   <ul>
        <li>A <i>measurement</i> will be created for each reading name.</li>
        <li>A <i>tag</i> called 'site_name' will be used for each device</li>
        <li>A <i>field</i> called 'value' will be used for each reading value</li>
   </ul>
    To use this module with InfluxDB 2, the buckets needs to be mapped to databases. <a href="https://docs.influxdata.com/influxdb/v2.0/query-data/influxql/#map-unmapped-buckets">link</a>

   <a name="InfluxDBLogger_Define"></a>
   <h4>Define</h4>
	<ul>
		<code>define &lt;name&gt; InfluxDBLogger [http|https]://IP_or_Hostname:port dbname devspec</code>
		<br /><br />For details about devspec see <a href="fhem/docs/commandref.html#devspec">here</a>. If you use a wildcard devspec, the device will be disabled on default in order to let you specify a readings-regex to reduce the log-amount.<br />
	</ul>

   <a name="InfluxDBLogger_Set"></a>
   <h4>Set</h4>
   <ul>
        <li><b>password</b>
        <code>set &lt;name&gt; password &lt;password&gt;</code><br />
        Securly stores the password for basic authentication. It is only used if security attribute is set to basic_auth.
        </li>
        <li><b>token</b>
        <code>set &lt;name&gt; token &lt;token&gt;</code><br />
        Securly stores the token for token based authentication. It is only used if security attribute is set to token.
        </li>
        <li><b>resetStatistics</b>
        <code>set &lt;name&gt; resetStatistics</code><br />
        Sets all statistical counters to zero and removes the last error message.
        </li>
   </ul>

    <a name="InfluxDBLogger_Attr"></a>
    <h4>Attributes</h4>
    <ul>
        <li><b>disable</b> <code>attr &lt;name&gt; disable [0|1]</code><br />
           If disabled no readings will be written to the database
        </li>
        <li><b>security</b> <code>attr &lt;name&gt; security [basic_auth|none|token]</code><br />
           If basic_auth is used, you have to define an user attribute and set a password<br>
           If token is used, you have to set a token<br>
        </li>
        <li><b>username</b> <code>attr &lt;name&gt; username &lt;username&gt;</code><br />
            Only used if security attribute is set to basic_auth<br>
        </li>
        <li><b>readingInclude</b> <code>attr &lt;name&gt; readingInclude &lt;regex&gt;</code><br />
            Only reading events that match the regex will be logged(inclusive). Note that readings usually have the format: 'state: on'<br></li>
        <li><b>readingExclude</b> <code>attr &lt;name&gt; readingInclude &lt;regex&gt;</code><br />
            Only reading events that do not match the regex will be logged(inclusive). Note that readings usually have the format: 'state: on'<br></li>
        <li><b>deviceTagName</b> <code>attr &lt;name&gt; deviceTagName &lt;deviceTagName&gt;</code><br />
            This will be the name of the device tag. default is 'site_name'
        </li>
        <li><b>conversions</b> <code>attr &lt;name&gt; conversions &lt;conv1,conv2&gt;</code><br />
            Comma seperated list of replacements e.g. open=1,closed=0,tilted=2 or true|on|yes=1,false|off|no=0
        </li>
        <li><b>measurement</b> <code>attr &lt;name&gt; measurement &lt;string&gt;</code><br />
            Name of the measurement to use. This can be any string.
            The keyword $DEVICE will be replaced by the device-name.
            The keyword $READINGNAME will be replaced by the reading-name
            Default is $READINGNAME.
        </li>
        <li><b>tags</b> <code>attr &lt;name&gt; tags &lt;x,y&gt;</code><br />
            This is the list of tags that will be sent to InfluxDB. The keyword $DEVICE will be replaced by the device-name.
            If this attribute is set it will override the attribute deviceTagName. If the attribute is set to "-"
            no tags will be written (useful if measurement is set to $DEVICE and fields to $READINGNAME=$READINGVALUE)
            Default is site_name=$DEVICE.
            Perl-Expression can be used in curly braces to evaluate the alias-attribute as a tag for example. $name, $device, $reading, $value are available as variables.
            attr influx tags device={AttrVal($device, "alias", "fallback")}
        </li>
        <li><b>fields</b> <code>attr &lt;name&gt; fields &lt;val=$READINGVALUE&gt;</code><br />
            This is the list of fields that will be sent to InfluxDB.
            The keyword $READINGNAME will be replaced by the reading-name.
            The keyword $READINGVALUE will be replaced by the reading-value.
            Default is value=$READINGVALUE.
        </li>
    </ul>

    <a name="InfluxDBLogger_Readings"></a>
    <h4>Readings</h4>
    <ul>
        <li><b>total_writes</b><br />
            Total number of initiated log events. These are the attempts to write, not the completed ones.
        </li>
        <li><b>succeeded_writes</b><br />
            Total number of successfully completed log events. These are the writes that you will find in the database.
        </li>
        <li><b>failed_writes</b><br />
            Total number of failed log events. These are failed due to some error which is captured in the log and in the reading failed_writes_last_error
        </li>
        <li><b>failed_writes_last_error</b><br />
            The last captured error. This is very useful for systematic problems, like wrong DNS or a wrong port, aso.
        </li>
        <li><b>dropped_writes</b><br />
            Total number of dropped writes due to non numeric value. See conversions to fix.
        </li>
        <li><b>state</b><br />
            Statistics: t=total_writes s=succeeded_writes f=failed_writes
        </li>
    </ul>
</ul>

=end html

=begin html_DE

<a name="InfluxDBLogger"></a>
<h3>InfluxDBLogger</h3>
<ul>
   Modul zum Loggen in eine InfluxDB Zeitreihendatenbank
   Entsprechend der <i>InfluxDB Terminologie</i>, hier die Standardzuordnung, die mittels Attribute frei verändert werden kann:
   <ul>
        <li>Ein <i>measurement</i> wird für jeden reading namen erzeugt.</li>
        <li>Ein <i>tag</i> namens 'site_name' wird für jedes device verwendet</li>
        <li>Ein <i>field</i> namens 'value' wird für die reading Werte genutzt</li>
   </ul>
   Um das Modul mit InfluxDB 2 zu nutzen, müssen die Buckets auf Datenbanken gemapped werden. <a href="https://docs.influxdata.com/influxdb/v2.0/query-data/influxql/#map-unmapped-buckets">link</a>

   <a name="InfluxDBLogger_Define"></a>
   <h4>Define</h4>
	<ul>
		<code>define &lt;name&gt; InfluxDBLogger [http|https]://IP_or_Hostname:port dbname devspec</code>
		<br /><br />Für details zur devspec bitte <a href="fhem/docs/commandref_DE.html#devspec">hier</a> informieren. Wenn eine devspec verwendet wird, die auf ALLE Geräe zutrifft, wird der Logger sich initial erstmal selber abschalten (disable 1). Wenn man eine RegEx für die Readings gesetzt hat, kann disable wieder auf 0 gesetzt werden.<br />
	</ul>

   <a name="InfluxDBLogger_Set"></a>
   <h4>Set</h4>
   <ul>
        <li><b>password</b>
        <code>set &lt;name&gt; password &lt;password&gt;</code><br />
        Speichert das Passwort verschlüsselt für basic authentication. Es wird nur genutzt, wenn das security Attribut auf basic_auth gesetzt wurde.
        </li>
        <li><b>token</b>
        <code>set &lt;name&gt; token &lt;token&gt;</code><br />
        Speichert das Token verschlüsselt für Token Authentification. Es wird nur genutzt, wenn das security Attribut auf token gesetzt wurde.
        </li>
        <li><b>resetStatistics</b>
        <code>set &lt;name&gt; resetStatistics</code><br />
        Setzt alle statistischen Zähler auf 0 und entfernt die letzte Fehlermeldung
        </li>
   </ul>

    <a name="InfluxDBLogger_Attr"></a>
    <h4>Attributes</h4>
    <ul>
        <li><b>disable</b> <code>attr &lt;name&gt; disable [0|1]</code><br />
           Wenn disable 1 ist, werden keine Ereignisse in die Datenbank geschrieben
        </li>
        <li><b>security</b> <code>attr &lt;name&gt; security [basic_auth|none|token]</code><br />
           Wenn basic_auth genutzt wird, muss ein Benutzer per Attribut und ein Passwort per set gesetzt werden<br>
           Wenn token genutzt wird, muss ein token über set gesetzt werden<br>
        </li>
        <li><b>username</b> <code>attr &lt;name&gt; username &lt;username&gt;</code><br />
            Wird nur genutzt wenn das security Attribut auf basic_auth gesetzt wurde<br>
        </li>
        <li><b>readingInclude</b> <code>attr &lt;name&gt; readingInclude &lt;regex&gt;</code><br />
            nur Ereignisse die zutreffen werden geschrieben(inklusiv). Hinweis - das Format eines Ereignisses sieht so aus: 'state: on'<br></li>
        <li><b>readingExclude</b> <code>attr &lt;name&gt; readingExclude &lt;regex&gt;</code><br />
            nur Ereignisse die nicht zutreffen werden geschrieben(inklusiv). Hinweis - das Format eines Ereignisses sieht so aus: 'state: on'<br></li>
        <li><b>deviceTagName</b> <code>attr &lt;name&gt; deviceTagName &lt;deviceTagName&gt;</code><br />
            das ist der Name des tags wo der Gerätename gespeichert wird. Standard ist 'site_name'
        </li>
        <li><b>conversions</b> <code>attr &lt;name&gt; conversions &lt;conv1,conv2&gt;</code><br />
            Kommagetrennte Liste von Ersetzungen e.g. open=1,closed=0,tilted=2 oder true|on|yes=1,false|off|no=0
        </li>
        <li><b>measurement</b> <code>attr &lt;name&gt; measurement &lt;string&gt;</code><br />
            Name des zu verwendenen measurements. Dies kann ein freie Zeichenkette sein.
            Das Schlüsselwort $DEVICE wird ersetzt durch den Gerätenamen.
            Das Schlüsselwort $READINGNAME wird ersetzt durch den Readingnamen.
            Standard ist $READINGNAME.
        </li>
        <li><b>tags</b> <code>attr &lt;name&gt; tags &lt;x,y&gt;</code><br />
            Dies ist the Liste der tags die an InfluxDB mitgesendet werden. Das Schlüsselwort $DEVICE wird ersetzt durch den Gerätenamen.
            Wenn dieses Attribut gesetzt ist wird das Attribut deviceTagName nicht berücksichtigt.
            Standard ist site_name=$DEVICE. Um keine Tags zu schreiben (insbesondere, weil measurement auf $DEVICE und
            fields auf $READINGNAME=$READINGVALUE steht) bitte ein "-" eintragen.
            Es können Perl-Ausdrücke in geschweiften Klammern verwendet werden um z.B. Attribute als tag zu nutzen. $name, $device, $reading, $value stehen dabei als Variable zur Verfügung.
            attr influx tags device={AttrVal($device, "alias", "fallback")}
        </li>
        <li><b>fields</b> <code>attr &lt;name&gt; fields &lt;val=$READINGVALUE&gt;</code><br />
            Dies ist the Liste der fields die an InfluxDB gesendet werden.
             Das Schlüsselwort $READINGNAME wird ersetzt durch den Readingnamen.
             Das Schlüsselwort $READINGVALUE wird ersetzt durch den Readingwert.
             Standard ist value=$READINGVALUE.
        </li>
    </ul>

    <a name="InfluxDBLogger_Readings"></a>
    <h4>Readings</h4>
    <ul>
        <li><b>total_writes</b><br />
            Anzahl der versuchten Schreibvorgänge. Dies sind nicht die Abgeschlossenen.
        </li>
        <li><b>succeeded_writes</b><br />
            Anzahl der erfolgreich geschriebenen Ereignisse. Dies sind die Ereignisse die man in der Datenbank finde wird.
        </li>
        <li><b>failed_writes</b><br />
            Anzahl der fehlgeschlagenen Ereignisse. Die letzte Fehlermeldung findet man im Reading failed_writes_last_error
        </li>
        <li><b>failed_writes_last_error</b><br />
            Die Fehlermeldung, was recht nützlich ist für systematische Fehler, wie falsche DNS Einträge usw.
        </li>
        <li><b>dropped_writes</b><br />
            Anzahl von nicht getätigten Schreibvorgängen aufgrund da nicht numerisch. Siehe conversions um es zu beheben.
        </li>
        <li><b>state</b><br />
            Statistics: t=total_writes s=succeeded_writes f=failed_writes
        </li>
    </ul>
</ul>

=end html_DE

# Ende der Commandref
=cut