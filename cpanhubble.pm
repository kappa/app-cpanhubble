package cpanhubble;
use Dancer;

use lib './lib';
use CpanHub;
use AnyEvent;
use Encode;
use CHI;

my $cache = CHI->new(driver => 'FastMmap', root_dir   => '/tmp/hubble-cache', cache_size => '10m');

get '/' => sub {
    template 'index';
};

get '/search' => sub {
    my ($cpan, $gh);

    my $cache_miss;
    my $res = $cache->get(params->{q});
    unless ($res) {
        $cache_miss = 1;

        my $cv = AnyEvent->condvar;
        $cv->begin;
        cpan_search_req(params->{q}, sub {
                $cpan = $_[0];
                $cv->end;
            });

        $cv->begin;
        github_search_req(params->{q}, sub {
                $gh = $_[0];
                $cv->end;
            });

        $cv->recv;

        $res = merge_cpan_and_github($cpan, $gh, params->{q});

        $cache->set(params->{q}, $res, '2 days');
    }

    template 'serp', { res => $res, cache_miss => $cache_miss };
};

true;
