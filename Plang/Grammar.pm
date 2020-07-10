#!/usr/bin/env perl

package Plang::Grammar;

use warnings;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw/Program/;
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

sub error {
    my ($parser, $err_msg, $consume_to) = @_;
    chomp $err_msg;

    $consume_to ||= 'TERM';

    if (defined (my $token = $parser->current_or_last_token)) {
        my $line = $token->[2]->{line};
        my $col  = $token->[2]->{col};
        $parser->add_error("Error: $err_msg at line $line, col $col.");
    } else {
        $parser->add_error("Error: $err_msg");
    }

    $parser->consume_to($consume_to);
    $parser->rewrite_backtrack;
    return;
}

my %pretty_tokens = (
    'TERM' => 'statement terminator',
);

sub pretty_token {
    $pretty_tokens{$_[0]} // $_[0];
}

sub pretty_value {
    my ($value) = @_;
    $value =~ s/\n/\\n/g;
    return $value;
}

sub expected {
    my ($parser, $expected, $consume_to) = @_;

    $parser->{indent}-- if $parser->{debug};

    if (defined (my $token = $parser->current_or_last_token)) {
        my $name = pretty_token($token->[0]) . ' (' . pretty_value($token->[1]) . ')';
        return error($parser, "Expected $expected but got $name");
    } else {
        return error($parser, "Expected $expected but got EOF");
    }
}

# Grammar: Program --> Statement(s)
sub Program {
    my ($parser) = @_;

    $parser->try('Program: Statement(s)');
    my @statements;

    while (defined $parser->next_token('peek')) {
        $parser->clear_error;

        my $statement = Statement($parser);
        next if $parser->errored;

        if ($statement and $statement->[0] ne 'NOP') {
            push @statements, $statement;
        }
    }

    $parser->advance;
    return @statements ? ['PRGM', \@statements] : undef;
}

# Grammar: Statement =>  | StatementGroup
#                        | FuncDef
#                        | Conditional
#                        | Loop
#                        | Expression TERM
#                        | TERM
sub Statement {
    my ($parser) = @_;

    $parser->try('Statement: StatementGroup');

    {
        my $statement_group = StatementGroup($parser);
        return if $parser->errored;

        if ($statement_group) {
            $parser->advance;
            return ['STMT', $statement_group];
        }
    }

    $parser->alternate('Statement: FuncDef');

    {
        my $funcdef = FuncDef($parser);
        return if $parser->errored;

        if ($funcdef) {
            $parser->advance;
            return ['STMT', $funcdef];
        }
    }

    $parser->alternate('Statement: Expression');

    {
        my $expression = Expression($parser);
        return if $parser->errored;

        if ($expression) {
            $parser->consume('TERM');
            $parser->advance;
            return ['STMT', $expression];
        }
    }

    $parser->alternate('Statement: TERM');

    {
        if ($parser->consume('TERM')) {
            $parser->advance;
            return ['NOP', 'null statement'];
        }
    }

    $parser->backtrack;
    return;
}

# Grammar: StatementGroup =>   L_BRACE Statement(s) R_BRACE
sub StatementGroup {
    my ($parser) = @_;

    $parser->try('StatementGroup: L_BRACE Statement R_BRACE');

    {
        goto STATEMENT_GROUP_FAIL if not $parser->consume('L_BRACE');

        my @statements;

        while (1) {
            my $statement = Statement($parser);
            return if $parser->errored;
            last if not $statement;
            push @statements, $statement unless $statement->[0] eq 'NOP';
        }

        goto STATEMENT_GROUP_FAIL if not $parser->consume('R_BRACE');

        $parser->advance;
        return ['STMT_GROUP', \@statements];
    }

  STATEMENT_GROUP_FAIL:
    $parser->backtrack;
    return;
}

# Grammar: FuncDef   =>    KEYWORD_fn IDENT L_PAREN IdentList(s) R_PAREN (StatementGroup | Statement)
#          IdentList =>    IDENT COMMA(?)
sub FuncDef {
    my ($parser) = @_;
    my $token;

    $parser->try('FuncDef');

    {
        if ($token = $parser->consume('KEYWORD_fn')) {
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

            $parser->try('FuncDef body: StatementGroup');

            {
                my $statement_group = StatementGroup($parser);
                return if $parser->errored;

                if ($statement_group) {
                    $parser->advance;
                    return ['FUNCDEF', $name, $parameters, $statement_group->[1]];
                }
            }

            $parser->alternate('FuncDef body: Statement');

            {
                my $statement = Statement($parser);
                return if $parser->errored;

                if ($statement) {
                    $parser->advance;
                    return ['FUNCDEF', $name, $parameters, [$statement]];
                }
            }

            $parser->backtrack;
        }
    }

  FUNCDEF_FAIL:
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

    $parser->try("Expression (prec $precedence)");

    {
        my $left = Prefix($parser, $precedence);
        return if $parser->errored;

        goto EXPRESSION_FAIL if not $left;

        while (1) {
            my $token = $parser->next_token('peek');
            last if not defined $token;
            last if $precedence >= get_precedence $token->[0];

            $left = Infix($parser, $left, $precedence);
            return if $parser->errored;
        }

        $parser->advance;
        return $left;
    }

  EXPRESSION_FAIL:
    $parser->backtrack;
    return;
}

sub UnaryOp {
    my ($parser, $op, $ins) = @_;

    if ($parser->consume($op)) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return $expr ? [$ins, $expr] : expected($parser, 'expression');
    }
}

sub BinaryOp {
    my ($parser, $left, $op, $ins, $precedence, $right_associative) = @_;
    $right_associative ||= 0;

    if ($parser->consume($op)) {
        my $right = Expression($parser, $precedence_table{$precedence} - $right_associative);
        return $right ? [$ins, $left, $right] : expected($parser, 'expression');
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

    if ($parser->consume('MINUS_MINUS')) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return expected($parser, 'expression') if not defined $expr;

        if ($expr->[0] eq 'IDENT') {
            return ['PREFIX_SUB', $expr];
        } else {
            return error($parser, "Prefix decrement must be used on objects (got " . pretty_token($expr->[0]) . ")");
        }
    }

    if ($parser->consume('PLUS_PLUS')) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return expected($parser, 'expression') if not defined $expr;

        if ($expr->[0] eq 'IDENT') {
            return ['PREFIX_ADD', $expr];
        } else {
            return error($parser, "Prefix increment must be used on objects (got " . pretty_token($expr->[0]) . ")");
        }
    }

    return $expr if $expr = UnaryOp($parser, 'BANG',        'NOT');

    if ($token = $parser->consume('L_PAREN')) {
        my $expr = Expression($parser, 0);
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
            return expected($parser, 'expression or closing R_PAREN for function call argument list');
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
        if ($left->[0] eq 'IDENT') {
            return ['POSTFIX_ADD', $left];
        } else {
            return error($parser, "Postfix increment must be used on objects (got " . pretty_token($left->[0]) . ")");
        }
    }

    if ($parser->consume('MINUS_MINUS')) {
        if ($left->[0] eq 'IDENT') {
            return ['POSTFIX_SUB', $left];
        } else {
            return error($parser, "Postfix decrement must be used on objects (got " . pretty_token($left->[0]) . ")");
        }
    }

    return $left;
}

1;
