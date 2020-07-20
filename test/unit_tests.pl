#!/usr/bin/env perl

use warnings;
use strict;

BEGIN {
    use File::Basename;
    my $home = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, "$home/..";
}

use utf8;

# format is:
# ['code', ['expected type', 'expected value'], ['STDOUT', 'expected output']]
# the ['STDOUT', ''] field can be omitted if no output is expected
my @tests = (
    ['print("hello", " ") print("world")  42',
        ['NUM', 42], ['STDOUT', "hello world\n" ]],
    ['1 + 4 * 3 + 2 * 4',
        ['NUM', 21 ]],
    ['fn add(a, b = 10) a + b; add(5)',
        ['NUM', 15]],
    ['(fn (a, b) a + b)(1, 2)',
        ['NUM', 3]],
    ['var adder = fn (a, b) a + b; adder(10, 20)',
        ['NUM', 30]],
    ['(fn 42)()',
        ['NUM', 42]],
    ['"blue" < "red"',
        ['BOOL', 1]],
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
    ['"hi" && 42',
        ['NUM', 42]],
    ['"" && 42',
        ['STRING', '']],
    ['"" || 42',
        ['NUM', 42]],
    ['1 == 1',
        ['BOOL', 1 ]],
    ['fn square(x) x * x; var a = 5; $"square of {a} = {square(a)}"',
        ['STRING', 'square of 5 = 25']],
    ['var a = fn 5 + 5; a()',
        ['NUM', 10 ]],
    ['var a = fn (a, b) a + b; a(10, 20)',
        ['NUM', 30 ]],
    [ <<'CODE'
# semi-colons and commas are largely optional
# (but recommended, this test just proves that they
# can still be omitted for these cases)
fn test
  (x y)       # no comma
{
  var a = x   # no semi-colons here
  a + y       # or here
}
test(2 3)     # prints 5 (yep no comma)
CODE
        ,
        ['NUM', 5             ]],
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
        ['NIL', undef], ['STDOUT', "outer\n" ]],
    ['fn curriedAdd(x) fn add(y) x + y;  curriedAdd(3)(4)',
        ['NUM', 7 ]],
    ['fn curriedAdd(x) fn add(y) x + y;  curriedAdd(3)(4)(5)',
        ['ERROR',  "Fatal error: Cannot invoke `7` as a function (have type Number)\n" ]],
    ['var a = fn (x) fn (y) x + y;  a(3)(4)',
        ['NUM', 7 ]],
    ['fn force(f) f(); var lazy = fn 1 + 1; force(lazy)',
        ['NUM', 2 ]],
    ['fn force(f)f(); fn a(x){print("a");x}; var lazy = fn 1 + a(2); print("b"); force(lazy)',
        ['NUM', 3], ['STDOUT', "b\na\n"]],
    ['var i = 0; while (i < 5) print(++i)',
        ['NIL', undef], ['STDOUT', "1\n2\n3\n4\n5\n"]],
);

use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse  = 1;
$Data::Dumper::Useqq  = 1;

# create our $plang object in embedded mode
use Plang::Interpreter;
my $plang = Plang::Interpreter->new(embedded => 1);

# override the Plang builtin `print` function so we can collect
# the output for testing, instead of printing it
$plang->{interpreter}->add_function_builtin('print',
    # these are the parameters we want: `stmt` and `end`.
    # `stmt` has no default value; `end` has default value [STRING, "\n"]
    [['stmt', undef], ['end', ['STRING', "\n"]]],
    # subref to our function that will override the `print` function
    \&print_override);

# we'll collect the output in here
my $output;

# our overridden `print` function
sub print_override {
    my ($plang, $name, $arguments) = @_;
    my ($stmt, $end) = ($plang->output_value($arguments->[0]), $arguments->[1]->[1]);
    $output .= "$stmt$end"; # append the print output to our $output
    return ['NIL', undef];
}

print "Running ", scalar @tests, " test", @tests == 1 ? '' : 's',  "...\n";

my @pass;
my @fail;

my $i = 0;
foreach my $test (@tests) {
    $i++;
    $output = "";
    my $result     = $plang->interpret_string($test->[0]);
    my $expected   = $test->[1];
    my $stdout     = ['STDOUT', $output];
    my $exp_stdout = $test->[2] // ['STDOUT', ''];

    $result     = Dumper ($result);
    $expected   = Dumper ($expected);
    $stdout     = Dumper ($stdout);
    $exp_stdout = Dumper ($exp_stdout);

    my $passed = 0;

    ++$passed if $result eq $expected;
    ++$passed if $stdout eq $exp_stdout;

    if ($passed != 2) {
        push @fail, [$test->[0], $expected, $result, $exp_stdout, $stdout];
        print "X";
    } else {
        push @pass, $test;
        print ".";
    }
    print "\n" if $i % 70 == 0;
}

print "\nPass: ", scalar @pass, "; Fail: ", scalar @fail, "\n";

$i = 0;
foreach my $failure (@fail) {
    $i++;
    print '-' x 70, "\n";
    print "FAILURE $i: ", $failure->[0], "\n";
    print " Expected: ", $failure->[1], "\n";
    print "      Got: ", $failure->[2], "\n";
    print "Expected Stdout: ", $failure->[3], "\n";
    print "     Got Stdout: ", $failure->[4], "\n";
}

exit 1 if @fail;
exit 0;
