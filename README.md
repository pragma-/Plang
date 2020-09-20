# Plang
Plang is a pragmatic scripting language written in Perl.

Why? Because I need a small, yet useful, scripting language I can embed into
some Perl scripts I have; notably [PBot](https://github.com/pragma-/pbot), an IRC bot that I've been tinkering with
for quite a while.

I want to be able to allow text from external sources to be safely interpreted
in a sandbox environment with access to selectively exposed Perl subroutines,
with full control over how deeply functions are allowed to recurse, et cetera.

Plang is in early development stage. There will be bugs. There will be abrupt design changes.

Here is a short overview of Plang. For more details see [the documentation](doc/).

## Table of contents
<details><summary>Click to show Table of Contents</summary>

<!-- md-toc-begin -->
* [Gradually typed](#gradually-typed)
  * [Optional type annotations](#optional-type-annotations)
  * [Explicit type conversion](#explicit-type-conversion)
  * [Type unions](#type-unions)
  * [Simple types](#simple-types)
* [Operators](#operators)
* [Keywords](#keywords)
* [Statements and Statement Groups](#statements-and-statement-groups)
  * [if/then/else expression](#ifthenelse-expression)
  * [var expression](#var-expression)
  * [while/next/last instruction](#whilenextlast-instruction)
* [Introspection](#introspection)
  * [type() function](#type-function)
  * [whatis() function](#whatis-function)
* [Functions](#functions)
  * [Optional type annotations](#optional-type-annotations-1)
  * [Anonymous functions](#anonymous-functions)
  * [Default arguments](#default-arguments)
  * [Named arguments](#named-arguments)
  * [Closures](#closures)
  * [Currying](#currying)
* [Variables](#variables)
* [Strings](#strings)
  * [Relational operations](#relational-operations)
  * [Interpolation](#interpolation)
  * [Concatenation](#concatenation)
  * [Substring search](#substring-search)
  * [Indexing](#indexing)
  * [Substring](#substring)
  * [Regular expressions](#regular-expressions)
* [Arrays](#arrays)
  * [map](#map)
  * [filter](#filter)
* [Maps](#maps)
* [JSON compatibility/serialization](#json-compatibilityserialization)
* [Embeddable](#embeddable)
* [More examples](#more-examples)
<!-- md-toc-end -->

</details>

## Gradually typed
Plang is gradually typed with optional nominal type annotations.

[Read more.](doc/README.md#type-checking)

### Optional type annotations
Plang's type system allows type annotations to be omitted. When type annotations are omitted,
the type will default to `Any`. The `Any` type tells Plang to infer the actual type from the
value provided.

[Read more.](doc/README.md#type-checking)

### Explicit type conversion
For stricter type-safety, Plang does not allow implicit conversion between types.
You must convert a value explicitly to a desired type.

[Read more.](doc/README.md#type-conversion)

### Type unions
Suppose you want to say that a variable, function parameter or function return will be
either type X or type Y? You can do this with a type union.

[Read more.](doc/README.md#type-unions)

### Simple types
Plang's types are simple and straightforward.

<details><summary>Click to show type table</summary>

Type | Subtypes
--- | ---
[Any](doc/README.md#Any) | All types
[Null](doc/README.md#Null) | -
[Boolean](doc/README.md#Boolean) | -
[Number](doc/README.md#Number) | [Integer](doc/README.md#Integer), [Real](doc/README.md#Real)
[Integer](doc/README.md#Integer) | -
[Real](doc/README.md#Real) | [Integer](doc/README.md#Integer)
[String](doc/README.md#String) | -
[Array](doc/README.md#Array) | -
[Map](doc/README.md#Map) | -
[Function](doc/README.md#Function) | [Builtin](doc/README.md#Builtin)
[Builtin](doc/README.md#Builtin) | -

</details>

## Operators
These are the operators implemented so far, from highest to lowest precedence.

<details><summary>Click to show operator table</summary>

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

</details>

## Keywords
Keywords are reserved identifiers that have a special meaning to Plang.

<details><summary>Click to show keywords table</summary>

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

</details>

## Statements and Statement Groups
A statement is a single instruction or expression. A statement group is multiple statements enclosed in curly-braces.

If a statement is an instruction, it instructs Plang to do something. If a statement is an expression, it yields a value.

### if/then/else expression
    > if true then 1 else 2
     1

    > if false then 1 else 2
     2

### var expression
    > var a = 3.14
     3.14

### while/next/last instruction
    > var i = 0; while (++i <= 5) print(i, end=" "); print("");
     1 2 3 4 5

The `next` keyword can be used to immediately jump to the next iteration of the loop.

The `last` keyword can be used to immediately exit the loop.

## Introspection
### type() function
The `type` function returns the type of an expression or function, as a string.

For functions, it returns strictly the type signature. If you're interested in function parameter
identifiers and default arguments, see the [`whatis`](#whatis-function) builtin function.

    > type(3.14)
     "Real"

    > var a = "hello"; type(a)
     "String"

    > type(print)
     "Builtin (Any, String) -> Null"

    > type(filter)
     "Builtin (Function (Any) -> Boolean, Array) -> Array"

### whatis() function
The `whatis` function is identical to the [`type`](#type-function) function, but with the
addition of function parameter identifiers and function default arguments.

    > whatis(print)
     "Builtin (expr: Any, end: String = \"\\n\") -> Null"

    > print(whatis(print)) # use `print` to avoid string escaping
     Builtin (expr: Any, end: String = "\n") -> Null

    > whatis(filter)
     "Builtin (func: Function (Any) -> Boolean, list: Array) -> Array"

## Functions
A function definition is created by using the `fn` keyword.

    > fn add(a, b) a + b; add(2, 3)
     5

### Optional type annotations
Type annotations may be provided for compile-time type-checking.

    > fn add(a: Number, b: Number) -> Number { a + b }; add(2, "hi")
     Error: in function call for `add`, expected Number for parameter `b` but got String

### Anonymous functions
Here are some ways to define and call an anonymous function:

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

[Read more.](doc/README.md#Functions)

### Default arguments
In a function definition, parameters may optionally be followed by an initializer. This is
called a default argument. Parameters that have a default argument may be omitted from the
function call, and will be replaced with the value of the default argument.

    > fn add(a, b = 10) a + b; add(5);
     15

### Named arguments
In a function call, arguments can be passed positionally or by name. Arguments that are
passed by name are called named arguments.

Consider a function definition that has many default arguments:

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

### Closures
The following snippet:

    fn counter { var i = 0; fn ++i }
    var count1 = counter()
    var count2 = counter()
    $"{count1()} {count1()} {count1()} {count2()} {count1()} {count2()}"

produces the output:

    1 2 3 1 4 2

### Currying
    > var a = fn (x) fn (y) x + y; a(3)(4)
     7

## Variables
Variables are explicitly declared with the `var` keyword. Without explicit
type annotations, the variable will infer its type from the value assigned.

    > var a = 5; print(type(a)); a
     Integer
     5

    > var a = "hello"; print(type(a)); a
     String
     "hello"

However, once a variable has been given a value, the variable may not be assigned a value of
a different type. This enforces the consistency of the variable's type.

    > var a = "hi"; a = 5
     Error: cannot assign to `a` a value of type Integer (expected String)

A type annotation may be provided to enable more strict compile-time type-checking.

    > var a: String = 5
     Error: cannot initialize `a` with value of type Integer (expected String)

Attempting to use a variable that has not been declared will produce a compile-time error.

    > var a = 5; a + b
     Error: `b` not declared.

Attempting to use a variable that has not yet been assigned a value will produce
a compile-time error.

    > var a = 5; var b; a + b
     Error: `b` not defined.

## Strings
### Relational operations
The relational operators behave as expected. There is no need to compare against `-1`, `0` or `1`.

    > "blue" < "red"
     true

### Interpolation
When prefixed with a dollar-sign, a `String` will interpolate any brace-enclosed Plang code.

    > var a = 42; $"hello {a + 1} world"
     "hello 43 world"

### Concatenation
To concatenate two strings, use the `^^` operator. But consider using [interpolation](#interpolation) instead.

    > var a = "Plang"; var b = "Rocks!"; a ^^ " " ^^ b
     "Plang Rocks!"

### Substring search
To find the index of a substring within a string, use the `~` operator.

    > "Hello world!" ~ "world"
     6

### Indexing
To get a positional character from a string, you can use postfix `[]` access notation.

    > "Hello!"[0]
     "H"

You can use negative numbers to start from the end.

    > "Hello!"[-2]
     "o"

You can assign to the above notation to replace the character instead.

    > "Hello!"[0] = "Jee"
     "Jeeello!"

### Substring
To extract a substring from a string, you can use the `..` range operator inside
postfix `[]` access notation.

    > "Hello!"[1..4]
     "ello"

You can assign to the above notation to replace the substring instead.

    > "Good-bye!"[5..7] = "night"
     "Good-night!"

### Regular expressions
You may use regular expressions on strings with the `~=` operator.

## Arrays
Arrays are lists of values. The types of each value need not be the same.

    > var array = ["red, "green", 3, 4]; array[1]
     "green"

### map
The `map` function applies a function to each element of an array, updating that
element in-place with the result of the applied function.

    > map(fn(x) x*10, [1,2,3,4,5])
     [10,20,30,40,50]

### filter
The `filter` function applies a function over an array's elements and constructs
a new array whose elements meet the criteria of the applied function.

    > filter(fn(x) x <= 3, [1,2,3,4,5])
     [1,2,3]

    > filter(fn(x) x['type'] == 'dog', [{'type': 'dog', 'name': 'Woofers'}, {'type': 'cat', 'name': 'Whiskers'}])
     [{'type': 'dog', 'name': 'Woofers'}]

## Maps
Maps are key/value pairs. There are two syntactical ways to set/access map keys. The first way
is to use a value of type `String` enclosed in square brackets.

    > var x = {}; x["y"] = 42; x
     {"y": 42}

The second way is to use the `.` operator followed by a bareword value.

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

To check for existence of a map key, use the `exists` keyword.

    > var m = { "a": 1, "b": 2 }; exists m["a"]
     true

To delete keys from a map, use the `delete` keyword.

When used on a Map key, the `delete` keyword deletes the key and returns its value, or
`null` if no such key exists.

When used on a Map itself, the `delete` keyword deletes all keys in the map and returns
the empty map.

    > var m = { "a": 1, "b": 2 }; delete m["b"]; m
     { "a": 1 }

    > var m = { "a": 1, "b": 2 }; delete m; m
     {}

## JSON compatibility/serialization
Plang's Array and Map syntax is designed to be compatible with JSON for easy and convenient serialization of
Plang data structures for data-exchange and interoperability.

[Read more.](doc/README.md#json-compatibilityserialization)

## Embeddable
Plang is designed to be embedded into larger Perl applications.

## More examples
[Check out some more examples!](examples/)

