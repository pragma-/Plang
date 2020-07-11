# Plang
Plang is an experimental foray into implementing a programming language in Perl.

Why? Because I wanted a small, yet useful, scripting language I could embed into
some Perl scripts I have; notably [PBot](https://github.com/pragma-/pbot), an IRC bot that I've been tinkering with
for quite a while.

I wanted to be able to allow text from external sources to be safely interpreted
in a sandbox environment with access to exposed Perl subroutines.

I originally tried using [PPI](https://metacpan.org/pod/PPI) to analyze and filter Perl subroutines
and expressions, but it proved impossible to make the programs safe and still able to do anything.

Since I've always wanted to explore how a scripting language is made and what kind of unique
ideas I might come up with, I decided to start writing Plang.

Plang is in early development stage. There will be bugs. There will be abrupt design changes.

This README describes what is implemented so far.

Here's a helpful table of contents:

<!-- md-toc-begin -->
* [Implementation](#implementation)
  * [Expressions](#expressions)
    * [Operators](#operators)
  * [Statements and StatementGroups](#statements-and-statementgroups)
  * [Identifiers](#identifiers)
    * [Keywords](#keywords)
    * [Variables](#variables)
      * [Scoping](#scoping)
  * [Functions](#functions)
    * [Built-in functions](#built-in-functions)
* [Debugging](#debugging)
  * [DEBUG environment variable](#debug-environment-variable)
  * [Testing the lexer](#testing-the-lexer)
<!-- md-toc-end -->

## Implementation
Plang automatically prints the value and type of the last statement of the program. To prevent this,
use the `return` keyword (or construct any statement that doesn't yield a value) as the last statement.

You may print the values of any statements explicitly by using the `println` function.

    $ ./plang <<< 'println(1 + 2); println(3 * 4); "Hello there!"'
      3
      12
      "Hello there!" (STRING)

### Expressions
Expressions perform arithmetic, logical or assignment operations.

    $ ./plang <<< '1 * 2 + (3 * 4)'        # arithmetic expressions
      14 (NUM)
<!-- -->
    $ ./plang <<< '1 + 2 == 4 - 1'         # logical expressions
      1 (NUM)

    $ ./plang <<< '3 > 5'
      0 (NUM)
<!-- -->
    $ ./plang <<< 'a = 5; b = 10; a + b'   # assignment expressions
      15 (NUM)

#### Operators
These are the operators implemented so far, from highest to lowest precedence.

Operator | Description | Type
--- | --- | ---
\(\) | Function call     |
\+\+ | Postfix increment | Postfix
\-\- | Postfix decrement | Postfix
\+\+ | Prefix increment  | Prefix
\-\- | Prefix decrement  | Prefix
!    | Logical negation  | Prefix
\*   | Product           | Infix (left-to-right)
/    | Division          | Infix (left-to-right)
%    | Remainder         | Infix (left-to-right)
\*\* | Exponent          | Infix (right-to-left)
\+   | Addition          | Infix (left-to-right)
\-   | Subtraction       | Infix (left-to-right)
==   | Equality          | Infix (left-to-right)
\>=  | Greater or equal  | Infix (left-to-right)
\<=  | Less or equal     | Infix (left-to-right)
\>   | Greater           | Infix (left-to-right)
\<   | Less              | Infix (left-to-right)
=    | Assignment        | Infix (right-to-left)

### Statements and StatementGroups
    Statement      ::=  StatementGroup
                      | VariableDeclaration
                      | FunctionDefinition
                      | Expression Terminator
                      | Terminator
    StatementGroup ::=  "{" Statement+ "}"
    Terminator     ::=  ";"

A statement is a single instruction. Statements must be terminated by a semi-colon.

A statement group is multiple statements enclosed in curly-braces.

In Plang, statements have values. The value of a statement is the value of its expression.

The value of a statement group is the value of the final statement in the group.

### Identifiers
    Identifier ::=  ("_" | Letter)  ("_" | Letter | Digit)*
    Letter     ::=  "a" - "z" | "A" - "Z"
    Digit      ::=  "0" - "9"

An identifier is a sequence of characters beginning with an underscore or a letter, optionally followed
by additional underscores, letters or digits.

#### Keywords
Keywords are reserved identifiers that have a special meaning to Plang.

Keyword | Description
--- | ---
var | variable declaration
fn | function definition
return | return value from function

#### Variables
    VariableDeclaration ::= "var" Identifier Initializer?
    Initializer         ::= "=" Expression

Variables are explicitly declared with the `var` keyword, followed by an identifier. Variables declarations
may optionally have an initializer that assigns a default value.

The `var` statement returns the value of the variable.

    $ ./plang <<< 'var a = 5'
      5 (NUM)

    $ ./plang <<< 'var a = "hello"'
      "hello" (STRING)

Attempting to use a variable that has not been declared will produce an error.

    $ ./plang <<< 'var a = 5; a + b'
      Error: `b` not declared.

Variables that have not yet been assigned a value will produce an error.

    $ ./plang <<< 'var a = 5; var b; a + b'
      Error: `b` not defined.

##### Scoping
Variables are lexically scoped. A statement group introduces a new lexical scope. There is some
consideration about allowing a way to write to the enclosing scope's identifiers.  `global` and
`nonlocal` are potential keywords.

### Functions
    FunctionDefinition ::= "fn" Identifier IdentifierList (StatementGroup | Statement)
    IdentifierList     ::= "(" (Identifier ","?)* ")"

A function definition is created by using the `fn` keyword followed by an identifer,
then a list of identifiers enclosed in parentheses. The comma in the list of identifiers
is optional. The body of the function can be either a group of statements enclosed in
braces or it can be a single statement.

Plang functions automatically return the value of the last statement or statement group.
You may use the `return` keyword to return the value of an ealier statement.

To call a function, write its identifier followed by a list of arguments enclosed in
parentheses. Arguments may be any valid expression.

The `fn` statement returns a reference to the function.

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
    $ DEBUG=10 ./plang <<< '1 + 2'  # most verbose debugging output

### Testing the lexer
You can pass `--dumptokens` as a command-line argument to display a flat-list
of all the tokens as they are encountered.

    $ ./plang --dumptokens < test/lexer_input.txt  # test the lexer
