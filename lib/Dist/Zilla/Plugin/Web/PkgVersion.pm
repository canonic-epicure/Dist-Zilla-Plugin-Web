package Dist::Zilla::Plugin::Web::PkgVersion;

# ABSTRACT: Embedd module version to sources

use Moose;

use Path::Class;

with 'Dist::Zilla::Role::FileMunger';


has 'file_match' => (
    is      => 'rw',

    default => sub { [ '^lib/.*\\.js$' ] }
);


has 'exculde_match' => (
    is      => 'rw',

    default => sub { [] }
);


sub mvp_multivalue_args { qw( file_match exculde_match ) }


sub munge_files {
    my ($self) = @_;
    
    my $matches_regex = qr/\000/;
    my $exclude_regex = qr/\000/;

    $matches_regex = qr/$_|$matches_regex/ for (@{$self->file_match});
    $exclude_regex = qr/$_|$exclude_regex/ for (@{$self->exculde_match});

    for my $file (@{$self->zilla->files}) {
        next unless $file->name =~ $matches_regex;
        next if     $file->name =~ $exclude_regex;

        my $content             = $file->content;
        my $content_copy        = $content;
        
        pos $content = 0;
        
        
        while ($content =~ m!
            ( (\s*) /\*  VERSION  (?'comma',)?  \*/)  
        !msxg) {
            
            my $overall             = $1;
            my $overall_quoted      = quotemeta $overall;
            
            my $comma               = $3 || '';
            my $whitespace          = $2;
            
            my $version             = $self->zilla->version;
            
            $version = "'$version'" if $version !~ m/^\d+(\.\d+)?$/;
            
            $content_copy =~ s!$overall_quoted!${whitespace}/*PKGVERSION*/VERSION : ${version}${comma}!;
        }
        
        $file->content($content_copy) if $content_copy ne $content;
    }
}


no Moose;
__PACKAGE__->meta->make_immutable();


1;



=head1 SYNOPSIS

In your F<dist.ini>:

    [Web::PkgVersion]
    file_match = ^lib/.*\.js$           ; default, regex for file names to process 
    file_match = ^lib/.*\.css$          ; allow several values
    excelude_match = ^lib/special.css$  ; default, regex for file names to exclude 
                                        ; from processing
    excelude_match = ^lib/donotinclude.css$  ; allow several values
    
In your sources:

    Class('Digest.MD5', {
        
        /*VERSION,*/
        
        has : {
            ...
        }
    })
    
    Class('Digest.MD5', {
        /*VERSION*/
    })
    
    
will become after build:

    Class('Digest.MD5', {
        
        VERSION : 0.01,
         
        has : {
            ...
        }
    })
    
    Class('Digest.MD5', {
        VERSION : 0.01
    })
    
    

=head1 DESCRIPTION

This plugin will process the files in your distribution, matching any of the "file_match" regular expressions. 
Files matching any of the "excelude_match" regular expression will not be processed.

Processing will mean the following: this plugin will replace the 
    
    /*VERSION*/
    /*VERSION,*/ 
    
placeholders with the distribution version.  


=cut
