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

<!-- md-toc-begin -->
* [Running Plang in the Bash shell](#running-plang-in-the-bash-shell)
  * [DEBUG environment variable](#debug-environment-variable)
* [Embedding Plang](#embedding-plang)
* [Example Plang scripts](#example-plang-scripts)
* [JSON compatibility/serialization](#json-compatibilityserialization)
* [The Plang Language (so far)](#the-plang-language-so-far)
  * [Identifiers](#identifiers)
    * [Keywords](#keywords)
  * [Scoping](#scoping)
  * [Variables](#variables)
  * [Functions](#functions)
    * [Type-checking](#type-checking)
    * [Default arguments](#default-arguments)
    * [Named arguments](#named-arguments)
    * [Anonymous functions](#anonymous-functions)
    * [Closures](#closures)
    * [Currying](#currying)
    * [Lazy evaluation](#lazy-evaluation)
    * [Built-in functions](#built-in-functions)
  * [Types](#types)
    * [Null](#null)
    * [Boolean](#boolean)
    * [Number](#number)
    * [String](#string)
    * [Array](#array)
      * [Creating and accessing arrays](#creating-and-accessing-arrays)
    * [Map](#map)
      * [Creating and accessing maps](#creating-and-accessing-maps)
      * [Exists](#exists)
      * [Delete](#delete)
      * [Function](#function)
      * [Builtin](#builtin)
    * [Type conversion](#type-conversion)
      * [Null()](#null-1)
      * [Boolean()](#boolean-1)
      * [Number()](#number-1)
      * [String()](#string-1)
      * [Array()](#array-1)
      * [Map()](#map-1)
      * [Function()](#function-1)
      * [Builtin()](#builtin-1)
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
<!-- md-toc-end -->

## Running Plang in the Bash shell
You may use the [`plang`](plang) executable to interpret Plang scripts. Currently, it
strictly reads from standard input.

    Usage: plang [--dumptokens]

To interpret a Plang file:

    $ ./plang < file

To interpret a string of Plang code:

    $ ./plang <<< '"Hello world!"'
      "Hello world!"

Plang automatically prints the value of the last statement of the program. To prevent this,
use the `null` keyword (or construct any statement that doesn't yield a value) as the last statement.

You can pass `--dumptokens` as a command-line argument to display a flat-list
of all the tokens as they are encountered.

    $ ./plang --dumptokens < test/lexer_input.txt  # test the lexer

### DEBUG environment variable
You can set the `DEBUG` environment variable to enable debugging output.

The value is a comma-separated list of tags, or `ALL` for everything.

Currently available `DEBUG` tags are: `TOKEN`, `PARSER`, `BACKTRACK`, `AST`, `STMT`, `RESULT`, `OPERS`, `VARS`, `FUNCS`.

    $ DEBUG=OPERS,VARS ./plang <<< '1 + 2'  # debug messages only for tags `OPERS` and `VARS`
<!-- -->
    $ DEBUG=ALL ./plang <<< '1 + 2'         # all debug messages

## Embedding Plang
Plang is designed to be embedded into larger Perl applications. Here's how you can
do that.

I will get around to documenting this soon. In the meantime, take a look at [this
unit-test script](test/unit_tests.pl) for a simple example. For a more advanced example, see
 [PBot's Plang plugin.](https://github.com/pragma-/pbot/blob/master/Plugins/Plang.pm)

## Example Plang scripts
[Check out some examples!](examples/)

## JSON compatibility/serialization
An [Array constructor](#array) is something like `["red",2,3.1459,null]`.

A [Map constructor](#map) is something like `{"name": "Bob", "age": 32}`.

It's no coincidence that this syntax is compatible with JSON. This allows easy and
convenient serialization of Plang data structures for data-exchange and interoperability.

The String() [type conversion function](#type-conversion) can be used to convert or serialize Arrays
and Maps to Strings for external storage or transmission.

The Array() and Map() type conversion functions can be used to convert a String containing
an Array constructor or a Map constructor back to an Array or a Map object.

See [examples/arrays_and_maps.pl](examples/arrays_and_maps.pl) and [examples/json.pl](examples/json.pl) for more details.

## The Plang Language (so far)
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

### Scoping
Variables and functions are lexically scoped. Statement groups introduce a new lexical scope.

### Variables
    VariableDeclaration ::= "var" Identifier Initializer?
    Initializer         ::= "=" Statement

Variables are explicitly declared with the `var` keyword, followed by an identifier. Variables declarations
may optionally have an initializer that assigns a default value. Without an initializer, the value of
variables will default to `null`, which has type `Null`.

Types of variables are inferred from the type of their value. All variables are simply declared with `var`
and no type specifier. However, there is no implicit conversion between types. You must [explicitly convert](#type-conversion) a
value to change its type.

The `var` statement returns the value of the variable.

    > var a = 5
     5

    > var a = "hello"
     "hello"

Attempting to use a variable that has not been declared will produce an error.

    > var a = 5; a + b
     Error: `b` not declared.

Variables that have not yet been assigned a value will produce an error.

    > var a = 5; var b; a + b
     Error: `b` not defined.

### Functions
    FunctionDefinition  ::= "fn" Type? Identifier? IdentifierList? Statement
    IdentifierList      ::= "(" (Type? Identifier Initializer? ","?)* ")"
    Type ::= "Any" | "Null" | "Boolean" | "Number" | "String" | "Array" | "Map" | "Function" | "Builtin"

A function definition is created by using the `fn` keyword followed by:
 * a type specifier (which may be omitted to specifiy the `Any` type)
 * an identifer (which may be omitted to create an anonymous function)
 * an identifier list (which may be omitted if there are no parameters desired)
 * and finally either a group of statements or a single statement

An identifier list is a parentheses-enclosed list of identifiers. The list is separated by
a comma and/or whitespace. Each identifier optionally may be prefixed with a type specifier.
Each identifier may optionally be followed by an initializer to create a default value.

Plang functions automatically return the value of the last statement or statement group.
You may use the `return` keyword to return the value of an ealier statement.

To call a function, write its identifier followed by a list of arguments enclosed in
parentheses. The argument list is separated the same way as the identifier list. Arguments
may be any valid expression.

The `fn` statement returns a reference to the newly defined function.

#### Type-checking
Plang's type system allows a mixture of dynamic run-time type checking and static compile-time
type checking. You can choose which parts of your program are dynamically or statically type
checked by omitting or adding type annotations. This is called gradual typing.

Here is a brief demonstration of the concept. Let's consider a simple `add` function. With
no explicit type annotations, the function's return type and types of its parameters will
default to the `Any` type:

    > fn add(a, b) a + b; print(type(add));
     Function (Any, Any) -> Any

Plang will infer, at run-time, the types of its parameters and return value from the types
of the arguments passed to it and the value returned.

    > fn add(a, b) a + b; add(3, 4)
     7

But be careful. If a `String` gets passed to it, Plang will terminate its execution
with an undesirable run-time error:

    > fn add(a, b) a + b; add(3, "4")
     Error: cannot apply binary operator ADD (have types Number and String)

One way to resolve this is to apply the `Number()` type-conversion function to the
parameters inside the function body, creating a polymorphic function that can accept
any arguments that can be converted to `Number`:

    > fn add(a, b) Number(a) + Number(b); add(3, "4")
     7

On the other hand, if you desire explicit type checking on the parameters you can add a
type annotation before each parameter identifier:

    > fn add(Number a, Number b) a + b; print(type(add));
      Function (Number, Number) -> Any

Now Plang will throw a compile-time error if the types of the arguments do not match the
types specified for the parameters:

    > fn add(Number a, Number b) a + b; add(3, "4")
     Error: In function call for `add`, expected Number for parameter `b` but got String

This version of `add` returns `Any` and its return type will be inferred at run-time from
the value being returned.

Let's delve a bit into return type inference by considering the `filter` built-in function:

    > print(type(filter))
     Builtin (Function (Any) -> Boolean, Array) -> Array

It has two parameters and returns an `Array`. The first parameter is a `Function` that takes
one `Any` argument and returns a `Boolean` value. The second parameter is an `Array`.

Thanks to type inference, a concise anonymous function without type annotations can be passed
as the first argument:

    > filter(fn(a) a<4, [1,2,3,4,5])
     [1,2,3]

Because the `filter` function is statically typed to return a `Boolean`, Plang can perform
compile-time type checking. For example, if we pass it a function inferred to return a `Number`:

    > filter(fn(a) 4, [1, 2, 3, 4, 5])
     Error: in function call for `filter`, expected Function (Any) -> Boolean
       for parameter `func` but got Function (Any) -> Number

Let's return to the `add` function. To enable static type checking of the return value, you
can place a type annotation before the function identifier:

    > fn Number add(Number a, Number b) a + b; print(type(add))
     Function (Number, Number) -> Number

Now Plang will throw a compile-time error if `add` attempts to return a value that
is not a `Number`:

    > fn Number add(Number a, Number b) "42"; add(3, 4)
     Error: cannot return String from function declared to return Number

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

#### Built-in functions
Function | Parameters | Description
--- | --- | ---
print | `expr`, `end` = `"\n"` | Prints expression `expr` to standard output. The optional `end` parameter defaults to `"\n"`.
type | `expr` | Returns the type of an expression, as a string.
Null | `expr` | Converts the value of `expr` to a value of type `Null`
Boolean | `expr` | Converts the value of `expr` to a value of type `Boolean`
Number | `expr` | Converts the value of `expr` to a value of type `Number`
String | `expr` | Converts the value of `expr` to a value of type `String`
Array | `expr` | Converts the value of `expr` to a value of type `Array`
Map | `expr` | Converts the value of `expr` to a value of type `Map`
Function | `expr` | Converts the value of `expr` to a value of type `Function`
Builtin | `expr` | Converts the value of `expr` to a value of type `Builtin`

### Types
Currently implemented types are:

#### Null
     Null ::= "null"

The `Null` type signifies that there is no value.

#### Boolean
    Boolean ::= "true" | "false"

A `Boolean` is either true or false.

#### Number
    Number ::= ("-" | "+")? ("0" - "9")* "."? ("0" - "9")+

`Number`s are things like `-100`, `+4.20`, `2001`, `1e1`, `0x4a`, etc.

In Plang, the `Number` type is equivalent to a double-precision type.

#### String
    String         ::= ("'" StringContents? "'") | ('"' StringContents? '"')
    StringContents ::= TODO

A `String` is a sequence of characters enclosed in double or single quotes. There is
no difference between the quotes.

#### Array
    ArrayConstructor ::= "[" (Expression ","?)* "]"

An `Array` is a collection of values. Array elements can be any type.

See [examples/arrays_and_maps.pl](examples/arrays_and_maps.pl) for more details.

##### Creating and accessing arrays
Creating an array and accessing an element:

    > var array = ["red, "green", 3, 4]; array[1]
     "green"

#### Map
    MapConstructor ::= "{" ( (IDENT | String) ":" Expression )* "}"

A `Map` is a collection of key/value pairs. Map keys must be of type `String`. Map
values can be any type.

See [examples/arrays_and_maps.pl](examples/arrays_and_maps.pl) for more details.

##### Creating and accessing maps
Creating a map and accessing a key:

    > var player = { "name": "Grok", "health": 100, "iq": 75 }; player["iq"]
     75

Creating an empty map and then assigning a value to a key:

    > var map = {}; map["color"] = "blue"; $"The color is {map['color']}!"
     "The color is blue!"

Nested maps:

    > var a = {"x": {"y": 42}}; a["x"]["y"]
     42

    > var a = {}; a["x"] = {"y": 42}; a["x"]["y"]
     42

##### Exists
To check for existence of a map key, use the `exists` keyword. If the key exists then
`true` is yielded, otherwise `false`. Note that setting a map key to `null` does not
delete the key. See the [`delete`](#delete) keyword.

    > var map = { "a": 1, "b": 2 }; exists map["a"]
     true

##### Delete
To delete keys from a map, use the `delete` keyword. Setting a key to `null` does not
delete the key.

When used on a Map key, the `delete` keyword deletes the key and returns its value, or
`null` if no such key exists.

When used on a Map itself, the `delete` keyword deletes all keys in the map and returns
the empty map.

    > var map = { "a": 1, "b": 2 }; delete map["b"]; map
     { "a": 1 }

##### Function
The `Function` type identifies a Plang function. See [functions](#functions) for more information.

##### Builtin
The `Builtin` type identifies an internal built-in function. See [builtin-in functions](#built-in-functions) for more information.

#### Type conversion
Plang does not allow implicit conversion between types. You must convert a value explicitly
to a desired type.

To convert a value to a different type, pass the value as an argument to the function named
after the desired type. To cast `x` to a `Boolean`, write `Boolean(x)`.

Wrong:

    > var a = "45"; a + 1
     Error: cannot apply binary operator ADD (have types String and Number)

Right:

    > var a = "45"; Number(a) + 1
     46

The following type conversion functions may be used to convert to and from the types
listed in their respective tables. If a type is not listed in a table, it is an error
to perform the conversion.

##### Null()
From Type | With Value | Resulting Null Value
--- | --- | ---
Null | `null` | `null`
Boolean | any value | `null`
Number | any value | `null`
String | any value | `null`
Array | any value | `null`
Map | any value | `null`

##### Boolean()
From Type | With Value | Resulting Boolean Value
--- | --- | ---
Null | `null` | `false`
Boolean | any value | that value
Number | `0` | `false`
Number | not `0` | `true`
String | `""` | `false`
String | not `""` | `true`

##### Number()
From Type | With Value | Resulting Number Value
--- | --- | ---
Null | `null` | `0`
Boolean | `true` | `1`
Boolean | `false` | `0`
Number | any value | that value
String | `""` | `0`
String | `"X"` | if `"X"` begins with a Number then its value, otherwise `0`

##### String()
From Type | With Value | Resulting String Value
--- | --- | ---
Null | null | `""`
Boolean | `true` | `"true"`
Boolean | `false` | `"false"`
Number | any value | that value as a String
String | any value | that value
Array | any value | A String containing a constructor of that Array
Map | any value | A String containing a constructor of that Map

##### Array()
From Type | With Value | Resulting Array Value
--- | --- | ---
String | A String containing an [Array constructor](#array) | the constructed Array
Array | any value | that value

##### Map()
From Type | With Value | Resulting Map Value
--- | --- | ---
String | A String containing a [Map constructor](#map) | the constructed Map
Map | any value | that value

##### Function()
It is an error to convert anything to or from `Function`.

##### Builtin()
It is an error to convert anything to or from `Builtin`.

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
To concatenate two strings, use the `.` operator. But consider using [interpolation](#interpolation) instead.

    > var a = "Plang"; var b = "Rocks!"; a . " " . b
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

