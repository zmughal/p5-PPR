package PPR::X;

use 5.010;
use if $] < 5.018004, re => 'eval';

BEGIN {
    if ($] >= 5.020 && $] <= 5.021) {
        say {STDERR} <<"        END_WARNING"
        Warning: This program is running under Perl $^V and uses the PPR::X module.
                 Due to an unresolved issue with compilation of large regexes
                 in this version of Perl, your code is likely to compile
                 extremely slowly (i.e. it may take more than a minute).
                 PPR::X is being loaded at ${\join ' line ', (caller 2)[1,2]}.
        END_WARNING
    }
}
use warnings;
our $VERSION = '0.000027';
use utf8;
use List::Util qw<min max>;

# Class for $PPR::X::ERROR objects...
{ package PPR::X::ERROR;

  use overload q{""} => 'source', q{0+} => 'line', fallback => 1;

  sub new {
      my ($class, %obj) = @_;
      return bless \%obj, $class;
  }

  sub prefix { return shift->{prefix} }

  sub source { return shift->{source} }

  sub line   { my $self = shift;
               my $offset = $self->{line} // shift // 1;
               return $offset + $self->{prefix} =~ tr/\n//;
              }

  sub origin { my $self = shift;
               my $line = shift // 0;
               my $file = shift // "";
               return bless { %{$self}, line => $line, file => $file }, ref($self);
             }

  sub diagnostic { my $self = shift;
                   my $line = defined $self->{line}
                                    ? $self->{line} + $self->{prefix} =~ tr/\n//
                                    : 0;
                   my $file = $self->{file} // q{};
                   return q{} if eval "no strict;\n"
                                    . "#line $line $file\n"
                                    . "sub{ $self->{source} }";
                   my $diagnostic = $@;
                   $diagnostic =~ s{ \s*+ \bat \s++ \( eval \s++ \d++ \) \s++ line \s++ 0,
                                   | \s*+ \( eval \s++ \d++ \)
                                   | \s++ \Z
                                   }{}gx;
                   return $diagnostic;
                 }
}

# Define the grammar...
our $GRAMMAR = qr{
    (?(DEFINE)

        (?<PerlEntireDocument>   (?<PerlStdEntireDocument>
            \A
            (?&PerlDocument)
            (?:
                \Z
            |
                (?(?{ !defined $PPR::X::ERROR })
                    (?>(?&PerlOWSOrEND))  (?{pos()})  ([^\n]++)
                    (?{ $PPR::X::ERROR = PPR::X::ERROR->new(source => "$^N", prefix => substr($_, 0, $^R) ) })
                    (?!)
                )
            )
    )) # End of rule

        (?<PerlDocument>   (?<PerlStdDocument>
            \x{FEFF}?+                      # Optional BOM marker
            (?&PerlStatementSequence)
            (?&PerlOWSOrEND)
    )) # End of rule

        (?<PerlStatementSequence>   (?<PerlStdStatementSequence>
            (?>(?&PerlPodSequence))
            (?:
                (?&PerlStatement)
                (?&PerlPodSequence)
            )*+
    )) # End of rule

        (?<PerlStatement>   (?<PerlStdStatement>
            (?>
                (?>(?&PerlPodSequence))
                (?: (?>(?&PerlLabel)) (?&PerlOWSOrEND) )?+
                (?>(?&PerlPodSequence))
                (?>
                    (?&PerlKeyword)
                |
                    (?&PerlSubroutineDeclaration)
                |
                    (?&PerlUseStatement)
                |
                    (?&PerlPackageDeclaration)
                |
                    (?&PerlControlBlock)
                |
                    (?&PerlFormat)
                |
                    (?>(?&PerlExpression))          (?>(?&PerlOWS))
                    (?&PerlStatementModifier)?+     (?>(?&PerlOWSOrEND))
                    (?> ; | (?= \} | \z ))
                |
                    (?&PerlBlock)
                |
                    ;
                )

            | # A yada-yada...
                \.\.\. (?>(?&PerlOWSOrEND))
                (?> ; | (?= \} | \z ))

            | # Just a label...
                (?>(?&PerlLabel)) (?>(?&PerlOWSOrEND))
                (?> ; | (?= \} | \z ))

            | # Just an empty statement...
                (?>(?&PerlOWS)) ;

            | # An error (report it, if it's the first)...
                (?(?{ !defined $PPR::X::ERROR })
                    (?> (?&PerlOWS) )
                    (?! (?: \} | \z ) )
                    (?{ pos() })
                    ( (?&PerlExpression) (?&PerlOWS) [^\n]++ | [^;\}]++ )
                    (?{ $PPR::X::ERROR //= PPR::X::ERROR->new(source => $^N, prefix => substr($_, 0, $^R) ) })
                    (?!)
                )
            )
    )) # End of rule

        (?<PerlSubroutineDeclaration>   (?<PerlStdSubroutineDeclaration>
        (?>
            (?: (?> my | our | state ) \b      (?>(?&PerlOWS)) )?+
            sub \b                             (?>(?&PerlOWS))
            (?>(?&PerlOldQualifiedIdentifier))    (?&PerlOWS)
        |
            AUTOLOAD                              (?&PerlOWS)
        |
            DESTROY                               (?&PerlOWS)
        )
        (?:
            # Perl pre 5.028
            (?:
                (?>
                    (?&PerlParenthesesList)    # Parameter list
                |
                    \( [^)]*+ \)               # Prototype (
                )
                (?&PerlOWS)
            )?+
            (?: (?>(?&PerlAttributes))  (?&PerlOWS) )?+
        |
            # Perl post 5.028
            (?: (?>(?&PerlAttributes))       (?&PerlOWS) )?+
            (?: (?>(?&PerlParenthesesList))  (?&PerlOWS) )?+    # Parameter list
        )
        (?> ; | (?&PerlBlock) )
    )) # End of rule

        (?<PerlUseStatement>   (?<PerlStdUseStatement>
        (?: use | no ) (?>(?&PerlNWS))
        (?>
            (?&PerlVersionNumber)
        |
            (?>(?&PerlQualifiedIdentifier))
            (?: (?>(?&PerlNWS)) (?&PerlVersionNumber)
                (?! (?>(?&PerlOWS)) (?> (?&PerlInfixBinaryOperator) | (?&PerlComma) | \? ) )
            )?+
            (?: (?>(?&PerlNWS)) (?&PerlPodSequence) )?+
            (?: (?>(?&PerlOWS)) (?&PerlExpression) )?+
        )
        (?>(?&PerlOWSOrEND)) (?> ; | (?= \} | \z ))
    )) # End of rule

        (?<PerlReturnExpression>   (?<PerlStdReturnExpression>
        return \b (?: (?>(?&PerlOWS)) (?&PerlExpression) )?+
    )) # End of rule

        (?<PerlReturnStatement>   (?<PerlStdReturnStatement>
        return \b (?: (?>(?&PerlOWS)) (?&PerlExpression) )?+
        (?>(?&PerlOWSOrEND)) (?> ; | (?= \} | \z ))
    )) # End of rule

        (?<PerlPackageDeclaration>   (?<PerlStdPackageDeclaration>
        package
            (?>(?&PerlNWS)) (?>(?&PerlQualifiedIdentifier))
        (?: (?>(?&PerlNWS)) (?&PerlVersionNumber) )?+
            (?>(?&PerlOWSOrEND)) (?> ; | (?&PerlBlock) | (?= \} | \z ))
    )) # End of rule

        (?<PerlExpression>   (?<PerlStdExpression>
                                (?>(?&PerlLowPrecedenceNotExpression))
            (?: (?>(?&PerlOWS)) (?>(?&PerlLowPrecedenceInfixOperator))
                (?>(?&PerlOWS))    (?&PerlLowPrecedenceNotExpression)  )*+
    )) # End of rule

        (?<PerlLowPrecedenceNotExpression>   (?<PerlStdLowPrecedenceNotExpression>
            (?: not \b (?&PerlOWS) )*+  (?&PerlCommaList)
    )) # End of rule

        (?<PerlCommaList>   (?<PerlStdCommaList>
                    (?>(?&PerlAssignment))  (?>(?&PerlOWS))
            (?:
                (?: (?>(?&PerlComma))          (?&PerlOWS)   )++
                    (?>(?&PerlAssignment))  (?>(?&PerlOWS))
            )*+
                (?: (?>(?&PerlComma))          (?&PerlOWSOrEND)   )*+
    )) # End of rule

        (?<PerlAssignment>   (?<PerlStdAssignment>
                                (?>(?&PerlConditionalExpression))
            (?:
                (?>(?&PerlOWS)) (?>(?&PerlAssignmentOperator))
                (?>(?&PerlOWS))    (?&PerlConditionalExpression)
            )*+
    )) # End of rule

        (?<PerlScalarExpression>   (?<PerlStdScalarExpression>
        (?<PerlConditionalExpression>   (?<PerlStdConditionalExpression>
            (?>(?&PerlBinaryExpression))
            (?:
                (?>(?&PerlOWS)) \? (?>(?&PerlOWS)) (?>(?&PerlAssignment))
                (?>(?&PerlOWS))  : (?>(?&PerlOWS))    (?&PerlConditionalExpression)
            )?+
    )) # End of rule
    )) # End of rule

        (?<PerlBinaryExpression>   (?<PerlStdBinaryExpression>
                                (?>(?&PerlPrefixPostfixTerm))
            (?: (?>(?&PerlOWS)) (?>(?&PerlInfixBinaryOperator))
                (?>(?&PerlOWS))    (?&PerlPrefixPostfixTerm) )*+
    )) # End of rule

        (?<PerlPrefixPostfixTerm>   (?<PerlStdPrefixPostfixTerm>
            (?: (?>(?&PerlPrefixUnaryOperator))  (?&PerlOWS) )*+
            (?>(?&PerlTerm))
            (?:
                (?&PerlTermPostfixDereference)
            )?+
            (?: (?>(?&PerlOWS)) (?&PerlPostfixUnaryOperator) )?+
    )) # End of rule

        (?<PerlLvalue>   (?<PerlStdLvalue>
            (?>
                \\?+ [\$\@%] (?>(?&PerlOWS)) (?&PerlIdentifier)
            |
                \(                                                                     (?>(?&PerlOWS))
                    (?> \\?+ [\$\@%] (?>(?&PerlOWS)) (?&PerlIdentifier) | undef )      (?>(?&PerlOWS))
                    (?:
                        (?>(?&PerlComma))                                              (?>(?&PerlOWS))
                        (?> \\?+ [\$\@%] (?>(?&PerlOWS)) (?&PerlIdentifier) | undef )  (?>(?&PerlOWS))
                    )*+
                    (?: (?>(?&PerlComma)) (?&PerlOWS) )?+
                \)
            )
    )) # End of rule

        (?<PerlTerm>   (?<PerlStdTerm>
            (?>
                (?&PerlReturnExpression)
            |
                (?&PerlVariableDeclaration)
            |
                (?&PerlAnonymousSubroutine)
            |
                (?&PerlVariable)
            |
                (?>(?&PerlNullaryBuiltinFunction))  (?! (?>(?&PerlOWS)) \( )
            |
                (?&PerlDoBlock) | (?&PerlEvalBlock)
            |
                (?&PerlCall)
            |
                (?&PerlTypeglob)
            |
                (?>(?&PerlParenthesesList))
                (?: (?>(?&PerlOWS)) (?&PerlArrayIndexer) )?+
                (?:
                    (?>(?&PerlOWS))
                    (?>
                        (?&PerlArrayIndexer)
                    |   (?&PerlHashIndexer)
                    )
                )*+
            |
                (?&PerlAnonymousArray)
            |
                (?&PerlAnonymousHash)
            |
                (?&PerlDiamondOperator)
            |
                (?&PerlContextualMatch)
            |
                (?&PerlQuotelikeS)
            |
                (?&PerlQuotelikeTR)
            |
                (?&PerlQuotelikeQX)
            |
                (?&PerlLiteral)
            )
    )) # End of rule

        (?<PerlTermPostfixDereference>   (?<PerlStdTermPostfixDereference>
        (?>(?&PerlOWS)) -> (?>(?&PerlOWS))
        (?>
            (?> (?&PerlQualifiedIdentifier) | (?&PerlVariableScalar) )
            (?: (?>(?&PerlOWS)) (?&PerlParenthesesList) )?+

        |   (?&PerlParenthesesList)
        |   (?&PerlArrayIndexer)
        |   (?&PerlHashIndexer)
        |   \$\*
        )

        (?:
            (?>(?&PerlOWS))
            (?>
                ->  (?>(?&PerlOWS))
                (?> (?&PerlQualifiedIdentifier) | (?&PerlVariableScalar) )
                (?: (?>(?&PerlOWS)) (?&PerlParenthesesList) )?+
            |
                (?: -> (?&PerlOWS) )?+
                (?> (?&PerlParenthesesList)
                |   (?&PerlArrayIndexer)
                |   (?&PerlHashIndexer)
                |   \$\*
                )
            )
        )*+
        (?:
            (?>(?&PerlOWS)) -> (?>(?&PerlOWS)) [\@%]
            (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
        )?+
    )) # End of rule

        (?<PerlControlBlock>   (?<PerlStdControlBlock>
            (?> # Conditionals...
                (?> if | unless ) \b                 (?>(?&PerlOWS))
                (?>(?&PerlParenthesesList))          (?>(?&PerlOWS))
                (?>(?&PerlBlock))

                (?:
                                                    (?>(?&PerlOWS))
                    (?>(?&PerlPodSequence))
                    elsif \b                         (?>(?&PerlOWS))
                    (?>(?&PerlParenthesesList))      (?>(?&PerlOWS))
                    (?&PerlBlock)
                )*+

                (?:
                                                    (?>(?&PerlOWS))
                    (?>(?&PerlPodSequence))
                    else \b                          (?>(?&PerlOWS))
                    (?&PerlBlock)
                )?+

            |   # Loops...
                (?>
                    for(?:each)?+ \b
                    (?>(?&PerlOWS))
                    (?:
                        (?> # Explicitly aliased iterator variable...
                            (?> \\ (?>(?&PerlOWS))  (?> my | our | state )
                            |                       (?> my | our | state )  (?>(?&PerlOWS)) \\
                            )
                            (?>(?&PerlOWS))
                            (?> (?&PerlVariableScalar)
                            |   (?&PerlVariableArray)
                            |   (?&PerlVariableHash)
                            )
                        |
                            # Implicitly aliased iterator variable...
                            (?> (?: my | our | state ) (?>(?&PerlOWS)) )?+
                            (?&PerlVariableScalar)
                        )?+
                        (?>(?&PerlOWS))
                        (?> (?&PerlParenthesesList) | (?&PerlQuotelikeQW) )
                    |
                        (?&PPR_X_three_part_list)
                    )
                |
                    (?> while | until) \b (?>(?&PerlOWS))
                    (?&PerlParenthesesList)
                )

                (?>(?&PerlOWS))
                (?>(?&PerlBlock))

                (?:
                    (?>(?&PerlOWS))   continue
                    (?>(?&PerlOWS))   (?&PerlBlock)
                )?+

            | # Phasers...
                (?> BEGIN | END | CHECK | INIT | UNITCHECK ) \b   (?>(?&PerlOWS))
                (?&PerlBlock)

            | # Switches...
                (?> given | when ) \b                             (?>(?&PerlOWS))
                (?>(?&PerlParenthesesList))                            (?>(?&PerlOWS))
                (?&PerlBlock)
            |
                default                                           (?>(?&PerlOWS))
                (?&PerlBlock)
            )
    )) # End of rule

        (?<PerlFormat>   (?<PerlStdFormat>
            format
            (?: (?>(?&PerlNWS))  (?&PerlQualifiedIdentifier)  )?+
                (?>(?&PerlOWS))  = [^\n]*+
                (?&PPR_X_newline_and_heredoc)
            (?:
                (?! \. \n )
                [^\n\$\@]*+
                (?:
                    (?>
                        (?= \$ (?! \s ) )  (?&PerlScalarAccessNoSpace)
                    |
                        (?= \@ (?! \s ) )  (?&PerlArrayAccessNoSpace)
                    )
                    [^\n\$\@]*+
                )*+
                (?&PPR_X_newline_and_heredoc)
            )*+
            \. (?&PerlEndOfLine)
    )) # End of rule

        (?<PerlStatementModifier>   (?<PerlStdStatementModifier>
            (?> if | for(?:each)?+ | while | unless | until | when )
            \b
            (?>(?&PerlOWS))
            (?&PerlExpression)
    )) # End of rule

        (?<PerlBlock>   (?<PerlStdBlock>
            \{  (?>(?&PerlStatementSequence))  \}
    )) # End of rule

        (?<PerlCall>   (?<PerlStdCall>
            (?>
                [&]                                    (?>(?&PerlOWS))
                (?> (?&PerlBlock)
                |   (?&PerlVariableScalar)
                |   (?&PerlQualifiedIdentifier)
                )                                      (?>(?&PerlOWS))
                (?:
                    \(                                 (?>(?&PerlOWS))
                        (?: (?>(?&PerlExpression))        (?&PerlOWS)   )?+
                    \)
                )?+
            |
                - (?>(?&PPR_X_filetest_name))            (?>(?&PerlOWS))
                (?&PerlPrefixPostfixTerm)?+
            |
                (?>(?&PerlBuiltinFunction))            (?>(?&PerlOWS))
                (?>
                    \(                                 (?>(?&PerlOWS))
                        (?>
                            (?= (?>(?&PPR_X_non_reserved_identifier))
                                (?>(?&PerlOWS))
                                (?! \( | (?&PerlComma) )
                            )
                            (?&PerlCall)
                        |
                            (?>(?&PerlBlock))          (?>(?&PerlOWS))
                            (?&PerlExpression)?+
                        |
                            (?>(?&PPR_X_indirect_obj))   (?>(?&PerlNWS))
                            (?&PerlExpression)
                        |
                            (?&PerlExpression)?+
                        )                              (?>(?&PerlOWS))
                    \)
                |
                        (?>
                            (?=
                                (?>(?&PPR_X_non_reserved_identifier))
                                (?>(?&PerlOWS))
                                (?! \( | (?&PerlComma) )
                            )
                            (?&PerlCall)
                        |
                            (?>(?&PerlBlock))          (?>(?&PerlOWS))
                            (?&PerlCommaList)?+
                        |
                            (?>(?&PPR_X_indirect_obj))   (?>(?&PerlNWS))
                            (?&PerlCommaList)
                        |
                            (?&PerlCommaList)?+
                        )
                )
            |
                (?>(?&PPR_X_non_reserved_identifier)) (?>(?&PerlOWS))
                (?>
                    \(                              (?>(?&PerlOWS))
                        (?: (?>(?&PerlExpression))     (?&PerlOWS)  )?+
                    \)
                |
                        (?>
                            (?=
                                (?>(?&PPR_X_non_reserved_identifier))
                                (?>(?&PerlOWS))
                                (?! \( | (?&PerlComma) )
                            )
                            (?&PerlCall)
                        |
                            (?>(?&PerlBlock))           (?>(?&PerlOWS))
                            (?&PerlCommaList)?+
                        |
                            (?>(?&PPR_X_indirect_obj))        (?&PerlNWS)
                            (?&PerlCommaList)
                        |
                            (?&PerlCommaList)?+
                        )
                )
            )
    )) # End of rule

        (?<PerlVariableDeclaration>   (?<PerlStdVariableDeclaration>
            (?> my | state | our ) \b           (?>(?&PerlOWS))
            (?: (?&PerlQualifiedIdentifier)        (?&PerlOWS)  )?+
            (?>(?&PerlLvalue))                  (?>(?&PerlOWS))
            (?&PerlAttributes)?+
    )) # End of rule

        (?<PerlDoBlock>   (?<PerlStdDoBlock>
            do (?>(?&PerlOWS)) (?&PerlBlock)
    )) # End of rule

        (?<PerlEvalBlock>   (?<PerlStdEvalBlock>
            eval (?>(?&PerlOWS)) (?&PerlBlock)
    )) # End of rule

        (?<PerlAttributes>   (?<PerlStdAttributes>
            :
            (?>(?&PerlOWS))
            (?>(?&PerlIdentifier))
            (?:
                (?= \( ) (?&PPR_X_quotelike_body)
            )?+

            (?:
                (?> (?>(?&PerlOWS)) : (?&PerlOWS) | (?&PerlNWS) )
                (?>(?&PerlIdentifier))
                (?:
                    (?= \( ) (?&PPR_X_quotelike_body)
                )?+
            )*+
    )) # End of rule

        (?<PerlList>   (?<PerlStdList>
            (?> (?&PerlParenthesesList) | (?&PerlCommaList) )
    )) # End of rule

        (?<PerlParenthesesList>   (?<PerlStdParenthesesList>
            \(  (?>(?&PerlOWS))  (?: (?>(?&PerlExpression)) (?&PerlOWS) )?+  \)
    )) # End of rule

        (?<PerlAnonymousArray>   (?<PerlStdAnonymousArray>
            \[  (?>(?&PerlOWS))  (?: (?>(?&PerlExpression)) (?&PerlOWS) )?+  \]
    )) # End of rule

        (?<PerlAnonymousHash>   (?<PerlStdAnonymousHash>
            \{  (?>(?&PerlOWS))  (?: (?>(?&PerlExpression)) (?&PerlOWS) )?+ \}
    )) # End of rule

        (?<PerlArrayIndexer>   (?<PerlStdArrayIndexer>
            \[                          (?>(?&PerlOWS))
                (?>(?&PerlExpression))  (?>(?&PerlOWS))
            \]
    )) # End of rule

        (?<PerlHashIndexer>   (?<PerlStdHashIndexer>
            \{  (?>(?&PerlOWS))
                (?: -?+ (?&PerlIdentifier) | (?&PerlExpression) )  # (Note: MUST allow backtracking here)
                (?>(?&PerlOWS))
            \}
    )) # End of rule

        (?<PerlDiamondOperator>   (?<PerlStdDiamondOperator>
            <<>>    # Perl 5.22 "double diamond"
        |
            < (?! < )
                (?>(?&PPR_X_balanced_angles))
            >
            (?=
                (?>(?&PerlOWSOrEND))
                (?> \z | [,;\}\])?] | => | : (?! :)        # (
                |   (?&PerlInfixBinaryOperator) | (?&PerlLowPrecedenceInfixOperator)
                |   (?= \w) (?> for(?:each)?+ | while | if | unless | until | when )
                )
            )
    )) # End of rule

        (?<PerlComma>   (?<PerlStdComma>
            (?> , | => )
    )) # End of rule

        (?<PerlPrefixUnaryOperator>   (?<PerlStdPrefixUnaryOperator>
            (?> \+\+ | -- | [!\\+~] | - (?! (?&PPR_X_filetest_name) \b ) )
    )) # End of rule

        (?<PerlPostfixUnaryOperator>   (?<PerlStdPostfixUnaryOperator>
            (?> \+\+  |  -- )
    )) # End of rule

        (?<PerlInfixBinaryOperator>   (?<PerlStdInfixBinaryOperator>
            (?>  [=!][~=]
            |    cmp
            |    <= >?+
            |    >=
            |    [lg][te]
            |    eq
            |    ne
            |    [+]             (?! [+=] )
            |     -              (?! [-=] )
            |    [.]{2,3}+
            |    [.%x]           (?! [=]  )
            |    [&|^][.]        (?! [=]  )
            |    [<>*&|/]{1,2}+  (?! [=]  )
            |    \^              (?! [=]  )
            |    ~~
            )
    )) # End of rule

        (?<PerlAssignmentOperator>   (?<PerlStdAssignmentOperator>
            (?:  [<>*&|/]{2}
            |  [-+.*/%x]
            |  [&|^][.]?+
            )?+
            =
            (?! > )
    )) # End of rule

        (?<PerlLowPrecedenceInfixOperator>   (?<PerlStdLowPrecedenceInfixOperator>
            (?> or | and | xor )
    )) # End of rule

        (?<PerlAnonymousSubroutine>   (?<PerlStdAnonymousSubroutine>
            sub \b
            (?>(?&PerlOWS))
            (?:
                # Perl pre 5.028
                (?:
                    (?>
                        (?&PerlParenthesesList)    # Parameter list
                    |
                        \( [^)]*+ \)               # Prototype (
                    )
                    (?&PerlOWS)
                )?+
                (?: (?>(?&PerlAttributes))  (?&PerlOWS) )?+
            |
                # Perl post 5.028
                (?: (?>(?&PerlAttributes))       (?&PerlOWS) )?+
                (?: (?>(?&PerlParenthesesList))  (?&PerlOWS) )?+    # Parameter list
            )
            (?&PerlBlock)
    )) # End of rule

        (?<PerlVariable>   (?<PerlStdVariable>
            (?= [\$\@%] )
            (?>
                (?&PerlScalarAccess)
            |   (?&PerlHashAccess)
            |   (?&PerlArrayAccess)
            )
    )) # End of rule

        (?<PerlTypeglob>   (?<PerlStdTypeglob>
            \*
            (?>
                \d++
            |
                \^ [][A-Z^_?\\]
            |
                \{ \^ [A-Z_] \w*+ \}
            |
                (?>(?&PerlOldQualifiedIdentifier))  (?: :: )?+
            |
                (?&PerlVariableScalar)
            |
                [][!"#\$%&'()*+,./:;<=>?\@\^`|~-]
            |
                (?&PerlBlock)
            )
            (?:
                (?>(?&PerlOWS)) (?: -> (?&PerlOWS) )?+
                (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList) )
            )*+
            (?:
                (?>(?&PerlOWS)) -> (?>(?&PerlOWS))
                [\@%]
                (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
            )?+
    )) # End of rule

        (?<PerlArrayAccess>   (?<PerlStdArrayAccess>
            (?>(?&PerlVariableArray))
            (?:
                (?>(?&PerlOWS)) (?: -> (?&PerlOWS) )?+
                (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList)  )
            )*+
            (?:
                (?>(?&PerlOWS)) -> (?>(?&PerlOWS))
                [\@%]
                (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
            )?+
    )) # End of rule

        (?<PerlArrayAccessNoSpace>   (?<PerlStdArrayAccessNoSpace>
            (?>(?&PerlVariableArrayNoSpace))
            (?:
                (?: -> )?+
                (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList)  )
            )*+
            (?:
                ->
                [\@%]
                (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
            )?+
    )) # End of rule

        (?<PerlArrayAccessNoSpaceNoArrow>   (?<PerlStdArrayAccessNoSpaceNoArrow>
            (?>(?&PerlVariableArray))
            (?:
                (?> (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList)  )
            )*+
    )) # End of rule

        (?<PerlHashAccess>   (?<PerlStdHashAccess>
            (?>(?&PerlVariableHash))
            (?:
                (?>(?&PerlOWS)) (?: -> (?&PerlOWS) )?+
                (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList) )
            )*+
            (?:
                (?>(?&PerlOWS)) -> (?>(?&PerlOWS))
                [\@%]
                (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
            )?+
    )) # End of rule

        (?<PerlScalarAccess>   (?<PerlStdScalarAccess>
            (?>(?&PerlVariableScalar))
            (?:
                (?>(?&PerlOWS))
                (?:
                    (?:
                        (?>(?&PerlOWS))      -> (?>(?&PerlOWS))
                        (?&PerlParenthesesList)
                    |
                        (?>(?&PerlOWS))  (?: ->    (?&PerlOWS)  )?+
                        (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
                    )
                    (?:
                        (?>(?&PerlOWS))  (?: ->    (?&PerlOWS)  )?+
                        (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList) )
                    )*+
                )?+
                (?:
                    (?>(?&PerlOWS)) -> (?>(?&PerlOWS))
                    [\@%]
                    (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
                )?+
            )?+
    )) # End of rule

        (?<PerlScalarAccessNoSpace>   (?<PerlStdScalarAccessNoSpace>
            (?>(?&PerlVariableScalarNoSpace))
            (?:
                (?:
                    (?:
                        ->
                        (?&PerlParenthesesList)
                    |
                        (?: -> )?+
                        (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
                    )
                    (?:
                        (?: -> )?+
                        (?> \$\* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList) )
                    )*+
                )?+
                (?:
                    ->
                    [\@%]
                    (?> \* | (?&PerlArrayIndexer) | (?&PerlHashIndexer) )
                )?+
            )?+
    )) # End of rule

        (?<PerlScalarAccessNoSpaceNoArrow>   (?<PerlStdScalarAccessNoSpaceNoArrow>
            (?>(?&PerlVariableScalarNoSpace))
            (?:
                (?> (?&PerlArrayIndexer) | (?&PerlHashIndexer) | (?&PerlParenthesesList) )
            )*+
    )) # End of rule

        (?<PerlVariableScalar>   (?<PerlStdVariableScalar>
            \$\$
            (?! [\$\{\w] )
        |
            (?:
                \$
                (?:
                    [#]
                    (?=  (?> [\$^\w\{:+] | - (?! > ) )  )
                )?+
                (?&PerlOWS)
            )++
            (?>
                \d++
            |
                \^ [][A-Z^_?\\]
            |
                \{ \^ [A-Z_] \w*+ \}
            |
                (?>(?&PerlOldQualifiedIdentifier)) (?: :: )?+
            |
                :: (?&PerlBlock)
            |
                [][!"#\$%&'()*+,.\\/:;<=>?\@\^`|~-]
            |
                \{ [!"#\$%&'()*+,.\\/:;<=>?\@\^`|~-] \}
            |
                \{ \w++ \}
            |
                (?&PerlBlock)
            )
        |
            \$\#
    )) # End of rule

        (?<PerlVariableScalarNoSpace>   (?<PerlStdVariableScalarNoSpace>
            \$\$
            (?! [\$\{\w] )
        |
            (?:
                \$
                (?:
                    [#]
                    (?=  (?> [\$^\w\{:+] | - (?! > ) )  )
                )?+
            )++
            (?>
                \d++
            |
                \^ [][A-Z^_?\\]
            |
                \{ \^ [A-Z_] \w*+ \}
            |
                (?>(?&PerlOldQualifiedIdentifier)) (?: :: )?+
            |
                :: (?&PerlBlock)
            |
                [][!"#\$%&'()*+,.\\/:;<=>?\@\^`|~-]
            |
                \{ \w++ \}
            |
                (?&PerlBlock)
            )
        |
            \$\#
    )) # End of rule

        (?<PerlVariableArray>   (?<PerlStdVariableArray>
            \@     (?>(?&PerlOWS))
            (?: \$    (?&PerlOWS)  )*+
            (?>
                \d++
            |
                \^ [][A-Z^_?\\]
            |
                \{ \^ [A-Z_] \w*+ \}
            |
                (?>(?&PerlOldQualifiedIdentifier)) (?: :: )?+
            |
                :: (?&PerlBlock)
            |
                [][!"#\$%&'()*+,.\\/:;<=>?\@\^`|~-]
            |
                (?&PerlBlock)
            )
    )) # End of rule

        (?<PerlVariableArrayNoSpace>   (?<PerlStdVariableArrayNoSpace>
            \@
            (?: \$ )*+
            (?>
                \d++
            |
                \^ [][A-Z^_?\\]
            |
                \{ \^ [A-Z_] \w*+ \}
            |
                (?>(?&PerlOldQualifiedIdentifier)) (?: :: )?+
            |
                :: (?&PerlBlock)
            |
                [][!"#\$%&'()*+,.\\/:;<=>?\@\^`|~-]
            |
                (?&PerlBlock)
            )
    )) # End of rule

        (?<PerlVariableHash>   (?<PerlStdVariableHash>
            %      (?>(?&PerlOWS))
            (?: \$    (?&PerlOWS)  )*+
            (?>
                \d++
            |
                \^ [][A-Z^_?\\]
            |
                \{ \^ [A-Z_] \w*+ \}
            |
                (?>(?&PerlOldQualifiedIdentifier)) (?: :: )?+
            |
                :: (?&PerlBlock)?+
            |
                [][!"#\$%&'()*+,.\\/:;<=>?\@\^`|~-]
            |
                (?&PerlBlock)
            )
    )) # End of rule

        (?<PerlLabel>   (?<PerlStdLabel>
            (?! (?> [msy] | q[wrxq]?+ | tr ) \b )
            (?>(?&PerlIdentifier))
            : (?! : )
    )) # End of rule

        (?<PerlLiteral>   (?<PerlStdLiteral>
            (?> (?&PerlString)
            |   (?&PerlQuotelikeQR)
            |   (?&PerlQuotelikeQW)
            |   (?&PerlNumber)
            |   (?&PerlBareword)
            )
    )) # End of rule

        (?<PerlString>   (?<PerlStdString>
            (?>
                "  [^"\\]*+  (?: \\. [^"\\]*+ )*+ "
            |
                '  [^'\\]*+  (?: \\. [^'\\]*+ )*+ '
            |
                qq \b
                (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
                (?&PPR_X_quotelike_body_interpolated)
            |
                q \b
                (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
                (?&PPR_X_quotelike_body)
            |
                (?&PerlHeredoc)
            |
                (?&PerlVString)
            )
    )) # End of rule

        (?<PerlQuotelike>   (?<PerlStdQuotelike>
            (?> (?&PerlString)
            |   (?&PerlQuotelikeQR)
            |   (?&PerlQuotelikeQW)
            |   (?&PerlQuotelikeQX)
            |   (?&PerlContextualMatch)
            |   (?&PerlQuotelikeS)
            |   (?&PerlQuotelikeTR)
            )
    )) # End of rule

        (?<PerlHeredoc>   (?<PerlStdHeredoc>
            # Match the introducer...
            <<
            (?<_heredoc_indented> [~]?+ )

            # Match the terminator specification...
            (?>
                \\?+   (?<_heredoc_terminator>  (?&PerlIdentifier)              )
            |
                (?>(?&PerlOWS))
                (?>
                    "  (?<_heredoc_terminator>  [^"\\]*+  (?: \\. [^"\\]*+ )*+  )  "  #"
                |
                    (?<PPR_X_HD_nointerp> ' )
                    (?<_heredoc_terminator>  [^'\\]*+  (?: \\. [^'\\]*+ )*+  )  '  #'
                |
                    `  (?<_heredoc_terminator>  [^`\\]*+  (?: \\. [^`\\]*+ )*+  )  `  #`
                )
            |
                    (?<_heredoc_terminator>                                  )
            )

            # Do we need to reset the heredoc cache???
            (?{
                if ( ($PPR::X::_heredoc_origin // q{}) ne $_ ) {
                    %PPR::X::_heredoc_skip      = ();
                    %PPR::X::_heredoc_parsed_to = ();
                    $PPR::X::_heredoc_origin    = $_;
                }
            })

            # Do we need to cache content lookahead for this heredoc???
            (?(?{ my $need_to_lookahead = !$PPR::X::_heredoc_parsed_to{+pos()};
                $PPR::X::_heredoc_parsed_to{+pos()} = 1;
                $need_to_lookahead;
                })

                # Lookahead to detect and remember trailing contents of heredoc
                (?=
                    [^\n]*+ \n                                   # Go to the end of the current line
                    (?{ +pos() })                                # Remember the start of the contents
                    (??{ $PPR::X::_heredoc_skip{+pos()} // q{} })   # Skip earlier heredoc contents
                    (?>                                          # The heredoc contents consist of...
                        (?:
                            (?!
                                (?(?{ $+{_heredoc_indented} }) \h*+ )   # An indent (if it was a <<~)
                                \g{_heredoc_terminator}                 # The terminator
                                (?: \n | \z )                           # At an end-of-line
                            )
                            (?(<PPR_X_HD_nointerp>)
                                [^\n]*+ \n
                            |
                                [^\n\$\@]*+
                                (?:
                                    (?>
                                        (?{ local $PPR::X::_heredoc_EOL_start = $^R })
                                        (?= \$ (?! \s ) )  (?&PerlScalarAccessNoSpace)
                                        (?{ $PPR::X::_heredoc_EOL_start })
                                    |
                                        (?{ local $PPR::X::_heredoc_EOL_start = $^R })
                                        (?= \@ (?! \s ) )  (?&PerlArrayAccessNoSpace)
                                        (?{ $PPR::X::_heredoc_EOL_start })
                                    )
                                    [^\n\$\@]*+
                                )*+
                                \n (??{ $PPR::X::_heredoc_skip{+pos()} // q{} })
                            )
                        )*+

                        (?(?{ $+{_heredoc_indented} }) \h*+ )            # An indent (if it was a <<~)
                        \g{_heredoc_terminator}                          # The specified terminator
                        (?: \n | \z )                                    # Followed by EOL
                    )

                    # Then memoize the skip for when it's subsequently needed by PerlOWS or PerlNWS...
                    (?{
                        # Split .{N} repetition into multiple repetitions to avoid the 32766 limit...
                        $PPR::X::_heredoc_skip{$^R} = '(?s:'
                                                . ( '.{32766}' x int((pos() - $^R) / 32766) )
                                                . '.{' . (pos() - $^R) % 32766 . '})';
                    })
                )
            )

    )) # End of rule

        (?<PerlQuotelikeQ>   (?<PerlStdQuotelikeQ>
            (?>
                '  [^'\\]*+  (?: \\. [^'\\]*+ )*+ '
            |
                \b q \b
                (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
                (?&PPR_X_quotelike_body)
            )
    )) # End of rule

        (?<PerlQuotelikeQQ>   (?<PerlStdQuotelikeQQ>
            (?>
                "  [^"\\]*+  (?: \\. [^"\\]*+ )*+ "
            |
                \b qq \b
                (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
                (?&PPR_X_quotelike_body_interpolated)
            )
    )) # End of rule

        (?<PerlQuotelikeQW>   (?<PerlStdQuotelikeQW>
            (?>
                qw \b
                (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
                (?&PPR_X_quotelike_body)
            )
    )) # End of rule

        (?<PerlQuotelikeQX>   (?<PerlStdQuotelikeQX>
            (?>
                `  [^`]*+  (?: \\. [^`]*+ )*+  `
            |
                qx
                    (?:
                        (?&PerlOWS) ' (?&PPR_X_quotelike_body)
                    |
                        \b (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
                        (?&PPR_X_quotelike_body_interpolated)
                    )
            )
    )) # End of rule

        (?<PerlQuotelikeS>   (?<PerlStdQuotelikeS>
        (?<PerlSubstitution>   (?<PerlStdSubstitution>
            s \b
            (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
            (?>
                # Hashed syntax...
                (?= [#] )
                (?>(?&PPR_X_regex_body_interpolated_unclosed))
                (?&PPR_X_quotelike_s_e_check)
                (?>(?&PPR_X_quotelike_body_interpolated))
            |
                # Bracketed syntax...
                (?= (?>(?&PerlOWS)) [\[(<\{] )      # )
                (?>(?&PPR_X_regex_body_interpolated))
                (?>(?&PerlOWS))
                (?&PPR_X_quotelike_s_e_check)
                (?>(?&PPR_X_quotelike_body_interpolated))
            |
                # Delimited syntax...
                (?>(?&PPR_X_regex_body_interpolated_unclosed))
                (?&PPR_X_quotelike_s_e_check)
                (?>(?&PPR_X_quotelike_body_interpolated))
            )
            [msixpodualgcern]*+
    )) # End of rule
    )) # End of rule

        (?<PerlQuotelikeTR>   (?<PerlStdQuotelikeTR>
        (?<PerlTransliteration>   (?<PerlStdTransliteration>
            (?> tr | y ) \b
            (?! (?>(?&PerlOWS)) => )
            (?>
                # Hashed syntax...
                (?= [#] )
                (?>(?&PPR_X_quotelike_body_interpolated_unclosed))
                (?&PPR_X_quotelike_body_interpolated)
            |
                # Bracketed syntax...
                (?= (?>(?&PerlOWS)) [\[(<\{] )      # )
                (?>(?&PPR_X_quotelike_body_interpolated))
                (?>(?&PerlOWS))
                (?&PPR_X_quotelike_body_interpolated)
            |
                # Delimited syntax...
                (?>(?&PPR_X_quotelike_body_interpolated_unclosed))
                (?&PPR_X_quotelike_body_interpolated)
            )
            [cdsr]*+
    )) # End of rule
    )) # End of rule

        (?<PerlContextualQuotelikeM>   (?<PerlStdContextualQuotelikeM>
        (?<PerlContextualMatch>   (?<PerlStdContextualMatch>
            (?<PerlQuotelikeM>
            (?<PerlMatch>
                (?>
                    \/\/
                |
                    (?>
                        m (?= [#] )
                    |
                        m \b
                        (?! (?>(?&PerlOWS)) => )
                    |
                        (?= \/ [^/] )
                    )
                    (?&PPR_X_regex_body_interpolated)
                )
                [msixpodualgcn]*+
            ) # End of rule (?<PerlMatch>)
            ) # End of rule (?<PerlQuotelikeM>)
            (?=
                (?>(?&PerlOWS))
                (?> \z | [,;\}\])?] | => | : (?! :)
                |   (?&PerlInfixBinaryOperator) | (?&PerlLowPrecedenceInfixOperator)
                |   (?= \w) (?> for(?:each)?+ | while | if | unless | until | when )
                )
            )
    )) # End of rule
    )) # End of rule

        (?<PerlQuotelikeQR>   (?<PerlStdQuotelikeQR>
            qr \b
            (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
            (?>(?&PPR_X_regex_body_interpolated))
            [msixpodualn]*+
    )) # End of rule

        (?<PerlRegex>   (?<PerlStdRegex>
            (?>
                (?&PerlMatch)
            |
                (?&PerlQuotelikeQR)
            )
    )) # End of rule

        (?<PerlContextualRegex>   (?<PerlStdContextualRegex>
            (?>
                (?&PerlContextualMatch)
            |
                (?&PerlQuotelikeQR)
            )
    )) # End of rule


        (?<PerlBuiltinFunction>   (?<PerlStdBuiltinFunction>
            # Optimized to match any Perl builtin name, without backtracking...
            (?=[^\W\d]) # Skip if possible
            (?>
                s(?>e(?>t(?>(?>(?>(?>hos|ne)t|gr)en|s(?>erven|ockop))t|p(?>r(?>iority|otoent)|went|grp))|m(?>ctl|get|op)|ek(?>dir)?|lect|nd)|y(?>s(?>write|call|open|read|seek|tem)|mlink)|h(?>m(?>write|read|ctl|get)|utdown|ift)|o(?>cket(?>pair)?|rt)|p(?>li(?>ce|t)|rintf)|(?>cala|ubst)r|t(?>ate?|udy)|leep|rand|qrt|ay|in)
                | g(?>et(?>p(?>r(?>oto(?>byn(?>umber|ame)|ent)|iority)|w(?>ent|nam|uid)|eername|grp|pid)|s(?>erv(?>by(?>name|port)|ent)|ock(?>name|opt))|host(?>by(?>addr|name)|ent)|net(?>by(?>addr|name)|ent)|gr(?>ent|gid|nam)|login|c)|mtime|lob|oto|rep)
                | r(?>e(?>ad(?>lin[ek]|pipe|dir)?|(?>quir|vers|nam)e|winddir|turn|set|cv|do|f)|index|mdir|and)
                | c(?>h(?>o(?>m?p|wn)|r(?>oot)?|dir|mod)|o(?>n(?>tinue|nect)|s)|lose(?>dir)?|aller|rypt)
                | e(?>nd(?>(?>hos|ne)t|p(?>roto|w)|serv|gr)ent|x(?>i(?>sts|t)|ec|p)|ach|val(?>bytes)?+|of)
                | l(?>o(?>c(?>al(?>time)?|k)|g)|i(?>sten|nk)|(?>sta|as)t|c(?>first)?|ength)
                | u(?>n(?>(?>lin|pac)k|shift|def|tie)|c(?>first)?|mask|time)
                | p(?>r(?>ototype|intf?)|ack(?>age)?|o[ps]|ipe|ush)
                | d(?>bm(?>close|open)|e(?>fined|lete)|ump|ie|o)
                | f(?>or(?>m(?>line|at)|k)|ileno|cntl|c|lock)
                | t(?>i(?>mes?|ed?)|ell(?>dir)?|runcate)
                | w(?>a(?>it(?>pid)?|ntarray|rn)|rite)
                | m(?>sg(?>ctl|get|rcv|snd)|kdir|ap)
                | b(?>in(?>mode|d)|less|reak)
                | i(?>n(?>dex|t)|mport|octl)
                | a(?>ccept|larm|tan2|bs)
                | o(?>pen(?>dir)?|ct|rd)
                | v(?>alues|ec)
                | k(?>eys|ill)
                | quotemeta
                | join
                | next
                | hex
                | _
            )
            \b
    )) # End of rule

        (?<PerlNullaryBuiltinFunction>   (?<PerlStdNullaryBuiltinFunction>
            # Optimized to match any Perl builtin name, without backtracking...
            (?= [^\W\d] )  # Skip if possible
            (?>
                get(?:(?:(?:hos|ne)t|serv|gr)ent|p(?:(?:roto|w)ent|pid)|login)
                | end(?:(?:hos|ne)t|p(?:roto|w)|serv|gr)ent
                | wa(?:ntarray|it)
                | times?
                | fork
                | _
            )
            \b
    )) # End of rule

        (?<PerlVersionNumber>   (?<PerlStdVersionNumber>
            (?>
                (?&PerlVString)
            |
                (?>(?&PPR_X_digit_seq))
                (?: \. (?&PPR_X_digit_seq)?+ )*+
            )
    )) # End of rule

        (?<PerlVString>   (?<PerlStdVString>
            v  (?>(?&PPR_X_digit_seq))  (?: \. (?&PPR_X_digit_seq) )*+
    )) # End of rule

        (?<PerlNumber>   (?<PerlStdNumber>
            [+-]?+
            (?>
                0  (?>  x (?&PPR_X_x_digit_seq)
                |    b (?&PPR_X_b_digit_seq)
                |      (?&PPR_X_o_digit_seq)
                )
            |
                (?>
                        (?>(?&PPR_X_digit_seq))
                    (?: \. (?&PPR_X_digit_seq)?+ )?+
                |
                        \. (?&PPR_X_digit_seq)
                )
                (?: [eE] [+-]?+ (?&PPR_X_digit_seq) )?+
            )
    )) # End of rule

        (?<PerlOldQualifiedIdentifier>   (?<PerlStdOldQualifiedIdentifier>
            (?> (?> :: | ' ) \w++  |  [^\W\d]\w*+ )  (?: (?> :: | ' )  \w++ )*+
    )) # End of rule

        (?<PerlQualifiedIdentifier>   (?<PerlStdQualifiedIdentifier>
            (?>     ::       \w++  |  [^\W\d]\w*+ )  (?: (?> :: | ' )  \w++ )*+
    )) # End of rule

        (?<PerlIdentifier>   (?<PerlStdIdentifier>
                                    [^\W\d]\w*+
    )) # End of rule

        (?<PerlBareword>   (?<PerlStdBareword>
            (?! (?> (?= \w )
                    (?> for(?:each)?+ | while | if | unless | until | use | no | given | when | sub | return )
                |   (?&PPR_X_named_op)
                |   __ (?> END | DATA ) __ \b
                ) \b
                (?! (?>(?&PerlOWS)) => )
            )
            (?! (?> q[qwrx]?+ | [mys] | tr ) \b
                (?> (?= [#] ) | (?! (?>(?&PerlOWS)) => ) )
            )
            (?: :: )?+
            [^\W\d]\w*+
            (?: (?: :: | ' )  [^\W\d]\w*+  )*+
            (?: :: )?+
            (?! \( )    # )
        |
            :: (?! \w | \{ )
    )) # End of rule

        (?<PerlKeyword>   (?<PerlStdKeyword>
            (?!)    # None, by default, but can be overridden in a composing regex
    )) # End of rule

        (?<PerlPodSequence>   (?<PerlStdPodSequence>
            (?>(?&PerlOWS))  (?: (?>(?&PerlPod))  (?&PerlOWS) )*+
    )) # End of rule

        (?<PerlPod>   (?<PerlStdPod>
            ^ = [^\W\d]\w*+             # A line starting with =<identifier>
            .*?                         # Up to the first...
            (?>
                ^ = cut \b [^\n]*+ $    # ...line starting with =cut
            |                           # or
                \z                      # ...EOF
            )
    )) # End of rule


        ##### Whitespace matching (part of API) #################################

        (?<PerlOWSOrEND>   (?<PerlStdOWSOrEND>
            (?:
                \h++
            |
                (?&PPR_X_newline_and_heredoc)
            |
                [#] [^\n]*+
            |
                __ (?> END | DATA ) __ \b .*+ \z
            )*+
    )) # End of rule

        (?<PerlOWS>   (?<PerlStdOWS>
            (?:
                \h++
            |
                (?&PPR_X_newline_and_heredoc)
            |
                [#] [^\n]*+
            )*+
    )) # End of rule

        (?<PerlNWS>   (?<PerlStdNWS>
            (?:
                \h++
            |
                (?&PPR_X_newline_and_heredoc)
            |
                [#] [^\n]*+
            )++
    )) # End of rule

        (?<PerlEndOfLine>   (?<PerlStdEndOfLine>
            \n
    )) # End of rule


        ###### Internal components (not part of API) ##########################

        (?<PPR_X_named_op>
            (?> cmp
            |   [lg][te]
            |   eq
            |   ne
            |   and
            |   or
            |   xor
            )
        ) # End of rule (?<PPR_X_named_op>)

        (?<PPR_X_non_reserved_identifier>
            (?! (?>
                for(?:each)?+ | while | if | unless | until | given | when | default
                |  sub | format | use | no
                |  (?&PPR_X_named_op)
                |  [msy] | q[wrxq]?+ | tr
                |   __ (?> END | DATA ) __
                )
                \b
            )
            (?>(?&PerlQualifiedIdentifier))
            (?! :: )
        ) # End of rule (?<PPR_X_non_reserved_identifier>)

        (?<PPR_X_three_part_list>
            \(  (?>(?&PerlOWS)) (?: (?>(?&PerlExpression)) (?&PerlOWS) )??
            ;  (?>(?&PerlOWS)) (?: (?>(?&PerlExpression)) (?&PerlOWS) )??
            ;  (?>(?&PerlOWS)) (?: (?>(?&PerlExpression)) (?&PerlOWS) )??
            \)
        ) # End of rule (?<PPR_X_three_part_list>)

        (?<PPR_X_indirect_obj>
            (?&PerlBareword)
        |
            (?>(?&PerlVariableScalar))
            (?! (?>(?&PerlOWS)) (?> [<\[\{] | -> ) )
        ) # End of rule (?<PPR_X_indirect_obj>)

        (?<PPR_X_quotelike_body>
            (?>(?&PPR_X_quotelike_body_unclosed))
            \S   # (Note: Don't have to test that this matches; the preceding subrule already did that)
        ) # End of rule (?<PPR_X_quotelike_body>)

        (?<PPR_X_balanced_parens>
            [^)(\\\n]*+
            (?:
                (?>
                    \\.
                |
                    \(  (?>(?&PPR_X_balanced_parens))  \)
                |
                    (?&PPR_X_newline_and_heredoc)
                )
                [^)(\\\n]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_parens>)

        (?<PPR_X_balanced_curlies>
            [^\}\{\\\n]*+
            (?:
                (?>
                    \\.
                |
                    \{  (?>(?&PPR_X_balanced_curlies))  \}
                |
                    (?&PPR_X_newline_and_heredoc)
                )
                [^\}\{\\\n]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_curlies>)

        (?<PPR_X_balanced_squares>
            [^][\\\n]*+
            (?:
                (?>
                    \\.
                |
                    \[  (?>(?&PPR_X_balanced_squares))  \]
                |
                    (?&PPR_X_newline_and_heredoc)
                )
                [^][\\\n]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_squares>)

        (?<PPR_X_balanced_angles>
            [^><\\\n]*+
            (?:
                (?>
                    \\.
                |
                    <  (?>(?&PPR_X_balanced_angles))  >
                |
                    (?&PPR_X_newline_and_heredoc)
                )
                [^><\\\n]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_angles>)

        (?<PPR_X_regex_body_unclosed>
            (?>
                [#]
                [^#\\\n]*+
                (?:
                    (?: \\. | (?&PPR_X_newline_and_heredoc) )
                    [^#\\\n]*+
                )*+
                (?= [#] )
            |
                (?>(?&PerlOWS))
                (?>
                    \{  (?>(?&PPR_X_balanced_curlies))            (?= \} )
                |
                    \[  (?>(?&PPR_X_balanced_squares))            (?= \] )
                |
                    \(  (?:
                            \?{1,2} (?= \{ ) (?>(?&PerlBlock))
                        |
                            (?>(?&PPR_X_balanced_parens))
                        )                                       (?= \) )
                |
                    <  (?>(?&PPR_X_balanced_angles))             (?=  > )
                |
                    \\
                        [^\\\n]*+
                        (
                            (?&PPR_X_newline_and_heredoc)
                            [^\\\n]*+
                        )*+
                    (?= \\ )
                |
                    /
                        [^\\/\n]*+
                    (?:
                        (?: \\. | (?&PPR_X_newline_and_heredoc) )
                        [^\\/\n]*+
                    )*+
                    (?=  / )
                |
                    (?<PPR_X_qldel> \S )
                        (?:
                            \\.
                        |
                            (?&PPR_X_newline_and_heredoc)
                        |
                            (?! \g{PPR_X_qldel} ) .
                        )*+
                    (?= \g{PPR_X_qldel} )
                )
            )
        ) # End of rule (?<PPR_X_regex_body_unclosed>)

        (?<PPR_X_quotelike_body_unclosed>
            (?>
                [#]
                [^#\\\n]*+
                (?:
                    (?: \\. | (?&PPR_X_newline_and_heredoc) )
                    [^#\\\n]*+
                )*+
                (?= [#] )
            |
                (?>(?&PerlOWS))
                (?>
                    \{  (?>(?&PPR_X_balanced_curlies))    (?= \} )
                |
                    \[  (?>(?&PPR_X_balanced_squares))    (?= \] )
                |
                    \(  (?>(?&PPR_X_balanced_parens))     (?= \) )
                |
                    <  (?>(?&PPR_X_balanced_angles))     (?=  > )
                |
                    \\
                        [^\\\n]*+
                        (
                            (?&PPR_X_newline_and_heredoc)
                            [^\\\n]*+
                        )*+
                    (?= \\ )
                |
                    /
                        [^\\/\n]*+
                    (?:
                        (?: \\. | (?&PPR_X_newline_and_heredoc) )
                        [^\\/\n]*+
                    )*+
                    (?=  / )
                |
                    (?<PPR_X_qldel> \S )
                        (?:
                            \\.
                        |
                            (?&PPR_X_newline_and_heredoc)
                        |
                            (?! \g{PPR_X_qldel} ) .
                        )*+
                    (?= \g{PPR_X_qldel} )
                )
            )
        ) # End of rule (?<PPR_X_quotelike_body_unclosed>)

        (?<PPR_X_quotelike_body_interpolated>
            (?>(?&PPR_X_quotelike_body_interpolated_unclosed))
            \S   # (Note: Don't have to test that this matches; the preceding subrule already did that)
        ) # End of rule (?<PPR_X_quotelike_body_interpolated>)

        (?<PPR_X_regex_body_interpolated>
            (?>(?&PPR_X_regex_body_interpolated_unclosed))
            \S   # (Note: Don't have to test that this matches; the preceding subrule already did that)
        ) # End of rule (?<PPR_X_regex_body_interpolated>)

        (?<PPR_X_balanced_parens_interpolated>
            [^)(\\\n\$\@]*+
            (?:
                (?>
                    \\.
                |
                    \(  (?>(?&PPR_X_balanced_parens_interpolated))  \)
                |
                    (?&PPR_X_newline_and_heredoc)
                |
                    (?= \$ (?! [\s\)] ) )  (?&PerlScalarAccessNoSpace)
                |
                    (?= \@ (?! [\s\)] ) )  (?&PerlArrayAccessNoSpace)
                |
                    [\$\@]
                )
                [^)(\\\n\$\@]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_parens_interpolated>)

        (?<PPR_X_balanced_curlies_interpolated>
            [^\}\{\\\n\$\@]*+
            (?:
                (?>
                    \\.
                |
                    \{  (?>(?&PPR_X_balanced_curlies_interpolated))  \}
                |
                    (?&PPR_X_newline_and_heredoc)
                |
                    (?= \$ (?! [\s\}] ) )  (?&PerlScalarAccessNoSpace)
                |
                    (?= \@ (?! [\s\}] ) )  (?&PerlArrayAccessNoSpace)
                |
                    [\$\@]
                )
                [^\}\{\\\n\$\@]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_curlies_interpolated>)

        (?<PPR_X_balanced_squares_interpolated>
            [^][\\\n\$\@]*+
            (?:
                (?>
                    \\.
                |
                    \[  (?>(?&PPR_X_balanced_squares_interpolated))  \]
                |
                    (?&PPR_X_newline_and_heredoc)
                |
                    (?= \$ (?! [\s\]] ) )  (?&PerlScalarAccessNoSpace)
                |
                    (?= \@ (?! [\s\]] ) )  (?&PerlArrayAccessNoSpace)
                |
                    [\$\@]
                )
                [^][\\\n\$\@]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_squares_interpolated>)

        (?<PPR_X_balanced_angles_interpolated>
            [^><\\\n\$\@]*+
            (?:
                (?>
                    \\.
                |
                    <  (?>(?&PPR_X_balanced_angles_interpolated))  >
                |
                    (?&PPR_X_newline_and_heredoc)
                |
                    (?= \$ (?! [\s>] ) )  (?&PerlScalarAccessNoSpace)
                |
                    (?= \@ (?! [\s>] ) )  (?&PerlArrayAccessNoSpace)
                |
                    [\$\@]
                )
                [^><\\\n\$\@]*+
            )*+
        ) # End of rule (?<PPR_X_balanced_angles_interpolated>)

        (?<PPR_X_regex_body_interpolated_unclosed>
            # Start by working out where it actually ends (ignoring interpolations)...
            (?=
                (?>
                    [#]
                    [^#\\\n\$\@]*+
                    (?:
                        (?>
                            \\.
                        |
                            (?&PPR_X_newline_and_heredoc)
                        |
                            (?= \$ (?! [\s#] ) )  (?&PerlScalarAccessNoSpace)
                        |
                            (?= \@ (?! [\s#] ) )  (?&PerlArrayAccessNoSpace)
                        |
                            [\$\@]
                        )
                        [^#\\\n\$\@]*+
                    )*+
                    (?= [#] )
                |
                    (?>(?&PerlOWS))
                    (?>
                        \{  (?>(?&PPR_X_balanced_curlies_interpolated))    (?= \} )
                    |
                        \[  (?>(?&PPR_X_balanced_squares_interpolated))    (?= \] )
                    |
                        \(  (?>(?&PPR_X_balanced_parens_interpolated))     (?= \) )
                    |
                        <   (?>(?&PPR_X_balanced_angles_interpolated))     (?=  > )
                    |
                        \\
                            [^\\\n\$\@]*+
                            (?:
                                (?>
                                    (?&PPR_X_newline_and_heredoc)
                                |
                                    (?= \$ (?! [\s\\] ) )  (?&PerlScalarAccessNoSpace)
                                |
                                    (?= \@ (?! [\s\\] ) )  (?&PerlArrayAccessNoSpace)
                                |
                                    [\$\@]
                                )
                                [^\\\n\$\@]*+
                            )*+
                        (?= \\ )
                    |
                        /
                            [^\\/\n\$\@]*+
                            (?:
                                (?>
                                    \\.
                                |
                                    (?&PPR_X_newline_and_heredoc)
                                |
                                    (?= \$ (?! [\s/] ) )  (?&PerlScalarAccessNoSpace)
                                |
                                    (?= \@ (?! [\s/] ) )  (?&PerlArrayAccessNoSpace)
                                |
                                    [\$\@]
                                )
                                [^\\/\n\$\@]*+
                            )*+
                        (?= / )
                    |
                        -
                            (?:
                                \\.
                            |
                                (?&PPR_X_newline_and_heredoc)
                            |
                                (?:
                                    (?= \$ (?! [\s-] ) )  (?&PerlScalarAccessNoSpaceNoArrow)
                                |
                                    (?= \@ (?! [\s-] ) )  (?&PerlArrayAccessNoSpaceNoArrow)
                                |
                                    [^-]
                                )
                            )*+
                        (?= - )
                    |
                        (?<PPR_X_qldel> \S )
                            (?:
                                \\.
                            |
                                (?&PPR_X_newline_and_heredoc)
                            |
                                (?! \g{PPR_X_qldel} )
                                (?:
                                    (?= \$ (?! \g{PPR_X_qldel} | \s ) )  (?&PerlScalarAccessNoSpace)
                                |
                                    (?= \@ (?! \g{PPR_X_qldel} | \s ) )  (?&PerlArrayAccessNoSpace)
                                |
                                    .
                                )
                            )*+
                        (?= \g{PPR_X_qldel} )
                    )
                )
            )

            (?&PPR_X_regex_body_unclosed)
        ) # End of rule (?<PPR_X_regex_body_interpolated_unclosed>)

        (?<PPR_X_quotelike_body_interpolated_unclosed>
            # Start by working out where it actually ends (ignoring interpolations)...
            (?=
                (?>
                    [#]
                    [^#\\\n\$\@]*+
                    (?:
                        (?>
                            \\.
                        |
                            (?&PPR_X_newline_and_heredoc)
                        |
                            (?= \$ (?! [\s#] ) )  (?&PerlScalarAccessNoSpace)
                        |
                            (?= \@ (?! [\s#] ) )  (?&PerlArrayAccessNoSpace)
                        |
                            [\$\@]
                        )
                        [^#\\\n\$\@]*+
                    )*+
                    (?= [#] )
                |
                    (?>(?&PerlOWS))
                    (?>
                        \{  (?>(?&PPR_X_balanced_curlies_interpolated))    (?= \} )
                    |
                        \[  (?>(?&PPR_X_balanced_squares_interpolated))    (?= \] )
                    |
                        \(  (?>(?&PPR_X_balanced_parens_interpolated))     (?= \) )
                    |
                        <   (?>(?&PPR_X_balanced_angles_interpolated))     (?=  > )
                    |
                        \\
                            [^\\\n\$\@]*+
                            (?:
                                (?>
                                    (?&PPR_X_newline_and_heredoc)
                                |
                                    (?= \$ (?! [\s\\] ) )  (?&PerlScalarAccessNoSpace)
                                |
                                    (?= \@ (?! [\s\\] ) )  (?&PerlArrayAccessNoSpace)
                                |
                                    [\$\@]
                                )
                                [^\\\n\$\@]*+
                            )*+
                        (?= \\ )
                    |
                        /
                            [^\\/\n\$\@]*+
                            (?:
                                (?>
                                    \\.
                                |
                                    (?&PPR_X_newline_and_heredoc)
                                |
                                    (?= \$ (?! [\s/] ) )  (?&PerlScalarAccessNoSpace)
                                |
                                    (?= \@ (?! [\s/] ) )  (?&PerlArrayAccessNoSpace)
                                |
                                    [\$\@]
                                )
                                [^\\/\n\$\@]*+
                            )*+
                        (?= / )
                    |
                        -
                            (?:
                                \\.
                            |
                                (?&PPR_X_newline_and_heredoc)
                            |
                                (?:
                                    (?= \$ (?! [\s-] ) )  (?&PerlScalarAccessNoSpaceNoArrow)
                                |
                                    (?= \@ (?! [\s-] ) )  (?&PerlArrayAccessNoSpaceNoArrow)
                                |
                                    [^-]
                                )
                            )*+
                        (?= - )
                    |
                        (?<PPR_X_qldel> \S )
                            (?:
                                \\.
                            |
                                (?&PPR_X_newline_and_heredoc)
                            |
                                (?! \g{PPR_X_qldel} )
                                (?:
                                    (?= \$ (?! \g{PPR_X_qldel} | \s ) )  (?&PerlScalarAccessNoSpace)
                                |
                                    (?= \@ (?! \g{PPR_X_qldel} | \s ) )  (?&PerlArrayAccessNoSpace)
                                |
                                    .
                                )
                            )*+
                        (?= \g{PPR_X_qldel} )
                    )
                )
            )

            (?&PPR_X_quotelike_body_unclosed)
        ) # End of rule (?<PPR_X_quotelike_body_interpolated_unclosed>)

        (?<PPR_X_quotelike_s_e_check>
            (??{ local $PPR::X::_quotelike_s_end = -1; '' })
            (?:
                (?=
                    (?&PPR_X_quotelike_body_interpolated)
                    (??{ $PPR::X::_quotelike_s_end = +pos(); '' })
                    [msixpodualgcrn]*+ e [msixpodualgcern]*+
                )
                (?=
                    (?(?{ $PPR::X::_quotelike_s_end >= 0 })
                        (?>
                            (??{ +pos() && +pos() < $PPR::X::_quotelike_s_end ? '' : '(?!)' })
                            (?>
                                (?&PerlExpression)
                            |
                                \\?+ .
                            )
                        )*+
                    )
                )
            )?+
        ) # End of rule (?<PPR_X_quotelike_s_e_check>)

        (?<PPR_X_filetest_name>   [ABCMORSTWXbcdefgkloprstuwxz]          )

        (?<PPR_X_digit_seq>               \d++ (?: _?+         \d++ )*+  )
        (?<PPR_X_x_digit_seq>     [\da-fA-F]++ (?: _?+ [\da-fA-F]++ )*+  )
        (?<PPR_X_o_digit_seq>          [0-7]++ (?: _?+      [0-7]++ )*+  )
        (?<PPR_X_b_digit_seq>          [0-1]++ (?: _?+      [0-1]++ )*+  )

        (?<PPR_X_newline_and_heredoc>
            \n (??{ ($PPR::X::_heredoc_origin // q{}) eq ($_//q{}) ? ($PPR::X::_heredoc_skip{+pos()} // q{}) : q{} })
        ) # End of rule (?<PPR_X_newline_and_heredoc>)
    )
}xms;

sub decomment {
    if ($] >= 5.014 && $] < 5.016) { _croak( "PPR::X::decomment() does not work under Perl 5.14" )}

    my ($str) = @_;

    local %PPR::X::comment_len;

    # Locate comments...
    $str =~ m{  (?&PerlEntireDocument)

                (?(DEFINE)
                    (?<decomment>
                       ( (?<! [\$@%] ) [#] [^\n]*+ )
                       (?{
                            my $len = length($^N);
                            my $pos = pos() - $len;
                            $PPR::X::comment_len{$pos} = $len;
                       })
                    )

                    (?<PerlOWS>
                        (?:
                            \h++
                        |
                            (?&PPR_X_newline_and_heredoc)
                        |
                            (?&decomment)
                        |
                            __ (?> END | DATA ) __ \b .*+ \z
                        )*+
                    ) # End of rule

                    (?<PerlNWS>
                        (?:
                            \h++
                        |
                            (?&PPR_X_newline_and_heredoc)
                        |
                            (?&decomment)
                        |
                            __ (?> END | DATA ) __ \b .*+ \z
                        )++

                    ) # End of rule

                    (?<PerlPod>
                        (
                            ^ = [^\W\d]\w*+
                            .*?
                            (?>
                                ^ = cut \b [^\n]*+ $
                            |
                                \z
                            )
                        )
                        (?{
                            my $len = length($^N);
                            my $pos = pos() - $len;
                            $PPR::X::comment_len{$pos} = $len;
                        })
                    ) # End of rule

                    $PPR::X::GRAMMAR
                )
            }xms or return;

    # Delete the comments found...
    for my $from_pos (_uniq(sort { $b <=> $a } keys %PPR::X::comment_len)) {
        substr($str, $from_pos, $PPR::X::comment_len{$from_pos}) =~ s/.+//g;
    }

    return $str;
}

sub _uniq {
    my %seen;
    return grep {!$seen{$_}++} @_;
}

sub _croak {
    require Carp;
    Carp::croak(@_);
}

sub _report {
    state $BUFFER = q{ } x 10;
    state $depth = 0;
    my ($msg, $increment) = @_;
    $depth++ if $increment;
    my $at = pos();
    my $str = $BUFFER . $_ . $BUFFER;
    my $pre  = substr($str, $at,    10);
    my $post = substr($str, $at+10, 10);
    tr/\n/ / for $pre, $post;
    warn sprintf("%10s|%-10s|  %s%s\n", $pre, $post, q{ } x $depth, $msg);
    $depth-- if !$increment;
}

1; # Magic true value required at end of module

__END__

=head1 NAME

PPR::X - Pattern-based Perl Recognizer


=head1 VERSION

This document describes PPR::X version 0.000027


=head1 SYNOPSIS

    use PPR::X;

    # Define a regex that will match an entire Perl document...
    my $perl_document = qr{

        # What to match            # Install the (?&PerlDocument) rule
        (?&PerlEntireDocument)     $PPR::X::GRAMMAR

    }x;


    # Define a regex that will match a single Perl block...
    my $perl_block = qr{

        # What to match...         # Install the (?&PerlBlock) rule...
        (?&PerlBlock)              $PPR::X::GRAMMAR
    }x;


    # Define a regex that will match a simple Perl extension...
    my $perl_coroutine = qr{

        # What to match...
        coro                                           (?&PerlOWS)
        (?<coro_name>  (?&PerlQualifiedIdentifier)  )  (?&PerlOWS)
        (?<coro_code>  (?&PerlBlock)                )

        # Install the necessary subrules...
        $PPR::X::GRAMMAR
    }x;


    # Define a regex that will match an integrated Perl extension...
    my $perl_with_classes = qr{

        # What to match...
        \A
            (?&PerlOWS)       # Optional whitespace (including comments)
            (?&PerlDocument)  # A full Perl document
            (?&PerlOWS)       # More optional whitespace
        \Z

        # Add a 'class' keyword into the syntax that PPR::X understands...
        (?(DEFINE)
            (?<PerlKeyword>

                    class                              (?&PerlOWS)
                    (?&PerlQualifiedIdentifier)        (?&PerlOWS)
                (?: is (?&PerlNWS) (?&PerlIdentifier)  (?&PerlOWS) )*+
                    (?&PerlBlock)
            )

            (?<kw_balanced_parens>
                \( (?: [^()]++ | (?&kw_balanced_parens) )*+ \)
            )
        )

        # Install the necessary standard subrules...
        $PPR::X::GRAMMAR
    }x;


=head1 DESCRIPTION

The PPR::X module provides a single regular expression that defines a set
of independent subpatterns suitable for matching entire Perl documents,
as well as a wide range of individual syntactic components of Perl
(i.e. statements, expressions, control blocks, variables, etc.)

The regex does not "parse" Perl (that is, it does not build a syntax
tree, like the PPI module does). Instead it simply "recognizes" standard
Perl constructs, or new syntaxes composed from Perl constructs.

Its features and capabilities therefore complement those of the PPI
module, rather than replacing them. See L<"Comparison with PPI">.


=head1 INTERFACE

=head2 Importing and using the Perl grammar regex

The PPR::X module exports no subroutines or variables,
and provides no methods. Instead, it defines a single
package variable, C<$PPR::X::GRAMMAR>, which can be
interpolated into regexes to add rules that permit
Perl constructs to be parsed:

    $source_code =~ m{ (?&PerlEntireDocument)  $PPR::X::GRAMMAR }x;

Note that all the examples shown so far have interpolated this "grammar
variable" at the end of the regular expression. This placement is
desirable, but not necessary. Both of the following work identically:

    $source_code =~ m{ (?&PerlEntireDocument)   $PPR::X::GRAMMAR }x;

    $source_code =~ m{ $PPR::X::GRAMMAR   (?&PerlEntireDocument) }x;


However, if the grammar is to be L<extended|"Extending the Perl syntax with keywords">,
then the extensions must be specified B<I<before>> the base grammar
(i.e. before the interpolation of C<$PPR::X::GRAMMAR>). Placing the grammar
variable at the end of a regex ensures that will be the case, and has
the added advantage of "front-loading" the regex with the most important
information: what is actually going to be matched.

Note too that, because the PPR::X grammar internally uses capture groups,
placing C<$PPR::X::GRAMMAR> anywhere other than the very end of your regex
may change the numbering of any explicit capture groups in your regex.
For complete safety, regexes that use the PPR::X grammar should probably
use named captures, instead of numbered captures.


=head2 Error reporting

Regex-based parsing is all-or-nothing: either your regex matches
(and returns any captures you requested), or it fails to match
(and returns nothing).

This can make it difficult to detect I<why> a PPR::X-based match failed;
to work out what the "bad source code" was that prevented your regex
from matching.

So the module provides a special variable that attempts to detect the
source code that prevented any call to the C<(?&PerlStatement)> subpattern
from matching. That variable is: C<$PPR::X::ERROR>

C<$PPR::X::ERROR> is only set if it is undefined at the point where an
error is detected, and will only be set to the first such error that
is encountered during parsing.

Note that errors are only detected when matching context-sensitive components
(for example in the middle of a C<(?&PerlStatement), as part of a
C<(?&PerlContextualRegex)>, or at the end of a C<(?&PerlEntireDocument>)>.
Errors, especially errors at the end of otherwise valid code, will often
not be detected in context-free components (for example, at the end of a
C<(?&PerlStatementSequence), as part of a C<(?&PerlRegex)>, or at the
end of a C<(?&PerlDocument>)>.

A common mistake in this area is to attempt to match an entire Perl document
using:

    m{ \A (?&PerlDocument) \Z   $PPR::X::GRAMMAR }x

instead of:

    m{ (?&PerlEntireDocument)   $PPR::X::GRAMMAR }x

Only the second approach will be able to successfully detect an unclosed
curly bracket at the end of the document.


=head3 C<PPR_X::ERROR> interface

If it is set, C<$PPR::X::ERROR> will contain an object of type PPR::X::ERROR,
with the following methods:

=over

=item C<< $PPR::X::ERROR->origin($line, $file) >>

Returns a clone of the PPR::X::ERROR object that now believes that the
source code parsing failure it is reporting occurred in a code fragment
starting at the specified line and file. If the second argument is
omitted, the file name is not reported in any diagnostic.

=item C<< $PPR::X::ERROR->source() >>

Returns a string containing the specific source code that could not be
parsed as a Perl statement.

=item C<< $PPR::X::ERROR->prefix() >>

Returns a string containing all the source code preceding the
code that could not be parsed. That is: the valid code that is
the preceding context of the unparsable code.

=item C<< $PPR::X::ERROR->line( $opt_offset ) >>

Returns an integer which is the line number at which the unparsable
code was encountered. If the optional "offset" argument is provided,
it will be added to the line number returned. Note that the offset
is ignored if the PPR::X::ERROR object originates from a prior call to
C<< $PPR::X::ERROR->origin >> (because in that case you will have already
specified the correct offset).

=item C<< $PPR::X::ERROR->diagnostic() >>

Returns a string containing the diagnostic that would be returned
by C<perl -c> if the source code were compiled.

B<I<Warning:>> The diagnostic is obtained by partially eval'ing
the source code. This means that run-time code will not be executed,
but C<BEGIN> and C<CHECK> blocks will run. Do B<I<not>> call this method
if the source code that created this error might also have non-trivial
compile-time side-effects.

=back

A typical use might therefore be:

    # Make sure it's undefined, and will only be locally modified...
    local $PPR::X::ERROR;

    # Process the matched block...
    if ($source_code =~ m{ (?<Block> (?&PerlBlock) )  $PPR::X::GRAMMAR }x) {
        process( $+{Block} );
    }

    # Or report the offending code that stopped it being a valid block...
    else {
        die "Invalid Perl block: " . $PPR::X::ERROR->source . "\n",
            $PPR::X::ERROR->origin($linenum, $filename)->diagnostic . "\n";
    }

=head2 Decommenting code with C<PPR_X::decomment()>

The module provides (but does not export) a C<decomment()>
subroutine that can remove any comments and/or POD from source code.

It takes a single argument: a string containing the course code.
It returns a single value: a string containing the decommented source code.

For example:

    $decommented_code = PPR::X::decomment( $commented_code );

The subroutine will fail if the argument wasn't valid Perl code,
in which case it returns C<undef> and sets C<$PPR::X::ERROR> to indicate
where the invalid source code was encountered.

Note that, due to separate bugs in the regex engine in Perl 5.14 and
5.20, the C<decomment()> subroutine is not available when running under
these releases.


=head2 Examples

I<Note:> In each of the following examples, the subroutine C<slurp()> is
used to acquire the source code from a file whose name is passed as its
argument. The C<slurp()> subroutine is just:

    sub slurp { local (*ARGV, $/); @ARGV = shift; readline; }

or, for the less twisty-minded:

    sub slurp {
        my ($filename) = @_;
        open my $filehandle, '<', $filename or die $!;
        local $/;
        return readline($filehandle);
    }


=head3 Validating source code

  # "Valid" if source code matches a Perl document under the Perl grammar
  printf(
      "$filename %s a valid Perl file\n",
      slurp($filename) =~ m{ (?&PerlEntireDocument)  $PPR::X::GRAMMAR }x
          ? "is"
          : "is not"
  );


=head3 Counting statements

  printf(                                        # Output
      "$filename contains %d statements\n",      # a report of
      scalar                                     # the count of
          grep {defined}                         # defined matches
              slurp($filename)                   # from the source code,
                  =~ m{
                        \G (?&PerlOWS)           # skipping whitespace
                           ((?&PerlStatement))   # and keeping statements,
                        $PPR::X::GRAMMAR            # using the Perl grammar
                      }gcx;                      # incrementally
  );


=head3 Stripping comments and POD from source code

  my $source = slurp($filename);                    # Get the source
  $source =~ s{ (?&PerlNWS)  $PPR::X::GRAMMAR }{ }gx;  # Compact whitespace
  print $source;                                    # Print the result


=head3 Stripping comments and POD from source code (in Perl v5.14 or later)

  # Print  the source code,  having compacted whitespace...
    print  slurp($filename)  =~ s{ (?&PerlNWS)  $PPR::X::GRAMMAR }{ }gxr;


=head3 Stripping everything C<except> comments and POD from source code

  say                                         # Output
      grep {defined}                          # defined matches
          slurp($filename)                    # from the source code,
              =~ m{ \G ((?&PerlOWS))          # keeping whitespace,
                       (?&PerlStatement)?     # skipping statements,
                    $PPR::X::GRAMMAR             # using the Perl grammar
                  }gcx;                       # incrementally


=head2 Available rules

Interpolating C<$PPR::X::GRAMMAR> in a regex makes all of the following
rules available within that regex.

Note that other rules not listed here may also be added, but these are
all considered strictly internal to the PPR::X module and are not
guaranteed to continue to exist in future releases. All such
"internal-use-only" rules have names that start with C<PPR_X_>...


=head3 C<< (?&PerlDocument) >>

Matches a valid Perl document, including leading or trailing
whitespace, comments, and any final C<__DATA__> or C<__END__> section.

This rule is context-free, so it can be embedded in a larger regex.
For example, to match an embedded chunk of Perl code, delimited by
C<<<< <<< >>>>...C<<<< >>> >>>>:

    $src = m{ <<< (?&PerlDocument) >>>   $PPR::X::GRAMMAR }x;


=head3 C<< (?&PerlEntireDocument) >>

Matches an entire valid Perl document, including leading or trailing
whitespace, comments, and any final C<__DATA__> or C<__END__> section.

This rule is I<not> context-free. It has an internal C<\A> at the beginning
and C<\Z> at the end, so a regex containing C<(?&PerlEntireDocument)>
will only match if:

=over

=item (a)

the C<(?&PerlEntireDocument)> is the sole top-level element of the regex
(or, at least the sole element of a single top-level C<|>-branch of the regex),

=item B<I<and>>


=item (b)

the entire string being matched contains only a single valid Perl document.

=back

In general, if you want to check that a string consists entirely of
a single valid sequence of Perl code, use:

    $str =~ m{ (?&PerlEntireDocument)  $PPR::X::GRAMMAR }

If you want to check that a string I<contains> at least one valid sequence
of Perl code at some point, possibly embedded in other text, use:

    $str =~ m{ (?&PerlDocument)  $PPR::X::GRAMMAR }


=head3 C<< (?&PerlStatementSequence) >>

Matches zero-or-more valid Perl statements, separated by optional
POD sequences.


=head3 C<< (?&PerlStatement) >>

Matches a single valid Perl statement, including: control structures;
C<BEGIN>, C<CHECK>, C<UNITCHECK>, C<INIT>, C<END>, C<DESTROY>, or
C<AUTOLOAD> blocks; variable declarations, C<use> statements, etc.


=head3 C<< (?&PerlExpression) >>

Matches a single valid Perl expression involving operators of any
precedence, but not any kind of block (i.e. not control structures,
C<BEGIN> blocks, etc.) nor any trailing statement modifier (e.g.
not a postfix C<if>, C<while>, or C<for>).


=head3 C<< (?&PerlLowPrecedenceNotExpression) >>

Matches an expression at the precedence of the C<not> operator.
That is, a single valid Perl expression that involves operators above
the precedence of C<and>.


=head3 C<< (?&PerlAssignment) >>

Matches an assignment expression.
That is, a single valid Perl expression involving operators above the
precedence of comma (C<,> or C<< => >>).


=head3 C<< (?&PerlConditionalExpression) >> or C<< (?&PerlScalarExpression) >>

Matches a conditional expression that uses the C<?>...C<:> ternary operator.
That is, a single valid Perl expression involving operators above the
precedence of assignment.

The alterative name comes from the fact that anything matching this rule
is what most people think of as a single element of a comma-separated list.


=head3 C<< (?&PerlBinaryExpression) >>

Matches an expression that uses any high-precedence binary operators.
That is, a single valid Perl expression involving operators above the
precedence of the ternary operator.


=head3 C<< (?&PerlPrefixPostfixTerm) >>

Matches a term with optional prefix and/or postfix unary operators
and/or a trailing sequence of C<< -> >> dereferences.
That is, a single valid Perl expression involving operators above the
precedence of exponentiation (C<**>).


=head3 C<< (?&PerlTerm) >>

Matches a simple high-precedence term within a Perl expression.
That is: a subroutine or builtin function call; a variable declaration;
a variable or typeglob lookup; an anonymous array, hash, or subroutine
constructor; a quotelike or numeric literal; a regex match; a
substitution; a transliteration; a C<do> or C<eval> block; or any other
expression in surrounding parentheses.


=head3 C<< (?&PerlTermPostfixDereference) >>

Matches a sequence of array- or hash-lookup brackets, or subroutine call
parentheses, or a postfix dereferencer (e.g. C<< ->$* >>), with
explicit or implicit intervening C<< -> >>, such as might appear after a term.


=head3 C<< (?&PerlLvalue) >>

Matches any variable or parenthesized list of variables that could
be assigned to.


=head3 C<< (?&PerlPackageDeclaration) >>

Matches the declaration of any package
(with or without a defining block).


=head3 C<< (?&PerlSubroutineDeclaration) >>

Matches the declaration of any named subroutine
(with or without a defining block).


=head3 C<< (?&PerlUseStatement) >>

Matches a C<< use <module name> ...; >> or C<< use <version number>; >> statement.


=head3 C<< (?&PerlReturnStatement) >>

Matches a C<< return <expression>; >> or C<< return; >> statement.


=head3 C<< (?&PerlReturnExpression) >>

Matches a C<< return <expression> >>
as an expression without trailing end-of-statement markers.


=head3 C<< (?&PerlControlBlock) >>

Matches an C<if>, C<unless>, C<while>, C<until>, C<for>, or C<foreach>
statement, including its block.


=head3 C<< (?&PerlDoBlock) >>

Matches a C<do>-block expression.


=head3 C<< (?&PerlEvalBlock) >>

Matches a C<eval>-block expression.


=head3 C<< (?&PerlStatementModifier) >>

Matches an C<if>, C<unless>, C<while>, C<until>, C<for>, or C<foreach>
modifier that could appear after a statement. Only matches the modifier, not
the preceding statement.



=head3 C<< (?&PerlFormat) >>

Matches a C<format> declaration, including its terminating "dot".



=head3 C<< (?&PerlBlock) >>

Matches a C<{>...C<}>-delimited block containing zero-or-more statements.


=head3 C<< (?&PerlCall) >>

Matches a class to a subroutine or built-in function.
Accepts all valid call syntaxes,
either via a literal names or a reference,
with or without a leading C<&>,
with or without arguments,
with or without parentheses on any argument list.


=head3 C<< (?&PerlAttributes) >>

Matches a list of colon-preceded attributes, such as might be specified
on the declaration of a subroutine or a variable.


=head3 C<< (?&PerlCommaList) >>

Matches a list of zero-or-more comma-separated subexpressions.
That is, a single valid Perl expression that involves operators above the
precedence of C<not>.


=head3 C<< (?&PerlParenthesesList) >>

Matches a list of zero-or-more comma-separated subexpressions inside
a set of parentheses.


=head3 C<< (?&PerlList) >>

Matches either a parenthesized or unparenthesized list of
comma-separated subexpressions. That is, matches anything that either of
the two preceding rules would match.


=head3 C<< (?&PerlAnonymousArray) >>

Matches an anonymous array constructor.
That is: a list of zero-or-more subexpressions inside square brackets.

=head3 C<< (?&PerlAnonymousHash) >>

Matches an anonymous hash constructor.
That is: a list of zero-or-more subexpressions inside curly brackets.


=head3 C<< (?&PerlArrayIndexer) >>

Matches a valid indexer that could be applied to look up elements of a array.
That is: a list of or one-or-more subexpressions inside square brackets.

=head3 C<< (?&PerlHashIndexer) >>

Matches a valid indexer that could be applied to look up entries of a hash.
That is: a list of or one-or-more subexpressions inside curly brackets,
or a simple bareword indentifier inside curley brackets.


=head3 C<< (?&PerlDiamondOperator) >>

Matches anything in angle brackets.
That is: any "diamond" readline (e.g. C<< <$filehandle> >>
or file-grep operation (e.g. C<< <*.pl> >>).


=head3 C<< (?&PerlComma) >>

Matches a short (C<,>) or long (C<< => >>) comma.


=head3 C<< (?&PerlPrefixUnaryOperator) >>

Matches any high-precedence prefix unary operator.


=head3 C<< (?&PerlPostfixUnaryOperator) >>

Matches any high-precedence postfix unary operator.


=head3 C<< (?&PerlInfixBinaryOperator) >>

Matches any infix binary operator
whose precedence is between C<..> and C<**>.


=head3 C<< (?&PerlAssignmentOperator) >>

Matches any assignment operator,
including all I<op>C<=> variants.


=head3 C<< (?&PerlLowPrecedenceInfixOperator) >>

Matches C<and>, <or>, or C<xor>.


=head3 C<< (?&PerlAnonymousSubroutine) >>

Matches an anonymous subroutine.


=head3 C<< (?&PerlVariable) >>

Matches any type of access on any scalar, array, or hash
variable.


=head3 C<< (?&PerlVariableScalar) >>

Matches any scalar variable,
including fully qualified package variables,
punctuation variables, scalar dereferences,
and the C<$#array> syntax.


=head3 C<< (?&PerlVariableArray) >>

Matches any array variable,
including fully qualified package variables,
punctuation variables, and array dereferences.


=head3 C<< (?&PerlVariableHash) >>

Matches any hash variable,
including fully qualified package variables,
punctuation variables, and hash dereferences.


=head3 C<< (?&PerlTypeglob) >>

Matches a typeglob.


=head3 C<< (?&PerlScalarAccess) >>

Matches any kind of variable access
beginning with a C<$>,
including fully qualified package variables,
punctuation variables, scalar dereferences,
the C<$#array> syntax, and single-value
array or hash look-ups.


=head3 C<< (?&PerlScalarAccessNoSpace) >>

Matches any kind of variable access beginning with a C<$>, including
fully qualified package variables, punctuation variables, scalar
dereferences, the C<$#array> syntax, and single-value array or hash
look-ups.
But does not allow spaces between the components of the
variable access (i.e. imposes the same constraint as within an
interpolating quotelike).


=head3 C<< (?&PerlScalarAccessNoSpaceNoArrow) >>

Matches any kind of variable access beginning with a C<$>, including
fully qualified package variables, punctuation variables, scalar
dereferences, the C<$#array> syntax, and single-value array or hash
look-ups.
But does not allow spaces or arrows between the components of the
variable access (i.e. imposes the same constraint as within a
C<< <...> >>-delimited interpolating quotelike).


=head3 C<< (?&PerlArrayAccess) >>

Matches any kind of variable access
beginning with a C<@>,
including arrays, array dereferences,
and list slices of arrays or hashes.


=head3 C<< (?&PerlArrayAccessNoSpace) >>

Matches any kind of variable access
beginning with a C<@>,
including arrays, array dereferences,
and list slices of arrays or hashes.
But does not allow spaces between the components of the
variable access (i.e. imposes the same constraint as within an
interpolating quotelike).


=head3 C<< (?&PerlArrayAccessNoSpaceNoArrow) >>

Matches any kind of variable access
beginning with a C<@>,
including arrays, array dereferences,
and list slices of arrays or hashes.
But does not allow spaces or arrows between the components of the
variable access (i.e. imposes the same constraint as within a
C<< <...> >>-delimited interpolating quotelike).


=head3 C<< (?&PerlHashAccess) >>

Matches any kind of variable access
beginning with a C<%>,
including hashes, hash dereferences,
and kv-slices of hashes or arrays.


=head3 C<< (?&PerlLabel) >>

Matches a colon-terminated label.


=head3 C<< (?&PerlLiteral) >>

Matches a literal value.
That is: a number, a C<qr> or C<qw>
quotelike, a string, or a bareword.


=head3 C<< (?&PerlString) >>

Matches a string literal.
That is: a single- or double-quoted string,
a C<q> or C<qq> string, a heredoc, or a
version string.


=head3 C<< (?&PerlQuotelike) >>

Matches any form of quotelike operator.
That is: a single- or double-quoted string,
a C<q> or C<qq> string, a heredoc, a
version string, a C<qr>, a C<qw>, a C<qx>,
a C</.../> or C<m/.../> regex,
a substitution, or a transliteration.


=head3 C<< (?&PerlHeredoc) >>

Matches a heredoc specifier.
That is: just the initial C<< <<TERMINATOR> >> component,
I<not> the actual contents of the heredoc on the
subsequent lines.

This rule only matches a heredoc specifier if that specifier
is correctly followed on the next line by any heredoc contents
and then the correct terminator.

However, if the heredoc specifier I<is> correctly matched, subsequent
calls to either of the whitespace-matching rules (C<(?&PerlOWS)> or
C<(?&PerlNWS)>) will also consume the trailing heredoc contents and
the terminator.

So, for example, to correctly match a heredoc plus its contents
you could use something like:

    m/ (?&PerlHeredoc) (?&PerlOWS)  $PPR::X::GRAMMAR /x

or, if there may be trailing items on the same line as the heredoc
specifier:

    m/ (?&PerlHeredoc)
       (?<trailing_items> [^\n]* )
       (?&PerlOWS)

       $PPR::X::GRAMMAR
    /x

Note that the saeme limitations apply to other constructs that
match heredocs, such a C<< (?&PerlQuotelike) >> or C<< (?&PerlString) >>.


=head3 C<< (?&PerlQuotelikeQ) >>

Matches a single-quoted string,
either a C<'...'>
or a C<q/.../> (with any valid delimiters).


=head3 C<< (?&PerlQuotelikeQQ) >>

Matches a double-quoted string,
either a C<"...">
or a C<qq/.../> (with any valid delimiters).


=head3 C<< (?&PerlQuotelikeQW) >>

Matches a "quotewords" list.
That is a C<qw/ list of words />
(with any valid delimiters).


=head3 C<< (?&PerlQuotelikeQX) >>

Matches a C<qx> system call,
either a C<`...`>
or a C<qx/.../> (with any valid delimiters)


=head3 C<< (?&PerlQuotelikeS) >> or C<< (?&PerlSubstitution) >>

Matches a substitution operation.
That is: C<s/.../.../>
(with any valid delimiters and any valid trailing modifiers).


=head3 C<< (?&PerlQuotelikeTR) >> or C<< (?&PerlTransliteration) >>

Matches a transliteration operation.
That is: C<tr/.../.../> or C<y/.../.../>
(with any valid delimiters and any valid trailing modifiers).


=head3 C<< (?&PerlContextualQuotelikeM) >> or C<< (?&PerContextuallMatch) >>

Matches a regex-match operation in any context where it would
be allowed in valid Perl.
That is: C</.../> or C<m/.../>
(with any valid delimiters and any valid trailing modifiers).


=head3 C<< (?&PerlQuotelikeM) >> or C<< (?&PerlMatch) >>

Matches a regex-match operation.
That is: C</.../> or C<m/.../>
(with any valid delimiters and any valid trailing modifiers)
in any context (i.e. even in places where it would not normally
be allowed within a valid piece of Perl code).


=head3 C<< (?&PerlQuotelikeQR) >>

Matches a C<qr> regex constructor
(with any valid delimiters and any valid trailing modifiers).


=head3 C<< (?&PerlContextualRegex) >>

Matches a C<qr> regex constructor or a C</.../> or C<m/.../> regex-match
operation (with any valid delimiters and any valid trailing modifiers)
anywhere where either would be allowed in valid Perl.

In other words: anything capable of matching within valid Perl code.


=head3 C<< (?&PerlRegex) >>

Matches a C<qr> regex constructor or a C</.../> or C<m/.../> regex-match
operation in any context (i.e. even in places where it would not normally
be allowed within a valid piece of Perl code).

In other words: anything capable of matching.


=head3 C<< (?&PerlBuiltinFunction) >>

Matches the I<name> of any builtin function.

To match an actual call to a built-in function, use:

    m/
        (?= (?&PerlBuiltinFunction) )
        (?&PerlCall)
    /x


=head3 C<< (?&PerlNullaryBuiltinFunction) >>

Matches the name of any builtin function that never
takes arguments.

To match an actual call to a built-in function that
never takes arguments, use:

    m/
        (?= (?&PerlNullaryBuiltinFunction) )
        (?&PerlCall)
    /x


=head3 C<< (?&PerlVersionNumber) >>

Matches any number or version-string that can be
used as a version number within a C<use>, C<no>,
or C<package> statement.


=head3 C<< (?&PerlVString) >>

Matches a version-string (a.k.a v-string).


=head3 C<< (?&PerlNumber) >>

Matches a valid number,
including binary, octal, decimal and hexadecimal integers,
and floating-point numbers with or without an exponent.


=head3 C<< (?&PerlIdentifier) >>

Matches a simple, unqualified identifier.


=head3 C<< (?&PerlQualifiedIdentifier) >>

Matches a qualified or unqualified identifier,
which may use either C<::> or C<'> as internal
separators, but only C<::> as initial or terminal
separators.


=head3 C<< (?&PerlOldQualifiedIdentifier) >>

Matches a qualified or unqualified identifier,
which may use either C<::> or C<'> as both
internal and external separators.


=head3 C<< (?&PerlBareword) >>

Matches a valid bareword.

Note that this is not the same as an simple identifier,
nor the same as a qualified identifier.

=head3 C<< (?&PerlPod) >>

Matches a single POD section containing any contiguous set of POD
directives, up to the first C<=cut> or end-of-file.


=head3 C<< (?&PerlPodSequence) >>

Matches any sequence of POD sections,
separated and /or surrounded by optional whitespace.


=head3 C<< (?&PerlNWS) >>

Match one-or-more characters of necessary whitespace,
including spaces, tabs, newlines, comments, and POD.


=head3 C<< (?&PerlOWS) >>

Match zero-or-more characters of optional whitespace,
including spaces, tabs, newlines, comments, and POD.


=head3 C<< (?&PerlOWSOrEND) >>

Match zero-or-more characters of optional whitespace,
including spaces, tabs, newlines, comments, POD,
and any trailing C<__END__> or C<__DATA__> section.


=head3 C<< (?&PerlEndOfLine) >>

Matches a single newline (C<\n>) character.

This is provided mainly to allow newlines to
be "hooked" by redefining C<< (?<PerlEndOfLine>) >>
(for example, to count lines during a parse).


=head3 C<< (?&PerlKeyword) >>

Match a pluggable keyword.

Note that there are no pluggable keywords
in the default PPR::X regex;
they must be added by the end-user.
See the following section for details.


=head2 Extending the Perl syntax with keywords

In Perl 5.12 and later, it's possible to add new types
of statements to the language using a mechanism called
"pluggable keywords".

This mechanism (best accessed via CPAN modules such as
C<Keyword::Simple> or C<Keyword::Declare>) acts like a limited macro
facility. It detects when a statement begins with a particular,
pre-specified keyword, passes the trailing text to an associated keyword
handler, and replaces the trailing source code with whatever the keyword
handler produces.

For example, the L<Dios> module uses this mechanism to add keywords such
as C<class>, C<method>, and C<has> to Perl 5, providing a declarative
OO syntax. And the L<Object::Result> module uses pluggable keywords to
add a C<result> statement that simplifies returning an ad hoc object from a
subroutine.

Unfortunately, because such modules effectively extend the standard Perl
syntax, by default PPR::X has no way of successfully parsing them.

However, when setting up a regex using C<$PPR::X::GRAMMAR> it is possible to
extend that grammar to deal with new keywords...by defining a rule named
C<< (?<PerlKeyword>...) >>.

This rule is always tested as the first option within the standard
C<(?&PerlStatement)> rule, so any syntax declared within effectively
becomes a new kind of statement. Note that each alternative within
the rule must begin with a valid "keyword" (that is: a simple
identifier of some kind).

For example, to support the three keywords from L<Dios>:

    $Dios::GRAMMAR = qr{

        # Add a keyword rule to support Dios...
        (?(DEFINE)
            (?<PerlKeyword>

                    class                              (?&PerlOWS)
                    (?&PerlQualifiedIdentifier)        (?&PerlOWS)
                (?: is (?&PerlNWS) (?&PerlIdentifier)  (?&PerlOWS) )*+
                    (?&PerlBlock)
            |
                    method                             (?&PerlOWS)
                    (?&PerlIdentifier)                 (?&PerlOWS)
                (?: (?&kw_balanced_parens)             (?&PerlOWS) )?+
                (?: (?&PerlAttributes)                 (?&PerlOWS) )?+
                    (?&PerlBlock)
            |
                    has                                (?&PerlOWS)
                (?: (?&PerlQualifiedIdentifier)        (?&PerlOWS) )?+
                    [\@\$%][.!]?(?&PerlIdentifier)     (?&PerlOWS)
                (?: (?&PerlAttributes)                 (?&PerlOWS) )?+
                (?: (?: // )?+ =                       (?&PerlOWS)
                    (?&PerlExpression)                 (?&PerlOWS) )?+
                (?> ; | (?= \} ) | \z )
            )

            (?<kw_balanced_parens>
                \( (?: [^()]++ | (?&kw_balanced_parens) )*+ \)
            )
        )

        # Add all the standard PPR::X rules...
        $PPR::X::GRAMMAR
    }x;

    # Then parse with it...

    $source_code =~ m{ \A (?&PerlDocument) \Z  $Dios::GRAMMAR }x;


Or, to support the C<result> statement from C<Object::Result>:

    my $ORK_GRAMMAR = qr{

        # Add a keyword rule to support Object::Result...
        (?(DEFINE)
            (?<PerlKeyword>
                result                        (?&PerlOWS)
                \{                            (?&PerlOWS)
                (?: (?> (?&PerlIdentifier)
                    |   < [[:upper:]]++ >
                    )                         (?&PerlOWS)
                    (?&PerlParenthesesList)?+      (?&PerlOWS)
                    (?&PerlBlock)             (?&PerlOWS)
                )*+
                \}
            )
        )

        # Add all the standard PPR::X rules...
        $PPR::X::GRAMMAR
    }x;

    # Then parse with it...

    $source_code =~ m{ \A (?&PerlDocument) \Z  $ORK_GRAMMAR }x;

Note that, although pluggable keywords are only available from Perl
5.12 onwards, PPR::X will still accept C<(&?PerlKeyword)> extensions under
Perl 5.10.


=head2 Extending the Perl syntax in other ways

Other modules (such as C<Devel::Declare> and C<Filter::Simple>)
make it possible to extend Perl syntax in even more flexible ways.
The L<< PPR::X >> module provides support for syntactic extensions more
general than pluggable keywords.


PPR::X allows I<any> of its public rules to be redefined in a
particular regex. For example, to create a regex that matches
standard Perl syntax, but which allows the keyword C<fun> as
a synonym for C<sub>:

    my $FUN_GRAMMAR = qr{

        # Extend the subroutine-matching rules...
        (?(DEFINE)
            (?<PerlStatement>
                # Try the standard syntax...
                (?&PerlStdStatement)
            |
                # Try the new syntax...
                fun                               (?&PerlOWS)
                (?&PerlOldQualifiedIdentifier)    (?&PerlOWS)
                (?: \( [^)]*+ \) )?+              (?&PerlOWS)
                (?: (?&PerlAttributes)            (?&PerlOWS) )?+
                (?> ; | (?&PerlBlock) )
            )

            (?<PerlAnonymousSubroutine>
                # Try the standard syntax
                (?&PerlStdAnonymousSubroutine)
            |
                # Try the new syntax
                fun                               (?&PerlOWS)
                (?: \( [^)]*+ \) )?+              (?&PerlOWS)
                (?: (?&PerlAttributes)            (?&PerlOWS) )?+
                (?> ; | (?&PerlBlock) )
            )
        )

        $PPR::X::GRAMMAR
    }x;

Note first that any redefinitions of the various rules have to be
specified before the interpolation of the standard rules (so that the
new rules take syntactic precedence over the originals).

The structure of each redefinition is essentially identical.
First try the original rule, which is still accessible as C<(?&PerlStd...)>
(instead of C<(?&Perl...)>). Otherwise, try the new alternative, which
may be constructed out of other rules.
    original rule.

There is no absolute requirement to try the original rule as part of the
new rule, but if you don't then you are I<replacing> the rule, rather
than extending it. For example, to replace the low-precedence boolean
operators (C<and>, C<or>, C<xor>, and C<not>) with their Latin equivalents:

    my $GRAMMATICA = qr{

        # Verbum sapienti satis est...
        (?(DEFINE)

            # Iunctiones...
            (?<PerlLowPrecedenceInfixOperator>
                atque | vel | aut
            )

            # Contradicetur...
            (?<PerlLowPrecedenceNotExpression>
                (?: non  (?&PerlOWS) )*+  (?&PerlCommaList)
            )
        )

        $PPR::X::GRAMMAR
    }x;

Or to maintain a line count within the parse:

    my $COUNTED_GRAMMAR = qr{

        (?(DEFINE)

            (?<PerlEndOfLine>
                # Try the standard syntax
                (?&PerlStdEndOfLine)

                # Then count the line (must localize, to handle backtracking)...
                (?{ local $linenum = $linenum + 1; })
            )
        )

        $PPR::X::GRAMMAR
    }x;



=head2 Comparison with PPI

The PPI and PPR::X modules can both identify valid Perl code,
but they do so in very different ways, and are optimal for
different purposes.

PPI scans an entire Perl document and builds a hierarchical
representation of the various components. It is therefore suitable for
recognition, validation, partial extraction, and in-place transformation
of Perl code.

PPR::X matches only as much of a Perl document as specified by the regex
you create, and does not build any hierarchical representation of the
various components it matches. It is therefore suitable for recognition
and validation of Perl code. However, unless great care is taken, PPR::X is
not as reliable as PPI for extractions or transformations of components
smaller than a single statement.

On the other hand, PPI always has to parse its entire input, and
build a complete non-trivial nested data structure for it, before it
can be used to recognize or validate any component. So it is almost
always significantly slower and more complicated than PPR::X for those
kinds of tasks.

For example, to determine whether an input string begins with a valid
Perl block, PPI requires something like:

    if (my $document = PPI::Document->new(\$input_string) ) {
        my $block = $document->schild(0)->schild(0);
        if ($block->isa('PPI::Structure::Block')) {
            $block->remove;
            process_block($block);
            process_extra($document);
        }
    }

whereas PPR::X needs just:

    if ($input_string =~ m{ \A (?&PerlOWS) ((?&PerlBlock)) (.*) }xs) {
        process_block($1);
        process_extra($2);
    }

Moreover, the PPR::X version will be at least twice as fast at recognizing that
leading block (and usually four to seven times faster)...mainly because it
doesn't have to parse the trailing code at all, nor build any representation
of its hierarchical structure.

As a simple rule of thumb, when you only need to quickly detect, identify,
or confirm valid Perl (or just a single valid Perl component), use PPR::X.
When you need to examine, traverse, or manipulate the internal structure
or component relationships within an entire Perl document, use PPI.


=head1 DIAGNOSTICS

=over

=item C<Warning: This program is running under Perl 5.20...>

Due to an unsolved issue with that particular release of Perl, the
single regex in the PPR::X module takes a ridiculously long time
to compile under Perl 5.20 (i.e. minutes, not milliseconds).

The code will work correctly when it eventually does compile,
but the start-up delay is so extreme that the module issues
this warning, to reassure users the something is actually
happening, and explain why it's happening so slowly.

The only remedy at present is to use an older or newer version
of Perl.

For all the gory details, see:
L<https://rt.perl.org/Public/Bug/Display.html?id=122283>
L<https://rt.perl.org/Public/Bug/Display.html?id=122890>


=item C<< PPR::X::decomment() does not work under Perl 5.14 >>

There is a separate bug in the Perl 5.14 regex engine that prevents
the C<decomment()> subroutine from correctly detecting the location
of comments.

The subroutine throws an exception if you attempt to call it
when running under Perl 5.14 specifically.

=back

The module has no other diagnostics, apart from those Perl
provides for all regular expressions.

The commonest error is to forget to add C<$PPR::X::GRAMMAR>
to a regex, in which case you will get a standard Perl
error message such as:

    Reference to nonexistent named group in regex;
    marked by <-- HERE in m/

        (?&PerlDocument <-- HERE )

    / at example.pl line 42.

Adding C<$PPR::X::GRAMMAR> at the end of the regex solves the problem.



=head1 CONFIGURATION AND ENVIRONMENT

PPR::X requires no configuration files or environment variables.


=head1 DEPENDENCIES

Requires Perl 5.10 or later.


=head1 INCOMPATIBILITIES

None reported.


=head1 LIMITATIONS

This module works under all versions of Perl from 5.10 onwards.

However, the lastest release of Perl 5.20 seems to have significant
difficulties compiling large regular expressions, and typically requires
over a minute to build any regex that incorporates the C<$PPR::X::GRAMMAR> rule
definitions.

The problem does not occur in Perl 5.10 to 5.18, nor in Perl 5.22 or later,
though the parser is still measurably slower in all Perl versions
greater than 5.20 (presumably because I<most> regexes are measurably
slower in more modern versions of Perl; such is the price of full
re-entrancy and safe lexical scoping).

The C<decomment()> subroutine trips a separate regex engine bug in Perl
5.14 only and will not run under that version.

There are also constructs in Perl 5 which cannot be parsed without
actually executing some code...which the regex does not attempt to
do, for obvious reasons.


=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-ppr@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Damian Conway  C<< <DCONWAY@CPAN.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2017, Damian Conway C<< <DCONWAY@CPAN.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
