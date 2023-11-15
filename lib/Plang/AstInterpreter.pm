#!/usr/bin/env perl

# Interprets a Plang abstract syntax tree.
#
# Run-time type-checking and semantic validation is kept to a minimum (this
# is handled at compile-time in Validator.pm). The AST is pruned to the
# program data; source file line/col information, etc, is not retained.
#
# The error() function in this module produces run-time errors (without
# line/col information).

package Plang::AstInterpreter;

use warnings;
use strict;
use feature 'signatures';

use Data::Dumper;
use Devel::StackTrace;
use Plang::AstDumper;

use Plang::Constants::Instructions ':all';

sub new($class, %args) {
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->{ast}      = $conf{ast};
    $self->{embedded} = $conf{embedded} // 0;
    $self->{debug}    = $conf{debug};

    $self->{max_recursion}  = $conf{max_recursion}  // 10000;
    $self->{recursions}     = 0;

    $self->{max_iterations} = $conf{max_iterations} // 25000;
    $self->{iterations}     = 0;

    $self->{repl_scope}     = undef; # persistent repl scope

    $self->{types} = $conf{types} // die 'Missing types';

    $self->{dumper} = Plang::AstDumper->new(types => $self->{types}, debug => $self->{debug});

    $self->{instr_dispatch} = [];

    # main instructions
    $self->{instr_dispatch}->[INSTR_NOP]         = \&null_op;
    $self->{instr_dispatch}->[INSTR_EXPR_GROUP]  = \&expression_group;
    $self->{instr_dispatch}->[INSTR_LITERAL]     = \&literal;
    $self->{instr_dispatch}->[INSTR_VAR]         = \&variable_declaration;
    $self->{instr_dispatch}->[INSTR_MAPCONS]     = \&map_constructor;
    $self->{instr_dispatch}->[INSTR_ARRAYCONS]   = \&array_constructor;
    $self->{instr_dispatch}->[INSTR_EXISTS]      = \&keyword_exists;
    $self->{instr_dispatch}->[INSTR_DELETE]      = \&keyword_delete;
    $self->{instr_dispatch}->[INSTR_KEYS]        = \&keyword_keys;
    $self->{instr_dispatch}->[INSTR_VALUES]      = \&keyword_values;
    $self->{instr_dispatch}->[INSTR_COND]        = \&conditional;
    $self->{instr_dispatch}->[INSTR_WHILE]       = \&keyword_while;
    $self->{instr_dispatch}->[INSTR_NEXT]        = \&keyword_next;
    $self->{instr_dispatch}->[INSTR_LAST]        = \&keyword_last;
    $self->{instr_dispatch}->[INSTR_IF]          = \&keyword_if;
    $self->{instr_dispatch}->[INSTR_AND]         = \&logical_and;
    $self->{instr_dispatch}->[INSTR_OR]          = \&logical_or;
    $self->{instr_dispatch}->[INSTR_ASSIGN]      = \&assignment;
    $self->{instr_dispatch}->[INSTR_ADD_ASSIGN]  = \&add_assign;
    $self->{instr_dispatch}->[INSTR_SUB_ASSIGN]  = \&sub_assign;
    $self->{instr_dispatch}->[INSTR_MUL_ASSIGN]  = \&mul_assign;
    $self->{instr_dispatch}->[INSTR_DIV_ASSIGN]  = \&div_assign;
    $self->{instr_dispatch}->[INSTR_CAT_ASSIGN]  = \&cat_assign;
    $self->{instr_dispatch}->[INSTR_IDENT]       = \&identifier;
    $self->{instr_dispatch}->[INSTR_FUNCDEF]     = \&function_definition;
    $self->{instr_dispatch}->[INSTR_CALL]        = \&function_call;
    $self->{instr_dispatch}->[INSTR_RET]         = \&keyword_return;
    $self->{instr_dispatch}->[INSTR_PREFIX_ADD]  = \&prefix_increment;
    $self->{instr_dispatch}->[INSTR_PREFIX_SUB]  = \&prefix_decrement;
    $self->{instr_dispatch}->[INSTR_POSTFIX_ADD] = \&postfix_increment;
    $self->{instr_dispatch}->[INSTR_POSTFIX_SUB] = \&postfix_decrement;
    $self->{instr_dispatch}->[INSTR_RANGE]       = \&range_operator;
    $self->{instr_dispatch}->[INSTR_DOT_ACCESS]  = \&access;
    $self->{instr_dispatch}->[INSTR_ACCESS]      = \&access;
    $self->{instr_dispatch}->[INSTR_TRY]         = \&keyword_try;
    $self->{instr_dispatch}->[INSTR_THROW]       = \&keyword_throw;
    $self->{instr_dispatch}->[INSTR_TYPE]        = \&keyword_type;
    $self->{instr_dispatch}->[INSTR_STRING_I]    = \&string_interpolation;

    # unary operators
    $self->{instr_dispatch}->[INSTR_NOT] = \&unary_op;
    $self->{instr_dispatch}->[INSTR_NEG] = \&unary_op;
    $self->{instr_dispatch}->[INSTR_POS] = \&unary_op;

    # binary operators
    $self->{instr_dispatch}->[INSTR_POW]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_REM]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_MUL]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_DIV]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_ADD]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_SUB]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_STRCAT] = \&binary_op;
    $self->{instr_dispatch}->[INSTR_STRIDX] = \&binary_op;
    $self->{instr_dispatch}->[INSTR_GTE]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_LTE]    = \&binary_op;
    $self->{instr_dispatch}->[INSTR_GT]     = \&binary_op;
    $self->{instr_dispatch}->[INSTR_LT]     = \&binary_op;
    $self->{instr_dispatch}->[INSTR_EQ]     = \&binary_op;
    $self->{instr_dispatch}->[INSTR_NEQ]    = \&binary_op;
}

sub reset($self) {
    $self->{recursions} = 0;
    $self->{iterations} = 0;
}

sub dispatch_instruction($self, $instr, $scope, $data) {
    if ($self->{debug}) {
        $self->{debug}->{print}->('INSTR', "Dispatching instruction $pretty_instr[$instr]\n");
    }

    # main instructions
    if ($instr < INSTR_NOT) {
        return $self->{instr_dispatch}->[$instr]->($self, $scope, $data);
    }

    # unary and binary operators
    return $self->{instr_dispatch}->[$instr]->($self, $instr, $scope, $data);
}

sub error($self, $scope, $err_msg) {
    chomp $err_msg;
    $self->{debug}->{print}->('ERRORS', "Got error: $err_msg\n") if $self->{debug};
    die "Runtime error: $err_msg\n";
}

sub new_scope($self, $parent = undef) {
    return {
        locals => {},
        parent => $parent,
    };
}

sub declare_variable($self, $scope, $type, $name, $value) {
    $scope->{guards}->{$name} = $type;
    $scope->{locals}->{$name} = $value;
    $self->{debug}->{print}->('VARS', "declare_variable $name with value " . Dumper($value) ."\n") if $self->{debug};
}

sub set_variable($self, $scope, $name, $value) {
    $scope->{locals}->{$name} = $value;
    $self->{debug}->{print}->('VARS', "set_variable $name to value " . Dumper($value) . "\n") if $self->{debug};
}

sub get_variable($self, $scope, $name, %opt) {
    $self->{debug}->{print}->('VARS', "get_variable: $name has value " . Dumper($scope->{locals}->{$name}) . "\n") if $self->{debug} and $name ne 'fib';

    # look for variables in current scope
    if (exists $scope->{locals}->{$name}) {
        my $var = $scope->{locals}->{$name};
        return ($var, $scope);
    }

    # check for closure
    if (defined $scope->{closure}) {
        my ($var, $var_scope) = $self->get_variable($scope->{closure}, $name);
        return ($var, $var_scope) if defined $var;
    }

    # look for variables in enclosing scopes
    if (!$opt{locals_only} and defined $scope->{parent}) {
        my ($var, $var_scope) = $self->get_variable($scope->{parent}, $name);
        return ($var, $var_scope) if defined $var;
    }

    # otherwise it's an undefined variable
    return (undef);
}

sub variable_declaration($self, $scope, $data) {
    my $type        = $data->[1];
    my $name        = $data->[2];
    my $initializer = $data->[3];
    my $right_value = undef;

    if ($initializer) {
        $right_value = $self->evaluate($scope, $initializer);
    } else {
        $right_value = [['TYPE', 'Null'], undef];
    }

    $self->declare_variable($scope, $type, $name, $right_value);
    return $right_value;
}

sub process_function_call_arguments($self, $scope, $name, $parameters, $arguments) {
    my $evaluated_arguments;

    for (my $i = 0; $i < @$parameters; $i++) {
        if (not defined $arguments->[$i]) {
            # no argument provided, but there's guaranteed to be a default
            # argument here since validator caught missing arguments, etc
            $evaluated_arguments->[$i] = $self->evaluate($scope, $parameters->[$i][2]);
            $scope->{locals}->{$parameters->[$i][1]} = $evaluated_arguments->[$i];
        } else {
            # argument provided
            $evaluated_arguments->[$i] = $self->evaluate($scope, $arguments->[$i]);
            $scope->{locals}->{$parameters->[$i][1]} = $evaluated_arguments->[$i];
        }
    }

    return $evaluated_arguments;
}

sub function_call($self, $scope, $data) {
    $Data::Dumper::Indent = 0;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;

    if ($target->[0] == INSTR_IDENT) {
        $self->{debug}->{print}->('FUNCS', "Calling function `$target->[1]` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        ($func) = $self->get_variable($scope, $target->[1]);

        if (defined $func and $func->[0][0] eq 'TYPEFUNC' and $func->[0][1] eq 'Builtin') {
            # builtin function
            return $self->call_builtin_function($scope, $data, $target->[1]);
        }
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
        $self->{debug}->{print}->('FUNCS', "Calling anonymous-1 function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $target;
    } else {
        $self->{debug}->{print}->('FUNCS', "Calling anonymous-2 function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->evaluate($scope, $target);
    }

    my $closure     = $func->[1][0];
    my $ret_type    = $func->[1][1];
    my $parameters  = $func->[1][2];
    my $expressions = $func->[1][3];

    if ($closure != $scope) {
        $scope->{closure} = $closure;
    }

    # create new scope to set function arguments
    my $func_scope = $self->new_scope($scope);

    $self->process_function_call_arguments($func_scope, $target->[1], $parameters, $arguments);

    # check for recursion limit
    if (++$self->{recursions} > $self->{max_recursion}) {
        $self->error($scope, "Max recursion limit ($self->{max_recursion}) reached.");
    }

    my $result;

    # invoke the function
    foreach my $expression (@$expressions) {
        $result = $self->evaluate($func_scope, $expression);
        last if $expression->[0] == INSTR_RET;
    }

    $self->{recursion}--;

    $scope->{closure} = undef;

    return $result;
}

sub function_definition($self, $scope, $data) {
    my $ret_type    = $data->[1];
    my $name        = $data->[2];
    my $parameters  = $data->[3];
    my $expressions = $data->[4];

    my $param_types = [];

    foreach my $param (@$parameters) {
        push @$param_types, $param->[0];
    }

    my $func = [['TYPEFUNC', 'Function', $param_types, $ret_type], [$scope, $ret_type, $parameters, $expressions]];

    if ($name eq '#anonymous') {
        $name = "anonfunc$func";
    }

    $scope->{locals}->{$name} = $func;
    return $func;
}

sub map_constructor($self, $scope, $data) {
    my $map     = $data->[1];
    my $hashref = {};

    my @props;

    foreach my $entry (@$map) {
        my $key   = $self->evaluate($scope, $entry->[0]);
        my $value = $self->evaluate($scope, $entry->[1]);

        $hashref->{$key->[1]} = $value;
        push @props, [$key->[1], $value->[0]];
    }

    return [['TYPEMAP', \@props], $hashref];
}

sub array_constructor($self, $scope, $data) {
    my $array    = $data->[1];
    my $arrayref = [];

    my @types;

    foreach my $entry (@$array) {
        my $value = $self->evaluate($scope, $entry);
        push @$arrayref,  $value;
        push @types, $value->[0];
    }

    my $type = $self->{types}->unite(\@types);

    return [['TYPEARRAY', $type], $arrayref];
}

sub keyword_exists($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1][1]);
    my $key = $self->evaluate($scope, $data->[1][2]);

    if (exists $var->[1]->{$key->[1]}) {
        return [['TYPE', 'Boolean'], 1];
    } else {
        return [['TYPE', 'Boolean'], 0];
    }
}

sub keyword_delete($self, $scope, $data) {
    # delete one key in map
    if ($data->[1][0] == INSTR_ACCESS) {
        my $var = $self->evaluate($scope, $data->[1][1]);
        my $key = $self->evaluate($scope, $data->[1][2]);

        my $val = delete $var->[1]->{$key->[1]};
        return [['TYPE', 'Null'], undef] if not defined $val;
        return $val;
    }

    # delete all keys in map
    if ($data->[1][0] == INSTR_IDENT) {
        my ($var) = $self->get_variable($scope, $data->[1][1]);
        $var->[1] = {};
        return $var;
    }
}

sub keyword_keys($self, $scope, $data) {
    my $map = $self->evaluate($scope, $data->[1]);

    my $hash = $map->[1];
    my $list = [];

    foreach my $key (sort keys %$hash) {
        push @$list, [['TYPE', 'String'], $key];
    }

    return [['TYPEARRAY', ['TYPE', 'String']], $list];
}

sub keyword_values($self, $scope, $data) {
    my $map = $self->evaluate($scope, $data->[1]);

    my $hash = $map->[1];
    my $list = [];
    my @types;

    foreach my $key (sort keys %$hash) {
        my $value = $hash->{$key};
        push @$list, $value;
        push @types, $value->[0];
    }

    my $type = $self->{types}->unite(\@types);

    return [['TYPEARRAY', $type], $list];
}

sub keyword_try($self, $scope, $data) {
    my $expr     = $data->[1];
    my $catchers = $data->[2];

    my $result = eval {
        $self->evaluate($scope, $expr);
    };

    if (my $exception = $@) {
        my $catch;

        if (not ref $exception) {
            chomp $exception;
            $exception =~ s/ at.*// if $exception =~ /\.pm line \d+/; # strip Perl info
            $exception = [['TYPE', 'String'], $exception];
        }

        foreach my $catcher (@$catchers) {
            my ($cond, $body) = @$catcher;

            if (not $cond) {
                $catch = $body;
                last;
            }

            $cond = $self->evaluate($scope, $cond);

            if ($cond->[1] eq $exception->[1]) {
                $catch = $body;
                last;
            }
        }

        my $try_scope = $self->new_scope($scope);
        $self->declare_variable($try_scope, ['TYPE', 'String'], 'e', $exception);
        return $self->evaluate($try_scope, $catch);
    }

    return $result;
}

sub keyword_throw($self, $scope, $data) {
    my $value = $self->evaluate($scope, $data->[1]);
    die $value->[1]; # guaranteed to be a String as per Validator.pm
}

sub keyword_return($self, $scope, $data) {
    return $self->evaluate($scope, $data->[1]);
}

sub keyword_next($self, $scope, $data) {
    return ['SPCL', 'NEXT'];
}

sub keyword_last($self, $scope, $data) {
    return ['SPCL', 'LAST'];
}

sub keyword_while($self, $scope, $data) {
    my $final_result = [['TYPE', 'Null'], undef];

    my $cond = $data->[1];
    my $body = $data->[2];

    while ($self->is_truthy($scope, $cond)) {
        if (++$self->{iterations} > $self->{max_iterations}) {
            $self->error($scope, "Max iteration limit ($self->{max_iterations}) reached.");
        }

        my $result = $self->evaluate($scope, $body);

        if ($result->[0] eq 'SPCL') {
            if ($result->[1] eq 'LAST') {
                $final_result = $result->[2];
                last;
            }

            if ($result->[1] eq 'NEXT') {
                $final_result = $result-[2];
                next;
            }
        }

        $final_result = $result;
    }

    return $final_result;
}

sub keyword_type($self, $scope, $data) {
    my $type  = $data->[1];
    my $name  = $data->[2];
    my $value = $data->[3];

    $type = [$type->[0], $type->[1], $value, $type->[2]];

    $self->{types}->add('Any', $name);
    $self->{types}->add_alias($name, $type);

    return [['NEWTYPE', $name], $type];
}

sub add_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    $left->[1] += $right->[1];
    return $left;
}

sub sub_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    $left->[1] -= $right->[1];
    return $left;
}

sub mul_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    $left->[1] *= $right->[1];
    return $left;
}

sub div_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    $left->[1] /= $right->[1];
    return $left;
}

sub cat_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    $left->[1] .= $right->[1];
    return $left;
}

sub prefix_increment($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    $var->[1]++;
    return $var;
}

sub prefix_decrement($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    $var->[1]--;
    return $var;
}

sub postfix_increment($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    my $temp_var = [$var->[0], $var->[1]];
    $var->[1]++;
    return $temp_var;
}

sub postfix_decrement($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    my $temp_var = [$var->[0], $var->[1]];
    $var->[1]--;
    return $temp_var;
}

sub string_interpolation($self, $scope, $data) {
    return [['TYPE', 'String'], $self->interpolate_string($scope, $data->[1])];
}

# ?: ternary conditional operator
sub conditional($self, $scope, $data) {
    return $self->keyword_if($scope, $data);
}

sub keyword_if($self, $scope, $data) {
    if ($self->is_truthy($scope, $data->[1])) {
        return $self->evaluate($scope, $data->[2]);
    } else {
        return $self->evaluate($scope, $data->[3]);
    }
}

sub logical_and($self, $scope, $data) {
    my $left_value = $self->evaluate($scope, $data->[1]);
    return $left_value if not $self->is_truthy($scope, $left_value);
    return $self->evaluate($scope, $data->[2]);
}

sub logical_or($self, $scope, $data) {
    my $left_value = $self->evaluate($scope, $data->[1]);
    return $left_value if $self->is_truthy($scope, $left_value);
    return $self->evaluate($scope, $data->[2]);
}

sub range_operator($self, $scope, $data) {
    my ($to, $from) = ($data->[1], $data->[2]);

    $to   = $self->evaluate($scope, $to);
    $from = $self->evaluate($scope, $from);

    return [INSTR_RANGE, $to, $from];
}

# lvalue assignment
sub assignment($self, $scope, $data) {
    my $left_value  = $data->[1];
    my $right_value = $self->evaluate($scope, $data->[2]);

    # lvalue variable
    if ($left_value->[0] == INSTR_IDENT) {
        my ($var, $var_scope) = $self->get_variable($scope, $left_value->[1]);
        $self->set_variable($var_scope, $left_value->[1], $right_value);
        return $right_value;
    }

    # lvalue array/map access
    if ($left_value->[0] == INSTR_ACCESS || $left_value->[0] == INSTR_DOT_ACCESS) {
        my $var = $self->evaluate($scope, $left_value->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->evaluate($scope, $left_value->[2]);
            my $val = $self->evaluate($scope, $right_value);
            $var->[1]->{$key->[1]} = $val;
            return $val;
        }

        if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
            my $index = $self->evaluate($scope, $left_value->[2]);
            my $val = $self->evaluate($scope, $right_value);
            $var->[1][$index->[1]] = $val;
            return $val;
        }

        if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
            my $value = $self->evaluate($scope, $left_value->[2]);

            if ($value->[0] == INSTR_RANGE) {
                my $from = $value->[1];
                my $to   = $value->[2];

                if ($self->{types}->check(['TYPE', 'String'], $right_value->[0])) {
                    substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = $right_value->[1];
                    return [['TYPE', 'String'], $var->[1]];
                }

                if ($self->{types}->check(['TYPE', 'Number'], $right_value->[0])) {
                    substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = chr $right_value->[1];
                    return [['TYPE', 'String'], $var->[1]];
                }
            }

            my $index = $value->[1];
            if ($self->{types}->check(['TYPE', 'String'], $right_value->[0])) {
                substr ($var->[1], $index, 1) = $right_value->[1];
                return [['TYPE', 'String'], $var->[1]];
            }

            if ($self->{types}->check(['TYPE', 'Number'], $right_value->[0])) {
                substr ($var->[1], $index, 1) = chr $right_value->[1];
                return [['TYPE', 'String'], $var->[1]];
            }
        }
    }
}

# rvalue array/map access
sub access($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);

    # map index
    if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
        my $key = $self->evaluate($scope, $data->[2]);
        my $val = $var->[1]->{$key->[1]};
        $val // return [['TYPE', 'Null'], undef];
        return $val;
    }

    # array index
    if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
        my $index = $self->evaluate($scope, $data->[2]);

        if ($self->{types}->check(['TYPE', 'Number'], $index->[0])) {
            my $val = $var->[1][$index->[1]];
            $val // return [['TYPE', 'Null'], undef];
            return $val;
        }

        # TODO support RANGE and x:y splices and negative indexing
    }

    # string index
    if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
        my $value = $self->evaluate($scope, $data->[2]);

        if ($value->[0] == INSTR_RANGE) {
            my $from = $value->[1];
            my $to = $value->[2];
            return [['TYPE', 'String'], substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1])];
        }

        if ($self->{types}->check(['TYPE', 'Number'], $value->[0])) {
            my $index = $value->[1];
            return [['TYPE', 'String'], substr($var->[1], $index, 1) // ""];
        }
    }
}

sub unary_op($self, $instr, $scope, $data) {
    my $value = $self->evaluate($scope, $data->[1]);

    my $result;

    if ($instr == INSTR_NOT) {
        $result = [['TYPE', 'Boolean'], int ! $value->[1]];
    } elsif ($instr == INSTR_NEG) {
        $result = [['TYPE', 'Number'], - $value->[1]];
    } elsif ($instr == INSTR_POS) {
        $result = [['TYPE', 'Number'], + $value->[1]];
    }

    if ($self->{types}->is_subtype($value->[0], $result->[0])) {
        $result->[0] = $value->[0];
    }

    return $result;
}

sub binary_op($self, $instr, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);

    # String operations
    if ($self->{types}->check(['TYPE', 'String'], $left->[0])
            or $self->{types}->check(['TYPE', 'String'], $right->[0])) {

        if ($self->{types}->check(['TYPE', 'Number'], $left->[0])) {
            $left->[1] = chr $left->[1];
        }

        if ($self->{types}->check(['TYPE', 'Number'], $right->[0])) {
            $right->[1] = chr $right->[1];
        }

        return [['TYPE', 'Boolean'],  $left->[1]   eq  $right->[1]]         if $instr == INSTR_EQ;
        return [['TYPE', 'Boolean'],  $left->[1]   ne  $right->[1]]         if $instr == INSTR_NEQ;
        return [['TYPE', 'Boolean'], ($left->[1]  cmp  $right->[1]) == -1]  if $instr == INSTR_LT;
        return [['TYPE', 'Boolean'], ($left->[1]  cmp  $right->[1]) ==  1]  if $instr == INSTR_GT;
        return [['TYPE', 'Boolean'], ($left->[1]  cmp  $right->[1]) <=  0]  if $instr == INSTR_LTE;
        return [['TYPE', 'Boolean'], ($left->[1]  cmp  $right->[1]) >=  0]  if $instr == INSTR_GTE;
        return [['TYPE', 'String'],   $left->[1]    .  $right->[1]]         if $instr == INSTR_STRCAT;
        return [['TYPE', 'Integer'], index $left->[1], $right->[1]]         if $instr == INSTR_STRIDX;
    }

    # Number operations
    my $result;

    if ($instr == INSTR_EQ) {
        $result = [['TYPE', 'Boolean'], $left->[1] == $right->[1]];
    } elsif ($instr == INSTR_NEQ) {
        $result = [['TYPE', 'Boolean'], $left->[1] != $right->[1]];
    } elsif ($instr == INSTR_ADD) {
        $result = [['TYPE', 'Number'],  $left->[1]  + $right->[1]];
    } elsif ($instr == INSTR_SUB) {
        $result = [['TYPE', 'Number'],  $left->[1]  - $right->[1]];
    } elsif ($instr == INSTR_MUL) {
        $result = [['TYPE', 'Number'],  $left->[1]  * $right->[1]];
    } elsif ($instr == INSTR_DIV) {
        $result = [['TYPE', 'Number'],  $left->[1]  / $right->[1]];
    } elsif ($instr == INSTR_REM) {
        $result = [['TYPE', 'Number'],  $left->[1]  % $right->[1]];
    } elsif ($instr == INSTR_POW) {
        $result = [['TYPE', 'Number'],  $left->[1] ** $right->[1]];
    } elsif ($instr == INSTR_LT) {
        $result = [['TYPE', 'Boolean'], $left->[1]  < $right->[1]];
    } elsif ($instr == INSTR_LTE) {
        $result = [['TYPE', 'Boolean'], $left->[1] <= $right->[1]];
    } elsif ($instr == INSTR_GT) {
        $result = [['TYPE', 'Boolean'], $left->[1]  > $right->[1]];
    } elsif ($instr == INSTR_GTE) {
        $result = [['TYPE', 'Boolean'], $left->[1] >= $right->[1]];
    }

    my $promotion = $self->{types}->get_promoted_type($left->[0], $right->[0]);

    if ($self->{types}->is_subtype($promotion, $result->[0])) {
        $result->[0] = $promotion;
    }

    return $result;
}

sub identifier($self, $scope, $data) {
    my ($var) = $self->get_variable($scope, $data->[1]);
    return $var;
}

sub literal($self, $scope, $data) {
    my $type  = $data->[1];
    my $value = $data->[2];
    return [$type, $value];
}

sub null_op {
    return [['TYPE', 'Null'], undef];
}

sub expression_group($self, $scope, $data) {
    return $self->execute($self->new_scope($scope), $data->[1]);
}

sub is_truthy($self, $scope, $expr) {
    my $result = $self->evaluate($scope, $expr);

    if ($self->{types}->check(['TYPE', 'Null'], $result->[0])) {
        return 0;
    }

    if ($self->{types}->check(['TYPE', 'Number'], $result->[0])) {
        return $result->[1] != 0;
    }

    if ($self->{types}->check(['TYPE', 'String'], $result->[0])) {
        return $result->[1] ne "";
    }

    if ($self->{types}->check(['TYPE', 'Boolean'], $result->[0])) {
        return $result->[1] != 0;
    }

    $self->error($scope, "cannot use value of type " . $self->{types}->to_string($result->[0]) . " as conditional");
}

# builtin functions
my %function_builtins = (
    'print'   => {
        # [[[param type], 'param name', [default value]], ...]
        params => [
                    [['TYPE',    'Any'], 'expr', undef],
                    [['TYPE', 'String'], 'end',  [INSTR_LITERAL, ['TYPE', 'String'], "\n"]],
                  ],
        ret    => ['TYPE', 'Null'],
        subref => \&function_builtin_print,
        vsubref => \&validate_builtin_print,
    },
    'typeof' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'String'],
        subref => \&function_builtin_typeof,
    },
    'whatis' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'String'],
        subref => \&function_builtin_whatis,
    },
    'length' => {
        params => [[['TYPEUNION', [['TYPE', 'String'], ['TYPE', 'Map'], ['TYPE', 'Array']]], 'expr', undef]],
        ret    => ['TYPE', 'Integer'],
        subref => \&function_builtin_length,
        vsubref => \&validate_builtin_length,
    },
    'map' => {
        params => [
                    [['TYPE', 'Array'], 'list', undef],
                    [['TYPEFUNC', 'Builtin', [['TYPE', 'Any']], ['TYPE', 'Any']], 'func', undef],
                  ],
        ret    => ['TYPE', 'Array'],
        subref => \&function_builtin_map,
    },
    'filter' => {
        params => [
                    [['TYPE', 'Array'], 'list', undef],
                    [['TYPEFUNC', 'Builtin', [['TYPE', 'Any']], ['TYPE', 'Boolean']], 'func', undef],
                  ],
        ret    => ['TYPE', 'Array'],
        subref => \&function_builtin_filter,
    },
    'char' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'String'],
        subref => \&function_builtin_char,
        vsubref => \&validate_builtin_char,
    },
    'Integer' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'Integer'],
        subref => \&function_builtin_Integer,
        vsubref => \&validate_builtin_Integer,
    },
    'Real' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'Real'],
        subref => \&function_builtin_Real,
        vsubref => \&validate_builtin_Real,
    },
    'String' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'String'],
        subref => \&function_builtin_String,
        vsubref => \&validate_builtin_String,
    },
    'Boolean' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'Boolean'],
        subref => \&function_builtin_Boolean,
        vsubref => \&validate_builtin_Boolean,
    },
    'Array' => {
        params => [[['TYPE', 'String'], 'expr', undef]],
        ret    => ['TYPE', 'Array'],
        subref => \&function_builtin_Array,
        vsubref => \&validate_builtin_Array,
    },
    'Map' => {
        params => [[['TYPE', 'String'], 'expr', undef]],
        ret    => ['TYPE', 'Map'],
        subref => \&function_builtin_Map,
        vsubref => \&validate_builtin_Map,
    },
);

sub add_builtin_function($self, $name, $parameters, $return_type, $subref, $validate_subref = undef) {
    $function_builtins{$name} = { params => $parameters, ret => $return_type, subref => $subref, vsubref => $validate_subref };
}

sub get_builtin_function($self, $name) {
    return $function_builtins{$name};
}

sub call_builtin_function($self, $scope, $data, $name) {
    my $parameters  = $function_builtins{$name}->{params};
    my $func        = $function_builtins{$name}->{subref};
    my $arguments   = $data->[2];
    my $evaled_args = $self->process_function_call_arguments($scope, $name, $parameters, $arguments);
    return $func->($self, $scope, $name, $evaled_args);
}

# just like typeof() except include function parameter identifiers and default values
sub introspect($self, $scope, $data) {
    my $type  = $data->[0];
    my $value = $data->[1];

    if ($type->[0] eq 'TYPEFUNC') {
        my $ret_type = $self->{types}->to_string($value->[1]);

        my @params;
        foreach my $param (@{$value->[2]}) {
            my $param_type = $self->{types}->to_string($param->[0]);
            if (defined $param->[2]) {
                my $default_value = $self->evaluate($self->new_scope, $param->[2]);
                push @params, "$param->[1]: $param_type = " . $self->output_value($scope, $default_value, literal => 1);
            } else {
                push @params, "$param->[1]: $param_type";
            }
        }

        $type = "Function ";
        $type .= '(' . join(', ', @params) . ') ';
        $type .= "-> $ret_type";
    } elsif ($type->[0] eq 'SPCL') {
        $type = $self->output_value($scope, $data);
    } else {
        $type = $self->{types}->to_string($type);
    }

    return $type;
}

# builtin print
sub function_builtin_print($self, $scope, $name, $arguments) {
    my ($text, $end) = ($self->output_value($scope, $arguments->[0]), $arguments->[1][1]);
    print "$text$end";
    return [['TYPE', 'Null'], undef];
}

# builtin typeof
sub function_builtin_typeof($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);
    return [['TYPE', 'String'], $self->{types}->to_string($expr->[0])];
}

# builtin whatis
sub function_builtin_whatis($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);
    return [['TYPE', 'String'], $self->introspect($scope, $expr)];
}

# builtin length
sub function_builtin_length($self, $scope, $name, $arguments) {
    my ($val) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'String'], $val->[0])) {
        return [['TYPE', 'Integer'], length $val->[1]];
    }

    if ($self->{types}->check(['TYPE', 'Array'], $val->[0])) {
        return [['TYPE', 'Integer'], scalar @{$val->[1]}];
    }

    if ($self->{types}->check(['TYPE', 'Map'], $val->[0])) {
        return [['TYPE', 'Integer'], scalar %{$val->[1]}];
    }
}

# builtin map
sub function_builtin_map($self, $scope, $name, $arguments) {
    my ($list, $func) = ($arguments->[0], $arguments->[1]);

    my $data = ['CALL', $func, undef];

    foreach my $val (@{$list->[1]}) {
        $data->[2] = [$val];
        $val = $self->function_call($scope, $data);
    }

    return $list;
}

# builtin filter
sub function_builtin_filter($self, $scope, $name, $arguments) {
    my ($list, $func) = ($arguments->[0], $arguments->[1]);

    my $data = ['CALL', $func, undef];

    my $new_list = [];
    my @types;

    foreach my $val (@{$list->[1]}) {
        $data->[2] = [$val];
        my $result = $self->function_call($scope, $data);

        if ($result->[1]) {
            push @$new_list, $val;
            push @types, $val->[0];
        }
    }

    my $type = $self->{types}->unite(\@types);

    return [['TYPEARRAY', $type], $new_list];
}

# builtin function validators
sub validate_builtin_print {
    return [['TYPE', 'Null'], undef];
}

sub validate_builtin_length($self, $scope, $name, $arguments) {
     my ($val) = ($arguments->[0]);

     my $type = $val->[0];

     if ($type->[0] eq 'TYPE' and
         ($type->[1] eq 'String' or $type->[1] eq 'Array' or $type->[1] eq 'Map')) {
         return [['TYPE', 'Number'], 0];
     }

     $self->error($scope, "cannot get length of a " . $self->{types}->to_string($val->[0]));
}

# cast functions
sub function_builtin_Integer($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'Null'], $expr->[0])) {
        return [['TYPE', 'Integer'], 0];
    }

    if ($self->{types}->check(['TYPE', 'Number'], $expr->[0])) {
        return [['TYPE', 'Integer'], int $expr->[1]];
    }

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        return [['TYPE', 'Integer'], int ($expr->[1] + 0)];
    }

    if ($self->{types}->check(['TYPE', 'Boolean'], $expr->[0])) {
        return [['TYPE', 'Integer'], $expr->[1]];
    }

    $self->error($scope, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Integer");
}

sub validate_builtin_Integer($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Integer($scope, $name, $arguments);
}

sub function_builtin_Real($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'Null'], $expr->[0])) {
        return [['TYPE', 'Real'], sprintf "%f", 0];
    }

    if ($self->{types}->check(['TYPE', 'Number'], $expr->[0])) {
        return [['TYPE', 'Real'], sprintf "%f", $expr->[1]];
    }

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        return [['TYPE', 'Real'], sprintf "%f", $expr->[1]];
    }

    if ($self->{types}->check(['TYPE', 'Boolean'], $expr->[0])) {
        return [['TYPE', 'Real'], sprintf "%f", $expr->[1]];
    }

    $self->error($scope, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Real");
}

sub validate_builtin_Real($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Real($scope, $name, $arguments);
}

sub function_builtin_char($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'Integer'], $expr->[0])) {
        return [['TYPE', 'String'], chr $expr->[1]];
    }

    $self->error($scope, "cannot apply char() to type " . $self->{types}->to_string($expr->[0]));
}

sub validate_builtin_char($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_char($scope, $name, $arguments);
}

sub function_builtin_String($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'Null'], $expr->[0])) {
        return [['TYPE', 'String'], ''];
    }

    if ($self->{types}->check(['TYPE', 'Number'], $expr->[0])) {
        return [['TYPE', 'String'], $expr->[1]];
    }

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        return $expr;
    }

    if ($self->{types}->check(['TYPE', 'Boolean'], $expr->[0])) {
        return [['TYPE', 'String'], $self->output_value($scope, $expr)];
    }

    if ($self->{types}->check(['TYPE', 'Map'], $expr->[0])) {
        return [['TYPE', 'String'], $self->map_to_string($scope, $expr)];
    }

    if ($self->{types}->check(['TYPE', 'Array'], $expr->[0])) {
        return [['TYPE', 'String'], $self->array_to_string($scope, $expr)];
    }

    $self->error($scope, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to String");
}

sub validate_builtin_String($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_String($scope, $name, $arguments);
}

sub function_builtin_Boolean($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'Null'], $expr->[0])) {
        return [['TYPE', 'Boolean'], 0];
    }

    if ($self->{types}->check(['TYPE', 'Number'], $expr->[0])) {
        if ($self->is_truthy($scope, $expr)) {
            return [['TYPE', 'Boolean'], 1];
        } else {
            return [['TYPE', 'Boolean'], 0];
        }
    }

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        if (not $self->is_truthy($scope, $expr)) {
            return [['TYPE', 'Boolean'], 0];
        } else {
            return [['TYPE', 'Boolean'], 1];
        }
    }

    if ($self->{types}->check(['TYPE', 'Boolean'], $expr->[0])) {
        return $expr;
    }

    $self->error($scope, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Boolean");
}

sub validate_builtin_Boolean($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Boolean($scope, $name, $arguments);
}

sub function_builtin_Map($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        my $mapinit = $self->parse_string($expr->[1])->[0];

        if ($mapinit->[0] != INSTR_MAPCONS) {
            $self->error($scope, "not a valid Map inside String in Map() cast (got `$expr->[1]`)");
        }

        return $self->evaluate($scope, $mapinit);
    }

    $self->error($scope, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Map");
}

sub validate_builtin_Map($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Map($scope, $name, $arguments);
}

sub function_builtin_Array($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        my $arrayinit = $self->parse_string($expr->[1])->[0];

        if ($arrayinit->[0] != INSTR_ARRAYCONS) {
            $self->error($scope, "not a valid Array inside String in Array() cast (got `$expr->[1]`)");
        }

        return $self->evaluate($scope, $arrayinit);
    }

    $self->error($scope, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Array");
}

sub validate_builtin_Array($self, $scope, $name, $arguments) {
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Array($scope, $name, $arguments);
}

sub identical_objects($self, $obj1, $obj2) {
    return 0 if not $self->{types}->is_equal($obj1->[0], $obj2->[0]);

    if ($self->{types}->is_subtype(['TYPE', 'String'], $obj1->[0])) {
        return $obj1->[1] eq $obj2->[1];
    } elsif ($self->{types}->is_subtype(['TYPE', 'Null'], $obj1->[0])) {
        return 1;
    } elsif ($self->{types}->is_subtype(['TYPE', 'Number'], $obj1->[0])) {
        return $obj1->[1] == $obj2->[1];
    } elsif ($self->{types}->is_subtype(['TYPE', 'Function'], $obj1->[0])) {
        return 0;
    } elsif ($obj1->[0][0] eq 'TYPEMAP') {
        my %h1 = %{$obj1->[1]};
        my %h2 = %{$obj2->[1]};

        my @keys1 = keys %h1;
        my @keys2 = keys %h2;

        return 0 if @keys1 != @keys2;

        foreach my $key (sort @keys1) {
            return 0 if !$self->identical_objects($h1{$key}, $h2{$key});
        }
    } elsif ($obj1->[0][0] eq 'TYPEARRAY') {
        my @a1 = @{$obj1->[1]};
        my @a2 = @{$obj2->[1]};

        return 0 if @a1 != @a2;

        for (my $i = 0; $i < @a1; $i++) {
            return 0 if !$self->identical_objects($a1[$i], $a2[$i]);
        }
    } else {
        return $obj1->[1] == $obj2->[1];
    }
    return 1;
}

use Plang::Interpreter;

sub parse_string($self, $string) {
    my $interpreter = Plang::Interpreter->new; # TODO reuse interpreter
    my $program = $interpreter->parse_string($string);
    return $program->[0][1];
}

sub interpolate_string($self, $scope, $string) {
    my $new_string = '';
    while ($string =~ /\G(.*?)(\{(?:[^\}\\]|\\.)*\})/gc) {
        my ($text, $interpolate) = ($1, $2);

        my $ast = $self->parse_string($interpolate);

        # run validator to desugar AST
        my $validator = Plang::Validator->new(types => $self->{types});
        my $errors = $validator->validate($ast, scope => $scope);

        if ($errors) {
            print STDERR $errors->[1];
            exit 1;
        }

        my $result = $self->execute($scope, $ast);
        $new_string .= $text . $self->output_value($scope, $result);
    }

    $string =~ /\G(.*)/gc;
    $new_string .= $1;
    return $new_string;
}

# converts a map to a string
# note: trusts $var to be Map type
sub map_to_string($self, $scope, $var) {
    my $hash = $var->[1];
    my $string = '{';

    my @entries;
    foreach my $key (sort keys %$hash) {
        my $value = $hash->{$key};
        $key = $self->output_string_literal($key);
        my $entry = "$key = ";
        $entry .= $self->output_value($scope, $value, literal => 1);
        push @entries, $entry;
    }

    $string .= join(', ', @entries);
    $string .= '}';
    return $string;
}

# converts an array to a string
# note: trusts $var to be Array type
sub array_to_string($self, $scope, $var) {
    my $array = $var->[1];
    my $string = '[';

    my @entries;
    foreach my $entry (@$array) {
        push @entries, $self->output_value($scope, $entry, literal => 1);
    }

    $string .= join(',', @entries);
    $string .= ']';
    return $string;
}

# TODO: do this more efficiently
sub output_string_literal($self, $text) {
    $Data::Dumper::Indent = 0;
    $Data::Dumper::Terse  = 1;
    $Data::Dumper::Useqq  = 1;

    $text = Dumper ($text);
    $text =~ s/\\([\@\$\%])/$1/g;

    return $text;
}

sub output_value($self, $scope, $value, %opts) {
    my $result = '';

    # special cases
    if ($value->[0][0] eq 'NEWTYPE') {
        my $default_value;
        if (defined $value->[1][2]) {
            $default_value = $self->evaluate($scope, $value->[1][2]);
            $default_value = $self->output_value($scope, $default_value, literal => 1);
        }
        $result .= "type $value->[0][1] : " . $self->{types}->to_string($value->[1], $default_value);
    }

    # booleans
    elsif ($self->{types}->check(['TYPE', 'Boolean'], $value->[0])) {
        if ($value->[1] == 0) {
            $result .= 'false';
        } else {
            $result .= 'true';
        }
    }

    # functions
    elsif ($self->{types}->name_is($value->[0], 'TYPEFUNC')) {
        $result .= $self->{types}->to_string($value->[0]);
    }

    # maps
    elsif ($self->{types}->check(['TYPE', 'Map'], $value->[0])) {
        $result .= $self->map_to_string($scope, $value);
    }

    # arrays
    elsif ($self->{types}->check(['TYPE', 'Array'], $value->[0])) {
        $result .= $self->array_to_string($scope, $value);
    }

    # String and Number
    else {
        if ($opts{literal}) {
            # output literals
            if ($self->{types}->check(['TYPE', 'String'], $value->[0])) {
                $result .= $self->output_string_literal($value->[1]);
            } elsif ($self->{types}->check(['TYPE', 'Null'], $value->[0])) {
                $result .= 'null';
            } else {
                $result .= $value->[1];
            }
        } else {
            $result .= $value->[1] if defined $value->[1];
        }
    }

    # append type if in REPL mode
    if ($self->{repl}) {
        my $show_type = 0;

        if ($opts{literal}) {
            $show_type = 1;
        } else {
            $show_type = 1 if defined $value->[1];
        }

        if ($show_type) {
            $result .= ': ' . $self->{types}->to_string($value->[0]);
        }
    }

    return $result;
}

# runs a new Plang program with a fresh environment
sub run($self, $ast = undef, %opt) {
    # ast can be supplied via new() or via this run() subroutine
    $ast ||= $self->{ast};

    # make sure we were given a program
    if (not $ast) {
        print STDERR "No program to run.\n";
        return;
    }

    # set up the global environment
    my $scope;

    if ($opt{repl}) {
        $self->{repl_scope} ||= $self->new_scope;
        $scope = $self->{repl_scope};
        $self->{repl} = 1;
    } elsif ($opt{scope}) {
        $scope = $opt{scope};
    } else {
        $scope = $self->new_scope;
        $self->{repl} = 0;
    }

    # add built-in functions to global enviornment
    foreach my $builtin (sort keys %function_builtins) {
        my $ret_type = $function_builtins{$builtin}{ret};
        my $param_types  = [];
        my $param_whatis = [];

        foreach my $param (@{$function_builtins{$builtin}{params}}) {
            push @$param_types, $param->[0];
            push @$param_whatis, $param;
        }

        my $type = ['TYPEFUNC', 'Builtin', $param_types, $ret_type];
        my $data = [$scope, $ret_type, $param_whatis, undef];

        $self->set_variable($scope, $builtin, [$type, $data]);
    }

    # grab our program's expressions
    my $program    = $ast->[0];
    my $expressions = $program->[1];

    # interpret the expressions
    my $result = $self->execute($scope, $expressions);

    # return result to parent program if we're embedded
    return $result if $self->{embedded};

    # return success if there's no result to print
    return if not defined $result;

    # print the result if defined
    unless ($opt{silent}) {
        if (defined $result->[1]) {
            print $self->output_value($scope, $result, literal => 1), "\n";
        }
    }

    return $result;
}

sub execute($self, $scope, $ast) {
    if ($self->{debug}) {
        $self->{debug}->{print}->('AST', "interpret ast: " . $self->{dumper}->dump($ast, tree => 1) . "\n");
    }

    my $final_result;

    foreach my $node (@$ast) {
        $self->{debug}->{print}->('AST', "AST node: " . $self->{dumper}->dump($node) . "\n") if $self->{debug};

        my $instruction = $node->[0];

        if ($instruction == INSTR_EXPR_GROUP) {
            return $self->execute($scope, $node->[1]);
        }

        my $result = $self->evaluate($scope, $node);

        if ($result && $result->[0] eq 'SPCL') {
            if ($result->[1] eq 'NEXT' or $result->[1] eq 'LAST') {
                $result->[2] = $final_result;
                return $result;
            }
        }

        $final_result = $result;
    }

    return $final_result // [['TYPE', 'Null'], undef];
}

sub evaluate($self, $scope, $data) {
    return if not $data;

    my $ins = $data->[0];

    if ($ins !~ /^\d+$/) {
        if ($self->{debug} && $self->{debug}->{tags}->{INSTR}) {
            print "Unknown instruction ", Dumper($ins), "\n";
            my $trace = Devel::StackTrace->new;
            print $trace->as_string;
        }
        return $data;
    }

    if ($self->{debug}) {
        $self->{debug}->{print}->('EVAL', "eval $pretty_instr[$ins]: " . $self->{dumper}->dump($data) . "\n");
    }

    my $result = $self->dispatch_instruction($ins, $scope, $data);

    if ($self->{debug}) {
        $Data::Dumper::Indent = 0;
        $Data::Dumper::Terse = 1;
        $self->{debug}->{print}->('EVAL', "done $pretty_instr[$ins]: " . Dumper($result) . "\n");
        $Data::Dumper::Indent = 1;
    }

    return $result;
}

1;
