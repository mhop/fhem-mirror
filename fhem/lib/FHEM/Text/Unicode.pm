################################################################
# $Id$
# Maintainer: Adimarantis
# Library to convert ASCII into formatted Unicode and apply styles like bold or emoticons
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################

package FHEM::Text::Unicode;
use strict;
use warnings; 
use Exporter 'import';
our @EXPORT_OK = qw (formatTextUnicode formatStringUnicode demoUnicode demoUnicodeHTML);
our %EXPORT_TAGS = (ALL => [@EXPORT_OK]);

#define globally for demo
#Emoticons
my @mrep = (
	[":\\)","\x{1F600}"],
	[":-\\)","\x{1F600}"],
	[":\\(","\x{1F641}"],
	["<3","\x{2665}"],
	[";-\\)","\x{1F609}"],
	[":\\+1:","\x{1F44D}"],
	[":smile:","\x{1F600}"],
	[":sad:","\x{1F641}"],
	[":heart:","\x{2665}"],
	[":wink:","\x{1F609}"],
	[":thumbsup:","\x{1F44D}"],
	);
#html like styles
my @htags = (
	["bold" ,"<b>","</b>"],
	["italic","<i>","</i>"],
	["bold-italic","<bi>","</bi>"],
	["mono","<tt>","</tt>"],
	["mono","<code>","</code>"],
	["underline","<u>","</u>"],
	["strikethrough","<s>","</s>"],
	["fraktur","<fraktur>","</fraktur>"],
	["script","<script>","</script>"],
	["square","<square>","</square>"],
);
#Single replacements in html mode
my @hrep = (
	["<br>","\n"],
);
#Markdown styles
my @mtags = (
	["italic","__","__"],
	["strikethrough","~~","~~"],
	["bold","\\*\\*","\\*\\*"],
	["mono","``","``"],
);

#Convert text with Markdown/html to Unicode
#Arguments:
#$format:
# html: Only apply HTML-like formatting like <x>....</x>
# markdown: Only apply Markdown formatting like __text__ and emoticon replacements
# both: Apply both formatting styles
#$msg: ASCII String that should be replaced
#returns: Unicode string with applied replacements
#To display all replacements use the demoUnicode() or demoUnicodeHTML() function
sub formatTextUnicode($$) {
    my ($format,$msg) = @_;
	my @tags;
	my @reps;
	
	if ($format eq "markdown" || $format eq "both") {
		push @tags, @mtags;
		push @reps, @mrep;
	}
	if ($format eq "html" || $format eq "both") {
		push @tags, @htags;
		push @reps, @hrep;
	}

	#First pass, replace singe special characters
	foreach my $arr (@reps) {
		my @val=@$arr;
		$msg =~ s/$val[0]/$val[1]/sg;
	}

	my $found=1;
	my $matches=0;
	my $text;
	while ($found && $matches<100) {
		$matches++;
		$found=0;
		foreach my $arr (@tags) {
			my @val=@$arr;
			$msg =~ /$val[1](.*?)$val[2]/s;
			if (defined $1) {
				$text=formatStringUnicode($val[0],$1);
				if (defined $text) {
					$msg =~ s/$val[1].*?$val[2]/$text/s;
					$found=1;
				}
			}
		}
	}
	return $msg;
}

#Converts normal ASCII into unicode with a special font or style
#$font: Style to be applied: underline, strikethrough, bold, italic, bold-italic, script, fraktur, square, mono
#$str: ASCII String that should be converted
#returns: Unicode String with style applied
sub formatStringUnicode($$) {
	my ($font,$str) = @_;
	
	if ($font eq "underline") {
		$str =~ s/./$&\x{332}/g;
		return $str;
	}
	if ($font eq "strikethrough") {
		$str =~ s/./$&\x{336}/g;
		return $str;
	}

	my %uc = (
		"bold" => [0x1d41a,0x1d400,0x1d7ce],
		"italic" => [0x1d44e,0x1d434,0x30],
		"bold-italic" => [0x1d482,0x1d468,0x30],
		"script" => [0x1d4ea,0x1d4d0,0x30],	#Using boldface since normal misses some letters
		"fraktur" => [0x1d586,0x1d56c,0x30],#Using boldface since normal misses some letters
		"square" => [0x1f130,0x1f130,0x30],
		"mono" => [0x1d68a,0x1d670,0x30],
	);

	return undef if (! defined $uc{$font});

	my $rep=chr($uc{$font}[0])."-".chr($uc{$font}[0]+25).chr($uc{$font}[1])."-".chr($uc{$font}[1]+25).chr($uc{$font}[2])."-".chr($uc{$font}[2]+9);
	$_=$str;
	#"no warnings" to prevent a bug in older Perl versions (seen in 5.28) that warns about
	#"Replacement list is longer than search list" when using ASCII->Unicode replacements
	eval "{no warnings; tr/a-zA-Z0-9/$rep/}";
	return undef if $@;
#Special handling for characters missing in some fonts
#	0x1d455 => 0x1d629, #italic h -> italic sans-serif h or 0x210e (planck constant)
#	0x1d4ba => 0x1d452, #script e -> serif e (not used -> using bold script charset which is complete
	$_ =~ tr/\x{1d455}\x{1d4ba}/\x{1d629}\x{1d452}/;
	return $_;
}

# Returns a String that is can be embedded in HTML (e.g. FHEM "get") and showcases all possible replacements and their syntax
sub demoUnicodeHTML {
	my $str=demoUnicode();
	$str =~ s/</&lt/sg;
	$str =~ s/</&gt/sg;
	$str =~ s/\n/<br>/sg;
	return $str;
}

# Returns a printable String that showcases all possible replacements and their syntax	
sub demoUnicode {
	my $str;
	$str.="HTML style formatting:\n";
	foreach my $arr (@htags) {
		my @val=@$arr;
		$str .= formatStringUnicode($val[0],$val[0]." TEXT 123").": $val[1]text$val[2]\n";
	}
	$str.="newline: <br>\n";

	$str.="\nMarkdown style formatting:\n";
	foreach my $arr (@mtags) {
		my @val=@$arr;
		my $md= formatStringUnicode($val[0],$val[0]." TEXT 123").": $val[1]text$val[2]\n";
		$md =~ s/\\//g;
		$str.=$md;
	}
	my $i=0;
	foreach my $arr (@mrep) {
		my @val=@$arr;
		my $emo=$val[0];
		$emo =~ s/\\//g;
		$str.="$val[1]=$emo ";
		$i++;
		if ($i>5) {
			$str.="\n";
			$i=0;
		}
	}	
	return $str;
}

1;
