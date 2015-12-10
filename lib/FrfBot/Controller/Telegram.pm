package FrfBot::Controller::Telegram;
use Mojo::Base 'Mojolicious::Controller';

use Handlers;

sub handle {
    my $self = shift;
    $self->app->log->debug("[webhook] incoming " . $self->req->to_string);

    handle_bot_update($self);

    $self->render(json => { ok => 1 });
}

sub set_webhook {
    my $self = shift;

    $self->app->log->debug("call setWebhook");
    unless ($self->tx->remote_address eq '127.0.0.1') {
        $self->render(text => 'Yasak');
        return;
    }

    $self->botapi->setWebhook({
        url			=> $self->app->config->{webhook_url_start} . $webhook_uri,
        certificate	=> {
            file	=> 'conf/https_public_cert.pem',
        },
    }, sub {
        my ($ua, $tx) = @_;
        $self->app->log->debug("setWH callback: " . $tx->res->to_string);
        $self->render(text => $tx->res->to_string);
    });
}

1;
