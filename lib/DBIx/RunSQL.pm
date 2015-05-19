package DBIx::RunSQL;
use strict;
use DBI;

use vars qw($VERSION);
$VERSION = '0.13';

=head1 NAME

DBIx::RunSQL - run SQL from a file

=cut

=head1 SYNOPSIS

    #!/usr/bin/perl -w
    use strict;
    use lib 'lib';
    use DBIx::RunSQL;

    my $test_dbh = DBIx::RunSQL->create(
        dsn     => 'dbi:SQLite:dbname=:memory:',
        sql     => 'sql/create.sql',
        force   => 1,
        verbose => 1,
    );

    ... # run your tests with a DB setup fresh from setup.sql

=head1 METHODS

=head2 C<< DBIx::RunSQL->create ARGS >>

=head2 C<< DBIx::RunSQL->run ARGS >>

Runs the SQL commands and returns the database handle

=over 4

=item *

C<sql> - name of the file containing the SQL statements

The default is C<sql/create.sql>

If C<sql> is a reference to a glob or a filehandle,
the SQL will be read from that. B<not implemented>

If C<sql> is undefined, the C<$::DATA> or the C<0> filehandle will
be read until exhaustion.  B<not implemented>

This allows to create SQL-as-programs as follows:

  #!/usr/bin/perl -w -MDBIx::RunSQL=create
  create table ...

If you want to run SQL statements from a scalar,
you can simply pass in a reference to a scalar containing the SQL:

    sql => \"update mytable set foo='bar';",

=item *

C<dsn>, C<user>, C<password> - DBI parameters for connecting to the DB

=item *

C<dbh> - a premade database handle to be used instead of C<dsn>

=item *

C<force> - continue even if errors are encountered

=item *

C<verbose> - print each SQL statement as it is run

=item *

C<verbose_handler> - callback to call with each SQL statement instead of C<print>

=item *

C<verbose_fh> - filehandle to write to instead of C<STDOUT>

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
        dbh => $dbh,
        %args,
    );

    $dbh
};
*run= \&create;

=head2 C<< DBIx::RunSQL->run_sql_file ARGS >>

    my $dbh = DBI->connect(...)

    for my $file (sort glob '*.sql') {
        DBIx::RunSQL->run_sql_file(
            verbose => 1,
            dbh     => $dbh,
            sql     => $file,
        );
    };

Runs an SQL file on a prepared database handle.
Returns the number of errors encountered.

If the statement returns rows, these are printed
separated with tabs.

=over 4

=item *

C<dbh> - a premade database handle

=item *

C<sql> - name of the file containing the SQL statements

=item *

C<force> - continue even if errors are encountered

=item *

C<verbose> - print each SQL statement as it is run

=item *

C<verbose_handler> - callback to call with each SQL statement instead of C<print>

=item *

C<verbose_fh> - filehandle to write to instead of C<STDOUT>

=back

=cut

sub run_sql_file {
    my ($self,%args) = @_;
    my $errors = 0;
    my @sql;
    {
        open my $fh, "<", $args{sql}
            or die "Couldn't read '$args{sql}' : $!";
        # potentially this should become C<< $/ = ";\n"; >>
        # and a while loop to handle large SQL files
        local $/;
        $args{ sql }= <$fh>; # sluuurp
    };

    $self->run_sql(
        %args
    );
}

=head2 C<< DBIx::RunSQL->run_sql ARGS >>

    my $dbh = DBI->connect(...)

    for my $file (sort glob '*.sql') {
        DBIx::RunSQL->run_sql_file(
            verbose => 1,
            dbh     => $dbh,
            sql     => 'create table foo',
        );
    };

Runs an SQL string on a prepared database handle.
Returns the number of errors encountered.

If the statement returns rows, these are printed
separated with tabs.

=over 4

=item *

C<dbh> - a premade database handle

=item *

C<sql> - string or array reference containing the SQL statements

=item *

C<force> - continue even if errors are encountered

=item *

C<verbose> - print each SQL statement as it is run

=item *

C<verbose_handler> - callback to call with each SQL statement instead of C<print>

=item *

C<verbose_fh> - filehandle to write to instead of C<STDOUT>

=back

=cut

sub run_sql {
    my ($self,%args) = @_;
    my $errors = 0;
    my @sql= 'ARRAY' eq ref $args{ sql }
             ? @{ $args{ sql }}
             : $args{ sql };

    $args{ verbose_handler } ||= sub {
        $args{ verbose_fh } ||= \*main::STDOUT;
        print { $args{ verbose_fh } } "$_[0]\n";
    };
    my $status = delete $args{ verbose_handler };

    # Because we blindly split above on /;\n/
    # we need to reconstruct multi-line CREATE TRIGGER statements here again
    my $trigger;
    for my $statement ($self->split_sql( $args{ sql })) {
        # skip "statements" that consist only of comments
        next unless $statement =~ /^\s*[A-Z][A-Z]/mi;

        $status->($statement) if $args{verbose};

        my $sth = $args{dbh}->prepare($statement);
        if(! $sth) {
            if (!$args{force}) {
                die "[SQL ERROR]: $statement\n";
            } else {
                warn "[SQL ERROR]: $statement\n";
            };
        } else {
            my $status= $sth->execute();
            if(! $status) {
                if (!$args{force}) {
                    die "[SQL ERROR]: $statement\n";
                } else {
                    warn "[SQL ERROR]: $statement\n";
                };
            } elsif( 0 < $sth->{NUM_OF_FIELDS} ) {
                # SELECT statement, output results
                print $self->format_results( sth => $sth );
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
        'force|f' => \my $force,
        'sql:s' => \my $sql,
        'help|h' => \my $help,
        'man' => \my $man,
    )) {
        return {
        user     => $user,
        password => $password,
        dsn      => $dsn,
        verbose  => $verbose,
        force    => $force,
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

    my $opts = $package->parse_command_line($appname,@argv)
        or pod2usage(2);
    pod2usage(1) if $opts->{help};
    pod2usage(-verbose => 2) if $opts->{man};

    $opts->{dsn} ||= sprintf 'dbi:SQLite:dbname=db/%s.sqlite', $appname;

    $package->create(
        %$opts
    );
}

=head2 C<< DBIx::RunSQL->format_results %options >>

  my $sth= $dbh->prepare( 'select * from foo' );
  $sth->execute();
  print DBIx::RunSQL->format_results( sth => $sth );

Executes C<< $sth->fetchall_arrayref >> and returns
the results either as tab separated string
or formatted using L<Text::Table> if the module is available.

If you find yourself using this often to create reports,
you may really want to look at L<Querylet> instead.

=over 4

=item *

C<sth> - the executed statement handle

=item *

C<formatter> - if you want to force C<tab> or C<Text::Table>
usage, you can do it through that parameter.
In fact, the module will use anything other than C<tab>
as the class name and assume that the interface is compatible
to C<Text::Table>.

=back

Note that the query results are returned as one large string,
so you really do not want to run this for large(r) result
sets.

=cut

sub format_results {
    my( $self, %options )= @_;
    my $sth= delete $options{ sth };

    if( ! exists $options{ formatter }) {
        if( eval { require "Text/Table.pm" }) {
            $options{ formatter }= 'Text::Table';
        } else {
            $options{ formatter }= 'tab';
        };
    };

    my @columns= @{ $sth->{NAME} };
    my $res= $sth->fetchall_arrayref();
    my $result='';
    if( @columns ) {
        # Output as print statement
        if( 'tab' eq $options{ formatter } ) {
            $result = join "\n",
                          join( "\t", @columns ),
                          map { join( "\t", @$_ ) } @$res
                      ;
        } else {
            my $t= $options{formatter}->new(@columns);
            $t->load( @$res );
            $result= $t;
        };
    };
    "$result"; # Yes, sorry - we stringify everything
}

=head2 C<< DBIx::RunSQL->split_sql ARGS >>

  my @statements= DBIx::RunSQL->split_sql( <<'SQL');
      create table foo (name varchar(64));
      create trigger foo_insert on foo before insert;
          new.name= 'foo-'||old.name;
      end;
      insert into foo name values ('bar');
  SQL
  # Returns three elements

This is a helper subroutine to split a sequence of (semicolon-newline-delimited)
SQL statements into separate statements. It is documented because
it is not a very smart subroutine and you might want to
override or replace it. It might also be useful outside the context
of L<DBIx::RunSQL> if you need to split up a large blob
of SQL statements into smaller pieces.

The subroutine needs the whole sequence of SQL statements in memory.
If you are attempting to restore a large SQL dump backup into your
database, this approach might not be suitable.

=cut

sub split_sql {
    my( $self, $sql )= @_;
    my @sql = split /;\r?\n/, $sql;

    # Because we blindly split above on /;\n/
    # we need to reconstruct multi-line CREATE TRIGGER statements here again
    my @res;
    my $trigger;
    for my $statement (@sql) {
        if( $statement =~ /^\s*CREATE\s+TRIGGER\b/i ) {
            $trigger = $statement;
            next
                if( $statement !~ /END$/i );
            $statement = $trigger;
            undef $trigger;
        } elsif( $trigger ) {
            $trigger .= ";\n$statement";
            next
                if( $statement !~ /END$/i );
            $statement = $trigger;
            undef $trigger;
        };
        push @res, $statement;
    };

    @res
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

    =item C<--force>

    Don't stop on errors

    =item C<--help>

    Show this message.

    =cut

=head2 C<< DBIx::RunSQL->handle_command_line >>

Parses the command line. This is a convenience method, which
passes the following command line arguments to C<< ->create >>:

  --user
  --password
  --dsn
  --sql
  --force
  --verbose

In addition, it handles the following switches through L<Pod::Usage>:

  --help
  --man

See also the section PROGRAMMER USAGE for a sample program to set
up a database from an SQL file.

=head1 NOTES

=head2 COMMENT FILTERING

The module tries to keep the SQL as much verbatim as possible. It
filters all lines that end in semicolons but contain only SQL comments. All
other comments are passed through to the database with the next statement.

=head2 TRIGGER HANDLING

This module uses a very simplicistic approach to recognize triggers.
Triggers are problematic because they consist of multiple SQL statements
and this module does not implement a full SQL parser. An trigger is
recognized by the following sequence of lines

    CREATE TRIGGER
        ...
    END;

If your SQL dialect uses a different syntax, it might still work to put
the whole trigger on a single line in the input file.

=head2 OTHER APPROACHES

If you find yourself wanting to write SELECT statements,
consider looking at L<Querylet> instead, which is geared towards that
and even has an interface for Excel or HTML output.

If you find yourself wanting to write parametrized queries as
C<.sql> files, consider looking at L<Data::Phrasebook::SQL>
or potentially L<DBIx::SQLHandler>.

=head1 SEE ALSO

L<ORLite::Migrate>

=head1 REPOSITORY

The public repository of this module is
L<http://github.com/Corion/DBIx--RunSQL>.

=head1 SUPPORT

The public support forum of this module is
L<http://perlmonks.org/>.

=head1 BUG TRACKER

Please report bugs in this module via the RT CPAN bug queue at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=DBIx-RunSQL>
or via mail to L<bug-dbix-runsql@rt.cpan.org>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2009-2014 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut
