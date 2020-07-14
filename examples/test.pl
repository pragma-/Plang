/* This is a Plang test script
 *
 * You can run it via ./plang < test/test.pl
 */

// this is a familiar C/C++ style comment to the EOL

# EOL comments can also start with a pound

# one-statement functions do not need braces
fn square(x)    x * x

print(square(4))

# $"" and $'' strings evaluate statements inside {}s
var foo = 4
print($"square of {foo}: {square(foo)}")  # prints "square of 4: 16"

# commas and semi-colons are largely optional
fn test
  (x y)
{
  var a = x
  a + y
}
test(2 3)  # prints 5
