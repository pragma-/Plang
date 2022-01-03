#!/usr/bin/env perl

# Constants related to tokens.

package Plang::Constants::Tokens;

use warnings;
use strict;
use constant;

my $n = 0; # easier rearranging/insertion/removal of tokens

my %constants = (
    TOKEN_KEYWORD => $n++,
    TOKEN_TYPE => $n++,
    TOKEN_IDENT => $n++,
    TOKEN_COMMENT_EOL => $n++,
    TOKEN_COMMENT_INLINE => $n++,
    TOKEN_COMMENT_MULTI => $n++,
    TOKEN_DQUOTE_STRING_I => $n++,
    TOKEN_SQUOTE_STRING_I => $n++,
    TOKEN_DQUOTE_STRING => $n++,
    TOKEN_SQUOTE_STRING => $n++,
    TOKEN_EQ_TILDE => $n++,
    TOKEN_BANG_TILDE => $n++,
    TOKEN_NOT_EQ => $n++,
    TOKEN_GREATER_EQ => $n++,
    TOKEN_LESS_EQ => $n++,
    TOKEN_EQ => $n++,
    TOKEN_SLASH_EQ => $n++,
    TOKEN_STAR_EQ => $n++,
    TOKEN_MINUS_EQ => $n++,
    TOKEN_PLUS_EQ => $n++,
    TOKEN_DOT_EQ => $n++,
    TOKEN_PLUS_PLUS => $n++,
    TOKEN_STAR_STAR => $n++,
    TOKEN_MINUS_MINUS => $n++,
    TOKEN_L_ARROW => $n++,
    TOKEN_R_ARROW => $n++,
    TOKEN_ASSIGN => $n++,
    TOKEN_PLUS => $n++,
    TOKEN_MINUS => $n++,
    TOKEN_GREATER => $n++,
    TOKEN_LESS => $n++,
    TOKEN_BANG => $n++,
    TOKEN_QUESTION => $n++,
    TOKEN_COLON_COLON => $n++,
    TOKEN_COLON => $n++,
    TOKEN_TILDE_TILDE => $n++,
    TOKEN_TILDE => $n++,
    TOKEN_PIPE_PIPE => $n++,
    TOKEN_PIPE => $n++,
    TOKEN_AMP_AMP => $n++,
    TOKEN_AMP => $n++,
    TOKEN_CARET_CARET_EQ => $n++,
    TOKEN_CARET_CARET => $n++,
    TOKEN_CARET => $n++,
    TOKEN_PERCENT => $n++,
    TOKEN_POUND => $n++,
    TOKEN_COMMA => $n++,
    TOKEN_STAR => $n++,
    TOKEN_SLASH => $n++,
    TOKEN_BSLASH => $n++,
    TOKEN_L_BRACKET => $n++,
    TOKEN_R_BRACKET => $n++,
    TOKEN_L_PAREN => $n++,
    TOKEN_R_PAREN => $n++,
    TOKEN_L_BRACE => $n++,
    TOKEN_R_BRACE => $n++,
    TOKEN_HEX => $n++,
    TOKEN_FLT => $n++,
    TOKEN_INT => $n++,
    TOKEN_DOT_DOT => $n++,
    TOKEN_DOT => $n++,
    TOKEN_NOT => $n++,
    TOKEN_AND => $n++,
    TOKEN_OR => $n++,
    TOKEN_TERM => $n++,
    TOKEN_WHITESPACE => $n++,
    TOKEN_OTHER => $n++,
);

our @pretty_token = map { s/^TOKEN_//; $_ } sort { $constants{$a} <=> $constants{$b} } keys %constants;

constant->import(\%constants);

use Exporter qw/import/;
our %EXPORT_TAGS = ('all' => [keys %constants, '@pretty_token']);
our @EXPORT_OK   = (keys %constants, '@pretty_token');

1;
