use v5.24;
use HTML::TableExtract;
use HTTP::Request;
use LWP::UserAgent;
use GD::Text;
use GD::Graph;
use GD::Graph::lines;
use List::Util qw(min max);
use POSIX qw(ceil);
use JSON::Parse qw(parse_json);
use Data::Dumper;
use Date;

my $help = '
 -h                         Show help

 -s[source_name[,...]]      Sources select
                              Available sources:
                                cb - Central Bank of Russia
                                yh - Yahoo finance
                                fx - fixer.io (European Central Bank)
                              Default: cb

 -f[file_name[,...]]        Specify file name
                              Default: file[index of source].png

 -c[currency_name[,...]]    Currencies select
                              Supported currencies:
                                cb: USD, EUR, JPY, CNY, GBP, UAH
                                yh: visit finance.yahoo.com
                                fx: visit fixer.io
                              Default: USD

 -d[dd.mm.yyyy,dd.mm.yyyy]  Specify date range
                              Default: 01.01.2015,01.02.2015
';

my %plan = (
	sources => [\&cb],
	date => {
		start => Date->new('01.01.2015'),
		end => Date->new('01.02.2015')
	},
	files => [],
	currency => {
		from => 'RUB',
		to => ['USD'],
	}
);

my %cb_names = (
	USD => 'R01235',
	EUR => 'R01239',
	JPY => 'R01820',
	CNY => 'R01375',
	GBP => 'R01035',
	UAH => 'R01720',
);

my %sources = (
	cb => \&cb,
	yh => \&yh,
	fx => \&fx,
);

my %mult = (
	JPY => 100,
	CNY => 10,
	UAH => 10,
);

sub cb {
	my $data = [];
	for (@{$plan{currency}->{to}}) {
		next if !defined $cb_names{$_};
		my $url = "https://www.cbr.ru/currency_base/dynamics.aspx?VAL_NM_RQ=$cb_names{$_}\&date_req1=$plan{date}->{start}\&date_req2=$plan{date}->{end}\&rt=1\&mode=1";
		my $te = HTML::TableExtract->new( attribs => { class => 'data' } )->parse(request($url));
		my ($values, $dates, $currency) = ([], [], $_);
		for ($te->tables) {
			for (@{$_->rows}[1..$#{$_->rows}]) {
				push @{$dates}, $_->[0];
				$_->[2] =~ s/,/./;
				push @{$values}, $_->[2] * ($mult{$currency} // 1) / $_->[1];
			}
		}
		push @{$data}, $dates if !defined($data->[0]);
		push @{$data}, $values;
	}
	save_graph($data, $_[0]);
};

sub json_parse_yh {
	my $json = parse_json(shift);
	return undef if $json->{error} || !defined $json->{query}->{results};
	my @data = ([], []);
	for (reverse @{$json->{query}->{results}->{quote}}) {
		$_->{Date} =~ s/(\d+)\-(\d+)\-(\d+)/$3\.$2\.$1/;
		push @{$data[0]}, $_->{Date};
		push @{$data[1]}, $_->{Close};
	}
	\@data;
} 

sub yh_url {
	my ($start_date, $end_date, $currency) = @_;
	$start_date =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
	$end_date =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
	"https://query.yahooapis.com/v1/public/yql?q=select Date, Close from yahoo.finance.historicaldata 
		where symbol = \"$currency=X\" and startDate = \"$start_date\" and endDate = \"$end_date\"&format=json&env=store://datatables.org/alltableswithkeys";
}

sub yh {
	my $data = [];
	my $usdrub = json_parse_yh(request(yh_url($plan{date}->{start}, $plan{date}->{end}, $plan{currency}->{from})));
	push @{$data}, $usdrub->[0];
	for (@{$plan{currency}->{to}}) {
		push @{$data}, $usdrub->[1] and next if /USD/;
		my $res = json_parse_yh(request(yh_url($plan{date}->{start}, $plan{date}->{end}, $_))) // next;
		my $currency = $_;
		$res->[1]->[$_] = $usdrub->[1]->[$_] / $res->[1]->[$_] * ($mult{$currency} // 1) for 0..$#{$res->[1]};
		push @{$data}, $res->[1];
	}
	save_graph($data, $_[0]);
}

sub check_unique_date {
	my ($array, $date) = @_;
	for (@{$array}) {
		return 0 if $_ == $date;
		return 1 if $_ > $date;
	}
	1;
}

sub fx {
	my ($data, @dates) = [];
	push @{$data}, [] for (0..$#{$plan{currency}->{to}} + 1);
	my ($start_date, $end_date) = ($plan{date}->{start}, $plan{date}->{end});
	my $step = max(1, int(($end_date - $start_date) / 20));
	my $curr_date = Date->new($start_date) - $step;
	my $symbols = join ',', @{$plan{currency}->{to}};
	while ($curr_date < $end_date) {
		my $date = min($curr_date += $step, $end_date)->to_string();
		$date =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
		my $json = parse_json(request("http://api.fixer.io/$date?base=RUB&symbols=$symbols"));
		next if ($json->{error});
		$json->{date} =~ s/(\d+)\-(\d+)\-(\d+)/$3\.$2\.$1/;
		$date = Date->new($json->{date});
		next if !check_unique_date(\@dates, $date);
		push @{$data->[0]}, $json->{date};
		push @dates, $date;
		for (0..$#{$plan{currency}->{to}}) {
			push @{$data->[$_ + 1]}, 1 / $json->{rates}->{$plan{currency}->{to}->[$_]} * ($mult{$plan{currency}->{to}->[$_]} // 1) 
				if defined $json->{rates}->{$plan{currency}->{to}->[$_]};
		}
			
	}
	save_graph($data, $_[0]);
}

sub save_graph {
	return undef if !defined $_[0]->[0];
	my $graph = GD::Graph::lines->new(max(1280, scalar(@{$_[0]->[0]}) * 20), 720);
	my ($y_max, $y_min) = (0, 10e10);
	for (@{$_[0]}[1..$#{$_[0]}]) {
		$y_min = min($y_min, @{$_});
		$y_max = max($y_max, @{$_});
	}
	$graph->set(
      	y_label => $plan{currency}->{from},
      	y_max_value => ceil($y_max),
      	y_min_value => int($y_min),
      	title => 'Currency',
      	bgclr => 'white',
      	transparent	=> 0,
      	x_labels_vertical => 1,
	) or die $graph->error;
	$graph->set_legend(@{$plan{currency}->{to}});
	my $file_name = $plan{files}->[$_[1]] ? $plan{files}->[$_[1]] : 'file' . ($_[1] + 1) . '.png';
	my $plot = $graph->plot($_[0]) // return undef;
	open(IMG, ">$file_name") or die $!;
	binmode IMG;
	print IMG $plot->png;
	say "Saved to $file_name";
}

sub request {
	LWP::UserAgent->new->request(HTTP::Request->new( GET => shift ))->decoded_content;
}

sub parse_sources_names { 
	$plan{sources} = [];
	push @{$plan{sources}}, $sources{$_} for (split ',', shift); 
}

sub parse_dates {
	shift =~ /(.+),(.+)/;
	$plan{date}->{start} = Date->new($1);
	$plan{date}->{end} = Date->new($2);
}

for (@ARGV) {
	my $s = $_;
	parse_sources_names($s) if $s =~ s/^-s//;
	parse_dates($s) if $s =~ s/^-d//;
	$plan{files} = [ split(',', $s) ] if $s =~ s/^-f//;
	$plan{currency}->{to} = [ split(',', $s) ] if $s =~ s/^-c//;
	say $help and exit if $s =~ /^-h/;
}

do { $plan{sources}->[$_]->($_) if defined $plan{sources}->[$_] } for (0..$#{$plan{sources}});
