package Stylish::REPL::Trait::TransferLexenv;
use Moose::Role;
use namespace::autoclean;
use Storable qw(nstore retrieve);

sub handle_save_state {
    my ($self, $args) = @_;
    nstore($self->backend->lexical_environment, $args->{filename});
    return 1;
}

sub handle_restore_state {
    my ($self, $args) = @_;
    $self->backend->lexical_environment(retrieve($args->{filename}));
    return 1;
}

1;
