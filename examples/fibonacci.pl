# This Plang script prints the first 15 Fibonacci numbers

# the fib() function
fn fib(n) n == 1 ? 1 : n == 2 ? 1 : fib(n-1) + fib(n-2)

# a basic while loop
var i = 0;
while (++i < 16) print(fib(i))
