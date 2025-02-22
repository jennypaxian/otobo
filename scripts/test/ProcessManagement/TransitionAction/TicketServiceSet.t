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
use Storable qw(dclone);

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::System::UnitTest::RegisterDriver;    # Set up $Kernel::OM and the test driver $Self
use Kernel::System::VariableCheck qw(:all);

our $Self;

# get needed objects
my $ServiceObject = $Kernel::OM->Get('Kernel::System::Service');
my $TicketObject  = $Kernel::OM->Get('Kernel::System::Ticket');
my $ModuleObject  = $Kernel::OM->Get('Kernel::System::ProcessManagement::TransitionAction::TicketServiceSet');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase  => 1,
        UseTmpArticleDir => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# define variables
my $UserID     = 1;
my $ModuleName = 'TicketServiceSet';
my $RandomID   = $Helper->GetRandomID();

# add a customer user
my $TestCustomerUserLogin = $Helper->TestCustomerUserCreate();

# set user details
my ( $TestUserLogin, $TestUserID ) = $Helper->TestUserCreate();

#
# Create new services
#
my @Services = (
    {
        Name    => 'Service0' . $RandomID,
        ValidID => 1,
        UserID  => 1,
    },
    {
        Name    => 'Service1' . $RandomID,
        ValidID => 1,
        UserID  => 1,
    },
    {
        Name    => 'Service2' . $RandomID,
        ValidID => 1,
        UserID  => 1,
    },
);

for my $ServiceData (@Services) {
    my $ServiceID = $ServiceObject->ServiceAdd( %{$ServiceData} );

    # sanity test
    $Self->IsNot(
        $ServiceID,
        undef,
        "ServiceAdd() for $ServiceData->{Name}, ServiceID should not be undef",
    );

    # store the ServiceID
    $ServiceData->{ServiceID} = $ServiceID;
}

#
# Assign services to customer (0 and 1)
#
my $Success = $ServiceObject->CustomerUserServiceMemberAdd(
    CustomerUserLogin => $TestCustomerUserLogin,
    ServiceID         => $Services[0]->{ServiceID},
    Active            => 1,
    UserID            => 1,
);

# sanity test
$Self->True(
    $Success,
    "CustomerUserServiceMemberAdd() for user $TestCustomerUserLogin, and Service $Services[0]->{Name}"
        . " with true",
);

$Success = $ServiceObject->CustomerUserServiceMemberAdd(
    CustomerUserLogin => $TestCustomerUserLogin,
    ServiceID         => $Services[1]->{ServiceID},
    Active            => 1,
    UserID            => 1,
);

# sanity test
$Self->True(
    $Success,
    "CustomerUserServiceMemberAdd() for user $TestCustomerUserLogin, and Service $Services[1]->{Name}"
        . " with true",
);

#
# Create a test tickets
#
my @TicketData;
for my $Item ( 0 .. 1 ) {
    my $TicketID = $TicketObject->TicketCreate(
        Title         => ( $Item == 0 ) ? $Services[0]->{ServiceID} : 'test',
        QueueID       => 1,
        Lock          => 'unlock',
        Priority      => '3 normal',
        StateID       => 1,
        TypeID        => 1,
        CustomerUser  => ( $Item == 0 ) ? $TestCustomerUserLogin : undef,
        OwnerID       => 1,
        ResponsibleID => 1,
        UserID        => $UserID,
    );

    # sanity checks
    $Self->True(
        $TicketID,
        "TicketCreate() - $TicketID",
    );

    my %Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID,
        UserID   => $UserID,
    );

    $Self->True(
        IsHashRefWithData( \%Ticket ),
        "TicketGet() - Get Ticket with ID $TicketID.",
    );

    push @TicketData, \%Ticket;

}

# Run() tests
my @Tests = (
    {
        Name    => 'No Params',
        Config  => undef,
        Success => 0,
    },
    {
        Name   => 'No UserID',
        Config => {
            UserID => undef,
            Ticket => $TicketData[0],
            Config => {
                CustomerID => 'test',
            },
        },
        Success => 0,
    },
    {
        Name   => 'No Ticket',
        Config => {
            UserID => $UserID,
            Ticket => undef,
            Config => {
                CustomerID => 'test',
            },
        },
        Success => 0,
    },
    {
        Name   => 'No Config',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {},
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Config',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                NoAgentNotify => 0,
            },
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Ticket Format',
        Config => {
            UserID => $UserID,
            Ticket => 1,
            Config => {
                Service => 'open',
            },
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Config Format',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => 1,
        },
        Success => 0,
    },
    {
        Name   => 'Wrong Service',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                Service => 'NotExisting' . $RandomID,
            },
        },
        Success => 0,
    },
    {
        Name   => 'Wrong ServiceID',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                ServiceID => 'NotExisting' . $RandomID,
            },
        },
        Success => 0,
    },
    {
        Name   => 'Not assigned Service',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                Service => $Services[2]->{Name},
            },
        },
        Success => 0,
    },
    {
        Name   => 'Not Assigned ServiceID',
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                ServiceID => $Services[2]->{ServiceID},
            },
        },
        Success => 0,
    },
    {
        Name   => "Ticket without customer with Service $Services[0]->{Name}",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[1],
            Config => {
                ServiceID => $Services[0]->{Name},
            },
        },
        Success => 0,
    },
    {
        Name   => "Ticket without customer with ServiceID $Services[1]->{Name}",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[1],
            Config => {
                ServiceID => $Services[0]->{ServiceID},
            },
        },
        Success => 0,
    },
    {
        Name   => "Correct Service $Services[0]->{Name}",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                Service => $Services[0]->{Name},
            },
        },
        Success => 1,
    },
    {
        Name   => "Correct Service $Services[1]->{Name}",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                Service => $Services[1]->{Name},
            },
        },
        Success => 1,
    },
    {
        Name   => "Correct ServiceID $Services[0]->{Name}",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                ServiceID => $Services[0]->{ServiceID},
            },
        },
        Success => 1,
    },
    {
        Name   => "Correct ServiceID $Services[1]->{Name}",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                ServiceID => $Services[1]->{ServiceID},
            },
        },
        Success => 1,
    },
    {
        Name   => "Correct Ticket->Title",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                ServiceID => '<OTOBO_TICKET_Title>',
            },
        },
        Success => 1,
    },
    {
        Name   => "Wrong Ticket->NotExisting",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                ServiceID => '<OTOBO_TICKET_NotExisting>',
            },
        },
        Success => 0,
    },
    {
        Name   => "Correct Using Different UserID",
        Config => {
            UserID => $UserID,
            Ticket => $TicketData[0],
            Config => {
                Service => $Services[0]->{Name},
                UserID  => $TestUserID,
            },
        },
        Success => 1,
    },
);

for my $Test (@Tests) {

    # make a deep copy to avoid changing the definition
    my $OrigTest = dclone($Test);

    my $Success = $ModuleObject->Run(
        %{ $Test->{Config} },
        ProcessEntityID          => 'P1',
        ActivityEntityID         => 'A1',
        TransitionEntityID       => 'T1',
        TransitionActionEntityID => 'TA1',
    );

    if ( $Test->{Success} ) {

        $Self->True(
            $Success,
            "$ModuleName Run() - Test:'$Test->{Name}' | executed with True"
        );

        # get ticket
        my $TicketID = $TicketData[0]->{TicketID};
        if ( $Test->{Config}->{Ticket}->{TicketID} eq $TicketData[1]->{TicketID} ) {
            $TicketID = $TicketData[1]->{TicketID};
        }

        my %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketID,
            UserID   => 1,
        );

        ATTRIBUTE:
        for my $Attribute ( sort keys %{ $Test->{Config}->{Config} } ) {

            $Self->True(
                defined $Ticket{$Attribute},
                "$ModuleName - Test:'$Test->{Name}' | Attribute: $Attribute for TicketID:"
                    . " $TicketID exists with True",
            );

            my $ExpectedValue = $Test->{Config}->{Config}->{$Attribute};
            if (
                $OrigTest->{Config}->{Config}->{$Attribute}
                =~ m{\A<OTOBO_TICKET_([A-Za-z0-9_]+)>\z}msx
                )
            {
                $ExpectedValue = $Ticket{$1} // '';
                $Self->IsNot(
                    $Test->{Config}->{Config}->{$Attribute},
                    $OrigTest->{Config}->{Config}->{$Attribute},
                    "$ModuleName - Test:'$Test->{Name}' | Attribute: $Attribute value: $OrigTest->{Config}->{Config}->{$Attribute} should been replaced",
                );
            }

            $Self->Is(
                $Ticket{$Attribute},
                $ExpectedValue,
                "$ModuleName - Test:'$Test->{Name}' | Attribute: $Attribute for TicketID:"
                    . " $TicketID match expected value",
            );
        }

        if ( $OrigTest->{Config}->{Config}->{UserID} ) {
            $Self->Is(
                $Test->{Config}->{Config}->{UserID},
                undef,
                "$ModuleName - Test:'$Test->{Name}' | Attribute: UserID for TicketID:"
                    . " $TicketID should be removed (as it was used)",
            );
        }
    }
    else {
        $Self->False(
            $Success,
            "$ModuleName Run() - Test:'$Test->{Name}' | executed with False"
        );
    }
}

done_testing;
