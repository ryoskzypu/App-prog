use v5.40.0;

use strict;
use warnings;

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
    NAME               => 'App::prog',
    AUTHOR             => q{ryoskzypu <ryoskzypu@proton.me>},
    VERSION_FROM       => 'lib/App/prog.pm',
    ABSTRACT_FROM      => 'lib/App/prog.pm',
    LICENSE            => 'open_source',
    MIN_PERL_VERSION   => 'v5.40.0',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
    },
    TEST_REQUIRES => {
        'Test2::V1'     => '0',
        'Capture::Tiny' => '0',
    },
    PREREQ_PM => {
        'Const::Fast'        => '0',
        'Cwd'                => '0',
        'Encode'             => '0',
        'Encode::Locale'     => '0',
        'File::Basename'     => '0',
        'File::HomeDir'      => '0',
        'File::Spec'         => '0',
        'File::XDG'          => '1.00',
        'Getopt::Long::More' => '0',
        'IPC::Run3'          => '0',
        'Path::Tiny'         => '0',
        'Pod::Usage'         => '0',
        'Term::ANSIColor'    => '2.02',
    },
    EXE_FILES => [
        'bin/prog',
    ],
    META_MERGE => {
        'meta-spec' => { version => 2 },
        prereqs     => {
            develop => {
                recommends => {
                    'App::CPANTS::Lint'        => '0',
                    'Data::Printer'            => '0',
                    'Devel::Cover'             => '0',
                    'Perl::Critic'             => '0',
                    'Perl::Tidy'               => '0',
                    'Pod::Markdown'            => '0',
                    'Pod::Markdown::Githubert' => '0',
                },
                requires => {
                    'Test::CPAN::Changes' => '0',
                    'Test::Kwalitee'      => '0',
                    'Test::Perl::Critic'  => '0',
                    'Test::Pod'           => '0',
                    'Test::Pod::Coverage' => '0',
                    'Test::Spelling'      => '0',
                },
            },
            runtime => {
                recommends => {
                    'Data::Printer' => '0',
                    'TOML::Tiny'    => '0',
                },
            },
            test => {
                recommends => {
                    'Data::Printer' => '0',
                    'TOML::Tiny'    => '0',
                },
            },
        },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/ryoskzypu/App-prog.git',
                web  => 'https://github.com/ryoskzypu/App-prog',
            },
            bugtracker => {
                web => 'https://github.com/ryoskzypu/App-prog/issues',
            },
        },
        x_contributors => [
            q{ryoskzypu <ryoskzypu@proton.me>},
        ],
    },
);

WriteMakefile(%WriteMakefileArgs);
