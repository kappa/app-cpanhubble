#! /usr/bin/perl
use Modern::Perl;

use lib::abs '../lib';

use CpanHub;
use AnyEvent;
use Data::Dumper;

use signatures;

my $q = 'FriendFeed';

my ($cpan, $gh);

my $cv = AnyEvent->condvar;
$cv->begin;
cpan_search_req($q, sub {
        $cpan = $_[0];
        $cv->end;
    });

$cv->begin;
github_search_req($q, sub {
        $gh = $_[0];
        $cv->end;
    });

$cv->recv;

my $res =
    merge_cpan_and_github($cpan, $gh, $q);

say Dumper($res);
