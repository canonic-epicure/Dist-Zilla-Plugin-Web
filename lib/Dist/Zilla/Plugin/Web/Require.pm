package Dist::Zilla::Plugin::Web::Require;

# ABSTRACT: Generate the boilerplate allowing to use synchronous-style "require" 

use Moose;

with 'Dist::Zilla::Role::FileGatherer';
with 'Dist::Zilla::Role::FileMunger';

use Dist::Zilla::File::FromCode;

use JSON;
use Path::Class;
use File::ShareDir;
use IPC::Open2;
use Template;


has 'file_match' => (
    isa     => 'Str',
    is      => 'rw',
    
    default => sub { [ '^lib/.*\.js$' ] } 
);


has 'quick_n_dirty' => (
    is          => 'ro',
    
    default     => 0
);


has 'extra_safe_wrapping' => (
    is          => 'ro',
    
    default     => 0
);



has 'processed_files' => (
    is      => 'rw',
    
    default => sub { {} }
);


#================================================================================================================================================================================================================================================
sub mvp_multivalue_args { qw( file_match ) }
#sub mvp_aliases { return { filename => 'filenames', match => 'matches' } }



#================================================================================================================================================================================================================================================
sub gather_files {
}


#================================================================================================================================================================================================================================================
sub munge_files {
    my $self = shift;
    
    # never match (at least the filename characters)
    my $matches_regex = qr/\000/;

    $matches_regex = qr/$_|$matches_regex/ for ($self->file_match->flatten);

    for my $file ($self->zilla->files->flatten) {
        next unless $file->name =~ $matches_regex;
        
        $self->process_file($file);
    }
}


#================================================================================================================================================================================================================================================
sub process_file {
    my ($self, $file_name)   = @_;
    
    my $content         = $self->get_content_of($file_name);
    
    my @requires        = $self->collect_all_resolved_requires($file_name);
    
    my $file_info       = {
        requires_raw            => $self->get_require_statements_of_file($file_name),
        requires_all_resolved   => \@requires
    };
    

    my $template = <<'REQUIRE';
require.modules["[% file_name %]"] = function (rootRequire) {

    var __dirname       = "[% dir_name %]"
    var __filename      = "[% file_name %]"
    
    var exports         = {}
    var module          = { exports : exports }
    
    var require         = rootRequire.child(__dirname)
    
    require.cache[ __filename ] = exports; 
    
    [% IF extra_safe_wrapping %]
    ;(function () {
        [% content %]
    })()
    [% ELSE %]
    [% content %]
    [% END %]
    
    return module.exports
}
REQUIRE
    
    
    my $tt      = Template->new();
    my $res     = '';
    
    $tt->process(\$template, {
        
        file_name               => $file_name,
        dir_name                => file($file_name)->dir . '',
        extra_safe_wrapping     => $self->extra_safe_wrapping,
        content                 => $file_name =~ m!\.json$! ? "module.exports = $content" : $content
        
    }, \$res) || die $tt->error(), "\n";
    
#    $file->content($res);
    
    $self->add_file(Dist::Zilla::File::FromCode->new({
        name => $file_name,
        
        code => sub {
        }
    }))
}


#================================================================================================================================================================================================================================================
sub collect_all_resolved_requires {
    my ($self, $file_name, $source_files) = @_;
    
    $source_files ||= [];
    
    # do not recurse in case of cycles
    return () if grep { $_ eq $file_name } @$source_files;
    
    my @requires        = $self->get_require_statements_of_file($file_name);
    
    foreach my $require (@requires) {
        my $resolved    = $self->resolve_require($file_name, $require);
        
        push @requires, $resolved, $self->collect_all_resolved_requires($resolved, \($file_name, @$source_files));
    }
    
    my %requires = map { $_ => 0 } @requires;
    
    return grep { $_ } %requires;
}



#================================================================================================================================================================================================================================================
sub resolve_require {
    my ($self, $base_file_name, $require)   = @_;
    
    $require =~ m!^  (\./|/|\.\./)?  (\.[^.]+)?  $!x;
    
    # require absolute
    if ($1 eq '/') {
        
    } elsif ($1) {
        # relative require
        my $resolved = $self->cleanup_file_name(file($base_file_name)->dir->file($require)->cleanup . '');

#        if ($self->has_file($resolved)) {}
        
    } else {
        # require built-in module or module from "node_modules"
        
        
    }
    
}


#================================================================================================================================================================================================================================================
sub cleanup_file_name {
    my ($self, $file_name)   = @_;
    
    my $parent_dir  = qr![^/]+/\.\./!;
    
    # remove "PARENT_DIR/../" chunks while available
    while ($file_name =~ m/$parent_dir/) {
        $file_name =~ s/$parent_dir//;    
    }
    
    return $file_name;
}



#================================================================================================================================================================================================================================================
sub get_content_of {
    my ($self, $file_name)      = @_;
    
#    if
}


#================================================================================================================================================================================================================================================
sub get_dzil_file {
    my ($self, $file_name)      = @_;
            
    if (ref(\$file_name) eq 'SCALAR') {
        my ($found)     = grep { $_->name eq $file_name } (@{$self->zilla->files});
        
        return $found;
    }
            
    if (ref($file_name) eq 'Regexp') {
        my @found       = grep { $_->name =~ $file_name } (@{$self->zilla->files});
        
        return @found;
    }
}

#================================================================================================================================================================================================================================================
sub get_require_statements_of_file {
    my ($self, $file_name)    = @_;
    
    my $processed_files = $self->processed_files;
    
    return $processed_files->{ $file_name } if defined($processed_files->{ $file_name });
    
    return $processed_files->{ $file_name } = $self->get_require_statements($self->get_content_of($file_name));
}


#================================================================================================================================================================================================================================================
sub get_require_statements {
    my ($self, $content)    = @_;
    
    if ($self->quick_n_dirty) {
        my @matches     = ($content =~ m/require \s* \(  ('|")  ([\w\/\.-]*)   \g{-2}   \)/gx);
        
        return grep { $_ ne '"' && $_ ne "'" } @matches;
        
    } else {
        my $extract_require_file = dir( File::ShareDir::dist_dir('Dist-Zilla-Plugin-Web') )->file('js/extract_require.js') . '';
        
        my ($child_out, $child_in);
        
        my $pid     = open2($child_out, $child_in, "node $extract_require_file");                
        
        print $child_in $content;
        
        close($child_in);
        
        waitpid( $pid, 0 );
        my $child_exit_status = $? >> 8;
        
        die "Error during 'require' extraction: $child_exit_status" if $child_exit_status;                
        
        my $res = do { local $/; <$child_out> };
        
        close($child_out);
        
        return @{JSON->new->decode($res)};
    }
}



no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;


=head1 SYNOPSIS

In your F<dist.ini>:

    [Web::Require]


=head1 DESCRIPTION

Description

=cut
