#!/usr/bin/env perl

# Validates a Plang syntax tree by performing static type-checking,
# semantic-analysis, etc, so the interpreter need not concern itself
# with these potentially expensive operations.

package Plang::Validator;

use warnings;
use strict;

use parent 'Plang::AstInterpreter';

use Data::Dumper;

sub unary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $value  = $self->statement($context, $data->[1]);

        if ($self->{debug} and $debug_msg) {
            $debug_msg =~ s/\$a/$value->[1] ($value->[0])/g;
            $self->{dprint}->('OPERS', "$debug_msg\n") if $self->{debug};
        }

        if ($self->{types}->is_arithmetic($value->[0])) {
            if (exists $self->{eval_unary_op_Number}->{$op}) {
                my $result = $self->{eval_unary_op_Number}->{$op}->($value->[1]);

                if ($self->{types}->is_subtype($value->[0], $result->[0])) {
                    $result->[0] = $value->[0];
                }

                return $result;
            }
        }

        $self->error($context, "cannot apply unary operator $op to type " . $self->{types}->to_string($value->[0]) . "\n");
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

        if ($self->{types}->check(['TYPE', 'String'], $left_value->[0]) or $self->{types}->check(['TYPE', 'String'], $right_value->[0])) {
            if (exists $self->{eval_binary_op_String}->{$op}) {
                $left_value->[1]  = chr $left_value->[1]  if $self->{types}->check(['TYPE', 'Number'], $left_value->[0],);
                $right_value->[1] = chr $right_value->[1] if $self->{types}->check(['TYPE', 'Number'], $right_value->[0]);
                return $self->{eval_binary_op_String}->{$op}->($left_value->[1], $right_value->[1]);
            }
        }

        if (not $self->{types}->is_arithmetic($left_value->[0])) {
            $self->error($context, "cannot apply operator $op to non-arithmetic type " . $self->{types}->to_string($left_value->[0]));
        }

        if (not $self->{types}->is_arithmetic($right_value->[0])) {
            $self->error($context, "cannot apply operator $op to non-arithmetic type " . $self->{types}->to_string($right_value->[0]));
        }

        if ($self->{types}->check($left_value->[0], $right_value->[0])) {
            if (exists $self->{eval_binary_op_Number}->{$op}) {
                my $result = $self->{eval_binary_op_Number}->{$op}->($left_value->[1], $right_value->[1]);

                if ($self->{types}->is_subtype($left_value->[0], $result->[0])) {
                    $result->[0] = $left_value->[0];
                }

                return $result;
            }
        }

        $self->error($context, "cannot apply binary operator $op (have types " . $self->{types}->to_string($left_value->[0]) . " and " . $self->{types}->to_string($right_value->[0]) . ")");
    }

    return;
}

sub type_check_prefix_postfix_op {
    my ($self, $context, $data, $op) = @_;

    if ($data->[1]->[0] eq 'IDENT' or $data->[1]->[0] eq 'ACCESS' && $data->[1]->[1]->[0] eq 'IDENT') {
        my $var = $self->statement($context, $data->[1]);

        if ($self->{types}->is_arithmetic($var->[0])) {
            return $var;
        }

        $self->error($context, "cannot apply $op to type " . $self->{types}->to_string($var->[0]));
    }

    if ($data->[1]->[0] eq 'LITERAL') {
        $self->error($context, "cannot apply $op to a " . $self->{types}->to_string($data->[1]->[1]) . " literal");
    }

    if (ref ($data->[1]->[0]) ne 'ARRAY') {
        $self->error($context, "cannot apply $op to instruction " . $data->[1]->[0]);
    }

    $self->error($context, "cannot apply $op to type " . $self->{types}->to_string($data->[1]->[0]));
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

    my $left  = $data->[1];
    my $right = $data->[2];

    if ($left->[0] eq 'LITERAL') {
        $self->error($context, "cannot assign to " . $self->{types}->to_string($left->[1]) . " literal");
    }

    $left  = $self->statement($context, $left);
    $right = $self->statement($context, $right);

    if (not $self->{types}->is_arithmetic($left->[0])) {
        $self->error($context, "cannot apply operator $op to non-arithmetic type " . $self->{types}->to_string($left->[0]));
    }

    if (not $self->{types}->is_arithmetic($right->[0])) {
        $self->error($context, "cannot apply operator $op to non-arithmetic type " . $self->{types}->to_string($right->[0]));
    }

    if ($self->{types}->check($left->[0], $right->[0])) {
        return $left;
    }

    $self->error($context, "cannot apply operator $op (have types " . $self->{types}->to_string($left->[0]) . " and " . $self->{types}->to_string($right->[0]) . ")");
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

    my $type        = $data->[1];
    my $name        = $data->[2];
    my $initializer = $data->[3];
    my $right_value = undef;

    if ($initializer) {
        $right_value = $self->statement($context, $initializer);
    } else {
        $right_value = [['TYPE', 'Null'], undef];
    }

    if (!$self->{repl} and (my $var = $self->get_variable($context, $name, locals_only => 1))) {
        if ($var->[0] ne 'Builtin') {
            $self->error($context, "cannot redeclare existing local `$name`");
        }
    }

    if ($self->get_builtin_function($name)) {
        $self->error($context, "cannot override builtin function `$name`");
    }

    if (not $self->{types}->check($type, $right_value->[0])) {
        $self->error($context, "cannot initialize `$name` with value of type "
            . $self->{types}->to_string($right_value->[0])
            . " (expected " . $self->{types}->to_string($type) . ")");
    }

    if ($self->{types}->check($type, ['TYPE', 'Any'])) {
        # narrow type to initialized value type
        $type = $right_value->[0];
    }

    $self->declare_variable($context, $type, $name, $right_value);
    return $right_value;
}

sub set_variable {
    my ($self, $context, $name, $value) = @_;

    $self->{dprint}->('VARS', "set_variable $name\n" . Dumper($context) . "\n") if $self->{debug};

    my $guard = $context->{guards}->{$name};

    if (defined $guard and not $self->{types}->check($guard, $value->[0])) {
        $self->error($context, "cannot assign to `$name` a value of type "
            . $self->{types}->to_string($value->[0])
            . " (expected " . $self->{types}->to_string($guard) . ")");
    }

    $context->{locals}->{$name} = $value;
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

            if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
                $hashref->{$var->[1]} = $self->statement($context, $entry->[1]);
                next;
            }

            $self->error($context, "cannot use type `" . $self->{types}->to_string($var->[0]) . "` as Map key");
        }

        if ($self->{types}->check(['TYPE', 'String'], $entry->[0]->[0])) {
            $hashref->{$entry->[0]->[1]} = $self->statement($context, $entry->[1]);
            next;
        }

        $self->error($context, "cannot use type `" . $self->{types}->to_string($entry->[0]->[0]) . "` as Map key");
    }

    return [['TYPE', 'Map'], $hashref];
}

sub keyword_exists {
    my ($self, $context, $data) = @_;

    # check for key in map
    if ($data->[1]->[0] eq 'ACCESS') {
        my $var = $self->statement($context, $data->[1]->[1]);

        # map index
        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->statement($context, $data->[1]->[2]);

            if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
                if (exists $var->[1]->{$key->[1]}) {
                    return [['TYPE', 'Boolean'], 1];
                } else {
                    return [['TYPE', 'Boolean'], 0];
                }
            }

            $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")");
        }

        $self->error($context, "exists must be used on Maps (got " . $self->{types}->to_string($var->[0]) . ")");
    }

    $self->error($context, "exists must be used on Maps (got " . $self->{types}->to_string($data->[1]->[0]) . ")");
}

sub keyword_delete {
    my ($self, $context, $data) = @_;

    # delete one key in map
    if ($data->[1]->[0] eq 'ACCESS') {
        my $var = $self->statement($context, $data->[1]->[1]);

        # map index
        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->statement($context, $data->[1]->[2]);

            if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
                my $val = delete $var->[1]->{$key->[1]};
                return [['TYPE', 'Null'], undef] if not defined $val;
                return $val;
            }

            $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")");
        }

        $self->error($context, "delete must be used on Maps (got " . $self->{types}->to_string($var->[0]) . ")");
    }

    # delete all keys in map
    if ($data->[1]->[0] eq 'IDENT') {
        my $var = $self->get_variable($context, $data->[1]->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            $var->[1] = {};
            return $var;
        }

        $self->error($context, "delete must be used on Maps (got " . $self->{types}->to_string($var->[0]) . ")");
    }

    $self->error($context, "delete must be used on Maps (got " . $self->{types}->to_string($data->[1]->[0]) . ")");
}

sub function_definition {
    my ($self, $context, $data) = @_;

    my $ret_type   = $data->[1];
    my $name       = $data->[2];
    my $parameters = $data->[3];
    my $statements = $data->[4];

    my $param_types = [];
    my $func_type   = ['TYPEFUNC', 'Function', $param_types, $ret_type];
    my $func_data   = [$context, $ret_type, $parameters, $statements];
    my $func        = [$func_type, $func_data];

    if ($name eq '#anonymous') {
        $name = "anonfunc$func";
    }

    if (!$self->{repl} and exists $context->{locals}->{$name} and $context->{locals}->{$name}->[0] ne 'Builtin') {
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

        push @$param_types, $type;

        my $value = $self->statement($new_context, $default_value);

        if (not defined $value) {
            if ($got_default_value) {
                $self->error($new_context, "in definition of function `$name`: missing default value for parameter `$ident` after previous parameter was declared with default value");
            }
        } else {
            $got_default_value = 1;

            if (not $self->{types}->check($type, $value->[0])) {
                $self->error($new_context, "in definition of function `$name`: parameter `$ident` declared as " . $self->{types}->to_string($type) . " but default value has type " . $self->{types}->to_string($value->[0]));
            }
        }
    }

    return $func;
}

sub validate_function_argument_type {
    my ($self, $context, $name, $parameter, $arg_type, %opts) = @_;

    my $type1 = $parameter->[0];
    my $type2 = $arg_type;

    if (not $self->{types}->check($type1, $type2)) {
        $self->error($context, "in function call for `$name`, expected " . $self->{types}->to_string($parameter->[0]) . " for parameter `$parameter->[1]` but got " . $self->{types}->to_string($arg_type));
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
                $self->error($context, "named argument must be an identifier (got " . $self->{types}->to_string($named_arg->[0]) . ")");
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
    my $validate   = $builtin->{vsubref};
    my $arguments  = $data->[2];

    my $evaled_args = $self->process_function_call_arguments($context, $name, $parameters, $arguments);

    for (my $i = 0; $i < @$parameters; $i++) {
        $self->validate_function_argument_type($context, $name, $parameters->[$i], $evaled_args->[$i]->[0]);
    }

    my $result;

    if ($validate) {
        $result = $validate->($self, $context, $name, $evaled_args);
    } else {
        $result = $func->($self, $context, $name, $evaled_args);
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
        $func = undef if defined $func and $func->[0]->[0] eq 'TYPEFUNC' and $func->[0]->[1] eq 'Builtin';
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
        $func = $target;
        $name = "anonymous-1";
    } else {
        $self->{dprint}->('FUNCS', "Calling anonymous function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->statement($context, $target);
        $name = "anonymous-2";
    }

    my $closure;       # function's closure context
    my $return_type;   # function signature's return type
    my $parameters;    # function signature's parameters
    my $statements;    # function's statements
    my $return_value;  # value returned from function

    if (defined $func) {
        if (not $self->{types}->name_is($func->[0], 'TYPEFUNC')) {
            $self->error($context, "cannot invoke `" . $self->output_value($func) . "` as a function (have type " . $self->{types}->to_string($func->[0]) . ")");
        }

        $closure     = $func->[1]->[0];
        $return_type = $func->[1]->[1];
        $parameters  = $func->[1]->[2];
        $statements  = $func->[1]->[3];
    } else {
        if ($target->[0] eq 'IDENT') {
            $self->{dprint}->('FUNCS', "Calling builtin function `$target->[1]` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
            if (defined ($func = $self->get_builtin_function($target->[1]))) {
                # builtin function
                $return_type  = $func->{ret};
                $return_value = $self->type_check_builtin_function($context, $data, $target->[1]);
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
            $return_value = $self->statement($new_context, $stmt->[1]);
            goto CHECK_RET_TYPE;
        }

        if ($stmt->[0] eq 'CALL') {
            # skip function calls
            next;
        }

        $return_value = $self->statement($new_context, $stmt);
    }

  CHECK_RET_TYPE:
    if ($self->{types}->is_subtype($return_type, $return_value->[0])) {
        $return_value->[0] = $return_type;
    }

    if (not $self->{types}->check($return_type, $return_value->[0])) {
        $self->error($context, "cannot return " . $self->{types}->to_string($return_value->[0]) . " from function declared to return " . $self->{types}->to_string($return_type));
    }

    if ($self->{types}->check($return_type, ['TYPE', 'Any'])) {
        # set inferred return type
        $func->[1]->[1] = $return_value->[0];
        $func->[0]->[3] = $return_value->[0];
    }

    # type-check arguments after inference
    if (defined $parameters) {
        for (my $i = 0; $i < @$parameters; $i++) {
            $self->validate_function_argument_type($context, $name, $parameters->[$i], $evaled_args->[$i]->[0]);
        }
    }

    return $return_value;
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

    return [['TYPE', 'Null'], undef];
}

sub keyword_while {
    my ($self, $context, $data) = @_;

    # validate conditional
    my $result = $self->statement($context, $data->[1]);

    # validate statements
    $result = $self->statement($context, $data->[2]);

    return [['TYPE', 'Null'], undef];
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

    # lvalue array/map access
    if ($left_value->[0] eq 'ACCESS') {
        my $var = $self->statement($context, $left_value->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->statement($context, $left_value->[2]);

            if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
                my $val = $self->statement($context, $right_value);
                $var->[1]->{$key->[1]} = $val;
                return $val;
            }

            $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")");
        }

        if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
            my $index = $self->statement($context, $left_value->[2]);

            if ($self->{types}->check(['TYPE', 'Number'], $index->[0])) {
                my $val = $self->statement($context, $right_value);
                $var->[1]->[$index->[1]] = $val;
                return $val;
            }

            $self->error($context, "Array index must be of type Number (got " . $self->{types}->to_string($index->[0]) . ")");
        }

        if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
            my $value = $self->statement($context, $left_value->[2]->[1]);

            if ($value->[0] eq 'RANGE') {
                my $from = $value->[1];
                my $to   = $value->[2];

                if ($self->{types}->check(['TYPE', 'Number'], $from->[0]) and $self->{types}->check(['TYPE', 'Number'], $to->[0])) {
                    if ($self->{types}->check(['TYPE', 'String'], $right_value->[0])) {
                        substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = $right_value->[1];
                        return [['TYPE', 'String'], $var->[1]];
                    }

                    if ($self->{types}->check(['TYPE', 'Number'], $right_value->[0])) {
                        substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = chr $right_value->[1];
                        return [['TYPE', 'String'], $var->[1]];
                    }

                    $self->error($context, "cannot assign from type " . $self->{types}->to_string($right_value->[0]) . " to type " . $self->{types}->to_string($left_value->[0]) . " with RANGE in postfix []");
                }

                $self->error($context, "invalid types to RANGE (have " . $self->{types}->to_string($from->[0]) . " and " . $self->{types}->to_string($to->[0]) . ") inside assignment postfix []");
            }

            if ($self->{types}->check(['TYPE', 'Number'], $value->[0])) {
                my $index = $value->[1];
                if ($self->{types}->check(['TYPE', 'String'], $right_value->[0])) {
                    substr ($var->[1], $index, 1) = $right_value->[1];
                    return [['TYPE', 'String'], $var->[1]];
                }

                if ($self->{types}->check(['TYPE', 'Number'], $right_value->[0])) {
                    substr ($var->[1], $index, 1) = chr $right_value->[1];
                    return [['TYPE', 'String'], $var->[1]];
                }

                $self->error($context, "cannot assign from type " . $self->{types}->to_string($right_value->[0]) . " to type " . $self->{types}->to_string($left_value->[0]) . " with postfix []");
            }

            $self->error($context, "invalid type " . $self->{types}->to_string($value->[0]) . " inside assignment postfix []");
        }

        $self->error($context, "cannot assign to postfix [] on type " . $self->{types}->to_string($var->[0]));
    }

    # a statement
    my $eval = $self->statement($context, $data->[1]);
    $self->error($context, "cannot assign to non-lvalue type " . $self->{types}->to_string($eval->[0]));
}

# rvalue array/map index
sub array_index_notation {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    # infer type
    if ($self->{types}->check($var->[0], ['TYPE', 'Any'])) {
        return $var;
    }

    # map index
    if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
        my $key = $self->statement($context, $data->[2]);

        if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
            my $val = $var->[1]->{$key->[1]};
            return [['TYPE', 'Null'], undef] if not defined $val;
            return $val;
        }

        $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")");
    }

    # array index
    if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
        my $index = $self->statement($context, $data->[2]);

        # number index
        if ($self->{types}->check(['TYPE', 'Number'], $index->[0])) {
            my $val = $var->[1]->[$index->[1]];
            return [['TYPE', 'Null'], undef] if not defined $val;
            return $val;
        }

        # TODO support RANGE and x:y splices and negative indexing

        $self->error($context, "Array index must be of type Number (got " . $self->{types}->to_string($index->[0]) . ")");
    }

    # string index
    if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
        my $value = $self->statement($context, $data->[2]->[1]);

        if ($value->[0] eq 'RANGE') {
            my $from = $value->[1];
            my $to = $value->[2];

            if ($self->{types}->check(['TYPE', 'Number'], $from->[0]) and $self->{types}->check(['TYPE', 'Number'], $to->[0])) {
                return [['TYPE', 'String'], substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1])];
            }

            $self->error($context, "invalid types to RANGE (have " . $self->{types}->to_string($from->[0]) . " and " . $self->{types}->to_string($to->[0]) . ") inside postfix []");
        }

        if ($self->{types}->check(['TYPE', 'Number'], $value->[0])) {
            my $index = $value->[1];
            return [['TYPE', 'String'], substr($var->[1], $index, 1) // ""];
        }

        $self->error($context, "invalid type " . $self->{types}->to_string($value->[0]) . " inside postfix []");
    }

    $self->error($context, "cannot use postfix [] on type " . $self->{types}->to_string($var->[0]));
}

sub handle_statement_result {
    my ($self, $result) = @_;
    return $result;
}

# validate the program
sub validate {
    my ($self, $ast) = @_;
    $self->run($ast);
    return;
}

1;
