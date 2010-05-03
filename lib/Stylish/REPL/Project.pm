use MooseX::Declare;

class Stylish::REPL::Project {
    use Stylish::Project;
    use AnyEvent::REPL;
    use AnyEvent::Debounce;
    use Coro;
    use Coro::Semaphore;

    use File::Temp qw(tempfile);

    has 'project' => (
        is       => 'ro',
        isa      => 'Stylish::Project',
        required => 1,
        trigger  => sub {
            my ($self, $project) = @_;
            $project->add_change_hook(sub { $self->change_debounce->send });
        }
    );

    has 'repl_version' => (
        reader   => 'get_repl_version',
        init_arg => undef,
        default  => 0,
        traits   => ['Counter'],
        handles  => { 'inc_repl_version' => 'inc' },
    );

    has 'good_repl' => (
        is         => 'rw',
        isa        => 'AnyEvent::REPL',
        lazy_build => 1,
    );

    has 'on_output' => (
        is       => 'ro',
        isa      => 'CodeRef',
        default  => sub { sub {} },
    );

    has 'on_repl_change' => (
        is       => 'ro',
        isa      => 'CodeRef',
        default  => sub { sub {} },
    );

    has 'change_debounce' => (
        accessor => 'change_debounce',
        default  => sub {
            my $self = shift;
            return AnyEvent::Debounce->new(
                delay => 0.1,
                cb    => sub { $self->change },
            );
        },
    );

    method make_repl {
        return AnyEvent::REPL->new(
            capture_stderr  => 1,
            loop_traits     => ['Stylish::REPL::Trait::TransferLexenv'],
            backend_plugins => [
                '+Devel::REPL::Plugin::DDS',
                '+Devel::REPL::Plugin::LexEnv',
                '+Devel::REPL::Plugin::Packages',
                '+Devel::REPL::Plugin::ResultNames',
                '+Devel::REPL::Plugin::InstallResult',
            ],
        );
    }

    method _build_good_repl {
        my $r = $self->make_repl;
        async { $self->_setup_repl_pwd($r) }->join;
        return $r;
    }

    method repl_eval(AnyEvent::REPL $repl, Str $code) {
        my $cb = Coro::rouse_cb;
        $repl->push_eval(
            $code,
            on_output => $self->on_output,
            on_result => sub { $cb->( result => @_ ) },
            on_error  => sub { $cb->( error  => @_ ) },
        );
        my @result = Coro::rouse_wait;
        my $status = shift @result;
        confess "REPL error: @result" if $status eq 'error';
        return @result if wantarray;
        return join '', @result;
    }

    method repl_command(AnyEvent::REPL $repl, Str $command, HashRef $args) {
        my $cb = Coro::rouse_cb;
        $repl->push_command(
            $command, $args,
            on_result => sub { $cb->( result => $_[0] ) },
            on_error  => sub { $cb->( error  => $_[0] ) },
        );
        my ($status, $result) = Coro::rouse_wait;
        confess "Command error: $result" if $status eq 'error';
        return $result;
    }

    method _setup_repl_pwd(AnyEvent::REPL $repl){
        my $dir = $self->project->root->resolve->absolute;
        my $lib = $dir->subdir('lib');
        $self->repl_eval($repl, qq{chdir "\Q$dir\E";});
        $self->repl_eval($repl, qq{use lib "\Q$lib\E"});
    }

    method _load_modules_in_repl(AnyEvent::REPL $repl, Bool $strict_load? = 1){
        my @modules = $self->project->get_libraries;
        my $error = 'unknown error';
        my $result = eval {
            $self->_setup_repl_pwd($repl);
            if ($strict_load) {
                $self->repl_eval($repl, qq{require "\Q$_\E"}) for @modules;
            }
            else {
                $self->repl_eval($repl, qq{eval { require "\Q$_\E" }}) for @modules;
            }
            return $self->repl_eval($repl, qq{2 + 2});
        };
        $error = $@ if $@;
        return $repl if defined $result && $result eq '4';
        die "Modules failed to load in the new REPL: $error";
    }

    method _transfer_lexenv(AnyEvent::REPL $from, AnyEvent::REPL $to){
        my ($fh, $filename) = tempfile();

        $self->repl_command($from, 'save_state', { filename => $filename });
        $self->repl_command($to, 'restore_state', { filename => $filename });

        close $fh;
        unlink $filename;
    }

    method new_repl {
        my $r = $self->make_repl;
        $self->_load_modules_in_repl($r, 1);
        $self->_transfer_lexenv($self->good_repl, $r);
        return $r;
    }

    method change {
        async {
            $Coro::current->desc("Reloading ". $self->project->root->stringify);
            my $new_repl = eval { $self->new_repl };
            $self->on_output->($@) if $@;
            if($new_repl){
                $self->good_repl($new_repl);
                $self->inc_repl_version;
                $self->on_repl_change->($self->get_repl_version);
            }
        };
    }

    method do_eval(Str $code, Bool $chomp? = 1){
        my $result = $self->repl_eval($self->good_repl, $code);
        chomp $result if $chomp;
        return $result;
    }

    method push_eval(@args){
        $self->good_repl->push_eval(@args);
    }

    method BUILD { $self->change }

    method kill(Int $num? = 9) {
        $self->good_repl->kill($num);
        $self->change;
    }
}
