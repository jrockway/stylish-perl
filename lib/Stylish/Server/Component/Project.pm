use MooseX::Declare;

class Stylish::Server::Component::Project with Stylish::Server::Component {
    use MooseX::Types::Moose qw(Str Maybe);
    use MooseX::Types::Path::Class qw(Dir);

    use Set::Object;

    use Stylish::Project;
    use Stylish::Project::Constrained;
    use Stylish::REPL::Project;
    use Stylish::Server::Component::REPL;

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
                root       => Str,
                subproject => Maybe[Str],
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

    sub project_change { #(Stylish::Project $project, Str $name){
        # git snapshot
        # rebuild tags table
    }

    method register_project( Str :$root, Str :$subproject?,
                             CodeRef :$response_cb,
                             Stylish::Server::Component::REPL :repl($repls) ){
        $root = Path::Class::dir($root);
        my $name = Path::Class::file($root)->basename;
        $name .= "/$subproject" if defined $subproject;

        my $class = $subproject && -e $root->file('.stylish.yml') ?
                    'Stylish::Project::Constrained' :
                    'Stylish::Project';
        my $project; $project = $class->new(
            defined $subproject ? (name => $subproject) : (),
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

        my $repl = Stylish::REPL::Project->new(
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

        $repls->add_repl($name, $repl);

        $project->add_destroy_hook(sub {
            $repls->remove_repl($name);
            $self->remove_project($project);
            undef $project;
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
