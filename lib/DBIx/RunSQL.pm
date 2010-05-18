package DBIx::RunSQL;
use strict;
use DBI;

use vars qw($VERSION);
$VERSION = '0.03';

=head1 NAME

DBIx::RunSQL - run SQL to create a database schema

=cut

=head1 SYNOPSIS

    #!/usr/bin/perl -w
    use strict;
    use lib 'lib';
    use DBIx::RunSQL;

    my $test_dbh = DBIx::RunSQL->create(
        dsn     => 'dbi:SQLite:dbfile=:memory:',
        sql     => 'sql/setup.sql',
        verbose => 1,
    );
    
    ... # run your tests with a DB setup fresh from setup.sql

=head1 METHODS

=head2 C<< DBIx::RunSQL->create ARGS >>

Creates the database and returns the database handle

=over 4

=item *

C<sql> - name of the file containing the SQL statements

If C<sql> is a reference to a glob or a filehandle,
the SQL will be read from that. B<not implemented>

If C<sql> is undefined, the C<$::DATA> or the C<0> filehandle will
be read until exhaustion.  B<not implemented>

This allows to create SQL-as-programs as follows:

  #!/usr/bin/perl -w -MDBIx::RunSQL=run
  create table ...

=item *

C<dsn>, C<user>, C<password> - DBI parameters for connecting to the DB

=item *

C<dbh> - a premade database handle to be used instead of C<dsn>

=item *

C<verbose> - print each SQL statement as it is run

=back

=cut

sub create {
    my ($self,%args) = @_;

    $args{sql} ||= 'sql/create.sql';

    my $dbh = delete $args{ dbh };
    if (! $dbh) {
        $dbh = DBI->connect($args{dsn}, $args{user}, $args{password}, {})
            or die "Couldn't connect to DSN '$args{dsn}' : " . DBI->errstr;
    };

    $self->run_sql_file(
        sql => $args{sql},
        dbh => $dbh,
        verbose => $args{verbose}
    );

    $dbh
};

sub run_sql_file {
    my ($class,%args) = @_;
    my $errors = 0;
    my @sql;
    {
        open my $fh, "<", $args{sql}
            or die "Couldn't read '$args{sql}' : $!";
        local $/;
        @sql = split /;\n/, <$fh> # potentially this should become C<< $/ = ";\n"; >>
        # and a while loop to handle large SQL files
    };

    for my $statement (@sql) {
        $statement =~ s/^\s*--.*$//mg;
        next unless $statement =~ /\S/; # skip empty lines
        print "$statement\n" if $args{verbose};
        if (! $args{dbh}->do($statement)) {
            $errors++;
            if ($args{fatal}) {
                die "[SQL ERROR]: $statement\n";
            } else {
                warn "[SQL ERROR]: $statement\n";
            };
        };
    };
    $errors
}

sub parse_command_line {
    my ($package,$appname,@argv) =  @_;
    require Getopt::Long; Getopt::Long->import();
    require Pod::Usage; Pod::Usage->import();
    
    if (! @argv) { @argv = @ARGV };
    
    local @ARGV = @argv;
    if (GetOptions(
        'user:s' => \my $user,
        'password:s' => \my $password,
        'dsn:s' => \my $dsn,
        'verbose' => \my $verbose,
        'sql:s' => \my $sql,
        'help|h' => \my $help,
        'man' => \my $man,
    )) {
        return {
        user     => $user,
        password => $password,
        dsn      => $dsn,
        verbose  => $verbose,
        sql      => $sql,
        help     => $help,
        man      => $man,
        };
    } else {
        return undef;
    };
}

sub handle_command_line {
    my ($package,$appname,@argv) =  @_;
    require Getopt::Long; Getopt::Long->import();
    require Pod::Usage; Pod::Usage->import();
    
    my $opts = $package->parse_command_line(@argv)
        or pod2usage(2);
    pod2usage(1) if $opts->{help};
    pod2usage(-verbose => 2) if $opts->{man};
    
    $opts->{dsn} ||= sprintf 'dbi:SQLite:dbname=db/%s.sqlite', $appname;
    
    $package->create(
        %$opts
    );
}

1;

=head1 PROGRAMMER USAGE

This module abstracts away the "run these SQL statements to set up 
your database" into a module. In some situations you want to give the
setup SQL to a database admin, but in other situations, for example testing,
you want to run the SQL statements against an in-memory database. This
module abstracts away the reading of SQL from a file and allows for various
command line parameters to be passed in. A skeleton C<create-db.sql>
looks like this:

    #!/usr/bin/perl -w
    use strict;
    use lib 'lib';
    use DBIx::RunSQL;

    DBIx::RunSQL->handle_command_line('myapp');

    =head1 NAME

    create-db.pl - Create the database

    =head1 ABSTRACT

    This sets up the database. The following
    options are recognized:

    =over 4

    =item C<--user> USERNAME

    =item C<--password> PASSWORD

    =item C<--dsn> DSN

    The DBI DSN to use for connecting to
    the database

    =item C<--sql> SQLFILE

    The alternative SQL file to use
    instead of C<sql/create.sql>.

    =item C<--help>

    Show this message.

    =cut

=head1 NOTES

If you find yourself wanting to write SELECT statements,
consider looking at L<Querylet> instead, which is geared towards that
and even has an interface for Excel or HTML output.

If you find yourself wanting to write parametrized queries as
C<.sql> files, consider looking at L<Data::Phrasebook::SQL>
or potentially L<DBIx::SQLHandler>.

=head1 SEE ALSO

L<ORLite::Migrate>

=cut