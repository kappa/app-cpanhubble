package CpanHub;
use Modern::Perl;

use parent 'Exporter';

use URI;
use URI::Escape;
use AnyEvent::HTTP;
use XML::Simple qw/:strict/;
use List::MoreUtils qw/first_index part/;
use DateTime::Format::RFC3339;

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
                date    => do { (my $d = $_->{released}->[0]) =~ s/(\d+)[a-z]{2}/$1/; $d },
                author  => ($_->{author}->[0]->{link}->[0] =~ /~([^\/]+)/),
        } } grep {
                      $_->{name}
                   && $_->{link}
                   && $_->{description}
                   && $_->{author}
                   && $_->{author}->[0]->{link}
                   && $_->{released} } @{$xml->{module}} ] if ref $xml eq 'HASH' && $xml->{module};

        $cb->($rv);
    });
}

sub github_search_req($q, $cb) {
    (my $gh_q = $q) =~ s/::|-/ /g;
    # XXX looks like description: search is broken on github right now
    #my $query = uri_escape("($gh_q OR description:$q) AND language:Perl AND fork:false");
    my $query = uri_escape("$gh_q AND language:Perl AND fork:false");
    my $dtf = DateTime::Format::RFC3339->new;

    _call('http://github.com/api/v2/xml/repos/search/' . $query, { }, sub {
        my $xml = shift;

        my $rv = [ map { {
                name    => $_->{name}->[0],
                'link'  => "http://github.com/$_->{username}->[0]/$_->{name}->[0]",
                desc    => ref $_->{description}->[0] ? '' : $_->{description}->[0],
                author_link => "http://github.com/$_->{username}->[0]",
                date    => $dtf->parse_datetime($_->{pushed}->[0])->strftime('%e %B %Y'),
                author  => $_->{username}->[0],
                ghscore => $_->{score}->[0]->{content},
        } } grep {
                      $_->{name}
                   && $_->{description}
                   && $_->{pushed}
                   && $_->{username} 
                   && $_->{username}->[0] ne 'gitpan' } @{$xml->{repository}} ] if ref $xml eq 'HASH' && $xml->{repository};

        $cb->($rv);
    });
}

sub _gh_query($q) {
    my $gh_q = lc $q;
    $gh_q =~ s/::/--?/g;
    $gh_q =~ s/\./\\./g;

    return $gh_q;
}

sub merge_cpan_and_github($cpan, $gh, $q) {
    my @res;

    foreach my $cp (@$cpan) {
        my $ghi = first_index { 
            my $name = _gh_query($cp->{name});
            $_->{name} =~ /^ $name $/ixs;
        } @$gh;

        $ghi >= 0 or next;

        $cp->{gh} = splice @$gh, $ghi, 1;
    }

    my $gh_q = _gh_query($q);

    # ranking algorithm:
    # ---
    # we reorder all results into 5 groups:
    #   0. github with query exactly matched in name
    #   1. CPAN with query matched in name
    #   2. github with query matched in name
    #   3. rest of CPAN results
    #   4. rest of github results   # this group is usually empty because current gh search use only names
    # the original order inside the groups is retained

    my ($cpan1, $cpan2)     = part { $_->{name} =~ /$q/i    ? 0 : 1 } @$cpan;
    my ($gh0, $gh1, $gh2)   = part { $_->{name} =~ /^$gh_q$/i ? 0 : $_->{name} =~ /$gh_q/i ? 1 : 2 } @$gh;

    return [ map { @$_ } grep defined, $gh0, $cpan1, $gh1, $cpan2, $gh2 ];
}

1;
