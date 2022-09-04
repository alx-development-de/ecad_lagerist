#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use File::Spec;
use File::Basename;

use Log::Log4perl;
use Log::Log4perl::Level;
use Log::Log4perl::Logger;

use Data::Dumper;

use Spreadsheet::Read qw(ReadData);
use Spreadsheet::WriteExcel;

# Initializing the logging mechanism
# TODO: Make log level configurable
Log::Log4perl->easy_init( Log::Log4perl::Level::to_priority( uc('INFO') ) );
my $logger = Log::Log4perl->get_logger();

# TODO: Should be passed as command line parameter
my $opt_lager_definition = File::Spec->rel2abs('./data/stock-001.xlsx');
my $opt_source_file = File::Spec->rel2abs(join(' ', @ARGV));
my $opt_storage_file = undef;
my $opt_nostorage_file = undef;
{
    my ($name,$path,$suffix) = fileparse($opt_source_file,('.xlsx', '.xls', '.csv', '.txt'));
    $opt_storage_file = File::Spec->catfile($path, "${name}_storage${suffix}");
    $opt_nostorage_file = File::Spec->catfile($path, "${name}_project${suffix}");
}

# Loading the storage manager information
$logger->info("Reading storage information from [$opt_lager_definition]");
my %storage_content;
{
    my $storage_data = Spreadsheet::Read::ReadData($opt_lager_definition) or die $!;

    $logger->debug("Analyzing headlines");
    my @headlines = Spreadsheet::Read::row($storage_data->[1], 1);
    $logger->debug('['.scalar(@headlines).'] Headline elements detected');

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
    $logger->debug('['.scalar(@bom_headlines).'] Headline elements detected');

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

my($storage_row, $nostorage_row) = (0, 0);
# Writing the headlines
$logger->debug("Writing headlines to both output spreadsheets");
for(my $col = 0; $col < scalar(@bom_headlines); $col++) {
    # TODO: A fancy format should be added to the headlines
    $storage_worksheet->write($storage_row, $col, $bom_headlines[$col]);
    $nostorage_worksheet->write($storage_row, $col, $bom_headlines[$col]);
}
$storage_row++; $nostorage_row++;

# Iterating the BOM result and writing the content inside the spreadsheets
foreach my $article_number (keys(%storage_content)) {
    if( defined($storage_content{$article_number}{'Lagerplatz'}) ) {
        # Article available in storage
        $logger->debug("Article [$article_number] defined for storage spreadsheet output");
        #print Dumper \$storage_content{$article_number};
        for(my $col = 0; $col < scalar(@bom_headlines); $col++) {
            my $key = $bom_headlines[$col];
            my $value = $bom_content{$article_number}{$bom_headlines[$col]} || '';

            if($key eq 'Lagerplatz') { $value = $storage_content{$article_number}{'Lagerplatz'}; }
            if($key eq 'Zusatztext 1') { $value = $article_number; } # Per definition specially for UPMANN

            $logger->debug(" -> Writing [$key]->[$value]");
            $storage_worksheet->write($storage_row, $col, $value);
        }
        $storage_row++;
    } else {
        # Article not available in storage
        $logger->debug("Article [$article_number] defined for project specific spreadsheet output");
        for(my $col = 0; $col < scalar(@bom_headlines); $col++) {
            my $key = $bom_headlines[$col];
            my $value = $bom_content{$article_number}{$bom_headlines[$col]} || '';

            if($key eq 'Lagerplatz') { $value = $storage_content{$article_number}{'Lagerplatz'}; }
            if($key eq 'Zusatztext 1') { $value = $article_number; } # Per definition specially for UPMANN
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