#! /usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::Mojo;

use FrfBot::Test;

my $t = get_test_frfbot();

send_to_bot($t, 'takoe');
like(bot_sent($t), qr/Сначала сюда нужно подключить/);

done_testing;
