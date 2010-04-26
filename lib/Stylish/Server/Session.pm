use MooseX::Declare;

class Stylish::Server::Session {
    use JSON::XS;
    use Try::Tiny;
    use Set::Object;
    use AnyEvent::REPL;
    use Scalar::Util qw(refaddr);
    use MooseX::Types::Path::Class qw(Dir);
    use Coro;
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

    has 'project_set' => (
        is      => 'ro',
        isa     => 'Set::Object',
        default => sub { Set::Object->new },
        handles => {
            add_project => 'insert',
        },
    );

    has 'repls' => (
        is         => 'ro',
        isa        => 'HashRef[AnyEvent::REPL]',
        default    => sub { {} },
        traits     => ['Hash'],
        handles => {
            get_repl => 'get',
            has_repl => 'exists',
            add_repl => 'set',
        },
    );

    before get_repl(Str $repl){
        # make REPLs auto-vivify
        $self->add_repl($repl, AnyEvent::REPL->new)
          if !$self->has_repl($repl);
    }

    method run {
        $self->print(encode_json({
            welcome => {
                session_id => $self->id,
                version    => $self->server->VERSION,
            },
        }). "\n");

        no warnings 'exiting';
        my @coros;

      line:
        while(my $line = $self->readline("\n")){
            my $cookie = undef;

            my $error_cb = sub {
                $self->print(encode_json({
                    error  => $_,
                    cookie => $cookie,
                }). "\n");
            };

            try {
                chomp $line;
                my $req = decode_json($line);
                my $cmd = delete $req->{command} || die 'no command?';
                last line if $cmd eq 'exit'; # we're done
                $cookie = delete $req->{cookie} || die 'no cookie?';
                push @coros, async {
                    $Coro::current->desc($self->id. ": $cmd ($cookie)");
                    # each request can run in its own thread
                    try {
                        my $result = $self->run_command($cmd, $cookie, $req);
                        $self->print(encode_json({
                            command => $cmd,
                            cookie  => $cookie,
                            result  => $result,
                        }). "\n");
                    } $error_cb;
                };
            } $error_cb;
        }

        # kill any in-progress activities
        $_->cancel for @coros;
    }

    method register_project(Str $name, Dir $root does coerce) {

    }

    method repl(Str $repl_name, Str $code, CodeRef $on_output){
        my $repl = $self->get_repl($repl_name);
        # todo: return an error if the REPL is busy?  or just queue it
        # like this?
        my $done = Coro::rouse_cb;
        my $is_success = 0;
        $repl->push_eval(
            $code,
            on_output => sub { warn "got output: @_"; $on_output->(@_) },
            on_error  => $done,
            on_result => sub { $is_success = 1; $done->(@_) },
        );

        return { success => $is_success, result => join('', Coro::rouse_wait) }
    }

    # method write_stdin(Str $repl_name){
    # }

    # method kill_repl(Str $repl_name){
    # }

    method run_command(Str $cmd, Str $cookie, HashRef $args){
        my $respond_cb = sub {
            my ($cmd, $res) = @_;
            warn "$cmd output";
            $self->print(encode_json({
                cookie  => $cookie,
                result  => $res,
                command => $cmd,
            })."\n");
        };

        given($cmd){
            when('repl'){
                return $self->repl(
                    ($args->{name} || 'default'),
                    ($args->{code} || die 'need code to eval'),
                    sub {
                        warn "here";
                        $respond_cb->( 'repl_output', {
                            data => join('', @_),
                            repl => ($args->{name} || 'default'),
                        });
                    },
                );
            }
            default {
                die "unknown command '$cmd'";
            }
        }
    }

}
