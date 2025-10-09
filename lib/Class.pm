package Class;

$Class::VERSION   = '0.02';
$Class::AUTHORITY = 'cpan:MANWAR';

=head1 NAME

Class - Lightweight Perl object system with parent-first BUILD and optional roles

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

    use Class;

    # Simple class with attributes and BUILD
    package Person;
    use Class;

    sub BUILD {
        my ($self, $attrs) = @_;
        $self->{full_name} = $attrs->{first} . ' ' . $attrs->{last};
    }

    package Employee;
    use Class;
    extends 'Person';

    sub BUILD {
        my ($self, $attrs) = @_;
        $self->{employee_id} = $attrs->{id};
    }

    # Create an object
    my $emp = Employee->new(first => 'John', last => 'Doe', id => 123);

    print $emp->{full_name};   # John Doe
    print $emp->{employee_id}; # 123

    # Using roles if Role.pm is available
    package Manager;
    use Class;
    with 'SomeRole';
    my $mgr = Manager->new();

=head1 DESCRIPTION

Class provides a lightweight Perl object system with:

=over 4

=item * Parent-first constructor building via C<BUILD> methods.

=item * Simple inheritance via C<extends>.

=item * Optional role consumption via C<with> and C<does> (if C<Role> module is available).

=item * Automatic caching of BUILD order for efficient object creation.

=back

=head1 EXPORT

The following functions are exported by default:

=over 4

=item * C<extends>

=item * C<with> (if Role.pm is available)

=item * C<does> (if Role.pm is available)

=back

=cut

use strict;
use warnings;
use Exporter;
use mro ();

our @EXPORT = qw(extends with does);
our @ISA    = qw(Exporter);

my %BUILD_ORDER_CACHE;
my %BUILD_METHODS_CACHE;
my %PARENT_LOADED_CACHE;

sub new {
    my $class = shift;
    my %attrs = @_;
    my $self = bless { %attrs }, $class;

    my $build_methods = $BUILD_METHODS_CACHE{$class} ||= _compute_build_methods($class);
    $_->($self, \%attrs) for @$build_methods;

    return $self;
}

sub _compute_build_methods {
    my $class = shift;

    my %seen;
    my @parent_first;
    my @stack = ($class);

    # Iterative DFS that ensures true parent-first order
    while (@stack) {
        my $current = pop @stack;

        if ($seen{$current}) {
            # If we've seen it but it's not in order yet, skip
            next;
        }

        # Check if all parents are already processed or in order
        no strict 'refs';
        my @parents = @{"${current}::ISA"};
        my $all_parents_ready = 1;

        foreach my $parent (@parents) {
            if (!$seen{$parent}) {
                $all_parents_ready = 0;
                last;
            }
        }

        if ($all_parents_ready) {
            # All parents are processed, we can add this class
            $seen{$current} = 1;
            push @parent_first, $current;
        } else {
            # Push current back and push unprocessed parents
            push @stack, $current;
            foreach my $parent (reverse @parents) {
                push @stack, $parent unless $seen{$parent};
            }
        }
    }

    # Get BUILD methods in parent-first order
    my @build_methods;
    foreach my $c (@parent_first) {
        no strict 'refs';
        if (my $build = *{"${c}::BUILD"}{CODE}) {
            push @build_methods, $build;
        }
    }

    return \@build_methods;
}

sub extends {
    my ($maybe_class, @maybe_parents) = @_;
    my $child_class = caller;

    delete_build_cache($child_class);

    my @parents = @maybe_parents ? ($maybe_class, @maybe_parents) : ($maybe_class);

    no strict 'refs';

    for my $parent_class (@parents) {
        die "Recursive inheritance detected: $child_class cannot extend itself"
            if $child_class eq $parent_class;

        # Link inheritance if not already linked
        push @{"${child_class}::ISA"}, $parent_class
            unless grep { $_ eq $parent_class } @{"${child_class}::ISA"};

        # --- Copy parent methods into child for performance ---
        my $parent_symtab = \%{"${parent_class}::"};
        for my $method (keys %$parent_symtab) {
            next if $method =~ /^(?:BUILD|new|extends|with|does|import|AUTOLOAD|DESTROY|BEGIN|END)$/;
            next if $method =~ /^_/;
            next if $method eq 'ISA' || $method eq 'VERSION' || $method eq 'EXPORT' || $method eq 'AUTHORITY';
            next if $method =~ /::$/;  # Skip nested packages

            # Only copy if not already defined
            if (!defined &{"${child_class}::${method}"} && defined &{"${parent_class}::${method}"}) {
                *{"${child_class}::${method}"} = \&{"${parent_class}::${method}"};
            }
        }

        # Set MRO to C3 for correct linearization
        mro::set_mro($child_class, 'c3');
    }
}

sub delete_build_cache {
    my ($class) = @_;
    delete $BUILD_ORDER_CACHE{$class};
    for my $cached_class (keys %BUILD_ORDER_CACHE) {
        if (grep { $_ eq $class } @{mro::get_linear_isa($cached_class)}) {
            delete $BUILD_ORDER_CACHE{$cached_class};
        }
    }
}

sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    # Enable strict and warnings in the caller
    {
        no strict 'refs';
        *{"${caller}::strict::import"}  = \&strict::import;
        *{"${caller}::warnings::import"} = \&warnings::import;
        strict->import;
        warnings->import;
    }

    # Load Role.pm if exists
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

    # optional extends => Parent
    if (@args && @args == 2 && $args[0] eq 'extends') {
        $class->extends($args[1]);
    }
}

=head1 METHODS

=head2 new

    my $obj = Class->new(%attributes);

Constructs a new object of the class, calling all C<BUILD> methods from parent classes in parent-first order. All attributes are passed to C<BUILD> as a hashref.

=head2 extends

    extends 'ParentClass';
    extends 'Parent1', 'Parent2';

Adds one or more parent classes to the calling class. Automatically loads the parent class if not already loaded and prevents recursive inheritance. Duplicate parents are ignored.

=head1 IMPORT

    use Class;
    use Class 'extends' => 'Parent';

When imported, Class automatically installs the following functions into the caller's namespace:

=over 4

=item * C<new> - constructor

=item * C<extends> - inheritance helper

=item * C<with> and C<does> - if Role.pm is available

=back

Optionally, you can specify C<extends> in the import statement to immediately set a parent class:

    use Class 'extends' => 'Parent';

=head1 BUILD METHODS

Classes can define a C<BUILD> method:

    sub BUILD {
        my ($self, $attrs) = @_;
        # initialize object
    }

All BUILD methods in the inheritance chain are called in parent-first order, ensuring proper initialization.

=head1 ROLES

If a C<Role> module is available, you can consume roles via:

    with 'RoleName';
    does 'RoleName';

This provides role-based composition for shared behavior.

=head1 CACHING

Class uses internal caches to optimize object construction:

=over 4

=item * %BUILD_ORDER_CACHE - caches linearized parent-first build order.

=item * %PARENT_LOADED_CACHE - ensures parent classes are loaded only once.

=back

Caches are automatically updated when C<extends> is called.

=head1 ERROR HANDLING

=over 4

=item * Recursive inheritance is detected and throws an exception.

=item * Failure to load a parent class dies with a meaningful error.

=back

=head1 EXAMPLES

    package Animal;
    use Class;

    sub BUILD {
        my ($self, $attrs) = @_;
        $self->{species} = $attrs->{species};
    }

    package Dog;
    use Class;
    extends 'Animal';

    sub BUILD {
        my ($self, $attrs) = @_;
        $self->{breed} = $attrs->{breed};
    }

    my $dog = Dog->new(species => 'Canine', breed => 'Labrador');
    print $dog->{species}; # Canine
    print $dog->{breed};   # Labrador

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
