# This Plang script demonstrates closures

# the counter() function returns an anonymous function that increments
# the `i` in counter()'s scope
fn counter() {
  var i = 0  # counter variable
  fn ++i     # return anonymous function incrementing counter variable
}

# these contain their own copies of the anonymous function returned by counter()
var count1 = counter()
var count2 = counter()

# each invocation of count1() and count2() increment their copy of `i`
# that was in scope at the time `fn ++i` was returned by counter()
$"{count1()} {count1()} {count1()} {count2()} {count1()} {count2()}";

# outputs: 1 2 3 1 4 2
