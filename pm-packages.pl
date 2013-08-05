#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use File::Find::Rule;
use File::Util qw(escape_filename);
use Path::Class;
use IO::Uncompress::Gunzip qw(gunzip);
use LWP::Simple qw(mirror);
use List::MoreUtils qw(any);

GetOptions(
    'cpan'    => \my $cpan,
    'core'    => \my $core,
    'local:s' => \my $local,
);

my $root = dir($ENV{HOME}, '.pm-packages.pl');
$root->mkpath;

if ($cpan) {
    my $local = $root->file('02packages.details.txt.gz');
    mirror 'http://cpan.perl.org/modules/02packages.details.txt.gz' => "$local";
    gunzip "$local" => \my $content;
    $content =~ s/^.+?\n\n//s;
    foreach (split /\n/, $content) {
        /^(\S+)/ and print $1, "\n";
    }
} elsif ($core) {
    require Module::CoreList;
    print $_, "\n" for Module::CoreList->find_modules(qr//);
} else {
    require Config;

    my $prefix = $Config::Config{prefix};
    my $perlbrew_perls = dir(
        ( $ENV{PERLBREW_ROOT} || ( $ENV{HOME}, 'perl5', 'perlbrew' ) ),
        'perls', ''
    );
    my $plenv_versions = dir(
        ( $ENV{PLENV_ROOT} || ( $ENV{HOME}, '.plenv' ) ),
        'versions', ''
    );
    $prefix =~ s/^\Q$perlbrew_perls\E/perlbrew/;
    $prefix =~ s/^\Q$plenv_versions\E/plenv/;

    if (defined $local) {
        $local = 'local' unless length $local;
        $local = dir($local)->absolute;

        require lib;
        lib->import("$local/lib/perl5");

        $prefix .= "-$local"
    }

    my $cache = $root->file('cache', escape_filename($prefix));

    my @source_dirs = grep $_->is_absolute, map dir($_), @INC;

    if (-e $cache && (my $cache_mtime = $cache->stat->mtime)) {
        my $cpanm_dir = dir($ENV{HOME}, '.cpanm');

        my $cache_expired;
        foreach my $dir (@source_dirs, $cpanm_dir) {
            if (-e $dir && (my $mtime = $dir->stat->mtime)) {
                if ($cache_mtime < $mtime) {
                    $cache_expired++;
                    last;
                }
            }
        }

        unless ($cache_expired) {
            print $_ for $cache->slurp;
            exit 0;
        }
    }

    $cache->dir->mkpath;
    my $fh = $cache->openw;

    foreach my $dir (@source_dirs) {
        my @files = File::Find::Rule->file->name('*.pm')->in($dir);
        foreach my $file (@files) {
            next if any { $file =~ /^\Q$_\E/ } grep { /^\Q$dir\E\// } @INC;
            $file =~ s"^\Q$dir\E/"";
            $file =~ s/\.pm$//;
            $file =~ s'/'::'g;
            print $file, "\n";
            print $fh $file, "\n";
        }
    }
}
