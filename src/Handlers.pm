package Handlers;
use utf8;
use strict;
use warnings;

use Exporter 'import';

our @EXPORT = qw/handle_bot_update/;

use Mojo::JSON qw/encode_json decode_json/;
use Mojo::Util qw/url_escape/;
use Mojo::IOLoop;

# states;
# logged_off, logged_in
# login_start, login_have_user
# posting

sub say_simple {
	my ($c, $chat_id, $text, %options) = @_;

	$c->botapi->sendMessage({
		chat_id		=> $chat_id,
		text		=> $text,
		($options{force_reply}
			? (reply_markup => '{"force_reply":true}')	# API requires JSON str here!
			: ()),
	},
	sub {
		my ($ua, $tx) = @_;
		$c->app->log->debug("[handle] say_simple succesful: " . $tx->res->to_string);
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
		say_simple($c, $chat_id, "Отлично, давайте начнём. Сначала скажите мне свой логин во FreeFeed.", force_reply => 1);
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
		say_simple($c, $chat_id, qq{Очень хорошо, $text. Теперь сложный, зато последний шаг. Скопируйте сюда свой секретный токен. Его можно узнать на странице https://freefeed.net/settings с помощью ссылки "show access token", предварительно включив опцию "Enable BetterFeed".}, force_reply => 1);
		$link->{state} = 'login_have_user';
		$link->{user} = $text;
		$c->redis->set($chat_id, encode_json($link));
	}
	else {
		say_simple($c, $chat_id, "Не очень похоже на логин. Попробуйте ещё разок.", force_reply => 1);
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
		say_simple($c, $chat_id, "Не очень похоже на токен. Попробуйте ещё раз.", force_reply => 1);
	}
}

sub upload_attachment {
	my ($c, $link, $get_file, $file_name, $cb) = @_;
	my $att_id;

	my $get_url = 'https://api.telegram.org/file/bot'
		. $c->config->{telegram_bot_token}
		. "/$get_file->{file_path}";

	$c->app->log->debug("[files] downloading: " . $get_url);

	my $get_tx = $c->ua->get($get_url);
	if ($get_tx->success) {
		$c->app->log->debug("[files] uploading");
		my $post_tx = $c->ua->post('https://freefeed.net/v1/attachments'
			=> { 'X-Authentication-Token' => $link->{token} }
			=> form
			=>
			{
				name => 'attachment[file]',
				'attachment[file]' => {
					file	=> $get_tx->res->content->asset,
					($file_name ? (filename => $file_name) : ()),
					# mimetype
				},
			}
		);
		if ($post_tx->success) {
			$c->app->log->debug("[files] successful upload: " . $post_tx->res->to_string);
			$c->app->log->debug("[files] successful upload req was: " . $post_tx->req->to_string);
			$att_id = $post_tx->res->json->{attachments}->{id};
		}
		else {
			$c->app->log->debug("[files] uploading FAILED: " .  $post_tx->res->to_string);
		}
	}
	else {
		$c->app->log->debug("[files] download FAILED: " . $get_tx->res->to_string);
	}
	$cb->($att_id);
}

sub prepare_files {
	my ($c, $message, $link, $cb) = @_;

	my @rv;
	my @files;

	if (my $photos = $message->{photo}) {
		push @files, [$photos->[-1]->{file_id}, undef];
	}

	foreach my $type (qw/voice audio sticker document video/) {
		if (my $file = $message->{$type}) {
			push @files, [$file->{file_id}, $file->{file_name}];
		}
	}

	unless (@files) {
		$cb->();
		return;
	};

	$c->app->log->debug("[files] found files: " . encode_json(\@files));

	Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			foreach my $file (@files) {
				my $end = $delay->begin(0);

				$c->botapi->getFile({
					file_id => $file->[0],
				}, sub {
					my ($ua, $tx) = @_;

					if ($tx->success && $tx->res->json->{ok}) {
						upload_attachment($c, $link, $tx->res->json->{result}, $file->[1], $end);
					}
					else {
						$c->app->log->debug("[files] getFile error: " .  $tx->res->to_string);
						$end->();
					}
				});
			}
		},
		sub {
			my $delay = shift;
			$c->app->log->debug("[files] rv ready, calling cb: " . encode_json(\@_));
			$cb->(@_);
		}
	);
}

sub conjure_text {
	my $message = shift;

	my $file;
	if ($message->{caption}) {
		return $message->{caption};
	}

	if ($message->{photo}) {
		$file = $message->{photo}->[-1];
		return 'image ' . $file->{width} . 'x' . $file->{height} . ($file->{file_size} ? " $file->{file_size} bytes" : '');
	}

	if ($message->{video}) {
		$file = $message->{video};
		return 'video ' . $file->{width} . 'x' . $file->{height} . ' ' . $file->{duration} . 's';
	}

	if ($message->{voice}) {
		$file = $file->{voice};
		return 'voice ' . $file->{duration} . 's';
	}

	if ($message->{audio}) {
		$file = $file->{audio};
		return ($file->{performer} ? "$file->{performer} - " : '')
			. ($file->{title} // 'Audio Track')
			. ' ' . $file->{duration} . 's'
			. ($file->{file_size} ? " $file->{file_size} bytes" : '');
	}

	if ($message->{sticker}) {
		$file = $message->{sticker};
		return 'sticker ' . $file->{width} . 'x' . $file->{height} . ($file->{file_size} ? " $file->{file_size} bytes" : '');
	}

	if ($message->{document}) {
		$file = $message->{document};
		return ($file->{file_name} // $file->{mime_type} // 'document') . ($file->{file_size} ? " $file->{file_size} bytes" : '');
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
	elsif ($text =~ /^\/to\s*(?<dest>.*)$/) {
		if (!$+{dest}) {
			say_simple($c, $chat_id, "Команда /to без параметров пока не работает.");
		}
		else {
			$link->{to} = [ split /[, ]+/, $+{dest} ];
			$c->redis->set($chat_id, encode_json($link));
			say_simple($c, $chat_id, "Следующее сообщение будет отправлено в: " . join(', ', @{$link->{to}}));
		}
		botan_report($c, $message, 'to');
	}
	elsif (length($text) > 10000) {
		say_simple($c, $chat_id, "Очень длинно, не надо так.");
	}
	else {
		Mojo::IOLoop->delay(
			sub {
				my $delay = shift;
				prepare_files($c, $message, $link, $delay->begin(0));
			},
			sub {
				my $delay = shift;

				my @attachments = @_;
				$c->app->log->debug("[files] files prepared: " . encode_json(\@attachments));

				$text //= conjure_text($message);

				my $tx = $c->ua->post('https://freefeed.net/v1/posts'
					=> { 'X-Authentication-Token' => $link->{token} }
					=> json
					=> {
						post => {
							body => $text,
							(@attachments
								? ( attachments => \@attachments )
								: ()
							),
						},
						meta => { feeds => $link->{to} || $link->{user} },
					}
					=> sub {
						my ($ua, $tx) = @_;
						if ($tx->res->code == 200 && (my $post_id = $tx->res->json->{posts}->{id})) {
							my $url_group = $link->{user};
							if ($link->{to}) {
								$url_group = $link->{to}->[0];
								delete $link->{to};
								$c->redis->set($chat_id, encode_json($link));
							}

							$c->botapi->sendMessage({
								chat_id		=> $chat_id,
								reply_to_message_id => $message->{message_id},
								text		=> "Готово, смотрите в https://m.freefeed.net/$url_group/$post_id",
							},
							sub {
								my ($ua, $tx) = @_;
								$c->app->log->debug("[handle] sendMSG w/ reply success");
							});
							botan_report($c, $message, 'message');
						}
						else {
							$c->app->log->debug("[handle] post error: " . $tx->res->to_string);
							$c->app->log->debug("[handle] req was: " . $tx->req->to_string);
							botan_report($c, $message, 'message_error');

							$c->botapi->sendMessage({
								chat_id		=> $chat_id,
								reply_to_message_id => $message->{message_id},
								text		=> "Что-то пошло не так, я не смог это запостить",
							}, sub { });
						}
					},
				);
			},
		);
	}
}

1;
