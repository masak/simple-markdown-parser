unit module Markdown;

sub transform_inlines($text) {
    my regex symbol { < * ** _ ` [ ] ( ) > }

    my @components = $text.comb(/ <symbol> | [<!before <symbol>> .]+ /);

    my $inside-code = False;
    SYMBOL:
    loop (my $i = 0; $i < @components; $i++) {
        if @components[$i] eq '</code>' {
            $inside-code = False;
        }
        if $inside-code {
            @components[$i] .= &escape;
            next;
        }
        next if @components[$i] eq '</strong>' | '</em>' | '</code>' | '</a>';  # XXX: feels dodgy

        if @components[$i] eq '**' {
            loop (my $j = $i + 1; $j < @components; $j++) {
                if @components[$j] eq '**' {
                    @components[$i] = '<strong>';
                    @components[$j] = '</strong>';
                    next SYMBOL;
                }
            }
        }
        if @components[$i] eq '*' {
            loop (my $j = $i + 1; $j < @components; $j++) {
                if @components[$j] eq '*' {
                    @components[$i] = '<em>';
                    @components[$j] = '</em>';
                    next SYMBOL;
                }
            }
        }
        if @components[$i] eq '_' {
            loop (my $j = $i + 1; $j < @components; $j++) {
                if @components[$j] eq '_' {
                    @components[$i] = '<em>';
                    @components[$j] = '</em>';
                    next SYMBOL;
                }
            }
        }
        if @components[$i] eq '`' {
            loop (my $j = $i + 1; $j < @components; $j++) {
                if @components[$j] eq '`' {
                    @components[$i] = '<code>';
                    @components[$j] = '</code>';
                    $inside-code = True;
                    next SYMBOL;
                }
            }
        }
        if @components[$i] eq '[' {
            CLOSER:
            loop (my $j = $i + 1; $j < @components; $j++) {
                if @components[$j] eq '[' {
                    last CLOSER;
                }
                if @components[$j] eq ']' && @components[$j + 1] eq '(' {
                    loop (my $k = $j + 2; $k < @components; $k++) {
                        if @components[$k] eq ')' {
                            my $href = @components[$j + 2 .. $k - 1].join;
                            @components[$i] = qq[<a href="{$href}">];
                            @components.splice($j, $k - $j + 1, qq[</a>]);
                            next SYMBOL;
                        }
                    }
                }
            }
        }
        @components[$i] .= &escape;
    }

    return @components.join;
}

sub escape {
    $^st.trans(['<', '>', '&'] => ['&lt;', '&gt;', '&amp;']);
}

class Paragraph {
    has $.contents is rw;

    method to_html {
        "<p>{transform_inlines $.contents}</p>\n";
    }
}

class UnorderedList {
    has @.contents handles <push AT_POS>;

    method to_html {
        "<ul>\n{@.contents».to_html.join}</ul>\n";
    }
}

class OrderedList {
    has @.contents handles <push AT_POS>;

    method to_html {
        "<ol>\n{@.contents».to_html.join}</ol>\n";
    }
}

class ListItem {
    has $.contents;

    method to_html {
        "<li>{transform_inlines $.contents}</li>\n";
    }
}

class HtmlBlock {
    has $.contents is rw;

    method to_html {
        "$.contents\n";
    }
}

class IndentedCodeBlock {
    has $.contents is rw;

    method to_html {
        "<pre><code>{escape $.contents}\n</code></pre>\n";
    }
}

class AtxHeader {
    has $.contents;

    method to_html {
        "<h2>{$.contents}</h2>\n";
    }
}

our sub to_html($input) {
    my @elements;
    my $new_paragraph = True;
    my $eating_html = False;

    LINE:
    for $input.lines -> $line {
        if $line ~~ /^ \s* $/ {
            $new_paragraph = True;
            $eating_html = False;
            next LINE;
        }
        elsif $eating_html {
            @elements[*-1].contents ~= "\n$line";
            next LINE;
        }
        elsif $line ~~ /^ '    ' (\N+) / {
            my $contents = ~$0;
            if !@elements || @elements[*-1] !~~ IndentedCodeBlock {
                @elements.push: IndentedCodeBlock.new(:$contents);
            }
            else {
                @elements[*-1].contents ~= "\n$0";
            }
            next LINE;
        }
        elsif $line ~~ /^ '- ' \h* (.*) / {
            if !@elements || @elements[*-1] !~~ UnorderedList {
                @elements.push: UnorderedList.new;
            }
            my $contents = ~$0;
            @elements[*-1].push: ListItem.new(:$contents);
            next LINE;
        }
        elsif $line ~~ /^ \d+ '. ' \h* (.*) / {
            if !@elements || @elements[*-1] !~~ OrderedList {
                @elements.push: OrderedList.new;
            }
            my $contents = ~$0;
            @elements[*-1].push: ListItem.new(:$contents);
            next LINE;
        }
        elsif $line ~~ /^ '##' \h* (.*) / {
            my $contents = ~$0;
            @elements.push: AtxHeader.new(:$contents);
            next LINE;
        }
        elsif $line ~~ /^ '<dl>' | '<pre>' / {   # XXX: generalize
            my $contents = $line;
            @elements.push: HtmlBlock.new(:$contents);
            $eating_html = True;
            next LINE;
        }

        if !$new_paragraph && @elements[*-1] ~~ Paragraph {
            @elements[*-1].contents ~= "\n$line";
        }
        else {
            my $contents = $line;
            @elements.push: Paragraph.new(:$contents);
            $new_paragraph = False;
        }
    }

    return @elements».to_html.join;
}
