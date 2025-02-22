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

# Set up the test driver $Self when we are running as a standalone script.
use Kernel::System::UnitTest::RegisterDriver;

our $Self;

my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

my $CacheType = 'UnitTestSchedulerDBGetIdentifier';

my $ChildCount          = 5;
my $IdentifiersPerChild = 10_000;

for my $ChildIndex ( 1 .. $ChildCount ) {

    # Disconnect database before fork.
    $DBObject->Disconnect();

    # Create a fork of the current process
    #   parent gets the PID of the child
    #   child gets PID = 0
    my $PID = fork;
    if ( !$PID ) {

        # Destroy objects.
        $Kernel::OM->ObjectsDiscard();

        my %IdentifiersData;
        for my $IdentifierIndex ( 1 .. $IdentifiersPerChild ) {

            my $Identifier = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB')->_GetIdentifier();

            $IdentifiersData{$IdentifierIndex} = $Identifier;
        }

        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => $CacheType,
            Key   => "${ChildIndex}",
            Value => {
                %IdentifiersData,
            },
            TTL => 60 * 10,
        );

        exit 0;
    }
}

my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

my %ChildData;

my $Wait = 1;
while ($Wait) {
    CHILDINDEX:
    for my $ChildIndex ( 1 .. $ChildCount ) {

        next CHILDINDEX if $ChildData{$ChildIndex};

        my $Cache = $CacheObject->Get(
            Type => $CacheType,
            Key  => "${ChildIndex}",
        );

        next CHILDINDEX if !$Cache;
        next CHILDINDEX if ref $Cache ne 'HASH';

        $ChildData{$ChildIndex} = $Cache;
    }
}
continue {
    my $GotDataCount = scalar keys %ChildData;
    if ( $GotDataCount == $ChildCount ) {
        $Wait = 0;
    }
    sleep 1;
}

my %Identifiers;

CHILDINDEX:
for my $ChildIndex ( 1 .. $ChildCount ) {
    for my $IdentifierIndex ( 1 .. $IdentifiersPerChild ) {

        my $Identifier = $ChildData{$ChildIndex}->{$IdentifierIndex};

        if ( $Identifiers{$Identifier} ) {
            $Self->Is(
                $Identifiers{$Identifier},
                undef,
                "Identifier $Identifier should not exists",
            );
        }
        $Identifiers{$Identifier} = 1;
    }
}

$Self->Is(
    scalar keys %Identifiers,
    $ChildCount * $IdentifiersPerChild,
    "Number of Identifiers",
);

$CacheObject->CleanUp(
    Type => $CacheType,
);

$Self->DoneTesting();
