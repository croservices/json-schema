use v6;
use JSON::Schema;
use Test;

# Tests for the opt-in `validate-errors` aggregation mode: it returns every
# X::JSON::Schema::Failed instead of failing on the first one, while leaving
# `validate` (fail-fast) and anyOf/oneOf/not/if/contains semantics unchanged.

sub has-reason(@errors, $rx) { so @errors.grep({ .reason ~~ $rx }) }

subtest 'object: missing required + wrong type collected together' => {
    my $s = JSON::Schema.new(schema => {
        type       => 'object',
        required   => <name host user password>.List,
        properties => {
            name => { type => 'string' },
            port => { type => 'integer' },
        },
        additionalProperties => False,
    });

    my @e = $s.validate-errors({ host => 'h', port => 'NOT-INT', bogus => 1 });
    ok @e.elems >= 3, "at least 3 distinct problems collected (got {@e.elems})";
    ok has-reason(@e, rx/ "Missing" .* "'name'" /), 'missing required reported';
    ok has-reason(@e, rx/ "Not an integer" /),      'wrong-typed port reported';
    ok has-reason(@e, rx/ "False schema" /),        'unknown key (additionalProperties) reported';
}

subtest 'all unknown keys collected, not just the first' => {
    my $s = JSON::Schema.new(schema => {
        type => 'object',
        properties => { a => { type => 'string' } },
        additionalProperties => False,
    });
    my @e = $s.validate-errors({ a => 'x', b => 1, c => 2, d => 3 });
    is @e.grep({ .reason ~~ rx/ "False schema" / }).elems, 3, 'all three unknown keys reported';
}

subtest 'nested object problems are collected at depth' => {
    my $s = JSON::Schema.new(schema => {
        type => 'object',
        properties => {
            db => {
                type => 'object',
                required => <name host>.List,
                properties => { name => { type => 'string' }, host => { type => 'string' } },
            },
        },
    });
    my @e = $s.validate-errors({ db => { host => 42 } });
    ok has-reason(@e, rx/ "Missing" .* "'name'" /), 'nested missing required reported';
    ok has-reason(@e, rx/ "Not a string" /),        'nested wrong type reported';
}

subtest 'valid value -> empty list' => {
    my $s = JSON::Schema.new(schema => {
        type => 'object',
        required => <name>.List,
        properties => { name => { type => 'string' } },
        additionalProperties => False,
    });
    is $s.validate-errors({ name => 'ok' }).elems, 0, 'no errors for a valid object';
}

subtest 'anyOf still atomic under aggregation' => {
    my $s = JSON::Schema.new(schema => { anyOf => [ { type => 'string' }, { type => 'integer' } ] });
    is $s.validate-errors(42).elems,  0, 'integer satisfies anyOf -> no errors';
    is $s.validate-errors('x').elems, 0, 'string satisfies anyOf -> no errors';
    is $s.validate-errors(3.14).elems, 1, 'value satisfying no branch -> exactly one anyOf error';
}

subtest 'not still atomic under aggregation' => {
    my $s = JSON::Schema.new(schema => { not => { type => 'string' } });
    is $s.validate-errors(42).elems,  0, 'non-string passes `not`';
    is $s.validate-errors('x').elems, 1, 'string fails `not` with a single error';
}

subtest 'validate (fail-fast) is unchanged' => {
    my $s = JSON::Schema.new(schema => { type => 'object', required => <a b c>.List });
    nok $s.validate({}),               'validate still falsy on invalid';
    ok  $s.validate({a=>1,b=>2,c=>3}), 'validate still truthy on valid';
}

done-testing;
