use warnings;
use strict;

use Test::More;

plan tests => 2;

use PPR;

my $code = <<'_EOT_';
<<X, qq!at
line 1 (in heredoc!)
X
line 3\n!;
_EOT_

ok $code =~ m{ $PPR::GRAMMAR
               \A (?&PerlDocument) \z }x
                    => 'Matched document';

ok $code =~ m{ $PPR::GRAMMAR
               \A (?&PerlHeredoc) , (?&PerlOWS)
                  (?&PerlString)    (?&PerlOWS)
                  ;
               \Z
             }x => 'Matched pieces';

done_testing();

