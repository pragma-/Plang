#!/usr/bin/env perl

use warnings;
use strict;

package Interpreter;

use Data::Dumper;

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

    if (not $self->{ast}) {
        print STDERR "No program to run.\n";
        return;
    }

    my $context = {
        variables => {},
        functions => {},
    };

    # first context pushed onto the stack is the global context
    # which contains global variables and functions
    $self->push_stack($context);

    my $program    = $self->{ast}->[0];
    my $statements = $program->[1];

    my $result = $self->interpret_ast($context, $statements);

    if (defined $result) {
        print "$result\n";
    }

    return $result;
}

sub warning {
    my ($self, $context, $warn_msg) = @_;
    chomp $warn_msg;
    print STDERR "Warning: $warn_msg\n";
    return;
}

sub error {
    my ($self, $context, $err_msg) = @_;
    chomp $err_msg;
    print STDERR "Fatal error: $err_msg\n";
    return;
}

sub push_stack {
    my ($self, $context) = @_;
    push @{$self->{stack}}, $context;
}

sub pop_stack {
    my ($self) = @_;
    return pop @{$self->{stack}};
}

sub set_variable {
    my ($self, $context, $name, $value) = @_;
    $context->{variables}->{$name} = $value;
}

sub get_variable {
    my ($self, $context, $name) = @_;

    if (exists $context->{variables}->{$name}) {
        return $context->{variables}->{$name}->[1];
    } elsif (exists $self->{stack}->[0]->{variables}->{$name}) {
        return $self->{stack}->[0]->{variables}->{$name}->[1];
    } else {
        return 0;
    }
}

sub interpret_ast {
    my ($self, $context, $ast) = @_;

    print "interpet ast: ", Dumper ($ast), "\n" if $self->{debug} >= 5;

    my $result;
    foreach my $node (@$ast) {
        my $instruction = $node->[0];

        if ($instruction eq 'STMT') {
            $result = $self->statement($context, $node->[1]);
            last if not defined $result;
        }
    }

    return $result;
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
            print $debug_msg, "\n";
        }
        return $eval_unary_op{$data->[0]}->($value);
    }
    return;
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
    return;
}

sub func_definition {
    my ($self, $context, $data) = @_;

    my $name       = $data->[1];
    my $parameters = $data->[2];
    my $statements = $data->[3];

    if (exists $context->{functions}->{$name}) {
        $self->warning($context, "Overwriting existing function `$name`.\n");
    }

    $context->{functions}->{$name} = [$parameters, $statements];
    return 1;
}

sub func_call {
    my ($self, $context, $data) = @_;

    my $name      = $data->[1];
    my $arguments = $data->[2];

    my $func;

    if (exists $context->{functions}->{$name}) {
        $func = $context->{functions}->{$name};
    } elsif (exists $self->{stack}->[0]->{functions}->{$name}) {
        $func = $self->{stack}->[0]->{functions}->{$name};
    } else {
        return $self->error($context, "Undefined function `$name`.");
    }

    my $parameters = $func->[0];
    my $statements = $func->[1];

    my $new_context = {
        variables => {},
        functions => {},
    };

    for (my $i = 0; $i < @$parameters; $i++) {
        my $arg = $arguments->[$i];

        if (not defined $arg) {
            return $self->error($context, "Missing argument $parameters->[$i] to function $name.\n");
        }

        if ($arg->[0] eq 'IDENT') {
            $arg = ['NUM', $self->get_variable($context, $arg->[1])];
        }

        $new_context->{variables}->{$parameters->[$i]} = $arg;
    }

    if (@$arguments > @$parameters) {
        $self->warning($context, "Extra arguments provided to function $name (takes " . @$parameters . " but passed " . @$arguments . ").");
    }

    $self->push_stack($context);
    my $result = $self->interpret_ast($new_context, $statements);;
    $self->pop_stack;
    return $result;
}

sub statement {
    my ($self, $context, $data) = @_;
    return if not $data;

    my $ins   = $data->[0];
    my $value = $data->[1];

    print "stmt ins: $ins\n" if $self->{debug} >= 4;

    return $value if $ins eq 'NUM';
    return $value if $ins eq 'STRING';

    if ($ins eq 'ASSIGN') {
        my $left_token  = $value;
        my $right_value = $self->statement($context, $data->[2]);
        $self->set_variable($context, $left_token->[1], [$left_token->[0], $right_value]);
        return $right_value;
    }

    if ($ins eq 'IDENT') {
        return $self->get_variable($context, $value);
    }

    if ($ins eq 'FUNCDEF') {
        return $self->func_definition($context, $data);
    }

    if ($ins eq 'CALL') {
        return $self->func_call($context, $data);
    }

    if ($ins eq 'PREFIX_ADD') {
        my $token = $value;
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        if ($tok_type eq 'IDENT') {
            return ++$context->{variables}->{$tok_value};
        }

        return;
    }

    if ($ins eq 'PREFIX_SUB') {
        my $token = $value;
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        if ($tok_type eq 'IDENT') {
            return --$context->{variables}->{$tok_value};
        }

        return;
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

    if ($ins eq 'POSTFIX_ADD') {
        my $token = $value;
        my ($type, $value) = ($token->[0], $token->[1]);

        if ($type eq 'IDENT') {
            return $context->{variables}->{$value}++;
        } else {
            return $self->error($context, "Postfix increment on non-object");
        }
    }

    if ($ins eq 'POSTFIX_SUB') {
        my $token = $value;
        my ($type, $value) = ($token->[0], $token->[1]);

        if ($type eq 'IDENT') {
            return $context->{variables}->{$value}--;
        }
    }

    return;
}

1;
