# Plang
Plang is an experimental foray into implementing a programming language in Perl.

## Features
Plang is in early development stages. This is what is implemented so far.

* Lexer: Done
* Parser: Done
* Grammar: In-progress
* Interpreter: In-progress

### Expressions
    $ ./plang <<< '1 * 2 + (3 * 4)'        # arithmetic expressions
      14
<!-- -->
    $ ./plang <<< '1 + 2 == 4 - 1'         # conditional expressions
      1

    $ ./plang <<< '3 > 5'
      0

#### Operators
These are the operators implemented so far, from lowest to highest precedence.

Operator | Description | Associativity
--- | --- | ---
=  | Assignment | Left
== | Equality | Right
\>= | Greater or equal | Right
\<= | Less or equal | Right
\> | Greater | Right
\<  | Less | Right
\+ | Addition | Right
\- | Subtraction | Right
\* | Product | Right
/ | Division | Right
\*\* | Exponent | Right
% | Remainder | Right
! | Not | Left
\+\+ | Prefix increment | Left
\-\- | Prefix decrement | Left
\+\+ | Postfix increment | Right
\-\- | Postfix decrement | Right

### Statements
A statement is a single instruction. Statements may be terminated by a
semi-colon or a newline.

Plang automatically prints the value of the last statement. To print the
values of previous statements, you must use the `print` [function](#functions).

    $ ./plang <<< 'print 1 + 2, "\n"; print 3 * 4, "\n"; 5 - 6'
      3
      12
      -1

### Variables
Variables are declared by assigning a value to an identifier;

    $ ./plang <<< 'a = 5; print a'
      5

Identifiers that have not yet been assigned a value will simply yield 0.

    $ ./plang <<< 'a = 5; a + b'
      5

    $ ./plang <<< '++c; ++c'
      2

### Keywords
Keyword | Description
--- | ---
fn | function definition
return | return value from function

### Functions
Functions are an abstracted group of statements. Functions can take variables
as arguments and will return the value of the last statement. You can also explicitly
return a value via the `return` keyword.

For example, a function to square a value:

    $ ./plang <<< 'fn square(x) { x * x } square 4'
      16

#### Built-in functions
Function | Description
--- | ---
print(string) | Prints `string` to standard output.

## Debugging
### DEBUG environment variable
You can set the `DEBUG` environment variable to enable debugging output.

The value is an integer representing verbosity, where higher values are more verbose.

    $ DEBUG=1 ./plang <<< '1 + 2'  # minimal (though still a quite a bit) output
<!-- -->
    $ DEBUG=5 ./plang <<< '1 + 2'  # very verbose debugging output

### Testing the lexer
You can pass `--dumptokens` as a command-line argument to display a flat-list
of all the tokens as they are encountered.

    $ ./plang --dumptokens < test/lexer_input.txt  # test the lexer
