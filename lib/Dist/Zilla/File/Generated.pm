package Dist::Zilla::File::Generated;

# ABSTRACT: a file whose content is built on demand and changed later
use Moose;

use namespace::autoclean;

extends 'Dist::Zilla::File::FromCode';

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

__PACKAGE__->meta->make_immutable;
1;
