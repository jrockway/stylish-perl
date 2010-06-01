use MooseX::Declare;

class Stylish::Test::Recorder {
    use Set::Object;
    has 'initial_lexenv' => (
        is      => 'ro',
        isa     => 'HashRef',
        default => sub { +{} },
        trigger => sub {
            my ($self, $val) = @_;
            $self->_bind_hash($val);
        },
    );

    has 'current_lexenv' => (
        accessor   => 'current_lexenv',
        isa        => 'HashRef',
        lazy_build => 1,
    );

    has 'namespace' => (
        reader  => '_namespace',
        isa     => 'Set::Object',
        default => sub { Set::Object->new },
        handles => {
            add_variable => 'insert',
            already_seen => 'member',
        },
    );

    has 'test_count' => (
        accessor => 'test_count',
        isa      => 'Int',
        default  => sub { 1 },
    );

    has 'script' => (
        isa     => 'ArrayRef[ArrayRef]',
        default => sub { +[] },
        traits  => ['Array'],
        handles => {
            push_command => 'push',
            script       => 'elements',
        },
    );

    method _build_current_lexenv {
        $self->initial_lexenv;
    }

    method _changed_keys(HashRef $new_lexenv) {
        # return a list of keys in new_lexenv that will need to be
        # updated, based on the state of current_lexenv

        my @keys;
        my %cur = %{$self->current_lexenv};
        key: for my $key (keys %$new_lexenv){
            if(!exists $cur{$key}){
                # we want to add a declaration even if the new value
                # is undef
                push @keys, $key;
                next key;
            }

            my $new_value = $new_lexenv->{$key};
            my $old_value = $cur{$key};

            no warnings 'uninitialized';
            push @keys, $key if $new_value ne $old_value;
        }
        return @keys;
    }

    method _bind_hash(HashRef $hash){
        for my $var (keys %$hash) {
            $self->push_command([bind => $var => $hash->{$var}]);
            $self->add_variable($var);
        }
    }

    method do_one_test(HashRef $lexenv, Str $code, Any $expected) {
        # setup lexenv
        my @changed = $self->_changed_keys($lexenv);
        for my $var (@changed) {
            my $cmd = 'bind';
            $cmd = 'set' if $self->already_seen($var);
            $self->push_command([$cmd => $var => $lexenv->{$var}]);
            $self->add_variable($var);
        }

        # find a variable named $TEST123 that hasn't been used yet
        my $num = $self->test_count;
        while($self->already_seen("\$TEST$num")){
            $num++;
        }
        $self->test_count($num+1);

        # run the code for the test
        my $test_var = "\$TEST$num";
        $self->push_command([bind => $test_var => "do { $code }"]);
        $self->add_variable($test_var);

        # then ensure that got == expected
        $self->push_command([test => $test_var => $expected]);

        # and save the lexenv for the next tests
        $self->current_lexenv({
            %{$self->current_lexenv},
            %$lexenv,
            ($test_var => 'DUMMY'),
        });
    }
}
