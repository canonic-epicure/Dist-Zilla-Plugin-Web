package Dist::Zilla::Plugin::NPM::Bundle;

# ABSTRACT: Bundle the library files into "tasks", using information from Components.JS 

use Moose;

with 'Dist::Zilla::Role::FileGatherer';


use Dist::Zilla::File::FromCode;

use JSON -support_by_pp, -no_export;
use Path::Class;
use IPC::Open2;
use File::ShareDir;

has 'filename' => (
    isa     => 'Str',
    is      => 'rw',
    
    default => 'components.json'
);


has 'lib_dir' => (
    isa     => 'Str',
    is      => 'rw',
    
    default => 'lib'
);


has 'bundleFiles' => (
    is      => 'rw',
    
    default => sub { {} }
);


#================================================================================================================================================================================================================================================
sub gather_files {
    my $self = shift;
    
    return unless -f $self->filename;
    
    my $content = file($self->filename)->slurp;

    #removing // style comments
    $content =~ s!//.*$!!gm;

    #extracting from outermost {} brackets
    $content =~ m/(\{.*\})/s;
    $content = $1;
    
    my $json = JSON->new->relaxed->allow_singlequote->allow_barekey;

    my $components = $json->decode($content);
    
    foreach my $component (keys(%$components)) {
        $self->process_component($components, $component);
    }
}


#================================================================================================================================================================================================================================================
sub process_component {
    my ($self, $components, $component) = @_;
    
    my $componentInfo   = $components->{ $component };
    $componentInfo      = { contains => $componentInfo } if ref $componentInfo eq 'ARRAY';
    
    my $saveAs          = $componentInfo->{ saveAs };
    
    $self->bundleFiles->{ $component } = Dist::Zilla::File::FromCode->new({
        
        name => $saveAs || "foo.js",
        
        code => sub {
            my $bundle_content  = ''; 
            my $is_js           = 1;
            
            foreach my $entry (@{$componentInfo->{ contains }}) {
                $is_js = 0 if $entry =~ /\.css$/;
                
                $bundle_content .= $self->get_entry_content($entry, $component) . ($is_js ? ";\n" : '');
            }
            
            my $minify = $componentInfo->{ minify } || '';
            
            if ($minify eq 'yui') {
                my $yui     = dir( File::ShareDir::dist_dir('Dist-Zilla-Plugin-NPM'), 'minifiers' )->file('yuicompressor-2.4.6.jar') . '';
                my $type    = $is_js ? 'js' : 'css';
                
                my ($child_out, $child_in);
                
                my $pid     = open2($child_out, $child_in, "java -jar $yui --type $type");                
                
                print $child_in $bundle_content;
                
                close($child_in);
                
                waitpid( $pid, 0 );
                my $child_exit_status = $? >> 8;
                
                die "Error during minification with YUI: $child_exit_status" if $child_exit_status;                
                
                $bundle_content = do { local $/; <$child_out> };
                
                close($child_out);
            }
            
            return $bundle_content;
        }
    });
    
    # only store the bundles that has "saveAs"     
    $self->add_file($self->bundleFiles->{ $component }) if $saveAs;
}


#================================================================================================================================================================================================================================================
sub get_entry_content {
    my ($self, $entry, $component) = @_;
    
    if ((ref $entry eq 'HASH') && $entry->{ text }) {
        
        return $entry->{ text };
        
    } elsif ($entry =~ /^\+(.+)/) {
        
        my $bundleFile  = $self->bundleFiles->{ $1 };
        
        die "Reference to non-existend bundle [$1] from [$component]" if !$bundleFile;
        
        return $bundleFile->content;
    
    } elsif ($entry !~ /\// && $entry !~ /\.js$/ && $entry !~ /\.css$/) {
        
        my $file_name = $self->entry_to_filename($entry);
        
        die "Can't find file [$file_name] in [$component]" if !-e $file_name;
        
        return file($file_name)->slurp;
        
    } else {
        return file($entry)->slurp;
    } 
}

#================================================================================================================================================================================================================================================
sub entry_to_filename {
	my ($self, $entry) = @_;
	
    my @dirs = split /\./, $entry;
    $dirs[-1] .= '.js';
	
	return file($self->lib_dir, @dirs);
}


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;


=head1 SYNOPSIS

In your F<dist.ini>:

    [JSAN::Bundle]

In your F<Components.JS>:

    COMPONENTS = {
        
        "Core" : [
            "KiokuJS.Reference",
            
            "KiokuJS.Exception",
            "KiokuJS.Exception.Network",
            "KiokuJS.Exception.Format",
            "KiokuJS.Exception.Overwrite",
            "KiokuJS.Exception.Update",
            "KiokuJS.Exception.Remove",
            "KiokuJS.Exception.LookUp",
            "KiokuJS.Exception.Conflict"
        ],
        
        
        "Prereq" : [
            "=/home/cleverguy/js/some/file.js",
            "jsan:Task.Joose.Core",
            "jsan:Task.JooseX.Attribute.Bootstrap",
            
            "jsan:Task.JooseX.Namespace.Depended.NodeJS",
            
            "jsan:Task.JooseX.CPS.All",
            "jsan:Data.UUID",
            "jsan:Data.Visitor"
        ],
        
        
        "All" : [
            "+Core",
            "+Prereq"
        ]
    } 
    


=head1 DESCRIPTION

This plugins concatenates several source files into single bundle using the information from Components.JS file.

This files contains a simple JavaScript assignment (to allow inclusion via <script> tag) of the JSON structure.

First level entries of the JSON structure defines a bundles. Each bundle is an array of entries. 

Entry, starting with the "=" prefix denotes the file from the filesystem. 

Entry, starting with the "jsan:" prefix denotes the module from the jsan library. See L<Module::Build::JSAN::Installable>.

Entry, starting with the "+" prefix denotes the content of another bundle.

All other entries denotes the javascript files from the "lib" directory. For example entry "KiokuJS.Reference" will be fetched
as the content of the file "lib/KiokuJS/Reference.js"

All bundles are stored as "lib/Task/Distribution/Name/BundleName.js", assuming the name of the distrubution is "Distribution-Name"
and name of bundle - "BundleName". During release, all bundles also gets added to the root of distribution as
"task-distribution-name-bundlename.js". To enable the latter feature for regular builds add the `roots_only_for_release = 0` config option  

=cut
