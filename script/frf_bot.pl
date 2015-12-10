#!/usr/bin/env perl
 
use uni::perl;
 
use lib 'lib';
 
require Mojolicious::Commands;
Mojolicious::Commands->start_app('FrfBot');
