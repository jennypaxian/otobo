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
use Kernel::System::EmailParser ();

our $Self;

# get config object
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

# Disable email addresses checking.
$Helper->ConfigSettingChange(
    Key   => 'CheckEmailAddresses',
    Value => 0,
);

my $SendEmail = sub {
    my %Param = @_;

    my $EmailObject     = $Kernel::OM->Get('Kernel::System::Email');
    my $MailQueueObject = $Kernel::OM->Get('Kernel::System::MailQueue');

    # Delete mail queue
    $MailQueueObject->Delete();

    # Generate the mail and queue it
    $EmailObject->Send( %Param, );

    # Get last item in the queue.
    my $Items = $MailQueueObject->List();
    $Items = [ sort { $b->{ID} <=> $a->{ID} } @{$Items} ];
    my $LastItem = $Items->[0];

    my $Result = $MailQueueObject->Send( %{$LastItem} );

    return ( \$LastItem->{Message}->{Header}, \$LastItem->{Message}->{Body}, );
};

# do not really send emails
$ConfigObject->Set(
    Key   => 'SendmailModule',
    Value => 'Kernel::System::Email::DoNotSendEmail',
);

# disable dns lookups
$ConfigObject->Set(
    Key   => 'CheckMXRecord',
    Value => 1,
);

# test scenarios
my @Tests = (
    {
        Name => 'ascii',
        Data => {
            From     => 'john.smith@example.com',
            To       => 'john.smith2@example.com',
            Subject  => 'some subject',
            Body     => 'Some Body',
            MimeType => 'text/plain',
            Charset  => 'utf8',
        },
    },
    {
        Name => 'utf8 - de',
        Data => {
            From    => '"Fritz Müller" <fritz@example.com>',
            To      => '"Hans Kölner" <friend@example.com>',
            Subject =>
                'This is a text with öäüßöäüß to check for problems äöüÄÖüßüöä!',
            Body     => "Some Body\nwith\n\nöäüßüüäöäüß1öää?ÖÄPÜ",
            MimeType => 'text/plain',
            Charset  => 'utf8',
        },
    },
    {
        Name => 'utf8 - ru',
        Data => {
            From    => '"Служба поддержки (support)" <me@example.com>',
            To      => 'friend@example.com',
            Subject =>
                'это специальныйсабжект для теста системы тикетов',
            Body     => "Some Body\nlala",
            MimeType => 'text/plain',
            Charset  => 'utf8',
        },
    },
    {
        Name => 'utf8 - high unicode characters',
        Data => {
            From     => '"Служба поддержки (support)" <me@example.com>',
            To       => 'friend@example.com',
            Subject  => 'Test related to bug#9832',
            Body     => "\x{2660}",
            MimeType => 'text/plain',
            Charset  => 'utf8',
        },
    },
);

my $Count = 0;
for my $Encoding ( '', qw(base64 quoted-printable 8bit) ) {

    $Count++;
    my $CountSub = 0;
    for my $Test (@Tests) {

        $CountSub++;
        my $Name = "#$Count.$CountSub $Encoding $Test->{Name}";

        # set forcing of encoding
        $ConfigObject->Set(
            Key   => 'SendmailEncodingForce',
            Value => $Encoding,
        );

        $Kernel::OM->ObjectsDiscard( Objects => ['Kernel::System::Email'] );
        my $EmailObject = $Kernel::OM->Get('Kernel::System::Email');

        my ( $Header, $Body ) = $SendEmail->( %{ $Test->{Data} }, );

        # start MIME::Tools workaround
        ${$Body} =~ s/\n/\r/g;

        # end MIME::Tools workaround
        my $Email = ${$Header} . "\n" . ${$Body};
        my @Array = split /\n/, $Email;

        # parse email
        my $ParserObject = Kernel::System::EmailParser->new(
            Email => \@Array,
        );

        # check header
        KEY:
        for my $Key (qw(From To Cc Subject)) {
            next KEY if !$Test->{Data}->{$Key};
            $Self->Is(
                $ParserObject->GetParam( WHAT => $Key ),
                $Test->{Data}->{$Key},
                "$Name GetParam(WHAT => '$Key')",
            );
        }

        # check body
        if ( $Test->{Data}->{Body} ) {
            my $Body = $ParserObject->GetMessageBody();

            # start MIME::Tools workaround
            $Body =~ s/\r/\n/g;
            $Body =~ s/=\n//;
            $Body =~ s/\n$//;
            $Body =~ s/=$//;

            # end MIME::Tools workaround
            $Self->Is(
                $Body,
                $Test->{Data}->{Body},
                "$Name GetMessageBody()",
            );
        }

        # check charset
        if ( $Test->{Data}->{Charset} ) {
            $Self->Is(
                $ParserObject->GetCharset(),
                $Test->{Data}->{Charset},
                "$Name GetCharset()",
            );
        }

        # check Content-Type
        if ( $Test->{Data}->{Type} ) {
            $Self->Is(
                ( split /;/, $ParserObject->GetContentType() )[0],
                $Test->{Data}->{Type},
                "$Name GetContentType()",
            );
        }
    }
}

# cleanup is done by RestoreDatabase

$Self->DoneTesting();
