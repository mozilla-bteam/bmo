#!/bin/bash

exec perl \
    -I/vagrant/local/lib/perl5 \
    -I$HOME/perl/lib/perl5 \
    $HOME/perl/bin/re.pl "$@"
