#!/usr/bin/env perl

# Constants related to keywords.

package Plang::Constants::Keywords;

use warnings;
use strict;
use constant;

my $n = 0; # easier rearranging/insertion/removal of keywords

my %constants = (
    KEYWORD_VAR => $n++,
    KEYWORD_TRUE => $n++,
    KEYWORD_FALSE => $n++,
    KEYWORD_NULL => $n++,
    KEYWORD_FN => $n++,
    KEYWORD_RETURN => $n++,
    KEYWORD_WHILE => $n++,
    KEYWORD_NEXT => $n++,
    KEYWORD_LAST => $n++,
    KEYWORD_IF => $n++,
    KEYWORD_THEN => $n++,
    KEYWORD_ELSE => $n++,
    KEYWORD_EXISTS => $n++,
    KEYWORD_DELETE => $n++,
    KEYWORD_KEYS => $n++,
    KEYWORD_VALUES => $n++,
);

our @pretty_keyword = map { s/^KEYWORD_//; lc $_ } sort { $constants{$a} <=> $constants{$b} } keys %constants;

our %keyword_id;

$n = 0;

foreach my $keyword (@pretty_keyword) {
    $keyword_id{$keyword} = $n++;
}

constant->import(\%constants);

use Exporter qw/import/;
our %EXPORT_TAGS = ('all' => [keys %constants, '@pretty_keyword', '%keyword_id']);
our @EXPORT_OK   = (keys %constants, '@pretty_keyword', '%keyword_id');

1;
