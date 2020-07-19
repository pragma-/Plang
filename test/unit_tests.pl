#!/usr/bin/env perl

use warnings;
use strict;

BEGIN {
    use File::Basename;
    my $home = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, "$home/..";
}

use utf8;

my @tests = (
    ['1 + 4 * 3 + 2 * 4',
        ['NUM', 21 ]],
    ['"hi"',
        ['STRING', "hi" ]],
    ['"hello world" ~ "world"',
        ['NUM', 6 ]],
    ['"hello world" ~ "bye"',
        ['NUM', -1 ]],
    ['"hi " . 0x263a',
        ['STRING', 'hi ☺' ]],
    ['fn fib(n) n == 1 ? 1 : n == 2 ? 1 : fib(n-1) + fib(n-2); fib(12)',
        ['NUM', 144 ]],
    ['1 == 1',
        ['BOOL', 1 ]],
    ['fn square(x) x * x; var a = 5; $"square of {a} = {square(a)}"',
        ['STRING', 'square of 5 = 25']],
    ['var a = fn 5 + 5; a()',
        ['NUM', 10 ]],
    ['var a = fn (a, b) a + b; a(10, 20)',
        ['NUM', 30 ]],
    [ <<'END'
fn test
  (x y)
{
  var a = x
  a + y
}
test(2 3)  # prints 5
END
        , ['NUM', 5 ]],
    ['type(fn)',
        ['STRING', 'Function' ]],
    ['type(1==1)',
        ['STRING', 'Boolean'  ]],
    ['type("hi")',
        ['STRING', 'String'   ]],
    ['type(42)',
        ['STRING', 'Number'   ]],
    ['type(nil)',
        ['STRING', 'Nil',     ]],
    ['"Hello!"[1..4]',
        ['STRING', 'ello',    ]],
    ['"Good-bye!"[5..7] = "night"',
        ['STRING', 'Good-night!' ]],
    ['"Hello!"[0] = "Jee"',
        ['STRING', 'Jeeello!' ]],
    ['"Hello!"[0]',
        ['STRING', 'H'        ]],
    ['var a',
        ['NIL',    undef      ]],
    ['1e2 + 1e3',
        ['NUM',    1100       ]],
    ['1e-4',
        ['NUM',    0.0001     ]],
    [ <<'CODE'
# closure test
fn counter() {
  var i = 0  # counter variable
  fn ++i     # final statement returns anonymous function taking no arguments, with one statement body `++i`
}

# these contain their own copies of the anonymous function `++i` returned by counter()
var count1 = counter()
var count2 = counter()

# these should increment their own `i` that was in scope at the time `fn ++i` was returned by counter()
$"{count1()} {count1()} {count1()} {count2()} {count1()} {count2()}";
CODE
        ,
        ['STRING', '1 2 3 1 4 2' ]],
    [ <<'CODE'
# another closure test
var x = "global"
fn outer {
  var x = "outer";
  fn inner { print(x); }
  inner();
}
outer();
CODE
        ,
        ['STDOUT', "outer\n"   ]],
    ['fn curriedAdd(x) fn add(y) x + y;  curriedAdd(3)(4)',
        ['NUM',    7   ]],
    ['fn curriedAdd(x) fn add(y) x + y;  curriedAdd(3)(4)(5)',
        ['ERROR',  "Fatal error: Cannot invoke `7` as a function (have type Number)\n" ]],
    ['var a = fn (x) fn (y) x + y;  a(3)(4)',
        ['NUM',    7   ]],
);

use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse  = 1;
$Data::Dumper::Useqq  = 1;

use Plang::Interpreter;
my $plang = Plang::Interpreter->new(embedded => 1);

print "Running ", scalar @tests, " test", @tests == 1 ? '' : 's',  "...\n";

my @pass;
my @fail;

my $i = 0;
foreach my $test (@tests) {
    $i++;
    my $result   = $plang->interpret_string($test->[0]);
    my $expected = $test->[1];

    $result   = Dumper ($result);
    $expected = Dumper ($expected);

    if ($result ne $expected) {
        push @fail, [$test->[0], $expected, $result];
        print "X";
    } else {
        push @pass, $test;
        print ".";
    }
    print "\n" if $i % 70 == 0;
}

print "\nPass: ", scalar @pass, "; Fail: ", scalar @fail, "\n";

foreach my $failure (@fail) {
    print "\nFAILURE: ",  $failure->[0], "\n";
    print "Expected: ",   $failure->[1], "\n";
    print "Got: ",        $failure->[2], "\n";
}

exit 1 if @fail;
exit 0;
