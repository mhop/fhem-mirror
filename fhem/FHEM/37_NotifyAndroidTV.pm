# $Id$

package main;

use strict;
use warnings;

use HttpUtils;

use vars qw($FW_icondir);

use Data::Dumper;

my $options = { position => { 'bottom-right' => 0,
                              'bottom-left' => 1,
                              'top-right' => 2,
                              'top-left' => 3,
                              'center' => 4,
                            },
                transparency => { 'default' => 0,
                                  '0%' => 1,
                                  '25%' => 2,
                                  '50%' => 3,
                                  '75%' => 4,
                                  '100%' => 5,
                                },
                interrupt => { 'true' => 1,
                               'false' => 0,
                             },
                bkgcolor => { 'grey' => '#607d8b',
                              'black' => '#000000',
                              'indigo' => '#303F9F',
                              'green' => '#4CAF50',
                              'red' => '#F44336',
                              'cyan' => '#00BCD4',
                              'teal' => '#009688',
                              'amber' => '#FFC107',
                              'pink' => '#E91E63',
                            },
                type => { '0' => 0,
                          '1' => 1,
                          '2' => 2,
                          '3' => 3,
                          '4' => 4,
                          '5' => 5,
                        },
                duration => undef,
                offset => undef,
                offsety => undef,
                icon => undef,
                title => undef,
                imageurl => undef,
             };

sub
NotifyAndroidTV_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "NotifyAndroidTV_Define";
  $hash->{UndefFn}  = "NotifyAndroidTV_Undefine";
  $hash->{SetFn}    = "NotifyAndroidTV_Set";
  #$hash->{AttrFn}   = "NotifyAndroidTV_Attr";
  #$hash->{AttrList} = "defaultIcon";

  foreach my $option (keys %{$options}) {
    $hash->{AttrList} .= ' ' if( $hash->{AttrList} );
    $hash->{AttrList} .= "NotifyAndroidTV#$option";
    if( $options->{$option} ) {
      $hash->{AttrList} .= ":select,". join( ',', sort keys %{$options->{$option}} )
    }
  }
  delete $hash->{AttrList};
}

#####################################

sub
NotifyAndroidTV_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> NotifyAndroidTV <host>" if(@a != 3);

  my $name = $a[0];
  my $host = $a[2];

  $hash->{NAME} = $name;
  $hash->{host} = $host;


  $hash->{STATE} = 'INITIALIZED';

  return undef;
}

sub
NotifyAndroidTV_Undefine($$)
{
  my ($hash, $arg) = @_;

  return undef;
}

sub
NotifyAndroidTV_addFormField($$;$)
{
  my ($name,$data,$extra) = @_;

  return "--boundary\r\n".
         "Content-Disposition: form-data; name=\"$name\"\r\n".
         ($extra?"$extra\r\n":"").
         "\r\n".
         $data."\r\n"
}

sub
NotifyAndroidTV_parseHttpAnswer($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 2, "NotifyAndroidTV ($name) - got error while sending notificaton $err";
    if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
      asyncOutput( $param->{cl}, "got error while sending notification $err\n" );
    }
    return;
  }
}

sub
NotifyAndroidTV_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;

  $hash->{".triggerUsed"} = 1;

  my $list = 'msg';

  if( $cmd eq 'msg' || $cmd eq 'notify' ) {
    my ($param_a, $param_h) = parseParams(\@params);

    my $txt = join( ' ', @{$param_a} );
    $txt =~ s/\n/<br>/g;

    my $error;
    foreach my $option (keys %{$param_h}) {
      if( $options->{$option} ) {
        $param_h->{$option} = $options->{$option}{$param_h->{$option}};

        if( !defined($param_h->{$option}) ) {
          $error .= "\n";
          $error .= "$option value must be one of: ". join( ' ', sort keys %{$options->{$option}} );
        }
      }
    }

    return "error: $error" if( $error );

    $param_h->{offset} = 0 if( !$param_h->{offset} );
    $param_h->{offsety} = 0 if( !$param_h->{offsety} );
    $param_h->{transparency} = 0 if( !$param_h->{transparency} );

    $param_h->{icon} = 'fhemicon.png' if( !$param_h->{icon} );
    $param_h->{icon} .= ".png" if( $param_h->{icon} !~ '\.' );
    $param_h->{icon} = "$FW_icondir/default/$param_h->{icon}" if( $param_h->{icon} !~ '^/' );

    Log3 $name, 5, "$name: using icon $param_h->{icon}";

    local( *FH ) ;
    open( FH, $param_h->{icon} );
    my $icon = do { local( $/ ) ; <FH> } ;

    return "icon not found: $param_h->{icon}" if( !$icon );
    delete $param_h->{icon};


    if( !$txt ) {
      my $usage = "usage: set $name msg";
      foreach my $option ( sort keys %{$options}) {
        if( $options->{$option} ) {
          $usage .= " [$option=". join( '|', sort keys %{$options->{$option}} ). "]";
        } else {
          $usage .= " [$option=<$option>]";
        }
      }
      #$usage .= " [duration=<duration>]";
      #$usage .= " [offset=<offset>]";
      #$usage .= " [offsety=<offsety>]";
      #$usage .= " [icon=<filename>]";
      #$usage .= " [title=<title>]";
      #$usage .= " [imageurl=<url>]";
      $usage .= " <message>";

      return $usage;
    }

    my $param;
    $param->{url}        = "http://$hash->{host}:7676/";
    $param->{callback}   = \&NotifyAndroidTV_parseHttpAnswer;
    $param->{hash}       = $hash;
    $param->{cl} = $hash->{CL} if( ref($hash->{CL}) eq 'HASH' );
    $param->{noshutdown} = 1;
    $param->{timeout}    = 5;
    $param->{loglevel}   = 5;
    $param->{method}     = "POST";
    $param->{header}     = "Content-Type: multipart/form-data; boundary=boundary";

    $param->{data} .= NotifyAndroidTV_addFormField('msg', $txt);
    foreach my $option (keys %{$param_h}) {
      $param->{data} .= NotifyAndroidTV_addFormField($option, $param_h->{$option})
    }
    Log3 $name, 5, $param->{data};

    $param->{data} .= NotifyAndroidTV_addFormField('filename', $icon, "filename=\"fhemicon.png\"\r\nContent-Type: application/octet-stream");
    $param->{data} .= "--boundary--";

    Log3 $name, 4, "NotifyAndroidTV ($name) - send notification ";
    #Log3 $name, 5, $param->{data};

    my ($err, undef) = HttpUtils_NonblockingGet($param);

    Log3 $name, 5, "NotifyAndroidTV ($name) - received http response code ".$param->{code} if(exists($param->{code}));

    if ($err) {
      Log3 $name, 3, "NotifyAndroidTV ($name) - got error while sending notificaton $err";
      return "got error while sending notification $err";
    }
    return;
  }

  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list";
}

sub
NotifyAndroidTV_Get($$@)
{
  my ($hash, $name, $cmd, @params) = @_;

  my $list = '';

  $list =~ s/ $//;
  return "Unknown argument $cmd, choose one of $list";
}

sub
NotifyAndroidTV_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");

  my $hash = $defs{$name};
  if( $attrName eq 'disable' ) {
  }


  if( $cmd eq "set" ) {
    if($options->{$attrName} && !defined($options->{$attrName}{$attrVal})) {
      return "$attrName value must be one of: ". join( ' ', sort keys %{$options->{$attrName}} );
    }
  }

  return;
}

1;

=pod
=item summary    Notifications for Android TV/Fire TV module
=item summary_DE Notifications for Android TV/Fire TV Modul
=begin html

<a name="NotifyAndroidTV"></a>
<h3>NotifyAndroidTV</h3>
<ul>
  This module allows you to send notifications to the
  <a href ='https://play.google.com/store/apps/details?id=de.cyberdream.androidtv.notifications.google'>
  Notifications for Android TV</a> and 
  <a href ='https://www.amazon.de/Christian-Fees-Notifications-for-Fire/dp/B00OESCXEK'>
  Notifications for Fire TV</a> apps.
  <br><br>
  <code>set &lt;name&gt; msg bkgcolor=amber interrupt=true position=top-left transparency=0% duration=2 offset=10 icon=fhemicon title="der titel" das ist ein test</code>

  <br><br>


  <a name="NotifyAndroidTV_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NotifyAndroidTV &lt;host&gt;</code>
    <br><br>
  </ul>

  <a name="NotifyAndroidTV_Set"></a>
  <b>Set</b>
  <ul>
    <li>msg [options] &lt;message&gt;<br>
    possible options are: bkgcolor, interrupt, position, transparency, duration, offset, offsety, type, icon, title, imageurl. use <code>set &lt;name&gt; notify</code> to see valid values.</li>
  </ul><br>

  <a name="NotifyAndroidTV_Get"></a>
  <b>Get</b>
  <ul>none
  </ul><br>

  <a name="NotifyAndroidTV_Attr"></a>
  <b>Attr</b>
  <ul>none
  </ul>

</ul><br>

=end html
=cut
