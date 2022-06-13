#!/usr/bin/env perl

# The validator pass happens once at compile-time immediately after parsing
# a Plang program into a syntax tree. Static type-checking, semantic-analysis,
# etc, is performed on the syntax tree so the run-time interpreter need not
# concern itself with these potentially expensive operations.
#
# This module also does some syntax desugaring.
#
# The error() function in this module produces compile-time errors with
# line/col information.

package Plang::Validator;

use parent 'Plang::AstInterpreter';

use warnings;
use strict;

use Data::Dumper;

use Plang::Constants::Instructions ':all';

sub initialize {
    my ($self, %conf) = @_;

    $self->SUPER::initialize(%conf);

    # validate these main instructions
    $self->{instr_dispatch}->[INSTR_EXPR_GROUP]  = \&expression_group;
    $self->{instr_dispatch}->[INSTR_IDENT]       = \&identifier;
    $self->{instr_dispatch}->[INSTR_LITERAL]     = \&literal;
    $self->{instr_dispatch}->[INSTR_VAR]         = \&variable_declaration;
    $self->{instr_dispatch}->[INSTR_ARRAYINIT]   = \&array_constructor;
    $self->{instr_dispatch}->[INSTR_MAPINIT]     = \&map_constructor;
    $self->{instr_dispatch}->[INSTR_EXISTS]      = \&keyword_exists;
    $self->{instr_dispatch}->[INSTR_DELETE]      = \&keyword_delete;
    $self->{instr_dispatch}->[INSTR_KEYS]        = \&keyword_keys;
    $self->{instr_dispatch}->[INSTR_VALUES]      = \&keyword_values;
    $self->{instr_dispatch}->[INSTR_COND]        = \&conditional;
    $self->{instr_dispatch}->[INSTR_WHILE]       = \&keyword_while;
    $self->{instr_dispatch}->[INSTR_NEXT]        = \&keyword_next;
    $self->{instr_dispatch}->[INSTR_LAST]        = \&keyword_last;
    $self->{instr_dispatch}->[INSTR_IF]          = \&keyword_if;
    $self->{instr_dispatch}->[INSTR_ASSIGN]      = \&assignment;
    $self->{instr_dispatch}->[INSTR_ADD_ASSIGN]  = \&add_assign;
    $self->{instr_dispatch}->[INSTR_SUB_ASSIGN]  = \&sub_assign;
    $self->{instr_dispatch}->[INSTR_MUL_ASSIGN]  = \&mul_assign;
    $self->{instr_dispatch}->[INSTR_DIV_ASSIGN]  = \&div_assign;
    $self->{instr_dispatch}->[INSTR_CAT_ASSIGN]  = \&cat_assign;
    $self->{instr_dispatch}->[INSTR_FUNCDEF]     = \&function_definition;
    $self->{instr_dispatch}->[INSTR_CALL]        = \&function_call;
    $self->{instr_dispatch}->[INSTR_RET]         = \&keyword_return;
    $self->{instr_dispatch}->[INSTR_PREFIX_ADD]  = \&prefix_increment;
    $self->{instr_dispatch}->[INSTR_PREFIX_SUB]  = \&prefix_decrement;
    $self->{instr_dispatch}->[INSTR_POSTFIX_ADD] = \&postfix_increment;
    $self->{instr_dispatch}->[INSTR_POSTFIX_SUB] = \&postfix_decrement;
    $self->{instr_dispatch}->[INSTR_ACCESS]      = \&access_notation;
    $self->{instr_dispatch}->[INSTR_TRY]         = \&keyword_try;
    $self->{instr_dispatch}->[INSTR_THROW]       = \&keyword_throw;

    # validate these unary operators
    $self->{instr_dispatch}->[INSTR_NOT] = \&unary_op;
    $self->{instr_dispatch}->[INSTR_NEG] = \&unary_op;
    $self->{instr_dispatch}->[INSTR_POS] = \&unary_op;

    # validate these binary operators
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

sub error {
    my ($self, $context, $err_msg, $position) = @_;

    chomp $err_msg;

    if (defined $position) {
        my $line = $position->{line};
        my $col  = $position->{col};

        if (defined $line) {
            $err_msg .= " at line $line, col $col";
        } else {
            $err_msg .= " at EOF";
        }
    }

    $self->{debug}->{print}->('ERRORS', "Got error: $err_msg\n") if $self->{debug};
    die "Validator error: $err_msg\n";
}

sub position {
    my ($self, $data) = @_;
    return $data->[@$data - 1]; # position information is always the last element
}

sub unary_op {
    my ($self, $instr, $context, $data) = @_;

    my $pos = $data->[2];

    my $value = $self->evaluate($context, $data->[1]);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $value->[0]) || $self->{types}->is_arithmetic($value->[0])) {
        my $result;

        if ($instr == INSTR_NOT) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        } elsif ($instr == INSTR_NEG) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_POS) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } else {
            $self->error($context, "Unknown unary operator $pretty_instr[$instr]", $pos);
        }

        if ($self->{types}->is_subtype($value->[0], $result->[0])) {
            $result->[0] = $value->[0];
        }

        return $result;
    }

    $self->error($context, "cannot apply unary operator $pretty_instr[$instr] to type " . $self->{types}->to_string($value->[0]) . "\n", $pos);
}

sub binary_op {
    my ($self, $instr, $context, $data) = @_;

    my $pos = $data->[3];

    my $left  = $self->evaluate($context, $data->[1]);
    my $right = $self->evaluate($context, $data->[2]);


    # String operations

    if (    $self->{types}->check(['TYPE', 'String'], $left->[0])
         or $self->{types}->check(['TYPE', 'String'], $right->[0])
         or $self->{types}->is_equal(['TYPE', 'Any'], $left->[0])
         or $self->{types}->is_equal(['TYPE', 'Any'], $right->[0]))
    {
        return [['TYPE', 'Boolean'], 0, $pos]  if $instr == INSTR_EQ;
        return [['TYPE', 'Boolean'], 0, $pos]  if $instr == INSTR_NEQ;
        return [['TYPE', 'Boolean'], 0, $pos]  if $instr == INSTR_LT;
        return [['TYPE', 'Boolean'], 0, $pos]  if $instr == INSTR_GT;
        return [['TYPE', 'Boolean'], 0, $pos]  if $instr == INSTR_LTE;
        return [['TYPE', 'Boolean'], 0, $pos]  if $instr == INSTR_GTE;
        return [['TYPE', 'String'],  0, $pos]  if $instr == INSTR_STRCAT;
        return [['TYPE', 'Integer'], 0, $pos]  if $instr == INSTR_STRIDX;
    }

    # Number operations

    if (!$self->{types}->is_equal(['TYPE', 'Any'], $left->[0]) && !$self->{types}->is_arithmetic($left->[0])) {
        $self->error($context, "cannot apply operator $pretty_instr[$instr] to non-arithmetic type " . $self->{types}->to_string($left->[0]), $pos);
    }

    if (!$self->{types}->is_equal(['TYPE', 'Any'], $right->[0]) && !$self->{types}->is_arithmetic($right->[0])) {
        $self->error($context, "cannot apply operator $pretty_instr[$instr] to non-arithmetic type " . $self->{types}->to_string($right->[0]), $pos);
    }

    if ($self->{types}->check($left->[0], $right->[0]) or $self->{types}->check($right->[0], $left->[0])) {
        my $result;

        if ($instr == INSTR_EQ) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        } elsif ($instr == INSTR_NEQ) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        } elsif ($instr == INSTR_ADD) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_SUB) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_MUL) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_DIV) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_REM) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_POW) {
            $result = [['TYPE', 'Number'],  0, $pos];
        } elsif ($instr == INSTR_LT) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        } elsif ($instr == INSTR_LTE) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        } elsif ($instr == INSTR_GT) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        } elsif ($instr == INSTR_GTE) {
            $result = [['TYPE', 'Boolean'], 0, $pos];
        }

        if (defined $result) {
            my $promotion = $self->{types}->get_promoted_type($left->[0], $right->[0]);

            if ($self->{types}->is_subtype($promotion, $result->[0])) {
                $result->[0] = $promotion;
            }

            return $result;
        }
    }

    $self->error($context, "cannot apply binary operator $pretty_instr[$instr] (have types " . $self->{types}->to_string($left->[0]) . " and " . $self->{types}->to_string($right->[0]) . ")", $pos);
}

sub expression_group {
    my ($self, $context, $data) = @_;

    my $new_context = $self->new_context($context);

    $new_context->{while_loop} = $context->{while_loop};

    return $self->execute($new_context, $data->[1]);
}

sub is_truthy {
    my ($self, $context, $expr) = @_;

    my $result = $self->evaluate($context, $expr);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $result->[0])) {
        return 1;
    }

    return $self->SUPER::is_truthy($context, $result);
}

sub type_check_prefix_postfix_op {
    my ($self, $context, $data, $op) = @_;

    my $pos = $self->position($data);

    if ($data->[1]->[0] == INSTR_IDENT or $data->[1]->[0] == INSTR_ACCESS && $data->[1]->[1]->[0] == INSTR_IDENT) {
        # desugar x.y to x['y']
        if (defined $data->[2] && ref($data->[2]) eq 'ARRAY' && $data->[2]->[0] == INSTR_IDENT) {
            $data->[2] = [INSTR_LITERAL, ['TYPE', 'String'], $data->[2]->[1]];
        }

        my $var = $self->evaluate($context, $data->[1]);

        if ($self->{types}->is_arithmetic($var->[0])) {
            return $var;
        }

        $self->error($context, "cannot apply $op to type " . $self->{types}->to_string($var->[0]), $pos);
    }

    if ($data->[1]->[0] == INSTR_LITERAL) {
        $self->error($context, "cannot apply $op to a " . $self->{types}->to_string($data->[1]->[1]) . " literal", $pos);
    }

    if (ref ($data->[1]->[0]) ne 'ARRAY') {
        $self->error($context, "cannot apply $op to instruction " . $pretty_instr[$data->[1]->[0]], $pos);
    }

    $self->error($context, "cannot apply $op to type " . $self->{types}->to_string($data->[1]->[0]), $pos);
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

    my $pos_left  = $self->position($left);
    my $pos_right = $self->position($right);

    if ($left->[0] == INSTR_LITERAL) {
        $self->error($context, "cannot assign to " . $self->{types}->to_string($left->[1]) . " literal", $pos_left);
    }

    $left  = $self->evaluate($context, $left);
    $right = $self->evaluate($context, $right);

    if ($self->{types}->is_equal(['TYPE', 'Any'], $left->[0])) {
        return $left;
    }

    if ($self->{types}->is_equal(['TYPE', 'Any'], $right->[0])) {
        return $right;
    }

    if ($op eq 'CAT') {
        if (not $self->{types}->check($left->[0], ['TYPE', 'String'])) {
            $self->error($context, "cannot apply operator $op to type " . $self->{types}->to_string($left->[0]) . " (expected String)", $pos_left);
        }

        if (not $self->{types}->check($right->[0], ['TYPE', 'String'])) {
            $self->error($context, "cannot apply operator $op to type " . $self->{types}->to_string($right->[0]) . " (expected String)", $pos_right);
        }

    } else {
        if (not $self->{types}->is_arithmetic($left->[0])) {
            $self->error($context, "cannot apply operator $op to non-arithmetic type " . $self->{types}->to_string($left->[0]), $pos_left);
        }

        if (not $self->{types}->is_arithmetic($right->[0])) {
            $self->error($context, "cannot apply operator $op to non-arithmetic type " . $self->{types}->to_string($right->[0]), $pos_right);
        }
    }

    if ($self->{types}->check($left->[0], $right->[0])) {
        return $left;
    }

    $self->error($context, "cannot apply operator $op (have types " . $self->{types}->to_string($left->[0]) . " and " . $self->{types}->to_string($right->[0]) . ")", $pos_left);
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

sub cat_assign {
    my ($self, $context, $data) = @_;
    $self->type_check_op_assign($context, $data, 'CAT');
}

sub identifier {
    my ($self, $context, $data) = @_;
    my $var = $self->get_variable($context, $data->[1]);
    $self->error($context, "undeclared variable `$data->[1]`", $data->[2]) if not defined $var;
    return $var;
}

sub literal {
    my ($self, $context, $data) = @_;
    my $type  = $data->[1];
    my $value = $data->[2];
    my $pos   = $data->[3];
    return [$type, $value, $pos];
}

sub variable_declaration {
    my ($self, $context, $data) = @_;

    my $type        = $data->[1];
    my $name        = $data->[2];
    my $initializer = $data->[3];
    my $right_value = undef;

    if ($initializer) {
        $right_value = $self->evaluate($context, $initializer);
    } else {
        $right_value = [['TYPE', 'Null'], undef];
    }

    if (!$self->{repl} and (my $var = $self->get_variable($context, $name, locals_only => 1))) {
        if ($var->[0] ne 'Builtin') {
            $self->error($context, "cannot redeclare existing local `$name`", $self->position($data));
        }
    }

    if ($self->get_builtin_function($name)) {
        $self->error($context, "cannot override builtin function `$name`", $self->position($data));
    }

    if (not $self->{types}->check($type, $right_value->[0])) {
        $self->error($context, "cannot initialize `$name` with value of type "
            . $self->{types}->to_string($right_value->[0])
            . " (expected " . $self->{types}->to_string($type) . ")", $self->position($data));
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

    $self->{debug}->{print}->('VARS', "set_variable $name to " . Dumper($value) . "\n") if $self->{debug};

    my $guard = $context->{guards}->{$name};

    if (defined $guard and not $self->{types}->check($guard, $value->[0])) {
        $self->error($context, "cannot assign to `$name` a value of type "
            . $self->{types}->to_string($value->[0])
            . " (expected " . $self->{types}->to_string($guard) . ")", $self->position($value));
    }

    $context->{locals}->{$name} = $value;
}

sub array_constructor {
    my ($self, $context, $data) = @_;

    my $array    = $data->[1];
    my $pos      = $data->[2];
    my $arrayref = [];

    my @types;

    foreach my $entry (@$array) {
        my $value = $self->evaluate($context, $entry);
        push @$arrayref, $value;
        push @types, $value->[0];
    }

    my $type = $self->{types}->unite(\@types);

    return [['TYPEARRAY', $type], $arrayref, $pos];
}

sub map_constructor {
    my ($self, $context, $data) = @_;

    my $map     = $data->[1];
    my $hashref = {};

    my @props;

    foreach my $entry (@$map) {
        if ($entry->[0]->[0] == INSTR_IDENT) {
            my $var = $self->get_variable($context, $entry->[0]->[1]);

            if (not defined $var) {
                $self->error($context, "cannot use undeclared variable `$entry->[0]->[1]` to assign Map key", $self->position($entry->[0]));
            }

            if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
                my $value = $self->evaluate($context, $entry->[1]);
                $hashref->{$var->[1]} = $value;
                push @props, [$var->[1], $value->[0]];
                next;
            }

            $self->error($context, "cannot use type `" . $self->{types}->to_string($var->[0]) . "` as Map key", $self->position($entry->[0]));
        }

        if ($self->{types}->check(['TYPE', 'String'], $entry->[0]->[0])) {
            my $value = $self->evaluate($context, $entry->[1]);
            $hashref->{$entry->[0]->[1]} = $value;
            push @props, [$entry->[0]->[1], $value->[0]];
            next;
        }

        $self->error($context, "cannot use type `" . $self->{types}->to_string($entry->[0]->[0]) . "` as Map key", $self->position($entry->[0]));
    }

    return [['TYPEMAP', \@props], $hashref];
}

sub keyword_exists {
    my ($self, $context, $data) = @_;

    # check for key in map
    if ($data->[1]->[0] == INSTR_ACCESS) {
        my $var = $self->evaluate($context, $data->[1]->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->evaluate($context, $data->[1]->[2]);

            if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
                if (exists $var->[1]->{$key->[1]}) {
                    return [['TYPE', 'Boolean'], 1];
                } else {
                    return [['TYPE', 'Boolean'], 0];
                }
            }

            $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")", $self->position($key));
        }

        $self->error($context, "exists must be used on Maps (got " . $self->{types}->to_string($var->[0]) . ")", $self->position($var));
    }

    my $expr = $self->evaluate($context, $data->[1]);
    $self->error($context, "exists must be used on a Map key (got " . $self->{types}->to_string($expr->[0]) . ")", $self->position($data->[1]));
}

sub keyword_delete {
    my ($self, $context, $data) = @_;

    # delete one key in map
    if ($data->[1]->[0] == INSTR_ACCESS) {
        my $var = $self->evaluate($context, $data->[1]->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            my $key = $self->evaluate($context, $data->[1]->[2]);

            if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
                my $val = delete $var->[1]->{$key->[1]};
                return [['TYPE', 'Null'], undef] if not defined $val;
                return $val;
            }

            $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")", $self->position($data->[1]->[2]));
        }

        $self->error($context, "delete must be used on Maps (got " . $self->{types}->to_string($var->[0]) . ")", $self->position($var));
    }

    # delete all keys in map
    if ($data->[1]->[0] == INSTR_IDENT) {
        my $var = $self->evaluate($context, $data->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            $var->[1] = {};
            return $var;
        }

        $self->error($context, "delete must be used on Maps (got " . $self->{types}->to_string($var->[0]) . ")", $self->position($data->[1]));
    }

    $self->error($context, "delete must be used on Maps (got " . $self->{types}->to_string($data->[1]) . ")");
}

sub keyword_keys {
    my ($self, $context, $data) = @_;

    my $map = $self->evaluate($context, $data->[1]);

    if (not $self->{types}->check(['TYPE', 'Map'], $map->[0])) {
        $self->error($context, "keys must be used on Maps (got " . $self->{types}->to_string($map->[0]) . ")", $self->position($data->[1]));
    }

    return [['TYPE', 'Array'], []];
}

sub keyword_values {
    my ($self, $context, $data) = @_;

    my $map = $self->evaluate($context, $data->[1]);

    if (not $self->{types}->check(['TYPE', 'Map'], $map->[0])) {
        $self->error($context, "values must be used on Maps (got " . $self->{types}->to_string($map->[0]) . ")", $self->position($data->[1]));
    }

    return [['TYPE', 'Array'], []];
}

sub keyword_try {
    my ($self, $context, $data) = @_;

    my $catchers = $data->[2];

    my $default_catcher;

    my %duplicates;

    foreach my $catcher (@$catchers) {
        my ($cond, $body, $pos) = @$catcher;

        if (not $cond) {
            if ($default_catcher) {
                $self->error($context, "extra default `catch`", $pos);
            }

            $default_catcher = $body;
        } else {
            if ($default_catcher) {
                $self->error($context, "default `catch` must be last", $pos);
            }

            my $new_context = $self->new_context($context);

            $cond = $self->evaluate($new_context, $cond);

            if (not $self->{types}->check(['TYPE', 'String'], $cond->[0])) {
                $self->error($new_context, "`catch` condition must be of type String (got " . $self->{types}->to_string($cond->[0]) . ")", $pos);
            }

            if (exists $duplicates{$cond->[1]}) {
                $self->error($new_context, 'duplicate `catch` condition "' . $cond->[1] . '"', $pos);
            }

            $duplicates{$cond->[1]} = $cond;
        }
    }

    if (not $default_catcher) {
        $self->error($context, "no default `catch` for `try`", $self->position($data));
    }

    return;
}

sub keyword_throw {
    my ($self, $context, $data) = @_;

    my $expr = $self->evaluate($context, $data->[1]);

    if (not $self->{types}->check(['TYPE', 'String'], $expr->[0])) {
        $self->error($context, "`throw` expression must be of type String (got " . $self->{types}->to_string($expr->[0]) . ")", $self->position($expr));
    }

    return $expr;
}

sub function_definition {
    my ($self, $context, $data) = @_;

    my $ret_type    = $data->[1];
    my $name        = $data->[2];
    my $parameters  = $data->[3];
    my $expressions = $data->[4];
    my $pos         = $data->[5];

    my $param_types = [];
    my $func_type   = ['TYPEFUNC', 'Function', $param_types, $ret_type];
    my $func_data   = [$context, $ret_type, $parameters, $expressions];
    my $func        = [$func_type, $func_data, $pos];

    if ($name eq '#anonymous') {
        $name = "anonfunc$func";
    }

    if (!$self->{repl} and exists $context->{locals}->{$name} and $context->{locals}->{$name}->[0]->[1] ne 'Builtin') {
        $self->error($context, "cannot define function `$name` with same name as existing local", $pos);
    }

    if ($self->get_builtin_function($name)) {
        $self->error($context, "cannot redefine builtin function `$name`", $pos);
    }

    $context->{locals}->{$name} = $func;
    my $new_context = $self->new_context($context);

    # validate parameters
    my $got_default_value = 0;
    foreach my $param (@$parameters) {
        my ($type, $ident, $default_value) = @$param;

        push @$param_types, $type;

        my $value = $self->evaluate($new_context, $default_value);

        if (not defined $value) {
            if ($got_default_value) {
                $self->error($new_context, "in definition of function `$name`: missing default value for parameter `$ident` after previous parameter was declared with default value", $self->position($param));
            }

            $value = [$type, 0];
        } else {
            $got_default_value = 1;

            if (not $self->{types}->check($type, $value->[0])) {
                $self->error($new_context, "in definition of function `$name`: parameter `$ident` declared as " . $self->{types}->to_string($type) . " but default value has type " . $self->{types}->to_string($value->[0]), $self->position($value));
            }
        }

        $self->declare_variable($new_context, $type, $ident, $value);
    }

    # collect returned values to infer return type
    my @return_values;
    my $result;
    my $expr_pos;

    $new_context->{current_function} = $name;

    foreach my $expression (@$expressions) {
        $expr_pos = $self->position($expression);
        $result = $self->evaluate($new_context, $expression);

        # make note of a returned value
        if ($expression->[0] == INSTR_RET) {
            push @return_values, [$result, $expr_pos];
        }
    }

    delete $new_context->{current_function};

    # add final statement to return values
    push @return_values, [$result, $expr_pos];

    # type check return types
    my @return_types;

    my $ret_is_any = $self->{types}->is_equal($ret_type, ['TYPE', 'Any']);

    foreach my $entry (@return_values) {
        my ($value, $pos) = @$entry;
        my $type = $value->[0];

        # check for self-referential return value
        if ($ret_is_any && $type->[0] eq 'TYPEFUNC' && $type->[3] == $func_type->[3]) {
            $self->error($new_context, "in definition of function `$name`: self-referential return type", $pos);
        }

        # add type to list of return types
        push @return_types, $value->[0];
    }

    my $type = $self->{types}->unite(\@return_types);

    if (not $self->{types}->check($ret_type, $type)) {
        $self->error($new_context, "in definition of function `$name`: cannot return value of type " . $self->{types}->to_string($type) . " from function declared to return type " . $self->{types}->to_string($ret_type), $pos);
    }

    # update with inferred return type if original return type is Any
    if ($self->{types}->is_equal($ret_type, ['TYPE', 'Any'])) {
        $data->[1]      = $type;
        $func_type->[3] = $type;
        $func_data->[1] = $type;
    }

    return $func;
}

sub validate_function_argument_type {
    my ($self, $context, $name, $parameter, $arg_type, $pos) = @_;

    my $type1 = $parameter->[0];
    my $type2 = $arg_type;

    if (not $self->{types}->check($type1, $type2)) {
        $self->error($context, "in function call for `$name`, expected " . $self->{types}->to_string($type1) . " for parameter `$parameter->[1]` but got " . $self->{types}->to_string($type2), $pos);
    }
}

sub process_function_call_arguments {
    my ($self, $context, $name, $parameters, $arguments, $data) = @_;

    if (@$arguments > @$parameters) {
        $self->error($context, "extra arguments provided to function `$name` (takes " . @$parameters . " but passed " . @$arguments . ")", $self->position($data));
    }

    my $evaluated_arguments;
    my $processed_arguments = [];

    for (my $i = 0; $i < @$arguments; $i++) {
        my $arg = $arguments->[$i];
        if ($arg->[0] == INSTR_ASSIGN) {
            # named argument
            if (not defined $parameters->[$i]->[2]) {
                # ensure positional arguments are filled first
                $self->error($context, "positional parameter `$parameters->[$i]->[1]` must be filled before using named argument", $self->position($arguments->[$i]));
            }

            my $named_arg = $arguments->[$i]->[1];
            my $value     = $arguments->[$i]->[2];

            if ($named_arg->[0] == INSTR_IDENT) {
                my $ident = $named_arg->[1];

                my $found = 0;
                for (my $j = 0; $j < @$parameters; $j++) {
                    if ($parameters->[$j]->[1] eq $ident) {
                        $processed_arguments->[$j] = $value;
                        $evaluated_arguments->[$j] = $self->evaluate($context, $value);
                        $context->{locals}->{$parameters->[$j]->[1]} = $evaluated_arguments->[$j];
                        $found = 1;
                        last;
                    }
                }

                if (not $found) {
                    $self->error($context, "function `$name` has no parameter named `$ident`", $self->position($named_arg));
                }
            } else {
                $self->error($context, "named argument must be an identifier (got " . $self->{types}->to_string($named_arg->[0]) . ")", $self->position($named_arg));
            }
        } else {
            # normal argument
            $processed_arguments->[$i] = $arg;
            $evaluated_arguments->[$i] = $self->evaluate($context, $arg);
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
            $evaluated_arguments->[$i] = $self->evaluate($context, $parameters->[$i]->[2]);
            $context->{locals}->{$parameters->[$i]->[1]} = $evaluated_arguments->[$i];
        } else {
            # no argument or default argument
            if (not defined $evaluated_arguments->[$i]) {
                $self->error($context, "missing argument `$parameters->[$i]->[1]` to function `$name`", $self->position($data)),
            }
        }
    }

    # rewrite/desugar CALL arguments with positional arguments
    $data->[2] = $processed_arguments;
    return $evaluated_arguments;
}

sub get_cached_type {
    my ($self, $context, $name) = @_;

    if (exists $context->{typed}->{$name}) {
        return $context->{typed}->{$name};
    }

    if (defined $context->{parent}) {
        return $self->get_cached_type($context->{parent}, $name);
    }

    return undef;
}

sub function_call {
    my ($self, $context, $data) = @_;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;
    my $name;

    if ($target->[0] == INSTR_IDENT) {
        $name = $target->[1];
        $func = $self->get_variable($context, $name);

        if (not defined $func) {
            # undefined function
            $self->error($context, "cannot invoke undefined function `" . $self->output_value($target) . "`", $self->position($target));
        }

        if ($self->{types}->is_equal(['TYPE', 'Any'], $func->[0])) {
            return $func;
        }

        if ($func->[0]->[0] ne 'TYPEFUNC') {
            # not a function
            $self->error($context, "cannot invoke `$name` as a function (got " . $self->{types}->to_string($func->[0]) . ")", $self->position($target));
        }

        if ($func->[0]->[1] eq 'Builtin') {
            $self->{debug}->{print}->('FUNCS', "Calling builtin function `$name` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
            $func = $self->get_builtin_function($name);
            return $self->type_check_builtin_function_call($context, $func, $data, $name);
        } else {
            $self->{debug}->{print}->('FUNCS', "Calling user-defined function `$name` with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        }
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
        $self->{debug}->{print}->('FUNCS', "Calling passed function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $target;
        $name = "anonymous-1";
    } else {
        $self->{debug}->{print}->('FUNCS', "Calling anonymous function with arguments: " . Dumper($arguments) . "\n") if $self->{debug};
        $func = $self->evaluate($context, $target);
        $name = "anonymous-2";

        if (not $self->{types}->name_is($func->[0], 'TYPEFUNC')) {
            $self->error($context, "cannot invoke value of type " . $self->{types}->to_string($func->[0]) . " as a function", $self->position($target));
        }
    }

    my $cached_type = $self->get_cached_type($context, $func);
    return $cached_type if defined $cached_type;

    if (not defined $func->[1]) {
        return $func;
    }

    my $closure     = $func->[1]->[0];
    my $return_type = $func->[1]->[1];
    my $parameters  = $func->[1]->[2];
    my $expressions  = $func->[1]->[3];
    my $return_value;

    my $new_context = $self->new_context($closure);
    $new_context->{locals} = { %{$context->{locals}} };
    $new_context = $self->new_context($new_context);

    my $evaled_args = $self->process_function_call_arguments($new_context, $name, $parameters, $arguments, $data);

    # type-check arguments
    if (defined $parameters) {
        for (my $i = 0; $i < @$parameters; $i++) {
            $self->validate_function_argument_type($context, $name, $parameters->[$i], $evaled_args->[$i]->[0], $self->position($evaled_args->[$i]));
        }
    }

    $new_context->{typed}->{"$func"} = [['TYPE', 'Any'], 0];

    # invoke the function
    $new_context->{current_function} = $name;
    foreach my $expression (@$expressions) {
        $return_value = $self->evaluate($new_context, $expression);
        last if $expression->[0] == INSTR_RET; # XXX - handle all returns and final expression
    }

    # handle the return value/type
    if ($self->{types}->is_subtype($return_type, $return_value->[0])) {
        $return_value->[0] = $return_type;
    }

    # type-check return value
    if (not $self->{types}->check($return_type, $return_value->[0])) {
        $self->error($context, "cannot return " . $self->{types}->to_string($return_value->[0]) . " from function declared to return " . $self->{types}->to_string($return_type), $self->position($return_value));
    }

    if ($self->{types}->check($return_type, ['TYPE', 'Any'])) {
        # set inferred return type
        $func->[1]->[1] = $return_value->[0];
        $func->[0]->[3] = $return_value->[0];
    }

    $context->{typed}->{"$func"} = $return_value;
    return $return_value;
}

sub type_check_builtin_function_call {
    my ($self, $context, $builtin, $data, $name) = @_;

    my $return_type = $builtin->{ret};
    my $parameters  = $builtin->{params};
    my $func        = $builtin->{subref};
    my $validate    = $builtin->{vsubref};
    my $arguments   = $data->[2];

    my $evaled_args = $self->process_function_call_arguments($context, $name, $parameters, $arguments, $data);

    for (my $i = 0; $i < @$parameters; $i++) {
        $self->validate_function_argument_type($context, $name, $parameters->[$i], $evaled_args->[$i]->[0], $self->position($evaled_args->[$i]));
    }

    my $return_value;

    if ($validate) {
        $return_value = $validate->($self, $context, $name, $evaled_args);
    } else {
        $return_value = $func->($self, $context, $name, $evaled_args);
    }

    if ($self->{types}->is_subtype($return_type, $return_value->[0])) {
        $return_value->[0] = $return_type;
    }

    if (not $self->{types}->check($return_type, $return_value->[0])) {
        $self->error($context, "in function `$name`: cannot return " . $self->{types}->to_string($return_value->[0]) . " from function declared to return " . $self->{types}->to_string($return_type), $self->position($return_value));
    }

    return $return_value;
}

sub keyword_return {
    my ($self, $context, $data) = @_;

    if (not $context->{current_function}) {
        $self->error($context, "cannot use `return` outside of function", $self->position($data));
    }

    return $self->evaluate($context, $data->[1]);
}

sub conditional {
    my ($self, $context, $data) = @_;
    return $self->keyword_if($context, $data);
}

sub keyword_if {
    my ($self, $context, $data) = @_;

    # validate conditional
    $self->is_truthy($context, $data->[1]);

    my @types;
    my $result;

    # validate then
    $result = $self->evaluate($context, $data->[2]);
    push @types, $result->[0];

    # validate else
    if (defined $data->[3]) {
        $result = $self->evaluate($context, $data->[3]);
        push @types, $result->[0];
    }

    $result->[0] = $self->{types}->unite(\@types);
    return $result;
}

sub keyword_while {
    my ($self, $context, $data) = @_;

    # validate conditional
    $self->evaluate($context, $data->[1]);

    $context->{while_loop} = 1;

    # validate expressions
    my $result = $self->evaluate($context, $data->[2]);

    delete $context->{while_loop};

    return $result;
}

sub keyword_next {
    my ($self, $context, $data) = @_;

    if (not $context->{while_loop}) {
        $self->error($context, "cannot use `next` outside of loop", $self->position($data));
    }

    return [['TYPE', 'Null'], undef, $self->position($data)];
}

sub keyword_last {
    my ($self, $context, $data) = @_;

    if (not $context->{while_loop}) {
        $self->error($context, "cannot use `last` outside of loop", $self->position($data));
    }

    return [['TYPE', 'Null'], undef];
}

# rvalue array/map access
sub access_notation {
    my ($self, $context, $data) = @_;

    my $var = $self->evaluate($context, $data->[1]);

    # map index
    if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
        # desugar x.y to x['y']
        if ($data->[2]->[0] == INSTR_IDENT) {
            $data->[2] = [INSTR_LITERAL, ['TYPE', 'String'], $data->[2]->[1]];
        }

        my $key = $self->evaluate($context, $data->[2]);
        my $val = $var->[1]->{$key->[1]};
        return [['TYPE', 'Null'], undef, $self->position($data)] if not defined $val;
        return $val;
    }

    # array index
    if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
        my $index = $self->evaluate($context, $data->[2]);

        if ($self->{types}->check(['TYPE', 'Number'], $index->[0])) {
            my $val = $var->[1]->[$index->[1]];
            return [['TYPE', 'Null'], undef, $self->position($data)] if not defined $val;
            return $val;
        }

        # TODO support RANGE and x:y splices and negative indexing
    }

    # string index
    if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
        my $value = $self->evaluate($context, $data->[2]);

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

    $self->error($context, "cannot use ACCESS notation on object of type " . $self->{types}->to_string($var->[0]), $self->position($var));
}

# lvalue assignment
sub assignment {
    my ($self, $context, $data) = @_;

    my $pos = $self->position($data);

    my $left_value  = $data->[1];
    my $right_value = $self->evaluate($context, $data->[2]);

    # lvalue variable
    if ($left_value->[0] == INSTR_IDENT) {
        my $var = $self->get_variable($context, $left_value->[1]);
        $var // $self->error($context, "cannot assign to undeclared variable `$left_value->[1]`", $left_value->[2]);
        $self->set_variable($context, $left_value->[1], $right_value);
        return $right_value;
    }

    # lvalue array/map access
    if ($left_value->[0] == INSTR_ACCESS) {
        my $var = $self->evaluate($context, $left_value->[1]);

        if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
            # desugar x.y to x['y']
            if ($left_value->[2]->[0] == INSTR_IDENT) {
                $left_value->[2] = [INSTR_LITERAL, ['TYPE', 'String'], $left_value->[2]->[1]];
            }

            my $key = $self->evaluate($context, $left_value->[2]);

            if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
                my $val = $self->evaluate($context, $right_value);
                $var->[1]->{$key->[1]} = $val;
                return $val;
            }

            $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")", $self->position($key));
        }

        if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
            my $index = $self->evaluate($context, $left_value->[2]);

            if ($self->{types}->check(['TYPE', 'Number'], $index->[0])) {
                my $val = $self->evaluate($context, $right_value);
                $var->[1]->[$index->[1]] = $val;
                return $val;
            }

            $self->error($context, "Array index must be of type Number (got " . $self->{types}->to_string($index->[0]) . ")", $self->position($index));
        }

        if ($self->{types}->check(['TYPE', 'String'], $var->[0])) {
            my $value = $self->evaluate($context, $left_value->[2]);

            if ($value->[0] == INSTR_RANGE) {
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

                    $self->error($context, "cannot assign from type " . $self->{types}->to_string($right_value->[0]) . " to type " . $self->{types}->to_string($left_value->[0]) . " with RANGE in postfix []", $pos);
                }

                $self->error($context, "invalid types to RANGE (have " . $self->{types}->to_string($from->[0]) . " and " . $self->{types}->to_string($to->[0]) . ") inside assignment postfix []", $pos);
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

                $self->error($context, "cannot assign from type " . $self->{types}->to_string($right_value->[0]) . " to type " . $self->{types}->to_string($left_value->[0]) . " with postfix []", $pos);
            }

            $self->error($context, "invalid type " . $self->{types}->to_string($value->[0]) . " inside assignment postfix []", $pos);
        }

        $self->error($context, "cannot assign to postfix [] on type " . $self->{types}->to_string($var->[0]), $pos);
    }

    # an expression
    my $eval = $self->evaluate($context, $data->[1]);
    $self->error($context, "cannot assign to non-lvalue type " . $self->{types}->to_string($eval->[0]), $self->position($eval));
}

# rvalue array/map index
sub array_index_notation {
    my ($self, $context, $data) = @_;
    my $var = $self->evaluate($context, $data->[1]);

    # infer type
    if ($self->{types}->check($var->[0], ['TYPE', 'Any'])) {
        return $var;
    }

    # map index
    if ($self->{types}->check(['TYPE', 'Map'], $var->[0])) {
        my $key = $self->evaluate($context, $data->[2]);

        if ($self->{types}->check(['TYPE', 'String'], $key->[0])) {
            my $val = $var->[1]->{$key->[1]};
            return [['TYPE', 'Null'], undef] if not defined $val;
            return $val;
        }

        $self->error($context, "Map key must be of type String (got " . $self->{types}->to_string($key->[0]) . ")");
    }

    # array index
    if ($self->{types}->check(['TYPE', 'Array'], $var->[0])) {
        my $index = $self->evaluate($context, $data->[2]);

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
        my $value = $self->evaluate($context, $data->[2]->[1]);

        if ($value->[0] == INSTR_RANGE) {
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

# validate the program
sub validate {
    my ($self, $ast, %opt) = @_;
    $self->run($ast, %opt, 'silent' => 1);
    return; # explicit return so we do not return value of run()
}

1;
