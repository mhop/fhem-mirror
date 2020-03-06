# $Id$
##############################################################################
#
#      98_DSBMobile.pm
#     An FHEM Perl module that retrieves information from DSBMobile
#
#     Copyright by KernSani
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#     Changelog:
#     20.02.2020    Parsing of grouped classes
##############################################################################
##############################################################################
#     Todo:
#
#
##############################################################################

package main;

use strict;
use warnings;
use HttpUtils;
use Data::Dumper;
use FHEM::Meta;

my $missingModul = "";

#eval "use Blocking;1" or $missingModul .= "Blocking ";
#eval "use UUID::Random;1"                      or $missingModul .= "install UUID::Random ";
eval "use IO::Compress::Gzip qw(gzip);1"           or $missingModul .= "IO::Compress::Gzip ";
eval "use IO::Uncompress::Gunzip qw(gunzip);1"     or $missingModul .= "IO::Compress::Gunzip ";
eval "use MIME::Base64;1"                          or $missingModul .= "MIME::Base64 ";
eval "use HTML::TableExtract;1"                    or $missingModul .= "HTML::TableExtract ";
eval "use HTML::TreeBuilder;1"                     or $missingModul .= "HTML::TreeBuilder ";
eval "use JSON::XS qw (encode_json decode_json);1" or $missingModul .= "JSON::XS ";

#####################################
sub DSBMobile_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}   = "DSBMobile_Define";
    $hash->{UndefFn} = "DSBMobile_Undefine";
    $hash->{GetFn}   = "DSBMobile_Get";

    #$hash->{SetFn}   = "DSBMobile_Set";
    $hash->{AttrFn} = "DSBMobile_Attr";

    my @DSBMobile_attr
        = (   "dsb_user "
            . "dsb_password "
            . "dsb_class "
            . "dsb_interval "
            . "dsb_classReading "
            . "dsb_outputFormat:textField-long " );
    $hash->{AttrList} = join( " ", @DSBMobile_attr ) . " " . $readingFnAttributes;
    return FHEM::Meta::InitMod( __FILE__, $hash );
}

#####################################
sub DSBMobile_Define($@) {
    my ( $hash, $def ) = @_;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    my @a = split( "[ \t][ \t]*", $def );

    my $usage = "syntax: define <name> DSBMobile";
    return "Cannot define device. Please install perl modules $missingModul."
        if ($missingModul);
    my ( $name, $type ) = @a;
    if ( int(@a) != 2 ) {
        return $usage;
    }

    Log3 $name, 3, "[$name] DSBMobile defined $name";

    $hash->{NAME} = $name;

    #start timer
    if ( AttrNum( $name, "dsb_interval", 0 ) > 0 && $init_done ) {
        my $next = int( gettimeofday() ) + 1;
        InternalTimer( $next, 'DSBMobile_ProcessTimer', $hash, 0 );
    }
}
###################################
sub DSBMobile_Undefine($$) {
    my ( $hash, $name ) = @_;
    RemoveInternalTimer($hash);
    return undef;
}
###################################
sub DSBMobile_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};               # own name / hash
    my $events = deviceEvents( $dev, 1 );

    return ""
        if ( IsDisabled($name) );           # Return without any further action if the module is disabled
    return if ( !grep( m/^INITIALIZED|REREADCFG$/, @{$events} ) );

    my $next = int( gettimeofday() ) + 1;
    InternalTimer( $next, 'DSBMobile_ProcessTimer', $hash, 0 );
}
###################################
sub DSBMobile_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

}

#####################################
sub DSBMobile_Get($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $ret   = "";
    my $usage = 'Unknown argument $a[1], choose one of timetable:noArg';

    return "\"get $name\" needs at least one argument"
        unless ( defined( $a[1] ) );

    if ( $a[1] eq "timetable" ) {
        $hash->{helper}{forceRead} = 1;
        return DSBMobile_query($hash);
    }

    # return usage hint
    else {
        return $usage;
    }
    return undef;
}

#####################################
sub DSBMobile_query($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 5, "[$name] Getting data";

    my $uuid = DSBMobileUUID();
    my $date = strftime "%Y-%m-%dT%H:%M:%S.999+0100", localtime time;
    my $user = AttrVal( $name, "dsb_user", "" );
    my $pw   = AttrVal( $name, "dsb_password", "" );

    if ( $user eq "" or $pw eq "" ) {
        return "User and password have to be maintained in the attributes";
    }

    my %arg = (
        "UserId"     => $user,
        "UserPw"     => $pw,
        "Language"   => "de",
        "Device"     => "Nexus 4",
        "AppId"      => $uuid,
        "appversion" => "2.5.9",
        "OsVersion"  => "27 8.1.0",
        "PushId"     => "",
        "BundleId"   => "de.heinekingmedia.dsbmobile",
        "Date"       => $date,
        "LastUpdate" => $date
    );

    my $json = encode_json( \%arg );
    Log3 $name, 5, "[$name] Arguments (in json) to encode" . Dumper($json);
    my $zip;
    IO::Compress::Gzip::gzip \$json => \$zip;
    my $b64  = encode_base64($zip);
    my $body = '{"req": {"Data": "' . $b64 . '","DataType": 1}}';

    my $header = {
        'Host'            => 'app.dsbcontrol.de',
        'Content-Type'    => 'application/json; charset=utf-8',
        'User-Agent'      => 'DSBmobile/9759 (iPhone; iOS 13.3; Scale/3.00)',
        'Connection'      => 'keep-alive',
        'Accept'          => '*/*',
        'Accept-Language' => 'de-DE;q=1, en-DE;q=0.9',
        'Accept-Encoding' => 'gzip, deflate',
    };
    my $param = {
        header   => $header,
        url      => 'https://www.dsbmobile.de/JsonHandler.ashx/GetData',
        method   => "POST",
        hash     => $hash,
        data     => $body,
        callback => \&DSBMobile_getDataCallback
    };
    Log3 $name, 5, "[$name] 1st nonblocking HTTP Call starting";
    HttpUtils_NonblockingGet($param);
    return undef;
}

#####################################
sub DSBMobile_getDataCallback($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err ne "" ) {
        Log3 $name, 3, "[$name] Error while requesting " . $param->{url} . " - $err";
        readingsSingleUpdate( $hash, "error", $err, 0 );
        return undef;
    }

    Log3 $name, 5, "[$name] 1st nonblocking HTTP Call returning";
    Log3 $name, 5, "[$name] GetData - received $data";
    my $j   = decode_json($data);
    my $d64 = decode_base64( $j->{d} );
    my $json;
    IO::Uncompress::Gunzip::gunzip \$d64 => \$json;
    $json = latin1ToUtf8($json);
    my $res = decode_json($json);
    if ( $res->{Resultcode} == 1 ) {
        readingsSingleUpdate( $hash, "error", $res->{ResultStatusInfo}, 0 );
        return undef;
    }
    Log3 $name, 5, "[$name] JSON received: " . Dumper($res);

    # todo - add error handling
    my $url;
    my $udate;
    my $test = $res->{ResultMenuItems}[0]->{Childs};
    my @aus;
    my %ttpages = ();    # hash to get unique urls
    foreach my $c (@$test) {

        #if ($c->{Title} eq "Pläne") {

        #$ret .= Dumper($c->{root}{Childs}[0]->{Childs}[0]->{Detail});
        foreach my $topic ($c) {
            if ( $c->{MethodName} eq "timetable" ) {
                my $p = $topic->{Root}{Childs};
                for my $tt (@$p) {
                    my $subtt = $tt->{Childs};
                    for my $stt (@$subtt) {
                        $url           = $stt->{Detail};
                        $udate         = $stt->{Date};
                        $ttpages{$url} = 1;
                        Log3 $name, 5, "[$name] found url $url";
                    }
                }
            }
            if ( $c->{MethodName} eq "tiles" ) {
                my $d = $topic->{Root}{Childs};

                for my $tile (@$d) {
                    my %au = (
                        title => $tile->{Title},
                        url   => $tile->{Childs}[0]->{Detail},
                        date  => $tile->{Childs}[0]->{Date}
                    );
                    push( @aus, \%au );
                }
            }
        }
    }

    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst )
        = localtime( gettimeofday() );
    $month++;
    $year += 1900;
    my $today = sprintf( '%04d-%02d-%02d %02d:%02d', $year, $month, $mday, $hour, $min );

    my ( $d, $m, $y, $h, $mi ) = $udate =~ /^([0-9]{2})\.([0-9]{2})\.([0-9]{4})\s([0-9]{2}):([0-9]{2})/;
    $udate = sprintf( '%04d-%02d-%02d %02d:%02d', $y, $m, $d, $h, $mi );

    my $lastCheck = ReadingsVal( $name, "lastCheck", "2000-01-01 00:00" );
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "lastTTUpdate", $udate );
    readingsBulkUpdate( $hash, "lastCheck",    $today );
    readingsBulkUpdate( $hash, ".overview",    $res );
    readingsEndUpdate( $hash, 1 );

    if ( time_str2num( $udate . ":00" ) < time_str2num( $lastCheck . ":00" ) ) {
        Log3 $name, 4, "[$name] Last update from $udate, now it's $today. Quitting." unless $hash->{helper}{forceRead};
        return undef unless $hash->{helper}{forceRead};
    }
    delete $hash->{helper}{forceRead};

    my $i = 0;
    CommandDeleteReading( undef, $name . " i.*" );
    readingsBeginUpdate($hash);
    foreach my $line (@aus) {
        my $reading = "i" . $i . "_";
        my %line    = %{$line};
        foreach my $key ( keys %line ) {
            my $val = %$line{$key};
            $val = "-" if ( !defined $val );
            readingsBulkUpdate( $hash, $reading . $key, $val );
        }
        $i++;
    }
    readingsBulkUpdate( $hash, ".lastAResult", encode_json( \@aus ) );
    readingsEndUpdate( $hash, 1 );

    # build an array from url hash
    my @ttpages = keys %ttpages;

    if ( @ttpages == 1 ) {
        Log3 $name, 4, "[$name] Extracted the url: " . $url;
    }
    else {
        Log3 $name, 4, "[$name] Extracted multiple urls: " . Dumper(@ttpages);
    }
    $hash->{helper}{tturl} = \@ttpages;
    DSBMobile_processTTPages($hash);
    return undef;
}
#####################################
sub DSBMobile_processTTPages($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $ttpage = shift @{ $hash->{helper}{tturl} };
    
    if ($ttpage) {
        Log3 $name, 5, "[$name] processing page " . $ttpage;
        my $nparam = {
            url      => $ttpage,
            method   => "GET",
            hash     => $hash,
            callback => \&DSBMobile_TTpageCallback
        };
        Log3 $name, 5, "[$name] 2nd nonblocking HTTP Call starting for " . $ttpage;

        HttpUtils_NonblockingGet($nparam);
    }
    else {
        delete $hash->{helper}{tturl};
        DSBMobile_getTTCallback($hash);
    }
    return undef;
}
#####################################
sub DSBMobile_TTpageCallback($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, 5, "[$name] 2nd nonblocking HTTP Call returning";
    Log3 $name, 5, "[$name] Received HTML: " . $data;

    if ( $err ne "" ) {
        Log3 $name, 3, "[$name] Error while requesting " . $param->{url} . " - $err";
        readingsSingleUpdate( $hash, "error", $err, 0 );
        return undef;
    }

    $hash->{helper}{ttdata} .= $data;
    DSBMobile_processTTPages($hash);
}

#####################################
sub DSBMobile_getTTCallback($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $data = $hash->{helper}{ttdata};
    delete $hash->{helper}{ttdata};

    $data =~ s/&nbsp;/-/g;
    $data = latin1ToUtf8($data);
    Log3 $name, 4, "[$name] Starting extraction mon_list";

    # Extract the tables
    my $tdata = $data;
    my @tt    = $tdata =~ m/(<table class="mon_list" >(?:(?:\r\n|[\r\n])[^\r\n]+?)*\/table>)/g;

    #my $te = HTML::TableExtract->new( attribs => { class => 'mon_list' } );
    #$te->parse($data);
    my @tabs;
    foreach my $ttab (@tt) {
        my $te = HTML::TableExtract->new( slice_columns => 0, gridmap => 0 );
        $te->parse($ttab);
        push( @tabs, $te->tables() );
    }

    #Log3 $name, 4, "[$name] Extracted Tables". Dumper(@tabs);

    Log3 $name, 4, "[$name] Starting extraction info";

    # Extract the Info of the day
    my $idata = $data;
    my @dinfo = $idata =~ m/(<table class="info" >(?:(?:\r\n|[\r\n])[^\r\n]+?)*\/table>)/g;

    my @itabs;
    foreach my $din (@dinfo) {
        Log3 $name, 5, "[$name] Found info of the Day: " . Dumper($din);
        my $tinfo = HTML::TableExtract->new();
        $tinfo->parse($din);
        push( @itabs, $tinfo->tables() );
    }

    Log3 $name, 4, "[$name] Starting extraction mon_title";

    #my $tree = HTML::TreeBuilder->new();
    #$tree->parse($data);
    #$tree->eof();

    # Let's find the dates first
    #my @e = $tree->look_down( 'class' => 'mon_title' );

    my @e = $data =~ m/class=\"mon_title\">(.*)<\/div>/g;

    my @result;
    my @iresult;

    my $i = 0;

    my $class  = AttrVal( $name, "dsb_classReading", "Klasse_n_" );
    my $filter = AttrVal( $name, "dsb_class",        ".*" );
    my @ch;

    #foreach my $c (@e) {
    foreach my $cn (@e) {
        Log3 $name, 5, "[$name] Processing line #$i";

        #Extract the date
        #my $cn = $c->content();
        #my ( $date, undef ) = split( " ", @$cn[0] );
        my ( $date, undef ) = split( " ", $cn );
        my ( $d, $m, $y ) = split( /\./, $date );
        my $fdate = $y . "-" . sprintf( "%02s", $m ) . "-" . sprintf( "%02s", $d );

        my $t    = $tabs[$i];
        my $info = $itabs[$i];
        $i++;
        my $j     = 0;
        my $group = undef;
        if ($t) {
            foreach my $r ( $t->rows() ) {
                my @f = @$r;

                #create readingnames from first line
                if ( $j == 0 ) {
                    $j++;
                    @ch = map { makeReadingName($_) } @f;
                    next;
                }

                #check if we have a single row (grouping by class)
                if ( !defined( $f[1] ) ) {

                    # create the reading if we didn't have a group before
                    unshift( @ch, makeReadingName($class) ) unless $group;
                    $group = $f[0];
                    next;
                }

                my %tst = ();
                my $k   = 0;

                # Add the group as "class"
                if ($group) {
                    $tst{$class} = $group;
                }

                foreach my $cl (@ch) {
                    next if $group && $class eq $cl;
                    $tst{$cl} = $f[$k];
                    $k++;
                }
                $tst{sdate} = $fdate;

                push( @result, \%tst )
                    if ( defined( $tst{$class} )
                    && $tst{$class} =~ /$filter/ );
            }
        }
        $j = 0;

        if ($info) {
            foreach my $inf ( $info->rows() ) {

                #skip first line
                if ( $j == 0 ) {
                    $j++;
                    next;
                }
                my @f = @$inf;

                my %irow = (
                    sdate => $fdate,
                    topic => $f[0],
                    text  => $f[1]
                );
                push( @iresult, \%irow );
            }
        }
    }

    Log3 $name, 5, "[$name] Extracted Lines " . Dumper(@result);

    CommandDeleteReading( undef, $name . " tt.*" );
    CommandDeleteReading( undef, $name . " ti.*" );

    $i = 0;
    readingsBeginUpdate($hash);
    foreach my $line (@result) {
        my $reading = "tt" . $i . "_";
        my %line    = %{$line};
        foreach my $key ( keys %line ) {
            my $val = %$line{$key};
            $val = "-" if ( !defined $val );
            readingsBulkUpdate( $hash, $reading . $key, $val );
        }
        $i++;
    }
    $i = 0;
    foreach my $line (@iresult) {
        my $reading = "ti" . $i . "_";
        my %line    = %{$line};
        foreach my $key ( keys %line ) {
            readingsBulkUpdate( $hash, $reading . $key, %$line{$key} );
        }
        $i++;
    }

    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst )
        = localtime( gettimeofday() );
    $month++;
    $year += 1900;
    my $today = sprintf( '%04d-%02d-%02d %02d:%02d', $year, $month, $mday, $hour, $min );

    readingsBulkUpdate( $hash, ".lastResult",  encode_json( \@result ) );
    readingsBulkUpdate( $hash, ".lastIResult", encode_json( \@iresult ) );
    readingsBulkUpdate( $hash, ".html",        $data );
    readingsBulkUpdate( $hash, "state",        "ok" );
    readingsBulkUpdate( $hash, "lastSync",     $today );
    readingsBulkUpdate( $hash, "columnNames",  join( ",", @ch ) );
    readingsEndUpdate( $hash, 1 );
    Log3 $name, 5, "[$name] 2nd nonblocking HTTP Call parse done";
    return undef;
}

#####################################
sub DSBMobile_ProcessTimer($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    DSBMobile_query($hash);

    my $now = int( gettimeofday() );
    my $interval = AttrNum( $name, "dsb_interval", 0 );
    if ( $interval > 0 ) {
        my $next = $now + $interval;
        InternalTimer( $next, 'DSBMobile_ProcessTimer', $hash, 0 );
    }

}
###################################
sub DSBMobile_Attr($) {

    my ( $cmd, $name, $aName, $aVal ) = @_;
    my $hash = $defs{$name};
    if ( $cmd eq "set" ) {
        if ( $aName eq "dsb_interval" ) {
            if ( int( $aVal > 0 ) ) {
                my $next = int( gettimeofday() ) + int($aVal);
                InternalTimer( $next, 'DSBMobile_ProcessTimer', $hash, 0 );
            }
            else {
                RemoveInternalTimer($hash);
            }
        }
        if ( $aName eq "dsb_class" or $aName eq "dsb_classReading" ) {
            $hash->{helper}{forceRead} = 1;
        }
    }
    elsif ( $cmd eq "del" ) {
        if ( $aName eq "dsb_interval" ) {
            RemoveInternalTimer($hash);
        }
    }
    return undef;
}
###################################
sub DSBMobile_simpleHTML($;$) {
    my ( $name, $infoDay ) = @_;
    my $dat  = ReadingsVal( $name, ".lastResult",  "" );
    my $idat = ReadingsVal( $name, ".lastIResult", "" );
    my @cn = split( ",", ReadingsVal( $name, "columnNames", "" ) );
    my $classr = ReadingsVal( $name, "dsb_classReading", "Klasse_n_" );
    my $ret = "<table>";

    $dat  = decode_json($dat);
    $idat = decode_json($idat);

    my @data  = @$dat;
    my @idata = @$idat;
    return "no data found" if ( @data == 0 && ( @idata == 0 || !$infoDay ) );

    if ( @data > 0 ) {
        @data = sort { $a->{sdate} cmp $b->{sdate} or $a->{$classr} cmp $b->{$classr} } @data;
    }

    # get today
    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst )
        = localtime( gettimeofday() );
    $month++;
    $year += 1900;
    my $today = sprintf( '%04d-%02d-%02d', $year, $month, $mday );

    # build a sorted array of valid dates
    my %hash = ();
    foreach my $d (@data) {
        $hash{ $d->{sdate} } = 1 if $d->{sdate} ge $today;
    }
    if ($infoDay) {
        foreach my $d (@idata) {
            $hash{ $d->{sdate} } = 1 if $d->{sdate} ge $today;
        }
    }
    my @days = keys %hash;
    @days = sort { $a cmp $b } @days;

    my $date = "";
    my $class;
    my $out = AttrVal( $name, "dsb_outputFormat", undef );

    foreach my $day (@days) {
        my $row   = 0;
        my $class = "even";
        $ret .= "</table><table class='block wide'><tr class='$class'><td><b>" . $day . "</b></td></tr>";
        $row++;
        if ($infoDay) {
            foreach my $iline (@idata) {
                if ( $row % 2 == 0 ) {
                    $class = "even";
                }
                else {
                    $class = "odd";
                }
                $row++;

                if ( $iline->{sdate} eq $day ) {
                    $ret .= "<tr class='$class'><td>" . $iline->{topic} . ": " . $iline->{text} . "</td></tr>";
                }
            }
        }
        foreach my $line (@data) {
            if ( $line->{sdate} eq $day ) {
                if ( $row % 2 == 0 ) {
                    $class = "even";
                }
                else {
                    $class = "odd";
                }
                $row++;

                $ret .= "<tr class='$class'><td>";
                if ($out) {
                    my $rep = $out;
                    foreach my $c (@cn) {
                        $rep =~ s/\%$c\%/$line->{$c}/g;
                    }
                    $ret .= $rep;
                }
                else {
                    foreach my $c (@cn) {
                        $ret .= $line->{$c} . " ";
                    }
                }
                $ret .= "</td></tr>";

            }
        }
    }

    $ret .= "</table>";
    return $ret;

}
###################################
sub DSBMobile_tableHTML($;$) {
    my ( $name, $infoDay ) = @_;
    my $dat  = ReadingsVal( $name, ".lastResult",  "" );
    my $idat = ReadingsVal( $name, ".lastIResult", "" );
    my @cn = split( ",", ReadingsVal( $name, "columnNames", "" ) );
    my $classr = ReadingsVal( $name, "dsb_classReading", "Klasse_n_" );
    my $ret = "<table>";

    $dat  = decode_json($dat);
    $idat = decode_json($idat);

    my @data  = @$dat;
    my @idata = @$idat;
    return "no data found" if ( @data == 0 && ( @idata == 0 || !$infoDay ) );

    if ( @data > 0 ) {
        @data = sort { $a->{sdate} cmp $b->{sdate} or $a->{$classr} cmp $b->{$classr} } @data;
    }

    # get today
    my ( $sec, $min, $hour, $mday, $month, $year, $wday, $yday, $isdst )
        = localtime( gettimeofday() );
    $month++;
    $year += 1900;
    my $today = sprintf( '%04d-%02d-%02d', $year, $month, $mday );

    # build a sorted array of valid dates
    my %hash = ();
    foreach my $d (@data) {
        $hash{ $d->{sdate} } = 1 if $d->{sdate} ge $today;
    }
    if ($infoDay) {
        foreach my $d (@idata) {
            $hash{ $d->{sdate} } = 1 if $d->{sdate} ge $today;
        }
    }
    my @days = keys %hash;
    @days = sort { $a cmp $b } @days;

    my $date = "";
    my $class;
    my $out = AttrVal( $name, "dsb_outputFormat", undef );
    my $cols = @cn;
    foreach my $day (@days) {
        my $row   = 0;
        my $cols  = @cn;
        my $class = "even";
        $ret
            .= "</table><table class='block wide'><tr class='$class'><td colspan = '$cols'><b>"
            . $day
            . "</b></td></tr>";
        $row++;
        if ($infoDay) {
            foreach my $iline (@idata) {
                if ( $row % 2 == 0 ) {
                    $class = "even";
                }
                else {
                    $class = "odd";
                }
                $row++;

                if ( $iline->{sdate} eq $day ) {
                    $ret
                        .= "<tr class='$class'><td colspan ='$cols' align='middle'>"
                        . $iline->{topic} . ": "
                        . $iline->{text}
                        . "</td></tr>";
                }
            }
        }
        $ret .= "<tr>";
        foreach my $c (@cn) {
            $ret .= "<td>" . $c . "</td>";
        }
        $ret .= "</tr>";
        $row++;
        foreach my $line (@data) {
            if ( $line->{sdate} eq $day ) {
                if ( $row % 2 == 0 ) {
                    $class = "even";
                }
                else {
                    $class = "odd";
                }
                $row++;

                $ret .= "<tr class='$class'>";

                foreach my $c (@cn) {
                    $ret .= "<td>" . $line->{$c} . "</td>";

                }
                $ret .= "</tr>";

            }
        }
    }

    $ret .= "</table>";
    return $ret;

}
#######################################
sub DSBMobile_infoHTML($) {
    my ( $name, $infoDay ) = @_;
    my $dat = ReadingsVal( $name, ".lastAResult", "" );
    my $ret = "<table class='block wide'>";

    $dat = decode_json($dat);

    my @data = @$dat;

    @data = sort { $a->{date} cmp $b->{date} } @data;
    my $row = 1;
    my $class;
    foreach my $line (@data) {
        if ( $row % 2 == 0 ) {
            $class = "even";
        }
        else {
            $class = "odd";
        }
        $row++;
        $ret .= "<tr class='$class'><td>"
            . "$line->{date}:</td><td><a  target='_blank' href='$line->{url}'>$line->{title}</a></td></tr>";
    }
    $ret .= "</table>";
    return $ret;

}
###################################
sub DSBMobileUUID() {
    my @chars = ( 'a' .. 'f', 0 .. 9 );
    my @string;
    push( @string, $chars[ int( rand(16) ) ] ) for ( 1 .. 32 );
    splice( @string, 8,  0, '-' );
    splice( @string, 13, 0, '-' );
    splice( @string, 18, 0, '-' );
    splice( @string, 23, 0, '-' );
    return join( '', @string );
}

1;

=pod
=item helper
=item summary Gets timetable information from DSBMobile
=item summary_DE Liest Vertretungspläne von DSBMobile


=begin html

<a name="DSBMobile"></a>
<div>
    <ul>
        DSBMobile reads and displays timetable change information from DSBMobile App, which is used at some schools in Germany (at least)<br><br>
        <a name="DSBMobileDefine"></a>
        <b>Define</b>
        <ul>
            DSBMobile uses several perl modules which have to be installed in advance:
            <ul>
                <li>IO::Compress::Gzip</li>
                <li>IO::Uncompress::Gunzip</li>
                <li>MIME::Base64</li>
                <li>HTML::TableExtract</li>
                DSBMobile will be defined without Parameters.
                <br><br>
                <code>define &lt;devicename&gt; DSBMobile</code><br><br>
                <br><br>
            </ul>
        </ul>
        <a name="DSBMobileGet"></a>
        <b>Get</b>
        <ul>
            <li><a name="timetable">Retrieves the current timetable changes and postings</li>
        </ul>
        <a name="DSBMobileReadings"></a>
        <b>Readings</b>
        <ul>
            Following readings are created:
            <ul>
                <li>columnNames: Readingnames generated dynamically from substitution table column headers</li>
                <li>lastCheck: Date/Time of the last successful check for new data</li>
                <li>lastSync: Date/Time of the last run where data was actually synchronized (not only checked)</li>
                <li>lastTTUpdate: Date/Time of the last update of the timetable data on the DSBMobile server</li>
                <li>error: contains the error message of the last error that occured while fetching data</li>
                <li>state: "ok" if last run was successful, "error" if not.</li>
            </ul>
            For each posting and change in the timetable the following readings are generated
            <ul>
                <li>i#_date: Date of the posting</li>
                <li>i#_title: Title of the posting</li>
                <li>i#_url: Link to the posting</li>
                <li>ti#_sdate: Date of the "Info of the day"</li>
                <li>ti#_topic: Title of the "Info of the day"</li>
                <li>ti#_text: Content of the "Info of the day"</li>
                <li>tt#_xxxx: Dynamically generated reading for each column of the substitution table</li>
            </ul>
        </ul>
        <a name="DSBMobileAttr"></a>
        <b>Attributes</b>
        <ul>
            <ul>
                <li><a name="dsb_user">dsb_user</a>: The user to log in to DSBMobile</li>
                <li><a name="dsb_password">dsb_password</a>: The password to log in to DSBMobile</li>
                <li><a name="dsb_class">dsb_class</a>: The grade to filter for. Can be a regex, e.g. 5a|8b or 6.*c.</li>
                <li><a name="dsb_classReading">dsb_classReading</a>: Has to be set if the column containing the class(es) is not named "Klasse(n)", i.e. the genarated reading is not "Klasse_n_"</li>
                <li><a name="dsb_interval">dsb_interval</a>: Interval in seconds to pull DSBMobile, value of 0 means disabled</li>
                <li><a name="dsb_outputFormat">dsb_outputFormat</a>: can be used to format the output of the weblink. Takes the readingnames enclosed in % as variables, e.g. <code>%Klasse_n_%</code></li>
            </ul>
        </ul>
        DSBMobile additionally provides three functions to display the information in weblinks:
        <ul>
            <li>DSBMobile_simpleHTML($name ["dsb","showInfoOfTheDay"]): Shows the timetable changes, if the second optional parameter is "1", the Info of the Day will be displayed additionally.
                The format may be defined with the dsb_outputFormat attribute
                Example <code>defmod dsb_web weblink htmlCode {DSBMobile_simpleHTML("dsb",1)}</code>
            </li>
            <li>DSBMobile_tableHTML($name ["dsb","showInfoOfTheDay"]): Shows the timetable changes in a tabular format, if the second optional parameter is "1", the Info of the Day will be displayed additionally.
                Example <code>defmod dsb_web weblink htmlCode {DSBMobile_tableHTML("dsb",1)}</code>
            </li>
            <li>DSBMobile_infoHTML($name): Shows the postings with links to the Details.
                Example <code>defmod dsb_infoweb weblink htmlCode {DSBMobile_infoHTML("dsb")}</code>
            </li>
        </ul>
    </ul>
</div>

=end html
=begin html_DE

<a name="DSBMobile"></a>
<div>
    <ul>
        DSBMobile liest die Vertretungspläne der DSBMobile App, die (zumindest) an einigen Schulen in Deutschland verwendet wird<br><br>
        <a name="DSBMobileDefine"></a>
    </ul>
    <b>Define</b>
    <ul>
        DSBMobile verwendet einige Perl-Module, die vorab installiert werden müssen:
        <ul>
            <li>IO::Compress::Gzip</li>
            <li>IO::Uncompress::Gunzip</li>
            <li>MIME::Base64</li>
            <li>HTML::TableExtract</li>
            DSBMobile wird ohne Parameter definiert.
            <br><br>
            <code>define &lt;devicename&gt; DSBMobile</code><br><br>
            <br><br>
        </ul>
        <a name="DSBMobileGet"></a>
        <b>Get</b>
        <ul>
            <ul>
                <li><a name="timetable">Empfängt die aktuellen Vertretungsplan- und Aushang-Informationen</li>
            </ul>
        </ul>
        <a name="DSBMobileReadings"></a>
        <b>Readings</b>
        <ul>
            Die folgenden Readings werden erstellt:
            <ul>
                <li>columnNames: Readingnamen, die dynamisch aus den Spaltenüberschriften des Vertretungsplans generiert werden</li>
                <li>lastCheck: Datum/Uhrzeit der letzten erfolgreichen Überprüfung auf neue Daten</li>
                <li>lastSync: Datum/Uhrzeit der letzten erfolgreichen Synchronisierung neuer Daten(nicht nur Überprüfung)</li>
                <li>lastTTUpdate: Datum/Uhrzeit der letztenAktualisierung auf dem DSBMobile Server</li>
                <li>error: enthält die letzte Fehlermeldung, die bei der Datensynchronisierung aufgetreten ist</li>
                <li>state: "ok" sofern der letzte Abruf erfolgreich war, "error" wenn nicht.</li>
            </ul>
            Für jeden Aushang bzw. jede Vertretung werden folgende Readings erstellt
            <ul>
                <li>i#_date: Datum des Aushangs</li>
                <li>i#_title: Titel des Aushangs</li>
                <li>i#_url: Link zum Aushang</li>
                <li>ti#_sdate: Datum der "Info des Tages"</li>
                <li>ti#_topic: Titel der "Info des Tages"</li>
                <li>ti#_text: Inhalt der "Info des Tages"</li>
                <li>tt#_xxxxDynamisch generierte Readings für jede Spalte des Vertretungsplanes</li>
            </ul>
        </ul>
        <a name="DSBMobileAttr"></a>
        <b>Attributes</b>
        <ul>
            <ul>
                <li><a name="dsb_user">dsb_user</a>: Der User für die DSBMobile-Anmeldung</li>
                <li><a name="dsb_password">dsb_password</a>: Das Passwort für die DSBMobile-Anmeldung</li>
                <li><a name="dsb_class">dsb_class</a>: Die Klasse nach der gefiltert werden soll. Kann eine Regex sein, z.B. 5a|8b or 6.*c.</li>
                <li><a name="dsb_classReading">dsb_classReading</a>: Muss gesetzt werden, wenn die Spalte mit der Klasse nicht "Klasse(n)" heisst, d.h. das generierte reading nicht "Klasse_n_" lautet</li>
                <li><a name="dsb_interval">dsb_interval</a>: Intervall in Sekunden in dem Daten von DSBMobile abgerufen werden, ein Wert von 0 bedeuted disabled</li>
                <li><a name="dsb_outputFormat">dsb_outputFormat</a>: Kann benutzt werden, um den Output des weblinks zu formatieren. Die Readingnamen von % umschlossen können als Variablen verwendet werden, z.B. <code>%Klasse_n_%</code></li>
            </ul>
        </ul>
        DSBMobile bietet zusätzlich drei Funktionen, um die Informationen in weblinks darzustellen:
        <ul>
            <li>DSBMobile_simpleHTML($name ["dsb",showInfoOfTheDay]): Zeigt den Vertretungsplan, wenn der zweite optionale Parameter auf "1" gesetzt wird, wird die Info des Tages zusätzlich mit angezeigt.
                Die Darstellung kann durch das Attribut dsb_outputFormat beeinflusst werden
                Beispiel <code>defmod dsb_web weblink htmlCode {DSBMobile_simpleHTML("dsb",1)}</code>
            </li>
            <li>DSBMobile_tableHTML($name ["dsb",showInfoOfTheDay]): Zeigt den Vertretungsplan in einfacher tabellarischer Ansicht, wenn der zweite optionale Parameter auf "1" gesetzt wird, wird die Info des Tages zusätzlich mit angezeigt.
                Beispiel <code>defmod dsb_web weblink htmlCode {DSBMobile_tableHTML("dsb",1)}</code>
            </li>
            <li>DSBMobile_infoHTML($name): Zeigt die Aushänge mit Links zu den Details.
                Beispiel <code>defmod dsb_infoweb weblink htmlCode {DSBMobile_infoHTML("dsb")}</code>
            </li>
        </ul>
    </ul>
</div>
=end html_DE

=for :application/json;q=META.json 98_DSBMobile.pm
    {
      "abstract": "Gets timetable information from DSBMobile(JSON)",
      "description": "DSBMobile reads and displays timetable change information from DSBMobile App, which is used at some schools in Germany (at least).",
      "x_lang": {
        "de": {
          "abstract": "Liest Vertretungspläne von DSBMobile",
          "description": "DSBMobile liest Vertretungspläne von DSBMobile und zeigt sie an. DSBMobile wird (zumindest) an einigen Schulen in Deutschland verwendet"
        }
      },
      "license":"gpl_2",
      "version": "v0.0.4",
      "x_release_date": "2020-10-01",
      "release_status": "testing",
      "author": [
        "Oli Merten aka KernSani"
      ],
      "x_fhem_maintainer": [
        "KernSani"
      ],
      "keywords": [
        "DSBMobile",
        "Schule",
        "Vertretungsplan",
        "Vertretung",
        "Stundenplan",
        "school",
        "timetable",
        "substitutions"
      ],
      "prereqs": {
        "runtime": {
          "requires": {
            "FHEM": 5.00918623,
            "FHEM::Meta": 0.001006,
            "HttpUtils": 0,
            "JSON": 0,
            "perl": 5.014,
            "IO::Compress::Gzip": 0,
            "IO::Uncompress::Gunzip": 0,
            "MIME::Base64": 0,
            "HTML::TableExtract": 0,
            "HTML::TreeBuilder": 0
          },
          "recommends": {
          },
          "suggests": {
          }
        }
      },
      "x_copyright": {
          "mailto": "oli.merten@gmail.com",
          "title": "Oli Merten"
      },
      "x_support_community": {
          "title": "Support Thread",
          "web": "https://forum.fhem.de/index.php/topic,107104.msg1011580.html"
       },
      "x_support_status": "supported"
    }

=end :application/json;q=META.json

=cut
