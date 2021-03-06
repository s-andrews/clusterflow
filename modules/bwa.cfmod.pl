#!/usr/bin/env perl
use warnings;
use strict;
use Getopt::Long;
use FindBin qw($RealBin);
use lib "$FindBin::RealBin/../source";
use CF::Constants;
use CF::Helpers;

##########################################################################
# Copyright 2014, Philip Ewels (phil.ewels@scilifelab.se)                #
#                                                                        #
# This file is part of Cluster Flow.                                     #
#                                                                        #
# Cluster Flow is free software: you can redistribute it and/or modify   #
# it under the terms of the GNU General Public License as published by   #
# the Free Software Foundation, either version 3 of the License, or      #
# (at your option) any later version.                                    #
#                                                                        #
# Cluster Flow is distributed in the hope that it will be useful,        #
# but WITHOUT ANY WARRANTY; without even the implied warranty of         #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          #
# GNU General Public License for more details.                           #
#                                                                        #
# You should have received a copy of the GNU General Public License      #
# along with Cluster Flow.  If not, see <http://www.gnu.org/licenses/>.  #
##########################################################################

# Module requirements
my %requirements = (
	'cores' 	=> ['1', '8'],
	'memory' 	=> ['8G', '16G'],
	'modules' 	=> ['bwa','samtools'],
	'references'=> 'bwa',
	'time' 		=> sub {
		my $cf = $_[0];
		my $num_files = $cf->{'num_starting_merged_aligned_files'};
		$num_files = ($num_files > 0) ? $num_files : 1;
		# BWA alignment typically takes less than 10 hours per BAM file
		# This is probably inaccurate? May need tweaking.
		return CF::Helpers::minutes_to_timestamp ($num_files * 14 * 60);
	}
);

# Help text
my $helptext = "".("-"x17)."\n BWA Module\n".("-"x17)."\n
BWA (Burrows-Wheeler Alignment Tool) is a software package for mapping
low-divergent sequences against a large reference genome, such as the
human genome. The BWA-MEM algorithm is used in this module.\n
The module needs a reference of type bwa.\n\n";

# Setup
my %cf = CF::Helpers::module_start(\%requirements, $helptext);

# MODULE
# Check that we have a genome defined
if(!defined($cf{'refs'}{'bwa'})){
    die "\n\n###CF Error: No BWA index path found in run file $cf{run_fn} for job $cf{job_id}. Exiting.. ###";
} else {
    warn "\nAligning against $cf{refs}{bwa}\n\n";
}

open (RUN,'>>',$cf{'run_fn'}) or die "###CF Error: Can't write to $cf{run_fn}: $!";

# Print version information about the module.
my $version = `bwa`;
warn "---------- BWA version information ----------\n";
warn $version;
warn "\n------- End of BWA version information ------\n";
if($version =~ /Version: ([\S\.]+)/){
  warn "###CFVERS bwa\t$1\n\n";
}

# Separate file names into single end and paired end
my ($se_files, $pe_files) = CF::Helpers::is_paired_end(\%cf, @{$cf{'prev_job_files'}});


# Go through each single end files and run BWA
if($se_files && scalar(@$se_files) > 0){
	foreach my $file (@$se_files){
		my $timestart = time;

		my $output_fn = $file;
		$output_fn =~ s/\.gz$//i;
		$output_fn =~ s/\.(fq|fastq)$//i;
		$output_fn .= "_".$cf{config}{genome};
		$output_fn .= "_bwa.bam";

		my $command = "bwa mem -t $cf{cores} $cf{refs}{bwa} $file | samtools view -bS - > $output_fn";
		warn "\n###CFCMD $command\n\n";

		if(!system ($command)){
			# BWA worked - print out resulting filenames
			my $duration =  CF::Helpers::parse_seconds(time - $timestart);
			warn "###CF BWA (SE mode) successfully exited, took $duration..\n";
			if(-e $output_fn){
				print RUN "$cf{job_id}\t$output_fn\n";
			} else {
				warn "\n###CF Error! BWA output file $output_fn not found..\n";
			}
		} else {
			warn "\n###CF Error! BWA (SE mode) exited in an error state for input file '$file': $? $!\n\n";
		}
	}
}

# Go through the paired end files and run BWA
if($pe_files && scalar(@$pe_files) > 0){
	foreach my $files_ref (@$pe_files){
		my @files = @$files_ref;
		if(scalar(@files) == 2){
			my $timestart = time;

			my $output_fn = $files[0];
			$output_fn =~ s/\.gz$//i;
			$output_fn =~ s/\.(fq|fastq)$//i;
			$output_fn .= "_".$cf{config}{genome};
			$output_fn .= "_bwa.bam";

    		my $command = "bwa mem -t $cf{cores} $cf{refs}{bwa} $files[0] $files[1] | samtools view -bS - > $output_fn";
    		warn "\n###CFCMD $command\n\n";

    		if(!system ($command)){
    			# BWA worked - print out resulting filenames
    			my $duration =  CF::Helpers::parse_seconds(time - $timestart);
    			warn "###CF BWA (PE mode) successfully exited, took $duration..\n";
    			if(-e $output_fn){
    				print RUN "$cf{job_id}\t$output_fn\n";
    			} else {
    				warn "\n###CF Error! BWA output file $output_fn not found..\n";
    			}
    		} else {
    			warn "\n###CF Error! BWA (PE mode) exited in an error state for input file '$files[0]': $? $!\n\n";
    		}

		} else {
			warn "\n###CF Error! BWA paired end files had ".scalar(@files)." input files instead of 2\n";
		}
	}
}


close (RUN);
