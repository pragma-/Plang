fn fib(n) n == 1 ? 1 : n == 2 ? 1 : fib(n-1) + fib(n-2)

var i = 0;
while (++i < 16) print(fib(i))
