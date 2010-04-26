use MooseX::Declare;

class Stylish::Server::Session {
    use JSON::XS;
    use Try::Tiny;
    use Scalar::Util qw(refaddr);

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

    method run {
        $self->print(encode_json({
            welcome => {
                session_id => $self->id,
                version    => $self->server->VERSION,
            },
        }). "\n");

        no warnings 'exiting';
      line:
        while(my $line = $self->readline("\n")){
            my $cookie = undef;
            try {
                chomp $line;
                my $req = decode_json($line);
                my $cmd = delete $req->{command} || die 'no command?';
                last line if $cmd eq 'exit'; # we're done
                $cookie = delete $req->{cookie} || die 'no cookie?';
                my $result = $self->run_command($cmd, $req);
                $self->print(encode_json({
                    command => $cmd,
                    cookie  => $cookie,
                    result  => $result,
                }). "\n");
            } catch {
                $self->print(encode_json({ error => $_, cookie => $cookie }). "\n");
            };
        }
    }

    method run_command(Str $cmd, HashRef $args){
        return { it => 'worked' };
    }

}
