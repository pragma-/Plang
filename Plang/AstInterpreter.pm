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
}

my %pretty_types = (
    'NULL'    => 'Null',
    'NUM'     => 'Number',
    'STRING'  => 'String',
    'BOOL'    => 'Boolean',
    'FUNC'    => 'Function',
    'BUILTIN' => 'Builtin',
    'MAP'     => 'Map',
    'ARRAY'   => 'Array',
);

sub pretty_type {
    my ($self, $value) = @_;
    my $type = $pretty_types{$value->[0]};
    return $value->[0] if not defined $type;
    return $type;
}

sub error {
    my ($self, $context, $err_msg) = @_;
    chomp $err_msg;
    $self->{dprint}->('ERRORS', "Got error: $err_msg\n");
    die "Error: $err_msg\n";
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
    $self->{dprint}->('VARS', "set_variable $name\n" . Dumper($context->{locals}) . "\n");
}

sub get_variable {
    my ($self, $context, $name, %opt) = @_;

    $self->{dprint}->('VARS', "get_variable: $name\n" . Dumper($context->{locals}) . "\n");

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

        if ($self->{debug} and $debug_msg) {
            $debug_msg =~ s/\$a/$value->[1] ($value->[0])/g;
            $self->{dprint}->('OPERS', "$debug_msg\n");
        }

        if ($self->is_arithmetic_type($value)) {
            if (exists $eval_unary_op_NUM{$op}) {
                return $eval_unary_op_NUM{$op}->($value->[1]);
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
            $self->{dprint}->('OPERS', "$debug_msg\n");
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

        $self->error($context, "cannot apply binary operator $op (have types " . $self->pretty_type($left_value) . " and " . $self->pretty_type($right_value) . ")");
    }
    return;
}

# builtin functions
my %function_builtins = (
    'print'   => {
        # [['param1 name', default value], ['param2 name', default value], [...]]
        params => [['expr', undef], ['end', ['STRING', "\n"]]],
        subref => \&function_builtin_print,
    },
    'type'   => {
        params => [['expr', undef]],
        subref => \&function_builtin_type,
    },
    'Number' => {
        params => [['expr', undef]],
        subref => \&function_builtin_Number,
    },
    'String' => {
        params => [['expr', undef]],
        subref => \&function_builtin_String,
    },
    'Boolean' => {
        params => [['expr', undef]],
        subref => \&function_builtin_Boolean,
    },
    'Null' => {
        params => [['expr', undef]],
        subref => \&function_builtin_Null,
    },
    'Function' => {
        params => [['expr', undef]],
        subref => \&function_builtin_CannotConvert,
    },
    'Builtin' => {
        params => [['expr', undef]],
        subref => \&function_builtin_CannotConvert,
    },
    'Map' => {
        params => [['expr', undef]],
        subref => \&function_builtin_Map,
    },
    'Array' => {
        params => [['expr', undef]],
        subref => \&function_builtin_Array,
    },
);

# builtin print
sub function_builtin_print {
    my ($self, $context, $name, $arguments) = @_;
    my ($text, $end) = ($self->output_value($arguments->[0]), $arguments->[1]->[1]);
    print "$text$end";
    return ['NULL', undef];
}

# builtin type
sub function_builtin_type {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);
    return ['STRING', $self->pretty_type($expr)];
}

# cast functions
sub function_builtin_Number {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($expr->[0] eq 'NULL') {
        return ['NUM', 0];
    }

    if ($expr->[0] eq 'NUM') {
        return $expr;
    }

    if ($expr->[0] eq 'STRING') {
        return ['NUM', $expr->[1] + 0];
    }

    if ($expr->[0] eq 'BOOL') {
        return ['NUM', !!$expr->[1]];
    }

    $self->error($context, "cannot convert type " . $self->pretty_type($expr) . " to Number");
}

sub function_builtin_String {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($expr->[0] eq 'NULL') {
        return ['STRING', ''];
    }

    if ($expr->[0] eq 'NUM') {
        return ['STRING', $expr->[1]];
    }

    if ($expr->[0] eq 'STRING') {
        return $expr;
    }

    if ($expr->[0] eq 'BOOL') {
        return ['STRING', $self->output_value($expr)];
    }

    if ($expr->[0] eq 'MAP') {
        return ['STRING', $self->map_to_string($expr)];
    }

    if ($expr->[0] eq 'ARRAY') {
        return ['STRING', $self->array_to_string($expr)];
    }

    $self->error($context, "cannot convert type " . $self->pretty_type($expr) . " to String");
}

sub function_builtin_Boolean {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($expr->[0] eq 'NULL') {
        return ['BOOL', 0];
    }

    if ($expr->[0] eq 'NUM') {
        if ($self->is_truthy($context, $expr)) {
            return ['BOOL', 1];
        } else {
            return ['BOOL', 0];
        }
    }

    if ($expr->[0] eq 'STRING') {
        if (not $self->is_truthy($context, $expr)) {
            return ['BOOL', 0];
        } else {
            return ['BOOL', 1];
        }
    }

    if ($expr->[0] eq 'BOOL') {
        return $expr;
    }

    $self->error($context, "cannot convert type " . $self->pretty_type($expr) . " to Boolean");
}

sub function_builtin_Null {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);
    return ['NULL', undef];
}

sub function_builtin_Map {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($expr->[0] eq 'STRING') {
        my $mapinit = $self->parse_string($expr->[1])->[0]->[1];

        if ($mapinit->[0] ne 'MAPINIT') {
            $self->error($context, "not a valid Map inside String in Map() cast (got `$expr->[1]`)");
        }

        return $self->statement($context, $mapinit);
    }

    $self->error($context, "cannot convert type " . $self->pretty_type($expr) . " to Map");
}

sub function_builtin_Array {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);

    if ($expr->[0] eq 'STRING') {
        my $mapinit = $self->parse_string($expr->[1])->[0]->[1];

        if ($mapinit->[0] ne 'ARRAYINIT') {
            $self->error($context, "not a valid Array inside String in Array() cast (got `$expr->[1]`)");
        }

        return $self->statement($context, $mapinit);
    }

    $self->error($context, "cannot convert type " . $self->pretty_type($expr) . " to Array");
}

sub function_builtin_CannotConvert {
    my ($self, $context, $name, $arguments) = @_;
    my ($expr) = ($arguments->[0]);
    $self->error($context, "cannot convert type " . $self->pretty_type($expr) . " to $name");
}

sub add_builtin_function {
    my ($self, $name, $parameters, $subref) = @_;
    $function_builtins{$name} = { params => $parameters, subref => $subref };
}

sub get_builtin_function {
    my ($self, $name) = @_;
    return $function_builtins{$name};
}

sub call_builtin_function {
    my ($self, $context, $data, $name) = @_;

    my $parameters = $function_builtins{$name}->{params};
    my $func       = $function_builtins{$name}->{subref};
    my $arguments  = $data->[2];

    my $evaled_args = $self->process_function_call_arguments($context, $name, $parameters, $arguments);

    return $func->($self, $context, $name, $evaled_args);
}

sub process_function_call_arguments {
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

sub function_definition {
    my ($self, $context, $data) = @_;

    my $name       = $data->[1];
    my $parameters = $data->[2];
    my $statements = $data->[3];

    my $func = ['FUNC', [$context, $parameters, $statements]];

    if ($name eq '#anonymous') {
        $name = "anonfunc$func";
        $name =~ s/ARRAY\(/@/;
        $name =~ s/\)$//;
    }

    if (!$self->{repl} and exists $context->{locals}->{$name} and $context->{locals}->{$name}->[0] ne 'BUILTIN') {
        $self->error($context, "cannot define function `$name` with same name as existing local");
    }

    if ($self->get_builtin_function($name)) {
        $self->error($context, "cannot redefine builtin function `$name`");
    }

    $context->{locals}->{$name} = $func;
    return $func;
}

sub function_call {
    my ($self, $context, $data) = @_;

    $Data::Dumper::Indent = 0;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;

    if ($target->[0] eq 'IDENT') {
        $self->{dprint}->('FUNCS', "Calling function `$target->[1]` with arguments: " . Dumper($arguments) . "\n");
        $func = $self->get_variable($context, $target->[1]);
        $func = undef if $func->[0] eq 'BUILTIN';
    } else {
        $self->{dprint}->('FUNCS', "Calling anonymous function with arguments: " . Dumper($arguments) . "\n");
        $func = $self->statement($context, $target);
    }

    if (not defined $func) {
        if ($target->[0] eq 'IDENT' and exists $function_builtins{$target->[1]}) {
            # builtin function
            return $self->call_builtin_function($context, $data, $target->[1]);
        } else {
            # undefined function
            $self->error($context, "Undefined function `" . $self->output_value($target) . "`.");
        }
    }

    if ($func->[0] ne 'FUNC') {
        $self->error($context, "cannot invoke `" . $self->output_value($func) . "` as a function (have type " . $self->pretty_type($func) . ")");
    }

    my $closure    = $func->[1]->[0];
    my $parameters = $func->[1]->[1];
    my $statements = $func->[1]->[2];

    # wedge closure in between current scope and previous scope
    my $new_context = $self->new_context($closure);
    $new_context->{locals} = { %{$context->{locals}} }; # assign copy of current scope's locals so we don't recurse into its parent
    $new_context = $self->new_context($new_context);    # make new current empty scope with previous current scope as parent

    my $ret = $self->process_function_call_arguments($new_context, $target->[1], $parameters, $arguments);

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

    $Data::Dumper::Indent = 0;
    $self->{dprint}->('STMT', "stmt ins: $ins (value: " . Dumper($value) . ")\n");

    if ($ins eq 'STMT') {
        return $self->statement($context, $data->[1]);
    }

    # statement group
    if ($ins eq 'STMT_GROUP') {
        my $new_context = $self->new_context($context);
        return $self->interpret_ast($new_context, $value);
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
            $right_value = ['NULL', undef];
        }

        if (!$self->{repl} and (my $var = $self->get_variable($context, $value, locals_only => 1))) {
            if ($var->[0] ne 'BUILTIN') {
                $self->error($context, "cannot redeclare existing local `$value`");
            }
        }

        if ($self->get_builtin_function($value)) {
            $self->error($context, "cannot override builtin function `$value`");
        }

        $self->set_variable($context, $value, $right_value);
        return $right_value;
    }

    # map initializer
    if ($ins eq 'MAPINIT') {
        my $map     = $data->[1];
        my $hashref = {};

        foreach my $entry (@$map) {
            if ($entry->[0]->[0] eq 'IDENT') {
                my $var = $self->get_variable($context, $entry->[0]->[1]);
                return $self->error($context, "cannot use undeclared variable `$entry->[0]->[1]` to assign Map key");

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

    # array initializer
    if ($ins eq 'ARRAYINIT') {
        my $array    = $data->[1];
        my $arrayref = [];

        foreach my $entry (@$array) {
            push @$arrayref, $self->statement($context, $entry);
        }

        return ['ARRAY', $arrayref];
    }

    # exists keyword
    if ($ins eq 'EXISTS') {
        # check for key in map
        if ($value->[0] eq 'ARRAY_INDEX') {
            my $var = $self->statement($context, $value->[1]);

            # map index
            if ($var->[0] eq 'MAP') {
                my $key = $self->statement($context, $value->[2]);

                if ($key->[0] eq 'STRING') {
                    if (exists $var->[1]->{$key->[1]}) {
                        return ['BOOL', 1];
                    } else {
                        return ['BOOL', 0];
                    }
                }

                $self->error($context, "Map key must be of type String (got " . $self->pretty_type($key) . ")");
            }

            $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($var) . ")");
        }

        $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($value) . ")");
    }

    # delete keyword
    if ($ins eq 'DELETE') {
        # delete one key in map
        if ($value->[0] eq 'ARRAY_INDEX') {
            my $var = $self->statement($context, $value->[1]);

            # map index
            if ($var->[0] eq 'MAP') {
                my $key = $self->statement($context, $value->[2]);

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
        if ($value->[0] eq 'IDENT') {
            my $var = $self->get_variable($context, $value->[1]);

            if ($var->[0] eq 'MAP') {
                $var->[1] = {};
                return $var;
            }

            $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($var) . ")");
        }

        $self->error($context, "delete must be used on Maps (got " . $self->pretty_type($value) . ")");
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

    # next
    if ($ins eq 'NEXT') {
        return ['NEXT', undef];
    }

    # last
    if ($ins eq 'LAST') {
        return ['LAST', undef];
    }

    # while loop
    if ($ins eq 'WHILE') {
        while ($self->is_truthy($context, $data->[1])) {
            if (++$self->{iterations} > $self->{max_iterations}) {
                $self->error($context, "Max iteration limit ($self->{max_iterations}) reached.");
            }

            my $result = $self->statement($context, $data->[2]);

            next if $result->[0] eq 'NEXT';
            last if $result->[0] eq 'LAST';
            return $result if $result->[0] eq 'ERROR';
        }

        return ['NULL', undef];
    }

    # if/else
    if ($ins eq 'IF') {
        if ($self->is_truthy($context, $data->[1])) {
            return $self->statement($context, $data->[2]);
        } else {
            return $self->statement($context, $data->[3]);
        }
    }

    # assignment
    if ($ins eq 'ASSIGN') {
        return $self->assignment($context, $data);
    }

    if ($ins eq 'ADD_ASSIGN') {
        my $left  = $self->statement($context, $data->[1]);
        my $right = $self->statement($context, $data->[2]);

        if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
            $left->[1] += $right->[1];
            return $left;
        }

        $self->error($context, "cannot apply operator ADD (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
    }

    if ($ins eq 'SUB_ASSIGN') {
        my $left  = $self->statement($context, $data->[1]);
        my $right = $self->statement($context, $data->[2]);

        if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
            $left->[1] -= $right->[1];
            return $left;
        }

        $self->error($context, "cannot apply operator SUB (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
    }

    if ($ins eq 'MUL_ASSIGN') {
        my $left  = $self->statement($context, $data->[1]);
        my $right = $self->statement($context, $data->[2]);

        if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
            $left->[1] *= $right->[1];
            return $left;
        }

        $self->error($context, "cannot apply operator MUL (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
    }

    if ($ins eq 'DIV_ASSIGN') {
        my $left  = $self->statement($context, $data->[1]);
        my $right = $self->statement($context, $data->[2]);

        if ($self->is_arithmetic_type($left) and $self->is_arithmetic_type($right)) {
            $left->[1] /= $right->[1];
            return $left;
        }

        $self->error($context, "cannot apply operator DIV (have types " . $self->pretty_type($left) . " and " . $self->pretty_type($right) . ")");
    }

    if ($ins eq 'CAT_ASSIGN') {
        my $left  = $self->statement($context, $data->[1]);
        my $right = $self->statement($context, $data->[2]);

        $left->[1] .= $right->[1];
        return $left;
    }

    # variable
    if ($ins eq 'IDENT') {
        my $var = $self->get_variable($context, $value);
        $self->error($context, "undeclared variable `$value`") if not defined $var;
        return $var;
    }

    # function definition
    if ($ins eq 'FUNCDEF') {
        return $self->function_definition($context, $data);
    }

    # function call
    if ($ins eq 'CALL') {
        return $self->function_call($context, $data);
    }

    # prefix increment
    if ($ins eq 'PREFIX_ADD') {
        my $var = $self->statement($context, $value);

        if ($self->is_arithmetic_type($var)) {
            $var->[1]++;
            return $var;
        }

        $self->error($context, "cannot apply prefix-increment to type " . $self->pretty_type($var));
    }

    # prefix decrement
    if ($ins eq 'PREFIX_SUB') {
        my $var = $self->statement($context, $value);

        if ($self->is_arithmetic_type($var)) {
            $var->[1]--;
            return $var;
        }

        $self->error($context, "cannot apply prefix-decrement to type " . $self->pretty_type($var));
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
    return $value if defined ($value = $self->binary_op($context, $data, 'STRCAT', '$a . $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'STRIDX', '$a ~ $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GTE', '$a >= $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LTE', '$a <= $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'GT',  '$a > $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'LT',  '$a < $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'EQ',  '$a == $b'));
    return $value if defined ($value = $self->binary_op($context, $data, 'NEQ', '$a != $b'));

    # postfix increment
    if ($ins eq 'POSTFIX_ADD') {
        my $var = $self->statement($context, $data->[1]);

        if ($self->is_arithmetic_type($var)) {
            my $temp_var = [$var->[0], $var->[1]];
            $var->[1]++;
            return $temp_var;
        }

        $self->error($context, "cannot apply postfix-increment to type " . $self->pretty_type($var));
    }

    # postfix decrement
    if ($ins eq 'POSTFIX_SUB') {
        my $var = $self->statement($context, $data->[1]);

        if ($self->is_arithmetic_type($var)) {
            my $temp_var = [$var->[0], $var->[1]];
            $var->[1]--;
            return $temp_var;
        }

        $self->error($context, "cannot apply postfix-decrement to type " . $self->pretty_type($var));
    }

    # range operator
    if ($ins eq 'RANGE') {
        my ($to, $from) = ($data->[1], $data->[2]);

        $to   = $self->statement($context, $to);
        $from = $self->statement($context, $from);

        return ['RANGE', $to, $from];
    }

    # rvalue array index
    if ($ins eq 'ARRAY_INDEX') {
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

    return $data;
}

my $dump_to_string = qr/\\([\@\$\%])/;

# converts a map to a string
# note: trusts $var to be MAP type
sub map_to_string {
    my ($self, $var) = @_;

    $Data::Dumper::Indent = 0;
    $Data::Dumper::Terse  = 1;
    $Data::Dumper::Useqq  = 1;

    my $hash = $var->[1];
    my $string = '{';

    my @entries;
    while (my ($key, $value) = each %$hash) {
        $key = Dumper ($key);
        $key =~ s/$dump_to_string/$1/g;
        my $entry = "$key: ";

        if ($value->[0] eq 'STRING') {
            my $dump = Dumper ($value->[1]);
            $dump =~ s/$dump_to_string/$1/g;
            $entry .= $dump;
        } elsif ($value->[0] eq 'NULL') {
            $entry .= 'null';
        } else {
            $entry .= $self->output_value($value);
        }
        push @entries, $entry;
    }

    $string .= join(', ', @entries);
    $string .= '}';
    return $string;
}

# converts an array to a string
# note: trusts $var to be ARRAY type
sub array_to_string {
    my ($self, $var) = @_;

    $Data::Dumper::Indent = 0;
    $Data::Dumper::Terse  = 1;
    $Data::Dumper::Useqq  = 1;

    my $array = $var->[1];
    my $string = '[';

    my @entries;
    foreach my $entry (@$array) {
        if ($entry->[0] eq 'STRING') {
            my $dump = Dumper ($entry->[1]);
            $dump =~ s/$dump_to_string/$1/g;
            push @entries, $dump;
        } elsif ($entry->[0] eq 'NULL') {
            push @entries, 'null';
        } else {
            push @entries, $self->output_value($entry);
        }
    }

    $string .= join(',', @entries);
    $string .= ']';
    return $string;
}

sub output_value {
    my ($self, $value) = @_;

    my $result = "";

    if ($self->{repl}) {
        $result .= "[" . $self->pretty_type($value) . "] ";
    }

    # booleans
    if ($value->[0] eq 'BOOL') {
        if ($value->[1] == 0) {
            $result .= 'false';
        } else {
            $result .= 'true';
        }
    }

    # functions
    elsif ($value->[0] eq 'FUNC') {
        $result .= 'Function';
    }

    # maps
    elsif ($value->[0] eq 'MAP') {
        $result .= $self->map_to_string($value);
    }

    # arrays
    elsif ($value->[0] eq 'ARRAY') {
        $result .= $self->array_to_string($value);
    }

    # STRING and NUM returned as-is
    else {
        $result .= $value->[1];
    }

    return $result;
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

sub is_arithmetic_type {
    my ($self, $value) = @_;
    return 1 if $value->[0] eq 'NUM' or $value->[0] eq 'BOOL';
    return 0;
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
        $self->set_variable($context, $builtin, ['BUILTIN', $builtin]);
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

    $self->{dprint}->('AST', "interpet ast: " . Dumper ($ast) . "\n");

    # try
    my $last_statement_result = eval {
        my $result;
        foreach my $node (@$ast) {
            my $instruction = $node->[0];

            if ($instruction eq 'STMT') {
                $result = $self->statement($context, $node->[1]);
                $result = $self->handle_statement_result($result) if defined $result;

                if (defined $result) {
                    $self->{dprint}->('AST', "Statement result: " . (defined $result->[1] ? $result->[1] : 'undef') . " ($result->[0])\n");
                    return $result if $result->[0] eq 'LAST' or $result->[0] eq 'NEXT';
                    return $result->[1] if $result->[0] eq 'RETURN';
                    return $result if $result->[0] eq 'ERROR';
                } else {
                    $self->{dprint}->('AST', "Statement result: none\n");
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

    $self->{dprint}->('RESULT', "handle result: " . Dumper($result) . "\n");

    # if Plang is embedded into a larger app return the result
    # to the larger app so it can handle it itself
    return $result if $self->{embedded};

    # return result unless we should print any result
    return $result unless $print_any;

    # print the result if possible and then consume it
    print $self->output_value($result), "\n" if defined $result->[1];
    return;
}

1;
