#!/usr/bin/env perl

# Parses and importss Plang modules.
# Desugars identifiers into INSTR_IDENT or INSTER_QIDENT depending on
# whether the identifier is namespace-qualified (i.e. Foo::Bar) or not.

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

    $self->{modpath} = $conf{modpath};

    $self->override_instruction(INSTR_IMPORT, \&keyword_import);
    $self->override_instruction(INSTR_IDENT,  \&identifier);
}

sub keyword_import($self, $scope, $data) {
    my $target = $data->[1][1];
    my $alias  = $data->[2][1][0]; # alias identifier always has one entry
    my $pos    = $data->[1][2];

    eval { $self->import_module($target, $alias) };

    if (my $exception = $@) {
        chomp $exception;
        print STDERR "$exception at line $pos->{line}, col $pos->{col}\n";
        exit 1;
    }
}

sub identifier($self, $scope, $data) {
    my $ident = $data->[1];

    if (@$ident == 1) {
        $data->[1] = $ident->[0];
    } else {
        $data->[0] = INSTR_QIDENT;
        my @module = $data->[1]->@*;
        my $name   = pop @module;
        $data->[1] = [(join '::', @module), $name];
    }
}

sub import_module($self, $target, $alias) {
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
            die $exception;
        } else {
            die "Failed to find module " . (join '::', @$target) . "\n";
        }
    }

    my $ast = $interp->parse_string($content);

    my $importer = Plang::ModuleImporter->new(
        ast        => $ast,
        target     => (join '::', @$target),
        alias      => $alias,
        types      => $self->{types},
        namespace  => $self->{namespace}
    );

    $importer->walk();
}

sub reset_modules() {
}

sub import_modules($self, $ast, %opts) {
    $self->{rootpath} = $opts{rootpath};
    return $self->walk($ast, %opts);
}

1;
