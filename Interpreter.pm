#!/usr/bin/env perl

use warnings;
use strict;

package Interpreter;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
    $self->{ast} = $conf{ast};
}

sub run {
    my ($self) = @_;
    return $self->interpret_ast if $self->{ast};
}

sub interpret_ast {
    my ($self) = @_;

    my $ast = $self->{ast};

    my $program = $ast->[0];
    my $statements = $program->[1];

    my $result;

    foreach my $statement (@$statements) {
        my $instruction = $statement->[0];

        if ($instruction eq 'STMT') {
            $result += $self->statement($statement->[1]);
        }
    }

    return $result;
}

sub statement {
    my ($self, $data) = @_;

    my $instruction = $data->[0];

    # This was originally a given/when switch block.
    #
    # While it was pretty to look at, it was a tad slower than if/else.

    if ($instruction eq 'NUM') {
        return $data->[1];
    }

    if ($instruction eq 'ADD') {
        my ($left, $right) = ($data->[1], $data->[2]);

        my $left_value  = $self->statement($left);
        my $right_value = $self->statement($right);

        return $left_value + $right_value;
    }

    if ($instruction eq 'MUL') {
        my ($left, $right) = ($data->[1], $data->[2]);

        my $left_value  = $self->statement($left);
        my $right_value = $self->statement($right);

        return $left_value * $right_value;
    }
}

1;
