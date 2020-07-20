# Plang
Plang is a pragmatic scripting language written in Perl.

Why? Because I need a small, yet useful, scripting language I can embed into
some Perl scripts I have; notably [PBot](https://github.com/pragma-/pbot), an IRC bot that I've been tinkering with
for quite a while.

I want to be able to allow text from external sources to be safely interpreted
in a sandbox environment with access to exposed Perl subroutines, with full control over
how deeply functions are allowed to recurse, et cetera.

Plang is in early development stage. There will be bugs. There will be abrupt design changes.

This README describes what is implemented so far.

Here's a helpful table of contents:

<!-- md-toc-begin -->
* [Running Plang in the Bash shell](#running-plang-in-the-bash-shell)
  * [DEBUG environment variable](#debug-environment-variable)
* [Embedding Plang](#embedding-plang)
* [The Plang Language (so far)](#the-plang-language-so-far)
  * [Expressions](#expressions)
    * [Operators](#operators)
    * [Truthiness](#truthiness)
  * [Statements and StatementGroups](#statements-and-statementgroups)
  * [Identifiers](#identifiers)
    * [Keywords](#keywords)
  * [Variables](#variables)
    * [Types](#types)
      * [Number](#number)
      * [String](#string)
      * [Boolean](#boolean)
      * [Nil](#nil)
  * [Functions](#functions)
    * [Trivial examples](#trivial-examples)
    * [Default arguments](#default-arguments)
    * [Anonymous functions](#anonymous-functions)
    * [Closures](#closures)
    * [Currying](#currying)
    * [Lazy evaluation](#lazy-evaluation)
    * [Built-in functions](#built-in-functions)
  * [Scoping](#scoping)
  * [if/then/else statement](#ifthenelse-statement)
  * [while/next/last statement](#whilenextlast-statement)
  * [String operations](#string-operations)
    * [Relational operations](#relational-operations)
    * [Interpolation](#interpolation)
    * [Concatenation](#concatenation)
    * [Substring search](#substring-search)
    * [Indexing](#indexing)
    * [Substring](#substring)
    * [Regular expressions](#regular-expressions)
* [Example Plang scripts](#example-plang-scripts)
<!-- md-toc-end -->

## Running Plang in the Bash shell
You may use the [`plang`](plang) executable to interpret Plang scripts. Currently, it
strictly reads from standard input.

    Usage: plang [--dumptokens]

To interpret a Plang file:

    $ ./plang < file

To interpret a string of Plang code:

    $ ./plang <<< '"Hello world!"'
      Hello world!

Plang automatically prints the value of the last statement of the program. To prevent this,
use the `nil` keyword (or construct any statement that doesn't yield a value) as the last statement.

You can pass `--dumptokens` as a command-line argument to display a flat-list
of all the tokens as they are encountered.

    $ ./plang --dumptokens < test/lexer_input.txt  # test the lexer

### DEBUG environment variable
You can set the `DEBUG` environment variable to enable debugging output.

The value is an integer representing verbosity, where higher values are more verbose.

    $ DEBUG=1 ./plang <<< '1 + 2'  # minimal (though still a quite a bit) output
<!-- -->
    $ DEBUG=10 ./plang <<< '1 + 2'  # most verbose debugging output

## Embedding Plang
Plang is designed to be embedded into larger Perl applications. Here's how you can
do that.

I will get around to documenting this soon. In the meantime, take a look at [this
unit-test script](test/unit_tests.pl) for a simple example. For a more advanced example, see
 [PBot's Plang plugin.](https://github.com/pragma-/pbot/blob/master/Plugins/Plang.pm)

## The Plang Language (so far)
### Expressions
Expressions perform arithmetic, logical or assignment operations.

#### Operators
These are the operators implemented so far, from highest to lowest precedence.

The precedence values are large to give me some space to add new operators with
new precedence. When the dust settles, the values will be made more sensible.

P | Operator | Description | Type
--- | --- | --- | ---
100 | () | Function call    |
70 | [] | Array notation    | Postfix
70 | ++ | Post-increment    | Postfix
70 | -- | Post-decrement    | Postfix
60 | ++ | Pre-increment     | Prefix
60 | -- | Pre-decrement     | Prefix
60 | !  | Logical negation  | Prefix
50 | ** | Exponent          | Infix (right-to-left)
50 | %  | Remainder         | Infix (left-to-right)
40 | *  | Product           | Infix (left-to-right)
40 | /  | Division          | Infix (left-to-right)
30 | +  | Addition          | Infix (left-to-right)
30 | -  | Subtraction       | Infix (left-to-right)
25 | .  | String concatenation | Infix (left-to-right)
25 | ~  | Substring index      | Infix (left-to-right)
23 | >= | Greater or equal  | Infix (left-to-right)
23 | <= | Less or equal     | Infix (left-to-right)
23 | >  | Greater           | Infix (left-to-right)
23 | <  | Less              | Infix (left-to-right)
20 | == | Equality          | Infix (left-to-right)
20 | != | Inequality        | Infix (left-to-right)
17 | && | Logical and       | Infix (left-to-right)
16 | \|\| | Logical or        | Infix (left-to-right)
15 | ?: | Conditional       | Infix ternary (right-to-left)
10 | =  | Assignment        | Infix (right-to-left)
10 | += | Addition assignment     | Infix (right-to-left)
10 | -= | Subtraction assignment  | Infix (right-to-left)
10 | \*= | Product assignment     | Infix (right-to-left)
10 | /= | Division assignment     | Infix (right-to-left)
7  | .= | String concat assignment | Infix (right-to-left)
5  | ,  | Comma             | Infix (left-to-right)
4  | not | Logical negation | Prefix
3  | and | Logical and      | Infix (left-to-right)
2  | or  | Logical or       | Infix (left-to-right)

`!`, `&&`, and `||` have high precedence such that they are useful in constructing an expression;
`not`, `and`, and `or` have low precedence such that they are useful for flow control between
what are essentially different expressions.

#### Truthiness
For the logical operators (==, ||, &&, etc), this is how truthiness
is evaluated for each type.

Type | Truthiness
--- | ---
Number | false when value is `0`;true otherwise.
String | false when value is empty string; true otherwise.
Boolean | false when value is `false`; true otherwise.
Nil | Attempting to use a Nil type is always an error.

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
true | a Boolean with a true value
false | a Boolean with a false value
nil | a Nil with a nil value
if | conditional if statement
then | then branch of a conditional if statement
else | else branch of a conditional if statement
while | loop while a condition is true
last | break out of the loop
next | jump to the next iteration of the loop

### Variables
    VariableDeclaration ::= "var" Identifier Initializer?
    Initializer         ::= "=" Statement

Variables are explicitly declared with the `var` keyword, followed by an identifier. Variables declarations
may optionally have an initializer that assigns a default value. Without an initializer, the value of
variables will default to `nil`, which has type `Nil`.

The `var` statement returns the value of the variable.

    > var a = 5
      5

    > var a = "hello"
      hello

Attempting to use a variable that has not been declared will produce an error.

    > var a = 5; a + b
      Error: `b` not declared.

Variables that have not yet been assigned a value will produce an error.

    > var a = 5; var b; a + b
      Error: `b` not defined.

#### Types
At this stage, there are seven types planned: reference, array, table, string, number, boolean and nil.

Types of variables are inferred from the type of their value. All variables are simply declared with `var`
and no type specifier.

Currently implemented are:

##### Number
    Number ::= ("-" | "+")? ("0" - "9")* "."? ("0" - "9")+

`Number`s are things like `-100`, `+4.20`, `2001`, etc. We all know what numbers are!

In Plang, the `Number` type is equivalent to a double-precision type.

##### String
    String         ::= ("'" StringContents? "'") | ('"' StringContents? '"')
    StringContents ::= TODO

A `String` is a sequence of characters enclosed in double or single quotes. There is
no difference between the quotes.

##### Boolean
    Boolean ::= "true" | "false"

A `Boolean` is either true or false.

##### Nil
     Nil ::= "Nil"

The `Nil` type signifies that there is no value. All logical comparisons against `Nil` produce
`Nil`.

### Functions
    FunctionDefinition ::= "fn" Identifier? IdentifierList? Statement
    IdentifierList     ::= "(" (Identifier Initializer? ","?)* ")"

A function definition is created by using the `fn` keyword followed by: an identifer (which may
be omitted to create an anonymous function), an identifier list (which may be omitted if there
are no parameters desired), and finally either a group of statements or a single statement.

An identifier list is a list of identifiers enclosed in parentheses. The list is separated
by a comma and/or whitespace. In other words, the comma is optional. Each identifier may
be followed by an optional initializer to create a default value.

Plang functions automatically return the value of the last statement or statement group.
You may use the `return` keyword to return the value of an ealier statement.

To call a function, write its identifier followed by a list of arguments enclosed in
parentheses. The argument list is separated the same way as the identifier list. Arguments
may be any valid expression.

The `fn` statement returns a reference to the newly defined function.

#### Trivial examples
    > fn square(x) x * x; square(2 + 2)
      16
<!-- -->
    > fn add(a, b) a + b; add(2, 3)
      5

#### Default arguments
    > fn add(a, b = 10) a + b; add(5);
      15

#### Anonymous functions
    > var adder = fn (a, b) a + b; adder(10, 20)
      30
<!-- -->
    > (fn (a, b) a + b)(1, 2)
      3
<!-- -->
    > (fn 42)()
      42

#### Closures
The following snippet:

    fn counter { var i = 0; fn ++i }
    var count1 = counter()
    var count2 = counter()
    $"{count1()} {count1()} {count1()} {count2()} {count1()} {count2()}"

produces the output:

    1 2 3 1 4 2

#### Currying
    > var a = fn (x) fn (y) x + y;  a(3)(4)
      7

#### Lazy evaluation
    > fn force(f) f(); var lazy = fn 1 + 1; force(lazy)
      2

#### Built-in functions
Function | Parameters | Description
--- | --- | ---
print | `expr`, `end` = `"\n"` | Prints expression `expr` to standard output. The optional `end` parameter defaults to `"\n"`.
type | `expr` | Returns the type of an expression, as a string.

### Scoping
Functions and variables are lexically scoped. A statement group introduces a new lexical scope. There is some
consideration about allowing a way to write to the enclosing scope's identifiers.  `global` and
`nonlocal` are potential keywords.

### if/then/else statement
    IfStatement ::= "if" Statement "then" Statement ("else" Statement)?

The `if` statement expects a condition expression followed by the `then` keyword and then
either a single statement or a group of statements enclosed in braces. This can optionally
then be followed by the `else` keyword and another single statement or group of statements
enclosed in braces.

If the condition is [truthy](#truthiness) then the statement(s) in the `then` branch are executed, otherwise
if an `else` branch exists then its statement(s) are executed. The value of the `if` statement is the
value of the final statement of the branch that was executed.

    if true then 1 else 2
      1

    if false then 1 else 2
      2

### while/next/last statement
    WhileStatement ::= "while" "(" Statement ")" Statement

The `while` statement expects a condition enclosed in parentheses, followed by a single statement
or a group of statements enclosed in braces.

As long as the condition is [truthy](#truthiness) the statement(s) in its body will be executed.
The value of the `while` statement is `nil`.

The `next` keyword can be used to immediately jump to the next iteration of the loop.

The `last` keyword can be used to immediately exit the loop.

### String operations
#### Relational operations
The relational operators behave as expected. There is no need to compare against `-1`, `0` or `1`.

    > "blue" < "red"
      true

#### Interpolation
When prefixed with a dollar-sign, a `String` will interpolate any brace-enclosed Plang code.

      > var a = 42; $"hello {a + 1} world"
      hello 43 world

#### Concatenation
To concatenate two strings, use the `.` operator. But consider using [interpolation](#interpolation) instead.

    > var a = "Plang"; var b = "Rocks!"; a . " " . b
      Plang Rocks!

#### Substring search
To find the index of a substring within a string, use the `~` operator.

    > "Hello world!" ~ "world"
      6

#### Indexing
To get a positional character from a string, you can use postfix `[]` array notation.

    > "Hello!"[0]
      H

You can use negative numbers to start from the end.

    > "Hello!"[-2]
      o

You can assign to the above notation to replace the character instead.

    > "Hello!"[0] = "Jee"
      Jeeello!

#### Substring
To extract a substring from a string, you can use the `..` range operator inside
postfix `[]` array notation.

    > "Hello!"[1..4]
      ello

You can assign to the above notation to replace the substring instead.

    > "Good-bye!"[5..7] = "night"
      Good-night!

#### Regular expressions
You may use regular expressions on strings with the `~=` operator.

## Example Plang scripts
[Check out some examples!](examples/)

