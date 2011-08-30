package Dist::Zilla::Plugin::Web::Require;

# ABSTRACT: Generate the boilerplate allowing to use synchronous-style "require" 

use Moose;

with 'Dist::Zilla::Role::FileGatherer';
with 'Dist::Zilla::Role::FileMunger';

use Dist::Zilla::File::FromCode;
use Dist::Zilla::File::InMemory;

use JSON;
use Path::Class;
use File::ShareDir;
use IPC::Open2;
use Template;


use XXX -with => 'Data::Dumper';

has 'file_match' => (
    is      => 'rw',
    
    default => sub { [ '^lib/.*\.js(on)?$' ] } 
);


has 'exculde_match' => (
    is      => 'rw',
    
    default => sub { [] } 
);



has 'quick_n_dirty' => (
    is          => 'ro',
    
    default     => 0
);


has 'extra_safe_wrapping' => (
    is          => 'ro',
    
    default     => 0
);


has 'raw_requires_cache' => (
    is      => 'rw',
    
    default => sub { {} }
);


has 'all_resolved_requires_cache' => (
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
    my $exclude_regex = qr/\000/;

    $matches_regex = qr/$_|$matches_regex/ for (@{$self->file_match});
    $exclude_regex = qr/$_|$exclude_regex/ for (@{$self->exculde_match});

    for my $file (@{$self->zilla->files}) {
        next unless $file->name =~ $matches_regex;
        next if     $file->name =~ $exclude_regex;
        
        $self->process_file($file);
    }
}


#================================================================================================================================================================================================================================================
sub process_file {
    my ($self, $file)   = @_;
    
    my $content         = $file->content;
    my $file_name       = $file->name;
    
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
    
    $file->content($res);
    
    $self->add_file(Dist::Zilla::File::FromCode->new({
        name => "$file_name.info",
        
        code => sub {
            JSON->new->utf8(1)->pretty(1)->encode($file_info);
        }
    }))
}


#================================================================================================================================================================================================================================================
sub collect_all_resolved_requires {
    my ($self, $file_name, $source_files) = @_;
    
    my $cache   = $self->all_resolved_requires_cache;
    
    return $cache->{ $file_name } if $cache->{ $file_name };
    
    $source_files ||= [];
    
    # do not recurse in case of cycles
    return () if grep { $_ eq $file_name } @$source_files;
    
    my @requires        = @{$self->get_require_statements_of_file($file_name)};
    
    foreach my $require (@requires) {
        my $resolved    = $self->resolve_require($file_name, $require);
        
        die "Can't resolve require string: require('$require') in [$file_name]" if !$resolved;
        
        push @requires, $resolved, $self->collect_all_resolved_requires($resolved, \($file_name, @$source_files));
    }
    
    my %requires = map { $_ => 0 } @requires;
    
    return $cache->{ $file_name } = grep { $_ } %requires;
}


#================================================================================================================================================================================================================================================
sub resolve_in_file_system {
    my ($self, $file_name, $not_dir)   = @_;
    
    return $file_name if $self->file_exists($file_name);
    
    return "$file_name.js" if $self->file_exists("$file_name.js");
    
    unless ($not_dir) {
        if ($self->directory_exists($file_name)) {
            
            my $package_json_file = dir($file_name)->file('package.json');
            
            if ($self->file_exists($package_json_file)) {
                my $package_json    = JSON->new->decode($self->get_content_of($package_json_file));
                
                return $self->resolve_require($file_name, $package_json->{ main }, 1) if $package_json->{ main }; 
            }
            
            return $self->resolve_require($file_name, 'index', 1)
        }
    }
    
    return undef
}


#================================================================================================================================================================================================================================================
sub resolve_require {
    my ($self, $base_file_name, $require, $not_dir)   = @_;
    
    $require =~ m!^(\./|/|\.\./)?(\.[^.]+)?$!;
    
    my $type = $1 || '';
    
    # require absolute
    if ($type eq '/') {
        
        return $self->resolve_in_file_system($require, $not_dir);
        
    } elsif ($type) {
        # relative require
        my $resolved = $self->cleanup_file_name(file($base_file_name)->dir->file($require)->cleanup . '');

        return $self->resolve_in_file_system($resolved, $not_dir);
        
    } else {
        # require built-in module or module from "node_modules"
        
        my @node_modules;
        
        my $dir = file($base_file_name)->dir . '';
        
        while ($dir =~ /((.*)(?:^|\/)node_modules)(?=\/|$)/) {
            
            push @node_modules, $1;
            
            $dir    = $2
        }
        
        WWW @node_modules;
        
        foreach my $node_module_dir (@node_modules) {
            my $resolved = $self->resolve_in_file_system(dir($node_module_dir)->file($require));
            
            return $resolved if $resolved;
        }
        
        return undef;
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
sub file_exists {
    my ($self, $file_name)      = @_;
    
    return 1 if $self->get_dzil_file($file_name);
    return 1 if -e $file_name;
    
    return 0; 
}


#================================================================================================================================================================================================================================================
sub directory_exists {
    my ($self, $file_name)      = @_;
    
    return 1 if $self->get_dzil_file(qr!$file_name/.+!);
    return 1 if -d $file_name;
    
    return 0; 
}



#================================================================================================================================================================================================================================================
sub get_content_of {
    my ($self, $file_name)      = @_;
    
    my $dzil_file       = $self->get_dzil_file($file_name);
    
    return $dzil_file->content if $dzil_file;
    
    die "Can't find file [$file_name]" unless -e $file_name;
    
    return file($file_name)->slurp; 
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
    
    my $raw_requires_cache = $self->raw_requires_cache;
    
    return $raw_requires_cache->{ $file_name } if defined($raw_requires_cache->{ $file_name });
    
    return $raw_requires_cache->{ $file_name } = $self->get_require_statements($self->get_content_of($file_name));
}


#================================================================================================================================================================================================================================================
sub get_require_statements {
    my ($self, $content)    = @_;
    
    if ($self->quick_n_dirty) {
        my @matches     = ($content =~ m/require \s* \(  ('|")  ([\w\/\.-]*)   \g{-2}   \)/gx);
        
        return \(grep { $_ ne '"' && $_ ne "'" } @matches);
        
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
        
        return JSON->new->decode($res);
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
