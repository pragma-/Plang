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
    my ($self, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $left_value  = $self->statement($data->[1]);
        my $right_value = $self->statement($data->[2]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$left_value/g;
            $debug_msg =~ s/\$b/$right_value/g;
            print $debug_msg, "\n";
        }

        return $eval_op{$data->[0]}->($left_value, $right_value);
    }

    return undef;
}

sub statement {
    my ($self, $data) = @_;
    return 0 if not $data;

    print "stmt ins: $data->[0]\n" if $self->{debug} >= 3;

    if ($data->[0] eq 'NUM') {
        return $data->[1];
    }

    if ($data->[0] eq 'NOT') {
        my $value  = $self->statement($data->[1]);
        print "!$value\n" if $self->{debug} >= 3;
        return int !$value;
    }

    my $value;
    return $value if defined ($value = $self->binary_op($data, 'ADD', '$a + $b'));
    return $value if defined ($value = $self->binary_op($data, 'SUB', '$a - $b'));
    return $value if defined ($value = $self->binary_op($data, 'MUL', '$a * $b'));
    return $value if defined ($value = $self->binary_op($data, 'DIV', '$a / $b'));
    return $value if defined ($value = $self->binary_op($data, 'REM', '$a % $b'));
    return $value if defined ($value = $self->binary_op($data, 'POW', '$a ** $b'));
    return $value if defined ($value = $self->binary_op($data, 'EQ',  '$a == $b'));
    return $value if defined ($value = $self->binary_op($data, 'LT',  '$a < $b'));
    return $value if defined ($value = $self->binary_op($data, 'GT',  '$a > $b'));
    return $value if defined ($value = $self->binary_op($data, 'LTE', '$a <= $b'));
    return $value if defined ($value = $self->binary_op($data, 'GTE', '$a >= $b'));
}

1;
