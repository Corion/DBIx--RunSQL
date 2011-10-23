#!perl -w
use strict;
use Test::More tests => 4;

use DBIx::RunSQL;

my $can_run = eval {
    require DBD::SQLite;
    1
};

if ($can_run) {
    my $lives = eval {
        my $test_dbh = DBIx::RunSQL->create(
            dsn     => 'dbi:SQLite:dbname=:memory:',
            sql     => $0,
        );
        1;
    };
    my $err = $@;
    ok !$lives, "We die on invalid SQL";
    isn't $@, '', "We die with some error message";

    $lives = eval {
        my $test_dbh = DBIx::RunSQL->create(
            dsn     => 'dbi:SQLite:dbname=:memory:',
            sql     => $0,
            force   => 1,
        );
        1;
    };
    $err = $@;
    ok $lives, "We can force invalid SQL";
    is $@, '', "We don't die with some error message";
} else {
    SKIP: {
        skip "SQLite not installed", 4
    }
}