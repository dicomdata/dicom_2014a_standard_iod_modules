#!/usr/bin/env perl
# Copyright 2014 Michal Špaček <tupinek@gmail.com>

package Dicom::IOD::Module::Handler;

# Pragmas.
use strict;
use warnings;

# Constructor.
sub new {
	my ($type, %params) = @_;
	return bless {
		%params,
		'section' => undef,
		'modules_flag' => 0,
		'section_2_flag' => 0,
		'section_2_stack' => [],
	}, $type;
}

# Start element.
sub start_element {
	my ($self, $element) = @_;

	# Chapter D. End of modules.
	if ($element->{'Name'} eq 'chapter'
		&& exists $element->{'Attributes'}
		&& exists $element->{'Attributes'}->{'{}label'}
		&& $element->{'Attributes'}->{'{}label'}->{'Value'} eq 'D') {

		$self->{'modules_flag'} = 0;
	}

	# Section 2.
	if ($element->{'Name'} eq 'section'
		&& exists $element->{'Attributes'}
		&& exists $element->{'Attributes'}->{'{}status'}
		&& $element->{'Attributes'}->{'{}status'}->{'Value'} eq '2') {

		# Begin of modules sections.
		if ($element->{'Attributes'}->{'{}label'}->{'Value'} eq 'C.2') {
			$self->{'modules_flag'} = 1;
		}

		# Right module section.
		if ($self->{'modules_flag'}) {
			$self->{'section_2_flag'} = 1;
		}
	}
	if (! $self->{'section_2_flag'}) {
		return;
	}

	# Stack.
	push @{$self->{'section_2_stack'}}, $element->{'Name'};
	return;
}

# End element.
sub end_element {
	my ($self, $element) = @_;
	if (! $self->{'section_2_flag'}) {
		return;
	}
	
	# Stack.
	if (@{$self->{'section_2_stack'}}
		&& $element->{'Name'} eq $self->{'section_2_stack'}->[-1]) {

		pop @{$self->{'section_2_stack'}};
	}

	# Remove section 2 flag.
	if ($element->{'Name'} eq 'section'
		&& @{$self->{'section_2_stack'}} == 0) {

		$self->{'section_2_flag'} = 0;
	}

	return;
}

# Characters.
sub characters {
	my ($self, $characters) = @_;
	if (! $self->{'section_2_flag'}) {
		return;
	}

	# Skip blank data.
	if ($characters->{'Data'} =~ m/^\s*$/ms) {
		return;
	}

	if ($self->{'section_2_stack'}->[-1] eq 'title'
		&& $self->{'section_2_stack'}->[-2] eq 'section') {

		if (@{$self->{'section_2_stack'}} == 2) {
			print "Section: $self->{'section'}\n";
			$self->{'section'} = $characters->{'Data'};

		} elsif (@{$self->{'section_2_stack'}} == 3
			&& $self->{'section_2_stack'}->[-2] eq 'section') {

			my $module = $characters->{'Data'};
			print "Module: $module\n";
			my $retired = 0;
			if ($module =~ m/^(.*?)\s*(\(Retired\))$/ms) {
				$module = $1;
				$retired = 1;
			}
			$self->{'dt'}->insert({
				'Section' => $self->{'section'},
				'Module' => $module,
				'Retired' => $retired,
			});
		}
	}
	return;
}

package main;

# Pragmas.
use strict;
use warnings;

# Modules.
use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use English;
use File::Temp qw(tempfile);
use LWP::UserAgent;
use URI;
use XML::SAX::Expat;

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

# URI of service.
my $base_uri = URI->new('ftp://medical.nema.org/medical/dicom/2014a/source/docbook/part03/part03.xml');

# Open a database handle.
my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

# Create a user agent object.
my $ua = LWP::UserAgent->new(
	'agent' => 'Mozilla/5.0',
);

# Get base root.
print 'Page: '.$base_uri->as_string."\n";
my $xml_file = get_file($base_uri);
my $h = Dicom::IOD::Module::Handler->new(
	'dt' => $dt,
);
my $p = XML::SAX::Expat->new('Handler' => $h);
$p->parse_file($xml_file);
unlink $xml_file;

# Get file
sub get_file {
	my $uri = shift;
	my (undef, $tempfile) = tempfile();
	my $get = $ua->get($uri->as_string,
		':content_file' => $tempfile,
	);
	if ($get->is_success) {
		return $tempfile;
	} else {
		die "Cannot GET '".$uri->as_string." page.";
	}
}

# Removing trailing whitespace.
sub remove_trailing {
	my $string_sr = shift;
	${$string_sr} =~ s/^\s*//ms;
	${$string_sr} =~ s/\s*$//ms;
	return;
}
