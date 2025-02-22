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

package Kernel::Modules::AgentTicketWatcher;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language              qw(Translatable);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # ------------------------------------------------------------ #
    # check if feature is active
    # ------------------------------------------------------------ #
    if ( !$ConfigObject->Get('Ticket::Watcher') ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Feature is not active'),
        );
    }

    # ------------------------------------------------------------ #
    # check access
    # ------------------------------------------------------------ #
    my @Groups;
    if ( $ConfigObject->Get('Ticket::WatcherGroup') ) {
        @Groups = @{ $ConfigObject->Get('Ticket::WatcherGroup') };
    }

    my $GroupObject = $Kernel::OM->Get('Kernel::System::Group');
    my $Access      = 1;
    if (@Groups) {
        $Access = 0;
        for my $Group (@Groups) {
            my $HasPermission = $GroupObject->PermissionCheck(
                UserID    => $Self->{UserID},
                GroupName => $Group,
                Type      => 'rw',
            );
            if ($HasPermission) {
                $Access = 1;
            }
        }
    }
    if ( !$Access ) {
        return $Self->{Layout}->NoPermission();
    }

    # get ACL restrictions
    my %PossibleActions = ( 1 => $Self->{Action} );

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $ACL = $TicketObject->TicketAcl(
        Data          => \%PossibleActions,
        Action        => $Self->{Action},
        TicketID      => $Self->{TicketID},
        ReturnType    => 'Action',
        ReturnSubType => '-',
        UserID        => $Self->{UserID},
    );
    my %AclAction = $TicketObject->TicketAclActionData();

    # check if ACL restrictions exist
    if ($ACL) {

        my %AclActionLookup = reverse %AclAction;

        # show error screen if ACL prohibits this action
        if ( !$AclActionLookup{ $Self->{Action} } ) {
            return $LayoutObject->NoPermission( WithHeader => 'yes' );
        }
    }

    # ------------------------------------------------------------ #
    # subscribe a ticket
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Subscribe' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # Checks if the user has permissions to see the ticket.
        #   This is needed because watching grants ro permissions (depending on configuration).
        my $Access = $TicketObject->TicketPermission(
            Type     => 'ro',
            TicketID => $Self->{TicketID},
            UserID   => $Self->{UserID},
        );
        if ( !$Access ) {
            return $LayoutObject->NoPermission( WithHeader => 'yes' );
        }

        # set subscribe
        my $Subscribe = $TicketObject->TicketWatchSubscribe(
            TicketID    => $Self->{TicketID},
            WatchUserID => $Self->{UserID},
            UserID      => $Self->{UserID},
        );

        if ( !$Subscribe ) {
            return $LayoutObject->ErrorScreen();
        }

        # redirect
        return $LayoutObject->Redirect(
            OP => "Action=AgentTicketZoom;TicketID=$Self->{TicketID}",
        );
    }

    # ------------------------------------------------------------ #
    # unsubscribe a ticket
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Unsubscribe' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # We don't need a permission check here as we will remove
        #   permissions by unsubscribing.
        my $Unsubscribe = $TicketObject->TicketWatchUnsubscribe(
            TicketID    => $Self->{TicketID},
            WatchUserID => $Self->{UserID},
            UserID      => $Self->{UserID},
        );

        if ( !$Unsubscribe ) {
            return $LayoutObject->ErrorScreen();
        }

        # redirect
        # checks if the user has permissions to see the ticket
        my $Access = $TicketObject->TicketPermission(
            Type     => 'ro',
            TicketID => $Self->{TicketID},
            UserID   => $Self->{UserID},
        );
        if ( !$Access ) {

            # generate output
            return $LayoutObject->Redirect(
                OP => $Self->{LastScreenOverview} || 'Action=AgentDashboard',
            );
        }
        return $LayoutObject->Redirect(
            OP => "Action=AgentTicketZoom;TicketID=$Self->{TicketID}",
        );
    }

    return $LayoutObject->ErrorScreen(
        Message => Translatable('Invalid Subaction.'),
    );
}

1;
