#!/usr/bin/env perl

# Dumps a Plang abstract syntax tree as human-readable text.

package Plang::AST::Dumper;
use parent 'Plang::AST::Walker';

use warnings;
use strict;
use feature 'signatures';

use Data::Dumper;
use Devel::StackTrace;

use Plang::Constants::Instructions ':all';

sub new($class, %args) {
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->SUPER::initialize(%conf);

    # main instructions
    $self->override_instruction(INSTR_NOP, \&null_op);
    $self->override_instruction(INSTR_EXPR_GROUP, \&expression_group);
    $self->override_instruction(INSTR_LITERAL, \&literal);
    $self->override_instruction(INSTR_VAR, \&variable_declaration);
    $self->override_instruction(INSTR_MAPCONS, \&map_constructor);
    $self->override_instruction(INSTR_ARRAYCONS, \&array_constructor);
    $self->override_instruction(INSTR_EXISTS, \&keyword_exists);
    $self->override_instruction(INSTR_DELETE, \&keyword_delete);
    $self->override_instruction(INSTR_KEYS, \&keyword_keys);
    $self->override_instruction(INSTR_VALUES, \&keyword_values);
    $self->override_instruction(INSTR_COND, \&conditional);
    $self->override_instruction(INSTR_WHILE, \&keyword_while);
    $self->override_instruction(INSTR_NEXT, \&keyword_next);
    $self->override_instruction(INSTR_LAST, \&keyword_last);
    $self->override_instruction(INSTR_IF, \&keyword_if);
    $self->override_instruction(INSTR_AND, \&logical_and);
    $self->override_instruction(INSTR_OR, \&logical_or);
    $self->override_instruction(INSTR_ASSIGN, \&assignment);
    $self->override_instruction(INSTR_ADD_ASSIGN, \&add_assign);
    $self->override_instruction(INSTR_SUB_ASSIGN, \&sub_assign);
    $self->override_instruction(INSTR_MUL_ASSIGN, \&mul_assign);
    $self->override_instruction(INSTR_DIV_ASSIGN, \&div_assign);
    $self->override_instruction(INSTR_CAT_ASSIGN, \&cat_assign);
    $self->override_instruction(INSTR_IDENT, \&identifier);
    $self->override_instruction(INSTR_QIDENT, \&qualified_identifier);
    $self->override_instruction(INSTR_FUNCDEF, \&function_definition);
    $self->override_instruction(INSTR_CALL, \&function_call);
    $self->override_instruction(INSTR_RET, \&keyword_return);
    $self->override_instruction(INSTR_PREFIX_ADD, \&prefix_increment);
    $self->override_instruction(INSTR_PREFIX_SUB, \&prefix_decrement);
    $self->override_instruction(INSTR_POSTFIX_ADD, \&postfix_increment);
    $self->override_instruction(INSTR_POSTFIX_SUB, \&postfix_decrement);
    $self->override_instruction(INSTR_RANGE, \&range_operator);
    $self->override_instruction(INSTR_DOT_ACCESS, \&access);
    $self->override_instruction(INSTR_ACCESS, \&access);
    $self->override_instruction(INSTR_TRY, \&keyword_try);
    $self->override_instruction(INSTR_THROW, \&keyword_throw);
    $self->override_instruction(INSTR_TYPE, \&keyword_type);
    $self->override_instruction(INSTR_IMPORT, \&keyword_import);
    $self->override_instruction(INSTR_MODULE, \&keyword_module);
    $self->override_instruction(INSTR_STRING_I, \&string_interpolation);

    # unary operators
    $self->override_instruction(INSTR_NOT, \&unary_op);
    $self->override_instruction(INSTR_NEG, \&unary_op);
    $self->override_instruction(INSTR_POS, \&unary_op);

    # binary operators
    $self->override_instruction(INSTR_POW, \&binary_op);
    $self->override_instruction(INSTR_REM, \&binary_op);
    $self->override_instruction(INSTR_MUL, \&binary_op);
    $self->override_instruction(INSTR_DIV, \&binary_op);
    $self->override_instruction(INSTR_ADD, \&binary_op);
    $self->override_instruction(INSTR_SUB, \&binary_op);
    $self->override_instruction(INSTR_STRCAT, \&binary_op);
    $self->override_instruction(INSTR_STRIDX, \&binary_op);
    $self->override_instruction(INSTR_GTE, \&binary_op);
    $self->override_instruction(INSTR_LTE, \&binary_op);
    $self->override_instruction(INSTR_GT, \&binary_op);
    $self->override_instruction(INSTR_LT, \&binary_op);
    $self->override_instruction(INSTR_EQ, \&binary_op);
    $self->override_instruction(INSTR_NEQ, \&binary_op);
}

sub dispatch_instruction($self, $instr, $scope, $data) {
    return $self->{instr_dispatch}->[$instr]->($self, $scope, $data);
}

sub variable_declaration($self, $scope, $data) {
    my $type        = $data->[1];
    my $name        = $data->[2];
    my $initializer = $data->[3];
    my $right_value = undef;

    if ($initializer) {
        $right_value = $self->evaluate($scope, $initializer);
    } else {
        $right_value = $self->evaluate($scope, [INSTR_LITERAL, ['TYPE', 'Null'], undef]);
    }

    return "(var $name : " . $self->{types}->to_string($type) . " = $right_value)";
}

sub function_call($self, $scope, $data) {
    my $target    = $data->[1];
    my $arguments = $data->[2];

    my $text = '';

    if ($target->[0] == INSTR_IDENT) {
        $text .= "$target->[1]";
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
        $text .= '#anon-' . $target;
    } else {
        my $val = $self->evaluate($scope, $target);
        $text .= "(#expr-" . $target . " $val)";
    }

    if (@$arguments) {
        $text .= ' ';
        my @args;
        foreach my $arg (@$arguments) {
            my $t = $self->evaluate($scope, $arg);
            push @args, $t;
        }
        $text .= join ' ', @args;
    }

    return "(call $text)";
}

sub function_definition($self, $scope, $data) {
    my $ret_type    = $data->[1];
    my $name        = $data->[2];
    my $parameters  = $data->[3];
    my $expressions = $data->[4];

    my $text = "";

    $text .= "(return-type " . $self->{types}->to_string($ret_type) . ") ";

    my @params;

    foreach my $param (@$parameters) {
        my $type = $param->[0];
        my $ident = $param->[1];
        my $value = "";

        if (defined $param->[2]) {
            $value = $self->evaluate($scope, $param->[2]);
            $value = " = $value";
        }

        push @params, "($ident : " . $self->{types}->to_string($type) . $value . ')';
    }

    if (@params) {
        $text .= '(params "'. (join ' ', @params) . ') ';
    }

    my @exprs;

    foreach my $expr (@$expressions) {
        push @exprs, $self->evaluate($scope, $expr);
    }

    $text .= '(exprs ' . (join ' ', @exprs) . ')';

    return "(func-def $name $text)";
}

sub map_constructor($self, $scope, $data) {
    my $map = $data->[1];

    my @props;

    foreach my $entry (@$map) {
        my $key   = $self->evaluate($scope, $entry->[0]);
        my $value = $self->evaluate($scope, $entry->[1]);
        push @props, "($key: $value)";
    }

    my $text = join ' ', @props;

    if (length $text) {
        return "(map-cons $text)";
    } else {
        return '(map-cons)';
    }
}

sub array_constructor($self, $scope, $data) {
    my $array = $data->[1];

    my @values;
    foreach my $entry (@$array) {
        push @values, $self->evaluate($scope, $entry);
    }

    my $text = join ' ', @values;

    if (length $text) {
        return "(array-cons $text)";
    } else {
        return '(array-cons)';
    }
}

sub keyword_exists($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1][1]);
    my $key = $self->evaluate($scope, $data->[1][2]);
    return "(exists $var $key)";
}

sub keyword_delete($self, $scope, $data) {
    my $text = $self->evaluate($scope, $data->[1]);
    return "(delete $text)";
}

sub keyword_keys($self, $scope, $data) {
    my $map = $self->evaluate($scope, $data->[1]);
    return "(keys $map)";
}

sub keyword_values($self, $scope, $data) {
    my $map = $self->evaluate($scope, $data->[1]);
    return "(values $map)";
}

sub keyword_try($self, $scope, $data) {
    my $expr     = $data->[1];
    my $catchers = $data->[2];

    my $try = $self->evaluate($scope, $expr);

    my @catches;

    foreach my $catcher (@$catchers) {
        my ($cond, $body) = @$catcher;

        if (not $cond) {
            $cond = '(default)';
        } else {
            $cond = $self->evaluate($scope, $cond);
        }

        $body = $self->evaluate($scope, $body);

        push @catches, "($cond $body)";
    }

    my $catch = join ' ', @catches;

    return "(try $try $catch)";
}

sub keyword_throw($self, $scope, $data) {
    my $value = $self->evaluate($scope, $data->[1]);
    return "(throw $value)";
}

sub keyword_return($self, $scope, $data) {
    my $value = $self->evaluate($scope, $data->[1]);
    return "(return $value)";
}

sub keyword_next($self, $scope, $data) {
    return "(next)";
}

sub keyword_last($self, $scope, $data) {
    return "(last)";
}

sub keyword_while($self, $scope, $data) {
    my $cond = $self->evaluate($scope, $data->[1]);
    my $body = $self->evaluate($scope, $data->[2]);
    return "(while $cond $body)";
}

sub keyword_type($self, $scope, $data) {
    my $type  = $data->[1];
    my $name  = $data->[2];
    my $value = $data->[3];

    if (defined $value) {
        $value = $self->evaluate($scope, $value);
        return "(new-type $name " . $self->{types}->to_string($type) . " = $value)";
    } else {
        return "(new-type $name " . $self->{types}->to_string($type) . ")";
    }
}

sub keyword_module($self, $scope, $data) {
    my $ident = $self->evaluate($scope, $data->[1]);
    return "(module $ident)";
}

sub keyword_import($self, $scope, $data) {
    my $ident = $self->evaluate($scope, $data->[1]);
    return "(import $ident)";
}

sub add_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(add-assign $left $right)";
}

sub sub_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(sub-assign $left $right)";
}

sub mul_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(mul-assign $left $right)";
}

sub div_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(div-assign $left $right)";
}

sub cat_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(cat-assign $left $right)";
}

sub prefix_increment($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    return "(prefix-inc $var)";
}

sub prefix_decrement($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    return "(prefix-dec $var)";
}

sub postfix_increment($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    return "(postfix-inc $var)";
}

sub postfix_decrement($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    return "(postfix-dec $var)";
}

sub string_interpolation($self, $scope, $data) {
    return "(interpolate-string \"$data->[1]\")";
}

# ?: ternary conditional operator
sub conditional($self, $scope, $data) {
    return "(cond " . $self->keyword_if($scope, $data) . ")";
}

sub keyword_if($self, $scope, $data) {
    my $text = "(if ";
    $text .= $self->evaluate($scope, $data->[1]);
    $text .= " then ";
    $text .= $self->evaluate($scope, $data->[2]);
    $text .= " else ";
    $text .= $self->evaluate($scope, $data->[3]);
    $text .= ")";
    return $text;
}

sub logical_and($self, $scope, $data) {
    my $left_value = $self->evaluate($scope, $data->[1]);
    my $right_value = $self->evaluate($scope, $data->[2]);
    return "(logical-and $left_value $right_value)";
}

sub logical_or($self, $scope, $data) {
    my $left_value = $self->evaluate($scope, $data->[1]);
    my $right_value = $self->evaluate($scope, $data->[2]);
    return "(logical-or $left_value $right_value)";
}

sub range_operator($self, $scope, $data) {
    my ($to, $from) = ($data->[1], $data->[2]);
    $to   = $self->evaluate($scope, $to);
    $from = $self->evaluate($scope, $from);
    return "(range $to $from)";
}

# lvalue assignment
sub assignment($self, $scope, $data) {
    my $left_value  = $self->evaluate($scope, $data->[1]);
    my $right_value = $self->evaluate($scope, $data->[2]);
    return "(assign $left_value $right_value)";
}

# rvalue array/map access
sub access($self, $scope, $data) {
    my $var = $self->evaluate($scope, $data->[1]);
    my $val = $self->evaluate($scope, $data->[2]);
    return "(access $var $val)";
}

sub unary_op($self, $scope, $data) {
    my $instr = $data->[0];
    my $value = $self->evaluate($scope, $data->[1]);

    my $result;

    if ($instr == INSTR_NOT) {
        $result = "(not $value)";
    } elsif ($instr == INSTR_NEG) {
        $result = "(negate $value)";
    } elsif ($instr == INSTR_POS) {
        $result = "(positive $value)";
    }

    return $result;
}

sub binary_op($self, $scope, $data) {
    my $instr = $data->[0];
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);

    my $result;

    if ($instr == INSTR_EQ) {
        $result = "(eq $left $right)";
    } elsif ($instr == INSTR_NEQ) {
        $result = "(neq $left $right)";
    } elsif ($instr == INSTR_ADD) {
        $result = "(add $left $right)";
    } elsif ($instr == INSTR_SUB) {
        $result = "(sub $left $right)";
    } elsif ($instr == INSTR_MUL) {
        $result = "(mul $left $right)";
    } elsif ($instr == INSTR_DIV) {
        $result = "(div $left $right)";
    } elsif ($instr == INSTR_REM) {
        $result = "(rem $left $right)";
    } elsif ($instr == INSTR_POW) {
        $result = "(pow $left $right)";
    } elsif ($instr == INSTR_LT) {
        $result = "(lt $left $right)";
    } elsif ($instr == INSTR_LTE) {
        $result = "(lte $left $right)";
    } elsif ($instr == INSTR_GT) {
        $result = "(gt $left $right)";
    } elsif ($instr == INSTR_GTE) {
        $result = "(gte $left $right)";
    } elsif ($instr == INSTR_STRCAT) {
        $result = "(cat $left $right)";
    } elsif ($instr == INSTR_STRIDX) {
        $result = "(idx $left $right)";
    }

    return $result;
}

sub identifier($self, $scope, $data) {
    my $name;

    if (ref $data->[1] eq 'ARRAY') {
        $name = 'BEFORE-DESUGAR ' . (join '::', $data->[1]->@*);
    } else {
        $name = $data->[1];
    }

    return "(ident $name)";
}

sub qualified_identifier($self, $scope, $data) {
    return "(qualified-ident $data->[1][0] $data->[1][1])";
}

sub literal($self, $scope, $data) {
    my $type  = $data->[1];
    my $value = [$data->[1], $data->[2]];
    return "(literal " . $self->output_value($scope, $value, literal => 1). " : " . $self->{types}->to_string($type) . ")";
}

sub null_op {
    return "(null op)";
}

sub expression_group($self, $scope, $data) {
    return "(expr-group " . $self->execute($scope, $data->[1]) . ")";
}

sub execute($self, $scope, $ast) {
    my @text;

    foreach my $node (@$ast) {
        my $instruction = $node->[0];

        if ($instruction == INSTR_EXPR_GROUP) {
            return $self->execute($scope, $node->[1]);
        }

        push @text, $self->evaluate($scope, $node);
    }

    return join ' ', @text;
}

sub evaluate($self, $scope, $data) {
    return "" if not $data;

    my $ins = $data->[0];

    if ($ins !~ /^\d+$/) {
        return $data;
    }

    return $self->dispatch_instruction($ins, $scope, $data);
}

sub dump($self, $ast = undef, %opt) {
    if ($opt{tree}) {
        return $self->walk($ast, %opt);
    } else {
        return $self->walk([$ast], %opt);
    }
}

1;
