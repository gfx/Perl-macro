use strict;
use warnings;
use inc::Module::Install;

name 'macro';

all_from 'lib/macro.pm';

# "For completeness sake, add support for empty documents",
#  by PPI-1.2004_01/Changes
requires 'PPI'                  => 1.203;

requires 'Filter::Util::Call'   => 1.06;

test_requires 'Test::Warn' => 0.11;

author_tests 'xt';

auto_set_repository;

WriteMakefile(
	clean => {FILES => 'macro-* example/*.plc misc/*.plc'},
);
