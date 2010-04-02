package cpanhubble;
use Dancer;

use lib './lib';
use CpanHub;
use AnyEvent;

get '/' => sub {
    template 'index';
};

get '/search' => sub {
    my ($cpan, $gh);

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

    my $res =
        merge_cpan_and_github($cpan, $gh, params->{q});

    template 'serp', { res => $res, query => params->{q} };
};

true;
