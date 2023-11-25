#!/usr/bin/env perl

# Base class to walk a Plang AST with stub subroutines that do nothing.
# Derive from this class to implement functionality for desired AST nodes.

package Plang::AST::Walker;

use warnings;
use strict;
use feature 'signatures';

use Plang::AST::Validator;
use Plang::Constants::Instructions ':all';

use Data::Dumper;
use Devel::StackTrace;

BEGIN {
    $Data::Dumper::Indent = 0;
    $Data::Dumper::Terse  = 1;
}

sub new($class, %args) {
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->{ast}       = $conf{ast};
    $self->{debug}     = $conf{debug};
    $self->{dumper}    = $conf{dumper};
    $self->{embedded}  = $conf{embedded} // 0;
    $self->{types}     = $conf{types};
    $self->{namespace} = $conf{namespace};

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
    $self->{instr_dispatch}->[INSTR_QIDENT]      = \&qualified_identifier;
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
    $self->{instr_dispatch}->[INSTR_MODULE]      = \&keyword_module;
    $self->{instr_dispatch}->[INSTR_IMPORT]      = \&keyword_import;
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

sub override_instruction($self, $instr, $sub) {
    $self->{instr_dispatch}->[$instr] = $sub;
}

sub dispatch_instruction($self, $instr, $scope, $data) {
    if ($self->{debug}) {
        $self->{debug}->{print}->('INSTR', "Dispatching instruction $pretty_instr[$instr]\n");
    }

    return $self->{instr_dispatch}->[$instr]->($self, $scope, $data);
}

sub unary_op($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub binary_op($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub variable_declaration($self, $scope, $data) {
    my $type        = $data->[1];
    my $name        = $data->[2];
    my $initializer = $data->[3];

    if ($initializer) {
        $self->evaluate($scope, $initializer);
    } else {
        $self->evaluate($scope, [INSTR_LITERAL, ['TYPE', 'Null'], undef]);
    }

    $self->declare_variable($scope, $type, $name, undef);
}

sub function_call($self, $scope, $data) {
    my $target    = $data->[1];
    my $arguments = $data->[2];

    if ($target->[0] == INSTR_IDENT) {
        $self->evaluate($scope, $target);
    } elsif ($self->{types}->name_is($target->[0], 'TYPEFUNC')) {
    } else {
        $self->evaluate($scope, $target);
    }

    my $func_scope = $self->new_scope($scope);

    if (@$arguments) {
        foreach my $arg (@$arguments) {
            $self->evaluate($func_scope, $arg);
        }
    }
}

sub function_definition($self, $scope, $data) {
    my $parameters  = $data->[3];
    my $expressions = $data->[4];

    foreach my $param (@$parameters) {
        my $type = $param->[0];
        my $ident = $param->[1];

        if (defined $param->[2]) {
            $self->evaluate($scope, $param->[2]);
        }
    }

    foreach my $expr (@$expressions) {
        $self->evaluate($scope, $expr);
    }
}

sub map_constructor($self, $scope, $data) {
    my $map = $data->[1];

    foreach my $entry (@$map) {
        $self->evaluate($scope, $entry->[0]);
        $self->evaluate($scope, $entry->[1]);
    }
}

sub array_constructor($self, $scope, $data) {
    my $array = $data->[1];

    foreach my $entry (@$array) {
        $self->evaluate($scope, $entry);
    }
}

sub keyword_exists($self, $scope, $data) {
    $self->evaluate($scope, $data->[1][1]);
    $self->evaluate($scope, $data->[1][2]);
}

sub keyword_delete($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub keyword_keys($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub keyword_values($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub keyword_try($self, $scope, $data) {
    my $expr     = $data->[1];
    my $catchers = $data->[2];

    my $new_scope = $self->new_scope($scope);

    $self->declare_variable($new_scope, ['TYPE', 'String'], 'e', 'dummy');

    $self->evaluate($new_scope, $expr);

    foreach my $catcher (@$catchers) {
        my ($cond, $body) = @$catcher;

        if ($cond) {
            $self->evaluate($new_scope, $cond);
        }

        $self->evaluate($new_scope, $body);
    }
}

sub keyword_throw($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub keyword_return($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub keyword_next($self, $scope, $data) {}

sub keyword_last($self, $scope, $data) {}

sub keyword_while($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub keyword_type($self, $scope, $data) {
    my $type  = $data->[1];
    my $name  = $data->[2];
    my $value = $data->[3];

    if (defined $value) {
        $self->evaluate($scope, $value);
    }

    if ($type->[0] eq 'TYPEMAP') {
        my $map = $type->[1];

        foreach my $entry (@$map) {
            my $value = $entry->[2];

            if (defined $value) {
                $self->evaluate($scope, $value);
            }
        }
    }
}

sub keyword_module($self, $scope, $data) {}

sub keyword_import($self, $scope, $data) {}

sub add_assign($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub sub_assign($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub mul_assign($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub div_assign($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub cat_assign($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub prefix_increment($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub prefix_decrement($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub postfix_increment($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub postfix_decrement($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
}

sub string_interpolation($self, $scope, $data) {
    $self->interpolate_string($scope, $data->[1], dryrun => 1);
}

# ?: ternary conditional operator
sub conditional($self, $scope, $data) {
    $self->keyword_if($scope, $data);
}

sub keyword_if($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
    $self->evaluate($scope, $data->[3]);
}

sub logical_and($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub logical_or($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub range_operator($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

# lvalue assignment
sub assignment($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

# rvalue array/map access
sub access($self, $scope, $data) {
    $self->evaluate($scope, $data->[1]);
    $self->evaluate($scope, $data->[2]);
}

sub identifier($self, $scope, $data) {}

sub qualified_identifier($self, $scope, $data) {
    my $module     = $data->[1][0];
    my $identifier = $data->[1][1];

    if (exists $self->{namespace}->{modules}->{$module}
            and exists $self->{namespace}->{modules}->{$module}->{$identifier}) {
        return $self->{namespace}->{modules}->{$module}->{$identifier};
    }
    return undef;
}

sub literal($self, $scope, $data) {}

sub null_op {}

sub expression_group($self, $scope, $data) {
    $self->execute($self->new_scope($scope), $data->[1]);
}

# walks a Plang AST
sub walk($self, $ast = undef, %opt) {
    # ast can be supplied via new() or via this run() subroutine
    $ast ||= $self->{ast};

    # make sure we were given a program
    if (not $ast) {
        print STDERR "No program.\n";
        return;
    }

    # set up the global environment
    my $scope = {};

    return $self->execute($scope, $ast);
}

sub execute($self, $scope, $ast) {
    if ($self->{debug}) {
        # verbose AST
        # (dumps whole program AST as an unreadable mess -- TODO: indentation and line-breaks in AST::Dumper)
        $self->{debug}->{print}->('ASTV', "interpret ast: " . $self->{dumper}->dump($ast, tree => 1) . "\n");
    }

    foreach my $node (@$ast) {
        $self->{debug}->{print}->('AST', "AST node: " . $self->{dumper}->dump($node) . "\n") if $self->{debug};

        my $instruction = $node->[0];

        if ($instruction == INSTR_EXPR_GROUP) {
            return $self->execute($scope, $node->[1]);
        }

        $self->evaluate($scope, $node);
    }
}

sub evaluate($self, $scope, $data) {
    return if not $data;

    my $ins = $data->[0];

    if ($ins !~ /^\d+$/) {
        if ($self->{debug} && $self->{debug}->{tags}->{INSTRUNK}) {
            print "Unknown instruction ", Dumper($ins), "\n";
            my $trace = Devel::StackTrace->new;
            print $trace->as_string;
        }
        return $data;
    }

    if ($self->{debug}) {
        $self->{debug}->{print}->('EVAL',    "eval $pretty_instr[$ins]: " . $self->{dumper}->dump($data) . "\n");
        $self->{debug}->{print}->('EVALRAW', "eval $pretty_instr[$ins]: " . Dumper($data) . "\n");
    }

    my $result = $self->dispatch_instruction($ins, $scope, $data);

    if ($self->{debug}) {
        $self->{debug}->{print}->('EVAL', "done $pretty_instr[$ins]: " . Dumper($result) . "\n");
    }

    return $result;
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

    # check builtins
    if (exists $self->{namespace}->{builtins}->{$name}) {
        return $self->{namespace}->{builtins}->{$name};
    }

    # otherwise it's an undefined variable
    return (undef);
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
    local $Data::Dumper::Indent = 0;
    local $Data::Dumper::Terse  = 1;
    local $Data::Dumper::Useqq  = 1;

    $text = Dumper($text);
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

use Plang::Interpreter;

sub parse_string($self, $string) {
    my $interpreter = Plang::Interpreter->new; # TODO reuse interpreter
    return $interpreter->parse_string($string);
}

sub interpolate_string($self, $scope, $string, %opts) {
    my $new_string = '';
    while ($string =~ /\G(.*?)(\{(?:[^\}\\]|\\.)*\})/gc) {
        my ($text, $interpolate) = ($1, $2);

        my $ast = $self->parse_string($interpolate);

        if (not $opts{dryrun}) {
            # run modules to desugar AST
            my $modules = Plang::Modules->new(types => $self->{types});
            $modules->import_modules($ast);

            # run validator to desugar AST
            my $validator = Plang::AST::Validator->new(types => $self->{types});
            my $errors = $validator->validate($ast, scope => $scope);

            if ($errors) {
                print STDERR $errors->[1];
                exit 1;
            }
        }

        my $result = $self->execute($scope, $ast);

        if (not $opts{dryrun}) {
            $new_string .= $text . $self->output_value($scope, $result);
        }
    }

    if (not $opts{dryrun}) {
        $string =~ /\G(.*)/gc;
        $new_string .= $1;
    }

    return $new_string;
}

sub position($self, $data) {
    return $data->[@$data - 1]; # position information is always the last element
}

1;
