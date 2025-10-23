#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME               => 'Class::Mite',
    AUTHOR             => q{Mohammad Sajid Anwar <mohammad.anwar@yahoo.com>},
    VERSION_FROM       => 'lib/Class/Mite.pm',
    ABSTRACT_FROM      => 'lib/Class/Mite.pm',
    LICENSE            => 'artistic_2',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    PREREQ_PM => {
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    test  => { TESTS => 't/*.t' },
    clean => { FILES => 'Class-Mite-*' },
    (eval { ExtUtils::MakeMaker->VERSION(6.46) } ? (META_MERGE => {
        'meta-spec' => { version => 2 },
        provides    => {
            'Class::Mite'  => { file => 'lib/Class/Mite.pm',  version => '0.06' },
            'Class::More'  => { file => 'lib/Class/More.pm',  version => '0.06' },
            'Class::Clone' => { file => 'lib/Class/Clone.pm', version => '0.06' },
            'Class'        => { file => 'lib/Class.pm',       version => '0.06' },
            'Role'         => { file => 'lib/Role.pm',        version => '0.06' },
        },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/manwar/Class-Mite.git',
                web  => 'https://github.com/manwar/Class-Mite',
            },
        }})
     : ()
    ),
);
