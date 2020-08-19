#!/usr/bin/env perl

# Plang's type system

package Plang::Types;

use warnings;
use strict;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    # root type is Any
    $self->add('Any');

    # subtypes of Any
    $self->add('Any', 'Null');
    $self->add('Any', 'Number');
    $self->add('Any', 'Boolean');
    $self->add('Any', 'String');
    $self->add('Any', 'Array');
    $self->add('Any', 'Map');
    $self->add('Any', 'Function');

    # subtypes of Number
    $self->add('Number', 'Real');
    $self->add('Number', 'Integer');

    # subtype of Function
    $self->add('Function', 'Builtin');
}

# add a type name
sub add {
    my ($self, $type, $subtype) = @_;

    if (not defined $subtype) {
        if (not exists $self->{types}->{$type}) {
            $self->{types}->{$type} = {};
        }
    } else {
        if (exists $self->{types}->{$type}) {
            $self->{types}->{$type}->{$subtype} = 1;
        } else {
            $self->{types}->{$type} = { $subtype => 1 };
        }
    }
}

# check if a type name has a subtype name
sub has_subtype {
    my ($self, $type, $subtype) = @_;

    return 1 if $type eq $subtype;
    return 1 if exists $self->{types}->{$type}->{$subtype};

    foreach my $t (keys %{$self->{types}->{$type}}) {
        return 1 if $self->has_subtype($t, $subtype);
    }

    return 0;
}

# check if a type name exists
sub exists {
    my ($self, $type) = @_;

    return 1 if exists $self->{types}->{$type};

    foreach my $t (keys %{$self->{types}}) {
        return 1 if $t eq $type;

        foreach my $subtype (keys %{$self->{types}->{$t}}) {
            return 1 if $subtype eq $type;
        }
    }

    return 0;
}

# check if a type is a specific type name
sub name_is {
    my ($self, $type, $name) = @_;
    return 0 if ref $type ne 'ARRAY';
    return $type->[0] eq $name;
}

# return true if a type is a subtype of another type
sub is_subtype {
    my ($self, $subtype, $type) = @_;

    if ($subtype->[0] eq 'TYPELIST' or $type->[0] eq 'TYPELIST') {
        return 0;
    }

    return $self->has_subtype($type->[1], $subtype->[1]);
}

# return true if a type name is arithmetic
sub is_arithmetic {
    my ($self, $type) = @_;
    return 1 if $self->has_subtype('Number', $type->[1]);
    return 0;
}

# type-checking
sub check {
    my ($self, $guard, $type) = @_;

    # a type
    if ($guard->[0] eq 'TYPE') {
        return 1 if $guard->[1] eq 'Any';
        return 0 if $type->[0] ne 'TYPE';
        return 0 if not $self->has_subtype($guard->[1], $type->[1]);
        return 1;
    }

    # a list of types
    if ($guard->[0] eq 'TYPELIST') {
        foreach my $g (@{$guard->[1]}) {
            return 1 if $self->check($g, $type);
        }

        return 0;
    }

    # a function-like type
    if ($guard->[0] eq 'TYPEFUNC') {
        return 0 if $type->[0] ne 'TYPEFUNC';

        my $guard_kind   = $guard->[1];
        my $guard_params = $guard->[2];
        my $guard_return = $guard->[3];

        my $type_kind   = $type->[1];
        my $type_params = $type->[2];
        my $type_return = $type->[3];

        # TODO: for now, we implicitly assume $guard_kind and $type_kind are equal
        # since Builtin is a subtype of Function and these are the only two types
        # that use TYPEFUNC.

        # fail if parameter counts are not equal
        return 0 if @$guard_params != @$type_params;

        # fail if parameter types are not equal
        for (my $i = 0; $i < @$guard_params; $i++) {
            return 0 if not $self->has_subtype($guard_params->[$i], $type_params->[$i]);
        }

        # return result of return value check
        return $self->check($guard_return, $type_return);
    }

    die "unknown type\n";
    return 0;
}

# return flat list of type names
sub as_list {
    my ($self) = @_;
    my %types;
    foreach my $t (keys %{$self->{types}}) {
        $types{$t} = 1;
        foreach my $subtype (keys %{$self->{types}->{$t}}) {
            $types{$subtype} = 1;
        }
    }
    return sort keys %types;
}

# convert a type structure into a string
sub to_string {
    my ($self, $type) = @_;

    if ($type->[0] eq 'TYPE') {
        return $type->[1];
    }

    if ($type->[0] eq 'TYPELIST') {
        my $types = [];
        foreach my $t (@{$type->[1]}) {
            push @$types, $self->to_string($t);
        }

        return "[" . join(", ", sort @$types) . "]";
    }

    if ($type->[0] eq 'TYPEFUNC') {
        my $kind   = $type->[1];  # Function or Builtin
        my $params = $type->[2];
        my $return = $type->[3];

        my $result = [];
        foreach my $param (@{$params}) {
            push @$result, $self->to_string($param);
        }

        my $param_string = "(" . join(', ', @$result) . ")";

        my $return_string = $self->to_string($return);

        return "$kind $param_string -> $return_string";
    }
}

1;
