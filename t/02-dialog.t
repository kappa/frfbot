#! /usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::Mojo;

use FrfBot::Test;

my $t = get_test_frfbot();

send_to_bot($t, 'takoe')
    ->status_is(200);

done_testing;
