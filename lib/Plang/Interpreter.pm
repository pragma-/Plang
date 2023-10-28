#!/usr/bin/env perl

# Plang interpreter main entry point and API.
#
# Defines tokens, keywords, types and rules. Reads input from streams
# or strings and sends it to be parsed and interpreted.

package Plang::Interpreter;

use warnings;
use strict;
use feature 'signatures';

use Plang::Lexer;
use Plang::Parser;
use Plang::ParseRules qw/Program/;
use Plang::Types;
use Plang::Validator;
use Plang::AstInterpreter;

use Plang::Constants::Tokens   ':all';
use Plang::Constants::Keywords ':all';

sub new($class, %args) {
    my $self  = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->{embedded} = $conf{embedded};
    $self->{debug}    = $conf{debug};

    if ($self->{debug}) {
        my %tags = map { $_ => 1 } split /,/, $self->{debug};

        $self->{debug} = {
            tags  => \%tags,
            print => sub {
                my ($tag, $message, $indent) = @_;
                if ($tags{$tag} || $tags{ALL}) {
                    print "|  " x $indent if defined $indent;
                    print $message;
                }
            }
        };
    }

    $self->{lexer} = Plang::Lexer->new(debug => $self->{debug});

    $self->{lexer}->define_tokens(
        # [ TOKEN_TYPE,  MATCH REGEX,  OPTIONAL TOKEN BUILDER,  OPTIONAL SUB-LEXER ]
        [TOKEN_COMMENT_EOL,      qr{\G(   (?://|\#).*$        )}x,  \&discard],
        [TOKEN_COMMENT_INLINE,   qr{\G(   /\* .*? \*/         )}x,  \&discard],
        [TOKEN_COMMENT_MULTI,    qr{\G(   /\* .*?(?!\*/)\s+$  )}x,  \&discard, sub { multiline_comment(@_) }],
        [TOKEN_DQUOTE_STRING_I,  qr{\G(   \$"(?:[^"\\]|\\.)*" )}x],
        [TOKEN_SQUOTE_STRING_I,  qr{\G(   \$'(?:[^'\\]|\\.)*' )}x],
        [TOKEN_DQUOTE_STRING,    qr{\G(   "(?:[^"\\]|\\.)*"   )}x],
        [TOKEN_SQUOTE_STRING,    qr{\G(   '(?:[^'\\]|\\.)*'   )}x],
        [TOKEN_EQ_TILDE,         qr{\G(   =~                  )}x],
        [TOKEN_BANG_TILDE,       qr{\G(   !~                  )}x],
        [TOKEN_NOT_EQ,           qr{\G(   !=                  )}x],
        [TOKEN_GREATER_EQ,       qr{\G(   >=                  )}x],
        [TOKEN_LESS_EQ,          qr{\G(   <=                  )}x],
        [TOKEN_EQ,               qr{\G(   ==                  )}x],
        [TOKEN_SLASH_EQ,         qr{\G(   /=                  )}x],
        [TOKEN_STAR_EQ,          qr{\G(   \*=                 )}x],
        [TOKEN_MINUS_EQ,         qr{\G(   -=                  )}x],
        [TOKEN_PLUS_EQ,          qr{\G(   \+=                 )}x],
        [TOKEN_DOT_EQ,           qr{\G(   \.=                 )}x],
        [TOKEN_PLUS_PLUS,        qr{\G(   \+\+                )}x],
        [TOKEN_STAR_STAR,        qr{\G(   \*\*                )}x],
        [TOKEN_MINUS_MINUS,      qr{\G(   --                  )}x],
# !used [TOKEN_L_ARROW,          qr{\G(   <-                  )}x],
        [TOKEN_R_ARROW,          qr{\G(   ->                  )}x],
        [TOKEN_ASSIGN,           qr{\G(   =                   )}x],
        [TOKEN_PLUS,             qr{\G(   \+                  )}x],
        [TOKEN_MINUS,            qr{\G(   -                   )}x],
        [TOKEN_GREATER,          qr{\G(   >                   )}x],
        [TOKEN_LESS,             qr{\G(   <                   )}x],
        [TOKEN_BANG,             qr{\G(   !                   )}x],
        [TOKEN_QUESTION,         qr{\G(   \?                  )}x],
# !used [TOKEN_COLON_COLON,      qr{\G(   ::                  )}x],
        [TOKEN_COLON,            qr{\G(   :                   )}x],
# !used [TOKEN_TILDE_TILDE,      qr{\G(   ~~                  )}x],
        [TOKEN_TILDE,            qr{\G(   ~                   )}x],
        [TOKEN_PIPE_PIPE,        qr{\G(   \|\|                )}x],
        [TOKEN_PIPE,             qr{\G(   \|                  )}x],
        [TOKEN_AMP_AMP,          qr{\G(   &&                  )}x],
# !used [TOKEN_AMP,              qr{\G(   &                   )}x],
        [TOKEN_CARET_CARET_EQ,   qr{\G(   \^\^=               )}x],
        [TOKEN_CARET_CARET,      qr{\G(   \^\^                )}x],
        [TOKEN_CARET,            qr{\G(   \^                  )}x],
        [TOKEN_PERCENT,          qr{\G(   %                   )}x],
        [TOKEN_POUND,            qr{\G(   \#                  )}x],
        [TOKEN_COMMA,            qr{\G(   ,                   )}x],
        [TOKEN_STAR,             qr{\G(   \*                  )}x],
        [TOKEN_SLASH,            qr{\G(   /                   )}x],
        [TOKEN_BSLASH,           qr{\G(   \\                  )}x],
        [TOKEN_L_BRACKET,        qr{\G(   \[                  )}x],
        [TOKEN_R_BRACKET,        qr{\G(   \]                  )}x],
        [TOKEN_L_PAREN,          qr{\G(   \(                  )}x],
        [TOKEN_R_PAREN,          qr{\G(   \)                  )}x],
        [TOKEN_L_BRACE,          qr{\G(   \{                  )}x],
        [TOKEN_R_BRACE,          qr{\G(   \}                  )}x],
        [TOKEN_DOT_DOT,          qr{\G(   \.\.                )}x],
        [TOKEN_DOT,              qr{\G(   \.                  )}x],
        [TOKEN_NOT,              qr{\G(   not                 )}x],
        [TOKEN_AND,              qr{\G(   and                 )}x],
        [TOKEN_OR,               qr{\G(   or                  )}x],
        [TOKEN_IDENT,            qr{\G(   [A-Za-z_]\w*        )}x],
        [TOKEN_HEX,              qr{\G(   0[xX][0-9a-fA-F]+   )}x],
        [TOKEN_FLT,              qr{\G(   [0-9]*(?:\.[0-9]*[eE][+-]?[0-9]+|\.[0-9]+|[eE][+-]?[0-9]+)  )}x],
        [TOKEN_INT,              qr{\G(   [0-9]+              )}x],
        [TOKEN_TERM,             qr{\G(   ;\n*                )}x],
        [TOKEN_WHITESPACE,       qr{\G(   \s+                 )}x,  \&discard],
        [TOKEN_OTHER,            qr{\G(   .                   )}x],
    );

    $self->{parser} = Plang::Parser->new(debug => $self->{debug});

    $self->{parser}->add_rule(\&Program);

    $self->{parser}->define_keywords(@pretty_keyword);

    $self->{types} = Plang::Types->new(debug => $self->{debug});

    $self->{parser}->define_types(map { $_ => 1 } $self->{types}->as_list);

    $self->{validator} = Plang::Validator->new(debug => $self->{debug}, types => $self->{types});

    $self->{interpreter} = Plang::AstInterpreter->new(embedded => $conf{embedded}, debug => $self->{debug}, types => $self->{types});
}

# discard token
sub discard {''}

# sub-lexer for a multi-line comment token
sub multiline_comment($lexer, $input, $text, $tokentype, $buf, $tokenbuilder) {
    while (1) {
        $lexer->{line}++, $$text = $input->() if not defined $$text;

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

sub add_builtin_function($self, @args) {
    $self->{interpreter}->add_builtin_function(@args);
}

sub parse($self, $input_iter) {
    $self->reset_parser;
    # iterates over tokens returned by lexer
    my $token_iter = $self->{lexer}->tokens($input_iter);
    $self->{ast}   = $self->{parser}->parse($token_iter);
    return $self->{ast};
}

sub parse_stream($self, $stream) {
    # iterates over lines of the stream
    my $input_iter = sub { <$stream> };
    return $self->parse($input_iter);
}

sub parse_string($self, $string) {
    # iterates over lines of the string
    my @lines = split /\n/, $string;
    my $input_iter = sub { shift @lines };
    return $self->parse($input_iter);
}

sub handle_parse_errors($self) {
    # were there any parse errors?
    if (my $count = @{$self->{parser}->{errors}}) {
        if (not $self->{embedded}) {
            # not embedded: print them and exit
            print STDERR "$_\n" for @{$self->{parser}->{errors}};
            print STDERR "$count error", $count == 1 ? '' : 's', ".\n";
            exit 1;
        } else {
            # embedded: return them as a string
            my $errors = join "\n", @{$self->{parser}->{errors}};
            $errors .= "\n$count error" . ($count == 1 ? '' : 's') . ".\n";
            return $errors;
        }
    }

    return;
}

sub reset_parser($self) {
    $self->{lexer}->reset_lexer;
}

sub reset_types($self) {
    $self->{types}->reset_types;
    $self->{parser}->define_types(map { $_ => 1 } $self->{types}->as_list);
}

sub validate($self, $ast, %opt) {
    return $self->{validator}->validate($ast, %opt);
}

sub interpret($self, %opt) {
    my $errors = $self->handle_parse_errors;
    die $errors if defined $errors;

    print "-- Validator --\n" if $self->{debug};
    $errors = $self->validate($self->{ast}, %opt);

    if ($errors) {
        if (not $self->{embedded}) {
            # not embedded: print errors and exit
            print STDERR $errors->[1];
            exit 1;
        } else {
            # embedded: return as-is
            return $errors;
        }
    }

    print "-- Interpreter --\n" if $self->{debug};
    $self->{interpreter}->reset; # reset recursion and iteration counters
    my $result = eval { $self->{interpreter}->run($self->{ast}, %opt) };

    if (my $exception = $@) {
        chomp $exception;
        $exception =~ s/ at.*// if $exception =~ /\.pm line \d+/; # strip Perl info
        die "Run-time error: unhandled exception: $exception\n";
    }

    return $result;
}

sub interpret_stream($self, $stream, %opt) {
    $self->reset_types unless $opt{repl};
    $self->parse_stream($stream);
    return $self->interpret(%opt);
}

sub interpret_string($self, $string, %opt) {
    $self->reset_types unless $opt{repl};
    $self->parse_string($string);
    return $self->interpret(%opt);
}

1;
