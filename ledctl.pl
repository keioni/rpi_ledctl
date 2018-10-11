#!/usr/bin/perl

	# On-board LED Controller for Raspberry Pi.

use strict;
	use warnings;
	use English;

	use constant SUCCEEDED => 0;
	use constant FAILED => 1;
	use constant DEFAULT_TIME_ACTIVE => 1000;
	use constant DEFAULT_LEDS_PATH => "/sys/class/leds";

	# LED definitions (for Raspberry Pi 2 Model B).
	my %defined_leds = (
		led0 => {
			display_name => 'Act',
			color => 'green',
			default_mode => 'mmc0',
			aliases => [ 'green', 'act', 'led0', '0' ],
		},
		led1 => {
			display_name => 'Power',
			color => 'red',
			default_mode => 'input',
			aliases => [ 'red', 'power', 'pwr', 'led1', '1' ],
		}
	);


sub verbose_print($)
{
	my $msg = shift;
	print $msg;
}


sub show_usage()
{
	print << '__USAGE__';
simple usage:

$ led.pl
   * show current LEDs status.
# led.pl <red|green>
   * set red/green LED mode to default.
# led.pl <red|green> <mode> [options...]
   * set red/green LED mode to <mode> with [options...]
     ref.) http://blog.livedoor.jp/victory7com/archives/43512294.html
__USAGE__

}


sub show_status()
{
	foreach my $led ( sort( keys( %defined_leds ) ) ) {
		my $trigger = DEFAULT_LEDS_PATH . "/$led/trigger";
		my $color = $defined_leds{$led}->{color};
		my $display_name = $defined_leds{$led}->{display_name};

		print "# $display_name LED ($color): $trigger\n";
		if ( -e $trigger ) {
			system( "cat $trigger" );
		} else {
			print "# WARNING: This LED is defined but does'nt exist!\n";
		}
		print "\n";
	}
}


sub setup_led($)
{
	my $requested_led = shift;

	foreach my $led ( keys( %defined_leds ) ) {
		my $r_alias = $defined_leds{$led}->{aliases};
		foreach my $alias_value (@$r_alias ) {
			if ( $requested_led eq $alias_value ) {
				return ( $led );
			}
		}
	}

	my $error = "Wrong LED name: '$requested_led'";
	return ( $requested_led, $error );
}


sub setup_mode(@)
{
	my $led = shift;
	my $mode = shift;

	my @options = ();
	my $error;

	# if mode doesn't defined...
	if ( ! $mode ) {
		$mode = 'default';
	}

	if ( $mode eq 'on' ) {
		# always on
		$mode = 'default-on';

	} elsif ( $mode eq 'off' ) {
		# always off
		$mode = 'none';

	} elsif ( $mode eq 'timer' ) {
		# timer mode
		# args: on-time(msec.) and off-time(msec.)
		my $time_active = shift;
		if ( ! $time_active ) {
			$time_active = DEFAULT_TIME_ACTIVE;
		}
		my $time_sleep = shift;
		if ( ! $time_sleep ) {
			$time_sleep = $time_active;
		}
		@options = ( $time_active, $time_sleep );

	} elsif ( $mode eq 'oneshot' ) {
		# one time lighting
		# arg: lighting time(msec.)
		my $time_active = shift;
		if ( ! $time_active ) {
			$time_active = DEFAULT_TIME_ACTIVE;
		}
		@options = ( $time_active );

	} elsif ( $mode eq 'gpio' ) {
		# light by gpio status
		# arg: gpio port number
		my $port_number = shift;
		if ( ! $port_number ) {
			$error = "GPIO port number is needed.";
		}
		@options = ( $port_number );

	} elsif ( $mode eq 'default' ) {
		# set to default mode
		$mode = $defined_leds{$led}->{default_mode};

	} else {
		# specified mode didn't define above, use as it is
		;
	}

	return ( $mode, \@options, $error );
}


sub execute($$$)
{
	my $led = shift;
	my $mode = shift;
	my $r_options = shift;

	my @operations = ();

	# set trigger operation
	push( @operations, [ 'trigger', $mode ] );

	# add options if needed
	if ( $mode eq 'oneshot' ) {
		push( @operations, [ 'delay_on', $r_options->[0] ] );
	} elsif ( $mode eq 'timer' ) {
		push( @operations, [ 'delay_on', $r_options->[0] ] );
		push( @operations, [ 'delay_off', $r_options->[1] ] );
	} elsif ( $mode eq 'gpio' ) {
		# XXX not tested yet. do test
		push( @operations, [ 'gpio', $r_options->[0] ] );
	}

	my $error;

	# execute operation(s)
	foreach my $r_op ( @operations ) {
		my ( $proc, $value ) = @$r_op;
		my $file = DEFAULT_LEDS_PATH . "/$led/$proc";

		&verbose_print( "$file >> $value" );
		if ( -e $file ) {
			if ( open( EXEC, ">", $file ) ) {
				print EXEC $value;
				close( EXEC );
				&verbose_print( " ... [OK]\n" );
			} else {
				&verbose_print( " ... [NG: Cannot open]\n" );
				&verbose_print( "Aborted.\n" );
				$error = "Cannot open: $file";
				last;
			}
		} else {
			&verbose_print( " ... [NG: File not exist]\n" );
			&verbose_print( "Aborted.\n" );
			$error = "File not exist: $file";
			last;
		}
	}

	return $error;
}


sub main()
{
	if ( @ARGV == 0 ) {
		&show_status();
		&show_usage();
		return SUCCEEDED;
	}

	my $error;

	# pick up target led
	my $led = shift @ARGV;
	( $led, $error ) = &setup_led( $led );
	if ( $error ) {
		print STDERR "$error\n";
		&show_usage();
		return FAILED;
	}

	# check mode
	my $mode = shift @ARGV;
	my $r_options;
	( $mode, $r_options, $error ) = &setup_mode( $led, $mode, @ARGV );
	if ( $error ) {
		print STDERR "$error\n";
		&show_usage();
		return FAILED;
	}

	# check privilege
	if ( $UID != 0 ) {
		print STDERR "Root privilege is required.\n";
		return FAILED;
	}

	# pull trigger and execute other operations
	$error = &execute( $led, $mode, $r_options );
	if ( $error ) {
		print STDERR "$error\n";
		return FAILED;
	}
	return SUCCEEDED;
}

&main();

