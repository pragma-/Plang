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
    'TERM'  => 'statement terminator',
    'IDENT' => 'identifier',
);

sub pretty_token {
    my ($token) = @_;
    return 'keyword' if $token =~ /^KEYWORD_/;
    return 'type'    if $token =~ /^TYPE_/;
    return $pretty_tokens{$token} // $token;
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

# Grammar: Program ::= Statement+
sub Program {
    my ($parser) = @_;

    $parser->try('Program: Statement+');
    my @statements;

    my $MAX_ERRORS = 3; # TODO make this customizable
    my $errors;
    my $failed = 0;
    while (defined $parser->next_token('peek')) {
        $parser->clear_error;

        my $statement = Statement($parser);

        if ($parser->errored) {
            last if ++$errors > $MAX_ERRORS;
            next;
        }

        if (not $statement or $statement->[0] eq 'NOP') {
            if (++$failed >= 2) {
                my $token = $parser->current_or_last_token;
                if (defined $token) {
                    my $name = pretty_token($token->[0]) . ' (' . pretty_value($token->[1]) . ')';
                    return error($parser, "Unexpected $name");
                } else {
                    return error($parser, "Unexpected EOF");
                }
            }
        }


        if ($statement and $statement->[0] ne 'NOP') {
            push @statements, $statement;
        }
    }

    $parser->advance;
    return @statements ? ['PRGM', \@statements] : undef;
}

sub alternate_statement {
    my ($parser, $subref, $debug_msg) = @_;

    $parser->alternate($debug_msg);

    {
        my $result = $subref->($parser);
        return if $parser->errored;

        if ($result) {
            $parser->consume('TERM');
            $parser->advance;
            return ['STMT', $result];
        }
    }
}

# Grammar: Statement ::=   StatementGroup
#                        | VariableDeclaration
#                        | FunctionDefinition
#                        | ReturnStatement
#                        | NextStatement
#                        | LastStatement
#                        | WhileStatement
#                        | IfStatement
#                        | ElseWithoutIf
#                        | ExistsStatement
#                        | DeleteStatement
#                        | RangeStatement
#                        | Expression TERM
#                        | UnexpectedKeyword
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

    my $result;
    return $result if defined ($result = alternate_statement($parser, \&VariableDeclaration, 'Statement: VariableDeclaration'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&FunctionDefinition,  'Statement: FunctionDefinition'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&ReturnStatement,     'Statement: ReturnStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&NextStatement,       'Statement: NextStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&LastStatement,       'Statement: LastStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&WhileStatement,      'Statement: WhileStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&IfStatement,         'Statement: IfStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&ElseWithoutIf,       'Statement: ElseWithoutIf'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&ExistsStatement,     'Statement: ExistsStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&DeleteStatement,     'Statement: DeleteStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&RangeStatement,      'Statement: RangeStatement'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&Expression,          'Statement: Expression'));
    return if $parser->errored;

    return $result if defined ($result = alternate_statement($parser, \&UnexpectedKeyword,   'Statement: UnexpectedKeyword'));
    return if $parser->errored;

    $parser->alternate('Statement: TERM');

    {
        if ($parser->consume('TERM')) {
            $parser->advance;
            return ['NOP', undef];
        }
    }

    $parser->advance;
    return ['NOP', undef];
}

# Grammar: StatementGroup ::= L_BRACE Statement* R_BRACE
sub StatementGroup {
    my ($parser) = @_;

    $parser->try('StatementGroup: L_BRACE Statement R_BRACE');

    {
        goto STATEMENT_GROUP_FAIL if not $parser->consume('L_BRACE');

        my @statements;

        while (1) {
            my $statement = Statement($parser);
            return if $parser->errored;

            if ($statement and $statement->[0] ne 'NOP') {
                push @statements, $statement;
                next;
            }

            last if $parser->consume('R_BRACE');
            goto STATEMENT_GROUP_FAIL;
        }

        $parser->advance;
        return ['STMT_GROUP', \@statements];
    }

  STATEMENT_GROUP_FAIL:
    $parser->backtrack;
}

# Grammar: VariableDeclaration ::= KEYWORD_var IDENT Initializer?
sub VariableDeclaration {
    my ($parser) = @_;

    $parser->try('VariableDeclaration');

    {
        if ($parser->consume('KEYWORD_var')) {
            my $token = $parser->consume('IDENT');
            return expected($parser, 'identifier for variable name') if not $token;

            my $name = $token->[1];

            my $initializer = Initializer($parser);
            return if $parser->errored;

            $parser->advance;
            return ['VAR', $name, $initializer];
        }
    }

    $parser->backtrack;
}

# Grammar: MapConstructor ::= "{" ((String | IDENT) ":" Expression ","?)* "}"
#          String ::= DQUOTE_STRING | SQUOTE_STRING
sub MapConstructor {
    my ($parser) = @_;

    $parser->try('MapConstructor');

    {
        if ($parser->consume('L_BRACE')) {
            my @map;
            while (1) {
                my $key = $parser->consume('DQUOTE_STRING')
                               || $parser->consume('SQUOTE_STRING')
                               || $parser->consume('STRING')
                               || $parser->consume('IDENT');

                if ($key) {
                    if ($key->[0] eq 'DQUOTE_STRING') {
                        $key->[1] =~ s/^\"|\"$//g;
                        $key->[0] = 'STRING';
                    } elsif ($key->[0] eq 'SQUOTE_STRING') {
                        $key->[1] =~ s/^\'|\'$//g;
                        $key->[0] = 'STRING';
                    }

                    if (not $parser->consume('COLON')) {
                        return expected($parser, '":" after map key');
                    }

                    my $expr = Expression($parser);
                    return if $parser->errored;

                    if (not $expr) {
                        return expected($parser, 'expression for map value');
                    }

                    $parser->consume('COMMA');

                    push @map, [$key, $expr];
                    next;
                }

                last if $parser->consume('R_BRACE');
                return expected($parser, 'map entry or `}` in map initializer');
            }

            $parser->advance;
            return ['MAPINIT', \@map];
        }
    }

    $parser->backtrack;
}

# Grammar: ArrayConstructor ::= "[" (Expression ","?)* "]"
sub ArrayConstructor {
    my ($parser) = @_;

    $parser->try('ArrayConstructor');

    {
        if ($parser->consume('L_BRACKET')) {
            my @array;
            while (1) {
                my $expr = Expression($parser);
                return if $parser->errored;

                if ($expr) {
                    $parser->consume('COMMA');
                    push @array, $expr;
                    next;
                }

                last if $parser->consume('R_BRACKET');
                return expected($parser, 'expression or `]` in array initializer');
            }

            $parser->advance;
            return ['ARRAYINIT', \@array];
        }
    }

    $parser->backtrack;
}

# Grammar: Initializer ::= ASSIGN Expression
sub Initializer {
    my ($parser) = @_;

    $parser->try('Initializer');

    {
        if ($parser->consume('ASSIGN')) {
            # try an expression
            my $expr = Expression($parser);
            return if $parser->errored;

            if ($expr) {
                $parser->advance;
                return $expr;
            }

            return expected($parser, 'expression for initializer');
        }
    }

    $parser->backtrack;
}

# Grammar: FunctionDefinition ::= KEYWORD_fn TYPE? IDENT? IdentifierList? (StatementGroup | Statement)
sub FunctionDefinition {
    my ($parser) = @_;

    $parser->try('FunctionDefinition');

    {
        if ($parser->consume('KEYWORD_fn')) {
            my $token = $parser->next_token('peek');

            my $return_type = 'Any';
            if ($token->[0] =~ /^TYPE_(.*)/) {
                $return_type = $1;
                $parser->consume;
            }

            $token = $parser->consume('IDENT');

            my $name;

            if ($token) {
                $name = $token->[1];
            } else {
                $name = "#anonymous";
            }

            my $identlist = IdentifierList($parser);
            return if $parser->errored;

            $identlist = [] if not defined $identlist;

            $parser->try('FunctionDefinition body: StatementGroup');

            {
                my $statement_group = StatementGroup($parser);
                return if $parser->errored;

                if ($statement_group) {
                    $parser->advance;
                    return ['FUNCDEF', $return_type, $name, $identlist, $statement_group->[1]];
                }
            }

            $parser->alternate('FunctionDefinition body: Statement');

            {
                my $statement = Statement($parser);
                return if $parser->errored;

                if ($statement) {
                    $parser->advance;
                    return ['FUNCDEF', $return_type, $name, $identlist, [$statement]];
                }
            }

            return expected($parser, "Statement or StatementGroup for body of function $name");
        }
    }

  FUNCDEF_FAIL:
    $parser->backtrack;
}

# Grammar: IdentifierList      ::= L_PAREN (TypeAndOrIdentifier Initializer? COMMA?)* R_PAREN
#          TypeAndOrIdentifier ::= Type Identifier | Identifier
#          Type ::= Any | Null | Boolean | Number | String | Array | Map | Function | Builtin
sub IdentifierList {
    my ($parser) = @_;

    $parser->try('IdentifierList');

    {
        goto IDENTLIST_FAIL if not $parser->consume('L_PAREN');

        my $identlist = [];
        while (1) {
            my $token = $parser->next_token('peek');

            my $type = 'Any';
            if ($token->[0] =~ /^TYPE_(.*)/) {
                $type = $1;
                $parser->consume;
            }

            if ($token = $parser->consume('IDENT')) {
                my $name = $token->[1];
                my $initializer = Initializer($parser);
                push @{$identlist}, [$type, $name, $initializer];
                $parser->consume('COMMA');
                next;
            }
            last if $parser->consume('R_PAREN');
            goto IDENTLIST_FAIL;
        }

        $parser->advance;
        return $identlist;
    }

  IDENTLIST_FAIL:
    $parser->backtrack;
}

# Grammar: ReturnStatement ::= KEYWORD_return Statement
sub ReturnStatement {
    my ($parser) = @_;

    $parser->try('ReturnStatement');

    {
        if ($parser->consume('KEYWORD_return')) {
            my $statement = Statement($parser);
            return if $parser->errored;

            $parser->advance;
            return ['RET', $statement];
        }
    }

    $parser->backtrack;
}

# Grammar: NextStatement ::= KEYWORD_next
sub NextStatement {
    my ($parser) = @_;

    $parser->try('NextStatement');

    {
        if ($parser->consume('KEYWORD_next')) {
            $parser->advance;
            return ['NEXT', undef];
        }
    }

    $parser->backtrack;
}

# Grammar: LastStatement ::= KEYWORD_last
sub LastStatement {
    my ($parser) = @_;

    $parser->try('LastStatement');

    {
        if ($parser->consume('KEYWORD_last')) {
            $parser->advance;
            return ['LAST', undef];
        }
    }

    $parser->backtrack;
}

# Grammar: WhileStatement ::= KEYWORD_while "(" Expression ")" Statement
sub WhileStatement {
    my ($parser) = @_;

    $parser->try('WhileStatement');

    {
        if ($parser->consume('KEYWORD_while')) {
            if (not $parser->consume('L_PAREN')) {
                return expected($parser, "'(' after `while` keyword");
            }

            my $expr = Expression($parser);
            return if $parser->errored;

            if (not $expr) {
                return expected($parser, "expression for `while` condition");
            }

            if (not $parser->consume('R_PAREN')) {
                return expected($parser, "')' after `while` condition expression");
            }

            my $body = Statement($parser);
            return if $parser->errored;

            if (not $body) {
                return expected($parser, "statement body for `while` loop");
            }

            $parser->advance;
            return ['WHILE', $expr, $body];
        }
    }

    $parser->backtrack;
}

# Grammar: IfStatement ::= KEYWORD_if Expression KEYWORD_then Statement (KEYWORD_else Statement)?
sub IfStatement {
    my ($parser) = @_;

    $parser->try('IfStatement');

    {
        if ($parser->consume('KEYWORD_if')) {
            my $expr = Expression($parser);
            return if $parser->errored;

            if (not $expr) {
                return expected($parser, "expression for `if` condition");
            }

            if (not $parser->consume('KEYWORD_then')) {
                return expected($parser, "`then` after `if` condition expression");
            }

            my $body = Statement($parser);
            return if $parser->errored;

            if (not $body) {
                return expected($parser, "statement body for `if` statement");
            }

            my $else;
            if ($parser->consume('KEYWORD_else')) {
                $else = Statement($parser);
                return if $parser->errored;
            }

            $parser->advance;
            return ['IF', $expr, $body, $else];
        }
    }

    $parser->backtrack;
}

# error about an `else` without an `if`
sub ElseWithoutIf {
    my ($parser) = @_;

    if ($parser->consume('KEYWORD_else')) {
        return error($parser, "`else` without matching `if`");
    }

    return;
}

# Grammar: ExistsStatement ::= KEYWORD_exists Statement
sub ExistsStatement {
    my ($parser) = @_;

    $parser->try('ExistsStatement');

    {
        if ($parser->consume('KEYWORD_exists')) {
            my $statement = Statement($parser);
            return if $parser->errored;

            if (not $statement or not defined $statement->[1]) {
                return expected($parser, "statement after exists keyword");
            }

            $parser->advance;
            return ['EXISTS', $statement->[1]];
        }
    }

    $parser->backtrack;
}

# Grammar: DeleteStatement ::= KEYWORD_delete Statement
sub DeleteStatement {
    my ($parser) = @_;

    $parser->try('DeleteStatement');

    {
        if ($parser->consume('KEYWORD_delete')) {
            my $statement = Statement($parser);
            return if $parser->errored;

            if (not $statement or not defined $statement->[1]) {
                return expected($parser, "statement after delete keyword");
            }

            $parser->advance;
            return ['DELETE', $statement->[1]];
        }
    }

    $parser->backtrack;
}

# Grammar: RangeStatement ::= Expression ".." Expression
sub RangeStatement {
    my ($parser) = @_;

    $parser->try('RangeStatement');

    {
        my $from = Expression($parser);
        return if $parser->errored;

        if ($parser->consume('DOT_DOT')) {
            my $to = Expression($parser);
            return if $parser->errored;

            if ($to) {
                $parser->advance;
                return ['RANGE', $from, $to];
            }
        }
    }

    $parser->backtrack;
}

# error about unexpected keywords
sub UnexpectedKeyword {
    my ($parser) = @_;

    my $token = $parser->next_token('peek');

    if ($token->[0] =~ m/^KEYWORD_(.*)$/) {
        return error($parser, "unexpected keyword `$1`");
    }

    return;
}

my %precedence_table = (
    CALL        => 100,
    POSTFIX     => 70,
    PREFIX      => 60,
    EXPONENT    => 50,
    PRODUCT     => 40,
    SUM         => 30,
    STRING      => 25,
    RELATIONAL  => 23,
    EQUALITY    => 20,
    LOGICAL_AND => 17,
    LOGICAL_OR  => 16,
    CONDITIONAL => 15,
    ASSIGNMENT  => 10,
    STRING_CAT  => 7,
    COMMA       => 5,
    LOW_NOT     => 4,
    LOW_AND     => 3,
    LOW_OR      => 2,
);

# postfix is handled by Infix
my %infix_token_precedence = (
    L_PAREN      => $precedence_table{'CALL'},
    PLUS_PLUS    => $precedence_table{'POSTFIX'},
    MINUS_MINUS  => $precedence_table{'POSTFIX'},
    L_BRACKET    => $precedence_table{'POSTFIX'},
    STAR_STAR    => $precedence_table{'EXPONENT'},
    PERCENT      => $precedence_table{'EXPONENT'},
    STAR         => $precedence_table{'PRODUCT'},
    SLASH        => $precedence_table{'PRODUCT'},
    PLUS         => $precedence_table{'SUM'},
    MINUS        => $precedence_table{'SUM'},
    TILDE        => $precedence_table{'STRING'},
    DOT          => $precedence_table{'STRING'},
    GREATER_EQ   => $precedence_table{'RELATIONAL'},
    LESS_EQ      => $precedence_table{'RELATIONAL'},
    GREATER      => $precedence_table{'RELATIONAL'},
    LESS         => $precedence_table{'RELATIONAL'},
    EQ           => $precedence_table{'EQUALITY'},
    NOT_EQ       => $precedence_table{'EQUALITY'},
    AMP_AMP      => $precedence_table{'LOGICAL_AND'},
    PIPE_PIPE    => $precedence_table{'LOGICAL_OR'},
    QUESTION     => $precedence_table{'CONDITIONAL'},
    ASSIGN       => $precedence_table{'ASSIGNMENT'},
    PLUS_EQ      => $precedence_table{'ASSIGNMENT'},
    MINUS_EQ     => $precedence_table{'ASSIGNMENT'},
    STAR_EQ      => $precedence_table{'ASSIGNMENT'},
    SLASH_EQ     => $precedence_table{'ASSIGNMENT'},
    DOT_EQ       => $precedence_table{'ASSIGNMENT'},
    #COMMA        => $precedence_table{'COMMA'},
    NOT          => $precedence_table{'LOW_NOT'},
    AND          => $precedence_table{'LOW_AND'},
    OR           => $precedence_table{'LOW_OR'},

);

sub get_precedence {
    my ($tokentype) = @_;
    return $infix_token_precedence{$tokentype} // 0;
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

sub Prefix {
    my ($parser, $precedence) = @_;
    my ($token, $expr);

    my $func = FunctionDefinition($parser);
    return if $parser->errored;
    return $func if $func;

    my $if = IfStatement($parser);
    return if $parser->errored;
    return $if if $if;

    my $map = MapConstructor($parser);
    return if $parser->errored;
    return $map if $map;

    my $array = ArrayConstructor($parser);
    return if $parser->errored;
    return $array if $array;

    if ($token = $parser->consume('KEYWORD_null')) {
        return ['NULL', undef];
    }

    if ($token = $parser->consume('KEYWORD_true')) {
        return ['BOOL', 1];
    }

    if ($token = $parser->consume('KEYWORD_false')) {
        return ['BOOL', 0];
    }

    if ($token = $parser->consume('NUM')) {
        return ['NUM', $token->[1] + 0];
    }

    if ($token = $parser->consume('HEX')) {
        return ['NUM', hex $token->[1]];
    }

    # special case types as identifiers here
    $token = $parser->next_token('peek');
    if ($token->[0] =~ /TYPE_(.*)/) {
        my $ident = $1;
        $parser->consume;
        my $postfix = Postfix($parser, ['IDENT', $ident]);
        return if $parser->errored;
        return $postfix;
    }

    if ($token = $parser->consume('IDENT')) {
        my $postfix = Postfix($parser, ['IDENT', $token->[1]]);
        return if $parser->errored;
        return $postfix;
    }

    if ($token = $parser->consume('SQUOTE_STRING_I')) {
        $token->[1] =~ s/^\$//;
        $token->[1] =~ s/^\'|\'$//g;
        return ['STRING_I', $token->[1]];
    }

    if ($token = $parser->consume('DQUOTE_STRING_I')) {
        $token->[1] =~ s/^\$//;
        $token->[1] =~ s/^\"|\"$//g;
        return ['STRING_I', expand_escapes($token->[1])];
    }

    if ($token = $parser->consume('SQUOTE_STRING')) {
        $token->[1] =~ s/^\'|\'$//g;
        return ['STRING', expand_escapes($token->[1])];
    }

    if ($token = $parser->consume('DQUOTE_STRING')) {
        $token->[1] =~ s/^\"|\"$//g;
        return ['STRING', expand_escapes($token->[1])];
    }

    if ($parser->consume('MINUS_MINUS')) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return expected($parser, 'Expression') if not defined $expr;
        return ['PREFIX_SUB', $expr];
    }

    if ($parser->consume('PLUS_PLUS')) {
        my $expr = Expression($parser, $precedence_table{'PREFIX'});
        return expected($parser, 'Expression') if not defined $expr;
        return ['PREFIX_ADD', $expr];
    }

    return $expr if $expr = UnaryOp($parser, 'BANG',   'NOT');
    return $expr if $expr = UnaryOp($parser, 'MINUS',  'NEG');
    return $expr if $expr = UnaryOp($parser, 'PLUS',   'POS');
    return $expr if $expr = UnaryOp($parser, 'NOT',    'NOT');

    if ($token = $parser->consume('L_PAREN')) {
        my $expr = Expression($parser);
        return expected($parser, '")"') if not $parser->consume('R_PAREN');
        return $expr;
    }

    return;
}

sub Infix {
    my ($parser, $left, $precedence) = @_;
    my $expr;

    # ternary conditional operator
    if ($parser->consume('QUESTION')) {
        my $then = Statement($parser);
        return if $parser->errored;

        if (not $then) {
            return expected($parser, '<then> statement in conditional <if> ? <then> : <else> operator');
        }

        if (not $parser->consume('COLON')) {
            return expected($parser, '":" after <then> statement in conditional <if> ? <then> : <else> operator');
        }

        my $else = Statement($parser);
        return if $parser->errored;

        if (not $else) {
            return expected($parser, '<else> statement in conditional <if> ? <then> : <else> operator');
        }

        return ['COND', $left, $then, $else];
    }

    # binary operators
    return $expr if $expr = BinaryOp($parser, $left, 'STAR_STAR',   'POW',        'EXPONENT',     1);
    return $expr if $expr = BinaryOp($parser, $left, 'PERCENT',     'REM',        'EXPONENT');
    return $expr if $expr = BinaryOp($parser, $left, 'STAR',        'MUL',        'PRODUCT');
    return $expr if $expr = BinaryOp($parser, $left, 'SLASH',       'DIV',        'PRODUCT');
    return $expr if $expr = BinaryOp($parser, $left, 'PLUS',        'ADD',        'SUM');
    return $expr if $expr = BinaryOp($parser, $left, 'MINUS',       'SUB',        'SUM');
    return $expr if $expr = BinaryOp($parser, $left, 'TILDE',       'STRIDX',     'STRING');
    return $expr if $expr = BinaryOp($parser, $left, 'DOT',         'STRCAT',     'STRING');
    return $expr if $expr = BinaryOp($parser, $left, 'GREATER_EQ',  'GTE',        'RELATIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'LESS_EQ',     'LTE',        'RELATIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'GREATER',     'GT',         'RELATIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'LESS',        'LT',         'RELATIONAL');
    return $expr if $expr = BinaryOp($parser, $left, 'NOT_EQ',      'NEQ',        'EQUALITY');
    return $expr if $expr = BinaryOp($parser, $left, 'AMP_AMP',     'AND',        'LOGICAL_AND');
    return $expr if $expr = BinaryOp($parser, $left, 'PIPE_PIPE',   'OR',         'LOGICAL_OR');
    return $expr if $expr = BinaryOp($parser, $left, 'EQ',          'EQ',         'EQUALITY');
    return $expr if $expr = BinaryOp($parser, $left, 'ASSIGN',      'ASSIGN',     'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'PLUS_EQ',     'ADD_ASSIGN', 'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'MINUS_EQ',    'SUB_ASSIGN', 'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'STAR_EQ',     'MUL_ASSIGN', 'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'SLASH_EQ',    'DIV_ASSIGN', 'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'DOT_EQ',      'CAT_ASSIGN', 'ASSIGNMENT',   1);
    return $expr if $expr = BinaryOp($parser, $left, 'AND',         'AND',        'LOW_AND');
    return $expr if $expr = BinaryOp($parser, $left, 'OR',          'OR',         'LOW_OR');

    return Postfix($parser, $left, $precedence);
}

sub Postfix {
    my ($parser, $left, $precedence) = @_;

    # post-increment
    if ($parser->consume('PLUS_PLUS')) {
        return ['POSTFIX_ADD', $left];
    }

    # post-decrement
    if ($parser->consume('MINUS_MINUS')) {
        return ['POSTFIX_SUB', $left];
    }

    # function call
    if ($parser->consume('L_PAREN')) {
        my $arguments = [];
        while (1) {
            my $expr = Expression($parser);
            return if $parser->errored;

            if ($expr) {
                push @{$arguments}, $expr;
                $parser->consume('COMMA');
                next;
            }

            last if $parser->consume('R_PAREN');
            return expected($parser, 'expression or closing ")" for function call argument list');
        }

        return ['CALL', $left, $arguments];
    }

    # array/map index
    if ($parser->consume('L_BRACKET')) {
        my $stmt = Statement($parser);
        return if $parser->errored;

        if (not $stmt or not defined $stmt->[1]) {
            return expected($parser, 'statement in postfix [] brackets');
        }

        if (not $parser->consume('R_BRACKET')) {
            return expected($parser, 'closing ] bracket');
        }

        return ['ARRAY_INDEX', $left, $stmt];
    }

    # no postfix
    return $left;
}

1;
