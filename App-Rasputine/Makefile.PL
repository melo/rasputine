use inc::Module::Install;

name     'App-Rasputine';
all_from 'lib/App/Rasputine.pm';
repository 'http://github.com/melo/rasputine';

install_script 'rasputine';

requires 'AnyEvent' => 0;
requires 'Net::XMPP2::Component' => 0;
requires 'AnyEvent::Handle' => 0;
requires 'AnyEvent::Socket' => 0;
requires 'Mojo' => '0.7';
requires 'AnyEvent::Mojo' => 0;
requires 'Params::Validate' => 0;
requires 'Config::Any' => 0;
requires 'Getopt::Long' => 0;

build_requires 'Test::More';

WriteAll;

