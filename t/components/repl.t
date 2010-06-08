use strict;
use warnings;
use Test::More;

use Coro;
use Stylish::Server::Component::REPL;

my $repls = Stylish::Server::Component::REPL->new;

async {
    isa_ok $repls->get_repl('test'), 'AnyEvent::REPL::CoroWrapper';
    is_deeply $repls->repl_eval(
        name        => 'new_repl',
        code        => '2 + 2',
        response_cb => sub {},
    ), { success => 1, result => 4 }, 'a new repl Just Works';

    is_deeply [sort $repls->list_repls], [sort qw/test new_repl/], 'got repls';

    my $pid = $repls->repl_eval(
        name => 'new_repl', code => '$$', response_cb => sub {},
    )->{result};

    my $long_running_eval = async {
        $repls->repl_eval(
            name => 'new_repl', code => 'while(1){ 1 }', response_cb => sub {},
        );
    };

    $repls->kill_repl( name => 'new_repl', signal => 9 );

    is $long_running_eval->join->{success}, 0, 'infinite loop killed ok';

    ok $pid != $repls->repl_eval(
        name => 'new_repl', code => '$$', response_cb => sub {},
    )->{result}, 'new PID is not the old one';

    my $readline = async {
        $repls->repl_eval(
            name => 'readline', code => 'scalar <>', response_cb => sub {},
        )->{result};
    };

    $repls->write_stdin( name => 'readline', input => "Hello, world!\n" );

    is $readline->join, "Hello, world!\n", 'got a line written to a REPLs stdin';

}->join;

done_testing;
