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

# Grammar: Statement =>    FuncDef
#                        | Conditional
#                        | Loop
#                        | StatementBlock
#                        | Expression TERM
#                        | TERM
sub Statement {
    my ($parser) = @_;

    $parser->try;

    my $funcdef = FuncDef($parser);
    return if $parser->errored;

    if ($funcdef) {
        $parser->advance;
        return ['STMT', $funcdef];
    }

    $parser->alternate;

    my $expression = Expression($parser);
    return if $parser->errored;

    if ($expression) {
        $parser->consume('TERM');
        $parser->advance;
        return ['STMT', $expression];
    }

    $parser->alternate;

    if ($parser->consume('TERM')) {
        $parser->advance;
        return ['STMT', ''];
    } else {
        return expected($parser, 'statement');
    }

    $parser->backtrack;
    return;
}

my %keywords = (
    'fn'     => 1,
    'return' => 1,
    'if'     => 1,
    'else'   => 1,
);

# Grammar: FuncDef   =>    fn IDENT L_PAREN IdentList R_PAREN L_BRACE Statement(s) R_BRACE
#          IdentList =>    IDENT COMMA(?)
sub FuncDef {
    my ($parser) = @_;
    my $token;

    $parser->try;

    if ($token = $parser->consume('IDENT')) {
        return if $token->[1] ne 'fn';

        $token = $parser->consume('IDENT');
        return expected($parser, 'IDENT for function name') if not $token;

        my $name = $token->[1];

        return expected($parser, 'L_PAREN after function IDENT') if not $parser->consume('L_PAREN');

        my $parameters = [];
        while (1) {
            if ($token = $parser->consume('IDENT')) {
                push @{$parameters}, $token->[1];
                next if $parser->consume('COMMA');
            }
            last if $parser->consume('R_PAREN');
            return expected($parser, 'COMMA or R_PAREN after function parameter IDENT');
        }

        return expected($parser, 'Opening L_BRACE for function body') if not $parser->consume('L_BRACE');

        my $statements = [];
        while (1) {
            my $statement = Statement($parser);
            return if $parser->errored;

            if ($statement) {
                push @{$statements}, $statement;
            }

            last if $parser->consume('R_BRACE');
            return expected($parser, 'STATEMENT or R_BRACE in function body');
        }

        return ['FUNCDEF', $name, $parameters, $statements];
    }

    $parser->{dprint}->(1, "<- FuncDef fail\n");
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
    EQ           => $precedence_table{'ASSIGNMENT'},
    EQ_EQ        => $precedence_table{'CONDITIONAL'},
    GREATER_EQ   => $precedence_table{'CONDITIONAL'},
    LESS_EQ      => $precedence_table{'CONDITIONAL'},
    LESS         => $precedence_table{'CONDITIONAL'},
    GREATER      => $precedence_table{'CONDITIONAL'},
    PLUS         => $precedence_table{'SUM'},
    MINUS        => $precedence_table{'SUM'},
    STAR         => $precedence_table{'PRODUCT'},
    SLASH        => $precedence_table{'PRODUCT'},
    STAR_STAR    => $precedence_table{'EXPONENT'},
    PERCENT      => $precedence_table{'EXPONENT'},
    BANG         => $precedence_table{'PREFIX'},
    # PLUS_PLUS0   => $precedence_table{'PREFIX'}, # documentation
    # MINUS_MINUS0 => $precedence_table{'PREFIX'}, # documentation
    PLUS_PLUS    => $precedence_table{'POSTFIX'},
    MINUS_MINUS  => $precedence_table{'POSTFIX'},
    L_PAREN      => $precedence_table{'CALL'},
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

sub BinaryOp {
    my ($parser, $left, $op, $ins, $precedence, $right_associative) = @_;
    $right_associative ||= 0;

    if ($parser->consume($op)) {
        my $right = Expression($parser, $precedence_table{$precedence} - $right_associative);
        return $right ? [$ins, $left, $right] : expected($parser, 'Expression');
    }
}

sub Prefix {
    my ($parser, $precedence) = @_;
    my ($token, $expr);

    if ($token = $parser->consume('NUM')) {
        return ['NUM', $token->[1]];
    }

    if ($token = $parser->consume('IDENT')) {
        return ['IDENT', $token->[1]];
    }

    if ($token = $parser->consume('SQUOTE_STRING')) {
        return ['STRING', $token->[1]];
    }

    if ($token = $parser->consume('DQUOTE_STRING')) {
        return ['STRING', $token->[1]];
    }

    return $expr if $expr = UnaryOp($parser, 'BANG',        'NOT');
    return $expr if $expr = UnaryOp($parser, 'PLUS_PLUS',   'PREFIX_ADD');
    return $expr if $expr = UnaryOp($parser, 'MINUS_MINUS', 'PREFIX_SUB');

    if ($token = $parser->consume('L_PAREN')) {
        my $expr = Expression($parser, $precedence);
        return expected($parser, 'R_PAREN') if not $parser->consume('R_PAREN');
        return $expr;
    }

    return;
}

sub Infix {
    my ($parser, $left, $precedence) = @_;
    my $expr;

    if ($parser->consume('L_PAREN')) {
        my $arguments = [];
        while (1) {
            my $expr = Expression($parser);
            return if $parser->errored;

            if ($expr) {
                push @{$arguments}, $expr;
                next if $parser->consume('COMMA');
            }

            last if $parser->consume('R_PAREN');
            return expected($parser, 'Expression or closing R_PAREN for function call argument list');
        }

        return ['CALL', $left->[1], $arguments];
    }

    return $expr if $expr = BinaryOp($parser, $left, 'PLUS',        'ADD',    'SUM');
    return $expr if $expr = BinaryOp($parser, $left, 'MINUS',       'SUB',    'SUM');
    return $expr if $expr = BinaryOp($parser, $left, 'STAR',        'MUL',    'PRODUCT');
    return $expr if $expr = BinaryOp($parser, $left, 'SLASH',       'DIV',    'PRODUCT');
    return $expr if $expr = BinaryOp($parser, $left, 'EQ',          'ASSIGN', 'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'EQ_EQ',       'EQ',     'CONDITIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'GREATER',     'GT',     'CONDITIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'LESS',        'LT',     'CONDITIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'GREATER_EQ',  'GTE',    'CONDITIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'LESS_EQ',     'LTE',    'CONDITIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'STAR_STAR',   'POW',    'EXPONENT',     1);
    return $expr if $expr = BinaryOp($parser, $left, 'PERCENT',     'REM',    'EXPONENT');

    return Postfix($parser, $left, $precedence);
}

sub Postfix {
    my ($parser, $left, $precedence) = @_;

    if ($parser->consume('PLUS_PLUS')) {
        return ['POSTFIX_ADD', $left];
    }

    if ($parser->consume('MINUS_MINUS')) {
        return ['POSTFIX_SUB', $left];
    }

    return $left;
}

1;
