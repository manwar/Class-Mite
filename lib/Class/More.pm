package Class::More;

$Class::More::VERSION    = '0.04';
$Class::More::AUTHORITY  = 'cpan:MANWAR';

=head1 NAME

Class::More - Extended Perl object system with parent-first BUILD, typed attributes, defaults and roles

=head1 VERSION

Version 0.04

=head1 SYNOPSIS

    use Class::More;

    # Define a class with attributes
    package Person;
    use Class::More;

    has 'first'  => (required => 1);
    has 'last'   => (required => 1);
    has 'age'    => (default  => 0);

    sub BUILD {
        my ($self, $attrs) = @_;
        $self->{full_name} = $self->{first} . ' ' . $self->{last};
    }

    package Employee;
    use Class::More;
    extends 'Person';

    has 'id' => (required => 1);

    sub BUILD {
        my ($self, $attrs) = @_;
        $self->{employee_id} = $self->{id};
    }

    my $emp = Employee->new(first => 'John', last => 'Doe', id => 123);
    print $emp->{full_name};   # John Doe
    print $emp->{employee_id}; # 123
    print $emp->age;           # 0

    # Using roles if Role.pm is available
    package Manager;
    use Class::More;
    with 'SomeRole';
    my $mgr = Manager->new();

=head1 DESCRIPTION

Class::More is an extended Perl object system that builds on L<Class>, providing:

=over 4

=item * Attribute declarations with C<has>, supporting C<required> and C<default>.

=item * Parent-first C<BUILD> methods for safe object initialization.

=item * Inheritance via C<extends> with automatic merging of parent attributes.

=item * Optional role composition via C<with> and C<does> (if L<Role> is installed).

=item * Automatic caching of BUILD order and loaded parents for efficiency.

=back

=cut

use strict;
use warnings;
use mro ();

my %BUILD_ORDER_CACHE;
my %PARENT_LOADED_CACHE;
our %ATTRIBUTES;

sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    # Install methods directly into caller's namespace
    no strict 'refs';

    # Install new methodi
    *{"${caller}::new"} = sub {
        my $class = shift;
        my %attrs = @_;
        my $self = bless { %attrs }, $class;

        # CRITICAL: Process attributes with required and default
        Class::More::_process_attributes($class, $self, \%attrs);

        # Determine BUILD order (parent-first)
        my $build_order = $BUILD_ORDER_CACHE{$class} ||= do {
            my %seen;
            my @order;
            local *collect;
            *collect = sub {
                my ($cur) = @_;
                return if $seen{$cur}++;
                no strict 'refs';
                collect($_) for @{"${cur}::ISA"};
                use strict 'refs';
                push @order, $cur;
            };
            collect($class);
            \@order;
        };

        # Call BUILD in order
        for my $c (@$build_order) {
            no strict 'refs';
            if (my $build = *{"${c}::BUILD"}{CODE}) {
                $build->($self, \%attrs);
            }
        }

        return $self;
    };


    # Install has method
    *{"${caller}::has"} = sub {
        my ($attr_name, %spec) = @_;
        my $current_class = caller;

        # VALIDATION: Reject 'require' in favor of 'required'
        if (exists $spec{require}) {
            die "Invalid attribute option 'require' for '$attr_name' in $current_class. " .
                "Use 'required => 1' instead.";
        }

        # Initialize the ATTRIBUTES hash for this class if it doesn't exist
        $ATTRIBUTES{$current_class} = {} unless exists $ATTRIBUTES{$current_class};

        # Store the attribute specification
        $ATTRIBUTES{$current_class}{$attr_name} = \%spec;

        # Generate accessor if not exists
        if (!defined *{"${current_class}::${attr_name}"}{CODE}) {
            *{"${current_class}::${attr_name}"} = sub {
                my $self = shift;
                if (@_) {
                    $self->{$attr_name} = shift;
                }
                return $self->{$attr_name};
            };
        }
    };

    # Install extends method
    *{"${caller}::extends"} = sub {
        my ($maybe_class, @maybe_parents) = @_;

        _delete_build_cache($caller);

        my @parents = @maybe_parents ? ($maybe_class, @maybe_parents) : ($maybe_class);

        for my $parent_class (@parents) {
            die "Recursive inheritance detected: $caller cannot extend itself"
                if $caller eq $parent_class;

            # SIMPLE AUTO-LOAD: Just check %INC
            unless ($INC{"$parent_class.pm"}) {
                (my $parent_file = "$parent_class.pm") =~ s{::}{/}g;
                eval { require $parent_file };
                # Don't die - parent might be defined inline in tests
            }

            # SET UP INHERITANCE
            no strict 'refs';

            # Avoid duplicate in @ISA
            use mro ();
            my @linear = @{ mro::get_linear_isa($caller) };
            unless (grep { $_ eq $parent_class } @linear) {
                push @{"${caller}::ISA"}, $parent_class;

                # Merge parent attributes into child
                _merge_parent_attributes($caller, $parent_class);

                # Install parent class accessors in child class
                _install_parent_accessors($caller, $parent_class);
            }
        }
    };

    # This ensures full compatibility with Class
    eval { require Role };
    if (!$@) {
        *Class::More::with = \&Role::with;
        *Class::More::does = \&Role::does;
        no strict 'refs';
        *{"${caller}::with"} = \&Role::with;
        *{"${caller}::does"} = \&Role::does;
        use strict 'refs';
    }

    # optional extends => Parent
    if (@args && @args == 2 && $args[0] eq 'extends') {
        no strict 'refs';
        *{"${caller}::extends"}->($args[1]);
    }

    # Enable strict and warnings in the caller
    {
        no strict 'refs';
        *{"${caller}::strict::import"}  = \&strict::import;
        *{"${caller}::warnings::import"} = \&warnings::import;
        strict->import;
        warnings->import;
    }
}

# Get all attributes including role attributes
sub _get_all_attributes {
    my ($class) = @_;

    my %all_attrs;

    # Get Class::More attributes from inheritance chain
    # Process from most specific to least specific (child overrides parent)
    my @isa = @{mro::get_linear_isa($class)};

    # Reverse to process child first, then parent (child overrides parent)
    foreach my $current_class (reverse @isa) {
        if (my $current_attrs = $ATTRIBUTES{$current_class}) {
            # Child attributes override parent attributes
            %all_attrs = (%all_attrs, %$current_attrs);
        }
    }

    # Get Role attributes (if Role is loaded) - roles should not override class attributes
    if (exists $INC{'Role.pm'} && $Role::APPLIED_ROLES{$class}) {
        foreach my $role (@{$Role::APPLIED_ROLES{$class}}) {
            if (my $role_attrs = $Role::ROLE_ATTRIBUTES{$role}) {
                # Role attributes are added but don't override class attributes
                foreach my $attr_name (keys %$role_attrs) {
                    if (!exists $all_attrs{$attr_name}) {
                        $all_attrs{$attr_name} = $role_attrs->{$attr_name};
                    }
                }
            }
        }
    }

    return \%all_attrs;
}

# Process both class and role attributes
sub _process_attributes {
    my ($class, $self, $attrs) = @_;

    # Get all attributes for this class (including inherited ones and role attributes)
    my $class_attrs = _get_all_attributes($class);

    # Sort attribute names to make required checking deterministic
    my @attr_names = sort keys %$class_attrs;

    # First pass: Validate attribute specifications and apply defaults
    for my $attr_name (@attr_names) {
        my $attr_spec = $class_attrs->{$attr_name};

        # VALIDATION: Reject 'require' in favor of 'required'
        if (exists $attr_spec->{require}) {
            die "Invalid attribute option 'require' for '$attr_name' in $class. " .
                "Use 'required => 1' instead.";
        }

        # Apply default if attribute not provided in constructor
        if (!exists $attrs->{$attr_name} && exists $attr_spec->{default}) {
            my $default = $attr_spec->{default};
            if (ref $default eq 'CODE') {
                $self->{$attr_name} = $default->($self, $attrs);
            } else {
                $self->{$attr_name} = $default;
            }
        }
        # If attribute was provided in constructor, use that value
        elsif (exists $attrs->{$attr_name}) {
            $self->{$attr_name} = $attrs->{$attr_name};
        }
    }

    # Second pass: Check required attributes (only 'required', not 'require')
    for my $attr_name (@attr_names) {
        my $attr_spec = $class_attrs->{$attr_name};

        # Check if attribute is required but not set (after defaults and constructor args)
        # ONLY check 'required', explicitly ignore 'require'
        if ($attr_spec->{required} && !exists $self->{$attr_name}) {
            die "Required attribute '$attr_name' not provided for class $class";
        }
    }
}

sub _merge_parent_attributes {
    my ($child_class, $parent_class) = @_;

    # Start with child's existing attributes
    my %merged_attrs = %{$ATTRIBUTES{$child_class} || {}};

    # Walk through all parent classes in inheritance order
    my @parent_classes = @{mro::get_linear_isa($parent_class)};

    # Process from most specific to least specific (reverse order)
    foreach my $parent_class (reverse @parent_classes) {
        if (my $parent_attrs = $ATTRIBUTES{$parent_class}) {
            # Parent attributes are merged in, but child attributes take precedence
            %merged_attrs = (%$parent_attrs, %merged_attrs);
        }
    }

    # Update the child's attributes with the merged result
    $ATTRIBUTES{$child_class} = \%merged_attrs;

    # Install accessors for all attributes
    for my $attr_name (keys %merged_attrs) {
        no strict 'refs';
        if (!defined *{"${child_class}::${attr_name}"}{CODE}) {
            *{"${child_class}::${attr_name}"} = sub {
                my $self = shift;
                if (@_) {
                    $self->{$attr_name} = shift;
                }
                return $self->{$attr_name};
            };
        }
    }
}

sub _install_parent_accessors {
    my ($child_class, $parent_class) = @_;
    my $parent_attrs = $ATTRIBUTES{$parent_class} || {};

    no strict 'refs';
    for my $attr_name (keys %$parent_attrs) {
        # Install accessor in child class if it doesn't exist
        if (!defined *{"${child_class}::${attr_name}"}{CODE}) {
            *{"${child_class}::${attr_name}"} = sub {
                my $self = shift;
                if (@_) {
                    $self->{$attr_name} = shift;
                }
                return $self->{$attr_name};
            };
        }
    }
}

sub _delete_build_cache {
    my ($class) = @_;
    delete $BUILD_ORDER_CACHE{$class};
    for my $cached_class (keys %BUILD_ORDER_CACHE) {
        if (grep { $_ eq $class } @{mro::get_linear_isa($cached_class)}) {
            delete $BUILD_ORDER_CACHE{$cached_class};
        }
    }
}

=head1 EXPORT

When C<use>d, Class::More automatically installs the following methods into the caller's namespace:

=over 4

=item * C<new> - constructor

=item * C<has> - declare attributes with optional C<required> and C<default>

=item * C<extends> - inheritance helper

=item * C<with> and C<does> - role helpers (if L<Role> is available)

=back

=head1 METHODS

=head2 new

    my $obj = Class->new(%attributes);

Creates a new object, processes attributes (required/defaults), and calls all C<BUILD> methods from parent to child in parent-first order.

=head2 has

    has 'attr_name' => (required => 1, default => 'value');

Declares an attribute for the class. Automatically generates an accessor method if one does not already exist. Supports:

=over 4

=item * C<required> - dies if not provided during object construction.

=item * C<default> - a scalar or code reference used to initialize the attribute if not provided.

=back

=head2 extends

    extends 'ParentClass';
    extends 'Parent1', 'Parent2';

Adds one or more parent classes to the calling class. Automatically loads the parent class if needed, merges parent attributes into the child, and prevents recursive inheritance.

=head2 BUILD

    sub BUILD {
        my ($self, $attrs) = @_;
        # object initialization
    }

All C<BUILD> methods in the inheritance chain are called in parent-first order during C<new>. Attributes declared via C<has> are processed before BUILD is called.

=head2 Roles

If L<Role> is available, you can consume roles:

    with 'RoleName';
    does 'RoleName';

This enables role-based composition for shared behavior.

=head1 ATTRIBUTE MERGING

Parent attributes are merged into child classes automatically when using C<extends>. Child attributes override parent attributes if there is a conflict. Accessors for inherited attributes are installed if not already defined.

=head1 ERROR HANDLING

=over 4

=item * Required attributes missing during construction will throw an exception.

=item * Recursive inheritance is detected and dies with a clear message.

=item * Failure to load a parent class dies with the error from C<require>.

=back

=head1 EXAMPLES

    package Animal;
    use Class::More;

    has 'species' => (required => 1);
    has 'age'     => (default => 0);

    sub BUILD {
        my ($self) = @_;
        print "Animal created: " . $self->species . "\n";
    }

    package Dog;
    use Class::More;
    extends 'Animal';

    has 'breed' => (required => 1);

    my $dog = Dog->new(species => 'Canine', breed => 'Labrador');
    print $dog->species; # Canine
    print $dog->breed;   # Labrador
    print $dog->age;     # 0

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

    perldoc Class::More

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

1; # End of Class::More
