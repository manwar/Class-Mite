package Class;

$Class::VERSION    = '0.02';
$Class::AUTHORITY  = 'cpan:MANWAR';

=head1 NAME

Class - A lightweight constructor and BUILD hook system for Perl

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

    package MyApp::Base;
    use Class;

    sub get_id { shift->{id} }

    package MyApp::User;
    use Class extends => 'MyApp::Base'; # <--- New 'extends' support!
    with 'Loggable';                    # from Role.pm

    sub get_name {
        my $self = shift;
        return $self->{name};
    }

    sub BUILD {
        my ($self, $args) = @_;
        $self->{full_name} = $args->{name} . ' ' . $args->{surname};
        delete $self->{surname}; # cleanup after initialization
    }

    # later
    my $user = MyApp::User->new(
        name    => 'Jane',
        surname => 'Doe',
        id      => 42,
    );

    say $user->get_name;    # Jane
    say $user->{full_name}; # Jane Doe
    say $user->get_id;      # 42 (inherited from MyApp::Base)

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

=item * Exports the C<with> function into your class, allowing role consumption

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

Internal. Handles inheritance, ensures C<Role> is available and exports C<with> into the calling class.

=back

=head1 INTEGRATION WITH Role

C<Class> is designed to be used together with L<Role>. Classes that
C<use Class;> can consume roles defined with L<Role>. The C<with>
function is made available automatically.

=head1 INHERITANCE

The C<extends> key allows a class to inherit from a parent class using
Perl's standard C<@ISA> mechanism.

    package ChildClass;
    use Class extends => 'ParentClass';
    # ChildClass methods and attributes will override ParentClass's.

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

sub new {
    my $class = shift;
    my %attrs = @_;

    # 1. Bless the object using the attributes hash
    my $self = bless { %attrs }, $class;

    # 2. Check for and call the BUILD hook
    # Note: BUILD is not inherited, it's a class-specific hook.
    if ($self->can('BUILD')) {
        $self->BUILD({ %attrs });
    }

    return $self;
}

sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    no strict 'refs';

    # Parse arguments for 'extends'
    my %args = @args;
    my $parent_class = $args{extends};

    # 1. Handle inheritance via @ISA
    if (defined $parent_class) {
        # Check if the class is already in @ISA to avoid warnings,
        # though 'use' typically only runs once.
        unless (grep { $_ eq $parent_class } @{"${caller}::ISA"}) {
            push @{"${caller}::ISA"}, $parent_class;
        }
        # Attempt to load the parent class
        my $parent_file = $parent_class;
        $parent_file =~ s/::/\//g;
        $parent_file .= '.pm';
        eval {
            require $parent_file;
        };
        die "Cannot load parent class '$parent_class': $@" if $@;
    }

    # 2. Ensure 'Role' is loaded and its 'with' subroutine is available.
    eval "require Role";
    Role::_export_with($caller) if defined &{"Role::import"};
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
