use 5.008;
use strict;
use warnings;

package Pod::Markdown;
# ABSTRACT: Convert POD to Markdown
use parent qw(Pod::Parser);

sub initialize {
    my $self = shift;
    $self->SUPER::initialize(@_);
    $self->_private;
    $self;
}

sub _private {
    my $self = shift;
    $self->{_MyParser} ||= {
        Text      => [],       # final text
        Indent    => 0,        # list indent levels counter
        ListType  => '-',      # character on every item
        searching => undef,    # what are we searching for? (title, author etc.)
        Title     => undef,    # page title
        Author    => undef,    # page author
    };
}

sub as_markdown {
    my ($parser, %args) = @_;
    my $data  = $parser->_private;
    my $lines = $data->{Text};
    my @header;
    if ($args{with_meta}) {
        @header = $parser->_build_markdown_head;
    }
    join("\n" x 2, @header, @{$lines});
}

sub _build_markdown_head {
    my $parser    = shift;
    my $data      = $parser->_private;
    my $paragraph = '';
    if (defined $data->{Title}) {
        $paragraph .= sprintf '[[meta title="%s"]]', $data->{Title};
    }
    if (defined $data->{Author}) {
        $paragraph .= "\n" . sprintf '[[meta author="%s"]]', $data->{Author};
    }
    return $paragraph;
}

sub _save {
    my ($parser, $text) = @_;
    my $data = $parser->_private;
    $text = $parser->_indent_text($text);
    push @{ $data->{Text} }, $text;
    return;
}

sub _indent_text {
    my ($parser, $text) = @_;
    my $data   = $parser->_private;
    my $level  = $data->{Indent};
    my $indent = undef;
    if ($level > 0) {
        $level--;
    }
    $indent = ' ' x ($level * 4);
    my @lines = map { $indent . $_; } split(/\n/, $text);
    return wantarray ? @lines : join("\n", @lines);
}

sub _clean_text {
    my $text    = $_[1];
    my @trimmed = grep { $_; } split(/\n/, $text);
    return wantarray ? @trimmed : join("\n", @trimmed);
}

sub command {
    my ($parser, $command, $paragraph, $line_num) = @_;
    my $data = $parser->_private;

    # cleaning the text
    $paragraph = $parser->_clean_text($paragraph);

    # is it a header ?
    if ($command =~ m{head(\d)}xms) {
        my $level = $1;

        $paragraph = $parser->interpolate($paragraph, $line_num);

        # the headers never are indented
        $parser->_save($parser->format_header($level, $paragraph));
        if ($level == 1) {
            if ($paragraph =~ m{NAME}xmsi) {
                $data->{searching} = 'title';
            } elsif ($paragraph =~ m{AUTHOR}xmsi) {
                $data->{searching} = 'author';
            } else {
                $data->{searching} = undef;
            }
        }
    }

    # opening a list ?
    elsif ($command =~ m{over}xms) {

        # update indent level
        $data->{Indent}++;

        # closing a list ?
    } elsif ($command =~ m{back}xms) {

        # decrement indent level
        $data->{Indent}--;
    } elsif ($command =~ m{item}xms) {
        $parser->_save(sprintf '%s %s',
            $data->{ListType}, $parser->interpolate($paragraph, $line_num));
    }

    # ignore other commands
    return;
}

sub verbatim {
    my ($parser, $paragraph) = @_;
    $parser->_save($paragraph);
}

sub textblock {
    my ($parser, $paragraph, $line_num) = @_;
    my $data = $parser->_private;

    # interpolate the paragraph for embebed sequences
    $paragraph = $parser->interpolate($paragraph, $line_num);

    # clean the empty lines
    $paragraph = $parser->_clean_text($paragraph);

    # searching ?
    if ($data->{searching}) {
        if ($data->{searching} =~ m{title|author}xms) {
            $data->{ ucfirst $data->{searching} } = $paragraph;
            $data->{searching} = undef;
        }
    }

    # save the text
    $parser->_save($paragraph);
}

sub interior_sequence {
    my ($seq_command, $seq_argument, $pod_seq) = @_[1..3];
    my %interiors = (
        'I' => sub { return '_' . $_[1] . '_' },      # italic
        'B' => sub { return '__' . $_[1] . '__' },    # bold
        'C' => sub { return '`' . $_[1] . '`' },      # monospace
        'F' => sub { return '`' . $_[1] . '`' },      # system path
        'S' => sub { return '`' . $_[1] . '`' },      # code
        'E' => sub {
            my $charname = $_[1];
            return '<' if $charname eq 'lt';
            return '>' if $charname eq 'gt';
            return '|' if $charname eq 'verbar';
            return '/' if $charname eq 'sol';
            return "&$charname;";
        },
        'L' => \&_resolv_link,
    );
    if (exists $interiors{$seq_command}) {
        my $code = $interiors{$seq_command};
        return $code->($seq_command, $seq_argument, $pod_seq);
    } else {
        return sprintf '%s<%s>', $seq_command, $seq_argument;
    }
}

sub _resolv_link {
    my ($cmd, $arg) = @_;
    my $text = $arg =~ s"^(.+?)\|"" ? $1 : '';

    if ($arg =~ m{^http|ftp}xms) { # direct link to a URL
        $text ||= $arg;
        return sprintf '[%s](%s)', $text, $arg;
    } elsif ($arg =~ m{^/(.*)$}) {
        $text ||= $1;
        $text = $1;
        return "[$text](\#pod_$1)";
    } elsif ($arg =~ m{^(\w+(?:::\w+)*)$}) {
        $text ||= $1;
        return "[$text](http://search.cpan.org/perldoc?$1)";
    } else {
        return sprintf '%s<%s>', $cmd, $arg;
    }
}

sub format_header {
    my ($level, $paragraph) = @_[1,2];
    sprintf '%s %s', '#' x $level, $paragraph;
}

1;

=begin :prelude

=for stopwords textblock

=end :prelude

=head1 SYNOPSIS

    my $parser = Pod::Markdown->new;
    $parser->parse_from_filehandle(\*STDIN);
    print $parser->as_markdown;

=head1 DESCRIPTION

This module subclasses L<Pod::Parser> and converts POD to Markdown.

=method initialize

Initializes a newly constructed object.

=method as_markdown

Returns the parsed POD as Markdown. Takes named arguments. If the C<with_meta>
argument is given a positive value, meta tags are generated as well.

=method command

Handles POD command paragraphs, denoted by a line beginning with C<=>.

=method verbatim

Handles verbatim text.

=method textblock

Handles normal blocks of POD.

=method interior_sequence

Handles interior sequences in POD. An interior sequence is an embedded command
within a block of text which appears as a command name - usually a single
uppercase character - followed immediately by a string of text which is
enclosed in angle brackets.

=method format_header

Formats a header according to the given level.

