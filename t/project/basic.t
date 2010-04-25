use strict;
use warnings;
use Test::More;

use Stylish::Project;
use Directory::Scratch;

my $tmp = Directory::Scratch->new;
$tmp->mkdir('t');
$tmp->mkdir('lib/Test/Project');
$tmp->touch('lib/Test/Project.pm', "class Test::Project {","}");
$tmp->touch('lib/Test/Project/Module.pm', "class Test::Project::Module {","}");

my $changes = 0;
my $project = Stylish::Project->new(
    root      => "$tmp",
    on_change => [sub { $changes++ }],
);

is_deeply [sort $project->get_libraries],
  ['lib/Test/Project.pm', 'lib/Test/Project/Module.pm'],
  'got library files';

is_deeply [sort $project->get_modules],
  ['Test::Project', 'Test::Project::Module'],
  'got modules';

$tmp->delete('lib/Test/Project.pm');

$project->_inotify->poll;

is $changes, 1, 'got delete';

is_deeply [$project->get_libraries],
  ['lib/Test/Project/Module.pm'],
  'got library files';

done_testing;
