use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
BEGIN { require 5.006; }

WriteMakefile(
    'NAME'          => 'Tie::SymlinkTree',
    'AUTHOR'	    => 'Jörg Walter <jwalt@cpan.org>',
    'ABSTRACT'	    => 'fast and multi-process-safe persistent storage',
    'VERSION_FROM'  => 'lib/Tie/SymlinkTree.pm', # finds $VERSION
    'PREREQ_PM'     => { },
    'dist' => {
        COMPRESS    =>"gzip -9",
        SUFFIX      =>"gz",
        },
);





