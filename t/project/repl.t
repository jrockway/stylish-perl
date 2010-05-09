use strict;
use warnings;
use Test::More;

use Stylish::Project;
use Stylish::REPL::Project;
use Directory::Scratch;

use Coro;

my $rchange = AnyEvent->condvar;

my $tmp = Directory::Scratch->new;
$tmp->mkdir('lib');

my $project = Stylish::Project->new(
    root      => "$tmp",
    on_change => [],
);

my $repl = Stylish::REPL::Project->new(
    project        => $project,
    on_repl_change => sub { $rchange->send(@_) },
    on_output      => sub { diag(join '', @_) },
);

is $rchange->recv, '1', 'got first generation REPL';
$rchange = AnyEvent->condvar;

is_deeply [$project->get_libraries], [], 'no libraries';
is_deeply [$project->get_modules], [], 'no modules';

async {
    is $repl->do_eval("2 + 2"), '4', 'repl works';
    is $repl->do_eval("`pwd`"), "$tmp", 'pwd is correct';
}->join;

$tmp->touch(
    'lib/Test.pm',
    'use MooseX::Declare;',
    'class Test {',
    '  has \'foo\' => ( is => \'ro\', required => 1 );',
    '  method bar { "OH HAI: ". $self->foo }',
    '}',
    '1;',
);

is $rchange->recv, '2', 'got next generation REPL';

is_deeply [$project->get_libraries], ['lib/Test.pm'], 'got Test.pm';
is_deeply [$project->get_modules], ['Test'], 'got class Test';

async {
    like $repl->do_eval('my $test = Test->new( foo => 42 )'),
      qr/test = bless\( { foo => 42 }/,
        'got Test object';
    is $repl->do_eval('$test->bar'), 'OH HAI: 42', 'the object works!';
}->join;

$rchange = AnyEvent->condvar;

$tmp->touch(
    'lib/Test.pm',
    'use MooseX::Declare;',
    'class Test {',
    '  has \'foo\' => ( is => \'ro\', required => 1 );',
    '  method bar { "Oh, hello: ". $self->foo }',
    '}',
    '1;',
);

is $rchange->recv, '3', 'got next generation REPL';

async {
    like $repl->do_eval('$test'),
      qr/test = bless\( { foo => 42 }/,
        'we still have the Test object';
    is $repl->do_eval('$test->bar'), 'Oh, hello: 42', 'the new code took effect!';
}->join;

done_testing;
