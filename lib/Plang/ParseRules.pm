#!/usr/bin/env perl

# Recursive descent rules to parse a Plang program using
# the Plang::Parser class.
#
# Program() is the start-rule.

package Plang::ParseRules;

use warnings;
use strict;

use base 'Exporter';
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
    TOKEN_TERM,  'statement terminator',
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

sub alternate_statement {
    my ($parser, $subref, $debug_msg) = @_;

    $parser->alternate($debug_msg);

    {
        my $result = $subref->($parser);

        if ($result) {
            $parser->consume(TOKEN_TERM);
            $parser->advance;
            return [INSTR_STMT, $result];
        }
    }
}

sub consume_keyword {
    my ($parser, $keyword) = @_;

    my $token = $parser->next_token('peek');

    if ($token->[0] == TOKEN_KEYWORD && $token->[1] eq $keyword) {
        $parser->consume(TOKEN_KEYWORD);
        return $token;
    }

    return;
}

# start-rule:
# Program ::= Statement*
sub Program {
    my ($parser) = @_;

    $parser->try('Program: Statement*');
    my @statements;

    my $MAX_ERRORS = 3; # TODO make this customizable
    my $errors;

    while (defined $parser->next_token('peek')) {
        eval {
            my $statement = Statement($parser);

            if ($statement and $statement->[0] != INSTR_NOP) {
                push @statements, $statement;
            }
        };

        if ($@) {
            last if ++$errors > $MAX_ERRORS;
            next;
        }
    }

    $parser->advance;
    return @statements ? ['PRGM', \@statements] : undef;
}

my @statement_dispatcher;
$statement_dispatcher[TOKEN_L_BRACE] = \&StatementGroup;
#$statement_dispatcher[TOKEN_KEYWORD] = \&StatementKeyword;

# Statement ::= StatementGroup
#             | VariableDeclaration
#             | FunctionDefinition
#             | ReturnStatement
#             | NextStatement
#             | LastStatement
#             | WhileStatement
#             | IfExpression
#             | ElseWithoutIf
#             | ExistsExpression
#             | DeleteExpression
#             | KeysExpression
#             | ValuesExpression
#             | Expression TERM
#             | UnexpectedKeyword
#             | TERM
sub Statement {
    my ($parser) = @_;

    $parser->try('Statement: ...');

    # peek at upcoming token
    my $token = $parser->next_token('peek');
    return if not defined $token;

    # get token's dispatcher
    my $dispatcher = $statement_dispatcher[$token->[0]];

    # attempt to dispatch token
    if (defined $dispatcher) {
        my $result = $dispatcher->($parser);
        return $result if defined $result;
    }

    # no dispatch for token, handle edge cases

    my $result;
    return $result if defined ($result = alternate_statement($parser, \&Expression,        'Statement: Expression'));
    return $result if defined ($result = alternate_statement($parser, \&UnexpectedKeyword, 'Statement: UnexpectedKeyword'));

    $parser->alternate('Statement: TERM');

    {
        if ($parser->consume(TOKEN_TERM)) {
            $parser->advance;
            return [INSTR_NOP, undef];
        }
    }

    $parser->backtrack;
    return;
}

# StatementGroup ::= L_BRACE Statement* R_BRACE
sub StatementGroup {
    my ($parser) = @_;

    $parser->try('StatementGroup: L_BRACE Statement R_BRACE');

    {
        goto STATEMENT_GROUP_FAIL if not $parser->consume(TOKEN_L_BRACE);

        my @statements;

        while (1) {
            my $statement = Statement($parser);

            if ($statement and $statement->[0] != INSTR_NOP) {
                push @statements, $statement;
                next;
            }

            last if $parser->consume(TOKEN_R_BRACE);
            goto STATEMENT_GROUP_FAIL;
        }

        $parser->advance;
        return [INSTR_STMT_GROUP, \@statements];
    }

  STATEMENT_GROUP_FAIL:
    $parser->backtrack;
}

my @keyword_dispatcher;
$keyword_dispatcher[KEYWORD_VAR]    = \&VariableDeclaration;
$keyword_dispatcher[KEYWORD_FN]     = \&FunctionDefinition;
$keyword_dispatcher[KEYWORD_RETURN] = \&ReturnStatement;
$keyword_dispatcher[KEYWORD_NEXT]   = \&NextStatement;
$keyword_dispatcher[KEYWORD_LAST]   = \&LastStatement;
$keyword_dispatcher[KEYWORD_WHILE]  = \&WhileStatement;
$keyword_dispatcher[KEYWORD_IF]     = \&IfExpression;
$keyword_dispatcher[KEYWORD_ELSE]   = \&ElseWithoutIf;
$keyword_dispatcher[KEYWORD_EXISTS] = \&ExistsStatement;
$keyword_dispatcher[KEYWORD_DELETE] = \&DeleteExpression;
$keyword_dispatcher[KEYWORD_KEYS]   = \&KeysExpression;
$keyword_dispatcher[KEYWORD_VALUES] = \&ValuesExpression;
$keyword_dispatcher[KEYWORD_NULL]   = \&KeywordNull;
$keyword_dispatcher[KEYWORD_TRUE]   = \&KeywordTrue;
$keyword_dispatcher[KEYWORD_FALSE]  = \&KeywordFalse;

sub StatementKeyword {
    my ($parser) = @_;

    $parser->try('StatementKeyword');

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
            return [INSTR_STMT, $result];
        }
    }

    error($parser, "Unknown keyword `$token->[1]`");
}

sub KeywordNull {
    my ($parser) = @_;

    $parser->try('KeywordNull');

    {

        if (consume_keyword($parser, 'null')) {
            return [['TYPE', 'Null'], undef];
        }

    }

    $parser->backtrack;

    return;
}

sub KeywordTrue {
    my ($parser) = @_;

    $parser->try('KeywordTrue');

    {

        if (consume_keyword($parser, 'true')) {
            return [['TYPE', 'Boolean'], 1];
        }

    }

    $parser->backtrack;

    return;
}

sub KeywordFalse {
    my ($parser) = @_;

    $parser->try('KeywordFalse');

    {

        if (consume_keyword($parser, 'false')) {
            return [['TYPE', 'Boolean'], 0];
        }

    }

    $parser->backtrack;

    return;
}

# VariableDeclaration ::= KEYWORD_var IDENT (":" Type)? Initializer?
sub VariableDeclaration {
    my ($parser) = @_;

    $parser->try('VariableDeclaration');

    {

        if (consume_keyword($parser, 'var')) {
            my $token = $parser->consume(TOKEN_IDENT);

            if (not $token) {
                expected($parser, 'identifier for variable name');
            }

            my $name = $token->[1];

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

            $parser->advance;
            return [INSTR_VAR, $type, $name, $initializer];
        }
    }

    $parser->backtrack;
}

# MapConstructor ::= "{" ((String | IDENT) ":" Expression ","?)* "}"
#         String ::= DQUOTE_STRING | SQUOTE_STRING
sub MapConstructor {
    my ($parser) = @_;

    $parser->try('MapConstructor');

    {
        if ($parser->consume(TOKEN_L_BRACE)) {
            my @map;
            while (1) {
                my $parsedkey = $parser->consume(TOKEN_DQUOTE_STRING)
                             || $parser->consume(TOKEN_SQUOTE_STRING)
                             || $parser->consume(TOKEN_IDENT);

                if ($parsedkey) {
                    my $mapkey;

                    if ($parsedkey->[0] == TOKEN_DQUOTE_STRING) {
                        $parsedkey->[1] =~ s/^"|"$//g;
                        $mapkey = [['TYPE', 'String'], $parsedkey->[1]];
                    } elsif ($parsedkey->[0] == TOKEN_SQUOTE_STRING) {
                        $parsedkey->[1] =~ s/^'|'$//g;
                        $mapkey = [['TYPE', 'String'], $parsedkey->[1]];
                    } else {
                        $mapkey = $parsedkey;
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
            return [INSTR_MAPINIT, \@map];
        }
    }

    $parser->backtrack;
}

# ArrayConstructor ::= "[" (Expression ","?)* "]"
sub ArrayConstructor {
    my ($parser) = @_;

    $parser->try('ArrayConstructor');

    {
        if ($parser->consume(TOKEN_L_BRACKET)) {
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
            return [INSTR_ARRAYINIT, \@array];
        }
    }

    $parser->backtrack;
}

# Initializer ::= ASSIGN Expression
sub Initializer {
    my ($parser) = @_;

    $parser->try('Initializer');

    {
        if ($parser->consume(TOKEN_ASSIGN)) {
            # try an expression
            my $expr = Expression($parser);

            if ($expr) {
                $parser->advance;
                return $expr;
            }

            expected($parser, 'expression for initializer');
        }
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

    {
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

        if (@$typeunion > 1) {
            my @sorted = sort { $a->[1] cmp $b->[1] } @$typeunion;
            return ['TYPEUNION', \@sorted];
        } else {
            return $type;
        }
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
        return ['TYPE', $type];
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

        return ['TYPEFUNC', $kind, $params, $return_type];
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

    my $token = $parser->next_token('peek');
    return if not $token;

    if ($token->[0] eq 'R_ARROW') {
        $parser->consume;
        my $type = TypeLiteral($parser);

        if (not $type) {
            expected($parser, 'function return type name');
        }

        return $type;
    }

    return;
}

# FunctionDefinition ::= KEYWORD_fn IDENT? IdentifierList? ("->" Type)? (StatementGroup | Statement)
sub FunctionDefinition {
    my ($parser) = @_;

    $parser->try('FunctionDefinition');

    {
        if (consume_keyword($parser, 'fn')) {
            my $token = $parser->consume(TOKEN_IDENT);
            my $name  = $token ? $token->[1] : '#anonymous';

            my $identlist = IdentifierList($parser);

            $identlist = [] if not defined $identlist;

            my $return_type;
            if ($parser->consume(TOKEN_R_ARROW)) {
                $return_type = Type($parser);
            }

            $return_type = ['TYPE', 'Any'] if not defined $return_type;

            $parser->try('FunctionDefinition body: StatementGroup');

            {
                my $statement_group = StatementGroup($parser);

                if ($statement_group) {
                    $parser->advance;
                    return [INSTR_FUNCDEF, $return_type, $name, $identlist, $statement_group->[1]];
                }
            }

            $parser->alternate('FunctionDefinition body: Statement');

            {
                my $statement = Statement($parser);

                if ($statement) {
                    $parser->advance;
                    return [INSTR_FUNCDEF, $return_type, $name, $identlist, [$statement]];
                }
            }

            expected($parser, "Statement or StatementGroup for body of function $name");
        }
    }

  FUNCDEF_FAIL:
    $parser->backtrack;
}

# IdentifierList ::= "(" (Identifier (":" Type)? Initializer? ","?)* ")"
sub IdentifierList {
    my ($parser) = @_;

    $parser->try('IdentifierList');

    {
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

                $type = ['TYPE', 'Any'] if not $type;

                my $initializer = Initializer($parser);
                push @{$identlist}, [$type, $name, $initializer];
                $parser->consume(TOKEN_COMMA);
                next;
            }

            last if $parser->consume(TOKEN_R_PAREN);
            goto IDENTLIST_FAIL;
        }

        $parser->advance;
        return $identlist;
    }

  IDENTLIST_FAIL:
    $parser->backtrack;
}

# ReturnStatement ::= KEYWORD_return Statement
sub ReturnStatement {
    my ($parser) = @_;

    $parser->try('ReturnStatement');

    {
        if (consume_keyword($parser, 'return')) {
            my $statement = Statement($parser);
            $parser->advance;
            return [INSTR_RET, $statement];
        }
    }

    $parser->backtrack;
}

# NextStatement ::= KEYWORD_next
sub NextStatement {
    my ($parser) = @_;

    $parser->try('NextStatement');

    {
        if (consume_keyword($parser, 'next')) {
            $parser->advance;
            return [INSTR_NEXT, undef];
        }
    }

    $parser->backtrack;
}

# LastStatement ::= KEYWORD_last
sub LastStatement {
    my ($parser) = @_;

    $parser->try('LastStatement');

    {
        if (consume_keyword($parser, 'last')) {
            $parser->advance;
            return [INSTR_LAST, undef];
        }
    }

    $parser->backtrack;
}

# WhileStatement ::= KEYWORD_while "(" Expression ")" Statement
sub WhileStatement {
    my ($parser) = @_;

    $parser->try('WhileStatement');

    {
        if (consume_keyword($parser, 'while')) {
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

            my $body = Statement($parser);

            if (not $body) {
                expected($parser, "statement body for `while` loop");
            }

            $parser->advance;
            return [INSTR_WHILE, $expr, $body];
        }
    }

    $parser->backtrack;
}

# IfExpression ::= KEYWORD_if Expression KEYWORD_then Statement KEYWORD_else Statement
sub IfExpression {
    my ($parser) = @_;

    $parser->try('IfExpression');

    {
        if (consume_keyword($parser, 'if')) {
            my $expr = Expression($parser);

            if (not $expr) {
                expected($parser, "expression for `if` condition");
            }

            if (not consume_keyword($parser, 'then')) {
                expected($parser, "`then` after `if` condition expression");
            }

            my $body = Statement($parser);

            if (not $body) {
                expected($parser, "statement body for `if` statement");
            }

            if (not consume_keyword($parser, 'else')) {
                expected($parser, "`else` branch for `if` condition expression");
            }

            my $else = Statement($parser);

            if (not $else) {
                expected($parser, "statement body for `else` branch of `if` condition expression");
            }

            $parser->advance;
            return [INSTR_IF, $expr, $body, $else];
        }
    }

    $parser->backtrack;
}

# error about an `else` without an `if`
sub ElseWithoutIf {
    my ($parser) = @_;

    if (consume_keyword($parser, 'else')) {
        error($parser, "`else` without matching `if`");
    }

    return;
}

# ExistsStatement ::= KEYWORD_exists Statement
sub ExistsStatement {
    my ($parser) = @_;

    $parser->try('ExistsStatement');

    {
        if (consume_keyword($parser, 'exists')) {
            my $map = MapConstructor($parser);
            return [INSTR_EXISTS, $map] if $map;

            my $statement = Statement($parser);

            if (not $statement or not defined $statement->[1]) {
                expected($parser, "statement after exists keyword");
            }

            $parser->advance;
            return [INSTR_EXISTS, $statement->[1]];
        }
    }

    $parser->backtrack;
}

# DeleteExpression ::= KEYWORD_delete Statement
sub DeleteExpression {
    my ($parser) = @_;

    $parser->try('DeleteExpression');

    {
        if (consume_keyword($parser, 'delete')) {
            my $map = MapConstructor($parser);
            return [INSTR_DELETE, $map] if $map;

            my $statement = Statement($parser);

            if (not $statement or not defined $statement->[1]) {
                expected($parser, "statement after delete keyword");
            }

            $parser->advance;
            return [INSTR_DELETE, $statement->[1]];
        }
    }

    $parser->backtrack;
}

# KeysExpression ::= KEYWORD_keys Statement
sub KeysExpression {
    my ($parser) = @_;

    $parser->try('KeysExpression');

    {
        if (consume_keyword($parser, 'keys')) {
            my $map = MapConstructor($parser);
            return [INSTR_KEYS, $map] if $map;

            my $statement = Statement($parser);

            if (not $statement or not defined $statement->[1]) {
                expected($parser, "statement after keys keyword");
            }

            $parser->advance;
            return [INSTR_KEYS, $statement->[1]];
        }
    }

    $parser->backtrack;
}

# ValuesExpression ::= KEYWORD_values Statement
sub ValuesExpression {
    my ($parser) = @_;

    $parser->try('ValuesExpression');

    {
        if (consume_keyword($parser, 'values')) {
            my $map = MapConstructor($parser);
            return [INSTR_VALUES, $map] if $map;

            my $statement = Statement($parser);

            if (not $statement or not defined $statement->[1]) {
                expected($parser, "statement after values keyword");
            }

            $parser->advance;
            return [INSTR_VALUES, $statement->[1]];
        }
    }

    $parser->backtrack;
}

# error about unexpected keywords
sub UnexpectedKeyword {
    my ($parser) = @_;

    my $token = $parser->next_token('peek');
    return if not $token;

    if ($token->[0] == TOKEN_KEYWORD) {
        error($parser, "unexpected keyword `$token->[1]`");
    }

    return;
}

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
$binop_data[TOKEN_AND]         = [INSTR_AND,        'LOW_AND',     ASSOC_LEFT];
$binop_data[TOKEN_OR]          = [INSTR_OR,         'LOW_OR',      ASSOC_LEFT];

sub get_precedence {
    my ($tokentype) = @_;
    return $infix_token_precedence{$tokentype} // 0;
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

sub Expression {
    my ($parser, $precedence) = @_;

    $precedence ||= 0;

    $parser->try("Expression (prec $precedence)");

    {
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
    return [INSTR_IDENT, $token->[1]];
}

sub LiteralInteger {
    my ($parser) = @_;

    my $token = $parser->consume(TOKEN_INT);

    if ($token->[1] =~ /^0/) {
        $token->[1] = oct $token->[1];
    }

    return [INSTR_LITERAL, ['TYPE', 'Integer'], $token->[1] + 0];
}

sub LiteralFloat {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_FLT);
    return [INSTR_LITERAL, ['TYPE', 'Real'], $token->[1] + 0];
}

sub LiteralHex {
    my ($parser) = @_;
    my $token = $parser->consume(TOKEN_HEX);
    return [INSTR_LITERAL, ['TYPE', 'Number'], hex $token->[1]];
}

my @prefix_dispatcher;
$prefix_dispatcher[TOKEN_KEYWORD]   = \&StatementKeyword;
$prefix_dispatcher[TOKEN_L_BRACE]   = \&MapConstructor;
$prefix_dispatcher[TOKEN_L_BRACKET] = \&ArrayConstructor;
$prefix_dispatcher[TOKEN_INT]       = \&LiteralInteger;
$prefix_dispatcher[TOKEN_FLT]       = \&LiteralFloat;
$prefix_dispatcher[TOKEN_HEX]       = \&LiteralHex;
$prefix_dispatcher[TOKEN_TYPE]      = \&Type;
$prefix_dispatcher[TOKEN_IDENT]     = \&Identifier;

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

    if ($token = $parser->consume(TOKEN_SQUOTE_STRING_I)) {
        $token->[1] =~ s/^\$//;
        $token->[1] =~ s/^\'|\'$//g;
        return [INSTR_STRING_I, $token->[1]];
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

    if ($token = $parser->consume(TOKEN_DQUOTE_STRING_I)) {
        $token->[1] =~ s/^\$//;
        $token->[1] =~ s/^\"|\"$//g;
        return [INSTR_STRING_I, expand_escapes($token->[1])];
    }

    if ($token = $parser->consume(TOKEN_SQUOTE_STRING)) {
        $token->[1] =~ s/^\'|\'$//g;
        return [INSTR_LITERAL, ['TYPE', 'String'], expand_escapes($token->[1])];
    }

    if ($token = $parser->consume(TOKEN_DQUOTE_STRING)) {
        $token->[1] =~ s/^\"|\"$//g;
        return [INSTR_LITERAL, ['TYPE', 'String'], expand_escapes($token->[1])];
    }

    if ($parser->consume(TOKEN_MINUS_MINUS)) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        expected($parser, 'Expression') if not defined $expr;
        return [INSTR_PREFIX_SUB, $expr];
    }

    if ($parser->consume(TOKEN_PLUS_PLUS)) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        expected($parser, 'Expression') if not defined $expr;
        return [INSTR_PREFIX_ADD, $expr];
    }

    my $expr;
    return $expr if $expr = UnaryOp($parser, TOKEN_BANG,  INSTR_NOT);
    return $expr if $expr = UnaryOp($parser, TOKEN_MINUS, INSTR_NEG);
    return $expr if $expr = UnaryOp($parser, TOKEN_PLUS,  INSTR_POS);
    return $expr if $expr = UnaryOp($parser, TOKEN_NOT,   INSTR_NOT);

    if ($token = $parser->consume(TOKEN_L_PAREN)) {
        my $expr = Expression($parser);
        expected($parser, '")"') if not $parser->consume(TOKEN_R_PAREN);
        return $expr;
    }

    return;
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

    if ($token->[0] == TOKEN_QUESTION) {
        $parser->consume;

        my $then = Statement($parser);

        if (not $then) {
            expected($parser, '<then> statement in conditional <if> ? <then> : <else> operator');
        }

        if (not $parser->consume(TOKEN_COLON)) {
            expected($parser, '":" after <then> statement in conditional <if> ? <then> : <else> operator');
        }

        my $else = Statement($parser);

        if (not $else) {
            expected($parser, '<else> statement in conditional <if> ? <then> : <else> operator');
        }

        return [INSTR_COND, $left, $then, $else];
    }

    return Postfix($parser, $left, $precedence);
}

sub Postfix {
    my ($parser, $left, $precedence) = @_;

    # post-increment
    if ($parser->consume(TOKEN_PLUS_PLUS)) {
        return [INSTR_POSTFIX_ADD, $left];
    }

    # post-decrement
    if ($parser->consume(TOKEN_MINUS_MINUS)) {
        return [INSTR_POSTFIX_SUB, $left];
    }

    # function call
    if ($parser->consume(TOKEN_L_PAREN)) {
        my $arguments = [];
        while (1) {
            my $expr = Expression($parser);

            if ($expr) {
                push @{$arguments}, $expr;
                $parser->consume(TOKEN_COMMA);
                next;
            }

            last if $parser->consume(TOKEN_R_PAREN);
            expected($parser, 'expression or closing ")" for function call argument list');
        }

        return [INSTR_CALL, $left, $arguments];
    }

    # array/map access
    if ($parser->consume(TOKEN_L_BRACKET)) {
        my $stmt = Statement($parser);

        if (not $stmt or not defined $stmt->[1]) {
            expected($parser, 'statement in postfix [] brackets');
        }

        if (not $parser->consume(TOKEN_R_BRACKET)) {
            expected($parser, 'closing ] bracket');
        }

        return [INSTR_ACCESS, $left, $stmt];
    }

    # no postfix
    return $left;
}

1;
