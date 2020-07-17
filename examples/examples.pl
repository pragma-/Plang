/* This is a Plang script that demonstrates some examples
 *
 * You can run it via ./plang < examples/examples.pl
 *
 * This is a block comment, by the way.
 */

// this is a familiar C/C++ style comment to the EOL

# EOL comments can also start with a pound

# one-statement functions do not need braces
# Plang automatically returns the value of the last statement
fn square(x)    x * x

# $"" and $'' strings evaluate statements inside {}s
var foo = 4
print($"square of {foo}: {square(foo)}")  # prints "square of 4: 16"

# you can make an aonymous function that takes no parameters by omitting the
# function name and the parameter identifier list
var a = fn { var x = 1 + 2;  $"x = {x}" }
print(a()) # prints x = 3

# you can make an anonymous function with parameters by omitting just the function name
var a = fn (a, b) { var x = a + b;  $"{a} + {b} = {x}" }
print(a(5, 10)) # prints 5 + 10 = 15

# you can declare a new function `add` and assign it to a variable `a`
# both of these can be called as the same function
var a = fn add(a, b) { var x = a + b;  $"{a} + {b} = {x}" }
print(add(5, 10)) # prints 5 + 10 = 15
print(a(1, 2))    # prints 1 + 2 = 3

# commas and semi-colons are largely optional
fn test
  (x y)
{
  var a = x
  a + y
}
test(2 3)  # prints 5


