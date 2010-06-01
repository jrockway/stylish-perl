use MooseX::Declare;

class Stylish::Test::REPL {
    use Stylish::Test::Recorder;
    use Stylish::Types qw(REPL);
    use Coro;
    use Storable;
    use AnyEvent::REPL;
    use File::Temp qw(tempfile);
    use File::Slurp qw(read_file);

    has 'repl' => (
        is         => 'ro',
        isa        => REPL,
        lazy_build => 1,
        handles    => {
            push_write    => 'push_write',
            kill          => 'kill',
            _push_eval    => 'push_eval',
            _push_command => 'push_command',
        },
    );

    has 'recorder' => (
        is         => 'ro',
        isa        => 'Stylish::Test::Recorder',
        handles    => ['do_one_test'],
        lazy_build => 1,
    );

    method _build_repl {
        return AnyEvent::REPL->new(
            capture_stderr  => 1,
            loop_traits     => ['Stylish::REPL::Trait::TransferLexenv'],
            backend_plugins => [
                '+Devel::REPL::Plugin::DDS',
                '+Devel::REPL::Plugin::LexEnv',
                '+Devel::REPL::Plugin::Packages',
                '+Devel::REPL::Plugin::ResultNames', # TODO: need to
                                                     # get the
                                                     # $TESTWHATEVER
                                                     # name for this.
                '+Devel::REPL::Plugin::InstallResult',
            ],
        );
    }

    method _build_recorder {
        return Stylish::Test::Recorder->new;
    }

    # not really a push, but for api compat...
    method push_eval(Str $code, CodeRef :$on_output?){
        $on_output ||= sub {};

        my $ecb = Coro::rouse_cb;
        $self->_push_eval(
            $code,
            on_output => $on_output,
            on_error  => sub { $ecb->({error => $_[0]}) },
            on_result => sub { $ecb->({result => $_[0]}) },
        );

        my $result = Coro::rouse_wait;
        die $result->{error} if exists $result->{error};

        # developers developers developers developers developers
        $result = $result->{result};
        return $result;
    }

    method test_eval(Str $code, CodeRef :$on_output?){
        $on_output ||= sub {};
        my ($fh, $filename) = tempfile();

        my $ccb = Coro::rouse_cb;
        $self->_push_command(
            save_state => { filename => $filename },
            on_result  => sub { $ccb->(undef) },
            on_error   => $ccb,
        );
        my $err = Coro::rouse_wait;
        die $err if defined $err;

        my $lexenv = retrieve($filename)->{context}{_};
        my $result = $self->push_eval($code, on_output => $on_output);
        $self->do_one_test($lexenv, $code, $result);
        return $result;
    }
}
