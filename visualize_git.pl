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
use Directory::Iterator::PP;

my %options = (
	debug => 0,
	repo => undef,
	outdir => undef,
	skip_existing => 1,
	max_lines => 0
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
		} elsif(/^--dont_skip_existing$/) {
			$options{skip_existing} = 0;
		} elsif(/^--max_lines=(\d.*)$/) {
			$options{max_lines} = $1;
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
		} elsif (/^--help$/) {
			print <<EOF;
IDEA:

This script visualizes git repository histories by analyzing how many times
lines have been changed. Red lines mean they've been changed a lot, white
ones barely or not at all after adding. The idea is to use this information
for more targeted tests: the lines that are most often edited are probably
the ones that contain the most bugs, so tests for these lines might be
especially useful.

PARAMETERS:

--help			This help
--debug			Enables debug option
--dont_skip_existing	Don't skip existing out files
--outdir=DIR		Dir where the outfiles should be written to
--repo=DIR		Dir with a git repo to visualize
--max_lines=INT		Maximum number of lines (longer files will be skipped,
			0 means no limit)
EOF
			
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

	my $list = Directory::Iterator::PP->new($dir);

	my @files = ();

	while ($list->next) {
		my $file = $list->get;
		if($file !~ m#\.html$#) {
			push @files, $list->get;
		}
	}

	@files = grep { !-d && !-B } @files;

	return @files;
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
	debug $command;

	chomp(my $number_of_commits = qx($command));

	return $number_of_commits;
}

sub main () {
	debug "main";

	my @text_files = get_text_files($options{repo});

	my %overview = ();
	
	for my $file (@text_files) {
		my $relative_path = File::Spec->abs2rel($file, $options{repo});
		my ($out_filename, $out_folder_base, undef) = fileparse($relative_path);

		$out_folder_base = $options{outdir}.'/'.$out_folder_base;

		make_path $out_folder_base;
	
		my $out_file_path = $out_folder_base.'/'.$out_filename.'.html';

		next if $options{skip_existing} &&  -e $out_file_path;

		my $number_of_lines = get_number_of_lines_in_file($file);

		if($options{max_lines} != 0 && $number_of_lines > $options{max_lines}) {
			warn "Skip $file because it is too long: $number_of_lines";
			next;
		}

		warn "$file: $number_of_lines\n";

		my @line_commit_number = ();

		for my $line (1 .. $number_of_lines) {
			if ($line % 100 == 0) {
				warn "$file: $line of $number_of_lines\n";
			}
			push @line_commit_number, get_number_of_commits($file, $line);
		}

		tie my @all_lines, 'Tie::File', $file or die $!; 

		my ($min_number_of_edits, $max_number_of_edits) = minmax @line_commit_number;

		my $divide_by = $max_number_of_edits - $min_number_of_edits;

		my $html = "<style>tr, th, td { border-bottom: 0; margin: 0; padding: 0}; table { border-collapse: collapse; }</style>";

		$html .= "<table border=0>\n";
		$html .= "<tr><th>L</th><th>&#8470;</th><th>Code</th></tr>\n";

		my $number_of_changes = 0;

		foreach my $i (0 .. $#all_lines) {
			my $changes = $line_commit_number[$i];

			my $relative_changes = $changes - $min_number_of_edits; # min = 0

			my $opacity = 0;
			eval { $opacity = (($relative_changes / $divide_by)); };

			my $style = "style='margin: 0; padding: 0; background-color: rgba(255, 0, 0, $opacity)'";

			$html .= "<tr><td><pre $style>".($i + 1)."</pre></td><td><pre $style>$changes</pre></td><td><pre $style>".encode_entities($all_lines[$i])."</pre></td></tr>\n";
			$number_of_changes += $changes;
		}

		$html .= "</table>\n";

		open my $fh, '>', $out_file_path;

		print $fh $html;

		close $fh;

		$overview{$relative_path} = {
			link => "$out_filename.html",
			changes => $number_of_changes
		};
	}

	open my $fh, '>', "$options{outdir}/visualize_git_overview.html";
	print $fh "<table>\n";
	print $fh "<tr>\n";
	print $fh "<th>File</th>\n";
	print $fh "<th>&#8470;</th>\n";
	print $fh "</tr>\n";

	for my $file (sort { $overview{$b}{changes} <=> $overview{$a}{changes} } keys %overview) {
		print $fh "<tr>\n";
		print $fh "<td><a href='$overview{$file}{link}'>$file</a></td>\n";
		print $fh "<td>$overview{$file}{changes}</td>\n";
		print $fh "</tr>\n";	
	}
	print $fh "</table>\n";
	close $fh;
}

analyze_args(@ARGV);

main();
