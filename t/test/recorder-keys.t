use strict;
use warnings;
use Test::More;

use Stylish::Test::Recorder;
my $r = Stylish::Test::Recorder->new();
$r->current_lexenv({});

sub do_test ($@) {
    my ($hash, @expected) = @_;
    no warnings;
    is_deeply [sort $r->_changed_keys($hash)], [sort @expected];
    $r->current_lexenv({ %{$r->current_lexenv}, %$hash});
}

do_test { foo => 42, bar => undef }, qw/foo bar/;
do_test { foo => 42, bar => 1 }, qw/bar/;
do_test { foo => 43, bar => 1 }, qw/foo/;
do_test { }, ();
do_test { foo => 43 }, ();
do_test { baz => 123, bar => undef }, qw/bar baz/;
do_test { foo => undef, bar => undef, baz => undef, quux => undef },
   qw/foo baz quux/;

done_testing;
