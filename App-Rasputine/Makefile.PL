use inc::Module::Install;

name     'App-Rasputine';
all_from 'lib/App/Rasputine.pm';
author   'Pedro Melo <melo@cpan.org>';

build_requires 'Test::More';

auto_install;

WriteAll;

