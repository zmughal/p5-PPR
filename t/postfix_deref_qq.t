use warnings;
use strict;

use Test::More;
use Test::Deep qw(cmp_bag);

use PPR::X;

use feature qw(postderef_qq);
use List::Util qw(all);

my $sref = \42;                         # ScalarRef
my $aref = [ 3, 9, 27 ];                # ArrayRef
my $href = { a => 16, b => 8, c => 4 }; # HashRef

# Array of ArrayRef of Int
my @AoAR = ( [125, 25, 5], [6, 36, 216] );

# ArrayRef of ArrayRef of ScalarRef
my $aosr = [ [ \1, \3, \5 ], [ \2, \4, \6 ] ];

# Ref to ArrayRef of Str
my $srar = \[ 'Z', 'Y', 'X' ];

my $srsr = \\'ref';


my $scalarref_qr = qr/SCALAR \(0x[0-f]+\)/x;
my $arrayref_qr  = qr/ARRAY  \(0x[0-f]+\)/x;
my $hashref_qr   = qr/HASH   \(0x[0-f]+\)/x;
# [
#   $valid  (Bool)
#   $code   (Str)
#   $pieces (ArrayRef)
#   $pattern (RegexpRef)
# ]
my @cases = (
    # From toke.c:
    #
    # /* S_intuit_more
    #  * ...
    #  * ->[ and ->{ return TRUE
    #  * ->$* ->$#* ->@* ->@[ ->@{ return TRUE if postderef_qq is enabled
    #  * ...
    #  */
    [ 1, 'qq{$aref->[0]}'        => [ [ v => '$aref->[0]'       ]  ], qr/^3$/      ], # TRUE
    [ 1, 'qq{$href->{a}}'        => [ [ v => '$href->{a}'       ]  ], qr/^16$/     ], # TRUE
    [ 1, 'qq{$sref->$*}'         => [ [ v => '$sref->$*'        ]  ], qr/^42$/     ], # TRUE if postderef_qq
    [ 1, 'qq{$aref->$#*}'        => [ [ v => '$aref->$#*'       ]  ], qr/^2$/      ], # TRUE if postderef_qq
    [ 1, 'qq{$aref->@*}'         => [ [ v => '$aref->@*'        ]  ], qr/^3 9 27$/ ], # TRUE if postderef_qq
    [ 1, 'qq{$aref->@[0,2]}'     => [ [ v => '$aref->@[0,2]'    ]  ], qr/^3 27$/   ], # TRUE if postderef_qq
    [ 1, 'qq{$href->@{a=>c=>}}'  => [ [ v => '$href->@{a=>c=>}' ]  ], qr/^16 4$/   ], # TRUE if postderef_qq

    # no postfix hash dereference
    [ 1, 'qq{$href->%*}'         => [ [ v => '$href' ], [ l => '->%*'         ]  ], qr/^$hashref_qr\Q->%*\E$/ ],

    # no k/v slices interpolate
    [ 1, 'qq{$aref->%[0,2]}'     => [ [ v => '$aref' ], [ l => '->%[0,2]'     ]  ], qr/^$arrayref_qr\Q->%[0,2]\E$/   ],
    [ 1, 'qq{$href->%{a=>c=>}}'  => [ [ v => '$href' ], [ l => '->%{a=>c=>}'  ]  ], qr/^$hashref_qr\Q->%{a=>c=>}\E$/ ],

    [ 1, 'qq{@AoAR[(1)]->$#*}'   => [ [ v => '@AoAR[(1)]->$#*'                ]  ], qr/^2$/        ],
    [ 1, 'qq{@AoAR[(1)]->@*}'    => [ [ v => '@AoAR[(1)]->@*'                 ]  ], qr/^6 36 216$/ ],

    # invalid code: syntax error
    [ 0, 'qq{@AoAR[(1)]->@[2]}'  => [ ] ],

    [ 1, 'qq{$aosr->[1][2]->$*}'       => [ [ v => '$aosr->[1][2]->$*'        ]  ], qr/^6$/ ],

    [ 1, 'qq{$aosr->@[(1)]->$#*}'      => [ [ v => '$aosr->@[(1)]->$#*'       ]  ], qr/^2$/ ],
    [ 1, 'qq{$aosr->@[(1)]->[2]->$*}'  => [ [ v => '$aosr->@[(1)]->[2]->$*'   ]  ], qr/^6$/ ],

    [ 1, 'qq{$srar->$*->@*}'  => [ [ v => '$srar->$*' ], [ l => '->@*'        ]  ], qr/^$arrayref_qr\Q->@*\E$/ ],

    [ 1, 'qq{$srsr->$*}'      => [ [ v => '$srsr->$*' ]                          ], qr/^$scalarref_qr$/ ],

    # Only one ->$* is postfix interpolated, then the $* after is deprecated / fatal
    # For Perl < v5.30, this gives a warning.
    # For Perl ≥ v5.30, this will die:
    #   > Error: $* is no longer supported as of Perl 5.30
    [ $^V < v5.30.0, 'qq{$srsr->$*->$*}'  => [ [ v => '$srsr->$*' ], [ l => '->' ], [ v => '$*' ] ], qr/^$scalarref_qr\Q->\E$/ ],
);

plan tests => 0+@cases;

our @got_vars = ();
my $scalar_access = qr{
    \A \s* (?&PerlQuotelike) \s* \Z

    (?(DEFINE)
        (?<PerlScalarAccessNoSpace>
            ((?&PerlStdScalarAccessNoSpace))
            (?{ push @got_vars, $^N })
        )

        (?<PerlArrayAccessNoSpace>
            ((?&PerlStdArrayAccessNoSpace))
            (?{ push @got_vars, $^N })
        )
    )

    $PPR::X::GRAMMAR
}xms;

for my $case (@cases) {
    my ($valid, $code, $pieces, $pattern) = @$case;
    subtest "Case << $code >> which is @{[ $valid ? 'valid' : 'invalid' ]} code" => sub {
        #use warnings FATAL => qw(all);
        no autovivification;
        if( $valid ) {
            eval $code;
            if(!$@) {
                pass "code is valid (it evals)"
            } else {
                fail "code is invalid when it should be valid, skipping rest of tests";
                note "Error: ", $@;
                return;
            }

            local @got_vars = ();
            ok $code =~ /$scalar_access/xg, 'PPR matches valid code';
            my @expected_vars = map { $_->[0] eq 'v' ? $_->[1] : () } @$pieces;

            my $all_evaluatable = all { defined } map {
                my $val = eval $_;
                $@ ? undef : $val
            } @expected_vars;
            ok $all_evaluatable, "all variables evaluate outside of interpolation";

            cmp_bag \@got_vars, \@expected_vars, "PPR found variables in interpolation";

            my $got_interpolated = eval $code;
            my $expected_interpolated = join "",
                map { $_->[0] eq 'v' ? eval("qq{$_->[1]}") : $_->[1] }
                @$pieces;
            note "got interpolated: $got_interpolated";
            note "exp interpolated: $got_interpolated";
            is $got_interpolated, $expected_interpolated, "piecewise interpolation";
            like $got_interpolated, $pattern, 'matches expected pattern';
        } else {
            eval $code;
            chomp(my $err = $@);
            ok $err, "code is invalid: $err";
            local @got_vars = ();
            ok $code !~ /$scalar_access/xg, 'PPR does not match invalid code';
        }
    };
}

done_testing;
