#!/usr/bin/env perl
# Scans all UD treebanks for language-specific features and values.
# Copyright © 2016-2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
my $datapath = '.';
my $tbklist;
GetOptions
(
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist   # path to file with treebank list; if defined, only treebanks on the list will be surveyed
);
my %treebanks;
if(defined($tbklist))
{
    open(TBKLIST, $tbklist) or die("Cannot read treebank list from '$tbklist': $!");
    while(<TBKLIST>)
    {
        s/^\s+//;
        s/\s+$//;
        my @treebanks = split(/\s+/, $_);
        foreach my $t (@treebanks)
        {
            $t =~ s:/$::;
            $treebanks{$t}++;
        }
    }
    close(TBKLIST);
}
# If this script is called from the parent folder, how can it find the UD library?
use lib 'tools';
use udlib;
# In debugging mode, only the first three treebanks will be scanned.
my $debug = 0;
if(scalar(@ARGV)>=1 && $ARGV[0] eq 'debug')
{
    $debug = 1;
}

# This script expects to be invoked in the folder in which all the UD_folders
# are placed.
opendir(DIR, $datapath) or die("Cannot read the contents of '$datapath': $!");
my @folders = sort(grep {-d $_ && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
my $n = scalar(@folders);
print STDERR ("Found $n UD folders in '$datapath'.\n");
if(defined($tbklist))
{
    my $n = scalar(keys(%treebanks));
    print STDERR ("We will only scan those listed in $tbklist (the list contains $n treebanks but we have not checked yet which of them exist in the folder).\n");
}
else
{
    print STDERR ("Warning: We will scan them all, whether their data is valid or not!\n");
}
if($datapath eq '.')
{
    print STDERR ("Use the --datapath option to scan a different folder with UD treebanks.\n");
}
sleep(5);
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes.
# There is now also the new list of languages in YAML in docs-automation; this one has also language families.
my $languages_from_yaml = udlib::get_language_hash();
my %langnames;
my %langcodes;
foreach my $language (keys(%{$languages_from_yaml}))
{
    # We need a mapping from language names in folder names (contain underscores instead of spaces) to language codes.
    my $usname = $language;
    $usname =~ s/ /_/g;
    # Language names in the YAML file may contain spaces (not underscores).
    $langcodes{$usname} = $languages_from_yaml->{$language}{lcode};
    $langnames{$languages_from_yaml->{$language}{lcode}} = $language;
}
# Look for features in the data.
my %hash;
my %hittreebanks;
my $n_treebanks = 0;
foreach my $folder (@folders)
{
    # If we received the list of treebanks to be released, skip all other treebanks.
    if(defined($tbklist) && !exists($treebanks{$folder}))
    {
        next;
    }
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my $language = '';
    my $treebank = '';
    my $langcode;
    my $key;
    if($folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
    {
        $n_treebanks++;
        if($debug && $n_treebanks>3)
        {
            next;
        }
        print STDERR ("$folder\n");
        $language = $1;
        $treebank = $2 if(defined($2));
        if(exists($langcodes{$language}))
        {
            $langcode = $langcodes{$language};
            $key = $langcode;
            $key .= '_'.lc($treebank) if($treebank ne '');
            my $nhits = 0;
            chdir($folder) or die("Cannot enter folder $folder");
            # Look for the other files in the repository.
            opendir(DIR, '.') or die("Cannot read the contents of the folder $folder");
            my @files = readdir(DIR);
            closedir(DIR);
            my @conllufiles = grep {-f $_ && m/\.conllu$/} (@files);
            foreach my $file (@conllufiles)
            {
                # Read the file and look for language-specific subtypes in the DEPREL column.
                # We currently do not look for additional types in the DEPS column.
                open(FILE, $file) or die("Cannot read $file: $!");
                while(<FILE>)
                {
                    if(m/^\d+\t/)
                    {
                        chomp();
                        my @fields = split(/\t/, $_);
                        my $features = $fields[5];
                        unless($features eq '_')
                        {
                            my @features = split(/\|/, $features);
                            foreach my $feature (@features)
                            {
                                my ($f, $vv) = split(/=/, $feature);
                                # There may be several values delimited by commas.
                                my @values = split(/,/, $vv);
                                foreach my $v (@values)
                                {
                                    $hash{$f}{$v}{$key}++;
                                    $nhits++;
                                }
                            }
                        }
                    }
                }
            }
            # Remember treebanks where we found something.
            if($nhits>0)
            {
                $hittreebanks{$key}++;
            }
            chdir('..') or die("Cannot return to the upper folder");
        }
    }
}
# Check the permitted feature values in validator data. Are there values that do not occur in the data?
chdir('tools/data') or die("Cannot enter folder tools/data");
opendir(DIR, '.') or die("Cannot read the contents of the folder tools/data");
my @files = readdir(DIR);
closedir(DIR);
my @featvalfiles = grep {-f $_ && m/^feat_val\..+/} (@files);
foreach my $file (@featvalfiles)
{
    $file =~ m/^feat_val\.(.+)$/;
    my $key = $1;
    next if($key eq 'ud');
    # Also skip treebanks where we did not find anything in the data (or did not find the data).
    next if(!exists($hittreebanks{$key}));
    open(FILE, $file) or die("Cannot read $file: $!");
    while(<FILE>)
    {
        s/\r?\n$//;
        my $feature = $_;
        my ($f, $v) = split(/=/, $feature);
        if(!m/^\s*$/ && !exists($hash{$f}{$v}{$key}))
        {
            $hash{$f}{$v}{$key} = 'ZERO BUT LISTED AS PERMITTED IN VALIDATOR DATA';
        }
    }
    close(FILE);
}
chdir('../..');
my @features = sort(keys(%hash));
print <<EOF
---
layout: base
title:  'Features and Values'
udver: '2'
---

This is an automatically generated list of features and values (both universal and language-specific) that occur in the UD data.
EOF
;
foreach my $f (@features)
{
    my %ffolders;
    my @values = sort(keys(%{$hash{$f}}));
    print("\#\# $f\n\n");
    print("[$f]()\n\n");
    foreach my $v (@values)
    {
        my @folders = sort(keys(%{$hash{$f}{$v}}));
        foreach my $folder (@folders)
        {
            print("* $f=$v\t$folder\t$hash{$f}{$v}{$folder}\n");
            $ffolders{$folder}++;
        }
    }
    print("\n");
}
