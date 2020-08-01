#!/usr/bin/env perl

# Pupose: validates the syntax tree by performing static type-checking,
# semantic-analysis, etc.

package Plang::Validator;

use warnings;
use strict;

use parent 'Plang::AstInterpreter';

use Data::Dumper;

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
    return $func;
}

sub function_call {
    my ($self, $context, $data) = @_;

    my $target    = $data->[1];
    my $arguments = $data->[2];
    my $func;

    if ($target->[0] eq 'IDENT') {
        $self->{dprint}->('FUNCS', "Calling function `$target->[1]` with arguments: " . Dumper($arguments) . "\n");
        $func = $self->get_variable($context, $target->[1]);
        $func = undef if defined $func and $func->[0] eq 'BUILTIN';
    } else {
        $self->{dprint}->('FUNCS', "Calling anonymous function with arguments: " . Dumper($arguments) . "\n");
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

    $self->process_function_call_arguments($new_context, $target->[1], $parameters, $arguments);

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
