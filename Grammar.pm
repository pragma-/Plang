#!/usr/bin/env perl

package Grammar;

use warnings;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw/Program/;
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

sub expected {
    my ($parser, $expected, $consume_to) = @_;

    $consume_to ||= 'TERM';

    my $token = $parser->current_token;

    if (defined $token) {
        my $name = "$token->[0] ($token->[1])";
        my $line = $token->[2]->{line};
        my $col  = $token->[2]->{col};
        $parser->add_error("Expected $expected but got $name at line $line, col $col");
    } else {
        $parser->add_error("Expected $expected but got EOF");
    }

    $parser->consume_to($consume_to);
    $parser->rewrite_backtrack;
    $parser->{got_error} = 1;
}

# Grammar: Program --> Statement(s)
sub Program {
    my ($parser) = @_;

    my @statements;

    while (defined $parser->next_token('peek')) {
        $parser->clear_error;

        my $statement = Statement($parser);
        next if $parser->errored;

        if ($statement) {
            push @statements, $statement;
        }
    }

    return @statements ? ['PRGM', \@statements] : undef;
}

# Grammar: Statement --> Expression | TERM
sub Statement {
    my ($parser) = @_;

    $parser->try;

    my $expression = Expression($parser);
    return if $parser->errored;

    if ($expression) {
        $parser->advance;
        return ['STMT', $expression];
    }

    $parser->alternate;

    if ($parser->consume('TERM')) {
        $parser->advance;
        return ['STMT', ''];
    } else {
        return expected($parser, 'TERM');
    }

    $parser->backtrack;
    return;
}

my %precedence_table = (
    ASSIGNMENT  => 1,
    CONDITIONAL => 2,
    SUM         => 3,
    PRODUCT     => 4,
    EXPONENT    => 5,
    PREFIX      => 6,
    POSTFIX     => 7,
    CALL        => 8,
);

my %token_precedence = (
    EQ          => $precedence_table{'ASSIGNMENT'},
    EQ_EQ       => $precedence_table{'CONDITIONAL'},
    GREATER_EQ  => $precedence_table{'CONDITIONAL'},
    LESS_EQ     => $precedence_table{'CONDITIONAL'},
    LESS        => $precedence_table{'CONDITIONAL'},
    GREATER     => $precedence_table{'CONDITIONAL'},
    PLUS        => $precedence_table{'SUM'},
    MINUS       => $precedence_table{'SUM'},
    STAR        => $precedence_table{'PRODUCT'},
    SLASH       => $precedence_table{'PRODUCT'},
    STAR_STAR   => $precedence_table{'EXPONENT'},
    PERCENT     => $precedence_table{'EXPONENT'},
    BANG        => $precedence_table{'PREFIX'},
    TILDE       => $precedence_table{'PREFIX'},
    PLUS_PLUS   => $precedence_table{'POSTFIX'},
    MINUS_MINUS => $precedence_table{'POSTFIX'},
    L_PAREN     => $precedence_table{'CALL'},
);

sub get_precedence {
    my ($tokentype) = @_;
    return $token_precedence{$tokentype} // 0;
}

sub Expression {
    my ($parser, $precedence) = @_;

    $precedence ||= 0;

    my $left = Prefix($parser, $precedence);
    return if $parser->errored;

    return if not $left;

    while (1) {
        my $token = $parser->next_token('peek');
        last if not defined $token;
        last if $precedence >= get_precedence $token->[0];

        $left = Infix($parser, $left, $precedence);
        return if $parser->errored;
    }

    return $left;
}

sub Prefix {
    my ($parser, $precedence) = @_;
    my $token;

    if ($token = $parser->consume('NUM')) {
        return ['NUM', $token->[1], Expression($parser, get_precedence 'NUM')];
    }

    if ($token = $parser->consume('TERM')) {
        return;
    }

    if ($token = $parser->consume('BANG')) {
        return ['NOT', Expression($parser, get_precedence 'BANG')];
    }

    if ($token = $parser->consume('L_PAREN')) {
        my $expr = Expression($parser);
        $parser->consume('R_PAREN');
        return $expr;
    }

    if ($token = $parser->consume('IDENT')) {
        return ['IDENT', $token->[1], Expression($parser, get_precedence 'IDENT')];
    }

    return;
}

sub Infix {
    my ($parser, $left, $precedence) = @_;
    my $token;

    if ($token = $parser->consume('PLUS')) {
        return ['ADD', $left, Expression($parser, get_precedence 'PLUS')];
    }

    if ($token = $parser->consume('MINUS')) {
        return ['SUB', $left, Expression($parser, get_precedence 'MINUS')];
    }

    if ($token = $parser->consume('STAR')) {
        return ['MUL', $left, Expression($parser, get_precedence 'STAR')];
    }

    if ($token = $parser->consume('SLASH')) {
        return ['DIV', $left, Expression($parser, get_precedence 'SLASH')];
    }

    if ($token = $parser->consume('EQ')) {
        # right-associative
        return ['ASSIGN', $left, Expression($parser, $precedence_table{'ASSIGNMENT'} - 1)];
    }

    if ($token = $parser->consume('STAR_STAR')) {
        # right-associative
        return ['EXP', $left, Expression($parser, get_precedence('STAR_STAR') - 1)];
    }

    $left = Postfix($parser, $left, $precedence);
    return $left;
}

sub Postfix {
    my ($parser, $left, $precedence) = @_;
    my $token;

    if ($token = $parser->consume('PLUS_PLUS')) {
        return ['POSTFIX_ADD', $token->[1], $left];
    }

    if ($token = $parser->consume('MINUS_MINUS')) {
        return ['POSTFIX_SUB', $token->[1], $left];
    }

    return $left;
}

1;
