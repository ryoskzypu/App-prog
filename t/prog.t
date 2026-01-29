#!/usr/bin/env perl
#
# Test every component of App::prog to ensure correct behavior. App::prog must
# run as documented in its POD (also in its wrapper POD).
#
# NOTE:
#   The color option with true value (auto) cannot be tested reliably, because
#   TAP::Harness/prove and Test2::Harness/yath seem to modify STDOUT, thus '-t STDOUT'
#   returns the wrong value.
#
#   Things not tested:
#
#     Completion
#       I'm not sure even how to start since there are so many components in the
#       Getopt::Long::More ecosystem, that also depends on specific shell and system.
#
#     Signals
#       It is not worth complicating a test script by messing with IPC. This can
#       be simply tested with a sleep() call in run() or prog in STDIN mode, then
#       manually send the signals.

use v5.40.0;

use strict;
use warnings;

use Test2::V1 -utf8, qw<
    subtest
    skip_all
    todo
    is
    isnt
    isa_ok
    like
    ok
    number
    pass
    fail
    dies
>;

use App::prog;

use File::Basename qw< basename >;
use File::Spec     ();
use Cwd            qw< getcwd >;
use Path::Tiny;
use Capture::Tiny qw< capture capture_stderr >;

my $DDP++;

try {
    require Data::Printer;
}
catch ($e) {
    $DDP = 0;
}

my $PROG = basename($0);

my $FAIL_MSG = 'This test fails when run by TAP::Harness/prove or Test2::Harness/yath';

my %DEFAULTS = (
    class => 'App::prog',
    data  => <<~'_',
        line1
        line2
        _
    prefs => {
        color   => 'never',
        dry_run => 0,
        quiet   => 0,
        verbose => 0,
    },
    palette => {
        data     => 'black on_grey18',
        debug    => 'green',
        dump     => 'r102g217b239',
        dry_run  => 'magenta',
        filename => 'grey12',
        header   => 'bold cyan',
        verbose  => 'blue',
    },
    config => {
        file => "$PROG.toml",
        data => <<~'_',
            # prog configuration file

            color   = 'never'
            dry_run = false
            quiet   = false
            verbose = false

            [palette]
            data     = 'black on_grey18'
            debug    = 'green'
            dump     = 'r102g217b239'
            dry_run  = 'magenta'
            filename = 'grey12'
            header   = 'bold cyan'
            verbose  = 'blue'
            _
    },
);

my %PREFS = (
    prefs => {
        $DEFAULTS{prefs}->%*,
        palette => { $DEFAULTS{palette}->%* },
    },
);

my $ANSI_RGX  = qr{\[ [0-9;]+ m}x;
my $RESET_RGX = qr{\[ 0? m}x;

my %REGEX = (
    ansi      => qr{\e $ANSI_RGX}x,
    reset     => qr{\e $RESET_RGX}x,
    lit_ansi  => qr{\\e \e $ANSI_RGX $ANSI_RGX}x,
    lit_reset => qr{\\e \e $ANSI_RGX $RESET_RGX}x,
);

# Unit test each method separately.
subtest 'Unit test' => sub {
    #skip_all;

    # Test constructor.
    subtest 'Construct App::prog instance' => sub {
        #skip_all;

        my $prog = App::prog->new(%PREFS);

        like(
            dies { $prog->new() },
            qr{\AInvocant is not a package name},
            'got exception (blessed invocant)',
        );

        is(
            $prog->{prefs}, $PREFS{prefs},
            'preferences match',
        );

        isa_ok(
            $prog, [ $DEFAULTS{class} ],
            'return value (blessed)',
        );
    };

    # Test options processing.
    #
    # NOTE:
    #   Do not test --help and --version because they must exit() immediately when
    #   invoked via CLI; they are so simple that can be skipped.
    subtest 'Options processing' => sub {
        #skip_all;

        my %TESTS_OPTS = (
            'nothing' => {
                success => undef,
            },
            '--bogus' => {
                error => [ qw< --bogus > ],
            },
            '-c' => {
                success => [ qw< -c > ],
                opts    => [ color => 1 ],
            },
            '--color=s' => {
                success => [ qw< --color=always > ],
                error   => [ qw< --color > ],
                opts    => [ color => 'always' ],
            },
            '--palette=s%' => {
                success => [ qw< --palette data=green > ],
                error   => [ qw< --palette > ],
                opts    => [ data => 'green' ],
            },
            '--dry-run' => {
                success => [ qw< --dry-run > ],
                opts    => [ dry_run => 1 ],
            },
            '-q, --quiet' => {
                success => [ qw< -q --quiet > ],
                opts    => [ quiet => 1 ],
            },
            '-v, --verbose' => {
                success => [ qw< -v --verbose > ],
                opts    => [ verbose => 1 ],
            },
        );

        my $prog = App::prog->new;

        foreach my ( $k, $v ) (%TESTS_OPTS) {
            subtest $k => sub {
                if ( defined $v->{error} ) {
                    my ( $stderr, @return ) = capture_stderr {
                        return $prog->_process_opts( $v->{error} );
                    };

                    is(
                        $return[0], number(2),
                        'return value (invalid option)',
                    );

                    return if $k eq '--bogus';
                }

                is(
                    $prog->_process_opts( $v->{success} ), number(0),
                    'return value (success)',
                );

                return if $k eq 'nothing';

                is(
                    $k eq '--palette=s%'
                    ? $prog->{opts}{palette}{ $v->{opts}[0] }
                    : $prog->{opts}{ $v->{opts}[0] },

                    $v->{opts}[1],
                    'opts value',
                );
            };
        }

        subtest '--generate-cfg' => sub {
            my %TESTS_GEN = (
                XDG_CONFIG_HOME => {
                    test => 'XDG',
                    env  => 'XDG_CONFIG_HOME',
                },
                # $HOME/.config/$PROG
                'XDG_CONFIG_HOME (fallback)' => {
                    test => 'XDG_fallback',
                    env  => 'HOME',
                },
                # NOTE:
                #   File::HomeDir respects $HOME in non Unix systems, so hopefully
                #   no portability problems.
                '$HOME' => {
                    test => 'HOME',
                    env  => 'HOME',
                },
            );

            my $file = $DEFAULTS{config}{file};

            my sub generate_cfg (%opts)
            {
                my $temp = Path::Tiny->tempdir;

                if ( $opts{test} eq 'XDG_fallback' ) {
                    $temp->child('.config')
                      ->mkdir( { mode => oct 700 } )
                      or die $!;
                }

                local $ENV{ $opts{env} } = $temp;

                my $path = $opts{test} eq 'XDG'
                  ? $temp->child($PROG)->child($file)                                                    # /tmp/4l9lQo4iRP/prog.t/prog.t.toml
                  : $opts{test} eq 'XDG_fallback' ? $temp->child('.config')->child($PROG)->child($file)  # /tmp/4l9lQo4iRP/.config/prog.t/prog.t.toml
                  : $opts{test} eq 'HOME'         ? $temp->child($file)                                  # /tmp/4l9lQo4iRP/prog.t.toml
                  :                                 ();

                # Test if config file is not overwritten when it exists.
                $path->touchpath if defined $opts{exists} && $opts{exists};

                my $ret = App::prog::_generate_cfg_handler( '', '', 'test' );

                if ( $ret->{code} == 0 ) {
                    if ( -f $path ) {
                        my $data = $path->slurp_utf8;

                        is(
                            $data, $DEFAULTS{config}{data},
                            'config contents match',
                        );
                    }
                }
                else {
                    $ret->{exists}
                      ? pass( $ret->{msg} )
                      : fail( $ret->{msg} );
                }
            }

            foreach my ( $k, $v ) (%TESTS_GEN) {
                subtest "Test $k" => sub {
                    generate_cfg( $v->%* );
                    generate_cfg( $v->%*, exists => 1 );
                };
            }
        };
    };

    # Test configuration file processing.
    subtest 'Configuration processing' => sub {
        #skip_all;
        try {
            require TOML::Tiny;
            TOML::Tiny->import( qw< from_toml > );
        }
        catch ($e) {
            skip_all('TOML::Tiny is required to read configuration file');
        }

        subtest 'Test config file discovery order' => sub {
            #skip_all;

            my $cwd  = getcwd();
            my $temp = Path::Tiny->tempdir;
            my $file = $DEFAULTS{config}{file};

            chdir $temp or die $!;

            # Create paths
            my $home        = $temp->child('home/test')->mkdir or die $!;           # /tmp/4l9lQo4iRP/home/test
            my $path_curr   = path($file);                                          # /tmp/4l9lQo4iRP/prog.t.toml
            my $path_xdg    = $home->child($PROG)->child($file);                    # /tmp/4l9lQo4iRP/home/test/prog.t/prog.t.toml
            my $path_xdg_fb = $home->child('.config')->child($PROG)->child($file);  # /tmp/4l9lQo4iRP/home/test/.config/prog.t/prog.t.toml
            my $path_home   = $home->child($file);                                  # /tmp/4l9lQo4iRP/home/test/prog.t.toml
            my $path_env    = $temp->child('env')->child($file);                    # /tmp/4l9lQo4iRP/env/prog.t.toml

            my sub init_test ()
            {
                my $prog = App::prog->new;

                # Create files
                $path_curr->touch;
                $path_xdg->touchpath;
                $path_xdg_fb->touchpath;
                $path_home->touchpath;
                $path_env->touchpath;

                #system(qw< tree -a >);

                return $prog;
            }

            my sub find_it (%opts)
            {
                die 'Missing class' unless defined $opts{class};

                my $prog     = $opts{class};
                my $comp     = $opts{comp};
                my $fallback = $opts{fb} // 0;

                local $ENV{XDG_CONFIG_HOME} = $fallback ? undef : $home;
                local $ENV{HOME}            = $home;

                my $ret = $prog->_find_config;
                fail('Failed to create Path::Tiny object') unless defined $prog->{path};

                if ( defined $comp ) {
                    if ( $comp eq 'is' ) {
                        is(
                            $prog->{path}->stringify, $opts{path}->stringify,
                            'config file match',
                        );
                    }
                    elsif ( $comp eq 'isnt' ) {
                        my $name = "config file exists in $opts{name} (no match)";

                        isnt(
                            $prog->{path}->stringify, $opts{path}->stringify,
                            $name,
                        );
                    }
                }

                isa_ok(
                    $ret, [ $DEFAULTS{class} ],
                    'return value (blessed)',
                );
            }

            subtest 'Current directory' => sub {
                my $prog = init_test();

                find_it(
                    class => $prog,
                    comp  => 'is',
                    path  => $path_curr,
                );
            };

            subtest 'XDG_CONFIG_HOME' => sub {
                my $prog = init_test();

                find_it(
                    class => $prog,
                    comp  => 'isnt',
                    path  => $path_xdg,
                    name  => 'current dir',
                );

                $path_curr->remove;
                find_it(
                    class => $prog,
                    comp  => 'is',
                    path  => $path_xdg,
                );
            };

            subtest 'XDG_CONFIG_HOME (fallback)' => sub {
                my $prog = init_test();

                find_it(
                    class => $prog,
                    comp  => 'isnt',
                    path  => $path_xdg_fb,
                    name  => 'current dir',
                );

                $path_curr->remove;
                find_it(
                    class => $prog,
                    comp  => 'isnt',
                    path  => $path_xdg_fb,
                    name  => 'XDG_CONFIG_HOME',
                );

                $path_xdg->remove;
                find_it(
                    class => $prog,
                    comp  => 'is',
                    path  => $path_xdg_fb,
                    fb    => 1,
                );
            };

            subtest '$HOME' => sub {
                my $prog = init_test();

                find_it(
                    class => $prog,
                    comp  => 'isnt',
                    path  => $path_home,
                    name  => 'current dir',
                );

                $path_curr->remove;
                find_it(
                    class => $prog,
                    comp  => 'isnt',
                    path  => $path_home,
                    name  => 'XDG_CONFIG_HOME',
                );

                $path_xdg->remove;
                find_it(
                    class => $prog,
                    comp  => 'isnt',
                    path  => $path_home,
                    name  => 'XDG_CONFIG_HOME fallback',
                    fb    => 1,
                );

                $path_xdg_fb->remove;
                find_it(
                    class => $prog,
                    comp  => 'is',
                    path  => $path_home,
                );
            };

            subtest 'Environment variable' => sub {
                my $prog = init_test();

                local $ENV{PROG_CFG} = $path_env;

                find_it(
                    class => $prog,
                    comp  => 'is',
                    path  => $path_env,
                );
            };

            chdir $cwd or die $!;  # tempdir cleanup
        };

        subtest 'Test config file parsing' => sub {
            #skip_all;

            my $temp = Path::Tiny->tempdir;
            my $path = $temp->child( $DEFAULTS{config}{file} );
            my $prog = App::prog->new;

            is(
                $prog->_read_config, number(0),
                'return value (missing $path)',
            );

            $prog->{path} = $path;

            {
                $path->spew_utf8('invalid = [');

                my ( $stderr, @return ) = capture_stderr {
                    return $prog->_read_config;
                };

                is(
                    $return[0], number(1),
                    'return value (invalid config syntax)',
                );
            }

            $path->spew_utf8( $DEFAULTS{config}{data} );
            is(
                $prog->_read_config, number(0),
                'return value (success)',
            );

            my $config = from_toml( $DEFAULTS{config}{data} );

            is(
                $prog->{config}, $config,
                'config contents match',
            );
        };

    };

    # Test preferences processing.
    subtest 'Preferences processing' => sub {
        #skip_all;

        subtest 'Test preferences merging' => sub {
            #skip_all;

            my %EXPECTED = (
                prefs => {
                    color   => 0,
                    dry_run => 0,
                    quiet   => 0,
                    verbose => 0,
                    palette => {
                        data     => 'black on_grey18',
                        debug    => 'green',
                        dump     => 'r102g217b239',
                        dry_run  => 'magenta',
                        filename => 'grey12',
                        header   => 'bold cyan',
                        verbose  => 'blue',
                    },
                },
            );

            my sub is_match (%args)
            {
                my $name = "pref match ($args{name})";
                my $prog = App::prog->new(%PREFS);

                $prog->{opts}   = $args{opts}   // {};
                $prog->{config} = $args{config} // {};

                $prog->_process_prefs;

                $args{set_opts}->() if defined $args{set_opts};

                is(
                    $prog->{prefs}, $EXPECTED{prefs},
                    $name,
                );
            }

            subtest 'Normal precedence' => sub {
                is_match( name => 'no overriding' );
            };

            subtest 'Options over config precedence' => sub {
                #skip_all;

                my $todo = todo $FAIL_MSG;

                is_match(
                    name => 'options override config',
                    opts => {
                        color   => 1,
                        palette => {
                            data => 'red',
                        },
                    },
                    config => {
                        color   => 0,
                        palette => {
                            data => 'green',
                        },
                    },
                    set_opts => sub {
                        $EXPECTED{prefs}{color} = 1;
                        $EXPECTED{prefs}{palette}{data} = 'red';
                    },
                );
            };

            subtest 'Options + config over prefs precedence' => sub {
                #skip_all;

                my $todo = todo $FAIL_MSG;

                is_match(
                    name => 'options + config override prefs',
                    opts => {
                        color   => 1,
                        palette => {
                            data => 'red',
                        },
                    },
                    config => {
                        color   => 0,
                        dry_run => 1,
                        palette => {
                            data  => 'green',
                            debug => 'blue',
                        },
                    },
                    set_opts => sub {
                        $EXPECTED{prefs}{color}          = 1;
                        $EXPECTED{prefs}{dry_run}        = 1;
                        $EXPECTED{prefs}{palette}{data}  = 'red';
                        $EXPECTED{prefs}{palette}{debug} = 'blue';
                    },
                );
            };
        };

        subtest 'Test color pref boolean translation' => sub {
            #skip_all;

            my $todo = todo $FAIL_MSG;

            my %TESTS = (
                auto => {
                    color   => 'auto',
                    name    => 'true',
                    non_tty => 'false',
                    ret     => 0,
                },
                '-c' => {
                    color   => 1,
                    name    => 'true',
                    non_tty => 'false',
                    ret     => 0,
                },
                never => {
                    color   => 'never',
                    name    => 'false',
                    non_tty => 'false',
                    ret     => 0,
                },
                always => {
                    color   => 'always',
                    name    => 'true',
                    non_tty => 'true',
                    ret     => 0,
                },
                invalid => {
                    color   => 'bogus',
                    name    => 'true',
                    non_tty => 'true',
                    ret     => 1,
                },
            );

            my sub is_bool (%args)
            {
                my $name = $args{name} // '';
                my $bool = $name eq 'true' ? 1 : 0;

                if ( defined $args{non_tty} ) {
                    $name = "$args{non_tty}; non-TTY";
                    $bool = $args{non_tty} eq 'true' ? 1 : 0;
                }

                # Emulate non-TTY STDOUT.
                local *STDOUT if defined $args{non_tty};

                my $prog = App::prog->new;

                $prog->{opts} = {
                    color => $args{color},
                };

                my ( $stderr, @return ) = capture_stderr {
                    return $prog->_process_prefs;
                };

                is(
                    $prog->{prefs}{color}, $bool,
                    "boolean match ($name)",
                ) if $return[0] == 0;

                my $ret_name =
                  $args{ret} == 0
                  ? 'success'
                  : 'invalid color';

                $ret_name .= '; non-TTY' if defined $args{non_tty};

                is(
                    $return[0], number( $args{ret} ),
                    "return value ($ret_name)",
                );
            }

            foreach my ( $k, $v ) (%TESTS) {
                subtest $k => sub {
                    is_bool(
                        color => $v->{color},
                        name  => $v->{name},
                        ret   => $v->{ret},
                    );

                    is_bool(
                        non_tty => $v->{non_tty},
                        color   => $v->{color},
                        ret     => $v->{ret},
                    );
                };
            }
        };

        subtest 'Test quiet mode' => sub {
            #skip_all;

            my $prog = App::prog->new;

            $prog->{opts} = {
                quiet => 1,
            };

            my $ret = $prog->_process_prefs;

            is(
                [ stat STDOUT ], [ stat File::Spec->devnull() ],
                'STDOUT redirected to null device',
            );

            is(
                $ret, number(0),
                'return value (success)',
            );
        };
    };

    # Test environment processing.
    subtest 'Environment processing' => sub {
        skip_all('Data::Printer is required to display debug information') unless $DDP;

        my $todo = todo 'This test fails when parent shell exports PROG_DEBUG';

        my sub is_env_set ($env)
        {
            my $name = $env ? 'set' : 'unset';

            my $prog = App::prog->new;

            local $ENV{PROG_DEBUG} = 1 if $env;

            my $ret = $prog->_process_env;

            is(
                $prog->{env}{debug}, number($env),
                "PROG_DEBUG ($name)",
            );

            isa_ok(
                $ret, [ $DEFAULTS{class} ],
                'return value (blessed)',
            );
        }

        is_env_set(0);
        is_env_set(1);
    };

    # Test file processing.
    subtest 'File processing' => sub {
        #skip_all;

        my %TESTS = (
            STDIN => {
                'No file' => {
                    name => 'no file',
                    ret  => 0,
                },
                q{'-'} => {
                    name => '-',
                    ret  => 0,
                },
            },
            FILE => {
                Normal => {
                    name => 'file',
                    ret  => 0,
                },
                Invalid => {
                    name => 'invalid',
                    ret  => 2,
                },
            },
        );

        my sub is_data (%opts)
        {
            my $temp;
            $temp = Path::Tiny->tempfile if $opts{name} eq 'file';

            my $prog = App::prog->new;

            my $stdin;

            my $data = $DEFAULTS{data};

            $prog->{argv} =
                $opts{name} eq 'no file' ? undef
              : $opts{name} eq '-'       ? [ qw< - > ]
              : $opts{name} eq 'file'    ? [ $temp->stringify ]
              : $opts{name} eq 'invalid' ? [ qw< bogus > ]
              :                            ();

            $temp->spew_utf8($data) if defined $temp;

            if ( $opts{name} eq 'no file' || $opts{name} eq '-' ) {
                open $stdin, '<', \$data or die $!;
            }
            local *STDIN = $stdin if defined $stdin;

            my ( $stderr, @return ) = capture_stderr {
                return $prog->_process_file;
            };

            close $stdin or die $! if defined $stdin;

            is(
                $prog->{data}, $data,
                'data match',
            ) if $opts{name} ne 'invalid';

            my $ret_name =
                $opts{ret} == 0 ? 'success'
              : $opts{ret} == 2 ? 'not a file'
              :                   ();

            is(
                $return[0], number( $opts{ret} ),
                "return value ($ret_name)",
            );
        }

        foreach my ( $k1, $v1 ) (%TESTS) {
            subtest $k1 => sub {
                foreach my ( $k2, $v2 ) ( $v1->%* ) {
                    subtest $k2 => sub {
                        is_data(
                            name => $v2->{name},
                            ret  => $v2->{ret},
                        );
                    };
                }
            };
        }
    };

    # Test file output.
    subtest 'File output' => sub {
        #skip_all;

        my %EXPECTED = (
            file => 'file.txt',
            data => $DEFAULTS{data},
            test => {
                data    => {},
                verbose => {
                    verbose => 1,
                },
                debug => {
                    debug => 1,
                },
                'verbose + data' => {
                    verbose => 1,
                    debug   => 1,
                },
            },
            output => {
                verbose => 'Printing file',
                palette => {
                    data     => 'black on_grey18',
                    debug    => 'yellow',
                    dry_run  => 'cyan',
                    dump     => 'r102g217b239',
                    filename => 'bright_green',
                    header   => 'bold white',
                    verbose  => 'black on_blue',
                },
            },
        );

        my %TESTS = (
            normal    => {},
            colorized => {
                color => 1,
            },
            'colorized (palette)' => {
                color   => 1,
                palette => 1,
            },
        );

        my sub is_output (%opts)
        {
            my $prog = App::prog->new;

            my $color   = $prog->{prefs}{color} = $opts{color} // 0;
            my $palette = $opts{palette}                       // 0;
            my $verbose = $prog->{prefs}{verbose} = $opts{verbose} // 0;
            my $debug   = $prog->{env}{debug}     = $opts{debug}   // 0;

            $prog->{prefs}{palette} = $EXPECTED{output}{palette} if $color && $palette;

            $prog->{file} = $EXPECTED{file};
            $prog->{data} = $EXPECTED{data};

            my $ansi  = $color ? $REGEX{ansi}  : '';
            my $reset = $color ? $REGEX{reset} : '';

            # Literal ANSI codes
            my $lit_ansi  = $color ? $REGEX{lit_ansi}  : '';
            my $lit_reset = $color ? $REGEX{lit_reset} : '';

            my $out_data = my $DATA_RGX = qr{
                \A $ansi File $reset\ $ansi '$EXPECTED{file}' $reset\ $ansi contents $reset\n
                \s+  $ansi line1 $reset\n
                \s+  $ansi line2 $reset\n
                \n
                \z
            }x;

            my $out_verbose = my $verbose_rgx =
              $verbose
              ? qr{$ansi \Q$EXPECTED{output}{verbose}\E $reset\n}x
              : '';

            my $out_debug = my $DEBUG_RGX = qr{
                \A
                $verbose_rgx

                $ansi \$file\ =\ '$EXPECTED{file}' $reset\n

                $ansi \$msg\  =\ $reset $ansi " $reset
                    $ansi $ansi $lit_ansi File $ansi $lit_reset\ $ansi $lit_ansi '$EXPECTED{file}' $ansi $lit_reset\ $ansi $lit_ansi contents $ansi $lit_reset $ansi \\n
                    $ansi $reset $ansi " $reset\n

                $ansi \$data\ =\ $reset $ansi " $reset
                    $ansi $ansi $lit_ansi line1 $ansi $lit_reset $ansi \\n
                    $ansi $ansi $lit_ansi line2 $ansi $lit_reset $ansi \\n
                    $ansi $reset $ansi " $reset\n
                \n
                \z
            }x;

            my ( $stdout, $stderr, @return ) = capture {
                return $prog->_print_file;
            };

            like(
                $stdout, $out_data,
                'expected output (data)',
            );

            like(
                $stderr, $out_debug,
                'expected output (verbose + debug)',
            ) if $verbose && $debug;

            like(
                $stderr, $out_verbose,
                'expected output (verbose)',
            ) if $verbose && !$debug;

            like(
                $stderr, $out_debug,
                'expected output (debug)',
            ) if $debug && !$verbose;

            isa_ok(
                $return[0], [ $DEFAULTS{class} ],
                'return value (blessed)',
            );
        }

        foreach my ( $k1, $v1 ) (%TESTS) {
            subtest "Test $k1 output" => sub {
                foreach my ( $k2, $v2 ) ( $EXPECTED{test}->%* ) {
                    next if !$DDP && $k2 eq 'debug' || $k2 eq 'verbose + data';

                    subtest $k2 => sub {
                        is_output( $v2->%*, $v1->%* );
                    };
                }
            };
        }
    };

    # Test stat output.
    subtest 'Stat output' => sub {
        #skip_all;
        skip_all('Test requires GNU stat on Linux') unless $^O eq 'linux';

        my %EXPECTED = (
            data => $DEFAULTS{data},
            test => {
                stat    => {},
                verbose => {
                    verbose => 1,
                },
                debug => {
                    debug => 1,
                },
                'verbose + data' => {
                    verbose => 1,
                    debug   => 1,
                },
            },
            output => {
                verbose => 'Running stat(1) command',
                palette => {
                    data     => 'black on_grey18',
                    debug    => 'yellow',
                    dry_run  => 'cyan',
                    dump     => 'r102g217b239',
                    filename => 'bright_green',
                    header   => 'bold white',
                    verbose  => 'black on_blue',
                },
            },
        );

        my %TESTS = (
            normal    => {},
            colorized => {
                color => 1,
            },
            'colorized (palette)' => {
                color   => 1,
                palette => 1,
            },
            'normal (dry-run)' => {
                dry_run => 1,
            },
            'colorized (dry-run)' => {
                dry_run => 1,
                color   => 1,
            },
            'colorized (palette + dry-run)' => {
                dry_run => 1,
                color   => 1,
                palette => 1,
            },
        );

        my sub is_output (%opts)
        {
            # Hardcode permissions to avoid messing with $stat->mode conversions.
            umask 0022;  # 0644

            my $prog = App::prog->new;

            my $color   = $prog->{prefs}{color} = $opts{color} // 0;
            my $palette = $opts{palette}                       // 0;
            my $verbose = $prog->{prefs}{verbose} = $opts{verbose} // 0;
            my $debug   = $prog->{env}{debug}     = $opts{debug}   // 0;
            my $dry_run = $prog->{prefs}{dry_run} = $opts{dry_run} // 0;

            $prog->{prefs}{palette} = $EXPECTED{output}{palette} if $color && $palette;

            if ( defined $opts{err} ) {
                $prog->{file} = "bogus_$$";

                my ( $stdout, $stderr, @return ) = capture {
                    return $prog->_stat;
                };

                is(
                    $return[0], number(1),
                    'return value (nonexistent file)',
                );

                return;
            }

            my $temp = Path::Tiny->tempfile;
            $temp->spew_utf8( $EXPECTED{data} );

            $prog->{file} = $temp->stringify;

            my $stat = $temp->stat;

            # See https://stackoverflow.com/a/17213290.
            my $dev   = $stat->dev;
            my $major = ( $dev >> 8 ) & 0xff;
            my $minor = $dev & 0xff;

            my $ino     = $stat->ino;
            my $mode    = '0644/-rw-r--r--';
            my $nlink   = $stat->nlink;
            my $uid     = $stat->uid;
            my $gid     = $stat->gid;
            my $size    = $stat->size;
            my $atime   = $stat->atime;
            my $mtime   = $stat->mtime;
            my $ctime   = $stat->ctime;
            my $blksize = $stat->blksize;
            my $blocks  = $stat->blocks;

            my $username = getpwuid $uid;
            my $grpname  = getgrgid $gid;

            # NOTE:
            #   Very naive regex; it is too complicated to match the stat(1) time outputs correctly.
            #   E.g. 2025-12-28 18:30:41.738150571 +0000
            my $DATE_RGX = qr{
                \b
                  [0-9]{4} - [0-9]{2} - [0-9]{2}
                \ [0-9]{2} : [0-9]{2} : [0-9]{2} \. [0-9]{9}
                \ [+-] [0-9]{4}
                \b
            }x;

            my $ansi  = $color ? $REGEX{ansi}  : '';
            my $reset = $color ? $REGEX{reset} : '';

            # Literal ANSI codes
            my $lit_ansi  = $color ? $REGEX{lit_ansi}  : '';
            my $lit_reset = $color ? $REGEX{lit_reset} : '';

            my $out_stat = my $STAT_RGX = qr{
                \A   $ansi File $reset\ $ansi '$temp' $reset\ $ansi status\ info $reset\n
                \s+  $ansi\s*     File:\ $temp $reset\n
                \s+  $ansi\s*     Size:\ $size\s+        Blocks:\ $blocks\s+                   IO\ Block:\ $blksize\s+ regular\ file $reset\n
                \s+  $ansi      Device:\ $major,$minor\t  Inode:\ $ino\s+                          Links:\ $nlink                    $reset\n
                \s+  $ansi      Access:\ \( $mode \)\s+     Uid:\ \(\s+ $uid/\s+ $username \)\s+       Gid:\ \(\s+ $gid/\s+ $grpname \)  $reset\n
                \s+  $ansi      Access:\ $DATE_RGX $reset\n
                \s+  $ansi      Modify:\ $DATE_RGX $reset\n
                \s+  $ansi      Change:\ $DATE_RGX $reset\n
                \s+  ${ansi}\s*  Birth:\ $DATE_RGX $reset\n
                \z
            }x;

            my $out_verbose = my $verbose_rgx =
              $verbose
              ? qr{$ansi \Q$EXPECTED{output}{verbose}\E $reset\n}x
              : '';

            my $out_debug = my $DEBUG_RGX = qr{
                \A
                $verbose_rgx
                $ansi \$command:\ 'stat\ $temp' $reset\n
                $ansi \$\?\ =\ 0                $reset\n
                $ansi \$stdout\ =\  $reset $ansi " $reset
                $ansi $ansi $lit_ansi\s+   File:\ $temp          $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi\s+   Size:\ $size\s+       $ansi \\t $ansi Blocks:\ $blocks\s+                   IO\ Block:\ $blksize\s+ regular\ file $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi    Device:\ $major,$minor  $ansi \\t $ansi  Inode:\ $ino\s+                          Links:\ $nlink                    $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi    Access:\ \( $mode \)\s+                    Uid:\ \(\s+ $uid/\s+ $username \)\s+       Gid:\ \(\s+ $gid/\s+ $grpname \)  $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi    Access:\ $DATE_RGX         $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi    Modify:\ $DATE_RGX         $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi    Change:\ $DATE_RGX         $ansi $lit_reset $ansi \\n
                $ansi $ansi $lit_ansi\    Birth:\ $DATE_RGX         $ansi $lit_reset $ansi \\n
                $ansi $reset $ansi "  $reset\n
                $ansi \$stderr\ =\ '' $reset\n
                \z
            }x;

            my $out_dry = my $DRY_RGX = qr{^$ansi\s+Executing 'stat \Q$prog->{file}\E'$reset\n}m;

            my $out_debug_dry = my $DRY_DEBUG_RGX = qr{
                \A
                $verbose_rgx
                $ansi \$command:\ 'stat\ $temp' $reset\n
                $DRY_RGX
                \z
            }x;

            my ( $stdout, $stderr, @return ) = capture {
                return $prog->_stat;
            };

            {
                my $name = 'expected output (stat)';

                like(
                    $stdout, $out_stat,
                    $name,
                ) unless $dry_run;

                like(
                    $stderr, $out_dry,
                    $name,
                ) if $dry_run;
            }

            {
                my $name = 'expected output (verbose + debug)';

                like(
                    $stderr, $out_debug,
                    $name,
                ) if $verbose && $debug && !$dry_run;

                like(
                    $stderr, $out_debug_dry,
                    $name,
                ) if $dry_run && $verbose && $debug;
            }

            like(
                $stderr, $out_verbose,
                'expected output (verbose)',
            ) if $verbose && !$debug;

            like(
                $stderr, $out_debug,
                'expected output (debug)',
            ) if $debug && !$verbose && !$dry_run;

            is(
                $return[0], number(0),
                'return value (success)',
            );
        }

        foreach my ( $k1, $v1 ) (%TESTS) {
            subtest "Test $k1 output" => sub {
                foreach my ( $k2, $v2 ) ( $EXPECTED{test}->%* ) {
                    next if !$DDP && $k2 eq 'debug' || $k2 eq 'verbose + data';

                    subtest $k2 => sub {
                        is_output( $v2->%*, $v1->%* );
                    };
                }
            };
        }

        subtest 'Test error' => sub {
            is_output( err => 1 );
        };
    };
};

# Test if App::prog methods work together correctly.
#
# NOTE:
#   Assert that prog runs correctly as documented in the POD, thus FILE mode is
#   enough for the test, since everything else is covered by unit testing.
subtest 'Integration test' => sub {
    #skip_all;

    subtest 'FILE mode (default prefs)' => sub {
        my $temp = Path::Tiny->tempfile;
        my $data = $DEFAULTS{data};

        $temp->spew_utf8($data);

        my ( $stdout, $stderr, @return ) = capture {
            return App::prog->new
              ->init( $temp->stringify )
              ->run;
        };

        is(
            $return[0], number(0),
            'return value (success)',
        );
    };
};

T2->done_testing;
