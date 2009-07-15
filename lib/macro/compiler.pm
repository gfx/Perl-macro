package macro::compiler;

use strict;
use warnings;

BEGIN{
	require macro;
	our @ISA = qw(macro);
	*VERSION = \$macro::VERSION;
}

my %compiled;

sub import{
	my $class = shift;

	return unless @_;

	my($pkg, $file) = do{
		my $i = 0;
		my($pkg, $file) = (caller($i))[0, 1];
		while($pkg->isa('macro')){
			($pkg, $file) = (caller(++$i))[0, 1]
		}
		($pkg, $file);
	};
	my $file_c = $file . 'c';

	if($^C and not $compiled{$file}){
		warn "Compiling $file by $class/$macro::VERSION ...\n";
	}

	my $self  = $class->new();

	$self->defmacro(@_);

	my $fh;

	($compiled{$file} and open $fh, '<:perlio', $file_c)
		or open $fh, '<:perlio', $file
		or die qq{Cannot open "$file" for reading: $!};

	my $src = <$fh>;

	unless($compiled{$file}){
		if($src =~ /^#/){
			$src .= $self->_sign($file, 2);
		}
		else{
			$src = $self->_sign($file, 1) . $src;
		}
	}

	{ local $/; $src .= <$fh> };
	close $fh;

	$src = $self->process($src, [$pkg, $file, -12]);

	chmod 0644, $file_c; # chmod +w

	open $fh, '>:perlio', $file_c
		or die qq{Cannot open "$file_c" for writing: $!};

	print $fh $src
		or die qq{Cannot write to "$file_c": $!};

	close $fh
		or die qq{Cannot close "$file_c: $!};
	chmod 0444 & (stat $file)[2], $file_c, ; # chmod -w

	$compiled{$file}++;


	require macro::filter;
	macro::filter->import(@_);

	return;
}

# called from process();
sub preprocess{
	my($self, $d) = @_;

	my $elem = $d->find_first(\&_want_use_macro);
	die $@ if $@;

	if($elem){

		my $stmt = $elem->content;
		$stmt =~ s/^/#/msxg;
		$stmt .= "\n";

		$d = $elem->parent;

		$stmt = PPI::Token::Comment->new($stmt); # comment out the statement
		$stmt->{enable} = 1;
		$d->{skip} = 1;

		$elem->__insert_before($stmt);
		$elem->remove();
	}

	return $d;
}

sub _want_use_macro{
	my(undef, $it) = @_;
	my $elem;

	return $it->isa('PPI::Statement::Include')

		&& ($elem = $it->schild(0))
		&& ($elem->content eq 'use')

		&& ($elem = $elem->snext_sibling)
		&& ($elem->content eq __PACKAGE__ or $elem->content eq 'macro')

		&& _has_args($it, $elem->snext_sibling);
}

# Does the use statement have arguments?
# It's too complex to understand :-(
# See macro/t/07_has_args.t for the subroutine spec.
sub _has_args{
	my($stmt, $arg) = @_; # 'use macro ...;' statement

	return 0 unless $arg;

	# check the most usual case first
	# case 'use macro foo => ...';
	return 1 if $arg->isa('PPI::Token::Word');

	# case 'use macro;'
	return 0 if $arg->isa('PPI::Token::Structure')
			&& $arg->content eq ';';

	# case 'use macro 0.1'
	$arg = $arg->snext_sibling if $arg->isa('PPI::Token::Number');


	my @queue = ($arg);
	ARG: while($arg = shift @queue){

		# case 'use macro  foo => ...'
		return 1 if $arg->isa('PPI::Token::Word');

		# case 'use macro "foo" => ...';
		return 1 if $arg->isa('PPI::Token::Quote');


		# case 'use macro qw(...);'
		return 1 if $arg->isa('PPI::Token::QuoteLike::Words')
				&& $arg->content !~ /^qw . \s* . $/msx;


		return 0 if $arg->isa('PPI::Token::Structure')
				&& $arg->content eq ';';


		# case '(' expr ')'
		if($arg->isa('PPI::Structure::List')){
			if(my $expr = $arg->schild(0)){
				push @queue, $expr->schildren;
			}
		}

		if(my $sibling = $arg->snext_sibling){
			push @queue, $sibling;
		}
	}
	return 0;
}
sub _sign{
	my($self, $file, $line) = @_;
	# meta
	my $pkg = ref($self);
	my $version = $pkg->VERSION;

	my $inc_key;
	while(my($key, $path) = each %INC){
		if($path eq $file){
			$inc_key = $key;
		}
	}

	# original file data
	my $mtime = (stat $file)[9];

	my $mtimestamp = localtime $mtime;

	# for the correct file path
	if(defined $inc_key){
		$file = $inc_key;
	}
	else{
		require File::Basename;
		$inc_key = File::Basename::basename($file);
	}

	return <<"SIGN";
# It was generated by $pkg version $version.
# Don't edit this file, edit $inc_key instead.
# ANY CHANGES MADE HERE WILL BE LOST!
# ============================= freshness check =============================
# the original file modified at $mtimestamp
BEGIN{my\$o=\$INC{q{$inc_key}}||q{$file};my\$m=(CORE::stat\$o)[9];
if(\$m and \$m != $mtime){ my \$f=do{CORE::open my\$in,'<',\$o or
die(qq{Cannot open \$o: \$!});local\$/;<\$in>;};require Filter::Util::Call;
Filter::Util::Call::filter_add(sub{ Filter::Util::Call::filter_del();
1 while Filter::Util::Call::filter_read();\$_=\$f;return 1; });}}
# line $line $inc_key
SIGN
}

1;

__END__

=head1 NAME

macro::compiler - macro.pm compiler backend

=head1 SYNOPSIS

	use macro::compiler add => sub{ $_[0] + $_[1] };

=head1 SEE ALSO

L<macro>.

=head1 AUTHOR

Goro Fuji E<lt>gfuji(at)cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2008, Goro Fuji E<lt>gfuji(at)cpan.orgE<gt>. Some rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
