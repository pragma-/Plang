#!/usr/bin/env perl

# Constants related to instructions.

package Plang::Constants::Instructions;

use warnings;
use strict;
use constant;

my $n = 0; # easier rearranging/insertion/removal of instructions

my %constants = (
    INSTR_NOP => $n++,
    INSTR_EXPR_GROUP => $n++,
    INSTR_LITERAL => $n++,
    INSTR_VAR => $n++,
    INSTR_MAPCONS => $n++,
    INSTR_ARRAYCONS => $n++,
    INSTR_EXISTS => $n++,
    INSTR_DELETE => $n++,
    INSTR_KEYS => $n++,
    INSTR_VALUES => $n++,
    INSTR_COND => $n++,
    INSTR_WHILE => $n++,
    INSTR_NEXT => $n++,
    INSTR_LAST => $n++,
    INSTR_IF => $n++,
    INSTR_AND => $n++,
    INSTR_OR => $n++,
    INSTR_ASSIGN => $n++,
    INSTR_ADD_ASSIGN => $n++,
    INSTR_SUB_ASSIGN => $n++,
    INSTR_MUL_ASSIGN => $n++,
    INSTR_DIV_ASSIGN => $n++,
    INSTR_CAT_ASSIGN => $n++,
    INSTR_IDENT => $n++,
    INSTR_QIDENT => $n++,
    INSTR_FUNCDEF => $n++,
    INSTR_CALL => $n++,
    INSTR_RET => $n++,
    INSTR_PREFIX_ADD => $n++,
    INSTR_PREFIX_SUB => $n++,
    INSTR_POSTFIX_ADD => $n++,
    INSTR_POSTFIX_SUB => $n++,
    INSTR_RANGE => $n++,
    INSTR_ACCESS => $n++,
    INSTR_DOT_ACCESS => $n++,
    INSTR_STRING_I => $n++,
    INSTR_TRY => $n++,
    INSTR_THROW => $n++,
    INSTR_TYPE => $n++,
    INSTR_MODULE => $n++,
    INSTR_IMPORT => $n++,

    # unary operators
    INSTR_NOT => $n++,
    INSTR_NEG => $n++,
    INSTR_POS => $n++,

    # binary operators
    INSTR_POW => $n++,
    INSTR_REM => $n++,
    INSTR_MUL => $n++,
    INSTR_DIV => $n++,
    INSTR_ADD => $n++,
    INSTR_SUB => $n++,
    INSTR_STRCAT => $n++,
    INSTR_STRIDX => $n++,
    INSTR_GTE => $n++,
    INSTR_LTE => $n++,
    INSTR_GT => $n++,
    INSTR_LT => $n++,
    INSTR_EQ => $n++,
    INSTR_NEQ => $n++,
);

our @pretty_instr = map { s/^INSTR_//; $_ } sort { $constants{$a} <=> $constants{$b} } keys %constants;

constant->import(\%constants);

use Exporter qw/import/;
our %EXPORT_TAGS = ('all' => [keys %constants, '@pretty_instr']);
our @EXPORT_OK   = (keys %constants, '@pretty_instr');

1;
