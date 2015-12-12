requires 'Mojolicious::Lite';
requires 'WWW::Telegram::BotAPI';
requires 'Ubic';
requires 'Ubic::Service::Hypnotoad';
requires 'EV';
requires 'Net::DNS::Native';
requires 'lib::abs';
requires 'Protocol::Redis::XS';
requires 'Mojo::Redis2';

on 'develop' => sub {
	requires 'Rex';
	requires 'Expect';
	requires 'Test::MockObject';
	requires 'IO::All';
}
