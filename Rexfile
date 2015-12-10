use Rex -feature => ['1.3'];

# this file contains real test/stage/live environments
require("Rexfile.local");

environment example => sub {
    set host_name => 'frfbot.example.com';

    set daemon_port => 8046;
    set account => 'frfbot';
};

my $host_name = get 'host_name';
my $root_dir = "/site/$host_name";
my $account = get 'account';

group bot_servers => $host_name;

use Rex::Lang::Perl::Cpanm;
task "prepare", group => "bot_servers", sub {
	my $ssh_key;
	LOCAL {
		$ssh_key = cat "$ENV{HOME}/.ssh/id_rsa.pub";
	};

	create_group $account;
	account $account,
		create_home		=> 1,
		crypt_password	=> '*',
		groups			=> [$account],
		home			=> "/home/$account",
		ssh_key			=> $ssh_key;

	file [map "$root_dir/$_", qw{www conf daemon daemon/lib log}],
		ensure	=> 'directory',
		owner	=> $account,
		group	=> $account;

	pkg [qw/nginx libxml2-dev zlib1g-dev redis-server/],
		ensure	=> 'present';

	symlink "$root_dir/conf/nginx-site.conf", "/etc/nginx/sites-enabled/$host_name.conf";

	file "$root_dir/daemon/cpanfile",
		source	=> 'cpanfile',
		owner	=> $account,
		group	=> $account;

	cpanm -install();
	cpanm -installdeps => "$root_dir/daemon";

	run 'ubic-admin --batch-mode',
		unless 'test -d /etc/ubic/service';
	chmod 1777, '/var/lib/ubic';

	symlink "$root_dir/conf/ubic-service", "/etc/ubic/service/$account";
};

task "deploy", group => "bot_servers", sub {
	file "$root_dir/www/index.html",
		content	=> "Dünya merhaba!";

    run "openssl req -newkey rsa:2048 -sha256 -nodes -keyout $root_dir/conf/https_priv.key -x509 -days 365 -out $root_dir/conf/https_public_cert.pem -subj '/C=US/ST=New York/L=Brooklyn/O=Example Brooklyn Company/CN=$host_name'";
    chmod 600, "$root_dir/conf/https_priv.key";

	file "$root_dir/conf/frfbot.conf",
		content	=> template("conf/frfbot.conf.tmpl");
	file "$root_dir/conf/nginx-site.conf",
		content	=> template("conf/nginx-site.conf.tmpl");
	file "$root_dir/conf/ubic-service",
		content	=> template("conf/ubic-service.tmpl");

    needs main "code";
};

task "start", group => "bot_servers", sub {
	run "ubic restart $account";

	service "redis",
		ensure	=> "started";
	service "nginx",
		ensure	=> "started";
};

task "code", group => "bot_servers", sub {
	file "$root_dir/daemon/frfbot.pl",
		source => "script/frfbot.pl";
	file "$root_dir/daemon/lib/FrfBot.pm",
		source => "lib/FrfBot.pm";
	file "$root_dir/daemon/lib/Handlers.pm",
		source => "lib/Handlers.pm";

	do_task "start";
};

auth for => 'prepare',
	user => 'root';
auth for => 'start',
	user => 'root';
auth for => 'deploy',
	user => $account;
auth for => 'code',
	user => $account;
