use inc::Module::Install;

name     'App-Rasputine';
all_from 'lib/App/Rasputine.pm';
repository 'http://github.com/melo/rasputine';

build_requires 'Test::More';

WriteAll;

