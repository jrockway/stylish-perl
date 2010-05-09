use strict;
use warnings;
use Test::More;
use Test::Exception;

use AnyEvent::Util;
use Coro::Handle;

use Stylish::Server;
use Stylish::Server::Session;
use Stylish::Server::Component::REPL;

my ($me, $them) = portable_socketpair;

my $server = Stylish::Server->new(
    components => [],
);
ok $server, 'made server ok';

my $session = Stylish::Server::Session->new(
    server => $server,
    fh     => unblock($them),
);
ok $session, 'made session ok';

throws_ok {
    $session->requires('repl');
} qr/cannot satisfy requirement 'repl'/, 'no repl yet';

my $repl = Stylish::Server::Component::REPL->new;
$repl->SESSION($session);

ok $session->requires('repl'), 'now it can do repl';

my $result;
my $get_result = sub { $result = $_[1] };
$session->run_command('repl', { code => '2 + 2' }, $get_result);
is_deeply $result, { success => 1, result => 4 }, 'got correct result';

done_testing;
