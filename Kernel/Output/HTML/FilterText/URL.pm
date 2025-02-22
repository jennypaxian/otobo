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

package Kernel::Output::HTML::FilterText::URL;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Pre {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{Data} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need Data!'
        );
        $Kernel::OM->Get('Kernel::Output::HTML::Layout')->FatalDie();
    }

    $Self->{LinkHash} = undef;
    my $Counter = 0;
    my %Seen;
    ${ $Param{Data} } =~ s{
        ( > | < | &gt; | &lt; | )  # $1 greater-than and less-than sign

        (                                            # $2
            (?:                                      # http or only www
                (?: (?: http s? | ftp ) :\/\/) |     # http://, https:// and ftp://
                (?: [a-z0-9\-]* \.?                  # allow for sub-domain or prefixes bug#12472
                    (?: www | ftp ) \. \w+           # www.something and ftp.something
                )
            )
            .*?                           # this part should be better defined!
        )
        (                                 # $3
            [\?,;!\.] (?: \s | $ )        # this construct was root cause of bug#2450 and bug#7288
            | \s
            | \"
            | &quot;
            | &nbsp;
            | '
            | >                           # greater-than and less-than sign
            | <                           # "
            | &gt;                        # "
            | &lt;                        # "
            | $                           # bug#2715
        )        }
    {
        my $Start = $1;
        my $Link  = $2;
        my $End   = $3;
        if ($Seen{$Link}) {
            $Start . $Seen{$Link} . $End;
        }
        else {
            $Counter++;
            my $Length = length $Link ;
            $Length = $Length < 75 ? $Length : 75;
            my $String = '#' x $Length;
            $Self->{LinkHash}->{"[$String$Counter]"} = $Link;
            $Seen{$Link} = "[$String$Counter]";
            $Start . "[$String$Counter]" . $End;
        }
    }egxism;

    return $Param{Data};
}

sub Post {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{Data} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need Data!'
        );
        $Kernel::OM->Get('Kernel::Output::HTML::Layout')->FatalDie();
    }

    if ( $Self->{LinkHash} ) {
        for my $Key ( sort keys %{ $Self->{LinkHash} } ) {
            my $LinkSmall = $Self->{LinkHash}->{$Key};
            $LinkSmall =~ s/^(.{75}).*$/$1\[\.\.\]/gs;
            my $Link = $Self->{LinkHash}->{$Key};
            if ( $Link !~ m{^ ( http | https | ftp ) : \/ \/ }xi ) {
                if ( $Link =~ m{^ ftp }smx ) {
                    $Link = 'ftp://' . $Link;
                }
                else {
                    $Link = 'http://' . $Link;
                }
            }
            $Link =~ s/ //g;
            ${ $Param{Data} }
                =~ s/\Q$Key\E/<a href=\"$Link\" target=\"_blank\" title=\"$Link\">$LinkSmall<\/a>/g;
        }
    }

    return $Param{Data};
}

1;
