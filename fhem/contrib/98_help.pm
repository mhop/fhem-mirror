# $Id$
#
package main;
use strict;
use warnings;

sub CommandHelp;

sub help_Initialize($$) {
  my %hash = (  Fn => "CommandHelp",
		   Hlp => "[<moduleName>],get help (this screen or module dependent docu)" );
  $cmds{help} = \%hash;
}

sub CommandHelp {
  my ($cl, $mod) = @_;

  if($mod) {
    $mod = lc($mod);
    my %mods;
    my @modDir = ("FHEM");
    foreach my $modDir (@modDir) {
      opendir(DH, $modDir) || die "Cant open $modDir: $!\n";
      while(my $l = readdir DH) {
	    next if($l !~ m/^\d\d_.*\.pm$/);
	    my $of = $l;
	    $l =~ s/.pm$//;
	    $l =~ s/^[0-9][0-9]_//;
	    $mods{lc($l)} = "$modDir/$of";
      }
    }

    return "Module $mod not found" unless defined($mods{$mod});

    my $output = "";
    my $skip = 1;
    my ($err,@text) = FileRead({FileName => $mods{$mod}, ForceType => 'file'});
    return $err if $err;
    foreach my $l (@text) {
      if($l =~ m/^=begin html$/) {
	    $skip = 0;
      } elsif($l =~ m/^=end html$/) {
	    $skip = 1;
      } elsif(!$skip) {
	  $output .= $l;
    }
  }

  if( $cl  && $cl->{TYPE} eq 'telnet' ) { 
    $output =~ s/<br>/\n/g;
    $output =~ s/<br\/>/\n/g;
    $output =~ s/<\/a>//g;
    $output =~ s/<a.*>//g;
    $output =~ s/<ul>/\n/g;
    $output =~ s/<\/ul>/\n/g;
    $output =~ s/<li>/-/g;
    $output =~ s/<\/li>/\n/g;
    $output =~ s/<code>//g;
    $output =~ s/<\/code>//g;
    $output =~ s/&lt;/</g;
    $output =~ s/&gt;/>/g;
    $output =~ s/<[bui]>/\ /g;
    $output =~ s/<\/[bui]>/\ /g;
    $output =~ s/\ \ +/\ /g;
    $output =~ s/\t+/ /g;
    $output =~ s/\n\n/\n/g;
    return $output;
  }

  return "<html>$output</html>";

  } else {

    my $str = "\n" .
		"Possible commands:\n\n" .
		"Command   Parameter                 Description\n" .
	    "-----------------------------------------------\n";

    for my $cmd (sort keys %cmds) {
      next if(!$cmds{$cmd}{Hlp});
      next if($cl && $cmds{$cmd}{ClientFilter} &&
           $cl->{TYPE} !~ m/$cmds{$cmd}{ClientFilter}/);
      my @a = split(",", $cmds{$cmd}{Hlp}, 2);
      $str .= sprintf("%-9s %-25s %s\n", $cmd, $a[0], $a[1]);
    }

    return $str;

  }
}

1;

=pod
=begin html

<a name="help"></a>
<h3>help</h3>
  <ul>
    <code>help [&lt;moduleName&gt;]</code><br/>
    <br/>
    <ul>
      <li>returns a list of available commands, when called without a moduleName</li>
      <li>returns a module dependent helptext, same as in commandref</li>
    </ul>
  </ul>

=end html
=cut
