#!/usr/bin/env perl
use Mojolicious::Lite;
use WWW::Telegram::BotAPI;
use Mojo::Redis2;

our $VERSION = '1.1';

use lib::abs '.';
use Handlers;

plugin 'Config' => { file => '../conf/frfbot.conf' };

helper botapi => sub {
	shift->stash->{botapi}
		||= WWW::Telegram::BotAPI->new(
			token		=> app->config->{telegram_bot_token},
			async		=> 1,
		)
};

my $webhook_uri = "/bot-" . app->config->{telegram_bot_token};
post $webhook_uri => sub {
	my $c = shift;
	app->log->debug("[webhook] incoming " . $c->req->to_string);

	handle_bot_update($c);

	$c->render(json => { ok => 1 });
};

get "/status" => sub {
	shift->render(text => "İyiyim");
};

get '/setwh' => sub {
	my $c = shift;

	app->log->debug("call setWebhook");
	unless ($c->tx->remote_address eq '127.0.0.1') {
		$c->render(text => 'Yasak');
		return;
	}

	$c->botapi->setWebhook({
		url			=> app->config->{webhook_url_start} . $webhook_uri,
		certificate	=> {
			file	=> 'conf/https_public_cert.pem',
		},
	}, sub {
		my ($ua, $tx) = @_;
		app->log->debug("setWH callback: " . $tx->res->to_string);
	});
};

any '/*' => sub {
	shift->render(text => 'yok');
};

helper redis => sub { shift->stash->{redis} ||= Mojo::Redis2->new; };

app->secrets(app->config->{secrets}) if app->config->{secrets};
app->start;
