#!/usr/bin/perl
# Common Configuration Parser version 0.1 ALPHA (!)
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
# $Id$
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

my $Version = "0.1 ALPHA";		# Version number

# Declare variables
my (
	$Type,		$OldFile,	$NewFile,
	$TemplateFile,	$Verbose,	$VeryVerbose,
	$OutputFile,
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
	print "\nUsage: $Command [OPTIONAL OPTIONS] --type [TYPE] --template [path] --oldfile [path] --newfile [path]\n\n";
	print "Mandatory options:\n";
	PrintHelp("-t", "--type", "Select the configuration filetype, see the documentation for info");
	PrintHelp("-p", "--template", "Define the template configuration file");
	PrintHelp("-o", "--oldfile", "Define the old configuration file");
	PrintHelp("-n", "--newfile", "Define the new configuration file");
	print "\nOptional options:\n";
	PrintHelp("", "--outputfile", "Output to this file instead of oldfile");
	PrintHelp("-h", "--help", "Display this help screen");
	PrintHelp("", "--version", "Display the version number");
	PrintHelp("-v", "--verbose", "Be verbose");
	PrintHelp("", "--veryverbose", "Be very verbose, useful for debugging. Implies -v");
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
		s/#.*//;                # Strip comments
		s/:.*//;		# Strip : comments
		s/;.*//;		# Strip ; comments
		s/\[.*//;		# We can't do anything with section headers
		s/^\s+//;               # Strip leading whitespace
		s/\s+$//;               # Strip trailing whitespace
		s/\"//g;                # Strip quotes
		s/\'//g;                # Ditto
		next unless length;	# Empty?
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
	printvv "Opening $OutputFile for writing\n";
	open(OUTPUTFILE, ">$OutputFile");
	foreach (@Template) {
			print OUTPUTFILE "$_";
	}
	close(OUTPUTFILE);
	printvv "Okay, written\n"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Commandline parameter parsing
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Help and exit 0 unless @ARGV;
GetOptions (
	'version' => sub { Version; exit 0; },
	'h|help' => sub { Help; exit 0; },
	'outputfile=s' => \$OutputFile,
	'o|oldfile=s' => \$OldFile,
	'n|newfile=s' => \$NewFile,
	'p|template=s' => \$TemplateFile,
	't|type=s' => sub { print "--type ignored, not implemented yet\n"; },
	'v|verbose' => \$Verbose,
	'veryverbose' => sub { $Verbose = 1;
		$VeryVerbose = 1;
	},
) or Help and die "\n";

die "No --oldfile supplied\n" unless $OldFile;
die "No --newfile supplied\n" unless $NewFile;
die "No --template supplied\n" unless $TemplateFile;
die "\"$OldFile\" and \"$NewFile\" is the same file!\n" if $NewFile eq $OldFile;

$OutputFile = $OldFile unless $OutputFile;

printvv "Okay, beginning.\n";
printnv "Merging changes between \"$OldFile\" and \"$NewFile\"...";

LoadFile("$NewFile");
LoadFile("$OldFile");
OutputFile;
printnv "done"
