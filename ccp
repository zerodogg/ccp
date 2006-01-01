#!/usr/bin/perl
# Common Configuration Parser version 0.1 
# $Id$
# Copyright (C) Eskild Hustvedt 2005
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
package CCP;
# The modules we want to use
use strict;                             # Make my coding strict
use warnings;                           # Warn me!
use Fatal qw/ open chdir mkdir /;       # So I don't have to type "or die" too much :)
use File::Basename;                     # Needed to find out our directory and name
use Cwd;                                # Needed for getcwd
use Getopt::Long;                       # Commandline parsing
use File::Copy;                         # We need to copy files!
# Allow bundling of options with GeteOpt
Getopt::Long::Configure ("bundling", 'prefix_pattern=(--|-)');

my $Version = "0.1-CVS";		# Version number

# Declare variables
my (
	$Type,		$OldFile,	$NewFile,
	$TemplateFile,	$Verbose,	$VeryVerbose,
	$OutputFile,	$IfExist,	$ConfigQuoting,
	$GenTemplate,
);	# Scalars
my (
	%Config,
);	# Hashes

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Help function declerations
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The function that actually outputs the help
# This is just because I'm too lazy to type the printf every time
# and this function makes it more practical.
# Syntax is simply: PrintHelp("shortoption", "longoption", "description")
sub PrintHelp {
        printf "%-4s %-16s %s\n", "$_[0]", "$_[1]", "$_[2]";
}

sub Version {
	print "Common Configuration Parser version $Version\n";
}

sub Help {
	my $Command = basename($0);
	print "\n";
	Version;
#	print "\nUsage: $Command [OPTIONAL OPTIONS] --type [TYPE] --template [path] --oldfile [path] --newfile [path]\n\n";
	print "\nUsage: $Command [OPTIONAL OPTIONS] --template [path] --oldfile [path] --newfile [path]\n\n";
	print "Mandatory options:\n";
#	PrintHelp("-t", "--type", "Select the configuration filetype, see the documentation for info");
	PrintHelp("-p", "--template", "Define the template configuration file");
	PrintHelp("-o", "--oldfile", "Define the old configuration file");
	PrintHelp("-n", "--newfile", "Define the new configuration file");
	print "\nOptional options:\n";
	PrintHelp("-i", "--ifexists", "Exit silently if --newfile doesn't exist");
	PrintHelp("-f", "--outputfile", "Output to this file instead of oldfile");
	PrintHelp("-h", "--help", "Display this help screen");
	PrintHelp("", "--version", "Display the version number");
	PrintHelp("-v", "--verbose", "Be verbose");
	PrintHelp("-V", "--veryverbose", "Be very verbose, useful for testing. Implies -v");
}

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
	printv "Loading and parsing \"$_[0]\"\n";
	open(FILE, "<$_[0]");
	# Parse and put into the hash
	foreach (<FILE>) {
		chomp;
		s/#.*//;                # Strip "#" comments
		s#^/\*.*##;		# Strip "/*" comments
		s#^\s*\*.*##;		# Strip "whitespace *" comments
		s#^\s*\*/.*##;		# Strip "whitespace */" comment endings
		s#^<.*##;		# Strip lines beginning with < (tags, php config files - this type doesn't support XML configs anyway)
		s#^\?>.*##;		# Strip lines beginning with ?> (php closing tag)
		s/^\s+//;               # Strip leading whitespace
		s/\s+$//;               # Strip trailing whitespace
		s/:.*//;		# Strip : comments
		s/;.*//;		# Strip ; comments
		s/\[.*//;		# We can't do anything with section headers so we skip them
		s/;$//;			# Strip trailing ; (FIXME: Dump?)
		s/^\$//;		# Strip leading $
					# TODO: Quote stripping shouldn't be this crude, strip them after key-value has been read and it
					# matches a set case.
		s/\"//g;                # Strip quotes (quoting is defined in the template)
		s/\'//g;                # Ditto
		next unless length;	# Empty?
		next unless /=/;	# No "=" in the line means nothing for us to do
		my ($var, $value) = split(/\s*=\s*/, $_, 2);    # Set the variables
		printvv "Read key value pair: \"$var\" = \"$value\"\n";
		$Config{$var} = $value;
	}
	close(FILE);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions for outputting the file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub OutputFile {
	die "\$OutputFile not set" unless $OutputFile;
	die "\$TemplateFile not set" unless $TemplateFile;
	printv "Loading template ($TemplateFile)\n";
	printvv "Opening $TemplateFile\n";
	open(TEMPLATE, "<$TemplateFile");
	my @Template = <TEMPLATE>;
	close(TEMPLATE);
	printv "Merging settings into $OutputFile\n";
	foreach my $key (keys %Config) {
		printvv "Exchanging {CCP::CONFIG::$key} in template with $Config{$key}\n";
		foreach (@Template) {
			s/{CCP::CONFIG::$key}/$Config{$key}/;
		}
	}
	foreach (@Template) {
		if (s/{CCP::CONFIG::(.+)}//) {
			printv "Warning: Option found in template but not in old or newfile: $1\n";
		}
	}
	open(OUTPUTFILE, ">$OutputFile");
	printv "Writing $OutputFile\n";
	foreach (@Template) {
			print OUTPUTFILE "$_";
	}
	close(OUTPUTFILE);
	printvv "Okay, written\n"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions to generate a template
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub GenerateTemplate {
	die "\$NewFile not set" unless $NewFile;
	printv "Generating template from $NewFile...\n";
	printvv "NOTICE: This isn't implemented fully yet, it'll just finish then exit.\n";
	printvv "Warning: Template generating may not work !\n";
	printvv "Report problems to https://savannah.nongnu.org/bugs/?group=ccp\n";
	printvv "\n";
	open(NEWFILE, "<$NewFile");
	my @NewFile = <NEWFILE>;
	close(NEWFILE);
	foreach (@NewFile) {
		my ( $LineQuotes,	$EOL );
		next if $_ =~ /^\s*[#|<|\?>|\*|\/\*|@]/;	# Checck for comments and other funstuff that we don't handle
		next if $_ =~ /^\s*$/;				# If the line is empty, then skip ahead
		next unless $_ =~ /=/;				# If there is no '=' in the line we just skip ahead
		my $Name = $_;	# Copy $_'s contents to $Line for parsing
		chomp($Name);
		# Start stripping junk from the line, to figure out the name of the variable
		$Name =~ s/(.+)\s*=\s*.*/$1/;
		$Name =~ s/\s*(\$)//;
		$Name =~ s/\s+//;
		next unless $Name;
		# Okay, we've got a name, now we need to try to figure out which quotes to use
		# If $ConfigQuoting is true then there is no need because the user has told us
		unless ($ConfigQuoting) {
			# " quotes?
			if (/.*".*".*/) {
				$LineQuotes = "\"";
			} # ' quotes ?
			elsif (/.*'.*'.*/) {
				$LineQuotes = "'";
			} # Hrm, okay, no quotes
			else {
				$LineQuotes = "";
			}
		} else {
			$LineQuotes = $ConfigQuoting;
		}
		# Quoting found, now lets find out the values
		my $LineContents = $_;
		$LineContents =~ s/.*\Q$Name\E\s*=\s*//;	# Remove the first part of the line
		# Check if the line ends with ; - in which case we need to append that later
		if ($LineContents =~ /;\s*$/) {
			$EOL = ';';
		}
		# Check for quotes, in theory it should begin and end with quotes for us to add it
		unless ($LineContents =~ /^$LineQuotes.*$LineQuotes;?/) {
			# Drop LineQuotes
			$LineQuotes = "";
		}
		# $LineContents is now the part of $_ we want to replace
		s/\Q$LineContents\E/${LineQuotes}{CCP::CONFIG::$Name}$LineQuotes$EOL\n/;
#		printvv "Found line named $Name\n";
		chomp;
		chomp($LineContents);
		printvv "$_ || $LineContents || $Name\n";
	}
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
	't|type=s' => sub { print "--type ignored, not implemented yet\n"; },
	'v|verbose' => \$Verbose,
	'V|veryverbose' => sub { $Verbose = 1;
		$VeryVerbose = 1;
	},
	'i|ifexist' => \$IfExist,
	'gentemplate' => \$GenTemplate,
) or Help and die "\n";

# Verify options
die "No --oldfile supplied\n" unless $OldFile;
die "No --newfile supplied\n" unless $NewFile;
if ($GenTemplate) {
	$Verbose = 1;
	$VeryVerbose = 1;
	GenerateTemplate;
	exit 0;
}
die "No --template supplied\n" unless $TemplateFile;
die "\"$OldFile\" and \"$NewFile\" is the same file!\n" if $NewFile eq $OldFile;
# Verify existance if $NewFile and exit as requested if needed
if (!-e $NewFile) {
	exit 0 if $IfExist;
	die "$NewFile does not exist\n";
}
# Verify file existance and validity
die "$OldFile does not exist\n" unless -e $OldFile;
die "$NewFile does not exist\n" unless -e $NewFile;
die "$TemplateFile does not exist\n" unless -e $TemplateFile;
die "$OldFile is not a normal file\n" unless -f $OldFile;
die "$NewFile is not a normal file\n" unless -f $NewFile;
die "$TemplateFile is not a normal file\n" unless -f $TemplateFile;
die "$OldFile is not readable by me\n" unless -r $OldFile;
die "$NewFile is not readable by me\n" unless -r $NewFile;
die "$TemplateFile is not readable by me\n" unless -r $TemplateFile;

unless ($OutputFile) {
	printvv "Using --oldfile ($OldFile) as --outputfile\n";
	$OutputFile = $OldFile;
}


printvv "Okay, beginning.\n";
printnv "Merging changes between \"$OldFile\" and \"$NewFile\"...";

LoadFile("$NewFile");
LoadFile("$OldFile");
OutputFile;
printnv "done\n";
