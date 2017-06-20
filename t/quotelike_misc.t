use strict;
use warnings;

use Test::More;

use PPR;

my $neg = 0;
while (my $str = <DATA>) {
           if ($str =~ /\A# TH[EI]SE? SHOULD MATCH/) { $neg = 0;       next; }
        elsif ($str =~ /\A# TH[EI]SE? SHOULD FAIL/)  { $neg = 1;       next; }
        elsif ($str !~ /^####\h*\Z/m)                { $str .= <DATA>; redo; }

        $str =~ s/\s*^####\h*\Z//m;

        if ($neg) {
            ok $str !~ m/\A (?&PerlOWS) (?&PerlQuotelike) (?&PerlOWS) \Z $PPR::GRAMMAR/xo => "FAIL: $str";
        }
        else {
            ok $str =~ m/\A (?&PerlOWS) (?&PerlQuotelike) (?&PerlOWS) \Z $PPR::GRAMMAR/xo => "MATCH: $str";
        }
}

done_testing();

__DATA__
# THESE SHOULD MATCH...
    s(a){b}
####
    s (a)
    /b/
####
    q(d)
####
    qq(e)
####
    qx(f)
####
    qr(g)
####
    qw(h i j)
####
<<EOHERE
    line1
    line2
EOHERE
####
        <<\EOHERE
    line1
    line2
EOHERE
####
    <<"EOHERE"
    line1
    line2
EOHERE
####
    <<`EOHERE`
    line1
    line2
EOHERE
####
    <<'EOHERE'
    line1
    'line2'
EOHERE
####
<<'EOHERE'
    line1
    line2
EOHERE
####
    <<"    EOHERE"
    line1
    line2
    EOHERE
####
    <<""
    line1
    line2

####
    <<
    line1
    line2

####
    <<EOHERE
EOHERE

####
    <<"*"

*

####
    qq{a nested { and } are okay as are () and <> pairs and escaped \}'s }
####
    ''
####
    ""
####
    "a"
####
    'b'
####
    `cc`
####
    "this is a nested $var[$x] {"
####
    /a/gci
####
    m/a/gci
####
    q{d}
####
    qq{e}
####
    qx{f}
####
    qr{g}
####
    q/slash/
####
    q# slash #
####
    qr qw qx
####
    s/x/y/
####
    s/x/y/cgimsox
####
    s{a}{b}
####
    s{a}
     {b}
####
    s/'/\\'/g
####
    tr/x/y/
####
    y/x/y/
####
# THESE SHOULD FAIL...
    q # slash #
####
    s-$self->{pap}-$self->{sub}-       # CAN'T HANDLE '-' in '->'
####
    s<$self->{pat}>{$self->{sub}}      # CAN'T HANDLE '>' in '->'
####
