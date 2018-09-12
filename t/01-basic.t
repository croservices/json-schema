use v6;
use Test;
use JSON::Schema;

throws-like { JSON::Schema.new(schema => { type => 42 }) },
    X::JSON::Schema::BadSchema,
    'Having type property be an integer is refused';
throws-like { JSON::Schema.new(schema => { type => 'namber' }) },
    X::JSON::Schema::BadSchema,
    'Having type property be an invalid type is refused';

my $schema;
{
    $schema = JSON::Schema.new(schema => {:type('string')});
    ok $schema.validate('hello'), 'Simple string validation accepts a string';
    nok $schema.validate(42), 'Simple string validation rejects an integer';
    nok $schema.validate(Any), 'Simple string validation rejects a type object';
}

throws-like { JSON::Schema.new(schema => { type => ('string', 1) }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, non-strings are impossible';
throws-like { JSON::Schema.new(schema => { type => ('string', 'string') }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, items must be unique';
throws-like { JSON::Schema.new(schema => { type => ('string', 'namber') }) },
    X::JSON::Schema::BadSchema,
    'When type is described as array, items must be withing allowed type range';

{
    $schema = JSON::Schema.new(schema => { type => ('string', 'integer') });
    ok $schema.validate('hello'), 'Simple string&integer validation accepts a string';
    ok $schema.validate(42), 'Simple string&integer validation accepts an integer';
    nok $schema.validate(666.666), 'Simple string&integer validation rejects a number';
    nok $schema.validate(Any), 'Simple string&integer validation rejects a type object';
}

done-testing;
