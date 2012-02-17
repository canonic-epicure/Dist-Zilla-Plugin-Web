package Dist::Zilla::Plugin::Web::StripBOM;

# ABSTRACT: Embedd module version to sources

use Moose;

use Path::Class;
use String::BOM qw(string_has_bom strip_bom_from_string);

with 'Dist::Zilla::Role::FileMunger';
with 'Dist::Zilla::Plugin::Web::Role::FileMatcher';

has 'file_match' => (
    is      => 'rw',

    default => sub { [ '.*' ] }
);



sub munge_files {
    my ($self) = @_;
    
    $self->for_each_matched_file(sub {
        my ($file)    = @_;

        my $content             = $file->content;
        
        if (string_has_bom($content)) {
            $file->content(strip_bom_from_string($content));
        }
    });
}


no Moose;
__PACKAGE__->meta->make_immutable();


1;

