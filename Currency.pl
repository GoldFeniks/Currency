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

my %opts = (
	func => undef,
	date => {
		start => '01.01.2015',
		end => '01.03.2015'
	},
	file => undef,
	currency => {
		from => 'RUB',
		to => ['USD', 'EUR', 'JPY'],
	}
);

my %cb_names = (
	USD => 'R01235',
	EUR => 'R01239',
	JPY => 'R01820',
);


sub cb {
	my $data = [];
	for (@{$opts{currency}->{to}}) {
		my $url = "https://www.cbr.ru/currency_base/dynamics.aspx?VAL_NM_RQ=$cb_names{$_}\&date_req1=$opts{date}->{start}\&date_req2=$opts{date}->{end}\&rt=1\&mode=1";
		my $te = HTML::TableExtract->new( attribs => { class => 'data' } )->parse(request($url));
		my ($values, $dates) = ([], []);
		for ($te->tables) {
			for (@{$_->rows}[1..$#{$_->rows}]) {
				push @{$dates}, @{$_}[0];
				@{$_}[2] =~ s/,/./;
				push @{$values}, @{$_}[2];
			}
		}
		push @{$data}, $dates if !defined($data->[0]);
		push @{$data}, $values;
	}
	save_graph($data);
};

sub json_parse_yh {
	my $json = parse_json(shift);
	my @data = ([], []);
	for (reverse @{$json->{query}->{results}->{quote}}) {
		$_->{Date} =~ s/(\d+)\-(\d+)\-(\d+)/$2\.$3\.$1/;
		push @{$data[0]}, $_->{Date};
		push @{$data[1]}, $_->{Close};
	}
	return \@data;
} 

sub yh_url {
	my ($start_date, $end_date, $currency) = @_;
	my  $s = 'https://query.yahooapis.com/v1/public/yql?q=select%20*%20from%20yahoo.finance.historicaldata%20where%20symbol%20%3D%20%22curr%3DX%22%20and%20startDate%20%3D%20%22sdate%22%20and%20endDate%20%3D%20%22edate%22&format=json&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys&callback=';
	$start_date =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
	$end_date =~ s/(\d+)\.(\d+)\.(\d+)/$3-$2-$1/;
	$s =~ s/curr/$currency/;
	$s =~ s/sdate/$start_date/;
	$s =~ s/edate/$end_date/;
	$s;
}

sub yh {
	my $data = [];
	my $usdrub = json_parse_yh(request(yh_url($opts{date}->{start}, $opts{date}->{end}, 'RUB')));
	push @{$data}, @{$usdrub}[0];
	for (@{$opts{currency}->{to}}) {
		if (/USD/) {
			push @{$data}, $usdrub->[1];
			next;
		};
		my $m = /JPY/ ? 100 : 1;
		my $res = json_parse_yh(request(yh_url($opts{date}->{start}, $opts{date}->{end}, $_)));
		$res->[1]->[-1 * $_] = $usdrub->[1]->[-1 * $_] / $res->[1]->[-1 * $_] * $m for (-$#{$res->[1]}..0);
		push @{$data}, $res->[1];
	}
	save_graph($data);
}

sub save_graph {
	my $graph = GD::Graph::lines->new(1280, 720);
	my ($y_max, $y_min) = (0, 10e10);
	for (@{$_[0]}[1..$#{$_[0]}]) {
		$y_min = min($y_min, @{$_});
		$y_max = max($y_max, @{$_});
	}
	$graph->set(
      	y_label => $opts{currency}->{from},
      	y_max_value => ceil($y_max),
      	y_min_value => int($y_min),
      	title => 'Currency',
      	bgclr => 'white',
      	transparent	=> 0,
      	x_labels_vertical => 1,
	) or die $graph->error;
	$graph->set_legend(@{$opts{currency}->{to}});
	$graph->set_title_font(GD::gdGiantFont);
	open(IMG, '>file.png') or die $!;
	binmode IMG;
	print IMG $graph->plot($_[0])->png;
}

sub request {
	my $url = shift;
	my $ua = LWP::UserAgent->new;
	my $request = HTTP::Request->new( GET => $url );
	$ua->request($request)->decoded_content;
}

cb();