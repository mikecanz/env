#!/usr/bin/perl -w
use strict;

# synopsis: export PS1='$(gitprompt.pl)'
#
# Trailing symbols:
#   $(gitprompt.pl "[%b%c%u%f%t]" c=\+ u=\~ f=\* statuscount=1)
# Change branchname color:
#   $(gitprompt.pl "[%c%u%t%b%e[0m]" c=%e[32m u=%e[31m t=%e[30;1m)
#
# Format codes:
#   %b - current branch name
#   %c - to-be-committed flag
#   %u - touched-files flag
#   %f - untracked-files flag
#   %t - timeout flag
#   %e - ascii escape
# Options:
#   c           - string to use for %c; defaults to 'c'
#   u           - string to use for %u; defaults to 'u'
#   f           - string to use for %f; defaults to 'f'
#   t           - string to use for %t; defaults to '?'
#   statuscount - boolean; whether to suffix %c/%u with counts ("c4u8")
 
use IO::Handle;
use IPC::Open3;
use Time::HiRes qw(time);
 
chomp(my $headref = `git symbolic-ref HEAD 2>&1`);
exit if $headref =~ /fatal: Not a git repository/;

my $format = '(%b)[%c%u%t]';
my %opt = (
  c => 'c',
  u => 'u',
  f => 'f',
  t => '?',
);
if (@ARGV) {
  $format = shift;
  foreach (@ARGV) {
    die "invalid parameter $_" unless /^(\w+)\=(.*?)$/;
    $opt{$1} = $2;
  }
}
foreach my $opt (keys %opt) {
  $opt{$opt} =~ s/\%e/\e/g;
}

my $branch;
if ($headref eq 'fatal: ref HEAD is not a symbolic ref') {
  # get commit id for lookup and fallback
  chomp($branch = `git rev-parse --short HEAD 2>&1`);

  # find gitdir
  chomp(my $gitdir = `git rev-parse --git-dir`);

  # parse HEAD log
  open(HEADLOG, "$gitdir/logs/HEAD");
  my $lastrelevant = '';
  while (<HEADLOG>) {
    $lastrelevant = $_ if /^\s*\w+\s+$branch\w+\s/;
  }

  # if the log mentions switching to the commit id, use whatever it calls it
  $branch = $1 if $lastrelevant =~ /\scheckout\:\s+moving\s+from\s+\S+\s+to\s+(\S+)\s*$/;
} elsif ($headref =~ /^refs\/heads\/(.+?)\s*$/) {
  # normal branch
  $branch = $1;
} else {
  # unexpected input
  $headref =~ s/[^\x20-\x7e]//g;
  print "!$headref!";
  exit;
}
 
my ($statusout);
$SIG{CHLD} = sub { wait(); };
my $statuspid = open3(undef,$statusout,undef,"git status");
$statusout->blocking(0);
 
my (@status);
my ($running, $waiting, $start) = (1, 1, time);
while ($running && $waiting) {
  while (<$statusout>) {
    push @status, $_;
  }
 
  $running = kill 0 => $statuspid;
  select undef, undef, undef, .001; #yield, actually
  $waiting = time < $start + .5;
}

my %statuscount;
my %sectionmap = (
  'Changes to be committed' => 'c',
  'Changed but not updated' => 'u',
  'Untracked files' => 'f',
);
if (!$running) {
  # if it terminated, parse output
  my ($section);
  foreach (@status) {
    if (/^\# (\S.+?)\:\s*$/ && exists $sectionmap{$1}) {
      $section = $sectionmap{$1};
    } elsif ($section && /^\#\t\S/) {
			$statuscount{$section}++;
    }
  }
}

my $str = $format;
my %formatvalue = (
  b => $branch,
  t => $running ? $opt{t} : '',
  e => "\e",
);
foreach my $flag (values %sectionmap) {
  $formatvalue{$flag} = $statuscount{$flag} ? ($opt{$flag}.($opt{statuscount} ? $statuscount{$flag} : '')) : '';
}
$str =~ s/\%(\w)/exists $formatvalue{$1} ? $formatvalue{$1} : '%'.$1/ge;
print $str;
