unit module Markdown;

sub transform_inlines {
    $^s.subst(:g, /'*' (<-[*]>+) '*'/, -> $/ { "<em>{$0}</em>" })\
        .subst(:g, /'`' (<-[`]>+) '`'/, -> $/ { "<code>{$0}</code>" })\
        .subst(:g, /'[' (<-[\]]>+) '](' (<-[)]>+) ')'/,
                -> $/ { qq[<a href="{$1}">{$0}</a>] });
}

class Paragraph {
    has $.contents is rw;

    method to_html {
        "<p>{transform_inlines $.contents}</p>\n";
    }
}

class MList {
    has @.contents handles <push AT_POS>;

    method to_html {
        "<ul>\n{@.contents».to_html.join}</ul>\n";
    }
}

class ListItem {
    has $.contents;

    method to_html {
        "<li>{$.contents}</li>\n";
    }
}

class HtmlBlock {
    has $.contents is rw;

    method to_html {
        "$.contents\n";
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
        elsif $line ~~ /^ '- ' \h* (.*) / {
            if !@elements || @elements[*-1] !~~ MList {
                @elements.push: MList.new;
            }
            my $contents = ~$0;
            @elements[*-1].push: ListItem.new(:$contents);
            next LINE;
        }
        elsif $line ~~ /^ '<dl>' $/ {   # XXX: generalize
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
