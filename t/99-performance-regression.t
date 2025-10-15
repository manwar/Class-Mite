#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use Benchmark qw(timethis timethese);
use File::Spec;
use FindBin;
use Time::HiRes qw(time);

# Skip this test unless PERFORMANCE_TESTS environment variable is set
plan skip_all => 'Performance tests skipped. Set PERFORMANCE_TESTS=1 to run.'
    unless $ENV{PERFORMANCE_TESTS};

# Set up test classes (same as before)
package Test::Performance::Class {
    use Class;

    sub BUILD {
        my ($self, $args) = @_;
        $self->{processed} = 1;
        $self->{name} = $args->{name} if $args->{name};
    }

    sub custom_method {
        my $self = shift;
        return $self->{name} || 'default';
    }

    sub get_processed { $_[0]->{processed} }
}

package Test::Performance::ClassMore {
    use Class::More;

    has name => (default => 'default');
    has processed => (default => 0);

    sub BUILD {
        my ($self, $args) = @_;
        $self->{processed} = 1;
    }

    sub custom_method {
        my $self = shift;
        return $self->name;
    }
}

package Test::Performance::ClassInherit {
    use Class;

    sub BUILD {
        my ($self, $args) = @_;
        $self->{base_build} = 1;
    }

    sub base_method { "base" }
}

package Test::Performance::ClassChild {
    use Class;
    extends 'Test::Performance::ClassInherit';

    sub BUILD {
        my ($self, $args) = @_;
        $self->{child_build} = 1;
    }

    sub child_method { "child" }
}

package Test::Performance::ClassMoreInherit {
    use Class::More;

    has base_build => (default => 0);

    sub BUILD {
        my ($self, $args) = @_;
        $self->{base_build} = 1;
    }

    sub base_method { "base" }
}

package Test::Performance::ClassMoreChild {
    use Class::More;
    extends 'Test::Performance::ClassMoreInherit';

    has child_build => (default => 0);

    sub BUILD {
        my ($self, $args) = @_;
        $self->{child_build} = 1;
    }

    sub child_method { "child" }
}

package main;

my $ITERATIONS = 100000;

# Store individual timing results
my %timing_results;

sub run_highres_benchmark {
    my ($code, $iterations) = @_;
    $iterations ||= $ITERATIONS;

    # Warm up
    $code->() for 1..1000;

    my $start = time();
    $code->() for 1..$iterations;
    my $end = time();

    return $end - $start;
}

sub run_benchmarks {
    my %results;

    # Basic Object Creation
    diag "\n=== Benchmarking Basic Object Creation ($ITERATIONS iterations) ===";

    $timing_results{class_create} = run_highres_benchmark(sub {
        Test::Performance::Class->new(name => 'test');
    });

    $timing_results{class_more_create} = run_highres_benchmark(sub {
        Test::Performance::ClassMore->new(name => 'test');
    });

    diag sprintf "  Class:      %.4f seconds", $timing_results{class_create};
    diag sprintf "  Class::More: %.4f seconds", $timing_results{class_more_create};

    # Method Access
    diag "\n=== Benchmarking Method Access ($ITERATIONS iterations) ===";
    my $class_obj = Test::Performance::Class->new;
    my $class_more_obj = Test::Performance::ClassMore->new;

    $timing_results{class_access} = run_highres_benchmark(sub {
        $class_obj->custom_method;
    });

    $timing_results{class_more_access} = run_highres_benchmark(sub {
        $class_more_obj->custom_method;
    });

    diag sprintf "  Class:      %.4f seconds", $timing_results{class_access};
    diag sprintf "  Class::More: %.4f seconds", $timing_results{class_more_access};

    # Inheritance Performance
    diag "\n=== Benchmarking Inheritance ($ITERATIONS iterations) ===";

    $timing_results{class_inherit} = run_highres_benchmark(sub {
        Test::Performance::ClassChild->new(name => 'test');
    });

    $timing_results{class_more_inherit} = run_highres_benchmark(sub {
        Test::Performance::ClassMoreChild->new(name => 'test');
    });

    diag sprintf "  Class:      %.4f seconds", $timing_results{class_inherit};
    diag sprintf "  Class::More: %.4f seconds", $timing_results{class_more_inherit};

    # Calculate combined metrics for regression detection
    $results{basic_creation_time} = $timing_results{class_create};
    $results{method_access_time} = $timing_results{class_access};
    $results{inheritance_time} = $timing_results{class_inherit};

    return \%results;
}

sub calculate_performance_ratio {
    my ($class_time, $class_more_time) = @_;
    return 0 if $class_more_time <= 0;
    return $class_time / $class_more_time;
}

sub format_performance_comparison {
    my ($ratio, $operation) = @_;

    if ($ratio > 1) {
        return sprintf "  Class is %.1fx slower than Class::More for $operation", $ratio;
    } elsif ($ratio < 1 && $ratio > 0) {
        return sprintf "  Class is %.1fx faster than Class::More for $operation", 1/$ratio;
    } else {
        return "  Cannot compare performance for $operation (invalid ratio: $ratio)";
    }
}

sub save_performance_baseline {
    my ($results, $file) = @_;

    open my $fh, '>', $file or die "Cannot write baseline: $!";
    print $fh "# Performance baseline data - DO NOT EDIT MANUALLY\n";
    print $fh "# Generated on: " . scalar(localtime) . "\n";
    print $fh "# Iterations: $ITERATIONS\n\n";

    while (my ($key, $value) = each %$results) {
        print $fh "$key=$value\n";
    }

    while (my ($key, $value) = each %timing_results) {
        print $fh "individual_$key=$value\n";
    }

    close $fh;
    diag "Performance baseline saved to: $file";
}

sub load_performance_baseline {
    my ($file) = @_;
    return unless -f $file;

    my %baseline;
    open my $fh, '<', $file or return;
    while (<$fh>) {
        chomp;
        next if /^#/ || /^\s*$/;
        my ($key, $value) = split /=/, $_, 2;
        $baseline{$key} = $value if defined $value;
    }
    close $fh;

    return \%baseline;
}

# Main test logic
subtest 'Performance Regression Tests' => sub {
    my $baseline_file = File::Spec->catfile($FindBin::Bin, 'performance.baseline');
    my $current_results = run_benchmarks();

    # Load baseline if it exists
    my $baseline = load_performance_baseline($baseline_file);

    if ($baseline && %$baseline) {
        diag "\n=== Performance Comparison vs Baseline ===";

        # Check for significant regressions (more than 20% slower)
        my $regression_detected = 0;
        my @comparison_keys = qw(basic_creation_time method_access_time inheritance_time);

        foreach my $key (@comparison_keys) {
            my $current = $current_results->{$key};
            my $baseline_val = $baseline->{$key};

            if (defined $baseline_val && defined $current && $current > 0) {
                my $ratio = $current / $baseline_val;
                my $percent_change = ($ratio - 1) * 100;

                diag sprintf "%-25s: %7.4fs (baseline: %7.4fs) %+7.1f%%",
                    $key, $current, $baseline_val, $percent_change;

                # Fail test if performance degraded more than 20%
                if ($percent_change > 20) {
                    fail("Significant performance regression in $key: +$percent_change%");
                    $regression_detected = 1;
                } elsif ($percent_change < -20) {
                    diag "  -> Performance improvement detected!";
                    pass("$key performance improved");
                } else {
                    pass("$key performance within acceptable range (±20%)");
                }
            } else {
                diag "WARNING: Cannot compare $key - current: " .
                     (defined $current ? $current : 'undef') .
                     ", baseline: " .
                     (defined $baseline_val ? $baseline_val : 'undef');
            }
        }

        # Update baseline if requested
        if ($ENV{UPDATE_PERFORMANCE_BASELINE}) {
            save_performance_baseline($current_results, $baseline_file);
            diag "Performance baseline updated";
        }

        if (!$regression_detected && @comparison_keys) {
            pass("No significant performance regressions detected");
        }
    } else {
        # First run - create baseline
        diag "No performance baseline found or baseline is empty. Creating initial baseline...";
        save_performance_baseline($current_results, $baseline_file);
        pass("Initial performance baseline created");
    }

    # Performance ratio check (Class vs Class::More)
    diag "\n=== Class vs Class::More Performance Comparison ===";

    # Calculate performance ratios
    my $creation_ratio = calculate_performance_ratio(
        $timing_results{class_create},
        $timing_results{class_more_create}
    );

    my $access_ratio = calculate_performance_ratio(
        $timing_results{class_access},
        $timing_results{class_more_access}
    );

    my $inherit_ratio = calculate_performance_ratio(
        $timing_results{class_inherit},
        $timing_results{class_more_inherit}
    );

    diag "Performance Ratios:";
    diag format_performance_comparison($creation_ratio, "object creation");
    diag format_performance_comparison($access_ratio, "method access");
    diag format_performance_comparison($inherit_ratio, "inheritance");

    # Note: Class::More being slower is expected due to additional features
    diag "\nNote: Class::More provides additional features (attribute handling,";
    diag "      validation, etc.) so some performance difference is expected.";

    pass("Performance analysis completed");
};

done_testing;
