use ExtUtils::MakeMaker;

WriteMakefile(
	AUTHOR        => 'Ka-Wai Mak',
	NAME          => 'PBS::Client',
	VERSION_FROM  => 'lib/PBS/Client.pm',
	ABSTRACT_FROM => "lib/PBS/Client.pm",
	PREREQ_PM     => { Class::MethodMaker => 1.11 },
	EXE_FILES     => [ 'bin/run' ],
	dist          => {
		SUFFIX   => '.gz',
		COMPRESS => 'gzip -f'
	}
);
