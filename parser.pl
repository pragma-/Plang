#!/usr/bin/env perl

use warnings;
use strict;

# allow loading .pm modules from the current directory
BEGIN {
    unshift @INC, '.';
}

# convenient data structure printer
use Data::Dumper;

use Lexer;
use Parser;

# our lexer
my $lexer = Lexer->new;

# define the tokens our lexer will recognize
$lexer->define_tokens(
  # [ TOKEN_TYPE,      MATCH REGEX,    OPTIONAL TOKEN BUILDER,  OPTIONAL SUB-LEXER ]
    ['COMMENT_EOL',    qr{\G(   (?://|\#).*$        )}x,  sub {''}],
    ['COMMENT_INLINE', qr{\G(   /\* .*? \*/         )}x,  sub {''}],
    ['COMMENT_MULTI',  qr{\G(   /\* .*?(?!\*/)\s+$  )}x,  sub {''}, sub { multiline_comment(@_) }],
    ['DQUOTE_STRING',  qr{\G(   "(?:[^"\\]|\\.)*"   )}x],
    ['SQUOTE_STRING',  qr{\G(   '(?:[^'\\]|\\.)*'   )}x],
    ['EQ_EQ',          qr{\G(   ==                  )}x],
    ['PLUS_EQ',        qr{\G(   \+=                 )}x],
    ['PLUS_PLUS',      qr{\G(   \+\+                )}x],
    ['EQ',             qr{\G(   =                   )}x],
    ['PLUS',           qr{\G(   \+                  )}x],
    ['MINUS',          qr{\G(   -                   )}x],
    ['COMMA',          qr{\G(   ,                   )}x],
    ['STAR',           qr{\G(   \*                  )}x],
    ['BSLASH',         qr{\G(   /                   )}x],
    ['FSLASH',         qr{\G(   \\                  )}x],
    ['L_PAREN',        qr{\G(   \(                  )}x],
    ['R_PAREN',        qr{\G(   \)                  )}x],
    ['NUM',            qr{\G(   [0-9.]+             )}x],
    ['IDENT',          qr{\G(   [A-Za-z_]\w*        )}x],
    ['TERM',           qr{\G(   ;\n* | \n+          )}x],
    ['WHITESPACE',     qr{\G(   \s+                 )}x,  sub {''}],
    ['OTHER',          qr{\G(   .                   )}x],
);

# sub-lexer for a multi-line comment token
sub multiline_comment {
    my ($input, $text, $tokentype, $buf, $tokenbuilder) = @_;

    while (1) {
        $$text = $input->() if not defined $$text;

        if (not defined $$text) {
            return defined $tokenbuilder ? $tokenbuilder->() : [$tokentype, $buf];
        }

        if ($$text =~ m{\G( .*? \*/ \s* )}gcx) {
            $buf .= $1;
            return defined $tokenbuilder ? $tokenbuilder->() : [$tokentype, $buf];
        } else {
            $$text =~ m{\G( .* \s* )}gxc;
            $buf .= $1;
            $$text = undef;
        }
    }
}

# Grammar: DumpToken --> *
sub DumpToken {
    my ($parser) = @_;
    return $parser->next_token;
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
        return $token;
    }

    $parser->{indent}--;
    $parser->{dprint}->(1, "<- Factor fail\n");

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
            my $token = $parser->{read_tokens}->[$parser->{current_position}];
            $token = defined $token ? $token->[0] : 'EOF';
            print "Expected Expression but got $token\n";
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

# iterates over lines of standard input
my $input_iter = sub { <STDIN> };

# iterates over tokens returned by lexer
my $token_iter = $lexer->tokens($input_iter);

# our parser and its token iterator
my $parser = Parser->new(token_iter => $token_iter);

# if -dumptokens was specified on command-line, use the DumpToken rule
# otherwise use the Program rule
if (grep { $_ eq '-dumptokens' } @ARGV) {
    $parser->add_rule(\&DumpToken);
} else {
    $parser->add_rule(\&Program);
}

# parse the input into $result
my $result = $parser->parse;

# dump the $result data structure
$Data::Dumper::Terse = 1;
print Dumper $result;
