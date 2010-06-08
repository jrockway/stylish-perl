use MooseX::Declare;

class Stylish::Server::Component::REPL with Stylish::Server::Component {
    use MooseX::Types::Moose qw(Str Maybe HashRef Int);
    use AnyEvent::REPL::Types qw(SyncREPL);
    use AnyEvent::REPL;
    use AnyEvent::REPL::CoroWrapper;
    use Try::Tiny;

    has 'repls' => (
        is         => 'ro',
        isa        => HashRef[SyncREPL],
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

    around add_repl(Str $name, $repl){
        return $self->$orig(
            $name,
            $repl->does('AnyEvent::REPL::API::Async')
              ? AnyEvent::REPL::CoroWrapper->new( repl => $repl )
              : $repl,
        );
    }

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

        my $is_success = 0;
        my $result = try {
            my $r = $repl->do_eval(
                $code,
                on_output => sub { $response_cb->('repl_output', {
                    data => join('', @_),
                    repl => $name,
                })},
            );
            $is_success = 1;
            return $r;
        } catch { $_ };

        return { success => $is_success, result => $result };
    }

    method write_stdin(Str :$name, Str :$input){
        $self->get_repl($name)->push_write($input);
    }

    method kill_repl(Str :$name, Int :$signal){
        $self->get_repl($name)->kill($signal);
        return 1;
    }
}
