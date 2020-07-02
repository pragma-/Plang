#!/usr/bin/env perl

package Grammar;

use warnings;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw/Program/;
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

sub expected {
    my ($parser, $expected) = @_;

    my $token = $parser->current_token;

    if (defined $token) {
        my $name = "$token->[0] ($token->[1])";
        my $line = $token->[2]->{line};
        my $col  = $token->[2]->{col};
        $parser->add_error("Expected $expected but got $name at line $line, col $col");
    } else {
        $parser->add_error("Expected $expected but got EOF");
    }

    $parser->consume_to('TERM');
    $parser->rewrite_backtrack;
    $parser->{got_error} = 1;
}

# Grammar: Program --> Statement(s)
sub Program {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Program\n");
    $parser->{indent}++;

    my @statements;

    while (defined $parser->next_token('peek')) {
        $parser->{dprint}->(1, "Program: Statement\n");
        $parser->try;

        $parser->{dprint}->(3, "Error cleared\n");
        $parser->{got_error} = 0;

        my $statement = Statement($parser);
        next if $parser->errored;

        if ($statement) {
            $parser->advance;
            push @statements, $statement;
        } else {
            $parser->backtrack;
        }
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Program (Statement)\n");

    return @statements ? ['PRGM', \@statements] : undef;
}

# Grammar: Statement --> Expression TERM | TERM
sub Statement {
    my ($parser) = @_;

    $parser->{dprint}->(1, "+-> Statement\n");
    $parser->{indent}++;

    $parser->{dprint}->(1, "Statement: Expression TERM\n");
    $parser->try;

    my $expression = Expression($parser);
    return undef if $parser->errored;

    if ($expression) {
        if ($parser->consume('TERM')) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Statement (Expression TERM)\n");
            $parser->advance;
            return ['STMT', $expression];
        } else {
            expected($parser, 'TERM');
            return undef;
        }
    }

    $parser->{dprint}->(1, "Statement alternate: TERM\n");
    $parser->alternate;

    if ($parser->consume('TERM')) {
        $parser->{indent}--;
        $parser->{dprint}->(1, "<- Statement (TERM)\n");
        $parser->advance;
        return ['STMT', ''];
    } else {
        expected($parser, 'TERM');
        return undef;
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
    return undef if $parser->errored;

    if ($term and $parser->consume('PLUS')) {
        my $expression = Expression($parser);
        return undef if $parser->errored;

        if (defined $expression) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Expression (Term PLUS Expression)\n");
            $parser->advance;
            return ['ADD', $term, $expression];
        } else {
            expected($parser, 'Expression');
            return undef;
        }
    }

    $parser->{dprint}->(1, "Expression alternate Term\n");
    $parser->alternate;

    $term = Term($parser);
    return undef if $parser->errored;

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
    return undef if $parser->errored;

    if ($factor and $parser->consume('STAR')) {
        my $term = Term($parser);
        return undef if $parser->errored;

        if (defined $term) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Term (Factor STAR Term)\n");
            $parser->advance;
            return ['MUL', $factor, $term];
        } else {
            expected($parser, 'Term');
            return undef;
        }
    }

    $parser->{dprint}->(1, "Term alternate: Factor\n");
    $parser->alternate;

    $factor = Factor($parser);
    return undef if $parser->errored;

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

    if ($parser->consume('L_PAREN')) {
        my $expression = Expression($parser);
        return undef if $parser->errored;

        if ($expression and $parser->consume('R_PAREN')) {
            $parser->{indent}--;
            $parser->{dprint}->(1, "<- Factor (L_PAREN Expression R_PAREN)\n");
            $parser->advance;
            return $expression;
        }
    }

    $parser->{dprint}->(1, "Factor alternate: NUM\n");
    $parser->alternate;

    if (my $token = $parser->consume('NUM')) {
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
