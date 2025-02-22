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

package Kernel::System::Console::Command::Maint::SMIME::CustomerCertificate::Renew;

use strict;
use warnings;

use parent qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::CheckItem',
    'Kernel::System::Crypt::SMIME',
    'Kernel::System::CustomerUser',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Renew existing S/MIME certificates from customer backends.');

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->Print("<yellow>Renewing existing customer S/MIME certificates...</yellow>\n");

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $StopExecution;
    if ( !$ConfigObject->Get('SMIME') ) {
        $Self->Print("'S/MIME' is not activated in SysConfig, can't continue!\n");
        $StopExecution = 1;
    }
    elsif ( !$ConfigObject->Get('SMIME::FetchFromCustomer') ) {
        $Self->Print("'SMIME::FetchFromCustomer' is not activated in SysConfig, can't continue!\n");
        $StopExecution = 1;
    }

    if ($StopExecution) {
        $Self->Print("\n<green>Done.</green>\n");
        return $Self->ExitCodeOk();
    }

    my $CryptObject = $Kernel::OM->Get('Kernel::System::Crypt::SMIME');
    if ( !$CryptObject ) {
        $Self->PrintError("S/MIME environment is not working!\n");
        $Self->Print("<red>Fail.</red>\n");
        return $Self->ExitCodeError();
    }

    my ( $ListOfCertificates, $EmailsFromCertificates ) = $Self->_GetCurrentData();

    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

    EMAIL:
    for my $Email ( sort keys %{$EmailsFromCertificates} ) {

        my %UserList = $CustomerUserObject->CustomerSearch(
            PostMasterSearch => $Email,
            Limit            => 1,
        );

        next EMAIL if !%UserList;

        my @UserLogins = sort keys %UserList;

        my %CustomerUser = $CustomerUserObject->CustomerUserDataGet(
            User => $UserLogins[0],
        );

        next EMAIL if !%CustomerUser;
        next EMAIL if !$CustomerUser{UserSMIMECertificate};
        next EMAIL if $ListOfCertificates->{ $CustomerUser{UserSMIMECertificate} };

        my @Files = $CryptObject->FetchFromCustomer(
            Search => $Email,
        );

        for my $Filename (@Files) {
            my $Certificate = $CryptObject->CertificateGet(
                Filename => $Filename,
            );

            my %CertificateAttributes = $CryptObject->CertificateAttributes(
                Certificate => $Certificate,
                Filename    => $Filename,
            );

            $Self->Print("  Found new S/MIME certificates for <yellow>$UserLogins[0]</yellow> ...\n");
            $Self->Print("    Added certificate $CertificateAttributes{Fingerprint} (<yellow>$Filename</yellow>)\n");
        }
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub _GetCurrentData {
    my ( $Self, %Param ) = @_;

    my $CryptObject = $Kernel::OM->Get('Kernel::System::Crypt::SMIME');

    # Get all existing certificates.
    my @CertList = $CryptObject->CertificateList();

    my %ListOfCertificates;
    my %EmailsFromCertificates;

    # Check all existing certificates for emails.
    CERTIFICATE:
    for my $Certname (@CertList) {

        my $CertificateString = $CryptObject->CertificateGet(
            Filename => $Certname,
        );

        my %CertificateAttributes = $CryptObject->CertificateAttributes(
            Certificate => $CertificateString,
            Filename    => $Certname,
        );

        # all SMIME certificates must have an Email Attribute
        next CERTIFICATE if !$CertificateAttributes{Email};

        my $ValidEmail = $Kernel::OM->Get('Kernel::System::CheckItem')->CheckEmail(
            Address => $CertificateAttributes{Email},
        );

        next CERTIFICATE if !$ValidEmail;

        # Remember certificate (don't need to be added again).
        $ListOfCertificates{$CertificateString} = $CertificateString;

        # Save email for checking for new certificate.
        $EmailsFromCertificates{ $CertificateAttributes{Email} } = 1;
    }

    return ( \%ListOfCertificates, \%EmailsFromCertificates );
}

1;
