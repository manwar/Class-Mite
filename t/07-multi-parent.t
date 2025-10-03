#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use FindBin qw($Bin);
use lib $Bin;

# Step 1: Load parent packages
use ParentDB;
use ParentFile;

# Step 2: Define the child package
{
    package MultiParentTest;
    use Class;

    # Add multiple parents
    extends qw/ParentDB ParentFile/;

    # Optional: convenience method
    sub save {
        my $self = shift;
        return $self->to_db . $self->to_file;
    }
}

# Step 3: Test
package main;
my $obj = MultiParentTest->new;

ok($obj->can('to_db'),   'can access method from ParentDB');
ok($obj->can('to_file'), 'can access method from ParentFile');
is($obj->save, "DB saved\nFile saved\n", 'Methods from all parents accessible');

done_testing;
