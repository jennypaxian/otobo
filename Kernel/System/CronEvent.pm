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

package Kernel::System::CronEvent;

use strict;
use warnings;

# core modules

# CPAN modules
use Schedule::Cron::Events ();

# OTOBO modules
use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::System::DateTime',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::CronEvent - Cron Events wrapper functions

=head1 DESCRIPTION

Functions to calculate cron events time.


=head2 new()

create a CronEvent object. Do not use it directly, instead use:

    my $CronEventObject = $Kernel::OM->Get('Kernel::System::CronEvent');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 NextEventGet()

gets the time when the next cron event should occur, from a given time.

    my $EventSystemTime = $CronEventObject->NextEventGet(
        Schedule      => '*/2 * * * *',    # recurrence parameters based in cron notation
        StartDateTime => $DateTimeObject,  # optional
    );

Returns:

    my $EventDateTime = '2016-01-23 14:56:12';  # or false in case of an error

=cut

sub NextEventGet {
    my ( $Self, %Param ) = @_;

    # check needed params
    if ( !$Param{Schedule} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Schedule!",
        );

        return;
    }

    my $StartDateTime = $Param{StartDateTime} || $Kernel::OM->Create('Kernel::System::DateTime');

    return if !$StartDateTime;

    # Calculations are only made in UTC time zone to prevent errors with times that
    # would not exist in the given time zone (e. g. on/around daylight saving time switch).
    # CPAN DateTime fails if trying to create a object of a non-existing
    # time in the given time zone. Converting it to UTC and back has the desired effect.
    my $OTOBOTimeZone = $StartDateTime->OTOBOTimeZoneGet();
    my $TimeZoneChanged;
    if ( $OTOBOTimeZone ne 'UTC' ) {
        $StartDateTime->ToTimeZone(
            TimeZone => 'UTC'
        );
        $TimeZoneChanged = 1;
    }

    # init cron object
    my $CronObject = $Self->_Init(
        Schedule      => $Param{Schedule},
        StartDateTime => $StartDateTime,
    );

    return if !$CronObject;

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $CronObject->nextEvent();

    my $EventDateTime = $Kernel::OM->Create(
        'Kernel::System::DateTime',
        ObjectParams => {
            Year     => $Year + 1900,
            Month    => $Month + 1,
            Day      => $Day,
            Hour     => $Hour,
            Minute   => $Min,
            Second   => $Sec,
            TimeZone => 'UTC'
        },
    );

    if ($TimeZoneChanged) {
        $EventDateTime->ToTimeZone(
            TimeZone => $OTOBOTimeZone
        );
    }

    return $EventDateTime->ToString();
}

=head2 NextEventList()

gets the time when the next cron events should occur, from a given time on a defined range.

    my @NextEvents = $CronEventObject->NextEventList(
        Schedule      => '*/2 * * * *',         # recurrence parameters based in cron notation
        StartDateTime => $StartDateTimeObject,  # optional, defaults to current date/time
        StopDateTime  => $StopDateTimeObject,
    );

Returns:

    my @NextEvents = [ '2016-01-12 13:23:01', ...  ];  # or false in case of an error

=cut

sub NextEventList {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(Schedule StopDateTime)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );

            return;
        }
    }

    my $StartDateTime = $Param{StartDateTime} || $Kernel::OM->Create('Kernel::System::DateTime');

    return if !$StartDateTime;

    my $StopDateTime = $Param{StopDateTime};

    if ( $StartDateTime > $StopDateTime ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "StartDateTime must be lower than or equals to StopDateTime",
        );

        return;
    }

    # Calculations are only made in UTC time zone to prevent errors with times that
    # would not exist in the given time zone (e. g. on/around daylight saving time switch).
    # CPAN DateTime fails if trying to create a object of a non-existing
    # time in the given time zone. Converting it to UTC and back has the desired effect.
    my $OTOBOTimeZone = $StartDateTime->OTOBOTimeZoneGet();
    my $TimeZoneChanged;
    if ( $OTOBOTimeZone ne 'UTC' ) {
        $StartDateTime->ToTimeZone(
            TimeZone => 'UTC'
        );
        $StopDateTime->ToTimeZone(
            TimeZone => 'UTC'
        );
        $TimeZoneChanged = 1;
    }

    # init cron object
    my $CronObject = $Self->_Init(
        Schedule      => $Param{Schedule},
        StartDateTime => $StartDateTime,
    );

    return if !$CronObject;

    my @Result;

    LOOP:
    while (1) {

        my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $CronObject->nextEvent();

        # it is needed to add 1 to the month for correct calculation
        my $EventDateTime = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                Year     => $Year + 1900,
                Month    => $Month + 1,
                Day      => $Day,
                Hour     => $Hour,
                Minute   => $Min,
                Second   => $Sec,
                TimeZone => 'UTC'
            },
        );

        last LOOP if !$EventDateTime;

        if ($TimeZoneChanged) {
            $EventDateTime->ToTimeZone(
                TimeZone => $OTOBOTimeZone
            );
        }

        last LOOP if $EventDateTime > $Param{StopDateTime};

        push @Result, $EventDateTime->ToString();
    }

    return @Result;
}

=head2 PreviousEventGet()

gets the time when the last Cron event had occurred, from a given time.

    my $PreviousSystemTime = $CronEventObject->PreviousEventGet(
        Schedule      => '*/2 * * * *',    # recurrence parameters based in Cron notation
        StartDateTime => $DateTimeObject,  # optional, defaults to current date/time
    );

Returns:

    my $EventDateTime = '2016-03-12 11:23:45';        # or false in case of an error

=cut

sub PreviousEventGet {
    my ( $Self, %Param ) = @_;

    # check needed params
    if ( !$Param{Schedule} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Schedule!",
        );

        return;
    }

    my $StartDateTime = $Param{StartDateTime} || $Kernel::OM->Create('Kernel::System::DateTime');

    return if !$StartDateTime;

    # Calculations are only made in UTC time zone to prevent errors with times that
    # would not exist in the given time zone (e. g. on/around daylight saving time switch).
    # CPAN DateTime fails if trying to create a object of a non-existing
    # time in the given time zone. Converting it to UTC and back has the desired effect.
    my $OTOBOTimeZone = $StartDateTime->OTOBOTimeZoneGet();
    my $TimeZoneChanged;
    if ( $OTOBOTimeZone ne 'UTC' ) {
        $StartDateTime->ToTimeZone(
            TimeZone => 'UTC'
        );
        $TimeZoneChanged = 1;
    }

    # init cron object
    my $CronObject = $Self->_Init(
        Schedule      => $Param{Schedule},
        StartDateTime => $StartDateTime,
    );

    return if !$CronObject;

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $CronObject->previousEvent();

    my $EventDateTime = $Kernel::OM->Create(
        'Kernel::System::DateTime',
        ObjectParams => {
            Year     => $Year + 1900,
            Month    => $Month + 1,
            Day      => $Day,
            Hour     => $Hour,
            Minute   => $Min,
            Second   => $Sec,
            TimeZone => 'UTC'
        },
    );

    if ($TimeZoneChanged) {
        $EventDateTime->ToTimeZone(
            TimeZone => $OTOBOTimeZone
        );
    }

    return $EventDateTime->ToString();
}

=head2 GenericAgentSchedule2CronTab()

converts a GenericAgent schedule to a CRON tab format string

    my $Schedule = $CronEventObject->GenericAgentSchedule2CronTab(
        ScheduleMinutes [1,2,3],
        ScheduleHours   [1,2,3],
        ScheduleDays    [1,2,3],
    );

    my $Schedule = '1,2,3 1,2,3 * * 1,2,3 *'  # or false in case of an error

=cut

sub GenericAgentSchedule2CronTab {
    my ( $Self, %Param ) = @_;

    # CRON Format
    # * * * * *     Field             Allowed values
    # | | | | |
    # | | | | +---- Day of the Week   (range: 1-7, 1 standing for Monday)
    # | | | +------ Month of the Year (range: 1-12)
    # | | +-------- Day of the Month  (range: 1-31)
    # | +---------- Hour              (range: 0-23)
    # +------------ Minute            (range: 0-59)

    # check needed params
    for my $Needed (qw(ScheduleMinutes ScheduleHours ScheduleDays)) {

        if ( !IsArrayRefWithData( $Param{$Needed} ) ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "$Needed is invalid!",
            );

            return;
        }

        # copy parameter to prevent changes
        my @Schedule = @{ $Param{$Needed} };

        # check ranges
        if ( $Needed eq 'ScheduleMinutes' ) {
            if ( grep { !IsNumber($_) || $_ < 0 || $_ > 59 } @Schedule ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "$Needed is invalid!",
                );

                return;
            }
        }
        elsif ( $Needed eq 'ScheduleHours' ) {
            if ( grep { !IsNumber($_) || $_ < 0 || $_ > 23 } @Schedule ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "$Needed is invalid!",
                );

                return;
            }
        }
        else {
            if ( grep { !IsNumber($_) || $_ < 0 || $_ > 6 } @Schedule ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "$Needed is invalid!",
                );

                return;
            }
        }
    }

    # set the minutes and hours components
    my $Schedule;
    for my $Component (qw(ScheduleMinutes ScheduleHours)) {

        $Schedule .= join ',', sort { $a <=> $b } @{ $Param{$Component} };

        # add a space
        $Schedule .= ' ';
    }

    # add the day and month components
    $Schedule .= '* * ';

    # convert week days (Sunday needs to be changed from 0 to 7)
    my @ScheduleDays = map {
        if   ( $_ == 0 ) {7}
        else             {$_}
    } @{ $Param{ScheduleDays} };

    $Schedule .= join ',', sort { $a <=> $b } @ScheduleDays;

    return $Schedule;
}

=begin Internal:

=cut

=head2 _Init()

creates a Schedule::Cron::Events object.

    my $CronObject = $CronEventObject->_Init(
        Schedule      => '*/2 * * * *',   # recurrence parameters based in Cron notation
        StartDateTime => $DateTimeObject,
    }

=cut

sub _Init {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(Schedule StartDateTime)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );

            return;
        }
    }

    # if a day and month are specified validate that the month has that specific day
    # this could be removed after Schedule::Cron::Events 1.94 is released and tested
    # see https://rt.cpan.org/Public/Bug/Display.html?id=109246
    my ( $Min, $Hour, $DayMonth, $Month, $DayWeek ) = split ' ', $Param{Schedule};    # pattern ' ' is treated as /\s+/
    if ( IsPositiveInteger($DayMonth) && IsPositiveInteger($Month) ) {

        my @MonthLastDay   = ( 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );
        my $LastDayOfMonth = $MonthLastDay[ $Month - 1 ];

        if ( $DayMonth > $LastDayOfMonth ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Schedule: $Param{Schedule} is invalid",
            );

            return;
        }
    }

    my %Start = %{ $Param{StartDateTime}->Get() };

    # create new internal cron object
    my $CronObject;
    eval {
        $CronObject = Schedule::Cron::Events->new(
            $Param{Schedule},
            Date => [
                $Start{'Second'},
                $Start{'Minute'},
                $Start{'Hour'},
                $Start{'Day'},
                $Start{'Month'} - 1,
                $Start{'Year'} - 1900,
            ],
        );
    };

    # error handling
    if ($@) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Schedule: $Param{Schedule} is invalid.",
        );
        return;
    }

    # check cron object
    if ( !$CronObject ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Could not create new Schedule::Cron::Events object!",
        );
        return;
    }

    return $CronObject;
}

=end Internal:

=cut

1;
