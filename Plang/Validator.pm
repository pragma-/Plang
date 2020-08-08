#!/usr/bin/env perl

# Validates a Plang syntax tree by performing static type-checking,
# semantic-analysis, etc, so the interpreter need not concern itself
# with these potentially expensive operations.

package Plang::Validator;

use warnings;
use strict;

use parent 'Plang::AstInterpreter';

use Data::Dumper;

sub initialize {
    my ($self, %conf) = @_;

    $self->SUPER::initialize(%conf);

    $self->{eval_unary_op_ANY} = {
        'NOT' => sub { ['BOOL', 0 ]},
        'NEG' => sub { ['NUM',  0 ]},
        'POS' => sub { ['NUM',  0 ]},
    };

    $self->{eval_binary_op_ANY} = {
        'POW'    => sub { ['NUM',    0  ]},
        'REM'    => sub { ['NUM',    0  ]},
        'MUL'    => sub { ['NUM',    0  ]},
        'DIV'    => sub { ['NUM',    0  ]},
        'ADD'    => sub { ['NUM',    0  ]},
        'SUB'    => sub { ['NUM',    0  ]},
        'GTE'    => sub { ['BOOL',   0  ]},
        'LTE'    => sub { ['BOOL',   0  ]},
        'GT'     => sub { ['BOOL',   0  ]},
        'LT'     => sub { ['BOOL',   0  ]},
        'EQ'     => sub { ['BOOL',   0  ]},
        'NEQ'    => sub { ['BOOL',   0  ]},
        'STRCAT' => sub { ['STRING', "" ]},
        'STRIDX' => sub { ['NUM',    0  ]},
    };

    $self->{internal_types} = {
        'Any'     => 'ANY',
        'Null'    => 'NULL',
        'Boolean' => 'BOOL',
        'Number'  => 'NUM',
        'String'  => 'STRING',
        'Map'     => 'MAP',
        'Array'   => 'ARRAY',
    };
}

sub parse_pretty_type {
    my ($self, $pretty_type) = @_;

    if (exists $self->{internal_types}->{$pretty_type}) {
        return [$self->{internal_types}->{$pretty_type}];
    }

    if ($pretty_type =~ /^(?:Builtin|Function)\s/) {
        my ($type, $rest) = $self->parse_pretty_type_function($pretty_type);
        return [$type];
    }

    die "unknown type `$pretty_type`";
}

sub parse_pretty_type_function {
    my ($self, $pretty_type) = @_;
    my $result = [];

    $pretty_type =~ s/^(Builtin|Function)\s*//;
    push @$result, $1;

    # parameter types
    if ($pretty_type =~ s/^\(//) {
      NEXT_PARAM:
        $pretty_type =~ s/(\w+)//;
        my $type = $1;
        my $rest;

        if (exists $self->{internal_types}->{$type}) {
            push @$result, $self->{internal_types}->{$type};
        }

        elsif ($type eq 'Function' or $type eq 'Builtin') {
            ($type, $rest) = $self->parse_pretty_type_function($type . $pretty_type);
            push @$result, $type;
            $pretty_type = $rest;
        }

        if ($pretty_type =~ s/^,\s*//) {
            goto NEXT_PARAM;
        }

        $pretty_type =~ s/^\)\s*//;
    }

    # return type
    $pretty_type =~ s/^->\s*(\w+)//;
    my $type = $1;
    my $rest;

    if (exists $self->{internal_types}->{$type}) {
        push @$result, $self->{internal_types}->{$type};
        return ($result, $pretty_type);
    }

    ($type, $rest) = $self->parse_pretty_type_function($type . $pretty_type);
    push @$result, $type;
    return ($result, $rest);
}

sub unary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $value  = $self->statement($context, $data->[1]);

        if ($self->{debug} and $debug_msg) {
            $debug_msg =~ s/\$a/$value->[1] ($value->[0])/g;
            $self->{dprint}->('OPERS', "$debug_msg\n") if $self->{debug};
        }

        if ($self->is_arithmetic_type($value)) {
            if (exists $self->{eval_unary_op_NUM}->{$op}) {
                return $self->{eval_unary_op_NUM}->{$op}->($value->[1]);
            }
        }

        # infer type
        if ($value->[0] eq 'Any') {
            if (exists $self->{eval_unary_op_ANY}->{$op}) {
                return $self->{eval_unary_op_ANY}->{$op}->($value->[1]);
            }
        }

        $self->error($context, "cannot apply unary operator $op to type " . $self->pretty_type($value) . "\n");
    }

    return;
}

sub binary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $left_value  = $self->statement($context, $data->[1]);
        my $right_value = $self->statement($context, $data->[2]);

        if ($self->{debug} and $debug_msg) {
            $debug_msg =~ s/\$a/$left_value->[1] ($left_value->[0])/g;
            $debug_msg =~ s/\$b/$right_value->[1] ($right_value->[0])/g;
            $self->{dprint}->('OPERS', "$debug_msg\n") if $self->{debug};
        }

        if ($self->is_arithmetic_type($left_value) and $self->is_arithmetic_type($right_value)) {
            if (exists $self->{eval_binary_op_NUM}->{$op}) {
                return $self->{eval_binary_op_NUM}->{$op}->($left_value->[1], $right_value->[1]);
            }
        }

        if ($left_value->[0] eq 'STRING' or $right_value->[0] eq 'STRING') {
            if (exists $self->{eval_binary_op_STRING}->{$op}) {
                $left_value->[1]  = chr $left_value->[1]  if $left_value->[0]  eq 'NUM';
                $right_value->[1] = chr $right_value->[1] if $right_value->[0] eq 'NUM';
                return $self->{eval_binary_op_STRING}->{$op}->($left_value->[1], $right_value->[1]);
            }
        }

        # infer type
        if ($left_value->[0] eq 'Any') {
            if (exists $self->{eval_binary_op_ANY}->{$op}) {
                return $self->{eval_binary_op_ANY}->{$op}->($left_value->[1], $right_value->[1]);
            }
        }

        $self->error($context, "cannot apply binary operator $op (have types " . $self->pretty_type($left_value) . " and " . $self->pretty_type($right_value) . ")");
    }

    return;
}

sub type_check_prefix_postfix_op {
    my ($self, $context, $data, $op) = @_;

    if ($data->[1]->[0] eq 'IDENT' or $data->[1]->[0] eq 'ARRAY_INDEX' && $data->[1]->[1]->[0] eq 'IDENT') {
        my $var = $self->statement($context, $data->[1]);

        if ($self->is_arithmetic_type($var)) {
            return $var;
        }

        if ($var->[0] eq 'Any') {
            return $var;
        }

        $self->error($context, "cannot apply $op to type " . $self->pretty_type($var));
    }

    $self->error($context, "cannot apply $op to type " . $self->pretty_type($data->[1]));
}

sub prefix_increment {
    my ($self, $context, $data) = @_;
    $self->type_check_prefix_postfix_op($context, $data, 'prefix-increment');
}

sub prefix_decrement {
    my ($self, $context, $data) = @_;
    $self->type_check_prefix_postfix_op($context, $data, 'prefix-decrement');
}

sub postfix_increment {
    my ($self, $context, $data) = @_;
    $self->type_check_prefix_postfix_op($context, $data, 'postfix-increment');
}

sub postfix_decrement {
    my ($self, $context, $data) = @_;
    $self->type_check_prefix_postfix_op($context, $data, 'postfix-decrement');
}

sub type_check_op_assign {
    my ($self, $context, $data, $op) = @_;

    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);

    if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
        return $left;
    }

    if ($left->[0] eq 'Any' and $self->is_arithmetic_type($right)) {
        return $left;
    }

    $self->error($context, "cannot apply operator $op (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
}

sub add_assign {
    my ($self, $context, $data) = @_;
    $self->type_check_op_assign($context, $data, 'ADD');
}

sub sub_assign {
    my ($self, $context, $data) = @_;
    $self->type_check_op_assign($context, $data, 'SUB');
}

sub mul_assign {
    my ($self, $context, $data) = @_;
    $self->type_check_op_assign($context, $data, 'MUL');
}

sub div_assign {
    my ($self, $context, $data) = @_;
    $self->type_check_op_assign($context, $data, 'DIV');
}

sub variable_declaration {
    my ($self, $context, $data) = @_;

    my $initializer = $data->[2];
    my $right_value = undef;

    if ($initializer) {
        $right_value = $self->statement($context, $initializer);
    } else {
        $right_value = ['NULL', undef];
    }

    if (!$self->{repl} and (my $var = $self->get_variable($context, $data->[1], locals_only => 1))) {
        if ($var->[0] ne 'BUILTIN') {
            $self->error($context, "cannot redeclare existing local `$data->[1]`");
        }
    }

    if ($self->get_builtin_function($data->[1])) {
        $self->error($context, "cannot override builtin function `$data->[1]`");
    }

    $self->set_variable($context, $data->[1], $right_value);
    return $right_value;
}

sub map_constructor {
    my ($self, $context, $data) = @_;

    my $map     = $data->[1];
    my $hashref = {};

    foreach my $entry (@$map) {
        if ($entry->[0]->[0] eq 'IDENT') {
            my $var = $self->get_variable($context, $entry->[0]->[1]);

            if (not defined $var) {
                $self->error($context, "cannot use undeclared variable `$entry->[0]->[1]` to assign Map key");
            }

            if ($var->[0] eq 'STRING') {
                $hashref->{$var->[1]} = $self->statement($context, $entry->[1]);
                next;
            }

            $self->error($context, "cannot use type `" . $self->pretty_type($var) . "` as Map key");
        }

        if ($entry->[0]->[0] eq 'STRING') {
            $hashref->{$entry->[0]->[1]} = $self->statement($context, $entry->[1]);
            next;
        }

        $self->error($context, "cannot use type `" . $self->pretty_type($entry->[0]) . "` as Map key");
    }

    return ['MAP', $hashref];
}

sub keyword_exists {
    my ($self, $context, $data) = @_;

    # check for key in map
    if ($data->[1]->[0] eq 'ARRAY_INDEX') {
        my $var = $self->statement($context, $data->[1]->[1]);

        # map index
        if ($var->[0] eq 'MAP') {
            my $key = $self->statement($context, $data->[1]->[2]);

            if ($key->[0] eq 'STRING') {
                if (exists $var->[1]->{$key->[1]}) {
                    return ['BOOL', 1];
                } else {
                    return ['BOOL', 0];
                }
            }

            $self->error($context, "Map key must be of type String (got " . $self->pretty_type($key) . ")");
        }

        $self->error($context, "exists must be used on Maps (got " . $self->pretty_type($var) . ")");
    }

    $self->error($context, "exists must be used on Maps (got " . $self->pretty_type($data->[1]) . ")");
}

sub keyword_delete {
    my ($self, $context, $data) = @_;

    # delete one key in map
    if ($data->[1]->[0] eq 'ARRAY_INDEX') {
        my $var = $self->statement($context, $data->[1]->[1]);

        # map index
        if ($var->[0] eq 'MAP') {
            my $key = $self->statement($context, $data->[1]->[2]);

            if ($key->[0] eq 'STRING') {
                my $val = delete $var->[1]->{$key->[1]};
                return ['NULL', undef] if not defined $val;
                return $val;
            }

            $self->error($context, "Map key must be of type String (got " . $self->pretty_type($key) . ")");
        }

        $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($var) . ")");
    }

    # delete all keys in map
    if ($data->[1]->[0] eq 'IDENT') {
        my $var = $self->get_variable($context, $data->[1]->[1]);

        if ($var->[0] eq 'MAP') {
            $var->[1] = {};
            return $var;
        }

        $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($var) . ")");
    }

    $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($data->[1]) . ")");
}

sub function_definition {
    my ($self, $context, $data) = @_;

    my $ret_type   = $data->[1];
    my $name       = $data->[2];
    my $parameters = $data->[3];
    my $statements = $data->[4];

    my $func = ['FUNC', [$context, $ret_type, $parameters, $statements]];

    if ($name eq '#anonymous') {
        $name = "anonfunc$func";
    }

    if (!$self->{repl} and exists $context->{locals}->{$name} and $context->{locals}->{$name}->[0] ne 'BUILTIN') {
        $self->error($context, "cannot define function `$name` with same name as existing local");
    }

    if ($self->get_builtin_function($name)) {
        $self->error($context, "cannot redefine builtin function `$name`");
    }

    $context->{locals}->{$name} = $func;

    my $new_context = $self->new_context($context);
    my $got_default_value = 0;

    foreach my $param (@$parameters) {
        my ($type, $ident, $default_value) = @$param;

        my $value = $self->statement($new_context, $default_value);

        if (not defined $value) {
            if ($got_default_value) {
                $self->error($new_context, "in definition of function `$name`: missing default value for parameter `$ident` after previous parameter was declared with default value");
            }
        } else {
            $got_default_value = 1;

            if ($type ne 'Any' and $type ne $self->pretty_type($value)) {
                $self->error($new_context, "in definition of function `$name`: parameter `$ident` declared as $type but default value has type " . $self->pretty_type($value));
            }
        }
    }

    return $func;
}

sub validate_types {
	my ($self, $type1, $type2) = @_;

	if (ref($type1) eq 'ARRAY' and ref($type2) eq 'ARRAY') {
		# function/builtin
		for (my $i = 0; $i < @$type1; $i++) {
			if ($type1->[$i] ne 'ANY' and $type1->[$i] ne $type2->[$i]) {
				return 0;
			}
		}
	}

	elsif (ref($type1 eq 'ARRAY')) {
		return 0;
	}

	elsif ($type1 ne 'ANY' and $type1 ne $type2) {
		return 0;
	}

	return 1;
}

sub validate_function_argument_type {
    my ($self, $context, $name, $parameter, $arg_type, %opts) = @_;

    my $type1 = $self->parse_pretty_type($parameter->[0]);
    my $type2 = $self->parse_pretty_type($arg_type);

    my $valid = 1;

    for (my $i = 0; $i < @$type1; $i++) {
        if (not $self->validate_types($type1->[$i], $type2->[$i])) {
            $valid = 0;
            last;
        }
    }

    if (not $valid) {
        $self->error($context, "in function call for `$name`, expected $parameter->[0] for parameter `$parameter->[1]` but got " . $arg_type);
    }
}

sub process_function_call_arguments {
    my ($self, $context, $name, $parameters, $arguments, $data) = @_;

    if (@$arguments > @$parameters) {
        $self->error($context, "extra arguments provided to function `$name` (takes " . @$parameters . " but passed " . @$arguments . ")");
    }

    my $evaluated_arguments;
    my $processed_arguments = [];

    for (my $i = 0; $i < @$arguments; $i++) {
        my $arg = $arguments->[$i];
        if ($arg->[0] eq 'ASSIGN') {
            # named argument
            if (not defined $parameters->[$i]->[2]) {
                # ensure positional arguments are filled first
                $self->error($context, "positional parameter `$parameters->[$i]->[1]` must be filled before using named argument");
            }

            my $named_arg = $arguments->[$i]->[1];
            my $value     = $arguments->[$i]->[2];

            if ($named_arg->[0] eq 'IDENT') {
                my $ident = $named_arg->[1];

                my $found = 0;
                for (my $j = 0; $j < @$parameters; $j++) {
                    if ($parameters->[$j]->[1] eq $ident) {
                        $processed_arguments->[$j] = $value;
                        $evaluated_arguments->[$j] = $self->statement($context, $value);
                        $context->{locals}->{$parameters->[$j]->[1]} = $evaluated_arguments->[$j];
                        $found = 1;
                        last;
                    }
                }

                if (not $found) {
                    $self->error($context, "function `$name` has no parameter named `$ident`");
                }
            } else {
                $self->error($context, "named argument must be an identifier (got " . $self->pretty_type($named_arg) . ")");
            }
        } else {
            # normal argument
            $processed_arguments->[$i] = $arg;
            $evaluated_arguments->[$i] = $self->statement($context, $arg);
            $context->{locals}->{$parameters->[$i]->[1]} = $evaluated_arguments->[$i];
        }
    }

    for (my $i = 0; $i < @$parameters; $i++) {
        if (defined $evaluated_arguments->[$i]) {
            next;
        }

        if (defined $parameters->[$i]->[2]) {
            # found default argument
            $processed_arguments->[$i] = $parameters->[$i]->[2];
            $evaluated_arguments->[$i] = $self->statement($context, $parameters->[$i]->[2]);
            $context->{locals}->{$parameters->[$i]->[1]} = $evaluated_arguments->[$i];
        } else {
            # no argument or default argument
            if (not defined $evaluated_arguments->[$i]) {
                $self->error($context, "Missing argument `$parameters->[$i]->[1]` to function `$name`."),
            }
        }
    }

    for (my $i = 0; $i < @$parameters; $i++) {
        if (not defined $evaluated_arguments->[$i]) {
            $self->error($context, "missing argument `$parameters->[$i]->[1]` to function `$name`.");
        }
    }

    # rewrite CALL arguments with positional arguments
    $data->[2] = $processed_arguments;
    return $evaluated_arguments;
}

sub type_check_builtin_function {
    my ($self, $context, $data, $name) = @_;

    my $builtin = $self->get_builtin_function($name);

    my $parameters = $builtin->{params};
    my $func       = $builtin->{subref};
    my $arguments  = $data->[2];

    my $evaled_args = $self->process_function_call_arguments($context, $name, $parameters, $arguments);

    # invoke builtin-in to infer types
    my $result = $func->($self, $context, $name, $evaled_args);

    # type-check arguments
    for (my $i = 0; $i < @$parameters; $i++) {
        $self->validate_function_argument_type($context, $name, $parameters->[$i], $self->pretty_type($evaled_args->[$i]));
    }

    return $result;
}

sub function_call {
    my ($self, $context, $data) = @_;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;
    my $name;

    if ($target->[0] eq 'IDENT') {
        $self->{dprint}->('FUNCS', "Calling function `$target->[1]` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $name = $target->[1];
        $func = $self->get_variable($context, $target->[1]);
        $func = undef if defined $func and $func->[0] eq 'BUILTIN';
    } elsif ($target->[0] eq 'FUNC') {
        $func = $target;
        $name = "anonymous-1";
    } else {
        $self->{dprint}->('FUNCS', "Calling anonymous function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->statement($context, $target);
        $name = "anonymous-2";
    }

    my $return;
    my $closure;
    my $ret_type;
    my $parameters;
    my $statements;

    if (defined $func) {
        if ($func->[0] ne 'FUNC') {
            $self->error($context, "cannot invoke `" . $self->output_value($func) . "` as a function (have type " . $self->pretty_type($func) . ")");
        }

        $closure    = $func->[1]->[0];
        $ret_type   = $func->[1]->[1];
        $parameters = $func->[1]->[2];
        $statements = $func->[1]->[3];
    } else {
        if ($target->[0] eq 'IDENT') {
            if (defined ($func = $self->get_builtin_function($target->[1]))) {
                # builtin function
                $ret_type = $func->{ret};

                if ($target->[1] eq 'print') {
                    # skip builtin print() call
                    $return = ['NULL', undef];
                } elsif ($target->[1] eq 'filter' or $target->[1] eq 'map') {
                    $return = $self->type_check_builtin_function($context, $data, $target->[1]);
                } else {
                    $return = $self->call_builtin_function($context, $data, $target->[1]);
                }
                goto CHECK_RET_TYPE;
            } else {
                # undefined function
                $self->error($context, "cannot invoke undefined function `" . $self->output_value($target) . "`.");
            }
        } else {
            print "unknown thing: ", Dumper($target), "\n";
        }
    }

    my $new_context = $self->new_context($closure);
    $new_context->{locals} = { %{$context->{locals}} };
    $new_context = $self->new_context($new_context);

    my $evaled_args = $self->process_function_call_arguments($new_context, $target->[1], $parameters, $arguments, $data);

    foreach my $stmt (@$statements) {
        if ($stmt->[0] eq 'RET') {
            $return = $self->statement($new_context, $stmt->[1]);
            goto CHECK_RET_TYPE;
        }

        if ($stmt->[0] eq 'CALL') {
            # skip function calls
            next;
        }

        $return = $self->statement($new_context, $stmt);
    }

  CHECK_RET_TYPE:
    if ($ret_type ne 'Any' and $ret_type ne $self->pretty_type($return)) {
        $self->error($context, "cannot return " . $self->pretty_type($return) . " from function declared to return " . $ret_type);
    }

    if ($ret_type eq 'Any') {
        # set inferred return type
        $func->[1]->[1] = $self->pretty_type($return);
    }

    # type-check arguments after inference
    if (defined $parameters) {
        for (my $i = 0; $i < @$parameters; $i++) {
            $self->validate_function_argument_type($context, $name, $parameters->[$i], $self->pretty_type($evaled_args->[$i]));
        }
    }

    return $return;
}

sub keyword_next {
    my ($self, $context, $data) = @_;
    $self->error($context, "cannot use `next` outside of loop");
}

sub keyword_last {
    my ($self, $context, $data) = @_;
    $self->error($context, "cannot use `last` outside of loop");
}

sub keyword_return {
    my ($self, $context, $data) = @_;
    $self->error($context, "cannot use `return` outside of function");
}

sub conditional {
    my ($self, $context, $data) = @_;

    if ($self->is_truthy($context, $data->[1])) {
        return $self->statement($context, [$data->[2]]);
    } else {
        return $self->statement($context, [$data->[3]]);
    }
}

sub keyword_if {
    my ($self, $context, $data) = @_;

    # validate conditional
    my $result = $self->statement($context, $data->[1]);

    # validate then
    $result = $self->statement($context, $data->[2]);

    # validate else
    $result = $self->statement($context, $data->[3]);

    return ['NULL', undef];
}

sub keyword_while {
    my ($self, $context, $data) = @_;

    # validate conditional
    my $result = $self->statement($context, $data->[1]);

    # validate statements
    $result = $self->statement($context, $data->[2]);

    return ['NULL', undef];
}

# lvalue assignment
sub assignment {
    my ($self, $context, $data) = @_;

    my $left_value  = $data->[1];
    my $right_value = $self->statement($context, $data->[2]);

    # lvalue variable
    if ($left_value->[0] eq 'IDENT') {
        my $var = $self->get_variable($context, $left_value->[1]);
        $self->error($context, "cannot assign to undeclared variable `$left_value->[1]`") if not defined $var;
        $self->set_variable($context, $left_value->[1], $right_value);
        return $right_value;
    }

    # lvalue array index
    if ($left_value->[0] eq 'ARRAY_INDEX') {
        my $var = $self->statement($context, $left_value->[1]);

        if ($var->[0] eq 'MAP') {
            my $key = $self->statement($context, $left_value->[2]);

            if ($key->[0] eq 'STRING') {
                my $val = $self->statement($context, $right_value);
                $var->[1]->{$key->[1]} = $val;
                return $val;
            }

            $self->error($context, "Map key must be of type String (got " . $self->pretty_type($key) . ")");
        }

        if ($var->[0] eq 'ARRAY') {
            my $index = $self->statement($context, $left_value->[2]);

            if ($index->[0] eq 'NUM') {
                my $val = $self->statement($context, $right_value);
                $var->[1]->[$index->[1]] = $val;
                return $val;
            }

            $self->error($context, "Array index must be of type Number (got " . $self->pretty_type($index) . ")");
        }

        if ($var->[0] eq 'STRING') {
            my $value = $self->statement($context, $left_value->[2]->[1]);

            if ($value->[0] eq 'RANGE') {
                my $from = $value->[1];
                my $to   = $value->[2];

                if ($from->[0] eq 'NUM' and $to->[0] eq 'NUM') {
                    if ($right_value->[0] eq 'STRING') {
                        substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = $right_value->[1];
                        return ['STRING', $var->[1]];
                    }

                    if ($right_value->[0] eq 'NUM') {
                        substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = chr $right_value->[1];
                        return ['STRING', $var->[1]];
                    }

                    $self->error($context, "cannot assign from type " . $self->pretty_type($right_value) . " to type " . $self->pretty_type($left_value) . " with RANGE in postfix []");
                }

                $self->error($context, "invalid types to RANGE (have " . $self->pretty_type($from) . " and " . $self->pretty_type($to) . ") inside assignment postfix []");
            }

            if ($value->[0] eq 'NUM') {
                my $index = $value->[1];
                if ($right_value->[0] eq 'STRING') {
                    substr ($var->[1], $index, 1) = $right_value->[1];
                    return ['STRING', $var->[1]];
                }

                if ($right_value->[0] eq 'NUM') {
                    substr ($var->[1], $index, 1) = chr $right_value->[1];
                    return ['STRING', $var->[1]];
                }

                $self->error($context, "cannot assign from type " . $self->pretty_type($right_value) . " to type " . $self->pretty_type($left_value) . " with postfix []");
            }

            $self->error($context, "invalid type " . $self->pretty_type($value) . " inside assignment postfix []");
        }

        $self->error($context, "cannot assign to postfix [] on type " . $self->pretty_type($var));
    }

    # a statement
    my $eval = $self->statement($context, $data->[1]);
    $self->error($context, "cannot assign to non-lvalue type " . $self->pretty_type($eval));
}

# rvalue array/map index
sub array_index_notation {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    # infer type
    if ($var->[0] eq 'Any') {
        return $var;
    }

    # map index
    if ($var->[0] eq 'MAP') {
        my $key = $self->statement($context, $data->[2]);

        if ($key->[0] eq 'STRING') {
            my $val = $var->[1]->{$key->[1]};
            return ['NULL', undef] if not defined $val;
            return $val;
        }

        $self->error($context, "Map key must be of type String (got " . $self->pretty_type($key) . ")");
    }

    # array index
    if ($var->[0] eq 'ARRAY') {
        my $index = $self->statement($context, $data->[2]);

        # number index
        if ($index->[0] eq 'NUM') {
            my $val = $var->[1]->[$index->[1]];
            return ['NULL', undef] if not defined $val;
            return $val;
        }

        # TODO support RANGE and x:y splices and negative indexing

        $self->error($context, "Array index must be of type Number (got " . $self->pretty_type($index) . ")");
    }

    # string index
    if ($var->[0] eq 'STRING') {
        my $value = $self->statement($context, $data->[2]->[1]);

        if ($value->[0] eq 'RANGE') {
            my $from = $value->[1];
            my $to = $value->[2];

            if ($from->[0] eq 'NUM' and $to->[0] eq 'NUM') {
                return ['STRING', substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1])];
            }

            $self->error($context, "invalid types to RANGE (have " . $self->pretty_type($from) . " and " . $self->pretty_type($to) . ") inside postfix []");
        }

        if ($value->[0] eq 'NUM') {
            my $index = $value->[1];
            return ['STRING', substr($var->[1], $index, 1) // ""];
        }

        $self->error($context, "invalid type " . $self->pretty_type($value) . " inside postfix []");
    }

    $self->error($context, "cannot use postfix [] on type " . $self->pretty_type($var));
}

sub function_builtin_length {
     my ($self, $context, $name, $arguments) = @_;
     my ($val) = ($arguments->[0]);

     my $type = $val->[0];

     if ($type ne 'STRING' and $type ne 'ARRAY' and $type ne 'MAP') {
         $self->error($context, "cannot get length of a " . $self->pretty_type($val));
     }

     return ['NUM', 0];
}

sub function_builtin_map {
    my ($self, $context, $name, $arguments) = @_;
    my ($func, $list) = ($arguments->[0], $arguments->[1]);

    my $data = ['CALL', $func, [['Any', undef]]];
	my $result = $self->function_call($context, $data);
    return ['ARRAY', $result];
}

sub function_builtin_filter {
    my ($self, $context, $name, $arguments) = @_;
    my ($func, $list) = ($arguments->[0], $arguments->[1]);

    my $data = ['CALL', $func, [['Any', undef]]];
	my $result = $self->function_call($context, $data);
    return ['ARRAY', $result];
}

sub handle_statement_result {
    my ($self, $result) = @_;
    return $result;
}

# validate the program
sub validate {
    my ($self, $ast) = @_;

    # override builtins for typechecking
    $self->add_builtin_function('length',
        [['Any', 'expr']],
        'Number',
        \&function_builtin_length);

    $self->add_builtin_function('map',
        [['Function (Any) -> Any', 'func', undef], ['Array', 'list', undef]],
        'Array',
        \&function_builtin_map);

    $self->add_builtin_function('filter',
        [['Function (Any) -> Boolean', 'func', undef], ['Array', 'list', undef]],
        'Array',
        \&function_builtin_filter);

    my $result = $self->run($ast, typecheck => 1);
    return if not defined $result;
    return if $result->[0] ne 'ERROR';
    return $result;
}

1;
