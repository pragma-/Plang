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

    print "statement: ins: $instruction\n";

    if ($instruction eq 'NUM') {
        return $data->[1];
    }

    if ($data->[0] eq 'ADD') {
        my $left_value  = $self->statement($data->[1]);
        my $right_value = $self->statement($data->[2]);

        print "adding $left_value + $right_value\n";
        return $left_value + $right_value;
    }

    if ($data->[0] eq 'SUB') {
        my $left_value  = $self->statement($data->[1]);
        my $right_value = $self->statement($data->[2]);

        print "subtracting $left_value - $right_value\n";
        return $left_value - $right_value;
    }


    if ($data->[0] eq 'MUL') {
        my $left_value  = $self->statement($data->[1]);
        my $right_value = $self->statement($data->[2]);

        print "multiplying $left_value * $right_value\n";
        return $left_value * $right_value;
    }

    if ($data->[0] eq 'DIV') {
        my $left_value  = $self->statement($data->[1]);
        my $right_value = $self->statement($data->[2]);

        print "dividing $left_value / $right_value\n";
        return $left_value / $right_value;
    }
}

1;
