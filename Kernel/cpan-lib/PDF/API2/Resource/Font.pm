package PDF::API2::Resource::Font;

use base 'PDF::API2::Resource::BaseFont';

use strict;
use warnings;

our $VERSION = '2.045'; # VERSION

use Encode qw(:all);

use PDF::API2::Util;
use PDF::API2::Basic::PDF::Utils;

sub encodeByData {
    my ($self, $encoding) = @_;
    my $data = $self->data();

    my ($firstChar, $lastChar);

    if ($self->issymbol()) {
        $encoding = undef;
    }

    if (defined $encoding and $encoding =~ /^uni(\d+)$/) {
        my $blk = $1;
        $data->{'e2u'} = [ map { $blk * 256 + $_ } (0 .. 255) ];
        $data->{'e2n'} = [ map { nameByUni($_) or '.notdef' } @{$data->{'e2u'}} ];
        $data->{'firstchar'} = 0;
    }
    elsif (defined $encoding) {
        $data->{'e2u'} = [ unpack('U*', decode($encoding, pack('C*', 0 .. 255))) ];
        $data->{'e2n'} = [ map { nameByUni($_) or '.notdef' } @{$data->{'e2u'}} ];
    }
    elsif (defined $data->{'uni'}) {
        $data->{'e2u'} = [ @{$data->{'uni'}} ];
        $data->{'e2n'} = [ map { $_ or '.notdef' } @{$data->{'char'}} ];
    }
    else {
        $data->{'e2u'} = [ map { uniByName($_) } @{$data->{'char'}} ];
        $data->{'e2n'} = [ map { $_ or '.notdef' } @{$data->{'char'}} ];
    }

    $data->{'u2c'} = {};
    $data->{'u2e'} = {};
    $data->{'u2n'} = {};
    $data->{'n2c'} = {};
    $data->{'n2e'} = {};
    $data->{'n2u'} = {};

    foreach my $n (0 .. 255) {
        my $xchar;
        my $xuni;

        $xchar = $data->{'char'}->[$n] // '.notdef';
        $data->{'n2c'}->{$xchar} //= $n;

        $xchar = $data->{'e2n'}->[$n] // '.notdef';
        $data->{'n2e'}->{$xchar} //= $n;

        $data->{'n2u'}->{$xchar} //= $data->{'e2u'}->[$n];

        $xchar = $data->{'char'}->[$n] // '.notdef';
        $xuni = $data->{'uni'}->[$n] // 0;
        $data->{'n2u'}->{$xchar} //= $xuni;

        $data->{'u2c'}->{$xuni} //= $n;

        $xuni = $data->{'e2u'}->[$n] // 0;
        $data->{'u2e'}->{$xuni} //= $n;

        $xchar = $data->{'e2n'}->[$n] // '.notdef';
        $data->{'u2n'}->{$xuni} //= $xchar;

        $xchar = $data->{'char'}->[$n] // '.notdef';
        $xuni = $data->{'uni'}->[$n] // 0;
        $data->{'u2n'}->{$xuni} //= $xchar;
    }

    my $en = PDFDict();
    $self->{'Encoding'} = $en;

    $en->{'Type'} = PDFName('Encoding');
    $en->{'BaseEncoding'} = PDFName('WinAnsiEncoding');

    $en->{'Differences'} = PDFArray(PDFNum(0));
    foreach my $n (0 .. 255) {
        my $element = ($self->glyphByEnc($n) or '.notdef');
        $en->{'Differences'}->add_elements(PDFName($element));
    }

    $self->{'FirstChar'} = PDFNum($data->{'firstchar'});
    $self->{'LastChar'} = PDFNum($data->{'lastchar'});

    $self->{'Widths'} = PDFArray();
    foreach my $n ($data->{'firstchar'} .. $data->{'lastchar'}) {
        $self->{'Widths'}->add_elements(PDFNum($self->wxByEnc($n)));
    }

    return $self;
}

sub automap {
    my $self = shift();
    my $data = $self->data();

    my %gl = map { $_ => defineName($_) } keys %{$data->{'wx'}};

    foreach my $n (0 .. 255) {
        delete $gl{$data->{'e2n'}->[$n]};
    }

    if (defined $data->{'comps'} and not $self->{'-nocomps'}) {
        foreach my $n (keys %{$data->{'comps'}}) {
            delete $gl{$n};
        }
    }

    my @nm = sort { $gl{$a} <=> $gl{$b} } keys %gl;

    my @fonts;
    my $count = 0;
    while (my @glyphs = splice(@nm, 0, 223)) {
        my $obj = $self->SUPER::new($self->{' apipdf'}, $self->name() . 'am' . $count);
        $obj->{' data'} = { %$data };
        $obj->data->{'firstchar'} = 32;
        $obj->data->{'lastchar'} = 32 + scalar(@glyphs);
        push @fonts, $obj;
        foreach my $key (qw(Subtype BaseFont FontDescriptor)) {
            $obj->{$key} = $self->{$key} if defined $self->{$key};
        }
        $obj->data->{'char'} = [];
        $obj->data->{'uni'} = [];
        foreach my $n (0 .. 31) {
            $obj->data->{'char'}->[$n] = '.notdef';
            $obj->data->{'uni'}->[$n] = 0;
        }
        $obj->data->{'char'}->[32] = 'space';
        $obj->data->{'uni'}->[32] = 32;
        foreach my $n (33 .. $obj->data->{'lastchar'}) {
            $obj->data->{'char'}->[$n] = $glyphs[$n - 33];
            $obj->data->{'uni'}->[$n] = $gl{$glyphs[$n - 33]};
        }
        foreach my $n (($obj->data->{'lastchar'} + 1) .. 255) {
            $obj->data->{'char'}->[$n] = '.notdef';
            $obj->data->{'uni'}->[$n] = 0;
        }
        $obj->encodeByData(undef);

        $count++;
    }

    return @fonts;
}

sub remap {
    my ($self, $enc) = @_;

    my $obj = $self->SUPER::new($self->{' apipdf'}, $self->name() . 'rm' . pdfkey());
    $obj->{' data'} = { %{$self->data()} };
    foreach my $key (qw(Subtype BaseFont FontDescriptor)) {
        $obj->{$key} = $self->{$key} if defined $self->{$key};
    }

    $obj->encodeByData($enc);

    return $obj;
}

1;
