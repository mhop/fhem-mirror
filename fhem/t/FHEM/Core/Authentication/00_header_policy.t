#!/usr/bin/env perl
use strict;
use warnings;

use Test2::V1 qw(is like subtest done_testing);
use Test2::Tools::Compare qw(array end field hash item match U);

use lib '.';
use lib './lib';

use FHEM::Core::Authentication::HeaderPolicy qw(
  evaluate_header_auth_policy
  parse_header_auth_policy
  validate_header_auth_policy
);

subtest 'parse valid JSON policy' => sub {
  my ($policy, $error) = parse_header_auth_policy(
    '{"op":"AND","items":[{"header":"X-Forwarded-User","match":"present"}]}'
  );

  is($error, U(), 'valid JSON policy parses without error');
  is(
    $policy,
    hash {
      field op => 'AND';
      field items => array {
        item hash {
          field header => 'X-Forwarded-User';
          field match => 'present';
          end;
        };
        end;
      };
      end;
    },
    'parsed policy structure matches expectation'
  );
};

subtest 'parse invalid JSON policy' => sub {
  my ($policy, $error) = parse_header_auth_policy('{"op":"AND"');

  is($policy, U(), 'invalid JSON returns no policy');
  like($error, qr/^invalid header auth policy JSON:/, 'invalid JSON returns parse error');
};

subtest 'validate rejects malformed policy' => sub {
  my $error = validate_header_auth_policy({
    op => 'AND',
    items => [
      {
        header => 'X-Test',
        match => 'regex',
        value => '[',
      }
    ],
  });

  like($error, qr/^invalid regex in policy\.items\[0\]:/, 'bad regex is rejected');
};

subtest 'evaluate AND policy requires all rules' => sub {
  my $policy = {
    op => 'AND',
    items => [
      { header => 'X-Forwarded-User', match => 'present' },
      { header => 'X-Auth-Source', match => 'equals', value => 'oauth2-proxy' },
    ],
  };

  my ($ok, $error) = evaluate_header_auth_policy($policy, {
    'X-Forwarded-User' => 'alice',
    'X-Auth-Source' => 'oauth2-proxy',
  });

  is($error, U(), 'AND policy evaluates without error');
  is($ok, 1, 'AND policy matches when all rules match');

  ($ok, $error) = evaluate_header_auth_policy($policy, {
    'X-Forwarded-User' => 'alice',
    'X-Auth-Source' => 'other',
  });

  is($error, U(), 'AND mismatch still evaluates without error');
  is($ok, 0, 'AND policy fails when one rule mismatches');
};

subtest 'evaluate OR policy supports case-insensitive header lookup' => sub {
  my $policy = {
    op => 'OR',
    items => [
      { header => 'X-Role', match => 'equals', value => 'fhem-admin' },
      { header => 'X-Forwarded-Groups', match => 'contains', value => 'admins' },
    ],
  };

  my ($ok, $error) = evaluate_header_auth_policy($policy, {
    'x-forwarded-groups' => 'users, admins, operators',
  });

  is($error, U(), 'OR policy evaluates without error');
  is($ok, 1, 'OR policy matches when one rule matches');
};

subtest 'evaluate nested policies' => sub {
  my $policy = {
    op => 'AND',
    items => [
      { header => 'X-Forwarded-User', match => 'present' },
      {
        op => 'OR',
        items => [
          { header => 'X-Role', match => 'equals', value => 'fhem-admin' },
          { header => 'X-Forwarded-Groups', match => 'contains', value => 'admins' },
        ],
      },
    ],
  };

  my ($ok, $error) = evaluate_header_auth_policy($policy, {
    'X-Forwarded-User' => 'alice',
    'X-Forwarded-Groups' => 'users,admins',
  });

  is($error, U(), 'nested policy evaluates without error');
  is($ok, 1, 'nested policy matches valid header combination');

  ($ok, $error) = evaluate_header_auth_policy($policy, {
    'X-Forwarded-Groups' => 'users,admins',
  });

  is($error, U(), 'nested policy mismatch still evaluates without error');
  is($ok, 0, 'nested policy fails when mandatory header is missing');
};

subtest 'evaluate string matchers' => sub {
  my $policy = {
    op => 'AND',
    items => [
      { header => 'X-Prefix', match => 'prefix', value => 'Bearer ' },
      { header => 'X-Suffix', match => 'suffix', value => '.example.org' },
      { header => 'X-User', match => 'regex', value => '^[a-z0-9._-]{3,64}$' },
      { header => 'X-State', match => 'notEquals', value => 'denied' },
    ],
  };

  my ($ok, $error) = evaluate_header_auth_policy($policy, {
    'X-Prefix' => 'Bearer token-123',
    'X-Suffix' => 'idp.example.org',
    'X-User' => 'alice_123',
    'X-State' => 'ok',
  });

  is($error, U(), 'string matcher policy evaluates without error');
  is($ok, 1, 'prefix, suffix, regex and notEquals match together');
};

done_testing();
exit(0);
1;
