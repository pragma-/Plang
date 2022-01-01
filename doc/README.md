# Plang
Plang is in early development stage. There will be bugs. There will be abrupt design changes.

This README describes what is implemented so far.

<!-- md-toc-begin -->
* [Running Plang in the Bash shell](#running-plang-in-the-bash-shell)
  * [DEBUG environment variable](#debug-environment-variable)
  * [REPL](#REPL)
* [Embedding Plang](#embedding-plang)
* [Running the Unit Tests](#running-the-unit-tests)
* [Example Plang scripts](#example-plang-scripts)
* [The Plang Language (so far)](#the-plang-language-so-far)
  * [Type-checking](#type-checking)
    * [Optional type annotations](#optional-type-annotations)
    * [Type narrowing during inference](#type-narrowing-during-inference)
    * [Type conversion](#type-conversion)
    * [Type unions](#type-unions)
    * [Types](#types)
      * [Any](#any)
      * [Null](#null)
      * [Boolean](#boolean)
      * [Number](#number)
      * [Integer](#integer)
      * [Real](#real)
      * [String](#string)
      * [Array](#array)
      * [Map](#map)
      * [Function](#function)
      * [Builtin](#builtin)
  * [Scoping](#scoping)
  * [Identifiers](#identifiers)
    * [Keywords](#keywords)
  * [Variables](#variables)
  * [Functions](#functions)
    * [Optional type annotations](#optional-type-annotations-1)
    * [Default arguments](#default-arguments)
    * [Named arguments](#named-arguments)
    * [Anonymous functions](#anonymous-functions)
    * [Closures](#closures)
    * [Currying](#currying)
    * [Lazy evaluation](#lazy-evaluation)
  * [Statements and StatementGroups](#statements-and-statementgroups)
    * [if/then/else](#ifthenelse)
    * [while/next/last](#whilenextlast)
  * [Expressions](#expressions)
    * [Operators](#operators)
    * [Truthiness](#truthiness)
  * [String operations](#string-operations)
    * [Relational operations](#relational-operations)
    * [Interpolation](#interpolation)
    * [Concatenation](#concatenation)
    * [Substring search](#substring-search)
    * [Indexing](#indexing)
    * [Substring](#substring)
    * [Regular expressions](#regular-expressions)
  * [Array operations](#array-operations)
    * [Creating and accessing arrays](#creating-and-accessing-arrays)
    * [map](#map-1)
    * [filter](#filter)
  * [Map operations](#map-operations)
    * [Creating and accessing maps](#creating-and-accessing-maps)
    * [exists](#exists)
    * [delete](#delete)
  * [Built-in functions](#built-in-functions)
    * [Input/Output](#inputoutput)
      * [print](#print)
    * [Introspection](#introspection)
      * [type](#type)
      * [whatis](#whatis)
    * [Data and structures](#data-and-structures)
      * [length](#length)
      * [map](#map-2)
      * [filter](#filter-1)
    * [Type conversion](#type-conversion-1)
  * [JSON compatibility/serialization](#json-compatibilityserialization)
<!-- md-toc-end -->

## Running Plang in the Bash shell
You may use the [`plang`](../bin/plang) executable to interpret Plang scripts.

    Usage: plang ([code] | STDIN)

To interpret a Plang file:

    $ ./plang < file

To interpret a string of Plang code:

    $ ./plang 'fn add(a, b) a + b; add(3, 7)'
      10

    $ ./plang <<< '4+5'
      9

Plang automatically prints the value of the last statement of the program. To prevent this,
use the `null` keyword (or construct any statement that doesn't yield a value) as the last statement.

### DEBUG environment variable
You can set the `DEBUG` environment variable to enable debugging output.

The value is a comma-separated list of tags, or `ALL` for everything.

Currently available `DEBUG` tags are: `ERRORS`, `TOKEN`, `PARSER`, `BACKTRACK`, `AST`, `TYPES`, `STMT`, `RESULT`, `OPERS`, `VARS`, `FUNCS`.

    $ DEBUG=OPERS,VARS ./plang <<< '1 + 2'  # debug messages only for tags `OPERS` and `VARS`
<!-- -->
    $ DEBUG=ALL ./plang <<< '1 + 2'         # all debug messages

### REPL
The [`plang_repl`](../bin/plang_repl) script can be used to start a REPL session.
It is recommended to use the `rlwrap` command-line utility for command history.

    $ rlwrap script/plang_repl
     Plang REPL. Type `.help` for help. `.quit` to exit.
     > "Hi!"
      [String] Hi!
     > var a = 42
      [Integer] 42
     > a + 10
      [Integer] 52

## Embedding Plang
Plang is designed to be embedded into larger Perl applications. Here's how you can
do that.

I will get around to documenting this soon. In the meantime, take a look at [this
unit-test script](../bin/runtests) and
 [PBot's Plang plugin](https://github.com/pragma-/pbot/blob/master/Plugins/Plang.pm) for
general idea of how to go about it.

## Running the Unit Tests
There are a number of unit tests in the [`test`](../test/) directory that may be invoked
by the [`runtests`](../bin/runtests) script.

The `runtests` script may be invoked without arguments to run all the tests. Alternatively, you
can specify which tests to run by passing a list of file paths.

    $ ./bin/runtests test/operators.pt test/closures.pt
    Running 2 test files: ..........
    Pass: 10; Fail: 0

A test failure looks like this:

    $ ./bin/runtests test/bad_test.pt
    Running 1 test file: XX.....
    Pass: 5; Fail: 2
    ----------------------------------------------------------------------
    FAIL bad_test.pt: arithmetic
           Expected: [["TYPE","Integer"],21]
                Got: [["TYPE","Integer"],42]
    ----------------------------------------------------------------------
    FAIL bad_test.pt: exponent literals
           Expected: [["TYPE","Real"],1100]
                Got: [["TYPE","Real"],1200]

## Example Plang scripts
[Check out some examples!](../examples/)

## The Plang Language (so far)
### Type-checking
Plang is gradually typed with optional nominal type annotations.

#### Optional type annotations
Plang's type system allows type annotations to be omitted. When type annotations are omitted,
the type will default to `Any`. The `Any` type tells Plang to infer the actual type from the
value provided.

Here is a brief demonstration of a function definition with optional type annotations. Let's consider
a simple `add` function. With no explicit type annotations, the function's return type and the types
of its parameters will default to the `Any` type:

    > fn add(a, b) a + b; print(type(add));
     Function (Any, Any) -> Any

This tells Plang to infer the types of its parameters from the types of the arguments passed,
and the type of its return value from the type of the value being returned.

    > fn add(a, b) a + b; add(3, 4)
     7

But be careful. If a `String` gets passed to it, Plang will terminate its execution
with an undesirable run-time error:

    > fn add(a, b) a + b; add(3, "4")
     Error: cannot apply binary operator ADD (have types Integer and String)

One way to resolve this is to apply the `Real()` type-conversion function to the
parameters inside the function body, creating a polymorphic function that can accept
any arguments that can be converted to `Real`:

    > fn add(a, b) Real(a) + Real(b); add(3, "4")
     7

On the other hand, if you desire explicit type checking on the parameters you can add a
type annotation, prefixed with a colon, after each parameter identifier:

    > fn add(a: Real, b: Real) a + b; print(type(add));
      Function (Real, Real) -> Real

Now Plang will throw a compile-time error if the types of the arguments do not match the
types specified for the parameters:

    > fn add(a: Real, b: Real) a + b; add(3, "4")
     Error: In function call for `add`, expected Real for parameter `b` but got String

This version of `add` returns `Real` because its return type was inferred from the types of
its parameters.

Let's delve a bit into return type inference by considering the `filter` built-in function:

    > print(type(filter))
     Builtin (Function (Any) -> Boolean, Array) -> Array

It has two parameters and returns an `Array`. The first parameter is a `Function` that takes
one `Any` argument and returns a `Boolean` value. The second parameter is an `Array`.

Thanks to type inference, a concise anonymous function without type annotations can be passed
as the first argument:

    > filter(fn(a) a<4, [1,2,3,4,5])
     [1,2,3]

Because the first parameter of the `filter` function is explicitly typed to return a `Boolean` value,
Plang can perform strict compile-time type checking on the return value of the passed argument. For
example, if we pass it a function inferred instead to return an `Integer` we get a helpful type error:

    > filter(fn(a) 4, [1, 2, 3, 4, 5])
     Error: in function call for `filter`, expected Function (Any) -> Boolean
       for parameter `func` but got Function (Any) -> Integer

Let's return to the `add` function. To explicitly specify the type of the return value, you
can place a type annotation, prefixed with an arrow, just before the function body:

    > fn add(a: Real, b: Real) -> Real { a + b }; print(type(add))
     Function (Real, Real) -> Real

Now Plang will throw a compile-time type error if `add` attempts to return a value that
is not a `Real`:

    > fn add(a: Real, b: Real) -> Real { "42" }
     Error: in definition of function `add`: cannot return value of type String from function declared to return type Real

#### Type narrowing during inference
To enforce the consistency of values assigned to the variable during its lifetime,
variables declared as `Any` will be narrowed to the type of the value initially assigned.

For example, a variable of type `Any` initialized to `true` will have its type narrowed
to `Boolean`:

    > var a = true; type(a)
     "Boolean"

It will then be a type error to assign a value of any other type to it.

    > var a = true; a = "hello"
     Error: cannot assign to `a` a value of type String (expected Boolean)

#### Type conversion
For stricter type-safety, Plang does not allow implicit conversion between types.
You must convert a value explicitly to a desired type.

To convert a value to a different type, pass the value as an argument to the
function named after the desired type. To convert `x` to a `Boolean`, write `Boolean(x)`.

Wrong:

    > var a = "45"; a + 1
     Error: cannot apply binary operator ADD (have types String and Integer)

Right:

    > var a = "45"; Integer(a) + 1
     46

#### Type unions
Suppose you want to say that a variable, function parameter or function return will be
either type X or type Y? You can do this with a type union. To make a type union,
separate multiple types with a pipe symbol.

For example, the signature of the `length()` built-in function is:

    Builtin (Array | Map | String) -> Integer

This tells the compiler (and us) that the function is a `Builtin` that takes either
`Array`, `Map` or `String` and returns an `Integer`.

#### Types
The currently implemented types and their subtypes are:

Type | Subtypes
--- | ---
[Any](#Any) | All types
[Null](#Null) | -
[Boolean](#Boolean) | -
[Number](#Number) | [Integer](#Integer), [Real](#Real)
[Integer](#Integer) | -
[Real](#Real) | -
[String](#String) | -
[Array](#Array) | -
[Map](#Map) | -
[Function](#Function) | [Builtin](#Builtin)
[Builtin](#Builtin) | -

##### Any
The `Any` type tells Plang to infer the actual type from the type of the provided value.

##### Null
     Null ::= "null"

The `Null` type's value is always `null`. It is used to signify that there is no meaningful value.

##### Boolean
    Boolean ::= "true" | "false"

A value of type `Boolean` is either `true` or `false`. It is used for conditional expressions and relational operations.

The `Boolean()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Boolean Value
--- | --- | ---
Null | `null` | `false`
Boolean | any value | that value
Number | `0` | `false`
Number | not `0` | `true`
String | `""` | `false`
String | not `""` | `true`

##### Number
    Number ::= HexLiteral | OctalLiteral | IntegerLiteral | RealLiteral

The `Number` type is the supertype of `Integer` and `Real`. Any guard typed as `Number`
will accept a value of types `Integer` or `Real`.

##### Integer
    HexLiteral     ::= "0" ("x" | "X") (Digit | "a" - "f" | "A" - "F")+
    OctalLiteral   ::= "0" ("0" - "9")+
    IntegerLiteral ::= ("0" - "9")+

The `Integer` type denotes an integral value. `Integer` is a subtype of `Number`.

`Integer` literals can be represented as:

* hexadecimal: `0x4a`
* octal: `012`
* integral: `42`

The `Integer()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Integer Value
--- | --- | ---
Null | `null` | `0`
Boolean | `true` | `1`
Boolean | `false` | `0`
Integer | any value | that value
Real | any value | that value with the factional part truncated
String | `""` | `0`
String | `"X"` | if `"X"` begins with an Integer then its value, otherwise `0`

##### Real
    RealLiteral ::= Digit+
                      (
                        "." Digit* ("e" | "E") ("+" | "-")? Digit+
                       | "." Digit+
                       | ("e" | "E") ("+" | "-")? Digit+
                      )?

The `Real` type denotes a floating-point value. `Real` is a subtype of `Number`.

`Real` literals can be represented as:

* floating-point: `3.1459`
* exponential: `6.02e23`

The `Real()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Real Value
--- | --- | ---
Null | `null` | `0`
Boolean | `true` | `1`
Boolean | `false` | `0`
Integer | any value | that value
Real | any value | that value
String | `""` | `0`
String | `"X"` | if `"X"` begins with a Real then its value, otherwise `0`

##### String
    String         ::= ("'" StringContents? "'") | ('"' StringContents? '"')
    StringContents ::= TODO

A `String` is a sequence of characters enclosed in double or single quotes. There is
no significance between the different quotes.

Strings may contain `\`-escaped characters, which will be expanded as expected.

Some such escape sequences and their expansion are:

Escape | Expansion
-- | --
`\n` | newline
`\r` | carriage return
`\t` | horizontal tab
`\"` | literal `"`
`\'` | literal `'`
 etc | ...

The `String()` type conversion function can be used to convert the following:

From Type | With Value | Resulting String Value
--- | --- | ---
Null | null | `""`
Boolean | `true` | `"true"`
Boolean | `false` | `"false"`
Number | any value | that value as a String
String | any value | that value
Array | any value | A String containing a constructor of that Array
Map | any value | A String containing a constructor of that Map

##### Array
    ArrayConstructor ::= "[" (Expression ","?)* "]"

An `Array` is a collection of values. Array elements can be any type. *TODO: Optional type annotations to constrain Array elements to a single type.*

For more details see:

* [Array operations](#array-operations)
* [examples/arrays_and_maps.plang](../examples/arrays_and_maps.plang)

The `Array()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Array Value
--- | --- | ---
String | A String containing an [Array constructor](#array) | the constructed Array
Array | any value | that value

##### Map
    MapConstructor ::= "{" ( (IDENT | String) ":" Expression )* "}"

A `Map` is a collection of key/value pairs. Map keys must be of type `String`. Map
values can be any type. *TODO: Optional interface syntax to ensure that maps contain specific key, as well as values of a specific type.*

For more details see:

* [Map operations](#map-operations)
* [examples/arrays_and_maps.plang](../examples/arrays_and_maps.plang)

The `Map()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Map Value
--- | --- | ---
String | A String containing a [Map constructor](#map) | the constructed Map
Map | any value | that value

##### Function
The `Function` type identifies a normal function defined with the `fn` keyword. See [functions](#functions) for more information.

##### Builtin
The `Builtin` type identifies an internal built-in function. See [built-in functions](#built-in-functions) for more information.

### Scoping
Variables and functions are lexically scoped. Statement groups introduce a new lexical scope.

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
null | a Null with a null value
if | conditional if statement
then | then branch of a conditional if statement
else | else branch of a conditional if statement
while | loop while a condition is true
last | break out of the loop
next | jump to the next iteration of the loop
exists | test if a key exists in a Map
delete | deletes a key from a Map

### Variables
    VariableDeclaration ::= "var" Identifier (":" Type)? Initializer?
    Initializer         ::= "=" Statement

Variables are explicitly declared with the `var` keyword, followed by an identifier.
The identifier may be optionally followed by a type annotation, which is a type description
prefixed with a colon. Variables declarations may optionally have an initializer that assigns
a default value. Without an initializer, the value of variables will default to `null`.

The `var` statement returns the value of the variable. When type annotations are omitted,
the variable's type will be inferred from its initializer value.

    > var a = 5; print(type(a)); a
     Integer
     5

    > var a = "hello"; print(type(a)); a
     String
     "hello"

A type annotation may be provided to enable strict compile-time type-checking.

    > var a: String = 5
     Error: cannot initialize `a` with value of type Integer (expected String)

Attempting to use a variable that has not been declared will produce an error.

    > var a = 5; a + b
     Error: `b` not declared.

Variables that have not yet been assigned a value will produce an error.

    > var a = 5; var b; a + b
     Error: `b` not defined.

### Functions
    FunctionDefinition  ::= "fn" Identifier? IdentifierList? ("->" Type)? Statement
    IdentifierList      ::= "(" (Identifier (":" Type)? Initializer? ","?)* ")"

A function definition is created by using the `fn` keyword followed by:
 * an identifer (which may be omitted to create an anonymous function)
 * an identifier list (which may be omitted if there are no parameters desired)
 * a "->" followed by a type (which may be omitted to infer the return type)
 * and finally either a group of statements or a single statement

An identifier list is a parentheses-enclosed list of identifiers. The list is separated by
a comma and/or whitespace. Each identifier optionally may be followed by a colon and a type
description. Each identifier may optionally be followed by an initializer to create a default value.

Plang functions automatically return the value of the last statement or statement group.
You may use the `return` keyword to return the value of an earlier statement.

To call a function, write its identifier followed by a list of arguments enclosed in
parentheses. The argument list is separated the same way as the identifier list. Arguments
may be any valid expression.

The `fn` statement returns a reference to the newly defined function.

#### Optional type annotations
Function definitions may optionally include type annotations to explicitly restrict
what types the function works with. Without a type annotation the `Any` type is used,
which tells Plang to infer the actual type from the value being supplied or returned.

See [Optional type annotations](#optional-type-annotations) for more information and examples.

#### Default arguments
In a function definition, parameters may optionally be followed by an initializer. This is
called a default argument. Parameters that have a default argument may be omitted from the
function call, and will be replaced with the value of the default argument.

    > fn add(a, b = 10) a + b; add(5);
     15

#### Named arguments
In a function call, arguments can be passed positionally or by name. Arguments that are
passed by name are called named arguments.

Named arguments may be passed only to parameters that have a default argument value. All
parameters without a default arguments are strictly positional parameters. All positional
arguments must be passed prior to passing a named argument.

Consider a function that has many default arguments:

    fn new_creature(name = "a creature", health = 100, armor = 50, damage = 10) ...

You can memorize the order of arguments, which can be error-prone and confusing:

    new_creature("a troll", 125, 75, 25)

Or you can used named arguments, which not only helps readability but also lets you specify
arguments in any order:

    new_creature(damage = 25, health = 125, armor = 75, name = "a troll")

Another advantage of named arguments comes into play when you want to omit some arguments. With
positional arguments, if you wanted to set specific arguments you'd also need to set each
each prior argument, defeating the purpose of the default arguments.

With named arguments you can simply specify the arguments you care about and let the
default arguments do their job for the rest:

    new_creature(armor = 200, damage = 100)

#### Anonymous functions
Here are some ways to define an anonymous function:

    > var greeter = fn { print("Hello!") }; greeter()
     Hello!
<!-- -->
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

### Statements and StatementGroups
    Statement      ::=  StatementGroup
                      | IfStatement
                      | WhileStatement
                      | [ et cetera ]
                      | Expression Terminator?
                      | Terminator?
    StatementGroup ::=  "{" Statement+ "}"
    Terminator     ::=  ";"

A statement is a single instruction. A statement group is multiple statements enclosed in curly-braces.

In Plang, statements and statement groups have values. The value of a statement is the value of its expression.
The value of a statement group is the value of the final statement in the group.

#### if/then/else
    IfStatement ::= "if" Statement "then" Statement ("else" Statement)?

The `if` statement expects a condition expression followed by the `then` keyword and then
either a single statement or a group of statements enclosed in braces. This can optionally
then be followed by the `else` keyword and another single statement or group of statements
enclosed in braces.

If the condition is [truthy](#truthiness) then the statement(s) in the `then` branch are executed, otherwise
if an `else` branch exists then its statement(s) are executed. The value of the `if` statement is the
value of the final statement of the branch that was executed.

    > if true then 1 else 2
     1

    > if false then 1 else 2
     2

#### while/next/last
    WhileStatement ::= "while" "(" Statement ")" Statement

The `while` statement expects a condition enclosed in parentheses, followed by a single statement
or a group of statements enclosed in braces.

As long as the condition is [truthy](#truthiness) the statement(s) in its body will be executed.
The value of the `while` statement is `null`.

The `next` keyword can be used to immediately jump to the next iteration of the loop.

The `last` keyword can be used to immediately exit the loop.

    > var i = 0; while (++i <= 5) print(i, end=" "); print("");
     1 2 3 4 5

### Expressions
Expressions perform arithmetic, logical or assignment operations.

#### Operators
These are the operators implemented so far, from highest to lowest precedence.

 Precedence | Operator   | Description              | Associativity
--- | ---   | ---                      | ---
18  | .    | Class/Map access         | Infix (left-to-right)
17  | ()   | Function call            | Postfix
16  | []   | Array/Map access         | Postfix
16  | ++   | Post-increment           | Postfix
16  | --   | Post-decrement           | Postfix
15  | ++   | Pre-increment            | Prefix
15  | --   | Pre-decrement            | Prefix
15  | !    | Logical negation         | Prefix
14  | ^    | Exponent                 | Infix (right-to-left)
14  | **   | Exponent                 | Infix (right-to-left)
14  | %    | Remainder                | Infix (left-to-right)
13  | *    | Product                  | Infix (left-to-right)
13  | /    | Division                 | Infix (left-to-right)
12  | +    | Addition                 | Infix (left-to-right)
12  | -    | Subtraction              | Infix (left-to-right)
11  | ^^   | String concatenation     | Infix (left-to-right)
11  | ~    | Substring index          | Infix (left-to-right)
10  | >=   | Greater or equal         | Infix (left-to-right)
10  | <=   | Less or equal            | Infix (left-to-right)
10  | >    | Greater                  | Infix (left-to-right)
10  | <    | Less                     | Infix (left-to-right)
9   | ==   | Equality                 | Infix (left-to-right)
9   | !=   | Inequality               | Infix (left-to-right)
8   | &&   | Logical and              | Infix (left-to-right)
7   | \|\| | Logical or               | Infix (left-to-right)
6   | ?:   | Conditional              | Infix ternary (right-to-left)
5   | =    | Assignment               | Infix (right-to-left)
5   | +=   | Addition assignment      | Infix (right-to-left)
5   | -=   | Subtraction assignment   | Infix (right-to-left)
5   | \*=  | Product assignment       | Infix (right-to-left)
5   | /=   | Division assignment      | Infix (right-to-left)
5   | .=   | String concat assignment | Infix (right-to-left)
4   | ,    | Comma                    | Infix (left-to-right)
3   | not  | Logical negation         | Prefix
2   | and  | Logical and              | Infix (left-to-right)
1   | or   | Logical or               | Infix (left-to-right)

`!`, `&&`, and `||` have high precedence such that they are useful in constructing an expression;
`not`, `and`, and `or` have low precedence such that they are useful for flow control between
what are essentially different expressions.

#### Truthiness
For the logical operators (==, ||, &&, etc), this is how truthiness
is evaluated for each type. If a type is omitted from the table, it is an error
to use that type in a truthy expression.

Type | Truthiness
--- | ---
Boolean | `false` when value is `false`; `true` otherwise.
Number | `false` when value is `0`; `true` otherwise.
String | `false` when value is empty string; `true` otherwise.

### String operations
#### Relational operations
The relational operators behave as expected. There is no need to compare against `-1`, `0` or `1`.

    > "blue" < "red"
     true

#### Interpolation
When prefixed with a dollar-sign, a `String` will interpolate any brace-enclosed Plang code.

    > var a = 42; $"hello {a + 1} world"
     "hello 43 world"

#### Concatenation
To concatenate two strings, use the `^^` operator. But consider using [interpolation](#interpolation) instead.

    > var a = "Plang"; var b = "Rocks!"; a ^^ " " ^^ b
     "Plang Rocks!"

#### Substring search
To find the index of a substring within a string, use the `~` operator.

    > "Hello world!" ~ "world"
     6

#### Indexing
To get a positional character from a string, you can use postfix `[]` access notation.

    > "Hello!"[0]
     "H"

You can use negative numbers to start from the end.

    > "Hello!"[-2]
     "o"

You can assign to the above notation to replace the character instead.

    > "Hello!"[0] = "Jee"
     "Jeeello!"

#### Substring
To extract a substring from a string, you can use the `..` range operator inside
postfix `[]` access notation.

    > "Hello!"[1..4]
     "ello"

You can assign to the above notation to replace the substring instead.

    > "Good-bye!"[5..7] = "night"
     "Good-night!"

#### Regular expressions
You may use regular expressions on strings with the `~=` operator.

### Array operations
#### Creating and accessing arrays
Creating an array and accessing an element:

    > var array = ["red, "green", 3, 4]; array[1]
     "green"

#### map
See the documentation for the builtin [map](#map-2) function.

#### filter
See the documentation for the builtin [filter](#filter-1) function.

### Map operations
#### Creating and accessing maps
To create a map use curly braces optionally containing a list of key/value pairs
formatted as `key: value` where `key` is of type `String`.

    > var x = {"y": 42, "z": true}

There are two syntactical ways to set/access map keys. The first, and core, way
is to use a value of type `String` enclosed in square brackets.

    > var x = {}; x["y"] = 42; x
     {"y": 42}

The second way is to use the `.` operator followed by a bareword value. A
bareword value is a single `String` word without quotation symbols. As such,
bareword values cannot contain whitespace.

    > var x = {}; x.y = 42; x
     {"y": 42}

Nested maps:

    > var m = {}; m["x"] = {}; m["x"]["y"] = 42; m
     {"x": {"y": 42}}

    > var m = {"x": {"y": 42}}; m["x"]["y"]
     42

    > var m = {}; m["x"] = {"y": 42}; m["x"]["y"]
     42

Same as above, but using the alternative `.` access syntax:

    > var m = {}; m.x = {}; m.x.y = 42; m
     {"x": {"y": 42}}

    > var m = {"x": {"y": 42}}; m.x.y
     42

    > var m = {}; m.x = {"y": 42}; m.x.y
     42

#### exists
To check for existence of a map key, use the `exists` keyword. If the key exists then
`true` is yielded, otherwise `false`. Note that setting a map key to `null` does not
delete the key. See the [`delete`](#delete) keyword.

    > var m = { "a": 1, "b": 2 }; exists m["a"]
     true

#### delete
To delete keys from a map, use the `delete` keyword. Setting a key to `null` does not
delete the key.

When used on a Map key, the `delete` keyword deletes the key and returns its value, or
`null` if no such key exists.

When used on a Map itself, the `delete` keyword deletes all keys in the map and returns
the empty map.

    > var m = { "a": 1, "b": 2 }; delete m["b"]; m
     { "a": 1 }

    > var m = { "a": 1, "b": 2 }; delete m; m
     {}

### Built-in functions
These are the built-in functions. You can add additional built-in functions
through Plang's embedding API.

#### Input/Output
##### print
The `print` function sends text to the standard output stream.

Its signature is: `Builtin (expr: Any, end: String = "\n") -> Null`

In other words, it takes two parameters and returns a `Null` value. The first parameter,
`expr`, is an expression of `Any` type, signifying what is to be printed. The second
parameter, `end`, a `String` with a default argument of `"\n"`, is always appended
to the output.

    > print("hello!"); print("good-bye!")
     hello!
     good-bye!

    > print("hello!", " "); print("good", ""); print("-bye!");
     hello! good-bye!

Optionally, you can use [named arguments](#named-arguments) for clarity:

    > print("hello!", end=" "); print("good", end=""); print("-bye!");
     hello! good-bye!

#### Introspection
##### type
The `type` function returns the type of an expression, as a string. For functions,
it returns strictly the type signature. If you're interested in function parameter
identifiers and default arguments, see the [`whatis`](#whatis) builtin function.

Its signature is: `Builtin (expr: Any) -> String`

    > type(3.14)
     "Real"

    > var a = "hello"; type(a)
     "String"

    > type(print)
     "Builtin (Any, String) -> Null"

    > type(filter)
     "Builtin (Function (Any) -> Boolean, Array) -> Array"

##### whatis
The `whatis` function is identical to the [`type`](#type) function, but with the
addition of function parameter identifiers and function default arguments.

    > whatis(print)
     "Builtin (expr: Any, end: String = \"\\n\") -> Null"

    > print(whatis(print)) # use `print` to avoid string escaping
     Builtin (expr: Any, end: String = "\n") -> Null

    > whatis(filter)
     "Builtin (func: Function (Any) -> Boolean, list: Array) -> Array"

#### Data and structures
##### length
The `length` function returns the count of elements within an expression of type
`String`, `Array` or `Map`.

For `String` it returns the count of characters. For `Array` it returns the count
of elements. For `Map` it returns the count of keys.

Its signature is: `Builtin (expr: Array | Map | String) -> Integer`

    > length("Hello!")
     6

    > length([10,20,30,40])
     4

    > length({"a": 1, "b": 2, "c": 3})
     3

##### map
The `map` function applies a function to each element of an array, updating that
element in-place with the result of the applied function. The parameter of the
applicative function is the current element it is being applied upon.

Its signature is: `Builtin (func: Function (Any) -> Any, list: Array) -> Array`

In other words, it takes two parameters and returns an `Array`. The first parameter,
`func`, is a `Function` that takes `Any` and returns `Any`. The second parameter,
`list`, is an `Array`.

    > map(fn(x) x*10, [1,2,3,4,5])
     [10,20,30,40,50]

##### filter
The `filter` function applies a function over an array's elements and constructs
a new array whose elements meet the criteria of the applied function.

Its signature is: `Builtin (func: Function (Any) -> Boolean, list: Array) -> Array`

In other words, it takes two parameters and returns an `Array`. The first parameter,
`func`, is a `Function` that takes `Any` and returns a `Boolean`. The second parameter,
`list`, is an `Array`.

    > filter(fn(x) x < 4, [1,2,3,4,5])
     [1,2,3]

    > filter(fn(x) x['type'] == 'dog', [{'type': 'dog', 'name': 'Woofers'}, {'type': 'cat', 'name': 'Whiskers'}])
     [{'type': 'dog', 'name': 'Woofers'}]

#### Type conversion
See [Types](#types).

### JSON compatibility/serialization
An [Array constructor](#array) is something like `["red", 2, 3.1459, null]`.

A [Map constructor](#map) is something like `{"name": "Bob", "age": 32}`.

This syntax is compatible with JSON. This allows easy and convenient serialization of
Plang data structures for data-exchange and interoperability.

The String() [type conversion function](#type-conversion) can be used to convert or serialize Arrays
and Maps to Strings for external storage or transmission.

The Array() and Map() type conversion functions can be used to convert a String containing
an Array constructor or a Map constructor back to an Array or a Map object.

See [examples/arrays_and_maps.plang](../examples/arrays_and_maps.plang) and [examples/json.plang](../examples/json.plang) for more details.
