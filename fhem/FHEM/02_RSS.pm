#
#
# 02_RSS.pm
# written by Dr. Boris Neubert 2012-03-24
# e-mail: omega at online dot de
#
##############################################
# $Id$

package main;
use strict;
use warnings;
use GD;
use feature qw/switch/;
use vars qw(%data);
use HttpUtils;

#require "98_SVG.pm"; # enable use of plotAsPng()
sub plotAsPng(@);    # forward declaration will be enough
                     # to ensure correct function
                     # and will avoid reloading 98_SVG.pm
                     # during fhem startup/rereadcfg

my @cmd_halign   = qw(halign thalign ihalign);
my @cmd_valign   = qw(valign tvalign ivalign);
my @valid_valign = qw(top center base bottom);
my @valid_halign = qw(left center right justified);

# we can
# use vars qw(%FW_types);  # device types,
# use vars qw($FW_RET);    # Returned data (html)
# use vars qw($FW_wname);  # Web instance
# use vars qw($FW_subdir); # Sub-path in URL for extensions, e.g. 95_FLOORPLAN
# use vars qw(%FW_pos);    # scroll position
# use vars qw($FW_cname);  # Current connection name

# http://blogs.perl.org/users/mike_b/2013/06/a-little-nicer-way-to-use-smartmatch-on-perl-518.html
#no if $] >= 5.017011, warnings => 'experimental::smartmatch';
no if $] >= 5.017011, warnings => 'experimental';

#########################
sub RSS_addExtension($$$) {
    my ( $func, $link, $friendlyname ) = @_;

    my $url = "/" . $link;
    $data{FWEXT}{$url}{FUNC}     = $func;
    $data{FWEXT}{$url}{LINK}     = "+$link";
    $data{FWEXT}{$url}{NAME}     = $friendlyname;
    $data{FWEXT}{$url}{SCRIPT}   = "RSS.js";
    $data{FWEXT}{$url}{FORKABLE} = 0;
}

##################
sub RSS_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}   = "RSS_Define";
    $hash->{UndefFn} = "RSS_Undefine";

    #$hash->{AttrFn}  = "RSS_Attr";
    $hash->{AttrList} =
"size itemtitle bg bgcolor tmin refresh areas autoreread:1,0 viewport noscroll urlOverride";
    $hash->{SetFn}    = "RSS_Set";
    $hash->{NotifyFn} = "RSS_Notify";

    return undef;
}

##################
sub RSS_readLayout($) {

    my ($hash)   = @_;
    my $filename = $hash->{fhem}{filename};
    my $name     = $hash->{NAME};

    my ( $err, @layoutfile ) = FileRead($filename);
    if ($err) {
        Log 1, "RSS $name: $err";
        $hash->{fhem}{layout} = ("text 0.1 0.1 'Error: $err'");
    }
    else {
        $hash->{fhem}{layout} = join( "\n", @layoutfile );
        $hash->{fhem}{layout} =~ s/\n\n/\n/g;
    }
    return;
}

##################
sub RSS_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def );

    return "Usage: define <name> RSS jpg|png hostname filename"
      if ( int(@a) != 5 );
    my $name     = $a[0];
    my $style    = $a[2];
    my $hostname = $a[3];
    my $filename = $a[4];

    $hash->{fhem}{style}    = $style;
    $hash->{fhem}{hostname} = $hostname;
    $hash->{fhem}{filename} = $filename;
    $hash->{LAYOUTFILE}     = $filename;
    $hash->{NOTIFYDEV}      = 'global';

    RSS_addExtension( "RSS_CGI", "rss", "RSS" );

    eval "use GD::Text::Align";
    $hash->{fhem}{useTextAlign} = ( $@ ? 0 : 1 );
    if ( !( $hash->{fhem}{useTextAlign} ) ) {
        Log3 $hash, 2, "$name: Cannot use text alignment: $@";
    }

    eval "use GD::Text::Wrap";
    $hash->{fhem}{useTextWrap} = ( $@ ? 0 : 1 );
    if ( !( $hash->{fhem}{useTextWrap} ) ) {
        Log3 $hash, 2, "$name: Cannot use text wrapping: $@";
    }

    RSS_readLayout($hash);

    $hash->{STATE} = 'defined';    #$name;
    return undef;
}

sub RSS_Undefine($$) {
    my ( $hash, $arg ) = @_;

    # check if last device
    my $url = '/rss';
    $data{FWEXT}{$url} = undef if int( devspec2array('TYPE=RSS') ) == 1;
    return undef;
}

sub RSS_Notify {
    my ( $hash, $dev ) = @_;

    my $name = $hash->{NAME};
    return unless AttrVal( $name, 'autoreread', 1 );
    return if ( $dev->{NAME} ne "global" );
    return
      if ( !grep( m/^FILEWRITE $hash->{LAYOUTFILE}$/, @{ $dev->{CHANGED} } ) );

    Log3( undef, 4, "RSS: $name reread layout after edit." );
    RSS_readLayout($hash);
    return undef;
}

##################
sub RSS_Set() {

    my ( $hash, @a ) = @_;
    my $name = $a[0];

    # usage check
    my $usage = "Unknown argument, choose one of rereadcfg:noArg";
    if ( ( @a == 2 ) && ( $a[1] eq "rereadcfg" ) ) {
        RSS_readLayout($hash);
        return undef;
    }
    else {
        return $usage;
    }
}

####################
#
sub RSS_getURL($) {
    my ($name) = @_;

    my $url = AttrVal( $name, 'urlOverride', '' );
    return $url if ( $url ne "" );

    my $hostname = $defs{$name}{fhem}{hostname};

    # http://hostname:8083/fhem
    my $proto = ( AttrVal( $FW_wname, 'HTTPS', 0 ) == 1 ) ? 'https' : 'http';
    return $proto . "://$hostname:" . $defs{$FW_wname}{PORT} . $FW_ME;
}

# ##################
# sub
# RSS_Attr(@)
# {
#   my @a = @_;
#   my $attr= $a[2];
#
#   if($a[0] eq "set") {  # set attribute
#     if($attr eq "bgdir") {
#     }
#   }
#   elsif($a[0] eq "del") { # delete attribute
#     if($attr eq "bgdir") {
#     }
#   }
#
#   return undef;
#
# }

##################
# list all RSS devices
sub RSS_Overview {

    my ( $name, $url );
    my $html = RSS_HTMLHead( "RSS Overview", undef ) . "<body>\n";
    foreach my $def ( sort keys %defs ) {
        if ( $defs{$def}{TYPE} eq "RSS" ) {
            $name = $defs{$def}{NAME};
            $url  = RSS_getURL($name);
            $html .= "$name<br>\n<ul>";
            $html .=
              "<a href='$url/rss/$name.rss' target='_blank' >RSS</a><br>\n";
            $html .=
              "<a href='$url/rss/$name.html' target='_blank' >HTML</a><br>\n";
            $html .=
"<a href='$url/rss/$name.png' target='_blank' >Portable Network Graphics</a><br>\n";
            $html .=
"<a href='$url/rss/$name.jpg' target='_blank' >JPEG Graphics</a><br>\n";
            $html .= "</ul>\n<p>\n";
        }
    }
    $html .= "</body>\n" . RSS_HTMLTail();

    return ( "text/html; charset=utf-8", $html );
}

##################
sub RSS_splitRequest($) {

    # http://hostname:8083/fhem/rss
    # http://hostname:8083/fhem/rss/myDeviceName.rss
    # http://hostname:8083/fhem/rss/myDeviceName.jpg?t=47110.815
    # |--------- url ----------|    |---name --| ext |--query--|

    my ($request) = @_;

    # http://hostname:8083/fhem/rss/myDeviceName.rss
    # http://hostname:8083/fhem/rss/myDeviceName.jpg
    # http://hostname:8083/fhem/rss/myDeviceName.png
    # http://hostname:8083/fhem/rss/myDeviceName.html
    use constant REGEXP => '^.*\/rss\/([^\/]*)\.(jpg|png|rss|html)(\?(.*))?$';
    if ( $request =~ REGEXP ) {
        return ( $1, $2, $4 );
    }
    else {
        #main::Debug "not matched";
        return ( undef, undef, undef );
    }
}

##################
sub RSS_returnRSS($) {
    my ($name) = @_;

    my $url       = RSS_getURL($name);
    my $type      = $defs{$name}{fhem}{style};
    my $mime      = ( $type eq 'png' ) ? 'image/png' : 'image/jpeg';
    my $now       = time();
    my $itemTitle = AttrVal( $name, "itemtitle", "" );
    my $titleTag =
      ( $itemTitle ne '' ) ? '<title>' . $itemTitle . '</title>' : '';
    my $code =
"<rss version='2.0' xmlns:media='http://search.yahoo.com/mrss/'><channel><title>$name</title><ttl>1</ttl><item>$titleTag<media:content url='$url/rss/$name.$type' type='$mime'/><guid isPermaLink='false'>item_$now</guid></item></channel></rss>";

    return ( "application/xml; charset=utf-8", $code );
}

##################
sub RSS_getScript() {

    my $jsTemplate = '<script type="text/javascript" src="%s"></script>';
    my $scripts    = "";
    if ( defined( $data{FWEXT} ) ) {
        foreach my $k ( sort keys %{ $data{FWEXT} } ) {
            my $h = $data{FWEXT}{$k};
            next if ( $h !~ m/HASH/ || !$h->{SCRIPT} );
            my $script = $h->{SCRIPT};
            $script =
              ( $script =~ m,^/, ) ? "$FW_ME$script" : "$FW_ME/pgm2/$script";
            $scripts .= sprintf( $jsTemplate, $script ) . "\n";
        }
    }
    return $scripts;
}

sub RSS_HTMLHead($$) {
    my ( $name, $refresh ) = @_;

    my ( $width, $height ) = split( /x/, AttrVal( $name, "size", "800x600" ) );
    my $viewportContent = AttrVal( $name, "viewport", "" );

    my $doctype =
'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
    my $xmlns   = 'xmlns="http://www.w3.org/1999/xhtml"';
    my $scripts = RSS_getScript();
    my $viewport =
      $viewportContent eq ""
      ? ""
      : "<meta name=\"viewport\" content=\"$viewportContent\"/>\n";
    my $code =
"$doctype\n<html $xmlns>\n<head>\n<title>$name</title>\n$viewport$scripts</head>\n";
}

sub RSS_HTMLTail() {
    return "</html>";
}

sub RSS_returnHTML($) {
    my ($name) = @_;

    my $url      = RSS_getURL($name);
    my $type     = $defs{$name}{fhem}{style};
    my $img      = "$url/rss/$name.$type";
    my $refresh  = AttrVal( $name, 'refresh', 60 );
    my $noscroll = AttrVal( $name, 'noscroll', 0 );
    my $overflow = $noscroll ? "  style=\"overflow:hidden\"" : "";
    my $areas    = AttrVal( $name, 'areas', "" );
    my $embed    = $defs{$name}{".embed"};
    my $r        = "";
    if ( defined($refresh) && ( $refresh > 0 ) ) {
        my $handler =
          "\"setTimeout(function(){reloadImage(\'img0\')},$refresh*1000);\"";
        $r = " onload=$handler onerror=$handler";
    }
    my $code =
        RSS_HTMLHead( $name, $refresh )
      . "<body topmargin=\"0\" leftmargin=\"0\" margin=\"0\" padding=\"0\"$overflow>\n"
      . "<div id=\"rss_$name\" style=\"z-index:1;\" >\n"
      . "<img id=\"img0\" src=\"$img\" usemap=\"#map\"$r/>\n"
      . "<map name=\"map\" id=\"map\">\n$areas\n</map>\n"
      . "</div>\n"
      . "$embed\n"
      . "</body>\n"
      . RSS_HTMLTail();
    return ( "text/html; charset=utf-8", $code );
}

##################
# Library
##################

sub RSS_xy {
    my ( $S, $x, $y, %params ) = @_;

    $x = $params{x} if ( $x eq 'x' );
    $y = $params{y} if ( $y eq 'y' );

    if ( ( -1 < $x ) && ( $x < 1 ) ) { $x *= $S->width; }
    if ( ( -1 < $y ) && ( $y < 1 ) ) { $y *= $S->height; }

    return ( $x, $y );
}

sub RSS_color {
    my ( $S, $rgb ) = @_;
    my $alpha = 0;
    my @d = split( "", $rgb );
    if ( length($rgb) == 8 ) {
        $alpha = hex("$d[6]$d[7]");
        $alpha = ( $alpha < 127 ) ? $alpha : 127;
    }
    return $S->colorAllocateAlpha( hex("$d[0]$d[1]"), hex("$d[2]$d[3]"),
        hex("$d[4]$d[5]"), $alpha );
}

sub RSS_itemText {
    my ( $S, $x, $y, $text, %params ) = @_;
    return unless ( defined($text) );

    if ( $params{useTextAlign} ) {
        my $align = GD::Text::Align->new(
            $S,
            color  => RSS_color( $S, $params{rgb} ),
            valign => $params{tvalign},
            halign => $params{thalign},
        );
        $align->set_font( $params{font}, $params{pt} );
        $align->set_text($text);
        $align->draw( $x, $y, 0 );
    }
    else {
        $S->stringFT( RSS_color( $S, $params{rgb} ),
            $params{font}, $params{pt}, 0, $x, $y, $text );
    }
}

sub RSS_itemTextBox {
    my ( $S, $x, $y, $boxwidth, $bgcolor, $text, %params ) = @_;
    return unless ( defined($text) );

    if ( $params{useTextWrap} ) {
        if ( ( 0 < $boxwidth ) && ( $boxwidth < 1 ) ) {
            $boxwidth *= $S->width;
        }
        my $wrapbox = GD::Text::Wrap->new(
            $S,
            color      => RSS_color( $S, $params{rgb} ),
            line_space => $params{linespace},
            text       => $text,
        );
        $wrapbox->set_font( $params{font}, $params{pt} );
        $wrapbox->set( align => $params{thalign}, width => $boxwidth );
        my ( $left, $top, $right, $bottom );
        ( $left, $top, $right, $bottom ) = $wrapbox->get_bounds( $x, $y );
        $S->filledRectangle( $left, $top, $right, $bottom,
            RSS_color( $S, $bgcolor ) )
          if ( defined($bgcolor) );
        ( $left, $top, $right, $bottom ) = $wrapbox->draw( $x, $y );
        return $bottom;
    }
    else {
        RSS_itemText( $S, $x, $y, $text, %params );
        return $y;
    }
}

sub RSS_itemTime {
    my ( $S, $x, $y, %params ) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    RSS_itemText( $S, $x, $y, sprintf( "%02d:%02d", $hour, $min ), %params );
}

sub RSS_itemSeconds {
    my ( $S, $x, $y, $format, %params ) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    if ( $format eq "colon" ) {
        RSS_itemText( $S, $x, $y, sprintf( ":%02d", $sec ), %params );
    }
    else {
        RSS_itemText( $S, $x, $y, sprintf( "%02d", $sec ), %params );
    }
}

sub RSS_itemDate {
    my ( $S, $x, $y, %params ) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    RSS_itemText( $S, $x, $y,
        sprintf( "%02d.%02d.%04d", $mday, $mon + 1, $year + 1900 ), %params );

}

sub RSS_itemImg {
    my ( $S, $x, $y, $scale, $imgtype, $srctype, $arg, %params ) = @_;
    return unless ( defined($arg) );
    return if ( $arg eq "" );
    my $I;
    if ( $srctype eq "url" || $srctype eq "urlq" ) {
        my $data;
        if ( $srctype eq "url" ) {
            $data = GetFileFromURL( $arg, 3, undef, 1 );
        }
        else {
            $data = GetFileFromURLQuiet( $arg, 3, undef, 1 );
        }
        if ( $imgtype eq "gif" ) {
            $I = GD::Image->newFromGifData($data);
        }
        elsif ( $imgtype eq "png" ) {
            $I = GD::Image->newFromPngData($data);
        }
        elsif ( $imgtype eq "jpeg" ) {
            $I = GD::Image->newFromJpegData($data);
        }
        else {
            return;
        }
    }
    elsif ( $srctype eq "file" ) {
        if ( $imgtype eq "gif" ) {
            $I = GD::Image->newFromGif($arg);
        }
        elsif ( $imgtype eq "png" ) {
            $I = GD::Image->newFromPng($arg);
        }
        elsif ( $imgtype eq "jpeg" ) {
            $I = GD::Image->newFromJpeg($arg);
        }
        else {
            return;
        }
    }
    elsif ( $srctype eq "data" ) {
        if ( $imgtype eq "gif" ) {
            $I = GD::Image->newFromGifData($arg);
        }
        elsif ( $imgtype eq "png" ) {
            $I = GD::Image->newFromPngData($arg);
        }
        elsif ( $imgtype eq "jpeg" ) {
            $I = GD::Image->newFromJpegData($arg);
        }
        else {
            return;
        }
    }
    else {
        return;
    }
    eval {
        my ( $width, $height ) = $I->getBounds();
        if ( $scale =~ s/([wh])([\d]*)/$2/ )
        {    # get the digit from width/hight to pixel entry
             #Debug "RSS scale $scale (1: $1 / 2: $2)contais px after Digit - width: $width / height: $height";
            if ( $1 eq "w" ) {
                $scale = $scale / $width;
            }
            else {
                $scale = $scale / $height;
            }
        }
        my ( $swidth, $sheight ) =
          ( int( $scale * $width ), int( $scale * $height ) );

        given ( $params{ihalign} ) {
            when ('center') { $x -= $swidth / 2; }
            when ('right')  { $x -= $swidth; }
            default {
            }    # nothing to do
        }
        given ( $params{ivalign} ) {
            when ('center') { $y -= $sheight / 2; }
            when ('base')   { $y -= $sheight; }
            when ('bottom') { $y -= $sheight; }
            default {
            }    # nothing to do
        }

        #Debug "RSS placing $arg ($swidth x $sheight) at ($x,$y)";
        $S->copyResampled( $I, $x, $y, 0, 0, $swidth, $sheight, $width,
            $height );
    };
    if ($@) {
        Log3 undef, 2, "RSS: cannot create image $srctype $imgtype '$arg': $@";
    }
}

sub RSS_itemLine {
    my ( $S, $x1, $y1, $x2, $y2, $th, %params ) = @_;
    $S->setThickness($th);
    $S->line( $x1, $y1, $x2, $y2, RSS_color( $S, $params{rgb} ) );
}

sub RSS_itemRect {
    my ( $S, $x1, $y1, $x2, $y2, $filled, %params ) = @_;
    $x2 = $x1 + $x2 if ( $x2 =~ /^\+/ );
    $y2 = $y1 + $y2 if ( $y2 =~ /^\+/ );
    if ($filled) {
        $S->filledRectangle( $x1, $y1, $x2, $y2,
            RSS_color( $S, $params{rgb} ) );
    }
    else {
        $S->rectangle( $x1, $y1, $x2, $y2, RSS_color( $S, $params{rgb} ) );
    }
}

##################

sub RSS_cleanLayout($) {
    my ($input) = @_;
    my @output;

    my $cont = "";
    foreach my $line ( split( "\n", $input ) ) {

        # kill trailing newline
        chomp $line;

        # kill comments and blank lines
        $line =~ s/\#.*$//;
        $line =~ s/\s+$//;
        $line = $cont . $line;
        if ( $line =~ s/\\$// ) { $cont = $line; undef $line; }
        next unless ($line);
        $cont = "";
        push @output, $line;
    }
    return @output;
}

sub RSS_analyzePerl($) {
    my ($expr) = @_;
    return AnalyzePerlCommand( undef, $expr, 1 );
}

sub RSS_evalLayout($$@) {
    my ( $S, $name, $layout ) = @_;

    my @layout = RSS_cleanLayout($layout);
    my $lineNr;
    my %labels;
    my %count;

    # first pass
    # collect labels
    for ( $lineNr = 0 ; $lineNr <= $#layout ; $lineNr++ ) {
        if ( $layout[$lineNr] =~ /^label\s+(.+)$/ ) {
            my $label = $1;
            if ( exists( $labels{$label} ) ) {
                Log3 $name, 2, "$name: label $label redefined.";
            }
            else {
                $labels{$label} = $lineNr;
                $count{ '$' . $label } = 0;
                #Debug "defined label $label";
            }
        }
    }
    EvalSpecials( undef, %count );

    # second pass
    # create actual layout

    my %pstack;
    my $pstackcount = 0;
    my %params;
    $params{font}      = "Arial";
    $params{pt}        = 12;
    $params{rgb}       = "ffffff";
    $params{halign}    = 'left';
    $params{valign}    = 'base';
    $params{condition} = 1;

    # we need two pairs of align parameters
    # due to different default values for text and img
    $params{useTextAlign} = $defs{$name}{fhem}{useTextAlign};
    $params{useTextWrap}  = $defs{$name}{fhem}{useTextWrap};
    $params{ihalign}      = 'left';
    $params{ivalign}      = 'top';
    $params{thalign}      = 'left';
    $params{tvalign}      = 'base';
    $params{linespace}    = 0;
    $params{x}            = 0;
    $params{y}            = 0;

    $defs{$name}{".embed"} = "";

    my (
        $x,    $y,       $z,       $x1,      $y1,
        $x2,   $y2,      $scale,   $bgcolor, $boxwidth,
        $text, $imgtype, $srctype, $arg,     $format
    );

    for ( $lineNr = 0 ; $lineNr <= $#layout ; $lineNr++ ) {
        my $line = $layout[$lineNr];

        #Debug "Line $lineNr: $line";

        #Debug "$name: evaluating >$line<";
        # split line into command and definition
        my ( $cmd, $def ) = split( "[ \t]+", $line, 2 );

        #Debug "CMD= \"$cmd\", DEF= \"$def\"";

        # separate condition handling
        if ( $cmd eq 'condition' ) {
            $params{condition} = RSS_analyzePerl($def);
            #Debug "condition $def evaluated to " . $params{condition};
            next;
        }
        next unless ( $params{condition} );

        #Debug "before command $line: x= " . $params{x} . ", y= " . $params{y};

        eval {
            if ( $cmd eq "rgb" ) {
                $def = "\"$def\""
                  if ( length($def) == 6 && $def =~ /[[:xdigit:]]{6}/ );
                $params{rgb} = RSS_analyzePerl($def);
            }
            elsif ( $cmd eq "font" ) {
                $params{font} = $def;
            }
            elsif ( $cmd eq "pt" ) {
                $def = RSS_analyzePerl($def);
                if ( $def =~ m/^[+-]/ ) {
                    $params{pt} += $def;
                }
                else {
                    $params{pt} = $def;
                }
                $params{pt} = 6 if ( $params{pt} < 0 );
            }
            elsif ( $cmd eq "moveto" ) {
                my ( $tox, $toy ) = split( '[ \t]+', $def, 2 );
                my ( $x, $y ) = RSS_xy( $S, $tox, $toy, %params );
                $params{x} = $x;
                $params{y} = $y;
            }
            elsif ( $cmd eq "moveby" ) {
                my ( $byx, $byy ) = split( '[ \t]+', $def, 2 );
                my ( $x, $y ) = RSS_xy( $S, $byx, $byy, %params );
                $params{x} += $x;
                $params{y} += $y;
            }
            elsif ( $cmd ~~ @cmd_halign ) {
                my $d = RSS_analyzePerl($def);
                if ( $d ~~ @valid_halign ) {
                    $params{ihalign} = $d unless ( $cmd eq "thalign" );
                    $params{thalign} = $d unless ( $cmd eq "ihalign" );
                }
                else {
                    Log3 $name, 2, "$name: Illegal horizontal alignment $d";
                }
            }
            elsif ( $cmd ~~ @cmd_valign ) {
                my $d = RSS_analyzePerl($def);
                if ( $d ~~ @valid_valign ) {
                    $params{ivalign} = $d unless ( $cmd eq "tvalign" );
                    $params{tvalign} = $d unless ( $cmd eq "ivalign" );
                }
                else {
                    Log3 $name, 2, "$name: Illegal vertical alignment $d";
                }
            }
            elsif ( $cmd eq "linespace" ) {
                $params{linespace} = $def;
            }
            elsif ( $cmd eq "text" ) {
                ( $x, $y, $text ) = split( "[ \t]+", $def, 3 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                $params{x} = $x;
                $params{y} = $y;
                my $txt = RSS_analyzePerl($text);

                #Debug "$name: ($x,$y) $txt";
                RSS_itemText( $S, $x, $y, $txt, %params );
            }
            elsif ( $cmd eq "textbox" ) {
                ( $x, $y, $boxwidth, $text ) = split( "[ \t]+", $def, 4 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                my $txt = RSS_analyzePerl($text);
                $y = RSS_itemTextBox( $S, $x, $y, $boxwidth, undef, $txt,
                    %params );
                $params{x} = $x;
                $params{y} = $y;
            }
            elsif ( $cmd eq "textboxf" ) {
                ( $x, $y, $boxwidth, $bgcolor, $text ) =
                  split( "[ \t]+", $def, 5 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                $bgcolor =
                  ( $bgcolor ne "" )
                  ? RSS_analyzePerl($bgcolor)
                  : undef;
                my $txt = RSS_analyzePerl($text);
                $y = RSS_itemTextBox( $S, $x, $y, $boxwidth, $bgcolor, $txt,
                    %params );
                $params{x} = $x;
                $params{y} = $y;
            }
            elsif ( $cmd eq "line" ) {
                ( $x1, $y1, $x2, $y2, $format ) =
                  split( "[ \t]+", $def, 5 );
                ( $x1, $y1 ) = RSS_xy( $S, $x1, $y1, %params );
                ( $x2, $y2 ) = RSS_xy( $S, $x2, $y2, %params );
                $format //=
                  1;    # set format to 1 as default thickness for the line
                RSS_itemLine( $S, $x1, $y1, $x2, $y2, $format, %params );
            }
            elsif ( $cmd eq "rect" ) {
                ( $x1, $y1, $x2, $y2, $format ) =
                  split( "[ \t]+", $def, 5 );
                ( $x1, $y1 ) = RSS_xy( $S, $x1, $y1, %params );
                ( $x2, $y2 ) = RSS_xy( $S, $x2, $y2, %params );
                $format //= 0;    # set format to 0 as default (not filled)
                RSS_itemRect( $S, $x1, $y1, $x2, $y2, $format, %params );
            }
            elsif ( $cmd eq "time" ) {
                ( $x, $y ) = split( "[ \t]+", $def, 2 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                $params{x} = $x;
                $params{y} = $y;
                RSS_itemTime( $S, $x, $y, %params );
            }
            elsif ( $cmd eq "seconds" ) {
                ( $x, $y, $format ) = split( "[ \+]", $def, 3 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                $params{x} = $x;
                $params{y} = $y;
                RSS_itemSeconds( $S, $x, $y, $format, %params );
            }
            elsif ( $cmd eq "date" ) {
                ( $x, $y ) = split( "[ \t]+", $def, 2 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                $params{x} = $x;
                $params{y} = $y;
                RSS_itemDate( $S, $x, $y, %params );
            }
            elsif ( $cmd eq "img" ) {
                ( $x, $y, $scale, $imgtype, $srctype, $arg ) =
                  split( "[ \t]+", $def, 6 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                $params{x} = $x;
                $params{y} = $y;
                my $arg = RSS_analyzePerl($arg);
                RSS_itemImg( $S, $x, $y, $scale, $imgtype, $srctype, $arg,
                    %params );
            }
            elsif ( $cmd eq "push" ) {
                $pstackcount++;
                while ( my ( $key, $value ) = each(%params) ) {
                    $pstack{$pstackcount}{$key} = $value;
                }
            }
            elsif ( $cmd eq "pop" ) {
                return unless $pstackcount;
                while ( my ( $key, $value ) =
                    each( %{ $pstack{$pstackcount} } ) )
                {
                    $params{$key} = $value;
                }
                delete $pstack{$pstackcount};
                $pstackcount--;
            }
            elsif ( $cmd eq "embed" ) {
                ( $x, $y, $z, $format, $text, $arg ) =
                  split( "[ \t]+", $def, 6 );
                ( $x, $y ) = RSS_xy( $S, $x, $y, %params );
                my $arg = RSS_analyzePerl($arg);
                $defs{$name}{".embed"} .=
                    "<div id=\"$text\" style=\"position:"
                  . $format
                  . "; left:"
                  . $x
                  . "px; top:"
                  . $y
                  . "px; z-index:$z;\">\n";
                $defs{$name}{".embed"} .= $arg . "\n";
                $defs{$name}{".embed"} .= "</div>\n";

                #main::Debug "SET EMBED=" . $defs{$name}{".embed"};
            }
            elsif ( $cmd eq "label" ) {

                #Debug "encountered label $def";
                $count{ '$' . $def }++;
                if ( $count{ '$' . $def } > 99 ) {
                    Log3 $name, 2, "$name: exceeded hit count for label $def";
                    last;
                }
                #Debug "label $def hit count " . $count{ '$' . $def };
                EvalSpecials(undef, %count);
            }
            elsif ( $cmd eq "goto" ) {
                my ( $label, $if, $condition ) = split( "[ \t]+", $def, 3 );
                if ( defined($if)
                    and ( ( $if ne "if" ) or ( !defined($condition) ) ) )
                {
                    Log3 $name, 2,
                      "$name: syntax error in goto command \"$line\".";
                    next;
                }
                if ( exists $labels{$label} ) {
                    if ( !defined($if)
                        or RSS_analyzePerl($condition) )
                    {
                        $lineNr = $labels{$label} - 1;
                    }
                }
                else {
                    Log3 $name, 2,
                      "$name: Undefined label $label in goto command.";
                }
            }
            else {
                Log3 $name, 2,
                  "$name: Illegal command $cmd in layout definition.";
            }

         #Debug "after  command $line: x= " . $params{x} . ", y= " . $params{y};
        };
        if ($@) {
            my $msg =
              "$name: Error from line \'$line\' in layout definition: $@";
            chomp $msg;
            Log3 $name, 2, $msg;
        }
    }
}

##################
sub RSS_returnIMG($$) {
    my ( $name, $type ) = @_;

    my ( $width, $height ) =
      split( /x/, AttrVal( $name, "size", "800x600" ) );

    #
    # increase counter
    #
    if (   defined( $defs{$name}{fhem} )
        && defined( $defs{$name}{fhem}{counter} ) )
    {
        $defs{$name}{fhem}{counter}++;
    }
    else {
        $defs{$name}{fhem}{counter} = 1;
    }

    # true color
    GD::Image->trueColor(1);

    #
    # create the image
    #
    our $S;

    # let's create a blank image, we will need it in most cases.
    $S = GD::Image->newTrueColor( $width, $height );
    my $bgcolor =
      AttrVal( $name, 'bgcolor', '000000' );    #default bg color = black
    $bgcolor = RSS_color( $S, $bgcolor );

    # $S->colorAllocate(0,0,0); # other colors seem not to work (issue with GD)
    $S->fill( 0, 0, $bgcolor );

    # wrap to make problems with GD non-lethal

    eval {
        #
        # set the background
        #
        # check if background directory is set
        my $reason = "?";    # remember reason for undefined image
        my $bgdir = AttrVal( $name, "bg", "undef" );
        if ( defined($bgdir) ) {
            my $bgnr;        # item number
            if (   defined( $defs{$name}{fhem} )
                && defined( $defs{$name}{fhem}{bgnr} ) )
            {
                $bgnr = $defs{$name}{fhem}{bgnr};
            }
            else {
                $bgnr = 0;
            }

            # check if at least tmin seconds have passed
            my $t0 = 0;
            my $tmin = AttrVal( $name, "tmin", 0 );
            if (   defined( $defs{$name}{fhem} )
                && defined( $defs{$name}{fhem}{t} ) )
            {
                $t0 = $defs{$name}{fhem}{t};
            }
            my $t1 = time();
            if ( $t1 - $t0 >= $tmin ) {
                $defs{$name}{fhem}{t} = $t1;
                $bgnr++;
            }

            # detect pictures
            if ( opendir( BGDIR, $bgdir ) ) {
                my @bgfiles = grep { $_ !~ /^\./ } readdir(BGDIR);

                #foreach my $f (@bgfiles) {
                #  Debug sprintf("File \"%s\"\n", $f);
                #}
                closedir(BGDIR);

                # get item number
                if ( $#bgfiles >= 0 ) {
                    if ( $bgnr > $#bgfiles ) { $bgnr = 0; }
                    $defs{$name}{fhem}{bgnr} = $bgnr;
                    my $bgfile = $bgdir . "/" . $bgfiles[$bgnr];
                    my $filetype = ( split( /\./, $bgfile ) )[-1];
                    my $bg;
                    $bg = newFromGif GD::Image($bgfile)
                      if $filetype =~ m/^gif$/i;
                    $bg = newFromJpeg GD::Image($bgfile)
                      if $filetype =~ m/^jpe?g$/i;
                    $bg = newFromPng GD::Image($bgfile)
                      if $filetype =~ m/^png$/i;

                    if ( defined($bg) ) {
                        my ( $bgwidth, $bgheight ) = $bg->getBounds();
                        if ( $bgwidth != $width or $bgheight != $height ) {

                            # we need to resize
                            my ( $w, $h );
                            my ( $u, $v ) =
                              ( $bgwidth / $width, $bgheight / $height );
                            if ( $u > $v ) {
                                $w = $width;
                                $h = $bgheight / $u;
                            }
                            else {
                                $h = $height;
                                $w = $bgwidth / $v;
                            }
                            $S->copyResized(
                                $bg,
                                ( $width - $w ) / 2,
                                ( $height - $h ) / 2,
                                0, 0, $w, $h, $bgwidth, $bgheight
                            );
                        }
                        else {
                            # size is as required
                            # kill the predefined image and take the original
                            undef $S;
                            $S = $bg;
                        }
                    }
                    else {
                        undef $S;
                        $reason =
"Something was wrong with background image \"$bgfile\".";
                    }
                }
            }
        }
        #
        # evaluate layout
        #
        if ( defined($S) ) {
            RSS_evalLayout( $S, $name, $defs{$name}{fhem}{layout} );
        }
        else {
            Log3 $name, 2, "$name: Could not create image. $reason";
            $S =
              GD::Image->newTrueColor( $width, $height );   # return empty image
        }
        $defs{$name}{STATE} = localtime();

    };    #warn $@ if $@;
    if ($@) {
        my $msg = $@;
        chomp $msg;
        Log3 $name, 2, $msg;
    }

    #
    # return image
    #
    return ( "image/jpeg; charset=utf-8", $S->jpeg ) if ( $type eq 'jpg' );
    return ( "image/png; charset=utf-8",  $S->png )  if ( $type eq 'png' );
}

##################
#
# here we answer any request to http://host:port/fhem/rss and below
sub RSS_CGI() {

    my ($request) =
      @_;    # /rss or /rss/name.rss or /rss/name.jpg or /rss/name.png

    my ( $name, $ext, $query ) =
      RSS_splitRequest($request);    # name, ext (rss, jpg, png, html), query
                                     # query is unused

    #main::Debug "Request: $request";
    #main::Debug " Name  : $name";
    #main::Debug " Ext   : $ext";
    #main::Debug " Query : $query";

    if ( defined($name) ) {
        if ( $ext eq "" ) {
            return ( "text/plain; charset=utf-8", "Illegal extension." );
        }
        if ( !defined( $defs{$name} ) ) {
            return ( "text/plain; charset=utf-8", "Unknown RSS device: $name" );
        }

        if ( $ext eq "jpg" ) {
            return RSS_returnIMG( $name, 'jpg' );
        }
        elsif ( $ext eq "png" ) {
            return RSS_returnIMG( $name, 'png' );
        }
        elsif ( $ext eq "rss" ) {
            return RSS_returnRSS($name);
        }
        elsif ( $ext eq "html" ) {
            return RSS_returnHTML($name);
        }
    }
    else {
        return RSS_Overview();
    }

}

sub plotFromUrl(@) {
    my (@plotName) = @_;
    my @webs;

    @webs = devspec2array("TYPE=FHEMWEB");
    foreach (@webs) {
        if ( !InternalVal( $_, 'TEMPORARY', undef ) ) {
            $FW_wname = InternalVal( $_, 'NAME', '' );
            last;
        }
    }

    my ( $w, $h ) =
      split( ",", AttrVal( $plotName[0], "plotsize", "800,160" ) );

    my $url;
    $url =
        "<embed src=\""
      . "$FW_ME/SVG_showLog?dev="
      . $plotName[0]
      . "&amp;logdev="
      . InternalVal( $plotName[0], "LOGDEVICE", "" )
      . "&amp;gplotfile="
      . InternalVal( $plotName[0], "GPLOTFILE", "" )
      . "&amp;logfile="
      . InternalVal( $plotName[0], "LOGFILE", "CURRENT" );
    $url .= "&amp;pos=" . $plotName[1]  if $plotName[1];
    $url .= "&amp;zoom=" . $plotName[2] if $plotName[2];
    $url .= "\"";
    $url .= " type=\"image/svg+xml\"";
    $url .= " width=\"$w\"";
    $url .= " height=\"$h\"";
    $url .= " id=\"" . $plotName[0] . "\" >";
    return $url;
}

#

1;

=pod
=item helper
=item summary Provides a freely configurable RSS feed and HTML page.
=item summary_DE Stellt frei konfigurierbaren RSS-Feed und HTML-Seite bereit.
=begin html

<a name="RSS"></a>
<h3>RSS</h3>
<ul>
  Provides a freely configurable RSS feed and HTML page.<p>

  The media RSS feed delivers status pictures either in JPEG or PNG format.

  This media RSS feed can be used to feed a status display to a
  network-enabled photo frame.<p>

  In addition, a periodically refreshing HTML page is generated that shows the picture
  with an optional HTML image map.<p>

  You need to have the perl module <code>GD</code> installed. This module is most likely not
  available for small systems like Fritz!Box.<p>
  RSS is an extension to <a href="#FHEMWEB">FHEMWEB</a>. You must install FHEMWEB to use RSS.<p>

  Beginners might find the <a href="http://forum.fhem.de/index.php/topic,22520.0.html">RSS Workshop</a> useful.<p>

  A note on colors: Colors are specified as 6- or 8-digit hex numbers,
  every 2 digits determining the red, green and blue color components as in HTML
  color codes. The optional 7th and 8th digit code the alpha channel (transparency from
  00 to 7F). Examples: <code>FF0000</code> for red, <code>C0C0C0</code> for light
  gray, <code>1C1C1C40</code> for semi-transparent gray.<p>

  <a name="RSSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RSS jpg|png &lt;hostname&gt; &lt;filename&gt;</code><br><br>

    Defines the RSS feed. <code>jpg</code> and <code>png</code> are fixed literals to select output format.
    <code>&lt;hostname&gt;</code> is the hostname of the fhem server as
    seen from the consumer of the RSS feed. <code>&lt;filename&gt;</code> is the
    name of the file that contains the <a href="RSSlayout">layout definition</a>.<p>

    Examples
    <ul>
      <code>define FrameRSS RSS jpg host.example.org /etc/fhem/layout</code><br>
      <code>define MyRSS RSS png 192.168.1.222 /var/fhem/conf/layout.txt</code><br>
    </ul>
    <br>

    The RSS feeds are at
    <ul>
        <code>http://host.example.org:8083/fhem/rss/FrameRSS.rss</code><br>
        <code>http://192.168.1.222:8083/fhem/rss/MyRSS.rss</code><br>
    </ul>
    <br>

    The pictures are at
    <ul>
        <code>http://host.example.org:8083/fhem/rss/FrameRSS.jpg</code><br>
        <code>http://192.168.1.222:8083/fhem/rss/MyRSS.png</code><br>
    </ul>
    <br>

    The HTML pages are at
    <ul>
        <code>http://host.example.org:8083/fhem/rss/FrameRSS.html</code><br>
        <code>http://192.168.1.222:8083/fhem/rss/MyRSS.html</code><br>
    </ul>
    <br>

  </ul>

  <a name="RSSset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; rereadcfg</code>
    <br><br>
    Rereads the <a href="RSSlayout">layout definition</a> from the file. Useful to enable
    changes in the layout on-the-fly.
    <br><br>
  </ul>

  <a name="RSSattr"></a>
  <b>Attributes</b>
  <br><br>
  <ul>
    <li>autoreread<br>If set to 1, layout is automatically reread when layout file has been changed
    by FHEMWEB file editor.</li><br>
    <li>size<br>The dimensions of the picture in the format
    <code>&lt;width&gt;x&lt;height&gt;</code>.</li><br>
    <li>bg<br>The directory that contains the background pictures (must be in JPEG, GIF or PNG format, file
    format is guessed from file name extension).</li><br>
    <li>bgcolor &lt;color&gt;<br>Sets the background color. </li><br>
    <li>tmin<br>The background picture is shown at least <code>tmin</code> seconds,
    no matter how frequently the RSS feed consumer accesses the page.</li><br>
    <li>refresh &lt;interval&gt;<br>Time in seconds after which the HTML page is automatically reloaded. Defaults to 60.
    Set &lt;interval&gt; to 0 to disable reloading.</li><br>
    <li>viewport<br>Adds a viewport directive to the HTML header.<br>
        Example: <code>attr FrameRSS viewport width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0</code><br>
        This scales the image to fit to the browser's viewport and inhibits zooming in or out on tablets.
    </li><br>
    <li>noscroll</br>Suppresses scrollbars in browsers, if set to 1.
    </li><br>
    <li>areas<br>HTML code that goes into the image map.<br>
        Example: <code>attr FrameRSS areas &lt;area shape="rect" coords="0,0,200,200" href="http://fhem.de"/&gt;&lt;area shape="rect" coords="600,400,799,599" href="http://has:8083/fhem" target="_top"/&gt;</code>
    </li><br>
    <li>itemtitle</br>Adds a title tag to the RSS item that contains the specified text.
    </li><br>
    <li>urlOverride<br>Overrides the URL in the generated feed.
    If you specify
    <code>attr &lt;name&gt; http://otherhost.example.org:8083/foo/bar</code>, the
    JPEG picture that is at
    <code>http://host.example.org:8083/fhem/rss/FrameRSS.jpg</code>
    will be referenced as
    <code>http://otherhost.example.org:8083/foo/bar/rss/FrameRSS.jpg</code>. This is useful when
    your FHEM URLs are rewritten, e.g. if FHEM is accessed by a Reverse Proxy.</li>
    <br>
  </ul>
  <br><br>

  <b>Usage information</b>
  <br><br>
  <ul>
  If a least one RSS feed is defined, the menu entry <code>RSS</code> appears in the FHEMWEB
  side menu. If you click it you get a list of all defined RSS feeds. The URL of any such is
  RSS feed is <code>http://hostname:port/fhem/rss/name.rss</code> with <code>hostname</code> and
  <code>name</code> from the RSS feed's <a href="RSSdefine">definition</a> and the <code>port</code>
  (usually 8083) and literal <code>/fhem</code> from the underlying <a href="#FHEMWEB">FHEMWEB</a>
  definition.<p>

  Example:
  <ul><code>http://host.example.org:8083/fhem/rss/FrameRSS.rss</code></ul><p>

  The media RSS feed points to a dynamically generated picture. The URL of the picture
  belonging to the RSS can be found by replacing the extension ".rss" in feed's URL by ".jpg" or ".png"
  depending on defined output format,<p>

  Example:
  <ul><code>http://host.example.org:8083/fhem/rss/FrameRSS.jpg</code></ul><p>
  <ul><code>http://192.168.100.200:8083/fhem/rss/FrameRSS.png</code></ul><p>

  To render the picture the current, or, if <code>tmin</code> seconds have elapsed, the next
  JPEG picture from the directory <code>bg</code> is chosen and scaled to the dimensions given
  in <code>size</code>. The background is black if no usable JPEG picture can be found. Next the
  script in the <a href="RSSlayout">layout definition</a> is used to superimpose items on
  the background.<p>

  You can directly access the URL of the picture in your browser. Reload the page to see
  how it works.<p>

  The media RSS feed advertises to refresh after 1 minute (ttl). Some photo frames ignore it and
  use their preset refresh rate. Go for a photo frame with an adjustable refresh rate (e.g
  every 5 seconds) if you have the choice!<p>

  This is how the fhem config part might look like:<p>
  <code>
  define ui FHEMWEB 8083 global<br><br>

  define FrameRSS RSS jpg host.example.org /etc/fhem/layout<br>
  attr FrameRSS size 800x600<br>
  attr FrameRSS bg /usr/share/pictures<br>
  attr FrameRSS tmin 10<br>
  </code>

  </ul>

  <a name="RSSlayout"></a>
  <b>Layout definition</b>
  <br><br>
  <ul>
    The layout definition is a script for placing items on the background. It is read top-down.
    It consists of layout control commands and items placement commands. Layout control
    commands define the appearance of subsequent items. Item placement commands actually
    render items.<p>

    Everything after a # is treated as a comment and ignored. You can fold long lines by
    putting a \ at the end.<p>

    <i>General notes</i><br>
    <ol>
    <li>Use double quotes to quote literal text if perl specials are allowed.</li>
    <li>Text alignment requires the Perl module GD::Text::Align to be installed. Text wrapping (in text boxes) require GD::Text::Wrap to be installed. Debian-based systems can install both with <code>apt-get install libgd-text-perl</code>.</li>
    </ol>
    <p>
    <i>Notes on coordinates</i><br>
    <ol>
    <li>(0,0) is the upper left corner.</li>
    <li>Coordinates equal or greater than 1 are considered to be absolute pixels, coordinates between 0 and 1 are considered to
    be relative to the total width or height of the picture.</li>
    <li>Literal <code>x</code> and <code>y</code> evaluate to the most recently used x- and y-coordinate. See also moveto and moveby below.</li>
    <!--<li>You can use <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for x and for y.</li>-->
    </ol>
    <p>


    <i>Layout control commands</i><p>

    <ul>
    <li>moveto &lt;x&gt; &lt;y&gt;<br>Moves most recently used x- and y-coordinate to the given absolute or relative position.</li><br>

    <li>moveby &lt;x&gt; &lt;y&gt;<br>Moves most recently used x- and y-coordinate by the given absolute or relative amounts.</li><br>

    <li>font "&lt;font&gt;"<br>Sets the font. &lt;font&gt; is the name of a TrueType font (e.g.
    <code>Arial</code>) or the full path to a TrueType font
    (e.g. <code>/usr/share/fonts/truetype/arial.ttf</code>),
    whatever works on your system.</li><br>

    <a name="rss_rgb"></a>
    <li>rgb "&lt;color&gt;"<br>Sets the color. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;color&gt.</li><br>

    <li>pt &lt;pt&gt;<br>Sets the font size in points. A + or - sign in front of the the number given
    for &lt;pt&gt signifies a change of the font size relative to the current size. Otherwise the absolute
    size is set. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;pt&gt.</li><br>

    <li>thalign|ihalign|halign "left"|"center"|"right"<br>Sets the horizontal alignment of text, image or both. Defaults to left-aligned. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> instead of the literal alignment control word.</li><br>

    <li>tvalign|ivalign|valign "top"|"center"|"base"|"bottom"<br>Sets the vertical alignment of text, image or both. Defaults to base-aligned for text and
    top-aligned for image. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> instead of the literal alignment control word.</li><br>

    <li>linespace &lt;space&gt;<br>Sets the line spacing in pixels for text boxes (see textbox item below).</li><br>

    <li>condition &lt;condition&gt;<br>Subsequent layout control and item placement commands except for another condition command are ignored if and only if &lt;condition&gt; evaluates to false.</li><br>

    <li>push<br>The current parameter set (position, color, font name and size, text alignment and line spacing) is
    put (saved) on top of a stack.</li><br>

    <li>pop<br>The most recently saved (pushed) current parameter set is pulled from the top of the stack and restored.</li><br>

    <li>label &lt;lbl&gt;<br>Define a label for this line &ndash; i.e. name this line &lt;lbl&gt;. This label can be used to jump back or forward to this line by the &lt;goto&gt; command.<br>
    A counter is implicitly defined for every label. From <a href="#perl">&lt;perl specials&gt;</a> it can be accessed with <code>{$&lt;lbl&gt;}</code>.
    Example: the hit count for label <code>foo</code> is in <code>$foo</code>.
    The counter starts with zero and is increased with every hit of the label.
    </li></br>

    <li>goto &lt;lbl&gt;<br>goto &lt;lbl&gt; if <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code><br>
        Jump back or forward to the line labelled &lt;lbl&gt;. The condition is
        optional. Example: <code>goto foo if { $foo < 5 }</code>. This can be used to create loops.
        Note: if the goto jumps forward to the label for the first time, the hit count is 0;
        if the goto jumps backward to the label for the first time, the hit count is already 1.</li><br>

    </ul>

    <i>Item placement commands</i><p>
    <ul>
    <li>text &lt;x&gt; &lt;y&gt; &lt;text&gt;<br>Renders the text &lt;text&gt; at the
    position (&lt;x&gt;, &lt;y&gt;) using the current font, font size and color.
    You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;text&gt; to fully
    access device readings and do some programming on the fly. See below for examples.</li><br>

    <li>textbox &lt;x&gt; &lt;y&gt; &lt;boxwidth&gt; &lt;text&gt;<br>Same as before but text is rendered
    in a box of horizontal width &lt;boxwidth&gt;.</li><br>

    <li>textboxf &lt;x&gt; &lt;y&gt; &lt;boxwidth&gt; &lt;bgcolor&gt; &lt;text&gt;<br>Same as before but
    the textbox will be filled with the given background color &lt;bgcolor&gt; before drawing the text.
    &lt;bgcolor&gt; can be used with <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> to evalute <a href="#rss_rgb">RGB</a> value.</li><br>

    <li>time &lt;x&gt; &lt;y&gt;<br>Renders the current time in HH:MM format.</li><br>

    <li>seconds &lt;x&gt; &lt;y&gt; &lt;format&gt<br>Renders the curent seconds. Maybe useful for a RSS Clock.</li><br>

    <li>date &lt;x&gt; &lt;y&gt;<br>Renders the current date in DD.MM.YYYY format.</li><br>

    <li>line &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt; [&lt;thickness&gt;]<br>Draws a line from position (&lt;x1&gt;, &lt;y1&gt;) to position (&lt;x2&gt;, &lt;y2&gt;) with optional thickness (default=1).</li><br>
    <li>rect &lt;x1&gt; &lt;y1&gt; &lt;x2&gt; &lt;y2&gt; [&lt;filled&gt;]<br>Draws a rectangle with corners at positions (&lt;x1&gt;, &lt;y1&gt;) and (&lt;x2&gt;, &lt;y2&gt;), which is filled if the &lt;filled&gt; parameter is set and not zero.<br>If x2 or y2 is preceeded with a + (plus sign) then the coordinate is relative to x1 or y1, or in other words, it is the width-1 or height-1 of the rectangle, respectively.</li><br>

    <li>img &lt;x&gt; &lt;y&gt; &lt;['w' or 'h']s&gt; &lt;imgtype&gt; &lt;srctype&gt; &lt;arg&gt; <br>Renders a picture at the
    position (&lt;x&gt;, &lt;y&gt;). The &lt;imgtype&gt; is one of <code>gif</code>, <code>jpeg</code>, <code>png</code>.
    The picture is scaled by the factor &lt;s&gt; (a decimal value). If 'w' or 'h' is in front of scale-value the value is used to set width or height to the value in pixel. If &lt;srctype&gt; is <code>file</code>, the picture
    is loaded from the filename &lt;arg&gt;, if &lt;srctype&gt; is <code>url</code> or <code>urlq</code>, the picture
    is loaded from the URL &lt;arg&gt; (with or without logging the URL), if &lt;srctype&gt; is <code>data</code>, the picture
    is piped in from data &lt;arg&gt;. You can use
    <code>{ <a href="#perl">&lt;perl special&gt;</a> }</code> for &lt;arg&gt. See below for example.<br>
    <b>Warning</b>: do not load the image from URL that is served by fhem as it leads to a deadlock.</li><br>

    <li>embed &lt;x&gt; &lt;y&gt; &lt;z&gt; &lt;position&gt; &lt;id&gt; &lt;element&gt;<br>
    For HTML output: embeds a <code>div</code> element into the HTML page at (&lt;x&gt;,&lt;y&gt;) with z-order &lt;z&gt; and positioning &lt;position&gt; (use <code>absolute</code>). &lt;id&gt; is the <code>id</code> attribute of the
    <code>div</code> element and &lt;element&gt; is its content.<br>
    <b>Note:</b> There are several issues with different browsers when using this.</li><br>

    </ul>

    <i>Example</i><p>
    This is how a layout definition might look like:<p>
    <code>
    font /usr/share/fonts/truetype/arial.ttf # must be a TrueType font<br>
    rgb "c0c0c0" # HTML color notation, RGB<br>
    pt 48 # font size in points<br>
    time 0.10 0.90<br>
    pt 24<br>
    text 0.10 0.95 { ReadingsVal("MyWeather","temperature","?"). "C" }<br>
    moveby 0 -25<br>
    text x y "Another text"<br>
    img 20 530 0.5 png file { "/usr/share/fhem/www/images/weather/" . ReadingsVal("MyWeather","icon","") . ".png" }<br>
    embed 0 0 2 absolute plot1 { plotFromUrl('mySVG') }
    embed 10 200 2 absolute iframe1 "&lt;iframe width=\"420\" height=\"315\" src=\"//www.youtube.com/embed/9HShl_ufOFI\" frameborder=\"0\" allowfullscreen&gt;&lt;/iframe&gt;"
    </code>
    <p>

    <i>Special uses</i><p>

    You can display <a href="#SVG">SVG</a> plots with the aid of the helper function <code>plotAsPng(&lt;name&gt;[,&lt;zoom&gt;[,&lt;offset&gt;]])</code> (in 98_SVG.pm). Examples:<p>
    <code>
    img 20 30 0.6 png data { plotAsPng("mySVGPlot") }<BR>
    img 20 30 0.6 png data { plotAsPng("mySVGPlot","qday",-1) }
    </code>
    <p>
    This requires the perl module Image::LibRSVG and librsvg. Debian-based systems can install these with <code>apt-get install libimage-librsvg-perl</code>.<p>

    For HTML output, you can use <code>plotFromURL(&lt;name&gt;[,&lt;zoom&gt;[,&lt;offset&gt;]])</code> instead.
  </ul>








</ul>


=end html
=cut
