use warnings;
use strict;

use Test::More;

plan tests => 3;

use PPR;

my $Perl_block = qr{
    \A (?&PerlOWS) (?&PerlBlock) (?&PerlOWS) \Z

    $PPR::GRAMMAR
}xms;

my $src = q{
    {
        my @example = map { $_ => $_ } $aref->@*;
        print join '-' => @example;
    }
};

ok $src =~ $Perl_block;

$src = q{{ $aref->@*; $href->%*; $sref->$*; $rref->$*->$*; $rref->$*->@*; }};

ok $src =~ $Perl_block;

# Taken from the examples in L<perlref>
#
# $ perldoc perlref | grep -- '->.*same as'
$src = q{{
    $sref->$*;
    $aref->@*;
    $aref->$#*;
    $href->%*;
    $cref->&*;
    $gref->**;

    $gref->*{SCALAR};

    $aref->@[    0..2   ];
    $href->@{ qw(i j k) };
    $aref->%[    0..2   ];
    $href->%{ qw(i j k) };
}};

ok $src =~ $Perl_block;

done_testing();

