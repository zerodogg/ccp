#!/usr/bin/perl
# Common Configuration Parser version 0.2.1
# $Id$
# Copyright (C) Eskild Hustvedt 2005, 2006
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
# The modules we want to use
use strict;				# Make my coding strict
use warnings;				# Warn me!
use Fatal qw/ open /;			# So I don't have to type "or die" too much :)
use File::Basename;			# Needed to find out our directory and name
use Cwd;				# Needed for getcwd
use Getopt::Long;			# Commandline parsing
use File::Copy;				# We need to copy files (backup)
# Allow bundling of options with GeteOpt
Getopt::Long::Configure ("bundling", 'prefix_pattern=(--|-)');

my $Version = "0.2.1-CVS";		# Version number

# Declare variables
my (
	$Type,		$OldFile,	$NewFile,
	$TemplateFile,	$Verbose,	$VeryVerbose,
	$OutputFile,	$IfExist,	$WriteTemplateTo,
	$WriteBackup,	$NoOrphans,	$DeleteNewfile,
	$ParanoidMode,
);	# Scalars
my (
	%Config,	
);	# Hashes
my (
	@Template,	@IgnoreOptions,	
);	# Arrays

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Verbosity functions
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Non-verbose print
sub printnv {
	print "$_[0]" unless $Verbose;
}

# Verbose print
sub printv {
	print "$_[0]" if $Verbose;
}

# Very verbose print
sub printvv {
	print " $_[0]" if $VeryVerbose;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions for loading the files
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub LoadFile {
	die "LoadFile got a nonexistant file supplied!" unless -e $_[0];
	my %ParanoiaHash if $ParanoidMode;
	printv "Loading and parsing \"$_[0]\"\n";
	open(FILE, "<$_[0]");
	# Parse and put into the hash
	foreach (<FILE>) {
		chomp;
		s/^\s+//;               # Strip leading whitespace
		s/\s+$//;               # Strip trailing whitespace
		next if m#^<.*#;	# Skip lines beginning with < (tags, php config files - this type doesn't support XML configs anyway)
		next if m#^\?>.*#;	# Skip lines beginning with ?> (php closing tag)
		next if /^(#|\/\*|:|;|\*)/; # Skip comments
		next if /^\[/;		# We can't do anything with section headers so we skip them
		s/;$//;			# Strip trailing ; 
		s/^\$//;		# Strip leading $
		next unless length;	# Empty?
		next unless /=/;	# No "=" in the line means nothing for us to do
		my ($var, $value) = split(/\s*=\s*/, $_, 2);    # Set the variables
		printvv "Read key value pair: \"$var\" = \"$value\"\n";
		$Config{$var} = $value;
		$ParanoiaHash{$var}++ if $ParanoidMode;
	}
	close(FILE);
	# If we're not in ParanoidMode then we're all done
	return(1) unless $ParanoidMode;
	printvv "Running paranoia test on $_[0]\n";
	foreach(sort(keys(%ParanoiaHash))) {
		print "PARANOIA WARNING: $_ was seen more than once! (Seen $ParanoiaHash{$_} times)\n" if $ParanoiaHash{$_} gt 1;
	}
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions to generate a template
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub GenerateTemplate {
	die "\$NewFile not set" unless $NewFile;
	printv "Generating template from $NewFile...\n";
	open(NEWFILE, "<$NewFile");
	@Template = <NEWFILE>;
	close(NEWFILE);
	foreach (@Template) {
		my $EOL = "";
		next if $_ =~ /^\s*[#|<|\?>|\*|\/\*|;|:|@|\[]/;	# Check for comments and other funstuff that we don't handle
		next if $_ =~ /^\s*$/;				# If the line is empty, then skip ahead
		next unless $_ =~ /=/;				# If there is no '=' in the line we just skip ahead
		chomp;						# Remove newlines
		my $Name = $_;					# Copy $_'s contents to $Name 
		# Start stripping junk from the line, to figure out the name of the variable
		$Name =~ s/(.+)\s*=\s*.*/$1/;
		$Name =~ s/\s*(\$)//;
		$Name =~ s/\s+//g;
		next unless $Name;
		# Don't do anything if Name exists in %IgnoreOptions
		$_ = "$_\n" and next if grep $_ eq $Name, @IgnoreOptions; 
		# Okay, time to find out the values
		my $LineContents = $_;				# Copy $_'s contents to $LineContents
		$LineContents =~ s/.*\Q$Name\E\s*=\s*//;	# Remove the first part of the line
		# Check if the line ends with ; - in which case we need to append that later
		if ($LineContents =~ /;\s*$/) {
			$EOL = ';';
		}
		# $LineContents is now the part of $_ we want to replace
		s/(.*=\s*)\Q$LineContents\E/${1}{CCP::CONFIG::$Name}$EOL\n/;
		printvv "Read setting \"$Name\"\n";
	}
}

# This function just outputs the template to a file instead of
# actually merging files.
sub WriteTemplate {
	# First, verify $WriteTemplateTo
	if ( -e $WriteTemplateTo ) {
		die "I can't write to \"$WriteTemplateTo\"\n" unless -w $WriteTemplateTo;
	} else {
		my $TestBase = dirname($WriteTemplateTo);
		if ($WriteTemplateTo eq $TestBase) {
			$TestBase = "./";
		}
		die "I can't write to the directory \"$TestBase\"\n" unless -w $TestBase;
	}
	printnv "Creating template from \"$NewFile\"... ";
	# Now, create the template
	GenerateTemplate;
	# Now, write the template
	printv "Writing template to \"$WriteTemplateTo\"\n";
	open(TEMPLATEOUT, ">$WriteTemplateTo");
	foreach (@Template) {
		print TEMPLATEOUT $_;
	}
	close(TEMPLATEOUT);
	printnv "Done\n";
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions for outputting the file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub OutputFile {
	die "\$OutputFile not set" unless $OutputFile;
	my $OrphansFound;
	# Find out which method to use for the template:
	if ($TemplateFile) {	# Use the already generated $TemplateFile
		printv "Loading template ($TemplateFile)\n";
		printvv "Opening $TemplateFile\n";
		open(TEMPLATE, "<$TemplateFile");
		@Template = <TEMPLATE>;
		close(TEMPLATE);
	} else {		# Use a template auto-generated on-the-fly
		GenerateTemplate;
	}
	printv "Merging settings into $OutputFile\n";
	# Merge the settings into the template
	foreach my $key (keys %Config) {
		printvv "Exchanging {CCP::CONFIG::$key} in template with $Config{$key}\n";
		foreach (@Template) {
			if (s/{CCP::CONFIG::\Q$key\E}/$Config{$key}/) {
				# If we replaced something then we delete the key.
				# A key should never be used more than once, you'll need an ini-type for that to work.
				delete($Config{$key});
				last;
			}
		}
	}
	# Remove options that are in the template but not in any of the other files.
	# Shouldn't happen with auto-generated templates - if it does then it's a bug.
	foreach (@Template) {
		if (s/{CCP::CONFIG::(.+)}//) {
			if ($TemplateFile) {
				printv "Warning: Option found in template but not in oldfile or newfile: $1\n";
			} else {
				# BUG!
				print "\nWARNING: Option found in template but not in oldfile or newfile: $1\n";
				print "This reflects a bug in CCP! Please report it to http://ccp.nongnu.org/\n";
				# Force a backup to be written even if it isn't requested
				unless ($WriteBackup) {
					print "Forcing CCP to write a backup file - but still continuing\n";
					$WriteBackup = "$OutputFile.ccpbackup";
				}
			}
		}
	}
	# If we're verbose (or if the user supplied --noorphans) then test for orphaned keys
	if ($Verbose or $NoOrphans) {
		foreach my $key (keys %Config) {
			unless (grep $_ eq $key, @IgnoreOptions) {
				if ($TemplateFile) {
					printv "Warning: Orphaned option (found in newfile or oldfile but not in the template): $key\n";
				} else {
					printv "Warning: Orphaned option (found in oldfile but not in the newfile): $key\n";
				}
				$OrphansFound = 1;
			}
		}
		if ($OrphansFound and $NoOrphans) {
			printnv "failed - orphaned options detected.\n";
			printv "Exiting as requested\n";
			exit 0;
		}
	}
	# Backup
	if ($WriteBackup) {
		if (-e $OutputFile) {
			copy($OutputFile, $WriteBackup);
			printv "Backed up \"$OutputFile\" to \"$WriteBackup\"\n";
		} else {
			printvv "I won't back up \"$OutputFile\", it doesn't exist so there's nothing to backup.\n";
		}
	}
	# Write it out
	open(OUTPUTFILE, ">$OutputFile");
	printv "Writing $OutputFile\n";
	foreach (@Template) {
			print OUTPUTFILE "$_";
	}
	close(OUTPUTFILE);
	printvv "Okay, written\n";
	# Check if we should delete $NewFile
	if ($DeleteNewfile) {
		if (-w $NewFile) {
			printv "Deleting $NewFile\n";
			unlink($NewFile) or printv "FAILED!: $!";
		} else {
			printvv "User requested that I should delete \"$NewFile\" but I can't write to it, ignoring request.\n";
		}
	}
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Help function declerations
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The function that actually outputs the help
# This is just because I'm too lazy to type the printf every time
# and this function makes it more practical.
# Syntax is simply: PrintHelp("shortoption", "longoption", "description")
sub PrintHelp ($$$) {
        printf "%-4s %-16s %s\n", "$_[0]", "$_[1]", "$_[2]";
}

sub Version {
	print "Common Configuration Parser version $Version\n";
}

sub Help {
	my $Command = basename($0);
	print "\n";
	Version;
	print "\nUsage: $Command [OPTIONAL OPTIONS] --oldfile [path] --newfile [path]\n\n";
	print "Mandatory options:\n";
	PrintHelp("-o", "--oldfile", "Define the old configuration file");
	PrintHelp("-n", "--newfile", "Define the new configuration file");
	print "\nOptional options:\n";
	PrintHelp("-b", "--backup", "Backup --oldfile (or --outputfile) to filename.ccpbackup");
	PrintHelp("","", "(or to the file supplied) before writing the upgraded config file");
	PrintHelp("-d", "--delete", "Delete --newfile if it is writeable by me and the configuration");
	PrintHelp("", "", "file is upgraded successfully");
	PrintHelp("-i", "--ifexists", "Exit silently if --newfile doesn't exist");
	PrintHelp("-r", "--noorphans", "Exit if orphaned options are detected");
	PrintHelp("", "", "(see manpage for more information");
	PrintHelp("-g", "--ignoreopt", "Keep the setting from --newfile for this option");
	PrintHelp("", "", "(can be supplied more than once)");
	PrintHelp("-f", "--outputfile", "Output to this file instead of oldfile");
	PrintHelp("-h", "--help", "Display this help screen");
	PrintHelp("", "--version", "Display the version number");
	PrintHelp("-v", "--verbose", "Be verbose");
	PrintHelp("-V", "--veryverbose", "Be very verbose, useful for testing. Implies -v");
	PrintHelp("-P", "--paranoid", "Run paranoid tests (see the manpage). Implies -v");
	PrintHelp("", "--writetemplate", "Write template to the file supplied and exit");
	PrintHelp("", "", "(doesn't do any merging and --oldfile isn't needed)");
	PrintHelp("-p", "--template", "Use the manually created template supplied");
	PrintHelp("", "", "(don't generate template on-the-fly)");
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Commandline parameter parsing
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Help and exit 0 unless @ARGV;
GetOptions (
	'version' => sub { Version; exit 0; },
	'h|help' => sub { Help; exit 0; },
	'f|outputfile=s' => \$OutputFile,
	'o|oldfile=s' => \$OldFile,
	'n|newfile=s' => \$NewFile,
	'p|template=s' => \$TemplateFile,
	't|type=s' => sub { die "--type isn't implemented in this version of CCP\n"},
	'v|verbose' => \$Verbose,
	'V|veryverbose' => sub { $Verbose = 1;
		$VeryVerbose = 1;
	},
	'i|ifexist' => \$IfExist,
	'writetemplate=s' => \$WriteTemplateTo,
	'b|backup:s' => \$WriteBackup,
	'r|noorphans' => \$NoOrphans,
	'd|delete' => \$DeleteNewfile,
	'g|ignoreopt=s' => \@IgnoreOptions,
	'P|paranoid' => \$ParanoidMode,
) or die "Run ", basename($0), " --help for more information\n";
# We need --newfile for everything
die "No --newfile supplied\n" unless $NewFile;

# Set the verbosity settings according to environment variables
if (defined($ENV{CCP_VERBOSE}) and $ENV{CCP_VERBOSE} eq 1) {
	$Verbose = 1;
}
if (defined($ENV{CCP_VERYVERBOSE}) and $ENV{CCP_VERYVERBOSE} eq 1) {
	$VeryVerbose = 1;
	$Verbose = 1;
}
# Set paranoia settings
if (defined($ENV{CCP_PARANOID}) and $ENV{CCP_PARANOID} eq 1) {
	$ParanoidMode = 1;
}
if ($ParanoidMode) {
	print "Paranoid mode is on!\n";
#	$VeryVerbose = 1;
	$Verbose = 1;
}

# Verify existance of $NewFile and exit as requested if needed
if (!-e $NewFile) {
	exit 0 if $IfExist;
	die "$NewFile does not exist\n";
}

# Verify newfile
die "$NewFile does not exist\n" unless -e $NewFile;
die "$NewFile is not a normal file\n" unless -f $NewFile;
die "$NewFile is not readable by me\n" unless -r $NewFile;


# If $WriteTemplateTo is set to something then we should just run WriteTemplate
# and then exit
if ($WriteTemplateTo) {
	WriteTemplate;
	exit 0;
}

# Verify oldfile
die "No --oldfile supplied\n" unless $OldFile;
die "$OldFile does not exist\n" unless -e $OldFile;
die "$OldFile is not a normal file\n" unless -f $OldFile;
die "$OldFile is not readable by me\n" unless -r $OldFile;

die "\"$OldFile\" and \"$NewFile\" is the same file!\n" if $NewFile eq $OldFile;

# Test the template file if supplied
if ($TemplateFile) {
	die "$TemplateFile does not exist\n" unless -e $TemplateFile;
	die "$TemplateFile is not a normal file\n" unless -f $TemplateFile;
	die "$TemplateFile is not readable by me\n" unless -r $TemplateFile;
}

# Check if we got --outputfile, if we didn't then use --oldfile
unless ($OutputFile) {
	printvv "Using --oldfile ($OldFile) as --outputfile\n";
	$OutputFile = $OldFile;
}

# Verify that we can write to $OutputFile
if ( -e $OutputFile ) {
	die "I can't write to \"$OutputFile\"\n" unless -w $OutputFile;
} else {
	my $TestBase = dirname($OutputFile);
	if ($OutputFile eq $TestBase) {
		$TestBase = "./";
	}
	die "I can't write to the directory \"$TestBase\"\n" unless -w $TestBase;
}

# Test if we where suppose to write a backup
if (defined($WriteBackup)) {
	# We where, so let's see if the user has already told us where to write it to
	if ($WriteBackup eq "" ) {	# User didn't tell us
		$WriteBackup = "$OutputFile.ccpbackup";
		printvv "Using \"$WriteBackup\" as backup target\n";
	}
	# Make sure we can write to the file
	if (-e $WriteBackup) {
		die "I can't write the backup to \"$WriteBackup\"\n" unless -w $WriteBackup;
	} else {
		my $TestBase = dirname($WriteBackup);
		if ($WriteBackup eq $TestBase) {
			$TestBase = "./";
		}
		die "I can't write to the directory \"$TestBase\"\n" unless -w $TestBase;
	}
}

printvv "Okay, beginning.\n";
unless ($OutputFile eq $OldFile) {
	printnv "Merging changes between \"$OldFile\" and \"$NewFile\" into \"$OutputFile\"...";
} else {
	printnv "Merging changes between \"$OldFile\" and \"$NewFile\"...";
}

# Load settings from the files
LoadFile($NewFile);
LoadFile($OldFile);
# Output the new file
OutputFile;
printnv "done\n";
