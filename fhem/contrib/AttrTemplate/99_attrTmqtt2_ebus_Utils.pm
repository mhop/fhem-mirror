##############################################
# $Id$
#

package FHEM::aTm2u_ebus;    ## no critic 'Package declaration'

use strict;
use warnings;

use JSON qw(decode_json);
use Scalar::Util qw(looks_like_number);
use List::Util 1.45 qw(uniq);

use GPUtils qw(GP_Import);

#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          json2nameValue
          toJSON
          AttrVal
          InternalVal
          CommandGet
          CommandSet
          CommandAttr
          CommandDefine
          CommandDeleteReading
          CommandVersion
          FmtDateTime
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsVal
          ReadingsNum
          ReadingsAge
          json2nameValue
          addToDevAttrList
          defs
          Log3
          trim
          )
    );
}

sub ::attrTmqtt2_ebus_Utils_Initialize { goto &Initialize }
sub ::attrTmqtt2_ebus_createBarView { goto &createBarView }

# initialize ##################################################################
sub Initialize {
    my $hash = shift;
    return;
}
# Enter you functions below _this_ line.

sub j2nv {
    my $EVENT = shift // return;
    my $pre   = shift;
    my $filt  = shift;
    my $not   = shift;

    return if !length $EVENT;
    $EVENT=~ s,[{]"value":\s("?[^"}]+"?)[}],$1,g;
    return json2nameValue($EVENT, $pre, $filt, $not);
}

sub j2singleReading {
    my $rName = shift // return;
    my $EVENT = shift // return;
    my $pre   = shift;
    my $filt  = shift;
    my $not   = shift;

    return if !length $EVENT;
    $EVENT=~ s,[{]"value":\s("?[^"}]+"?)[}],$1,g;
    my $values = json2nameValue($EVENT, $pre, $filt, $not);
    my @all;
    for my $item ( sort keys %{$values} ) {
        push @all, qq{$item: $values->{$item}};
    }
    return { $rName => join q{ - }, @all };
}

sub send_weekprofile {
    my $name       = shift // return;
    my $wp_name    = shift // return;
    my $wp_profile = shift // return;
    my $model      = shift // ReadingsVal($name,'week','unknown'); #selected,Mo-Fr,Mo-So,Sa-So? holiday to set actual $wday to sunday program?
    #[quote author=Reinhart link=topic=97989.msg925644#msg925644 date=1554057312]
    #"daysel" nicht. Für mich bedeutet dies, das das Csv mit der Feldbeschreibung nicht überein stimmt. Ich kann aber nirgends einen Fehler sichten (timerhc.inc oder _templates.csv). [code]daysel,UCH,0=selected;1=Mo-Fr;2=Sa-So;3=Mo-So,,Tage[/code]
    #Ebenfalls getestet mit numerischem daysel (0,1,2,3), auch ohne Erfolg.
    my $onLimit    = shift // '20';

    my $hash = $defs{$name} // return;

    my $wp_profile_data = CommandGet(undef,"$wp_name profile_data $wp_profile 0");
    if ($wp_profile_data =~ m{(profile.*not.found|usage..profile_data..name)}xms ) {
        Log3( $hash, 3, "[$name] weekprofile $wp_name: no profile named \"$wp_profile\" available" );
        return;
    }

    my @Dl = ("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday");
    my @D = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat");

    my $payload;
    #my @days = (0..6);
    my $text = decode_json($wp_profile_data);

    ( $model, my @days ) = split m{:}xms, $model;
    (my $sec,my $min,my $hour,my $mday,my $mon,my $year,my $wday,my $yday,my $isdst) = localtime;

    my @models;
    if ( $model eq 'unknown' ) {
        my $monday = toJSON($text->{$D[1]}{time}) . toJSON($text->{$D[1]}{temp});
        my $satday = toJSON($text->{$D[6]}{time}) . toJSON($text->{$D[6]}{temp});
        my $sunday = toJSON($text->{$D[0]}{time}) . toJSON($text->{$D[0]}{temp});
        $models[0] = $satday eq $sunday && $sunday eq $monday ? '3' : $satday eq $sunday ? 2 : 0;
        $models[1] = 1;
        for my $i (2..5) {
            my $othday = toJSON($text->{$D[$i]}{time}) . toJSON($text->{$D[$i]}{temp});
            next if $othday eq $monday;
            $models[1] = 0;
            last;
        }
        @days = $models[0] == 3 ? (1) :
                $models[1] == 1 && $models[0] == 2 ? (0,1) :
                $models[1] == 1 ? (0,1,6) :
                $models[1] == 0 && $models[0] == 2 ? (0..5) : (0..6)
    }

    if (!@days) {
        if ( $model eq 'Mo-Fr' ) {
            @days = (1);
            $models[1] = 1;
        } elsif ( $model eq 'Mo-So' ) {
            @days = (1);
            $models[1] = 1;
            $models[0] = 3;
        } elsif ( $model eq 'holiday' ) {
            @days = (0);
        } elsif ( $model eq 'selected' ) {
            @days = (0..6);
            $models[1] = 0;
            $models[0] = 0;
        } elsif ( $model eq 'Sa-So' ) {
            @days = (0);
            $models[0] = 2;
        }
    }

    for my $i (@days) {
        $payload = q{};
        my $pairs = 0;
        my $onOff = 'off';

        for my $j (0..20) {
            my $time = '00:00';
            if (defined $text->{$D[$i]}{time}[$j]) {
                $time = $text->{$D[$i]}{time}[$j-1] // '00:00';
                my $val = $text->{$D[$i]}{temp}[$j];
                if ( $val eq $onOff || (looks_like_number($val) && _compareOnOff( $val, $onOff, $onLimit ) ) ) {
                    $time = '00:00' if !$j;
                    $payload .= qq{$time;$text->{$D[$i]}{time}[$j];};
                    $pairs++;
                    $val = $val eq 'on' ? 'off' : 'on';
                }
            }
            while ( $pairs < 3 && !defined $text->{$D[$i]}{time}[$j] ) {
                #fill up the three pairs with last time
                $pairs++;
                $payload .= qq{-,-;-,-;};
            }
            last if $pairs == 3;
        }

        if ( $model eq 'holiday' ) {
            $payload .= 'selected';
            CommandSet($defs{$name},"$name $Dl[$wday] $payload") if ReadingsVal($name,$Dl[$wday],'') ne $payload;
        } elsif ( $model eq 'selected' ) {
            $payload .= 'selected';
            CommandSet($defs{$name},"$name $Dl[$i] $payload") if ReadingsVal($name,$Dl[$i],'') ne $payload;
        } elsif ($i == 1) {
            $payload .=  defined $models[0] && $models[0] == 3 ? 'Mo-So' : defined $models[1] && $models[1] ? 'Mo-Fr' : 'selected';
            CommandSet($defs{$name},"$name $Dl[$i] $payload") if defined $models[0] && $models[0] == 3 ||defined $models[1] && $models[1];
            CommandSet($defs{$name},"$name $Dl[$i] $payload") if ReadingsVal($name,$Dl[$i],'') ne $payload;
        } elsif ($i == 0 || $i == 6 ) {
            my $united = defined $models[0] && $models[0] == 2; 
            $payload .=  $united ? 'Sa-So' : 'selected';
            CommandSet($defs{$name},"$name $Dl[$united ? 6 : $i] $payload") if ReadingsVal($name,$Dl[$united ? 6 : $i],'') ne $payload || $united;
        } else {
            $payload .= 'selected';
            CommandSet($defs{$name},"$name $Dl[$i] $payload") if ReadingsVal($name,$Dl[$i],'') ne $payload;
        }
    }

    readingsSingleUpdate( $defs{$name}, 'weekprofile', "$wp_name $wp_profile",1);
    return;
}

sub _compareOnOff {
    my $val   = shift // return;
    my $onOff = shift // return;
    my $lim   = shift;

    if ( $onOff eq 'on' ) {
        return $val < $lim;
    } else {
        return $val >= $lim;
    }
    return;
}

sub analyzeReadingList {
    my $name   = shift // return;
    my $setpre = shift // 0;

    my $hash = $defs{$name} // return;

    my $cid = $defs{$name}{CID};
    my $dt = $defs{$name}{DEVICETOPIC};
    my $revsn = (split q{\n}, CommandVersion(undef, 'attrTmqtt2_ebus_Utils noheader'))[0] // 'unknown';
    $revsn = FmtDateTime(time) . " $revsn";
    my $attrTemplt = q{ebus_analyzeReadingList};

    my $rList_old = AttrVal( $name, 'readingList', '');
    my $rList_new = q{};
    my $firstprofile = 0;
    my $dylist = 0;

    my @need_prefix;
    my @readings = keys %{$defs{$name}->{READINGS}};
    for my $m (@readings){
        if ($m =~ m{\A([^_]+_)_}){
            push @need_prefix, $1;
        }
    }
    @need_prefix = uniq @need_prefix;
    my $needs_prefix = join q{|}, @need_prefix;
    #Log3(undef,3,"präfix regex: $needs_prefix");

    my $newline;
    for my $line ( split q{\n}, $rList_old ) {
        $line = trim($line);
        next if $line eq '';
        my $func;
        my $prefix;

        if ( $line =~ m{FHEM::aTm2u_ebus::}xm ) {
            $rList_new .= $rList_new ? qq{\n$line} : $line;
            next;
        }
        my ($re,$code) = split q{ }, $line, 2;
        if ( !defined $code ) {
            Log3($name, 3, "ERROR: deleted empty code in existing readingList line >$line< for $name");
            next;
        }

        $re =~ s{\$DEVICETOPIC}{$dt}g;
        $re =~ s{\A$cid:}{}g;
        $code = trim($code);

        #not Perl?
        if($code !~ m{\A[{].*[}]\z}s) {
            $rList_new .= $rList_new ? qq{\n$re $code} : qq{$re $code};
            next;
        }

        my $newtop;
        my $short;

        #weekprofile type rL element?
        if ( $re =~ m{(?<start>.+[/])(?<short>[^/:.]+)(?:[.]|\\x2e)(?<dy>[^.]+)(?:[.]|\\x2e)[1-3]:}xm ) {
            $newtop = qq{$+{start}$+{short}.*:.*};
            my $sLtop  = qq{$+{start}$+{short}};
            $short  = $+{short};
            my $dy     = $+{dy};
            next if $firstprofile eq $short;
            my @Dl = ("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday");
            my @dylists = qw(Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday Sonntag|Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag Sun|Mon|Tue|Wed|Thu|Fri|Sat Son|Mon|Die|Mit|Don|Fre|Sam Su|Mo|Tu|We|Th|Fr|Sa So|Mo|Di|Mi|Do|Fr|Sa);
            
            for my $daylist (@dylists) {
                if ( $dylist) {
                    $func = "{ FHEM::aTm2u_ebus::upd_day_profile( \$NAME, \$TOPIC, \$EVENT, '" . $dylist . "' ) }";
                } elsif ( $dy =~ m{$daylist}xms ) {
                    $func = "{ FHEM::aTm2u_ebus::upd_day_profile( \$NAME, \$TOPIC, \$EVENT, '" . $daylist . "' ) }";
                    $dylist = $daylist;
                }
            }
            if ( !defined $func ) {
                Log3(undef, 1, "error evaluating daylist, day is $dy");
                next;
            }
            $newline = qq{$newtop $func};
            #Log3(undef, 3, "topic: $newtop, function $func");

            my @shD = split m{\|}xms, $dylist;
            if ( !$firstprofile ) {
                $rList_new .= $rList_new ? qq{\n$newline} : qq{$newline};
                $firstprofile = $short;
                my $sList_old = AttrVal( $name, 'setList', '');
                my $sList_new = $sList_old;
                for my $i (0..6) {
                    my $sLline = qq{$Dl[$i] $sLtop.$shD[$i]/set};
                    if ( index ($sList_new, $sLline) == -1 ) {
                        $sList_new .= $sList_new ? qq{\n$sLline} : $sLline;
                    }
                }
                CommandAttr(undef, "$name setList $sList_new") if $sList_new ne $sList_old;
                addToDevAttrList($name, 'weekprofile', 'weekprofile');
                CommandAttr(undef, "$name weekprofile $name") if !defined AttrVal($name, 'weekprofile', undef);
                next;
            }
            my $newdev  = qq{${name}_${short}};
            if ( !defined $defs{$newdev} ) {
                CommandDefine( $defs{$name}, "$newdev MQTT2_DEVICE" );
                readingsBeginUpdate($defs{$newdev});
                readingsBulkUpdate($defs{$newdev}, 'associatedWith', $name);
                readingsBulkUpdate($defs{$newdev}, 'IODev', InternalVal($name, 'IODev',undef)->{NAME});
                readingsBulkUpdate($defs{$newdev}, 'attrTemplateVersion', $revsn);
                readingsEndUpdate($defs{$newdev}, 0);
                my $nroom = AttrVal($name, 'room','MQTT2_DEVICE');
                CommandAttr(undef, "$newdev room $nroom");
                my $sList;
                for my $i (0..6) {
                    my $sLlin = qq{$Dl[$i] $sLtop.$shD[$i]/set};
                    $sList .= $sList ? qq{\n$sLlin} : $sLlin;
                }
                CommandAttr(undef, "$newdev setList $sList");
                CommandAttr(undef, "$newdev model $attrTemplt");
                addToDevAttrList($newdev, 'weekprofile', 'weekprofile');
                CommandAttr(undef, "$newdev weekprofile $newdev");
                my $ac = ReadingsVal($name, 'associatedWith','');
                $ac .= $ac ? qq{,$newdev} : $newdev;
                readingsSingleUpdate($defs{$name}, 'associatedWith', $ac, 0);
                
            }
            my $rl2 = AttrVal($newdev, 'readingList', "");
            $rl2 .= q{\n} if $rl2;
            CommandAttr(undef, "$newdev readingList $rl2$newline") if index($rl2, $newtop) == -1;
            next;
        }

        my $prefix ;

        #json2nameValue type rL element with dot?
        if ( $re =~ m{(?<start>.+[/])(?<short>[^/:]+)(?:[.]|\\x2e)(?<item>[^.:123]+):}xm ) {
            $newtop = qq{$+{start}$+{short}.$+{item}:.*};
            $prefix = qq{$+{short}_$+{item}_};
            
            $func = '{ FHEM::aTm2u_ebus::j2nv( $EVENT, ' . qq{'$prefix', } . '$JSONMAP ) }';
            $newline = qq{$newtop $func};
            $rList_new .= $rList_new ? qq{\n$newline} : qq{$newline};
            next;
        }

        #json2nameValue type rL element with Error content? ebusd/sc/ErrorHistory
        if ( $re =~ m{(?<start>.+[/])(?<short>ErrorHistory):}xm ) {
            $newtop = $re;
            $short  = $+{short};
            $func = q<{ FHEM::aTm2u_ebus::j2singleReading( > . qq{'$short', }. q<$EVENT, '', $JSONMAP ) }>;
            $newline = qq{$newtop $func};
            $rList_new .= $rList_new ? qq{\n$newline} : qq{$newline};
            next;
        }

        #json2nameValue type rL element w/o dot?
        if ( $code =~ m{\A[{]\s+json2nameValue.*[}]\z}s) {
            $func = q<{ FHEM::aTm2u_ebus::j2nv( $EVENT, '>;
            my $funcb = q<', $JSONMAP ) }>;
            my $mid  = q{};
            $re =~ m{(?<start>.+[/])(?<pre>[^/:]+):}xm;
            my $mid2 = qq{$+{pre}_};
            $mid = $mid2 if $setpre || $mid2 =~ m{$needs_prefix}xms;
            $newline = qq{$re $func${mid}${funcb}};
            $rList_new .= $rList_new ? qq{\n$newline} : qq{$newline};
            next;
        }
    }
    #Log3(undef,3,"readingList new: $rList_new");
    CommandAttr(undef, "$name readingList $rList_new") if index($rList_old, $rList_new) == -1;
    CommandAttr(undef, "$name model $attrTemplt") if AttrVal($name, 'model', '') ne $attrTemplt;
    CommandDeleteReading(undef, "$name .*_value");
    readingsSingleUpdate($defs{$name}, 'attrTemplateVersion', $revsn,0);
    return;
}


#ebusd/hc1/HP1.Mo.1:.* { json2nameValue($EVENT) }
#zwei Readings "Start_value" und "End_value" 
# Vermutung: { "Start": {"value": "10:00"}, "End": {"value": "11:00"}}
#ebusd/hc1/HP1\x2eMo\x2e2:.* { json2nameValue($EVENT) }
sub upd_day_profile {
    my $name    = shift // return;
    my $topic   = shift // return;
    my $payload = shift // return;
    my $daylist = shift // q(Su|Mo|Tu|We|Th|Fr|Sa);

    my $hash = $defs{$name} // return;
    return if !length $payload;

    my @Dl = ("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday");

    my $data = decode_json($payload);
    $topic =~ m{[.](?<dayshort>$daylist)[.](?<pair>[1-3])\z}xms;
    my $shday   = $+{dayshort} // return;
    my $pairNr  = $+{pair} // return;
    $pairNr--;

    my @days = split m{\|}xms, $daylist;
    my %days_index = map { $days[$_] => $_ } (0..6);
    my $index = $days_index{$shday};
    #Log3(undef,3, "[$name] day $shday, pair $pairNr, index $index days @days");

    return if !defined $index;

    my $rVal = ReadingsVal( $name, $Dl[$index], '-,-;-,-;-,-;-,-;-,-;-,-;Mo-So' );
    my @times = split m{;}xms, $rVal;
    $times[$pairNr*2] = $data->{Start}->{value};
    $times[$pairNr*2+1] = $data->{End}->{value};
    $rVal = join q{;}, @times;

    readingsSingleUpdate( $defs{$name}, $Dl[$index], $rVal, 1);
    return;
}


sub createBarView {
  my ($val,$maxValue,$color) = @_;
  $maxValue = $maxValue//100;
  $color = $color//"red";
  my $percent = $val / $maxValue * 100;
  # Definition des valueStyles
  my $stylestring = 'style="'.
    'width: 200px; '.
    'text-align:center; '.
    'border: 1px solid #ccc ;'. 
    "background-image: -webkit-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '.
    "background-image:    -moz-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:     -ms-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:      -o-linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%); '. 
    "background-image:         linear-gradient(left,$color $percent".'%, rgba(0,0,0,0) '.$percent.'%);"';
    # Rückgabe des definierten Strings
  return $stylestring;
}

1;

__END__
=pod
=begin html

<a id="attrTmqtt2_ebus_Utils"></a>
<h3>attrTmqtt2_ebus_Utils</h3>
<ul>
  <b>Functions to support attrTemplates for ebusd</b><br> 
</ul>
<ul>
  <li><b>FHEM::aTm2u_ebus::j2nv</b><br>
  <code>FHEM::aTm2u_ebus::j2nv($,$$$)</code><br>
  This is just a wrapper to fhem.pl json2nameValue() to prevent the "_value" postfix. It will first clean the first argument by applying <code>$EVENT=~ s,[{]"value":\s("?[^"}]+"?)[}],$1,g</code>. 
  </li>
  <li><b>FHEM::aTm2u_ebus::upd_day_profile</b><br>
  <code>FHEM::aTm2u_ebus::upd_day_profile($$$,$)</code><br>
  Helper function to collect weekprofile info received over different topics. $NAME, $TOPIC and $EVENT are obligatory to be handed over, additionally you may provide a <i>daylist</i> as 4th argument. <i>daylist</i> defaults to Su|Mo|Tu|We|Th|Fr|Sa. Generated readings will be named Sunday, Monday, ..., so make sure to use different MQTT2-devices for each topic-group, if there's more than one item attached to your ebus capable to use weekly profiles.
  </li>
  <li><b>FHEM::aTm2u_ebus::send_weekprofile</b><br>
  <code>FHEM::aTm2u_ebus::send_weekprofile($$$,$$)</code><br>
  Helper function that may be capable to translate a (temperature) <i>weekly profile<i> provided by a <i>weekprofile<i> TYPE device to the ebus format (max. three pairs of on/off switching times).
  </li>
  <li><b>FHEM::aTm2u_ebus::createBarView</b><br>
  <code>FHEM::aTm2u_ebus::createBarView($,$$)</code><br>
  Parameters are 
  <ul>
    <li>$value (required)</li> 
    <li>$maxvalue (optional), defaults to 100</li> 
    <li>$color, (optional), defaults to red</li> 
  </ul>
  For compability reasons, function will also be exported as attrTmqtt2_ebus_createBarView(). Better use package version to call it... 
  </li>
</ul><br>
=end html
=cut
