# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::Elastic::Role::Object;

use 5.10.1;
use Role::Tiny;

requires qw(ES_TYPE ES_PROPERTIES es_document);
requires qw(ID_FIELD DB_TABLE);

sub ES_OBJECTS_AT_ONCE { 100 }

sub ES_SELECT_ALL_SQL {
    my ($class, $last_id) = @_;

    my $id = $class->ID_FIELD;
    my $table = $class->DB_TABLE;

    return ("SELECT $id FROM $table WHERE $id > ? ORDER BY $id", [$last_id // 0]);
}

requires qw(ES_SELECT_UPDATED_SQL);

around 'ES_PROPERTIES' => sub {
    my $orig = shift;
    my $self = shift;
    my $properties = $orig->($self, @_);
    $properties->{es_mtime} = { type => 'long' };
    $properties->{$self->ID_FIELD} = { type => 'long', analyzer => 'keyword' };

    return $properties;
};

around 'es_document' => sub {
    my ($orig, $self, $mtime) = @_;
    my $doc = $orig->($self);

    $doc->{es_mtime} = $mtime;
    $doc->{$self->ID_FIELD} = $self->id;

    return $doc;
};

sub ES_INDEX { Bugzilla->params->{elasticsearch_index} }

sub ES_ETTINGS {
    return {
        number_of_shards => 2,
        analysis         => {
            filter => {
                asciifolding_original => {
                    type              => "asciifolding",
                    preserve_original => \1,
                },
            },
            analyzer => {
                autocomplete => {
                    type      => 'custom',
                    tokenizer => 'keyword',
                    filter    => [ 'lowercase', 'asciifolding_original' ],
                },
                folding => {
                    tokenizer => 'standard',
                    filter    => [ 'standard', 'lowercase', 'asciifolding_original' ],
                },
                bz_text_analyzer => {
                    type             => 'standard',
                    filter           => [ 'lowercase', 'stop' ],
                    max_token_length => '20'
                },
                bz_equals_analyzer => {
                    type      => 'custom',
                    filter    => ['lowercase'],
                    tokenizer => 'keyword',
                },
                whiteboard_words => {
                    type      => 'custom',
                    tokenizer => 'whiteboard_words_pattern',
                    filter    => ['stop']
                },
                whiteboard_shingle_words => {
                    type      => 'custom',
                    tokenizer => 'whiteboard_words_pattern',
                    filter    => [ 'stop', 'shingle', 'lowercase' ]
                },
                whiteboard_tokens => {
                    type      => 'custom',
                    tokenizer => 'whiteboard_tokens_pattern',
                    filter    => [ 'stop', 'lowercase' ]
                },
                whiteboard_shingle_tokens => {
                    type      => 'custom',
                    tokenizer => 'whiteboard_tokens_pattern',
                    filter    => [ 'stop', 'shingle', 'lowercase' ]
                }
            },
            tokenizer => {
                whiteboard_tokens_pattern => {
                    type    => 'pattern',
                    pattern => '\\s*([,;]*\\[|\\][\\s\\[]*|[;,])\\s*'
                },
                whiteboard_words_pattern => {
                    type    => 'pattern',
                    pattern => '[\\[\\];,\\s]+'
                },
            },
        },
    };
}


1;
