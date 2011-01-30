##############################################
package main;

use strict;
use warnings;
use POSIX;
#use Devel::Size qw(size total_size);



sub SVG_render($$$$$$$);
sub time_to_sec($);
sub fmtTime($$);


my ($SVG_lt, $SVG_ltstr);

#####################################
sub
SVG_Initialize($)
{
  my ($hash) = @_;
}


#####################################
sub
SVG_render($$$$$$$)
{
  my $name = shift;  # e.g. wl_8
  my $from = shift;  # e.g. 2008-01-01
  my $to = shift;    # e.g. 2009-01-01
  my $confp = shift; # lines from the .gplot file, w/o FileLog and plot
  my $dp = shift;    # pointer to data (one string)
  my $plot = shift;  # Plot lines from the .gplot file
  my $SVG_ss = shift;  # small screen

  return "" if(!defined($dp));

  my $th = 16;                          # "Font" height
  my ($x, $y) = (($SVG_ss ? 2 : 3)*$th,  1.2*$th);      # Rect offset
  my %conf;                             # gnuplot file settings

  # Convert the configuration to a "readable" form -> array to hash
  map { chomp; my @a=split(" ",$_, 3);
         if($a[0] && $a[0] eq "set") { $conf{$a[1]} = $a[2]; } } @{$confp};

  my $ps = "800,400";
  $ps = $1 if($conf{terminal} =~ m/.*size[ ]*([^ ]*)/);
  $conf{title} =~ s/'//g;

  my ($ow,$oh) = split(",", $ps);       # Original width
  my ($w, $h) = ($ow-2*$x, $oh-2*$y);   # Rect size

 # Html Header
  pO '<?xml version="1.0" encoding="UTF-8"?>';
  pO '<!DOCTYPE svg>';
  pO '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" '.
         'xmlns:xlink="http://www.w3.org/1999/xlink" >';

  pO "<style type=\"text/css\"><![CDATA[";
  if(open(FH, "$FW_dir/svg_style.css")) {
    pO join("", <FH>);
    close(FH);
  } else {
    Log 0, "Can't open $FW_dir/svg_style.css"
  }
  pO "]]></style>";

  if(open(FH, "$FW_dir/svg_defs.svg")) { # gradient definitions
    pO join("", <FH>);
    close(FH);
  } else {
    Log 0, "Can't open $FW_dir/svg_defs.svg"
  }

  # Background
  pO "<rect width =\"$ow\" height=\"$oh\" class=\"background\"/>";
  # Rectangle
  pO "<rect x=\"$x\" y=\"$y\" width =\"$w\" height =\"$h\" rx=\"8\" ry=\"8\" ".
        "fill=\"none\" class=\"border\"/>";

  my ($off1,$off2) = ($ow/2, 3*$y/4);
  my $title = ($conf{title} ? $conf{title} : " ");
  $title =~ s/</&lt;/g;
  $title =~ s/>/&gt;/g;
  pO "<text id=\"svg_title\" x=\"$off1\" y=\"$off2\" " .
        "class=\"title\" text-anchor=\"middle\">$title</text>";

  pO "<text id=\"svg_paste\" x=\"" . ($ow-$x) . "\" y=\"$off2\" " .
        "onclick=\"parent.svg_paste(evt)\" " .
        "class=\"paste\" text-anchor=\"end\"> </text>";
  pO "<text id=\"svg_copy\" x=\"" . ($ow-2*$x) . "\" y=\"$off2\" " .
        "onclick=\"parent.svg_copy(evt)\" " .
        "class=\"copy\" text-anchor=\"end\"> </text>";


  my $t = ($conf{ylabel} ? $conf{ylabel} : "");
  $t =~ s/"//g;
  if(!$SVG_ss) {
    ($off1,$off2) = (3*$th/4, $oh/2);
    pO "<text x=\"$off1\" y=\"$off2\" text-anchor=\"middle\" " .
        "class=\"ylabel\" transform=\"rotate(270,$off1,$off2)\">$t</text>";

    $t = ($conf{y2label} ? $conf{y2label} : "");
    $t =~ s/"//g;
    ($off1,$off2) = ($ow-$th/4, $oh/2);
    pO "<text x=\"$off1\" y=\"$off2\" text-anchor=\"middle\" " .
        "class=\"y2label\" transform=\"rotate(270,$off1,$off2)\">$t</text>";
  }

  # Digest axes/title/type from $plot (gnuplot) and draw the line-titles
  my (@axes,@ltitle,@type);
  my $i;
  $i = 0; $plot =~ s/ axes (\w+)/$axes[$i++]=$1/gse;
  $i = 0; $plot =~ s/ title '([^']*)'/$ltitle[$i++]=$1/gse;
  $i = 0; $plot =~ s/ with (\w+)/$type[$i++]=$1/gse;

  for my $i (0..int(@type)-1) {         # axes is optional
    $axes[$i] = "x1y2" if(!$axes[$i]);
  }

  ($off1,$off2) = ($ow-$x-$th, $y+$th);



  for my $i (0..int(@ltitle)-1) {
    my $j = $i+1;
    my $t = $ltitle[$i];
    my $desc = "";
    if(defined($data{"min$j"}) && $data{"min$j"} ne "undef") {
      $desc = sprintf("%s: Min:%g Max:%g Last:%g",
        $t, $data{"min$j"}, $data{"max$j"}, $data{"currval$j"});
    }
    pO "<text title=\"$desc\" ".
          "onclick=\"parent.svg_labelselect(evt)\" line_id=\"line_$i\" " .
          "x=\"$off1\" y=\"$off2\" text-anchor=\"end\" class=\"l$i\">$t</text>";
    $off2 += $th;
  }

  # Loop over the input, digest dates, calculate min/max values
  my ($fromsec, $tosec);
  $fromsec = time_to_sec($from) if($from ne "0"); # 0 is special
  $tosec   = time_to_sec($to)   if($to ne "9");   # 9 is special
  my $tmul; 
  $tmul = $w/($tosec-$fromsec) if($tosec && $fromsec);

  my ($min, $max, $idx) = (99999999, -99999999, 0);
  my (%hmin, %hmax, @hdx, @hdy);
  my ($dxp, $dyp) = (\(), \());

  my ($d, $v, $ld, $lv) = ("","","","");

  my ($dpl,$dpoff,$l) = (length($$dp), 0, "");
  while($dpoff < $dpl) {                # using split instead is memory hog
    my $ndpoff = index($$dp, "\n", $dpoff);
    if($ndpoff == -1) {
      $l = substr($$dp, $dpoff);
    } else {
      $l = substr($$dp, $dpoff, $ndpoff-$dpoff);
    }
    $dpoff = $ndpoff+1;
    if($l =~ m/^#/) {
      my $a = $axes[$idx];
      if(defined($a)) {
        $hmin{$a} = $min if(!defined($hmin{$a}) || $hmin{$a} > $min);
        $hmax{$a} = $max if(!defined($hmax{$a}) || $hmax{$a} < $max);
      }
      ($min, $max) = (99999999, -99999999);
      $hdx[$idx] = $dxp; $hdy[$idx] = $dyp;
      ($dxp, $dyp) = (\(), \());
      $idx++;

    } else {
      ($d, $v) = split(" ", $l);

      $d =  ($tmul ? int((time_to_sec($d)-$fromsec)*$tmul) : $d);
      if($ld ne $d || $lv ne $v) {              # Saves a lot on year zoomlevel
        $ld = $d; $lv = $v;
        push @{$dxp}, $d;
        push @{$dyp}, $v;
        $min = $v if($min > $v);
        $max = $v if($max < $v);
      }
    }
    last if($ndpoff == -1);
  }

  $dxp = $hdx[0];
  if($dxp && int(@{$dxp}) < 2 && !$tosec) { # not enough data and no range...
    pO "</svg>";
    return;
  }

  if(!$tmul) {                     # recompute the x data if no range sepcified
    $fromsec = time_to_sec($dxp->[0]) if(!$fromsec);
    $tosec = time_to_sec($dxp->[int(@{$dxp})-1]) if(!$tosec);
    $tmul = $w/($tosec-$fromsec);

    for my $i (0..@hdx-1) {
      $dxp = $hdx[$i];
      for my $i (0..@{$dxp}-1) {
        $dxp->[$i] = int((time_to_sec($dxp->[$i])-$fromsec)*$tmul);
      }
    }
  }


  # Compute & draw vertical tics, grid and labels
  my $ddur = ($tosec-$fromsec)/86400;
  my ($first_tag, $tag, $step, $tstep, $aligntext,  $aligntics);
  if($ddur <= 0.5) {
    $first_tag=". 2 1"; $tag=": 3 4"; $step = 3600; $tstep = 900;
  } elsif($ddur <= 1.1) {       # +0.1 -> DST
    $first_tag=". 2 1"; $tag=": 3 4"; $step = 4*3600; $tstep = 3600;
  } elsif ($ddur <= 7.1) {
    $first_tag=". 6";   $tag=". 2 1"; $step = 24*3600; $tstep = 6*3600;
  } elsif ($ddur <= 31.1) {
    $first_tag=". 6";   $tag=". 2 1"; $step = 7*24*3600; $tstep = 24*3600;
    $aligntext = 1;
  } else {
    $first_tag=". 6";   $tag=". 1";   $step = 28*24*3600; $tstep = 28*24*3600;
    $aligntext = 2; $aligntics = 2;
  }

  # First the tics
  $off2 = $y+4;
  my ($off3, $off4) = ($y+$h-4, $y+$h);
  my $initoffset = $tstep;
  $initoffset = int(($tstep/2)/86400)*86400 if($aligntics);
  for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $tstep) {
    $i = time_align($i,$aligntics);
    $off1 = int($x+($i-$fromsec)*$tmul);
    pO "<polyline points=\"$off1,$y $off1,$off2\"/>";
    pO "<polyline points=\"$off1,$off3 $off1,$off4\"/>";
  }

  # then the text and the grid
  $off1 = $x;
  $off2 = $y+$h+$th;
  $t = fmtTime($first_tag, $fromsec);
  pO "<text x=\"0\" y=\"$off2\" class=\"ylabel\">$t</text>";
  $initoffset = $step;
  $initoffset = int(($step/2)/86400)*86400 if($aligntext);
  for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $step) {
    $i = time_align($i,$aligntext);
    $off1 = int($x+($i-$fromsec)*$tmul);
    $t = fmtTime($tag, $i);
    pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\" " .
              "text-anchor=\"middle\">$t</text>";
    pO "  <polyline points=\"$off1,$y $off1,$off4\" class=\"hgrid\"/>";
  }


  # Left and right axis tics / text / grid
  $hmin{x1y1}=$hmin{x1y2}, $hmax{x1y1}=$hmax{x1y2} if(!defined($hmin{x1y1}));
  $hmin{x1y2}=$hmin{x1y1}, $hmax{x1y2}=$hmax{x1y1} if(!defined($hmin{x1y2}));


  for my $axis ("x1y1", "x1y2") {

    # Round values, compute a nice step
    next if(!defined($hmax{$axis}));

    # yrange handling
    my $yr = ($axis eq "x1y1" ? "yrange" : "y2range");
    if($conf{$yr} && $conf{$yr} =~ /\[(.*):(.*)\]/) {
      $hmin{$axis} = $1 if($1 ne "");
      $hmax{$axis} = $2 if($2 ne "");
    }

    my $dh = $hmax{$axis} - $hmin{$axis};
    my ($step, $mi, $ma) = (1, 1, 1);
    my @limit = (1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,
                 20000,50000,100000,200000,500000,1000000,2000000);
    for my $li (0..int(@limit)-1) {
      my $l = $limit[$li];
      next if($dh > $l);
      $ma = doround($hmax{$axis}, $l/10, 1);
      $mi = doround($hmin{$axis}, $l/10, 0);

      if(($ma-$mi)/($l/10) >= 7) {    # If more then 7 steps, then choose next
        $l = $limit[$li+1];
        $ma = doround($hmax{$axis}, $l/10, 1);
        $mi = doround($hmin{$axis}, $l/10, 0);
      }
      $step = $l/10;
      last;
    }
    $hmax{$axis} = $ma;
    $hmin{$axis} = $mi;

    # Draw the horizontal values and grid
    my $hmul = $h/($ma-$mi);
    $off1 = ($axis eq "x1y1" ? $x-$th*0.3 : $x+$w+$th*0.3);
    $off3 = ($axis eq "x1y1" ? $x : $x+$w-5);
    $off4 = $off3+5;

    $yr = ($axis eq "x1y1" ? "ytics" : "y2tics");
    my $tic = $conf{$yr};
    if($tic && $tic !~ m/mirror/) {     # Tics specified in the configfile
      $tic =~ s/^\((.*)\)$/$1/;   # Strip ()
      foreach my $onetic (split(",", $tic)) {
        $onetic =~ s/^ *(.*) *$/$1/;
        my ($tlabel, $tvalue) = split(" ", $onetic);
        $tlabel =~ s/^"(.*)"$/$1/;

        $off2 = int($y+($ma-$tvalue)*$hmul);
        pO "<polyline points=\"$off3,$off2 $off4,$off2\"/>";
        $off2 += $th/4;
        my $align = ($axis eq "x1y1" ? " text-anchor=\"end\"" : "");
        pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>
                $tlabel</text>";
      }

    } else {                             # Auto-tic

      for(my $i = $mi; $i <= $ma; $i += $step) {
        $off2 = int($y+($ma-$i)*$hmul);
        pO "  <polyline points=\"$off3,$off2 $off4,$off2\"/>";
        if($axis eq "x1y2")  {
          my $o6 = $x+$w;
          pO "  <polyline points=\"$x,$off2 $o6,$off2\" class=\"vgrid\"/>"
            if($i > $mi && $i < $ma);
        }
        $off2 += $th/4;
        my $align = ($axis eq "x1y1" ? " text-anchor=\"end\"" : "");
        my $txt = sprintf("%g", $i);
        pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$txt</text>";
      }
    }

  }


  # Second loop over the data: draw the measured points
  for my $idx (0..int(@hdx)-1) {
    my $a = $axes[$idx];

    next if(!defined($a));
    $min = $hmin{$a};
    $hmax{$a} += 1 if($min == $hmax{$a});  # Else division by 0 in the next line
    my $hmul = $h/($hmax{$a}-$min);
    my $ret = "";
    my ($dxp, $dyp) = ($hdx[$idx], $hdy[$idx]);
    next if(!defined($dxp));

    my $yh = $y+$h;
    my $tl = $ltitle[$idx] ? $ltitle[$idx]  : "";
    my $dec = int(log($hmul*3)/log(10));
    $dec = 0 if($dec < 0);
    my $js_helpers = "id=\"line_$idx\" decimals=\"$dec\" ".
          "x_off=\"$fromsec\" x_min=\"$x\" x_mul=\"$tmul\" ".
          "y_h=\"$yh\" y_min=\"$min\" y_mul=\"$hmul\" title=\"$tl\" ".
          "onclick=\"parent.svg_click(evt)\"";

    my ($lx, $ly) = (-1,-1);
    if($type[$idx] eq "points" ) {

        foreach my $i (0..int(@{$dxp})-1) {
          my ($x1, $y1) = (int($x+$dxp->[$i]),
                           int($y+$h-($dyp->[$i]-$min)*$hmul));
          next if($x1 == $lx && $y1 == $ly);
          $ly = $x1; $ly = $y1;
          $ret =  sprintf(" %d,%d %d,%d %d,%d %d,%d %d,%d",
                $x1-3,$y1, $x1,$y1-3, $x1+3,$y1, $x1,$y1+3, $x1-3,$y1);
          pO "<polyline $js_helpers points=\"$ret\" class=\"l$idx\"/>";
        }

    } elsif($type[$idx] eq "steps" || $type[$idx] eq "fsteps" ) {

      if(@{$dxp} == 1) {
          my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
      } else {
        foreach my $i (1..int(@{$dxp})-1) {
          my ($x1, $y1) = ($x+$dxp->[$i-1], $y+$h-($dyp->[$i-1]-$min)*$hmul);
          my ($x2, $y2) = ($x+$dxp->[$i],   $y+$h-($dyp->[$i]  -$min)*$hmul);
          next if(int($x2) == $lx && int($y1) == $ly);
          $lx = int($x2); $ly = int($y2);
          if($type[$idx] eq "steps") {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x2,$y1, $x2,$y2);
          } else {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x1,$y2, $x2,$y2);
          }
        }
      }
      pO "<polyline $js_helpers points=\"$ret\" class=\"l$idx\"/>";

    } elsif($type[$idx] eq "histeps" ) {
      if(@{$dxp} == 1) {
          my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
      } else {
        foreach my $i (1..int(@{$dxp})-1) {
          my ($x1, $y1) = ($x+$dxp->[$i-1], $y+$h-($dyp->[$i-1]-$min)*$hmul);
          my ($x2, $y2) = ($x+$dxp->[$i],   $y+$h-($dyp->[$i]  -$min)*$hmul);
          next if(int($x2) == $lx && int($y1) == $ly);
          $lx = int($x2); $ly = int($y2);
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
             $x1,$y1, ($x1+$x2)/2,$y1, ($x1+$x2)/2,$y2, $x2,$y2);
        }
      }
      pO "<polyline $js_helpers points=\"$ret\" class=\"l$idx\"/>";

    } else {                            # lines and everything else
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));
        next if($x1 == $lx && $y1 == $ly);
        $lx = $x1; $ly = $y1;
        $ret .=  sprintf(" %d,%d", $x1, $y1);
      }

      pO "<polyline $js_helpers points=\"$ret\" class=\"l$idx\"/>";
    
    }

  }
  pO "</svg>";
}

sub
time_to_sec($)
{
  my ($str) = @_;
  if(!$str) {
    return 0;
  }
  my ($y,$m,$d,$h,$mi,$s) = split("[-_:]", $str);
  $s = 0 if(!$s);
  $mi= 0 if(!$mi);
  $h = 0 if(!$h);
  $d = 1 if(!$d);
  $m = 1 if(!$m);

  if(!$SVG_ltstr || $SVG_ltstr ne "$y-$m-$d-$h") { # 2.5x faster
    $SVG_lt = mktime(0,0,$h,$d,$m-1,$y-1900,0,0,-1);
    $SVG_ltstr = "$y-$m-$d-$h";
  }
  return $s+$mi*60+$SVG_lt;
}

sub
fmtTime($$)
{
  my ($sepfmt, $sec) = @_;
  my @tarr = split("[ :]+", localtime($sec));
  my ($sep, $fmt) = split(" ", $sepfmt, 2);
  my $ret = "";
  for my $f (split(" ", $fmt)) {
    $ret .= $sep if($ret);
    $ret .= $tarr[$f];
  }
  return $ret;
}

sub
time_align($$)
{
  my ($v,$align) = @_;
  return $v if(!$align);
  if($align == 1) {             # Look for the beginning of the week
    for(;;) {
      my @a = localtime($v);
      return $v if($a[6] == 0);
      $v += 86400;
    }
  }
  if($align == 2) {             # Look for the beginning of the month
    for(;;) {
      my @a = localtime($v);
      return $v if($a[3] == 1);
      $v += 86400;
    }
  }
}

sub
doround($$$)
{
  my ($v, $step, $isup) = @_;
  if($v >= 0) {
    return (int($v/$step))*$step+($isup ? $step : 0);
  } else {
    return (int($v/$step))*$step+($isup ? 0 : -$step);
  }
}
1;
