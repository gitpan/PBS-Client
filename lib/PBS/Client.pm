package PBS::Client;
use strict;
use vars qw($VERSION);
use Carp;
$VERSION = 0.02;

#------------------------------------------------
# Submit jobs to PBS server
#
# Included methods:
# - Construct job server
#     $server = PBS::Client->new();
#
# - Submit jobs
#     $server->qsub($job);
#     -- $server -- job server
#     -- $job ----- job object
#
# - Generate job script without job submission
#     $server->genScript($job);
#     -- $server -- job server
#     -- $job ----- job object
#------------------------------------------------

use Class::MethodMaker
	new_with_init => 'new',
	new_hash_init => '_init_args',
	get_set       => [qw(server)];


#-----------------------
# Constructor method
#
# <IN>
# $self -- server object
# %args -- argument hash
#
# <OUT>
# $self -- server object
sub init
{
	my ($self, %args) = @_;
	$self->_init_args(%args);
	return $self;
}
#-----------------------


#-----------------------------------------------------------------
# Submit PBS jobs by qsub command
# called subroutines: getScript(), _numPrevJob() and _qsubDepend()
#
# <IN>
# $self -- server object
# $job --- job object
#
# <OUT>
# \@pbsid -- array reference of PBS job ID
sub qsub
{
	my ($self, $job) = @_;

	#------------------------------------------
	# Codes for backward compatatible with v0.x
	#------------------------------------------
	if (!ref($job) || ref($job) eq 'ARRAY')
	{
		$self->cmd($job);
		&qsub($self, $self);
	}

	#-----------------------------------------------
	# Dependency: count number of previous jobs
	#-----------------------------------------------
	my $on = &_numPrevJob($job);
	$job->{depend}{on} = [$on] if ($on);
	my $file = $job->{script};
	my @pbsid = ();

	#-----------------------------------------------
	# Single job
	#-----------------------------------------------
	if (!ref($job->{cmd}))
	{
		&genScript($self, $job);
		my $out = `qsub $file`;
		my $pbsid = ($out =~ /^(\d+)/)[0];
		rename($file, "$file.$pbsid");
		push(@pbsid, $pbsid);
		$job->pbsid($pbsid);
	}
	#-----------------------------------------------
	# Multiple (matrix of) jobs
	#-----------------------------------------------
	else
	{
		my $subjob = $job->clone;
		for (my $i = 0; $i < @{$job->{cmd}}; $i++)
		{
			# Get command
			my $list = ${$job->{cmd}}[$i];
			my $cmd = (ref $list)? (join("\n", @$list)): $list;
			$subjob->{cmd} = $cmd;
	
			# Generate and submit job script
			&genScript($self, $subjob);				# generate script
			my $out = `qsub $file`;					# submit script
			my $pbsid = ($out =~ /^(\d+)/)[0];		# grab pid
			rename("$file", "$file.$pbsid");		# rename script
			push(@pbsid, $pbsid);
		}
		$job->pbsid(\@pbsid);
	}

	#-----------------------------------------------
	# Dependency: submit previous and following jobs
	#-----------------------------------------------
	&_qsubDepend($self, $job, \@pbsid);

	return(\@pbsid);
}
#-----------------------------------------------------------------


#-------------------------------------------------------
# Generate shell script from command string array
# called subroutines: _getTime(), _nodes() and _depend()
# called by qsub()
#
# <IN>
# $self -- server object
# $job --- job object
#
# <OUT>
# job script
sub genScript
{
	my ($self, $job) = @_;
	my $file = $job->{script};
	my $queue = '';
	$queue .= $job->{queue};
	$queue .= '@'.$self->{server} if (defined $self->{server});
	my $partition;
	$partition = $job->{partition};

	my $nodes = &_nodes($job);

	#------------------------
	# PBS request option list
	#------------------------
	open(SH, ">$file") || confess "Can't write $file";
	print SH "#!/bin/sh\n\n";
	print SH "#PBS -N $job->{name}\n" if (defined $job->{name});
	print SH "#PBS -d $job->{wd}\n";
	print SH "#PBS -e $job->{efile}\n" if (defined $job->{efile});
	print SH "#PBS -o $job->{ofile}\n" if (defined $job->{ofile});
	print SH "#PBS -q $queue\n" if ($queue);
	print SH "#PBS -W x=PARTITION:$partition\n" if (defined $partition);
	print SH "#PBS -W stagein=".join(',', @{$job->{stagein}})."\n" if
		(defined $job->{stagein});
	print SH "#PBS -W stageout=".join(',', @{$job->{stageout}})."\n" if
		(defined $job->{stageout});
	print SH "#PBS -A $job->{account}\n" if (defined $job->{account});
	print SH "#PBS -p $job->{pri}\n" if (defined $job->{pri});
	print SH "#PBS -l nodes=$nodes\n";
	print SH "#PBS -l host=$job->{host}\n" if (defined $job->{host});
	print SH "#PBS -l mem=$job->{mem}\n" if (defined $job->{mem});
	print SH "#PBS -l pmem=$job->{pmem}\n" if (defined $job->{pmem});
	print SH "#PBS -l vmem=$job->{vmem}\n" if (defined $job->{vmem});
	print SH "#PBS -l pvmem=$job->{pvmem}\n" if (defined $job->{pvmem});
	print SH "#PBS -l cput=$job->{cput}\n" if (defined $job->{cput});
	print SH "#PBS -l pcput=$job->{pcput}\n" if (defined $job->{pcput});
	print SH "#PBS -l walltime=$job->{wallt}\n" if (defined $job->{wallt});
	print SH "#PBS -l nice=$job->{nice}\n" if (defined $job->{nice});

	#----------------------
	# Job dependency option
	#----------------------
	if (defined $job->{depend})
	{
		my $depend = &_depend($job->{depend});
		print SH "#PBS -W depend=$depend\n";
	}
	print SH "\n";

	#--------------------------
	# Locate execution machines
	#--------------------------
	my $cmd = $job->{cmd};
	my $tracer = $job->{tracer};
	$cmd = &_trace($cmd) if ($tracer && $tracer ne 'off');
	
	#-------------------------------
	# Get start time and finish time
	#-------------------------------
	my $timer = $job->{timer};
	$cmd = &_getTime($timer, $cmd) if ($timer && $timer !~ /^(off|0|nil)$/);

	#----------------
	# Execute command
	#----------------
	print SH "$cmd\n";
	close(SH);
}
#-------------------------------------------------------


#------------------------------
# Count number of previous jobs
sub _numPrevJob
{
	my ($job) = @_;
	my $on = 0;
	if (defined $job->{prev})
	{
		foreach my $type (keys %{$job->{prev}})
		{
			if (ref($job->{prev}{$type}) eq 'ARRAY')
			{
				foreach my $jobTmp (@{$job->{prev}{$type}})
				{
					my $prevcmd = $jobTmp->{cmd};
					if (ref($prevcmd))
					{
						my $numCmd = scalar(@$prevcmd);
						$on += $numCmd;
					}
					else
					{
						$on++;
					}
				}
			}
			else
			{
				my $prevcmd = $job->{prev}{$type}{cmd};
				if (ref($prevcmd))
				{
					my $numCmd = scalar(@$prevcmd);
					$on += $numCmd;
				}
				else
				{
					$on++;
				}
			}
		}
	}
	return($on);
}
#------------------------------


#----------------------
# Submit dependent jobs
# called by qsub()
sub _qsubDepend
{
	my ($self, $job, $pbsid) = @_;

	my %type = (
		'prevstart' => 'before',
		'prevend'   => 'beforeany',
		'prevok'    => 'beforeok',
		'prevfail'  => 'beforenotok',
		'nextstart' => 'after',
		'nextend'   => 'afterany',
		'nextok'    => 'afterok',
		'nextfail'  => 'afternotok',
		);

	foreach my $order qw(prev next)
	{
		foreach my $cond qw(start end ok fail)
		{
			if (defined $job->{$order}{$cond})
			{
				my $type = $type{$order.$cond};
				if (ref($job->{$order}{$cond}) eq 'ARRAY')	# array of job obj
				{
					foreach my $jobTmp (@{$job->{$order}{$cond}})
					{
						$$jobTmp{depend}{$type} = $pbsid;
						&qsub($self, $jobTmp);
					}
				}
				else
				{
					my $jobTmp = $job->{$order}{$cond};
					$$jobTmp{depend}{$type} = $pbsid;
					&qsub($self, $jobTmp);
				}
			}
		}
	}
}
#----------------------


#-----------------------------------------------------
# Trace the job by recording the location of execution
# - called by genScript()
# <IN>
# $cmd -- command string
#
# <OUT>
# $cmd -- modified command string
sub _trace
{
	my ($cmd) = @_;
	$cmd = "echo MACHINES:\ncat \$PBS_NODEFILE\necho ''\n".$cmd;
	return($cmd);
}
#-----------------------------------------------------


#---------------------------------------------------
# Modified $cmd to obtain start time and finish time
# - called by genScript()
# - depreciated
#
# <IN>
# $timer -- time format
# $cmd ---- command string
#
# <OUT>
# $cmd -- modified command string
sub _getTime
{
	my ($timer, $cmd) = @_;
	
	if ($timer =~ /^(on|1|default)$/)			# default format
	{
		$cmd = 'echo "START:  `date`"; '.$cmd;	# start time
		$cmd .= '; echo "FINISH: `date`"';		# finish time
	}
	else										# user-defined format
	{
		$cmd = 'echo "START:  `date '."+'$timer'".'`"; '.$cmd;
		$cmd .= '; echo "FINISH: `date '."+'$timer'".'`"';
	}
	return($cmd);
}
#---------------------------------------------------


#----------------------------------------------------------
# Construct node request string
# called by genScript()
#
# <IN>
# $job -- job object
#
# <OUT>
# $str -- node request string
sub _nodes
{
	my ($job) = @_;
	$job->nodes('1') if (!defined $job->{nodes});
	my $type = ref($job->{nodes});

	#-------------------------------------------
	# String
	# Example:
	# (1) nodes => 2, ppn => 2
	# (2) nodes => "delta01+delta02", ppn => 2
	# (3) nodes => "delta01:ppn=2+delta02:ppn=1"
	#-------------------------------------------
	if ($type eq '')
	{
		if ($job->{nodes} =~ /^\d+$/)
		{
			my $str = "$job->{nodes}";
			$str .= ":ppn=$job->{ppn}" if (defined $job->{ppn});
			return($str);
		}
		else
		{
			if (defined $job->{ppn})
			{
				my @node = split(/\s*\+\s*/, $job->{nodes});
				my $str = join(":ppn=$job->{ppn}+", @node);
				$str .= ":ppn=$job->{ppn}";
				return($str);
			}
			return($job->{nodes});
		}
	}
	#-----------------------------------------------
	# Array
	# Example:
	# (1) nodes => [qw(delta01 delta02)], ppn => 2
	# (2) nodes => [qw(delta01:ppn=2 delta02:ppn=1)]
	#-----------------------------------------------
	elsif ($type eq 'ARRAY')
	{
		if (defined $job->{ppn})
		{
			my $str = join( ":ppn=$job->{ppn}+", @{$job->{nodes}} );
			$str .= ":ppn=$job->{ppn}";
			return($str);
		}
		return( join('+', @{$job->{nodes}}) );
	}
	#------------------------------------------
	# Hash
	# Example:
	# (1) nodes => {delta01 => 2, delta02 => 1}
	#------------------------------------------
	elsif ($type eq 'HASH')
	{
		my $str = '';
		foreach my $node (keys %{$job->{nodes}})
		{
			$str .= "$node:ppn=${$job->{nodes}}{$node}+";
		}
		chop($str);
		return($str);
	}
}
#----------------------------------------------------------


#----------------------------------------------------------
# Construct the job dependency string
# called by genScript()
#
# <IN>
# $arg -- hash reference of job dependency
#
# <OUT>
# $str -- job dependency string
sub _depend
{
	my ($arg) = @_;
	my $str = '';

	foreach my $type (keys %$arg)
	{
		$str .= ',' unless ($str eq '');
		my $joblist = join(':', @{$$arg{$type}});
		$str .= "$type:$joblist";
	}
	return($str);
}
#----------------------------------------------------------


#################### PBS::Client::Job ####################

package PBS::Client::Job;
use strict;

#------------------------------------------------
# Job class
#------------------------------------------------

use Cwd;
use Carp;
use Class::MethodMaker
	new_with_init => 'new',
	new_hash_init => '_init_args',
	deep_copy     => 'clone',
	get_set       => [qw(wd name script tracer timer host nodes ppn account
		cluster partition queue ofile efile pri mem pmem vmem pvmem cput pcput
		wallt nice pbsid cmd prev next depend stagein stageout mpistagein)];


#-----------------------
# Constructor method
#
# <IN>
# $self -- job object
# %args -- argument hash
#
# <OUT>
# $self -- job object
sub init
{
	my ($self, %args) = @_;

	#-------------
	# set defaults
	#-------------
	my $wd = cwd;
	$self->wd($wd);
	$self->script('pbsjob.sh');
	$self->tracer('off');
	$self->timer('off');

	#-----------------------------
	# optionally override defaults
	#-----------------------------
	$self->_init_args(%args);
	return $self;
}
#-----------------------


#---------------------------------------
# Pack commands
#
# <IN>
# $self -- job object
# %args -- argument hash
#          -- numQ -- number of queues
#          -- cpq --- commands per queue
sub pack
{
	my ($self, %args) = @_;
	my $cmdlist = $self->{cmd};
	return if (ref($cmdlist) ne 'ARRAY');

	my @pack = ();
	my $jc = 0;		# job counter
	if (defined $args{numQ})
	{
		for (my $i = 0; $i < @$cmdlist; $i++)
		{
			if (ref($$cmdlist[$i]))
			{
				foreach my $cell (@{$$cmdlist[$i]})
				{
					my $row = $jc % $args{numQ};
					push(@{$pack[$row]}, $cell);
					$jc++;
				}
			}
			else
			{
				my $row = $jc % $args{numQ};
				push(@{$pack[$row]}, $$cmdlist[$i]);
				$jc++;
			}
		}
	}
	elsif (defined $args{cpq})
	{
		for (my $i = 0; $i < @$cmdlist; $i++)
		{
			if (ref($$cmdlist[$i]))
			{
				foreach my $cell (@{$$cmdlist[$i]})
				{
					my $row = int($jc / $args{cpq});
					push(@{$pack[$row]}, $cell);
					$jc++;
				}
			}
			else
			{
				my $row = int($jc / $args{cpq});
				push(@{$pack[$row]}, $$cmdlist[$i]);
				$jc++;
			}
		}
	}
	$self->cmd([@pack]);
}
#---------------------------------------


#------------------------------------
# Copy job objects
#
# <IN>
# $self -- original job object
# $num --- number of copies
#
# <OUT>
# @job -- array of copied job objects
sub copy
{
	my ($self, $num) = @_;
	return $self->clone if (!defined $num);

	my @job = ();
	while($num > 0)
	{
		$num = int($num-0.5);
		push(@job, $self->clone);
	}
	return(@job);
}
#------------------------------------


__END__

=head1 NAME

PBS::Client - job submission interface of the PBS (Portable Batch System)

=head1 SYNOPSIS

    # Load this module
    use PBS::Client;
    
    # Create a client object linked to a server
    my $client = PBS::Client->new;
    
    # Discribe the job
    my $job = PBS::Client::Job->new(
    	%job_options,		# e.g. queue => 'queue_1', mem => '800mb'
    	cmd => \@commands
    );
    
    # Optionally, re-organize the commands to a number of queues
    $job->pack(numQ => $numQ);
    
    # Submit job
    $client->qsub($job);

=head1 DESCRIPTION

This module lets you submit jobs to PBS server in Perl. It would be especially
useful when you submit a large amount of jobs. Inter-dependency among jobs can
also be declared.

=head1 SIMPLE USAGE

To submit PBS jobs using PBS::Client, there are basically three steps:

=over

=item 1 Create a client object using C<new()>, e.g.,

    my $client = PBS::Client->new;

=item 2 Create a job object using C<new()> and specify the commands to be
submitted using option C<cmd>, e.g.,

    my $job = PBS::Client::Job->new(cmd => \@commands);

=item 3 Use the C<qsub()> method of the client object to submit the jobs, e.g.,

    $client->qsub($job);

=back

There are other methods and options of the client object and job object.
However, most of them may appear to be too difficult for the first use. The
only must option is C<cmd> which tells the client object what need to be
submitted. Other options are optional. If omitted, default values are used.

=head1 CLIENT OBJECT METHODS

=head2 new()

    $pbs = PBS::Client->new(
        server => $server       # PBS server name (optional)
    );

Client object is created by the C<new> method. The name of the PBS server can
by optionally supplied. If it is omitted, default server is assumed.

=head2 qsub()

Job (as a job object) is submitted to PBS by the method C<qub>.

    my $pbsid = $pbs->qsub($job_object);

An array reference of PBS job ID would be returned.

=head1 JOB OBJECT METHODS

=head2 new()

     $job = PBS::Client::Job->new(
         wd        => $wd,              # working directory, default: cwd
         nodes     => $nodes,           # execution nodes, default: 1
         name      => $name,            # job name, default: pbsjob.sh
         script    => $script,          # job script name, default: pbsjob.sh
         account   => $account,         # account string
         partition => $partition,       # partition
         queue     => $queue,           # queue
         host      => $host,            # host used to execute
         stagein   => [@in_files],      # files staged in
         stageout  => [@out_files],     # files staged out
         pri       => $pri,             # priority
         nice      => $nice,            # nice value
         mem       => $mem,             # requested total memory
         pmem      => $pmem,            # requested per-process memory
         vmem      => $vmem,            # requested virtual memory
         pvmem     => $pvmem,           # requested per-process virtual memory
         cput      => $cput,            # requested total CPU time
         pcput     => $pcput,           # requested per-process CPU time
         wallt     => $wallt,           # requested wall time
         ppn       => $ppn,             # process per node
         cmd       => [@commands],      # command to be submitted
         efile     => $efile,           # standard error file
         ofile     => $ofile,           # standard output file
         prev      => {
                       ok    => $job1,  # successful job before $job
                       fail  => $job2,  # failed job before $job
                       start => $job3,  # started job before $job
                       end   => $job4,  # ended job before $job
                      },
         next      => {
                       ok    => $job5,  # next job after $job succeeded
                       fail  => $job6,  # next job after $job failed
                       start => $job7,  # next job after $job started
                       end   => $job8,  # next job after $job ended
                      },
     );

Two points may be noted:

=over

=item 1 Except C<cmd>, all attributes are optional.

=item 2 All attributes can also be modified by methods, e.g.,

    $job = PBS::Client::Job->new(cmd => [@commands]);

is equivalent to

    $job = PBS::Client::Job->new;
    $job->cmd([@commands]);

=back

=head3 Options

=head4 wd

Full path of the working directory, i.e. the directory where the command(s) is
executed. The default value is the current working directory.

=head4 nodes

Nodes used. It can be an integer (declaring number of nodes used), string
(declaring which nodes are used), array reference (declaring which nodes are
used), and hash reference (declaring which nodes, and how many processes of
each node are used).

Examples:

=over

=item * Integer

    nodes => 3

means that three nodes are used.

=item * String / array reference

    # string representation
    nodes => "node01 + node02"

    # array representation
    nodes => ["node01", "node02"]

means that nodes "node01" and "node02" are used.

=item * Hash reference

    nodes => {node01 => 2, node02 => 1}

means that "node01" is used with 2 processes, and "node02" with 1 processes.

=back

=head4 name

Job name. It can have 15 or less characters. It cannot contain space and the
first character must be alphabetic. If not specified, it would follow the
script name.

=head4 script

Filename prefix of the job script to be generated. The PBS job ID would be
appended to the filename as the suffix.

Example: C<< script => test.sh >> would generate a job script like
F<test.sh.12345> if the job ID is '12345'.

The default value is C<pbsjob.sh>.

=head4 account

Account string. This is meaningful if you need to which account you are using
to submit the job.

=head4 partition

Partition name. This is meaningful only for the clusters with partitions. If it
is omitted, default value will be assumed.

=head4 queue

Queue of which jobs are submitted to. If omitted, default queue would be used.

=head4 host

You can specify the host on which the job will be run.

=head4 stagein

Specify which files are need to stage (copy) in before the job starts. An array
reference of file list is expected. For example, C<< stagein => ["dir1/file1",
"dir2/file2, ..."] >>.

=head4 stageout

Specify which files are need to stage (copy) out after the job finishs. An
array reference of file list is expected. For example, C<< stageout =>
["dir1/file1","dir2/file2, ..."] >>.

=head4 pri

Priority of the job in queueing. The higher the priority is, the shorter is the
queueing time. Priority must be an integer between -1024 to +1023 inclusive.
The default value is 0.

=head4 nice

Nice value of the job during execution. It must be an integer between -20
(highest priority) to 19 (lowest). The default value is 10.

=head4 mem

Maximum physical memory used by all processes. Unit can be b (bytes), w
(words), kb, kw, mb, mw, gb or gw. If it is omitted, default value will be
used. Please see also C<pmem>, C<vmem> and C<pvmem>.

=head4 pmem

Maximum per-process physical memory. Unit can be b (bytes), w (words), kb, kw,
mb, mw, gb or gw. If it is omitted, default value will be used. Please see also
C<mem>, C<vmem> and C<pvmem>.

=head4 vmem

Maximum virtual memory used by all processes. Unit can be b (bytes), w (words),
kb, kw, mb, mw, gb or gw. If it is omitted, default value will be used. Please
see also C<mem>, C<pmem> and C<pvmem>.

=head4 pvmem

Maximum virtual memory per processes. Unit can be b (bytes), w (words), kb, kw,
mb, mw, gb or gw. If it is omitted, default value will be used. Please see also
C<mem>, C<pmem> and C<vmem>.

=head4 cput

Maximum amount of total CPU time used by all processes. Values are specified in
the form [[hours:]minutes:]seconds[.milliseconds]. Please see also C<pcput>.

=head4 pcput

Maximum amount of per-process CPU time. Values are specified in the form
[[hours:]minutes:]seconds[.milliseconds]. Please see also C<cput>.

=head4 wallt

Maximum amount of wall time used. Values are specified in the form
[[hours:]minutes:]seconds[.milliseconds].

=head4 ppn

Maximum number of processes per node. The default value is 1.

=head4 cmd

Command(s) to be submitted. It can be an array (2D or 1D) reference or a
string. For 2D array reference, each row would be a separate job in PBS, while
different elements of the same row are commands which would be executed one by
one in the same job.  For 1D array, each element is a command which would be
submitted separately to PBS. If it is a string, it is assumed that the string
is the only one command which would be executed.

Examples:

=over

=item * 2D array reference

    cmd => [["./a1.out"],
            ["./a2.out" , "./a3.out"]]

means that C<a1.out> would be excuted as one PBS job, while C<a2.out> and
C<a3.out> would be excuted one by one in another job.

=item * 1D array reference

    cmd => ["./a1.out", "./a2.out"]

means that C<a1.out> would be executed as one PBS job and C<a2.out> would be
another. Therefore, this is equilvalent to

    cmd => [["./a1.out", "./a2.out"]]

=item * String

    cmd => "./a.out"

means that the command C<a.out> would be executed. Equilvalently, it can be

    cmd => [["./a.out"]]  # as a 2D array
    # or
    cmd => ["./a.out"]    # as a 1D array.

=back

=head4 efile

Path of the file for standard error. The default filename is like
F<jobName.e12345> if the job name is 'jobName' and its ID is '12345'. Please
see also C<ofile>.

=head4 ofile

Path of the file for standard output. The default filename is like
F<jobName.o12345> if the job name is 'jobName' and its ID is '12345'. Please
see also C<efile>.

=head4 prev

Hash reference which declares the job(s) executed beforehand. The hash can have
four possible keys: C<start>, C<end>, C<ok> and C<fail>. C<start> declares
job(s) which has started execution. C<end> declares job(s) which has already
ended. C<ok> declares job(s) which has finished successfully. C<fail> declares
job(s) which failed. Please see also C<next>.

Example: C<< $job1->prev({ok => $job2, fail => $job3}) >> means that C<$job1>
is executed only after C<$job2> exits normally and C<job3> exits with error.

=head4 next

Hash reference which declares the job(s) executed later. The hash can have four
possible keys: C<start>, C<end>, C<ok> and C<fail>. C<start> declares job(s)
after started execution. C<end> declares job(s) after finished execution. C<ok>
declares job(s) after finished successfully. C<fail> declares job(s) after
failure. Please see also C<prev>.

Example: C<< $job1->next({ok => $job2, fail => $job3}) >> means that C<$job2>
would be executed after C<$job1> exits normally, and otherwise C<job3> would be
executed instead.

=head2 pbsid

Return the PBS job ID(s) of the job(s). It returns after the job(s) has
submitted to the PBS. The returned value is an integer if C<cmd> is a string.
If C<cmd> is an array reference, the reference of the array of ID will be
returned. For example,

    $pbsid = $job->pbsid;

=head2 pack()

C<pack> is used to rearrange the commands among different queues (PBS jobs).
Two options, which are C<numQ> and C<cpq> can be set. C<numQ> specifies number
of jobs that the commands will be distributed. For example,

    $job->pack(numQ => 8);

distributes the commands among 8 jobs. On the other hand, the C<cpq>
(abbreviation of B<c>ommand B<p>er B<q>ueue) option rearranges the commands
such that each job would have specified commands. For example,

    $job->pack(cpq => 8);

packs the commands such that each job would have 8 commands, until no command
left.

=head2 copy()

Job objects can be copied by the C<copy> method:

    my $new_job = $old_job->copy;

The new job object (C<$new_job>) is identical to, but independent of the
original job object (C<$old_job>).

C<copy> can also specify number of copies to be generated. For example,

    my @copies = $old_job->copy(3);

makes three identical copies.

Hence, the following two statements are the same:

    my $new_job = $old_job->copy;
    my ($new_job) = $old_job->copy(1);

=head1 SCENARIOS

=over

=item 1. Submit a Single Command

You want to run C<a.out> of current working directory in 'delta' queue

    use PBS::Client;
    my $pbs = PBS::Client->new;
    my $job = PBS::Client::Job->new(
        cmd   => './a.out',
    );

=item 2. Submit a List of Commands

You need to submit a list of commands to PBS. They are stored in the Perl array
C<@jobs>. You want to execute them one by one in a single CPU.

    use PBS::Client;
    my $pbs = PBS::Client->new;
    my $job = PBS::Client::Job->new(
        cmd => [\@jobs],
    );
    $pbs->qsub($job);

=item 3. Submit Multiple Lists

You have 3 groups of commands, stored in C<@jobs_a>, C<@jobs_b>, C<@jobs_c>.
You want to execute each group in different CPU.

    use PBS::Client;
    my $pbs = PBS::Client->new;
    my $job = PBS::Client::Job->new(
        cmd => [
                \@jobs_a,
                \@jobs_b,
                \@jobs_c,
               ],
    );
    $pbs->qsub($job);

=item 4. Rearrange Commands (Specifying Number of Queues)

You have 3 groups of commands, stored in C<@jobs_a>, C<@jobs_b>, C<@jobs_c>.
You want to re-organize them to 4 groups.

    use PBS::Client;
    my $pbs = PBS::Client->new;
    my $job = PBS::Client::Job->new(
        cmd => [
                \@jobs_a,
                \@jobs_b,
                \@jobs_c,
               ],
    );
    $job->pack(numQ => 4);
    $pbs->qsub($job);

=item 5. Rearrange Commands (Specifying Commands Per Queue)

You have 3 groups of commands, stored in C<@jobs_a>, C<@jobs_b>, C<@jobs_c>.
You want to re-organize such that each group has 4 commands.

    use PBS::Client;
    my $pbs = PBS::Client->new;
    my $job = PBS::Client::Job->new(
        cmd => [
                \@jobs_a,
                \@jobs_b,
                \@jobs_c,
               ],
    );
    $job->pack(cpq => 4);
    $pbs->qsub($job);

=item 6. Customize resource

You want to use customized resource rather than the default resource
allocation.

    use PBS::Client;
    my $pbs = PBS::Client->new;

    my $job = Kode::PBS::Job->new(
        account   => 'my_project',       # account string
        partition => 'partition01',      # partition name
        queue     => 'queue01',          # PBS queue name
        wd        => '/tmp',             # working directory
        name      => 'testing',          # job name
        script    => 'test.sh',          # name of script generated

        pri       => '10',               # higher priority
        mem       => '800mb',            # 800 MB memory
        cput      => '10:00:00',         # 10 hrs CPU time
        wallt     => '05:00:00',         # 5 hrs wall time
        cmd       => './a.out --debug',  # command line
    );
    $pbs->qsub($job);

=item 7. Job dependency

You want to run C<a1.out>. Then run C<a2.out> if C<a1.out> finished
successfully; otherwise run C<a3.out> and C<a4.out>.

    use PBS::Client;
    my $pbs = PBS::Client->new;
    my $job1 = PBS::Client::Job->new(cmd => "./a1.out");
    my $job2 = PBS::Client::Job->new(cmd => "./a2.out");
    my $job3 = PBS::Client::Job->new(cmd => ["./a3.out", "./a4.out"]);

    $job1->next({ok => $job2, fail => $job3});
    $pbs->qsub($job1);

=back

=head1 SCRIPT "RUN"

If you want to execute a single command, you need not write script.  The
simplest way is to use the script F<run> in this package. For example,

    run "./a.out --debug > a.dat"

would submit the job executing the command "a.out" with option "--debug", and
redirect the output to the file "a.dat".

The options of the job object, such as the resource requested can be edited by

    run -e

The more detail manual can be viewed by

    run -m

=head1 REQUIREMENTS

Class::MethodMaker

=head1 BUGS

Perhaps many, but none is found yet. Bugs and suggestions please email to
kwmak@cpan.org

=head1 AUTHOR(S)

Ka-Wai Mak <kwmak@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2006 Ka-Wai Mak. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
