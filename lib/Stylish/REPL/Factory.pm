package Stylish::REPL::Factory;
use strict;
use warnings;
use AnyEvent::REPL;
use AnyEvent::REPL::CoroWrapper;

use Sub::Exporter -setup => {
    exports => ['new_repl'],
};

sub new_repl($) {
    my $args = shift;
    $args = { $args, @_ } if @_;

    my $sync = do {
        no warnings 'uninitialized';
        delete $args->{sync} || !delete $args->{async} || 0;
    };

    $args->{capture_stderr} //= 1;

    $args->{backend_plugins} ||= [];
    push @{$args->{backend_plugins}},
      '+Devel::REPL::Plugin::DDS',
      '+Devel::REPL::Plugin::LexEnv',
      '+Devel::REPL::Plugin::Packages',
      '+Devel::REPL::Plugin::ResultNames',
      '+Devel::REPL::Plugin::InstallResult';

    $args->{loop_traits} ||= [];
    push @{$args->{loop_traits}}, 'Stylish::REPL::Trait::TransferLexenv';

    my $repl = AnyEvent::REPL->new(
        %$args,
    );

    if($sync) {
        $repl = AnyEvent::REPL::CoroWrapper->new( repl => $repl );
    }

    return $repl;
}

1;
