use MooseX::Declare;

class Stylish::Server::Session {

    use Stylish::Types qw(REPL);
    use MooseX::Types::Moose qw(HashRef);
    use MooseX::Types::Path::Class qw(Dir);

    use AnyEvent::REPL;
    use Coro;
    use JSON::XS;
    use Scalar::Util qw(refaddr);
    use Set::Object;
    use Try::Tiny;

    use Stylish::Project;
    use Stylish::REPL::Project;

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
        isa        => HashRef[REPL],
        default    => sub { {} },
        traits     => ['Hash'],
        handles => {
            get_repl   => 'get',
            has_repl   => 'exists',
            add_repl   => 'set',
            list_repls => 'keys',
        },
    );

    before get_repl(Str $repl){
        # make REPLs auto-vivify
        $self->add_repl($repl, AnyEvent::REPL->new)
          if !$self->has_repl($repl);
    }

    method run {
        $self->print(encode_json({
            command => "welcome",
            result  => {
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

    method project_change(Stylish::Project $project, Str $name){
        # git snapshot
        # rebuild tags table
    }

    method register_project(Str $name, Dir $root, CodeRef $on_output, CodeRef $on_repl) {
        my $project; $project = Stylish::Project->new(
            root      => $root,
            on_change => [ sub { $self->project_change($project, $name) } ],
        );
        $self->add_project($project);

        my $repl = Stylish::REPL::Project->new(
            project        => $project,
            on_output      => $on_output,
            on_repl_change => $on_repl,
        );

        $self->add_repl($name, $repl);

        return 1;
    }

    method repl(Str $repl_name, Str $code, CodeRef $on_output){
        my $repl = $self->get_repl($repl_name);
        # todo: return an error if the REPL is busy?  or just queue it
        # like this?
        my $done = Coro::rouse_cb;
        my $is_success = 0;
        $repl->push_eval(
            $code,
            on_output => $on_output,
            on_error  => $done,
            on_result => sub { $is_success = 1; $done->(@_) },
        );

        return { success => $is_success, result => join('', Coro::rouse_wait) }
    }

    method write_stdin(Str $repl_name, Str $string){
        $self->get_repl($repl_name)->push_write($string);
    }

    method kill_repl(Str $repl_name, Int $sig? = 9){
        $self->get_repl($repl_name)->kill(9);
    }

    method run_command(Str $cmd, Str $cookie, HashRef $args){
        my $respond_cb = sub {
            my ($cmd, $res) = @_;
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
                        $respond_cb->( 'repl_output', {
                            data => join('', @_),
                            repl => ($args->{name} || 'default'),
                        });
                    },
                );
            }
            when('list_repls'){
                return [$self->list_repls];
            }
            when('kill_repl'){
                return $self->kill_repl(
                    $args->{name} || die 'need name of repl',
                    $args->{signal} // 9,
                );
            }
            when('write_to_repl'){
                $self->write_stdin(
                    $args->{name} || 'default',
                    $args->{input} || die 'need input',
                );
                return 1;
            }
            when('register_project'){
                my $dir = Path::Class::dir($args->{root} || die 'need root');
                my $name = $args->{name} || $dir->basename;
                return $self->register_project(
                    $name, $dir,
                    sub {
                        $respond_cb->( 'repl_output', {
                            data => join('', @_),
                            repl => $name,
                        });
                    },
                    sub {
                        $respond_cb->( 'repl_generation_change', {
                            generation => $_[0],
                            repl       => $name,
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
