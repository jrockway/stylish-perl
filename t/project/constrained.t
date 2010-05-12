use strict;
use warnings;
use Test::More;

use Stylish::Project::Constrained;
use Directory::Scratch;

my $tmp = Directory::Scratch->new;
$tmp->mkdir('t');
$tmp->mkdir('lib/Test/Project');
$tmp->touch('lib/Test/Project.pm', "class Test::Project {","}");
$tmp->touch('lib/Test/Project/Module.pm', "class Test::Project::Module {","}");

$tmp->touch('.stylish.yml', 'module:',  ' library_regexp: "Module.pm$"',
                            'project:', ' library_regexp: "Project.pm$"',);

my $changes = 0;
my $project = Stylish::Project::Constrained->new(
    root      => "$tmp",
    name      => 'module',
    on_change => [sub { $changes++ }],
);

is_deeply [sort $project->get_libraries],
  ['lib/Test/Project/Module.pm'],
  'got library files';

is_deeply [sort $project->get_modules],
  ['Test::Project::Module'],
  'got modules';

$tmp->delete('lib/Test/Project.pm');

$project->_inotify->poll;

is $changes, 1, 'got delete';

is_deeply [$project->get_libraries],
  ['lib/Test/Project/Module.pm'],
  'got library files';

done_testing;
