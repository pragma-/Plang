#!/usr/bin/env perl

# Parses and importss Plang modules.

package Plang::Modules;
use parent 'Plang::AST::Walker';

use warnings;
use strict;
use feature 'signatures';

use Plang::Interpreter;
use Plang::ModuleImporter;
use Plang::Constants::Instructions ':all';

use Data::Dumper;
use Devel::StackTrace;

use Cwd qw(realpath);
use File::Basename qw(dirname);

sub initialize($self, %conf) {
    $self->SUPER::initialize(%conf);

    $self->{modpath}   = $conf{modpath};
    $self->{validator} = $conf{validator};

    $self->override_instruction(INSTR_IMPORT, \&keyword_import);
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
    die "Module import error: $err_msg\n";
}

sub keyword_import($self, $scope, $data) {
    my $target = $data->[1];
    my $alias  = $data->[2][1];
    my $pos    = $data->[1][2];

    if ($target->[0] == INSTR_IDENT) {
        $target = [$target->[1]];
    }
    elsif ($target->[0] == INSTR_QIDENT) {
        $target = $target->[1];
    } else {
        $self->error($scope, "unknown instruction $target->[0] for import target", $pos);
    }

    eval { $self->import_module($target, $alias, $scope, $pos) };

    if (my $exception = $@) {
        die $exception;
    }
}

sub import_module($self, $target, $alias, $scope, $pos) {
    my $interp = Plang::Interpreter->new(
        path     => $self->{path},
        embedded => $self->{embedded},
        modpath  => $self->{modpath},
    );

    my $content;

    my @modpath = $self->{modpath}->@*;
    my $source  = join '/', @$target;

    foreach my $path (@modpath) {
        my $file = "$path/$source.plang";

        next if not -e $file;

        $content = eval { $interp->load_file($file) };
        last;
    }

    if (not defined $content) {
        if (my $exception = $@) {
            $self->error($scope, $exception, $pos);
        } else {
            $self->error($scope, "failed to find module " . (join '::', @$target) . "\n", $pos);
        }
    }

    my $ast = $interp->parse_string($content);

    $self->{validator}->validate($ast);

    my $importer = Plang::ModuleImporter->new(
        ast        => $ast,
        target     => (join '::', @$target),
        alias      => $alias,
        types      => $self->{types},
        namespace  => $self->{namespace}
    );

    $importer->walk();
}

sub reset_modules($self) {
    $self->{namespace}->{modules} = {};
}

sub import_modules($self, $ast, %opts) {
    $self->{rootpath} = $opts{rootpath};
    return $self->walk($ast, %opts);
}

1;
