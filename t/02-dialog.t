#! /usr/bin/perl
use strict;
use warnings;
use utf8;
use Test::More;
use Test::Mojo;

use FrfBot::Test;

bot_responds('takoe', 'Сначала сюда нужно подключить');

bot_responds('/freefeed', 'скажите мне свой логин во FreeFeed');

bot_responds('tes ter', 'Не очень похоже на логин');

bot_responds('tester', 'Теперь сложный, зато последний шаг');

bot_responds('freefeed token', 'Не очень похоже');

bot_responds('freefeed-token', 'Круто. Для проверки напишите какой-нибудь пост.');

bot_responds('/logout', 'уже забыл');

bot_responds('/mokum', 'скажите мне свой логин в Mokum');

bot_responds('tester', 'Его можно создать на странице https://mokum.place/settings/apitokens');

bot_responds('mokum-token', 'Не очень похоже на токен');

bot_responds('1234abde', 'Круто. Для проверки напишите какой-нибудь пост.');

bot_responds('/login', 'скажите мне свой логин во FreeFeed');

send_to_bot('tester');
send_to_bot('freefeed-token');

send_to_bot('this is a post to both');
ok(
       $FrfBot::Test::BOT_MESSAGES[-1]->{text} =~ 'Готово, смотрите в https://m.freefeed'
    && $FrfBot::Test::BOT_MESSAGES[-2]->{text} =~ 'Готово, смотрите в https://mokum.place'
    ||
       $FrfBot::Test::BOT_MESSAGES[-2]->{text} =~ 'Готово, смотрите в https://m.freefeed'
    && $FrfBot::Test::BOT_MESSAGES[-1]->{text} =~ 'Готово, смотрите в https://mokum.place'
    , 'posted to both'
);

done_testing;
