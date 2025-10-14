package Class::Clone;

$Class::Clone::VERSION    = '0.03';
$Class::Clone::AUTHORITY  = 'cpan:MANWAR';

use strict;
use warnings;

sub import {
    my ($class, @args) = @_;
    my $caller = caller(0);

    no strict 'refs';

    # Install clone method if not already defined
    if (!defined &{"${caller}::clone"}) {
        *{"${caller}::clone"} = sub {
            my $self = shift;
            my %attrs = (%$self, @_);
            return ref($self)->new(%attrs);
        };
    }
}

1;

__END__

=head1 NAME

Class::Clone - Add clone method to Class-based classes

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

    package My::Class;
    use Class;
    use Class::Clone;

    has name => (required => 1);
    has age  => (default => 0);

    package main;
    my $original = My::Class->new(name => 'John', age => 30);
    my $clone = $original->clone;
    my $modified = $original->clone(name => 'Jane', age => 25);

=head1 DESCRIPTION

Provides a C<clone> method that creates a shallow copy of objects.
Accepts optional attribute overrides.

=cut
