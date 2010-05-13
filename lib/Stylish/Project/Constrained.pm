use MooseX::Declare;

class Stylish::Project::Constrained extends Stylish::Project {
    use YAML::XS qw(LoadFile);

    has 'projects' => (
        is         => 'ro',
        isa        => 'HashRef[HashRef]',
        lazy_build => 1,
    );

    method _build_projects {
        eval { LoadFile($self->root->file('.stylish.yml')) } || {};
    }

    has 'name' => (
        is       => 'ro',
        isa      => 'Str',
        required => 1,
    );

    has 'project' => (
        is         => 'ro',
        isa        => 'HashRef',
        lazy_build => 1,
    );

    method _build_project {
        return $self->projects->{$self->name};
    }

    has 'library_regexp' => (
        is         => 'ro',
        isa        => 'RegexpRef',
        lazy_build => 1,
    );

    method _build_library_regexp {
        my $re = $self->project->{library_regexp} ||
                 $self->project->{library_regex}  || '.*';
        return qr{$re};
    }

    around _is_library($file){
        my $re = $self->library_regexp;
        return ($file =~ /$re/) && $self->$orig($file);
    }
}
