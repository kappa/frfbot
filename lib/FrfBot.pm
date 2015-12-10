package FrfBot;
use Mojo::Base 'Mojolicious';

our $VERSION = '1.2';

use WWW::Telegram::BotAPI;
use Mojo::Redis2;

use Handlers;

sub startup {
    my $self = shift;

    $self->plugin('Config' => { file => './conf/frfbot.conf' });
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

    my $webhook_uri = "/bot-" . $self->config->{telegram_bot_token};

    my $r = $self->routes;

    $r->post($webhook_uri => sub {
        my $c = shift;
        $self->log->debug("[webhook] incoming " . $c->req->to_string);

        handle_bot_update($c);

        $c->render(json => { ok => 1 });
    });

    $r->get("/status" => sub {
        shift->render(text => "İyiyim");
    });

    $r->get('/setwh' => sub {
        my $c = shift;

        $self->log->debug("call setWebhook");
        unless ($c->tx->remote_address eq '127.0.0.1') {
            $c->render(text => 'Yasak');
            return;
        }

        $c->botapi->setWebhook({
            url			=> $self->config->{webhook_url_start} . $webhook_uri,
            certificate	=> {
                file	=> 'conf/https_public_cert.pem',
            },
        }, sub {
            my ($ua, $tx) = @_;
            $self->log->debug("setWH callback: " . $tx->res->to_string);
            $c->render(text => $tx->res->to_string);
        });
    });

    $r->any('*w' => { w => '' } => sub {
        shift->render(text => 'yok');
    });
}

1;
