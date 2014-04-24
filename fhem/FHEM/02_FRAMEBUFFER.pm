#
#
# 02_FRAMEBUFFER.pm
# written by Kai Stuke
# based on 02_RSS.pm 
#
##############################################
# $Id: $

package main;
use strict;
use warnings;
use GD;
use feature qw/switch/;
use vars qw(%data);
use Scalar::Util qw(looks_like_number);

require "02_RSS.pm"; # enable use of layout files and image creation

my %sets = (
	'updateDisplay' => "",
	'relLayoutNo' => "",
	'absLayoutNo' => "",
	'layoutFilename' => "",
);


##################################################
# Forward declarations
#
##################
sub FRAMEBUFFER_Initialize($);
sub FRAMEBUFFER_rewindCounter($);
sub FRAMEBUFFER_readLayout($);
sub FRAMEBUFFER_Define($$);
sub FRAMEBUFFER_updateDisplay($);
sub FRAMEBUFFER_Set($@);
sub FRAMEBUFFER_Attr(@);
sub FRAMEBUFFER_returnPNG($);


sub
FRAMEBUFFER_Initialize($) {
    my ($hash) = @_;
    $hash->{DefFn}   = "FRAMEBUFFER_Define";
    $hash->{AttrFn}  = "FRAMEBUFFER_Attr";
    $hash->{AttrList} = 'loglevel:0,1,2,3,4,5,6 update_interval:1,2,5,10,20,30 ' .
	                'size layoutBasedir layoutList startLayoutNo debugFile bgcolor ' . $readingFnAttributes;
    $hash->{SetFn}   = "FRAMEBUFFER_Set";
    $hash->{UndefFn}  = 'FRAMEBUFFER_Undef';
}

sub FRAMEBUFFER_Undef($$) {
	my ($hash, $arg) = @_;
	
	RemoveInternalTimer($hash);
	return undef;
}
 
##################
sub FRAMEBUFFER_rewindCounter($) {
	my ($hash) = @_;
	my $name= $hash->{NAME};
	my $updateInterval = AttrVal($hash->{NAME}, 'update_interval', 0);
	
	Log3 $name, 5, "rewindCounter $updateInterval"; 
	if ($updateInterval > 0) {
		# round to the begin of the next minute to get a more accurate time display
		my $currentTime = time();
		my $triggerTime = int(($currentTime + ($updateInterval * 60))/60)*60;
		Log3 $name, 5, "current $currentTime next trigger at $triggerTime";
		InternalTimer($triggerTime, 'FRAMEBUFFER_rewindCounter', $hash, 0);
	}
	FRAMEBUFFER_updateDisplay($hash);
}
 
##################
sub FRAMEBUFFER_readLayout($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};

  my $filename= $hash->{fhem}{filename};
  if (!defined $filename) {
	return 0;
  }
  
  if (defined $hash->{layoutBasedir} && substr($filename,0,1) ne '/') {
	$filename = $hash->{layoutBasedir} . '/' . $filename;
  }

  if(open(LAYOUT, $filename)) {
    my @layout= <LAYOUT>;
    $hash->{fhem}{layout}= join("", @layout);
    close(LAYOUT);
    return 1;
  } else {
    $hash->{fhem}{layout}= ();
    Log3 $name, 1, "Cannot open $filename";
    return 0;
  }
}  
 
##################
sub FRAMEBUFFER_Define($$) {

  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def);

  return "Usage: define <name> FRAMEBUFFER framebuffer_device"  if(int(@a) != 3);
  my $name= $a[0];
  my $fb_device= $a[2];

  if (! (-r $fb_device && -w $fb_device)) {
	return "$fb_device isn't readable and writable";
  }
  $hash->{fhem}{fb_device}= $fb_device;


  readingsSingleUpdate($hash, 'state', 'Initialized',1);
  return undef;
}

##################
sub FRAMEBUFFER_updateDisplay($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $fbv = '/usr/local/bin/fbvs';
  
  if (-x $fbv) {
	if (defined $hash->{debugFile}) {
		use File::Spec;
		my $dfile = $hash->{debugFile};
                my($vol,$dir,$file) = File::Spec->splitpath($dfile);
		if ((-e $dfile && -w $dfile) || -w $dir) { 
			$fbv = "tee $dfile | $fbv";
		}
	}  

	if (FRAMEBUFFER_readLayout($hash)) {
		open(FBV, "|".$fbv . ' -d '. $hash->{fhem}{fb_device});
		binmode FBV;
		print FBV FRAMEBUFFER_returnPNG($name);
		close FBV;
	}
  } else {
	Log3 $name, 1, "$fbv doesn't exist or isn't executable, please install it";
	
  }
}

##################
sub
FRAMEBUFFER_Set($@) {

  my ($hash, @a) = @_;

  my $name =$a[0];
  my $cmd = $a[1];
  my $val = $a[2];
  my $val2 = $a[3];

  # usage check
  my $usage= "Unknown argument, choose one of " . join(' ', keys %sets);
  if (@a == 2) {
    if ($cmd eq "updateDisplay") {
	# just display the current layout again
      FRAMEBUFFER_updateDisplay($hash);
      $usage = undef;
    }
  } elsif (@a == 3 || @a == 4) { 
     if ($cmd eq "absLayoutNo") {
	my $layoutNo = (defined($val) && looks_like_number($val) && $val >= 0) ? $val : 0;
	my @layoutList = split(/ /,$hash->{layoutList});
	my $noOfLayouts = @layoutList;

	if ($val < $noOfLayouts) {	
		$hash->{fhem}{filename} = $layoutList[$layoutNo];
		$hash->{fhem}{absLayoutNo} = $layoutNo;
		FRAMEBUFFER_updateDisplay($hash);
		$usage = undef;
	} else {
		$usage = "absLayoutNo out of bounds, must be between 0 and $noOfLayouts";
	}
    } elsif ($cmd eq "relLayoutNo") {
	my $relLayoutNo = (defined($val) && looks_like_number($val)) ? $val : 0;
	my @layoutList = split(/ /,$hash->{layoutList});
	my $noOfLayouts = @layoutList;
	
	if ($noOfLayouts > 0) {
		$hash->{fhem}{absLayoutNo} += $relLayoutNo;
		if ($hash->{fhem}{absLayoutNo} > $noOfLayouts-1) {
			$hash->{fhem}{absLayoutNo} = $noOfLayouts-1;
		} elsif ($hash->{fhem}{absLayoutNo} < 0) {
			$hash->{fhem}{absLayoutNo} = 0;
		}
		$hash->{fhem}{filename} = $layoutList[$hash->{fhem}{absLayoutNo}];
		FRAMEBUFFER_updateDisplay($hash);
		$usage = undef;
	} else {
		$usage = "layoutList is empty, please set that attribute first";
	}
    } elsif ($cmd eq "layoutFilename") {
	my $timeout = (defined($val2) && looks_like_number($val2) && $val2 >= 0) ? $val2 : 0;
	my $prevFilename = $hash->{fhem}{filename};
	$hash->{fhem}{filename} = $val;
	FRAMEBUFFER_updateDisplay($hash);
	if ($timeout > 0) {
		# nach timeout Sekunden wieder das aktuelle Layout anzeigen
		RemoveInternalTimer($hash);
		$hash->{fhem}{filename} = $prevFilename;
		InternalTimer(time() + $timeout, 'FRAMEBUFFER_rewindCounter', $hash, 0);
	}
	$usage = undef;
    }
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"absLayoutNo", $hash->{fhem}{absLayoutNo});
    readingsBulkUpdate($hash,"layoutFilename", $hash->{fhem}{filename});
    readingsEndUpdate($hash,1);
  }
  return $usage;
}


###################
sub
FRAMEBUFFER_Attr(@)
{
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	Log3 $name, 5, "attr " . $attr . " val " . $val; 
	if ($attr eq 'debugFile') {
		$hash->{debugFile} = $val;
	} elsif ($attr eq 'update_interval') {
		my $updateInterval = (defined($val) && looks_like_number($val) && $val >= 0) ? $val : -1;

		
		if ($updateInterval >= 0) {
			if ($updateInterval != AttrVal($hash->{NAME}, 'update_interval', 0)) {
				RemoveInternalTimer($hash);
				$hash->{updateInterval} = $updateInterval;
				if ($val > 0) {
					InternalTimer(1, 'FRAMEBUFFER_rewindCounter', $hash, 0);
				}
			}
		} else {
			$msg = 'Wrong update_interval defined. update_interval must be a number >= 0';
		}
        } elsif ($attr eq 'layoutBasedir') {
		my $layoutBasedir = $val;
		
		if (-d $val && -r $val) {
			$hash->{layoutBasedir} = $val;
		} else {
			$msg = "$val is not a readable directory";
		}
		
	} elsif ($attr eq 'layoutList') {
		$hash->{layoutList} = $val;
	} elsif ($attr eq 'startLayoutNo') {
		# Beim start des Moduls das anzuzeigenden Layout aus diesem Attribut nehmen
		if (!defined $hash->{fhem}{absLayoutNo}) {
			fhem "set $name absLayoutNo $val" ;
		}
	} elsif ($attr eq 'bgcolor') {
	}
	

	return ($msg) ? $msg : undef;  
}



##################
sub
FRAMEBUFFER_returnPNG($) {
  my ($name)= @_;

  my ($width,$height)= split(/x/, AttrVal($name,"size","128x160"));

  #
  # increase counter
  #
  if(defined($defs{$name}{fhem}) && defined($defs{$name}{fhem}{counter})) {
    $defs{$name}{fhem}{counter}++;
  } else {
    $defs{$name}{fhem}{counter}= 1;
  }

  # true color
  GD::Image->trueColor(1);
  
  #
  # create the image
  #
  my $S;
  # let's create a blank image, we will need it in most cases. 
  $S= GD::Image->newTrueColor($width,$height);
  my $bgcolor = AttrVal($name,'bgcolor','000000'); #default bg color = black
  $bgcolor = RSS_color($S, $bgcolor);
  # $S->colorAllocate(0,0,0); # other colors seem not to work (issue with GD)
  $S->fill(0,0,$bgcolor);

  # wrap to make problems with GD non-lethal

    #
    # evaluate layout
    #
    eval { RSS_evalLayout($S, $name, $defs{$name}{fhem}{layout}) };
    Log3 $name, 1, "Problem with layout " . $defs{$name}{fhem}{layout} . ", maybe wrong syntax or included images don't exist: $@" if $@ ne "";

  #
  # return png image
  #
  return $S->png(0);
}
  



1;




=pod
=begin html

<a name="FRAMEBUFFER"></a>
<h3>FRAMEBUFFER</h3>
<ul>
  Provides a device to display arbitrary content on a linux framebuffer device<p>

  You need to have the perl module <code>GD</code> installed. This module is most likely not
  available for small systems like Fritz!Box.<p>
  FRAMEBUFFER uses <a href="#RSS">RSS</a> to create an image that is displayed on the framebuffer.<br>
  The binary program fbvs is required to display the image. You can download it from <a href="https://github.com/kaihs/fbvs">github</a>.
  </p>

  <a name="FRAMEBUFFERdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FRAMEBUFFER &lt;framebuffer_device_name&gt;</code><br><br>

    Defines a framebuffer device. <code>&lt;framebuffer_device_name&gt;</code> is the name of the linux
    device file for the kernel framebuffer device, e.g. /dev/fb1 or /dev/fb0.
    
    Examples:
    <ul>
      <code>define display FRAMEBUFFER /dev/fb1</code><br>
      <code>define TV FRAMEBUFFER /dev/fb0</code><br>
    </ul>
    <br>
  </ul>

  <a name="FRAMBUFFERset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; absLayoutNo &lt;number&gt;</code>
    <br><br>
    A list of layout files can be defined with <code>attr layoutList</code>, see below.
    This command selects the layout with the given number from this list and displays it.
    This can e.g. be useful if bound to a key of a remote control to display a specific layout.
    <br><br>
  </ul>
  <ul>
    <code>set &lt;name&gt; layoutFilename &lt;name&gt; [&lt;timeout in seconds&gt;]</code>
    <br><br>
    Displays the image described by the layout in file &lt;name&gt;. If &lt;name&gt; is an absolute path
    name it is used as is to access the file. Otherwise the attribute  &lt;layoutBasedir&gt; is prepended to 
    the &lt;name&gt;.
    If a timeout is given, the image is only displayed for timeout seconds before the previously displayed image
    is displayed again.
    Useful for displaying an image only for a certain time after an event has occured.
    <br><br>
  </ul>
  <ul>
    <code>set &lt;name&gt; relLayoutNo &lt;number&gt;</code>
    <br><br>
    Like absLayoutNo this displays a certain image from the layoutList. Here &lt;number&gt; is added to the current
    layout number. 
    So<br>
    <code>set &lt;name&gt; relLayoutNo 1</code>
    displays the next image from the list while<br>
    <code>set &lt;name&gt; relLayoutNo -1</code><br>
    displays the previous one.
    Useful if bound to a next/previous key on a remote control to scroll through all defined layouts.
    <br><br>
  </ul>
  <ul>
    <code>set &lt;name&gt; updateDisplay</code>
    <br><br>
    Refreshes the display defined by the currently active layout.
    <br><br>
  </ul>

  <a name="FRAMEUFFERattr"></a>
  <b>Attributes</b>
  <br>
  <ul>
    <code>size &lt;width&gt;x&lt;height&gt;</code><br>
    The dimensions of the display in pixels.
    Images will generated using this size. If the size is greater than the actual display
    size they will be scaled to fit. As this requires computing performance it should be avoided by
    defining the size to match the display size.
    <br>Example<br>
    <code>attr &lt;name&gt; size 128x160</code>
    <br><br>
  </ul>
  <ul>
    <code>layoutBasedir &lt;directory name&gt;</code><br>
    Directory that contains the layout files. If a layout filename is specified using a relative path 
    <code>layoutBasedir</code> will be prepended before accessing the file.
    <br>Example<br>
    <code>attr &lt;name&gt; layoutBasedir /opt/fhem/layouts</code>
    <br><br>
  </ul>
  <ul>
    <code>layoutList &lt;file1&gt; [&lt;file2&gt;] ...</code>
    <br>Space separated list of layout files.
    These will be used by <code>absLayoutNo</code> and <code>relLayoutNo</code>.
    <code>layoutBasedir</code> will be prepended to each file if it is a relative path.
    <br>Example<br>
    <code>attr &lt;name&gt; layoutList standard.txt wetter.txt schalter.txt</code>
    <br><br>
  </ul>
  <ul>
    <code>update_interval &lt;interval&gt;</code>
    <br>Update interval in minutes.
    The currently displayed layout will be refreshed every &lt;interval&gt; minutes. The first
    interval will be scheduled to the beginning of the next minute to help create an accurate
    time display.<br>
    <br>Example<br>
    <code>attr &lt;name&gt; update_interval 1</code>
    <br><br>
  </ul>
  <ul>
    <code>debugFile &lt;file&gt;</code><br>
    Normally the generated image isn't written to a file. To ease debugging of layouts the generated image is written to the
    filename specified by this attribute.
    This attribute shouldn't be set during normal operation.
    <br><br>
  </ul>
  <ul>
    <code>startLayoutNo &lt;number&gt;</code><br>
    The number of the layout to be displayed on startup of the FRAMEBUFFER device. 
    <br><br>
  </ul>
  <ul>bgcolor &lt;color&gt;<br>Sets the background color. &lt;color&gt; is 
    a 6-digit hex number, every 2 digits  determining the red, green and blue 
    color components as in HTML color codes (e.g.<code>FF0000</code> for red, <code>C0C0C0</code> for light gray).
  </ul>
  <br><br>

  <b>Usage information</b>
  <br>
  <ul>
  This module requires the binary program fbvs to be installed in /usr/local/bin and it must be executable
  by user fhem.
  fbvs (framebuffer viewer simple) is a stripped down version of fbv that can only display png images. It reads
  the image from stdin, displays it on the framebuffer and terminates afterwards.
  This module generates a png image based on a layout description internally and then pipes it to fbvs for display.

  </ul>
  <br>

  <a name="FRAMEBUFFERlayout"></a>
  <b>Layout definition</b>
  <br>
  <ul>
    FRAMEBUFFER uses the same <a href="#RSSlayout">layout definition</a> as <a href="#RSS">RSS</a>. In fact FRAMEBUFFER calls RSS to generate an image.
  </ul>

</ul>

=end html
=cut
