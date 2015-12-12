package FrfBot::Test;
use strict;
use warnings;
use v5.10;

use base 'Exporter';
our @EXPORT = qw/get_test_frfbot send_to_bot bot_sent/;

use File::Temp qw/tempdir/;
use IO::All;
use Test::MockObject;

my $TESTING_TOKEN = 'testing-token';

sub get_test_frfbot {
    my $cfg = io('conf/frfbot.conf.tmpl')->slurp;
    $cfg =~ s/Talk to.*'/$TESTING_TOKEN'/;

    my $test_home_dir = tempdir(CLEANUP => 1);
    mkdir("$test_home_dir/conf");
    io("$test_home_dir/conf/frfbot.conf")->print($cfg);

    $ENV{MOJO_HOME} = $test_home_dir;
    my $ua = Test::Mojo->new('FrfBot');

    $ua->app->helper(botapi => sub {
        state $botapi = create_mock_botapi();
    });

    return $ua;
}

sub send_to_bot {
    my ($ua, $text) = @_;

    my $message = {
        message => {
            chat => {
                id => 'test-chat-id',
            },
            text => $text,
        },
    };

    return $ua->post_ok("/bot-$TESTING_TOKEN" => json => $message)
        ->status_is(200)->content_type_like(qr{application/json})->json_is({ ok => 1 });
}

our $LAST_BOT_MESSAGE;

sub create_mock_botapi {
    my $botapi = Test::MockObject->new();

    $botapi->mock(sendMessage => sub {
        $LAST_BOT_MESSAGE = $_[1];
    });

    return $botapi;
}

sub bot_sent {
    my $ua = shift;

    return $LAST_BOT_MESSAGE->{text};
}

1;
