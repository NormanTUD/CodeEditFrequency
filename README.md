# Code Edit Frequency Visualizer

This script visualizes git repository histories by analyzing how many times
lines have been changed. Red lines mean they've been changed a lot, white
ones barely or not at all after adding. The idea is to use this information
for more targeted tests: the lines that are most often edited are probably
the ones that contain the most bugs, so tests for these lines might be
especially useful.

# Requirements

```console
sudo cpan -i Directory::Iterator::PP
sudo cpan -i Data::Printer
```

# Call

`perl visualize_git.pl --repo=DIRECTORY_WITH_GIT_REPO --outdir=DIRECTORY`

# Example

See the file `visualize_git.pl.html` on how the output looks (online-version
[here](https://htmlpreview.github.io/?https://github.com/NormanTUD/CodeEditFrequency/blob/master/visualize_git.pl.html)).
