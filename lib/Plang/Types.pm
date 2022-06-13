#!/usr/bin/env perl

# Plang's type system

package Plang::Types;

use warnings;
use strict;

use Data::Dumper;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{debug} = $conf{debug};

    $self->{types}   = {};
    $self->{aliases} = {};
    $self->{rank}    = {};

    $self->add_default_types;

    # ranks for promotions
    $self->{rank}->{Null}    = 5;
    $self->{rank}->{Boolean} = 10;
    $self->{rank}->{Integer} = 15;
    $self->{rank}->{Real}    = 20;
}

sub add_default_types {
    my ($self) = @_;

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

# add a type alias
sub add_alias {
    my ($self, $name, $type) = @_;
    $self->{aliases}->{$name} = $type;
}

# get an existing type alias by name
sub get_alias {
    my ($self, $name) = @_;
    return $self->{aliases}->{$name};
}

# resolve a type to an alias
sub resolve_alias {
    my ($self, $type) = @_;

    my $alias = $self->{aliases}->{$type->[1]};

    if ($alias) {
        if ($alias->[0] eq 'TYPE') {
            return $self->resolve_alias($alias);
        } else {
            return $alias;
        }
    }

    return $type;
}

# reset type aliases
sub reset_types {
    my ($self) = @_;

    $self->{types}   = {};
    $self->{aliases} = {};

    $self->add_default_types;
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
        my $type_alias = $self->{aliases}->{$type->[1]};

        if ($type_alias) {
            return "$type->[1] aka " . $self->to_string($type_alias);
        } else {
            return $type->[1];
        }
    }

    if ($type->[0] eq 'TYPEARRAY') {
        return '[' . $self->to_string($type->[1]) . ']';
    }

    if ($type->[0] eq 'TYPEMAP') {
        my @types;

        foreach my $entry (sort { $a->[0] cmp $b->[0] } @{$type->[1]}) {
            my ($key, $type) = @$entry;

            push @types, "\"$key\": " . $self->to_string($type);
        }

        return '{' . join(', ', @types) . '}';
    }

    if ($type->[0] eq 'TYPEUNION') {
        my $types = [];
        foreach my $t (@{$type->[1]}) {
            push @$types, $self->to_string($t);
        }

        return join ' | ', @$types;
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

    if ($type->[0] eq 'SPCL') {
        return $type->[1];
    }

    die "[to-string] unknown type\n";
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

# check if a type name has a subtype name
sub has_subtype {
    my ($self, $type, $subtype) = @_;

    my $type_alias = $self->{aliases}->{$type};

    if ($type_alias) {
        if ($type_alias->[0] eq 'TYPE') {
            $type = $type_alias->[1];
        } else {
            return 0;
        }
    }

    my $subtype_alias = $self->{aliases}->{$subtype};

    if ($subtype_alias) {
        if ($subtype_alias->[0] eq 'TYPE') {
            $subtype = $subtype_alias->[1];
        } else {
            return 0;
        }
    }

    return 1 if $type eq $subtype;
    return 1 if exists $self->{types}->{$type}->{$subtype};

    foreach my $t (keys %{$self->{types}->{$type}}) {
        return 1 if $self->has_subtype($t, $subtype);
    }

    return 0;
}

# return true if a type is a subtype of another type
sub is_subtype {
    my ($self, $subtype, $type) = @_;

    # only basic types can be subtypes of another
    if ($subtype->[0] ne 'TYPE' or $type->[0] ne 'TYPE') {
        return 0;
    }

    return $self->has_subtype($type->[1], $subtype->[1]);
}

# check if a type is a specific type name
sub name_is {
    my ($self, $type, $name) = @_;
    return 0 if ref $type ne 'ARRAY';
    return $type->[0] eq $name;
}

# return true if a type name is arithmetic
sub is_arithmetic {
    my ($self, $type) = @_;

    if ($type->[0] eq 'TYPE') {
        return 1 if $self->has_subtype('Number', $type->[1]);
    }

    if ($type->[0] eq 'TYPEUNION') {
        foreach my $t (@{$type->[1]}) {
            return 1 if $self->is_arithmetic($t);
        }
    }

    return 0;
}

# returns higher ranked type
sub get_promoted_type {
    my ($self, $type1, $type2) = @_;

    if ($self->is_subtype($type1, $type2)) {
        if (exists $self->{rank}->{$type1->[1]} and exists $self->{rank}->{$type2->[1]}) {
            if ($self->{rank}->{$type1->[1]} > $self->{rank}->{$type2->[1]}) {
                return $type1;
            } else {
                return $type2;
            }
        }
    }

    return $type1;
}

# returns true if one type is identical to another
sub is_equal {
    my ($self, $type1, $type2) = @_;

    # a type
    if ($type1->[0] eq 'TYPE') {
        if ($type2->[0] eq 'TYPE') {
            my $type1_alias = $self->{aliases}->{$type1->[1]};
            my $type2_alias = $self->{aliases}->{$type2->[1]};

            if ($type1_alias && $type2_alias) {
                return $self->is_equal($type1_alias, $type2_alias);
            } elsif ($type1_alias) {
                return $self->is_equal($type1_alias, $type2);
            } elsif ($type2_alias) {
                return $self->is_equal($type1, $type2_alias);
            } else {
                return 1 if $type1->[1] eq $type2->[1];
            }
        }
        return 0;
    }

    # an array of types
    if ($type1->[0] eq 'TYPEARRAY') {
        return 0 if $type2->[0] ne 'TYPEARRAY';
        return 1 if $self->is_equal($type1->[1], $type2->[1]);
        return 0;
    }

    # a map of types
    if ($type1->[0] eq 'TYPEMAP') {
        return 0 if $type2->[0] ne 'TYPEMAP';

        my $type1_props = $type1->[1];
        my $type2_props = $type2->[1];

        return 0 if @$type1_props != @$type2_props;

        for (my $i = 0; $i < @$type1_props; ++$i) {
            # compare prop name
            return 0 if not $type1_props->[$i]->[0] eq $type2_props->[$i]->[0];
            # compare prop type
            return 0 if not $self->is_equal($type1_props->[$i]->[1], $type2_props->[$i]->[1]);
        }

        return 1;
    }

    # a union of types
    if ($type1->[0] eq 'TYPEUNION') {
        return 0 if $type2->[0] ne 'TYPEUNION';
        return 0 if @{$type1->[1]} != @{$type2->[1]};

        for (my $i = 0; $i < @{$type1->[1]}; ++$i) {
            return 0 if not $self->is_equal($type1->[1]->[$i], $type2->[1]->[$i]);
        }

        return 1;
    }

    # a function-like type
    if ($type1->[0] eq 'TYPEFUNC') {
        return 0 if $type2->[0] ne 'TYPEFUNC';

        my $type1_kind   = $type1->[1];
        my $type1_params = $type1->[2];
        my $type1_return = $type1->[3];

        my $type_kind   = $type2->[1];
        my $type_params = $type2->[2];
        my $type_return = $type2->[3];

        # TODO: for now, we implicitly assume $type1_kind and $type_kind are equal
        # since Builtin is a subtype of Function and these are the only two types
        # that use TYPEFUNC.

        # fail if parameter counts are not equal
        return 0 if @$type1_params != @$type_params;

        # fail if parameter types are not equal
        for (my $i = 0; $i < @$type1_params; $i++) {
            return 0 if not $self->is_equal($type_params->[$i], $type1_params->[$i]);
        }

        # return result of return value comparison
        return $self->is_equal($type1_return, $type_return);
    }

    die "[is_equal] unknown type\n";
}

# type-checking
sub check {
    my ($self, $guard, $type) = @_;

    if ($self->{debug}) {
        $Data::Dumper::Terse = 1;
        $Data::Dumper::Indent = 0;

        $self->{debug}->{print}->('TYPES', "type check " . Dumper($guard) . " vs " . Dumper($type) . "\n");

        if ($self->{debug}->{tags}->{TYPES}) {
            use Devel::StackTrace;
            my $trace = Devel::StackTrace->new(indent => 1, ignore_class => ['Plang::Interpreter', 'main']);
            print "  at ", $trace->as_string(), "\n";
        }
    }

    # check for aliases
    # we wrap these resolve_alias() calls with a check for 'TYPE'
    # to avoid an unnecessary subcall
    if ($guard->[0] eq 'TYPE') {
        $guard = $self->resolve_alias($guard);
    }

    if ($type->[0] eq 'TYPE') {
        $type  = $self->resolve_alias($type);
    }

    # a type
    if ($guard->[0] eq 'TYPE') {
        return 1 if $guard->[1] eq 'Any';
        return 1 if $guard->[1] eq 'Array' and $type->[0] eq 'TYPEARRAY';
        return 1 if $guard->[1] eq 'Map'   and $type->[0] eq 'TYPEMAP';
        return 0 if $type->[0] ne 'TYPE';
        return 0 if not $self->has_subtype($guard->[1], $type->[1]);
        return 1;
    }

    # an array of types
    if ($guard->[0] eq 'TYPEARRAY') {
        return 0 if $type->[0] ne 'TYPEARRAY';
        return $self->check($guard->[1], $type->[1]);
    }

    # a map of types
    if ($guard->[0] eq 'TYPEMAP') {
        return 0 if $type->[0] ne 'TYPEMAP';

        my $guard_props = $guard->[1];
        my $type_props  = $type->[1];

        return 0 if @$guard_props != @$type_props; # arity of properties do not match

        for (my $i = 0; $i < @$guard_props; ++$i) {
            # compare prop name
            return 0 if not $guard_props->[$i]->[0] eq $type_props->[$i]->[0];
            # compare prop type
            return 0 if not $self->check($guard_props->[$i]->[1], $type_props->[$i]->[1]);
        }

        return 1;
    }

    # an union of types
    if ($guard->[0] eq 'TYPEUNION') {
        if ($type->[0] eq 'TYPEUNION') {
            return $self->is_equal($guard, $type);
        }

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
            return 0 if not $self->is_subtype($type_params->[$i], $guard_params->[$i]);
        }

        # return result of return value check
        return $self->check($guard_return, $type_return);
    }

    die "[check] unknown type\n";
}

sub unite {
    my ($self, $types) = @_;

    my @union;
    my %uniq;

    foreach my $type (@$types) {
        next if $self->is_equal($type, ['TYPE', 'Any']);

        if ($type->[0] eq 'TYPEUNION') {
            foreach my $t (@{$type->[1]}) {
                my $string;

                if ($t->[0] eq 'TYPE') {
                    $string = $t->[1];
                } else {
                    $string = $self->to_string($t);
                }

                push @union, $t unless exists $uniq{$string};
                $uniq{$string} = 1;
            }
        } else {
            my $string;

            if ($type->[0] eq 'TYPE') {
                $string = $type->[1];
            } else {
                $string = $self->to_string($type);
            }

            push @union, $type unless exists $uniq{$string};
            $uniq{$string} = 1;
        }
    }

    return ['TYPE', 'Any'] if @union == 0;

    if (@union == 1) {
        return $union[0]
    }

    return $self->make_typeunion(\@union);
}

sub make_typeunion {
    my ($self, $types) = @_;
    my @union = sort { $a->[1] cmp $b->[1] } @$types;
    return ['TYPEUNION', \@union];
}

1;
