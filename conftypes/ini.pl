#!/usr/bin/perl
# Common Configuration Parser - ini-style parsing
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

# NOTE: Don't run this file directly, run ccp --type ini

$CCP_ConfTypeVer = "1";		# Set the version of the CCP ConfigType spec this
				# obeys.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions for loading the files
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub LoadFile ($) {
	my $CurrentHeader = "CCP_NoHeader_Default";	# Set the default header
							# This is set so that we can handle
							# files that doesn't have a header
							# for the first part of the file
	die "LoadFile got a nonexistant file supplied!" unless -e $_[0];
	my %ParanoiaHash if $UserSettings{ParanoidMode};
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
		s/;$//;			# Strip trailing ; 
		# Handle []-headers
		if (/^\s*\[(.*)\]/) {
			$CurrentHeader = $1;
			printvv "Read header: $CurrentHeader\n";
			next;
		}
		s/^\$//;		# Strip leading $
		next unless length;	# Empty?
		next unless m/=/;	# No "=" in the line means nothing for us to do
		my ($var, $value) = split(/\s*=\s*/, $_, 2);    # Set the variables
		printvv "Ignoring key $var as requested" and next if grep $_ eq $var, @IgnoreOptions;
		printvv "Read key value pair: $var = $value\n";
		$Config{$CurrentHeader}{$var} = $value;
		$ParanoiaHash{$CurrentHeader}{$var}++ if $UserSettings{ParanoidMode};
	}
	close(FILE);
	# If we're not in ParanoidMode then we're all done
	return(1) unless $UserSettings{ParanoidMode};
	printvv "Running paranoia test on $_[0]\n";
	foreach my $CurrParaHeader (sort(keys(%ParanoiaHash))) {
		foreach(sort(keys(%{$ParanoiaHash{$CurrParaHeader}}))) {
			print "PARANOIA WARNING: $_ was seen more than once! (Seen $ParanoiaHash{$CurrParaHeader}{$_} times)\n" if $ParanoiaHash{$_} gt 1;
		}
	}
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions to generate a template
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub GenerateTemplate {
	our $CurrentHeader = "CCP_NoHeader_Default";	# Set the default header
							# This is set so that we can handle
							# files that doesn't have a header
							# for the first part of the file
	# @Template is a global array
	die "\$NewFile not set" unless $NewFile;
	our %Templ_ConfigOptsFound;	# A hash of all config options found.
	our $Templ_DummyRun;		# If true GenTemplateReal won't actually change anything in @Template
	printv "Generating template from $NewFile...\n";
	open(NEWFILE, "<$NewFile");
	@Template = <NEWFILE>;
	close(NEWFILE);
	# This subroutine is the one that actually goes ahead and generates the template.
	# It will simply read through the @Template array and parse it.
	# It doesn't know what is uncommented by ccp and what is really there
	sub GenTemplateReal {
		foreach (@Template) {
			my $RunType = $_[0];
			my $EOL = "";
			next if $_ =~ /^\s*[#|<|\?>|\*|\/\*|;|:|@|]/; # Check for comments and other funstuff that we don't handle
			next if $_ =~ /^\s*$/;				# If the line is empty, then skip ahead
			# Handle []-headers
			if (/^\s*\[(.*)\]/) {
				$CurrentHeader = $1;
				printvv "Read header: $CurrentHeader\n" if $RunType;
				next;
			}
			next unless $_ =~ /=/;				# If there is no '=' in the line we just skip ahead
			chomp;						# Remove newlines
			my $Name = $_;					# Copy $_'s contents to $Name 
				# Start stripping junk from the line, to figure out the name of the variable
			$Name =~ s/^([^\n|^=]+)\s*=\s*.*/$1/;
			$Name =~ s/^\s*(\$)//;
			$Name =~ s/\s+//g;
			next unless $Name;
			# Set the hash value
			$Templ_ConfigOptsFound{$CurrentHeader}{$Name} = 1;
			# If this is a dummy run then we just move on without getting down and dirty.
			next if $Templ_DummyRun;
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
			s/(.*=\s*)\Q$LineContents\E/${1}{CCP::CONFIG::$CurrentHeader\:\:$Name}$EOL\n/;
			printd "Regexp: s/(.*=\\s*)\\Q$LineContents\\E/\${1}{CCP::CONFIG::$CurrentHeader\:\:$Name}$EOL\\n/\n";
			printvv "Read setting \"$Name\"\n";
		}
	}
	# Subroutine that uncomments options in the config file if needed/possible
	sub Templ_UncommentOptions {
		foreach (@Template) {
			# Handle []-headers
			if (/^\s*\[(.*)\]/) {
				$CurrentHeader = $1;
				next;
			}
			next unless m/^\s*[#|\;]/ and m/=/;
			# Try to figure out the name of the option
			my $Name = $_;
			$Name =~ s/^[#|\;]+\s*//;
			$Name =~ s/^([^\n|^=]+)\s*=\s*.*/$1/;
			$Name =~ s/^\s*(\$)//;
			$Name =~ s/\s+//g;
			if ($Config{$CurrentHeader}{$Name} and not $Templ_ConfigOptsFound{$CurrentHeader}{$Name} and not (grep $_ eq $Name, @IgnoreOptions)) {
				# Uncomment it !
				s/^[#|\;]+\s*//;
				printvv "Uncommented [$CurrentHeader]->$Name\n";
				$Templ_ConfigOptsFound{$Name} = 1;
			}
		}
	}
	# Call the routines
	unless ($UserSettings{NoTemplateUncommenting}) {
		# Read the template, dummy run of GenTemplateReal
		$Templ_DummyRun = 1;
		GenTemplateReal(0);
		# Try to uncomment options as needed
		Templ_UncommentOptions;
		# Real run, make changes to the template
		$Templ_DummyRun = 0;
		GenTemplateReal(1);
	} else {
		# Just make changes to the template without attempting to uncomment
		$Templ_DummyRun = 0;
		GenTemplateReal(1);
	}
	# Empty the hash
	%Templ_ConfigOptsFound = ();
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
	foreach my $header (keys %Config) {
		foreach my $key (keys %{$Config{$header}}) {
			my $LineNo = 0 if $DebugMode;
			printvv "Setting [$header]->$key to $Config{$header}{$key}\n";
			printd "{CCP::CONFIG::$header\:\:$key}\n";
			foreach (@Template) {
				$LineNo++ if $DebugMode;
				if (s/{CCP::CONFIG::\Q$header\E\:\:\Q$key\E}/$Config{$header}{$key}/) {
					# If we replaced something then we delete the key.
					# A key should never be used more than once, you'll need an ini-type for that to work.
					printd "Match of $key on line $LineNo, key deleted - moving on to next key\n" if $DebugMode;
					delete($Config{$header}{$key});
					last;
				}
			}
		}
		delete $Config{$header}
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
	if ($Verbose or $UserSettings{NoOrphans}) {
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
		if ($OrphansFound and $UserSettings{NoOrphans}) {
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
	return(1);
}
