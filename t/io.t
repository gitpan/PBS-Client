#!/usr/bin/perl -w
use strict;
use PBS::Client;
use Test::More (tests => 1);

#----------------
# Test IO options
#----------------
my $pbs = PBS::Client->new;
my $job = PBS::Client::Job->new(
    stagein  => 'in.dat',
    stageout => 'out.dat',
    maillist => 'he@where.com, she@where.com, me@where.com',
    mailopt  => 'b,e',
    efile    => 'test1.err',
    ofile    => 'test1.out',
    wd       => '.',
    cmd      => 'pwd',
);

$pbs->genScript($job);

my $diff = &diff($job->{_tempScript}, "t/io.sh");
is($diff, 0, "IO options");
unlink($job->{_tempScript});


#---------------------------------------------
# Compare two files
# - return 0 if two files are exactly the same
# - return 1 otherwise
#---------------------------------------------
sub diff
{
    my ($f1, $f2) = @_;
    open(F1, $f1);
    open(F2, $f2);
    my @c1 = <F1>;
    my @c2 = <F2>;
    close(F1);
    close(F2);
    return(0) if (join("", @c1) eq join("", @c2));
    return(1);
}
