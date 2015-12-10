#! /usr/bin/perl
use Test::More;
use Test::Mojo;

use FindBin;
require "$FindBin::Bin/../src/frfbot.pl";

my $t = Test::Mojo->new;

$t->get_ok('/')
    ->status_is(200);

done_testing;
