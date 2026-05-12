use v5.40.0;

use strict;
use warnings;

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
    NAME             => 'App::prog',
    AUTHOR           => q{ryoskzypu <ryoskzypu@proton.me>},
    VERSION_FROM     => 'lib/App/prog.pm',
    ABSTRACT_FROM    => 'lib/App/prog.pm',
    LICENSE          => 'open_source',
    MIN_PERL_VERSION => 'v5.40.0',
    EXE_FILES        => [
        'bin/prog',
    ],
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
    },
    TEST_REQUIRES => {
        'Capture::Tiny' => '0.50',
        'Path::Tiny'    => '0.150',
        'Test2::V1'     => '0',
    },
    PREREQ_PM => {
        'Const::Fast'     => '0.014',
        'Encode'          => '0',
        'Encode::Locale'  => '1.05',
        'File::Basename'  => '0',
        'File::HomeDir'   => '1.006',
        'File::Spec'      => '0',
        'File::XDG'       => '1.03',
        'IPC::Run3'       => '0.049',
        'Path::Tiny'      => '0.150',
        'Pod::Usage'      => '0',
        'Term::ANSIColor' => '5.01',
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        no_index    => {
            directory => [
                qw<
                    eg
                    examples
                    share
                    xt
                >
            ],
        },
        prereqs => {
            develop => {
                recommends => {
                    'App::CPANTS::Lint' => '0',
                    'Data::Printer'     => '0',
                    'Devel::Cover'      => '0',
                    'Devel::NYTProf'    => '0',
                    'Perl::Critic'      => '0',
                    'Perl::Tidy'        => '0',
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
                    'Data::Printer'      => '1.002001',
                    'Getopt::Long::More' => '0.007',
                    'TOML::Tiny'         => '0.21',
                },
            },
            test => {
                recommends => {
                    'Data::Printer' => '1.002001',
                    'TOML::Tiny'    => '0.21',
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
        x_spdx_expression => 'MIT-0',
    },
);

WriteMakefile(%WriteMakefileArgs);
