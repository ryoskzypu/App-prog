[![CI](https://github.com/ryoskzypu/App-prog/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/ryoskzypu/App-prog/actions/workflows/test.yml)
[![Coverage Status](https://coveralls.io/repos/github/ryoskzypu/App-prog/badge.svg)](https://coveralls.io/github/ryoskzypu/App-prog)

# App::prog

**prog** is a small command-line utility intended to be a baseline for Perl CLI
programs; it follows Unix conventions and modern practices.

This script reads an entire file into memory, prints its contents to standard
output, then runs the command [stat(1)](http://man.he.net/man1/stat) on it to display status information.

## Installation

To download and install this module directly with [cpanminus](https://metacpan.org/pod/App::cpanminus):

```shell
$ cpanm https://github.com/ryoskzypu/App-prog.git
```

To do it manually, run the following commands (after cloning the repository):

```shell
$ cd App-prog
$ perl Makefile.PL
$ make
$ make test
$ make install
```

## Support and documentation

You can find documentation for this module in [docs](docs/) or with the
`perldoc` command (after installing):

```shell
$ perldoc prog
$ perldoc App::prog
```

You can also look for information at:

- GitHub issue tracker (report bugs here)

    https://github.com/ryoskzypu/App-prog/issues

- Search CPAN

    https://metacpan.org/dist/App-prog

## Copyright

Copyright © 2026 ryoskzypu

MIT-0 License. See LICENSE for details.
