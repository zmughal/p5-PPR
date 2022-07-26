use warnings;
use strict;

use Test::More;

plan tests => 2;

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


done_testing();

