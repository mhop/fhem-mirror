use strict;
use warnings;
package Net::MQTT::TopicStore;
$Net::MQTT::TopicStore::VERSION = '1.142010';
# ABSTRACT: Perl module to represent MQTT topic store


sub new {
  my $pkg = shift;
  my $self = bless { topics => { } }, $pkg;
  $self->add($_) foreach (@_);
  $self
}


sub add {
  my ($self, $topic_pattern) = @_;
  unless (exists $self->{topics}->{$topic_pattern}) {
    $self->{topics}->{$topic_pattern} = _topic_to_regexp($topic_pattern);
  }
  $topic_pattern
}


sub delete {
  my ($self, $topic) = @_;
  delete $self->{topics}->{$topic};
}


sub values {
  my ($self, $topic) = @_;
  my @res = ();
  foreach my $t (keys %{$self->{topics}}) {
    my $re = $self->{topics}->{$t};
    next unless (defined $re ? $topic =~ $re : $topic eq $t);
    push @res, $t;
  }
  return \@res;
}

sub _topic_to_regexp {
  my $topic = shift;
  my $c;
  $topic = quotemeta $topic;
  $c += ($topic =~ s!\\/\\\+!\\/[^/]*!g);
  $c += ($topic =~ s!\\/\\#$!(?:\$|/.*)!);
  $c += ($topic =~ s!^\\\+\\/![^/]*\\/!g);
  $c += ($topic =~ s!^\\\+$![^/]*!g);
  $c += ($topic =~ s!^\\#$!.*!);
  $topic .= '$' unless ($topic =~ m!\$$!);
  unless ($c) {
    return;
  }
  qr/^$topic/
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::TopicStore - Perl module to represent MQTT topic store

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  use Net::MQTT::TopicStore;
  my $topic_store = Net::MQTT::TopicStore->new();
  $topic_store->add($topic_pattern1);
  $topic_store->add($topic_pattern2);
  my @topics = @{ $topic->get($topic) };
  $topic_store->remove($topic_pattern2);

=head1 DESCRIPTION

This module encapsulates a single MQTT topic store.

=head1 METHODS

=head2 C<new( )>

Constructs a L<Net::MQTT::TopicStore> object.

=head2 C<add( $topic_pattern )>

Adds the topic pattern to the store.

=head2 C<delete( $topic_pattern )>

Remove the topic pattern from the store.

=head2 C<values( $topic )>

Returns all the topic patterns in the store that apply to the given topic.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
