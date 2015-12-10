#!/usr/bin/env perl
use strict;
use warnings;
 
use lib::abs qw(../lib);
 
require Mojolicious::Commands;
Mojolicious::Commands->start_app('FrfBot');
