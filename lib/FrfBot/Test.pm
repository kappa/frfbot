package FrfBot::Test;
use strict;
use warnings;
use v5.10;

use base 'Exporter';
our @EXPORT = qw/get_test_frfbot send_to_bot bot_responds/;

use File::Temp qw/tempdir/;
use IO::All;
use Test::MockObject;
use Test::Mock::Redis;
use Test::More;

my $TESTING_TOKEN = 'testing-token';

my $Test_UA;

sub get_test_frfbot {
    my $cfg = io('conf/frfbot.conf.tmpl')->slurp;
    $cfg =~ s/Talk to.*'/$TESTING_TOKEN'/;

    my $test_home_dir = tempdir(CLEANUP => 1);
    mkdir("$test_home_dir/conf");
    io("$test_home_dir/conf/frfbot.conf")->print($cfg);

    $ENV{MOJO_HOME} = $test_home_dir;
    $Test_UA = Test::Mojo->new('FrfBot');

    $Test_UA->app->helper(botapi => sub {
        state $botapi = create_mock_botapi();
    });

    $Test_UA->app->helper(redis => sub {
        state $redis = Test::Mock::Redis->new();
    });

    $Test_UA->app->helper(ua => sub {
        state $ua = create_mock_ua();
    });

    return $Test_UA;
}

sub send_to_bot {
    my $text = shift;

    my $message = {
        message => {
            chat => {
                id => 'test-chat-id',
            },
            text => $text,
        },
    };

    $Test_UA or get_test_frfbot();

    return $Test_UA->post_ok("/bot-$TESTING_TOKEN" => json => $message)
        ->status_is(200)->content_type_like(qr{application/json})->json_is({ ok => 1 });
}

our @BOT_MESSAGES;

sub create_mock_botapi {
    my $botapi = Test::MockObject->new();

    $botapi->mock(sendMessage => sub {
        push @BOT_MESSAGES, $_[1];
    });

    return $botapi;
}

sub create_mock_ua {
    my $ua = Test::MockObject->new();

    $ua->mock(post => sub {
        my $on_success = pop;
        my $res = Mojo::Message::Response->new();
        $res->parse("HTTP/1.0 200 OK\x0d\x0a");
        $res->parse("Content-Type: application/json\x0d\x0a\x0d\x0a");
        $res->parse('{"posts": {"id": "posted-freefeed-id-test"}, "post": {"id": "posted-mokum-id-test"}}');
        my $tx = Test::MockObject->new()->set_always('res', $res);
        $on_success->($ua, $tx);
    });

    return $ua;
}

sub bot_responds {
    my ($message, $response) = @_;

    push @BOT_MESSAGES, { text => ">sent to bot: [$message]" };
    send_to_bot($message);
    like($BOT_MESSAGES[-1]->{text}, qr/$response/, "correct response to [$message]");
}

1;
