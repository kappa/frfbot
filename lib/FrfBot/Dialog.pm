package FrfBot::Dialog;
use utf8;
use strict;
use warnings;

use Mojo::JSON qw/encode_json decode_json/;
use Mojo::Util qw/url_escape/;
use Mojo::IOLoop;

use Moo;
use namespace::clean;

# states;
# logged_off (no services)
# ready_to_post
# login_start, login_have_user
# mokum_start, mokum_have_user

# todo:
# in_post

my $DISPATCH = {
	logout		=> qr/.*/,
	mokum		=> qr/^(logged_off|ready_to_post)$/,
	login		=> qr/^(logged_off|ready_to_post)$/,
	freefeed	=> qr/^(logged_off|ready_to_post)$/,
};

has c => (
	is => 'ro',
	required => 1,
);

has storage => (
	is => 'rw',
	lazy => 1,
	builder => sub {
		my $obj = $_[0]->c->redis->get($_[0]->chat_id);
		return $obj ? decode_json($obj) : { state => 'logged_off' };
	},
);

has _botapi => (
	is => 'ro',
	lazy => 1,
	builder => sub { $_[0]->c->botapi },
	handles => {
		botapi_send => 'sendMessage',
		botapi_file => 'getFile',
	},
);

has _log => (
	is => 'ro',
	lazy => 1,
	builder => { $_[0]->c->app->log },
	handles => ['debug'],
);

sub chat_id { $_[0]->message->{chat}->{id} };
sub message { $_[0]->c->req->json->{message} };
sub text { $_[0]->message->{text} };
sub state { $_[0]->storage->{state} };

sub update_state {
	my ($self, $new_state) = @_;
	$self->state = $new_state if $new_state;

	$self->c->redis->set($self->chat_id, encode_json($self->storage));
}

sub say_simple {
	my ($self, $text, %options) = @_;

	$self->botapi_send({
		chat_id		=> $self->chat_id,
		text		=> $text,
		($options{force_reply}
			? (reply_markup => '{"force_reply":true}')	# API requires JSON str here!
			: ()),
	});
}

sub handle_update {
	my $self = shift;

	# upgrade from old scheme
	if ($self->state eq 'logged_in') {
		$self->update_state('ready_to_post');
	}

	$self->debug('chat: ' . $self->chat_id . ' stored: ' . encode_json($self->storage));

	# dispatch on command and state
	if ($self->text =~ m{^ /(?<command>\S+)}x) {
		my $command = $+{command};
		$self->debug("dispatching command: $command");
		if ($DISPATCH->{$command} && $self->state =~ $DISPATCH->{$command}) {
			my $command_handler = \&{"command_$command"};
			return $self->$command_handler();
		}
		else {
			$self->say_simple('Неверная команда.');
			return;
		}
	}
	else {
		# no command found
		$self->state_ready_to_post();
	}
}

sub command_logout {
	my $self = shift;

	delete @{$self->storage}{qw/token user mokum_user mokum_token/};
	$self->update_state('logged_off');

	$self->say_simple('Забываю все ваши токены... Вот, уже забыл.');

	$self->botan_report('logout');
}

sub command_mokum {
	my $self = shift;

	$self->say_simple('Отлично, давайте начнём. Сначала скажите мне свой логин в Mokum.', force_reply => 1);
	$self->update_state('mokum_start');

	$self->debug('command_mokum processed for ' . $self->chat_id . ' storage = ' . encode_json($self->storage));
}

sub command_login {
	# backwards compatibility
	goto &command_freefeed;
}

sub command_freefeed {
	my $self = shift;

	$self->say_simple('Отлично, давайте начнём. Сначала скажите мне свой логин во FreeFeed.', force_reply => 1);
	$self->update_state('login_start');

	$self->debug('command_login processed for ' . $self->chat_id . ' storage = ' . encode_json($self->storage));
}

sub state_mokum_start {
	my $self = shift;

	my $text = $self->text;
	if ($text =~ /^[a-z0-9_]+$/ && length($text) < 50) {
		$self->say_simple(qq{Очень хорошо, $text. Теперь сложный, зато последний шаг. Скопируйте сюда свой секретный токен. Его можно создать на странице https://mokum.place/settings/apitokens.}, force_reply => 1);
		$self->storage->{mokum_user} = $text;
		$self->update_state('mokum_have_user');
	}
	else {
		$self->say_simple('Не очень похоже на логин. Попробуйте ещё разок.', force_reply => 1);
	}
}

sub state_mokum_have_user {
	my $self = shift;

	my $text = $self->text;

	if ($text =~ /^[a-f0-9-]+$/ && length($text) < 100) {
		$self->say_simple('Круто. Для проверки напишите какой-нибудь пост.');
		$self->storage->{mokum_token} = $text;
		$self->update_state('ready_to_post');

		$self->botan_report('mokum');
	}
	else {
		$self->say_simple('Не очень похоже на токен. Попробуйте ещё раз.', force_reply => 1);
	}
}

sub botan_report {
	my ($self, $event) = @_;

	return unless $self->c->config->{appmetrica_token};

	$self->debug("[botan] event $event");
	my $tx = $self->c->ua->post("https://api.botan.io/track"
			. "?token=" . $self->c->config->{appmetrica_token}
			. "&uid=" . ($self->c->config->{appmetrica_uid_mask} ^ (0+$self->message->{from}->{id}))
			. "&name=" . url_escape($event)
		=> json
		=> {
			message_id => $self->message->{message_id},
		}
		=> sub {
			my ($ua, $tx) = @_;
			$self->debug("[botan] botanIO req: " . $tx->req->to_string);
			if ($tx->res->json->{status} ne 'accepted') {
				$self->debug("[botan] botanIO ERROR: " . $tx->res->to_string);
			}
		}
	);
}

sub state_logged_off {
	my $self = shift;

	$self->say_simple('Привет! Сначала сюда нужно подключить ваш аккаунт во FreeFeed и/или Mokum. Это делается всего один раз, и вам точно будет удобнее не с телефона, а на компьютере, например через веб-интерфейс https://web.telegram.org или с помощью десктопного клиента Telegram. Для подключения соответствующих сервисов используйте команды /freefeed или /mokum.');

	$self->botan_report('before_login');
}

sub state_login_start {
	my $self = shift;

	my $text = $self->text;

	if ($text =~ /^[a-z0-9_]+$/ && length($text) < 50) {
		$self->say_simple(qq{Очень хорошо, $text. Теперь сложный, зато последний шаг. Скопируйте сюда свой секретный токен. Его можно узнать на странице https://freefeed.net/settings с помощью ссылки "show access token", предварительно включив опцию "Enable BetterFeed".}, force_reply => 1);
		$self->storage->{user} = $text;
		$self->update_state('login_have_user');
	}
	else {
		$self->say_simple('Не очень похоже на логин. Попробуйте ещё разок.', force_reply => 1);
	}
}

sub state_login_have_user {
	my $self = shift;

	my $text = $self->text;

	if ($text =~ /^[.a-zA-Z0-9_-]+$/ && length($text) < 500) {
		$self->say_simple('Круто. Для проверки напишите какой-нибудь пост.');
		$self->storage->{token} = $text;
		$self->update_state('ready_to_post');

		$self->botan_report('login');
	}
	else {
		$self->say_simple('Не очень похоже на токен. Попробуйте ещё раз.', force_reply => 1);
	}
}

sub upload_attachment {
	my $self = shift;
	my ($get_file, $file_name, $cb) = @_;
	my $att_id;

	my $get_url = 'https://api.telegram.org/file/bot'
		. $self->c->config->{telegram_bot_token}
		. "/$get_file->{file_path}";

	$self->debug("[files] downloading: " . $get_url);

	my $get_tx = $self->c->ua->get($get_url);
	if ($get_tx->success) {
		$self->debug("[files] uploading");
		my $post_tx = $self->c->ua->post('https://freefeed.net/v1/attachments'
			=> { 'X-Authentication-Token' => $self->storage->{token} }
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
			$self->debug("[files] successful upload: " . $post_tx->res->to_string);
			$self->debug("[files] successful upload req was: " . $post_tx->req->to_string);
			$att_id = $post_tx->res->json->{attachments}->{id};
		}
		else {
			$self->debug("[files] uploading FAILED: " .  $post_tx->res->to_string);
		}
	}
	else {
		$self->debug("[files] download FAILED: " . $get_tx->res->to_string);
	}
	$cb->($att_id);
}

sub prepare_files {
	my ($self, $cb) = @_;

	my @rv;
	my @files;

	if (my $photos = $self->message->{photo}) {
		push @files, [$photos->[-1]->{file_id}, undef];
	}

	foreach my $type (qw/voice audio sticker document video/) {
		if (my $file = $self->message->{$type}) {
			push @files, [$file->{file_id}, $file->{file_name}];
		}
	}

	unless (@files) {
		$cb->();
		return;
	};

	$self->debug("[files] found files: " . encode_json(\@files));

	Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			foreach my $file (@files) {
				my $end = $delay->begin(0);

				$self->botapi_file({
					file_id => $file->[0],
				}, sub {
					my ($ua, $tx) = @_;

					if ($tx->success && $tx->res->json->{ok}) {
						$self->upload_attachment($tx->res->json->{result}, $file->[1], $end);
					}
					else {
						$self->debug("[files] getFile error: " .  $tx->res->to_string);
						$end->();
					}
				});
			}
		},
		sub {
			my $delay = shift;
			$self->debug("[files] rv ready, calling cb: " . encode_json(\@_));
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
		$file = $message->{voice};
		return 'voice ' . $file->{duration} . 's';
	}

	if ($message->{audio}) {
		$file = $message->{audio};
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

sub state_ready_to_post {
	my $self = shift;

	my $text = $self->text // '';

	if ($text =~ /^\/to(?<plus>\+?)\s*(?<dest>.*)$/) {
		if (!$+{dest}) {
			$self->say_simple('Команда /to без параметров пока не работает.');
		}
		else {
			if ($+{plus}) {
				$self->storage->{to} //= [ $self->storage->{user} ];
				push @{$self->storage->{to}}, split(/[, ]+/, $+{dest});
			}
			else {
				$self->storage->{to} = [ split(/[, ]+/, $+{dest}) ];
			}
			$self->update_state();

			$self->say_simple('Следующее сообщение будет отправлено в: ' . join(', ', @{$self->storage->{to}}));
		}

		$self->botan_report('to');
	}
	elsif (length($text) > 10000) {
		$self->say_simple('Очень длинно, не надо так.');
	}
	else {
		if ($self->storage->{token}) {
			$self->_post_to_freefeed();
		}
		if ($self->storage->{mokum_token}) {
			$self->_post_to_mokum();
		}
	}
}

sub _post_to_freefeed {
	my $self = shift;

	Mojo::IOLoop->delay(
		sub {
			my $delay = shift;
			$self->_prepare_files($delay->begin(0));
		},
		sub {
			my $delay = shift;

			my @attachments = @_;
			$self->debug("[files] files prepared: " . encode_json(\@attachments));

			my $text = $self->text ne '' ? $self->text : conjure_text($self->message);

			my $tx = $self->c->ua->post('https://freefeed.net/v1/posts'
				=> { 'X-Authentication-Token' => $self->storage->{token} }
				=> json
				=> {
					post => {
						body => $text,
						(@attachments
							? ( attachments => \@attachments )
							: ()
						),
					},
					meta => { feeds => $self->storage->{to} || $self->storage->{user} },
				}
				=> sub {
					my ($ua, $tx) = @_;
					if ($tx->res->code == 200 && (my $post_id = $tx->res->json->{posts}->{id})) {
						my $url_group = $self->storage->{user};
						if ($self->storage->{to}) {
							$url_group = $self->storage->{to}->[0];
							delete $self->storage->{to};
							$self->update_state();
						}

						$self->botapi_send({
							chat_id		=> $self->chat_id,
							reply_to_message_id => $self->message->{message_id},
							text		=> "Готово, смотрите в https://m.freefeed.net/$url_group/$post_id",
						},
						sub {
							my ($ua, $tx) = @_;
							$self->debug("[handle] sendMSG w/ reply success");
						});
						$self->botan_report('message');
					}
					else {
						$self->debug("[handle] post error: " . $tx->res->to_string);
						$self->debug("[handle] req was: " . $tx->req->to_string);
						$self->botan_report('message_error');

						$self->botapi_send({
							chat_id		=> $self->chat_id,
							reply_to_message_id => $self->message->{message_id},
							text		=> "Что-то пошло не так, я не смог это запостить",
						}, sub { });
					}
				},
			);
		},
	);
}


sub post_to_mokum {
	my $self = shift;

	my $tx = $self->c->ua->post('https://mokum.place/api/v1/posts.json'
		=> { 'X-API-Token' => $self->storage->{mokum_token} }
		=> json
		=> {
			post => {
				text		=> $self->text,
				timelines	=> [ 'user' ],
			},
		}
		=> sub {
			my ($ua, $tx) = @_;
			if ($tx->res->code == 200 && (my $post_id = $tx->res->json->{post}->{id})) {
				my $url_group = $self->storage->{mokum_user};

				delete $self->storage->{to};
				$self->update_state();

				$self->botapi_send({
					chat_id		=> $self->chat_id,
					reply_to_message_id => $self->message->{message_id},
					text		=> "Готово, смотрите в https://mokum.place/$url_group/$post_id",
				},
				sub {
					my ($ua, $tx) = @_;
					$self->debug("[handle] sendMSG w/ reply success");
				});
				$self->botan_report('message');
			}
			else {
				$self->debug("[handle] post error: " . $tx->res->to_string);
				$self->debug("[handle] req was: " . $tx->req->to_string);
				$self->botan_report('message_error');

				$self->botapi_send({
					chat_id		=> $self->chat_id,
					reply_to_message_id => $self->message->{message_id},
					text		=> "Что-то пошло не так, я не смог это запостить в Mokum",
				}, sub { });
			}
		},
	);
}

1;
