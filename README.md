# plang
plang is an experimental foray into implementing a programming language in Perl

## Features
None yet.

Here's what you can do so far:

    $ ./plang <<< '1 + 2; 3 * 4;'
<!-- -->
    $ ./plang <<< '1 + 2 * (3 * 4)'
<!-- -->
    $ ./plang -dumptokens < test/lexer_input.txt
