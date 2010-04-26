use MooseX::Declare;

class Stylish::Server with (MooseX::LogDispatch, MooseX::Runnable) {
    use AnyEvent::Socket;
    use EV;
    use Coro;
    use Coro::EV;
    use Coro::Debug;
    use Coro::Handle;
    use Stylish::Server::Session;
    use Set::Object;

    our $VERSION = '0.00_01';

    has 'server' => (
        is         => 'ro',
        lazy_build => 1,
    );

    has 'sessions' => (
        is      => 'ro',
        isa     => 'Set::Object',
        default => sub { Set::Object->new },
        handles => {
            register_session   => 'insert',
            unregister_session => 'delete',
        },
    );

    method _build_server {
        return tcp_server 'unix/', '/tmp/stylish', sub { $self->run_session($_[0]) };
    }

    method run_session(GlobRef $fh){
        return async {
            my $session = Stylish::Server::Session->new(
                fh     => unblock $fh,
                server => $self,
            );
            $self->logger->info("New connection ". $session->id);
            $Coro::current->desc("Stylish session ". $session->id);
            $self->register_session($session);
            $session->run;
            $self->unregister_session($session);
            $self->logger->info("Finished session ". $session->id);
        };
    }

    method run {
        my $loop = async { EV::loop };
        my $debug = Coro::Debug->new_unix_server("/tmp/stylish-debug");
        $loop->prio(3);
        $self->server;
        $self->logger->debug("Server listening on /tmp/stylish");
        schedule;
    }
}
