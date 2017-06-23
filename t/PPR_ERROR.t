use warnings;
use strict;

use Test::More;

plan tests => 4;

use PPR;

my $OFFSET = __LINE__ + 2;
my $source_code = <<'END_SOURCE';
    sub foo {
        my $x = 1;
        my $y = 2:
        my $z = 3;
    }
END_SOURCE

# Make sure it's undefined, and won't have global consequences...
local $PPR::ERROR;

# Attempt the match...
$source_code =~ m{ (?<Block> (?&PerlBlock) )  $PPR::GRAMMAR }x;

is $PPR::ERROR->source, 'my $y = 2:'                => 'Error source identified';
is $PPR::ERROR->prefix, substr($source_code, 0, 41) => 'Prefix identified';
is $PPR::ERROR->line, 3                             => 'Line identified';
is $PPR::ERROR->line($OFFSET), 14                   => 'Line with offset identified';

done_testing();

