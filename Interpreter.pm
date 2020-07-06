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
    $self->{debug} = $conf{debug} // 0;
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

    print "$result\n";
    return 1;
}

my %eval_op = (
    'ADD' => sub { $_[0]  + $_[1] },
    'SUB' => sub { $_[0]  - $_[1] },
    'MUL' => sub { $_[0]  * $_[1] },
    'DIV' => sub { $_[0]  / $_[1] },
    'REM' => sub { $_[0]  % $_[1] },
    'POW' => sub { $_[0] ** $_[1] },
    'EQ'  => sub { $_[0] == $_[1] },
    'LT'  => sub { $_[0]  < $_[1] },
    'GT'  => sub { $_[0]  > $_[1] },
    'LTE' => sub { $_[0] <= $_[1] },
    'GTE' => sub { $_[0] >= $_[1] },
);

sub binary_op {
    my ($self, $data, $instruction, $op, $debug_msg) = @_;

    if ($instruction eq $op) {
        my $left_value  = $self->statement($data->[1]);
        my $right_value = $self->statement($data->[2]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$left_value/g;
            $debug_msg =~ s/\$b/$right_value/g;
            print $debug_msg, "\n";
        }

        return $eval_op{$instruction}->($left_value, $right_value);
    }

    return undef;
}

sub statement {
    my ($self, $data) = @_;
    return 0 if not $data;

    my $instruction = $data->[0];
    print "stmt ins: $instruction\n" if $self->{debug} >= 3;

    if ($instruction eq 'NUM') {
        return $data->[1];
    }

    if ($instruction eq 'NOT') {
        my $value  = $self->statement($data->[1]);
        print "NOTing $value\n" if $self->{debug} >= 3;
        return int !$value;
    }

    my $value;
    return $value if defined ($value = $self->binary_op($data, $instruction, 'ADD', '$a + $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'SUB', '$a - $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'MUL', '$a * $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'DIV', '$a / $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'REM', '$a % $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'POW', '$a ** $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'EQ',  '$a == $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'LT',  '$a < $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'GT',  '$a > $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'LTE', '$a <= $b'));
    return $value if defined ($value = $self->binary_op($data, $instruction, 'GTE', '$a >= $b'));
}

1;
