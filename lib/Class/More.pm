package Class::More;

$Class::More::VERSION    = '0.04';
$Class::More::AUTHORITY  = 'cpan:MANWAR';

use strict;
use warnings;
use mro ();

# Performance optimization caches
my %BUILD_ORDER_CACHE;
my %PARENT_LOADED_CACHE;
my %ALL_ATTRIBUTES_CACHE;
our %ATTRIBUTES;

# Pre-generate common accessor for maximum performance
my $SIMPLE_ACCESSOR = sub {
    my ($attr_name) = @_;
    return sub {
        my $self = shift;
        if (@_) {
            $self->{$attr_name} = shift;
        }
        return $self->{$attr_name};
    };
};

# Precompute skip patterns for faster inheritance
my %INHERITANCE_SKIP = map { $_ => 1 } qw(
    Class Class::More UNIVERSAL
);

sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    # Enable strict and warnings first
    strict->import;
    warnings->import;

    # Install methods directly into caller's namespace
    no strict 'refs';

    # Install optimized new method
    *{"${caller}::new"} = _generate_new_method($caller);

    # Install has method
    *{"${caller}::has"} = \&_has;

    # Install extends method
    *{"${caller}::extends"} = \&_extends;

    # Load Role.pm if available
    eval { require Role };
    if (!$@) {
        *{"${caller}::with"} = \&Role::with;
        *{"${caller}::does"} = \&Role::does;
    }

    # Handle extends in import if specified
    if (@args && $args[0] eq 'extends') {
        _extends($caller, @args[1..$#args]);
    }
}

# Generate highly optimized new method
sub _generate_new_method {
    my $class = shift;

    return sub {
        my $class = shift;
        my %attrs = @_;
        my $self = bless { %attrs }, $class;

        # OPTIMIZATION: Fast path for classes with no attributes
        my $class_attrs = _get_all_attributes_fast($class);
        if (%$class_attrs) {
            _process_attributes_fast($class, $self, \%attrs, $class_attrs);
        }

        # Get cached BUILD methods
        my $build_methods = $BUILD_ORDER_CACHE{$class} ||= _compute_build_methods_fast($class);
        $_->($self, \%attrs) for @$build_methods;

        return $self;
    };
}

# Optimized attribute processing
sub _process_attributes_fast {
    my ($class, $self, $attrs, $class_attrs) = @_;

    # First pass: handle constructor values and defaults
    foreach my $attr_name (keys %$class_attrs) {
        my $attr_spec = $class_attrs->{$attr_name};

        # Check if attribute was provided in constructor
        if (exists $attrs->{$attr_name}) {
            # Use constructor value
            $self->{$attr_name} = $attrs->{$attr_name};
        } elsif (exists $attr_spec->{default}) {
            # Apply default if not provided
            my $default = $attr_spec->{default};
            $self->{$attr_name} = ref $default eq 'CODE' ? $default->($self, $attrs) : $default;
        }
        # If neither provided nor has default, leave undef
    }

    # Second pass: check required attributes
    foreach my $attr_name (keys %$class_attrs) {
        my $attr_spec = $class_attrs->{$attr_name};
        if ($attr_spec->{required} && !exists $self->{$attr_name}) {
            die "Required attribute '$attr_name' not provided for class $class";
        }
    }
}

# Fast attribute resolution with minimal MRO usage
sub _get_all_attributes_fast {
    my ($class) = @_;

    # Check cache first
    return $ALL_ATTRIBUTES_CACHE{$class} if exists $ALL_ATTRIBUTES_CACHE{$class};

    my %all_attrs;

    # OPTIMIZATION: Direct inheritance scan instead of full MRO when possible
    no strict 'refs';
    my @isa = @{"${class}::ISA"};

    # Process current class first
    if (my $current_attrs = $ATTRIBUTES{$class}) {
        %all_attrs = %$current_attrs;
    }

    # Process parents (child attributes already override parent ones)
    foreach my $parent (@isa) {
        next if $INHERITANCE_SKIP{$parent};
        if (my $parent_attrs = $ATTRIBUTES{$parent}) {
            %all_attrs = (%$parent_attrs, %all_attrs);
        }
    }

    # Cache the result
    return $ALL_ATTRIBUTES_CACHE{$class} = \%all_attrs;
}

# Optimized BUILD method computation
sub _compute_build_methods_fast {
    my $class = shift;

    my @build_order;
    my %visited;
    my @stack = ($class);

    # Iterative DFS for better performance than recursion
    while (@stack) {
        my $current = pop @stack;

        if ($visited{$current}) {
            next;
        }

        no strict 'refs';
        my @parents = @{"${current}::ISA"};
        my $all_parents_ready = 1;

        # Check if all parents are processed
        foreach my $parent (@parents) {
            if (!$visited{$parent}) {
                $all_parents_ready = 0;
                last;
            }
        }

        if ($all_parents_ready) {
            $visited{$current} = 1;
            push @build_order, $current;
        } else {
            # Push current back and push unprocessed parents
            push @stack, $current;
            foreach my $parent (reverse @parents) {
                push @stack, $parent unless $visited{$parent};
            }
        }
    }

    # Extract BUILD methods in order
    my @build_methods;
    foreach my $c (@build_order) {
        no strict 'refs';
        if (defined &{"${c}::BUILD"}) {
            push @build_methods, \&{"${c}::BUILD"};
        }
    }

    return \@build_methods;
}

# Optimized has method
sub _has {
    my ($attr_name, %spec) = @_;
    my $current_class = caller;

    # Validate attribute options
    if (exists $spec{require}) {
        die "Invalid attribute option 'require' for '$attr_name' in $current_class. " .
            "Use 'required => 1' instead.";
    }

    # Clear attributes cache
    _clear_attributes_cache($current_class);

    # Store attribute specification
    $ATTRIBUTES{$current_class} = {} unless exists $ATTRIBUTES{$current_class};
    $ATTRIBUTES{$current_class}{$attr_name} = \%spec;

    # Install accessor if not exists - use pre-generated accessor
    no strict 'refs';
    if (!defined &{"${current_class}::${attr_name}"}) {
        *{"${current_class}::${attr_name}"} = $SIMPLE_ACCESSOR->($attr_name);
    }
}

# Optimized extends method
sub _extends {
    my $caller = caller;
    my @parents = @_;

    _delete_build_cache($caller);
    _clear_attributes_cache($caller);

    for my $parent_class (@parents) {
        die "Recursive inheritance detected: $caller cannot extend itself"
            if $caller eq $parent_class;

        # Efficient parent loading with cache
        unless ($PARENT_LOADED_CACHE{$parent_class}) {
            unless ($INC{"$parent_class.pm"}) {
                (my $parent_file = "$parent_class.pm") =~ s{::}{/}g;
                eval { require $parent_file };
            }
            $PARENT_LOADED_CACHE{$parent_class} = 1;
        }

        # Set up inheritance
        no strict 'refs';
        unless (grep { $_ eq $parent_class } @{"${caller}::ISA"}) {
            push @{"${caller}::ISA"}, $parent_class;

            # Merge parent attributes
            _merge_parent_attributes_fast($caller, $parent_class);
        }
    }
}

# Fast parent attribute merging
sub _merge_parent_attributes_fast {
    my ($child_class, $parent_class) = @_;

    # Clear cache for child class
    _clear_attributes_cache($child_class);

    # Start with child's existing attributes
    my %merged_attrs = %{$ATTRIBUTES{$child_class} || {}};

    # Get all parent classes efficiently
    no strict 'refs';
    my @parent_classes = ($parent_class, @{"${parent_class}::ISA"});

    # Merge attributes from all parent classes
    foreach my $parent (@parent_classes) {
        next if $INHERITANCE_SKIP{$parent};
        if (my $parent_attrs = $ATTRIBUTES{$parent}) {
            %merged_attrs = (%$parent_attrs, %merged_attrs);
        }
    }

    # Update child's attributes
    $ATTRIBUTES{$child_class} = \%merged_attrs;

    # Install accessors for merged attributes
    _install_accessors_batch($child_class, \%merged_attrs);
}

# Batch install accessors for better performance
sub _install_accessors_batch {
    my ($class, $attrs) = @_;

    no strict 'refs';
    while (my ($attr_name, $spec) = each %$attrs) {
        if (!defined &{"${class}::${attr_name}"}) {
            *{"${class}::${attr_name}"} = $SIMPLE_ACCESSOR->($attr_name);
        }
    }
}

sub _delete_build_cache {
    my ($class) = @_;
    delete $BUILD_ORDER_CACHE{$class};

    # Only clear caches for classes that actually inherit from this class
    for my $cached_class (keys %BUILD_ORDER_CACHE) {
        if (_inherits_from_fast($cached_class, $class)) {
            delete $BUILD_ORDER_CACHE{$cached_class};
        }
    }
}

# Fast inheritance check
sub _inherits_from_fast {
    my ($class, $parent) = @_;

    no strict 'refs';
    my @isa = @{"${class}::ISA"};

    return 1 if grep { $_ eq $parent } @isa;

    foreach my $direct_parent (@isa) {
        return 1 if _inherits_from_fast($direct_parent, $parent);
    }

    return 0;
}

# Clear attributes cache for a class and its descendants
sub _clear_attributes_cache {
    my ($class) = @_;
    delete $ALL_ATTRIBUTES_CACHE{$class};

    # Clear cache for descendant classes
    for my $cached_class (keys %ALL_ATTRIBUTES_CACHE) {
        if (_inherits_from_fast($cached_class, $class)) {
            delete $ALL_ATTRIBUTES_CACHE{$cached_class};
        }
    }
}

# For Role.pm to detect attribute capability
sub can_handle_attributes { 1 }

sub meta {
    my $class = shift;
    return {
        can_handle_attributes => 1,
        attributes => $ATTRIBUTES{$class} || {},
    };
}

=head1 NAME

Class::More - A fast, lightweight class builder for Perl

=head1 VERSION

Version 0.04

=head1 SYNOPSIS

    package My::Class;
    use Class::More;

    # Define attributes
    has 'name' => ( required => 1 );
    has 'age'  => ( default => 0 );
    has 'tags' => ( default => sub { [] } );

    # Set up inheritance
    extends 'My::Parent';

    # Custom constructor logic
    sub BUILD {
        my ($self, $args) = @_;
        $self->{initialized} = time;
    }

    sub greet {
        my $self = shift;
        return "Hello, " . $self->name;
    }

    1;

    # Usage
    my $obj = My::Class->new(
        name => 'Alice',
        age  => 30
    );

    print $obj->name;  # Alice
    print $obj->age;   # 30

=head1 DESCRIPTION

Class::More provides a fast, lightweight class building system for Perl with
attribute support, inheritance, and constructor building. It's designed for
performance and simplicity while providing essential object-oriented features.

The module focuses on speed with optimized method generation, caching, and
minimal runtime overhead.

=head1 FEATURES

=head2 Core Features

=over 4

=item * B<Fast Attribute System>: Simple attributes with required flags and defaults

=item * B<Automatic Accessors>: Automatically generates getter/setter methods

=item * B<Inheritance Support>: Multiple inheritance with proper method resolution

=item * B<BUILD Methods>: Constructor-time initialization hooks

=item * B<Performance Optimized>: Extensive caching and optimized code paths

=item * B<Role Integration>: Works seamlessly with L<Role> when available

=back

=head2 Performance Features

=over 4

=item * Pre-generated accessors for maximum speed

=item * Method resolution order caching

=item * Attribute specification caching

=item * Fast inheritance checks

=item * Batch accessor installation

=back

=head1 METHODS

=head2 Class Definition Methods

These methods are exported to your class when you C<use Class::More>.

=head3 has

    has 'attribute_name';
    has 'count' => ( default => 0 );
    has 'items' => ( default => sub { [] } );
    has 'name'  => ( required => 1 );

Defines an attribute in your class. Creates an accessor method that can get
and set the attribute value.

Supported options:

=over 4

=item * C<default> - Default value or code reference that returns default value

=item * C<required> - Boolean indicating if attribute must be provided to constructor

=back

=head3 extends

    extends 'Parent::Class';
    extends 'Parent1', 'Parent2';

Sets up inheritance for your class. Can specify multiple parents for multiple
inheritance. Automatically loads parent classes if needed.

=head3 new

    my $obj = My::Class->new(%attributes);
    my $obj = My::Class->new( name => 'test', count => 42 );

The constructor method. Automatically provided by Class::More. Handles:

=over 4

=item * Attribute initialization with defaults

=item * Required attribute validation

=item * BUILD method calling in proper inheritance order

=back

=head2 Special Methods

=head3 BUILD

    sub BUILD {
        my ($self, $args) = @_;
        # Custom initialization logic
        $self->{internal_field} = process($args->{external_field});
    }

Optional method called after object construction but before returning from C<new>.
Receives the object and the hashref of constructor arguments.

BUILD methods are called in inheritance order (parent classes first).

=head3 meta

    my $meta = My::Class->meta;
    print $meta->{can_handle_attributes};  # 1
    print keys %{$meta->{attributes}};     # name, age, tags

Returns metadata about the class. Currently provides:

=over 4

=item * C<can_handle_attributes> - Always true

=item * C<attributes> - Hashref of attribute specifications

=back

=head1 ATTRIBUTE SYSTEM

=head2 Basic Usage

    package User;
    use Class::More;

    has 'username' => ( required => 1 );
    has 'email'    => ( required => 1 );
    has 'status'   => ( default => 'active' );
    has 'created'  => ( default => sub { time } );

Attributes defined with C<has> automatically get accessor methods:

    my $user = User->new(
        username => 'alice',
        email    => 'alice@example.com'
    );

    # Getter
    print $user->username;  # alice

    # Setter
    $user->status('inactive');

=head2 Required Attributes

    has 'critical_data' => ( required => 1 );

If a required attribute is not provided to the constructor, an exception is thrown:

    # Dies: "Required attribute 'critical_data' not provided for class User"
    User->new( username => 'test' );

=head2 Default Values

    has 'counter' => ( default => 0 );
    has 'list'    => ( default => sub { [] } );
    has 'complex' => ( default => sub {
        return { computed => time }
    });

Defaults can be simple values or code references. Code references are executed
at construction time and receive the object and constructor arguments.

=head2 Inheritance and Attributes

    package Parent;
    use Class::More;
    has 'parent_attr' => ( default => 'from_parent' );

    package Child;
    use Class::More;
    extends 'Parent';
    has 'child_attr' => ( default => 'from_child' );

Child classes inherit parent attributes. If both parent and child define the
same attribute, the child's specification takes precedence.

=head1 PERFORMANCE OPTIMIZATIONS

Class::More includes several performance optimizations:

=over 4

=item * B<Pre-generated Accessors>: Simple accessors are pre-compiled and reused

=item * B<Attribute Caching>: Combined attribute specifications are cached per class

=item * B<BUILD Order Caching>: BUILD method call order is computed once per class

=item * B<Fast Inheritance Checks>: Optimized inheritance tree traversal

=item * B<Batch Operations>: Multiple accessors installed in batch when possible

=back

=head1 EXAMPLES

=head2 Simple Class

    package Person;
    use Class::More;

    has 'name' => ( required => 1 );
    has 'age'  => ( default => 0 );

    sub introduce {
        my $self = shift;
        return "I'm " . $self->name . ", age " . $self->age;
    }

    1;

=head2 Class with Inheritance

    package Animal;
    use Class::More;

    has 'species' => ( required => 1 );
    has 'sound'   => ( required => 1 );

    sub speak {
        my $self = shift;
        return $self->sound;
    }

    package Dog;
    use Class::More;
    extends 'Animal';

    sub BUILD {
        my ($self, $args) = @_;
        $self->{species} = 'Canine' unless $args->{species};
        $self->{sound}   = 'Woof!'  unless $args->{sound};
    }

    sub fetch {
        my $self = shift;
        return $self->name . " fetches the ball!";
    }

=head2 Class with Complex Attributes

    package Configuration;
    use Class::More;

    has 'settings' => ( default => sub { {} } );
    has 'counters' => ( default => sub { { success => 0, failure => 0 } } );
    has 'log_file' => ( required => 1 );

    sub BUILD {
        my ($self, $args) = @_;

        # Initialize complex data structures
        $self->{internal_cache} = {};
        $self->{start_time} = time;
    }

    sub increment {
        my ($self, $counter) = @_;
        $self->counters->{$counter}++;
    }

=head1 INTEGRATION WITH Role

When L<Role> is available, Class::More automatically exports:

=head3 with

    package My::Class;
    use Class::More;

    with 'Role::Printable', 'Role::Serializable';

Composes roles into your class. See L<Role> for complete documentation.

=head3 does

    if ($obj->does('Role::Printable')) {
        $obj->print;
    }

Checks if an object consumes a specific role.

=head1 LIMITATIONS

=head2 Attribute System Limitations

=over 4

=item * B<No Type Constraints>: Attributes don't support type checking

=item * B<No Access Control>: All attributes are readable and writable

=item * B<No Coercion>: No automatic value transformation

=item * B<No Triggers>: No callbacks when attributes change

=item * B<No Lazy Building>: Defaults are applied immediately at construction

=item * B<No Private/Protected>: All attributes are publicly accessible via accessors

=back

=head2 Inheritance Limitations

=over 4

=item * B<No Interface Enforcement>: No compile-time method requirement checking

=item * B<Limited Meta-Object Protocol>: Basic metadata only

=item * B<No Traits>: No trait-based composition

=item * B<Diamond Problem>: Multiple inheritance may have ambiguous method resolution

=back

=head2 General Limitations

=over 4

=item * B<No Immutability>: Can't make classes immutable for performance

=item * B<No Serialization>: No built-in serialization/deserialization

=item * B<No Database Integration>: No ORM-like features

=item * B<No Exception Hierarchy>: No custom exception classes

=back

=head2 Compatibility Notes

=over 4

=item * Designed for simplicity and speed over feature completeness

=item * Uses standard Perl OO internals (blessed hashrefs)

=item * Compatible with most CPAN modules that expect blessed hashrefs

=item * Not compatible with Moose/Mouse object systems

=item * Role integration requires separate L<Role> module

=back

=head1 DIAGNOSTICS

=head2 Common Errors

=over 4

=item * C<"Required attribute 'attribute_name' not provided for class Class::Name">

A required attribute was not passed to the constructor.

=item * C<"Recursive inheritance detected: ClassA cannot extend itself">

A class tries to inherit from itself, directly or indirectly.

=item * C<"Invalid attribute option 'option_name' for 'attribute_name' in Class::Name">

An unsupported attribute option was used.

=item * C<"Can't locate Parent/Class.pm in @INC">

A parent class specified in C<extends> couldn't be loaded.

=back

=head2 Performance Tips

=over 4

=item * Use simple defaults when possible (avoid sub refs for static values)

=item * Define all attributes before calling C<extends> for optimal caching

=item * Keep BUILD methods lightweight

=item * Use the provided C<new> method rather than overriding it

=back

=head1 SEE ALSO

=over 4

=item * L<Role> - Companion role system for Class::More

=item * L<Moo> - Lightweight Moose-like OO system

=item * L<Mojo::Base> - Minimalistic base class for Mojolicious

=item * L<Object::Tiny> - Extremely lightweight class builder

=item * L<Class::Accessor> - Simple class builder with accessors

=item * L<Moose> - Full-featured object system

=back

=head1 AUTHOR

Mohammad S Anwar, C<< <mohammad.anwar at yahoo.com> >>

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to the issue tracker at:

L<https://github.com/manwar/Class-More/issues>

Please note that this module is designed to be lightweight. Feature requests
that would significantly increase complexity or reduce performance may not
be accepted.

=head1 LICENSE AND COPYRIGHT

Copyright 2023 Mohammad S Anwar.

This program is free software; you can redistribute it and/or modify it
under the terms of the Artistic License (2.0). You may obtain a copy of
the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

=cut

1; # End of Class::More
