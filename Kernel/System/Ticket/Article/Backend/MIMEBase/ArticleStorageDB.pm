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

package Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageDB;

use strict;
use warnings;
use v5.24;

use parent qw(Kernel::System::Ticket::Article::Backend::MIMEBase::Base);

# core modules
use MIME::Base64 qw(decode_base64 encode_base64);

# CPAN modules

# OTOBO modules
use Kernel::System::VariableCheck qw(IsStringWithData);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Encode',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS',
);

=head1 NAME

Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageDB - DB based ticket article storage interface

=head1 DESCRIPTION

This class provides functions to manipulate ticket articles
in the database.
The methods are currently documented in L<Kernel::System::Ticket::Article::Backend::MIMEBase>.

Inherits from L<Kernel::System::Ticket::Article::Backend::MIMEBase::Base>.

See also L<Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS>.

=cut

sub ArticleMoveFiles {
    my ( $Self, %Param ) = @_;

    if ( !$Param{ArticleID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need ArticleID!",
        );

        return;
    }

    $Kernel::OM->Get('Kernel::System::DB')->Do(
        SQL  => 'DELETE FROM article_data_mime_attachment WHERE article_id = ?',
        Bind => [ \$Param{ArticleID} ],
    );

    return;
}

sub ArticleDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Item (qw(ArticleID UserID)) {
        if ( !$Param{$Item} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Item!",
            );

            return;
        }
    }

    # delete attachments
    $Self->ArticleDeleteAttachment(
        ArticleID        => $Param{ArticleID},
        UserID           => $Param{UserID},
        DeletedVersionID => $Param{DeletedVersionID} || 0
    );

    # delete plain message
    $Self->ArticleDeletePlain(
        ArticleID        => $Param{ArticleID},
        UserID           => $Param{UserID},
        DeletedVersionID => $Param{DeletedVersionID} || 0
    );

    # Delete storage directory in case there are leftovers in the FS.
    $Self->_ArticleDeleteDirectory(
        ArticleID => $Param{ArticleID},
        UserID    => $Param{UserID},
    );

    return 1;
}

sub ArticleDeletePlain {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Item (qw(ArticleID UserID)) {
        if ( !$Param{$Item} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Item!",
            );

            return;
        }
    }

    # delete attachments
    if ( !$Param{DeletedVersionID} ) {
        return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL  => 'DELETE FROM article_data_mime_plain WHERE article_id = ?',
            Bind => [ \$Param{ArticleID} ],
        );
    }
    else {
        return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL  => 'DELETE FROM article_data_mime_plain_version WHERE article_id = ?',
            Bind => [ \$Param{DeletedVersionID} ],
        );
    }

    # return if we only need to check one backend
    return 1 if !$Self->{CheckAllBackends};

    # return of only delete in my backend
    return 1 if $Param{OnlyMyBackend};

    return $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS')->ArticleDeletePlain(
        %Param,
        OnlyMyBackend => 1,
    );
}

sub ArticleDeleteAttachment {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Item (qw(ArticleID UserID)) {
        if ( !$Param{$Item} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Item!",
            );

            return;
        }
    }

    # delete attachments
    if ( !$Param{DeletedVersionID} ) {
        return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL  => 'DELETE FROM article_data_mime_attachment WHERE article_id = ?',
            Bind => [ \$Param{ArticleID} ],
        );
    }
    else {
        return if !$Kernel::OM->Get('Kernel::System::DB')->Do(
            SQL  => 'DELETE FROM article_data_mime_att_version WHERE article_id = ?',
            Bind => [ \$Param{DeletedVersionID} ],
        );
    }

    # return if we only need to check one backend
    return 1 if !$Self->{CheckAllBackends};

    # return if only delete in my backend
    return 1 if $Param{OnlyMyBackend};

    return $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS')->ArticleDeleteAttachment(
        %Param,
        OnlyMyBackend => 1,
    );
}

sub ArticleWritePlain {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Item (qw(ArticleID Email UserID)) {
        if ( !$Param{$Item} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Item!",
            );

            return;
        }
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # encode attachment if it's a postgresql backend!!!
    if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {

        $Kernel::OM->Get('Kernel::System::Encode')->EncodeOutput( \$Param{Email} );

        $Param{Email} = encode_base64( $Param{Email} );
    }

    # write article to db 1:1
    if ( !$Param{DeletedVersionID} ) {
        return if !$DBObject->Do(
            SQL => 'INSERT INTO article_data_mime_plain '
                . ' (article_id, body, create_time, create_by, change_time, change_by) '
                . ' VALUES (?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => [ \$Param{ArticleID}, \$Param{Email}, \$Param{UserID}, \$Param{UserID} ],
        );
    }
    else {
        return if !$DBObject->Do(
            SQL => 'INSERT INTO article_data_mime_plain_version '
                . ' (article_id, body, create_time, create_by, change_time, change_by) '
                . ' VALUES (?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => [ \$Param{DeletedVersionID}, \$Param{Email}, \$Param{UserID}, \$Param{UserID} ],
        );
    }

    return 1;
}

sub ArticleWriteAttachment {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Item (qw(Filename ContentType ArticleID UserID)) {
        if ( !IsStringWithData( $Param{$Item} ) ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Item!",
            );

            return;
        }
    }

    # Perform FilenameCleanUp here already to check for
    #   conflicting existing attachment files correctly
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    my $OrigFilename = $MainObject->FilenameCleanUp(
        Filename  => $Param{Filename},
        Type      => 'Local',
        NoReplace => 1,
    );

    # check for conflicts in the attachment file names
    my $UniqueFilename = $OrigFilename;
    {
        my %Index = $Self->ArticleAttachmentIndex(
            ArticleID => $Param{ArticleID},
        );

        my %UsedFile = map
            { $_->{Filename} => 1 }
            values %Index;

        NAME_CHECK:
        for ( my $i = 1; $i <= 50; $i++ ) {
            next NAME_CHECK unless $UsedFile{$UniqueFilename};

            # keep the extension when renaming
            if ( $OrigFilename =~ m/^(.*)\.(.+?)$/ ) {
                $UniqueFilename = "$1-$i.$2";
            }
            else {
                $UniqueFilename = "$OrigFilename-$i";
            }
        }
    }

    # get attachment size
    $Param{Filesize} = bytes::length( $Param{Content} );

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # encode attachment if it's a postgresql backend!!!
    if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {

        $Kernel::OM->Get('Kernel::System::Encode')->EncodeOutput( \$Param{Content} );

        $Param{Content} = encode_base64( $Param{Content} );
    }

    # set content id in angle brackets
    if ( $Param{ContentID} ) {
        $Param{ContentID} =~ s/^([^<].*[^>])$/<$1>/;
    }

    # Remove the file name from the disposition
    my $Disposition;
    if ( $Param{Disposition} ) {
        ($Disposition) = split /;/, $Param{Disposition}, 2;
    }
    $Disposition //= '';

    # write attachment to db
    if ( !$Param{DeletedVersionID} ) {
        return if !$DBObject->Do(
            SQL => '
                INSERT INTO article_data_mime_attachment (article_id, filename, content_type, content_size,
                    content, content_id, content_alternative, disposition, create_time, create_by,
                    change_time, change_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => [
                \$Param{ArticleID}, \$UniqueFilename,   \$Param{ContentType}, \$Param{Filesize},
                \$Param{Content},   \$Param{ContentID}, \$Param{ContentAlternative},
                \$Disposition,      \$Param{UserID},    \$Param{UserID},
            ],
        );
    }
    else {
        return if !$DBObject->Do(
            SQL => '
                INSERT INTO article_data_mime_att_version (article_id, filename, content_type, content_size,
                    content, content_id, content_alternative, disposition, create_time, create_by,
                    change_time, change_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, current_timestamp, ?, current_timestamp, ?)',
            Bind => [
                \$Param{DeletedVersionID}, \$UniqueFilename,   \$Param{ContentType}, \$Param{Filesize},
                \$Param{Content},          \$Param{ContentID}, \$Param{ContentAlternative},
                \$Disposition,             \$Param{UserID},    \$Param{UserID},
            ],
        );
    }

    return 1;
}

sub ArticlePlain {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ArticleID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ArticleID!',
        );

        return;
    }

    # prepare/filter ArticleID
    $Param{ArticleID} = quotemeta( $Param{ArticleID} );
    $Param{ArticleID} =~ s/\0//g;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # can't open article, try database
    return if !$DBObject->Prepare(
        SQL    => 'SELECT body FROM article_data_mime_plain WHERE article_id = ?',
        Bind   => [ \$Param{ArticleID} ],
        Encode => [0],
    );

    my $Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {

        # decode attachment if it's e. g. a postgresql backend!!!
        if ( !$DBObject->GetDatabaseFunction('DirectBlob') && $Row[0] !~ m/ / ) {
            $Data = decode_base64( $Row[0] );
        }
        else {
            $Data = $Row[0];
        }
    }
    return $Data if defined $Data;

    # return if we only need to check one backend
    return if !$Self->{CheckAllBackends};

    # return of only delete in my backend
    return if $Param{OnlyMyBackend};

    return $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS')->ArticlePlain(
        %Param,
        OnlyMyBackend => 1,
    );
}

sub ArticleAttachmentIndexRaw {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ArticleID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ArticleID!',
        );

        return;
    }

    my %Index;
    my $Counter = 0;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # try database
    if ( !$Param{VersionView} ) {
        return if !$DBObject->Prepare(
            SQL => '
                SELECT filename, content_type, content_size, content_id, content_alternative,
                    disposition
                FROM article_data_mime_attachment
                WHERE article_id = ?
                ORDER BY filename, id',
            Bind => [ \$Param{ArticleID} ],
        );
    }
    else {
        return if !$DBObject->Prepare(
            SQL => '
                    SELECT att.filename, att.content_type, att.content_size, att.content_id, att.content_alternative, att.disposition
                    FROM article_data_mime_att_version att
                    INNER JOIN article_version av ON att.article_id = av.id
                    WHERE av.source_article_id = ? AND att.article_id = ?
                    ORDER BY att.filename, att.id',
            Bind => [ \$Param{SourceArticleID}, \$Param{ArticleID} ],
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {

        my $Disposition = $Row[5];
        if ( !$Disposition ) {

            # if no content disposition is set images with content id should be inline
            if ( $Row[3] && $Row[1] =~ m{image}i ) {
                $Disposition = 'inline';
            }

            # converted article body should be inline
            elsif ( $Row[0] =~ m{file-[12]} ) {
                $Disposition = 'inline';
            }

            # all others including attachments with content id that are not images
            #   should NOT be inline
            else {
                $Disposition = 'attachment';
            }
        }

        # add the info the the hash
        $Counter++;
        $Index{$Counter} = {
            Filename           => $Row[0],
            FilesizeRaw        => $Row[2] || 0,
            ContentType        => $Row[1],
            ContentID          => $Row[3] || '',
            ContentAlternative => $Row[4] || '',
            Disposition        => $Disposition,
        };
    }

    # return existing index
    return %Index if %Index;

    # return if we only need to check one backend
    return if !$Self->{CheckAllBackends};

    # return if only delete in my backend
    return if $Param{OnlyMyBackend};

    return $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS')->ArticleAttachmentIndexRaw(
        %Param,
        OnlyMyBackend => 1,
    );
}

sub ArticleAttachment {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Item (qw(ArticleID FileID)) {
        if ( !$Param{$Item} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Item!",
            );

            return;
        }
    }

    # prepare/filter ArticleID
    $Param{ArticleID} = quotemeta( $Param{ArticleID} );
    $Param{ArticleID} =~ s/\0//g;

    # get attachment index
    my %Index = $Self->ArticleAttachmentIndex(
        ArticleID       => $Param{ArticleID},
        VersionView     => $Param{VersionView},
        SourceArticleID => $Param{SourceArticleID},
        ArticleDeleted  => $Param{ArticleDeleted} || ''
    );

    return if !$Index{ $Param{FileID} };
    my %Data = %{ $Index{ $Param{FileID} } };

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # try database
    if ( !$Param{VersionView} ) {
        return if !$DBObject->Prepare(
            SQL => '
                SELECT id
                FROM article_data_mime_attachment
                WHERE article_id = ?
                ORDER BY filename, id',
            Bind  => [ \$Param{ArticleID} ],
            Limit => $Param{FileID},
        );
    }
    else {

        if ( $Param{ArticleDeleted} ) {
            my $Temp = $Param{SourceArticleID};
            $Param{SourceArticleID} = $Param{ArticleID};
            $Param{ArticleID}       = $Temp;
        }

        return if !$DBObject->Prepare(
            SQL => '
                SELECT att.id
                FROM article_data_mime_att_version att
                INNER JOIN article_version av ON att.article_id = av.id
                WHERE av.id = ? AND av.source_article_id = ?
                ORDER BY att.filename, att.id',
            Bind  => [ \$Param{ArticleID}, \$Param{SourceArticleID} ],
            Limit => $Param{FileID},
        );
    }

    my $AttachmentID;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $AttachmentID = $Row[0];
    }

    if ( !$Param{VersionView} ) {
        return if !$DBObject->Prepare(
            SQL => '
                SELECT content_type, content, content_id, content_alternative, disposition, filename
                FROM article_data_mime_attachment
                WHERE id = ?',
            Bind   => [ \$AttachmentID ],
            Encode => [ 1, 0, 0, 0, 1, 1 ],
        );
    }
    else {
        return if !$DBObject->Prepare(
            SQL => '
                SELECT att.content_type, att.content, att.content_id, att.content_alternative, att.disposition, att.filename
                FROM article_data_mime_att_version att
                WHERE att.id = ?',
            Bind   => [ \$AttachmentID ],
            Encode => [ 1, 0, 0, 0, 1, 1 ],
        );
    }

    while ( my @Row = $DBObject->FetchrowArray() ) {

        $Data{ContentType} = $Row[0];

        # decode attachment if it's e. g. a postgresql backend!!!
        if ( !$DBObject->GetDatabaseFunction('DirectBlob') ) {
            $Data{Content} = decode_base64( $Row[1] );
        }
        else {
            $Data{Content} = $Row[1];
        }
        $Data{ContentID}          = $Row[2] || '';
        $Data{ContentAlternative} = $Row[3] || '';
        $Data{Disposition}        = $Row[4];
        $Data{Filename}           = $Row[5];
    }

    if ( !$Data{Disposition} ) {

        # if no content disposition is set images with content id should be inline
        if ( $Data{ContentID} && $Data{ContentType} =~ m{image}i ) {
            $Data{Disposition} = 'inline';
        }

        # converted article body should be inline
        elsif ( $Data{Filename} =~ m{file-[12]} ) {
            $Data{Disposition} = 'inline';
        }

        # all others including attachments with content id that are not images
        #   should NOT be inline
        else {
            $Data{Disposition} = 'attachment';
        }
    }

    return %Data if defined $Data{Content};

    # return if we only need to check one backend
    return if !$Self->{CheckAllBackends};

    # return if only delete in my backend
    return if $Param{OnlyMyBackend};

    return $Kernel::OM->Get('Kernel::System::Ticket::Article::Backend::MIMEBase::ArticleStorageFS')->ArticleAttachment(
        %Param,
        OnlyMyBackend => 1,
    );
}

1;
