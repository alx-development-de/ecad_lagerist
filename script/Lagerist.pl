#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Basename;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Spreadsheet::Read qw(ReadData);
use Spreadsheet::WriteExcel;

use Getopt::Long;
use Config::General qw(ParseConfig);
use Pod::Usage;

use Data::Dumper; # TODO: Remove debug stuff

# Reading the default configuration from the __DATA__ section
# of this script
my $default_config = do {
    local $/;
    <main::DATA>
};
# Loading the file based configuration
my %options = ParseConfig(
    -ConfigFile            => basename($0, qw(.pl .exe .bin)) . '.cfg',
    -ConfigPath            => [ "./", "./etc", "/etc" ],
    -AutoTrue              => 1,
    -MergeDuplicateBlocks  => 1,
    -MergeDuplicateOptions => 1,
    -DefaultConfig         => $default_config,
);

# Processing the command line options
GetOptions(
    'help|?'     => \($options{'run'}{'help'}),
    'man'        => \($options{'run'}{'man'}),
    'loglevel=s' => \($options{'log'}{'level'}),
    'stock=s'    => \($options{'files'}{'stock'}),
) or die "Invalid options passed to $0\n";

# Show the help message if '--help' or '--?' if provided as command line parameter
pod2usage(-verbose => 1) if ($options{'run'}{'help'});
pod2usage(-verbose => 2) if ($options{'run'}{'man'});

=head1 NAME

Lagerist - A simple pick list generator

=head1 DESCRIPTION

A simple pick list generator, which uses a Excel file containing
one table as source for the stock source.

=head1 SYNOPSIS

C<Lagerist> F<[options]>

 Options:
   --help                  Shows a brief help message
   --man                   Prints the full documentation
   --loglevel=[VALUE]      Defines the level for messages
   --stock=[FILE]          Defines the stock source file

=head1 OPTIONS

=over 4

=item B<--help>

Prints a brief help message containing the synopsis and a few more
information about usage and exists.

=item B<--man>

Prints the complete manual page and exits.

=item B<--loglevel>=I<[VALUE]>

To adjust the level for the logging messages the desired level may be defined
with this option. Valid values are:

=over 4

=item I<FATAL>

One or more key business functionalities are not working and the whole system does not fulfill
the business functionalities.

=item I<ERROR>

One or more functionalities are not working, preventing some functionalities from working correctly.

=item I<WARN>

Unexpected behavior happened inside the application, but it is continuing its work and the key
business features are operating as expected.

=item I<INFO>

An event happened, the event is purely informative and can be ignored during normal operations.

=item I<DEBUG>

A log level used for events considered to be useful during software debugging when more granular
information is needed.

=item I<TRACE>

A log level describing events showing step by step execution of your code that can be ignored
during the standard operation, but may be useful during extended debugging sessions.

=back

=item B<--stock>=I<[FILE]>

This option is to provide an alternative stock source file to the pick list
generator. It might be useful if you need to generate pick lists based on
several stocks.

=back

=cut

# Initializing the logging mechanism
Log::Log4perl->easy_init(Log::Log4perl::Level::to_priority(uc($options{'log'}{'level'})));
my $logger = Log::Log4perl->get_logger();

# TODO: Should be passed as command line parameter
my $opt_source_file = File::Spec->rel2abs(join(' ', @ARGV));

# Postprocessing command line parameters
$options{'files'}{'stock'} = File::Spec->rel2abs($options{'files'}{'stock'});
my $opt_storage_file = undef;
my $opt_nostorage_file = undef;
{
    my ($name, $path, $suffix) = fileparse($opt_source_file, ('.xlsx', '.xls', '.csv', '.txt'));
    $opt_storage_file = File::Spec->catfile($path, "${name}_storage${suffix}");
    $opt_nostorage_file = File::Spec->catfile($path, "${name}_project${suffix}");
}

# Loading the storage manager information
$logger->info("Reading storage information from [$options{'files'}{'stock'}]");
my %storage_content;
{
    my $storage_data = Spreadsheet::Read::ReadData($options{'files'}{'stock'}) or $logger->logdie("Something went wrong: " . $!);

    $logger->debug("Analyzing headlines");
    my @headlines = Spreadsheet::Read::row($storage_data->[1], 1);
    $logger->debug('[' . scalar(@headlines) . '] Headline elements detected');

    $logger->debug("Reading content");
    my @rowsmulti = Spreadsheet::Read::rows($storage_data->[1]);
    foreach my $row_number (2 .. scalar @rowsmulti) {
        my $active_part_number = &get_article_number($rowsmulti[$row_number - 1][1]);
        $logger->debug("Article [$active_part_number] detected");
        foreach my $column_number (1 .. scalar @{$rowsmulti[$row_number - 1]}) {
            $storage_content{$active_part_number}{$headlines[$column_number - 1]} =
                $rowsmulti[$row_number - 1][$column_number - 1];
        }
    }
}
# print Dumper \%storage_content;

# Loading the storage manager information
$logger->info("Reading project bill of material from [$opt_source_file]");
my %bom_content;
my @bom_headlines;
{
    my $bom_data = Spreadsheet::Read::ReadData($opt_source_file) or die $!;

    $logger->debug("Analyzing headlines");
    @bom_headlines = Spreadsheet::Read::row($bom_data->[1], 1);
    push(@bom_headlines, 'Lagerplatz'); # Adding the 'Lagerplatz' headline
    $logger->debug('[' . scalar(@bom_headlines) . '] Headline elements detected');

    $logger->debug("Reading content");

    my @rowsmulti = Spreadsheet::Read::rows($bom_data->[1]);
    foreach my $row_number (2 .. scalar @rowsmulti) {
        my $active_part_number = &get_article_number($rowsmulti[$row_number - 1][2]);
        $logger->debug("Article [$active_part_number] detected");
        foreach my $column_number (1 .. scalar @{$rowsmulti[$row_number - 1]}) {
            $bom_content{$active_part_number}{$bom_headlines[$column_number - 1]} =
                $rowsmulti[$row_number - 1][$column_number - 1];
            # Setting up the storage location. It is undef, if the article is not
            # located inside the storage.
            $bom_content{$active_part_number}{'Lagerplatz'} =
                $storage_content{$active_part_number}{'Lagerplatz'};
        }
    }
}
#print Dumper \%bom_content;
#print Dumper \@bom_headlines;

# Let's generate the two output files for the storage information
$logger->info("Generating storage output file [$opt_storage_file]");
my $storage_spreadsheet = Spreadsheet::WriteExcel->new($opt_storage_file);
$logger->info("Generating file for special components [$opt_nostorage_file]");
my $nostorage_spreadsheet = Spreadsheet::WriteExcel->new($opt_nostorage_file);

# Add a worksheet
my $storage_worksheet = $storage_spreadsheet->add_worksheet();
my $nostorage_worksheet = $nostorage_spreadsheet->add_worksheet();

my ($storage_row, $nostorage_row) = (0, 0);
# Writing the headlines
$logger->debug("Writing headlines to both output spreadsheets");
for (my $col = 0; $col < scalar(@bom_headlines); $col++) {
    # TODO: A fancy format should be added to the headlines
    $storage_worksheet->write($storage_row, $col, $bom_headlines[$col]);
    $nostorage_worksheet->write($storage_row, $col, $bom_headlines[$col]);
}
$storage_row++;
$nostorage_row++;

# Iterating the BOM result and writing the content inside the spreadsheets
foreach my $article_number (keys(%storage_content)) {
    if (defined($storage_content{$article_number}{'Lagerplatz'})) {
        # Article available in storage
        $logger->debug("Article [$article_number] defined for storage spreadsheet output");
        #print Dumper \$storage_content{$article_number};
        for (my $col = 0; $col < scalar(@bom_headlines); $col++) {
            my $key = $bom_headlines[$col];
            my $value = $bom_content{$article_number}{$bom_headlines[$col]} || '';

            if ($key eq 'Lagerplatz') {$value = $storage_content{$article_number}{'Lagerplatz'};}
            if ($key eq 'Zusatztext 1') {$value = $article_number;} # Per definition specially for UPMANN

            $logger->debug(" -> Writing [$key]->[$value]");
            $storage_worksheet->write($storage_row, $col, $value);
        }
        $storage_row++;
    }
    else {
        # Article not available in storage
        $logger->debug("Article [$article_number] defined for project specific spreadsheet output");
        for (my $col = 0; $col < scalar(@bom_headlines); $col++) {
            my $key = $bom_headlines[$col];
            my $value = $bom_content{$article_number}{$bom_headlines[$col]} || '';

            if ($key eq 'Lagerplatz') {$value = $storage_content{$article_number}{'Lagerplatz'};}
            if ($key eq 'Zusatztext 1') {$value = $article_number;} # Per definition specially for UPMANN
            $value = defined($value) ? $value : '';

            $logger->debug(" -> Writing [$key]->[$value]");
            $nostorage_worksheet->write($nostorage_row, $col, $value);
        }
        $nostorage_row++;
    }
}

# Closing both spreadsheet files
$logger->debug("Closing output spreadsheets");
$storage_spreadsheet->close();
$nostorage_spreadsheet->close();

exit(0);

sub get_article_number($;) {
    my $source_string = shift();

    my $article_number = $source_string;
    $article_number =~ s/\s//gi; # Removing any whitespace

    return $article_number;
}

=pod

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2022 Alexander Thiel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

__DATA__

<log>
    level=DEBUG
</log>

<files>
    stock = "./data/stock-001.xlsx"
</files>
