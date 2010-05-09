use MooseX::Declare;

class Stylish::Server::Session {
    use Stylish::Types qw(Command);
    use MooseX::Types::Path::Class qw(Dir);
    use MooseX::MultiMethods;

    use AnyEvent::REPL;
    use Coro;
    use Coro::Semaphore;
    use JSON;
    use Scalar::Util qw(refaddr);
    use Sub::AliasedUnderscore qw/transform/;
    use Try::Tiny;

    use feature 'switch';

    has 'id' => (
        is      => 'ro',
        isa     => 'Str',
        lazy    => 1,
        default => sub { q{}. refaddr($_[0]) },
    );

    has 'fh' => (
        is       => 'ro',
        isa      => 'Coro::Handle',
        required => 1,
        handles  => [qw/print readline/],
    );

    has 'server' => (
        is       => 'ro',
        isa      => 'Stylish::Server',
        weak_ref => 1,
        required => 1,
    );

    has 'print_lock' => (
        accessor => 'print_lock',
        isa      => 'Coro::Semaphore',
        default  => sub { Coro::Semaphore->new(1) },
    );

    around print(@args){
        my $guard = $self->print_lock->guard;
        my $result = encode_json({@args});
        $self->server->logger->debug(" => $result");
        return $self->$orig("$result\n");
    }

    around readline {
        my $parse; $parse = sub {
            my $line = $self->$orig("\n");
            return unless $line;
            return try {
                decode_json($line);
            } catch {
                $self->print(
                    error => $_
                );
                # keep reading until it's not an error
                goto $parse;
            }
        };
        return $parse->();
    }

    has 'commands' => (
        is       => 'ro',
        isa      => 'HashRef[HashRef]',
        default  => sub { +{} },
        traits   => ['Hash'],
        handles  => {
            'add_command' => 'set',
            'has_command' => 'exists',
            'get_command' => 'get',
        },
    );

    # can
    has 'cheezburger' => (
        isa     => 'HashRef',
        default => sub { +{} }, # should probably be a weak hash
        traits  => ['Hash'],
        handles => {
            provide  => 'set', # http://xrl.us/bhkhxj
            requires => 'get', # http://xrl.us/bhkhxm
        },
    );

    around requires($thing) {
        return $self->$orig($thing) ||
          confess "cannot satisfy requirement '$thing'";
    }

    method register_command(Command $def){
        $def->{requires} ||= [];

        confess 'requires will conflict with args'
          if $def->{args} ~~ $def->{requires};

        my $obj = $def->{object};
        my $method = $def->{method};
        $self->add_command(
            $def->{name} => {
                invoke   => sub { $obj->$method(@_) },
                args     => $def->{args},
                requires => $def->{requires},
                defaults => $def->{defaults} || {},
            },
        );
    }

    method run_command(Str $cmd, HashRef $args, CodeRef $response_cb){
        die "no command '$cmd' registered" unless $self->has_command($cmd);

        # workaround broken moose stuff
        $self->provide(response_cb => $response_cb);

        my $def = $self->get_command($cmd);
        my %deps = map { ( $_ => $self->requires($_) ) } @{$def->{requires} || []};
        $response_cb->(
            $cmd,
            $def->{invoke}->(
                %{ +{ %{$def->{defaults}}, %deps, %$args } },
            ),
        );
        return;
    }

    method run {
        $self->print(
            command => "welcome",
            result  => {
                session_id => $self->id,
                version    => $self->server->VERSION,
            },
        );

        no warnings 'exiting';
        my @coros;

      line:
        while (my $req = $self->readline) {
            my $cookie = undef;

            my $error_cb = sub {
                $self->print(
                    error  => $_,
                    cookie => $cookie,
                );
            };

            my $respond_cb = sub {
                my ($cmd, $res) = @_;
                $self->print(
                    cookie  => $cookie,
                    result  => $res,
                    command => $cmd,
                );
            };

            try {
                $cookie = delete $req->{cookie} || die 'no cookie?';
                my $cmd = delete $req->{command} || die 'no command?';

                $self->server->logger->debug("$cmd: ". encode_json($req));
                last line if $cmd eq 'exit'; # we're done

                push @coros, async {
                    $Coro::current->desc($self->id. ": $cmd ($cookie)");
                    # each request can run in its own thread
                    try {
                        $self->run_command(
                            $cmd, $req, $respond_cb,
                        );
                    } $error_cb;
                };
            } $error_cb;
        }

        # kill any in-progress activities
        $_->cancel for @coros;
        # $self->remove_project($_) for $self->list_projects;
        # $self->remove_repl($_) for $self->list_repls;
    }
}
