#!/usr/bin/env perl

use warnings;
use strict;

use lib '..';
use utf8;

use Plang::Interpreter;

use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse  = 1;
$Data::Dumper::Useqq  = 1;

my $plang = Plang::Interpreter->new(embedded => 1);

my @tests = (
    ['1 + 4 * 3 + 2 * 4',                                                ['NUM',    21                ]],
    ['"hi"',                                                             ['STRING', "hi"              ]],
    ['"hello world" ~ "world"',                                          ['NUM',    6                 ]],
    ['"hello world" ~ "bye"',                                            ['NUM',    -1                ]],
    ['"hi " . 0x263a',                                                   ['STRING', 'hi ☺'            ]],
    ['fn fib(n) n == 1 ? 1 : n == 2 ? 1 : fib(n-1) + fib(n-2); fib(12)', ['NUM',    144               ]],
    ['1 == 1',                                                           ['BOOL',   1                 ]],
    ['fn square(x) x * x; var a = 5; $"square of {a} = {square(a)}"',    ['STRING', 'square of 5 = 25']],
    ['var a = fn 5 + 5; a()',                                            ['NUM',    10                ]],
    ['var a = fn (a, b) a + b; a(10, 20)',                               ['NUM',    30                ]],
    [ <<'END'
fn test
  (x y)
{
  var a = x
  a + y
}
test(2 3)  # prints 5
END
        ,                                                                ['NUM',    5                 ]],
    ['type(fn)',                                                         ['STRING', 'Function'        ]],
    ['type(1==1)',                                                       ['STRING', 'Boolean'         ]],
    ['type("hi")',                                                       ['STRING', 'String'          ]],
    ['type(42)',                                                         ['STRING', 'Number'          ]],
    ['type(nil)',                                                        ['STRING', 'Nil',            ]],
);

my @pass;
my @fail;

print "Running ", scalar @tests, " test", @tests == 1 ? '' : 's',  "...\n";

my $i = 0;
foreach my $test (@tests) {
    $i++;
    my $result   = $plang->interpret_string($test->[0]);
    my $expected = $test->[1];

    $result   = Dumper ($result);
    $expected = Dumper ($expected);

    if ($result ne $expected) {
        push @fail, [$test->[0], $result, $expected];
        print "Test $i failed.\n";
    } else {
        push @pass, $test;
        print ".";
        print "\n" if $i % 70 == 0;
    }
}

print "\nPass: ", scalar @pass, "; Fail: ", scalar @fail, "\n";

foreach my $failure (@fail) {
    print "\nFAILURE: ",  $failure->[0], "\n";
    print "Expected: ", $failure->[1], "\n";
    print "Got: ",      $failure->[2], "\n";
}

exit 1 if @fail;
exit 0;
