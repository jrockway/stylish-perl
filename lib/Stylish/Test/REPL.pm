use MooseX::Declare;

class Stylish::Test::REPL with AnyEvent::REPL::API::Sync {
    use Stylish::Test::Recorder;
    use Coro;
    use Storable;
    use Stylish::REPL::Factory qw(new_repl);
    use AnyEvent::REPL::Types qw(REPL SyncREPL);
    use File::Temp qw(tempfile);
    use File::Slurp qw(read_file);

    has 'repl' => (
        is         => 'ro',
        isa        => REPL,
        lazy_build => 1,
    );

    has 'wrapped_repl' => (
        is         => 'ro',
        isa        => SyncREPL,
        handles    => 'AnyEvent::REPL::API::Sync',
        lazy_build => 1,
    );

    has 'recorder' => (
        is         => 'ro',
        isa        => 'Stylish::Test::Recorder',
        handles    => ['do_one_test'],
        lazy_build => 1,
    );

    method _build_repl { new_repl {} }

    method _build_wrapped_repl {
        return $self->repl if $self->repl->does('AnyEvent::REPL::API::SyncREPL');
        return AnyEvent::REPL::CoroWrapper->new( repl => $self->repl );
    }

    method _build_recorder {
        return Stylish::Test::Recorder->new;
    }

    method test_eval(Str $code, CodeRef :$on_output?){
        $on_output ||= sub {};

        my ($fh, $filename) = tempfile();
        $self->do_command( save_state => { filename => $filename } );
        my $lexenv = retrieve($filename)->{context}{_};

        my $result = $self->do_eval($code, on_output => $on_output);
        $self->do_one_test($lexenv, $code, $result);
        return $result;
    }
}

