#! /usr/bin/env perl

use strict;
use warnings;

use Test::More;

BEGIN{
    BAIL_OUT "A bug in Perl 5.20 regex compilation prevents the use of PPR under that release"
        if $] > 5.020 && $] < 5.022;
}

plan tests => 24;

use PPR::X;
use re 'eval';

my $METAREGEX = qr{
    \A \s* (?&PerlQuotelike) \s* \Z

    (?(DEFINE)
        (?<PerlInfixBinaryOperator>
            ((?&PerlStdInfixBinaryOperator))
            (?{ ok 1 => "Found infix: $^N"
                    if $^N eq '//' || $^N eq '||';
            })
        )
    )

    $PPR::X::GRAMMAR
}xms;

ok q{ s<(RE)>< $var{$1} // croak() >ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s[(RE)][ $var{$1} // croak() ]ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s{(RE)}{ $var{$1} // croak() }ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s((RE))( $var{$1} // croak() )ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s"(RE)"  $var{$1} // croak() "ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s%(RE)%  $var{$1} // croak() %ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s'(RE)'  $var{$1} // croak() 'ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s+(RE)+  $var{$1} // croak() +ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s,(RE),  $var{$1} // croak() ,ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s/(RE)/  $var{$1} || croak() /ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s@(RE)@  $var{$1} // croak() @ge } =~ $METAREGEX  =>  'Matched METAREGEX';
ok q{ s|(RE)|  $var{$1} // croak() |ge } =~ $METAREGEX  =>  'Matched METAREGEX';

done_testing();



