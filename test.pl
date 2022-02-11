#!/usr/bin/perl

use strict;
use warnings;
use File::Find;
use File::Path qw(make_path);
use File::Spec;
use Data::Printer;
use List::MoreUtils qw(minmax);
use Tie::File;
use HTML::Entities;
use File::Basename;

my %options = (
	debug => 0,
	repo => undef,
	outdir => undef
);

sub debug (@) {
	return unless $options{debug};
	for (@_) {
		warn "DEBUG: $_\n";
	}
}

sub analyze_args {
	for (@_) {
		if(/^--debug$/) {
			$options{debug} = 1;
		} elsif(/^--outdir=(.*)$/) {
			my $outdir = $1;
			$outdir = File::Spec->rel2abs($outdir);
			$options{outdir} = $outdir;
			make_path $outdir;
		} elsif(/^--repo=(.*)$/) {
			my $folder = $1;
			$folder = File::Spec->rel2abs($folder);
			if(-d $folder) {
				if(-d "$folder/.git") {
					$options{repo} = $1;
				} else {
					die "$folder is not a git repo (does not contain .git directory)";
				}
			} else {
				die "$folder does not exist";
			}
		} else {
			die "Unknown parameter $_";
		}
	}

	die "Must specify valid --repo" unless $options{repo};
	die "Must specify valid --outdir" unless $options{outdir};
}

sub get_text_files {
	my $dir = shift;
	debug "get_text_files($dir)";

	return grep { !-d && !-B } glob "$dir/*";
}

sub get_number_of_lines_in_file {
	my $file = shift;
	debug "get_number_of_lines_in_file($file)";

	my $count = 0;

	open(my $FILE, "< $file") or die "can't open $file: $!";
	$count++ while <$FILE>;

	return $count;
}

sub get_number_of_commits {
	my ($file, $line) = @_;
	debug "get_number_of_commits($file, $line)";

	my $rel_path = File::Spec->abs2rel($file, $options{repo}) ;

	my $command = qq#cd $options{repo}; git log -L${line},${line}:'${rel_path}' --pretty=format:"%h" --no-patch | wc -l#;

	chomp(my $number_of_commits = qx($command));

	return $number_of_commits;
}

sub main () {
	debug "main";

	my @text_files = get_text_files($options{repo});

	for my $file (@text_files) {
		my $number_of_lines = get_number_of_lines_in_file($file);

		my @line_commit_number = ();

		for my $line (1 .. $number_of_lines) {
			push @line_commit_number, get_number_of_commits($file, $line);
		}

		tie my @all_lines, 'Tie::File', $file or die $!; 

		my ($min, $max) = minmax @line_commit_number;

		my $divide_by = $max - $min;

		my $html = "";

		foreach my $i (0 .. $#all_lines) {
			my $changes = $line_commit_number[$i];

			my $relative_changes = $changes - $min; # min = 0

			my $opacity = 0;
			eval { $opacity = (($relative_changes / $divide_by)); };

			$html .= "<pre style='width: 99%; margin: 0; padding: 0; background-color: rgba(255, 0, 0, $opacity)'>".encode_entities($all_lines[$i])."</pre>";
		}

		my $relative_path = File::Spec->abs2rel($file, $options{repo});
		my ($out_filename, $out_folder_base, undef) = fileparse($relative_path);

		make_path $out_folder_base;
	
		my $out_file_path = $options{outdir}.'/'.$out_folder_base.'/'.$out_filename.'.html';

		open my $fh, '>', $out_file_path;

		print $fh $html;

		close $fh;
	}
}

analyze_args(@ARGV);

main();
