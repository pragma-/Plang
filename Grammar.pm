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

sub UnaryOp {
    my ($parser, $op, $ins) = @_;

    if ($parser->consume($op)) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return $expr ? [$ins, $expr] : expected($parser, 'Expression');
    }
}

sub Prefix {
    my ($parser, $precedence) = @_;
    my ($token, $expr);

    if ($token = $parser->consume('NUM')) {
        return ['NUM', $token->[1], Expression($parser)];
    }

    if ($token = $parser->consume('IDENT')) {
        return ['IDENT', $token->[1], Expression($parser)];
    }

    if ($token = $parser->consume('TERM')) {
        return;
    }

    return $expr if $expr = UnaryOp($parser, 'BANG',     'NOT');

    if ($token = $parser->consume('L_PAREN')) {
        my $expr = Expression($parser);
        return expected($parser, 'R_PAREN') if not $parser->consume('R_PAREN');
        return $expr;
    }

    return;
}

sub BinaryOp {
    my ($parser, $left, $op, $ins, $precedence, $right_associative) = @_;
    $right_associative ||= 0;

    if ($parser->consume($op)) {
        my $right = Expression($parser, $precedence_table{$precedence} - $right_associative);
        return $right ? [$ins, $left, $right] : expected($parser, 'Expression');
    }
}

sub Infix {
    my ($parser, $left, $precedence) = @_;
    my $expr;

    return $expr if $expr = BinaryOp($parser, $left, 'PLUS',      'ADD',    'SUM');
    return $expr if $expr = BinaryOp($parser, $left, 'MINUS',     'SUB',    'SUM');
    return $expr if $expr = BinaryOp($parser, $left, 'STAR',      'MUL',    'PRODUCT');
    return $expr if $expr = BinaryOp($parser, $left, 'SLASH',     'DIV',    'PRODUCT');
    return $expr if $expr = BinaryOp($parser, $left, 'EQ',        'ASSIGN', 'ASSIGNMENT', 1);
    return $expr if $expr = BinaryOp($parser, $left, 'EQ_EQ',     'EQ',     'CONDITIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'STAR_STAR', 'POW',    'EXPONENT');

    return Postfix($parser, $left, $precedence);
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
