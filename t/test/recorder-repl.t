use strict;
use warnings;
use Test::More;
use Coro;

use Stylish::Test::REPL;
use Stylish::Test::Writer::Run;

my $repl = Stylish::Test::REPL->new;
ok $repl;

async {
    $repl->do_eval('my $foo = 42');
    $repl->test_eval('$foo + 1');
    $repl->test_eval('$foo == 42');
}->join;

is_deeply [$repl->recorder->script], [
    [bind => '$foo' => 42],
    [bind => '$TEST1' => 'do { $foo + 1 }'],
    [test => '$TEST1', 43],
    [bind => '$TEST2' => 'do { $foo == 42 }'],
    [test => '$TEST2', 1],
], 'test script is like what we ran';

async {
    my $runner = Stylish::Test::Writer::Run->new;
    my $result = $runner->run([$repl->recorder->script]);
    is_deeply [$result->passed], [qw/1 2/], 'both tests passed';
    ok $result->is_good_plan, 'and we got a plan (gotta have a plan!)';
}->join;

done_testing;
