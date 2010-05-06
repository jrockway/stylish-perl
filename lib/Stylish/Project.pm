use MooseX::Declare;

class Stylish::Project with AnyEvent::Inotify::EventReceiver {
    use AnyEvent::Inotify::Simple;
    use Devel::InPackage;
    use File::Next::Filtered qw(files);
    use MooseX::FileAttribute;
    use MooseX::MultiMethods;
    use MooseX::Types::Path::Class qw(File Dir);
    use Path::Filter::Rule::Glob;
    use Path::Filter;
    use Scalar::Util qw(weaken);

    has_directory 'root' => (
        must_exist => 1,
    );

    has 'on_change' => (
        is       => 'ro',
        traits   => ['Array'],
        isa      => 'ArrayRef[CodeRef]',
        required => 1,
        handles  => {
            on_change_hooks => 'elements',
            add_change_hook => 'push',
        },
    );

    method run_on_change(@args) {
        $_->(@args) for $self->on_change_hooks;
    }

    has 'filter' => (
        is         => 'ro',
        isa        => 'Path::Filter',
        lazy_build => 1,
    );

    method _build_filter {
        my $f = Path::Filter->new(
            root  => $self->root,
            rules => [qw/Backup VersionControl EditorJunk/],
        );

        # $f->add_filter( Path::Filter::Rule::Glob->new(
        #     glob => 'blib/*',
        # ));

        # $f->add_filter( Path::Filter::Rule::Glob->new(
        #     glob => 'inc/*',
        # ));

        return $f;
    }

    has 'inotify' => (
        reader     => '_inotify',
        isa        => 'AnyEvent::Inotify::Simple',
        lazy_build => 1,
    );

    method _build_inotify {
        my $i = AnyEvent::Inotify::Simple->new(
            directory      => $self->root,
            event_receiver => $self,
            filter         => $self->filter,
        );

        weaken $i->{event_receiver};

        return $i;
    }

    has 'libraries' => (
        is         => 'ro',
        traits     => ['Hash'],
        isa        => 'HashRef[ArrayRef[Str]]',
        lazy_build => 1,
        handles    => {
            _get_libraries => 'keys',
            _get_modules   => 'values',
            _add_library   => 'set',
            delete_library => 'delete',
        },
    );

    has 'on_destroy' => (
        is       => 'ro',
        traits   => ['Array'],
        isa      => 'ArrayRef[CodeRef]',
        default  => sub { [] },
        handles  => {
            on_destroy_hooks => 'elements',
            add_destroy_hook => 'push',
        },
    );

    multi method _is_library(Dir $file){ return }

    multi method _is_library(File $file) {
        return unless $file =~ /[.]pm$/;
        return unless $file =~ /\blib\b/;

        # skip blib, inc, and t
        return if $file =~ /^(blib|inc|t)\b/;
        return 1;
    }

    around _add_library(File $lib, ArrayRef $val){
        return unless $self->_is_library($lib);
        $self->$orig($lib, $val);
    }

    method extract_library_modules(File $file) {
        my %packages;
        eval {
            Devel::InPackage::scan(
                file     => $file->absolute($self->root)->stringify,
                callback => sub { $packages{$_[1]}++; 1 },
            );
        }; # sometimes files don't stay around long enough for this to work
        return [ grep { $_ ne 'main' } keys %packages ];
    }

    method add_library(File|Dir $lib){
        return unless -f $lib->absolute($self->root);
        $self->_add_library($lib, $self->extract_library_modules($lib));
    }

    method get_libraries {
        map { Path::Class::file($_) } $self->_get_libraries;
    }

    method get_modules {
        map { @{ $_ || [] } } $self->_get_modules;
    }

    method _build_libraries {
        # normally, Inotify::Simple filters everything, but the first
        # time around, we do it ourselves
        my $i = files(
            { filter => $self->filter },
            $self->root,
        );

        my @result;
        while(my $file = $i->()){
            $file = $file->relative($self->root);
            push @result, $file if $self->_is_library($file);
        }
        return { map { $_ => $self->extract_library_modules($_) } @result };
    }

    method handle_access {}
    method handle_attribute_change {}
    method handle_close {}
    method handle_open {}

    method handle_create(File|Dir $file) {
        $self->add_library($file);
        $self->run_on_change($file);
    }

    method handle_move(File|Dir $old, File|Dir $new) {
        $self->run_on_change($new);
        $self->delete_library($old);
        $self->add_library($new);
    }

    method handle_modify(File|Dir $file) {
        $self->run_on_change($file);
    }

   method handle_delete(File|Dir $file) {
        $self->delete_library($file);
        $self->run_on_change($file);
    }

    method BUILD { $self->_inotify }

    method DEMOLISH {
        undef $self->{_inotify};
        $_->() for $self->on_destroy_hooks;
    }
}
