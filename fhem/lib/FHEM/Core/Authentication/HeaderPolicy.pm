##############################################
# $Id$
#
# FHEM::Core::Authentication::HeaderPolicy
# parse, validate and evaluate header authentication policies
#
# Author: Sidey
# Version: 0.1.0
#
package FHEM::Core::Authentication::HeaderPolicy;

use strict;
use warnings;

use Exporter qw(import);
use JSON::PP qw(decode_json);

our $VERSION = '0.1.0';

our @EXPORT_OK = qw(
  evaluate_header_auth_policy
  parse_header_auth_policy
  validate_header_auth_policy
);

sub parse_header_auth_policy {
  my ($raw) = @_;

  return (undef, 'header auth policy is undefined') if(!defined $raw);
  return ($raw, undef) if(ref($raw) eq 'HASH');
  return (undef, 'header auth policy must be a JSON object or hash reference')
    if(ref($raw));

  my $policy;
  eval { $policy = decode_json($raw); 1 }
    or return (undef, "invalid header auth policy JSON: $@");

  return (undef, 'header auth policy must decode to a JSON object')
    if(ref($policy) ne 'HASH');

  return ($policy, undef);
}

sub validate_header_auth_policy {
  my ($policy) = @_;

  return 'header auth policy must be a hash reference'
    if(ref($policy) ne 'HASH');

  return _validate_node($policy, 'policy');
}

sub evaluate_header_auth_policy {
  my ($policy, $headers) = @_;

  my $error = validate_header_auth_policy($policy);
  return (undef, $error) if($error);

  return (undef, 'headers must be a hash reference')
    if(ref($headers) ne 'HASH');

  my %normalized = map { (lc($_) => defined($headers->{$_}) ? $headers->{$_} : undef) }
                   keys %{$headers};

  return (_evaluate_node($policy, \%normalized), undef);
}

sub _validate_node {
  my ($node, $path) = @_;

  if(exists $node->{op}) {
    return "missing items array in $path"
      if(ref($node->{items}) ne 'ARRAY');
    return "empty items array in $path"
      if(!@{$node->{items}});
    return "invalid op in $path: $node->{op}"
      if($node->{op} !~ m/^(AND|OR)$/);

    for(my $idx = 0; $idx < @{$node->{items}}; $idx++) {
      my $item = $node->{items}[$idx];
      return "item $idx in $path must be a hash reference"
        if(ref($item) ne 'HASH');
      my $error = _validate_node($item, "$path.items[$idx]");
      return $error if($error);
    }

    return;
  }

  return "missing header in $path" if(!defined($node->{header}) || ref($node->{header}));
  return "missing match in $path" if(!defined($node->{match}) || ref($node->{match}));

  my %match_needs_value = map { $_ => 1 } qw(equals notEquals regex contains prefix suffix);
  my %known_match = map { $_ => 1 } qw(present equals notEquals regex contains prefix suffix);

  return "unknown match type in $path: $node->{match}"
    if(!$known_match{$node->{match}});

  return "missing value for $node->{match} in $path"
    if($match_needs_value{$node->{match}} && !defined($node->{value}));

  if($node->{match} eq 'regex') {
    my $ok = eval { '' =~ m/$node->{value}/; 1 };
    return "invalid regex in $path: $@" if(!$ok);
  }

  return;
}

sub _evaluate_node {
  my ($node, $headers) = @_;

  if(exists $node->{op}) {
    if($node->{op} eq 'AND') {
      for my $item (@{$node->{items}}) {
        return 0 if(!_evaluate_node($item, $headers));
      }
      return 1;
    }

    for my $item (@{$node->{items}}) {
      return 1 if(_evaluate_node($item, $headers));
    }
    return 0;
  }

  my $value = $headers->{lc($node->{header})};
  my $match = $node->{match};

  return (defined($value) && $value ne '') ? 1 : 0 if($match eq 'present');
  return 0 if(!defined($value));

  return $value eq $node->{value} ? 1 : 0 if($match eq 'equals');
  return $value ne $node->{value} ? 1 : 0 if($match eq 'notEquals');
  return $value =~ m/$node->{value}/ ? 1 : 0 if($match eq 'regex');
  return index($value, $node->{value}) == 0 ? 1 : 0 if($match eq 'prefix');
  return substr($value, -length($node->{value})) eq $node->{value} ? 1 : 0 if($match eq 'suffix');

  if($match eq 'contains') {
    my @parts = map {
      my $part = $_;
      $part =~ s/^\s+//;
      $part =~ s/\s+$//;
      $part;
    } split(',', $value);
    return (scalar grep { $_ eq $node->{value} } @parts) ? 1 : 0;
  }

  return 0;
}

1;
