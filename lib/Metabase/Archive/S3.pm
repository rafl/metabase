# Copyright (c) 2008 by Ricardo Signes. All rights reserved.
# Licensed under terms of Perl itself (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License was distributed with this file or you may obtain a
# copy of the License from http://dev.perl.org/licenses/

package Metabase::Archive::S3;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;

use Metabase::Fact;
use Carp       ();
use Data::GUID ();
use JSON::XS   ();
use Net::Amazon::S3;
use Path::Class ();
use Compress::Zlib qw(compress uncompress);

our $VERSION = '0.001';
$VERSION = eval $VERSION;

with 'Metabase::Archive';

has 'aws_access_key_id' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'aws_secret_access_key' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'bucket' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'prefix' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'compressed' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
);

has 's3_bucket' => (
    is       => 'ro',
    isa      => 'Net::Amazon::S3::Client::Bucket',
    required => 1,
    lazy     => 1,
    default  => sub {
        my $self = shift;
        my $s3   = Net::Amazon::S3->new(
            aws_access_key_id     => $self->aws_access_key_id,
            aws_secret_access_key => $self->aws_secret_access_key,
            retry                 => 1,
        );
        my $client = Net::Amazon::S3::Client->new( s3 => $s3 );
        return $client->bucket( name => $self->bucket );
    }
);

# given fact, store it and return guid; return
# XXX can we store a fact with a GUID already?  Replaces?  Or error?
# here assign only if no GUID already
sub store {
    my ( $self, $fact_struct ) = @_;
    my $guid = $fact_struct->{metadata}{core}{guid}[1];
    my $type = $fact_struct->{metadata}{core}{type}[1];

    unless ($guid) {
        Carp::confess "Can't store: no GUID set for fact\n";
    }

    my $content = $fact_struct->{content};

    my $object = {
        guid    => $guid,
        type    => $type,
        meta    => $fact_struct->{metadata}{core},
        content => $content,
    };

    my $json = JSON::XS->new->encode($object);

    if ( $self->compressed ) {
        $json = compress($json);
    }

    my $s3_object = $self->s3_bucket->object(
        key          => $self->prefix . $guid,
        acl_short    => 'public-read',
        content_type => 'application/json',
    );
    $s3_object->put($json);

    return $guid;
}

# given guid, retrieve it and return it
# type is directory path
# class isa Metabase::Fact::Subclass
sub extract {
    my ( $self, $guid ) = @_;

    my $s3_object = $self->s3_bucket->object( key => $self->prefix . $guid );
    my $json = $s3_object->get;

    if ( $self->compressed ) {
        $json = uncompress($json);
    }

    my $object  = JSON::XS->new->decode($json);
    my $type    = $object->{type};
    my $meta    = $object->{meta};
    my $content = $object->{content};

    # reconstruct fact meta and extract type to find the class
    my $class = Metabase::Fact->class_from_type($type);

    return {
        content  => $content,
        metadata => { core => $meta },
    };
}

1;

__END__

=pod

=for Pod::Coverage::TrustPod store extract

=head1 NAME

Metabase::Archive::S3 - Metabase storage using Amazon S3

=head1 SYNOPSIS

  require Metabase::Archive::S3;
  Metabase::Archive::S3->new(
    aws_access_key_id => 'XXX',
    aws_secret_access_key => 'XXX',
    bucket     => 'acme',
    prefix     => 'metabase/',
    compressed => 0,
  );

=head1 DESCRIPTION

Store facts in Amazon S3.

=head1 USAGE

See L<Metabase::Archive> and L<Metabase::Librarian>.

TODO: document optional C<compressed> option (default 1) and
C<schema> option (sensible default provided).

=head1 BUGS

Please report any bugs or feature using the CPAN Request Tracker.
Bugs can be submitted through the web interface at
L<http://rt.cpan.org/Dist/Display.html?Queue=Metabase>

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

=head1 AUTHOR

=over

=item *

Leon Brocard (ACME)

=back

=head1 COPYRIGHT AND LICENSE

Portions Copyright (c) 2010 by Leon Brocard

Licensed under terms of Perl itself (the "License").
You may not use this file except in compliance with the License.
A copy of the License was distributed with this file or you may obtain a
copy of the License from http://dev.perl.org/licenses/

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut
