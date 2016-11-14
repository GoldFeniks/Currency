use v5.24;
package Date {

	use Scalar::Util 'looks_like_number';

	use overload 
		'""' => \&to_string,
		'<=>' => \&compare,
		'+' => \&add,
		'-' => \&sub,
		'0+' => \&days;

	my @month_days = qw(0 31 28 31 30 31 30 31 31 30 31 30 31);
	my @month_names = qw(January February March April May June July August September October November December);
	my @weekdays = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);

	my $calculateWeekday = sub {
		my $date = shift;
		my ($d, $m, $y) = ($date->{day}, $date->{month}, $date->{year});
		$y -= 1 if $m < 3;
		$m = $m != 2 ? ($m - 2) % 12 : 12;
		($d + int(2.6 * $m - 0.2) + 5 * ($y % 4) + 4 * ($y % 100) + 6 * ($y % 400)) % 7;
	};

	my $calculateDate = sub {
		my $g = shift;
		my $y = int((10000 * $g + 14780) / 3652425);
		my $ddd = 0;
		$y -= 1 while (($ddd = $g - (365 * $y + int($y / 4) - int($y / 100) + int($y / 400))) < 0);
		my $mi = int((100 * $ddd + 52) / 3060);
		my $mm = ($mi + 2) % 12 + 1;
		$y = $y + int(($mi + 2) / 12);
		my $dd = $ddd - int(($mi * 306 + 5) / 10) + 1;
		my $date = { day => $dd, month => $mm, year => $y };
		$date->{weekday} = $calculateWeekday->($date);
		return $date;
	};

	my $isLeap = sub {
		my $year = shift;
		$year % 4 == 0 && ($year % 100 != 0 || $year % 400 == 0);
	};

	my $checkDate = sub {
		my $date = shift;
		my ($d, $m, $y) = ($date->{day}, $date->{month}, $date->{year});
		die "Wrong month $m" if $m < 1 || $m > 12;
		die "Wrong day $d" if $d < 1 || $d > $month_days[$m] + ($m == 2 && $isLeap->($y));
	};

	my $calculateDays = sub {
		my $date = shift;
		my ($d, $m, $y) = ($date->{day}, $date->{month}, $date->{year});
		$m = ($m + 9) % 12;
		$y = $y - int($m / 10);
		365 * $y + int($y / 4) - int($y / 100) + int($y / 400) + int(($m * 306 + 5) / 10) + $d - 1;
	};

	my $setDateValue = sub {
		my ($self, $date, $name, $value) = @_;
		die "\"$value\" is not a number" if !looks_like_number($value);
		$self->{date} = undef;
		$date->{$name} = $value;
		$checkDate->($date);
		$self->days($calculateDays->($date));
		$self->{date} = $calculateDate->($self->days);
	};

	sub INIT {
		no strict 'refs';
		for my $name (qw(day month weekday)) {
			*$name = sub {
				my ($self, $value) = @_;
				$self->{date} = $calculateDate->($self->days) if !defined $self->{date};
				$setDateValue->($self, $self->{date}, $name, $value) if (defined $value);
				$self->{date}->{$name};		
			};
		}
	}

	sub year {
		my ($self, $value) = @_;
		$self->{date} = $calculateDate->($self->days) if !defined $self->{date};
		if (defined $value) {
			die "\"$value\" is not a number" if !looks_like_number($value);
			die "Wrong year 0" if $value == 0;
			$setDateValue->($self, $self->{date}, 'year', $value + ($value < 0 ? 1 : 0));
		}
		my $result = $self->{date}->{year};
		$result - ($result <= 0 ? 1 : 0);		
	}

	sub new {
		my($class, $value) = @_;
		my $self = { date => undef, days => 0 };
		bless $self, $class;
		$self->set($value);
	}

	sub set {
		my ($self, $other) = @_;
		die "Can't construct date without parameter" if !defined $other;
		if (ref(\$other) eq 'SCALAR') {
			if ($other =~ /^-?\d+\z/) {
				$self->days($other);
			}
			else {
				die "\"$other\" has wrong format" if !($other =~ /^(-?\d+)\.(-?\d+)\.(-?\d+)/);
				die 'Wrong year 0' if $3 == 0;
				my $date = { day => $1, month => $2, year => $3 + ($3 < 0 ? 1 : 0) };
				$checkDate->($date);
				$self->days($calculateDays->($date));
			}
		}
		elsif (ref($other) eq 'Date') {
			$self->days($other->days);
		}
		else {
			die "Can't use \"$other\" as date";
		}
		$self;
	}

	sub to_string {
		my $self = shift;
		(length $self->day == 2 ? $self->day : ('0'.$self->day)) . '.' . (length $self->month == 2 ? $self->month : ('0' . $self->month)) . '.' . $self->year;
	}

	sub compare {
		my ($self, $other) = @_;
		$self->days <=> $other->days;
	}

	sub add {
		my ($self, $other) = @_;
		die "\"$other\" is not a number" if !looks_like_number($other);
		my $result = Date->new($self);
		$result->days($result->days + $other);
		$result;
	}

	sub sub {
		my ($self, $other) = @_;
		if (ref($other) eq 'Date') {
			return $self->days - $other->days;
		}
		$self->add(-$other);	
	}

	sub days {
		my ($self, $value) = @_;
		if (defined $value) {
			$self->{days} = $value;
			$self->{date} = undef;
		}
		$self->{days};
	}

	sub addYears {
		my ($self, $value) = @_;
		die "\"$value\" is not a number" if !looks_like_number($value);
		my $date = {day => $self->day, month => $self->month, year => $self->year + $value + ($self->year < 0 ? 1 : 0)};
		$self->days($calculateDays->($date));
		$self;
	}

	sub addMonths {
		my ($self, $value) = @_;
		die "\"$value\" is not a number" if !looks_like_number($value);
		my $inc_years = int($value < 0 ? ($self->month + $value - 12) / 12 : ($self->month + $value) / 12);
		my $months = ($self->month + $value + ($value < 0 ? -1 : 1)) % 12;
		$self->days($calculateDays->({day => $self->day, month => $months, year => $self->year + $inc_years}));
		$self;
	}

	sub isLeap {
		my $self = shift;
		$isLeap->($self->year);
	}

	sub weekdayName {
		my $self = shift;
		$weekdays[$self->weekday];
	}

	sub monthName {
		my $self = shift;
		$month_names[$self->month - 1];
	}

	1;
}