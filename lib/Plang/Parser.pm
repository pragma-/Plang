#!/usr/bin/env perl

# Generic parser class.
#
# Gets tokens from Plang::Lexer and parses them using keywords,
# types and rules defined by define_keywords(), define_types()
# and add_rule(). Typically only the start-rule need be added.
#
# See Plang::ParseRules::Program() for the start-rule for a Plang program.
#
# See Plang::Interpreter for token, keyword and type definitions.

package Plang::Parser;

use warnings;
use strict;
use feature 'signatures';

use Plang::Constants::Tokens ':all';

sub new($class, %args) {
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->{token_iter} = $conf{token_iter};

    $self->{debug} = $conf{debug};

    if ($self->{debug}) {
        $self->{indent} = 0;
        $self->{clean}  = sub { $_[0] =~ s/\n/\\n/g; $_[0] };
    }

    $self->{rules}    = [];
    $self->{keywords} = [];
    $self->{types}    = {};
}

# define our keywords
sub define_keywords($self, @args) {
    @{$self->{keywords}} = @args;
}

# define our types
sub define_types($self, @args) {
    %{$self->{types}} = @args;
}

# add a new type
sub add_type($self, $name) {
    $self->{types}->{$name} = 1;
}

# get an existing type
sub get_type($self, $name) {
    return $self->{types}->{$name};
}

# try a rule (pushes the current token index onto the backtrack)
sub try($self, $dbg_msg) {
    push @{$self->{backtrack}}, $self->{current_token};

    if ($self->{debug}) {
        $self->{debug}->{print}->('PARSER', "+-> Trying $dbg_msg\n", $self->{indent});
        push @{$self->{current_rule}}, $dbg_msg;
        $self->{indent}++;

        my $count = @{$self->{backtrack}};
        $self->{debug}->{print}->('BACKTRACK', "[$count] saving posiition $self->{current_token}\n", $self->{indent});

        my $token = $self->{read_tokens}->[$self->{current_token}];
        $self->{debug}->{print}->('TOKEN', "Trying token [" . $pretty_token[$token->[0]] . ", " . $self->{clean}->($token->[1]) . "]\n", $self->{indent}) if defined $token;
    }
}

# backtrack to the previous try point
sub backtrack($self) {
    $self->{current_token} = pop @{$self->{backtrack}};

    if ($self->{debug}) {
        my $count = @{$self->{backtrack}} + 1;
        $self->{debug}->{print}->('BACKTRACK', "[$count] backtracking to position $self->{current_token}\n", $self->{indent});

        my $token = $self->{read_tokens}->[$self->{current_token}];
        $self->{debug}->{print}->('TOKEN', "Backtracked to token [" . $pretty_token[$token->[0]] . ", " . $self->{clean}->($token->[1]) . "]\n", $self->{indent}) if defined $token;

        $self->{indent}--;
        my $rule = pop @{$self->{current_rule}};
        $self->{debug}->{print}->('PARSER', "<- Backtracked $rule\n", $self->{indent});
    }

    return;
}

# advance to the next rule (pops and discards one backtrack)
sub advance($self) {
    pop @{$self->{backtrack}};

    if ($self->{debug}) {
        my $count = @{$self->{backtrack}};
        $self->{debug}->{print}->('BACKTRACK', "[$count] popped a backtrack\n", $self->{indent});

        $self->{indent}--;

        my $rule = pop @{$self->{current_rule}};
        $self->{debug}->{print}->('PARSER', "<- Advanced $rule\n", $self->{indent}) if defined $rule;
    }
}

# alternate to another variant (backtrack and try another variant)
sub alternate($self, $dbg_msg) {
    $self->backtrack;
    $self->try($dbg_msg);
}

# gets the next token from the token iterator
# if the first argument is 'peek' then the token will be returned unconsumed
sub next_token($self, $opt = '') {
    if ($self->{debug}) {
        if ($opt eq 'peek') {
            $self->{debug}->{print}->('TOKEN', "Peeking next token:\n", $self->{indent});
        } else {
            $self->{debug}->{print}->('TOKEN', "Fetching next token:\n", $self->{indent});
        }
    }

    my $token;

    NEXT_TOKEN: {
        if ($opt eq 'peek' and @{$self->{read_tokens}}) {
            # return token if we've already peeked a token
            $token = $self->{read_tokens}->[$self->{current_token}];

            if ($self->{debug} && defined $token) {
                $self->{debug}->{print}->('TOKEN', "Peeked existing token: [" . $pretty_token[$token->[0]] . ", " . $self->{clean}->($token->[1]) . "]\n", $self->{indent});
            }

            if (defined $token) {
                return $token;
            }
        }

        # attempt to get a new token
        $token = $self->{token_iter}->();

        # no token, bail early
        return if not defined $token;

        # is this token ignored?
        if (ref $token and not length $token->[1] or not length $token) {
            redo NEXT_TOKEN;
        }

        if ($token->[0] == TOKEN_IDENT) {
            # is this identifier a keyword?
            foreach my $keyword (@{$self->{keywords}}) {
                if ($token->[1] eq $keyword) {
                    $token->[0] = TOKEN_KEYWORD;
                    last;
                }
            }

            # is this identifier a type?
            if (exists $self->{types}->{$token->[1]}) {
                $token->[0] = TOKEN_TYPE;
            }
        }
    }

    # add to list of tokens read so far in case we need to backtrack
    push @{$self->{read_tokens}}, $token;

    # consume token unless we're just peeking
    $self->consume unless $opt eq 'peek';

    if ($self->{debug}) {
        $self->{debug}->{print}->('TOKEN', "Got new token: [" . $pretty_token[$token->[0]] . ", " . $self->{clean}->($token->[1]) . "], position: $self->{current_token}\n", $self->{indent});
    }

    return $token;
}

# gets the current token from the token history without consuming it
# next_token() must have been invoked at least once
sub current_token($self) {
    return $self->{read_tokens}->[$self->{current_token}];
}

# gets the previous token from the token history
# if only one token exists, returns that token
sub previous_token($self) {
    if ($self->{current_token} > 1) {
        return $self->{read_tokens}->[$self->{current_token} - 1];
    }
    elsif ($self->{current_token} == 1) {
        return $self->{read_tokens}->[0];
    }
    return undef;
}


# if no arguments passed, consumes the current token
# otherwise, consumes and returns token only if token matches argument
sub consume($self, $wanted = undef) {
    my $debug = $self->{debug};

    my $token = $self->next_token('peek');
    return if not defined $token;

    if (not defined $wanted) {
        $self->{current_token}++;
        return $token;
    }

    $self->{debug}->{print}->('PARSER', "Looking for " . $pretty_token[$wanted] . "\n", $self->{indent}) if $debug;

    if ($token->[0] == $wanted) {
        $self->{debug}->{print}->('PARSER', "Got it (" . $self->{clean}->($token->[1]) . ")\n", $self->{indent}) if $debug;
        $self->{current_token}++;
        return $token;
    }

    $self->{debug}->{print}->('PARSER', "Got " . $pretty_token[$token->[0]] . " instead\n", $self->{indent}) if $debug;
    return;
}

# consumes and discards tokens until target is reached,
# whereupon target is consumed as well
sub consume_to($self, $target) {
    my $debug = $self->{debug};

    $self->{debug}->{print}->('PARSER', "Consuming until $pretty_token[$target]\n", $self->{indent}) if $debug;

    while (1) {
        my $token = $self->next_token('peek');

        $self->{debug}->{print}->('PARSER', "Peeked EOF\n", $self->{indent}) if $debug and not defined $token;
        return if not defined $token;

        $self->{debug}->{print}->('PARSER', "Consumed $pretty_token[$token->[0]] at position $self->{current_token}\n", $self->{indent}) if $debug;
        $self->consume;

        if ($token->[0] == $target) {
            $self->{debug}->{print}->('PARSER', "Got target.\n", $self->{indent}) if $debug;
            return;
        }
    }
}

# rewrites the backtrack to the current token position
sub rewrite_backtrack($self) {
    foreach my $backtrack (@{$self->{backtrack}}) {
        $backtrack = $self->{current_token};
    }
}

# add an error message
sub add_error($self, $text) {
    push @{$self->{errors}}, $text;
    $self->set_error;
    $self->{debug}->{print}->('PARSER', "Added error: $text\n", $self->{indent}) if $self->{debug};
}

# was there an error in the last parse?
sub errored($self) {
    if ($self->{got_error}) {
        $self->{debug}->{print}->('PARSER', "Got error.\n", $self->{indent}) if $self->{debug};
        $self->advance;
        return 1;
    }

    return 0;
}

# set the error flag
sub set_error($self) {
    $self->{debug}->{print}->('PARSER', "Error set.\n", $self->{indent}) if $self->{debug};
    $self->{got_error} = 1;
}

# clear the error flag
sub clear_error($self) {
    $self->{debug}->{print}->('PARSER', "Error cleared.\n", $self->{indent}) if $self->{debug};
    $self->{got_error} = 0;
}

# remove existing rules
sub clear_rules($self) {
    $self->{rules} = [];
}

# add a rule to the parser engine
sub add_rule($self, $rule) {
    push @{$self->{rules}}, $rule;
}

# parse the rules
sub parse($self, $token_iter = undef) {
    $self->{token_iter} = $token_iter if defined $token_iter;

    $self->{read_tokens}   = [];
    $self->{current_token} = 0;
    $self->{backtrack}     = [];

    $self->{errors} = [];

    my @results;

    RULE: {
        foreach my $rule (@{$self->{rules}}) {
            if (defined (my $result = $rule->($self))) {
                push @results, $result;
                redo RULE;
            }
        }
    }

    return \@results;
}

1;
