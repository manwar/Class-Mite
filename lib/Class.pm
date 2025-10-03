package Class;

$Class::VERSION    = '0.02';
$Class::AUTHORITY  = 'cpan:MANWAR';

=head1 NAME

Class - A lightweight constructor and BUILD hook system for Perl

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

=head2 Class ONLY

    package MyApp::User;
    use Class;

    sub BUILD {
        my ($self, $args)  = @_;
        $self->{full_name} = join ' ', $args->{first}, $args->{last};
    }

    sub get_name { shift->{full_name} }
    sub get_id   { shift->{id} }

    package main;

    use strict;
    use warnings;

    my $user = MyApp::User->new(
        first => 'John',
        last  => 'Doe',
        id    => 42,
    );

    print $user->get_id;   # 42
    print $user->get_name; # John Doe

=head2 Class with Inheritance

    package MyApp::Person;
    use Class;

    sub BUILD {
        my ($self, $args)  = @_;
        $self->{full_name} = join ' ', $args->{first}, $args->{last};
    }

    sub get_name { shift->{full_name} }

    package MyApp::Employee;
    use Class;
    extends qw/MyApp::Person/;

    sub get_id { shift->{id} }

    package main;

    use strict;
    use warnings;

    my $emp = MyApp::Employee->new(
        first => 'John',
        last  => 'Doe',
        id    => 42
    );

    print $user->get_id;   # 42
    print $user->get_name; # John Doe

=head2 Class with Role

    package Loggable;
    use Role;
    requires qw/get_name/;

    sub log {
        my ($self, $msg) = @_;
        return "[LOG] $msg\n";
    }

    package MyApp::Admin;
    use Class;
    with qw/Loggable/;

    sub get_name { shift->{name} }

    package main;
    use strict;
    use warnings;

    my $admin = MyApp::Admin->new(name => 'Alice');

    print $admin->get_name;              # Alice
    print $admin->log("Admin created");  # [LOG] Admin created

=head2 Class with Roles

    package Loggable;
    use Role;
    requires qw/get_name/;

    sub log {
        my ($self, $msg) = @_;
        return "[LOG] $msg\n";
    }

    package File;
    use Role;
    requires qw/save/;

    package MyApp::Admin;
    use Class;
    with qw/Loggable File/;

    sub get_name { shift->{name}     }

    sub save     { shift->log(shift) }

    package main;
    use strict;
    use warnings;

    my $admin = MyApp::Admin->new(name => 'Alice');

    print $admin->get_name;              # Alice
    print $admin->log("Admin created");  # [LOG] Admin created
    print $admin->save("Data saved");    # [LOG] Data saved

=head1 DESCRIPTION

C<Class> provides a minimal object system for Perl. It focuses on:

=over 4

=item * Object instantiation with C<new>

=item * Automatic execution of a C<BUILD> method if present

=item * Integration with L<Role> for role composition

=item * **Simple inheritance via the C<extends> key**

=back

The goal is to provide the smallest possible framework for classes and
roles without requiring large dependencies such as Moose or Moo.

=head1 CONSTRUCTOR

=head2 new

    my $object = MyClass->new(%attributes);

Creates a new object, blesses a hash reference with the given attributes
into the class, and then calls the optional C<BUILD> method.

If a C<BUILD> method is defined in the class, it is invoked with the
signature:

    sub BUILD {
        my ($self, $args) = @_;
        ...
    }

where:

=over 4

=item * C<$self> is the newly created object (blessed hash).

=item * C<$args> is a plain hash reference containing the constructor arguments.

=back

This allows you to modify or validate the object immediately after creation,
for example by normalizing attributes, calculating derived values, or
cleaning up arguments.

=head1 IMPORT HOOK

When you C<use Class;> in a package, it automatically:

=over 4

=item * Sets up **inheritance** if the C<extends> key is provided.

=item * Ensures L<Role> is loaded

=item * Exports the C<with> and C<does> functions into your class, allowing role composition

=back

This makes role-based composition seamless:

    package MyApp::Thing;
    use Class;
    with 'SomeRole', 'OtherRole';

=head1 METHODS

=over 4

=item * new

Creates a new object and optionally calls C<BUILD>.

=item * import

Internal. Handles inheritance, ensures C<Role> is available and exports C<with> and C<does> into the calling class.

=back

=head1 INTEGRATION WITH Role

C<Class> is designed to be used together with L<Role>. Classes that
C<use Class;> can consume roles defined with L<Role>. The C<with>
function is made available automatically.

=head1 INHERITANCE

The C<extends> key allows a class to inherit from a parent class using
Perl's standard C<@ISA> mechanism.

    package ChildClass;
    use Class;
    extends 'ParentClass';
    # ChildClass methods and attributes will override ParentClass's.

=head1 INHERITANCE AND MULTI-PARENT SUPPORT

The C<extends> function now supports **multiple parents** in a single call:

    package Backend;
    use Class;
    extends qw/Database File/;

This sets up standard Perl C<@ISA> linearization. You can still call C<extends> multiple times:

    extends 'AnotherParent';

C<Class> automatically handles **diamond inheritance**, ensuring:

=over 4

=item * Parent classes are loaded in order.

=item * C<BUILD> hooks are called **once per class**, even if multiple inheritance paths reach the same ancestor.

=item * C<BUILD> hooks are called in **parent-first order**, consistent with Moo/Moose.

=back

Example:

    package A;
    use Class;
    sub BUILD { push @build_log, 'A' }

    package B;
    use Class;
    extends 'A';
    sub BUILD { push @build_log, 'B' }

    package C;
    use Class;
    extends 'A';
    sub BUILD { push @build_log, 'C' }

    package D;
    use Class;
    extends qw/B C/;
    sub BUILD { push @build_log, 'D' }

    package main;
    use Class;

    my @build_log;
    my $obj = D->new;

    # @build_log now contains: ('A','B','C','D')
    # Each BUILD called exactly once, parent-first.

=head1 NEW FEATURES

=over 4

=item * Multi-parent inheritance via C<extends qw/.../>.

=item * Diamond-safe BUILD hook execution (parent-first, single invocation).

=item * Optional C<extends => 'ParentClass'> syntax on C<use Class;>.

=back

=head1 DIAGNOSTICS

=over 4

=item * C<Recursive inheritance detected: Child cannot extend itself>

Thrown if a class attempts to extend itself.

=item * C<BUILD hooks called in wrong order or multiple times>

Will fail tests if diamond-safe BUILD is violated. Use C<@ISA> and C<extends> as documented.

=back

=head1 EXAMPLES

=head2 Basic Usage

    package Point;
    use Class;

    sub BUILD {
        my ($self, $args) = @_;
        $self->{x} ||= 0;
        $self->{y} ||= 0;
    }

    my $p = Point->new(x => 10, y => 20);
    say $p->{x}; # 10
    say $p->{y}; # 20

=head2 With Inheritance

    package BaseItem;
    use Class;

    sub get_type { 'item' }

    package HeavyItem;
    use Class extends => 'BaseItem';

    sub get_type { 'heavy ' . shift->SUPER::get_type() }

    my $item = HeavyItem->new;
    say $item->get_type; # heavy item

=cut

use strict;
use warnings;

use Exporter;
our @EXPORT = qw(extends with does);
our @ISA    = qw(Exporter);

use mro ();

sub new {
    my $class = shift;
    my %attrs = @_;

    my $self = bless { %attrs }, $class;

    # Diamond-safe, parent-first BUILD calls
    my %seen;
    my @order;

    # DFS to collect parents first
    my $collect;
    $collect = sub {
        my ($cur) = @_;
        return if $seen{$cur}++;
        no strict 'refs';
        $collect->($_) for @{"${cur}::ISA"};
        use strict 'refs';
        push @order, $cur;
    };

    $collect->($class);

    # Call BUILD in parent-first order
    for my $c (@order) {
        no strict 'refs';
        my $build = *{"${c}::BUILD"}{CODE};
        use strict 'refs';
        $build->($self, \%attrs) if $build;
    }

    return $self;
}

sub extends {
    my ($maybe_class, @maybe_parents) = @_;
    my $child_class = caller;

    # Handle multiple parents: if called with one scalar, treat as one parent
    my @parents = @maybe_parents ? ($maybe_class, @maybe_parents) : ($maybe_class);

    for my $parent_class (@parents) {
        die "Recursive inheritance detected: $child_class cannot extend itself"
            if $child_class eq $parent_class;

        # Load parent if not yet compiled
        my $parent_exists;
        {
            no strict 'refs';
            $parent_exists = keys %{"${parent_class}::"};
        }

        unless ($parent_exists || $INC{"$parent_class.pm"}) {
            (my $parent_file = "$parent_class.pm") =~ s{::}{/}g;
            eval { require $parent_file };
            die "Failed to load parent class '$parent_class' from '$parent_file': $@" if $@;
        }

        # Avoid duplicate parents
        use mro ();
        my @linear = @{ mro::get_linear_isa($child_class) };
        next if grep { $_ eq $parent_class } @linear;

        # Add parent
        no strict 'refs';
        push @{"${child_class}::ISA"}, $parent_class;
        use strict 'refs';
    }
}

sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    # Try loading Role.pm, but don't die if it doesn't exist
    eval { require Role };
    if (!$@) {
        *Class::with = \&Role::with;
        *Class::does = \&Role::does;
        no strict 'refs';
        *{"${caller}::with"} = \&Role::with;
        *{"${caller}::does"} = \&Role::does;
        use strict 'refs';
    }

    # Always install new and extends
    no strict 'refs';
    *{"${caller}::new"}     = \&Class::new;
    *{"${caller}::extends"} = \&Class::extends;
    use strict 'refs';

    # optional extends => Parent syntax
    if (@args && @args == 2 && $args[0] eq 'extends') {
        $class->extends($args[1]);
    }
}

=head1 DIAGNOSTICS

=over 4

=item * C<BUILD did not receive arguments!>

Your C<BUILD> method should always accept two arguments: the object
and a hashref of constructor arguments.

=item * C<Cannot find or load 'Role.pm'>

Ensure L<Role> is installed and available in C<@INC>.

=item * C<Cannot load parent class 'ParentClass': ...>

The class specified with C<extends => 'ParentClass'> could not be found
or loaded from its corresponding C<.pm> file in C<@INC>.

=back

=head1 LIMITATIONS

=over 4

=item * Only hash-based objects are supported.

=item * No attribute declaration or type constraints.

=item * No method modifiers (before/after/around).

=item * **C<BUILD> methods are not inherited or chained.**

=back

=head1 SEE ALSO

=over 4

=item * L<Role> - Companion role composition system

=item * L<Moo>, L<Moose>, L<Role::Tiny> - Heavier or alternative object systems

=back

=head1 AUTHOR

Mohammad Sajid Anwar, C<< <mohammad.anwar at yahoo.com> >>

=head1 REPOSITORY

L<https://github.com/manwar/Class-Mite>

=head1 BUGS

Please report any bugs or feature requests through the web interface at L<https://github.com/manwar/Class-Mite/issues>.
I will be notified and then you'll automatically be notified of progress on your
bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Class

You can also look for information at:

=over 4

=item * BUG Report

L<https://github.com/manwar/Class-Mite/issues>

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2025 Mohammad Sajid Anwar.

This program is free software; you can redistribute it and / or modify it under
the terms of the the Artistic License (2.0). You may obtain a copy of the full
license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified Versions is
governed by this Artistic License.By using, modifying or distributing the Package,
you accept this license. Do not use, modify, or distribute the Package, if you do
not accept this license.

If your Modified Version has been derived from a Modified Version made by someone
other than you,you are nevertheless required to ensure that your Modified Version
complies with the requirements of this license.

This license does not grant you the right to use any trademark, service mark,
tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge patent license
to make, have made, use, offer to sell, sell, import and otherwise transfer the
Package with respect to any patent claims licensable by the Copyright Holder that
are necessarily infringed by the Package. If you institute patent litigation
(including a cross-claim or counterclaim) against any party alleging that the
Package constitutes direct or contributory patent infringement,then this Artistic
License to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER AND
CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES. THE IMPLIED
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR
NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY YOUR LOCAL LAW. UNLESS
REQUIRED BY LAW, NO COPYRIGHT HOLDER OR CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE
OF THE PACKAGE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1; # End of Class
