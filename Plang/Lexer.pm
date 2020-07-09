#!/usr/bin/env perl

package Plang::Lexer;

use warnings;
use strict;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{tokentypes} = [];
}

# define our tokentypes
sub define_tokens {
    my $self = shift;

    $self->{tokentypes} = [];

    foreach my $arg (@_) {
        push @{$self->{tokentypes}}, $arg;
    }
}

sub tokens {
    my ($self, $input, $tokentypes) = @_;

    # allow overriding list of tokentypes and matchers
    $tokentypes ||= $self->{tokentypes};

    # the current line being lexed
    my $text;

    $self->{line} = 0;
    $self->{col}  = 0;

    # closures are neat
    return sub {
        while (1) {
            # get next line if we don't have a line
            $self->{line}++, $text = $input->() if not defined $text;

            # all done when there's no more input
            return if not defined $text;

            LOOP: {
                # go through each tokentype
                foreach my $tokentype (@$tokentypes) {
                    # does this bit of text match this tokentype?
                    if ($text =~ /$tokentype->[1]/gc) {
                        # got a token
                        my $literal = $1;

                        $self->{col} = pos ($text) + 1;
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
                            {
                                line    => $self->{line},
                                col     => $self->{col},
                            }
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
