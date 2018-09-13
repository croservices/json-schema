use v6;
use Test;
use JSON::Schema;

my $schema;

throws-like
    { JSON::Schema.new(schema => { minProperties => 2.5 }) },
    X::JSON::Schema::BadSchema,
    'Having minProperties property be an non-integer is refused (Rat)';
throws-like
    { JSON::Schema.new(schema => { maxProperties => '4' }) },
    X::JSON::Schema::BadSchema,
    'Having maxProperties property be an non-integer is refused (Str)';
throws-like
    { JSON::Schema.new(schema => { required => <a a> }) },
    X::JSON::Schema::BadSchema,
    'Having required property be an non-unique list is refused';

{
    $schema = JSON::Schema.new(schema => {
        type => 'object',
        minProperties => 2,
        maxProperties => 4
    });
    nok $schema.validate({a => 1}), 'Object below minimum properties number rejected';
    ok $schema.validate({a => 1, b => 2}), 'Object of minimum properties number rejected';
    ok $schema.validate({a => 1, b => 2, c => 3, d => 4}), 'Object of maximum properties number accepted';
    nok $schema.validate({a => 1, b => 2, c => 3, d => 4, e => 5}), 'Object over maximum properties number rejected';
    nok $schema.validate('string'), 'String instead of array rejected';
    $schema = JSON::Schema.new(schema => {
        type => 'object',
        required => <a b>
    });
    nok $schema.validate({a => 1}), 'Object without required attribute rejected';
    ok $schema.validate({a => 1, b => 2}), 'Object with all required attributes accepted';
    ok $schema.validate({a => 1, b => 2, c => 3}), 'Object that has additional attributes besides required accepted';
}

{
    $schema = JSON::Schema.new(schema => {
        type => 'object',
        properties => {
            id => { type => 'integer' },
            name => { type => 'string' }
        }
    });
    ok $schema.validate({id => 1, name => 'one'}), 'Correct object accepted';
    ok $schema.validate({name => 'one'}), 'Correct object with values not in properties accepted';
    nok $schema.validate({id => 1, name => 2}), 'Object with incorrect schema rejected';
    nok $schema.validate({name => 2}), 'Object with incorrect schema rejected';
}

{
    $schema = JSON::Schema.new(schema => {
        type => 'object',
        patternProperties => {
           '^foo\w+' => { type => 'string' },
            '\w+bar$' => { type => 'number' }
        }
    });
    subtest {
        ok $schema.validate({foo => 1}), 'Property not matched with patternProperties rule is accepted';
        ok $schema.validate({fooo => 'foo'}), 'Property matched with patternProperties is accepted';
        nok $schema.validate({fooo => 1}), 'Property matched with patternProperties is rejected';
        nok $schema.validate({fooo => 1, foobar => 5.5}), 'Properties matched with patternProperties are rejected 1';
        nok $schema.validate({fooo => 1, foobar => 1}), 'Properties matched with patternProperties are rejected 2';
        ok $schema.validate({fooo => 'foo', obar => 5.5}), 'Two patterns are matched';
        nok $schema.validate({fooo => 'foo', obar => 5}), 'Incorrect data for one of many patterns in patternProperties is rejected';
    }, 'patternProperties are matched';
}

done-testing;
