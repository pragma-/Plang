#!/usr/bin/env perl

package Plang::Interpreter;

use warnings;
use strict;

use Plang::Lexer;
use Plang::Parser;
use Plang::Grammar qw/Program/;
use Plang::AstInterpreter;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{debug} = $conf{debug};

    $self->{embedded} = $conf{embedded};

    if ($self->{debug}) {
        $self->{clean}  = sub { $_[0] =~ s/\n/\\n/g; $_[0] };
        $self->{dprint} = sub { my $level = shift; print "|  " x $self->{indent}, @_ if $level <= $self->{debug} };
        $self->{indent} = 0;
    } else {
        $self->{dprint} = sub {};
        $self->{clean}  = sub {};
    }

    $self->{lexer} = Plang::Lexer->new(debug => $conf{debug});

    $self->{lexer}->define_tokens(
        # [ TOKEN_TYPE,  MATCH REGEX,  OPTIONAL TOKEN BUILDER,  OPTIONAL SUB-LEXER ]
        ['COMMENT_EOL',      qr{\G(   (?://|\#).*$        )}x,  \&discard],
        ['COMMENT_INLINE',   qr{\G(   /\* .*? \*/         )}x,  \&discard],
        ['COMMENT_MULTI',    qr{\G(   /\* .*?(?!\*/)\s+$  )}x,  \&discard, sub { multiline_comment(@_) }],
        ['DQUOTE_STRING_I',  qr{\G(   \$"(?:[^"\\]|\\.)*" )}x],
        ['SQUOTE_STRING_I',  qr{\G(   \$'(?:[^'\\]|\\.)*' )}x],
        ['DQUOTE_STRING',    qr{\G(   "(?:[^"\\]|\\.)*"   )}x],
        ['SQUOTE_STRING',    qr{\G(   '(?:[^'\\]|\\.)*'   )}x],
        ['NOT_EQ',           qr{\G(   !=                  )}x],
        ['GREATER_EQ',       qr{\G(   >=                  )}x],
        ['LESS_EQ',          qr{\G(   <=                  )}x],
        ['EQ',               qr{\G(   ==                  )}x],
        ['SLASH_EQ',         qr{\G(   /=                  )}x],
        ['STAR_EQ',          qr{\G(   \*=                 )}x],
        ['MINUS_EQ',         qr{\G(   -=                  )}x],
        ['PLUS_EQ',          qr{\G(   \+=                 )}x],
        ['PLUS_PLUS',        qr{\G(   \+\+                )}x],
        ['STAR_STAR',        qr{\G(   \*\*                )}x],
        ['MINUS_MINUS',      qr{\G(   --                  )}x],
        ['ASSIGN',           qr{\G(   =                   )}x],
        ['PLUS',             qr{\G(   \+                  )}x],
        ['MINUS',            qr{\G(   -                   )}x],
        ['GREATER',          qr{\G(   >                   )}x],
        ['LESS',             qr{\G(   <                   )}x],
        ['BANG',             qr{\G(   !                   )}x],
        ['QUESTION',         qr{\G(   \?                  )}x],
        ['COLON',            qr{\G(   :                   )}x],
        ['TILDE',            qr{\G(   ~                   )}x],
        ['CARET',            qr{\G(   ^                   )}x],
        ['PERCENT',          qr{\G(   %                   )}x],
        ['POUND',            qr{\G(   \#                  )}x],
        ['COMMA',            qr{\G(   ,                   )}x],
        ['STOP',             qr{\G(   \.                  )}x],
        ['STAR',             qr{\G(   \*                  )}x],
        ['SLASH',            qr{\G(   /                   )}x],
        ['BSLASH',           qr{\G(   \\                  )}x],
        ['L_PAREN',          qr{\G(   \(                  )}x],
        ['R_PAREN',          qr{\G(   \)                  )}x],
        ['L_BRACE',          qr{\G(   \{                  )}x],
        ['R_BRACE',          qr{\G(   \}                  )}x],
        ['NUM',              qr{\G(   [0-9.]+             )}x],
        ['IDENT',            qr{\G(   [A-Za-z_]\w*        )}x],
        ['TERM',             qr{\G(   ;\n*                )}x],
        ['WHITESPACE',       qr{\G(   \s+                 )}x,  \&discard],
        ['OTHER',            qr{\G(   .                   )}x],
    );

    $self->{parser} = Plang::Parser->new(debug => $conf{debug});

    $self->{parser}->add_rule(\&Program);

    $self->{parser}->define_keywords(
        'var',
        'fn', 'return',
        'if', 'else',
    );

    $self->{interpreter} = Plang::AstInterpreter->new(embedded => $conf{embedded}, debug => $conf{debug});
}

# discard token
sub discard {''}

# sub-lexer for a multi-line comment token
sub multiline_comment {
    my ($lexer, $input, $text, $tokentype, $buf, $tokenbuilder) = @_;

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

sub parse {
    my ($self, $input_iter) = @_;
    # iterates over tokens returned by lexer
    my $token_iter = $self->{lexer}->tokens($input_iter);
    $self->{ast}   = $self->{parser}->parse($token_iter);
    return $self->{ast};
}

sub parse_stream {
    my ($self, $stream) = @_;
    # iterates over lines of the stream
    my $input_iter = sub { <$stream> };
    return $self->parse($input_iter);
}

sub parse_string {
    my ($self, $string) = @_;
    # iterates over lines of the string
    my @lines = split /\n/, $string;
    my $input_iter = sub { shift @lines };
    return $self->parse($input_iter);
}

sub handle_parse_errors {
    my ($self) = @_;
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
            $errors .= "\n$count error" . $count == 1 ? '' : 's' . ".\n";
            return $errors;
        }
    }

    return;
}

sub interpret {
    my ($self) = @_;
    my $errors = $self->handle_parse_errors;
    return $errors if defined $errors;
    return $self->{interpreter}->run($self->{ast});
}

sub interpret_stream {
    my ($self, $stream) = @_;
    $self->parse_stream($stream);
    return $self->interpret;
}

sub interpret_string {
    my ($self, $string) = @_;
    $self->parse_string($string);
    return $self->interpret;
}

1;
