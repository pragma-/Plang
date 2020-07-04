# plang
plang is an experimental foray into implementing a programming language in Perl

## Features
None yet.

Here's what you can do so far:

    $ ./plang <<< '1 + 2; 3 * 4; 5 - 6;'   # statements
<!-- -->
    $ ./plang <<< '1 * 2 + (3 * 4)'        # complex expressions
<!-- -->
    $ ./plang --dumptokens < test/lexer_input.txt  # test the lexer

## Debugging
You can set the `DEBUG` environment variable to enable debugging output.

The value is an integer representing verbosity, where higher values are more verbose.

    $ DEBUG=1 ./plang <<< '1 + 2'  # minimal (though still a quite a bit) output
<!-- -->
    $ DEBUG=5 ./plang <<< '1 + 2'  # very verbose debugging output
