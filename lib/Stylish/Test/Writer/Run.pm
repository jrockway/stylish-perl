use MooseX::Declare;

# export test script to eval'd TAP
class Stylish::Test::Writer::Run {
    use AnyEvent::REPL;
    use Stylish::Types qw(REPL);
    use Coro::Util::Rouse qw(rouse_cb rouse_wait);
    use TAP::Parser;

    has 'repl' => (
        is         => 'ro',
        isa        => REPL,
        lazy_build => 1,
        handles    => {
            _push_eval => 'push_eval',
        },
    );

    has 'tap_accumulator' => (
        reader  => 'captured_tap',
        isa     => 'Str',
        traits  => ['String'],
        lazy    => 1,
        default => sub { "" },
        clearer => 'clear_tap_accumulator',
        handles => { 'accumulate_tap' => 'append' },
    );

    method _build_repl {
        AnyEvent::REPL->new( capture_stderr => 1 );
    }

    method BUILD {
        $self->run_use_command('Test::More');
    }

    method push_eval(Str $code){
        my ($ok, $err) = rouse_cb;
        # print "# $code\n";
        $self->_push_eval(
            $code,
            on_output => sub { $self->accumulate_tap( $_[0] ) if $_[0] },
            on_error  => $err,
            on_result => $ok,
        );

        return rouse_wait;
    }

    method run(ArrayRef $script){
        $self->push_eval('delete $_REPL->{lexical_environment}');
        $self->push_eval('Test::Builder->new->reset');
        $self->clear_tap_accumulator;

        for my $step (@$script) {
            # TODO: capture tap at each step, so we can see which test
            # produced what tap
            $self->run_command(@$step);
        }

        $self->push_eval('done_testing');

        my $parser = TAP::Parser->new({
            tap => $self->captured_tap,
        });

        # while ($API->suffers from retardation) { work around the dumbness }
        while ( my $result = $parser->next ) {}

        return $parser;
    }

    method run_command(Str $command, @args) {
        my $method = "run_${command}_command";
        confess "don't know how to run '$command'" unless $self->can($method);
        return $self->$method(@args);
    }

    method escape_for_eval (Any $val) {
        return "$val"; # LOLCAT
    }

    method run_use_command(Str $module, Str $args?){
        $args ||= "";
        $self->push_eval("use $module $args");
    }

    method run_bind_command(Str $var, Any $val) {
        $self->push_eval("my $var = ". $self->escape_for_eval($val));
    }

    method run_set_command(Str $var, Any $val) {
        $self->push_eval("$var = ". $self->escape_for_eval($val));
    }

    method run_test_command(Str $got_var, Any $expected) {
        $self->push_eval("is_deeply $got_var, ". $self->escape_for_eval($expected));
    }
}
