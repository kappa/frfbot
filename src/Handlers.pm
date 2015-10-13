package Handlers;
use utf8;

use Exporter 'import';

our @EXPORT = qw/handle_bot_update/;

use Mojo::JSON qw/encode_json decode_json/;
use Mojo::Util qw/url_escape/;

# states;
# logged_off, logged_in
# login_start, login_have_user
# posting

sub say_simple {
	my ($c, $chat_id, $text) = @_;

	$c->botapi->sendMessage({
		chat_id		=> $chat_id,
		text		=> $text,
	},
	sub {
		my ($ua, $tx) = @_;
		$c->app->log->debug("[handle] say_simple succesful");
	});
}

sub handle_bot_update {
	my $c = shift;

	my $message = $c->req->json->{message};

	my $link = $c->redis->get($message->{chat}->{id});
	$link = $link ? decode_json($link) : { state => 'logged_off' };

	$c->app->log->debug("[handle] for $message->{chat}->{id} found " . encode_json($link));

	my $state_handler = \&{"state_$link->{state}"};
	&$state_handler($c, $message, $link);
}

sub botan_report {
	my ($c, $message, $event) = @_;

	return unless $c->config->{appmetrica_token};

	$c->app->log->debug("[botan] event $event");
	my $tx = $c->ua->post("https://api.botan.io/track"
			. "?token=" . $c->config->{appmetrica_token}
			. "&uid=" . ($c->config->{appmetrica_uid_mask} ^ (0+$message->{from}->{id}))
			. "&name=" . url_escape($event)
		=> json
		=> {
			message_id => $message->{message_id},
		}
		=> sub {
			my ($ua, $tx) = @_;
			$c->app->log->debug("[botan] botanIO req: " . $tx->req->to_string);
			$c->app->log->debug("[botan] botanIO resp: " . $tx->res->to_string);
			if ($tx->res->json->{status} ne 'accepted') {
				$c->app->log->debug("[botan] botanIO ERROR: " . $tx->res->to_string);
			}
		}
	);
}

sub state_logged_off {
	my ($c, $message, $link) = @_;

	my $chat_id = $message->{chat}->{id};

	if ($message->{text} eq '/login') {
		say_simple($c, $chat_id, "Отлично, давайте начнём. Сначала скажите мне свой логин во FreeFeed.");
		$link->{state} = 'login_start';
		$c->app->log->debug("[handle] state_logged_off before saving state for $chat_id, obj = " . encode_json($link));
		$c->redis->set($chat_id => encode_json($link));
		$c->app->log->debug("[handle] state_logged_off after saving state");
	}
	else {
		say_simple($c, $chat_id, "Привет! Сначала сюда нужно подключить ваш аккаунт во FreeFeed. Это нужно сделать всего один раз, и вам точно будет удобнее не с телефона, а на компьютере, например через веб-интерфейс https://web.telegram.org. Чтобы начать подключение, используйте команду /login.");
	}

	botan_report($c, $message, 'before_login');
}

sub state_login_start {
	my ($c, $message, $link) = @_;

	my $text = $message->{text};
	my $chat_id = $message->{chat}->{id};

	if ($text =~ /^[a-z0-9_]+$/ && length($text) < 50) {
		say_simple($c, $chat_id, qq{Очень хорошо, $text. Теперь сложный, зато последний шаг. Скопируйте сюда свой секретный токен. Его можно узнать на странице https://freefeed.net/settings, предварительно включив опцию "Enable BetterFeed"});
		$link->{state} = 'login_have_user';
		$link->{user} = $text;
		$c->redis->set($chat_id, encode_json($link));
	}
	else {
		say_simple($c, $chat_id, "Не очень похоже на логин. Попробуйте ещё разок.");
	}
}

sub state_login_have_user {
	my ($c, $message, $link) = @_;

	my $text = $message->{text};
	my $chat_id = $message->{chat}->{id};

	if ($text =~ /^[.a-zA-Z0-9_-]+$/ && length($text) < 500) {
		say_simple($c, $chat_id, "Круто. Для проверки напишите какой-нибудь пост.");
		$link->{state} = 'logged_in';
		$link->{token} = $text;
		$c->redis->set($chat_id, encode_json($link));
		botan_report($c, $message, 'login');
	}
	else {
		say_simple($c, $chat_id, "Не очень похоже на токен. Попробуйте ещё раз.");
	}
}

sub state_logged_in {
	my ($c, $message, $link) = @_;

	my $text = $message->{text};
	my $chat_id = $message->{chat}->{id};

	if ($text =~ /^\/logout$/) {
		$link->{state} = 'logged_off';
		delete $link->{token};
		delete $link->{user};
		$c->redis->set($chat_id, encode_json($link));
		say_simple($c, $chat_id, "Забываю ваш токен... Вот, уже всё забыл.");
		botan_report($c, $message, 'logout');
	}
	elsif (length($text) > 10000) {
		say_simple($c, $chat_id, "Очень длинно, не надо так.");
	}
	else {
		my $tx = $c->ua->post('https://freefeed.net/v1/posts'
			=> { 'X-Authentication-Token' => $link->{token} }
			=> json
			=> {
				post => { body	=> $text },
				meta => { feeds => $link->{user} },
			}
			=> sub {
				my ($ua, $tx) = @_;
				if ($tx->res->code == 200 && (my $post_id = $tx->res->json->{posts}->{id})) {
					$c->botapi->sendMessage({
						chat_id		=> $chat_id,
						reply_to_message_id => $message->{message_id},
						text		=> "Готово, смотрите в https://m.freefeed.net/$link->{user}/$post_id",
					},
					sub {
						my ($ua, $tx) = @_;
						$c->app->log->debug("[handle] sendMSG w/ reply success");
					});
					botan_report($c, $message, 'message');
				}
				else {
					$c->botapi->sendMessage({
						chat_id		=> $chat_id,
						reply_to_message_id => $message->{message_id},
						text		=> "Что-то пошло не так, я не смог это запостить",
					},
					sub {
						my ($ua, $tx) = @_;
						$c->app->log->debug("[handle] sendMSG w/ reply ERROR: " . $tx->res->to_string);
					});
					botan_report($c, $message, 'message_error');
				}
			},
		);
	}
}

1;
