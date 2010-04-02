package CpanHub;
use strict;
use warnings;

use parent 'Exporter';

use URI;
use URI::Escape;
use AnyEvent::HTTP;
use XML::Simple qw/:strict/;
use List::MoreUtils qw/first_index/;

use signatures;

our @EXPORT = qw/cpan_search_req github_search_req merge_cpan_and_github/;

sub _call($api_point, $args, $cb) {
    my $uri = new URI $api_point;
    $uri->query_form($args);

    http_get $uri->as_string, sub {
        my ($body, $headers) = @_;

        $body or return $cb->({});
        
        my $hashref = eval { XMLin($body, ForceArray => 1, KeyAttr => []) };
        $@ and $hashref = {};

        $cb->($hashref);
    };
}

sub cpan_search_req($q, $cb) {
    _call('http://search.cpan.org/search', { query => $q, mode => 'all', format => 'xml' }, sub {
        my $xml = shift;

        my $rv = [ map { {
                name    => $_->{name}->[0],
                'link'  => $_->{link}->[0],
                desc    => $_->{description}->[0],
                author_link => $_->{author}->[0]->{link}->[0],
                date    => $_->{released}->[0],
        } } grep {    $_->{name}
                   && $_->{link}
                   && $_->{description}
                   && $_->{author}
                   && $_->{author}->[0]->{link}
                   && $_->{released} } @{$xml->{module}} ] if ref $xml eq 'HASH' && $xml->{module};

        $cb->($rv);
    });
}

sub github_search_req($q, $cb) {
    my $query = uri_escape("($q OR description:$q) AND language:Perl AND fork:false");
    _call('http://github.com/api/v2/xml/repos/search/' . $query, { }, sub {
        my $xml = shift;

        my $rv = [ map { {
                name    => $_->{name}->[0],
                'link'  => "http://github.com/$_->{username}->[0]/$_->{name}->[0]",
                desc    => $_->{description}->[0],
                author_link => "http://github.com/$_->{username}->[0]",
                date    => $_->{pushed}->[0],
        } } grep {    $_->{name}
                   && $_->{description}
                   && $_->{pushed}
                   && $_->{username} 
                   && $_->{username}->[0] ne 'gitpan' } @{$xml->{repository}} ] if ref $xml eq 'HASH' && $xml->{repository};

        $cb->($rv);
    });
}

sub merge_cpan_and_github($cpan, $gh) {
    my @res;

    foreach my $cp (@$cpan) {
        my $ghi = first_index { 
            (my $name = lc $cp->{name}) =~ s/::/--?/g;
            $name =~ s/\./\\./g;
            $_->{name} =~ /^ $name $/ixs;
        } @$gh;

        $ghi >= 0 or next;

        $cp->{gh} = splice @$gh, $ghi, 1;
    }

    return [@$cpan, @$gh];
}

1;
