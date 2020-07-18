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

    # create a fresh empty environment
    my $context = $self->new_context;

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
    my ($self, $parent) = @_;

    return {
        locals => {},
        parent => $parent,
    };
}

sub set_variable {
    my ($self, $context, $name, $value) = @_;
    $context->{locals}->{$name} = $value;
    print "set_variable $name\n", Dumper($context->{locals}), "\n" if $self->{debug} >= 6;
}

sub get_variable {
    my ($self, $context, $name) = @_;

    print "get_variable: $name\n", Dumper($context->{locals}), "\n" if $self->{debug} >= 6;
    # look for variables in current scope
    if (exists $context->{locals}->{$name}) {
        return $context->{locals}->{$name};
    }

    # look for variables in enclosing scopes
    if (defined $context->{parent}) {
        my $var = $self->get_variable($context->{parent}, $name);
        return $var if defined $var;
    }

    # otherwise it's an undefined variable
    return undef;
}

sub interpret_ast {
    my ($self, $context, $ast) = @_;

    print "interpet ast: ", Dumper ($ast), "\n" if $self->{debug} >= 5;

    # try
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

    # catch
    if ($@) {
        return ['ERROR', $@];
    }

    return $last_statement_result;
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
    print $self->output_value($result), "\n" if defined $result->[1];
    return;
}

my %pretty_type = (
    'NIL'    => 'Nil',
    'NUM'    => 'Number',
    'STRING' => 'String',
    'BOOL'   => 'Boolean',
    'FUNC'   => 'Function',
);

my %eval_unary_op_NUM = (
    'NOT' => sub { ['BOOL', int ! $_[0]] },
    'NEG' => sub { ['NUM',      - $_[0]] },
    'POS' => sub { ['NUM',      + $_[0]] },
);

my %eval_binary_op_NUM = (
    'POW' => sub { ['NUM',  $_[0] ** $_[1]] },
    'REM' => sub { ['NUM',  $_[0]  % $_[1]] },
    'MUL' => sub { ['NUM',  $_[0]  * $_[1]] },
    'DIV' => sub { ['NUM',  $_[0]  / $_[1]] },
    'ADD' => sub { ['NUM',  $_[0]  + $_[1]] },
    'SUB' => sub { ['NUM',  $_[0]  - $_[1]] },
    'GTE' => sub { ['BOOL', $_[0] >= $_[1]] },
    'LTE' => sub { ['BOOL', $_[0] <= $_[1]] },
    'GT'  => sub { ['BOOL', $_[0]  > $_[1]] },
    'LT'  => sub { ['BOOL', $_[0]  < $_[1]] },
    'EQ'  => sub { ['BOOL', $_[0] == $_[1]] },
    'NEQ' => sub { ['BOOL', $_[0] != $_[1]] },
);

my %eval_binary_op_STRING = (
    'EQ'     => sub { ['BOOL',    $_[0]  eq $_[1]] },
    'NEQ'    => sub { ['BOOL',    $_[0]  ne $_[1]] },
    'LT'     => sub { ['BOOL',   ($_[0] cmp $_[1]) == -1] },
    'GT'     => sub { ['BOOL',   ($_[0] cmp $_[1]) ==  1] },
    'LTE'    => sub { ['BOOL',   ($_[0] cmp $_[1]) <=  0] },
    'GTE'    => sub { ['BOOL',   ($_[0] cmp $_[1]) >=  0] },
    'STRCAT' => sub { ['STRING',  $_[0]   . $_[1]] },
    'STRIDX' => sub { ['NUM', index $_[0], $_[1]] },
);

sub unary_op {
    my ($self, $context, $data, $op, $debug_msg) = @_;

    if ($data->[0] eq $op) {
        my $value  = $self->statement($context, $data->[1]);

        if ($debug_msg and $self->{debug} >= 3) {
            $debug_msg =~ s/\$a/$value->[1] ($value->[0])/g;
            print $debug_msg, "\n";
        }

        if ($self->is_arithmetic_type($value)) {
            if (exists $eval_unary_op_NUM{$op}) {
                return $eval_unary_op_NUM{$op}->($value->[1]);
            }
        }

        $self->error($context, "Cannot apply unary operator $op to type $pretty_type{$value->[0]}\n");
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

        if ($self->is_arithmetic_type($left_value) and $self->is_arithmetic_type($right_value)) {
            if (exists $eval_binary_op_NUM{$op}) {
                return $eval_binary_op_NUM{$op}->($left_value->[1], $right_value->[1]);
            }
        }

        if ($left_value->[0] eq 'STRING' or $right_value->[0] eq 'STRING') {
            if (exists $eval_binary_op_STRING{$op}) {
                $left_value->[1]  = chr $left_value->[1]  if $left_value->[0]  eq 'NUM';
                $right_value->[1] = chr $right_value->[1] if $right_value->[0] eq 'NUM';
                return $eval_binary_op_STRING{$op}->($left_value->[1], $right_value->[1]);
            }
        }

        $self->error($context, "Cannot apply binary operator $op (have types $pretty_type{$left_value->[0]} and $pretty_type{$right_value->[0]})");
    }
    return;
}

my %func_builtins = (
    'print'   => {
        # [['param1 name', default value], ['param2 name', default value], [...]]
        params => [['statement', undef], ['end', ['STRING', "\n"]]],
        subref => \&func_builtin_print,
    },
    'type'   => {
        params => [['expr', undef]],
        subref => \&func_builtin_type,
    },
);

sub func_builtin_print {
    my ($self, $name, $arguments) = @_;
    my ($text, $end) = ($arguments->[0]->[1], $arguments->[1]->[1]);
    return ['STDOUT', "$text$end"];
}

sub func_builtin_type {
    my ($self, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);
    return ['STRING', $pretty_type{$expr->[0]}];
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
                $context->{locals}->{$parameters->[$i]->[0]} = $evaluated_arguments->[$i];
            } else {
                # no argument or default argument
                $self->error($context, "Missing argument `$parameters->[$i]->[0]` to function `$name`.\n"),
            }
        } else {
            # argument provided
            $evaluated_arguments->[$i] = $self->statement($context, $arguments->[$i]);
            $context->{locals}->{$parameters->[$i]->[0]} = $evaluated_arguments->[$i];
        }
    }

    if (@$arguments > @$parameters) {
        $self->error($context, "Extra arguments provided to function `$name` (takes " . @$parameters . " but passed " . @$arguments . ")");
    }

    return $evaluated_arguments;
}

sub func_definition {
    my ($self, $context, $data) = @_;

    my $name       = $data->[1];
    my $parameters = $data->[2];
    my $statements = $data->[3];

    my $func = ['FUNC', [$parameters, $statements]];

    if ($name eq '#anonymous') {
        $name = "$func";
    }

    if (exists $context->{locals}->{$name}) {
        $self->error($context, "Cannot define function `$name` with same name as existing local");
    }

    $context->{locals}->{$name} = $func;
    return $func;
}

sub func_call {
    my ($self, $context, $data) = @_;

    my $name      = $data->[1];
    my $arguments = $data->[2];

    $Data::Dumper::Indent = 0 if $self->{debug} >= 5;
    print "Calling function `$name` with arguments: ", Dumper($arguments), "\n" if $self->{debug} >= 5;

    my $func = $self->get_variable($context, $name);

    if (not defined $func) {
        if (exists $func_builtins{$name}) {
            # builtin function
            return $self->call_builtin_function($context, $data, $name);
        } else {
            # undefined function
            $self->error($context, "Undefined function `$name`.");
        }
    }

    if ($func->[0] ne 'FUNC') {
        $self->error($context, "Cannot invoke `$name` as a function (have type $pretty_type{$func->[0]})");
    }

    my $parameters = $func->[1]->[0];
    my $statements = $func->[1]->[1];

    my $new_context = $self->new_context($context);
    my $ret = $self->process_func_call_arguments($new_context, $name, $parameters, $arguments);
    print "new context: ", Dumper($new_context), "\n" if $self->{debug} >= 5;

    # check for recursion limit
    if (++$self->{recursions} > $self->{max_recursion}) {
        $self->error($context, "Max recursion limit ($self->{max_recursion}) reached.");
    }


    # invoke the function
    my $result = $self->interpret_ast($new_context, $statements);;
    $self->{recursion}--;
    return $result;
}

sub is_truthy {
    my ($self, $context, $expr) = @_;

    my $result = $self->statement($context, $expr);

    if ($result->[0] eq 'NUM') {
        return $result->[1] != 0;
    }

    if ($result->[0] eq 'STRING') {
        return $result->[1] ne "";
    }

    if ($result->[0] eq 'BOOL') {
        return $result->[1] != 0;
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
        $new_string .= $text . $self->output_value($result);
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

    print "stmt ins: $ins (value: ", Dumper($value), ")\n" if $self->{debug} >= 4;

    if ($ins eq 'STMT') {
        return $self->statement($context, $data->[1]);
    }

    # statement group
    if ($ins eq 'STMT_GROUP') {
        my $new_context = $self->new_context($context);
        my $result = $self->interpret_ast($new_context, $value);
        return $result;
    }

    # literals
    return ['NUM',    $value] if $ins eq 'NUM';
    return ['STRING', $value] if $ins eq 'STRING';
    return ['BOOL',   $value] if $ins eq 'BOOL';

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
            $right_value = ['NIL', undef];
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
        return $self->assignment($context, $data);
    }

    # variable
    if ($ins eq 'IDENT') {
        my $var = $self->get_variable($context, $value);
        $self->error($context, "Attempt to use undeclared variable `$value`") if not defined $var;
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

        if ($self->is_arithmetic_type($var)) {
            $var->[1]++;
            return $var;
        }

        $self->error($context, "Cannot apply prefix-increment to type $pretty_type{$var->[0]}");
    }

    # prefix decrement
    if ($ins eq 'PREFIX_SUB') {
        my $token = $value;
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to prefix-decrement undeclared variable `$tok_value`");
        }

        if ($self->is_arithmetic_type($var)) {
            $var->[1]--;
            return $var;
        }

        $self->error($context, "Cannot apply prefix-decrement to type $pretty_type{$var->[0]}");
    }

    # short-circuiting logical and
    if ($ins eq 'AND') {
        my $left_value = $self->statement($context, $data->[1]);
        return $left_value if not $self->is_truthy($context, $left_value);
        return $self->statement($context, $data->[2]);
    }

    # short-circuiting logical or
    if ($ins eq 'OR') {
        my $left_value = $self->statement($context, $data->[1]);
        return $left_value if $self->is_truthy($context, $left_value);
        return $self->statement($context, $data->[2]);
    }

    # unary operators
    return $value if defined ($value = $self->unary_op($context, $data, 'NOT', '!/not $a'));
    return $value if defined ($value = $self->unary_op($context, $data, 'NEG', '- $a'));
    return $value if defined ($value = $self->unary_op($context, $data, 'POS', '+ $a'));

    # binary operators
    return $value if defined ($value = $self->binary_op($context, $data, 'POW', '$a ** $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'REM', '$a % $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'MUL', '$a * $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'DIV', '$a / $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'ADD', '$a + $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'SUB', '$a - $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'STRCAT', '$a & $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'STRIDX', '$a ~ $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GTE', '$a >= $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LTE', '$a <= $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GT',  '$a > $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LT',  '$a < $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'EQ',  '$a == $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'NEQ', '$a != $b'));

    # postfix increment
    if ($ins eq 'POSTFIX_ADD') {
        my $token = $data->[1];
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to postfix-increment undeclared variable `$tok_value`");
        }

        if ($self->is_arithmetic_type($var)) {
            my $temp_var = [$var->[0], $var->[1]];
            $var->[1]++;
            return $temp_var;
        }

        $self->error($context, "Cannot apply postfix-increment to type $pretty_type{$var->[0]}");
    }

    # postfix decrement
    if ($ins eq 'POSTFIX_SUB') {
        my $token = $data->[1];
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var = $self->get_variable($context, $tok_value);

        if (not defined $var) {
            $self->error($context, "Attempt to postfix-increment undeclared variable `$tok_value`");
        }

        if ($self->is_arithmetic_type($var)) {
            my $temp_var = [$var->[0], $var->[1]];
            $var->[1]--;
            return $temp_var;
        }

        $self->error($context, "Cannot apply postfix-decrement to type $pretty_type{$var->[0]}");
    }

    # range operator
    if ($ins eq 'RANGE') {
        my ($to, $from) = ($data->[1], $data->[2]);

        $to   = $self->statement($context, $to);
        $from = $self->statement($context, $from);

        return ['RANGE', $to, $from];
    }

    # array notation
    if ($ins eq 'POSTFIX_ARRAY') {
        my $token = $data->[1];
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var;

        if ($tok_type eq 'IDENT') {
            $var = $self->get_variable($context, $tok_value);

            if (not defined $var) {
                $self->error($context, "Cannot use postfix [] notation on undeclared variable `$tok_value`");
            }

            if (not defined $var->[1]) {
                $self->error($context, "Cannot use postfix [] notation on undefined variable `$tok_value`");
            }
        } else {
            $var = $token;
        }

        if ($var->[0] eq 'STRING') {
            my $value = $self->statement($context, $data->[2]->[1]);

            if ($value->[0] eq 'RANGE') {
                my $from = $value->[1];
                my $to = $value->[2];

                if ($from->[0] eq 'NUM' and $to->[0] eq 'NUM') {
                    return ['STRING', substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1])];
                } else {
                    $self->error($context, "Invalid types to RANGE (have $pretty_type{$from->[0]} and $pretty_type{$to->[0]}) inside postfix [] notation");
                }
            } elsif ($value->[0] eq 'NUM') {
                my $index = $value->[1];
                return ['STRING', substr($var->[1], $index, 1) // ""];
            } else {
                $self->error($context, "Invalid type $pretty_type{$value->[0]} inside postfix [] notation");
            }
        } else {
            $self->error($context, "Cannot use postfix [] notation on type $pretty_type{$var->[0]}");
        }
    }

    return $data;
}

sub output_value {
    my ($self, $value) = @_;

    # booleans should say 'true' or 'false'
    if ($value->[0] eq 'BOOL') {
        if ($value->[1] == 0) {
            return 'false';
        } else {
            return 'true';
        }
    }

    # STRING and NUM returned as-is
    return $value->[1];
}

sub assignment {
    my ($self, $context, $data) = @_;

    my $left_value  = $data->[1];
    my $right_value = $self->statement($context, $data->[2]);

    # plain variable
    if ($left_value->[0] eq 'IDENT') {
        my $var = $self->get_variable($context, $left_value->[1]);
        $self->error($context, "Attempt to assign to undeclared variable `$left_value->[1]`") if not defined $var;
        $self->set_variable($context, $left_value->[1], $right_value);
        return $right_value;
    }

    # postfix-array notation
    if ($left_value->[0] eq 'POSTFIX_ARRAY') {
        my $token = $left_value->[1];
        my ($tok_type, $tok_value) = ($token->[0], $token->[1]);

        my $var;

        if ($tok_type eq 'IDENT') {
            $var = $self->get_variable($context, $tok_value);

            if (not defined $var) {
                $self->error($context, "Cannot assign to postfix [] notation on undeclared variable `$tok_value`");
            }
        } else {
            $var = $token;
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
                    } elsif ($right_value->[0] eq 'NUM') {
                        substr($var->[1], $from->[1], $to->[1] + 1 - $from->[1]) = chr $right_value->[1];
                        return ['STRING', $var->[1]];
                    } else {
                        $self->error($context, "Cannot assign from type $pretty_type{$right_value->[0]} to type $pretty_type{$left_value->[0]} with RANGE in postfix [] notation");
                    }
                } else {
                    $self->error($context, "Invalid types to RANGE (have $pretty_type{$from->[0]} and $pretty_type{$to->[0]}) inside assignment postfix [] notation");
                }
            } elsif ($value->[0] eq 'NUM') {
                my $index = $value->[1];
                if ($right_value->[0] eq 'STRING') {
                    substr ($var->[1], $index, 1) = $right_value->[1];
                    return ['STRING', $var->[1]];
                } elsif ($right_value->[0] eq 'NUM') {
                    substr ($var->[1], $index, 1) = chr $right_value->[1];
                    return ['STRING', $var->[1]];
                } else {
                    $self->error($context, "Cannot assign from type $pretty_type{$right_value->[0]} to type $pretty_type{$left_value->[0]} with postfix [] notation");
                }
            } else {
                $self->error($context, "Invalid type $pretty_type{$value->[0]} inside assignment postfix [] notation");
            }
        } else {
            $self->error($context, "Cannot assign to postfix [] notation on type $pretty_type{$var->[0]}");
        }
    }

    # a statement
    my $eval = $self->statement($context, $data->[1]);
    $self->error($context, "Cannot assign to non-lvalue type $pretty_type{$eval->[0]}");
}

sub is_arithmetic_type {
    my ($self, $value) = @_;
    return 1 if $value->[0] eq 'NUM' or $value->[0] eq 'BOOL';
    return 0;
}

1;
