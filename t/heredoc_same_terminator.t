#! /usr/bin/env perl

use 5.014;
use warnings;
use Test::More;
use re 'eval';

plan tests => 3;

use PPR;

my $MATCH_DOCUMENT = qr{ $PPR::GRAMMAR \A (?&PerlDocument) \z }x;

my $code = <<'_EOT_';
<<A . <<A;
)
A
]]]
A
_EOT_

ok $code =~ $MATCH_DOCUMENT;

$code = <<'_EOT_';
<<A . <<B;
))))
A
]]]]]]]]
B
_EOT_

ok $code =~ $MATCH_DOCUMENT;


$code = <<'_EOT_';
<<A . <<A;
)
A
]]]
A
_EOT_

ok $code =~ $MATCH_DOCUMENT;

done_testing();
