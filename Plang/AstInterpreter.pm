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

    $self->{max_recursion} = $conf{max_recursion} // 10000;
    $self->{recursions}    = 0;
}

# creates a fresh environment for a Plang program
sub init_program {
    my ($self) = @_;

    # stack for function calls
    $self->{stack} = [];

    # current evaluation context
    my $context = $self->new_context;

    # first context pushed onto the stack is the global context
    # which contains global variables and functions
    $self->push_stack($context);

    return $context;
}

# runs a new Plang program with a fresh environment
sub run {
    my ($self, $ast) = @_;

    # ast can be supplied via new() or via this run() subroutine
    $self->{ast} = $ast if defined $ast;

    # make sure we were given a program
    if (not $self->{ast}) {
        print STDERR "No program to run.\n";
        return;
    }

    # create a fresh environment
    my $context = $self->init_program;

    # grab our program's statements
    my $program    = $self->{ast}->[0];
    my $statements = $program->[1];

    # interpret the statements
    my $result = $self->interpret_ast($context, $statements);

    # return result to parent program if we're embedded
    return $result if $self->{embedded};

    # return success if there's no result to print
    return if not defined $result;

    # handle final statement (print last value of program if not Nil)
    return $self->handle_statement_result($result, 1);
}

sub error {
    my ($self, $context, $err_msg) = @_;
    chomp $err_msg;
    die "Fatal error: $err_msg\n";
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
    print "set_variable $name\n", Dumper($context->{variables}), "\n" if $self->{debug} >= 6;
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

    my $last_statement_result = eval {
        my $result;
        foreach my $node (@$ast) {
            my $instruction = $node->[0];

            if ($instruction eq 'STMT') {
                $result = $self->statement($context, $node->[1]);
                $result = $self->handle_statement_result($result) if defined $result;
                return $result->[1] if defined $result and $result->[0] eq 'RETURN';
            }

            if ($self->{debug} >= 3) {
                if (defined $result) {
                    print "Statement result: ", defined $result->[1] ? $result->[1] : 'undef', " ($result->[0])\n";
                } else {
                    print "Statement result: none\n";
                }
            }
        }

        return $result;
    };

    if ($@) {
        return ['ERROR', $@];
    }

    return $last_statement_result; # return result of final statement
}

# handles one statement result
sub handle_statement_result {
    my ($self, $result, $print_any) = @_;
    $print_any ||= 0;

    return if not defined $result;

    $Data::Dumper::Indent = 0 if $self->{debug} >= 3;
    print "handle result: ", Dumper($result), "\n" if $self->{debug} >= 3;

    # if Plang is embedded into a larger app return the result
    # to the larger app so it can handle it itself
    return $result if $self->{embedded};

    # print to stdout and consume result by returning nothing
    if ($result->[0] eq 'STDOUT') {
        print $result->[1];
        return;
    }

    # return result unless we should print any result
    return $result unless $print_any;

    # print the result if possible and then consume it
    print "$result->[1]\n" if defined $result->[1];
    return;
}

my %eval_unary_op_NUM = (
    'NOT' => sub { int ! $_[0] },
    'NEG' => sub {     - $_[0] },
    'POS' => sub {     + $_[0] },
);

my %eval_binary_op_NUM = (
    'ADD' => sub { $_[0]  + $_[1] },
    'SUB' => sub { $_[0]  - $_[1] },
    'MUL' => sub { $_[0]  * $_[1] },
    'DIV' => sub { $_[0]  / $_[1] },
    'REM' => sub { $_[0]  % $_[1] },
    'POW' => sub { $_[0] ** $_[1] },
    'EQ'  => sub { $_[0] == $_[1] },
    'NEQ' => sub { $_[0] != $_[1] },
    'LT'  => sub { $_[0]  < $_[1] },
    'GT'  => sub { $_[0]  > $_[1] },
    'LTE' => sub { $_[0] <= $_[1] },
    'GTE' => sub { $_[0] >= $_[1] },
);

my %eval_binary_op_STRING = (
    'ADD' => sub { $_[0]   . $_[1] },
    'EQ'  => sub { $_[0]  eq $_[1] },
    'NEQ' => sub { $_[0]  ne $_[1] },
    'LT'  => sub { $_[0] cmp $_[1] },
    'GT'  => sub { $_[0] cmp $_[1] },
    'LTE' => sub { $_[0] cmp $_[1] },
    'GTE' => sub { $_[0] cmp $_[1] },
    'REM' => sub { index $_[0], $_[1] },
);

sub unary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $value  = $self->statement($context, $data->[1]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$value->[1] ($value->[0])/g;
            print $debug_msg, "\n";
        }

        if ($value->[0] eq 'NUM') {
            if (exists $eval_unary_op_NUM{$op}) {
                return ['NUM', $eval_unary_op_NUM{$op}->($value->[1])];
            }
        }

        $self->error($context, "Cannot apply unary operator $op to type $value->[0]\n");
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

        if ($left_value->[0] eq 'NUM' and $right_value->[0] eq 'NUM') {
            if (exists $eval_binary_op_NUM{$op}) {
                return ['NUM', $eval_binary_op_NUM{$op}->($left_value->[1], $right_value->[1])];
            }
        }

        if ($left_value->[0] eq 'STRING' or $right_value->[0] eq 'STRING') {
            if (exists $eval_binary_op_STRING{$op}) {
                return ['STRING', $eval_binary_op_STRING{$op}->($left_value->[1], $right_value->[1])];
            }
        }

        $self->error($context, "Cannot apply binary operator $op (have types $left_value->[0] and $right_value->[0])");
    }
    return;
}

sub func_definition {
    my ($self, $context, $data) = @_;

    my $name       = $data->[1];
    my $parameters = $data->[2];
    my $statements = $data->[3];

    # TODO warn or error about overwriting existing functions?
    $context->{functions}->{$name} = [$parameters, $statements];
    return ['FUNCREF', undef]; # TODO return reference to function
}

my %func_builtins = (
    'print'   => {
        # [['param1 name', default value], ['param2 name', default value], [...]]
        params => [['statement', undef]],
        subref => \&func_builtin_print,
    },
    'println' => {
        params => [['statement', undef]],
        subref => \&func_builtin_println,
    },
);

sub func_builtin_print {
    my ($self, $name, $arguments) = @_;
    my $output = $arguments->[0]->[1];
    return ['STDOUT', $output];
}

sub func_builtin_println {
    my ($self, $name, $arguments) = @_;
    my $output .= $arguments->[0]->[1] . "\n";
    return ['STDOUT', $output];
}

sub add_function_builtin {
    my ($self, $name, $parameters, $subref) = @_;
    # TODO warn/error if overwriting?
    $func_builtins{$name} = { params => $parameters, subref => $subref };
}

sub call_builtin_function {
    my ($self, $context, $data, $name) = @_;

    my $parameters = $func_builtins{$name}->{params};
    my $func       = $func_builtins{$name}->{subref};
    my $arguments  = $data->[2];

    my $evaled_args = $self->process_func_call_arguments($context, $name, $parameters, $arguments);

    return $func->($self, $name, $evaled_args);
}

sub process_func_call_arguments {
    my ($self, $context, $name, $parameters, $arguments) = @_;

    my $evaluated_arguments;

    for (my $i = 0; $i < @$parameters; $i++) {
        if (not defined $arguments->[$i]) {
            # no argument provided
            if (defined $parameters->[$i]->[1]) {
                # found default argument
                $evaluated_arguments->[$i] = $self->statement($context, $parameters->[$i]->[1]);
                $context->{variables}->{$parameters->[$i]->[0]} = $evaluated_arguments->[$i];
            } else {
                # no argument or default argument
                $self->error($context, "Missing argument `$parameters->[$i]->[0]` to function `$name`.\n"),
            }
        } else {
            # argument provided
            $evaluated_arguments->[$i] = $self->statement($context, $arguments->[$i]);
            $context->{variables}->{$parameters->[$i]->[0]} = $evaluated_arguments->[$i];
        }
    }

    if (@$arguments > @$parameters) {
        $self->error($context, "Extra arguments provided to function `$name` (takes " . @$parameters . " but passed " . @$arguments . ")");
    }

    return $evaluated_arguments;
}

sub func_call {
    my ($self, $context, $data) = @_;

    my $name      = $data->[1];
    my $arguments = $data->[2];

    $Data::Dumper::Indent = 0 if $self->{debug} >= 5;
    print "Calling function `$name` with arguments: ", Dumper($arguments), "\n" if $self->{debug} >= 5;

    my $func;

    if (exists $context->{functions}->{$name}) {
        # local function
        $func = $context->{functions}->{$name};
    } elsif (exists $self->{stack}->[0]->{functions}->{$name}) {
        # global function
        $func = $self->{stack}->[0]->{functions}->{$name};
    } elsif (exists $func_builtins{$name}) {
        # builtin function
        return $self->call_builtin_function($context, $data, $name);
    } else {
        # undefined function
        $self->error($context, "Undefined function `$name`.");
    }

    my $parameters = $func->[0];
    my $statements = $func->[1];

    my $new_context = $self->new_context($context); # TODO do we want context to be parent of new_context?

    my $ret = $self->process_func_call_arguments($new_context, $name, $parameters, $arguments);


    # check for recursion limit
    if (++$self->{recursions} > $self->{max_recursion}) {
        $self->error($context, "Max recursion limit ($self->{max_recursion}) reached.");
    }

    print "new context: ", Dumper($new_context), "\n" if $self->{debug} >= 5;

    # invoke the function
    $self->push_stack($context);
    my $result = $self->interpret_ast($new_context, $statements);;
    $self->{recursion}--;
    $self->pop_stack;
    return $result;
}

sub is_truthy {
    my ($self, $context, $expr) = @_;

    my $result = $self->statement($context, $expr);

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

# TODO: do this much more efficiently
sub parse_string {
    my ($self, $string) = @_;

    use Plang::Interpreter;
    my $interpreter = Plang::Interpreter->new;
    my $program = $interpreter->parse_string($string);
    my $statements = $program->[0]->[1];

    return $statements;
}

sub interpolate_string {
    my ($self, $context, $string) = @_;

    my $new_string = "";
    while ($string =~ /\G(.*?)(\{(?:[^\}\\]|\\.)*\})/gc) {
        my ($text, $interpolate) = ($1, $2);
        my $ast = $self->parse_string($interpolate);
        my $result = $self->interpret_ast($context, $ast);
        $new_string .= $text . $result->[1];
    }

    $string =~ /\G(.*)/gc;
    $new_string .= $1;
    return $new_string;
}

sub statement {
    my ($self, $context, $data) = @_;
    return if not $data;

    my $ins   = $data->[0];
    my $value = $data->[1];

    print "stmt ins: $ins (value: ", Dumper($value), "\n" if $self->{debug} >= 4;

    # statement group
    if ($ins eq 'STMT_GROUP') {
        my $new_context = $self->new_scope($context);
        my $result = $self->interpret_ast($new_context, $value);
        return $result;
    }

    # literals
    return ['NUM',    $value] if $ins eq 'NUM';
    return ['STRING', $value] if $ins eq 'STRING';

    # interpolated string
    if ($ins eq 'STRING_I') {
        $value = $self->interpolate_string($context, $value);
        return ['STRING', $value];
    }

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

    # return
    if ($ins eq 'RET') {
        return ['RETURN', $self->statement($context, $value->[1])];
    }

    # if/else
    if ($ins eq 'IF') {
    }

    # assignment
    if ($ins eq 'ASSIGN') {
        my $left_token  = $value;
        my $right_value = $self->statement($context, $data->[2]);
        my $var = $self->get_variable($context, $value->[1]);
        $self->error($context, "Attempt to use undeclared variable `$value->[1]`") if not defined $var;
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
    return $value if defined ($value = $self->unary_op($context, $data, 'NEG', '- $a'));
    return $value if defined ($value = $self->unary_op($context, $data, 'POS', '+ $a'));

    # binary operators
    return $value if defined ($value = $self->binary_op($context, $data, 'ADD', '$a + $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'SUB', '$a - $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'MUL', '$a * $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'DIV', '$a / $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'REM', '$a % $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'POW', '$a ** $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'EQ',  '$a == $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'NEQ', '$a != $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LT',  '$a < $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GT',  '$a > $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LTE', '$a <= $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GTE', '$a >= $b'));

    # postfix array index [] notation
    if ($ins eq 'IDX') {
    }

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
