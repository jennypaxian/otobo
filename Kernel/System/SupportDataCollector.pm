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

package Kernel::System::SupportDataCollector;

use v5.24;
use strict;
use warnings;

# core modules
use File::Basename qw(dirname);

# CPAN modules

# OTOBO modules
use Kernel::System::WebUserAgent ();

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::Encode',
    'Kernel::System::JSON',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::SystemData',
);

=head1 NAME

Kernel::System::SupportDataCollector - support data collector

=head1 DESCRIPTION

Functions for the support data collector.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $SupportDataCollectorObject = $Kernel::OM->Get('Kernel::System::SupportDataCollector');

=cut

sub new {
    my ($Type) = @_;

    # allocate new hash ref to object
    return bless {}, $Type;
}

=head2 Collect()

collect system data

    my %Result = $SupportDataCollectorObject->Collect(
        UseCache   => 1,    # (optional) to get data from cache if any
        WebTimeout => 60,   # (optional)
        Debug      => 1,    # (optional)
        Hostname   => 'my.test.host:8080' # (optional, for testing purposes)
    );

returns in case of error

    (
        Success      => 0,
        ErrorMessage => '...',
    )

otherwise

    (
        Success => 1,
        Result  => [
            {
                Identifier  => 'Kernel::System::SupportDataCollector::OTOBO::Version',
                DisplayPath => 'OTOBO',
                Status      => $StatusOK,
                Label       => 'OTOBO Version'
                Value       => '3.3.2',
                Message     => '',
            },
            {
                Identifier  => 'Kernel::System::SupportDataCollector::Apache::mod_perl',
                DisplayPath => 'OTOBO',
                Status      => $StatusProblem,
                Label       => 'mod_perl usage'
                Value       => '0',
                Message     => 'Please enable mod_perl to speed up OTOBO.',
            },
            {
                Identifier       => 'Some::Identifier',
                DisplayPath      => 'SomePath',
                Status           => $StatusOK,
                Label            => 'Some Label'
                Value            => '0',
                MessageFormatted => 'Some \n Formatted \n\t Text.',
            },
        ],
    )

=cut

sub Collect {
    my ( $Self, %Param ) = @_;

    my $CacheKey = 'DataCollect';

    if ( $Param{UseCache} ) {
        my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
            Type => 'SupportDataCollector',
            Key  => $CacheKey,
        );

        return %{$Cache} if ref $Cache eq 'HASH';
    }

    # Data must be collected in a web request context to be able to collect web server data.
    #   If called from CLI, make a web request to collect the data, but if the data couldn't
    #   be collected the function runs normal.
    if ( !$ENV{GATEWAY_INTERFACE} ) {
        my %ResultWebRequest = $Self->CollectByWebRequest(%Param);

        return %ResultWebRequest if $ResultWebRequest{Success};
    }

    # Get the disabled plugins from the config to generate a lookup hash, which can be used to skip these plugins.
    my %LookupPluginDisabled;
    {
        my $PluginDisabled = $Kernel::OM->Get('Kernel::Config')->Get('SupportDataCollector::DisablePlugins') || [];
        %LookupPluginDisabled = map { $_ => 1 } @{$PluginDisabled};
    }

    # Get the identifier filter blacklist from the config to generate a lookup hash, which can be used to
    # filter these identifier.
    my %LookupIdentifierFilterBlacklist;
    {
        my $IdentifierFilterBlacklist = $Kernel::OM->Get('Kernel::Config')->Get('SupportDataCollector::IdentifierFilterBlacklist') || [];
        %LookupIdentifierFilterBlacklist = map { $_ => 1 } @{$IdentifierFilterBlacklist};
    }

    # Look for all plug-ins in the file system, including the async plugins
    my @PluginFiles = (
        $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
            Directory => dirname(__FILE__) . '/SupportDataCollector/Plugin',
            Filter    => '*.pm',
            Recursive => 1,
        ),
        $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
            Directory => dirname(__FILE__) . '/SupportDataCollector/PluginAsynchronous',
            Filter    => '*.pm',
            Recursive => 1,
        ),
    );

    # Execute all plug-ins, except the disabled plugins
    my @Result;
    PLUGINFILE:
    for my $PluginFile (@PluginFiles) {

        # Convert file name => package name
        $PluginFile =~ s{^.*(Kernel/System.*)[.]pm$}{$1}xmsg;
        $PluginFile =~ s{/+}{::}xmsg;

        next PLUGINFILE if $LookupPluginDisabled{$PluginFile};

        if ( !$Kernel::OM->Get('Kernel::System::Main')->Require($PluginFile) ) {
            return (
                Success      => 0,
                ErrorMessage => "Could not load $PluginFile!",
            );
        }

        my $PluginObject = $PluginFile->new( %{$Self} );
        my %PluginResult = $PluginObject->Run();
        if ( !%PluginResult || !$PluginResult{Success} ) {
            return (
                Success      => 0,
                ErrorMessage => "Error during execution of $PluginFile: $PluginResult{ErrorMessage}",
            );
        }

        push @Result, @{ $PluginResult{Result} // [] };
    }

    # Remove the disabled plugins after the execution, because some plugins returns
    #   more information with a own identifier.
    @Result = grep { !$LookupIdentifierFilterBlacklist{ $_->{Identifier} } } @Result;

    # Sort the results from the plug-ins by the short identifier.
    @Result = sort { $a->{ShortIdentifier} cmp $b->{ShortIdentifier} } @Result;

    my %ReturnData = (
        Success => 1,
        Result  => \@Result,
    );

    # Cache the result only, if the support data were collected in a web request,
    #   to have all support data in the admin view.
    if ( $ENV{GATEWAY_INTERFACE} ) {

        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => 'SupportDataCollector',
            Key   => $CacheKey,
            Value => \%ReturnData,
            TTL   => 60 * 10,
        );
    }

    return %ReturnData;
}

sub CollectByWebRequest {
    my ( $Self, %Param ) = @_;

    # Create a challenge token to authenticate this request without customer/agent login.
    #   PublicSupportDataCollector requires this ChallengeToken.
    my $ChallengeToken = $Kernel::OM->Get('Kernel::System::Main')->GenerateRandomString(
        Length     => 32,
        Dictionary => [ 0 .. 9, 'a' .. 'f' ],    # Generate a hexadecimal value.
    );

    if (
        $Kernel::OM->Get('Kernel::System::SystemData')->SystemDataGet( Key => 'SupportDataCollector::ChallengeToken' )
        )
    {
        $Kernel::OM->Get('Kernel::System::SystemData')->SystemDataUpdate(
            Key    => 'SupportDataCollector::ChallengeToken',
            Value  => $ChallengeToken,
            UserID => 1,
        );
    }
    else {
        $Kernel::OM->Get('Kernel::System::SystemData')->SystemDataAdd(
            Key    => 'SupportDataCollector::ChallengeToken',
            Value  => $ChallengeToken,
            UserID => 1,
        );
    }

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Host = $Param{Hostname};
    $Host ||= $ConfigObject->Get('SupportDataCollector::HTTPHostname');

    if ( !$Host ) {
        my $FQDN = $ConfigObject->Get('FQDN');

        if ( $FQDN ne 'yourhost.example.com' && gethostbyname($FQDN) ) {
            $Host = $FQDN;
        }

        if ( !$Host && gethostbyname('localhost') ) {
            $Host = 'localhost';
        }

        $Host ||= '127.0.0.1';
    }

    # If the public interface is proteceted with .htaccess
    #   we can specify the htaccess login data here,
    #   this is neccessary for the support data collector.
    my $AuthString   = '';
    my $AuthUser     = $ConfigObject->Get('PublicFrontend::AuthUser');
    my $AuthPassword = $ConfigObject->Get('PublicFrontend::AuthPassword');
    if ( $AuthUser && $AuthPassword ) {
        $AuthString = $AuthUser . ':' . $AuthPassword . '@';
    }

    # Prepare web service config for the internal web request.
    my $URL =
        $ConfigObject->Get('HttpType')
        . '://'
        . $AuthString
        . $Host
        . '/'
        . $ConfigObject->Get('ScriptAlias')
        . 'public.pl';

    my $WebUserAgentObject = Kernel::System::WebUserAgent->new(
        Timeout => $Param{WebTimeout} || 20,
    );

    # Disable webuseragent proxy since the call is sent to self server, see bug#11680.
    $WebUserAgentObject->{Proxy} = '';

    my %Result = (
        Success => 0,
    );

    # Skip the ssl verification, because this is only a internal web request.
    my %Response = $WebUserAgentObject->Request(
        Type => 'POST',
        URL  => $URL,
        Data => {
            Action         => 'PublicSupportDataCollector',
            ChallengeToken => $ChallengeToken,
        },
        SkipSSLVerification => 1,
        NoLog               => $Param{Debug} ? 0 : 1,
    );

    if ( $Response{Status} ne '200 OK' ) {

        if ( $Param{Debug} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "SupportDataCollector - Can't connect to server - $Response{Status}",
            );
        }

        return %Result;
    }

    # check if we have content as a scalar ref
    if ( !$Response{Content} || ref $Response{Content} ne 'SCALAR' ) {

        if ( $Param{Debug} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "SupportDataCollector - No content received.",
            );
        }
        return %Result;
    }

    # convert internal used charset
    $Kernel::OM->Get('Kernel::System::Encode')->EncodeInput( $Response{Content} );

    # Discard HTML responses (error pages etc.).
    if ( substr( ${ $Response{Content} }, 0, 1 ) eq '<' ) {

        if ( $Param{Debug} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "SupportDataCollector - Response looks like HTML instead of JSON.",
            );
        }

        return %Result;
    }

    # decode JSON data
    my $ResponseData = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
        Data => ${ $Response{Content} },
    );
    if ( !$ResponseData || ref $ResponseData ne 'HASH' ) {

        if ( $Param{Debug} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "SupportDataCollector - Can't decode JSON: '" . ${ $Response{Content} } . "'!",
            );
        }
        return %Result;
    }

    return %{$ResponseData};
}

=head2 CollectAsynchronous()

collect asynchronous data (the asynchronous plug-in decide at which place the data will be saved)

    my %Result = $SupportDataCollectorObject->CollectAsynchronous();

returns:

    %Result = (
        Success      => 1,                  # or 0 in case of an error
        ErrorMessage => 'some message'      # optional (only in case of an error)
    );

=cut

sub CollectAsynchronous {
    my ( $Self, %Param ) = @_;

    # Look for all plug-ins in the FS
    my @PluginFiles = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
        Directory => dirname(__FILE__) . "/SupportDataCollector/PluginAsynchronous",
        Filter    => "*.pm",
        Recursive => 1,
    );

    # Execute all plug-ins
    for my $PluginFile (@PluginFiles) {

        # Convert file name => package name
        $PluginFile =~ s{^.*(Kernel/System.*)[.]pm$}{$1}xmsg;
        $PluginFile =~ s{/+}{::}xmsg;

        if ( !$Kernel::OM->Get('Kernel::System::Main')->Require($PluginFile) ) {
            return (
                Success      => 0,
                ErrorMessage => "Could not load $PluginFile!",
            );
        }
        my $PluginObject = $PluginFile->new( %{$Self} );

        my $Success = $PluginObject->RunAsynchronous();

        if ( !$Success ) {
            return (
                Success      => 0,
                ErrorMessage => "Error during asynchronous execution of $PluginFile.",
            );
        }
    }

    return (
        Success => 1,
    );
}

=head2 CleanupAsynchronous()

clean-up asynchronous data (the asynchronous plug-in decide for themselves)

    my $Success = $SupportDataCollectorObject->CleanupAsynchronous();

=cut

sub CleanupAsynchronous {
    my ( $Self, %Param ) = @_;

    # Look for all plug-ins in the FS
    my @PluginFiles = $Kernel::OM->Get('Kernel::System::Main')->DirectoryRead(
        Directory => dirname(__FILE__) . "/SupportDataCollector/PluginAsynchronous",
        Filter    => "*.pm",
        Recursive => 1,
    );

    # Execute all Plug-ins
    PLUGINFILE:
    for my $PluginFile (@PluginFiles) {

        # Convert file name => package name
        $PluginFile =~ s{^.*(Kernel/System.*)[.]pm$}{$1}xmsg;
        $PluginFile =~ s{/+}{::}xmsg;

        if ( !$Kernel::OM->Get('Kernel::System::Main')->Require($PluginFile) ) {
            return (
                Success      => 0,
                ErrorMessage => "Could not load $PluginFile!",
            );
        }
        my $PluginObject = $PluginFile->new( %{$Self} );

        next PLUGINFILE unless $PluginFile->can('CleanupAsynchronous');

        $PluginObject->CleanupAsynchronous();
    }

    return 1;
}

1;
