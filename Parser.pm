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
    $self->{current_position} = 0;
    $self->{saved_positions} = [];

    my $rules = [];
}

sub try {
    my ($self) = @_;
    push @{$self->{saved_positions}}, $self->{current_position};

    if ($self->{debug}) {
        my $count = @{$self->{saved_positions}};
        $self->{dprint}->(2, "[$count] saving posiition $self->{current_position}: ");

        my $token = $self->{read_tokens}->[$self->{current_position}];
        print "[$token->[0], ", $self->{clean}->($token->[1]), "]\n" if defined $token and $self->{debug} >= 2;
        print "\n" if not defined $token and $self->{debug} >= 2;

    }
}

sub backtrack {
    my ($self) = @_;
    $self->{current_position} = pop @{$self->{saved_positions}};

    if ($self->{debug}) {
        my $count = @{$self->{saved_positions}};
        $self->{dprint}->(2, "[$count] backtracking to position $self->{current_position}: ");

        my $token = $self->{read_tokens}->[$self->{current_position}];
        print "[$token->[0], ", $self->{clean}->($token->[1]), "]\n" if defined $token and $self->{debug} >= 2;
        print "\n" if not defined $token and $self->{debug} >= 2;
    }
}

sub alternate {
    my ($self) = @_;
    $self->backtrack;
    $self->try;
}

sub advance {
    my ($self) = @_;
    pop @{$self->{saved_positions}};

    if ($self->{debug}) {
        my $count = @{$self->{saved_positions}};
        $self->{dprint}->(2, "[$count] popped a backtrack\n");
    }
}

sub terminal {
    my ($self) = @_;
    $self->{dprint}->(2, "discarding backtrack\n");
    $self->{read_tokens} = [];
    $self->{saved_positions} = [];
    $self->{current_token} = 0;
}

sub next_token {
    my ($self, $opt) = @_;

    $opt ||= '';

    $self->{dprint}->(5, "Fetching next token: ");
    print "(peeking) " if $opt eq 'peek' and $self->{debug} >= 5;

    my $token;

    NEXT_TOKEN: {
        if ($opt eq 'peek') {
            # return token if we've already peeked a token
            $token = $self->{read_tokens}->[$self->{current_position}];
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
    $self->{current_position}++ unless $opt eq 'peek';

    print "[$token->[0], ", $self->{clean}->($token->[1]), "], position: $self->{current_position}\n" if $self->{debug} >= 5;

    return $token;
}

sub upcoming {
    my ($self, $expected) = @_;

    my $token = $self->next_token('peek');

    return undef if not defined $token;

    $self->{dprint}->(1, "Looking for $expected... ");

    if ($token->[0] eq $expected) {
        print "got it (", $self->{clean}->($token->[1]), ")\n" if $self->{debug};
        $self->{current_position}++;
        return $token;
    } else {
        print "got $token->[0]\n" if $self->{debug};
        return undef;
    }
}

sub expect {
    my ($self, $expected) = @_;

    my $token = $self->next_token('peek');

    if (not defined $token) {
        print "Expected $expected but got EOF\n";
        return 0;
    }

    if ($token->[0] ne $expected) {
        print "Expected $expected but got $token->[0]\n";
        return 0;
    }

    return 1;
}

sub add_rule {
    my ($self, $rule) = @_;
    push @{$self->{rules}}, $rule;
}

sub parse {
    my ($self) = @_;

    my @results;

    RULE: {
        foreach my $rule (@{$self->{rules}}) {
            my $result = $rule->($self);

            if (defined $result) {
                push @results, $result;
                redo RULE;
            }
        }
    }

    return \@results;
}

1;
