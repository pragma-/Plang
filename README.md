# Plang
Plang is an experimental foray into implementing a programming language in Perl.

Plang is in early development stage. There will be bugs. There will be abrupt design changes.

<!-- md-toc-begin -->
* [Features](#features)
  * [Expressions](#expressions)
    * [Operators](#operators)
  * [Statements and StatementGroups](#statements-and-statementgroups)
  * [Identifiers](#identifiers)
    * [Keywords](#keywords)
    * [Variables](#variables)
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
Expressions perform arithmetic, assignment or logical operations.

    $ ./plang <<< '1 * 2 + (3 * 4)'        # arithmetic expressions
      14
<!-- -->
    $ ./plang <<< '1 + 2 == 4 - 1'         # logical expressions
      1

    $ ./plang <<< '3 > 5'
      0
<!-- -->
    $ ./plang <<< 'a = 5; b = 10; a + b'   # assignment expressions
      15

#### Operators
These are the operators implemented so far, from highest to lowest precedence.

Operator | Description | Associativity
--- | --- | ---
\(\) | Function call     | Left to right
\+\+ | Postfix increment | Left to right
\-\- | Postfix decrement | Left to right
\+\+ | Prefix increment  | Right to left
\-\- | Prefix decrement  | Right to left
!    | Logical negation  | Right to left
\*   | Product           | Left to right
/    | Division          | Left to right
%    | Remainder         | Left to right
\*\* | Exponent          | Right to left
\+   | Addition          | Left to right
\-   | Subtraction       | Left to right
==   | Equality          | Left to right
\>=  | Greater or equal  | Left to right
\<=  | Less or equal     | Left to right
\>   | Greater           | Left to right
\<   | Less              | Left to right
=    | Assignment        | Right to left

### Statements and StatementGroups
    Statement      =>   StatementGroup
                      | FuncDef
                      | Expression TERM
                      | TERM
    StatementGroup =>   L_BRACE Statement+ R_BRACE
    TERM  => ';'

A statement is a single instruction. Statements must be terminated by a semi-colon.

A statement group is multiple statements enclosed by curly-braces.

In Plang, statements have values. The value of a statement is the value of its expression.

The value of a statement group is the value of the final statement in the group.

Plang automatically prints the value of the last statement of the program. To prevent this,
use the `return` keyword as the last statement.

You may print the values of previous statements explicitly by using the `println` function.

    $ ./plang <<< 'println(1 + 2); println(3 * 4); 5 - 6'
      3
      12
      -1

### Identifiers
    IDENT  =>  ('_' | LETTER)  ('_' | LETTER | DIGIT)+
    LETTER =>  'a' - 'z' | 'A' - 'Z'
    DIGIT  =>  '0' - '9'

An identifier is a sequence of characters beginning with an underscore or a letter, optionally followed
by additional underscores, letters or digits.

#### Keywords
Keywords are reserved identifiers that have a special meaning to Plang.

Keyword | Description
--- | ---
fn | function definition
return | return value from function

#### Variables
Variables are declared by assigning a value to an identifier that is not a keyword.

    $ ./plang <<< 'a = 5; a'
      5

Identifiers that have not yet been assigned a value will simply yield 0.

    $ ./plang <<< 'a = 5; a + b'
      5

    $ ./plang <<< '++c; ++c'
      2

### Functions
    FuncDef   => KEYWORD_fn IDENT L_PAREN IdentList* R_PAREN (StatementGroup | Statement)
    IdentList => IDENT COMMA?

A function definition is created by using the `fn` keyword followed by an identifer,
then a list of identifiers enclosed in parentheses. The comma in the list of identifiers
is optional. The body of the function can be either a group of statements enclosed in
braces or it can be a single statement.

Plang functions automatically return the value of the last statement or statement group.
You may use the `return` keyword to return the value of an ealier statement.

To call a function, write its identifier followed by a list of arguments enclosed in
parentheses. Arguments may be any valid expression.

For example, a function to square a value:

    $ ./plang <<< 'fn square(x) x * x; square(2 + 2)'
      16

Another trivial example, adding two numbers:

    $ ./plang <<< 'fn add(a, b) a + b; add(2, 3)'
      5

#### Built-in functions
Function | Parameters | Description
--- | --- | ---
print | `expr` | Prints expression `expr` to standard output.
println | `expr` | Prints expression `expr` to standard output, with a newline appended.

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
