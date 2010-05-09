use strict;
use warnings;
use Test::More;

use Stylish::Server::Component::Project;

my $pro = Stylish::Server::Component::Project->new;
ok $pro;

done_testing;
