use MooseX::Declare;

class Stylish::Server::Component::Project with Stylish::Server::Component {
    use MooseX::Types::Moose qw(Str);
    use MooseX::Types::Path::Class qw(Dir);

    use Set::Object;

    use Stylish::Project;
    use Stylish::REPL::Project;

    method SERVER {}
    method UNSERVER {}
    method UNSESSION {}

    method SESSION($session) {
        $session->register_command({
            name     => 'register_project',
            object   => $self,
            method   => 'register_project',
            requires => ['repl', 'response_cb'],
            args     => {
                root => Str,
            },
        });

        $session->register_command({
            name   => 'unregister_project',
            object => $self,
            method => 'unregister_project',
            args   => { root => Str },
        });
    }

    has 'project_set' => (
        is      => 'ro',
        isa     => 'Set::Object',
        default => sub { Set::Object->new },
        handles => {
            add_project    => 'insert',
            list_projects  => 'members',
            remove_project => 'remove',
        },
    );

    method project_change(Stylish::Project $project, Str $name){
        # git snapshot
        # rebuild tags table
    }

    method ensure_project_uniqueness(Str $name, Dir $root){
        die 'this project is not unique'
          if grep { $_->root->stringify eq $root } $self->list_projects;
    }

    method register_project(Str :$root, CodeRef :$response_cb, :repl($repls)) {
        $root = Path::Class::dir($root);
        my $name = Path::Class::file($root)->basename;

        $self->ensure_project_uniqueness($name, $root);

        my $project; $project = Stylish::Project->new(
            root      => $root,
            on_change => [
                sub {
                    $response_cb->('project_change', {
                        project => $name,
                    });
                },
                sub { $self->project_change($project, $name) },
            ],
        );
        $self->add_project($project);

        my $new_repl = Stylish::REPL::Project->new(
            project        => $project,
            on_output      => sub {
                $response_cb->('repl_output', {
                    data => join('', @_),
                    repl => $name,
                });
            },
            on_repl_change => sub {
                $response_cb->('repl_generation_change', {
                    generation => $_[0],
                    repl       => $name,
                });
            },
        );

        $repls->add_repl($name, $new_repl);

        $project->add_destroy_hook(sub {
            $repls->remove_repl($name);
            $self->remove_project($project);
        });

        return { root => $root->stringify, name => $name };
    }

    method unregister_project(Str :$root){
        $root = Path::Class::dir($root)->absolute->resolve->stringify;
        for my $project ($self->list_projects) {
            if ($project->root->stringify eq $root) {
                $project->DEMOLISH;
                return 1;
            }
        }
        return 0;
    }

    # multi method unregister_project(Str :$name){
    #     $self->unregister_project($self->get_repl($name)->project);
    # }
}
