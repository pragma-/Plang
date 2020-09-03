#!/usr/bin/env perl

use warnings;
use strict;

BEGIN {
    use File::Basename;
    my $home = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, "$home/..";
}

use utf8;
STDOUT->autoflush(1);

# format is:
# ['code', ['expected type', 'expected value'], ['STDOUT', 'expected output']]
# the ['STDOUT', ''] field can be omitted if no output is expected
my @tests = (
    ['print("hello", " ") print("world")  42',
        [['TYPE', 'Integer'], 42], ['STDOUT', "hello world\n" ]],
    ['1 + 4 * 3 + 2 * 4',
        [['TYPE', 'Integer'], 21 ]],
    ['fn add(a, b = 10) a + b; add(5)',
        [['TYPE', 'Integer'], 15]],
    ['(fn (a, b) a + b)(1, 2)',
        [['TYPE', 'Integer'], 3]],
    ['var adder = fn (a, b) a + b; adder(10, 20)',
        [['TYPE', 'Integer'], 30]],
    ['(fn 42)()',
        [['TYPE', 'Integer'], 42]],
    ['"blue" < "red"',
        [['TYPE', 'Boolean'], 1]],
    ['"hi"',
        [['TYPE', 'String'], "hi" ]],
    ['"hello world" ~ "world"',
        [['TYPE', 'Integer'], 6 ]],
    ['"hello world" ~ "bye"',
        [['TYPE', 'Integer'], -1 ]],
    ['"hi " ^^ 0x263a',
        [['TYPE', 'String'], 'hi ☺' ]],
    ['fn fib(n) n == 1 ? 1 : n == 2 ? 1 : fib(n-1) + fib(n-2); fib(12)',
        [['TYPE', 'Integer'], 144 ]],
    ['"hi" && 42',
        [['TYPE', 'Integer'], 42]],
    ['"" && 42',
        [['TYPE', 'String'], '']],
    ['"" || 42',
        [['TYPE', 'Integer'], 42]],
    ['1 == 1',
        [['TYPE', 'Boolean'], 1 ]],
    ['fn square(x) x * x; var a = 5; $"square of {a} = {square(a)}"',
        [['TYPE', 'String'], 'square of 5 = 25']],
    ['var a = fn 5 + 5; a()',
        [['TYPE', 'Integer'], 10 ]],
    ['var a = fn (a, b) a + b; a(10, 20)',
        [['TYPE', 'Integer'], 30 ]],
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
        [['TYPE', 'Integer'], 5             ]],
    ['type(fn)',
        [['TYPE', 'String'], 'Function () -> Any' ]],
    ['fn f(a: Number, b: String) -> Boolean true; type(f)',
        [['TYPE', 'String'], 'Function (Number, String) -> Boolean' ]],
    ['type(1==1)',
        [['TYPE', 'String'], 'Boolean'  ]],
    ['type("hi")',
        [['TYPE', 'String'], 'String'   ]],
    ['type(42)',
        [['TYPE', 'String'], 'Integer'   ]],
    ['type(null)',
        [['TYPE', 'String'], 'Null',    ]],
    ['"Hello!"[1..4]',
        [['TYPE', 'String'], 'ello',    ]],
    ['"Good-bye!"[5..7] = "night"',
        [['TYPE', 'String'], 'Good-night!' ]],
    ['"Hello!"[0] = "Jee"',
        [['TYPE', 'String'], 'Jeeello!' ]],
    ['"Hello!"[0]',
        [['TYPE', 'String'], 'H'        ]],
    ['var a',
        [['TYPE', 'Null'],    undef      ]],
    ['1e2 + 1e3',
        [['TYPE', 'Real'],    1100       ]],
    ['1e-4',
        [['TYPE', 'Real'],    0.0001     ]],
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
        [['TYPE', 'String'], '1 2 3 1 4 2' ]],
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
        [['TYPE', 'Null'], undef], ['STDOUT', "outer\n" ]],
    ['fn curriedAdd(x) fn add(y) x + y;  curriedAdd(3)(4)',
        [['TYPE', 'Integer'], 7 ]],
    ['fn curriedAdd(x) fn add(y) x + y;  curriedAdd(3)(4)(5)',
        ['ERROR',  "Error: cannot invoke `7` as a function (have type Integer)\n" ]],
    ['var a = fn (x) fn (y) x + y;  a(3)(4)',
        [['TYPE', 'Integer'], 7 ]],
    ['fn force(f) f(); var lazy = fn 1 + 1; force(lazy)',
        [['TYPE', 'Integer'], 2 ]],
    ['fn force(f)f(); fn a(x){print("a");x}; var lazy = fn 1 + a(2); print("b"); force(lazy)',
        [['TYPE', 'Integer'], 3], ['STDOUT', "b\na\n"]],
    ['var i = 0; while (i < 5) print(++i)',
        [['TYPE', 'Null'], undef], ['STDOUT', "1\n2\n3\n4\n5\n"]],
    ['var player = { "name": "Grok", "health": 100, "iq": 75 }; player["iq"]',
        [['TYPE', 'Integer'], 75]],
    ['var a = {}; a["color"] = "blue"; $"The color is {a[\\"color\\"]}!"',
        [['TYPE', 'String'], 'The color is blue!']],
    ['var a = {"x": 42}; ++a["x"]; a["x"] += 5; a["x"] + 1',
        [['TYPE', 'Integer'], 49]],
    ['var a = {"x": {"y": 42}}; a["x"]["y"] # nested Maps',
        [['TYPE', 'Integer'], 42]],
    ['var a = {}; a["x"] = {"y": 42}; a["x"]["y"] # assign anonymous Map to another Map key',
        [['TYPE', 'Integer'], 42]],
    ['var a = ["red", "blue", 3, 4]; a[1]',
        [['TYPE', 'String'], 'blue']],
    ['var a = [[1,2], [3, 4], [5,6]]; a[2][1] # nested arrays',
        [['TYPE', 'Integer'], 6]],
    ['var a = [fn "hi", fn "bye"]; a[1]() # functions as array element',
        [['TYPE', 'String'], 'bye']],
    ['var a = {"say_hi": fn "hi", "say_bye": fn "bye"};  a["say_bye"]() # functions as map value',
        [['TYPE', 'String'], 'bye']],
    ['var a = [1, 2, 3, 4]; a[-1] # index backwards',
        [['TYPE', 'Integer'], 4]],
    ['var a = ["hi", "bye", {"foo": 42}];  a[2]["foo"] # map as array element',
        [['TYPE', 'Integer'], 42]],
    ['var a = {"hi": [1, "bye"]}; a["hi"][1] # array as map element',
        [['TYPE', 'String'], 'bye']],
);

use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse  = 1;
$Data::Dumper::Useqq  = 1;

# create our $plang object in embedded mode
use Plang::Interpreter;
my $plang = Plang::Interpreter->new(embedded => 1, debug => $ENV{DEBUG});

# override the Plang builtin `print` function so we can collect
# the output for testing, instead of printing it
$plang->add_builtin_function('print',
    # these are the parameters we want: `expr` and `end`.
    # `expr` has no default value; `end` has default value [String, "\n"]
    [[['TYPE', 'Any'], 'expr', undef], [['TYPE', 'String'], 'end', [['TYPE', 'String'], "\n"]]],
    # the type of value print() returns
    ['TYPE', 'Null'],
    # subref to our function that will override the `print` function
    \&print_override,
    \&print_validator);

# we'll collect the output in here
my $output;

# our overridden `print` function
sub print_override {
    my ($plang, $context, $name, $arguments) = @_;
    my ($expr, $end) = ($plang->output_value($arguments->[0]), $arguments->[1]->[1]);
    $output .= "$expr$end"; # append the print output to our $output
    return [['TYPE', 'Null'], undef];
}

sub print_validator {
    return [['TYPE', 'Null'], undef];
}

my @selected_tests;

if (@ARGV) {
    # select comma-separated list of test ids
    my $args = "@ARGV";
    my @wanted = split /\s*,\s*/, $args;

    foreach my $id (@wanted) {
        push @selected_tests, $tests[$id - 1];
    }
} else {
    # select all tests
    @selected_tests = @tests;
}


print "Running ", scalar @selected_tests, " test", @selected_tests == 1 ? '' : 's',  "...\n";

my @pass;
my @fail;

my $i = 0;
foreach my $test (@selected_tests) {
    $i++;
    $output = "";
    my $result     = eval { $plang->interpret_string($test->[0]) };
    $result = ['ERROR', $@] if $@;
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
        push @fail, [$i, $test->[0], $expected, $result, $exp_stdout, $stdout];
        print "X";
    } else {
        push @pass, $test;
        print ".";
    }
    print "\n" if $i % 70 == 0;
}

print "\nPass: ", scalar @pass, "; Fail: ", scalar @fail, "\n";

unless ($ENV{QUIET}) {
    foreach my $failure (@fail) {
        print '-' x 70, "\n";
        print "FAIL (Test #", $failure->[0], ")\n";
        print "\n$failure->[1]\n";
        print "       Expected: ", $failure->[2], "\n";
        print "            Got: ", $failure->[3], "\n";
        print "Expected Stdout: ", $failure->[4], "\n";
        print "     Got Stdout: ", $failure->[5], "\n";
    }
}

exit 1 if @fail;
exit 0;
