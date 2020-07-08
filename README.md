# Plang
Plang is an experimental foray into implementing a programming language in Perl.

Plang is in early development stage. There will be bugs. There will be abrupt design changes.

<!-- md-toc-begin -->
* [Features](#features)
  * [Expressions](#expressions)
    * [Operators](#operators)
  * [Statements](#statements)
  * [Variables](#variables)
  * [Keywords](#keywords)
  * [Functions](#functions)
    * [Built-in functions](#built-in-functions)
* [Debugging](#debugging)
  * [DEBUG environment variable](#debug-environment-variable)
  * [Testing the lexer](#testing-the-lexer)
<!-- md-toc-end -->

## Features
This is what is implemented so far.

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
=  | Assignment | Right to left
== | Equality | Left to right
\>= | Greater or equal | Left to right
\<= | Less or equal | Left to right
\> | Greater | Left to right
\<  | Less | Left to right
\+ | Addition | Left to right
\- | Subtraction | Left to right
\* | Product | Left to right
/ | Division | Left to right
% | Remainder | Left to right
\*\* | Exponent | Right to left
! | Not | Right to left
\+\+ | Prefix increment | Right to left
\-\- | Prefix decrement | Right to left
\+\+ | Postfix increment | Left to right
\-\- | Postfix decrement | Left to right
\(\) | Function call | Left to right

### Statements
A statement is a single instruction. Statements may be terminated by a
semi-colon or a newline.

Plang automatically prints the value of the last statement. To print the
values of previous statements, you must use the `print` [function](#functions)
To prevent printing the last statement, make the last statement `return`.

    $ ./plang <<< 'print 1 + 2, "\n"; print 3 * 4, "\n"; 5 - 6'
      3
      12
      -1

### Variables
Variables are declared by assigning a value to an identifier. An identifier is a
sequence of characters beginning with an underscore or a letter, optionally followed
by additional underscores, letters or digits.

    $ ./plang <<< 'a = 5; a'
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
Functions are an abstracted group of statements. Functions can take identifiers as
parameters and will return the value of the last statement. You can explicitly
return an earlier statement's value via the `return` keyword. Arguments passed to
function calls may be any valid expression, optionally enclosed with parentheses.

For example, a function to square a value:

    $ ./plang <<< 'fn square(x) { x * x } square 4'
      16

Another trivial example, adding two numbers:

    $ ./plang <<< 'fn add(a, b) { a + b } add(2, 3)'
      5

#### Built-in functions
Function | Description
--- | ---
print `expr` | Prints expression `expr` to standard output.

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
