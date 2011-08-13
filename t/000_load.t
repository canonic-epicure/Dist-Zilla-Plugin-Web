use strict;
use warnings;
use Test::More 0.88;

BEGIN {
	use_ok( 'Dist::Zilla::Plugin::NPM' );
	use_ok( 'Dist::Zilla::Plugin::NPM::Bundle' );
}

done_testing;