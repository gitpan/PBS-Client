#!/usr/bin/perl -w
use strict;
use Test::More (tests => 10);

BEGIN
{
	use_ok('PBS::Client');
}

###################### Tests ######################

#-----------------------
# Test execution request
#-----------------------
{
	my $pbs = PBS::Client->new(
		server  => 'clc',
	);
	
	my $job = PBS::Client::Job->new(
		partition => 'dell',
		queue     => 'delta',
		host      => 'delta01.clustertech.com',
		wd        => '/tmp/test',
		account   => 'guest',
		name      => 'test1',
		script    => 't01.sh',
		efile     => 'test1.err',
		ofile     => 'test1.out',
		cmd       => 'pwd',
	);
	
	$pbs->genScript($job);

	my $diff = `diff t01.sh t/a01.sh`;
	is($diff, '', "execution related request");
	unlink("t01.sh");
}


#----------------------
# Test resource request
#----------------------
{
	my $pbs = PBS::Client->new;
	my $job = PBS::Client::Job->new(
		queue  => 'delta',
		wd     => '/tmp/test',
		script => 't02.sh',
		cput   => '01:30:00',
		pcput  => '00:10:00',
		wallt  => '00:30:00',
		mem    => '600mb',
		vmem   => '1gb',
		pvmem  => '100mb',
		pri    => 10,
		nice   => 5,
		nodes  => 2,
		ppn    => 1,
		cmd    => 'pwd',
	);
	
	$pbs->genScript($job);

	my $diff = `diff t02.sh t/a02.sh`;
	is($diff, '', "resource request");
	unlink("t02.sh");
}


#---------------------------------------
# Test requesting nodes in string format
#---------------------------------------
{
	my $pbs = PBS::Client->new;
	my $job = PBS::Client::Job->new(
		queue  => 'delta',
		wd     => '/tmp/test',
		script => 't03.sh',
		nodes  => "delta01.clustertech.com + delta03.clustertech.com",
		ppn    => 2,
		cmd    => 'date',
	);

	$pbs->genScript($job);

	my $diff = `diff t03.sh t/a03.sh`;
	is($diff, '', "request nodes in string format");
	unlink("t03.sh");
}


#-------------------------------
# Test specifying nodes in array
#-------------------------------
{
	my $pbs = PBS::Client->new;
	my $job = PBS::Client::Job->new(
		queue  => 'delta',
		wd     => '/tmp/test',
		script => 't04.sh',
		nodes  => [qw(delta01.clustertech.com delta03.clustertech.com)],
		ppn    => 2,
		cmd    => 'date',
	);
	
	$pbs->genScript($job);

	my $diff = `diff t04.sh t/a03.sh`;
	is($diff, '', "request nodes in array format");
	unlink("t04.sh");
}


#------------------------------
# Test specifying nodes in hash
#------------------------------
{
	my $pbs = PBS::Client->new;
	my $job = PBS::Client::Job->new(
		queue  => 'delta',
		wd     => '/tmp/test',
		script => 't05.sh',
		nodes  => {'delta01.clustertech.com' => 1,
				   'delta03.clustertech.com' => 2,
			      },
		cmd    => 'date',
	);
	
	$pbs->genScript($job);

	my $diff = `diff t05.sh t/a05.sh`;
	is($diff, '', "request nodes in hash format");
	unlink("t05.sh");
}


#---------------------------------------
# Test packing matrix of commands (numQ)
#---------------------------------------
{
	my @cmd = (
		['c00', 'c01'],
		['c10', 'c11', 'c12'],
		['c20'],
		['c30'],
		['c40', 'c41'],
		['c50'],
		'c60',
		['c70'],
		['c80'],
		['c90', 'c91', 'c92'],
	);
	
	my $pbs = PBS::Client->new;
	my $job = PBS::Client::Job->new(
		queue  => 'delta',
		nodes  => 2,
		cmd    => \@cmd,
	);
	
	$job->pack(numQ => 3);
	my @res = @{$job->{cmd}};

	my @ans = (
		['c00', 'c11', 'c30', 'c50', 'c80', 'c92'],
		['c01', 'c12', 'c40', 'c60', 'c90'],
		['c10', 'c20', 'c41', 'c70', 'c91'],
	);
	
	my $fail = 0;
	for(my $r = 0; $r < @ans; $r++)
	{
		for(my $c = 0; $c < @{$ans[$r]}; $c++)
		{
			$fail = 1 if ($res[$r][$c] ne $ans[$r][$c]);
		}
	}
	is($fail, 0, "packing array to a specified number of queue");
}


#--------------------------------------
# Test packing matrix of commands (cpq)
#--------------------------------------
{
	my @cmd = (
		['c00', 'c01'],
		['c10', 'c11', 'c12'],
		['c20'],
		['c30'],
		['c40', 'c41'],
		['c50'],
		'c60',
		['c70'],
		['c80'],
		['c90', 'c91', 'c92'],
	);
	
	my $pbs = PBS::Client->new;
	my $job = PBS::Client::Job->new(
		queue  => 'delta',
		nodes  => 2,
		cmd    => \@cmd,
	);
	
	$job->pack(cpq => 3);
	my @res = @{$job->{cmd}};

	my @ans = (
		['c00', 'c01', 'c10'],
		['c11', 'c12', 'c20'],
		['c30', 'c40', 'c41'],
		['c50', 'c60', 'c70'],
		['c80', 'c90', 'c91'],
		['c92'],
	);
	
	my $fail = 0;
	for(my $r = 0; $r < @ans; $r++)
	{
		for(my $c = 0; $c < @{$ans[$r]}; $c++)
		{
			$fail = 1 if ($res[$r][$c] ne $ans[$r][$c]);
		}
	}
	is($fail, 0, "packing array to a specified commands per queue");
}


#-----------------
# Test cloning job
#-----------------
{
	my $fail = 0;
	my $oJob = PBS::Client::Job->new(
		mem   => '600mb',
		nodes => 1,
	);

	my $nJob = $oJob->clone;
	$fail = 1 if ($nJob->{mem} ne '600mb' || $nJob->{nodes} ne 1);

	$oJob->nodes(2);
	$fail = 1 if ($oJob->{nodes} ne 2 || $nJob->{nodes} ne 1);

	$nJob->nodes(10);
	$fail = 1 if ($oJob->{nodes} ne 2 || $nJob->{nodes} ne 10);
	
	is($fail, 0, "cloning job object");
}


#-----------------
# Test copying job
#-----------------
{
	my $fail = 0;
	my $oJob = PBS::Client::Job->new(
		mem   => '600mb',
		nodes => 1,
	);

	#----------------------
	# Copy without argument
	my $nJob1 = $oJob->copy;
	$fail = 1 if ($nJob1->{mem} ne '600mb' || $nJob1->{nodes} ne 1);

	$oJob->nodes(2);
	$fail = 1 if ($oJob->{nodes} ne 2 || $nJob1->{nodes} ne 1);

	$nJob1->nodes(10);
	$fail = 1 if ($oJob->{nodes} ne 2 || $nJob1->{nodes} ne 10);
	#----------------------

	#---------------------
	# Make multiple copies
	my @nJob = $oJob->copy(2);
	$fail = 1 if (@nJob ne 2);
	$fail = 1 if ($nJob[0]->{mem} ne '600mb' || $nJob[0]->{nodes} ne 2);
	$fail = 1 if ($nJob[1]->{mem} ne '600mb' || $nJob[1]->{nodes} ne 2);

	$oJob->nodes(1);
	$fail = 1 if ($oJob->{nodes} ne 1 ||
				  $nJob[0]->{nodes} ne 2 || $nJob[1]->{nodes} ne 2);

	$nJob[0]->nodes(10);
	$fail = 1 if ($oJob->{nodes} ne 1 ||
				  $nJob[0]->{nodes} ne 10 || $nJob[1]->{nodes} ne 2);

	$nJob[1]->nodes(20);
	$fail = 1 if ($oJob->{nodes} ne 1 ||
				  $nJob[0]->{nodes} ne 10 || $nJob[1]->{nodes} ne 20);
	#---------------------
	
	is($fail, 0, "copying job object");
}
