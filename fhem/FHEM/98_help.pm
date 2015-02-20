# $Id: 98_help.pm 8032 2015-02-18 18:36:37Z betateilchen $
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
  my ($cl, $arg) = @_;

  my ($mod,$lang) = split(" ",$arg);

  $lang //= AttrVal('global','language','en');
  $lang = (lc($lang) eq 'de') ? '_DE' : '';

  if($mod) {

    $mod = lc($mod);
    my $modPath = AttrVal('global','modpath','.');
	my $output = "";

	if($mod ne 'global') {
      my %mods;
	  my @modDir = ("$modPath/FHEM");

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

	  my $skip = 1;
	  my ($err,@text) = FileRead({FileName => $mods{$mod}, ForceType => 'file'});
	  return $err if $err;
	  foreach my $l (@text) {
	    if($l =~ m/^=begin html$lang$/) {
	      $skip = 0;
	    } elsif($l =~ m/^=end html$lang$/) {
	      $skip = 1;
	    } elsif(!$skip) {
	      $output .= $l;
	    }
	  }

    } else {

      $output = '';
	  my $i;
	  my $f = "$modPath/docs/commandref_frame$lang.html";
      my $skip = 1;
	  my ($err,@text) = FileRead({FileName => $f, ForceType => 'file'});
	  return $err if $err;

	  foreach my $l (@text) {
        if($l =~ m/name=.global./) { 
           $skip = 0;
        } elsif($l =~ m/^<!-- global.end/) {
           $skip = 1;
        } elsif (!$skip) {
           $output .= $l;
        }
	  }   

	}

    $output = "Keine deutsche Hilfe gefunden!\n\n".
             CommandHelp(undef, "$mod en") unless $output;

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
    $output =~ s/&auml;/ä/g;
    $output =~ s/&Auml;/Ä/g;
    $output =~ s/&ouml;/ö/g;
    $output =~ s/&Ouml;/Ö/g;
    $output =~ s/&uuml;/ü/g;
    $output =~ s/&Uuml;/Ü/g;
    $output =~ s/&szlig;/ß/g;

    return $output;
    }

    return "<html>$output</html>";

  } else {   # mod

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
<h3>?, help</h3>
  <ul>
    <code>? [&lt;moduleName&gt;] [<language>]</code><br/>
    <code>help [&lt;moduleName&gt;] [<language>]</code><br/>
    <br/>
    <ul>
      <li>Returns a list of available commands, when called without a
        moduleName.</li>
      <li>Returns a module dependent helptext, same as in commandref.</li>
      <li>language will be determined in following order: 
         <ul>
         <li>valid parameter &lt;language&gt; given</li>
         <li>global attribute language</li>
         <li>nothing founde: return english</li>
         </ul>
      </li>
    </ul>
  </ul>

=end html

=begin html_DE

<a name="help"></a>
<h3>?, help</h3>
  <ul>
    <code>? [&lt;moduleName&gt;] [<language>]</code><br/>
    <code>help [&lt;moduleName&gt;] [<language>]</code><br/>
    <br>
    <ul>
      <li>Liefert eine Liste aller Befehle mit einer Kurzbeschreibung zur&uuml;ck.</li>
      <li>Falls moduleName spezifiziert ist, wird die modul-spezifische Hilfe
          aus commandref zur&uuml;ckgeliefert.</li>
      <li>Die anzuzeigende Sprache wird in folgender Reihenfolge bestimmt: 
         <ul>
         <li>g&uuml;ltiger Parameter &lt;language&gt; beim Aufruf &uuml;bergeben</li>
         <li>globales Attribut language</li>
         <li>falls alles fehlt: englisch</li>
         </ul>
      </li>
    </ul>
  </ul>
=end html_DE

=cut
