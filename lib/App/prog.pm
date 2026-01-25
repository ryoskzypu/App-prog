package App::prog;

use v5.40.0;

use strict;
use warnings;

use sigtrap 'handler' => \&_sig_handler, qw< INT TERM >;  # Handle INT and TERM signals.
use utf8;                                                 # Decode all Unicode strings from source code.
use open qw< :std :encoding(UTF-8) >;                     # Encode/decode STDIN, STDOUT, STDERR, and filehandles to UTF-8.
use feature qw< unicode_strings >;                        # Use Unicode rules for all string operations.

use Encode qw< encode decode >;
use Encode::Locale;
use Path::Tiny;                                                # Add several file operations.
use File::Basename qw< basename >;
use File::Spec     ();
use File::HomeDir  ();                                         # Find home directory portably.
use File::XDG 1.00;                                            # Add XDG base directory specification.
use Getopt::Long::More qw< GetOptionsFromArray optspec >;
use Pod::Usage;
use Const::Fast;                                               # Add read-only variables support.
use Term::ANSIColor 2.02 qw< colored colorstrip colorvalid >;  # Add ANSI color support.
use IPC::Run3;                                                 # Redirect/capture STDIN, STDOUT, and STDERR from a subprocess.

# Additional useful modules
#   Term::ReadLine::Gnu    # Add Readline support.
#   Term::ReadKey;         # Add non-blocking key reads from TTY.
#   Path::Iterator::Rule;  # Find files recursively.
#   JSON::MaybeXS;         # Serialize JSON.
#   Mojo::UserAgent;       # Non-blocking HTTP requests.
#   Mojo::Log;             # Add logging support.

END { close STDOUT or die $! }  # Detect if data was written correctly.

$|++;                           # Disable STDOUT buffering.

our $VERSION = 'v1.0.0';

const my $PROG => basename($0);

const my %DEFAULTS => (
    prefs => {
        color   => 'never',
        dry_run => 0,
        quiet   => 0,
        verbose => 0,
    },
    palette => {
        data     => 'black on_grey18',
        debug    => 'green',
        dump     => 'r102g217b239',    # Cyan (DDP Material theme)
        dry_run  => 'magenta',
        filename => 'grey12',
        header   => 'bold cyan',
        verbose  => 'blue',
    },
    complete_outputs => [
        qw<
            data=
            debug=
            dump=
            dry_run=
            filename=
            header=
            verbose=
        >
    ],
    config => <<~'END',
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
        END
);

const my $SPACE  => "\x{20}";
const my $INDENT => $SPACE x 2;

$Term::ANSIColor::EACHLINE = "\n";

sub new ( $class, %prefs )
{
    die 'Invocant is not a package name' if ref $class;

    # Default preferences
    my %def = (
        prefs => {
            $DEFAULTS{prefs}->%*,
            palette => { $DEFAULTS{palette}->%* },
        },
    );

    if ( %prefs && exists $prefs{prefs} ) {
        _set_prefs(
            subject => $prefs{prefs},
            target  => $def{prefs},
            compare => { $def{prefs}->%* },  # Same as target (gets mutated), so copy it.
        );
    }

    %prefs = (%def);

    my $self = bless {%prefs}, $class;

    return $self;
}

sub init ( $self, @argv )
{
    die 'Missing blessed object' unless blessed $self;

    # NOTE:
    #   The processing of options must be done before the config one, otherwise
    #   config processing will run at every tab completion attempt.
    _exit( $self->_process_opts( \@argv ) );
    _exit( $self->_find_config->_read_config );
    _exit( $self->_process_prefs );
    $self->_process_env;

    return $self;
}

sub run ($self)
{
    die 'Missing blessed object' unless blessed $self;

    _exit( $self->_process_file );
    _exit( $self->_print_file->_stat );

    return 0;
}

sub _sig_handler
{
    my $signal = shift;

    # Exit cleanly if SIGINT or SIGTERM are caught.

    my $err = "$PROG: signal '$signal' caught; exiting\n";

    # ^C (Ctrl+c)
    if ( $signal eq 'INT' ) {
        warn "\n$err";
    }
    # E.g. 'pkill prog'.
    elsif ( $signal eq 'TERM' ) {
        warn $err;
    }

    # _cleanup();

    exit 0;
}

# Iterate a preferences hash (subject), optionally validate it against a prefs
# specification (compare), and set values on another hash (target).
sub _set_prefs (%opts)
{
    $opts{compare} //= {};

    foreach my $k ( qw< subject target compare > ) {
        die "Missing $k key"                   unless exists $opts{$k};
        die "$k value is not a HASH reference" if ref $opts{$k} ne 'HASH';
    }

    foreach my ( $k, $v ) ( $opts{subject}->%* ) {
        next unless defined $v;

        my $has_compare = keys $opts{compare}->%* ? 1 : 0;

        next if $has_compare && !exists $opts{compare}{$k};

        if ( $k eq 'palette' && ref $v eq 'HASH' ) {
            foreach my ( $output, $ansi ) ( $v->%* ) {
                next if $has_compare && !exists $opts{compare}{$k}{$output};

                $opts{target}{$k}{$output} = $ansi if colorvalid($ansi);
            }
        }
        else {
            $opts{target}{$k} = $v;
        }
    }
}

sub _process_opts ( $self, $argv //= undef )
{
    die 'Missing blessed object'          unless blessed $self;
    return 0                              unless defined $argv;
    die '$argv is not an ARRAY reference' if !defined reftype $argv || reftype $argv ne 'ARRAY';

    # Decode program arguments as locale encoding.
    my @argv = map { decode( locale => $_, 1 ) } $argv->@*;

    $self->{argv} = \@argv;

    # Transform Getopt::Long error warns.
    local $SIG{__WARN__} = sub {
        chomp( my $msg = shift );

        $msg =~ tr{"}{'};
        $msg = lcfirst $msg;

        warn "$PROG: $msg\n";
    };

    Getopt::Long::More::Configure(
        qw<
            default
            gnu_getopt
            no_ignore_case
        >
    );

    GetOptionsFromArray(
        $self->{argv},
        'c'       => \$self->{opts}{color},
        'color=s' => optspec(
            destination => \$self->{opts}{color},
            completion  => [ qw< never always auto > ],
        ),
        'palette=s%' => optspec(
            destination => sub {
                my ( $opt_name, $output, $ansi ) = @_;

                return unless exists $self->{prefs}{palette}{$output};

                $self->{opts}{palette}{$output} = $ansi if colorvalid($ansi);
            },
            completion => sub {
                require Complete::Util;
                my %args = @_;

                # Prevent '=' from being escaped.
                $ENV{COMPLETE_BASH_DEFAULT_ESC_MODE} = 'none';

                my $comp = Complete::Util::complete_array_elem(
                    word  => $args{word},
                    array => $DEFAULTS{complete_outputs},
                );

                # Prevent shell from appending a space.
                Complete::Util::ununiquify_answer( answer => $comp ) if scalar $comp->@* == 1;

                return $comp;
            },
        ),
        'dry-run'      => \$self->{opts}{dry_run},
        'generate-cfg' => \&_generate_cfg_handler,
        'h|help'       => sub { pod2usage( -exitval => 0, -verbose => 0 ); },
        'q|quiet'      => \$self->{opts}{quiet},
        'v|verbose'    => \$self->{opts}{verbose},
        'V|version'    => sub { print "$PROG $VERSION\n"; exit 0 },

    ) or return 2;

    return 0;
}

sub _generate_cfg_handler ( $opt_name, $opt_value, $test //= undef )
{
    my $file    = "$PROG.toml";
    my $gen_msg = 'failed to create default configuration file';

    my sub generate ($path)
    {
        $path->spew_utf8( $DEFAULTS{config} ) or defined $test
          ? return 1
          : _err( 1, $gen_msg );

        return 0;
    }

    # Check XDG_CONFIG_HOME
    my $xdg = File::XDG->new( name => $PROG, api => 1 );

    # ~/.config
    if ( -e $xdg->{config} ) {
        my $path      = $xdg->config_home;    # ~/.config/prog
        my $full_path = $path->child($file);  # ~/.config/prog/prog.toml

        my $msg = "failed to create '$path'";

        if ( !-f $full_path ) {
            if ( !$path->is_dir ) {
                $path->mkdir( { mode => oct 700 } )
                  or defined $test
                  ? return { msg => $msg, code => 1 }
                  : _err( 1, $msg );
            }

            return { msg => $gen_msg, code => 1 } if generate($full_path) == 1;
        }
        else {
            return {
                msg    => "file '$path' exists",
                code   => 1,
                exists => 1,
            };
        }
    }
    # Check home directory
    else {
        if ( defined( my $home = File::HomeDir->my_home ) ) {
            my $path = path($home)->child($file);  # ~/prog.toml

            if ( !-f $path ) {
                return { msg => $gen_msg, code => 1 } if generate($path) == 1;
            }
            else {
                return {
                    msg    => "file '$path' exists",
                    code   => 1,
                    exists => 1,
                };
            }
        }
        else {
            my $msg = 'failed to find home directory';

            defined $test
              ? return { msg => $msg, code => 1 }
              : _err( 1, $msg );
        }
    }

    defined $test
      ? return { code => 0 }
      : exit 0;
}

sub _find_config ($self)
{
    die 'Missing blessed object' unless blessed $self;

    # Check environment variable.
    {
        my $env = $ENV{PROG_CFG};

        if ( defined $env && -f $env ) {
            $self->{path} = path($env);

            return $self;
        }
    }

    my $file = "$PROG.toml";

    # Check current directory.
    {
        if ( -f $file ) {
            $self->{path} = path($file);

            return $self;
        }
    }

    # Check XDG_CONFIG_HOME.
    {
        my $xdg  = File::XDG->new( name => $PROG, api => 1 );
        my $path = $xdg->lookup_config_file($file);           # File::XDG returns a Path::Tiny object.

        $self->{path} = $path;

        return $self if defined $path;
    }

    # Check home directory.
    {
        if ( defined( my $home = File::HomeDir->my_home ) ) {
            my $path = path($home)->child($file);

            $self->{path} = $path if -f $path;
        }
    }

    return $self;
}

sub _read_config ($self)
{
    die 'Missing blessed object' unless blessed $self;

    my $path = $self->{path};

    return 0 unless defined $path;

    try {
        require TOML::Tiny;
        TOML::Tiny->import( qw< from_toml > );
    }
    catch ($e) {
        warn $e;
        _err( 1, 'TOML::Tiny is required to read configuration file' );
    }

    my $toml = $path->slurp_utf8;
    my ( $config, $error ) = from_toml($toml);

    if ( defined $error && $error ne '' ) {
        warn $error;
        warn "$PROG: failed to read '$path' configuration file\n";

        return 1;
    }

    _set_prefs(
        subject => $config,
        target  => $self->{config} //= {},
        compare => $self->{prefs},
    );

    return 0;
}

sub _process_prefs ($self)
{
    die 'Missing blessed object' unless blessed $self;

    $self->{opts}   //= {};
    $self->{config} //= {};

    # Merge preferences.
    # NOTE: Options prefs must override config file prefs.
    {
        # options prefs -> config prefs.
        _set_prefs(
            subject => $self->{opts},
            target  => $self->{config},
        );

        # config prefs -> default prefs.
        _set_prefs(
            subject => $self->{config},
            target  => $self->{prefs},
        );
    }

    # Translate color pref value to boolean.
    {
        my $color = $self->{prefs}{color};

        if ( defined $color ) {
            if ( $color eq 'auto' || $color eq '1' ) {
                $self->{prefs}{color} = -t STDOUT ? 1 : 0;
            }
            elsif ( $color eq 'never' ) {
                $self->{prefs}{color} = 0;
            }
            elsif ( $color eq 'always' ) {
                $self->{prefs}{color} = 1;
            }
            else {
                warn "$PROG: invalid color value '$color'\n";
                return 1;
            }
        }
    }

    # Quiet (redirect STDOUT to /dev/null)
    if ( $self->{prefs}{quiet} ) {
        open STDOUT, '>', File::Spec->devnull() or die $!;
    }

    return 0;
}

sub _process_env ($self)
{
    die 'Missing blessed object' unless blessed $self;

    $self->{env}{debug} = $ENV{PROG_DEBUG} ? 1 : 0;

    try {
        require Data::Printer if $self->{env}{debug};
    }
    catch ($e) {
        warn $e;
        _err( 1, 'Data::Printer is required to display debug information' );
    }

    return $self;
}

sub _process_file ($self)
{
    die 'Missing blessed object' unless blessed $self;

    $self->_verb("Processing file\n");

    my $file = $self->{argv}[0];
    my $path = '';
    my $data;

    if ( !defined $file || $file eq '-' ) {
        $file = '/dev/fd/' . fileno STDIN;  # Not portable, but OK.
        $data = do { local $/; <STDIN> };   # Slurp
    }
    else {
        $path = path($file);

        if ( $path->is_file ) {
            $data = $path->slurp_utf8;
        }
        else {
            warn "$PROG: '$file' is not a file\n";
            return 2;
        }
    }

    $self->{file} = $file;
    $self->{data} = $data;

    # Debug
    $self->_pdbg(
        <<~"_"
        \$file = '$file'
        \$path = '$path'
        _
    );
    $self->_pdump( '$data', $data );
    $self->_pdbg("\n");

    return 0;
}

sub _print_file ($self)
{
    die 'Missing blessed object' unless blessed $self;

    $self->_verb("Printing file\n");

    my $file = $self->{file};
    my $data = $self->{data};

    return $self unless defined $file;

    my $msg = $self->_maybe_color(
        join(
            $SPACE,
            colored( 'File',       $self->{prefs}{palette}{header} ),
            colored( "'$file'",    $self->{prefs}{palette}{filename} ),
            colored( "contents\n", $self->{prefs}{palette}{header} ),
        ),
    );

    $data = $self->_maybe_color( $data, 'data' ) if $data ne '';

    # Debug
    $self->_pdbg("\$file = '$file'\n");
    $self->_pdump( '$msg',  $msg );
    $self->_pdump( '$data', $data );
    $self->_pdbg("\n");

    print $msg;
    print _indent($data);
    print "\n";

    return $self;
}

sub _stat ($self)
{
    die 'Missing blessed object' unless blessed $self;

    my $file = $self->{file};

    return 0 unless defined $file;

    $self->_verb("Running stat(1) command\n");

    my @command = ( qw< stat >, $file );
    my $cmd     = join $SPACE, @command;

    print $self->_maybe_color(
        join(
            $SPACE,
            colored( 'File',          $self->{prefs}{palette}{header} ),
            colored( "'$file'",       $self->{prefs}{palette}{filename} ),
            colored( "status info\n", $self->{prefs}{palette}{header} ),
        ),
    );

    $self->_pdbg("\$command: '$cmd'\n");

    if ( $self->{prefs}{dry_run} ) {
        $self->_dry("${INDENT}Executing '$cmd'\n");
    }
    else {
        run3( \@command, \undef, \my $stdout, \my $stderr );

        $stdout = $self->_maybe_color( $stdout, 'data' );

        # Debug
        $self->_pdbg("\$? = $?\n");
        $self->_pdump( '$stdout', $stdout );
        $self->_pdbg("\$stderr = '$stderr'\n");

        if ( ( $? >> 8 ) > 0 ) {
            warn $stderr if defined $stderr && $stderr ne '';
            warn "$PROG: failed to run '$cmd'\n";
            return 1;
        }

        print _indent($stdout) if defined $stdout && $stdout ne '';
    }

    return 0;
}

sub _exit ($code)
{
    die 'Missing exit code' unless defined $code;

    exit $code if $code > 0;
}

# Print error message and exit the script with given exit code.
sub _err ( $code, $msg )
{
    die 'Missing exit code' unless defined $code;

    my $err = "$PROG: $msg\n";

    print STDERR $err;
    exit $code;
}

# Indent multiline text.
sub _indent ($text)
{
    die 'Missing text' unless defined $text;

    return ( $text =~ s{^(?=[^\n]+)}{$INDENT}mgr );
}

# Print verbose message.
sub _verb ( $self, $msg )
{
    die 'Missing blessed object' unless blessed $self;
    die 'Missing message'        unless defined $msg;

    return undef unless $self->{prefs}{verbose};

    print STDERR $self->_maybe_color( $msg, 'verbose' );
}

# Print debug message.
sub _pdbg ( $self, $msg )
{
    die 'Missing blessed object' unless blessed $self;
    die 'Missing message'        unless defined $msg;

    return undef unless $self->{env}{debug};

    print STDERR $self->_maybe_color( $msg, 'debug' );
}

# Print variable dump.
sub _pdump ( $self, $prefix, $var )
{
    die 'Missing blessed object' unless blessed $self;
    die 'Missing variable'       unless defined $var;

    return undef unless $self->{env}{debug};

    my $dump = join(
        '',
        colored( "$prefix = ", $self->{prefs}{palette}{dump} ),
        # NOTE: $var should be a scalar reference (\$var) when DDP is not loaded at compile time.
        Data::Printer::np(
            \$var,
            escape_chars  => 'nonascii',
            print_escapes => 1,
            colored       => 1,
            theme         => 'Material',
        ),
        "\n",
    );

    print STDERR $self->_maybe_color($dump);
}

# Print dry-run message.
sub _dry ( $self, $msg )
{
    die 'Missing blessed object' unless blessed $self;
    die 'Missing message'        unless defined $msg;

    return undef unless $self->{prefs}{dry_run};

    print STDERR $self->_maybe_color( $msg, 'dry_run' );
}

# Whether to colorize message; colorize whole message if PALLETE is set.
sub _maybe_color ( $self, $msg, $palette //= undef )
{
    die 'Missing blessed object' unless blessed $self;
    die 'Missing message'        unless defined $msg;

    $msg = colored( $msg, $self->{prefs}{palette}{$palette} ) if defined $palette;
    $msg = colorstrip($msg)                                   unless $self->{prefs}{color};

    return $msg;
}

=encoding UTF-8

=for highlighter language=perl

=head1 NAME

App::prog - core implementation for prog

=head1 SYNOPSIS

  use App::prog;

  App::prog->new->init(@ARGV)->run;

=head1 DESCRIPTION

B<App::prog> provides the logic behind the L<prog> wrapper script, handling
configuration management, file processing, and command execution. See L<prog/DESCRIPTION>
for more details.

=head1 METHODS

=head2 new

  my $prog = App::prog->new(%prefs);

Constructs and returns a new B<App::prog> instance with a hash of preferences
(or default preferences specification, if none is given). See L<prog/OPTIONS>.

Default preferences:

    prefs => {
        color   => 'never',
        dry_run => 0,
        quiet   => 0,
        verbose => 0,
        palette => {
            data     => 'black on_grey18',
            debug    => 'green',
            dump     => 'r102g217b239',     # Cyan (DDP Material theme)
            dry_run  => 'magenta',
            filename => 'grey12',
            header   => 'bold cyan',
            verbose  => 'blue',
        }
    }

Note that invalid C<prefs> and C<palette> keys are silently ignored (or invalid
C<palette> colors).

=head2 init

  $prog->init(@ARGV);

Parses the list given (typically from C<@ARGV>) for options, reads configuration
from C<prog.toml> if present (see L<prog/CONFIGURATION>), and reads environment
variables.

=head2 run

  $prog->run;

Performs the program actions: reads the specified file (or C<STDIN>), prints its
contents, and runs L<stat(1)> on the file (or displays the L<dry-run|prog/-dry-run>
output). Takes no arguments and returns C<0> on success.

=head1 ERRORS

This module reports errors to C<STDERR> and exits with a non‑zero status in the
following:

=over 4

=item * Missing runtime dependencies (L<TOML::Tiny>, L<Data::Printer>).

=item * Syntax error in TOML configuration file.

=item * File access/permission issues.

=item * Invalid command-line options.

=item * Failure to execute external command (L<stat(1)>).

=back

See L<prog/EXIT-STATUS> for exit code details.

=head1 BUGS

Report bugs at L<https://github.com/ryoskzypu/App-prog/issues>.

=head1 AUTHOR

ryoskzypu <ryoskzypu@proton.me>

=head1 SEE ALSO

=over 4

=item *

L<prog>

=item *

L<TOML::Tiny>

=item *

L<Data::Printer>

=back

=head1 COPYRIGHT

Copyright © 2026 ryoskzypu

MIT-0 License. See LICENSE for details.

=cut
