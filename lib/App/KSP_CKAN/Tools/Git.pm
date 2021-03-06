package App::KSP_CKAN::Tools::Git;

use v5.010;
use strict;
use warnings;
use autodie qw(:all);
use Method::Signatures 20140224;
use Carp qw(croak);
use Try::Tiny;
use Git::Wrapper;
use Capture::Tiny qw(capture);
use File::chdir;
use File::Path qw(remove_tree mkpath);
use Moo;
use namespace::clean;

# ABSTRACT: A collection of our regular git commands

# VERSION: Generated by DZP::OurPkg:Version

=head1 SYNOPSIS

  use App::KSP_CKAN::Git;

  my $git = App::KSP_CKAN::Git->new(
    remote => 'git@github.com:KSP-CKAN/NetKAN-bot.git',
    local => "$ENV{HOME}/.NetKAN/NetKAN-bot",
    clean => 1,
  );

=head1 DESCRIPTION

CKAN's development + build process is built around git. The
things we need to do are pretty common and all git 
interactions will fit nicely here.

The wrapper can be called with the following options.

=over

=item remote

Remote repository path or url.

=item local

Path to the working directory of where it will be cloned.

=item working

This optional, we'll try to guess that. It can however
be provided (just the human name, no slashes).

=item clean

Will remove and pull a fresh copy of the repository.

=item shallow

Will perform a shallow clone of the repository

=back

=cut

has 'remote'    => ( is => 'ro', required => 1 );
has 'local'     => ( is => 'ro', required => 1 );
has 'working'   => ( is => 'ro', lazy => 1, builder => 1 );
has 'clean'     => ( is => 'ro', default => sub { 0 } );
has 'shallow'   => ( is => 'ro', default => sub { 1 } );
has 'branch'    => ( is => 'rw', lazy => 1, builder => 1 );
has '_git'      => ( is => 'rw', isa => sub { "Git::Wrapper" }, lazy => 1, builder => 1 );

method _build__git {
  if ( ! -d $self->local ) {
    mkpath($self->local);
  }

  if ($self->clean) {
    $self->_clean;
  }

  if ( ! -d $self->local."/".$self->working ) {
    $self->_clone;
  }

  return Git::Wrapper->new({
    dir => $self->local."/".$self->working,
  });
}

method _build_working {
  $self->remote =~ m/^(?:.*\/)?(.+)$/;
  my $working = $1;
  $working =~ s/\.git$//;
  return $working;
}

method _clone {
  # TODO: I think Git::Wrapper has a way to do this natively
  # TODO: We should pass back success or failure.
  if ($self->shallow) {
    capture { system("git", "clone", "--depth", "1", $self->remote, $self->local."/".$self->working) };
  } else {
    capture { system("git", "clone", $self->remote, $self->local."/".$self->working) };
  }
  return;
}

method _clean {
  local $CWD = $self->local;
  if ( -d $self->working) {
    remove_tree($self->working);
  }
  return;
}

method _build_branch {
  my @parse = $self->_git->rev_parse(qw|--abbrev-ref HEAD|);
  return $parse[0];
}

=method add_all

  $git->add;

This method will perform a 'git add .' 

=cut

# TODO: It'd probably be nice to allow a list of 
# files
method add($file?) {
  if ($file) {
    $self->_git->add($file);
  } else {
    $self->_git->add(".");
  }
  return;
}

=method changed
  
  my @changed = $git->changed;

Will return a list of changed files when compared to 
origin/current_branch. Can be used in scalar context 
(number of committed files) or an if block.

  if ($git->changed) {
    say "We've got changed files!";
  }

Takes an optional bool parameter of 'origin' if you want
a list of comparing local.

  my @local = $git->changed( origin => 0 );

=cut

method changed(:$origin = 1) {
  if ( $origin ) {
    return $self->_git->diff({ 'name-only' => 1, }, "--stat", "origin/".$self->branch );
  } else {
    return $self->_git->diff({ 'name-only' => 1, });
  }
}

=method commit

  $git->commit( all => 1, message => "Commit Message!" );

Will commit all staged added files with a generic
commit message.

=over

=item all

Optional argument. Defaults to false.

=item file

Optional argument. Will commit all if not provided.

=item message

Optional argument. Will literally add 'Generic Commit' as
the commit message if not provided.

=back

=cut

method commit(:$all = 0, :$file = 0, :$message = "Generic Commit") {
  if ($all || ! $file) {
    return $self->_git->commit({ a => 1 }, "-m $message");
  } else {
    return $self->_git->commit($file, "-m \"$message\"");
  }
}

=method reset
  
  $git->reset( file => $file );

Will reset the uncommitted file.

=cut

# TODO: We can likely expand what we can do with reset.
method reset(:$file) {
  return $self->_git->RUN("reset", $file);
}

=method push
  
  $git->push;

Will push the local branch to origin/branh.

=cut

method push {
  return $self->_git->push("origin",$self->branch);
}

=method pull

  $git->pull;

Performs a git pull. Takes optional bool arguments of
'ours' and 'theirs' which will tell git who wins when
merge conflicts arise.

=cut

method pull(:$ours?,:$theirs?) {
  if ($theirs) {
    $self->_git->pull(qw|-X theirs|);
  } elsif ($ours) {
    $self->_git->pull(qw|-X ours|);
  } else {
    $self->_git->pull;
  }
  return;
}

1;
