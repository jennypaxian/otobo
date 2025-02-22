# --
# OTOBO is a web-based ticketing system for service organisations.
# --
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

package Kernel::Output::HTML::Dashboard::MyLastChangedTickets;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed objects
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    # check if the user has filter preferences for this widget
    my %Preferences = $Kernel::OM->Get('Kernel::System::User')->GetPreferences(
        UserID => $Self->{UserID},
    );

    $Self->{PrefKeyShown} = 'UserDashboardPref' . $Self->{Name} . '-Shown';
    $Self->{PageShown}    = $Preferences{ $Self->{PrefKeyShown} };

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    my @Params = (
        {
            Desc  => Translatable('Shown Tickets'),
            Name  => $Self->{PrefKeyShown},
            Block => 'Option',
            Data  => {
                5  => ' 5',
                10 => '10',
                15 => '15',
                20 => '20',
                25 => '25',
                30 => '30',
                35 => '35',
            },
            SelectedID  => $Self->{PageShown},
            Translation => 0,
        },
    );

    return @Params;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },
        CacheKey => 'MyLastChangedTickets'
            . $Self->{UserID} . '-'
            . $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{UserLanguage},
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $UseRefresh = $ConfigObject->Get('DashboardMyLastChangedTickets::UseRefresh');
    if ($UseRefresh) {
        $LayoutObject->Block(
            Name => 'Refresh',
            Data => {
                Name => $Self->{Name},
            },
        );
    }

    my %Preferences = $UserObject->GetPreferences(
        UserID => $Self->{UserID},
    );

    my $UserLimit = $Preferences{ $Self->{PrefKeyShown} };
    my $Limit     = $UserLimit || $ConfigObject->Get('DashboardMyLastChangedTickets::Limit');

    my $SQL = qq~
        SELECT ticket_id, MAX(change_time) max_t
        FROM ticket_history
        WHERE change_by = ?
        GROUP BY ticket_id
        ORDER BY max_t desc
    ~;

    return if !$DBObject->Prepare(
        SQL   => $SQL,
        Bind  => [ \$Self->{UserID} ],
        Limit => $Limit,
    );

    my @TicketIDs;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @TicketIDs, $Row[0];
    }

    if ( !@TicketIDs ) {
        $LayoutObject->Block(
            Name => 'NoTickets',
        );
    }
    else {
        for my $TicketID (@TicketIDs) {
            my %Ticket = $TicketObject->TicketGet(
                TicketID => $TicketID,
                UserID   => $Self->{UserID},
            );

            $Ticket{Link} = "Action=AgentTicketZoom&TicketID=$TicketID";

            $LayoutObject->Block(
                Name => 'Ticket',
                Data => \%Ticket,
            );
        }
    }

    # render content
    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardMyLastChangedTickets',
        Data         => {
            %{ $Self->{Config} },
        },
    );

    # return content
    return $Content;
}

1;
