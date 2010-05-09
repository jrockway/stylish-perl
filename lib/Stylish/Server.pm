use MooseX::Declare;

class Stylish::Server with (MooseX::LogDispatch, MooseX::Runnable) {
    use AnyEvent::Socket;
    use Coro::Debug;
    use Coro::EV;
    use Coro::Handle;
    use Coro;
    use EV;
    use Set::Object;
    use Stylish::Server::Session;
    use Stylish::Types qw(Components);

    our $VERSION = '0.00_01';
    our $_SERVER;

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

    has 'components' => (
        is         => 'ro',
        isa        => Components,
        coerce     => 1,
        lazy_build => 1,
        traits     => ['Array'],
        handles    => {
            get_components => 'elements',
        },
    );

    method visit_components(CodeRef $code) {
        for my $component ($self->get_components){
            $code->($component);
        }
    }

    method _build_components {
        return [ 'REPL', 'Project' ];

    }

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
            $self->visit_components(sub { $_[0]->SESSION($session) });
            $self->register_session($session);
            $session->run;
            $self->unregister_session($session);
            $self->visit_components(sub { $_[0]->UNSESSION($session) });
            $self->logger->info("Finished session ". $session->id);
            close $session->fh;
            undef $session;
        };
    }

    method run {
        $_SERVER = $self; # for the debug REPL
        my $loop = async { EV::loop };
        my $debug = Coro::Debug->new_unix_server("/tmp/stylish-debug");
        $loop->prio(3);
        $self->server;
        $self->visit_components(sub { $_[0]->SERVER($self) });
        $self->logger->debug("Server listening on /tmp/stylish");
        schedule;
        $self->visit_components(sub { $_[0]->UNSERVER($self) });
        return 0;
    }
}
