# NAME

App::prog - core implementation for prog

# SYNOPSIS

```perl
use App::prog;

App::prog->new->init(@ARGV)->run;
```

# DESCRIPTION

**App::prog** provides the logic behind the [prog](https://metacpan.org/pod/prog) wrapper script, handling
configuration management, file processing, and command execution. See ["DESCRIPTION" in prog](https://metacpan.org/pod/prog#DESCRIPTION)
for more details.

# METHODS

## new

```perl
my $prog = App::prog->new(%prefs);
```

Constructs and returns a new **App::prog** instance with a hash of preferences
(or default preferences specification, if none is given). See ["OPTIONS" in prog](https://metacpan.org/pod/prog#OPTIONS).

Default preferences:

```perl
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
```

Note that invalid `prefs` and `palette` keys are silently ignored (or invalid
`palette` colors).

## init

```perl
$prog->init(@ARGV);
```

Parses the list given (typically from `@ARGV`) for options, reads configuration
from `prog.toml` if present (see ["CONFIGURATION" in prog](https://metacpan.org/pod/prog#CONFIGURATION)), and reads environment
variables.

## run

```perl
$prog->run;
```

Performs the program actions: reads the specified file (or `STDIN`), prints its
contents, and runs [stat(1)](http://man.he.net/man1/stat) on the file (or displays the [dry-run](https://metacpan.org/pod/prog#dry-run)
output). Takes no arguments and returns `0` on success.

# ERRORS

This module reports errors to `STDERR` and exits with a non‑zero status in the
following:

- Missing runtime dependencies ([TOML::Tiny](https://metacpan.org/pod/TOML%3A%3ATiny), [Data::Printer](https://metacpan.org/pod/Data%3A%3APrinter)).
- Syntax error in TOML configuration file.
- File access/permission issues.
- Invalid command-line options.
- Failure to execute external command ([stat(1)](http://man.he.net/man1/stat)).

See ["EXIT-STATUS" in prog](https://metacpan.org/pod/prog#EXIT-STATUS) for exit code details.

# BUGS

Report bugs at [https://github.com/ryoskzypu/App-prog/issues](https://github.com/ryoskzypu/App-prog/issues).

# AUTHOR

ryoskzypu <ryoskzypu@proton.me>

# SEE ALSO

- [prog](https://metacpan.org/pod/prog)
- [TOML::Tiny](https://metacpan.org/pod/TOML%3A%3ATiny)
- [Data::Printer](https://metacpan.org/pod/Data%3A%3APrinter)

# COPYRIGHT

Copyright © 2026 ryoskzypu

MIT-0 License. See LICENSE for details.
