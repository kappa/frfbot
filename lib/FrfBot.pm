package FrfBot;
use Mojo::Base 'Mojolicious';

our $VERSION = '1.4';

use WWW::Telegram::BotAPI;
use Mojo::Redis2;

sub startup {
    my $self = shift;

    $self->plugin('Config' => { file => 'conf/frfbot.conf' });
    $self->secrets($self->config->{secrets}) if $self->config->{secrets};

    $self->helper(botapi => sub {
        state $botapi = WWW::Telegram::BotAPI->new(
            token		=> $self->config->{telegram_bot_token},
            async		=> 1,
        )
    });
    $self->helper(redis => sub {
        state $redis = Mojo::Redis2->new(url => $self->config->{redis_url});
    });

    $self->config->{webhook_uri} = '/bot-' . $self->config->{telegram_bot_token};

    my $r = $self->routes;
    # ============================================================
    $r->get('/setwh')     ->to('telegram#set_webhook');
    $r->post($self->config->{webhook_uri})->to('telegram#handle');

    $r->get('/status'           => sub { shift->render(text => 'İyiyim') });
    $r->any('*w' => { w => '' } => sub { shift->render(text => 'yok') });
}

1;
