use inc::Module::Install;
use strict;

name 'Stylish';
all_from 'lib/Stylish.pm';

requires 'AnyEvent';
requires 'AnyEvent::Inotify::Simple';
requires 'AnyEvent::REPL';
requires 'AnyEvent::Term';
requires 'Coro';
requires 'Sub::AliasedUnderscore';
requires 'MooseX::Declare';

test_requires 'Test::More';
test_requires 'Test::Exception';

WriteAll;
