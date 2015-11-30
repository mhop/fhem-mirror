package RPCQueue;

use strict;
use IO::File;
use Fcntl 'SEEK_END', 'SEEK_SET', 'O_CREAT', 'O_RDWR';
use Carp qw(carp croak);

our $VERSION = '1.01';

sub new
{
  my $class = shift;
  my $mi = $class . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  # convert to lower case
  my @keylist = keys %params;
  foreach my $key (@keylist) {
    my $val = $params{$key};
    delete $params{$key};
    $params{ lc($key) } = $val;
  }

  croak "$mi needs an File parameter" unless exists $params{file};
  my $queue_file = delete $params{file};
  my $idx_file = $queue_file . '.idx';
  $queue_file .= '.dat';

  my $self;
  my $mode = delete $params{mode} || '0600';
  $self->{block_size} = delete $params{blocksize} || 64;
  $self->{seperator} = delete $params{seperator} || "\n";
  $self->{sep_length} = length $self->{seperator};

  croak "Seperator length cannot be greater than BlockSize" if ($self->{sep_length} > $self->{block_size});

  $self->{queue_file} = $queue_file;
  $self->{idx_file} = $idx_file;

  $self->{queue} = new IO::File $queue_file, O_CREAT | O_RDWR, $mode or croak $!;
  $self->{idx} = new IO::File $idx_file, O_CREAT | O_RDWR, $mode or croak $!;

  ### Default ptr to 0, replace it with value in idx file if one exists
  $self->{idx}->sysseek(0, SEEK_SET); 
  $self->{idx}->sysread($self->{ptr}, 1024);
  $self->{ptr} = '0' unless $self->{ptr};
  
  if($self->{ptr} > -s $queue_file)
  {
    carp "Ptr is greater than queue file size, resetting ptr to '0'";

    $self->{idx}->truncate(0) or croak "Could not truncate idx: $!";
    $self->{idx}->sysseek(0, SEEK_SET); 
    $self->{idx}->syswrite('0') or croak "Could not syswrite to idx: $!";
  }

  bless $self, $class;
  return $self;
}

sub enq
{
  my ($self, $element) = @_;

  $self->{queue}->sysseek(0, SEEK_END); 

  if(ref $element)
  {
    croak 'Cannot handle references';
  }

  if($element =~ s/$self->{seperator}//g)
  {
    carp "Removed illegal seperator(s) from $element";
  }

  $self->{queue}->syswrite("$element$self->{seperator}") or croak "Could not syswrite to queue: $!";  
}

sub deq
{
  my $self = shift;
  my $element;

  $self->{queue}->sysseek($self->{ptr}, SEEK_SET);

  my $i;
  while($self->{queue}->sysread($_, $self->{block_size}))
  {

    $i = index($_, $self->{seperator});
    if($i != -1)
    {
      $element .= substr($_, 0, $i);
      $self->{ptr} += $i + $self->{sep_length};
      $self->{queue}->sysseek($self->{ptr}, SEEK_SET);

      last;
    }
    else
    {
      ## If seperator isn't found, go back 'sep_length' spaces to ensure we don't miss it between reads
      $element .= substr($_, 0, -$self->{sep_length}, '');
      $self->{ptr} += $self->{block_size} - $self->{sep_length};
      $self->{queue}->sysseek($self->{ptr}, SEEK_SET);
    }
  }

  ## If queue seek pointer is at the EOF, truncate the queue file
  if($self->{queue}->sysread($_, 1) == 0)
  {
    $self->{queue}->truncate(0) or croak "Could not truncate queue: $!";
    $self->{queue}->sysseek($self->{ptr} = 0, SEEK_SET);
  }

  ## Set idx file contents to point to the current seek position in queue file
  $self->{idx}->truncate(0) or croak "Could not truncate idx: $!";
  $self->{idx}->sysseek(0, SEEK_SET);
  $self->{idx}->syswrite($self->{ptr}) or croak "Could not syswrite to idx: $!";

  return $element;
}

sub peek
{
  my ($self, $count) = @_;
  croak "Invalid argument to peek ($count)" unless $count > 0;

  my $elements;

  $self->{queue}->sysseek($self->{ptr}, SEEK_SET);

  my (@items, $remainder);
GATHER:
  while($self->{queue}->sysread($_, $self->{block_size}))
  {
    if(defined $remainder)
    {
      $_ = $remainder . $_;
    }

    @items = split /$self->{seperator}/, $_, -1;
    $remainder = pop @items;

    foreach (@items)
    {
      push @$elements, $_;
      last GATHER if $count == @$elements;
    }
  }

  return $elements;
}

sub reset
{
  my $self = shift;

  $self->{idx}->truncate(0) or croak "Could not truncate idx: $!";
  $self->{idx}->sysseek(0, SEEK_SET); 
  $self->{idx}->syswrite('0') or croak "Could not syswrite to idx: $!";

  $self->{queue}->sysseek($self->{ptr} = 0, SEEK_SET); 
}

sub close
{
  my $self = shift;

  $self->{idx}->close();
  $self->{queue}->close();
}

sub delete
{
  my $self = shift;

  $self->close();

  unlink $self->{queue_file};
  unlink $self->{idx_file};
}

1;
