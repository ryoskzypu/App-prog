# NAME

prog - read a file, print its contents, then run stat(1) on it

# SYNOPSIS

**prog** \[*OPTION*\]... \[*FILE*\]

Options:

```
-c, --color=WHEN      colorize output; WHEN is 'never', 'always', or 'auto';
                      -c means --color='auto'
    --palette=PALETTE set colors used when --color is active; PALETTE is an
                      output=color pair
    --dry-run         print but do not execute commands
    --generate-cfg    create a default config file and exit
-h, --help            show this help and exit
-q, --quiet           suppress standard output
-v, --verbose         more output info
-V, --version         show version info and exit
```

Examples:

```shell
$ prog FILE
$ prog --dry-run -v FILE
$ prog --color=always | cat
$ prog <<<$'hi\nbye' -vc
```

If no *FILE* is given or *FILE* is `-`, read standard input.

# DESCRIPTION

**prog** is a small command-line utility intended to be a baseline for Perl CLI
programs; it follows Unix conventions and modern practices.

This script reads an entire file into memory, prints its contents to standard
output, then runs the command [stat(1)](http://man.he.net/man1/stat) on it to display status information.

# OPTIONS

- **-c**, **--color**\[=*WHEN*\]

    Colorize output (per [Term::ANSIColor](https://metacpan.org/pod/Term%3A%3AANSIColor) spec) depending on *WHEN*. *WHEN* is
    `never`, `always`, or `auto`; **-c** means **--color=**`auto`, which enables
    color only when `STDOUT` is an interactive TTY; `always` forces color; `never`
    disables color. Default: `never`.

- **--palette**=*PALETTE*

    Set the colors used when **--color** is active (per [Term::ANSIColor](https://metacpan.org/pod/Term%3A%3AANSIColor) spec); *PALETTE*
    is an `output=color` pair (an output type and its color).

    Default colors:

    ```perl
    data     => 'black on_grey18',  # File contents / stat(1).
    debug    => 'green',
    dump     => 'r102g217b239',
    dry_run  => 'magenta',          # E.g. "Executing 'stat file.txt'".
    filename => 'grey12',
    header   => 'bold cyan',        # E.g. "File 'file.txt' status info".
    verbose  => 'blue',
    ```

    Example:

    ```shell
    $ prog \
        -c \
        --palette header='bold white' \
        --palette filename=bright_green \
        --palette verbose='black on_blue' \
        --verbose \
        file.txt
    ```

    Note that invalid outputs and colors are silently ignored.

- **--dry-run**

    Print commands that would be executed to `STDERR`; do not run them. Default: `false`.

- **--generate-cfg**

    Create a default configuration file and exit. The `prog.toml` file is created
    only if none exists, under `$XDG_CONFIG_HOME/prog` (or `$HOME/.config/prog`
    if `$XDG_CONFIG_HOME` is unset), or in the home directory as a fallback.

- **-h**, **--help**

    Display a summary of options and exit.

- **-q**, **--quiet**

    Do not write anything to `STDOUT`. Default: `false`.

- **-v**, **--verbose**

    Display more information to `STDERR`. Default: `false`.

- **-V**, **--version**

    Display the **prog** version number and exit.

## COMPLETION

To enable tab completion in bash, put the script in the `PATH` and run this
in the shell or add it to a bash startup file (e.g. `/etc/bash.bashrc` or `~/.bashrc`):

```shell
complete -C prog prog
```

# CONFIGURATION

**prog** supports a configuration file to simplify common ["OPTIONS"](#options). By default,
it looks first for `prog.toml` in the current directory, then in `$XDG_CONFIG_HOME/prog`
(or `$HOME/.config/prog` if `$XDG_CONFIG_HOME` is unset), and last in the
home directory. Override this by setting the `PROG_CFG` environment variable
to a file path.

The configuration file uses [TOML](https://toml.io/en/v1.0.0). Example `prog.toml`:

```toml
color   = 'auto'
verbose = true

[palette]
filename = 'bright_green'
header   = 'bold white'
verbose  = 'black on_blue'
```

# SIGNALS

- SIGINT
- SIGTERM

    When caught, displays a message to `STDERR` and exits cleanly with status `0`.

# EXIT STATUS

```
0  success
1  general failure
2  command-line usage error
```

# ENVIRONMENT

- **PROG\_CFG**

    If set to an existing file path, overrides the default configuration file path.

- **PROG\_DEBUG**

    If true, displays debug information to `STDERR`.

# BUGS

Report bugs at [https://github.com/author/App-prog/issues](https://github.com/author/App-prog/issues).

# AUTHOR

ryoskzypu <ryoskzypu@proton.me>

# SEE ALSO

- [Term::ANSIColor](https://metacpan.org/pod/Term%3A%3AANSIColor)
- [stat(1)](http://man.he.net/man1/stat)
- [The Art of Unix Programming](http://www.catb.org/esr/writings/taoup/html/)

# COPYRIGHT

Copyright © 2026 ryoskzypu

MIT-0 License. See LICENSE for details.
