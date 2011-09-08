#!/usr/bin/perl -w

eval 'exec /usr/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell
use strict;

# Examples:
#   Legacy style (mcanz):
#     export PS0='[\t]\[\e[36m\]%{(%b)\[\e[0;1m\][%c%u%f%t]%}\[\e[0m\]\u\$ '
#     export PROMPT_COMMAND=$PROMPT_COMMAND';export PS1=$(gitprompt.pl statuscount=1)'
#   Trailing symbols (ewastl):
#     export PS0='...%{[%b\[\e[0m\]%c%u%f%t\[\e[30;1m\]]%}\[\e[0m\]...'
#     export PROMPT_COMMAND=$PROMPT_COMMAND';export PS1=$(gitprompt.pl c=\+ u=\~ f=\* statuscount=1)'
#   Change branchname color (inspired by amirabella):
#     export PS0='%{[\[%f%c%u%t\]%b\[\e[0m\]]%}\[\e[0m\]\u\$ '
#     export PROMPT_COMMAND=$PROMPT_COMMAND';export PS1=$(gitprompt.pl c=%e[32m u=%e[31m f=%e[35m t=%e[30\;1m)'
#   Colored counts instead of flags (cmaher):
#     export PS0='%{\[\e[0;36m\](\[\e[1;36m\]%b\[\e[0;36m\])[%c%u%f%t\[\e[0;36m\]]%}\[\e[0m\]$ '
#     export PROMPT_COMMAND=$PROMPT_COMMAND';export PS1=$(gitprompt.pl statuscount=1 u=%[%e[31m%] c=%[%e[32m%] f=%[%e[1\;30m%])'
#
#
# Format codes:
#   These can be placed in PS0 or the option definitions.  In PS0, bash escapes
#   should be preferred when available.
#
#   %b - current branch name
#   %i - current commit id
#   %c - to-be-committed flag
#   %u - touched-files flag
#   %f - untracked-files flag
#   %A - merge commits ahead flag
#   %B - merge commits behind flag
#   %F - can-fast-forward flag
#   %t - terrible tragedy flag
#   %g - is-git-repo flag
#   %e - ascii escape
#   %[ - literal '\[' to mark the start of nonprinting characters for bash
#   %] - literal '\]' to mark the end of nonprinting characters for bash
#   %% - literal '%'
#   %{ - begin conditionally printed block, only shown if a nonliteral expands within
#   %} - end conditionally printed block
#
#
# Options:
#   These are specified as arguments to the call to gitprompt.pl in the form
#   name=value, such as $(gitprompt.pl c=\+ u=\~ f=\* statuscount=1).
#
#   c           - string to use for %c; defaults to 'c'
#   u           - string to use for %u; defaults to 'u'
#   f           - string to use for %f; defaults to 'f'
#   A           - string to use for %A; defaults to 'A'
#   B           - string to use for %B; defaults to 'B'
#   F           - string to use for %F; defaults to 'F'
#   t           - string to use for %t after a timeout; defaults to '?'
#   l           - string to use for %t when the repo is locked; defaults to '?~'
#   n           - string to use for %t when no data could be collected, such as
#                 if run from within a .git directory; defaults to '??'
#   g           - string to use for %g; defaults to the empty string (see %{)
#   statuscount - boolean; whether to suffix %c/%u with counts ("c4u8")
#
#
# Notes:
# - If your .bashrc doesn't already define a $PROMPT_COMMAND (this is common
#   in /etc/bashrc, which is often sourced by default), use this
#   PROMPT_COMMAND line instead:
#     export PROMPT_COMMAND='export PS1=$(gitprompt.pl ...)'
# - A good rule of thumb is to use real bash escapes (backslash flavor) inside
#   the definition for PS0 (where escaping is normal) and gitprompt.pl escapes
#   (percent flavor) inside the arguments to gitprompt.pl (where escaping is
#   troublesome).
# - To prevent your prompt from getting garbled, wrap all nonprinting sequences
#   (like color codes) in \[...\] or %[...%].  This tells Bash not to count
#   those characters when determining the length of your prompt and prevents it
#   from becoming confused.
# - For...  (assuming %c is whatever flags you care about)
#   - brackets no matter what, use...
#       [%c]
#   - brackets only in a git repo, regardless of status, use...
#       %{[%c%g]%}
#   - brackets only when a flag is set, use...
#       %{[%c]%}

use IO::Handle;
use IPC::Open3;
use Time::HiRes qw(time);

### prechecks ###
my $ps0 = $ENV{PS0};
unless ($ps0) {
  print "!define PS0!> ";
  exit 1;
}

### global definitions ###
my %formatliteral = (
  e => "\e",
  '%' => '%',
  '[' => "\\[",
  ']' => "\\]",
);

my %formatvalue = %{gitdata()};
my $output = "";
my @ps0 = split(/\%\{(.*?)\%\}/, $ps0);
my $conditional = 0;
foreach my $part (@ps0) {
  if ($conditional) {
    my $keep = 0;
    $part =~ s/\%(.)/exists $formatliteral{$1} ? $formatliteral{$1} : exists $formatvalue{$1} ? (($keep=1),$formatvalue{$1}) : ''/ge;
    $output .= $part if $keep;
  } else {
    $part =~ s/\%(.)/exists $formatliteral{$1} ? $formatliteral{$1} : exists $formatvalue{$1} ? $formatvalue{$1} : ''/ge;
    $output .= $part;
  }
  $conditional = !$conditional;
}
$output = "\\[\e[0;30;41m\\]! $formatvalue{error} !\\[\e[0m\\]$output" if exists $formatvalue{error};
print $output;

sub gitdata {
  ### prechecks ###
  chomp(my $headref = `git symbolic-ref HEAD 2>&1`);
  return {} if $headref =~ /fatal: Not a git repository|fatal: Unable to read current working directory/i;

  ### definitions ###
  my %opt = (
    c => 'c',
    u => 'u',
    f => 'f',
    A => 'A',
    B => 'B',
    F => 'F',
    t => '?',
    l => '?~',
    n => '??',
    g => '',
    statuscount => 0,
  );

  ### read options ###
  if (@ARGV) {
    foreach (@ARGV) {
      return {error=>"invalid parameter $_"} unless /^(\w+)\=(.*?)$/;
      my ($key,$val) = ($1,$2);
      $val =~ s/\%(.)/exists $formatliteral{$1} ? $formatliteral{$1} : ''/ge;
      $opt{$key} = $val;
    }
  }

  ### collect branch data ###
  chomp(my $commitid = `git rev-parse --short HEAD 2>&1`);
  my $branch = $commitid; #fallback value
  if ($headref =~ /fatal: ref HEAD is not a symbolic ref/i) {
    # find gitdir
    chomp(my $gitdir = `git rev-parse --git-dir`);
 
    # parse HEAD log
    open(HEADLOG, "$gitdir/logs/HEAD");
    my $lastrelevant = '';
    while (<HEADLOG>) {
      $lastrelevant = $_ if /^\s*\w+\s+$branch\w+\s/;
    }

    # if the log mentions switching to the commit id, use whatever it calls it
    $branch = $1 if $lastrelevant =~ /\scheckout\:\s+moving\s+from\s+\S+\s+to\s+(\S+)\s*$/ || $lastrelevant =~ /\smerge\s+(\S+)\:\s+Fast\-forward\s*$/;
  } elsif ($headref =~ /^refs\/heads\/(.+?)\s*$/) {
    # normal branch
    $branch = $1;
  } else {
    # unexpected input
    $headref =~ s/[^\x20-\x7e]//g;
    return {error=>$headref};
  }
 
  ### collect status data ###
  my ($statusexitcode, $statusout, @status);
  $SIG{CHLD} = sub { wait(); $statusexitcode = $?>>8; };
  my $statuspid = open3(undef,$statusout,undef,"git status");
  $statusout->blocking(0);
  my ($running, $waiting, $start, $valid) = (1, 1, time, 0);
  while ($running && $waiting) {
    while (<$statusout>) {
      push @status, $_;
    }
 
    $running = kill 0 => $statuspid;
    select undef, undef, undef, .001; #yield, actually
    $waiting = time < $start + 1;
  }

  ### parse status data ###
  my %statuscount;
  my %sectionmap = (
    'Changes to be committed' => 'c',
    'Changed but not updated' => 'u',
    'Changes not staged for commit' => 'u',
    'Untracked files' => 'f',
    'Unmerged paths' => 'u',
  );
  $statuscount{$_} = 0 foreach values %sectionmap;
  my $can_fast_forward = '';

  if (!$running) {
    # if it terminated, parse output
    my ($section);
    foreach (@status) {
      if (/^\# (\S.+?)\:\s*$/ && exists $sectionmap{$1}) {
        $section = $sectionmap{$1};
      } elsif ($section && /^\#\t\S/) {
        $statuscount{$section}++;
        $valid = 1;
      } elsif (/^nothing to commit\b/) {
        $valid = 1;
      } elsif (/\bis (ahead|behind) .+ by (\d+) commits?(\,? and can be fast\-forwarded)?/) {
        $statuscount{($1 eq 'ahead') ? 'A' : 'B'} = $2;
        $can_fast_forward = 1 if $3;
      } elsif (/^\# and have (\d+) and (\d+) different commit/) {
        $statuscount{A} = $1;
        $statuscount{B} = $2;
      }
    }
  }

  my $timeout = '';
  if ($running) {
    # it was running when we stopped caring
    $timeout = $opt{t};
    kill 2 => $statuspid;
  } elsif (!$valid) {
    #determine cause of failure
    if ($status[0] =~ /\.git\/index\.lock/) {
      $timeout = $opt{l};
    } elsif ($status[0] =~ /must be run in a work tree/) {
      $timeout = $opt{n};
    } else {
      print "\\[\e[41m\\]!! gitprompt.pl: \\`git status\' returned with exit code $statusexitcode and message:\n$status[0]\\[\e[0m\\]";
      $timeout = "\\[\e[41m\\]!$statusexitcode!\\[\e[0m\\]";
    }
  }

  ### produce output ###
  my %formatvalue = (
    b => $branch,
    i => $commitid,
    t => $timeout,
    g => $opt{g},
  );
  $formatvalue{F} = $opt{F} if $can_fast_forward;
  foreach my $flag (keys %statuscount) {
    $formatvalue{$flag} = $statuscount{$flag} ? ($opt{$flag}.($opt{statuscount} ? $statuscount{$flag} : '')) : '';
  }
  return \%formatvalue;
}
