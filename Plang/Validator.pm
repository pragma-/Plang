#!/usr/bin/env perl

# Validates a Plang syntax tree by performing static type-checking,
# semantic-analysis, etc, so the interpreter need not concern itself
# with these potentially expensive operations.

package Plang::Validator;

use warnings;
use strict;

use parent 'Plang::AstInterpreter';

use Data::Dumper;

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

        $self->error($context, "cannot apply binary operator $op (have types " . $self->pretty_type($left_value) . " and " . $self->pretty_type($right_value) . ")");
    }

    return;
}

sub prefix_increment {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    if ($self->is_arithmetic_type($var)) {
        $var->[1]++;
        return $var;
    }

    $self->error($context, "cannot apply prefix-increment to type " . $self->pretty_type($var));
}

sub prefix_decrement {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    if ($self->is_arithmetic_type($var)) {
        $var->[1]--;
        return $var;
    }

    $self->error($context, "cannot apply prefix-decrement to type " . $self->pretty_type($var));
}

sub postfix_increment {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    if ($self->is_arithmetic_type($var)) {
        my $temp_var = [$var->[0], $var->[1]];
        $var->[1]++;
        return $temp_var;
    }

    $self->error($context, "cannot apply postfix-increment to type " . $self->pretty_type($var));
}

sub postfix_decrement {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    if ($self->is_arithmetic_type($var)) {
        my $temp_var = [$var->[0], $var->[1]];
        $var->[1]--;
        return $temp_var;
    }

    $self->error($context, "cannot apply postfix-decrement to type " . $self->pretty_type($var));
}

sub add_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);

    if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
        $left->[1] += $right->[1];
        return $left;
    }

    $self->error($context, "cannot apply operator ADD (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
}

sub sub_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);

    if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
        $left->[1] -= $right->[1];
        return $left;
    }

    $self->error($context, "cannot apply operator SUB (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
}

sub mul_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);

    if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
        $left->[1] *= $right->[1];
        return $left;
    }

    $self->error($context, "cannot apply operator MUL (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
}

sub div_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);

    if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
        $left->[1] /= $right->[1];
        return $left;
    }

    $self->error($context, "cannot apply operator DIV (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
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

sub validate_function_argument_type {
    my ($self, $context, $name, $parameter, $arg_type) = @_;

    if ($parameter->[0] ne 'Any' and $parameter->[0] ne $arg_type) {
        $self->error($context, "in function call for `$name`, expected " . $self->pretty_type($parameter)
            . " for parameter `$parameter->[1]` but got " . $arg_type);
    }
}

sub process_function_call_arguments {
    my ($self, $context, $name, $parameters, $arguments, $data) = @_;

    if (@$arguments > @$parameters) {
        $self->error($context, "Extra arguments provided to function `$name` (takes " . @$parameters . " but passed " . @$arguments . ")");
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
                        $self->validate_function_argument_type($context, $name, $parameters->[$j], $self->pretty_type($evaluated_arguments->[$j]));
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
            $self->validate_function_argument_type($context, $name, $parameters->[$i], $self->pretty_type($evaluated_arguments->[$i]));
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

    # don't actually invoke builtin function; return an object of its return-type instead
    return [$builtin->{ret}, undef];
}


sub function_call {
    my ($self, $context, $data) = @_;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;

    if ($target->[0] eq 'IDENT') {
        $self->{dprint}->('FUNCS', "Calling function `$target->[1]` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->get_variable($context, $target->[1]);
        $func = undef if defined $func and $func->[0] eq 'BUILTIN';
    } elsif ($target->[0] eq 'FUNC') {
        $func = $target;
    } else {
        $self->{dprint}->('FUNCS', "Calling anonymous function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->statement($context, $target);
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

    # process args and validate types
    $self->process_function_call_arguments($new_context, $target->[1], $parameters, $arguments, $data);

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

sub keyword_if {
    my ($self, $context, $data) = @_;

    # validate conditional
    my $result = $self->statement($context, $data->[1]);
    return $result if defined $result and $result->[0] eq 'ERROR';

    # validate then
    $result = $self->statement($context, $data->[2]);
    return $result if defined $result and $result->[0] eq 'ERROR';

    # validate else
    $result = $self->statement($context, $data->[3]);
    return $result if defined $result and $result->[0] eq 'ERROR';

    return ['NULL', undef];
}

sub keyword_while {
    my ($self, $context, $data) = @_;

    # validate conditional
    my $result = $self->statement($context, $data->[1]);
    return $result if defined $result and $result->[0] eq 'ERROR';

    # validate statements
    $result = $self->statement($context, $data->[2]);
    return $result if defined $result and $result->[0] eq 'ERROR';

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

sub handle_statement_result {
    my ($self, $result) = @_;
    return $result;
}

# validate the program
sub validate {
    my ($self, $ast) = @_;
    my $result = $self->run($ast); # invoke AstInterpreter's run()
    return if not defined $result;
    return if $result->[0] ne 'ERROR';
    return $result;
}

1;
