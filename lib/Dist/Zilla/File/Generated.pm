package Dist::Zilla::File::Generated;
# ABSTRACT: a file whose content is built on demand and changed later
use Moose;

use namespace::autoclean;

=head1 DESCRIPTION

This represents a file whose contents will be generated on demand from a
callback or method name.

It has one attribute, C<code>, which may be a method name (string) or a
coderef.  When the file's C<content> method is first called, the code is used to
generate the content.  This content I<is> cached and later can be changed, 
using C<content> method as accessor. 

=cut

has 'code' => (
    is        => 'rw',
    isa       => 'CodeRef|Str',
    required  => 1
);


has 'content' => (
    is        => 'rw',
    isa       => 'Str',
    lazy      => 1,
  
    builder   => '_build_content',
);


sub _build_content {
    my ($self) = @_;

    my $code = $self->code;
    
    return $self->$code;
}


with 'Dist::Zilla::Role::File';

__PACKAGE__->meta->make_immutable;
1;
