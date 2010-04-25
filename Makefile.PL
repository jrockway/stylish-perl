use inc::Module::Install;
use strict;

name 'Stylish';
all_from 'lib/Stylish.pm';

requires 'AnyEvent';
requires 'AnyEvent::Inotify::Simple';
requires 'AnyEvent::REPL';
requires 'AnyEvent::Term';
requires 'Coro';

WriteAll;
