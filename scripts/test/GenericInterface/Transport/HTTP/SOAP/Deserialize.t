# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2024 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use strict;
use warnings;
use utf8;

# core modules

# CPAN modules

# OTOBO modules
use Kernel::System::UnitTest::RegisterDriver;    # Set up $Kernel::OM and the test driver $Self
use Kernel::GenericInterface::Debugger              ();
use Kernel::GenericInterface::Transport::HTTP::SOAP ();
use Kernel::System::VariableCheck                   qw(:all);

our $Self;

# get helper object
# skip SSL certificate verification
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        SkipSSLVerify => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# create soap object to use the soap output recursion
my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'error',
        TestMode       => 1,
    },
    CommunicationType => 'requester',
    WebserviceID      => 1,             # not used
);
my $SOAPObject = Kernel::GenericInterface::Transport::HTTP::SOAP->new(
    DebuggerObject  => $DebuggerObject,
    TransportConfig => {
        Config => undef,
    },
);

my $SOAPTagIni = '<soap:Envelope '
    . 'soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" '
    . 'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" '
    . 'xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/" '
    . 'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
    . 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    . '<soap:Body>';
my $SOAPTagEnd = '</soap:Body></soap:Envelope>';

my @Tests = (
    {
        Name      => 'Test 0',
        Data      => '',
        Operation => 'Response',
        Success   => '1',
        Result    => '',
    },
    {
        Name      => 'Test 1',
        Data      => '<Simple>Test</Simple>',
        Operation => 'Response',
        Success   => '1',
        Result    => {
            'Simple' => 'Test'
        },
    },
    {
        Name      => 'Test 1 Unicode',
        Data      => '<Simple>äöüß€ис</Simple>',
        Operation => 'Response',
        Success   => '1',
        Result    => {
            'Simple' => 'äöüß€ис'
        },
    },
    {
        Name      => 'Test 2',
        Data      => '<fooResponse><bar>abcd</bar></fooResponse>',
        Operation => 'Response',
        Success   => '1',
        Result    => {
            'fooResponse' => {
                'bar' => 'abcd'
            }
        },
    },
    {
        Name      => 'Test 2 Unicode',
        Data      => '<fooResponse><bar>äöüß€ис</bar></fooResponse>',
        Operation => 'Response',
        Success   => '1',
        Result    => {
            'fooResponse' => {
                'bar' => 'äöüß€ис'
            }
        },
    },
    {
        Name      => 'Test 3',
        Data      => '<Simple>Test</NonSimple>',
        Operation => 'Response',
        Success   => '0',
    },
    {
        Name      => 'Test 4',
        Data      => '<Simple>Test<Simple>',
        Operation => 'Response',
        Success   => '0',
    },
    {
        Name      => 'Test 5',
        Data      => '<1>Test</1>',
        Operation => 'Response',
        Success   => '0',
    },
    {
        Name      => 'Test 6',
        Data      => '<fooResponse><bar>abcd</bart></fooResponse>',
        Operation => 'Response',
        Success   => '0',
    },
    {
        Name => 'Test 7',
        Data =>
            '<catalog>' .
            '<product>' .
            '<catalog_item>' .
            '<item_number>QWERTY1</item_number>' .
            '<price>50.3</price>' .
            '<size>' .
            '<color>Red</color>' .
            '<color>Blue</color>' .
            '</size>' .
            '<size>' .
            '<color>Red</color>' .
            '<color>Green</color>' .
            '</size>' .
            '</catalog_item>' .
            '<catalog_item>' .
            '<item_number>QWERTY2</item_number>' .
            '<price>42.50</price>' .
            '<size>' .
            '<color>Red</color>' .
            '<color>Navy</color>' .
            '<color>Green</color>' .
            '</size>' .
            '<size>' .
            '<color>Red</color>' .
            '<color>Navy</color>' .
            '<color>Green</color>' .
            '<color>Black</color>' .
            '</size>' .
            '<size>' .
            '<color>Navy</color>' .
            '<color>Black</color>' .
            '</size>' .
            '<size>' .
            '<color>Green</color>' .
            '<color>Black</color>' .
            '</size>' .
            '</catalog_item>' .
            '</product>' .
            '</catalog>',
        Operation => 'Response',
        Success   => '1',
        Result    => {
            'catalog' => {
                'product' => {
                    'catalog_item' => [
                        {
                            'item_number' => 'QWERTY1',
                            'price'       => '50.3',
                            'size'        => [
                                {
                                    'color' => [
                                        'Red',
                                        'Blue'
                                    ]
                                },
                                {
                                    'color' => [
                                        'Red',
                                        'Green'
                                    ]
                                }
                            ],
                        },
                        {
                            'item_number' => 'QWERTY2',
                            'price'       => '42.50',
                            'size'        => [
                                {
                                    'color' => [
                                        'Red',
                                        'Navy',
                                        'Green'
                                    ]
                                },
                                {
                                    'color' => [
                                        'Red',
                                        'Navy',
                                        'Green',
                                        'Black'
                                    ]
                                },
                                {
                                    'color' => [
                                        'Navy',
                                        'Black'
                                    ]
                                },
                                {
                                    'color' => [
                                        'Green',
                                        'Black'
                                    ]
                                }
                            ],
                        },
                    ],
                },
            },
        },
    },
);

TEST:
for my $Test (@Tests) {
    my $SuccessCounter = 0;

    # deserialize
    my $Deserialized = eval {
        SOAP::Deserializer->deserialize(
            $SOAPTagIni . $Test->{Data} . $SOAPTagEnd
        );
    };
    my $DeserializerError = $@;
    if ( !$Test->{Success} ) {
        $Self->True(
            $DeserializerError,
            "$Test->{Name} - SOAP::Deserializer with error $DeserializerError",
        );
        next TEST;
    }
    else {
        $Self->False(
            $DeserializerError,
            "$Test->{Name} - SOAP::Deserializer Successful",
        );
    }

    my $Body = $Deserialized->body();
    $Self->IsDeeply(
        \$Test->{Result},
        \$Body,
        "$Test->{Name} - Deserialize",
    );

    # serializer
    my $SOAPData = $SOAPObject->_SOAPOutputRecursion(
        Data => $Body,
    );

    # create return structure and expected result
    my @CallData = ( 'response', $Test->{Operation} );
    my $ExpectedResult;
    if ( ref $SOAPData->{Data} eq 'ARRAY' ) {
        my $SOAPResult = SOAP::Data->value( @{ $SOAPData->{Data} } );
        push @CallData, $SOAPResult;
        $ExpectedResult =
            '<?xml version="1.0" encoding="UTF-8"?>' .
            $SOAPTagIni . '<' . $Test->{Operation} . '>' .
            $Test->{Data} .
            '</' . $Test->{Operation} . '>' .
            $SOAPTagEnd;
    }
    else {
        $ExpectedResult =
            '<?xml version="1.0" encoding="UTF-8"?>' .
            $SOAPTagIni .
            '<Response xsi:nil="true" />' .
            $SOAPTagEnd;
    }
    my $Content = SOAP::Serializer->autotype(0)->envelope(@CallData);

    $Self->Is(
        $Content,
        $ExpectedResult,
        "$Test->{Name} - Deserialize",
    );
}

$Self->DoneTesting();
