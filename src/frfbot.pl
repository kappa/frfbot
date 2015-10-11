#!/usr/bin/env perl
use Mojolicious::Lite;
use WWW::Telegram::BotAPI;
use Mojo::Redis2;

use lib::abs '.';
use Handlers;

my $cfg = plugin 'Config'
	=> { file => '../conf/frfbot.conf' };
my $webhook_uri = "/bot-" . $cfg->{telegram_bot_token};

my $bot_api = WWW::Telegram::BotAPI->new(
	token		=> $cfg->{telegram_bot_token},
	async		=> 1,
);
helper botapi => sub { shift->stash->{botapi} ||= $bot_api };

post $webhook_uri => sub {
	my $c = shift;
	$c->app->log->debug("[webhook] incoming " . $c->req->to_string);

	handle_bot_update($c);

	$c->render(json => { ok => 1 });
};

get "/status" => sub {
	my $c = shift;
	$c->render(text => "İyiyim");
};

any '/*' => sub {
	render(text => 'yok');
};

helper redis => sub { shift->stash->{redis} ||= Mojo::Redis2->new; };

app->start;
