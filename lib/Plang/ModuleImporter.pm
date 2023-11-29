#!/usr/bin/env perl

# Imports a Plang module by walking its AST to add variables, functions
# and new type definitions to the namespace.

package Plang::ModuleImporter;
use parent 'Plang::Interpreter::AST';

use warnings;
use strict;
use feature 'signatures';

use Plang::Constants::Instructions ':all';

sub new($class, %args) {
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    $self->SUPER::initialize(%conf);

    $self->{target} = $conf{target};
    $self->{alias}  = $conf{alias};

    $self->override_instruction(INSTR_MODULE,  \&keyword_module);
    $self->override_instruction(INSTR_IMPORT,  \&keyword_import);
    $self->override_instruction(INSTR_QIDENT,  \&qualified_identifier);
    $self->override_instruction(INSTR_VAR,     \&variable_declaration);
    $self->override_instruction(INSTR_FUNCDEF, \&function_definition);
    $self->override_instruction(INSTR_TYPE,    \&keyword_type);
}

sub error($self, $scope, $err_msg, $position = undef) {
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
    die "Import error: $err_msg\n";
}

sub keyword_module($self, $scope, $data) {
    my $target = $data->[1];

    if ($target->[0] == INSTR_IDENT) {
        $target = $target->[1];
    }
    elsif ($target->[0] == INSTR_QIDENT) {
        $target = join '::', $target->[1]->@*;
    } else {
        die "Unknown instruction $target->[0] for module target";
    }

    if (defined $self->{module}) {
        if ($self->{module} eq $target) {
            $self->error($scope, "duplicate use of `module` for $target", $self->position($data->[1]));
        } else {
            $self->error($scope, "cannot redefine module $self->{module} as $target", $self->position($data->[1]));
        }
    }

    if ($target ne $self->{target}) {
        $self->error($scope, "expected module $self->{target} but found $target", $self->position($data->[1]));
    }

    if (defined $self->{alias}) {
        $self->{module} = $self->{alias};
    } else {
        $self->{module} = $target;
    }

    if (exists $self->{targetspace}->{$self->{module}}) {
        $self->error($scope, "there already exists a module loaded as $self->{module}", $self->position($data->[1]));
    }
}

sub variable_declaration($self, $scope, $data) {
    my $type        = $data->[1];
    my $name        = $data->[2];
    my $initializer = $data->[3];

    my $result = $self->SUPER::variable_declaration($scope, $data);

    if (!exists $scope->{parent}) {
        if (!defined $self->{module}) {
            $self->error($scope, "cannot declare variable $name before module name", $self->position($data));
        }

        if (exists $self->{namespace}->{modules}->{$self->{module}}->{$name}) {
            $self->error($scope, "cannot redeclare existing local $name", $self->position($data));
        }

        $self->{namespace}->{modules}->{$self->{module}}->{$name} = $result;
    }
}

sub function_definition($self, $scope, $data) {
    my $name        = $data->[2];
    my $parameters  = $data->[3];
    my $expressions = $data->[4];

    if (!exists $scope->{parent}) {
        if (!defined $self->{module}) {
            $self->error($scope, "cannot define function $name before module name", $self->position($data));
        }

        if (exists $self->{namespace}->{modules}->{$self->{module}}->{$name}) {
            $self->error($scope, "cannot redefine existing local $name", $self->position($data));
        }
    }

    my $result = $self->SUPER::function_definition($scope, $data);

    $self->{namespace}->{modules}->{$self->{module}}->{$name} = $result;
}

sub keyword_type($self, $scope, $data) {
    my $type  = $data->[1];
    my $name  = $data->[2];
    my $value = $data->[3];

    if (!defined $self->{module}) {
        $self->error($scope, "cannot define type $name before module name", $self->position($data));
    }

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

sub keyword_import($self, $scope, $data) {}

sub qualified_identifier($self, $scope, $data) {}

1;
