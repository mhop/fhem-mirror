##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
#use Devel::Size qw(size total_size);



sub SVG_render($$$$$$$$);
sub SVG_time_to_sec($);
sub SVG_fmtTime($$);
sub SVG_time_align($$);
sub SVG_doround($$$);
sub SVG_pO($);
my $SVG_RET;        # Returned data (SVG)


my ($SVG_lt, $SVG_ltstr);

#####################################
sub
SVG_Initialize($)
{
  my ($hash) = @_;
}


#####################################
sub
SVG_render($$$$$$$$)
{
  my $name = shift;  # e.g. wl_8
  my $from = shift;  # e.g. 2008-01-01
  my $to = shift;    # e.g. 2009-01-01
  my $confp = shift; # lines from the .gplot file, w/o FileLog and plot
  my $dp = shift;    # pointer to data (one string)
  my $plot = shift;  # Plot lines from the .gplot file
  my $parent_name = shift;  # e.g. FHEMWEB instance name
  my $parent_dir  = shift;  # FW_dir

  $SVG_RET="";

  my $SVG_ss = AttrVal($parent_name, "smallscreen", 0);
  return $SVG_RET if(!defined($dp));
  my $th = 16;                          # "Font" height
  my ($x, $y) = (($SVG_ss ? 2 : 3)*$th,  1.2*$th);      # Rect offset

  ######################
  # Convert the configuration to a "readable" form -> array to hash
  my %conf;                             # gnuplot file settings
  map { chomp; my @a=split(" ",$_, 3);
         if($a[0] && $a[0] eq "set") { $conf{lc($a[1])} = $a[2]; } } @{$confp};

  my $ps = "800,400";
  $ps = $1 if($conf{terminal} =~ m/.*size[ ]*([^ ]*)/);
  $conf{title} = "" if(!defined($conf{title}));
  $conf{title} =~ s/'//g;

  my ($ow,$oh) = split(",", $ps);       # Original width
  my ($w, $h) = ($ow-2*$x, $oh-2*$y);   # Rect size

  ######################
  # Html Header
  SVG_pO '<?xml version="1.0" encoding="UTF-8"?>';
  SVG_pO '<!DOCTYPE svg>';
  SVG_pO '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" '.
         'xmlns:xlink="http://www.w3.org/1999/xlink" >';

  my $prf = AttrVal($parent_name, "stylesheetPrefix", "");
  SVG_pO "<style type=\"text/css\"><![CDATA[";
  if(open(FH, "$parent_dir/${prf}svg_style.css") ||
     open(FH, "$parent_dir/svg_style.css")) {
    SVG_pO join("", <FH>);
    close(FH);
  } else {
    Log 0, "Can't open $parent_dir/svg_style.css"
  }
  SVG_pO "]]></style>";

  ######################
  # gradient definitions
  if(open(FH, "$parent_dir/${prf}svg_defs.svg") ||
     open(FH, "$parent_dir/svg_defs.svg")) {
    SVG_pO join("", <FH>);
    close(FH);
  } else {
    Log 0, "Can't open $parent_dir/svg_defs.svg"
  }

  ######################
  # Draw the background
  SVG_pO "<rect width =\"$ow\" height=\"$oh\" class=\"background\"/>";
  # Rectangle
  SVG_pO "<rect x=\"$x\" y=\"$y\" width =\"$w\" height =\"$h\" rx=\"8\" ry=\"8\" ".
        "fill=\"none\" class=\"border\"/>";

  my ($off1,$off2) = ($ow/2, 3*$y/4);
  my $title = ($conf{title} ? $conf{title} : " ");
  $title =~ s/</&lt;/g;
  $title =~ s/>/&gt;/g;
  SVG_pO "<text id=\"svg_title\" x=\"$off1\" y=\"$off2\" " .
        "class=\"title\" text-anchor=\"middle\">$title</text>";

  ######################
  # Copy and Paste labels, hidden by default
  SVG_pO "<text id=\"svg_paste\" x=\"" . ($ow-$x) . "\" y=\"$off2\" " .
        "onclick=\"parent.svg_paste(evt)\" " .
        "class=\"paste\" text-anchor=\"end\"> </text>";
  SVG_pO "<text id=\"svg_copy\" x=\"" . ($ow-2*$x) . "\" y=\"$off2\" " .
        "onclick=\"parent.svg_copy(evt)\" " .
        "class=\"copy\" text-anchor=\"end\"> </text>";

  ######################
  # Digest grid
  my $t = ($conf{grid} ? $conf{grid} : "");
  my $hasxgrid = ( $t =~ /.*xtics.*/ ? 1 : 0);
  my $hasygrid = ( $t =~ /.*ytics.*/ ? 1 : 0);
  my $hasy2grid = ( $t =~ /.*y2tics.*/ ? 1 : 0);
  
  ######################
  # Left label = ylabel and right label = y2label
  $t = ($conf{ylabel} ? $conf{ylabel} : "");
  $t =~ s/"//g;
  if(!$SVG_ss) {
    ($off1,$off2) = (3*$th/4, $oh/2);
    SVG_pO "<text x=\"$off1\" y=\"$off2\" text-anchor=\"middle\" " .
        "class=\"ylabel\" transform=\"rotate(270,$off1,$off2)\">$t</text>";

    $t = ($conf{y2label} ? $conf{y2label} : "");
    $t =~ s/"//g;
    ($off1,$off2) = ($ow-$th/4, $oh/2);
    SVG_pO "<text x=\"$off1\" y=\"$off2\" text-anchor=\"middle\" " .
        "class=\"y2label\" transform=\"rotate(270,$off1,$off2)\">$t</text>";
  }

  ######################
  # Digest axes/title/etc from $plot (gnuplot) and draw the line-titles
  my (@lAxis,@lTitle,@lType,@lStyle,@lWidth);
  my ($i, $pTemp);
  $pTemp = $plot; $i = 0; $pTemp =~ s/ axes (\w+)/$lAxis[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ title '([^']*)'/$lTitle[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ with (\w+)/$lType[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ ls (\w+)/$lStyle[$i++]=$1/gse;
  $pTemp = $plot; $i = 0; $pTemp =~ s/ lw (\w+)/$lWidth[$i++]=$1/gse;

  for my $i (0..int(@lType)-1) {         # lAxis is optional
    $lAxis[$i] = "x1y2" if(!$lAxis[$i]);
    $lStyle[$i] = "class=\"". (defined($lStyle[$i]) ? $lStyle[$i] : "l$i") . "\"";
    $lWidth[$i] = (defined($lWidth[$i]) ? "style=\"stroke-width:$lWidth[$i]\"" :"");
  }

  ($off1,$off2) = ($ow-$x-$th, $y+$th);


  ######################
  # Plot caption (title)
  for my $i (0..int(@lTitle)-1) {
    my $j = $i+1;
    my $t = $lTitle[$i];
    my $desc = "";
    if(defined($data{"min$j"}) && $data{"min$j"} ne "undef") {
      $desc = sprintf("%s: Min:%g Max:%g Last:%g",
        $t, $data{"min$j"}, $data{"max$j"}, $data{"currval$j"});
    }
    SVG_pO "<text title=\"$desc\" ".
          "onclick=\"parent.svg_labelselect(evt)\" line_id=\"line_$i\" " .
          "x=\"$off1\" y=\"$off2\" text-anchor=\"end\" $lStyle[$i]>$t</text>";
    $off2 += $th;
  }

  ######################
  # Loop over the input, digest dates, calculate min/max values
  my ($fromsec, $tosec);
  $fromsec = SVG_time_to_sec($from) if($from ne "0"); # 0 is special
  $tosec   = SVG_time_to_sec($to)   if($to ne "9");   # 9 is special
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
      my $a = $lAxis[$idx];
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

      $d =  ($tmul ? int((SVG_time_to_sec($d)-$fromsec)*$tmul) : $d);
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
    SVG_pO "</svg>";
    return $SVG_RET;
  }

  if(!$tmul) {                     # recompute the x data if no range sepcified
    $fromsec = SVG_time_to_sec($dxp->[0]) if(!$fromsec);
    $tosec = SVG_time_to_sec($dxp->[int(@{$dxp})-1]) if(!$tosec);
    $tmul = $w/($tosec-$fromsec);

    for my $i (0..@hdx-1) {
      $dxp = $hdx[$i];
      for my $i (0..@{$dxp}-1) {
        $dxp->[$i] = int((SVG_time_to_sec($dxp->[$i])-$fromsec)*$tmul);
      }
    }
  }


  ######################
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

  my $barwidth = $tstep;

  ######################
  # First the tics
  $off2 = $y+4;
  my ($off3, $off4) = ($y+$h-4, $y+$h);
  my $initoffset = $tstep;
  $initoffset = int(($tstep/2)/86400)*86400 if($aligntics);
  for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $tstep) {
    $i = SVG_time_align($i,$aligntics);
    $off1 = int($x+($i-$fromsec)*$tmul);
    SVG_pO "<polyline points=\"$off1,$y $off1,$off2\"/>";
    SVG_pO "<polyline points=\"$off1,$off3 $off1,$off4\"/>";
  }

  ######################
  # then the text and the grid
  $off1 = $x;
  $off2 = $y+$h+$th;
  $t = SVG_fmtTime($first_tag, $fromsec);
  SVG_pO "<text x=\"0\" y=\"$off2\" class=\"ylabel\">$t</text>";
  $initoffset = $step;
  $initoffset = int(($step/2)/86400)*86400 if($aligntext);
  for(my $i = $fromsec+$initoffset; $i < $tosec; $i += $step) {
    $i = SVG_time_align($i,$aligntext);
    $off1 = int($x+($i-$fromsec)*$tmul);
    $t = SVG_fmtTime($tag, $i);
    SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\" " .
              "text-anchor=\"middle\">$t</text>";
    SVG_pO "  <polyline points=\"$off1,$y $off1,$off4\" class=\"hgrid\"/>";
  }


  ######################
  # Left and right axis tics / text / grid
  #-- just in case we have only one data line, but want to draw both axes
  $hmin{x1y1}=$hmin{x1y2}, $hmax{x1y1}=$hmax{x1y2} if(!defined($hmin{x1y1}));
  $hmin{x1y2}=$hmin{x1y1}, $hmax{x1y2}=$hmax{x1y1} if(!defined($hmin{x1y2}));

  my (%hstep,%htics,%axdrawn);
  
  #-- yrange handling for axes x1y1..x1y8
  for my $idx (0..7)  {
    my $a = "x1y".($idx+1);
    next if( !defined($hmax{$a}) || !defined($hmin{$a}) );
    my $yra="y".($idx+1)."range";
    $yra="yrange" if ($yra eq "y1range");  
    #-- yrange is specified in plotfile
    if($conf{$yra} && $conf{$yra} =~ /\[(.*):(.*)\]/) {
      $hmin{$a} = $1 if($1 ne "");
      $hmax{$a} = $2 if($2 ne "");
    }
    #-- tics handling
    my $yt="y".($idx+1)."tics";
    $yt="ytics" if ($yt eq"y1tics");
    $htics{$a} = defined($conf{$yt}) ? $conf{$yt} : "";
    
    #-- Round values, compute a nice step  
    my $dh = $hmax{$a} - $hmin{$a};
    my ($step, $mi, $ma) = (1, 1, 1);
    my @limit = (0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100,
                 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000,
                 200000, 500000, 1000000, 2000000);
    for my $li (0..int(@limit)-1) {
      my $l = $limit[$li];
      next if($dh > $l);
      $ma = SVG_doround($hmax{$a}, $l/10, 1);
      $mi = SVG_doround($hmin{$a}, $l/10, 0);

      if(($ma-$mi)/($l/10) >= 7) {    # If more then 7 steps, then choose next
        $l = $limit[$li+1];
        $ma = SVG_doround($hmax{$a}, $l/10, 1);
        $mi = SVG_doround($hmin{$a}, $l/10, 0);
      }
      $step = $l/10;
      last;
    }
    $hmax{$a}    = $ma;
    $hmin{$a}    = $mi;
    $hstep{$a}   = $step;
    $axdrawn{$a} = 0;
    
    #Log 2, "Axis $a has interval [$hmin{$a},$hmax{$a}], step $hstep{$a}, tics $htics{$a}\n";
  }

  #-- run through all axes for drawing (each only once !) 
  foreach my $a (sort keys %hmin) {
    next if( $axdrawn{$a} );
    $axdrawn{$a}=1;
   
    #-- safeguarding against pathological data
    if( !$hstep{$a} ){
        $hmax{$a} = $hmin{$a}+1;
        $hstep{$a} = 1;
    }

    #-- Draw the y-axis values and grid
    my $dh = $hmax{$a} - $hmin{$a};
    my $hmul = $dh>0 ? $h/$dh : $h;
   
    # offsets
    my ($align,$display,$cll);
    if( $a eq "x1y1" ){
      # first axis = left
      $off1 = $x-4-$th*0.3;
      $off3 = $x-4;
      $off4 = $off3+5;
      $align = " text-anchor=\"end\"";
      $display = "";
      $cll = "";
    } elsif ( $a eq "x1y2" ){
      # second axis = right
      $off1 = $x+4+$w+$th*0.3;
      $off3 = $x+4+$w-5;
      $off4 = $off3+5;
      $align = "";
      $display = "";
      $cll = "";
    } else {
      # other axes in between
      $off1 = $x-$th*0.3+30;
      $off3 = $x+30;
      $off4 = $off3+5;
      $align = " text-anchor=\"end\"";
      $display = " display=\"none\" id=\"hline_$idx\"";
      $cll = " class=\"l$idx\"";
    };
    
    #-- grouping
    SVG_pO "<g$display>";
    my $yp = $y + $h;
    
    #-- axis if not left or right axis
    SVG_pO "<polyline points=\"$off3,$y $off3,$yp\" $cll/>" if( ($a ne "x1y1") && ($a ne "x1y2") );

    #-- tics handling
    my $tic = $htics{$a};
    #-- tics as in the config-file
    if($tic && $tic !~ m/mirror/) {     
      $tic =~ s/^\((.*)\)$/$1/;   # Strip ()
      foreach my $onetic (split(",", $tic)) {
        $onetic =~ s/^ *(.*) *$/$1/;
        my ($tlabel, $tvalue) = split(" ", $onetic);
        $tlabel =~ s/^"(.*)"$/$1/;
        $tvalue = 0 if( !$tvalue );

        $off2 = int($y+($hmax{$a}-$tvalue)*$hmul);
        #-- tics
        SVG_pO "<polyline points=\"$off3,$off2 $off4,$off2\" $cll/>";
        #--grids
        my $off6 = $x+$w;
        if( ($a eq "x1y1") && $hasygrid )  {
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($i > $hmin{$a} && $i < $hmax{$a});
        }elsif( ($a eq "x1y2") && $hasy2grid )  {
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($i > $hmin{$a} && $i < $hmax{$a});
        }
        $off2 += $th/4;
        #--  text
        SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$tlabel</text>";
      }
    #-- tics automatically 
    } elsif( $hstep{$a}>0 ) {            
      for(my $i = $hmin{$a}; $i <= $hmax{$a}; $i += $hstep{$a}) {
        $off2 = int($y+($hmax{$a}-$i)*$hmul);
        #-- tics
        SVG_pO "  <polyline points=\"$off3,$off2 $off4,$off2\" $cll/>";
        #--grids
        my $off6 = $x+$w;
        if( ($a eq "x1y1") && $hasygrid )  {
          my $off6 = $x+$w;
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($i > $hmin{$a} && $i < $hmax{$a});
        }elsif(  ($a eq "x1y2") && $hasy2grid )  {
          SVG_pO "  <polyline points=\"$x,$off2 $off6,$off2\" class=\"vgrid\"/>"
            if($i > $hmin{$a} && $i < $hmax{$a});
        }
        $off2 += $th/4;
        #--  text   
        my $txt = sprintf("%g", $i);
        SVG_pO "<text x=\"$off1\" y=\"$off2\" class=\"ylabel\"$align>$txt</text>";
      }
    }
    SVG_pO "</g>";

  }

  ######################
  # Second loop over the data: draw the measured points
  for(my $idx=$#hdx; $idx >= 0; $idx--) {
    my $a = $lAxis[$idx];

    SVG_pO "<!-- Warning: No axis for data item $idx defined -->" if(!defined($a));
    next if(!defined($a));
    $min = $hmin{$a};
    $hmax{$a} += 1 if($min == $hmax{$a});  # Else division by 0 in the next line
    my $hmul = $h/($hmax{$a}-$min);
    my $ret = "";
    my ($dxp, $dyp) = ($hdx[$idx], $hdy[$idx]);
    SVG_pO "<!-- Warning: No data item $idx defined -->" if(!defined($dxp));
    next if(!defined($dxp));

    my $yh = $y+$h;
    #-- Title attributes
    my $tl = $lTitle[$idx] ? $lTitle[$idx]  : "";
    #my $dec = int(log($hmul*3)/log(10)); # perl can be compiled without log() !
    my $dec = length(sprintf("%d",$hmul*3))-1;
    $dec = 0 if($dec < 0);
    my $attributes = "id=\"line_$idx\" decimals=\"$dec\" ".
          "x_off=\"$fromsec\" x_min=\"$x\" x_mul=\"$tmul\" ".
          "y_h=\"$yh\" y_min=\"$min\" y_mul=\"$hmul\" title=\"$tl\" ".
          "onclick=\"parent.svg_click(evt)\" $lWidth[$idx] $lStyle[$idx]";
    my $isFill = ($lStyle[$idx] =~ m/fill/);

    my ($lx, $ly) = (-1,-1);

    if($lType[$idx] eq "points" ) {
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));
        next if($x1 == $lx && $y1 == $ly);
        $ly = $x1; $ly = $y1;
        $ret =  sprintf(" %d,%d %d,%d %d,%d %d,%d %d,%d",
              $x1-3,$y1, $x1,$y1-3, $x1+3,$y1, $x1,$y1+3, $x1-3,$y1);
        SVG_pO "<polyline $attributes points=\"$ret\"/>";
      }

    } elsif($lType[$idx] eq "steps" || $lType[$idx] eq "fsteps" ) {

      $ret .=  sprintf(" %d,%d", $x+$dxp->[0], $y+$h) if($isFill && @{$dxp});
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
          if($lType[$idx] eq "steps") {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x2,$y1, $x2,$y2);
          } else {
            $ret .=  sprintf(" %d,%d %d,%d %d,%d", $x1,$y1, $x1,$y2, $x2,$y2);
          }
        }
      }
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);

      SVG_pO "<polyline $attributes points=\"$ret\"/>";

    } elsif($lType[$idx] eq "histeps" ) {
      $ret .=  sprintf(" %d,%d", $x+$dxp->[0], $y+$h) if($isFill && @{$dxp});
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
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);
      SVG_pO "<polyline $attributes points=\"$ret\"/>";

    } elsif( $lType[$idx] eq "bars" ) {
       if(@{$dxp} == 1) {
          my $y1 = $y+$h-($dyp->[0]-$min)*$hmul;
          $ret .=  sprintf(" %d,%d %d,%d %d,%d %d,%d",
                $x,$y+$h, $x,$y1, $x+$w,$y1, $x+$w,$y+$h);
       } else {
          $barwidth = $barwidth*$tmul;
          # bars are all of equal width (see far above !), 
          # position rounded to integer multiples of bar width
          foreach my $i (0..int(@{$dxp})-1) {
            my ($x1, $y1) = ( $x +4 + $dxp->[$i] - $barwidth,
                               $y +$h-($dyp->[$i]-$min)*$hmul);
            my ($x2, $y2) = ($barwidth, ($dyp->[$i]-$min)*$hmul);    
            SVG_pO "<rect $attributes x=\"$x1\" y=\"$y1\" width=\"$x2\" height=\"$y2\"/>";
         }
       }

    } else {                            # lines and everything else
      foreach my $i (0..int(@{$dxp})-1) {
        my ($x1, $y1) = (int($x+$dxp->[$i]),
                         int($y+$h-($dyp->[$i]-$min)*$hmul));
        next if($x1 == $lx && $y1 == $ly);
        $ret .=  sprintf(" %d,%d", $x1, $y+$h) if($i == 0 && $isFill);
        $lx = $x1; $ly = $y1;
        $ret .=  sprintf(" %d,%d", $x1, $y1);
      }
      #-- insert last point for filled line
      $ret .=  sprintf(" %d,%d", $lx, $y+$h) if($isFill && $lx > -1);

      SVG_pO "<polyline $attributes points=\"$ret\"/>";
    }

  }
  SVG_pO "</svg>";
  return $SVG_RET;
}

sub
SVG_time_to_sec($)
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
SVG_fmtTime($$)
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
SVG_time_align($$)
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
SVG_doround($$$)
{
  my ($v, $step, $isup) = @_;
  if($v >= 0) {
    return (int($v/$step))*$step+($isup ? $step : 0);
  } else {
    return (int($v/$step))*$step+($isup ? 0 : -$step);
  }
}

##################
# print (append) to output
sub
SVG_pO($)
{
  my $arg = shift;
  return if(!defined($arg));
  $SVG_RET .= $arg;
  $SVG_RET .= "\n";
}

1;
