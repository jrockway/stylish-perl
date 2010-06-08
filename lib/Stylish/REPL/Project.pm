use MooseX::Declare;

class Stylish::REPL::Project
  with (AnyEvent::REPL::API::Sync, AnyEvent::REPL::API::Async) {
    use Stylish::Project;
    use AnyEvent::REPL;
    use AnyEvent::REPL::Types qw(SyncREPL AsyncREPL);
    use AnyEvent::REPL::CoroWrapper;
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
        isa        => SyncREPL,
        handles    => 'AnyEvent::REPL::API::Sync',
        lazy_build => 1,
    );

    has 'on_output' => (
        is      => 'ro',
        isa     => 'CodeRef',
        default => sub { sub {} },
    );

    has 'on_repl_change' => (
        is      => 'ro',
        isa     => 'CodeRef',
        default => sub { sub {} },
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
        my $repl = AnyEvent::REPL->new(
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

        return AnyEvent::REPL::CoroWrapper->new(
            repl => $repl,
        );
    }

    method _build_good_repl {
        my $r = $self->make_repl;
        $self->_setup_repl_pwd($r);
        return $r;
    }

    around do_eval(@args){
        my $result = $self->$orig(@args);
        chomp $result;
        return $result;
    }

    method push_eval(@args) {
        my $good_repl = $self->good_repl;
        return $good_repl->can('push_eval') ?
          $good_repl->push_eval(@args)      :
          $good_repl->repl->push_eval(@args);
    }

    method push_command(@args) {
        my $good_repl = $self->good_repl;
        return $good_repl->can('push_command') ?
          $good_repl->push_command(@args)      :
          $good_repl->repl->push_command(@args);
    }


    after kill { $self->change }

    method _setup_repl_pwd(SyncREPL $repl){
        my $dir = $self->project->root->resolve->absolute;
        my $lib = $dir->subdir('lib');
        $repl->do_eval(qq{chdir "\Q$dir\E";});
        $repl->do_eval(qq{use lib "\Q$lib\E"});
    }

    method _load_modules_in_repl(SyncREPL $repl, Bool $strict_load? = 1){
        my @modules = $self->project->get_libraries;
        my $error = 'unknown error';
        my $result = eval {
            $self->_setup_repl_pwd($repl);
            if ($strict_load) {
                $repl->do_eval(qq{require "\Q$_\E"}) for @modules;
            }
            else {
                $repl->do_eval(qq{eval { require "\Q$_\E" }}) for @modules;
            }
            return $repl->do_eval(qq{2 + 2});
        };
        $error = $@ if $@;
        return $repl if defined $result && $result eq '4';
        die "Modules failed to load in the new REPL: $error";
    }

    method _transfer_lexenv(SyncREPL $from, SyncREPL $to){
        my ($fh, $filename) = tempfile();

        $from->do_command( 'save_state',    { filename => $filename } );
        $to->do_command(   'restore_state', { filename => $filename } );

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

    method BUILD { $self->change }
}
