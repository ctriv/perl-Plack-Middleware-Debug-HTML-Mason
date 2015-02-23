package Plack::Middleware::Debug::HTML::Mason;

use strict;
use warnings;

use parent qw(Plack::Middleware::Debug::Base);

=head1 NAME

Plack::Middleware::Debug::HTML::Mason - Debug info for old HTML::Mason apps.

=head1 SYNOPSIS

	# add this to your mason configuration
	plugins => ['Plack::Middleware::Debug::HTML::Mason::Plugin']
	
	# and then enable the middleware
	enable 'Debug::HTML::Mason';

=head1 DESCRIPTION

Provides a call tree and some basic configuration information for a request
processed by HTML::Mason.

=cut

my $root;
my @stack;
my %env;

package Plack::Middleware::Debug::HTML::Mason::Plugin {
	use strict;
	use warnings;
	use parent qw(HTML::Mason::Plugin);
	use Time::HiRes qw(time);
	use JSON;

	my $json = JSON->new->convert_blessed(1)->allow_blessed(1)->allow_unknown(1)->utf8(1);
	
	sub start_component_hook {
		my ($self, $context) = @_;
		
		my $frame = {
			start => time(),
			kids  => [],
		};
		$root ||= [$frame];
		if (@stack) {
			my $parent= $stack[-1];
			push @{$parent->{kids}}, $frame;
		}
		push @stack, $frame;
	}
	
	sub end_component_hook {
		my ($self, $context) = @_;
		
		my $frame = pop @stack;
		my $name  = $context->comp->title;
		
		my ($path, $root, $method) = $name =~ m/(.*) (\[.+?\])(:.+)?/;
		
		$frame->{name} = $method ? "$root $path$method" : "$root $path";
		$frame->{end}  = time();
		$frame->{duration} = $frame->{end} - $frame->{start};
		$frame->{args} = $json->encode($context->args);
	}
	
	sub end_request_hook {
		my ($self, $context) = @_;
		
		$env{main_comp} = $context->request->request_comp;
		$env{args}      = $context->args;
		$env{comp_root} = $context->request->interp->comp_root;
	}

}

 
sub run {
	my ($self, $env, $panel) = @_;
	
	$root  = undef;
	@stack = ();
	%env   = ();
	
	return sub {
		my $res = shift;
		
		$panel->nav_title("HTML::Mason");
		$panel->title("HTML::Mason Summary");		
		
		my $depth  = 0;
		my $frame;
		my $walker;
		my $html = '';
		my $i = 0;
		$walker = sub {
			my ($context, $depth) = @_;
			return unless $context && @$context;

			
			foreach my $frame (@$context) {
				my $margin = sprintf("%dpx", $depth * 16);
				my $background;
				$i++;
				if ($i % 2) {
					$background = '#f5f5f5';
				}
				elsif ($frame->{name} eq $env{main_comp}->title) {
					$background = '#f0f0f0';
				}
				else {
					$background = 'white';
				}
				
				$html .= sprintf('<div style="background-color: %s; padding-left: %s">%s(%s) - %.5fs</div>',
					$background,
					$margin,
					$frame->{name},
					$frame->{args},
					$frame->{duration},
				);
				
				$walker->($frame->{kids}, $depth + 1);				
			}
		};
		
		$walker->($root, 1);
		
		my $css = <<END;
<style type="text/css">
	div#mason_debug  {
		margin-top: 16px;
		background: white;
		border: solid 1px #ddd;
	}
	
	div#mason_debug div {
		padding-top: 2px;
		padding-bottom: 2px;
	}
</style>
END
		
		$panel->content(
			$self->render_list_pairs([
				'Main Comp' => $env{main_comp}->source_file,
				'Args'      => $env{args},
				'Comp Root' => $env{comp_root},
				
			]) . 
			qq|$css<div id="mason_debug">$html</div>|
		);
	};
}

1;
__END__
