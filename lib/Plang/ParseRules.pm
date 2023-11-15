#!/usr/bin/env perl

# Recursive descent rules to parse a Plang program using the Plang::Parser
# class. Constructs an abstract syntax tree annotated with token line/col
# positions.
#
# Program() is the start-rule.

package Plang::ParseRules;

use warnings;
use strict;
use feature 'signatures';

use parent 'Exporter';
our @EXPORT_OK = qw/Program/; # start-rule
our %EXPORT_TAGS = ('all' => \@EXPORT_OK);

use Plang::Constants::Tokens       ':all';
use Plang::Constants::Keywords     ':all';
use Plang::Constants::Instructions ':all';

sub error($parser, $err_msg, $consume_to = TOKEN_TERM) {
    my $pos = '';

    if (defined (my $token = $parser->current_token)) {
        $pos = " at line $token->[2], col $token->[3]";
    }
    elsif (defined (my $prev_token = $parser->previous_token)) {
        $pos = " at line $prev_token->[2], col $prev_token->[3]";
    }

    chomp $err_msg;
    $err_msg = "Parse error: $err_msg$pos.";
    $parser->consume_to($consume_to);
    $parser->rewrite_backtrack;
    $parser->add_error($err_msg);
    die $err_msg;
}

sub expected($parser, $expected) {
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

sub pretty_token($token) {
    return $prettier_token{$token} // $pretty_token[$token] // $token;
}

sub pretty_value($value) {
    $value =~ s/\n/\\n/g;
    return $value;
}

sub token_position($token) {
    my ($line, $col);

    if (defined $token) {
        $line = $token->[2];
        $col  = $token->[3];
    }

    return { line => $line, col => $col };
}

# start-rule:
# Program ::= {Expression}+
sub Program($parser) {
    $parser->try('Program: Expression*');
    my @expressions;

    my $MAX_ERRORS = 3; # TODO make this customizable
    my $errors;

    while (defined $parser->next_token('peek')) {
        eval {
            my $expression = Expression($parser);

            if (not defined $expression) {
                expected($parser, 'expression');
            }

            if ($expression->[0] != INSTR_NOP) {
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
$keyword_dispatcher[KEYWORD_TRY]    = \&KeywordTry;
$keyword_dispatcher[KEYWORD_CATCH]  = \&CatchWithoutTry;
$keyword_dispatcher[KEYWORD_THROW]  = \&KeywordThrow;
$keyword_dispatcher[KEYWORD_TYPE]   = \&KeywordType;

sub Keyword($parser) {
    $parser->try('Keyword');

    # peek at upcoming token
    my $token = $parser->next_token('peek') // return;

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

    error($parser, "unknown keyword `$token->[1]`");
}

# error about unexpected keywords
sub UnexpectedKeyword($parser) {
    # if a keyword is found outside of Keyword() then it is unexpected
    if (my $token = $parser->consume(TOKEN_KEYWORD)) {
        error($parser, "unexpected keyword `$token->[1]`");
    }

    return;
}

sub consume_keyword($parser, $keyword) {
    my $token = $parser->consume(TOKEN_KEYWORD) // return;

    if ($token->[1] eq $keyword) {
        return $token;
    }

    return;
}

# KeywordNull ::= "null"
sub KeywordNull($parser) {
    my $token = consume_keyword($parser, 'null');
    return [INSTR_LITERAL, ['TYPE', 'Null'], undef, token_position($token)];
}

# KeywordTrue ::= "true"
sub KeywordTrue($parser) {
    my $token = consume_keyword($parser, 'true');
    return [INSTR_LITERAL, ['TYPE', 'Boolean'], 1, token_position($token)];
}

# KeywordFalse ::= "false"
sub KeywordFalse($parser) {
    my $token = consume_keyword($parser, 'false');
    return [INSTR_LITERAL, ['TYPE', 'Boolean'], 0, token_position($token)];
}

# KeywordReturn ::= "return" [Expression]
sub KeywordReturn($parser) {
    my $token = consume_keyword($parser, 'return');
    my $expression = Expression($parser);
    return [INSTR_RET, $expression, token_position($token)];
}

# KeywordWhile ::= "while" "(" Expression ")" Expression
sub KeywordWhile($parser) {
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
sub KeywordNext($parser) {
    my $token = consume_keyword($parser, 'next');
    return [INSTR_NEXT, undef, token_position($token)];
}

# KeywordLast ::= "last" [Expression]
sub KeywordLast($parser) {
    my $token = consume_keyword($parser, 'last');
    my $expression = Expression($parser);
    return [INSTR_LAST, $expression, token_position($token)];
}


# KeywordIf ::= "if" Expression "then" Expression "else" Expression
sub KeywordIf($parser) {
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
sub ElseWithoutIf($parser) {
    # if an `else` is consumed outside of KeywordIf() then it is a stray `else`
    if (consume_keyword($parser, 'else')) {
        error($parser, "`else` without matching `if`");
    }

    return;
}

# KeywordExists ::= "exists" Expression
sub KeywordExists($parser) {
    my $token = consume_keyword($parser, 'exists');

    my $expression = Expression($parser);

    if (not $expression) {
        expected($parser, "expression after `exists` keyword");
    }

    return [INSTR_EXISTS, $expression, token_position($token)];
}

# KeywordDelete ::= "delete" Expression
sub KeywordDelete($parser) {
    my $token = consume_keyword($parser, 'delete');

    my $expression = Expression($parser);

    if (not $expression) {
        expected($parser, "expression after `delete` keyword");
    }

    return [INSTR_DELETE, $expression, token_position($token)];
}

# KeywordKeys ::= "keys" Expression
sub KeywordKeys($parser) {
    my $token = consume_keyword($parser, 'keys');

    my $expression = Expression($parser);

    if (not $expression) {
        expected($parser, "expression after `keys` keyword");
    }

    return [INSTR_KEYS, $expression, token_position($token)];
}

# KeywordValues ::= "values" Expression
sub KeywordValues($parser) {
    my $token = consume_keyword($parser, 'values');

    my $expression = Expression($parser);

    if (not $expression) {
        expected($parser, "expression after `values` keyword");
    }

    return [INSTR_VALUES, $expression, token_position($token)];
}

# KeywordTry ::= try Expression {catch ["(" Expression ")"] Expression}+
sub KeywordTry($parser) {
    my $try_token = consume_keyword($parser, 'try');

    my $expr = Expression($parser);

    if (not $expr) {
        expected($parser, "expression for body of `try`");
    }

    my @catchers;

    while (my $catch_token = consume_keyword($parser, 'catch')) {
        my $catch_cond;
        my $catch_body;

        # check for a catch condition
        if ($parser->consume(TOKEN_L_PAREN)) {
            $catch_cond = Expression($parser);

            if (not $catch_cond) {
                expected($parser, "expression for `catch` condition");
            }

            if (not $parser->consume(TOKEN_R_PAREN)) {
                expected($parser, "closing ) for `catch` condition");
            }
        }

        $catch_body = Expression($parser);

        if (not $catch_body) {
            expected($parser, "expression for `catch` body");
        }

        push @catchers, [$catch_cond, $catch_body, token_position($catch_token)];
    }

    if (not @catchers) {
        expected($parser, "`catch` expression after `try`");
    }

    return [INSTR_TRY, $expr, \@catchers, token_position($try_token)];
}

# error about a `catch` without a `try`
sub CatchWithoutTry($parser) {
    # if a `catch` is consumed outside of KeywordTry() then it is a stray `catch`
    if (consume_keyword($parser, 'catch')) {
        error($parser, "cannot use `catch` outside of `try`");
    }

    return;
}

# KeywordThrow ::= "throw" Expression
sub KeywordThrow($parser) {
    my $token = consume_keyword($parser, 'throw');

    my $expr = Expression($parser);

    if (not $expr) {
        expected($parser, "expression after `throw`");
    }

    return [INSTR_THROW, $expr, token_position($token)];
}

# KeywordVar ::= "var" IDENT [":" Type] [Initializer]
sub KeywordVar($parser) {
    my $var_token = consume_keyword($parser, 'var');

    my $ident_token = $parser->consume(TOKEN_IDENT);

    if (not $ident_token) {
        expected($parser, 'identifier for variable');
    }

    my $name = $ident_token->[1];

    my $type;

    if ($parser->consume(TOKEN_COLON)) {
        $type = Type($parser);

        if (not $type) {
            expected($parser, "type after \":\" for variable `$name`");
        }
    }

    $type //= ['TYPE', 'Any'];

    my $initializer = Initializer($parser);

    return [INSTR_VAR, $type, $name, $initializer, token_position($var_token)];
}

# KeywordType ::= "type" IDENT [":" Type] [Initializer]
sub KeywordType($parser) {
    my $type_token = consume_keyword($parser, 'type');

    my $ident_token = $parser->consume(TOKEN_IDENT);

    if (not $ident_token) {
        expected($parser, 'identifier for new type');
    }

    my $name = $ident_token->[1];

    # check for duplicate type definition
    if ($parser->get_type($name)) {
        error($parser, "cannot redefine existing type `$name`");
    }

    # add type to parser's internal list of types
    $parser->add_type($name);

    my $type;

    if ($parser->consume(TOKEN_COLON)) {
        $type = Type($parser);

        if (not $type) {
            expected($parser, "type after \":\" for new type `$name`");
        }
    }

    $type //= ['TYPE', 'Any'];

    my $initializer = Initializer($parser);

    return [INSTR_TYPE, $type, $name, $initializer, token_position($type_token)];
}

# Initializer ::= "=" Expression
sub Initializer($parser) {
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

# Type         ::= TypeLiteral {"|" TypeLiteral}*
sub Type($parser) {
    $parser->try('Type');

    my $type = TypeLiteral($parser) // goto TYPE_FAIL;

    my $typeunion = [];

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

# TypeLiteral  ::= TypeMap | TypeArray | TypeFunction | TYPE
sub TypeLiteral($parser) {
    my $type;

    $type = TypeMap($parser);
    return $type if $type;

    $type = TypeArray($parser);
    return $type if $type;

    $type = TypeFunction($parser);
    return $type if $type;

    if (my $token = $parser->consume(TOKEN_TYPE)) {
        my $type = $token->[1];
        return ['TYPE', $type, undef, token_position($token)];
    }

    return;
}

# TypeMap ::= "{" {(String | IDENT) ":" Type [","]}* "}"
sub TypeMap($parser) {
    $parser->try('TypeMap');

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

                my $type;

                if ($parser->consume(TOKEN_COLON)) {
                    $type = Type($parser);

                    if (not $type) {
                        expected($parser, 'type after ":" for map entry');
                    }
                }

                my $initializer = Initializer($parser);

                if (!defined $type && !defined $initializer) {
                    expected($parser, '": <type>" or "= <default value>" after map key');
                }

                $type //= ['TYPE', 'Any'];

                $parser->consume(TOKEN_COMMA);

                push @map, [$mapkey->[1], $type, $initializer];
                next;
            }

            last if $parser->consume(TOKEN_R_BRACE);
            expected($parser, 'map entry or `}` in map type');
        }

        $parser->advance;
        return ['TYPEMAP', \@map, token_position($token)];
    }

    $parser->backtrack;
}

# TypeArray ::= "[" Type "]"
sub TypeArray($parser) {
    $parser->try('TypeArray');

    if (my $token = $parser->consume(TOKEN_L_BRACKET)) {
        my $type = Type($parser);

        if (not $type) {
            expected($parser, 'type of elements for array type');
        }

        if (not $parser->consume(TOKEN_R_BRACKET)) {
            expected($parser, 'closing "]" for array type');
        }

        $parser->advance;
        return ['TYPEARRAY', $type, token_position($token)];
    }

    $parser->backtrack;
}

# TypeFunction ::= (TYPE_Function | TYPE_Builtin) [TypeFunctionParams] [TypeFunctionReturn]
sub TypeFunction($parser) {
    my $token = $parser->next_token('peek') // return;

    my $kind = $token->[1];

    if (defined $kind and ($kind eq 'Function' or  $kind eq 'Builtin')) {
        $parser->consume;

        my $params = TypeFunctionParams($parser) // [];

        my $return_type = TypeFunctionReturn($parser) // ['TYPE', 'Any'];

        return ['TYPEFUNC', $kind, $params, $return_type, token_position($token)];
    }

    return;
}

# TypeFunctionParams ::= "(" {Type [","]}* ")"
sub TypeFunctionParams($parser) {
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

# TypeFunctionReturn ::= "->" TypeLiteral
sub TypeFunctionReturn($parser) {
    if ($parser->consume(TOKEN_R_ARROW)) {
        my $type = TypeLiteral($parser);

        if (not $type) {
            expected($parser, 'function return type');
        }

        return $type;
    }

    return;
}

# KeywordFn ::= "fn" [IDENT] [IdentifierList] ["->" Type] Expression
sub KeywordFn($parser) {
    my $fn_token = consume_keyword($parser, 'fn');

    my $ident_token = $parser->consume(TOKEN_IDENT);
    my $name  = $ident_token ? $ident_token->[1] : '#anonymous';

    my $identlist = IdentifierList($parser) // [];

    my $return_type = TypeFunctionReturn($parser) // ['TYPE', 'Any'];

    my $expression = Expression($parser);

    if (not $expression) {
        expected($parser, "expression for body of function $name");
    }

    return [INSTR_FUNCDEF, $return_type, $name, $identlist, [$expression], token_position($fn_token)];
}

# IdentifierList ::= "(" {Identifier [":" Type] [Initializer] [","]}* ")"
sub IdentifierList($parser) {
    $parser->try('IdentifierList');

    $parser->consume(TOKEN_L_PAREN) // goto IDENTLIST_FAIL;

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

# MapConstructor ::= "{" {(String | IDENT) "=" Expression [","]}* "}"
#         String ::= DQUOTE_STRING | SQUOTE_STRING
sub MapConstructor($parser) {
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
                    $mapkey = [INSTR_LITERAL, ['TYPE', 'String'], $parsedkey->[1], token_position($parsedkey)];
                } elsif ($parsedkey->[0] == TOKEN_SQUOTE_STRING) {
                    $parsedkey->[1] =~ s/^'|'$//g;
                    $mapkey = [INSTR_LITERAL, ['TYPE', 'String'], $parsedkey->[1], token_position($parsedkey)];
                } else {
                    $mapkey = [INSTR_IDENT, $parsedkey->[1], token_position($parsedkey)];
                }

                if (not $parser->consume(TOKEN_ASSIGN)) {
                    goto MAPCONS_FAIL;
                }

                my $expr = Expression($parser);

                if (not $expr) {
                    goto MAPCONS_FAIL;
                }

                $parser->consume(TOKEN_COMMA);

                push @map, [$mapkey, $expr];
                next;
            }

            last if $parser->consume(TOKEN_R_BRACE);
            goto MAPCONS_FAIL;
        }

        $parser->advance;
        return [INSTR_MAPCONS, \@map, token_position($token)];
    }

  MAPCONS_FAIL:
    $parser->backtrack;
}

# ArrayConstructor ::= "[" {Expression [","]}* "]"
sub ArrayConstructor($parser) {
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
        return [INSTR_ARRAYCONS, \@array, token_position($token)];
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
    TOKEN_CARET_CARET_EQ, $precedence_table{'ASSIGNMENT'},
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
$binop_data[TOKEN_DOT]            = [INSTR_DOT_ACCESS, 'ACCESS',      ASSOC_LEFT];
$binop_data[TOKEN_STAR_STAR]      = [INSTR_POW,        'EXPONENT',    ASSOC_RIGHT];
$binop_data[TOKEN_CARET]          = [INSTR_POW,        'EXPONENT',    ASSOC_RIGHT];
$binop_data[TOKEN_PERCENT]        = [INSTR_REM,        'EXPONENT',    ASSOC_LEFT];
$binop_data[TOKEN_STAR]           = [INSTR_MUL,        'PRODUCT',     ASSOC_LEFT];
$binop_data[TOKEN_SLASH]          = [INSTR_DIV,        'PRODUCT',     ASSOC_LEFT];
$binop_data[TOKEN_PLUS]           = [INSTR_ADD,        'SUM',         ASSOC_LEFT];
$binop_data[TOKEN_MINUS]          = [INSTR_SUB,        'SUM',         ASSOC_LEFT];
$binop_data[TOKEN_TILDE]          = [INSTR_STRIDX,     'STRING',      ASSOC_LEFT];
$binop_data[TOKEN_CARET_CARET]    = [INSTR_STRCAT,     'STRING',      ASSOC_LEFT];
$binop_data[TOKEN_GREATER_EQ]     = [INSTR_GTE,        'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_LESS_EQ]        = [INSTR_LTE,        'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_GREATER]        = [INSTR_GT,         'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_LESS]           = [INSTR_LT,         'RELATIONAL',  ASSOC_LEFT];
$binop_data[TOKEN_NOT_EQ]         = [INSTR_NEQ,        'EQUALITY',    ASSOC_LEFT];
$binop_data[TOKEN_AMP_AMP]        = [INSTR_AND,        'LOGICAL_AND', ASSOC_LEFT];
$binop_data[TOKEN_PIPE_PIPE]      = [INSTR_OR,         'LOGICAL_OR',  ASSOC_LEFT];
$binop_data[TOKEN_EQ]             = [INSTR_EQ,         'EQUALITY',    ASSOC_LEFT];
$binop_data[TOKEN_ASSIGN]         = [INSTR_ASSIGN,     'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_PLUS_EQ]        = [INSTR_ADD_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_MINUS_EQ]       = [INSTR_SUB_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_STAR_EQ]        = [INSTR_MUL_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_SLASH_EQ]       = [INSTR_DIV_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_CARET_CARET_EQ] = [INSTR_CAT_ASSIGN, 'ASSIGNMENT',  ASSOC_RIGHT];
$binop_data[TOKEN_DOT_DOT]        = [INSTR_RANGE,      'COMMA',       ASSOC_RIGHT];
$binop_data[TOKEN_AND]            = [INSTR_AND,        'LOW_AND',     ASSOC_LEFT];
$binop_data[TOKEN_OR]             = [INSTR_OR,         'LOW_OR',      ASSOC_LEFT];

sub get_precedence($tokentype) {
    return $infix_token_precedence{$tokentype} // 0;
}

# UnaryOp ::= Op Expression
# Op      ::= "!" | "-" | "+" | ? etc ?
sub UnaryOp($parser, $op, $ins) {
    if (my $token = $parser->consume($op)) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return $expr ? [$ins, $expr, token_position($token)] : expected($parser, "expression after unary operator `" . $pretty_token[$op] . "`");
    }
}

# BinaryOp ::= Expression BinOp Expression
# BinOp    ::= "-" | "+" | "/" | "*" | "%" | ">" | ">=" | "<" | "<=" | "==" | "&&" | ? etc ?
sub BinaryOp($parser, $left, $op, $ins, $precedence, $right_associative) {
    if (my $token = $parser->consume($op)) {
        my $right = Expression($parser, $precedence_table{$precedence} - $right_associative);
        return $right ? [$ins, $left, $right, token_position($token)] : expected($parser, "expression after binary operator `" . $pretty_token[$op] . "`");
    }
}

# ExpressionGroup ::= "{" {Expression}* "}"
sub ExpressionGroup($parser) {
    $parser->try('ExpressionGroup: L_BRACE Expression R_BRACE');

    my $token = $parser->consume(TOKEN_L_BRACE) // goto EXPRESSION_GROUP_FAIL;

    my @expressions;

    while (1) {
        my $expression = Expression($parser);

        if ($expression) {
            push @expressions, $expression unless $expression->[0] == INSTR_NOP;
            next;
        }

        last if $parser->consume(TOKEN_R_BRACE);
        expected($parser, 'terminating } for expression');
    }

    $parser->advance;
    return [INSTR_EXPR_GROUP, \@expressions, token_position($token)];

  EXPRESSION_GROUP_FAIL:
    $parser->backtrack;
}

# Expression ::= ExpressionGroup | UnaryOp | BinaryOp | Identifier | KeywordNull .. KeywordThrow | LiteralInteger .. LiteralFloat | ? etc ?
sub Expression($parser, $precedence = 0) {
    $parser->try("Expression (prec $precedence)");

    if ($parser->consume(TOKEN_TERM)) {
        $parser->advance;
        return [INSTR_NOP, undef];
    }

    my $left = Prefix($parser, $precedence) // goto EXPRESSION_FAIL;

    while (1) {
        my $token = $parser->next_token('peek') // last;
        my $token_precedence = get_precedence $token->[0];
        last if $precedence >= $token_precedence;
        $left = Infix($parser, $left, $token_precedence);
    }

    $parser->advance;
    return $left;

  EXPRESSION_FAIL:
    $parser->backtrack;
}

# Identifier ::= ["_" | "a" .. "z" | "A" .. "Z"] {"_" | "a" .. "z" | "A" .. "Z" | "0" .. "9"}*
sub Identifier($parser) {
    my $token = $parser->consume(TOKEN_IDENT);
    return [INSTR_IDENT, $token->[1], token_position($token)];
}

# LiteralInteger ::= {"0" .. "9"}+
sub LiteralInteger($parser) {
    my $token = $parser->consume(TOKEN_INT);

    if ($token->[1] =~ /^0/) {
        $token->[1] = oct $token->[1];
    }

    return [INSTR_LITERAL, ['TYPE', 'Integer'], $token->[1] + 0, token_position($token)];
}

# LiteralFloat ::= {"0" .. "9"}* ("." {"0" .. "9"}* ("e" | "E") ["+" | "-"] {"0" .. "9"}+ | "." {"0" .. "9"}+ | ("e" | "E") ["+" | "-"] {"0" .. "9"}+)
sub LiteralFloat($parser) {
    my $token = $parser->consume(TOKEN_FLT);
    return [INSTR_LITERAL, ['TYPE', 'Real'], $token->[1] + 0, token_position($token)];
}

# LiteralHexInteger ::= "0" ("x" | "X") {"0" .. "9" | "a" .. "f" | "A" .. "F"}+
sub LiteralHexInteger($parser) {
    my $token = $parser->consume(TOKEN_HEX);
    return [INSTR_LITERAL, ['TYPE', 'Integer'], hex $token->[1], token_position($token)];
}

sub PrefixLBrace($parser) {
    my $expr = MapConstructor($parser);
    return $expr if defined $expr;

    $expr = ExpressionGroup($parser);
    return $expr if defined $expr;

    error($parser, "Unhandled { token");
}

sub PrefixSquoteStringI($parser) {
    my $token = $parser->consume(TOKEN_SQUOTE_STRING_I);
    $token->[1] =~ s/^\$//;
    $token->[1] =~ s/^\'|\'$//g;
    return [INSTR_STRING_I, $token->[1], token_position($token)];
}

sub expand_escapes($string) {
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

sub PrefixDquoteStringI($parser) {
    my $token = $parser->consume(TOKEN_DQUOTE_STRING_I);
    $token->[1] =~ s/^\$//;
    $token->[1] =~ s/^\"|\"$//g;
    return [INSTR_STRING_I, expand_escapes($token->[1]), token_position($token)];
}

sub PrefixSquoteString($parser) {
    my $token = $parser->consume(TOKEN_SQUOTE_STRING);
    $token->[1] =~ s/^\'|\'$//g;
    return [INSTR_LITERAL, ['TYPE', 'String'], expand_escapes($token->[1]), token_position($token)];
}

sub PrefixDquoteString($parser) {
    my $token = $parser->consume(TOKEN_DQUOTE_STRING);
    $token->[1] =~ s/^\"|\"$//g;
    return [INSTR_LITERAL, ['TYPE', 'String'], expand_escapes($token->[1]), token_position($token)];
}

sub PrefixMinusMinus($parser) {
    my $token = $parser->consume(TOKEN_MINUS_MINUS);
    my $expr = Expression($parser, $precedence_table{'PREFIX'});
    expected($parser, 'expression after prefix `--`') if not defined $expr;
    return [INSTR_PREFIX_SUB, $expr, token_position($token)];
}

sub PrefixPlusPlus($parser) {
    my $token = $parser->consume(TOKEN_PLUS_PLUS);
    my $expr = Expression($parser, $precedence_table{'PREFIX'});
    expected($parser, 'expression after prefix `++`') if not defined $expr;
    return [INSTR_PREFIX_ADD, $expr, token_position($token)];
}

sub PrefixBang($parser) {
    return UnaryOp($parser, TOKEN_BANG, INSTR_NOT);
}

sub PrefixMinus($parser) {
    return UnaryOp($parser, TOKEN_MINUS, INSTR_NEG);
}

sub PrefixPlus($parser) {
    return UnaryOp($parser, TOKEN_PLUS,  INSTR_POS);
}

sub PrefixNot($parser) {
    return UnaryOp($parser, TOKEN_NOT,   INSTR_NOT);
}

sub PrefixLParen($parser) {
    my $token = $parser->consume(TOKEN_L_PAREN);
    my $expr = Expression($parser);
    expected($parser, '")"') if not $parser->consume(TOKEN_R_PAREN);
    return [INSTR_EXPR_GROUP, [$expr], token_position($token)];
}

sub PrefixType($parser) {
    my $token = $parser->consume(TOKEN_TYPE);
    # convert to identifier to invoke builtin function for type conversion
    return [INSTR_IDENT, $token->[1], token_position($token)];
}

my @prefix_dispatcher;
$prefix_dispatcher[TOKEN_KEYWORD]         = \&Keyword;
$prefix_dispatcher[TOKEN_L_BRACE]         = \&PrefixLBrace;
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

sub Prefix($parser, $precedence) {
    $parser->try("Prefix");

    # peek at upcoming token
    my $token = $parser->next_token('peek') // return;

    # get token's dispatcher
    my $dispatcher = $prefix_dispatcher[$token->[0]];

    # attempt to dispatch token
    if (defined $dispatcher) {
        my $result = $dispatcher->($parser);

        if (defined $result) {
            $parser->advance;
            return $result;
        }
    }

    # no dispatch for token, handle edge cases

    # throw exception on unexpected keyword
    UnexpectedKeyword($parser);

    $parser->advance;
    return;
}

sub InfixConditionalOperator($parser, $left) {
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

sub Infix($parser, $left, $precedence) {
    $parser->try("Infix");
    # peek at upcoming token
    my $token = $parser->next_token('peek') // return;

    # get token's binop data
    my $data = $binop_data[$token->[0]];

    # attempt to dispatch token
    if (defined $data) {
        my $result = BinaryOp($parser, $left, $token->[0], $data->[0], $data->[1], $data->[2]);

        if (defined $result) {
            $parser->advance;
            return $result;
        }
    }

    # no dispatch for token, handle edge cases

    $data = InfixConditionalOperator($parser, $left);

    if (defined $data) {
        $parser->advance;
        return $data;
    }

    my $post = Postfix($parser, $left, $precedence);
    $parser->advance;
    return $post;
}

sub PostfixPlusPlus($parser, $left) {
    my $token = $parser->consume(TOKEN_PLUS_PLUS);
    return [INSTR_POSTFIX_ADD, $left, token_position($token)];
}

sub PostfixMinusMinus($parser, $left) {
    my $token = $parser->consume(TOKEN_MINUS_MINUS);
    return [INSTR_POSTFIX_SUB, $left, token_position($token)];
}

sub PostfixLParen($parser, $left) {
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

sub PostfixLBracket($parser, $left) {
    my $token = $parser->consume(TOKEN_L_BRACKET);

    my $expression = Expression($parser);

    if (not $expression) {
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

sub Postfix($parser, $left, $precedence) {
    $parser->try("Postfix");
    # peek at upcoming token
    my $token = $parser->next_token('peek') // return;

    # get token's dispatcher
    my $dispatcher = $postfix_dispatcher[$token->[0]];

    # attempt to dispatch token
    if (defined $dispatcher) {
        my $result = $dispatcher->($parser, $left);

        if (defined $result) {
            $parser->advance;
            return $result;
        }
    }

    # no postfix
    $parser->advance;
    return $left;
}

1;
