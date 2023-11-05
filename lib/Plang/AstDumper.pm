#!/usr/bin/env perl

# Dumps a Plang abstract syntax tree as human-readable text.

package Plang::AstDumper;

use warnings;
use strict;
use feature 'signatures';

use Data::Dumper;
use Devel::StackTrace;

use Plang::Constants::Instructions ':all';

use parent 'Plang::AstInterpreter';

sub new($class, %args) {
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->{ast}      = $conf{ast};
    $self->{embedded} = $conf{embedded} // 0;

    $self->{types} = $conf{types} // die 'Missing types';

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

sub dispatch_instruction($self, $instr, $scope, $data) {
    # main instructions
    if ($instr < INSTR_NOT) {
        return $self->{instr_dispatch}->[$instr]->($self, $scope, $data);
    }

    # unary and binary operators
    return $self->{instr_dispatch}->[$instr]->($self, $instr, $scope, $data);
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

    return "(var $name : " . $self->type_to_string($type) . " = $right_value)";
}

sub function_call($self, $scope, $data) {
    my $target    = $data->[1];
    my $arguments = $data->[2];

    my $text = "";

    if ($target->[0] == INSTR_IDENT) {
        $text .= "$target->[1] ";
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
        $text .= "anonymous-1 ";
    } else {
        $text .= "anonymous-2 ";
    }

    if (@$arguments) {
        $text .= "(args ";
        my @args;
        foreach my $arg (@$arguments) {
            my $t = $self->evaluate($scope, $arg);
            push @args, $t;
        }
        $text .= join ', ', @args;
        $text .= ")";
    }

    return "(call $text)";
}

sub function_definition($self, $scope, $data) {
    my $ret_type    = $data->[1];
    my $name        = $data->[2];
    my $parameters  = $data->[3];
    my $expressions = $data->[4];

    my $text = "";

    $text .= "(return-type " . $self->type_to_string($ret_type) . ") ";

    my @params;

    foreach my $param (@$parameters) {
        my $type = $param->[0];
        my $ident = $param->[1];
        my $value = "";

        if (defined $param->[2]) {
            $value = $self->evaluate($scope, $param->[2]);
            $value = " = $value";
        }

        push @params, "($ident : " . $self->type_to_string($type) . $value . ')';
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
        my $key   = $entry->[0];
        my $value = $self->evaluate($scope, $entry->[1]);
        push @props, "($key->[1]: $value)";
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
    my $name    = $data->[1];
    my $type    = $data->[2];
    return "(new-type $name " . $self->type_to_string($type) . ")";
}

sub add_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(add-assign $left $right)";
}

sub sub_assign($self, $scope, $data) {
    my $left  = $self->evaluate($scope, $data->[1]);
    my $right = $self->evaluate($scope, $data->[2]);
    return "(add-assign $left $right)";
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
    return "(interpolate-string " . $self->interpolate_string($scope, $data->[1]) . ")";
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

sub unary_op($self, $instr, $scope, $data) {
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

sub binary_op($self, $instr, $scope, $data) {
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
    return "(ident $data->[1])";
}

sub literal($self, $scope, $data) {
    my $type  = $data->[1];
    my $value = [$data->[1], $data->[2]];
    return "(literal " . $self->output_value($value, literal => 1). " : " . $self->type_to_string($type) . ")";
}

sub null_op {
    return "(null op)";
}

sub expression_group($self, $scope, $data) {
    return "(expr-group " . $self->execute($scope, $data->[1]) . ")";
}

# just like typeof() except include function parameter identifiers and default values
sub introspect($self, $data) {
    my $type  = $data->[0];
    my $value = $data->[1];

    if ($type->[0] eq 'TYPEFUNC') {
        my $ret_type = $self->{types}->to_string($value->[1]);

        my @params;
        foreach my $param (@{$value->[2]}) {
            my $param_type = $self->{types}->to_string($param->[0]);
            if (defined $param->[2]) {
                my $default_value = $self->evaluate($self->new_scope, $param->[2]);
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

use Plang::Interpreter;

sub parse_string($self, $string) {
    my $interpreter = Plang::Interpreter->new; # TODO reuse interpreter
    my $program = $interpreter->parse_string($string);
    return $program->[0][1];
}

sub interpolate_string($self, $scope, $string) {
    my $new_string = "";

    while ($string =~ /\G(.*?)(\{(?:[^\}\\]|\\.)*\})/gc) {
        my ($text, $interpolate) = ($1, $2);
        my $ast = $self->parse_string($interpolate);
        my $result = $self->execute($scope, $ast);
        $new_string .= $text . $result;
    }

    $string =~ /\G(.*)/gc;
    $new_string .= $1;
    return $new_string;
}

# converts a map to a string
# note: trusts $var to be Map type
sub map_to_string($self, $var) {
    my $hash = $var->[1];
    my $string = '{';

    my @entries;
    foreach my $key (sort keys %$hash) {
        my $value = $hash->{$key};
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
sub array_to_string($self, $var) {
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

sub value_to_string($self, $value) {
    return $self->output_value($value);
}

sub type_to_string($self, $type) {
    return $self->{types}->to_string($type);
}

# returns a Plang AST as dumped as human-readable text
sub dump($self, $ast = undef, %opt) {
    # ast can be supplied via new() or via this run() subroutine
    $ast ||= $self->{ast};

    # make sure we were given a program
    if (not $ast) {
        print STDERR "No program to dump.\n";
        return;
    }

    # set up the (unused) global environment
    my $scope = {};

    # interpret the expressions and return the human-readable text
    return $self->execute($scope, [$ast]);
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

1;
