use strict;
use warnings;
use Test::More;

use Stylish::Server::Component::Project;
use Directory::Scratch;
use AnyEvent;

my $tmp = Directory::Scratch->new;
$tmp->touch('lib/Foo.pm', 'package Foo;', '1;');

my $pc = Stylish::Server::Component::Project->new;
my $rc = Stylish::Server::Component::REPL->new;
ok $pc;

my $cv = AnyEvent->condvar;
my $cb = sub { return unless $_[0] =~ /generation/;
               $cv->($_[1]->{generation}) };

$pc->register_project(
    root        => "$tmp",
    response_cb => $cb,
    repl        => $rc,
);

is $cv->recv, 1, 'got gen 1';
is scalar $rc->list_repls, 1, 'got REPL';
is scalar @{[$pc->list_projects]}, 1, 'got project';

my $destroyed = 0;
$pc->list_projects->add_destroy_hook(sub { $destroyed = 1 });

ok $pc->unregister_project(root => "$tmp"), 'unreg ok';

is scalar $rc->list_repls, 0, 'REPL is gone';
is scalar @{[$pc->list_projects]}, 0, 'project is gone';
is $destroyed, 1, 'destroy hook ran';

$cv = AnyEvent->condvar;
my $timeout = AnyEvent->timer( after => 1.5, interval => 0, cb => sub {
    $cv->send(0);
});

$tmp->touch('lib/Bar.pm', 'package Bar;', '1;');

is $cv->recv, 0, 'got timeout, NOT gen 2';

done_testing;
