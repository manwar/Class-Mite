#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use FindBin qw($Bin);
use lib $Bin;

require ParentDB;
require ParentFile;

package MultiParentTest;
use Class;
extends qw/ParentDB ParentFile/;

our @build_log;
sub BUILD { push @build_log, 'MultiParentTest' }

package main;

my $obj = MultiParentTest->new;

# Methods from both parents accessible
ok($obj->can('to_db'), 'can access method from ParentDB');
ok($obj->can('to_file'), 'can access method from ParentFile');
is($obj->to_db . $obj->to_file, "DB saved\nFile saved\n", 'Methods from all parents accessible');

# BUILD hook order according to C3 linearization (ancestor-first)
my @linear = @{ mro::get_linear_isa('MultiParentTest') };
my @expected_build_order = grep {
    my $f;
    {
        no strict 'refs';
        $f = *{"${_}::BUILD"}{CODE};
    }
    $f;
} grep { $_ ne 'UNIVERSAL' } reverse @linear;

is_deeply([@build_log], \@expected_build_order, 'BUILD hooks called in linearized order');

done_testing;
