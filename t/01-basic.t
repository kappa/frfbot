#! /usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::Mojo;

use FrfBot::Test;

my $t = get_test_frfbot();

$t->get_ok('/')
    ->content_is('yok')
    ->status_is(200);

$t->get_ok('/status')
    ->content_is('İyiyim')
    ->status_is(200);

done_testing;
