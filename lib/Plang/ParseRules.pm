#!/usr/bin/env perl

# Recursive descent rules to parse a Plang program using
# the Plang::Parser class. Constructs a syntax tree annotated
# with token line/col positions.
#
# Program() is the start-rule.

package Plang::ParseRules;

use warnings;
use strict;

use parent 'Exporter';
our @EXPORT_OK = qw/Program/; # start-rule
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

use Plang::Constants::Tokens       ':all';
use Plang::Constants::Keywords     ':all';
use Plang::Constants::Instructions ':all';

sub error {
    my ($parser, $err_msg, $consume_to) = @_;

    chomp $err_msg;

    $consume_to ||= TOKEN_TERM;

    if (defined (my $token = $parser->current_token)) {
        my $line = $token->[2];
        my $col  = $token->[3];
        $err_msg = "Parse error: $err_msg at line $line, col $col.";
    } else {
        $err_msg = "Parse error: $err_msg";
    }

    $parser->consume_to($consume_to);
    $parser->rewrite_backtrack;

    $parser->add_error($err_msg);
    die $err_msg;
}

sub expected {
    my ($parser, $expected, $consume_to) = @_;

    $parser->{indent}-- if $parser->{debug};

    if (defined (my $token = $parser->current_token)) {
        my $name = pretty_token($token->[0]) . ' (' . pretty_value($token->[1]) . ')';
        error($parser, "Expected $expected but got $name");
    } else {
        error($parser, "Expected $expected but got EOF");
    }
}

my %prettier_token = (
    TOKEN_TERM,  'expression terminator',
    TOKEN_IDENT, 'identifier',
);

sub pretty_token {
    my ($token) = @_;
    return $prettier_token{$token} // $pretty_token[$token] // $token;
}

sub pretty_value {
    my ($value) = @_;
    $value =~ s/\n/\\n/g;
    return $value;
}

sub token_position {
    my ($token) = @_;

    my ($line, $col);

    if (defined $token) {
        $line = $token->[2];
        $col  = $token->[3];
    }

    return { line => $line, col => $col };
}

# start-rule:
# Program ::= Expression*
sub Program {
    my ($parser) = @_;

    $parser->try('Program: Expression*');
    my @expressions;

    my $MAX_ERRORS = 3; # TODO make this customizable
    my $errors;

    while (defined $parser->next_token('peek')) {
        eval {
            my $expression = Expression($parser);

            if ($expression and $expression->[0] != INSTR_NOP) {
                push @expressions, $expression;
            }
        };

        if ($@) {
            last if ++$errors > $MAX_ERRORS;
            next;
        }
    }

    $parser->advance;
    return @expressions ? ['PRGM', \@expressions] : undef;
}

my @keyword_dispatcher;
$keyword_dispatcher[KEYWORD_NULL]   = \&KeywordNull;
$keyword_dispatcher[KEYWORD_TRUE]   = \&KeywordTrue;
$keyword_dispatcher[KEYWORD_FALSE]  = \&KeywordFalse;
$keyword_dispatcher[KEYWORD_FN]     = \&KeywordFn;
$keyword_dispatcher[KEYWORD_RETURN] = \&KeywordReturn;
$keyword_dispatcher[KEYWORD_WHILE]  = \&KeywordWhile;
$keyword_dispatcher[KEYWORD_NEXT]   = \&KeywordNext;
$keyword_dispatcher[KEYWORD_LAST]   = \&KeywordLast;
$keyword_dispatcher[KEYWORD_IF]     = \&KeywordIf;
$keyword_dispatcher[KEYWORD_ELSE]   = \&ElseWithoutIf;
$keyword_dispatcher[KEYWORD_EXISTS] = \&KeywordExists;
$keyword_dispatcher[KEYWORD_DELETE] = \&KeywordDelete;
$keyword_dispatcher[KEYWORD_KEYS]   = \&KeywordKeys;
$keyword_dispatcher[KEYWORD_VALUES] = \&KeywordValues;
$keyword_dispatcher[KEYWORD_VAR]    = \&KeywordVar;

sub Keyword {
    my ($parser) = @_;

    $parser->try('Keyword');

    # peek at upcoming token
    my $token = $parser->next_token('peek');
    return if not defined $token;

    # get token's dispatcher
    my $dispatcher = $keyword_dispatcher[$keyword_id{$token->[1]}];

    # attempt to dispatch token
    if (defined $dispatcher) {
        my $result = $dispatcher->($parser);

        if (defined $result) {
            $parser->advance;
            return $result;
        }
    }

    error($parser, "Unknown keyword `$token->[1]`");
}

# error about unexpected keywords
sub UnexpectedKeyword {
    my ($parser) = @_;

    # if a keyword is found outside of Keyword() then it is unexpected
    if (my $token = $parser->consume(TOKEN_KEYWORD)) {
        error($parser, "unexpected keyword `$token->[1]`");
    }

    return;
}

sub consume_keyword {
    my ($parser, $keyword) = @_;

    my $token = $parser->consume(TOKEN_KEYWORD);

    if (!defined $token) {
        return;
    }

    if ($token->[1] eq $keyword) {
        return $token;
    }

    return;
}

# KeywordNull ::= "null"
sub KeywordNull {
    my ($parser) = @_;
    my $token = consume_keyword($parser, 'null');
    return [['TYPE', 'Null'], undef, token_position($token)];
}

# KeywordTrue ::= "true"
sub KeywordTrue {
    my ($parser) = @_;
    my $token = consume_keyword($parser, 'true');
    return [['TYPE', 'Boolean'], 1, token_position($token)];
}

# KeywordFalse ::= "false"
sub KeywordFalse {
    my ($parser) = @_;
    my $token = consume_keyword($parser, 'false');
    return [['TYPE', 'Boolean'], 0, token_position($token)];
}

# KeywordReturn ::= "return" Expression?
sub KeywordReturn {
    my ($parser) = @_;
    my $token = consume_keyword($parser, 'return');
    my $expression = Expression($parser);
    return [INSTR_RET, $expression, token_position($token)];
}

# KeywordWhile ::= "while" "(" Expression ")" Expression
sub KeywordWhile {
    my ($parser) = @_;

    my $token = consume_keyword($parser, 'while');

    if (not $parser->consume(TOKEN_L_PAREN)) {
        expected($parser, "'(' after `while` keyword");
    }

    my $expr = Expression($parser);

    if (not $expr) {
        expected($parser, "expression for `while` condition");
    }

    if (not $parser->consume(TOKEN_R_PAREN)) {
        expected($parser, "')' after `while` condition expression");
    }

    my $body = Expression($parser);

    if (not $body) {
        expected($parser, "expression for `while` loop body");
    }

    return [INSTR_WHILE, $expr, $body, token_position($token)];
}

# KeywordNext ::= "next"
sub KeywordNext {
    my ($parser) = @_;
    my $token = consume_keyword($parser, 'next');
    return [INSTR_NEXT, undef, token_position($token)];
}

# KeywordLast ::= "last" Expression?
sub KeywordLast {
    my ($parser) = @_;
    my $token = consume_keyword($parser, 'last');
    my $expression = Expression($parser);
    return [INSTR_LAST, $expression, token_position($token)];
}


# KeywordIf ::= "if" Expression "then" Expression "else" Expression
sub KeywordIf {
    my ($parser) = @_;

    my $token = consume_keyword($parser, 'if');

    my $expr = Expression($parser);

    if (not $expr) {
        expected($parser, "expression for `if` condition");
    }

    if (not consume_keyword($parser, 'then')) {
        expected($parser, "`then` after `if` condition");
    }

    my $body = Expression($parser);

    if (not $body) {
        expected($parser, "expression for `then` branch of `if` expression");
    }

    if (not consume_keyword($parser, 'else')) {
        expected($parser, "`else` branch for `if` expression");
    }

    my $else = Expression($parser);

    if (not $else) {
        expected($parser, "expression for `else` branch of `if` expression");
    }

    return [INSTR_IF, $expr, $body, $else, token_position($token)];
}

# error about an `else` without an `if`
sub ElseWithoutIf {
    my ($parser) = @_;

    # if an `else` is consumed outside of IfExpression() then it is a stray `else`
    if (consume_keyword($parser, 'else')) {
        error($parser, "`else` without matching `if`");
    }

    return;
}

# KeywordExists ::= "exists" Expression
sub KeywordExists {
    my ($parser) = @_;

    my $token = consume_keyword($parser, 'exists');

    my $expression = Expression($parser);

    if (not $expression or not defined $expression->[1]) {
        expected($parser, "expression after `exists` keyword");
    }

    return [INSTR_EXISTS, $expression, token_position($token)];
}

# KeywordDelete ::= "delete" Expression
sub KeywordDelete {
    my ($parser) = @_;

    my $token = consume_keyword($parser, 'delete');

    my $expression = Expression($parser);

    if (not $expression or not defined $expression->[1]) {
        expected($parser, "expression after `delete` keyword");
    }

    return [INSTR_DELETE, $expression, token_position($token)];
}

# KeywordKeys ::= "keys" Expression
sub KeywordKeys {
    my ($parser) = @_;

    my $token = consume_keyword($parser, 'keys');

    my $expression = Expression($parser);

    if (not $expression or not defined $expression->[1]) {
        expected($parser, "expression after `keys` keyword");
    }

    return [INSTR_KEYS, $expression, token_position($token)];
}

# KeywordValues ::= KEYWORD_values Expression
sub KeywordValues {
    my ($parser) = @_;

    my $token = consume_keyword($parser, 'values');

    my $expression = Expression($parser);

    if (not $expression or not defined $expression->[1]) {
        expected($parser, "expression after `values` keyword");
    }

    return [INSTR_VALUES, $expression, token_position($token)];
}

# KeywordVar ::= "var" IDENT (":" Type)? Initializer?
sub KeywordVar {
    my ($parser) = @_;

    my $var_token = consume_keyword($parser, 'var');

    my $ident_token = $parser->consume(TOKEN_IDENT);

    if (not $ident_token) {
        expected($parser, 'identifier for variable name');
    }

    my $name = $ident_token->[1];

    my $type;
    if ($parser->consume(TOKEN_COLON)) {
        $type = Type($parser);

        if (not $type) {
            expected($parser, "type after \":\" for variable `$name`");
        }
    }

    if (not $type) {
        $type = ['TYPE', 'Any'];
    }

    my $initializer = Initializer($parser);

    return [INSTR_VAR, $type, $name, $initializer, token_position($var_token)];
}

# Initializer ::= ASSIGN Expression
sub Initializer {
    my ($parser) = @_;

    $parser->try('Initializer');

    if ($parser->consume(TOKEN_ASSIGN)) {
        my $expr;

        $expr = MapConstructor($parser);

        if ($expr) {
            $parser->advance;
            return $expr;
        }

        # try an expression
        $expr = Expression($parser);

        if ($expr) {
            $parser->advance;
            return $expr;
        }

        expected($parser, 'expression for initializer');
    }

    $parser->backtrack;
}

# Type         ::= TypeLiteral ("|" TypeLiteral)*
# TypeLiteral  ::= TypeFunction | TYPE
# TypeFunction ::= (TYPE_Function | TYPE_Builtin) TypeFunctionParams? TypeFunctionReturn?
# TypeFunctionParams ::= "(" (Type ","?)* ")"
# TypeFunctionReturn ::= "->" Type
sub Type {
    my ($parser) = @_;

    $parser->try('Type');

    my $typeunion = [];

    my $type = TypeLiteral($parser);
    goto TYPE_FAIL if not $type;

    while (1) {
        push @$typeunion, $type;

        if (not $parser->consume(TOKEN_PIPE)) {
            last;
        }

        $type = TypeLiteral($parser);

        if (not $type) {
            expected($parser, 'type after "|"');
        }
    }

    $parser->advance;

    if (@$typeunion > 1) {
        my @sorted = sort { $a->[1] cmp $b->[1] } @$typeunion;
        return ['TYPEUNION', \@sorted];
    } else {
        return $type;
    }

  TYPE_FAIL:
    $parser->backtrack;
};

sub TypeLiteral {
    my ($parser) = @_;

    my $type = TypeFunction($parser);
    return $type if $type;

    my $token = $parser->next_token('peek');
    return if not $token;

    if ($token->[0] == TOKEN_TYPE) {
        my $type = $token->[1];
        $parser->consume;
        return ['TYPE', $type, token_position($token)];
    }

    return;
}

sub TypeFunction {
    my ($parser) = @_;

    my $token = $parser->next_token('peek');
    return if not $token;

    my $kind = $token->[1];

    if (defined $kind and ($kind eq 'Function' or  $kind eq 'Builtin')) {
        $parser->consume;

        my $params = TypeFunctionParams($parser) // [];

        my $return_type = TypeFunctionReturn($parser) // ['TYPE', 'Any'];

        return ['TYPEFUNC', $kind, $params, $return_type, token_position($token)];
    }

    return;
}

sub TypeFunctionParams {
    my ($parser) = @_;

    if ($parser->consume(TOKEN_L_PAREN)) {
        my $types = [];

        while (1) {
            my $type = TypeLiteral($parser);

            push @$types, $type if $type;

            $parser->consume(TOKEN_COMMA);
            last if $parser->consume(TOKEN_R_PAREN);
            expected($parser, 'type name or ")"');
        }

        return $types;
    }

    return;
}

sub TypeFunctionReturn {
    my ($parser) = @_;

    if ($parser->consume(TOKEN_R_ARROW)) {
        my $type = TypeLiteral($parser);

        if (not $type) {
            expected($parser, 'function return type');
        }

        return $type;
    }

    return;
}

# KeywordFn ::= "fn" IDENT? IdentifierList? ("->" Type)? ExpressionGroup | Expression)
sub KeywordFn {
    my ($parser) = @_;

    my $fn_token = consume_keyword($parser, 'fn');

    my $ident_token = $parser->consume(TOKEN_IDENT);
    my $name  = $ident_token ? $ident_token->[1] : '#anonymous';

    my $identlist = IdentifierList($parser);

    $identlist = [] if not defined $identlist;

    my $return_type = TypeFunctionReturn($parser);

    $return_type = ['TYPE', 'Any'] if not defined $return_type;

    my $expression = Expression($parser);

    if (!defined $expression) {
        expected($parser, "expression for body of function $name");
    }

    return [INSTR_FUNCDEF, $return_type, $name, $identlist, [$expression], token_position($fn_token)];
}

# IdentifierList ::= "(" (Identifier (":" Type)? Initializer? ","?)* ")"
sub IdentifierList {
    my ($parser) = @_;

    $parser->try('IdentifierList');

    goto IDENTLIST_FAIL if not $parser->consume(TOKEN_L_PAREN);

    my $identlist = [];
    while (1) {
        if (my $token = $parser->consume(TOKEN_IDENT)) {
            my $name = $token->[1];
            my $type;

            if ($parser->consume(TOKEN_COLON)) {
                $type = Type($parser);

                if (not $type) {
                    expected($parser, "type after \":\" for parameter `$name`");
                }
            }

            $type //= ['TYPE', 'Any'];

            my $initializer = Initializer($parser);
            push @{$identlist}, [$type, $name, $initializer, token_position($token)];
            $parser->consume(TOKEN_COMMA);
            next;
        }

        last if $parser->consume(TOKEN_R_PAREN);
        goto IDENTLIST_FAIL;
    }

    $parser->advance;
    return $identlist;

  IDENTLIST_FAIL:
    $parser->backtrack;
}

# MapConstructor ::= "{" ((String | IDENT) ":" Expression ","?)* "}"
#         String ::= DQUOTE_STRING | SQUOTE_STRING
sub MapConstructor {
    my ($parser) = @_;

    $parser->try('MapConstructor');

    if (my $token = $parser->consume(TOKEN_L_BRACE)) {
        my @map;
        while (1) {
            my $parsedkey = $parser->consume(TOKEN_DQUOTE_STRING)
            || $parser->consume(TOKEN_SQUOTE_STRING)
            || $parser->consume(TOKEN_IDENT);

            if ($parsedkey) {
                my $mapkey;

                if ($parsedkey->[0] == TOKEN_DQUOTE_STRING) {
                    $parsedkey->[1] =~ s/^"|"$//g;
                    $mapkey = [['TYPE', 'String'], $parsedkey->[1], token_position($parsedkey)];
                } elsif ($parsedkey->[0] == TOKEN_SQUOTE_STRING) {
                    $parsedkey->[1] =~ s/^'|'$//g;
                    $mapkey = [['TYPE', 'String'], $parsedkey->[1], token_position($parsedkey)];
                } else {
                    $mapkey = [INSTR_IDENT, $parsedkey->[1], token_position($parsedkey)];
                }

                if (not $parser->consume(TOKEN_COLON)) {
                    expected($parser, '":" after map key');
                }

                my $expr = Expression($parser);

                if (not $expr) {
                    expected($parser, 'expression for map value');
                }

                $parser->consume(TOKEN_COMMA);

                push @map, [$mapkey, $expr];
                next;
            }

            last if $parser->consume(TOKEN_R_BRACE);
            expected($parser, 'map entry or `}` in map initializer');
        }

        $parser->advance;
        return [INSTR_MAPINIT, \@map, token_position($token)];
    }

    $parser->backtrack;
}

# ArrayConstructor ::= "[" (Expression ","?)* "]"
sub ArrayConstructor {
    my ($parser) = @_;

    $parser->try('ArrayConstructor');

    if (my $token = $parser->consume(TOKEN_L_BRACKET)) {
        my @array;
        while (1) {
            my $expr = Expression($parser);

            if ($expr) {
                $parser->consume(TOKEN_COMMA);
                push @array, $expr;
                next;
            }

            last if $parser->consume(TOKEN_R_BRACKET);
            expected($parser, 'expression or `]` in array initializer');
        }

        $parser->advance;
        return [INSTR_ARRAYINIT, \@array, token_position($token)];
    }

    $parser->backtrack;
}

# Pratt parser for expressions

my %precedence_table = (
    ACCESS      => 18,
    CALL        => 17,
    POSTFIX     => 16,
    PREFIX      => 15,
    EXPONENT    => 14,
    PRODUCT     => 13,
    SUM         => 12,
    STRING      => 11,
    RELATIONAL  => 10,
    EQUALITY    => 9,
    LOGICAL_AND => 8,
    LOGICAL_OR  => 7,
    CONDITIONAL => 6,
    ASSIGNMENT  => 5,
    COMMA       => 4,
    LOW_NOT     => 3,
    LOW_AND     => 2,
    LOW_OR      => 1,
);

# postfix is handled by Infix
my %infix_token_precedence = (
    TOKEN_DOT         , $precedence_table{'ACCESS'},
    TOKEN_L_PAREN     , $precedence_table{'CALL'},
    TOKEN_PLUS_PLUS   , $precedence_table{'POSTFIX'},
    TOKEN_MINUS_MINUS , $precedence_table{'POSTFIX'},
    TOKEN_L_BRACKET   , $precedence_table{'POSTFIX'},
    TOKEN_STAR_STAR   , $precedence_table{'EXPONENT'},
    TOKEN_CARET       , $precedence_table{'EXPONENT'},
    TOKEN_PERCENT     , $precedence_table{'EXPONENT'},
    TOKEN_STAR        , $precedence_table{'PRODUCT'},
    TOKEN_SLASH       , $precedence_table{'PRODUCT'},
    TOKEN_PLUS        , $precedence_table{'SUM'},
    TOKEN_MINUS       , $precedence_table{'SUM'},
    TOKEN_CARET_CARET , $precedence_table{'STRING'},
    TOKEN_TILDE       , $precedence_table{'STRING'},
    TOKEN_GREATER_EQ  , $precedence_table{'RELATIONAL'},
    TOKEN_LESS_EQ     , $precedence_table{'RELATIONAL'},
    TOKEN_GREATER     , $precedence_table{'RELATIONAL'},
    TOKEN_LESS        , $precedence_table{'RELATIONAL'},
    TOKEN_EQ          , $precedence_table{'EQUALITY'},
    TOKEN_NOT_EQ      , $precedence_table{'EQUALITY'},
    TOKEN_AMP_AMP     , $precedence_table{'LOGICAL_AND'},
    TOKEN_PIPE_PIPE   , $precedence_table{'LOGICAL_OR'},
    TOKEN_QUESTION    , $precedence_table{'CONDITIONAL'},
    TOKEN_ASSIGN      , $precedence_table{'ASSIGNMENT'},
    TOKEN_PLUS_EQ     , $precedence_table{'ASSIGNMENT'},
    TOKEN_MINUS_EQ    , $precedence_table{'ASSIGNMENT'},
    TOKEN_STAR_EQ     , $precedence_table{'ASSIGNMENT'},
    TOKEN_SLASH_EQ    , $precedence_table{'ASSIGNMENT'},
    TOKEN_DOT_EQ      , $precedence_table{'ASSIGNMENT'},
    TOKEN_DOT_DOT     , $precedence_table{'COMMA'},
    TOKEN_NOT         , $precedence_table{'LOW_NOT'},
    TOKEN_AND         , $precedence_table{'LOW_AND'},
    TOKEN_OR          , $precedence_table{'LOW_OR'},
);

use constant {
    ASSOC_LEFT  => 0,
    ASSOC_RIGHT => 1,
};

my @binop_data;
$binop_data[TOKEN_DOT]         = [INSTR_ACCESS,     'ACCESS',      ASSOC_LEFT];
$binop_data[TOKEN_STAR_STAR]   = [INSTR_POW,        'EXPONENT',    ASSOC_RIGHT];
$binop_data[TOKEN_CARET]       = [INSTR_POW,        'EXPONENT',    ASSOC_RIGHT];
$binop_data[TOKEN_PERCENT]     = [INSTR_REM,        'EXPONENT',    ASSOC_LEFT];
$binop_data[TOKEN_STAR]        = [INSTR_MUL,        'PRODUCT',     ASSOC_LEFT];
$binop_data[TOKEN_SLASH]       = [INSTR_DIV,        'PRODUCT',     ASSOC_LEFT];
$binop_data[TOKEN_PLUS]        = [INSTR_ADD,        'SUM',         ASSOC_LEFT];
$binop_data[TOKEN_MINUS]       = [INSTR_SUB,        'SUM',         ASSOC_LEFT];
$binop_data[TOKEN_TILDE]       = [INSTR_STRIDX,     'STRING',      ASSOC_LEFT];
$binop_data[TOKEN_CARET_CARET] = [INSTR_STRCAT,     'STRING',      ASSOC_LEFT];
$binop_data[TOKEN_GREATER_EQ]  = [INSTR_GTE,        'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_LESS_EQ]     = [INSTR_LTE,        'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_GREATER]     = [INSTR_GT,         'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_LESS]        = [INSTR_LT,         'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_NOT_EQ]      = [INSTR_NEQ,        'EQUALITY',    ASSOC_LEFT];
$binop_data[TOKEN_AMP_AMP]     = [INSTR_AND,        'LOGICAL_AND', ASSOC_LEFT];
$binop_data[TOKEN_PIPE_PIPE]   = [INSTR_OR,         'LOGICAL_OR',  ASSOC_LEFT];
$binop_data[TOKEN_EQ]          = [INSTR_EQ,         'EQUALITY',    ASSOC_LEFT];
$binop_data[TOKEN_ASSIGN]      = [INSTR_ASSIGN,     'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_PLUS_EQ]     = [INSTR_ADD_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_MINUS_EQ]    = [INSTR_SUB_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_STAR_EQ]     = [INSTR_MUL_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_SLASH_EQ]    = [INSTR_DIV_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_DOT_EQ]      = [INSTR_CAT_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_DOT_DOT]     = [INSTR_RANGE,      'COMMA',       ASSOC_RIGHT];
$binop_data[TOKEN_AND]         = [INSTR_AND,        'LOW_AND',     ASSOC_LEFT];
$binop_data[TOKEN_OR]          = [INSTR_OR,         'LOW_OR',      ASSOC_LEFT];

sub get_precedence {
    my ($tokentype) = @_;
    return $infix_token_precedence{$tokentype} // 0;
}

sub UnaryOp {
    my ($parser, $op, $ins) = @_;

    if (my $token = $parser->consume($op)) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return $expr ? [$ins, $expr, token_position($token)] : expected($parser, 'expression');
    }
}

sub BinaryOp {
    my ($parser, $left, $op, $ins, $precedence, $right_associative) = @_;
    $right_associative ||= 0;

    if (my $token = $parser->consume($op)) {
        my $right = Expression($parser, $precedence_table{$precedence} - $right_associative);
        return $right ? [$ins, $left, $right, token_position($token)] : expected($parser, 'expression');
    }
}

# ExpressionGroup ::= L_BRACE Expression* R_BRACE
sub ExpressionGroup {
    my ($parser) = @_;

    $parser->try('ExpressionGroup: L_BRACE Expression R_BRACE');

    {
        my $token = $parser->consume(TOKEN_L_BRACE);

        if (!defined $token) {
            goto EXPRESSION_GROUP_FAIL;
        }

        my @expressions;

        while (1) {
            my $expression = Expression($parser);

            if ($expression) {
                push @expressions, $expression unless $expression->[0] == INSTR_NOP;
                next;
            }

            last if $parser->consume(TOKEN_R_BRACE);
            goto EXPRESSION_GROUP_FAIL;
        }

        $parser->advance;
        return [INSTR_EXPR_GROUP, \@expressions, token_position($token)];
    }

  EXPRESSION_GROUP_FAIL:
    $parser->backtrack;
}

sub Expression {
    my ($parser, $precedence) = @_;

    $precedence ||= 0;

    $parser->try("Expression (prec $precedence)");

    {
        if ($parser->consume(TOKEN_TERM)) {
            $parser->advance;
            return [INSTR_NOP, undef];
        }

        my $left = Prefix($parser, $precedence);

        goto EXPRESSION_FAIL if not $left;

        while (1) {
            my $token = $parser->next_token('peek');
            last if not defined $token;
            my $token_precedence = get_precedence $token->[0];
            last if $precedence >= $token_precedence;

            $left = Infix($parser, $left, $token_precedence);
        }

        $parser->advance;
        return $left;
    }

  EXPRESSION_FAIL:
    $parser->backtrack;
}

sub Identifier {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_IDENT);
    return [INSTR_IDENT, $token->[1], token_position($token)];
}

sub LiteralInteger {
    my ($parser) = @_;

    my $token = $parser->consume(TOKEN_INT);

    if ($token->[1] =~ /^0/) {
        $token->[1] = oct $token->[1];
    }

    return [INSTR_LITERAL, ['TYPE', 'Integer'], $token->[1] + 0, token_position($token)];
}

sub LiteralFloat {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_FLT);
    return [INSTR_LITERAL, ['TYPE', 'Real'], $token->[1] + 0, token_position($token)];
}

sub LiteralHexInteger {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_HEX);
    return [INSTR_LITERAL, ['TYPE', 'Integer'], hex $token->[1], token_position($token)];
}

sub PrefixRBrace {
    my ($parser) = @_;

    my $expr = ExpressionGroup($parser);
    return $expr if defined $expr;

    $expr = MapConstructor($parser);
    return $expr if defined $expr;

    error($parser, "Unhandled { token");
}

sub PrefixSquoteStringI {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_SQUOTE_STRING_I);
    $token->[1] =~ s/^\$//;
    $token->[1] =~ s/^\'|\'$//g;
    return [INSTR_STRING_I, $token->[1], token_position($token)];
}

sub expand_escapes {
    my ($string) = @_;
    $string =~ s/\\(
    (?:[arnt'"\\]) |               # Single char escapes
    (?:[ul].) |                    # uc or lc next char
    (?:x[0-9a-fA-F]{2}) |          # 2 digit hex escape
    (?:x\{[0-9a-fA-F]+\}) |        # more than 2 digit hex
    (?:\d{2,3}) |                  # octal
    (?:N\{U\+[0-9a-fA-F]{2,4}\})   # unicode by hex
    )/"qq|\\$1|"/geex;
    return $string;
}

sub PrefixDquoteStringI {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_DQUOTE_STRING_I);
    $token->[1] =~ s/^\$//;
    $token->[1] =~ s/^\"|\"$//g;
    return [INSTR_STRING_I, expand_escapes($token->[1]), token_position($token)];
}

sub PrefixSquoteString {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_SQUOTE_STRING);
    $token->[1] =~ s/^\'|\'$//g;
    return [INSTR_LITERAL, ['TYPE', 'String'], expand_escapes($token->[1]), token_position($token)];
}

sub PrefixDquoteString {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_DQUOTE_STRING);
    $token->[1] =~ s/^\"|\"$//g;
    return [INSTR_LITERAL, ['TYPE', 'String'], expand_escapes($token->[1]), token_position($token)];
}

sub PrefixMinusMinus {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_MINUS_MINUS);
    my $expr = Expression($parser, $precedence_table{'PREFIX'});
    expected($parser, 'expression') if not defined $expr;
    return [INSTR_PREFIX_SUB, $expr, token_position($token)];
}

sub PrefixPlusPlus {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_PLUS_PLUS);
    my $expr = Expression($parser, $precedence_table{'PREFIX'});
    expected($parser, 'expression') if not defined $expr;
    return [INSTR_PREFIX_ADD, $expr, token_position($token)];
}

sub PrefixBang {
    my ($parser) = @_;
    return UnaryOp($parser, TOKEN_BANG, INSTR_NOT);
}

sub PrefixMinus {
    my ($parser) = @_;
    return UnaryOp($parser, TOKEN_MINUS, INSTR_NEG);
}

sub PrefixPlus {
    my ($parser) = @_;
    return UnaryOp($parser, TOKEN_PLUS,  INSTR_POS);
}

sub PrefixNot {
    my ($parser) = @_;
    return UnaryOp($parser, TOKEN_NOT,   INSTR_NOT);
}

sub PrefixLParen {
    my ($parser) = @_;
    $parser->consume(TOKEN_L_PAREN);
    my $expr = Expression($parser);
    expected($parser, '")"') if not $parser->consume(TOKEN_R_PAREN);
    return $expr;
}

sub PrefixType {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_TYPE);
    # convert to identifier to invoke builtin function for type conversion
    return [INSTR_IDENT, $token->[1], token_position($token)];
}

my @prefix_dispatcher;
$prefix_dispatcher[TOKEN_KEYWORD]         = \&Keyword;
$prefix_dispatcher[TOKEN_L_BRACE]         = \&PrefixRBrace;
$prefix_dispatcher[TOKEN_L_BRACKET]       = \&ArrayConstructor;
$prefix_dispatcher[TOKEN_INT]             = \&LiteralInteger;
$prefix_dispatcher[TOKEN_FLT]             = \&LiteralFloat;
$prefix_dispatcher[TOKEN_HEX]             = \&LiteralHexInteger;
$prefix_dispatcher[TOKEN_TYPE]            = \&PrefixType;
$prefix_dispatcher[TOKEN_IDENT]           = \&Identifier;
$prefix_dispatcher[TOKEN_SQUOTE_STRING_I] = \&PrefixSquoteStringI;
$prefix_dispatcher[TOKEN_DQUOTE_STRING_I] = \&PrefixDquoteStringI;
$prefix_dispatcher[TOKEN_SQUOTE_STRING]   = \&PrefixSquoteString;
$prefix_dispatcher[TOKEN_DQUOTE_STRING]   = \&PrefixDquoteString;
$prefix_dispatcher[TOKEN_MINUS_MINUS]     = \&PrefixMinusMinus;
$prefix_dispatcher[TOKEN_PLUS_PLUS]       = \&PrefixPlusPlus;
$prefix_dispatcher[TOKEN_BANG]            = \&PrefixBang;
$prefix_dispatcher[TOKEN_PLUS]            = \&PrefixPlus;
$prefix_dispatcher[TOKEN_MINUS]           = \&PrefixMinus;
$prefix_dispatcher[TOKEN_NOT]             = \&PrefixNot;
$prefix_dispatcher[TOKEN_L_PAREN]         = \&PrefixLParen;

sub Prefix {
    my ($parser, $precedence) = @_;

    # peek at upcoming token
    my $token = $parser->next_token('peek');
    return if not defined $token;

    # get token's dispatcher
    my $dispatcher = $prefix_dispatcher[$token->[0]];

    # attempt to dispatch token
    if (defined $dispatcher) {
        my $result = $dispatcher->($parser);
        return $result if defined $result;
    }

    # no dispatch for token, handle edge cases

    # throw exception on unexpected keyword
    UnexpectedKeyword($parser);

    return;
}

sub InfixConditionalOperator {
    my ($parser, $left) = @_;

    if (my $token = $parser->consume(TOKEN_QUESTION)) {

        my $then = Expression($parser);

        if (not $then) {
            expected($parser, '<then> expression in conditional <if> ? <then> : <else> operator');
        }

        if (not $parser->consume(TOKEN_COLON)) {
            expected($parser, '":" after <then> expression in conditional <if> ? <then> : <else> operator');
        }

        my $else = Expression($parser);

        if (not $else) {
            expected($parser, '<else> expression in conditional <if> ? <then> : <else> operator');
        }

        return [INSTR_COND, $left, $then, $else, token_position($token)];
    }
}

sub Infix {
    my ($parser, $left, $precedence) = @_;

    # peek at upcoming token
    my $token = $parser->next_token('peek');
    return if not defined $token;

    # get token's binop data
    my $data = $binop_data[$token->[0]];

    # attempt to dispatch token
    if (defined $data) {
        my $result = BinaryOp($parser, $left, $token->[0], $data->[0], $data->[1], $data->[2]);
        return $result if defined $result;
    }

    # no dispatch for token, handle edge cases

    $data = InfixConditionalOperator($parser, $left);
    return $data if defined $data;

    return Postfix($parser, $left, $precedence);
}

sub PostfixPlusPlus {
    my ($parser, $left) = @_;
    my $token = $parser->consume(TOKEN_PLUS_PLUS);
    return [INSTR_POSTFIX_ADD, $left, token_position($token)];
}

sub PostfixMinusMinus {
    my ($parser, $left) = @_;
    my $token = $parser->consume(TOKEN_MINUS_MINUS);
    return [INSTR_POSTFIX_SUB, $left, token_position($token)];
}

sub PostfixLParen {
    my ($parser, $left) = @_;

    my $token = $parser->consume(TOKEN_L_PAREN);

    my $arguments = [];

    while (1) {
        my $expression = Expression($parser);

        if ($expression) {
            push @{$arguments}, $expression;
            $parser->consume(TOKEN_COMMA);
            next;
        }

        last if $parser->consume(TOKEN_R_PAREN);
        expected($parser, 'expression or closing ")" for function call argument list');
    }

    return [INSTR_CALL, $left, $arguments, token_position($token)];
}

sub PostfixLBracket {
    my ($parser, $left) = @_;

    my $token = $parser->consume(TOKEN_L_BRACKET);

    my $expression = Expression($parser);

    if (not $expression or not defined $expression->[1]) {
        expected($parser, 'expression in postfix [] brackets');
    }

    if (not $parser->consume(TOKEN_R_BRACKET)) {
        expected($parser, 'closing ] bracket');
    }

    return [INSTR_ACCESS, $left, $expression, token_position($token)];
}

my @postfix_dispatcher;
$postfix_dispatcher[TOKEN_PLUS_PLUS]   = \&PostfixPlusPlus;
$postfix_dispatcher[TOKEN_MINUS_MINUS] = \&PostfixMinusMinus;
$postfix_dispatcher[TOKEN_L_PAREN]     = \&PostfixLParen;
$postfix_dispatcher[TOKEN_L_BRACKET]   = \&PostfixLBracket;

sub Postfix {
    my ($parser, $left, $precedence) = @_;

    # peek at upcoming token
    my $token = $parser->next_token('peek');
    return if not defined $token;

    # get token's dispatcher
    my $dispatcher = $postfix_dispatcher[$token->[0]];

    # attempt to dispatch token
    if (defined $dispatcher) {
        my $result = $dispatcher->($parser, $left);
        return $result if defined $result;
    }

    # no postfix
    return $left;
}

1;
