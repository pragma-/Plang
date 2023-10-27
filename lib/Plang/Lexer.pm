#!/usr/bin/env perl

# Converts a stream of characters into a stream of tokens.
#
# Use define_tokens() to define the rules for creating tokens.
#
# See Plang::Interpreter::initialize() for Plang's token definitions.

package Plang::Lexer;

use warnings;
use strict;
use feature 'signatures';

sub new($class, %args) {
    my $self  = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->{tokentypes} = [];

    $self->{line} = 0;
    $self->{col}  = 0;
    $self->{eof}  = 0;
}

# define our tokentypes
sub define_tokens($self, @args) {
    @{$self->{tokentypes}} = @args;
}

sub reset_lexer($self) {
    $self->{line} = 0;
    $self->{col}  = 0;
    $self->{eof}  = 0;
}

sub tokens($self, $input, $tokentypes = undef) {
    # allow overriding list of tokentypes and matchers
    $tokentypes ||= $self->{tokentypes};

    # the current line being lexed
    my $text;

    # closures are neat
    return sub {
        while (1) {
            # get next line if we don't have a line
            $self->{line}++, $text = $input->() if not defined $text and not $self->{eof};

            # all done when there's no more input
            if (not defined $text) {
                $self->{eof} = 1;
                return;
            }

            LOOP: {
                # go through each tokentype
                foreach my $tokentype (@$tokentypes) {
                    # does this bit of text match this tokentype?
                    if ($text =~ /$tokentype->[1]/gc) {
                        # got a token
                        my $literal = $1;

                        $self->{col}  = pos ($text) + 1;
                        $self->{col} -= length $literal;

                        # do we have a specific function to continue lexing this token?
                        if (defined $tokentype->[3]) {
                            my $token = $tokentype->[3]->($self, $input, \$text, $tokentype->[0], $literal, $tokentype->[2]);
                            if (defined $token and (ref $token and length $token->[1]) or not length $token) {
                                return $token;
                            } else {
                                redo LOOP;
                            }
                        }

                        # do we have a specific function to build this token?
                        if (defined $tokentype->[2]) {
                            my $token = $tokentype->[2]->();

                            # is this token ignored?
                            redo LOOP if not ref $token or not length $token->[1];

                            # return built token
                            return $token;
                        }

                        # return this token
                        return [
                            $tokentype->[0],
                            $literal,
                            $self->{line},
                            $self->{col},
                        ];
                    }
                }

                # end of this input
                $text = undef;
            }
        }
    }
}

1;
