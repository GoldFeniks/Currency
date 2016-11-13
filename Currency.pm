use v5.24;
use HTML::TableExtract;
use HTTP::Request;
use LWP::UserAgent;
use GD::Text;
use GD::Graph;
use GD::Graph::lines;
use List::Util qw(min max);
use POSIX qw(ceil);

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

my $cb = sub {
	my $data = [];
	for (@{$opts{currency}->{to}}) {
		my $url = "https://www.cbr.ru/currency_base/dynamics.aspx?VAL_NM_RQ=$cb_names{$_}\&date_req1=$opts{date}->{start}\&date_req2=$opts{date}->{end}\&rt=1\&mode=1";
		my $response = request($url);
		my $te = HTML::TableExtract->new( attribs => { class => 'data' } );
		$te->parse($response);
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

sub save_graph {
	my $graph = GD::Graph::lines->new(720, 380);
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
      	boxclr => 'white',
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

$cb->();
