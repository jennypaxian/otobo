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

# get needed objects
my $MainObject       = $Kernel::OM->Get('Kernel::System::Main');
my $SystemDataObject = $Kernel::OM->Get('Kernel::System::SystemData');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# add system data
my $SystemDataNameRand0 = 'systemdata' . $Helper->GetRandomID();

my $Success = $SystemDataObject->SystemDataAdd(
    Key    => $SystemDataNameRand0,
    Value  => $SystemDataNameRand0,
    UserID => 1,
);

$Self->True(
    $Success,
    "SystemDataAdd() - added '$SystemDataNameRand0'",
);

# another time, it should fail
$Success = $SystemDataObject->SystemDataAdd(
    Key    => $SystemDataNameRand0,
    Value  => $SystemDataNameRand0,
    UserID => 1,
);

$Self->False(
    $Success,
    "SystemDataAdd() - can not add duplicate key '$SystemDataNameRand0'",
);

my $SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand0 );

$Self->True(
    $SystemData eq $SystemDataNameRand0,
    'SystemDataGet() - value',
);

my $SystemDataUpdate = $SystemDataObject->SystemDataUpdate(
    Key    => $SystemDataNameRand0,
    Value  => 'update' . $SystemDataNameRand0,
    UserID => 1,
);

$Self->True(
    $SystemDataUpdate,
    'SystemDataUpdate()',
);

$SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand0 );

$Self->Is(
    $SystemData,
    'update' . $SystemDataNameRand0,
    'SystemDataGet() - after update',
);

$SystemDataUpdate = $SystemDataObject->SystemDataUpdate(
    Key    => 'NonExisting' . $MainObject->GenerateRandomString(),
    Value  => 'some value',
    UserID => 1,
);

$Self->False(
    $SystemDataUpdate,
    'SystemDataUpdate() should not work on nonexisting value',
);

my $SystemDataDelete = $SystemDataObject->SystemDataDelete(
    Key    => $SystemDataNameRand0,
    UserID => 1,
);

$Self->True(
    $SystemDataDelete,
    'SystemDataDelete() - removed key',
);

$SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand0 );

$Self->False(
    $SystemData,
    'SystemDataGet() - data is gone after delete',
);

# test setting value to empty string
# add system data 1
my $SystemDataNameRand1 = 'systemdata' . $Helper->GetRandomID();

$Success = $SystemDataObject->SystemDataAdd(
    Key    => $SystemDataNameRand1,
    Value  => '',
    UserID => 1,
);

$Self->True(
    $Success,
    "SystemDataAdd() - added '$SystemDataNameRand1' value empty string",
);

$SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand1 );

$Self->Is(
    $SystemData,
    '',
    'SystemDataGet() - value - empty string',
);

# set to 0
$Success = $SystemDataObject->SystemDataUpdate(
    Key    => $SystemDataNameRand1,
    Value  => 0,
    UserID => 1,
);

$Self->True(
    $Success,
    "SystemDataAdd() - added '$SystemDataNameRand1' value empty string",
);

$SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand1 );

$Self->IsDeeply(
    $SystemData,
    0,
    'SystemDataGet() - value - 0',
);

$SystemDataUpdate = $SystemDataObject->SystemDataUpdate(
    Key    => $SystemDataNameRand1,
    Value  => 'update',
    UserID => 1,
);

$Self->True(
    $SystemDataUpdate,
    'SystemDataUpdate()',
);

$SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand1 );

$Self->Is(
    $SystemData,
    'update',
    'SystemDataGet() - after update',
);

$SystemDataUpdate = $SystemDataObject->SystemDataUpdate(
    Key    => $SystemDataNameRand1,
    Value  => '',
    UserID => 1,
);

$Self->True(
    $SystemDataUpdate,
    'SystemDataUpdate()',
);

$SystemData = $SystemDataObject->SystemDataGet( Key => $SystemDataNameRand1 );

$Self->Is(
    $SystemData,
    '',
    'SystemDataGet() - after update empty string',
);

$SystemDataDelete = $SystemDataObject->SystemDataDelete(
    Key    => $SystemDataNameRand1,
    UserID => 1,
);

$Self->True(
    $SystemDataDelete,
    'SystemDataDelete() - removed key',
);

my $SystemDataGroupRand = 'systemdata' . $Helper->GetRandomID();

my %Storage = (
    Foo   => 'bar',
    Bar   => 'baz',
    Beef  => 'spam',
    Empty => '',
);

for my $Key ( sort keys %Storage ) {
    my $Result = $SystemDataObject->SystemDataAdd(
        Key    => $SystemDataGroupRand . '::' . $Key,
        Value  => $Storage{$Key},
        UserID => 1,
    );
    $Self->True(
        $Result,
        "SystemDataAdd: added key " . $SystemDataGroupRand . '::' . $Key,
    );
}

my %Group = $SystemDataObject->SystemDataGroupGet(
    Group  => $SystemDataGroupRand,
    UserID => 1,
);

for my $Key ( sort keys %Storage ) {
    $Self->Is(
        $Group{$Key},
        $Storage{$Key},
        "SystemDataGroupGet: test value for '$Key'.",
    );
}

$Storage{Bar} = 'drinks';
$SystemDataObject->SystemDataUpdate(
    Key    => $SystemDataGroupRand . '::Bar',
    Value  => $Storage{Bar},
    UserID => 1,
);

%Group = $SystemDataObject->SystemDataGroupGet(
    Group  => $SystemDataGroupRand,
    UserID => 1,
);

for my $Key ( sort keys %Storage ) {
    $Self->Is(
        $Group{$Key},
        $Storage{$Key},
        "SystemDataGroupGet: test value for '$Key'.",
    );
}

$SystemDataObject->SystemDataDelete(
    Key    => $SystemDataGroupRand . '::Beef',
    UserID => 1,
);

%Group = $SystemDataObject->SystemDataGroupGet(
    Group  => $SystemDataGroupRand,
    UserID => 1,
);

$Self->False(
    $Group{Beef},
    "Key 'Beef' deleted, GroupGet",
);

$Self->Is(
    $Group{Foo},
    'bar',
    "Key 'Foo' still there, GroupGet",
);

for my $Key ( sort keys %Group ) {
    my $Result = $SystemDataObject->SystemDataDelete(
        Key    => $SystemDataGroupRand . '::' . $Key,
        UserID => 1,
    );
    $Self->True(
        $Result,
        "SystemData: deleted key " . $SystemDataGroupRand . '::' . $Key,
    );
}

# cleanup is done by RestoreDatabase

$Self->DoneTesting();
