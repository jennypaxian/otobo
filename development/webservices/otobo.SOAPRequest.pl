#!/usr/bin/env perl
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

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use SOAP::Lite;
use Data::Dumper;    ## no critic qw(Modules::ProhibitEvilModules)

# Variables to be defined

# this is the URL for the web service
# the format is
# <HTTP_TYPE>:://<OTOBO_FQDN>/nph-genericinterface.pl/Webservice/<WEB_SERVICE_NAME>
# or
# <HTTP_TYPE>:://<OTOBO_FQDN>/nph-genericinterface.pl/WebserviceID/<WEB_SERVICE_ID>
my $URL = 'http://localhost/otobo/nph-genericinterface.pl/Webservice/GenericTicketConnectorSOAP';

# this name space should match the specified name space in the SOAP transport for the web service
my $NameSpace = 'http://www.otobo.org/TicketConnector/';

# this is operation to execute, it could be TicketCreate, TicketUpdate, TicketGet, TicketSearch
# or SessionCreate. and they must to be defined in the web service.
my $Operation = 'TicketCreate';

# this variable is used to store all the parameters to be included on a request in XML format, each
# operation has a determined set of mandatory and non mandatory parameters to work correctly, please
# check OTRS Admin Manual in order to get the complete list
my $XMLData = '
<UserLogin>some user login</UserLogin>
<Password>some password</Password>
<Ticket>
    <Title>some title</Title>
    <CustomerUser>some customer user login</CustomerUser>
    <Queue>some queue</Queue>
    <State>some state</State>
    <Priority>some priority</Priority>
</Ticket>
<Article>
    <Subject>some subject</Subject>
    <Body>some body</Body>
    <ContentType>text/plain; charset=utf8</ContentType>
</Article>
';

# create a SOAP::Lite data structure from the provided XML data structure
my $SOAPData = SOAP::Data->type( 'xml' => $XMLData );

my $SOAPObject = SOAP::Lite->uri($NameSpace)->proxy($URL)
    ->$Operation($SOAPData);

# check for a fault in the soap code
if ( $SOAPObject->fault() ) {
    print $SOAPObject->faultcode(), " ", $SOAPObject->faultstring(), "\n";
}

# otherwise print the results
else {

    # get the XML response part from the SOAP message
    my $XMLResponse = $SOAPObject->context()->transport()->proxy()->http_response()->content();

    # deserialize response (convert it into a perl structure)
    my $Deserialized = eval {
        SOAP::Deserializer->deserialize($XMLResponse);
    };

    # remove all the headers and other not needed parts of the SOAP message
    my $Body = $Deserialized->body();

    # just output relevant data and no the operation name key (like TicketCreateResponse)
    for my $ResponseKey ( sort keys %{$Body} ) {
        print Dumper( $Body->{$ResponseKey} );
    }
}
