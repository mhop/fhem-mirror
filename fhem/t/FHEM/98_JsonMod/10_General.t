# perl fhem.pl -t t/FHEM/98_JsonMod/10_General.t
# test general funcionality
use strict;
use warnings;
use Test::More;

my %_10_test_data = (
    'store.bicycle.color' => 'red',
    'store.bicycle.price' => '19.95',
    'store.book.0.author' => 'Nigel Rees',
    'store.book.0.category' => 'reference',
    'store.book.0.price' => '8.95',
    'store.book.0.title' => 'Sayings of the Century',
    'store.book.1.author' => 'Evelyn Waugh',
    'store.book.1.category' => 'fiction',
    'store.book.1.price' => '12.99',
    'store.book.1.title' => 'Sword of Honour',
    'store.book.2.author' => 'Herman Melville',
    'store.book.2.category' => 'fiction',
    'store.book.2.isbn' => '0-553-21311-3',
    'store.book.2.price' => '8.99',
    'store.book.2.title' => 'Moby Dick',
    'store.book.3.author' => 'J. R. R. Tolkien',
    'store.book.3.category' => 'fiction',
    'store.book.3.isbn' => '0-395-19395-8',
    'store.book.3.price' => '22.99',
    'store.book.3.title' => 'The Lord of the Rings',
);


fhem('set 10_JsonMod reread');

my @readings = sort split ',', ReadingsVal('10_JsonMod', '.computedReadings', undef);

# create test data set once:
if (0) {
    print "\%_10_test_data = (\n";
    foreach (@readings) {
        print "\t'$_' => '" . $defs{'10_JsonMod'}->{'READINGS'}->{$_}->{'VAL'} . "',\n";
    }
    print ");\n";
    printf "%d keys created \n", scalar @readings;
};

plan tests => 33;

print "\tvalidate basic functionallity:\n";
my @expected = sort keys %_10_test_data;
is((@readings), (@expected), 'all expected readings created');

# validate the readings value
foreach (@readings) {
    my $val;
    is($val = ReadingsVal('10_JsonMod', $_, undef), $_10_test_data{$_}, "reading '$_' is '$val'");
};

# test http(s) functionallity
print "\tvalidate basic http(s) functionallity:\n";

my %_11_test_data = (
        '0-1' => 'Sincere@april.biz Gwenborough',
        '1-2' => 'Shanna@melissa.tv Wisokyburgh',
        '2-3' => 'Nathan@yesenia.net McKenziehaven',
        '3-4' => 'Julianne.OConner@kory.org South Elvis',
        '4-5' => 'Lucio_Hettinger@annie.ca Roscoeview',
        '5-6' => 'Karley_Dach@jasper.info South Christy',
        '6-7' => 'Telly.Hoeger@billy.biz Howemouth',
        '7-8' => 'Sherwood@rosamond.me Aliyaview',
        '8-9' => 'Chaim_McDermott@dana.io Bartholomebury',
        '9-10' => 'Rey.Padberg@karina.biz Lebsackbury',
);

# we need to make sure that the async request is processed before starting the test
# to do so we create a temporary wrapper to catch the result of the request

sub wrapper {
    my $orig_func = shift;
    $orig_func->(@_);
    ok($_[0]->{'code'} == 200, "http request: 200 OK");
    @readings = sort split ',', ReadingsVal('11_JsonMod', '.computedReadings', undef);
    # check num readings (10)
    # is(scalar @readings, 10, "multi() 10 readings created");

    if (0) {
        print "\%_11_test_data = (\n";
        foreach (@readings) {
            print "\t'$_' => '" . $defs{'11_JsonMod'}->{'READINGS'}->{$_}->{'VAL'} . "',\n";
        }
        print ");\n";
        printf "%d keys created \n", scalar @readings;
    };

    @expected = sort keys %_11_test_data;
    is((@readings), (@expected), 'all expected readings created');

    foreach (@readings) {
        my $val;
        is($val = ReadingsVal('11_JsonMod', $_, undef), $_11_test_data{$_}, "reading '$_' is '$val'");
    };

    done_testing;
    exit(0);
};

{
    no warnings 'redefine';
    my $original_func_ref = \&JsonMod_ApiResponse;
    *JsonMod_ApiResponse = sub { wrapper($original_func_ref, @_); };
};

fhem('set 11_JsonMod reread');


1;
