use strict;
use warnings;
use Test::More;
use Stylish::Test::Recorder;
use Test::Exception;

my $r = Stylish::Test::Recorder->new(
    initial_lexenv => {
        '$foo' => 0,
    },
);

ok $r;

is_deeply [$r->script], [[ bind => '$foo', 0 ]],
          'initial lexenv generated bindings';

my $var = 42;
lives_ok {
    $r->do_one_test({ '$foo' => 42 }, '$foo + 2', 44);
    $r->do_one_test({ '$foo' => 42 }, 'my $bar = 1; $foo - $bar', 41);
    $r->do_one_test({ '$foo' => 42, '$bar' => 1 }, '$foo + $bar', 43);
    $r->do_one_test({ '$foo' => \$var, '$bar' => 2 }, '$$foo + $bar', 123);
} 'record some tests';

is_deeply [sort $r->_namespace->members], [sort qw/$foo $bar $TEST1 $TEST2 $TEST3 $TEST4/],
   'see that the variables we expected were bound';

is_deeply [$r->script], [
    [bind => '$foo' => 0 ],
    [set  => '$foo' => 42 ],
    [bind => '$TEST1', 'do { $foo + 2 }'],
    [test => '$TEST1', 44],
    [bind => '$TEST2', 'do { my $bar = 1; $foo - $bar }'],
    [test => '$TEST2', 41],
    [bind => '$bar' => 1],
    [bind => '$TEST3', 'do { $foo + $bar }'],
    [test => '$TEST3', 43],
    [set  => '$foo', \$var],
    [set  => '$bar', 2],
    [bind => '$TEST4', 'do { $$foo + $bar }'],
    [test => '$TEST4', 123],
], 'is our script what we expect?';

done_testing;
