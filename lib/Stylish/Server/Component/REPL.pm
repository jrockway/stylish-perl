use MooseX::Declare;

class Stylish::Server::Component::REPL with Stylish::Server::Component {
    use MooseX::Types::Moose qw(Str Maybe HashRef Int);
    use Stylish::Types qw(REPL);
    use AnyEvent::REPL;

    has 'repls' => (
        is         => 'ro',
        isa        => HashRef[REPL],
        default    => sub { +{} },
        traits     => ['Hash'],
        handles    => {
            get_repl    => 'get',
            has_repl    => 'exists',
            add_repl    => 'set',
            list_repls  => 'keys',
            remove_repl => 'delete',
        },
    );

    before get_repl(Str $repl_name){
        # make REPLs auto-vivify
        $self->add_repl($repl_name, AnyEvent::REPL->new)
          if !$self->has_repl($repl_name);
    }

    method SERVER {}
    method UNSERVER {}
    method UNSESSION {}

    method SESSION($session) {
        $session->provide( repl => $self );
        $session->register_command({
            name     => 'repl',
            object   => $self,
            method   => 'repl_eval',
            defaults => { name => 'default' },
            requires => ['response_cb'],
            args     => {
                name => Maybe[Str],
                code => Str,
            },
        });

        $session->register_command({
            name   => 'list_repls',
            args   => {},
            method => 'list_repls',
            object => $self,
        });

        $session->register_command({
            name     => 'kill_repl',
            args     => { signal => Int },
            defaults => { signal => 9 },
            method   => 'kill_repl',
            object   => $self,
        });

        $session->register_command({
            name   => 'write_to_repl',
            args   => { input => Str },
            method => 'write_stdin',
            object => $self,
        });
    }

    method repl_eval(Str :$name, Str :$code, CodeRef :$response_cb){
        my $repl = $self->get_repl($name);

        my $done = Coro::rouse_cb;
        my $is_success = 0;
        $repl->push_eval(
            $code,
            on_error  => $done,
            on_result => sub { $is_success = 1; $done->(@_) },
            on_output => sub { $response_cb->('repl_output', {
                data => join('', @_),
                repl => $name,
            })},
        );

        return { success => $is_success, result => join('', Coro::rouse_wait) };
    }

    method write_stdin(Str :$name, Str :$input){
        $self->get_repl($name)->push_write($input);
    }

    method kill_repl(Str :$name, Int :$signal){
        $self->get_repl($name)->kill($signal);
        return 1;
    }
}
