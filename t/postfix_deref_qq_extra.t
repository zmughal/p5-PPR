use warnings;
use strict;

use Test::More;
use Test::Deep;

use PPR::X;

my @cases = (
    # From toke.c:
    #
    # /* S_intuit_more
    #  * ...
    #  * ->[ and ->{ return TRUE
    #  * ->$* ->$#* ->@* ->@[ ->@{ return TRUE if postderef_qq is enabled
    #  * ...
    #  */
    [ 'qq{$foo->[0]}'   => [ '$foo->[0]'  ] ], # TRUE
    [ 'qq{$foo->{a}}'   => [ '$foo->{a}'  ] ], # TRUE
    [ 'qq{$foo->$*}'    => [ '$foo->$*'   ] ], # TRUE if postderef_qq
    [ 'qq{$foo->$#*}'   => [ '$foo->$#*'  ] ], # TRUE if postderef_qq
    [ 'qq{$foo->@*}'    => [ '$foo->@*'   ] ], # TRUE if postderef_qq
    [ 'qq{$foo->@[0]}'  => [ '$foo->@[0]' ] ], # TRUE if postderef_qq
    [ 'qq{$foo->@{a}}'  => [ '$foo->@{a}' ] ], # TRUE if postderef_qq

    [ 'qq{$foo->%*}'    => [ '$foo'       ] ],
    [ 'qq{$foo->%[0]}'  => [ '$foo'       ] ],
    [ 'qq{$foo->%{a}}'  => [ '$foo'       ] ],
);

plan tests => 0+@cases;

our @got_matches = ();
my $scalar_access = qr{
    \A \s* (?&PerlQuotelike) \s* \Z

    (?(DEFINE)
        (?<PerlScalarAccessNoSpace>
            ((?&PerlStdScalarAccessNoSpace))
            (?{ push @got_matches, $^N })
        )
    )

    $PPR::X::GRAMMAR
}xms;

for my $case (@cases) {
    my ($code, $expected) = @$case;
    local @got_matches = ();
    $code =~ /$scalar_access/xg;
    cmp_bag \@got_matches, $expected, "Expected interpolation of << $code >>";
}

done_testing;
