#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'App::Rasputine' );
}

diag( "Testing App::Rasputine $App::Rasputine::VERSION, Perl $], $^X" );
