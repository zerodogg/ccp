#!/usr/bin/perl
# Common Configuration Parser
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

# The modules we want to use
use strict;				# Make my coding strict
use warnings;				# Warn me!
use Fatal qw/ open /;			# So I don't have to type "or die" too much :)
use File::Basename;			# Needed to find out our directory and name
use Cwd;				# Needed for getcwd
use Getopt::Long;			# Commandline parsing
use File::Copy;				# We need to copy files (backup)
use Data::Dumper; #FIXME
# Allow bundling of options with GeteOpt
Getopt::Long::Configure ("bundling", 'prefix_pattern=(--|-)');

my $Version = "0.4.0";			# Version number
my $CVSRevision = '$Id$';# CVS revision

# Declare variables
our (
	$Type,		$OldFile,	$NewFile,
	$TemplateFile,	$Verbose,	$VeryVerbose,
	$OutputFile,	$IfExist,	$WriteTemplateTo,
	$WriteBackup,	$DeleteNewfile,
	$DebugMode,	$OutputBug,
	$ConfType,
	$CCP_ConfTypeVer
);	# Scalars
our (
	%Config,	
);	# Hashes
our (
	@Template,	@IgnoreOptions,	
);	# Arrays

# This hash contains the settings that the user can modify.
# It's used as an alternative to havving one commandline options for
# each option so that we don't have a flood of commandline options available.
our %UserSettings = (
	NoOrphans => 0,
	NoTemplateUncommenting => 0,
	ParanoidMode => 0,
);
# TODO: Write --set which sets the option to a true (1) value.
# FIXME: Deprecate --nooprhans --no-uncomment and --paranoid

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

# Debugging print
sub printd {
	print "DEBUG: $_[0]" if $DebugMode;
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Subroutine that loads the type
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub LoadConfigType {
	my $Loaded;
	$ConfType = "keyvalue" unless $ConfType;
	for (dirname(Cwd::realpath($0)), "/usr/share/ccp", "/usr/local/ccp" ) {
		if ( -d "$_/conftypes" and -r "$_/conftypes/$ConfType.pl") {
			unless (my $ConfTypeDo = do("$_/conftypes/$ConfType.pl")) {
				die "Couldn't parse conftype \"$ConfType\" at \"$_/conftypes/$ConfType.pl\": $@" if $@;
				die "Couldn't do() conftype \"$ConfType\" at \"$_/conftypes/$ConfType.pl\": $!"    unless defined $ConfTypeDo;
				die "Couldn't load conftype \"$ConfType\" at \"$_/conftypes/$ConfType.pl\"" unless $ConfTypeDo;
			}
			$Loaded = 1;
			printd "Config type: $ConfType - $_/conftypes/$ConfType.pl\n";
			last;
		}
	}
	unless ($Loaded) {
		die "Unrecognized configuration type: $ConfType\n";
	}
	if ($CCP_ConfTypeVer != 1) {
		warn "CCP: $ConfType is for a later version of CCP and may not work!\n"
	}
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Debugging function
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Function that creates a debugging file (self-contained)
sub OutputDebug {
	die "Unable to write ./ccpdebug\n" unless -w "./";
	# Load the files into arrays
	print "Loading $NewFile\n";
	open(FILE, "<$NewFile");
	my @NewFile = <FILE>;
	close(FILE);
	print "Loading $OldFile\n";
	open(FILE, "<$OldFile");
	my @OldFile = <FILE>;
	close(FILE);
	print "Okay, writing ./ccpdebug\n";

	# Create ./ccpdebug (a shell script)
	open(DEBUG_OUT, ">./ccpdebug");
	print DEBUG_OUT "#!/bin/bash\n\n# Automatically generated debugging file for CCP\n";
	print DEBUG_OUT "# Give this to the developer to assist him or her in debugging your problem\n\n";
	# Dump %UserSettings content to the file
	print DEBUG_OUT "# Dump of hash \%UserSettings:\n";
	foreach (keys %UserSettings) {
		print DEBUG_OUT "# \$UserSettings{$_} = $UserSettings{$_}\n";
	}
	# Output initial info
	print DEBUG_OUT "\necho 'Common Configuration Parser debugging script revision 1'\n";
	print DEBUG_OUT "echo 'Generated by CCP $Version'\necho '$CVSRevision'\n";
	print DEBUG_OUT "echo 'NewFile was $NewFile'\necho 'OldFile was $OldFile'\n";
	print DEBUG_OUT "echo 'TemplateFile was $TemplateFile'\n" if $TemplateFile;
	print DEBUG_OUT "\n# --- BEGIN OLDFILE ---\n";
	print DEBUG_OUT "cat << __COMMON_CONFIGURATION_PARSER__EOF > oldfile.ccp_debug\n";
	foreach(@OldFile) {
		s/\$/\\\$/g;		# Escape \$
		print DEBUG_OUT "$_";
	}
	print DEBUG_OUT "__COMMON_CONFIGURATION_PARSER__EOF\n";
	print DEBUG_OUT "# --- END OLDFILE ---\n\n";
	print DEBUG_OUT "echo 'Wrote ./oldfile.ccp_debug'\n\n";
	print DEBUG_OUT "# --- BEGIN NEWFILE ---\n";
	print DEBUG_OUT "cat << __COMMON_CONFIGURATION_PARSER__EOF > newfile.ccp_debug\n";
	foreach(@NewFile) {
		s/\$/\\\$/g;		# Escape \$
		print DEBUG_OUT "$_";
	}
	print DEBUG_OUT "__COMMON_CONFIGURATION_PARSER__EOF\n";
	print DEBUG_OUT "# --- END NEWFILE ---\n\n";
	print DEBUG_OUT "echo 'Wrote ./newfile.ccp_debug'\n\n";
	print DEBUG_OUT "# --- BEGIN TEMPLATEFILE ---\n";
	# We include an external template or the internally generated one
	if ($TemplateFile) {
		print DEBUG_OUT "echo 'Template type: manual'\n";
		open(FILE, "<$TemplateFile");
		print DEBUG_OUT "cat << __COMMON_CONFIGURATION_PARSER__EOF > templatefile.ccp_debug\n";
		my @TemplateFile = <FILE>;
		close(FILE);
		foreach(@TemplateFile) {
			s/\$/\\\$/g;	# Escape \$
			print DEBUG_OUT "$_";
		}
	} else { # Include our autogenerated template
		print DEBUG_OUT "echo 'Template type: automatic'\n";
		#CCP::CT::GenerateTemplate();
		GenerateTemplate();
		print DEBUG_OUT "cat << __COMMON_CONFIGURATION_PARSER__EOF > templatefile.ccp_debug\n";
		foreach(@Template) {
			s/\$/\\\$/g;	# Escape \$
			print DEBUG_OUT "$_";
		}
	}
	print DEBUG_OUT "__COMMON_CONFIGURATION_PARSER__EOF\n";
	print DEBUG_OUT "# --- END TEMPLATEFILE ---\n\n";
	print DEBUG_OUT "echo 'Wrote ./templatefile.ccp_debug'\n\n";
	print DEBUG_OUT "# END OF DEBUGGING SCRIPT\n";
	print "Done, debugging information written to ./ccpdebug\n";
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

sub FullVersion {
	Version;
	print "(CVS Revision $CVSRevision)\n";
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
#	PrintHelp("-r", "--noorphans", "Exit if orphaned options are detected");	# TODO: Deprecated
#	PrintHelp("", "", "(see manpage for more information");
#	PrintHelp("-u", "--no-uncomment", "Don't uncomment options automatically in");	# TODO: Deprecated
#	PrintHelp("","", "autogenerated templates.");
	PrintHelp("-g", "--ignoreopt", "Keep the setting from --newfile for this option");
	PrintHelp("", "", "(can be supplied more than once)");
	PrintHelp("-f", "--outputfile", "Output to this file instead of oldfile");
	PrintHelp("-h", "--help", "Display this help screen");
	PrintHelp("", "--version", "Display the version number");
	PrintHelp("-v", "--verbose", "Be verbose");
	PrintHelp("-V", "--veryverbose", "Be very verbose, useful for testing. Implies -v");
#	PrintHelp("-P", "--paranoid", "Run paranoid tests (see the manpage). Implies -v");
	PrintHelp("", "--writetemplate", "Write template to the file supplied and exit");
	PrintHelp("", "", "(doesn't do any merging and --oldfile isn't needed)");
	PrintHelp("-p", "--template", "Use the manually created template supplied");
	PrintHelp("", "", "(don't generate template on-the-fly)");
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Exit on CCP_DISABLE
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Exit if the environment variable is set
if (defined($ENV{CCP_DISABLE}) and $ENV{CCP_DISABLE} eq 1) {
	printv "Exiting as requested by the CCP_DISABLE environment variable\n";
	exit 0;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Commandline parameter parsing
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Help and exit 0 unless @ARGV;
GetOptions (
	
	'version' => sub { Version; exit 0; },
	'fullversion|full-version' => sub {FullVersion; exit 0; },
	'h|help' => sub { Help; exit 0; },
	'f|outputfile=s' => \$OutputFile,
	'o|oldfile=s' => \$OldFile,
	'n|newfile=s' => \$NewFile,
	'p|template=s' => \$TemplateFile,
	't|type=s' => \$ConfType, 
	'v|verbose' => \$Verbose,
	'V|veryverbose' => sub { $Verbose = 1;
		$VeryVerbose = 1;
	},
	'i|ifexist|ifexists' => \$IfExist,
	'writetemplate=s' => \$WriteTemplateTo,
	'b|backup:s' => \$WriteBackup,
	'd|delete' => \$DeleteNewfile,
	'g|ignoreopt=s' => \@IgnoreOptions,
	'D|debug' => sub {
		$DebugMode = 1;
		$VeryVerbose = 1;
		$UserSettings{ParanoidMode} = 1;
		$Verbose = 1;
	},
	'bug' => \$OutputBug,
	's|set=s' => sub {
		foreach (split(/\s+/, $_[1])) {
				$UserSettings{$_} = 1;
			}
	},
	# Deprecated/old: 
	'r|noorphans' => sub {
		$UserSettings{NoOrphans} = 1;
		print "CCP: warning: deprecated commandline option: --noorphans. Use --set NoOprhans\n";
	},
	'u|nouncomment|no-uncomment' => sub {
		$UserSettings{NoUncomment} = 1;
		print "CCP: warning: deprecated commandline option: --no-uncomment. Use --set NoUncomment\n";
	},
	'P|paranoid' => sub {
		$UserSettings{ParanoidMode} = 1;
		print "CCP: warning: deprecated commandline option: --paranoid. Use --set ParanoidMode\n";
	},
) or die "Run ", basename($0), " --help for more information\n";

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
	$UserSettings{ParanoidMode} = 1;
}
if ($UserSettings{ParanoidMode}){
	print "Paranoid mode is on!\n";
	$Verbose = 1;
}

# Load and verify type
LoadConfigType;
# We need --newfile for everything
die "No --newfile supplied\n" unless $NewFile;

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
	WriteTemplate() or die("\n");
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

# If --bug was specified then write ./ccpdebug and exit
if ($OutputBug) {
	OutputDebug;
	exit 0;
}

# Begin merging the configuration files
printvv "Okay, beginning.\n";
unless ($OutputFile eq $OldFile) {
	printnv "Merging changes between \"$OldFile\" and \"$NewFile\" into \"$OutputFile\"...";
} else {
	printnv "Merging changes between \"$OldFile\" and \"$NewFile\"...";
}

if ($DebugMode) {
	printd "OldFile is \"$OldFile\", newfile is \"$NewFile\n";
	printd "CCP version $Version\n";
	printd "$CVSRevision\n";
}
# Load settings from the files
LoadFile($NewFile) or die("\n");
LoadFile($OldFile) or die("\n");
# Output the new file
OutputFile() or die("\n");
printnv "done\n";
