#!/usr/bin/env perl

package Grammar;

use warnings;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw/Program/;
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

# Grammar: Program --> Statement(s)
sub Program {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Program");
    $parser->{indent}++;

    my @statements;

    while (1) {
        $parser->{dprint}->(1, "Program: Statement \n");
        $parser->try;

        my $statement = Statement($parser);

        if ($statement) {
            $parser->advance;
            push @statements, $statement;
        } else {
            $parser->backtrack;
            last;
        }
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Program (Statement)\n");

    return @statements ? ['PRGM', \@statements] : undef;
}

# Grammar: Statement --> Expression TERM | TERM
sub Statement {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Statement");
    $parser->{indent}++;

    $parser->{dprint}->(1, "Statement: Expression TERM\n");
    $parser->try;

    my $expression = Expression($parser);

    if ($expression and $parser->upcoming('TERM')) {
        $parser->{indent}--;
        $parser->{dprint}->(1, "<- Statement (Expression TERM)\n");
        $parser->advance;
        return ['STMT', $expression];
    }

    $parser->{dprint}->(1, "Statement alternate: TERM\n");
    $parser->alternate;

    if ($parser->upcoming('TERM')) {
        $parser->{indent}--;
        $parser->{dprint}->(1, "<- Statement (TERM)\n");
        $parser->advance;
        return ['STMT', ''];
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Statement fail\n");

    $parser->backtrack;
    return undef;
}

# Grammar: Expression --> Term PLUS Expression | Term
sub Expression {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Expression\n");
    $parser->{indent}++;

    $parser->{dprint}->(1, "Expression: Term PLUS Expression\n");
    $parser->try;

    my $term = Term($parser);

    if ($term and $parser->upcoming('PLUS')) {
        my $expression = Expression($parser);

        if (defined $expression) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Expression (Term PLUS Expression)\n");
            $parser->advance;
            return ['ADD', $term, $expression];
        } else {
            my $token = $parser->current_token;
            if (defined $token) {
                my $name = $token->[0];
                my $line = $token->[2]->{line};
                my $col  = $token->[2]->{col};
                $parser->add_diagnostic("Expected Expression but got $name on line $line, col $col");
            } else {
                $parser->add_diagnostic("Expected Expression but got EOF");
            }
        }
    }

    $parser->{dprint}->(1, "Expression alternate Term\n");
    $parser->alternate;

    $term = Term($parser);

    if (defined $term) {
        $parser->{indent}--;
        $parser->{dprint}->(1, "<- Expression (Term)\n");
        $parser->advance;
        return $term;
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Expression fail\n");

    $parser->backtrack;
    return undef;
}

# Grammar: Term --> Factor STAR Term | Factor
sub Term {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Term\n");
    $parser->{indent}++;

    $parser->{dprint}->(1, "Term: Factor STAR Term\n");
    $parser->try;

    my $factor = Factor($parser);

    if ($factor and $parser->upcoming('STAR')) {
        my $term = Term($parser);

        if (defined $term) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Term (Factor STAR Term)\n");
            $parser->advance;
            return ['MUL', $factor, $term];
        }
    }

    $parser->{dprint}->(1, "Term alternate: Factor\n");
    $parser->alternate;

    $factor = Factor($parser);

    if (defined $factor) {
        $parser->{indent}--;
        $parser->{dprint}->(1, "<- Term (Factor)\n");
        $parser->advance;
        return $factor;
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Term fail\n");

    $parser->backtrack;
    return undef;
}

# Grammar: Factor --> L_PAREN Expression R_PAREN | NUM
sub Factor {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Factor\n");
    $parser->{indent}++;

    $parser->{dprint}->(1,"Factor: L_PAREN Expression R_PAREN\n");
    $parser->try;

    if ($parser->upcoming('L_PAREN')) {
        my $expression = Expression($parser);

        if ($expression and $parser->upcoming('R_PAREN')) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Factor (L_PAREN Expression R_PAREN)\n");
            $parser->advance;
            return $expression;
        }
    }

    $parser->{dprint}->(1, "Factor alternate: NUM\n");
    $parser->alternate;

    if (my $token = $parser->upcoming('NUM')) {
        $parser->{indent}--;
        $parser->{dprint}->(1, "<- Factor (NUM)\n");
        $parser->advance;
        return [ $token->[0], $token->[1] ];
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Factor fail\n");

    $parser->backtrack;
    return undef;
}

1;
