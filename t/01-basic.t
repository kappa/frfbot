#! /usr/bin/perl
use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('FrfBot');

$t->get_ok('/')
    ->status_is(200);

done_testing;
