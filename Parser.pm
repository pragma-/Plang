#!/usr/bin/env perl

use warnings;
use strict;

package Parser;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{token_iter} = $conf{token_iter};

    $self->{debug} = $ENV{DEBUG} // 0;

    if ($self->{debug}) {
        $self->{clean} = sub { $_[0] =~ s/\n/\\n/g; $_[0] };
        $self->{dprint} = sub { my $level = shift; print "|  " x $self->{indent}, @_ if $level <= $self->{debug} };
        $self->{indent} = 0;
    } else {
        $self->{dprint} = sub {};
        $self->{clean} = sub {};
    }

    $self->{read_tokens} = [];
    $self->{current_token} = 0;
    $self->{backtrack} = [];

    $self->{errors} = [];

    $self->{rules} = [];
}

# try a rule (pushes the current token index onto the backtrack)
sub try {
    my ($self) = @_;
    push @{$self->{backtrack}}, $self->{current_token};

    if ($self->{debug}) {
        my $count = @{$self->{backtrack}};
        $self->{dprint}->(2, "[$count] saving posiition $self->{current_token}: ");

        my $token = $self->{read_tokens}->[$self->{current_token}];
        print "[$token->[0], ", $self->{clean}->($token->[1]), "]\n" if defined $token and $self->{debug} >= 2;
        print "\n" if not defined $token and $self->{debug} >= 2;

    }
}

# backtrack to the previous try point
sub backtrack {
    my ($self) = @_;
    $self->{current_token} = pop @{$self->{backtrack}};

    if ($self->{debug}) {
        my $count = @{$self->{backtrack}};
        $self->{dprint}->(2, "[$count] backtracking to position $self->{current_token}: ");

        my $token = $self->{read_tokens}->[$self->{current_token}];
        print "[$token->[0], ", $self->{clean}->($token->[1]), "]\n" if defined $token and $self->{debug} >= 2;
        print "\n" if not defined $token and $self->{debug} >= 2;
    }
}

sub errored {
    my ($self) = @_;

    if ($self->{got_error}) {
        $self->{dprint}->(1, "Got error.\n");
        $self->{indent}--;
        $self->advance;
        return 1;
    }

    return 0;
}

# advance to the next rule (pops and discards one backtrack)
sub advance {
    my ($self) = @_;
    pop @{$self->{backtrack}};

    if ($self->{debug}) {
        my $count = @{$self->{backtrack}};
        $self->{dprint}->(2, "[$count] popped a backtrack\n");
    }
}

# alternate to another variant (backtrack and try another variant)
sub alternate {
    my ($self) = @_;
    $self->backtrack;
    $self->try;
}

# gets the next token from the token iterator
# if the first argument is 'peek' then the token will be returned unconsumed
sub next_token {
    my ($self, $opt) = @_;

    $opt ||= '';

    $self->{dprint}->(5, "Fetching next token: ");
    print "(peeking) " if $opt eq 'peek' and $self->{debug} >= 5;

    my $token;

    NEXT_TOKEN: {
        if ($opt eq 'peek') {
            # return token if we've already peeked a token
            $token = $self->{read_tokens}->[$self->{current_token}];
            print "peeked existing: [$token->[0], ", $self->{clean}->($token->[1]), "]\n" if defined $token and $self->{debug} >= 5;
            return $token if defined $token;
        }

        # attempt to get a new token
        $token = $self->{token_iter}->();

        # no token, bail early
        return undef if not defined $token;

        # is this token ignored?
        if (ref $token and not length $token->[1] or not length $token) {
            redo NEXT_TOKEN;
        }
    }

    # add to list of tokens read so far in case we need to backtrack
    push @{$self->{read_tokens}}, $token;

    # consume token unless we're just peeking
    $self->consume unless $opt eq 'peek';

    print "[$token->[0], ", $self->{clean}->($token->[1]), "], position: $self->{current_token}\n" if $self->{debug} >= 5;

    return $token;
}

# gets the current token from the backtrack without consuming it
# next_token() must have been invoked at least once
sub current_token {
    my ($self) = @_;
    return $self->{read_tokens}->[$self->{current_token}];
}

# if no arguments passed, consumes the current token
# otherwise, consumes and returns token only if token matches argument
sub consume {
    my ($self, $wanted) = @_;

    if (not defined $wanted) {
        $self->{current_token}++;
        return;
    }

    my $token = $self->next_token('peek');

    return undef if not defined $token;

    $self->{dprint}->(1, "Looking for $wanted... ");

    if ($token->[0] eq $wanted) {
        print "got it (", $self->{clean}->($token->[1]), ")\n" if $self->{debug};
        $self->{current_token}++;
        return $token;
    }

    print "got $token->[0] instead\n" if $self->{debug};
    return undef;
}

# consumes and discards tokens until target is reached,
# whereupon target is consumed as well
sub consume_to {
    my ($self, $target) = @_;

    $self->{dprint}->(1, "Consuming until $target\n");

    while (1) {
        my $token = $self->next_token('peek');

        $self->{dprint}->(1, "Peeked EOF\n") if not defined $token;
        return if not defined $token;

        $self->{dprint}->(1, "Consumed $token->[0] at position $self->{current_token}\n");
        $self->consume;

        if ($token->[0] eq $target) {
            $self->{dprint}->(1, "Got target.\n");
            return;
        }
    }
}

# rewrites the backtrack to the current token position
sub rewrite_backtrack {
    my ($self) = @_;

    foreach my $backtrack (@{$self->{backtrack}}) {
        $backtrack = $self->{current_token};
    }
}

# add an error message
sub add_error {
    my ($self, $text) = @_;
    push @{$self->{errors}}, $text;

    $self->{dprint}->(1, "Added error: $text\n");
}

# add a rule to the parser engine
sub add_rule {
    my ($self, $rule) = @_;
    push @{$self->{rules}}, $rule;
}

# parse the rules
sub parse {
    my ($self) = @_;

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
