use strict;
use warnings;
use Test::More;
use Coro;
use Stylish::Test::REPL;

my $r = Stylish::Test::REPL->new;
ok $r;

async {
    $r->push_eval('my $foo = 42');
    $r->test_eval('$foo + 1');
    $r->test_eval('$foo == 42');
}->join;

is_deeply [$r->recorder->script], [
    [bind => '$foo' => 42],
    [bind => '$TEST1' => 'do { $foo + 1 }'],
    [test => '$TEST1', 43],
    [bind => '$TEST2' => 'do { $foo == 42 }'],
    [test => '$TEST2', 1],
], 'test script is like what we ran';


done_testing;
