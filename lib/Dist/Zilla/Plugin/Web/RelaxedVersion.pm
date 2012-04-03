package Dist::Zilla::Plugin::Web::RelaxedVersion;

# ABSTRACT: Allow free-form version of the distribution, currently using dirty hack

use Moose;

with 'Dist::Zilla::Role::Plugin';

use version 0.82;

has 'enabled' => (
    isa     => 'Bool',
    is      => 'rw',
    
    default => 0
);


#================================================================================================================================================================================================================================================
sub BUILD {
    my ($self)      = @_;
    
    if ($self->enabled) {
        no warnings;
        
        *version::is_lax = sub { 1 };
    }
}


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;


=head1 SYNOPSIS

In your F<dist.ini>:

    [Web::RelaxedVersion]
    enabled = 0 ; default

=head1 DESCRIPTION

This plugins uses a dirty hack to allow you to have a free-form version for your distribution, like : '1.0.8-alpha-2-beta-3'.
Because the hack is really dirty (a global override for version::is_lax), one need to explicitly enable this plugin with "enabled = 1" config option. 

=cut
