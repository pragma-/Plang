# Plang
Plang is in early development stage. There will be bugs. There will be abrupt design changes.

This README describes what is implemented so far.

<details><summary>Click to show table of contents</summary>

<!-- md-toc-begin -->
* [Project structure](#project-structure)
* [Running Plang](#running-plang)
  * [DEBUG environment variable](#debug-environment-variable)
  * [REPL](#repl)
* [Embedding Plang](#embedding-plang)
* [Running the Unit Tests](#running-the-unit-tests)
* [Example Plang scripts](#example-plang-scripts)
* [The Plang Language (so far)](#the-plang-language-so-far)
    * [Operators](#operators)
    * [Truthiness](#truthiness)
  * [Identifiers](#identifiers)
    * [Keywords](#keywords)
  * [Variables](#variables)
  * [Functions](#functions)
    * [Uniform function call syntax](#uniform-function-call-syntax)
    * [Optional type annotations](#optional-type-annotations)
    * [Default arguments](#default-arguments)
    * [Named arguments](#named-arguments)
    * [Anonymous functions](#anonymous-functions)
    * [Closures](#closures)
    * [Currying](#currying)
    * [Lazy evaluation](#lazy-evaluation)
  * [Built-in functions](#built-in-functions)
    * [Input/Output](#inputoutput)
      * [print](#print)
    * [Introspection](#introspection)
      * [typeof](#typeof)
      * [whatis](#whatis)
    * [Data and structures](#data-and-structures)
      * [length](#length)
      * [map](#map)
      * [filter](#filter)
      * [Type conversion functions](#type-conversion-functions)
  * [Scoping](#scoping)
  * [Expressions and ExpressionGroups](#expressions-and-expressiongroups)
    * [if/then/else](#ifthenelse)
    * [while/next/last](#whilenextlast)
    * [try/catch/throw](#trycatchthrow)
  * [Type-checking](#type-checking)
    * [Optional type annotations](#optional-type-annotations-1)
    * [Type narrowing during inference](#type-narrowing-during-inference)
    * [Type conversion](#type-conversion)
    * [Type unions](#type-unions)
    * [Defining new types](#defining-new-types)
      * [Default values in new types](#default-values-in-new-types)
      * [Inferring type from default values](#inferring-type-from-default-values)
    * [Types](#types)
      * [Any](#any)
      * [Null](#null)
      * [Boolean](#boolean)
      * [Number](#number)
      * [Integer](#integer)
      * [Real](#real)
      * [String](#string)
      * [Array](#array)
      * [Map](#map-1)
      * [Function](#function)
      * [Builtin](#builtin)
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
    * [map](#map-2)
    * [filter](#filter-1)
  * [Map operations](#map-operations)
    * [Creating and accessing maps](#creating-and-accessing-maps)
    * [keys](#keys)
    * [values](#values)
    * [exists](#exists)
    * [delete](#delete)
  * [Modules](#modules)
    * [qualified identifiers](#qualified-identifiers)
    * [module](#module)
    * [import](#import)
  * [Plang EBNF Grammar](#plang-ebnf-grammar)
<!-- md-toc-end -->

</details>

## Project structure
Path | Description
--- | ---
[`bin/plang`](../bin/plang) | Plang executable entry point. Parses and interprets Plang programs from STDIN or command-line arguments.
[`bin/plang_builtin`](../bin/plang_builtin) | Simple demonstration of creating user-defined built-in functions.
[`bin/plang_repl`](../bin/plang_repl) | Read-evaluate-print-loop with persistent environment. Use this to play with Plang.
[`bin/runtests`](../bin/runtests) | Verifies that Plang is working correctly by running the tests in the [`test`](../test) directory.
[`doc/`](../doc/) | Plang documentation.
[`examples/`](../examples) | Example Plang programs that demonstrate Plang's syntax and semantics.
[`lib/Plang/Interpreter.pm`](../lib/Plang/Interpreter.pm) | Plang library entry point. Use `Plang::Interpreter` to embed Plang into your Perl scripts.
[`lib/Plang/Lexer.pm`](../lib/Plang/Lexer.pm) | Generic abstract lexer class that accepts a list of regular expressions to lex into a stream of tokens.
[`lib/Plang/ModuleImporter.pm`](../lib/Plang/ModuleImporter.pm) | Imports a Plang module by walking its AST to add variables, functions and type definitions.
[`lib/Plang/Modules.pm`](../lib/Plang/Modules.pm) | Loads a Plang module by finding and parsing its file into an AST, then passing the AST to ModuleImporter.
[`lib/Plang/Parser.pm`](../lib/Plang/Parser.pm) | Generic abstract backtracking parser class that accepts a list of parse rules.
[`lib/Plang/ParseRules.pm`](../lib/Plang/ParseRules.pm) | Recursive-descent rules to parse a stream of tokens into an AST.
[`lib/Plang/Types.pm`](../lib/Plang/Types.pm) | Plang's simple yet evolving and growing type system.
[`lib/Plang/AST/Dumper.pm`](../lib/Plang/AST/Dumper.pm) | Pretty-prints Plang's AST as Lisp-like text.
[`lib/Plang/AST/Validator.pm`](../lib/Plang/AST/Validator.pm) | Compile-time type-checking and semantic validation. Does some syntax desugaring.
[`lib/Plang/AST/Walker.pm`](../lib/Plang/AST/Walker.pm) | Base class to walk a Plang AST. Overload its methods to perform actions on nodes.
[`lib/Plang/Compiler/ByteCode.pm`](../lib/Plang/Compiler/ByteCode.pm) | Placeholder for future plans to compile Plang AST to bytecode instructions.
[`lib/Plang/Compiler/C.pm`](../lib/Plang/Compiler/C.pm) | Placeholder for future plans to compile Plang AST to C source code.
[`lib/Plang/Constants/`](../lib/Plang/Constants/) | Integer constants identifying various tokens, keywords and instructions.
[`lib/Plang/Interpreter/AST.pm`](../lib/Plang/Interpreter/AST.pm) | At this early stage, Plang is a simple AST interpreter.
[`lib/Plang/Interpreter/ByteCode.pm`](../lib/Plang/Interpreter/ByteCode.pm) | Placeholder for future plans to interpret bytecode instructions.
[`test/`](../test) | Plang test programs to verify functionality and detect bugs.

## Running Plang
You may use the [`plang`](../bin/plang) executable to interpret Plang scripts.

Plang automatically prints the value of the final expression in the program. To prevent this,
use the `null` keyword (or construct any expression that evaluates to `null`) as the final expression.

    Usage: plang ([code] | STDIN)

To interpret a Plang file:

    $ plang < file

To interpret a string of Plang code from command-line arguments:

    $ plang 'fn add(a, b) a + b; add(3, 7)'
      10

To interpret directly from STDIN:

    $ echo '2*3' | plang
      6

    $ plang <<< '4+5'
      9

    $ plang
        print("Hello, world!")
        ^D
      Hello, world!

### DEBUG environment variable
You can set the `DEBUG` environment variable to enable debugging output.

The value is a comma-separated list of tags, or `ALL` for everything.

Available `DEBUG` tags are: `ERRORS`, `TOKEN`, `PARSER`, `BACKTRACK`, `AST`, `TYPES`, `EXPR`, `EVAL`, `RESULT`, `OPERS`, `VARS`, `FUNCS`.

    $ DEBUG=PARSER,AST ./plang '12 + 23'  # debug messages only for tags `PARSER` and `AST`
        +-> Trying Program: Expression*
        |  +-> Trying Expression (prec 0)
        |  |  Looking for INT
        |  |  Got it (12)
        |  |  Looking for PLUS
        |  |  Got it (+)
        |  |  +-> Trying Expression (prec 12)
        |  |  |  Looking for INT
        |  |  |  Got it (23)
        |  |  <- Advanced Expression (prec 12)
        |  <- Advanced Expression (prec 0)
        <- Advanced Program: Expression*
        AST: [[ADD,[LITERAL,['TYPE','Integer'],12,{'col' => 1,'line' => 1}],[LITERAL,['TYPE','Integer'],23,{'col' => 5,'line' => 1}],{'col' => 3,'line' => 1}]];
        35

<!-- -->
    $ DEBUG=ALL ./plang '1 + 2'         # all debug messages (output too verbose to show here)

### REPL
The [`plang_repl`](../bin/plang_repl) script can be used to start a REPL session.
It is recommended to use the `rlwrap` command-line utility for command history.

    $ rlwrap bin/plang_repl
     Plang REPL. Type `.help` for help. `.quit` to exit.
     > "Hi!"
      [String] Hi!
     > var a = 42
      [Integer] 42
     > a + 10
      [Integer] 52

## Embedding Plang
Plang is designed to be embedded into larger Perl applications.

I will get around to documenting this soon. In the meantime, take a look at [this unit-test script](../bin/runtests) and
 [PBot's Plang plugin](https://github.com/pragma-/pbot/blob/master/lib/PBot/Plugin/Plang.pm) for
general idea of how to go about it.

## Running the Unit Tests
There are a number of unit tests in the [`test`](../test/) directory that may be invoked
by the [`runtests`](../bin/runtests) script.

The `runtests` script may be invoked without arguments to run all the tests. Alternatively, you
can specify which tests to run by passing a list of file paths.

```
    $ ./bin/runtests test/operators.pt test/closures.pt
    Running 2 test files: ..........
    Pass: 10; Fail: 0
```

A test failure looks like this:

```
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
```

## Example Plang scripts
[Check out some examples!](../examples/)

## The Plang Language (so far)

Plang is a statically-typed expression-oriented language with optional type annotations.
Everything in Plang evaluates to a value that can be used in an expression.

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
5   | ^^=  | String concat assignment | Infix (right-to-left)
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

### Identifiers
    Identifier ::=  ("_" | Letter)  {"_" | Letter | Digit}*
    Letter     ::=  "a" .. "z" | "A" .. "Z"
    Digit      ::=  "0" .. "9"

An identifier is a sequence of characters beginning with an underscore or a letter, optionally followed
by additional underscores, letters or digits.

#### Keywords
Keywords are reserved identifiers that have a special meaning to Plang.

Keyword | Description
--- | ---
module | module declaration
import | import a module
as | provides an alias for `import`, e.g. `import x as y`
var | variable declaration
fn | function definition
return | return value from function
true | a Boolean with a true value
false | a Boolean with a false value
null | a Null with a null value
if | conditional if expression
then | then branch of a conditional if expression
else | else branch of a conditional if expression
while | loop while a condition is true
last | break out of the loop
next | jump to the next iteration of the loop
keys | create array of a Map's keys
values | create array of a Map's values
exists | test if a key exists in a Map
delete | deletes a key from a Map
try | try an expression with exception handling
catch | catch an exception from a tried expression
throw | throw an exception
type | type declaration

### Variables
    VariableDeclaration ::= "var" Identifier [":" Type] [Initializer]
    Initializer         ::= "=" Expression

The `var` expression evaluates to the value of its initializer. When type annotations are omitted,
the variable's type will be inferred from its initializer value.

    > var a = 5
     [Integer] 5

    > var a = "hello"
     [String] "hello"

A type annotation may be provided to enable strict compile-time type-checking.

    > var a: String = 5
     Validator error: cannot initialize `a` with value of type Integer (expected String)

Attempting to use a variable that has not been declared will produce a compile-time error.

    > var a = 5; a + b
     Validator error: `b` not declared.

Variables that have not yet been assigned a value will produce a compile-time error.

    > var a = 5; var b; a + b
     Validator error: `b` not defined.

### Functions
    FunctionDefinition  ::= "fn" [Identifier] [IdentifierList] ["->" Type] Expression
    IdentifierList      ::= "(" {Identifier [":" Type] [Initializer] [","]}* ")"

A function definition is created by using the `fn` keyword followed by:
 * an identifer, which may be omitted to create an anonymous function
 * an identifier list, which may be omitted if there are no parameters desired
 * a "->" followed by a type, which may be omitted to infer the return type
 * and finally an expression (which can also be a group of expressions)

An identifier list is a parentheses-enclosed list of identifiers. The list is separated by
a comma and/or whitespace. Each identifier optionally may be followed by a colon and a type
description. Each identifier may optionally be followed by an initializer to create a default value.

Plang functions automatically return the value of its expression. When using a group of expressions,
the `return` keyword may be used to return the value of any expression within the group.

To call a function, write its identifier followed by a list of arguments enclosed in
parentheses.

The `fn` expression evaluates to a reference to the newly defined function.

#### Uniform function call syntax
Functions may be invoked using uniform call syntax with dot notation. This
means that `x.f()` will be converted into `f(x)` during compilation. For
example, `[2,4,8].map(fn (x) x * 2)` will be converted into
`map([2,4,8], fn (x) x * 2)`. This allows better ergonomics and readability
of composed functions. Instead of writing `add(mul(2, 4), 8)` we can write
`2.mul(4).add(8)`.

#### Optional type annotations
Function definitions may optionally include type annotations for the function signature.
Compile-time errors will be generated if the types of values provided to or returned from
the function do not match the annotations.

Without a type annotation, Plang will attempt to infer the types from the values being supplied
or returned. If Plang cannot infer the type then the `Any` type will be used, effectively disabling
type-checking for the parameter or return value.

See [Optional type annotations](#optional-type-annotations-1) for more information and examples.

#### Default arguments
In a function definition, parameters may optionally be followed by an initializer. This is
called a default argument. Parameters that have a default argument may be omitted from the
function call, and will be replaced with the value of the default argument.

    > fn add(a, b = 10) a + b; add(5);
     15

#### Named arguments
In a function call, arguments can be passed positionally or by name. Arguments that are
passed by name are called named arguments.

Named arguments may be passed only to parameters that have a default argument. All
parameters without a default arguments are strictly positional parameters. All positional
arguments must be passed prior to passing a named argument. If a named argument is
passed, all subsequent arguments must also be named.

Consider a function that has many default arguments:

    fn new_creature(name = "a creature", health = 100, armor = 50, damage = 10) ...

You can memorize the order of arguments, which can be error-prone and confusing:

    new_creature("a troll", 125, 75, 25)

Or you can used named arguments, which not only helps readability but also lets you specify
arguments in any order:

    new_creature(damage = 25, health = 125, armor = 75, name = "a troll")

Another advantage of named arguments is that you can simply specify the arguments you care
about and let the default arguments do their job for the rest:

    new_creature(armor = 200, damage = 100)

#### Anonymous functions
Here are some ways to define an anonymous function:

By omitting the identifier:

    > var adder = fn (a, b) a + b; adder(10, 20)
     30

If it takes no arguments, the parameter list can be omitted too:

    > var greeter = fn { print("Hello!") }; greeter()
     Hello!

Anonymous functions can be invoked directly:

    > (fn (a, b) a + b)(1, 2)
     3

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

### Built-in functions
These are the provided built-in functions. You can define additional built-in functions
through Plang's internal API. See [embedding Plang](#embedding-plang) for more information.

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
##### typeof
The `typeof` function returns the type of an expression, as a string. For functions,
it returns strictly the type signature. If you're interested in function parameter
identifiers and default arguments, see the [`whatis`](#whatis) builtin function.

Its signature is: `Builtin (expr: Any) -> String`

    > typeof(3.14)
     "Real"

    > typeof([1, 2, 3])
     "[Integer]"

    > var a = "hello"; typeof(a)
     "String"

    > typeof(print)
     "Builtin (Any, String) -> Null"

    > typeof(filter)
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

    > length({"a" = 1, "b" = 2, "c" = 3})
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

    > filter(fn(x) x['type'] == 'dog', [{'type' = 'dog', 'name' = 'Woofers'}, {'type' = 'cat', 'name' = 'Whiskers'}])
     [{'type' = 'dog', 'name' = 'Woofers'}]

##### Type conversion functions
See [Types](#types).

### Scoping
Plang is lexically scoped. Expression groups introduce a new lexical scope. Identifiers, variables and functions
created within a scope are destroyed when the scope ends. Identifiers within an inner scope may override identifers
of the same name found in outer scopes.

    { # outer scope
       var a = 5

       { # new inner scope
          var a = 10 # new instance of `a` shadows outer `a`
          var b = 15

          a + b  # 25
       } # end inner scope, inner `a` and `b` no longer exist

       a  # 5
    } # end outer scope, `a` no longer exists

### Expressions and ExpressionGroups
    Expression      ::=  ExpressionGroup
                      | IfExpression
                      | WhileExpression
                      | ? et cetera ?
                      | [Terminator]
    ExpressionGroup ::=  "{" Expression* "}"
    Terminator      ::=  ";"

A single expression evaluates to a value. In the place of any expression, an expression group may be used.

An expression group is multiple expressions enclosed in a pair of curly-braces. An expression groups evaluates to the value of its final expression.

Expressions can optionally be explicitly terminated by a semi-colon.

#### if/then/else
    IfExpression ::= "if" Expression "then" Expression "else" Expression

If the expression after `if` is [truthy](#truthiness) then the expression after `then` will be
evaluated otherwise the expression after `else` will be evaluated.

The value of the `if` expression is the value of the expression of the branch that was evaluated.

    > if true then 1 else 2
     1

    > if false then 1 else 2
     2

#### while/next/last
    WhileExpression ::= "while" "(" Expression ")" Expression

While the expression in parenthesis is [truthy](#truthiness) the expression in the while body will be evaluated.

The value of the `while` expression is the value of the expression evaluated within the loop.

The `next` keyword can be used to immediately jump to the next iteration of the loop.

The `last <expression>` keyword can be used to immediately exit the loop, with a value.

    > var i = 0; while (++i <= 5) print(i, end=" "); print("");
     1 2 3 4 5

See [`print`](#print) for information about the `print` function.

#### try/catch/throw
    Try   ::= "try" Expression {"catch" ["(" Expression ")"] Expression}+
    Throw ::= "throw" Expression

At this early stage, Plang supports simplified String-based exceptions. Eventually Plang will
support properly typed exceptions.

Use `try <expression>` to evaluate an expression with exception handling.

Use `catch [exception] <expression> ` to handle an exception. `[exception]` is an optional
parenthesized String denoting the name of the exception to catch. When `[exception]` is
omitted, the `catch` will act as a default handler for any exception.

All `catch` expressions are evaluated in a new lexical scope. A special variable named `e` is
implicitly declared in this new scope, defined to be the value of the caught exception.

Use `throw <exception>` to trigger an exception. `<exception>` is a required String denoting
the name of the exception to throw.

    > try
        1/0
      catch
        print("Caught {e}")

    Caught Illegal division by zero
<!-- -->
    > try
        throw "bar"
      catch ("foo")
        print($"Caught {e} in foo handler")
      catch ("bar")
        print($"Caught {e} in bar handler")
      catch
        print($"Caught some other exception: {e}")

    Caught bar in bar handler
<!-- -->
    > try
        throw "foobar"
      catch ("foo")
        print($"Caught {e} in foo handler")
      catch ("bar")
        print($"Caught {e} in bar handler")
      catch
        print($"Caught some other exception: {e}")

    Caught some other exception: foobar

### Type-checking
Plang is gradually typed with optional nominal type annotations.

#### Optional type annotations
Plang's type system allows type annotations to be omitted. When type annotations are omitted,
Plang will attempt to infer the types from the values. If Plang cannot infer the types, the
`Any` type will be used, which effectively disables type-checking for that object.

Let's consider a simple `add` function without type annotations:

    > fn add(a, b) a + b; print(typeof(add));
     Function (Any, Any) -> Number

Because the `+` operator expects types of `Number`, Plang can infer the return type. Since
`a` and `b` are of type `Any`, any value may be passed to the function. As long as the values
are sub-types of `Number`, the function will be happy:

    > fn add(a, b) a + b; add(3, 4)
     7

But be careful. If a `String` gets passed to it, Plang will terminate its execution
with an undesirable run-time error:

    > fn add(a, b) a + b; add(3, "4")
     Run-time error: cannot apply binary operator ADD (have types Integer and String)

The `Real()` type-conversion function can be applied to the parameters, inside the function
body, to create a semi-polymorphic function that can accept any argument that can be converted
to `Real`:

    > fn add(a, b) Real(a) + Real(b); add(3, "4")
     7

Unfortunately, the above will still produce a run-time error if something that cannot
be converted to `Real` is passed. Wouldn't compile-time error messages be better? Enter
type annotations!

    > fn add(a: Real, b: Real) a + b; print(typeof(add));
      Function (Real, Real) -> Real

Now Plang will throw a compile-time error if the types of the arguments do not match the
types specified for the parameters:

    > fn add(a: Real, b: Real) a + b; add(3, "yellow")
     Validator error: In function call for `add`, expected Real for parameter `b` but got String

In the follow example, the function `f` is annotated to return `Integer`, but whoops:

    > fn f(x) -> Integer "strawberry"
     Validator error: in definition of function `f`: cannot return value of type String from function declared to return type Integer

That was a silly example. Let's consider the built-in `filter` function:

    > print(typeof(filter))
     Builtin (Function (Any) -> Boolean, Array) -> Array

It has two parameters and returns an `Array`. The first parameter is a `Function` that takes
one `Any` argument and returns a `Boolean` value. The second parameter is an `Array`.

Here's how it works. The `Function` parameter is applied to each element of the `Array`
parameter; if it returns a `true` value then that element will be added to the `Array`
returned from the `filter` function. Like so:

    > filter(fn(a) a<4, [1,2,3,4,5])
     [1,2,3]

If a function that returns an `Integer` is passed instead, a helpful compile-time type error is produced:

    > filter(fn(a) 4, [1,2,3,4,5])
     Validator error: in function call for `filter`, expected Function (Any) -> Boolean
       for parameter `func` but got Function (Any) -> Integer

Had this been allowed to compile, the `4`, being non-zero, would have been interpreted as a `true` value on
every element of the array. Corrected:

    > filter(fn(a) a==4, [1,2,3,4,5])
     4

#### Type narrowing during inference
To enforce the consistency of values assigned to the variable during its lifetime,
variables declared as `Any` will be narrowed to the type of the value initially assigned.

For example, a variable of type `Any` initialized to `true` will have its type narrowed
to `Boolean`:

    > var a = true; typeof(a)
     "Boolean"

It will then be a compile-time type error to assign a value of any other type to it.

    > var a = true; a = "hello"
     Validator error: cannot assign to `a` a value of type String (expected Boolean)

#### Type conversion
For stricter type-safety, Plang does not allow implicit conversion between types.
You must convert a value explicitly to a desired type.

To convert a value to a different type, pass the value as an argument to the
function named after the desired type. To convert `x` to a `Boolean`, write `Boolean(x)`.

Wrong:

    > var a = "45"; a + 1
     Validator error: cannot apply binary operator ADD (have types String and Integer)

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

#### Defining new types
    TypeDefinition ::= "type" Identifier [":" Type] [Initializer]

Use the `type` keyword to define new types.

To define a `Port` type that is an Integer:

```
    type Port : Integer
```

To define a `Person` type that is a Map with two properties:

```
    type Person : {
        "name" : String,
        "age"  : Integer
     }
```

Then you can use it any place you'd use a type annotation. For instance, instead of writing

    var x: {"name": String, "age": Integer} = {"name" = "John Doe", "age" = 18}

you can more concisely write

    var x: Person = {"name" = "John Doe", "age" = 18}

##### Default values in new types
You can optionally set default values in new types.

```
    type Port : Integer = 80
    var x : Port;
    print(x)  # prints 80
```

```
    type Person : {
        "name" : String
        "age"  : Integer
    } = {
        "name" = "John Doe"
        "age"  = 18
    }
```

New variables of type `Person` will be initialized with the default values. See
the next section for a much more concise way to write the `Person` type by using
type inference.

##### Inferring type from default values
If you use a default value, you can omit the type. Plang will infer the type from the default value.

```
    type Port = 80
```

```
    type Person = {
       "name" = "John Doe",
       "age"  = 18
    }
```

Note that here we use `type Person = { ... }` to set default values instead of `type Person : { ... }`
to define types.

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
[Map](#map-1) | -
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
    HexLiteral     ::= "0" ("x" | "X") {Digit | "a" - "f" | "A" - "F"}+
    OctalLiteral   ::= "0" {"0" - "9"}+
    IntegerLiteral ::= {"0" - "9"}+

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
                        "." Digit* ( "e" | "E" ) [ "+" | "-" ] Digit+
                       | "." Digit+
                       | ( "e" | "E" ) [ "+" | "-" ] Digit+
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
    String         ::= ("'" [StringContents] "'") | ('"' [StringContents] '"')
    StringContents ::= ? sequence of bytes/characters ?

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
    ArrayConstructor ::= "[" {Expression [","]}* "]"

An `Array` is a collection of values. Array elements can be any type.

For more details see:

* [Array operations](#array-operations)
* [examples/arrays_and_maps.plang](../examples/arrays_and_maps.plang)

The `Array()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Array Value
--- | --- | ---
String | A String containing an [Array constructor](#array) | the constructed Array

##### Map
    MapConstructor ::= "{" {(IDENT | String) "=" Expression}* "}"

A `Map` is a collection of key/value pairs. Map keys must be of type `String`. Map
values can be any type.

For more details see:

* [Map operations](#map-operations)
* [examples/arrays_and_maps.plang](../examples/arrays_and_maps.plang)

The `Map()` type conversion function can be used to convert the following:

From Type | With Value | Resulting Map Value
--- | --- | ---
String | A String containing a [Map constructor](#map-1) | the constructed Map

##### Function
The `Function` type identifies a normal function defined with the `fn` keyword. See [functions](#functions) for more information.

##### Builtin
The `Builtin` type identifies an internal built-in function. See [built-in functions](#built-in-functions) for more information.

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
Coming soon. You may use regular expressions on strings with the `~=` operator.

### Array operations
#### Creating and accessing arrays
Creating an array and accessing an element:

    > var array = ["red, "green", 3, 4]; array[1]
     "green"

Use a type annotation to constrain the type of elements:

    > var array: [Integer] = [1, 2, "hi"]
     Validator error: cannot initialize `x` with value of type [Integer | String] (expected [Integer]) at line 1, col 1

#### map
See the documentation for the builtin [map](#map) function.

#### filter
See the documentation for the builtin [filter](#filter) function.

### Map operations
#### Creating and accessing maps
To create a map use curly braces optionally containing a list of key/value pairs
formatted as `key: value` where `key` is of type `String`.

    > var x = {"y" = 42, "z" = true}

Use a type annotation to ensure a key exists and to constrain the type of its value:

    > var x: {"y": Integer, "z": Boolean} = {"y" = 42, "z" = 3.14}
     Validator error: cannot initialize `x` with value of type {"y": Integer, "z": Real} (expected {"y": Integer, "z": Boolean}) at line 1, col 1

To make this easier to read, you can use the `type` keyword to create a type alias:

```
    type Person = {
       "name" : String,
       "age"  : Integer
     }

     var x: Person = {"name" = "Bob", "age" = 42}
```

There are two syntactical ways to set/access map keys. The first, and core, way
is to use a value of type `String` enclosed in square brackets.

    > var x = {}; x["y"] = 42; x
     {"y" = 42}

The second way is to use the `.` operator followed by a bareword value. A
bareword value is a single `String` word without quotation symbols. As such,
bareword values cannot contain whitespace.

    > var x = {}; x.y = 42; x
     {"y" = 42}

Nested maps:

    > var m = {}; m["x"] = {}; m["x"]["y"] = 42; m
     {"x" = {"y" = 42}}

    > var m = {"x" = {"y" = 42}}; m["x"]["y"]
     42

    > var m = {}; m["x"] = {"y" = 42}; m["x"]["y"]
     42

Same as above, but using the alternative `.` access syntax:

    > var m = {}; m.x = {}; m.x.y = 42; m
     {"x" = {"y" = 42}}

    > var m = {"x" = {"y" = 42}}; m.x.y
     42

    > var m = {}; m.x = {"y" = 42}; m.x.y
     42

#### keys
Use `keys` to get an array of a Map's keys.

    > var m = {'apple' = 'green', 'banana' = 'yellow', 'cherry' = 'red'}; keys m
     ['apple','banana','cherry']

#### values
Use `values` to get an array of a Map's values.

    > var m = {'apple' = 'green', 'banana' = 'yellow', 'cherry' = 'red'}; values m
     ['green','yellow','red']

#### exists
To check for existence of a Map key, use the `exists` keyword. If the key exists then
`true` is yielded, otherwise `false`. Note that setting a Map key to `null` does not
delete the key. See the [`delete`](#delete) keyword.

    > var m = {"a" = 1, "b" = 2}; exists m["a"]
     true

#### delete
To delete keys from a Map, use the `delete` keyword. Setting a key to `null` does not
delete the key.

When used on a Map key, the `delete` keyword deletes the key and returns its value, or
`null` if no such key exists.

When used on a Map itself, the `delete` keyword deletes all keys in the Map and returns
the empty Map.

    > var m = {"a" = 1, "b" = 2}; delete m["b"]; m
     {"a" = 1}

    > var m = {"a" = 1, "b" = 2}; delete m; m
     {}

### Modules
A module is a collection of related concepts in an independent source file. For
example, the `Math` module may contain math-related concepts, such as variables
like `Math::pi` and functions like `Math::abs()`.

To create a module in your project, make a `modules/` directory and place the
source file, i.e. `Math.plang`, in it.

You can create subdirectories within `modules/` to group related modules together.
For example, a module `Math::Trig::Funcs` would be found as `modules/Math/Trig/Funcs.plang`.

The `-m` switch to the `bin/plang` script allows you to define module search paths.
Multiple `-m` switches may be provided to create a list of search paths. The paths
will be searched in reverse order of the `-m` switches provided, starting from the
last `-m` path.

It is possible to have a module in the same directory as your source file by using
`-m .` as a module search path.

#### qualified identifiers
A qualified identifier is a collection of identifiers separated by `::`, i.e. `Math::pi`.

#### module
A module file must begin with the `module` keyword followed by the module name.

A module `modules/Math.plang` must begin with `module Math`:

```
    module Math

    var pi = 3.14159

    fn abs ...
```

A module `modules/Math/Trig/Funcs.plang` must begin with `module Math::Trig::Funcs`:

```
    module Math::Trig::Funcs

    fn sin ...
    fn cos ...
```

#### import
To use a module in your source, it must be imported by using the `import` keyword.
Variables and functions imported from modules can be accessed using qualified identifiers.

```
    import Math

    var two_pi = Math::pi * 2
```

Modules may be imported as a different name using the `as` keyword.

```
    import Math as m
    import Math::Trig::Funcs as f

    var x = f::cos(m::pi)
```

### Plang EBNF Grammar
Here is the, potentially incomplete, Plang EBNF grammar.

     Program            ::= {Expression}+
     KeywordNull        ::= "null"
     KeywordTrue        ::= "true"
     KeywordFalse       ::= "false"
     KeywordReturn      ::= "return" [Expression]
     KeywordWhile       ::= "while" "(" Expression ")" Expression
     KeywordNext        ::= "next"
     KeywordLast        ::= "last" [Expression]
     KeywordIf          ::= "if" Expression "then" Expression "else" Expression
     KeywordExists      ::= "exists" Expression
     KeywordDelete      ::= "delete" Expression
     KeywordKeys        ::= "keys" Expression
     KeywordValues      ::= "values" Expression
     KeywordTry         ::= try Expression {catch ["(" Expression ")"] Expression}+
     KeywordThrow       ::= "throw" Expression
     KeywordVar         ::= "var" IDENT [":" Type] [Initializer]
     KeywordType        ::= "type" IDENT [":" Type] [Initializer]
     KeywordModule      ::= "module" Identifier
     KeywordImport      ::= "import" Identifier ["as" IDENT]
     Initializer        ::= "=" Expression
     Type               ::= TypeLiteral {"|" TypeLiteral}*
     TypeLiteral        ::= TypeMap | TypeArray | TypeFunction | TYPE
     TypeMap            ::= "{" {(String | IDENT) ":" Type [","]}* "}"
     TypeArray          ::= "[" Type "]"
     TypeFunction       ::= (TYPE_Function | TYPE_Builtin) [TypeFunctionParams] [TypeFunctionReturn]
     TypeFunctionParams ::= "(" {Type [","]}* ")"
     TypeFunctionReturn ::= "->" TypeLiteral
     KeywordFn          ::= "fn" [IDENT] [IdentifierList] ["->" Type] Expression
     IdentifierList     ::= "(" {Identifier [":" Type] [Initializer] [","]}* ")"
     MapConstructor     ::= "{" {(String | IDENT) "=" Expression [","]}* "}"
     String             ::= DQUOTE_STRING | SQUOTE_STRING
     ArrayConstructor   ::= "[" {Expression [","]}* "]"
     UnaryOp            ::= Op Expression
     Op                 ::= "!" | "-" | "+" | ...
     BinaryOp           ::= Expression BinOp Expression
     BinOp              ::= "-" | "+" | "/" | "*" | "%" | ">" | ">=" | "<" | "<=" | "==" | "&&" | ...
     ExpressionGroup    ::= "{" {Expression}* "}"
     Expression         ::= ExpressionGroup | UnaryOp | BinaryOp | Identifier | KeywordNull .. KeywordThrow | LiteralInteger .. LiteralFloat | ...
     Identifier         ::= ["_" | "a" .. "z" | "A" .. "Z"] {"_" | "a" .. "z" | "A" .. "Z" | "0" .. "9"}* {"::" IDENT}*
     LiteralInteger     ::= {"0" .. "9"}+
     LiteralFloat       ::= {"0" .. "9"}* ("." {"0" .. "9"}* ("e" | "E") ["+" | "-"] {"0" .. "9"}+ | "." {"0" .. "9"}+ | ("e" | "E") ["+" | "-"] {"0" .. "9"}+)
     LiteralHexInteger  ::= "0" ("x" | "X") {"0" .. "9" | "a" .. "f" | "A" .. "F"}+
