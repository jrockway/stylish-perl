package Stylish::Types;
use strict;
use warnings;

use MooseX::Types -declare => [qw/REPL Type Command Component Components/];
use MooseX::Types::Moose qw(CodeRef HashRef ArrayRef Str Object);
use MooseX::Types::Structured qw(Dict Optional);

class_type Type, { class => 'Moose::Meta::TypeConstraint' };

duck_type REPL, ['push_eval'];

subtype Command, as Dict[
    name     => Str,
    args     => Optional[HashRef[Type]],
    defaults => Optional[HashRef],
    object   => Object,
    method   => Str|CodeRef,
    requires => Optional[ArrayRef[Str]],
];

role_type Component, { role => 'Stylish::Server::Component' };

subtype Components, as ArrayRef[Component];

coerce Components, from ArrayRef[Str], via {
    my @result;
    for (@$_){
        my $class = "Stylish::Server::Component::$_";
        Class::MOP::load_class($class);
        push @result, $class->new;
    }
    return \@result;
};

1;
