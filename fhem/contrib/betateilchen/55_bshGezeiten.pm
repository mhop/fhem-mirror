##############################################
# $Id$
package main;

use strict;
use warnings;
use HTML::TreeBuilder::XPath;

sub bshGezeiten_Initialize($) {
  my ($hash) = @_;

#  $hash->{SetFn}     = "bshG_Set";
  $hash->{DefFn}     = "bshG_Define";
  $hash->{UndefFn}   = "bshG_Undefine";
  $hash->{AttrList}  = "bsh_skipOutdated:1,0 " .
                       $readingFnAttributes;
}

###################################

sub bshG_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use define <name> bshGezeiten <location>" if(int(@a) != 3);

  $hash->{'.url'}       = "http://mobile.bsh.de/cgi-bin/gezeiten/was_mobil.pl?ort=__LOC__&zone=Gesetzliche+Zeit&niveau=KN";
  $hash->{'.url'} =~ s/__LOC__/$a[2]/;
  _bsh_pegel($hash);
  readingsSingleUpdate($hash, 'state', 'initialized', 1);
  return undef;
}

sub bshG_Undefine($) {
   my ($hash) = @_;
   RemoveInternalTimer($hash);
   return;
}   
   
sub _bsh_pegel($) {
   my ($hash) = @_;
   my $name = $hash->{NAME};
#   my $next = computeAlignTime("01:00", "00:01");
#   $hash->{TRIGGERTIME}     = $next;
#   $hash->{TRIGGERTIME_FMT} = FmtDateTime($next);
   InternalTimer(gettimeofday()+3600, "_bsh_pegel", $hash, 0);
   HttpUtils_NonblockingGet({ 
      hash       => $hash,
      timeout    => 5,
      url        => $hash->{'.url'},
      callback   => \&_bsh_pegel_cb,
  })
}

sub _bsh_pegel_cb($){
  my ($param, $err, $content) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
     $hash->{'.content'} = $content;
  _bsh_decode($hash,$content);   
}

sub _bsh_decode($$) {
  my ($hash,$content) = @_;
  my $name = $hash->{NAME};
  
  my $tree= HTML::TreeBuilder::XPath->new;
  $tree->parse($content);
  my @ort = $tree->findvalues(q{//strong});
  my (undef,undef,$ort) = split(/ /,$ort[1],3);
  $ort = latin1ToUtf8($ort);
  my @values = $tree->findvalues(q{//table//tr});
  my $counter = 0;
  my $year = (split(/ /,localtime(time)))[4];
  readingsBeginUpdate($hash);
  foreach my $v (@values){
    next if(length($v) < 2);
    #Sa16.12.HW03:09 4.0�m
    my $d = substr($v,2,6);
    my $w = substr($v,8,2);
    my $t = substr($v,10,5);
    my $h = substr($v,15,4);
    if (AttrVal($name,'bsh_skipOutdated',1)) {
      my ($day1,$month1) = split(/\./,$d);
      my ($hour1,$min1)  = split(/:/,$t);
      my $x = time_str2num "$year-$month1-$day1 $hour1:$min1:00";
      next if time > $x;
    }
	$counter++;
	readingsBulkUpdate($hash, sprintf('Meldung.%02s',$counter), "$w $d $t $h");
	last if ($counter == 8);
  }
  readingsBulkUpdate($hash,'Pegelname',$ort);
  readingsBulkUpdate($hash,'state','active');
  readingsEndUpdate($hash,1);
}


1;
