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

    $self->{stack} = [];
}

sub run {
    my ($self) = @_;
    return $self->interpret_ast if $self->{ast};
}

sub push_stack {
    my ($self, $context) = @_;
    push @{$self->{stack}}, $context;
}

sub pop_stack {
    my ($self) = @_;
    return pop @{$self->{stack}};
}

sub interpret_ast {
    my ($self) = @_;

    my $ast = $self->{ast};

    my $program = $ast->[0];
    my $statements = $program->[1];

    my $result;

    my $context = {
        variables => {},
    };

    foreach my $statement (@$statements) {
        my $instruction = $statement->[0];

        if ($instruction eq 'STMT') {
            $result += $self->statement($context, $statement->[1]);
        }
    }

    print "$result\n";
    return 1;
}

my %eval_unary_op = (
    'NOT' => sub { int ! $_[0] },
);

my %eval_binary_op = (
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

sub unary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $value  = $self->statement($context, $data->[1]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$value/g;
        }
        return $eval_unary_op{$data->[0]}->($value);
    }
    return undef;
}

sub binary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $left_value  = $self->statement($context, $data->[1]);
        my $right_value = $self->statement($context, $data->[2]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$left_value/g;
            $debug_msg =~ s/\$b/$right_value/g;
            print $debug_msg, "\n";
        }

        return $eval_binary_op{$data->[0]}->($left_value, $right_value);
    }
    return undef;
}

sub statement {
    my ($self, $context, $data) = @_;
    my $value;

    return 0 if not $data;

    print "stmt ins: $data->[0]\n" if $self->{debug} >= 3;

    if ($data->[0] eq 'NUM') {
        return $data->[1];
    }

    if ($data->[0] eq 'IDENT') {
        return $context->{variables}->{$data->[1]} // 0;
    }

    if ($data->[0] eq 'ASSIGN') {
        my $left_value  = $data->[1];
        my $right_value = $self->statement($context, $data->[2]);
        $context->{variables}->{$left_value->[1]} = $right_value;
        return 0;
    }

    return $value if defined ($value = $self->unary_op($context, $data, 'NOT', '! $a'));

    return $value if defined ($value = $self->binary_op($context, $data, 'ADD', '$a + $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'SUB', '$a - $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'MUL', '$a * $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'DIV', '$a / $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'REM', '$a % $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'POW', '$a ** $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'EQ',  '$a == $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LT',  '$a < $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GT',  '$a > $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LTE', '$a <= $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GTE', '$a >= $b'));
}

1;
