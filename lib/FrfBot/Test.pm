package FrfBot::Test;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw/get_test_frfbot send_to_bot/;

use File::Temp qw/tempdir/;
use IO::All;

my $TESTING_TOKEN = 'testing-token';

sub get_test_frfbot {
    my $cfg = io('conf/frfbot.conf.tmpl')->slurp;
    $cfg =~ s/Talk to.*'/$TESTING_TOKEN'/;

    my $test_home_dir = tempdir(CLEANUP => 1);
    mkdir("$test_home_dir/conf");
    io("$test_home_dir/conf/frfbot.conf")->print($cfg);

    $ENV{MOJO_HOME} = $test_home_dir;
    return Test::Mojo->new('FrfBot');
}

sub send_to_bot {
    my ($app, $text) = @_;

    my $message = {
        message => {
            chat => {
                id => 'test-chat-id',
            },
            text => $text,
        },
    };

    return $app->post_ok("/bot-$TESTING_TOKEN" => json => $message);
}

1;
