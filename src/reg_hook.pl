#!/usr/bin/env perl
use Mojolicious::Lite;
use WWW::Telegram::BotAPI;

use lib::abs '.';
use Handlers;

my $cfg = plugin 'Config'
	=> { file => '../conf/frfbot.conf' };
my $webhook_uri = "/bot-" . $cfg->{telegram_bot_token};

my $bot_api = WWW::Telegram::BotAPI->new(
	token		=> $cfg->{telegram_bot_token},
	async		=> 1,
);

get '/setwh' => sub {
	app->log->debug("call setWebhook");
	$bot_api->setWebhook({
		url			=> $cfg->{webhook_url_start} . $webhook_uri,
		certificate	=> {
			file	=> '../conf/https_public_cert.pem',
		},
	}, sub {
		my ($ua, $tx) = @_;

		app->log->debug("setWH callback: " . $tx->res->to_string);
	});
};

app->start;
