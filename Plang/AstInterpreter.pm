#!/usr/bin/env perl

package Plang::AstInterpreter;

use warnings;
use strict;

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

    $self->{ast}      = $conf{ast};
    $self->{debug}    = $conf{debug}    // 0;
    $self->{embedded} = $conf{embedded} // 0;
}

# runs a new Plang program with a fresh environment
sub run {
    my ($self, $ast) = @_;

    $self->{ast} = $ast if defined $ast;

    if (not $self->{ast}) {
        print STDERR "No program to run.\n";
        return;
    }

    # stack for function calls
    $self->{stack} = [];

    # current evaluation context
    my $context = $self->new_context;

    # first context pushed onto the stack is the global context
    # which contains global variables and functions
    $self->push_stack($context);

    # grab our program's statements
    my $program    = $self->{ast}->[0];
    my $statements = $program->[1];

    # interpret the statements
    my $result = $self->interpret_ast($context, $statements);

    # automatically print the result of the program unless we're
    # running in embedded mode
    if (!$self->{embedded} and defined $result) {
        print "$result->[1] ($result->[0])\n";
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
    exit 1;
}

sub new_context {
    my ($self, $parent_context) = @_;

    return {
        variables => {},
        functions => {},
        parent_context => $parent_context,
    };
}

sub new_scope {
    my ($self, $context) = @_;
    return $self->new_context($context);
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
    print "set_variable:\n", Dumper($context->{variables}), "\n" if $self->{debug} >= 6;
}

sub get_variable {
    my ($self, $context, $name) = @_;

    print "get_variable: $name\n", Dumper($context->{variables}), "\n" if $self->{debug} >= 6;
    # look for local variables in current scope
    if (exists $context->{variables}->{$name}) {
        return $context->{variables}->{$name};
    }

    # look for variables in enclosing scopes
    if (defined $context->{parent_context}) {
        my $var = $self->get_variable($context->{parent_context}, $name);
        return $var if defined $var;
    }

    # and finally look for global variables
    if (exists $self->{stack}->[0]->{variables}->{$name}) {
        return $self->{stack}->[0]->{variables}->{$name};
    }

    # otherwise it's an undefined variable
    return undef;
}

sub interpret_ast {
    my ($self, $context, $ast) = @_;

    print "interpet ast: ", Dumper ($ast), "\n" if $self->{debug} >= 5;

    my $result;  # result of final statement

    foreach my $node (@$ast) {
        my $instruction = $node->[0];

        if ($instruction eq 'STMT') {
            $result = $self->statement($context, $node->[1]);
        }

        if ($self->{debug} >= 3) {
            print "Statement result: $result->[1] ($result->[0])\n";
        }
    }

    return $result; # return result of final statement
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
            $debug_msg =~ s/\$a/$value->[1] ($value->[0])/g;
            print $debug_msg, "\n";
        }
        # TODO Check $value->[0] for 'NUM' or 'STRING'
        return ['NUM', $eval_unary_op{$data->[0]}->($value->[1])];
    }
    return;
}

sub binary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $left_value  = $self->statement($context, $data->[1]);
        my $right_value = $self->statement($context, $data->[2]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$left_value->[1] ($left_value->[0])/g;
            $debug_msg =~ s/\$b/$right_value->[1] ($right_value->[0])/g;
            print $debug_msg, "\n";
        }
        # TODO Check $left_value->[0] and $right_value->[0] for 'NUM' or 'STRING'
        return ['NUM', $eval_binary_op{$data->[0]}->($left_value->[1], $right_value->[1])];
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
    return ['VAR', undef]; # TODO return reference to function
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

    my $new_context = $self->new_context;

    for (my $i = 0; $i < @$parameters; $i++) {
        my $arg = $arguments->[$i];

        if (not defined $arg) {
            if (defined $parameters->[$i]->[1]) {
                $arg = $parameters->[$i]->[1];
            } else {
                return $self->error($context, "Missing argument $parameters->[$i]->[0] to function $name.\n");
            }
        }

        $arg = $self->statement($context, $arg); # this ought to be an expression, but
                                                 # let's see where this goes (imagine `if` statements
                                                 # returning the value of their branches...)

        $new_context->{variables}->{$parameters->[$i]->[0]} = $arg;
    }

    if (@$arguments > @$parameters) {
        $self->warning($context, "Extra arguments provided to function $name (takes " . @$parameters . " but passed " . @$arguments . ").");
    }

    $self->push_stack($context);
    my $result = $self->interpret_ast($new_context, $statements);;
    $self->pop_stack;
    return $result;
}

sub is_truthy {
    my ($self, $context, $expr) = @_;

    my $result = $self->statement($context, $expr);

    $self->error($context, 'No truthiness to check for...') if not $result;

    if ($result->[0] eq 'NUM') {
        return $result->[1] == 1;
    }

    if ($result->[0] eq 'STRING') {
        return $result->[1] ne "";
    }

    if ($result->[0] eq 'BOOL') {
        return $result->[1] == 1;
    }

    return;
}

sub statement {
    my ($self, $context, $data) = @_;
    return if not $data;

    my $ins   = $data->[0];
    my $value = $data->[1];

    print "stmt ins: $ins\n" if $self->{debug} >= 4;

    # statement group
    if ($ins eq 'STMT_GROUP') {
        my $new_context = $self->new_scope($context);
        my $result = $self->interpret_ast($new_context, $value);
        return $result;
    }

    # literals
    return ['NUM',    $value] if $ins eq 'NUM';
    return ['STRING', $value] if $ins eq 'STRING';

    # variable declaration
    if ($ins eq 'VAR') {
        my $initializer = $data->[2];
        my $right_value = undef;

        if ($initializer) {
            $right_value = $self->statement($context, $initializer);
        } else {
            $right_value = ['VAR', undef];
        }

        $self->set_variable($context, $value, $right_value);
        return $right_value;
    }

    # ternary ?: conditional operator
    if ($ins eq 'COND') {
        if ($self->is_truthy($context, $data->[1])) {
            return $self->interpret_ast($context, [$data->[2]]);
        } else {
            return $self->interpret_ast($context, [$data->[3]]);
        }
    }

    # if/else
    if ($ins eq 'IF') {
    }

    # assignment
    if ($ins eq 'ASSIGN') {
        my $left_token  = $value;
        my $right_value = $self->statement($context, $data->[2]);
        $self->set_variable($context, $left_token->[1], $right_value);
        return $right_value;
    }

    # variable
    if ($ins eq 'IDENT') {
        my $var = $self->get_variable($context, $value);

        if (not defined $var) {
            $self->error($context, "Attempt to use undeclared variable `$value`");
        }

        if (not defined $var->[1]) {
            $self->error($context, "Attempt to use undefined variable `$value`");
        }

        return $var;
    }

    # function definition
    if ($ins eq 'FUNCDEF') {
        return $self->func_definition($context, $data);
    }

    # function call
    if ($ins eq 'CALL') {
        return $self->func_call($context, $data);
    }

    # prefix increment
    if ($ins eq 'PREFIX_ADD') {
        my $token = $value;
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to prefix-increment undeclared variable `$tok_value`");
        }

        if (not defined $var->[1]) {
            $self->error($context, "Attempt to prefix-increment undefined variable `$tok_value`");
        }

        # TODO check type
        $var->[1]++;
        return $var;
    }

    # prefix decrement
    if ($ins eq 'PREFIX_SUB') {
        my $token = $value;
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to prefix-decrement undeclared variable `$tok_value`");
        }

        if (not defined $var->[1]) {
            $self->error($context, "Attempt to prefix-decrement undefined variable `$tok_value`");
        }

        # TODO check type
        $var->[1]--;
        return $var;
    }

    # unary operators
    return $value if defined ($value = $self->unary_op($context, $data, 'NOT', '! $a'));

    # binary operators
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

    # postfix increment
    if ($ins eq 'POSTFIX_ADD') {
        my $token = $data->[1];
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to postfix-increment undeclared variable `$tok_value`");
        }

        if (not defined $var->[1]) {
            $self->error($context, "Attempt to postfix-increment undefined variable `$tok_value`");
        }

        # TODO check type
        my $temp_var = [$var->[0], $var->[1]];
        $var->[1]++;
        return $temp_var;
    }

    # postfix decrement
    if ($ins eq 'POSTFIX_SUB') {
        my $token = $data->[1];
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to postfix-increment undeclared variable `$tok_value`");
        }

        if (not defined $var->[1]) {
            $self->error($context, "Attempt to postfix-increment undefined variable `$tok_value`");
        }

        # TODO check type
        my $temp_var = [$var->[0], $var->[1]];
        $var->[1]--;
        return $temp_var;
    }

    return;
}

1;
