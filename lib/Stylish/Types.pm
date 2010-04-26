package Stylish::Types;
use strict;
use warnings;

use MooseX::Types -declare => ['REPL'];

duck_type REPL, ['push_eval'];

1;
