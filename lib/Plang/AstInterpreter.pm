#!/usr/bin/env perl

# Interprets a Plang syntax tree.

package Plang::AstInterpreter;

use warnings;
use strict;

use Data::Dumper;

use Plang::Constants::Instructions ':all';

sub new {
    my ($class, %args) = @_;
    my $self  = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{ast}      = $conf{ast};
    $self->{embedded} = $conf{embedded} // 0;
    $self->{debug}    = $conf{debug}    // 0;

    if ($self->{debug}) {
        my @tags = split /,/, $self->{debug};
        $self->{debug}  = \@tags;
        $self->{clean}  = sub { $_[0] =~ s/\n/\\n/g; $_[0] };
        $self->{dprint} = sub {
            my $tag = shift;
            print "|  " x $self->{indent}, @_ if grep { $_ eq $tag } @{$self->{debug}} or $self->{debug}->[0] eq 'ALL';
        };
        $self->{indent} = 0;
    } else {
        $self->{dprint} = sub {};
        $self->{clean}  = sub {''};
    }

    $self->{max_recursion}  = $conf{max_recursion}  // 10000;
    $self->{recursions}     = 0;

    $self->{max_iterations} = $conf{max_iterations} // 25000;
    $self->{iterations}     = 0;

    $self->{repl_context}   = undef; # persistent repl context

    $self->{types} = $conf{types} // die 'Missing types';

    $self->{instr_dispatch} = [];

    # main instructions
    $self->{instr_dispatch}->[INSTR_NOP]         = \&null_statement;
    $self->{instr_dispatch}->[INSTR_STMT_GROUP]  = \&statement_group;
    $self->{instr_dispatch}->[INSTR_LITERAL]     = \&stmt_literal;
    $self->{instr_dispatch}->[INSTR_VAR]         = \&variable_declaration;
    $self->{instr_dispatch}->[INSTR_MAPINIT]     = \&map_constructor;
    $self->{instr_dispatch}->[INSTR_ARRAYINIT]   = \&array_constructor;
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
    $self->{instr_dispatch}->[INSTR_ACCESS]      = \&access_notation;

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

sub dispatch_instruction {
    my ($self, $instr, $context, $data) = @_;

    # main instructions
    if ($instr < INSTR_NOT) {
        return $self->{instr_dispatch}->[$instr]->($self, $context, $data);
    }

    # unary and binary operators
    return $self->{instr_dispatch}->[$instr]->($self, $instr, $context, $data);
}

sub error {
    my ($self, $context, $err_msg) = @_;
    chomp $err_msg;
    $self->{dprint}->('ERRORS', "Got error: $err_msg\n") if $self->{debug};
    die "Runtime error: $err_msg\n";
}

sub new_context {
    my ($self, $parent) = @_;

    return {
        locals => {},
        parent => $parent,
    };
}

sub declare_variable {
    my ($self, $context, $type, $name, $value) = @_;
    $context->{guards}->{$name} = $type;
    $context->{locals}->{$name} = $value;
    $self->{dprint}->('VARS', "declare_variable $name\n" . Dumper($context->{locals}) . "\n") if $self->{debug};
}

sub set_variable {
    my ($self, $context, $name, $value) = @_;
    $context->{locals}->{$name} = $value;
    $self->{dprint}->('VARS', "set_variable $name\n" . Dumper($context->{locals}) . "\n") if $self->{debug};
}

sub get_variable {
    my ($self, $context, $name, %opt) = @_;

    $self->{dprint}->('VARS', "get_variable: $name\n" . Dumper($context->{locals}) . "\n") if $self->{debug};

    # look for variables in current scope
    if (exists $context->{locals}->{$name}) {
        return $context->{locals}->{$name};
    }

    # look for variables in enclosing scopes
    if (!$opt{locals_only} and defined $context->{parent}) {
        my $var = $self->get_variable($context->{parent}, $name);
        return $var if defined $var;
    }

    # otherwise it's an undefined variable
    return undef;
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

    $self->declare_variable($context, $type, $name, $right_value);
    return $right_value;
}

sub process_function_call_arguments {
    my ($self, $context, $name, $parameters, $arguments) = @_;

    my $evaluated_arguments;

    for (my $i = 0; $i < @$parameters; $i++) {
        if (not defined $arguments->[$i]) {
            # no argument provided, but there's guaranteed to be a default
            # argument here since validator caught missing arguments, etc
            $evaluated_arguments->[$i] = $self->statement($context, $parameters->[$i]->[2]);
            $context->{locals}->{$parameters->[$i]->[1]} = $evaluated_arguments->[$i];
        } else {
            # argument provided
            $evaluated_arguments->[$i] = $self->statement($context, $arguments->[$i]);
            $context->{locals}->{$parameters->[$i]->[1]} = $evaluated_arguments->[$i];
        }
    }

    return $evaluated_arguments;
}

sub function_call {
    my ($self, $context, $data) = @_;

    $Data::Dumper::Indent = 0;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;

    if ($target->[0] == INSTR_IDENT) {
        $self->{dprint}->('FUNCS', "Calling function `$target->[1]` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->get_variable($context, $target->[1]);

        if (defined $func and $func->[0]->[0] eq 'TYPEFUNC' and $func->[0]->[1] eq 'Builtin') {
            # builtin function
            return $self->call_builtin_function($context, $data, $target->[1]);
        }
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
        $self->{dprint}->('FUNCS', "Calling anonymous-1 function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $target;
    } else {
        $self->{dprint}->('FUNCS', "Calling anonymous-2 function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->statement($context, $target);
    }

    my $closure    = $func->[1]->[0];
    my $ret_type   = $func->[1]->[1];
    my $parameters = $func->[1]->[2];
    my $statements = $func->[1]->[3];

    # wedge closure in between current scope and previous scope
    my $new_context = $self->new_context($closure);
    $new_context->{locals} = { %{$context->{locals}} }; # assign copy of current scope's locals so we don't recurse into its parent
    $new_context = $self->new_context($new_context);    # make new current empty scope with previous current scope as parent

    $self->process_function_call_arguments($new_context, $target->[1], $parameters, $arguments);

    # check for recursion limit
    if (++$self->{recursions} > $self->{max_recursion}) {
        $self->error($context, "Max recursion limit ($self->{max_recursion}) reached.");
    }

    my $result;

    # invoke the function
    foreach my $stmt (@$statements) {
        $result = $self->statement($new_context, $stmt);
        last if $stmt->[0] == INSTR_RET;
    }

    $self->{recursion}--;

    return $result;
}

sub function_definition {
    my ($self, $context, $data) = @_;

    my $ret_type   = $data->[1];
    my $name       = $data->[2];
    my $parameters = $data->[3];
    my $statements = $data->[4];

    my $param_types = [];

    foreach my $param (@$parameters) {
        push @$param_types, $param->[0];
    }

    my $func = [['TYPEFUNC', 'Function', $param_types, $ret_type], [$context, $ret_type, $parameters, $statements]];

    if ($name eq '#anonymous') {
        $name = "anonfunc$func";
    }

    $context->{locals}->{$name} = $func;
    return $func;
}

sub map_constructor {
    my ($self, $context, $data) = @_;

    my $map     = $data->[1];
    my $hashref = {};

    foreach my $entry (@$map) {
        if ($entry->[0]->[0] == INSTR_IDENT) {
            my $var = $self->get_variable($context, $entry->[0]->[1]);
            $hashref->{$var->[1]} = $self->statement($context, $entry->[1]);
            next;
        }

        if ($self->{types}->check(['TYPE', 'String'], $entry->[0]->[0])) {
            $hashref->{$entry->[0]->[1]} = $self->statement($context, $entry->[1]);
            next;
        }
    }

    return [['TYPE', 'Map'], $hashref];
}

sub array_constructor {
    my ($self, $context, $data) = @_;

    my $array    = $data->[1];
    my $arrayref = [];

    foreach my $entry (@$array) {
        push @$arrayref, $self->statement($context, $entry);
    }

    return [['TYPE', 'Array'], $arrayref];
}

sub keyword_exists {
    my ($self, $context, $data) = @_;

    my $var = $self->statement($context, $data->[1]->[1]);
    my $key = $self->statement($context, $data->[1]->[2]);

    if (exists $var->[1]->{$key->[1]}) {
        return [['TYPE', 'Boolean'], 1];
    } else {
        return [['TYPE', 'Boolean'], 0];
    }
}

sub keyword_delete {
    my ($self, $context, $data) = @_;

    # delete one key in map
    if ($data->[1]->[0] == INSTR_ACCESS) {
        my $var = $self->statement($context, $data->[1]->[1]);
        my $key = $self->statement($context, $data->[1]->[2]);

        my $val = delete $var->[1]->{$key->[1]};
        return [['TYPE', 'Null'], undef] if not defined $val;
        return $val;
    }

    # delete all keys in map
    if ($data->[1]->[0] == INSTR_IDENT) {
        my $var = $self->get_variable($context, $data->[1]->[1]);
        $var->[1] = {};
        return $var;
    }
}

sub keyword_keys {
    my ($self, $context, $data) = @_;

    my $map = $self->statement($context, $data->[1]);

    my $hash = $map->[1];
    my $list = [];

    foreach my $key (keys %$hash) {
        push @$list, [['TYPE', 'String'], $key];
    }

    return [['TYPE', 'Array'], $list];
}

sub keyword_values {
    my ($self, $context, $data) = @_;

    my $map = $self->statement($context, $data->[1]);

    my $hash = $map->[1];
    my $list = [];

    foreach my $value (values %$hash) {
        push @$list, $value;
    }

    return [['TYPE', 'Array'], $list];
}

sub keyword_return {
    my ($self, $context, $data) = @_;
    return $self->statement($context, $data->[1]->[1]);
}

sub keyword_next {
    my ($self, $context, $data) = @_;
    return [INSTR_NEXT, undef];
}

sub keyword_last {
    my ($self, $context, $data) = @_;
    return [INSTR_LAST, undef];
}

sub keyword_while {
    my ($self, $context, $data) = @_;

    while ($self->is_truthy($context, $data->[1])) {
        if (++$self->{iterations} > $self->{max_iterations}) {
            $self->error($context, "Max iteration limit ($self->{max_iterations}) reached.");
        }

        my $result = $self->statement($context, $data->[2]);

        next if $result->[0] == INSTR_NEXT;
        last if $result->[0] == INSTR_LAST;
    }

    return [['TYPE', 'Null'], undef];
}

sub add_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);
    $left->[1] += $right->[1];
    return $left;
}

sub sub_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);
    $left->[1] -= $right->[1];
    return $left;
}

sub mul_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);
    $left->[1] *= $right->[1];
    return $left;
}

sub div_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);
    $left->[1] /= $right->[1];
    return $left;
}

sub cat_assign {
    my ($self, $context, $data) = @_;
    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);
    $left->[1] .= $right->[1];
    return $left;
}

sub prefix_increment {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);
    $var->[1]++;
    return $var;
}

sub prefix_decrement {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);
    $var->[1]--;
    return $var;
}

sub postfix_increment {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);
    my $temp_var = [$var->[0], $var->[1]];
    $var->[1]++;
    return $temp_var;
}

sub postfix_decrement {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);
    my $temp_var = [$var->[0], $var->[1]];
    $var->[1]--;
    return $temp_var;
}

# ?: ternary conditional operator
sub conditional {
    my ($self, $context, $data) = @_;
    return $self->keyword_if($context, $data);
}

# if statement
sub keyword_if {
    my ($self, $context, $data) = @_;

    if ($self->is_truthy($context, $data->[1])) {
        return $self->statement($context, $data->[2]);
    } else {
        return $self->statement($context, $data->[3]);
    }
}

sub logical_and {
    my ($self, $context, $data) = @_;
    my $left_value = $self->statement($context, $data->[1]);
    return $left_value if not $self->is_truthy($context, $left_value);
    return $self->statement($context, $data->[2]);
}

sub logical_or {
    my ($self, $context, $data) = @_;
    my $left_value = $self->statement($context, $data->[1]);
    return $left_value if $self->is_truthy($context, $left_value);
    return $self->statement($context, $data->[2]);
}

sub range_operator {
    my ($self, $context, $data) = @_;

    my ($to, $from) = ($data->[1], $data->[2]);

    $to   = $self->statement($context, $to);
    $from = $self->statement($context, $from);

    return [INSTR_RANGE, $to, $from];
}

# lvalue assignment
sub assignment {
    my ($self, $context, $data) = @_;

    my $left_value  = $data->[1];
    my $right_value = $self->statement($context, $data->[2]);

    # lvalue variable
    if ($left_value->[0] == INSTR_IDENT) {
        my $var = $self->get_variable($context, $left_value->[1]);
        $self->set_variable($context, $left_value->[1], $right_value);
        return $right_value;
    }

    # lvalue array/map access
    if ($left_value->[0] == INSTR_ACCESS) {
        my $var = $self->statement($context, $left_value->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->statement($context, $left_value->[2]);
            my $val = $self->statement($context, $right_value);
            $var->[1]->{$key->[1]} = $val;
            return $val;
        }

        if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
            my $index = $self->statement($context, $left_value->[2]);
            my $val = $self->statement($context, $right_value);
            $var->[1]->[$index->[1]] = $val;
            return $val;
        }

        if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
            my $value = $self->statement($context, $left_value->[2]->[1]);

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
sub access_notation {
    my ($self, $context, $data) = @_;
    my $var = $self->statement($context, $data->[1]);

    # map index
    if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
        my $key = $self->statement($context, $data->[2]);
        my $val = $var->[1]->{$key->[1]};
        return [['TYPE', 'Null'], undef] if not defined $val;
        return $val;
    }

    # array index
    if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
        my $index = $self->statement($context, $data->[2]);

        if ($self->{types}->check(['TYPE', 'Number'], $index->[0])) {
            my $val = $var->[1]->[$index->[1]];
            return [['TYPE', 'Null'], undef] if not defined $val;
            return $val;
        }

        # TODO support RANGE and x:y splices and negative indexing
    }

    # string index
    if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
        my $value = $self->statement($context, $data->[2]->[1]);

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

sub unary_op {
    my ($self, $instr, $context, $data) = @_;

    my $value = $self->statement($context, $data->[1]);

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

sub binary_op {
    my ($self, $instr, $context, $data) = @_;

    my $left  = $self->statement($context, $data->[1]);
    my $right = $self->statement($context, $data->[2]);

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

sub identifier {
    my ($self, $context, $data) = @_;
    my $var = $self->get_variable($context, $data->[1]);
    $self->error($context, "undeclared variable `$data->[1]`") if not defined $var;
    return $var;
}

sub stmt_literal {
    my ($self, $context, $data) = @_;
    my $type  = $data->[1];
    my $value = $data->[2];
    return [$type, $value];
}

sub null_statement {
    return [['TYPE', 'Null'], undef];
}

sub statement_group {
    my ($self, $context, $data) = @_;
    return $self->interpret_ast($self->new_context($context), $data->[1]);
}

sub statement {
    my ($self, $context, $data) = @_;

    return if not $data;

    $Data::Dumper::Indent = 0;
    $self->{dprint}->('STMT', "stmt: " . Dumper($data) . "\n") if $self->{debug};

    my $ins = $data->[0];

    return $data if $ins !~ /^\d+$/;

    if ($ins == INSTR_STMT) {
        return $self->statement($context, $data->[1]);
    }

    if ($ins == INSTR_STRING_I) {
        return [['TYPE', 'String'], $self->interpolate_string($context, $data->[1])];
    }

    return $self->dispatch_instruction($ins, $context, $data);
}

sub is_truthy {
    my ($self, $context, $expr) = @_;

    my $result = $self->statement($context, $expr);

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

    $self->error($context, "cannot use value of type " . $self->{types}->to_string($result->[0]) . " as conditional");
}

# builtin functions
my %function_builtins = (
    'print'   => {
        # [[[param type], 'param name', [default value]], ...]
        params => [[['TYPE',    'Any'], 'expr', undef],
                   [['TYPE', 'String'], 'end',  [['TYPE', 'String'], "\n"]]],
        ret    => ['TYPE', 'Null'],
        subref => \&function_builtin_print,
        vsubref => \&validate_builtin_print,
    },
    'type' => {
        params => [[['TYPE', 'Any'], 'expr', undef]],
        ret    => ['TYPE', 'String'],
        subref => \&function_builtin_type,
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
        params => [[['TYPEFUNC', 'Builtin', [['TYPE', 'Any']], ['TYPE', 'Any']], 'func', undef],
                   [['TYPE', 'Array'], 'list', undef]],
        ret    => ['TYPE', 'Array'],
        subref => \&function_builtin_map,
    },
    'filter' => {
        params => [[['TYPEFUNC', 'Builtin', [['TYPE', 'Any']], ['TYPE', 'Boolean']], 'func', undef],
                   [['TYPE', 'Array'], 'list', undef]],
        ret    => ['TYPE', 'Array'],
        subref => \&function_builtin_filter,
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
        params => [[['TYPEUNION', [['TYPE', 'String'], ['TYPE', 'Array']]], 'expr', undef]],
        ret    => ['TYPE', 'Array'],
        subref => \&function_builtin_Array,
        vsubref => \&validate_builtin_Array,
    },
    'Map' => {
        params => [[['TYPEUNION', [['TYPE', 'String'], ['TYPE', 'Map']]], 'expr', undef]],
        ret    => ['TYPE', 'Map'],
        subref => \&function_builtin_Map,
        vsubref => \&validate_builtin_Map,
    },
);

sub add_builtin_function {
    my ($self, $name, $parameters, $return_type, $subref, $validate_subref) = @_;
    $function_builtins{$name} = { params => $parameters, ret => $return_type, subref => $subref, vsubref => $validate_subref };
}

sub get_builtin_function {
    my ($self, $name) = @_;
    return $function_builtins{$name};
}

sub call_builtin_function {
    my ($self, $context, $data, $name) = @_;
    my $parameters  = $function_builtins{$name}->{params};
    my $func        = $function_builtins{$name}->{subref};
    my $arguments   = $data->[2];
    my $evaled_args = $self->process_function_call_arguments($context, $name, $parameters, $arguments);
    return $func->($self, $context, $name, $evaled_args);
}

# just like type() except include function parameter identifiers and default values
sub introspect {
    my ($self, $data) = @_;

    my $type  = $data->[0];
    my $value = $data->[1];

    if ($type->[0] eq 'TYPEFUNC') {
        my $ret_type = $self->{types}->to_string($value->[1]);

        my @params;
        foreach my $param (@{$value->[2]}) {
            my $param_type = $self->{types}->to_string($param->[0]);
            if (defined $param->[2]) {
                my $default_value = $self->statement($self->new_context, $param->[2]);
                push @params, "$param->[1]: $param_type = " . $self->output_value($default_value, literal => 1);
            } else {
                push @params, "$param->[1]: $param_type";
            }
        }

        $type = "Function ";
        $type .= '(' . join(', ', @params) . ') ';
        $type .= "-> $ret_type";
    } else {
        $type = $self->{types}->to_string($type);
    }

    return $type;
}

# builtin print
sub function_builtin_print {
    my ($self, $context, $name, $arguments) = @_;
    my ($text, $end) = ($self->output_value($arguments->[0]), $arguments->[1]->[1]);
    print "$text$end";
    return [['TYPE', 'Null'], undef];
}

# builtin type
sub function_builtin_type {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);
    return [['TYPE', 'String'], $self->{types}->to_string($expr->[0])];
}

# builtin whatis
sub function_builtin_whatis {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);
    return [['TYPE', 'String'], $self->introspect($expr)];
}

# builtin length
sub function_builtin_length {
    my ($self, $context, $name, $arguments) = @_;
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
sub function_builtin_map {
    my ($self, $context, $name, $arguments) = @_;
    my ($func, $list) = ($arguments->[0], $arguments->[1]);

    my $data = ['CALL', $func, undef];

    foreach my $val (@{$list->[1]}) {
        $data->[2] = [$val];
        $val = $self->function_call($context, $data);
    }

    return $list;
}

# builtin filter
sub function_builtin_filter {
    my ($self, $context, $name, $arguments) = @_;
    my ($func, $list) = ($arguments->[0], $arguments->[1]);

    my $data = ['CALL', $func, undef];

    my $new_list = [];

    foreach my $val (@{$list->[1]}) {
        $data->[2] = [$val];
        my $result = $self->function_call($context, $data);

        if ($result->[1]) {
            push @$new_list, $val;
        }
    }

    return [['TYPE', 'Array'], $new_list];
}

# builtin function validators
sub validate_builtin_print {
    return [['TYPE', 'Null'], undef];
}

sub validate_builtin_length {
     my ($self, $context, $name, $arguments) = @_;
     my ($val) = ($arguments->[0]);

     my $type = $val->[0];

     if ($type->[0] eq 'TYPE' and
         ($type->[1] eq 'String' or $type->[1] eq 'Array' or $type->[1] eq 'Map')) {
         return [['TYPE', 'Number'], 0];
     }

     $self->error($context, "cannot get length of a " . $self->{types}->to_string($val->[0]));
}

# cast functions
sub function_builtin_Integer {
    my ($self, $context, $name, $arguments) = @_;
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

    $self->error($context, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Integer");
}

sub validate_builtin_Integer {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Integer($context, $name, $arguments);
}

sub function_builtin_Real {
    my ($self, $context, $name, $arguments) = @_;
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

    $self->error($context, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Real");
}

sub validate_builtin_Real {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Real($context, $name, $arguments);
}

sub function_builtin_String {
    my ($self, $context, $name, $arguments) = @_;
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
        return [['TYPE', 'String'], $self->output_value($expr)];
    }

    if ($self->{types}->check(['TYPE', 'Map'], $expr->[0])) {
        return [['TYPE', 'String'], $self->map_to_string($expr)];
    }

    if ($self->{types}->check(['TYPE', 'Array'], $expr->[0])) {
        return [['TYPE', 'String'], $self->array_to_string($expr)];
    }

    $self->error($context, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to String");
}

sub validate_builtin_String {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_String($context, $name, $arguments);
}

sub function_builtin_Boolean {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'Null'], $expr->[0])) {
        return [['TYPE', 'Boolean'], 0];
    }

    if ($self->{types}->check(['TYPE', 'Number'], $expr->[0])) {
        if ($self->is_truthy($context, $expr)) {
            return [['TYPE', 'Boolean'], 1];
        } else {
            return [['TYPE', 'Boolean'], 0];
        }
    }

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        if (not $self->is_truthy($context, $expr)) {
            return [['TYPE', 'Boolean'], 0];
        } else {
            return [['TYPE', 'Boolean'], 1];
        }
    }

    if ($self->{types}->check(['TYPE', 'Boolean'], $expr->[0])) {
        return $expr;
    }

    $self->error($context, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Boolean");
}

sub validate_builtin_Boolean {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Boolean($context, $name, $arguments);
}

sub function_builtin_Map {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        my $mapinit = $self->parse_string($expr->[1])->[0]->[1];

        if ($mapinit->[0] != INSTR_MAPINIT) {
            $self->error($context, "not a valid Map inside String in Map() cast (got `$expr->[1]`)");
        }

        return $self->statement($context, $mapinit);
    }

    $self->error($context, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Map");
}

sub validate_builtin_Map {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Map($context, $name, $arguments);
}

sub function_builtin_Array {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        my $mapinit = $self->parse_string($expr->[1])->[0]->[1];

        if ($mapinit->[0] != INSTR_ARRAYINIT) {
            $self->error($context, "not a valid Array inside String in Array() cast (got `$expr->[1]`)");
        }

        return $self->statement($context, $mapinit);
    }

    $self->error($context, "cannot convert type " . $self->{types}->to_string($expr->[0]) . " to Array");
}

sub validate_builtin_Array {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $expr->[0])) {
        return $expr;
    }

    return $self->function_builtin_Array($context, $name, $arguments);
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
        $new_string .= $text . $self->output_value($result);
    }

    $string =~ /\G(.*)/gc;
    $new_string .= $1;
    return $new_string;
}

# converts a map to a string
# note: trusts $var to be Map type
sub map_to_string {
    my ($self, $var) = @_;

    my $hash = $var->[1];
    my $string = '{';

    my @entries;
    while (my ($key, $value) = each %$hash) {
        $key = $self->output_string_literal($key);
        my $entry = "$key: ";
        $entry .= $self->output_value($value, literal => 1);
        push @entries, $entry;
    }

    $string .= join(', ', @entries);
    $string .= '}';
    return $string;
}

# converts an array to a string
# note: trusts $var to be Array type
sub array_to_string {
    my ($self, $var) = @_;

    my $array = $var->[1];
    my $string = '[';

    my @entries;
    foreach my $entry (@$array) {
        push @entries, $self->output_value($entry, literal => 1);
    }

    $string .= join(',', @entries);
    $string .= ']';
    return $string;
}

# TODO: do this more efficiently
sub output_string_literal {
    my ($self, $text) = @_;

    $Data::Dumper::Indent = 0;
    $Data::Dumper::Terse  = 1;
    $Data::Dumper::Useqq  = 1;

    $text = Dumper ($text);
    $text =~ s/\\([\@\$\%])/$1/g;

    return $text;
}

sub output_value {
    my ($self, $value, %opts) = @_;

    my $result = '';;

    # identifiers
    if ($value->[0] == INSTR_IDENT) {
        return $value->[1];
    }

    if ($self->{repl}) {
        $result .= "[" . $self->{types}->to_string($value->[0]) . "] ";
    }

    # booleans
    if ($self->{types}->check(['TYPE', 'Boolean'], $value->[0])) {
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
        $result .= $self->map_to_string($value);
    }

    # arrays
    elsif ($self->{types}->check(['TYPE', 'Array'], $value->[0])) {
        $result .= $self->array_to_string($value);
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

    return $result;
}

# runs a new Plang program with a fresh environment
sub run {
    my ($self, $ast, %opt) = @_;

    # ast can be supplied via new() or via this run() subroutine
    $ast ||= $self->{ast};

    # make sure we were given a program
    if (not $ast) {
        print STDERR "No program to run.\n";
        return;
    }

    # set up the global environment
    my $context;

    if ($opt{repl}) {
        $self->{repl_context} ||= $self->new_context;
        $context = $self->{repl_context};
        $self->{repl} = 1;
    } else {
        $context = $self->new_context;
        $self->{repl} = 0;
    }

    # add built-in functions to global enviornment
    foreach my $builtin (keys %function_builtins) {
        my $ret_type = $function_builtins{$builtin}{ret};
        my $param_types  = [];
        my $param_whatis = [];

        foreach my $param (@{$function_builtins{$builtin}{params}}) {
            push @$param_types, $param->[0];
            push @$param_whatis, $param;
        }

        my $type = ['TYPEFUNC', 'Builtin', $param_types, $ret_type];
        my $data = [$context, $ret_type, $param_whatis, undef];

        $self->set_variable($context, $builtin, [$type, $data]);
    }

    # grab our program's statements
    my $program    = $ast->[0];
    my $statements = $program->[1];

    # interpret the statements
    my $result = $self->interpret_ast($context, $statements);

    # return result to parent program if we're embedded
    return $result if $self->{embedded};

    # return success if there's no result to print
    return if not defined $result;

    # handle final statement (print last value of program if not Null)
    return $self->handle_statement_result($result, 1);
}

sub interpret_ast {
    my ($self, $context, $ast) = @_;

    $Data::Dumper::Indent = 0;

    $self->{dprint}->('AST', "interpet ast: " . Dumper ($ast) . "\n") if $self->{debug};

    # try
    my $last_statement_result = eval {

        my $result;

        foreach my $node (@$ast) {
            my $instruction = $node->[0];

            if ($instruction == INSTR_STMT) {
                $result = $self->statement($context, $node->[1]);

                if (defined $result) {
                    $result = $self->handle_statement_result($result);
                    $self->{dprint}->('AST', "Statement result: " . Dumper($result) . "\n") if $self->{debug};
                } else {
                    $self->{dprint}->('AST', "Statement result: none\n") if $self->{debug};
                }
            }
        }

        $result //= [['TYPE', 'Null'], undef];

        return $result;
    };

    # catch
    die $@ if $@;

    return $last_statement_result;
}

# handles one statement result
sub handle_statement_result {
    my ($self, $result, $print_any) = @_;

    $print_any ||= 0;

    $self->{dprint}->('RESULT', "handle result: " . Dumper($result) . "\n") if $self->{debug};

    # if Plang is embedded into a larger app return the result
    # to the larger app so it can handle it itself
    return $result if $self->{embedded};

    # return result unless we should print any result
    return $result unless $print_any;

    # print the result if possible and then consume it
    if (defined $result->[1]) {
        if ($self->{types}->check(['TYPE', 'String'], $result->[0])) {
            print $self->output_string_literal($result->[1]), "\n";;
        } else {
            print $self->output_value($result), "\n";
        }
    }

    return;
}

1;
