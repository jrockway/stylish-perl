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

async {
    is $repl->push_eval("2 + 2"), '4', 'repl works';
    is $repl->push_eval("`pwd`"), "$tmp", 'pwd is correct';
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

is $rchange->recv, '1', 'got next generation REPL';

async {
    like $repl->push_eval('my $test = Test->new( foo => 42 )'),
      qr/Test=HASH/,
        'got Test object';
    is $repl->push_eval('$test->bar'), 'OH HAI: 42', 'the object works!';
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

is $rchange->recv, '2', 'got next generation REPL';

async {
    like $repl->push_eval('my $test = Test->new( foo => 42 )'),
      qr/Test=HASH/,
        'got Test object';
    is $repl->push_eval('$test->bar'), 'Oh, hello: 42', 'the new code took effect!';
}->join;

done_testing;
