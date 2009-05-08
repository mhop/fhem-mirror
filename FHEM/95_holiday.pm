##############################################
package main;

use strict;
use warnings;
use POSIX;

sub holiday_refresh($$);

#####################################
sub
holiday_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "holiday_Define";
  $hash->{GetFn}    = "holiday_Get";
  $hash->{UndefFn}  = "holiday_Undef";
}


#####################################
sub
holiday_Define($$)
{
  my ($hash, $def) = @_;

  return holiday_refresh($hash->{NAME}, undef);
}

sub
holiday_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($name);
  return undef;
}

sub
holiday_refresh($$)
{
  my ($name, $fordate) = (@_);
  my $hash = $defs{$name};
  my $internal;

  return if(!$hash);           # Just deleted

  my $nt = gettimeofday();
  my @lt = localtime($nt);
  my @fd;
  if(!$fordate) {
    $internal = 1;
    $fordate = sprintf("%02d-%02d", $lt[4]+1, $lt[3]);
    @fd = @lt;
  } else {
    my ($m,$d) = split("-", $fordate);
    @fd = localtime(mktime(1,1,1,$d,$m-1,$lt[5],0,0,-1));
  }

  my $fname = $attr{global}{modpath} . "/FHEM/" . $hash->{NAME} . ".holiday";
  return "Can't open $fname: $!" if(!open(FH, $fname));
  my $found = "none";
  while(my $l = <FH>) {
    next if($l =~ m/^\s*#/);
    next if($l =~ m/^\s*$/);
    chomp($l);

    if($l =~ m/^1/) {               # Exact date: 1 MM-DD Holiday
      my @args = split(" +", $l, 3);
      if($args[1] eq $fordate) {
        $found = $args[2];
        last;
      }

    } elsif($l =~ m/^2/) {          # Easter date: 2 +1 Ostermontag

      eval { require DateTime::Event::Easter } ;

      if( $@) {
        Log 1, "$@";

      } else {
        my @a = split(" +", $l, 3);
        my $dt = DateTime::Event::Easter->new(day=>$a[1])
                          ->following(DateTime->new(year=>(1900+$lt[5])));
        next if($dt->day != $fd[3] || $dt->month != $fd[4]+1);
        $found = $a[2];
        last;
      }

    } elsif($l =~ m/^3/) {          # Relative date: 3 -1 Mon 03 Holiday
      my @a = split(" +", $l, 5);
      my %wd = ("Sun"=>0, "Mon"=>1, "Tue"=>2, "Wed"=>3,
                "Thu"=>4, "Fri"=>5, "Sat"=>6);
      my @md = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
      my $wd = $wd{$a[2]};
      if(!defined($wd)) {
        Log 1, "Wrong timespec: $l";
        next;
      }
      next if($wd != $fd[6]);       # Weekday
      next if($a[3] != ($fd[4]+1)); # Month
      if($a[1] > 0) {               # N'th day from the start
        my $d = $fd[3] - ($a[1]-1)*7;
        next if($d < 1 || $d > 7);
      } elsif($a[1] < 0) {          # N'th day from the end
        my $d = $fd[3] - ($a[1]+1)*7;
        my $md = $md[$fd[4]];
        $md++ if($fd[5]%4 == 0);
        next if($d > $md || $d < $md-6);
      }

      $found = $a[4];
      last;

    } elsif($l =~ m/^4/) {          # Interval: 4 MM-DD MM-DD Holiday
      my @args = split(" +", $l, 4);
      if($args[1] le $fordate && $args[2] ge $fordate) {
        $found = $args[3];
        last;
      }
    }
  }

  RemoveInternalTimer($name);
  $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0]);         # Midnight
  $nt += 86400 + 2;                              # Tomorrow
  $hash->{TRIGGERTIME} = $nt;
  InternalTimer($nt, "holiday_refresh", $name, 0);

  if($internal) {
    $hash->{STATE} = $found;
    return undef;
  } else {
    return $found;
  }

}

sub
holiday_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);
  return "wrong argument: need MM-DD" if($a[1] !~ m/[01]\d-[0-3]\d/);
  return holiday_refresh($hash->{NAME}, $a[1]);
}

1;
